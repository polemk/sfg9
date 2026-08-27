# frozen_string_literal: true

module Api
  module V1
    class FlowExecutions < Grape::API
      include Api::V1::Defaults

      resource :flow_executions do
        before { authenticate! }

        desc "List all flow executions (grouped by session)"
        params do
          optional :flow_id, type: Integer, desc: "Filter by flow ID"
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get do
          # Get unique sessions with their latest execution info
          sessions = ChatSession
                     .joins(:flow_executions)
                     .includes(:chat_flow)
                     .distinct
                     .order(updated_at: :desc)

          sessions = sessions.where(chat_flow_id: params[:flow_id]) if params[:flow_id].present?

          total = sessions.count
          sessions = sessions.offset((params[:page] - 1) * params[:per_page]).limit(params[:per_page])

          {
            sessions: sessions.map do |session|
              executions = session.flow_executions.ordered
              {
                id: session.id,
                flow_name: session.chat_flow&.name,
                flow_id: session.chat_flow_id,
                steps_count: executions.count,
                started_at: executions.first&.created_at,
                last_activity_at: executions.last&.created_at,
                current_step: session.current_step_id,
                context: session.context
              }
            end,
            meta: {
              total: total,
              page: params[:page],
              per_page: params[:per_page],
              total_pages: (total.to_f / params[:per_page]).ceil
            }
          }
        end

        desc "Get execution details for a session"
        params do
          requires :session_id, type: Integer, desc: "Chat session ID"
        end
        get ":session_id" do
          session = ChatSession.includes(:chat_flow, :flow_executions).find(params[:session_id])
          executions = session.flow_executions.ordered

          {
            session: {
              id: session.id,
              flow_name: session.chat_flow&.name,
              flow_id: session.chat_flow_id,
              current_step: session.current_step_id,
              context: session.context,
              created_at: session.created_at
            },
            timeline: executions.map do |exec|
              {
                id: exec.id,
                node_id: exec.node_id,
                node_type: exec.node_type,
                input_data: exec.input_data,
                output_data: exec.output_data,
                context_snapshot: exec.context_snapshot,
                summary: exec.summary,
                created_at: exec.created_at
              }
            end
          }
        end

        desc "Get execution stats for analytics"
        params do
          optional :flow_id, type: Integer, desc: "Filter by flow ID"
          optional :days, type: Integer, default: 7, desc: "Number of days to analyze"
        end
        get :stats do
          scope = FlowExecution.where('created_at > ?', params[:days].days.ago)
          scope = scope.where(chat_flow_id: params[:flow_id]) if params[:flow_id].present?

          {
            total_executions: scope.count,
            unique_sessions: scope.select(:chat_session_id).distinct.count,
            by_node_type: scope.group(:node_type).count,
            by_day: scope.group("DATE(created_at)").count
          }
        end
      end
    end
  end
end
