# Tasks: S2 — Console e navegação

Fila de trabalho do Phase 3 para a fatia **S2**. Ordem por camada: **dados → backend →
frontend → testes → paridade**. Uma tarefa = **um comportamento verificável**.

Depende de **S0** (`current_project!`, papéis/C3, `authorize!`, `Pagination`, `DataTable`,
`AsyncSection`, `PageHeader`, toasts).

Portões: `cd backend && bundle exec rspec` · `cd frontend && node
node_modules/typescript/bin/tsc --noEmit` (baseline **0 erro**).

## 1. Dados — mensagens administrativas e observadores

- [x] 1.1 Migration `admin_messages`: booleanos `integer 0/1` → **boolean**; `message` como
      **text** (era `string(255)` no banco com validação permitindo mais — truncamento
      silencioso); tokens público/privado; 2 campos configuráveis nomeados (sai
      `hadouken`/`shoryuken`). — **DB-390, DB-508, BE-526**
- [x] 1.2 Migration `message_notes` (thread). A citação aninhada
      (`top_parent_quote_id`/`quoted_note_id`) **não é portada** — a UI do console nunca a
      preenche (Q-B14); acrescentar depois é aditivo. — **DB-395, DB-513, BE-528**
- [x] 1.3 Migration `observers` — `is_extern` **não entra** (campo morto: defaultado e não
      exposto em UI nem em params). — **DB-391, DB-511**
- [x] 1.4 Migration `observer_contexts` com **índice único `(observer_id, context_id)`** no
      lugar do `SELECT COUNT` sujeito a corrida. — **DB-392, DB-512**
- [x] 1.5 Os 4 contextos e as 8 situações como **enum string**, com seed idempotente e sem
      resolução em variável de classe na carga (a armadilha do `Feedback19::State`). —
      **DB-393, DB-394, DB-509, DB-510, OPS-507** (parte `feedback19`)
- [x] 1.6 Registrar `DB-399` como **ausência**: não existe model, view SQL, materialized
      view nem job que alimente indicador de dashboard. Nada a migrar. — **DB-399**

## 2. Backend — casca, áreas e navegação

- [x] 2.1 Metadado de rota por área (título, ícone, papel) no lugar do `case/when` de ~38
      áreas. **Some o rebaixamento silencioso para `dash`.** — **BE-392, BE-393**
- [x] 2.2 Gate central com **default = exigir sessão** (no legado `requires_current_user?`
      era `false` e só o `ConsoleController` sobrescrevia — por isso users, permissions e
      memberships ficavam abertos). — **BE-414**
- [x] 2.3 Configuração declarativa do menu (6 grupos), derivada de `create_console_menu`,
      com filtro por **papel + participação** e o gate `projects.count > 0`. — **BE-418,
      NAV-001**
- [x] 2.4 `locked` lido **do item** (não do grupo) e **nenhum item nasce marcado**
      (DEC-15.1 — disponibilidades e cobranças estão vivas). — **BE-419**
- [x] 2.5 Seletor de projeto no servidor: troca **só** entre projetos com participação;
      nada de cookie; sem a heurística de "selecionar a segunda opção" quando não bate. —
      **BE-412**
- [x] 2.6 Defaults de listagem com **teto** de `per_page` (o legado aceitava `l=999999`; a
      base **também não tem teto**). — **BE-423**
- [x] 2.7 `GET /api/v1/countries/:code/states` e as demais opções encadeadas de formulário
      (as actions `state_select`/`city_select` do legado **não têm rota**). — **BE-413**
- [x] 2.8 **FECHADA em 26/08/2026 — as 13 áreas responderam.** As fatias donas (S3..S13)
      fecharam e preencheram as rotas. Conferido **rota por rota, rodando**, contra o
      servidor de dev com sessão de Admin de verdade — id real e uuid fantasma, código de
      resposta lido, não suposto:

      | # | área | rota de detalhe | id real | inexistente |
      | - | ---- | --------------- | :-----: | :---------: |
      | 1 | usuários | `GET /api/v1/users/:id` | 200 | 404 |
      | 2 | contratos | `GET /api/v1/contract_versions/:id` | 200 | 404 |
      | 3 | ajuda | `GET /api/v1/help_items/:id` | 200 | 404 |
      | 4 | projetos | `GET /api/v1/projects/:id` | 200 | 404 |
      | 5 | conexões de portador | `GET /api/v1/carriers/:id` (lista em `/project_carrier_connections`) | 200 | 404 |
      | 6 | recebíveis | `GET /api/v1/receivables/:id` | 200 | 404 |
      | 7 | renegociações | `GET /api/v1/renegotiations/:id` | 200 | 404 |
      | 8 | disponibilidades | `GET /api/v1/availability_templates/:id` · `GET /api/v1/project_availabilities/:id` | 200 | 404 |
      | 9 | empresas | `GET /api/v1/companies/:id` | 200 | 404 |
      | 10 | operações de risco | `GET /api/v1/risk_operations/:id` | 200 | 404 |
      | 11 | garantias | `GET /api/v1/project_guarantees/:id` | 200 | 404 |
      | 12 | operações estruturadas | `GET /api/v1/structured_operations/:id` | 200 | 404 |
      | 13 | cobranças/recibos | `GET /api/v1/charges/:id` · `GET /api/v1/charges/:id/receipts` | 200 | 404 |

      Área desconhecida (`/api/v1/nao_existe/:id`) → **404**, nunca casca de outra tela.

      **Três ressalvas de forma, nenhuma delas um detalhe faltando.** (a) A **conexão de
      portador** não tem `GET :id` próprio: ela é lida pela lista e o detalhe equivalente é
      o do portador — é o `BE-401` do legado (`carriers` + `section: 'carrier_connections'`),
      e não uma tela perdida. (b) `help_groups/:id` e `help_categories/:id` existem só para
      `PUT`/`DELETE`/`:id/impact`; a leitura é a árvore em `GET /help_groups`, e a edição da
      Central de Ajuda é em linha. (c) **Ajuda, garantias e disponibilidades não têm rota
      FILHA** em `consoleNavigation.tsx` — o detalhe delas abre em drawer (o FE-399), que é o
      padrão do console para formulário curto. O endpoint responde 200/404 do mesmo jeito; a
      2.8 é sobre a resposta do servidor, e a rota filha é escolha de tela. As outras dez
      áreas têm `children` declarados.

      **Um defeito real achado na conferência, e corrigido aqui:**
      `GET /api/v1/project_carrier_connections/:id` (a conexão expõe só `DELETE :id`)
      respondia **500** — com 9,5 KB de backtrace no corpo — porque o `rescue_from :all`
      herdado da base ai9 engolia o `Grape::Exceptions::MethodNotAllowed`. É literalmente o
      "500 de verdade" que esta tarefa manda eliminar. Agora responde **405** com
      `Allow: OPTIONS, DELETE`, e o backtrace vai para o log (o vazamento era EXCEÇÃO-2 do
      DEC-30). Alterado em `app/controllers/api/v1/base.rb` por DEC-50; registrado em
      `upstream-flags.md`. Pinado em `spec/requests/api/v1/detail_routes_spec.rb`.
      — **BE-395, BE-397, BE-398, BE-400, BE-401, BE-402, BE-403, BE-404, BE-405,
      BE-406, BE-407, BE-408, BE-409**
- [x] 2.9 **FECHADA em 26/08/2026 — o bloqueio era fóssil.** S6 e S9 fecharam e entregaram
      os dois estados; a conferência foi ler o código das quatro telas e rodá-las.

      1. **`default_project` nulo** — o que no legado era `NoMethodError` é hoje o
         `ProjectScopeState`, e ele distingue **três** situações onde o legado tinha uma:
         404 `PROJECT_NOT_FOUND` (pediu projeto que não enxerga, erro de verdade), 409
         `PROJECT_NOT_SELECTED` ("escolha um projeto na barra lateral") e 409
         `PROJECT_NONE_AVAILABLE` ("peça a um administrador — não há nada a corrigir aqui").
         Ligado nas quatro telas do escopo: `ReceivablesPage`, `ReceivableFormPage`,
         `RenegotiationsPage`, `RenegotiationFormPage` (e em mais 18 telas do console).
      2. **Lista vazia em silêncio** — criar renegociação em projeto **sem fornecedores**
         agora suprime o formulário com a razão e o atalho ("Este projeto ainda não tem
         fornecedor" → Cadastrar fornecedor), idem sem empresa; o borderô faz o mesmo para
         portador não conectado e para empresa ausente.

      **Um defeito real achado na conferência, e corrigido aqui:** o atalho "Conectar
      portadores" do borderô apontava para `/project-carriers`, **rota que não existe** — a
      registrada é `/project-carrier-connections`. O botão caía na rota curinga e levava à
      tela de "não encontrado": o estado vazio explicava o problema e o atalho não resolvia,
      que é meio caminho de volta ao defeito do legado. — **BE-402, BE-403**
- [x] 2.10 Formatação de data/número em **pt-BR no cliente** (os locales da engine serviam
      nomes de dia/mês para o `I18n.l` do servidor); **não ligar i18n** (DS2-5). —
      **BE-511**
- [x] 2.11 Registrar os `dropped` de backend com evidência: branch de "viewing token",
      área `changelog` (link morto), `respond_to` de duas caras, renderização em duas
      passadas, `protect_from_forgery` inócuo, e os 3 endpoints de `dash` quebrados. —
      **BE-394, BE-396, BE-410, BE-411, BE-415, BE-420, BE-421, BE-422**

## 3. Backend — mensagens administrativas e observadores

- [x] 3.1 `GET /api/v1/admin_messages` com filtros, paginação **e total correto** (o
      `@total_count` do legado era `Message.all.count` — o total **global**, calculado antes
      dos filtros). — **BE-424**
- [x] 3.2 `AdminMessage` + `MessageNote` como código do app (não engine), com as validações
      preservadas e o limite de caracteres aplicado **no banco e no servidor**. — **BE-526,
      BE-528, BE-531**
- [x] 3.3 Máquina de estados das 8 situações, com as transições automáticas (admin abre
      "Não lido" → "Lido"; 1ª resposta do admin → "Respondido"). **Correção observável:**
      pedir "Concluído" grava **"Concluído"**, não "Fechado" (DC-16/Q-B16). — **BE-527**
- [x] 3.4 `GET /api/v1/observers` com `limit`/`offset` **aplicados** (hoje o legado lê e
      nunca aplica — D-88), papel checado, e o CRUD completo. — **BE-426, BE-427, BE-428,
      BE-429, BE-529**
- [x] 3.5 `ObserverMailer` + `MessageMailer` com **template ERB** — o HTML dos e-mails era
      montado por concatenação de string dentro do Ruby. — **BE-530, OPS-394**
- [x] 3.6 Envio de mensagem: **autenticado por padrão**; se o envio anônimo for confirmado
      (Q-B17), entra na allowlist **por rota** com throttle do Rack::Attack, nunca por
      brecha de formato. O honeypot anti-bot vira throttle. — **BE-531, BE-525**
- [x] 3.7 Registrar os `dropped` com evidência: `AdminMessagesController#index` duplamente
      morto e as sobrescritas do SFG que roteavam a resposta da engine. — **BE-425, BE-532**

## 4. Frontend — casca e navegação

- [x] 4.1 **Rota curinga `*` com tela de não encontrado** — a base não tem nenhuma
      (`App.tsx:56-87`). Sem ela, área desconhecida vira tela em branco. — **BE-390**
- [x] 4.2 As ~38 rotas por área com URL estável, compartilhável e **histórico de verdade**
      (`pushState`, não `replaceState`): o botão Voltar deixa de sair do console. —
      **BE-390, FE-397, OPS-393** (IMP-A11)
- [x] 4.3 `Layout` + `Suspense` no lugar do splash com polling de 10 ms; sem detecção de
      dispositivo por user-agent no servidor. — **FE-390, FE-391, BE-416**
- [x] 4.4 Topbar: logo da marca SFG, ícone de menu (mobile), **seletor de projeto** (visível
      quando há ≥1 participação), busca global e chip do usuário. — **FE-392, FE-393,
      FE-394**
- [x] 4.5 Sidebar em grupos acordeão, filtrada por papel + participação, com `NavLink`
      marcando o item ativo (no legado o item selecionado era derivado da URL à mão). —
      **FE-395, FE-741**
- [x] 4.6 Resumo do usuário na sidebar com **cor determinística** das iniciais (o
      `random_color` do legado gerava cor nova a cada render). — **FE-396** (IMP-A23)
- [x] 4.7 **FECHADA em 26/08/2026.** O drawer (FE-399) segue reusado em `/messages`. A
      **FE-400** foi feita agora, sobre o formulário longo que a S6 entregou (borderô) —
      era exatamente a condição que a tarefa esperava. É `adapt`, não réplica: no lugar da
      pilha LIFO de ações anônimas do legado entram três coisas, cada uma amarrada a um
      cenário da spec `console-admin`:

      - **estado sujo anunciado** — `FormActionBar` ganhou `alterado` e `erro`. A ordem de
        precedência do texto é erro › pendências › alterações não salvas › resumo, e a
        falha ao salvar é `role="alert"` e **fica na barra**: o `toast` some em 4 s e leva o
        motivo junto (cenário "Falha ao salvar");
      - **Descartar sem recarregar** — restaura o ponto inicial **em memória**, com
        confirmação. É a correção do bug do `cancel()`: o legado montava
        `{ reload: defaultReload() }` **com os parênteses** e portanto recarregava a página
        na hora de montar o objeto (cenário "Descartar alterações");
      - **aviso antes de sair** — `useUnsavedChanges`, novo na biblioteca compartilhada:
        `beforeunload` mais interceptação de clique em link interno na **fase de captura**,
        que é o caminho real de saída (a barra lateral usa `NavLink`, que é `<a href>`). A
        saída é represada como FUNÇÃO e só executa na confirmação (cenário "Alterações
        descartadas ao navegar" — o legado descartava em silêncio).

      **`useBlocker` não serve**: ele exige data router, e o app monta `<BrowserRouter>` em
      `main.tsx`. Trocar o tipo de roteador para ganhar um aviso de formulário é refatorar a
      base (Princípio 6b). O que a guarda **não** pega — o botão Voltar do navegador dentro
      do SPA — está escrito no cabeçalho do hook, não escondido.

      **Mobile (DEC-100), e aqui "cabe" não bastou.** Em 390×844 a barra nascia **atrás** da
      `MobileBottomBar` (`z-20` contra `z-appbar` = 30) e o botão "Cadastrar borderô"
      aparecia como uma tira de 6 px sob a aba "Recebíveis" — `tsc` e a suíte passavam. E a
      lista de nove pendências do formulário em branco ocupava quatro linhas, um oitavo da
      tela. Corrigido: a barra fica **acima** das abas
      (`bottom-[calc(4.25rem+env(safe-area-inset-bottom))] md:bottom-0`), o texto empilha
      sobre os botões no telefone, e a lista nasce **recolhida** com a contagem em primeiro
      plano ("Faltam 9 campos: …", tocável para abrir). No desktop nada muda.

      11 exemplos em `frontend/src/components/ui/__tests__/FormActionBar.test.tsx`.
      — **FE-399, FE-400**
- [x] 4.8 Paginação de desktop nas listagens do console, consumindo o `Pagination` de S0
      (corrigindo as inconsistências do legado: `defaultLimit = 50` com `limit` inicial 5,
      input sem teto). — **FE-403**
- [x] 4.9 `/` autenticado → **redirecionador por papel** (FE-404): OG → usuários;
      Admin/Gerente → projetos (sem projeto) ou recebíveis (com projeto); demais → minha
      conta (sem projeto) ou resultados (com projeto). **Não existe dashboard.** —
      **FE-404, BE-417**
- [x] 4.10 **Rotear `WhatsappPage.tsx`** (hoje existe e não está roteada), gateada por papel
      administrativo — é a tela de pareamento de que o login por WhatsApp de S1 depende.
      Decisão **DS2-2**. — **BE-390** (rota nova; sem ID de inventário — é achado da base)
- [x] 4.11 Registrar os `dropped` de front com evidência: `dashHolder`, contrato universal
      de `search` em `format: :js`, e os componentes de navegação matricial do `navkit`. —
      **FE-398, FE-402, FE-539**

## 5. Frontend — mensagens administrativas

- [x] 5.1 `/messages` em 2 colunas (mensagens / observadores), **com item de menu** — a tela
      era órfã no legado. — **FE-405, FE-528**
- [x] 5.2 Widget/formulário de mensagem com nome, e-mail, contexto (com cor), situação,
      corpo e campos extras **nomeados**. — **FE-406, FE-523, FE-526**
- [x] 5.3 Filtros de `/messages` que **zeram o offset ao trocar** (no legado dava para ficar
      numa página inexistente). — **FE-407**
- [x] 5.4 Lista de observadores + drawer de observador (nome, e-mail, "Feedbacks do
      sistema", checkboxes de contexto), corrigindo o bug de copy-paste do legado. —
      **FE-408, FE-409**
- [x] 5.5 Pontos do produto que enviam feedback, apontando para o endpoint autenticado. —
      **FE-527**
- [x] 5.6 Registrar os `dropped`: telas placeholder da engine e respostas `js.erb`. —
      **FE-524, FE-525**

## 6. Testes

### 6.1 Navegação por papel (C3) — **sempre os dois lados**

- [x] 6.1.1 O menu de um Gerente **NÃO** traz o grupo Admin **e** **traz** o grupo Cadastro.
      — **BE-418, NAV-001**
- [x] 6.1.2 O menu de um Colaborador **NÃO** traz Cadastro nem Admin **e** **traz** as telas
      do projeto. — **BE-418**
- [x] 6.1.3 Sem participação em projeto nenhum, o menu mostra o conjunto reduzido; com
      participação, mostra o completo do papel. — **BE-418**
- [x] 6.1.4 **Nenhum** dos 4 itens historicamente marcados nasce `locked` — disponibilidades
      e cobranças aparecem (DEC-15.1). O teste falha se alguém "corrigir" marcando. —
      **BE-419**

### 6.2 Escopo e projeto corrente (C1)

- [x] 6.2.1 O seletor de projeto troca **só** entre projetos com participação. — **BE-412,
      FE-393**
- [x] 6.2.2 Projeto inexistente e projeto sem participação, informados pelo seletor,
      respondem **o mesmo status**. — **BE-412**
- [x] 6.2.3 Nenhum cookie carrega o projeto corrente (regressão do D-28): o valor vem do
      servidor. — **DB-396, OPS-392**

### 6.3 Roteamento

- [x] 6.3.1 URL de área com registro selecionado abre **em aba nova** já com o registro
      carregado. — **BE-390**
- [x] 6.3.2 Área desconhecida responde **404 com tela de não encontrado** — nunca tela em
      branco, nunca rebaixamento silencioso. — **BE-390**
- [x] 6.3.3 O botão Voltar do navegador **navega dentro** do console. — **FE-397**
- [x] 6.3.4 `per_page` acima do teto é limitado. — **BE-423**

### 6.4 Mensagens

- [x] 6.4.1 O total da listagem respeita os filtros (regressão do `Message.all.count`). —
      **BE-424**
- [x] 6.4.2 ~~Pedir "Concluído" grava "Concluído"~~ → **DEC-73: a inversão é REPLICADA.**
      O golden test trava os DOIS sentidos (`admin_messages_spec.rb`) e reprova quem
      "consertar" sem uma DEC nova. — **BE-527**
- [x] 6.4.3 `limit`/`offset` de observadores são **aplicados** (regressão do D-88). —
      **BE-426**
- [x] 6.4.4 Observador duplicado no mesmo contexto é barrado **pelo índice único**, mesmo em
      requisições concorrentes. — **DB-392**
- [x] 6.4.5 Envio de mensagem exige sessão (ou, se Q-B17 mudar, é público **por rota** e com
      throttle). — **BE-531**

## 7. Paridade e registro

- [x] 7.1 Ledger: os `dropped` desta fatia com evidência — **BE-394, BE-396, BE-410,
      BE-411, BE-415, BE-420, BE-421, BE-422, BE-425, BE-532, BE-539, FE-398, FE-402,
      FE-524, FE-525, FE-539, DB-399, OPS-392, OPS-396, OPS-399, OPS-508, OPS-509,
      OPS-749, ENG-navkit**
- [x] 7.2 Ledger: os demais IDs de S2 para `migrated`.
- [x] 7.3 `improvements-log.md`: IMP-A11 (**observável**), IMP-A23 (**observável**), e a
      correção "Concluído" (DC-16) — que é observável e **não** se corrige em silêncio.
- [x] 7.4 `upstream-flags.md`: U7 (`Api::V1::Chat` montado duas vezes, uma sem o clamp de
      visitante), U12 (`useAutoRefresh` é helper de polling — Princípio 10).
- [x] 7.5 Levar ao usuário: **Q-B11** (o cliente espera um dashboard? é o maior descompasso
      entre paridade correta e impressão de venda), **Q-B15** (Google Analytics),
      **Q-B16** (correção do "Concluído"), **Q-B17** (envio anônimo de feedback),
      **Q-B20** (PWA entra na entrega?).
- [x] 7.6 Registrar que **PWA** (decidido SIM no Phase 0) se ancora nesta casca mas é a
      fatia **S16** — para a decisão não sumir (DC-18).


## Fechamento de órfãos do Phase 2 — menu, erros e o esquema de `feedback19`

Dez IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Estender `CONSOLE_NAV_ITEMS` / `useNavItems.ts` com `roles?: string[]` e
      `requiresProject?: boolean`, e mover o gate para **dado**, não `if` espalhado.
      Verificável: um papel novo muda o menu sem alterar componente. **Fecha: FE-441.**
- [x] F.2 Entradas de menu das 6 entidades de cadastro, cada uma com o seu `roles`.
      Verificável: Colaborador não vê as entradas de escrita. **Fecha: FE-050.**
- [x] F.3 Teste do menu por papel cobrindo **os dois lados** (o que aparece e o que **não**
      aparece) para og, admin, gerente e colaborador. Gate de menu testado só pela positiva
      passa com a regra invertida.
- [x] F.4 Páginas de erro 404 / 422 / 500 do console, coerentes com os estados vazio/erro da
      fatia. **Fecha: OPS-634.**
- [x] F.5 Conferir, **linha a linha**, que as seis tabelas de `feedback19` vistas por
      `data-schema` são as **mesmas** já construídas no Grupo B — e não uma segunda família:
      mensagens, estados, contextos, observadores, junção e notas. **Fecha: DB-594, DB-595,
      DB-732, DB-733, DB-734, DB-735.**
- [x] F.6 Seed de referência de estados (8) e contextos (4: Outros, Problema, Contato,
      Sugestão), idempotente. **Fecha: OPS-542 (parte).**
- [ ] F.7 **ABERTA — depende do ETL (S14).** O de-para está pronto e é determinístico
      (`AdminMessage::STATES` / `CONTEXTS`, 8 e 4 chaves), mas não há dado legado carregado
      neste repositório para converter nem para contar. O relatório sai junto com a carga.
      A migração de dados verificável dos estados/contextos existentes: um relatório
      que diz quantas linhas foram convertidas e quantas ficaram sem correspondência —
      nenhuma conversão silenciosa. **Fecha: OPS-542.**
