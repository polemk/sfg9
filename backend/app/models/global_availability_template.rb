# frozen_string_literal: true

# S11 / DB-121, BE-132..139 — **o catálogo global de padrões de disponibilidade**
# ("Tipos de disponibilidade").
#
# **Este model NÃO é escopado por projeto, e isso é a regra, não o esquecimento.**
# Mesma leitura do `GlobalCatalog` (S3): o menu esconde a tela de administração
# do catálogo, não o dado do catálogo. Um padrão global cadastrado "no projeto A"
# sumiria da tela do projeto B e quebraria os padrões de projeto que derivam
# dele. Se você veio da S4 e está tentando aplicar `for_project` aqui: pare.
#
# ## Dois comportamentos que o legado escondia do usuário
#
# 1. **`is_mandatory |= 1`** (`global_availability_template.rb:44`) — OR bit a
#    bit com 1, ou seja: **todo padrão global nascia obrigatório**, ignorando o
#    que o formulário dizia. Aqui o valor do formulário é respeitado (BE-134).
# 2. **`should_insert_on_existing_projects` com default `1` e nunca exposto** —
#    o `after_create` (`:26-38`) enfileirava um job **para cada projeto** em
#    **toda** criação. Aqui é escolha do usuário, na tela (DB-132), e a
#    propagação é disparada pelo serviço, não por callback de model.
class GlobalAvailabilityTemplate < AvailabilityTemplate
  # `has_children?` consulta a **classe certa**. No legado o model global
  # declarava `has_many :ignore_lock_active_child_templates, class_name:
  # "ProjectAvailabilityTemplate"` — dentro do model **global** —, então "este
  # padrão global tem filhos?" era respondido consultando padrões de **projeto**
  # (DB-121). O `children_for_sum` da base usa `self.class`, que aqui resolve
  # para esta classe.
  has_many :project_templates, class_name: 'ProjectAvailabilityTemplate',
                               foreign_key: :global_availability_template_id,
                               inverse_of: :global_template, dependent: :nullify

  validates :project_id, absence: { message: 'não se aplica ao catálogo global' }

  before_validation :mark_as_global

  # Marcador de leitura, espelho do `ProjectScoped.project_scoped?`. O spec de
  # contrato C1 confere que este model **não** é `project_scoped?`.
  def self.global_catalog? = true

  def scope_label = 'Global'

  private

  def siblings_at_base
    GlobalAvailabilityTemplate.where(parent_template_id: nil)
  end

  def mark_as_global
    self.is_global = true
    self.project_id = nil
  end
end
