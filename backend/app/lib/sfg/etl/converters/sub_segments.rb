# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `sub_segments` (legado) -> `SubSegment` (ai9). **S4.**
      #
      # Catálogo GLOBAL, mesmo molde de `Segments` — e é de propósito que os dois
      # conversores sejam quase idênticos: **DC-13, não há associação entre eles.**
      # Apesar do nome, o legado nunca ligou subsegmento a segmento; são duas listas
      # planas e `projects` aponta para cada uma por uma coluna própria. Quem for
      # "consertar" a hierarquia aqui vai precisar inventar o mapeamento dos 20
      # registros existentes — e inventar mapeamento é o que esta migração não faz.
      #
      # ## O `strip` do título não é cosmético
      #
      # Medido no dump de 31/05/2025: **2 dos 20 títulos têm espaço sobrando**. O
      # `normalize_catalog_title` do `GlobalCatalog` faria o `strip` de qualquer
      # jeito na gravação; fazê-lo aqui é o que deixa a **reconciliação comparar o
      # que de fato foi gravado** em vez de acusar divergência nas duas linhas.
      # Mesmo motivo do `strip` em `Converters::Wallets`.
      #
      # ## A chave de integração é COPIADA, nunca rederivada
      #
      # As 20 linhas têm `integration_key` preenchida e as 20 chaves são distintas.
      # Rederivar por `GlobalCatalog.slugify` produziria chaves diferentes das que o
      # legado publicou — é chave de **integração**, e recalculá-la em silêncio
      # quebra consumidor externo (mesma leitura conservadora do DEC-85).
      class SubSegments < Base
        def self.source_table = 'sub_segments'
        def self.target_model = 'SubSegment'
        def self.owner_slice = 'S4'
        def self.references = { 'user_id' => 'livetat_auth_users' }
        def self.booleans = %w[is_active]
        # `title` é único NO BANCO no ai9 (`index_sub_segments_on_title`); no legado
        # era só validação de aplicação. A `integration_key` tem índice **não**
        # único no destino, mas entra aqui para que uma repetição futura apareça no
        # relatório antes de virar duas linhas com a mesma chave publicada.
        def self.uniques = [%w[title], %w[integration_key]]

        def convert(row)
          {
            title: row['title'].to_s.strip,
            integration_key: row['integration_key'],
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
