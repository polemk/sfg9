# frozen_string_literal: true

require 'rails_helper'

# S9 — **renegociações**: listagem, filtros, ordenação, paginação e CRUD.
#
# Cobre as tarefas 4.17 (exclusão honesta) e 4.19 (paginação e ordenação reais).
RSpec.describe 'API::V1::Renegotiations' do
  let(:user) { create(:user, :og) }
  let(:project) { create_project_with_owner(user) }
  let(:provider) { create(:provider, project: project, title: 'Aço Norte') }
  let(:company) { create(:company, project: project) }
  let(:headers) { auth_headers(user, project: project) }

  def criar_renegociacao(**attrs)
    create(:renegotiation, { project: project, provider: provider, company: company }.merge(attrs))
  end

  describe 'GET /api/v1/renegotiations' do
    it 'lista apenas as do projeto corrente' do
      minha = criar_renegociacao(title: 'Acordo A')
      outra_project = create(:project)
      create(:renegotiation, project: outra_project,
                             provider: create(:provider, project: outra_project),
                             company: create(:company, project: outra_project))

      get '/api/v1/renegotiations', headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).map { |r| r['id'] }).to eq([minha.id])
    end

    it 'busca por NOME da renegociação e por nome do fornecedor (BE-190)' do
      # No legado a primeira coluna da lista era "Nome" (`title`) e o `where` só
      # olhava `provider_name`: buscar pelo que estava escrito na tela não achava
      # nada.
      pelo_nome = criar_renegociacao(title: 'Acordo Especial')
      pelo_fornecedor = criar_renegociacao(title: 'Outro acordo')

      get '/api/v1/renegotiations', params: { q: 'Especial' }, headers: headers
      expect(JSON.parse(response.body).map { |r| r['id'] }).to eq([pelo_nome.id])

      get '/api/v1/renegotiations', params: { q: 'Aço' }, headers: headers
      expect(JSON.parse(response.body).map { |r| r['id'] }).to match_array([pelo_nome.id, pelo_fornecedor.id])
    end

    it 'filtra por estado, inclusive "empty" — que no legado dava 500 (D-49)' do
      vazia = criar_renegociacao(title: 'Sem parcela')
      Renegotiations::AggregateService.recalculate!(vazia, broadcast: false)
      com_parcela = criar_renegociacao(title: 'Com parcela')
      create(:renegotiation_installment, renegotiation: com_parcela, due_date: Date.new(2025, 6, 1))
      Renegotiations::AggregateService.recalculate!(com_parcela, broadcast: false)

      get '/api/v1/renegotiations', params: { state: 'empty' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).map { |r| r['id'] }).to eq([vazia.id])
    end

    it 'filtra por tipo' do
      financeiro = criar_renegociacao(kind: 'Financeiro')
      criar_renegociacao(kind: 'Trabalhista')

      get '/api/v1/renegotiations', params: { kind: 'Financeiro' }, headers: headers
      expect(JSON.parse(response.body).map { |r| r['id'] }).to eq([financeiro.id])
    end

    it 'recusa tipo e estado fora do domínio, em vez de abortar a action' do
      get '/api/v1/renegotiations', params: { state: 'inexistente' }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it 'ordena pelas chaves conhecidas e IGNORA a desconhecida (BE-193)' do
      a = criar_renegociacao(title: 'AAA')
      z = criar_renegociacao(title: 'ZZZ')

      get '/api/v1/renegotiations',
          params: { 'ordering_keys[]' => ['title'], 'ordering_style[]' => ['down'] }, headers: headers
      expect(JSON.parse(response.body).map { |r| r['id'] }).to eq([z.id, a.id])

      # No legado `get_ordering_key` devolvia `nil` para chave fora do `case`, e a
      # linha seguinte fazia `nil + " "` → NoMethodError → 500. Bastava digitar na
      # barra de endereço.
      get '/api/v1/renegotiations',
          params: { 'ordering_keys[]' => ['coluna_inventada'], 'ordering_style[]' => ['up'] }, headers: headers
      expect(response).to have_http_status(:ok)
    end

    it 'pagina de verdade e emite o envelope em cabeçalho (D-20 / DEC-62)' do
      3.times { |i| criar_renegociacao(title: "Acordo #{i}") }

      get '/api/v1/renegotiations', params: { page: 1, per_page: 2 }, headers: headers

      expect(JSON.parse(response.body).size).to eq(2)
      expect(response.headers['X-Total-Count']).to eq('3')
      expect(response.headers['X-Total-Pages']).to eq('2')

      get '/api/v1/renegotiations', params: { page: 2, per_page: 2 }, headers: headers
      expect(JSON.parse(response.body).size).to eq(1)
    end

    it 'serve overdue_installments APURADO NA CONSULTA, não a coluna do cron (OPS-190)' do
      renegociacao = criar_renegociacao
      create(:renegotiation_installment, renegotiation: renegociacao, due_date: 5.days.ago.to_date)
      # A coluna é deixada MENTINDO de propósito: é o estado em que o cron diário
      # do legado deixava o registro entre uma execução e a outra.
      renegociacao.update_column(:overdue_installments, 0)

      get '/api/v1/renegotiations', headers: headers

      expect(JSON.parse(response.body).first['overdue_installments']).to eq(1)
    end
  end

  describe 'GET /api/v1/renegotiations/:id/general_values' do
    it 'RECALCULA e devolve os sete valores (BE-195, corrige D-48)' do
      renegociacao = criar_renegociacao(total_debt: 3000)
      create(:renegotiation_installment, renegotiation: renegociacao,
                                         due_date: Date.new(2025, 3, 1), main_value: 1000)
      # A coluna fica desatualizada; o endpoint tem de recalcular antes de responder.
      renegociacao.update_column(:installments_main_value, 0)

      get "/api/v1/renegotiations/#{renegociacao.id}/general_values", headers: headers

      corpo = JSON.parse(response.body)
      expect(corpo['installments_value'].to_d).to eq(1000)
      expect(corpo['unposted_value'].to_d).to eq(2000)
      expect(corpo['installment_status']).to eq('Inconsistente')
      expect(corpo['show_remove_all_option']).to be(true)
    end

    it '404 para renegociação inexistente' do
      get "/api/v1/renegotiations/#{SecureRandom.uuid}/general_values", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/renegotiations' do
    it 'cria já com os agregados calculados e o estado certo (BE-198)' do
      post '/api/v1/renegotiations',
           params: { provider_id: provider.id, company_id: company.id, kind: 'Financeiro',
                     renegotiation_date: '2025-01-10', operation_interest_rate: 0.0,
                     original_value: 3500, total_debt: 3000, desagio_value: 500 },
           headers: headers

      expect(response).to have_http_status(:created)
      corpo = JSON.parse(response.body)
      # No legado o registro nascia com tudo zerado e "Inconsistente".
      expect(corpo['state']).to eq('Sem parcela cadastrada')
      expect(corpo['title']).to eq('Aço Norte')
      expect(corpo['provider_name']).to eq('Aço Norte')
      expect(corpo['correct_value'].to_d).to eq(3000)
      expect(corpo['total_value_with_desagio'].to_d).to eq(3000)
    end

    it 'IGNORA agregado enviado no corpo — não é campo gravável' do
      post '/api/v1/renegotiations',
           params: { provider_id: provider.id, company_id: company.id, kind: 'Financeiro',
                     renegotiation_date: '2025-01-10', operation_interest_rate: 0.0,
                     total_debt: 1000, paid_value: 999_999, state: 'Liquidado' },
           headers: headers

      expect(response).to have_http_status(:created)
      corpo = JSON.parse(response.body)
      # O `permit` do legado aceitava as ~40 colunas, agregados inclusive.
      expect(corpo['paid_value'].to_d).to eq(0)
      expect(corpo['state']).to eq('Sem parcela cadastrada')
    end

    it 'recusa fornecedor de OUTRO projeto' do
      alheio = create(:provider, project: create(:project))

      post '/api/v1/renegotiations',
           params: { provider_id: alheio.id, company_id: company.id, kind: 'Financeiro',
                     renegotiation_date: '2025-01-10', operation_interest_rate: 0.0 },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('não pertence a este projeto')
    end

    it 'recusa chave de integração repetida NO MESMO projeto' do
      criar_renegociacao(integration_key: 'aco_norte')

      post '/api/v1/renegotiations',
           params: { provider_id: provider.id, company_id: company.id, kind: 'Financeiro',
                     renegotiation_date: '2025-01-10', operation_interest_rate: 0.0 },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('já está em uso neste projeto')
    end
  end

  describe 'PUT /api/v1/renegotiations/:id' do
    it 'edição INVÁLIDA não muta agregado (BE-200)' do
      renegociacao = criar_renegociacao(total_debt: 3000)
      create(:renegotiation_installment, renegotiation: renegociacao, due_date: Date.new(2025, 3, 1))
      Renegotiations::AggregateService.recalculate!(renegociacao, broadcast: false)
      antes = renegociacao.reload.attributes.slice('main_value', 'remaining_value', 'state')

      put "/api/v1/renegotiations/#{renegociacao.id}",
          params: { provider_id: create(:provider, project: create(:project)).id }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      # No legado o controller chamava `update` e, na linha seguinte,
      # `update_values!` — mesmo com o `update` tendo falhado.
      expect(renegociacao.reload.attributes.slice('main_value', 'remaining_value', 'state')).to eq(antes)
    end
  end

  describe 'DELETE /api/v1/renegotiations/:id' do
    it 'com parcela: responde ERRO com o motivo e o registro CONTINUA (4.17 / D-24)' do
      renegociacao = criar_renegociacao
      create(:renegotiation_installment, renegotiation: renegociacao, due_date: Date.new(2025, 3, 1))

      delete "/api/v1/renegotiations/#{renegociacao.id}", headers: headers

      # O legado respondia `errors.any? ? :ok : :ok` com template VAZIO: a tela
      # dizia "removido com sucesso", a lista recarregava e o registro voltava.
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)['message']).to include('parcela')
      expect(::Renegotiation.exists?(renegociacao.id)).to be(true)
    end

    it 'sem parcela: remove, e os ANEXOS vão junto (BE-201)' do
      renegociacao = criar_renegociacao
      create(:renegotiation_attachment, renegotiation: renegociacao, author: user)
      anexo_id = renegociacao.attachments.reload.first.id

      delete "/api/v1/renegotiations/#{renegociacao.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(::Renegotiation.exists?(renegociacao.id)).to be(false)
      expect(RenegotiationAttachment.exists?(anexo_id)).to be(false)
    end
  end

  describe 'trilha de auditoria (DEC-59)' do
    it 'versiona a renegociação com payload completo' do
      renegociacao = nil
      expect do
        renegociacao = criar_renegociacao
      end.to change(PaperTrail::Version.where(item_type: 'Renegotiation'), :count).by_at_least(1)

      expect(renegociacao.versions.last.event).to eq('create')
    end
  end
end
