# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `contracts` (legado) -> `Contract` (ai9). **S12** (DB-330, BE-336, DEC-80).
      #
      # **2 linhas** em produção, medidas no dump de 31/05/2025: uma versão 1 de
      # cada tipo, as duas criadas em 27/02/2022, as duas com autor. É o menor
      # conversor da migração e um dos mais delicados: são os textos que 135
      # pessoas aceitaram, e cada linha aqui é a âncora de 136 aceites.
      #
      # ## `version` é CONGELADA, e é por isso que ela é atribuída explicitamente
      #
      # DB-330: a numeração existente vira a numeração daqui, **sem renumerar** —
      # renumerar quebraria a correspondência com toda prova de aceite anterior,
      # que é justamente o que esta fatia existe para não perder.
      #
      # Atribuir `version` no `convert` não é redundância: é o que faz
      # `Contract#assign_version_and_slug` (`on: :create`) **não calcular nada**.
      # Deixar em branco chamaria `next_version_for`, que pega o `max + 1` da
      # base de destino — e num banco já semeado a versão 1 do legado viraria 2.
      #
      # E o defeito que o ai9 corrigiu, para ninguém tentar reintroduzi-lo: no
      # legado `version_guess` era `before_save` **sem `on:`**
      # (`../sfg/app/models/contract.rb:2`), então **re-salvar incrementava** — a
      # versão 3 virava 4 sem ninguém publicar nada (BE-336).
      #
      # ## O `kind` preserva o typo, e isso é decisão (Q-B34)
      #
      # `Politicas de Privacidade`, sem acento em "Políticas", é a grafia que
      # está em produção **e em URL pública**: existem links externos com ela. O
      # catálogo do ai9 (`Contract::KINDS`) consolida o typo de propósito, e a
      # rota pública aceita as duas formas — a literal antiga e o slug novo.
      # Conferido no dump: os 2 tipos são reconhecidos por `Contract.kind_for`.
      #
      # Tipo **fora** do catálogo não é convertido às cegas (OPS-332): vira
      # anomalia declarada. Não existe hoje; o dia em que existir, alguém vê.
      #
      # ## `published_at` é a data de criação do legado, não `Time.current`
      #
      # É o marco da tolerância de 30 dias (BE-342). `Contract#ensure_defaults`
      # cairia em `Time.current` se a coluna chegasse vazia, e o efeito seria
      # **zerar a contagem de tolerância de todo mundo no dia 1**. A origem tem
      # a data; ela é que vale.
      #
      # ## O corpo viaja AQUI — mesma razão de `HelpItems`
      #
      # `Contract` tem `validate :corpo_nao_pode_ser_vazio`, e o corpo é
      # ActionText, que na ordem de carga só chega no último passo. Carregar o
      # contrato "vazio agora, texto depois" faria as 2 linhas serem recusadas —
      # e sem elas os 272 aceites não têm a que apontar.
      #
      # `Converters::ActionTextRichTexts` continua rodando depois e reconcilia a
      # mesma linha: ele casa por `(record_type, record_id, name)`, encontra o
      # registro que este conversor criou e **atualiza em vez de duplicar**.
      #
      # Medido: os 2 corpos existem e nenhum é vazio (8.844 bytes no total), e
      # nenhum tem sequência `%XX` — a suspeita de corpo URL-escapado, que vinha
      # de as views de contrato do legado fazerem `URI.unescape`, **não se
      # confirmou contra o dump**. O corpo viaja como está.
      #
      # ## ⚠ A CHAVE NATURAL AQUI NÃO É `legacy_id` — e descobrir isso custou uma carga
      #
      # `Seeds::Reference::Contracts` (OPS-330) **já publica a versão 1 dos dois
      # tipos** na base ai9, a partir de `db/seed_assets/contracts/`. E ele semeia
      # **sem `legacy_id`**: a chave dele é a existência do tipo
      # (`Contract.of_kind(kind).exists?`).
      #
      # Com a chave natural padrão do motor (`legacy_id`), a carga sobre uma base
      # semeada faz `find_or_initialize_by(legacy_id: 1)` **não achar nada**,
      # construir um registro NOVO e bater no índice único `(kind, version)`.
      # Medido, com a mensagem inteira: `PG::UniqueViolation: duplicate key value
      # violates unique constraint "index_contracts_on_kind_and_version"`.
      #
      # A chave natural do DESTINO é `(kind, version)` — é o índice único que o
      # ai9 declara, e é a identidade real de uma versão publicada. Com ela, a
      # carga sobre a base semeada **ATUALIZA a versão 1 com o texto do cliente**
      # em vez de tentar criar uma segunda: o seed é marcador de lugar, o legado
      # é o documento que 135 pessoas aceitaram. E o `legacy_id` entra na linha
      # atualizada, então o de-para fecha e os 272 aceites religam.
      #
      # É a mesma família da nota de idempotência de `Converters::Wallets` e
      # `Converters::ResourceSources` — com uma diferença que importa: lá o seed
      # semeia COM o mesmo `legacy_id`, e por isso a chave padrão basta. Aqui não
      # semeia, e por isso a chave é outra. Não dá para copiar a solução sem
      # olhar o seed.
      #
      # ## O que NÃO viaja
      #
      # `Contract#decoded_description` do legado (`contract.rb:27-29`) não é
      # portado: `URI.unescape` foi removido no Ruby 3.0 e o método levantaria
      # `NoMethodError` em qualquer chamada (BE-345). E `content_hash` **não é
      # coluna de `contracts`** no ai9 — é método, calculado do texto vigente.
      class Contracts < Base
        def self.source_table = 'contracts'
        def self.target_model = 'Contract'
        def self.requires = ['Contract']
        def self.owner_slice = 'S12'
        def self.references = { 'creator_id' => 'livetat_auth_users' }
        # No legado era `validates_uniqueness_of :kind, scope: [:version]` —
        # validação de aplicação. No ai9 é índice do banco. Medido: 2 linhas,
        # 2 pares distintos.
        def self.uniques = [%w[kind version]]
        # `slug` nasce do `kind` no model (`SLUGS`); `description` não é coluna.
        def self.derived = %w[slug description]

        def convert(row)
          {
            kind: Contract.kind_for(row['kind']),
            # DB-330 — congelada. Ver o bloco acima: sem isto o model recalcula.
            version: row['version'],
            title: row['title'],
            creator_id: ref('livetat_auth_users', row['creator_id']),
            # BE-342 — o marco da tolerância de 30 dias vem da ORIGEM.
            published_at: Values.to_utc(row['created_at']).value,
            description: corpo(row),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # A identidade de uma versão publicada, e o índice único do ai9. Ver o
        # bloco "A CHAVE NATURAL AQUI NÃO É `legacy_id`" acima.
        def natural_key(row)
          { kind: Contract.kind_for(row['kind']), version: row['version'] }
        end

        # Mesmo desenho de `HelpItems#corpo`: o texto rico é lido da origem e
        # atribuído junto com o registro, porque a validação de corpo vazio roda
        # antes de `ActionTextRichTexts`. Aqui não há segundo acervo — `contracts`
        # nunca teve coluna `description` (conferido no dump: a tabela tem `id`,
        # `title`, `kind`, `version`, `creator_id` e os timestamps, e foi essa
        # medição que fechou o D-108).
        def corpo(row)
          corpos_ricos[row['id'].to_i]
        end

        def corpos_ricos
          @corpos_ricos ||= begin
            tabela = 'action_text_rich_texts'
            if source.table?(tabela)
              source.ordered_rows(tabela)
                    .select { |r| r['record_type'].to_s == 'Contract' && r['name'].to_s == 'description' }
                    .to_h { |r| [r['record_id'].to_i, r['body']] }
            else
              {}
            end
          end
        end

        def anomalies(row)
          linhas = []

          # OPS-332 — documento de origem sem tipo do catálogo NÃO é carregado às
          # cegas. Medido: 0 em produção; os 2 tipos são reconhecidos.
          if Contract.kind_for(row['kind']).blank?
            linhas << { key: 'contracts:kind_outside_catalog',
                        title: 'Contrato com `kind` FORA do catálogo fechado do ai9 (BE-339/Q-B4) — ' \
                               'o catálogo não é configurável pela interface: tipo novo é migration',
                        line: "- pk=#{row['id']} `kind` = #{row['kind'].inspect}" }
          end

          # Sem corpo o `Contract` do ai9 recusa (BE-345 / `corpo_nao_pode_ser_vazio`),
          # e um contrato sem texto é um contrato que ninguém pode ter aceitado.
          if corpo(row).to_s.strip.blank?
            linhas << { key: 'contracts:without_body',
                        title: 'Contrato SEM corpo em `action_text_rich_texts` — o ai9 recusa corpo ' \
                               'vazio, e sem o contrato os aceites dele não têm a que apontar',
                        line: "- pk=#{row['id']} versão #{row['version']}" }
          end

          linhas
        end
      end
    end
  end
end
