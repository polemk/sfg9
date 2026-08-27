# frozen_string_literal: true

module Demo
  module Writers
    # As **cobranças** (`charges`) e os **recibos** (`receipts`) que as compõem.
    #
    # ## Por que este escritor foi escrito antes de a fatia dona fechar
    #
    # A S6 estava em voo quando isto nasceu. O mecanismo é o mesmo dos outros
    # dezessete módulos: `requires` nomeia os models, e enquanto um faltar o
    # escritor **pula com aviso nomeando o model e a fatia** — e passa a gravar
    # sozinho no dia em que a tabela chegar, sem ninguém editar nada. Nada aqui
    # inventa tabela ou coluna: o que não existe, não é escrito.
    #
    # ## `receipts` é a ÚNICA ponte até a operação (D-B11)
    #
    # A migration de 2022 é explícita: *"jamais relacionar cobranças e ops
    # diretamente"*. `charges` não tem coluna de operação e este escritor não
    # inventa uma: ele grava o pacote, grava um recibo por operação encerrada e
    # deixa a cobrança conhecer só os recibos.
    #
    # ## Os sete totais são derivados, e o razão os calcula da mesma lista
    #
    # `Charge#recalculate!` reescreve `value`, os três valores de operação e as
    # três contagens somando os recibos do banco. Aqui eles vêm do razão — da
    # **mesma** lista que produz os recibos —, o que mantém o escritor
    # idempotente (chamar `recalculate!` a cada execução gravaria e a contagem de
    # "atualizados" nunca zeraria). O spec confere que os dois caminhos dão o
    # mesmo número.
    #
    # ## `EST`: parte faturada, parte candidata (27/08/2026)
    #
    # Até aqui **todo recibo emitido era `LIQ`**, os contadores de estruturada
    # dos pacotes ficavam em zero e toda linha da lista de Cobranças dizia
    # `0 est.` — a classe `EST` existia na tabela de preço e em recibo nenhum.
    #
    # A divisão agora é por **estado do pacote** (ver `Ledger::Billing`): os
    # pacotes já emitidos (`done`) levam recibos `EST`; os `editing` e
    # `available` não. As estruturadas que sobram continuam sendo o que
    # `Charges::ReceiptGenerator#candidates` lista, e é isso que a apresentação
    # marca ao vivo dentro de um pacote em edição.
    #
    # O recibo é **polimórfico** (`operation_type` = `RiskOperation` ou
    # `StructuredOperation`), e o índice único é `(project_id, operation_type,
    # operation_id)`: as duas classes convivem sem colidir.
    #
    # ## `remuneration_id` e `operation.receipt_id` — os dois lados do vínculo
    #
    # `Charges::BulkReceiptsService#ensure_receipt!` grava `receipts.operation_id`
    # **e** `operation.receipt_id` na mesma transação (DB-165). O seed faz o
    # mesmo, e não por simetria: `available_for_receipt` é
    # `where(receipt_id: nil)`, então operação já faturada que não aponta de
    # volta continua **listada como candidata** — a mesma operação apareceria
    # duas vezes na tela de recibos, uma como recibo emitido e outra como linha a
    # marcar.
    class Charges < Base
      def self.requires = %w[Charge Receipt RiskOperation StructuredOperation Remuneration]
      def self.owner_slice = 'S6'

      def call
        author = demo_author
        # Os recibos que ESTA execução gravou, por projeto. É contra esta lista
        # que a poda decide o que é geração anterior.
        @written_receipts = Hash.new { |hash, key| hash[key] = [] }

        ledger.charges.each do |charge|
          project = project_for(charge.client)
          next if project.nil?

          # Chave natural: `(project_id, date)`. O razão dá um pacote por mês por
          # cliente, então a data é única dentro do projeto — e `state` fica
          # como atributo, para que reabrir um pacote pela tela não faça o seed
          # criar um segundo.
          record = upsert!(::Charge,
                           find_by: { project_id: project.id, date: charge.date },
                           attributes: charge_attributes(charge, author))

          write_receipts!(record, charge, project, author)
        end

        prune_stale_receipts!
        prune_stale_charges!
      end

      private

      # Os sete totais vêm do razão — da mesma lista que produz os recibos —, e
      # não de `Charge#recalculate!`: chamá-lo a cada execução gravaria, e a
      # contagem de "atualizados" nunca zeraria.
      def charge_attributes(charge, author)
        {
          state: charge.state,
          user_id: author&.id,
          value: charge.value,
          risk_operations_value: charge.risk_operations_value,
          structured_operations_value: charge.structured_operations_value,
          total_operations_value: charge.total_operations_value,
          receipts_count: charge.receipts_count,
          risk_operations_count: charge.risk_operations_count,
          structured_operations_count: charge.structured_operations_count
        }
      end

      # **O seed CONVERGE, não acumula — e sem isto ele acumulava.**
      #
      # A chave natural do pacote é `(project_id, date)`, e a data é **relativa
      # à data-base** (`Billing.charge_date`): o pacote do mês corrente é datado
      # em `min(dia sorteado, data-base)`. Rodar o seed amanhã produz outra data,
      # não reencontra o pacote de hoje e **cria um segundo**. Medido no banco de
      # desenvolvimento: o razão dizia 42 pacotes e a tela de Cobranças mostrava
      # **76**, três gerações empilhadas do mesmo mês.
      #
      # A regra é a mesma do lote de recibos (`BulkReceiptsService`) e da lista
      # de tarifas do borderô (DEC-72): **o razão manda o estado final e o
      # escritor faz o diff**. Pacote de projeto do elenco que não está na
      # lista sai — inclusive nos três projetos de `WITHOUT_CHARGES`, cuja tela
      # vazia é de propósito e não sobrevive a um pacote esquecido.
      #
      # A poda do **recibo** vem primeiro: um recibo de geração anterior pode
      # estar pendurado num pacote que continua válido (mesma data, menos
      # operações), e nesse caso o pacote fica — só o recibo sai.
      def prune_stale_receipts!
        prune!('recibo(s)', method(:destroy_receipt!)) do |project, _client|
          escritos = @written_receipts[project.id]
          scope = ::Receipt.where(project_id: project.id)
          escritos.any? ? scope.where.not(id: escritos) : scope
        end
      end

      # E a poda do **pacote** depois, com os recibos que sobraram nele.
      def prune_stale_charges!
        esperadas = ledger.charges.group_by { |charge| charge.client.slug }

        prune!('pacote(s)', method(:destroy_charge!)) do |project, client|
          datas = (esperadas[client.slug] || []).map(&:date)
          scope = ::Charge.where(project_id: project.id)
          datas.any? ? scope.where.not(date: datas) : scope
        end
      end

      # O laço comum das duas podas: **só projetos do elenco**. Nada fora da
      # lista de clientes do razão é tocado — o seed não é dono do que não
      # escreveu.
      def prune!(label, remover)
        ledger.clients.each do |client|
          project = project_for(client)
          next if project.nil?

          scope = yield(project, client)
          next unless scope.exists?

          io.puts "   ↳ removendo #{scope.count} #{label} de geração anterior em #{client.slug}"
          scope.each { |record| remover.call(record) }
        end
      end

      def destroy_charge!(charge)
        charge.receipts.each { |receipt| destroy_receipt!(receipt) }
        charge.receipts.reset
        charge.destroy!
      end

      # A ordem que a FK cobra (DB-165) e que já custou um 500 na S8: solta o
      # lado da operação primeiro, destrói o recibo depois.
      def destroy_receipt!(receipt)
        receipt.operation&.update!(receipt_id: nil)
        receipt.destroy!
      end

      # Chave natural do recibo: `(project_id, operation_type, operation_id)` — o
      # índice único que garante que **uma operação não é faturada duas vezes**.
      # As duas classes de operação passam pelo MESMO caminho: só mudam a tabela
      # onde a operação é procurada e a classe de tipo com que a remuneração é
      # resolvida. Duplicar o laço por classe seria criar dois lugares onde
      # `temp_id` e `remuneration_id` podem divergir.
      OPERATION_TYPE_BY_KIND = {
        'LIQ' => ['RiskOperation', 'RiskOperationType'],
        'EST' => ['StructuredOperation', 'StructuredOperationType']
      }.freeze

      def write_receipts!(record, charge, project, author)
        remunerations = remunerations_for(project)

        charge.receipts.each do |receipt|
          operation_type, type_class = OPERATION_TYPE_BY_KIND.fetch(receipt.kind)
          operation = operations_for(project, operation_type)[receipt.operation.contract_number]
          # A remuneração do par (classe, tipo) **da operação** — a mesma que o
          # `ReceiptGenerator` usaria. `receipt.fee` já veio dela pelo razão
          # (`Billing.fee_for`), então os dois lados dizem o mesmo número.
          remuneration = remunerations[[type_class, operation&.operation_type_id]]
          next if operation.nil? || remuneration.nil?

          persisted = upsert!(::Receipt,
                              find_by: { project_id: project.id, operation_type: operation_type,
                                         operation_id: operation.id },
                              attributes: receipt_attributes(record, receipt, operation, remuneration, author))

          @written_receipts[project.id] << persisted.id
          link_operation!(operation, persisted)
        end
      end

      # `title` e `remuneration_id` saem da remuneração, como em
      # `Charges::ReceiptGenerator#build_attributes` — e `fee` já veio dela pelo
      # razão. `temp_id` é a identidade estável do candidato
      # (`receipt.rb:68-70`): com `remuneration_id` nulo ela nascia
      # `RCP-<projeto>-LIQ--<operação>`, e a tela não casava o recibo gravado
      # com o candidato que o gerador monta.
      def receipt_attributes(charge_record, receipt, operation, remuneration, author)
        {
          charge_id: charge_record.id,
          user_id: author&.id,
          kind: receipt.kind,
          title: remuneration.title,
          fee: receipt.fee,
          operation_value: receipt.operation_value,
          value: receipt.value,
          date: receipt.date,
          operation_title: operation.title,
          remuneration_id: remuneration.id,
          temp_id: ::Receipt.temp_id_for(project_id: charge_record.project_id, kind: receipt.kind,
                                         remuneration_id: remuneration.id, operation_id: operation.id)
        }
      end

      # O outro lado do vínculo (DB-165), para as DUAS classes — as duas têm
      # `receipt_id`, e `available_for_receipt` é `where(receipt_id: nil)` nas
      # duas: estruturada faturada que não aponta de volta continuaria listada
      # como candidata, e apareceria duas vezes na tela de recibos.
      #
      # **Só grava se mudou**: `RiskOperation` recalcula a cadeia de saldo em
      # todo save (`before_validation :refresh_balance_cache`, BE-265) e
      # `StructuredOperation` reescreve `balance` (golden E6), e um `update!`
      # incondicional aqui custaria centenas de recálculos por execução e nunca
      # deixaria a contagem de "atualizados" zerar.
      def link_operation!(operation, receipt)
        return if receipt.nil? || operation.receipt_id == receipt.id

        operation.update!(receipt_id: receipt.id)
      end

      # `CT-…` para risco, `EST-…` para estruturada: os dois prefixos não se
      # cruzam, mas o índice é por (projeto, classe) mesmo assim — é o que o
      # índice único do banco cobra.
      def operations_for(project, operation_type)
        @operations_for ||= {}
        @operations_for[[project.id, operation_type]] ||=
          operation_class(operation_type).where(project_id: project.id).index_by(&:contract_number)
      end

      def operation_class(operation_type)
        operation_type == 'StructuredOperation' ? ::StructuredOperation : ::RiskOperation
      end

      # Indexada pelo par polimórfico, que é a chave natural da remuneração
      # descontado o projeto — o mesmo trio do índice único (DB-284).
      def remunerations_for(project)
        @remunerations_for ||= {}
        @remunerations_for[project.id] ||=
          ::Remuneration.where(project_id: project.id)
                        .index_by { |r| [r.operation_type_type, r.operation_type_id] }
      end
    end
  end
end
