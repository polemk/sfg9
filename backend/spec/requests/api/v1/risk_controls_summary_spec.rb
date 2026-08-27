# frozen_string_literal: true

require 'rails_helper'

# S5 / BE-231 — **o console "Controle de Risco"**, pela borda HTTP.
#
# É o painel principal do produto: a tela que o cliente abre para saber quanto
# de cada limite está utilizado, disponível, liquidável e em pré-faturamento
# numa data.
RSpec.describe 'API V1 Risk controls summary', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro_gerente) { create(:user, user_type: UserType.gerente) }

  let!(:projeto) { create_project_with_owner(gerente, slug: 'sum-a', name: 'Resumo A') }
  let!(:outro_projeto) { create_project_with_owner(outro_gerente, slug: 'sum-b', name: 'Resumo B') }

  let(:empresa) { create(:company, project: projeto, title: 'Empresa Resumo') }
  let(:outra_empresa) { create(:company, project: projeto, title: 'Empresa Vizinha') }
  let(:portador) { create(:carrier, title: 'Banco Resumo') }
  let(:tipo) { create(:risk_operation_type, title: 'Fomento Resumo') }

  let!(:limite) do
    create(:risk_control, project: projeto, company: empresa, carrier: portador,
                          risk_operation_type: tipo, limite: 400_000, taxa: 2.00)
  end

  def headers = auth_headers(gerente, project: projeto)

  describe 'GET /api/v1/risk_controls/summary' do
    it 'without company_id aggregates the WHOLE project ("Grupo econômico")' do
      get '/api/v1/risk_controls/summary', headers: headers

      expect(response).to have_http_status(200)
      corpo = JSON.parse(response.body)
      expect(corpo['scope']).to eq('project')
      expect(corpo['company_id']).to be_nil
      expect(corpo['is_single']).to be(false)
    end

    it 'with company_id aggregates the COMPANY' do
      get '/api/v1/risk_controls/summary', params: { company_id: empresa.id }, headers: headers

      corpo = JSON.parse(response.body)
      expect(corpo['scope']).to eq('company')
      expect(corpo['company_id']).to eq(empresa.id)
    end

    it 'flips is_single when a carrier is given' do
      ProjectToCarrierConnection.find_or_create_by!(project: projeto, carrier: portador)
      get '/api/v1/risk_controls/summary', params: { carrier_id: portador.id }, headers: headers

      corpo = JSON.parse(response.body)
      expect(corpo['is_single']).to be(true)
      expect(corpo['carrier_title']).to eq('Banco Resumo')
    end

    it 'answers 404 for a carrier that does not exist — the legacy Carrier.find gave 500' do
      get '/api/v1/risk_controls/summary', params: { carrier_id: SecureRandom.uuid }, headers: headers
      expect(response).to have_http_status(404)
    end

    it 'answers 404 for a carrier that is not connected to this project (C1)' do
      solto = create(:carrier, title: 'Solto')
      get '/api/v1/risk_controls/summary', params: { carrier_id: solto.id }, headers: headers
      expect(response).to have_http_status(404)
    end

    it 'answers 404 for a company of ANOTHER project (C1)' do
      alheia = create(:company, project: outro_projeto, title: 'Alheia')
      get '/api/v1/risk_controls/summary', params: { company_id: alheia.id }, headers: headers
      expect(response).to have_http_status(404)
    end

    it 'answers 400 for a malformed date — validated by Grape, not by a rescue' do
      get '/api/v1/risk_controls/summary', params: { date: '31/02/naodata' }, headers: headers
      expect(response).to have_http_status(400)
    end

    it 'defaults the date to today' do
      get '/api/v1/risk_controls/summary', headers: headers
      expect(JSON.parse(response.body)['date']).to eq(Date.current.to_s)
    end

    it 'carries the type header with the aggregate numbers and the formatted strings' do
      get '/api/v1/risk_controls/summary', params: { company_id: empresa.id }, headers: headers

      cabecalho = JSON.parse(response.body)['controls_info'].find { |i| i['id'] == tipo.id }
      expect(cabecalho['title']).to eq('Fomento Resumo')
      expect(cabecalho['total']).to eq('400000.0')
      expect(cabecalho['formatted_total']).to eq('400.000,00')
      expect(cabecalho['rcs'].map { |r| r['id'] }).to eq([limite.id])
    end

    it 'carries total_limits with the four identical keys (BE-251)' do
      get '/api/v1/risk_controls/summary', params: { company_id: empresa.id }, headers: headers

      linha = JSON.parse(response.body)['total_limits']['limits'].find { |l| l['id'] == tipo.id }
      expect(linha['liq']).to eq(linha['perc_util'])
      expect(linha['perc_liq']).to eq(linha['perc_util'])
      expect(linha['pre']).to eq(linha['perc_util'])
      expect(linha['perc_pre']).to eq(linha['perc_util'])
    end

    it 'requires a session' do
      get '/api/v1/risk_controls/summary'
      expect(response).to have_http_status(401)
    end

    it 'answers 404 for a user with no membership — same status as a nonexistent project' do
      estranho = create(:user, user_type: UserType.colaborador)
      get '/api/v1/risk_controls/summary', headers: auth_headers(estranho, project: projeto)
      expect(response).to have_http_status(404)
    end
  end

  describe 'GET /api/v1/companies/risk_summary/list (BE-052 / BE-251)' do
    it 'now returns real numbers instead of the S5 placeholder' do
      get '/api/v1/companies/risk_summary/list', params: { company_id: empresa.id }, headers: headers

      expect(response).to have_http_status(200)
      corpo = JSON.parse(response.body)
      expect(corpo).not_to have_key('pending_slice')
      linha = corpo['limits'].find { |l| l['id'] == tipo.id }
      expect(linha['total']).to eq('400000.0')
    end

    it 'is the SAME service the risk console calls (contract C2)' do
      get '/api/v1/companies/risk_summary/list', params: { company_id: empresa.id }, headers: headers
      pela_empresa = JSON.parse(response.body)

      get '/api/v1/risk_controls/summary', params: { company_id: empresa.id }, headers: headers
      pelo_console = JSON.parse(response.body)['total_limits']

      expect(pela_empresa['limits']).to eq(pelo_console['limits'])
    end
  end
end
