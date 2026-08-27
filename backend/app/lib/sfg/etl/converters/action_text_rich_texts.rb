# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `action_text_rich_texts` (legado) -> `action_text_rich_texts` (ai9) — tarefa F.3,
      # fecha **DB-598**, **DB-736** e **DB-737**.
      #
      # ==========================================================================
      # ESTA TABELA É FONTE, NÃO INFRAESTRUTURA A IGNORAR.
      # ==========================================================================
      #
      # É a **única** tabela do legado que o ai9 já tem pronta e que mesmo assim
      # precisa de conversor. As outras duas da mesma família (`active_storage_blobs`
      # e `active_storage_attachments`) têm **0 linha** em produção — medido —, porque
      # o legado guarda binário em **Paperclip** sob `public/system/`. Esta tem 512.
      #
      # **O risco que ela cria é de perda silenciosa.** O corpo de texto rico não mora
      # numa coluna da tabela dona: `Contract#description`, `HelpItem#description` e
      # `Indicator#description` são `has_rich_text`. Carregar `indicators` sem carregar
      # esta tabela junto perde 485 descrições **e não deixa rastro** — não existe
      # coluna vazia para alguém notar.
      #
      # Distribuição medida no dump de produção de 31/05/2025:
      #
      #   | dono       | nome          | linhas |
      #   | ---------- | ------------- | -----: |
      #   | `Indicator`| `description` |    485 |
      #   | `HelpItem` | `description` |     25 |
      #   | `Contract` | `description` |      2 |
      #
      # 48.721 bytes de corpo no total, e **nenhum** deles percent-encoded (a única
      # ocorrência de `%XX` no acervo é o texto literal `%DE PARTICIPAÇÃO`, no
      # indicador 288). A suspeita registrada em `db/etl/load_order.yml` — de que os
      # corpos pudessem estar URL-escapados como as views de contrato sugerem — **não
      # se confirmou contra o dump real.** O corpo viaja como está.
      #
      # **O religamento é polimórfico e sai do de-para**, nunca do id numérico: o
      # `record_id` do legado é `integer` e o do ai9 é `uuid`.
      class ActionTextRichTexts < Base
        # `record_type` do legado => tabela de origem cujo de-para resolve o dono.
        # Fora desta tabela **nada é convertido**: um dono desconhecido vira anomalia,
        # não um `record_id` inventado.
        OWNERS = {
          'Indicator' => { table: 'indicators', model: 'Indicator', slice: 'S10' },
          'HelpItem' => { table: 'help_items', model: 'HelpItem', slice: 'S12' },
          'Contract' => { table: 'contracts', model: 'Contract', slice: 'S12' }
        }.freeze

        def self.source_table = 'action_text_rich_texts'
        def self.target_model = 'ActionText::RichText'
        def self.requires = ['ActionText::RichText']
        def self.owner_slice = 'S14 (a tabela já existe na base ai9)'
        def self.uniques = [%w[record_type record_id name]]

        # `record_id` é polimórfico: o motor não consegue contar órfão por ele, porque
        # a tabela apontada muda linha a linha. A conferência vive em `anomalies`.
        def self.references = {}

        def convert(row)
          owner = OWNERS[row['record_type'].to_s]
          {
            name: row['name'],
            body: row['body'],
            record_type: owner&.fetch(:model),
            record_id: owner && ref(owner.fetch(:table), row['record_id']),
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # Sem `legacy_id` na tabela (ela é do framework): a chave natural é o próprio
        # trio polimórfico, que já é único no legado e no ai9.
        def natural_key(row)
          owner = OWNERS[row['record_type'].to_s]
          { record_type: owner&.fetch(:model), record_id: owner && ref(owner.fetch(:table), row['record_id']),
            name: row['name'] }
        end

        def anomalies(row)
          linhas = []
          tipo = row['record_type'].to_s
          owner = OWNERS[tipo]

          if owner.nil?
            linhas << { key: 'action_text:unknown_owner',
                        title: 'Texto rico de um dono que o ai9 não conhece — NÃO é convertido',
                        line: "- pk=#{row['id']} `record_type` = #{tipo.inspect}, `name` = #{row['name'].inspect}" }
            return linhas
          end

          if ref(owner.fetch(:table), row['record_id']).nil?
            linhas << { key: 'action_text:owner_not_loaded',
                        title: 'Texto rico cujo DONO ainda não está no de-para — carregue ' \
                               "`#{owner.fetch(:table)}` antes (fatia #{owner.fetch(:slice)})",
                        line: "- pk=#{row['id']} #{tipo}##{row['record_id']} `#{row['name']}` " \
                              "(#{row['body'].to_s.bytesize} B de corpo)" }
          end

          # A validação item a item que `db/etl/load_order.yml` exige. Validar em lote
          # esconde justamente o item torto.
          if row['body'].to_s.match?(/%[0-9A-Fa-f]{2}/)
            linhas << { key: 'action_text:percent_encoded_body',
                        title: 'Corpo com sequência `%XX` — conferir se é texto literal ou URL-escape ' \
                               '(as views de contrato do legado fazem `URI.unescape`)',
                        line: "- pk=#{row['id']} #{tipo}##{row['record_id']} — " \
                              "#{row['body'].to_s[/.{0,60}%[0-9A-Fa-f]{2}.{0,20}/]}" }
          end

          linhas
        end
      end
    end
  end
end
