# frozen_string_literal: true

require 'rails_helper'

# S2 — observadores das mensagens administrativas.
RSpec.describe 'Observadores', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
    ActionMailer::Base.deliveries.clear
  end

  let(:og) { create(:user, :og) }
  let(:gerente) { create(:user, :gerente) }

  def criar_observador(email:, contexts: ['problem'])
    o = Observer.new(name: 'Observador', email: email, user: og)
    o.contexts = contexts
    o.save!
    o
  end

  describe 'GET /api/v1/observers' do
    # 6.4.3 — regressão do D-88: o legado LIA `limit`/`offset` e nunca aplicava.
    it 'aplica a paginação de verdade' do
      5.times { |i| criar_observador(email: "obs#{i}@example.com") }

      get '/api/v1/observers', params: { page: 1, per_page: 2 }, headers: auth_headers(og)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(2)
      expect(response.headers['X-Total-Count']).to eq('5')
      expect(response.headers['X-Total-Pages']).to eq('3')
    end

    it 'a segunda página traz registros diferentes da primeira' do
      5.times { |i| criar_observador(email: "obs#{i}@example.com") }

      get '/api/v1/observers', params: { page: 1, per_page: 2 }, headers: auth_headers(og)
      pagina1 = JSON.parse(response.body).map { |o| o['id'] }
      get '/api/v1/observers', params: { page: 2, per_page: 2 }, headers: auth_headers(og)
      pagina2 = JSON.parse(response.body).map { |o| o['id'] }

      expect(pagina1 & pagina2).to be_empty
    end

    # 6.3.4 — `per_page` acima do teto é limitado. O legado aceitava `l=999999`.
    it 'limita `per_page` ao teto' do
      3.times { |i| criar_observador(email: "obs#{i}@example.com") }

      get '/api/v1/observers', params: { per_page: 999_999 }, headers: auth_headers(og)

      expect(response.headers['X-Per-Page']).to eq('100')
    end

    it 'o Gerente NÃO alcança; o OG alcança' do
      get '/api/v1/observers', headers: auth_headers(gerente)
      expect(response).to have_http_status(:forbidden)

      get '/api/v1/observers', headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'CRUD' do
    it 'cria com contextos e avisa o observador por e-mail' do
      expect do
        post '/api/v1/observers',
             params: { name: 'Ana', email: 'ana@example.com', contexts: %w[problem contact] },
             headers: auth_headers(og)
      end.to change(Observer, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['contexts']).to contain_exactly('problem', 'contact')
    end

    it 'recusa observador sem contexto nenhum — cadastro que nunca notificaria' do
      post '/api/v1/observers', params: { name: 'Ana', email: 'ana@example.com', contexts: [] },
                                headers: auth_headers(og)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'atualiza a lista de contextos sem duplicar' do
      o = criar_observador(email: 'bia@example.com', contexts: %w[problem])

      put "/api/v1/observers/#{o.id}", params: { contexts: %w[problem suggestion] }, headers: auth_headers(og)

      expect(response).to have_http_status(:ok)
      expect(o.reload.contexts).to contain_exactly('problem', 'suggestion')
      expect(ObserverContext.where(observer_id: o.id).count).to eq(2)
    end

    it 'remove' do
      o = criar_observador(email: 'cia@example.com')
      expect { delete "/api/v1/observers/#{o.id}", headers: auth_headers(og) }.to change(Observer, :count).by(-1)
    end
  end

  # 6.4.4 — a duplicata é barrada PELO ÍNDICE ÚNICO, não por `SELECT COUNT`.
  # O legado contava antes de gravar (`observer_context.rb:9`): duas requisições
  # concorrentes passavam as duas pela contagem e gravavam as duas.
  describe 'duplicata de contexto' do
    it 'o banco recusa, mesmo furando a validação do model' do
      o = criar_observador(email: 'dia@example.com', contexts: %w[problem])

      expect do
        ObserverContext.new(observer_id: o.id, context: 'problem').save!(validate: false)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'notificação' do
    it 'só observadores do contexto da mensagem são alvo' do
      criar_observador(email: 'problema@example.com', contexts: %w[problem])
      criar_observador(email: 'contato@example.com', contexts: %w[contact])

      m = AdminMessage.create!(sender_name: 'Fulano de Tal', sender_email: 'f@example.com',
                               message: 'texto', context: 'problem')

      expect(Observer.for_message(m).map(&:email)).to eq(['problema@example.com'])
    end

    it 'observador não interno não recebe mensagem interna' do
      externo = criar_observador(email: 'externo@example.com', contexts: %w[problem])
      externo.update!(is_internal: false)

      m = AdminMessage.create!(sender_name: 'Fulano de Tal', sender_email: 'f@example.com',
                               message: 'texto', context: 'problem', is_internal: true)

      expect(Observer.for_message(m)).to be_empty
    end
  end
end
