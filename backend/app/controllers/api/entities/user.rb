# frozen_string_literal: true

module Api
  module Entities
    class User < Grape::Entity
      expose :id
      expose :email
      expose :phone
      expose :name
      # Regra de fronteira: o NOME e a forma do campo não mudam (o front lê
      # `avatarUrl` em UserAvatar, Sidebar, ConsoleTopbar, trilha…). O que muda é
      # de onde o valor vem: anexo ActiveStorage quando houver, senão a URL do
      # OAuth que já estava na coluna. Nenhum consumidor precisa ser tocado.
      expose :avatar_url do |user, _opts|
        user.respond_to?(:display_avatar_url) ? user.display_avatar_url : user.avatar_url
      end
      expose :cpf_cnpj, if: ->(user, _opts) { user.respond_to?(:cpf_cnpj) }
      expose :cep, if: ->(user, _opts) { user.respond_to?(:cep) }
      expose :street, if: ->(user, _opts) { user.respond_to?(:street) }
      expose :number, if: ->(user, _opts) { user.respond_to?(:number) }
      expose :complement, if: ->(user, _opts) { user.respond_to?(:complement) }
      expose :district, if: ->(user, _opts) { user.respond_to?(:district) }
      expose :city, if: ->(user, _opts) { user.respond_to?(:city) }
      expose :state, if: ->(user, _opts) { user.respond_to?(:state) }
      expose :user_type_id
      expose :is_og do |user, _opts|
        user.og?
      end
      expose :user_type, as: :user_type do |user|
        user.user_type&.display_name
      end
      expose :user_type_slug do |user|
        user.user_type&.name
      end
      expose :last_login_at
      expose :login_count

      # --- Identidade Safegold (S1) ---------------------------------------
      # `identifier` é o código curto que o usuário dita por telefone (BE-048);
      # `username` é a terceira chave de identidade (DEC-45) e aparece porque a tela de
      # conta precisa mostrar por qual nome a pessoa entra.
      expose :identifier
      expose :username
      # DEC-39 — a listagem administrativa mostra o selo de conta bloqueada. Sem expor
      # isto, bloquear vira uma ação sem confirmação visível: o administrador clica e a
      # lista continua igual.
      expose :blocked_at
      expose :blocked_reason
      expose :is_blocked do |user|
        user.respond_to?(:blocked?) ? user.blocked? : false
      end
      # DEC-74 — indicador "Verificação: {nível}", replicado como está. Decorativo: o
      # produto não decide nada com ele.
      expose :confiability_level do |user|
        user.respond_to?(:confiability_level) ? user.confiability_level : nil
      end
      # --- Perfil estendido (DEC-74 / tarefa 1.1) --------------------------
      #
      # **Regra de fronteira aplicada a um campo, não a uma rota.** As seis colunas
      # existem no banco desde a migration da tarefa 1.1 e `PATCH /auth/v1/me` já as
      # aceitava (`Auth::MeService#update`) — mas a entity **não as expunha**. Efeito
      # medido: a tela de perfil gravava e, ao recarregar, os campos voltavam vazios;
      # o dado estava lá, invisível. Caminho de escrita sem caminho de leitura é
      # exatamente a metade de fronteira que esta migração aprendeu a procurar.
      #
      # `is_phone_checked` entra junto porque é o degrau "Máxima" do indicador de
      # verificação, e sem ele a tela não consegue explicar por que o nível parou.
      # Ele **não** trava a edição do telefone (a trava do legado não é replicada).
      expose :gender, if: ->(user, _opts) { user.respond_to?(:gender) }
      expose :birthday, if: ->(user, _opts) { user.respond_to?(:birthday) }
      expose :cnpj, if: ->(user, _opts) { user.respond_to?(:cnpj) }
      expose :fiscal_document_number, if: ->(user, _opts) { user.respond_to?(:fiscal_document_number) }
      expose :fiscal_document_issued_at, if: ->(user, _opts) { user.respond_to?(:fiscal_document_issued_at) }
      expose :graduation, if: ->(user, _opts) { user.respond_to?(:graduation) }
      expose :is_phone_checked, if: ->(user, _opts) { user.respond_to?(:is_phone_checked) }

      expose :is_default_member, if: ->(user, _opts) { user.respond_to?(:is_default_member) }
      expose :created_at
      expose :updated_at
      expose :biography_html, if: lambda { |user, _opts|
        user.respond_to?(:biography) && begin
          ActiveRecord::Base.connection.data_source_exists?('action_text_rich_texts')
        rescue StandardError
          false
        end
      } do |user|
        user.biography&.body&.to_s
      end
      expose :biography_text, if: lambda { |user, _opts|
        user.respond_to?(:biography) && begin
          ActiveRecord::Base.connection.data_source_exists?('action_text_rich_texts')
        rescue StandardError
          false
        end
      } do |user|
        user.biography&.to_plain_text
      end

      expose :custom_variables

      # **IMP-A24 — o N+1 morre aqui.**
      #
      # Este bloco disparava UMA consulta por usuário: uma listagem de 100 contas fazia
      # 101 idas ao banco, e a conta piorava sozinha à medida que a base crescesse —
      # sem erro nenhum, só a tela ficando lenta.
      #
      # Agora a associação `user_permissions` (com `permission` pré-carregada pelo
      # `includes` do `UsersService.index`) é lida da memória. Quando o chamador NÃO
      # pré-carregou, o `loaded?` é falso e o fallback consulta — correto nos dois
      # casos, rápido no caso que importa, que é a lista.
      expose :permissions do |user|
        records =
          if user.association(:user_permissions).loaded?
            user.user_permissions
          else
            ::UserPermission.where(user_id: user.id).includes(:permission)
          end

        records.filter_map do |up|
          permission = up.permission
          next if permission.nil?

          {
            key: permission.key,
            title: permission.title,
            granted_at: up.granted_at,
            revoked_at: up.revoked_at
          }
        end
      end
    end
  end
end
