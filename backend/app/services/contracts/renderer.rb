# frozen_string_literal: true

module Contracts
  # S12 / BE-345, FE-331 — **o único lugar que transforma ActionText em HTML**
  # para contratos e para a ajuda.
  #
  # Existe por um motivo específico: no legado a mesma versão de contrato era
  # renderizada de **duas** formas diferentes. O console mostrava o rich text; a
  # página pública fazia `CGI.unescape(...to_plain_text).html_safe` e perdia
  # título, lista e negrito. A tela com valor jurídico era a menos fiel das
  # duas. Com um renderizador só, "as duas telas mostram o mesmo texto" deixa de
  # ser combinado e passa a ser estrutural.
  #
  # A **sanitização é na renderização, não na gravação**: o que fica guardado é
  # o que o editor produziu, e a allowlist é aplicada em toda saída.
  module Renderer
    # A allowlist mora em `Sfg::RichText`, não aqui. Ela nasceu neste arquivo e
    # foi promovida quando apareceu o TERCEIRO caminho de rich text do sistema
    # com a terceira história de sanitização. Os apelidos abaixo continuam
    # porque há consumidor deles.
    ALLOWED_TAGS = Sfg::RichText::ALLOWED_TAGS
    ALLOWED_ATTRIBUTES = Sfg::RichText::ALLOWED_ATTRIBUTES

    module_function

    # HTML sanitizado, pronto para ir ao cliente.
    def html(rich_text)
      bruto = raw_html(rich_text)
      return '' if bruto.blank?

      Sfg::RichText.sanitize(bruto)
    end

    # Texto puro — usado pela validação de corpo vazio e pelo resumo da busca.
    def text(rich_text)
      return '' if rich_text.blank?

      bruto = raw_html(rich_text)
      return '' if bruto.blank?

      Nokogiri::HTML.fragment(bruto).text.gsub(/[[:space:]]+/, ' ').strip
    end

    # SHA-256 do texto **normalizado**. Normalizar antes de somar é o que impede
    # que reindentar o HTML no editor pareça, para a prova de aceite, uma
    # mudança de conteúdo.
    def digest(rich_text)
      Digest::SHA256.hexdigest(text(rich_text))
    end

    def raw_html(rich_text)
      return '' if rich_text.nil?
      return rich_text.to_s if rich_text.is_a?(String)

      corpo = rich_text.respond_to?(:body) ? rich_text.body : nil
      return '' if corpo.nil?

      corpo.to_html.to_s
    end
  end
end
