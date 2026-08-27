# frozen_string_literal: true

require 'rails_helper'

# **Duas telas que o menu oferece ao Admin e que o servidor recusava.**
#
# Achadas abrindo o app, não em portão: `tsc` limpo, `rspec` verde, matriz
# aprovada — e o Admin clicava em "Credenciais" e em "WhatsApp" e recebia
# "Erro ao carregar" e "Acesso negado". É a mesma família do defeito que o
# usuário já tinha achado em 14 telas (o somente-leitura vendo botão que o
# servidor recusa): **o menu e a API discordando sobre quem entra.**
#
# ## Por que a API é que estava errada nas duas
#
# - **Credenciais (DEC-61)** — a decisão escolheu guardar as chaves de terceiro
#   no `Credential` para que *o cliente* trocasse a própria chave da ReceitaWS
#   sem deploy. O cliente é o **Admin**; OG é o fornecedor (Livetat, DEC-18.1).
#   Com `require_og!` a decisão não se realizava.
# - **WhatsApp (DEC-83)** — a decisão diz por que o Admin precisa entrar: com o
#   DEC-14 o WhatsApp é porta de entrada, e sem a tela *"quando a sessão da
#   instância expirar o canal cai e ninguém consegue reparear pela interface"*.
#
# Estreitar o menu para OG calaria as duas telas e **criaria** a dependência da
# Livetat que as duas decisões existem para evitar.
#
# Este arquivo trava os dois lados: Admin entra, Gerente e Colaborador não.
RSpec.describe 'O papel que o menu oferece é o papel que o servidor aceita', type: :request do
  def bearer_for(user)
    "Bearer #{Auth::TokenService.new(user).generate_tokens[:token]}"
  end

  def headers_for(user) = { 'Authorization' => bearer_for(user) }

  def user_com_papel(nome, nivel)
    tipo = UserType.find_by(name: nome) ||
           UserType.create!(name: nome, description: nome, hierarchy_level: nivel)
    User.create!(name: nome, email: "#{nome.downcase}@papeis.test", user_type: tipo)
  end

  let(:og) { user_com_papel('OG', 1) }
  let(:admin) { user_com_papel('Admin', 2) }
  let(:gerente) { user_com_papel('Gerente', 3) }
  let(:colaborador) { user_com_papel('Colaborador', 4) }

  # ------------------------------------------------------------------
  describe 'GET /api/v1/credentials — DEC-61' do
    it 'o Admin LÊ a lista (respondia 403)' do
      get '/api/v1/credentials', headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
    end

    it 'o OG continua lendo' do
      get '/api/v1/credentials', headers: headers_for(og)

      expect(response).to have_http_status(:ok)
    end

    it 'Gerente e Colaborador continuam FORA' do
      [gerente, colaborador].each do |usuario|
        get '/api/v1/credentials', headers: headers_for(usuario)

        expect(response).to have_http_status(:forbidden), "#{usuario.name} entrou"
        expect(JSON.parse(response.body)['code']).to eq('ROLE_REQUIRED')
      end
    end

    it 'sem token continua 401' do
      get '/api/v1/credentials'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ------------------------------------------------------------------
  describe 'GET /whats/v1/instances/instance — DEC-83' do
    let!(:instancia) do
      PolemkInstance.create!(
        display_name: 'Instância da demonstração', instance_name: 'DEMO_INSTANCE',
        instance_id: 'inst_demo', api_key: 'apikey_demo',
        integration: 'WHATSAPP-BAILEYS', is_qrcode: true,
        connection_status: 'connected', number: '5548999999999', raw_response: {}
      )
    end

    it 'o Admin ENXERGA a instância (respondia 401 "Acesso negado")' do
      get '/whats/v1/instances/instance', headers: headers_for(admin)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['instance_id']).to eq('inst_demo')
    end

    it 'o OG continua enxergando' do
      get '/whats/v1/instances/instance', headers: headers_for(og)

      expect(response).to have_http_status(:ok)
    end

    it 'Gerente e Colaborador continuam FORA' do
      [gerente, colaborador].each do |usuario|
        get '/whats/v1/instances/instance', headers: headers_for(usuario)

        expect(response).to have_http_status(:unauthorized), "#{usuario.name} entrou"
      end
    end
  end

  # ------------------------------------------------------------------
  # A política vive num lugar só — estava copiada em quatro guardas do engine,
  # e quatro cópias de uma regra de autorização é a forma de três continuarem
  # erradas depois que alguém conserta a primeira.
  describe Sfg::Whats::Access do
    it 'aceita OG e Admin, recusa os outros dois' do
      expect(described_class.allowed?(nil, og)).to be(true)
      expect(described_class.allowed?(nil, admin)).to be(true)
      expect(described_class.allowed?(nil, gerente)).to be(false)
      expect(described_class.allowed?(nil, colaborador)).to be(false)
    end

    it 'aceita integração máquina-a-máquina, que não tem papel' do
      expect(described_class.allowed?(ClientApplication.new, nil)).to be(true)
    end

    it 'recusa quem não está autenticado' do
      expect(described_class.allowed?(nil, nil)).to be(false)
    end
  end
end
