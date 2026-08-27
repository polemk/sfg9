# Tarefa 3.2: Operations Dashboard UI & Bulk Upload

**Sprint:** 3 - Operations Admin UI & Bulk Upload
**Estimativa:** 2 dias
**Tipo:** Frontend

---

## Contexto
O administrador, após configurar as chaves da OpenAI (no `AIAgentConfigPanel`), precisará de um lugar visual para colocar todo o conteúdo específico daquele novo condomínio ou clínica que acabou de cadastrar no sistema (`Operations`).
Será criado um "Hub" ou "Dashboard" (Painel Administrativo) em React para listar Operations, visualizar métricas de conversão de Leads, permitir arrastar e soltar (drag & drop) vários PDFs e imagens de uma só vez (Bulk Upload) para alimentar a base de conhecimento e mídias daquela Operação específica, consumindo os endpoints criados na Tarefa 3.1.

---

## Onde começa
A UI atual possui um menu de "Gerenciamento" focado em Chats/Agentes e Leads soltos na Master, porém as `Operations` rodam invisíveis (são manipuladas apenas por seeds ou backend devs).

## Onde termina
Haverá uma nova tela no painel (em `/admin/operations` ou equivalente) rica em interações onde a equipe não técnica alimentará os textos pesados, FAQs, PDFs e fotos que alimentarão os cérebros (Vector Embeddings) dos bots que falam sobre tal Operation. Se o bot não sabe algo sobre o Empreendimento X, é por essa tela que o Admin arrumará.

---

## O que precisa ser feito

### No Frontend

1. **Dashboard List**:
   Criar `OperationsDashboardPage.tsx` contendo uma Tabela (shadcn/ui `Table` ou Grid Cards) que mostra todas as Operações. Ela deve consumir a rota `GET /api/v1/operations`. Deve exibir as colunas: Nome, Status, Qtd. de Leads Gerados, Qtd. Assets anexados.
   
2. **Operation Details / Editor**:
   Ao clicar nela, abrir a `OperationManagerPanel.tsx`.
   - Terá duas abas principais (Tabs): "Base de Conhecimento" e "Mídias & Docs".
   - **Base de Conhecimento**: Um formulário `<textarea>` largo, ou "Wysiwyg" minimalista. O Admin cola o briefing, FAQ ou regras daquela Operation. Ao salvar (`PUT /api/...`), exibe Toast de "Indexando na IA...".
   - **Mídias & Docs**: Uma área pontilhada rica em DND (Drag And Drop). O usuário joga 5 fotos e 1 vídeo. O painel deve uploadeá-los (pode usar XHR `FormData`). Ao finalizar os envios para a API e receber os shortcodes (ex: `[asset:SECURE12]`), listar a fotinha na tela, a descrição dela, e o seu shortcode visual em um pequeno `Copy Badge`.

3. **Status e Feedback**:
   Caso o contador assíncrono (Task 1.3) demore, mantenha o estado de loading otimista na tela (usando cache/Invalidation do `react-query` onde os queries re-buscam após 2 segundos do upload para preencher os dados persistentes).

### No Backend
Não se aplica estruturalmente, as rotas para suprir a UX foram preparadas na Tarefa 3.1. O backend só garantirá CORS permissivo e limites de tamanho em multipart (`Rack::Request` config).

---

## Observações importantes
- Para a função de Multi-Upload, gerencie as chamadas de maneira co-rosteada (ex: um loop de Axios Promises em vez de um payload monstruoso) de forma a mostrar uma barra de progresso (Progress Bar shadcn/ui) "3/5 enviados...".
- Como a visualização (Preview) de PDFs no grid do painel pode ser custosa na renderização, mostre um ícone padrão `FileText` (Lucide) se o `mimeType` retornado em tela conter `application/pdf`. Mostre `<img>` em Thumbnails pequenos para `image/*`.

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. Conseguir criar uma tela listando as Operations mockadas retornadas do backend em layout limpo/shadcn.
2. Demonstrar o Drag & Drop puxando três fotos duma vez: a barra exibindo progresso, e por fim o backend retornando três Cards com as imagens visíveis, botão de exclusão e o número do "Shortcode RAG" (`asset:XYZ`) explícito pra copiar.
3. Teste Unitário (React Testing Library) na aba de Multi-Upload garantindo que os requests acontecem simulados (Nock/msw) com o Mock de erro ("Falha no upload!").

---

## Dependências
- Backend (Toda a Sprint 3.1 executada com as rotas REST completadas).

## Próxima tarefa
Tarefa 4.1: Route-to-Agent Mapping (Backend & Builder UI) (`spec-025-route-agent-mapping.md`)
