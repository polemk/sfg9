# frozen_string_literal: true

require 'rails_helper'

# S6 / `BE-187`, `BE-188`, `BE-189` — **cobranças e recibos**.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `20220707164909_create_charges` e `20220802225011_create_receipts` estão entre
# as **24 migrations que nunca subiram**. Conferido no dump de **31/05/2025**:
# não há `COPY public.charges` nem `COPY public.receipts`, e `remunerations`
# também não existe. Em três anos de produção, **nenhuma cobrança foi emitida**.
#
# O que isso muda para este arquivo, e é a diferença que importa: aqui o golden
# **não tem oráculo**. Nos recebíveis o oráculo são 28.131 linhas gravadas pelo
# legado ao longo de três anos; aqui o oráculo é a **leitura do código de 2022**
# — `../sfg/app/models/charge.rb` e
# `../sfg/app/controllers/pub/charges_controller.rb`. O teste trava essa
# leitura, não um comportamento observado. Por isso **cada exemplo que replica
# regra cita arquivo e linha do legado**: quem discordar da regra tem onde
# conferir de onde ela veio, em vez de discutir com um número sem procedência.
#
# Onde o ai9 diverge de propósito, a divergência está nomeada no exemplo com o
# defeito que a motivou (D-18, D-20, C1, FE-180).
RSpec.describe 'API V1 Charges', type: :request do
  let(:og) { create(:user, :og) }
  let(:project) { create_project_with_owner(og) }
  let(:outro_projeto) { create_project_with_owner(create(:user, :og)) }
  let(:headers) { auth_headers(og, project: project) }

  # Um recibo criado DIRETO, sem passar pelo `Charges::ReceiptGenerator`.
  #
  # É deliberado: o gerador depende de `Remuneration`, tabela da **S8** que não
  # existe neste ambiente. Sem este atalho, nada do que depende de recibo
  # (bloqueio de exclusão, extrato, `recalculate!`) seria testável hoje — e
  # justamente essas três são as regras que a S8 vai herdar prontas.
  def criar_recibo(charge, kind:, value:, operation_value:, fee: '2.0', title: 'Remuneração')
    Receipt.create!(
      project_id: charge.project_id, charge_id: charge.id, user_id: og.id,
      kind: kind, title: title, fee: BigDecimal(fee),
      operation_value: BigDecimal(operation_value), value: BigDecimal(value)
    )
  end

  # ====================================================================
  # C1 — escopo por projeto (família D-01/D-16/D-29/D-76/D-100)
  # ====================================================================
  describe 'C1 — escopo por projeto' do
    # `../sfg/app/controllers/pub/charges_controller.rb:136-138`: o
    # `fetch_charge` do legado é `Charge.find(params[:id] || params[:charge_id])`
    # — **sem nenhum filtro de projeto**, e ele é o `before_action` de `edit`,
    # `update`, `destroy`, `search_receipts` e `bulk_update_receipts`. Só o
    # `search` (`:11`) escopava. Ou seja: a listagem respeitava o tenant e
    # **todas as cinco ações que alteram, não**.
    let!(:minha) { create(:charge, project: project, author: og, date: Date.new(2025, 3, 10)) }
    let!(:alheia) { create(:charge, project: outro_projeto, date: Date.new(2025, 3, 11)) }

    it 'a lista NÃO traz cobrança de outro projeto' do
      get '/api/v1/charges', headers: headers
      expect(response.parsed_body.map { |c| c['id'] }).to eq([minha.id])
    end

    it '`charge_id` de outro projeto devolve VAZIO — nunca a lista inteira' do
      get '/api/v1/charges', params: { charge_id: alheia.id }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it '`charge_id` malformado devolve VAZIO, não 500' do
      get '/api/v1/charges', params: { charge_id: 'nao-e-uuid' }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it 'GET de id alheio responde EXATAMENTE como id inexistente' do
      # Distinguir 403 de 404 transformaria o endpoint num oráculo de
      # existência de ids: bastaria varrer UUIDs para mapear as cobranças dos
      # outros tenants pela diferença de status.
      get "/api/v1/charges/#{alheia.id}", headers: headers
      status_alheio = response.status
      corpo_alheio = response.parsed_body

      get "/api/v1/charges/#{SecureRandom.uuid}", headers: headers
      expect(response.status).to eq(status_alheio)
      expect(response.parsed_body).to eq(corpo_alheio)
      expect(response).to have_http_status(:not_found)
    end

    it 'PUT em cobrança de outro projeto responde 404 e NÃO altera nada' do
      expect {
        put "/api/v1/charges/#{alheia.id}", params: { date: '2030-01-01' }, headers: headers, as: :json
      }.not_to(change { alheia.reload.date })
      expect(response).to have_http_status(:not_found)
    end

    it 'DELETE alheio NÃO apaga nada' do
      expect { delete "/api/v1/charges/#{alheia.id}", headers: headers }
        .not_to(change { Charge.count })
      expect(response).to have_http_status(:not_found)
      expect(Charge.exists?(alheia.id)).to be(true)
    end

    it 'o `project_id` do corpo é IGNORADO na criação' do
      # Mover pacote entre projetos arrastaria os recibos — e, por eles, as
      # operações — para outro tenant (DC-04).
      post '/api/v1/charges', params: { date: '2025-06-01', project_id: outro_projeto.id },
                              headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(Charge.find(response.parsed_body['id']).project_id).to eq(project.id)
    end
  end

  # ====================================================================
  # CRUD e o estado inicial
  # ====================================================================
  describe 'criação' do
    it 'nasce em `editing` por padrão' do
      # `../sfg/app/models/charge.rb:22-24` — `after_initialize` gravando
      # `self.state ||= @@STATE__EDITING`. Replicado em
      # `Charge#apply_default_state`, com a diferença de que o valor no banco
      # passa a ser `editing` e não o texto pt-BR "Edição" (BE-445: valor
      # estável no banco, rótulo na apresentação).
      post '/api/v1/charges', params: { date: '2025-06-01' }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['state']).to eq('editing')
      expect(response.parsed_body['state_label']).to eq('Edição')
      expect(response.parsed_body['done']).to be(false)
    end

    it 'o mesmo default vale para o objeto novo em memória' do
      expect(Charge.new.state).to eq(Charge::STATE_EDITING)
    end

    it 'aceita nascer em `available`' do
      post '/api/v1/charges', params: { date: '2025-06-01', state: 'available' }, headers: headers, as: :json
      expect(response.parsed_body['state']).to eq('available')
    end

    it 'NÃO aceita nascer em `done` — o Grape recusa com 400' do
      # `../sfg/app/views/pub/console/parts/charges/helper/_body.html.erb:11`
      # remove "Faturado" do select **só quando `charge.id.nil?`** — ou seja, a
      # regra existe e é do legado, mas mora no HTML. A API de 2022 aceitava
      # `state: "Faturado"` no `create` sem reclamar. Aqui o domínio do
      # parâmetro é fechado no servidor: `values` do Grape recusa antes de o
      # endpoint rodar, e por isso o status é **400** (validação de parâmetro),
      # não 422 (validação de negócio).
      expect {
        post '/api/v1/charges', params: { date: '2025-06-01', state: 'done' }, headers: headers, as: :json
      }.not_to(change { Charge.count })

      expect(response).to have_http_status(:bad_request)
    end

    it 'exige a data — a de hoje + 30 dias é decisão de INTERFACE (FE-186)' do
      post '/api/v1/charges', params: {}, headers: headers, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it 'o autor vem da SESSÃO' do
      post '/api/v1/charges', params: { date: '2025-06-01', user_id: create(:user).id },
                              headers: headers, as: :json
      expect(Charge.find(response.parsed_body['id']).user_id).to eq(og.id)
    end
  end

  # ====================================================================
  # D-18 — `done` bloqueia NO SERVIDOR
  # ====================================================================
  describe 'D-18 — cobrança Faturada recusa alteração no SERVIDOR' do
    # No legado o bloqueio existe **só na tela**:
    # `charges/detail/_body.html.erb:108` acrescenta a classe
    # `action_line__disabled` quando o estado é "Faturado", e
    # `charges/detail/_body.js.erb:68` desiste do clique por causa dela.
    # `pub/charges_controller.rb:92-98` (`update`) e `:100-106` (`destroy`) não
    # olham o estado: um `curl` alterava documento emitido.
    let!(:faturada) { create(:charge, project: project, author: og, state: 'done', date: Date.new(2025, 1, 5)) }

    it 'PUT de DATA em `done` responde 422 com mensagem clara' do
      expect {
        put "/api/v1/charges/#{faturada.id}", params: { date: '2030-01-01' }, headers: headers, as: :json
      }.not_to(change { faturada.reload.date })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Faturada')
      expect(response.parsed_body['message']).to include('não pode mais ser alterada')
    end

    it 'PUT de ESTADO em `done` também recusa — reabrir é alteração' do
      # A trava não é sobre a data: um pacote faturado é documento emitido, e
      # "voltar para Edição" é a alteração mais cara de todas.
      put "/api/v1/charges/#{faturada.id}", params: { state: 'editing' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(faturada.reload.state).to eq('done')
    end

    it 'DELETE em `done` responde 422 e o registro continua lá' do
      expect { delete "/api/v1/charges/#{faturada.id}", headers: headers }
        .not_to(change { Charge.count })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Faturada')
    end

    it '`editing` aceita PUT e DELETE' do
      aberta = create(:charge, project: project, author: og, state: 'editing', date: Date.new(2025, 2, 2))

      put "/api/v1/charges/#{aberta.id}", params: { date: '2025-02-20' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(aberta.reload.date).to eq(Date.new(2025, 2, 20))

      delete "/api/v1/charges/#{aberta.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(Charge.exists?(aberta.id)).to be(false)
    end

    it '`available` aceita PUT e DELETE' do
      disponivel = create(:charge, project: project, author: og, state: 'available', date: Date.new(2025, 2, 3))

      put "/api/v1/charges/#{disponivel.id}", params: { state: 'done' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(disponivel.reload.state).to eq('done')

      # E agora que ficou `done`, a porta fecha.
      put "/api/v1/charges/#{disponivel.id}", params: { date: '2025-03-03' }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ====================================================================
  # FE-180 — o filtro de ano em branco
  # ====================================================================
  describe 'FE-180 — filtros de ano, mês e estado' do
    # `pub/charges_controller.rb:119-133`:
    #
    #     @year = params[:year].blank? ? Date.current.year : params[:year]
    #
    # O ano em branco **virava o ano corrente**, e o `select` da tela não tinha
    # opção vazia: era impossível ver todas as cobranças de uma vez. O ramo
    # `else` com `DateTime.dinosaurs`/`DateTime.mars` (`:131-132`, um intervalo
    # de 4000 anos) era inalcançável justamente por causa dessa linha.
    let!(:de_2023) { create(:charge, project: project, author: og, date: Date.new(2023, 5, 10)) }
    let!(:de_2024_marco) { create(:charge, project: project, author: og, date: Date.new(2024, 3, 10)) }
    let!(:de_2024_julho) do
      create(:charge, project: project, author: og, date: Date.new(2024, 7, 10), state: 'available')
    end

    it 'ano EM BRANCO devolve TODAS as cobranças' do
      get '/api/v1/charges', headers: headers
      expect(response.parsed_body.size).to eq(3)
    end

    it 'ano preenchido filtra por ano' do
      get '/api/v1/charges', params: { year: 2024 }, headers: headers
      expect(response.parsed_body.map { |c| c['id'] }).to contain_exactly(de_2024_marco.id, de_2024_julho.id)
    end

    it 'mês em branco não filtra; mês preenchido filtra' do
      get '/api/v1/charges', params: { month: 3 }, headers: headers
      expect(response.parsed_body.map { |c| c['id'] }).to eq([de_2024_marco.id])
    end

    it 'ano e mês combinam' do
      get '/api/v1/charges', params: { year: 2023, month: 5 }, headers: headers
      expect(response.parsed_body.map { |c| c['id'] }).to eq([de_2023.id])

      get '/api/v1/charges', params: { year: 2024, month: 5 }, headers: headers
      expect(response.parsed_body).to eq([])
    end

    it 'estado em branco não filtra; estado preenchido filtra' do
      get '/api/v1/charges', params: { state: 'available' }, headers: headers
      expect(response.parsed_body.map { |c| c['id'] }).to eq([de_2024_julho.id])

      get '/api/v1/charges', params: { state: 'editing' }, headers: headers
      expect(response.parsed_body.map { |c| c['id'] }).to contain_exactly(de_2023.id, de_2024_marco.id)
    end

    it 'estado fora do domínio responde 400, não devolve a lista inteira' do
      get '/api/v1/charges', params: { state: 'Faturado' }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  # ====================================================================
  # Exclusão bloqueada por recibo
  # ====================================================================
  describe 'exclusão bloqueada por recibo vinculado' do
    it 'responde 422 nomeando "recibo(s)" e o pacote continua lá' do
      # `../sfg/app/models/charge.rb:5` —
      # `has_many :receipts, dependent: :restrict_with_error`. O
      # `pub/charges_controller.rb:104` transformava a recusa em
      # **`:internal_server_error`**: o usuário via 500 onde a regra tinha
      # funcionado exatamente como planejado.
      cobranca = create(:charge, project: project, author: og)
      criar_recibo(cobranca, kind: 'LIQ', value: '100.00', operation_value: '5000.00')

      expect { delete "/api/v1/charges/#{cobranca.id}", headers: headers }
        .not_to(change { Charge.count })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('recibo(s)')
      expect(Charge.exists?(cobranca.id)).to be(true)
    end

    it 'sem recibo, exclui' do
      cobranca = create(:charge, project: project, author: og)

      delete "/api/v1/charges/#{cobranca.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['deleted']).to be(true)
    end
  end

  # ====================================================================
  # Extrato — FE-182
  # ====================================================================
  describe 'GET /charges/:id/statement' do
    it 'devolve o extrato AGREGADO por remuneração' do
      # `pub/charges_controller.rb:52-58` (`show`) montava os totais em Ruby,
      # linha a linha, e o próprio código carregava um
      # `# TODO #7388 otimizar a busca`. Aqui é uma consulta agrupada — e o
      # exemplo confere que o agrupado bate com a soma manual, que é a condição
      # do Princípio 9 (otimização que muda resultado é defeito).
      cobranca = create(:charge, project: project, author: og)
      criar_recibo(cobranca, kind: 'LIQ', value: '100.00', operation_value: '5000.00', title: 'Comissão')
      criar_recibo(cobranca, kind: 'LIQ', value: '40.00', operation_value: '2000.00', title: 'Comissão')
      criar_recibo(cobranca, kind: 'EST', value: '75.00', operation_value: '2500.00', title: 'Estruturação')

      get "/api/v1/charges/#{cobranca.id}/statement", headers: headers

      expect(response).to have_http_status(:ok)
      corpo = response.parsed_body
      expect(corpo['charge']['id']).to eq(cobranca.id)

      linhas = corpo['statement'].index_by { |l| [l['kind'], l['title']] }
      comissao = linhas[%w[LIQ Comissão]]
      expect(comissao['receipts_count']).to eq(2)
      expect(BigDecimal(comissao['operations_value'].to_s)).to eq(BigDecimal('7000.00'))
      expect(BigDecimal(comissao['value'].to_s)).to eq(BigDecimal('140.00'))

      estruturacao = linhas[%w[EST Estruturação]]
      expect(estruturacao['receipts_count']).to eq(1)
      expect(BigDecimal(estruturacao['value'].to_s)).to eq(BigDecimal('75.00'))
    end

    it 'cobrança sem recibo devolve extrato vazio, não 404' do
      cobranca = create(:charge, project: project, author: og)
      get "/api/v1/charges/#{cobranca.id}/statement", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['statement']).to eq([])
    end

    it 'extrato de cobrança de OUTRO projeto responde 404' do
      alheia = create(:charge, project: outro_projeto)
      get "/api/v1/charges/#{alheia.id}/statement", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  # ====================================================================
  # Recibos — a dependência da S8, DECLARADA
  # ====================================================================
  # ====================================================================
  # Recibos — a dependência da S8, ENTREGUE
  # ====================================================================
  #
  # **Este bloco mudou de sinal na S8, e a mudança é o registro.** Enquanto
  # `Remuneration` não existia, os três primeiros exemplos afirmavam o 422 que
  # nomeava a fatia — que era o comportamento CORRETO então, não uma pendência
  # escondida: 500 diria "quebrou" quando nada quebrou, e uma lista vazia diria
  # "não há nada a faturar", que é falso e leva a fechar o mês com receita a
  # menos.
  #
  # Com a S8 no lugar, o mesmo endpoint responde **200 com candidatos**. Manter
  # os exemplos antigos "verdes" exigiria estubar a ausência do model — que é
  # exatamente o modo de falha que já apareceu três vezes nesta migração: spec
  # verde estubando justamente o que faltava. Eles foram reescritos, não
  # desligados.
  describe 'recibos, com `Remuneration` entregue pela S8' do
    let!(:cobranca) { create(:charge, project: project, author: og) }
    let(:company) { create(:company, project: project) }
    let(:tipo) { create(:structured_operation_type) }

    it 'o model e a tabela existem — o 422 que nomeava a S8 não é mais alcançável' do
      expect(Object.const_defined?('Remuneration')).to be(true)
      expect(Charges::ReceiptGenerator.remunerations_available?).to be(true)
    end

    it 'GET /charges/:id/receipts responde 200 com o candidato JÁ CALCULADO' do
      create(:remuneration, project: project, operation_type: tipo, value: BigDecimal('2.55'))
      operacao = create(:structured_operation, project: project, company: company,
                                               operation_type: tipo,
                                               operation_value: BigDecimal('200000.00'))

      get "/api/v1/charges/#{cobranca.id}/receipts", headers: headers

      expect(response).to have_http_status(:ok)
      candidato = response.parsed_body.find { |c| c['operation_id'] == operacao.id }
      expect(candidato).to be_present
      # Golden E1. O valor vem PRONTO do servidor — nenhum componente React
      # multiplica capital por taxa (design.md §1).
      expect(BigDecimal(candidato['value'].to_s)).to eq(BigDecimal('5100.00'))
      expect(candidato['kind']).to eq('EST')
      expect(candidato['temp_id']).to start_with("RCP-#{project.id}-EST-")
    end

    it 'projeto sem remuneração devolve 200 com lista VAZIA, não erro' do
      create(:structured_operation, project: project, company: company, operation_type: tipo,
                                    operation_value: BigDecimal('200000.00'))

      get "/api/v1/charges/#{cobranca.id}/receipts", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it 'PUT /charges/:id/receipts grava o lote e responde 200 (FE-185)' do
      create(:remuneration, project: project, operation_type: tipo, value: BigDecimal('2.55'))
      operacao = create(:structured_operation, project: project, company: company,
                                               operation_type: tipo,
                                               operation_value: BigDecimal('200000.00'))

      get "/api/v1/charges/#{cobranca.id}/receipts", headers: headers
      temp_id = response.parsed_body.first['temp_id']

      put "/api/v1/charges/#{cobranca.id}/receipts", params: { temp_ids: [temp_id] },
                                                     headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(Receipt.where(operation_id: operacao.id).count).to eq(1)
      # A ponta que fecha o ciclo: a operação sai de `available_for_receipt`.
      expect(operacao.reload.receipt_id).to be_present
    end

    it 'GET de recibos em cobrança de OUTRO projeto responde 404 (C1)' do
      alheia = create(:charge, project: outro_projeto)
      get "/api/v1/charges/#{alheia.id}/receipts", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'PUT de recibos em cobrança `done` recusa por D-18' do
      faturada = create(:charge, project: project, author: og, state: 'done')

      put "/api/v1/charges/#{faturada.id}/receipts", params: { temp_ids: ['qualquer'] },
                                                     headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Faturada')
    end
  end

  # ====================================================================
  # D-20 — paginação REAL
  # ====================================================================
  describe 'D-20 — paginação real' do
    before do
      45.times { |i| create(:charge, project: project, author: og, date: Date.new(2024, 1, 1) + i.days) }
    end

    it 'respeita `page`/`per_page` e emite os cabeçalhos' do
      # `pub/charges_controller.rb:109-117` (`fetch_loq`): o limite era **1000
      # fixo**, aplicado quando o cliente não mandava nada, e o cliente nunca
      # mandava. Não havia paginação no servidor — a lista vinha inteira (até
      # mil) e a UI paginava por cima.
      get '/api/v1/charges', params: { page: 2, per_page: 20 }, headers: headers

      expect(response.parsed_body.size).to eq(20)
      expect(response.headers['X-Total-Count']).to eq('45')
      expect(response.headers['X-Page']).to eq('2')
      expect(response.headers['X-Per-Page']).to eq('20')
      expect(response.headers['X-Total-Pages']).to eq('3')
    end

    it 'a ÚLTIMA página traz o resto' do
      get '/api/v1/charges', params: { page: 3, per_page: 20 }, headers: headers
      expect(response.parsed_body.size).to eq(5)
    end

    it 'o total do cabeçalho é o do FILTRO, não o da tabela' do
      get '/api/v1/charges', params: { year: 2024, month: 1, per_page: 5 }, headers: headers
      expect(response.headers['X-Total-Count']).to eq('31')
      expect(response.parsed_body.size).to eq(5)
    end

    it 'ordena por data DESC por padrão e aceita as chaves do contrato' do
      get '/api/v1/charges', params: { per_page: 5 }, headers: headers
      datas = response.parsed_body.map { |c| c['date'] }
      expect(datas).to eq(datas.sort.reverse)

      get '/api/v1/charges', params: { ordering_keys: ['date'], ordering_style: ['up'], per_page: 5 },
                             headers: headers
      datas = response.parsed_body.map { |c| c['date'] }
      expect(datas).to eq(datas.sort)
    end

    it 'chave de ordenação desconhecida é IGNORADA, não 500' do
      get '/api/v1/charges', params: { ordering_keys: ['drop table'], ordering_style: ['up'], per_page: 5 },
                             headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.size).to eq(5)
    end
  end

  # ====================================================================
  # Princípio 9 — `recalculate!` × a soma manual
  # ====================================================================
  describe 'Charge#recalculate! (Princípio 9)' do
    # `../sfg/app/models/charge.rb:48-63` (`calc!`) fazia **cinco agregações
    # separadas** — `liq.sum(:value)`, `est.sum(:value)`, `est.sum(:operation_value)`,
    # `liq.sum(:operation_value)`, `liq.count`, `est.count` — mais um
    # `self.receipts.count`, e terminava em `self.save` com o retorno ignorado
    # (`:62`). Aqui é **uma** consulta agrupada por `kind` e um `save!`.
    #
    # Otimização que muda resultado é defeito. Este bloco existe para provar
    # que não mudou: os totais da consulta agrupada são comparados com a soma
    # feita à mão, recibo a recibo, em Ruby.
    let(:cobranca) { create(:charge, project: project, author: og) }

    before do
      criar_recibo(cobranca, kind: 'LIQ', value: '150.55', operation_value: '7527.50')
      criar_recibo(cobranca, kind: 'LIQ', value: '80.10', operation_value: '4005.00')
      criar_recibo(cobranca, kind: 'LIQ', value: '12.34', operation_value: '617.00')
      criar_recibo(cobranca, kind: 'EST', value: '900.00', operation_value: '30000.00')
      criar_recibo(cobranca, kind: 'EST', value: '0.01', operation_value: '0.33')
    end

    it 'produz exatamente os totais da soma manual dos recibos' do
      cobranca.recalculate!
      cobranca.reload

      recibos = Receipt.where(charge_id: cobranca.id).to_a
      liq = recibos.select { |r| r.kind == 'LIQ' }
      est = recibos.select { |r| r.kind == 'EST' }

      expect(cobranca.value).to eq(liq.sum(&:value) + est.sum(&:value))
      expect(cobranca.risk_operations_value).to eq(liq.sum(&:operation_value))
      expect(cobranca.structured_operations_value).to eq(est.sum(&:operation_value))
      expect(cobranca.total_operations_value)
        .to eq(cobranca.risk_operations_value + cobranca.structured_operations_value)
      expect(cobranca.risk_operations_count).to eq(liq.size)
      expect(cobranca.structured_operations_count).to eq(est.size)
      expect(cobranca.receipts_count).to eq(recibos.size)
    end

    it 'os valores absolutos são os esperados' do
      # Os mesmos números escritos à mão: se a soma manual acima e a agregada
      # divergirem JUNTAS por um erro de fixture, este exemplo pega.
      cobranca.recalculate!

      expect(cobranca.value).to eq(BigDecimal('1143.00'))
      expect(cobranca.risk_operations_value).to eq(BigDecimal('12149.50'))
      expect(cobranca.structured_operations_value).to eq(BigDecimal('30000.33'))
      expect(cobranca.total_operations_value).to eq(BigDecimal('42149.83'))
      expect(cobranca.risk_operations_count).to eq(3)
      expect(cobranca.structured_operations_count).to eq(2)
      expect(cobranca.receipts_count).to eq(5)
    end

    it 'pacote SEM recibo zera os sete totais, em vez de deixar o valor antigo' do
      # O `group(:kind)` não devolve linha para o tipo ausente. Ler o resultado
      # sem default deixaria o total anterior gravado — e um pacote esvaziado
      # continuaria "valendo" o que valia antes.
      cobranca.recalculate!
      Receipt.where(charge_id: cobranca.id).delete_all
      cobranca.recalculate!.reload

      expect(cobranca.value).to eq(0)
      expect(cobranca.risk_operations_value).to eq(0)
      expect(cobranca.structured_operations_value).to eq(0)
      expect(cobranca.total_operations_value).to eq(0)
      expect(cobranca.receipts_count).to eq(0)
    end

    it 'só de LIQ, o bucket EST fica zerado (e não nulo)' do
      Receipt.where(charge_id: cobranca.id, kind: 'EST').delete_all
      cobranca.recalculate!.reload

      expect(cobranca.structured_operations_value).to eq(0)
      expect(cobranca.structured_operations_count).to eq(0)
      expect(cobranca.total_operations_value).to eq(cobranca.risk_operations_value)
    end

    it 'NÃO conta recibo de outra cobrança' do
      outra = create(:charge, project: project, author: og)
      criar_recibo(outra, kind: 'LIQ', value: '999.99', operation_value: '99999.00')

      cobranca.recalculate!.reload
      expect(cobranca.receipts_count).to eq(5)
      expect(cobranca.value).to eq(BigDecimal('1143.00'))
    end

    it 'devolve `self`, e o total gravado é o mesmo que o endpoint publica' do
      expect(cobranca.recalculate!).to eq(cobranca)

      get "/api/v1/charges/#{cobranca.id}", headers: headers
      expect(BigDecimal(response.parsed_body['value'].to_s)).to eq(BigDecimal('1143.00'))
      expect(response.parsed_body['receipts_count']).to eq(5)
    end
  end

  # ====================================================================
  # Autorização
  # ====================================================================
  describe 'autorização' do
    it 'sem credencial responde 401' do
      get '/api/v1/charges'
      expect(response).to have_http_status(:unauthorized)
    end

    it 'usuário SEM participação no projeto responde 404 — igual a projeto inexistente' do
      estranho = create(:user, :colaborador)
      get '/api/v1/charges', headers: auth_headers(estranho, project: project)
      expect(response).to have_http_status(:not_found)
    end

    it 'Colaborador participante TEM CRUD em `charges` (DEC-15.1)' do
      # A matriz dá `CRUD` aos quatro papéis: os 4 itens `locked` do legado
      # nascem HABILITADOS porque produção é a verdade, não a intenção aparente
      # do código.
      colaborador = create(:user, :colaborador)
      Membership.create!(project: project, user: colaborador, role: 'participante')

      post '/api/v1/charges', params: { date: '2025-06-01' },
                              headers: auth_headers(colaborador, project: project), as: :json
      expect(response).to have_http_status(:created)
    end

    it 'somente-leitura NÃO cria, mesmo chamando a API direto' do
      permissao = Permission.find_or_create_by!(key: 'user_is_readonly') { |p| p.title = 'Somente leitura' }
      UserPermission.create!(user: og, permission: permissao, granted_at: Time.current, source: 'manual')

      expect {
        post '/api/v1/charges', params: { date: '2025-06-01' }, headers: headers, as: :json
      }.not_to(change { Charge.count })

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('READONLY_RESTRICTED')
    end
  end
end
