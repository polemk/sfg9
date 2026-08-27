# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `structured_operation_types` (legado) -> `StructuredOperationType` (ai9). **S8.**
      #
      # ## ⚠ A TABELA NÃO EXISTE NA ORIGEM DE PRODUÇÃO — DEC-103b
      #
      # `20220701123654_create_structured_operation_types` está entre as **24
      # migrations que nunca subiram**: a última aplicada em produção é de
      # 25/05/2022 e o sistema rodou em uso até 31/05/2025. Conferido no dump: a
      # relação não existe. **Zero linha lida é o resultado esperado.** Os 4 tipos
      # que existem no ai9 vêm de `Seeds::Reference::StructuredOperationTypes`.
      #
      # ## O irmão que este tipo NÃO é
      #
      # `RiskOperationTypes` (S5) tem os mesmos nomes de coluna e dois
      # comportamentos que este **não** tem, e confundi-los custa caro:
      #
      # * lá o `after_create` **gera subtipos**. Aqui não existe subtipo de
      #   operação estruturada — nada a proteger, nada a duplicar;
      # * lá `has_pre_faturamento` decide o **bucket de exposição** de toda
      #   operação do tipo. Aqui a coluna está no `permit` do legado
      #   (`structured_operation_types_controller.rb:135`) **sem formulário e sem
      #   um único leitor** em todo o repositório (Q-R15). Ela viaja como coluna e
      #   **não ganha consumidor**.
      #
      # Os cinco flags são `integer` 0/1 na origem (DB-295) e boolean no destino.
      #
      # ## `integration_key` é CONTRATO, e por isso é copiada
      #
      # `fomento` / `comissaria` / `intercompany` / `auto_liquidavel` — é a chave
      # que `Remuneration` casa e que a integração usa. Rederivá-la por
      # `GlobalCatalog.slugify` produziria a mesma coisa nos quatro casos
      # conhecidos e coisa diferente em qualquer título novo. Copia-se (DEC-85).
      class StructuredOperationTypes < Base
        def self.source_table = 'structured_operation_types'
        def self.target_model = 'StructuredOperationType'
        def self.owner_slice = 'S8'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active is_default allow_manual_operations allow_receivable_entries
                               has_pre_faturamento]
        # BE-297 — a chave é única NO BANCO no ai9. No legado só o título era
        # único: "Auto Liquidável" e "Auto-Liquidável" derivavam a MESMA chave e
        # colidiam em silêncio. Declarada aqui para que a colisão apareça no
        # relatório antes de o índice único recusar a carga no meio.
        def self.uniques = [%w[title], %w[integration_key]]

        def convert(row)
          {
            title: row['title'].to_s.strip,
            integration_key: row['integration_key'].presence || GlobalCatalog.slugify(row['title']),
            is_active: Values.to_boolean(row['is_active']).value,
            is_default: Values.to_boolean(row['is_default']).value,
            allow_manual_operations: Values.to_boolean(row['allow_manual_operations']).value,
            allow_receivable_entries: Values.to_boolean(row['allow_receivable_entries']).value,
            # Q-R15 — coluna sem consumidor, migrada como está e sem ganhar um.
            has_pre_faturamento: Values.to_boolean(row['has_pre_faturamento']).value,
            user_id: ref('livetat_auth_users', row['user_id']),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end
      end
    end
  end
end
