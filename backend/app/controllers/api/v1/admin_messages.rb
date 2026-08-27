# frozen_string_literal: true

module Api
  module V1
    # S2 / BE-424, BE-425, BE-531, BE-532 — mensagens administrativas.
    #
    # **Autorização (C3):** `authorize!('admin_messages', …)` — OG e Admin
    # administram, o Gerente **não alcança**, o Colaborador lê. É a linha da
    # matriz aprovada, e não um `if` aqui dentro.
    #
    # **Autenticação do envio (DEC-40 / P-056):** o `POST` exige sessão. No
    # legado o `create` era isento **de propósito**
    # (`feedback19/.../messages_controller.rb:6`) e o único filtro restante fazia
    # **bypass total** quando o formato era HTML ou JS
    # (`auth_ux19/.../application_controller.rb:21-27`) — e o console usava
    # `format: :js`, então o endpoint era efetivamente público. Com o cadastro
    # público desligado (DEC-18.7) não sobra visitante legítimo para o canal
    # anônimo. **`BE-531` sai da allowlist pública** e não há nada a acrescentar
    # em `Api::Root`: rota que não está lá já exige token.
    class AdminMessages < Grape::API
      helpers Api::V1::ControllerHelpers

      namespace :admin_messages do
        before do
          authenticate_user!
        end

        desc 'Lista as mensagens administrativas' do
          summary 'Mensagens'
          detail 'Filtros por situação, contexto e busca. O total do cabeçalho RESPEITA os filtros (BE-424).'
        end
        params do
          optional :state, type: String, values: ::AdminMessage::STATES.keys
          optional :context, type: String, values: ::AdminMessage::CONTEXTS.keys
          optional :q, type: String
          optional :favorite, type: Boolean
          optional :unread, type: Boolean
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!('admin_messages', :read)

          result = AdminMessagesService.index(params: params)
          # `paginate` emite `X-Total-Count` a partir do escopo JÁ FILTRADO.
          # Era exatamente aqui que o legado errava: `Message.all.count`.
          Api::Entities::AdminMessage.represent(paginate(result[:data]))
        end

        desc 'Situações e contextos disponíveis' do
          summary 'Vocabulário das mensagens'
          detail 'Chave estável + rótulo pt-BR. Substitui as tabelas de referência da engine (OPS-507).'
        end
        get :vocabulary do
          authorize!('admin_messages', :read)

          {
            states: ::AdminMessage::STATES.map { |key, label| { key: key, label: label } },
            contexts: ::AdminMessage::CONTEXTS.map { |key, label| { key: key, label: label } }
          }
        end

        desc 'Detalhe da mensagem, com a thread' do
          summary 'Mensagem'
          detail 'Abrir uma mensagem "Não lido" a move para "Lido" (BE-527).'
        end
        params do
          requires :id, type: String, desc: 'Id, token público ou token privado'
        end
        get ':id' do
          authorize!('admin_messages', :read)

          result = AdminMessagesService.show(id: params[:id], admin: acting_user)
          error!({ error: result[:error] }, result[:status]) if result[:status] != 200
          Api::Entities::AdminMessage.represent(result[:data], full: true)
        end

        desc 'Envia uma mensagem administrativa' do
          summary 'Nova mensagem'
          detail 'Autenticado por padrão — DEC-40. O honeypot anti-bot do legado não é portado.'
        end
        params do
          requires :message, type: String
          optional :sender_name, type: String
          optional :sender_email, type: String
          optional :context, type: String, values: ::AdminMessage::CONTEXTS.keys, default: 'other'
          optional :is_internal, type: Boolean, default: false
          optional :extra1_enabled, type: Boolean
          optional :extra1_label, type: String
          optional :extra1_value, type: String
          optional :extra2_enabled, type: Boolean
          optional :extra2_label, type: String
          optional :extra2_value, type: String
        end
        post '' do
          # Qualquer usuário autenticado pode ENVIAR — `my_account` é o recurso
          # que todo papel tem. Ler e administrar a caixa é que é de OG/Admin.
          authorize!('my_account', :read)

          attrs = declared(params, include_missing: false).symbolize_keys
          result = AdminMessagesService.create(attrs: attrs, sender: current_user)
          error!({ error: result[:error], details: result[:details] }, result[:status]) if result[:status] != 201

          status 201
          Api::Entities::AdminMessage.represent(result[:data])
        end

        desc 'Atualiza situação, leitura e favorito' do
          summary 'Atualizar mensagem'
          detail 'DEC-73: pedir "Concluído" grava "Fechado" — a inversão do legado é REPLICADA, e travada por golden test.'
        end
        params do
          requires :id, type: String
          optional :state, type: String, values: ::AdminMessage::STATES.keys
          optional :is_read, type: Boolean
          optional :is_favorite, type: Boolean
        end
        put ':id' do
          authorize!('admin_messages', :update)

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          result = AdminMessagesService.update(id: params[:id], attrs: attrs, admin: acting_user)
          error!({ error: result[:error], details: result[:details] }, result[:status]) if result[:status] != 200
          Api::Entities::AdminMessage.represent(result[:data])
        end

        desc 'Encerra a mensagem' do
          summary 'Encerrar'
          detail 'O outro lado da inversão do DEC-73: esta ação grava "Concluído".'
        end
        params do
          requires :id, type: String
        end
        put ':id/close' do
          authorize!('admin_messages', :update)

          result = AdminMessagesService.close(id: params[:id], admin: acting_user)
          error!({ error: result[:error] }, result[:status]) if result[:status] != 200
          Api::Entities::AdminMessage.represent(result[:data])
        end

        desc 'Responde na thread' do
          summary 'Nova resposta'
        end
        params do
          requires :id, type: String
          requires :description, type: String
        end
        post ':id/notes' do
          authorize!('admin_messages', :update)

          result = AdminMessagesService.add_note(id: params[:id], description: params[:description],
                                                 admin: acting_user)
          error!({ error: result[:error], details: result[:details] }, result[:status]) if result[:status] != 201

          status 201
          Api::Entities::MessageNote.represent(result[:data])
        end

        desc 'Remove a mensagem'
        params do
          requires :id, type: String
        end
        delete ':id' do
          authorize!('admin_messages', :destroy)

          result = AdminMessagesService.destroy(id: params[:id])
          error!({ error: result[:error] }, result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
