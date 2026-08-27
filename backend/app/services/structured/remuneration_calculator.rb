# frozen_string_literal: true

module Structured
  # S8 / **BE-305**, **BE-306**, **BE-294**, **OPS-287** — a **única** fórmula de
  # faturamento, e o lugar onde ela é travada por golden.
  #
  # ## Contrato C2: um cálculo, um dono — e este NÃO é o dono
  #
  # A aritmética mora em `Charges::ReceiptGenerator` (S6), porque é ela que
  # `Receipt#fetch` executa na hora de **gravar** o recibo. Esta classe é a
  # **fachada da S8**: acrescenta o que a fórmula não tinha — os erros de
  # negócio com status (BE-294), a paginação dos candidatos (BE-306) e os
  # goldens `E1`…`E5`/`E7` — **sem uma linha de aritmética própria**.
  #
  # Duas implementações divergindo aqui é dinheiro errado, e não é hipótese: o
  # legado tinha `Receipt#fetch` gravando e `Remuneration#receipt_candidates`
  # pré-visualizando, cada uma instanciando o seu `Receipt`. Bastava alguém
  # mexer numa.
  #
  # ## A sequência exata, medida na fonte (`../sfg/app/models/receipt.rb:41-66`)
  #
  # 1. `receipt_id` já preenchido na operação → erro de negócio
  #    *"Já existe um recibo associado a essa operação"*;
  # 2. copia `project_id`, `operation_title` e `date = operation.issue_date`;
  # 3. busca a remuneração por (`project_id`, `operation_type_id`,
  #    `operation_type_type`) — o índice único de `DB-284` garante **uma só**;
  # 4. sem remuneração → erro de negócio *"Não existe remuneração no projeto
  #    para esse tipo de operação"*;
  # 5. **congela** no recibo `kind`, `title`, `fee` e `operation_value`;
  # 6. **`value = operation_value × (fee.to_f / 100.0)`**;
  # 7. `temp_id = "RCP-{project}-{kind}-{remuneração}-{operação}"`.
  #
  # **Sem pro-rata e sem prazo** (T-D8 / Q-R17): nem `agreed_rate`, nem
  # `issue_date`/`due_date`, nem `balance` entram. 2,55% de uma operação de 30
  # dias e de uma de 360 dias dão o **mesmo** valor. O modelo guarda datas e uma
  # `agreed_rate` que *sugerem* um pro-rata que não existe — a sugestão é o
  # motivo de a pergunta ter sido feita, e a resposta é replicar.
  #
  # ## A política de arredondamento passa a ser EXPLÍCITA (tarefa 3.2)
  #
  # No legado ela é **acidental**: o passo 6 é `decimal × Float` e quem arredonda
  # é o cast na gravação da coluna. Aqui ela está escrita —
  # {Charges::ReceiptGenerator::ROUNDING} (`ROUND_HALF_UP`, 2 casas) — e
  # **reproduz** o resultado atual, comprovado pelos cinco goldens. Escrever a
  # política não é mudá-la; é parar de depender de um efeito colateral do
  # adapter do banco para saber quanto o cliente paga.
  #
  # O `E5` é o caso que prova que a aritmética é `float`: o produto exato é
  # `7769.9992229999990000001` — o artefato aparece na **décima** casa — e só
  # existe porque `fee.to_f / 100.0` passa por ponto flutuante. Um golden que
  # some com a troca de `Float` por `BigDecimal` é um golden que estava
  # guardando a coisa certa.
  #
  # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
  #
  # `receipts` e `remunerations` estão entre as **24 migrations que nunca
  # subiram**. Estes goldens travam a **leitura do código de 2022**, não três
  # anos de uso — diferente do borderô da S6, que tem oráculo. A distinção está
  # escrita porque é ela que diz o peso da evidência.
  class RemunerationCalculator
    # Os dois erros de negócio, com o status que cada um passa a devolver.
    #
    # **BE-294** — no legado os dois eram `ArgumentError` levantado de dentro de
    # um `before_validation`, e o controller não os tratava: **500** no meio do
    # fluxo de cobrança, com a tela dizendo "erro inesperado" sobre uma
    # condição de negócio perfeitamente normal.
    #
    # `409` para "já faturada" porque é **conflito de estado** (a operação já
    # tem recibo; nada no pedido está malformado); `422` para "sem remuneração"
    # porque falta um cadastro que o usuário precisa fazer.
    ALREADY_BILLED = 'Já existe um recibo associado a esta operação.'
    NO_REMUNERATION = 'Não existe remuneração cadastrada neste projeto para este tipo de operação.'
    UNKNOWN_OPERATION = 'Tipo de operação desconhecido — não é possível calcular a remuneração.'

    class << self
      include ApiResponseHandler

      # Calcula o recibo de **uma** operação. **Não persiste.**
      #
      # @param operation [RiskOperation, StructuredOperation]
      # @return [Hash] `{ status: 200, data: {...} }` ou `{ status: 409|422, error: String }`
      #
      # O `data` traz `kind`, `title`, `fee`, `operation_value`, `value`,
      # `date`, `operation_title` e `temp_id` — os sete campos que o recibo
      # congela, mais a identidade estável do candidato.
      def calculate(operation)
        return { status: 422, error: UNKNOWN_OPERATION } if operation.nil?

        # Passo 1 — a recusa vem ANTES de qualquer consulta. É a ordem do
        # legado, e ela importa: operação já faturada não deve nem tocar a
        # tabela de remunerações.
        return { status: 409, error: ALREADY_BILLED } if operation.receipt_id.present?

        remuneration = remuneration_for(operation)
        return { status: 422, error: NO_REMUNERATION } if remuneration.nil?

        # Passos 2 a 7 — no dono da aritmética. Aqui não se multiplica nada.
        Charges::ReceiptGenerator.build_attributes(
          operation: operation, remuneration: remuneration, actor: nil
        )
      end

      # A remuneração que cobre esta operação, por (projeto, classe, tipo).
      #
      # `Receipt#fetch` faz `.first` (`receipt.rb:47-51`); aqui é `find_by`, que
      # é o mesmo com o índice único de `DB-284` garantindo que só há uma linha.
      def remuneration_for(operation)
        return nil unless Charges::ReceiptGenerator.remunerations_available?

        tipo = type_class_name_for(operation)
        return nil if tipo.nil?

        ::Remuneration.find_by(project_id: operation.project_id,
                               operation_type_type: tipo,
                               operation_type_id: operation.operation_type_id)
      end

      # **BE-306 — os candidatos a cobrança de um projeto, já calculados.**
      #
      # Para cada remuneração do projeto,
      # `operation_class.where(project_id:, operation_type_id:, receipt_id: nil)`.
      #
      # Três coisas mudam em relação ao legado (`charge.rb:34-46`):
      #
      # - **pagina.** Hoje o laço percorre **todas** as remunerações do projeto
      #   e, dentro de cada uma, **todas** as operações sem recibo, montando a
      #   lista inteira na memória antes de a tela ver a primeira linha;
      # - **`operation_class` nil deixa de dar 500.** No legado
      #   `Remuneration#operation_class` devolvia `nil` para `operation_type_type`
      #   desconhecido e o `nil.where(...)` seguinte derrubava a requisição. O
      #   domínio agora é fechado no banco (`check_constraint`) e na validação,
      #   e ainda assim o serviço pula a linha em vez de explodir — cinto e
      #   suspensório, porque a coluna existe desde antes da constraint;
      # - **nada é instanciado como `Receipt`.** O legado fazia
      #   `Receipt.new(operation:)` por candidato, e o setter disparava o
      #   `fetch` — N consultas por linha da tela.
      #
      # **Golden `E7` (Q-R18): operação ENCERRADA continua candidata.**
      # `is_ended` não entra no predicado — nem aqui, nem no legado. Não é
      # esquecimento meu: é a ausência replicada, e o teste existe para que
      # ninguém "conserte" isso achando que encerrada não deve ser faturada.
      #
      # @param project [Project]
      # @param page [Integer, nil] quando nulo, devolve a relação inteira
      # @return [Hash] `{ status: 200, data: [...] }` ou o 422 nomeando a S8
      def candidates(project, page: nil, per_page: nil)
        Charges::ReceiptGenerator.candidates(project: project, charge: nil, page: page, per_page: per_page)
      end

      private

      # `remuneration.rb:31-36` do lado inverso: dada a operação, qual classe de
      # **tipo** a remuneração dela usa. `Receipt::KIND_BY_OPERATION` já é o
      # de-para operação → sigla; este é operação → classe do tipo, e as duas
      # tabelas vivem juntas de propósito.
      TYPE_CLASS_BY_OPERATION = {
        'RiskOperation' => ::Remuneration::RISK_TYPE,
        'StructuredOperation' => ::Remuneration::STRUCTURED_TYPE
      }.freeze

      def type_class_name_for(operation)
        TYPE_CLASS_BY_OPERATION[operation.class.base_class.name]
      end
    end
  end
end
