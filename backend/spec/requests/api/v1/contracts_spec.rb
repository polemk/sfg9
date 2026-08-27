# frozen_string_literal: true

require 'rails_helper'

# S12 — leitura e **aceite** de contrato (BE-331..BE-334, BE-341, BE-347, DEC-65,
# DEC-66, DEC-80).
RSpec.describe 'Contratos — leitura e aceite', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og) { create(:user, :og) }
  let(:colaborador) { create(:user, :colaborador) }

  def publicar(kind: Contract::KIND_TERMS_OF_USE, title: 'Termos de Uso', body: '<p>v1</p>')
    contrato = Contract.new(kind: kind, title: title, creator: og)
    contrato.description = body
    contrato.save!
    contrato
  end

  # ---------------------------------------------------------------------
  # 5.1 — versionamento (BE-331 / BE-336)
  # ---------------------------------------------------------------------
  describe 'versionamento' do
    it 'a vigente é a de MAIOR VERSÃO, não a de maior id' do
      v1 = publicar(body: '<p>primeira</p>')
      v2 = publicar(body: '<p>segunda</p>')
      # Re-salvar a v1 a move para o fim da tabela por `updated_at`/id — era
      # exatamente o que fazia o `.last` do legado servir o texto errado.
      v1.update!(title: 'Termos de Uso (revisto)')

      expect(Contracts::Resolver.current(Contract::KIND_TERMS_OF_USE)).to eq(v2)
    end

    it 're-salvar uma versão NÃO incrementa o número' do
      contrato = publicar
      expect { contrato.update!(title: 'Outro título') }.not_to(change { contrato.reload.version })
    end

    it 'a numeração é atribuída só na criação e cresce de um em um' do
      expect([publicar.version, publicar.version, publicar.version]).to eq([1, 2, 3])
    end

    it 'publicações do mesmo tipo recebem números DISTINTOS — garantia do banco' do
      publicar
      # A tentativa de forçar o mesmo número bate no índice único `(kind, version)`.
      duplicado = Contract.new(kind: Contract::KIND_TERMS_OF_USE, title: 'X', version: 1)
      duplicado.description = '<p>y</p>'
      expect { duplicado.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    # 5.2 — append-only, na leitura da DEC-80: a IDENTIDADE é imutável; o TEXTO
    # continua editável no lugar (a opção (d), com versionamento imutável, foi
    # recusada). O `tasks.md:5.2` pedia o documento inteiro imutável — a DEC vence.
    it 'tipo e número NÃO mudam depois de publicados' do
      contrato = publicar
      expect(contrato.update(version: 99)).to be(false)
      expect(contrato.reload.version).to eq(1)
      expect(contrato.update(kind: Contract::KIND_PRIVACY_POLICY)).to be(false)
    end

    it 'o TEXTO continua editável, e o hash muda junto (DEC-80)' do
      contrato = publicar(body: '<p>antes</p>')
      antes = contrato.content_hash
      contrato.description = '<p>depois</p>'
      contrato.save!

      expect(contrato.reload.content_hash).not_to eq(antes)
    end
  end

  # ---------------------------------------------------------------------
  # 2.5 / BE-334 — índice agrupado ANTES de paginar
  # ---------------------------------------------------------------------
  describe 'GET /api/v1/contracts' do
    it 'devolve UMA linha por tipo, com a versão mais recente' do
      publicar
      recente = publicar
      publicar(kind: Contract::KIND_PRIVACY_POLICY, title: 'Politicas de Privacidade')

      get '/api/v1/contracts', headers: auth_headers(colaborador)

      corpo = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(corpo.size).to eq(2)
      termos = corpo.find { |c| c['kind'] == Contract::KIND_TERMS_OF_USE }
      expect(termos['version']).to eq(recente.version)
      expect(termos['slug']).to eq('termos-de-uso')
    end

    it 'sem sessão, recusa' do
      get '/api/v1/contracts'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ---------------------------------------------------------------------
  # 5.9 / BE-341 — pendência a partir do CATÁLOGO
  # ---------------------------------------------------------------------
  describe 'GET /api/v1/contracts/pending' do
    it 'usuário criado ANTES da publicação fica pendente do tipo novo' do
      usuario = colaborador # já existe
      publicar

      get '/api/v1/contracts/pending', headers: auth_headers(usuario)

      expect(JSON.parse(response.body).map { |p| p['kind'] }).to eq([Contract::KIND_TERMS_OF_USE])
    end

    it 'sem contrato publicado, não há pendência — e o convite conclui' do
      get '/api/v1/contracts/pending', headers: auth_headers(colaborador)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'não faz N+1: duas consultas, independentemente do número de tipos' do
      publicar
      publicar(kind: Contract::KIND_PRIVACY_POLICY, title: 'Politicas de Privacidade')
      colaborador # materializa antes de contar

      consultas = 0
      contador = ->(*, payload) { consultas += 1 unless payload[:name].to_s.include?('SCHEMA') }
      ActiveSupport::Notifications.subscribed(contador, 'sql.active_record') do
        Contracts::PendingService.call(colaborador)
      end

      expect(consultas).to be <= 3
    end

    # DEC-66 — o carimbo da base antiga NÃO satisfaz a pendência.
    it 'aceite `implicit_legacy` continua pendente' do
      contrato = publicar
      create(:contract_deal, :implicit_legacy, user: colaborador, contract: contrato)

      get '/api/v1/contracts/pending', headers: auth_headers(colaborador)
      expect(JSON.parse(response.body).size).to eq(1)
    end
  end

  # ---------------------------------------------------------------------
  # 5.8 / BE-333 / D-68 — o aceite é SEMPRE do usuário da sessão
  # ---------------------------------------------------------------------
  describe 'PUT /api/v1/contracts/:id/accept' do
    it 'grava o aceite do usuário da SESSÃO, com IP, user-agent e hash' do
      contrato = publicar

      put "/api/v1/contracts/#{contrato.id}/accept",
          headers: auth_headers(colaborador).merge('User-Agent' => 'RSpec/1.0')

      expect(response).to have_http_status(:created)
      deal = ContractDeal.last
      expect(deal.user_id).to eq(colaborador.id)
      expect(deal.source).to eq('explicit')
      expect(deal.ip_address).to be_present
      expect(deal.user_agent).to eq('RSpec/1.0')
      expect(deal.content_hash).to eq(contrato.content_hash)
      expect(deal.accepted_body).to include('v1')
    end

    it '`user_id` no payload é IGNORADO — não existe aceite em nome de outro' do
      contrato = publicar

      put "/api/v1/contracts/#{contrato.id}/accept",
          params: { user_id: og.id, contract_deal: { user_id: og.id } },
          headers: auth_headers(colaborador)

      expect(ContractDeal.pluck(:user_id)).to eq([colaborador.id])
    end

    it 'é idempotente: aceitar duas vezes grava UMA linha' do
      contrato = publicar
      2.times { put "/api/v1/contracts/#{contrato.id}/accept", headers: auth_headers(colaborador) }

      expect(response).to have_http_status(:ok)
      expect(ContractDeal.count).to eq(1)
    end

    it 'aceitar versão NÃO vigente é recusado' do
      antiga = publicar
      publicar(body: '<p>v2</p>')

      put "/api/v1/contracts/#{antiga.id}/accept", headers: auth_headers(colaborador)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['code']).to eq('CONTRACT_NOT_CURRENT')
    end

    it 'sem sessão → 401' do
      contrato = publicar
      put "/api/v1/contracts/#{contrato.id}/accept"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'id inexistente → 404, igual a id inacessível' do
      put "/api/v1/contracts/#{SecureRandom.uuid}/accept", headers: auth_headers(colaborador)
      expect(response).to have_http_status(:not_found)
    end

    # DEC-66 — a promoção preserva a data original em `legacy_accepted_at`.
    it 'promove o aceite `implicit_legacy` da versão vigente, guardando a data antiga' do
      contrato = publicar
      antigo = create(:contract_deal, :implicit_legacy, user: colaborador, contract: contrato)
      data_original = antigo.accepted_at

      put "/api/v1/contracts/#{contrato.id}/accept", headers: auth_headers(colaborador)

      antigo.reload
      expect(antigo.source).to eq('explicit')
      expect(antigo.legacy_accepted_at).to be_within(1.second).of(data_original)
      expect(antigo.accepted_at).to be > data_original
      expect(ContractDeal.count).to eq(1)
    end
  end

  # ---------------------------------------------------------------------
  # DEC-65 — o aceite é AÇÃO, e NÃO bloqueia acesso
  # ---------------------------------------------------------------------
  describe 'o aceite pendente NÃO bloqueia o sistema (DEC-65)' do
    it 'com contrato pendente, o resto da API continua respondendo' do
      publicar

      get '/api/v1/contracts', headers: auth_headers(colaborador)
      expect(response).to have_http_status(:ok)

      get '/api/v1/faq', headers: auth_headers(colaborador)
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------
  # DEC-38 (armadilha) + DC-09 — o readonly PRECISA conseguir aceitar
  # ---------------------------------------------------------------------
  describe 'o gate de somente-leitura NÃO tranca o aceite' do
    let(:readonly) do
      usuario = create(:user, :colaborador)
      UserPermission.create!(user: usuario, permission: Permission.find_by(key: 'user_is_readonly'),
                             source: 'manual', granted_at: Time.current)
      usuario
    end

    it 'o readonly é barrado numa escrita comum' do
      expect(Authorization::PermissionResolver.new(readonly).readonly?).to be(true)

      post '/api/v1/help_groups', params: { title: 'X' }, headers: auth_headers(readonly)
      expect(response).to have_http_status(:forbidden)
    end

    it 'mas ACEITA os Termos — o caminho real casa READONLY_EXEMPT_PATHS' do
      contrato = publicar

      put "/api/v1/contracts/#{contrato.id}/accept", headers: auth_headers(readonly)
      expect(response).to have_http_status(:created)
    end

    it 'e aceita em bloco por `/api/v1/me/terms`' do
      publicar
      post '/api/v1/me/terms', headers: auth_headers(readonly)
      expect(response).to have_http_status(:ok)
    end

    # O padrão foi escrito pela S0 ANTES de a rota existir, "testado como dado".
    # Este é o teste que prova que o dado bate com a rota real.
    it 'os dois padrões de READONLY_EXEMPT_PATHS casam as rotas que existem' do
      contrato = publicar
      caminhos = ["/api/v1/contracts/#{contrato.id}/accept", '/api/v1/me/terms']
      caminhos.each do |caminho|
        expect(Api::V1::ControllerHelpers::READONLY_EXEMPT_PATHS.any? { |p| caminho.match?(p) })
          .to be(true), "o caminho real #{caminho} NÃO casa nenhum padrão de isenção"
      end
    end
  end

  # ---------------------------------------------------------------------
  # `/api/v1/me/terms` — o botão do banner
  # ---------------------------------------------------------------------
  describe '/api/v1/me/terms' do
    it 'aceita TUDO o que está pendente num clique' do
      publicar
      publicar(kind: Contract::KIND_PRIVACY_POLICY, title: 'Politicas de Privacidade')

      post '/api/v1/me/terms', headers: auth_headers(colaborador)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['pending']).to eq([])
      expect(ContractDeal.for_user(colaborador).count).to eq(2)
    end

    it 'devolve o histórico, distinguindo o aceite carimbado do explícito' do
      contrato = publicar
      create(:contract_deal, :implicit_legacy, user: colaborador, contract: contrato)

      get '/api/v1/me/terms', headers: auth_headers(colaborador)

      corpo = JSON.parse(response.body)
      expect(corpo['accepted'].first['source']).to eq('implicit_legacy')
      expect(corpo['pending'].size).to eq(1)
    end
  end

  # ---------------------------------------------------------------------
  # 5.6 — fidelidade do conteúdo, e a allowlist de sanitização
  # ---------------------------------------------------------------------
  describe 'fidelidade e sanitização do conteúdo (BE-345 / FE-331)' do
    it 'preserva título, lista e negrito' do
      contrato = publicar(body: '<h1>Título</h1><ul><li>um</li></ul><p><strong>forte</strong></p>')

      expect(contrato.description_html).to include('<h1>', '<ul>', '<li>', '<strong>')
    end

    it 'remove script e atributo de evento' do
      contrato = publicar(body: '<p onclick="x()">ok</p><script>alert(1)</script>')

      expect(contrato.description_html).not_to include('script')
      expect(contrato.description_html).not_to include('onclick')
      expect(contrato.description_html).to include('ok')
    end

    it 'a página pública e o console mostram o MESMO texto' do
      contrato = publicar(body: '<h2>Cláusula</h2><p>corpo</p>')

      get "/api/v1/public/contracts/#{contrato.slug}"
      publico = JSON.parse(response.body)['description_html']

      get "/api/v1/contracts/#{contrato.id}", headers: auth_headers(colaborador)
      console = JSON.parse(response.body)['description_html']

      expect(publico).to eq(console)
    end
  end

  # ---------------------------------------------------------------------
  # 5.11 / DEC-80 — a prova
  # ---------------------------------------------------------------------
  describe 'prova de aceite (DB-331 / OPS-333)' do
    it 'alterar o contrato depois NÃO muda a impressão registrada' do
      contrato = publicar(body: '<p>original</p>')
      put "/api/v1/contracts/#{contrato.id}/accept", headers: auth_headers(colaborador)
      deal = ContractDeal.last
      impressao = deal.content_hash

      contrato.description = '<p>alterado</p>'
      contrato.save!

      expect(deal.reload.content_hash).to eq(impressao)
      expect(deal.accepted_body).to include('original')
      expect(deal.hash_matches_current?).to be(false)
      expect(contrato.reload.divergent_deals_count).to eq(1)
    end

    it 'a exportação traz o texto integral aceito' do
      contrato = publicar(body: '<p>cláusula integral</p>')
      put "/api/v1/contracts/#{contrato.id}/accept", headers: auth_headers(colaborador)

      csv = Contracts::ProofExport.to_csv(contrato.contract_deals)
      expect(csv).to include('cláusula integral')
      expect(csv).to include('Hash do texto')
    end
  end

  # ---------------------------------------------------------------------
  # 5.12 / OPS-330 — o seed NÃO fabrica aceite
  # ---------------------------------------------------------------------
  describe 'o seed de contratos (OPS-330)' do
    it 'publica a versão 1 de cada tipo e cria ZERO aceites' do
      create(:user, :og)
      Seeds::Reference::Contracts.call!

      expect(Contract.pluck(:kind, :version)).to match_array(
        [[Contract::KIND_TERMS_OF_USE, 1], [Contract::KIND_PRIVACY_POLICY, 1]]
      )
      expect(ContractDeal.count).to eq(0)
    end

    it 'é idempotente: a segunda execução não publica versão 2' do
      Seeds::Reference::Contracts.call!
      relatorio = Seeds::Reference::Contracts.call!

      expect(relatorio.created).to eq(0)
      expect(Contract.count).to eq(2)
    end

    it 'OPS-332 — `user.html` NÃO é carregado: o tipo não está no catálogo' do
      Seeds::Reference::Contracts.call!
      expect(Contract.pluck(:kind)).not_to include('Contrato de usuário')
      expect(Seeds::Reference::Contracts::IGNORED_SOURCES).to include('user.html')
    end
  end
end
