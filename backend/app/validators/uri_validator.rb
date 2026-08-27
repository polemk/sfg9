# frozen_string_literal: true

# Formato de URL `http(s)` — `BE-456`.
#
#     validates :webhook_url, uri: true
#     validates :site, uri: { allow_blank: true, schemes: %w[https] }
#
# **A verificação de disponibilidade NÃO é portada, e isso é decisão (D6).**
# O original (`sfg/app/validators/uri_validator.rb`) faz
# `Net::HTTP.get_response(URI.parse(value))` **dentro do `validate`**. Três
# consequências, e nenhuma é teórica:
#
#  - salvar um registro vira chamada de rede, **dentro da transação**, com
#    timeout padrão do `Net::HTTP` — que é indefinido para conexão;
#  - um endereço válido é **recusado** porque o site estava fora do ar naquele
#    segundo. O dado do usuário passa a depender do uptime de terceiro;
#  - o `rescue` sem classe engole tudo, inclusive `Interrupt`, e transforma
#    qualquer falha de DNS em "URL inválida" — a mensagem não diz o que houve.
#
# Se disponibilidade virar requisito, ela é verificação **assíncrona** com
# resultado gravado, nunca uma condição de salvar.
#
# Detalhe menor, também corrigido: o original usa
# `I18n.t('errors.events.invalid_url')`, chave que **não existe** em nenhum dos
# 6 arquivos de locale do legado — a mensagem sairia como "translation missing".
#
# Como o `IntervalValidator`, este validador **não tem consumidor no legado**:
# nenhum model declara `uri: true`. Vem porque URL de integração é campo que
# nasce em S13, e ter uma validação só evita a segunda.
class UriValidator < ActiveModel::EachValidator
  DEFAULT_SCHEMES = %w[http https].freeze

  def validate_each(record, attribute, value)
    return if value.blank? && options[:allow_blank]

    unless valid_uri?(value)
      record.errors.add(attribute, :invalid_url, message: options[:message] || 'não é uma URL http(s) válida')
    end
  end

  private

  def schemes
    Array(options[:schemes]).presence || DEFAULT_SCHEMES
  end

  def valid_uri?(value)
    return false if value.blank?
    # `URI.parse` aceita espaço em branco em algumas formas; um endereço com
    # espaço é sempre erro de digitação.
    return false if value.to_s.match?(/\s/)

    uri = URI.parse(value.to_s)
    schemes.include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
end
