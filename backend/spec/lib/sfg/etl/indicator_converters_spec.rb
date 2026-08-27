# frozen_string_literal: true

require 'rails_helper'

# S10 / DEC-102 — os conversores de ETL dos indicadores.
#
# A **DEC-102** adiou a CARGA de dados para depois da apresentação; não adiou o
# conversor. Escrevê-lo agora, com a fórmula na cabeça, custa pouco — e o que
# este arquivo trava é justamente o que se esquece meses depois: que o título
# migrado chega em CAIXA ALTA (DEC-89), que `is_active` do legado é `= 1` e não
# `≠ 0`, e que **não há conversão de fuso a fazer no período**.
#
# Os conversores são exercitados pela conversão pura (`convert`/`anomalies`), sem
# subir o motor: `ref` é resolvido por um duplo do `run`, que é exatamente o que
# o motor faz com o de-para.
RSpec.describe 'Conversores de ETL dos indicadores' do
  # Duplo do `run`: o de-para devolve o uuid que o motor teria gravado.
  let(:de_para) do
    {
      %w[projects 7] => 'aaaaaaaa-0000-4000-8000-000000000001',
      %w[indicators 11] => 'bbbbbbbb-0000-4000-8000-000000000002',
      %w[livetat_auth_users 3] => 'cccccccc-0000-4000-8000-000000000003'
    }
  end

  let(:origem) do
    duplo = instance_double(Sfg::Etl::Source::Base)
    # `IndicatorEntries#pares_conectados` ganhou uma guarda `source.table?` (a
    # DEC-129.3 lê `project_indicator_connections` para achar lançamento sem
    # conexão) e o dublê nunca foi atualizado: dois exemplos morriam com
    # "received unexpected message :table?", e não por causa do que testam.
    #
    # O default é `false` — sem a tabela na origem, o conversor devolve conjunto
    # vazio e a anomalia sob teste (mês fora de faixa, valor nulo) é a única que
    # sobra. É o cenário que estes exemplos querem isolar.
    allow(duplo).to receive(:table?).and_return(false)
    duplo
  end

  let(:run) do
    duplo = instance_double(Sfg::Etl::Run)
    allow(duplo).to receive(:resolve_reference) { |tabela, pk| de_para[[tabela, pk.to_s]] }
    allow(duplo).to receive(:source).and_return(origem)
    duplo
  end

  # ---------------------------------------------------------------------------
  describe Sfg::Etl::Converters::Indicators do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 11, 'project_id' => nil, 'title' => 'Inadimplência', 'key' => 'inadimplencia',
        'value_type' => 'Dinheiro', 'is_active' => 1,
        'created_at' => '2018-03-10 09:00:00', 'updated_at' => '2021-07-02 14:30:00' }
    end

    before { allow(origem).to receive(:ordered_rows).with('indicators').and_return([linha]) }

    # **DEC-89.** Os acentos do dado legado já se perderam de forma irreversível;
    # "re-humanizar" na carga seria adivinhação.
    it 'o título migrado chega em CAIXA ALTA sem acento' do
      expect(conversor.convert(linha)[:title]).to eq('INADIMPLENCIA')
    end

    it 'a chave é COPIADA da origem, não recalculada (DEC-85 — pode haver consumidor externo)' do
      expect(conversor.convert(linha.merge('key' => 'chave_do_bi'))[:key]).to eq('chave_do_bi')
    end

    # As duas leituras do legado (`is_active?` e `where(is_active: 1)`) comparam
    # com 1. Um `is_active = 2` conta como INATIVO nas duas.
    it '`is_active = 1` vira `true`' do
      expect(conversor.convert(linha)[:is_active]).to be(true)
    end

    it '`is_active = 0` vira `false`' do
      expect(conversor.convert(linha.merge('is_active' => 0))[:is_active]).to be(false)
    end

    it 'nenhum registro migrado chega descartado — a exclusão lógica é feature nova (D-66)' do
      expect(conversor.convert(linha)[:discarded_at]).to be_nil
    end

    it 'o `project_id` é religado pelo DE-PARA, nunca pelo id numérico da origem' do
      convertido = conversor.convert(linha.merge('project_id' => 7))
      expect(convertido[:project_id]).to eq('aaaaaaaa-0000-4000-8000-000000000001')
    end

    it 'as três regras de unicidade do legado viram ANOMALIA no dry-run, com o par de ids' do
      outro = linha.merge('id' => 12, 'title' => 'INADIMPLENCIA')
      allow(origem).to receive(:ordered_rows).with('indicators').and_return([linha, outro])

      expect(conversor.anomalies(linha).first).to match(/título duplicado.*12/)
    end

    it 'específicos homônimos em projetos DIFERENTES não são anomalia — é aceito no legado' do
      a = linha.merge('id' => 21, 'project_id' => 7, 'title' => 'MARGEM')
      b = linha.merge('id' => 22, 'project_id' => 8, 'title' => 'MARGEM')
      allow(origem).to receive(:ordered_rows).with('indicators').and_return([a, b])

      expect(conversor.anomalies(a)).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  describe Sfg::Etl::Converters::IndicatorEntries do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 500, 'project_id' => 7, 'indicator_id' => 11, 'user_id' => 3,
        'year' => 2019, 'month' => 12, 'value' => '-1500.75',
        'title' => 'MARGEM ANTIGA', 'key' => 'margem_antiga', 'value_type' => 'Dinheiro',
        'created_at' => '2019-12-31 23:30:00', 'updated_at' => '2019-12-31 23:30:00' }
    end

    # **O ponto que o briefing desta fatia mandava conferir, e a resposta é
    # medida, não suposta.** A conversão UTC-2/UTC-3 vale para os timestamps; o
    # bucket do mês vem de `year`/`month` INTEIROS, digitados pelo usuário, e
    # não de timestamp nenhum. Converter aqui seria inventar um deslocamento.
    it 'ano e mês atravessam INTACTOS — a virada de fuso não os alcança' do
      convertido = conversor.convert(linha)

      expect(convertido[:year]).to eq(2019)
      expect(convertido[:month]).to eq(12)
    end

    it 'o `user_id` do legado vira `created_by`; `updated_by` fica NULO' do
      convertido = conversor.convert(linha)

      expect(convertido[:created_by]).to eq('cccccccc-0000-4000-8000-000000000003')
      # O legado não guardava quem alterou por último. Repetir o mesmo id seria
      # afirmar algo que o dado não diz.
      expect(convertido[:updated_by]).to be_nil
    end

    it 'a foto denormalizada é COPIADA da origem, não recalculada do indicador atual' do
      expect(conversor.convert(linha)[:title]).to eq('MARGEM ANTIGA')
    end

    it 'valores NEGATIVOS atravessam' do
      expect(conversor.convert(linha)[:value]).to eq(BigDecimal('-1500.75'))
    end

    it 'mês fora de faixa é ANOMALIA — o CHECK do ai9 recusaria a linha no meio da carga' do
      expect(conversor.anomalies(linha.merge('month' => 13)).first).to match(/mês fora de 1\.\.12/)
    end

    it 'valor nulo é anomalia — zero é lançamento, nulo não é' do
      expect(conversor.anomalies(linha.merge('value' => nil)).first).to match(/valor nulo/)
    end

    it 'a identidade (projeto, indicador, ano, mês) é declarada — o legado só a tinha na aplicação' do
      expect(described_class.uniques).to eq([%w[project_id indicator_id year month]])
    end
  end

  # ---------------------------------------------------------------------------
  describe Sfg::Etl::Converters::ProjectIndicatorConnections do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 90, 'project_id' => 7, 'indicator_id' => 11,
        'created_at' => '2021-01-05 10:00:00', 'updated_at' => '2021-01-05 10:00:00' }
    end

    it 'religa os dois lados pelo de-para' do
      convertido = conversor.convert(linha)

      expect(convertido[:project_id]).to eq('aaaaaaaa-0000-4000-8000-000000000001')
      expect(convertido[:indicator_id]).to eq('bbbbbbbb-0000-4000-8000-000000000002')
    end

    it 'NÃO converte `is_active` — a coluna não existe na origem (só no `permit` do controller)' do
      expect(conversor.convert(linha)).not_to have_key(:is_active)
    end
  end

  # ---------------------------------------------------------------------------
  describe 'ordem de carga' do
    let(:ordem) do
      YAML.load_file(Rails.root.join('db/etl/load_order.yml'))['order']
          .map { |e| e.is_a?(String) ? e : e['converter'] }
    end

    it 'o indicador entra ANTES da ponte e do lançamento — os dois o referenciam' do
      expect(ordem.index('Indicators')).to be < ordem.index('ProjectIndicatorConnections')
      expect(ordem.index('Indicators')).to be < ordem.index('IndicatorEntries')
    end

    it 'os três são classes de verdade, não lacunas declaradas' do
      %w[Indicators ProjectIndicatorConnections IndicatorEntries].each do |nome|
        expect(Sfg::Etl::Converters.const_get(nome)).to be < Sfg::Etl::Converters::Base
      end
    end
  end
end
