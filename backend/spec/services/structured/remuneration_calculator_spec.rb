# frozen_string_literal: true

require 'rails_helper'

# S8 / **OPS-287**, **BE-305**, **BE-306**, **BE-294** — o **primeiro** teste da
# unidade de operações estruturadas.
#
# Antes deste arquivo havia **zero** cobertura para `StructuredOperation`,
# `StructuredOperationType`, `Remuneration`, `ResourceSource` e `Receipt`. A
# fórmula que multiplica todo o faturamento não tinha um único teste — nem no
# legado, nem no ai9.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b / DEC-115
#
# Estes goldens têm **FONTE, não ORÁCULO** — e a diferença é o ponto.
#
# `receipts` e `remunerations` estão entre as **24 migrations que nunca
# subiram** (`analise-dump-producao.md` §1): a última aplicada em produção é de
# **25/05/2022** e o sistema rodou em uso até **31/05/2025**. Não existe uma
# linha de produção contra a qual conferir.
#
# Logo, o que estes exemplos travam é a **leitura do código de 2022**
# (`../sfg/app/models/receipt.rb:41-66`), conferida executando a mesma
# aritmética Ruby — e **não** três anos de comportamento validado, como é o
# caso do borderô da S6. Dizer isso aqui é o que impede alguém de ler "golden"
# como "provado em produção".
#
# **Encerramento (DEC-115, 26/08/2026):** a tarefa **13.5** pedia reconferir
# estes goldens *"contra o legado, com o dump carregado"*. Ela foi **reescrita**,
# não adiada: o usuário confirmou que não existe outra base (*"nao tem, a tabela
# de excel que tinha foi perdida"*), e a conferência que vale passou a ser
# **contra a FONTE de 2022** — que é o que este arquivo faz. **Nada disso
# promove ID a `verified`**: a régua continua sendo "comparado com dado de
# produção e bateu", e para esta família isso é permanentemente impossível.

RSpec.describe Structured::RemunerationCalculator do
  let(:project) { create(:project) }
  let(:company) { create(:company, project: project) }
  let(:tipo) { create(:structured_operation_type) }

  def operacao(valor:, **extra)
    create(:structured_operation, project: project, company: company,
                                  operation_type: tipo, operation_value: BigDecimal(valor), **extra)
  end

  def remuneracao(taxa)
    create(:remuneration, project: project, operation_type: tipo, value: BigDecimal(taxa))
  end

  # ====================================================================
  # E1…E5 — a fórmula, casa por casa
  # ====================================================================
  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO · fonte: `../sfg/app/models/receipt.rb:41-66`.
  describe 'goldens E1…E5 — `value = operation_value × (fee.to_f / 100.0)`' do
    # | # | capital | taxa | produto exato | gravado | por que este caso existe |
    # | E1 | 200.000,00 | 2,55 | 5100.0 | 5.100,00 | caso limpo |
    # | E2 | 1.234,56 | 2,55 | 31.48128 | 31,48 | truncamento comum |
    # | E3 | 87.654,32 | 1,75 | 1533.9506 | 1.533,95 | 4ª casa arredonda p/ baixo |
    # | E4 | 10.000,20 | 2,55 | 255.0051 | 255,01 | FRONTEIRA: 3ª casa é 5 |
    # | E5 | 99.999,99 | 7,77 | 7769.9992229999990000001 | 7.770,00 | artefato do float na 10ª casa |
    [
      ['E1', '200000.00', '2.55', '5100.00',  'caso limpo, sem arredondamento'],
      ['E2', '1234.56',   '2.55', '31.48',    'truncamento comum'],
      ['E3', '87654.32',  '1.75', '1533.95',  'a quarta casa arredonda para baixo'],
      ['E4', '10000.20',  '2.55', '255.01',   'FRONTEIRA — a terceira casa é 5'],
      ['E5', '99999.99',  '7.77', '7770.00',  'o artefato do float aparece na décima casa']
    ].each do |nome, capital, taxa, esperado, porque|
      it "#{nome}: #{capital} × #{taxa}% = #{esperado} (#{porque})" do
        remuneracao(taxa)
        resultado = described_class.calculate(operacao(valor: capital))

        expect(resultado[:status]).to eq(200)
        expect(resultado[:data][:value]).to eq(BigDecimal(esperado))
        # A taxa e o capital são FOTOGRAFIA: o recibo congela os dois.
        expect(resultado[:data][:fee]).to eq(BigDecimal(taxa))
        expect(resultado[:data][:operation_value]).to eq(BigDecimal(capital))
      end
    end

    it 'E5 — o produto CRU tem o artefato do float, e é ele que o arredondamento resolve' do
      # Este exemplo existe para o dia em que alguém trocar `fee.to_f / 100.0`
      # por `fee / 100` (BigDecimal). O valor final continuaria 7.770,00 e os
      # outros quatro goldens continuariam verdes — **a sequência de cálculo do
      # DEC-02 teria mudado sem nenhum teste reclamar**. Aqui reclama.
      cru = BigDecimal('99999.99') * (BigDecimal('7.77').to_f / 100.0)
      expect(cru.to_s('F')).to start_with('7769.99922299999')
      expect(Charges::ReceiptGenerator.round_value(cru)).to eq(BigDecimal('7770.00'))
    end
  end

  # ====================================================================
  # A política de arredondamento (tarefa 3.2)
  # ====================================================================
  describe 'política de arredondamento EXPLÍCITA — ROUND_HALF_UP, 2 casas' do
    it 'está declarada, e não deduzida do cast da coluna' do
      expect(Charges::ReceiptGenerator::ROUNDING_SCALE).to eq(2)
      expect(Charges::ReceiptGenerator::ROUNDING_MODE).to eq(BigDecimal::ROUND_HALF_UP)
    end

    it 'HALF_UP e não HALF_EVEN: 255,005 sobe para 255,01, não desce para 255,00' do
      # É a diferença que o `E4` mede na fronteira. `ROUND_HALF_EVEN` (o default
      # de banqueiro) devolveria 255,00 aqui e passaria despercebido em quatro
      # dos cinco goldens.
      expect(Charges::ReceiptGenerator.round_value(BigDecimal('255.005'))).to eq(BigDecimal('255.01'))
    end

    it 'arredonda SÓ o valor final — a taxa e o capital não são tocados' do
      remuneracao('1.7550')
      resultado = described_class.calculate(operacao(valor: '100000.00'))

      # `fee` guarda as 4 casas. Arredondá-la para 2 na origem transformaria
      # 1,7550% em 1,75% e mudaria o valor faturado — é a razão de
      # `remunerations.value` ser `decimal(7,4)` e não `decimal(15,2)` (F.5).
      expect(resultado[:data][:fee]).to eq(BigDecimal('1.7550'))
      expect(resultado[:data][:value]).to eq(BigDecimal('1755.00'))
    end
  end

  # ====================================================================
  # A sequência: o que NÃO entra na conta (T-D8 / Q-R17)
  # ====================================================================
  describe 'a remuneração é percentual FLAT, sem prazo nem pro-rata' do
    it 'operação de 30 dias e de 360 dias com o mesmo capital dão o MESMO valor' do
      remuneracao('2.55')
      curta = operacao(valor: '200000.00', issue_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 3, 31))
      longa = operacao(valor: '200000.00', issue_date: Date.new(2026, 3, 1), due_date: Date.new(2027, 2, 24))

      expect(described_class.calculate(curta)[:data][:value])
        .to eq(described_class.calculate(longa)[:data][:value])
    end

    it '`agreed_rate` NÃO é a taxa que remunera — mudá-la não move o valor' do
      # Q-R14 / BE-295. O modelo guarda uma "taxa acordada" que parece ser a
      # taxa e não é: quem remunera é `remunerations.value`. Sem este exemplo, a
      # primeira pessoa a ler `structured_operations.agreed_rate` vai usá-la.
      remuneracao('2.55')
      baixa = operacao(valor: '200000.00', agreed_rate: BigDecimal('0.01'))
      alta  = operacao(valor: '200000.00', agreed_rate: BigDecimal('99.99'))

      expect(described_class.calculate(baixa)[:data][:value]).to eq(BigDecimal('5100.00'))
      expect(described_class.calculate(alta)[:data][:value]).to eq(BigDecimal('5100.00'))
    end
  end

  # ====================================================================
  # `temp_id` — a identidade estável do candidato
  # ====================================================================
  describe '`temp_id`' do
    it 'operação estruturada usa a sigla EST' do
      rem = remuneracao('2.55')
      op = operacao(valor: '200000.00')
      resultado = described_class.calculate(op)

      expect(resultado[:data][:temp_id]).to eq("RCP-#{project.id}-EST-#{rem.id}-#{op.id}")
      expect(resultado[:data][:kind]).to eq(Receipt::KIND_STRUCTURED)
    end

    it 'operação de risco usa a sigla LIQ — o MESMO serviço, o outro lado (C3)' do
      controle = create(:risk_control, project: project, company: company)
      op = create(:risk_operation, risk_control: controle, operation_value: BigDecimal('200000.00'))
      rem = create(:remuneration, project: project, operation_type: controle.risk_operation_type,
                                  value: BigDecimal('2.55'))

      resultado = described_class.calculate(op)

      expect(resultado[:status]).to eq(200)
      expect(resultado[:data][:kind]).to eq(Receipt::KIND_RISK)
      expect(resultado[:data][:temp_id]).to eq("RCP-#{project.id}-LIQ-#{rem.id}-#{op.id}")
      expect(resultado[:data][:value]).to eq(BigDecimal('5100.00'))
    end
  end

  # ====================================================================
  # BE-294 — os dois caminhos de erro deixam de ser 500
  # ====================================================================
  describe 'erros de negócio (BE-294)' do
    it 'operação já faturada responde 409, não exceção não tratada' do
      remuneracao('2.55')
      recibo = create(:charge, project: project)
      op = operacao(valor: '200000.00')
      op.update_column(:receipt_id, create_receipt(op, recibo).id)

      resultado = described_class.calculate(op.reload)

      expect(resultado[:status]).to eq(409)
      expect(resultado[:error]).to eq(described_class::ALREADY_BILLED)
    end

    it 'projeto sem remuneração para o tipo responde 422 com mensagem de negócio' do
      resultado = described_class.calculate(operacao(valor: '200000.00'))

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to eq(described_class::NO_REMUNERATION)
    end

    it 'a recusa por recibo vem ANTES da busca de remuneração — a ordem do legado' do
      # Sem remuneração cadastrada E já faturada: o legado recusa pelo recibo
      # (passo 1), não pela remuneração (passo 4). A ordem é observável no
      # status devolvido, e por isso é testável.
      recibo_charge = create(:charge, project: project)
      op = operacao(valor: '200000.00')
      op.update_column(:receipt_id, create_receipt(op, recibo_charge, sem_remuneracao: true).id)

      expect(described_class.calculate(op.reload)[:status]).to eq(409)
    end

    it 'operação nula não derruba a requisição' do
      expect(described_class.calculate(nil)[:status]).to eq(422)
    end
  end

  # ====================================================================
  # E7 — candidatos (BE-306)
  # ====================================================================
  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO · fonte: `../sfg/app/models/receipt.rb:27-35`
  # (`available_for_receipt`, filtrando por `receipt_id`).
  describe 'golden E7 — candidatos a cobrança' do
    it 'operação ENCERRADA continua candidata (Q-R18) — a ausência é replicada' do
      remuneracao('2.55')
      encerrada = operacao(valor: '200000.00', is_ended: true)

      lista = described_class.candidates(project)[:data]

      expect(lista.map { |c| c[:operation_id] }).to include(encerrada.id)
    end

    it 'operação JÁ faturada sai da lista — é o predicado `receipt_id: nil`' do
      remuneracao('2.55')
      livre = operacao(valor: '200000.00')
      faturada = operacao(valor: '100000.00')
      charge = create(:charge, project: project)
      faturada.update_column(:receipt_id, create_receipt(faturada, charge).id)

      ids = described_class.candidates(project)[:data].map { |c| c[:operation_id] }

      expect(ids).to include(livre.id)
      expect(ids).not_to include(faturada.id)
    end

    it 'cada candidato já vem COM o valor calculado — a tela não multiplica nada' do
      remuneracao('2.55')
      operacao(valor: '1234.56')

      candidato = described_class.candidates(project)[:data].first

      expect(candidato[:value]).to eq(BigDecimal('31.48'))
      expect(candidato[:persisted]).to be(false)
    end

    it 'tipo sem remuneração no projeto não produz candidato' do
      outro_tipo = create(:structured_operation_type)
      create(:structured_operation, project: project, company: company, operation_type: outro_tipo,
                                    operation_value: BigDecimal('200000.00'))

      expect(described_class.candidates(project)[:data]).to be_empty
    end

    it 'operação de OUTRO projeto nunca entra na lista (C1)' do
      remuneracao('2.55')
      outro = create(:project)
      create(:structured_operation, project: outro,
                                    company: create(:company, project: outro),
                                    operation_type: tipo, operation_value: BigDecimal('500000.00'))

      expect(described_class.candidates(project)[:data]).to be_empty
    end

    it 'pagina quando a página é pedida, e devolve tudo quando não é (BE-306)' do
      remuneracao('2.55')
      3.times { |i| operacao(valor: '1000.00', issue_date: Date.new(2026, 3, i + 1)) }

      expect(described_class.candidates(project)[:data].size).to eq(3)
      expect(described_class.candidates(project, page: 1, per_page: 2)[:data].size).to eq(2)
      expect(described_class.candidates(project, page: 2, per_page: 2)[:data].size).to eq(1)
    end

    it '`operation_type_type` desconhecido NÃO CHEGA ao banco — o domínio é fechado lá' do
      # No legado `operation_type_type` era string livre: um valor arbitrário
      # entrava, `Remuneration#operation_class` devolvia `nil` e o
      # `nil.where(...)` seguinte derrubava a requisição com 500; `beauty_type`
      # devolvia a string `"???"`, que ia parar na coluna `kind` do recibo e
      # virava um recibo que nenhum filtro achava.
      #
      # Aqui o `check_constraint` de `DB-284` recusa a linha **no banco**, e é
      # por isso que o cenário de 500 não é mais alcançável nem contornando o
      # model com `update_all`.
      rem = remuneracao('2.55')

      expect { Remuneration.where(id: rem.id).update_all(operation_type_type: 'Inexistente') }
        .to raise_error(ActiveRecord::StatementInvalid, /remunerations_operation_type_type_check/)
    end

    it 'e mesmo assim o serviço tolera a classe desconhecida, em vez de explodir' do
      # Cinto e suspensório: a constraint é a proteção real, mas a coluna existe
      # desde antes dela e um banco restaurado de antes da migration não a tem.
      # `operation_class` devolve `nil` e o serviço **pula a linha**.
      orfa = Remuneration.new(project: project, operation_type_type: 'Inexistente',
                              operation_type_id: SecureRandom.uuid, value: BigDecimal('2.55'),
                              title: 'órfã')

      expect(orfa.operation_class).to be_nil
      expect(orfa.beauty_type).to be_nil
      expect(orfa.candidate_operations).to be_empty
    end
  end

  # Cria um recibo persistido para a operação, sem passar pela fórmula (o
  # objetivo do exemplo é o ESTADO "já faturada", não o cálculo).
  def create_receipt(operation, charge, sem_remuneracao: false)
    rem = sem_remuneracao ? nil : Remuneration.find_by(project_id: project.id)
    Receipt.create!(
      project: project, charge: charge, operation: operation,
      remuneration_id: rem&.id || create(:remuneration, project: create(:project)).id,
      kind: Receipt::KIND_STRUCTURED, title: 'Recibo', fee: BigDecimal('2.55'),
      operation_value: operation.operation_value, value: BigDecimal('1.00'),
      user_id: create(:user).id, date: operation.issue_date, operation_title: operation.title
    )
  end
end
