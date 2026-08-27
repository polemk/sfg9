# Sprint: Telemetria Comportamental & Mapa de Calor

**Projeto:** ai9 / monorepo
**Estimativa:** 5–7 dias  
**Referência de implementação:** Hotjar / PostHog / Ferramentas de Analytics Modernas

---

## Contexto

A camada de trackeamento atual do app (via `tracked_events`) está excessivamente poluída, gerando um volume massivo de eventos inúteis (ex: "scroll_depth" disparando 90% em três etapas de 25% no mesmo segundo). Pior ainda, os dados estão isolados e desvinculados do histórico do `Lead`. Se um visitante chega via Meta Ads e futuramente se torna um cliente, não conseguimos fazer o retrocesso para mapear sua jornada pregressa de cliques, comportamento tátil e tempo de tela.

O objetivo desta sprint é reconstruir o pipeline de *Behavioral Analytics* de ponta a ponta. Isso exige a implementação de um sistema robusto de `High Watermark` e `Debounce` no frontend, a vinculação estrutural de eventos ao id do Lead no backend e a construção de duas ferramentas analíticas visuais no Admin: uma "Timeline" descritiva no perfil de cada lead e um "Mapa de Calor" para visualizar interações massivas baseadas na origem de tráfego.

---

## Como o fluxo deverá funcionar

```
Usuário (origem UTM ex: ad_video_1) acessa a Landing/Site
        ↓
Gera "Session UUID" armazenado em localStorage e atrelado ao Lead 
        ↓
Listener `useTracker` agrupa "Scrolls", visualizações de blocos e "Cliques" sob regras drásticas de Anti-Spam (apenas o maior scroll conta, clicks são bufferizados).
        ↓
POST /api/v1/tracked_events/batch (Envio das informações em lote via Heartbeat ou Fechamento da Sessão)
        ↓
Gravação no Postgres: payload enriquecido e referenciado a `lead_id`
        ↓
PAINEL ADMIN (Goat Analytics)
  ├── 1. Perfil do Lead: Lista exata da jornada (Ex: "Ficou 4min na Home, rolou 75% e clicou em Garantia")
  └── 2. Heatmap Global: Mostra um mapa térmico onde cliques se concentram para a URL selecionada (ex: botões fantasmas, imagens ou botões primários).
```

---

## Tarefa 1: Vínculo de Identidade do TrackedEvent (Backend & Frontend)

**Contexto**  
Hoje os eventos têm *session_uuid* soltos. Precisamos que o banco de dados entenda quando essa sessão pertence a uma identidade de Lead concreta, para mapear comportamento à conversões reais.

**O que fazer**  
Modificar o contrato da API (`POST /api/v1/tracked_events`) e do model `TrackedEvent`.
1. Adicionar `lead_id` opcional na tabela `tracked_events`.
2. Se o backend recebe um evento e já sabe quem é o lead (via JWT ou *fingerprint* da sessão no Cookie), o evento é salvo com `lead_id`.
3. Quando um visitante anônimo interage pela primeira vez, os eventos ficam só com o `session_uuid`. Assim que ele se registra (cria um Lead), um job retroativo deve atualizar os `tracked_events` desse `session_uuid` injetando o novo `lead_id`.

**Critério de aceite**  
Registros na tabela `tracked_events` passam a ter o ID de um lead associado. Toda vez que um anônimo virar capturado, todas as suas "leitura e cliques" passados aparecem instantaneamente vinculados a ele.

---

## Tarefa 2: Anti-Spam de Scroll e Normalização (Frontend)

**Contexto**  
A mecânica de disparo atual registra repetidamente marcos de scroll de forma imediata e desorganizada (emitindo vários eventos no mesmo segundo). 

**O que fazer**  
Limpar as diretrizes no frontend criando um *High Watermark*:
1. Remover envio instantâneo a cada "pedacinho" que o cara rola de tela. O sistema gravará a "Profundidade Máxima" rolada numa variável em runtime e apenas enviará esse evento via "Debounce" largo (ex: ao terminar de ler e pausar por 4 segundos, ou no fim da sessão).
2. Garantir que as chaves de payload enviadas fiquem padronizadas no frontend (ex: `{ type: "scroll_depth", max_percentage: 75, duration_viewed: 45 }`).

**Critério de aceite**  
Um usuário entrando no site e rolando pro fim da página de uma só vez gera no máximo **um ou dois** eventos consolidados contendo a profundidade real atingida, reduzindo em 90% o ruído no banco.

---

## Tarefa 3: Coletor de Ouro (X,Y) para o Mapa de Calor (Frontend)

**Contexto**  
Para podermos enxergar onde o lead tentou interagir e estudar atritos de UX, precisamos não apenas ver que ele "rolou", mas em quê ele bateu com o dedo/mouse. 

**O que fazer**  
No hook de observação global (wrapper principal do React):
1. Capturar todo e qualquer `onClick`.
2. Ocultar de envios instantâneos, jogando-os num Buffer local (`array`).
3. Calcular as posições físicas do clique transformadas em porcentagens (`X% da tela horizontal` e `Y% baseado no Height do Container ativo`).
4. Extrair metadata tática: Ex `'dumb_click'` (clique no fundo, falho) ou `'active_click'` (cliques em botões, links). 

**Critério de aceite**  
Se eu clico 8 vezes consecutivas numa foto achando que é um produto (UX confusa), o state do componente reune esses 8 cliques em formato matemático, prontos para deságue, sem travar o browser.

---

## Tarefa 4: Endpoint de Ingestão em Lote (Backend)

**Contexto**  
Enviar os cliques de `Tarefa 3` de forma individual mataria o pool de conexões do nosso servidor e causaria anomalias. 

**O que fazer**  
1. Criar novo Action no namespace Grape de eventos: `POST /api/v1/tracked_events/batch`.
2. A API deve aceitar um array JSON contendo centenas de interações formatadas e usar processamento bruto ou em `bulk_insert` (`insert_all`) no PostgresSQL.
3. Isso será disparado a cada N segundos silenciosamente pelo frontend (heartbeat) acompanhado dos atributos UTM de rastreamento.

**Critério de aceite**  
Uma requisição mandando 20 ações interativas juntas retorna Status 201 e injeta simultaneamente e com eficiência total as 20 fileiras na base de dados, devidamente assinadas.

---

## Tarefa 5: Dashboard de Timeline Cronológica (React)

**Contexto**  
Com o `Lead` tendo seus eventos vinculados retroativamente (Tarefa 1) e de forma enxuta (Tarefa 2), a visualização dos logs da página Analytics e até mesmo a aba interna do Lead individualmente perdem ruído.

**O que fazer**  
1. Criar um painel cronológico visual na página de detalhe/métrica do `Lead`.
2. Formatar os registros limpos: "08:15: Desceu até as Perguntas Frequentes (75%)" e "08:16 Clicou para Comprar".  
3. Oferecer filtros para descartar interações minúsculas e permitir ver a "Big Picture" de venda.

**Critério de aceite**  
O vendedor (usuário do Goat Admin) entende num bater de olho, lendo a aba Analytics do Lead, o nível de engajamento através da pureza semântica das ações mapeadas ali, gerando valor real de análise.

---

## Tarefa 6: Motor e Render Visual do Heatmap (React Admin)

**Contexto**  
Essa é a coroa do tracking. Entender empiricamente com o que e onde a massa de usuários provenientes de campanhas chaves mais está sofrendo de atrito através do "Tracking Termal".

**O que fazer**  
1. Nova sub-aba em `Metricas -> Heatmaps`.
2. Selecionador "URL Visada" e "Filtros de Táfego/UTM".
3. A interface faz fetch por coordenandas `X / Y` em batch da nossa API de listagem de eventos.
4. Renderiza um Iframe do Site em Sandbox (read only) envolto por uma camada SVG ou Canvas transparente.
5. Injeta pontos de coloração por grau de radiação visual (frequência) onde aconteceram agrupamentos nos metadados obtidos.  

**Critério de aceite**  
Posso solicitar métricas de calor oriundas da `/` na versão "Mobile" das campanhas Tiktok e assistir buracos avermelhados no meio de seções em que eu jamais imaginei que humanos tivessem tocando na tela.

---

## O que esta sprint não cobre (Próxima)

1. Funcionalidade de gravação ininterrupta da tela em tempo real (Session Replay estilo video-playback).
2. Transposição direta e integral deste heatmap voltado para conversão às aberturas do "Painel Autenticado Logado do Visitante" (nesta sprint testamos a bala apenas no site vitrine e painel principal).
