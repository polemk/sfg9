# Project Rules — Trae AI • Monorepo (Rails 8 API + React .tsx)

> **Objetivo**: Documento‑guia para iniciar e manter o novo projeto com backend **Rails 8 (API‑first)** + **Grape + Swagger** (visualização com **Stoplight Elements**) e frontend **React (.tsx)** consumindo **100% via API**. Inclui Action Cable, Turbo/Hotwire (tempo real/admin), PostgreSQL, Evolution API (WhatsApp), Asaas (pagamentos), temas **dark/light**, testes obrigatórios e automações de CI/CD.

---

## 1) Arquitetura & Padrões

* **Monorepo** com duas pastas raiz:

  * `backend/` → Rails 8 API‑only
  * `frontend/` → React + TypeScript (.tsx)
* **API‑first**: todo fluxo de dados, autenticação e autorização via API.
* **Versionamento de API**: por módulo com **Grape** dentro de `controllers/api`:
  * Autenticação: `/auth/v1/*`
  * WhatsApp: `/whats/v1/*`
  * Asaas: `/asaas/v1/*`
* **Documentação**: gerar OpenAPI (Swagger) automaticamente com **grape-swagger**; servir **/swagger_doc** (JSON) e visualizar com **Stoplight Elements** em `/docs`.
* **Tempo real**: **Action Cable** para eventos do servidor → cliente (notificações, estados de pagamento, mensagens), canalizando por **Redis**. **Turbo Streams**/Hotwire opcionais para painel/admin interno.
* **Banco**: **PostgreSQL 14+**, chaves **UUID** por padrão, migrações idempotentes, índices compostos.
* **Mensageria/Jobs**: **ActiveJob** com **Sidekiq** (Redis) para webhooks, filas e integrações externas.
* **Config por ambiente**: `dotenv-rails`/Credenciais Rails; no frontend, `.env` + Vite/Next.
* **Observabilidade**: logs estruturados (JSON), **Rack::Attack** (rate limit), **Skylight/New Relic** (perf).

---

## 2) Backend (Rails 8 API‑only)

### 2.1 Estrutura de pastas (essencial)

```
backend/
  app/
    controllers/
      api/
        v1/
          base.rb           # monta endpoints Grape
          auth.rb           # login/refresh/logout
          users.rb          # CRUD usuários
          payments.rb       # Asaas webhooks e consultas
          whatsapp.rb       # Evolution webhooks/envio
    channels/               # Action Cable channels
    models/                 # modelos ActiveRecord (uuid)
    serializers/            # (opcional) representação JSON
    services/
      asaas/
      evolution/
      auth/
    jobs/
    workers/                # (se usar Sidekiq diretamente)
  config/
    initializers/
      grape.rb
      grape_swagger.rb
      cors.rb
      sidekiq.rb
      action_cable.rb
    cable.yml
    database.yml
  spec/                     # RSpec + FactoryBot + VCR/WebMock
```

### 2.2 Gems base

* **API**: `grape`, `grape-entity`, `grape-swagger`, `grape-swagger-rails` (ou servir JSON puro + Stoplight Elements no frontend `/docs`).
* **Auth**: `devise`, `devise-jwt` (JWT stateless), `doorkeeper` (opcional se OAuth2).
* **Perf/Sec**: `rack-cors`, `rack-attack`, `brakeman`, `bundler-audit`.
* **Jobs/Realtime**: `sidekiq`, `redis`, `actioncable`.
* **Pagamentos**: cliente HTTP para Asaas (`faraday`/`httpx`) + serviços dedicados.
* **WhatsApp**: cliente HTTP Evolution API (`faraday`/`httpx`) + webhooks.
* **Testes**: `rspec-rails`, `factory_bot_rails`, `database_cleaner-active_record`, `faker`, `vcr`, `webmock`, `simplecov`.
* **Qualidade**: `rubocop`, `standardrb` (opcional), `solargraph` (LSP), `yard` (docs).

### 2.3 Convenções de código

* **Comentários obrigatórios** em classes, módulos e métodos públicos (YARD).
* **Nomes explícitos** de serviços (ex.: `Asaas::CreatePayment`, `Evolution::SendTextMessage`).
* **Entities** do Grape para **contratos de resposta**. Nunca retornar modelos crus.
* **Erros** padronizados: envelope `{ error: { code, message, details } }` + HTTP correto.
* **Paginação** padrão: `page` + `per_page`, cabeçalhos `X-Total-Count`, `Link`.
* **Idempotência** em endpoints sensíveis (ex.: criação de cobrança). Use `Idempotency-Key`.
* **CORS** liberando apenas origens conhecidas (env var).

### 2.4 Autenticação & Autorização

* **JWT** (Bearer) emitido no login; refresh token separado.
* **Scopes**/Roles em `Ability` (Pundit ou CanCanCan). Autorização em cada endpoint.
* Expirar tokens curtos (ex.: 15min) e renovar com refresh (ex.: 7d). Revogação em blacklist Redis.

### 2.5 Action Cable

* Canais por recurso: `NotificationsChannel`, `PaymentsChannel`, `ChatChannel`.
* Identificar usuário pelo JWT (cookie httpOnly opcional para admin).
* Escalar com Redis (config em `cable.yml`).

### 2.6 Integração Evolution API (WhatsApp)

* **Env vars**: `EVOLUTION_BASE_URL`, `EVOLUTION_API_KEY`, `EVOLUTION_INSTANCE`, callbacks.
* **Serviços**: `Evolution::SendTextMessage`, `Evolution::SendMedia`, `Evolution::ListContacts`.
* **Webhooks**: endpoint `POST /whats/v1/webhooks` (Grape), validar assinatura/UA quando aplicável.
* Persistir eventos relevantes (mensagens recebidas, status de entrega) e publicar em `ChatChannel`.

### 2.7 Integração Asaas (Pagamentos)

* **Env vars**: `ASAAS_BASE_URL`, `ASAAS_API_KEY`, `ASAAS_WEBHOOK_SECRET`.
* **Serviços**: `Asaas::CreateCustomer`, `Asaas::CreateCharge`, `Asaas::GetQRCode`, `Asaas::Refund`.
* **Webhooks**: `POST /asaas/v1/webhooks/*` com verificação de assinatura.
* Estados de pagamento em FSM (`aasm` opcional) e broadcasts via Action Cable.

### 2.8 Modelagem & Banco (PostgreSQL)

* **UUID** como PK: `enable_extension 'pgcrypto'` e `default: -> { "gen_random_uuid()" }`.
* **Timestamps UTC**; conversão de fuso no frontend.
* **Índices** para buscas (compostos para chaves usuais) e restrições de unicidade.
* **Auditoria** (opcional): `paper_trail`.

### 2.9 Documentação OpenAPI

* Gerar em `/swagger_doc` via `grape-swagger`.
* **Stoplight Elements** servido em `/docs` consumindo o JSON.
* Manter exemplos de request/response e códigos de erro.

### 2.10 Testes (obrigatório)

* **RSpect** unitário, request e canais (Action Cable).
* **Cobertura mínima** 90% (falha de CI se < 90%).
* **VCR** + **WebMock** para Evolution/Asaas.
* **Factories** consistentes; `lint` em CI.
* Rodar `brakeman` e `bundler-audit` no pipeline.

---

## 3) Frontend (React + TypeScript .tsx)

### 3.1 Stack

* **Builder**: Vite (ou Next.js se SSR necessário).
* **Linguagem**: TypeScript (.tsx).
* **UI**: Tailwind + shadcn/ui; ícones com `lucide-react`.
* **Estado**: React Query (server-state) + Zustand/Redux Toolkit (client-state).
* **HTTP**: Axios com **interceptores** para JWT/refresh e trat. de erros.
* **Roteamento**: React Router (ou Next Router).
* **i18n**: `react-i18next` (pt-BR default).
* **Themes**: dark/light via CSS vars + `prefers-color-scheme` + toggle persistido.
* **A11y**: WAI‑ARIA, foco visível, contraste AA+.

### 3.2 Organização de pastas

```
frontend/
  src/
    app/                 # rotas/pages
    components/
    features/
      auth/
      payments/
      chat/
    lib/
      api/
        client.ts        # axios preconfigurado
        endpoints.ts     # contratos TS das rotas
    store/
    styles/
    hooks/
    types/
```

### 3.3 Contratos & Tipagem

* **Gerar tipos** a partir do Swagger (`openapi-typescript`) e consumir em `endpoints.ts`.
* **Nunca** usar `any`. Estrito em `tsconfig`.

### 3.4 Realtime

* **Action Cable JS** (ou Sockette) com reconexão exponencial.
* Listeners por feature (ex.: `usePaymentsChannel`, `useNotificationsChannel`).

### 3.5 Erros & UX

* Toasts padronizados para sucesso/erro.
* Loading/skeletons; retry com `react-query`.
* Empty states com dicas de ação.

### 3.6 Comentários & Docs

* **JSDoc/TSdoc** obrigatório em componentes, hooks e funções utilitárias.
* Storybook (opcional) para catálogo de UI.

---

## 4) Segurança

* **HTTPS only**; HSTS.
* **JWT** seguro: expiração curta + refresh; armazenamento: memory/httponly (admin) + CSRF para painéis.
* **Rate limit** (Rack::Attack) por IP/rota; chaves em headers.
* **Validação de payload** (Grape params + esquemas TS no frontend).
* **Headers**: `X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`.
* **Secrets** exclusivamente em variáveis de ambiente/credenciais.

---

## 5) Qualidade & Padrões de Código

* **Lint**: `rubocop` (backend) e `eslint + @typescript-eslint` (frontend); `prettier`.
* **Commits**: Conventional Commits + **lint-staged** em pre-commit.
* **Branching**: trunk‑based com feature branches curtas; PR obrigatório.
* **Code Review**: 1+ aprovação; não fazer merge com CI vermelho.
* **Comentários**: todo arquivo/classe/função com comentário explicando finalidade.

---

## 6) Testes & CI/CD

### 6.1 Pipeline (GitHub Actions)

* **Backend**:

  * `bundle install --path vendor/bundle`
  * `rubocop`, `brakeman`, `bundler-audit`
  * `rails db:setup RAILS_ENV=test`
  * `rspec --format documentation --fail-fast`
  * `simplecov` → gate 90%
* **Frontend**:

  * `pnpm i`
  * `eslint --max-warnings=0`
  * `vitest run` (ou `jest`)
  * `tsc --noEmit`
* **Artifacts**: publicar cobertura e relatório de lint.

### 6.2 Deploy

* **Infra**: Docker + Compose; produção em Kubernetes ou VM com Systemd.
* **Rails**: Puma; **Redis** para Sidekiq/Action Cable.
* **Migrations**: rodar antes do boot da nova versão.
* **Rollback**: manter 2 releases prontos.

---

## 7) Convenções de API

* **Prefix**: por módulo (`/auth/v1`, `/whats/v1`, `/asaas/v1`).
* **Content‑Type**: `application/json; charset=utf-8`.
* **Autorização**: `Authorization: Bearer <jwt>`.
* **Padrão de resposta** (ex.):
* **Descobir endpoints da api:** `http://localhost:3000/swagger_doc`
```json
{
  "data": {"id": "...", "attributes": {...}},
  "meta": {"request_id": "..."},
  "errors": null
}
```

* **Erros**:

```json
{
  "errors": [{"code": "validation_error", "message": "...", "details": {...}}]
}
```

* **Paginação**: `?page=1&per_page=20` + headers `X-Total-Count` e `Link`.
* **Idempotência**: cabeçalho `Idempotency-Key` em POST críticos.

------------------------------------------------------------------------

### 7.1 **Padrão Oficial para API + Services + Entities (OBRIGATÓRIO)**

Esta subseção adiciona diretrizes **formais** que todo endpoint e todo
service devem seguir, baseadas exatamente no padrão adotado em
`UsersService`.

#### ✔️ 1. Toda lógica de negócio deve ficar em Services

Controllers Grape **não podem** conter: - consultas ao banco - blocos
`if/else` de regras - cálculos - parse ou limpeza de dados -
criação/atualização de modelos

#### ✔️ 2. Services DEVEM retornar Entities do Grape para qualquer modelo interno

Sempre que o service retorna dados de modelos, deve retornar:

``` ruby
success_response(Api::Entities::User.represent(user), 200)
```

Ou para coleções:

``` ruby
success_response(
  { users: Api::Entities::User.represent(users), total: total },
  200
)
```

#### ✔️ 3. Controllers NÃO chamam `present`

Eles apenas fazem:

``` ruby
process_service_response(UsersService.index(params))
```

#### ✔️ 4. Estrutura padrão de um service

Todos os services devem conter:

``` ruby
include ApiResponseHandler
```

E sempre retornar usando:

``` ruby
success_response(data, http_status)
error_response(data, http_status)
validation_error_response(message)
not_found_response(model_name)
internal_error_response(error_message)
```

#### ✔️ 5. Entities obrigatórios para qualquer retorno que envolva ActiveRecord

**Proibido** retornar AR diretamente:

❌ Errado:

``` ruby
success_response(user)
```

✔️ Certo:

``` ruby
success_response(Api::Entities::User.represent(user))
```

#### ✔️ 6. Controllers finos ("thin controllers")

Controllers devem conter apenas:

1.  descrição (`desc`)
2.  validação de parâmetros (`params do ... end`)
3.  chamada de serviço
4.  headers de paginação quando aplicável
5.  `process_service_response`

Exemplo obrigatório:

``` ruby
get '' do
  result = UsersService.index(params)
  set_pagination_headers(result[:data][:total], params[:page], params[:per_page])
  process_service_response(result)
end
```

#### ✔️ 7. Padrão único para erros

Todos os serviços devem retornar:

``` json
{
  "errors": [
    { "code": "validation_error", "message": "Mensagem" }
  ]
}
```

Grape NUNCA deve retornar erros crus ou mensagens inconsistentes.

#### ✔️ 8. Documentação Grape obrigatória

Cada endpoint precisa ter:

-   `summary`
-   `detail`
-   códigos HTTP
-   entidade de resposta (quando existir)
-   parâmetros validados

---

## 8) Integrações — Notas Operacionais

### 8.1 Evolution API (WhatsApp)

* Requisitos de autenticação, limites e formato de mensagens centralizados em `services/evolution/*`.
* Webhook único mapeando eventos → comandos de domínio; sempre logar request_id e signature.
* Rejeitar/ignorar duplicados via chave idempotente (message id).

### 8.2 Asaas (Pagamentos)

* **Clientes → Cobranças → Webhooks**.
* Estados: `pending`, `paid`, `refunded`, `failed`, `expired`.
* QR Code PIX obtido e cacheado; broadcasts de mudança de estado.

---

## 9) Temas (Dark/Light)

* **Design tokens** (CSS vars): `--bg`, `--fg`, `--muted`, `--primary`, `--accent`, `--radius`.
* `data-theme="dark|light"` na `<html>`; toggle salva em `localStorage`.
* Testes visuais mínimos por tema (screenshots Storybook/Playwright opcional).

---

## 10) Definition of Done (DoD)

### 10.1 Backend

* [ ] **Docs**: endpoint documentado no Swagger com **exemplos de request/response**, códigos de erro e `Idempotency-Key` quando aplicável.
* [ ] **Testes**: unitários (models/services), requests (Grape), canais (Action Cable), jobs (Sidekiq). Cobertura **≥ 90%** (SimpleCov) e sem `pending`.
* [ ] **Segurança**: params validados (Grape), autenticação/escopos checados, CORS restrito, verificação de assinatura em webhooks (Evolution/Asaas).
* [ ] **Perf**: sem N+1 (Bullet), índices/migrações reversíveis, latência média do endpoint **< 250ms** em dev/profile.
* [ ] **Erros padronizados**: envelope `errors[]` e mapeamento HTTP correto; logs com `request_id`.
* [ ] **Mensageria**: jobs idempotentes e reentrantes; DLQ/retentativas configuradas.
* [ ] **Qualidade**: `rubocop` sem offenses; `brakeman` e `bundler-audit` limpos.

### 10.2 Frontend

* [ ] **Tipagem**: sem `any` não justificado; `tsc --noEmit` sem erros.
* [ ] **UX/Estados**: loading, empty, error e sucesso cobertos; toasts padronizados.
* [ ] **A11y**: navegação por teclado, labels/ARIA, contraste AA; foco visível.
* [ ] **Temas**: dark/light completos, tokens aplicados e persistência do tema.
* [ ] **Tests**: unit (components/hooks) e integração de páginas (React Testing Library/Vitest) verdes.
* [ ] **Performance**: orçamento de bundle `≤ 250KB` (gzip) por rota inicial; imagens otimizadas.

### 10.3 Realtime

* [ ] Canais protegidos por JWT/roles; reconexão exponencial; unsub em unmount.
* [ ] Eventos versionados, payloads tipados e tratados (retry/backoff) no cliente.

### 10.4 Operação & Release

* [ ] **README** atualizado com uso/variáveis/migrações.
* [ ] **Feature flag**/kill-switch se risco alto.
* [ ] **Plano de migração/rollback** verificado (dry run). Migrations **reversíveis**.
* [ ] **Pipeline CI** verde (lint + testes + segurança) e artefatos publicados.

---

## 11) Scripts & Comandos Rápidos

### Backend

```bash
bin/setup            # instala gems, prepara DB
bin/rspec            # roda testes com SimpleCov
rubocop -A           # corrige estilo
brakeman -q -w2      # segurança
bundle audit check   # dependências vulneráveis
sidekiq -C config/sidekiq.yml
```

### Frontend

```bash
pnpm i
pnpm dev            # dev server
pnpm test           # vitest/jest
pnpm lint           # eslint
pnpm build          # produção
```

---

## 12) Checklist de Segurança em Produção

### 12.1 Contas & Acesso

* [ ] Admin/console atrás de **login JWT** + **roles**; MFA obrigatório para contas administrativas.
* [ ] Painéis (Sidekiq/Any admin) com proteção extra (basic auth/IP allowlist).

### 12.2 Segredos & Config

* [ ] Segredos apenas em **Rails.credentials**/variáveis protegidas do CI; nunca em git.
* [ ] Rotação periódica de chaves (Asaas/Evolution/JWT). Algoritmo JWT `RS256` ou `HS256` com chave forte.

### 12.3 Transporte & Headers

* [ ] **HTTPS** obrigatório + **HSTS**.
* [ ] **CSP** restritiva (default-src 'self';) com allowlists mínimas.
* [ ] `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`.

### 12.4 API & Rate Limiting

* [ ] **Rack::Attack** por IP/rota/chaves.
* [ ] Validação de payload (Grape params) e limites de tamanho (`max_content_length`).
* [ ] Webhooks (Asaas/Evolution) com verificação de assinatura/timestamp e **rejeição** de duplicatas.

### 12.5 Dados & Banco

* [ ] Postgres com SSL, usuários mínimos por ambiente, **least privilege**.
* [ ] **Criptografia** at-rest (armazenamento) quando aplicável; hashing de senhas com **bcrypt** (custo adequado).
* [ ] Backups automáticos testados (restore drill) e retenção definida.
* [ ] Índices/constraints para integridade; remoção/anonimização de PII quando desnecessária.

### 12.6 Uploads & Conteúdo

* [ ] Sanitização de uploads (MIME/Extensão), varredura anti‑malware se aplicável.
* [ ] Desabilitar execução em buckets (S3/Cloud) e tornar privados por padrão.

### 12.7 Observabilidade & Resposta a Incidentes

* [ ] Logs estruturados, sem PII sensível; retenção/rotação configuradas.
* [ ] Runbooks para incidentes (webhook fora do ar, fila congestionada, picos de tráfego).

### 12.8 Dependências & Build

* [ ] `brakeman`/`bundler-audit`/`npm audit` limpos; pins em versões seguras.
* [ ] Supply chain: lockfiles com integridade, verificação de assinaturas se disponível.

### 12.9 Realtime

* [ ] Action Cable com Redis autenticado, canais namespaced, checagem de escopos.
* [ ] Limites de broadcast, proteção contra flood, desconexão de clientes ociosos.

### 12.10 Política de CORS & Origem

* [ ] Origens explicitamente **whitelistadas** por ambiente; bloquear wildcard em produção.

---

## 13) Roadmap Inicial (sugestão)

1. Bootstrap Monorepo + CI básico (lint + testes em branco).
2. Autenticação JWT end‑to‑end (login/refresh/logout) + guard no React.
3. Módulo Pagamentos (Asaas): criar cobrança, webhook, realtime status.
4. Módulo WhatsApp (Evolution): envio texto, recepção webhook, canal realtime.
5. Tematização dark/light completa.
6. Observabilidade (Sentry) + limites (Rack::Attack).
7. Harden: idempotência, paginação, erros padronizados, docs ricas.

---

## 14) Áreas do Sistema

* **Site Público**: acessível a todos, consumindo APIs públicas (ex.: landing pages, planos, documentação, política de privacidade, status page).
* **Console Administrativo**: somente para usuários autenticados (JWT) e autorizados por role/scope. Todo o backend é via API e o frontend React controla acesso com guards e refresh token.

### Notas finais

* Este arquivo deve viver na raiz do repositório como **`PROJECT_RULES.md`** e ser lido pelo Trae para orquestrar as tasks.
* Qualquer divergência dessas regras requer **issue** + **aprovação em PR**.
* Para preview rodar ./bin/dev ele ja abre os dois servidores (backend e frontend)
* Backend (API) roda na porta 3000
* Frontend (React) roda na porta 5173
