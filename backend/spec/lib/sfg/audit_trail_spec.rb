# frozen_string_literal: true

require 'rails_helper'

# S19 / DEC-59 / DEC-78 #1 — o portão da lista de models versionados.
#
# Este spec existe porque a lista é **deliberada e curta**, e listas deliberadas
# só continuam curtas se algo reprovar o contrário. Ele falha em quatro casos, e
# cada um é um jeito real de a decisão se perder:
#
#  1. um model ganha `has_paper_trail` sem estar declarado (a base dobra em
#     silêncio, com payload completo);
#  2. um model declarado existe mas esqueceu de ser versionado (a fatia dona
#     acrescentou a linha e não o `include`);
#  3. as opções (`skip`/`ignore`) do model divergem do que a lista declara;
#  4. um model declarado não tem verbete pt-BR — a trilha o mostraria com
#     rótulo derivado do nome da classe, em inglês, na tela.
RSpec.describe Sfg::AuditTrail do
  # Carrega tudo antes de perguntar "quem tem paper_trail?": em `development`
  # e `test` o Zeitwerk só define a constante quando alguém a nomeia, e sem isto
  # a varredura veria só os models que outros specs por acaso tocaram.
  before(:all) { Rails.application.eager_load! }

  describe 'a lista é a fonte da verdade' do
    it 'todo model versionado neste repositório está declarado' do
      versionados = ApplicationRecord.descendants.select { |k| k.respond_to?(:paper_trail_options) }
                                     .reject(&:abstract_class?)
                                     .map { |k| k.base_class.name }.uniq

      nao_declarados = versionados - described_class.declared_names
      expect(nao_declarados).to be_empty,
                                "models com `has_paper_trail` fora de Sfg::AuditTrail::VERSIONED: " \
                                "#{nao_declarados.join(', ')}. Com payload COMPLETO (DEC-78) cada save " \
                                'grava a foto inteira do registro — a lista é deliberada, declare a linha ' \
                                'com o motivo ou remova o `has_paper_trail`.'
    end

    it 'todo model declarado que JÁ existe está de fato versionado' do
      faltando = described_class.existing_models.reject { |k| k.respond_to?(:paper_trail_options) }
      expect(faltando.map(&:name)).to be_empty,
                                      'declarados em VERSIONED mas sem `include Auditable`/`has_paper_trail`.'
    end

    it 'as opções do model batem com as declaradas' do
      divergentes = described_class.existing_models.filter_map do |klass|
        esperado = described_class.options_for(klass.name)
        atual = klass.paper_trail_options || {}
        next if Array(atual[:skip]).map(&:to_sym).sort == Array(esperado[:skip]).map(&:to_sym).sort &&
                Array(atual[:ignore]).map(&:to_sym).sort == Array(esperado[:ignore]).map(&:to_sym).sort

        "#{klass.name}: declarado #{esperado.inspect}, model #{atual.slice(:skip, :ignore).inspect}"
      end

      expect(divergentes).to be_empty, divergentes.join(' | ')
    end

    it 'a lista de exclusões não contradiz a de inclusões' do
      expect(described_class::EXCLUDED.keys & described_class.declared_names).to be_empty
    end

    it 'todo model EXCLUÍDO que existe NÃO é versionado' do
      violando = described_class::EXCLUDED.keys.filter_map do |nome|
        klass = nome.safe_constantize
        nome if klass&.respond_to?(:paper_trail_options)
      end
      expect(violando).to be_empty
    end

    it 'cada exclusão tem o motivo escrito' do
      expect(described_class::EXCLUDED.values).to all(be_present)
    end

    it 'cada inclusão tem fatia dona e motivo escritos' do
      described_class::VERSIONED.each do |nome, dados|
        expect(dados[:slice]).to be_present, "#{nome} sem fatia dona"
        expect(dados[:why]).to be_present, "#{nome} sem motivo"
      end
    end
  end

  describe 'a lista chega antes dos models (S5..S12)' do
    it 'declara os models de auditoria financeira que o DEC-78 #1 nomeia' do
      expect(described_class.declared_names).to include(
        # **`ReceivableEntry`, não `Receivable`** (S6). Não há nem haverá um
        # model `Receivable`: a tabela do legado é `receivable_entries` e a
        # classe é `ReceivableEntry` (`../sfg/app/models/receivable_entry.rb:1`).
        # Com o nome antigo o `include Auditable` do model levantaria na carga
        # da classe — que é o portão funcionando. `Charge` e `Receipt` entram
        # pelo mesmo critério de auditoria financeira (DEC-63 os deu à S6).
        'RiskOperation', 'ReceivableEntry', 'Charge', 'Receipt',
        'Renegotiation', 'RiskControl', 'Contract',
        'User', 'UserType', 'Permission'
      )
    end

    it 'os pendentes são só os que ainda não nasceram, e não os da S0' do
      expect(described_class.pending_names).not_to include('User', 'Project', 'Membership')
    end
  end

  describe '.options_for' do
    it 'recusa model não declarado, com a mensagem dizendo o que fazer' do
      expect { described_class.options_for('Qualquer') }
        .to raise_error(ArgumentError, /não está declarado/)
    end

    it 'ignora `updated_at` por padrão — com payload completo, um touch gravaria o registro inteiro' do
      expect(described_class.options_for('Project')[:ignore]).to eq(%i[updated_at])
    end

    it 'o `jti` do usuário é `skip`, não `ignore`: não pode ser COPIADO para a trilha' do
      opts = described_class.options_for('User')
      expect(opts[:skip]).to include(:jti)
      expect(opts[:ignore]).to include(:last_login_at, :login_count)
    end
  end

  describe 'catálogo pt-BR' do
    it 'todo model declarado tem verbete com rótulo e gênero' do
      sem_verbete = described_class.declared_names.reject do |nome|
        v = I18n.t("audit_trail.entidades.#{nome}", default: nil)
        v.is_a?(Hash) && v[:rotulo].present? && %w[f m].include?(v[:genero].to_s)
      end
      expect(sem_verbete).to be_empty,
                             "sem verbete em config/locales/pt-BR.yml: #{sem_verbete.join(', ')}"
    end
  end

  describe '.filter — filtros COMBINÁVEIS (BE-432)' do
    let!(:a) do
      PaperTrail::Version.create!(item_type: 'Project', item_id: '1', event: 'create',
                                  whodunnit: '10', created_at: 3.days.ago)
    end
    let!(:b) do
      PaperTrail::Version.create!(item_type: 'Project', item_id: '2', event: 'update',
                                  whodunnit: '10', created_at: 2.days.ago)
    end
    let!(:c) do
      PaperTrail::Version.create!(item_type: 'Membership', item_id: '1', event: 'create',
                                  whodunnit: '20', created_at: 1.day.ago)
    end

    it 'dois filtros juntos reduzem o resultado — e o total é o do filtrado' do
      um = described_class.filter(item_type: 'Project')
      dois = described_class.filter(item_type: 'Project', event: 'create')

      expect(um.count).to eq(2)
      expect(dois.count).to eq(1)
      expect(dois.first).to eq(a)
    end

    it 'combina autor com período' do
      resultado = described_class.filter(whodunnit: '10', from: 2.5.days.ago)
      expect(resultado.to_a).to eq([b])
    end

    it 'sem filtro nenhum devolve tudo, do mais recente para o mais antigo' do
      expect(described_class.filter({}).to_a).to eq([c, b, a])
    end
  end

  describe '.for_record — o histórico do próprio objeto (DEC-77)' do
    it 'usa `base_class`, que é o que o paper_trail grava em `item_type`' do
      UserType.seed_default_types!
      dono = create(:user, user_type: UserType.og)
      projeto = Project.create!(name: 'Trilha', slug: 'trilha-s19', owner: dono)
      projeto.update!(name: 'Outro nome')

      historico = described_class.for_record(projeto)
      expect(historico.count).to eq(2)
      expect(historico.first.event).to eq('update')
      expect(historico.map(&:item_type).uniq).to eq(['Project'])
    end
  end
end
