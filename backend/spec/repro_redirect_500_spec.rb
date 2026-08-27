require 'rails_helper'

RSpec.describe Ai::Nodes::Redirect do
  let(:step_data) do
    {
      'id' => 'node_redirect',
      'type' => 'redirect',
      'data' => {
        'action' => 'auth',
        'url' => 'http://example.com',
        'target' => '_self'
      }
    }
  end

  let(:session) { create(:chat_session, context: { 'email' => 'test@example.com', 'name' => 'Test User' }) }
  let(:input) { nil }
  let(:node) { described_class.new(step_data, session, input) }

  before do
    # DEC-41 removeu `visitor`; quem chega sem papel entra como Colaborador.
    UserType.seed_default_types!
  end

  describe '#payload' do
    it 'attempts authentication and returns payload' do
      # This mimics what FlowEngine does: handler.process! then handler.payload
      # But FlowEngine calls process! first.
      
      # Mock ExistingUserSessionService to pinpoint if it's the culprit or something deeper
      # Actually, let's integration test it to fail if Service crashes
      
      expect {
        node.process!
      }.not_to raise_error

      payload = node.payload

      
      expect(payload[:action]).to eq('auth')
      expect(payload[:url]).to eq('http://example.com')
      # Expect auth token to be present if auth succeeded
      # If auth failed (e.g. Service returned error), token might be nil
    end

    context 'when user type is missing (real scenario?)' do
      before do
        UserType.delete_all
      end

      it 'handles missing UserType gracefully or raises specific error' do
        expect {
           node.process!
        }.not_to raise_error
      end
    end
  end
end
