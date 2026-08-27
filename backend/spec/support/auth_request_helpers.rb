# frozen_string_literal: true

# Helpers de request spec para as fatias do Safegold.
module AuthRequestHelpers
  # Cabeçalho de sessão para `user`. `project` emite o `X-Project-Id` (suporte a
  # duas abas, contrato C1).
  def auth_headers(user, project: nil)
    headers = { 'Authorization' => "Bearer #{Auth::TokenService.new(user).generate_tokens[:token]}" }
    headers['X-Project-Id'] = project.id.to_s if project
    headers
  end

  # Cria projeto + participação do dono numa tacada. `Project#user_id` é o dono,
  # e o dono também precisa de participação — o escopo lê `memberships`, nunca a
  # coluna de dono.
  #
  # **O nome default é único** (S4): `projects.name` ganhou índice único no
  # banco, porque o legado já exigia `validates :formal, uniqueness: true` e não
  # tinha índice nenhum — duas abas criavam dois projetos com o mesmo nome. Quem
  # precisa de um nome específico continua passando `name:`.
  def create_project_with_owner(owner, slug: nil, name: nil)
    sufixo = SecureRandom.hex(4)
    project = Project.create!(name: name || "Projeto #{sufixo}", slug: slug || "p-#{sufixo}", owner: owner)
    Membership.create!(project: project, user: owner, role: 'responsavel')
    project
  end
end

RSpec.configure do |config|
  config.include AuthRequestHelpers
end
