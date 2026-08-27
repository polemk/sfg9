# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/seeds/demo/ledger').to_s

# **A regra de cobertura do seed de demonstração** (S20 / DEC-64).
#
# ## Por que este arquivo existe
#
# A apresentação de sexta **não é conduzida por quem construiu o sistema**.
# Quem apresenta não sabe desviar de tela vazia: o que estiver faltando vai
# aparecer, e vai aparecer no meio da conversa.
#
# A medição de 26/08/2026 no banco de demonstração encontrou o oposto do que o
# desenho prometia — disponibilidade em **2 de 13** projetos, `charges`,
# `admin_messages`, `observers` e `receipts` **zeradas**, e quatro clientes com
# uma empresa e um limite (sem duas empresas não há consolidação; com um limite
# não há carteira).
#
# A regra que saiu daí, nas palavras do usuário: *"a maioria dos projetos tem
# que ter tudo preenchido; menos da metade pode ficar faltando algumas
# coisas."*
#
# Lacuna em minoria é **realista** — projeto novo, projeto pequeno — e serve
# para demonstrar o estado vazio. O que este spec impede é a lacuna virar
# **sobra**: cada projeto sem uma área precisa estar numa lista nomeada, com
# motivo escrito, e a soma dessas listas precisa continuar sendo minoria.
#
# Roda **no razão**, sem tocar no banco: é onde a cobertura é decidida, e é o
# que faz este spec falhar no minuto em que alguém acrescentar um cliente novo
# sem lhe dar conteúdo.
RSpec.describe 'Demo::Ledger — cobertura por projeto' do
  let(:ledger) { Demo::Ledger.new(base_date: Date.new(2026, 8, 28)) }

  # As áreas que a apresentação abre pelo menu, e o mínimo que faz cada tela
  # deixar de parecer quebrada.
  def coverage_for(client)
    {
      empresas: ledger.companies_by_client.fetch(client.slug, []).size,
      limites: ledger.controls_by_client.fetch(client.slug, []).size,
      borderos: ledger.borderos.count { |b| b.client.slug == client.slug },
      renegociacoes: ledger.renegotiations.count { |r| r.client.slug == client.slug },
      disponibilidades: ledger.availability_entries_by_client.fetch(client.slug, []).size,
      cobrancas: ledger.charges.count { |c| c.client.slug == client.slug },
      indicadores: ledger.indicator_entries.count { |e| e.client.slug == client.slug }
    }
  end

  def complete?(client)
    coverage_for(client).values.all?(&:positive?)
  end

  it 'a MAIORIA dos projetos tem todas as áreas preenchidas' do
    completos = ledger.clients.select { |c| complete?(c) }

    expect(completos.size * 2).to be > ledger.clients.size,
                                  "só #{completos.size} de #{ledger.clients.size} projetos completos: " \
                                  "#{(ledger.clients - completos).map(&:slug).join(', ')}"
  end

  it 'toda lacuna está numa lista nomeada — nenhuma é sobra' do
    declaradas = Demo::Ledger::Availability::WITHOUT_ENTRIES +
                 Demo::Ledger::Billing::WITHOUT_CHARGES

    incompletos = ledger.clients.reject { |c| complete?(c) }.map(&:slug)

    expect(incompletos - declaradas).to be_empty
  end

  # **Duas empresas é o piso do painel de disponibilidade**: com uma só, a linha
  # de consolidação geral repete a da empresa e a tela mostra o mesmo número
  # duas vezes.
  it 'todo projeto com lançamento de disponibilidade tem duas ou mais empresas' do
    com_lancamento = ledger.availability_entries_by_client.keys

    magros = com_lancamento.reject { |slug| ledger.companies_by_client.fetch(slug, []).size >= 2 }

    expect(magros).to be_empty
  end

  # **Datas diferentes no mesmo mês** é o que marca dias no calendário (FE-122)
  # e o que faz o saldo acumulado variar de um clique para o outro. Um mês com
  # um lançamento só é um calendário com um ponto.
  it 'todo projeto com disponibilidade tem três ou mais datas no mesmo mês' do
    pobres = ledger.availability_entries_by_client.filter_map do |slug, entries|
      por_mes = entries.map(&:date).uniq.group_by { |d| [d.year, d.month] }
      slug unless por_mes.values.any? { |dates| dates.size >= 3 }
    end

    expect(pobres).to be_empty
  end

  # **O painel abre com HOJE selecionado.** Sem lançamento na data-base, a
  # primeira coisa que quem apresenta vê é uma grade inteira de `R$ 0,00`, com o
  # calendário marcando pontos noutros dias e os cards de saldo do mês cheios —
  # pior do que vazio, porque parece defeito. Foi o que a renderização de 26/08
  # mostrou, e é por isso que a data-base entra sempre na lista.
  #
  # Três datas-base de propósito: um dia útil no meio do mês, o **1º** (quando o
  # mês corrente tem uma data só) e o **último dia do ano** (quando o mês
  # anterior é de outro ano).
  it 'todo projeto com disponibilidade tem lançamento na própria data-base' do
    [Date.new(2026, 8, 28), Date.new(2026, 9, 1), Date.new(2026, 12, 31)].each do |base|
      razao = Demo::Ledger.new(base_date: base)
      hoje = Demo::Ledger::Availability.business_day_on_or_before(base)

      sem_hoje = razao.availability_entries_by_client.reject do |_slug, entries|
        entries.any? { |e| e.date == hoje }
      end

      expect(sem_hoje.keys).to be_empty, "data-base #{base}: #{sem_hoje.keys.join(', ')}"
    end
  end

  # **O par base × corrigido (FE-134 / DEC-24)**: sem um padrão `is_adjusted`
  # com lançamento, metade da tela de padrões não tem o que demonstrar.
  it 'a árvore de padrões tem padrão corrigido, não cumulativo e das duas naturezas' do
    templates = ledger.availability_templates

    expect(templates.select(&:is_adjusted)).not_to be_empty
    expect(templates.reject(&:is_cumulative)).not_to be_empty
    expect(templates.map(&:operation_type).uniq).to include('C', 'D')
    # **Os dois escopos.** A coluna de marcadores da tela distingue o padrão que
    # veio do catálogo ("Global") do que o projeto cadastrou ("Específico"); com
    # todos vindos do catálogo o selo não demonstra nada.
    expect(templates.map(&:is_global).uniq).to match_array([true, false])
    expect(ledger.availability_entries.select { |e| adjusted?(templates, e) }).not_to be_empty
  end

  def adjusted?(templates, entry)
    templates.find { |t| t.key == entry.template_key }&.is_adjusted
  end

  # **Todo estado que a tela sabe pintar tem ao menos um exemplo.** Lista
  # monocromática não demonstra filtro nem pílula.
  it 'as 8 situações e os 4 contextos de mensagem administrativa têm exemplo' do
    expect(ledger.admin_messages.map(&:state).uniq).to match_array(AdminMessage::STATES.keys)
    expect(ledger.admin_messages.map(&:context).uniq).to match_array(AdminMessage::CONTEXTS.keys)
  end

  it 'os observadores cobrem os 4 contextos e os dois lados de `is_internal`' do
    expect(ledger.observers.flat_map(&:contexts).uniq).to match_array(AdminMessage::CONTEXTS.keys)
    expect(ledger.observers.map(&:is_internal).uniq).to match_array([true, false])
  end

  it 'as 3 situações de cobrança têm exemplo' do
    expect(ledger.charges.map(&:state).uniq).to match_array(Charge::STATES)
  end

  # **Volume para a paginação aparecer** (`per_page` é 20) em pelo menos uma
  # lista de cada área que a apresentação abre.
  it 'pelo menos uma lista de cada área passa de uma página' do
    por_cliente = lambda do |colecao|
      colecao.group_by { |r| r.client.slug }.values.map(&:size).max.to_i
    end

    expect(por_cliente.call(ledger.borderos)).to be > 20
    expect(por_cliente.call(ledger.operations)).to be > 20
    expect(por_cliente.call(ledger.renegotiations)).to be >= 12
    expect(ledger.admin_messages.size).to be > 20
    expect(ledger.availability_templates.size).to be >= 16
  end

  # **"Nova renegociação" precisa ter fornecedor SOBRANDO.**
  #
  # A `integration_key` da renegociação é derivada do nome do fornecedor e é
  # única por projeto (`Renegotiation`, S9), e o formulário oferece os
  # fornecedores ATIVOS do projeto. Enquanto o seed cadastrava exatamente os
  # fornecedores que as renegociações já usavam, **toda** opção do `select`
  # colidia: medido em 27/08/2026, folga zero nos 12 projetos e 422 nos três
  # fornecedores oferecidos.
  #
  # Este exemplo é o que impede a folga de voltar a zero quando alguém subir a
  # volumetria de renegociações sem subir a lista de fornecedores.
  it 'todo projeto tem fornecedor sem renegociação — folga para criar uma nova' do
    usados = ledger.renegotiations.group_by { |r| r.client.slug }
                   .transform_values { |lista| lista.map(&:provider_name).uniq }

    magros = ledger.clients.filter_map do |client|
      titulos = ledger.providers.select { |p| p.client.slug == client.slug }.map(&:title)
      livres = titulos - usados.fetch(client.slug, [])
      [client.slug, livres.size] if livres.size < Demo::Ledger::Ancillary::PROVIDER_SLACK
    end

    expect(magros).to be_empty
  end

  # A folga só é folga se os nomes forem DISTINTOS: a chave natural do escritor
  # de fornecedores é `(project_id, title)`, então dois títulos iguais no mesmo
  # projeto viram uma linha só e a folga medida acima seria fictícia.
  it 'nenhum projeto tem dois fornecedores com o mesmo nome' do
    repetidos = ledger.providers.group_by { |p| [p.client.slug, p.title] }
                      .select { |_, lista| lista.size > 1 }

    expect(repetidos.keys).to be_empty
  end

  # **A transferência pré → antecipação (BE-275) precisa existir e ser SÓ o par.**
  #
  # Medido antes: as 78 operações estáticas do seed tinham saldo zero e zero
  # movimentos, e o razão lançava 105 "Transferência Recebida" SOLTAS em
  # operações comuns — dado que o sistema não produz, porque `is_transfer` está
  # fora de `RiskMovementType.manual` e o único caminho é o
  # `Risk::TransferService`, que sempre cria as duas pontas.
  it 'o razão declara transferência de par estático, e em modalidade que abre par' do
    expect(ledger.static_transfers).not_to be_empty

    modalidades = ledger.static_transfers.map { |t| t.control.modality }.uniq
    expect(modalidades - Demo::Ledger::Operations::PRE_MODALITIES).to be_empty
  end

  # Fora do plano de utilização: a exposição da transferência não pode empurrar
  # um limite planejado para outra faixa da DEC-116.
  it 'a transferência cai em limite que o plano de utilização NÃO usa' do
    planejados = ledger.static_transfers.select do |t|
      (t.control.target_utilization || 0) >= Demo::Ledger::Controls::FORCED_UTILIZATION_FLOOR
    end

    expect(planejados.map { |t| t.control.key }).to be_empty
  end

  it 'nenhum movimento de transferência é lançado solto nas operações comuns' do
    soltas = ledger.movements.select { |m| %i[transferencia_recebida valor_transferido].include?(m.type_key) }

    expect(soltas.map { |m| m.operation.contract_number }).to be_empty
  end

  # **Os sete totais de `charges` são derivados**, e `Charge#recalculate!` os
  # reescreve somando os recibos do banco. O razão os calcula da mesma lista —
  # se os dois caminhos divergirem, a tela some com dinheiro na frente do
  # cliente.
  it 'o total de cada cobrança é a soma dos recibos dela' do
    divergentes = ledger.charges.reject do |charge|
      soma = charge.receipts.sum(&:value).round(2)
      (charge.value - soma).abs < 0.02 &&
        charge.receipts_count == charge.receipts.size &&
        charge.risk_operations_count == charge.receipts.count { |r| r.kind == 'LIQ' }
    end

    expect(divergentes.map(&:key)).to be_empty
  end

  # `operation_value × (fee / 100)` — a fórmula do `receipt.rb` de 2022 (D-B14).
  it 'o valor de cada recibo é a taxa aplicada ao valor da operação' do
    errados = ledger.charge_receipts.reject do |receipt|
      esperado = (receipt.operation_value * (receipt.fee / 100.0)).round(2)
      (receipt.value - esperado).abs < 0.01
    end

    expect(errados).to be_empty
  end

  # Uma operação **não pode ser faturada duas vezes** — é o índice único
  # `(operation_id, project_id, operation_type)` de `receipts`.
  #
  # A chave é `(cliente, contrato)`, e **não** o contrato sozinho: o número de
  # contrato é sequencial **por cliente** (`counters[control.client.slug]` em
  # `ledger/operations.rb`), então `CT-2024-00001` existe uma vez em cada
  # projeto. O índice do banco também é por projeto — comparar só o número aqui
  # reprovaria um seed correto.
  it 'nenhuma operação aparece em dois recibos DENTRO do mesmo projeto' do
    contratos = ledger.charge_receipts.map { |r| [r.client.slug, r.operation.contract_number] }

    expect(contratos.tally.select { |_, n| n > 1 }).to be_empty
  end

  # ------------------------------------------------------------------
  # Remuneração (S8) — a tabela de preço, e as regras que a sustentam
  # ------------------------------------------------------------------
  # **A taxa é o número que mais rápido desmonta uma demonstração.** O seed do
  # legado sorteava `rand(0.00..100.00)` e entregava 87% ao mês; aqui a faixa é
  # de mercado e o spec a trava, para que nenhuma banda futura escape dela sem
  # que este exemplo reprove.
  it 'toda remuneração fica dentro da faixa de mercado' do
    piso, teto = Demo::Ledger::Billing::FEE_RANGE

    fora = ledger.remunerations.reject { |r| r.value.between?(piso, teto) }

    expect(fora.map { |r| [r.key, r.value] }).to be_empty
  end

  # As duas classes do polimorfismo de `remuneration.rb:31-46`. Semear só `LIQ`
  # deixaria as 136 estruturadas sem um único candidato a recibo.
  it 'as duas classes de remuneração estão cobertas, em todo projeto' do
    por_cliente = ledger.remunerations.group_by { |r| r.client.slug }

    sem_liq = por_cliente.reject { |_, lista| lista.any? { |r| r.kind == 'LIQ' } }.keys
    sem_est = por_cliente.reject { |_, lista| lista.any? { |r| r.kind == 'EST' } }.keys

    expect(ledger.remunerations.map(&:operation_type_class).uniq)
      .to match_array(%w[RiskOperationType StructuredOperationType])
    expect(sem_liq + sem_est).to be_empty
  end

  # **Toda remuneração responde a "por que esta taxa existe?"**: a modalidade é
  # derivada do que o cliente opera, então há sempre limite (LIQ) ou operação
  # estruturada (EST) por trás dela.
  it 'nenhuma remuneração é de modalidade que o cliente não opera' do
    liq = ledger.controls.map { |c| [c.client.slug, c.modality] }.uniq
    est = ledger.structured_operations.map { |o| [o.client.slug, o.modality] }.uniq

    orfas = ledger.remunerations.reject do |r|
      (r.kind == 'LIQ' ? liq : est).include?([r.client.slug, r.modality])
    end

    expect(orfas.map(&:key)).to be_empty
  end

  # **Uma taxa, um dono.** `Receipt#fee` é cópia de `remunerations.value`
  # (`receipt.rb:61-63`); se o razão sorteasse a taxa do recibo por conta
  # própria, o mesmo cliente apareceria faturado a duas taxas na mesma
  # modalidade — e é isso que este exemplo impede de voltar.
  it 'a taxa de cada recibo é a da remuneração do par cliente × tipo' do
    tabela = ledger.remunerations.to_h { |r| [[r.client.slug, r.kind, r.modality], r] }

    divergentes = ledger.charge_receipts.reject do |receipt|
      # A modalidade da operação de risco vem do LIMITE; a da estruturada é
      # atributo dela mesma. Mesma regra de `Billing.modality_of`.
      modalidade = Demo::Ledger::Billing.modality_of(receipt.operation)
      remuneracao = tabela[[receipt.client.slug, receipt.kind, modalidade]]
      remuneracao && receipt.fee == remuneracao.value && receipt.title == remuneracao.title
    end

    expect(divergentes.map { |r| [r.client.slug, r.fee] }).to be_empty
  end

  # ------------------------------------------------------------------
  # As lacunas de cobertura medidas em 27/08/2026
  # ------------------------------------------------------------------
  # **A classe `EST` existia na tabela de preço e em recibo nenhum.** Toda linha
  # da lista de Cobranças dizia `0 est.`, e a coluna existia para não mostrar
  # nada.
  it 'a classe EST é exercitada: há recibo de operação estruturada' do
    est = ledger.charge_receipts.select { |r| r.kind == 'EST' }

    expect(est).not_to be_empty
    expect(est.map { |r| r.client.slug }.uniq.size).to be >= 3
    # O recibo `EST` aponta mesmo para uma estruturada, e não para uma operação
    # de risco rotulada errado.
    expect(est.map { |r| r.operation.contract_number }).to all(start_with('EST-'))
  end

  # E a contrapartida: **sobra candidato**. Faturar tudo tiraria da apresentação
  # a demonstração de marcar uma estruturada ao vivo dentro de um pacote em
  # edição, que é o que `Charges::ReceiptGenerator#candidates` lista.
  it 'sobram estruturadas encerradas SEM recibo — os candidatos da demonstração' do
    faturadas = ledger.charge_receipts.select { |r| r.kind == 'EST' }
                      .map { |r| [r.client.slug, r.operation.contract_number] }.to_set

    candidatas = ledger.structured_operations.select(&:is_ended).reject do |operation|
      faturadas.include?([operation.client.slug, operation.contract_number])
    end

    expect(candidatas.size).to be >= 20
  end

  # **O espelho da produção estava invertido**: 527 indicadores de projeto e 2
  # globais lá; 5 globais e ZERO específico aqui. A coluna "Alcance" dizia
  # "Global" em todas as linhas, e um selo que nunca muda não demonstra que
  # existe diferença.
  it 'existe indicador ESPECÍFICO de projeto, com lançamento' do
    especificos = ledger.indicator_entries.select(&:project_specific)

    expect(especificos).not_to be_empty
    expect(especificos.map { |e| e.client.slug }.uniq.size).to be >= 2
    expect(especificos.map(&:indicator_key).uniq.size).to be >= 3
  end

  # O específico não pode roubar a cena: o catálogo global é o que permite
  # comparar carteira contra carteira.
  it 'o lançamento de indicador continua majoritariamente global' do
    total = ledger.indicator_entries.size
    especificos = ledger.indicator_entries.count(&:project_specific)

    expect(especificos).to be_positive
    expect(especificos * 2).to be < total
  end

  # Desconto por volume: quem opera mais paga percentual menor. É a primeira
  # coisa que um diretor financeiro confere numa tabela de preço.
  it 'o cliente grande paga percentual menor que o pequeno' do
    media = lambda do |tier|
      lista = ledger.remunerations.select { |r| r.client.tier == tier }
      lista.sum(&:value) / lista.size
    end

    expect(media.call(:grande)).to be < media.call(:medio)
    expect(media.call(:medio)).to be < media.call(:pequeno)
  end

  # CNPJ que o próprio formulário recusaria é demonstração que se desmente.
  it 'todo CNPJ de empresa fecha o dígito verificador' do
    invalidos = ledger.companies.reject { |c| Demo::Support::Br.valid_cnpj?(c.cnpj) }

    expect(invalidos.map(&:title)).to be_empty
  end
end
