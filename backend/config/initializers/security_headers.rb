# frozen_string_literal: true

# Cabeçalhos de segurança do backend — CSP **bloqueante** (DEC-48) e o resto do
# conjunto que não existia nem no legado nem na base ai9 (OPS-628).
#
# Divisão de trabalho, porque ela não é óbvia:
#
# * O **console** é um SPA servido pelo Vite/host estático. O CSP dele viaja como
#   `<meta http-equiv>` no `index.html`, montado em `frontend/csp.config.ts` a partir
#   do que a aplicação realmente carrega. Um header emitido por este backend
#   `api_only` só alcançaria as respostas JSON, que não carregam recurso nenhum —
#   colocar o CSP do console aqui seria uma política que nunca chega ao documento.
# * O que este arquivo protege são as respostas **do próprio backend**: o JSON da API,
#   os redirects do ActiveStorage, as páginas de erro e a doc da API em `/docs`.
#
# Por que um middleware e não `config.action_dispatch.default_headers`: `/docs` é a
# única resposta HTML do backend e ela carrega o Stoplight Elements do `unpkg.com`
# (`app/views/docs/elements.html.erb:6-7`). Com uma política global de
# `default-src 'none'` a doc da API fica em branco — e branco em silêncio, que é
# exatamente o modo de falha que o DEC-48 assume. A exceção fica isolada aqui, escrita,
# em vez de afrouxar a política de toda a API.
#
# Nome achatado de propósito: `Sfg::Coercion` e `Sfg::DateBounds` moram em
# `app/lib/sfg/`, sob o Zeitwerk. Abrir o mesmo namespace `Sfg` num initializer, que
# roda antes do autoload, é o jeito conhecido de brigar com o recarregamento.
class SfgSecurityHeaders
  # JSON não carrega nada. `'none'` em tudo é a política correta e a mais barata de
  # manter: qualquer coisa que o backend passe a servir aparece como violação.
  API_POLICY = [
    "default-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'"
  ].join('; ').freeze

  # `/docs` — Stoplight Elements vem do unpkg (CSS, JS, fontes) e desenha em
  # `data:`/`blob:`.
  DOCS_POLICY = [
    "default-src 'self'",
    "base-uri 'self'",
    "object-src 'none'",
    "frame-ancestors 'none'",
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://unpkg.com",
    "style-src 'self' 'unsafe-inline' https://unpkg.com",
    "font-src 'self' data: https://unpkg.com",
    "img-src 'self' data: blob: https://unpkg.com",
    "connect-src 'self'"
  ].join('; ').freeze

  STATIC_HEADERS = {
    'X-Content-Type-Options' => 'nosniff',
    'X-Frame-Options' => 'DENY',
    'Referrer-Policy' => 'strict-origin-when-cross-origin',
    'X-Permitted-Cross-Domain-Policies' => 'none',
    # Nenhum endpoint desta API usa câmera, microfone, geolocalização ou pagamento.
    # O mapa (DEC-61) roda no front, não aqui.
    'Permissions-Policy' => 'accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()'
  }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)

    STATIC_HEADERS.each { |name, value| headers[name] ||= value }
    headers['Content-Security-Policy'] ||= policy_for(env['PATH_INFO'].to_s)

    [status, headers, body]
  end

  private

  def policy_for(path)
    path.start_with?('/docs') ? DOCS_POLICY : API_POLICY
  end
end

# Antes de tudo que possa responder — inclusive do Rack::Attack, para que uma resposta
# de bloqueio também saia com os cabeçalhos.
Rails.application.config.middleware.insert_before 0, SfgSecurityHeaders
