# frozen_string_literal: true

require 'rails_helper'

# S14 — os três conversores da **central de ajuda** (S12): grupo, categoria e
# item. São 5, 7 e 25 linhas em produção — o menor volume da migração e, ainda
# assim, o conjunto com mais decisão por linha, porque **duas das três colunas
# que importam não existem na origem** (`slug`, `position`) e a terceira (o
# corpo do item) mora em outra tabela.
#
# Os conversores são exercitados pela conversão pura (`convert`/`anomalies`),
# sem subir o motor: `ref` é resolvido por um duplo do `run`, e a origem por um
# duplo do `source` — que é exatamente o que o motor entrega.
RSpec.describe 'Conversores de ETL da central de ajuda (S14)' do
  let(:de_para) do
    {
      %w[livetat_auth_users 3] => 'cccccccc-0000-4000-8000-000000000003',
      %w[help_groups 4] => 'bbbbbbbb-0000-4000-8000-000000000004',
      %w[help_categories 6] => 'bbbbbbbb-0000-4000-8000-000000000006'
    }
  end

  # A tabela de texto rico do LEGADO, como o motor a entrega: linhas cruas, com
  # `record_type`/`record_id` do legado (integer, não uuid).
  let(:textos_ricos) do
    [
      { 'id' => 1, 'record_type' => 'HelpItem', 'record_id' => 12, 'name' => 'description',
        'body' => '<div class="trix-content">corpo de 2024</div>' },
      { 'id' => 2, 'record_type' => 'Indicator', 'record_id' => 12, 'name' => 'description',
        'body' => '<div>corpo de OUTRO dono, com o MESMO id</div>' }
    ]
  end

  let(:origem) do
    duplo = instance_double(Sfg::Etl::Source::Base)
    allow(duplo).to receive(:table?).with('action_text_rich_texts').and_return(true)
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
  describe Sfg::Etl::Converters::HelpGroups do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 4, 'title' => ' Painel de Risco ',
        'created_at' => '2022-02-10 11:00:00', 'updated_at' => '2022-02-10 11:00:00' }
    end

    # BE-358 — o `permit` do legado aceitava `:user_id` numa tabela que NÃO TEM
    # a coluna. Um formulário que o enviasse causaria `UnknownAttributeError`.
    it 'NÃO carrega `user_id`: a coluna nunca existiu na tabela (BE-358)' do
      expect(conversor.convert(linha)).not_to have_key(:user_id)
    end

    # DB-367 — no legado a view ordenava por `title ASC`, então renomear um grupo
    # reordenava o menu. A coluna é nova e o model a atribui na criação.
    it 'NÃO inventa `position` — a coluna é do ai9 e nasce no model, na ordem de leitura' do
      expect(conversor.convert(linha)).not_to have_key(:position)
      expect(described_class.derived).to include('position')
    end

    it 'apara o título, para a reconciliação comparar o que foi gravado' do
      expect(conversor.convert(linha)[:title]).to eq('Painel de Risco')
    end

    it 'a raiz da árvore não tem referência nenhuma a religar' do
      expect(described_class.references).to be_empty
    end

    it 'o `legacy_id` é o `id` da origem e a chave natural sai dele' do
      expect(conversor.convert(linha)[:legacy_id]).to eq(4)
      expect(conversor.natural_key(linha)).to eq(legacy_id: 4)
    end
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::HelpCategories do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 6, 'help_group_id' => 4, 'title' => 'Conceitos',
        'created_at' => '2022-02-10 11:05:00', 'updated_at' => '2022-02-10 11:05:00' }
    end

    # DB-368 — o slug precisa ser PERSISTIDO e desambiguado, e quem faz as duas
    # coisas é `HelpCategory#assign_slug`. Medido em produção: dos 7 títulos saem
    # 5 slugs distintos — dois pares de homônimas, em grupos diferentes. Duplicar
    # a regra aqui criaria dois lugares que precisam concordar para sempre.
    it 'NÃO calcula o slug — quem desambigua é o model, com sufixo determinístico (DB-368)' do
      expect(conversor.convert(linha)).not_to have_key(:slug)
      expect(described_class.derived).to include('slug')
    end

    it 'o grupo é religado pelo DE-PARA, nunca pelo id numérico da origem' do
      expect(conversor.convert(linha)[:help_group_id]).to eq('bbbbbbbb-0000-4000-8000-000000000004')
    end

    it 'declara a unicidade (grupo, título) que o legado só validava em aplicação' do
      expect(described_class.uniques).to eq([%w[help_group_id title]])
    end
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::HelpItems do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 12, 'help_category_id' => 6, 'user_id' => 3, 'title' => 'Como lançar',
        'description' => nil,
        'created_at' => '2022-03-04 19:47:55', 'updated_at' => '2022-03-09 16:53:09' }
    end

    # O ai9 recusa corpo vazio (BE-352) e o corpo é ActionText, que na ordem de
    # carga só chega no ÚLTIMO passo. Sem ler o corpo aqui, os 25 itens seriam
    # recusados um a um no meio da janela de cutover.
    it 'traz o corpo do acervo ActionText junto com o item — sem isso o item nem salva (BE-352)' do
      expect(conversor.convert(linha)[:description]).to eq('<div class="trix-content">corpo de 2024</div>')
    end

    # O `record_id` do legado é integer e se repete entre donos diferentes: o
    # indicador 12 e o item 12 existem os dois. Filtrar por `record_type` não é
    # zelo — é o que impede o corpo do indicador de virar corpo do item.
    it 'só olha `record_type = HelpItem`: o `record_id` do legado se repete entre donos' do
      corpo = conversor.convert(linha)[:description]

      expect(corpo).not_to include('OUTRO dono')
    end

    # D-58 — o legado tem DOIS acervos: a coluna (até 04/2019) e o ActionText
    # (depois). `has_rich_text` sobrescreveu o leitor da coluna, e a busca por
    # conteúdo passou a mentir. A ordem certa é ActionText primeiro.
    it 'ActionText VENCE a coluna — inverter faria o texto de 2018 cobrir o de 2024 (D-58)' do
      convertido = conversor.convert(linha.merge('description' => 'corpo de 2018, da coluna'))

      expect(convertido[:description]).to eq('<div class="trix-content">corpo de 2024</div>')
    end

    it 'sem ActionText, a coluna assume — é o acervo escrito até 04/2019' do
      convertido = conversor.convert(linha.merge('id' => 99, 'description' => 'corpo de 2018, da coluna'))

      expect(convertido[:description]).to eq('corpo de 2018, da coluna')
    end

    # FE-366 — no legado o `user_id` viajava num campo escondido sempre com o
    # `current_user`: editar item de outro autor REESCREVIA a autoria. As duas
    # colunas do ai9 existem para desfazer essa confusão; copiar o autor para as
    # duas seria refazê-la.
    it 'o autor vai para `user_id` e `last_updated_user_id` fica NULO (FE-366)' do
      convertido = conversor.convert(linha)

      expect(convertido[:user_id]).to eq('cccccccc-0000-4000-8000-000000000003')
      expect(convertido[:last_updated_user_id]).to be_nil
    end

    it 'item sem corpo em NENHUM dos dois acervos é DECLARADO, não convertido em silêncio' do
      anomalias = conversor.anomalies(linha.merge('id' => 99, 'description' => '   '))

      expect(anomalias.map { |a| a[:key] }).to eq(['help_items:without_body'])
    end

    it 'item com corpo não gera anomalia' do
      expect(conversor.anomalies(linha)).to be_empty
    end

    it 'declara as duas referências, para o motor contar órfão em vez de gravar `nil`' do
      expect(described_class.references)
        .to eq('help_category_id' => 'help_categories', 'user_id' => 'livetat_auth_users')
    end
  end
end
