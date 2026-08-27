# frozen_string_literal: true

require 'rails_helper'

# S14 — os conversores de ETL dos catálogos que faltavam: `sub_segments`,
# `resource_sources`, `project_guarantee_types` e `structured_operation_types`.
#
# Os quatro são o mesmo objeto com colunas diferentes (é o molde `GlobalCatalog`),
# e é justamente por isso que estes testes travam o que **difere** entre eles —
# não o que se repete:
#
#   * o `strip` do título, que existe porque 2 dos 20 subsegmentos de produção
#     têm espaço sobrando e sem ele a reconciliação acusa divergência falsa;
#   * a chave de integração **copiada**, nunca rederivada (DEC-85);
#   * o `legacy_id` que é `id` da origem, e não o `legacy_id` que a própria
#     origem carrega de uma importação anterior;
#   * e as duas tabelas que **não existem em produção** (DEC-103b), cujo
#     conversor existe para que a lacuna apareça no relatório.
#
# Os conversores são exercitados pela conversão pura (`convert`/`anomalies`), sem
# subir o motor: `ref` é resolvido por um duplo do `run`, que é exatamente o que
# o motor faz com o de-para.
RSpec.describe 'Conversores de ETL dos catálogos (S14)' do
  let(:de_para) do
    {
      %w[livetat_auth_users 3] => 'cccccccc-0000-4000-8000-000000000003',
      %w[projects 7] => 'aaaaaaaa-0000-4000-8000-000000000001',
      %w[carriers 9] => 'dddddddd-0000-4000-8000-000000000009'
    }
  end

  let(:origem) { instance_double(Sfg::Etl::Source::Base) }

  let(:run) do
    duplo = instance_double(Sfg::Etl::Run)
    allow(duplo).to receive(:resolve_reference) { |tabela, pk| de_para[[tabela, pk.to_s]] }
    allow(duplo).to receive(:source).and_return(origem)
    duplo
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::SubSegments do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 12, 'title' => 'Agronegócio ', 'integration_key' => 'agronegocio',
        'is_active' => 1, 'user_id' => 3,
        'created_at' => '2021-05-10 09:00:00', 'updated_at' => '2022-01-04 11:20:00' }
    end

    # Medido no dump de 31/05/2025: 2 dos 20 títulos têm espaço sobrando. O
    # `normalize_catalog_title` do model faria o `strip` na gravação de qualquer
    # jeito — fazê-lo aqui é o que deixa a RECONCILIAÇÃO comparar o que foi de
    # fato gravado, em vez de acusar divergência nas duas linhas.
    it 'apara o espaço sobrando do título, para a reconciliação comparar o que foi gravado' do
      expect(conversor.convert(linha)[:title]).to eq('Agronegócio')
    end

    it 'a chave de integração é COPIADA da origem, nunca rederivada (DEC-85)' do
      convertido = conversor.convert(linha.merge('integration_key' => 'chave_publicada'))

      expect(convertido[:integration_key]).to eq('chave_publicada')
    end

    # DC-13 — o legado nunca ligou subsegmento a segmento. Um `segment_id` aqui
    # seria mapeamento inventado sobre 20 registros reais.
    it 'NÃO carrega vínculo com `Segment` — DC-13, os dois catálogos são listas planas' do
      expect(conversor.convert(linha)).not_to have_key(:segment_id)
    end

    it '`is_active = 1` vira `true` e `0` vira `false` (integer 0/1 no legado)' do
      expect(conversor.convert(linha)[:is_active]).to be(true)
      expect(conversor.convert(linha.merge('is_active' => 0))[:is_active]).to be(false)
    end

    it 'o autor é religado pelo DE-PARA, nunca pelo id numérico da origem' do
      expect(conversor.convert(linha)[:user_id]).to eq('cccccccc-0000-4000-8000-000000000003')
    end

    it 'o `legacy_id` é a proveniência (DEC-12), e a chave natural sai dele' do
      expect(conversor.convert(linha)[:legacy_id]).to eq(12)
      expect(conversor.natural_key(linha)).to eq(legacy_id: 12)
    end

    # DEC-06 — a conversão usa as transições da tz database, não offset fixo.
    # 2021 já é UTC-3 fixo; o teste do lado com DST está em `values_precision_spec`.
    it 'os timestamps chegam em UTC pela regra da tz database (DEC-06)' do
      convertido = conversor.convert(linha)

      expect(convertido[:created_at].utc.strftime('%Y-%m-%d %H:%M')).to eq('2021-05-10 12:00')
    end
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::ResourceSources do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 4, 'title' => 'Fomento', 'integration_key' => 'fomento', 'is_active' => 1,
        'user_id' => 3, 'legacy_id' => 991,
        'created_at' => '2022-02-01 08:00:00', 'updated_at' => '2022-02-01 08:00:00' }
    end

    # A ARMADILHA desta tabela: a origem carrega uma coluna `legacy_id` PRÓPRIA,
    # de uma importação anterior, preenchida em 6 de 6 linhas. Copiá-la aqui
    # encadearia duas proveniências diferentes na mesma coluna e o de-para
    # deixaria de fechar com `resource_sources.id`.
    it 'o `legacy_id` é o `id` da ORIGEM — não o `legacy_id` que a própria origem carrega' do
      convertido = conversor.convert(linha)

      expect(convertido[:legacy_id]).to eq(4)
      expect(convertido[:legacy_id]).not_to eq(991)
    end

    # É a condição para que a carga não crie uma segunda "Fomento" e deixe metade
    # dos 28.131 borderôs apontando para cada uma. O seed de referência semeia as
    # 6 linhas com o MESMO `legacy_id`, e a chave natural é ele.
    it 'a chave natural é o `legacy_id`, que é o que faz a carga CASAR com o seed em vez de duplicar' do
      expect(conversor.natural_key(linha)).to eq(legacy_id: 4)
    end

    # Q-R19 — a decisão é da S8: `is_active` NÃO filtra o select do borderô. O
    # conversor carrega o valor como está; não transforma "inativa" em "ausente".
    it 'carrega `is_active` como está — não converte fonte inativa em fonte ausente (Q-R19)' do
      expect(conversor.convert(linha.merge('is_active' => 0))[:is_active]).to be(false)
    end

    it 'a chave de integração vem da origem' do
      expect(conversor.convert(linha)[:integration_key]).to eq('fomento')
    end
  end

  # ===========================================================================
  # As duas abaixo NÃO EXISTEM na origem de produção. Os testes travam o
  # mapeamento para o dia em que existirem — e travam o fato de a ausência ser
  # esperada, que é o que se esquece.
  describe Sfg::Etl::Converters::ProjectGuaranteeTypes do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 2, 'title' => 'Aval', 'integration_key' => 'aval', 'is_active' => 1,
        'user_id' => 3, 'created_at' => '2022-06-27 10:00:00', 'updated_at' => '2022-06-27 10:00:00' }
    end

    it 'declara a tabela e o model, para a lacuna aparecer no relatório com nome' do
      expect(described_class.source_table).to eq('project_guarantee_types')
      expect(described_class.target_model).to eq('ProjectGuaranteeType')
    end

    # DEC-86 — os tipos semeados são SUPOSIÇÃO do orquestrador, e a tela avisa.
    # Linha vinda do legado é dado do cliente e **não** nasce provisória.
    it 'o que vem do legado NÃO nasce provisório — `is_provisional` é marca de seed (DEC-86)' do
      expect(conversor.convert(linha)[:is_provisional]).to be(false)
    end

    it 'a ordem de exibição não existe na origem e entra ZERADA, nunca inventada' do
      expect(conversor.convert(linha)[:sort_order]).to eq(0)
    end
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::StructuredOperationTypes do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 1, 'title' => 'Fomento', 'integration_key' => 'fomento', 'is_active' => 1,
        'is_default' => 1, 'allow_manual_operations' => 1, 'allow_receivable_entries' => 0,
        'has_pre_faturamento' => 0, 'user_id' => 3,
        'created_at' => '2022-07-01 12:00:00', 'updated_at' => '2022-07-01 12:00:00' }
    end

    it 'os cinco flags do legado são `integer` 0/1 e viram boolean' do
      convertido = conversor.convert(linha)

      expect(convertido[:is_active]).to be(true)
      expect(convertido[:is_default]).to be(true)
      expect(convertido[:allow_manual_operations]).to be(true)
      expect(convertido[:allow_receivable_entries]).to be(false)
      expect(convertido[:has_pre_faturamento]).to be(false)
    end

    # A diferença que dá erro caro: o homônimo de `risk_operation_types` gera
    # subtipo no `after_create` e decide o bucket de exposição. Aqui não existe
    # subtipo de operação estruturada — a coluna viaja SEM ganhar consumidor.
    it '`has_pre_faturamento` viaja como coluna e NÃO gera subtipo — não é o homônimo do risco (Q-R15)' do
      expect(conversor.convert(linha.merge('has_pre_faturamento' => 1))[:has_pre_faturamento]).to be(true)
      expect(described_class.target_model).to eq('StructuredOperationType')
    end
  end
end
