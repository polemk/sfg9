# Design: S1 — Autenticação e conta

> **Este documento não repete o mapa.** As 179 linhas item-a-item estão em
> `.migration-ai9/map/auth-admin.md` §2.1 (BE-001…BE-049), §2.2 (FE-001…FE-049), §2.3
> (DB-001…DB-018), §2.4 (OPS-001…OPS-009), §2.11–§2.14 (engines) e nas decisões **DC-01,
> DC-02, DC-05, DC-06, DC-07, DC-10, DC-11, DC-12, DC-19**. Aqui está só o desenho da fatia.

## 1. A decisão que governa tudo: não existe senha

`map/auth-admin.md` **DC-01**. A identidade do ai9 é: código de 6 dígitos (e-mail **ou**
WhatsApp, DEC-14) · magic link · OAuth. O que some do produto: campo de senha, "esqueci a
senha", "trocar senha", e-mail de senha alterada e a confirmação por senha na exclusão de
conta — que vira **confirmação por código enviado ao destino cadastrado**: mesma força,
mesmo canal de identidade do login.

Consequência de desenho que é fácil errar: `login` (username **ou** e-mail) vira
`identifier` (e-mail **ou** telefone). **`username` não é portado** — o legado tinha duas
validações concorrentes rodando juntas (engine 3..20 com `_`; decorator 2..45 sem). O
dry-run do ETL precisa **contar** quantos usuários têm `username` e não têm e-mail válido:
se houver, isso é **bloqueador de cutover** (Q-B7), não detalhe.

**O canal WhatsApp continua ligado.** O DEC-14 revogou o DEC-13.4: `code_validation.rb:27`,
`magic_login.rb:25,70,106` e `registration.rb:60,91,120` já aceitam `method: %w[email
whatsapp]` e **não se mexe neles**. Mas há um achado operacional do mapa (§6 item 7) que
vira tarefa: **`WhatsappPage.tsx` não está roteada** (`App.tsx:56-87`) — é a tela de
pareamento por QR de que `EvolutionConnection.send_message` depende via
`PolemkInstance.first`. Sem rota, ninguém pareia e **o login por WhatsApp cai quando a
sessão da instância expirar**. A rota é de S2; a dependência é registrada aqui.

## 2. O D-39 tem duas portas, e a segunda não veio do legado

`map/auth-admin.md` **DC-02**, achado #4 do `migration-map.md`. Não portar o cadastro do
legado fecha **uma** porta. A outra está aberta na base:

```
backend/app/controllers/api/root.rb:35-46   (allowlist pública)
  %r{^/auth/v1/pre_register/?$}
  %r{^/auth/v1/complete_registration/?$}
  %r{^/auth/v1/visitor_signup/?$}
  %r{^/auth/v1/visitor_signup_with_link/?$}
```

Retirar as quatro da allowlist **e** desmontar os endpoints correspondentes é tarefa
explícita desta fatia (2.1 e 2.2 do `tasks.md`), com teste de regressão. A entrada no
Safegold passa a ser **só por convite** — e o convite carrega **magic link**, nunca senha
(D-38, IMP-A6).

## 3. Aplicação dos contratos transversais nesta fatia

### C1 — escopo por projeto
Esta fatia é quase toda de recursos **globais ou próprios** (`users`, `profile`,
`sessions`), então `current_project!` aparece pouco. Onde aparece, vale a regra do §0.6 sem
exceção: a aba "Projetos" de `/users/:id` (FE-025) lista **paginado e escopado ao que o
solicitante pode ver** — o legado listava `Project.all` — e o `BE-034` é escopado, não
`Project.all`. **Nada nesta fatia introduz `default_scope`**, e o `project_id` do corpo da
requisição continua sendo ignorado onde existir.

### C3 — hierarquia invertida
Três pontos desta fatia dependem do **sinal** da comparação, e cada um tem teste dos dois
lados em `tasks.md` §5.1:

1. **Filtro de usuários** (BE-025): o `role_types_for_filter` do legado (OG vê todos; Admin
   vê Admin/Gerente/Colaborador; Gerente vê Gerente/Colaborador) vira consulta por
   `UserType.hierarchy_level` com os scopes do ai9 (`higher_than` é `<`).
2. **Impersonation** (BE-031, DEC-18.3): Admin personifica **só** hierarquia inferior —
   nunca OG, nunca lateral.
3. **Telas de permissão** (BE-018, FE-024, FE-026): o ator só edita papéis inferiores ao
   seu; Gerente não alcança a tela.

## 4. Perfil estendido: uma tabela a menos, tipos que dizem a verdade

`DC-05`. `livetat_auth_user_infos` é 1:1 com o usuário, 41 campos e tipos errados (`gender`
`integer` guardando constantes string, `tax_document_issue_date` `string`, booleanos
`integer 0/1`). **Não vira tabela**: os campos entram em `users` — 12 deles **já existem**
(`schema.rb:653-660`) — com enum/date/boolean de verdade (IMP-A8). 1:1 obrigatório não
justifica um join em toda requisição, e a tabela separada era a única razão de existir do
`update_info`, rota quebrada (D-43).

## 5. Bloqueio de conta: um campo, e ele revoga a sessão

`DC-07`. O legado tem **dois** campos concorrentes (`is_active` do Django e `deactivated` da
UI) e só um era consultado no login (D-44). A base ai9 não tem **nenhum**. Nasce
`users.blocked_at` (timestamp — *quando* é informação que um sistema de crédito vai querer),
a checagem entra **no gate central** (`api/root.rb`, não espalhada por controller), e
bloquear **denylista o JWT ativo na hora**: "force logout" passa a ser verdade (IMP-A16), e
a conta bloqueada recebe explicação em vez de logout mudo (IMP-A17).

**Duas armadilhas da base, registradas para ninguém tropeçar:** `User.active`
(`user.rb:75`) significa "já logou alguma vez", **não** "está habilitado"; e `users.is_admin`
existe e **não é lido por nada**.

## 6. Impersonation: `adapt` com cinco acréscimos

`DC-10`. Reescrever do zero jogaria fora o claim `impersonated_by` que já sobrevive ao
refresh (`sessions_service.rb:65-69`) e a UI que já existe (`ImpersonateSearch.tsx`, hoje
**morta** — revivê-la economiza uma tela inteira). Os cinco acréscimos: trava de hierarquia,
motivo obrigatório, trilha no `AuditEvent` de S0, expiração da sessão personificada, e
**sem encadeamento** (o personificado não personifica).

E uma correção obrigatória de ordem: `impersonate_service.rb:13-18` responde **404/422 antes
do 403**, vazando existência de usuário para quem não pode personificar (IMP-A28, U5).

## 7. Upload de avatar: nem Paperclip, nem o caminho atual da base

`DC-19`. Active Storage, com validação de tipo **do conteúdo real** no servidor e teto no
servidor. **Não** reusar `assets_proxy_controller.rb` (serve `public/uploads/**` sem
autenticação — padrão do D-82, e ainda sem sanitização de caminho, U1) nem o caminho atual
de `api/v1/uploads.rb:38-42`, que grava direto em `public/uploads/avatars`, confia no
`content_type` **enviado pelo cliente** e **não tem teto de tamanho** (o teto de 2 MB existe
só no front). O legado tem o spoof detector **monkey-patchado para `false`** (D-56):
replicar o caminho atual traria os dois defeitos de volta por outra porta.

## 8. Engines: nenhuma vira engine

`DC-12`. `auth19` → infraestrutura do ai9 que já existe · `auth_ux19` → some (HTTP e telas já
existem) · `auth_omni19` → **morta** (`app_id = 0`, botão não renderizado, D-41), função vira
`oauth.rb` · `mailer19` → `ApplicationMailer` + Sidekiq. Engine é mecanismo de reuso entre
produtos, e **o ai9 já é esse mecanismo**: portar `auth19` como engine criaria uma segunda
base compartilhada dentro da primeira.

Onde o legado tem **duas** telas para a mesma coisa (2 de reset de senha, 2 de "esqueci",
2 de novo/editar usuário — D-42), **a canônica é sempre a do app, não a da engine**
(`DC-11`): é a que está no ar. As da engine vão para `dropped` **com evidência, uma a uma**.

## 9. Decisões que tomei nesta fatia

| # | Questão | Decisão | Razão |
| - | ------- | ------- | ----- |
| **DS1-1** | As telas de permissão (FE-024, FE-026, FE-027, FE-043, FE-513) estavam na fatia interna de autorização (S3 do mapa), cujo servidor eu pus em S0 | **Servidor em S0, telas em S1** | A tela de permissões vive dentro de `/users/:id` e da tela de contas — separá-las das contas produziria duas fatias tocando o mesmo arquivo. O contrato (matriz, hierarquia) fica em S0, onde é testável sem UI |
| **DS1-2** | O e-mail transacional (fatia interna S8) não tem fatia global própria | **Absorvido por S1** | Os 3 e-mails vivos do produto são de identidade: convite, código de acesso e boas-vindas. Sem eles o convite — a **única** porta de entrada depois do DEC-18.7 — não funciona |
| **DS1-3** | `DB-514` (guardar o corpo de todo e-mail, como `livetat_mailer_contacts`) é `build?` | **Metadados sem corpo**, com expurgo de 180 dias, até o usuário responder Q-B18 | Guardar o corpo de todo e-mail sem política de expurgo é passivo de LGPD, e o legado fazia exatamente isso. Metadado resolve investigação de entrega sem reter dado pessoal |
| **DS1-4** | `OPS-501` (DKIM) é `build?` e depende de infraestrutura | **Assinatura no provedor**, chave fora do repositório, e **rotação obrigatória** no runbook | No legado a chave privada estava **versionada no repositório** (D-85): ela precisa ser rotacionada de qualquer forma, independentemente de quem assina |
