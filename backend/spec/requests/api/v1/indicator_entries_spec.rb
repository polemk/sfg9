# frozen_string_literal: true

require 'rails_helper'

# S10 / 10.7, 10.8, 10.9 — a grade mensal e as conexões pela API.
#
# É aqui que o contrato **C1** desta fatia é verificado nos dois sentidos:
# lançamento e conexão são **escopados por projeto**; o catálogo global
# (`indicators_spec.rb`) é **sem escopo**. As duas regras convivem por desenho.
RSpec.describe 'API V1 Indicator entries e connections', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro_gerente) { create(:user, user_type: UserType.gerente) }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'ent-a', name: 'Lancamentos A') }
  let!(:projeto_b) { create_project_with_owner(outro_gerente, slug: 'ent-b', name: 'Lancamentos B') }

  let!(:margem) { create(:indicator, title: 'MARGEM') }
  let!(:atraso) { create(:indicator, title: 'ATRASO') }

  before do
    create(:project_indicator_connection, project: projeto_a, indicator: margem)
    create(:project_indicator_connection, project: projeto_a, indicator: atraso)
    Membership.create!(project: projeto_a, user: colaborador, role: 'participante')
  end

  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/indicator_entries/grid' do
    before do
      create(:indicator_entry, project: projeto_a, indicator: margem, year: 2024, month: 3, value: 0)
      create(:indicator_entry, project: projeto_a, indicator: margem, year: 2024, month: 4, value: 1_000)
    end

    it 'devolve uma linha por indicador com 12 células, em ordem alfabética' do
      get '/api/v1/indicator_entries/grid', params: { year: 2024 },
                                            headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      corpo = JSON.parse(response.body)
      expect(corpo.map { |l| l['indicator']['title'] }).to eq(%w[ATRASO MARGEM])
      expect(corpo.first['cells'].size).to eq(12)
    end

    # **DEC-70.** É a mudança mais visível desta fatia.
    it 'NÃO LANÇADO vem como `entry: null`; LANÇADO COMO ZERO vem com valor' do
      get '/api/v1/indicator_entries/grid', params: { year: 2024 },
                                            headers: auth_headers(gerente, project: projeto_a)

      linha = JSON.parse(response.body).find { |l| l['indicator']['title'] == 'MARGEM' }
      marco = linha['cells'].find { |c| c['month'] == 3 }
      maio = linha['cells'].find { |c| c['month'] == 5 }

      expect(marco['entry']).to be_present
      expect(marco['entry']['value']).to eq('0.0')
      expect(maio['entry']).to be_nil
    end

    it 'exige projeto corrente — sem participação é 404 (C1)' do
      get '/api/v1/indicator_entries/grid', headers: auth_headers(gerente, project: projeto_b)

      expect(response).to have_http_status(404)
      expect(JSON.parse(response.body)['code']).to eq('PROJECT_NOT_FOUND')
    end

    it 'nunca traz lançamento de outro projeto' do
      create(:project_indicator_connection, project: projeto_b, indicator: margem)
      create(:indicator_entry, project: projeto_b, indicator: margem, year: 2024, month: 5, value: 999)

      get '/api/v1/indicator_entries/grid', params: { year: 2024 },
                                            headers: auth_headers(gerente, project: projeto_a)

      linha = JSON.parse(response.body).find { |l| l['indicator']['title'] == 'MARGEM' }
      expect(linha['cells'].find { |c| c['month'] == 5 }['entry']).to be_nil
    end

    it 'o COLABORADOR participante lê a grade (a matriz dá CRUD ao grupo Gestão)' do
      get '/api/v1/indicator_entries/grid', headers: auth_headers(colaborador, project: projeto_a)
      expect(response).to have_http_status(200)
    end
  end

  # ---------------------------------------------------------------------------
  describe 'PUT /api/v1/indicator_entries — o autosave da célula' do
    it 'grava e devolve 201, com o autor vindo da SESSÃO' do
      put '/api/v1/indicator_entries',
          params: { indicator_id: margem.id, year: 2024, month: 6, value: '1234.56' },
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      corpo = JSON.parse(response.body)
      expect(corpo['value']).to eq('1234.56')
      expect(corpo['created_by']).to eq(gerente.id)
    end

    # **BE-326.** No legado `user_id` vinha de um campo escondido do formulário
    # e estava no `permit`: dava para lançar em nome de outro usuário.
    it 'o `user_id` do PAYLOAD é ignorado — o autor é sempre a sessão' do
      put '/api/v1/indicator_entries',
          params: { indicator_id: margem.id, year: 2024, month: 6, value: '10', user_id: outro_gerente.id },
          headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body)['created_by']).to eq(gerente.id)
    end

    it 'a SEGUNDA gravação da mesma célula atualiza (200), não falha com "já está em uso"' do
      put '/api/v1/indicator_entries', params: { indicator_id: margem.id, year: 2024, month: 6, value: '1' },
                                       headers: auth_headers(gerente, project: projeto_a)
      put '/api/v1/indicator_entries', params: { indicator_id: margem.id, year: 2024, month: 6, value: '2' },
                                       headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)['value']).to eq('2.0')
    end

    it 'aceita NEGATIVO' do
      put '/api/v1/indicator_entries', params: { indicator_id: margem.id, year: 2024, month: 7, value: '-99.9' },
                                       headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body)['value']).to eq('-99.9')
    end

    it 'mês fora da faixa é 400 na validação do endpoint, nunca 500' do
      put '/api/v1/indicator_entries', params: { indicator_id: margem.id, year: 2024, month: 13, value: '1' },
                                       headers: auth_headers(gerente, project: projeto_a)

      expect(response.status).to be_between(400, 422)
      expect(response.status).not_to eq(500)
    end

    it 'indicador não conectado a este projeto é 404' do
      solto = create(:indicator, title: 'SOLTO')

      put '/api/v1/indicator_entries', params: { indicator_id: solto.id, year: 2024, month: 1, value: '1' },
                                       headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end

    # **FE-718 / BE-717.** No legado o readonly só desabilitava o campo no HTML:
    # o POST direto passava.
    it 'usuário READONLY é BLOQUEADO no servidor, não só na tela' do
      UserPermission.create!(user: colaborador, permission: Permission.find_by(key: 'user_is_readonly'),
                             source: 'manual', granted_at: Time.current)

      put '/api/v1/indicator_entries', params: { indicator_id: margem.id, year: 2024, month: 8, value: '1' },
                                       headers: auth_headers(colaborador, project: projeto_a)

      expect(response).to have_http_status(403)
      expect(JSON.parse(response.body)['code']).to eq('READONLY_RESTRICTED')
    end
  end

  # ---------------------------------------------------------------------------
  describe 'DELETE /api/v1/indicator_entries/:id — endpoint SEM tela (DEC-71)' do
    it 'apaga e a célula volta a "não lançado"' do
      entrada = create(:indicator_entry, project: projeto_a, indicator: margem, year: 2024, month: 9, value: 5)

      delete "/api/v1/indicator_entries/#{entrada.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)

      get '/api/v1/indicator_entries/grid', params: { year: 2024, month: 9 },
                                            headers: auth_headers(gerente, project: projeto_a)
      linha = JSON.parse(response.body).find { |l| l['indicator']['title'] == 'MARGEM' }
      expect(linha['cells'].first['entry']).to be_nil
    end

    # Condição 1 do DEC-53: endpoint sem tela continua alcançável por URL e
    # precisa de autorização e escopo como qualquer outro.
    it 'lançamento de OUTRO projeto é 404, mesmo sem tela que o chame' do
      alheio = create(:indicator_entry, project: projeto_b, indicator: margem, year: 2024, month: 9)

      delete "/api/v1/indicator_entries/#{alheio.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end
  end

  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/indicator_connections' do
    let!(:meu_especifico) { create(:indicator, :specific, title: 'MEU', project: projeto_a) }
    let!(:alheio) { create(:indicator, :specific, title: 'ALHEIO', project: projeto_b) }

    it 'lista globais + específicos DESTE projeto, com a marca de conectado' do
      get '/api/v1/indicator_connections', headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      corpo = JSON.parse(response.body)
      expect(corpo.map { |i| i['title'] }).to contain_exactly('ATRASO', 'MARGEM', 'MEU')
      expect(corpo.find { |i| i['title'] == 'MARGEM' }['connected']).to be(true)
      expect(corpo.find { |i| i['title'] == 'MEU' }['connected']).to be(false)
    end

    it 'NUNCA lista o específico de outro projeto (C1)' do
      get '/api/v1/indicator_connections', headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).map { |i| i['id'] }).not_to include(alheio.id)
    end

    it 'a busca filtra de verdade — no legado `q` era ignorado' do
      get '/api/v1/indicator_connections', params: { q: 'meu' },
                                           headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).map { |i| i['title'] }).to eq(['MEU'])
    end
  end

  describe 'POST /api/v1/indicator_connections/connect e /disconnect' do
    let!(:novo) { create(:indicator, title: 'NOVO GLOBAL') }

    it 'conecta e o indicador passa a aparecer na grade' do
      post '/api/v1/indicator_connections/connect', params: { indicator_ids: [novo.id] },
                                                    headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      get '/api/v1/indicator_entries/grid', headers: auth_headers(gerente, project: projeto_a)
      expect(JSON.parse(response.body).map { |l| l['indicator']['title'] }).to include('NOVO GLOBAL')
    end

    it 'desconectar não apaga lançamento, e reconectar traz o histórico (Q-R31)' do
      create(:indicator_entry, project: projeto_a, indicator: margem, year: 2024, month: 2, value: 42)

      post '/api/v1/indicator_connections/disconnect', params: { indicator_ids: [margem.id] },
                                                       headers: auth_headers(gerente, project: projeto_a)
      expect(IndicatorEntry.where(project: projeto_a, indicator: margem).count).to eq(1)

      post '/api/v1/indicator_connections/connect', params: { indicator_ids: [margem.id] },
                                                    headers: auth_headers(gerente, project: projeto_a)

      get '/api/v1/indicator_entries/grid', params: { year: 2024 },
                                            headers: auth_headers(gerente, project: projeto_a)
      linha = JSON.parse(response.body).find { |l| l['indicator']['title'] == 'MARGEM' }
      expect(linha['cells'].find { |c| c['month'] == 2 }['entry']['value']).to eq('42.0')
    end

    it 'conectar indicador de outro projeto REPROVA o lote e não grava nada (BE-709)' do
      alheio = create(:indicator, :specific, title: 'ALHEIO', project: projeto_b)

      post '/api/v1/indicator_connections/connect', params: { indicator_ids: [novo.id, alheio.id] },
                                                    headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(ProjectIndicatorConnection.where(project: projeto_a, indicator: novo).count).to eq(0)
    end
  end

  describe 'DELETE /api/v1/indicator_connections/:indicator_id — BE-711' do
    it 'exclui o específico e PRESERVA os lançamentos (o D-66 na tela que nem confirmação tinha)' do
      especifico = create(:indicator, :specific, title: 'MEU', project: projeto_a)
      create(:project_indicator_connection, project: projeto_a, indicator: especifico)
      create(:indicator_entry, project: projeto_a, indicator: especifico, month: 1, value: 8)

      delete "/api/v1/indicator_connections/#{especifico.id}",
             headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(especifico.reload.discarded_at).to be_present
      expect(IndicatorEntry.where(indicator: especifico).count).to eq(1)
    end

    it 'indicador GLOBAL é 422 com a frase — no legado era `NoMethodError`' do
      delete "/api/v1/indicator_connections/#{margem.id}", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['message']).to match(/globais com associação/)
    end
  end
end
