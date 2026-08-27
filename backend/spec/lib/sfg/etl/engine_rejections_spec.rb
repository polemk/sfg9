# frozen_string_literal: true

require 'rails_helper'

# S14 — **DEC-127: o motor COLETA as falhas, não morre na primeira.**
#
# O defeito que estes testes fecham (D-PAR-04) custou o dia 27/08/2026 inteiro:
# `Converters::Base#write!` chamava `save!` e ninguém resgatava `RecordInvalid`,
# então a carga morria na **primeira** linha inválida e se descobria **um defeito
# por execução** — com a execução completa levando ~1h só de `risk_entries`
# (642.447 linhas). Slug com `&`, CEP de 7 dígitos, título vazio, `NaN` nos
# derivados, `providers` ausente: cada um só apareceu depois de o anterior sair
# do caminho, e não havia como saber quantos faltavam.
#
# **O que estes testes precisam provar, e a distinção é o assunto todo:**
#
#   1. a linha inválida **NÃO ENTRA** no destino;
#   2. ela sai **LISTADA**, com id, tabela, campo e mensagem de validação;
#   3. a carga **CONTINUA** — as linhas seguintes, e os conversores seguintes;
#   4. o `load` **TERMINA REPROVADO** quando houve recusa;
#   5. o `dry_run` **continua abortando** em anomalia sem decisão registrada.
#
# Faltando o 3, é o defeito de volta. Faltando o 1 ou o 4, virou "ignorar erro" —
# que é pior que o defeito, porque parece que carregou.
RSpec.describe 'Sfg::Etl::Run — linhas recusadas (DEC-127)' do
  # Origem sintética: o mínimo para exercitar o motor sem arquivo nenhum.
  # `Source::Base` já dá `each_batch`, `table?` e `pks` em cima de `ordered_rows`.
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

  # `HelpCategory` é o alvo porque a validação dela é a mesma FORMA da que
  # derrubava a carga de verdade: `title` obrigatório, e 90 de 2.705
  # `availability_templates` chegam com título vazio (DEC-128.4).
  let(:categories_converter) do
    grupo_id = help_group.id
    Class.new(Sfg::Etl::Converters::Base) do
      define_singleton_method(:name) { 'Sfg::Etl::Converters::SpecHelpCategories' }
      define_singleton_method(:converter_name) { 'spec_help_categories' }
      define_singleton_method(:source_table) { 'help_categories' }
      define_singleton_method(:target_model) { 'HelpCategory' }
      define_method(:convert) { |row| { title: row['title'], help_group_id: grupo_id } }
    end
  end

  let(:help_group) { create(:help_group) }

  def run_load(tables, converters:, decisions: Sfg::Etl::Decisions.new([]))
    allow(Sfg::Etl::Pipeline).to receive(:converters).and_return(Array(converters))
    report = Sfg::Etl::Report.new('spec', io: StringIO.new)
    run = Sfg::Etl::Run.new(source: synthetic_source.new(tables), mode: :load, report: report,
                            io: StringIO.new, decisions: decisions,
                            run_id: "spec-#{SecureRandom.hex(4)}")
    outcomes = run.execute!
    [report, outcomes, run]
  end

  # ==========================================================================
  describe 'a linha inválida não entra, sai listada, e a carga SEGUE' do
    # Título vazio no meio: se o motor morresse na 2, a 3 nunca entraria.
    let(:tables) do
      { 'help_categories' => [{ 'id' => 1, 'title' => 'Primeira' },
                              { 'id' => 2, 'title' => '   ' },
                              { 'id' => 3, 'title' => 'Terceira' }] }
    end

    it 'CONTINUA depois da linha recusada — a de depois entra' do
      _report, outcomes, = run_load(tables, converters: categories_converter)

      expect(outcomes.first.read).to eq(3)
      expect(outcomes.first.written).to eq(2)
      expect(outcomes.first.rejected).to eq(1)
      expect(HelpCategory.where(help_group_id: help_group.id).pluck(:title))
        .to contain_exactly('Primeira', 'Terceira')
    end

    it 'a linha recusada NÃO ENTRA, e não fica no de-para' do
      run_load(tables, converters: categories_converter)

      expect(HelpCategory.where(help_group_id: help_group.id).count).to eq(2)
      expect(Sfg::Etl::IdMap.where(source_table: 'help_categories').pluck(:legacy_pk).map(&:to_i))
        .to contain_exactly(1, 3)
    end

    it 'sai LISTADA com id de origem, campo e mensagem de validação' do
      report, = run_load(tables, converters: categories_converter)
      texto = report.render

      expect(texto).to include('Linhas RECUSADAS por validação')
      expect(texto).to include('`help_categories`#2')
      expect(texto).to include('title')
      expect(texto).to include('não pode ficar em branco')
    end

    # DEC-123 — dado real de cliente não sai no relatório. A mensagem de
    # validação é `errors#message`, não `full_message`: ela diz o que está
    # errado, nunca **qual era o valor**.
    it 'NÃO escreve o valor recusado no relatório (DEC-123)' do
      tabelas = { 'help_categories' => [{ 'id' => 7, 'title' => '' },
                                        { 'id' => 8, 'title' => 'Válida' }] }
      report, = run_load(tabelas, converters: categories_converter)

      rejeicoes = report.reject_sections.flat_map(&:lines).join("\n")
      expect(rejeicoes).to include('`help_categories`#7')
      expect(rejeicoes).not_to include('Válida')
    end
  end

  # ==========================================================================
  describe 'o `load` termina REPROVADO quando houve recusa' do
    let(:tables) { { 'help_categories' => [{ 'id' => 1, 'title' => '' }] } }

    it 'o relatório fica `rejected?` e `failed?`' do
      report, = run_load(tables, converters: categories_converter)

      expect(report).to be_rejected
      expect(report).to be_failed
    end

    it 'o texto final diz CARGA INCOMPLETA — e não "sem bloqueio"' do
      report, = run_load(tables, converters: categories_converter)

      expect(report.render).to include('RESULTADO: CARGA INCOMPLETA')
      expect(report.render).not_to include('RESULTADO: sem bloqueio')
    end

    # A distinção que o desenho inteiro depende: recusa **não** é aborto.
    # `Run#run_converter` consulta `aborted?` no começo de CADA conversor — se a
    # recusa marcasse `:abort`, a primeira linha inválida bloquearia todos os
    # conversores seguintes, que é exatamente o defeito de volta.
    it 'NÃO fica `aborted?` — senão os conversores seguintes não rodariam' do
      report, = run_load(tables, converters: categories_converter)

      expect(report).not_to be_aborted
    end

    it 'sem recusa nenhuma o relatório continua "sem bloqueio"' do
      report, = run_load({ 'help_categories' => [{ 'id' => 1, 'title' => 'Boa' }] },
                         converters: categories_converter)

      expect(report).not_to be_failed
      expect(report.render).to include('RESULTADO: sem bloqueio')
    end
  end

  # ==========================================================================
  # É esta a diferença que a DEC-127 pediu: **uma execução revela todos os
  # casos**, em vez de um defeito por execução de ~1h.
  describe 'uma execução revela TODOS os casos, inclusive nos conversores seguintes' do
    let(:segundo_converter) do
      grupo_id = help_group.id
      Class.new(Sfg::Etl::Converters::Base) do
        define_singleton_method(:name) { 'Sfg::Etl::Converters::SpecHelpItems' }
        define_singleton_method(:converter_name) { 'spec_help_items' }
        define_singleton_method(:source_table) { 'help_items' }
        define_singleton_method(:target_model) { 'HelpCategory' }
        define_method(:convert) { |row| { title: row['title'], help_group_id: grupo_id } }
      end
    end

    it 'o conversor seguinte RODA e as recusas dele também aparecem' do
      report, outcomes, = run_load(
        { 'help_categories' => [{ 'id' => 1, 'title' => '' }],
          'help_items' => [{ 'id' => 50, 'title' => '' }, { 'id' => 51, 'title' => 'Ok' }] },
        converters: [categories_converter, segundo_converter]
      )

      expect(outcomes.map(&:converter)).to eq(%w[spec_help_categories spec_help_items])
      expect(outcomes.map(&:rejected)).to eq([1, 1])
      expect(report.render).to include('`help_categories`#1').and include('`help_items`#50')
    end

    it 'o RESUMO POR CAUSA agrupa as recusas de toda a execução' do
      report, = run_load(
        { 'help_categories' => [{ 'id' => 1, 'title' => '' }, { 'id' => 2, 'title' => '' },
                                { 'id' => 3, 'title' => 'Ok' }] },
        converters: categories_converter
      )

      resumo = report.sections.find { |s| s.title.include?('RESUMO POR CAUSA') }
      expect(resumo).to be_present
      expect(resumo.title).to include('2 linha(s)')
      expect(resumo.lines.join("\n")).to include('| 2 | `help_categories`.`title`')
    end

    it 'sem recusa nenhuma o resumo existe e diz isso — ausência de seção seria lida como "não conferido"' do
      report, = run_load({ 'help_categories' => [{ 'id' => 1, 'title' => 'Ok' }] },
                         converters: categories_converter)

      resumo = report.sections.find { |s| s.title.include?('Linhas recusadas') }
      expect(resumo.severity).to eq(:info)
      expect(resumo.lines.join("\n")).to include('nenhuma linha recusada')
    end
  end

  # ==========================================================================
  # O portão de 5.4 não pode ter sido afrouxado junto. `:abort` continua sendo
  # `:abort`, e continua acontecendo **antes da primeira escrita**.
  describe 'o portão de anomalia sem decisão NÃO foi afrouxado' do
    let(:converter_com_orfao) do
      Class.new(Sfg::Etl::Converters::Base) do
        define_singleton_method(:name) { 'Sfg::Etl::Converters::SpecOrphans' }
        define_singleton_method(:converter_name) { 'spec_orphans' }
        define_singleton_method(:source_table) { 'companies' }
        define_singleton_method(:target_model) { 'HelpCategory' }
        define_singleton_method(:references) { { 'project_id' => 'projects' } }
        define_method(:convert) { |row| { title: row['title'] } }
      end
    end

    let(:tabelas) do
      { 'companies' => [{ 'id' => 1, 'title' => 'X', 'project_id' => 999 }],
        'projects' => [{ 'id' => 1 }] }
    end

    it 'o dry-run continua ABORTANDO em órfão sem decisão registrada' do
      allow(Sfg::Etl::Pipeline).to receive(:converters).and_return([converter_com_orfao])
      report = Sfg::Etl::Report.new('spec', io: StringIO.new)
      Sfg::Etl::Run.new(source: synthetic_source.new(tabelas), mode: :dry_run, report: report,
                        io: StringIO.new, decisions: Sfg::Etl::Decisions.new([])).execute!

      expect(report).to be_aborted
      expect(report.render).to include('SEM DECISÃO REGISTRADA — ABORTA')
    end

    it 'a carga levanta `Blocked` ANTES de escrever a primeira linha' do
      allow(Sfg::Etl::Pipeline).to receive(:converters).and_return([converter_com_orfao])
      report = Sfg::Etl::Report.new('spec', io: StringIO.new)
      run = Sfg::Etl::Run.new(source: synthetic_source.new(tabelas), mode: :load, report: report,
                              io: StringIO.new, decisions: Sfg::Etl::Decisions.new([]),
                              run_id: "spec-#{SecureRandom.hex(4)}")

      expect { run.execute! }.to raise_error(Sfg::Etl::Run::Blocked)
      expect(HelpCategory.count).to eq(0)
    end
  end

  # ==========================================================================
  # DEC-127 — erro de BANCO não é recusa de validação, e continua sendo
  # barulhento. `save!` valida antes de emitir SQL, então `RecordInvalid` não
  # suja a transação do lote; um `StatementInvalid` suja, e seguir ali dentro
  # esconderia defeito de esquema ou de conversor.
  describe 'o resgate é ESTREITO — só validação' do
    let(:converter_que_explode) do
      Class.new(Sfg::Etl::Converters::Base) do
        define_singleton_method(:name) { 'Sfg::Etl::Converters::SpecBoom' }
        define_singleton_method(:converter_name) { 'spec_boom' }
        define_singleton_method(:source_table) { 'help_categories' }
        define_singleton_method(:target_model) { 'HelpCategory' }
        define_method(:convert) { |_row| raise ArgumentError, 'conversor com defeito' }
      end
    end

    it 'erro que não é de validação DERRUBA a execução, de propósito' do
      expect do
        run_load({ 'help_categories' => [{ 'id' => 1, 'title' => 'X' }] },
                 converters: converter_que_explode)
      end.to raise_error(ArgumentError, /conversor com defeito/)
    end
  end
end
