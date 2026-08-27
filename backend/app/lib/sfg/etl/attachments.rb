# frozen_string_literal: true

require 'open3'

module Sfg
  module Etl
    # MIGRAÇÃO DOS BINÁRIOS — DB-482 / tarefas 5.6 e 6.7.
    #
    # ==========================================================================
    # O ACERVO CHEGOU (26/08/2026). ESTE PASSO DEIXOU DE ESTAR BLOQUEADO.
    # ==========================================================================
    #
    # Os 11 anexos (44 colunas Paperclip) vivem em
    # `:rails_root/public/system/:attachment/:id/:basename_:style.:extension`
    # **no disco da máquina do legado** — o path está configurado inline em cada model
    # (`carrier.rb:17` e os outros dez). O usuário entregou o acervo como um `.tar` de
    # 42,3 MB com 467 arquivos sob `public/system/`, e a **DEC-84** deixa de ser
    # bloqueante para a conferência: falta só o cutover.
    #
    # **Por que isso importa e não é "resolve depois":** anexo de renegociação é
    # documento financeiro. Registro apontando para arquivo inexistente é **pior que
    # ausência declarada** — quem abre a renegociação vê um anexo listado e um download
    # que falha, e conclui que o sistema novo perdeu o documento.
    #
    # --------------------------------------------------------------------------
    # DUAS ORIGENS DE BINÁRIO, E O TAR NÃO É EXTRAÍDO
    # --------------------------------------------------------------------------
    #
    #   SYSTEM_ROOT=/caminho/para/public/system   diretório já extraído
    #   SYSTEM_TAR=/caminho/para/acervo.tar       o `.tar` como veio, LIDO EM FLUXO
    #
    # O `.tar` é indexado por `tar -tvf` (nomes e tamanhos) e cada arquivo é lido por
    # `tar -xOf`, um de cada vez, direto para a memória. **Nada é extraído para o
    # disco** — instrução explícita do usuário para esta rodada.
    #
    # --------------------------------------------------------------------------
    # O CAMINHO DE PAPERCLIP, MEDIDO CONTRA O ACERVO REAL
    # --------------------------------------------------------------------------
    #
    # `:attachment` é o **nome do anexo pluralizado**, e não inclui o model. Duas
    # consequências medidas no acervo de produção:
    #
    # * `User#avatar` e `Project#avatar` compartilham `public/system/avatars/:id/` —
    #   o usuário 62 e o projeto 62 gravam na MESMA pasta. Só não colidem porque o
    #   `:basename` difere. Casar por pasta é errado; casa-se por **basename**.
    # * `Carrier#logo` e `Provider#logo` compartilhariam `logos/:id/`. No acervo real
    #   **não existe pasta `logos/`** — e no banco os dois anexos têm 0 linhas.
    #
    # Anexo com `:styles` grava `<basename>_original.<ext do estilo>` (a extensão é a
    # do ESTILO, não a do original: `download.png` virou `download_original.jpg`).
    # `renegotiation_attachments.file` **não tem estilo** e grava `<basename>.<ext>`.
    class Attachments
      # `tabela legada => { anexo => metadados }`. As 4 colunas Paperclip por anexo
      # (`_file_name`, `_content_type`, `_file_size`, `_updated_at`) **não** são
      # recriadas no ai9: o ETL copia o arquivo e **reanexa** por ActiveStorage.
      #
      # `dir` é o `:attachment` do path (nome pluralizado) e `styled` diz se o arquivo
      # no disco leva o sufixo `_original`.
      MAP = {
        'livetat_auth_users' => {
          'avatar' => { model: 'User', attachment: :avatar, slice: 'S1', dir: 'avatars', styled: true }
        },
        'projects' => {
          'avatar' => { model: 'Project', attachment: :avatar, slice: 'S4', dir: 'avatars', styled: true }
        },
        'carriers' => {
          'logo' => { model: 'Carrier', attachment: :logo, slice: 'S4', dir: 'logos', styled: true }
        },
        'providers' => {
          'logo' => { model: 'Provider', attachment: :logo, slice: 'S4', dir: 'logos', styled: true }
        },
        'renegotiation_attachments' => {
          'file' => { model: 'RenegotiationAttachment', attachment: :file, slice: 'S9',
                      dir: 'files', styled: false, critical: 'documento financeiro (DEC-84)' }
        },
        'app_themes' => {
          'symbol_logo' => { model: nil, attachment: :symbol_logo, slice: 'S17 (DEC-55/56 — tema encolhido)',
                             dir: 'symbol_logos', styled: true },
          'full_logo' => { model: nil, attachment: :full_logo, slice: 'S17', dir: 'full_logos', styled: true },
          'text_logo' => { model: nil, attachment: :text_logo, slice: 'S17', dir: 'text_logos', styled: true },
          'login_bkg_image' => { model: nil, attachment: :login_bkg_image, slice: 'S17',
                                 dir: 'login_bkg_images', styled: true }
        },
        # `pictures` NÃO migra (DB-593): nenhum model declara `has_many :pictures`.
        # Continua aqui porque o ETL **conta as linhas** antes de o descarte fechar.
        'pictures' => { 'image' => { model: nil, attachment: :image, slice: 'descartado — DB-593',
                                     dir: 'images', styled: true } }
      }.freeze

      # ------------------------------------------------------------------------
      # O ACERVO. Duas implementações, e a escolha é por parâmetro.
      # ------------------------------------------------------------------------
      class Archive
        Missing = Class.new(StandardError)

        def self.open(root: nil, tar: nil)
          return TarArchive.new(tar) if tar.present?
          return DirectoryArchive.new(root) if root.present?

          nil
        end

        # `{ 'public/system/files/9/Simulação.pdf' => 983_078 }`
        def entries = raise(NotImplementedError)
        def describe = raise(NotImplementedError)
        def read(_path) = raise(NotImplementedError)

        def size(path) = entries[path]
        def exist?(path) = entries.key?(path)

        # Arquivos dentro de `public/system/<dir>/<id>/`.
        def siblings(dir, legacy_id)
          prefix = "public/system/#{dir}/#{legacy_id}/"
          @sibling_cache ||= entries.keys.group_by { |p| p[%r{\A(public/system/[^/]+/[^/]+/)}, 1] }
          @sibling_cache.fetch(prefix, [])
        end
      end

      # `public/system/` já extraído em disco.
      class DirectoryArchive < Archive
        def initialize(root)
          super()
          @root = Pathname.new(root.to_s)
          raise Missing, "diretório de acervo inexistente: #{@root}" unless @root.directory?
        end

        def describe = "diretório #{@root} (#{entries.size} arquivo(s))"

        def entries
          @entries ||= Dir.glob(@root.join('**/*')).each_with_object({}) do |path, acc|
            next unless File.file?(path)

            rel = Pathname.new(path).relative_path_from(@root.parent.parent).to_s
            rel = "public/system/#{Pathname.new(path).relative_path_from(@root)}" unless rel.start_with?('public/')
            acc[rel] = File.size(path)
          end
        end

        def read(path)
          File.binread(@root.join(path.sub(%r{\Apublic/system/}, '')))
        end
      end

      # O `.tar` **como veio**. Indexado por `tar -tvf`, lido por `tar -xOf`.
      # Nada vai para o disco.
      class TarArchive < Archive
        def initialize(path)
          super()
          @path = Pathname.new(path.to_s)
          raise Missing, "arquivo de acervo inexistente: #{@path}" unless @path.file?
        end

        attr_reader :path

        def describe = "tar #{@path} (#{(@path.size / 1_048_576.0).round(1)} MB, #{entries.size} arquivo(s))"

        def entries
          @entries ||= begin
            out, err, status = Open3.capture3('tar', '-tvf', @path.to_s)
            raise Missing, "não consegui listar o tar: #{err.lines.first}" unless status.success?

            out.each_line.with_object({}) do |line, acc|
              next if line.start_with?('d')

              parts = line.split(nil, 6)
              next if parts.size < 6

              acc[parts[5].chomp] = parts[2].to_i
            end
          end
        end

        # Lê UM arquivo do tar direto para a memória. `binmode` é obrigatório:
        # sem ele o Ruby transcodifica o PDF e o SHA-256 muda.
        def read(path)
          out, err, status = Open3.capture3('tar', '-xOf', @path.to_s, '--', path, binmode: true)
          raise Missing, "não consegui ler `#{path}` do tar: #{err.lines.first}" unless status.success?

          out
        end
      end

      # ------------------------------------------------------------------------

      # Uma linha do acervo: o que o banco diz e o que o arquivo é.
      #
      # `detected_type` e `sha256` só existem depois da **conferência de conteúdo**
      # (`inspect_content!`), que é a tarefa 5.3: *"o tipo revalidado pelo
      # conteúdo"*. Antes dela `content_type` é o que o Paperclip **gravou** — e o
      # que o Paperclip gravou é o que o navegador **declarou** em 2022.
      Item = Struct.new(:table, :name, :meta, :legacy_pk, :file_name, :content_type, :declared_size,
                        :archive_path, :archive_size, :detected_type, :sha256, keyword_init: true) do
        def found? = !archive_path.nil?
        def size_match? = found? && (declared_size.nil? || declared_size == archive_size)
        def empty_file? = found? && archive_size.to_i.zero?
        def inspected? = !detected_type.nil?

        # Extensão do nome de arquivo, sem o ponto e em minúscula.
        def extension = File.extname(file_name.to_s).delete('.').downcase.presence

        # O que o banco declarou × o que os bytes dizem. Divergência aqui é o
        # arquivo renomeado — o caso (d) do teste de segurança 4.20.
        def type_mismatch? = inspected? && content_type.present? && detected_type != content_type
      end

      def initialize(source:, system_root: nil, system_tar: nil, report: nil, io: $stdout)
        @source = source
        @archive = Archive.open(root: system_root, tar: system_tar)
        @report = report || Report.new('attachments', io: io)
        @io = io
        @bytes_read = 0
      end

      attr_reader :source, :archive, :report, :io, :bytes_read

      # -------------------------------------------------------------- 5.6 scan
      #
      # `verify_content:` liga a **conferência de conteúdo** (5.3). Ela lê os bytes
      # de cada arquivo do acervo, um por vez, e mede tipo real e assinatura:
      #
      #   :critical  (padrão) só os anexos marcados como documento financeiro
      #   :all                todo anexo do de-para
      #   :none               nenhum — só reconciliação por nome e tamanho
      #
      # O padrão não é preguiça: ler os 467 arquivos custa uma varredura do tar por
      # arquivo, e a única família em que arquivo trocado é **dinheiro** é a da
      # renegociação. Quem quiser tudo pede `VERIFY_CONTENT=all`.
      def scan!(verify_content: :critical)
        report.meta('origem', source.describe)
        report.meta('acervo', archive&.describe || '(nenhum)')
        report.meta('conferência de conteúdo', verify_content)

        if archive.nil?
          blocked_section
          return report
        end

        items = collect_items
        inspect_contents!(items, scope: verify_content)
        report_reconciliation(items)
        report_content_check(items, scope: verify_content)
        report_orphan_files(items)
        report
      end

      # -------------------------------------------------------- 6.7 religação
      #
      # Copia o binário do acervo e **reanexa por ActiveStorage** no registro que o
      # de-para aponta. Registro sem arquivo é reportado, nunca silenciado; arquivo
      # cuja assinatura não bate depois de anexado **aborta**.
      def migrate!(dry_run: true)
        report.meta('origem', source.describe)
        report.meta('acervo', archive&.describe || '(nenhum)')
        report.meta('modo', dry_run ? 'ensaio (não anexa)' : 'religando')
        report.meta('storage de destino', storage_describe)

        # **Portão de storage — tarefa 9.7 / Q-07 / F-13.** Roda ANTES de olhar o
        # acervo: não adianta ter o binário se o destino o perde no primeiro
        # redeploy. Ver `storage_gate!`.
        storage_gate!(dry_run: dry_run)

        if archive.nil?
          blocked_section
          return report
        end

        MAP.each do |table, attachments|
          attachments.each do |name, meta|
            relink_attachment(table, name, meta, dry_run: dry_run)
          end
        end
        report
      end

      # Religa UM registro e **prova** a religação: tamanho e SHA-256 do que voltou
      # do ActiveStorage contra o que saiu do acervo. É a tarefa 6.7 em uma linha,
      # e é o que os testes usam com um PDF de verdade.
      def relink_one!(table, name, legacy_pk)
        meta = MAP.fetch(table).fetch(name)
        item = build_item(table, name, meta, row_for(table, legacy_pk))
        raise Archive::Missing, "sem arquivo no acervo para #{table}##{legacy_pk}" unless item.found?

        record = target_record(table, legacy_pk, meta)
        raise ActiveRecord::RecordNotFound, "sem registro de destino para #{table}##{legacy_pk}" if record.nil?

        bytes = archive.read(item.archive_path)
        attach!(record, meta, item, bytes)
        verify!(record, meta, bytes)
      end

      private

      # ------------------------------------------------------------------------
      # PORTÃO DE STORAGE — tarefa 9.7 · Q-07 · F-13
      # ------------------------------------------------------------------------
      #
      # **`Disk` não serve para o cutover, e até hoje isso só estava ESCRITO.** O
      # runbook trazia a decisão como pré-requisito 1.4 e o cabeçalho de
      # `config/storage.yml` explicava o risco — mas nada, em lugar nenhum, impedia
      # `relink_attachments RELINK=1` de despejar **37,6 MB de documento
      # financeiro** (os 44 anexos de renegociação) num serviço `Disk` dentro do
      # container. Pré-requisito que ninguém confere não é pré-requisito: é
      # lembrete, e lembrete não sobrevive a uma sexta-feira.
      #
      # O modo de falha é o pior que existe num sistema financeiro: **silencioso e
      # diferido**. A carga passa, o portão de reconciliação fecha, alguém assina —
      # e o acervo some no primeiro deploy que troque o diretório, meses depois,
      # com o registro no banco ainda apontando para um blob que não existe.
      #
      # Escolher o provedor continua sendo **decisão do usuário** (DEC-76): esta
      # classe não escolhe nada. Ela recusa a gravação em produção enquanto a
      # escolha não tiver sido feita, e o desvio consciente existe e deixa rastro —
      # `ALLOW_DISK_STORAGE=1` grava a autorização no relatório, com nome próprio.
      #
      # Fora de produção o portão **não bloqueia**: o ensaio precisa rodar, e o dev
      # usa `Disk` por definição. Mas o serviço vai para o cabeçalho de todo
      # relatório, para que "em que storage isto rodou?" seja pergunta de um
      # segundo.
      #
      # ------------------------------------------------------------------------
      # DEC-129.1 — `Disk` PASSA, quando alguém AFIRMA que o volume existe
      # ------------------------------------------------------------------------
      #
      # O usuário decidiu manter `Disk`, com o deploy garantindo um volume que
      # sobrevive a redeploy. **A forma importa, e a DEC é explícita sobre ela:**
      # o ETL não deve simplesmente parar de recusar — isso trocaria uma trava por
      # silêncio, e o modo de falha continuaria sendo o mesmo (anexo que some
      # semanas depois, quando ninguém lembra do dia da virada).
      #
      # Então o portão passa a aceitar `Disk` **quando alguém afirmar
      # explicitamente que o volume é persistente**. São DUAS variáveis, e as duas
      # são exigidas de propósito:
      #
      #   ACTIVE_STORAGE_DISK_VOLUME_IS_PERSISTENT=1
      #   ACTIVE_STORAGE_DISK_VOLUME_CONFIRMED_BY="Nome de gente"
      #
      # O nome da primeira **diz o que está sendo afirmado** (não "permita disk",
      # que é permissão; "o volume do disco é persistente", que é um fato sobre a
      # infraestrutura, verificável e falsificável). A segunda dá **autor** à
      # afirmação — é a mesma regra do `signed_by` de `db/etl/decisions.yml`, e
      # pela mesma razão: autorização sem autor é autorização que ninguém tomou.
      #
      # Afirmar sem assinar é **recusado**, e com mensagem própria. Aceitar a
      # afirmação anônima seria reintroduzir exatamente o `if` que ninguém lê que
      # a DEC-129.1 mandou evitar.
      #
      # A diferença para `ALLOW_DISK_STORAGE=1`, que continua existindo: aquilo é
      # *"grave assim mesmo, eu sei do risco"* (desvio consciente); isto é *"o
      # risco não se aplica aqui, e eis por quê"* (pré-requisito cumprido). São
      # coisas diferentes e o relatório as escreve diferente.
      DISK_OVERRIDE = 'ALLOW_DISK_STORAGE'
      DISK_VOLUME_ASSERTION = 'ACTIVE_STORAGE_DISK_VOLUME_IS_PERSISTENT'
      DISK_VOLUME_AUTHOR = 'ACTIVE_STORAGE_DISK_VOLUME_CONFIRMED_BY'

      def storage_service = ActiveStorage::Blob.service
      def storage_name = Rails.application.config.active_storage.service

      def disk_storage?
        storage_service.is_a?(ActiveStorage::Service::DiskService)
      end

      def storage_describe
        raiz = (" (root: #{storage_service.root})" if disk_storage? && storage_service.respond_to?(:root))
        "#{storage_name} → #{storage_service.class.name.demodulize}#{raiz}"
      end

      # A afirmação da DEC-129.1: o volume é persistente, e QUEM está afirmando.
      # Sem autor a afirmação não vale — e o portão diz isso em vez de aceitar
      # calado.
      def disk_volume_assertion
        afirmado = ENV.fetch(DISK_VOLUME_ASSERTION, nil) == '1'
        autor = ENV.fetch(DISK_VOLUME_AUTHOR, '').to_s.strip
        { asserted: afirmado, author: autor.presence,
          valid: afirmado && autor.present?, anonymous: afirmado && autor.blank? }
      end

      def storage_gate!(dry_run:)
        return unless disk_storage?

        autorizado = ENV.fetch(DISK_OVERRIDE, nil) == '1'
        volume = disk_volume_assertion
        bloqueia = !dry_run && Rails.env.production? && !autorizado && !volume[:valid]

        report.section('Storage de destino — Q-07 (F-13) · DEC-129.1', severity: bloqueia ? :abort : :warn) do |lines|
          lines << "- serviço em uso: `#{storage_describe}`"
          lines << "- ambiente: `#{Rails.env}` · modo: #{dry_run ? 'ensaio (não anexa)' : 'religando'}"
          lines << ''
          if bloqueia
            storage_blocked_lines(lines, volume)
          elsif volume[:valid] && !dry_run
            lines << "**VOLUME AFIRMADO PERSISTENTE** por `#{DISK_VOLUME_ASSERTION}=1`, e quem afirma é"
            lines << "**#{volume[:author]}** (`#{DISK_VOLUME_AUTHOR}`)."
            lines << ''
            lines << 'DEC-129.1: `Disk` fica, com o deploy garantindo um volume que sobrevive. Esta'
            lines << 'linha é a afirmação com autor que a decisão exigiu — não um `if` no código.'
            lines << ''
            lines << '**O runbook cobra a conferência ANTES da carga** (pré-requisito 1.4): que o'
            lines << 'volume está montado no caminho de `ACTIVE_STORAGE_DISK_ROOT` e que ele'
            lines << 'sobrevive a um redeploy. Anexo que some entre deploys é defeito que só'
            lines << 'aparece semanas depois.'
          elsif autorizado && !dry_run
            lines << "**DESVIO AUTORIZADO** por `#{DISK_OVERRIDE}=1`: gravando em `Disk` de"
            lines << 'propósito. Quem assinar este relatório está assinando isto também.'
            lines << ''
            lines << 'Isto NÃO é a afirmação da DEC-129.1 — é o escape antigo. Para declarar que o'
            lines << "volume é persistente, use `#{DISK_VOLUME_ASSERTION}` com `#{DISK_VOLUME_AUTHOR}`."
          else
            lines << 'Sem bloqueio: ensaio não grava, e fora de produção `Disk` é o esperado.'
            lines << 'No cutover (produção, `RELINK=1`) este mesmo trecho **aborta** enquanto'
            lines << "ninguém afirmar o volume por `#{DISK_VOLUME_ASSERTION}` + `#{DISK_VOLUME_AUTHOR}`."
          end
        end
      end

      def storage_blocked_lines(lines, volume)
        if volume[:anonymous]
          lines << "**BLOQUEADO. `#{DISK_VOLUME_ASSERTION}=1` veio SEM AUTOR.**"
          lines << ''
          lines << "Preencha `#{DISK_VOLUME_AUTHOR}` com nome de gente — quem conferiu que o volume"
          lines << 'existe e sobrevive a um redeploy. Afirmação anônima é o `if` que ninguém lê que'
          lines << 'a DEC-129.1 mandou evitar: ela some no histórico do deploy e não responde'
          lines << '"quem disse que isso estava certo?" seis meses depois.'
          return lines
        end

        lines << '**BLOQUEADO. `Disk` sem volume afirmado não serve para o cutover (F-13).** Sem'
        lines << 'volume persistente o anexo desaparece no primeiro redeploy, **em silêncio** — e'
        lines << 'são 37,6 MB de documento financeiro (44 anexos de renegociação, DEC-84).'
        lines << ''
        lines << '**DEC-129.1 — o caminho decidido pelo usuário:** manter `Disk` e AFIRMAR o volume.'
        lines << 'Confirme no servidor que `ACTIVE_STORAGE_DISK_ROOT` é um volume montado e que ele'
        lines << 'sobrevive a um redeploy, e então declare:'
        lines << ''
        lines << "    #{DISK_VOLUME_ASSERTION}=1"
        lines << "    #{DISK_VOLUME_AUTHOR}=\"quem conferiu\""
        lines << ''
        lines << 'O outro caminho continua aberto: os alvos `amazon` e `s3_compatible` já existem'
        lines << 'em `config/storage.yml` — basta apontar `ACTIVE_STORAGE_SERVICE` e preencher as ENV.'
        lines << ''
        lines << "Para gravar assim mesmo, sem afirmar nada: `#{DISK_OVERRIDE}=1` — e a"
        lines << 'autorização fica escrita neste relatório, que é o que se anexa ao portão.'
        lines
      end

      def blocked_section
        report.section('Binários dos anexos — SEM ACERVO NESTA EXECUÇÃO', severity: :warn) do |lines|
          lines << 'Nenhum acervo informado. Rode com um dos dois:'
          lines << ''
          lines << '    SYSTEM_ROOT=/caminho/para/public/system   (diretório extraído)'
          lines << '    SYSTEM_TAR=/caminho/para/acervo.tar       (o tar como veio, lido em fluxo)'
          lines << ''
          lines << '**DEC-84.** Sem o acervo, SÓ OS REGISTROS MIGRAM, e o runbook mantém o passo'
          lines << 'como bloqueado (item 9.6), nunca como concluído.'
        end
      end

      # ------------------------------------------------------------- coleta
      def collect_items
        MAP.flat_map do |table, attachments|
          next [] unless source.table?(table)

          rows = source.each_row(table).to_a
          attachments.flat_map do |name, meta|
            next [] unless source.column_names(table).include?("#{name}_file_name")

            rows.filter_map do |row|
              next if row["#{name}_file_name"].to_s.strip.empty?

              build_item(table, name, meta, row)
            end
          end
        end
      end

      def row_for(table, legacy_pk)
        source.each_row(table).find { |r| r['id'].to_s == legacy_pk.to_s } ||
          raise(ActiveRecord::RecordNotFound, "linha #{table}##{legacy_pk} não existe na origem")
      end

      def build_item(table, name, meta, row)
        file_name = row["#{name}_file_name"].to_s
        declared = row["#{name}_file_size"]
        path = locate(meta, row['id'], file_name)

        Item.new(table: table, name: name, meta: meta, legacy_pk: row['id'], file_name: file_name,
                 content_type: row["#{name}_content_type"],
                 declared_size: declared.presence&.to_i,
                 archive_path: path, archive_size: path && archive.size(path))
      end

      # Casa **por basename**, nunca por "o único arquivo da pasta": `avatars/62/`
      # tem o avatar do usuário 62 E o do projeto 62.
      def locate(meta, legacy_id, file_name)
        base = File.basename(file_name, '.*')
        dir = meta.fetch(:dir)
        candidates = archive.siblings(dir, legacy_id)
        return nil if candidates.empty?

        if meta[:styled]
          candidates.find { |p| File.basename(p) == "#{base}_original#{File.extname(p)}" }
        else
          candidates.find { |p| File.basename(p) == file_name } ||
            candidates.find { |p| File.basename(p, '.*') == base }
        end
      end

      # ------------------------------------------------- conferência de conteúdo
      #
      # **Tarefa 5.3: o tipo é revalidado pelo CONTEÚDO, não pela extensão.**
      #
      # As 4 colunas do Paperclip guardam o que o navegador declarou no upload de
      # 2022 — `file_content_type` é dado do cliente, e o legado ainda desligava a
      # conferência (`do_not_validate_attachment_file_type` + o detector de spoof
      # monkey-patchado para `false`, **D-82**). Confiar nelas na migração é portar
      # a vulnerabilidade junto com o arquivo.
      #
      # Aqui os bytes mandam: `Marcel::MimeType.for` lê os magic bytes, e é o tipo
      # DETECTADO que vai para o `attach!`. O `sha256` sai da mesma leitura e é o
      # que a religação compara depois de anexar.
      def inspect_contents!(items, scope: :critical)
        return if scope.to_sym == :none

        alvo = items.select do |item|
          next false unless item.found?

          scope.to_sym == :all || item.meta[:critical].present?
        end

        alvo.each { |item| inspect_content!(item) }
      end

      # Lê UM arquivo do acervo e mede o que ele é. Devolve os bytes — quem já os
      # tem em mãos não paga uma segunda leitura.
      def inspect_content!(item)
        bytes = archive.read(item.archive_path)
        @bytes_read += bytes.bytesize
        item.detected_type = detect_type(bytes, item.file_name)
        item.sha256 = Digest::SHA256.hexdigest(bytes)
        bytes
      end

      def detect_type(bytes, file_name)
        Marcel::MimeType.for(StringIO.new(bytes), name: file_name.to_s)
      end

      # A allowlist do catálogo (`config/attachments.yml`), em tipos MIME. É a
      # MESMA lista que o servidor aplica no upload — o ETL não pode ser a porta
      # dos fundos por onde entra o que o endpoint recusaria.
      def allowed_types_for(meta)
        model = meta[:model]
        return nil if model.blank?

        chave = Sfg::Attachments.model_key_for(Object.const_get(model))
        spec = Sfg::Attachments.spec_for(chave, meta.fetch(:attachment))
        spec.content_types.map { |ext| Marcel::MimeType.for(name: "arquivo.#{ext}") }.uniq
      rescue StandardError
        nil
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def report_content_check(items, scope: :critical)
        return if scope.to_sym == :none

        conferidos = items.select(&:inspected?)
        if conferidos.empty?
          return report.section('Conferência de conteúdo — nenhum arquivo lido', severity: :info) do |lines|
            lines << "- escopo `#{scope}`: nenhum item elegível tinha arquivo no acervo."
          end
        end

        conferidos.group_by { |i| [i.table, i.name] }.each do |(table, name), list|
          meta = list.first.meta
          permitidos = allowed_types_for(meta)
          divergentes = list.select(&:type_mismatch?)
          fora = permitidos ? list.reject { |i| permitidos.include?(i.detected_type) } : []
          vazios = list.select(&:empty_file?)

          # Tipo recusado pela allowlist **aborta** num anexo crítico: o registro
          # não pode ser reanexado, então ele viraria exatamente o "anexo listado
          # com download que falha" que a DEC-84 existe para impedir.
          severity = if fora.any?
                       meta[:critical] ? :abort : :warn
                     else
                       (divergentes.any? || vazios.any?) ? :warn : :ok
                     end

          report.section("Conteúdo de `#{table}.#{name}`: #{list.size} arquivo(s) lido(s), " \
                         "#{divergentes.size} com tipo diferente do declarado, " \
                         "#{fora.size} fora da allowlist", severity: severity) do |lines|
            lines << '- o tipo vem dos **magic bytes** (Marcel), não da extensão nem da coluna'
            lines << "  `#{name}_content_type` — que é o que o navegador declarou em 2022 (D-82)."
            lines << "- allowlist do catálogo: #{permitidos ? permitidos.join(', ') : '(model ainda sem destino)'}"
            lines << "- bytes lidos nesta família: #{list.sum { |i| i.archive_size.to_i }}"
            list.group_by(&:detected_type).sort_by { |_t, l| -l.size }.each do |tipo, l|
              lines << "- `#{tipo}`: #{l.size} arquivo(s)"
            end
            divergentes.first(40).each do |i|
              lines << "- ⚠ `#{table}`##{i.legacy_pk} `#{i.file_name}` — banco diz `#{i.content_type}`, " \
                       "bytes dizem `#{i.detected_type}`"
            end
            fora.first(40).each do |i|
              lines << "- ✗ `#{table}`##{i.legacy_pk} `#{i.file_name}` — `#{i.detected_type}` NÃO está na " \
                       'allowlist; o endpoint de upload recusaria este arquivo hoje'
            end
            vazios.each do |i|
              lines << "- ⚠ `#{table}`##{i.legacy_pk} `#{i.file_name}` tem **0 byte**; sha256 do vazio " \
                       "`#{i.sha256.to_s[0, 16]}…`"
            end
          end
        end

        report.section("Total lido do acervo nesta conferência — #{bytes_read} bytes", severity: :info) do |lines|
          lines << "- #{conferidos.size} arquivo(s) lido(s) do acervo **em fluxo**, um por vez."
          lines << '- nada foi extraído para o disco (instrução do usuário para esta rodada).'
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # -------------------------------------------------------- reconciliação
      def report_reconciliation(items)
        items.group_by { |i| [i.table, i.name] }.each do |(table, name), list|
          meta = list.first.meta
          missing = list.reject(&:found?)
          divergent = list.select { |i| i.found? && !i.size_match? }
          empties = list.select(&:empty_file?)

          severity = if missing.empty? && divergent.empty?
                       empties.empty? ? :ok : :warn
                     else
                       (meta[:critical] ? :abort : :warn)
                     end

          title = "Anexo `#{table}.#{name}` -> #{meta[:model] || '(sem destino)'}"
          title += " — #{meta[:critical]}" if meta[:critical]
          report.section("#{title}: #{list.size} no banco, #{list.size - missing.size} no acervo, " \
                         "#{missing.size} sem arquivo, #{divergent.size} com tamanho divergente",
                         severity: severity) do |lines|
            lines << "- fatia dona: #{meta[:slice]} · pasta Paperclip: `public/system/#{meta[:dir]}/:id/`"
            lines << '- as 4 colunas Paperclip NÃO são recriadas: o arquivo é copiado e **reanexado** por ActiveStorage'
            lines << "- soma dos tamanhos declarados no banco: #{list.sum { |i| i.declared_size.to_i }} bytes"
            lines << "- soma dos tamanhos no acervo: #{list.sum { |i| i.archive_size.to_i }} bytes"
            missing.first(100).each { |i| lines << "- `#{table}`##{i.legacy_pk} `#{i.file_name}` SEM ARQUIVO no acervo" }
            divergent.first(100).each do |i|
              lines << "- `#{table}`##{i.legacy_pk} `#{i.file_name}` banco #{i.declared_size} B × acervo #{i.archive_size} B"
            end
            empties.each do |i|
              lines << "- ⚠ `#{table}`##{i.legacy_pk} `#{i.file_name}` tem **0 byte** no banco E no acervo — " \
                       'o arquivo existe e está vazio. Reconciliação não pega isto; conferência de conteúdo pega.'
            end
          end
        end

        return if items.any?

        report.section('Nenhum anexo com arquivo declarado nesta origem', severity: :info) do |lines|
          lines << '- as 44 colunas Paperclip existem, mas nenhuma linha tem `_file_name` preenchido'
        end
      end

      # Arquivo no acervo que nenhuma linha do banco reivindica. É o outro lado da
      # reconciliação, e é o que pega arquivo apagado do banco e esquecido no disco.
      def report_orphan_files(items)
        claimed = items.filter_map(&:archive_path).to_set
        styled_dirs = MAP.values.flat_map(&:values).select { |m| m[:styled] }.map { |m| m[:dir] }.uniq
        plain_dirs = MAP.values.flat_map(&:values).reject { |m| m[:styled] }.map { |m| m[:dir] }.uniq

        orphans = archive.entries.keys.select do |path|
          next false if claimed.include?(path)

          dir = path.split('/')[2]
          if styled_dirs.include?(dir)
            File.basename(path, '.*').end_with?('_original')
          else
            plain_dirs.include?(dir)
          end
        end

        report.section("Arquivos no acervo sem linha no banco — #{orphans.size}",
                       severity: orphans.empty? ? :ok : :warn) do |lines|
          if orphans.empty?
            lines << '- nenhum. Todo arquivo original do acervo tem dono no banco.'
          else
            orphans.first(60).each { |p| lines << "- `#{p}` (#{archive.size(p)} B)" }
            lines << "- … (#{orphans.size - 60} outros)" if orphans.size > 60
          end
          lines << ''
          lines << 'Derivados (`_thumb`, `_preview`, `_medium`, `_large`) NÃO são migrados: o ai9'
          lines << 'gera variante sob demanda pelo motor de anexos (S13). Só o `_original` viaja.'
        end
      end

      # ---------------------------------------------------------- religação
      def relink_attachment(table, name, meta, dry_run:)
        return unless source.table?(table)
        return unless source.column_names(table).include?("#{name}_file_name")

        model = meta[:model]
        if model.nil? || !model_ready?(model)
          return report.section("Religação de `#{table}.#{name}` — PULADA", severity: :warn) do |lines|
            lines << "- model de destino #{model.inspect} ainda não existe no ai9 (fatia #{meta[:slice]})"
          end
        end

        items = source.each_row(table).filter_map do |row|
          next if row["#{name}_file_name"].to_s.strip.empty?

          build_item(table, name, meta, row)
        end

        done = []
        # **Registro cujo arquivo não existe mais no acervo tem lista PRÓPRIA**
        # (tarefa 5.3). Misturá-lo com "a tabela ainda não foi carregada" apaga a
        # única distinção que importa: um é dado perdido no legado, o outro é
        # ordem de execução.
        missing = []
        # Arquivo que EXISTE no acervo e tem 0 byte. Não é ausência e não é erro
        # do motor: é um documento vazio gravado assim em 2022, e o próprio
        # Paperclip anotou `inode/x-empty` na coluna de tipo. Anexá-lo carimbado
        # como `application/pdf` — que é o que a extensão faria — produziria um
        # download de 0 byte com cara de PDF válido. Fica sem binário, nomeado.
        empty = []
        skipped = []
        failed = []

        items.each do |item|
          unless item.found?
            missing << "- `#{table}`##{item.legacy_pk} `#{item.file_name}` " \
                       "(#{item.declared_size.to_i} B no banco) — **SEM ARQUIVO no acervo**. " \
                       'O registro NÃO recebe binário, e isso está reportado em vez de virar anexo quebrado.'
            next
          end

          if item.empty_file?
            empty << "- `#{table}`##{item.legacy_pk} `#{item.file_name}` — arquivo existe no acervo e tem " \
                     "**0 byte** (o legado gravou `#{item.content_type}` na própria coluna de tipo). " \
                     'Fica SEM binário: anexá-lo carimbado pela extensão daria um download de 0 byte ' \
                     'com cara de documento válido.'
            next
          end

          record = target_record(table, item.legacy_pk, meta)
          if record.nil?
            skipped << "- `#{table}`##{item.legacy_pk} — sem registro de destino no de-para (`etl_id_map`); " \
                       'carregue a tabela antes de religar o binário'
            next
          end

          # Idempotência: já religado é pulado, sem tocar no ActiveStorage. Rodar
          # duas vezes não pode criar um segundo blob.
          if already_attached?(record, meta)
            skipped << "- `#{table}`##{item.legacy_pk} — já tem binário anexado; nada a fazer (idempotente)"
            next
          end

          if dry_run
            done << "- `#{table}`##{item.legacy_pk} `#{item.file_name}` (#{item.archive_size} B) -> " \
                    "#{meta[:model]}##{record.id}"
            next
          end

          begin
            bytes = inspect_content!(item)
            attach!(record, meta, item, bytes)
            proof = verify!(record, meta, bytes)
            aviso = item.type_mismatch? ? " ⚠ banco dizia `#{item.content_type}`" : ''
            done << "- `#{table}`##{item.legacy_pk} `#{item.file_name}` -> #{meta[:model]}##{record.id} " \
                    "· #{proof[:bytes]} B · `#{item.detected_type}`#{aviso} · sha256 #{proof[:sha256][0, 16]}…"
          rescue StandardError => e
            failed << "- `#{table}`##{item.legacy_pk} `#{item.file_name}` — #{e.class}: #{e.message.lines.first.to_s.strip}"
          end
        end

        # Num anexo crítico (documento financeiro, DEC-84) **arquivo ausente
        # aborta**: o relatório sai vermelho e o passo do runbook não fecha. É a
        # mesma severidade que a reconciliação já dá ao mesmo fato — antes ela
        # divergia da religação, e um dos dois estava mentindo.
        severity = if failed.any? || ((missing + empty).any? && meta[:critical])
                     (meta[:critical] ? :abort : :warn)
                   else
                     ((missing + empty + skipped).any? ? :warn : :ok)
                   end
        report.section("Religação de `#{table}.#{name}` -> #{meta[:model]}: " \
                       "#{done.size} ok, #{missing.size} SEM ARQUIVO no acervo, " \
                       "#{empty.size} com 0 byte, #{skipped.size} sem religar, #{failed.size} com erro",
                       severity: severity) do |lines|
          lines.concat(failed)
          lines.concat(missing.first(60))
          lines << "- … (#{missing.size - 60} outros sem arquivo)" if missing.size > 60
          lines.concat(empty)
          lines.concat(skipped.first(60))
          lines.concat(done.first(60))
          lines << "- … (#{done.size - 60} outros religados)" if done.size > 60
        end
      end

      # Um anexo `has_one_attached` já preenchido. É o que faz a religação ser
      # **resumível**: matar o processo no meio e rodar de novo continua de onde
      # parou, sem duplicar blob.
      def already_attached?(record, meta)
        anexo = record.public_send(meta.fetch(:attachment))
        anexo.respond_to?(:attached?) && anexo.attached?
      rescue StandardError
        false
      end

      def model_ready?(model)
        return false unless Object.const_defined?(model)

        klass = Object.const_get(model)
        klass.respond_to?(:table_exists?) && klass.table_exists?
      rescue StandardError
        false
      end

      # O destino sai **exclusivamente do de-para**. Nunca do id numérico do legado:
      # as tabelas do ai9 são uuid, e casar por número associaria o registro errado.
      def target_record(table, legacy_pk, meta)
        ai9_id = IdMap.resolve(table, legacy_pk)
        return nil if ai9_id.nil?

        Object.const_get(meta.fetch(:model)).find_by(id: ai9_id)
      end

      # **O tipo que vai para o ActiveStorage é o DETECTADO** (tarefa 5.3), nunca o
      # `file_content_type` do Paperclip — aquela coluna guarda o que o navegador
      # declarou em 2022, e o legado desligava a conferência (D-82). Passar o
      # declarado adiante seria reanexar um `.pdf` que é `.svg` com o carimbo de
      # PDF, e o único lugar em que isso apareceria é no download do cliente.
      #
      # `attach` num registro já persistido salva na hora e roda as validações do
      # `Attachable` (allowlist + `spoofing_protection`). Se elas recusarem, o
      # `attach` devolve `false` **sem levantar** — daí o `save!` explícito, que
      # transforma a recusa silenciosa em `RecordInvalid` com o motivo, e o
      # `relink_attachment` a reporta em vez de deixar o registro sem binário.
      def attach!(record, meta, item, bytes)
        tipo = item.detected_type || detect_type(bytes, item.file_name)
        item.detected_type ||= tipo

        record.public_send(meta.fetch(:attachment)).attach(
          io: StringIO.new(bytes), filename: item.file_name, content_type: tipo
        )
        record.save!
        record
      end

      # A PROVA da tarefa 6.7: o que volta do ActiveStorage tem o mesmo tamanho e a
      # mesma assinatura do que saiu do acervo. Tamanho igual com conteúdo diferente
      # é o modo de falha que uma conferência de tamanho sozinha não pega.
      def verify!(record, meta, bytes)
        attachment = record.public_send(meta.fetch(:attachment))
        attachment.reload if attachment.respond_to?(:reload)
        stored = attachment.download

        source_sha = Digest::SHA256.hexdigest(bytes)
        stored_sha = Digest::SHA256.hexdigest(stored)

        if stored.bytesize != bytes.bytesize
          raise "tamanho divergente depois de anexar: acervo #{bytes.bytesize} B, ActiveStorage #{stored.bytesize} B"
        end
        raise "assinatura divergente depois de anexar: #{source_sha} != #{stored_sha}" if source_sha != stored_sha

        { bytes: stored.bytesize, sha256: stored_sha, blob_id: attachment.blob.id }
      end
    end
  end
end
