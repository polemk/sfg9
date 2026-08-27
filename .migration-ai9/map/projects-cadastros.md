# Migration map — sfg → ai9 · bloco **PROJETOS E CADASTROS**

> Phase 2. Cobre **290 IDs** de 3 capacidades:
> `openspec/specs/projects/spec.md` (110) · `openspec/specs/companies-carriers/spec.md` (94) ·
> `openspec/specs/availability/spec.md` (86).
>
> Toda linha `reuse`/`adapt` cita uma peça real da base **depois do trim**, conferida no
> repositório em 25/08/2026 (não apenas no `ai9-base-catalog.md`). Onde o catálogo ou as
> convenções estavam erradas, a correção está na seção **Correções ao catálogo / às convenções**.
>
> Nada aqui é código. Nada aqui refatora a base ai9 (Princípio 6b) — o que parece errado
> na base virou linha no `upstream-flags.md`.

---

## 0. Leitura obrigatória antes da tabela

### 0.1 O veredito de uma frase

**O domínio inteiro deste bloco é `build`.** Não existe projeto, empresa, portador,
fornecedor, segmento, garantia, padrão de disponibilidade nem lançamento em lugar nenhum da
base ai9 — nem model, nem tabela, nem tela. Procurar equivalente para forçar `adapt` seria
entregar abstração que não foi feita para o problema.

**O reuso real está em outro lugar e é grande:** autenticação, papel/hierarquia, anexos,
editor de texto rico, Action Cable, Grape + paginação Kaminari, React Query, design system,
`SideDrawer`, `ImageCropper`, `components/mobile/`, Sidekiq com retry. **Mesmo em `build` a
coluna "Equivalente ai9" está preenchida** — é exatamente o que impede alguém de
reimplementar upload, drawer ou tabela do zero.

### 0.2 Legenda de abreviações (cada uma é um arquivo real)

| Sigla | Arquivo(s) na base ai9 |
| ----- | ---------------------- |
| **GRAPE** | `backend/app/controllers/api/v1/base.rb` (montagem + `before { restrict_visitor_access! }`) |
| **CH** | `backend/app/controllers/api/v1/controller_helpers.rb` — `process_service_response`, `set_pagination_headers` (linhas 18-22), `authenticate_user!`, `require_og!` (41-47), `restrict_visitor_access!` (49-56) |
| **ARH** | `backend/app/services/concerns/api_response_handler.rb` — `success_response` / `error_response` / `not_found_response` / `validation_error_response` |
| **ENT** | `backend/app/controllers/api/entities/` (padrão `Grape::Entity` com `documentation:`) |
| **KAM** | gem `kaminari` (`backend/Gemfile:85`) + `set_pagination_headers` + CORS já expondo `X-Total-Count` (`backend/config/initializers/cors.rb`) |
| **AUTHH** | `backend/app/controllers/api/auth/v1/auth_helpers.rb` (JWT, `impersonated_by`, cookies httpOnly) + `backend/app/services/auth/token_service.rb` |
| **UT** | `backend/app/models/user_type.rb` — `hierarchy_level`, `higher_than?`, `lower_than?`, `seed_default_types!`, escopos `higher_than`/`lower_than` |
| **AS** | ActiveStorage + `active_storage_validations` (`Gemfile:8`) + `image_processing` (`Gemfile:10`); exemplo vivo em `backend/app/models/medium.rb` (`has_one_attached`, `optimized_url`, variantes) |
| **MED** | `backend/app/models/medium.rb` + `app/services/medium_service.rb` + `api/v1/{media,uploads,downloads}.rb` + `api/entities/medium.rb` |
| **SIDEKIQ** | gem `sidekiq` + `sidekiq-cron` (`Gemfile:37-38`), `backend/config/sidekiq.yml` (filas prefixadas por `APP_NAME`, inclusive `_low_priority`), `backend/config/initializers/sidekiq.rb`, `backend/app/jobs/` |
| **CABLE** | `backend/app/channels/` (`application_cable/`, `permissions_channel.rb`) + `frontend/src/hooks/useCable.ts` (`useCable`, `useChannel`) |
| **RQ** | React Query (`frontend/src/main.tsx`) + `frontend/src/lib/api/client.ts` + `endpoints.ts` + `tokenStore.ts` |
| **DS** | `frontend/src/components/ui/` — `Table`, `Card`, `Button`, `Input`, `Label`, `Badge`, `dialog`, `tabs`, `switch`, `drawer`, `Sheet`, `Tooltip`, `Progress`, `textarea`, `accordion`, `avatar` |
| **DRAWER** | `frontend/src/components/SideDrawer.tsx` (`open/onClose/title/children/footer`) |
| **SEL** | `frontend/src/components/ui/SearchableSelect.tsx` e `SearchableMultiSelect.tsx` — **filtro client-side sobre `options` já carregadas** |
| **CROP** | `frontend/src/components/ui/ImageCropper.tsx` + `frontend/src/components/ThumbnailPicker.tsx` |
| **RTE** | `frontend/src/components/RichTextEditor.tsx` — editor **Slate**, com `serializeToHTML` (:75) e `deserializeHTML` (:102); props `value: string` / `onChange: (v: string) => void` — **fala HTML nos dois sentidos** |
| **ATEXT** | **ActionText, vivo na base**: `backend/config/application.rb:12` (`action_text/engine`), tabela `action_text_rich_texts` (`schema.rb`), `backend/app/models/user.rb:18` (`has_rich_text :biography`), param em `api/v1/users.rb:190`, exposição em `api/entities/user.rb:33-49` (`biography_html` = `body.to_s`, `biography_text` = `to_plain_text`). **É um caminho ponta a ponta pronto para copiar linha a linha** |
| **NAV** | `frontend/src/hooks/useNavItems.ts` (fonte única do menu, **com o ponto de extensão por papel documentado nas linhas 27-32**) + `components/Sidebar.tsx` + `components/mobile/MobileBottomBar.tsx` |
| **MOB** | `frontend/src/components/mobile/` — `MobilePageLayout`, `MobileCard`, `MobileKPI`, `MobileContextSheet`, `MobileMenuActions`, `MobilePagination`, `MobileTopBar`, `MobileChartCard` |
| **CHART** | `frontend/src/components/charts/{RechartsBar,RechartsLine,RechartsPie,theme}.tsx` + `components/kpi/KpiCard.tsx` |
| **CRED** | `backend/app/models/credential.rb` + `api/v1/credentials.rb` + `frontend/src/features/credentials/` |
| **PAL** | `backend/app/models/permission_audit_log.rb` + `api/entities/permission_audit_log.rb` — **formato** de trilha a copiar (não é trilha genérica) |
| **HDR** | `frontend/src/components/PageHeader.tsx` |
| **THEME** | `frontend/src/styles/globals.css` (tokens `:root` + `.dark`) + `hooks/useTheme.ts` + `ThemeProvider`/`ThemeToggle` |

### 0.3 O que **cada** `build` de tela deste bloco herda, sem exceção

`ProtectedRoute` + `Layout` + `HDR` + `DS` + `THEME` (light **e** dark, marca Safegold) +
`RQ` (`useQuery`/`useMutation` + `invalidateQueries`) + `NAV` + `MOB` para as views estreitas.
Só está repetido na tabela quando muda alguma coisa.

### 0.4 O que **cada** `build` de endpoint deste bloco herda, sem exceção

`GRAPE` + `CH` + `ARH` + `ENT` + `KAM`, montado em `api/v1/base.rb` dentro de um `namespace`,
com `desc`/`params`/`http_codes` e resposta por `process_service_response`.
Só está repetido quando muda alguma coisa.

### 0.5 As quatro regras transversais que atravessam os 290 IDs

1. **Escopo (DEC-07/DEC-18)** — `companies`, `providers`, `project_availabilities`,
   `availability_entries`, `project_guarantees` e as conexões são **por projeto**;
   `carriers`, `carrier_groups`, `segments`, `sub_segments`, `availability_templates`
   (globais) e `project_guarantee_types` são **catálogo global**, com `R` ao Colaborador
   (DEC-18.4). O projeto corrente **nunca** vem do cliente.
2. **Paginação real (Q-04/D-20)** — todo `search` deste bloco passa a aplicar `limit`/`offset`
   de verdade, com total sem limite. É mudança visível: hoje as telas trazem tudo.
3. **Polling é proibido (Princípio 10 / D-86)** — progresso de job, bloqueio de padrão e
   recálculo chegam por **Action Cable invalidando query**, nunca por `setInterval`.
4. **Disponibilidades e cobranças nascem HABILITADAS (DEC-15.1)** — o `locked: true` do menu
   legado nunca funcionou (D-90) e as telas estão em uso. Porta-se o **efeito**, não a intenção.

### 0.6 O escopo por projeto — **desenho normativo** (contrato para os outros três blocos)

> **Leia isto antes de desenhar escopo no seu bloco.** `Project` e `Membership` nascem aqui
> (DB-080, DB-086, DB-087, BE-098, BE-099), e a base ai9 é **declaradamente single-tenant**
> — não há `tenant_id`, `account_id` nem `organization_id` em `backend/app/models/`, e
> `blog_intake_session.rb` chega a dizer isso em comentário. Portanto o mecanismo de escopo
> por projeto **não existe e é definido aqui, uma vez só**. Recebíveis, renegociações, risco,
> operações estruturadas, indicadores e contratos **apontam para este desenho** em vez de
> inventar o seu. Se algo aqui não servir ao seu caso, **me diga** — mudar aqui é barato,
> descobrir duas semânticas de escopo no Phase 4 não é.

**As quatro peças, e o que cada uma resolve:**

| # | Peça | Onde | Papel |
| - | ---- | ---- | ----- |
| 1 | `memberships` (`user_id`, `project_id`, `role`, único `(user_id, project_id)`) | DB-086 | **A verdade sobre quem enxerga o quê.** `role` é rótulo descritivo, **nunca** consultado para autorizar (DEC-18.6) |
| 2 | `users.current_project_id` (FK + índice) | DB-087 | O projeto corrente, resolvido **no servidor**. Nunca cookie, nunca campo escondido de formulário (fecha **D-28**) |
| 3 | `current_project!` em `backend/app/controllers/api/v1/controller_helpers.rb` | S0 | Resolve e **valida contra membership a cada request**; aborta 403/404 se o usuário não for membro. Aceita `X-Project-Id` **só** se houver membership (suporte a duas abas) |
| 4 | Concern `ProjectScoped` em `backend/app/models/concerns/` (hoje **vazio**) | S0 | `belongs_to :project` + `scope :for_project` + validação de presença |

**A regra de aplicação, em uma frase:**

> **O escopo é aplicado no endpoint, explicitamente, através de `current_project!` — nunca
> por `default_scope`.**

Por que **não** `default_scope`: ele vaza para `unscoped`, quebra `joins`/`includes` de forma
silenciosa, contamina jobs e seeds (que legitimamente cruzam projetos — OPS-081, OPS-121,
OPS-085 replicam padrões em **todos** os projetos) e, o pior, torna o escopo **invisível na
leitura do código**. O legado errou justamente por o escopo ser implícito: sempre que um
parâmetro chegava (`company_id`, `receivable_id`, `risk_operation_id`,
`structured_operation_id`, `project_guarantee_id`), o filtro de projeto era **descartado** —
é a família inteira D-01 / D-16 / D-29 / D-76 / D-100. Escopo explícito no endpoint torna
esse erro visível na revisão.

**A forma canônica (copie esta, não invente outra):**

```
# 1. o endpoint declara o escopo — uma linha, sempre visível
project = current_project!          # 403/404 se não houver membership
scope   = Receivable.for_project(project)

# 2. TODO filtro por id do cliente é aplicado DENTRO do escopo, nunca fora
scope = scope.where(id: params[:receivable_id]) if params[:receivable_id]

# 3. o project_id que vem do corpo da requisição é SEMPRE ignorado
```

**As cinco regras que valem para os quatro blocos:**

1. **`project_id` do cliente é sempre ignorado** — no `create` e no `update`. O projeto vem
   de `current_project!`. (O legado forçava no `create` e esquecia no `update` — BE-062.)
2. **Filtro por id nunca sobrepõe o escopo.** `x_id` é aplicado *dentro* do `for_project`.
   Resultado esperado quando o id é de outro projeto: **vazio**, não 403 — não se confirma a
   existência de registro alheio.
3. **`:id` fora do `permit`** em todo recurso (família D-60/D-68; DEC-15.2 exige para membership).
4. **Catálogo global não recebe escopo**: `carriers`, `carrier_groups`, `segments`,
   `sub_segments`, `availability_templates` globais, `project_guarantee_types`, `indicators`
   globais, `wallets`, `movement_kinds`, `receivable_kinds`, `resource_sources`,
   `risk_operation_types`, `structured_operation_types`, `risk_movement_types`,
   `resource_kinds` — leitura liberada ao Colaborador (DEC-18.4), escrita por papel.
   **A regra em uma frase: o menu esconde a tela de administração do catálogo, não o dado do
   catálogo.**
5. **Job, seed e rake não usam `current_project!`** — recebem `project_id` como argumento
   explícito. É por isso que o escopo não pode ser `default_scope`.

**O que isto entrega aos outros blocos:** um `current_project!` e um `ProjectScoped` prontos
ao fim do **S2**. Até lá, os blocos podem escrever `# TODO: escopo — ver §0.6` e seguir;
o que **não** podem é criar um segundo mecanismo.

### 0.7 Duas coisas da base que este bloco **não** usa (e por quê)

| Peça da base | Veredito | Evidência medida |
| ------------ | -------- | ---------------- |
| `Medium` para os logos | **não usar** | `backend/app/models/medium.rb:12` aceita só `image`/`video` — os 3 logos deste bloco *são* imagens, então o tipo não é o problema; o problema é que `media` **não tem dono nem escopo** (`schema.rb`: `title`, `description`, `identifier`, `active`, `media_type`, `display_order`, `external_url`), e um logo criado por lá aparece na galeria `/media` para qualquer autenticado. Ver **DC-02** e **Q-05**. *(Este bloco não tem nenhum anexo de documento/PDF — os 3 anexos são logos. O caso de PDF em `Medium`, que não funciona, é dos blocos `renegotiations` e `contracts`.)* |
| `assets_proxy_controller.rb` | **proibido** para qualquer arquivo deste bloco | Verificado: herda de `ActionController::Base` (linha 5), **zero autenticação**, serve `Rails.root.join('public','uploads', params[:path])` com `disposition: 'inline'` e mapeia inclusive `application/pdf` (linhas 6-24). Não há guarda de *path traversal* sobre `params[:path]`. É o padrão do **D-82**, veredito `corrigir`. Logo de projeto/portador/fornecedor é servido por **ActiveStorage** (URL assinada e expirável), nunca por aqui. **É achado da base compartilhada → pertence ao `upstream-flags.md`, não a um refactor nesta branch (Princípio 6b)** |

---

## 1. Fatias verticais propostas (ordem de execução)

Ordem por **dependência técnica** (DEC-17.1 revogou a ordenação por valor de demo):
dado → backend → tela. Dentro do bloco, `S1` desbloqueia FK; `S2` é a pedra angular
(é dela que sai o gate `projects.count > 0` e o escopo de tenant de **todo o Safegold**).

| Slice | Descrição (feature ponta a ponta, entregável) | IDs incluídos | Depende de | Prioridade |
| ----- | -------------------------------------------- | ------------- | ---------- | ---------- |
| **S0** | **Habilitadores compartilhados.** Backend: helpers Grape `require_role!` / `require_not_readonly!` / `current_project!` (papel + membership no servidor); trilha de auditoria genérica; canal de progresso de job. Frontend: `DataTable` (ordenação por cabeçalho + estados), `Pagination` (`X-Total-Count`), `AsyncSearchableSelect` (busca server-side com debounce), `MoneyInput`/`PercentInput` pt-BR, `EmptyState`/`ErrorState`, `useJobProgress` (Action Cable). **Todos entram na biblioteca compartilhada, nunca peça de uma tela só (Princípio 11).** | BE-079 · FE-053 · FE-061 · FE-079 · FE-052 · FE-062 · FE-066 · OPS-086 · OPS-087 · OPS-125 · OPS-126 · OPS-127 · OPS-128 | matriz de autorização (DEC-18) + papéis do bloco `auth-users` | **crítica** — trava S1..S8 |
| **S1** | **Catálogos globais**: Segmentos, Subsegmentos, Grupos de Portadores e Portadores (com estrutura de FIDC). Lista + busca + ordenação + paginação + CRUD + detalhe. | BE-067..078 · FE-060..068 · FE-075..078 · FE-061 · DB-057..066 · DB-072 · OPS-051 · OPS-052 · OPS-053 · OPS-056 · OPS-057 · OPS-058 · OPS-054 (parte catálogo) | S0 | **alta** — nada tem FK sem isto |
| **S2** | **Projeto: a pedra angular.** Tabela `projects`, `memberships`, projeto corrente do usuário, CRUD, detalhe, membros, marcas Safegold/BI, limpeza de projeto de treinamento, logo, observação, efeitos colaterais da criação. **Aqui nascem o gate `projects.count > 0` e o escopo de tenant do sistema inteiro.** | BE-080..101 · FE-080..099 · FE-105 · FE-106 · FE-118 · FE-119 · DB-080 · DB-086..091 · OPS-080 · OPS-085 · OPS-088 | S0, S1 (FK de segmento/subsegmento) | **alta** |
| **S3** | **Conexões do projeto**: projeto↔portador (nos dois sentidos) e projeto↔indicador (globais e específicos do projeto). | BE-102..109 · FE-100..104 · DB-081 · DB-082 · DB-092 | S1, S2; catálogo de `indicators` vem do bloco `indicators` | média |
| **S4** | **Empresas e Fornecedores** (escopo de projeto): lista, busca, paginação, CRUD, detalhe, documento CPF/CNPJ, logo, autopreenchimento por CNPJ. | BE-050..066 · FE-051..059 · FE-069..074 · DB-050..056 · DB-067..071 · OPS-050 · OPS-055 | S2 (escopo); **BE-052 depende de `risk_controls`** (bloco `risk`) | **alta** |
| **S5** | **Catálogo global de padrões de disponibilidade** ("Tipos de disponibilidade"): árvore de 3 níveis, numeração/posicionamento, reordenação, obrigatoriedade hierárquica, propagação para projetos. | BE-132..139 · FE-135..141 · DB-120 · DB-121 · DB-124 · DB-128 · DB-129 · DB-131 · DB-132 · DB-134 · DB-135 · OPS-121 | S0, S2 (propagação precisa de projeto) | média |
| **S6** | **Padrões de disponibilidade do projeto**: árvore do projeto, criar/editar, ativar/desativar/remover em segundo plano com bloqueio, progresso e liberação garantida. | BE-110..116 · BE-140..147 · FE-107..112 · FE-142..149 · DB-122 · OPS-081..084 · OPS-120 · OPS-122..125 · OPS-129 | S5, S2 | média |
| **S7** | **Painel de Disponibilidade e lançamentos**: grade hierárquica por data/empresa, consolidação geral, saldo acumulado, correção por dias úteis, indicadores e calendário. | BE-117 · BE-120..131 · BE-148 · BE-149 · FE-120..134 · DB-123 · DB-125..127 · DB-130 · DB-133 | S6, S4 (empresas) | média |
| **S8** | **Garantias do projeto e Tipos de garantia**: lista com filtros/ordenação/paginação, CRUD e catálogo global de tipos. | BE-118 · BE-119 · BE-700..706 · FE-113..117 · DB-083 · DB-084 | S2, S3 (portadores conectados), S1 | média |

> **Nota de sequenciamento honesta:** `BE-052` (resumo de limites de risco por empresa) e as
> contagens de "controles de risco" nas telas de Empresa e Portador **não fecham** sem a
> tabela `risk_controls`, que é do bloco `risk`. O S4 entrega tudo menos esses agregados, que
> ficam atrás de uma fatia de integração com o bloco `risk`.

---

## 2. Tabela item por item

### 2.1 `companies-carriers` — Backend (BE-050 … BE-079)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| BE-050 | build | GRAPE·CH·ARH·ENT·KAM | `api/v1/companies.rb` + `CompanyService` + `Api::Entities::Company` | Escopo por projeto corrente resolvido no servidor; `q`/`l`/`o` passam a **funcionar**; total sem limite | Paginação real (D-20); `company_id` deixa de furar o escopo (D-29) | **médio** — a tela hoje traz tudo; o usuário vai notar | S0, S2 |
| BE-051 | build | idem BE-050 | mesmo endpoint, `order_mode=dash` | Modo resumo por título asc., `q` ignorado | — | baixo | BE-050 |
| BE-052 | build | idem + `Company#risk_limits_on` | `CompanyService.risk_summary` | Agregados como **número** (formatação sai do domínio); N+1 eliminado; `date` validado no `params do` | Divisão por zero → 100% explícito; data inválida = 422, não 500 | **alto** — depende de `risk_controls` (bloco `risk`) | bloco `risk` |
| BE-053 | build | GRAPE·CH·ARH | `api/v1/companies.rb#form` | Sem projeto corrente → 422 explícito, não `NoMethodError` | — | baixo | S2 |
| BE-054 | build | idem | `CompanyService.create` | `project_id` **ignorado** do payload; erros em pt-BR nomeando o campo | Fecha D-23/D-29 (criar empresa em projeto alheio); `:id` fora do `permit` | baixo | S2 |
| BE-055 | build | idem | `CompanyService.update` | `project_id` ignorado no update | Ver **DC-04** (mover empresa entre projetos) | baixo | BE-054 |
| BE-056 | build | idem | `CompanyService.destroy` | Bloqueio por dependentes responde **422 real** | Fecha D-24 (o legado respondia `:ok ? :ok`) | baixo | BE-054 |
| BE-057 | build | idem | `GET /companies`, `GET /companies/:id` | Rotas que **respondem** (o legado dava `MissingTemplate`) | — | baixo | BE-050 |
| BE-058 | build | ActiveRecord validations | `app/models/company.rb` | `title` único **por projeto** (índice composto), `project` obrigatório | Sem `NoMethodError` de `project` nulo; agregados sem N+1 | baixo | DB-050 |
| BE-059 | build | GRAPE·CH·KAM | `api/v1/providers.rb` | Escopo de projeto **obrigatório** (sem projeto → 422, não catálogo geral) | Fecha D-23/D-29; paginação+ordenação juntas (D-20) | **médio** — mudança visível | S0, S2 |
| BE-060 | build | idem | `#form` | 404 para fornecedor inexistente | — | baixo | BE-059 |
| BE-061 | build | idem + AS | `ProviderService.create` | `project_id` do servidor; nada de `destroy` sobre registro não persistido | — | baixo | S2 |
| BE-062 | build | idem | `ProviderService.update` | `title`/`integration_key` obrigatórios **também no update**; `project_id` ignorado | Fecha D-23 (mover fornecedor por campo escondido) | baixo | BE-061 |
| BE-063 | build | idem | `ProviderService.destroy` | 422 real quando há renegociações | Fecha D-24 | baixo | bloco `renegotiations` (checagem) |
| BE-064 | **adapt** | **CRED** (`app/models/credential.rb`, `api/v1/credentials.rb`) | `ReceitaWsService` + `api/v1/providers.rb#cnpj_lookup` | Token sai de `ENV['rws_api_token']` e vai para `Credential`; CNPJ validado **no servidor** antes de chamar o provedor; rate-limit e timeout | Nunca commitar chave (ver `legacy-defects.md`); resposta normalizada, não crua | **médio** — D-27: religar ou descartar (**Q-03**) | S4 |
| BE-065 | build | GRAPE·CH | `GET /providers`, `GET /providers/:id` | Rotas que respondem; tela de detalhe passa a existir | D-22: o HTML legado existe, portar é barato | baixo | BE-059 |
| BE-066 | build | AR validations | `app/models/provider.rb` | Documento validado (CPF/CNPJ), único **por projeto**; `cnaes` e `atividades` em **JSON único** | Fecha D-25 (YAML + JSON na mesma tabela); `integration_key` única de verdade | **médio** — leitura do YAML legado exige carga segura | DB-055 |
| BE-067 | build | GRAPE·CH·KAM | `api/v1/carriers.rb` | **Catálogo global** (DEC-07); busca simétrica (mesmo resultado com/sem ordenação) | Paginação real (D-20) | **médio** — mudança visível | S0 |
| BE-068 | build | idem | `#form`, `GET /carriers/:id` | Detalhe passa a ser alcançável | D-22: portar (**DC-08**) | baixo | BE-067 |
| BE-069 | build | idem | `CarrierService.create/update` | `bank_code` **string** (preserva `001`); `financial_agent` validado por inclusão (FIDC/Securitizadora/Factoring/Cliente); dinheiro nunca castado em silêncio | Fecha D-25; vocabulário de **contraparte financiadora**, não "fornecedor genérico" | **médio** — migração precisa reconstituir zeros à esquerda | DB-057, DB-059 |
| BE-070 | build | idem | `CarrierService.destroy` | Exclusão **bloqueada** por `risk_controls`/conexões/recebíveis; **nunca** cascata | Fecha D-24 (a assimetria mais perigosa do legado: excluir portador apagava limites) | **alto** se replicado errado | bloco `risk` |
| BE-071 | build | AR validations | `app/models/carrier.rb` | Só `title` obrigatório; **título duplicado continua permitido** (preservado de propósito, "Cloud #7036"); cidade formatada com fallback | Comportamento **preservado** — não é bug | baixo | DB-057 |
| BE-072 | build | GRAPE·CH·KAM | `api/v1/carrier_groups.rb` | Ordenação por título funciona (o legado dava 500) | Fecha D-21 e D-20 | baixo | S0 |
| BE-073 | build | idem | `CarrierGroupService` | Exclusão de grupo com portadores → **422** no servidor, não só botão escondido | Fecha D-24 (`group_id` órfão) | baixo | DB-058 |
| BE-074 | build | idem | `app/models/carrier_group.rb` | `carriers_count` com default `0` e consistente | Fecha OPS-058 | baixo | DB-063 |
| BE-075 | build | GRAPE·CH·KAM | `api/v1/segments.rb` | Ordenação por título **e** por chave; paginação real | Fecha D-20 | baixo | S0 |
| BE-076 | build | idem | `SegmentService` | **Criação passa a funcionar** (o legado falhava 100% das vezes por `user_id` fora do `permit`); `user_id` vem da sessão | Fecha D-21 — feature quebrada em produção nasce funcionando | baixo | DB-064 |
| BE-077 | build | idem | `api/v1/sub_segments.rb` | Ordenação resolvida pelo **próprio** subsegmento | Remove o acoplamento acidental com `Segment` | baixo | S0 |
| BE-078 | build | idem | `SubSegmentService` | Exclusão bloqueada por projetos vinculados → 422 | Fecha D-24 | baixo | DB-066 |
| BE-079 | **adapt** | **CH:41-56** (`require_og!`, `restrict_visitor_access!`) + **GRAPE:14** (`before { restrict_visitor_access! }`) + **UT** (`hierarchy_level`) + **AUTHH** | `controller_helpers.rb` ganha `require_role!(*roles)`, `require_not_readonly!`, `current_project!` — usados pelos **6 cadastros** e por todo o bloco | Autorização deixa de ser de view e passa a ser **do servidor**; `user_is_readonly` promovido de flag de UI a checagem que nega todo verbo de escrita; `target_mode` deixa de escolher caminho de arquivo | Fecha D-17/D-23/D-34; `restrict_visitor_access!` já é **exatamente** a forma do `user_is_readonly` — é o gancho, não um mecanismo paralelo | **alto** — é a base de segurança de tudo | matriz DEC-18, papéis (bloco `auth-users`) |

### 2.2 `companies-carriers` — Frontend (FE-050 … FE-079)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| FE-050 | **adapt** | **NAV** (`useNavItems.ts:27-32` — o ponto de extensão por papel está **documentado no próprio arquivo**) | `useNavItems.ts` ganha `roles?: string[]` + `requiresProject?: boolean`; `Sidebar` e `MobileBottomBar` **não mudam** (já leem daí) | Menu por papel + gate `projects.count > 0`, como no `create_console_menu` (D-118) | Regra de navegação sai de helper ERB e vira registro declarativo | baixo | S0 |
| FE-051 | build | DS(`Table`,`Card`,`Badge`)·HDR·RQ·MOB | `pages/companies/CompaniesPage.tsx` | Colunas Empresa/Portadores/Controles; estados de carregando, vazio e **falha** | Falha deixa de ser silenciosa | baixo | S0, BE-050 |
| FE-052 | build | RQ + `DS/Input` | `useDebouncedSearch` (compartilhado, S0) | Debounce; entrada só de espaços ignorada | Um hook para as ~12 buscas do bloco | baixo | S0 |
| FE-053 | build (**lado servidor é `reuse` de KAM**) | **KAM** cobre o servidor por inteiro. No front, `MOB/MobilePagination` **não atende**: só tem anterior/próxima (sem primeiro/último e sem limite por página, que o FE-053 exige) e usa cor literal `border-white/10 bg-white/5` em vez de token de tema — generalizá-lo seria editar componente da base (Princípio 6b) | `components/ui/Pagination.tsx` (**novo, compartilhado**); `MobilePagination` fica intocado para telas estreitas | Controles de página **alteram de fato** a consulta; total é o real | Fecha D-20/D-53: hoje o input mostra 20 e o servidor recebe 50 | **médio** — mudança visível | S0 |
| FE-054 | build | DS | filtros de `CompaniesPage` | **Só filtros que existem** ficam na tela | Ver **DC-05** (filtros `kind`/`state` fantasmas) | baixo | FE-051 |
| FE-055 | build | DS(`dialog`)·MOB(`MobileMenuActions`,`MobileContextSheet`) | linha + menu de contexto | Ações por papel/readonly; "Remover" coerente com **todos** os bloqueios (não só `risk_controls`) | Critério do botão = critério do servidor | baixo | BE-056 |
| FE-056 | build | **DRAWER**·DS(`Input`,`Label`) | painel lateral de Empresa | Erros em pt-BR nomeando o campo; some o texto herdado "Essa construtora não pode ser alterada" | Um `SideDrawer` para os 6 cadastros | baixo | DRAWER |
| FE-057 | build | DS(`dialog`)·RQ | exclusão a partir da lista | Reflete o resultado **real** (422 aparece) | Fecha D-24 no front | baixo | BE-056 |
| FE-058 | build | DS(`tabs`,`Card`)·`date-fns` | `CompanyDetailPage` | Data formatada corretamente (o legado tinha `dd/mm/aaaa- HH:MM`) | — | baixo | BE-057 |
| FE-059 | build (**decisão: não portar a aba vazia**) | — | `CompanyDetailPage` só com abas funcionais | A aba "Controles de Risco" do legado **não é listada, o parcial é vazio e nenhuma action a renderiza** | Ver **DC-06** | baixo | FE-058 |
| FE-060 | build | DS·HDR·MOB | `CarriersPage` | Colunas Título/Grupo/Agente/Cidade/# Projetos **com paginação** (o legado não tinha) | Fecha D-20 | baixo | FE-053 |
| FE-061 | build | DS(`Table`) — hoje é **só primitivo** (`Table/TableHeader/TableBody/...`), não há `DataTable` | `components/ui/DataTable.tsx` (**novo, compartilhado**) | Cabeçalho ordenável **ordena de verdade**; coluna não ordenável não parece ordenável | Fecha D-21 (clicar em "Grupo" dava **500**) | **médio** — lacuna real do ai9 | S0 |
| FE-062 | build | FE-052 | busca de portadores | Vazio cita o termo buscado | — | baixo | FE-052 |
| FE-063 | build | DS·MOB | linha de portador | Fallback `-`; clique abre "Relações" | — | baixo | S3 |
| FE-064 | build | DRAWER·DS·SEL | formulário de portador | 13 campos, incluindo a **estrutura de FIDC** (`net_worth`, `bank_code`, `senior_accounts`, `subordinated_accounts`, `%`) | Vocabulário de contraparte financiadora nos rótulos | baixo | BE-069 |
| FE-065 | build | — | campo "% contas subordinadas" | Derivado, sem divisão por zero | Ver **DC-09** (derivado no servidor × coluna editável) | baixo | DC-09 |
| FE-066 | build | — (não existe input monetário na base) | `components/ui/MoneyInput.tsx` + `PercentInput.tsx` (**novos, compartilhados**) | Envia número; nunca depende de reformatação concorrente | Fecha a corrida do legado (`Rails.fire` + reformat) que gravava `1` em silêncio | **médio** — lacuna real | S0 |
| FE-067 | **build?** | CROP·AS | logo do portador | **Ou** o upload existe e funciona, **ou** não há vestígio dele | **Q-04**: no legado o HTML está comentado mas o backend aceita `logo` | baixo | DC-10 |
| FE-068 | build | DS(`tabs`,`Card`) | `CarrierDetailPage` | Tela passa a ser **alcançável** | D-22: HTML+SCSS já existem no legado, portar é barato (**DC-08**) | baixo | BE-068 |
| FE-069 | build | DS·MOB·`avatar` | `ProvidersPage` | Colunas Título/Projeto/# Renegociações/avatar | Permissão do botão "Cadastrar" alinhada à matriz (hoje diverge dos outros cadastros) | baixo | BE-059 |
| FE-070 | build | DS(`avatar`) | linha de fornecedor | Iniciais quando não há logo; **sem ação inerte** | Ver **DC-07** ("relações de fornecedor" é código morto) | baixo | FE-069 |
| FE-071 | build | DS | alternância CPF/CNPJ | Campos do bloco não escolhido **não são enviados** (no legado "desabilitar" era só CSS) | — | baixo | BE-066 |
| FE-072 | build | — | máscara + validação de documento | Avisa documento **incompleto**, não só inválido | — | baixo | FE-071 |
| FE-073 | build | RQ + BE-064 | autopreenchimento por CNPJ | Recurso volta a existir (hoje está duplamente morto) | Depende de **Q-03** (D-27) | **médio** | BE-064 |
| FE-074 | **adapt** | **CROP** (`ImageCropper`, `ThumbnailPicker`) + AS | upload de logo do fornecedor | Limite verificado **antes** de enviar; preview e recorte pelo componente da base | **Não portar paperclip** | baixo | OPS-051 |
| FE-075 | build | DS·MOB | `CarrierGroupsPage` | Toast se refere ao **grupo** (o legado dizia "O portador foi excluído") | — | baixo | BE-072 |
| FE-076 | build | DRAWER·DS | painel de grupo | — | — | baixo | DRAWER |
| FE-077 | build | DS·DRAWER | `SegmentsPage` | Criação **funciona**; exclusão bloqueada é comunicada | Fecha D-21 + D-24 no front | baixo | BE-076 |
| FE-078 | build | DS·DRAWER | `SubSegmentsPage` | Textos próprios de subsegmento (o placeholder legado dizia "Ex: Segmento Comercial") | — | baixo | BE-078 |
| FE-079 | build | DS·THEME | `components/ui/{EmptyState,ErrorState,LoadingState}.tsx` (**novos, compartilhados**) | Estados consistentes nos 6 cadastros, textos do domínio, **light e dark**, marca Safegold | Some "Essa construtora não pode ser alterada" das **seis** entidades | baixo | S0, THEME |

### 2.3 `companies-carriers` — Dados (DB-050 … DB-074)

Todos `build` (tabelas novas). Herdam as convenções do ai9: `ActiveRecord::Migration[8.0]`,
classe e cabeçalho em pt-BR explicando o porquê, colunas em inglês, **`id: :uuid` com
`gen_random_uuid()`** (domínio novo — `pgcrypto` já habilitado), índices explícitos com
`name:`/`unique:`/parcial quando couber, `comment:` nas colunas, `decimal(14,2)` para dinheiro,
`enum` string do Rails 8, `dependent:` sempre explícito.

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| DB-050 | build | padrão de migração ai9 (`backend/db/migrate/`, `schema.rb`) | `companies` | FK `project_id` + **índice único composto `(project_id, title)`** | Fecha a corrida de unicidade só-de-aplicação | baixo | DB-080 |
| DB-051 | build | — | `companies.has_safegold_management` | Ver **DC-01** (derivar × carimbo datado) | Decisão única para as **6** tabelas | **alto** — muda relatório | DC-01 |
| DB-052 | build | AS | `providers` | Índices em `project_id`, `cnpj`, `cpf`, `integration_key`; `is_active` **boolean** | Busca por documento passa a usar índice | baixo | DB-080 |
| DB-053 | build | — | `providers.document_type` + `document` | Tipo e valor explícitos | Ver **DC-11** (par `(tipo, documento)`) | baixo | DC-11 |
| DB-054 | build | — | campos ReceitaWS + `cnpj_fetched_at` | Carimbo de "consultado em"; `abertura`/`data_situacao` como `date` de verdade | Rastreabilidade do snapshot cadastral | baixo | BE-064 |
| DB-055 | build | `jsonb` (Postgres, DEC-05) | `providers.cnaes` + `.atividades` | **Um formato só**: `jsonb` | Fecha D-25; leitura do YAML legado com carga segura (classes permitidas) | **médio** — ETL | DEC-05 |
| DB-056 | **adapt** | **AS** + MED (`medium.rb` como exemplo vivo de `has_one_attached` + variantes) | `Provider#logo` | Sai `public/system/logos/:id/…` do Paperclip, entra o storage do ai9 | Ver **DC-02** (`Medium` × `has_one_attached`) | baixo | DC-02 |
| DB-057 | build | — | `carriers` | `bank_code` **string**; `subordinated_accounts_percent` decimal (não float); `bank_name` redundante removido | Fecha D-25 | **médio** — ETL precisa reconstituir `001` | DC-12 |
| DB-058 | build | — | `carriers.group_id` | FK + índice, exclusão do grupo recusada pelo banco | Fecha o `group_id` órfão | baixo | DB-063 |
| DB-059 | build | `enum` string Rails 8 | `carriers.financial_agent` | Conjunto fechado (FIDC/Securitizadora/Factoring/Cliente) | Divergentes reportados no dry-run, não inseridos calados | baixo | BE-069 |
| DB-060 | build | — | `carriers.city`, `.uf` | UF normalizada em 2 caracteres maiúsculos | Não reconhecidos reportados | baixo | OPS-057 |
| DB-061 | build | — | `carriers.legacy_id` | Preservada (DEC-12), única | Única prova de proveniência 2016-2021 | baixo | DEC-12 |
| DB-062 | **adapt** | AS | `Carrier#logo` | Idem DB-056 | Dry-run informa **quantos portadores têm arquivo de fato** (FE-067) | baixo | DC-02 |
| DB-063 | build | — | `carrier_groups` | `carriers_count` com **default 0** | Fecha OPS-058 | baixo | — |
| DB-064 | build | — | `segments` | `title` único **no banco** | Fecha D-26 no caminho: `segment_id = 1` nunca mais | baixo | — |
| DB-065 | build | — | `segments.legacy_id` | Preservada (DEC-12) | — | baixo | DEC-12 |
| DB-066 | build | — | `sub_segments` | Catálogo **independente** de `segments` | Ver **DC-13** (hierarquia segmento→subsegmento) | baixo | DC-13 |
| DB-067 | build | — | `projects.segment_id`, `.sub_segment_id` | FK + índice, ambos opcionais | Fecha D-26 | baixo | DB-080 |
| DB-068 | build | — | `project_to_carrier_connections` | **Única ponte**; portadores da empresa são derivados do projeto | Nenhuma tabela empresa↔portador inventada | baixo | DB-081 |
| DB-069 | build | — | `risk_controls.company_id`/`.carrier_id` | Política **simétrica**: bloquear, nunca cascatear | Fecha D-24 (a assimetria mais perigosa) | **alto** | bloco `risk` |
| DB-070 | build | — | `receivable_entries.company_id`/`.carrier_id` | FK + índice | Órfãos reportados no dry-run | médio | bloco `receivables` |
| DB-071 | build | — | `renegotiations.company_id`/`.provider_id` | FK + índice | Órfãs reportadas no dry-run | médio | bloco `renegotiations` |
| DB-072 | build | — | FK + índices dos 6 cadastros | O legado tinha **zero** `add_foreign_key` | Mandato de performance (Princípio 9) | baixo | S1 |
| DB-073 | build | — | etapa de introspecção do ETL | Aborta com relatório diante de estrutura desconhecida | DEC-04; já há 2 provas (`default_position`, `contracts.description`) | **alto** | bloco `data-schema` |
| DB-074 | build | — | relatório de volumetria | Medida antes do cutover | — | baixo | bloco `data-schema` |

### 2.4 `companies-carriers` — Operação (OPS-050 … OPS-058)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| OPS-050 | **adapt** | **CRED** | `Credential` "receitaws" + `ReceitaWsService` | Credencial por ambiente, timeout, cache, indisponibilidade tratada | Chave **nunca** no código | médio | Q-03 |
| OPS-051 | **adapt** | **AS** (`active_storage_validations`, `image_processing`) + MED | validação e storage de logos | Tipo **real** do arquivo verificado | Fecha o `MediaTypeSpoofDetector#spoofed? → false` do legado (detecção **desligada**) | baixo | DC-02 |
| OPS-052 | build (mínimo) | — | só `carriers.legacy_id` | **Pipeline `Legacy::execute` NÃO é portado** (DEC-12) | Correlação preservada, código morto fora | baixo | DEC-12 |
| OPS-053 | build (mínimo) | — | só `segments.legacy_id` | Idem | Idem | baixo | DEC-12 |
| OPS-054 | **adapt** | `backend/db/seeds.rb` + `backend/db/seeds/` | `db/seeds/catalogos.rb` × `db/seeds/demo.rb` | **Semente de catálogo separada da de demonstração** | O legado misturava — o bloco de empresas está marcado no próprio código como "seed feito somente para vídeo de aprovação" | baixo | `demo-seed-design.md` |
| OPS-055 | build | SIDEKIQ + rake | `lib/tasks/fix_company_links.rake` | Idempotente, com pré-visualização e log | O legado rodava `update_all` a mão no console, sem log | médio | S4 |
| OPS-056 | build | AR + Postgres `ILIKE` com bind (DEC-05) | `scope :search` nos 6 models | Sem `Dev.ilike` interpolando SQL de adapter | `100%` e `a'b` tratados como texto literal | baixo | DEC-05 |
| OPS-057 | build | padrão de `api/v1/countries.rb` (constante `COUNTRIES` no próprio arquivo) | `api/v1/br_states.rb` (constante `UF`) | Cidade/UF são dado do cadastro; **sem geocoder** | `geocoder`/`city-state` não são portados | baixo | — |
| OPS-058 | build | `counter_cache` do AR | `carrier_groups.carriers_count` | Contagem sempre bate com a lista | Fecha a divergência que decidia se o botão de exclusão aparecia | baixo | DB-063 |

---

### 2.5 `projects` — Backend (BE-080 … BE-101)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| BE-080 | build | GRAPE·CH·KAM | `api/v1/projects.rb` + `ProjectService` | **Escopo por membership**; busca `ILIKE`; ordenação e paginação aplicadas | Fecha D-20; hoje a lista volta inteira | **médio** — visível | S0, DB-086 |
| BE-081 | build | idem | `order_mode=dash` | Ordena por `updated_at` asc., ignora `q` | — | baixo | BE-080 |
| BE-082 | build | idem | filtros `importing_id`/`project_id` | Filtros **sempre dentro do membership** | Fecha D-29 (qualquer autenticado lia qualquer projeto por id) | **alto** se replicado | DEC-07 |
| BE-083 | build | idem | `#autocomplete` | `ILIKE` (o legado usava `LIKE` cru, case-sensitive no Postgres) e **com limite** | Consistente com a listagem | baixo | BE-080 |
| BE-084 | build | UT (`higher_than`/`lower_than`) | `#form` | Lista de responsáveis filtrada por hierarquia de papel | Hierarquia sai de `user_decorator` e vira consulta por `UserType.hierarchy_level` | baixo | bloco `auth-users` |
| BE-085 | build | `Auth::*` (`magic_login_service`, convite) | `ProjectService.create_with_new_owner` | Cria projeto + usuário responsável **e envia link para o usuário definir a própria credencial**; transação atômica | Fecha D-38 neste fluxo: o legado montava **username e senha em texto plano** para a view. Nenhuma senha é montada, exibida ou enviada | **alto** — segurança | bloco `auth-users` |
| BE-086 | build | idem | `create` sem responsável | Projeto pertence a quem criou | — | baixo | BE-085 |
| BE-087 | build | idem | `create` com responsável existente | Responsável em branco → **422**, não 500 | Ver **DC-14** (o criador perdia a posse) | médio | DC-14 |
| BE-088 | build | SIDEKIQ·CABLE | `ProjectCreationJob` + `SeedGlobalTemplatesJob` | Cada tarefa com **progresso próprio** (no legado as duas escreviam no mesmo `job_id`) | Sem criação duplicada dos vínculos padrão | médio | OPS-080, OPS-081 |
| BE-089 | build | GRAPE·CH | `ProjectService.update` | Troca de responsável garante o vínculo; marca de BI **não muda** por aqui | — | baixo | BE-085 |
| BE-090 | build | OPS-086 (trilha) | evento na trilha de auditoria | Onboarding vira evento auditado | Ver **DC-15** (não há consumidor conhecido) | baixo | OPS-086 |
| BE-091 | build | GRAPE·CH·ARH | `ProjectService.destroy` | Bloqueio por dependentes responde **422 real** e a tela **não navega** | Fecha D-24: o legado respondia `:ok` e o JS redirecionava — "removido com sucesso" sem ter removido | médio | BE-080 |
| BE-092 | build | SIDEKIQ | `ProjectResetService` | Segmento resolvido **por configuração**, nunca id fixo; projeto de treinamento não pode ser removido | Fecha D-26 (`segment_id = 1` hardcoded) | médio | DB-064 |
| BE-093 | build | — | `PATCH /projects/:id/safegold_management` | Ver **DC-01** | Uma regra única para as 6 tabelas | **alto** | DC-01 |
| BE-094 | build | — | `PATCH /projects/:id/bi` | Marca comercial | Ver **DC-16** (D-31: `has_bi` não é lido em lugar nenhum) | baixo | DC-16 |
| BE-095 | build | padrão `smart_id`/`by_any_id` **documentado** em `ai9-conventions.md §4` mas **sem nenhuma implementação viva na base** (verificado: 0 ocorrências em `backend/app`) | `Project#slug` + `integration_key` + cor | Slug único, gerado do nome | Ver **DC-17** (slug imutável após criação) | médio | DC-17 |
| BE-096 | build | AS + AR validations | `app/models/project.rb` | Nome único, dono, slug e situação obrigatórios; logo com limite; **erros em pt-BR** | O legado tinha `translate_every_key` e **nunca o chamava** | baixo | DB-089 |
| BE-097 | **adapt** | **ATEXT** — o caminho ponta a ponta de `biography` (`user.rb:18` → `users.rb:190` → `entities/user.rb:33-49`) | `has_rich_text :availability_note` em `Project` + param + `expose :availability_note_html` | Sanitização passa a ser do ActionText (`ActionText::Content` escapa na renderização); **anexo bloqueado no servidor** (ActionText os aceita por padrão) | O legado bloqueava anexo **só no cliente** (`trix-file-accept` + botão escondido). O único trabalho novo é restringir anexo — o resto é copiar `biography` | baixo | DB-088 |
| BE-098 | **adapt** | **AUTHH** (`auth_helpers.rb`, payload com `impersonated_by` — claims são extensíveis) + **CH** (`api.current_user`) | `current_project!` em `controller_helpers.rb` + `users.current_project_id` | Projeto corrente vem da **sessão do servidor**, validado contra membership a cada request; troca só entre projetos do usuário | Fecha **D-28**, a falha mais grave do legado (trocar o cookie trocava de tenant). Ver **DC-03** (onde o projeto corrente mora) | **alto** — é o tenant de quase todo o sistema | DC-03, DB-087 |
| BE-099 | build | CH (`require_role!`) | `api/v1/memberships.rb` + `MembershipService` | **3 condições da view viram regra de servidor** (DEC-15.2/DEC-18.5): não-readonly, não remove o dono (`project.user_id`), não remove a si mesmo. `:id` fora do `permit`. Criar/remover: OG/Admin/Gerente. Busca com termo vazio devolve lista válida | Fecha **D-28** + **D-34**: hoje qualquer sessão se auto-adiciona a qualquer projeto e **ganha o grupo "Gestão" inteiro** | **alto** — segurança | DEC-18.5, S0 |
| BE-100 | build | — | `GET /users/:id/projects` | Só o que o solicitante pode ver | Ver **DC-18** (aba informativa × vincular/desvincular) | baixo | DC-18 |
| BE-101 | build + **dropped com evidência** | — | endpoints reais | `index`/`detail` de projeto passam a responder 200. As rotas comprovadamente mortas **não são portadas** | `config/routes.rb:75` aponta para controller inexistente (`project_to_availability_connections`) e as views `detail/connection_template/**` chamam helpers inexistentes. Ver **DC-19** | baixo | DEC-09 |

### 2.6 `projects` — Conexões e disponibilidade do projeto (BE-102 … BE-119)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| BE-102 | build | GRAPE·CH·KAM | `api/v1/project_carrier_connections.rb` | Tipo de entidade vem de **conjunto fechado** (nunca `constantize` de parâmetro); estado "conectado" resolvido em **consulta única** | Fecha a enumeração de classes por `constantize` **e** o N+1 (`o.carriers.include?(t)` por linha) | **alto** se replicado | S1, S2 |
| BE-103 | build | idem | conectar/desconectar em lote | Lote vazio → 400; resultado **por item**; desconectar o que não está conectado não dá 500 | Corrige a condição invertida do legado (`unless errors.blank?`) que só avaliava o último item | médio | BE-102 |
| BE-104 | build | idem | **um** endpoint de candidatos | Dois endpoints quase idênticos do legado viram um | Menos superfície | baixo | BE-102 |
| BE-105 | build | idem | remover conexão isolada | Action que **funciona** (o `before_action` legado preenchia `@connections`, plural → `NoMethodError`) | — | baixo | BE-103 |
| BE-106 | build | idem | `api/v1/project_indicator_connections.rb` | Mesma correção de `constantize` do BE-102 | — | **alto** se replicado | bloco `indicators` |
| BE-107 | build | idem | candidatos: globais + do projeto | Nenhum específico de outro projeto aparece | — | baixo | DB-092 |
| BE-108 | build | idem | conectar/desconectar indicadores em lote | Mesmos 4 defeitos do BE-103, corrigidos | — | médio | BE-106 |
| BE-109 | build | idem | excluir indicador específico | Indicador **global** não pode ser excluído: 422, não 500 | — | baixo | BE-107 |
| BE-110 | build | GRAPE·CH | `api/v1/project_availabilities.rb#tree` | Sem projeto corrente → **erro de pré-condição**, não `NoMethodError`; árvore ordenada por índice | Fecha o `1+N` por nível e a ordenação por `JOIN (VALUES …)` | médio | S6, DB-122 |
| BE-111 | build | idem | `#form` | "Faz parte de" só oferece pais válidos para o nível pretendido | — | baixo | BE-110 |
| BE-112 | build | idem | criar/editar padrão do projeto | Hierarquia limitada a 3 níveis; título único no nível; **nível derivado do pai de forma determinística** | Fecha o ` \|= ` (OR bit a bit) do legado, que só funcionava por acidente com `0`/`nil` | médio | BE-137 |
| BE-113 | build | **SIDEKIQ** (retry nativo) · CABLE | `ActivateProjectTemplateJob` | Bloqueio liberado em `ensure`, **inclusive na falha**; enfileiramento recusado → 409 | Fecha **D-05**: o legado engolia a exceção, `destroy_failed_jobs? false`, sem retry, `unlocked!` só no caminho feliz → **template travado para sempre** | **alto** | S6 |
| BE-114 | build | idem | `DeactivateProjectTemplateJob` | **A regra roda no serviço, antes de enfileirar**: padrão obrigatório e padrão com dependentes obrigatórios não desativam | Fecha **D-04/D-33**: no legado a guarda existia e **nunca era executada no fluxo real** (e ainda filtrava por `project_id: self.id`) | **alto** | BE-113 |
| BE-115 | build | idem | `RemoveProjectTemplateJob` | Lançamentos vinculados tratados **explicitamente**; bloqueio liberado na falha | Fecha a divergência entre `is_deletable?` (dica de UI) e `background_removal` (que apagava `entries.destroy_all` mesmo assim) | **alto** — dado financeiro | DC-20 |
| BE-116 | build | — | reordenação/recálculo em cascata | Posições consistentes após criar/ativar/desativar/remover/mover | Fecha o custo **quadrático** (os 3 `import` rodavam dentro do loop de 1º nível) | médio | DC-21 |
| BE-117 | build | GRAPE·CH·AUTHH | `api/v1/projects/:id/availability` | **Autenticado e escopado**; empresa inexistente → 422 | Fecha **D-01** (IDOR: `ApplicationController` vazio + `Project.find` sem escopo lia valor financeiro de qualquer projeto). **Não se replica um IDOR** | **alto** — segurança | BE-098 |
| BE-118 | build | GRAPE·CH·KAM | `api/v1/project_guarantees.rb` | Ordenar por "Título" funciona; `project_guarantee_id` **não fura** o escopo; paginação real | Fecha D-32 (ordenava por `risk_operations.title`, tabela fora do join → erro SQL) e D-29 | médio | S8 |
| BE-119 | build | idem | CRUD de garantias | `edit` funciona (o legado fazia `@companies.first.id` com `@companies` nunca definido); só portadores **conectados** ao projeto; remoção bloqueada responde 422 | Fecha D-24 | baixo | BE-103 |

### 2.7 `projects` — Tipos de garantia (BE-700 … BE-706)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| BE-700 | build | GRAPE·CH·KAM | `api/v1/project_guarantee_types.rb` | Catálogo **global** com `R` ao Colaborador (DEC-18.4); busca/ordenação/paginação reais; **401 sem credencial** | Fecha D-20 + D-23 (`requires_current_user? == false`: o endpoint respondia para anônimo) | médio | S0 |
| BE-701 | build | CH (`require_role!`) | `#form` (novo) | Sem papel autorizado → **403 no servidor** | Fecha D-23 (o gate og/admin/manager só existia na view) | baixo | S0 |
| BE-702 | build | idem | `#form` (edição) | Inexistente → 404 | — | baixo | BE-701 |
| BE-703 | build | idem | `create` | `user_id` **da sessão**, ignorando o do corpo; título único | Fecha D-23 (aqui o legado não sobrescrevia o `user_id`, diferente dos outros controllers) | baixo | BE-701 |
| BE-704 | build | idem | `update` | Ver **DC-22** (chave de integração recalculada × congelada) | — | baixo | DC-22 |
| BE-705 | build | idem | `destroy` | Tipo em uso → 422 real | Fecha D-24 | baixo | BE-703 |
| BE-706 | build | GRAPE·CH | `GET /project_guarantee_types(/:id)` | Rotas que respondem (o legado dava `MissingTemplate` → 500) | — | baixo | BE-700 |

### 2.8 `projects` — Frontend (FE-080 … FE-119)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| FE-080 | build | DS(`Card`,`Badge`)·HDR·RQ·MOB(`MobileCard`) | `pages/projects/ProjectsPage.tsx` | Cards com nome, chave, progresso e menu; estados de carregando/vazio/**falha** | Falha deixa de ser silenciosa | baixo | BE-080 |
| FE-081 | build | FE-052 (hook de busca, S0) | busca incremental | Debounce; só-espaços ignorado; vazio cita o termo | — | baixo | S0 |
| FE-082 | build | DS(`dialog`)·MOB(`MobileMenuActions`) | card + menu de contexto | Editar/remover **só** para papel autorizado | Critério do menu = critério do servidor | baixo | S0 |
| FE-083 | **adapt** | **CABLE** (`useCable.ts` — `useChannel` invalidando query) | `ProjectProgressChannel` + `useJobProgress` | Percentual avança **sozinho** | Fecha **D-86**: no legado não havia nem polling nem push — só recarregando a lista à mão. **Polling é proibido (Princípio 10)** | médio | S0, OPS-087 |
| FE-084 | build | DS(`dialog`)·RQ | remoção pela lista | Erro do servidor aparece e o projeto **permanece** na lista | Fecha D-24 no front (o tratamento de erro estava **comentado**) | baixo | BE-091 |
| FE-085 | build | DS·DRAWER·SEL | formulário de projeto | Nome, chave, situação, segmento, subsegmento, endereço, observação, responsável, data de baixa, logo | — | baixo | BE-096 |
| FE-086 | **adapt** | **SEL** (`SearchableSelect.tsx` — hoje **filtra client-side** sobre `options` já carregadas) | `AsyncSearchableSelect` (S0) — `SearchableSelect` ganha `onSearch`/`loading`, ou nasce uma variante irmã | Escolher entre criar novo responsável, indicar existente ou nenhum; **busca server-side** (a lista de usuários não cabe no cliente) | Sem isto, o autocomplete carregaria a base de usuários inteira | **médio** — lacuna real do ai9 | S0, BE-084 |
| FE-087 | **adapt** | **CROP** (`ImageCropper`, `ThumbnailPicker`) + AS | upload e preview do logo | Escolha do logo **sobrevive** a erro de validação em outro campo | O legado resetava o input de arquivo em qualquer `ajax:error` | baixo | DC-02 |
| FE-088 | build | `date-fns` (já na base) | campo de data de baixa | `dd/mm/aaaa`, enviado correto | — | baixo | — |
| FE-089 | build | RQ (`useMutation`) | salvamento do formulário | **Uma** requisição por salvamento | Ver **DC-23** (o legado registrava salvamento a cada `keyup`) | baixo | DC-23 |
| FE-090 | build | `sonner` (toasts, já na base) | mensagens de resultado | Distingue "cadastrado" de "**atualizado**"; campos em pt-BR | O legado dizia "cadastrado com sucesso" ao editar e mostrava a chave técnica em negrito | baixo | FE-089 |
| FE-091 | build | DS(`tabs`,`Card`)·`date-fns` | `ProjectDetailPage` | Data de criação bem formatada (o legado: `dd/mm/aaaa- HH:MM`) | — | baixo | BE-101 |
| FE-092 | build | DS(`switch`) | alternar "Gerido pela Safegold" | Bloqueado para readonly, com aviso | — | baixo | BE-093 |
| FE-093 | build | DS(`switch`) | alternar "BI contratado" | **Ids HTML distintos** (o legado usava `id="is_active_{project.id}"` nos dois interruptores) | Clicar no rótulo do BI altera o BI | baixo | BE-094 |
| FE-094 | build | DS(`dialog`) | ações rápidas do detalhe | Projeto de treinamento oferece "limpar", não "remover" | — | baixo | BE-092 |
| FE-095 | build | DS(`avatar`,`Badge`) | lista de membros | Dono do projeto e o próprio usuário **sem** ação de remover | As 3 condições do DEC-15.2 também no front, espelhando o servidor | baixo | BE-099 |
| FE-096 | **adapt** | **SEL** → `AsyncSearchableSelect` (S0) | adicionar membro | Busca incremental de usuários; campo some para quem não pode | Mesmo componente do FE-086 | médio | S0 |
| FE-097 | build | DS(`dialog`) | remover membro | Mensagem se refere ao **projeto** | O legado dizia "O membro foi removido da empresa" | baixo | BE-099 |
| FE-098 | build | DS(`Card`,`Badge`) | cartão "Portadores" | Ordem alfabética, com grupo; vazio explícito | — | baixo | BE-102 |
| FE-099 | **reuse** | **RTE** — `value: string` / `onChange: (v: string) => void`, HTML dos dois lados (`serializeToHTML`:75 / `deserializeHTML`:102), casando exatamente com o `*_html` do **ATEXT** | cartão "Observação - Disponibilidade" | Renderiza a marcação sanitizada; some quando vazio | Substitui o Trix do legado **sem escrever componente nenhum** — os contratos já batem | baixo | BE-097 |
| FE-100 | build | DS·HDR | tela de conexões projeto↔portador | Título coerente com o sentido; "voltar" retorna à **origem** | — | baixo | BE-102 |
| FE-101 | build | DS(`switch`)·RQ | item de conexão | Estado **confirmado pelo servidor**; falha reverte o item | O legado era otimista e divergia do servidor em erro parcial | baixo | BE-103 |
| FE-102 | build | DS·HDR | tela "Indicadores específicos" | Botão de cadastrar some para readonly | — | baixo | BE-106 |
| FE-103 | build | DS(`Badge`,`accordion`) | item global × específico | Global: conectar/desconectar. Específico: editar/ativar/excluir. Inativo visualmente distinto | — | baixo | BE-107 |
| FE-104 | build | RQ | ações do indicador específico | Ações **continuam utilizáveis** após a primeira execução | O `preventDoubleSubmit` do legado era ativado e **nunca restaurado** | baixo | BE-108 |
| FE-105 | build | NAV·HDR·DS(`SearchableSelect`) | seletor de projeto na barra do console | Só os projetos do usuário, em ordem alfabética | — | baixo | BE-098 |
| FE-106 | **adapt** | **AUTHH** + `tokenStore.ts` (access token **só em memória**) | resolução do projeto corrente | Vem da **sessão**, não de estado do navegador | Fecha **D-28** no front: o legado apagava o cookie e forçava a **segunda** opção do select, sem justificativa no código | **alto** | BE-098, DC-03 |
| FE-107 | build | DS(`Table`)·MOB | tela "Disponibilidades" do projeto | Árvore de 3 níveis com indentação e ordem por posição | — | baixo | BE-110 |
| FE-108 | **adapt** | **CABLE** + DS(`Badge`,`Tooltip`) | estados do padrão na lista | Bloqueado / inativo / específico visíveis; **motivo do bloqueio consultável**; menu nunca vazio | O legado deixava o menu de "global + com filhos" **sem nenhum item** | médio | S0, BE-147 |
| FE-109 | build | DRAWER·DS | formulário de padrão | Na edição, o que não pode mudar aparece como somente leitura **com a razão** | Ver **DC-24** (no legado só o título é editável, sem explicação) | baixo | DC-24 |
| FE-110 | build | RQ (busca sob demanda) | dependência pai↔níveis | Níveis derivados do pai; **nenhum padrão de outro projeto no payload** | Fecha o vazamento do legado: `data-templates` embutia **todos** os `AvailabilityTemplate` no HTML | **alto** — vazamento | BE-111 |
| FE-111 | build | RQ·`sonner` | ativar/desativar pela lista | Mensagem fala em **padrão de disponibilidade**; ação reutilizável | O legado dizia "Indicador ativado/deasativado" (texto de outro módulo, com erro de grafia) | baixo | BE-113 |
| FE-112 | build | DS(`dialog`)·RQ | remover padrão pela lista | Confirmação; padrão fica **bloqueado até concluir** | O legado usava `M.SUCESS` (constante inexistente) e renderizava `data-deletable` sem nunca lê-lo | baixo | BE-115 |
| FE-113 | build | `DataTable`+`Pagination` (S0) | tela "Garantias do Projeto" | **Uma** consulta por interação; paginação real | O legado executava o proxy duas vezes por clique de ordenação | médio | S0, BE-118 |
| FE-114 | build | DS | item de garantia | Valor em reais; ações por permissão | — | baixo | BE-119 |
| FE-115 | build | DRAWER·DS·`MoneyInput`(S0) | formulário de garantia | **Um único critério** de "o projeto tem portador" | O legado usava `active_risk_controls_carriers` no botão e `project.carriers` no formulário | baixo | BE-119 |
| FE-116 | build | `DataTable`(S0)·DRAWER | tela "Tipos de garantia" | Busca, ordenação por título e chave; ações por papel | — | baixo | BE-700 |
| FE-117 | build | DRAWER·DS | formulário de tipo de garantia | Erro de dependência **nomeia o campo** | — | baixo | BE-705 |
| FE-118 | build | DS(`tabs`) | aba "Projetos" no detalhe do usuário | Mostra de quais projetos o usuário participa | Ver **DC-18** | baixo | BE-100 |
| FE-119 | **adapt** | **NAV** (`useNavItems.ts:27-32`) | menu do domínio de projetos | Gate `projects.count > 0` + papel; **Disponibilidades nasce visível (DEC-15.1)** | Fecha D-90 pelo efeito: o `locked` continua existindo como mecanismo (lido do item, não do grupo) mas **nenhum item nasce marcado** | médio | FE-050, DEC-15.1 |

### 2.9 `projects` — Dados (DB-080 … DB-092)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| DB-080 | build | padrão de migração ai9; **nome `projects` está livre** (verificado: nenhum model, nenhuma `create_table "projects"` em `backend/db/schema.rb`; existe `work_projects`, que é órfã e já está no `upstream-flags.md §7`) | `projects` | `responsible_id` é **referência de usuário de verdade** (era `string`); FK e índices em `user_id`, `segment_id`, `slug`, `integration_key`; marcas como **boolean**; `is_active` com `null: false` | Nome único e slug único **no banco** (o legado dependia de validação de aplicação) | médio | S1 |
| DB-081 | build | — | `project_to_carrier_connections` | FK + **único `(project_id, carrier_id)`**; `legacy_*` preservadas (DEC-12) | Fecha a corrida que criava duplicatas | baixo | DB-080 |
| DB-082 | build | — | `project_indicator_connections` | FK + único; `is_active` **não é aceito** (o controller legado o permitia sem a coluna existir) | — | baixo | bloco `indicators` |
| DB-083 | build | — | `project_guarantees` | `observation` **text** (era `string(255)` com `textarea` na tela); `value` `decimal(14,2)`; FK+índices | Fim do risco de truncamento | baixo | DB-084 |
| DB-084 | build | — | `project_guarantee_types` | Título e chave únicos no banco; exclusão de tipo em uso bloqueada | — | baixo | — |
| DB-085 | build | — | `availability_templates` (uma tabela, globais **e** de projeto) | **Uma estrutura hierárquica ordenável** no lugar de 3 colunas numéricas + string `position`; `top_parent_id` sem default `0`; índices em `project_id` e `parent_template_id` | Fecha "órfãos apontando para o id 0" e a reordenação quadrática (BE-116) | **médio** — remodelagem | DC-21, DB-131 |
| DB-086 | build | — | `memberships` | `role` como **enum estável** (responsavel/participante/coordenador/gestor); único `(user_id, project_id)` | DEC-18.6: `role` é **rótulo descritivo**, nunca consultado para autorizar. Remoção deixa de ser `delete_all` sem callbacks | médio | DB-080 |
| DB-087 | **adapt** | **AUTHH** + `backend/app/models/user.rb` | `users.current_project_id` (FK + índice) | Sempre corresponde a um projeto do qual o usuário é **membro**; reavaliado quando o vínculo some | Fecha **D-28** no modelo: era o tenant de fato do sistema, **sem FK, sem índice e sem validação**. Ver **DC-03** | **alto** | DB-086, BE-098 |
| DB-088 | **reuse** | **ATEXT** — a tabela `action_text_rich_texts` **já existe** no `schema.rb` da base | nenhuma coluna nova, nenhuma migration | O texto vive em `action_text_rich_texts` polimórfico, como o `biography` do `User` | **Zero migration.** A migração de dados sanitiza o conteúdo formatado do legado ao inserir | baixo | BE-097 |
| DB-089 | **adapt** | **AS** (exemplo vivo: `medium.rb` com `has_one_attached` + `optimized_url`/variantes) | `Project#logo` | Sai Paperclip em disco local; ausência de logo é **explícita** | O legado tratava a string literal `"missing.jpg"` como ausência | baixo | DC-02 |
| DB-090 | build | — | marca de gestão nas 6 tabelas filhas | Ver **DC-01** | **A decisão mais consequente do bloco** | **alto** | DC-01 |
| DB-091 | build | — | colunas `legacy_*` | Preservadas (DEC-12) | Única prova de proveniência dos borderôs 2016-2021 | baixo | DEC-12 |
| DB-092 | build | — | `indicators.scope` explícito | Global × de projeto **sem depender de campo nulo** | Hoje `project_id IS NULL` governa a interface inteira | baixo | bloco `indicators` |

### 2.10 `projects` — Operação (OPS-080 … OPS-089)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| OPS-080 | build | **SIDEKIQ** (`sidekiq.yml`, retry nativo) | `LinkDefaultMembersJob` | Retry automático; falha **visível** ao esgotar | Fecha D-05 (`destroy_failed_jobs? false`, job falho sumia na fila) | médio | S0 |
| OPS-081 | build | SIDEKIQ·CABLE | `SeedGlobalTemplatesJob` | Hierarquia preservada; projeto não fica **silenciosamente incompleto** | Fecha D-05 + a dependência de ordem de criação dos globais | médio | OPS-120 |
| OPS-082 | build | SIDEKIQ | `ActivateProjectTemplateJob` | Bloqueio liberado em `ensure`, com ou sem sucesso | Fecha D-05 (padrão travado para sempre) | **alto** | BE-113 |
| OPS-083 | build | SIDEKIQ | `DeactivateProjectTemplateJob` | Idem + recálculo dos somatórios | Fecha D-05 | **alto** | BE-114 |
| OPS-084 | build | SIDEKIQ | `RemoveProjectTemplateJob` | Idem + reordenação; padrão volta utilizável na falha | Fecha D-05 | **alto** | BE-115 |
| OPS-085 | build | SIDEKIQ | `LinkDefaultUserToProjectsJob` | Erro **registrado e visível**; demais vínculos preservados | O `rescue` do legado era **vazio** | médio | OPS-080 |
| OPS-086 | build | **PAL** (`permission_audit_log.rb` + `api/entities/permission_audit_log.rb`) — o **formato** a copiar; `paper_trail` está no Gemfile e **não é usado em nenhum model** | trilha de auditoria genérica (`AuditEvent`) + `api/v1/audit_events.rb` | Criação, replicação, ativação, desativação, remoção e onboarding auditados, com descrição em pt-BR; **consulta exige autorização** | Ver **Lacuna L-05** e **Q-06** (ligar `paper_trail` é decisão de plataforma → `upstream-flags.md`) | médio | S0 |
| OPS-087 | **adapt** | **CABLE** (`useCable.ts`, `useChannel`) | `ProjectProgressChannel` + `useJobProgress` | Percentual avança na tela **sem recarregar** | Fecha D-86. **Polling é proibido (Princípio 10)** | médio | S0 |
| OPS-088 | **reuse** | **AS** + `image_processing` (`Gemfile:10`); a receita inteira já está em `medium.rb#optimized_url`/`small_url` (`variant(resize_to_limit:, format: :webp)` + fallback no `rescue`) | derivados do logo do projeto | Variantes geradas sob demanda, como no `Medium` | Substitui o pipeline do Paperclip **sem escrever pipeline nenhum** | baixo | DB-089 |
| OPS-089 | build | rake + AuditEvent | `lib/tasks/fix_project_data.rake` | Idempotente, com pré-visualização e log persistente | O legado rodava `fix_after_global_remove` e `fix__7412` **a mão no console**, sem rake, sem agendamento e sem log | médio | OPS-086 |

---

### 2.11 `availability` — Lançamentos (BE-120 … BE-131)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| BE-120 | build | GRAPE·CH·KAM | `api/v1/availability_entries.rb#search` | `q`/`l`/`o` passam a **existir de fato**; empresa inválida → 422 (não cai em "consolidação geral" calado); grade montada em consultas **agregadas** | Fecha D-07/D-20 e o N+1 (uma consulta por padrão) | **médio** — visível | S6, S4 |
| BE-121 | build + **dropped** | — | um caminho só | A rota `index` vestigial **não é portada** | Ver **DC-19** (DEC-09: descartar só com evidência) | baixo | DEC-09 |
| BE-122 | build | GRAPE·CH·ARH | `AvailabilityEntryService.create` | Duplicidade → 422; sem resíduo em falha | Sem `destroy` sobre registro não persistido | baixo | DB-123 |
| BE-123 | build | idem | `.update` | **Uma única gravação** (o legado fazia `update` + `save`); consolidação geral **não é editável nem por envio direto**; padrão bloqueado → 409 | Fecha o gatilho do decaimento composto (**DC-25**) e o bloqueio que só existia na UI | **alto** — valor financeiro | DC-25, BE-147 |
| BE-124 | build | idem | `.destroy` | Exclusão **não cria registro** (no legado `parent_entry` era chamado antes do destroy e **criava** o pai) | Reconsolidação sem efeito colateral | médio | DC-26 |
| BE-125 | build | — | consolidação geral (mirror) | Ver **DC-27** (`is_cumulative`/`is_debit` na consolidação) | Projeto sem empresas devolve zero, sem erro | **alto** — muda número exibido | DC-27 |
| BE-126 | build | — | valor de padrão com filhos | Ver **DC-27** (sinal de débito em nó intermediário) e **DC-28** (`is_credit?` comparando string traduzida) | Filho bloqueado tratado de forma consistente com a tela | **alto** — muda número exibido | DC-27, DC-28 |
| BE-127 | build | `date-fns` no front; cálculo **no servidor** | correção por dias úteis | Correção aplicada **uma única vez**; valor digitado preservado | Ver **DC-25** (D-02, decaimento composto) e **DC-29** (D-03, feriados) | **alto** — dinheiro | DC-25, DC-29 |
| BE-128 | build | — | saldo acumulado no 1º nível | Acumulado **determinístico**: não depende de quais células já foram preenchidas; desativados fora da conta | Fecha o comportamento não determinístico do legado | **alto** — muda número | BE-126 |
| BE-129 | build | AR `transaction` | propagação em cascata | **Atômica**; guarda de ciclo | O legado fazia saves recursivos + upsert em massa **sem transação** e com `validate: false` | **alto** | BE-125 |
| BE-130 | build | — | materialização de derivados | **Ler a grade não cria registro**; derivado identificável como derivado | Ver **DC-30** (materialização implícita × cálculo sob demanda) | **alto** | DC-30 |
| BE-131 | build | AR validations | `app/models/availability_entry.rb` | Unicidade `(project, company, template, date)` **garantida por índice**; título derivado do padrão | Fecha a corrida da unicidade só-de-aplicação | baixo | DB-133 |

### 2.12 `availability` — Catálogo global de padrões (BE-132 … BE-139)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| BE-132 | build | GRAPE·CH·KAM | `api/v1/availability_templates.rb#search` | Busca por **substring** (não só prefixo) e **sem `default_position`**; catálogo vazio não gera SQL inválido | Fecha D-06/D-07/D-20. Hoje **qualquer texto digitado derruba a requisição** | médio | **Q-01** (D-06) |
| BE-133 | build | GRAPE·CH | detalhe e formulários | Detalhe funciona **também** para padrão de projeto | O legado chamava `.projects`, associação **inexistente** → `NoMethodError` | baixo | BE-132 |
| BE-134 | build | GRAPE·CH·SIDEKIQ | `create` global | **A obrigatoriedade escolhida no formulário é respeitada**; propagação para projetos existentes é **opção do usuário** | Fecha o `is_mandatory \|= 1` (todo global nascia obrigatório) e o `should_insert_on_existing_projects` com default 1 **nunca exposto** — toda criação disparava job em **todos** os projetos | médio | DB-132, OPS-121 |
| BE-135 | build | idem | `update` global | Posição recalculada também no update; colisão de número impedida | Ver **DC-31** (propagar `is_adjusted`/`is_cumulative` aos derivados) | médio | DC-31 |
| BE-136 | build | idem | `destroy` global | Desvínculo em cascata **completo e transacional**; falha comunicada | Elimina a necessidade da rotina manual `fix_after_global_remove`. Fecha D-24 | médio | OPS-129 |
| BE-137 | build | — | numeração/posicionamento | Nível derivado do pai de forma determinística; pai inexistente → 422; **criação concorrente não colide** | Fecha o ` \|= ` bit a bit (2 herdando de 5 virava 7) e o `NoMethodError` em `ensure_top_parent` | médio | DB-131 |
| BE-138 | build | — | reordenação | Movimento inválido **recusado no servidor**; custo linear | Ver **DC-21** (a reordenação não é exposta em nenhuma tela) | médio | DC-21 |
| BE-139 | build | AR validations | obrigatoriedade hierárquica | Cadeia superior precisa ser obrigatória | — | baixo | BE-137 |

### 2.13 `availability` — Padrões do projeto (BE-140 … BE-149)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| BE-140 | build | GRAPE·CH·KAM | `api/v1/project_availabilities.rb#tree` | Projeto zerado devolve lista vazia (não SQL inválido); `q`/`l`/`o` funcionam; inativos identificados | Fecha D-07/D-20 | médio | BE-110 |
| BE-141 | build | idem | formulários | Sem projeto corrente → pré-condição explícita; campos imutáveis identificados **com a razão** | Ver **DC-24** | baixo | DC-24 |
| BE-142 | build | idem | `create` | Projeto **do servidor**; `:id` fora do `permit`; erros em pt-BR; unicidade inclui o 3º nível | Fecha D-23/D-29 (criar padrão em projeto alheio por campo escondido) e o mass assignment de PK | médio | BE-098 |
| BE-143 | build | idem | `update` | Padrão bloqueado → 409; renomear **não renumera** | Ver **DC-32** (assimetria global × projeto no `before_validation`) | baixo | DC-32 |
| BE-144 | build | SIDEKIQ·CABLE | ativar padrão do projeto | **Idempotente** (segunda ativação → 409); falha ao enfileirar é erro, não sucesso; bloqueio liberado em `ensure` | Fecha D-05 + D-24. Ver **DC-33** (ativar com pai inativo) | **alto** | S0, DC-33 |
| BE-145 | build | SIDEKIQ | desativar padrão do projeto | Guarda de obrigatoriedade **no serviço, antes de enfileirar** | Fecha **D-04/D-33**: pela tela era possível desativar padrão obrigatório | **alto** | BE-114 |
| BE-146 | build | SIDEKIQ + AR `transaction` | remover padrão do projeto | Lançamentos vinculados tratados **explicitamente**; remoção **atômica**; global não é removível pela rota do projeto | Fecha a remoção destrutiva, irreversível e sem rollback do legado (`entries.destroy_all` contornando `restrict_with_error`) | **alto** — dado financeiro | DC-20 |
| BE-147 | build | CABLE | bloqueio de padrões | Bloqueio **termina junto com a operação**, com ou sem sucesso; vale **no servidor**, não só na UI | Fecha D-05: `background_removal` nunca desbloqueava — padrão **bloqueado para sempre** sem caminho de recuperação | **alto** | S0 |
| BE-148 | build | — | consolidação por padrão base | **Semântica única de "total"** | Ver **DC-34** (o legado mistura `value` no total geral e `virtual_value` nos cards) | **alto** — muda número | DC-34 |
| BE-149 | build | GRAPE·CH·AUTHH | `api/v1/projects/:id/availability` | **Autenticado e escopado**; mês inválido → 422; JSON **sem dupla serialização** | Fecha **D-01** (IDOR). **Não se replica um IDOR** | **alto** — segurança | BE-117 |

### 2.14 `availability` — Frontend (FE-120 … FE-149)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| FE-120 | build | DS(`Card`)·HDR·RQ·MOB(`MobilePageLayout`) | `pages/availability/AvailabilityPage.tsx` | Duas colunas; URL coerente com a seção; falha dos indicadores **aparece** | O callback de erro do legado era **vazio** | baixo | S0, BE-148 |
| FE-121 | build | DS(`SearchableSelect`) | seletor de visão por empresa | Troca recarrega indicadores e grade | — | baixo | S4 |
| FE-122 | build | `date-fns` + `react-day-picker`/DS | calendário pt-BR | Dias com lançamento marcados; faixa consistente | Ver **Lacuna L-06** (não há componente de calendário na base) | médio | L-06 |
| FE-123 | **adapt** | **MOB** (`MobileTopBar`, `MobilePageLayout`, `MobileContextSheet`) | seleção de data em tela estreita | **Uma** fonte de verdade para "é estreito" (`hooks/useMobile.ts`), no cliente | O legado decidia no servidor por user agent **e** no cliente por detecção própria, que podiam discordar | baixo | MOB |
| FE-124 | **adapt** | **CHART** (`components/kpi/KpiCard.tsx`) | indicador de quantidade | Conta lançamentos com valor ≠ 0 | — | baixo | CHART |
| FE-125 | **adapt** | **CHART** (`KpiCard`, `RechartsBar`) | indicadores por padrão base | **Sinal negativo visível no próprio valor**, além da cor | O legado exibia em **módulo** e sinalizava só por vermelho — ambíguo e inacessível | baixo | CHART |
| FE-126 | **reuse** | **RTE** (modo leitura) | bloco de observação no painel | Some quando vazio | Mesmo componente do FE-099 | baixo | BE-097 |
| FE-127 | build | DS(`Table`) + `DataTable`(S0) | grade hierárquica | 3 níveis com indentação; folha editável, nó com filhos mostra total | Ver **DC-35** (expandir/recolher está **comentado** no legado) | médio | DC-35 |
| FE-128 | build | `EmptyState`/`ErrorState`(S0) | estados da grade | Carregando / sem data / sem padrões / sem resultado / **falha** | O callback de falha era vazio; corrige também o português ("Você", "possui") | baixo | S0 |
| FE-129 | build | `MoneyInput`(S0) | campo de valor | Vírgula ou ponto, 2 casas, aviso de separador duplo; natureza da operação **legível** | O legado exibia o código `C`/`D` cru | baixo | S0 |
| FE-130 | build | RQ(`useMutation`)·`sonner` | salvamento na grade | Guarda de envio duplo **por célula**, não em `$('form')` global; mensagem distingue **criado** de alterado | Elimina o efeito colateral global do legado | baixo | BE-122 |
| FE-131 | build | DS(`dialog`) | excluir lançamento | Oferecida só onde se aplica | — | baixo | BE-124 |
| FE-132 | build | CH(`restrict_visitor_access!` no servidor) | modo somente-leitura e consolidação | **Mesmo critério no cliente e no servidor** | Fecha D-23: no legado o bloqueio era **exclusivamente de interface** | médio | BE-123 |
| FE-133 | build | DS(`Badge`,`Tooltip`) | marcador de não cumulativo | Explicação consultável | — | baixo | DS |
| FE-134 | build | DS(`Badge`,`Tooltip`) | marcador de corrigido | **Valor digitado e valor gravado, ambos visíveis** | O usuário digitava X e via Y, sem nenhuma indicação | médio | BE-127 |
| FE-135 | build | `DataTable`(S0)·HDR | tela "Tipos de disponibilidade" | Catálogo global na ordem hierárquica | — | baixo | BE-132 |
| FE-136 | build | busca com debounce (S0) | busca de padrões globais | Passa a **funcionar** | Hoje qualquer texto quebra a requisição e a lista só para de atualizar, sem mensagem (**Q-01**) | médio | Q-01 |
| FE-137 | build | `EmptyState`/`ErrorState`(S0) | estados da lista global | Falha deixa de ser silenciosa | — | baixo | S0 |
| FE-138 | build | DS·MOB(`MobileMenuActions`) | linha de padrão global | Indentação; ações por permissão | `_child_widget.html.erb` (usa `default_position`, sem emissor) **não é portado** — código morto | baixo | DB-134 |
| FE-139 | build | DRAWER·DS(`switch`) | formulário de padrão global | **Obrigatoriedade aparece na tela** (não existia); nenhum padrão de outro projeto no payload | Fecha o vazamento do `AvailabilityTemplate.all` serializado em atributo `data-` | **alto** — vazamento | BE-134 |
| FE-140 | build | DS(`Card`,`tabs`) | detalhe do padrão | Funciona para padrão de projeto | O legado chamava `.projects` (inexistente) e quebrava a tela | baixo | BE-133 |
| FE-141 | build | NAV + CH(`require_role!`) | permissão de cadastro no catálogo | **Mesmo critério no servidor** (403 por API) | Fecha D-23 | médio | S0 |
| FE-142 | build | `DataTable`(S0) | tela "Disponibilidades" do projeto | Cadastro conforme permissão | Nasce **habilitada** (DEC-15.1) | baixo | BE-140 |
| FE-143 | build | `EmptyState`/`ErrorState`(S0) | estados da lista do projeto | Falha visível; some a mensagem de "busca sem resultado" inalcançável | — | baixo | S0 |
| FE-144 | build | RQ·`sonner` | ligar/desligar pela lista | Controle **utilizável após a primeira ação**; mensagem fala em **disponibilidade** | Fecha o `preventDoubleSubmit` nunca resetado e o texto "Indicador ativado/deasativado" | baixo | BE-144 |
| FE-145 | build | DS·MOB(`MobileContextSheet`) | menu de contexto do padrão | Menu **nunca vazio**, mesmo para global bloqueado; clicar na linha abre o detalhe | Fecha o `ReferenceError` de `openDetail(id, title)` e a constante inexistente `M.SUCESS` | baixo | BE-147 |
| FE-146 | **adapt** | **CABLE** + DS(`Badge`,`Tooltip`) | estados visuais do padrão | Bloqueado / desativado / específico, com motivo, autor e data | Ver **DC-36** (estilos `.disabled`/`.project_availability_completed` sem emissor) | baixo | DC-36 |
| FE-147 | build | DRAWER·DS | formulário de padrão do projeto | Textos do domínio; nenhum padrão de outro projeto no payload | Some "Essa construtora não pode ser alterada" | baixo | FE-139 |
| FE-148 | build | RQ (busca server-side) | níveis derivados do pai | Pai de **outro projeto** → operação recusada | Fecha o vazamento: o filtro usava o JSON de todos os padrões de todos os projetos | **alto** — vazamento | BE-142 |
| FE-149 | build | RQ(`invalidateQueries`) | recarregar a lista | **Um** controle, funcional | O legado registrava dois handlers, um para seletor inexistente | baixo | RQ |

### 2.15 `availability` — Dados (DB-120 … DB-135)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| DB-120 | build | padrão de migração ai9 | `availability_templates` | FK e índices (o legado tinha **zero**); booleanos de verdade; `top_parent_id` sem default `0` | Fecha os "órfãos apontando para o id 0" | médio | DB-085 |
| DB-121 | build | — | escopo global (`project_id` nulo + marca explícita) | `has_children?` consulta a **classe certa** | O legado declarava `class_name: "ProjectAvailabilityTemplate"` **dentro do model global** | baixo | DB-120 |
| DB-122 | build | — | padrão de projeto | Projeto obrigatório; vínculo opcional ao global de origem; **únicos** cobrindo o 3º nível e "um por global por projeto" | Fecha a unicidade só-de-aplicação | médio | DB-120 |
| DB-123 | build | — | `availability_entries` | FK + índices `(project_id, date)`, `(template_id, date)` e **único `(project_id, company_id, template_id, date)`**; `value` `decimal(14,2)` | A maior tabela do módulo não tinha **nenhum** índice | **alto** — performance | DB-133 |
| DB-124 | build | — | `templates.is_adjusted` boolean | Par obrigatório com DB-125 | — | baixo | DB-125 |
| DB-125 | build | — | `entries.original_value` | Valor digitado preservado ao lado do corrigido | **Divergentes reportados no dry-run** — parte da base pode ter valor corrigido várias vezes (**DC-25**) | **alto** — dinheiro | DC-25 |
| DB-126 | build | — | marca explícita de consolidação | Consolidação **não é inferida por empresa nula** | O legado usava `after:` (sintaxe MySQL) numa base Postgres (DEC-05); e `fix__7412` reatribuía empresa nula à primeira empresa — a migração precisa distinguir consolidação legítima de dado sujo | **alto** — ETL | DC-27 |
| DB-127 | build | — | `entries.virtual_value` | Derivado persistido, com rotina de reconciliação | Divergências reportadas | médio | BE-128 |
| DB-128 | build | — | bloqueio com motivo e instante | Padrões travados no legado **migram desbloqueados** e são reportados | Fecha D-05/BE-147 | médio | BE-147 |
| DB-129 | build | `enum` string Rails 8 | estado das tarefas | Conjunto estável; falha **estruturada** | O legado usava texto livre em pt-BR ("Concluido" sem acento), array Ruby em coluna de texto, e referência à tabela do executor, que é **purgada** | baixo | SIDEKIQ |
| DB-130 | build | — | marca de gestão no lançamento | Ver **DC-01** | Mesma decisão de DB-090/DB-051 | **alto** | DC-01 |
| DB-131 | build | — | hierarquia por **uma** estrutura ordenável | 12 irmãos ordenam 1,2,…,10,11,12 | Fecha a `position` string ordenada lexicograficamente ("10" antes de "2") e as **nove colunas redundantes** | médio | DB-120 |
| DB-132 | build | — | `should_insert_on_existing_projects` **exposta** | Controlável pelo usuário | Hoje default 1 e fora de qualquer tela — toda criação propagava para todos os projetos | baixo | BE-134 |
| DB-133 | build | — | FK, `null: false` e índices únicos | Limpeza e deduplicação **antes** das restrições | O legado não tinha `add_index`, `add_foreign_key` nem `null: false` | **alto** — ETL | bloco `data-schema` |
| DB-134 | build (**não portar**) | — | — | `default_position` **não existe em migration nenhuma**; o parcial que a usa não é renderizado por ninguém | **Q-01**: confirmar contra o banco de produção (uma das 2 provas do DEC-04) | médio | Q-01 |
| DB-135 | build | — | introspecção do esquema de origem | Aborta com relatório | DEC-04 | **alto** | bloco `data-schema` |

### 2.16 `availability` — Operação (OPS-120 … OPS-129)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| OPS-120 | build | SIDEKIQ + AR `transaction` | `SeedGlobalTemplatesJob` | Atômica, **idempotente**, falha visível; **`is_adjusted` copiado** | O legado não copiava `is_adjusted` — todo padrão de projeto nascia não ajustado, mesmo derivando de global ajustado. Fecha D-05 | **alto** | S0, OPS-081 |
| OPS-121 | build | SIDEKIQ·CABLE | `PropagateGlobalTemplateJob` | Progresso **por projeto** (não se atropelam); atributos copiados **fielmente** | O legado **forçava obrigatoriedade a 1** aqui (divergindo do OPS-120, que copiava) e não copiava `is_adjusted`. Fecha D-05 | **alto** | OPS-120 |
| OPS-122 | build | SIDEKIQ | ativação do padrão do projeto | Bloqueio liberado; **processo íntegro para as demais tarefas** | O legado restaurava o logger **dentro** do bloco protegido: uma falha deixava o **logger global desligado para o worker inteiro** | **alto** | BE-144 |
| OPS-123 | build | SIDEKIQ | desativação | Pai sem lançamento na data conclui normalmente | Fecha o `recalculate_entry.id` sem checar nulo e D-05 | médio | BE-145 |
| OPS-124 | build | SIDEKIQ + AR `transaction` | remoção | **Nada permanece** em falha; reexecução após conclusão termina sem erro | Fecha D-05, a ausência de transação, a gravação de estado sobre registro já destruído e o nulo sobrevivente do achatamento da lista | **alto** — dado financeiro | BE-146 |
| OPS-125 | build | SIDEKIQ + PAL (formato) | infraestrutura das tarefas | Tipo, entidade, autor e progresso expostos | — | médio | S0 |
| OPS-126 | build | PAL (formato) + OPS-086 | trilha de auditoria do módulo | Solicitação, início e desfecho auditados; **consulta exige autorização** | Ver **Lacuna L-05** / **Q-06** | médio | OPS-086 |
| OPS-127 | **adapt** | **CABLE** (`useCable.ts`) | progresso na própria tela | Avança até a conclusão, **sem recarregar** | Fecha D-86. No legado o delegate padrão apenas imprimia no stdout e **nenhuma tela consumia o progresso** | médio | S0 |
| OPS-128 | **reuse** | **SIDEKIQ** — retry automático é o comportamento **padrão** do Sidekiq; as filas (inclusive `_low_priority`) já estão em `backend/config/sidekiq.yml` | registrar a fila do módulo em `sidekiq.yml` | Falha transitória é reexecutada; falha definitiva fica na *dead set*, visível | Fecha D-05 pela raiz: **nenhum** dos 5 jobs do legado tinha retry (`destroy_failed_jobs? false` + `rescue` que engolia) | baixo | SIDEKIQ |
| OPS-129 | build | rake + AuditEvent | `lib/tasks/fix_availability_data.rake` | Idempotente, auditada, com pré-visualização e **proteção contra execução destrutiva** | O `destroy_existing` do legado apagava **todos** os lançamentos e **todos** os padrões sem nenhuma guarda. A própria existência dessas rotinas indica que os fluxos automáticos deixam inconsistência recorrente | **alto** | OPS-086 |

---

## 3. Decisões de comportamento

> Ambiguidade do legado que eu resolvi, com o porquê. As marcadas **PRECISA DO USUÁRIO**
> estão repetidas na seção 6 e **não** são decididas aqui.

| # | ID(s) | Ambiguidade do legado | Decisão | Racional |
| - | ----- | --------------------- | ------- | -------- |
| **DC-01** | BE-093 · DB-051 · DB-090 · DB-130 | **D-30** — `has_safegold_management` é carimbo denormalizado em **6** tabelas, mas só `companies` é atualizado em massa quando a flag muda. Histórico inconsistente por design | **PRECISA DO USUÁRIO (Q-02).** Recomendação: **derivar do projeto em tempo de consulta** e remover a coluna das 6 filhas | Nenhum consumidor a jusante foi encontrado no repositório. Derivar elimina a inconsistência de vez e simplifica 6 tabelas. **Mas** se algum relatório externo depende do carimbo como foto do momento, derivar muda número. Não decido sozinho |
| **DC-02** | DB-056 · DB-062 · DB-089 · OPS-051 · OPS-088 · FE-074 · FE-087 | Paperclip guarda `avatar` de projeto e `logo` de portador/fornecedor em disco local | **`has_one_attached` direto nos models novos** (`Project#logo`, `Carrier#logo`, `Provider#logo`), reusando a mesma pilha que o `Medium` usa: ActiveStorage + `image_processing` + `active_storage_validations`, com `ImageCropper`/`ThumbnailPicker` no front. **Paperclip não é portado.** | Cumpre o mandato ("anexos usam a pilha do ai9, não paperclip") **sem** o efeito colateral de usar `Medium`: `media` é uma **galeria autônoma** — não tem `owner_type`/`owner_id`, e um logo criado por lá apareceria em `/media` para qualquer autenticado. Filtrar a galeria significaria mexer em `MediumService`, que é da base compartilhada (Princípio 6b). Ver **Q-05** se você preferir `Medium` mesmo assim |
| **DC-03** | BE-098 · DB-087 · FE-106 | O DEC-07 diz "o projeto corrente vem do JWT validado contra membership" | **Fonte de verdade = `users.current_project_id`** (FK + índice), resolvida **no servidor** a cada request e validada contra membership. Um header opcional `X-Project-Id` é aceito **somente** se o usuário for membro, para suportar duas abas em projetos diferentes. **Nunca** cookie do cliente | Colocar `current_project_id` como *claim* do JWT obrigaria a **reemitir o token a cada troca de projeto**, e o access token da base é gerado por `Warden::JWTAuth::UserEncoder` (`token_service.rb:88`) — mexer nisso é tocar o auth de todos os sistemas da base. O DB-087 já pede a coluna. O espírito do DEC-07 ("vem da sessão, não do cliente") fica **integralmente** cumprido, e o D-28 fechado |
| **DC-04** | BE-055 | Trocar `project_id` de uma empresa era permitido, sem revalidar dependentes | **Não é caso de uso.** O campo é ignorado no update | Mover empresa arrasta `risk_controls`, recebíveis e renegociações para outro tenant. Se algum dia for necessário, é fluxo próprio com revalidação — não um campo de formulário |
| **DC-05** | FE-054 | JS ligava `change` em `#kind`/`#state` e enviava os filtros, mas **os selects não existem no HTML** e o backend os ignora | **Descartar** os dois filtros; a barra fica só com a busca | Três evidências independentes de que a feature nunca existiu: sem HTML, sem coluna, sem tratamento no servidor. DEC-09: descartar com evidência |
| **DC-06** | FE-059 | Aba "Controles de Risco" no detalhe de Empresa: parcial vazio, não listada nas abas, widgets sem action | **Não portar a aba.** A informação de controles de risco já aparece no cartão-resumo (FE-058) | Funcionalidade planejada e abandonada, sem uma linha funcional. Portá-la seria construir feature nova (DEC-09 proíbe) |
| **DC-07** | FE-070 | "Relações de fornecedor": handler aponta para `.provider_widget_content`, seletor **inexistente**; o parcial de destino nem existe | **Código morto — não portar.** O clique na linha abre o detalhe do fornecedor (BE-065) | Seletor errado + parcial ausente + rota sem tela = nunca funcionou |
| **DC-08** | BE-068 · FE-068 · BE-065 | **D-22** — telas de detalhe de Portador e de Fornecedor totalmente desenhadas (HTML + SCSS) mas **inacessíveis** | **Portar as duas.** São telas prontas e pagas | O inventário já recomendava portar; o custo é baixo e a alternativa é ter uma lista que não leva a lugar nenhum |
| **DC-09** | FE-065 | `subordinated_accounts_percent` é derivado no JS a cada tecla **e** persistido como coluna editável | **Derivar no servidor** a partir de `senior_accounts`/`subordinated_accounts`; o campo fica somente leitura na tela e a coluna passa a ser cache do cálculo | Dois donos do mesmo número é fonte garantida de divergência. Derivar mantém o valor exibido idêntico e elimina a ambiguidade. **Vocabulário de FIDC preservado** nos rótulos |
| **DC-10** | FE-067 · DB-062 | Logo de portador: HTML comentado, exibição comentada na lista, **mas** o handler JS vive e o backend aceita `logo` | **PRECISA DO USUÁRIO (Q-04).** Recomendação: **ativar** o upload (a infra do DC-02 já cobre) — é 1 campo e a coluna existe | O dry-run tem de informar quantos portadores realmente têm arquivo antes de migrar binários (DB-062) |
| **DC-11** | DB-053 · BE-066 | Fornecedor pode ter CPF **ou** CNPJ **ou nenhum**; a regra "ao menos um" está **comentada** no model | **Normalizar em `(document_type, document)`** e **manter o documento opcional** | A base legada quase certamente tem fornecedores sem documento; exigir um quebraria a migração. O par explícito resolve a ambiguidade de leitura sem mudar quem pode ser criado |
| **DC-12** | BE-069 · DB-057 | `bank_code` é `integer`: `001` virou `1` na base | Coluna passa a ser **string**; o ETL **reconstitui** os zeros à esquerda pelo comprimento de 3 do código COMPE e **reporta** o que não conseguir | Replicar um código de banco inválido não é preservar comportamento — é propagar corrupção de dado. Não é regra de negócio, é tipo errado (D-25) |
| **DC-13** | DB-066 | Apesar do nome, `sub_segments` **não** tem FK nem associação com `segments`, e não tem `legacy_id` | **Manter os dois catálogos independentes** | Criar a hierarquia agora exigiria inventar o mapeamento segmento→subsegmento para os dados existentes. É feature nova (DEC-09). Se o negócio quiser, é aditivo depois |
| **DC-14** | BE-087 | Ao indicar um responsável existente, o criador **perdia a posse** (`user_id = responsible_id`) e ficava sem membership própria | **O criador permanece com membership explícita**; a posse (`project.user_id`) vai para o responsável indicado | O comportamento legado produz o caso absurdo de o usuário criar um projeto e não conseguir mais abri-lo. Como membership é o que abre o grupo "Gestão" inteiro, deixá-lo de fora é regressão silenciosa de acesso |
| **DC-15** | BE-090 | O tracking de onboarding só dispara no update e **não tem efeito visível** em nenhuma tela | **Portar como evento da trilha de auditoria** (OPS-086), não como feature própria | Existe no legado (DEC-09 manda portar), mas não merece tela nem endpoint dedicados enquanto não houver consumidor. Como evento auditado, o dado não se perde e o custo é zero |
| **DC-16** | BE-094 · FE-093 | **D-31** — `has_bi` **não é lido em lugar nenhum** de `app/`, `engines/` ou `config/` | **Portar como marca comercial** (grava e exibe), exatamente como hoje | Pode haver consumidor **externo** (BI de terceiro lendo o banco) que não aparece no repositório. Remover uma coluna por ausência de leitura interna é risco assimétrico: manter custa uma coluna, remover pode quebrar um relatório do cliente |
| **DC-17** | BE-095 | `set_smart_id` rodava em **todo** `before_validation`: renomear o projeto **mudava o slug** e as URLs baseadas nele | **Slug imutável após a criação** | O slug é referência externa (chave de integração, URL). Mudá-lo em silêncio quebra links e integrações. Se for preciso mudar, vira ação explícita com aviso |
| **DC-18** | BE-100 · FE-118 | A aba "Projetos" do usuário listava **todos** os projetos com interruptor `disabled readonly` | **Permanece informativa**, listando apenas os projetos dos quais ele participa | Tornar a aba editável duplicaria o fluxo de membership (que já existe no detalhe do projeto, BE-099) com uma segunda superfície de autorização. Uma porta só para criar/remover membership |
| **DC-19** | BE-101 · BE-121 · BE-706 | Rotas mortas: `config/routes.rb:75` aponta para controller inexistente; `index`/`detail` renderizam templates que não existem; `projects/detail/connection_template/**` chama helpers inexistentes; `availability_entries#index` é vestigial | **Não portar as rotas comprovadamente mortas**; os endpoints reais de listagem/detalhe passam a responder 200 | DEC-09: o que é comprovadamente morto vai para `dropped` **com evidência**. A evidência aqui é template ausente + controller ausente + navegação real passando pelo console |
| **DC-20** | BE-115 · BE-146 | `is_deletable?` (só sem lançamentos) era **dica de UI**, enquanto `background_removal` apagava recursivamente filhos **e seus lançamentos** | **O servidor recusa (422)** a remoção de padrão com lançamentos; para remover, o usuário remove os lançamentos primeiro, de forma explícita | Apagar dado financeiro em silêncio, sem transação e sem rollback, não é comportamento a preservar. A intenção do código (`is_deletable?`) é inequívoca; o que faltava era ela rodar no caminho real |
| **DC-21** | BE-116 · BE-138 · DB-085 | Reordenação manual (`set_new_position!`) **não tem rota HTTP** e não é exposta em nenhuma tela | **Portar como serviço + endpoint autorizado**, sem tela nova nesta entrega | A reordenação automática (após criar/remover) é obrigatória e o código dela é o mesmo. Expor o endpoint custa quase nada; construir uma UI de arrastar-e-soltar seria feature nova (DEC-09) |
| **DC-22** | BE-704 | A chave de integração do tipo de garantia é derivada do título **só na criação** — título e chave divergem após a primeira edição | **Chave congelada na criação e editável explicitamente** | É chave de integração: recalcular em silêncio ao renomear quebra quem consome. Mesma lógica do DC-17 |
| **DC-23** | FE-089 | Qualquer `keyup`/`change` registrava a ação de salvar na fila do rodapé, e o sucesso redirecionava para a lista | **Sem autosave.** Um botão "Salvar" e **uma** requisição; o sucesso mantém o usuário no formulário com confirmação | O autosave por tecla é efeito colateral do jQuery do legado, não requisito. E redirecionar após salvar impede correções encadeadas |
| **DC-24** | FE-109 · BE-141 | Na edição de padrão **só o título é editável** — todo o resto está dentro de `if id.blank?`, sem nenhuma explicação | **Manter a restrição**, agora **explicando** na tela: os campos imutáveis aparecem somente leitura com a razão ("alterar o tipo invalidaria os lançamentos existentes") | A restrição é coerente com o domínio: mudar tipo de operação, prazo, cumulatividade ou hierarquia depois de existirem lançamentos invalidaria valores já consolidados. O defeito era a **falta de explicação**, não a regra |
| **DC-25** | BE-127 · BE-123 · DB-125 | **D-02** — decaimento composto: `original_value` é regravado a cada mudança de `value` e a correção é reaplicada sobre o valor já corrigido | **PRECISA DO USUÁRIO (Q-07).** Recomendação: **corrigir** (correção aplicada uma única vez, sempre sobre `original_value`) e reconstituir `original_value` no ETL onde for possível, reportando o resto | Não é convenção de sinal nem float — o DEC-01 e o DEC-02 **não cobrem** este caso. É valor que muda a cada salvamento repetido, o que significa que dois usuários salvando a mesma célula produzem números diferentes. Mas pode haver dependência contábil no valor atual: precisa de reconciliação com dado real |
| **DC-26** | BE-124 | Excluir lançamento de 1º nível: `parent_entry` montava um lançamento com padrão nulo cujo `save` falhava em silêncio; há um `TODO #7408` admitindo que o cenário multiempresa não foi fechado | **1º nível não tem pai**: a exclusão reconsolida a **consolidação geral** e o **saldo acumulado** dos demais itens de 1º nível | É a única leitura coerente com BE-128 (o saldo acumulado é justamente a relação entre itens de 1º nível). O `save` que falhava em silêncio não é comportamento, é bug |
| **DC-27** | BE-125 · BE-126 · DB-126 · DB-130 | **D-08** — a consolidação geral é **soma bruta** ignorando `is_cumulative`/`is_debit`, divergindo da regra dos nós com filhos; e o sinal de débito só é aplicado em folhas | **PRECISA DO USUÁRIO (Q-08).** Recomendação: **uma regra só** — cumulatividade e sinal aplicados de forma idêntica em folha, subtotal e consolidação | Duas semânticas de soma na mesma tela é a definição de número em que não se pode confiar. Mas **está em produção e muda número exibido ao cliente** — a mesma família do DEC-01, e por isso não decido sozinho |
| **DC-28** | BE-126 | `is_credit?`/`is_debit?` comparam a **string traduzida** em vez do código `C`/`D`: qualquer `operation_type` fora de `C`/`D`/`S`/`M` é tratado como crédito | **Comparar o código**, e `operation_type` passa a ser `enum` com conjunto fechado; valores fora do conjunto são reportados no dry-run | Comparar rótulo traduzido é bug latente que quebra ao mudar uma tradução. O `enum` elimina a classe inteira do problema sem mudar o resultado para os valores válidos |
| **DC-29** | BE-127 | **D-03** — dias úteis contam só segunda a sexta, **sem feriados** | **PRECISA DO USUÁRIO (Q-09).** Recomendação: **manter sem feriados** nesta entrega | Incluir feriados muda resultado financeiro de todo o histórico e exige escolher o calendário (nacional? estadual? bancário?). Manter é o comportamento atual; ligar depois é aditivo |
| **DC-30** | BE-130 | A leitura da grade **instancia** em memória, mas `parent_entry`, `next_level_entries` e `update_mirror!` **salvam no banco**, e os derivados herdam o autor de quem editou | **Abrir a grade nunca cria registro.** Derivados são materializados **apenas** no salvamento/recálculo, marcados como `derived: true` e **sem autor de usuário** | Um `GET` que grava é surpresa operacional e polui a base com lançamentos que ninguém fez. Marcar o derivado resolve a atribuição de autoria errada sem perder a materialização (que a performance da grade precisa) |
| **DC-31** | BE-135 | Alterar `is_adjusted`/`is_cumulative` de um global **não se propaga** aos padrões de projeto já derivados | **Propagar**, em segundo plano, com progresso por projeto — como o OPS-121 já faz para a criação | Sem propagar, o catálogo global vira ficção: cada projeto diverge silenciosamente. E a infra de propagação já existe (OPS-121); reusá-la é o caminho barato |
| **DC-32** | BE-143 | O `before_validation` de posicionamento é `on: [:create]` no global mas roda **também no update** no padrão de projeto — um update pode renumerar o item | **Assimetria eliminada**: posicionamento só recalcula quando a hierarquia muda, nos dois casos. Renomear nunca renumera | A assimetria não tem justificativa no código e produz renumeração surpresa. Alinhar os dois é o comportamento que a tela já sugere |
| **DC-33** | BE-144 | Ativar padrão com o pai inativo: o job só marca o próprio padrão; o método que subia a hierarquia (`active_and_reorder!`) **não é chamado por nenhuma rota** | **Recusar (422)** a ativação de padrão cujo pai está inativo, orientando a ativar a cadeia superior primeiro | Um filho ativo sob pai inativo é estado que a árvore não sabe representar (ele nunca aparece nos totais). Recusar é explícito; ativar a cadeia em cascata seria efeito colateral não pedido |
| **DC-34** | BE-148 | O total geral usa `value` (soma bruta) e cada card de padrão base usa `virtual_value` (saldo acumulado) — **duas métricas com o mesmo nome na mesma tela** | **PRECISA DO USUÁRIO (Q-10).** Recomendação: uma definição só de "total", coerente com a decisão do DC-27 | Está subordinado ao DC-27: escolher a semântica de soma resolve os dois de uma vez |
| **DC-35** | FE-127 | O código de colapsar/expandir a árvore está **comentado** no HTML e no SCSS — a grade é sempre totalmente expandida | **Portar como sempre expandida** e oferecer expandir/recolher como comportamento novo **do componente** (`DataTable` hierárquico do S0), com o padrão = expandido | Preserva exatamente o que o usuário vê hoje. O recolher vem de graça do componente compartilhado e não altera nenhum valor |
| **DC-36** | FE-146 | Existem estilos `.disabled` e `.project_availability_completed` **sem nenhum emissor** no HTML | **Não portar o estado "concluído"** | Sem emissor, sem coluna e sem menção em controller: não há o que preservar. Registrado aqui para não parecer omissão |
| **DC-37** | FE-119 · S6 · S7 | **D-90 / DEC-15.1** — o `locked: true` do menu nunca funcionou; as telas estão em uso | **Disponibilidades, Cobranças, Disponibilidades do Projeto e Padrões de Disponibilidade nascem HABILITADOS.** O mecanismo `locked` é portado corrigido (lido do **item**, não do grupo), mas **nenhum item nasce marcado** | DEC-15.1, literalmente: produção é a verdade, não a intenção aparente do código. Porta-se o **efeito real** |
| **DC-38** | todo o bloco | Toda ordenação/paginação server-side era descartada (D-20) | **Paginação e ordenação passam a funcionar** em todos os `search` do bloco | Q-04 já decidiu. Registrado aqui porque **muda o que ~15 telas fazem**: hoje trazem tudo. É a mudança visível mais ampla deste bloco |

---

## 4. Lacunas do ai9 (padrão novo a criar)

> Nenhuma tem equivalente na base **depois do trim** — todas verificadas no repositório.
> As que tocam a base compartilhada foram para o `upstream-flags.md` em vez de virar refactor.

| # | Necessidade do legado | Não existe no ai9? | Padrão proposto | Onde entra |
| - | --------------------- | ------------------ | --------------- | ---------- |
| **L-01** | **Tabela com ordenação por cabeçalho, paginação e estados** — ~15 telas do bloco | `frontend/src/components/ui/Table.tsx` é **só o primitivo shadcn** (`Table`/`TableHeader`/`TableBody`/…). Não há `DataTable`. Paginação de desktop é ad-hoc em `ExecutionViewerPage.tsx`; só existe `MobilePagination` | `components/ui/DataTable.tsx` + `components/ui/Pagination.tsx` (lê `X-Total-Count`), com variante hierárquica (indentação por nível) para a grade de disponibilidade. **Membros da biblioteca compartilhada** | **S0** |
| **L-02** | **Autocomplete com busca no servidor** — responsável de projeto, membro, portador candidato | `SearchableSelect.tsx` filtra **client-side** sobre `options` já carregadas (linhas 41-44). Serve para listas pequenas; **não serve** para usuários/portadores | `AsyncSearchableSelect` (ou `onSearch`/`loading` no existente), com debounce e limite server-side | **S0** |
| **L-03** | **Entrada monetária/percentual pt-BR** — portador, garantia, lançamento | Não há `MoneyInput`, `PercentInput` nem lib de máscara no `package.json` | `components/ui/MoneyInput.tsx` + `PercentInput.tsx`: exibem formatado, **enviam número**, avisam separador duplo | **S0** |
| **L-04** | **Escopo por projeto** — o escopo de quase todo o Safegold, e de **três outros blocos** | Zero `tenant_id`/`account_id`/`organization_id` em `backend/app/models/`; a base é declaradamente single-tenant; nenhum conceito de membership | **`memberships` + `users.current_project_id` + `current_project!` + concern `ProjectScoped`, aplicado explicitamente no endpoint (nunca `default_scope`). Desenho normativo completo em §0.6 — recebíveis, renegociações, risco e operações estruturadas apontam para lá** | **S2** · §0.6 · DC-03 |
| **L-05** | **Trilha de auditoria genérica** — OPS-086 e OPS-126 | `paper_trail` está no `Gemfile:47` e **não é usado em nenhum model**. Só existe `PermissionAuditLog`, específico de permissão | `AuditEvent` (ator, ação, entidade, projeto, payload, descrição pt-BR) + endpoint autorizado, no **formato** de `PermissionAuditLog`. **Ligar `paper_trail` é decisão de plataforma → já flagado em `upstream-flags.md §4`** | **S0** · **Q-06** |
| **L-06** | **Calendário de seleção de data com dias marcados** — FE-122 | Não há componente de calendário/date-picker em `components/ui/`; existe `date-fns` (formatação) mas nenhum picker | `components/ui/Calendar.tsx` sobre `react-day-picker` (padrão do ecossistema shadcn que o resto de `components/ui/` segue), pt-BR, com marcação de dias | **S7** |
| **L-07** | **Estados compartilhados de carregando/vazio/falha** — FE-079, FE-128, FE-137, FE-143 | Cada página da base implementa o seu | `components/ui/{LoadingState,EmptyState,ErrorState}.tsx`, com "tentar novamente" | **S0** |
| **L-08** | **Progresso de job na tela sem polling** — FE-083, OPS-087, OPS-127, FE-108 | `useCable`/`useChannel` existem, mas **não há canal nem hook de progresso**; os canais que sobraram são `permissions`, `public_events`, `whatsapp_instance` | `JobProgressChannel` (backend) + `useJobProgress` (frontend), no padrão documentado em `useCable.ts`: **o evento não carrega estado, apenas invalida a query** | **S0** |
| **L-09** | **`smart_id` / `by_any_id`** — BE-095 | `ai9-conventions.md §4` documenta o padrão, mas **não há nenhuma implementação viva** (0 ocorrências em `backend/app`; os models que o tinham — `Operation`, `Lead`, `Purchase` — saíram no trim) | Concern `Sluggable` em `backend/app/models/concerns/` (**diretório hoje vazio**), com `generate_slug` e `by_any_id` | **S2** |
| **L-10** | **Estado formal de operação em segundo plano** — DB-129, BE-147 | `aasm` está no `Gemfile:45` e **não é usado**; a base usa `enum` string + transições ad hoc | `enum` string (`pending`/`running`/`done`/`failed`) + serviço, seguindo o padrão da base. **Não ativar `aasm` nesta migração** (Princípio 6b) | **S6** |
| **L-11** | **Catálogo de UF brasileiras** — OPS-057, DB-060 | `api/v1/countries.rb` só tem países/DDI; não há lista de estados | `api/v1/br_states.rb` com constante `UF`, no mesmo padrão de `COUNTRIES` | **S1** |
| **L-12** | **Concerns de model** — o mapa assume vários | `backend/app/models/concerns/` está **vazio** (`Identificavel`, `FiltravelPorOrigem`, `ActsAsLimited` saíram no trim, apesar de `ai9-conventions.md §4` ainda os listar) | Os concerns deste bloco (`Sluggable`, `ProjectScoped`, `Auditable`) nascem aqui | **S0/S2** |

---

## 5. Correções ao catálogo e às convenções

> Verificado no repositório em 25/08/2026, branch `sfg9`. Cada item tem evidência.

**Correções ao `ai9-base-catalog.md`** (o catálogo estava **certo no essencial**; estes são
acréscimos e ajustes de precisão):

| # | O que o catálogo diz | O que o repositório mostra | Consequência para o mapa |
| - | -------------------- | -------------------------- | ------------------------ |
| C-1 | Fala em "policies" e "gate vago" para autorização | **`controller_helpers.rb:41-56` já traz `require_og!` e `restrict_visitor_access!`**, e `api/v1/base.rb:14` já executa `before { restrict_visitor_access! }` globalmente | `user_is_readonly` (BE-079) é **`adapt`, não `build`**: `restrict_visitor_access!` é literalmente "nega todo verbo de escrita para um tipo de usuário". É o gancho a estender, não um mecanismo paralelo |
| C-2 | Lista `User`, `UserType` sem detalhar | **`user_type.rb` tem `hierarchy_level`, `higher_than?`, `lower_than?`, escopos `higher_than`/`lower_than` e `seed_default_types!`** | Os 4 papéis Safegold (OG 1111 / Admin 998 / Gerente 888 / Colaborador 799) e a trava `inferior_role_types` do DEC-18.2/18.3 são **`adapt` do `UserType`**, não modelagem nova |
| C-3 | Design system: não menciona editor de texto rico; e o catálogo não menciona ActionText | **Existe um caminho de texto rico ponta a ponta, vivo**: backend `ActionText` (`config/application.rb:12`, tabela `action_text_rich_texts` no `schema.rb`, `user.rb:18` `has_rich_text :biography`, param em `api/v1/users.rb:190`, exposição em `api/entities/user.rb:33-49`) + frontend `RichTextEditor.tsx` com `serializeToHTML`(:75)/`deserializeHTML`(:102) e props `value: string`/`onChange: (v: string) => void`. **Os dois lados falam HTML — os contratos já casam** | Rebaixa 4 IDs de `build`/`adapt` para **`reuse`/`adapt` barato**: DB-088 vira `reuse` **sem nenhuma migration** (a tabela existe), FE-099 e FE-126 viram `reuse` do componente como está, e BE-097 fica `adapt` cujo único trabalho novo é **bloquear anexo no servidor** (ActionText os aceita por padrão) |
| C-3b | Catálogo (após `daa41118`): "`Medium` serve imagem e vídeo, e só" | **Confirmado** — `medium.rb:12`. Para este bloco, porém, **não é o fator decisivo**: os 3 anexos daqui (logo de projeto, de portador e de fornecedor) **são imagens**. O que exclui o `Medium` aqui é a **ausência de dono e de escopo** na tabela `media` (ver C-5). O problema de PDF é dos blocos `renegotiations`/`contracts` | Reforça **DC-02** por um segundo caminho independente. A conclusão não muda: ActiveStorage direto |
| C-3c | Catálogo lista `assets_proxy_controller.rb` entre as peças de anexo | **Peça perigosa, não reusável.** Verificado: `ActionController::Base` (linha 5), **zero autenticação**, serve `Rails.root.join('public','uploads', params[:path])` com `disposition: 'inline'`, mapeia inclusive `application/pdf` (linhas 6-24), sem guarda de *path traversal* sobre `params[:path]` | **Proibido** para qualquer arquivo deste bloco (ver §0.7). É o padrão do **D-82** (veredito `corrigir`). **Achado da base compartilhada → precisa entrar no `upstream-flags.md`**; não corrijo aqui (Princípio 6b) e não posso escrever fora de `map/` — fica como pedido explícito ao coordenador |
| C-4 | "`components/mobile/` (views separadas)" | São **9 componentes** prontos: `MobilePageLayout`, `MobileCard`, `MobileKPI`, `MobileContextSheet`, `MobileMenuActions`, `MobilePagination`, `MobileTopBar`, `MobileChartCard`, `MobileBottomBar` | FE-123 (seleção de data em tela estreita) e os menus de contexto das listas são `adapt`, não `build` |
| C-5 | "`Medium` + … cobre o que o legado faz com kt-paperclip: `avatar` de projeto, `logo` de portador" | **`media` não tem `owner_type`/`owner_id`** (`schema.rb`: `title`, `description`, `identifier`, `active`, `media_type`, `display_order`, `external_url`) — é uma **galeria autônoma**, sem dono e sem escopo | O logo por registro **não cabe** em `Medium` sem poluir `/media`. Ver **DC-02** e **Q-05**. A pilha (ActiveStorage + `image_processing` + `active_storage_validations`) continua sendo o reuso correto |
| C-6 | "`api/v1/{media,uploads,downloads}.rb`" no bloco de anexos | **`api/v1/uploads.rb` (avatar) grava em disco local** (`public/uploads/avatars`, `IO.copy_stream`), **não** em ActiveStorage | Não usar `POST /api/v1/uploads/avatar` como caminho de logo. O caminho correto é ActiveStorage (o que `Medium` faz), não o `uploads/avatar` |
| C-7 | "Sidekiq (o bloco de cron ficou vazio após o trim)" | Confirmado, **e mais**: `backend/config/sidekiq.yml` já define filas prefixadas por `APP_NAME` **incluindo `_low_priority`**, com comentário registrando o defeito já corrigido no `brsw` e no `facil` | OPS-128 (política de retentativa e retenção) é **`reuse` puro** — o retry é o default do Sidekiq e as filas já existem. É o único `reuse` puro dos 290 IDs |
| C-8 | "Action Cable (a camada de realtime obrigatória)" | Confirmado, mas **só sobraram 3 canais**: `permissions_channel`, `public_events_channel`, `whatsapp_instance_channel` | Não há canal de progresso de job — é a **Lacuna L-08** |
| C-9 | 18 models / 52 tabelas | Confirmado. **E o nome `Project` está de fato livre**: nenhum `app/models/project.rb`, nenhuma `create_table "projects"` em `schema.rb`, zero referências no frontend | DB-080 pode usar `projects` sem prefixo nem sufixo. (Existe `work_projects`, órfã, já registrada em `upstream-flags.md §7`) |

**Correções ao `ai9-conventions.md`** (o documento é **pré-trim** em três pontos; não é
erro de quem o escreveu, é o trim que passou por cima):

| # | O que as convenções dizem | O que o repositório mostra |
| - | ------------------------- | -------------------------- |
| C-10 | §4: "Concerns de model existentes e reaproveitáveis: `Identificavel`, `FiltravelPorOrigem`, `ActsAsLimited`" | **`backend/app/models/concerns/` está vazio.** Os três saíram no trim |
| C-11 | §4: "`smart_id` … `Model.by_any_id(id)` … Reproduza isso em recursos expostos por URL" | **Zero ocorrências de `smart_id`/`by_any_id` em `backend/app`.** O padrão está documentado mas não tem implementação viva → Lacuna **L-09** |
| C-12 | §5.7: lista 8 canais (`DashboardChannel`, `LeadChatChannel`, `PaymentsChannel`, …) | **Sobraram 3** (ver C-8) |
| C-13 | §5.1: cita `ClientRoute` entre as guardas de rota | **`ClientRoute.tsx` não existe mais** (o catálogo já registra a remoção no Bloco 4). Sobraram `ProtectedRoute`, `OgRoute`, `VisitorRoute` |
| C-14 | §9 item 11: "a infra existe (`sidekiq-cron` em `initializers/sidekiq.rb`)" | `sidekiq-cron` está no **`Gemfile:38`**, mas `initializers/sidekiq.rb` **só configura o Redis** — não há bloco de cron nenhum. Cada job agendado precisa criar esse bloco |

**Correção ao `feature-inventory.md` / aos specs:** nenhuma. As contagens batem —
projects 110 (BE-080..119, BE-700..706, FE-080..119, DB-080..092, OPS-080..089),
companies-carriers 94, availability 86. **Total 290.**

---

## 6. Perguntas para o usuário

> Só o que **não** consigo decidir com evidência. Nenhuma bloqueia o início do S0/S1.

| # | Pergunta | Por que trava | O que eu faço se você não responder | Impacto |
| - | -------- | ------------- | ----------------------------------- | ------- |
| **Q-01** | **A coluna `default_position` existe no banco de produção?** (D-06) | Nenhuma migration a cria, mas `availability_templates_controller.rb:22` a usa na busca com texto. Se ela **não** existe, a busca de padrões globais está quebrada em produção há anos e ninguém reclamou; se **existe**, há schema fora do versionamento (uma das 2 provas do DEC-04) | Assumo que **não existe** e a busca nasce sem ela, ordenada pela hierarquia. Registro para o dry-run confirmar | Médio. Você tem o dump desde 25/08 — é um `\d availability_templates` |
| **Q-02** | **`has_safegold_management` é foto do momento (carimbo histórico) ou deve ser derivado do projeto?** (D-30, DC-01) | A marca é copiada para **6** tabelas mas só `companies` é atualizada em massa. Qualquer relatório que filtre por ela mente hoje. Nenhum consumidor foi encontrado no repositório — mas o consumidor pode ser externo | **Não decido.** Sigo com a coluna derivada do projeto e **marco os 4 IDs como pendentes** (BE-093, DB-051, DB-090, DB-130) | **Alto.** É a decisão mais consequente do bloco: muda o desenho de 6 tabelas |
| **Q-03** | **O autopreenchimento por CNPJ (ReceitaWS) volta a funcionar?** (D-27) | O backend está vivo e configurado (token, cache 365 d, timeout 10 s), mas a UI está **duplamente morta**: botão comentado e URL com ERB escapado. A integração é paga | Ligo (o endpoint existe, o custo é o botão) e registro no `improvements-log.md` | Baixo. É 1 botão, mas envolve custo de terceiro |
| **Q-04** | **O logo do Portador volta a existir?** (DC-10, FE-067) | HTML comentado, exibição comentada na lista, handler JS vivo, backend aceitando `logo` | Ligo, reusando a mesma pilha dos outros dois logos | Baixo |
| **Q-05** | **Você prefere os logos em `Medium` mesmo assim?** (DC-02) | `media` não tem dono nem escopo (C-5): um logo criado por lá aparece na galeria `/media` para qualquer autenticado. Filtrar a galeria significaria mexer em `MediumService`, que é da base compartilhada (Princípio 6b) | Sigo com `has_one_attached` direto nos models novos, reusando a mesma pilha ActiveStorage que o `Medium` usa. **Paperclip não é portado nas duas opções** | Médio. Se você quiser `Medium`, precisa autorizar tocar na galeria compartilhada ou aceitar os logos aparecendo lá |
| **Q-06** | **Ativar `paper_trail` (base compartilhada) ou criar `AuditEvent` só do Safegold?** (L-05) | `paper_trail` está no Gemfile e não é usado por **nenhum** sistema da base. Ativá-lo é decisão de plataforma; criar `AuditEvent` é escopo desta migração | Crio `AuditEvent` só do Safegold, no formato de `PermissionAuditLog`, e deixo o flag de plataforma em `upstream-flags.md §4` | Médio. Duplicar trilha depois custa mais caro que decidir agora |
| **Q-07** | **O decaimento composto da correção por dias úteis: corrigir ou replicar?** (D-02, DC-25) | O DEC-01 (sinal) e o DEC-02 (float) **não cobrem** este caso — não é convenção nem precisão, é o valor mudando a cada salvamento repetido. Parte da base pode ter valor corrigido várias vezes | **Não decido.** Marco BE-127/BE-123/DB-125 como pendentes e o ETL só reconstitui `original_value` depois da sua resposta | **Alto.** É dinheiro, e a reconstituição do histórico depende disto |
| **Q-08** | **A consolidação geral deve respeitar `is_cumulative` e `is_debit`?** (D-08, DC-27) | Hoje são **duas regras de soma diferentes** na mesma tela: a consolidação geral soma bruto, os nós com filhos aplicam cumulatividade e sinal. Está em produção e muda número exibido ao cliente | **Não decido.** Mesma família do DEC-01 (replicar × corrigir) | **Alto.** Muda número na tela do cliente |
| **Q-09** | **Dias úteis passam a considerar feriados?** (D-03, DC-29) | Sem calendário de feriados hoje. Incluir muda resultado financeiro de todo o histórico e exige escolher qual calendário (nacional, estadual, bancário) | Mantenho seg–sex sem feriados (comportamento atual); ligar depois é aditivo | Médio |
| **Q-10** | **"Total" no painel: soma bruta ou saldo acumulado?** (DC-34) | O total geral usa `value` e cada card de padrão base usa `virtual_value` — mesma palavra, duas métricas | Subordino ao Q-08: a mesma resposta resolve os dois | Médio |
| **Q-11** | **Quem gerencia membership: confirma OG/Admin/Gerente, sem o dono do projeto?** (DEC-18.5) | O DEC-18.5 já decidiu **e** registrou que o dono do projeto **não** vira papel com poder. Só levanto porque o DC-14 me fez tocar em posse: se o criador que indica outro responsável perde a posse, ele fica sem nenhum caminho de gerenciar o projeto que criou | Sigo o DEC-18.5 como está e aplico o DC-14 (criador mantém membership explícita) | Baixo — é confirmação, não pergunta aberta |

---

## 7. Resumo do bloco

| Estratégia | IDs | % |
| ---------- | --- | - |
| **reuse** | 5 | 1,7 % |
| **adapt** | 26 | 9,0 % |
| **build** | 259 | 89,3 % |
| **Total** | **290** | 100 % |

**Os 5 `reuse` puros** (a base serve **como está**; o trabalho é apontar e configurar):

| ID | O que a base já entrega |
| -- | ----------------------- |
| DB-088 | **ActionText** — `action_text_rich_texts` já existe no `schema.rb`. **Zero migration** |
| FE-099 · FE-126 | **`RichTextEditor.tsx`** — `value`/`onChange` em HTML, casando com o `*_html` do ActionText. **Zero componente novo** |
| OPS-088 | **`image_processing` + variantes** — a receita inteira está em `medium.rb#optimized_url`/`small_url` |
| OPS-128 | **Sidekiq** — retry é o default; as filas (inclusive `_low_priority`) já estão em `config/sidekiq.yml` |

**Os 26 `adapt`** (cada um estende uma peça real da base, não reimplementa):

| Capacidade | IDs |
| ---------- | --- |
| BE (4) | BE-064 (Credential) · BE-079 (`restrict_visitor_access!`/`require_og!`) · BE-097 (ActionText — só falta bloquear anexo) · BE-098 (AuthHelpers + `current_project!`) |
| FE (13) | FE-050 · FE-119 (`useNavItems`) · FE-074 · FE-087 (ImageCropper) · FE-083 · FE-108 · FE-146 (Action Cable) · FE-086 · FE-096 (SearchableSelect) · FE-106 (AuthHelpers/tokenStore) · FE-123 (`components/mobile/`) · FE-124 · FE-125 (KpiCard/Recharts) |
| DB (4) | DB-056 · DB-062 · DB-089 (ActiveStorage) · DB-087 (AuthHelpers/User) |
| OPS (5) | OPS-050 (Credential) · OPS-051 (ActiveStorage + `active_storage_validations`) · OPS-054 (`db/seeds.rb` + `db/seeds/`) · OPS-087 · OPS-127 (Action Cable) |

> **Nota sobre "paginação é reuse".** Correto **no servidor**: Kaminari + `set_pagination_headers`
> cobrem 100% do lado backend de todos os ~15 `search` deste bloco, e é isso que está citado
> em cada linha via **KAM**. No **frontend** a medição diz outra coisa: `MobilePagination` só
> tem anterior/próxima, sem primeiro/último e sem limite por página — que é exatamente o que
> o FE-053 exige — e usa cor literal em vez de token de tema. Por isso o controle de desktop
> segue `build`, e `MobilePagination` fica **intocado** (Princípio 6b).

**Dos 260 `build`, 3 estão marcados como pendentes de resposta** (`build?` / decisão em aberto):
FE-067 (Q-04) e o par BE-127/DB-125 (Q-07), além dos 4 IDs de DC-01 (BE-093, DB-051, DB-090,
DB-130) que dependem da Q-02 para fechar o desenho.

**O único `reuse` puro:** OPS-128 (retentativa e retenção de tarefas) — Sidekiq já entrega.

> **A proporção não é falha de reuso — é o diagnóstico correto.** O catálogo diz, e a
> verificação confirma: **o domínio de crédito do Safegold é `build` inteiro**, porque a base
> ai9 depois do trim é infraestrutura, não domínio. Forçar `adapt` sobre `Operation`,
> `Medium` ou `work_projects` entregaria abstração emprestada de outro problema.
> O reuso real está no que **cada** `build` herda de graça: auth, papel/hierarquia,
> ActiveStorage + `image_processing`, **ActionText + `RichTextEditor`**, Action Cable,
> Grape + Kaminari, Sidekiq com retry, React Query, design system, `SideDrawer`,
> `ImageCropper` e os 9 componentes de `components/mobile/`.
>
> **E há uma coisa que este bloco não herda, mas produz:** o escopo por projeto (§0.6).
> É a fundação de que os outros três blocos dependem.
