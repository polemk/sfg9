# frozen_string_literal: true

module Sfg
  # Motor **único** de anexos do Safegold (sub-bloco B da S13, antecipado pela
  # DEC-63/P-100 para rodar logo depois da S1).
  #
  # Por que ele existe antes das fatias que o consomem: a base ai9 já tinha **dois**
  # caminhos de arquivo (C-04) — ActiveStorage no antigo `Medium` e gravação crua em
  # `public/uploads` servida sem autenticação pelo `AssetsProxyController`. Se a S9
  # (renegociações, 4 anexos de documento financeiro) tivesse chegado primeiro, ela
  # improvisaria um terceiro. Este arquivo é o caminho que sobra.
  #
  # Três garantias, e cada uma fecha um defeito medido:
  #
  #  1. **Limite vem de `config/attachments.yml` (CFG-02), nunca do código.** O legado
  #     validava 4 arquivos / 5 MB só no JavaScript da tela — o servidor aceitava
  #     qualquer coisa. Aqui o cliente é conveniência e o servidor é o limite.
  #  2. **Tipo é conferido pelo conteúdo real, não pelo `Content-Type` declarado.**
  #     `api/v1/uploads.rb:31` confia no que o cliente disse (flag F-09); o
  #     `active_storage_validations` 3.x lê os magic bytes via Marcel.
  #  3. **Binário nunca é URL pública.** Toda leitura passa por
  #     `GET /api/v1/attachments/:signed_id`, que autoriza ANTES de emitir uma URL
  #     assinada de prazo curto. É o D-82 do legado (arquivo em `public/system/`,
  #     URL adivinhável, sem autenticação) fechado para valer.
  #
  # Uso no model dono — é isto que S9/S17/S3/S4 escrevem, e nada além disto:
  #
  #     class Renegotiation < ApplicationRecord
  #       include Attachable
  #       sfg_attachment :files
  #     end
  module Attachments
    CONFIG_PATH = Rails.root.join('config/attachments.yml')

    # Propósito do identificador assinado que o front recebe no lugar do id cru. Não
    # é segurança por si (a autorização é conferida a cada leitura) — é para que um
    # id de anexo não vire um contador enumerável na resposta da API.
    #
    # **Por que um verificador próprio e não o `signed_id` do ActiveRecord:** medido
    # nesta base (Rails 8.0.4), `ActiveStorage::Attachment.signed_id_verifier` e o
    # verificador que a INSTÂNCIA usa em `#signed_id` são objetos diferentes, e o
    # `find_signed!` do próprio round-trip levanta `InvalidSignature: mismatched
    # digest`. Em vez de depender de um detalhe interno que já diverge, o token é
    # emitido e conferido aqui, num verificador nomeado — que é também o que permite
    # trocar o prazo sem mexer em model nenhum.
    SIGNED_ID_PURPOSE = 'sfg/attachment'

    # Quem pode LER o binário. Não existe política default: anexo sem `policy`
    # declarada levanta na carga da classe. Default silencioso em autorização é como
    # documento financeiro vira link público.
    POLICIES = {
      # Qualquer sessão válida. Para o que já é visível a qualquer usuário do
      # sistema de qualquer forma (avatar em lista de usuários, trilha).
      'authenticated' => ->(record:, user:) { user.present? },

      # C1 — o binário segue o escopo do dono. É a política do documento
      # financeiro: renegociação, fornecedor, portador, projeto.
      'project_member' => lambda { |record:, user:|
        return false if user.blank?
        return true if user.og?

        project_id = record.respond_to?(:project_id) ? record.project_id : record.try(:id)
        project_id.present? && user.member_of?(project_id)
      },

      # O próprio dono do registro, ou quem administra.
      'owner' => lambda { |record:, user:|
        return false if user.blank?
        return true if user.og? || user.admin?
        return record.id == user.id if record.is_a?(User)

        record.respond_to?(:user_id) && record.user_id == user.id
      },

      'og_admin' => ->(record:, user:) { user.present? && (user.og? || user.admin?) }

      # `public_brand` ESTEVE aqui e foi removida junto com o catálogo `app_theme`
      # de `config/attachments.yml` (DEC-55: a área de temas não é portada).
      #
      # Era a única política que devolvia `true` sem olhar o usuário — anexo legível
      # ANTES de existir sessão, porque a tela de login precisava do logo do tema.
      # Sem tema, ela ficou sem consumidor, e política de "todo mundo, inclusive
      # anônimo" sem consumidor é arma carregada: a próxima linha de catálogo que a
      # escolhesse por engano abriria o anexo para a internet.
      #
      # A marca hoje é arquivo estático versionado (`frontend/public/images/brand/`),
      # servido pelo próprio front — não passa por este motor e não precisa de
      # política nenhuma. Se algum dia existir anexo genuinamente público, ele nasce
      # com política nomeada e um teste que prove que é público de propósito.
    }.freeze

    # Um anexo declarado, já validado contra o catálogo.
    Spec = Struct.new(
      :model_key, :name, :multiple, :max_files, :max_size_bytes,
      :content_types, :policy, :variants,
      keyword_init: true
    ) do
      def multiple? = multiple

      # Texto que o servidor devolve quando recusa — os mesmos números da tela,
      # porque saem da mesma linha do catálogo.
      def max_size_megabytes = (max_size_bytes.to_f / 1.megabyte).round

      def variant_names = variants.keys
    end

    class << self
      def config
        # Em desenvolvimento o arquivo é relido: mexer no limite não deve exigir
        # reiniciar o servidor, senão ninguém mexe no arquivo certo.
        @config = nil if Rails.env.development?
        @config ||= YAML.safe_load_file(CONFIG_PATH, aliases: true).freeze
      end

      def url_expires_in
        config.dig('defaults', 'url_expires_in_seconds').to_i.seconds
      end

      # Prazo das URLs de imagem. Ver o comentário no catálogo: documento e imagem
      # têm prazos diferentes de propósito, e os dois são declarados.
      def image_url_expires_in
        config.dig('defaults', 'image_url_expires_in_seconds').to_i.seconds
      end

      # Chave do model no catálogo: `Renegotiation` → `renegotiation`.
      def model_key_for(klass) = klass.name.underscore

      # Levanta com instrução, não com `nil`. É o mesmo padrão do `Auditable`:
      # declarar anexo fora do catálogo é o começo do segundo motor.
      def spec_for(model_key, name)
        raw = config.dig('attachments', model_key.to_s, name.to_s)
        if raw.nil?
          raise KeyError, "Anexo `#{name}` de `#{model_key}` não está declarado em " \
                          'config/attachments.yml (CFG-02). Declare o limite lá — ' \
                          'anexo com limite escrito no model é o segundo motor nascendo.'
        end

        policy = raw['policy'].to_s
        unless POLICIES.key?(policy)
          raise KeyError, "Política de leitura `#{raw['policy']}` desconhecida para " \
                          "#{model_key}.#{name}. Conhecidas: #{POLICIES.keys.join(', ')}."
        end

        Spec.new(
          model_key: model_key.to_s,
          name: name.to_sym,
          multiple: raw.fetch('multiple', false),
          max_files: raw['max_files'],
          max_size_bytes: raw.fetch('max_size_bytes'),
          content_types: Array(raw.fetch('content_types')).map(&:to_sym),
          policy: policy,
          variants: (raw['variants'] || {}).transform_keys(&:to_sym)
        )
      end

      # Todos os specs declarados, para o portão de conferência e para o endpoint
      # de limites que a tela consome.
      def all_specs
        config.fetch('attachments').flat_map do |model_key, names|
          names.keys.map { |name| spec_for(model_key, name) }
        end
      end

      # Payload de limites para o front. A tela NÃO tem número escrito nela: os
      # textos "máximo de 4 arquivos" e "5 MB" são formatados a partir daqui.
      def limits_payload
        all_specs.each_with_object({}) do |spec, acc|
          acc[spec.model_key] ||= {}
          acc[spec.model_key][spec.name.to_s] = {
            multiple: spec.multiple?,
            max_files: spec.max_files,
            max_size_bytes: spec.max_size_bytes,
            max_size_megabytes: spec.max_size_megabytes,
            content_types: spec.content_types.map(&:to_s)
          }
        end
      end

      # ------------------------------------------------------------------
      # Leitura
      # ------------------------------------------------------------------
      def readable?(record:, name:, user:)
        spec = spec_for(model_key_for(record.class), name)
        POLICIES.fetch(spec.policy).call(record: record, user: user)
      rescue KeyError
        # Anexo que o catálogo não conhece não é legível. Falhar fechado.
        false
      end

      # URL assinada de prazo curto. **Único** emissor de URL de anexo do Safegold —
      # nada de `rails_blob_url` espalhado por entity, que é como um deles acaba sem
      # prazo.
      def url_for(attachment, expires_in: url_expires_in)
        return nil if attachment.blank?

        # Caminho RELATIVO em desenvolvimento, para o proxy do Vite interceptar —
        # é a receita que `Carrier` já usa nesta base, e trocá-la por
        # URL absoluta faria o anexo do front de dev sair do proxy sem aviso.
        # Absoluto no resto, porque lá o front está noutro host.
        if Rails.env.development?
          Rails.application.routes.url_helpers.rails_blob_path(
            attachment, only_path: true, expires_in: expires_in, disposition: 'inline'
          )
        else
          Rails.application.routes.url_helpers.rails_blob_url(
            attachment, host: default_host, expires_in: expires_in, disposition: 'inline'
          )
        end
      rescue StandardError => e
        Rails.logger.warn("[Sfg::Attachments] falha ao assinar URL: #{e.class}: #{e.message}")
        nil
      end

      def variant_url(attachment, variant_name, expires_in: url_expires_in)
        return nil if attachment.blank?
        return nil unless attachment.variable?

        variant = attachment.variant(variant_name.to_sym).processed
        if Rails.env.development?
          Rails.application.routes.url_helpers.rails_representation_path(
            variant, only_path: true, expires_in: expires_in
          )
        else
          Rails.application.routes.url_helpers.rails_representation_url(
            variant, host: default_host, expires_in: expires_in
          )
        end
      rescue StandardError => e
        Rails.logger.warn("[Sfg::Attachments] falha ao gerar variante #{variant_name}: #{e.class}: #{e.message}")
        nil
      end

      # Metadados de UM anexo, no formato que `Api::Entities::Attachment` expõe.
      # O id **nunca** é o id cru: é o `signed_id`, para que a resposta não vire um
      # contador enumerável de anexos.
      def describe(attachment)
        return nil if attachment.blank?

        {
          id: sign_id(attachment.id),
          filename: attachment.filename.to_s,
          content_type: attachment.content_type,
          byte_size: attachment.byte_size,
          created_at: attachment.created_at
        }
      end

      def describe_many(attachments)
        Array(attachments).filter_map { |a| describe(a) }
      end

      # Verificador nomeado do identificador de anexo. Ver a nota em
      # `SIGNED_ID_PURPOSE`.
      def signed_id_verifier
        @signed_id_verifier ||= Rails.application.message_verifier(SIGNED_ID_PURPOSE)
      end

      def sign_id(attachment_id)
        signed_id_verifier.generate(attachment_id.to_s)
      end

      # Devolve `nil` — nunca levanta — para qualquer token inválido, expirado ou
      # de anexo já removido. O endpoint traduz isso para 404, o mesmo 404 do anexo
      # que existe mas o usuário não pode ler.
      def find_signed(signed_id)
        return nil if signed_id.blank?

        attachment_id = signed_id_verifier.verified(signed_id.to_s)
        return nil if attachment_id.blank?

        ActiveStorage::Attachment.find_by(id: attachment_id)
      rescue StandardError
        nil
      end

      # ------------------------------------------------------------------
      # Escrita
      # ------------------------------------------------------------------
      # Anexa arquivos ao registro respeitando o catálogo. Devolve
      # `[:ok, record]` ou `[:error, mensagem]` — o endpoint traduz para HTTP.
      #
      # O teto de quantidade é conferido **aqui**, contra o que já está anexado, e
      # não só sobre o lote que chegou: sem isso, quatro requisições de um arquivo
      # cada passam pela validação de lote e o registro termina com oito.
      def attach!(record:, name:, files:)
        spec = spec_for(model_key_for(record.class), name)
        incoming = Array(files).compact
        return [:error, 'Nenhum arquivo enviado.'] if incoming.empty?

        if !spec.multiple? && incoming.size > 1
          return [:error, 'Este campo aceita apenas um arquivo.']
        end

        association = record.public_send(name)

        if spec.multiple? && spec.max_files.present?
          already = association.attachments.size
          if already + incoming.size > spec.max_files
            return [:error, "O máximo de arquivos permitido para envio é de #{spec.max_files} arquivos"]
          end
        end

        oversized = incoming.find { |f| upload_size(f) > spec.max_size_bytes }
        if oversized
          return [:error,
                  "O tamanho máximo de cada arquivo permitido para envio é de #{spec.max_size_megabytes} MB"]
        end

        payloads = incoming.map { |f| to_attachable(f) }

        record.transaction do
          spec.multiple? ? association.attach(*payloads) : association.attach(payloads.first)
          record.save!
        end

        [:ok, record]
      rescue ActiveRecord::RecordInvalid => e
        [:error, e.record.errors.full_messages.to_sentence.presence || e.message]
      end

      # Remove um anexo específico (pelo `signed_id`) de um registro. Devolve
      # `[:ok, nil]` ou `[:error, mensagem]`.
      def detach!(record:, name:, signed_id:)
        spec_for(model_key_for(record.class), name) # valida a declaração
        attachment = find_signed(signed_id)
        return [:error, 'Anexo não encontrado.'] if attachment.blank?

        # `record_id` é **string** desde a migration `20260825214500` (é o que
        # permite model de PK bigint ter anexo). Comparar com o id do registro sem
        # converter faz `"5" == 5` dar `false` e a remoção falhar em silêncio para
        # todo model bigint — que é a metade do domínio Safegold.
        unless attachment.record_type == record.class.name &&
               attachment.record_id.to_s == record.id.to_s &&
               attachment.name.to_s == name.to_s
          return [:error, 'Anexo não pertence a este registro.']
        end

        attachment.purge_later
        [:ok, nil]
      end

      private

      def default_host
        ENV['API_HOST'].presence ||
          Rails.application.routes.default_url_options[:host].presence ||
          'http://localhost:3000'
      end

      # Grape entrega `{filename:, type:, tempfile:}`; Rack entrega
      # `ActionDispatch::Http::UploadedFile`. As duas formas chegam aqui.
      def upload_size(file)
        return file.tempfile.size if file.respond_to?(:tempfile)
        return file[:tempfile].size if file.is_a?(Hash) && file[:tempfile]
        return file.size if file.respond_to?(:size)

        0
      end

      def to_attachable(file)
        if file.is_a?(Hash)
          {
            io: file[:tempfile],
            filename: file[:filename],
            content_type: file[:type]
          }
        else
          file
        end
      end
    end
  end
end
