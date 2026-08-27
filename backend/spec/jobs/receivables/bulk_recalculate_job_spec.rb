# frozen_string_literal: true

require 'rails_helper'

# S6 / `OPS-151` — **o recálculo em lote dos borderôs de um projeto**.
#
# ## O que o legado tinha
#
# Uma rake/console com `ReceivableEntry.all.each(&:save)`: de uma vez, sem lote,
# sem progresso, com o logger silenciado "para não poluir". Em 28.131 borderôs
# isso carrega a tabela inteira na memória — e, pior, cada `save` disparava o
# `after_commit` de `../sfg/app/models/receivable_entry.rb:124-176`, que mexe na
# exposição ao risco. Rodar duas vezes criava **movimento duplicado** (D-11).
#
# ## O que este arquivo mede
#
# Três coisas que só aparecem em lote e que nenhum teste de endpoint pega:
#
# 1. **O efeito colateral está DESLIGADO por padrão** — e o padrão é a decisão,
#    não a conveniência (DEC-36);
# 2. **uma linha ruim não derruba o lote** — o legado abortava no primeiro
#    `save` que levantasse, deixando a base metade recalculada e sem dizer onde
#    parou;
# 3. **a alíquota de IOF é a da data do BORDERÔ** (D-15) — que é a diferença
#    entre reprocessar e reescrever a história.
RSpec.describe Receivables::BulkRecalculateJob do
  let(:og) { create(:user, :og) }
  let(:project) { create_project_with_owner(og) }
  let(:company) { create(:company, project: project) }
  let(:carrier) { create(:carrier) }

  # Sem `iof_rate` cadastrada o `Calculator` cai nas alíquotas de origem, e o
  # resultado é o mesmo — mas o bloco D-15 abaixo precisa de duas vigências
  # distintas, então cada bloco cadastra as suas.
  def bordero(**over)
    create(:receivable_entry, { project: project, company: company, carrier: carrier }.merge(over))
  end

  # ====================================================================
  # O contrato de retorno
  # ====================================================================
  describe 'o lote e o relatório' do
    it 'recalcula e devolve `{processed:, changed:, failures:}`' do
      # Progresso e falhas **visíveis**. A rake do legado não devolvia nada:
      # quem a rodava descobria o resultado olhando o banco depois.
      3.times { bordero }

      resultado = described_class.perform_now(project.id)

      expect(resultado).to match(processed: 3, changed: 3, failures: [])
    end

    it 'preenche os ~33 derivados de um borderô que nasceu sem eles' do
      # A factory NÃO calcula, de propósito: quem calcula é o serviço, uma vez
      # por operação (contrato C2). Aqui é o job que faz esse papel.
      entry = bordero(valor_bruto: BigDecimal('100000.00'),
                      prz_med_pond_emp: BigDecimal('28'), prz_med_pond_bco: BigDecimal('30'))
      # Borderô não calculado não tem derivado NULO: tem o **default do banco**,
      # que é zero. É o que torna "não recalculado" indistinguível de
      # "recalculado e deu zero" quando se olha só a coluna — por isso os
      # exemplos abaixo comparam contra um valor bruto que não é zero.
      expect(entry.valor_liquido).to eq(0)

      described_class.perform_now(project.id)

      entry.reload
      expect(entry.valor_liquido).to eq(BigDecimal('100000.00'))
      expect(entry.vlr_bruto_final).to eq(BigDecimal('100000.00'))
      expect(entry.status).to be_present
    end

    it 'a segunda passada não conta como `changed` — nada mudou' do
      # É o que permite rodar o job de novo com segurança e ler o `changed` como
      # "quantos borderôs o recálculo REALMENTE corrigiu". Um `changed` sempre
      # igual ao `processed` não informa nada.
      2.times { bordero }
      described_class.perform_now(project.id)

      expect(described_class.perform_now(project.id)).to match(processed: 2, changed: 0, failures: [])
    end

    it 'NÃO toca em borderô de outro projeto' do
      alheio = create(:receivable_entry, project: create_project_with_owner(create(:user, :og)),
                                         valor_bruto: BigDecimal('100000.00'))
      bordero

      resultado = described_class.perform_now(project.id)

      expect(resultado[:processed]).to eq(1)
      # Zero é o default do banco: o borderô alheio continua como nasceu.
      expect(alheio.reload.valor_liquido).to eq(0)
    end

    it 'projeto sem nenhum borderô devolve o relatório zerado' do
      expect(described_class.perform_now(project.id)).to match(processed: 0, changed: 0, failures: [])
    end

    it 'respeita `batch_size` sem mudar o resultado' do
      # `find_each` em lotes é o que evita carregar 28 mil linhas na memória. O
      # tamanho do lote é ajuste de operação e **não pode** mudar o número.
      5.times { bordero }

      expect(described_class.perform_now(project.id, batch_size: 2)).to match(processed: 5, changed: 5,
                                                                              failures: [])
    end
  end

  # ====================================================================
  # DEC-36 — a sincronia de risco DESLIGADA por padrão
  # ====================================================================
  describe 'sync_risk: false é o padrão (DEC-36)' do
    # **Por que o padrão é `false`, e por que ele é a parte importante do job.**
    #
    # O DEC-36 decidiu **COPIAR** `operation_value` das operações de risco
    # históricas como está no legado, e **não** recalcular: *"o painel de
    # exposição do ai9 bate 100% com o do legado, e o dado errado vai junto"*.
    # Recalcular número de borderô e relançar exposição ao risco são duas
    # operações distintas, e só a primeira é o que `OPS-151` pede.
    #
    # Rodar este job com `sync_risk: true` sobre a base carregada **desfaria a
    # DEC-36 em silêncio**: as operações históricas passariam a valer o líquido
    # recalculado, o painel deixaria de bater com o legado, e não haveria
    # nenhum registro de quando isso aconteceu. Por isso o padrão é `false` —
    # quem quiser o efeito colateral pede por parâmetro, e aí está escolhendo.
    let(:tipo) { create(:risk_operation_type) }
    let(:subtipo) { tipo.reload.subtypes.first }

    before do
      # **Acrescentado pela S7 (26/08/2026) — lacuna de fixture, não de regra.**
      # Desde que a S7 entregou o `after_create` de `RiskOperation` (`BE-264`),
      # a operação criada pelo borderô lança "Liberação do Recurso", resolvido
      # por `integration_key` (B-09). Esses tipos são **dado de referência**: em
      # produção `rake reference:seed` os garante. Sem semeá-los, o exemplo de
      # `sync_risk: true` exercitava um ambiente que não existe.
      Seeds::Reference::RiskMovementTypes.call!

      create(:risk_control, project: project, company: company, carrier: carrier,
                            risk_operation_type: tipo, is_active: true)
    end

    it 'NÃO cria `RiskOperation` nova ao recalcular' do
      bordero(risk_operation_subtype: subtipo)

      expect { described_class.perform_now(project.id) }
        .not_to(change { RiskOperation.count })
    end

    it 'NÃO cria nem duplica `RiskMovement`, nem rodando o job duas vezes' do
      # O defeito concreto do legado: `after_commit` dispara em TODO save, e o
      # controller salvava duas vezes (D-11). Um recálculo em massa sobre 28
      # mil linhas produziria 28 mil movimentos de liberação inexistentes.
      bordero(risk_operation_subtype: subtipo)

      expect {
        described_class.perform_now(project.id)
        described_class.perform_now(project.id)
      }.not_to(change { RiskMovement.count })
    end

    it 'o borderô É recalculado mesmo com a sincronia desligada' do
      # Desligar o efeito colateral não pode desligar o trabalho. Se este
      # exemplo cair junto com os dois de cima, o "padrão seguro" virou
      # "padrão que não faz nada".
      entry = bordero(risk_operation_subtype: subtipo, valor_bruto: BigDecimal('100000.00'))

      described_class.perform_now(project.id)

      expect(entry.reload.valor_liquido).to eq(BigDecimal('100000.00'))
    end

    it '`sync_risk: true` cria a operação — o parâmetro existe e funciona' do
      # Este exemplo é o contraponto: prova que o padrão `false` está
      # **escolhendo** não sincronizar, e não escondendo um caminho quebrado.
      # É também a demonstração do que NÃO se deve rodar sobre a base carregada.
      entry = bordero(risk_operation_subtype: subtipo)

      expect { described_class.perform_now(project.id, sync_risk: true) }
        .to change { RiskOperation.count }.by(1)

      operacao = entry.reload.risk_operation
      expect(operacao.operation_value).to eq(entry.valor_liquido)
      expect(operacao.operation_type_id).to eq(tipo.id)
    end

    it 'borderô SEM subtipo não sincroniza nada, nem com `sync_risk: true`' do
      # "Não associar" é escolha válida na tela (DB-156). Sem subtipo não há
      # exposição a lançar, e o `RiskSyncService` sai na primeira linha.
      bordero

      expect { described_class.perform_now(project.id, sync_risk: true) }
        .not_to(change { RiskOperation.count })
    end
  end

  # ====================================================================
  # Uma linha ruim não derruba o lote
  # ====================================================================
  describe 'falhas isoladas' do
    it 'borderô com entrada inválida entra em `failures` e os outros CONTINUAM' do
      # `update_columns` porque a validação do model já recusaria prazo zero: o
      # registro corrompido não entra pela tela. Foi exatamente por um caminho
      # assim que os **30 borderôs com `NaN`** de produção entraram — rake,
      # console ou o importador Django, nunca o formulário.
      ruim = bordero(valor_bruto: BigDecimal('100000.00'))
      ruim.update_columns(prz_med_pond_emp: 0)
      bons = Array.new(2) { bordero(valor_bruto: BigDecimal('100000.00')) }

      resultado = described_class.perform_now(project.id)

      expect(resultado[:processed]).to eq(3)
      expect(resultado[:changed]).to eq(2)
      expect(resultado[:failures].map { |f| f[:id] }).to eq([ruim.id])
      expect(resultado[:failures].first[:erro]).to include('prazo médio ponderado da empresa')

      bons.each { |entry| expect(entry.reload.valor_liquido).to eq(BigDecimal('100000.00')) }
      # O que falhou continua no default do banco: nada foi gravado nele.
      expect(ruim.reload.valor_liquido).to eq(0)
    end

    it 'a falha NÃO grava nada no borderô que falhou' do
      # O `InputGuard` barra **antes** de calcular. No legado o cálculo rodava
      # num `before_validation`, então o registro já saía do callback com
      # `Infinity`/`NaN` atribuído — e bastava um `save` distraído depois para
      # gravá-lo (D-10).
      ruim = bordero
      ruim.update_columns(prz_med_pond_bco: 0)

      described_class.perform_now(project.id)

      ruim.reload
      ReceivableEntry::DERIVED_COLUMNS.each do |coluna|
        valor = ruim.public_send(coluna)
        expect(Receivables::InputGuard.nonfinite?(valor)).to be(false), "#{coluna} = #{valor.inspect}"
      end
    end

    it 'várias linhas ruins entram TODAS no relatório' do
      # O legado abortava na primeira: quem rodasse a rake teria de consertar
      # uma linha, rodar de novo, descobrir a próxima. Aqui o lote termina e o
      # relatório traz a lista inteira.
      ruins = Array.new(3) { bordero }
      ruins.each { |e| e.update_columns(prz_med_pond_emp: 0) }
      bordero

      resultado = described_class.perform_now(project.id)

      expect(resultado[:processed]).to eq(4)
      expect(resultado[:changed]).to eq(1)
      expect(resultado[:failures].map { |f| f[:id] }).to match_array(ruins.map(&:id))
    end
  end

  # ====================================================================
  # D-15 — a alíquota é a da DATA DO BORDERÔ
  # ====================================================================
  describe 'D-15 — a alíquota vigente na data do borderô' do
    before do
      create(:iof_rate, daily_rate: BigDecimal('0.000041'), fixed_rate: BigDecimal('0.0038'),
                        valid_from: Date.new(2016, 1, 1), valid_to: Date.new(2024, 12, 31))
      create(:iof_rate, daily_rate: BigDecimal('0.000082'), fixed_rate: BigDecimal('0.0076'),
                        valid_from: Date.new(2025, 1, 1), valid_to: nil)
    end

    it 'um borderô de 2022 recalculado agora usa a alíquota DE 2022' do
      # É aqui que o D-15 se materializa. No legado as duas alíquotas estão
      # literais em `../sfg/app/models/receivable_entry.rb:54`, então o
      # recálculo em massa reescreveria os 28.131 borderôs históricos com a
      # alíquota vigente no dia em que a rake rodou — em silêncio, e sem forma
      # de descobrir depois qual foi usada.
      #
      # 100.000 × (30 × 0,000041) + 100.000 × 0,0038 = 123,00 + 380,00 = 503,00
      antigo = bordero(date: Date.new(2022, 6, 15), valor_bruto: BigDecimal('100000.00'),
                       prz_med_pond_emp: BigDecimal('28'), prz_med_pond_bco: BigDecimal('30'))

      described_class.perform_now(project.id)

      expect(antigo.reload.checagem_iof).to eq(BigDecimal('503.00'))
    end

    it 'no MESMO lote, cada borderô usa a alíquota da SUA data' do
      # A alíquota é resolvida por linha, não uma vez no começo do job. Resolver
      # fora do laço seria mais rápido e produziria o defeito de volta para todo
      # borderô que não fosse da vigência corrente.
      #
      # 2025: 100.000 × (30 × 0,000082) + 100.000 × 0,0076 = 246,00 + 760,00 = 1.006,00
      antigo = bordero(date: Date.new(2022, 6, 15), valor_bruto: BigDecimal('100000.00'),
                       prz_med_pond_emp: BigDecimal('28'), prz_med_pond_bco: BigDecimal('30'))
      novo = bordero(date: Date.new(2025, 6, 15), valor_bruto: BigDecimal('100000.00'),
                     prz_med_pond_emp: BigDecimal('28'), prz_med_pond_bco: BigDecimal('30'))

      described_class.perform_now(project.id)

      expect(antigo.reload.checagem_iof).to eq(BigDecimal('503.00'))
      expect(novo.reload.checagem_iof).to eq(BigDecimal('1006.00'))
    end

    it 'o resultado do job é o MESMO do `Calculator` chamado à mão (C2)' do
      # Não existe uma segunda fórmula "de lote". O job monta o mesmo `Input` e
      # chama o mesmo serviço que a tela — é o contrato C2, e é o que impede
      # este caminho de virar o D-09 outra vez, agora entre lote e tela.
      entry = bordero(date: Date.new(2022, 6, 15), valor_bruto: BigDecimal('149208.24'),
                      prz_med_pond_emp: BigDecimal('42'), prz_med_pond_bco: BigDecimal('42'))
      esperado = Receivables::Calculator.call(entry.calculator_input,
                                              iof_rate: IofRate.effective_on(entry.date))

      described_class.perform_now(project.id)

      entry.reload
      esperado.each do |coluna, valor|
        next if valor.nil?

        expect(entry.public_send(coluna)).to eq(valor), "#{coluna}: #{entry.public_send(coluna)} ≠ #{valor}"
      end
    end
  end

  # ====================================================================
  # Projeto inexistente
  # ====================================================================
  describe 'projeto inexistente' do
    it 'sai cedo, sem erro e sem tocar em nada' do
      # O job é enfileirado com um id, e o projeto pode ter sido excluído entre
      # o enfileiramento e a execução. Levantar aqui mandaria o job para o dead
      # set repetidamente, por uma condição que não tem conserto possível — é o
      # mesmo raciocínio do `rescue_from DeserializationError` do
      # `ApplicationJob`.
      entry = bordero(valor_bruto: BigDecimal('100000.00'))

      expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
      expect(entry.reload.valor_liquido).to eq(0)
    end

    it 'id malformado também sai cedo, sem `PG::InvalidTextRepresentation`' do
      expect { described_class.perform_now('não é uuid') }.not_to raise_error
    end

    it 'id nulo sai cedo' do
      expect { described_class.perform_now(nil) }.not_to raise_error
    end
  end
end
