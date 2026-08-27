# frozen_string_literal: true

require 'rails_helper'

# S14 — **o gancho `post_load!` existia e ninguem o chamava.**
#
# Quatro conversores (`RiskControls`, `RiskEntries`, `RiskMovementTypes`,
# `RiskOperationSubtypes`) definem `post_load!` desde `cf84f5bf6`. O unico
# chamador em toda a arvore era um spec, que o executava **na mao** — e por isso
# ele passava, provando que o metodo funciona e **nada** sobre ele acontecer numa
# carga. Consequencia medida: o `is_default_for_type` da DEC-67 nunca foi marcado
# numa carga real.
#
# **Por isso este arquivo nunca chama `post_load!` diretamente.** Ele roda o
# MOTOR e confere o EFEITO no banco. Um teste que chamasse o metodo repetiria
# exatamente o erro que deixou o defeito invisivel por um dia inteiro.
RSpec.describe 'Sfg::Etl::Run — o gancho post_load! (DEC-67)' do
  let(:synthetic_source) do
    Class.new(Sfg::Etl::Source::Base) do
      def initialize(tables) # rubocop:disable Lint/MissingSuper
        @tables = tables
      end

      def describe = 'origem sintética de teste'
      def tables = @tables.keys.sort
      def count(table) = @tables.fetch(table.to_s, []).size
      def ordered_rows(table, pk: 'id') = @tables.fetch(table.to_s, []).sort_by { |r| r[pk].to_i }

      def columns(table)
        rows = @tables.fetch(table.to_s, [])
        rows.flat_map(&:keys).uniq.map do |n|
          { name: n, type: n.to_s.end_with?('_at') ? 'timestamp' : 'character varying', null: true }
        end
      end
    end
  end

  def executar(tables, converters:, mode: :load)
    allow(Sfg::Etl::Pipeline).to receive(:converters).and_return(Array(converters))
    report = Sfg::Etl::Report.new('spec', io: StringIO.new)
    Sfg::Etl::Run.new(source: synthetic_source.new(tables), mode: mode, report: report,
                      io: StringIO.new, decisions: Sfg::Etl::Decisions.new([]),
                      run_id: "spec-#{SecureRandom.hex(4)}").execute!
    report
  end

  # ==========================================================================
  # O EFEITO, no banco. Nao "o metodo rodou" — `is_default_for_type` marcado.
  describe 'DEC-67 — `is_default_for_type` fica marcado numa carga' do
    # O tipo GERA os proprios subtipos no `after_create` (dois quando ha
    # pre-faturamento). Sao eles o alvo do gancho, e nascem todos com
    # `is_default_for_type` falso — que e o estado que a carga precisa corrigir.
    let!(:tipo_com_pre) { create(:risk_operation_type, :com_pre) }
    let!(:tipo_sem_pre) { create(:risk_operation_type) }

    before do
      RiskOperationSubtype.update_all(is_default_for_type: false) # rubocop:disable Rails/SkipsModelValidations
    end

    # A guarda que faz o resto valer: se ja nascesse marcado, o teste passaria
    # sem o motor fazer nada.
    it 'o ponto de partida e "nenhum subtipo padrao" — senao o resto nao prova nada' do
      expect(RiskOperationSubtype.where(is_default_for_type: true).count).to eq(0)
    end

    it 'depois da carga, CADA tipo tem exatamente UM subtipo padrao' do
      executar({ 'risk_operation_subtypes' => [] },
               converters: Sfg::Etl::Converters::RiskOperationSubtypes)

      [tipo_com_pre, tipo_sem_pre].each do |tipo|
        marcados = tipo.subtypes.where(is_default_for_type: true)
        expect(marcados.count).to eq(1), "tipo #{tipo.id} ficou com #{marcados.count} padrão(ões)"
      end
    end

    # DEC-67 reproduz o `subtypes.where(...).pluck(:id).first` SEM `order` do
    # legado. A ordem canonica da associacao (`is_pre: :desc, created_at: :asc`)
    # e o que aquele `.first` devolvia — o "pre" nasce antes.
    it 'o marcado e o que o `.first` do legado escolheria' do
      executar({ 'risk_operation_subtypes' => [] },
               converters: Sfg::Etl::Converters::RiskOperationSubtypes)

      expect(tipo_com_pre.subtypes.first.reload.is_default_for_type).to be(true)
    end

    it 'e IDEMPOTENTE: rodar de novo nao acumula um segundo padrao' do
      2.times do
        executar({ 'risk_operation_subtypes' => [] },
                 converters: Sfg::Etl::Converters::RiskOperationSubtypes)
      end

      expect(tipo_com_pre.subtypes.where(is_default_for_type: true).count).to eq(1)
    end

    it 'o relatorio registra o passo, com a contagem' do
      report = executar({ 'risk_operation_subtypes' => [] },
                        converters: Sfg::Etl::Converters::RiskOperationSubtypes)

      secao = report.sections.find { |s| s.title.include?('Passo pós-carga') }
      expect(secao).to be_present
      expect(secao.lines.join("\n")).to include('marked').and include('2')
    end

    # O gancho ESCREVE. Num dry-run ele nao pode acontecer — senao "não escreve
    # nada" deixaria de ser verdade.
    it 'o `dry_run` NAO chama o gancho — ele escreve' do
      report = executar({ 'risk_operation_subtypes' => [] },
                        converters: Sfg::Etl::Converters::RiskOperationSubtypes, mode: :dry_run)

      expect(RiskOperationSubtype.where(is_default_for_type: true).count).to eq(0)
      expect(report.sections.map(&:title)).not_to include(a_string_including('Passo pós-carga'))
    end
  end

  # ==========================================================================
  describe 'o contrato do gancho' do
    let(:com_gancho) do
      Class.new(Sfg::Etl::Converters::Base) do
        define_singleton_method(:name) { 'Sfg::Etl::Converters::SpecComGancho' }
        define_singleton_method(:converter_name) { 'spec_com_gancho' }
        define_singleton_method(:source_table) { 'help_groups' }
        define_singleton_method(:target_model) { 'HelpGroup' }
        define_singleton_method(:post_load!) { { conferido: 'sim', faltando: [] } }
        define_method(:convert) { |row| { title: row['title'] } }
      end
    end

    let(:gancho_que_explode) do
      Class.new(Sfg::Etl::Converters::Base) do
        define_singleton_method(:name) { 'Sfg::Etl::Converters::SpecGanchoRuim' }
        define_singleton_method(:converter_name) { 'spec_gancho_ruim' }
        define_singleton_method(:source_table) { 'help_groups' }
        define_singleton_method(:target_model) { 'HelpGroup' }
        define_singleton_method(:post_load!) { raise 'o gancho quebrou' }
        define_method(:convert) { |row| { title: row['title'] } }
      end
    end

    let(:sem_gancho) do
      Class.new(Sfg::Etl::Converters::Base) do
        define_singleton_method(:name) { 'Sfg::Etl::Converters::SpecSemGancho' }
        define_singleton_method(:converter_name) { 'spec_sem_gancho' }
        define_singleton_method(:source_table) { 'help_groups' }
        define_singleton_method(:target_model) { 'HelpGroup' }
        define_method(:convert) { |row| { title: row['title'] } }
      end
    end

    let(:linhas) { { 'help_groups' => [{ 'id' => 1, 'title' => 'Grupo' }] } }

    it 'transcreve o Hash devolvido, sem interpretar' do
      report = executar(linhas, converters: com_gancho)

      secao = report.sections.find { |s| s.title.include?('Passo pós-carga') }
      expect(secao.lines.join("\n")).to include('**conferido**: sim').and include('**faltando**: (vazio)')
    end

    # Conversor que nao declara o gancho nao ganha secao nenhuma — secao vazia em
    # 46 conversores seria ruido, e ruido esconde a secao que importa.
    it 'conversor SEM gancho nao produz secao' do
      report = executar(linhas, converters: sem_gancho)

      expect(report.sections.map(&:title)).not_to include(a_string_including('Passo pós-carga'))
    end

    # Mesma escolha das linhas recusadas, pela mesma razao: reprovar sem
    # interromper. As linhas ja entraram; o que falhou foi o ajuste depois delas.
    it 'gancho que levanta REPROVA a carga, mas nao interrompe os conversores seguintes' do
      report = executar(linhas, converters: [gancho_que_explode, com_gancho])

      expect(report).to be_rejected
      expect(report).not_to be_aborted
      expect(report.render).to include('Passo pós-carga FALHOU').and include('o gancho quebrou')
      # o conversor seguinte rodou:
      expect(report.render).to include('**conferido**: sim')
    end
  end

  # ==========================================================================
  # A regressao que interessa: o gancho existir nos conversores E o motor saber
  # dele. Se alguem apagar a chamada, este teste cai.
  describe 'os quatro conversores que declaram o gancho continuam declarando' do
    it 'e o motor os reconhece por `post_load?`' do
      [Sfg::Etl::Converters::RiskControls,
       Sfg::Etl::Converters::RiskEntries,
       Sfg::Etl::Converters::RiskMovementTypes,
       Sfg::Etl::Converters::RiskOperationSubtypes].each do |klass|
        expect(klass).to be_post_load, "#{klass} deixou de declarar `post_load!`"
      end
    end

    it 'e o motor CHAMA quem declara — a chamada existe no `run_converter`' do
      # Não é teste de texto por preguiça: é a única forma de travar a LIGAÇÃO
      # entre motor e conversor, que é justamente o que faltava. O efeito no
      # banco está provado acima; isto trava a chamada não sumir de novo.
      fonte = Rails.root.join('app/lib/sfg/etl/run.rb').read
      expect(fonte).to include('run_post_load!(converter_class)')
      expect(fonte).to match(/def run_post_load!/)
    end
  end
end
