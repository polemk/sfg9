# frozen_string_literal: true

module Api
  module V1
    # Leitura de anexo do Safegold — OPS-491, OPS-492.
    #
    # **Este é o único caminho pelo qual um binário do Safegold sai do servidor.**
    # A regra que ele implementa: *autoriza primeiro, assina depois*. O legado fazia
    # o contrário — o arquivo morava em `public/system/:attachment/:id/...`, com URL
    # adivinhável e servida como estático, sem autenticação nenhuma (D-82). A base
    # ai9 repete o mesmo padrão em `AssetsProxyController` (flag F-10); o Safegold
    # simplesmente não usa nenhum dos dois.
    #
    # A URL devolvida **tem prazo** (`url_expires_in_seconds` do
    # `config/attachments.yml`, hoje 5 min). Ela é um portador: quem a tiver, abre o
    # arquivo. Prazo curto é o que impede que ela vire link compartilhável.
    class Attachments < Grape::API
      helpers Api::V1::ControllerHelpers

      resource :attachments do
        desc 'Limites de anexo declarados em config/attachments.yml (CFG-02).'
        get :limits do
          authenticate_user!
          status 200
          {
            url_expires_in_seconds: Sfg::Attachments.url_expires_in.to_i,
            attachments: Sfg::Attachments.limits_payload
          }
        end

        route_param :signed_id, type: String do
          desc 'URL assinada de prazo curto para o anexo, emitida APÓS a autorização.'
          get do
            authenticate_user!
            attachment = resolve_attachment!(params[:signed_id])
            authorize_attachment!(attachment)

            status 200
            {
              id: params[:signed_id],
              filename: attachment.filename.to_s,
              content_type: attachment.content_type,
              byte_size: attachment.byte_size,
              url: Sfg::Attachments.url_for(attachment),
              expires_at: Sfg::Attachments.url_expires_in.from_now
            }
          end

          desc 'URL assinada de um derivado nomeado (thumb, preview, large…).'
          params do
            requires :variant, type: String, desc: 'Nome do derivado declarado no catálogo'
          end
          get :variant do
            authenticate_user!
            attachment = resolve_attachment!(params[:signed_id])
            authorize_attachment!(attachment)

            spec = attachment_spec_for(attachment)
            unless spec.variant_names.include?(params[:variant].to_sym)
              error!({ error: 'not_found',
                       message: "Derivado `#{params[:variant]}` não declarado para este anexo." }, 404)
            end

            url = Sfg::Attachments.variant_url(attachment, params[:variant])
            error!({ error: 'unprocessable', message: 'Não foi possível gerar o derivado.' }, 422) if url.blank?

            status 200
            { id: params[:signed_id], variant: params[:variant], url: url,
              expires_at: Sfg::Attachments.url_expires_in.from_now }
          end
        end
      end

      helpers do
        # Anexo inexistente e anexo não autorizado respondem **404 do mesmo jeito**.
        # Distinguir 403 de 404 aqui transformaria o endpoint num oráculo de
        # existência de anexo — a mesma razão pela qual `current_project!` responde
        # 404 para projeto sem participação (DC-08).
        def resolve_attachment!(signed_id)
          attachment = Sfg::Attachments.find_signed(signed_id)
          attachment_not_found! if attachment.blank?
          attachment_not_found! if attachment.record.blank?
          attachment
        end

        def authorize_attachment!(attachment)
          record = attachment.record
          readable = Sfg::Attachments.readable?(record: record, name: attachment.name, user: acting_user)
          attachment_not_found! unless readable
        end

        def attachment_spec_for(attachment)
          Sfg::Attachments.spec_for(
            Sfg::Attachments.model_key_for(attachment.record.class),
            attachment.name
          )
        rescue KeyError
          attachment_not_found!
        end

        def attachment_not_found!
          error!({ error: 'not_found', message: 'Anexo não encontrado.', code: 'ATTACHMENT_NOT_FOUND' }, 404)
        end
      end
    end
  end
end
