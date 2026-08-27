# frozen_string_literal: true

require 'rails_helper'

# S12 / BE-330, BE-349, D-69 — a superfície pública.
RSpec.describe 'Contratos — superfície pública', type: :request do
  before { UserType.seed_default_types! }

  let(:og) { create(:user, :og) }

  def publicar(kind: Contract::KIND_TERMS_OF_USE, body: '<p>texto</p>')
    contrato = Contract.new(kind: kind, title: kind, creator: og)
    contrato.description = body
    contrato.save!
    contrato
  end

  it 'lê SEM sessão' do
    publicar
    get '/api/v1/public/contracts/termos-de-uso'

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['description_html']).to include('texto')
  end

  # 5.5 / BE-349 — a rota que SEMPRE dava 500
  it 'sem tipo, lista os tipos disponíveis — nunca 500' do
    publicar
    get '/api/v1/public/contracts'

    corpo = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(corpo['kinds'].map { |k| k['slug'] }).to include('termos-de-uso')
  end

  it 'sem nenhum contrato publicado, 404 — nunca 500' do
    get '/api/v1/public/contracts'
    expect(response).to have_http_status(:not_found)
  end

  it 'tipo desconhecido é 404, não 500 (`nil.kind` do legado)' do
    get '/api/v1/public/contracts/nao-existe'
    expect(response).to have_http_status(:not_found)
  end

  # Q-B34 — as duas formas de endereçar o mesmo documento
  it 'aceita o SLUG e a STRING LITERAL do legado (com espaço e typo)' do
    publicar(kind: Contract::KIND_PRIVACY_POLICY)

    get '/api/v1/public/contracts/politicas-de-privacidade'
    expect(response).to have_http_status(:ok)

    get "/api/v1/public/contracts/#{ERB::Util.url_encode('Politicas de Privacidade')}"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['kind']).to eq('Politicas de Privacidade')
  end

  # 5.4 / D-69 — os DOIS vetores no mesmo parâmetro
  describe 'allowlist de destino de retorno (D-69)' do
    before { publicar }

    it 'destino fora da allowlist é recusado e cai no padrão' do
      get '/api/v1/public/contracts/termos-de-uso', params: { return_to: 'https://evil.example.com' }

      corpo = JSON.parse(response.body)
      expect(corpo['return_to_allowed']).to be(false)
      expect(corpo['return_to']).to eq('/login')
    end

    it 'nenhum valor do parâmetro chega à resposta — nem escapado' do
      malicioso = '"><script>alert(1)</script>'
      get '/api/v1/public/contracts/termos-de-uso', params: { return_to: malicioso }

      # `<script` e não `script`: a chave `description_html` do próprio corpo
      # contém a subsequência "script", e o assert ingênuo passava por acidente.
      expect(response.body).not_to include('<script')
      expect(response.body).not_to include('alert(1)')
      expect(JSON.parse(response.body)['return_to']).to eq('/login')
    end

    it 'destino conhecido resolve para o caminho interno' do
      get '/api/v1/public/contracts/termos-de-uso', params: { return_to: 'profile' }

      corpo = JSON.parse(response.body)
      expect(corpo['return_to']).to eq('/profile')
      expect(corpo['return_to_allowed']).to be(true)
    end

    it 'o resolvedor nunca devolve o que veio do cliente' do
      %w[javascript:alert(1) //evil.com /../../etc/passwd].each do |entrada|
        expect(Contracts::ReturnDestinations.resolve(entrada)).to eq('/login')
      end
    end
  end

  # A superfície pública é só LEITURA. Publicar exige sessão E papel (DEC-38).
  it 'a rota pública NÃO publica nem aceita' do
    publicar
    expect do
      post '/api/v1/public/contracts', params: { kind: Contract::KIND_TERMS_OF_USE, title: 'X',
                                                 description: '<p>x</p>' }
    end.not_to(change { Contract.count })
    expect(response.status).to be >= 400
  end

  # OPS-331 — o host público, validado no boot
  describe 'PublicHost (OPS-331)' do
    it 'monta o link com o SLUG, escapado' do
      expect(PublicHost.contract_url(Contract::KIND_PRIVACY_POLICY))
        .to end_with('/contract/politicas-de-privacidade')
    end

    it 'em produção, a ausência de APP_HOST derruba o boot em vez de gerar link quebrado' do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('APP_HOST').and_return(nil)

      expect { PublicHost.verify! }.to raise_error(PublicHost::MissingHost, /APP_HOST/)
    end
  end
end
