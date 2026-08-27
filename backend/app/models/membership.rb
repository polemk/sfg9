# frozen_string_literal: true

# S0 / DB-086, DB-545 — peça 1 do contrato **C1**.
#
# É a verdade sobre quem enxerga o quê. `users.current_project_id` é preferência;
# a linha desta tabela é autorização, e é revalidada a cada request por
# `current_project!`.
#
# **`role` NUNCA autoriza nada** (DEC-18.6 / Q-A2). Se você está lendo isto
# porque quer `membership.role == 'gestor'` num gate: pare. A autorização do
# Safegold tem UMA dimensão — papel global (`users.user_type_id`) mais a
# existência de participação. O `role` é rótulo para a tela de membros.
class Membership < ApplicationRecord
  # Trilha de auditoria (DEC-59): conceder e revogar participação é ato de
  # acesso, e é isso que se quer poder reconstruir depois.
  has_paper_trail ignore: %i[updated_at]

  ROLES = %w[responsavel participante coordenador gestor].freeze

  belongs_to :user
  belongs_to :project

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :project_id,
                                    message: 'já participa deste projeto' }

  scope :for_project, lambda { |project|
    project_id = project.respond_to?(:id) ? project.id : project
    where(project_id: project_id)
  }
  scope :for_user, lambda { |user|
    user_id = user.respond_to?(:id) ? user.id : user
    where(user_id: user_id)
  }

  # O dono do projeto não pode perder a participação (DEC-18.5 / DEC-15.2) —
  # a condição vivia na view do legado e vira regra de servidor aqui.
  def project_owner?
    project.user_id == user_id
  end
end
