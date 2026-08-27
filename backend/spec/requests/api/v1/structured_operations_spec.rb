# frozen_string_literal: true

require 'rails_helper'

# S8 / **BE-280**…**BE-287**, **BE-291**, **FE-309**, **OPS-283**, **OPS-288**,
# tarefas 12.3, 12.5, 12.6 e 12.7.
#
# O primeiro exemplo é a IDOR literal do legado
# (`structured_operations_controller.rb:25`): a linha
#
#     @structured_operations = StructuredOperation.where(id: params[:structured_operation_id])
#
# **reatribui** a relação escopada da linha anterior, e o filtro de projeto
# desaparece — qualquer autenticado lia operação de qualquer projeto pela query
# string.
RSpec.describe 'API V1 Structured operations', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:outro) { create(:user, user_type: UserType.gerente) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'est-a', name: 'Estruturadas A') }
  let!(:projeto_b) { create_project_with_owner(outro, slug: 'est-b', name: 'Estruturadas B') }

  let(:empresa_a) { create(:company, project: projeto_a, title: 'Empresa A') }
  let(:empresa_b) { create(:company, project: projeto_b, title: 'Empresa B') }
  let(:portador) { create(:carrier, title: 'Portador Alfa') }
  let(:tipo) { create(:structured_operation_type, title: 'Fomento S8') }

  let!(:op_a) do
    create(:structured_operation, project: projeto_a, company: empresa_a, carrier: portador,
                                  operation_type: tipo, title: 'Operação A',
                                  operation_value: BigDecimal('200000.00'),
                                  issue_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 6, 30))
  end
  let!(:op_b) do
    create(:structured_operation, project: projeto_b, company: empresa_b, carrier: portador,
                                  operation_type: tipo, title: 'Operação B',
                                  operation_value: BigDecimal('90000.00'))
  end

  def headers_a = auth_headers(gerente, project: projeto_a)

  # ====================================================================
  # C1 — escopo. O defeito que define a fatia.
  # ====================================================================
  describe 'GET /api/v1/structured_operations — escopo (BE-280)' do
    it 'com `structured_operation_id` de OUTRO projeto devolve VAZIO, não a operação alheia' do
      get '/api/v1/structured_operations', params: { structured_operation_id: op_b.id }, headers: headers_a

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to be_empty
      expect(response.headers['X-Total-Count']).to eq('0')
    end

    it 'com `structured_operation_id` do PRÓPRIO projeto filtra DENTRO do escopo' do
      get '/api/v1/structured_operations', params: { structured_operation_id: op_a.id }, headers: headers_a

      expect(response.parsed_body.map { |o| o['id'] }).to eq([op_a.id])
    end

    it 'sem filtro nenhum, só as do projeto corrente' do
      get '/api/v1/structured_operations', headers: headers_a

      expect(response.parsed_body.map { |o| o['id'] }).to eq([op_a.id])
    end

    it 'GET /:id de operação de outro projeto responde 404, não 403 (não é oráculo de ids)' do
      get "/api/v1/structured_operations/#{op_b.id}", headers: headers_a
      expect(response).to have_http_status(404)
    end

    it 'PUT em operação de outro projeto responde 404 (BE-286)' do
      put "/api/v1/structured_operations/#{op_b.id}", params: { title: 'Sequestrada' },
                                                      headers: headers_a, as: :json

      expect(response).to have_http_status(404)
      expect(op_b.reload.title).to eq('Operação B')
    end

    it 'DELETE em operação de outro projeto responde 404' do
      delete "/api/v1/structured_operations/#{op_b.id}", headers: headers_a
      expect(response).to have_http_status(404)
      expect(StructuredOperation.exists?(op_b.id)).to be(true)
    end
  end

  # ====================================================================
  # FE-309 — autenticação. Nenhum endpoint responde sem JWT.
  # ====================================================================
  describe 'autenticação (FE-309)' do
    it 'nenhum verbo responde sem JWT válido' do
      get '/api/v1/structured_operations'
      expect(response).to have_http_status(401)

      post '/api/v1/structured_operations', params: {}, as: :json
      expect(response).to have_http_status(401)

      put "/api/v1/structured_operations/#{op_a.id}", params: {}, as: :json
      expect(response).to have_http_status(401)

      delete "/api/v1/structured_operations/#{op_a.id}"
      expect(response).to have_http_status(401)
    end
  end

  # ====================================================================
  # BE-281 / BE-282 / BE-283 / BE-284 — busca, período, ordenação, total
  # ====================================================================
  describe 'busca, período e ordenação' do
    it 'a busca alcança portador OU título, e SÓ isso (Q-R12 — o alcance é replicado)' do
      get '/api/v1/structured_operations', params: { q: 'Portador Alfa' }, headers: headers_a
      expect(response.parsed_body.size).to eq(1)

      get '/api/v1/structured_operations', params: { q: 'Operação A' }, headers: headers_a
      expect(response.parsed_body.size).to eq(1)

      # O legado NÃO busca por número de contrato nem por empresa, embora as
      # duas apareçam na tabela. A limitação é replicada de propósito.
      get '/api/v1/structured_operations', params: { q: 'CT-0001' }, headers: headers_a
      expect(response.parsed_body).to be_empty

      get '/api/v1/structured_operations', params: { q: 'Empresa A' }, headers: headers_a
      expect(response.parsed_body).to be_empty
    end

    it 'o termo é escapado: `100%` é texto literal, não curinga (OPS-056)' do
      get '/api/v1/structured_operations', params: { q: '100%' }, headers: headers_a
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to be_empty
    end

    it 'o período INTERSECTA o intervalo da operação (BE-282)' do
      get '/api/v1/structured_operations',
          params: { from: '2026-06-01', to: '2026-06-15' }, headers: headers_a
      expect(response.parsed_body.size).to eq(1)

      get '/api/v1/structured_operations',
          params: { from: '2027-01-01', to: '2027-01-31' }, headers: headers_a
      expect(response.parsed_body).to be_empty
    end

    it 'IMP-R4 — operação com data NULA aparece quando não há filtro de período' do
      # No legado a sentinela `DateTime.dinosaurs`/`mars` ia como bound e o
      # `DATE(NULL)` excluía a linha **em silêncio**. Aqui, sem `from`/`to`, o
      # predicado simplesmente não é aplicado.
      sem_data = create(:structured_operation, project: projeto_a, company: empresa_a,
                                               carrier: portador, operation_type: tipo)
      sem_data.update_columns(issue_date: nil, due_date: nil)

      get '/api/v1/structured_operations', headers: headers_a
      expect(response.parsed_body.map { |o| o['id'] }).to include(sem_data.id)

      # Com filtro de período, ela continua fora — o predicado é o mesmo.
      get '/api/v1/structured_operations',
          params: { from: '2026-01-01', to: '2026-12-31' }, headers: headers_a
      expect(response.parsed_body.map { |o| o['id'] }).not_to include(sem_data.id)
    end

    it 'data malformada responde 400, não 500' do
      get '/api/v1/structured_operations', params: { from: 'ontem' }, headers: headers_a
      expect(response).to have_http_status(400)
    end

    it 'chave de ordenação desconhecida responde 400 (OPS-288)' do
      get '/api/v1/structured_operations', params: { ordering_keys: ['drop table'] }, headers: headers_a
      expect(response).to have_http_status(400)
    end

    it 'a chave `company` SAIU da allowlist (B-13 — não há coluna Empresa na tela)' do
      get '/api/v1/structured_operations', params: { ordering_keys: ['company'] }, headers: headers_a
      expect(response).to have_http_status(400)
    end

    it 'ordena pelas chaves da allowlist' do
      get '/api/v1/structured_operations',
          params: { ordering_keys: ['operation_value'], ordering_style: ['up'] }, headers: headers_a
      expect(response).to have_http_status(200)
    end

    it 'X-Total-Count é o total REAL, não o tamanho da página (BE-284)' do
      4.times { create(:structured_operation, project: projeto_a, company: empresa_a, carrier: portador, operation_type: tipo) }

      get '/api/v1/structured_operations', params: { per_page: 2, page: 1 }, headers: headers_a

      expect(response.parsed_body.size).to eq(2)
      expect(response.headers['X-Total-Count']).to eq('5')
    end

    it '`per_page` tem teto — o legado aceitava `l=999999`' do
      get '/api/v1/structured_operations', params: { per_page: 999_999 }, headers: headers_a

      expect(response).to have_http_status(200)
      expect(response.headers['X-Per-Page'].to_i).to be <= 200
    end
  end

  # ====================================================================
  # BE-285 / BE-290 / BE-291 — criação
  # ====================================================================
  describe 'POST /api/v1/structured_operations' do
    let(:corpo) do
      { company_id: empresa_a.id, carrier_id: portador.id, operation_type_id: tipo.id,
        issue_date: '2026-04-01', due_date: '2026-08-01', operation_value: '150000.00',
        original_balance: '50000.00' }
    end

    it 'cria com o autor da SESSÃO e o projeto DERIVADO da empresa' do
      post '/api/v1/structured_operations', params: corpo, headers: headers_a, as: :json

      expect(response).to have_http_status(201)
      corpo_resp = response.parsed_body
      expect(corpo_resp['user_id']).to eq(gerente.id)
      expect(corpo_resp['project_id']).to eq(projeto_a.id)
      # DB-297 — autor e último editor são colunas SEPARADAS.
      expect(corpo_resp['updated_by_id']).to eq(gerente.id)
    end

    it 'BE-290 — `title` em branco recebe o título do portador' do
      post '/api/v1/structured_operations', params: corpo, headers: headers_a, as: :json
      expect(response.parsed_body['title']).to eq('Portador Alfa')
    end

    it 'BE-290 — `carrier_id` inexistente responde 422, não NoMethodError' do
      post '/api/v1/structured_operations', params: corpo.merge(carrier_id: SecureRandom.uuid),
                                            headers: headers_a, as: :json

      expect(response).to have_http_status(422)
      expect(response.parsed_body['message']).to be_present
    end

    it 'DEC-01 — `original_balance` é gravado NEGATIVO, e `balance` o acompanha' do
      post '/api/v1/structured_operations', params: corpo, headers: headers_a, as: :json

      expect(BigDecimal(response.parsed_body['original_balance'])).to eq(BigDecimal('-50000.00'))
      expect(BigDecimal(response.parsed_body['balance'])).to eq(BigDecimal('-50000.00'))
    end

    it 'BE-285 — `:id` no corpo é IGNORADO (mass assignment, família D-60/D-68)' do
      forjado = SecureRandom.uuid
      post '/api/v1/structured_operations', params: corpo.merge(id: forjado, user_id: outro.id),
                                            headers: headers_a, as: :json

      expect(response).to have_http_status(201)
      expect(response.parsed_body['id']).not_to eq(forjado)
      expect(response.parsed_body['user_id']).to eq(gerente.id)
    end

    it 'BE-291 — empresa de OUTRO projeto exige confirmação explícita' do
      post '/api/v1/structured_operations', params: corpo.merge(company_id: empresa_b.id),
                                            headers: headers_a, as: :json

      expect(response).to have_http_status(422)
      expect(response.parsed_body['message']).to include('outro projeto')
      expect(response.parsed_body['code']).to eq('PROJECT_CHANGE_REQUIRES_CONFIRMATION')
    end

    it 'BE-293 — as validações AUSENTES continuam ausentes' do
      # Sem `due_date >= issue_date`, sem `operation_value > 0`, sem faixa de
      # `agreed_rate`, sem unicidade de `contract_number`. Replicar a ausência é
      # a decisão (Q-R7): validar recusaria registro que o sistema aceita hoje.
      post '/api/v1/structured_operations',
           params: corpo.merge(issue_date: '2026-12-01', due_date: '2026-01-01',
                               operation_value: '-5000.00', agreed_rate: '250.0',
                               contract_number: 'CT-0001'),
           headers: headers_a, as: :json

      expect(response).to have_http_status(201)
    end
  end

  # ====================================================================
  # BE-286 / BE-292 / T-D5 — edição
  # ====================================================================
  describe 'PUT /api/v1/structured_operations/:id' do
    # ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b / DEC-115 · fonte:
    # `../sfg/app/controllers/pub/structured_operations_controller.rb:25`. Fonte,
    # não oráculo: a tabela nunca existiu em produção.
    it 'golden E6 — editar SÓ a observação reseta o `balance` (BE-292, T-D6)' do
      op_a.update_columns(original_balance: BigDecimal('-50000.00'), balance: BigDecimal('-12.34'))

      put "/api/v1/structured_operations/#{op_a.id}", params: { observation: 'só um comentário' },
                                                      headers: headers_a, as: :json

      expect(response).to have_http_status(200)
      expect(BigDecimal(response.parsed_body['balance'])).to eq(BigDecimal('-50000.00'))
    end

    it 'T-D5 — as datas são IMUTÁVEIS na edição, no SERVIDOR' do
      put "/api/v1/structured_operations/#{op_a.id}",
          params: { issue_date: '2020-01-01', due_date: '2020-02-01' }, headers: headers_a, as: :json

      expect(response).to have_http_status(200)
      expect(op_a.reload.issue_date).to eq(Date.new(2026, 3, 1))
      expect(op_a.due_date).to eq(Date.new(2026, 6, 30))
    end

    it 'DB-297 — o último editor muda, o AUTOR não' do
      colega = create(:user, user_type: UserType.gerente)
      Membership.create!(project: projeto_a, user: colega, role: 'participante')

      put "/api/v1/structured_operations/#{op_a.id}", params: { title: 'Renomeada' },
                                                      headers: auth_headers(colega, project: projeto_a),
                                                      as: :json

      expect(response).to have_http_status(200)
      expect(op_a.reload.user_id).to eq(op_a.user_id)
      expect(op_a.updated_by_id).to eq(colega.id)
    end
  end

  # ====================================================================
  # BE-287 — exclusão bloqueada responde 422 DE VERDADE
  # ====================================================================
  describe 'DELETE /api/v1/structured_operations/:id' do
    it 'exclui a operação livre' do
      delete "/api/v1/structured_operations/#{op_a.id}", headers: headers_a

      expect(response).to have_http_status(200)
      expect(StructuredOperation.exists?(op_a.id)).to be(false)
    end

    it 'com recibo emitido responde 422, e a operação CONTINUA lá (BE-287)' do
      # No legado o ternário `errors.any? ? :ok : :ok` respondia 200: o front
      # tratava como sucesso, recarregava a lista e a operação estava lá.
      cobranca = create(:charge, project: projeto_a)
      recibo = Receipt.create!(project: projeto_a, charge: cobranca, operation: op_a,
                               remuneration: create(:remuneration, project: projeto_a, operation_type: tipo),
                               kind: Receipt::KIND_STRUCTURED, title: 'Recibo', fee: BigDecimal('2.55'),
                               operation_value: op_a.operation_value, value: BigDecimal('5100.00'),
                               user_id: gerente.id)
      op_a.update_column(:receipt_id, recibo.id)

      delete "/api/v1/structured_operations/#{op_a.id}", headers: headers_a

      expect(response).to have_http_status(422)
      expect(StructuredOperation.exists?(op_a.id)).to be(true)
    end
  end

  # ====================================================================
  # BE-294 (5.5) — o ciclo completo do `available_for_receipt`
  # ====================================================================
  describe 'o vínculo com o recibo, ida e volta' do
    it 'entrar no lote grava `receipt_id`; sair do lote LIMPA' do
      tipo_ = tipo
      create(:remuneration, project: projeto_a, operation_type: tipo_, value: BigDecimal('2.55'))
      cobranca = create(:charge, project: projeto_a)

      get "/api/v1/charges/#{cobranca.id}/receipts", headers: headers_a
      temp_id = response.parsed_body.find { |c| c['operation_id'] == op_a.id }['temp_id']

      # Ida — a operação sai de `available_for_receipt`.
      put "/api/v1/charges/#{cobranca.id}/receipts", params: { temp_ids: [temp_id] },
                                                     headers: headers_a, as: :json
      expect(response).to have_http_status(200)
      expect(op_a.reload.receipt_id).to be_present
      expect(StructuredOperation.available_for_receipt).not_to include(op_a)

      # Volta — a lista enviada é o estado FINAL: o que não está nela é
      # removido, e o `receipt_id` do outro lado volta a ser nulo.
      put "/api/v1/charges/#{cobranca.id}/receipts", params: { temp_ids: [] },
                                                     headers: headers_a, as: :json
      expect(response).to have_http_status(200)
      expect(op_a.reload.receipt_id).to be_nil
      expect(StructuredOperation.available_for_receipt).to include(op_a)
    end
  end

  # ====================================================================
  # OPS-284 — os textos de ajuda
  # ====================================================================
  describe 'GET /api/v1/structured_operations/help_texts' do
    it 'responde 200 e nasce VAZIO (Q-R9 — as 13 chaves do legado são o mesmo placeholder)' do
      get '/api/v1/structured_operations/help_texts', headers: headers_a

      expect(response).to have_http_status(200)
      expect(response.parsed_body).to eq({})
    end

    it 'arquivo ausente devolve `{}` em vez de 500 — o defeito do legado' do
      # No legado o helper fazia `YAML.load_file` a cada campo renderizado; se o
      # arquivo sumisse do deploy, o formulário inteiro respondia 500.
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(Rails.root.join(Structured::HelpTexts::CONFIG_PATH))
                                     .and_return(false)
      Structured::HelpTexts.reload!

      get '/api/v1/structured_operations/help_texts', headers: headers_a
      expect(response).to have_http_status(200)
    end

    it 'a rota não é engolida pelo `GET /:id`' do
      # `help_texts` é declarada ANTES de `get ":id"`; invertida a ordem, o
      # `:id` a capturaria e o endpoint responderia 404 para sempre.
      get '/api/v1/structured_operations/help_texts', headers: headers_a
      expect(response).to have_http_status(200)
      expect(response.parsed_body).to be_a(Hash)
    end
  end

  # ====================================================================
  # C3 — os DOIS lados, e o gate de somente leitura (tarefas 12.7 e 8.2)
  # ====================================================================
  describe 'autorização' do
    def grant_readonly!(user)
      UserPermission.create!(user: user, permission: Permission.find_by(key: 'user_is_readonly'),
                             source: 'manual', granted_at: Time.current)
    end

    # **A matriz é a fonte da verdade, e ela diz `CRUD` nas quatro colunas para
    # `structured_operations`** (`authorization-matrix.md`, grupo "Gestão").
    # Escrevi este exemplo esperando 403 para o Colaborador e ele devolveu 201 —
    # a expectativa é que estava errada, não o servidor. A operação estruturada
    # é trabalho de operação, não de administração; quem separa os lados nesta
    # unidade é o CATÁLOGO (`structured_operation_types`, `CRUD CRUD CRUD R`),
    # testado no spec dele.
    it 'o Colaborador ESCREVE operação estruturada — é o que a matriz diz (DEC-18)' do
      colaborador = create(:user, user_type: UserType.colaborador)
      Membership.create!(project: projeto_a, user: colaborador, role: 'participante')

      post '/api/v1/structured_operations',
           params: { company_id: empresa_a.id, carrier_id: portador.id, operation_type_id: tipo.id,
                     issue_date: '2026-04-01', due_date: '2026-08-01', operation_value: '1000.00' },
           headers: auth_headers(colaborador, project: projeto_a), as: :json

      expect(response).to have_http_status(201)
    end

    it 'e o Colaborador NÃO escreve no CATÁLOGO da mesma unidade — o outro lado (C3)' do
      colaborador = create(:user, user_type: UserType.colaborador)

      post '/api/v1/structured_operation_types', params: { title: 'Forjado' },
                                                 headers: auth_headers(colaborador), as: :json

      expect(response).to have_http_status(403)
      expect(response.parsed_body['code']).to eq('ROLE_REQUIRED')
    end

    it '8.2 — `user_is_readonly` bloqueia a escrita NO SERVIDOR, e deixa a leitura passar' do
      grant_readonly!(gerente)

      post '/api/v1/structured_operations',
           params: { company_id: empresa_a.id, carrier_id: portador.id, operation_type_id: tipo.id,
                     issue_date: '2026-04-01', due_date: '2026-08-01', operation_value: '1000.00' },
           headers: headers_a, as: :json
      expect(response).to have_http_status(403)
      expect(response.parsed_body['code']).to eq('READONLY_RESTRICTED')

      put "/api/v1/structured_operations/#{op_a.id}", params: { title: 'X' }, headers: headers_a, as: :json
      expect(response).to have_http_status(403)

      delete "/api/v1/structured_operations/#{op_a.id}", headers: headers_a
      expect(response).to have_http_status(403)

      get '/api/v1/structured_operations', headers: headers_a
      expect(response).to have_http_status(200)
    end
  end
end
