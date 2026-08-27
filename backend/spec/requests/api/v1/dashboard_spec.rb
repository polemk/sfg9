# frozen_string_literal: true

require 'rails_helper'

# S15 / **NEW-002** e **NEW-001 (parte 2)** — o painel da tela inicial.
#
# > **Feature NOVA (DEC-21), não paridade.** Não existe no legado e o QA do
# > Phase 4 **não deve procurá-la lá** (`DB-399`, `dropped`: o `dash` legado é
# > uma tela vazia). No `parity-ledger.md` entra como `new`.
#
# Os três grupos abaixo são exatamente os três riscos do `design.md`:
#
# 1. **a segunda implementação da fórmula (D-09)** — cada cartão é comparado,
#    valor a valor, com o serviço de domínio que a tela de detalhe consome;
# 2. **o agregado sem escopo (D-110)** — dois projetos, dois números; projeto
#    sem participação, nenhum número;
# 3. **o cartão zerado por falta de permissão** — ele **some**, e some sem
#    virar zero.
RSpec.describe 'API V1 Dashboard', type: :request do
  before do
    UserType.seed_default_types!
    Seeds::Reference::Permissions.call!
  end

  let(:gerente) { create(:user, user_type: UserType.gerente) }
  let(:estranho) { create(:user, user_type: UserType.gerente) }
  let(:somente_leitura) { create(:user, user_type: UserType.colaborador) }

  let!(:projeto_a) { create_project_with_owner(gerente, slug: 'dash-a', name: 'Painel A') }
  let!(:projeto_b) { create_project_with_owner(gerente, slug: 'dash-b', name: 'Painel B') }
  let!(:projeto_alheio) { create_project_with_owner(estranho, slug: 'dash-x', name: 'Painel alheio') }

  let(:hoje) { Date.new(2026, 6, 15) }

  def corpo
    JSON.parse(response.body)
  end

  def cartao(chave)
    corpo['cards'].find { |c| c['key'] == chave }
  end

  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/dashboard/summary' do
    # Um borderô em cada projeto, com valores diferentes: é o que faz o teste de
    # escopo poder falhar. Dois projetos com o mesmo número não provam nada.
    let!(:bordero_a) do
      create(:receivable_entry, project: projeto_a, date: Date.new(2026, 5, 10), valor_bruto: BigDecimal('50000.00'))
    end
    let!(:bordero_b) do
      create(:receivable_entry, project: projeto_b, date: Date.new(2026, 5, 10), valor_bruto: BigDecimal('12345.00'))
    end

    it 'devolve os quatro cartões, a série e o período' do
      get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                       headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(corpo['cards'].map { |c| c['key'] }).to contain_exactly(
        'total_operado', 'exposicao', 'limites_no_teto', 'renegociacoes_em_atraso'
      )
      expect(corpo['date']).to eq(hoje.to_s)
      expect(corpo['period']).to eq('from' => '2025-07-01', 'to' => '2026-06-30')
      expect(corpo['series']['labels'].size).to eq(12)
    end

    # === 5.1 — o teste que impede a segunda implementação da fórmula =========
    #
    # Não confere "um número plausível": confere **o mesmo objeto** que a tela de
    # detalhe recebe. Se alguém escrever um `SUM` dentro do endpoint, este
    # exemplo continua passando enquanto as duas contas concordarem — e falha no
    # dia em que divergirem, que é exatamente o dia em que o D-09 nasce.
    describe 'contrato C2 — o número é o do serviço de domínio' do
      it 'total operado == Receivables::SearchService.totals do mesmo período' do
        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        janela = Dashboard::SummaryService.window_for(hoje, Dashboard::SummaryService::DEFAULT_MONTHS)
        esperado = Receivables::SearchService.totals(
          projeto_a, { date_from: janela[:from], date_to: janela[:to] }
        )[:valor_bruto]

        expect(BigDecimal(cartao('total_operado')['value'].to_s)).to eq(esperado)
      end

      it 'exposição == a soma dos `util` que o console de risco mostra' do
        control = create(:risk_control, project: projeto_a, limite: 100_000)
        # **Medido, não deduzido:** o saldo da operação nasce em
        # `operation_value − original_balance` (a "Liberação do Recurso" da S7
        # entra como movimento de `operation_value` sobre `original_balance`), e
        # `limite_utilizado_on` é `saldo × (−1)`. Então quem produz utilização
        # positiva é o **capital original**, com liberação zero. Com os padrões
        # da factory (100.000 e 100.000) o exemplo mediria zero contra zero.
        create(:risk_operation, risk_control: control, issue_date: Date.new(2026, 1, 1),
                                due_date: Date.new(2026, 12, 31), original_balance: 30_000,
                                operation_value: 0)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        esperado = Risk::AggregateService.total_limits_on(projeto_a, hoje)[:limits].sum { |l| l[:util] }
        expect(cartao('exposicao')['value'].to_d).to eq(esperado.to_d)
      end

      it 'limites no teto == quantos limites têm disponível negativo (o semáforo FE-238)' do
        # 90.000 utilizados sobre um limite de 10.000: disponível −80.000, que é
        # o caso que o semáforo pinta com o token negativo.
        control = create(:risk_control, project: projeto_a, limite: 10_000)
        create(:risk_operation, risk_control: control, issue_date: Date.new(2026, 1, 1),
                                due_date: Date.new(2026, 12, 31), original_balance: 90_000,
                                operation_value: 0)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        esperado = Risk::AggregateService.active_controls(projeto_a).count do |c|
          Risk::Calculator.limite_disponivel_on(c, hoje).negative?
        end
        expect(cartao('limites_no_teto')['value']).to eq(esperado)
        expect(esperado).to eq(1) # o exemplo precisa medir algo, não só concordar consigo
      end

      it 'renegociações em atraso == quantas têm ao menos uma parcela vencida' do
        reneg = create(:renegotiation, project: projeto_a)
        create(:renegotiation_installment, renegotiation: reneg, due_date: Date.new(2026, 1, 10))
        create(:renegotiation, project: projeto_a) # sem parcela: não conta

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        esperado = Renegotiations::AggregateService.overdue_renegotiations_count(
          Renegotiation.for_project(projeto_a), today: hoje
        )
        expect(cartao('renegociacoes_em_atraso')['value']).to eq(esperado)
        expect(esperado).to eq(1)
      end
    end

    # === DEC-116 — dois indicadores, não um ================================
    #
    # O cartão contava só o que **estourou** (`disponivel < 0`), e um limite a
    # 98% do teto não entrava. "No teto" lê como "chegou", não como "passou".
    describe 'DEC-116 — o teto e a zona de perigo' do
      # Consumo IGUAL ao teto: disponível exatamente zero. É o caso que o rótulo
      # descreve ao pé da letra, e era justamente o que ficava de fora.
      def limite_com_consumo!(teto:, consumido:)
        control = create(:risk_control, project: projeto_a, limite: teto)
        create(:risk_operation, risk_control: control, issue_date: Date.new(2026, 1, 1),
                                due_date: Date.new(2026, 12, 31), original_balance: consumido,
                                operation_value: 0)
        control
      end

      it 'o limite EXATAMENTE no teto conta no cartão (`<= 0`, não `< 0`)' do
        limite_com_consumo!(teto: 50_000, consumido: 50_000)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(cartao('limites_no_teto')['value']).to eq(1)
      end

      it 'a lista traz quem está em 90% ou mais, com a porcentagem como NÚMERO' do
        limite_com_consumo!(teto: 100_000, consumido: 95_000) # 95%
        limite_com_consumo!(teto: 100_000, consumido: 50_000) # 50% — fica de fora

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        lista = corpo['near_ceiling']
        expect(lista['threshold']).to eq(90)
        expect(lista['items'].size).to eq(1)
        expect(lista['items'].first['percent']).to be_within(0.01).of(95.0)
        # Número, nunca texto formatado: quem escreve "95,0%" é o front (OPS-289).
        expect(lista['items'].first['percent']).to be_a(Numeric)
        expect(lista['items'].first).not_to have_key('at_ceiling')
        expect(lista['has_data']).to be(true)
      end

      # **Cada limite em exatamente um lugar.** Quem já estourou não está
      # "prestes" a nada: ele é do cartão, e some da lista.
      it 'quem passou de 100% conta no cartão e NÃO aparece na lista' do
        limite_com_consumo!(teto: 10_000, consumido: 90_000) # 900%

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(cartao('limites_no_teto')['value']).to eq(1)
        expect(corpo['near_ceiling']['items']).to eq([])
      end

      # O limite EXATAMENTE no teto (disponível zero) também é do cartão.
      it 'o limite exatamente em 100% fica fora da lista' do
        limite_com_consumo!(teto: 50_000, consumido: 50_000)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(corpo['near_ceiling']['items']).to eq([])
      end

      it 'os dois indicadores não contam o mesmo limite duas vezes' do
        limite_com_consumo!(teto: 100_000, consumido: 95_000)  # lista
        limite_com_consumo!(teto: 100_000, consumido: 120_000) # cartão

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(cartao('limites_no_teto')['value']).to eq(1)
        expect(corpo['near_ceiling']['items'].size).to eq(1)
        expect(corpo['near_ceiling']['items'].first['percent']).to be_within(0.01).of(95.0)
      end

      # Divisão por zero não pode chegar à tela como `Infinity`/`NaN`.
      it 'limite com teto ZERO fica fora da lista' do
        limite_com_consumo!(teto: 0, consumido: 5_000)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(corpo['near_ceiling']['items']).to eq([])
        expect(response.body).not_to include('Infinity')
        expect(response.body).not_to include('NaN')
      end

      it 'a lista vem ordenada da mais apertada para a menos' do
        limite_com_consumo!(teto: 100_000, consumido: 92_000)
        limite_com_consumo!(teto: 100_000, consumido: 99_000)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        percentuais = corpo['near_ceiling']['items'].map { |i| i['percent'] }
        expect(percentuais).to eq(percentuais.sort.reverse)
      end

      # Vazio é uma RESPOSTA ("nenhum limite apertado"), e `nil` é ausência de
      # permissão/dado. A tela precisa dos dois separados para poder tranquilizar.
      it 'sem limite apertado, a lista vem VAZIA e `has_data: false` — não nula' do
        limite_com_consumo!(teto: 100_000, consumido: 1_000)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(corpo['near_ceiling']['items']).to eq([])
        expect(corpo['near_ceiling']['has_data']).to be(false)
      end

      it 'sem direito de ver limites, nem o cartão nem a lista aparecem' do
        allow(Authorization::Matrix).to receive(:allow?).and_call_original
        allow(Authorization::Matrix).to receive(:allow?)
          .with(anything, 'risk_controls', :read).and_return(false)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(cartao('limites_no_teto')).to be_nil
        expect(corpo['near_ceiling']).to be_nil
      end
    end

    # === A lista de renegociações em atraso — o par da lista de limites ======
    describe 'renegociações em atraso: a lista, não só a contagem' do
      it 'nomeia cada acordo, com quantas parcelas venceram, da pior para a menos' do
        um = create(:renegotiation, project: projeto_a, title: 'Acordo A')
        create(:renegotiation_installment, renegotiation: um, due_date: Date.new(2026, 1, 10))

        dois = create(:renegotiation, project: projeto_a, title: 'Acordo B')
        create(:renegotiation_installment, renegotiation: dois, due_date: Date.new(2026, 1, 10))
        create(:renegotiation_installment, renegotiation: dois, due_date: Date.new(2026, 2, 10))

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        lista = corpo['overdue_renegotiations']
        expect(lista['items'].map { |i| i['title'] }).to eq(['Acordo B', 'Acordo A'])
        expect(lista['items'].map { |i| i['overdue_count'] }).to eq([2, 1])
        expect(lista['total']).to eq(2)
        # O cartão irmão conta o mesmo conjunto: os dois nunca discordam.
        expect(cartao('renegociacoes_em_atraso')['value']).to eq(2)
      end

      it 'sem parcela vencida, vem vazia e `has_data: false` — não nula' do
        create(:renegotiation, project: projeto_a)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(corpo['overdue_renegotiations']['items']).to eq([])
        expect(corpo['overdue_renegotiations']['has_data']).to be(false)
      end

      # Truncar sem mentir: `total` é o número REAL, `items` é o que cabe.
      it 'trunca a lista mas informa o total verdadeiro' do
        (Dashboard::SummaryService::MAX_OVERDUE_ROWS + 2).times do |i|
          reneg = create(:renegotiation, project: projeto_a, title: "Acordo #{format('%02d', i)}")
          create(:renegotiation_installment, renegotiation: reneg, due_date: Date.new(2026, 1, 10))
        end

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        lista = corpo['overdue_renegotiations']
        expect(lista['items'].size).to eq(Dashboard::SummaryService::MAX_OVERDUE_ROWS)
        expect(lista['total']).to eq(Dashboard::SummaryService::MAX_OVERDUE_ROWS + 2)
      end

      it 'sem direito de ver renegociação, a lista não vem' do
        allow(Authorization::Matrix).to receive(:allow?).and_call_original
        allow(Authorization::Matrix).to receive(:allow?)
          .with(anything, 'renegotiations', :read).and_return(false)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(corpo['overdue_renegotiations']).to be_nil
      end
    end

    # === O endpoint é compositor, e isso é verificável no arquivo ============
    it 'não tem agregação financeira própria (nenhum SUM no arquivo do endpoint)' do
      fonte = Rails.root.join('app/controllers/api/v1/dashboard.rb').read
      expect(fonte).not_to match(/\bSUM\(/i)
      expect(fonte).not_to match(/\.sum\b/)
    end

    # === 5.2 — escopo (C1) e a lição do D-110 ===============================
    describe 'escopo por projeto' do
      it 'dois projetos devolvem números diferentes para o MESMO usuário' do
        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)
        a = cartao('total_operado')['value'].to_d

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_b)
        b = cartao('total_operado')['value'].to_d

        expect(a).to eq(bordero_a.valor_bruto)
        expect(b).to eq(bordero_b.valor_bruto)
        expect(a).not_to eq(b)
      end

      it 'projeto sem participação não vaza número nenhum' do
        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_alheio)

        expect(response).to have_http_status(404)
        expect(response.body).not_to include('total_operado')
      end

      # A anti-enumeração da condição 2 do DC-08: **o mesmo corpo** para "não
      # existe" e "existe e não é seu". Corpos diferentes transformariam o painel
      # num oráculo de ids.
      it 'projeto inexistente e projeto alheio respondem o MESMO status e o MESMO corpo' do
        get '/api/v1/dashboard/summary', headers: auth_headers(gerente, project: projeto_alheio)
        alheio = [response.status, response.body]

        get '/api/v1/dashboard/summary', headers: auth_headers(gerente).merge(
          'X-Project-Id' => SecureRandom.uuid
        )
        inexistente = [response.status, response.body]

        expect(alheio).to eq(inexistente)
      end
    end

    # === 5.3 — permissão: o cartão SOME, não vem zerado =====================
    #
    # Na matriz DEC-18 de hoje os quatro papéis leem `renegotiations`, então
    # nenhum papel exercita este caminho. O mecanismo precisa existir e ser
    # testado assim mesmo: ele é o que impede um cartão zerado de mentir no dia
    # em que a matriz mudar. O stub é da **matriz**, não do serviço — é a matriz
    # que decide.
    it 'sem direito de ver renegociação, o cartão NÃO VEM (e não vem zerado)' do
      allow(Authorization::Matrix).to receive(:allow?).and_call_original
      allow(Authorization::Matrix).to receive(:allow?)
        .with(anything, 'renegotiations', :read).and_return(false)

      get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                       headers: auth_headers(gerente, project: projeto_a)

      expect(cartao('renegociacoes_em_atraso')).to be_nil
      expect(corpo['cards'].map { |c| c['key'] }).to contain_exactly(
        'total_operado', 'exposicao', 'limites_no_teto'
      )
    end

    # === D-117 — ausência é distinguível de zero ============================
    describe 'ausência de dado' do
      it 'sem borderô no período, o total operado vem NULO — não zero' do
        get '/api/v1/dashboard/summary', params: { date: Date.new(2020, 1, 1).to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(cartao('total_operado')).to have_key('value')
        expect(cartao('total_operado')['value']).to be_nil
      end

      it 'sem limite ativo, exposição e limites no teto vêm NULOS — não zero' do
        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(cartao('exposicao')['value']).to be_nil
        expect(cartao('limites_no_teto')['value']).to be_nil
      end

      it 'COM limite ativo e nada utilizado, o zero é um zero de verdade' do
        create(:risk_control, project: projeto_a, limite: 100_000)

        get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                         headers: auth_headers(gerente, project: projeto_a)

        expect(cartao('limites_no_teto')['value']).to eq(0)
      end
    end

    # === Somente leitura é leitura pura =====================================
    it 'usuário somente-leitura vê o painel inteiro' do
      Membership.create!(project: projeto_a, user: somente_leitura, role: 'participante')
      UserPermission.create!(user: somente_leitura, permission: Permission.find_by!(key: 'user_is_readonly'),
                             source: 'manual', granted_at: Time.current)

      get '/api/v1/dashboard/summary', params: { date: hoje.to_s },
                                       headers: auth_headers(somente_leitura, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(corpo['cards'].size).to eq(4)
    end
  end

  # ---------------------------------------------------------------------------
  describe 'GET /api/v1/dashboard/volume_by_carrier' do
    it 'devolve `{ labels, values }` por portador, no escopo do projeto' do
      control = create(:risk_control, project: projeto_a, limite: 100_000)
      create(:risk_operation, risk_control: control, issue_date: Date.new(2026, 1, 1),
                              due_date: Date.new(2026, 12, 31), original_balance: 40_000,
                              operation_value: 0)

      get '/api/v1/dashboard/volume_by_carrier', params: { date: hoje.to_s },
                                                 headers: auth_headers(gerente, project: projeto_a)

      expect(response).to have_http_status(200)
      expect(corpo['labels']).to eq([control.carrier.title])
      expect(corpo['values'].size).to eq(1)
      expect(corpo['has_data']).to be(true)
    end

    # Lista vazia = **não há limite ativo**. É diferente de "todos zerados", e é
    # o front que mostra mensagens diferentes para os dois.
    it 'projeto sem limite ativo devolve lista vazia e `has_data: false`' do
      get '/api/v1/dashboard/volume_by_carrier', params: { date: hoje.to_s },
                                                 headers: auth_headers(gerente, project: projeto_a)

      expect(corpo['labels']).to eq([])
      expect(corpo['has_data']).to be(false)
    end

    it 'projeto sem participação não devolve nada' do
      get '/api/v1/dashboard/volume_by_carrier', headers: auth_headers(gerente, project: projeto_alheio)

      expect(response).to have_http_status(404)
    end
  end
end
