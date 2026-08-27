# frozen_string_literal: true

# S12 / DB-331, DB-547, OPS-333 — **a prova de aceite** (DEC-80).
#
# O legado guardava `user_id`, `contract_id`, `created_at`, `updated_at`
# (`20180405164055_create_contract_deals.rb:3-8`) — e mais nada. Era o D-65: um
# registro que diz QUE alguém aceitou e não consegue dizer O QUE ele aceitou.
#
# DEC-80 fixou o conjunto mínimo: **usuário, versão, data/hora, IP, user-agent e
# hash do texto**, com índice único `(user_id, contract_id)` e exportador de
# prova. **Mais o texto renderizado no momento do aceite** — a mitigação 1 da
# própria DEC-80, porque o versionamento imutável foi recusado (opção (d)) e o
# documento continua editável no lugar: sem o corpo gravado aqui, editar o
# contrato depois deixa o sistema sabendo *que* mudou e incapaz de mostrar *o
# que* a pessoa leu.
#
# `source` é o DEC-66: os aceites históricos migram marcados `implicit_legacy`,
# preservando a data original, **e não satisfazem a pendência** — o novo aceite
# explícito é exigido na próxima entrada. O passivo tem duas origens no legado, o
# `after_create` que gravava sem interação (`user_decorator.rb:234-240`) e o seed
# que fabricou aceite retroativo para toda a base (`db/seeds.rb:141-157`).
#
# **NÃO é versionado pelo paper_trail** — está em `Sfg::AuditTrail::EXCLUDED`
# com o motivo escrito: o aceite tem prova própria, aqui.
class CreateContractDeals < ActiveRecord::Migration[8.0]
  # `explicit` = a pessoa clicou. `implicit_legacy` = veio carimbado da base
  # antiga. A base do legado NÃO distinguia os dois, e é essa indistinção que a
  # DEC-66 acaba.
  SOURCES = %w[explicit implicit_legacy].freeze

  def change
    create_table :contract_deals, id: :uuid,
                                  comment: 'Aceite de uma versão de contrato por um usuário. É PROVA: guarda IP, user-agent, hash e o texto lido (DEC-80).' do |t|
      t.uuid :user_id, null: false, comment: 'Quem aceitou. Sempre o usuário da sessão — nunca vem do payload (D-68).'
      t.uuid :contract_id, null: false, comment: 'A VERSÃO aceita, não o tipo. Uma linha por versão.'

      t.datetime :accepted_at, null: false,
                               comment: 'Quando. Na carga do legado preserva a data original do registro carimbado (DEC-66).'
      t.string :source, null: false, default: 'explicit',
                        comment: 'DEC-66: `explicit` = a pessoa clicou; `implicit_legacy` = carimbado pela base antiga, NÃO satisfaz a pendência.'
      t.datetime :legacy_accepted_at,
                 comment: 'DEC-66 — data do aceite carimbado pela base antiga. Preservada quando o MESMO registro é promovido a explícito: o índice único (user_id, contract_id) só admite uma linha por versão, e a data original é histórico que não pode ser sobrescrito.'

      # Denormalizados de propósito: a prova tem de sobreviver a qualquer coisa
      # que aconteça com a linha de `contracts` depois.
      t.string :contract_kind, null: false, comment: 'Tipo do documento no momento do aceite. Denormalizado: a prova não pode depender de JOIN.'
      t.integer :contract_version, null: false, comment: 'Número da versão no momento do aceite. Mesma razão.'

      t.string :ip_address, comment: 'Origem da requisição do aceite (DEC-80). Nulo nos aceites `implicit_legacy` — não havia requisição.'
      t.text :user_agent, comment: 'Navegador declarado no aceite (DEC-80). Nulo nos `implicit_legacy`.'
      t.string :content_hash, limit: 64,
                              comment: 'SHA-256 do texto aceito. Prova QUE mudou: editar o contrato depois faz o hash divergir.'
      t.text :accepted_body,
             comment: 'Mitigação 1 da DEC-80: o texto renderizado no momento do aceite. É o que prova O QUE a pessoa leu.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    # O índice único da DEC-80. No legado a unicidade era
    # `validates_uniqueness_of :contract_id, scope: [:user_id]` — só de
    # aplicação, e o duplo clique gravava duas.
    add_index :contract_deals, %i[user_id contract_id], unique: true
    add_index :contract_deals, %i[user_id contract_kind]
    add_index :contract_deals, :legacy_id, unique: true

    add_foreign_key :contract_deals, :users, column: :user_id, on_delete: :cascade
    add_foreign_key :contract_deals, :contracts, column: :contract_id, on_delete: :cascade

    add_check_constraint :contract_deals,
                         "source IN (#{SOURCES.map { |s| "'#{s}'" }.join(', ')})",
                         name: 'contract_deals_source_enum'
  end
end
