# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `risk_operation_subtypes` (legado) -> `RiskOperationSubtype` (ai9). **S5.**
      #
      # ### Por que os subtipos vêm do legado, e não do `after_create`
      #
      # É o subtipo que decide o **bucket** de cada operação no painel de exposição
      # (`is_pre = false` → liquidável, `is_pre = true` → pré-faturamento). As
      # `risk_operations` do legado apontam para **estes** ids; gerá-los pelo
      # callback produziria linhas novas, e o de-para não teria a quem religar as
      # operações — todas virariam órfãs contadas.
      #
      # Por isso o conversor de tipos grava **sem callback** (ver o cabeçalho de
      # `RiskOperationTypes`) e o subtipo entra aqui, com o `legacy_id` que amarra
      # o de-para.
      #
      # ### `integration_key` nasce aqui, porque no legado ela é NULA
      #
      # `RiskOperationSubtype` do legado **não tem** `before_validation` derivando a
      # chave (só o tipo e o movimento têm), então a coluna existe e fica vazia. No
      # ai9 o `GlobalCatalog` exige a chave — ela é derivada do título pela mesma
      # regra. Não há contrato a quebrar: nenhuma integração do legado lê a chave do
      # subtipo, porque ela nunca teve valor.
      #
      # ### `is_default_for_type` — DEC-67, reproduzindo o `.first` do legado
      #
      # O legado escolhia o subtipo da operação com
      # `subtypes.where(...).pluck(:id).first`, **sem `order`** — ordem de inserção.
      # A coluna torna a escolha explícita, e o valor carregado tem de reproduzir o
      # que aquele `.first` devolveria: o subtipo de **menor `id` do legado** dentro
      # do tipo. É isso que `#post_load!` faz, depois que as linhas estão gravadas
      # (dentro do lote não dá para saber quem é o menor do tipo inteiro).
      class RiskOperationSubtypes < Base
        def self.source_table = 'risk_operation_subtypes'
        def self.target_model = 'RiskOperationSubtype'
        def self.requires = %w[RiskOperationSubtype RiskOperationType]
        def self.owner_slice = 'S5'

        def self.references = {
          'user_id' => 'livetat_auth_users',
          'risk_operation_type_id' => 'risk_operation_types',
          'pair_id' => 'risk_operation_subtypes'
        }

        def self.booleans = %w[is_active is_default is_pre allow_manual_operations allow_receivable_entries]
        def self.uniques = [%w[risk_operation_type_id is_pre], %w[risk_operation_type_id title]]
        # Derivada na carga, não copiada da origem (a origem é sempre nula).
        def self.derived = %w[integration_key is_default_for_type]

        def convert(row)
          {
            title: row['title'],
            integration_key: row['integration_key'].presence || GlobalCatalog.slugify(row['title']),
            is_active: Values.to_boolean(row['is_active']).value,
            is_default: Values.to_boolean(row['is_default']).value,
            is_pre: Values.to_boolean(row['is_pre']).value,
            allow_manual_operations: Values.to_boolean(row['allow_manual_operations']).value,
            allow_receivable_entries: Values.to_boolean(row['allow_receivable_entries']).value,
            risk_operation_type_id: ref('risk_operation_types', row['risk_operation_type_id']),
            pair_id: ref('risk_operation_subtypes', row['pair_id']),
            # Marcado no `post_load!`: dentro do lote não dá para saber quem é o
            # menor `legacy_id` do tipo inteiro.
            is_default_for_type: false,
            user_id: ref('livetat_auth_users', row['user_id']),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # DEC-67 — marca **um** subtipo padrão por tipo, reproduzindo o que o
        # `.first` sem `order` do legado escolhia: o de menor id na origem.
        #
        # Idempotente: limpa antes de marcar, então rodar de novo não acumula.
        # Devolve a contagem, para o relatório dizer quantos tipos ficaram com
        # padrão — tipo sem nenhum subtipo é anomalia a reportar, não a corrigir.
        def self.post_load!
          return { marked: 0, without_subtype: 0 } unless model_ready?('RiskOperationSubtype')

          RiskOperationSubtype.update_all(is_default_for_type: false)

          marcados = 0
          RiskOperationType.find_each do |tipo|
            escolhido = tipo.subtypes.order(Arel.sql('legacy_id NULLS LAST'), :created_at).first
            next if escolhido.nil?

            escolhido.update_column(:is_default_for_type, true)
            marcados += 1
          end

          { marked: marcados, without_subtype: RiskOperationType.count - marcados }
        end
      end
    end
  end
end
