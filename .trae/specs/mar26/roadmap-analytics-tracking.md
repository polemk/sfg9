# Sprint: Revamp da Camada Analytics & Behavioral Tracking
**Projeto:** ai9 / branch: analytics-revamp  
**Estimativa:** 4–5 dias  
**Referência de implementação:** Baseado no template de `roadmap-meta-omni.md`.

---

## Contexto

Atualmente, a aba "Live Event Log" no Dashboard captura eventos do frontend (como `scroll_depth`), porém o comportamento não é acionável. Múltiplos eventos são disparados e salvos assincronamente no exato mesmo segundo (25%, 50%, 75%, 90%) sem uma clara correlação estruturada com o `Lead` dono da sessão, tornando a tela de métricas um mar de eventos brutos de difícil leitura.

O objetivo desta sprint é elevar o "Log Padrão" a uma **Ferramenta de Telemetria Comportamental (Behavioural Tracking)**. Queremos rastrear passos vitais do funil (como clique no zap, formulários abandonados, etc.), normalizar os envios excessivos no frontend e, mais vital, "costurar" o evento rastreado ao Lead proprietário dele no ato de armazenamento da base, permitindo a visão "Jornada do Cliente X".

---

## Como o fluxo deverá funcionar

```
Visitante entra na página
        ↓
Gera "session_uuid" no localStorage
        ↓
O frontend (React) retém os rastreios ao invés de inundar a API
(Uso de High Watermark para Scroll, ou Debounce pesado)
        ↓
Atinge rodapé? Sai da aba (unmount)? Clica em CTA (botão Whatsapp)?
        ↓
Dispara apenas O evento consolidado ao POST /api/v1/tracked_events
        ↓
API intercepta Payload → Localiza o Lead dono da "session_uuid"
        ↓
O Evento Rastreável salva no BD vinculado explicitamente ao `Lead` (lead_id)
        ↓
Console Admin cruza dados em tempo real montando as Histórias Estatísticas dos Usuários
```

---

## Tarefa 1: Modelagem do DB e Vínculo Opcional Rígido (Backend)

**Contexto**  
A tabela `tracked_events` atual tem `session_id` e `user_id`, mas não possui vinculação de tabela com os leads (visitantes anônimos/cadastrados). Eventos comportamentais de funil perdem o sentido se a equipe comercial não puder ler "O que foi que este lead específico acessou no nosso site antes de me chamar".

**O que fazer**  
Adicionar aos eventos a chave relacional do `Lead`:

1.  Gerar migration: `add_reference :tracked_events, :lead, type: :uuid, null: true, foreign_key: true`.
2.  No modelo `TrackedEvent`, inserir `belongs_to :lead, optional: true`.
3.  Modificar o serviço que recebe `POST /api/v1/tracked_events` (ver `api/v1/events` ou rota correlata da Grape API): ao gravar, capturar o parâmetro em comum (seja via UUID de cookie, seja header, seja `session_id`) e localizar um `Lead` associado. Se achar, atrela o evento ao Lead.

**Critério de aceite**  
Na listagem e inspeção, eventos que pertencem a um usuário de quem sabemos a identificação e os cookies aparecem nativamente salvos vinculados ao respectivo `lead_id` no Postgres.

---

## Tarefa 2: Refatoração do Frontend Crawler / Debounce Inteligente (React)

**Contexto**  
"Todos os acessos estão gerando 90% em três etapas de 25% no mesmo segundo". Isso ocorre pois o ouvinte react não efetua limite ou filtro de submissões.

**O que fazer**  
Mapear o atuador de scroll e reescrever a lógica para usar o conceito de *High Watermark*:

1.  Armazenar o maior estágio percentual tocado na respectiva montagem da página (`maxDepthReached = 90`).
2.  Substituir o modelo atual de "Gatilho imediato toda vez que mudar 25%" para:
    *   Um script acoplado as interfaces de Unmount da página (`useEffect return()`), ou eventos globais de fechamento da tag (`window.addEventListener('pagehide', handler)`),
    *   **OU** uma rotina debounced onde a requisição sai da pilha se o estado mudar imediatamente em menos de 1000ms.
    *   Submeter *apenas uma vez*, apontando para: `"event": "scroll_completed", "payload": { "max_depth": "90%" }`.

**Critério de aceite**  
Visitar o site do topo à base instantaneamente não dispara 4 chamadas seguidas de `POST`. A tela de Admin captura e lista apenas uma iteração valiosa do usuário atigindo os 90%.

---

## Tarefa 3: Enriquecimento Estruturado Semântico (`Payload Jsonb`)

**Contexto**  
Um `page_view` ou clique se perde analiticamente sem metadados. O banco já possui um Jsonb de `payload`, no entanto ele frequentemente subutilizado ou caótico.

**O que fazer**  
Criar um contrato estrito em TypeScript na interface do Tracker e padronizar campos no `TrackedEventService` em Rubi.

*   `target_element:` Para apontar de qual sessão exata o disparo em um CTA se refere `(hero/cta-wpp, pricing/sign-up, navkit/back)`.
*   `duration_seconds:` Tempo retido desde o carregamento daquela subpágina, útil em logs unmount para saber se o leitor analisou aquele conteúdo ou deu skip rápido.

**Critério de aceite**  
Na tabela Live Event Log, não aparece mais apenas a mensagem crua. Existe a coluna `DETAILS` informando "Button Whatsapp Clicado Em: Seção de Preços (Ficou na página 42s)".

---

## Tarefa 4: Dashboard - O Painel "Lead Journey" / Comportamental (Admin)

**Contexto**  
A tabela temporal ao estilo `Live Event Log` agrafa todos os dados num balde global; ela segue sendo importante pro TI checar se o servidor opera. Pro analista ou corretor é inútil.

**O que fazer**  
Ação dupla de visualização sobre os dados filtrados em GraphQL ou chamadas Rest dedicadas:

1.  **Linha do Tempo Específica (Funil Individual)**: Na página Modal / Detalhes de um `Lead` lá dentro de Vendas ou Canal de Chats, gerar um feed lateral "Pegada Digital" (`events.where(lead_id: current_lead.id).order(:created_at)`), com ícones indicando "View Landing -> Viu Planos -> Clicou no WPP".
2.  **Métricas Estatísticas Abstratas (Funil Genérico)**: Na aba Analytics Overview, agrupar o "qual a taxa percentual dos leads que dão *bounce* e nunca descem aos 75% da home?". 

**Critério de aceite**  
Eu como administrador posso selecionar uma visualização na aba de Analytics "Por Sessão Individual" agrupando sequenciadamente do topo pra baixo os passos do cliente antes do evento gatilho, me ajudando a ler padrões.

---

## O que a sprint aborda (Escopo fechado)
- Redução brusca do log noise em infra de métricas;
- Assinatura de comportamento cruzada entre `Leads` e eventos;
- UI remodelada para visualizar jornadas lógicas pelo ID da sessão.

## O que a sprint não inclui
- Mapas de colorimetria de Calor no cursor (`Heatmaps UI`);
- Testes A/B nativos entre a navegação do `NavKit`;
