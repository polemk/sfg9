# frozen_string_literal: true

# S4 / DB-050, DB-555 — **empresas**, escopadas por projeto.
#
# A empresa é a contraparte tomadora dentro de um projeto: é dela que pendem os
# limites de risco (S5), os recebíveis (S6) e as renegociações (S9). Por isso ela
# é a primeira tabela desta fatia — sem `companies` a S5 não tem onde pendurar
# `risk_controls`.
#
# **Escopo por projeto é do contrato C1**: `project_id` é obrigatório, com FK
# real, e o filtro é aplicado NO ENDPOINT (`Company.for_project(current_project!)`),
# nunca por `default_scope`.
#
# Três decisões de esquema:
#
# 1. **Único composto `(project_id, title)` NO BANCO.** O legado tinha só
#    `validates_uniqueness_of :title, scope: [:project_id]` — unicidade de
#    aplicação, que duas requisições simultâneas furam. O índice fecha a corrida.
# 2. **`has_safegold_management` NÃO entra aqui.** No legado a coluna era copiada
#    do projeto por `before_validation` e re-carimbada por `update_all` quando a
#    marca do projeto mudava — histórico inconsistente por design (D-30/DC-01).
#    A escolha entre carimbo histórico e derivação depende da **Q-02**, sem
#    resposta do usuário. Enquanto isso a marca é **derivada do projeto** na
#    leitura, e não há coluna para divergir.
# 3. **`Company` não tem anexo** (DEC-47, explícito): dar logo à empresa seria
#    feature nova, e a opção foi recusada.
class CreateCompanies < ActiveRecord::Migration[8.0]
  def change
    create_table :companies, id: :uuid, default: -> { 'gen_random_uuid()' },
                             comment: 'Empresa (contraparte tomadora) dentro de um projeto. Escopada por projeto — contrato C1.' do |t|
      t.uuid :project_id, null: false,
                          comment: 'Projeto dono. Obrigatório: empresa sem projeto é registro fora de qualquer escopo.'
      t.string :title, null: false, comment: 'Razão social. Única POR PROJETO, garantida por índice (não só por validação).'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência do registro na base do legado.'

      t.timestamps
    end

    add_index :companies, :project_id
    add_index :companies, %i[project_id title], unique: true
    add_index :companies, :legacy_id, unique: true

    # `NO ACTION` de propósito: excluir projeto com empresa deve BLOQUEAR, nunca
    # cascatear (D-24). A mesma política vale nos dois sentidos.
    add_foreign_key :companies, :projects, column: :project_id
  end
end
