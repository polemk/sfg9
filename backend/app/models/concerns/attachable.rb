# frozen_string_literal: true

# DSL de anexo do Safegold — a **única** forma de um model do Safegold ganhar arquivo.
#
#     class Renegotiation < ApplicationRecord
#       include Attachable
#       sfg_attachment :files
#     end
#
# Isso já traz, sem mais nenhuma linha no model:
#   - `has_many_attached :files` (ou `has_one_attached`, conforme o catálogo);
#   - as variantes nomeadas do legado, com o mesmo tamanho e a mesma qualidade;
#   - validação de **tamanho** e de **quantidade** no servidor;
#   - validação de **tipo pelo conteúdo real** do arquivo (magic bytes, via Marcel) —
#     não pelo `Content-Type` que o cliente declarou;
#   - a política de leitura, que o endpoint de URL assinada consulta.
#
# **Os limites não moram aqui nem no model: moram em `config/attachments.yml`**
# (CFG-02). `sfg_attachment` levanta na carga da classe se a chave não existir lá —
# de propósito, e pelo mesmo motivo do `Auditable`: o caminho para anexar tem de
# passar por um arquivo que a revisão de código lê.
#
# **O que este concern deliberadamente não faz:** não usa o antigo model `Medium`
# (a tabela `media` não tem dono nem escopo — DEC-91) e não grava em
# `public/uploads` (servido sem autenticação — D-82/C-04). Paperclip não é portado:
# nenhuma das 44 colunas `*_file_name`/`*_content_type`/`*_file_size`/`*_updated_at`
# é recriada.
module Attachable
  extend ActiveSupport::Concern

  included do
    class_attribute :sfg_attachment_specs, instance_writer: false, default: {}
  end

  class_methods do
    def sfg_attachment(name)
      spec = Sfg::Attachments.spec_for(Sfg::Attachments.model_key_for(self), name)

      # `class_attribute` com merge (e não `<<`): subclasse não pode mutar a lista
      # da superclasse por acidente.
      self.sfg_attachment_specs = sfg_attachment_specs.merge(name.to_sym => spec)

      variants = spec.variants
      attach_block = lambda do |attachable|
        variants.each do |variant_name, options|
          attachable.variant(variant_name, **Attachable.variant_transformations(options))
        end
      end

      if spec.multiple?
        has_many_attached name, &attach_block
      else
        has_one_attached name, &attach_block
      end

      # ---- validações, todas NO SERVIDOR ----
      # O legado validava 4 arquivos / 5 MB só no JavaScript da tela: bastava o
      # cliente adulterado (ou um `curl`) para o servidor aceitar qualquer coisa.
      validates name,
                content_type: {
                  in: spec.content_types,
                  # `spoofing_protection` é o que faz o `active_storage_validations`
                  # LER os magic bytes (Marcel) em vez de acreditar no
                  # `Content-Type` que o cliente declarou. **Sem esta linha a
                  # validação é decorativa** — conferido: um arquivo de texto puro
                  # enviado como `image/png` passava.
                  spoofing_protection: true,
                  message: 'tem um formato que não é aceito neste campo'
                },
                size: {
                  less_than_or_equal_to: spec.max_size_bytes,
                  message: "O tamanho máximo de cada arquivo permitido para envio é de #{spec.max_size_megabytes} MB"
                }

      if spec.multiple? && spec.max_files.present?
        validates name,
                  limit: {
                    max: spec.max_files,
                    message: "O máximo de arquivos permitido para envio é de #{spec.max_files} arquivos"
                  }
      end
    end
  end

  # Traduz uma linha de variante do catálogo para as opções do `image_processing`.
  #
  # `resize: 80` equivale ao `'80>'` do Paperclip: **só reduz, nunca amplia** — é o
  # que `resize_to_limit` faz. `resize_to_fill`/`resize_to_fit` mudariam o
  # enquadramento dos logos já existentes no cutover.
  #
  # O fundo branco reproduz o `convert_options` do legado
  # (`-alpha remove -background white -flatten`), que existe porque PNG com
  # transparência salvo como JPEG sai com fundo preto.
  #
  # ⚠ **Não use a operação `flatten` para isso.** Foi a primeira tentativa e ela
  # quebra: numa imagem RGB **sem** canal alfa o `vips_flatten` toma a terceira
  # banda como se fosse alfa e estoura com `linear: vector must have 1 or 2
  # elements`. Como a transformação é estática (a chave da variante é derivada
  # dela, então nada de `proc`, que mudaria a chave a cada boot e regeraria a
  # variante para sempre), a decisão "tem alfa?" não pode ser tomada aqui.
  # O `background` no `saver` resolve os dois casos: o `jpegsave` do libvips já
  # achata o alfa quando existe, e ignora a opção quando não existe.
  def self.variant_transformations(options)
    side = options[:resize] || options['resize']
    format = (options[:format] || options['format'] || :jpeg).to_sym
    quality = (options[:quality] || options['quality'] || 80).to_i

    saver = { quality: quality, strip: true }
    saver[:background] = [255, 255, 255] if format == :jpeg

    {
      resize_to_limit: [side, side],
      format: format,
      saver: saver
    }
  end

  # ------------------------------------------------------------------
  # Leitura, do lado do registro
  # ------------------------------------------------------------------
  # Metadados prontos para a entity. Devolve um hash (anexo único) ou um array
  # (múltiplo), sempre com `signed_id` no lugar do id cru.
  def sfg_attachment_payload(name)
    spec = sfg_attachment_specs.fetch(name.to_sym)
    association = public_send(name)

    if spec.multiple?
      Sfg::Attachments.describe_many(association.attachments)
    else
      association.attached? ? Sfg::Attachments.describe(association.attachment) : nil
    end
  end

  # `true` se o usuário pode ler o binário deste anexo. O endpoint de URL assinada
  # é o único chamador em produção; specs de autorização chamam direto.
  def sfg_attachment_readable_by?(name, user)
    Sfg::Attachments.readable?(record: self, name: name, user: user)
  end
end
