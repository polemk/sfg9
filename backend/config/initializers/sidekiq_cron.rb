# frozen_string_literal: true

# Agendamento de jobs — carga e PORTÃO.
#
# Contexto (upstream-flags.md #13): antes desta fatia o agendamento da base não existia
# em código nenhum. Os 10 crons registrados eram todos `source: dynamic`, cadastrados em
# runtime e persistidos só em chaves `cron_job:*` do Redis. Isso quebra dos dois lados:
# Redis limpo = cron some em silêncio; classe apagada = cron órfão re-enfileirando
# `NameError` para sempre (foram 916 jobs em retry).
#
# Este arquivo faz três coisas, nesta ordem:
#
#   1. **Aponta o caminho absoluto** de `config/schedule.yml`. O default do gem é o
#      caminho RELATIVO `config/schedule.yml`, resolvido contra o CWD do processo — um
#      `sidekiq` iniciado de fora de `backend/` não encontraria o arquivo e não
#      carregaria cron nenhum, sem erro.
#   2. **Reprova o boot** se alguma classe agendada não existir ou se alguma expressão
#      cron for inválida. É o portão que faltava: o `NameError` do cron órfão é
#      silencioso até alguém abrir o log do Sidekiq.
#   3. **Sincroniza o Redis** no startup do servidor Sidekiq, via
#      `Sidekiq::Cron::Job.load_from_hash!`, que remove o que não está declarado.
#
# ⚠ O Redis é COMPARTILHADO com o app `apl9` (`cron_job:apl9:data_cleanup` e um
# `cron_job:default:data_cleanup` que enfileira em `apl9_default`). O `load_from_hash!`
# só destrói jobs com `source == "schedule"`; os do `apl9` são `dynamic` e sobrevivem.
# Nenhuma limpeza aqui pode ser mais larga do que isso — `FLUSHDB` ou `destroy_all`
# derrubam o outro app.

module SidekiqCronSchedule
  SCHEDULE_PATH = Rails.root.join('config', 'schedule.yml').freeze

  module_function

  # Lê e renderiza o ERB do arquivo. Devolve `{}` quando o arquivo não existe.
  def read
    return {} unless File.exist?(SCHEDULE_PATH)

    parsed = YAML.safe_load(ERB.new(File.read(SCHEDULE_PATH)).result, aliases: true) || {}
    raise "config/schedule.yml precisa ser um mapa nome => definição (veio #{parsed.class})" unless parsed.is_a?(Hash)

    parsed
  end

  # PORTÃO. Devolve a lista de problemas; vazia significa schedule sadio.
  def problems(schedule = read)
    schedule.filter_map do |name, definition|
      unless definition.is_a?(Hash)
        next "#{name}: definição precisa ser um mapa com `class` e `cron`"
      end

      klass_name = definition['class'] || definition['klass']
      cron = definition['cron']

      next "#{name}: falta a chave `class`" if klass_name.blank?
      next "#{name}: falta a chave `cron`" if cron.blank?

      # A classe precisa EXISTIR. Este é o defeito que gerou os 916 retries.
      begin
        klass_name.to_s.constantize
      rescue NameError
        next "#{name}: a classe agendada `#{klass_name}` não existe"
      end

      # A expressão precisa ser parseável, senão o job entra no Redis e nunca dispara.
      next "#{name}: expressão cron inválida (#{cron.inspect})" if Fugit.parse_cron(cron).nil?

      nil
    end
  end

  def verify!(schedule = read)
    found = problems(schedule)
    return true if found.empty?

    raise <<~MSG
      Agendamento inválido em config/schedule.yml:
      #{found.map { |p| "  - #{p}" }.join("\n")}

      Cron que aponta para classe inexistente re-enfileira NameError para sempre e não
      aparece em lugar nenhum além do log do Sidekiq. Corrija o arquivo ou remova a
      entrada.
    MSG
  end

  # Remove membros órfãos dos conjuntos `cron_jobs:*` — entradas cujo hash `cron_job:*`
  # já não existe. Sobra do trim do Phase 1b: apagar a definição não tira o nome do
  # conjunto, e o painel do Sidekiq continua contando cron que não existe.
  #
  # Seguro para o `apl9`: só remove membro SEM hash. Job vivo (nosso ou dele) tem hash.
  def prune_dangling_members!
    removed = []
    Sidekiq.redis do |conn|
      cursor = '0'
      loop do
        cursor, keys = conn.call('SCAN', cursor, 'MATCH', 'cron_jobs:*', 'COUNT', 100)
        Array(keys).each do |set_key|
          Array(conn.call('SMEMBERS', set_key)).each do |member|
            next if conn.call('EXISTS', member).to_i.positive?

            conn.call('SREM', set_key, member)
            removed << "#{set_key} -> #{member}"
          end
        end
        break if cursor == '0'
      end
    end
    removed
  end
end

Sidekiq::Cron.configure do |config|
  config.cron_schedule_file = SidekiqCronSchedule::SCHEDULE_PATH.to_s
end

# O portão roda no boot de QUALQUER processo (web, console, worker, rake). Um schedule
# quebrado não chega ao Redis.
Rails.application.config.after_initialize do
  SidekiqCronSchedule.verify!
end

# A sincronização com o Redis é do processo servidor. O próprio gem já registra um
# `on(:startup)` que chama `load_from_hash!(schedule, source: "schedule")` sobre o
# arquivo apontado acima; o hook abaixo só limpa o lixo herdado e deixa rastro no log
# do que ficou agendado — sem ele, "o schedule carregou" é invisível.
Sidekiq.configure_server do |config|
  config.on(:startup) do
    dangling = SidekiqCronSchedule.prune_dangling_members!
    Sidekiq.logger.info { "Cron Jobs - #{dangling.size} membro(s) orfao(s) removido(s): #{dangling.join(', ')}" } if dangling.any?

    declared = SidekiqCronSchedule.read.keys
    Sidekiq.logger.info { "Cron Jobs - schedule versionado: #{declared.join(', ')}" }
  end
end
