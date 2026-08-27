# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `help_items` (legado) -> `HelpItem` (ai9). **S12** (DB-590, DB-369, BE-352, BE-362).
      #
      # Terceiro nível da árvore de ajuda: 25 linhas em produção, medidas no dump
      # de 31/05/2025.
      #
      # ==========================================================================
      # ⚠ O CORPO DO ITEM VIAJA AQUI, E NÃO NA TABELA DE TEXTO RICO — LEIA ANTES
      # ==========================================================================
      #
      # `HelpItem` do ai9 tem `validate :corpo_nao_pode_ser_vazio` (BE-352): item
      # sem texto **não salva**. E o corpo é ActionText, que na ordem de carga só
      # chega em `ActionTextRichTexts`, o ÚLTIMO passo — depois deste. Carregar o
      # item "vazio agora, texto depois" **não funciona**: os 25 itens seriam
      # recusados um a um, no meio da janela de cutover.
      #
      # Então o corpo é lido da origem **aqui**, e atribuído junto com o
      # registro. `ActionTextRichTexts` continua rodando depois e continua
      # reconciliando a mesma linha — ele casa por `(record_type, record_id,
      # name)`, encontra o registro que este conversor criou e **atualiza em vez
      # de duplicar**. Os dois caminhos convergem, de propósito.
      #
      # ## Os DOIS acervos de corpo, e a ordem que decide qual vence — D-58
      #
      # O item de ajuda do legado tem conteúdo em dois lugares:
      #
      #  - a **coluna** `help_items.description`, escrita até 04/2019;
      #  - `action_text_rich_texts`, usada depois, quando `has_rich_text` entrou.
      #
      # `has_rich_text` **sobrescreveu o leitor da coluna**: a partir de 04/2019 o
      # conteúdo novo ficou invisível para todo `WHERE description ILIKE …`, e
      # ninguém percebia — o item abria normalmente; só a busca mentia. É o D-58.
      #
      # A regra é a de `Help::LegacyImport`: **ActionText primeiro, coluna
      # depois**, e nunca o contrário — inverter faria o conteúdo de 2018
      # sobrescrever o de 2024 nos itens que têm os dois.
      #
      # **Medido no dump de 31/05/2025**: os 25 itens têm registro ActionText com
      # corpo NÃO vazio, e a **coluna está vazia nos 25**. Nenhum item de
      # produção depende hoje do segundo passo — mas a regra fica escrita, porque
      # a base do dia da virada é outra e o custo de descobrir isso lá é alto.
      #
      # ## AUTOR e ÚLTIMO EDITOR são colunas separadas — FE-366
      #
      # No legado o `user_id` viajava num campo escondido **sempre com o
      # `current_user`**: editar item de outro autor **reescrevia a autoria**. O
      # ai9 tem `user_id` (autor) e `last_updated_user_id` (quem mexeu por
      # último). A origem só sabe uma coisa, e ela é o autor: `user_id` recebe o
      # de-para e **`last_updated_user_id` entra NULO**. Copiar o autor para os
      # dois afirmaria que o autor foi o último a editar — que é exatamente a
      # confusão que a segunda coluna existe para desfazer.
      #
      # Medido: 25 de 25 itens têm `user_id` preenchido e **nenhum é órfão**.
      #
      # ## ⚠ Foi ESTE conversor que revelou o carimbo de `updated_at` do ActionText
      #
      # Carregar o corpo aqui expôs um defeito que valia para os **três** donos
      # de texto rico (`Indicator`, `HelpItem`, `Contract`):
      # `ActionText::RichText` é `belongs_to :record, touch: true`, então gravar
      # o corpo **toca o dono** e reescreve `updated_at` com `Time.current`. Os
      # 25 itens voltaram da primeira carga com data de hoje — `created_at`
      # certo, `updated_at` perdido, sem erro nenhum.
      #
      # Quem pegou foi a reconciliação: 25 amostradas, **25 divergências**, todas
      # na mesma coluna. A correção **não está aqui** — está no motor
      # (`Run#load_rows` envolve o lote em `no_touching`), porque o problema não
      # é deste conversor e um remendo local deixaria `Indicators` sangrando 485
      # datas. Ver o comentário lá, que explica também por que corrigir DEPOIS do
      # `save!` não funciona (dentro de transação o Rails usa `touch_later`, e o
      # carimbo cai no commit).
      #
      # ## `position` — mesma história de `HelpGroups` e `HelpCategories`
      #
      # Coluna nova, sem valor na origem, atribuída pelo model na criação, dentro
      # da categoria. Declarada em `derived`.
      class HelpItems < Base
        def self.source_table = 'help_items'
        def self.target_model = 'HelpItem'
        def self.requires = %w[HelpItem HelpCategory]
        def self.owner_slice = 'S12'
        def self.references = { 'help_category_id' => 'help_categories',
                                'user_id' => 'livetat_auth_users' }
        def self.uniques = [%w[help_category_id title]]
        # `position` nasce no model; `description` não é coluna no ai9 (é
        # ActionText) e por isso também não se compara literalmente.
        def self.derived = %w[position description]

        def convert(row)
          {
            help_category_id: ref('help_categories', row['help_category_id']),
            title: row['title'].to_s.strip,
            # FE-366 — o autor da origem é o AUTOR, e só ele.
            user_id: ref('livetat_auth_users', row['user_id']),
            last_updated_user_id: nil,
            # Ver o bloco do topo: sem isto, os 25 itens são recusados pela
            # validação de corpo vazio antes de `ActionTextRichTexts` rodar.
            description: corpo(row),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # D-58 — ActionText primeiro, coluna depois. `nil` quando não há nenhum
        # dos dois: o model recusa, e a recusa aparece como erro da linha, que é
        # melhor que gravar um item de ajuda em branco.
        def corpo(row)
          rico = corpos_ricos[row['id'].to_i]
          return rico if rico.to_s.strip.present?

          coluna = row['description']
          coluna.to_s.strip.present? ? coluna : nil
        end

        # Índice `id do item => corpo`, montado UMA vez. `anomalies` e `convert`
        # rodam linha a linha, e reler 512 linhas de texto rico por item seria
        # trocar 25 leituras por 12.800 — mesmo motivo do índice de `Indicators`.
        def corpos_ricos
          @corpos_ricos ||= begin
            tabela = 'action_text_rich_texts'
            if source.table?(tabela)
              source.ordered_rows(tabela)
                    .select { |r| r['record_type'].to_s == 'HelpItem' && r['name'].to_s == 'description' }
                    .to_h { |r| [r['record_id'].to_i, r['body']] }
            else
              {}
            end
          end
        end

        # Item sem corpo em NENHUM dos dois acervos não é convertido em silêncio:
        # o ai9 o recusaria de qualquer forma (BE-352), e a linha precisa
        # aparecer antes da janela, não durante. Medido: 0 em produção.
        def anomalies(row)
          return [] if corpo(row).present?

          [{ key: 'help_items:without_body',
             title: 'Item de ajuda sem corpo em NENHUM dos dois acervos (ActionText e coluna) — ' \
                    'o ai9 recusa corpo vazio (BE-352), e a linha NÃO entra',
             line: "- pk=#{row['id']} categoria=#{row['help_category_id']}" }]
        end
      end
    end
  end
end
