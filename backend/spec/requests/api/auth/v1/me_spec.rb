require 'rails_helper'

RSpec.describe 'Auth Me API', type: :request do
  let(:user) { create(:user) }
  # Generate token using the service logic
  let(:token_service) { Auth::TokenService.new(user) }
  # Since generate_tokens returns a hash { token: ..., refresh_token: ... } or just token string depending on version?
  # Reading TokenService: generate_tokens returns { token: ..., refresh_token: ... }
  # But Api::Root uses TokenService.decode_token(token).
  # generate_access_token is private but called by generate_tokens.
  let(:access_token) { token_service.generate_tokens[:token] }
  let(:headers) { { 'Authorization' => "Bearer #{access_token}" } }

  describe 'GET /auth/v1/me' do
    context 'when authenticated' do
      it 'returns user data' do
        # Mocking logic isn't strictly necessary if we rely on simple standard behavior,
        # but the controller calls Auth::MeService.
        # Let's mock the service to ensure isolation.
        service_double = instance_double(Auth::MeService)
        allow(Auth::MeService).to receive(:new).with(user).and_return(service_double)
        
        expected_data = { id: user.id, name: user.name, email: user.email }
        expect(service_double).to receive(:show).and_return({ status: 200, data: expected_data })

        get '/auth/v1/me', headers: headers

        expect(response).to have_http_status(200)
        json = JSON.parse(response.body)
        expect(json['id']).to eq(user.id)
      end
    end

    context 'when unauthenticated' do
      it 'returns 401' do
        get '/auth/v1/me'
        expect(response).to have_http_status(401)
      end
    end
  end

  describe 'PATCH /auth/v1/me' do
    let(:update_params) { { name: 'New Name' } }
    let(:csrf_token) { 'valid_csrf' }
    let(:headers_with_csrf) { headers.merge('X-CSRF-Token' => csrf_token) }

    context 'when authenticated and valid csrf' do
      it 'updates user data' do
        service_double = instance_double(Auth::MeService)
        allow(Auth::MeService).to receive(:new).with(user).and_return(service_double)
        
        expect(service_double).to receive(:update).with(anything, csrf_token).and_return({ status: 200, data: { success: true } })

        patch '/auth/v1/me', params: update_params, headers: headers_with_csrf

        expect(response).to have_http_status(200)
      end
    end

    context 'when missing csrf' do
      it 'returns 403' do
        patch '/auth/v1/me', params: update_params, headers: headers
        expect(response).to have_http_status(403)
      end
    end

    # S1 / DEC-74 — **apagar um campo do perfil é uma operação, e ela tem de funcionar.**
    #
    # O endpoint entregava `params` cru ao serviço, e o Grape põe `nil` em TODO parâmetro
    # declarado que o cliente não mandou. O serviço se defendia com um `.compact` — que não
    # distingue "não mandei" de "mandei vazio para apagar".
    #
    # Medido em 26/08/2026 contra o servidor de dev, antes da correção:
    # `{"graduation": null}` → **422 "Nenhum campo para atualizar"**; `{"birthday": ""}`
    # também, porque o Grape converte data vazia para `nil`. Ou seja: **campo de data não
    # tinha como ser limpo**, e nada acusava — a tela mandava e a resposta dizia que não
    # havia o que atualizar.
    #
    # A correção é `declared(params, include_missing: false)` no endpoint e a saída do
    # `.compact` no serviço. Estes exemplos travam os dois lados: o que foi mandado apaga,
    # e o que não foi mandado continua intacto.
    context 'limpando campos do perfil estendido' do
      let(:csrf_token) { 'valid_csrf' }
      let(:headers_with_csrf) { headers.merge('X-CSRF-Token' => csrf_token) }

      before do
        allow_any_instance_of(Auth::CsrfService).to receive(:valid?).and_return(true)
        user.update!(graduation: 'Mestrado', birthday: Date.new(1990, 5, 10),
                     gender: 'female', name: 'Nome Original')
      end

      it 'apaga um campo de TEXTO quando o cliente manda null' do
        patch '/auth/v1/me', params: { graduation: nil }.to_json,
              headers: headers_with_csrf.merge('CONTENT_TYPE' => 'application/json')

        expect(response).to have_http_status(200)
        expect(user.reload.graduation).to be_nil
      end

      # O exemplo que mais importa: antes da correção ele respondia 422.
      it 'apaga um campo de DATA quando o cliente manda null' do
        patch '/auth/v1/me', params: { birthday: nil }.to_json,
              headers: headers_with_csrf.merge('CONTENT_TYPE' => 'application/json')

        expect(response).to have_http_status(200)
        expect(user.reload.birthday).to be_nil
      end

      it 'não mexe no que o cliente NÃO mandou' do
        patch '/auth/v1/me', params: { graduation: nil }.to_json,
              headers: headers_with_csrf.merge('CONTENT_TYPE' => 'application/json')

        expect(response).to have_http_status(200)
        user.reload
        expect(user.name).to eq('Nome Original')
        expect(user.birthday).to eq(Date.new(1990, 5, 10))
        expect(user.gender).to eq('female')
      end

      it 'continua recusando um corpo sem campo nenhum' do
        patch '/auth/v1/me', params: {}.to_json,
              headers: headers_with_csrf.merge('CONTENT_TYPE' => 'application/json')

        expect(response).to have_http_status(422)
      end
    end
  end
end
