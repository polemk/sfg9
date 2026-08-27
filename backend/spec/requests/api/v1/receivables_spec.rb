# frozen_string_literal: true

require 'rails_helper'

# S6 — **os contratos transversais do borderô**, provados pela API.
#
# Fecha as tarefas 4.29 a 4.35 e a parte de endpoint de `BE-150`…`BE-153`.
#
# Os goldens de fórmula estão em `spec/services/receivables/calculator_spec.rb`,
# alimentados pelas 28.131 linhas de produção. Aqui o que se prova é diferente:
# que **o caminho HTTP inteiro** honra C1, C2 e as guardas de D-10 — porque
# fórmula certa atrás de endpoint que vaza tenant não serve de nada.
RSpec.describe 'API V1 Receivables', type: :request do
  let(:og) { create(:user, :og) }
  let(:project) { create_project_with_owner(og) }
  let(:outro_projeto) { create_project_with_owner(og) }

  let(:company) { create(:company, project: project) }
  let(:carrier) { create(:carrier) }
  let(:wallet) { create(:wallet) }
  let(:receivable_kind) { create(:receivable_kind) }
  let(:resource_source) { create(:resource_source) }
  let!(:desagio) { create(:movement_kind, :desagio) }
  let!(:iof) { create(:movement_kind, :iof) }
  # A tarifa SEM classificador — em produção é "Outras Despesas". É ela que
  # alimenta o bucket `tarifas_outras`, o resto da subtração.
  let!(:outras) { create(:movement_kind, title: 'Outras Despesas') }
  let!(:aliquota) { create(:iof_rate) }

  let(:headers) { auth_headers(og, project: project) }

  before { create(:project_to_carrier_connection, project: project, carrier: carrier) }

  def payload(**over)
    {
      date: '2024-05-10',
      company_id: company.id, carrier_id: carrier.id, wallet_id: wallet.id,
      receivable_kind_id: receivable_kind.id, resource_source_id: resource_source.id,
      valor_bruto: '149208.24', qtd_titulos: 4,
      prz_med_pond_emp: '42', prz_med_pond_bco: '42', float_acordado: '2',
      cst_efetivo_acordado: '2.05',
      # As DUAS tarifas do borderô 19086 de produção: deságio 4.331,19 e
      # outras 67,50. Total 4.398,69 — é o que fecha o líquido em 144.809,55.
      taxes: [{ movement_kind_id: desagio.id, value: '4331.19' },
              { movement_kind_id: outras.id, value: '67.50' }]
    }.merge(over)
  end

  # ====================================================================
  # 4.29 — C2: a prévia e a gravação passam pelo MESMO serviço
  # ====================================================================
  describe 'C2 — POST /receivables/preview × POST /receivables' do
    it 'devolve os MESMOS derivados, campo a campo, para o mesmo payload' do
      # É o teste que fecha o **D-09** na raiz. No legado a prévia era uma
      # reimplementação parcial da fórmula em JavaScript
      # (`receivables/new/_body.js.erb:339-504`) que não calculava
      # `taxa_desconto_nominal_*`, `custo_efetivo_com_float_*`,
      # `multiplicador_*` nem os `*_percent`: o usuário via um número na tela e
      # outro depois de salvar, e não havia como dizer qual estava certo.
      #
      # Divergência de UM único campo reprova este exemplo.
      post '/api/v1/receivables/preview', params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      previa = response.parsed_body

      post '/api/v1/receivables', params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:created)
      gravado = response.parsed_body['derived']

      expect(gravado.keys.sort).to eq(previa.keys.sort)
      previa.each do |campo, valor_previsto|
        expect(BigDecimal(gravado[campo].to_s)).to eq(BigDecimal(valor_previsto.to_s)) if valor_previsto.is_a?(Numeric)
        expect(gravado[campo]).to eq(valor_previsto) unless valor_previsto.is_a?(Numeric)
      end
    end

    it 'a prévia NÃO persiste nada' do
      expect { post '/api/v1/receivables/preview', params: payload, headers: headers, as: :json }
        .not_to(change { ReceivableEntry.count })
      expect(ReceivableTax.count).to eq(0)
    end

    it 'a prévia reproduz o borderô 19086 de PRODUÇÃO, número a número' do
      # A mesma linha que abre o golden do calculador. Aqui ela atravessa
      # Grape, `declared`, o cast de `BigDecimal` do params e o entity — e
      # continua batendo. É o caminho inteiro, não só a fórmula.
      post '/api/v1/receivables/preview', params: payload, headers: headers, as: :json

      derivados = response.parsed_body
      expect(BigDecimal(derivados['valor_liquido'])).to eq(BigDecimal('144809.55'))
      expect(BigDecimal(derivados['checagem_iof'])).to eq(BigDecimal('800.01'))
      expect(BigDecimal(derivados['custo_efetivo_pz_med_emp'])).to eq(BigDecimal('2.0612'))
      expect(BigDecimal(derivados['custo_efetivo_sem_float'])).to eq(BigDecimal('2.1604'))
      expect(BigDecimal(derivados['calc_valor_liq_correto'])).to eq(BigDecimal('144765.91'))
      expect(derivados['status']).to eq('ok')
      expect(derivados['status_label']).to eq('OK')
      # A guarda `tarifas_iof < 1` dispara: sem IOF, as duas variantes são nulas.
      expect(derivados['taxa_desconto_nominal_despesas_bancos']).to be_nil
      expect(derivados['custo_efetivo_com_float_sem_iof']).to be_nil
    end
  end

  # ====================================================================
  # 4.30 — C1: a suíte cross-project
  # ====================================================================
  describe 'C1 — escopo por projeto (família D-01/D-16/D-29/D-76/D-100)' do
    let!(:alheio) do
      create(:receivable_entry, project: outro_projeto,
                                company: create(:company, project: outro_projeto))
    end
    let!(:meu) { create(:receivable_entry, project: project, company: company, carrier: carrier) }

    it 'a lista NÃO traz borderô de outro projeto' do
      get '/api/v1/receivables', headers: headers
      expect(response.parsed_body.map { |r| r['id'] }).to eq([meu.id])
    end

    it '`receivable_id` de outro projeto devolve VAZIO — nunca a lista inteira' do
      # No legado, quando chegava um id por parâmetro, a query era SUBSTITUÍDA
      # por `ReceivableEntry.where(id: ...)` e o filtro de projeto sumia
      # (D-16). Aqui o filtro é aplicado DENTRO do escopo.
      get '/api/v1/receivables', params: { receivable_id: alheio.id }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it 'id malformado devolve VAZIO, não 500' do
      get '/api/v1/receivables', params: { receivable_id: 'nao-e-uuid' }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([])
    end

    it 'GET de id alheio responde EXATAMENTE como id inexistente' do
      # Distinguir 403 de 404 transformaria o endpoint num oráculo de
      # existência de ids: um Colaborador enumeraria os borderôs alheios pela
      # diferença de status.
      get "/api/v1/receivables/#{alheio.id}", headers: headers
      alheio_status = response.status
      alheio_corpo = response.parsed_body

      get "/api/v1/receivables/#{SecureRandom.uuid}", headers: headers
      expect(response.status).to eq(alheio_status)
      expect(response.parsed_body).to eq(alheio_corpo)
      expect(response).to have_http_status(:not_found)
    end

    it 'PUT em borderô de outro projeto responde 404 e NÃO altera nada' do
      expect {
        put "/api/v1/receivables/#{alheio.id}", params: { description: 'invadido' }, headers: headers, as: :json
      }.not_to(change { alheio.reload.description })
      expect(response).to have_http_status(:not_found)
    end

    it 'DELETE em borderô de outro projeto é recusado e NADA é apagado' do
      expect { delete "/api/v1/receivables/#{alheio.id}", headers: headers }
        .not_to(change { ReceivableEntry.count })
      expect(response).to have_http_status(:not_found)
    end

    it 'nenhum model do domínio tem `default_scope`' do
      # O escopo é aplicado no ENDPOINT, sempre visível. `default_scope` vaza
      # para `unscoped`, quebra `joins` em silêncio e contamina job e seed.
      [ReceivableEntry, ReceivableTax, Charge, Receipt].each do |model|
        expect(model.default_scopes).to be_empty, "#{model} não pode ter default_scope (C1)"
      end
      expect(ReceivableEntry.project_scoped?).to be(true)
    end
  end

  # ====================================================================
  # 4.31 — paginação e ordenação REAIS (D-20)
  # ====================================================================
  describe 'paginação e ordenação (D-20)' do
    before do
      # 120 borderôs: o suficiente para a última página não ser a segunda.
      120.times do |i|
        create(:receivable_entry, project: project, company: company, carrier: carrier,
                                  wallet: wallet, date: Date.new(2024, 1, 1) + i.days)
      end
    end

    it 'respeita `page`/`per_page` e emite os cabeçalhos que o `PaginationPill` lê' do
      get '/api/v1/receivables', params: { page: 2, per_page: 50 }, headers: headers

      expect(response.parsed_body.size).to eq(50)
      expect(response.headers['X-Total-Count']).to eq('120')
      expect(response.headers['X-Page']).to eq('2')
      expect(response.headers['X-Per-Page']).to eq('50')
      expect(response.headers['X-Total-Pages']).to eq('3')
    end

    it 'a ÚLTIMA página aponta para o lugar certo' do
      # No legado a última página ia para o lugar errado porque `limit`/`offset`
      # eram lidos e descartados: o cliente calculava a paginação sobre uma
      # lista que o servidor mandava inteira.
      get '/api/v1/receivables', params: { page: 3, per_page: 50 }, headers: headers
      expect(response.parsed_body.size).to eq(20)
    end

    it 'chave de ordenação desconhecida é IGNORADA, não 500' do
      # `?ordering_keys[]=x` na barra de endereço bastava para derrubar o
      # request no legado: `get_ordering_key` devolvia `nil` e a linha seguinte
      # fazia `nil + " "`.
      get '/api/v1/receivables', params: { ordering_keys: ['drop table'], ordering_style: ['up'] },
                                 headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.size).to eq(20)
    end

    it 'ordena pelas chaves do legado' do
      get '/api/v1/receivables', params: { ordering_keys: ['date'], ordering_style: ['up'], per_page: 5 },
                                 headers: headers
      datas = response.parsed_body.map { |r| r['date'] }
      expect(datas).to eq(datas.sort)
    end

    it 'o resumo soma a consulta INTEIRA, não a página' do
      get '/api/v1/receivables/summary', headers: headers
      expect(response.parsed_body['count']).to eq(120)
    end
  end

  # ====================================================================
  # 4.32 — sanitização da busca (OPS-157)
  # ====================================================================
  describe 'busca (OPS-157)' do
    let!(:cem_por_cento) { create(:carrier, title: 'Banco 100% Digital') }
    let!(:outro) { create(:carrier, title: 'Banco Comum') }

    before do
      create(:project_to_carrier_connection, project: project, carrier: cem_por_cento)
      create(:project_to_carrier_connection, project: project, carrier: outro)
      create(:receivable_entry, project: project, company: company, carrier: cem_por_cento)
      create(:receivable_entry, project: project, company: company, carrier: outro)
    end

    it '`%` no termo casa como LITERAL e não devolve a base inteira' do
      # No legado o fragmento SQL era interpolado na string do `where`: `%`
      # virava curinga e `100%` devolvia tudo.
      get '/api/v1/receivables', params: { q: '100%' }, headers: headers
      expect(response.parsed_body.size).to eq(1)
      expect(response.parsed_body.first['carrier_title']).to eq('Banco 100% Digital')
    end

    it '`_` no termo também é literal' do
      get '/api/v1/receivables', params: { q: 'Banco_' }, headers: headers
      expect(response.parsed_body).to eq([])
    end
  end

  # ====================================================================
  # 4.33 — transação e recálculo ÚNICO (D-11)
  # ====================================================================
  describe 'transação (D-11)' do
    it 'grava borderô e tarifas juntos, com os buckets já preenchidos' do
      post '/api/v1/receivables', params: payload, headers: headers, as: :json

      entry = ReceivableEntry.last
      expect(entry.taxes.count).to eq(2)
      # O ponto do D-11: no legado o primeiro `save` calculava **sem nenhuma
      # tarifa** e a operação de risco nascia com esse líquido.
      expect(entry.tarifas_desagio).to eq(BigDecimal('4331.19'))
      expect(entry.valor_liquido).to eq(BigDecimal('144809.55'))
    end

    it 'falha ao gravar uma tarifa DESFAZ o borderô inteiro' do
      # No legado o `save` da tarifa não era checado
      # (`receivables_controller.rb:85`): a tarifa era descartada em silêncio e
      # o borderô ficava gravado com o total errado.
      corpo = payload(taxes: [{ movement_kind_id: desagio.id, value: '10.00' },
                              { movement_kind_id: SecureRandom.uuid, value: '10.00' }])

      expect { post '/api/v1/receivables', params: corpo, headers: headers, as: :json }
        .not_to(change { ReceivableEntry.count })
      expect(ReceivableTax.count).to eq(0)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'a edição recalcula os buckets quando a lista de tarifas muda (DEC-72)' do
      post '/api/v1/receivables', params: payload, headers: headers, as: :json
      entry = ReceivableEntry.last
      tarifa = entry.taxes.first

      # A tela manda o estado FINAL: a tarifa de deságio sai, entra uma de IOF.
      put "/api/v1/receivables/#{entry.id}",
          params: { taxes: [{ movement_kind_id: iof.id, value: '500.00' }] },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      entry.reload
      expect(ReceivableTax.exists?(tarifa.id)).to be(false)
      expect(entry.taxes.count).to eq(1)
      expect(entry.tarifas_desagio).to eq(0)
      expect(entry.tarifas_iof).to eq(BigDecimal('500.00'))
    end

    it 'payload SEM a chave `taxes` PRESERVA as tarifas existentes' do
      post '/api/v1/receivables', params: payload, headers: headers, as: :json
      entry = ReceivableEntry.last

      put "/api/v1/receivables/#{entry.id}", params: { description: 'só a descrição' },
                                             headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(entry.reload.taxes.count).to eq(2)
      expect(entry.tarifas_desagio).to eq(BigDecimal('4331.19'))
    end
  end

  # ====================================================================
  # 4.35 — nenhuma entrada consegue gravar Infinity/NaN (D-10)
  # ====================================================================
  describe 'D-10 — Infinity e NaN são recusados no SERVIDOR' do
    # Em produção há **30 borderôs com `NaN` gravado** em coluna de dinheiro,
    # porque no legado a única guarda existia no JavaScript da tela e o cálculo
    # rodava num `before_validation`, antes de qualquer validação.
    #
    # O DEC-02 manda replicar o float, mas exclui explicitamente o D-10:
    # *"isso não é precisão, é registro corrompido"*.
    combinacoes = {
      'prazo da empresa zerado' => { prz_med_pond_emp: '0' },
      'prazo do banco zerado' => { prz_med_pond_bco: '0' },
      'prazo negativo' => { prz_med_pond_emp: '-5' },
      'custo efetivo acordado abaixo de -100%' => { cst_efetivo_acordado: '-150' }
    }

    combinacoes.each do |nome, over|
      it "recusa com 422: #{nome}" do
        post '/api/v1/receivables', params: payload(**over), headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(ReceivableEntry.count).to eq(0)
      end

      it "a PRÉVIA recusa pelo MESMO motivo: #{nome}" do
        # A tela trava e o servidor responde 422 pela mesma razão — é o que
        # impede a tela de ser a única defesa.
        post '/api/v1/receivables/preview', params: payload(**over), headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it 'recusa líquido ZERO — o divisor de quatro fórmulas' do
      corpo = payload(valor_bruto: '1000.00', taxes: [{ movement_kind_id: desagio.id, value: '1000.00' }])
      post '/api/v1/receivables', params: corpo, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('líquido')
    end

    it 'nenhuma coluna do banco fica com Infinity ou NaN depois de uma bateria de payloads' do
      [payload, payload(vlr_bruto_recusado: '149208.24', valor_bruto: '149208.25'),
       payload(recompra: '999999.99'), payload(float_acordado: '0'),
       payload(cst_efetivo_acordado: '0')].each do |corpo|
        post '/api/v1/receivables', params: corpo, headers: headers, as: :json
      end

      ReceivableEntry.find_each do |entry|
        (ReceivableEntry::DERIVED_COLUMNS + ReceivableEntry::INPUT_COLUMNS).each do |coluna|
          valor = entry.public_send(coluna)
          expect(Receivables::InputGuard.nonfinite?(valor)).to be(false),
                                                              "#{coluna} = #{valor.inspect} no borderô #{entry.id}"
        end
      end
    end

    it 'o model recusa mesmo quando alguém escreve NaN direto, sem passar pelo serviço' do
      # Foi por um caminho assim que os 30 registros de produção entraram: não
      # pela tela.
      entry = build(:receivable_entry, project: project, company: company, carrier: carrier)
      entry.valor_liquido = BigDecimal('NaN')
      expect(entry).not_to be_valid
      expect(entry.errors[:base].join).to include('indeterminado')
    end
  end

  # ====================================================================
  # 4.34 — autorização NO SERVIDOR (D-17 / D-24)
  # ====================================================================
  describe 'autorização no servidor (D-17, D-24)' do
    let(:colaborador) { create(:user, :colaborador) }

    before { Membership.create!(project: project, user: colaborador, role: 'participante') }

    it 'usuário SEM participação no projeto responde 404 — igual a projeto inexistente' do
      estranho = create(:user, :colaborador)
      get '/api/v1/receivables', headers: auth_headers(estranho, project: project)
      expect(response).to have_http_status(:not_found)
    end

    it 'somente-leitura NÃO cria, mesmo chamando a API direto' do
      # Esconder o botão nunca foi autorização. No legado o gate era de view
      # (D-17) e a requisição fora da tela fazia tudo (D-34).
      permissao = Permission.find_or_create_by!(key: 'user_is_readonly') { |p| p.title = 'Somente leitura' }
      UserPermission.create!(user: colaborador, permission: permissao, granted_at: Time.current, source: 'manual')

      post '/api/v1/receivables', params: payload, headers: auth_headers(colaborador, project: project), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('READONLY_RESTRICTED')
      expect(ReceivableEntry.count).to eq(0)
    end

    it 'exclusão bloqueada responde ERRO, nunca `:ok`' do
      # No legado os DOIS ramos do ternário respondiam `:ok` (D-24), e a tela
      # dizia "removido com sucesso" sem ter removido.
      entry = create(:receivable_entry, project: project, company: company, carrier: carrier)
      allow_any_instance_of(ReceivableEntry).to receive(:destroy).and_return(false)

      delete "/api/v1/receivables/#{entry.id}", headers: headers
      expect(response).not_to have_http_status(:ok)
      expect(ReceivableEntry.exists?(entry.id)).to be(true)
    end

    it 'sem credencial nenhuma responde 401' do
      get '/api/v1/receivables'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ====================================================================
  # BE-181 — a validação de limite ativo. NUNCA EXECUTADO EM PRODUÇÃO.
  # ====================================================================
  describe 'BE-181 — recebível exige limite de risco ativo' do
    # ⚠ **NUNCA EXECUTADO EM PRODUÇÃO** (DEC-103b). Esta regra depende de
    # `receivable_entries.risk_operation_subtype_id`, coluna criada por
    # `20220610122917_add_risk_operation_type_to_receivable_entries` — uma das
    # 24 migrations que nunca subiram. O `COPY` de `receivable_entries` no dump
    # de 31/05/2025 tem 68 colunas e **nenhuma das duas** está lá.
    #
    # Fonte da regra: `../sfg/app/models/receivable_entry.rb:27-36`.
    let(:tipo) { create(:risk_operation_type) }
    let(:subtipo) { tipo.reload.subtypes.first }

    # **Acrescentado pela S7 (26/08/2026), e é lacuna de fixture, não de regra.**
    # Desde que a S7 entregou o `after_create` de `RiskOperation` (`BE-264`), a
    # operação criada pelo borderô de tipo SEM pré-faturamento lança o movimento
    # "Liberação do Recurso" — resolvido por `integration_key` (B-09). Esses
    # tipos são **dado de referência**: em produção `rake reference:seed` os
    # garante. Sem semeá-los aqui, o exemplo exercitava um ambiente que não
    # existe e respondia 422/500 por falta de catálogo, não por falta de limite.
    before { Seeds::Reference::RiskMovementTypes.call! }

    it 'recusa quando NÃO há limite ativo para (empresa, portador, tipo)' do
      post '/api/v1/receivables', params: payload(risk_operation_subtype_id: subtipo.id),
                                  headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('limite de risco ativo')
    end

    it 'aceita quando o limite existe e está ativo, e DERIVA o tipo do subtipo' do
      create(:risk_control, project: project, company: company, carrier: carrier,
                            risk_operation_type: tipo, is_active: true)

      post '/api/v1/receivables', params: payload(risk_operation_subtype_id: subtipo.id),
                                  headers: headers, as: :json

      expect(response).to have_http_status(:created)
      # `risk_operation_type_id` NÃO vem do corpo: é derivado do subtipo.
      expect(ReceivableEntry.last.risk_operation_type_id).to eq(tipo.id)
    end

    it 'operação estática ausente responde 422 com a frase, NUNCA 500' do
      # `RiskSyncService` **levanta de propósito** para desfazer a transação —
      # o legado seguia em silêncio (`unless static_op.nil?`) e o borderô ficava
      # gravado sem a liberação de recurso. Mas `RecordInvalid` subindo até o
      # endpoint cai no `rescue_from StandardError` local (que existe para não
      # vazar backtrace) e viraria **"o servidor quebrou"**, quando o que houve
      # foi uma regra recusando.
      #
      # ⚠ NUNCA EXECUTADO EM PRODUÇÃO (DEC-103b).
      tipo_pre = create(:risk_operation_type, :com_pre)
      subtipo_pre = tipo_pre.reload.subtypes.find(&:is_pre)
      create(:risk_control, project: project, company: company, carrier: carrier,
                            risk_operation_type: tipo_pre, is_active: true)
      # O par estático nasce com o limite; apagá-lo reproduz a inconsistência.
      RiskOperation.where(risk_control_id: RiskControl.last.id, is_static: true).delete_all

      expect {
        post '/api/v1/receivables', params: payload(risk_operation_subtype_id: subtipo_pre.id),
                                    headers: headers, as: :json
      }.not_to(change { ReceivableEntry.count })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('operação estática')
    end

    it 'recusa quando o limite existe mas está DESATIVADO' do
      create(:risk_control, project: project, company: company, carrier: carrier,
                            risk_operation_type: tipo, is_active: false)

      post '/api/v1/receivables', params: payload(risk_operation_subtype_id: subtipo.id),
                                  headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ====================================================================
  # BE-182 — o autor vem da SESSÃO
  # ====================================================================
  describe 'BE-182 — autor e marca do projeto' do
    it 'ignora o `user_id` do corpo e usa o da sessão' do
      intruso = create(:user, :colaborador)
      post '/api/v1/receivables', params: payload(user_id: intruso.id), headers: headers, as: :json

      expect(ReceivableEntry.last.user_id).to eq(og.id)
    end

    it 'carimba `has_safegold_management` a partir do projeto' do
      post '/api/v1/receivables', params: payload, headers: headers, as: :json
      expect(ReceivableEntry.last.has_safegold_management).to eq(project.has_safegold_management || false)
    end

    it 'recusa empresa de OUTRO projeto no corpo' do
      alheia = create(:company, project: outro_projeto)
      post '/api/v1/receivables', params: payload(company_id: alheia.id), headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Empresa não encontrada neste projeto')
    end

    it 'recusa portador NÃO conectado ao projeto' do
      # **Um critério só** para portador oferecível — o mesmo que a tela usa
      # (`ProjectToCarrierConnection.for_project`). Ter dois critérios foi o que
      # fez a tela do legado oferecer portador que o servidor recusava.
      solto = create(:carrier)
      post '/api/v1/receivables', params: payload(carrier_id: solto.id), headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to include('Portador não conectado')
    end
  end

  # ====================================================================
  # DEC-52 — `observacoes` passa a ter tela
  # ====================================================================
  describe 'DEC-52 — `observacoes`' do
    it 'aceita e devolve o campo' do
      # A tarefa 1.5 / Q-B18 dizia "migrar sem tela". A **DEC-52 venceu**: o
      # campo ganha input e exibição, porque há 379 textos de negócio em
      # produção, vindos do importador Django, que ninguém nunca viu.
      post '/api/v1/receivables', params: payload(observacoes: 'Cliente pediu prorrogação de 5 dias.'),
                                  headers: headers, as: :json

      expect(response.parsed_body['observacoes']).to eq('Cliente pediu prorrogação de 5 dias.')
    end
  end
end
