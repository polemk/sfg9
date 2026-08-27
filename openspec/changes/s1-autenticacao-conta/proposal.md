# Proposal: S1 — Autenticação e conta

> Fatia **S1** de `.migration-ai9/migration-map.md`. Bloco de origem: `auth`.
> **Depende de S0** (papéis, hierarquia, participação, primitivos).
> Absorve as fatias internas **S2, S5, S7 e S8** do `.migration-ai9/map/auth-admin.md` —
> identidade, contas de usuário, impersonation e e-mail transacional — porque as quatro
> tratam do mesmo objeto: **a conta de quem entra no sistema**.

## Why

O legado autentica com **Devise + senha**. A base ai9 **não tem senha em lugar nenhum** —
verificado: nenhuma coluna `encrypted_password` em `schema.rb:640-675`, `devise
:omniauthable` e nada mais em `user.rb:9`, `bcrypt` não é requerido por nenhum arquivo de
app. Construir senha no ai9 seria criar um **segundo sistema de identidade dentro da base**:
o desperdício mais caro possível e o oposto do reuse-first.

Por isso esta fatia é, ao mesmo tempo, a de **maior reuso** e a de **maior mudança
observável** do Safegold: quem entra hoje digitando senha vai digitar um código de 6 dígitos
recebido por e-mail ou WhatsApp (DEC-14), ou entrar por magic link, ou por OAuth
(**IMP-A1**). Isso precisa estar combinado com o usuário **antes** da demo.

E há uma coisa que não dá para adiar: **o D-39 volta sozinho se ninguém agir**. No legado,
`PUBLIC_CREATE_USER = 1` + `minimal_type_to_sign_up_through_web = "Admin"` faziam qualquer
pessoa da internet virar Admin. A decisão foi desligar o cadastro público (DEC-18.7) — mas
**não basta não portar a rota do legado**: a base ai9 já tem uma porta equivalente aberta na
allowlist pública (`backend/app/controllers/api/root.rb:35-46`: `pre_register`,
`complete_registration`, `visitor_signup`, `visitor_signup_with_link`). Se essas rotas
ficarem, o defeito renasce por uma porta que **não veio do legado** e ninguém percebe.

## What Changes

### Grupo A — Identidade: entrar, sair, recuperar acesso

Um fluxo de login só (o legado tinha dois paralelos — D-42), sem senha, com abas
**E-mail / WhatsApp**, magic link e OAuth. Somem: senha, "esqueci a senha", "trocar senha",
e-mail de senha alterada e cadastro público.

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-001 | `reuse` | rota `/login` |
| BE-002 | `adapt` | `POST /auth/v1/magic_login/request_code` |
| BE-003 | `adapt` | `POST /auth/v1/code_validation` + `GET /auth/v1/me` |
| BE-004 | `drop` | — |
| BE-005 | `reuse` | `DELETE /auth/v1/sessions/logout` |
| BE-006 | `adapt` | mesmo endpoint do BE-005 |
| BE-007 | `adapt` | `/login?next=<path>` |
| BE-008 | `drop` | — |
| BE-011 | `drop` | — |
| BE-019 | `drop` | — |
| BE-020 | `adapt` | `POST /auth/v1/magic_login/request_code` |
| BE-021 | `adapt` | `/magic-login?token=…` |
| BE-022 | `adapt` | `GET /auth/v1/magic_link/verify` |
| BE-023 | `reuse` | `GET /auth/v1/oauth/facebook_url` + `POST /auth/v1/oauth/callback` |
| BE-024 | `reuse` | `POST /auth/v1/oauth/callback` |
| BE-047 | `reuse` | `Authorization: Bearer <client_token>` |
| BE-509 | `drop` | — |
| BE-510 | `drop` | — |
| BE-512 | `drop` | — |
| BE-513 | `drop` | — |
| BE-514 | `drop` | — |
| BE-515 | `adapt` | gate central + helpers |
| BE-516 | `adapt` | login único |
| BE-517 | `adapt` | logout único |
| BE-521 | `drop` | — |
| BE-522 | `adapt` | `AuthMailer` |
| BE-523 | `drop` | — |
| BE-524 | `drop` | — |
| BE-747 | `drop` | — |
| DB-009 | `reuse` | `client_applications` |
| DB-010 | `reuse` | `users.provider` + `provider_uid` |
| DB-012 | `reuse` | `users` + `login_attempts` |
| DB-013 | `drop` | — |
| DB-504 | `reuse` | `client_applications` |
| DB-506 | `reuse` | `users.provider`/`provider_uid` |
| DB-507 | `drop` | `parity-ledger` |
| FE-001 | `adapt` | `/login` |
| FE-002 | `adapt` | painel "Acessar" |
| FE-003 | `drop` | — |
| FE-004 | `adapt` | mesmo fluxo do FE-002 |
| FE-005 | `reuse` | rodapé social do login |
| FE-006 | `adapt` | aviso no `/login?next=` |
| FE-007 | `adapt` | `/magic-login` |
| FE-008 | `drop` | — |
| FE-009 | `drop` | — |
| FE-010 | `adapt` | estado de erro do `/magic-login` |
| FE-039 | `reuse` | "Sair" |
| FE-045 | `adapt` | barra das telas de auth |
| FE-046 | `drop` | — |
| FE-048 | `drop` | — |
| FE-049 | `drop` | — |
| FE-500 | `drop` | — |
| FE-501 | `adapt` | layout das telas de auth |
| FE-502 | `drop` | — |
| FE-503 | `drop` | — |
| FE-504 | `drop` | — |
| FE-505 | `drop` | — |
| FE-506 | `drop` | — |
| FE-507 | `adapt` | `/magic-login` |
| FE-508 | `drop` | — |
| FE-509 | `drop` | — |
| FE-510 | `drop` | — |
| FE-514 | `drop` | — |
| FE-518 | `reuse` | metadados das telas de auth |
| FE-519 | `drop` | — |
| FE-520 | `drop` | — |
| FE-521 | `drop` | — |
| FE-522 | `drop` | — |
| ENG-auth_omni19 | `drop` | `parity-ledger` (`dropped`) |
| OPS-002 | `reuse` | `AuthMailer#magic_login_code` |
| OPS-003 | `drop` | — |
| OPS-004 | `drop` | — |
| OPS-007 | `reuse` | ENV `FACEBOOK_*` / `GOOGLE_*` |
| OPS-008 | `reuse` | ENV + `client_applications` |

### Grupo B — Contas de usuário, perfil e bloqueio

A tela `/users` do ai9 vira a tela "Contas" do Safegold, com a matriz do DEC-18 aplicada no
servidor e paginação de verdade. O perfil estendido (`livetat_auth_user_infos`, 41 campos e
tipos errados) **não vira tabela**: entra em `users`, com os tipos corretos. Bloqueio de
conta ganha **um** campo (`blocked_at`) no lugar dos dois concorrentes do legado.
Inclui as telas de permissão, que comandam o servidor construído em S0.

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-009 | `adapt` | `GET /api/v1/users` |
| BE-010 | `adapt` | `GET /api/v1/users/:id` |
| BE-012 | `adapt + build` | `POST /api/v1/users` + `POST /api/v1/users/:id/invite` |
| BE-013 | `adapt` | `PUT /api/v1/users/:id` |
| BE-014 | `adapt` | `DELETE /api/v1/users/:id` (auto-remoção) |
| BE-015 | `adapt` | `GET /auth/v1/me` |
| BE-016 | `adapt + build` | `PATCH /auth/v1/me` |
| BE-017 | `adapt` | `POST /api/v1/uploads/avatar` → `has_one_attached :avatar` |
| BE-025 | `adapt` | `GET /api/v1/users?q=&type=&page=` |
| BE-026 | `reuse` | `/users` |
| BE-027 | `adapt` | `/users/:id` |
| BE-028 | `adapt` | `/users/new` (drawer) |
| BE-029 | `adapt` | `/users/:id/edit` (drawer) |
| BE-030 | `adapt` | `DELETE /api/v1/users/:id` |
| BE-034 | `build` | `GET /api/v1/users/:id/memberships` |
| BE-035 | `adapt` | \d{14}`); `backend/app/controllers/api/v1/users.rb` |
| BE-036 | `build` | coluna `users.blocked_at` + `POST /api/v1/users/:id/block` |
| BE-037 | `build` | `DELETE /api/v1/users/:id/block` |
| BE-038 | `adapt` | `Api::Root#before` |
| BE-039 | `reuse` | `ProtectedRoute` + 401 do gate central |
| BE-048 | `build` | coluna `users.identifier` + `before_create` |
| BE-049 | `adapt + build` | callbacks do `User` + `UsersService.create` |
| BE-501 | `reuse` | `User` |
| BE-502 | `reuse` | JWT |
| BE-503 | `adapt` | `has_one_attached :avatar` + variants |
| BE-507 | `adapt` | colunas em `users` |
| BE-508 | `reuse` | `ClientApplication` |
| BE-518 | `adapt` | `GET /api/v1/users` |
| BE-519 | `adapt` | CRUD de usuário |
| DB-001 | `adapt` | tabela `users` |
| DB-002 | `adapt` | colunas do `users` |
| DB-003 | `adapt` | `has_one_attached :avatar` |
| DB-004 | `adapt` | colunas em `users` |
| DB-014 | `adapt` | validações do `User` |
| DB-015 | `adapt` | coluna `users.profile_completeness` |
| DB-016 | `adapt` | validações de perfil |
| DB-017 | `drop` | `parity-ledger` + runbook de ETL |
| DB-500 | `adapt` | `users` |
| DB-505 | `adapt` | colunas em `users` |
| FE-011 | `adapt` | `/users` |
| FE-012 | `reuse` | `/users` |
| FE-013 | `adapt` | og\ |
| FE-014 | `build` | `components/ui/Pagination.tsx` |
| FE-015 | `adapt` | card de usuário |
| FE-016 | `adapt` | menu de ações do card |
| FE-017 | `reuse` | card de usuário |
| FE-018 | `reuse` | drawer de criar/editar |
| FE-019 | `adapt` | drawer de usuário |
| FE-020 | `drop` | — |
| FE-021 | `adapt` | drawer de usuário |
| FE-022 | `adapt` | `/users/:id` |
| FE-023 | `adapt` | card "Dados do usuário" |
| FE-024 | `adapt` | painel de permissões em `/users/:id` |
| FE-025 | `build` | aba Projetos de `/users/:id` |
| FE-026 | `build` | `/permissions` |
| FE-027 | `adapt` | toggle em `/permissions` |
| FE-028 | `reuse` | `/profile` |
| FE-029 | `adapt` | `/profile` |
| FE-030 | `adapt` | `/profile` |
| FE-031 | `reuse` | `/profile` |
| FE-032 | `drop` | — |
| FE-033 | `adapt` | `/profile` |
| FE-034 | `adapt` | `/profile` |
| FE-035 | `adapt` | `/profile` |
| FE-042 | `reuse` | toasts de `/users` |
| FE-043 | `reuse` | toasts de `/permissions` |
| FE-044 | `adapt` | interceptor 401 |
| FE-047 | `drop` | — |
| FE-511 | `drop` | — |
| FE-512 | `drop` | — |
| FE-513 | `adapt` | painel de permissões em `/users/:id` |
| FE-515 | `reuse` | card de usuário |
| FE-516 | `adapt` | `Api::Entities::User` |
| FE-517 | `drop` | — |
| OPS-001 | `adapt` | `InviteMailer#invitation` |
| OPS-505 | `adapt` | Active Storage |
| OPS-506 | `adapt` | validação de upload |

### Grupo C — Impersonation auditada

A base **já tem** impersonation funcionando, com `can_impersonate?` e claim
`impersonated_by` que sobrevive ao refresh. Faltam as cinco exigências do DEC-18.3: trava de
hierarquia, motivo obrigatório, trilha persistida, sessão que expira e **sem encadeamento**.
É `adapt`, não `build`.

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-031 | `adapt` | `POST /auth/v1/impersonate/start` |
| BE-032 | `reuse` | `POST /auth/v1/impersonate/stop` |
| BE-033 | `reuse + adapt` | `GET /api/v1/users?q=&per_page=5` + revive `ImpersonateSearch` na topbar |
| FE-036 | `adapt` | menu do usuário |
| FE-037 | `reuse` | chip de "Vendo como" |
| FE-038 | `reuse` | topbar |
| OPS-395 | `adapt` | JWT com claim |

### Grupo D — E-mail transacional do produto

O `mailer19` **não vira engine**: vira `ApplicationMailer` + Sidekiq (que já está em pé). Os
3 e-mails vivos do Safegold são reescritos como templates ERB — nunca concatenação de string
dentro do Ruby — e **nenhum deles carrega senha** (D-38).

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-533 | `adapt` | config SMTP |
| BE-534 | `drop` | — |
| BE-535 | `adapt` | `ApplicationMailer` + layout |
| BE-536 | `adapt` | 3 mailers do produto |
| BE-537 | `drop` | `parity-ledger` (`dropped`) |
| DB-514 | `build?` | tabela `mail_deliveries` **ou** nada |
| DB-515 | `drop` | — |
| FE-529 | `drop` | — |
| FE-530 | `build` | template de confirmação de mensagem |
| FE-531 | `drop` | — |
| FE-532 | `drop` | — |
| FE-533 | `build` | `generic_message` |
| FE-534 | `build` | `generic_message_with_link` |
| FE-535 | `adapt` | `InviteMailer#invitation` |
| FE-536 | `adapt` | `AuthMailer#magic_login_code` |
| FE-537 | `drop` | — |
| OPS-500 | `reuse` | ENV `SMTP_*` |
| OPS-501 | `build?` | assinatura no provedor de SMTP |
| OPS-502 | `reuse` | Sidekiq |
| OPS-503 | `drop` | — |
| OPS-504 | `adapt` | recursos de e-mail |

### Contagem

| Grupo | IDs |
| ----- | --- |
| A — identidade | 74 |
| B — contas, perfil, permissões | 77 |
| C — impersonation | 7 |
| D — e-mail transacional | 21 |
| **Total** | **179** (todos do bloco `auth-admin`) |

### Fronteiras

- **Consome de S0:** papéis e hierarquia (C3), `authorize!`, `require_not_readonly!`,
  `AuditEvent`, `Pagination`, `DataTable`, `AsyncSection`, `SearchInput`, `Avatar`.
- **Não está aqui:** a casca do console, o menu por papel, o 404 e o seletor de projeto
  (**S2**); a aba "Membros" do projeto (FE-040/FE-041, **S4**).
- **Pendências de decisão que atravessam a fatia:** Q-B2 (login por Facebook),
  Q-B3 (`is_active` e `legacy_password` no ETL), Q-B4 (telefone verificado), Q-B5 (onde
  ficam os arquivos em produção), Q-B7 (quem entra por `username` hoje), Q-B18 (guardar o
  corpo dos e-mails), Q-B19 (quem assina DKIM). Todas com default declarado no mapa.

## Impact

- **Afetado (backend):** `api/auth/v1/{magic_login,code_validation,magic_link,oauth,
  sessions,me,impersonate,registration}.rb`, `api/v1/{users,uploads}.rb`,
  `api/entities/user.rb`, `app/services/auth/**`, `app/mailers/**`,
  `app/controllers/api/root.rb` (**allowlist**), migrations de `users`.
- **Afetado (frontend):** `app/pages/{LoginPage,UsersPage,ProfilePage}.tsx`,
  `features/auth/**`, `components/{ImpersonateSearch,ImpersonateSelector}.tsx`,
  `lib/api/client.ts`.
- **Mudanças observáveis (vão para `improvements-log.md`, não são regressão):** IMP-A1
  (login sem senha), IMP-A5 (cadastro público desligado **nos dois lados**), IMP-A6
  (convite com magic link em vez de senha por e-mail), IMP-A16 (bloqueio revoga a sessão
  na hora), IMP-A17 (conta bloqueada recebe explicação em vez de logout mudo), IMP-A23,
  IMP-A27 (fim do dado falso servido como real na tela de usuários).
- **Risco principal:** a superfície de segurança inteira do produto está nesta fatia. Dois
  itens não podem ser esquecidos: **retirar as 4 rotas de cadastro da allowlist do ai9**
  (senão o D-39 volta) e **corrigir a ordem das checagens da impersonation** (hoje
  `impersonate_service.rb:13-18` responde 404/422 **antes** do 403, vazando existência de
  usuário).


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-540 | adapt | `livetat_auth_users` → migration `add_safegold_columns_to_users` + `User`: `legacy_id` (único), `manager_id`, `default_project_id`, `app_theme_id`, `is_default_member`, `kind`, `identifier`, `color` | S1 é dona da conta de usuário |
| DB-541 | build | `livetat_auth_user_infos` → tabela `user_profiles` 1:1 (telefones país/DDD/número, e o que não cabe em `users`) | idem |
| DB-543 | adapt | `livetat_auth_client_applications` → `client_applications` estendida (o ai9 já tem a tabela, com domínio próprio: **funde**, não duplica) | idem |
| DB-544 | reuse | `livetat_auth_omni_providers` — o vínculo OAuth já existe em `users.provider`/`users.provider_uid` com índice único parcial. A tabela **não é criada** | idem |
| OPS-604 | adapt | Configuração do engine `Livetat::Auth` → ENV + seed | idem |

**`DB-540` é mudança de comportamento observável e precisa de linha no
`improvements-log.md`:** quem entrava com senha passa a entrar por link/código.

**`DB-544` tem uma condição de ETL que não pode ser esquecida:** antes de descartar a tabela,
o ETL **conta as linhas** de `livetat_auth_omni_providers`. Login social permanece
**desligado**; descartar sem contar é `dropped` por omissão.
