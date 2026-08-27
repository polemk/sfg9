# frozen_string_literal: true

require 'rails_helper'

# S11 — **os testes de escopo dos endpoints de disponibilidade** (seção 6 da
# fila).
#
# A seção 6.1 é a mais importante da fatia: **`/projects/:id/availability` era
# um IDOR sem autenticação** (D-01). O controller do legado herdava de
# `ApplicationController` — não do `PubApplicationController` — e a primeira
# linha era `Project.find(params[:id] || params[:project_id])`, sem escopo e sem
# sessão. Não é "o filtro é descartado quando chega um id", como nos irmãos
# D-16/D-29/D-76/D-100: é **não havia filtro nenhum**.
#
# Cada endpoint que aceita id por parâmetro (`template_id`, `entry_id`,
# `company_id`, `parent_id`, `:id` do projeto) leva um exemplo com id de OUTRO
# projeto. **Busca → vazio; detalhe/escrita → 404. Nunca 403** — 403 confirmaria
# a existência do registro alheio e transformaria o endpoint num oráculo de ids.
RSpec.describe 'Api::V1 disponibilidade — escopo e autenticação', type: :request do
  before { UserType.seed_default_types! }

  # DEC-99: OG e Admin enxergam TODOS os projetos. Os casos de escopo usam
  # **Gerente**, o papel mais alto que continua preso à participação — usar
  # admin faria os exemplos passarem por motivo errado.
  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro_gerente) { create(:user, user_type: UserType.gerente) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'disp-a', name: 'Disponibilidade A') }
  let!(:projeto_b) { create_project_with_owner(outro_gerente, slug: 'disp-b', name: 'Disponibilidade B') }

  let!(:empresa_a) { create(:company, project: projeto_a) }
  let!(:empresa_b) { create(:company, project: projeto_b) }

  let!(:padrao_a) { create(:project_availability_template, project: projeto_a, title: 'Caixa A') }
  let!(:padrao_b) { create(:project_availability_template, project: projeto_b, title: 'Caixa B') }

  def json = JSON.parse(response.body)

  # ===================================================================
  describe '6.1 — D-01: o IDOR que dá nome à família' do
    it 'GET /projects/:id/availability SEM credencial responde 401' do
      get "/api/v1/projects/#{projeto_a.id}/availability"

      expect(response).to have_http_status(401)
      expect(response.body).not_to include('by_entry')
    end

    it 'GET /availability sem credencial responde 401' do
      get '/api/v1/availability'
      expect(response).to have_http_status(401)
    end

    it 'com credencial válida, o `:id` de um projeto de que o usuário NÃO participa responde 404' do
      get "/api/v1/projects/#{projeto_b.id}/availability", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(404)
      # Nenhum valor financeiro do outro projeto sai no corpo.
      expect(response.body).not_to include(padrao_b.title)
    end

    it 'e o `:id` do PRÓPRIO projeto funciona — a negação sozinha não prova escopo' do
      get "/api/v1/projects/#{projeto_a.id}/availability", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(json['project_id']).to eq(projeto_a.id)
      expect(json).to have_key('by_entry')
    end

    it 'id malformado responde 404, não 500 — o Postgres levantaria comparando uuid com texto' do
      get '/api/v1/projects/nao-e-uuid/availability', headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end

    it 'BE-149 — o corpo é objeto, não uma string JSON dentro de um JSON' do
      get '/api/v1/availability', headers: auth_headers(gerente, project: projeto_a)

      expect(json).to be_a(Hash)
      expect(json['dates']).to be_a(Array)
    end

    it 'mês inválido responde 422 — o legado dava 500 em `Date.new(ano, 13, 1)`' do
      get '/api/v1/availability?month=13', headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)
    end
  end

  # ===================================================================
  describe '6.2 — escopo cruzado, um caso por endpoint com id por parâmetro' do
    it '6.2.1 — grade com `company_id` de OUTRO projeto responde 422' do
      get "/api/v1/availability_entries?date=2026-08-14&company_id=#{empresa_b.id}",
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      # E não "cai calado na consolidação geral", que é o que o legado fazia.
      expect(json['error']).to include('Empresa inválida')
    end

    it '6.2.2 — update de lançamento de OUTRO projeto responde 404 e o lançamento PERMANECE' do
      alheio = Availability::EntryService.create(
        project: projeto_b,
        attrs: { availability_template_id: padrao_b.id, company_id: empresa_b.id,
                 date: '2026-08-14', value: 500 }
      ).fetch(:data)

      put "/api/v1/availability_entries/#{alheio.id}", params: { value: 1 },
                                                       headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(404)
      expect(alheio.reload.value).to eq(500)

      delete "/api/v1/availability_entries/#{alheio.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
      expect(AvailabilityEntry.exists?(alheio.id)).to be(true)
    end

    it '6.2.3 — a árvore do projeto A não traz padrão do B, e TRAZ o do A' do
      get '/api/v1/project_availabilities', headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      titulos = json.map { |t| t['title'] }
      expect(titulos).to include('Caixa A')
      expect(titulos).not_to include('Caixa B')
    end

    it '6.2.3 — detalhe de padrão de OUTRO projeto responde 404' do
      get "/api/v1/project_availabilities/#{padrao_b.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end

    it '6.2.4 — criar padrão com `parent_id` de OUTRO projeto é RECUSADO' do
      post '/api/v1/project_availabilities',
           params: { title: 'Tentativa', operation_type: 'C', deadline_type: 'CP',
                     parent_template_id: padrao_b.id },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(ProjectAvailabilityTemplate.find_by(title: 'Tentativa')).to be_nil
    end

    it '6.2.5 — ativar/desativar/remover padrão de OUTRO projeto responde 404 e NENHUM job é enfileirado' do
      allow(ActivateProjectTemplateJob).to receive(:perform_later)
      allow(DeactivateProjectTemplateJob).to receive(:perform_later)
      allow(RemoveProjectTemplateJob).to receive(:perform_later)

      cabecalhos = auth_headers(gerente, project: projeto_a)
      post "/api/v1/project_availabilities/#{padrao_b.id}/activate", headers: cabecalhos
      expect(response).to have_http_status(404)
      post "/api/v1/project_availabilities/#{padrao_b.id}/deactivate", headers: cabecalhos
      expect(response).to have_http_status(404)
      delete "/api/v1/project_availabilities/#{padrao_b.id}", headers: cabecalhos
      expect(response).to have_http_status(404)

      expect(ActivateProjectTemplateJob).not_to have_received(:perform_later)
      expect(DeactivateProjectTemplateJob).not_to have_received(:perform_later)
      expect(RemoveProjectTemplateJob).not_to have_received(:perform_later)
    end

    it '6.2.6 — `project_id` no CORPO apontando outro projeto é IGNORADO' do
      post '/api/v1/availability_entries',
           params: { availability_template_id: padrao_a.id, company_id: empresa_a.id,
                     date: '2026-08-14', value: 42, project_id: projeto_b.id },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      expect(AvailabilityEntry.find(json['id']).project_id).to eq(projeto_a.id)
    end

    it '6.2.7 — o CATÁLOGO GLOBAL é legível sem projeto corrente e NÃO é escopado' do
      global = create(:global_availability_template, title: 'Padrão do catálogo')
      sem_projeto = create(:user, user_type: UserType.gerente)

      get '/api/v1/availability_templates', headers: auth_headers(sem_projeto)

      expect(response).to have_http_status(200)
      expect(json.map { |t| t['id'] }).to include(global.id)
      # Regra OPOSTA à das entidades de projeto, e de propósito: o menu esconde
      # a tela de administração do catálogo, não o dado do catálogo.
      expect(json.first['project_id']).to be_nil
    end
  end

  # ===================================================================
  describe 'D-06 / BE-132 — a busca do catálogo global VOLTA A FUNCIONAR' do
    before do
      create(:global_availability_template, title: 'Disponibilidade imediata')
      create(:global_availability_template, title: 'Recebíveis futuros')
    end

    it 'busca por SUBSTRING, não só por prefixo' do
      get '/api/v1/availability_templates?q=imediata', headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(json.map { |t| t['title'] }).to eq(['Disponibilidade imediata'])
    end

    it 'texto com caractere especial não derruba a requisição' do
      get '/api/v1/availability_templates?q=100%25', headers: auth_headers(gerente)
      expect(response).to have_http_status(200)

      get "/api/v1/availability_templates?q=#{CGI.escape("a'b_%")}", headers: auth_headers(gerente)
      expect(response).to have_http_status(200)
      expect(json).to eq([])
    end

    it 'catálogo vazio devolve lista vazia, sem SQL inválido' do
      GlobalAvailabilityTemplate.delete_all
      get '/api/v1/availability_templates?q=qualquer', headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(json).to eq([])
    end

    it 'D-07/D-20 — a paginação existe de fato' do
      get '/api/v1/availability_templates?per_page=1', headers: auth_headers(gerente)

      expect(response).to have_http_status(200)
      expect(json.size).to eq(1)
      expect(response.headers['X-Total-Count']).to eq('2')
      expect(response.headers['X-Total-Pages']).to eq('2')
    end
  end

  # ===================================================================
  describe 'BE-134 / DB-132 — o formulário do catálogo global é respeitado' do
    it 'criar com `is_mandatory = false` GRAVA false (o legado forçava `|= 1`)' do
      post '/api/v1/availability_templates',
           params: { title: 'Opcional', operation_type: 'C', deadline_type: 'CP', is_mandatory: false },
           headers: auth_headers(gerente)

      expect(response).to have_http_status(201)
      expect(GlobalAvailabilityTemplate.find(json['id']).is_mandatory).to be(false)
    end

    it 'a propagação para projetos existentes SÓ acontece quando o usuário a pede' do
      allow(PropagateGlobalTemplateJob).to receive(:perform_later)

      post '/api/v1/availability_templates',
           params: { title: 'Sem propagar', operation_type: 'C', deadline_type: 'CP' },
           headers: auth_headers(gerente)
      expect(PropagateGlobalTemplateJob).not_to have_received(:perform_later)

      post '/api/v1/availability_templates',
           params: { title: 'Com propagação', operation_type: 'C', deadline_type: 'CP',
                     should_insert_on_existing_projects: true },
           headers: auth_headers(gerente)
      expect(PropagateGlobalTemplateJob).to have_received(:perform_later).once
    end

    it 'BE-139 — filho obrigatório exige pai obrigatório' do
      pai = create(:global_availability_template, is_mandatory: false)

      post '/api/v1/availability_templates',
           params: { title: 'Filho obrigatório', operation_type: 'C', deadline_type: 'CP',
                     parent_template_id: pai.id, is_mandatory: true },
           headers: auth_headers(gerente)

      expect(response).to have_http_status(422)
      expect(json['error']).to include('obrigatórios')
    end
  end

  # ===================================================================
  describe 'FE-141 / D-23 — a permissão de cadastro vale NO SERVIDOR' do
    it 'o Colaborador LÊ o catálogo global mas não cria' do
      colaborador = create(:user, user_type: UserType.colaborador)
      Membership.create!(project: projeto_a, user: colaborador, role: 'participante')
      create(:global_availability_template)

      get '/api/v1/availability_templates', headers: auth_headers(colaborador, project: projeto_a)
      expect(response).to have_http_status(200)

      post '/api/v1/availability_templates',
           params: { title: 'Não deveria', operation_type: 'C', deadline_type: 'CP' },
           headers: auth_headers(colaborador, project: projeto_a)
      expect(response).to have_http_status(403)
      expect(GlobalAvailabilityTemplate.find_by(title: 'Não deveria')).to be_nil
    end
  end

  # ===================================================================
  describe 'BE-123 / FE-132 — o critério de somente-leitura é o MESMO nos dois lados' do
    it 'a consolidação geral não é editável nem por envio direto ao endpoint' do
      entrada = Availability::EntryService.create(
        project: projeto_a,
        attrs: { availability_template_id: padrao_a.id, company_id: empresa_a.id,
                 date: '2026-08-14', value: 100 }
      ).fetch(:data)
      espelho = AvailabilityEntry.find_by(availability_template_id: padrao_a.id, company_id: nil)

      put "/api/v1/availability_entries/#{espelho.id}", params: { value: 999 },
                                                        headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(espelho.reload.value).to eq(entrada.value)
    end

    it 'nó COM FILHOS não aceita valor digitado, e a grade marca a célula como não editável' do
      filho = create(:project_availability_template, project: projeto_a, parent_template_id: padrao_a.id)
      Availability::EntryService.create(
        project: projeto_a,
        attrs: { availability_template_id: filho.id, company_id: empresa_a.id,
                 date: '2026-08-14', value: 100 }
      )
      pai_entry = AvailabilityEntry.find_by(availability_template_id: padrao_a.id, company_id: empresa_a.id)

      put "/api/v1/availability_entries/#{pai_entry.id}", params: { value: 999 },
                                                          headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)

      get "/api/v1/availability_entries?date=2026-08-14&company_id=#{empresa_a.id}",
          headers: auth_headers(gerente, project: projeto_a)
      linha_pai = json['rows'].find { |r| r['template']['id'] == padrao_a.id }
      expect(linha_pai['editable']).to be(false)
      expect(linha_pai['value_semantics']).to eq('group_total')
    end

    it 'lançar em padrão BLOQUEADO responde 409' do
      padrao_a.lock!('Ativando.', actor: gerente)

      post '/api/v1/availability_entries',
           params: { availability_template_id: padrao_a.id, company_id: empresa_a.id,
                     date: '2026-08-14', value: 1 },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(409)
    end
  end

  # ===================================================================
  describe 'BE-143 / DC-24 — o que não pode mudar na edição é recusado com a RAZÃO' do
    it 'renomear funciona' do
      put "/api/v1/project_availabilities/#{padrao_a.id}", params: { title: 'Caixa renomeada' },
                                                           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(padrao_a.reload.title).to eq('Caixa renomeada')
      # DC-32 — renomear NÃO renumera.
      expect(padrao_a.position).to eq(1)
    end

    it 'padrão bloqueado responde 409 na edição' do
      padrao_a.lock!('Removendo.', actor: gerente)

      put "/api/v1/project_availabilities/#{padrao_a.id}", params: { title: 'X' },
                                                           headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(409)
    end
  end
end
