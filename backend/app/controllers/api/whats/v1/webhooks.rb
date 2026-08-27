# frozen_string_literal: true

module Api
  module Whats
    module V1
      # Webhooks de ciclo de vida da instância Evolution: conexão, logout, QR code
      # e configuração da URL de webhook. É o que o pareamento por QR (e, por
      # consequência, o login por WhatsApp) precisa — ver DEC-14.
      class Webhooks < Grape::API
        resource 'connection-update' do
          desc 'Webhook para processar atualizações de conexão do WhatsApp' do
            detail 'Recebe eventos de mudança de status de conexão do Evolution API'
          end

          params do
          end

          post '', http_codes: [
            [200, 'Processado com sucesso'],
            [400, 'Dados inválidos'],
            [500, 'Erro interno']
          ] do
            WhatsAppWebhookService.process_connection_update(params)
          end
        end

        resource 'logout-instance' do
          desc 'Webhook para processar eventos de logout do WhatsApp' do
            detail 'Recebe eventos de logout de instância do Evolution API'
          end

          params do
          end

          post '', http_codes: [
            [200, 'Processado com sucesso'],
            [400, 'Dados inválidos'],
            [500, 'Erro interno']
          ] do
            WhatsAppWebhookService.process_logout_instance(params)
          end
        end

        resource 'qrcode-updated' do
          desc 'Webhook para processar atualizações de QR Code do WhatsApp' do
            detail 'Recebe eventos de novo QR Code do Evolution API'
          end

          params do
          end

          post '', http_codes: [
            [200, 'Processado com sucesso'],
            [400, 'Dados inválidos'],
            [500, 'Erro interno']
          ] do
            WhatsAppWebhookService.process_qrcode_updated(params)
          end
        end

        resource 'config' do
          desc 'Configurar webhook para Evolution API' do
            detail 'Cria/atualiza configuração de webhook incluindo URL, eventos e flags'
          end

          # `url` é OPCIONAL de propósito. A fonte de verdade passou a ser a
          # configuração (`WHATS_WEBHOOK_URL`, com degrau para `API_HOST`) — ver
          # `PolemkWebhookService.callback_base_url`. Exigir a URL no corpo é o
          # que produziu o `https://tst` que ficou no banco: alguém digitou um
          # placeholder uma vez e nunca mais voltou. Informar a URL continua
          # valendo, e sobrescreve a configurada.
          params do
            optional :url, type: String, desc: 'URL do webhook (padrão: a configurada em WHATS_WEBHOOK_URL)'
            optional :events, type: Array[String], desc: 'Lista de eventos'
            optional :webhookByEvents, type: Boolean, desc: 'Enviar por eventos separados'
            optional :webhookBase64, type: Boolean, desc: 'Arquivos em base64'
          end

          post '', http_codes: [
            [201, 'Configurado'],
            [401, 'Unauthorized'],
            [422, 'Unprocessable Entity'],
            [500, 'Erro interno']
          ] do
            allowed = Sfg::Whats::Access.allowed?(@current_client, @current_user)
            error!({ error: 'unauthorized', message: 'Acesso negado' }, 401) unless allowed

            alvo = params[:url].presence || PolemkWebhookService.callback_base_url
            if alvo.blank?
              error!(
                { error: 'invalid_url',
                  message: 'Nenhuma URL informada e nenhuma configurada (WHATS_WEBHOOK_URL / API_HOST).' }, 422
              )
            end

            begin
              uri = URI.parse(alvo)
              unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
                error!({ error: 'invalid_url', message: 'URL inválida' }, 422)
              end
            rescue URI::InvalidURIError
              error!({ error: 'invalid_url', message: 'URL inválida' }, 422)
            end

            PolemkWebhookService.create_webhook(params.merge(url: alvo))
          end

          get '', http_codes: [
            [200, 'Listagem'],
            [401, 'Unauthorized']
          ] do
            allowed = Sfg::Whats::Access.allowed?(@current_client, @current_user)
            error!({ error: 'unauthorized', message: 'Acesso negado' }, 401) unless allowed
            PolemkWebhookService.list(params)
          end

          post 'test', http_codes: [
            [200, 'OK'],
            [422, 'URL inválida'],
            [502, 'Erro de conexão'],
            [401, 'Unauthorized']
          ] do
            allowed = Sfg::Whats::Access.allowed?(@current_client, @current_user)
            error!({ error: 'unauthorized', message: 'Acesso negado' }, 401) unless allowed

            error!({ error: 'invalid_url', message: 'URL é obrigatória' }, 422) unless params[:url].present?
            PolemkWebhookService.test_connection(params[:url])
          end
        end
      end
    end
  end
end
