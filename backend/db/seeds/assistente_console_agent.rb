# frozen_string_literal: true

# Seed: assistente do console — o ÚNICO agente do ai9 depois do trim.
#
# Bloco 8 do trim (AI9-007). Substitui os cinco seeds de demonstração que
# vendiam a plataforma de captura de lead (`laura_agent.rb`, `laura_flow.json`,
# `maya_flow.json`, `goat_agent.rb`, `data_agent_flow.json`). Aqueles não foram
# "reescritos": estavam com CONFIGURAÇÃO MORTA, não só prosa velha —
# `extract_lead: true` (capability `lead_capture`, removida no Bloco 6) e
# `tools_enabled: true` (capability `assets`, removida no Bloco 7). Nenhuma das
# duas existe mais no `Ai::Tools::ToolRegistry`.
#
# O DEC-13.2 define o uso: **assistente de ajuda ao usuário interno, dentro do
# console. Não captura lead, não faz marketing.** O prompt abaixo diz isso.
#
# Sem `capabilities`: o `ToolRegistry` está vazio de propósito (decisão do Bloco
# 7 — o motor multi-provider de tool calling fica como ponto de extensão). O
# agente responde em texto puro, que é o que um assistente de ajuda precisa.
#
# Idempotente: find_or_initialize_by + assign_attributes.
# Uso:  rails runner db/seeds/assistente_console_agent.rb

puts '[Seed] Assistente do console...'

# Credential resolvida dinamicamente — NUNCA id numérico fixo.
credential = Credential.find_by(id: ENV['ASSISTENTE_CREDENTIAL_ID']) if ENV['ASSISTENTE_CREDENTIAL_ID'].present?
credential ||= Credential.find_by(provider: 'anthropic') || Credential.first

unless credential
  puts '[Seed] AVISO: nenhuma Credential na base. O assistente será salvo sem credential_id ' \
       '(responde "Agente não configurado" até alguém cadastrar uma em /admin/credentials).'
end

ASSISTENTE_CONSOLE_SYSTEM_PROMPT = <<~PROMPT.strip
  Você é o assistente de ajuda do console. Quem fala com você é um usuário
  INTERNO, já autenticado, trabalhando dentro do sistema.

  === O QUE VOCÊ FAZ ===
  - Explica o que cada tela do console faz e como usá-la.
  - Ajuda a entender um campo, um estado ou uma mensagem de erro que apareceu.
  - Diz onde encontrar uma funcionalidade no menu.
  - Quando não souber, diz que não sabe e sugere quem procurar. Não inventa
    tela, botão nem caminho que você não tem certeza que existe.

  === O QUE VOCÊ NÃO FAZ ===
  - Não vende nada. Não fala de plano, preço, contratação, demonstração ou
    upgrade — não existe nada disso aqui.
  - Não pede nome, e-mail nem telefone. Você já está falando com alguém
    identificado; pedir cadastro é comportamento de captura de lead, e captura
    de lead não faz parte deste sistema.
  - Não agenda reunião nem consulta agenda.
  - Não dá orientação de decisão de crédito, jurídica ou financeira. Se a
    pergunta for dessa natureza, diga que a decisão é de quem tem alçada.

  === COMO VOCÊ ESCREVE ===
  - Português do Brasil, direto, sem saudação longa e sem emoji.
  - Uma ideia por parágrafo, separados por linha em branco: cada parágrafo vira
    uma mensagem na sequência do widget.
  - Resposta curta por padrão. Detalhe só o que foi perguntado.
  - Não termine perguntando "quer que eu detalhe?". Se faltar UMA informação
    sem a qual você não consegue responder, faça UMA pergunta.

  === CONTEXTO AUTOMÁTICO ===
  O sistema injeta a data/hora atual e a rota em que o usuário está. Use isso
  para responder sobre a tela em que ele já se encontra, sem perguntar onde ele
  está.
PROMPT

flow = ChatFlow.find_or_initialize_by(name: 'assistente-console')
flow.assign_attributes(
  kind: :ai_agent,
  published: true,
  is_default: true,
  persona_name: 'Assistente',
  persona_avatar: '/maya-avatar.svg',
  persona_description: 'Ajuda com o console',
  keywords: %w[ajuda help duvida duvidas como assistente],
  mapped_routes: [],
  override_active_chat: false,
  definition: { 'nodes' => [], 'edges' => [] },
  credential_id: credential&.id,
  agent_config: {
    credential_id: credential&.id,
    # Conferido contra `GET /v1/models`: `claude-3-5-sonnet-20241022` (o que
    # todos os seeds antigos usavam) responde 404 na API hoje.
    model: 'claude-opus-5',
    system_prompt: ASSISTENTE_CONSOLE_SYSTEM_PROMPT,
    welcome_message: 'Oi! Sou o assistente do console. Em que tela você está e o que precisa entender?',
    # Sem `temperature`: a família 5 rejeita amostragem com 400 (o provider
    # já filtra, mas gravar aqui um valor que nunca será enviado engana quem ler).
    max_tokens: 1024
    # Sem `capabilities`: o ToolRegistry está vazio (Blocos 6 e 7). O motor de
    # tool calling continua de pé como ponto de extensão — ver tool_registry.rb.
  }
)
flow.save!

puts "[Seed] OK: #{flow.name} (id #{flow.id}, default: #{flow.is_default}, credential: #{credential&.id || 'nenhuma'})"
