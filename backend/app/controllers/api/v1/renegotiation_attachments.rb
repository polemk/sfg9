# frozen_string_literal: true

module Api
  module V1
    # S9 / BE-225, BE-226, BE-227, BE-229 — **anexos da renegociação**.
    #
    # É o recurso do **D-82**, que são cinco defeitos de segurança na mesma tela.
    # O que muda, endpoint por endpoint:
    #
    # - **`GET`** — a rota do legado **nunca funcionou**: o `search` atribuía
    #   `@limit`/`@offset` e a view iterava sobre `la` quando a variável era `ra`
    #   (`NameError` garantido). Aqui a lista existe, pagina e ordena.
    # - **`GET :id/download`** — **autorizado por projeto**, nome original
    #   preservado, `Content-Disposition: attachment` **sempre**. No legado era
    #   `send_file` com `disposition: 'inline'` e o content-type que o **uploader**
    #   declarou: XSS armazenado na mesma origem, sem checagem de permissão
    #   nenhuma. **Posse da URL não é autorização.**
    # - **`PUT :id`** — renomear, que **nasce funcionando** (DEC-53). No legado a
    #   action chamava `renegotiation_params` (método inexistente neste
    #   controller) e `update_attributes` (removido no Rails 6.1), com o
    #   `respond_to` inteiro comentado.
    # - **`DELETE :id`** — **só o autor**, checado no servidor. No legado a regra
    #   de dono era só visual.
    #
    # **`AssetsProxyController` não é reusado de forma alguma** — ele serve
    # `public/uploads/**` inline e sem autenticação, que é literalmente o padrão do
    # D-82 (flag F-1, registrada e **não** mexida: é usado por outros sistemas da
    # base).
    class RenegotiationAttachments < Grape::API
      helpers Api::V1::ControllerHelpers

      RESOURCE = 'renegotiation_attachments'

      namespace 'renegotiations/:renegotiation_id/attachments' do
        before { authenticate_user! }

        desc 'Lista os anexos de uma renegociação' do
          success [code: 200, model: Api::Entities::RenegotiationAttachment]
          is_array true
        end
        params do
          requires :renegotiation_id, type: String
          optional :q, type: String, desc: 'Busca no título do anexo'
          optional :page, type: Integer, default: 1
          optional :per_page, type: Integer, default: 20
        end
        get '' do
          authorize!(RESOURCE, :read)
          renegotiation = fetch_renegotiation!

          scope = renegotiation.attachments.includes(:author, file_attachment: :blob).ordered
          if params[:q].present?
            padrao = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)}%"
            scope = scope.where('renegotiation_attachments.title ILIKE ?', padrao)
          end

          Api::Entities::RenegotiationAttachment.represent(paginate(scope).to_a, current_user: acting_user)
        end

        desc 'Limites do anexo, vindos do catálogo (CFG-02)' do
          detail 'A tela NÃO tem "4" nem "5 MB" escritos nela. Corrige D-50: no legado os dois números só ' \
                 'existiam no JavaScript, lendo um seletor de OUTRO produto e comparando com NaN.'
        end
        params { requires :renegotiation_id, type: String }
        get :limits do
          authorize!(RESOURCE, :read)
          renegotiation = fetch_renegotiation!
          spec = ::Renegotiations::AttachmentService.spec

          status 200
          {
            max_files: spec.max_files,
            max_size_bytes: spec.max_size_bytes,
            max_size_megabytes: spec.max_size_megabytes,
            content_types: spec.content_types.map(&:to_s),
            used: renegotiation.attachments_count,
            remaining: [spec.max_files - renegotiation.attachments_count, 0].max
          }
        end

        desc 'Envia arquivos' do
          detail 'Limites aplicados NO SERVIDOR (4 arquivos contra o ESTADO, 5 MB por arquivo) e tipo ' \
                 'conferido pelos MAGIC BYTES contra allowlist. Ou todos entram, ou nenhum entra.'
        end
        params do
          requires :renegotiation_id, type: String
          requires :files, type: Array[File], desc: 'Arquivos'
        end
        post '' do
          authorize!(RESOURCE, :create)
          renegotiation = fetch_renegotiation!

          resultado = ::Renegotiations::AttachmentService.attach!(
            renegotiation: renegotiation, files: params[:files], actor: acting_user
          )
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] >= 400

          status 201
          Api::Entities::RenegotiationAttachment.represent(resultado[:data][:attachments],
                                                           current_user: acting_user)
        end

        desc 'Renomeia um anexo (DEC-53 — nunca funcionou no legado)'
        params do
          requires :renegotiation_id, type: String
          requires :id, type: String
          requires :title, type: String
        end
        put ':id' do
          authorize!(RESOURCE, :update)
          anexo = fetch_attachment!

          resultado = ::Renegotiations::AttachmentService.rename!(attachment: anexo, title: params[:title])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          Api::Entities::RenegotiationAttachment.represent(resultado[:data], current_user: acting_user)
        end

        desc 'Baixa o binário — AUTORIZADO por projeto' do
          detail 'Content-Disposition SEMPRE `attachment`, nome original preservado, arquivo ausente → 404 ' \
                 'legível. Modelo: `api/v1/downloads.rb:17-40`.'
        end
        params do
          requires :renegotiation_id, type: String
          requires :id, type: String
        end
        get ':id/download' do
          authorize!(RESOURCE, :read)
          anexo = fetch_attachment!

          unless anexo.file.attached?
            error!({ error: 'not_found', message: 'O arquivo deste anexo não está disponível.' }, 404)
          end

          blob = anexo.file.blob
          # `attachment` SEMPRE, nunca `inline`: o legado servia `inline` com o
          # content-type que o uploader declarou, o que faz um `.svg` renomeado
          # para `.pdf` executar script na origem da aplicação.
          header 'Content-Disposition',
                 ActionDispatch::Http::ContentDisposition.format(disposition: 'attachment',
                                                                 filename: anexo.filename)
          header 'Content-Type', blob.content_type
          header 'Content-Length', blob.byte_size.to_s
          # `X-Content-Type-Options` fecha o sniffing do navegador: sem ele, um
          # tipo declarado corretamente ainda pode ser reinterpretado.
          header 'X-Content-Type-Options', 'nosniff'
          env['api.format'] = :binary
          body blob.download
        end

        desc 'Remove um anexo — SÓ o autor, checado no servidor (BE-229)'
        params do
          requires :renegotiation_id, type: String
          requires :id, type: String
        end
        delete ':id' do
          authorize!(RESOURCE, :destroy)
          anexo = fetch_attachment!

          resultado = ::Renegotiations::AttachmentService.destroy!(attachment: anexo, actor: acting_user)
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] >= 400
          resultado[:data]
        end
      end

      helpers do
        def fetch_renegotiation!
          resultado = RenegotiationService.show(project: current_project!, id: params[:renegotiation_id])
          error!(error_payload_for(resultado), resultado[:status]) if resultado[:status] != 200
          resultado[:data]
        end

        # **Anexo de outro projeto é recusado ANTES da checagem de autoria.** A
        # ordem importa: conferir autoria primeiro responderia 403 para um anexo
        # alheio, confirmando que ele existe.
        def fetch_attachment!
          renegotiation = fetch_renegotiation!
          anexo = renegotiation.attachments.find_by(id: uuid_or_nil(params[:id]))
          error!({ error: 'not_found', message: 'Anexo não encontrado.' }, 404) if anexo.nil?
          anexo
        end

        def uuid_or_nil(valor)
          valor.to_s.match?(ProjectScopedService::UUID_FORMAT) ? valor : nil
        end
      end
    end
  end
end
