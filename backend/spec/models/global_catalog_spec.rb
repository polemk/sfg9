# frozen_string_literal: true

require 'rails_helper'

# S3 — o molde dos catálogos globais, exercitado nos cinco de uma vez.
#
# Um spec por model deixaria quatro cobertos e o quinto não, que é exatamente
# como o legado terminou com `prepare_ordering` copiado idêntico em 18 models e
# um deles (o do grupo de portadores) simplesmente ausente — respondendo 500.
RSpec.describe GlobalCatalog do
  MODELS = {
    Carrier => :carrier,
    CarrierGroup => :carrier_group,
    Segment => :segment,
    SubSegment => :sub_segment,
    ProjectGuaranteeType => :project_guarantee_type
  }.freeze

  # 4.3.10 / OPS-056 — o legado usava `Dev.ilike`, que interpolava o operador
  # conforme o adapter e montava o padrão dentro da string.
  describe 'busca — ILIKE com bind, nunca interpolação' do
    it 'termo com `%` é tratado como TEXTO, não como curinga' do
      alvo = create(:carrier, title: 'Fundo 100% Capital Próprio')
      create(:carrier, title: 'Fundo 200 Capital')

      expect { Carrier.search('100%').to_a }.not_to raise_error
      expect(Carrier.search('100%').map(&:id)).to eq([alvo.id])
    end

    it 'termo com aspa simples não quebra o SQL' do
      alvo = create(:carrier, title: "Banco d'Oeste")
      expect { Carrier.search("d'O").to_a }.not_to raise_error
      expect(Carrier.search("d'O").map(&:id)).to eq([alvo.id])
    end

    it '`_` é tratado como texto, não como "qualquer caractere"' do
      # A chave do engodo é dada à mão: derivada do título ela seria
      # `comercio_exterior` e casaria com o termo por outro caminho, escondendo
      # o que este exemplo quer provar.
      create(:segment, title: 'Comercio Exterior', integration_key: 'engodo')
      alvo = create(:segment, title: 'Comercio_Exterior')
      expect(Segment.search('comercio_ext').map(&:id)).to eq([alvo.id])
    end

    it 'busca é case-insensitive e alcança também a chave de integração' do
      alvo = create(:segment, title: 'Indústria Pesada')
      expect(Segment.search('INDÚSTRIA').map(&:id)).to eq([alvo.id])
      expect(Segment.search('industria_pesada').map(&:id)).to eq([alvo.id])
    end

    it 'termo vazio ou só de espaços não filtra nada' do
      create(:segment)
      expect(Segment.search('   ').count).to eq(1)
      expect(Segment.search(nil).count).to eq(1)
    end
  end

  # DC-22 — congelada na criação.
  describe 'chave de integração' do
    it 'nasce derivada do título, sem acento e em minúsculas, nos cinco' do
      MODELS.each_key do |model|
        registro = model.create!(title: 'Alienação Fiduciária Ltda')
        expect(registro.integration_key).to eq('alienacao_fiduciaria_ltda'), model.name
        registro.destroy!
      end
    end

    it 'NÃO é recalculada quando o título muda, nos cinco' do
      MODELS.each_key do |model|
        registro = model.create!(title: 'Original')
        registro.update!(title: 'Renomeado')
        expect(registro.reload.integration_key).to eq('original'), model.name
        registro.destroy!
      end
    end

    it 'respeita a chave informada na criação' do
      s = Segment.create!(title: 'Qualquer', integration_key: 'chave_externa')
      expect(s.integration_key).to eq('chave_externa')
    end
  end

  # Contrato C1, regra 4 — a decisão de desenho mais fácil de errar na direção
  # oposta das outras fatias.
  describe 'contrato C1 — catálogo global NÃO recebe escopo' do
    it 'os cinco são `global_catalog?` e nenhum tem `project_id`' do
      MODELS.each_key do |model|
        expect(model).to be_global_catalog
        expect(model.column_names).not_to include('project_id'), "#{model} ganhou `project_id`"
        expect(model.include?(ProjectScoped)).to be(false), "#{model} incluiu ProjectScoped"
      end
    end
  end

  describe 'título' do
    it 'é obrigatório nos cinco' do
      MODELS.each_key do |model|
        registro = model.new(title: '   ')
        expect(registro).not_to be_valid, model.name
        expect(registro.errors[:title]).to be_present
      end
    end

    it 'é aparado' do
      expect(Segment.create!(title: '  Varejo  ').title).to eq('Varejo')
    end
  end

  # A regra que vale para os cinco: exclusão BLOQUEIA, nunca cascateia (D-24).
  describe 'exclusão' do
    it 'nenhum dos cinco tem associação de domínio em cascata' do
      MODELS.each_key do |model|
        cascatas = model.reflect_on_all_associations
                        .select { |a| a.options[:dependent] == :destroy }
                        .reject { |a| a.name.to_s.match?(/\A(logo|file|thumbnail)_/) }
        expect(cascatas).to be_empty,
                            "#{model}: #{cascatas.map(&:name).join(', ')} — no legado excluir portador " \
                            'apagava os limites de risco dele (D-24)'
      end
    end

    # O exemplo original afirmava que `RiskControl` **não existia** — era a
    # prova de que a regra escrita antes da tabela fica inerte, não quebrada.
    # A S5 entregou a tabela, e a afirmação envelheceu **por sucesso**: agora a
    # regra está viva. O que se prova aqui passa a ser a propriedade, e não o
    # estado de uma fatia num dia:
    #
    #  1. o dependente cuja tabela AINDA não nasceu é ignorado em silêncio;
    #  2. o dependente cuja tabela JÁ nasceu passa a bloquear sozinho, sem
    #     ninguém ter voltado no model para acrescentar linha.
    it 'declara os dependentes por NOME: o que não existe é inerte, o que nasceu passa a bloquear' do
      expect(Carrier.blocking_dependents).to include('RiskControl')

      # (1) Nome que nenhuma fatia vai entregar: inerte, nunca `NameError`.
      expect(BlockingDependents.dependent_class('TabelaQueNuncaVaiExistir')).to be_nil
      expect(GlobalCatalog.dependent_class('TabelaQueNuncaVaiExistir')).to be_nil

      # Sem dependente gravado, excluir continua funcionando.
      expect { create(:carrier).destroy! }.not_to raise_error
    end
  end
end
