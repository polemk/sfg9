# frozen_string_literal: true

# Papel global do usuário — contrato **C3**.
#
# **A escala é a do ai9: menor = mais poder.** OG=1, Admin=2, Gerente=3,
# Colaborador=4 (DEC-41). Os scopes `higher_than`/`lower_than` abaixo já
# comparam assim e **não foram invertidos**: inverter o sinal aqui dá poder de OG
# a um Colaborador, e passa em qualquer teste que verifique só que "a trava
# existe" — porque ela existe, apontando para o lado errado.
#
# `client`, `free` e `visitor` foram REMOVIDOS (DEC-41 parte 2). Só OG sobrevive
# do seed original da base ai9.
class UserType < ApplicationRecord
  # Trilha de auditoria (DEC-59): mudar a definição de um papel é ato de acesso.
  has_paper_trail ignore: %i[updated_at]

  OG          = 'og'
  ADMIN       = 'admin'
  GERENTE     = 'gerente'
  COLABORADOR = 'colaborador'

  # A escala do Safegold na numeração do ai9 (DEC-41). É **tabela**, nunca
  # fórmula — ver `Legacy::RoleMap` para o de-para do ETL e o porquê.
  SAFEGOLD_HIERARCHY = {
    OG => 1,
    ADMIN => 2,
    GERENTE => 3,
    COLABORADOR => 4
  }.freeze

  # Associations
  has_many :users, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :description, presence: true
  validates :hierarchy_level, presence: true,
                              numericality: { only_integer: true, greater_than: 0 },
                              uniqueness: true

  # Callbacks
  before_save :normalize_name

  # Scopes — NÃO INVERTER. `higher_than(4)` devolve quem tem MAIS poder que o
  # nível 4, ou seja `hierarchy_level < 4`.
  scope :ordered_by_hierarchy, -> { order(hierarchy_level: :asc) }
  scope :higher_than, ->(level) { where('hierarchy_level < ?', level) }
  scope :lower_than, ->(level) { where('hierarchy_level > ?', level) }

  # Métodos de classe
  def self.og
    find_by(name: OG)
  end

  def self.admin
    find_by(name: ADMIN)
  end

  def self.gerente
    find_by(name: GERENTE)
  end

  def self.colaborador
    find_by(name: COLABORADOR)
  end

  # Papel padrão de quem entra sem papel explícito. DEC-18.8: papel vazio é
  # tratado como Colaborador e vai para a lista de exceções — nunca promovido
  # nem bloqueado em silêncio.
  def self.default_type
    colaborador
  end

  # Seed idempotente dos 4 papéis do Safegold. Delegado ao seed de referência
  # versionado (`db/seeds/reference/user_types.rb`) para que exista **um** lugar
  # com a escala — chamar isto duas vezes não duplica nem reescreve papel já
  # atribuído a usuário.
  def self.seed_default_types!
    Seeds::Reference::UserTypes.call!
  end

  # Métodos de instância
  def og?
    name.to_s.downcase == OG
  end

  def admin?
    name.to_s.downcase == ADMIN
  end

  def gerente?
    name.to_s.downcase == GERENTE
  end

  def colaborador?
    name.to_s.downcase == COLABORADOR
  end

  def higher_than?(other_type)
    hierarchy_level < other_type.hierarchy_level
  end

  def lower_than?(other_type)
    hierarchy_level > other_type.hierarchy_level
  end

  def same_level?(other_type)
    hierarchy_level == other_type.hierarchy_level
  end

  def display_name
    {
      OG => 'OG',
      ADMIN => 'Administrador',
      GERENTE => 'Gerente',
      COLABORADOR => 'Colaborador'
    }.fetch(name.to_s.downcase, name.to_s.humanize)
  end

  # Autorização não é lida daqui: a fonte é `Authorization::Matrix`, consultada a
  # cada request (BE-042 / DEC-18). Estes três atalhos existem só porque a base
  # já os chamava; ficam derivados da matriz para não haver duas verdades.
  def can_access_admin_panel?
    Authorization::Matrix.allow?(name, 'help_items', :read)
  end

  def can_manage_users?
    Authorization::Matrix.allow?(name, 'users', :create)
  end

  def can_manage_system?
    og?
  end

  # DEC-18.3 — OG e Admin personificam; o Admin só alcança hierarquia inferior à
  # dele, e essa parte é verificada no serviço, com o alvo em mãos.
  def can_impersonate?
    og? || admin?
  end

  private

  def normalize_name
    self.name = name.downcase.strip if name.present?
  end
end
