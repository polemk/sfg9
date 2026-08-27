module Api
  module V1
    class Credentials < Grape::API
      include Api::V1::Defaults

      # **OG e Admin — DEC-61.**
      #
      # Estava `require_og!`, e o menu oferecia `/admin/credentials` a OG **e**
      # Admin (`consoleNavigation.tsx`). Medido abrindo o app como Helena
      # (Admin), nos três modos: a tela sobe com o estado vazio ("Nenhuma
      # credencial cadastrada") **e** o erro "Erro ao carregar credenciais" ao
      # mesmo tempo — os dois na mesma tela, porque o `GET` responde 403.
      #
      # O menu é que estava certo. A DEC-61 escolheu guardar as chaves de
      # terceiro no `Credential` justamente para que **o cliente** trocasse a
      # própria chave sem deploy: *"o cliente troca a propria chave da ReceitaWS,
      # que e paga por consulta"*. O cliente é o Admin — OG é o fornecedor
      # (Livetat, DEC-18.1). Com `require_og!` a decisão não se realizava:
      # trocar a chave voltava a depender da Livetat.
      #
      # Gerente e Colaborador continuam fora, e a rota nem chega até eles (o
      # `RoleRoute` os manda para `/dashboard`).
      before do
        authenticate_user!
        require_role!(:og, :admin)
      end

      resource :credentials do
        desc "List all credentials (with masked keys)"
        get do
          present Credential.order(created_at: :desc), with: Api::Entities::Credential
        end

        desc "Get a specific credential"
        get ":id" do
          credential = Credential.find(params[:id])
          present credential, with: Api::Entities::Credential
        end

        desc "Create a new credential"
        params do
          requires :name, type: String, desc: "Credential name"
          requires :provider, type: String, values: Credential::PROVIDERS, desc: "Provider type"
          requires :api_key, type: String, desc: "API key (will be encrypted)"
        end
        post do
          credential = Credential.create!(
            name: params[:name],
            provider: params[:provider],
            api_key: params[:api_key]
          )
          status 201
          present credential, with: Api::Entities::Credential
        end

        desc "Update a credential"
        params do
          optional :name, type: String, desc: "Credential name"
          optional :api_key, type: String, desc: "New API key (will be encrypted)"
        end
        put ":id" do
          credential = Credential.find(params[:id])
          attrs = declared(params, include_missing: false).except(:id)
          credential.update!(attrs)
          present credential, with: Api::Entities::Credential
        end

        desc "Delete a credential"
        delete ":id" do
          credential = Credential.find(params[:id])
          credential.destroy!
          status 204
          nil
        end
      end
    end
  end
end
