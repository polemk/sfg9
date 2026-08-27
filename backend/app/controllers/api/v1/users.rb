# frozen_string_literal: true

module Api
  module V1
    class Users < Grape::API
      helpers Api::V1::ControllerHelpers

      # O `require_og!` local foi removido: era cópia do helper compartilhado e
      # ficava fora da matriz. Autorização agora é `authorize!` (DEC-18).

      # ===============================================
      # USERS - VERIFICAÇÃO POR WHATSAPP
      # ===============================================

      # GET /api/v1/users/find_by_whatsapp - Buscar usuário por WhatsApp
      resource :find_by_whatsapp do
        desc 'Buscar usuário por número de WhatsApp' do
          summary 'Buscar usuário por número de WhatsApp'
          detail 'Verifica se existe um usuário cadastrado com o número de WhatsApp fornecido. Se existir, retorna os dados do usuário. Caso contrário, retorna a URL de login.'
          success [code: 200, message: 'Ok']
          named 'Find User by WhatsApp Response'
        end

        params do
          requires :whatsapp, type: String, desc: 'Número de WhatsApp do usuário (ex: 5548999999999)'
        end

        get '', http_codes: [
          [404, 'Usuário não encontrado - retorna URL de login'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [403, 'Forbidden'],
          [500, 'Internal Server Error']
        ] do
          # **U4 — este endpoint não tinha gate nenhum** (flag de upstream da base ai9).
          #
          # Qualquer sessão autenticada consultava qualquer telefone e recebia o
          # `Api::Entities::User` inteiro do dono — nome, e-mail, CPF, endereço. Com o
          # Colaborador sendo o papel mais numeroso do Safegold, isso é a base de
          # clientes legível por quem só deveria ver o próprio projeto.
          #
          # Agora responde à mesma matriz do resto do recurso (DEC-18): OG e Admin
          # CRUD, Gerente leitura, Colaborador nenhum acesso.
          authorize!('users', :read)
          process_service_response(UsersService.find_by_whatsapp(params))
        end
      end

      # ===============================================
      # USERS - LISTAGEM, CRIAÇÃO, VISUALIZAÇÃO, REMOÇÃO (Somente OG)
      # ===============================================
      resource '' do
        desc 'Listar usuários (Somente OG)' do
          summary 'Listar usuários'
          detail 'Retorna usuários com paginação, busca e filtro por tipo.'
          failure [{ code: 403, message: 'Forbidden (Somente OG)' }]
        end

        params do
          optional :q, type: String, desc: 'Busca por nome, email ou telefone'
          optional :type, type: String, desc: 'Filtro por tipo de usuário (og, client)'
          optional :page, type: Integer, default: 1, desc: 'Página'
          optional :per_page, type: Integer, default: 20, desc: 'Itens por página'
        end

        get '', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [403, 'Forbidden'],
          [500, 'Internal Server Error']
        ] do
          # Matriz DEC-18: OG e Admin CRUD; Gerente R; Colaborador nenhum acesso.
          authorize!('users', :read)
          result = UsersService.index(params, actor: acting_user)
          set_pagination_headers(result[:data][:total], result[:data][:page], result[:data][:per_page])
          process_service_response(result)
        end

        desc 'Criar usuário (Somente OG)' do
          summary 'Criar usuário'
          detail 'Cria um novo usuário. Email ou telefone devem ser informados.'
          failure [{ code: 403, message: 'Forbidden (Somente OG)' }]
        end

        params do
          optional :email, type: String, desc: 'Email do usuário'
          optional :phone, type: String, desc: 'Telefone (WhatsApp)'
          optional :name, type: String, desc: 'Nome'
          optional :avatar_url, type: String, desc: 'URL do avatar'
          optional :cpf_cnpj, type: String, desc: 'CPF/CNPJ'
          optional :cep, type: String, desc: 'CEP'
          optional :street, type: String, desc: 'Rua'
          optional :number, type: String, desc: 'Número'
          optional :complement, type: String, desc: 'Complemento'
          optional :district, type: String, desc: 'Bairro'
          optional :city, type: String, desc: 'Cidade'
          optional :state, type: String, desc: 'Estado (UF)'
          optional :state, type: String, desc: 'Estado (UF)'
          optional :user_type_id, type: Integer, desc: 'Tipo de usuário (UserType ID)'
          optional :user_type, type: String, desc: 'Tipo de usuário (Nome/Slug)'
          optional :user_type_slug, type: String, desc: 'Slug do tipo de usuário'
          # **FE-019 — o “Membro padrão” do legado.** Só OG e Admin podem mexer
          # (`users/helper/_body.html.erb:17` desenhava o campo só para eles). O
          # serviço IGNORA o parâmetro para os demais em vez de recusar a
          # requisição inteira: recusar transformaria em erro um payload que o
          # legado simplesmente não oferecia.
          optional :is_default_member, type: Boolean, desc: 'Participa de TODOS os projetos (somente OG/Admin)'
        end

        post '', http_codes: [
          [201, 'Created'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [403, 'Forbidden'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          authorize!('users', :create)
          # DEC-108 — a ability por cima da matriz. `may_create_users` era gate de
          # view no legado (`my_account/_body.html.erb:13`) e alimentava
          # `RoleType.inferior_role_types` (`role_type.rb:19,21`); nenhum dos dois
          # impedia a requisição direta. Agora impede.
          require_permission!('may_create_users')
          # O teto do legado (`registrations/index.html.erb:7`) contava
          # `Livetat::Auth::User.all` — o total de contas do sistema. É essa a
          # contagem, e agora ela é comparada em vez de só exibida.
          enforce_limit!('max_users_amount', User.count)
          process_service_response(UsersService.create(params, actor: acting_user))
        end
      end

      # ===============================================
      # USERS - VALIDAÇÃO DE CPF — BE-035 / IMP-A14
      # ===============================================
      # Os status HTTP do legado estavam errados: **405** (Method Not Allowed) para CPF
      # malformado e **406** (Not Acceptable) para CPF já cadastrado. Nenhum dos dois
      # descreve o que aconteceu, e cliente nenhum sabe tratá-los — 405 fala de verbo
      # HTTP, 406 fala de content negotiation. Aqui é **422** para formato inválido e
      # **409** para conflito de unicidade.
      resource :validate_cpf do
        desc 'Valida CPF (formato e unicidade)' do
          summary 'Validar CPF'
          detail 'Devolve 422 para CPF inválido e 409 para CPF já cadastrado em outra conta.'
        end

        params do
          requires :cpf, type: String, desc: 'CPF com ou sem máscara'
          optional :id, type: String, desc: 'ID do usuário sendo editado (exclui a própria conta do conflito)'
        end

        get '', http_codes: [
          [200, 'CPF válido e disponível'],
          [401, 'Unauthorized'],
          [409, 'CPF já cadastrado'],
          [422, 'CPF inválido']
        ] do
          process_service_response(UsersService.validate_cpf(params))
        end
      end

      # ===============================================
      # USERS - ESTATÍSTICAS (Somente OG)
      # ===============================================
      resource :stats do
        desc 'Estatísticas de usuários (Somente OG)'
        get '', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [403, 'Forbidden']
        ] do
          authorize!('users', :read)
          process_service_response(UsersService.stats(params))
        end
      end

      route_param :id do
        desc 'Buscar usuário por ID (Somente OG)' do
          summary 'Detalhe do usuário'
          failure [{ code: 403, message: 'Forbidden (Somente OG)' }]
        end

        params do
          requires :id, type: String, desc: 'ID do usuário (UUID)'
        end

        get '', http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [403, 'Forbidden'],
          [404, 'Not Found']
        ] do
          authorize!('users', :read)
          process_service_response(UsersService.show(params))
        end

        desc 'Excluir usuário (Somente OG)' do
          summary 'Excluir usuário'
          failure [{ code: 403, message: 'Forbidden (Somente OG)' }]
        end

        params do
          requires :id, type: String, desc: 'ID do usuário (UUID)'
          optional :code, type: String, desc: 'Código de confirmação — obrigatório na auto-remoção (BE-014)'
        end
        delete '', http_codes: [
          [204, 'No Content'],
          [401, 'Unauthorized'],
          [403, 'Forbidden'],
          [404, 'Not Found'],
          [409, 'Conflict — conta é dona de projeto'],
          [422, 'Código de confirmação ausente ou inválido']
        ] do
          # **Auto-remoção não passa pela matriz** (BE-014). A matriz responde "pode
          # remover CONTAS", que é poder administrativo; remover a própria conta é
          # direito do titular. Sem esta linha o Colaborador — o papel mais numeroso —
          # não conseguiria sair do sistema, e a confirmação por código já prova posse.
          auto_remocao = acting_user && acting_user.id.to_s == params[:id].to_s
          unless auto_remocao
            authorize!('users', :destroy)
            # DEC-108 — `may_delete_users` deixa de ser o `if` do botão "Editar"
            # (`users/detail/tabs/_tab_geral.html.erb:3`, onde já estava na
            # permissão errada) e passa a recusar a remoção de verdade.
            require_permission!('may_delete_users')
          end
          process_service_response(UsersService.destroy(params, actor: acting_user))
        end

        # ===============================================
        # USERS - ATUALIZAÇÃO (Somente OG)
        # ===============================================
        desc 'Atualizar usuário (Somente OG)' do
          summary 'Atualizar usuário'
          detail 'Atualiza um usuário existente pelo ID.'
          success [code: 200, message: 'Ok', model: Api::Entities::User]
        end

        params do
          requires :id, type: String, desc: 'ID do usuário (UUID)'
          optional :email, type: String, desc: 'Email do usuário'
          optional :phone, type: String, desc: 'Telefone (WhatsApp)'
          optional :name, type: String, desc: 'Nome'
          optional :avatar_url, type: String, desc: 'URL do avatar'
          optional :cpf_cnpj, type: String, desc: 'CPF/CNPJ'
          optional :cep, type: String, desc: 'CEP'
          optional :street, type: String, desc: 'Rua'
          optional :number, type: String, desc: 'Número'
          optional :complement, type: String, desc: 'Complemento'
          optional :district, type: String, desc: 'Bairro'
          optional :city, type: String, desc: 'Cidade'
          optional :state, type: String, desc: 'Estado (UF)'
          optional :user_type_id, type: Integer, desc: 'Tipo de usuário (UserType)'
          optional :user_type, type: String, desc: 'Tipo de usuário (Nome/Slug)'
          optional :user_type_slug, type: String, desc: 'Slug do tipo de usuário'
          optional :biography, type: String, desc: 'Biografia (ActionText)'
          optional :custom_variables, type: Hash, desc: 'Variáveis customizadas do usuário (JSON)'
          # **FE-019 — o “Membro padrão” do legado.** Só OG e Admin podem mexer
          # (`users/helper/_body.html.erb:17` desenhava o campo só para eles). O
          # serviço IGNORA o parâmetro para os demais em vez de recusar a
          # requisição inteira: recusar transformaria em erro um payload que o
          # legado simplesmente não oferecia.
          optional :is_default_member, type: Boolean, desc: 'Participa de TODOS os projetos (somente OG/Admin)'
        end

        put '', http_codes: [
          [200, 'Ok'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          authorize!('users', :update)
          process_service_response(UsersService.update(params, actor: acting_user))
        end

        patch '', http_codes: [
          [200, 'Ok'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [404, 'Not Found'],
          [422, 'Unprocessable Entity'],
          [500, 'Internal Server Error']
        ] do
          authorize!('users', :update)
          process_service_response(UsersService.update(params, actor: acting_user))
        end

        # ===============================================
        # AVATAR — OPS-493 (motor único de anexos, S13)
        # ===============================================
        # **Regra de fronteira aplicada.** O avatar do Safegold saía por
        # `POST /api/v1/uploads/avatar`, que grava o arquivo cru em
        # `public/uploads/avatars/` e o serve como estático, sem autenticação
        # nenhuma — é o D-82 do legado vivo dentro do produto novo. Aquele endpoint
        # CONTINUA existindo, porque é da base e os outros sistemas dependem dele
        # (Princípio 6b / flag F-09); o Safegold é que passa a usar este.
        #
        # O que muda em relação ao caminho antigo:
        #  - o binário vai para ActiveStorage, privado, com URL assinada de prazo;
        #  - o tipo é conferido pelos magic bytes, não pelo `Content-Type` que o
        #    cliente declarou (o antigo faz `ct.start_with?('image/')` no valor
        #    enviado pelo próprio cliente);
        #  - o limite de 3 MB do legado passa a existir DE FATO (o antigo não tem
        #    limite de tamanho nenhum).
        #
        # A resposta devolve `avatar_url` com o mesmo nome de campo que o front já
        # lê — nenhuma tela precisa aprender um formato novo.
        desc 'Envia o avatar do usuário (ActiveStorage, privado)' do
          detail 'Multipart. O próprio usuário ou quem pode atualizar usuários.'
        end
        params do
          requires :file, type: File, desc: 'Imagem do avatar (máx. 3 MB)'
        end
        post :avatar, http_codes: [
          [200, 'Ok'],
          [401, 'Unauthorized'],
          [403, 'Forbidden'],
          [404, 'Not Found'],
          [422, 'Unprocessable Entity']
        ] do
          user = User.find_by(id: params[:id])
          error!({ error: 'not_found', message: 'Usuário não encontrado.' }, 404) if user.nil?
          # O próprio usuário sempre pode trocar o próprio avatar; para os outros,
          # vale a matriz.
          authorize!('users', :update) unless acting_user&.id.to_s == user.id.to_s

          status_code, result = Sfg::Attachments.attach!(record: user, name: :avatar, files: [params[:file]])
          if status_code == :error
            error!({ error: 'unprocessable_entity', message: result, code: 'ATTACHMENT_REJECTED' }, 422)
          end

          status 200
          { id: user.id, avatar_url: result.reload.display_avatar_url }
        end

        desc 'Remove o avatar do usuário'
        delete :avatar, http_codes: [[200, 'Ok'], [401, 'Unauthorized'], [404, 'Not Found']] do
          user = User.find_by(id: params[:id])
          error!({ error: 'not_found', message: 'Usuário não encontrado.' }, 404) if user.nil?
          authorize!('users', :update) unless acting_user&.id.to_s == user.id.to_s

          user.avatar.purge_later if user.avatar.attached?
          status 200
          { id: user.id, avatar_url: user.reload.display_avatar_url }
        end

        # ===============================================
        # BLOQUEIO DE CONTA — BE-036 / BE-037 (IMP-A15, IMP-A16)
        # ===============================================
        # Bloquear **revoga a sessão ativa na hora**: `User#block!` rotaciona o `jti`,
        # e o access token que a pessoa já tem na aba aberta deixa de casar. Bloqueio
        # que só vale no próximo login não é bloqueio — é aviso.
        #
        # O barramento em si acontece no gate central (`api/root.rb`), com
        # `code: ACCOUNT_BLOCKED` para que a tela de login explique o motivo em vez de
        # deslogar em silêncio (IMP-A17).
        desc 'Bloquear conta' do
          summary 'Bloquear usuário'
          detail 'Grava `blocked_at`, revoga a sessão ativa e audita. Não apaga a conta.'
          failure [{ code: 403, message: 'Usuário fora do alcance de hierarquia' }]
        end
        params do
          requires :id, type: String, desc: 'ID do usuário (UUID)'
          optional :reason, type: String, desc: 'Motivo — exibido ao usuário bloqueado'
        end
        post :block do
          authorize!('users', :update)
          process_service_response(
            UsersService.block(actor: acting_user, target_id: params[:id], reason: params[:reason])
          )
        end

        desc 'Desbloquear conta' do
          summary 'Desbloquear usuário'
          failure [{ code: 403, message: 'Usuário fora do alcance de hierarquia' }]
        end
        delete :block do
          authorize!('users', :update)
          process_service_response(UsersService.unblock(actor: acting_user, target_id: params[:id]))
        end

        # ===============================================
        # CONVITE — BE-012 / OPS-001
        # ===============================================
        desc 'Reenviar convite de primeiro acesso' do
          summary 'Convidar usuário'
          detail 'Emite um magic link de uso único e o envia por e-mail. Nenhuma senha (D-38).'
        end
        post :invite do
          authorize!('users', :create)
          # DEC-108 — no legado `may_invite_users` só escondia o botão
          # (`registrations/index.html.erb:6`). O convite é a ÚNICA porta de
          # entrada do sistema (DEC-18.7), então este é o gate que mais importa
          # dos seis.
          require_permission!('may_invite_users')
          # Teto de convites EM ABERTO emitidos por quem está convidando —
          # convite usado ou vencido libera a vaga.
          enforce_limit!('max_invitations_amount',
                         LoginCode.pending_invitations.where(invited_by_id: acting_user&.id).count)
          process_service_response(UsersService.invite(actor: acting_user, target_id: params[:id]))
        end

        # ===============================================
        # PARTICIPAÇÕES DO USUÁRIO — BE-034
        # ===============================================
        # **Paginada e escopada.** O legado fazia `Project.all` — sem paginação e sem
        # filtro nenhum —, então a aba "Projetos" de um usuário qualquer listava a
        # carteira inteira do sistema para quem abrisse a tela. É vazamento de escopo
        # (família D-100), não lentidão.
        desc 'Projetos de um usuário' do
          summary 'Participações do usuário'
          detail 'Lista paginada e escopada ao que o solicitante pode ver (C1).'
        end
        params do
          requires :id, type: String, desc: 'ID do usuário (UUID)'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get :memberships do
          authorize!('users', :read)
          target = User.find_by(id: params[:id])
          error!({ error: 'not_found', message: 'Usuário não encontrado' }, 404) if target.nil?

          # O recorte é a interseção: os projetos DO ALVO que o SOLICITANTE também
          # alcança. OG enxerga tudo; os demais só o que participam.
          scope = Project.joins(:memberships).where(memberships: { user_id: target.id })
          scope = scope.where(id: Project.for_member(acting_user).select(:id)) unless acting_user&.og?

          projects = paginate(scope.distinct.order(:name))
          { projects: Api::Entities::ProjectOption.represent(projects) }
        end

        # ===============================================
        # PERMISSÕES DO USUÁRIO — BE-018 / D-34
        # ===============================================
        # **O `:id` do usuário PASSA A MANDAR.** No legado
        # (`pub/permissions_controller.rb:55-57`) o `:id` era descartado e
        # qualquer linha de `Ability` era alcançável por URL — o vetor mais
        # direto de escalação de privilégio. Aqui o alvo é carregado e a trava de
        # hierarquia é aplicada contra o papel DELE.
        desc 'Permissões efetivas de um usuário' do
          summary 'Permissões do usuário'
        end
        get :permissions do
          authorize!('permissions', :read)
          target = User.find_by(id: params[:id])
          error!({ error: 'not_found', message: 'Usuário não encontrado' }, 404) if target.nil?
          unless Authorization::Hierarchy.can_edit_user_permissions?(acting_user, target)
            error!({ error: 'forbidden', message: 'Usuário fora do seu alcance de hierarquia.',
                     code: 'HIERARCHY_LOCKED' }, 403)
          end

          process_service_response(PermissionsService.for_user(target_user: target))
        end

        desc 'Concede ou revoga uma permissão de um usuário' do
          summary 'Editar permissão do usuário'
          failure [{ code: 403, message: 'Usuário fora do alcance de hierarquia' }]
        end
        params do
          requires :key, type: String, desc: 'Chave da permissão'
          # DEC-108 — `granted` deixou de ser obrigatório porque duas das sete
          # permissões são **limite**: nelas o que muda é `limit_value`, e um
          # booleano não guarda "50". O serviço recusa a combinação errada.
          optional :granted, type: Boolean, desc: 'Permissão condicional: true concede, false revoga'
          optional :limit_value, type: Integer, desc: 'Permissão de limite: o teto. Vazio remove o override.'
          optional :reason, type: String, desc: 'Motivo — vai para a trilha de auditoria'
        end
        put 'permissions/:key' do
          authorize!('permissions', :update)
          process_service_response(
            PermissionsService.set_user_permission(
              actor: acting_user,
              target_user: User.find_by(id: params[:id]),
              key: params[:key],
              granted: params[:granted],
              limit_value: params.key?(:limit_value) ? params[:limit_value] : :unset,
              reason: params[:reason]
            )
          )
        end
      end

    end
  end
end
