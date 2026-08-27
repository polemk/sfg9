# frozen_string_literal: true

require 'rails_helper'

# S8 / **BE-300**…**BE-304**, tarefas 12.2, 12.4, 12.5, 12.6 e 12.7.
#
# A remuneração é **preço de cliente**: é a taxa que multiplica todo o
# faturamento do tipo. No legado o `project_id` vinha de um `hidden_field` e não
# era conferido em lugar nenhum (BE-301) — trocar o valor do campo criava a
# remuneração no projeto de outro cliente. É o primeiro exemplo daqui.
RSpec.describe 'API V1 Remunerations', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro) { create(:user, user_type: UserType.gerente) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'rem-a', name: 'Remuneracoes A') }
  let!(:projeto_b) { create_project_with_owner(outro, slug: 'rem-b', name: 'Remuneracoes B') }

  let(:tipo_est) { create(:structured_operation_type, title: 'Fomento EST') }
  let(:tipo_liq) { create(:risk_operation_type, title: 'Fomento LIQ') }

  def headers_a = auth_headers(gerente, project: projeto_a)

  # ====================================================================
  # BE-301 — `project_id` forçado ao projeto corrente
  # ====================================================================
  describe 'POST /api/v1/remunerations' do
    it 'ignora o `project_id` do corpo e grava no projeto corrente (BE-301)' do
      post '/api/v1/remunerations',
           params: { project_id: projeto_b.id, operation_type_type: 'StructuredOperationType',
                     operation_type_id: tipo_est.id, value: '2.55' },
           headers: headers_a, as: :json

      expect(response).to have_http_status(201)
      expect(response.parsed_body['project_id']).to eq(projeto_a.id)
      expect(Remuneration.where(project_id: projeto_b.id)).to be_empty
    end

    it 'BE-304 — `title` é copiado do tipo, e `beauty_type` é a sigla' do
      post '/api/v1/remunerations',
           params: { operation_type_type: 'StructuredOperationType', operation_type_id: tipo_est.id,
                     value: '2.55' },
           headers: headers_a, as: :json

      expect(response.parsed_body['title']).to eq('Fomento EST')
      expect(response.parsed_body['beauty_type']).to eq('EST')
    end

    it 'BE-304 — o outro lado da hierarquia: `RiskOperationType` vira LIQ (C3)' do
      post '/api/v1/remunerations',
           params: { operation_type_type: 'RiskOperationType', operation_type_id: tipo_liq.id,
                     value: '1.75' },
           headers: headers_a, as: :json

      expect(response).to have_http_status(201)
      expect(response.parsed_body['beauty_type']).to eq('LIQ')
      expect(response.parsed_body['title']).to eq('Fomento LIQ')
    end

    it '`operation_type_type` arbitrário responde 422, não 500 nem `"???"`' do
      # No legado a string livre passava, `operation_class` devolvia nil e o
      # `nil.where(...)` seguinte dava 500; `beauty_type` devolvia `"???"`, que
      # ia parar na coluna `kind` do recibo e virava recibo que nenhum filtro
      # achava.
      post '/api/v1/remunerations',
           params: { operation_type_type: 'Qualquer', operation_type_id: tipo_est.id, value: '2.55' },
           headers: headers_a, as: :json

      expect(response).to have_http_status(400)
      expect(Remuneration.count).to eq(0)
    end

    it 'BE-301 — a unicidade (projeto, classe, tipo) é do BANCO, não só do model' do
      create(:remuneration, project: projeto_a, operation_type: tipo_est, value: BigDecimal('2.55'))

      post '/api/v1/remunerations',
           params: { operation_type_type: 'StructuredOperationType', operation_type_id: tipo_est.id,
                     value: '9.99' },
           headers: headers_a, as: :json

      expect(response).to have_http_status(422)
      expect(Remuneration.where(project_id: projeto_a.id, operation_type_id: tipo_est.id).count).to eq(1)
    end

    it 'o MESMO tipo em OUTRO projeto é permitido — a unicidade é por projeto' do
      create(:remuneration, project: projeto_b, operation_type: tipo_est, value: BigDecimal('7.00'))

      post '/api/v1/remunerations',
           params: { operation_type_type: 'StructuredOperationType', operation_type_id: tipo_est.id,
                     value: '2.55' },
           headers: headers_a, as: :json

      expect(response).to have_http_status(201)
    end

    it 'T-D9 — a faixa de `value` NÃO é validada: 250% passa, e continua passando' do
      # Validar a faixa recusaria registro que o sistema aceita hoje. A decisão
      # é do negócio, não da migração (DEC-37). O exemplo existe para que a
      # ausência seja deliberada e visível, não um esquecimento.
      post '/api/v1/remunerations',
           params: { operation_type_type: 'StructuredOperationType', operation_type_id: tipo_est.id,
                     value: '250.0' },
           headers: headers_a, as: :json

      expect(response).to have_http_status(201)
      expect(BigDecimal(response.parsed_body['value'])).to eq(BigDecimal('250.0'))
    end
  end

  # ====================================================================
  # BE-300 — a listagem ganha os três que não tinha
  # ====================================================================
  describe 'GET /api/v1/remunerations' do
    let!(:rem_est) { create(:remuneration, project: projeto_a, operation_type: tipo_est, value: BigDecimal('2.55')) }
    let!(:rem_liq) do
      create(:remuneration, project: projeto_a, operation_type: tipo_liq,
                            operation_type_type: 'RiskOperationType', value: BigDecimal('1.75'))
    end
    let!(:rem_alheia) { create(:remuneration, project: projeto_b, operation_type: tipo_est) }

    it 'lista SÓ as do projeto corrente (C1)' do
      get '/api/v1/remunerations', headers: headers_a

      expect(response.parsed_body.map { |r| r['id'] }).to match_array([rem_est.id, rem_liq.id])
    end

    it 'filtra por classe — no legado LIQ e EST vinham juntas, sem filtro' do
      get '/api/v1/remunerations', params: { operation_type_type: 'StructuredOperationType' },
                                   headers: headers_a

      expect(response.parsed_body.map { |r| r['id'] }).to eq([rem_est.id])
    end

    it 'busca no título — a coluna DESNORMALIZADA (B-06) é o que a busca usa' do
      get '/api/v1/remunerations', params: { q: 'Fomento LIQ' }, headers: headers_a

      expect(response.parsed_body.map { |r| r['id'] }).to eq([rem_liq.id])
    end

    it 'X-Total-Count real e paginação — o legado não tinha nenhum dos dois' do
      get '/api/v1/remunerations', params: { per_page: 1 }, headers: headers_a

      expect(response.parsed_body.size).to eq(1)
      expect(response.headers['X-Total-Count']).to eq('2')
    end

    it 'chave de ordenação desconhecida responde 400' do
      get '/api/v1/remunerations', params: { ordering_keys: ['sql'] }, headers: headers_a
      expect(response).to have_http_status(400)
    end

    it 'GET /:id de remuneração de OUTRO projeto responde 404 (BE-302)' do
      get "/api/v1/remunerations/#{rem_alheia.id}", headers: headers_a
      expect(response).to have_http_status(404)
    end
  end

  # ====================================================================
  # BE-302 — edição, e o que ela NÃO faz
  # ====================================================================
  describe 'PUT /api/v1/remunerations/:id' do
    let!(:rem) { create(:remuneration, project: projeto_a, operation_type: tipo_est, value: BigDecimal('2.55')) }

    it 'edita a taxa dentro do escopo' do
      put "/api/v1/remunerations/#{rem.id}", params: { value: '3.10' }, headers: headers_a, as: :json

      expect(response).to have_http_status(200)
      expect(BigDecimal(response.parsed_body['value'])).to eq(BigDecimal('3.10'))
    end

    it 'PUT em remuneração de OUTRO projeto responde 404 (BE-302)' do
      alheia = create(:remuneration, project: projeto_b, operation_type: tipo_est, value: BigDecimal('9.99'))

      put "/api/v1/remunerations/#{alheia.id}", params: { value: '0.01' }, headers: headers_a, as: :json

      expect(response).to have_http_status(404)
      expect(alheia.reload.value).to eq(BigDecimal('9.99'))
    end

    it 'trocar o tipo recalcula o `title` — e NÃO mexe em recibo já emitido' do
      # O recibo congela `fee`/`title`/`kind` na emissão, então o histórico fica
      # correto sozinho. Recalcular seria reescrever o que já foi cobrado.
      cobranca = create(:charge, project: projeto_a)
      recibo = Receipt.create!(project: projeto_a, charge: cobranca, remuneration: rem,
                               kind: Receipt::KIND_STRUCTURED, title: 'Fomento EST',
                               fee: BigDecimal('2.55'), operation_value: BigDecimal('100000.00'),
                               value: BigDecimal('2550.00'), user_id: gerente.id)

      outro_tipo = create(:structured_operation_type, title: 'Comissária EST')
      put "/api/v1/remunerations/#{rem.id}", params: { operation_type_id: outro_tipo.id, value: '9.00' },
                                             headers: headers_a, as: :json

      expect(response.parsed_body['title']).to eq('Comissária EST')
      expect(recibo.reload.title).to eq('Fomento EST')
      expect(recibo.fee).to eq(BigDecimal('2.55'))
      expect(recibo.value).to eq(BigDecimal('2550.00'))
    end
  end

  # ====================================================================
  # BE-303 — exclusão bloqueada por recibo
  # ====================================================================
  describe 'DELETE /api/v1/remunerations/:id' do
    let!(:rem) { create(:remuneration, project: projeto_a, operation_type: tipo_est, value: BigDecimal('2.55')) }

    it 'exclui a remuneração sem recibos' do
      delete "/api/v1/remunerations/#{rem.id}", headers: headers_a

      expect(response).to have_http_status(200)
      expect(Remuneration.exists?(rem.id)).to be(false)
    end

    it 'com recibos emitidos responde 422 — o recibo órfão do legado deixa de existir' do
      # No legado `has_many :receipts` estava **sem `dependent:`**: apagar a
      # remuneração deixava recibo órfão, e como `Receipt belongs_to
      # :remuneration` é obrigatório, qualquer save posterior daquele recibo
      # falhava — silenciosamente, meses depois.
      cobranca = create(:charge, project: projeto_a)
      Receipt.create!(project: projeto_a, charge: cobranca, remuneration: rem,
                      kind: Receipt::KIND_STRUCTURED, title: 'Fomento EST', fee: BigDecimal('2.55'),
                      operation_value: BigDecimal('100000.00'), value: BigDecimal('2550.00'),
                      user_id: gerente.id)

      delete "/api/v1/remunerations/#{rem.id}", headers: headers_a

      expect(response).to have_http_status(422)
      expect(response.parsed_body['message']).to be_present
      expect(Remuneration.exists?(rem.id)).to be(true)
    end
  end

  # ====================================================================
  # Q-R21 — o select do painel lateral
  # ====================================================================
  describe 'GET /api/v1/remunerations/operation_types' do
    it 'oferece só os ATIVOS para uma remuneração nova' do
      ativo = create(:structured_operation_type, title: 'Ativo')
      create(:structured_operation_type, :inativo, title: 'Inativo')

      get '/api/v1/remunerations/operation_types',
          params: { operation_type_type: 'StructuredOperationType' }, headers: headers_a

      titulos = response.parsed_body.map { |t| t['title'] }
      expect(titulos).to include(ativo.title)
      expect(titulos).not_to include('Inativo')
    end

    it 'na EDIÇÃO inclui o tipo já escolhido, mesmo desativado (Q-R21)' do
      # Sem isto o select da edição sobe vazio, o campo `disabled` some do
      # submit e a remuneração perde o tipo ao salvar — que é o defeito exato
      # dos dois selects sobrepostos do legado.
      inativo = create(:structured_operation_type, :inativo, title: 'Descontinuado')

      get '/api/v1/remunerations/operation_types',
          params: { operation_type_type: 'StructuredOperationType', include_id: inativo.id },
          headers: headers_a

      expect(response.parsed_body.map { |t| t['title'] }).to include('Descontinuado')
    end
  end

  # ====================================================================
  # FE-309 — autenticação
  # ====================================================================
  describe 'autenticação (FE-309)' do
    it 'nenhum verbo responde sem JWT válido' do
      get '/api/v1/remunerations'
      expect(response).to have_http_status(401)

      post '/api/v1/remunerations', params: {}, as: :json
      expect(response).to have_http_status(401)

      put "/api/v1/remunerations/#{SecureRandom.uuid}", params: {}, as: :json
      expect(response).to have_http_status(401)

      delete "/api/v1/remunerations/#{SecureRandom.uuid}"
      expect(response).to have_http_status(401)
    end
  end
end
