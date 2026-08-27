# frozen_string_literal: true

# ETL do legado Safegold — S14 (OPS-632).
#
# O esqueleto nasceu na S18, vazio e nomeado de propósito ("alvo que não existe no
# repositório não aparece em revisão"). Esta é a S14 preenchendo.
#
# Cada etapa é uma tarefa versionada e nomeada, e **todo relatório é arquivo**
# (`tmp/etl/`), não saída de terminal: o portão de cutover é relatório anexado e
# assinado.
#
#   rake sfg_etl:baseline    SFG_LEGACY_ROOT=../sfg   # esquema esperado das 139 migrations
#   rake sfg_etl:introspect  SOURCE=dump DUMP=…       # esquema real + volumetria + comparação
#   rake sfg_etl:dry_run     SOURCE=fixture           # anomalias. NÃO escreve nada
#   rake sfg_etl:load        SOURCE=fixture           # carga em lotes, retomável, idempotente
#   rake sfg_etl:status                               # onde cada tabela parou
#   rake sfg_etl:reconcile   SOURCE=fixture           # contagem, amostra, somatório, fuso
#   rake sfg_etl:attachments SYSTEM_TAR=…             # reconcilia binários (DEC-84)
#   rake sfg_etl:relink_attachments SYSTEM_TAR=… RELINK=1  # copia e reanexa (6.7)
#   rake sfg_etl:renegotiation_parity SOURCE=dump DUMP=…   # paridade numérica S9 (5.7)
#   rake sfg_etl:renegotiation_fixups DRY_RUN=0        # empresa padrão + recálculo + renumeração (5.5)
#   rake sfg_etl:schema_gate                          # portão OPS-549 do destino
#   rake sfg_etl:ledger_gate                          # portão do razão (10.7)
#   rake sfg_etl:rehearsal                            # o ensaio completo, em uma linha
#
# **Parâmetros (todos com padrão, nada obrigatório):**
#   SOURCE=fixture|dump|db   origem. `fixture` é a versionada; `db` é a do cutover
#   DUMP=<caminho>           arquivo pg_dump quando SOURCE=dump
#   SFG_LEGACY_URL=<url>     banco vivo do legado quando SOURCE=db  (DEPENDÊNCIA EXTERNA)
#   DECISIONS=<caminho|none> arquivo de decisões. `none` = nada autorizado (prova o portão)
#   BATCH=<n>                tamanho do lote (padrão 1000)
#   RUN_ID=<id>              execução, para retomada (padrão `default`)
#   ONLY=<conv,conv>         restringe a conversores
#   RESUME=0                 ignora o checkpoint e RELE a origem inteira (prova a idempotencia
#                            pelo de-para, e nao pelo checkpoint)
#   SYSTEM_ROOT=<caminho>    cópia de `public/system/` do legado, já extraída
#   SYSTEM_TAR=<caminho>     o `.tar` do acervo COMO VEIO — lido em fluxo, nada é extraído
#   RELINK=1                 `relink_attachments` grava de verdade (padrão: ensaio)
#   VERIFY_CONTENT=critical|all|none  conferência de TIPO pelos magic bytes (padrão: critical)
#   DRY_RUN=0                `renegotiation_fixups` grava de verdade (padrão: ensaio)
#   STEPS=<passo,passo>      restringe os fixups (company, recalculate, renumber, counters)
#   SAMPLE=<n>               `renegotiation_parity` compara só as N primeiras renegociações
namespace :sfg_etl do
  # ------------------------------------------------------------------ helpers
  def etl_source
    kind = ENV.fetch('SOURCE', 'fixture')
    case kind
    when 'fixture' then Sfg::Etl::Source::Fixture.new(ENV.fetch('FIXTURES', nil))
    when 'dump'
      path = ENV.fetch('DUMP') { abort 'Informe DUMP=<caminho do pg_dump>.' }
      Sfg::Etl::Source::SqlDump.new(path)
    when 'db'
      Sfg::Etl::Source::Connection.new(ENV.fetch('SFG_LEGACY_URL', nil))
    else
      abort "SOURCE desconhecida: #{kind}. Use fixture, dump ou db."
    end
  rescue Sfg::Etl::Source::Base::UnavailableSource => e
    abort "Origem indisponível: #{e.message}"
  end

  def etl_decisions
    path = ENV.fetch('DECISIONS', nil)
    return Sfg::Etl::Decisions.new([]) if path == 'none'

    Sfg::Etl::Decisions.load(path)
  end

  def etl_options
    { batch_size: ENV.fetch('BATCH', 1_000).to_i,
      run_id: ENV.fetch('RUN_ID', 'default'),
      only: ENV['ONLY']&.split(',')&.map(&:strip),
      resume: ENV.fetch('RESUME', '1') != '0' }
  end

  # **Sair com status de falha é parte do relatório.** Um `rake` que termina em 0
  # é lido como "deu certo" por gente e por CI, e a DEC-127 é explícita: ninguém
  # deve poder confundir "terminou" com "carregou tudo".
  #
  # São dois vereditos diferentes, e o texto os separa:
  #   * `aborted?`  — parou ANTES de escrever (anomalia sem decisão registrada);
  #   * `rejected?` — escreveu, mas alguma linha do cliente ficou de fora.
  def etl_finish(report)
    path = report.write!
    report.echo!(path)
    abort "ABORTADO. Ver #{path}" if report.aborted?
    abort "CARGA INCOMPLETA: houve linha recusada por validação. Ver #{path}" if report.rejected?
    path
  end

  # -------------------------------------------------------------------- alvos

  desc 'Gera o baseline do esquema ESPERADO da origem, das 139 migrations do legado'
  task baseline: :environment do
    root = ENV.fetch('SFG_LEGACY_ROOT', '../sfg')
    payload = Sfg::Etl::LegacySchema.build!(legacy_root: root)
    file = Sfg::Etl::LegacySchema.write_baseline!(payload)
    puts "Baseline gravado em #{file}"
    puts "  migrations lidas: #{payload['migrations_replayed']}/#{payload['migrations_total']}"
    puts "  tabelas derivadas: #{payload['tables'].size}"
    failures = payload['migrations_failed']
    next if failures.empty?

    puts "  #{failures.size} migration(s) NÃO reexecutáveis (registradas no baseline):"
    failures.first(10).each { |f| puts "    - #{f['file']}: #{f['error']}" }
  end

  desc 'Lê o esquema REAL da origem, mede volumetria e compara com o baseline (ABORTA em surpresa)'
  task introspect: :environment do
    report = Sfg::Etl::Introspection.new(etl_source).run!
    etl_finish(report)
  end

  desc 'Dry-run: conta órfãos, duplicatas e anomalias. NÃO escreve nada'
  task dry_run: :environment do
    run = Sfg::Etl::Run.new(source: etl_source, mode: :dry_run, decisions: etl_decisions, **etl_options)
    run.execute!
    etl_finish(run.report)
  end

  desc 'Carga: lotes, transação por lote, checkpoint dentro da transação, idempotente e retomável'
  task load: :environment do
    run = Sfg::Etl::Run.new(source: etl_source, mode: :load, decisions: etl_decisions, **etl_options)
    begin
      run.execute!
    rescue Sfg::Etl::Run::Blocked => e
      puts "BLOQUEADO: #{e.message}"
    end
    etl_finish(run.report)
  end

  desc 'Onde cada tabela parou (não escreve nada)'
  task status: :environment do
    run_id = ENV.fetch('RUN_ID', 'default')
    puts
    puts "Execução `#{run_id}`"
    puts '=' * 92
    checkpoints = Sfg::Etl::Checkpoint.where(run_id: run_id).order(:source_table)
    if checkpoints.empty?
      puts '  (nenhum checkpoint — esta execução ainda não carregou nada)'
    else
      # "recusadas" é DERIVADO, não uma coluna nova: linha lida que não foi
      # gravada nem pulada por já estar no de-para só pode ter sido recusada por
      # validação (DEC-127). Deriva-se de propósito — acrescentar coluna ao
      # `etl_checkpoints` exigiria migration, e migration é da outra fatia.
      puts format('  %-34<t>s %-9<s>s %10<p>s %10<w>s %10<k>s %10<r>s  %<pk>s',
                  t: 'tabela', s: 'estado', p: 'lidas', w: 'gravadas', k: 'já mapeadas',
                  r: 'recusadas', pk: 'última pk')
      checkpoints.each do |c|
        recusadas = c.processed_count - c.written_count - c.skipped_count
        puts format('  %-34<t>s %-9<s>s %10<p>d %10<w>d %10<k>d %10<r>s  %<pk>s',
                    t: c.source_table, s: c.state, p: c.processed_count,
                    w: c.written_count, k: c.skipped_count,
                    r: recusadas.positive? ? recusadas.to_s : '-', pk: c.last_legacy_pk || '-')
      end
    end
    puts
    puts 'De-para (`etl_id_map`):'
    Sfg::Etl::IdMap.group(:source_table).count.sort.each { |t, n| puts format('  %-34<t>s %6<n>d', t: t, n: n) }
    puts
    puts 'Conversores declarados em `db/etl/load_order.yml`:'
    Sfg::Etl::Pipeline.converters.each do |c|
      missing = c.missing_models
      puts format('  %<i>s %-30<n>s %-34<src>s %<m>s',
                  i: missing.empty? ? 'ok  ' : 'pula', n: c.converter_name, src: c.source_table,
                  m: missing.empty? ? '' : c.skip_message)
    end
    puts
  end

  desc 'Reconciliação: contagem, amostra determinística, somatórios, religamento e fuso'
  task reconcile: :environment do
    report = Sfg::Etl::Reconcile.new(source: etl_source, only: etl_options[:only], decisions: etl_decisions).run!
    etl_finish(report)
  end

  def etl_attachments(name)
    Sfg::Etl::Attachments.new(source: etl_source,
                              system_root: ENV.fetch('SYSTEM_ROOT', nil),
                              system_tar: ENV.fetch('SYSTEM_TAR', nil),
                              report: Sfg::Etl::Report.new(name))
  rescue Sfg::Etl::Attachments::Archive::Missing => e
    abort "Acervo indisponível: #{e.message}"
  end

  desc 'Reconcilia os binários dos 11 anexos contra o acervo (DEC-84). NÃO anexa nada'
  task attachments: :environment do
    escopo = ENV.fetch('VERIFY_CONTENT', 'critical').to_sym
    etl_finish(etl_attachments('attachments').scan!(verify_content: escopo))
  end

  desc 'Religa os binários por ActiveStorage (tarefa 6.7). RELINK=1 grava; sem ele é ensaio'
  task relink_attachments: :environment do
    dry = ENV.fetch('RELINK', '0') != '1'
    etl_finish(etl_attachments('relink_attachments').migrate!(dry_run: dry))
  end

  desc 'Paridade numérica da renegociação contra o dump de produção (tarefa 5.7). NÃO escreve nada'
  task renegotiation_parity: :environment do
    report = Sfg::Etl::Parity::Renegotiations.new(source: etl_source,
                                                  sample: ENV.fetch('SAMPLE', nil)).run!
    etl_finish(report)
  end

  desc 'Fixups pós-carga da renegociação (OPS-197). DRY_RUN=0 grava; sem ele é ensaio'
  task renegotiation_fixups: :environment do
    fixups = Sfg::Etl::Fixups::Renegotiations.new(
      dry_run: ENV.fetch('DRY_RUN', '1') != '0',
      batch_size: ENV.fetch('BATCH', 500).to_i,
      run_id: ENV.fetch('RUN_ID', 'default'),
      only: ENV['STEPS']&.split(',')&.map(&:strip),
      after: ENV.fetch('AFTER', nil)
    )
    etl_finish(fixups.run!)
  end

  desc 'Portão de schema do destino (OPS-549): tabela no schema.rb que nenhuma migration cria'
  task schema_gate: :environment do
    undeclared = Sfg::Etl::TargetBaseline.undeclared_tables
    orphans = Sfg::Etl::TargetBaseline.known_orphans_present
    failures = Sfg::Etl::TargetBaseline.replay_failures
    if failures.any?
      puts "PORTÃO VERMELHO: #{failures.size} migration(s) que o gravador não conseguiu reexecutar —"
      puts '  as tabelas delas somem da conferência e o portão passa a mentir:'
      failures.each { |f| puts "  - #{f}" }
      abort
    end
    puts "Órfãs herdadas ainda presentes (allowlist explícita, C-07/F-08): #{orphans.size}"
    orphans.each_slice(6) { |s| puts "  #{s.join(', ')}" }
    puts
    if undeclared.empty?
      puts 'PORTÃO VERDE: nenhuma tabela nova sem migration.'
    else
      puts "PORTÃO VERMELHO: #{undeclared.size} tabela(s) no schema.rb que nenhuma migration cria:"
      undeclared.each { |t| puts "  - #{t}" }
      abort
    end
  end

  desc 'Portão do RAZÃO (tarefa 10.7): to-remove, build? e item aberto sem dono'
  task ledger_gate: :environment do
    etl_finish(Sfg::Etl::LedgerGate.new(ENV.fetch('LEDGER', nil)).report!)
  end

  desc 'Apaga o que a carga da FIXTURE criou (só ela — pelo de-para, na ordem inversa)'
  task rehearsal_reset: :environment do
    # **`DELETE FROM` na ordem INVERSA das dependências. Nunca `TRUNCATE … CASCADE`**:
    # ele não para na tabela nomeada, segue as FKs, e foi assim que
    # `TRUNCATE projects CASCADE` levou `users` junto e apagou as contas de login.
    #
    # A linha do de-para só sai DEPOIS de o registro sair. Apagar o de-para primeiro
    # deixa órfão no destino e um ETL que acha que nunca carregou — foi exatamente o
    # estado em que um script ad-hoc deixou o banco de dev durante o ensaio.
    deleted = {}
    blocked = []
    Sfg::Etl::Pipeline.converters.reverse.each do |c|
      next if c.missing_models.any?

      ids = Sfg::Etl::IdMap.where(source_table: c.source_table).pluck(:ai9_id)
      next if ids.empty?

      begin
        deleted[c.target_model] = c.target_class.where(id: ids).delete_all
        Sfg::Etl::IdMap.where(source_table: c.source_table).delete_all
      rescue ActiveRecord::InvalidForeignKey => e
        # Registro do ensaio referenciado por algo de fora do ensaio (no banco de dev
        # isso acontece: outra fatia cria conexões). Reporta e SEGUE — apagar o
        # referenciador seria apagar dado que não é meu.
        blocked << "#{c.target_model}: #{e.message.lines.first.strip}"
      end
    end
    Sfg::Etl::Checkpoint.delete_all
    puts "Ensaio limpo: #{deleted.map { |k, v| "#{k} #{v}" }.join(', ')}"
    blocked.each { |b| puts "  BLOQUEADO por FK externa ao ensaio — #{b}" }
  end

  desc 'ENSAIO COMPLETO: introspecção + dry-run + carga + carga de novo + reconciliação'
  task rehearsal: :environment do
    %w[introspect dry_run load load reconcile].each_with_index do |target, i|
      puts
      puts "### passo #{i + 1}: sfg_etl:#{target}"
      Rake::Task["sfg_etl:#{target}"].reenable
      Rake::Task["sfg_etl:#{target}"].invoke
    end
  end
end

# Aliases do namespace declarado pela S18 em `OPS-632`. Ficam apontando para os
# alvos reais — **regra de fronteira**: nome declarado por outra fatia não some
# porque esta fatia preferiu outro nome.
namespace :sfg do
  namespace :etl do
    desc '(alias de sfg_etl:introspect + sfg_etl:dry_run)'
    task extract: %w[sfg_etl:introspect sfg_etl:dry_run]

    desc '(alias de sfg_etl:load)'
    task load: %w[sfg_etl:load]

    desc '(alias de sfg_etl:reconcile)'
    task verify: %w[sfg_etl:reconcile]

    desc 'extract + load + verify, na ordem'
    task all: %w[sfg:etl:extract sfg:etl:load sfg:etl:verify]
  end
end
