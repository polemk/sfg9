# frozen_string_literal: true

class ChatFlowsService
  class << self
    include ApiResponseHandler

    def index(params)
      limit = (params[:limit] || 50).to_i
      offset = (params[:offset] || 0).to_i
      q = params[:search].to_s.strip

      begin
        scope = ChatFlow.all

        if q.present?
          like_query = "%#{q.downcase}%"
          # Search in name, persona_name, and keywords array using ILIKE or equivalent.
          # Since keywords is an array of strings, we use the ANY operator for searching.
          # And we also search inside the jsonb agent_config
          
          # Construct an array of words to search within keywords array (case insensitive)
          # using Postgres ILIKE ANY (ARRAY[...]) or just casting array to text.
          # A simpler approach that works across PG arrays and jsonb is casting to text.
          
          scope = scope.where(
            "LOWER(name) LIKE :q OR LOWER(persona_name) LIKE :q OR array_to_string(keywords, ',') ILIKE :q OR agent_config::text ILIKE :q",
            q: like_query
          )
        end

        total = scope.except(:limit, :offset, :order).count
        flows = scope.order(is_default: :desc, updated_at: :desc).limit(limit).offset(offset)
        
        data = { flows: Api::Entities::ChatFlow.represent(flows), total: total, limit: limit, offset: offset }
        success_response(data, 200)
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    def show(params)
      flow = ChatFlow.find_by(id: params[:id])
      return not_found_response('Fluxo') unless flow

      success_response(Api::Entities::ChatFlow.represent(flow), 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def create(params)
      attrs = params.slice(:name, :kind, :definition, :agent_config, :keywords, :persona_name, :persona_avatar, :credential_id, :mapped_routes, :override_active_chat).compact

      flow = ChatFlow.create!(attrs)
      success_response(Api::Entities::ChatFlow.represent(flow), 201)
    rescue ActiveRecord::RecordInvalid => e
      validation_error_response(e.message)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def update(params)
      id = params.delete(:id)
      flow = ChatFlow.find_by(id: id)
      return not_found_response('Fluxo') unless flow

      begin
        update_params = params.slice(:name, :definition, :agent_config, :keywords, :persona_name, :persona_description, :persona_avatar, :credential_id, :is_default, :mapped_routes, :override_active_chat).compact
        flow.update!(update_params)
        success_response(Api::Entities::ChatFlow.represent(flow), 200)
      rescue ActiveRecord::RecordInvalid => e
       validation_error_response(e.message)
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    def destroy(params)
      flow = ChatFlow.find_by(id: params[:id])
      return not_found_response('Fluxo') unless flow

      if flow.is_default
        return error_response({ error: 'O fluxo padrão não pode ser removido.' }, 403)
      end

      flow.destroy!
      success_response({ success: true }, 200)
    rescue StandardError => e
      internal_error_response(e.message)
    end

    def set_default(params)
      flow = ChatFlow.find_by(id: params[:id])
      return not_found_response('Fluxo') unless flow

      begin
        flow.update!(is_default: true)
        success_response(Api::Entities::ChatFlow.represent(flow), 200)
      rescue ActiveRecord::RecordInvalid => e
       validation_error_response(e.message)
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    def default(_params)
      begin
        flow = ChatFlow.get_default || ChatFlow.create!(name: 'Fluxo Padrão', definition: { nodes: [], edges: [] }, is_default: true)
        success_response(Api::Entities::ChatFlow.represent(flow), 200)
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end

    def contextual(params)
      user_type = params[:user_type]
      route_path = params[:route_path]

      begin
        flow = ChatFlow.contextual(user_type, route_path).first
        
        # Se não achar nada específico, pega o default
        flow ||= ChatFlow.get_default

        success_response(Api::Entities::ChatFlow.represent(flow), 200)
      rescue StandardError => e
        internal_error_response(e.message)
      end
    end
  end
end
