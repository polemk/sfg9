# frozen_string_literal: true

if ENV['LOAD_PROD_STARTPOINT'] == 'true'
  puts "==========================================================================="
  puts "⚠️ ATENÇÃO: IGNORANDO SEEDS PADRÃO E EXECUTANDO PRODUCTION STARTPOINT"
  puts "==========================================================================="
  startpoint_path = Rails.root.join('db', 'seeds', 'production_startpoint.rb')
  if File.exist?(startpoint_path)
    load startpoint_path
  else
    puts "❌ Startpoint não encontrado em #{startpoint_path}! Execute 'rake export:startpoint' no ambiente local antes."
  end
  # Encerra o seeds.rb atual para não rodar os seeds de dev em cima disso
  return
end

# ==========================================
# CONFIGURAÇÃO GERAL DO SEED
# ==========================================
# Defina as variáveis abaixo como true ou false para controlar 
# quais partes do seed serão executadas.
#
# true  => Executa o trecho
# false => Pula o trecho
# ==========================================

should_perform_users              = true  # Criação de usuários (Admin, Cliente Teste, Tipos)
should_perform_client_application = true  # Criação de Client Applications (Frontend)
should_perform_instance_whats     = true  # Configuração da instância WhatsApp na Evolution API
# Bloco 6 do trim (AI9-006): as flags `should_perform_leads_operations` /
# `should_perform_lead_messages` e os filtros `leads_only` / `leads_skip` saíram
# junto com os leads de demonstração.
# Bloco 7 do trim (AI9-014): a flag `should_perform_operations` e o bloco que
# criava as 5 `Operation` de demonstração saíram com o `Operation`.

if should_perform_instance_whats
  if Rails.env.production?
    params = {
      instanceName: 'AI9_WHATS',
      integration: 'WHATSAPP-BAILEYS',
      qrcode: true
    }
  else
    raw_tag = ENV['USER'] || ENV['USERNAME'] || Socket.gethostname
    user_tag = I18n.transliterate(raw_tag).gsub(/[\s\-.]+/, '_').gsub(/[^a-zA-Z0-9_]/, '').upcase
    params = {
      instanceName: "AI9_#{user_tag}",
      integration: 'WHATSAPP-BAILEYS',
      qrcode: true
    }
  end

  begin
    # Tenta buscar na Evolution API
    params_result = { instance_name: params[:instanceName] }
    result_exists = EvolutionConnection.list_instances(params_result)

    puts '✅ Instância encontrada na Evolution API.'

    instance_data = result_exists[:response].first

    polemk_instance = PolemkInstance.find_or_initialize_by(instance_name: instance_data['name'])

    polemk_instance.assign_attributes(
      display_name: 'AI9',
      instance_name: instance_data['name'],
      instance_id: instance_data['id'],
      integration: instance_data['integration'],
      is_qrcode: params[:qrcode],
      api_key: instance_data['token'],
      raw_response: instance_data
    )
    polemk_instance.save!
    puts '✅ Instância recuperada e salva no banco!'
    puts '🔎 procurando webhooks...'
    result_webhook = EvolutionConnection.list_webhooks
    if result_webhook[:response].present?
      events = %w[SEND_MESSAGE MESSAGES_UPSERT MESSAGES_UPDATE]
      events.each do |event|
        full_url = "#{result_webhook[:response]['url']}/#{event.downcase.tr('_', '-')}"
        webhook = polemk_instance.polemk_webhooks.find_or_initialize_by(event: event)
        webhook.update(
          url: full_url,
          enabled: true,
          webhook_by_events: true,
          webhook_base_64: true,
          raw_response: result_webhook[:response]
        )
      end

      puts '✅ Webhooks da Instância criados no banco!'
    else
      puts '🔎 sem webhook configurado na instancia...'
    end
  rescue EvolutionConnection::InvalidResponseError => e
    if e.status == 404
      puts '🔎 Instância não encontrada na Evolution API, criando nova...'

      begin
        result_create = EvolutionConnection.create_instance(params)
        response = result_create[:response]
        instance_data = response['instance']

        polemk_instance = PolemkInstance.find_or_initialize_by(instance_name: instance_data['instanceName'])

        polemk_instance.assign_attributes(
          display_name: 'AI9',
          instance_name: instance_data['instanceName'],
          instance_id: instance_data['instanceId'],
          integration: instance_data['integration'],
          is_qrcode: params[:qrcode],
          api_key: response['hash'].is_a?(Hash) ? response['hash']['apikey'] : response['hash'],
          raw_response: response
        )
        polemk_instance.save!
        puts '✅ Instância criada e salva no banco!'
      rescue StandardError => e
        puts "🧨 Erro inesperado ao criar: #{e.class} - #{e.message}"
      end

    else
      puts "❌ Falha na comunicação com Evolution API: #{e.error} (#{e.status})"
      puts "Detalhes: #{e.details}"
    end
  rescue EvolutionConnection::TimeoutError, EvolutionConnection::ConnectionError => e
    puts "🚨 Erro de comunicação com a Evolution API: #{e.message}"
  rescue StandardError => e
    puts "🧨 Erro inesperado: #{e.class} - #{e.message}"
  end
end


if should_perform_users
  # Seeds de REFERÊNCIA (idempotentes) — OPS-540.
  #
  # Eram dois `load` de caminho fixo, e cada fatia nova acrescentaria o seu até
  # o deploy ter cinco formas de semear. Agora o carregador é UM
  # (`Seeds::Reference::Runner`) e a lista de catálogos é dado. Quem entrega um
  # catálogo novo (S5, S6, S8, S17) acrescenta uma linha lá, não um `load` aqui.
  #
  # O mesmo caminho é o do deploy: `rake reference:seed`.
  load Rails.root.join('db/seeds/reference/index.rb')

  # Criar usuário admin OG
  puts '👤 Criando usuário admin OG...'
  og_type = UserType.og || (UserType.seed_default_types!
                            UserType.og)
  raise 'Tipo de usuário OG ausente' if og_type.nil?

  admin_user = User.find_or_initialize_by(email: 'vinaoxd@gmail.com')
  admin_user.assign_attributes(
    name: 'Vini',
    phone: '5548988051484',
    user_type: og_type,
    provider: nil,
    provider_uid: nil
  )
  begin
    admin_user.save!
  rescue ActiveRecord::RecordInvalid => e
    puts "⚠️ Falha ao criar admin: #{e.message}"
  end
  puts "✅ Usuário admin criado: #{admin_user.email}"

  admin_user2 = User.find_or_initialize_by(email: 'gui@polemk.com')
  admin_user2.assign_attributes(
    name: 'Gui',
    phone: '5549999350244',
    user_type: og_type,
    provider: nil,
    provider_uid: nil
  )
  begin
    admin_user2.save!
  rescue ActiveRecord::RecordInvalid => e
    puts "⚠️ Falha ao criar admin: #{e.message}"
  end
  puts "✅ Usuário admin criado: #{admin_user2.email}"

  admin_user3 = User.find_or_initialize_by(email: 'felippesilas@gmail.com')
  admin_user3.assign_attributes(
    name: 'Silas',
    phone: '5549998318862',
    user_type: og_type,
    provider: nil,
    provider_uid: nil
  )
  begin
    admin_user3.save!
  rescue ActiveRecord::RecordInvalid => e
    puts "⚠️ Falha ao criar admin: #{e.message}"
  end

  admin_user4 = User.find_or_initialize_by(email: 'leonidasmarquesdev@gmail.com')
  admin_user4.assign_attributes(
    name: 'Leonidas',
    phone: '5586999397255',
    user_type: og_type,
    provider: nil,
    provider_uid: nil
  )
  begin
    admin_user4.save!
  rescue ActiveRecord::RecordInvalid => e
    puts "⚠️ Falha ao criar admin: #{e.message}"
  end
  puts "✅ Usuário admin criado: #{admin_user4.email}"

  # --------------------------------------------------------------------------
  # Usuário alvo de impersonação
  # --------------------------------------------------------------------------
  # O comentário da flag `should_perform_users` já prometia "Cliente Teste", mas
  # o bloco só criava OGs — então não havia ninguém para o OG impersonar, e o
  # seletor "VENDO COMO" da sidebar abria sempre vazio.
  #
  # DEC-41 removeu `client`/`free`/`visitor`: o usuário comum do Safegold é o
  # **Colaborador** (nível 4). Continua servindo de alvo de impersonação —
  # `Auth::ImpersonateService.start` exige `can_impersonate?` só de QUEM
  # impersona, e o Colaborador é hierarquia inferior ao OG, que é o que a
  # DEC-18.3 pede.
  #
  # O e-mail é um plus-address do OG de propósito: em desenvolvimento
  # `raise_delivery_errors` está ligado (`config/environments/development.rb:44`),
  # então um domínio inexistente faria o `request_code` estourar 500 e este
  # usuário não conseguiria nem logar direto para comparar com a impersonação.
  puts '👤 Criando usuário alvo de impersonação...'
  client_type = UserType.colaborador
  if client_type.nil?
    puts '⚠️ Tipo `colaborador` ausente — impersonação não terá alvo'
  else
    target_user = User.find_or_initialize_by(email: 'vinaoxd+cliente@gmail.com')
    target_user.assign_attributes(
      name: 'Cliente Teste',
      phone: '5548988059001',
      user_type: client_type,
      provider: nil,
      provider_uid: nil
    )
    begin
      target_user.save!
      puts "✅ Alvo de impersonação criado: #{target_user.email} (#{client_type.name})"
    rescue ActiveRecord::RecordInvalid => e
      puts "⚠️ Falha ao criar alvo de impersonação: #{e.message}"
    end
  end
end

if should_perform_client_application
  # Client Applications padrão
  puts '🔐 Criando Client Applications...'
  begin
    default_apps = [
      { name: 'FRONTEND_PUBLIC', token: SecureRandom.hex(32) }
    ]

    default_apps.each do |app|
      ClientApplication.find_or_create_by!(name: app[:name]) do |record|
        record.token = app[:token]
        record.active = true
      end
    end
    puts '✅ Client Applications criados/atualizados'
  rescue StandardError => e
    puts "❌ Erro ao criar Client Applications: #{e.message}"
  end
end

# ==========================
# Assistente do console (AI9-007 - o unico agente que sobrou)
# ==========================
#
# Bloco 8 do trim: aqui viviam tres blocos de seed de demonstracao - a Maya
# ("guia interativa do site", `is_default`), a Laura ("especialista em solucoes",
# agente + flow de fallback) e o Data Agent ("rastreamento/pixel/UTM"). Os tres
# vendiam a plataforma de captura de lead: falavam de plano, preco, demo,
# comment-to-DM do Instagram e CRM - features removidas nos Blocos 1 a 7.
#
# Nao era so prosa velha: os seeds de AGENTE traziam `extract_lead: true`
# (capability `lead_capture`, removida no Bloco 6) e `tools_enabled: true`
# (capability `assets`, removida no Bloco 7). Nenhuma das duas existe mais no
# `Ai::Tools::ToolRegistry` - era configuracao morta, nao texto desatualizado.
#
# O DEC-13.2 define o uso do que ficou: assistente de ajuda ao usuario INTERNO,
# dentro do console. Um agente so, e o prompt dele diz isso.
should_perform_assistente_console = true

if should_perform_assistente_console
  puts 'Criando assistente do console...'

  begin
    load Rails.root.join('db', 'seeds', 'assistente_console_agent.rb')
  rescue StandardError => e
    puts "Erro ao criar o assistente do console: #{e.class} - #{e.message}"
  end
end

# Bloco 6 do trim (AI9-006): `db/seeds/goat_canais.rb` foi apagado — populava a
# tabela `canais`, que saiu com a feature.

