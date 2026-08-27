# frozen_string_literal: true

module Api
  module V1
    # **Este NÃO é o caminho de anexo do Safegold.**
    #
    # O avatar do Safegold sai por `POST /api/v1/users/:id/avatar`, que passa pelo
    # motor único (`Sfg::Attachments` + `config/attachments.yml`): ActiveStorage
    # privado, URL assinada de prazo curto, política de leitura declarada. Ver a nota
    # extensa em `api/v1/users.rb`.
    #
    # Este endpoint continua existindo porque é da base ai9 e **tem dois consumidores
    # vivos** que não são deste produto — `features/chat-builder/components/
    # AIAgentConfigPanel.tsx:226` e `FlowSettingsModal.tsx:72`, que enviam a imagem do
    # agente do assistente interno. Removê-lo quebraria as duas telas (Regra de
    # fronteira), e reescrevê-las para o motor de anexos é escopo da fatia dona do
    # chat, não desta.
    #
    # ## O que a S1 mudou aqui, e por quê
    #
    # Duas linhas de segurança, e **só** elas — nada de reescrever o endpoint:
    #
    #  1. **Tipo pelo conteúdo real (F-09).** A versão anterior fazia
    #     `ct.start_with?('image/')` sobre o `Content-Type` que o **cliente** declarou:
    #     bastava mandar um `.html` (ou um `.svg` com `<script>`) rotulado como
    #     `image/png` para gravá-lo na árvore pública e servi-lo como estático. O
    #     Marcel lê os magic bytes do arquivo, que é o mesmo mecanismo que o
    #     `active_storage_validations` usa no motor novo.
    #  2. **Teto de tamanho no servidor.** Não havia nenhum: qualquer sessão
    #     autenticada enchia o disco da aplicação.
    #
    # Isto é exceção prevista no DEC-30 ("segurança/autorização") e mudança mínima
    # sobre base compartilhada (Princípio 6b): o contrato de resposta não muda, os
    # dois consumidores continuam funcionando, e o que passa a falhar é só o que
    # nunca deveria ter passado.
    #
    # O que **não** foi consertado aqui, e continua flag de upstream: o arquivo
    # continua indo para `public/uploads/avatars/`, servido sem autenticação. Corrigir
    # isso é mover os dois consumidores para o motor de anexos — trabalho da fatia do
    # chat, não desta.
    class Uploads < Grape::API
      helpers Api::V1::ControllerHelpers

      # Os mesmos formatos que `config/attachments.yml` declara para imagem, escritos
      # como MIME porque aqui não há catálogo de anexo para consultar.
      ALLOWED_IMAGE_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze

      # 3 MB — o mesmo teto do avatar no catálogo. Um número só para a casa inteira.
      MAX_UPLOAD_BYTES = 3.megabytes

      helpers do
        def require_user!
          return if defined?(@current_user) && @current_user.present?

          error!({ error: 'unauthorized', message: 'Usuário não autenticado' },
                 401)
        end

        # O tipo REAL, lido **só** dos magic bytes.
        #
        # ⚠ Nem o `name:` nem o `declared_type:` do Marcel entram aqui, e isso é o
        # ponto do método: os dois vêm do cliente e o Marcel os usa como dica quando
        # o conteúdo é ambíguo. Medido nesta base — um arquivo de texto puro chamado
        # `fake.png` volta como `image/png` quando o nome é passado, e como
        # `text/plain` quando não é. Passar o nome refaz exatamente o buraco que este
        # método existe para fechar. Os cinco formatos aceitos (PNG, JPEG, WEBP, GIF)
        # têm assinatura de bytes própria e não precisam de dica nenhuma.
        def detected_content_type(tempfile)
          tempfile.rewind if tempfile.respond_to?(:rewind)
          Marcel::MimeType.for(tempfile)
        rescue StandardError
          nil
        end
      end

      resource :avatar do
        params do
          requires :file, type: File, desc: 'Arquivo de imagem'
        end

        post '', http_codes: [
          [201, 'Created'],
          [400, 'Bad Request'],
          [401, 'Unauthorized'],
          [413, 'Payload Too Large'],
          [415, 'Unsupported Media Type'],
          [500, 'Internal Server Error']
        ] do
          require_user!
          f = params[:file]
          tempfile = f[:tempfile]

          size = tempfile.respond_to?(:size) ? tempfile.size.to_i : 0
          if size > MAX_UPLOAD_BYTES
            error!({ error: 'payload_too_large',
                     message: "O tamanho máximo permitido é de #{MAX_UPLOAD_BYTES / 1.megabyte} MB" },
                   413)
          end

          real_type = detected_content_type(tempfile)
          unless ALLOWED_IMAGE_TYPES.include?(real_type)
            # A mensagem cita o tipo DETECTADO, não o declarado: quem enviou um
            # arquivo errado por engano precisa saber o que o servidor viu.
            error!({ error: 'unsupported_media_type',
                     message: "Arquivo deve ser imagem (detectado: #{real_type || 'desconhecido'})" },
                   415)
          end

          ext = File.extname((f[:filename] || '').to_s).downcase
          ext = '.jpg' if ext.blank?
          dir = Rails.root.join('public', 'uploads', 'avatars')
          FileUtils.mkdir_p(dir)
          name = "#{SecureRandom.uuid}#{ext}"
          path = dir.join(name)
          tempfile.rewind if tempfile.respond_to?(:rewind)
          IO.copy_stream(tempfile, path)
          status 201
          { url: "#{request.base_url}/uploads/avatars/#{name}" }
        rescue StandardError => e
          error!({ error: 'internal_error', message: e.message }, 500)
        end
      end
    end
  end
end
