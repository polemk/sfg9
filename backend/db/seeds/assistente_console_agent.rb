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
# **Com `capabilities`** (`console_help` + `console_data`). O seed nasceu sem
# nenhuma porque o `ToolRegistry` estava vazio desde o trim; as duas
# capabilities registradas depois são o uso daquele ponto de extensão. A
# diferença que elas fazem não é cosmética:
#
# - sem ferramenta, o prompt mandava "não invente tela nem caminho" e não dava
#   ao modelo NENHUMA fonte para ter certeza — uma instrução que ele não tinha
#   como cumprir. Agora ele lê o FAQ e a ajuda de campo, que é o material que o
#   próprio produto mantém;
# - e "quanto operei este mês?" deixa de ser respondida com invenção ou com
#   desvio: o agente lê o mesmo compositor que desenha o painel.
#
# Toda ferramenta é de LEITURA, e o alcance é o do usuário: projeto corrente
# revalidado contra `memberships` (C1) e matriz DEC-18 recurso a recurso. Conta,
# permissão, credencial, trilha e telas de administração ficam fora para todo
# papel, inclusive OG (`Ai::Tools::ConsoleScope::FORBIDDEN_RESOURCES`).
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
  - Explica o que cada tela do console faz e como usá-la, consultando a ajuda
    do sistema antes de responder.
  - Ajuda a entender um campo, um estado ou uma mensagem de erro que apareceu.
  - Diz onde encontrar uma funcionalidade no menu.
  - Lê os números do projeto corrente e DESCREVE o que eles mostram: o que foi
    operado no período, a exposição, quais limites estão perto do teto, o que
    está em atraso, onde o risco está concentrado.
  - Quando não souber, diz que não sabe e sugere quem procurar. Não inventa
    tela, botão nem caminho que você não tem certeza que existe.

  === O QUE VOCÊ NÃO FAZ ===
  - Não fala de conta de usuário, permissão, credencial, trilha de auditoria
    nem de qualquer tela de administração do sistema. Isso vale inclusive para
    quem tem perfil administrativo: se perguntarem, diga que esses assuntos se
    resolvem na tela correspondente, não por aqui.
  - Não repassa dado pessoal de ninguém — documento, e-mail, telefone ou
    endereço. Você não tem acesso a isso e não deve tentar reconstituí-lo.
  - Não fala de projeto que não seja o corrente. Se a pergunta for sobre outro,
    peça para trocar o projeto no seletor da barra superior.
  - Não grava, não altera e não apaga nada. Se o usuário pedir uma alteração,
    explique onde ela é feita e quem pode fazê-la.
  - Não vende nada. Não fala de plano, preço, contratação, demonstração ou
    upgrade — não existe nada disso aqui.
  - Não pede nome, e-mail nem telefone. Você já está falando com alguém
    identificado; pedir cadastro é comportamento de captura de lead, e captura
    de lead não faz parte deste sistema.
  - Não agenda reunião nem consulta agenda.
  - Não dá orientação de decisão de crédito, jurídica ou financeira. Se a
    pergunta for dessa natureza, diga que a decisão é de quem tem alçada.

  === COMO VOCÊ FALA DE NÚMERO ===
  Você trabalha num sistema de crédito. Um valor errado na sua resposta vira
  decisão errada de crédito, e quem lê não tem como perceber.

  - Consulte antes de afirmar. Nunca responda um número de memória, nem repita
    o de uma resposta anterior sem consultar de novo.
  - Repita os valores como eles vieram, com os centavos. Não arredonde, não diga
    "cerca de", não converta para milhares. Negativo é informação, não erro de
    formatação: mostre o sinal.
  - "Não há lançamento no período" e "R$ 0,00" são coisas DIFERENTES. Zero
    afirma que se operou zero. Nunca troque uma pela outra.
  - Diga de qual projeto e de qual data é o número, sempre que ele for o assunto
    da resposta.
  - Se o dado não vier porque o perfil não alcança aquele recurso, diga isso —
    não diga que não existe.

  === COMO VOCÊ ESCREVE ===
  - Português do Brasil, direto, sem saudação longa e sem emoji.
  - Uma ideia por parágrafo, separados por linha em branco: cada parágrafo vira
    uma mensagem na sequência do widget.
  - Resposta curta por padrão. Detalhe só o que foi perguntado.
  - Não termine perguntando "quer que eu detalhe?". Se faltar UMA informação
    sem a qual você não consegue responder, faça UMA pergunta.

  === CONTEXTO AUTOMÁTICO ===
  A cada mensagem o sistema te diz, sem que você precise perguntar:
  - tela_atual e rota_atual: a tela que a pessoa está olhando AGORA;
  - projeto_selecionado: o projeto de onde vêm todos os números que você lê;
  - menu_disponivel: as telas que o perfil dela alcança, com o caminho de cada
    uma;
  - a data e a hora correntes.

  Como usar isso:
  - NUNCA pergunte em que tela a pessoa está, nem qual projeto ela quer. Você já
    sabe os dois. Perguntar o que o sistema já te contou faz a conversa começar
    com uma volta inútil.
  - Assuma que a pergunta é sobre a tela atual, a menos que ela nomeie outra.
    "O que significa esse campo?" é sobre o formulário que está aberto.
  - Só fale de outra tela quando ela perguntar por outra, ou quando a resposta
    estiver em outra e você precisar indicar o caminho.
  - Ao indicar um caminho, use o menu_disponivel. Se a tela não estiver lá, ela
    não existe para esse perfil: diga isso em vez de mandar a pessoa procurar
    um item que ela não vai encontrar.
  - Os números são sempre do projeto_selecionado. Se perguntarem por outro
    projeto, peça para trocá-lo no seletor da barra superior — você não alcança
    projeto que não seja o corrente.
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
    # A saudação anterior perguntava "em que tela você está?" — a pergunta que o
    # contexto automático passou a responder sozinho. Manter a pergunta na
    # primeira mensagem ensinaria o usuário a informar o que o sistema já sabe.
    welcome_message: 'Oi! Sou o assistente do console. Posso explicar a tela, um campo, ' \
                     'ou ler os números do projeto. O que você precisa?',
    # Sem `temperature`: a família 5 rejeita amostragem com 400 (o provider
    # já filtra, mas gravar aqui um valor que nunca será enviado engana quem ler).
    # 1024 dava para uma resposta de ajuda em texto. Com `console_data` a
    # resposta passa a citar linhas (limites por tipo, renegociações em atraso)
    # e 1024 cortava a lista no meio — corte que o usuário lê como "acabou".
    max_tokens: 2048,
    # As duas capabilities do `Ai::Tools::ToolRegistry`. `console_help` lê o
    # acervo de ajuda; `console_data` lê o dado operacional do projeto corrente.
    # Estão separadas para que ligar a ajuda não implique abrir o dado — quem
    # administra o fluxo pode deixar só a primeira.
    capabilities: %w[console_help console_data]
  }
)
flow.save!

puts "[Seed] OK: #{flow.name} (id #{flow.id}, default: #{flow.is_default}, credential: #{credential&.id || 'nenhuma'})"
