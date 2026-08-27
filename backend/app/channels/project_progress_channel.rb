# frozen_string_literal: true

# S0 / OPS-087, OPS-128 — progresso de job por Action Cable.
#
# **Princípio 10:** progresso chega por evento invalidando a consulta, nunca por
# `setInterval` batendo no servidor. O legado fazia polling a cada N segundos e
# o job de disponibilidade podia terminar sem que a tela soubesse.
#
# **Escopo (C1):** o canal só aceita quem PARTICIPA do projeto. O
# `PermissionsChannel` da base aceita qualquer `user_id` que o cliente mandar —
# é a flag de upstream U2, e não se repete o padrão aqui.
class ProjectProgressChannel < ApplicationCable::Channel
  def subscribed
    project_id = params[:project_id]
    return reject if project_id.blank?
    return reject if current_user.blank?
    # A verdade é a linha de `memberships`, a mesma que `current_project!` usa.
    return reject unless current_user.member_of?(project_id)

    stream_from self.class.stream_name_for(project_id)
  end

  def self.stream_name_for(project_id)
    "project_progress:#{project_id}"
  end

  # Ponto único de emissão. Jobs chamam isto — nunca `ActionCable.server.broadcast`
  # solto, senão o nome do stream vira convenção oral.
  def self.publish(project_id, payload)
    ActionCable.server.broadcast(stream_name_for(project_id), payload)
  end
end
