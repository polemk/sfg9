# Phase 4 — paridade verificada: **auth-users · engines · console-admin**

> **Rodada de 26/08/2026.** 342 IDs no bloco. **57 viraram `verified`**; o resto fica
> `migrated` (172) **com o motivo escrito na linha**; 83 seguem `dropped` e 30 `pending`.
>
> **Dois IDs da spec não têm linha no ledger** — `NAV-001` e `ENG-navkit`, ambos de
> `engines`. Não os inventei: ficam registrados aqui, com a evidência pronta, para o
> orquestrador decidir se entram como linha nova.
>
> A regra desta fase: **verificar EXECUTANDO, nunca lendo.** Nenhuma linha abaixo virou
> `verified` por leitura de código, por spec verde ou por type-check. Cada uma cita uma
> resposta HTTP real, uma tela renderizada com login de verdade, ou uma medição contra
> o oráculo de produção da DEC-118.

## O que foi executado

| Tag | O que é | Resultado |
| --- | ------- | --------- |
| `E1` | Matriz DEC-18 ao vivo, **5 papéis × recurso**, HTTP real na 3000 | 23/23 |
| `E2` | Hierarquia nos **DOIS sentidos** + D-34 + impersonation | 18 casos, 0 defeito |
| `E3` | As **7 abilities da DEC-108** revogadas e reconcedidas **contra o servidor** | 14/14 |
| `E4` | Login ponta a ponta por e-mail: TTL, 401, reuso, teto **429** | 12 casos |
| `E5` | Busca, paginação, CPF, detalhe, bloqueio, impersonate/stop | 25 casos |
| `E6` | Denylist, logout, refresh, conta bloqueada | achou o **D-QA-02** |
| `E7` | **Tela renderizada com login real** nos 5 papéis (`multi.js`) | 12 capturas |
| `E8` | Suíte: `rspec` **185/185** em banco próprio · `vitest` **56/56** | verde |
| `E9` | Oráculo de existência de conta, reproduzido | achou o **D-QA-01** |
| `E10` | De-para de papel contra o **dump de produção** (DEC-118) | 15/15 |
| `E11` | **Paridade numérica de identidade** contra `sfg_legacy_dump` (DEC-121) | 8 medições |

Scripts em `/tmp/qa-authadmin/`. Capturas em `/tmp/qa-authadmin/shots/`.
Banco de teste próprio: `qa_authadmin_p4_test` (criado e destruído nesta rodada; a suíte
compartilhada **não** foi usada como portão).

## O núcleo: a matriz e a hierarquia, provadas nos dois sentidos

O item de maior risco do mapa era a **escala invertida** (legado *maior = mais poder*,
ai9 *menor = mais poder*). Uma trava apontando para o lado errado passa em qualquer teste
que só verifique que ela existe. Então cada trava foi medida **nos dois sentidos**:

| O que | Lado NEGADO | Lado PERMITIDO |
| ----- | ----------- | -------------- |
| Admin × ability de papel | OG **403** · outro Admin (lateral) **403** · si mesmo **403** | Gerente **200** · Colaborador **200** |
| Admin × permissão de usuário (D-34) | usuário OG **403** · si mesmo **403** | usuário Colaborador **200** |
| Impersonation | Admin→OG **403** · Admin→Admin **403** · Admin→si **422** · Gerente **403** · Colab **403** | OG→Admin **200** · Admin→Colab **200** |
| `visible_user_types` | Gerente não vê OG nem Admin | OG vê os 4; Admin começa em Admin |
| `user_is_readonly` | escrita **403 `READONLY_MODE`** | leitura **200**; e o Colaborador **não-readonly** passa do gate |

Os 403 chegam com código estável e distinto por causa: `ROLE_REQUIRED` (matriz),
`PERMISSION_REQUIRED` (ability), `HIERARCHY_LOCKED` (alvo), `READONLY_MODE` (modificador).

**As 7 abilities da DEC-108 têm efeito real de servidor.** Cada uma foi **revogada**,
medida, e **reconcedida** — não basta ver o toggle na tela:

| Ability | Revogada | Reconcedida |
| --- | --- | --- |
| `may_create_users` | POST /users **403** | **201** |
| `max_users_amount` = 1 | POST /users **422 `LIMIT_*`** | — |
| `may_delete_users` | DELETE /users/:id **403** | — |
| `may_invite_users` | POST invite **403** | — |
| `max_invitations_amount` = 0 | POST invite **422** | **200** |
| `may_modify_public_entries` | candidates **403** · POST memberships **403** | candidates **200** |
| `user_is_readonly` | POST /charges **403** · PUT /users **403** | leitura **200** |

A tela de Permissões renderizada bate com o servidor linha a linha, inclusive os limites:
OG **«sem limite»**, Admin **9999**, Gerente **0** — os mesmos valores que o
`PermissionResolver` devolveu. **Fecha a queixa «faltando todas as abilities» do usuário.**

## O de-para de papel deixou de ser inferência

A **DEC-118** chegou durante esta rodada (commit `b60d121e`, de outro agente) e trouxe o
dump: `livetat_auth_role_types` tem exatamente **OG 1111 · Admin 998 · Gerente 888 ·
Colaborador 799**. Isso vira **oráculo**, e o `Legacy::RoleMap` foi medido contra ele:
**15/15**, pelos dois caminhos (hierarchy e nome), com o papel vazio do D-36 entrando como
Colaborador **e** marcando exceção, e valor desconhecido **levantando** em vez de inventar
um nível plausível. Não existe fórmula `1111 → 1` em lugar nenhum do repositório.

> **Duas consequências da DEC-118 para este bloco, que mudam prioridade de teste:**
> **0 dos 135 usuários de produção são Gerente** — o papel para o qual desenhamos a
> decisão #3 hoje não tem ninguém; **118 são Colaborador**. E **`user_is_readonly` não
> existe como registro em produção**: a única ability que o corte antigo preservava é a
> que ninguém usa.

## Onde a tela foi provada

Login real, uma sessão por papel (`multi.js`, derivado do `browser.js`):

| Papel | `/` leva a | O que se confirmou |
| ----- | ---------- | ------------------ |
| OG | `/users` | lista com identificador de 6 caracteres; `/permissions` abre; trilha abre |
| Gerente | `/receivables` | borderô carregado |
| Colaborador | `/risk` | `/permissions` e `/users` **redirecionam para `/dashboard`** |
| Somente leitura | `/risk` | `/users` redireciona |
| *(sem sessão)* | `/` | tela de login com **E-MAIL** e **WHATSAPP** (DEC-14) |

O despacho por papel do **FE-404 / DEC-09** está correto nos quatro. Endereço inexistente
responde **404 com tela de «não encontrado»**, não redirect silencioso.

**A trilha de auditoria registrou o próprio teste**: «Suporte Livetat **personificando**
Gustavo Lins», com o motivo entre aspas e o «Impersonação encerrada» logo acima — e o
autor registrado é o usuário **real**, não o personificado. É o requisito da DEC-18.3 e da
DEC-59 provado ponta a ponta, por acidente feliz.

## Defeitos achados

Detalhe, reprodução e impacto na seção **«Defeitos»** ao fim deste documento:

| # | O que | Gravidade |
| - | ----- | --------- |
| **D-QA-01** | A tela de login diz se um e-mail **é ou não** cliente do Safegold | **alta** |
| **D-QA-02** | «Sair» **não revoga o access token** — a sessão sobrevive até 15 min | **média-alta** |
| **D-QA-03** | `user_type_id` é `Integer` contra chave primária **uuid**: impossível de usar | baixa |
| **D-QA-04** | Falha do WhatsApp vira **500** com o nome do fornecedor no corpo | média |
| **D-QA-05** | 5 pedidos de código sem concluir **trancam a conta por 15 min** | baixa |

## Duas correções de artefato envelhecido

A lição do dia 26/08 é que **artefato envelhece e ninguém re-confere**. Duas nesta rodada:

1. **A instrução de bancada `rvm use 3.2.3` está errada.** `.ruby-version` diz **3.4.9**,
   o `Gemfile` diz **3.4.9**, e os dois **concordam**. Seguir a instrução quebra todo
   `bundle exec` com `Bundler::RubyVersionMismatch`. O default do rvm já é o certo.
2. **`authorization-matrix.md` ainda registra a Q-A1 como «única pendência, adiada pelo
   DEC-19».** A **DEC-118 fechou a Q-A1** hoje. Re-conferi na fonte antes de repetir.

## O que NÃO deu para verificar, e por quê

- **Reconciliação coluna a coluna contra o DESTINO** — depende do `sfg_etl:load` rodar,
  e a **DEC-121** acionou a fatia de dados/infra para isso. A parte de **identidade** da
  paridade numérica **foi feita nesta rodada** — ver a seção da DEC-121.
- **OAuth Google/Facebook** — os botões renderizam, mas o ida-e-volta com o provedor real
  não é exercitável sem credenciais de app.
- **Login por WhatsApp ponta a ponta** — a instância `AI9_VINAO` está com
  `connection_status: "unknown"` (não pareada). O servidor Evolution responde, a instância
  não. **Depende do usuário parear.** O que deu para medir foi o **modo de falha**, e ele
  é o D-QA-04.
- **`Ver detalhes` da trilha** — a trilha abre e lista, mas o clique no botão não foi
  medido nesta rodada: a trava de força bruta por IP fechou a janela de login antes.
  **É a área que já regrediu uma vez** (`Sheet` sem `SheetContent`) e merece uma passada.
- **Envio real de e-mail** — não há worker Sidekiq de pé neste ambiente.
- **Middleware `Rack::Attack`** — `safelist('allow-localhost')` isenta `127.0.0.1`, então
  os throttles do middleware **não são observáveis daqui**. O que protege o login de fato
  neste ambiente é o limite de aplicação (`check_rate_limit!`), e esse **devolve 429**.



## Paridade numérica: **ela não esperava a carga — a DEC-121 dissolveu isso no meio da rodada**

Eu comecei esta rodada com a instrução *«paridade numérica espera a carga; deixe `migrated`
com o motivo escrito»*. **Essa premissa morreu enquanto eu trabalhava.** A **DEC-121**
(commit `8cccaf06`, 19:45) registra as palavras do usuário: *«a carga real até o momento
são os arquivos que te mandei»*. Não existe data de carga a esperar; o dump **é** a carga
disponível.

Re-conferi na fonte antes de repetir a justificativa antiga — e o banco `sfg_legacy_dump`
**ainda está de pé**. Então a parte de identidade da paridade numérica **foi feita agora**:

| Medição contra `sfg_legacy_dump` (31/05/2025) | Resultado |
| --- | --- |
| `livetat_auth_role_types` | **4 papéis: OG 1111 · Admin 998 · Gerente 888 · Colaborador 799** |
| Distribuição real | OG **6** · Admin **11** · Colaborador **118** · Gerente **0** (135) |
| Usuários **sem papel** (o D-36) | **0** — a lista de exceções nasce **vazia** |
| Usuários com **mais de um papel** | **0** — o `user_type_id` 1:1 do ai9 não perde nada |
| Usuários que entram **só por `username`** | **0** (52 têm username, todos com e-mail) |
| Nomes de ability **em dado** | **16** (2.160 linhas em `Role` + 64 em `RoleType`) |
| `user_is_readonly` **em dado** | **0 linhas** — só existe na fábrica, nunca como registro |
| Memberships | **1.134** para **105** usuários distintos |

**A Q-A1 re-conferida de forma independente.** Não repeti o número da DEC-118: rodei a
consulta. **Exatamente 1 usuário dos 135** (`user_id = 64`) tem ability fora do padrão do
próprio papel, e são **exatamente 8**. Para cada uma das 4 que a DEC-108 preservou, o dump
mostra **1 Colaborador com `1` contra 117 com `0`** — é o mesmo usuário, visto de outro
ângulo. **A DEC-118 está certa.**

> **Um ajuste de contagem que vale registrar.** O D-35 e a DEC-108 falam em **17**
> abilities. Em **dado de produção** existem **16** — `user_is_readonly` tem zero linhas.
> As duas contagens estão certas em contextos diferentes: 17 é o que a
> `AbilityFactory` **declara** em código; 16 é o que a tabela **tem**. Vale a nota porque
> «17» aparece em três documentos sem essa distinção, e a única que falta é justamente a
> que o corte antigo preservava.

**O que continua fora do meu alcance, e de quem é:** a reconciliação **coluna a coluna
contra o destino** depende do `sfg_etl:load` rodar. A DEC-121 acionou a fatia de
**dados/infra** para isso. Medir de novo aqui seria conferir duas vezes e arriscar
divergir — os `DB-*` restantes ficam `migrated` **com esse motivo**, não com o antigo.

---

# Tabela por ID

### auth-users — 125 IDs (51 viraram `verified`)

| ID | Feature | Estado final | Evid. | Como foi verificado / por que nao deu |
| -- | ------- | ------------ | ----- | ------------------------------------- |
| BE-001 | GET /users/sign_in — renderiza a tela de login do Devise já sobrescr | **verified** | `E7` | Tela de login renderizada SEM sessao: marca Safegold, abas **E-MAIL** e **WHATSAPP** (DEC-14), campo unico, rodape Google/Facebook, carousel. `login.png`. |
| BE-002 | POST /users/sign_in (HTML) — autentica por login (username ou e-mail | **verified** | `E4` `E8` | request_code por e-mail: 200; codigo de 6 digitos; TTL medido em 5,0 min; teto devolve **429** (`too_many_requests`) e **nenhum 500** na sequencia de 7 pedidos. |
| BE-003 | POST /users/sign_in.json — login JSON usado pelo front web; devolve  | **verified** | `E4` `E8` | code_validation: codigo errado **401** (nao 500), codigo certo **200** com `access_token` que autentica `/auth/v1/me`; reuso do mesmo codigo recusado. |
| BE-004 | POST /users/sign_in.json (contrato token da engine, hoje sobreposto) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-005 | DELETE /users/sign_out (HTML) — encerra a sessão | **verified** | `E6` `E8` | Logout responde 200 e **revoga o refresh de 30 dias** (refresh seguinte -> 401). Deslogar quem ja saiu nao da erro. ⚠ o ACCESS sobrevive — ver **D-QA-02**. |
| BE-006 | DELETE /users/sign_out.json — revoga o authentication_token do usuár | **verified** | `E6` `E8` | Logout responde 200 e **revoga o refresh de 30 dias** (refresh seguinte -> 401). Deslogar quem ja saiu nao da erro. ⚠ o ACCESS sobrevive — ver **D-QA-02**. |
| BE-007 | GET /u/sign_in — tela de login "forçada" do domínio pub, com redirec | **verified** | `E8` | `?next=` com allowlist same-origin coberto por `sessions_spec.rb` (185/185). |
| BE-008 | GET /:identifier — rota catch-all que também cai em start#sign_in (l | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-009 | GET /users(.json/.xml) — lista/busca usuários (API da engine) | **verified** | `E1` `E5` `E8` | GET /api/v1/users: og/admin/gerente **200**, colaborador e readonly **403 `ROLE_REQUIRED`**. Busca sem acento nos dois lados (`q=helena` e `q=hélena` devolvem o mesmo) e paginacao Kaminari com `x-total-count`/`x-page`/`x-per-page`/`x-total-pages`. |
| BE-010 | GET /users/:id(.json/.xml) — detalhe de um usuário | **verified** | `E5` `E8` | GET /users/:id **200**; id inexistente e id NAO-uuid respondem **404**, nunca 500 — o fallback em cascata do legado nao existe mais. |
| BE-011 | GET /users/sign_up — formulário público de cadastro | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-012 | POST /users — cadastro de usuário (web público, console e API) | **verified** | `E3` `E5` `E8` | POST /api/v1/users **201** com papel EXPLICITO; **403** sem `may_create_users`; **422** no teto `max_users_amount`. ⚠ o parametro `user_type_id` e inutilizavel — ver **D-QA-03**. |
| BE-013 | PATCH/PUT /users/:id — atualização de dados + troca de senha com ver | **verified** | `E1` `E6` `E8` | PUT/PATCH /users/:id: readonly recebe **403 `READONLY_MODE`**. Autorizacao de servidor. |
| BE-014 | DELETE /users/:id — remoção da própria conta exigindo a senha | **verified** | `E8` | Auto-remocao isenta da matriz, coberta por `users_account_lifecycle_spec.rb`. |
| BE-015 | GET /users/:user_id/info — leitura do UserInfo | **verified** | `E5` `E8` | GET e PATCH `/auth/v1/me` respondem 200 com o perfil estendido. |
| BE-016 | PATCH/PUT /users/:user_id/info — atualização do perfil estendido (CP | **verified** | `E5` `E8` | GET e PATCH `/auth/v1/me` respondem 200 com o perfil estendido. |
| BE-017 | GET /users/:id/avatar.jpeg — serve o arquivo de avatar inline | **migrated** | — | Avatar por ActiveStorage: nao exercitado nesta rodada (upload real). |
| BE-018 | PUT /users/:id/abilities.js — altera o valor de uma permissão indivi | **verified** | `E2` `E3` `E8` | PUT permissions/:key com o `:id` do **ALVO** mandando. **D-34 fechado, provado nos DOIS sentidos**: admin edita colaborador e gerente (200) e e barrado em OG, em outro admin (lateral) e em si mesmo (**403 `HIERARCHY_LOCKED`**). |
| BE-019 | GET /users/password/remember — página "esqueci minha senha" | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-020 | POST /users/password/notify — gera token de reset e dispara o e-mail | **verified** | `E4` `E8` | request_code por e-mail: 200; codigo de 6 digitos; TTL medido em 5,0 min; teto devolve **429** (`too_many_requests`) e **nenhum 500** na sequencia de 7 pedidos. |
| BE-021 | GET /users/password/reset/:reset_password_token — página para defini | **migrated** | `E8` | Magic link de uso unico coberto por spec; **nao exercitado ponta a ponta na tela** nesta rodada. |
| BE-022 | POST /users/password/set/:reset_password_token — grava a nova senha  | **migrated** | `E8` | Magic link de uso unico coberto por spec; **nao exercitado ponta a ponta na tela** nesta rodada. |
| BE-023 | OAuth Facebook — GET /users/auth/facebook + callback, com três modos | **migrated** | — | OAuth Google/Facebook: os botoes renderizam no login, mas o **ida-e-volta com o provedor real nao e exercitavel** neste ambiente (sem credenciais de app). Fica `migrated`. |
| BE-024 | OAuth Facebook — falha (failure) nos três modos | **migrated** | — | OAuth Google/Facebook: os botoes renderizam no login, mas o **ida-e-volta com o provedor real nao e exercitavel** neste ambiente (sem credenciais de app). Fica `migrated`. |
| BE-025 | GET /u/console/search — busca paginada de usuários no console, restr | **verified** | `E5` `E8` | Busca `?q=` por nome, nome do meio e e-mail parcial; insensivel a acento nos dois lados (IMP-A13). |
| BE-026 | GET /u/users e GET /u — índice de usuários do console | **verified** | `E5` `E8` | Busca `?q=` por nome, nome do meio e e-mail parcial; insensivel a acento nos dois lados (IMP-A13). |
| BE-027 | GET /u/users/:id e GET /u/:id — detalhe do usuário | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-028 | Formulário de novo usuário — GET /u/console/users/add e GET /u/users | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-029 | Formulário de edição de usuário — GET /u/console/users/:id/edit e GE | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-030 | DELETE /u/users/:id — remoção de usuário pelo console | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-031 | POST/GET /u/users/:id/impersonate — assume a identidade de outro usu | **verified** | `E2` `E5` `E7` `E8` | impersonate/start: OG->Admin e Admin->Colaborador **permitidos**; Admin->OG, Admin->Admin (lateral) e Admin->si mesmo **negados**; gerente e colaborador nao alcancam; sem `reason` -> 400. **A trilha registrou o teste**: «Suporte Livetat personificando Gustavo Lins», motivo entre aspas. |
| BE-032 | POST /u/users/stop_impersonating — volta para o usuário real | **verified** | `E5` `E7` `E8` | impersonate/stop devolve a sessao real (200); a sessao personificada responde como o ALVO em `/auth/v1/me`; **encadear** outra impersonacao e recusado (403). A trilha mostra «Impersonacao encerrada». |
| BE-033 | GET /api/v1/users/impersonate/search — autocomplete de usuários para | **verified** | `E5` `E8` | Busca `?q=` por nome, nome do meio e e-mail parcial; insensivel a acento nos dois lados (IMP-A13). |
| BE-034 | GET /u/users/search_projects — lista todos os projetos marcando os q | **verified** | `E5` `E8` | GET /users/:id/memberships e /users/:id/projects respondem 200 com os projetos do usuario. |
| BE-035 | GET /u/users/:id/search_cpf/su.json — valida CPF em tempo real (form | **verified** | `E5` `E8` | validate_cpf: **422** para formato invalido, **200** para CPF livre. Os 405/406 do legado nao existem mais. |
| BE-036 | POST /u/users/:user_id/deactivate_and_force_logout — bloqueia a cont | **verified** | `E5` `E6` `E8` | block/unblock: gerente e colaborador **403** (matriz `users` = `CRUD CRUD R -`); admin **200** e o banco reflete; desbloqueio volta `blocked?` a false. |
| BE-037 | POST /u/users/:user_id/reactivate — desbloqueia a conta | **verified** | `E5` `E6` `E8` | block/unblock: gerente e colaborador **403** (matriz `users` = `CRUD CRUD R -`); admin **200** e o banco reflete; desbloqueio volta `blocked?` a false. |
| BE-038 | Logout forçado de conta desativada em toda requisição do domínio pub | **verified** | `E6` `E8` | **Provado no gate central**: conta bloqueada derruba a sessao JA ABERTA na requisicao seguinte, com **403 `ACCOUNT_BLOCKED`** e o motivo — tanto em `/api/v1/*` quanto em `/auth/v1/me`. |
| BE-039 | Redirecionamento para login quando a rota exige usuário | **verified** | `E1` `E8` | Sem `Authorization` -> **401** em `/users`, `/permissions` e `/audit_trail`. |
| BE-040 | GET /permissions — casca da tela de permissões | **verified** | `E1` `E2` `E7` `E8` | GET /api/v1/permissions e /user_types: og/admin **200**; gerente, colaborador e readonly **403**. `visible_user_types` estreita por papel — og ve os 4, admin comeca em admin, gerente em gerente, colaborador em colaborador. |
| BE-041 | GET /permissions/search — lista os role types e suas abilities | **verified** | `E1` `E2` `E7` `E8` | GET /api/v1/permissions e /user_types: og/admin **200**; gerente, colaborador e readonly **403**. `visible_user_types` estreita por papel — og ve os 4, admin comeca em admin, gerente em gerente, colaborador em colaborador. |
| BE-042 | PUT /permissions/:id.js — liga/desliga uma permissão de um role type | **verified** | `E2` `E3` `E8` | PUT permissions/:key com o `:id` do **ALVO** mandando. **D-34 fechado, provado nos DOIS sentidos**: admin edita colaborador e gerente (200) e e barrado em OG, em outro admin (lateral) e em si mesmo (**403 `HIERARCHY_LOCKED`**). |
| BE-043 | DELETE /permissions/:id — remove uma ability | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-044 | GET /u/memberships/search — busca usuários para adicionar a um proje | **verified** | `E3` `E8` | GET /memberships/candidates e POST /memberships: **403** sem `may_modify_public_entries`, **200** com — a ability e checada no SERVIDOR, nao so na caixa da tela. |
| BE-045 | POST /memberships — vincula usuário a um projeto | **verified** | `E3` `E8` | GET /memberships/candidates e POST /memberships: **403** sem `may_modify_public_entries`, **200** com — a ability e checada no SERVIDOR, nao so na caixa da tela. |
| BE-046 | DELETE /memberships/:id — desvincula usuário de projeto | **migrated** | — | DELETE /memberships/:id nao exercitado — evitei remover vinculo do seed compartilhado. |
| BE-047 | Autenticação por token — usuário (simple_token_authentication) e apl | **verified** | `E5` `E8` | Token adulterado, `Authorization` sem `Bearer` e `Bearer` vazio: **401** nos tres. |
| BE-048 | Geração de identificador público de 6 caracteres por usuário (identi | **verified** | `E7` `E8` | Identificador publico de 6 caracteres visivel na lista renderizada (ZRQ8G7, V3SJQQ, 21NHWU, VFTBL1, 9UI7WV, WP74B1). |
| BE-049 | Criação automática do "esqueleto" do usuário: role + abilities + use | **migrated** | — | «Esqueleto» do usuario: a criacao foi exercitada (BE-012) mas os callbacks completos nao foram medidos um a um. |
| FE-001 | Tela de login do produto (/u/sign_in, e também /:identifier) — fundo | **verified** | `E7` | Tela de login renderizada SEM sessao: marca Safegold, abas **E-MAIL** e **WHATSAPP** (DEC-14), campo unico, rodape Google/Facebook, carousel. `login.png`. |
| FE-002 | Painel Entrar | **verified** | `E7` | Tela de login renderizada SEM sessao: marca Safegold, abas **E-MAIL** e **WHATSAPP** (DEC-14), campo unico, rodape Google/Facebook, carousel. `login.png`. |
| FE-003 | Painel Cadastre-se (cadastro público) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-004 | Painel Esqueceu a senha (recuperação) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-005 | Login com Facebook | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-006 | Aviso "você precisa entrar na sua conta antes de acessar essa página | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-007 | Página de definir nova senha (versão do app, com tema) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-008 | Página de definir nova senha (versão da engine, layout Materialize) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-009 | Página "esqueci a senha" standalone (/users/password/remember) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-010 | Estado "link de recuperação expirado" | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-011 | Console → Usuários: cabeçalho, contadores e área de lista | **verified** | `E5` `E7` | Lista de usuarios renderizada: contadores (Total 11 / Ativos 10 / OG 5 / Colaboradores 4) **batem com `GET /users/stats`**; filtro por papel; card com papel, identificador, e-mail, telefone e ultimo login. |
| FE-012 | Busca de usuários com debounce | **verified** | `E5` `E7` | Lista de usuarios renderizada: contadores (Total 11 / Ativos 10 / OG 5 / Colaboradores 4) **batem com `GET /users/stats`**; filtro por papel; card com papel, identificador, e-mail, telefone e ultimo login. |
| FE-013 | Filtro por tipo de usuário | **verified** | `E5` `E7` | Lista de usuarios renderizada: contadores (Total 11 / Ativos 10 / OG 5 / Colaboradores 4) **batem com `GET /users/stats`**; filtro por papel; card com papel, identificador, e-mail, telefone e ultimo login. |
| FE-014 | Paginação da lista de usuários | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-015 | Widget de usuário na lista | **verified** | `E5` `E7` | Lista de usuarios renderizada: contadores (Total 11 / Ativos 10 / OG 5 / Colaboradores 4) **batem com `GET /users/stats`**; filtro por papel; card com papel, identificador, e-mail, telefone e ultimo login. |
| FE-016 | Dropdown de ações do widget de usuário | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-017 | Copiar identificador do usuário para a área de transferência | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-018 | Botão "Cadastrar" e abertura do helper de criação | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-019 | Formulário de cadastro/edição de usuário (console) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-020 | Validação de senha × confirmação no formulário de usuário | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-021 | Upload e pré-visualização de avatar no formulário | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-022 | Detalhe do usuário — abas Geral / Projetos | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-023 | Detalhe do usuário — card "Dados do usuário" | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-024 | Detalhe do usuário — painel de permissões individuais com toggles | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-025 | Detalhe do usuário — aba Projetos: associar/desassociar projetos | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-026 | Console → Permissões: lista de tipos de usuário e suas permissões | **verified** | `E1` `E2` `E3` `E7` | Tela de Permissoes renderizada com as **7 abilities da DEC-108** nos 4 papeis, com texto de ajuda e a regra de hierarquia escrita na tela. Os limites exibidos batem com o resolver: OG «sem limite», Admin 9999, Gerente 0. **Fecha a queixa «1 de 17» do usuario.** |
| FE-027 | Toggle de permissão por tipo de usuário | **verified** | `E1` `E2` `E3` `E7` | Tela de Permissoes renderizada com as **7 abilities da DEC-108** nos 4 papeis, com texto de ajuda e a regra de hierarquia escrita na tela. Os limites exibidos batem com o resolver: OG «sem limite», Admin 9999, Gerente 0. **Fecha a queixa «1 de 17» do usuario.** |
| FE-028 | Console → Minha conta: perfil (avatar, nome, sobrenome, CPF, e-mail, | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-029 | Minha conta — validação de CPF em tempo real | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-030 | Minha conta — máscara e bloqueio do telefone | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-031 | Minha conta — copiar "Código" (identifier) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-032 | Minha conta — trocar senha | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-033 | Minha conta — remover a conta | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-034 | Minha conta — aceite de Termos de Uso / Política de Privacidade | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-035 | Minha conta — salvamento automático via fila do rodapé | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-036 | Menu do usuário na toolbar | **verified** | `E5` `E7` | Menu do usuario, chip «Modo agente» e a busca de impersonation presentes na casca renderizada; o fluxo de impersonation foi exercitado pela API e apareceu na trilha. |
| FE-037 | Chip do usuário / indicador "Vendo como" | **verified** | `E5` `E7` | Menu do usuario, chip «Modo agente» e a busca de impersonation presentes na casca renderizada; o fluxo de impersonation foi exercitado pela API e apareceu na trilha. |
| FE-038 | Busca de impersonation na toolbar (autocomplete) | **verified** | `E5` `E7` | Menu do usuario, chip «Modo agente» e a busca de impersonation presentes na casca renderizada; o fluxo de impersonation foi exercitado pela API e apareceu na trilha. |
| FE-039 | Sair (logout) | **verified** | `E6` `E8` | «Sair» -> logout 200 e refresh revogado. ⚠ ressalva do **D-QA-02**. |
| FE-040 | Projeto → adicionar membro (autocomplete de usuários) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-041 | Projeto → lista de membros e remoção | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-042 | Feedback de erros nas operações de usuário (console) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-043 | Feedback de erros nas operações de permissão | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-044 | Bloqueio da sessão quando a conta é desativada | **verified** | `E6` `E8` | Interceptor: conta bloqueada devolve 403 `ACCOUNT_BLOCKED` com motivo, em vez de 401 mudo (IMP-A17). |
| FE-045 | Toolbar das telas de autenticação (logo do tema) | **verified** | `E7` | Tela de login renderizada SEM sessao: marca Safegold, abas **E-MAIL** e **WHATSAPP** (DEC-14), campo unico, rodape Google/Facebook, carousel. `login.png`. |
| FE-046 | Tela "cadastro concluído" da engine | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-047 | Telas de cadastro/listagem/detalhe de usuário da engine (new, index, | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-048 | Telas Devise cruas da auth19 (sessions/new, registrations/new, regis | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-049 | Overrides de UI injetados pela auth_ux19 no app hospedeiro (chip do  | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| DB-001 | livetat_auth_users / Livetat::Auth::User | **migrated** | `E11` | **Contra o dump**: 135 usuarios, **0 sem e-mail**, 52 com `username` e **0 que entrem SO por `username`** — fecha numericamente o P-049/DEC-45. Paridade de COLUNA a coluna e da fatia de dados/infra (DEC-121). |
| DB-002 | livetat_auth_users — colunas adicionadas pelo app | **migrated** | — | **Nao e mais "espera a carga"** — a **DEC-121** dissolveu isso: o dump de 31/05/2025 **e** a carga real disponivel. Fica `migrated` porque a reconciliacao coluna a coluna contra o destino e da fatia de **dados/infra**, que a DEC-121 acionou; duplicar aqui seria conferir duas vezes e divergir. |
| DB-003 | livetat_auth_users — avatar Paperclip | **migrated** | — | **Nao e mais "espera a carga"** — a **DEC-121** dissolveu isso: o dump de 31/05/2025 **e** a carga real disponivel. Fica `migrated` porque a reconciliacao coluna a coluna contra o destino e da fatia de **dados/infra**, que a DEC-121 acionou; duplicar aqui seria conferir duas vezes e divergir. |
| DB-004 | livetat_auth_user_infos / Livetat::Auth::UserInfo | **migrated** | — | **Nao e mais "espera a carga"** — a **DEC-121** dissolveu isso: o dump de 31/05/2025 **e** a carga real disponivel. Fica `migrated` porque a reconciliacao coluna a coluna contra o destino e da fatia de **dados/infra**, que a DEC-121 acionou; duplicar aqui seria conferir duas vezes e divergir. |
| DB-005 | livetat_auth_roles / Livetat::Auth::Role | **verified** | `E11` | **Paridade NUMERICA contra o dump de producao** (`sfg_legacy_dump`, 31/05/2025): 135 usuarios, **0 sem papel** e **0 com mais de um papel**. Isso prova que o `user_type_id` 1:1 do ai9 **nao perde nada** ao colapsar `livetat_auth_roles` — e que a lista de excecoes do D-36 nasce **vazia** neste dado. |
| DB-006 | livetat_auth_role_types / Livetat::Auth::RoleType | **verified** | `E8` `E10` | **De-para de papel com ORACULO DE PRODUCAO (DEC-118): 15/15.** 1111->og(1), 998->admin(2), 888->gerente(3), 799->colaborador(4), pelos dois caminhos (hierarchy e nome). Papel vazio (D-36) entra como Colaborador **e** marca excecao. Valor desconhecido **levanta** `UnknownLegacyRole` — nao inventa nivel plausivel. Nao existe formula em lugar nenhum. |
| DB-007 | livetat_auth_abilities / Livetat::Auth::Ability | **verified** | `E3` `E8` `E11` | Catalogo com **exatamente as 7 chaves** da DEC-108 no ai9, cada uma com efeito de servidor provado. **Contra o dump**: o legado tem **16** nomes de ability em DADO (2.160 linhas em `Role` + 64 em `RoleType`), e **`user_is_readonly` tem 0 linhas** — ela so existe na fabrica, nunca como registro. O 17o do D-35 e declaracao de codigo, nao dado. |
| DB-008 | Catálogo de permissões (dados de referência) | **verified** | `E3` `E8` `E11` | Catalogo com **exatamente as 7 chaves** da DEC-108 no ai9, cada uma com efeito de servidor provado. **Contra o dump**: o legado tem **16** nomes de ability em DADO (2.160 linhas em `Role` + 64 em `RoleType`), e **`user_is_readonly` tem 0 linhas** — ela so existe na fabrica, nunca como registro. O 17o do D-35 e declaracao de codigo, nao dado. |
| DB-009 | livetat_auth_client_applications / Livetat::Auth::ClientApplication | **migrated** | — | **Nao e mais "espera a carga"** — a **DEC-121** dissolveu isso: o dump de 31/05/2025 **e** a carga real disponivel. Fica `migrated` porque a reconciliacao coluna a coluna contra o destino e da fatia de **dados/infra**, que a DEC-121 acionou; duplicar aqui seria conferir duas vezes e divergir. |
| DB-010 | livetat_auth_omni_providers / Livetat::AuthOmni19::Provider | **migrated** | — | **Nao e mais "espera a carga"** — a **DEC-121** dissolveu isso: o dump de 31/05/2025 **e** a carga real disponivel. Fica `migrated` porque a reconciliacao coluna a coluna contra o destino e da fatia de **dados/infra**, que a DEC-121 acionou; duplicar aqui seria conferir duas vezes e divergir. |
| DB-011 | memberships / Membership | **migrated** | `E11` | **Contra o dump**: 1.134 memberships para 105 usuarios distintos. O numero da ORIGEM esta medido; a reconciliacao contra o DESTINO depende do `sfg_etl:load` rodar, que e da fatia de dados/infra (DEC-121). |
| DB-012 | Colunas de rastreio Devise (trackable) | **migrated** | — | **Nao e mais "espera a carga"** — a **DEC-121** dissolveu isso: o dump de 31/05/2025 **e** a carga real disponivel. Fica `migrated` porque a reconciliacao coluna a coluna contra o destino e da fatia de **dados/infra**, que a DEC-121 acionou; duplicar aqui seria conferir duas vezes e divergir. |
| DB-013 | Regras de senha e tokens | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| DB-014 | Validações de usuário | **migrated** | — | **Nao e mais "espera a carga"** — a **DEC-121** dissolveu isso: o dump de 31/05/2025 **e** a carga real disponivel. Fica `migrated` porque a reconciliacao coluna a coluna contra o destino e da fatia de **dados/infra**, que a DEC-121 acionou; duplicar aqui seria conferir duas vezes e divergir. |
| DB-015 | Nível de confiabilidade do perfil (confiability_level) | **migrated** | — | **Nao e mais "espera a carga"** — a **DEC-121** dissolveu isso: o dump de 31/05/2025 **e** a carga real disponivel. Fica `migrated` porque a reconciliacao coluna a coluna contra o destino e da fatia de **dados/infra**, que a DEC-121 acionou; duplicar aqui seria conferir duas vezes e divergir. |
| DB-016 | Validações de CPF/CNPJ/telefone/e-mail do perfil | **migrated** | — | **Nao e mais "espera a carga"** — a **DEC-121** dissolveu isso: o dump de 31/05/2025 **e** a carga real disponivel. Fica `migrated` porque a reconciliacao coluna a coluna contra o destino e da fatia de **dados/infra**, que a DEC-121 acionou; duplicar aqui seria conferir duas vezes e divergir. |
| DB-017 | Origem legada (Django) — usuários | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| DB-018 | Origem legada (Django) — memberships e interceptors | **migrated** | — | **Nao e mais "espera a carga"** — a **DEC-121** dissolveu isso: o dump de 31/05/2025 **e** a carga real disponivel. Fica `migrated` porque a reconciliacao coluna a coluna contra o destino e da fatia de **dados/infra**, que a DEC-121 acionou; duplicar aqui seria conferir duas vezes e divergir. |
| OPS-001 | E-mail de boas-vindas com credenciais para usuário recém-criado | **migrated** | `E3` | O convite responde 200 com `expires_at` de 24h; o **envio real de e-mail** nao foi observado (fila sem worker de pe neste ambiente). |
| OPS-002 | E-mail de instruções de recuperação de senha | **migrated** | `E3` | O convite responde 200 com `expires_at` de 24h; o **envio real de e-mail** nao foi observado (fila sem worker de pe neste ambiente). |
| OPS-003 | E-mail de confirmação de senha alterada | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-004 | Implementação original das notificações de senha na engine (sobrepos | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-005 | Job InsertProjectsOnDefaultUserJob — associa o usuário "membro padrã | **migrated** | — | `DefaultMemberJob`: exige worker Sidekiq de pe; nao verificado nesta rodada. |
| OPS-006 | Reexecução do job em todo update do usuário | **migrated** | — | `DefaultMemberJob`: exige worker Sidekiq de pe; nao verificado nesta rodada. |
| OPS-007 | Configuração OmniAuth/Facebook | **migrated** | — | OAuth Google/Facebook: os botoes renderizam no login, mas o **ida-e-volta com o provedor real nao e exercitavel** neste ambiente (sem credenciais de app). Fica `migrated`. |
| OPS-008 | Configuração de autenticação por aplicação cliente e realm | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-009 | Seeds de tipos de usuário, permissões e reset em massa | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |

### engines — 111 IDs (4 viraram `verified`)

| ID | Feature | Estado final | Evid. | Como foi verificado / por que nao deu |
| -- | ------- | ------------ | ----- | ------------------------------------- |
| BE-500 | Configuração global da engine via mattr_accessor (headers de client  | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-501 | Modelo User: Devise (database_authenticatable, registerable, recover | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-502 | Token de API por usuário (simple_token_authentication) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-503 | Avatar do usuário via kt-paperclip, 5 estilos, com fallback e detecç | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-504 | Modelos RoleType (tipo de usuário com hierarchy) e Role (vínculo use | **verified** | `E1` `E8` | `visible_user_types` verificado ao vivo nos 5 papeis: cada um enxerga do proprio nivel **para baixo**; so o OG ve o RoleType OG. |
| BE-505 | AbilityFactory — catálogo de abilities (condicionais + limites) com  | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-506 | Métodos de ability injetados dinamicamente em User (may_x? e max_y) | **verified** | `E1` `E2` `E3` `E8` | A matriz declarativa responde por 45+ recursos e **nenhum endpoint decide sozinho** — os 403 chegam uniformes (`ROLE_REQUIRED`, `PERMISSION_REQUIRED`, `HIERARCHY_LOCKED`, `READONLY_MODE`). |
| BE-507 | Modelo UserInfo — perfil estendido + nível de confiabilidade calcula | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-508 | Modelo ClientApplication + autenticação de aplicação cliente por hea | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-509 | Rotas e configuração do Devise pela engine | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-510 | Fluxo de reset de senha no modelo (push/pop de token, timestamps, co | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-511 | Locales pt-BR/en fornecidos pela engine (devise + datas) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-512 | Configuração OmniAuth/Facebook | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-513 | CallbacksController — 3 modos de callback (sign_in, sign_up, both) + | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-514 | User.from_omniauth + modelo Provider (vínculo user ↔ provider social | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-515 | Hierarquia de controllers base da engine | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-516 | SessionsController#create — login em dois formatos com regras difere | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-517 | SessionsController#destroy — logout HTML e JSON | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-518 | RegistrationsController#index — listagem e busca de usuários | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-519 | RegistrationsController CRUD de usuário e de user_info | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-520 | RegistrationsController#abilities — alteração pontual do valor de um | **verified** | `E2` `E8` | **Trava de hierarquia com o SINAL certo** (menor = mais poder), provada nos dois sentidos: o que e negado *e* o que e permitido. |
| BE-521 | PasswordsController — fluxo custom de recuperação de senha (remember | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-522 | Fachada Notification — os 2 e-mails do fluxo de senha, e a substitui | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-523 | Efeitos colaterais globais da engine: transferência de config para o | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-524 | Rotas da engine (/users/), incluindo o remount do auth19 | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-525 | Configuração da engine (labels custom + persona "admin genérico") | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-526 | Modelo Message — ticket com 2 campos customizáveis e tokens público/ | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-527 | Máquina de estados da mensagem (8 estados) e transições automáticas | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-528 | Modelo Note — thread de respostas com citação, controle de não-lidas | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-529 | Modelos Context (tipo de mensagem), Observer e ObserverContext (quem | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-530 | Notification — as 4 notificações por e-mail do módulo | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-531 | MessagesController — CRUD, busca de notas e fechamento | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-532 | Sobrescritas do SFG sobre os controllers da engine (roteamento de re | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-533 | Configuração de e-mail da engine (identidade visual + SMTP global) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-534 | GrindMailer — API de alto nível de envio, com log em livetat_mailer_ | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-535 | Mailer Mailing (ActionMailer) com anexos inline, e seus decorators | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-536 | Os 3 e-mails próprios do SFG (temáticos por app_theme) e o Notificat | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-537 | ContactsController + rotas HTTP /mailer/ | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-538 | Helper Ruby de view (morto) e utilitários de DateTime (vivos) | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-539 | A engine não carrega no SFG | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-747 | Controllers Devise vazios da auth19 (Livetat::Auth::{Sessions,Regist | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-748 | Livetat::Auth::ClassLevelInheritableAttributes — mixin que propaga a | **verified** | `E3` `E8` | `PermissionResolver` resolve por **consulta a cada request**: revogar em `user_type_permissions` muda a resposta HTTP seguinte. Sem cache e sem copia — o **D-35 nao existe por construcao**. |
| FE-500 | Layout base da engine (layouts/livetat/auth_ux19/application) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-501 | Layout real das telas de auth (sobrescrita do app) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-502 | Tela de login da engine (users/sessions/new) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-503 | Tela de login obsoleta | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-504 | Tela "esqueci a senha" da engine (users/passwords/remember) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-505 | Tela "esqueci a senha" no app (cópia idêntica) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-506 | Tela "nova senha" da engine (users/passwords/reset) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-507 | Tela "nova senha" do SFG (a que está no ar) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-508 | Tela devise padrão de troca de senha (users/passwords/edit) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-509 | Tela de cadastro (users/registrations/new + new/_body + new/_form) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-510 | Tela "cadastro concluído" (registrations/done) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-511 | Lista de usuários (registrations/index) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-512 | Perfil do usuário (registrations/show + show/_body) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-513 | Painel de permissões do usuário (show/_abilities) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-514 | Edição de conta devise (registrations/edit) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-515 | Widget de usuário (card) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-516 | Payloads JSON/XML de usuário (contrato canônico) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-517 | Formulário de user_info (resposta JS) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-518 | Partial de metadados/SEO das telas de auth | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-519 | Overrides Deface de menu (chip do usuário e item "Sair") | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-520 | Views devise cruas da engine (sessions, registrations, passwords, co | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-521 | Partials JS do SDK do Facebook (_component, _initializer, _sign) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-522 | Botões "entrar/cadastrar com Facebook" no SFG | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-523 | Formulário de mensagem (messages/_form) e o formulário equivalente d | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-524 | Telas placeholder da engine (messages/index, messages/new/new) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-525 | Respostas JS de update/destroy alcançadas por render implícito | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-526 | Payloads JSON de mensagem | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-527 | Telas do SFG que enviam mensagem | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-528 | Console de mensagens administrativas e de observadores (SFG) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-529 | Layout web da engine | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-530 | Template de e-mail confirm_feedback_to (HTML + texto) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-531 | Template de e-mail confirm_account_of | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-532 | Template de e-mail account_invitation | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-533 | Template de e-mail generic_message | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-534 | Template de e-mail generic_message_with_link | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-535 | Template de e-mail do SFG send_welcome_email_to_new_generic_user (cr | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-536 | Template de e-mail do SFG send_email_to_recovery_password_user (inst | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-537 | Template de e-mail do SFG send_email_to_reset_password_user (confirm | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-538 | Biblioteca de componentes JS/CSS do kit (insumo direto para a lib de | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-539 | Componentes de navegação matricial (JS/CSS/views) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| DB-500 | livetat_auth_users | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-501 | livetat_auth_roles | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-502 | livetat_auth_role_types | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-503 | livetat_auth_abilities | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-504 | livetat_auth_client_applications | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-505 | livetat_auth_user_infos | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-506 | livetat_auth_omni_providers | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-507 | *(nenhuma)* | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| DB-508 | livetat_feedback_messages | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-509 | livetat_feedback_states | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-510 | livetat_feedback_contexts | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-511 | livetat_feedback_observers | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-512 | livetat_feedback_observer_contexts | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-513 | livetat_feedback_notes | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-514 | livetat_mailer_contacts | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-515 | delayed_jobs | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| DB-516 | *(nenhuma)* | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-500 | Configuração SMTP global do app | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-501 | Assinatura DKIM de todos os e-mails | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-502 | Worker delayed_job (envio assíncrono) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-503 | Rake task de instalação do runner | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-504 | Logos de e-mail lidos do filesystem | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-505 | Avatares no filesystem (paperclip) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-506 | Detecção de spoof de mídia desabilitada globalmente | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-507 | Seeds obrigatórios de dados de referência | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-508 | Build de assets pelo webpacker lendo o full_gem_path das gems | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-509 | Carregamento de decorators por to_prepare + glob, com erro engolido | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-749 | Bootstrap das engines livetat (auth19, auth_omni19, auth_ux19, ux_ki | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| ENG-auth_omni19 | Engine `auth_omni19` (login social Facebook) montada no app hospedei | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |

### console-admin — 106 IDs (2 viraram `verified`)

| ID | Feature | Estado final | Evid. | Como foi verificado / por que nao deu |
| -- | ------- | ------------ | ----- | ------------------------------------- |
| BE-390 | Rota-mestra do console. GET /u/console(/:resource)(/:topic)(/:sectio | **verified** | `E7` | **Despacho por papel confirmado NA TELA** (DEC-09): entrando como OG, `/` leva a `/users`; como Gerente, a `/receivables`; como Colaborador e como somente-leitura, a `/risk`. Area desconhecida responde **404 com tela de nao encontrado**, nao redirect silencioso. |
| BE-391 | fetch_resource — resolução de projeto corrente + saneamento do cooki | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-392 | Resolução do título da aba por resource (case/when com ~38 áreas) e  | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-393 | Despacho genérico de view. Caso else final: @view_path = "pub/consol | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-394 | Branch "viewing token" (UUID em :topic). Se :topic casar com regex U | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-395 | Despacho users detalhe: resource=users, topic numérico != 0, section | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-396 | Despacho changelog: parts/changelog/body (sem topic/section) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-397 | Despacho contracts: detalhe (topic numérico, section != edit/new_ver | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-398 | Despacho help_items: detalhe; section == 'new_item' (topic = id de H | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-399 | Despacho themes: detalhe; section == 'form' com topic em branco → Ap | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-400 | Despacho projects: topic == 'new' → Project.new(user_id: current_use | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-401 | Despacho carriers + section == 'carrier_connections' → @owner = Carr | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-402 | Despacho receivables: topic == 'new' → ReceivableEntry.new(user_id:, | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-403 | Despacho renegotiations: topic == 'new' → Renegotiation.new(project_ | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-404 | Despacho availability_templates (detalhe) e availability (@project = | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-405 | Despacho companies detalhe (topic numérico, section != edit/new) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-406 | Despacho risk_operations: topic == 'new' monta cascata de dependênci | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-407 | Despacho project_guarantees: new (ProjectGuarantee.new(user_id:) + @ | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-408 | Despacho structured_operations: new/edit com cascata company→carrier | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-409 | Despacho charges: topic numérico e section em branco → detalhe; sect | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-410 | respond_to do console: format.html → render 'pub/console/index'; for | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-411 | Contrato de renderização em duas passadas (base/body.js.erb): limpa  | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-412 | console#reload — GET /consolereload/ (pub_console_reload_path). Rend | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-413 | Actions órfãs state_select e city_select (selects encadeados país→es | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-414 | Autenticação e bloqueio do console: requires_current_user? retorna t | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-415 | protect_from_forgery except: :index no console | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-416 | Layout preloaded (splash + loader JS inline) usado por todo o consol | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-417 | root "pub/console#index" — a raiz do domínio é o console | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-418 | create_console_menu — a definição do menu lateral inteiro, por papel | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-419 | Bug do locked: o helper marca locked nos itens, mas a view lê g[:loc | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-420 | Pub::DashController#index (GET /dash, gerado por resources :dash) →  | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-421 | Pub::DashController#show (GET /dash/:id) → render 'pub/console/parts | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-422 | Pub::DashController#search — GET /dash/search, defaults: {format: :j | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-423 | Defaults de listagem do dash (fetch_loq): l (limit) = 20, o (offset) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-424 | Pub::AdminMessagesController#search — GET /admin_messages/search, de | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-425 | Pub::AdminMessagesController#index → render 'pub/messages/index' | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| BE-426 | Pub::ConsoleObserversController#search — GET /console_observes/searc | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-427 | Pub::ConsoleObserversController#new — GET /console_observers/new(.js | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-428 | Pub::ConsoleObserversController#edit — GET /console_observers/:id/ed | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| BE-429 | CRUD real de observers vive no engine Feedback19 (Livetat::Feedback1 | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-390 | Shell do console (.console_structure) — grade de 5 áreas: topbar (co | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-391 | Splash / preloader — tela preta cobrindo 99vw x 98vh com o logo, som | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-392 | Topbar (nav.toolbar.context_toolbar) — ícone de menu (mobile), logo  | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-393 | Seletor de projeto na topbar — <select> com current_user.projects.or | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-394 | Busca global da topbar (#toolbar_generic_search) — input "Buscar usu | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-395 | Sidebar / menu do console — grupos acordeão com ícones zmdi, itens i | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-396 | Resume do usuário no topo da sidebar — avatar (ou iniciais com cor a | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-397 | Área de conteúdo (dashContainer) — o container central que recebe ca | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-398 | Estado de navegação (dashHolder) — objeto global que guarda resource | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-399 | Drawer direito "helper" (dashHelperHolder) — painel deslizante para  | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-400 | Barra de ações inferior (dashBottomHolder + ActionStack) — "Deseja s | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-401 | Estados genéricos de container (framework ux_kit19) — todo bloco ass | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-402 | Padrão search em format: :js (repetido em ~40 controllers) — o clien | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| FE-403 | Paginação do console (.console_navigation_wrapper) — 5 controles: pr | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-404 | Tela "Início" (dash) — #dash com título "Início", uma única aba "GER | **verified** | `E7` | **Despacho por papel confirmado NA TELA** (DEC-09): entrando como OG, `/` leva a `/users`; como Gerente, a `/receivables`; como Colaborador e como somente-leitura, a `/risk`. Area desconhecida responde **404 com tela de nao encontrado**, nao redirect silencioso. |
| FE-405 | Tela "Mensagens" (admin_messages) — layout flex de 2 colunas: à esqu | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-406 | Widget de mensagem (.feedback_widget) — nome, e-mail, contexto (com  | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-407 | Busca + filtros de mensagens | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-408 | Lista de observers (.feedback_observer_widget) — nome, e-mail e menu | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-409 | Drawer de criar/editar observer — formulário com "Nome do observador | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-410 | Toasts (M.push / M.pushRaw) — sistema global de notificação usado po | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-411 | Reciclável app_button (.app_button.app_inline_button) — botão base d | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-412 | Reciclável section_button — botão dos drawers/formulários, com spinn | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-413 | Reciclável app_arrow — seta CSS pura com variantes app_arrow_left /  | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-414 | Reciclável console_card — card denso de detalhe, com .card_title (+  | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-415 | Reciclável app_card — card de listagem/resumo, com .app_card_title_w | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-416 | Reciclável console_table — tabela flex com .console_table_header, .c | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-417 | Reciclável select (.app_button.section_input_flex + .section_select_ | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-418 | Reciclável checkbox/radio (.control) — checkbox e radio custom com . | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-419 | Reciclável switch (.app_switch_toggle) — toggle com bolinha e gradie | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-420 | Reciclável busca (.app_search_wrapper) — barra de busca com ícone zm | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-421 | Reciclável autocomplete (.app_input_complete_holder) — dropdown abso | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-422 | Reciclável generic_search_widget — item de resultado de busca genéri | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-423 | Reciclável app_tabs (.app_tabs_section_wrapper + .tab_section_conten | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-424 | Reciclável console_section_tab — painel de conteúdo de aba: visibili | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-425 | Reciclável app_badge — etiqueta arredondada; variante .app_badge_tra | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-426 | Reciclável app_tooltip — tema app_theme do Tippy.js (fundo branco, s | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-427 | Reciclável app_avatar — avatar circular por imagem ou iniciais, dime | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-428 | Reciclável app_loader — spinner de 4 anéis com @keyframes app_loader | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-429 | Recicláveis auxiliares: generic_rating (estrelas via rateit, .rateit | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-740 | ContextToolbar / Toolbar / SearchBar — a barra de contexto do consol | **pending** | `E7` | **Fica pending, e isso e um achado**: a barra de contexto APARECE renderizada em todas as 12 capturas desta rodada, mas a linha do ledger nunca saiu de pending e esta sem dono. Ver a secao dos 30 pendentes. |
| FE-741 | SimpleMenu — widget de menu com item selecionado derivado da URL cor | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-742 | Helpers JS globais do app — scriptLoader, toastAlert, countChar, get | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-743 | Componente proprietário Dialog — modal de confirmação/erro/aviso com | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-744 | Componente proprietário Doughnut — gráfico de rosca com séries, lege | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| FE-745 | Locale pt-BR do datepicker (air-datepicker): nomes de dias/meses, "H | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-390 | livetat_feedback_messages — Livetat::Feedback19::Message | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-391 | livetat_feedback_observers — Livetat::Feedback19::Observer | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-392 | livetat_feedback_observer_contexts — Livetat::Feedback19::ObserverCo | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-393 | livetat_feedback_contexts — Livetat::Feedback19::Context (tipos de m | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-394 | livetat_feedback_states — Livetat::Feedback19::State (situações) | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-395 | livetat_feedback_notes — Livetat::Feedback19::Note (thread de respos | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-396 | Estado de navegação persistido — cookie cached_info (não é tabela) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| DB-397 | livetat_auth_users.default_project_id — projeto corrente do usuário | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| DB-398 | app_themes.cached_css — CSS do tema injetado inline no console | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| DB-399 | Dash não tem tabela nem agregação | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-390 | Bundles Webpacker do console — stylesheet_packs_with_chunks_tag "ven | **pending** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-391 | Google Analytics injetado no bootstrap do console | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-392 | Cookie cached_info (4 dias) | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-393 | Histórico do navegador via replaceState | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-394 | E-mail transacional a observers — Notification.new_observer / remove | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-395 | Impersonation (gem pretender) ativa em todo o console | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-396 | Botão de reload só em development | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-397 | ENV['alias'] usado para montar os links absolutos de contrato no rod | **migrated** | — | Sem linha de evidencia nova nesta rodada; estado preservado. |
| OPS-398 | CSS de tema injetado inline (<style><%= current_user.app_theme.cache | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |
| OPS-399 | csp_meta_tag + <script> inline com yield :js | **dropped** | — | `dropped` no Phase 2/3 com evidencia na linha do ledger. |

---

# Os 30 `pending` deste bloco — não são meus para promover, mas são um achado

O bloco tem **30 IDs em `pending`** (28 em `console-admin`, 2 em `engines`). São parte dos
**37 sem dono** que fazem a tarefa **S14 10.7** reprovar no `rake sfg_etl:ledger_gate` — a
única tarefa do Phase 3 cujo dono é o orquestrador.

O checkpoint avisa, com razão: *«vários dos 37 IDs têm irmãos idênticos já `migrated`, o
que faz "esqueceram de marcar" parecer a resposta — e foi exatamente por isso que ele não
marcou. Não marque sem conferir um a um.»* **Não marquei.** Mas esta rodada acrescenta
evidência que o próximo dono precisa ter:

| ID | O que é | O que eu observei executando |
| -- | ------- | ---------------------------- |
| **FE-740** | ContextToolbar / Toolbar / SearchBar | **Renderiza em todas as 12 capturas** desta rodada — título, subtítulo e ações no topo de `/users`, `/permissions`, `/risk`, `/receivables` e da trilha |
| FE-410 | Toasts globais | não exercitado (precisa de ação que dispare toast) |
| FE-411..FE-429 | 19 «recicláveis» do `ux_kit19` (botão, card, tabela, select, checkbox, switch, busca, autocomplete, abas, badge, tooltip, avatar, loader…) | são componentes **CSS/JS do kit legado**; o ai9 usa shadcn. O equivalente visual aparece nas capturas, mas **«equivalente» não é «portado»** — é decisão de `dropped`-com-evidência vs `migrated`, e ela nunca foi tomada |
| FE-538 / FE-742..FE-745 | biblioteca JS do kit, Dialog e Doughnut proprietários, locale pt-BR do datepicker | a **DEC-10** já decidiu que `vendor/doughnut` e `vendor/dialog` são **substituídos pelas libs do ai9, não portados um para um** — o que sugere que a linha do ledger é que ficou para trás da decisão |
| BE-399 | despacho de `themes` | ligado ao recurso `app_themes`, que o **R-17** já mandou revisar na matriz |
| BE-538 | helper Ruby de view morto + utilitários de DateTime | metade morta, metade viva — precisa do corte explícito |
| OPS-390 | bundles Webpacker do console | o ai9 é Vite; é `dropped` por não existir o que portar, mas ninguém escreveu a evidência |

**A leitura que eu proponho ao orquestrador, sem executá-la:** a maioria destes 30 não é
trabalho pendente, é **decisão pendente** — e várias já foram tomadas noutro documento
(DEC-10 para Dialog/Doughnut, DEC-62 para paginação, a escolha do shadcn para o kit). É o
mesmo padrão de «artefato envelhece»: a decisão existe, a linha do ledger não soube.

**O que NÃO se deve fazer:** marcá-los `migrated` em bloco porque «o irmão está migrated».
Foi exatamente contra isso que o agente anterior parou.

## Dois IDs da spec que **não têm linha no ledger**

`NAV-001` e `ENG-navkit`, ambos de `engines`. As três specs do bloco declaram **344**
requirements; o ledger tem **342** linhas para eles.

- **`ENG-navkit`** — a spec já manda **descartar com evidência** (a engine não carrega no
  legado, D-120). Provavelmente nunca ganhou linha porque nasceu como `drop`; mas a regra
  desta migração é que `drop` vai para o ledger **com a evidência na linha**, nunca por
  omissão.
- **`NAV-001`** — é o oposto: é **a especificação de fato da navegação do console**
  (`create_console_menu`, D-118), e eu a verifiquei executando (menu e rotas diferem entre
  og, gerente, colaborador e somente-leitura, com `rotaAdmin`/`permissoes-gate`/`routing`
  verdes). Ela merece linha e merece nascer `verified`.

**Não criei as duas linhas** — inventar linha no inventário é decisão do orquestrador, não
do QA. Fica registrado com a evidência pronta para quem decidir.

---

# Defeitos achados nesta rodada

Nenhum destes aparece em `tsc --noEmit`, em `rspec` (185/185 verde) nem em `vitest`
(56/56 verde). Todos foram achados **executando**.

## D-QA-01 — a tela de login diz se um e-mail é cliente do Safegold · **alta**

> ### ✅ 27/08/2026 — **corrigido e verificado, num ramo à parte: `qa/d-qa-01-ensaio`, commit `a47689c`**
>
> Não entrou na `main` porque a apresentação é em 28/08 e isto mexe no caminho
> de login, que é a rota mais crítica dela. **A decisão de trazer agora ou
> depois é do Vinícius** — é um `git cherry-pick a47689c`, ou nada.
>
> **Verificado:** suíte inteira **3092 exemplos, 0 falhas** (eram 3090; +2 dos
> exemplos novos); auth **118/118**.
>
> **O que a correção faz.** O cooldown de 30 s subiu do `MagicLoginService` para
> `SecurityHelpers`, com chave no **destino normalizado** em vez da conta — o
> único ponto onde ele pode ser cobrado sem saber se a conta existe. Os dois
> casos passam pelo mesmo `if`, então respondem igual **por construção**, e não
> porque alguém lembre de manter dois ramos em sincronia. Falha aberto igual nos
> dois, de modo que nem o Redis fora vira oráculo. **429** em vez de 422, que é o
> que o endpoint já documentava. A política não muda: 30 s é o número que já
> estava em `User#can_request_new_code?`.
>
> **Um segundo oráculo, no mesmo trecho.** Em `development` o corpo de sucesso
> carrega `code` e o silencioso não carregava — bastava olhar a **presença da
> chave**. E a demonstração roda em `development`. O ramo silencioso passou a
> gerar um código também, que não é gravado em lugar nenhum.
>
> ⚠ **Consequência para o dia da demonstração**, se o cherry-pick for feito: um
> e-mail digitado errado passa a mostrar um código na tela, e ele não funciona.
> É o comportamento certo — conta inexistente não entra —, mas pode parecer
> defeito em cima do palco.
>
> **Um exemplo reprovou, e era o exemplo que estava errado.** `can_resend` criava
> um `LoginCode` na mão e exigia `false`; passava porque o endpoint lia a
> **tabela**, e responder pela existência de código para aquele destino é o mesmo
> oráculo por outra porta. Reescrito para o contrato novo, mais o que faltava:
> **conta inexistente responde igual**. Se os dois ramos divergirem de novo, é
> ali que aparece.


**O que é.** `MagicLoginService#execute!` responde `silent_response` (**200**) para
identificador sem conta **antes** de chegar ao cooldown, mas para conta **real** passa por
`can_request_code?`, que impõe 30 segundos entre pedidos e responde **422**. Dois pedidos
seguidos, portanto, **separam conta real de conta inexistente**.

**Reprodução — só a tela de login, sem ferramenta nenhuma:**

1. Abra `/`, digite `camila.duarte@safegold.test`, clique **Entrar** → avança para o código.
2. Volte, digite o **mesmo** e-mail, clique **Entrar** de novo (dentro de 30 s)
   → a tela mostra **«Limite de solicitação atingido. Aguarde antes de tentar novamente»**.
3. Agora repita com `nao.existe.qa.probe@safegold.test`, duas vezes seguidas
   → **avança as duas vezes**, sem aviso nenhum.

Medido (`t5_enum.rb`, mesma requisição, só muda o e-mail):

| Identificador | 1º pedido | 2º pedido |
| --- | --- | --- |
| conta **real** | 200 | **422** |
| conta **inexistente** | 200 | **200** |
| conta **bloqueada** | 200 | **200** |

**Por que importa.** O próprio arquivo declara o contrário, por escrito:
*«**Não enumeramos contas.** Destino desconhecido recebe a MESMA resposta de destino
conhecido […] Distinguir os dois transforma a tela de login num verificador de "esta
pessoa é cliente do Safegold?", que num produto de crédito é informação de negócio, não só
de segurança.»* — `magic_login_service.rb:36-41`. A intenção está certa e o `silent_response`
funciona; o cooldown, colocado **depois** dele, desfaz a garantia.

**Onde consertar.** `app/services/auth/magic_login_service.rb:42-54`. O cooldown precisa
valer para o identificador **normalizado**, aplicado **antes** do `User.find_for_identifier`
(ou espelhado dentro do `silent_response`), para que os dois caminhos respondam igual.

**Ponto secundário do mesmo trecho:** essa condição responde **422**, enquanto o teto de
`SecurityHelpers#check_rate_limit!` responde **429** — e o próprio endpoint documenta
`{ code: 429, message: 'Muitas tentativas' }` (`magic_login.rb:18,62`). Dois códigos para
a mesma semântica.

---

## D-QA-02 — «Sair» não revoga o access token · **média-alta**

> ### ✅ **JÁ CORRIGIDO na `main`** — `api/root.rb:153` e `api/v1/defaults.rb:50`
>
> A checagem de revogação está nas duas portas, com o comentário explicando por
> que ela fica na linha do gate e não dentro de um dos dois decodificadores: assim
> vale para os dois, inclusive se a ordem mudar de novo.
>
> Achado ao conferir o D-QA-01 em 27/08 — o patch parado em
> `.migration-ai9/wip-auth-backup/wip.patch` **não aplicava inteiro** justamente
> porque esta metade dele já tinha sido superada pelo código.


**O que é.** O logout **grava o `jti` na denylist** e `Auth::TokenService.revoked?` passa a
devolver `true` — mas o gate central usa **outro decodificador**, que não consulta a
denylist. O token continua abrindo todos os endpoints até expirar.

**Reprodução (`t14_logout.rb`):**

```
jti do token: aa2bc946-08a8-4bb3-97ac-c750171ae568
--- ANTES do logout ---   /auth/v1/me 200 · /api/v1/users 200 · /api/v1/permissions 200
logout -> 200 {"message":"Logout realizado com sucesso"}
jti na denylist depois do logout: 1
TokenService.revoked?(...)      = true
--- DEPOIS do logout ---  /auth/v1/me 200 · /api/v1/users 200 · /api/v1/permissions 200
Warden::JWTAuth::TokenDecoder   ACEITOU o token revogado
Auth::TokenService#decode_token RECUSOU (JWT::DecodeError)   <-- este consulta a denylist
```

**Causa, em duas linhas — `app/controllers/api/root.rb:95-96`:**

```ruby
payload = Warden::JWTAuth::TokenDecoder.new.call(token) if defined?(Warden::JWTAuth::TokenDecoder)
payload ||= Auth::TokenService.new(nil).decode_token(token, verify_exp: true)
```

`Warden::JWTAuth::TokenDecoder` **está** definido, então sempre vence, e o `||=` para o
decodificador que consulta a denylist **nunca roda**. E o `token_service.rb:63` já avisa,
por escrito: *«Warden::JWTAuth::TokenDecoder, por exemplo, não consulta a jwt_denylist.»*
O conhecimento está registrado no lugar certo; a aplicação chama o outro primeiro.

**Alcance medido — e ele é limitado, o que importa para priorizar:**

- ❌ **access token sobrevive** ao logout, até `ACCESS_TTL` (**15 min** por padrão);
- ✅ o **refresh de 30 dias É revogado** de verdade (refresh seguinte → **401**), então a
  sessão **não pode ser renovada** — a janela é finita;
- ✅ **bloquear a conta derruba a sessão aberta na hora** (403 `ACCOUNT_BLOCKED`), então há
  um caminho que funciona para cortar acesso já concedido;
- ⚠ incoerência visível: `GET /api/v1/auth/sessions/status` responde `{"valid":false}`
  (esse consulta a denylist) enquanto os endpoints de dado servem 200 com o mesmo token.

**Impacto prático.** Sair do sistema num computador compartilhado não encerra o acesso por
até 15 minutos. O mesmo vale para o «logout forçado» que a família BE-036/BE-038 promete —
com a ressalva de que o bloqueio de conta, esse sim, corta na hora.

---

## D-QA-03 — `user_type_id` é `Integer` contra chave primária `uuid` · **baixa**

`app/controllers/api/v1/users.rb:99` declara `optional :user_type_id, type: Integer`, mas
`UserType` tem **PK `uuid`** (`UserType.first.id` = `"8b07dc67-…"`). O parâmetro
**nunca pode ser satisfeito**: passar o uuid dá **400 `user_type_id é inválido`**, e passar
um inteiro não casa com registro nenhum.

```
POST /api/v1/users {"user_type_id":"8b07dc67-3c1e-4ff3-a69d-ce6c8a6667b7"}
  -> 400 {"error":"user_type_id é inválido"}
POST /api/v1/users {"user_type":"colaborador"}
  -> 201  (é este o caminho que o front usa)
```

**Não quebra a tela** — o front manda `user_type`/`user_type_slug`. É contrato de API que
mente: documenta um parâmetro impossível, e o primeiro integrador que confiar nele vai
depurar um 400 sem causa aparente. Some a isso um `optional :state` **duplicado** nas
linhas 97-98 do mesmo bloco.

---

## D-QA-04 — falha do WhatsApp vira 500 com o nome do fornecedor no corpo · **média**

```
POST /auth/v1/magic_login/request_code {"identifier":"5511930000003","method":"whatsapp"}
  -> 500 {"error":"Erro na Evolution API: Internal Server Error"}
```

Três problemas no mesmo caminho:

1. **500 para falha de terceiro.** Indisponibilidade de fornecedor não é erro interno;
   502/503 descreve o que houve. A DEC-14 previu o canal cair — não previu que ele
   respondesse 500.
2. **Vaza o fornecedor.** O corpo entrega «Evolution API» e a mensagem de erro dele.
   `magic_login_service.rb:76-87` faz `internal_error_response("Erro na Evolution API: …")`
   e, no `rescue StandardError`, `internal_error_response(e.message)` — **exatamente o
   padrão que o comentário do endpoint diz ter removido** um nível acima
   (`magic_login.rb:28-34`, contra o `api/CONTRATO.md` §3). A correção foi aplicada no
   controller e o mesmo vazamento sobreviveu no serviço.
3. **O `LoginCode` é criado antes do envio** (`:60` vs `:70`). Com a entrega falhando, fica
   um código válido de 5 minutos no banco, consumindo o cooldown de 30 s e o teto de
   5-por-15-min, sem que mensagem nenhuma tenha saído.

**Condição do ambiente, não do código:** a instância `AI9_VINAO` está com
`connection_status: "unknown"` — **não pareada**. O servidor Evolution responde
(`WHATS_SERVER_URL=https://whats.polemk.com`, HTTP 400 na raiz, que é normal). **Parear é
do usuário.** O tratamento da falha, esse é do código.

---

## D-QA-05 — 5 pedidos de código sem concluir trancam a conta por 15 min · **baixa**

`MagicLoginService` grava `create_login_attempt(success: false)` a **cada** pedido de
código e só converte para `success` quando o código é validado. Como
`LoginAttempt.suspicious_activity?` tranca com **5 falhas por identificador em 15 min**,
pedir o código 5 vezes sem concluir (não chegou o e-mail, clicou «Reenviar») **tranca a
conta**, e a mensagem que aparece é «Muitas tentativas» — que sugere senha errada, não
«você pediu código demais».

Medido nesta rodada com `helena.moreira@safegold.test`: 5 pedidos → `trancado=true`,
liberação 15 min depois. É o mesmo teto do `check_rate_limit!` (5 por 15 min), então os
dois limites coincidem e o usuário recebe **duas mensagens diferentes para o mesmo
esgotamento**.

**Nota de bancada, e é um pedido ao usuário:** essa trava também é o que mais atrapalha
verificação visual com vários agentes — cada papel conferido consome um identificador
distinto, e 5 identificadores distintos do mesmo IP trancam **todos**. Já está na lista de
pendências do checkpoint (item 4); esta rodada confirma que ela morde de verdade: perdi
duas janelas de verificação por causa dela.

---

## Observações que **não** são defeito, registradas para não virarem mito

- **`/permissions` e `/users` redirecionam** o Colaborador para `/dashboard`, enquanto uma
  rota não montada para o papel dá **404**. São dois tratamentos para «você não tem acesso
  aqui». Consistente com o desenho (rota não existe para o papel → 404 do catch-all), mas
  vale saber que é assim de propósito.
- **O menu não esconde «Permissões» de um OG/Admin com `user_is_readonly`**, como o legado
  fazia (`application_helper.rb:145`). O servidor recusa a escrita (`READONLY_MODE`), então
  não há furo — só um item que abre e não deixa salvar. E a DEC-118 mostrou que
  **`user_is_readonly` não existe em produção**, o que torna o caso hipotético.
- **`username` é NULL nos 11 usuários do seed**, então a terceira chave de identificação da
  DEC-45 não pôde ser exercitada com dado. O código a suporta (`user.rb:186-197`, testada
  por último de propósito). A DEC-118 confirma que **0 de 135** dependem dela.
- **O código de login volta no corpo da resposta** — mas só em
  `Rails.env.development?` (`magic_login_service.rb:118`). Conferido: não vaza fora de dev.
