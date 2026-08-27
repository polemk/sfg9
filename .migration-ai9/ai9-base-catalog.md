# Catalogo da base ai9 **depois do trim** — a referencia de reuso do Phase 2

> Escrito em 25/08/2026, logo apos fechar o Phase 1b. **Toda decisao `reuse`/`adapt`/
> `build` do `migration-map.md` deve citar uma linha deste documento.** Sem isto, cinco
> agentes redescobrem a mesma base e decidem de forma inconsistente.
>
> **Este documento descreve o que EXISTE, nao o que e bonito.** Se algo aqui estiver
> errado, corrija com evidencia (arquivo:linha) — errar para o lado de "ja existe" faz
> alguem construir em cima de coisa que nao esta la.

## O tamanho da base hoje

**18 models. 52 tabelas. ~35 arquivos de endpoint Grape. 7 paginas + 20 componentes de UI.**

Depois de remover 27 features, sobrou **infraestrutura**, quase nenhum dominio. Isso tem
uma consequencia direta e que vale enunciar antes da tabela:

> **O dominio de credito do Safegold e `build` inteiro.** Nao existe no ai9 nada parecido
> com projeto/empresa/portador/borderô/operacao de risco/renegociacao/indicador. Nao
> procure equivalente — nao ha. Procurar equivalente para forcar um `adapt` e pior que
> `build`, porque entrega uma abstracao que nao foi feita para o problema.
>
> **O ganho de reuso esta em outro lugar, e e grande:** autenticacao, usuarios,
> permissoes, anexos e toda a camada de frontend.

---

## Backend — o que existe

### Autenticacao e sessao — **reuse forte**
| Peca | Onde | Serve para (Safegold) |
| ---- | ---- | --------------------- |
| `User`, `UserType` | `app/models/{user,user_type}.rb` | A capability **auth-users** (125 requirements) |
| `LoginCode`, `LoginAttempt` | `app/models/` | Codigo de acesso, forca bruta, trilha de tentativa |
| `Api::Auth::V1::*` | `app/controllers/api/auth/v1/` | `magic_login`, `code_validation`, `oauth`, `registration`, `sessions`, `me`, **`impersonate`** |
| `SecurityHelpers` | `api/auth/v1/security_helpers.rb` | `check_brute_force!`, `check_rate_limit!`, `current_ip`, `current_user_agent`. **Restaurado em `ab40bf83`** — estava quebrado |
| `AuthHelpers` | `api/auth/v1/auth_helpers.rb` | JWT, cookies **httpOnly** de refresh e de cable, impersonation |
| `Auth::*` services | `app/services/auth/` | O legado usa Devise + senha; aqui e magic link/codigo |

**Nota importante para o mapa:** o legado autentica com **Devise + senha**. O ai9 nao tem
login por senha — tem magic link e codigo (por e-mail **ou WhatsApp**, DEC-14). Isso e uma
**mudanca de comportamento observavel** e precisa de linha propria no
`improvements-log.md` e nas decisoes, nao pode passar como detalhe de implementacao.

### Autorizacao — **adapt**, e e o gancho do DEC-18
| Peca | Onde |
| ---- | ---- |
| `Permission`, `UserPermission` | `app/models/` — consumidos por `api/v1/downloads.rb:17,52` |
| `PermissionAuditLog`, `PermissionConflict` | `app/models/` — hoje orfaos; o Phase 3 pluga |
| `api/v1/permissions.rb` | endpoint |

A **matriz aprovada (DEC-18)** — 45 recursos, 4 papeis, `user_is_readonly`, escopo por
membership — se implementa **sobre estas pecas**. Nao criar mecanismo paralelo.
`ClientRoute` e `PermissionsSyncService` **foram removidos** no Bloco 4 (eram
plan-driven): hoje **qualquer autenticado alcanca `/dashboard`, `/users`, `/media`**. Esse
gate esta vago e e trabalho do Phase 3.

### Anexos e arquivos — **CORRIGIDO em 25/08/2026, leia com atencao**

> **Eu errei aqui na primeira versao deste catalogo.** Escrevi que `Medium` cobria tambem
> os anexos de renegociacao. **Nao cobre.** O agente do bloco de recebiveis abriu o
> arquivo e me corrigiu. Fica registrado porque a licao vale: **eu afirmei `reuse` sem
> abrir o model** — exatamente o erro que este catalogo pede que voce nao cometa.

**`Medium` serve IMAGEM e VIDEO, e so.** `app/models/medium.rb:12`:
```ruby
validates :media_type, presence: true, inclusion: { in: %w[image video] }
```
Serve para: `avatar` de projeto, `logo` de portador, fotos. Vem com
`api/v1/{media,uploads,downloads}.rb`, `MediumService`, `ImageCropper`/`ThumbnailPicker`.

**Para DOCUMENTO (PDF), que e o caso dos `renegotiation_attachments`:** o caminho e
**ActiveStorage direto** (`has_one_attached`/`has_many_attached`), que ja esta no projeto
com `image_processing` (`Gemfile:10`). Estrategia: **`adapt`**, nao `reuse`.

**NAO reusar o `assets_proxy_controller.rb` para documento privado.**
`assets_proxy_controller.rb:5` herda de `ActionController::Base` e serve
`public/uploads/**` com `disposition: 'inline'` e **sem autenticacao nenhuma**. E
literalmente o padrao do **D-82**, que esta na lista dos 23 defeitos de seguranca a
**corrigir**. Documento de renegociacao e privado e precisa de entrega autenticada.

**Em todo caso: nao portar kt-paperclip.**

### Outras pecas que faltavam neste catalogo (mesma correcao)

| Peca | Onde | Muda a estrategia de |
| ---- | ---- | -------------------- |
| **ActionText** | `config/application.rb:12`, `user.rb:18`, tabela `action_text_rich_texts` (`schema.rb:30`) + `RichTextEditor.tsx` no front | Texto rico (ex.: `Contract#description`) vira **`adapt`**, nao `build` |
| **Kaminari** | `Gemfile:85` | Paginacao e **`reuse`**. Resolve o D-20 |
| **sidekiq-cron** | `Gemfile:38` | Job agendado e **`reuse`**. O bloco de cron esta **vazio** apos o trim |
| **image_processing** | `Gemfile:10` | Derivacao de imagem e **`reuse`** |

**Flag de upstream:** o ActiveStorage esta configurado com `service: Disk`. Em producao
isso exige volume persistente garantido pelo deploy — senao anexo some entre deploys.

### Integracoes e credenciais — **CORRIGIDO em 25/08/2026**

> Segundo erro meu neste catalogo, mesma causa do primeiro: afirmei sem abrir o model.

`Credential` + `api/v1/credentials.rb` existem, mas **so aceitam provedor de IA**
(`credential.rb:7`: `inclusion: { in: %w[openai anthropic google openai_whisper] }`).

**As chaves de terceiro do Safegold (ReceitaWS, Google Maps) NAO cabem la** sem alterar um
model compartilhado. **Vao para ENV**, com o segredo fora do repo — e os segredos que o
legado commitou estao no `legacy-defects.md` para rotacao.

### WhatsApp — **reuse parcial** (DEC-14)
`EvolutionConnection`, `PolemkInstance`, `PolemkWebhook`, `api/whats/v1/{instances,webhooks}.rb`,
`EvolutionReconnectJob`. Existe **porque o login por WhatsApp precisa** — chats, grupos e
inbox sairam no Bloco 3.

### Assistente interno (AI9-007, adaptado) — **nao e do legado**
`ChatFlow`, `ChatSession` (com `user_id`), `AgentRun`, `FlowExecution`, `app/services/ai/**`,
`Ai::ConversationMemory` (Redis, TTL 2h). Motor multi-provider; `DEFAULT_MODEL =
claude-opus-5`. **Nao mapear ID de legado para ca.**

### Infra transversal — **reuse**
Grape com `/api/v1`, `/auth/v1`, `/whats/v1` · JWT · **Action Cable** (a camada de
realtime obrigatoria — Principio 10: **polling e proibido**) · Sidekiq (o bloco de cron
ficou **vazio** apos o trim) · Redis · `Rack::Attack` com limites de auth ·
`api/v1/countries.rb`, `defaults.rb`, `controller_helpers.rb` · pgcrypto.

---

## Frontend — o que existe

### Design system — **reuse**, e e regra do Principio 11
`src/components/ui/`: `Button`, `Input`, `Label`, `Card`, `Badge`, `Table`, `Tooltip`,
`Progress`, `Slider`, `Sheet`, `SearchableSelect`, `SearchableMultiSelect`, `ImageCropper`,
`accordion`, `avatar`, `dialog`, `drawer`, `switch`, `tabs`, `textarea`.

**Toda tela do Safegold se monta com estes.** Componente novo vira membro da biblioteca
compartilhada, nunca peca de uma tela so.

### Estrutura — **reuse**
`Layout`, `Sidebar` (**ja desacoplada de plano no Bloco 4**; `useNavItems.ts` e fonte unica
estatica, com o ponto de extensao por papel documentado), `PageHeader`, `SideDrawer`,
`ThemeProvider` + `ThemeToggle` (**light e dark**), `ProtectedRoute`/`OgRoute`/`VisitorRoute`,
`components/mobile/` (views separadas — opcao do Phase 0), `components/layouts/`.

### Dados e graficos — **reuse** (DEC-10: usar as libs do ai9)
**React Query** (`@tanstack/react-query`) + **Axios** (`lib/api/client.ts` + `endpoints.ts`)
+ **Zustand**. **Nao e RTK Query.** Graficos: **Recharts**, com `components/charts/` e
`components/kpi/` ja existentes. Datas: `date-fns`.

`lib/api/tokenStore.ts`: access token **so em memoria**, nunca em `localStorage`.

### Paginas que sobraram
`LoginPage`, `DashboardPage`, `ClientDashboardPage`, `UsersPage`, `ProfilePage`,
`MediaPage`, `WhatsappPage`, `pages/admin/`. A rota `/` aponta para o login (DEC-13.3).

---

## O que a base **NAO** tem (e portanto e `build`)

1. **Todo o dominio de credito** — projeto, empresa, portador, fornecedor, carteira,
   segmento, borderô, recebivel, renegociacao + parcelas/pagamentos, operacao de risco +
   movimentos + extensoes, operacao estruturada, limite/controle de risco, garantia,
   indicador, disponibilidade, cobranca, remuneracao, contrato.
2. **Membership de projeto** — o gate `projects.count > 0` do legado e o escopo por
   projeto do DEC-07. Nao existe conceito de membership no ai9.
3. **Geracao de PDF** — o legado usa `wicked_pdf`. Fora de escopo por DEC-09.
4. **Formularios com validacao declarativa** — nao ha `react-hook-form` nem `zod` no
   `package.json`. Confirme o padrao real de formulario antes de assumir um.
5. **i18n** — fora de escopo por DEC-09.

---

## Como usar isto no mapa

- `reuse` = existe aqui e serve **como esta**; o trabalho e apontar e configurar.
- `adapt` = existe aqui algo proximo; **estender** (campo, regra, variante).
- `build` = nao existe; implementar novo, idiomatico ao ai9, **com as pecas acima**.

Um `build` de dominio **quase sempre reusa** infra (auth, media, Action Cable, design
system). Cite na coluna "Existing ai9 equivalent" o que ele reusa, mesmo sendo `build` —
e isso que impede alguem de reimplementar upload ou tabela do zero.
