# frozen_string_literal: true

require 'rails_helper'

# S7 / **BE-253..BE-277** — as operações de risco pela **borda HTTP**.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# As seis migrations da família estão entre as **24 que nunca subiram**
# (`analise-dump-producao.md` §1). Estes exemplos travam a leitura do fonte de
# 2022 (`../sfg/app/controllers/pub/risk_operations_controller.rb`,
# `risk_movements_controller.rb`, `risk_operation_extensions_controller.rb`),
# **não** um comportamento observado.
#
# Duas famílias de exemplo, porém, **não** replicam o legado e não deveriam:
# escopo por projeto (**C1**, as duas IDORs) e autorização (**C3**) são a
# EXCEÇÃO-2 do DEC-30.
RSpec.describe 'API V1 Risk operations', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
    Seeds::Reference::RiskMovementTypes.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro_gerente) { create(:user, user_type: UserType.gerente) }
  let(:colaborador) { create(:user, user_type: UserType.colaborador) }
  let(:admin) { create(:user, user_type: UserType.admin) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'ro-a', name: 'Risco A') }
  let!(:projeto_b) { create_project_with_owner(outro_gerente, slug: 'ro-b', name: 'Risco B') }

  let(:empresa_a) { create(:company, project: projeto_a, title: 'Empresa A') }
  let(:empresa_b) { create(:company, project: projeto_b, title: 'Empresa B') }

  let(:portador_alfa) { create(:carrier, title: 'Banco Alfa') }
  let(:portador_beta) { create(:carrier, title: 'Banco Beta') }
  let(:tipo) { create(:risk_operation_type, title: 'Fomento S7') }

  let!(:limite_a) do
    create(:risk_control, project: projeto_a, company: empresa_a, carrier: portador_alfa,
                          risk_operation_type: tipo, limite: 500_000, taxa: 2.55)
  end
  let!(:limite_b) do
    create(:risk_control, project: projeto_b, company: empresa_b, carrier: portador_beta,
                          risk_operation_type: tipo, limite: 500_000, taxa: 1.10)
  end

  let!(:op_a) do
    create(:risk_operation, risk_control: limite_a, author: gerente, title: 'Operação A',
                            operation_value: 100_000, original_balance: 100_000,
                            issue_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 6, 30))
  end
  let!(:op_b) do
    create(:risk_operation, risk_control: limite_b, author: outro_gerente, title: 'Operação B',
                            operation_value: 50_000, original_balance: 0,
                            issue_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 6, 30))
  end

  # =====================================================================
  # BE-253 — lista
  # =====================================================================
  describe 'GET /api/v1/risk_operations' do
    it 'lista SÓ o projeto corrente (C1)' do
      get '/api/v1/risk_operations', headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body).map { |o| o['id'] }).to eq([op_a.id])
    end

    # --- D-100, a IDOR --------------------------------------------------
    it 'D-100 — risk_operation_id filtra DENTRO do escopo, nunca substitui a relation' do
      # `risk_operations_controller.rb:23` faz
      # `RiskOperation.where(id: params[:risk_operation_id])`, jogando fora o
      # `where(project_id:)` da linha anterior: qualquer autenticado lia
      # operação de qualquer projeto.
      get '/api/v1/risk_operations', params: { risk_operation_id: op_b.id },
                                     headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to be_empty
      expect(response.headers['X-Total-Count']).to eq('0')
    end

    it 'o par ESTÁTICO do limite não aparece na lista' do
      tipo_pre = create(:risk_operation_type, :com_pre, title: 'Comissária S7')
      create(:risk_control, project: projeto_a, company: empresa_a,
                            carrier: create(:carrier, title: 'Banco Pré'),
                            risk_operation_type: tipo_pre)

      get '/api/v1/risk_operations', headers: auth_headers(gerente, project: projeto_a)
      expect(JSON.parse(response.body).map { |o| o['id'] }).to eq([op_a.id])
    end

    it 'busca em título do PORTADOR ou da OPERAÇÃO' do
      get '/api/v1/risk_operations', params: { q: 'alfa' },
                                     headers: auth_headers(gerente, project: projeto_a)
      expect(JSON.parse(response.body).map { |o| o['id'] }).to eq([op_a.id])

      get '/api/v1/risk_operations', params: { q: 'Operação A' },
                                     headers: auth_headers(gerente, project: projeto_a)
      expect(JSON.parse(response.body).map { |o| o['id'] }).to eq([op_a.id])
    end

    it 'X-Total-Count é o total REAL, calculado antes do recorte' do
      # No legado `@total_count = @risk_operations.count` roda DEPOIS do
      # `limit!/offset!` (`:34,40,44`): o total era o tamanho da página e a
      # paginação nunca passava de uma.
      3.times do |i|
        create(:risk_operation, risk_control: limite_a, author: gerente, title: "Extra #{i}")
      end

      get '/api/v1/risk_operations', params: { per_page: 2 },
                                     headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).size).to eq(2)
      expect(response.headers['X-Total-Count']).to eq('4')
      expect(response.headers['X-Total-Pages']).to eq('2')
    end

    it 'chave de ordenação desconhecida devolve 400 — no legado é 500' do
      # `get_ordering_key` devolve `nil` fora do `case` e a linha seguinte faz
      # `nil + " "` → `NoMethodError`.
      get '/api/v1/risk_operations', params: { ordering_keys: ['inventada'] },
                                     headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(400)
      expect(JSON.parse(response.body)['message']).to include('inventada')
    end

    it 'aceita a allowlist e ordena por várias colunas' do
      get '/api/v1/risk_operations',
          params: { ordering_keys: %w[carrier due_date], ordering_style: %w[up down] },
          headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(200)
    end

    it 'order_mode=dash força emissão decrescente e ignora as chaves' do
      antiga = create(:risk_operation, risk_control: limite_a, author: gerente,
                                       issue_date: Date.new(2026, 1, 1), due_date: Date.new(2026, 5, 1))
      get '/api/v1/risk_operations', params: { order_mode: 'dash' },
                                     headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).map { |o| o['id'] }).to eq([op_a.id, antiga.id])
    end

    it 'a janela from/to é fechada nos dois lados (BE-242)' do
      get '/api/v1/risk_operations', params: { from: '2026-07-01', to: '2026-12-31' },
                                     headers: auth_headers(gerente, project: projeto_a)
      expect(JSON.parse(response.body)).to be_empty

      get '/api/v1/risk_operations', params: { from: '2026-06-30', to: '2026-03-01' },
                                     headers: auth_headers(gerente, project: projeto_a)
      expect(JSON.parse(response.body).map { |o| o['id'] }).to eq([op_a.id])
    end
  end

  # =====================================================================
  # BE-254 — combos
  # =====================================================================
  describe 'GET /api/v1/risk_operations/filters' do
    it 'search_type=company devolve os portadores com limite ativo de tipo manual' do
      get '/api/v1/risk_operations/filters',
          params: { search_type: 'company', company_id: empresa_a.id },
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body).map { |c| c['id'] }).to eq([portador_alfa.id])
    end

    it 'search_type=carrier devolve os tipos manuais do trio' do
      get '/api/v1/risk_operations/filters',
          params: { search_type: 'carrier', company_id: empresa_a.id, carrier_id: portador_alfa.id },
          headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body).map { |t| t['id'] }).to eq([tipo.id])
    end

    it 'search_type desconhecido devolve 400 — no legado era {} com 200' do
      get '/api/v1/risk_operations/filters',
          params: { search_type: 'inventado', company_id: empresa_a.id },
          headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(400)
    end

    it 'empresa de OUTRO projeto devolve 404 — no legado, Company.find → 500' do
      get '/api/v1/risk_operations/filters',
          params: { search_type: 'company', company_id: empresa_b.id },
          headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end
  end

  # =====================================================================
  # BE-256 — criação
  # =====================================================================
  describe 'POST /api/v1/risk_operations' do
    let(:payload) do
      { company_id: empresa_a.id, carrier_id: portador_alfa.id, operation_type_id: tipo.id,
        title: 'Nova operação', issue_date: '2026-04-01', due_date: '2026-08-31',
        operation_value: '250000.00', original_balance: '250000.00', agreed_rate: '3.10' }
    end

    it 'cria com a cascata inteira e devolve 201' do
      post '/api/v1/risk_operations', params: payload, headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      corpo = JSON.parse(response.body)
      expect(corpo['risk_control_id']).to eq(limite_a.id)
      expect(corpo['operation_subtype_id']).to eq(tipo.default_subtype.id)
      expect(corpo['original_balance'].to_f).to eq(-250_000.00)
      expect(corpo['original_balance_abs'].to_f).to eq(250_000.00)
      expect(corpo['balance'].to_f).to eq(0.00)

      operacao = RiskOperation.find(corpo['id'])
      expect(operacao.user_id).to eq(gerente.id)
      expect(operacao.original_due_date).to eq(Date.new(2026, 8, 31))
      expect(operacao.movements.count).to eq(1)
    end

    it 'BE-261 — sem limite para a quádrupla, recusa dizendo o que falta' do
      outro_portador = create(:carrier, title: 'Banco Sem Limite')
      create(:project_to_carrier_connection, project: projeto_a, carrier: outro_portador)

      post '/api/v1/risk_operations', params: payload.merge(carrier_id: outro_portador.id),
                                      headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(JSON.parse(response.body)['message']).to include('não existe limite cadastrado')
    end

    it 'BE-261 — limite DESATIVADO continua aceitando operação (replicado, DEC-105)' do
      limite_a.update!(is_active: false)
      post '/api/v1/risk_operations', params: payload, headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(201)
    end

    it 'BE-262 / DEC-67 — subtipo informado SOBRESCREVE o tipo' do
      outro_tipo = create(:risk_operation_type, title: 'Outro tipo S7')
      create(:risk_control, project: projeto_a, company: empresa_a, carrier: portador_alfa,
                            risk_operation_type: outro_tipo)

      post '/api/v1/risk_operations',
           params: payload.merge(operation_subtype_id: outro_tipo.default_subtype.id),
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      expect(JSON.parse(response.body)['operation_type_id']).to eq(outro_tipo.id)
    end

    it 'BE-267 / Q-R7 — capital ZERO e vencimento anterior à emissão continuam aceitos' do
      # **Replicar as ausências.** O legado não tem `operation_value > 0` nem
      # `due_date >= issue_date` (`:54-62`). Acrescentá-las recusaria dado que
      # hoje entra, e isso é decisão de usuário.
      post '/api/v1/risk_operations',
           params: payload.merge(operation_value: '0', issue_date: '2026-08-31', due_date: '2026-04-01'),
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)

      # **Consequência do espelho, e ela é visível.** Com a janela invertida o
      # movimento de liberação é recusado por `BE-274` — e o legado usa
      # `RiskMovement.create` **sem bang** (`risk_operation.rb:41`), então a
      # operação é gravada assim mesmo, **sem movimento**. Trocar por `create!`
      # seria mais correto e não seria o espelho (DEC-103b / DEC-105).
      operacao = RiskOperation.find(JSON.parse(response.body)['id'])
      expect(operacao.movements).to be_empty
      # Sem movimento, o cache do saldo fica em `original_balance` (`:110`).
      expect(operacao.balance).to eq(-250_000.00)
    end

    it 'BE-264 — tipo COM pré-faturamento não ganha movimento de liberação' do
      tipo_pre = create(:risk_operation_type, :com_pre, title: 'Pré S7')
      portador_pre = create(:carrier, title: 'Banco Pré S7')
      create(:risk_control, project: projeto_a, company: empresa_a, carrier: portador_pre,
                            risk_operation_type: tipo_pre)

      post '/api/v1/risk_operations',
           params: payload.merge(carrier_id: portador_pre.id, operation_type_id: tipo_pre.id),
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      expect(RiskOperation.find(JSON.parse(response.body)['id']).movements).to be_empty
    end

    it 'balance NÃO entra no permit — é cache derivado' do
      post '/api/v1/risk_operations', params: payload.merge(balance: '999999'),
                                      headers: auth_headers(gerente, project: projeto_a)
      expect(JSON.parse(response.body)['balance'].to_f).to eq(0.00)
    end

    it 'empresa de OUTRO projeto não cria nada (C1)' do
      # **Regressão que este exemplo pegou, e que vale registro:** replicar o
      # `self.project_id = self.company.project_id` do legado (`:28`) sem trava
      # nenhuma deixava a operação nascer no projeto da empresa enviada — o
      # `record.project = project` do molde era sobrescrito pelo callback. A
      # resolução de empresa e portador DENTRO do projeto corrente é
      # EXCEÇÃO-2 do DEC-30.
      post '/api/v1/risk_operations', params: payload.merge(company_id: empresa_b.id),
                                      headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
      # Só a `op_b` do `let!`, que nasceu no projeto B por caminho legítimo.
      expect(RiskOperation.where(company_id: empresa_b.id).count).to eq(1)
    end
  end

  # =====================================================================
  # BE-257 — edição
  # =====================================================================
  describe 'PUT /api/v1/risk_operations/:id' do
    it 'T-D5 / FE-260 — as datas NÃO são editáveis, e o servidor aplica a regra' do
      put "/api/v1/risk_operations/#{op_a.id}",
          params: { title: 'Renomeada', issue_date: '2020-01-01', due_date: '2030-01-01' },
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      op_a.reload
      expect(op_a.title).to eq('Renomeada')
      expect(op_a.issue_date).to eq(Date.new(2026, 3, 1))
      expect(op_a.due_date).to eq(Date.new(2026, 6, 30))
    end

    it 'BE-257 — editar operation_value NÃO regenera o movimento de liberação (replicado)' do
      put "/api/v1/risk_operations/#{op_a.id}", params: { operation_value: '10000' },
                                                headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      liberacao = op_a.reload.movements.order(:sequence).first
      expect(liberacao.movement_value).to eq(100_000.00)
    end

    it 'operação de outro projeto responde 404, igual a id inexistente (C1)' do
      put "/api/v1/risk_operations/#{op_b.id}", params: { title: 'x' },
                                                headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end
  end

  # =====================================================================
  # BE-258 — exclusão
  # =====================================================================
  describe 'DELETE /api/v1/risk_operations/:id' do
    it 'apaga a operação e os movimentos junto' do
      delete "/api/v1/risk_operations/#{op_a.id}", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(RiskOperation.exists?(op_a.id)).to be(false)
      expect(RiskMovement.where(risk_operation_id: op_a.id).count).to eq(0)
    end

    it 'D-98 — operação com RECIBO responde 422 DE VERDADE' do
      # No legado a resposta é literalmente `errors.any? ? :ok : :ok` (`:139`) e
      # a tela dizia "Operação foi removida com sucesso!" sem ter removido.
      recibo = Receipt.create!(project: projeto_a, operation: op_a, user_id: gerente.id,
                               kind: Receipt::KIND_RISK, title: 'Recibo S7',
                               fee: 1.0, operation_value: 100_000, value: 1_000)
      op_a.update_columns(receipt_id: recibo.id)

      delete "/api/v1/risk_operations/#{op_a.id}", headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(422)
      expect(RiskOperation.exists?(op_a.id)).to be(true)
    end

    it 'apaga as prorrogações junto (FK em cascata, DB-237)' do
      Risk::ExtensionService.create(project: projeto_a, operation_id: op_a.id,
                                    attrs: { new_due_date: Date.new(2026, 8, 31) }, actor: gerente)
      expect(RiskOperationExtension.count).to eq(1)

      delete "/api/v1/risk_operations/#{op_a.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(RiskOperationExtension.count).to eq(0)
    end
  end

  # =====================================================================
  # BE-255 — última movimentação
  # =====================================================================
  describe 'GET /api/v1/risk_operations/:id/last_movement' do
    it 'devolve o último movimento por sequence' do
      get "/api/v1/risk_operations/#{op_a.id}/last_movement",
          headers: auth_headers(gerente, project: projeto_a)

      corpo = JSON.parse(response.body)
      expect(corpo['movement_type']).to eq('Liberação do Recurso')
      expect(corpo['movement_value_sign']).to eq(1)
    end

    it 'devolve {} para operação sem movimento — no legado é 500' do
      tipo_pre = create(:risk_operation_type, :com_pre, title: 'Pré vazio S7')
      controle = create(:risk_control, project: projeto_a, company: empresa_a,
                                       carrier: create(:carrier, title: 'Banco Vazio'),
                                       risk_operation_type: tipo_pre)
      estatica = controle.risk_operations.first

      get "/api/v1/risk_operations/#{estatica.id}/last_movement",
          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body)).to eq({})
    end
  end

  # =====================================================================
  # BE-270..BE-273 — movimentos
  # =====================================================================
  describe 'movimentos' do
    it 'BE-270 — a listagem é paginada e ordenada por sequence' do
      RiskMovement.create!(risk_operation: op_a, movement_type: RiskMovementType.find_by(integration_key: 'juros'),
                           date: Date.new(2026, 3, 15), movement_value: 2_500, balance: 0, user_id: gerente.id)

      get "/api/v1/risk_operations/#{op_a.id}/movements", params: { per_page: 1 },
                                                          headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(JSON.parse(response.body).size).to eq(1)
      expect(response.headers['X-Total-Count']).to eq('2')
      expect(JSON.parse(response.body).first['sequence']).to eq(1)
    end

    # --- A SEGUNDA IDOR -------------------------------------------------
    it 'BE-270 — o extrato de operação de OUTRO projeto responde 404 (a IDOR morre aqui)' do
      # `risk_movements_controller.rb:15` é
      # `RiskMovement.where(risk_operation_id: params[:risk_operation_id])`,
      # **sem escopo nenhum**: qualquer autenticado lia o extrato de qualquer
      # operação, de qualquer projeto.
      get "/api/v1/risk_operations/#{op_b.id}/movements",
          headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end

    it 'BE-272 — o payload não escolhe projeto, empresa nem portador' do
      post "/api/v1/risk_operations/#{op_a.id}/movements",
           params: { movement_type_id: RiskMovementType.find_by(integration_key: 'juros').id,
                     date: '2026-03-15', movement_value: '2500.00',
                     project_id: projeto_b.id, company_id: empresa_b.id },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      movimento = RiskMovement.find(JSON.parse(response.body)['id'])
      expect(movimento.project_id).to eq(projeto_a.id)
      expect(movimento.company_id).to eq(empresa_a.id)
      expect(movimento.user_id).to eq(gerente.id)
    end

    it 'B-05 — movement_value <= 0 é recusado NO SERVIDOR' do
      post "/api/v1/risk_operations/#{op_a.id}/movements",
           params: { movement_type_id: RiskMovementType.find_by(integration_key: 'juros').id,
                     date: '2026-03-15', movement_value: '-2500.00' },
           headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)
    end

    it 'BE-274 — data fora da janela é recusada, fechada nas duas pontas' do
      post "/api/v1/risk_operations/#{op_a.id}/movements",
           params: { movement_type_id: RiskMovementType.find_by(integration_key: 'juros').id,
                     date: '2026-07-01', movement_value: '100.00' },
           headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)

      post "/api/v1/risk_operations/#{op_a.id}/movements",
           params: { movement_type_id: RiskMovementType.find_by(integration_key: 'juros').id,
                     date: '2026-06-30', movement_value: '100.00' },
           headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(201)
    end

    it 'tipo exclusivo do sistema não é lançável manualmente' do
      post "/api/v1/risk_operations/#{op_a.id}/movements",
           params: { movement_type_id: RiskMovementType.release.id,
                     date: '2026-03-15', movement_value: '100.00' },
           headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)
    end

    it 'BE-271 — as opções do drawer trazem a janela e os tipos manuais' do
      get "/api/v1/risk_operations/#{op_a.id}/movements/options",
          headers: auth_headers(gerente, project: projeto_a)

      corpo = JSON.parse(response.body)
      expect(corpo['mode']).to eq('new')
      expect(corpo['movement_type_locked']).to be(false)
      expect(corpo['min_date']).to eq('2026-03-01')
      expect(corpo['max_date']).to eq('2026-06-30')
      expect(corpo['movement_types'].map { |t| t['integration_key'] })
        .not_to include(RiskMovementType::RELEASE_KEY)
    end

    # **BE-275 / DEC-137 — este exemplo travava o comportamento ERRADO.**
    #
    # Ele exigia 422 quando a operação não é de subtipo pré. No legado a
    # condição `is_pre?` mora no `after_create` do movimento
    # (`risk_movement.rb:46`) e decide se a CONTRAPARTIDA nasce — nunca se a
    # transferência pode ser lançada. Recusar era transformar uma regra sobre o
    # par numa trava sobre o lançamento, e o cabeçalho do `TransferService` já
    # descrevia o comportamento certo enquanto a linha de baixo o contrariava.
    it 'BE-275 — mode=transfer abre também fora da pré; o que muda é a contrapartida' do
      get "/api/v1/risk_operations/#{op_a.id}/movements/options", params: { mode: 'transfer' },
                                                                  headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      corpo = JSON.parse(response.body)
      expect(corpo['mode']).to eq('transfer')
      # O tipo continua fixado: transferência é sempre "Valor Transferido".
      expect(corpo['movement_type_locked']).to be(true)
    end

    it 'BE-273 — excluir renumera o sequence dos restantes' do
      juros = RiskMovement.create!(risk_operation: op_a,
                                   movement_type: RiskMovementType.find_by(integration_key: 'juros'),
                                   date: Date.new(2026, 3, 15), movement_value: 2_500,
                                   balance: 0, user_id: gerente.id)
      liberacao = op_a.movements.order(:sequence).first

      delete "/api/v1/risk_operations/#{op_a.id}/movements/#{liberacao.id}",
             headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(juros.reload.sequence).to eq(1)
      expect(juros.balance).to eq(-97_500.00)
    end
  end

  # =====================================================================
  # BE-259/BE-260 e BE-277 pela borda
  # =====================================================================
  describe 'renovação e prorrogação' do
    it 'GET :id/renewal sugere as datas preservando o prazo' do
      travel_to Date.new(2026, 5, 20) do
        get "/api/v1/risk_operations/#{op_a.id}/renewal", headers: auth_headers(gerente, project: projeto_a)
      end
      expect(JSON.parse(response.body)['due_date']).to eq('2026-09-18')
    end

    it 'POST :id/renewal cria a nova SEM encerrar a original (DEC-35)' do
      post "/api/v1/risk_operations/#{op_a.id}/renewal",
           params: { issue_date: '2026-05-20', due_date: '2026-09-18' },
           headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(201)
      expect(JSON.parse(response.body)['original_id']).to eq(op_a.id)
      expect(op_a.reload.is_ended).to be(false)
    end

    it 'POST :id/extensions estica o vencimento e recusa encurtar' do
      post "/api/v1/risk_operations/#{op_a.id}/extensions", params: { new_due_date: '2026-08-31' },
                                                            headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(201)
      expect(op_a.reload.due_date).to eq(Date.new(2026, 8, 31))

      post "/api/v1/risk_operations/#{op_a.id}/extensions", params: { new_due_date: '2026-07-01' },
                                                            headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(422)
    end

    it 'o original_due_date do formulário é IGNORADO' do
      post "/api/v1/risk_operations/#{op_a.id}/extensions",
           params: { new_due_date: '2026-08-31', original_due_date: '2000-01-01' },
           headers: auth_headers(gerente, project: projeto_a)

      expect(JSON.parse(response.body)['original_due_date']).to eq('2026-06-30')
    end
  end

  # =====================================================================
  # C1 e C3 — escopo e autorização
  # =====================================================================
  describe 'escopo (C1) e autorização (C3)' do
    it 'um usuário de P1 não alcança operação NEM movimento de P2' do
      get "/api/v1/risk_operations/#{op_b.id}", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)

      get "/api/v1/risk_operations/#{op_b.id}/movements", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)

      get "/api/v1/risk_operations/#{op_b.id}/extensions", headers: auth_headers(gerente, project: projeto_a)
      expect(response).to have_http_status(404)
    end

    it 'o Colaborador do projeto LÊ e ESCREVE (a matriz é CRUD para os quatro papéis)' do
      # **Os dois lados do C3.** Aqui o gate é a PARTICIPAÇÃO no projeto (C1),
      # não o papel: a linha `risk_operations` da matriz é `CRUD CRUD CRUD CRUD`.
      Membership.create!(project: projeto_a, user: colaborador, role: 'participante')

      get '/api/v1/risk_operations', headers: auth_headers(colaborador, project: projeto_a)
      expect(response).to have_http_status(200)
    end

    it 'o Colaborador SEM participação não alcança o projeto (o outro lado)' do
      get '/api/v1/risk_operations', headers: auth_headers(colaborador, project: projeto_a)
      expect(response.status).to be_between(403, 409)
    end

    it 'o Admin enxerga todo projeto, sem participação (DEC-99)' do
      get '/api/v1/risk_operations', headers: auth_headers(admin, project: projeto_a)
      expect(response).to have_http_status(200)
    end

    it 'sem autenticação, 401' do
      get '/api/v1/risk_operations'
      expect(response).to have_http_status(401)
    end
  end
end
