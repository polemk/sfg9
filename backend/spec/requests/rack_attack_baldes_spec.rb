# frozen_string_literal: true

require 'rails_helper'

# **O teto genérico não pode punir quem usa bem o sistema (27/08/2026).**
#
# Em produção, gente logada perdia a tela: `req/ip` valia 60/min para TODO
# tráfego, e o uso normal do console estoura isso — trocar de projeto refaz todas
# as consultas de uma vez, e cada navegação dispara `/flows/contextual`.
#
# Depois vinha o dano de verdade: o token expira em 15 min, a próxima chamada leva
# 401, o cliente tenta RENOVAR, a renovação leva 429, e a sessão era destruída.
#
# **Subir o número não resolveria**, só adiaria: num sistema corporativo a pessoa
# fica MAIS RÁPIDA conforme domina a ferramenta. Por isso o recorte mudou de
# limite para CRITÉRIO — anônimo tem um balde, autenticado tem outro.
#
# Estes exemplos travam o critério. O número pode ser ajustado; o critério não
# pode voltar a ser "conta todo mundo junto".
RSpec.describe 'Rack::Attack — o recorte dos baldes', type: :request do
  before do
    Rack::Attack.enabled = true
    Rack::Attack.reset!
  end

  after do
    Rack::Attack.enabled = false
    Rack::Attack.reset!
  end

  let(:og) { create(:user, :og) }
  let(:token) { Auth::TokenService.new(og).generate_tokens[:token] }

  # `127.0.0.1` é safelisted (`allow-localhost`), então os exemplos precisam de um
  # IP de fora — senão passariam por não haver limite nenhum, e não por acerto.
  def cabecalhos(autenticado:, ip: '203.0.113.7')
    base = { 'REMOTE_ADDR' => ip }
    autenticado ? base.merge('Authorization' => "Bearer #{token}") : base
  end

  describe 'o balde ANÔNIMO' do
    it 'existe — sem identidade, o teto por IP vale' do
      chave = Rack::Attack.throttles['req/ip']

      expect(chave).to be_present
      expect(chave.limit).to eq(300)
    end

    it 'NÃO conta requisição autenticada' do
      # É este o ponto do conserto: a mesma requisição, com e sem `Bearer`, cai em
      # baldes diferentes. Antes ambas caíam no mesmo.
      requisicao = Rack::Attack::Request.new(
        Rack::MockRequest.env_for('/api/v1/users', 'HTTP_AUTHORIZATION' => "Bearer #{token}")
      )

      expect(Rack::Attack.autenticada?(requisicao)).to be(true)
    end
  end

  describe 'o balde AUTENTICADO' do
    it 'é alto o bastante para nenhuma pessoa alcançar clicando' do
      chave = Rack::Attack.throttles['req/token']

      expect(chave).to be_present
      # 1.200/min são 20 por SEGUNDO sustentados por um minuto inteiro. É teto
      # contra automação desgovernada, não contra gente.
      expect(chave.limit).to eq(1_200)
      expect(chave.limit).to be > Rack::Attack.throttles['req/ip'].limit
    end

    it 'separa tokens diferentes em baldes diferentes' do
      outro = create(:user, :admin)
      token_outro = Auth::TokenService.new(outro).generate_tokens[:token]

      chave_a = Rack::Attack.chave_do_token(
        Rack::Attack::Request.new(Rack::MockRequest.env_for('/', 'HTTP_AUTHORIZATION' => "Bearer #{token}"))
      )
      chave_b = Rack::Attack.chave_do_token(
        Rack::Attack::Request.new(Rack::MockRequest.env_for('/', 'HTTP_AUTHORIZATION' => "Bearer #{token_outro}"))
      )

      # Sem isso, o uso intenso de uma pessoa gastaria o orçamento das outras —
      # que é o defeito de origem, por outro caminho.
      expect(chave_a).not_to eq(chave_b)
    end
  end

  # **Os limites ESTREITOS continuam valendo, e é onde a proteção real mora.**
  #
  # Num produto sem senha, o código de 6 dígitos É a credencial: sem teto na
  # validação, são 1 milhão de tentativas para varrer. Afrouxar o teto genérico
  # não pode ter afrouxado este.
  describe 'os limites que protegem de verdade' do
    it 'a validação de código continua com teto apertado' do
      chave = Rack::Attack.throttles['auth/code_validation/ip']

      expect(chave).to be_present
      expect(chave.limit).to eq(20)
    end

    it 'o envio de código continua com teto apertado' do
      expect(Rack::Attack.throttles['auth/code_request/ip'].limit).to eq(10)
    end
  end
end
