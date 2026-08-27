# frozen_string_literal: true

module Api
  module V1
    module Public
      class Chat < Grape::API
        helpers Api::V1::ControllerHelpers

        resource :chat do
          # Bloco 6 do trim (AI9-006): `GET session`, `GET messages` e
          # `POST message` saíram daqui. Eram o chat PÚBLICO de captação —
          # criavam `Lead` na primeira mensagem, gravavam `LeadMessage` e
          # carregavam o funil (`current_stage`, `discovery_level`,
          # `enchantment_level`, `closing_level`), com o disparo para o n8n
          # (`PublicChatService`). O DEC-13.2 define o chatbot mantido como
          # ASSISTENTE INTERNO do console, que não captura lead — o caminho vivo
          # dele é o `/api/v1/chat` autenticado.
          #
          # Sobraram aqui os dois endpoints que não são de captação:
          # `resolve_assets` (AI9-014, sai no Bloco 7) e `routing` (AI9-007).

          # Bloco 7 do trim (AI9-014): `GET resolve_assets` saiu daqui — resolvia
          # os shortcodes `[asset:XXX]` contra `OperationAsset`, que morreu com o
          # `Operation`. Sobrou `routing`, que é AI9-007.

          desc 'Obter mapeamento de rotas para agentes' do
            summary 'Mapping de rotas'
          end
          get 'routing' do
            # Find all AI agents that have at least one mapped route
            agents = ChatFlow.where(kind: 'ai_agent')
                            .where.not(mapped_routes: [])
                            .order(created_at: :desc)

            agents.map do |agent|
              {
                id: agent.id,
                name: agent.name,
                mapped_routes: agent.mapped_routes,
                override_active_chat: !!agent.override_active_chat,
                persona_name: agent.persona_name,
                persona_avatar: agent.persona_avatar
              }
            end
          end
        end
      end
    end
  end
end
