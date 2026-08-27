# frozen_string_literal: true

class UsersService
  class << self
    include ApiResponseHandler

    # Busca usuário por WhatsApp e retorna entity ou URL de login
    def find_by_whatsapp(params)
      whatsapp = params[:whatsapp]&.gsub(/\D/, '')
      return validation_error_response('WhatsApp inválido') if whatsapp.blank?

      begin
        user = User.find_by(phone: whatsapp)
        if user
          success_response(Api::Entities::User.represent(user), 200)
        else
          error_response({ login_url: "/auth/magic_login?method=whatsapp&identifier=#{whatsapp}" }, 404)
        end
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    # Atualização padrão por ID (sem integração com WhatsApp)
    def update(params)
      id = params.delete(:id)
      user = User.find_by(id: id)
      return not_found_response('Usuário') unless user

      begin
        update_params = params.slice(:email, :phone, :name, :avatar_url, :user_type_id,
                                     :cpf_cnpj, :cep, :street, :number, :complement, :district, :city, :state, :custom_variables).to_h.symbolize_keys.compact
        if update_params[:user_type_id].blank? && (params[:user_type].present? || params[:user_type_slug].present?)
          type_str = (params[:user_type_slug] || params[:user_type]).to_s.downcase
          type = UserType.where('LOWER(name) = ?', type_str).first
          update_params[:user_type_id] = type&.id
        end
        user.assign_attributes(update_params)
        user.custom_variables = params[:custom_variables] if params[:custom_variables].present?
        user.biography = params[:biography] if params[:biography].present?
        user.save!
        success_response(Api::Entities::User.represent(user), 200)
      rescue ActiveRecord::RecordInvalid => e
       validation_error_response(e.message)
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    # Lista de usuários.
    #
    # **BE-504 / C3 — a hierarquia filtra a lista.** O ator só enxerga papéis do
    # próprio nível para baixo: o filtro de um Gerente não devolve OG nem Admin,
    # mas devolve Colaborador. OG enxerga todos. No legado isto vivia em
    # `user_decorator.rb:166-176` e valia só para o dropdown da tela.
    #
    # **DEC-62 — paginação por Kaminari.** O `limit/offset` manual saiu; o
    # envelope vai em cabeçalho, emitido pelo endpoint.
    def index(params, actor: nil)
      page = [(params[:page] || 1).to_i, 1].max
      per_page = (params[:per_page] || 20).to_i
      per_page = 20 if per_page <= 0
      per_page = [per_page, 100].min
      q = params[:q].to_s.strip
      type = params[:type].to_s.strip.downcase

      begin
        # `actor` nulo é o token de sistema (`ClientApplication`), que o endpoint
        # já autorizou e que não tem papel para comparar. Sessão de usuário
        # SEMPRE chega com ator — o endpoint passa `acting_user`.
        # `includes` mata o N+1 da listagem (IMP-A24). São TRÊS associações, e a
        # terceira é a que não se vê: além de `permissions` (uma consulta por usuário)
        # e de `user_type` (que a entity lê duas vezes por linha), a entity expõe
        # `biography_html`, e `has_rich_text` faz uma consulta a
        # `action_text_rich_texts` por linha. Sem `rich_text_biography` no preload a
        # contagem de queries continuava crescendo com a lista mesmo com o resto
        # resolvido — foi o teste de contagem que apontou.
        # S13 — a QUARTA associação: `avatar_url` na entity passou a olhar o anexo
        # ActiveStorage (OPS-493, motor único de anexos), e `avatar.attached?` é uma
        # consulta a `active_storage_attachments` por linha. Sem
        # `with_attached_avatar` a contagem volta a crescer com a lista — o teste de
        # contagem de queries do IMP-A24 pegou na hora, que é para o que ele existe.
        scope = User.includes(:user_type, :rich_text_biography, user_permissions: :permission)
                    .with_attached_avatar
        scope = scope.where(user_type_id: Authorization::Hierarchy.visible_user_types(actor).select(:id)) if actor
        scope = apply_search(scope, q) if q.present?
        # O filtro por tipo é aplicado DENTRO do recorte de hierarquia: pedir
        # `type=og` sendo Gerente devolve vazio, nunca a lista de OGs.
        if type.present? && UserType::SAFEGOLD_HIERARCHY.key?(type)
          ids = UserType.where(name: type).pluck(:id)
          scope = scope.where(user_type_id: ids)
        end

        users = scope.order(created_at: :desc).page(page).per(per_page)
        data = {
          users: Api::Entities::User.represent(users),
          total: users.total_count,
          page: page,
          per_page: per_page,
          total_pages: users.total_pages
        }
        success_response(data, 200)
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    # Criação de conta — **sempre por convite** (DEC-18.7 / BE-012).
    #
    # Três coisas que o legado não fazia e que mudam o resultado:
    #
    #  1. **Papel explícito.** Nunca `Admin` fixo (D-39). Sem `user_type` informado o
    #     padrão é Colaborador, o papel de menos poder — nunca o de mais.
    #  2. **Trava de hierarquia.** Quem convida não cria alguém do próprio nível ou
    #     acima; senão o convite vira a autopromoção que a DEC-18.2 fechou na tela de
    #     permissões, só que por outra rota.
    #  3. **Sem senha.** Não há campo de senha para preencher — o produto não tem senha
    #     (DEC-14). A conta nasce e recebe convite com magic link de primeiro acesso.
    def create(params, actor: nil)
      attrs = params.slice(:email, :phone, :name, :avatar_url, :user_type_id, :username,
                           :cpf_cnpj, :cep, :street, :number, :complement, :district, :city, :state).to_h.symbolize_keys.compact
      return validation_error_response('Informe email ou telefone') if attrs[:email].blank? && attrs[:phone].blank?

      type = resolve_user_type(params, attrs)
      return validation_error_response('Tipo de usuário inválido') if type.nil?

      if actor && !Authorization::Hierarchy.can_edit_user_type?(actor, type)
        return forbidden_response('Você não pode criar um usuário com papel igual ou superior ao seu.')
      end

      attrs[:user_type_id] = type.id
      user = User.create!(attrs)

      # O convite é o que torna a conta utilizável. Se o envio falhar, a conta já
      # existe e o administrador reenvia por `POST /api/v1/users/:id/invite` — falhar a
      # criação inteira por causa do SMTP deixaria o operador sem saber o que aconteceu.
      invite_result = user.email.present? ? Auth::InviteService.call(inviter: actor, user: user) : nil

      data = Api::Entities::User.represent(user).as_json
      data[:invite_sent] = invite_result.present? && invite_result[:success] == true
      success_response(data, 201)
    rescue ActiveRecord::RecordInvalid => e
      validation_error_response(e.message)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    # Reenvio de convite (BE-012). Mesmo caminho da criação, para que não existam dois
    # jeitos de emitir o primeiro acesso.
    def invite(actor:, target_id:)
      target = User.find_by(id: target_id)
      return not_found_response('Usuário') unless target
      unless Authorization::Hierarchy.can_edit_user_permissions?(actor, target)
        return forbidden_response('Usuário fora do seu alcance de hierarquia.')
      end

      Auth::InviteService.call(inviter: actor, user: target)
    end

    def show(params)
      user = User.find_by(id: params[:id])
      return not_found_response('Usuário') unless user

      success_response(Api::Entities::User.represent(user), 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    # Remoção de conta. **Dois caminhos, uma rota** (BE-014 / BE-030).
    #
    #  - **auto-remoção**: o legado confirmava por SENHA. Num produto sem senha
    #    (DEC-14) isso não existe, e a confirmação passa a ser um **código enviado ao
    #    destino cadastrado** — mesma prova de posse, mesmo canal do login;
    #  - **remoção por administrador**: o legado gateava só na view
    #    (`may_delete_users`, D-34) — ou seja, **não gateava**: bastava chamar a rota. A
    #    permissão passa a ser verificada no servidor, com trava de hierarquia.
    #
    # A cascata é declarada no model (`dependent:`): participações e códigos de login
    # somem com a conta; projetos DE PROPRIEDADE dela bloqueiam a remoção
    # (`restrict_with_error`) em vez de sumirem em silêncio.
    def destroy(params, actor: nil)
      user = User.find_by(id: params[:id])
      return not_found_response('Usuário') unless user

      self_removal = actor.present? && actor.id == user.id

      if self_removal
        return validation_error_response(
          'Confirme a remoção com o código enviado ao seu e-mail ou WhatsApp'
        ) unless valid_self_removal_code?(user, params[:code])
      elsif actor.present? && !Authorization::Hierarchy.can_edit_user_permissions?(actor, user)
        return forbidden_response('Usuário fora do seu alcance de hierarquia.')
      end

      user.destroy!
      success_response({}, 204)
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::DeleteRestrictionError
      conflict_response(
        'Esta conta é dona de um ou mais projetos. Transfira a propriedade antes de removê-la.'
      )
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def stats(_params)
      total = User.count
      active = User.active.count
      recent = User.where('created_at >= ?', 7.days.ago).count
      # Contagem por papel do Safegold (DEC-41). O contrato novo é `by_role`.
      by_role = UserType::SAFEGOLD_HIERARCHY.keys.index_with do |name|
        User.joins(:user_type).where(user_types: { name: name }).count
      end
      # **`client_count` FOI REMOVIDO** (S1, 25/08/2026).
      #
      # Era o alias depreciado que apontava `client` (tipo que a DEC-41 removeu) para
      # Colaborador, e existia por um motivo só: `UsersPage.tsx:111` ainda o lia, e sem
      # ele o card de contagem mostraria **zero em silêncio** — que é pior do que
      # quebrar, porque ninguém percebe.
      #
      # O consumidor foi migrado para `by_role` no mesmo passo (Regra de fronteira: o
      # `grep` do outro lado é trabalho de quem remove, não da próxima fatia). Se você
      # veio procurar `client_count`, o que você quer é `by_role.colaborador`.
      data = {
        total: total,
        active: active,
        recent: recent,
        og_count: by_role[UserType::OG],
        by_role: by_role
      }
      success_response(data, 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    # DEC-39 — bloquear/desbloquear conta.
    #
    # Não é `destroy` com outro nome: a conta continua na base, na listagem e na
    # trilha. O que muda é que o gate central passa a recusá-la (`api/root.rb`), e a
    # sessão que ela já tinha **cai na hora** — `User#block!` rotaciona o `jti`, então
    # o access token da aba aberta deixa de casar com o do usuário.
    def block(actor:, target_id:, reason: nil)
      target = User.find_by(id: target_id)
      return not_found_response('Usuário') unless target

      # 403 ANTES de qualquer coisa que dependa do alvo: a ordem inversa vaza a
      # existência do id para quem não tem alcance (mesma família do IMP-A28).
      # A auto-verificação vem ANTES da hierarquia: o próprio papel nunca é "inferior a
      # si mesmo", então a hierarquia responderia 403 e o operador leria "você não tem
      # alcance" quando o problema é outro — ele está tentando se trancar para fora.
      return validation_error_response('Não é possível bloquear a própria conta') if actor&.id == target.id

      unless Authorization::Hierarchy.can_edit_user_permissions?(actor, target)
        return forbidden_response('Usuário fora do seu alcance de hierarquia.')
      end

      target.block!(reason: reason)
      success_response(Api::Entities::User.represent(target.reload), 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def unblock(actor:, target_id:)
      target = User.find_by(id: target_id)
      return not_found_response('Usuário') unless target
      unless Authorization::Hierarchy.can_edit_user_permissions?(actor, target)
        return forbidden_response('Usuário fora do seu alcance de hierarquia.')
      end

      target.unblock!
      success_response(Api::Entities::User.represent(target.reload), 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    # BE-035 / IMP-A14 — validação de CPF com os status HTTP certos.
    #
    # O legado respondia **405** (Method Not Allowed) para CPF malformado e **406**
    # (Not Acceptable) para CPF já cadastrado. Os dois estão errados: 405 fala do
    # método HTTP, 406 fala de content negotiation, e nenhum dos dois é lido por
    # cliente nenhum como "seu dado está inválido". Aqui é **422** para formato
    # inválido e **409** para conflito de unicidade.
    def validate_cpf(params)
      digits = params[:cpf].to_s.gsub(/\D/, '')
      return { status: 422, error: 'invalid_cpf', message: 'CPF deve ter 11 dígitos' } unless digits.length == 11
      return { status: 422, error: 'invalid_cpf', message: 'CPF inválido' } unless valid_cpf_digits?(digits)

      existing = User.where(cpf_cnpj: digits)
      existing = existing.where.not(id: params[:id]) if params[:id].present?
      if existing.exists?
        return { status: 409, error: 'cpf_taken', message: 'Este CPF já está cadastrado em outra conta' }
      end

      success_response({ cpf: digits, valid: true }, 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    # A confirmação de auto-remoção é o MESMO código do login: um `LoginCode` ativo,
    # não usado, do próprio usuário. Reusar o mecanismo evita inventar um segundo tipo
    # de código com regras próprias de expiração e tentativa — que é onde o legado
    # acumulou seis caminhos de credencial diferentes.
    def valid_self_removal_code?(user, code)
      return false if code.blank?

      login_code = LoginCode.where(user_id: user.id, used_at: nil)
                            .where('expires_at > ?', Time.current)
                            .order(created_at: :desc)
                            .first
      return false if login_code.nil?
      return false unless login_code.matches?(code)

      login_code.update!(used_at: Time.current)
      true
    end

    def resolve_user_type(params, attrs)
      return UserType.find_by(id: attrs[:user_type_id]) if attrs[:user_type_id].present?

      # DEC-41 removeu `client`; o padrão é Colaborador (DEC-18.8) — o papel de MENOS
      # poder. Nunca herde para cima quando o chamador não disse nada.
      type_str = (params[:user_type_slug] || params[:user_type] || UserType::COLABORADOR).to_s.downcase
      UserType.where('LOWER(name) = ?', type_str).first || UserType.default_type
    end

    # Busca insensível a acento **dos dois lados** da comparação (IMP-A13).
    #
    # O legado transliterava só o dado do banco e comparava contra o termo cru: quem
    # digitasse "João" não achava "Joao", e quem digitasse "Joao" achava os dois. Metade
    # da busca funcionava, o que é pior que nenhuma — o operador conclui que a pessoa
    # não está cadastrada.
    #
    # `unaccent` vem da extensão do Postgres quando ela existe; sem ela, o fallback é
    # `LOWER` dos dois lados, que ao menos mantém a simetria.
    def apply_search(scope, q)
      term = "%#{q.to_s.downcase.strip}%"
      digits = q.to_s.gsub(/\D/, '')

      if unaccent_available?
        clause = 'unaccent(LOWER(users.name)) LIKE unaccent(?) OR unaccent(LOWER(users.email)) LIKE unaccent(?) ' \
                 'OR LOWER(users.username) LIKE ? OR UPPER(users.identifier) = ?'
      else
        clause = 'LOWER(users.name) LIKE ? OR LOWER(users.email) LIKE ? ' \
                 'OR LOWER(users.username) LIKE ? OR UPPER(users.identifier) = ?'
      end

      args = [term, term, term, q.to_s.strip.upcase]
      if digits.present?
        clause += ' OR users.phone LIKE ?'
        args << "%#{digits}%"
      end

      scope.where(clause, *args)
    end

    def unaccent_available?
      return @unaccent_available if defined?(@unaccent_available)

      @unaccent_available = ActiveRecord::Base.connection.extension_enabled?('unaccent')
    rescue StandardError
      @unaccent_available = false
    end

    # Dígitos verificadores do CPF. Rejeita as sequências repetidas
    # (`11111111111`…), que passam na conta mas nunca são CPF de ninguém.
    def valid_cpf_digits?(digits)
      return false if digits.chars.uniq.size == 1

      [9, 10].all? do |position|
        slice = digits[0, position].chars.map(&:to_i)
        sum = slice.each_with_index.sum { |digit, index| digit * (position + 1 - index) }
        remainder = (sum * 10) % 11
        remainder = 0 if remainder == 10
        remainder == digits[position].to_i
      end
    end
  end
end
