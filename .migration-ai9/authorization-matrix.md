# Matriz de autorizacao — Safegold no ai9

> **Status: APROVADA em 24/08/2026 (DEC-18).** As 7 decisoes que faltavam foram
> respondidas pelo Vinicius; 3 delas **alteraram** a minha proposta e estao marcadas
> abaixo. Este documento deixou de ser proposta e passou a ser **contrato**: e dele que
> nascem o seed versionado de RoleTypes e as policies declarativas por rota.
>
> **Unica pendencia: Q-A1** (abilities editadas a mao em producao) — **adiada para depois
> da venda por decisao do usuario (DEC-19)**. Nao bloqueia a demo nem a implementacao da
> matriz: o que fica adiado e so a **conferencia contra o banco real** antes de ligar as
> restricoes em producao. **Volta como item obrigatorio do runbook de cutover.**

## Como esta matriz foi derivada

Tres fontes, nesta ordem de forca probatoria:

| # | Fonte | Arquivo | O que prova |
| - | ----- | ------- | ----------- |
| 1 | `create_console_menu` | `..\sfg\app\helpers\application_helper.rb:100-172` | **Onde** cada papel entra. E a especificacao de fato da navegacao (**D-118**): 6 grupos, gate por projeto (`current_user.projects.count == 0`), por papel (`og?`/`admin?`/`manager?`), por permissao (`may?("user_is_readonly")`) e 4 itens `locked: true` |
| 2 | Gates nas views ERB (`_body.html.erb`) | `..\sfg\app\views\pub\console\parts\*\_body.html.erb` | **O que** cada papel faz na tela — botao de criar/editar/remover. Hoje e a **unica** autorizacao existente (**D-23**) |
| 3 | As 17 abilities + os seeds de RoleType | `..\sfg\app\decorators\models\ability_factory_decorator.rb:1-35`, `..\sfg\db\seeds.rb:33-95`, `..\sfg\engines\auth19\db\seeds.rb:9-90` | Quais abilities existem e **que valor cada RoleType recebe**. Isto e evidencia forte e foi uma descoberta: apesar do DEC-04 nao ter o dump de `livetat_auth_role_types`, os **seeds versionados reconstroem a tabela inteira** |

**Descoberta que muda o DEC-04 (parcialmente).** O DEC-04 registrou que a hierarquia de
papeis teria de ser inferida por nao existir o dump de `livetat_auth_role_types`. Isso e
verdade para o **estado atual do banco de producao**, mas **nao** para a intencao do
codigo: `db/seeds.rb:33-95` e `engines/auth19/db/seeds.rb` escrevem nome, `hierarchy` e
os 17 valores de ability de cada RoleType, linha a linha. Entao a coluna "que abilities
cada papel tem" e **evidencia**, nao inferencia. O que continua inferido e (a) se
producao rodou esses seeds, e (b) se alguem editou abilities pela tela de Permissoes
depois disso — que e editavel em runtime e **nao deixa rastro**.

**O que e evidencia vs o que e inferencia nesta matriz:**

- **Evidencia** — a existencia dos 4 papeis e seus nomes literais; os 17 nomes de
  ability; o valor de cada ability por papel nos seeds; que grupo de menu cada papel ve;
  que botao cada papel ve em cada tela; que **nenhum** controller checa papel.
- **Inferencia** (marcada **[inf]** em cada linha) — traduzir "ve o botao de criar" em
  "pode `POST`"; deduzir acesso de **leitura** a recursos que nao aparecem no menu mas
  cujos dados a tela do usuario consome (dropdowns); e o que fazer com os 4 itens
  `locked`.
- **Decidido** — a secao das 8 decisoes, agora com o veredito do usuario (DEC-18).

---

## Papeis

Os quatro papeis sao constantes literais em `..\sfg\app\decorators\models\user_decorator.rb:24-30`:

```ruby
mattr_accessor :ADMIN, :OG, :MANAGER, :COLAB
class_variable_set('@@OG',      "OG")
class_variable_set('@@ADMIN',   "Admin")
class_variable_set('@@MANAGER', "Gerente")
class_variable_set('@@COLAB',   "Colaborador")
```

| Papel | De onde veio | O que significa | Evidencia |
| ----- | ------------ | --------------- | --------- |
| **OG** (`"OG"`, hierarchy 1111) | Seed da engine, mantido pelo app | Super-usuario da Livetat (fornecedor), nao do cliente. **E o unico que enxerga o proprio RoleType OG** na tela de Permissoes e o unico que lista todos os RoleTypes no filtro de usuarios. `dash` o manda para `users` | `engines\auth19\db\seeds.rb:9-29`; `user_decorator.rb:153-155,166-176`; `pub\permissions_controller.rb:17-21`; `views\...\dash\_body.js.erb:8-9` |
| **Admin** (`"Admin"`, hierarchy 998) | `db/seeds.rb:40-60` (sobrescreve o 999 da engine) | Administrador do cliente. **Todas as 12 abilities condicionais = 1** e todos os limites em 9999. Ve os grupos Cadastro **e** Admin | `db\seeds.rb:40-60`; `application_helper.rb:139,166`; `user_decorator.rb:149-151` |
| **Gerente** (`"Gerente"`, hierarchy 888) | `db/seeds.rb:62-80` | Gestor operacional. Tem 10 das 12 condicionais — **nao tem `may_create_users` nem `may_delete_users`**, mas tem `may_invite_users`. Ve o grupo Cadastro, **nao** ve o grupo Admin | `db\seeds.rb:62-80`; `application_helper.rb:139,166` |
| **Colaborador** (`"Colaborador"`, hierarchy 799) | `db/seeds.rb:82-95` | Usuario final por projeto. Tem 4 condicionais: `create/modify/read_private_entries` + `read_public_entries`. **Nao tem `delete_private_entries` nem nenhuma ability de usuarios.** Nao ve Cadastro nem Admin. Unico papel cujo `projects_for_filter` retorna so os proprios projetos | `db\seeds.rb:82-95`; `user_decorator.rb:156-158,178-185` |
| `user_is_readonly` | **Nao e papel** — e a 17a ability, um modificador ortogonal | Quando `= 1`, some todo botao de criar/editar/remover em ~30 telas e some o item "Permissoes" do menu. Os seeds setam `0` para Admin, Gerente e Colaborador | `ability_factory_decorator.rb:30`; `db\seeds.rb:55,75,90,341-353`; `application_helper.rb:145` |

### Papeis fantasma (D-36) — registro

`engines/auth19/db/seeds.rb` cria quatro RoleTypes: `OG`, `Admin`, `Manager`, `Visitor`.
`db/seeds.rb:35-37` **destroi tres deles** (`Admin`, `Manager`, `Visitor`) e recria
`Admin`/`Gerente`/`Colaborador` com os nomes do SFG.

Ao mesmo tempo, a configuracao aponta para nomes destruidos:

| Config | Valor | Onde | Consequencia |
| ------ | ----- | ---- | ------------ |
| `default_role_type` | `""` (**vazio**, nao `"Visitor"`) | `..\sfg\config\application.rb:65` | O app **sobrescreve** o default `"Visitor"` da engine (`engines\auth19\lib\livetat\auth\configuration.rb:53`) por string vazia. Usuario sem `role_type` explicito fica com papel `""` — nao casa com nenhum `og?/admin?/manager?/colab?`, entao cai no ramo "demais" de todo gate |
| `minimal_type_to_sign_up_through_web` | `"Admin"` (**nao** `"Manager"`) | `..\sfg\config\application.rb:84` | O app sobrescreve o default `"Manager"` da engine (`engines\auth_ux19\lib\livetat\auth_ux19\configuration.rb:37`). **Este e o D-39**: `sessions_controller.rb:24` faz `RoleType.where(name: config).first.hierarchy` — com `"Admin"` o RoleType **existe** (recriado no seed do app), entao **nao levanta `NoMethodError`**; ele simplesmente autoriza cadastro web ate a hierarquia 998 |

**Correcao ao D-36:** o defeito previa `NoMethodError` no corte de hierarquia. Na
configuracao real do SFG isso **nao acontece** — `"Admin"` resolve. O `NoMethodError`
so ocorreria com o default da engine (`"Manager"`, destruido no `seeds.rb:36`). Ou seja:
o D-36 e real como inconsistencia de configuracao, mas o sintoma previsto esta errado; o
sintoma verdadeiro e o **D-39** (cadastro web ate Admin). Vale corrigir a ficha do D-36.

> **Nota sobre `should_perform_user_seed = false`** (`db/seeds.rb:2`): o bloco que
> destroi/recria os RoleTypes esta **desligado** hoje. Ja o `should_update_abilities =
> true` (`db/seeds.rb:20`, executado em `:341-359`) **esta ligado** e faz
> `RoleType.where(name: ...).first` **sem guarda de nil** para Admin/Gerente/Colaborador —
> ou seja, num banco onde o seed de usuarios nunca rodou, `db:seed` quebra com
> `NoMethodError`. Isso e evidencia de que o seed de usuarios **ja rodou** em producao
> (senao o seed atual nao completaria), o que reforca a confianca na tabela de abilities
> acima.

---

## Matriz recurso x papel

**Legenda.** `C`/`R`/`U`/`D` = criar/ler/atualizar/remover. `-` = nenhum acesso.
`R*` = leitura **inferida** (recurso fora do menu, mas a tela do papel depende do dado).
Coluna `user_is_readonly`: o efeito do modificador **sobre o papel que ja tem acesso**.
Coluna `Escopo`: `projeto` = filtrado por `default_project` / membership (DEC-07);
`global` = catalogo compartilhado; `proprio` = so o registro do proprio usuario.

Em **todas** as linhas, a coluna "demais" e o Colaborador (e o papel `""` do D-36).
Em **todas** as linhas, o estado de hoje e o mesmo: **CRUD total para qualquer sessao
autenticada**, porque nenhum controller checa nada (D-23/D-34). A matriz abaixo e o
**alvo aprovado**; o delta em relacao a hoje esta na secao de divergencias.

### Grupo "Inicio" — sem gate

| Recurso | og | admin | manager | demais | user_is_readonly | Escopo | Evidencia (arquivo:linha) |
| ------- | -- | ----- | ------- | ------ | ---------------- | ------ | ------------------------- |
| `dash` | R | R | R | R | sem efeito | proprio | `application_helper.rb:103` (grupo sem gate); destino por papel em `views\pub\console\parts\dash\_body.js.erb:8-22` |

### Grupo "Gestao" — gate `projects.count > 0`, sem gate de papel

Todos os quatro papeis entram, desde que tenham ao menos um projeto.
Evidencia do grupo: `application_helper.rb:105-107`.

| Recurso | og | admin | manager | demais | user_is_readonly | Escopo | Evidencia (arquivo:linha) |
| ------- | -- | ----- | ------- | ------ | ---------------- | ------ | ------------------------- |
| `risk` (Controle de Risco) | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:109` |
| `availability` (Painel de Disponibilidade) | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:111` tem `locked: true`, que **nunca funcionou** (D-90). **DEC-15.1: recurso VIVO — nasce HABILITADO** |
| `receivables` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:112`; gate de botao em `views\...\receivables\_body.html.erb:16` e `list\_widget.html.erb:1,3,45` |
| `renegotiations` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:113` |
| `renegotiation_installments` / `_payments` / `_attachments` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | Sub-recursos de `renegotiations`; sem item de menu proprio — herdam o gate do pai **[inf]** |
| `indicator_entries` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:114` |
| `risk_operations` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:115` |
| `risk_operation_extensions` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | Sub-recurso de `risk_operations` **[inf]** |
| `risk_entries` / `risk_movements` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | Sub-recursos de `risk` **[inf]**; ver Q-07 (D-99) |
| `structured_operations` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:116` |
| `receivable_taxes` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | Sub-recurso de `receivables` **[inf]** |

### Grupo "Projeto" — gate `projects.count > 0`, sem gate de papel

Evidencia do grupo: `application_helper.rb:121-123`.

| Recurso | og | admin | manager | demais | user_is_readonly | Escopo | Evidencia (arquivo:linha) |
| ------- | -- | ----- | ------- | ------ | ---------------- | ------ | ------------------------- |
| `charges` (Cobrancas) | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:127` tem `locked: true` inoperante (D-90). **DEC-15.1: VIVO — nasce HABILITADO** |
| `project_availabilities` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:128` tem `locked: true` inoperante (D-90); gates em `views\...\project_availabilities\_body.html.erb:6` e `list\_widget.html.erb:44,53,57`. **DEC-15.1: VIVO — nasce HABILITADO** |
| `availability_entries` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | Sub-recurso de `project_availabilities` **[inf]** |
| `companies` (Empresas) | CRUD | CRUD | CRUD | CRUD | tira C/U/D | **projeto** | `application_helper.rb:129`; escopo por DEC-07 |
| `providers` (Fornecedores) | CRUD | CRUD | CRUD | CRUD | tira C/U/D | **projeto** | `application_helper.rb:130`; escopo por DEC-07 |
| `project_guarantees` (Garantias) | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:131`; gates em `views\...\project_guarantees\_body.html.erb:17`, `list\_widget.html.erb:1,3,20` |
| `indicator_connections` (Indicadores especificos) | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:132`; gates em `views\...\indicator_connections\_body.html.erb:7`, `list\_widget.html.erb:17,27,32` |
| `project_indicator_connections` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | Controller irmao de `indicator_connections` **[inf]** |
| `project_to_carrier_connections` | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | Liga projeto a catalogo global de portadores **[inf]** |
| `risk_controls` (Limites) | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:133` |
| `remunerations` (Remuneracoes) | CRUD | CRUD | CRUD | CRUD | tira C/U/D | projeto | `application_helper.rb:134`; **gate duplo** — `views\...\remunerations\_body.html.erb:9` (readonly) **e** `:10` (og/admin/manager). Ver decisao **#4** |

### Grupo "Cadastro" — gate `og? || admin? || manager?`

Evidencia do grupo: `application_helper.rb:139-141`. O Colaborador **nao ve nenhum
item deste grupo**. As linhas `R*` na coluna "demais" foram **aprovadas** pela decisao
**#1** (DEC-18.4).

| Recurso | og | admin | manager | demais | user_is_readonly | Escopo | Evidencia (arquivo:linha) |
| ------- | -- | ----- | ------- | ------ | ---------------- | ------ | ------------------------- |
| `projects` (Projetos) | CRUD | CRUD | CRUD | R (so os seus) | tira C/U/D | global (lista) / projeto (detalhe) | `application_helper.rb:142`; gates em `views\...\projects\_body.html.erb:11`, `_body.js.erb:114`, `list\_widget.html.erb:41`, `detail\tabs\_tab_geral.html.erb:114`; escopo em `user_decorator.rb:178-185` (`projects_for_filter`: colab ve so os seus, os outros veem `Project.all`) |
| `memberships` | CRUD | CRUD | CRUD | R* | tira C/U/D | projeto | **DEC-18.5 + DEC-15.2.** Sem item de menu; vive na aba de detalhe do projeto. `views\...\projects\detail\memberships\list\_widget.html.erb:19,23`; `pub\memberships_controller.rb` (zero gates — D-34). As 3 condicoes da view viram **regra de servidor**: nao-readonly, nao remove o dono (`project.user_id`), nao remove a si mesmo. `:id` sai do `permit` |
| `wallets` (Carteiras) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | `application_helper.rb:143`; gate de botao em `views\...\wallets\_body.html.erb:11` |
| `users` (Contas) | CRUD | CRUD | **R** | - | tira C/U/D | global (filtrado por hierarquia) | `application_helper.rb:144` (menu: og/admin/manager) **mas** `views\...\users\detail\_body.html.erb:22`, `detail\_body.js.erb:8` e `helper\_body.html.erb:18` gatam as acoes em **`og? \|\| admin?`** apenas. `list\_widget.html.erb:44` deixa o Gerente ver a lista. Filtro por hierarquia em `user_decorator.rb:166-176`. Ver decisao **#3** |
| `carrier_groups` (Grupos de Portadores) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | **global** | `application_helper.rb:145`; gates em `views\...\carrier_groups\_body.html.erb:10,11` e `list\_widget.html.erb:9,13`; escopo global por DEC-07 |
| `carriers` (Portadores) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | **global** | `application_helper.rb:151`; gate em `views\...\carriers\_body.html.erb:11`; escopo global por DEC-07 |
| `segments` (Segmentos) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | **global** | `application_helper.rb:152`; gate em `views\...\segments\_body.html.erb:11` |
| `sub_segments` (Subsegmentos) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | **global** | `application_helper.rb:153`; gates em `views\...\sub_segments\_body.html.erb:10,11` e `list\_widget.html.erb:13,18` |
| `indicators` (Indicadores) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | `application_helper.rb:146`; gate em `views\...\indicators\_body.html.erb:11` |
| `availability_templates` (Padroes de Disponibilidade) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | `application_helper.rb:148` tem `locked: true` inoperante (D-90); gate em `views\...\availability_templates\_body.html.erb:12`. **DEC-15.1: VIVO — nasce HABILITADO**; `R*` ao Colaborador por DEC-18.4 (o formulario de `project_availabilities` consome o padrao) |
| `permissions` (Permissoes) | **CRUD** | **CRUD, so RoleTypes de hierarquia inferior** | **-** | - | **remove do menu** | global | **DEC-18.2.** `application_helper.rb:149-150`; `pub\permissions_controller.rb:17-21` (tratamento especial do og). A trava usa `RoleType.inferior_role_types` (`engines\auth19\app\models\livetat\auth\role_type.rb:16-25`). **Exige corrigir o D-34 junto** — hoje `fetch_permission` (`:55-57`) descarta o `:id` do usuario, o que tornaria a trava contornavel por URL |
| `movement_kinds` (Tipos de Movimentacao) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | `application_helper.rb:154`; gate em `views\...\movement_kinds\_body.html.erb:12` |
| `receivable_kinds` (Tipos de Recebiveis) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | `application_helper.rb:155`; gate em `views\...\receivable_kinds\_body.html.erb:11` |
| `resource_sources` (Tipos de Recursos) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | `application_helper.rb:156`; gate em `views\...\resource_sources\_body.html.erb:11` |
| `risk_operation_types` (Tipos de Limite) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | `application_helper.rb:157`; gates em `views\...\risk_operation_types\_body.html.erb:10,11` e `list\_widget.html.erb:12,16` |
| `structured_operation_types` (Tipos de OP Estruturada) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | `application_helper.rb:158`; gate em `views\...\structured_operation_types\_body.html.erb:11` |
| `risk_movement_types` (Movimentacoes de Risco) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | `application_helper.rb:159`; gate em `views\...\risk_movement_types\_body.html.erb:11` |
| `project_guarantee_types` (Tipos de garantia) | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | `application_helper.rb:160`; gate em `views\...\project_guarantee_types\_body.html.erb:11` |
| `resource_kinds` | CRUD | CRUD | CRUD | **R\*** | tira C/U/D | global | **Fora do menu** (item nunca adicionado em `create_console_menu`) mas a tela existe com o gate og/admin/manager: `views\...\resource_kinds\_body.html.erb:10`. Ver Q-07 |

### Grupo "Admin" — gate `og? || admin?`

Evidencia do grupo: `application_helper.rb:166-168`. O Gerente **nao** entra aqui.

| Recurso | og | admin | manager | demais | user_is_readonly | Escopo | Evidencia (arquivo:linha) |
| ------- | -- | ----- | ------- | ------ | ---------------- | ------ | ------------------------- |
| `help_items` (Central de ajuda) | CRUD | CRUD | - | R* | tira C/U/D | global | `application_helper.rb:167` |
| `help_categories` / `help_groups` | CRUD | CRUD | - | R* | tira C/U/D | global | Sub-recursos de `help_items`, sem item de menu **[inf]** |
| `admin_messages` | CRUD | CRUD | - | R* | tira C/U/D | global | **Fora do menu**; nome e ausencia de tela publica indicam area administrativa **[inf]** |

### Grupo "Perfil" e "Ajuda" — sem gate

Evidencia: `application_helper.rb:171-175`.

| Recurso | og | admin | manager | demais | user_is_readonly | Escopo | Evidencia (arquivo:linha) |
| ------- | -- | ----- | ------- | ------ | ---------------- | ------ | ------------------------- |
| `my_account` | RU | RU | RU | RU | tira U | **proprio** | `application_helper.rb:172-173` |
| `faq` / `help` | R | R | R | R | sem efeito | global | `application_helper.rb:175` |
| `contracts` (termos / privacidade) | R | R | R | R | sem efeito | global | `views\pub\console\base\menu\_container.html.erb:37,40` (links publicos); aceite em `db\seeds.rb:113-160` |
| `contract_versions` (publicar versao) | CRUD | CRUD | - | - | tira C/U/D | global | **DEC-38, recurso NOVO (o 46o).** O legado tinha ZERO gate: `contracts_controller.rb` tem 101 linhas e nenhum `before_action`/`may?`/`admin?`/`og?`/`authorize`, e as rotas nao tem constraint (`routes.rb:30-31`). Qualquer autenticado publicava um novo Termos de Uso. Implementado em `Authorization::Matrix` e `api/v1/contract_versions.rb`; provado nos dois lados em `spec/requests/api/v1/contract_versions_spec.rb`. **`user_is_readonly` tira C/U/D daqui, mas NUNCA do aceite** (`/api/v1/contracts/:id/accept` e `/api/v1/me/terms` estao em `READONLY_EXEMPT_PATHS`) — senao o readonly nunca aceita e fica trancado fora do sistema. |

### Recursos transversais (sem item de menu)

| Recurso | og | admin | manager | demais | user_is_readonly | Escopo | Evidencia (arquivo:linha) |
| ------- | -- | ----- | ------- | ------ | ---------------- | ------ | ------------------------- |
| `app_themes` (Temas) | CRUD | CRUD | - | R* | tira C/U/D | global | **Q-A4 resolvida (DEC-18): og/admin**, que e o gate do grupo Admin. As 3 evidencias discordavam entre si: `views\...\themes\helper\_body.html.erb:169` = `og?` puro; `form\_body.html.erb:327` = og/admin/manager; `pub\app_themes_controller.rb:24,31` = so `Admin` como destinatario |
| **Impersonation** | **CRUD (auditado)** | **so usuarios de hierarquia inferior, auditado** | - | - | bloqueia | global | **DEC-18.3.** `pub\users_controller.rb:107-127`; rotas em `config\routes.rb:14,17-18`; `PubApplicationController:18-20`. Hoje **zero checagem** — nucleo do D-34. Nunca personificar OG, nunca lateral; exige motivo; grava trilha; a sessao expira; nao encadeia |
| `console` / `console_observers` / `start` | R | R | R | R | sem efeito | proprio | Infra de render do console, nao recurso de negocio |

**Contagem: 46 recursos (45 + `contract_versions`, DEC-38), 4 papeis + 1 modificador (`user_is_readonly`).**

---

## As 17 abilities

Fonte unica: `..\sfg\app\decorators\models\ability_factory_decorator.rb:11-30`. Sao 12
do tipo `conditional` (0/1) + 4 do tipo `limit` (numero) + `user_is_readonly`
(`conditional`). Os aliases vem de `..\sfg\config\application.rb:66-67`:
`private_entities_alias = "Projetos"`, `public_entities_alias = "Modulos"` — ou seja,
**"private entries" = Projetos** e **"public entries" = Modulos** no vocabulario do SFG.

Os valores por papel vem de `..\sfg\db\seeds.rb:40-95` (Admin/Gerente/Colaborador) e
`..\sfg\engines\auth19\db\seeds.rb:9-29` (OG).

| # | Ability | Tipo | O que libera | OG | Admin | Gerente | Colab | Evidencia |
| - | ------- | ---- | ------------ | -- | ----- | ------- | ----- | --------- |
| 1 | `may_create_private_entries` | cond. | Criar **Projetos** | 1 | 1 | 1 | 1 | `ability_factory_decorator.rb:11`; `db\seeds.rb:43,67,85`; `auth19\db\seeds.rb:16` |
| 2 | `may_modify_private_entries` | cond. | Alterar Projetos | 1 | 1 | 1 | 1 | `ability_factory_decorator.rb:12`; `db\seeds.rb:44,69,86` |
| 3 | `may_read_private_entries` | cond. | Ler Projetos | 1 | 1 | 1 | 1 | `ability_factory_decorator.rb:13`; `db\seeds.rb:45,68,87` |
| 4 | `may_delete_private_entries` | cond. | Remover Projetos | 1 | 1 | 1 | **0** | `ability_factory_decorator.rb:14`; `db\seeds.rb:46,70` — **ausente** no bloco do Colaborador (`:82-95`) |
| 5 | `may_create_public_entries` | cond. | Criar **Modulos** | 1 | 1 | 1 | **0** | `ability_factory_decorator.rb:16`; `db\seeds.rb:47,71` |
| 6 | `may_modify_public_entries` | cond. | Alterar Modulos | 1 | 1 | 1 | **0** | `ability_factory_decorator.rb:17`; `db\seeds.rb:49,73` |
| 7 | `may_read_public_entries` | cond. | Ler Modulos | 1 | 1 | 1 | 1 | `ability_factory_decorator.rb:18`; `db\seeds.rb:48,72,88` |
| 8 | `may_delete_public_entries` | cond. | Remover Modulos | 1 | 1 | 1 | **0** | `ability_factory_decorator.rb:19`; `db\seeds.rb:50,74` |
| 9 | `may_create_users` | cond. | Criar usuarios direto | 1 | 1 | **0** | **0** | `ability_factory_decorator.rb:21`; `db\seeds.rb:51`; **ausente** no bloco do Gerente (`:62-80`). Tambem alimenta `RoleType.inferior_role_types` (`auth19\app\models\livetat\auth\role_type.rb:16-25`) |
| 10 | `may_read_users` | cond. | Ver dados de outros usuarios | 1 | 1 | 1 | **0** | `ability_factory_decorator.rb:22`; `db\seeds.rb:52,65` |
| 11 | `may_invite_users` | cond. | Convidar usuarios (por e-mail) | 1 | 1 | 1 | **0** | `ability_factory_decorator.rb:23`; `db\seeds.rb:53,66` |
| 12 | `may_delete_users` | cond. | Remover usuarios | 1 | 1 | **0** | **0** | `ability_factory_decorator.rb:24`; `db\seeds.rb:54`; **ausente** no bloco do Gerente |
| 13 | `max_private_entries_amount` | limit | Teto de Projetos | 100 | 9999 | **0** | 100 | `ability_factory_decorator.rb:26`; `db\seeds.rb:56,76,91`; `auth19\db\seeds.rb:25` |
| 14 | `max_public_entries_amount` | limit | Teto de Modulos | 200 | 9999 | 200 | **0** | `ability_factory_decorator.rb:27`; `db\seeds.rb:57,77,92` |
| 15 | `max_invitations_amount` | limit | Teto de convites | 200 | 9999 | 50 | 0 | `ability_factory_decorator.rb:28`; `db\seeds.rb:58,78,93` |
| 16 | `max_users_amount` | limit | Teto de usuarios criados | 100 | 9999 | 0 | 0 | `ability_factory_decorator.rb:29`; `db\seeds.rb:59,79,94` |
| 17 | `user_is_readonly` | cond. | **Modificador**: `1` remove todo botao de escrita em ~30 telas e some o item "Permissoes" | 0 | 0 | 0 | 0 | `ability_factory_decorator.rb:3,30`; `db\seeds.rb:55,75,90` e reafirmado em `:341-353`; consumido em `application_helper.rb:145` e em ~30 views |

**Contagem: 17 abilities — bate com o esperado (D-35).**

### Tres observacoes que afetam a proposta

1. **Contradicao explicita nos limites** (evidencia, nao inferencia). O **Gerente** tem
   `may_create_private_entries = 1` mas `max_private_entries_amount = 0`
   (`db\seeds.rb:67` vs `:76`). E o **Colaborador** tem `max_private_entries_amount = 100`
   (`:91`) sendo que so ve projetos dos quais ja e membro. Ou seja, os limites e as
   condicionais **discordam entre si** para os dois papeis. Isso e forte indicio de que
   os limites **nunca foram usados** de fato — grep nao encontra nenhum consumidor de
   `max_*` fora do proprio factory.
2. **As abilities nao mapeiam nos recursos do SFG.** Elas falam de "Projetos" e
   "Modulos" (vocabulario generico da engine Livetat). Nao existe ability para
   `receivables`, `carriers`, `risk_operations` etc. **Nenhuma das 12 condicionais e
   consultada em lugar nenhum do app** — apenas `user_is_readonly` e, e so na view. Isso
   e o que sustenta a decisao **#6**.
3. **`user_is_readonly` esta em 0 para todos os papeis semeados** — ou seja, se existe
   usuario readonly em producao hoje, ele foi marcado **manualmente** pela tela de
   Permissoes, fora do seed. Nao tenho como saber quantos sao. Ver pergunta **Q-A1**.

---

## Divergencias entre a intencao do codigo e o efeito real hoje

| # | O que o codigo **pretendia** | O que **acontece de fato hoje** | Evidencia | Defeito |
| - | ---------------------------- | ------------------------------- | --------- | ------- |
| 1 | Menu gata Cadastro em `og?/admin?/manager?` e Admin em `og?/admin?` — logo, so eles acessam esses recursos | O menu **some**, o endpoint **fica**. Um Colaborador que saiba a URL faz `POST /carriers`, `DELETE /segments`, tudo | `application_helper.rb:139,166` vs. **zero** `before_action` de autorizacao em `app\controllers\pub\*` | **D-23** |
| 2 | `PUT /users/:id/abilities` alteraria as abilities **do usuario `:id`** | `fetch_permission` faz `Livetat::Auth::Ability.find(params[:id] \|\| params[:ability_id])` — **descarta o `:id` do usuario** e edita **qualquer linha de ability do sistema**, inclusive as do RoleType OG | `pub\permissions_controller.rb:55-57`; `update` em `:26-39` sem gate | **D-34** |
| 3 | Impersonation seria de administrador | `impersonate` faz `User.find(params[:id])` + `impersonate_user(@user)` **sem checar nada**. Qualquer sessao vira qualquer usuario, inclusive OG | `pub\users_controller.rb:107-116`; `PubApplicationController:12-20` so tem `lock_if_there_is_no_user` | **D-34** |
| 4 | `destroy`, `deactivate_and_force_logout` e `reactivate` de usuario seriam de admin | Nenhum dos tres checa papel. `deactivate_and_force_logout` nem usa o `fetch_user` — pega `params[:user_id]` cru | `pub\users_controller.rb:135-157` | **D-34** |
| 5 | Memberships (quem entra em que projeto) seriam controlados | `pub\memberships_controller.rb` tem apenas `fetch_target` e `fetch_membership`. `create`/`destroy` sem gate: qualquer um se auto-adiciona a qualquer projeto — **e ai ganha o grupo "Gestao" inteiro** | `pub\memberships_controller.rb:2-3,29,45` | **D-34 + D-28** |
| 6 | **`locked: true`** travaria 4 itens: `availability`, `charges`, `project_availabilities`, `availability_templates` | O ERB le **`g[:locked]`** (do **grupo**) mas o flag foi setado nos **itens** (`i[:locked]`). `g[:locked]` e sempre `nil` -> a classe `locked` nunca e aplicada e `data-locked` sai `false` em **todos** os itens. **Os 4 estao destravados**, e o `locked` nao trava **nada** no app inteiro | Set: `application_helper.rb:111,127,128,148`. Leitura errada: `views\pub\console\base\menu\_container.html.erb:24` — `<%= (!g[:locked].nil? && g[:locked]) ? 'locked' : '' %>` | **D-90** |
| 7 | `default_role_type` seria `"Visitor"` | O app o sobrescreve por **`""`**. Usuario sem papel explicito nao casa com nenhum gate e cai em "demais" | `config\application.rb:65` sobrescreve `engines\auth19\lib\livetat\auth\configuration.rb:53` | **D-36** |
| 8 | `minimal_type_to_sign_up_through_web` seria `"Manager"` (RoleType destruido -> `NoMethodError`) | O app o sobrescreve por **`"Admin"`**, que **existe**. Nao ha `NoMethodError`; ha algo pior: **cadastro publico ate hierarquia 998** | `config\application.rb:84`; `engines\auth_ux19\...\sessions_controller.rb:24`; `db\seeds.rb:35-37,41` | **D-36 (sintoma errado na ficha) + D-39** |
| 9 | Alterar a ability de um RoleType propagaria aos usuarios | `Role` congela as abilities no usuario; so `reset_permissions` re-propaga, e ele so roda no seed (`db\seeds.rb:354-358`). Revogar permissao pela tela **nao revoga** de quem ja existe | `auth19\app\models\livetat\auth\role_type.rb:4,37-41`; `db\seeds.rb:354-358` | **D-35** |
| 10 | `Membership.role` (`Responsavel`/`Participante`/`Coordenador`/`Gestor`) daria nivel dentro do projeto | O campo e **escrito em 7 lugares e lido em zero**. E puramente descritivo — nao autoriza nada | Escrita: `app\models\project.rb:70,72,387,732,734`, `user_decorator.rb:246,259`. Leitura para autorizacao: **nenhuma** (grep) | novo — ver **Q-A2** |
| 11 | `permissions` seria escondido de readonly (`if !may?("user_is_readonly")`) | Some do menu, mas `PUT /permissions/:id` continua aberto — e e justamente o endpoint que edita as proprias abilities | `application_helper.rb:145` vs `pub\permissions_controller.rb:26-39` | **D-23 + D-34** |

---

## As 8 decisoes — veredito do Vinicius (DEC-18, 24/08/2026)

5 aprovadas como propostas, 2 alteradas (#2 e #5), 1 invertida (#4). O texto original
de cada uma fica preservado abaixo do veredito, para quem precisar do racional.

### 1. Colaborador ganha **leitura explicita** nos catalogos globais que hoje o menu esconde dele

> **Veredito (DEC-18.4): APROVADA como proposta.** O Colaborador recebe `R` nos 14
> catalogos globais. Regra em uma frase: **o menu esconde a tela de administracao do
> catalogo, nao o dado do catalogo.** Leitura apenas, nenhum verbo de escrita.

**Racional.** O menu nega o grupo Cadastro ao Colaborador
(`application_helper.rb:139`). Se eu traduzir isso literalmente em "Colaborador nao
acessa `carriers`/`segments`/`wallets`/`movement_kinds`/...", **as telas dele quebram**:
o formulario de recebivel precisa ler `receivable_kinds` e `wallets`; o de operacao de
risco precisa de `risk_operation_types`; o de empresa precisa de `segments` e
`sub_segments`. Hoje isso funciona por acidente (nao ha autorizacao nenhuma). A regra
correta e: **o menu esconde a tela de *administracao* do catalogo, nao o *dado* do
catalogo.** Por isso as linhas `R*`.

**Risco se eu estiver errado — este e o maior risco desta proposta.** Se eu **nao**
conceder esse `R*`, todo Colaborador perde o preenchimento de dropdown no dia 1 e o
sistema fica inutilizavel para o papel mais numeroso. Se eu conceder demais, um
Colaborador consegue **listar** o catalogo global inteiro (nomes de portadores,
segmentos) — vazamento de baixa gravidade, sem dado financeiro, e que **ja acontece
hoje**. Escolhi errar para o lado que nao quebra ninguem. **Se voce discordar**, preciso
da lista exata de catalogos que o Colaborador pode ler, e eu implemento um endpoint de
"opcoes de formulario" restrito em vez de leitura do recurso.

### 2. ~~`permissions` exclusivo do OG~~ -> **OG + Admin, limitado a hierarquia inferior** (ALTERADA)

> **Veredito (DEC-18.2): ALTERADA — o usuario abriu para o Admin, com trava.** O Admin
> edita abilities **so de RoleTypes abaixo do dele** — nunca a propria, nunca a do OG.
> Isto fecha a autopromocao (o risco real) **sem** criar dependencia da Livetat para uma
> tarefa administrativa do cliente. Melhor que a minha proposta: eu resolvia o risco
> cortando a funcionalidade; a resposta resolve **mantendo** a funcionalidade.
> **Gerente sai** da tela. **O D-34 tem de ser corrigido na mesma tarefa**, senao a trava
> e contornavel por URL.

**Racional.** Hoje o menu libera para og/admin/manager. Mas o recurso edita as linhas de
`Livetat::Auth::Ability` — e `permissions_controller.rb:55-57` nao amarra a ability ao
usuario, entao **qualquer** ability e alcancavel, inclusive as do proprio RoleType OG.
Manter Admin e Gerente ali significa manter um caminho de auto-promocao. Alem disso o
proprio controller ja trata o OG como especial (`:17-21`: so ele ve o RoleType OG).

**Risco.** Se hoje um Admin do cliente administra permissoes na rotina dele, ele perde
essa tela no dia 1 e passa a depender da Livetat. **Se voce discordar**, a alternativa
segura e: Admin **pode** editar abilities, mas so de RoleTypes de hierarquia **abaixo da
sua** (`RoleType.inferior_role_types`, que ja existe em
`auth19\app\models\livetat\auth\role_type.rb:16-25`) — nunca a propria nem a do OG.
Essa alternativa e implementavel com o mesmo esforco; so preciso saber qual voce quer.

### 3. Gerente fica com **R** em `users`, nao CRUD

> **Veredito (DEC-18): APROVADA.** Tres evidencias independentes concordam. Gerente le
> usuarios e **convida**; nao cria nem remove.

**Racional.** Aqui as duas fontes divergem e eu segui a mais especifica. O menu poe
"Contas" no grupo Cadastro, que inclui o Gerente (`application_helper.rb:139,144`), e a
lista deixa ele ver (`users\list\_widget.html.erb:44`). Mas **todas** as acoes de
escrita estao atras de `og? || admin?`: `users\detail\_body.html.erb:22`,
`detail\_body.js.erb:8`, `helper\_body.html.erb:18`. E as abilities concordam: o Gerente
**nao tem** `may_create_users` nem `may_delete_users` (`db\seeds.rb:62-80`), mas **tem**
`may_read_users` e `may_invite_users` (`:65-66`).

Entao: **Gerente le usuarios e convida** (fluxo de convite, nao criacao direta); nao
cria nem remove. Tres evidencias independentes apontam para o mesmo lugar — esta e a
linha em que tenho mais confianca da matriz inteira.

**Risco.** Baixo. Se hoje algum Gerente cria conta na mao, ele passa a usar convite.

### 4. ~~Os 4 itens `locked` entram desligados~~ -> **entram HABILITADOS** (INVERTIDA)

> **Veredito (DEC-15.1): INVERTIDA.** O usuario confirmou que disponibilidades e
> cobrancas **estao vivas**. Eu ia portar a *intencao* do codigo e desligar os quatro —
> teria tirado tela de quem trabalha com elas hoje. O D-90 deixa de ser "bug a corrigir"
> e passa a ser **comportamento efetivo a preservar**. O mecanismo `locked` continua
> existindo e sendo corrigido (ler do item, nao do grupo), mas **nenhum dos 4 nasce
> marcado**. Licao: **producao e a verdade, nao a intencao aparente do codigo.**

**Racional.** A intencao do codigo e inequivoca — `locked: true` em `availability`,
`charges`, `project_availabilities` e `availability_templates`
(`application_helper.rb:111,127,128,148`). O efeito real e o oposto: destravados para
todos (D-90). Porto a **intencao**, nao o bug: os quatro nascem desabilitados no ai9,
atras de um feature flag, visiveis so para OG.

**Risco — e o que eu menos consigo medir.** `project_availabilities` tem tela completa
com toggles ativar/desativar e gates de readonly (`views\...\project_availabilities\
list\_widget.html.erb:44,53,57`), o que **nao parece** funcionalidade abandonada. Se
alguem usa disponibilidades hoje (justamente porque o lock nunca funcionou), essa gente
perde a tela no dia 1. **Preciso que voce confirme:** disponibilidades e cobrancas sao
recursos vivos ou features nunca lancadas? Se forem vivos, eu inverto — entram
habilitados com escopo de projeto, como os demais do grupo.

### 5. ~~Impersonation so OG~~ -> **OG + Admin restrito a hierarquia inferior** (ALTERADA)

> **Veredito (DEC-18.3): ALTERADA — mesmo padrao da decisao #2.** O Admin personifica
> **so usuarios de hierarquia inferior a dele**; nunca OG, nunca lateral. Para os dois
> papeis: exige motivo, grava trilha (quem, quem foi personificado, quando, por que,
> quando encerrou), a sessao **expira**, e **nao encadeia** (o personificado nao
> personifica). Desarma a combinacao D-34 + D-109.

**Racional.** Hoje nao ha checagem nenhuma (`users_controller.rb:107-116`) — e o vetor
mais direto do D-34, e combina com o D-109 (senha deterministica) para comprometimento
trivial. E ferramenta de suporte do fornecedor, nao de administracao do cliente.
Proponho: so OG, exige motivo, grava trilha (quem, quem foi personificado, quando, por
que) e expira a sessao personificada.

**Risco.** Se o Admin do cliente usa impersonation para dar suporte aos proprios
usuarios, ele perde isso. **Se discordar**, estendo para Admin **restrito a usuarios de
hierarquia inferior a sua** — nunca para OG, nunca lateral.

### 6. As 12 abilities condicionais **nao viram** o mecanismo de autorizacao do ai9; `user_is_readonly` vira

> **Veredito (DEC-18): APROVADA.** Autorizacao no ai9 = **papel + membership**,
> declarativa por rota, avaliada **no servidor**. Das 17 abilities so
> `user_is_readonly` sobrevive, promovida de flag de UI a checagem de servidor.
> As 16 restantes ficam registradas aqui e **nao** sao portadas.

**Racional.** Elas falam de "Projetos" e "Modulos" (`config\application.rb:66-67`), nao
dos 45 recursos reais, e **nenhuma delas e consultada em lugar nenhum do app** — so
`user_is_readonly` e, e so em view. Alem disso os limites se contradizem (Gerente com
`create = 1` e `max = 0`, `db\seeds.rb:67` vs `:76`) e o D-35 mostra que alterar a
ability nao propaga. Manter esse mecanismo seria portar complexidade morta.

**Proposta.** Autorizacao no ai9 = **papel + membership de projeto**, declarativa por
rota, avaliada no servidor. Das 17, so **`user_is_readonly` sobrevive**, promovida de
flag de UI a **checagem de servidor** que nega todo verbo de escrita. As outras 16 ficam
registradas aqui e **nao** sao portadas.

**Risco.** Se alguem em producao editou abilities pela tela de Permissoes para criar um
perfil sob medida (unico jeito de fazer isso hoje), esse perfil desaparece. Como a tela
existe e e alcancavel, **isso e possivel e eu nao tenho como verificar sem o banco.**
Ver **Q-A1** — e a pergunta que mais me preocupa.

### 7. Cadastro publico deixa de criar Admin (D-39)

> **Veredito (DEC-18.7): APROVADA na forma mais restritiva.** Cadastro publico
> **desligado**; nao existe rota de auto-cadastro no ai9. Entrada so por **convite**
> (OG, Admin e Gerente ja tem `may_invite_users`); o convite carrega o papel e, quando
> aplicavel, o projeto.

**Racional.** `config\application.rb:84` define `minimal_type_to_sign_up_through_web =
"Admin"` — qualquer pessoa na internet se cadastra ate hierarquia 998.

**Proposta.** Cadastro publico **desligado**. Entrada no sistema so por **convite**
(`may_invite_users`, que OG/Admin/Gerente ja tem). Se o convite for insuficiente, o
fallback e cadastro publico criando **Colaborador sem nenhuma membership** — que ve
apenas "Inicio", "Perfil" e "Ajuda" ate um Admin adiciona-lo a um projeto (o gate
`projects.count > 0` de `application_helper.rb:106,122` ja faz esse trabalho
naturalmente).

**Risco.** Baixo, mas real: se existe onboarding comercial que depende de auto-cadastro,
ele para. Precisa de uma palavra sua.

### 8. O papel `""` (D-36) e tratado como "sem acesso", nao como Colaborador

> **Veredito (DEC-18): APROVADA.** `role_type` e **obrigatorio** no seed do ai9. Na
> migracao, usuario com papel vazio entra como **Colaborador** e sai numa **lista de
> excecoes** para revisao humana antes do cutover — nem promovido nem bloqueado em
> silencio.

**Racional.** `default_role_type = ""` (`config\application.rb:65`) produz usuarios cujo
`role_type` nao casa com `og?`/`admin?`/`manager?`/`colab?`
(`user_decorator.rb:145-158`). Hoje eles caem em "demais" e, como nao ha autorizacao,
fazem tudo.

**Proposta.** No seed versionado do ai9 (DEC-04), `role_type` e **obrigatorio** e o
default e `Colaborador`. Na migracao de dados, todo usuario com `role_type` vazio ou
nulo entra **como Colaborador** e sai numa lista de excecoes para revisao — nao e
silenciosamente promovido nem silenciosamente bloqueado.

**Risco.** Se houver muitos usuarios com papel vazio, a lista de excecoes fica grande e
alguem precisa revisar antes do cutover. Melhor descobrir no dry-run do que no dia 1.

---

## Perguntas — estado final

| # | Pergunta | Resposta | Onde |
| - | -------- | -------- | ---- |
| **Q-A1** | Existe usuario em producao com abilities editadas na mao (em especial `user_is_readonly = 1`)? | **AINDA ABERTA.** So o banco responde; dump em 25/08. **Irrelevante para a demo** (usuarios criados por nos); **trava do cutover real** — o dry-run tem de listar todo usuario cuja ability efetiva divirja do seed do RoleType dele | DEC-15.3, DEC-16 |
| **Q-A2** | `Membership.role` deveria autorizar algo? | **Nao — so rotulo descritivo.** A matriz permanece com **uma dimensao** (papel global + membership). Era o maior risco de a matriz mudar de forma; nao mudou | DEC-18.6 |
| **Q-A3** | Disponibilidades e cobrancas sao features vivas? | **VIVAS.** Os 4 itens `locked` nascem habilitados | DEC-15.1 |
| **Q-A4** | Quem administra `app_themes`? | **og/admin** — decisao minha, baixo impacto (recurso cosmetico, 3 evidencias contraditorias) | DEC-18, Q-A4 |
| **Q-A5** | OG e papel de cliente ou de fornecedor? | **Fornecedor (Livetat).** Nao entra na operacao do cliente nem no seed de demo como usuario normal | DEC-18.1 |
| **Q-A6** | Quem pode criar/remover membership? | **OG, Admin e Gerente**, mais as 3 condicoes da view promovidas a regra de servidor. O **dono do projeto nao** vira papel com poder — segue descritivo e protegido contra remocao | DEC-18.5, DEC-15.2 |
| **Q-A7** | Os limites `max_*` devem ser aplicados? | **Nao** — decisao minha. Nada os le fora do factory e eles se contradizem (Gerente: `create = 1`, `max = 0`). Aplica-los faria o Gerente nao criar nenhum projeto | DEC-18, Q-A7 |

---

## Resumo aprovado (DEC-18, 24/08/2026)

- **46 recursos** (45 aprovados + `contract_versions`, acrescentado pela **DEC-38**), **4 papeis** (OG, Admin, Gerente, Colaborador) + **1 modificador**
  (`user_is_readonly`), **17 abilities** levantadas — bate com o D-35.
- A matriz **restringe praticamente tudo** em relacao a hoje, porque hoje **nao existe
  restricao nenhuma no servidor** (D-23/D-34).
- Das 8 decisoes que eu propus, **5 foram aprovadas como estavam**, **2 foram alteradas**
  (#2 e #5 — o usuario delegou mais poder ao Admin do que eu propunha, sempre com trava
  de hierarquia inferior) e **1 foi invertida** (#4 — disponibilidades e cobrancas estao
  vivas).
- **Padrao que emergiu das duas alteracoes:** onde eu resolvia risco **cortando
  funcionalidade**, o usuario preferiu **manter a funcionalidade com uma trava de
  hierarquia**. O Admin e do cliente e precisa operar sem depender do fornecedor. Aplicar
  este mesmo criterio em decisoes futuras da mesma familia.

### O que isto gera quando o Phase 3 comecar

1. **Seed versionado de RoleTypes** (fecha parte do DEC-04): 4 papeis, hierarquias
   1111/998/888/799, `user_is_readonly = 0` para todos.
2. **Policies declarativas por rota** — papel + membership, avaliadas **no servidor**,
   substituindo os gates de view que hoje sao a unica autorizacao existente (D-23).
3. **Correcoes de seguranca que a matriz torna obrigatorias:** D-34 (permissions,
   impersonation, users, memberships), D-28 (auto-membership), D-39 (cadastro publico),
   D-23 (autorizacao so na view), mais o `:id` fora do `permit` (familia D-60/D-68).
4. **Trilha de auditoria de impersonation** — entidade nova, nao existe no legado.
5. **Lista de excecoes do dry-run:** usuarios com `role_type` vazio, e (quando o dump
   chegar) usuarios cuja ability efetiva divirja do seed do RoleType — a Q-A1.

> **Aviso que sobrevive a aprovacao:** nao aplicar restricao de papel **em producao**
> antes de responder a Q-A1 contra o banco real. Restringir bem e util; restringir cego
> tira acesso de usuario legitimo no dia 1.
