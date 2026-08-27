# frozen_string_literal: true

require 'rails_helper'

# Regressão do **DEC-49**: as 4 rotas de auto-cadastro não existem mais.
#
# Este teste vale por si: rota removida responde 404 porque o Grape não tem
# endpoint para casar, não porque alguma flag esteja desligada. Se alguém
# remontar qualquer uma delas, este spec cai — que é o ponto, já que é por essa
# porta que o **D-39** voltaria sozinho apesar do DEC-18.7.
RSpec.describe 'Auth Registration API', type: :request do
  before do
    UserType.seed_default_types!
    allow_any_instance_of(Auth::EmailService).to receive(:send_magic_login_code).and_return(true)
    allow(EvolutionConnection).to receive(:send_message).and_return(true)
  end

  describe 'as 4 rotas de auto-cadastro removidas (DEC-49)' do
    {
      '/auth/v1/pre_register' => { identifier: 'new@example.com', method: 'email' },
      '/auth/v1/complete_registration' => { identifier: 'new@example.com', method: 'email', code: '1', name: 'X' },
      '/auth/v1/visitor_signup' => { name: 'Visitor', phone: '5511999999999' },
      '/auth/v1/visitor_signup_with_link' => { name: 'Visitor', email: 'v@example.com' }
    }.each do |path, body|
      it "POST #{path} não existe" do
        post path, params: body
        expect(response).to have_http_status(404)
      end

      it "POST #{path} não cria usuário" do
        expect { post path, params: body }.not_to change(User, :count)
      end
    end
  end

  # O outro lado do par: o que **sobrou** continua funcionando. Um teste que só
  # verificasse os 404 passaria com a API inteira fora do ar.
  describe 'POST /auth/v1/verify_code — continua vivo e NÃO cria conta' do
    let!(:user) { create(:user, email: 'verify@example.com') }

    it 'valida um código emitido para usuário existente' do
      post '/auth/v1/magic_login/request_code', params: { identifier: 'verify@example.com', method: 'email' }
      code = LoginCode.by_destination('verify@example.com').by_method('email').recent.first.code

      expect do
        post '/auth/v1/verify_code', params: { identifier: 'verify@example.com', method: 'email', code: code }
      end.not_to change(User, :count)

      expect(response).to have_http_status(:ok).or have_http_status(:created)
    end

    it 'rejeita código inválido' do
      post '/auth/v1/verify_code', params: { identifier: 'verify@example.com', method: 'email', code: 'wrong' }
      expect(response).to have_http_status(401)
    end
  end
end
