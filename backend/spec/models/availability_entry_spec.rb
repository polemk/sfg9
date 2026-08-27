# frozen_string_literal: true

require 'rails_helper'

# S11 — **os golden tests do motor de números da disponibilidade**.
#
# ## Como os valores esperados foram obtidos
#
# Lendo o legado linha a linha: `../sfg/app/models/availability_entry.rb`
# (`:17-24` o pipeline de gravação, `:186-215` as fórmulas) e
# `../sfg/app/decorators/models/date_decorator.rb` (dias úteis). O legado é
# Rails 6.1 e **não tem banco disponível neste ambiente**, então os números
# foram derivados da fonte, não de uma execução — está dito aqui para que
# ninguém leia "golden" como "capturado rodando".
#
# ## O que estes testes protegem
#
# Quatro decisões do usuário, todas mandando **replicar**, todas amparadas pelo
# **DEC-30** (o legado é sistema validado):
#
#  - **DEC-24** — o decaimento composto (D-02);
#  - **DEC-26** — as duas semânticas de soma na mesma tela (D-08);
#  - **DEC-27** — as duas métricas de "total";
#  - **DEC-28** — dias úteis sem feriados (D-03).
#
# **Um teste que exija a fórmula "certa" está errado contra estas DECs.**
#
# ## ⚠ O que É validado por produção, e o que NÃO é
#
# A análise do dump (26/08/2026) mostrou que **a última migration aplicada em
# produção é de 25/05/2022** e que 24 migrations nunca subiram. Três são desta
# fatia, e elas partem estes golden tests ao meio:
#
# | Regra | Fundamento |
# | ----- | ---------- |
# | hierarquia, soma do nó com filhos, cumulatividade, sinal de débito, saldo acumulado | **três anos de uso real** — 23.674 lançamentos, 2.705 padrões, dado até 09/05/2025. DEC-30 vale por inteiro |
# | **correção por dias úteis (DEC-24 / D-02)** | `add_original_value_column_to_availability_entries` e `add_is_adjusted_column_to_availability_templates` **nunca rodaram**. Em produção não há `original_value` nem `is_adjusted`: **nenhum usuário jamais viu um valor corrigido** |
# | **consolidação geral / soma bruta (DEC-26)** | `add_company_column_to_availability_entries` **nunca rodou**. Sem `company_id` não há multiempresa e não há espelho: `update_mirror!` nunca executou |
#
# Os exemplos das duas últimas linhas continuam aqui e continuam travando o
# comportamento — o DEC-22 mantém o escopo completo e as DECs do usuário estão
# de pé. O que muda é **o que eles provam**: não "isto é o que produção faz",
# e sim "isto é o que o código de 2022 faria se tivesse subido". Onde não há
# produção, o golden test não tem oráculo — ele tem uma fonte.
#
# Cada exemplo afetado está marcado com `NUNCA EXECUTADO EM PRODUÇÃO`.
RSpec.describe AvailabilityEntry do
  let(:project) { create(:project) }
  let(:company) { create(:company, project: project) }
  let(:outra_empresa) { create(:company, project: project) }
  let(:data) { Date.new(2026, 8, 14) } # 10 de 21 dias úteis decorridos

  def padrao(**atributos)
    create(:project_availability_template, project: project, **atributos)
  end

  def lancar(template, valor, empresa: company, em: data)
    resultado = Availability::EntryService.create(
      project: project,
      attrs: { availability_template_id: template.id, company_id: empresa.id, date: em, value: valor }
    )
    raise "falhou: #{resultado[:error]}" unless resultado[:status] == 201

    resultado[:data]
  end

  # Grava numa célula que já existe — inclusive nas que a cascata materializou.
  def atualizar(template, valor, empresa: company, em: data)
    entrada = described_class.find_by!(project_id: project.id, company_id: empresa.id,
                                       availability_template_id: template.id, date: em)
    resultado = Availability::EntryService.update(project: project, id: entrada.id,
                                                  attrs: { value: valor })
    raise "falhou: #{resultado[:error]}" unless resultado[:status] == 200

    resultado[:data]
  end

  # -------------------------------------------------------------------
  # ⚠ NUNCA EXECUTADO EM PRODUÇÃO — as duas migrations que criam `original_value`
  # e `is_adjusted` são de ago/2022 e não subiram. O que estes exemplos travam é
  # a leitura do código, não um comportamento observado.
  describe 'DEC-24 / D-02 — o decaimento composto da correção por dias úteis' do
    let(:corrigido) { padrao(is_adjusted: true) }

    it 'aplica o multiplicador de dias úteis na primeira gravação' do
      entrada = lancar(corrigido, 1000)

      # `original_value` recebe o valor digitado; `value` recebe a correção.
      # 1000 × 10/21 = 476,190476… → decimal(15,2) grava 476,19.
      expect(entrada.original_value).to eq(1000)
      expect(entrada.value).to eq(BigDecimal('476.19'))
    end

    # **O mecanismo exato do D-02, e ele é mais estreito do que a descrição do
    # defeito sugere.** O `before_validation` do legado
    # (`availability_entry.rb:20`) só regrava `original_value` quando `value`
    # **mudou**; reenviar um número idêntico é `no-op` nos dois sistemas.
    #
    # O que fazia "salvar de novo multiplicar de novo" na prática era a
    # combinação com a tela: o campo vinha preenchido com o valor **já
    # corrigido** (`_widget.html.erb:56,131`, `value: e.value`) e a máscara
    # `money-value` o devolvia como texto pt-BR — `"476,19"`, que o cast decimal
    # do Rails lê como **476,0**. Ou seja: todo envio chegava com um número
    # ligeiramente diferente, e a correção incidia sobre o valor já corrigido.
    #
    # No ai9 o número trafega exato (`MoneyInput` + `BigDecimal` no Grape),
    # então um reenvio idêntico é reenvio idêntico. **A regra do model é
    # replicada; a corrupção da máscara não** — ela é defeito de tela, não
    # fórmula, e a DEC-24 fala da fórmula.
    it 'reaplica o multiplicador sobre o valor DIGITADO — o D-02, replicado (DEC-24)' do
      entrada = lancar(corrigido, 1000)

      # Reenvio idêntico: nada muda, porque `value` não mudou.
      Availability::EntryService.update(project: project, id: entrada.id,
                                        attrs: { value: BigDecimal('476.19') })
      expect(entrada.reload.original_value).to eq(1000)
      expect(entrada.value).to eq(BigDecimal('476.19'))

      # Um centavo de diferença basta: a tela mostrava 476,19 e o usuário
      # reenvia 476,20 — a correção incide sobre o valor **já corrigido**.
      # 476,20 × 10/21 = 226,7619… → 226,76.
      Availability::EntryService.update(project: project, id: entrada.id,
                                        attrs: { value: BigDecimal('476.20') })
      entrada.reload

      expect(entrada.original_value).to eq(BigDecimal('476.20'))
      expect(entrada.value).to eq(BigDecimal('226.76'))
    end

    it 'não corrige nada quando o padrão não é ajustado' do
      entrada = lancar(padrao(is_adjusted: false), 1000)

      expect(entrada.value).to eq(1000)
      # Sem correção, `original_value` sequer é tocado — mesmo comportamento do
      # `if self.changed.include?('value') && self.should_adjust?` do legado.
      expect(entrada.original_value).to eq(0)
    end
  end

  # -------------------------------------------------------------------
  describe 'DEC-26 / D-08 — as duas semânticas de soma convivem' do
    # ⚠ NUNCA EXECUTADO EM PRODUÇÃO — `availability_entries.company_id` não
    # existe lá, então `mirror?`/`update_mirror!` jamais rodaram.
    it 'a consolidação geral soma BRUTO, ignorando cumulatividade e sinal' do
      debito_nao_cumulativo = padrao(operation_type: 'D', is_cumulative: false)

      lancar(debito_nao_cumulativo, 100, empresa: company)
      lancar(debito_nao_cumulativo, 40, empresa: outra_empresa)

      espelho = described_class.find_by(project_id: project.id, company_id: nil,
                                        availability_template_id: debito_nao_cumulativo.id, date: data)

      expect(espelho).to be_present
      expect(espelho.is_consolidation).to be(true)
      # 140, e não -140 nem 0: o `mirrored_entries.sum(:value)` do legado é
      # bruto (`availability_entry.rb:188`).
      expect(espelho.value).to eq(140)
    end

    # ✔ VALIDADO POR PRODUÇÃO — três anos, 23.674 lançamentos. DEC-30 por inteiro.
    it 'o nó com filhos APLICA cumulatividade e sinal' do
      pai = padrao
      credito = padrao(parent_template_id: pai.id, operation_type: 'C')
      debito = padrao(parent_template_id: pai.id, operation_type: 'D')
      fora_da_soma = padrao(parent_template_id: pai.id, operation_type: 'C', is_cumulative: false)

      lancar(credito, 100)
      lancar(debito, 30)
      lancar(fora_da_soma, 999)

      entrada_pai = described_class.find_by(project_id: project.id, company_id: company.id,
                                            availability_template_id: pai.id, date: data)

      # 100 (crédito) − 30 (débito) + 0 (não cumulativo) = 70.
      expect(entrada_pai.value).to eq(70)
    end

    it 'o nó intermediário entra no pai pelo próprio valor, SEM o sinal — réplica de `:191`' do
      avo = padrao
      pai = padrao(parent_template_id: avo.id, operation_type: 'D')
      neto = padrao(parent_template_id: pai.id, operation_type: 'C')

      lancar(neto, 100)

      entrada_pai = described_class.find_by(availability_template_id: pai.id, company_id: company.id,
                                            date: data)
      entrada_avo = described_class.find_by(availability_template_id: avo.id, company_id: company.id,
                                            date: data)

      expect(entrada_pai.value).to eq(100)
      # O legado escreve `e.has_child? ? e.value : e.value * sinal`: o nó com
      # filhos entra POSITIVO mesmo sendo de débito. Réplica consciente.
      expect(entrada_avo.value).to eq(100)
    end
  end

  # -------------------------------------------------------------------
  describe 'DEC-27 — `value` e `virtual_value` são métricas DIFERENTES' do
    # ✔ VALIDADO POR PRODUÇÃO.
    it 'no 1º nível, `virtual_value` acumula os padrões base anteriores, com sinal' do
      primeiro = padrao(operation_type: 'C')
      segundo = padrao(operation_type: 'D')
      terceiro = padrao(operation_type: 'C')

      # **A primeira gravação MATERIALIZA os padrões base seguintes** — é o
      # `update_virtual_value_for_next_levels` do legado, que cria a entrada de
      # cada nível posterior para recalcular o acumulado. Por isso os dois
      # seguintes são `update`, não `create`: a célula já existe.
      lancar(primeiro, 100)
      atualizar(segundo, 40)
      atualizar(terceiro, 10)

      valores = described_class.where(company_id: company.id, date: data)
                               .index_by(&:availability_template_id)

      expect(valores[primeiro.id].virtual_value).to eq(100)          # +100
      expect(valores[segundo.id].virtual_value).to eq(60)            # -40 + 100
      expect(valores[terceiro.id].virtual_value).to eq(70)           # +10 + 100 - 40

      # E `value` continua sendo o valor bruto de cada um — duas métricas, dois
      # rótulos ("Total bruto" × "Saldo acumulado"), nenhum número mudado.
      expect(valores[segundo.id].value).to eq(40)
    end

    it 'abaixo do 1º nível `virtual_value` é igual a `value`' do
      pai = padrao
      filho = padrao(parent_template_id: pai.id)

      entrada = lancar(filho, 100)
      expect(entrada.virtual_value).to eq(entrada.value)
    end
  end

  # -------------------------------------------------------------------
  describe 'DC-28 — `operation_type` é conjunto FECHADO' do
    it 'recusa um código desconhecido em vez de tratá-lo como crédito' do
      registro = build(:project_availability_template, project: project, operation_type: 'X')

      expect(registro).not_to be_valid
      expect(registro.errors[:operation_type].join).to include('natureza')
    end

    it 'compara o CÓDIGO, não a string traduzida' do
      expect(padrao(operation_type: 'D')).to be_debit
      expect(padrao(operation_type: 'C')).not_to be_debit
      # `S` e `M` não são débito nem crédito — no legado, por comparar
      # `beauty_op_type`, qualquer coisa que não fosse "Débito" somava POSITIVO,
      # o que dava o mesmo efeito por acaso. Aqui é explícito.
      expect(padrao(operation_type: 'S')).not_to be_debit
      expect(padrao(operation_type: 'S')).not_to be_credit
    end
  end

  # -------------------------------------------------------------------
  describe 'DC-30 / BE-130 — ler a grade NUNCA cria registro' do
    it 'a contagem de lançamentos é a mesma antes e depois de montar a grade' do
      pai = padrao
      padrao(parent_template_id: pai.id)
      padrao

      antes = described_class.count
      Availability::GridService.grid(project: project, date: data, company_id: company.id)
      Availability::GridService.panel(project: project, month: 8, year: 2026, company_id: company.id)

      expect(described_class.count).to eq(antes)
    end
  end

  # -------------------------------------------------------------------
  describe 'DC-26 / BE-124 — excluir lançamento de 1º nível não cria o pai' do
    it 'não materializa o pai que ainda não existe' do
      pai = padrao
      filho = padrao(parent_template_id: pai.id)
      entrada = lancar(filho, 100)

      # O pai foi criado pela gravação (materialização por gravação explícita, o
      # que a DC-30 permite). Apago-o para reproduzir o cenário do legado.
      described_class.where(availability_template_id: pai.id).delete_all

      Availability::EntryService.destroy(project: project, id: entrada.id)

      expect(described_class.where(availability_template_id: pai.id)).to be_empty
    end
  end

  # -------------------------------------------------------------------
  describe 'unicidade garantida pelo ÍNDICE (BE-131 / DB-123)' do
    it 'recusa duas gravações do mesmo (projeto, empresa, padrão, data)' do
      alvo = padrao
      lancar(alvo, 100)

      resultado = Availability::EntryService.create(
        project: project,
        attrs: { availability_template_id: alvo.id, company_id: company.id, date: data, value: 200 }
      )

      expect(resultado[:status]).to eq(422)
    end

    it 'recusa duas linhas de consolidação geral, apesar do NULL em `company_id`' do
      alvo = padrao
      lancar(alvo, 100)
      espelho = described_class.find_by(availability_template_id: alvo.id, company_id: nil)

      duplicata = described_class.new(project: project, company_id: nil, availability_template: alvo,
                                      date: espelho.date, value: 1)

      # O Postgres trata cada NULL como distinto num índice único comum: sem o
      # índice parcial `… WHERE company_id IS NULL`, esta linha passaria.
      expect { duplicata.save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # -------------------------------------------------------------------
  describe 'contrato C1 — escopo' do
    it 'recusa padrão de outro projeto' do
      outro = create(:project)
      alheio = create(:project_availability_template, project: outro)

      registro = described_class.new(project: project, company: company,
                                     availability_template: alheio, date: data, value: 1)

      expect(registro).not_to be_valid
      expect(registro.errors[:availability_template_id].join).to include('outro projeto')
    end

    it 'recusa empresa de outro projeto' do
      outra = create(:company, project: create(:project))
      registro = described_class.new(project: project, company: outra,
                                     availability_template: padrao, date: data, value: 1)

      expect(registro).not_to be_valid
      expect(registro.errors[:company_id].join).to include('não pertence')
    end

    # DEC-112 / DB-130 — CARIMBO, não derivação. E o carimbo NÃO é
    # ressincronizado quando a marca do projeto muda: só `companies` é.
    it 'carimba a marca de gestão do projeto e NÃO a ressincroniza depois (D-30)' do
      project.update_columns(has_safegold_management: true)
      entrada = lancar(padrao, 10)
      expect(entrada.has_safegold_management).to be(true)

      project.update_columns(has_safegold_management: false)
      # Nada re-carimba a linha já gravada — é a foto do momento.
      expect(entrada.reload.has_safegold_management).to be(true)
      expect(described_class.column_names).to include('has_safegold_management')
    end
  end

  # S11, tarefa **F.2** / **DB-567** — o contrato C4, agora que a S6 entregou a
  # base. A tarefa pede herdar a base de lançamento **sem redefinir a situação**,
  # e diz o verificável: "o valor persistido é o mesmo dos recebíveis".
  #
  # O que isto trava, e o que deliberadamente NÃO trava:
  #
  #  - trava que existe **um** de-para de situação no sistema, e que os dois
  #    lançamentos leem o MESMO objeto congelado — não duas cópias que possam
  #    divergir no dia em que alguém renomear um rótulo;
  #  - trava que `availability_entries` **não ganhou** coluna de situação para
  #    "usar a herança". A célula da grade é valor, não título a conferir;
  #    criar `status` aqui seria feature nova travestida de paridade (DEC-09).
  describe 'F.2 / DB-567 — herda `Entry` sem redefinir a situação (contrato C4)' do
    it 'herda da base abstrata de lançamento construída pela S6' do
      expect(described_class.superclass).to eq(Entry)
      expect(Entry.abstract_class?).to be(true)
      # Base abstrata NÃO é STI: a tabela continua sendo a própria, sem `type`.
      expect(described_class.table_name).to eq('availability_entries')
      expect(described_class.column_names).not_to include('type')
    end

    it 'usa o MESMO de-para de situação dos recebíveis, e não uma segunda cópia' do
      expect(ReceivableEntry.superclass).to eq(Entry)
      # `equal?` e não `eq`: tem de ser o mesmo objeto, não um igual.
      expect(described_class::LEGACY_STATUS_LABELS)
        .to equal(ReceivableEntry::LEGACY_STATUS_LABELS)
      expect(described_class::STATUSES).to equal(ReceivableEntry::STATUSES)
      expect(described_class.status_from_legacy('OK')).to eq('ok')
      expect(described_class.status_from_legacy('Diferença')).to eq('difference')
      expect(described_class.status_from_legacy('OK'))
        .to eq(ReceivableEntry.status_from_legacy('OK'))
    end

    it 'NÃO define situação própria — nem coluna, nem enum, nem constante nova' do
      expect(described_class.column_names).not_to include('status')
      expect(described_class.defined_enums).to eq({})
      # A constante não pode estar declarada AQUI: se estiver, é a segunda cópia
      # que o contrato C4 existe para impedir.
      expect(described_class.const_defined?(:STATUSES, false)).to be(false)
      expect(described_class.const_defined?(:LEGACY_STATUS_LABELS, false)).to be(false)
    end
  end
end
