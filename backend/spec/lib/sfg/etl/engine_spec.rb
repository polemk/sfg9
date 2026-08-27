# frozen_string_literal: true

require 'rails_helper'

# S14 — o motor do ETL de produção.
#
# **O que estes testes NÃO provam:** que o ETL funciona. Isso se prova executando
# (`rake sfg_etl:rehearsal`), e é assim que os quatro defeitos reais desta fatia
# apareceram — a ordem de carga que deixava `carriers.user_id` nulo, o
# `subordinated_accounts_percent` que o model recalcula, o `updated_at` carimbado
# com a data de hoje e o `identifier` fora do formato do ai9. Nenhum deles teria
# aparecido num teste que estubasse o banco.
#
# O que eles provam é o **contrário do que se espera de um teste de ETL**: que o
# motor FALHA nos lugares certos.
RSpec.describe 'Sfg::Etl' do
  # Origem sintética: o mínimo para exercitar o motor sem arquivo nenhum.
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

  # ==========================================================================
  describe 'contrato C3 — de-para de papel (Legacy::RoleMap)' do
    it 'traduz os quatro papéis do legado para a escala do ai9, que é INVERTIDA' do
      expect(Legacy::RoleMap.resolve(hierarchy: 1111)).to eq([UserType::OG, false])
      expect(Legacy::RoleMap.resolve(hierarchy: 998)).to eq([UserType::ADMIN, false])
      expect(Legacy::RoleMap.resolve(hierarchy: 888)).to eq([UserType::GERENTE, false])
      expect(Legacy::RoleMap.resolve(hierarchy: 799)).to eq([UserType::COLABORADOR, false])
    end

    it 'FALHA ALTO em valor inesperado, em vez de produzir um nível plausível' do
      # É o coração do C3. Uma fórmula (`1111 -> 1`, `998 -> 2`, …) sobreviveria a
      # `900` e devolveria algo entre 2 e 3 — plausível e errado. A tabela levanta.
      [900, 1, 0, -1, 9999, 'Diretor'].each do |unexpected|
        expect { Legacy::RoleMap.resolve(hierarchy: unexpected) }
          .to raise_error(Legacy::RoleMap::UnknownLegacyRole, /tabela explícita/),
              "hierarchy=#{unexpected.inspect} deveria levantar, e não virar um nível qualquer"
      end
    end

    it 'não existe fórmula convertendo hierarchy em hierarchy_level em lugar nenhum do repositório' do
      # Um implementador zeloso "simplificaria" a tabela numa aritmética. Este teste
      # existe para reprovar essa simplificação.
      source = Rails.root.join('app/services/legacy/role_map.rb').read
      expect(source).not_to match(%r{hierarchy\s*[/*+-]}),
                            'apareceu aritmética sobre `hierarchy` — o de-para é TABELA, nunca fórmula'
    end

    it 'papel vazio (D-36) entra como Colaborador E marcado como exceção' do
      expect(Legacy::RoleMap.resolve(hierarchy: nil, name: nil)).to eq([UserType::COLABORADOR, true])
      expect(Legacy::RoleMap.resolve(hierarchy: '', name: '')).to eq([UserType::COLABORADOR, true])
    end

    # DISCIPLINA DE TESTE DO C3, não negociável: verificar os DOIS lados. Um teste
    # que só confira que a trava existe **passa com o sinal invertido**, porque a
    # trava existe — apontando para o lado errado.
    describe 'hierarquia — os dois lados' do
      before { Seeds::Reference::UserTypes.call! }

      let(:og) { UserType.find_by(name: UserType::OG) }
      let(:admin) { UserType.find_by(name: UserType::ADMIN) }
      let(:colab) { UserType.find_by(name: UserType::COLABORADOR) }

      it 'Admin NÃO alcança OG' do
        expect(UserType.higher_than(admin.hierarchy_level)).to include(og)
        expect(UserType.lower_than(admin.hierarchy_level)).not_to include(og)
      end

      it 'Admin ALCANÇA Colaborador' do
        expect(UserType.lower_than(admin.hierarchy_level)).to include(colab)
      end

      it 'menor número = mais poder (o oposto do legado)' do
        expect(og.hierarchy_level).to be < admin.hierarchy_level
        expect(admin.hierarchy_level).to be < colab.hierarchy_level
      end
    end
  end

  # ==========================================================================
  describe 'Sfg::Etl::Values — conversores de valor' do
    it 'converte hora local de Brasília para UTC pelas transições da tz database' do
      # 2017 tinha horário de verão (UTC-2); 2022 não (UTC-3). Offset fixo erraria um
      # dos dois — é o D-102.
      expect(Sfg::Etl::Values.to_utc('2017-01-15 10:00:00').value.utc.strftime('%H:%M')).to eq('12:00')
      expect(Sfg::Etl::Values.to_utc('2022-01-15 10:00:00').value.utc.strftime('%H:%M')).to eq('13:00')
    end

    it 'reexibe em Brasília exatamente a mesma hora local, ano a ano de 2016 a 2026' do
      (2016..2026).each do |year|
        local = "#{year}-01-15 10:00:00"
        back = Sfg::Etl::Values.to_utc(local).value.in_time_zone(Sfg::Etl::Values::ZONE_NAME)
        expect(back.strftime('%Y-%m-%d %H:%M:%S')).to eq(local)
      end
    end

    it 'resolve a hora AMBÍGUA da virada de outono pela regra padrão E a reporta' do
      # 2018-02-17 23:30 acontece duas vezes: o relógio volta de 00:00 para 23:00.
      converted = Sfg::Etl::Values.to_utc('2018-02-17 23:30:00', table: 'carriers', pk: 2, column: 'updated_at')
      expect(converted.value).to be_present
      expect(converted).to be_anomaly
      expect(converted.anomaly).to include('ambígua')
    end

    it 'reporta booleano fora de {0,1} em vez de engolir como false' do
      expect(Sfg::Etl::Values.to_boolean(1).value).to be(true)
      expect(Sfg::Etl::Values.to_boolean(0).value).to be(false)

      out = Sfg::Etl::Values.to_boolean(2, table: 't', pk: 9, column: 'is_active')
      expect(out.value).to be_nil
      expect(out).to be_anomaly
    end

    it 'reporta enum fora do de-para em vez de virar nil silencioso' do
      map = Sfg::Etl::Values::RECEIVABLE_STATUS
      expect(Sfg::Etl::Values.to_enum_key('Diferença', map).value).to eq('difference')
      expect(Sfg::Etl::Values.to_enum_key('OK', map).value).to eq('ok')

      out = Sfg::Etl::Values.to_enum_key('Pendente', map, table: 'receivable_entries', pk: 1, column: 'status')
      expect(out.value).to be_nil
      expect(out).to be_anomaly
    end

    it 'DEC-89: título de indicador em CAIXA ALTA e sem acento' do
      expect(Sfg::Etl::Values.indicator_title('Inadimplência')).to eq('INADIMPLENCIA')
    end
  end

  # ==========================================================================
  describe 'Sfg::Etl::IdMap — a peça que sustenta a idempotência' do
    it 'registra o vínculo uma vez só, mesmo chamado duas vezes' do
      uuid = SecureRandom.uuid
      2.times do
        Sfg::Etl::IdMap.record!(source_table: 'carriers', legacy_pk: 42, target_table: 'carriers', ai9_id: uuid)
      end
      expect(Sfg::Etl::IdMap.where(source_table: 'carriers', legacy_pk: 42).count).to eq(1)
    end

    it 'devolve nil para referência sem correspondência — nunca inventa id' do
      expect(Sfg::Etl::IdMap.resolve('projects', 999_999)).to be_nil
    end
  end

  # ==========================================================================
  describe 'Sfg::Etl::Introspection — DB-ETL-01' do
    let(:baseline) do
      { 'tables' => { 'carriers' => { 'columns' => [{ 'name' => 'id', 'type' => 'integer' },
                                                    { 'name' => 'title', 'type' => 'string' }] },
                      'contracts' => { 'columns' => [{ 'name' => 'id', 'type' => 'integer' }] },
                      'availability_templates' => { 'columns' => [{ 'name' => 'id', 'type' => 'integer' }] } } }
    end

    def introspect(tables)
      report = Sfg::Etl::Report.new('spec', io: StringIO.new)
      Sfg::Etl::Introspection.new(synthetic_source.new(tables), report: report, baseline: baseline).run!
      report
    end

    it 'não aborta quando a origem cabe no esperado' do
      expect(introspect('carriers' => [{ 'id' => 1, 'title' => 'x' }])).not_to be_aborted
    end

    it 'ABORTA numa coluna desconhecida, nomeando o que encontrou' do
      report = introspect('carriers' => [{ 'id' => 1, 'title' => 'x', 'coluna_surpresa' => 'y' }])
      expect(report).to be_aborted
      expect(report.render).to include('carriers.coluna_surpresa')
    end

    it 'ABORTA numa tabela desconhecida' do
      report = introspect('tabela_surpresa' => [{ 'id' => 1 }])
      expect(report).to be_aborted
      expect(report.render).to include('tabela_surpresa')
    end

    it 'NÃO aborta nas duas divergências conhecidas (D-06 e D-108)' do
      report = introspect(
        'availability_templates' => [{ 'id' => 1, 'default_position' => 3 }],
        'contracts' => [{ 'id' => 1, 'description' => 'termos' }]
      )
      expect(report).not_to be_aborted
    end

    it 'mas a TERCEIRA surpresa aborta' do
      report = introspect(
        'availability_templates' => [{ 'id' => 1, 'default_position' => 3 }],
        'contracts' => [{ 'id' => 1, 'description' => 'termos', 'terceira_surpresa' => 1 }]
      )
      expect(report).to be_aborted
      expect(report.render).to include('contracts.terceira_surpresa')
    end
  end

  # ==========================================================================
  describe 'Sfg::Etl::Decisions — o portão de 5.4' do
    let(:decisions) do
      Sfg::Etl::Decisions.new([
                                Sfg::Etl::Decisions::Entry.new(key: 'timestamps:*', decision: 'DEC-06',
                                                               effect: 'converte e lista', signed_by: 'x', at: '2026-08-26')
                              ])
    end

    it 'reconhece a família autorizada por curinga' do
      expect(decisions).to be_registered('timestamps:carriers.created_at')
    end

    it 'não reconhece o que não está declarado' do
      expect(decisions).not_to be_registered('orphans:carriers.user_id')
    end

    it 'o arquivo versionado NÃO autoriza órfão, duplicata nem papel desconhecido' do
      real = Sfg::Etl::Decisions.load
      expect(real).not_to be_registered('orphans:receivable_entries.company_id')
      expect(real).not_to be_registered('duplicates:companies[project_id+title]')
      expect(real).not_to be_registered('roles:unknown')
      expect(real).not_to be_registered('users:username_without_channel')
    end
  end

  # ==========================================================================
  describe 'Sfg::Etl::Run — dry-run detecta órfão e duplicata e ABORTA' do
    let(:converter) do
      Class.new(Sfg::Etl::Converters::Base) do
        def self.name = 'Sfg::Etl::Converters::SpecCompanies'
        def self.converter_name = 'spec_companies'
        def self.source_table = 'companies'
        def self.target_model = 'Company'
        def self.references = { 'project_id' => 'projects' }
        def self.uniques = [%w[project_id title]]
        def convert(row) = { title: row['title'] }
      end
    end

    def dry_run(tables)
      klass = converter
      allow(Sfg::Etl::Pipeline).to receive(:converters).and_return([klass])
      report = Sfg::Etl::Report.new('spec', io: StringIO.new)
      run = Sfg::Etl::Run.new(source: synthetic_source.new(tables), mode: :dry_run, report: report,
                              io: StringIO.new, decisions: Sfg::Etl::Decisions.new([]))
      run.execute!
      report
    end

    it 'conta órfão contra a ORIGEM (e não contra o de-para, que está vazio antes da carga)' do
      report = dry_run(
        'projects' => [{ 'id' => 1 }],
        'companies' => [{ 'id' => 1, 'project_id' => 1, 'title' => 'A' },
                        { 'id' => 2, 'project_id' => 77, 'title' => 'B' }]
      )
      expect(report).to be_aborted
      expect(report.render).to include('aponta para `projects`#77')
      expect(report.render).not_to include('aponta para `projects`#1')
    end

    it 'conta duplicata da unicidade composta que o legado só validava em aplicação' do
      report = dry_run(
        'projects' => [{ 'id' => 1 }],
        'companies' => [{ 'id' => 1, 'project_id' => 1, 'title' => 'A' },
                        { 'id' => 2, 'project_id' => 1, 'title' => 'A' }]
      )
      expect(report).to be_aborted
      expect(report.render).to include('aparece 2×')
      expect(report.render).to include('índice único fica BLOQUEADO')
    end

    it 'NÃO escreve nada no destino' do
      expect do
        dry_run('projects' => [{ 'id' => 1 }], 'companies' => [{ 'id' => 1, 'project_id' => 1, 'title' => 'A' }])
      end
        .not_to change(Company, :count)
    end
  end

  # ==========================================================================
  describe 'Sfg::Etl::Pipeline — a lacuna declarada aparece no relatório' do
    it 'converter ainda não escrito vira um "pulado" nomeando a tabela e a fatia dona' do
      missing = Sfg::Etl::Pipeline.resolve('NaoExisteAinda',
                                           { 'source_table' => 'risk_entries',
                                             'target_model' => 'RiskEntry',
                                             'owner_slice' => 'S7' })
      expect(missing.missing_models).to eq(['RiskEntry'])
      expect(missing.skip_message).to include('S7')
      expect(missing.source_table).to eq('risk_entries')
    end

    it 'todo conversor do load_order.yml declara tabela de origem e model de destino' do
      Sfg::Etl::Pipeline.converters.each do |c|
        expect(c.source_table).to be_present, "#{c.converter_name} sem source_table"
        expect(c.target_model).to be_present, "#{c.converter_name} sem target_model"
      end
    end

    it 'nenhuma tabela descartada por decisão aparece na ordem de carga' do
      order_tables = Sfg::Etl::Pipeline.converters.map(&:source_table)
      dropped = YAML.safe_load_file(Sfg::Etl::Pipeline.file)['do_not_migrate'].map { |d| d['table'] }
      # DEC-92 em especial: geolocalização é descartada e NÃO tem conversor.
      expect(dropped).to include('geolocations')
      expect(order_tables & dropped).to be_empty
    end
  end

  # ==========================================================================
  describe 'portão de schema do destino (OPS-549 / tarefa 1.2)' do
    # Vem ANTES do portão: migration que o gravador não reexecuta some com as
    # tabelas dela, e aí o portão acusa "tabela sem migration" que tem migration.
    # O `rescue StandardError; next` escondia isso.
    it 'toda migration do ai9 é reexecutável pelo gravador' do
      expect(Sfg::Etl::TargetBaseline.replay_failures).to eq([])
    end

    it 'nenhuma tabela do schema.rb sem migration, fora a allowlist explícita' do
      expect(Sfg::Etl::TargetBaseline.undeclared_tables).to eq([])
    end

    it 'uma tabela órfã NOVA faz o portão falhar (as antigas ficam visíveis, não invisíveis)' do
      allow(Sfg::Etl::TargetBaseline).to receive(:schema_tables)
        .and_return(Sfg::Etl::TargetBaseline.migration_tables + %w[tabela_orfa_nova achievements])
      expect(Sfg::Etl::TargetBaseline.undeclared_tables).to eq(['tabela_orfa_nova'])
      expect(Sfg::Etl::TargetBaseline.known_orphans_present).to include('achievements')
    end
  end

  # ==========================================================================
  describe 'baseline do legado — replay das migrations' do
    it 'está versionado e cobre as tabelas que os conversores leem' do
      baseline = Sfg::Etl::LegacySchema.load_baseline
      tables = baseline.fetch('tables')
      %w[livetat_auth_users livetat_auth_roles livetat_auth_role_types
         carriers segments projects companies memberships
         receivable_entries risk_operations risk_movements].each do |table|
        expect(tables).to have_key(table), "baseline sem `#{table}` — rode `rake sfg_etl:baseline`"
      end
    end

    it 'derivou as 4 colunas Paperclip de cada anexo (o que uma regex perderia)' do
      columns = Sfg::Etl::LegacySchema.load_baseline.dig('tables', 'carriers', 'columns').map { |c| c['name'] }
      expect(columns).to include('logo_file_name', 'logo_content_type', 'logo_file_size', 'logo_updated_at')
    end
  end
end
