# frozen_string_literal: true

module Demo
  module Writers
    # As operações de risco. Chave natural: `(project_id, contract_number)`.
    #
    # `original_balance` e `balance` vão **negativos** — é a convenção de sinal do
    # legado, que a **DEC-01** mandou replicar exatamente, incluindo o `* -1` de
    # `limite_utilizado_on` na tela. Gravar positivo aqui daria números "mais
    # bonitos" e diferentes dos do legado, que é o que a decisão proíbe.
    #
    # `is_static` substitui os sentinelas de ±2000 anos (`DateTime.dinosaurs` /
    # `mars`) que o legado usava para dizer "sem vencimento". Nenhuma operação
    # deste seed é estática, mas a coluna é preenchida explicitamente para o
    # padrão nascer certo.
    class RiskOperations < Base
      def self.requires = %w[RiskOperation RiskControl]
      def self.owner_slice = 'S7'

      def call
        controls = index_controls
        subtypes = liquidable_subtypes
        # **O autor é obrigatório desde a S7** (`validates :user_id, presence:
        # true, unless: :is_static?`, `risk_operation.rb:114`) — no ai9 ele vem
        # sempre da sessão. Aqui é o Admin do elenco. Sem isto o escritor inteiro
        # falha e as 933 operações somem do banco de demonstração, que foi
        # exatamente o que a suíte pegou no dia em que a validação chegou.
        author_id = demo_author&.id

        ledger.operations.each do |operation|
          project = project_for(operation.client)
          company = companies_by_key[operation.company.key]
          carrier = carrier_for(operation.carrier)
          control = controls[operation.control.key]
          # **Sem limite não há operação.** `risk_control_id` é `null: false` na
          # S5 pelo motivo escrito na própria coluna — operação sem limite é
          # exposição sem teto —, e `operation_type_id` sai do limite, nunca de
          # uma escolha deste escritor: a modalidade da operação É a do limite
          # que ela consome.
          next if project.nil? || company.nil? || carrier.nil? || control.nil?

          upsert!(::RiskOperation,
                  find_by: { project_id: project.id, contract_number: operation.contract_number },
                  attributes: {
                    company_id: company.id,
                    carrier_id: carrier.id,
                    risk_control_id: control.id,
                    operation_type_id: control.risk_operation_type_id,
                    # O subtipo liquidável (`is_pre: false`): a operação de
                    # borderô/manual é a antecipação, nunca o pré-faturamento —
                    # o "pré" é o par estático que o próprio limite abre (BE-241).
                    operation_subtype_id: subtypes[control.risk_operation_type_id]&.id,
                    title: "#{operation.contract_number} — #{operation.carrier.title}",
                    operation_value: operation.operation_value,
                    agreed_rate: operation.agreed_rate,
                    original_balance: -operation.operation_value,
                    # **`balance` NÃO é escrito**, e isso é o contrário de um
                    # esquecimento. Desde a S7 ele é um **cache derivado do
                    # model**: `before_validation :refresh_balance_cache` chama
                    # `Risk::Calculator.recalculate_chain` em TODO save
                    # (`risk_operation.rb:94`, BE-265). Propor aqui o saldo do
                    # razão faz o escritor oferecer, em toda execução, um número
                    # que o model reescreve um instante depois — "855
                    # atualizados" para sempre, sem nada ter mudado. É a mesma
                    # armadilha do `subordinated_accounts_percent` do carrier e
                    # do título normalizado do indicador.
                    #
                    # A cadeia continua fechando: a aritmética do razão e a do
                    # `Risk::Calculator` produzem o mesmo saldo, e é o spec das 7
                    # regras que trava a fórmula do razão.
                    issue_date: operation.issue_date,
                    due_date: operation.due_date,
                    is_static: false,
                    is_ended: operation.state == :ended,
                    is_on_variable: false,
                    user_id: author_id,
                    observation: nil
                  })
        end

        prune_stale_operations!
        recalculate_with_service!
      end

      private

      # **O seed CONVERGE, não acumula.** Mesmo contrato de `writers/charges.rb`:
      # o razão manda o estado final e o escritor faz o diff.
      #
      # Nasceu de uma sobra concreta: o mecanismo antigo de estresse de limite
      # criava uma operação de reforço por controle marcado, e ao trocá-lo pelo
      # plano de utilização a operação da geração anterior **continuou no banco**,
      # somando exposição num limite que ninguém mais planejava. Número de
      # exposição que não sai de nenhuma linha do razão é o pior tipo de sobra:
      # ele parece dado.
      #
      # **`is_static` fica de fora**, e não por descuido: o par estático é criado
      # pelo `after_create` do próprio `RiskControl` (`Risk::StaticPairService`),
      # não pelo seed. Apagá-lo seria o seed removendo o que a fatia dona cria.
      def prune_stale_operations!
        esperados = ledger.operations
                          .group_by { |o| o.client.slug }
                          .transform_values { |lista| lista.map(&:contract_number) }

        ledger.clients.each do |client|
          project = project_for(client)
          next if project.nil?

          scope = ::RiskOperation.where(project_id: project.id, is_static: false)
                                 .where.not(contract_number: esperados[client.slug] || [''])
          next unless scope.exists?

          # **A mensagem conta o que SAIU, não o que foi tentado.** Ela dizia
          # "removendo 29" e removia 14: as outras 15 tinham recibo emitido e o
          # `destroy_operation!` as devolvia intactas, em silêncio. Mensagem de
          # seed que exagera é pior do que nenhuma — foi preciso ler o banco
          # para descobrir que a poda não tinha terminado.
          removidas = 0
          mantidas = 0
          scope.each { |operation| destroy_operation!(operation) ? removidas += 1 : mantidas += 1 }

          io.puts "   ↳ removidas #{removidas} operação(ões) de geração anterior em #{client.slug}"
          next unless mantidas.positive?

          # Isto acontece quando o plano de utilização muda: a operação da
          # geração anterior já foi faturada, e quem solta `receipt_id` é o
          # escritor de cobranças — que roda DEPOIS deste. Não é erro: é a
          # ordem de dependência. A execução seguinte as remove, e é por isso
          # que trocar o plano exige **duas** passadas para convergir.
          io.puts "     · #{mantidas} ficaram por terem recibo emitido; saem na próxima execução " \
                  '(o escritor de cobranças solta o vínculo depois desta etapa)'
        end
      end

      # `movements` cai por `dependent: :destroy`; o recibo, não — ele é
      # `restrict_with_error` do lado da operação e tem FK de volta. Operação com
      # recibo emitido **não** é apagada aqui: se ela sobrou e está faturada, é
      # caso para olhar, não para varrer.
      # Devolve `true` quando removeu — é o que a mensagem acima conta.
      def destroy_operation!(operation)
        return false if operation.receipt_id.present?

        operation.destroy!
        true
      end

      # Um subtipo liquidável por tipo. Nos tipos sem pré-faturamento é o único
      # subtipo; nos com, é a metade "antecipação".
      def liquidable_subtypes
        return {} unless defined?(::RiskOperationSubtype)

        ::RiskOperationSubtype.where(is_pre: false).index_by(&:risk_operation_type_id)
      end

      # O controle é resolvido pelo mesmo trio que o identifica no banco.
      def index_controls
        return {} unless defined?(::RiskControl)

        types = defined?(::RiskOperationType) ? ::RiskOperationType.all.index_by(&:integration_key) : {}

        ledger.controls.each_with_object({}) do |control, acc|
          company = companies_by_key[control.company.key]
          carrier = carrier_for(control.carrier)
          type = types[control.modality.to_s]
          next if company.nil? || carrier.nil? || type.nil?

          record = ::RiskControl.find_by(company_id: company.id, carrier_id: carrier.id,
                                         risk_operation_type_id: type.id)
          acc[control.key] = record if record
        end
      end

      # `demo-seed-design.md` §7: onde o app tiver serviço próprio de cálculo, **o
      # seed chama o serviço** em vez de escrever o número final — assim o dado da
      # demo nasce pelo mesmo caminho do dado real. O serviço é da S7; enquanto
      # não existir, o razão é a fonte, e a spec das 7 regras é o que garante que
      # ele não desviou da fórmula.
      def recalculate_with_service!
        return unless defined?(::Risk::BalanceCalculator)
        return unless ::Risk::BalanceCalculator.respond_to?(:recalculate_all!)

        io.puts '   ↳ recalculando saldos pelo serviço da S7 (Risk::BalanceCalculator)'
        ::Risk::BalanceCalculator.recalculate_all!
      end
    end
  end
end
