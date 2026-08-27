# frozen_string_literal: true

require 'rails_helper'

# S14 — os quatro conversores das tabelas que **nunca existiram em produção**
# (DEC-103b): garantia de projeto, prorrogação de risco, operação estruturada e
# remuneração.
#
# As quatro migrations que as criam estão entre as **24 que nunca subiram**: a
# última aplicada em produção é de 25/05/2022 e o sistema rodou em uso até
# 31/05/2025. Conferido no dump: nenhuma das quatro relações existe.
#
# Testar conversor de tabela vazia parece cerimônia, e não é — é o único lugar
# onde o mapeamento fica travado. No dia em que o cliente rodar as migrations
# pendentes, quem carregar não vai ter tempo de redescobrir que
# `original_balance` é gravado negativo, que `operation_type_id` é polimórfico,
# ou que o model de prorrogação **reescreve** o dado da origem ao criar.
#
# E é isso que estes testes travam: as decisões, não a plumbing.
RSpec.describe 'Conversores de ETL das tabelas que a produção não tem (S14)' do
  let(:de_para) do
    {
      %w[livetat_auth_users 3] => 'cccccccc-0000-4000-8000-000000000003',
      %w[projects 7] => 'aaaaaaaa-0000-4000-8000-000000000001',
      %w[carriers 9] => 'dddddddd-0000-4000-8000-000000000009',
      %w[project_guarantee_types 2] => 'eeeeeeee-0000-4000-8000-000000000002',
      %w[companies 5] => 'aaaaaaaa-0000-4000-8000-000000000005',
      %w[risk_operation_types 1] => '11111111-0000-4000-8000-000000000001',
      %w[structured_operation_types 1] => '22222222-0000-4000-8000-000000000001',
      %w[risk_operations 4] => '33333333-0000-4000-8000-000000000004'
    }
  end

  let(:conexoes) do
    [{ 'id' => 1, 'project_id' => 7, 'carrier_id' => 9 }]
  end

  let(:empresas) do
    [{ 'id' => 5, 'project_id' => 7 }]
  end

  let(:origem) do
    duplo = instance_double(Sfg::Etl::Source::Base)
    allow(duplo).to receive(:table?).and_return(true)
    allow(duplo).to receive(:ordered_rows).with('project_to_carrier_connections').and_return(conexoes)
    allow(duplo).to receive(:ordered_rows).with('companies').and_return(empresas)
    duplo
  end

  let(:run) do
    duplo = instance_double(Sfg::Etl::Run)
    allow(duplo).to receive(:resolve_reference) { |tabela, pk| de_para[[tabela, pk.to_s]] }
    allow(duplo).to receive(:source).and_return(origem)
    duplo
  end

  # As quatro declaram tabela e model, que é o que faz a lacuna aparecer no
  # relatório com NOME — em vez de sumir porque ninguém acrescentou o arquivo.
  describe 'as quatro declaram origem e destino, para o relatório nomear a lacuna' do
    {
      Sfg::Etl::Converters::ProjectGuarantees => %w[project_guarantees ProjectGuarantee],
      Sfg::Etl::Converters::RiskOperationExtensions => %w[risk_operation_extensions RiskOperationExtension],
      Sfg::Etl::Converters::StructuredOperations => %w[structured_operations StructuredOperation],
      Sfg::Etl::Converters::Remunerations => %w[remunerations Remuneration]
    }.each do |conversor, (tabela, model)|
      it "#{tabela} -> #{model}" do
        expect(conversor.source_table).to eq(tabela)
        expect(conversor.target_model).to eq(model)
      end
    end
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::ProjectGuarantees do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 3, 'project_id' => 7, 'carrier_id' => 9, 'user_id' => 3, 'guarantee_type_id' => 2,
        'title' => ' Aval do socio ', 'value' => '150000.55', 'observation' => 'texto',
        'created_at' => '2022-07-01 10:00:00', 'updated_at' => '2022-07-01 10:00:00' }
    end

    it 'as quatro referências saem do de-para, nunca do id numérico' do
      convertido = conversor.convert(linha)

      expect(convertido[:project_id]).to eq('aaaaaaaa-0000-4000-8000-000000000001')
      expect(convertido[:carrier_id]).to eq('dddddddd-0000-4000-8000-000000000009')
      expect(convertido[:guarantee_type_id]).to eq('eeeeeeee-0000-4000-8000-000000000002')
      expect(convertido[:user_id]).to eq('cccccccc-0000-4000-8000-000000000003')
    end

    it 'o valor entra como decimal, sem arredondamento extra (DEC-02)' do
      expect(conversor.convert(linha)[:value]).to eq(BigDecimal('150000.55'))
    end

    # BE-119 — a regra que o legado só tinha no `select` da tela: nada impedia um
    # POST com portador de outro projeto. O ai9 exige a conexão, e sem ela a
    # garantia é recusada linha a linha no meio da carga.
    it 'garantia com portador NÃO conectado ao projeto é DECLARADA no dry-run (BE-119)' do
      anomalias = conversor.anomalies(linha.merge('carrier_id' => 999))

      expect(anomalias.map { |a| a[:key] }).to eq(['project_guarantees:carrier_not_connected'])
    end

    it 'garantia com portador conectado não gera anomalia' do
      expect(conversor.anomalies(linha)).to be_empty
    end
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::RiskOperationExtensions do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 1, 'risk_operation_id' => 4, 'user_id' => 3,
        'original_due_date' => '2022-08-01', 'new_due_date' => '2022-09-15',
        'observation' => 'pedido do cliente',
        'created_at' => '2022-07-20 09:00:00', 'updated_at' => '2022-07-20 09:00:00' }
    end

    # O ponto inteiro deste conversor. `stamp_original_due_date` DESCARTA o
    # `original_due_date` da origem, e `push_operation_due_date!` reescreve a
    # `risk_operations` já reconciliada. Os dois são certos para uma prorrogação
    # lançada na tela e errados para uma carga, que não está lançando nada — está
    # recontando o que já aconteceu.
    it 'declara anomalia em TODA linha lida: o model do ai9 só sabe CRIAR prorrogação' do
      anomalias = conversor.anomalies(linha)

      expect(anomalias.map { |a| a[:key] }).to include('risk_operation_extensions:model_rewrites_source')
    end

    it 'ainda assim atribui o `original_due_date` da ORIGEM — é ele que o relatório compara' do
      expect(conversor.convert(linha)[:original_due_date]).to eq('2022-08-01')
      expect(described_class.derived).to include('original_due_date')
    end

    # No legado a regra vivia no datepicker da tela: um POST direto passava. No
    # ai9 é `check_constraint`, e o banco recusaria no meio da carga.
    it 'prorrogação que não avança a data é declarada em separado (o CHECK do banco a recusaria)' do
      anomalias = conversor.anomalies(linha.merge('new_due_date' => '2022-07-01'))

      expect(anomalias.map { |a| a[:key] }).to include('risk_operation_extensions:not_moving_forward')
    end

    it 'prorrogação que avança não dispara a segunda anomalia' do
      expect(conversor.anomalies(linha).map { |a| a[:key] })
        .not_to include('risk_operation_extensions:not_moving_forward')
    end
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::StructuredOperations do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 2, 'title' => 'Operação Um', 'user_id' => 3, 'operation_type_id' => 1,
        'project_id' => 7, 'company_id' => 5, 'carrier_id' => 9, 'contract_number' => 'CT-1',
        'issue_date' => '2022-07-05', 'due_date' => '2022-10-05',
        'operation_value' => '500000.00', 'original_balance' => '-500000.00',
        'balance' => '-500000.00', 'agreed_rate' => '2.5', 'observation' => 'obs',
        'is_on_variable' => 1, 'is_ended' => 0, 'receipt_id' => nil,
        'created_at' => '2022-07-05 08:00:00', 'updated_at' => '2022-07-05 08:00:00' }
    end

    # DB-297 — no legado `current_user.id` era forçado no create E no update, e o
    # "autor" virava o último editor. A origem sabe UM valor e não sabe qual dos
    # dois ele é; espalhá-lo pelas duas colunas refaria a confusão que a segunda
    # coluna existe para desfazer.
    it 'o `user_id` ambíguo da origem NÃO é copiado para `updated_by_id` (DB-297)' do
      convertido = conversor.convert(linha)

      expect(convertido[:user_id]).to eq('cccccccc-0000-4000-8000-000000000003')
      expect(convertido[:updated_by_id]).to be_nil
    end

    # DEC-01 — convenção de sinal do legado, replicada. O model reaplica a mesma
    # regra na gravação, então os dois concordam por construção.
    it '`original_balance` viaja NEGATIVO, como o legado o grava (DEC-01)' do
      expect(conversor.convert(linha)[:original_balance]).to eq(BigDecimal('-500000.00'))
      expect(described_class.derived).to include('original_balance', 'balance')
    end

    # Q-R7/BE-293 — o legado não tem a validação, e replicar a ausência é a
    # decisão. Declarar `uniques` faria o motor bloquear por duplicata legítima.
    it 'NÃO declara unicidade de `contract_number` — a ausência é replicada (Q-R7)' do
      expect(described_class.uniques).to be_empty
    end

    it 'os dois flags `integer` 0/1 do legado viram boolean' do
      convertido = conversor.convert(linha)

      expect(convertido[:is_on_variable]).to be(true)
      expect(convertido[:is_ended]).to be(false)
    end

    # C1 — o ai9 deriva o projeto da empresa em todo save, e o do corpo é
    # ignorado. Origem discordando é divergência a reportar, não a converter.
    it 'projeto que discorda do da empresa é DECLARADO — o valor da origem será descartado' do
      anomalias = conversor.anomalies(linha.merge('project_id' => 99))

      expect(anomalias.map { |a| a[:key] }).to eq(['structured_operations:project_disagrees_with_company'])
    end

    it 'projeto coerente com a empresa não gera anomalia' do
      expect(conversor.anomalies(linha)).to be_empty
    end
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::Remunerations do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 1, 'project_id' => 7, 'operation_type_id' => 1,
        'operation_type_type' => 'RiskOperationType', 'value' => '2.5', 'title' => 'Fomento',
        'created_at' => '2022-08-02 10:00:00', 'updated_at' => '2022-08-02 10:00:00' }
    end

    # A FK aponta para tabelas DIFERENTES linha a linha. O motor não consegue
    # contar órfão por uma coluna cujo destino muda, então o religamento é feito
    # no conversor e a conferência vive em `anomalies` — desenho de
    # `ActionTextRichTexts`.
    it 'o tipo polimórfico escolhe a tabela do de-para pelo `operation_type_type`' do
      risco = conversor.convert(linha)
      estruturada = conversor.convert(linha.merge('operation_type_type' => 'StructuredOperationType'))

      expect(risco[:operation_type_id]).to eq('11111111-0000-4000-8000-000000000001')
      expect(estruturada[:operation_type_id]).to eq('22222222-0000-4000-8000-000000000001')
    end

    it 'a referência polimórfica NÃO é declarada em `references` — o motor não a conferiria' do
      expect(described_class.references).to eq('project_id' => 'projects')
    end

    # No legado `operation_class` devolvia `nil` e `beauty_type` devolvia `"???"`:
    # o valor arbitrário entrava e quebrava depois, longe da causa.
    it 'tipo fora das duas classes é DECLARADO e NÃO vira `nil` em silêncio' do
      anomalias = conversor.anomalies(linha.merge('operation_type_type' => 'Qualquer'))

      expect(anomalias.map { |a| a[:key] }).to eq(['remunerations:unknown_operation_type'])
      expect(conversor.convert(linha.merge('operation_type_type' => 'Qualquer'))[:operation_type_type]).to be_nil
    end

    it 'tipo conhecido mas ainda fora do de-para é DECLARADO como ordem de carga' do
      anomalias = conversor.anomalies(linha.merge('operation_type_id' => 999))

      expect(anomalias.map { |a| a[:key] }).to eq(['remunerations:operation_type_not_loaded'])
    end

    # DEC-37/T-D9 — sem validação de faixa: 250% passa hoje e continua passando.
    it 'a taxa entra como decimal e SEM validação de faixa (DEC-37/T-D9)' do
      expect(conversor.convert(linha.merge('value' => '250.0'))[:value]).to eq(BigDecimal('250.0'))
    end

    # No legado a coluna não existe e `user_id` sequer estava no `permit`.
    # Escolher alguém seria repetir a autoria inventada do ETL de 2021.
    it '`user_id` entra NULO: a coluna não existe na origem e inventar autoria é o defeito de 2021' do
      expect(conversor.convert(linha)[:user_id]).to be_nil
    end

    # DB-284 — o índice único composto que garante que `Receipt#fetch` (um
    # `.first`) ache UMA taxa.
    it 'declara a unicidade composta (projeto, tipo, id do tipo) — DB-284' do
      expect(described_class.uniques).to eq([%w[project_id operation_type_type operation_type_id]])
    end
  end
end
