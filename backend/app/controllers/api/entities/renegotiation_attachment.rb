# frozen_string_literal: true

module Api
  module Entities
    # S9 / BE-225, BE-226 — forma do anexo de renegociação na API.
    #
    # **Não existe campo de URL aqui, e isso é o desenho** — a mesma regra de
    # `Api::Entities::Attachment`. URL de anexo tem prazo (5 min), e prazo embutido
    # numa listagem que fica aberta na tela expira antes de ser usado. O front pede
    # a URL a `GET /api/v1/attachments/:signed_id` no momento de abrir o arquivo,
    # que é também o momento em que a autorização é conferida.
    #
    # É o oposto do legado, onde o caminho do arquivo vinha no HTML e apontava para
    # `public/system/…`: estático, adivinhável, sem autenticação (D-82).
    class RenegotiationAttachment < Grape::Entity
      expose :id
      expose :renegotiation_id
      expose :title, documentation: { desc: 'Nome exibido, EDITÁVEL (DEC-53)' }
      expose :format_label, as: :format, documentation: { desc: 'Extensão real do arquivo ("PDF")' }
      expose :filename
      # rubocop:disable Style/SymbolProc -- ver a nota do `author_id` abaixo
      expose :is_image do |a|
        a.image?
      end
      # rubocop:enable Style/SymbolProc
      expose :byte_size do |a|
        a.file.attached? ? a.file.byte_size : nil
      end
      expose :content_type do |a|
        a.file.attached? ? a.file.content_type : nil
      end
      # `file_id` é o identificador ASSINADO do binário — nunca o id da linha de
      # `active_storage_attachments`, que é sequencial e viraria um contador de
      # quantos anexos existem no sistema.
      expose :file_id do |a|
        a.file.attached? ? Sfg::Attachments.sign_id(a.file.attachment.id) : nil
      end
      # ⚠ **Nada de `&:user_id` aqui — e o RuboCop vai pedir.** `Grape::Entity`
      # chama o bloco com **(objeto, options)**, e um `Symbol#to_proc` repassa o
      # segundo argumento para o método: `a.user_id(options)` levanta
      # `ArgumentError`, que o Grape **engole** no middleware de formatação e
      # transforma em **500 sem stack útil**. Medido, custou quatro exemplos
      # vermelhos (flag F-S9-5 em `upstream-flags.md`).
      # rubocop:disable Style/SymbolProc
      expose :author_id do |a|
        a.user_id
      end
      # rubocop:enable Style/SymbolProc
      expose :author_name do |a|
        a.author&.name
      end
      # A tela esconde a ação de excluir para quem não é o autor (FE-211) — e o
      # servidor recusa de qualquer forma (BE-229). Este campo é a conveniência;
      # a regra é a do servidor.
      expose :can_delete do |a, options|
        a.deletable_by?(options[:current_user])
      end
      expose :created_at
    end
  end
end
