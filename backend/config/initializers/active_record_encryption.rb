# Active Record Encryption Configuration
# Required for encrypted fields (like Credential.api_key)
#
# ⚠ As três chaves abaixo vinham COMMITADAS como default (`qnpYZCIR…`, `L8lsBAd4…`,
# `cetdP8FH…`). Chave de cifra versionada é cifra decorativa: quem tem o repositório
# decifra o banco. Isso ganhou peso com o **DEC-61**, que manda as chaves de terceiro
# (ReceitaWS, Google Maps) para o model `Credential`, cujo `api_key` é protegido
# exatamente por elas.
#
# O default sobrevive só em desenvolvimento e teste, e apenas para não quebrar o
# ambiente de quem já roda — trocá-lo torna ilegível o que já está gravado no banco
# local. Em produção não há default: `RequiredEnv` (config/initializers/required_env.rb)
# reprova o boot se as três não vierem do ambiente, e o `fetch` sem default abaixo é a
# segunda trava, caso alguém remova a checagem.
#
# Gerar um jogo novo: `bin/rails db:encryption:init`.
dev_only_defaults = {
  'ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY' => 'qnpYZCIR4dzYmCcOhlwgqZZArtqlS8ME',
  'ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY' => 'L8lsBAd4I9go5DN5tUvbwL00DlPQ0sCT',
  'ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT' => 'cetdP8FHqFZyhJt8nGYR6gGYxIbTro0r'
}.freeze

fetch_key = lambda do |name|
  next ENV.fetch(name) if Rails.env.production?

  ENV.fetch(name) { dev_only_defaults.fetch(name) }
end

Rails.application.configure do
  config.active_record.encryption.primary_key = fetch_key.call('ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY')
  config.active_record.encryption.deterministic_key = fetch_key.call('ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY')
  config.active_record.encryption.key_derivation_salt = fetch_key.call('ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT')
end
