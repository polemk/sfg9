# frozen_string_literal: true

require 'rails_helper'

# S10 / 10.1 — **caracterização `G1` e `G2`** do `design.md` §2.
#
# Estes exemplos não existem para provar que a regra está certa. Existem para
# **reprovar quem a "consertar"** sem passar por uma decisão (DEC-30). Os valores
# foram extraídos da fonte do legado, arquivo e linha citados em cada bloco.
#
# No legado este model tem **zero cobertura** (OPS-314: 5 models, 4 controllers e
# ~40 views sem um único teste).
RSpec.describe Indicator do
  let(:projeto1) { create(:project) }
  let(:projeto2) { create(:project) }

  # ---------------------------------------------------------------------------
  describe 'G1 — as três regras de unicidade (BE-320)' do
    # Fonte: `../sfg/app/models/indicator.rb:12-23`. A comparação do legado é
    # `where("title ILIKE LOWER(?)", title)` — igualdade insensível a caixa; a
    # insensibilidade a acento vem do armazenamento já transliterado.

    it '(a) global recusa título de outro GLOBAL — "Já utilizado"' do
      create(:indicator, title: 'MARGEM')
      novo = build(:indicator, title: 'margem')

      expect(novo).not_to be_valid
      expect(novo.errors[:title]).to include('Já utilizado')
    end

    it '(b) específico recusa título de GLOBAL — "Já utilizado por indicador global"' do
      create(:indicator, title: 'MARGEM')
      novo = build(:indicator, title: 'Margem', project: projeto1)

      expect(novo).not_to be_valid
      expect(novo.errors[:title]).to include('Já utilizado por indicador global')
    end

    it '(c) específico recusa título de outro específico DO MESMO projeto' do
      create(:indicator, title: 'Margem', project: projeto1)
      novo = build(:indicator, title: 'margem', project: projeto1)

      expect(novo).not_to be_valid
      expect(novo.errors[:title]).to include('Já utilizado nesse projeto')
    end

    it 'dois projetos DIFERENTES podem ter específicos homônimos — aceito' do
      create(:indicator, title: 'Margem', project: projeto1)
      novo = build(:indicator, title: 'Margem', project: projeto2)

      expect(novo).to be_valid
    end

    # **O efeito colateral replicado.** É consequência direta da regra (a), que
    # olha `Indicator.where(title …)` sem filtrar por projeto: dois projetos
    # podem ter específicos homônimos, mas **nenhum global** pode usar esse nome
    # depois. Parece errado e é o que o legado faz. Não conserte.
    it 'depois de um ESPECÍFICO com esse nome, o GLOBAL homônimo é recusado' do
      create(:indicator, title: 'Margem', project: projeto1)
      novo = build(:indicator, title: 'Margem')

      expect(novo).not_to be_valid
      expect(novo.errors[:title]).to include('Já utilizado')
    end

    it 'a comparação ignora ACENTO — e o acento nem chega ao banco (DEC-89)' do
      create(:indicator, title: 'Inadimplência')
      expect(Indicator.first.title).to eq('INADIMPLENCIA')

      expect(build(:indicator, title: 'inadimplencia')).not_to be_valid
    end

    it 'editar o próprio registro não colide consigo mesmo' do
      indicador = create(:indicator, title: 'MARGEM')
      indicador.title = 'Margem'

      expect(indicador).to be_valid
    end

    it 'indicador DESCARTADO continua ocupando o nome — o dado não sumiu' do
      create(:indicator, :discarded, title: 'MARGEM')

      expect(build(:indicator, title: 'margem')).not_to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  describe 'G2 — título em CAIXA ALTA sem acento e chave derivada (BE-321, DEC-89/DEC-85)' do
    # Fonte: `../sfg/app/models/indicator.rb:38-46`.
    #
    # A **DEC-89 mandou replicar** o `I18n.transliterate(title).upcase`,
    # encerrando o conflito em que a spec de `BE-321` pedia "o título aparece
    # como digitado". Consequência escrita na decisão e sem volta:
    # "Inadimplência" vira "INADIMPLENCIA" **no banco**.

    it '"Rentabilidade média" vira "RENTABILIDADE MEDIA" e a chave "rentabilidade_media"' do
      indicador = create(:indicator, title: 'Rentabilidade média')

      expect(indicador.title).to eq('RENTABILIDADE MEDIA')
      expect(indicador.key).to eq('rentabilidade_media')
    end

    it 'normaliza em TODO save, não só na criação (o `before_validation` do legado não tem `on:`)' do
      indicador = create(:indicator, title: 'PRIMEIRO')
      indicador.update!(title: 'Índice de atraso')

      expect(indicador.reload.title).to eq('INDICE DE ATRASO')
    end

    # DEC-85 / OPS-312 (T-D13): a chave é "de Integração". **Só o espaço** vira
    # sublinhado — `GlobalCatalog.slugify` trocaria todo caractere não
    # alfanumérico e mudaria o formato do dado migrado em silêncio.
    it 'a chave preserva o formato do legado: só o ESPAÇO vira sublinhado' do
      indicador = create(:indicator, title: 'Margem S/A 2024')

      expect(indicador.key).to eq('margem_s/a_2024')
    end

    it 'a chave NÃO é recalculada no update — ela é congelada (DEC-85)' do
      indicador = create(:indicator, title: 'ANTIGO')
      indicador.update!(title: 'NOVO')

      expect(indicador.reload.key).to eq('antigo')
    end

    it 'a chave informada na criação é respeitada' do
      expect(create(:indicator, title: 'QUALQUER', key: 'chave_do_bi').key).to eq('chave_do_bi')
    end

    it '`title` nulo é 422, não 500 (`I18n.transliterate(nil)` levanta antes da validação)' do
      indicador = build(:indicator, title: nil)

      expect { indicador.valid? }.not_to raise_error
      expect(indicador.errors[:title]).to be_present
    end

    it 'o tipo de valor nasce "Dinheiro" — um valor só, e é o texto que o legado grava (Q-R32)' do
      expect(create(:indicator, title: 'X').value_type).to eq('Dinheiro')
    end
  end

  # ---------------------------------------------------------------------------
  describe 'G4 — a denormalização reescreve o histórico (BE-322, T-D11)' do
    # Fonte: `../sfg/app/models/indicator.rb:48-50`.
    # `self.entries.update_all(title:, key:, value_type:)` em todo save.
    #
    # O resultado é REPLICADO de propósito: um lançamento de 2023 passa a dizer
    # o nome que o indicador tem hoje. O que muda é só onde a escrita acontece.

    let(:indicador) { create(:indicator, title: 'MARGEM') }
    let!(:lancamento) do
      create(:indicator_entry, project: projeto1, indicator: indicador, year: 2023, month: 3, value: 10)
    end

    it 'renomear reescreve `title` e `value_type` de TODAS as entries' do
      indicador.update!(title: 'Margem operacional')

      expect(lancamento.reload.title).to eq('MARGEM OPERACIONAL')
      expect(lancamento.value_type).to eq('Dinheiro')
    end

    it 'a chave da entry NÃO muda, porque a do indicador não muda (DEC-85)' do
      indicador.update!(title: 'OUTRO NOME')

      expect(lancamento.reload.key).to eq('margem')
    end

    it 'não toca `updated_at` das entries — é `update_all`, como no legado' do
      antes = lancamento.updated_at
      indicador.update!(title: 'MAIS UM NOME')

      expect(lancamento.reload.updated_at).to eq(antes)
    end

    it 'acima do limite a propagação vai para o job — a resposta não espera N updates' do
      stub_const('Indicator::PROPAGATION_INLINE_LIMIT', 0)
      adaptador = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test

      expect { indicador.update!(title: 'GRANDE') }
        .to have_enqueued_job(PropagateIndicatorFieldsJob).with(indicador.id)
    ensure
      ActiveJob::Base.queue_adapter = adaptador if adaptador
    end

    it 'salvar sem mudar os três campos NÃO reescreve nada (o `update_all` seria invisível de qualquer forma)' do
      expect(IndicatorEntry).not_to receive(:propagate_from)
      indicador.update!(is_active: false)
    end
  end

  # ---------------------------------------------------------------------------
  describe 'exclusão LÓGICA — o fechamento do D-66 (BE-318)' do
    # No legado: `has_many :entries, dependent: :delete_all` — excluir o
    # indicador apagava **toda a série histórica**, sem callbacks e sem backup.

    let(:indicador) { create(:indicator, title: 'HISTORICO') }
    let!(:lancamentos) do
      [1, 2, 3].map { |m| create(:indicator_entry, project: projeto1, indicator: indicador, month: m) }
    end

    it 'descartar PRESERVA os lançamentos' do
      indicador.discard!

      expect(IndicatorEntry.where(indicator_id: indicador.id).count).to eq(3)
      expect(lancamentos.map { |l| l.reload.value }).to all(be_present)
    end

    it 'descartado sai de `kept` e o `discarded_at` fica gravado' do
      indicador.discard!

      expect(Indicator.kept).not_to include(indicador)
      expect(indicador.reload.discarded_at).to be_present
    end

    it 'a associação NÃO tem `dependent: :delete_all` — um destroy é RECUSADO, não silencioso' do
      expect(described_class.reflect_on_association(:entries).options[:dependent]).to eq(:restrict_with_error)
      expect(indicador.destroy).to be false
    end

    it 'reverter é possível — a exclusão deixou de ser definitiva' do
      indicador.discard!
      indicador.undiscard!

      expect(Indicator.kept).to include(indicador)
    end

    it 'o impacto é calculado ANTES de qualquer escrita (FE-315)' do
      create(:project_indicator_connection, project: projeto2, indicator: indicador)
      impacto = indicador.deletion_impact

      expect(impacto[:entries_count]).to eq(3)
      expect(impacto[:projects].map { |p| p[:name] }).to include(projeto1.name, projeto2.name)
    end
  end

  # ---------------------------------------------------------------------------
  describe 'ordenação (BE-312) — o achado A-5 do DEC-85' do
    # `../sfg/app/models/indicator.rb:64-71`: `get_ordering_key("key")` devolve
    # `"integration_key"`, **coluna que não existe** em `indicators` (a coluna é
    # `key`). Ordenar por "Chave" era `PG::UndefinedColumn` → 500.
    it 'a chave pública `key` aponta para a coluna `key`, não `integration_key`' do
      expect(described_class::ORDERING.allowed['key']).to eq(:key)
    end

    it 'ordenar por "Chave" não levanta erro de SQL' do
      create(:indicator, title: 'BBB')
      create(:indicator, title: 'AAA')

      relacao = described_class::ORDERING.apply(described_class.all, keys: ['key'], styles: ['up'])
      expect(relacao.map(&:key)).to eq(%w[aaa bbb])
    end

    it 'chave desconhecida é IGNORADA, não 500 (o legado fazia `nil + " "`)' do
      relacao = described_class::ORDERING.apply(described_class.all, keys: ['drop table'], styles: ['up'])
      expect { relacao.to_a }.not_to raise_error
    end
  end
end
