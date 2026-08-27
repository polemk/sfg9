# frozen_string_literal: true

require 'rails_helper'

# S2 — mensagens administrativas (`feedback19` virando código do app, DC-12).
RSpec.describe 'Mensagens administrativas', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
    ActionMailer::Base.deliveries.clear
  end

  let(:og) { create(:user, :og) }
  let(:admin) { create(:user, :admin) }
  let(:gerente) { create(:user, :gerente) }
  let(:colaborador) { create(:user, :colaborador) }

  def criar_mensagem(**attrs)
    AdminMessage.create!({
      sender_name: 'Fulano de Tal',
      sender_email: 'fulano@example.com',
      message: 'Achei um problema na tela de recebíveis.'
    }.merge(attrs))
  end

  describe 'GET /api/v1/admin_messages' do
    # 6.4.1 — regressão do `@total_count = Message.all.count` do legado, que era
    # o total GLOBAL calculado ANTES dos filtros.
    it 'o total do cabeçalho respeita os filtros' do
      3.times { criar_mensagem(context: 'problem') }
      2.times { criar_mensagem(context: 'contact') }

      get '/api/v1/admin_messages', params: { context: 'problem' }, headers: auth_headers(og)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(3)
      expect(response.headers['X-Total-Count']).to eq('3')
    end

    it 'sem filtro, o total é o total' do
      5.times { criar_mensagem }
      get '/api/v1/admin_messages', headers: auth_headers(og)
      expect(response.headers['X-Total-Count']).to eq('5')
    end

    # C3, os DOIS lados. Um teste que só verifique "o Gerente não entra" passa
    # com a regra invertida.
    it 'OG e Admin leem; o Gerente NÃO; o Colaborador lê' do
      criar_mensagem

      [og, admin, colaborador].each do |u|
        get '/api/v1/admin_messages', headers: auth_headers(u)
        expect(response).to have_http_status(:ok), "#{u.user_type.name} deveria ler"
      end

      get '/api/v1/admin_messages', headers: auth_headers(gerente)
      expect(response).to have_http_status(:forbidden)
    end

    it 'exige sessão' do
      get '/api/v1/admin_messages'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'a máquina de estados (BE-527)' do
    # 6.4.2 REESCRITO PELA DEC-73.
    #
    # O `tasks.md` (3.3 e 6.4.2) pedia "pedir Concluído grava Concluído",
    # seguindo a DC-16. A **DEC-73 respondeu o contrário**: vale o DEC-30, a
    # inversão é REPLICADA. A DEC vence o tasks, escrito antes dela.
    #
    # Este é o golden test que trava os DOIS sentidos: quem "consertar" a
    # inversão sem passar por uma DEC nova é reprovado aqui.
    it 'DEC-73: pedir "Concluído" (done) grava "Fechado" (closed)' do
      m = criar_mensagem
      put "/api/v1/admin_messages/#{m.id}", params: { state: 'done' }, headers: auth_headers(og)

      expect(response).to have_http_status(:ok)
      expect(m.reload.state).to eq('closed')
      expect(m.state_label).to eq('Fechado')
    end

    it 'DEC-73: a ação de encerrar grava "Concluído" (done)' do
      m = criar_mensagem
      put "/api/v1/admin_messages/#{m.id}/close", headers: auth_headers(og)

      expect(response).to have_http_status(:ok)
      expect(m.reload.state).to eq('done')
      expect(m.state_label).to eq('Concluído')
    end

    it 'as demais situações gravam o que foi pedido' do
      m = criar_mensagem
      %w[read open evaluated answered rejected closed].each do |estado|
        put "/api/v1/admin_messages/#{m.id}", params: { state: estado }, headers: auth_headers(og)
        expect(m.reload.state).to eq(estado)
      end
    end

    it 'abrir uma mensagem "Não lido" a move para "Lido"' do
      m = criar_mensagem
      expect(m.state).to eq('unread')

      get "/api/v1/admin_messages/#{m.id}", headers: auth_headers(og)

      expect(response).to have_http_status(:ok)
      expect(m.reload.state).to eq('read')
    end

    it 'a primeira resposta do administrador move para "Respondido"' do
      m = criar_mensagem
      get "/api/v1/admin_messages/#{m.id}", headers: auth_headers(og) # unread -> read

      post "/api/v1/admin_messages/#{m.id}/notes", params: { description: 'Vamos verificar.' },
                                                   headers: auth_headers(og)

      expect(response).to have_http_status(:created)
      expect(m.reload.state).to eq('answered')
    end
  end

  describe 'POST /api/v1/admin_messages' do
    # 6.4.5 / DEC-40 — no legado o `create` era isento de autenticação de
    # propósito e o filtro restante fazia bypass total no formato JS.
    it 'exige sessão' do
      post '/api/v1/admin_messages', params: { message: 'oi' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'qualquer papel autenticado consegue enviar' do
      post '/api/v1/admin_messages',
           params: { message: 'A tela de limites está lenta.', context: 'problem' },
           headers: auth_headers(colaborador)

      expect(response).to have_http_status(:created)
      criada = AdminMessage.last
      expect(criada.sender_email).to eq(colaborador.email)
      expect(criada.state).to eq('unread')
    end

    it 'a conversa nasce com a fala do remetente' do
      post '/api/v1/admin_messages', params: { message: 'Primeira fala.' }, headers: auth_headers(colaborador)

      notas = AdminMessage.last.notes
      expect(notas.size).to eq(1)
      expect(notas.first.description).to eq('Primeira fala.')
      expect(notas.first.from_admin?).to be(false)
    end

    it 'recusa corpo acima de 500 caracteres em vez de truncar em silêncio' do
      post '/api/v1/admin_messages', params: { message: 'x' * 501 }, headers: auth_headers(colaborador)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'vocabulário' do
    it 'entrega as 8 situações e os 4 contextos' do
      get '/api/v1/admin_messages/vocabulary', headers: auth_headers(og)

      json = JSON.parse(response.body)
      expect(json['states'].size).to eq(8)
      expect(json['contexts'].size).to eq(4)
      expect(json['contexts'].map { |c| c['label'] })
        .to contain_exactly('Outros', 'Problema', 'Contato', 'Sugestão')
    end
  end
end
