# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `structured_operations` (legado) -> `StructuredOperation` (ai9). **S8.**
      #
      # ## ⚠ A TABELA NÃO EXISTE NA ORIGEM DE PRODUÇÃO — DEC-103b
      #
      # `20220701125757_create_structured_operations` está entre as **24
      # migrations que nunca subiram**. Conferido no dump de 31/05/2025: a
      # relação não existe, e o tipo dela (`structured_operation_types`) também
      # não. **A operação estruturada nunca rodou em produção.** Zero linha lida
      # é o resultado esperado.
      #
      # ## As três convenções do legado que são REPLICADAS, e nenhuma delas é bug
      #
      # **1. `original_balance` é gravado NEGATIVO** — `(-1) * abs`
      # (`../sfg/app/models/structured_operation.rb:37`). É convenção de sinal, e
      # a DEC-01 mandou replicar. O conversor copia o valor da origem **como
      # está** (ele já vem negativo de lá) e o `reset_balance_from_original` do
      # ai9 reaplica a mesma regra na gravação — os dois concordam por
      # construção. Declarado em `derived` porque quem produz o valor final é o
      # model, não o `convert`.
      #
      # **2. `balance` é RESETADO para `original_balance` em todo save**, inclusive
      # editando só a observação (`structured_operation.rb:38`, sem `on:`). Nada
      # no legado inteiro dá baixa nele: a coluna é **decorativa** (T-D6/BE-292),
      # e o golden E7 trava isso. Copiar o `balance` da origem seria fingir que
      # ele significa alguma coisa.
      #
      # **3. `agreed_rate` NÃO é a taxa que remunera.** Quem remunera é
      # `remunerations.value` (BE-295, Q-R14). A coluna é persistida e exibida,
      # sem consumidor de cálculo. Viaja como está e não ganha um.
      #
      # ## `user_id` da origem é AMBÍGUO, e a coluna nova existe por causa disso
      #
      # DB-297: no legado `current_user.id` era forçado **no create E no update**,
      # então o "autor" virava o **último editor**. O ai9 separa `user_id`
      # (autor) de `updated_by_id` (último editor).
      #
      # A origem sabe **um** valor, e não sabe qual dos dois ele é. Ele entra em
      # `user_id`, que é a coluna de onde veio, e `updated_by_id` fica **NULO** —
      # afirmar que o autor foi o último a editar refaria a confusão que a
      # segunda coluna existe para desfazer. É a mesma família do Q-B19 em
      # `receivable_entries`: o autor registrado pode não ser quem lançou, e o
      # honesto é dizer isso em vez de espalhar o valor.
      #
      # ## `contract_number` SEM unicidade, `due_date` SEM piso — ausências replicadas
      #
      # O legado não tem nenhuma das duas validações (Q-R7/BE-293), e replicar a
      # ausência é a decisão. Não há `uniques` declarada aqui de propósito:
      # declará-la faria o motor bloquear a carga por duplicatas que são
      # legítimas na origem.
      class StructuredOperations < Base
        def self.source_table = 'structured_operations'
        def self.target_model = 'StructuredOperation'
        def self.requires = %w[StructuredOperation StructuredOperationType Company Carrier Project]
        def self.owner_slice = 'S8'

        def self.references = {
          'user_id' => 'livetat_auth_users',
          'operation_type_id' => 'structured_operation_types',
          'project_id' => 'projects',
          'company_id' => 'companies',
          'carrier_id' => 'carriers',
          'receipt_id' => 'receipts'
        }

        def self.booleans = %w[is_on_variable is_ended]
        def self.sums = %w[operation_value original_balance balance]
        def self.year_column = 'issue_date'
        # As três que o model produz em todo save: `project_id` sai de
        # `company.project_id`, e `original_balance`/`balance` saem do
        # `reset_balance_from_original`. Comparar literalmente acusaria
        # divergência em toda linha — ruído que esconde a divergência de verdade.
        def self.derived = %w[project_id original_balance balance]

        def convert(row)
          {
            title: row['title'],
            # DB-297 — ver o bloco acima: o valor da origem é ambíguo e NÃO é
            # copiado para as duas colunas.
            user_id: ref('livetat_auth_users', row['user_id']),
            updated_by_id: nil,
            operation_type_id: ref('structured_operation_types', row['operation_type_id']),
            project_id: ref('projects', row['project_id']),
            company_id: ref('companies', row['company_id']),
            carrier_id: ref('carriers', row['carrier_id']),
            receipt_id: ref('receipts', row['receipt_id']),
            contract_number: row['contract_number'],
            issue_date: row['issue_date'],
            due_date: row['due_date'],
            operation_value: Values.to_decimal(row['operation_value']),
            # DEC-01 — a convenção de sinal do legado, copiada. O model reaplica
            # a mesma regra na gravação.
            original_balance: Values.to_decimal(row['original_balance']),
            # T-D6/BE-292 — decorativa: o model a reseta para `original_balance`
            # em todo save, e nada no legado dá baixa nela.
            balance: Values.to_decimal(row['balance']),
            # BE-295/Q-R14 — persistida e exibida, sem consumidor de cálculo.
            agreed_rate: Values.to_float(row['agreed_rate']),
            observation: row['observation'],
            is_on_variable: Values.to_boolean(row['is_on_variable']).value,
            is_ended: Values.to_boolean(row['is_ended']).value,
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # `project_id` é DERIVADO de `company.project_id` em todo save
        # (`structured_operation.rb:36`), e o do corpo é ignorado. Se a origem
        # trouxer os dois discordando, o valor gravado será o da empresa — e a
        # divergência precisa aparecer no relatório, não sumir na conversão.
        def anomalies(row)
          projeto_da_empresa = empresas[row['company_id'].to_i]
          return [] if projeto_da_empresa.nil? || row['project_id'].blank?
          return [] if projeto_da_empresa.to_i == row['project_id'].to_i

          [{ key: 'structured_operations:project_disagrees_with_company',
             title: 'Operação cujo `project_id` NÃO é o da empresa — o ai9 deriva o projeto da ' \
                    'empresa em todo save (C1), então o valor da origem é DESCARTADO',
             line: "- pk=#{row['id']} origem diz projeto=#{row['project_id']}, " \
                   "empresa #{row['company_id']} é do projeto #{projeto_da_empresa}" }]
        end

        private

        # `id da empresa => id do projeto`, montado uma vez sobre a ORIGEM.
        def empresas
          @empresas ||= begin
            tabela = 'companies'
            if source.table?(tabela)
              source.ordered_rows(tabela).to_h { |r| [r['id'].to_i, r['project_id']] }
            else
              {}
            end
          end
        end
      end
    end
  end
end
