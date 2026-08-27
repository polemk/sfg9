# Convenções do ai9 (base de destino da migração sfg → ai9)

Documento de calibragem escrito a partir da **leitura do código que já existe neste repositório**
(branch `sfg9`, 2026-08-24). Toda afirmação abaixo tem um caminho de arquivo real como prova.
Onde o repositório é **inconsistente**, isso está registrado como divergência — não foi
"normalizado" na escrita, porque quem for portar código precisa saber com o que vai esbarrar.

---

## 1. Stack e versões exatas

### Backend (`backend/`)

| Item | Versão / valor | Prova |
| :-- | :-- | :-- |
| Ruby (declarado no Gemfile) | `3.2.3` | `backend/Gemfile` (`ruby '3.2.3'`) |
| Ruby (declarado no `.ruby-version`) | `3.4.9` | `backend/.ruby-version` |
| Ruby (imagem Docker) | `ruby:3.2.0-alpine` | `Dockerfile` |
| Ruby (produção real, systemd) | RVM `ruby-3.2.3` | `bin/prod` |
| Rails | `~> 8.0.0` (lock: `8.0.4`), `config.api_only = true` | `backend/Gemfile`, `backend/Gemfile.lock`, `backend/config/application.rb` |
| API framework | `grape` + `grape-entity` + `grape-swagger` + `grape-swagger-entity` + `grape-swagger-rails` | `backend/Gemfile` |
| Banco | PostgreSQL (`pg ~> 1.1`), extensões `pgcrypto` e `vector` habilitadas | `backend/db/schema.rb` (`enable_extension`) |
| Busca vetorial / IA | `pgvector ~> 0.3`, `neighbor ~> 0.6.0`, `ruby-openai ~> 8.3` | `backend/Gemfile` |
| Busca textual | `pg_search ~> 2.3` | `backend/Gemfile`, `Post.search_full_text` |
| Redis | `redis >= 5.0` (imagem `redis:7` no compose) | `backend/Gemfile`, `docker-compose.yml` |
| Jobs | `sidekiq` + `sidekiq-cron` | `backend/Gemfile`, `backend/config/initializers/sidekiq.rb` |
| Realtime | Action Cable, adapter `redis`, mount em `/cable` | `backend/config/cable.yml`, `backend/config/application.rb` |
| Auth | `devise` + `devise-jwt` + `omniauth` (google/facebook) + JWT próprio | `backend/Gemfile`, `backend/app/services/auth/token_service.rb` |
| Rate limit / CORS | `rack-attack`, `rack-cors` | `backend/config/initializers/rack_attack.rb`, `cors.rb` |
| Paginação | `kaminari ~> 1.2` | `backend/Gemfile` |
| HTTP externo | `faraday`, `faraday-multipart`, `httparty` | `backend/Gemfile` |
| Uploads | Active Storage + `image_processing ~> 1.2` + `active_storage_validations` | `backend/Gemfile`, `Showroom#avatar_file_url` |
| App server | `puma ~> 6.4` | `backend/Gemfile` |
| Timezone / locale | `Brasilia`, `:'pt-BR'` default, fallback `:en` | `backend/config/application.rb` |

> **Gems declaradas e NÃO usadas** (verificado por grep em `backend/app/`): `paper_trail`
> (zero `has_paper_trail`), `aasm` (zero `include AASM`), `groupdate`. Não assuma auditoria
> nem máquina de estado pronta — veja §9 (Lacunas).

### Frontend (`frontend/`)

| Item | Versão | Prova |
| :-- | :-- | :-- |
| React / ReactDOM | `^18.2.0` | `frontend/package.json` |
| TypeScript | `^5.2.2` | idem |
| Vite | `^5.0.8` (+ `@vitejs/plugin-react ^4.2.1`) | idem |
| Roteamento | `react-router-dom ^6.20.1` | idem |
| Dados de servidor | `@tanstack/react-query ^5.14.2` | idem |
| HTTP | `axios ^1.6.2` | idem |
| Estado global | `zustand ^4.4.7` | idem |
| CSS | `tailwindcss ^3.3.6` + `tailwindcss-animate ^1.0.7` + `autoprefixer` + `postcss` | idem |
| Primitivos de UI | `@radix-ui/react-*` (accordion, avatar, dialog, progress, slider, switch), `vaul` | idem |
| Ícones | `lucide-react ^0.294.0` | idem |
| Toasts | `sonner ^1.2.4` | idem |
| Realtime | `@rails/actioncable ^7.1.2` (+ `@types/rails__actioncable`) | idem |
| i18n | `i18next ^25.8.0` + `react-i18next ^16.5.4` | idem |
| Gráficos | `recharts ^3.5.1` | idem |
| Animação | `framer-motion ^12.38.0`, `gsap`, `tsparticles` | idem |
| Editor rich text | `@tiptap/react ^3.10.7`, `slate` | idem |
| Fluxos / canvas | `@xyflow/react ^12.10.0` e `reactflow ^11.11.4` (as DUAS presentes) | idem |
| Testes | `vitest ^1.0.4` + `@testing-library/react ^14.1.2` + `jsdom` | idem |
| Lint | `eslint ^8.55.0` + `@typescript-eslint/* ^6.14.0` | idem |
| Gerenciador de pacotes | `packageManager: pnpm@10.32.1` | `frontend/package.json` |

> **Divergência de package manager**: o `package.json` fixa **pnpm**, o `Procfile.dev` usa
> `pnpm dev`, mas `bin/dev` roda `npm install --silent --legacy-peer-deps` e existem
> **os dois lockfiles** (`frontend/pnpm-lock.yaml` e `frontend/package-lock.json`). Para
> código novo, siga o `packageManager`: **pnpm**.

### Infra

- `docker-compose.yml`: `postgres:14`, `redis:7`, `backend` (3000), `frontend` (5173), `sidekiq`.
- `Dockerfile`: multi-stage (`backend-base|dev|prod`, `frontend-base|dev|prod`, `frontend-nginx`).
- `Procfile.dev`: `backend` (rails s -p 3000), `worker` (sidekiq), `frontend` (vite 5173).
- Produção como serviço: systemd via `config/ai9.service.example` + `bin/prod` (ver `DAEMON.md`).

---

## 2. Layout de pastas (caminhos reais)

```
backend/
  app/
    controllers/
      application_controller.rb
      api/root.rb                 # Grape raiz: auth global, rescue_from, swagger
      api/v1/base.rb              # monta todos os módulos /api/v1/*
      api/v1/controller_helpers.rb# helpers compartilhados (auth, paginação, resposta)
      api/v1/<recurso>.rb         # ENDPOINTS Grape (ex.: showrooms.rb, posts.rb, leads.rb)
      api/v1/public/<recurso>.rb  # variantes públicas (sem auth)
      api/auth/v1/*.rb            # /auth/v1/* (magic_login, sessions, oauth, impersonate…)
      api/whats/v1/*.rb           # /whats/v1/*
      api/asaas/v1/*.rb           # /asaas/v1/*
      api/entities/<recurso>.rb   # Grape::Entity (serializers) — SIM, dentro de controllers/
    models/
      <modelo>.rb
      concerns/{identificavel,filtravel_por_origem,acts_as_limited}.rb
    services/
      <recurso>_service.rb        # ex.: showroom_service.rb, lead_service.rb
      <dominio>/<acao>.rb         # ex.: auth/token_service.rb, analytics/track_event.rb
      concerns/api_response_handler.rb
    jobs/<algo>_job.rb
    channels/{application_cable/,<algo>_channel.rb}
    mailers/
  config/
    routes.rb                     # mínimo: monta Api::Root e ActionCable
    application.rb, cable.yml, sidekiq.yml, database.yml.example
    initializers/{cors,rack_attack,sidekiq,devise_jwt,filter_parameter_logging,…}.rb
  db/{migrate/,schema.rb,seeds.rb,seeds/}
  spec/{requests,services,models,jobs,channels,controllers,factories,cassettes}/
  docs/                           # guias de tracking (GA4, GTM, Meta CAPI, UTM)

frontend/src/
  main.tsx                        # QueryClient, BrowserRouter, Helmet, i18n, Analytics
  app/App.tsx                     # TODAS as rotas (React Router), lazy por rota
  app/pages/*.tsx                 # páginas; app/pages/admin/, app/pages/partner/, app/pages/posts/
  features/<dominio>/             # auth, leads, chat-builder, credentials, integrations, marketing, metrics
  components/                     # compartilhados; components/ui/ = design system
  hooks/                          # useAuth, useCable, useTheme, usePlanFeatures…
  store/                          # Zustand "oficial" (authStore, themeStore, couponStore…)
  stores/                         # Zustand de features pontuais (useTerminalStore…) — DUPLICADO, ver §9
  lib/api/{client.ts,endpoints.ts,tokenStore.ts,types.ts,…}
  lib/{i18n.ts,utils.ts,analytics/}
  styles/{globals.css,tokens-campfire.css,easter-theme.css}
  locales/{pt-br,en}/translation.json
  test/setup.ts
```

---

## 3. Backend — padrões

### 3.1 Endpoint Grape

Regra de ouro (`PROJECT_STANDARDIZATION.md`): **o roteamento é 100% Grape**. Não se cria nada
em `backend/config/routes.rb` — ele só monta `Api::Root => '/'`, `/docs` e o Action Cable.

Versionamento **por módulo**, não global:

- `/api/v1/*` → `Api::V1::Base` (`version 'v1', using: :path`, `prefix :api`)
- `/auth/v1/*` → `Api::Auth::V1::Base`
- `/whats/v1/*` → `Api::Whats::V1::Base`
- `/asaas/v1/*` → `Api::Asaas::V1::Base`
- `/public/v1/*` → `Public::V1::*`

Um recurso novo se escreve assim (modelo real: `backend/app/controllers/api/v1/showrooms.rb`):

```ruby
# frozen_string_literal: true

module Api
  module V1
    class Showrooms < Grape::API
      helpers Api::V1::ControllerHelpers

      resource '' do
        desc 'Listar showrooms' do
          summary 'Listar showrooms'
          detail 'Retorna uma lista de showrooms cadastrados (Painel Administrador).'
          success [code: 200, message: 'Ok', model: Api::Entities::Showroom]
          is_array true
        end
        params do
          optional :o, type: Integer, desc: 'Offset'
          optional :l, type: Integer, desc: 'Limit'
          optional :q, type: String,  desc: 'Query de busca'
        end
        get '', http_codes: [[401, 'Unauthorized'], [500, 'Internal Server Error']] do
          response = ShowroomService.list(params)
          process_service_response(response)
        end

        route_param :id do
          # get '' / put '' / delete '' …
        end
      end
    end
  end
end
```

E depois se **monta** em `backend/app/controllers/api/v1/base.rb`, dentro de um `namespace`:

```ruby
namespace :showrooms do
  mount Api::V1::Showrooms
end
```

Pontos obrigatórios:

- `# frozen_string_literal: true` no topo de todo arquivo Ruby novo.
- `desc` com `summary`, `detail`, `success [.. model: Api::Entities::X]` — é isso que alimenta
  o Swagger em `GET /swagger_doc` e o Stoplight em `GET /docs`.
- `params do … end` com `requires`/`optional`, `type:`, `desc:` e `default:` — validação é do
  Grape, não do model. `Grape::Exceptions::ValidationErrors` vira **400** com
  `{ error:, details: }` (`api/v1/base.rb`).
- `http_codes: [...]` listando os códigos de erro documentados.
- Upload de arquivo: `type: File` (showrooms) ou `type: Rack::Multipart::UploadedFile`
  (`api/v1/posts.rb`). As duas formas existem; prefira `Rack::Multipart::UploadedFile`.

### 3.2 Duas formas de responder (as duas existem no repo)

1. **Service → `process_service_response`** (dominante). O endpoint chama o service e passa
   adiante. Definido em `backend/app/controllers/api/v1/controller_helpers.rb`:
   sucesso devolve `response[:data]`; erro chama `error!({ error:, details? }, status)`.
2. **`present … with: Api::Entities::X`** direto no endpoint (ex.: `api/v1/posts.rb` linha 50).

Escolha 1 para CRUD com regra de negócio; 2 só para listagens finas já resolvidas em escopo.

### 3.3 Formato de erro

Contrato de saída do service — `backend/app/services/concerns/api_response_handler.rb`:

```ruby
success_response(data, 200)      # => { success: true,  data:, status: }
error_response(msg, 422, details: nil)
not_found_response('Showroom')   # 404 "Showroom não encontrado"
validation_error_response(msg)   # 422
internal_error_response(msg)     # 500
unauthorized_response / forbidden_response / conflict_response / rate_limit_response
no_content_response              # 204
```

Na borda HTTP o cliente recebe `{ "error": "<mensagem>", "details": … }` com o status certo.
Mensagens de erro voltadas ao usuário são **em pt-BR**.

> **Armadilha conhecida**: o `rescue_from :all` em `api/root.rb` e em `api/v1/base.rb` devolve
> `e.message` + `backtrace` no corpo da resposta 500. É vazamento de stack para o cliente.
> Ao portar telas do `sfg`, **não confie** nesse comportamento como contrato e evite propagá-lo.

### 3.4 Paginação

Dois estilos, ambos vivos:

- **Kaminari + header** (preferido): `scope.page(page).per(per_page)` e depois
  `set_pagination_headers(scope.total_count, page, per_page)` — emite `X-Total-Count`,
  `X-Page`, `X-Per-Page` (`controller_helpers.rb`). Os headers estão expostos no CORS
  (`expose: %w[X-Total-Count Link Content-Disposition]`, `backend/config/initializers/cors.rb`).
  Exemplos: `api/v1/posts.rb`, `api/v1/integrations.rb`, `api/v1/operations.rb`, `api/v1/users.rb`.
- **Offset/limit por query `o`/`l`** (legado, showrooms/media): `params[:o]`, `params[:l]`, `params[:q]`.

Alguns services também devolvem `meta: { total:, page:, per_page: }` no `data`
(`lead_service.rb:85`). Para código novo: **Kaminari + `set_pagination_headers`**.

### 3.5 Grape::Entity (serializer)

Ficam em `backend/app/controllers/api/entities/`. Padrão (`api/entities/showroom.rb`):

```ruby
module Api
  module Entities
    class Showroom < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'ID do item' }
      expose :partnership, documentation: { type: 'Boolean', desc: 'Se possui parceria' } do |s|
        s.partnership?
      end
      expose :media, using: Api::Entities::Medium, documentation: { type: 'Array', desc: '…' }
      expose :created_at, :updated_at
    end
  end
end
```

Todo `expose` leva `documentation:` (é o que gera o Swagger). Nomes dos campos = colunas do
banco (inglês); as descrições são em pt-BR.

### 3.6 Service object

Convenção dominante: **classe com `class << self`**, métodos de classe, incluindo
`ApiResponseHandler`. Modelo real (`backend/app/services/showroom_service.rb`):

```ruby
# frozen_string_literal: true

class ShowroomService
  class << self
    include ApiResponseHandler

    def list(params)      … success_response(Api::Entities::Showroom.represent(rel).as_json, 200) end
    def get_showroom(id)  … return not_found_response('Showroom') unless showroom … end
    def create(params)
      …
      if showroom.save
        success_response(Api::Entities::Showroom.represent(showroom).as_json, 201)
      else
        validation_error_response(showroom.errors.full_messages.join(', '))
      end
    rescue StandardError => e
      internal_error_response(e.message)
    end

    private

    def attach_file(record, name, file) … end
  end
end
```

Variante para domínios com subpasta: `Auth::TokenService`, `Analytics::TrackEvent`,
`Omnichannel::DispatchService` (esta usa `.call(...)` — `backend/app/jobs/omnichannel_dispatch_job.rb`).
Nomes: `<Recurso>Service` na raiz, `<Dominio>::<Acao>` quando agrupado.

### 3.7 Job

`backend/app/jobs/<algo>_job.rb`, herda de `ApplicationJob` (`ActiveJob::Base`), adapter Sidekiq.

```ruby
# frozen_string_literal: true

class OmnichannelDispatchJob < ApplicationJob
  queue_as :default

  def perform(message_id)
    message = LeadMessage.find_by(id: message_id)
    return unless message
    result = Omnichannel::DispatchService.call(lead: message.lead, …)
    Rails.logger.info "🚀 [Omnichannel] Dispatched via #{result[:provider]} …"
  rescue StandardError => e
    Rails.logger.error("[OmnichannelDispatchJob] Dispatch Error: #{e.message}")
  end
end
```

Regras:
- Job recebe **IDs**, nunca objetos AR; e sai cedo (`return unless`) se o registro sumiu.
- Filas são **prefixadas por `APP_NAME`** (`config.active_job.queue_name_prefix`,
  delimitador `_`) → `ai9_default`, `ai9_mailers`, `ai9_webhooks`, `ai9_transcriptions`,
  `ai9_low_priority` (`backend/config/sidekiq.yml`). **Se você criar uma fila nova com
  `queue_as`, adicione-a ao `sidekiq.yml` ou o job empilha para sempre** — é o bug documentado
  em comentário no próprio arquivo.
- **Cron**: `sidekiq-cron` carregado em `config.on(:startup)` dentro de
  `backend/config/initializers/sidekiq.rb` via `Sidekiq::Cron::Job.load_from_hash`. Não há
  `schedule.yml`. Horário em UTC, com o equivalente BRT no comentário.

### 3.8 Channel (Action Cable)

`backend/app/channels/<algo>_channel.rb`. Autorização acontece no `subscribed`, com `reject`.

```ruby
class LeadChatChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user&.og?
    lead = Lead.by_any_id(params[:lead_id])
    return reject unless lead
    stream_from "lead_chat_#{lead.id}"
  end
  def unsubscribed; end
end
```

Broadcast a partir de callback de model (`backend/app/models/lead_message.rb:140`) ou de
service/job: `ActionCable.server.broadcast("lead_chat_#{lead_id}", payload)` para stream
nomeada, ou `DashboardChannel.broadcast_to("kpis", payload)` para `broadcast_for`.
Payload sempre com `type:` (`'message_created'`, `'lead_updated'`, `'payment_update'`…), que é
o discriminador que o frontend lê.

`ApplicationCable::Connection` (`backend/app/channels/application_cable/connection.rb`):
- `identified_by :current_user`
- Token do handshake vem do **cookie HttpOnly `cable_token`** (escopo `/cable`); fallback ao
  query param `?token=` só para clientes antigos. **Não coloque token na URL.**
- Verifica denylist (`Auth::TokenService.revoked?`) e recusa `payload['type'] == 'refresh'`.
- Conexão anônima é permitida (chat público).

### 3.9 Autenticação (JWT) e autorização

**Onde acontece**: um `before do … end` gigante em `backend/app/controllers/api/root.rb`.
Ele:
1. Trata webhooks Asaas por token dedicado (`Asaas-Access-Token` / `ClientApplication`).
2. Deixa passar rotas de uma **allowlist por regex de path** (`public_paths`). Há um comentário
   explícito no código: **nunca reintroduzir bypass por header** (`X-Skip-Auth` já vazou a base
   de leads inteira até 01/08/2026). Endpoint público entra na allowlist **por rota**.
3. Caso contrário autentica por Warden/Devise-JWT, senão pelo `Auth::TokenService`, senão
   por `ClientApplication.active.find_by(token:)`; e publica `env['api.current_user']` /
   `env['api.current_client']`.

**Tokens** (`backend/app/services/auth/token_service.rb`):
- Algoritmo `HS256`, segredo `ENV['DEVISE_JWT_SECRET_KEY']` (fallbacks: `JWT_SECRET`, credentials).
- `ACCESS_TTL` = `JWT_EXPIRATION_TIME_MINUTES` (default **15 min**).
- `REFRESH_TTL` = `JWT_REFRESH_EXPIRATION_DAYS` (default 30 dias), claim `type: 'refresh'` + `jti`.
- `CABLE_TTL` = `JWT_CABLE_EXPIRATION_HOURS` (default 12h), claim `type: 'cable'`, só serve para
  abrir WebSocket.
- Impersonação: `generate_impersonation_tokens(true_user_id)` embute `impersonated_by`.
- Revogação: tabela `jwt_denylist` consultada por `Auth::TokenService.revoked?`; **chame-a sempre
  que decodificar fora do `decode_token`** (o decoder do Warden não consulta a denylist).
- Refresh: `POST /auth/v1/sessions/refresh` — está na allowlist pública **de propósito** (o access
  já expirou quando ele é chamado).

**Autorização** — não há Pundit/CanCan. É feita por helpers em `api/v1/controller_helpers.rb`:

```ruby
authenticate_user!        # 401 se não houver env['api.current_user']
current_user
require_og!               # 403 'Somente usuários OG' (libera ClientApplication)
restrict_visitor_access!  # 403 code: 'VISITOR_RESTRICTED' em qualquer verbo != GET/HEAD
```

`restrict_visitor_access!` roda em **todo** `/api/v1/*` (`before do` em `api/v1/base.rb`).
Papéis vêm de `User#og?`, `#client?`, `#visitor?`, `#free?`, que comparam
`user_type.name.downcase` (`backend/app/models/user.rb:146-160`). Há também um modelo de
permissões granulares (`Permission` com `key`/`title`/`is_active`/`sort_order`,
`UserPermission` com `source`/`granted_at`/`revoked_at`, `PlanFeaturePermission`), sincronizado
por `PermissionsSyncService`, que faz push por `PermissionsChannel.broadcast_to("permissions:#{user.id}", …)`.

**Impersonação** já existe: `backend/app/controllers/api/auth/v1/impersonate.rb`
(`POST /auth/v1/impersonate/start` e `/stop`), com `Auth::ImpersonateService`.

### 3.10 Logging

- `Rails.logger.info/warn/error` com **prefixo de tag entre colchetes**: `[OmnichannelDispatchJob]`,
  `[TokenService]`, `[Omnichannel]`. Emojis aparecem em logs de job (🚀, ⚠️) — é o estilo da casa.
- Parâmetros sensíveis filtrados em `backend/config/initializers/filter_parameter_logging.rb`
  (`passw secret token _key crypt salt certificate otp ssn code login_code magic_code`).
- `ActionMailer::MailDeliveryJob.log_arguments = false` (`initializers/active_job_log_filter.rb`)
  para não logar magic codes.

### 3.11 Config, segredos e ENV

- `dotenv-rails`. Arquivos: `backend/.env`, `frontend/.env`, `.env` na raiz — **todos gitignored**;
  os versionados são `*.env.example` e `.env.secrets.example`.
- `backend/config/database.yml` é **gitignored** (`.gitignore` linha 23); o versionado é
  `backend/config/database.yml.example`. Decisão registrada no próprio arquivo: cada branch de
  migração ganha **banco próprio** (a branch `pika9` usa `pika9_dev`/`pika9_test`), para não
  misturar dado do produto base com dado do cliente migrado. **Faça o mesmo para `sfg9`.**
- Troca de ambiente: `bin/switch_env local|ngrok <url>|prod` regenera os `.env` a partir de
  `.env.secrets` (documentado em `README.md` e `BUILD_SYSTEM.md`).
- ENV mais relevantes: `APP_NAME` (prefixo de filas Sidekiq e título do Swagger), `DATABASE_URL`,
  `REDIS_URL`, `CORS_ORIGINS`, `DEVISE_JWT_SECRET_KEY`, `SECRET_KEY_BASE`, `API_HOST`,
  `ACTION_CABLE_URL`, `SESSION_KEY`, `COOKIES_SAME_SITE`, `SIDEKIQ_CONCURRENCY`,
  `ASAAS_*`, `WHATS_*`, `META_WEBHOOK_VERIFY_TOKEN`, `SMTP_*`.
- Frontend: só `VITE_*` (`VITE_API_URL`, `VITE_WS_URL`, `VITE_BACKEND_URL` para o proxy do Vite,
  `VITE_GOOGLE_API_KEY`, `VITE_DISCORD_SERVER_URL`).

---

## 4. Dados — padrões

- **IDs**: **mistos**. 34 de 96 tabelas usam `id: :uuid, default: -> { "gen_random_uuid()" }`
  (`backend/db/schema.rb`) — ex.: `showrooms`, `access_codes`, `posts`, `categories`. As demais
  usam bigint. Para código novo, siga o padrão da tabela vizinha do domínio; se for domínio novo,
  **use UUID** (é o que as migrações recentes fazem).
- **`smart_id`**: além do id técnico, vários modelos têm um identificador legível gerado em
  `before_create :generate_smart_id` (`Operation`, `Lead`, `Purchase`) e um lookup dual
  `Model.by_any_id(id)` que aceita id numérico **ou** `smart_id`. Endpoints e canais usam
  `by_any_id`. Reproduza isso em recursos expostos por URL.
- **Migrações**: `ActiveRecord::Migration[8.0]`, `def change` (ou `def up`/`down` quando
  irreversível). Nomes de arquivo com timestamp; as antigas são geradas pelo Rails
  (`20260228132314_create_showrooms.rb`), as recentes são **escritas à mão e nomeadas em pt-BR**
  (`20260808020000_goat_alcanca_o_modelo_de_pessoa.rb`, `20260808060000_sessao_de_chat_nasce_sem_lead.rb`).
  As colunas continuam em inglês; o **nome da classe da migração** e o comentário-cabeçalho longo
  explicando o porquê (às vezes 20 linhas) são pt-BR. Esse cabeçalho é esperado.
- **Índices**: declarados explicitamente na migração, com `unique:` e, quando aplicável,
  **índice parcial** (`where: 'visitor_id IS NOT NULL'`) e `name:` explícito. Colunas ganham
  `comment:` descrevendo a semântica — ver a migração `goat_alcanca_o_modelo_de_pessoa`.
- **Enums**: sintaxe Rails 8, `enum :campo, { … }`, com valores **string** na maioria
  (`enum :state, { pending: 'pending', … }, default: 'pending', suffix: true` em `Delivery`),
  ocasionalmente inteiro (`ChatFlow#kind`). Prefira string.
- **Dinheiro**: `t.decimal precision: 14, scale: 2` (custos/preços de order) — mas há
  `precision: 10, scale: 3` em `plans`. Para o domínio financeiro do `sfg`, padronize
  `decimal(14,2)` e registre a decisão.
- **Soft delete**: **não existe** gem nem coluna `deleted_at`. O que existe é status explícito:
  `PostDraft` usa `status: 'discarded'` + `discarded_at` + job de purga
  (`PurgeDiscardedDraftsJob`). Se o `sfg` precisa de exclusão lógica, é padrão novo (§9).
- **Auditoria**: `paper_trail` está no Gemfile e **não é usado**. Existe auditoria *ad hoc*:
  `PermissionAuditLog` (entity em `api/entities/permission_audit_log.rb`) e `UserPermission`
  com `granted_at`/`revoked_at`/`source`. Não há trilha genérica.
- **Multi-tenancy**: **não existe**. Zero `acts_as_tenant`, zero `tenant_id`/`account_id`/
  `organization_id` em `backend/app/models/`. `Operation` é agrupador de domínio (leads, flows,
  assets), não isolamento de dados. Um comentário em `blog_intake_session.rb` diz explicitamente
  "single-tenant (sem operation_id)".
- **Concerns de model** existentes e reaproveitáveis: `Identificavel` (níveis
  `anonimo`/`contactavel`/`identificado`, `caminhos_de_contato`, `confirmar_nome!`),
  `FiltravelPorOrigem`, `ActsAsLimited` (registra o model como recurso limitável por plano,
  com enforcement em `before_create` — o exemplo do próprio docstring é `class Contract`).
- Validações no model (`validates :key, presence: true, uniqueness: true`), escopos nomeados
  (`scope :active`, `scope :ordered`), `dependent: :destroy|:nullify` sempre explícito.

---

## 5. Frontend — padrões

### 5.1 Bootstrap e roteamento

`frontend/src/main.tsx` monta, nesta ordem: `QueryClientProvider` → `HelmetProvider` →
`BrowserRouter` → `AnalyticsProvider` → `App`. Antes de renderizar chama
`purgeLegacyTokenStorage()`.

`QueryClient` padrão do app:

```ts
new QueryClient({ defaultOptions: { queries: { staleTime: 0, retry: 1, refetchOnWindowFocus: false } } })
```

`frontend/src/app/App.tsx` concentra **todas** as rotas. Toda página é `lazy(() => import(...))`
com `Suspense fallback={<PageLoader />}`. Guardas de rota são componentes:
`ProtectedRoute`, `OgRoute`, `ClientRoute`, `VisitorRoute` (em `frontend/src/components/`).
Layout autenticado: `<ProtectedRoute><Layout /></ProtectedRoute>` como rota-pai com `<Outlet/>`.

> As URLs de rota são **mistas**: `/dashboard`, `/plans`, `/checkout/:identifier` (inglês) convivem
> com `/vendas`, `/guia-rastreamento` (pt-BR). Para código novo: **inglês** (§8).

### 5.2 Camada de dados — **NÃO é RTK Query** ✅ verificado

Confirmado por leitura: **não há `@reduxjs/toolkit`, nem `react-redux`, nem RTK Query** em
`frontend/package.json`. A menção a `@RTK.md` no `CLAUDE.md` do usuário é resíduo e **não
descreve este repositório**. A camada real é **Axios + `endpoints.ts` + React Query + Zustand**:

**(a) Cliente Axios** — `frontend/src/lib/api/client.ts`. Classe `ApiClient` singleton
exportada como `apiClient`. `baseURL = import.meta.env.VITE_API_URL`, `timeout: 30000`,
`withCredentials: true` (para o cookie HttpOnly de refresh, `Path=/auth/v1`).

- Interceptor de request: injeta `Authorization: Bearer <accessToken>` lendo do `tokenStore`,
  a menos que o header `X-Skip-Auth: '1'` esteja presente.
- Interceptor de response:
  - `403` com `data.code === 'VISITOR_RESTRICTED'` → abre o `UpgradeModal` global.
  - `401` → refresh **único** com fila (`isRefreshing` + `refreshQueue`), reenvia a requisição
    original com o token novo; se o refresh falhar, `endSession()` (limpa tokens, `logout()` do
    authStore, redireciona para `/login`).
- Métodos: `get/post/put/patch/delete`, mais `getRaw` (resposta completa, p/ blob),
  `getPublic`, `postPublic`, `postPublicForm` (que só adicionam `X-Skip-Auth`).

**(b) Tokens** — `frontend/src/lib/api/tokenStore.ts`. Store Zustand **sem `persist`**:
o access token vive **só em memória**; o refresh token vive em **cookie HttpOnly** invisível ao JS.
`useAccessToken()` é o hook reativo (é o que dispara a reconexão do WebSocket).
`purgeLegacyTokenStorage()` limpa resíduos de versões antigas em `localStorage`.
**Nunca** persista token em `localStorage`.

**(c) Contrato central de endpoints** — `frontend/src/lib/api/endpoints.ts` (**1530 linhas**).
Um objeto exportado por recurso, com métodos que só montam URL + chamam `apiClient`. Nunca
se chama `axios` direto numa página.

```ts
export const showroomsApi = {
  list: (o = 0, l = 100, q?: string) =>
    apiClient.get<Showroom[]>(`/api/v1/showrooms?o=${o}&l=${l}${q}`),
  get: (id: string) => apiClient.get<Showroom>(`/api/v1/showrooms/${id}`),
  create: (data: Partial<Showroom>) => apiClient.post<Showroom>("/api/v1/showrooms", data),
  update: (id: string, data: Partial<Showroom>) => apiClient.put<Showroom>(`/api/v1/showrooms/${id}`, data),
  delete: (id: string) => apiClient.delete(`/api/v1/showrooms/${id}`),
};
export const showroomsPublicApi = { list: … apiClient.getPublic(…) };
```

Tipos ficam em `frontend/src/lib/api/types.ts`. Alguns recursos maiores têm arquivo próprio
(`lib/api/auth.ts`, `credentials.ts`, `chatFlow.ts`, `downloads.ts`, `publicChat.ts`,
`operationAssets.ts`) reexportado por `endpoints.ts`; features têm sua própria camada quando
o domínio é grande (`features/chat-builder/api/builder.ts`).

**(d) React Query** — direto na página/componente, sem hook-fábrica genérico:

```ts
const queryClient = useQueryClient()
const { data, isLoading } = useQuery({ queryKey: ['showrooms'], queryFn: () => showroomsApi.list() })
const createMutation = useMutation({
  mutationFn: showroomsApi.create,
  onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['showrooms'] }) },
})
```

- **Query keys**: array com string kebab/lowercase do recurso, mais os parâmetros que variam —
  `['showrooms']`, `['leads']`, `['leads-stats']`, `['lead-messages', selectedId]`
  (`frontend/src/app/pages/ShowroomsPage.tsx`, `frontend/src/app/pages/LeadsChatPage.tsx`).
- **Invalidação**: sempre em `onSuccess` da mutation, por `queryKey`. Não se faz update otimista
  em lugar nenhum do repo.

**(e) Zustand** — `frontend/src/store/`. Padrão: `create<T>()(persist((set) => ({…}), { name, partialize }))`.
Exemplo canônico `authStore.ts`:
- `persist` com `name: 'auth-storage'` e **`partialize` explícito** — persiste `isAuthenticated`,
  `user`, `impersonating`, `trueUser`. **Tokens nunca entram no partialize.**
- Estado + actions no mesmo objeto; hooks derivados exportados do arquivo (`useRole()`).
- `themeStore.ts`: `persist` `name: 'theme-storage'`.
- Stores efêmeras (sem persist): `tokenStore.ts`, `stores/useTerminalStore.ts`.

### 5.3 Formulários e validação

**Não há `react-hook-form`, `zod` nem `yup`** no `package.json`. Formulários são
componentes controlados com `useState` + validação manual; a validação forte é a do Grape
(`params do … end`) e do model. Toasts de erro via `sonner`. Componentes de campo em
`frontend/src/components/ui/` (`Input.tsx`, `Label.tsx`, `textarea.tsx`, `SearchableSelect.tsx`,
`SearchableMultiSelect.tsx`, `Slider.tsx`, `switch.tsx`) e `components/PhoneInputGroup.tsx`.

### 5.4 Marca Safegold, tokens e tema — **leia antes de estilizar qualquer coisa**

> Reescrito em 25/08/2026 pelo `theming-brand-engineer`. Esta seção não descreve
> mais o tema default do ai9: ela descreve o tema **Safegold** que substituiu o
> default. Se você está construindo tela, **esta é a seção que você tem que ler
> inteira** — ela é o contrato que impede a base de voltar a ser o ai9.

#### 5.4.1 A marca

Fonte canônica: `../sfg/app/definitions/SFG/theme.rb`. Confirmada contra os pixels
do arquivo de logo (`app_logo_full_original.png`).

| Peça | Valor | Onde vive no ai9 |
| ---- | ----- | ---------------- |
| Grafite (ink) — `COLOR__PRIMARY` | **#2D2D2A** | `--brand-ink`, e é o `--foreground` do claro |
| Ouro — `COLOR__ACCENT` | **#FFC107** | `--brand-gold`, e é o `--primary` nos DOIS modos |
| Ouro do logo (hover/pressed) | **#EB9600** | `--brand-gold-deep` |
| Aço auxiliar — `COLOR__ACCENT_AUX` | #607D8B | `--brand-steel` |
| Indicador positivo | #217B55 | `--success` (claro) |
| Indicador negativo | #7D1F1E | `--negative` (claro) |
| Fonte de texto e título | **Work Sans** | `--font-title`, `--font-text` |
| Fonte numérica | **Fira Mono** | `--font-numeric` |

**Divergência de `primary`, resolvida:** havia três valores concorrentes no legado
(`theme.rb` #2D2D2A · `colors.scss` #050517 · factory do banco #373435). Vale o
`theme.rb`, e a amostragem do PNG do logo (#292C28) confirma: é grafite morno, não
navy. #050517 fica registrado como variante herdada do SCSS e **não** é usado.

**Logos:** `frontend/public/images/brand/` — `safegold-logo{,-white}.png`,
`safegold-wordmark{,-white}.png`, `safegold-symbol{,-white}.png`,
`safegold-icon-{32,180,192,512}.png`. Gerados a partir do original vetorizado do
legado (fundo branco removido com alpha real, recorte por bounding box).
**Nunca use esses caminhos direto numa tela** — use o componente:

```tsx
import { Logo } from '@/components/brand/Logo'
<Logo variant="full" height={28} />        // símbolo + palavra
<Logo variant="symbol" height={24} />      // sidebar recolhida, avatar
<Logo variant="full" height={34} onDark /> // superfície escura fixa
```
A variante clara/escura é escolhida por CSS (`.brand-logo-light` /
`.brand-logo-dark`), não por JS: nasce certa no primeiro paint e não pisca.

#### 5.4.2 Tokens — a regra de ouro

**Nunca escreva cor em componente.** Nem `#hex`, nem `rgb()/rgba()`, nem
`bg-blue-500`, nem `text-white`, nem `border-white/10`, nem `dark:bg-slate-900`.
Cor vem **sempre** do token semântico, e o token já muda sozinho entre claro e
escuro. Se você precisou de uma variante `dark:` para consertar cor, você
hardcodou cor.

Os dois modos são definidos **por inteiro** em `frontend/src/styles/globals.css`
(`:root` = claro, `.dark` = escuro, `.surface-dark` = espelho do escuro para
forçar bloco escuro dentro do claro). Nenhum token existe só em um modo. Se você
adicionar um token, adicione **nos três blocos**.

| Classe Tailwind | Quando usar |
| --------------- | ----------- |
| `bg-background` / `text-foreground` | o chão da página e o texto normal |
| `bg-card` / `text-card-foreground` | superfície elevada: card, painel, linha |
| `bg-popover` / `text-popover-foreground` | flutuante: dropdown, dialog, drawer, tooltip |
| `bg-muted` / `text-muted-foreground` | fundo neutro; texto secundário/legenda |
| `bg-secondary` / `text-secondary-foreground` | superfície alternativa discreta |
| `bg-accent` / `text-accent-foreground` | **superfície de hover** — não é o ouro |
| `bg-primary` / `text-primary-foreground` | **a ação** — é o ouro Safegold |
| `text-primary` (e `text-warning`, `text-success`…) | a mesma cor semântica **escrita como texto** — ver o quadro abaixo |
| `bg-destructive` / `…-foreground` | apagar/encerrar |
| `bg-success` `bg-warning` `bg-info` `bg-negative` (+ `-foreground`) | estado e indicador |
| `bg-brand-gold` `bg-brand-gold-deep` `bg-brand-ink` `text-brand-steel` | só quando a peça **é** a marca (faixa, selo, logo) |
| `border-border` / `border-input` / `ring-ring` | traço e foco |

Não-cor: raio `rounded-sm|md|lg` (derivam de `--radius: 0.75rem`) — nada de
`rounded-2xl`/`rounded-[900px]`. Elevação `shadow-e1|e2|e3` — nada de
`shadow-[0_4px_…]`. z-index **nomeado**: `z-base z-sticky z-fab z-drawer-backdrop
z-drawer z-parede z-brand z-modal-backdrop z-modal z-toast z-tooltip` — nunca
`z-[999]`. Espaçamento: escala padrão do Tailwind, nada de `p-[13px]`.

**`text-primary` NÃO é a mesma cor que `bg-primary` — e isso é de propósito.**
Uma cor de estado é usada de dois jeitos opostos e um valor só não serve aos
dois. `bg-primary` quer o ouro **cheio** da marca, com grafite por cima
(10,4:1). `text-primary` quer a mesma ideia em letra de 12px — e ouro `#FFC107`
sobre branco dá **1,63:1**, que reprova AA por mais de três vezes. Clarear o
ouro conserta o texto e estraga o botão; escurecer faz o contrário.

Por isso existem os tokens `-text` (`--primary-text`, `--warning-text`,
`--destructive-text`, `--success-text`, `--info-text`, `--negative-text`), e o
`tailwind.config.js` mapeia **só `textColor`** para eles — `backgroundColor`,
`borderColor` e `ringColor` continuam no token de fundo.

**Para você isso não muda nada:** escreva `text-primary` e sai legível nos dois
modos. O que você **não** deve fazer é "consertar" o contraste na tela com uma
cor própria ou um `dark:`. Se mexer nos tokens, mexa no par inteiro e confira
os **dois** modos — no escuro o ouro cheio já dá 10:1 e `--primary-text` volta a
ser o próprio ouro; foi sempre o claro que era o problema.

`text-brand-gold` **não** é rebaixado: ali a cor é o assunto (faixa, selo,
logo), não o texto.

**Número é token também:** todo valor monetário, KPI e coluna numérica leva
`font-numeric` (Fira Mono + `tabular-nums`). Sem isso a coluna de valor de um
borderô não alinha, e neste app isso é defeito, não estética.

#### 5.4.3 Botão — existe UM, com CINCO variantes

`frontend/src/components/ui/Button.tsx`. Variantes canônicas, e não há uma sexta:

| Variante | O que é |
| -------- | ------- |
| `primary` (padrão) | ouro sólido. A ação principal. No máximo uma por bloco |
| `secondary` | contorno discreto. Cancelar, voltar, filtrar |
| `ghost` | sem fundo até o hover. Ícone de barra, ação terciária em linha |
| `destructive` | vermelho sólido. Só para o que apaga de verdade |
| `link` | texto sublinhado no hover |

Tamanhos: `default | sm | lg | icon`. `type` já cai em `"button"` por padrão —
declare `type="submit"` explicitamente em form.

As variantes antigas do ai9 (`default`, `outline`, `gradient`, `uiverse`) **foram
removidas** e os call sites migrados. Não as reintroduza.

**Proibido passar cor no `className` do Button.** `className` é só layout
(`w-full`, `mt-4`, `flex-1`). Se você escreveu
`<Button className="bg-emerald-600 text-white rounded-xl">`, você acabou de
recriar o botão nessa tela — que é exatamente o que a padronização matou. Dois
botões da mesma variante têm que renderizar idênticos em qualquer lugar.

`<button>` cru continua legítimo para o que **não é** um botão visual: item de
dropdown, aba, célula/card clicável, ponto de carousel, nó de canvas. Nesses
casos ainda assim: token na cor, `type="button"` e
`focus-visible:ring-2 focus-visible:ring-ring`.

#### 5.4.4 Superfície flutuante — as duas armadilhas que já morderam

Todo painel que flutua (menu suspenso, select, combobox, tooltip, popover,
dialog, sheet, drawer, toast) usa **`bg-popover text-popover-foreground border
border-border shadow-e2|e3`**. Nunca `bg-card`, nunca `bg-background`, nunca cor
literal. Duas coisas já quebraram por causa disso e valem regra:

**1. Contraste do `--popover` contra o que está atrás.** Um popover só existe se
for visivelmente mais claro (no escuro) que o `--card` embaixo dele. Chegamos a
ter `--card: 60 4% 12%` e `--popover: 60 4% 13%`: 1% de diferença, e o painel
aberto parecia transparente. Hoje o escuro é `--popover: 60 4% 18%` — três
degraus acima de `--background` (9%) e do `--card` (12%). Se você mexer nesses
três, mexa mantendo a distância.

**2. Contexto de empilhamento, não z-index.** `z-modal` no painel não adianta
nada se um ancestral criar um contexto de empilhamento mais baixo: o filho fica
preso dentro dele. Foi o defeito do `SidebarModeToggle`/`ImpersonateSelector` —
o bloco que os hospeda e o `<nav>` logo abaixo estavam **os dois em `z-10`** e,
empatados, quem vem depois no DOM ganha; o menu aberto ia parar atrás dos itens
do menu. A correção é no ancestral (`z-sticky` no bloco, `z-base` no `<nav>`),
nunca subindo o z do painel.

Lembre que **`transform`, `filter`, `backdrop-filter`, `opacity < 1`, `isolation`
e `will-change` criam contexto de empilhamento mesmo sem `position`**. Um
`backdrop-blur` inocente num contêiner intermediário prende todos os popovers de
dentro dele.

E: um popover **fechado** parece perfeito nos dois modos. **Abra cada um** antes
de dizer que verificou.

#### 5.4.5 Onde a cor literal ainda é permitida

Um lugar só: **template de e-mail** (`backend/app/views/layouts/mailer.html.erb` e
`app/views/auth_mailer/*`). Cliente de e-mail não entende custom property nem
classe Tailwind. Os hex de lá são os mesmos tokens da marca e estão comentados no
topo do layout — se a marca mudar, mude os dois lugares.

#### 5.4.6 Como o tema é aplicado

`frontend/src/hooks/useTheme.ts` remove `light`/`dark` de `document.documentElement`,
adiciona o atual e seta `data-theme`. `frontend/src/store/themeStore.ts` persiste
(`theme-storage`), default **`'light'`** — que é o modo que corresponde ao legado.
`components/ThemeProvider.tsx` só chama `useTheme()`; `components/ThemeToggle.tsx`
alterna e está exposto no login.

#### 5.4.7 Checklist antes de abrir PR de tela

1. `grep -nE "#[0-9a-fA-F]{3,6}|rgba?\(|bg-gradient|z-\[" <seus arquivos>` volta vazio.
2. Nenhuma classe de paleta literal do Tailwind (`slate-`, `blue-`, `white`, `black`…).
3. Todo botão é `<Button>` com uma das cinco variantes, sem cor no `className`.
4. Todo valor numérico tem `font-numeric`.
5. Você **abriu a tela nos dois modos** e olhou — incluindo **abrir cada menu,
   select, modal e tooltip** dela. `tsc` limpo não é verificação visual: o
   type-check passa perfeitamente com um popover invisível.
6. Você **abriu a tela em 390×844** e olhou (DEC-100, §5.4.8). Mesmo peso do item 5:
   tela sem versão mobile verificada **não fecha tarefa**.

#### 5.4.8 Mobile — **views próprias, não responsivo por breakpoint** (DEC-100)

> Escrito em 25/08/2026 pelo `mobile-pwa engineer`, depois que a conferência mostrou que
> **só 7 das 21 fatias mencionavam mobile no `tasks.md`**. Sem este padrão escrito, cada
> fatia inventa o seu jeito de mostrar lista no celular — e depois não há passada de
> correção que unifique sete telas diferentes.

**Critério de aceite, mesmo peso do dark mode (DEC-98): tela sem versão mobile verificada
não fecha tarefa.** Verificação é **renderizar em 390×844 e olhar**, com captura. `tsc`
limpo e `vitest` verde não provam nada disso — uma barra de abas com os rótulos sobrepostos
passa nos dois.

##### O que "sensação nativa" significa aqui, em termos concretos

Não é animação nem imitação de iOS. São seis coisas mensuráveis:

1. **Alvo de toque de no mínimo 44 px** (usamos `min-h-[3rem]`). Botão de 32 px é alvo de
   mouse, não de polegar.

   **Isso é responsabilidade dos componentes da biblioteca, não da tela.** Desde 26/08/2026
   `Button`, `Input`, `SearchInput`, `DatePicker`, `Select` (gatilho **e** opções), `tabs`,
   `switch`, `Checkbox` sem rótulo, a trilha do `PageHeader` e os gatilhos do
   `MobileRowActions`/`MobileTopBar` já nascem com 44 px abaixo de `md` e voltam à densidade
   do desktop a partir dele. A passada mediu 31 das 33 telas auditadas com alvo abaixo do
   mínimo **antes** disso, e nenhuma delas por descuido: todas herdavam o mesmo `h-10`.
   Consertar em centenas de call sites com `className="min-h-[3rem]"` é a versão que a
   próxima tela esquece.

   Onde o desenho **não pode** crescer (o trilho de 24 px do interruptor, a caixa de 16 px da
   marcação sem rótulo), quem cresce é a **área que responde**, com um `::after` invisível de
   44 px. Medir `getBoundingClientRect` nesses casos dá o tamanho do desenho e mente sobre o
   alvo — a medida honesta é `document.elementFromPoint` a 20 px do centro, ou ler a altura do
   `::after`.
2. **Ação principal na zona do polegar** — metade de baixo da tela. Por isso ação de linha é
   **folha ancorada no rodapé**, nunca menu colado no topo direito.
3. **Nada de rolagem horizontal na página.** `document.documentElement.scrollWidth` não pode
   passar de `window.innerWidth`. Conteúdo largo (tabela, gráfico, bloco de código) rola
   dentro do **próprio** contêiner com `overflow-x-auto`.
4. **`env(safe-area-inset-*)` no que é fixo.** Instalado como PWA (`display: standalone`,
   `NEW-003`) o navegador some: sem a inset, o cabeçalho fica sob o relógio e a última aba
   sob o indicador de início do iPhone. **Não aparece no DevTools — só no aparelho.**
5. **Superfície flutuante em portal.** Vale a §5.4.4 inteira, e no mobile ela morde mais: a
   `MobileTopBar` usa `glass-panel`, que aplica `backdrop-filter` e **cria contexto de
   empilhamento** — todo descendente fica preso no `z-sticky` do cabeçalho, por mais alto que
   seja o `z` dele.
6. **Toque fecha por `pointerdown`, não `mousedown`.** O `mousedown` sintético do telefone só
   chega depois do `touchend`, e o atraso é visível.

##### Qual componente para qual caso

Todos em `frontend/src/components/mobile/`. **Componente que faltar nasce aqui, nunca dentro
de uma tela** (Princípio 11).

| Caso | Componente | Observação |
| ---- | ---------- | ---------- |
| Moldura da tela | `MobilePageLayout` | Reserva o espaço das duas barras + `safe-area`. Aceita `fab` |
| Cabeçalho | `MobileTopBar` | Montado pelo `Layout`; a tela não o instancia |
| Navegação primária | `MobileBottomBar` | **4 destinos + "Mais"**, rotulados por inteiro, `aria-current` na ativa |
| **O menu inteiro** | `MobileNavSheet` | Aberto pela aba "Mais". É o ÚNICO caminho para os ~35 destinos que não cabem na barra |
| **Linha de lista** | `MobileCard` | Substitui a linha de tabela. `statusTone` é token, não paleta |
| Ações de uma linha | `MobileRowActions` | Folha no rodapé, ações **declaradas** pela tela |
| Ações em lote (seleção) | `MobileActionBar` | Barra contextual acima da navegação; some quando a seleção acaba |
| Indicador / KPI | `MobileKPI` | `format` = `currency \| percent \| plain`; tem `loading` |
| Gráfico | `MobileChartCard` | Série tipada, eixo compacto, vazio explícito |
| Paginação | `MobilePagination` | Anterior/Próxima + contador. Não use régua de números |
| **Carregando** | `MobileListSkeleton` | Esqueleto com a forma do `MobileCard`, não spinner |
| **Vazio** | `MobileEmptyState` | `filtered` distingue "não há" de "seu filtro não achou" |
| **Erro** | `MobileErrorState` | `role="alert"` + detalhe técnico + "tentar de novo" |
| Perfil / conta | `MobileContextSheet` | Aberto pelo avatar da `MobileTopBar` |
| ~~`MobileMenuActions`~~ | **descontinuado** | Lista de ações fixa (ver/editar/excluir) e painel preso ao ancestral. Use `MobileRowActions` |

##### O que **não** fazer

- **Tabela com `overflow-x` fingindo de mobile.** Coluna fora da tela é coluna que o usuário
  nunca descobre — e neste produto a coluna escondida costuma ser o valor ou o vencimento.
  Lista no telefone é `MobileCard`.
- **Só `hidden md:block` / `md:hidden` e chamar de "versão mobile".** Esconder coluna não é
  desenhar tela; a decisão do Phase 0 é **view própria**.
- **Lista sem os três estados.** Carregando, vazio e erro são obrigatórios, e **erro não pode
  parecer vazio**: quem decide sobre carteira olhando "nada aqui" quando a verdade é "não
  consegui perguntar" decide errado.

  Desde 26/08/2026 a tela **não precisa lembrar disso**: o `AsyncSection`
  (`components/ui/AsyncSection.tsx`) renderiza `MobileListSkeleton` /`MobileEmptyState` /
  `MobileErrorState` sozinho abaixo de 768 px, e o `ErrorState` do desktop ganhou
  `role="alert"` e moldura destrutiva. A varredura em 390×844 tinha achado **zero
  `role="alert"` em 33 telas nos dois modos** — não por descuido de cada tela, mas porque
  todas herdavam o mesmo bloco. A decisão mora num lugar; um sinalizador opcional
  (`variant="list"`) repetiria o modo de falha que o DEC-100 nomeia.
- **Cor literal, `dark:` para consertar cor, `z-[999]`.** Vale a §5.4.2 inteira; a
  biblioteca mobile não tem exceção.
- **Ícone sem rótulo em barra de abas.** "Operações" e "Operações estruturadas" viram o mesmo
  desenho, e este produto tem os dois.
- **Cartão clicável em `<div>` com `onClick` e nada mais.** Sem `role`/`tabIndex` a linha é
  inalcançável por teclado. O `MobileCard` já faz isso sozinho quando recebe `onClick`.
- **Barra de abas como se fosse o menu inteiro.** Cinco abas não são quarenta destinos. Se o
  console tem mais itens do que cabem na barra, a última aba é **"Mais"** e abre a
  `MobileNavSheet` — senão a área existe, tem rota montada, e o polegar não chega nela. Foi
  o que a passada de 26/08/2026 achou renderizando: **35 destinos inalcançáveis no telefone**,
  com `tsc` e `vitest` verdes.
- **Rótulo de aba com `truncate`.** "Painel de Disponibilidade" virava "Painel de D…" e
  "Disponibilidades" virava "Disponibili…" — e os dois usam o **mesmo** `CalendarRange`. Duas
  abas com o mesmo desenho e o nome cortado antes de divergir são o "ícone sem rótulo" da
  regra acima, por outro caminho. O rótulo cabe inteiro (até três linhas, `hyphens-auto`), ou
  a barra está errada.

##### Como verificar antes de fechar a tarefa

1. Renderize em **390×844**, nos **dois modos**, e capture.
2. Confirme que `document.documentElement.scrollWidth <= window.innerWidth`.
3. **Abra** cada folha, menu e seletor da tela — fechado, tudo parece perfeito (§5.4.4).
4. Percorra os três estados da lista: com dado, sem dado e com erro.
5. `node node_modules/vitest/vitest.mjs run src/components/mobile` continua verde — o
   contrato da biblioteca está travado em teste.

**Há duas varreduras prontas, e elas medem o que o olho deixa passar** (escritas na passada
de 26/08/2026, `frontend/scripts/`):

- `node scripts/mobile-audit.mjs [rota,…]` — renderiza cada tela em 390×844 nos dois modos,
  logado, e mede rolagem horizontal (e **quem** a causa), `<table>` viva, alvo de toque abaixo
  de 44 px **por toque**, e o fim da lista contra a barra de abas. Captura tudo.
- `node scripts/mobile-surfaces.mjs [rota,…]` — **abre** a folha "Mais", o seletor de modo, a
  folha de ações de linha e o primeiro `select` de cada tela, e confere por
  `document.elementFromPoint` que o painel responde no próprio centro, além de listar os
  ancestrais que criam contexto de empilhamento (§5.4.4).

Contraste **nunca por pixel**: no headless com `--disable-gpu` o `backdrop-filter` compõe
errado e a captura mente. Leia `getComputedStyle`.


#### 5.4.9 Campo monetário — preenchimento da **direita para a esquerda**

**A regra, nas palavras do usuário:** *"campos monetários tem que ter preenchimento facilitado
sempre, ou seja conforme digita vai colocando as vírgulas e pontos — ele é preenchido da direita
para esquerda. Se o user digitar `1` é `0,01`, ou seja um centavo; se ele digita `100` seria
`1,00`, ou seja um real ou dólar, depende da moeda do app."*

O usuário nunca digita vírgula nem ponto. Ele digita **só os algarismos**, e a máscara monta o
número:

| Teclas | Mostra |
| --- | --- |
| `1` | `R$ 0,01` |
| `12` | `R$ 0,12` |
| `123` | `R$ 1,23` |
| `123456` | `R$ 1.234,56` |
| `1234567` | `R$ 12.345,67` |
| Backspace | volta uma casa: `R$ 12,34` → `R$ 1,23` |

**Use `MoneyInput`, sempre.** Ele está em `frontend/src/components/ui/MoneyInput.tsx` e é
reexportado de `components/ui/NumericInput` — os dois caminhos de import funcionam. Nunca escreva
máscara de moeda na tela: é um componente da biblioteca, e a regra vive em um lugar só.

##### O que mudou, e por que o comentário antigo não vale mais

O `MoneyInput` anterior formatava **só ao sair do campo**, e o comentário dele justificava assim:

> *"Formatar a cada tecla move o cursor sozinho — digitar `1234` com máscara ao vivo pula o cursor
> para o fim a cada dígito e o usuário não consegue corrigir o meio."*

**O raciocínio está certo para uma máscara da esquerda para a direita**, onde existe um "meio"
para corrigir. **Não se aplica a este desenho:** aqui o cursor mora no fim por construção, e a
correção é o próprio Backspace. Quem for "consertar" isso de volta vai encontrar o argumento
acima e precisa saber por que ele foi descartado. Há teste travando o comportamento em
`components/ui/__tests__/MoneyInput.test.tsx` (12 casos).

##### A moeda vem da configuração, não do componente

`frontend/src/lib/config/currency.ts` é a fonte única — `APP_CURRENCY`, com `BRL` e `USD`, como o
`Currency::DEFAULT = BRL` do legado (`config/initializers/type_casting.rb`). Antes disso,
`currency: 'BRL'` estava **cravado em sete lugares**; sete cópias não são sete decisões.

O `minorUnits` da moeda é o que dá sentido à tecla: com 2, digitar `1` é um centavo; numa moeda
sem subunidade, digitar `1` é uma unidade inteira. **Nunca cravar `'BRL'` numa tela nova.**

##### Contrato preservado

**Exibe formatado, envia número** (FE-066). O `onChange` entrega `number | null` em unidade
**maior** — `1234.56`, nunca `"R$ 1.234,56"` e nunca os centavos crus `123456`. Vazio devolve
`null`, que não é a mesma coisa que zero.

##### Percentual é diferente — e continua diferente

`PercentInput` **não** acumula da direita para a esquerda: percentual se digita com vírgula
(`2,5`), sobre o `NumericInput`, com o parse pt-BR e o aviso de separador ambíguo. Se o usuário
pedir o mesmo comportamento para percentual, é uma linha — mas é decisão dele, não suposição.


### 5.5 i18n

`frontend/src/lib/i18n.ts`: `i18next` + `initReactI18next`, `lng: 'pt-BR'`, `fallbackLng: 'pt-BR'`.
**Só o bundle pt-BR é carregado** (`locales/pt-br/translation.json`), embora exista
`locales/en/translation.json` e `i18next-browser-languagedetector` esteja instalado (não usado).
Há um `components/LanguageSwitcher.tsx`. Boa parte das telas ainda tem string pt-BR hardcoded.

> **Atualizado em 25/08/2026:** os dois bundles eram ~350 linhas de copy de venda da
> landing do GOAT/polemk (`hero`, `plans`, `checkout`, `creators`, legendas de Instagram),
> órfãs desde que o site público saiu de escopo. Foram substituídos por um stub Safegold
> (`app`, `common`, `seo`) que serve de padrão de nomeação de chave. **Nenhuma tela chama
> `useTranslation` hoje** — se você for internacionalizar uma tela nova, é aqui que a chave
> entra, e o texto do Safegold é pt-BR.

### 5.6 Acessibilidade

Não há regra de lint de a11y nem auditoria no repo. O que existe é herdado dos primitivos Radix
(`dialog`, `accordion`, `switch`, `tabs`, `avatar`, `slider`, `progress`) e `focus-visible:ring-2
focus-visible:ring-ring` nos botões. **Isto é uma lacuna** (§9).

### 5.7 Realtime (Action Cable) — **polling é proibido nesta migração**

Hook único: `frontend/src/hooks/useCable.ts`.

```ts
const consumer = useCable()   // createConsumer(VITE_WS_URL ?? `${ws|wss}://${host}/cable`)
useChannel('LeadChatChannel', { lead_id: selectedId }, {
  received: (evt) => {
    if (evt?.type === 'message_created') {
      queryClient.invalidateQueries({ queryKey: ['lead-messages', selectedId] })
      queryClient.invalidateQueries({ queryKey: ['leads'] })
    }
  },
})
```

Regras aprendidas em produção e escritas em comentário no próprio hook:
- A autenticação do WS é **cookie HttpOnly `cable_token`**, nunca a URL.
- O gatilho de reconexão é a **presença** do access token (`useAccessToken()`), não seu valor.
- **Não recrie a subscription no `disconnected()`** — o `ConnectionMonitor` do
  `@rails/actioncable` já reconecta e re-assina; fazer manualmente duplicava cada broadcast.
- `useChannel` não assina enquanto algum `param` estiver `undefined`/`null`/`''`.
- Padrão de consumo: o evento **não carrega o estado**; ele apenas dispara
  `invalidateQueries` no React Query. É esse casamento (Cable invalida, React Query refaz)
  que substitui polling.

Canais existentes: `DashboardChannel`, `LeadChatChannel`, `PublicChatChannel`,
`PublicEventsChannel`, `EventLoggerChannel`, `PaymentsChannel`, `PermissionsChannel`,
`WhatsappInstanceChannel`.

> **Dívida a não replicar**: ainda há `refetchInterval` em
> `frontend/src/app/pages/admin/HeatmapPage.tsx:145` (30 s) e em
> `frontend/src/app/pages/admin/CurationQueuePage.tsx:121`. Código migrado do `sfg` **não pode**
> introduzir polling novo — use Action Cable + invalidação.

### 5.8 Proxy de dev

`frontend/vite.config.ts` faz proxy de `/api`, `/chat`, `/public`, `/auth`, `/whats`, `/asaas`,
`/rails`, `/docs`, `/swagger_doc` e `/cable` (com `ws: true`) para `VITE_BACKEND_URL`
(default `http://localhost:3000`). Build usa `manualChunks` por vendor
(`react-vendor`, `router-vendor`, `ui-vendor`, `query-vendor`, `animation-vendor`,
`state-vendor`, `i18n-vendor`, `http-vendor`).

---

## 6. Qualidade e testes

### Backend — RSpec

- `backend/spec/` com `requests/` (espelhando a árvore Grape: `spec/requests/api/v1/showrooms_spec.rb`),
  `services/`, `models/`, `jobs/`, `channels/`, `controllers/`, `factories/`, `cassettes/`.
  **227 arquivos `_spec.rb`.**
- `backend/spec/rails_helper.rb`: `use_transactional_fixtures = true`, `FactoryBot::Syntax::Methods`
  incluído, `infer_spec_type_from_file_location!`, `shoulda-matchers` (rspec + rails),
  `WebMock.disable_net_connect!(allow_localhost: true)`, VCR com
  `cassette_library_dir = 'spec/cassettes'` e `ignore_localhost = true`.
- Padrão de request spec (`spec/requests/api/v1/showrooms_spec.rb`):

```ruby
RSpec.describe 'Api::V1::Showrooms', type: :request do
  let!(:og_user) { create(:user, :og) }
  let(:og_token) { Auth::TokenService.new(og_user).generate_tokens[:token] }
  let(:headers)  { { 'Authorization' => "Bearer #{og_token}" } }

  it 'creates a showroom' do
    post '/api/v1/showrooms', params: valid_params, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)['identifier']).to eq('post-1234')
  end
end
```

  Ou seja: token real gerado pelo `TokenService`, `headers` com Bearer, `as: :json`,
  asserção por `have_http_status(:symbol)` + `JSON.parse(response.body)`. Descrições dos
  `describe/it` em **inglês** nos specs; comentários explicativos em pt-BR.
- Factories em `backend/spec/factories/<recurso>.rb` com `sequence` para campos únicos:
  `sequence(:identifier) { |n| "showroom-#{n}-#{SecureRandom.hex(4)}" }`. Traits para papéis (`:og`).
- Cobertura: `simplecov` no grupo `:test`.

### Frontend — Vitest

- `frontend/vitest.config.ts`: `globals: true`, `environment: 'jsdom'`,
  `setupFiles: ['./src/test/setup.ts']`, alias `@ → ./src`.
- `frontend/src/test/setup.ts`: importa `@testing-library/jest-dom` e mocka
  `navigator.clipboard` e `window.location`.
- Testes ficam em `__tests__/` ao lado do código (`src/components/__tests__/`,
  `src/app/pages/__tests__/`, `src/features/auth/__tests__/`, `src/lib/api/__tests__/`).

### Lint / format

- Ruby: `rubocop` + `rubocop-rails` + `rubocop-rspec`. `backend/.rubocop.yml` herda de
  `.rubocop_todo.yml` — que tem **3051 linhas** de exclusões. Na prática o Rubocop está
  quase todo silenciado; trate-o como orientação, não como portão.
- TS: `frontend/.eslintrc.cjs`. **A maioria das regras está `off`** (`no-explicit-any`,
  `no-unused-vars`, `exhaustive-deps`, `rules-of-hooks`, `prefer-const`…). O script
  `pnpm lint` roda com `--max-warnings 0`, mas com esse config quase nada é reportado.
- Segurança: `brakeman` e `bundler-audit` no Gemfile (grupo `:development`).
- **Não há Prettier** configurado.

### CI

`.github/workflows/ci.yml` existe e está **vazio (0 bytes)**. Ou seja: **a CI não exige nada
hoje**. O `README.md` descreve uma CI (testes, lint, build) que não está implementada.
Para a migração, o portão de qualidade tem de ser local/manual — ou reconstruído (§9).

---

## 7. Comandos verificados

Todos abaixo foram lidos em manifesto, script ou arquivo de configuração deste repositório.

**Setup**

| Comando | Onde está declarado |
| :-- | :-- |
| `./setup.sh` | `setup.sh` (raiz, executável) — orquestra o setup completo |
| `./create_dev_db.sh` | `create_dev_db.sh` (raiz, executável); aceita `USE_SUDO`, `CONFIG_PATH` |
| `./install.sh` | `install.sh` (raiz, executável) |
| `cp backend/.env.example backend/.env` / `cp frontend/.env.example frontend/.env` / `cp .env.example .env` | `README.md`, `BUILD_SYSTEM.md` |
| `cp .env.secrets.example .env.secrets` | `BUILD_SYSTEM.md` |
| `bin/switch_env local` \| `bin/switch_env ngrok <url>` \| `bin/switch_env prod` | `bin/switch_env`, `README.md` |
| `cd backend && bundle install` | `backend/Gemfile`, `bin/dev` |
| `cd frontend && pnpm install` | `frontend/package.json` (`packageManager: pnpm@10.32.1`) — **`bin/dev` usa `npm install --legacy-peer-deps`; divergência** |

**Dev**

| Comando | Onde |
| :-- | :-- |
| `bin/dev` | `bin/dev` — sobe Rails (:3000) + Sidekiq + Vite (:5173) juntos; env `RAILS_PORT`, `VITE_PORT`, `SKIP_INSTALL=1` |
| `cd backend && bundle exec rails s -p 3000` | `Procfile.dev` |
| `cd backend && bundle exec sidekiq -C config/sidekiq.yml` | `Procfile.dev`, `bin/dev` |
| `cd frontend && pnpm dev --host --port 5173` | `Procfile.dev` |
| `docker-compose up` | `docker-compose.yml`, `README.md` |

**Migrações**

| Comando | Onde |
| :-- | :-- |
| `cd backend && bin/rails generate migration <NomeEmCamelCase>` | `backend/bin/rails` existe; padrão Rails 8 |
| `cd backend && rails db:create db:migrate` | `README.md` |
| `cd backend && rails db:seed` | `README.md` (após editar `backend/db/seeds.rb`) |
| `cd backend && bin/rails db:schema:load` | citado no cabeçalho de `backend/db/schema.rb` |

**Testes / qualidade**

| Comando | Onde |
| :-- | :-- |
| `cd backend && bundle exec rspec` | `README.md` |
| `cd frontend && pnpm test` (`vitest`) | `frontend/package.json` |
| `cd frontend && pnpm test:ui` / `pnpm test:coverage` | `frontend/package.json` |
| `cd frontend && pnpm lint` (`eslint . --ext ts,tsx --max-warnings 0`) | `frontend/package.json` |
| `cd frontend && pnpm type-check` (`tsc --noEmit`) | `frontend/package.json` |
| `cd backend && bundle exec rubocop` | gem `rubocop` + `backend/.rubocop.yml` |
| `cd backend && bundle exec brakeman` / `bundle exec bundler-audit` | gems no grupo `:development` |
| `bundle exec rails secret` | `README.md` (gerar `DEVISE_JWT_SECRET_KEY`) |

**Build / produção**

| Comando | Onde |
| :-- | :-- |
| `cd frontend && pnpm build` (`tsc && vite build`) | `frontend/package.json` |
| `cd frontend && pnpm preview` | `frontend/package.json` |
| `bin/prod` | `bin/prod` (executado pelo systemd) |
| `sudo systemctl {enable,start,restart,status} ai9` · `sudo journalctl -u ai9 -f` | `DAEMON.md` |

**Grafo de conhecimento** (instalado, fora do repo)

| Comando | Situação |
| :-- | :-- |
| `graphify explain "<nó>"` / `graphify query "<pergunta>"` / `graphify hook status` | binário existe no PATH (`.../Python312/Scripts/graphify`), v0.9.11 registrada em `.migration-ai9/project-options.md`; hook post-commit já instalado. **Não executei** as subcomandos nesta sessão — comportamento não verificado. |
| `tools/graphify/rebuild.sh` | arquivo existe em `tools/graphify/` |

**Não verificados / não existem**

- `docker-compose -f docker-compose.prod.yml up` — citado no `README.md`, mas **`docker-compose.prod.yml` não existe** no repositório.
- Qualquer job de CI — `.github/workflows/ci.yml` está **vazio**.
- `npm test` no frontend funciona, mas o gerenciador oficial é pnpm.

---

## 8. Nomenclatura e estilo

**Regra de língua (explícita para esta migração):**

- **INGLÊS**: identificadores de código (classes, métodos, variáveis, funções, componentes),
  nomes de arquivo e módulo, URLs e rotas de API, nomes de rota do frontend, colunas e enums do
  banco, query keys do React Query, chaves de `Permission`.
- **pt-BR**: comentários que explicam módulo, feature ou lógica; mensagens de erro destinadas ao
  usuário; textos de UI (via i18n); `desc`/`detail`/`summary` do Swagger; cabeçalhos explicativos
  de migração; mensagens de commit (mistas no histórico atual).

**Onde o repositório JÁ viola essa regra** (saiba disto antes de "seguir o exemplo ao lado"):

- Colunas e conceitos em pt-BR em migrações recentes: `first_ad_conjunto_id`,
  `first_ad_campanha_id`, `first_ad_plataforma`, `nome_confirmado_em`, `nome_origem`,
  `nome_confirmado_via`; tabela `canais`.
- Concerns e métodos em pt-BR: `backend/app/models/concerns/identificavel.rb`
  (`caminhos_de_contato`, `nome_proprio?`, `confirmar_nome!`, `contactaveis`),
  `filtravel_por_origem.rb`, `Lead#mudou_de_origem?`.
- Classes de migração em pt-BR: `GoatAlcancaOModeloDePessoa`, `SessaoDeChatNasceSemLead`,
  `RemoveTabelasGhostDeMaio`.
- Rotas de frontend em pt-BR: `/vendas`, `/guia-rastreamento`. Endpoints Grape em pt-BR: `/api/v1/origens`.
- Token de z-index `parede` (pt-BR) no `tailwind.config.js`.

Para o `sfg9`: **novo código em inglês**, sem replicar essas exceções. Não renomeie o que já existe.

**Outras convenções de estilo observadas:**

- Ruby: `# frozen_string_literal: true` em todo arquivo; 2 espaços; `class << self` em services;
  guard clauses (`return … unless`); `rescue StandardError => e` no fim do método, não em bloco.
- Comentários pt-BR são **longos e narrativos**, explicando o *incidente* que motivou o código
  ("Até 01/08/2026 este bloco honrava `X-Skip-Auth: 1` e qualquer pessoa lia a base de leads
  inteira sem login"). Esse é o padrão de comentário da casa — comentário explica **por que**, e
  cita o bug que ele previne. Reproduza isso.
- TypeScript: componentes `PascalCase` exportados nomeados (`export function ShowroomsPage`),
  às vezes `export default` (páginas passadas em `lazy`). Hooks `useAlgo` em `src/hooks/`.
  Stores `<algo>Store.ts` exportando `use<Algo>Store`. Objetos de API `<recurso>Api`.
  Import alias `@/` sempre (configurado em `vite.config.ts`, `vitest.config.ts`, `tsconfig.json`).
- Migrações antigas: nome gerado pelo Rails. Novas: nome descritivo escrito à mão + comentário
  de cabeçalho longo.

---

## 9. Lacunas do ai9 para um app financeiro / de risco de crédito (`sfg`)

Nenhum dos itens abaixo tem equivalente no ai9 hoje — cada um vira decisão explícita no mapa
de migração.

**Domínio (não existe nada equivalente)**
1. **Recebíveis, renegociações, operações de risco, operações estruturadas, garantias, sacados
   (carriers), carteiras (wallets), contratos, cobranças (charges), adesões (memberships),
   indicadores** — não há modelo nem tabela para nada disso em `backend/app/models/` nem em
   `backend/db/schema.rb`. `Operation` no ai9 é agrupador de leads/flows de marketing, **não** é
   operação financeira: o nome colide e não deve ser reutilizado.
2. **Projetos**: existe `20260429000001…create_projects` no histórico de migrações, mas o domínio
   atual é de conteúdo/pedidos (`Order`, `Delivery`, `DeliveryItem`, `OrderMilestone`), não de
   projetos de crédito.

**Capacidades transversais ausentes**
3. **Geração de PDF**: **zero** gems (`prawn`, `wicked_pdf`, `grover`, `pdfkit`, `hexapdf`) e
   zero libs no frontend (`jspdf`). O `sfg` gera PDF; é capacidade nova a introduzir.
4. **Auditoria / trilha de alterações**: `paper_trail` está no `Gemfile` mas **não é usado em
   nenhum model**. Só há `PermissionAuditLog`. Um app de crédito precisa de trilha genérica —
   decidir entre ativar `paper_trail` ou criar padrão próprio.
5. **Soft delete**: não existe. O único padrão é status `discarded` + `discarded_at` +
   job de purga (`PostDraft`/`PurgeDiscardedDraftsJob`). Se o `sfg` depende de exclusão lógica,
   é padrão novo.
6. **Máquina de estados**: `aasm` está no Gemfile e **não é usado** — estados hoje são
   `enum` string + transições ad hoc (`Order#state`, `Delivery#state`). Renegociação e operação
   estruturada pedem estado formal; decidir entre ativar `aasm` ou manter enum + services.
7. **Multi-tenancy / isolamento por carteira ou empresa**: inexistente (§4). Se o `sfg` isola
   dados por cliente/carteira, isso é arquitetura nova — não há `tenant_id` para copiar.
8. **Autorização granular por recurso**: existe `Permission`/`UserPermission` por `key`, mas a
   checagem em runtime é só `require_og!` / `restrict_visitor_access!` / `user_type`. Não há
   Pundit/CanCan nem policy por registro (row-level). Perfis do `sfg` (analista, gestor,
   originador…) exigem camada de policy nova.
9. **Console de administração**: não há ActiveAdmin/Avo — o "admin" são páginas React em
   `frontend/src/app/pages/admin/` protegidas por `OgRoute`. Todo CRUD administrativo migrado
   precisa ser escrito à mão nesse padrão.
10. **Help / FAQ / central de ajuda**: não existe modelo nem tela (só blocos de FAQ estáticos em
    landing pages). Capacidade nova.
11. **Jobs agendados**: a infra existe (`sidekiq-cron` em `initializers/sidekiq.rb`), mas o
    agendamento é **hardcoded em Ruby**, não em YAML nem em banco. Cada job agendado do `sfg`
    precisa ser adicionado ali à mão — e sua fila precisa entrar em `backend/config/sidekiq.yml`.
12. **Precisão monetária**: não há padrão único (`decimal(14,2)` em orders vs `decimal(10,3)` em
    plans) e não há gem de dinheiro (`money-rails`). Fixar `decimal(14,2)` + arredondamento
    explícito antes de migrar valores.
13. **Relatórios / exportação (CSV, XLSX)**: nenhum gerador no backend; o CORS já expõe
    `Content-Disposition` e existe `api/v1/downloads.rb` + `getRaw` para blob, mas não há
    geração de planilha.
14. **Formulários complexos com validação declarativa**: sem `react-hook-form`/`zod`. Formulários
    de operação/renegociação do `sfg` (muitos campos, regras cruzadas) vão ficar pesados no padrão
    atual de `useState` manual. Considerar introduzir a lib **antes** de portar as telas grandes.
15. **Acessibilidade**: sem regras de lint nem auditoria (§5.6). Se o `sfg` tem exigência de
    acessibilidade, é trabalho novo.
16. **CI**: `.github/workflows/ci.yml` vazio. Não existe portão automático de testes/lint/build —
    reconstruir antes de a migração ganhar volume.
17. **Observabilidade**: só `Rails.logger`. Não há Sentry/APM; o `rescue_from :all` inclusive
    devolve backtrace ao cliente em vez de reportá-lo.
18. **i18n de verdade**: só pt-BR é carregado e há muita string hardcoded (§5.5). Não é bloqueio
    para o `sfg` (pt-BR), mas o `LanguageSwitcher` existente é enganoso.

---

## 10. Checklist para escrever uma feature nova no ai9

1. Migração em `backend/db/migrate/` (classe descritiva, comentário-cabeçalho pt-BR explicando o
   porquê, `id: :uuid` se domínio novo, índices explícitos com `where:` parcial quando fizer
   sentido, `comment:` nas colunas).
2. Model em `backend/app/models/` com `validates`, `scope`, `dependent:` explícito,
   `by_any_id`/`smart_id` se for exposto por URL.
3. Service em `backend/app/services/` (`class << self` + `include ApiResponseHandler`),
   devolvendo `success_response`/`*_response`.
4. Entity em `backend/app/controllers/api/entities/` com `documentation:` em todo `expose`.
5. Endpoint Grape em `backend/app/controllers/api/v1/`, com `desc`/`params`/`http_codes` e
   `process_service_response`; montar em `api/v1/base.rb` dentro de um `namespace`.
6. Job em `backend/app/jobs/` se houver trabalho assíncrono — **e cadastrar a fila em
   `backend/config/sidekiq.yml`**; cron em `backend/config/initializers/sidekiq.rb`.
7. Channel em `backend/app/channels/` se houver realtime (`reject` na autorização, payload com `type:`).
8. Spec de request em `backend/spec/requests/api/v1/` + factory em `backend/spec/factories/`.
9. Tipo em `frontend/src/lib/api/types.ts` e objeto `<recurso>Api` em
   `frontend/src/lib/api/endpoints.ts`.
10. Página em `frontend/src/app/pages/` (ou `features/<dominio>/`), com `useQuery`/`useMutation`,
    `queryKey` array e `invalidateQueries` no `onSuccess`.
11. Rota em `frontend/src/app/App.tsx` com `lazy()` + guarda (`ProtectedRoute`/`OgRoute`/
    `ClientRoute`/`VisitorRoute`).
12. Se houver evento em tempo real: `useChannel(...)` invalidando as queries. **Nunca polling.**
13. Estilos só com os tokens semânticos do Tailwind (`bg-card`, `text-muted-foreground`,
    `border-border`, `z-modal`…) — nunca cor literal, nunca `z-[999]`.
14. Teste Vitest em `__tests__/` ao lado.

## Regra de fronteira — antes de remover ou renomear qualquer coisa de contrato

Nasceu de um defeito real desta migracao (25/08/2026). A **DEC-49** mandou remover 4 rotas de
auto-cadastro; o agente de backend removeu corretamente. Mas o **frontend chamava `pre_register`
dentro do fluxo de login** — a rota de auto-cadastro estava sendo usada como rota de login. O
backend saiu ajustado, o front nao, e **o login inteiro caiu com 404**. `rspec` estava 628/0 e
`tsc` limpo: nenhum portao pegou, porque cada lado estava certo sozinho.

**A regra, obrigatoria para qualquer agente:**

Antes de **remover, renomear ou mudar a forma** de rota, campo de entity, chave de resposta,
coluna exposta ou nome de header:

1. **Procure o consumidor do outro lado.** Removeu rota no backend? `grep` no `frontend/src`
   pelo caminho da rota **e** pelo nome do metodo do service. Mudou nome de campo numa entity?
   `grep` pelo nome do campo no front. Mudou algo no front que o back preenche? Confira o entity.
2. **Consumidor achado nao e bloqueio — e trabalho seu.** Ajuste os dois lados **no mesmo passo**.
   Deixar para "a fatia de frontend depois" e como o login caiu.
3. **Renomeou? O nome novo nao pode mentir.** `preRegister` apontando para `magic_login/request_code`
   compila e funciona — e a proxima pessoa "conserta" de volta. Renomeie o metodo junto.
4. **Prove executando, pela tela.** `tsc` e `rspec` provam que carrega. O login quebrado passou
   nos dois. Abra a tela afetada com o navegador headless.

**Vale nas duas direcoes**, e vale tambem entre fatias: se a sua fatia muda algo que outra
consome, o `grep` e seu.
