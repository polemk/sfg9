# frozen_string_literal: true

require 'rails_helper'

# **BE-211 — a próxima parcela da renegociação: data E valor.**
#
# O legado renderizava DUAS colunas na listagem, as duas saindo da mesma linha:
# a data (`calculate_next_installment_date`) e o valor
# (`calculate_next_installment_value`, `renegotiation.rb:162-173`), consumidas
# em `list/_widget.html.erb:22`.
#
# A migração trouxe só a data. O valor **não existia em ponta nenhuma do ai9** —
# nem cálculo, nem exposição —, então a coluna simplesmente sumiu da tela.
# Achado pela conferência de paridade da Phase 4 (27/08/2026).
#
# A data, por sua vez, existia e **não tinha um único teste**: `grep -rln
# next_due_date spec/` não achava nada. Os dois casos ficam cobertos aqui, pela
# mesma razão — as duas colunas saem da mesma linha, e é essa escolha de linha
# que a regra define.
#
# ## A regra do legado, que estes exemplos travam
#
#   * só parcela **não paga**;
#   * só vencimento **hoje ou no futuro** — vencida NUNCA é "próxima";
#   * entre as candidatas, a de **menor vencimento**;
#   * o valor é `main_value_with_interest_cm` (principal com juros e correção),
#     não o `main_value` seco;
#   * **sem candidata, o valor é `0`** (`return 0.00`, `:164`) — e não nulo. A
#     coluna é dinheiro numa tabela: nulo viraria célula vazia onde o legado
#     mostra R$ 0,00.
RSpec.describe 'API::V1::Renegotiations — próxima parcela' do
  let(:user) { create(:user, :og) }
  let(:project) { create_project_with_owner(user) }
  let(:provider) { create(:provider, project: project, title: 'Aço Norte') }
  let(:company) { create(:company, project: project) }
  let(:headers) { auth_headers(user, project: project) }

  let(:renegociacao) do
    create(:renegotiation, project: project, provider: provider, company: company, title: 'Acordo A')
  end

  # **`is_paid` é DERIVADO, não atribuído.** `Formulas.installment` o calcula de
  # `pending <= 0`, e o `after(:build)` da fábrica reescreve por cima do que se
  # passar — `create(..., is_paid: true)` é silenciosamente ignorado, e o exemplo
  # que confiasse nisso testaria o contrário do que anuncia. Descoberto tentando.
  #
  # Aqui a parcela fica paga do jeito que o domínio a torna paga: com
  # `paid_value` cobrindo o total, pela MESMA fórmula da gravação.
  def parcela(dias:, main_value:, paga: false, number: 1)
    registro = create(:renegotiation_installment,
                      renegotiation: renegociacao, number: number,
                      due_date: Date.current + dias, main_value: main_value)
    return registro unless paga

    derivados = Renegotiations::Formulas.installment(
      main_value: main_value, interest_value: 0, monetary_correction_value: 0,
      paid_value: registro.installment_total_value
    )
    registro.update_columns(derivados)
    expect(registro.reload).to be_is_paid, 'a parcela deveria ter ficado paga'
    registro
  end

  def linha
    get '/api/v1/renegotiations', headers: headers
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body).find { |r| r['id'] == renegociacao.id }
  end

  it 'escolhe a parcela em aberto de MENOR vencimento futuro' do
    parcela(dias: 30, main_value: 300, number: 2)
    proxima = parcela(dias: 10, main_value: 100, number: 1)
    parcela(dias: 60, main_value: 600, number: 3)

    resultado = linha

    expect(resultado['next_due_date']).to eq(proxima.due_date.to_s)
    expect(resultado['next_installment_value'].to_d).to eq(proxima.main_value_with_interest_cm)
  end

  it 'IGNORA a parcela já paga, mesmo que ela vença antes' do
    parcela(dias: 5, main_value: 999, paga: true, number: 1)
    aberta = parcela(dias: 20, main_value: 250, number: 2)

    resultado = linha

    expect(resultado['next_due_date']).to eq(aberta.due_date.to_s)
    expect(resultado['next_installment_value'].to_d).to eq(aberta.main_value_with_interest_cm)
  end

  it 'IGNORA a parcela VENCIDA — atrasada não é "próxima"' do
    parcela(dias: -15, main_value: 999, number: 1)
    futura = parcela(dias: 7, main_value: 180, number: 2)

    resultado = linha

    expect(resultado['next_due_date']).to eq(futura.due_date.to_s)
    expect(resultado['next_installment_value'].to_d).to eq(futura.main_value_with_interest_cm)
  end

  it 'vencendo HOJE ainda é "próxima" — o limite do legado é `>=`, não `>`' do
    hoje = parcela(dias: 0, main_value: 400, number: 1)

    resultado = linha

    expect(resultado['next_due_date']).to eq(Date.current.to_s)
    expect(resultado['next_installment_value'].to_d).to eq(hoje.main_value_with_interest_cm)
  end

  it 'sem parcela futura em aberto: valor ZERO e data nula' do
    parcela(dias: -3, main_value: 500, number: 1)
    parcela(dias: 9, main_value: 500, paga: true, number: 2)

    resultado = linha

    expect(resultado['next_due_date']).to be_nil
    expect(resultado['next_installment_value'].to_d).to eq(0)
  end

  it 'o valor é o principal COM juros e correção, não o principal seco' do
    com_juros = create(:renegotiation_installment,
                       renegotiation: renegociacao, number: 1, due_date: Date.current + 5,
                       main_value: 1_000, interest_value: 120, monetary_correction_value: 30)

    resultado = linha

    expect(com_juros.main_value_with_interest_cm).to eq(1_150)
    expect(resultado['next_installment_value'].to_d).to eq(1_150)
  end

  # A razão de a busca ser em lote: no legado eram DUAS consultas por linha da
  # listagem. Este exemplo trava o número de consultas para que a coluna nova
  # não reintroduza o N+1 que a migração tinha eliminado.
  it 'resolve a página inteira sem uma consulta por linha' do
    3.times do |i|
      outra = create(:renegotiation, project: project, provider: provider, company: company,
                                     title: "Acordo #{i}")
      create(:renegotiation_installment, renegotiation: outra, number: 1,
                                         due_date: Date.current + i + 1, main_value: 100 * (i + 1))
    end
    parcela(dias: 4, main_value: 700, number: 1)

    consultas = 0
    assinatura = ->(_n, _s, _f, _i, payload) do
      consultas += 1 if payload[:sql]&.include?('renegotiation_installments')
    end

    ActiveSupport::Notifications.subscribed(assinatura, 'sql.active_record') do
      get '/api/v1/renegotiations', headers: headers
    end

    expect(response).to have_http_status(:ok)
    # Uma para a próxima parcela, e o que a agregação de vencidas já fazia. O
    # que não pode é crescer com o número de linhas: são 4 renegociações.
    expect(consultas).to be <= 3
  end
end
