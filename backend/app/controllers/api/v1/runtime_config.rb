# frozen_string_literal: true

module Api
  module V1
    # Configuração que o **navegador** precisa em runtime — DEC-61.
    #
    # O buraco que esta classe fecha: o DEC-61 mandou as chaves de terceiro para o model
    # `Credential`, encriptadas por Active Record Encryption e gerenciáveis por tela
    # (`/admin/credentials`), sem deploy. Isso resolve a ReceitaWS, que é consumida pelo
    # backend. **Não resolve o Google Maps**: o script do mapa é carregado pelo
    # navegador, e chave encriptada no banco não chega ao navegador sozinha. Sem este
    # endpoint, o mapa não carrega e o `Credential` guarda uma chave que ninguém lê.
    #
    # Das duas saídas que o DEC-61 admite, esta é a recomendada — a alternativa era
    # manter a chave em `VITE_GOOGLE_API_KEY`, o que a assa no bundle: qualquer um que
    # baixe o JS a tem, e trocá-la exige um build. Aqui ela sai do banco a cada carga de
    # página, exige sessão, e a troca é imediata pela tela de credenciais.
    #
    # **O que este endpoint NÃO é:** um cofre. Chave de Google Maps que vai para o
    # navegador é pública por construção — o navegador precisa dela em claro para
    # montar a URL do script. A proteção real é a **restrição por referrer/IP no Google
    # Cloud**, e ela é ação externa, registrada no runbook. O que se ganha aqui é: (a)
    # a chave sai do código-fonte e do bundle, (b) rotacionar é trocar uma linha no
    # banco, (c) anônimo não a coleta raspando o JS.
    class RuntimeConfig < Grape::API
      format :json

      # Chave em resposta autenticada nunca entra em cache compartilhado.
      after do
        header 'Cache-Control', 'private, no-store'
      end

      resource :runtime_config do
        desc 'Configuração de runtime do console (chaves públicas de terceiro).'
        get do
          {
            google_maps: {
              # `nil` quando não há credencial cadastrada. O front precisa distinguir
              # "sem chave" de "chave errada": sem esta diferença o mapa some sem
              # mensagem, que é o defeito do legado (o autocomplete simplesmente não
              # reagia quando o script não carregava).
              api_key: google_maps_key,
              enabled: google_maps_key.present?
            }
          }
        end
      end

      helpers do
        def google_maps_key
          return @google_maps_key if defined?(@google_maps_key)

          @google_maps_key = Credential.by_provider('google_maps').order(created_at: :desc).first&.api_key
          # Escape para ambiente que ainda não tem a credencial cadastrada (a demo sobe
          # antes do cliente informar a chave dele). ENV é o degrau, o banco é o alvo.
          @google_maps_key = ENV['GOOGLE_MAPS_API_KEY'].presence if @google_maps_key.blank?
          @google_maps_key
        end
      end
    end
  end
end
