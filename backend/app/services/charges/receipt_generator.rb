# frozen_string_literal: true

module Charges
  # S6 / **BE-188**, **D-B14** — a geração do recibo sobre uma operação.
  #
  # ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
  #
  # `receipts` e `remunerations` **não existem** no banco de produção: as três
  # migrations que as criariam estão entre as 24 que nunca subiram. Espelho de
  # `../sfg/app/models/receipt.rb:41-70` (`fetch`) e `../sfg/app/models/remuneration.rb:25-46`.
  #
  # ## A fórmula do valor faturado — replicada, inclusive o truncamento
  #
  #     self.value = self.operation_value * (self.fee.to_f / 100.0)   # receipt.rb:63
  #
  # `operation_value` é `decimal`, `fee.to_f / 100.0` é **Float**: é
  # `decimal × float`, e o resultado é truncado pela coluna `decimal(15,2)`.
  # **É o número que vai na fatura**, então ele é replicado como está (DEC-02 /
  # D-B14) e travado por golden.
  #
  # A fórmula é percentual **flat, sem prazo** (D-72, Q-B14): 2% de uma operação
  # de 30 dias e 2% de uma de 360 dias dão o mesmo valor. Replicado.
  #
  # ## Duas divergências deliberadas do legado
  #
  # 1. **Tipo de operação desconhecido FALHA.** `Remuneration#beauty_type`
  #    (`remuneration.rb:38-46`) terminava num `else` que devolvia a string
  #    `"???"` — e essa string ia para a coluna `kind`, atravessava a validação
  #    de presença e virava um recibo que nenhum filtro encontrava.
  # 2. **`fetch` não é mais um `before_validation` que levanta `ArgumentError`.**
  #    No legado, gerar recibo para operação já faturada levantava exceção crua
  #    dentro de um callback, e o controller devolvia 500. Aqui é 422 com texto.
  #
  # ## Dependência da S8, declarada
  #
  # `Remuneration` é da **S8**. Enquanto o model não existir, este serviço
  # **para com aviso nomeando a fatia** em vez de explodir — mesmo padrão do
  # motor de ETL (`Sfg::Etl::Converters::Base`). Um serviço que só carrega
  # quando tudo existir é um serviço que ninguém testou.
  class ReceiptGenerator
    # A frase do 422 que **nomeia a fatia que falta**. Fica no corpo da classe,
    # e não dentro do `class << self`: lá ela seria constante da *singleton
    # class* e `Charges::ReceiptGenerator::MISSING_REMUNERATION_MODEL` — que é
    # como `BulkReceiptsService` e o teste a leem — levantaria `NameError`,
    # virando **500** exatamente no caminho que existe para não dar 500.
    MISSING_REMUNERATION_MODEL = 'As remunerações ainda não existem neste ambiente (fatia S8). ' \
                                 'A geração de recibos depende delas.'

    # **S8, tarefa 3.2 — a política de arredondamento deixa de ser acidental.**
    #
    # No legado ninguém arredonda: o passo `operation_value * (fee.to_f / 100.0)`
    # devolve o produto cru — para `99.999,99 × 7,77%` isso é
    # `7769.9992229999990000001`, com o artefato do float na **décima** casa — e
    # quem corta em 2 casas é o **cast da coluna** `decimal(_,2)` na hora do
    # INSERT. Quanto o cliente paga passava a depender de um efeito colateral do
    # adapter do banco.
    #
    # Aqui a regra está escrita: `ROUND_HALF_UP`, 2 casas, aplicada ao **valor
    # final** e só a ele. Ela **reproduz** o que o cast já fazia — os cinco
    # goldens `E1`…`E5` (5.100,00 · 31,48 · 1.533,95 · **255,01** na fronteira ·
    # **7.770,00** no artefato) passam antes e depois, e foram conferidos
    # executando a mesma aritmética Ruby do legado.
    #
    # O que muda de verdade é a **prévia**: antes ela mostrava `31,48128` na
    # tela e gravava `31,48`, e agora mostra o que vai ser cobrado. A sequência
    # de cálculo (DEC-02) é a mesma, coluna por coluna.
    ROUNDING_SCALE = 2
    ROUNDING_MODE = BigDecimal::ROUND_HALF_UP

    # O ÚNICO lugar que arredonda. `Structured::RemunerationCalculator` (S8) é
    # fachada e não tem aritmética própria — contrato C2.
    def self.round_value(raw)
      raw.to_d.round(ROUNDING_SCALE, ROUNDING_MODE)
    end

    class << self
      include ApiResponseHandler

      def remunerations_available?
        Object.const_defined?('Remuneration') &&
          Object.const_get('Remuneration').respond_to?(:table_exists?) &&
          Object.const_get('Remuneration').table_exists?
      rescue StandardError
        false
      end

      # Os candidatos a recibo de um projeto: toda operação **sem recibo** cujo
      # tipo tem remuneração cadastrada, mais os recibos já vinculados à
      # cobrança. `../sfg/app/models/charge.rb:34-46`.
      #
      # O legado montava isto com um laço de `Remuneration` chamando
      # `receipt_candidates`, que instanciava um `Receipt` por operação **e
      # disparava o `fetch` em cada um** — N consultas por candidato. Aqui os
      # candidatos são estruturas simples; nada é instanciado como AR.
      # **S8 / BE-306 — agora pagina.**
      #
      # O legado (`charge.rb:34-46`) percorre TODAS as remunerações do projeto e,
      # dentro de cada uma, TODAS as operações sem recibo, montando a lista
      # inteira antes de a tela ver a primeira linha.
      #
      # A paginação é de **array**, e não de relação, porque os candidatos vêm
      # de **duas tabelas diferentes** (`risk_operations` e
      # `structured_operations`) e são ordenados pela data já materializada —
      # não existe um `ORDER BY` que atravesse as duas. `Kaminari.paginate_array`
      # é o mecanismo previsto pelo DEC-62 exatamente para este caso, e o
      # envelope de cabeçalho continua o mesmo.
      #
      # **`page: nil` devolve a lista inteira**, que é o que a gravação em lote
      # (`BulkReceiptsService`) precisa: paginar ali mudaria o resultado do
      # faturamento, e otimização não pode mudar linha devolvida.
      def candidates(project:, charge: nil, page: nil, per_page: nil)
        return { status: 422, error: MISSING_REMUNERATION_MODEL } unless remunerations_available?

        remuneracoes = Object.const_get('Remuneration').where(project_id: project.id).to_a
        lista = remuneracoes.flat_map { |r| candidates_for(project, r) }
        lista += charge.receipts.map { |r| existing_candidate(r) } if charge

        ordenada = lista.sort_by { |c| c[:date] || Date.new(1900, 1, 1) }.reverse
        return { status: 200, data: ordenada } if page.nil?

        { status: 200, data: Kaminari.paginate_array(ordenada).page(page).per(per_page) }
      end

      # Monta (sem gravar) o recibo de uma operação. Devolve o Hash de
      # atributos ou um erro de negócio.
      def build_attributes(operation:, remuneration:, actor:)
        kind = Receipt.kind_for_operation_type(operation.class.name)
        if kind.nil?
          return { status: 422,
                   error: "Tipo de operação desconhecido: #{operation.class.name}. " \
                          'Não é possível gerar recibo.' }
        end
        if operation.receipt_id.present?
          return { status: 422, error: 'Já existe um recibo associado a esta operação.' }
        end

        fee = remuneration.value
        operation_value = operation.operation_value

        {
          status: 200,
          data: {
            project_id: operation.project_id,
            operation_id: operation.id,
            operation_type: operation.class.name,
            remuneration_id: remuneration.id,
            kind: kind,
            title: remuneration.title,
            fee: fee,
            operation_value: operation_value,
            # D-B14 — `decimal × float`, a sequência do legado, com o
            # arredondamento agora EXPLÍCITO (ver `ROUNDING_SCALE`). É a receita.
            value: round_value(operation_value * (fee.to_f / 100.0)),
            date: operation.try(:issue_date),
            operation_title: operation.title,
            user_id: actor&.id,
            temp_id: Receipt.temp_id_for(project_id: operation.project_id, kind: kind,
                                         remuneration_id: remuneration.id, operation_id: operation.id)
          }
        }
      end

      private

      def candidates_for(project, remuneration)
        klass = operation_class_for(remuneration)
        return [] if klass.nil?

        klass.where(project_id: project.id,
                    operation_type_id: remuneration.operation_type_id,
                    receipt_id: nil).map do |op|
          kind = Receipt.kind_for_operation_type(klass.name)
          {
            temp_id: Receipt.temp_id_for(project_id: project.id, kind: kind,
                                         remuneration_id: remuneration.id, operation_id: op.id),
            id: nil, operation_id: op.id, operation_type: klass.name,
            remuneration_id: remuneration.id, kind: kind, title: remuneration.title,
            fee: remuneration.value, operation_value: op.operation_value,
            value: round_value(op.operation_value * (remuneration.value.to_f / 100.0)),
            date: op.try(:issue_date), operation_title: op.title, persisted: false
          }
        end
      end

      def existing_candidate(receipt)
        {
          temp_id: receipt.temp_id, id: receipt.id, operation_id: receipt.operation_id,
          operation_type: receipt.operation_type, remuneration_id: receipt.remuneration_id,
          kind: receipt.kind, title: receipt.title, fee: receipt.fee,
          operation_value: receipt.operation_value, value: receipt.value,
          date: receipt.date, operation_title: receipt.operation_title, persisted: true
        }
      end

      # `remuneration.rb:31-36`, sem o `nil` silencioso do `else`.
      def operation_class_for(remuneration)
        case remuneration.operation_type_type.to_s
        when 'RiskOperationType' then RiskOperation
        when 'StructuredOperationType'
          Object.const_defined?('StructuredOperation') ? Object.const_get('StructuredOperation') : nil
        end
      end
    end
  end
end
