# frozen_string_literal: true

# S5 / DB-233, DB-575 — **subtipos de limite** (`RiskOperationSubtype`).
#
# O subtipo é o que decide o **bucket** em que a operação entra no painel de
# exposição: `is_pre = false` soma em "Liquidável" (`risk_control.rb:129-130` do
# legado) e `is_pre = true` soma em "Pré-Faturamento" (`:144-145`). Errar aqui
# muda número na tela principal do produto.
#
# **Quantos subtipos cada tipo tem** é consequência do `has_pre_faturamento` do
# pai: tipo **com** pré-faturamento nasce com **dois** (pré e antecipação),
# ligados um ao outro por `pair_id`; tipo **sem** nasce com **um**. Isso é
# comportamento do model (`after_create`), não do esquema — mas os índices aqui
# o tornam impossível de violar.
#
# ### `is_default_for_type` — o subtipo padrão explícito (DEC-67)
#
# No legado a escolha do subtipo de uma operação criada sem campo na tela é
# `operation_type.subtypes.where(...).pluck(:id).first` (`risk_operation.rb:32`)
# — **sem `order`**, ou seja, ordem de inserção no banco. Como o `after_create`
# do tipo cria o "pré" ANTES do "antecipação", o `.first` tende a cair no pré.
#
# A **DEC-67** trocou esse acidente por uma coluna: o tipo passa a ter um subtipo
# padrão **declarado**, e o valor semeado **reproduz o que o `.first` fazia** —
# nada muda para quem já opera, e o futuro deixa de depender da ordem de
# inserção de linhas num cadastro. É uma exceção consciente ao DEC-30, com o
# critério escrito na própria decisão.
#
# A coluna é `is_default_for_type` e **não** `is_default`: `is_default` já existe
# nesta família com outro significado (linha semeada pelo sistema, que bloqueia
# a exclusão) e é copiada do pai para os DOIS subtipos — não serviria para
# distinguir um deles.
class SubtiposDeLimiteDeRisco < ActiveRecord::Migration[8.0]
  def change
    create_table :risk_operation_subtypes, id: :uuid, default: -> { 'gen_random_uuid()' },
                                           comment: 'Subtipo de limite. Decide o bucket (liquidável × pré-faturamento) da operação no painel de exposição.' do |t|
      t.string :title, null: false, comment: 'Nome do subtipo. Único DENTRO do tipo pai.'
      t.string :integration_key, null: false, comment: 'Chave estável derivada do título na criação e congelada depois.'
      t.boolean :is_active, null: false, default: true, comment: 'Propagado do tipo pai a cada update dele.'
      t.uuid :user_id
      t.boolean :is_default, null: false, default: false, comment: 'Linha semeada pelo sistema — copiada do tipo pai.'
      t.boolean :is_default_for_type, null: false, default: false,
                                      comment: 'DEC-67 — o subtipo escolhido quando o formulário não pergunta. Um por tipo (índice parcial).'
      t.uuid :pair_id, comment: 'O outro subtipo do par pré/antecipação. Nulo em tipo sem pré-faturamento.'
      t.uuid :risk_operation_type_id, null: false
      t.boolean :is_pre, null: false, default: false,
                         comment: 'true = pré-faturamento (soma no bucket "Pré"); false = antecipação/liquidável.'
      t.boolean :allow_manual_operations, null: false, default: true, comment: 'Propagado do tipo pai.'
      t.boolean :allow_receivable_entries, null: false, default: true, comment: 'Propagado do tipo pai.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :risk_operation_subtypes, :risk_operation_type_id
    add_index :risk_operation_subtypes, :pair_id
    add_index :risk_operation_subtypes, :legacy_id, unique: true
    # `validates_uniqueness_of :is_pre, scope: [:risk_operation_type_id]` do legado,
    # promovido a índice: um tipo tem NO MÁXIMO um "pré" e um "antecipação".
    add_index :risk_operation_subtypes, %i[risk_operation_type_id is_pre], unique: true,
                                                                           name: 'index_risk_subtypes_on_type_and_is_pre'
    add_index :risk_operation_subtypes, %i[risk_operation_type_id title], unique: true,
                                                                          name: 'index_risk_subtypes_on_type_and_title'
    add_index :risk_operation_subtypes, :integration_key, unique: true
    # DEC-67 — **um** subtipo padrão por tipo, garantido por índice PARCIAL.
    add_index :risk_operation_subtypes, :risk_operation_type_id, unique: true,
                                                                 where: 'is_default_for_type',
                                                                 name: 'index_risk_subtypes_one_default_per_type'

    # O subtipo morre com o tipo: ele não existe fora dele (`dependent: :destroy`
    # no legado). É a única cascata deste bloco, e é intencional.
    add_foreign_key :risk_operation_subtypes, :risk_operation_types, column: :risk_operation_type_id,
                                                                     on_delete: :cascade
    add_foreign_key :risk_operation_subtypes, :risk_operation_subtypes, column: :pair_id, on_delete: :nullify
    add_foreign_key :risk_operation_subtypes, :users, column: :user_id
  end
end
