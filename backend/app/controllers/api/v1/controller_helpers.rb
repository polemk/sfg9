# frozen_string_literal: true

module Api
  module V1
    # Helpers compartilhados por todo `/api/v1/*`.
    #
    # Aqui moram os dois contratos transversais da migração:
    #  - **C1** (escopo por projeto): `current_project!`;
    #  - **C3** (papel e hierarquia): `authorize!`, `require_role!`,
    #    `require_not_readonly!`.
    #
    # Nenhum endpoint decide autorização nem escopo sozinho.
    module ControllerHelpers
      # Chave que o `Api::Root` grava no env com o id do usuário REAL quando a
      # sessão é de impersonação.
      TRUE_USER_ENV_KEY = 'api.true_user_id'

      # Rotas que `user_is_readonly` **nunca** bloqueia (DC-09 / tarefa 3.4).
      #
      # O aceite dos Termos pelo próprio usuário é a exceção obrigatória: o
      # readonly tira C/U/D, mas se tirar também o aceite, o usuário readonly
      # nunca aceita os Termos e fica trancado fora do sistema.
      #
      # Quando a fatia de Contratos entrar, a rota real de aceite tem de estar
      # nesta lista — está escrita como padrão de caminho de propósito, para que
      # o gate global não precise conhecer o recurso.
      READONLY_EXEMPT_PATHS = [
        %r{^/api/v1/contracts/[^/]+/accept/?$},
        %r{^/api/v1/me/terms/?$}
      ].freeze

      def process_service_response(response)
        status response[:status]

        if (200..299).include?(response[:status])
          response[:data]
        else
          error!(error_payload_for(response), response[:status])
        end
      end

      # **Forma única de erro: `{error, message, code}`** (api/CONTRATO.md §3, FE-516).
      #
      # Antes o corpo era `{ error: <mensagem inteira> }` e o `code` era descartado no
      # caminho. O front lê `data.code` para decidir o que mostrar
      # (`lib/api/client.ts:93`), então um 403 de conta bloqueada chegava
      # indistinguível de um 403 qualquer — e virava logout mudo, que é o IMP-A17.
      #
      # `error` é o identificador estável (`account_blocked`), `message` é o texto para
      # o humano, `code` é a constante que o cliente casa. Não se troca um pelo outro.
      def error_payload_for(response)
        payload = {
          error: response[:error] || response[:message] || 'error',
          message: response[:message] || response[:error]
        }
        payload[:code] = response[:code] if response[:code]
        payload[:details] = response[:details] if response[:details]
        payload
      end

      # ---------------------------------------------------------------------
      # Paginação — DEC-62 (Kaminari no backend, `PaginationPill` no front)
      # ---------------------------------------------------------------------
      # **O envelope vai em CABEÇALHO, não no corpo.** Decidido uma vez, vale
      # para todos os endpoints de lista: é o que a base já fazia
      # (`set_pagination_headers`) e o que o irmão `apl9` já roda em produção
      # (`api/v1/integrations.rb:24`). Colocar no corpo obrigaria a mudar o
      # formato de resposta de todo endpoint existente, e é o caminho para
      # acabar "meio a meio" — que é justamente o que a decisão proíbe.
      #
      # `X-Total-Pages` é acrescentado porque o `PaginationPill` espera
      # `totalPages`; derivar no cliente é onde os dois lados divergem.
      DEFAULT_PER_PAGE = 20
      MAX_PER_PAGE = 100

      def set_pagination_headers(total, page, per_page)
        page = normalize_page(page)
        per_page = normalize_per_page(per_page)
        header 'X-Total-Count', total.to_s
        header 'X-Page', page.to_s
        header 'X-Per-Page', per_page.to_s
        header 'X-Total-Pages', (total.to_f / per_page).ceil.to_s
      end

      # Aplica Kaminari e emite os cabeçalhos. Devolve a relação paginada.
      def paginate(scope, page: params[:page], per_page: params[:per_page])
        page = normalize_page(page)
        per_page = normalize_per_page(per_page)
        paginated = scope.page(page).per(per_page)
        set_pagination_headers(paginated.total_count, page, per_page)
        paginated
      end

      def normalize_page(value)
        [value.to_i, 1].max
      end

      def normalize_per_page(value)
        value = value.to_i
        value = DEFAULT_PER_PAGE if value <= 0
        [value, MAX_PER_PAGE].min
      end

      # ---------------------------------------------------------------------
      # Sessão
      # ---------------------------------------------------------------------
      def authenticate_user!
        user = env['api.current_user']
        error!({ error: 'unauthorized', message: 'Não autenticado' }, 401) unless user
        @current_user = user
      end

      def current_user
        @current_user ||= env['api.current_user']
      end

      # O usuário REAL do ato. Em sessão de impersonação é quem iniciou a
      # impersonação, não quem está sendo visto.
      #
      # É este que a trilha registra (`whodunnit`, DEC-59 #3) e este que decide
      # autorização em recurso administrativo (BE-041): senão o OG impersona um
      # Colaborador e a trilha diz que o Colaborador fez o que o OG fez, que é o
      # oposto do ponto de ter trilha.
      def true_user
        return @true_user if defined?(@true_user)

        @true_user = env[TRUE_USER_ENV_KEY].present? ? User.find_by(id: env[TRUE_USER_ENV_KEY]) : nil
      end

      def impersonating?
        true_user.present?
      end

      # Quem responde por autorização administrativa: o usuário real.
      def acting_user
        true_user || current_user
      end

      # ---------------------------------------------------------------------
      # C3 — papel, matriz e readonly
      # ---------------------------------------------------------------------
      def require_og!
        return if env['api.current_client'].present?
        return if acting_user&.og?

        error!({ error: 'forbidden', message: 'Somente usuários OG', code: 'ROLE_REQUIRED' }, 403)
      end

      # `require_role!(:og, :admin)` — coerente com `require_og!`.
      def require_role!(*roles)
        return if env['api.current_client'].present?

        allowed = roles.flatten.map { |r| r.to_s.downcase }
        return if allowed.include?(acting_user&.user_type&.name.to_s.downcase)

        error!({
                 error: 'forbidden',
                 message: 'Seu perfil não tem acesso a este recurso.',
                 code: 'ROLE_REQUIRED'
               }, 403)
      end

      # O gate declarativo: o endpoint diz **qual recurso** e **qual ação**, e a
      # matriz de `.migration-ai9/authorization-matrix.md` (DEC-18) responde.
      #
      # `authorize!` não sabe nada de escopo — ter acesso ao recurso não é ter
      # acesso ao registro. O escopo é `current_project!`.
      def authorize!(resource, action)
        return if env['api.current_client'].present?

        user = acting_user
        error!({ error: 'unauthorized', message: 'Não autenticado' }, 401) if user.nil?

        return if Authorization::Matrix.allow?(user.user_type&.name, resource, action)

        error!({
                 error: 'forbidden',
                 message: 'Seu perfil não tem acesso a este recurso.',
                 code: 'ROLE_REQUIRED'
               }, 403)
      end

      def permission_resolver
        @permission_resolver ||= Authorization::PermissionResolver.new(current_user)
      end

      # ---------------------------------------------------------------------
      # DEC-108 — as 7 abilities com efeito real, checadas NO SERVIDOR
      # ---------------------------------------------------------------------
      #
      # No legado seis das sete eram **só CSS**: o gate vivia na view, então
      # bastava chamar a rota fora da tela para fazer tudo (a família do D-34).
      # A DEC-30 replica regra, cálculo e dado do legado, mas abre exceção
      # explícita para **segurança e autorização** — replicar um gate de view
      # seria portar a vulnerabilidade, não a paridade.
      #
      # A ability é a camada de cima da matriz, não a substitui: `authorize!`
      # responde "este PAPEL alcança o recurso"; isto responde "esta CONCESSÃO
      # ainda está de pé". Um endpoint que precisa das duas chama as duas.
      #
      # Quem responde é o **usuário real** (`acting_user`, BE-041): estas seis
      # são poder administrativo, e um OG personificando um Colaborador não pode
      # perdê-lo — nem o contrário.
      def require_permission!(key)
        return if env['api.current_client'].present?

        user = acting_user
        error!({ error: 'unauthorized', message: 'Não autenticado' }, 401) if user.nil?
        return if Authorization::PermissionResolver.new(user).granted?(key)

        error!({
                 error: 'forbidden',
                 message: 'Seu perfil não tem esta permissão.',
                 code: 'PERMISSION_REQUIRED',
                 details: { code: 'PERMISSION_REQUIRED', permission: key.to_s }
               }, 403)
      end

      # O par numérico do anterior, para as duas permissões do tipo `limit`
      # (`max_users_amount`, `max_invitations_amount`).
      #
      # **422, não 403.** Um 403 diz "você não pode fazer isto"; aqui a pessoa
      # pode — o que acabou foi a cota. Quem chama passa a contagem REAL, não uma
      # estimativa: o legado só exibia `"#{@users.size}/#{max}"` na barra de
      # título (`registrations/index.html.erb:7`) e nunca comparava nada.
      #
      # Teto ausente (`NULL`) é **sem limite** e nunca estoura; `0` é **nenhum
      # permitido** e estoura sempre. Os dois existem no seed do legado.
      def enforce_limit!(key, count)
        return if env['api.current_client'].present?

        user = acting_user
        return if user.nil?

        resolver = Authorization::PermissionResolver.new(user)
        return unless resolver.limit_exceeded?(key, count)

        error!({
                 error: 'unprocessable_entity',
                 message: "Limite atingido: o seu perfil permite no máximo #{resolver.limit_for(key)}.",
                 code: 'LIMIT_EXCEEDED',
                 details: { code: 'LIMIT_EXCEEDED', permission: key.to_s,
                            limit: resolver.limit_for(key), current: count }
               }, 422)
      end

      def readonly?
        permission_resolver.readonly?
      end

      # Generaliza o `restrict_visitor_access!` que a base tinha: o predicado
      # deixa de ser "é do tipo visitor" (tipo removido pelo DEC-41) e passa a
      # ser "tem concessão ativa de `user_is_readonly`" — a única das 17
      # abilities do legado que sobrevive (DEC-18.6), promovida de flag de view
      # a checagem de servidor.
      #
      # O gate em si já existia e já rodava em todo `/api/v1/*`; o 403 com `code`
      # já é tratado pelo front (`lib/api/client.ts`). O que muda é o predicado.
      def require_not_readonly!
        return if request.get? || request.head?
        return if readonly_exempt_path?
        return unless readonly?

        error!({
                 error: 'forbidden',
                 message: 'Modo Somente Leitura: seu perfil não permite alterações.',
                 code: 'READONLY_RESTRICTED'
               }, 403)
      end

      def readonly_exempt_path?
        READONLY_EXEMPT_PATHS.any? { |pattern| request.path.match?(pattern) }
      end

      # ---------------------------------------------------------------------
      # C1 — escopo por projeto
      # ---------------------------------------------------------------------
      # Peça 3 do contrato. Resolve o projeto corrente **no servidor** e o
      # revalida contra `memberships` a cada request.
      #
      # Duas condições que não podem faltar (DC-08):
      #
      #  1. **O valor armazenado é revalidado a cada request.** `users.current_project_id`
      #     é preferência, não autorização — sem revalidar, uma participação
      #     revogada continuaria valendo até o usuário deslogar.
      #  2. **Projeto inexistente e projeto sem participação respondem o MESMO
      #     status (404).** Distinguir 403 de 404 transforma este helper num
      #     oráculo de existência de ids: um Colaborador de um projeto
      #     enumeraria os ids de todos os outros.
      #
      # Precedência: `X-Project-Id` (suporte a duas abas) > `users.current_project_id`
      # > única participação do usuário. O `project_id` que vem no CORPO da
      # requisição é **sempre ignorado** — nem é lido aqui.
      #
      # Leitura não grava (DB-397): nenhum GET escreve `current_project_id`. O
      # legado regravava o projeto padrão a cada GET, e uma aba aberta noutro
      # projeto trocava o projeto da outra.
      # **Três situações diferentes, três respostas diferentes.** Antes daqui
      # todas caíam no mesmo 404 `PROJECT_NOT_FOUND`, e a tela mostrava "Projeto
      # não encontrado." para quem simplesmente ainda não tinha escolhido um —
      # uma mensagem que acusa o usuário de um erro que ele não cometeu e não
      # diz o que fazer.
      #
      # A distinção **não** enfraquece a proteção anti-enumeração da condição 2.
      # Aquela regra existe para não revelar a EXISTÊNCIA de projeto ALHEIO: por
      # isso "id inexistente" e "id existente sem participação" continuam
      # respondendo exatamente o mesmo 404. Quantos projetos o usuário tem não é
      # segredo dele para ele mesmo — dizer "você não escolheu" ou "você não
      # participa de nenhum" não revela nada sobre id de terceiro.
      def current_project!
        project = resolve_current_project
        return project unless project.nil?

        # Pediu um projeto específico e ele não está visível: pode não existir e
        # pode não ser dele. **Mesma resposta para os dois casos** — condição 2.
        #
        # "Pedido" inclui a preferência GRAVADA, não só o header. O spec de
        # participação revogada pegou isto: um usuário com `current_project_id`
        # apontando para projeto de onde foi removido caía no 409 de "você não
        # participa de nenhum", que **vaza** que o id guardado deixou de valer e
        # ainda por cima troca um 404 por uma tela de convite. Preferência
        # gravada é pedido explícito igual ao header.
        project_not_found! if candidate_project_id.present?

        # Não pediu nenhum. Então o que falta é escolha — ou participação.
        visiveis = Project.visible_to(current_user).limit(2).count
        visiveis.zero? ? project_none_available! : project_not_selected!
      end

      # Versão que não aborta — para endpoint que funciona com ou sem projeto.
      def current_project
        @current_project ||= resolve_current_project
      end

      def resolve_current_project
        return @current_project if defined?(@current_project) && @current_project

        user = current_user
        return nil if user.nil?

        candidate_id = requested_project_id.presence || user.current_project_id

        @current_project =
          if candidate_id.present?
            # A verdade é a linha de `memberships`, sempre — inclusive para o
            # valor que já estava gravado na coluna.
            Project.visible_to(user).find_by(id: candidate_id)
          else
            # Sem preferência: se o usuário participa de exatamente um projeto,
            # é esse. Com vários, o cliente precisa escolher (X-Project-Id).
            scope = Project.visible_to(user)
            scope.count == 1 ? scope.first : nil
          end
      end

      # O id pedido, venha do header ou da coluna. Extraído porque o
      # `current_project!` precisa saber se houve pedido explícito para escolher
      # entre "não encontrado" e "não escolhido".
      def requested_project_id
        headers['X-Project-Id'] || headers['x-project-id'] || env['HTTP_X_PROJECT_ID']
      end

      # O id efetivamente pedido: header tem precedência, a coluna é o resto.
      # É a MESMA precedência do `resolve_current_project` — de propósito, para
      # que "o que foi pedido" e "o que foi resolvido" nunca discordem.
      def candidate_project_id
        requested_project_id.presence || current_user&.current_project_id
      end

      # 404, nunca 403 — ver a condição 2 acima. **Não relaxar**: distinguir
      # "não existe" de "não é seu" transforma este helper num oráculo de ids.
      def project_not_found!
        error!({
                 error: 'not_found',
                 message: 'Projeto não encontrado.',
                 code: 'PROJECT_NOT_FOUND'
               }, 404)
      end

      # O usuário TEM projetos e não escolheu nenhum. Não é erro dele: é um
      # passo que falta. 409 em vez de 404 justamente para a tela conseguir
      # distinguir e mostrar o seletor em vez de uma página de erro.
      def project_not_selected!
        error!({
                 error: 'conflict',
                 message: 'Escolha um projeto para ver estes dados.',
                 code: 'PROJECT_NOT_SELECTED'
               }, 409)
      end

      # O usuário não participa de NENHUM projeto visível. A saída não está com
      # ele — está com quem administra —, então a mensagem diz isso em vez de
      # mandá-lo escolher algo que não existe para ele.
      def project_none_available!
        error!({
                 error: 'conflict',
                 message: 'Você ainda não participa de nenhum projeto. Peça a um administrador para incluir você.',
                 code: 'PROJECT_NONE_AVAILABLE'
               }, 409)
      end
    end
  end
end
