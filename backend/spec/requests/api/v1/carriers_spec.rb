# frozen_string_literal: true

require 'rails_helper'

# S3 / BE-067..BE-071 — portadores.
RSpec.describe 'Portadores', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:og) { create(:user, :og) }

  describe 'GET /api/v1/carriers — paginação REAL (D-20 / 4.3.7)' do
    # A verificação literal da tarefa 2.1.1: com 45 portadores, a segunda página
    # de 20 traz 20 a partir do 21º e o header diz 45.
    it 'aplica `page`/`per_page` e o total do cabeçalho é o total SEM limite' do
      45.times { |i| create(:carrier, title: format('Portador %02d', i)) }

      get '/api/v1/carriers', params: { page: 2, per_page: 20, ordering_keys: ['title'] },
                              headers: auth_headers(og)

      expect(response).to have_http_status(:ok)
      corpo = JSON.parse(response.body)
      expect(corpo.size).to eq(20)
      expect(corpo.first['title']).to eq('Portador 20')
      expect(response.headers['X-Total-Count']).to eq('45')
      expect(response.headers['X-Page']).to eq('2')
      expect(response.headers['X-Total-Pages']).to eq('3')
    end

    it 'páginas diferentes trazem registros diferentes' do
      6.times { create(:carrier) }

      get '/api/v1/carriers', params: { page: 1, per_page: 3 }, headers: auth_headers(og)
      p1 = JSON.parse(response.body).map { |c| c['id'] }
      get '/api/v1/carriers', params: { page: 2, per_page: 3 }, headers: auth_headers(og)
      p2 = JSON.parse(response.body).map { |c| c['id'] }

      expect(p1 & p2).to be_empty
    end
  end

  # 2.1.2 / BE-067 (2ª metade) — a **simetria da busca**.
  #
  # No legado o ramo com `ordering_keys` e o sem montavam consultas diferentes:
  # o não-ordenado fazia `q.upcase` e o ordenado não. Com dado em caixa mista o
  # mesmo termo devolvia conjuntos diferentes conforme a coluna clicada.
  describe 'simetria da busca' do
    it 'o mesmo `q` devolve o MESMO conjunto com e sem ordenação' do
      create(:carrier, title: 'Fomento Alfa')
      create(:carrier, title: 'FOMENTO BETA')
      create(:carrier, title: 'Securitizadora Gama')

      get '/api/v1/carriers', params: { q: 'fomento' }, headers: auth_headers(og)
      sem_ordem = JSON.parse(response.body).map { |c| c['id'] }.sort

      get '/api/v1/carriers', params: { q: 'fomento', ordering_keys: ['title'], ordering_style: ['down'] },
                              headers: auth_headers(og)
      com_ordem = JSON.parse(response.body).map { |c| c['id'] }.sort

      expect(sem_ordem).to eq(com_ordem)
      expect(sem_ordem.size).to eq(2)
    end

    it 'chave de ordenação DESCONHECIDA é ignorada, não 500' do
      create(:carrier)
      get '/api/v1/carriers', params: { ordering_keys: ['drop_table'] }, headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
    end
  end

  # 4.3.8 / DC-12 — `001` sobrevive à ida e à volta inteira.
  describe '`bank_code` string' do
    it 'preserva `001` na criação, na leitura, na edição e na serialização' do
      post '/api/v1/carriers', params: { title: 'Banco do Brasil S.A.', bank_code: '001' },
                               headers: auth_headers(og)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['bank_code']).to eq('001')

      id = JSON.parse(response.body)['id']
      expect(Carrier.find(id).bank_code).to eq('001')

      get "/api/v1/carriers/#{id}", headers: auth_headers(og)
      expect(JSON.parse(response.body)['bank_code']).to eq('001')

      put "/api/v1/carriers/#{id}", params: { title: 'Banco do Brasil' }, headers: auth_headers(og)
      expect(JSON.parse(response.body)['bank_code']).to eq('001')
    end
  end

  # 2.1.5 / DC-09 — derivado no servidor, e NÃO aceito do payload.
  #
  # A FÓRMULA é a do legado, replicada (DEC-30): subordinadas ÷ SÊNIOR × 100.
  # O golden que a trava é `spec/models/carriers_percentual_golden_spec.rb`.
  describe '`subordinated_accounts_percent`' do
    it 'é derivado das cotas e IGNORA o que vier do cliente' do
      post '/api/v1/carriers',
           params: { title: 'FIDC Exemplo', senior_accounts: 750, subordinated_accounts: 250,
                     subordinated_accounts_percent: 99.9 },
           headers: auth_headers(og)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['subordinated_accounts_percent'].to_f).to eq(33.33)
    end

    it 'sem cota sênior é `0` — a guarda de divisão por zero do legado, agora no SERVIDOR' do
      post '/api/v1/carriers', params: { title: 'Factoring Sem Cotas' }, headers: auth_headers(og)
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)['subordinated_accounts_percent'].to_f).to eq(0.0)
    end

    it 'recalcula quando as cotas mudam' do
      carrier = create(:carrier, senior_accounts: 800, subordinated_accounts: 200)
      expect(carrier.subordinated_accounts_percent.to_f).to eq(25.0)

      put "/api/v1/carriers/#{carrier.id}", params: { subordinated_accounts: 600 }, headers: auth_headers(og)
      expect(JSON.parse(response.body)['subordinated_accounts_percent'].to_f).to eq(75.0)
    end
  end

  # BE-071 — comportamento PRESERVADO de propósito ("Cloud #7036"). É teste de
  # não-regressão da preservação: alguém acrescentar `uniqueness` reprova aqui.
  it '4.3.12 — dois portadores com o MESMO título são aceitos' do
    post '/api/v1/carriers', params: { title: 'Cloud' }, headers: auth_headers(og)
    expect(response).to have_http_status(:created)
    post '/api/v1/carriers', params: { title: 'Cloud' }, headers: auth_headers(og)
    expect(response).to have_http_status(:created)
    expect(Carrier.where(title: 'Cloud').count).to eq(2)
  end

  describe 'agente financeiro (DB-059)' do
    it 'aceita os quatro valores do conjunto fechado' do
      Carrier::FINANCIAL_AGENTS.each do |agente|
        post '/api/v1/carriers', params: { title: "Portador #{agente}", financial_agent: agente },
                                 headers: auth_headers(og)
        expect(response).to have_http_status(:created), agente
      end
    end

    it 'recusa valor fora do conjunto' do
      post '/api/v1/carriers', params: { title: 'X', financial_agent: 'Banco' }, headers: auth_headers(og)
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'cidade e UF (DB-060)' do
    it 'normaliza a UF em 2 maiúsculas e recusa UF inexistente' do
      post '/api/v1/carriers', params: { title: 'Y', city: 'Campinas', uf: 'sp' }, headers: auth_headers(og)
      expect(response).to have_http_status(:created)
      corpo = JSON.parse(response.body)
      expect(corpo['uf']).to eq('SP')
      expect(corpo['city_label']).to eq('Campinas, SP')

      post '/api/v1/carriers', params: { title: 'Z', uf: 'XX' }, headers: auth_headers(og)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'sem cidade e sem UF o rótulo é `-` (comportamento preservado)' do
      post '/api/v1/carriers', params: { title: 'Sem endereço' }, headers: auth_headers(og)
      expect(JSON.parse(response.body)['city_label']).to eq('-')
    end
  end

  # BE-068 / DC-08 — o detalhe passa a ser ALCANÇÁVEL. No legado o HTML e o SCSS
  # existem e nenhuma rota chega neles.
  describe 'GET /api/v1/carriers/:id' do
    it 'responde 200 no existente e 404 no inexistente' do
      carrier = create(:carrier)
      get "/api/v1/carriers/#{carrier.id}", headers: auth_headers(og)
      expect(response).to have_http_status(:ok)

      get "/api/v1/carriers/#{SecureRandom.uuid}", headers: auth_headers(og)
      expect(response).to have_http_status(:not_found)
    end
  end

  # BE-070 / D-24 — a assimetria mais perigosa do bloco.
  describe 'DELETE /api/v1/carriers/:id' do
    it 'exclui quando não há vínculo' do
      carrier = create(:carrier)
      delete "/api/v1/carriers/#{carrier.id}", headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
      expect(Carrier.exists?(carrier.id)).to be(false)
    end

    # 4.3.3 — o vínculo de verdade nasce na S4/S5/S6. Enquanto as tabelas não
    # existem, o que se pode provar é que a REGRA está declarada e que nada
    # cascateia. O exemplo de comportamento ponta a ponta é a tarefa 5.7.
    it 'declara os três dependentes que bloqueiam, e NENHUM deles é cascata' do
      expect(Carrier.blocking_dependents.keys)
        .to contain_exactly('ProjectToCarrierConnection', 'RiskControl', 'ReceivableEntry')

      # O anexo do ActiveStorage é a única cascata legítima: o logo pertence ao
      # portador e não sobrevive a ele. O que não pode cascatear é DADO DE
      # DOMÍNIO de outra fatia.
      cascatas = Carrier.reflect_on_all_associations
                        .select { |a| a.options[:dependent] == :destroy }
                        .reject { |a| a.name.to_s.start_with?('logo_') }
      expect(cascatas).to be_empty,
                          "associação em cascata no portador: #{cascatas.map(&:name).join(', ')} — " \
                          'no legado era `risk_controls, dependent: :destroy` e excluir portador apagava limites (D-24)'
    end

    # ------------------------------------------------------------------------
    # S3 / tarefa 5.7 — **a assimetria mais perigosa do legado**, ponta a ponta.
    #
    # Enquanto `risk_controls` não existia, a 4.3.3 acima só conseguia provar que
    # a REGRA estava declarada. A S5 entregou a tabela, então o cenário de
    # verdade passa a ser exercível: excluir um portador que tem limite de risco
    # devolve **422** e **o limite permanece**.
    #
    # No legado (`../sfg/app/models/carrier.rb`, `has_many :risk_controls,
    # dependent: :destroy`) esta mesma chamada devolvia sucesso e **apagava os
    # limites** — o teto que autoriza toda operação de crédito do Safegold —
    # sem 422, sem aviso e sem trilha. Não é limpeza de cadastro: é perda
    # silenciosa de dado financeiro.
    #
    # O teste verifica os DOIS lados (disciplina C3 do DEC-41): que o bloqueio
    # existe **e** que o dado sobrevive. Um teste que só olhasse o 422 passaria
    # mesmo se o limite tivesse sido apagado antes do `throw(:abort)`.
    describe 'portador com limite de risco (5.7 / D-24 / BE-070)' do
      let(:project) { create(:project) }
      let(:carrier) { create(:carrier) }
      let!(:control) { create(:risk_control, project: project, carrier: carrier) }

      it 'responde 422, NOMEIA o vínculo, e o limite PERMANECE' do
        expect(RiskControl.where(carrier_id: carrier.id).count).to eq(1)

        delete "/api/v1/carriers/#{carrier.id}", headers: auth_headers(og)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['error']).to include('limite(s) de risco')

        # O que o legado perdia.
        expect(RiskControl.exists?(control.id)).to be(true),
                                                   'o limite de risco foi APAGADO ao excluir o portador — é exatamente o D-24'
        expect(RiskControl.find(control.id).limite).to eq(control.limite)
        # E o portador também continua: bloquear é recusar, não excluir pela metade.
        expect(Carrier.exists?(carrier.id)).to be(true)
      end

      # O limite SOZINHO basta para bloquear. A factory de `risk_control` cria a
      # conexão projeto↔portador junto (é o critério do servidor no `create`), e
      # sem remover a conexão o 422 poderia estar vindo só dela — a regra do
      # `risk_control` passaria despercebida se ela sumisse.
      it 'bloqueia mesmo quando o limite é o ÚNICO vínculo' do
        ProjectToCarrierConnection.where(carrier_id: carrier.id).delete_all

        expect(carrier.destroy).to be(false)
        expect(carrier.errors.full_messages.to_sentence).to include('limite(s) de risco')
        expect(RiskControl.exists?(control.id)).to be(true)
        expect(Carrier.exists?(carrier.id)).to be(true)
      end

      # A terceira camada: mesmo contornando o model, o Postgres recusa. A FK
      # `risk_controls.carrier_id → carriers` nasce `NO ACTION`.
      # O `requires_new: true` é obrigatório aqui, não estilo: a violação de FK
      # aborta a transação do exemplo, e sem o SAVEPOINT toda consulta seguinte
      # morre com `PG::InFailedSqlTransaction` — inclusive a que confere que o
      # limite sobreviveu, que é o ponto do teste.
      it 'o banco recusa a exclusão mesmo por fora do model (FK NO ACTION)' do
        expect do
          ActiveRecord::Base.transaction(requires_new: true) { Carrier.where(id: carrier.id).delete_all }
        end.to raise_error(ActiveRecord::InvalidForeignKey)

        expect(RiskControl.exists?(control.id)).to be(true)
        expect(Carrier.exists?(carrier.id)).to be(true)
      end

      # O outro lado do C3: removido o limite, a exclusão passa. Um teste que só
      # verifique a trava passa com a trava apontando para o lado errado.
      it 'com o limite removido, a exclusão volta a funcionar' do
        control.destroy!
        ProjectToCarrierConnection.where(carrier_id: carrier.id).delete_all

        delete "/api/v1/carriers/#{carrier.id}", headers: auth_headers(og)

        expect(response).to have_http_status(:ok)
        expect(Carrier.exists?(carrier.id)).to be(false)
      end
    end
  end

  # DEC-47 + OPS-051 — o logo volta, e o tipo REAL do arquivo é verificado.
  describe 'logo (DEC-47 / DEC-91)' do
    def upload(conteudo, filename, content_type)
      caminho = Rails.root.join("tmp/#{filename}")
      FileUtils.mkdir_p(caminho.dirname)
      File.binwrite(caminho, conteudo)
      Rack::Test::UploadedFile.new(caminho, content_type)
    end

    let(:png) do
      # PNG 1×1 real — o cabeçalho é o que a detecção de tipo lê.
      Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
    end

    it 'anexa um PNG de verdade e devolve a URL' do
      carrier = create(:carrier)
      post "/api/v1/carriers/#{carrier.id}/logo",
           params: { file: upload(png, 'logo.png', 'image/png') }, headers: auth_headers(og)

      expect(response).to have_http_status(:ok)
      expect(carrier.reload.logo).to be_attached
      expect(JSON.parse(response.body)['logo_url']).to be_present
    end

    # 4.3.11 — o legado tinha `MediaTypeSpoofDetector#spoofed? → false`: a
    # detecção estava DESLIGADA e um executável renomeado entrava.
    it 'RECUSA um executável renomeado para .png' do
      carrier = create(:carrier)
      exe = "MZ\x90\x00\x03\x00\x00\x00#{'A' * 200}"

      post "/api/v1/carriers/#{carrier.id}/logo",
           params: { file: upload(exe, 'malicioso.png', 'image/png') }, headers: auth_headers(og)

      expect(response).to have_http_status(:unprocessable_content)
      expect(carrier.reload.logo).not_to be_attached
    end

    it 'remove o logo' do
      carrier = create(:carrier)
      post "/api/v1/carriers/#{carrier.id}/logo",
           params: { file: upload(png, 'logo.png', 'image/png') }, headers: auth_headers(og)
      delete "/api/v1/carriers/#{carrier.id}/logo", headers: auth_headers(og)
      expect(response).to have_http_status(:ok)
    end
  end
end
