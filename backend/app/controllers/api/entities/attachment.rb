# frozen_string_literal: true

module Api
  module Entities
    # Forma única de um anexo do Safegold na API.
    #
    # **`id` é o `signed_id`, nunca o id da linha de `active_storage_attachments`.**
    # Duas razões: o id cru é sequencial e transforma a resposta num contador de
    # quantos anexos existem no sistema; e o `signed_id` é o que o endpoint de
    # leitura aceita, então não há como o front montar uma URL "na mão".
    #
    # **Não existe campo de URL aqui, e isso é o desenho.** URL de anexo tem prazo,
    # e prazo embutido numa listagem que fica aberta na tela expira antes de ser
    # usada. O front pede a URL a `GET /api/v1/attachments/:id` no momento de abrir
    # o arquivo — que é também o momento em que a autorização é conferida.
    class Attachment < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'Identificador assinado do anexo' }
      expose :filename, documentation: { type: 'String', desc: 'Nome original do arquivo' }
      expose :content_type, documentation: { type: 'String', desc: 'Tipo de conteúdo real (magic bytes)' }
      expose :byte_size, documentation: { type: 'Integer', desc: 'Tamanho em bytes' }
      expose :created_at, documentation: { type: 'DateTime', desc: 'Data do envio' }
    end
  end
end
