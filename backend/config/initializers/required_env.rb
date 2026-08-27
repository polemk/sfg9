# frozen_string_literal: true

# Contrato de configuração: **o boot falha quando falta segredo obrigatório** (OPS-611).
#
# O legado escolheu o oposto — `secret_key_base` de 128 hex commitado em texto puro
# (`config/development_credentials.yml:1`) para que "sempre funcione", e um
# `credentials.yml.enc` sem `master.key`, que é inútil e ninguém percebe porque o Rails
# cai no caminho não cifrado. O resultado é um sistema que sobe em produção com o
# segredo de desenvolvimento e **nada quebra**. Falhar no boot troca um incidente de
# segurança silencioso por um erro de deploy barulhento.
#
# Duas regras que a lista tem de respeitar, e as duas vêm de erro conhecido:
#
# 1. **A lista é por ambiente.** Exigir `SMTP_PASSWORD` em `test` faz a suíte parar de
#    rodar na máquina de quem só quer testar cálculo.
# 2. **A mensagem nomeia TODAS as ausentes de uma vez**, não a primeira. Descobrir as
#    variáveis faltantes uma por deploy é o modo mais caro de ler uma lista.
#
# Escape: `SKIP_ENV_CHECK=true`, para `assets:precompile` e afins em imagem de build
# que ainda não tem os segredos injetados.
module RequiredEnv
  # Vale em todo ambiente que não seja `test`.
  BASE = %w[
    SECRET_KEY_BASE
    DEVISE_JWT_SECRET_KEY
    REDIS_URL
    APP_NAME
  ].freeze

  BY_ENVIRONMENT = {
    'development' => BASE,
    # `test` não exige nada: a suíte de caracterização financeira (contrato C2) tem de
    # rodar sem nenhuma variável de integração externa definida.
    'test' => [].freeze,
    'production' => (BASE + %w[
      CORS_ORIGINS
      APP_HOST
      API_HOST
      ACTION_CABLE_URL
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
    ]).freeze
  }.freeze

  module_function

  def required_for(env = Rails.env.to_s)
    BY_ENVIRONMENT.fetch(env, BASE)
  end

  def missing(env = Rails.env.to_s, source = ENV)
    required_for(env).reject { |name| source[name].to_s.strip.present? }
  end

  def verify!(env = Rails.env.to_s, source = ENV)
    absent = missing(env, source)
    return true if absent.empty?

    raise <<~MSG
      Configuração incompleta para o ambiente `#{env}`.

      Variáveis de ambiente obrigatórias ausentes (#{absent.size}):
      #{absent.map { |name| "  - #{name}" }.join("\n")}

      Os nomes e o formato estão em `backend/.env.example`, que é o único arquivo de
      configuração versionado. Nenhum valor real entra no repositório.

      Se este processo é um build que ainda não tem os segredos injetados, use
      SKIP_ENV_CHECK=true.
    MSG
  end
end

RequiredEnv.verify! unless ENV['SKIP_ENV_CHECK'].to_s == 'true'
