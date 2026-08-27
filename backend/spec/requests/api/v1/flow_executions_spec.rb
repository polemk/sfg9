require 'rails_helper'

RSpec.describe 'Api::V1::FlowExecutions', type: :request do
  let(:user) { create(:user, :og) }
  let(:flow) { create(:chat_flow) }
  let(:session) { create(:chat_session, chat_flow: flow) }
  let!(:executions) do
    [
      create(:flow_execution, :trigger, chat_session: session, chat_flow: flow, created_at: 3.minutes.ago),
      create(:flow_execution, :text, chat_session: session, chat_flow: flow, created_at: 2.minutes.ago),
      create(:flow_execution, :question, chat_session: session, chat_flow: flow, created_at: 1.minute.ago)
    ]
  end

  let(:auth_headers) do
    token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/flow_executions' do
    context 'when authenticated' do
      it 'returns list of sessions with executions' do
        get '/api/v1/flow_executions', headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['sessions']).to be_an(Array)
        expect(json['sessions'].length).to eq(1)
        expect(json['sessions'].first['id']).to eq(session.id)
        expect(json['sessions'].first['steps_count']).to eq(3)
        expect(json['meta']).to include('total', 'page', 'per_page', 'total_pages')
      end

      it 'filters by flow_id' do
        other_flow = create(:chat_flow)
        other_session = create(:chat_session, chat_flow: other_flow)
        create(:flow_execution, chat_session: other_session, chat_flow: other_flow)

        get '/api/v1/flow_executions', params: { flow_id: flow.id }, headers: auth_headers

        json = JSON.parse(response.body)
        expect(json['sessions'].length).to eq(1)
        expect(json['sessions'].first['flow_id']).to eq(flow.id)
      end

      it 'paginates results' do
        get '/api/v1/flow_executions', params: { page: 1, per_page: 5 }, headers: auth_headers

        json = JSON.parse(response.body)
        expect(json['meta']['page']).to eq(1)
        expect(json['meta']['per_page']).to eq(5)
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        get '/api/v1/flow_executions'

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/flow_executions/:session_id' do
    context 'when authenticated' do
      it 'returns session details with timeline' do
        get "/api/v1/flow_executions/#{session.id}", headers: auth_headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json['session']['id']).to eq(session.id)
        expect(json['session']['flow_name']).to eq(flow.name)
        expect(json['timeline']).to be_an(Array)
        expect(json['timeline'].length).to eq(3)
      end

      it 'returns timeline in chronological order' do
        get "/api/v1/flow_executions/#{session.id}", headers: auth_headers

        json = JSON.parse(response.body)
        node_types = json['timeline'].map { |t| t['node_type'] }
        expect(node_types).to eq(%w[trigger text question])
      end

      it 'returns 404 for non-existent session' do
        get '/api/v1/flow_executions/999999', headers: auth_headers

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/flow_executions/stats' do
    it 'returns execution statistics' do
      get '/api/v1/flow_executions/stats', headers: auth_headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json['total_executions']).to eq(3)
      expect(json['unique_sessions']).to eq(1)
      expect(json['by_node_type']).to be_a(Hash)
      expect(json['by_day']).to be_a(Hash)
    end

    it 'filters stats by flow_id' do
      get '/api/v1/flow_executions/stats', params: { flow_id: flow.id }, headers: auth_headers

      json = JSON.parse(response.body)
      expect(json['total_executions']).to eq(3)
    end

    it 'filters stats by days' do
      old_exec = create(:flow_execution, chat_session: session, chat_flow: flow, created_at: 10.days.ago)

      get '/api/v1/flow_executions/stats', params: { days: 7 }, headers: auth_headers

      json = JSON.parse(response.body)
      # Should not include the old execution
      expect(json['total_executions']).to eq(3)
    end
  end
end
