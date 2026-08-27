# frozen_string_literal: true

# S0 / BE-099, BE-045, BE-046, BE-044 — participação em projeto.
#
# As três condições que no legado viviam na **view**
# (`projects/detail/memberships/list/_widget.html.erb:19,23`) viram **regra de
# servidor** aqui. No legado `memberships_controller.rb` não tinha gate nenhum
# (D-34): a tela escondia o botão e a rota fazia tudo.
#
#  1. **não-readonly** — gate global `require_not_readonly!` (DEC-18.6);
#  2. **não remove o dono do projeto** (`project.user_id`) — aqui;
#  3. **não remove a si mesmo** — aqui.
#
# Mais duas que o legado não tinha e que fecham defeitos:
#  - **auto-participação é impossível** (D-28 + D-34): nenhuma sessão se
#    adiciona a um projeto; quem adiciona é OG/Admin/Gerente, e nunca a si mesmo;
#  - **revogar limpa o `current_project_id` de quem saiu** (DB-018): o usuário
#    não continua "dentro" do projeto por causa de uma preferência obsoleta.
class MembershipService
  class << self
    include ApiResponseHandler

    # Lista os membros do projeto CORRENTE. O projeto vem de `current_project!`,
    # nunca de parâmetro — contrato C1.
    def index(project:, params: {})
      scope = Membership.for_project(project).includes(:user).order(created_at: :asc)
      page = [(params[:page] || 1).to_i, 1].max
      per_page = normalize_per_page(params[:per_page])
      paginated = scope.page(page).per(per_page)

      success_response({
                         memberships: paginated.map { |m| serialize(m) },
                         total: paginated.total_count,
                         page: page,
                         per_page: per_page,
                         total_pages: paginated.total_pages
                       }, 200)
    end

    # Autocomplete de quem AINDA NÃO é membro (BE-044).
    #
    # Termo vazio devolve lista válida (os primeiros N candidatos) — no legado a
    # busca com termo vazio montava um `LIKE` sem placeholder e quebrava.
    def candidates(project:, actor: nil, params: {})
      already = Membership.for_project(project).select(:user_id)
      scope = User.where.not(id: already)
      # A hierarquia também vale aqui: um Gerente não convida OG nem Admin.
      scope = scope.where(user_type_id: Authorization::Hierarchy.visible_user_types(actor).select(:id)) if actor

      term = params[:q].to_s.strip
      if term.present?
        like = "%#{term.downcase}%"
        digits = term.gsub(/\D/, '')
        scope = if digits.present?
                  scope.where('LOWER(name) LIKE ? OR LOWER(email) LIKE ? OR phone LIKE ?', like, like, "%#{digits}%")
                else
                  scope.where('LOWER(name) LIKE ? OR LOWER(email) LIKE ?', like, like)
                end
      end

      page = [(params[:page] || 1).to_i, 1].max
      per_page = normalize_per_page(params[:per_page])
      paginated = scope.order(:name).page(page).per(per_page)

      success_response({
                         candidates: paginated.map { |u| { id: u.id, name: u.name, email: u.email, phone: u.phone } },
                         total: paginated.total_count,
                         page: page,
                         per_page: per_page,
                         total_pages: paginated.total_pages
                       }, 200)
    end

    # `:id` NÃO entra: o id da participação é gerado pelo banco (família
    # D-60/D-68, exigência do DEC-15.2). O `project_id` também não entra — vem de
    # `current_project!`.
    def create(project:, actor:, user_id:, role: nil)
      return forbidden('Sessão inválida.') if actor.nil?

      # D-28 + D-34: auto-participação é impossível.
      return forbidden('Ninguém se adiciona a um projeto.', code: 'SELF_MEMBERSHIP') if user_id.to_s == actor.id.to_s

      target = User.find_by(id: user_id)
      return not_found_response('Usuário') if target.nil?

      membership = Membership.new(project: project, user: target, role: role.presence || 'participante')
      return validation_error_response(membership.errors.full_messages.to_sentence) unless membership.save

      success_response(serialize(membership), 201)
    rescue ActiveRecord::RecordNotUnique
      validation_error_response('Usuário já participa deste projeto')
    end

    def destroy(project:, actor:, membership_id:)
      return forbidden('Sessão inválida.') if actor.nil?

      membership = Membership.for_project(project).find_by(id: membership_id)
      # Id de outro projeto responde 404 igual a id inexistente — não se
      # confirma a existência de registro alheio (regra 2 do C1).
      return not_found_response('Participação', genero: :feminino) if membership.nil?

      if membership.project_owner?
        return forbidden('O dono do projeto não pode ser removido.', code: 'OWNER_PROTECTED')
      end
      if membership.user_id == actor.id
        return forbidden('Você não pode remover a própria participação.', code: 'SELF_REMOVAL')
      end

      removed_user_id = membership.user_id
      Membership.transaction do
        membership.destroy!
        release_current_project!(removed_user_id, project)
      end

      success_response({}, 204)
    end

    private

    # DB-018 — quem perdeu a participação não continua "dentro" do projeto.
    # Recalcula: se sobrou exatamente um projeto, vira o corrente; senão, nulo.
    def release_current_project!(user_id, project)
      user = User.find_by(id: user_id)
      return if user.nil? || user.current_project_id != project.id

      remaining = Project.for_member(user)
      user.update_columns(
        current_project_id: (remaining.count == 1 ? remaining.first.id : nil),
        updated_at: Time.current
      )
    end

    def serialize(membership)
      {
        id: membership.id,
        role: membership.role,
        project_id: membership.project_id,
        is_project_owner: membership.project_owner?,
        user: {
          id: membership.user_id,
          name: membership.user.name,
          email: membership.user.email,
          phone: membership.user.phone
        },
        created_at: membership.created_at
      }
    end

    def normalize_per_page(value)
      value = value.to_i
      value = 20 if value <= 0
      [value, 100].min
    end

    def forbidden(message, code: 'FORBIDDEN')
      error_response(message, 403, details: { code: code })
    end
  end
end
