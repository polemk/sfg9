# frozen_string_literal: true

require 'rails_helper'
require 'open3'

# S14 — o que o DUMP DE PRODUÇÃO ensinou, virado em teste.
#
# Cada bloco aqui é um defeito que só apareceu quando o motor rodou contra
# `sfg-31-may-25.sql` (133,4 MB, `pg_dump` 13.4, 56 tabelas, 782.742 linhas) e
# contra `sfg-31-may-25.tar` (42,3 MB, 467 arquivos). Sem estes testes o motor
# volta a passar verde lendo zero linha.
RSpec.describe 'ETL contra o dump de produção' do
  # `pg_dump` com `COPY` — que é o PADRÃO da ferramenta e o formato do dump real.
  # O parser antigo só entendia `INSERT`, e contra este texto devolvia **zero
  # linha em toda tabela**, sem erro nenhum.
  let(:copy_dump) do
    <<~SQL
      --
      -- PostgreSQL database dump
      --

      SET statement_timeout = 0;

      CREATE TABLE public.livetat_auth_users (
          id integer NOT NULL,
          email character varying DEFAULT ''::character varying NOT NULL,
          username character varying,
          is_active integer DEFAULT 1,
          deactivated boolean DEFAULT false,
          created_at timestamp without time zone
      );

      ALTER TABLE public.livetat_auth_users OWNER TO sfg_user;

      COPY public.livetat_auth_users (id, email, username, is_active, deactivated, created_at) FROM stdin;
      3\tterceiro@example.invalid\t\\N\t1\tf\t2022-03-01 10:00:00
      1\tprimeiro@example.invalid\tmestre\t1\tt\t2022-02-27 23:18:49
      2\tsegundo@example.invalid\tSilva,\tJoao\t0\tf\t2022-02-28 08:00:00
      \\.

      CREATE INDEX index_users_on_email ON public.livetat_auth_users USING btree (email);

      ALTER TABLE ONLY public.livetat_auth_users
          ADD CONSTRAINT livetat_auth_users_pkey PRIMARY KEY (id);
    SQL
  end

  # A terceira linha acima tem um TAB a mais de propósito: no formato `COPY` o
  # separador é TAB e uma vírgula dentro do valor **não** desloca coluna. A linha
  # correta tem 6 campos; escrevê-la com 7 é o erro que o teste não pode aceitar.
  let(:corrected_dump) { copy_dump.sub("Silva,\tJoao\t0", "Silva, Joao\t0") }

  def dump_file(text)
    file = Tempfile.new(['dump', '.sql'])
    file.write(text)
    file.flush
    file
  end

  describe Sfg::Etl::Source::SqlDump do
    subject(:source) { described_class.new(file.path) }

    let(:file) { dump_file(corrected_dump) }

    after { file.close! }

    it 'reconhece o formato COPY e conta as linhas (o parser de INSERT contava zero)' do
      expect(source.format_name).to eq('copy')
      expect(source.count('livetat_auth_users')).to eq(3)
    end

    it 'lê o esquema e os índices, inclusive o da chave primária declarada por ALTER TABLE' do
      expect(source.column_names('livetat_auth_users'))
        .to eq(%w[id email username is_active deactivated created_at])
      nomes = source.indexes('livetat_auth_users').map { |i| i[:name] }
      expect(nomes).to include('index_users_on_email', 'livetat_auth_users_pkey')
      expect(source.indexes('livetat_auth_users').find { |i| i[:name] == 'livetat_auth_users_pkey' }[:unique]).to be true
    end

    it 'ordena por PK mesmo quando o bloco COPY vem fora de ordem' do
      # Medido no dump real: 24 das 56 tabelas saem fora de ordem de PK, porque o
      # `COPY` sai na ordem física do heap. Sem ordenar, a retomada não é estável.
      expect(source.ordered_rows('livetat_auth_users').map { |r| r['id'] }).to eq(%w[1 2 3])
    end

    it 'traduz `\\N` para nil e mantém string vazia como string vazia' do
      linhas = source.ordered_rows('livetat_auth_users').to_a
      expect(linhas[2]['username']).to be_nil
      expect(linhas[0]['username']).to eq('mestre')
    end

    it 'converte só a coluna DECLARADA boolean, e deixa o `integer` 0/1 como está (regra D-E)' do
      # No dump de produção existe **um único** `boolean`
      # (`livetat_auth_users.deactivated`). Ler `t`/`f` como texto faria o conversor
      # de booleano contar anomalia onde não há.
      linhas = source.ordered_rows('livetat_auth_users').to_a
      expect(linhas[0]['deactivated']).to be true
      expect(linhas[1]['deactivated']).to be false
      expect(linhas[0]['is_active']).to eq('1')
    end

    it 'não deixa vírgula dentro do valor deslocar coluna' do
      linha = source.ordered_rows('livetat_auth_users').to_a[1]
      expect(linha['username']).to eq('Silva, Joao')
      expect(linha['is_active']).to eq('0')
    end

    it 'responde `pks` sem montar linha nenhuma' do
      expect(source.pks('livetat_auth_users')).to eq(Set[1, 2, 3])
    end

    it 'entrega lotes ordenados e respeita o `after_pk` da retomada' do
      lotes = []
      source.each_batch('livetat_auth_users', batch_size: 2, after_pk: 1) { |b| lotes << b.map { |r| r['id'] } }
      expect(lotes).to eq([%w[2 3]])
    end

    it 'continua lendo dump em formato INSERT — é o do sistema Django anterior' do
      insert = dump_file(<<~SQL)
        CREATE TABLE public.segments (
            id integer NOT NULL,
            title character varying
        );
        INSERT INTO public.segments (id, title) VALUES (2, 'Silva, Joao');
        INSERT INTO public.segments (id, title) VALUES (1, 'Outro');
      SQL
      src = described_class.new(insert.path)
      expect(src.format_name).to eq('insert')
      expect(src.ordered_rows('segments').map { |r| r['title'] }).to eq(['Outro', 'Silva, Joao'])
      insert.close!
    end
  end

  describe Sfg::Etl::LegacySchema do
    # Três migrations do legado usam a forma antiga `def self.up` (Rails 4.2) e
    # duas usam `change_table`. O gravador não tinha `change_table`, e como
    # `Migration#method_missing` embrulha tudo em `say_with_time` — estubado para
    # `nil` — a chamada **sumia sem erro**. O baseline saía sem as 4 colunas
    # Paperclip de avatar e sem as 3 de progresso de job, e a introspecção contra
    # o dump real acusava 7 "surpresas" que não existiam.
    def replay(text)
      file = Tempfile.new(['migration', '.rb'])
      file.write(text)
      file.flush
      recorder = described_class::Recorder.new
      described_class.replay(Pathname.new(file.path), recorder)
      file.close!
      recorder.to_h
    end

    it 'reexecuta migration escrita com `def self.up`' do
      schema = replay(<<~RUBY)
        class AddCompanyColumnToAvailabilityEntries < ActiveRecord::Migration[6.1]
          def self.up
            add_column :availability_entries, :company_id, :integer
          end
        end
      RUBY
      expect(schema.dig('availability_entries', 'columns').map { |c| c['name'] }).to eq(['company_id'])
    end

    it 'grava as 4 colunas Paperclip de um `change_table` com `t.attachment`' do
      schema = replay(<<~RUBY)
        class AddAttachmentAvatarToUsers < ActiveRecord::Migration[4.2]
          def self.up
            change_table :livetat_auth_users do |t|
              t.attachment :avatar
            end
          end
        end
      RUBY
      expect(schema.dig('livetat_auth_users', 'columns').map { |c| c['name'] })
        .to contain_exactly('avatar_file_name', 'avatar_content_type', 'avatar_file_size', 'avatar_updated_at')
    end

    it 'resolve `column_exists?` contra o gravador, nunca contra um banco' do
      schema = replay(<<~RUBY)
        class AddProgressToDelayedJobs < ActiveRecord::Migration[4.2]
          def change
            change_table :delayed_jobs do |t|
              t.string :progress_stage unless column_exists? :delayed_jobs, :progress_stage
              t.integer :progress_current unless column_exists? :delayed_jobs, :progress_current
            end
          end
        end
      RUBY
      expect(schema.dig('delayed_jobs', 'columns').map { |c| c['name'] })
        .to eq(%w[progress_stage progress_current])
    end

    it '`t.foreign_key` NÃO vira coluna' do
      schema = replay(<<~RUBY)
        class CreateActiveStorageTables < ActiveRecord::Migration[6.0]
          def change
            create_table :active_storage_attachments do |t|
              t.string :name, null: false
              t.foreign_key :active_storage_blobs, column: :blob_id
            end
          end
        end
      RUBY
      expect(schema.dig('active_storage_attachments', 'columns').map { |c| c['name'] }).to eq(%w[id name])
    end

    it 'DSL desconhecida LEVANTA, em vez de sumir calada' do
      expect { replay(<<~RUBY) }.to raise_error(described_class::UnknownDsl, /dsl_que_nao_existe/)
        class Estranha < ActiveRecord::Migration[6.1]
          def change
            dsl_que_nao_existe :alguma_coisa
          end
        end
      RUBY
    end
  end

  describe Sfg::Etl::Scan do
    # 11 dos 13 conversores devolvem STRING em `anomalies`; 2 devolvem Hash. O
    # `publish!` só sabia ler Hash e estourava `TypeError` na primeira anomalia
    # real do dump. A fixture nunca alcançou o caminho porque as duas únicas
    # anomalias que ela dispara vêm justamente dos dois conversores que usam Hash.
    it 'aceita anomalia em String e em Hash na mesma execução' do
      run = instance_double(Sfg::Etl::Run)
      klass = Class.new(Sfg::Etl::Converters::Base) do
        def self.source_table = 'segments'
        def self.target_model = 'Segment'
        def self.converter_name = 'segments'
      end
      converter = klass.allocate
      allow(converter).to receive_messages(class: klass,
                                           anomalies: ['- linha em texto puro',
                                                       { key: 'k', title: 'T', line: '- linha em hash' }])

      scan = described_class.new(run, converter)
      scan.instance_variable_set(:@custom, converter.anomalies(nil))
      recebidas = []
      allow(run).to receive(:record_anomaly_group) { |**kw| recebidas << kw }
      scan.send(:publish!)

      expect(recebidas.map { |r| r[:key] }).to contain_exactly('custom:segments', 'k')
    end
  end

  describe Sfg::Etl::Converters::Users do
    # Medido no dump de produção: `is_active = 0` são 13 usuários e
    # `deactivated = true` são 85, sendo os 13 um SUBCONJUNTO dos 85. Bloquear só
    # por `is_active` deixaria **72 contas hoje impedidas de entrar no legado**
    # entrarem no ai9. `deactivated` é o único boolean do schema e o único que o
    # legado lê no login (`sessions_decorator.rb:12`).
    it 'bloqueia por `deactivated`, e não só por `is_active`' do
      ativo = { 'is_active' => '1', 'deactivated' => false }
      desligado_pelo_produto = { 'is_active' => '1', 'deactivated' => true }
      inativo_e_desligado = { 'is_active' => '0', 'deactivated' => true }

      expect(described_class.blocked?(ativo)).to be false
      expect(described_class.blocked?(desligado_pelo_produto)).to be true
      expect(described_class.blocked?(inativo_e_desligado)).to be true
    end

    it 'o motivo do bloqueio nomeia QUAL coluna desligou a conta' do
      converter = described_class.allocate
      motivo = converter.blocked_reason_for({ 'is_active' => '1', 'deactivated' => true })
      expect(motivo).to include('deactivated = true')
      expect(motivo).not_to include('is_active = 0')
    end
  end

  # ------------------------------------------------------------------ acervo
  describe Sfg::Etl::Attachments do
    # Um `.tar` sintético com a MESMA forma do acervo real
    # (`public/system/<attachment>/<id>/<basename>.<ext>`).
    let(:pdf_bytes) { "%PDF-1.7\n#{'conteudo binario ' * 64}\n%%EOF\n".b }
    let(:tar_path) do
      dir = Dir.mktmpdir('sfg-acervo')
      alvo = File.join(dir, 'public', 'system', 'files', '9')
      FileUtils.mkdir_p(alvo)
      File.binwrite(File.join(alvo, 'Simulação.pdf'), pdf_bytes)
      tar = File.join(dir, 'acervo.tar')
      _out, err, status = Open3.capture3('tar', '-cf', tar, '-C', dir, 'public')
      raise err unless status.success?

      tar
    end

    let(:archive) { Sfg::Etl::Attachments::Archive.open(tar: tar_path) }

    it 'aceita o acervo já extraído em disco, com os mesmos caminhos do tar' do
      dir = Dir.mktmpdir('sfg-extraido')
      alvo = File.join(dir, 'public', 'system', 'files', '9')
      FileUtils.mkdir_p(alvo)
      File.binwrite(File.join(alvo, 'Simulação.pdf'), pdf_bytes)

      acervo = Sfg::Etl::Attachments::Archive.open(root: File.join(dir, 'public', 'system'))
      expect(acervo.entries).to eq('public/system/files/9/Simulação.pdf' => pdf_bytes.bytesize)
      expect(acervo.read('public/system/files/9/Simulação.pdf')).to eq(pdf_bytes)
    end

    it 'indexa o tar e lê UM arquivo sem extrair nada' do
      expect(archive.entries).to include('public/system/files/9/Simulação.pdf' => pdf_bytes.bytesize)
      expect(archive.read('public/system/files/9/Simulação.pdf')).to eq(pdf_bytes)
      expect(Dir.exist?(File.join(File.dirname(tar_path), 'extraido'))).to be false
    end

    # ⚠ A PROVA DA TAREFA 6.7. Lê o binário do acervo, **reanexa por
    # ActiveStorage** e confere que o que volta tem o mesmo tamanho E a mesma
    # assinatura. Tamanho igual com conteúdo diferente é o modo de falha que uma
    # conferência de tamanho sozinha não pega.
    it 'religa o anexo e o binário volta com o mesmo tamanho e a mesma assinatura' do
      anexo = create(:renegotiation_attachment)
      Sfg::Etl::IdMap.record!(source_table: 'renegotiation_attachments', legacy_pk: 9,
                              target_table: 'renegotiation_attachments', ai9_id: anexo.id, run_id: 'spec')

      source = instance_double(Sfg::Etl::Source::Base)
      allow(source).to receive_messages(
        describe: 'fonte de teste',
        table?: true,
        column_names: %w[id file_file_name file_content_type file_file_size],
        each_row: [{ 'id' => '9', 'file_file_name' => 'Simulação.pdf',
                     'file_content_type' => 'application/pdf',
                     'file_file_size' => pdf_bytes.bytesize.to_s }].each
      )

      migrador = described_class.new(source: source, system_tar: tar_path)
      prova = migrador.relink_one!('renegotiation_attachments', 'file', 9)

      expect(prova[:bytes]).to eq(pdf_bytes.bytesize)
      expect(prova[:sha256]).to eq(Digest::SHA256.hexdigest(pdf_bytes))
      expect(anexo.reload.file).to be_attached
      expect(anexo.file.download).to eq(pdf_bytes)
    end

    # ⚠ A MESMA PROVA, CONTRA O ACERVO E O DUMP DE PRODUÇÃO DE VERDADE.
    #
    # Só roda quando os dois arquivos são apontados por variável de ambiente —
    # eles não estão (e não podem estar) no repositório. Rodada em 26/08/2026:
    #
    #   SFG_DUMP=…/sfg-31-may-25.sql SFG_SYSTEM_TAR=…/sfg-31-may-25.tar \
    #     bundle exec rspec spec/lib/sfg/etl/production_dump_spec.rb -e 'acervo de produção'
    #
    # Resultado medido: `renegotiation_attachments#9` `Simulação.pdf`, 983.078 B,
    # sha256 `126956878458bcf03c75af3bce7c15cb6cd8671a183b61de2e375515a2b70ee2`,
    # idêntico ao de `tar -xOf … | sha256sum`.
    it 'religa um PDF real do acervo de produção com tamanho e assinatura idênticos', :acervo_real do
      dump = ENV.fetch('SFG_DUMP', nil)
      tar = ENV.fetch('SFG_SYSTEM_TAR', nil)
      skip 'defina SFG_DUMP e SFG_SYSTEM_TAR para rodar contra os artefatos de produção' if dump.nil? || tar.nil?

      source = Sfg::Etl::Source::SqlDump.new(dump)
      anexo = create(:renegotiation_attachment)
      Sfg::Etl::IdMap.record!(source_table: 'renegotiation_attachments', legacy_pk: 9,
                              target_table: 'renegotiation_attachments', ai9_id: anexo.id, run_id: 'spec')

      esperado, _err, _st = Open3.capture3('tar', '-xOf', tar, '--', 'public/system/files/9/Simulação.pdf',
                                           binmode: true)
      prova = described_class.new(source: source, system_tar: tar)
                             .relink_one!('renegotiation_attachments', 'file', 9)

      expect(prova[:bytes]).to eq(983_078)
      expect(prova[:bytes]).to eq(esperado.bytesize)
      expect(prova[:sha256]).to eq(Digest::SHA256.hexdigest(esperado))
      expect(prova[:sha256]).to eq('126956878458bcf03c75af3bce7c15cb6cd8671a183b61de2e375515a2b70ee2')
      expect(anexo.reload.file.download[0, 8]).to eq('%PDF-1.7')
    end

    # ⚠ **A TAREFA 5.3 INTEIRA, CONTRA O ACERVO DE PRODUÇÃO.**
    #
    # Não um arquivo: os **44** anexos de renegociação do dump, copiados do `.tar`
    # e reanexados por ActiveStorage, com o tipo revalidado pelos magic bytes e
    # com tamanho e SHA-256 conferidos depois de anexar.
    #
    # Rodada em 26/08/2026:
    #
    #   SFG_DUMP=…/sfg-31-may-25.sql SFG_SYSTEM_TAR=…/sfg-31-may-25.tar \
    #     bundle exec rspec spec/lib/sfg/etl/production_dump_spec.rb -e 'os 44 anexos'
    #
    # Medido: **43 de 44 religados** · 39.424.330 bytes lidos · 0 sem arquivo no
    # acervo · 0 fora da allowlist.
    #
    # O 44º é o achado que só apareceu executando: `renegotiation_attachments#45`
    # `ANEXO_INSTRUMENTO_DE_GARANTIA.pdf` tem **0 byte no acervo E 0 no banco**, e
    # o próprio Paperclip gravou `inode/x-empty` na coluna de tipo em 2022. Ele
    # **não** é reanexado: um arquivo vazio carimbado pela extensão viraria um
    # download de 0 byte com cara de PDF válido, que é o modo de falha que a
    # DEC-84 chama de "pior que ausência declarada". Fica reportado e nomeado.
    it 'religa os 44 anexos de renegociação do acervo de produção, com tipo pelo conteúdo', :acervo_real do
      dump = ENV.fetch('SFG_DUMP', nil)
      tar = ENV.fetch('SFG_SYSTEM_TAR', nil)
      skip 'defina SFG_DUMP e SFG_SYSTEM_TAR para rodar contra os artefatos de produção' if dump.nil? || tar.nil?

      source = Sfg::Etl::Source::SqlDump.new(dump)
      linhas = source.each_row('renegotiation_attachments').to_a
      expect(linhas.size).to eq(44)

      # Os registros de destino. Um por linha do legado, **sem binário** — é
      # exatamente o estado em que a carga (`ETL_LOAD_RENEGOTIATION_ATTACHMENT_ROWS`)
      # os deixa, e é o estado que a DEC-84 chama de "pior que ausência declarada"
      # enquanto o binário não chegar.
      renegociacao = create(:renegotiation)
      linhas.each do |linha|
        destino = RenegotiationAttachment.create!(
          renegotiation: renegociacao, project: renegociacao.project,
          author: create(:user), title: linha['title'].presence || 'Anexo'
        )
        Sfg::Etl::IdMap.record!(source_table: 'renegotiation_attachments', legacy_pk: linha['id'],
                                target_table: 'renegotiation_attachments', ai9_id: destino.id,
                                run_id: 'spec-5.3')
      end

      relatorio = described_class.new(source: source, system_tar: tar,
                                      report: Sfg::Etl::Report.new('spec-relink', io: StringIO.new))
                                 .migrate!(dry_run: false)

      secao = relatorio.sections.find { |s| s.title.include?('Religação de `renegotiation_attachments.file`') }
      expect(secao.title).to include('43 ok', '0 SEM ARQUIVO no acervo', '1 com 0 byte', '0 com erro')
      # Documento financeiro sem binário deixa o relatório VERMELHO. O passo do
      # runbook não fecha por conta própria; alguém assina.
      expect(secao.severity).to eq(:abort)
      expect(secao.lines.join).to include('ANEXO_INSTRUMENTO_DE_GARANTIA.pdf', '0 byte')

      # Cada registro tem binário, e o binário é o do acervo — conferido por
      # tamanho E por assinatura, um a um.
      anexos = RenegotiationAttachment.where(renegotiation: renegociacao).includes(file_attachment: :blob)
      expect(anexos.count).to eq(44)
      expect(anexos.count { |a| a.file.attached? }).to eq(43)
      expect(anexos.sum { |a| a.file.attached? ? a.file.blob.byte_size : 0 }).to eq(39_424_330)

      esperado, _err, _st = Open3.capture3('tar', '-xOf', tar, '--',
                                           'public/system/files/9/Simulação.pdf', binmode: true)
      nove = Sfg::Etl::IdMap.resolve('renegotiation_attachments', 9)
      expect(RenegotiationAttachment.find(nove).file.download).to eq(esperado)

      # **Rodar duas vezes não duplica.** É a regra de idempotência do ETL, e aqui
      # ela vale para o blob: a segunda passada encontra o anexo já preso e não
      # cria um segundo.
      blobs = ActiveStorage::Blob.count
      described_class.new(source: source, system_tar: tar,
                          report: Sfg::Etl::Report.new('spec-relink-2', io: StringIO.new))
                     .migrate!(dry_run: false)
      expect(ActiveStorage::Blob.count).to eq(blobs)
    end

    it 'casa por BASENAME, porque usuário e projeto de mesmo id dividem `avatars/:id/`' do
      dir = Dir.mktmpdir('sfg-avatares')
      alvo = File.join(dir, 'public', 'system', 'avatars', '62')
      FileUtils.mkdir_p(alvo)
      File.binwrite(File.join(alvo, 'missing_original.jpg'), 'avatar-do-usuario')
      File.binwrite(File.join(alvo, '1610222783781_original.jpg'), 'avatar-do-projeto')
      tar = File.join(dir, 'a.tar')
      Open3.capture3('tar', '-cf', tar, '-C', dir, 'public')

      migrador = described_class.new(source: instance_double(Sfg::Etl::Source::Base), system_tar: tar)
      caminho_usuario = migrador.send(:locate, described_class::MAP.dig('livetat_auth_users', 'avatar'),
                                      '62', 'missing.jpg')
      caminho_projeto = migrador.send(:locate, described_class::MAP.dig('projects', 'avatar'),
                                      '62', '1610222783781.jpg')

      expect(caminho_usuario).to end_with('avatars/62/missing_original.jpg')
      expect(caminho_projeto).to end_with('avatars/62/1610222783781_original.jpg')
    end
  end
end
