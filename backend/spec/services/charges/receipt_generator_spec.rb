# frozen_string_literal: true

require 'rails_helper'

# S6 / **BE-188**, tarefas **2.35** e **4.27** — o **golden do recibo**: o número
# que vai na fatura.
#
# ## Por que este arquivo só existe agora
#
# As duas tarefas ficaram abertas desde o fechamento da S6 com o rótulo
# *"ESCRITO, SEM GOLDEN REAL — depende da S8"*: `Charges::ReceiptGenerator`
# existia inteiro, mas `Remuneration` é da **S8** e não havia model nem tabela.
# O serviço parava num 422 nomeando a fatia, e o único teste possível era o
# teste desse 422. A S8 entregou a remuneração; o golden passou a ser possível
# e é este.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b / DEC-115
#
# FONTE, não ORÁCULO.
#
# `receipts` e `remunerations` estão entre as **24 migrations que nunca
# subiram** (`analise-dump-producao.md` §1). Em três anos de produção
# (25/05/2022 → 31/05/2025) **nenhum recibo foi emitido**. Não existe uma linha
# gravada contra a qual conferir.
#
# O que estes exemplos travam, então, é a **leitura do código de 2022**
# (`../sfg/app/models/receipt.rb:41-66`), conferida executando a mesma
# aritmética Ruby — e **não** comportamento validado por uso. A diferença está
# escrita aqui para que ninguém leia "golden" como "provado em produção".
#
# **Encerramento (DEC-115, 26/08/2026):** a tarefa **13.5** pedia reconferir
# estes goldens *"contra o legado, com o dump carregado"*. Ela foi **reescrita**,
# não adiada: o usuário confirmou que não existe outra base (*"nao tem, a tabela
# de excel que tinha foi perdida"*), e a conferência que vale passou a ser
# **contra a FONTE de 2022** — que é o que este arquivo faz. **Nada disso
# promove ID a `verified`**: a régua continua sendo "comparado com dado de
# produção e bateu", e para esta família isso é permanentemente impossível.

#
# ## O que o `remuneration_calculator_spec.rb` (S8) já trava, e não se repete
#
# Aquele arquivo é o golden da **fórmula** vista pela fachada da S8. Este é o
# golden do **recibo**: o mesmo número depois de atravessar a coluna
# `decimal(15,2)`, mais as três fotografias, o tipo desconhecido e a recusa de
# operação já faturada — a metade que pertence à S6.
# As mesmas cinco linhas do `design.md` §7 da S8, aqui exercidas do lado da
# **persistência**: o que interessa nesta fatia é o número que a coluna guarda.
GOLDENS_DO_RECIBO = [
  ['E1', '200000.00', '2.55', '5100.00',  'caso limpo, sem arredondamento'],
  ['E2', '1234.56',   '2.55', '31.48',    'truncamento comum'],
  ['E3', '87654.32',  '1.75', '1533.95',  'a quarta casa arredonda para baixo'],
  ['E4', '10000.20',  '2.55', '255.01',   'FRONTEIRA — a terceira casa é 5'],
  ['E5', '99999.99',  '7.77', '7770.00',  'o artefato do float aparece na décima casa']
].freeze

RSpec.describe Charges::ReceiptGenerator do
  let(:project) { create(:project) }
  let(:company) { create(:company, project: project) }
  let(:tipo) { create(:structured_operation_type) }
  let(:autor) { create(:user) }

  def operacao(valor:, **extra)
    create(:structured_operation, project: project, company: company, operation_type: tipo,
                                  operation_value: BigDecimal(valor), **extra)
  end

  def remuneracao(taxa)
    create(:remuneration, project: project, operation_type: tipo, value: BigDecimal(taxa))
  end

  # ====================================================================
  # 4.27 — o golden do recibo, atravessando a coluna
  # ====================================================================
  describe 'golden do recibo — `value = operation_value × (fee / 100)` GRAVADO' do
    GOLDENS_DO_RECIBO.each do |nome, capital, taxa, esperado, porque|
      it "#{nome}: #{capital} × #{taxa}% grava #{esperado} em decimal(15,2) (#{porque})" do
        rem = remuneracao(taxa)
        op = operacao(valor: capital)

        montado = described_class.build_attributes(operation: op, remuneration: rem, actor: autor)
        expect(montado[:status]).to eq(200)

        # O recibo é CRIADO: o golden só vale se sobreviver ao INSERT, que é
        # onde o legado deixava o arredondamento acontecer por acidente.
        recibo = Receipt.create!(montado[:data])
        expect(recibo.reload.value).to eq(BigDecimal(esperado))
        expect(recibo.value.to_s('F').split('.').last.length).to be <= 2
      end
    end

    it 'a coluna é mesmo `decimal(15,2)` — a escala do legado, preservada' do
      # `../sfg/db/migrate/20220802225011_create_receipts.rb:12-13`.
      col = Receipt.columns_hash['value']
      expect([col.precision, col.scale]).to eq([15, 2])
      expect(Receipt.columns_hash['operation_value'].precision).to eq(15)
    end
  end

  # ====================================================================
  # 2.35 — a SEQUÊNCIA: `decimal × float`, replicada (DEC-02 / D-B14)
  # ====================================================================
  describe 'DEC-02 / D-B14 — a multiplicação é `decimal × float`, não `decimal × decimal`' do
    it 'o produto CRU de E5 carrega o artefato do float na décima casa' do
      # `receipt.rb:63` — `self.operation_value * (self.fee.to_f / 100.0)`.
      # `operation_value` é BigDecimal, `fee.to_f / 100.0` é Float.
      cru = BigDecimal('99999.99') * (BigDecimal('7.77').to_f / 100.0)
      expect(cru.to_s('F')).to start_with('7769.99922299999')
      # A mesma conta em BigDecimal puro NÃO tem o artefato — é a prova de que
      # a sequência importa, mesmo quando o valor final coincide.
      exato = BigDecimal('99999.99') * (BigDecimal('7.77') / 100)
      expect(exato).to eq(BigDecimal('7769.999223'))
      expect(cru).not_to eq(exato)
    end

    it 'a política EXPLÍCITA reproduz o cast da coluna — medido no Postgres, golden a golden' do
      # **É esta a prova que faltava.** No legado ninguém arredonda: quem corta
      # em 2 casas é o cast de `decimal(15,2)` no INSERT. Aqui o corte é
      # declarado (`ROUND_HALF_UP`, 2 casas). Os dois só podem conviver se
      # produzirem o MESMO número — e a comparação é feita mandando o produto
      # cru para o próprio banco.
      GOLDENS_DO_RECIBO.each do |nome, capital, taxa, esperado, _|
        cru = BigDecimal(capital) * (BigDecimal(taxa).to_f / 100.0)
        pelo_banco = ActiveRecord::Base.connection.select_value(
          ActiveRecord::Base.sanitize_sql_array(['SELECT CAST(? AS numeric(15,2))', cru.to_s('F')])
        )
        expect(BigDecimal(pelo_banco.to_s)).to eq(BigDecimal(esperado)), nome
        expect(described_class.round_value(cru)).to eq(BigDecimal(pelo_banco.to_s)), nome
      end
    end

    it 'a taxa é congelada com as 4 casas — arredondá-la na origem mudaria a fatura' do
      rem = remuneracao('1.7550')
      montado = described_class.build_attributes(operation: operacao(valor: '100000.00'),
                                                 remuneration: rem, actor: autor)
      expect(montado[:data][:fee]).to eq(BigDecimal('1.7550'))
      expect(Receipt.create!(montado[:data]).reload.fee).to eq(BigDecimal('1.7550'))
    end
  end

  # ====================================================================
  # 2.35 — tipo de operação desconhecido FALHA (o fim do `"???"`)
  # ====================================================================
  describe 'tipo de operação desconhecido falha, em vez de virar "???"' do
    # `../sfg/app/models/remuneration.rb:38-46` — o `beauty_type` terminava num
    # `else` que devolvia a string `"???"`. Ela ia para `receipts.kind`,
    # atravessava o `validates :kind, presence: true` e virava um recibo que
    # nenhum filtro (`Receipt.risk` / `Receipt.structured`) encontrava — invisível
    # no extrato e invisível no total da cobrança.
    it 'o de-para só conhece as duas classes reais' do
      expect(Receipt.kind_for_operation_type('RiskOperation')).to eq('LIQ')
      expect(Receipt.kind_for_operation_type('StructuredOperation')).to eq('EST')
      expect(Receipt.kind_for_operation_type('Company')).to be_nil
      expect(Receipt.kind_for_operation_type(nil)).to be_nil
    end

    it 'gerar recibo sobre classe desconhecida devolve 422 nomeando a classe' do
      estranha = create(:company, project: project)
      def estranha.operation_value = BigDecimal('1000.00')
      def estranha.receipt_id = nil

      resultado = described_class.build_attributes(operation: estranha,
                                                   remuneration: remuneracao('2.55'), actor: autor)

      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include('Company')
      expect(resultado[:error]).to include('Tipo de operação desconhecido')
    end

    it 'e a coluna `kind` recusa "???" no banco — a segunda trava' do
      recibo = Receipt.new(project_id: project.id, user_id: autor.id, kind: '???',
                           title: 'x', fee: 1, operation_value: 1, value: 1)
      expect(recibo).not_to be_valid
      expect(recibo.errors[:kind]).to be_present
    end
  end

  # ====================================================================
  # 2.35 — a recusa de operação já faturada, e a ORDEM dos dois erros
  # ====================================================================
  describe 'operação já faturada' do
    it 'devolve 422 em vez de levantar ArgumentError dentro de um callback (500)' do
      # `receipt.rb:42` — `raise ArgumentError` num `before_validation`.
      rem = remuneracao('2.55')
      op = operacao(valor: '200000.00')
      recibo = Receipt.create!(described_class.build_attributes(operation: op, remuneration: rem,
                                                                actor: autor)[:data])
      op.update!(receipt_id: recibo.id)

      resultado = described_class.build_attributes(operation: op.reload, remuneration: rem, actor: autor)
      expect(resultado[:status]).to eq(422)
      expect(resultado[:error]).to include('Já existe um recibo')
    end
  end

  # ====================================================================
  # As três fotografias (DB-164) — o que o recibo CONGELA
  # ====================================================================
  describe 'as três fotografias do dia do recibo' do
    it 'capital, data e título ficam como estavam, mesmo depois de a operação mudar' do
      rem = remuneracao('2.55')
      op = operacao(valor: '200000.00', title: 'Operação de março', issue_date: Date.new(2026, 3, 1))
      recibo = Receipt.create!(described_class.build_attributes(operation: op, remuneration: rem,
                                                                actor: autor)[:data])

      op.update!(operation_value: BigDecimal('900000.00'), title: 'Operação reavaliada')

      expect(recibo.reload.operation_value).to eq(BigDecimal('200000.00'))
      expect(recibo.value).to eq(BigDecimal('5100.00'))
      expect(recibo.operation_title).to eq('Operação de março')
      expect(recibo.date).to eq(Date.new(2026, 3, 1))
    end

    it '`date` NULA não impede o recibo (FE-184 / B-08)' do
      # A data nula NÃO vem da operação estruturada — `issue_date` é
      # `validates presence` lá (`structured_operation.rb:96`, replicando o
      # legado). Ela vem do **par estático** da operação de risco (B-08 da S5),
      # que nasce sem datas de propósito. É esse o caso que quebrava a tela.
      controle = create(:risk_control, project: project, company: company)
      op = create(:risk_operation, risk_control: controle, is_static: true,
                                   issue_date: nil, due_date: nil,
                                   operation_value: BigDecimal('200000.00'))
      rem = create(:remuneration, project: project, operation_type: controle.risk_operation_type,
                                  value: BigDecimal('2.55'))
      montado = described_class.build_attributes(operation: op, remuneration: rem, actor: autor)

      expect(montado[:status]).to eq(200)
      expect(montado[:data][:date]).to be_nil
      expect(Receipt.create!(montado[:data]).reload.date).to be_nil
    end
  end

  # ====================================================================
  # Contrato C3 — o OUTRO lado da hierarquia (LIQ)
  # ====================================================================
  describe 'a mesma fórmula na classe LIQ (operação de risco)' do
    it 'E1 vale igual do lado do risco, com `kind` LIQ e `temp_id` próprio' do
      controle = create(:risk_control, project: project, company: company)
      op = create(:risk_operation, risk_control: controle, operation_value: BigDecimal('200000.00'))
      rem = create(:remuneration, project: project, operation_type: controle.risk_operation_type,
                                  value: BigDecimal('2.55'))

      montado = described_class.build_attributes(operation: op, remuneration: rem, actor: autor)

      expect(montado[:data][:kind]).to eq('LIQ')
      expect(montado[:data][:value]).to eq(BigDecimal('5100.00'))
      expect(montado[:data][:temp_id]).to eq("RCP-#{project.id}-LIQ-#{rem.id}-#{op.id}")
    end
  end
end
