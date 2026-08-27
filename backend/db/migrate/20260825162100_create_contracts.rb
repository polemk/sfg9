# frozen_string_literal: true

# S12 / DB-330, DB-546, BE-337, BE-339 — os documentos de contrato (Termos de
# Uso e Política de Privacidade) e o seu versionamento.
#
# O legado (`20180405163859_create_contracts.rb`) tinha quatro colunas soltas,
# **zero índice além da PK, zero FK e zero `null: false`**. Quatro defeitos
# nascem daí e são fechados aqui:
#
#  1. **`kind` sem `presence`** — contrato com `kind` nulo nunca aparecia na
#     busca do console (o filtro é `where(kind: contract_kinds)`), então ficava
#     invisível E ineditável. Aqui `kind` é `null: false` **com CHECK** do
#     catálogo fechado (BE-339 / Q-B4).
#  2. **Unicidade só de aplicação** (`validates_uniqueness_of :kind, scope:
#     [:version]`) — duas publicações concorrentes do mesmo tipo passavam as
#     duas pela validação e gravavam o mesmo número. Aqui é **índice único
#     `(kind, version)`**, garantia do banco (BE-337).
#  3. **`creator_id` era `integer` sem FK** — autor apagado deixava id órfão
#     apontando para nada. Aqui é FK real com `ON DELETE SET NULL`, e a coluna é
#     anulável de propósito: perder o nome do autor não pode apagar o contrato
#     que as pessoas aceitaram.
#  4. **`version` sem garantia de positividade** — `version_guess` gravava
#     `nil + 1` no primeiro contrato de um tipo. CHECK `version >= 1`.
#
# **A PK é `uuid`, e isso não é estilo:** `action_text_rich_texts.record_id` é
# `uuid NOT NULL` nesta base (`schema.rb:33`). Um `contracts` com PK `bigint`
# faria `has_rich_text :description` estourar na primeira gravação — e o
# `Contract#description` legado JÁ é ActionText, então não há caminho sem isto.
class CreateContracts < ActiveRecord::Migration[8.0]
  # Catálogo FECHADO (BE-339 / Q-B4 / Q-B35). As duas strings são as do legado,
  # **inclusive o typo consolidado** "Politicas" sem acento (`contract.rb:12`):
  # elas viajam em URL pública e existem em links externos (Q-B34), então
  # "corrigir" a grafia aqui quebraria link de terceiro.
  KINDS = ['Termos de Uso', 'Politicas de Privacidade'].freeze

  def change
    create_table :contracts, id: :uuid,
                             comment: 'Versão publicada de um documento de contrato (ToU / Privacidade). Append-only na NUMERAÇÃO — DEC-80.' do |t|
      t.string :kind, null: false,
                      comment: 'Tipo do documento. Catálogo fechado com CHECK; a string preserva o typo do legado porque viaja em URL pública (Q-B34).'
      t.integer :version, null: false,
                          comment: 'Número da versão, atribuído SÓ na criação (BE-336). O legado recalculava em todo save e re-salvar incrementava.'
      t.string :title, null: false, comment: 'Título exibido no topo do documento.'
      t.uuid :creator_id,
             comment: 'Quem publicou. Anulável: perder o autor não pode apagar o documento que as pessoas aceitaram.'
      t.datetime :published_at, null: false,
                                comment: 'Quando a versão foi publicada. É o marco da tolerância de 30 dias (BE-342).'
      t.string :slug, null: false,
                      comment: 'Forma segura do `kind` para URL (`termos-de-uso`). Existe para que o link público não dependa de string com espaço e acento.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    # A garantia do BANCO para publicações concorrentes (BE-337).
    add_index :contracts, %i[kind version], unique: true
    add_index :contracts, %i[slug version], unique: true
    add_index :contracts, :legacy_id, unique: true

    add_foreign_key :contracts, :users, column: :creator_id, on_delete: :nullify

    add_check_constraint :contracts,
                         "kind IN (#{KINDS.map { |k| "'#{k}'" }.join(', ')})",
                         name: 'contracts_kind_enum'
    add_check_constraint :contracts, 'version >= 1', name: 'contracts_version_positive'
  end
end
