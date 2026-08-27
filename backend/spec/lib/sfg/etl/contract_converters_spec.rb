# frozen_string_literal: true

require 'rails_helper'

# S14 — os dois conversores dos **contratos** (S12): a versão publicada e o
# aceite. São 2 e 272 linhas, e é o par com mais consequência jurídica da
# migração: cada linha de `contracts` é a âncora de 136 aceites, e cada linha de
# `contract_deals` é a prova de que uma pessoa concordou com um texto.
#
# O que estes testes travam é o que a DEC-66 e a DEC-80 decidiram, e que se
# perde com uma linha de código distraída: a numeração congelada, a data de
# publicação que vem da origem, o aceite que entra marcado como carimbo, e as
# quatro colunas de prova que ficam VAZIAS de propósito.
RSpec.describe 'Conversores de ETL dos contratos (S14)' do
  let(:de_para) do
    {
      %w[livetat_auth_users 3] => 'cccccccc-0000-4000-8000-000000000003',
      %w[contracts 2] => 'ffffffff-0000-4000-8000-000000000002'
    }
  end

  let(:contratos_da_origem) do
    [
      { 'id' => 1, 'kind' => 'Politicas de Privacidade', 'version' => 1,
        'title' => 'Politicas de Privacidade', 'creator_id' => 3,
        'created_at' => '2022-02-27 23:18:52', 'updated_at' => '2022-02-27 23:18:52' },
      { 'id' => 2, 'kind' => 'Termos de Uso', 'version' => 1, 'title' => 'Termos de Uso',
        'creator_id' => 3, 'created_at' => '2022-02-27 23:18:52', 'updated_at' => '2022-02-27 23:18:52' }
    ]
  end

  let(:textos_ricos) do
    [
      { 'id' => 1, 'record_type' => 'Contract', 'record_id' => 2, 'name' => 'description',
        'body' => '<div class="trix-content">Termos, versao 1</div>' }
    ]
  end

  let(:origem) do
    duplo = instance_double(Sfg::Etl::Source::Base)
    allow(duplo).to receive(:table?).and_return(true)
    allow(duplo).to receive(:ordered_rows).with('contracts').and_return(contratos_da_origem)
    allow(duplo).to receive(:ordered_rows).with('action_text_rich_texts').and_return(textos_ricos)
    duplo
  end

  let(:run) do
    duplo = instance_double(Sfg::Etl::Run)
    allow(duplo).to receive(:resolve_reference) { |tabela, pk| de_para[[tabela, pk.to_s]] }
    allow(duplo).to receive(:source).and_return(origem)
    duplo
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::Contracts do
    subject(:conversor) { described_class.new(run) }

    let(:linha) { contratos_da_origem.second }

    # DB-330 — a numeração existente vira a numeração daqui, sem renumerar.
    # Atribuir `version` explicitamente é o que faz o `assign_version_and_slug`
    # do model NÃO calcular nada: em branco ele pegaria `max + 1` do DESTINO, e
    # numa base semeada a versão 1 do legado viraria 2.
    it 'a `version` do legado é CONGELADA — atribuída, nunca recalculada (DB-330/BE-336)' do
      expect(conversor.convert(linha)[:version]).to eq(1)
    end

    # Q-B34 — a grafia com o typo consolidado ("Politicas") viaja em URL pública
    # e existe em links externos. O catálogo do ai9 a preserva de propósito.
    it 'o `kind` passa pelo catálogo fechado do ai9, preservando o typo do legado (Q-B34)' do
      expect(conversor.convert(linha)[:kind]).to eq('Termos de Uso')
      expect(conversor.convert(contratos_da_origem.first)[:kind]).to eq('Politicas de Privacidade')
    end

    # BE-342 — é o marco da tolerância de 30 dias. `ensure_defaults` cairia em
    # `Time.current`, e o efeito seria zerar a tolerância de todo mundo no dia 1.
    it '`published_at` vem da ORIGEM, nunca de `Time.current` (BE-342)' do
      convertido = conversor.convert(linha)

      expect(convertido[:published_at].utc.strftime('%Y-%m-%d %H:%M')).to eq('2022-02-28 02:18')
    end

    # A chave natural NÃO é `legacy_id`: `Seeds::Reference::Contracts` já publica
    # a versão 1 dos dois tipos SEM `legacy_id`, e o índice único do ai9 é
    # `(kind, version)`. Com a chave padrão, a carga sobre a base semeada bate em
    # `PG::UniqueViolation` — medido.
    it 'a chave natural é `(kind, version)`, para a carga ATUALIZAR a versão semeada em vez de duplicar' do
      expect(conversor.natural_key(linha)).to eq(kind: 'Termos de Uso', version: 1)
    end

    # Mesma razão de `HelpItems`: `corpo_nao_pode_ser_vazio` roda antes de
    # `ActionTextRichTexts`, e sem o contrato os 272 aceites não têm a que apontar.
    it 'traz o corpo do ActionText junto com o registro — sem isso o contrato nem salva' do
      expect(conversor.convert(linha)[:description]).to eq('<div class="trix-content">Termos, versao 1</div>')
    end

    it 'contrato sem corpo é DECLARADO, não carregado às cegas' do
      anomalias = conversor.anomalies(contratos_da_origem.first)

      expect(anomalias.map { |a| a[:key] }).to include('contracts:without_body')
    end

    # OPS-332 — o catálogo não é configurável pela interface: tipo novo é
    # migration + linha em `Contract::KINDS`. Nada entra fora dele.
    it 'tipo fora do catálogo é DECLARADO (OPS-332)' do
      anomalias = conversor.anomalies(linha.merge('kind' => 'Contrato de Adesao'))

      expect(anomalias.map { |a| a[:key] }).to include('contracts:kind_outside_catalog')
    end

    it 'o autor é religado pelo de-para e o contrato entra sem autor se ele não vier' do
      expect(conversor.convert(linha)[:creator_id]).to eq('cccccccc-0000-4000-8000-000000000003')
      expect(conversor.convert(linha.merge('creator_id' => 999))[:creator_id]).to be_nil
    end
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::ContractDeals do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 77, 'user_id' => 3, 'contract_id' => 2,
        'created_at' => '2022-03-01 10:30:00', 'updated_at' => '2022-03-01 10:30:00' }
    end

    # DEC-66 — o passivo do legado tem duas origens conhecidas: o `after_create`
    # que gravava aceite sem interação e o seed que fabricou aceite retroativo
    # para a base inteira. A base antiga não distingue quem aceitou de quem foi
    # carimbado, e nada aqui pode dizer que distingue.
    it 'todo aceite existente entra `implicit_legacy` — carimbo NÃO é consentimento (DEC-66)' do
      expect(conversor.convert(linha)[:source]).to eq('implicit_legacy')
      expect(conversor.convert(linha)[:source]).not_to eq(ContractDeal::SOURCE_EXPLICIT)
    end

    # A data original é preservada nas DUAS colunas para que a promoção a
    # explícito não apague o histórico: o índice único só admite uma linha por
    # versão, e a data original é histórico que não pode ser sobrescrito.
    it 'a data original vai para `accepted_at` E para `legacy_accepted_at`' do
      convertido = conversor.convert(linha)

      expect(convertido[:accepted_at]).to eq(convertido[:legacy_accepted_at])
      expect(convertido[:accepted_at].utc.strftime('%Y-%m-%d %H:%M')).to eq('2022-03-01 13:30')
    end

    # Inventar o hash faria um aceite carimbado parecer prova de leitura — que é
    # exatamente a diferença que a DEC-80 existe para preservar.
    it 'IP, user-agent, hash e texto lido ficam VAZIOS: o vazio é informação (DEC-80)' do
      convertido = conversor.convert(linha)

      expect(convertido[:ip_address]).to be_nil
      expect(convertido[:user_agent]).to be_nil
      expect(convertido[:content_hash]).to be_nil
      expect(convertido[:accepted_body]).to be_nil
    end

    # "A prova não pode depender de JOIN". E os valores vêm da ORIGEM, não do
    # destino: no dry-run o destino ainda está vazio, e conversor que só funciona
    # depois da carga não é conversor.
    it 'tipo e versão são denormalizados a partir da ORIGEM, não do destino' do
      convertido = conversor.convert(linha)

      expect(convertido[:contract_kind]).to eq('Termos de Uso')
      expect(convertido[:contract_version]).to eq(1)
    end

    it 'aceite cujo contrato não está na origem é DECLARADO — sem tipo e número não há prova' do
      anomalias = conversor.anomalies(linha.merge('contract_id' => 999))

      expect(anomalias.map { |a| a[:key] }).to eq(['contract_deals:contract_not_in_source'])
    end

    # A anomalia dos 2 órfãos de `user_id` é contada pelo MOTOR, pela declaração
    # abaixo. É ela que faz o dry-run abortar com `orphans:contract_deals.user_id`.
    it 'declara `user_id` como referência — é o que faz os 2 órfãos de produção aparecerem' do
      expect(described_class.references)
        .to eq('user_id' => 'livetat_auth_users', 'contract_id' => 'contracts')
    end

    it 'declara a unicidade (usuário, contrato) que no legado era só validação de aplicação' do
      expect(described_class.uniques).to eq([%w[user_id contract_id]])
    end
  end
end
