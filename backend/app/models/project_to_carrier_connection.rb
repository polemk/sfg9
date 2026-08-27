# frozen_string_literal: true

# S4 / DB-068, DB-081 — **a ponte única projeto ↔ portador**.
#
# Os portadores de uma empresa são derivados do projeto (`Company#carriers` é
# `through: :project`). Não existe tabela empresa↔portador, e não se inventa uma:
# a conexão é do projeto, e é ela que decide quais portadores aparecem no
# formulário de garantia (BE-119) e no de limite de risco (S5).
#
# **O portador é catálogo GLOBAL; a CONEXÃO é que é escopada** (C1). Por isso
# este model inclui `ProjectScoped` e `Carrier` não inclui — as duas regras são
# opostas de propósito, e é aqui que elas se encontram.
class ProjectToCarrierConnection < ApplicationRecord
  include ProjectScoped

  belongs_to :carrier

  # A unicidade real é o índice composto do banco; a validação existe para dar
  # mensagem de humano em vez de `RecordNotUnique`. O legado tinha **só** a
  # validação — e duas abas a furavam.
  validates :carrier_id, uniqueness: { scope: :project_id,
                                       message: 'já está conectado a este projeto' }
end
