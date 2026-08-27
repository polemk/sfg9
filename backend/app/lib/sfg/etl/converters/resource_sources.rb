# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `resource_sources` (legado) -> `ResourceSource` (ai9). **Dona: S8**
      # (DB-287, DB-562, BE-308, Q-R19); a TABELA nasceu na S6 por dependência de FK.
      #
      # ## Este é o catálogo que o borderô NÃO PODE PERDER
      #
      # `receivable_entries.resource_source_id` é obrigatório e está preenchido em
      # **28.131 de 28.131** linhas de produção. Se este conversor não rodar antes de
      # `ReceivableEntries`, o de-para não tem a linha, `ref` devolve `nil` e cada
      # borderô vira órfão contado — 28.131 deles. É por isso que a entrada está na
      # ordem de carga **antes** de `Projects`, e não junto da fatia dona.
      #
      # ## 6 linhas, e a divergência com o mapa está registrada
      #
      # Medido no dump de 31/05/2025: **6 linhas**, todas `is_active = 1`, todas com
      # `integration_key` preenchida e distinta. O mapa da S8 previa 7 fontes com
      # outros nomes; produção tem 6. O seed de referência do ai9 já reproduz as 6
      # **com o mesmo `legacy_id`**, que é a chave natural aqui — rodar o conversor
      # sobre a base semeada **ATUALIZA, não duplica**. Sem isso a carga criaria uma
      # segunda "Fomento" e metade dos borderôs apontaria para cada uma. É a mesma
      # nota de idempotência de `Converters::Wallets`.
      #
      # ## A origem tem uma coluna `legacy_id` PRÓPRIA — e ela NÃO é a nossa
      #
      # A tabela do legado carrega um `legacy_id` seu, de uma importação anterior
      # (6 de 6 linhas preenchidas). O `legacy_id` do ai9 é **proveniência nesta
      # migração** (DEC-12) e recebe `resource_sources.id`, como diz o comentário da
      # coluna no `schema.rb`. Copiar o `legacy_id` do legado aqui encadearia duas
      # proveniências diferentes na mesma coluna e o de-para deixaria de fechar.
      class ResourceSources < Base
        def self.source_table = 'resource_sources'
        def self.target_model = 'ResourceSource'
        def self.owner_slice = 'S8'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active]
        # As duas são únicas NO BANCO no ai9 (`index_resource_sources_on_title` e
        # `..._on_integration_key`), e no legado nenhuma das duas tinha índice.
        def self.uniques = [%w[title], %w[integration_key]]

        def convert(row)
          {
            title: row['title'].to_s.strip,
            integration_key: row['integration_key'],
            # Q-R19 — `is_active` é replicada e **não filtra** o select do borderô.
            # A decisão é da S8; o que este conversor faz é carregar o valor como
            # está, sem transformar "inativa" em "ausente".
            is_active: Values.to_boolean(row['is_active']).value,
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
