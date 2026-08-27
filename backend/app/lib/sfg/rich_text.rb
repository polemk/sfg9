# frozen_string_literal: true

module Sfg
  # **A única allowlist de rich text do sistema.**
  #
  # Existiam TRÊS caminhos de rich text com três histórias de sanitização
  # diferentes, e isso é pior do que ter uma fraca — porque cria a impressão de
  # que o assunto está resolvido:
  #
  # 1. **Contrato** (S12) sanitizava no servidor, com allowlist, em um lugar só.
  # 2. **Instrução do indicador** (S10) mandava o HTML cru e sanitizava **só no
  #    cliente**, com sanitizador escrito à mão.
  # 3. **Nota de disponibilidade do projeto** (S4) mandava cru e a tela
  #    renderizava com `dangerouslySetInnerHTML`, justificando no comentário que
  #    "o ActionText recusa anexo no servidor". Recusar anexo não é sanitizar.
  #
  # Sanitização no cliente é **defesa em profundidade, nunca a defesa**: quem
  # consome a API não é só a nossa tela. Um relatório, uma exportação, um cliente
  # futuro ou um `curl` recebem o que o servidor mandar. A borda que vale é esta.
  #
  # A **sanitização é na renderização, não na gravação** — o que fica guardado é
  # o que o editor produziu, e a allowlist é aplicada em toda saída. Assim,
  # apertar a allowlist protege o conteúdo que já está no banco, sem migração.
  #
  # Usa o `Rails::HTML5::SafeListSanitizer`, e não um sanitizador nosso: HTML tem
  # mXSS, confusão de namespace (`<svg>`, `<math>`) e reserialização, e uma
  # allowlist escrita à mão erra nesses cantos. Este é mantido por quem
  # acompanha os vetores.
  module RichText
    # Allowlist deliberadamente pequena: é texto de documento, não página. Sem
    # `<script>`, `<style>`, `<iframe>` ou atributo de evento — e sem `<form>`,
    # que aqui só serviria para phishing.
    ALLOWED_TAGS = %w[
      p br div span strong b em i u s
      h1 h2 h3 h4 h5 h6
      ul ol li blockquote pre code hr
      a table thead tbody tr th td
      figure figcaption img
    ].freeze

    ALLOWED_ATTRIBUTES = %w[href title alt src width height colspan rowspan].freeze

    module_function

    def sanitizer
      @sanitizer ||= Rails::HTML5::SafeListSanitizer.new
    end

    # HTML sanitizado, pronto para ir ao cliente. Aceita String ou ActionText.
    def sanitize(html)
      bruto = html.to_s
      return '' if bruto.blank?

      sanitizer.sanitize(bruto, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES).to_s
    end
  end
end
