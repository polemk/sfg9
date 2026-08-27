# Origens permitidas para chamadas cross-origin.
#
# Em producao a lista vem SO da ENV `CORS_ORIGINS` — nada de dominio no codigo.
#
# Em desenvolvimento tambem liberamos qualquer tunel ngrok por EXPRESSAO, e nao
# por dominio fixo: o subdominio efemero muda a cada `ngrok http`, e a versao
# anterior deste arquivo carregava um tunel morto ha semanas. Dominio de tunel
# escrito na mao vira lixo no dia seguinte — e manda o proximo dev caçar CORS
# quando o problema e so o endereco ter mudado.
#
# A expressao vale so em dev de proposito: aceitar `*.ngrok-free.app` com
# `credentials: true` em producao entregaria o cookie de sessao a qualquer um
# capaz de subir um tunel.
DEV_TUNNEL_ORIGINS = %r{\Ahttps://[a-z0-9-]+\.(ngrok-free\.(app|dev)|ngrok\.(app|io))\z}

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    configured = ENV.fetch(
      "CORS_ORIGINS",
      "http://localhost:5173,http://localhost:3000"
    ).split(",").map(&:strip).reject(&:empty?)

    origins(*configured, *(Rails.env.development? ? [DEV_TUNNEL_ORIGINS] : []))

    resource "*",
      headers: :any,
      expose: %w[X-Total-Count Link Content-Disposition],
      methods: %i[get post put patch delete options head],
      credentials: true,
      max_age: 7200
  end
end
