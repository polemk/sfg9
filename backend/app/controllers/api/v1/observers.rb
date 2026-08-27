# frozen_string_literal: true

module Api
  module V1
    # S2 / BE-426..BE-429 — observadores das mensagens administrativas.
    #
    # **D-88 fechado aqui:** o legado lia `limit`/`offset` e **nunca os
    # aplicava** — a lista voltava inteira, sempre. A paginação agora é a mesma
    # do resto do produto (Kaminari, envelope em cabeçalho, teto de `per_page`),
    # e é aplicada de verdade.
    #
    # O gate é `admin_messages`: observador é configuração da caixa de mensagens,
    # e quem administra a caixa administra quem é notificado por ela.
    class Observers < Grape::API
      helpers Api::V1::ControllerHelpers

      namespace :observers do
        before do
          authenticate_user!
        end

        desc 'Lista os observadores' do
          summary 'Observadores'
          detail 'Paginação APLICADA — regressão do D-88.'
        end
        params do
          optional :context, type: String, values: ::AdminMessage::CONTEXTS.keys
          optional :q, type: String
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!('admin_messages', :read)

          result = ObserversService.index(params: params)
          Api::Entities::Observer.represent(paginate(result[:data]))
        end

        desc 'Cadastra um observador'
        params do
          requires :name, type: String
          requires :email, type: String
          # Sem `values:` de propósito. O validador do Grape reprova a lista
          # VAZIA com 400 "não tem um valor válido" — erro de forma para o que é
          # uma regra de domínio. Quem valida é o model: contexto desconhecido é
          # descartado em `Observer#contexts=`, e lista vazia vira 422 com
          # "deve ter ao menos um selecionado", que é o que o usuário precisa ler.
          optional :contexts, type: Array[String], default: []
          optional :is_internal, type: Boolean, default: true
        end
        post '' do
          authorize!('admin_messages', :create)

          attrs = declared(params, include_missing: false).symbolize_keys
          result = ObserversService.create(attrs: attrs, actor: acting_user)
          error!({ error: result[:error], details: result[:details] }, result[:status]) if result[:status] != 201

          status 201
          Api::Entities::Observer.represent(result[:data])
        end

        desc 'Atualiza um observador'
        params do
          requires :id, type: Integer
          optional :name, type: String
          optional :email, type: String
          optional :contexts, type: Array[String] # ver a nota do `create`
          optional :is_internal, type: Boolean
        end
        put ':id' do
          authorize!('admin_messages', :update)

          attrs = declared(params, include_missing: false).symbolize_keys.except(:id)
          result = ObserversService.update(id: params[:id], attrs: attrs, actor: acting_user)
          error!({ error: result[:error], details: result[:details] }, result[:status]) if result[:status] != 200
          Api::Entities::Observer.represent(result[:data])
        end

        desc 'Remove um observador'
        params do
          requires :id, type: Integer
        end
        delete ':id' do
          authorize!('admin_messages', :destroy)

          result = ObserversService.destroy(id: params[:id])
          error!({ error: result[:error] }, result[:status]) if result[:status] != 200
          result[:data]
        end
      end
    end
  end
end
