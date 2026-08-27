# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `risk_operation_extensions` (legado) -> `RiskOperationExtension` (ai9).
      # Esquema da **S5** (DB-237); o comportamento é da **S7**.
      #
      # ## ⚠ A TABELA NÃO EXISTE NA ORIGEM DE PRODUÇÃO — DEC-103b
      #
      # Conferido no dump de 31/05/2025: a relação não existe. É mais uma das 24
      # migrations que nunca subiram — e a prorrogação de vencimento, portanto,
      # **nunca rodou em produção**. Zero linha lida é o resultado esperado.
      #
      # ==========================================================================
      # ⚠⚠ ESTE CONVERSOR DECLARA ANOMALIA EM **TODA** LINHA QUE LER, E É DE PROPÓSITO
      # ==========================================================================
      #
      # `RiskOperationExtension` do ai9 tem dois callbacks que **reescrevem dado
      # da origem** quando o registro é criado — e uma carga é uma criação:
      #
      #  1. `before_validation :stamp_original_due_date, on: :create` faz
      #     `self.original_due_date = operation&.due_date`. Ou seja: o
      #     `original_due_date` que veio do legado é **descartado** e trocado
      #     pelo vencimento que a operação tem AGORA. Como `RiskOperations` já
      #     carrega o vencimento FINAL (depois de todas as prorrogações), o valor
      #     gravado seria a data final em todas as linhas — e o histórico de
      #     "de que data para que data" desapareceria;
      #
      #  2. `after_create :push_operation_due_date!` pega a operação e faz
      #     `operation.due_date = new_due_date; operation.save!`. Isto **reescreve
      #     a `risk_operations`** durante a carga da extensão, disparando os
      #     callbacks daquele model por cima de dado já reconciliado.
      #
      # Os dois são o comportamento **certo** para uma prorrogação lançada por
      # gente na tela (é o que `../sfg/app/models/risk_operation_extension.rb:5-11`
      # fazia, e a S7 portou fielmente). Os dois são **errados** para uma carga,
      # que não está lançando prorrogação nenhuma: está recontando as que já
      # aconteceram.
      #
      # Como não existe linha em produção, **nada disso acontece hoje**. E como o
      # ETL não pode depender de continuar assim, o conversor **declara**: se a
      # tabela aparecer com dado, `custom:risk_operation_extensions` sobe com uma
      # linha por registro e o dry-run **aborta**. Quem for assinar precisa
      # resolver primeiro o caminho de carga (o model aceitar valores da origem
      # sem os dois callbacks, ou o registro entrar por outro caminho) — e não
      # apenas autorizar a contagem. **Está declarado, não contornado.**
      #
      # ## O CHECK do banco que o legado só tinha no datepicker
      #
      # `new_due_date > original_due_date`, com `check_constraint`. No legado a
      # regra vivia no seletor de data da tela: um POST direto passava. Linha que
      # não avança é declarada em separado, porque o banco a recusaria e a causa
      # seria difícil de ler no meio de uma carga.
      #
      # ## Não há `update` exposto, e por isso não há o que reconciliar depois
      #
      # Corrigir uma prorrogação é lançar outra — que é o que preserva a contagem
      # da coluna "Prorrogações" na lista de operações.
      class RiskOperationExtensions < Base
        def self.source_table = 'risk_operation_extensions'
        def self.target_model = 'RiskOperationExtension'
        def self.requires = %w[RiskOperationExtension RiskOperation]
        def self.owner_slice = 'S7'
        def self.references = { 'risk_operation_id' => 'risk_operations',
                                'user_id' => 'livetat_auth_users' }
        # `original_due_date` é reescrita pelo `before_validation` do model — ver
        # o bloco acima. Declarada aqui para a reconciliação não acusar
        # divergência em toda linha e esconder a de verdade.
        def self.derived = %w[original_due_date]

        def convert(row)
          {
            risk_operation_id: ref('risk_operations', row['risk_operation_id']),
            user_id: ref('livetat_auth_users', row['user_id']),
            # Atribuída mesmo sabendo que o model a sobrescreve: o valor da
            # ORIGEM é o que o relatório compara, e é ele que diz o que se perdeu.
            original_due_date: row['original_due_date'],
            new_due_date: row['new_due_date'],
            observation: row['observation'],
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        def anomalies(row)
          linhas = []

          # Uma por linha lida. Ver o bloco do topo — é o aviso de que carregar
          # esta tabela HOJE perde o `original_due_date` e reescreve a operação.
          linhas << { key: 'risk_operation_extensions:model_rewrites_source',
                      title: 'Prorrogação lida numa tabela que o ai9 só sabe CRIAR: ' \
                             '`stamp_original_due_date` descarta o `original_due_date` da origem e ' \
                             '`push_operation_due_date!` reescreve a `risk_operations`. ' \
                             'A carga precisa de caminho próprio ANTES de ser autorizada',
                      line: "- pk=#{row['id']} operação=#{row['risk_operation_id']} " \
                            "#{row['original_due_date']} -> #{row['new_due_date']}" }

          if row['original_due_date'].present? && row['new_due_date'].present? && !avanca?(row)
            linhas << { key: 'risk_operation_extensions:not_moving_forward',
                        title: 'Prorrogação que NÃO avança a data — o ai9 tem `check_constraint` ' \
                               '(`new_due_date > original_due_date`); o legado só tinha o datepicker',
                        line: "- pk=#{row['id']} #{row['original_due_date']} -> #{row['new_due_date']}" }
          end

          linhas
        end

        private

        def avanca?(row)
          nova = to_date(row['new_due_date'])
          antiga = to_date(row['original_due_date'])
          return true if nova.nil? || antiga.nil?

          nova > antiga
        end

        def to_date(valor)
          return valor if valor.is_a?(Date)
          return valor.to_date if valor.respond_to?(:to_date) && !valor.is_a?(String)

          Date.parse(valor.to_s)
        rescue ArgumentError, TypeError
          nil
        end
      end
    end
  end
end
