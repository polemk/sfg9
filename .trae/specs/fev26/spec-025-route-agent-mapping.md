# Tarefa 4.1: Route-to-Agent Mapping & Context Switching

**Sprint:** 4 - Agent UI Redesign & Embedded Navigation
**Estimativa:** 2 dias
**Tipo:** Backend + Frontend

---

## Contexto e Regras de Negócio (A "Maravilha de Solução")

O sistema precisa suportar a troca dinâmica de Agentes de IA baseada na rota (URL) atual do usuário, mas sem prejudicar conversas em andamento ou a jornada principal do lead. 

Para resolver o conflito entre "agente isolado da página" vs "agente da jornada principal iniciada", estabelecemos o conceito de **"Ancoragem por Intenção"**:

1. **Atribuição de Operação:** O Lead SÓ é associado a uma Operação quando sua **intenção é detectada** (via *IntentDetector* ou *Keyword*). Simplesmente conversar com um agente que pertence a uma operação, por estar navegando na página daquele agente, **não** trava o lead naquela operação.
2. **Imutabilidade da Intenção:** Uma vez que o Lead ganha uma Operação, sabemos o que ele quer. A partir daí, a Operação não muda mais por navegação (somente se o admin alterar manualmente no painel ou se o lead digitar uma keyword exata de outra operação/agente alvo).
3. **Troca de Contexto na Rota (`override_active_chat`):** Cada "Agent Flow" agora dirá quais rotas ele domina e se ele tem prioridade sobre conversas em andamento (Leads SEM operação).

### Matriz de Decisão de Roteamento de Agentes (No Widget do Frontend):

| Estado do Lead | Histórico do Chat Atual | Ação Primária do Widget ao Mudar de Rota | Comportamento na UI |
| --- | --- | --- | --- |
| **SEM** Operação | **Vazio** (nunca mandou msg) | Troca para o **Page Agent** | Carrega a saudação do Page Agent imediatamente. |
| **SEM** Operação | **Em Andamento** (com outro agente) | Avalia `override_active_chat` do Page Agent | Se *true*: Interrompe e troca pro Page Agent.<br>Se *false*: Mantém o agente da conversa atual. |
| **COM** Operação | Qualquer | **Mantém o Agente Atual** | Não carrega o Page Agent primário. Mantém o fluxo atual, **mas mostra um banner/botão no topo do chat**: *"💡 Falar com o especialista desta página"*. Se clicado, troca temporariamente de contexto com botão de *"⬅️ Voltar ao Atendimento Principal"*. |

---

## Onde começa
O Model `ChatFlow` no backend (`app/models/chat_flow.rb`) tem tipos `chatbot` e `ai_agent`, mas não sabe para quais rotas de Frontend ele foi designado e não tem a configuração de `override_active_chat`. O frontend não tem a lógica de arbitragem de contexto. O Lead tem o campo `operation_id`, que deverá ser exposto no estado do visitante do Frontend da loja.

## Onde termina
A tabela `chat_flows` receberá o campo `mapped_routes` (array) e `override_active_chat` (boolean). A API Rest e o Frontend React (`AIChatWidget`) agirão como os "Árbitros" do chat, avaliando a URL atual vs o estado do Lead atual para decidir qual agente renderizar de forma fluida.

---

## O que precisa ser feito

### No Backend

1. **Migration Mapped Routes**:
   Criar nova migration para a tabela `chat_flows`:
   `rails g migration AddRoutingToChatFlows mapped_routes:string,array:true,default:[] override_active_chat:boolean,default:false`
   
2. **Model e Permitted Params**:
   Atualizar o model `ChatFlow` e seu serializer (`Api::Entities::ChatFlow`), permitindo os campos `mapped_routes` (Array[String]) e `override_active_chat` (Boolean) através do Grape API nos processos de POST e PUT.

3. **API do Estado do Visitante/Lead**:
   Verificar nos hooks de autenticação/sessão de Visitante (ex: `VisitorService` ou API de identificação de sessão atual) se o Lead amarrado a ele já possui `operation_id` não nulo. O frontend precisa dessa variável `hasOperation` de forma reativa.

### No Frontend

1. **Builder UI (`AIAgentConfigPanel.tsx`)**:
   - Inserir campo (Tags Input ou Creatable Select multiselect) para rotas nas Configurações do Agente: **"Ativar neste Agente nas Rotas (URL Mapped)"**. Ex: `/ofertas`, `/precos`.
   - Inserir Toggle Switch: **"Sobrescrever Atendimento em Andamento"** vinculando ao `override_active_chat`. Tooltip sugerida: *"Se ativo, este agente interrompe a conversa atual de leads sem operação que entrarem nesta rota."*

2. **Lógica de Arbitragem no `AIChatWidget`**:
   - Criar um hook customizado `useAgentRouter(currentPath, visitorLeadState)`.
   - O hook varre a lista configurada de todos os `chat_flows` globais disponíveis do sistema.
   - Encontrar o agente que case com o `currentPath` no array `mapped_routes`.
   - Aplicar as lógicas da **Matriz de Decisão**.
   
3. **UI de Troca de Contexto (Banners Customizados)**:
   - Se a regra diz para iniciar a UI do Page Agent, renderizar o chatFlow associado a ele.
   - Cenário *"Lead já tem Operação e entra na rota com Page Agent"*: Adicionar o botão dinâmico na Header do Widget (ex: `[?] Especialista em Preços disponível`). Ao acessar este fluxo paralelo, trocar a header para uma cor de "Atendimento Auxiliar" e exibir um CTA primário pulsante *"Voltar para minha jornada"* para restaurar o ChatFlow da operação em andamento.

---

## Observações Importantes
- Mantenha a sincronia do histórico ao trocar de agente! As mensagens pertencem à `Session` ou `Lead`, então ao trocar o agente o balão deve mostrar tipo um "Transferido" do que apagar tudo. (Decisão técnica sujeita a revisão caso as threads fiquem complexas).
- Aceitar o "upsert" das URLs. Não adicione validação de rota única no model backend logo de cara para não burocratizar (`validates_uniqueness_of`). Foque na resolução (Ex: O primeiro flow encontrado com a URL preenchida ganha a prioridade do React).

---

## Critérios de Aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. Execução de Migration livre de erros.
2. No componente do Builder, configurar o Agente A preenchendo as rotas `['/cursos']` e checando na aba Network do navegador (XHR) que os dados foram salvos e retornaram HTTP 200.
3. Teste Manual (Cenário 1): Entrar na página `/cursos` (chat vazio, Lead novo) -> O Widget deve iniciar forçado no Agente A.
4. Teste Manual (Cenário 2): Conversando em progresso com Agente B, sem operação. Agente A configurado com `override = true`. Navegar pra `/cursos` -> Widget encerra contexto antigo e ativa Agente A.
5. Teste Manual (Cenário 3): O Lead teve Intenção Detectada (Ganhou Operação O1). Conversando com B, navega para `/cursos`. O Agente B continua 100% ativo na tela, mas um botão visual extra sugere conversar com o "Especialista em cursos" (Agente A).

---

## Dependências
- Contexto de V4 FlowEngine estar de pé para suportar chamadas de APIs de múltiplos agentes.

## Próxima tarefa
Tarefa 4.2: Side-by-Side Desktop Layout (`spec-026-desktop-split-layout.md`)
