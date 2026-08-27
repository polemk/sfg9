# frozen_string_literal: true

require 'rails_helper'

# S14 — os conversores de ETL do bloco de **estrutura** (S4): a ponte
# projeto↔portador, o fornecedor e a garantia de projeto.
#
# Os três não são catálogo: são escopados por projeto (C1), e o que estes testes
# travam é justamente o que muda quando o registro tem dono — a proveniência que
# NÃO pode ser copiada, o documento que passa a ser validado de verdade, e as
# duas colunas de endereço que o legado deixava passar torto.
#
# Como no `catalog_converters_spec`, os conversores são exercitados pela
# conversão pura (`convert`/`anomalies`), sem subir o motor: `ref` é resolvido
# por um duplo do `run`, que é exatamente o que o motor faz com o de-para.
RSpec.describe 'Conversores de ETL da estrutura (S14)' do
  let(:de_para) do
    {
      %w[livetat_auth_users 3] => 'cccccccc-0000-4000-8000-000000000003',
      %w[projects 7] => 'aaaaaaaa-0000-4000-8000-000000000001',
      %w[carriers 9] => 'dddddddd-0000-4000-8000-000000000009',
      %w[project_guarantee_types 2] => 'eeeeeeee-0000-4000-8000-000000000002'
    }
  end

  let(:run) do
    duplo = instance_double(Sfg::Etl::Run)
    allow(duplo).to receive(:resolve_reference) { |tabela, pk| de_para[[tabela, pk.to_s]] }
    duplo
  end

  # ===========================================================================
  describe Sfg::Etl::Converters::ProjectToCarrierConnections do
    subject(:conversor) { described_class.new(run) }

    # A linha de produção tem SEIS colunas úteis, e três delas se chamam
    # `legacy_*` — a proveniência de uma migração anterior à nossa.
    let(:linha) do
      { 'id' => 512, 'project_id' => 7, 'carrier_id' => 9,
        'legacy_id' => 4321, 'legacy_project_id' => 88, 'legacy_carrier_id' => 99,
        'created_at' => '2021-11-03 14:25:00', 'updated_at' => '2021-11-03 14:25:00' }
    end

    # ESTE é o teste que existe por causa de um número medido: `legacy_id` está
    # preenchida em 774 das 1.177 linhas de produção. As outras 403 são nulas —
    # e `legacy_id` no ai9 tem índice ÚNICO e é a chave natural. Copiar a coluna
    # errada faria 403 linhas casarem entre si e a carga terminaria com 775
    # registros no lugar de 1.177.
    it 'o `legacy_id` é o `id` da ORIGEM — NUNCA o `legacy_id` que a própria origem carrega' do
      convertido = conversor.convert(linha)

      expect(convertido[:legacy_id]).to eq(512)
      expect(convertido[:legacy_id]).not_to eq(4321)
    end

    it 'a proveniência do `fbancoproj` sobrevive nas DUAS colunas que não disputam a chave' do
      convertido = conversor.convert(linha)

      expect(convertido[:legacy_project_id]).to eq(88)
      expect(convertido[:legacy_carrier_id]).to eq(99)
    end

    it 'a chave natural sai do `id` da origem, que é o que o de-para indexa' do
      expect(conversor.natural_key(linha)).to eq(legacy_id: 512)
    end

    it 'projeto e portador são religados pelo DE-PARA, nunca pelo id numérico' do
      convertido = conversor.convert(linha)

      expect(convertido[:project_id]).to eq('aaaaaaaa-0000-4000-8000-000000000001')
      expect(convertido[:carrier_id]).to eq('dddddddd-0000-4000-8000-000000000009')
    end

    # No legado era só `validates_uniqueness_of :carrier_id, scope: [:project_id]`
    # — validação de aplicação, que duas abas furam. No ai9 é índice do banco.
    # Medido: as 1.177 linhas de produção já cabem na restrição, com 0 duplicata.
    it 'declara a unicidade (projeto, portador) que no legado era só validação de aplicação' do
      expect(described_class.uniques).to eq([%w[project_id carrier_id]])
    end

    it 'declara as duas referências, para o motor contar órfão em vez de gravar `nil`' do
      expect(described_class.references).to eq('project_id' => 'projects', 'carrier_id' => 'carriers')
    end

    # A tabela não tem autor nem flag de ativação em nenhum dos dois lados: a
    # conexão é fato binário, e desligá-la é apagá-la.
    it 'não inventa `user_id` nem `is_active` — nenhum dos dois existe nos dois lados' do
      convertido = conversor.convert(linha)

      expect(convertido).not_to have_key(:user_id)
      expect(convertido).not_to have_key(:is_active)
    end

    it 'os timestamps chegam em UTC pela regra da tz database (DEC-06)' do
      convertido = conversor.convert(linha)

      expect(convertido[:created_at].utc.strftime('%Y-%m-%d %H:%M')).to eq('2021-11-03 17:25')
    end
  end

  # ===========================================================================
  # `providers` é o conversor com mais redesenho de coluna da migração: 31
  # colunas na origem viram 27 no destino, e três pares legados viram um campo
  # cada. Os testes travam os três pares — e a anomalia que a produção tem.
  describe Sfg::Etl::Converters::Providers do
    subject(:conversor) { described_class.new(run) }

    let(:linha) do
      { 'id' => 55, 'project_id' => 7, 'user_id' => 3,
        'title' => '  Fornecedor Um  ', 'resume' => 'texto livre',
        'integration_key' => 'SSA', 'is_active' => 1,
        'cnpj' => '11.222.333/0001-81', 'cpf' => '',
        'nome' => 'Razao Social Um', 'fantasia' => 'Fantasia Um', 'situacao' => 'ATIVA',
        'abertura' => '2010-04-01', 'data_situacao' => '2010-04-05',
        'email' => 'contato@exemplo.invalid', 'telefone' => '(11) 4000-0000',
        'cep' => '01310-100', 'logradouro' => 'Avenida Um', 'numero' => '1000',
        'complemento' => 'sala 1', 'bairro' => 'Centro', 'municipio' => 'Sao Paulo', 'uf' => 'sp',
        'atividades' => nil, 'cnaes' => nil,
        'logo_file_name' => 'logo.png', 'logo_content_type' => 'image/png',
        'logo_file_size' => 1234, 'logo_updated_at' => '2020-01-01 10:00:00',
        'created_at' => '2022-03-10 08:15:00', 'updated_at' => '2023-06-01 09:00:00' }
    end

    # --- os três pares que viram um campo ------------------------------------

    # DC-11. Medido em produção: 195 só com CNPJ, 44 só com CPF, 50 sem nenhum,
    # 0 com os dois. Os 239 que existem passam no dígito verificador.
    it 'CNPJ e CPF viram o par `(document_type, document)`, somente dígitos' do
      convertido = conversor.convert(linha)

      expect(convertido[:document_type]).to eq('CNPJ')
      expect(convertido[:document]).to eq('11222333000181')
    end

    it 'sem CNPJ, o CPF ocupa o par' do
      convertido = conversor.convert(linha.merge('cnpj' => '', 'cpf' => '390.533.447-05'))

      expect(convertido[:document_type]).to eq('CPF')
      expect(convertido[:document]).to eq('39053344705')
    end

    # Os 50 fornecedores sem documento são caso legítimo: a regra "ao menos um"
    # estava COMENTADA no model do legado, e exigi-la agora reprovaria histórico.
    it 'sem documento nenhum, o par fica NULO dos dois lados — meio par é a coluna ilegível' do
      convertido = conversor.convert(linha.merge('cnpj' => nil, 'cpf' => ''))

      expect(convertido[:document_type]).to be_nil
      expect(convertido[:document]).to be_nil
    end

    # D-25 — medido: as duas colunas estão NULAS em 289 de 289 linhas, e por isso
    # a carga real grava `{}`. O parser existe porque o conversor não pode
    # depender de o dado continuar vazio.
    it '`atividades` e `cnaes` viram UM jsonb; vazias nos dois lados dão `{}`, não nulo' do
      expect(conversor.convert(linha)[:activities]).to eq({})
    end

    it 'lê o JSON de `atividades` e o YAML de `cnaes` preservando o nome legado da chave' do
      convertido = conversor.convert(
        linha.merge('atividades' => '[{"code":"62.01-5-01"}]', 'cnaes' => "---\n- '6201501'\n")
      )

      expect(convertido[:activities]).to eq('atividades' => [{ 'code' => '62.01-5-01' }],
                                            'cnaes' => %w[6201501])
    end

    # `serialize :cnaes` no legado é YAML, e YAML vindo do banco do cliente é
    # superfície de desserialização. Carga SEGURA, sempre.
    it 'YAML que tenta instanciar objeto arbitrário NÃO desserializa — vira nulo, nunca objeto' do
      convertido = conversor.convert(linha.merge('cnaes' => "--- !ruby/object:Struct\nfoo: 1\n"))

      expect(convertido[:activities]).to eq({})
    end

    # DEC-91 — o binário vive em `public/system/` e é religado por ActiveStorage
    # no passo 6.7. Medido: 0 dos 289 fornecedores tem logo.
    it 'as 4 colunas `logo_*` do Paperclip NÃO viajam — o binário é do passo 6.7 (DEC-91)' do
      convertido = conversor.convert(linha)

      expect(convertido.keys.map(&:to_s).grep(/logo/)).to be_empty
    end

    # --- o que o model normaliza, o conversor entrega normalizado -------------

    it '`zip_code` e `state` chegam como o model os gravaria, para a reconciliação comparar' do
      convertido = conversor.convert(linha)

      expect(convertido[:zip_code]).to eq('01310100')
      expect(convertido[:state]).to eq('SP')
    end

    it 'o título é aparado — mesmo motivo do `strip` de `SubSegments`' do
      expect(conversor.convert(linha)[:title]).to eq('Fornecedor Um')
    end

    it '`cnpj_fetched_at` nasce NULO: a coluna é do ai9 e todo migrado foi preenchido à mão' do
      expect(conversor.convert(linha)[:cnpj_fetched_at]).to be_nil
    end

    it 'a chave de integração é COPIADA da origem, nunca rederivada (DEC-85)' do
      expect(conversor.convert(linha)[:integration_key]).to eq('SSA')
    end

    it 'projeto e autor são religados pelo DE-PARA' do
      convertido = conversor.convert(linha)

      expect(convertido[:project_id]).to eq('aaaaaaaa-0000-4000-8000-000000000001')
      expect(convertido[:user_id]).to eq('cccccccc-0000-4000-8000-000000000003')
    end

    # --- a anomalia que a produção TEM ---------------------------------------

    # 6 grupos, 163 das 289 linhas, um deles com 119. Dentro de cada grupo os
    # títulos são TODOS distintos: a chave não foi derivada do título — são
    # rótulos de classificação digitados por gente. Declarar é o que faz o
    # dry-run abortar em vez de a carga parar no meio.
    it 'declara `(project_id, integration_key)` como unicidade — é o que faz a duplicata aparecer' do
      expect(described_class.uniques).to eq([%w[project_id integration_key]])
    end

    # --- as duas anomalias que a produção NÃO tem, e que existem mesmo assim --

    it 'CNPJ e CPF juntos: o CNPJ prevalece e o descarte do CPF vai para o relatório' do
      anomalias = conversor.anomalies(linha.merge('cpf' => '390.533.447-05'))

      expect(anomalias.map { |a| a[:key] }).to include('providers:two_documents')
      expect(conversor.convert(linha.merge('cpf' => '390.533.447-05'))[:document_type]).to eq('CNPJ')
    end

    it 'documento que não passa no dígito verificador é DECLARADO — o legado não validava o já gravado' do
      anomalias = conversor.anomalies(linha.merge('cnpj' => '11.111.111/1111-11'))

      expect(anomalias.map { |a| a[:key] }).to include('providers:invalid_document')
    end

    it 'o documento válido não gera anomalia nenhuma' do
      expect(conversor.anomalies(linha)).to be_empty
    end

    it 'o `legacy_id` é o `id` da origem e a chave natural sai dele' do
      expect(conversor.convert(linha)[:legacy_id]).to eq(55)
      expect(conversor.natural_key(linha)).to eq(legacy_id: 55)
    end
  end
end
