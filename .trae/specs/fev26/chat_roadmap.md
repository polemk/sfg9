Roadmap V2: Advanced Flow Builder & Integrations
Version: 2.0 Last Updated: February 2026 Focus: Flow Connections, Rich Media, Integrations (Leads/OCR), and Commerce.

📅 Sprint 1: Flow Connections & Logic
Focus: enabling complex, multi-flow architectures and user redirection.

Tarefa 1.1: End Node - Flow Handoff (Conexão entre Fluxos)
Estimativa: 1.5 dias Tipo: Backend + Frontend

Contexto
Atualmente, os fluxos são isolados. Para criar experiências complexas e modulares (ex: um fluxo de "Onboarding" que leva a um de "Suporte"), precisamos conectar um fluxo ao outro. Isso permite reutilizar lógica e manter o visual do builder limpo. O "Handoff Node" serve como um "teletransporte": quando o usuário chega nele, o motor troca o fluxo ativo e começa o novo fluxo imediatamente.

Onde começa
O 
FlowEngine
 processa nós sequencialmente dentro do mesmo flow_id.
Não existe conceito de "trocar de fluxo" via nó.
Onde termina
Builder tem um nó "Jump to Flow".
Widget transita suavemente para o novo fluxo sem que o usuário perceba a troca técnica (mantendo histórico visual quando possível).
Importante: Atualizar o visual do bot (Avatar/Nome) para o novo fluxo imediatamente.
O que precisa ser feito
Backend:

Criar Ai::Nodes::Handoff com propriedade target_flow_id.
Atualizar Ai::FlowEngine: ao encontrar handoff, atualizar ChatSession.chat_flow_id e resetar current_step_id.
Manter session.context (variáveis) para não perder dados do usuário.
Frontend:

Criar componente HandoffNode no Builder com dropdown para selecionar fluxos existentes.
Critérios de aceite
Criar Fluxo A e Fluxo B.
Adicionar Handoff no final do Fluxo A apontando para B.
Ao testar, finalizar A e ver a primeira mensagem de B aparecer automaticamente.
Verificar que variáveis capturadas em A estão disponíveis em B.
Tarefa 1.2: End Node - Redirect & Account Creation
Estimativa: 1 dia Tipo: Backend + Frontend

Contexto
O objetivo final de muitos bots é converter o visitante em usuário. Precisamos de um nó que finalize a conversa e direcione o usuário para fora do chat (ex: Dashboard, Página de Login, Link Externo).

Onde começa
Chat apenas troca mensagens de texto.
Onde termina
Chat pode comandar o navegador do usuário para mudar de URL, rolar para âncoras ou disparar eventos.
O que precisa ser feito
Backend:

Ai::Nodes::Redirect: payload { type: "redirect", url: "...", action: "navigate" | "scroll_to", target: "#id" }.
Auth Action: Se configurado "Create Account", gerar User (shadow) com Name/Email (Telefone opcional, não bloqueante). Retornar token de autologin.
Frontend:

Widget escuta evento de action:
Se navigate: router.push(url) (SPA transition) ou window.location (external).
Se scroll_to: document.getElementById(target).scrollIntoView().
Se auth_token presente: persistir e atualizar estado de usuário.
O Builder deve receber lista de rotas/seções disponíveis para autocomplete (se possível).
Critérios de aceite
Configurar nó para redirecionar para /dashboard.
Ao chegar no nó, usuário é autenticado (se dados existirem) e navega para dashboard.
Testar nó "Scroll to Pricing": chat faz a landing page rolar até #pricing.
📅 Sprint 2: Rich Media & Engagement
Focus: Making the chat experience immersive with multimedia.

Tarefa 2.1: Additional Media Nodes (Image, Audio, Video)
Estimativa: 1.5 dias Tipo: Backend + Frontend

Contexto
Texto puro tem baixa conversão. Bots modernos usam áudio (voice notes simulados) para intimidade, imagens para produtos, e vídeo para demos. Precisamos expandir o nó de "Bubble" para suportar esses tipos, com foco total em performance (WebP/Otimização).

Onde começa
Builder só suporta "Text" e "Video" (básico).
Onde termina
Builder suporta Upload de arquivos (com otimização no backend) E Gravação de Áudio (microfone) direto no admin.
Widget renderiza components otimizados:
Imagens: srcset, WebP, lazy loading. "Nada de jogar 4k no chat".
Audio: Player nativo estilizado.
O que precisa ser feito
Backend:

Alterar Ai::Nodes::Output para aceitar media_type.
Implementar processamento de upload (ActiveStorage variants ou processamento manual para resize/compress).
Frontend:

Builder:
Input de URL ou Upload.
Audio Recorder: Botão para gravar voice note direto no navegador (similar ao /audio-visualizer).
Widget:
Componentes ImageBubble, AudioBubble (visualização de onda se possível).
Critérios de aceite
No Builder, gravar um áudio de 5s via microfone e salvar.
Widget reproduz o áudio corretamente.
Upload de imagem grande (>2MB) é redimensionada/otimizada antes de aparecer no chat.
📅 Sprint 3: Integrations & Intelligence (Data & OCR)
Focus: Connecting chat data to business value.

Tarefa 3.1: Lead Integration (Save to Lead)
Estimativa: 2 dias Tipo: Backend

Contexto
O chat coleta dados, mas eles ficam presos no JSON da sessão. Precisamos persistir isso na tabela 
Leads
 ou Users para CRM e marketing. O usuário deve mapear "Qual variável do chat" vai para "Qual campo do Lead".

Onde começa
Dados ficam em session.context.
Onde termina
Dados fluem para 
Lead
 (nome, email, telefone, custom_fields).
O que precisa ser feito
Backend:

Ai::Nodes::SaveToLead.
Configuração: Hashmap { "lead_name": "{{name}}", "lead_email": "{{email}}" }.
Service busca ou cria Lead baseado no identificador (email/session) e atualiza campos.
Critérios de aceite
Chat coleta email em variável user_email.
Nó "Save to Lead" configurado para salvar user_email -> Lead.email.
Após execução, verificar no banco de dados que o registro 
Lead
 foi atualizado.
Tarefa 3.2: Image Input & OCR (AI Vision Actions)
Estimativa: 2 dias Tipo: Backend + AI Integration

Contexto
Permitir que o usuário envie imagens. O bot deve usar IA (Provider desacoplado) para "ler" a imagem e gerar uma versão melhorada/texto refinado (Prompt Enhancer), não apenas OCR puro.

Onde começa
Usuário só pode enviar texto.
Onde termina
Widget aceita upload de imagem.
Backend envia para Ai::Services::VisionProvider (Adapter pattern: Claude/OpenAI).
LLM analisa imagem + Prompt instrucional ("Melhore este texto...") -> Retorna texto refinado.
O que precisa ser feito
Backend:

Service Ai::Services::VisionExtract com adapter para providers (iniciar com Claude/Anthropic).
Prompt engineering para "refinamento" e não apenas "leitura".
Frontend:

Widget: Botão de clipe/upload. Support drag&drop.
Critérios de aceite
Usuário envia foto de um rascunho manuscrito.
Bot responde com o texto digitado E melhorado (corrigindo pontuação/estilo), conforme instrução da IA.
📅 Sprint 4: Commerce & Advanced Testing
Focus: Monetization and developer experience.

Tarefa 4.1: End Node - Tracked Link (Checkout)
Estimativa: 1 dia Tipo: Backend

Contexto
Para e-commerce, precisamos gerar links de checkout que saibam quem é o usuário (para não pedir dados de novo) e rastrem a venda.

O que precisa ser feito
Nó que gera URL com parâmetros: checkout.com?ref=SESSION_ID&email=USER_EMAIL.
Apresentar como "Card de Produto" ou botão CTA.
Tarefa 4.2: Improved Test Logs (Data Tracking)
Estimativa: 1 dia Tipo: Frontend (Console)

Contexto
O console de testes atual mostra o fluxo, mas não mostra claramente as mudanças de dados (ex: "Lead Email atualizado para 
x@x.com
").

O que precisa ser feito
Atualizar logs para incluir eventos de DATA_CHANGE.
Mostrar visualmente diff de variáveis no console lateral.