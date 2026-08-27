# frozen_string_literal: true

module Ai
  module Tools
    # O ESCOPO DE TODA FERRAMENTA DO ASSISTENTE DO CONSOLE (DEC-13.2).
    #
    # O agente conversa; quem decide **o que ele alcança** é este objeto, e ele
    # sozinho. Três perguntas, sempre nesta ordem, antes de qualquer leitura:
    #
    #  1. **Quem é o dono da conversa?** `chat_sessions.user_id` (Bloco 8 do
    #     trim). Sessão sem dono não lê nada — é a mesma regra que fechou o IDOR
    #     do `/chat/*`, e vale aqui porque a ferramenta roda DEPOIS do
    #     controller, sem `current_user` à mão.
    #  2. **Qual é o projeto?** `users.current_project_id` **revalidado contra
    #     `memberships` a cada chamada** (contrato C1). Nunca o id que a sessão
    #     guardou: entre abrir o chat e perguntar, a participação pode ter sido
    #     revogada, e o assistente responderia com o número de um projeto do qual
    #     a pessoa já foi removida.
    #  3. **O papel alcança o recurso?** `Authorization::Matrix`, a mesma matriz
    #     da DEC-18 que o endpoint usa. O assistente **não é uma porta lateral**:
    #     o que a tela esconde do papel, a conversa também esconde. Um agregado
    #     respondido por chat vaza o número sem mostrar a linha — é o D-110 com
    #     outra interface.
    #
    # ## A lista de recursos PROIBIDOS, e por que ela existe além da matriz
    #
    # A matriz diria "sim" para um OG perguntando de `users` ou `audit_trail`.
    # O uso definido no DEC-13.2 é **ajuda ao operador**, não console de
    # administração por conversa: conta, permissão, credencial, trilha e
    # impersonação ficam fora **para todos os papéis**, inclusive OG. Nenhum
    # handler toca nesses modelos — a constante existe para que isso seja uma
    # regra verificável (`console_scope_spec`) em vez de uma característica
    # acidental do conjunto de handlers que existe hoje.
    class ConsoleScope
      # Administração e dado sensível: fora da conversa, para todo papel.
      FORBIDDEN_RESOURCES = %w[
        users memberships permissions user_types
        audit_trail impersonation
        admin_messages contract_versions
        help_items help_categories help_groups
        console
      ].freeze

      # Motivos de recusa. São devolvidos ao modelo como texto e chegam ao
      # usuário parafraseados — por isso dizem o que fazer, não o que falhou.
      SEM_DONO    = 'Não consigo identificar quem está falando comigo. Recarregue a página e abra o assistente de novo.'
      SEM_PROJETO = 'Nenhum projeto está selecionado. Escolha um no seletor da barra superior e pergunte de novo.'
      SEM_ACESSO  = 'Seu perfil não alcança esses dados.'

      def initialize(session)
        @session = session
      end

      def user
        return @user if defined?(@user)

        @user = @session.respond_to?(:user) ? @session.user : nil
      end

      # O projeto corrente, revalidado — **a mesma resolução do
      # `resolve_current_project`**, e ela é copiada de propósito em vez de
      # aproximada:
      #
      #  - preferência gravada, sempre conferida contra `memberships`;
      #  - sem preferência, participação em exatamente UM projeto é esse projeto.
      #
      # O segundo ramo parece detalhe e não é. Sem ele, quem participa de um
      # projeto só e nunca tocou no seletor vê os números na tela — porque o
      # endpoint aplica o fallback — e ouve "escolha um projeto" do assistente
      # que roda dentro daquela mesma tela. Discordar da tela é pior que não
      # responder.
      #
      # **Não há como ler o `X-Project-Id` daqui** (a ferramenta roda fora do
      # ciclo do controller). Na prática nada diverge: o cliente não manda esse
      # cabeçalho — trocar de projeto é um `PUT` que grava a coluna, e é a coluna
      # que os dois lados leem.
      def project
        return @project if defined?(@project)

        @project =
          if user.nil?
            nil
          elsif user.current_project_id.present?
            ::Project.visible_to(user).find_by(id: user.current_project_id)
          else
            visiveis = ::Project.visible_to(user)
            visiveis.count == 1 ? visiveis.first : nil
          end
      end

      def role
        user&.user_type&.name
      end

      def allow?(resource)
        return false if FORBIDDEN_RESOURCES.include?(resource.to_s)

        ::Authorization::Matrix.allow?(role, resource, :read)
      end

      # Portão único das ferramentas de DADO: dono + projeto + recurso.
      # Devolve `nil` quando pode seguir, ou o `{ success: false }` pronto.
      def block_for_data(resource)
        return failure(SEM_DONO) if user.nil?
        return failure(SEM_ACESSO) unless allow?(resource)
        return failure(SEM_PROJETO) if project.nil?

        nil
      end

      # Portão das ferramentas de AJUDA: só dono + recurso. Ajuda de tela não é
      # dado de projeto — negá-la por falta de seleção deixaria o assistente mudo
      # justamente para quem acabou de entrar e ainda não escolheu nada.
      def block_for_help(resource)
        return failure(SEM_DONO) if user.nil?
        return failure(SEM_ACESSO) unless allow?(resource)

        nil
      end

      def failure(message)
        { success: false, message: message }
      end
    end
  end
end
