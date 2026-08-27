# frozen_string_literal: true

# S12 / OPS-331 — **o host das páginas públicas de contrato, validado no boot**.
#
# No legado o link de Termos de Uso e de Política de Privacidade era montado
# concatenando `ENV['alias']` com o tipo em português, cru. A dependência era
# **silenciosa e não documentada em lugar nenhum**: sem a variável, TODOS os
# links de contrato quebram — e quebram no rodapé, no e-mail e no fluxo de
# entrada ao mesmo tempo, sem nenhum erro no servidor.
#
# Aqui é o mesmo contrato do `RequiredEnv` (OPS-611): falta de configuração
# obrigatória **derruba o boot**, com a mensagem dizendo qual variável falta.
# Um erro de deploy barulhento é mais barato que um link morto silencioso.
#
# Segue o padrão `ENV.fetch('API_HOST')` que o antigo `app/models/medium.rb` usava
# — mas o host aqui é o do **front** (`APP_HOST`), porque a página de contrato é
# uma tela React, não um endpoint.
#
# O módulo mora no initializer, e não em `app/`, de propósito: constante de `app/`
# referenciada durante a inicialização é autoload em tempo de boot, que o Zeitwerk
# reprova. É a mesma escolha do `RequiredEnv`.
module PublicHost
  class MissingHost < StandardError; end

  # Caminho da página pública de contrato no front. Uma constante só, porque o
  # back monta o link e o front monta a rota — se as duas divergirem, o link
  # existe e leva a 404.
  CONTRACT_PATH = '/contract'

  module_function

  # `nil` em desenvolvimento e teste: lá o front roda em `localhost:5173` e o
  # link relativo funciona. Em produção é obrigatório.
  def base_url
    valor = ENV['APP_HOST'].to_s.strip
    return valor.chomp('/') if valor.present?
    return nil unless Rails.env.production?

    raise MissingHost, 'APP_HOST não está definido: os links públicos de contrato ficariam quebrados.'
  end

  def verify!
    base_url
    true
  end

  # URL da página pública de um contrato. Usa o **slug** (`termos-de-uso`), não
  # a string literal com espaço e acento que o legado concatenava sem escape —
  # e mesmo assim escapa, porque "o valor é seguro" é o argumento que produziu o
  # D-69.
  def contract_url(kind_or_slug)
    slug = Contract::SLUGS.fetch(kind_or_slug, kind_or_slug.to_s)
    caminho = "#{CONTRACT_PATH}/#{ERB::Util.url_encode(slug)}"
    base = base_url
    base.present? ? "#{base}#{caminho}" : caminho
  end
end

PublicHost.verify! unless ENV['SKIP_ENV_CHECK'].to_s == 'true'
