require 'rails_helper'

RSpec.describe Ai::Nodes::Redirect do
  let(:flow) { create(:chat_flow) }
  let(:session) { create(:chat_session, chat_flow: flow) }
  
  let(:step_data) do
    {
      'id' => 'redirect_node_1',
      'type' => 'redirect',
      'data' => {
        'action' => 'navigate',
        'url' => 'https://example.com',
        'target' => '_blank'
      }
    }
  end

  subject(:node) { described_class.new(step_data, session) }

  describe '#payload' do
    context 'when action is navigate' do
      it 'includes action, url, and target' do
        expect(node.payload).to include(
          type: 'redirect',
          action: 'navigate',
          url: 'https://example.com',
          target: '_blank'
        )
      end
    end

    context 'when action is scroll_to' do
      let(:step_data) do
        {
          'id' => 'scroll_node',
          'type' => 'redirect',
          'data' => {
            'action' => 'scroll_to',
            'target' => '#pricing'
          }
        }
      end

      it 'includes action and target' do
        result = node.payload
        expect(result[:action]).to eq('scroll_to')
        expect(result[:target]).to eq('#pricing')
      end
    end

    context 'when auto_auth is true' do
      let(:step_data) do
        {
          'id' => 'auth_node',
          'type' => 'redirect',
          'data' => {
            'action' => 'navigate',
            'url' => '/dashboard',
            'auto_auth' => true
          }
        }
      end

      let(:mock_user) { create(:user, name: 'Test User', email: 'test@example.com') }
      let(:mock_user_entity) { Api::Entities::User.represent(mock_user) }

      before do
        session.update!(context: { 'email' => 'test@example.com', 'name' => 'Test User' }, current_step_id: 'start')
        allow(Auth::ExistingUserSessionService).to receive(:call).and_return(
          status: 200,
          data: {
            token: 'jwt_token_123',
            refresh_token: 'refresh_token_456',
            user: mock_user_entity
          }
        )
      end

      it 'authenticates user and includes token in payload' do
        node.process! # Auth happens here
        
        result = node.payload
        expect(result[:action]).to eq('navigate')
        expect(result[:auth]).to be_present
        expect(result[:auth][:token]).to eq('jwt_token_123')
        expect(result[:auth][:user_email]).to eq('test@example.com')
      end

      it 'calls ExistingUserSessionService with context data' do
        expect(Auth::ExistingUserSessionService).to receive(:call).with(
          hash_including(email: 'test@example.com', name: 'Test User')
        )
        node.process!
      end
    end
  end

  describe '#transparent?' do
    it 'returns false' do
      expect(node.transparent?).to be(false)
    end
  end
end
