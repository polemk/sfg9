# frozen_string_literal: true

# S4 / BE-080..BE-096, BE-100 — **o CRUD do projeto**, o tenant do Safegold.
#
# A visibilidade é `Project.visible_to(user)` (DEC-99: OG e Admin enxergam todos
# os projetos, sem participação); a **participação literal** continua sendo
# `for_member`, e é ela que a aba de membros e o cálculo de "sobrou algum?"
# usam. Os dois escopos existem e significam coisas diferentes.
#
# Os três defeitos que esta classe fecha:
#
# - **D-29** — `Project.where(id: params[:project_id])` **substituía** a lista
#   escopada por membership. Aqui o filtro entra DENTRO do escopo.
# - **D-38** — criar projeto com responsável novo montava `username` e `senha em
#   texto plano` num hash para a view. Aqui **nenhuma senha é montada, exibida ou
#   enviada**: a pessoa recebe um link de convite (`Auth::InviteService`).
# - **DC-14** — indicar um responsável existente passava a posse e deixava o
#   criador **de fora do próprio projeto**. Aqui o criador permanece com
#   participação explícita.
class ProjectService
  class << self
    include ApiResponseHandler

    UUID_FORMAT = ProjectScopedService::UUID_FORMAT

    # BE-080/BE-081/BE-082 — a busca. `project_id` e `importing_id` são
    # aplicados **dentro** do escopo de visibilidade, nunca no lugar dele.
    def index(user:, params: {})
      scope = Project.visible_to(user)

      scope = scope.where(id: params[:project_id]) if uuid?(params[:project_id])
      scope = scope.none if params[:project_id].present? && !uuid?(params[:project_id])
      scope = scope.where(importing_id: params[:importing_id]) if params[:importing_id].present?

      # BE-081 — `order_mode=dash`: `updated_at` ascendente e `q` IGNORADO.
      return { status: 200, data: scope.order(updated_at: :asc) } if params[:order_mode].to_s == 'dash'

      scope = scope.search(params[:q]) if params[:q].present?
      { status: 200, data: Project::ORDERING.apply(scope, keys: params[:ordering_keys],
                                                          styles: params[:ordering_style]) }
    end

    # BE-083 — autocomplete. `ILIKE` (o legado usava `LIKE` cru, case-sensitive
    # no Postgres: digitar minúscula não achava nada) **e com limite**.
    def autocomplete(user:, term:, limit: 10)
      scope = Project.visible_to(user).search(term).order(:name).limit([limit.to_i, 50].min.clamp(1, 50))
      { status: 200, data: scope }
    end

    def show(user:, id:)
      project = find(user, id)
      return not_found_response('Projeto') if project.nil?

      { status: 200, data: project }
    end

    # BE-084 — os candidatos a responsável, filtrados por **hierarquia de
    # papel** (`Authorization::Hierarchy`), não por decorator de view.
    def responsible_candidates(actor:, params: {})
      scope = User.where(user_type_id: Authorization::Hierarchy.visible_user_types(actor).select(:id))
      termo = params[:q].to_s.strip
      if termo.present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
        scope = scope.where('name ILIKE :q OR email ILIKE :q', q: like)
      end

      { status: 200, data: scope.order(:name) }
    end

    WRITABLE = %i[name is_active segment_id sub_segment_id color address_type address
                  address_number address_complement neighborhood cep address_state
                  address_city closing_date has_safegold_management availability_note].freeze

    # BE-085/BE-086/BE-087 — a criação, nos três modos do legado, em **transação
    # atômica**.
    #
    # `responsible_mode`:
    #   `new`      → cria o usuário e **envia link de convite** (D-38);
    #   `existing` → usa um usuário que já existe (DC-14: o criador FICA);
    #   `none`     → grava só nome e e-mail em texto, sem conta.
    def create(actor:, attrs:, responsible_mode: 'none', responsible: {})
      project = Project.new
      assign(project, attrs)
      project.owner = actor

      convidado = nil

      Project.transaction do
        case responsible_mode.to_s
        when 'new'
          convidado = build_new_responsible(project, responsible, actor)
          return unprocessable(convidado) if convidado.errors.any?

          project.responsible = convidado
          project.owner = convidado
        when 'existing'
          alvo = User.find_by(id: responsible[:user_id])
          # Responsável em branco → **422**, não o 500 do legado
          # (`@project.responsible.formal` sobre `nil`).
          return validation_error_response('Selecione um responsável existente.') if alvo.nil?

          project.responsible = alvo
          project.owner = alvo
        else
          project.responsible = nil
          project.responsible_name = responsible[:name].presence
          project.responsible_email = responsible[:email].presence
        end

        return unprocessable(project) unless project.save

        ensure_memberships!(project, actor)
        create_default_company!(project)
        raise ActiveRecord::Rollback if project.errors.any?
      end

      return unprocessable(project) if project.errors.any? || project.id.blank?

      # O convite sai **depois** do commit: e-mail enviado dentro de transação
      # que depois rola de volta é convite para um projeto que não existe.
      Auth::InviteService.call(inviter: actor, user: convidado) if convidado.present?

      # BE-088 — **progresso próprio**. No legado as duas tarefas de criação
      # escreviam no MESMO `job_id` (`self.job_id = job.id` duas vezes) e se
      # atropelavam: a barra do usuário mostrava o progresso de uma e o fim da
      # outra. Aqui cada job publica com o seu identificador.
      #
      # A segunda tarefa da criação — semear os padrões de disponibilidade a
      # partir dos globais — é da **S11**, dona de `availability_templates`. Ela
      # se enfileira aqui, com `job_id` PRÓPRIO.
      LinkDefaultMembersJob.perform_later(project.id)

      # S13 / OPS-465 — **o legado enfileirava as DUAS tarefas no `after_create`**
      # (`../sfg/app/models/project.rb:74,82`), e a segunda é esta. O
      # `SeedGlobalTemplatesJob` existia desde a S11 e **ninguém o chamava**: um
      # projeto novo nascia sem nenhum padrão de disponibilidade, e nada acusava
      # — o job estava correto, testado e órfão. Achado ao fechar a dívida da
      # S13 em 26/08/2026.
      SeedGlobalTemplatesJob.perform_later(project.id, actor&.id)

      { status: 201, data: project.reload }
    end

    # BE-089 — a edição. Trocar de responsável **garante a participação dele**;
    # a marca de BI **não** muda por aqui (tem endpoint próprio, DC-16).
    def update(actor:, user:, id:, attrs:, responsible: nil)
      project = find(user, id)
      return not_found_response('Projeto') if project.nil?

      assign(project, attrs)

      if responsible.present? && responsible.key?(:user_id)
        alvo = responsible[:user_id].present? ? User.find_by(id: responsible[:user_id]) : nil
        return validation_error_response('Responsável inexistente.') if responsible[:user_id].present? && alvo.nil?

        project.responsible = alvo
      end

      return unprocessable(project) unless project.save

      ensure_membership_for(project, project.responsible) if project.responsible.present?
      ensure_membership_for(project, actor)

      { status: 200, data: project.reload }
    end

    # BE-091 — exclusão bloqueada responde **422 real** (D-24). O projeto de
    # treinamento nunca é removido, só limpo (BE-092).
    def destroy(user:, id:)
      project = find(user, id)
      return not_found_response('Projeto') if project.nil?

      unless project.destroy
        return error_response(project.errors.full_messages.to_sentence, 422,
                              details: project.errors.messages)
      end

      success_response({ deleted: true, id: id.to_s }, 200)
    rescue ActiveRecord::InvalidForeignKey
      error_response('Não é possível excluir: há registros vinculados a este projeto.', 422)
    end

    # BE-093 — a marca "Gerido pela Safegold".
    #
    # **DEC-112.** O "Q-02 sem resposta" que travava isto era citação errada: a
    # Q-02 é a matriz de autorização. A pergunta certa (Q-17 dos mapas) foi
    # respondida pelo DEC-30 — **manter o carimbo, inclusive a inconsistência**.
    #
    # Réplica de `project.rb:297-303`: grava a marca no projeto e, **só se o save
    # deu certo**, ressincroniza em massa as **empresas** — e nada mais. Os
    # limites de risco, as posições, os lançamentos de disponibilidade, os
    # recebíveis e as renegociações já gravados **ficam com o carimbo velho**.
    #
    # Isso é o **D-30**, e é replicado de propósito: o carimbo é a foto do
    # momento, não há leitor interno nenhum (nem `where`, nem scope, nem `if` de
    # regra), e o consumidor real é externo (BI/planilha do cliente), que quer
    # justamente o valor histórico. **Não estenda o `update_all` às outras
    # cinco** — seria melhoria não autorizada.
    def set_safegold_management(user:, id:, value:)
      resultado = toggle(user: user, id: id, column: :has_safegold_management, value: value)
      return resultado if resultado[:status] != 200

      projeto = resultado[:data]
      # `update_all`: sem callback e sem `updated_at`, exatamente como o legado.
      # Recarimbar empresa a empresa dispararia o `before_validation` de cada uma
      # e reescreveria `updated_at` de toda a carteira.
      Company.where(project_id: projeto.id)
             .update_all(has_safegold_management: projeto.has_safegold_management)

      resultado
    end

    # BE-094 — a marca comercial de BI. Gravada e exibida como hoje (DC-16):
    # pode haver consumidor externo.
    def set_bi(user:, id:, value:)
      toggle(user: user, id: id, column: :has_bi, value: value)
    end

    # BE-100 / DC-18 — os projetos de um usuário. Aba **informativa**: mostra só
    # o que o SOLICITANTE já poderia ver.
    def projects_of(actor:, target_id:)
      target = User.find_by(id: target_id)
      return not_found_response('Usuário') if target.nil?

      visiveis = Project.visible_to(actor).select(:id)
      { status: 200, data: Project.for_member(target).where(id: visiveis).order(:name).distinct }
    end

    # DB-089 / OPS-088 — o logo do projeto. `Project#avatar` já vinha ligado ao
    # motor único de anexos (S13, `config/attachments.yml`, 5 MB, política
    # `project_member`); o que faltava era o caminho de escrita.
    def attach_avatar_file(user:, id:, file:)
      project = find(user, id)
      return not_found_response('Projeto') if project.nil?

      project.avatar.attach(io: file[:tempfile], filename: file[:filename], content_type: file[:type])
      unless project.save
        project.avatar.purge
        return unprocessable(project)
      end

      { status: 200, data: project.reload }
    end

    def remove_avatar(user:, id:)
      project = find(user, id)
      return not_found_response('Projeto') if project.nil?

      project.avatar.purge_later if project.avatar.attached?
      { status: 200, data: project.reload }
    end

    private

    def toggle(user:, id:, column:, value:)
      project = find(user, id)
      return not_found_response('Projeto') if project.nil?

      project.public_send(:"#{column}=", ActiveModel::Type::Boolean.new.cast(value) == true)
      return unprocessable(project) unless project.save

      { status: 200, data: project.reload }
    end

    def find(user, id)
      return nil unless uuid?(id)

      Project.visible_to(user).find_by(id: id)
    end

    def assign(project, attrs)
      WRITABLE.each do |attribute|
        next unless attrs.key?(attribute)

        project.public_send(:"#{attribute}=", attrs[attribute])
      end
    end

    # **D-38 — nenhuma senha é montada.** O usuário nasce sem credencial e
    # recebe um link de uso único para definir a própria entrada.
    def build_new_responsible(project, responsible, actor)
      user = User.new(
        name: responsible[:name],
        email: responsible[:email],
        user_type: UserType.colaborador
      )
      user.validate
      if user.errors.any?
        user.errors.full_messages.each { |m| project.errors.add(:responsible, m) }
        return user
      end

      user.save
      user
    end

    # DC-14 — **o criador permanece com participação própria**, mesmo quando a
    # posse vai para outra pessoa. No legado ele ficava de fora do projeto que
    # acabara de criar.
    def ensure_memberships!(project, actor)
      ensure_membership_for(project, project.owner, role: 'responsavel')
      ensure_membership_for(project, actor)
    end

    def ensure_membership_for(project, user, role: 'participante')
      return if user.blank?
      return if Membership.exists?(project_id: project.id, user_id: user.id)

      Membership.create(project: project, user: user, role: role)
    end

    # O legado criava `Company.create(project_id:, title: "Empresa Padrão")` no
    # `after_create` do model. Fica, mas **no serviço**: efeito colateral de
    # criação não pertence ao model, e um seed ou um ETL que crie projeto não
    # quer necessariamente a empresa padrão.
    def create_default_company!(project)
      Company.create(project: project, title: 'Empresa Padrão')
    end

    def uuid?(value)
      value.to_s.match?(UUID_FORMAT)
    end

    def unprocessable(record)
      error_response(record.errors.full_messages.to_sentence, 422, details: record.errors.messages)
    end
  end
end
