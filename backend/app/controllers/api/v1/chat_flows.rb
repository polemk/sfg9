
module Api
  module V1
    class ChatFlows < Grape::API
      include Api::V1::Defaults

      resource :flows do
        desc "List all chat flows"
        params do
          optional :limit, type: Integer, default: 50, desc: "Limit of records"
          optional :offset, type: Integer, default: 0, desc: "Offset of records"
          optional :search, type: String, desc: "Search term"
        end
        get do
          result = ChatFlowsService.index(params)
          process_service_response(result)
        end

        desc "Return the default flow"
        get :default do
          result = ChatFlowsService.default(params)
          process_service_response(result)
        end

        desc "Get flow by context (user_type and route_path)"
        params do
          requires :user_type, type: String, desc: "User type slug"
          optional :route_path, type: String, desc: "Current page route path"
        end
        get :contextual do
          result = ChatFlowsService.contextual(params)
          process_service_response(result)
        end

        desc "Get a specific flow"
        get ":id" do
          result = ChatFlowsService.show(params)
          process_service_response(result)
        end

        desc "Create a new chat flow"
        params do
          requires :name, type: String, desc: "Flow name"
          optional :kind, type: String, values: %w[chatbot ai_agent], default: "chatbot", desc: "Flow type"
          optional :definition, type: Hash, desc: "React Flow JSON definition", default: { nodes: [], edges: [] }
          optional :agent_config, type: Hash, desc: "AI Agent configuration (model, system_prompt)", default: {}
          optional :keywords, type: Array[String], desc: "Trigger keywords", default: []
          optional :persona_name, type: String, desc: "Persona name"
          optional :persona_description, type: String, desc: "Persona description (header subtitle)"
          optional :persona_avatar, type: String, desc: "Persona avatar URL"
          optional :credential_id, type: Integer, desc: "Associated credential ID for AI agents"
          optional :mapped_routes, type: Array[String], desc: "Routes mapped to this agent", default: []
          optional :override_active_chat, type: Boolean, desc: "Override active chat for mapped routes", default: false
        end
        post do
          result = ChatFlowsService.create(params)
          process_service_response(result)
        end

        desc "Update a chat flow"
        params do
          optional :name, type: String, desc: "Flow name"
          optional :definition, type: Hash, desc: "React Flow JSON definition"
          optional :agent_config, type: Hash, desc: "AI Agent configuration (model, system_prompt)"
          optional :keywords, type: Array[String], desc: "Trigger keywords"
          optional :persona_name, type: String, desc: "Persona name"
          optional :persona_description, type: String, desc: "Persona description (header subtitle)"
          optional :persona_avatar, type: String, desc: "Persona avatar URL"
          optional :is_default, type: Boolean, desc: "Set as default flow"
          optional :credential_id, type: Integer, desc: "Associated credential ID for AI agents"
          optional :mapped_routes, type: Array[String], desc: "Routes mapped to this agent"
          optional :override_active_chat, type: Boolean, desc: "Override active chat for mapped routes"
        end
        put ":id" do
          result = ChatFlowsService.update(params)
          process_service_response(result)
        end

        desc "Delete a chat flow (cannot delete default)"
        delete ":id" do
          result = ChatFlowsService.destroy(params)
          process_service_response(result)
        end

        desc "Set a flow as default"
        put ":id/set_default" do
          result = ChatFlowsService.set_default(params)
          process_service_response(result)
        end
      end
    end
  end
end

