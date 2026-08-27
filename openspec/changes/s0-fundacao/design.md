# Design: S0 — Fundação

> **Este documento não repete o mapa.** As 77 linhas item-a-item (estratégia, equivalente
> ai9, o que muda, risco) estão em `.migration-ai9/map/auth-admin.md` §2.1–§2.14 e em
> `.migration-ai9/map/projects-cadastros.md` §2.5, §2.9 e §0.6. Aqui está **só o que é
> decisão de desenho desta fatia**: onde cada grupo aterrissa no repo, os dois contratos
> transversais aplicados, e as escolhas que tomei onde os dois mapas divergiam.

## 1. Contrato C1 — escopo por projeto, no endpoint

Desenho normativo: `.migration-ai9/map/projects-cadastros.md` **§0.6** (as quatro peças, a
forma canônica e as cinco regras). **Adotado sem alteração.** O que esta fatia acrescenta é
a execução das duas condições que o bloco `auth-admin` exigiu (`map/auth-admin.md` **DC-08**)
e que o `migration-map.md` promoveu a contrato:

| # | Condição | Consequência no código |
| - | -------- | ---------------------- |
| 1 | O valor **armazenado** em `users.current_project_id` é revalidado contra `memberships` **a cada request** — não só o header `X-Project-Id` | `current_project!` nunca confia na coluna: ela é uma preferência, a verdade é a linha de `memberships`. Membership revogada deixa de valer na requisição seguinte, sem precisar de logout |
| 2 | Projeto **inexistente** e projeto **sem participação** respondem **o mesmo status (404)** | Distinguir 403 de 404 transforma o helper num **oráculo de existência de ids de projeto**. Um Colaborador de um projeto poderia enumerar os ids de todos os outros |

**Por que não `default_scope`** (recusado no §0.6, repetido aqui porque é a tentação óbvia
de quem for implementar): vaza para `unscoped`, quebra `joins`/`includes` em silêncio,
contamina job/seed/rake que **legitimamente** cruzam projetos, e torna o escopo **invisível
na leitura**. O legado errou exatamente aí — sempre que chegava um id por parâmetro, o
filtro de projeto era descartado (família D-01/D-16/D-29/D-76/D-100).

A forma canônica é a do §0.6 e **não se inventa outra**:

```ruby
project = current_project!                      # 404 se não houver participação
scope   = Receivable.for_project(project)       # ProjectScoped
scope   = scope.where(id: params[:receivable_id]) if params[:receivable_id]
# o project_id que vier no corpo da requisição é SEMPRE ignorado
```

Onde isso mora: `backend/app/controllers/api/v1/controller_helpers.rb` (o helper, ao lado de
`require_og!`/`restrict_visitor_access!`, que já rodam em todo `/api/v1/*` por
`api/v1/base.rb:12-14`) e `backend/app/models/concerns/project_scoped.rb` — **o diretório
`concerns/` não existe hoje e é criado nesta fatia**.

Job, seed e rake **não** chamam `current_project!`: recebem `project_id` como argumento
explícito (regra 5 do §0.6). É por isso que o escopo não pode ser `default_scope`.

## 2. Contrato C3 — a escala de hierarquia é invertida

| Sistema | Convenção | Evidência |
| ------- | --------- | --------- |
| Legado `sfg` | **maior = mais poder** | `../sfg/db/seeds.rb:40-95`: OG 1111 > Admin 998 > Gerente 888 > Colaborador 799 |
| Base ai9 | **menor = mais poder** | `backend/app/models/user_type.rb:38-41` (OG `hierarchy_level: 1`) e os scopes em `:19-21` — `higher_than` é `where('hierarchy_level < ?', level)` |

**Adotada a convenção do ai9** (Princípio 6b: `UserType` é peça da base compartilhada e
outros sistemas dependem desses scopes). De-para do ETL: **tabela explícita, nunca fórmula**
— OG→1, Admin→2, Gerente→3, Colaborador→4, papel vazio (`""`, D-36)→4 **e sai na lista de
exceções** para revisão humana. Qualquer aritmética sobrevive a um valor inesperado e produz
um nível plausível e errado; a tabela **falha alto**, que é o comportamento desejado.

**Como isso aparece nos testes desta fatia (não é opcional):** as decisões DEC-18.2 e
DEC-18.3 dependem inteiramente do **sinal** dessa comparação. Inverter o sinal dá poder de
OG a um Colaborador — e **passa** em qualquer teste que verifique só que "a trava existe",
porque ela existe: está apontando para o lado errado. Por isso toda tarefa de teste de
hierarquia em `tasks.md` exige o par:

- Admin **NÃO** edita ability de OG · Admin **EDITA** ability de Colaborador;
- o filtro de usuários de um Gerente **NÃO** devolve OG nem Admin · **devolve** Colaborador.

## 3. Autorização — o achado que rebaixa a peça central de `build` para `adapt`

`user_is_readonly` (a única das 17 abilities que sobrevive, DEC-18 #6) **não precisa de
mecanismo novo**: `restrict_visitor_access!`
(`controller_helpers.rb:44-53`) já roda em todo `/api/v1/*` e já nega todo verbo que não
seja GET/HEAD, e o front já trata o 403 com `code` (`frontend/src/lib/api/client.ts:93-95`).
A tarefa é **generalizar o predicado**, não construir o gate (`map/auth-admin.md` DC-04).

O resto da matriz vira `authorize!(recurso, ação)` no mesmo arquivo, alimentado por uma
tabela declarativa dos recursos × 4 papéis derivada de `.migration-ai9/authorization-matrix.md`
(contrato aprovado, DEC-18). **Nenhum endpoint decide autorização sozinho.**

Permissão é **consulta**, nunca cópia: papel → defaults; `user_permissions` → override com
`granted_at`/`revoked_at`. É assim que o **D-35** (alterar a permissão do papel não
propagava para quem já existia, porque a `Role` clonava as 17 abilities na atribuição)
**desaparece por construção** — não por correção.

**Armadilha registrada (DC-09):** `user_is_readonly` tira C/U/D, mas **não pode** bloquear o
aceite dos Termos pelo próprio usuário — senão o readonly nunca aceita e fica trancado fora
do sistema.

## 4. Decisões que tomei porque os dois mapas divergiam

| # | Divergência | Decisão | Razão |
| - | ----------- | ------- | ----- |
| **DS0-1** | Trilha de auditoria: `auth-admin` §4 manda dar o primeiro produtor a `permission_audit_logs` (tabela que já existe na base, formato certo, **zero produtores**); `projects` OPS-086 manda criar uma trilha genérica `AuditEvent` | **Uma trilha só: `AuditEvent` genérica**, com o **formato** de `permission_audit_logs` como molde (`actor_type`/`actor_id`/`reason`/`metadata`). Concessão/revogação de permissão, troca de papel e impersonation gravam nela. `permission_audit_logs` **continua sem produtor** e vira linha em `upstream-flags.md` | Duas trilhas para o mesmo tipo de ato administrativo é exatamente o que os contratos transversais existem para evitar. Escolher a genérica é o que permite que renegociação, risco e recebíveis auditem no mesmo lugar sem uma tabela por domínio |
| **DS0-2** | A tabela `projects` é pré-requisito de `memberships`, mas o CRUD de projeto é da fatia S4 | **`projects` nasce em S0 como esquema** (DB-080); endpoints, telas e efeitos colaterais ficam em S4 | Sem a tabela não há FK de membership, e sem membership não há escopo — S0 travaria a si mesma. Separar esquema de produto mantém a fronteira legível no ledger |
| **DS0-3** | Paginação aparece em três IDs (FE-014 em S1, FE-053 em S0, FE-403 em S2), todos apontando para `components/ui/Pagination.tsx` | **S0 constrói o componente uma vez** (FE-053); S1 e S2 o **consomem** e fecham os seus IDs pelo consumo | Princípio 11. Três telas construindo a mesma paginação é como se chega a três comportamentos de "próxima página" |
| **DS0-4** | O seed de papéis do ai9 (`UserType.seed_default_types!`, `user_type.rb:38-41`) traz `OG/client/free/visitor`, que **não** são os papéis do Safegold | **Acrescentar** os 4 papéis do Safegold (OG, Admin, Gerente, Colaborador) sem remover os da base | Princípio 6b: `UserType` é peça compartilhada. `visitor` continua existindo porque `restrict_visitor_access!` depende dele |

## 5. Onde cada grupo aterrissa

| Grupo | Camada | Arquivos-alvo no repo |
| ----- | ------ | --------------------- |
| Papéis e permissões | dados | `db/migrate/**` (`permissions`, `user_permissions`), `db/seeds/` (seed **idempotente e versionado** — OPS-507; é o **primeiro** seed de `permissions` da base) |
| Papéis e permissões | backend | `models/{user_type,permission,user_permission}.rb`, `api/v1/{permissions,user_types}.rb`, `controller_helpers.rb` |
| Projeto e participação | dados | `db/migrate/**` (`projects`, `memberships`, `users.current_project_id`) |
| Projeto e participação | backend | `models/concerns/project_scoped.rb` (**novo diretório**), `controller_helpers.rb#current_project!`, `api/v1/memberships.rb` + `MembershipService` |
| Infra transversal | backend | `models/audit_event.rb` + `api/v1/audit_events.rb`, `ProjectProgressChannel`, fila em `config/sidekiq.yml` (já existe, inclusive `_low_priority`) |
| Primitivos | frontend | `components/ui/**` (novos: `Checkbox`, `RadioGroup`, `Select`, `Spinner`, `DatePicker`, `Pagination`, `DataTable`, `MoneyInput`, `PercentInput`, `EmptyState`/`ErrorState`/`LoadingState`, `AsyncSection`, `ResultItem`), `hooks/useDebouncedSearch.ts`, `hooks/useJobProgress.ts`, `lib/utils/` |

**Herança obrigatória de todo primitivo** (§0.3 do mapa de `projects`): tokens de marca
Safegold em **light e dark**, `MOB` para as views estreitas, e nada de dependência nova sem
necessidade (o `DatePicker` pt-BR é crítico — quase toda tela financeira filtra por período).

## 6. O que **não** se faz aqui (Princípio 6b)

Achados da base que **não** viram tarefa desta fatia — vão para `.migration-ai9/upstream-flags.md`:
`assets_proxy_controller` sem sanitização de caminho (U1), `PermissionsChannel` sem escopo
por dono (U2), `ApplicationCable::Connection` que nunca recusa conexão (U3), `Rack::Attack`
nunca inserido explicitamente (U8), `permissions.is_active` não honrado (U9), `TokenService`
com segredo de fallback (U14), access token sem `jti` (U15). **Exceção:** onde a fatia
**precisa** do comportamento correto para cumprir o próprio contrato (o 403 de readonly, o
404 uniforme do escopo), a correção é tarefa — e está marcada como tal.
