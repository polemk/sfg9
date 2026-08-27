# Data Schema Specification

## Purpose
Define o esquema de dados do ai9 para o domínio migrado do legado `sfg` (Safegold): as 67 tabelas
reconstruídas a partir das 139 migrations, suas colunas, relações, índices e seeds obrigatórios, mais
as regras de integridade que o legado só tinha em nível de aplicação.
O banco alvo é **PostgreSQL** (DEC-05, deduzido do bundle: os 3 Gemfiles declaram `gem 'pg'` e nenhum
declara `mysql2`). Não existe `pg_dump` de referência (DEC-04), então o ETL carrega uma etapa de
introspecção obrigatória. Timestamps do legado estão em horário de Brasília e são convertidos para UTC
por faixa de data (DEC-06). Precisão financeira em float é replicada por decisão do usuário (DEC-02).

## Requirements

### Requirement: DB-540 — livetat_auth_users
O ai9 **MUST** portar a tabela de usuários do produto (`Livetat::Auth::User`, alias global `U`) com todos os campos
Devise, os campos Paperclip de avatar e as colunas de vínculo (`manager_id`, `app_theme_id`,
`default_project_id`). Fonte legada: `engines/auth19/db/migrate/20160409121830:3-35`,
`20160409121831:3-5`, `db/migrate/20171120004723:3`, `20190121164730:3`, `20190207025722:3`,
`20190419000711:3`, `20200206191948:3`, `20210303182740:3`, `20210402111120:2-8`, `20210402134709:3`,
`20210402135252:3`, `20220523124957:3`, `20220525124802:3`; model `engines/auth19/app/models/livetat/auth/user.rb:286`.

- **Colunas**: `id` PK · `formal`, `username`, `email` (NOT NULL default `""`), `unconfirmed_email`,
  `encrypted_password` (NOT NULL default `""`), `authentication_token`, `reset_password_token`,
  `confirmation_token`, `unlock_token` string · `sign_in_count`, `failed_attempts` int NOT NULL d0 ·
  `current_sign_in_ip`, `last_sign_in_ip` string · `current_sign_in_at`, `last_sign_in_at`,
  `confirmation_sent_at`, `reset_password_sent_at`, `remember_created_at`, `locked_at`, `confirmed_at`
  datetime · `avatar_file_name`, `avatar_content_type`, `avatar_file_size` int, `avatar_updated_at` ·
  `kind`, `identifier`, `color` string · `manager_id`, `app_theme_id`, `default_project_id` · `legacy_id`
  int · `legacy_password` string (hash Django do sistema pré-2021) · `is_active` int d1 ·
  `deactivated` boolean d false · `is_default_member` int d0 · timestamps.
- **Relações**: `has_one :role` e `has_one :info` (destroy) · `belongs_to :app_theme`,
  `:default_project` · auto-relação `manager_id` → `dependents` · `has_many :memberships` (delete_all no
  legado) · `has_many :projects, through: :memberships` · `has_many :contract_deals`, `:receivables`.
- **Índices**: únicos em `email`, `reset_password_token`, `confirmation_token`, `unlock_token`,
  `authentication_token`, `legacy_id`; no ai9 acrescentam-se índices em `manager_id`, `app_theme_id`,
  `default_project_id`.
- `role_type` **não é coluna** — é atributo virtual persistido em `livetat_auth_roles` (`user.rb:191-196`).

#### Scenario: unicidade de e-mail
- **GIVEN** um usuário existente com `email = "a@safegold.com.br"`
- **WHEN** o ETL tenta inserir outro registro com o mesmo `email`
- **THEN** o índice único rejeita a inserção e o registro entra no relatório de duplicatas, sem sobrescrever o existente

#### Scenario: dois flags de desativação concorrentes
- **GIVEN** um registro legado com `is_active = 0` e `deactivated = false`
- **WHEN** o ETL normaliza o estado da conta
- **THEN** o usuário é gravado no ai9 como desativado e a divergência entre os dois flags é registrada no relatório de reconciliação

#### Scenario: manager inexistente
- **GIVEN** um usuário legado com `manager_id` apontando para um id que não existe em `livetat_auth_users`
- **WHEN** o ETL valida as referências antes de inserir
- **THEN** a linha é contada como órfã, a carga aborta conforme DB-ETL-03 e nenhum vínculo errado é criado

> Nota: corrige D-103 (legado: nenhuma foreign key e nenhum índice em `manager_id`/`app_theme_id`/`default_project_id`)

### Requirement: DB-541 — livetat_auth_user_infos
O ai9 **MUST** manter o perfil estendido 1:1 do usuário (CPF/CNPJ, telefones, endereço de entrega, contato de emergência,
documento fiscal), herdado da engine genérica. Fonte legada:
`engines/auth19/db/migrate/20171020133117:3-38`, `20171201171447:3-5`, `20171201171448:3-11`,
`20171204213707:3`, `20171206031439:3`, `20171213170127:3-6`.

- **Colunas**: `user_id` int · `first_name`, `last_name` string · `gender` int · `birthday` timestamp ·
  `public_email`, `professional_email`, `cpf`, `cnpj` string · `phone_confirmation_code`,
  `complementary_phone_confirmation_code` string · `is_phone_checked`, `is_complementary_phone_checked`
  int · `language`, `living_address` string · `biography` text · `graduation`, `work` string ·
  `is_emergency_contact_active` int · `emergency_contact_name/_phone/_email/_relation` string ·
  `is_delivery_location_active` int · `delivery_location_country/_address/_complement/_city/_state/_cep/_address_number`
  string · `tax_document_number/_issuer/_issue_date` string · `phone_country_code` string d`"55"` ·
  `phone_area_code`, `phone_number` string · `complementary_phone_country_code` d`"55"`,
  `complementary_phone_area_code`, `complementary_phone_number` string · `confiability_level` string
  d`"Baixa"` · timestamps.
- **Relações**: `belongs_to :user`, unicidade de `user_id`.
- **Índices (ai9)**: índice **único** em `user_id` (o legado validava só em aplicação, `user_info.rb:18`).

#### Scenario: um perfil por usuário
- **GIVEN** um usuário que já possui `livetat_auth_user_infos`
- **WHEN** uma segunda linha de info é criada para o mesmo `user_id`
- **THEN** o índice único no banco rejeita a operação

#### Scenario: nível de confiabilidade default
- **GIVEN** um perfil criado sem `confiability_level`
- **WHEN** o registro é persistido
- **THEN** o valor gravado é `"Baixa"`

> Nota: corrige D-103 (legado: unicidade de `user_id` só em aplicação, sem índice no banco)

### Requirement: DB-542 — livetat_auth_roles
O ai9 **MUST** manter o vínculo 1:1 entre usuário e tipo de papel; as abilities individuais penduram nele por associação
polimórfica. Fonte legada: `engines/auth19/db/migrate/20160409121832:3-8`.

- **Colunas**: `id`, `role_type_id` int, `user_id` int, timestamps.
- **Relações**: `belongs_to :role_type`, `belongs_to :livetat_auth_user` ·
  `has_many :abilities, as: :abilitable` (delete_all).
- **Índices (ai9)**: índice único em `user_id`; índice em `role_type_id`.

#### Scenario: papel único por usuário
- **GIVEN** um usuário que já possui um `role`
- **WHEN** um segundo `role` é criado para o mesmo `user_id`
- **THEN** o índice único rejeita a operação

#### Scenario: remoção do usuário
- **GIVEN** um usuário com `role` e abilities associadas
- **WHEN** o usuário é excluído
- **THEN** o `role` e as suas abilities são removidos em cascata, sem deixar abilities órfãs

> Nota: corrige D-103 (legado: nenhum índice em `user_id` nem em `role_type_id`)

### Requirement: DB-543 — livetat_auth_client_applications
O ai9 **MUST** portar as aplicações-cliente com token de integração da engine de auth. Fonte legada:
`engines/auth19/db/migrate/20160409121835:3-9`, `db/migrate/20200211205426:3-5`.

- **Colunas**: `id`, `name` string, `agent` string, `authentication_token` string, `external_id` int,
  `color` string, `default_user_id` int, timestamps.
- **Relações**: `name` e `agent` únicos (`client_application.rb:4-5`).
- **Índices (ai9)**: únicos em `name`, `agent` e `authentication_token`.
- **Colisão de nome**: o ai9 já possui `client_applications` (`backend/db/schema.rb`) com domínio
  diferente — a tabela legada é importada com prefixo próprio ou fundida por decisão do Phase 2.

#### Scenario: colisão com a tabela homônima do ai9
- **GIVEN** o ai9 já tem uma tabela `client_applications` em uso pela autenticação por token
- **WHEN** a introspecção do ETL encontra `livetat_auth_client_applications` no legado
- **THEN** a carga usa o nome de destino resolvido no mapeamento e nunca escreve na tabela `client_applications` nativa do ai9

#### Scenario: token de aplicação único
- **GIVEN** duas aplicações-cliente legadas com o mesmo `authentication_token`
- **WHEN** o ETL as insere
- **THEN** a segunda é rejeitada pelo índice único e listada no relatório de duplicatas

> Nota: corrige D-103 (legado: `name`/`agent` únicos apenas em aplicação, sem índice no banco)

### Requirement: DB-544 — livetat_auth_omni_providers
O ai9 **MUST** preservar o vínculo entre usuário e provedor OAuth (Facebook). Fonte legada:
`engines/auth_omni19/db/migrate/20170722163911:3-10`, `20170722164423:3`.

- **Colunas**: `id`, `name` string, `uid` string, `user_id` int, timestamps.
- **Relações**: `belongs_to :user`.
- **Índices**: índice **único** composto `[name, uid, user_id]` (já existe no legado; preservar).
- `uid` é o identificador do provedor OAuth, sem relação com qualquer `public_uid` do ai9.

#### Scenario: vínculo duplicado com o provedor
- **GIVEN** um usuário já vinculado a `name = "facebook"` e um `uid`
- **WHEN** o mesmo trio `[name, uid, user_id]` é inserido de novo
- **THEN** o índice único rejeita a inserção

#### Scenario: tabela vazia no legado
- **GIVEN** que o login social está desativado no legado (app id `0`, ver OPS-489)
- **WHEN** o ETL conta as linhas de origem
- **THEN** uma contagem zero é aceita e registrada no relatório, sem falhar a carga

### Requirement: DB-545 — memberships
O ai9 **MUST** manter a associação polimórfica entre usuário e entidade "membrável" — na prática, sempre `Project`. É a tabela
que define o que cada usuário enxerga (DEC-07). Fonte legada: `db/migrate/20210301171119:3-10`,
`20210402111120:2-8`, `20210403175036:3-4`.

- **Colunas**: `id`, `user_id` int, `memberable_id` int, `memberable_type` string, `role` string,
  `is_active` int, `legacy_id` int, `legacy_project_id` int, `legacy_user_id` int, timestamps.
- **Relações**: `belongs_to :memberable` (polimórfico), `belongs_to :user`.
- **`role`** é enum-string pt-BR com default aplicado em `after_initialize`: `"Responsável"`,
  `"Participante"`, `"Coordenador"`, `"Gestor"` (`membership.rb:9-21`).
- **Índices**: único em `legacy_id` (existente); no ai9 acrescentam-se índice único composto
  `[user_id, memberable_type, memberable_id]` e índice em `[memberable_type, memberable_id]`.

#### Scenario: usuário não entra duas vezes no mesmo projeto
- **GIVEN** um usuário já membro do projeto X
- **WHEN** duas requisições concorrentes tentam criar a membership de novo
- **THEN** o índice único composto garante que apenas uma linha exista

#### Scenario: escopo de leitura do usuário
- **GIVEN** um usuário sem membership no projeto X
- **WHEN** ele solicita dados escopados a projeto
- **THEN** nenhum registro do projeto X é retornado

> Nota: corrige D-103 (legado: unicidade `user_id` × `[memberable_id, memberable_type]` só em aplicação e nenhum índice em `user_id` nem em `memberable`)

### Requirement: DB-546 — contracts
O ai9 **MUST** portar os termos de uso e a política de privacidade versionados, aceitos pelos usuários. Fonte legada:
`db/migrate/20180405163859:3-10`; model `app/models/contract.rb:9,13-14`.

- **Colunas**: `id`, `title` string, `creator_id` int, `version` int, `kind` string, timestamps NOT NULL,
  **`description` text** — coluna gravada por `db/seeds.rb:124` e **não criada por nenhuma migration**.
- **Relações**: `has_many :contract_deals`, `has_many :users, through: :contract_deals`,
  `belongs_to :creator` (User).
- **`kind`** é enum-string pt-BR: `"Termos de Uso"`, `"Politicas de Privacidade"` (sem acento no legado).
- **Índices (ai9)**: índice único composto `[kind, version]`; índice em `creator_id`.

#### Scenario: coluna fora das migrations
- **GIVEN** que `contracts.description` existe no banco de produção mas em nenhuma migration (D-108)
- **WHEN** a etapa de introspecção do ETL lê o schema real
- **THEN** a coluna é reconhecida pelo mapeamento explícito e o corpo do contrato é migrado, em vez de ser silenciosamente descartado

#### Scenario: versão duplicada do mesmo tipo
- **GIVEN** um contrato `kind = "Termos de Uso"` na `version = 1`
- **WHEN** outro registro do mesmo tipo e versão é inserido
- **THEN** o índice único composto rejeita a inserção

> Nota: corrige D-108 (legado: `description` gravada pelo seed sem migration que a crie) e D-103 (legado: unicidade `kind` × `version` só em aplicação)

### Requirement: DB-547 — contract_deals
O ai9 **MUST** registrar o aceite de um contrato por um usuário. Fonte legada: `db/migrate/20180405164055:3-8`.

- **Colunas**: `id`, `user_id` int, `contract_id` int, timestamps NOT NULL.
- **Relações**: `belongs_to :contract`, `belongs_to :user`.
- **Índices (ai9)**: índice único composto `[contract_id, user_id]`; índices em `user_id` e `contract_id`.

#### Scenario: aceite único por usuário e contrato
- **GIVEN** um usuário que já aceitou o contrato X
- **WHEN** o mesmo aceite é registrado de novo
- **THEN** o índice único composto rejeita a inserção

#### Scenario: consulta de aceite sem varredura completa
- **GIVEN** a tabela de aceites carregada
- **WHEN** o sistema verifica se o usuário corrente aceitou a versão vigente
- **THEN** a consulta usa o índice em `user_id` e não percorre a tabela inteira

> Nota: corrige D-103 (legado: nenhum índice, a consulta do seed em `db/seeds.rb:144` fazia full scan)

### Requirement: DB-548 — app_themes
O ai9 **MUST** portar os temas white-label (STI `GlobalTheme` / `UserTheme`) com cores, fontes, 4 anexos Paperclip e CSS
cacheado. Fonte legada: `db/migrate/20200205130201:3-25`; model `app/models/app_theme.rb:75-86`.

- **Colunas**: `id`, `user_id` int, `title` string, **`type` string (STI real)**, `primary_color`,
  `second_color`, `accent_color`, `style`, `login_bkg_style`, `login_bkg_color`, `bar_font_name`,
  `font_name` string, `is_default` int, 16 colunas Paperclip (`symbol_logo_*`, `full_logo_*`,
  `text_logo_*`, `login_bkg_image_*`, cada um com `_file_name`, `_content_type`, `_file_size` int,
  `_updated_at` datetime), `override_css` text, `cached_css` text, `display_name` string,
  `copyright` string, timestamps.
- **Relações**: `belongs_to :user`; `UserTheme has_many :users` via `livetat_auth_users.app_theme_id`.
- **Enums-string em inglês**: `style` ∈ {`Dark`, `Light`}, `login_bkg_style` ∈ {`Color`, `Image`,
  `Default`}, `font_name` ∈ {`Helvetica`, `Arial`, `Tahoma`, `Baloo Thambi 2`, `Lato`}.
- **Índices (ai9)**: único em `title`; índices em `user_id` e `type`.

#### Scenario: CSS cacheado não é migrado como dado
- **GIVEN** um tema legado com `cached_css` preenchido
- **WHEN** o tema é importado para o ai9
- **THEN** o CSS é recalculado a partir dos tokens do tema e a coluna de cache não carrega conteúdo legado

#### Scenario: título de tema único
- **GIVEN** um tema chamado "Safegold"
- **WHEN** outro tema com o mesmo `title` é criado
- **THEN** o índice único rejeita a operação

> Nota: corrige D-103 (legado: `title` único apenas em aplicação, sem nenhum índice na tabela)

### Requirement: DB-549 — projects
O projeto **MUST** permanecer a unidade central de escopo do produto: quase todo dado financeiro é filtrado por ele
(DEC-07). Fonte legada: `db/migrate/20210301170412:3-32`, `20210402111120:2-8`, `20210511211918:3`,
`20211025163624:3`, `20220524121821:3`, `20220620140220:3`; model `app/models/project.rb:3-46`.

- **Colunas**: `id`, `formal` string, `integration_key` string, `user_id` int, `smart_id` string,
  `segment_id` int, `is_active` int d1, `color` string, Paperclip `avatar_*` ×4, `address_type`,
  `address`, `address_number`, `address_complement`, `neighborhood`, `cep`, `address_state`,
  `address_city`, `city` string, `closing_date` date, `importing_id` int, `responsible_email`,
  `responsible_formal` string, **`responsible_id` string** (usado como FK inteira), `job_state` string,
  `job_report` text, `job_id` int, `legacy_id` int, `has_safegold_management` int d1,
  `sub_segment_id` int, `is_sandbox` int d0, `has_bi` int d0, timestamps.
- **Relações**: `belongs_to :responsible` (User), `:segment`, `:sub_segment`, `:user` ·
  `has_many :memberships` (as `:memberable`), `:users through`, `:project_to_carrier_connections`
  (restrict), `:carriers through`, `:project_indicator_connections` (restrict), `:indicators through`,
  `:indicator_entries` (restrict), `:receivables` (restrict), `:renegotiations` (restrict),
  `:providers` (destroy), `:companies` (restrict), `:risk_controls` (restrict),
  `:availability_entries` (restrict), `:availability_templates` (destroy), `:remunerations`.
- **Índices**: único em `legacy_id` (existente); no ai9 acrescentam-se únicos em `smart_id` e
  `integration_key`, e índices em `segment_id`, `sub_segment_id`, `responsible_id`, `user_id`.
- **`responsible_id` é normalizada para inteiro/uuid** na migração; `job_id` deixa de existir (ver D-80).

#### Scenario: responsible_id com tipo errado no legado
- **GIVEN** um projeto legado com `responsible_id` gravado como string
- **WHEN** o ETL converte a coluna para a chave do ai9
- **THEN** valores não conversíveis são contados como órfãos e reportados, em vez de virarem NULL silencioso

#### Scenario: exclusão de projeto com dado financeiro
- **GIVEN** um projeto com recebíveis associados
- **WHEN** alguém tenta excluir o projeto
- **THEN** a exclusão é recusada (`restrict`) e uma mensagem de erro identifica a relação que impede a remoção

#### Scenario: estado de processamento sem FK para a fila
- **GIVEN** um projeto cujo job de criação de templates está em andamento
- **WHEN** o estado é consultado
- **THEN** o progresso vem de colunas da própria tabela `projects` e não de uma referência à tabela de jobs

> Nota: corrige D-80 (legado: `projects.job_id` era FK para `delayed_jobs`) e D-103 (legado: só o índice de `legacy_id`)

### Requirement: DB-550 — segments
O ai9 **MUST** manter o catálogo **global** de segmentos de mercado, compartilhado por todos os projetos (DEC-07). Fonte
legada: `db/migrate/20210317140228:3-11`, `20210402111120:2-8`; seed em `db/seeds.rb:160-164`.

- **Colunas**: `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int,
  `legacy_id` int, timestamps.
- **Relações**: `has_many :projects` (restrict_with_error).
- **Seed obrigatório**: Comércio, Indústria, Serviços (o flag no seed está `false`, mas o dado já existe
  em produção e é migrado).
- **Índices**: único em `legacy_id` (existente); no ai9 acrescenta-se único em `title`.

#### Scenario: segmento em uso não pode sumir
- **GIVEN** um segmento vinculado a pelo menos um projeto
- **WHEN** a exclusão do segmento é solicitada
- **THEN** a operação é recusada e o projeto permanece com o segmento

#### Scenario: catálogo global e não por projeto
- **GIVEN** dois projetos de escopos diferentes
- **WHEN** cada um lista os segmentos disponíveis
- **THEN** ambos veem exatamente o mesmo catálogo

### Requirement: DB-551 — sub_segments
O ai9 **MUST** manter o catálogo **global** de subsegmentos, criado depois do ETL de 2021 (por isso sem `legacy_id`). Fonte
legada: `db/migrate/20211025163246:3-11`.

- **Colunas**: `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int,
  timestamps.
- **Relações**: `has_many :projects` (restrict_with_error).
- **Índices (ai9)**: único em `title`.
- Sem seed: a tabela é populada exclusivamente pela interface.

#### Scenario: ausência de legacy_id
- **GIVEN** que `sub_segments` nunca recebeu `legacy_id`
- **WHEN** o ETL monta a tabela de-para
- **THEN** o mapeamento desta tabela é feito por `title` normalizado e a ausência de `legacy_id` é registrada como esperada, sem abortar

#### Scenario: subsegmento em uso
- **GIVEN** um subsegmento vinculado a um projeto
- **WHEN** a exclusão é solicitada
- **THEN** a operação é recusada

### Requirement: DB-552 — carriers
O ai9 **MUST** manter o catálogo **global** de cedentes/bancos (FIDC, securitizadora, factoring, cliente). Fonte legada:
`db/migrate/20210301192131:3-18`, `20210402111120:2-8`, `20210819194535:3`, `20220620135412:3`,
`20220810142317:3-4`; model `app/models/carrier.rb:46-49`.

- **Colunas**: `id`, `title` string, `resume` text, `user_id` int, `is_active` int d1, Paperclip
  `logo_*` ×4, `integration_key` string, `bank_code` int, `bank_name` string, `senior_accounts` int d0,
  `subordinated_accounts` int d0, `net_worth` **decimal(15,2)** d0, `subordinated_accounts_percent`
  **float** d0.0, `legacy_id` int, `group_id` int, `financial_agent` string, `city`, `uf` string,
  timestamps.
- **Relações**: `belongs_to :group` (CarrierGroup) · `has_many :project_to_carrier_connections`
  (restrict), `:projects through`, `:companies through: :projects`, `:receivables` (restrict),
  `:risk_controls` (**destroy**).
- **`financial_agent`** é enum-string: `"FIDC"`, `"Securitizadora"`, `"Factoring"`, `"Cliente"`.
- **Índices**: único em `legacy_id` (existente); no ai9 acrescentam-se índices em `group_id` e único em
  `integration_key`.

#### Scenario: exclusão de cedente apaga controles de risco
- **GIVEN** um cedente com `risk_controls` associados e sem recebíveis
- **WHEN** o cedente é excluído
- **THEN** os `risk_controls` são removidos em cascata, mantendo o comportamento do legado

#### Scenario: cedente com recebível não pode ser excluído
- **GIVEN** um cedente referenciado por um recebível
- **WHEN** a exclusão é solicitada
- **THEN** a operação é recusada

#### Scenario: precisão mista de patrimônio e percentual
- **GIVEN** `net_worth` em decimal(15,2) e `subordinated_accounts_percent` em float
- **WHEN** os valores são migrados
- **THEN** os tipos e o resultado dos cálculos derivados são idênticos aos do legado

> Nota: DEC-02 — precisao legada preservada por decisao do usuario

### Requirement: DB-553 — carrier_groups
O ai9 **MUST** portar o agrupamento de cedentes com contador de filhos mantido por `counter_cache`. Fonte legada:
`db/migrate/20210819193736:3-11`.

- **Colunas**: `id`, `title` string, `user_id` int, `carriers_count` int, timestamps.
- **Relações**: `has_many :carriers` com `counter_cache: :carriers_count` · `belongs_to :user`.
- **Índices (ai9)**: único em `title`; índice em `user_id`.
- No ai9 `carriers_count` recebe **NOT NULL default 0** — no legado a coluna não tinha default e as
  linhas antigas ficaram NULL, quebrando o counter cache.

#### Scenario: contador nulo vindo do legado
- **GIVEN** um grupo legado com `carriers_count` NULL
- **WHEN** o ETL o importa
- **THEN** o contador é recalculado pela contagem real de cedentes e gravado como inteiro não nulo

#### Scenario: contador acompanha a associação
- **GIVEN** um grupo com 2 cedentes
- **WHEN** um terceiro cedente é vinculado ao grupo
- **THEN** `carriers_count` passa a 3

> Nota: corrige D-103 (legado: `carriers_count` sem default, contador quebrado com NULL, e nenhum índice)
### Requirement: DB-554 — project_to_carrier_connections
O ai9 **MUST** manter a junção explícita projeto ↔ cedente (com `id` e timestamps próprios; o legado não
usa HABTM em lugar nenhum). Fonte legada: `db/migrate/20210301192607:3-8`, `20210402111120:2-8`,
`20210403154220:3-4`.

- **Colunas**: `id`, `project_id` int, `carrier_id` int, `legacy_id` int, `legacy_project_id` int,
  `legacy_carrier_id` int, timestamps.
- **Relações**: `belongs_to :project`, `belongs_to :carrier`; `Project has_many` com `restrict_with_error`.
- **Índices**: único em `legacy_id` (existente); no ai9 acrescentam-se índice único composto
  `[project_id, carrier_id]` e índices em `project_id` e `carrier_id`.

#### Scenario: vínculo duplicado entre projeto e cedente
- **GIVEN** o projeto X já vinculado ao cedente Y
- **WHEN** o mesmo par é inserido novamente
- **THEN** o índice único composto rejeita a inserção

#### Scenario: cedente vinculado bloqueia exclusão do projeto
- **GIVEN** um projeto com conexão a um cedente
- **WHEN** a exclusão do projeto é solicitada
- **THEN** a operação é recusada com erro que identifica a conexão

> Nota: corrige D-103 (legado: unicidade `carrier_id` × `project_id` só em aplicação e nenhum índice em `project_id`/`carrier_id`)

### Requirement: DB-555 — companies
O ai9 **MUST** portar a empresa como unidade de risco/operação abaixo do projeto, escopada por projeto
(DEC-07). Fonte legada: `db/migrate/20210510211117:3-9`, `20210511211918:7`.

- **Colunas**: `id`, `project_id` int, `title` string, `has_safegold_management` int d1, timestamps.
- **Relações**: `belongs_to :project` · `has_many :carriers, through: :project` ·
  `has_many :risk_controls` (restrict), `:receivables` (restrict).
- **Índices (ai9)**: índice único composto `[project_id, title]`; índice em `project_id`.
- A tabela **não tem** `is_active` — não existe desativação de empresa no legado.

#### Scenario: nome de empresa único dentro do projeto
- **GIVEN** a empresa "ACME" já cadastrada no projeto X
- **WHEN** outra empresa com o mesmo título é criada no mesmo projeto
- **THEN** o índice único composto rejeita a inserção, mas o mesmo título continua permitido em outro projeto

#### Scenario: empresa com controle de risco não é excluída
- **GIVEN** uma empresa com `risk_controls` associados
- **WHEN** a exclusão é solicitada
- **THEN** a operação é recusada

> Nota: corrige D-103 (legado: unicidade `title` × `project_id` só em aplicação, sem índices)

### Requirement: DB-556 — providers
O ai9 **MUST** portar o fornecedor escopado por projeto, incluindo o payload denormalizado da ReceitaWS.
Fonte legada: `db/migrate/20210325141909:3-15`, `20210426135539:3`, `20210504151249:3-18`; model
`app/models/provider.rb:2,42-43,97-110`.

- **Colunas**: `id`, `title` string, `resume` text, `user_id` int, `project_id` int, `is_active` int d1,
  Paperclip `logo_*` ×4, `integration_key` string, `cnpj`, `cpf` string, `abertura` date, `bairro`,
  `cep` string, `data_situacao` date, `email`, `fantasia`, `logradouro`, `complemento`, `municipio`,
  `nome`, `numero`, `situacao`, `telefone`, `uf` string, **`atividades` text (JSON escrito à mão)**,
  **`cnaes` text (YAML via `serialize`)**, timestamps.
- **Relações**: `belongs_to :project` · `has_many :renegotiations` (restrict).
- **Índices (ai9)**: únicos compostos `[project_id, cnpj]` e `[project_id, cpf]` (índices parciais,
  ignorando NULL); índice em `project_id`.
- No ai9 `atividades` e `cnaes` são normalizadas para **um único formato** (`jsonb`); o `limit: 16777214`
  das colunas é resquício MySQL sem efeito no PostgreSQL.

#### Scenario: dois formatos de serialização na origem
- **GIVEN** um fornecedor legado com `cnaes` em YAML e `atividades` em JSON
- **WHEN** o ETL importa o registro
- **THEN** ambas as colunas chegam ao ai9 como `jsonb` com o mesmo conteúdo semântico e nenhuma string YAML é persistida

#### Scenario: CNPJ duplicado no mesmo projeto
- **GIVEN** um fornecedor com CNPJ 00.000.000/0001-00 no projeto X
- **WHEN** outro fornecedor com o mesmo CNPJ é criado no projeto X
- **THEN** o índice único parcial rejeita a inserção; o mesmo CNPJ em outro projeto continua permitido

> Nota: corrige D-103 (legado: unicidade de `cnpj`/`cpf` por projeto só em aplicação, sem índices)

### Requirement: DB-557 — project_guarantees
O ai9 **MUST** portar as garantias do projeto por cedente e tipo. Fonte legada:
`db/migrate/20220627125026:3-12`.

- **Colunas**: `id`, `project_id` int, `carrier_id` int, `user_id` int, `guarantee_type_id` int,
  `title` string, `value` decimal(15,2) d0, `observation` string, timestamps.
- **Relações**: `belongs_to :project`, `:carrier`, `:user`, `:guarantee_type`.
- **Índices (ai9)**: índices em `project_id`, `carrier_id` e `guarantee_type_id`.

#### Scenario: tipo de garantia em uso
- **GIVEN** uma garantia vinculada a um `project_guarantee_type`
- **WHEN** a exclusão do tipo é solicitada
- **THEN** a operação é recusada (`restrict`)

#### Scenario: valor default
- **GIVEN** uma garantia criada sem `value`
- **WHEN** o registro é persistido
- **THEN** o valor gravado é `0` em decimal(15,2)

> Nota: corrige D-12 (legado: domínio financeiro sem FK e sem índice)

### Requirement: DB-558 — project_guarantee_types
O ai9 **MUST** portar o catálogo de tipos de garantia e **MUST** nascer com seed, porque o legado subiu
sem nenhum e a tela de garantia fica inutilizável com a tabela vazia. Fonte legada:
`db/migrate/20220627125208:3-10`.

- **Colunas**: `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int,
  timestamps.
- **Relações**: `has_many :guarantee` (restrict) · scope `active` = `is_active = 1`.
- **Índices (ai9)**: único em `title`.

#### Scenario: catálogo vazio no dia 1
- **GIVEN** um ambiente ai9 recém-provisionado
- **WHEN** o operador abre o cadastro de garantia
- **THEN** os tipos migrados do legado (ou o seed versionado, se a origem estiver vazia) já estão disponíveis para seleção

#### Scenario: tipo inativo não aparece
- **GIVEN** um tipo com `is_active = 0`
- **WHEN** a lista de tipos selecionáveis é montada
- **THEN** o tipo inativo não é oferecido, mas as garantias já existentes que o referenciam continuam legíveis

### Requirement: DB-559 — wallets
O ai9 **MUST** portar o catálogo de carteiras (produto financeiro do borderô) com o seed obrigatório de
produção. Fonte legada: `db/migrate/20210317140156:3-10`, `20210402111120:2-8`; seed `db/seeds.rb:166-177`.

- **Colunas**: `id`, `title` string, `user_id` int, `integration_key` string, `is_active` int d1,
  `legacy_id` int, timestamps.
- **Relações**: `has_many :receivables` (restrict).
- **Seed obrigatório**: ACC, ACE, Antecipação, Caução, Cheque, Comissária, Conta Garantida, Desconto,
  Domicílio, Fomento.
- **Índices**: único em `legacy_id` (existente); no ai9 acrescenta-se único em `title`.

#### Scenario: carteira em uso não pode ser excluída
- **GIVEN** uma carteira referenciada por recebíveis
- **WHEN** a exclusão é solicitada
- **THEN** a operação é recusada

#### Scenario: seed obrigatório presente
- **GIVEN** o ambiente ai9 após a carga inicial
- **WHEN** as carteiras são listadas
- **THEN** as 10 carteiras do seed de produção existem, com `integration_key` estável

### Requirement: DB-560 — receivable_kinds
O ai9 **MUST** portar o catálogo de tipos de recebível com o seed obrigatório. Fonte legada:
`db/migrate/20210317140206:3-11`, `20210402111120:2-8`; seed `db/seeds.rb:179-185`.

- **Colunas**: `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int,
  `legacy_id` int, timestamps.
- **Relações**: `has_many :receivables` (restrict).
- **Seed obrigatório**: Cheque, Duplicata, Cartão de crédito, ACC, PAC.
- **Índices**: único em `legacy_id` (existente); no ai9 acrescenta-se único em `title`.

#### Scenario: tipo referenciado por borderô
- **GIVEN** um tipo de recebível usado por um borderô
- **WHEN** a exclusão do tipo é solicitada
- **THEN** a operação é recusada

#### Scenario: seed obrigatório presente
- **GIVEN** o ambiente ai9 após a carga inicial
- **WHEN** os tipos de recebível são listados
- **THEN** os 5 tipos do seed de produção existem

### Requirement: DB-561 — resource_kinds
O ai9 **MUST** portar o catálogo de tipos de recurso, com seed obrigatório e **MUST** passar a validar a
referência `receivable_entries.resource_kind_id`, hoje não validada. Fonte legada:
`db/migrate/20210317140213:3-12`; seed `db/seeds.rb:197-203`.

- **Colunas**: `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int,
  `is_conta_corrente` int d1, `is_unique` int d1, timestamps.
- **Relações**: `has_many :receivables` (restrict).
- **Índices (ai9)**: único em `title`.
- Sem `legacy_id`: a tabela não veio do ETL de 2021.

#### Scenario: referência inválida em borderô
- **GIVEN** um borderô cujo `resource_kind_id` não existe na tabela
- **WHEN** o registro é salvo no ai9
- **THEN** a gravação é recusada pela FK, em vez de persistir referência inválida como no legado

#### Scenario: seed obrigatório presente
- **GIVEN** o ambiente ai9 após a carga inicial
- **WHEN** os tipos de recurso são listados
- **THEN** os tipos do seed de produção existem

> Nota: corrige D-12 (legado: `receivable_entry.rb` valida `resource_source_id` mas não `resource_kind_id`, e não há FK)

### Requirement: DB-562 — resource_sources
O ai9 **MUST** portar o catálogo de origens de recurso com o seed obrigatório. Fonte legada:
`db/migrate/20210317140220:3-11`, `20210402111120:2-8`; seed `db/seeds.rb:187-195`.

- **Colunas**: `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int,
  `legacy_id` int, timestamps.
- **Relações**: `has_many :receivables` (restrict).
- **Índices**: único em `legacy_id` (existente); no ai9 acrescenta-se único em `title`.

#### Scenario: origem em uso
- **GIVEN** uma origem referenciada por recebíveis
- **WHEN** a exclusão é solicitada
- **THEN** a operação é recusada

#### Scenario: seed obrigatório presente
- **GIVEN** o ambiente ai9 após a carga inicial
- **WHEN** as origens de recurso são listadas
- **THEN** as 7 origens do seed de produção existem

### Requirement: DB-563 — movement_kinds
O ai9 **MUST** portar o catálogo de tipos de movimento/tarifa (17 linhas de seed) e **MUST** remover a
associação quebrada `has_many :receivables` que aponta para a coluna inexistente
`receivable_entries.movement_kind_id`. Fonte legada: `db/migrate/20210317151301:3-16`,
`20210402111120:2-8`; model `app/models/movement_kind.rb:2,27-28`; seed `db/seeds.rb:205-223`.

- **Colunas**: `id`, `title` string, `user_id` int, `integration_key` string, `is_operation` int d0,
  `is_title` int d0, `is_active` int d1, `is_advalorem` int d0, `is_desagio` int d0, `is_iof` int d0,
  `is_liquidation` int d0, `kind` string, `legacy_id` int, timestamps.
- **Relações**: `has_many :receivable_taxes` (restrict).
- **`kind`** é enum-string pt-BR: `"Crédito"` / `"Débito"`.
- **Índices**: único em `legacy_id` (existente); no ai9 acrescenta-se único em `title`.

#### Scenario: associação inexistente removida
- **GIVEN** o model legado declarando `has_many :receivables, foreign_key: :movement_kind_id, class_name: "ReceivableEntry"`
- **WHEN** o model equivalente é escrito no ai9
- **THEN** a associação não existe, porque `receivable_entries` não possui a coluna `movement_kind_id`

#### Scenario: seed de 17 tipos de tarifa
- **GIVEN** o ambiente ai9 após a carga inicial
- **WHEN** os tipos de movimento são listados
- **THEN** os 17 tipos do seed de produção existem com as flags `is_advalorem`/`is_desagio`/`is_iof`/`is_liquidation` preservadas

### Requirement: DB-564 — receivable_entries
O ai9 **MUST** portar a maior tabela transacional do sistema — o borderô, com ~70 colunas, quase todas
derivadas e recalculadas em aplicação. Fonte legada: `db/migrate/20210315183541:3-67`,
`20210402111120:2-8`, `20210403171744:3`, `20210511211918:6`, `20220322123523:3-6`, `20220330140334:3`,
`20220610122917:3-4`; model `app/models/receivable_entry.rb:2`, `app/models/entry.rb:11-12`.

- **Chaves**: `user_id`, `project_id`, `carrier_id`, `wallet_id`, `receivable_kind_id`,
  `resource_source_id`, `resource_kind_id`, `company_id`, `risk_operation_type_id`,
  `risk_operation_subtype_id`, `legacy_id`.
- **Identificação e datas**: `date` date, **`nro_bordero` string** (era int, alterada em
  `20210403171744`), `data_credito` date, `contrato` string, `status` string
  (enum-string pt-BR `"Diferença"` / `"OK"`), `observacoes` text, `description` text,
  `has_safegold_management` int d1, timestamps.
- **Contagens**: `qtd_titulos`, `qtd_recusada`, `qtd_final` int.
- **decimal(15,2)**: `valor_bruto`, `vlr_bruto_recusado`, `vlr_bruto_final`, `valor_total_tarifas`,
  `valor_liquido`, `calc_valor_liq_correto`, `recompra` d0, `retencao` d0, `fomento` d0, `outros` d0,
  `total_deducoes` d0, `vlr_liq_recebido`, `tarifas_ad_valorem` d0, `tarifas_desagio` d0,
  `tarifas_iof` d0, `tarifas_outras` d0, `multiplicador_pm_empresa`, `multiplicador_pm_float`.
- **float (~30 colunas de taxa)**: `prz_med_pond_emp`, `prz_med_pond_bco`, `float_calculado`,
  `float_acordado`, `diferenca_float`, `checagem_iof`, `cst_efetivo_acordado`, `dif_calc_vlr_liq`,
  `recompra_percent`, `retencao_percent`, `fomento_percent`, `outros_percent`,
  `taxa_desconto_nominal_desagio_advalorem_bancos`, `taxa_desconto_nominal_despesas_bancos`,
  `taxa_desconto_nominal_despesas_iof_bancos`, `custo_efetivo_pz_med_banco`,
  `custo_efetivo_pz_med_banco_sem_iof`, `taxa_desconto_nominal_desagio_advalorem_emp`,
  `taxa_desconto_nominal_despesas_emp`, `taxa_desconto_nominal_despesas_iof_emp`,
  `custo_efetivo_pz_med_emp`, `custo_efetivo_pz_med_emp_sem_iof`, `custo_efetivo_sem_float`,
  `custo_efetivo_com_float_total`, `custo_efetivo_com_float_sem_iof`, `nominal_tax`,
  `nominal_tax_check`, `nominal_tax_check_with_float`.
- **Relações**: `belongs_to :user`, `:project`, `:carrier`, `:wallet` (herdadas de `Entry`), `:company`,
  `:risk_operation_type`, `:risk_operation_subtype` · `has_many :taxes` (ReceivableTax, destroy) ·
  `has_one :risk_operation` (destroy).
- **Índices**: único em `legacy_id` (existente); no ai9 acrescentam-se índices em `project_id`,
  `carrier_id`, `company_id`, `date`, `wallet_id` e composto `[project_id, date]`.
- `self.inheritance_column = :_type_disabled` — a tabela **não é STI**.

#### Scenario: precisão financeira replicada
- **GIVEN** um borderô legado com taxas em float e valores em decimal(15,2)
- **WHEN** o ai9 recalcula os campos derivados
- **THEN** a sequência de operações, casts e arredondamentos reproduz o resultado do legado dígito a dígito

#### Scenario: divisão por zero não corrompe o registro
- **GIVEN** um borderô com `valor_liquido = 0` ou `prz_med_pond_emp = 0`
- **WHEN** o servidor calcula os campos derivados
- **THEN** a validação do servidor recusa a gravação de `Infinity`/`NaN` e devolve erro, em vez de persistir registro corrompido

#### Scenario: busca por projeto e data usa índice
- **GIVEN** a tabela de borderôs com o volume histórico desde 2016
- **WHEN** a listagem filtra por projeto e intervalo de datas
- **THEN** a consulta usa o índice composto `[project_id, date]` e não faz varredura sequencial

> Nota: DEC-02 — precisao legada preservada por decisao do usuario
> Nota: corrige D-10 (legado: guardas de divisão por zero só no cliente, servidor gravava `Infinity`/`NaN`) e D-12 (legado: nenhum índice além de `legacy_id` na maior tabela transacional)

### Requirement: DB-565 — receivable_taxes
O ai9 **MUST** portar as tarifas do borderô, preservando a denormalização de `title` e das flags vindas
de `movement_kinds`. Fonte legada: `db/migrate/20210323134328:3-13`, `20210402111120:2-8`.

- **Colunas**: `id`, `receivable_entry_id` int, `movement_kind_id` int, `value` decimal(15,2) d0,
  `title` string, `is_advalorem` int d0, `is_desagio` int d0, `is_iof` int d0, `legacy_id` int,
  timestamps.
- **Relações**: `belongs_to :receivable` (via `receivable_entry_id`), `belongs_to :movement_kind`.
- **Índices**: único em `legacy_id` (existente); no ai9 acrescentam-se índices em `receivable_entry_id`
  e `movement_kind_id`.

#### Scenario: leitura das tarifas de um borderô
- **GIVEN** um borderô com N tarifas
- **WHEN** o cálculo do borderô lê as tarifas (o legado fazia 4 leituras por save, sem índice)
- **THEN** cada leitura usa o índice em `receivable_entry_id`

#### Scenario: exclusão do borderô leva as tarifas
- **GIVEN** um borderô com tarifas associadas
- **WHEN** o borderô é excluído
- **THEN** as tarifas são removidas em cascata e nenhuma tarifa órfã permanece

> Nota: corrige D-12 (legado: `receivable_taxes` lida 4× por save sem índice em `receivable_entry_id`)

### Requirement: DB-566 — availability_templates
O ai9 **MUST** portar os templates de disponibilidade (STI `GlobalAvailabilityTemplate` /
`ProjectAvailabilityTemplate`), preservando a hierarquia de 3 níveis, e **MUST** substituir a FK
`job_id → delayed_jobs` por estado de processamento na própria entidade. Fonte legada:
`db/migrate/20210420180734:3-27`, `20220224142653:3-4`, `20220225133130:3-5`, `20220325134030:3`,
`20220818194956:3`; models `app/models/availability_template.rb:32-46`,
`app/models/project_availability_template.rb:33,44,52`.

- **Colunas**: `id`, `title` string, `project_id` int, **`type` string (STI)**, `is_global` int d0,
  `is_mandatory` int d0, `is_active` int d1, `global_availability_template_id` int,
  `operation_type` string (siglas `"C"`/`"D"`/`"S"`/`"M"`), `deadline_type` string (`"CP"`/`"LP"`),
  `user_id` int, `is_cumulative` int d1, `numeric_first_level`, `numeric_second_level`,
  `numeric_third_level` int, `max_level` int d0, `is_upper_level` int d0, `top_parent_id` int d0,
  `should_insert_on_existing_projects` int d1, **`position` string** (`"1"`, `"1.2"`, `"1.2.3"`),
  `parent_level` int, **`parent_position` string**, `parent_template_id` int, `is_locked` int d0,
  `locked_at` datetime, `locked_message` string, `is_adjusted` int d0, `job_report` text,
  `job_state` string, timestamps.
- **Relações**: auto-relações `belongs_to :parent_template`, `:top_parent` ·
  `has_many :child_templates` (destroy), `:availability_templates` via `top_parent_id` (destroy) ·
  `GlobalAvailabilityTemplate has_many :project_templates` · `ProjectAvailabilityTemplate belongs_to
  :project`, `:global_template` e `has_many :entries` (restrict).
- **Índices (ai9)**: índices em `project_id`, `type`, `parent_template_id`, `top_parent_id` e
  `global_availability_template_id`; único composto por subclasse conforme as validações do legado.
- `top_parent_id` tem default `0` no legado (valor mágico) e **MUST** ser normalizado para NULL no ai9.

#### Scenario: quatro representações da mesma árvore
- **GIVEN** um template com `position`, `numeric_*_level`, `parent_template_id` e `top_parent_id` divergentes na origem
- **WHEN** o ETL importa o template
- **THEN** a hierarquia é reconstruída a partir de `parent_template_id` e as demais representações são recalculadas de forma consistente, com as divergências listadas no relatório

#### Scenario: valor mágico zero em top_parent_id
- **GIVEN** um template legado com `top_parent_id = 0`
- **WHEN** o registro é migrado
- **THEN** o campo chega ao ai9 como NULL, e nenhuma FK aponta para um id inexistente

#### Scenario: template bloqueado sem referência à fila
- **GIVEN** um template em processamento
- **WHEN** o estado do processamento é consultado
- **THEN** o estado vem de colunas da própria tabela e não de `job_id` apontando para a tabela de jobs

> Nota: corrige D-80 (legado: `project_availability_templates.job_id` era FK para `delayed_jobs`, deixando itens `locked` para sempre se o worker não rodasse) e D-103 (legado: nenhum índice)

### Requirement: DB-567 — availability_entries
O ai9 **MUST** portar as entradas de disponibilidade — a maior tabela do sistema, com uma linha por
template × projeto × data — e **MUST** materializar a unicidade composta como índice único no banco.
Fonte legada: `db/migrate/20210420180813:3-12`, `20210511211918:4`, `20210804175519:3`,
`20220818150945:3`, `20220818201713:3`; model `app/models/availability_entry.rb:2,12`.

- **Colunas**: `id`, `title` string, `user_id` int, `project_id` int, `availability_template_id` int,
  `value` decimal(15,2) d0, `virtual_value` decimal(15,2) d0, `original_value` decimal(15,2) d0,
  `date` date, `company_id` int, `has_safegold_management` int d1, timestamps.
- **Relações**: `belongs_to :project`, `belongs_to :availability_template` (aponta para
  `ProjectAvailabilityTemplate`).
- **Índices (ai9)**: índice **único** composto `[date, project_id, company_id, availability_template_id]`;
  índices em `project_id` e `availability_template_id`.
- As três colunas de valor têm semânticas distintas (valor corrente, valor virtual e valor original
  antes do decaimento) e **MUST** ser preservadas separadamente.

#### Scenario: duplicata sob concorrência
- **GIVEN** duas requisições concorrentes criando a entrada da mesma data, projeto, empresa e template
- **WHEN** ambas tentam gravar
- **THEN** o índice único no banco permite apenas uma e a segunda recebe erro, em vez de gerar duplicata como no legado

#### Scenario: três valores preservados
- **GIVEN** uma entrada com `value`, `virtual_value` e `original_value` diferentes entre si
- **WHEN** a entrada é migrada
- **THEN** os três valores chegam ao ai9 sem fusão nem sobrescrita

> Nota: corrige D-103 (legado: unicidade `date` × `[project_id, company_id, availability_template_id]` só em aplicação, sem índice único no banco)

### Requirement: DB-568 — renegotiations
O ai9 **MUST** portar a renegociação com as suas 20 colunas monetárias derivadas e **MUST** declarar a
relação com `companies`, hoje validada como obrigatória sem nenhum `belongs_to`. Fonte legada:
`db/migrate/20210324173930:3-35`, `20210503202015:3`, `20210511211918:5`, `20210512151746:3`,
`20220407163633:3`, `20220429122226:3-13`, `20220620134050:3-4`; model `app/models/renegotiation.rb:21,41-49`.

- **Chaves e identificação**: `id`, `provider_name` string (denormalizado de `providers.title`),
  `provider_id` int, `project_id` int, `company_id` int, `kind` string, `integration_key` string,
  `title` string, `origin` string, `observation` text, `state` string, `attachments_count` int,
  `has_safegold_management` int d1, `monetary_correction` string, timestamps.
- **decimal(15,2) d0**: `original_value`, `original_pending_value`, `additional_value`, `total_debt`,
  `paid_value`, `remaining_value`, `installments_main_value` (renomeada de `total_value` em
  `20220429122226:4`), `correct_value`, `current_installment_value`, `current_value`,
  `installments_interest_value`, `installments_main_value_with_interest`,
  `installments_monetary_correction_value`, `installments_main_value_with_interest_cm`, `main_value`,
  `paid_value_with_interest_cm`, `pending_main_value`, `late_payment_value`, `desagio_value`,
  `total_value_with_desagio`.
- **Datas**: `renegotiation_date`, `first_due_date`, `last_due_date`.
- **float**: `interest_rate_correction` d0, `operation_interest_rate`, `paid_percent` d0.
- **Contagens**: `grace_period` int d0, `installments_count` int, `paid_installments`,
  `overdue_installments`, `due_installments` int d0.
- **Enums-string pt-BR**: `state` ∈ {`Liquidado`, `Pago`, `Inconsistente`, `Sem parcela cadastrada`};
  `kind` ∈ {`Financeiro`, `Operacional`, `Tributario`, `Trabalhista`}.
- **Relações**: `belongs_to :project`, `:provider` e (novo no ai9) `:company` ·
  `has_many :installments` (restrict), `:payments` (restrict), `:attachments` (destroy).
- **Índices (ai9)**: índices em `project_id`, `provider_id`, `company_id` e `state`;
  `attachments_count` recebe NOT NULL default 0.

#### Scenario: company_id obrigatório com relação declarada
- **GIVEN** uma renegociação sem `company_id`
- **WHEN** o registro é salvo
- **THEN** a validação recusa a gravação e a FK garante que o `company_id` gravado existe de fato

#### Scenario: contador de anexos sem NULL
- **GIVEN** uma renegociação legada com `attachments_count` NULL
- **WHEN** o registro é migrado
- **THEN** o contador é recalculado pela contagem real de anexos e gravado como inteiro não nulo

#### Scenario: precisão dos totais preservada
- **GIVEN** uma renegociação com `paid_percent` e `operation_interest_rate` em float
- **WHEN** o ai9 recalcula os totais derivados
- **THEN** os valores exibidos são idênticos aos do legado

> Nota: DEC-02 — precisao legada preservada por decisao do usuario
> Nota: corrige D-103 (legado: `company_id` validado como obrigatório sem `belongs_to`, `attachments_count` sem default e nenhum índice)

### Requirement: DB-569 — renegotiation_installments
O ai9 **MUST** portar as parcelas da renegociação e **MUST** garantir a unicidade de `batch_token` e do
par `[renegotiation_id, due_date]` por índice no banco. Fonte legada:
`db/migrate/20210324174436:3-18`, `20220429122346:3-10`; model
`app/models/renegotiation_installment.rb:96-100`.

- **Colunas**: `id`, `renegotiation_id` int, `due_date` date, `installment` int, `month`, `year` int,
  `batch_token` string, `is_paid` int d0, `color` string, timestamps.
- **decimal(15,2) d0**: `main_value` (renomeada de `value`), `paid_value`, `pending_value`, `saldo`,
  `interest_value`, `main_value_with_interest`, `monetary_correction_value`,
  `main_value_with_interest_cm`, `late_payment_value`, `installment_total_value`.
- **Relações**: `belongs_to :renegotiation` · `has_many :payments` (restrict).
- **Índices (ai9)**: único composto `[renegotiation_id, due_date]`; único em `batch_token`; índice em
  `renegotiation_id`.
- `saldo` (pt) e `pending_value` (en) coexistem com semânticas distintas e **MUST** ser preservadas;
  `color` é apresentação persistida e é migrada como está.

#### Scenario: colisão de batch_token sob concorrência
- **GIVEN** duas gerações de lote concorrentes sorteando o mesmo `batch_token`
- **WHEN** ambas tentam gravar
- **THEN** o índice único rejeita a segunda, em vez de depender da verificação por SELECT do legado

#### Scenario: duas parcelas no mesmo vencimento
- **GIVEN** uma renegociação com parcela vencendo em 10/03/2026
- **WHEN** outra parcela com o mesmo vencimento é criada na mesma renegociação
- **THEN** o índice único composto rejeita a inserção

> Nota: corrige D-103 (legado: unicidade `due_date` × `renegotiation_id` e do `batch_token` só em aplicação, com corrida possível)

### Requirement: DB-570 — renegotiation_payments
O ai9 **MUST** portar os pagamentos de parcela, registrando explicitamente a mudança de semântica da
coluna renomeada em 04/2022. Fonte legada: `db/migrate/20210324174615:3-12`, `20210426130102:3`,
`20220429122419:3-6`.

- **Colunas**: `id`, `renegotiation_id` int, `renegotiation_installment_id` int,
  `installment_paid_value_with_interest_cm` decimal(15,2) d0 (renomeada de `value` em
  `20220429122419:3`), `date` date, `days_late` int, `payment_number` int d1,
  `late_payment_value` decimal(15,2) d0, `total_paid_value` decimal(15,2) d0, timestamps.
- **Relações**: `belongs_to :renegotiation`, `belongs_to :renegotiation_installment`.
- **Índices (ai9)**: índices em `renegotiation_id` e `renegotiation_installment_id`.

#### Scenario: pagamento anterior a 04/2022
- **GIVEN** um pagamento gravado antes da renomeação, quando a coluna guardava só o principal
- **WHEN** o ETL importa o registro
- **THEN** o valor é migrado sem reinterpretação e a faixa de datas afetada é sinalizada no relatório de reconciliação

#### Scenario: exclusão de parcela com pagamento
- **GIVEN** uma parcela com pagamento associado
- **WHEN** a exclusão da parcela é solicitada
- **THEN** a operação é recusada (`restrict`)

> Nota: corrige D-12 (legado: domínio financeiro sem FK nem índice)
### Requirement: DB-571 — renegotiation_attachments
O ai9 **MUST** portar os anexos de renegociação e **MUST** armazená-los em storage privado com URL
assinada, nunca em diretório público. Fonte legada: `db/migrate/20210503195535:3-11`; model
`app/models/renegotiation_attachment.rb:4-13,38-40`.

- **Colunas**: `id`, `renegotiation_id` int, `user_id` int, `title` string, Paperclip `file_file_name`,
  `file_content_type`, `file_file_size` int, `file_updated_at` datetime, timestamps.
- **Relações**: `belongs_to :renegotiation` com `counter_cache: :attachments_count`.
- **Índices (ai9)**: índices em `renegotiation_id` e `user_id`.
- **Limites no servidor**: máximo de 4 arquivos por renegociação e 5 MB por arquivo, vindos de
  configuração (ver `ops-config`), não de constante de código.

#### Scenario: anexo não é público
- **GIVEN** um anexo de renegociação (documento financeiro do cliente) armazenado no ai9
- **WHEN** alguém acessa a URL do arquivo sem sessão válida
- **THEN** o acesso é negado, porque o arquivo vive em storage privado e só é servido por URL assinada de vida curta

#### Scenario: limite de anexos aplicado no servidor
- **GIVEN** uma renegociação que já possui 4 anexos
- **WHEN** um POST direto tenta enviar o quinto arquivo, sem passar pela interface
- **THEN** o servidor recusa o upload, em vez de aceitá-lo como no legado, onde o limite existia só em JavaScript

> Nota: corrige D-82 (legado: `do_not_validate_attachment_file_type`, spoof detector desligado, limites só no cliente e arquivos servidos de `public/` sem autenticação)

### Requirement: DB-572 — risk_controls
O ai9 **MUST** portar os controles de risco por empresa × cedente, preservando **as duas gerações de
modelo que coexistem** na tabela: as colunas `limite_*`/`taxa_*` por tipo fixo (2021) e o par
`limite`/`taxa` + `risk_operation_type_id` (2022). Fonte legada: `db/migrate/20210510211438:3-16`,
`20210511211918:8-9`, `20210603125803:3`, `20220223143338:3`, `20220611152145:3-8`.

- **Colunas**: `id`, `company_id` int, `carrier_id` int, `project_id` int, `title` string,
  `is_active` int d1, `risk_operation_type_id` int, `user_id` int, `has_safegold_management` int d1,
  timestamps.
- **decimal(15,2) d0**: `limite_auto_liquidaveis`, `limite_fomento`, `limite_comissaria`,
  `limite_intercompany`, `limite`, `original_balance`, `original_balance_pre`.
- **float d0**: `taxa_auto_liquidaveis`, `taxa_fomento`, `taxa_comissaria`, `taxa_intercompany`, `taxa`.
- **Relações**: `belongs_to :company`, `:carrier`, `:project`, `:risk_operation_type` ·
  `has_many :risk_entries` (restrict), `:risk_operations` (restrict) · scopes `active`/`inactive`.
- **Índices (ai9)**: único composto `[carrier_id, company_id, risk_operation_type_id]`; índices em
  `project_id` e `company_id`.

#### Scenario: modelo antigo ainda com dado
- **GIVEN** um controle criado antes de 06/2022, com valores nas colunas `limite_*`/`taxa_*` e `limite`/`taxa` zerados
- **WHEN** o controle é migrado
- **THEN** as colunas antigas são preservadas com o seu conteúdo e a origem do limite exibido é a mesma do legado

#### Scenario: controle duplicado
- **GIVEN** um controle já existente para o par empresa × cedente e um tipo de operação
- **WHEN** outro controle idêntico é criado
- **THEN** o índice único composto rejeita a inserção

> Nota: DEC-02 — precisao legada preservada por decisao do usuario
> Nota: corrige D-103 (legado: unicidade `carrier_id` × `[company_id, risk_operation_type_id]` só em aplicação, sem índices)

### Requirement: DB-573 — risk_entries
O ai9 **MUST** portar as posições diárias de risco (uma linha por controle × dia), preservando as
renomeações de 03/2022 e o campo denormalizado `risk_control_title`. Fonte legada:
`db/migrate/20210510211736:3-19`, `20210511211918:10-11`, `20210603125803:4`, `20220321180205:3-8`,
`20220325145251:3-5`.

- **Colunas**: `id`, `risk_control_id` int, `company_id` int, `project_id` int, `date` date,
  `observacoes` string, `risk_control_title` string, `has_safegold_management` int d1, timestamps.
- **decimal(15,2) d0**: `vencidos_value`, `a_vencer_value`, `total_carteira_value`, `liquidacao_value`,
  `descontos_value`, `total_reducoes_value`, `fomento_total_value` (renomeada de `fomento_value`),
  `intercompany_total_value` (renomeada), `comissaria_total_value` (renomeada),
  `comissaria_vencidos_value`, `comissaria_a_vencer_value`, `fomento_vencidos_value`,
  `fomento_a_vencer_value`, `intercompany_vencidos_value`, `intercompany_a_vencer_value`.
- **Relações**: `belongs_to :company`, `:risk_control`, `:project`.
- **Índices (ai9)**: único composto `[date, risk_control_id, company_id]`; índice em
  `[project_id, date]`.

#### Scenario: duas posições no mesmo dia
- **GIVEN** uma posição já registrada para o controle X, empresa Y e data D
- **WHEN** outra posição com a mesma tripla é criada
- **THEN** o índice único composto rejeita a inserção

#### Scenario: título denormalizado do controle
- **GIVEN** uma posição com `risk_control_title` gravado no momento da criação
- **WHEN** o título do controle muda depois
- **THEN** a posição mantém o título histórico, preservando o comportamento do legado

> Nota: corrige D-103 (legado: unicidade `date` × `[risk_control_id, company_id]` só em aplicação, sem índices)

### Requirement: DB-574 — risk_operation_types
O ai9 **MUST** portar o catálogo de tipos de operação de risco **com o seed ativo de produção**, que é
dado obrigatório no dia 1. Fonte legada: `db/migrate/20220606124734:3-17`; seed `db/seeds.rb:18,315-321`.

- **Colunas**: `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int,
  `is_default` int d0, `allow_manual_operations` int d1, `allow_receivable_entries` int d1,
  `has_pre_faturamento` int d0, timestamps.
- **Relações**: `has_many :operations` (restrict), `has_many :subtypes` (destroy) · scopes `manual`,
  `receivable`, `active`, `with_pre`.
- **Seed obrigatório**: Fomento, Comissária, Intercompany, Auto Liquidável.
- **Índices (ai9)**: único em `title`; único em `integration_key`.

#### Scenario: seed presente no dia 1
- **GIVEN** um ambiente ai9 recém-carregado
- **WHEN** os tipos de operação de risco são listados
- **THEN** os 4 tipos do seed existem, com as flags `allow_manual_operations`, `allow_receivable_entries` e `has_pre_faturamento` iguais às do legado

#### Scenario: user_id hardcoded no seed
- **GIVEN** que o seed legado grava `user_id: 1` fixo
- **WHEN** o seed versionado do ai9 roda
- **THEN** o dono dos registros de catálogo é resolvido por configuração e não por id fixo, e a ausência do usuário não quebra a carga

### Requirement: DB-575 — risk_operation_subtypes
O ai9 **MUST** portar os subtipos de operação de risco e **MUST** declarar a relação `pair_id`, que no
legado apontava para outro subtipo sem nenhum `belongs_to`. Fonte legada:
`db/migrate/20220621131905:3-18`.

- **Colunas**: `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int,
  `is_default` int d0, `pair_id` int, `risk_operation_type_id` int, `is_pre` int d0,
  `allow_manual_operations` int d1, `allow_receivable_entries` int d1, timestamps.
- **Relações**: `belongs_to :operation_type` (RiskOperationType), `has_many :operations` (restrict),
  e (novo no ai9) auto-relação `pair` via `pair_id`.
- **Índices (ai9)**: únicos compostos `[title, risk_operation_type_id]` e `[is_pre, risk_operation_type_id]`;
  índice em `pair_id`.
- Sem seed no legado: se a origem estiver vazia, o ai9 sobe sem subtipos e isso é registrado no relatório.

#### Scenario: par pré/pós-faturamento
- **GIVEN** um subtipo `is_pre = 1` apontando para o seu par por `pair_id`
- **WHEN** o subtipo é migrado
- **THEN** a relação de par existe como associação declarada e a FK garante que o par referenciado existe

#### Scenario: subtipo duplicado no mesmo tipo
- **GIVEN** um subtipo "Fomento pré" no tipo Fomento
- **WHEN** outro subtipo com o mesmo título é criado no mesmo tipo
- **THEN** o índice único composto rejeita a inserção

> Nota: corrige D-103 (legado: `pair_id` sem `belongs_to` e unicidades compostas só em aplicação)

### Requirement: DB-576 — risk_operations
O ai9 **MUST** portar as operações de risco e **MUST** declarar a relação `risk_control_id`, hoje
validada como obrigatória sem `belongs_to`. Fonte legada: `db/migrate/20220607123547:3-30`,
`20220802225011:20`; model `app/models/risk_operation.rb:62`.

- **Colunas**: `id`, `title` string, `user_id` int, `operation_type_id` int, `operation_subtype_id` int,
  `project_id` int, `company_id` int, `carrier_id` int, `risk_control_id` int, `receivable_id` int,
  `receipt_id` int, `original_id` int, `pair_id` int, `contract_number` string, `issue_date` date,
  `due_date` date, `original_due_date` date, `operation_value` decimal(15,2) d0, `original_balance`
  decimal(15,2) d0, `balance` decimal(15,2) d0, `agreed_rate` float d0, `observation` string,
  `is_on_variable` int d0, `is_ended` int d0, timestamps.
- **Relações**: `belongs_to :company`, `:carrier`, `:project`, `:user`, `:operation_type`,
  `:operation_subtype`, `:receivable`, `:original_operation` (via `original_id`) e (novo no ai9)
  `:risk_control` · `has_one :pair_operation` (via `pair_id`) · `has_one :receipt` (restrict) ·
  `has_many :movements` (destroy), `:renovations` (via `original_id`), `:extensions` · scope
  `available_for_receipt` (`receipt_id: nil`).
- **Índices (ai9)**: índices em `project_id`, `company_id`, `carrier_id`, `risk_control_id`,
  `receivable_id`, `receipt_id`, `original_id`, `due_date`.
- A redundância bidirecional recibo↔operação (`risk_operations.receipt_id` e
  `receipts.operation_id/operation_type`) é preservada, com o ETL garantindo que as duas direções
  concordem.

#### Scenario: relação com o controle de risco declarada
- **GIVEN** uma operação de risco com `risk_control_id` obrigatório
- **WHEN** o registro é gravado com um `risk_control_id` inexistente
- **THEN** a FK recusa a gravação, em vez de aceitar referência solta como no legado

#### Scenario: renovação não encerra a original
- **GIVEN** uma operação renovada, com `original_id` apontando para a operação de origem
- **WHEN** as duas são consultadas
- **THEN** ambas permanecem ativas e consomem limite simultaneamente, reproduzindo o comportamento do legado

#### Scenario: recibo consistente nas duas direções
- **GIVEN** uma operação com `receipt_id` preenchido
- **WHEN** o ETL verifica a direção inversa em `receipts.operation_id`/`operation_type`
- **THEN** divergências entre as duas direções são contadas e reportadas antes da inserção

> Nota: corrige D-103 (legado: `risk_control_id` validado obrigatório sem `belongs_to` e nenhum índice na tabela)

### Requirement: DB-577 — risk_operation_extensions
O ai9 **MUST** portar o histórico de prorrogação de vencimento e **MUST** definir política de exclusão
explícita, que o legado não tinha. Fonte legada: `db/migrate/20220616181724:3-12`.

- **Colunas**: `id`, `risk_operation_id` int, `user_id` int, `original_due_date` date,
  `new_due_date` date, `observation` string, timestamps.
- **Relações**: `belongs_to :operation` (via `risk_operation_id`); no ai9,
  `RiskOperation has_many :extensions, dependent: :destroy`.
- **Índices (ai9)**: índice em `risk_operation_id`.

#### Scenario: exclusão da operação não deixa órfãos
- **GIVEN** uma operação de risco com prorrogações registradas
- **WHEN** a operação é excluída
- **THEN** as prorrogações são removidas junto, em vez de virarem órfãs como no legado

#### Scenario: histórico preservado
- **GIVEN** uma operação prorrogada duas vezes
- **WHEN** o histórico é consultado
- **THEN** as duas linhas aparecem com `original_due_date` e `new_due_date` de cada prorrogação

> Nota: corrige D-103 (legado: `has_many :extensions` sem `dependent:`, gerando órfãos ao apagar a operação)

### Requirement: DB-578 — risk_movement_types
O ai9 **MUST** portar o catálogo de tipos de movimento de risco **com o seed ativo de produção** e
**MUST** unificar as duas colunas que codificam o mesmo enum. Fonte legada:
`db/migrate/20220606160027:3-16`; model `app/models/risk_movement_type.rb:29-33`; seed
`db/seeds.rb:19,323-332`.

- **Colunas**: `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int,
  `is_default` int d0, `is_system_exclusive` int d0, `credit_type` string (siglas `"C"`/`"D"`),
  `credit_type_description` string (`"Crédito"`/`"Débito"`), `is_transfer` int d0, timestamps.
- **Relações**: referenciado por `risk_movements.movement_type_id` · scope `manual`.
- **Seed obrigatório (8 linhas)**: Juros, AdValorem, IOF, Liberação do Recurso, Liquidação, Juros de
  Mora, Transferência Recebida, Valor Transferido.
- **Índices (ai9)**: único em `title`.

#### Scenario: enum único para crédito e débito
- **GIVEN** um tipo legado com `credit_type = "C"` e `credit_type_description = "Crédito"`
- **WHEN** o tipo é migrado
- **THEN** existe um único campo de enum no ai9 e o rótulo exibido é derivado dele, sem uma segunda coluna a manter em sincronia

#### Scenario: seed presente no dia 1
- **GIVEN** um ambiente ai9 recém-carregado
- **WHEN** os tipos de movimento de risco são listados
- **THEN** os 8 tipos do seed existem

### Requirement: DB-579 — risk_movements
O ai9 **MUST** portar os movimentos de operação de risco e **MUST** renomear a coluna `order` (palavra
reservada em SQL) para `sequence`. Fonte legada: `db/migrate/20220608162424:3-21`.

- **Colunas**: `id`, `user_id` int, **`order` int → `sequence` no ai9**, `date` date,
  `movement_type_id` int, `movement_value` decimal(15,2) d0, `balance` decimal(15,2) d0,
  `observation` string, `project_id` int, `company_id` int, `carrier_id` int, `risk_operation_id` int,
  `receivable_id` int, `pair_id` int, timestamps.
- **Relações**: `belongs_to :company`, `:carrier`, `:project`, `:user`, `:movement_type`,
  `:risk_operation` · `has_one :pair_movement` (via `pair_id`) · `delegate :credit_type, to: :movement_type`.
- **Índices (ai9)**: índices em `risk_operation_id`, `[risk_operation_id, sequence]`, `project_id`,
  `company_id` e `date`.
- `balance` é saldo acumulado **persistido**, sensível à ordem de inserção.

#### Scenario: coluna reservada renomeada
- **GIVEN** a coluna legada chamada `order`
- **WHEN** o schema do ai9 é criado
- **THEN** a coluna se chama `sequence` e nenhuma consulta precisa de aspas para acessá-la

#### Scenario: saldo acumulado depende da ordem
- **GIVEN** os movimentos de uma operação com `balance` acumulado
- **WHEN** o ETL insere os movimentos
- **THEN** a inserção respeita a ordem original de `sequence`/`date` e o `balance` final coincide com o do legado

> Nota: corrige D-12 (legado: domínio financeiro sem FK e sem índice)

### Requirement: DB-580 — structured_operation_types
O ai9 **MUST** portar o catálogo de tipos de operação estruturada **com o seed ativo de produção**.
Fonte legada: `db/migrate/20220701123654:3-14`; seed `db/seeds.rb:20,334-339`.

- **Colunas**: `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int,
  `is_default` int d0, `allow_manual_operations` int d1, `allow_receivable_entries` int d0,
  `has_pre_faturamento` int d0, timestamps.
- **Relações**: `has_many :operations` (restrict) · scope `active`.
- **Seed obrigatório**: Fomento, Comissária, Intercompany, Auto Liquidável.
- **Índices (ai9)**: único em `title`.

#### Scenario: user_id divergente no seed
- **GIVEN** que `db/seeds.rb:338` usa `user_id: 11` enquanto as demais linhas usam `1` (provável typo já em produção)
- **WHEN** o seed do ai9 é escrito
- **THEN** todas as linhas do catálogo apontam para o mesmo dono resolvido por configuração, e a divergência do legado fica registrada no relatório de migração

#### Scenario: seed presente no dia 1
- **GIVEN** um ambiente ai9 recém-carregado
- **WHEN** os tipos de operação estruturada são listados
- **THEN** os 4 tipos do seed existem

### Requirement: DB-581 — structured_operations
O ai9 **MUST** portar as operações estruturadas, que espelham `risk_operations` com menos colunas
(sem `risk_control_id`, `receivable_id`, `pair_id`, `original_id` e subtipo). Fonte legada:
`db/migrate/20220701125757:3-23`, `20220802225011:19`.

- **Colunas**: `id`, `title` string, `user_id` int, `operation_type_id` int, `project_id` int,
  `company_id` int, `carrier_id` int, `receipt_id` int, `contract_number` string, `issue_date` date,
  `due_date` date, `operation_value` decimal(15,2) d0, `original_balance` decimal(15,2) d0,
  `balance` decimal(15,2) d0, `agreed_rate` float d0, `observation` string, `is_on_variable` int d0,
  `is_ended` int d0, timestamps.
- **Relações**: `belongs_to :company`, `:carrier`, `:project`, `:user`, `:operation_type` ·
  `has_one :receipt` (restrict) · scope `available_for_receipt`.
- **Índices (ai9)**: índices em `project_id`, `company_id`, `carrier_id`, `receipt_id`, `due_date`.
- A unificação com `risk_operations` **não** é feita nesta migração: as duas tabelas permanecem
  separadas, como no legado (DEC-09).

#### Scenario: operação disponível para recibo
- **GIVEN** uma operação estruturada sem `receipt_id`
- **WHEN** a lista de operações faturáveis é montada
- **THEN** a operação aparece; assim que um recibo é vinculado, ela deixa de aparecer

#### Scenario: exclusão com recibo vinculado
- **GIVEN** uma operação estruturada com recibo
- **WHEN** a exclusão é solicitada
- **THEN** a operação é recusada (`restrict`)

### Requirement: DB-582 — remunerations
O ai9 **MUST** portar a tabela de remuneração por tipo de operação e projeto, mantendo `value` como
**float** para que os totais faturados batam com o legado. Fonte legada:
`db/migrate/20220629123512:3-11`, `20220802165837:3`.

- **Colunas**: `id`, `project_id` int, `operation_type_id` int + `operation_type_type` string
  (**polimórfico**: `RiskOperationType` | `StructuredOperationType`), **`value` float d0** (taxa
  percentual 0–100 usada para calcular dinheiro), `title` string, timestamps.
- **Relações**: `belongs_to :project`, `belongs_to :operation_type` (polimórfico) ·
  `has_many :receipts`.
- **Índices**: índice `[operation_type_type, operation_type_id]` (já existe no legado); no ai9
  acrescenta-se único composto `[operation_type_type, operation_type_id, project_id]` e índice em
  `project_id`.

#### Scenario: taxa em float multiplicando decimal
- **GIVEN** uma remuneração com `value` float e uma operação com `operation_value` decimal(15,2)
- **WHEN** o valor faturado é calculado
- **THEN** a sequência de operações e arredondamentos replica a do legado e o total é idêntico

#### Scenario: remuneração duplicada
- **GIVEN** uma remuneração já definida para um tipo de operação em um projeto
- **WHEN** outra remuneração para o mesmo par é criada
- **THEN** o índice único composto rejeita a inserção

> Nota: DEC-02 — precisao legada preservada por decisao do usuario
> Nota: corrige D-103 (legado: unicidade `operation_type_id` × `[operation_type_type, project_id]` só em aplicação)

### Requirement: DB-583 — charges
O ai9 **MUST** portar a cobrança, mantendo a decisão de modelagem documentada na própria migration:
cobrança nunca se liga a operação diretamente, apenas via recibo. Fonte legada:
`db/migrate/20220707164909:2-3,5-21`; model `app/models/charge.rb:14-16`.

- **Colunas**: `id`, `project_id` int, `user_id` int, `date` date, `state` string,
  `value` decimal(15,2) d0, `structured_operations_value` decimal(15,2) d0,
  `risk_operations_value` decimal(15,2) d0, `total_operations_value` decimal(15,2) d0,
  `receipts_count` int d0, `risk_operations_count` int d0, `structured_operations_count` int d0,
  timestamps.
- **Relações**: `belongs_to :project`, `:user` · `has_many :receipts` (restrict).
- **`state`** é enum-string pt-BR: `"Edição"`, `"Disponível"`, `"Faturado"`, com default em callback.
- **Índices (ai9)**: índices em `project_id` e `[project_id, state]`.
- Os 3 contadores **não** são `counter_cache` do Rails — são mantidos explicitamente pelo código.

#### Scenario: cobrança só alcança operações pelo recibo
- **GIVEN** uma cobrança com recibos vinculados
- **WHEN** as operações cobradas são consultadas
- **THEN** o caminho de consulta passa por `receipts` e não existe FK direta entre cobrança e operação

#### Scenario: cobrança faturada não perde recibos
- **GIVEN** uma cobrança no estado `"Faturado"` com recibos
- **WHEN** a exclusão é solicitada
- **THEN** a operação é recusada (`restrict`)

### Requirement: DB-584 — receipts
O ai9 **MUST** portar o recibo, ligando cobrança, operação (polimórfica) e remuneração, mantendo `fee`
como **float**. Fonte legada: `db/migrate/20220802225011:3-17`, `20220804195335:3-4`; model
`app/models/receipt.rb:17-18`.

- **Colunas**: `id`, `temp_id` string, `project_id` int, `charge_id` int, `operation_id` int +
  `operation_type` string (**polimórfico**: `RiskOperation` | `StructuredOperation`),
  `remuneration_id` int, `kind` string (`"LIQ"`/`"EST"`), `title` string, `operation_title` string,
  **`fee` float**, `operation_value` decimal(15,2), `value` decimal(15,2), `user_id` int, `date` date,
  timestamps.
- **Relações**: `belongs_to :charge`, `:project`, `:remuneration`, `belongs_to :operation`
  (polimórfico).
- **Índices**: índice `[operation_type, operation_id]` (já existe); no ai9 acrescenta-se único composto
  `[project_id, operation_type, operation_id]` e índice em `charge_id`.
- `title` e `operation_title` são denormalizados de remuneração/operação e são preservados.

#### Scenario: valor faturado com fee em float
- **GIVEN** um recibo com `fee` float e `operation_value` decimal(15,2)
- **WHEN** `value` é calculado
- **THEN** o resultado replica exatamente o do legado, sem arredondamento adicional

#### Scenario: recibo duplicado para a mesma operação
- **GIVEN** uma operação que já possui recibo no projeto X
- **WHEN** outro recibo para a mesma operação é criado no mesmo projeto
- **THEN** o índice único composto rejeita a inserção

#### Scenario: temp_id de interface
- **GIVEN** um recibo criado pela interface com `temp_id` efêmero
- **WHEN** o recibo é persistido
- **THEN** o `temp_id` é migrado como está, sem virar identificador de negócio

> Nota: DEC-02 — precisao legada preservada por decisao do usuario
> Nota: corrige D-103 (legado: unicidade `operation_id` × `[project_id, operation_type]` só em aplicação)

### Requirement: DB-585 — indicators
O ai9 **MUST** portar o catálogo de indicadores e **MUST** substituir o `dependent: :delete_all` das
entradas por exclusão com callbacks. Fonte legada: `db/migrate/20211026165448:3-9`, `20211027150648:3`,
`20211029172624:3`, `20220223145902:3`; model `app/models/indicator.rb:4,26`.

- **Colunas**: `id`, `title` string, `key` string, `value_type` string (enum-string pt-BR, ex.:
  `"Dinheiro"`), `project_id` int, `is_active` int d1, timestamps.
- **Relações**: `has_many :project_indicator_connections` (restrict), `:projects through`, `:entries`.
- **Índices (ai9)**: único em `key`; índice em `project_id`.

#### Scenario: exclusão de indicador com entradas
- **GIVEN** um indicador com entradas históricas
- **WHEN** o indicador é excluído
- **THEN** as entradas são removidas com callbacks executados, e não por `delete_all` cego como no legado

#### Scenario: chave de indicador única
- **GIVEN** um indicador com `key = "faturamento"`
- **WHEN** outro indicador com a mesma chave é criado
- **THEN** o índice único rejeita a inserção

> Nota: corrige D-103 (legado: `key` sem unicidade no banco e nenhum índice)

### Requirement: DB-586 — project_indicator_connections
O ai9 **MUST** portar a junção explícita projeto ↔ indicador, na mesma forma de
`project_to_carrier_connections`. Fonte legada: `db/migrate/20211026184044:3-9`.

- **Colunas**: `id`, `project_id` int, `indicator_id` int, timestamps.
- **Relações**: junção com `belongs_to :project` e `belongs_to :indicator`.
- **Índices (ai9)**: único composto `[project_id, indicator_id]`; índices em `project_id` e
  `indicator_id`.

#### Scenario: conexão duplicada
- **GIVEN** o indicador X já conectado ao projeto Y
- **WHEN** a mesma conexão é criada de novo
- **THEN** o índice único composto rejeita a inserção

#### Scenario: indicador conectado bloqueia exclusão
- **GIVEN** um indicador conectado a um projeto
- **WHEN** a exclusão do indicador é solicitada
- **THEN** a operação é recusada (`restrict`)

> Nota: corrige D-103 (legado: unicidade `indicator_id` × `project_id` só em aplicação, sem índices)

### Requirement: DB-587 — indicator_entries
O ai9 **MUST** portar os lançamentos mensais de indicador, preservando `month`/`year` como inteiros
separados e os campos denormalizados do indicador. Fonte legada: `db/migrate/20211027140815:3-15`,
`20211027150857:3`.

- **Colunas**: `id`, `title` string, `user_id` int, `project_id` int, `indicator_id` int,
  `value` decimal(15,2) d0, `month` int, `year` int, `key` string, `value_type` string, timestamps.
- **Relações**: `belongs_to :project`, `:indicator`, `:user`.
- **Índices (ai9)**: único composto `[month, year, project_id, indicator_id]`; índice em
  `[project_id, year]`.
- `title`, `key` e `value_type` são denormalizados de `indicators` e são preservados.

#### Scenario: lançamento duplicado no mês
- **GIVEN** um lançamento do indicador X no projeto Y em 03/2026
- **WHEN** outro lançamento da mesma competência é criado
- **THEN** o índice único composto rejeita a inserção

#### Scenario: competência como mês e ano separados
- **GIVEN** um lançamento com `month = 3` e `year = 2026`
- **WHEN** o ETL importa o registro
- **THEN** os dois inteiros são preservados como estão, sem serem convertidos para `date`

> Nota: corrige D-103 (legado: unicidade `month` × `[year, project_id, indicator_id]` só em aplicação, sem índices)

### Requirement: DB-588 — help_groups
O ai9 **MUST** portar os grupos da central de ajuda. Fonte legada: `db/migrate/20180410131904:3-7`;
model `app/models/help_group.rb:1` (herda de `ActiveRecord::Base`, não de `ApplicationRecord`).

- **Colunas**: `id`, `title` string, timestamps NOT NULL.
- **Relações**: `has_many :categories` (destroy), `has_many :items, through: :categories`.
- **Índices (ai9)**: único em `title`.
- Sem seed no legado.

#### Scenario: exclusão em cascata
- **GIVEN** um grupo com categorias e itens
- **WHEN** o grupo é excluído
- **THEN** categorias e itens descendentes são removidos junto

#### Scenario: título de grupo único
- **GIVEN** um grupo "Primeiros passos"
- **WHEN** outro grupo com o mesmo título é criado
- **THEN** o índice único rejeita a inserção

### Requirement: DB-589 — help_categories
O ai9 **MUST** portar as categorias da central de ajuda. Fonte legada:
`db/migrate/20180410132114:3-8`.

- **Colunas**: `id`, `title` string, `help_group_id` int, timestamps NOT NULL.
- **Relações**: `belongs_to :group`, `has_many :items` (destroy).
- **Índices (ai9)**: único composto `[title, help_group_id]`; índice em `help_group_id`.

#### Scenario: categoria duplicada no grupo
- **GIVEN** a categoria "Login" no grupo X
- **WHEN** outra categoria com o mesmo título é criada no mesmo grupo
- **THEN** o índice único composto rejeita a inserção

#### Scenario: mesmo título em grupos diferentes
- **GIVEN** a categoria "Login" no grupo X
- **WHEN** a categoria "Login" é criada no grupo Y
- **THEN** a criação é aceita

> Nota: corrige D-103 (legado: unicidade `title` × `help_group_id` só em aplicação, sem índices)

### Requirement: DB-590 — help_items
O ai9 **MUST** portar os itens (artigos) da central de ajuda. Fonte legada:
`db/migrate/20180410132354:3-10`.

- **Colunas**: `id`, `title` string, `help_category_id` int, `description` text, `user_id` int,
  timestamps NOT NULL.
- **Relações**: `belongs_to :category`, `belongs_to :user`, `has_one :group, through: :category`.
- **Índices (ai9)**: único composto `[title, help_category_id]`; índice em `help_category_id`.
- Os arquivos `db/seed_assets/*_help_inputs.yml` **não** alimentam esta tabela — são help de campo de
  formulário (ver `ops-config`).

#### Scenario: item duplicado na categoria
- **GIVEN** um item "Como redefinir a senha" na categoria X
- **WHEN** outro item com o mesmo título é criado na mesma categoria
- **THEN** o índice único composto rejeita a inserção

#### Scenario: fonte do conteúdo de ajuda de campo
- **GIVEN** os arquivos `*_help_inputs.yml` do legado
- **WHEN** a central de ajuda é carregada
- **THEN** o conteúdo desses arquivos não é inserido em `help_items`, porque pertence ao help de formulário

### Requirement: DB-591 — trackings
O ai9 **MUST** portar a trilha de auditoria polimórfica e **MUST** indexar `trackable_*`, que é
exatamente o filtro usado pela consulta do produto. Fonte legada: `db/migrate/20180724162731:3-18`;
`lib/tracking_facade.rb`; `app/controllers/api/v1/trackings_controller.rb:21-23`.

- **Colunas**: `id`, `user_id` int, `target_id` int, `trackable_type` string + `trackable_id` int
  (polimórfico), `resume` string (limitado a 300 chars em aplicação), **`type` string (STI nunca
  preenchida)**, `target_group_id` int, `target_group_type` string, `trackable_parent_id` int +
  `trackable_parent_type` string (polimórfico), `kind` string, timestamps NOT NULL.
- **Relações**: `belongs_to :user`, `:target` (ambos User), `:trackable` e `:trackable_parent`
  (polimórficos).
- **Índices (ai9)**: índices em `[trackable_type, trackable_id]`, `[trackable_parent_type,
  trackable_parent_id]`, `user_id` e `created_at`.
- Valores conhecidos de `trackable_type`: `"Project"`, `"ProjectAvailabilityTemplate"`;
  `kind` inclui `"JOB"`.
- A coluna `type` (STI sem subclasses, sempre NULL) **MUST** ser descartada no ai9.

#### Scenario: consulta de trilha por entidade
- **GIVEN** a tabela de auditoria com o volume histórico
- **WHEN** a trilha de um projeto específico é consultada
- **THEN** a consulta usa o índice em `[trackable_type, trackable_id]` e não faz varredura sequencial

#### Scenario: coluna STI morta descartada
- **GIVEN** a coluna `type` sempre NULL no legado
- **WHEN** o schema do ai9 é criado
- **THEN** a coluna não existe e nenhum comportamento depende dela

> Nota: corrige D-103 (legado: nenhum índice numa tabela grande e crescente cuja consulta filtra por `trackable_*`)

### Requirement: DB-592 — geolocations
O ai9 **MUST** tratar `geolocations` como **candidata a descarte com verificação**: nenhum model do
legado declara `has_one`/`has_many :geolocation` e não há referência a `geolocatable` fora de
`app/models/geolocation.rb`. Fonte legada: `db/migrate/20160302002809:3-38`.

- **Colunas**: `id`, `geolocatable_id` int + `geolocatable_type` string (polimórfico), `lat`, `lng`
  decimal(10,6), `city`, `state`, `cep`, `neighborhood`, `country`, `address`, `complement`,
  `full_address`, `distance_unity` string, `street_number` int, `auto_loading` int d0,
  `distance` float, `ref_lat`, `ref_lng` decimal(10,6), timestamps.
- **Índice existente**: `[geolocatable_type, geolocatable_id]`.

#### Scenario: contagem antes de descartar
- **GIVEN** que o código do legado não referencia a tabela em lugar nenhum
- **WHEN** o ETL executa a contagem de linhas de origem
- **THEN** contagem zero confirma o descarte, e contagem maior que zero aborta o descarte e entra no relatório para decisão

#### Scenario: geocoding não roda no save
- **GIVEN** um registro com `lat`/`lng` preenchidos
- **WHEN** ele é gravado no ai9
- **THEN** nenhum geocoding síncrono acontece no `before_save`

> Nota: corrige D-83 (legado: Geocoder síncrono no `before_save` com timeout de ~3h20 e sem cache)

### Requirement: DB-593 — pictures
O ai9 **MUST NOT** migrar `pictures`: nenhum model declara `has_many :pictures` e o
`counter_cache: :pictures_count` aponta para uma coluna que não existe em tabela alguma, o que faria
qualquer `Picture.create` levantar exceção — prova de que a tabela nunca foi usada. Fonte legada:
`db/migrate/20160124203946:3-13`; model `app/models/picture.rb:2`.

- **Colunas**: `id`, `imageable_id` int + `imageable_type` string (polimórfico), Paperclip
  `image_file_name`, `image_content_type`, `image_file_size` int, `image_updated_at` datetime,
  `description` text, `width` int d0, `height` int d0, `last_calc_at` timestamp, timestamps.
- **Índice existente**: `[imageable_type, imageable_id]`.

#### Scenario: descarte confirmado por contagem
- **GIVEN** a tabela `pictures` no banco legado
- **WHEN** o ETL conta as linhas de origem
- **THEN** contagem zero confirma o descarte; qualquer linha encontrada aborta a carga com relatório, porque contradiz a análise

#### Scenario: nenhuma tabela equivalente é criada
- **GIVEN** o schema do ai9 após a migração
- **WHEN** as tabelas são listadas
- **THEN** não existe tabela `pictures` nem coluna `pictures_count`

### Requirement: DB-594 — livetat_feedback_messages
O ai9 **MUST** portar as mensagens do canal de feedback, incluindo os dois campos livres configuráveis
(`hadouken_*`/`shoryuken_*`) e os tokens público/privado. Fonte legada:
`engines/feedback19/db/migrate/20160826200511:3-16`, `20170413135718:3-7`, `20170413143721:3-4`,
`20170505145152:3`, `20170505222143:3`, `20170506000127:3`, `20181005020002:3-4`.

- **Colunas**: `id`, `formal` string, `email` string, `message` string (limite de 500 só em aplicação),
  `user_id` int, `is_read` int d0, `is_favorite` int d0, `read_at` timestamp, `hadouken_label`,
  `hadouken_value`, `shoryuken_label`, `shoryuken_value` string, `uses_hadouken_field`,
  `uses_shoryuken_field` int, `state_id` int, `context_id` int, `is_intern` int,
  `public_token`, `private_token` string, timestamps.
- **Relações**: `belongs_to :state`, `:context`, `:user` · `has_many :notes` (destroy).
- **Índices (ai9)**: únicos em `public_token` e `private_token`; índices em `state_id`, `context_id`,
  `user_id`.
- A coluna `tag` foi removida no legado e substituída pelos campos `hadouken_*`/`shoryuken_*` — não há
  dado de `tag` a migrar.

#### Scenario: token público único
- **GIVEN** duas mensagens legadas com o mesmo `public_token`
- **WHEN** o ETL as insere
- **THEN** a segunda é rejeitada pelo índice único e reportada, porque o token dá acesso à conversa

#### Scenario: mensagem interna
- **GIVEN** uma mensagem com `is_intern = 1`
- **WHEN** a lista de destinatários da notificação é montada
- **THEN** só observadores internos são considerados, preservando a regra do legado

> Nota: corrige D-103 (legado: `public_token`/`private_token` sem índice nem unicidade, apesar de darem acesso à conversa)

### Requirement: DB-595 — livetat_feedback_states
O ai9 **MUST** portar o catálogo de estados de mensagem de feedback **com o seed obrigatório**,
preservando o `code` inteiro estável em vez do `id`. Fonte legada:
`engines/feedback19/db/migrate/20170505143940:3-8`; seed `engines/feedback19/db/seeds.rb:2-18`.

- **Colunas**: `id`, `name` string, `code` int, timestamps.
- **Relações**: `has_many :messages`.
- **Seed obrigatório**: os 8 estados pt-BR (de "Não lido" a "Rejeitado"), com `code` estável.
- **Índices (ai9)**: únicos em `name` e em `code`.

#### Scenario: identidade estável pelo code
- **GIVEN** uma mensagem legada apontando para um estado por `id`
- **WHEN** o ETL religa a mensagem no ai9
- **THEN** a ligação é feita pelo `code` do estado, não pelo `id`, que muda na carga

#### Scenario: seed presente
- **GIVEN** um ambiente ai9 recém-carregado
- **WHEN** os estados de feedback são listados
- **THEN** os 8 estados do seed existem

### Requirement: DB-596 — livetat_mailer_contacts
O ai9 **MUST** portar o log de e-mails enviados e **MUST** acrescentar status de entrega, que o legado
não registrava. Fonte legada: `engines/mailer19/db/migrate/20160409121840:3-13`, `20170519223014:3`,
`20170519223026:3`.

- **Colunas**: `id`, `sender` string, `target` string, `target_name` string, `subject` string,
  **`type` string (STI nunca preenchida)**, `message` **text**, timestamps NOT NULL.
- **Relações**: nenhuma no model do legado.
- **Índices (ai9)**: índices em `target` e `created_at`.
- No ai9 acrescenta-se **status de entrega** (enfileirado / enviado / falhou) com o erro associado; a
  coluna `type` sempre NULL é descartada.

#### Scenario: falha de entrega deixa rastro
- **GIVEN** um e-mail cuja entrega SMTP falha
- **WHEN** o envio é processado
- **THEN** a linha de log registra o status de falha e o erro, em vez de registrar apenas a intenção como no legado

#### Scenario: histórico anterior à troca de tipo da coluna
- **GIVEN** que `message` foi removida e recriada no legado (`20170519223014` + `20170519223026`), perdendo o conteúdo anterior
- **WHEN** o ETL importa o histórico
- **THEN** as linhas sem corpo são migradas como estão e a perda é registrada no relatório, sem tentativa de reconstrução

> Nota: corrige D-78 (legado: e-mail perdido silenciosamente, sem nenhum registro de sucesso ou falha de entrega)

### Requirement: DB-597 — delayed_jobs
O ai9 **MUST NOT** portar a tabela `delayed_jobs`: a fila passa a ser Sidekiq/Redis e o `handler` do
legado é YAML de objetos Ruby, não migrável entre stacks. Fonte legada:
`engines/mailer19/db/migrate/20170505110720:4-17`, `20170505114146:3-7`.

- **Colunas do legado**: `id`, `priority` int NOT NULL d0, `attempts` int NOT NULL d0,
  `handler` text NOT NULL (YAML), `last_error` text, `run_at`, `locked_at`, `failed_at` datetime,
  `locked_by` string, `queue` string, `progress_stage` string, `progress_current` int d0,
  `progress_max` int d0, timestamps nullable.
- **Índice existente**: `delayed_jobs_priority` em `[priority, run_at]`.
- O contrato de progresso exibido ao usuário (`progress_stage`, `progress_current`, `progress_max`)
  **MUST** ser reimplementado no ai9 em colunas da própria entidade processada, com atualização por
  Action Cable.

#### Scenario: referências à fila removidas do schema
- **GIVEN** `projects.job_id` e `project_availability_templates.job_id` apontando para `delayed_jobs`
- **WHEN** o schema do ai9 é criado
- **THEN** nenhuma coluna referencia a tabela de jobs, e o estado de processamento vive na entidade

#### Scenario: jobs pendentes no cutover
- **GIVEN** linhas em `delayed_jobs` com `failed_at` preenchido ou ainda pendentes no momento da migração
- **WHEN** o ETL roda
- **THEN** essas linhas são reportadas como trabalho não concluído para reprocessamento manual, e nenhum `handler` YAML é importado

> Nota: corrige D-80 (legado: `job_id` como FK para a tabela da fila)

### Requirement: DB-598 — active_storage_blobs
O ai9 **MUST NOT** recriar nem migrar `active_storage_blobs` do legado: o produto usa Paperclip
(`kt-paperclip 7.0`) para todos os anexos, nenhum model declara `has_one_attached`, e o ai9 já possui a
tabela. Fonte legada: `db/migrate/20190310025434:4-25`.

- **Colunas do legado**: `id`, `key` string NOT NULL, `filename` string NOT NULL, `content_type` string,
  `metadata` text, `byte_size` bigint NOT NULL, `checksum` string NOT NULL, `created_at` NOT NULL.
- **Índice existente**: único em `key`.
- `active_storage_variant_records` não existe no legado (a migration é da versão 5.2).

#### Scenario: tabela do ai9 preservada
- **GIVEN** o ai9 com `active_storage_blobs` já em uso
- **WHEN** o ETL roda
- **THEN** a tabela do ai9 não é alterada nem recebe linhas do legado

#### Scenario: verificação de resíduo
- **GIVEN** a tabela `active_storage_blobs` no banco legado
- **WHEN** o ETL conta as linhas
- **THEN** contagem zero confirma o resíduo de instalação; qualquer linha encontrada entra no relatório para decisão manual

### Requirement: DB-599 — schema_migrations
O ai9 **MUST NOT** migrar `schema_migrations` do legado: o ai9 tem o seu próprio histórico de
migrations. A tabela legada é lida **apenas** pela etapa de introspecção, para conferir quais das 139
migrations foram de fato aplicadas no banco de origem. Fonte legada: geradas pelo Rails; versões
implícitas nos 139 arquivos de `db/migrate` e `engines/*/db/migrate`.

- **Colunas**: `version` string PK.
- As migrations das engines não têm cópia em `db/migrate` — são carregadas por
  `Engine.paths["db/migrate"]`, e por isso o histórico do banco depende da ordem de montagem das
  engines.

#### Scenario: migration esperada e ausente no banco
- **GIVEN** a lista das 139 versões esperadas
- **WHEN** a introspecção compara com `schema_migrations` do banco real
- **THEN** qualquer versão ausente é listada no relatório, porque indica coluna esperada que pode não existir

#### Scenario: versão desconhecida no banco
- **GIVEN** uma versão presente em `schema_migrations` que não corresponde a nenhum arquivo do repositório
- **WHEN** a introspecção roda
- **THEN** a carga aborta com relatório, porque é indício de schema aplicado fora do versionamento

### Requirement: DB-730 — livetat_auth_role_types
O ai9 **MUST** portar os tipos de papel do produto com índice único real em `name` e **MUST** tratá-los
como configuração versionada (seed), não como linhas soltas do banco legado (DEC-04). Fonte legada:
`engines/auth19/db/migrate/20160409121833:3-7`, `20160409121836:3`.

- **Colunas**: `id`, `name` string, `hierarchy` int, timestamps.
- **Relações**: `has_many :roles` · `has_many :abilities, as: :abilitable` (delete_all).
- **Índices (ai9)**: único em `name`.
- Papéis do produto: `Administrador`, `Gestor`, `Colaborador` (e `og`); `hierarchy` define a precedência.

#### Scenario: hierarquia decide precedência
- **GIVEN** dois papéis com `hierarchy` diferentes
- **WHEN** a comparação de precedência é feita
- **THEN** o papel de maior `hierarchy` prevalece, como no legado

#### Scenario: catálogo como seed versionado
- **GIVEN** que não há dump do banco legado (DEC-04) e o seed do legado destruía papéis
- **WHEN** o ai9 é provisionado
- **THEN** os tipos de papel vêm de seed versionado no repositório, e a lista é a mesma em qualquer ambiente

> Nota: corrige D-103 (legado: `name` único apenas em aplicação)

### Requirement: DB-731 — livetat_auth_abilities
O ai9 **MUST** portar as abilities polimórficas e **MUST** indexar `abilitable`, que a migration
`Migration[4.2]` do legado não criou. Fonte legada: `engines/auth19/db/migrate/20160409121834:3-10`,
`20160824171513:3-4`; model `engines/auth19/app/models/livetat/auth/ability.rb:2`;
`engines/auth19/lib/livetat/auth/ability_factory.rb:56-74`.

- **Colunas**: `id`, `name` string (5..50), `value` int d1, `description` string (5..100),
  `type` string (`conditional` | `limit`), `abilitable_id` int, `abilitable_type` string, timestamps.
- **Relações**: `belongs_to :abilitable` polimórfico, com `abilitable_type` ∈
  {`Livetat::Auth::Role`, `Livetat::Auth::RoleType`}.
- **Índices (ai9)**: índice em `[abilitable_type, abilitable_id]`; único composto
  `[abilitable_type, abilitable_id, name]`.
- `self.inheritance_column = nil`: **`type` não é STI** — é enum livre e migra como enum.
- Esta linha e DB-007 (unidade auth-users) descrevem **a mesma tabela** e viram **uma única migration**
  no ai9.

#### Scenario: type não é STI
- **GIVEN** uma ability com `type = "conditional"`
- **WHEN** o registro é carregado no ai9
- **THEN** ele é instanciado como enum e nenhuma resolução de subclasse STI é tentada

#### Scenario: ability duplicada no mesmo dono
- **GIVEN** um `Role` que já possui a ability `may_create_users`
- **WHEN** outra ability com o mesmo nome é criada para o mesmo dono
- **THEN** o índice único composto rejeita a inserção

> Nota: corrige D-103 (legado: `t.references … polymorphic: true` em `Migration[4.2]` não criou índice)

### Requirement: DB-732 — livetat_feedback_contexts
O ai9 **MUST** portar o catálogo de contextos de feedback **com o seed obrigatório**, preservando o
`code` inteiro estável. Fonte legada: `engines/feedback19/db/migrate/20170505214502:3-8`; seed
`engines/feedback19/db/seeds.rb:32-45`.

- **Colunas**: `id`, `name` string, `code` int, timestamps NOT NULL.
- **Relações**: `has_many :messages` · `has_many :observer_contexts` (destroy) ·
  `has_many :observers, through:`.
- **Seed obrigatório (4 linhas)**: Outros, Problema, Contato, Sugestão.
- **Índices (ai9)**: únicos em `name` e em `code`.

#### Scenario: religação pelo code
- **GIVEN** uma mensagem legada apontando para um contexto por `id`
- **WHEN** o ETL religa a mensagem no ai9
- **THEN** a ligação usa o `code`, não o `id`

#### Scenario: seed presente
- **GIVEN** um ambiente ai9 recém-carregado
- **WHEN** os contextos são listados
- **THEN** os 4 contextos do seed existem

### Requirement: DB-733 — livetat_feedback_observers
O ai9 **MUST** portar os observadores do canal de feedback, com `email` único no banco. Fonte legada:
`engines/feedback19/db/migrate/20170505211325:3-12`.

- **Colunas**: `id`, `user_id` int, `last_updated_user_id` int, `email` string, `title` string,
  `is_intern` int, `is_extern` int, timestamps.
- **Relações**: `belongs_to :user` · `has_many :observer_contexts` (destroy) ·
  `has_many :contexts, through:`.
- **Índices (ai9)**: único em `email`; índice em `user_id`.
- `is_intern`/`is_extern` são inteiros 0/1 (não booleanos) e são preservados como enum/booleano
  explícito no ai9; `last_updated_user_id` é a única auditoria de atualização de todo o schema.

#### Scenario: observador duplicado por e-mail
- **GIVEN** um observador com `email = "obs@safegold.com.br"`
- **WHEN** outro observador com o mesmo e-mail é criado
- **THEN** o índice único rejeita a inserção

#### Scenario: observador interno e mensagem interna
- **GIVEN** um observador com `is_intern = 0`
- **WHEN** chega uma mensagem com `is_intern = 1`
- **THEN** esse observador não é notificado

> Nota: corrige D-103 (legado: `email` único apenas em aplicação, sem índice)

### Requirement: DB-734 — livetat_feedback_observer_contexts
O ai9 **MUST** portar a junção observador ↔ contexto com **índice único composto no banco**, porque a
validação do legado (`where(...).size > 0`) permite duplicata sob concorrência. Fonte legada:
`engines/feedback19/db/migrate/20170505225555:3-8`; model
`engines/feedback19/app/models/livetat/feedback19/observer_context.rb:6-10`.

- **Colunas**: `id`, `observer_id` int, `context_id` int, timestamps.
- **Relações**: `belongs_to :context`, `belongs_to :observer`.
- **Índices (ai9)**: único composto `[observer_id, context_id]`; índices em `observer_id` e `context_id`.

#### Scenario: duplicata sob concorrência
- **GIVEN** duas requisições concorrentes vinculando o mesmo observador ao mesmo contexto
- **WHEN** ambas tentam gravar
- **THEN** o índice único permite apenas uma e a segunda recebe o erro "Definição já existente"

#### Scenario: verificação sem carregar registros
- **GIVEN** a checagem de duplicidade no ai9
- **WHEN** a validação roda
- **THEN** ela usa uma consulta de existência apoiada no índice, e não carrega a coleção como o legado fazia

> Nota: corrige D-103 (legado: unicidade `(context_id, observer_id)` só em aplicação, via `where(...).size > 0`)

### Requirement: DB-735 — livetat_feedback_notes
O ai9 **MUST** portar as notas (respostas) de feedback, preservando o encadeamento por dupla
auto-referência, e **MUST** indexar `feedback_id`. Fonte legada:
`engines/feedback19/db/migrate/20170516185759:3-13`, `20181005020904:3`.

- **Colunas**: `id`, `description` text, `user_formal` string, `user_email` string, `user_id` int,
  `top_parent_quote_id` int, `quoted_note_id` int, `feedback_id` int, `unread` int d1,
  timestamps NOT NULL.
- **Relações**: `belongs_to :feedback`, `:quoted`, `:top_parent` · `has_many :quotes`.
- **Índices (ai9)**: índices em `feedback_id`, `quoted_note_id` e `top_parent_quote_id`.
- `user_formal`/`user_email` são denormalizados do usuário e ficam defasados se o usuário mudar — o
  comportamento é preservado como registro histórico.

#### Scenario: listagem de thread sem seq scan
- **GIVEN** um feedback com muitas notas
- **WHEN** a thread é listada
- **THEN** a consulta usa o índice em `feedback_id`

#### Scenario: dados denormalizados do autor
- **GIVEN** uma nota gravada com `user_formal` e `user_email` do autor
- **WHEN** o autor troca de nome depois
- **THEN** a nota mantém os valores históricos

> Nota: corrige D-103 (legado: nenhum índice, listagem de thread fazia seq scan)

### Requirement: DB-736 — active_storage_attachments
O ai9 **MUST NOT** recriar nem migrar `active_storage_attachments` do legado; a tabela já existe no ai9
e no legado é resíduo de instalação do framework (todos os anexos usam Paperclip). Fonte legada:
`db/migrate/20190310025434:4-25`.

- **Colunas do legado**: `id`, `name` string NOT NULL, `record_type`/`record_id` NOT NULL
  (polimórfico), `blob_id` NOT NULL, `created_at` NOT NULL.
- **Índices existentes**: único `index_active_storage_attachments_uniqueness` em
  `[record_type, record_id, name, blob_id]`, índice em `blob_id` e a **única foreign key real do banco
  legado inteiro**: `blob_id → active_storage_blobs.id`.

#### Scenario: única FK do legado registrada como evidência
- **GIVEN** que esta é a única foreign key existente no schema legado
- **WHEN** o relatório de integridade do ETL é gerado
- **THEN** o relatório afirma explicitamente que todas as demais ~40 relações eram apenas de aplicação, justificando a contagem de órfãos

#### Scenario: nenhuma linha importada
- **GIVEN** o ai9 com a sua própria tabela `active_storage_attachments`
- **WHEN** o ETL roda
- **THEN** nenhuma linha do legado é inserida nela

### Requirement: DB-737 — action_text_rich_texts
O ai9 **MUST NOT** migrar `action_text_rich_texts` do legado: nenhum model declara `has_rich_text` e
nenhuma view usa o editor, apesar de o pack importar `trix`/`@rails/actiontext`. Fonte legada:
`db/migrate/20190425020855:4-13`.

- **Colunas do legado**: `id`, `name` string NOT NULL, `body` text, `record_type`/`record_id` NOT NULL
  (polimórfico), timestamps.
- **Índice existente**: único `index_action_text_rich_texts_uniqueness` em
  `[record_type, record_id, name]`.

#### Scenario: descarte confirmado por contagem
- **GIVEN** a tabela no banco legado
- **WHEN** o ETL conta as linhas
- **THEN** contagem zero confirma o resíduo; qualquer linha encontrada entra no relatório antes do descarte

#### Scenario: rich text do projeto
- **GIVEN** a descrição de disponibilidade do projeto, que no legado usava `has_rich_text`
- **WHEN** o campo é migrado
- **THEN** o conteúdo vai para a coluna de texto da própria entidade no ai9, sem depender desta tabela

### Requirement: DB-738 — ar_internal_metadata
O ai9 **MUST NOT** migrar `ar_internal_metadata`: é infraestrutura do Rails (guarda de `db:drop` e
`db:schema:load` por ambiente) e o ai9 gera a sua. Fonte legada: criada pelo Rails, não por migration.

- **Colunas**: `key` string PK, `value` string, timestamps.
- Conteúdo típico: 2 linhas (`environment`, `schema_sha1`).

#### Scenario: ambiente do banco de origem conferido
- **GIVEN** a linha `environment` do banco legado
- **WHEN** a introspecção do ETL roda
- **THEN** o valor é lido e registrado no relatório, para confirmar que a origem é de fato produção

#### Scenario: nenhuma linha importada
- **GIVEN** o ai9 com a sua própria `ar_internal_metadata`
- **WHEN** o ETL roda
- **THEN** nenhuma linha do legado é inserida nela
### Requirement: DB-ETL-01 — Etapa de introspecção do schema real
Como não haverá `pg_dump --schema-only` (DEC-04), o ETL **MUST** começar por uma etapa de introspecção
que lê o schema **real** do banco legado no momento da execução (tabelas, colunas, tipos, índices) e o
compara com o esperado a partir das 139 migrations, **abortando com relatório** ao encontrar qualquer
tabela, coluna ou índice desconhecido. Já existem duas provas de schema fora das migrations:
`default_position` (D-06, `app/controllers/pub/availability_templates_controller.rb:22`) e
`contracts.description` (D-108, `db/seeds.rb:124`).

#### Scenario: coluna desconhecida encontrada
- **GIVEN** um banco legado com uma coluna que nenhuma migration cria
- **WHEN** a etapa de introspecção roda no dry-run
- **THEN** o ETL aborta antes de inserir qualquer linha e emite relatório nomeando tabela, coluna e tipo encontrados

#### Scenario: as duas provas conhecidas
- **GIVEN** o banco legado com `default_position` e `contracts.description`
- **WHEN** a introspecção roda
- **THEN** as duas colunas são reconhecidas pelo mapeamento explícito e não abortam a carga, enquanto qualquer terceira surpresa aborta

#### Scenario: surpresa aparece no dry-run, não no cutover
- **GIVEN** um dry-run executado antes do cutover
- **WHEN** o relatório de introspecção é lido
- **THEN** ele lista o schema real conferido tabela a tabela, permitindo decidir antes da janela de migração

> Nota: corrige D-06 e D-108 (legado: estrutura de banco usada por código e ausente das migrations)

### Requirement: DB-ETL-02 — Tabela de-para `legacy_id → uuid`
O ETL **MUST** manter uma tabela de correspondência persistida `(tabela_origem, legacy_pk, id_ai9)`
para cada registro migrado, e **MUST** religar todas as referências por essa tabela. O legado tem
**exatamente uma** foreign key em todo o schema (`active_storage_attachments.blob_id`) e o ai9 usa
`uuid` em parte das tabelas — sem o de-para, o religamento por id numérico associa registros errados em
silêncio.

#### Scenario: religamento por de-para e não por id numérico
- **GIVEN** um recebível legado com `project_id = 12`
- **WHEN** o ETL insere o recebível no ai9
- **THEN** o `project_id` gravado é o identificador resolvido na tabela de-para para a origem `projects`/`12`, nunca o número 12 reaproveitado

#### Scenario: referência sem correspondência
- **GIVEN** uma referência legada cujo alvo não está na tabela de-para
- **WHEN** o ETL tenta religar
- **THEN** a linha é contada como órfã e a carga aborta conforme DB-ETL-03, sem gravar referência inventada

#### Scenario: de-para auditável depois do cutover
- **GIVEN** a migração concluída
- **WHEN** é preciso rastrear a origem de um registro do ai9
- **THEN** a tabela de-para responde qual era a chave legada, junto com as colunas `legacy_*` preservadas

> Nota: corrige D-103 (legado: zero foreign keys úteis e nenhum índice único nas 20+ unicidades compostas)

### Requirement: DB-ETL-03 — Contagem de órfãos e duplicatas antes de inserir
O ETL **MUST** executar, antes de qualquer inserção, uma contagem de **órfãos** (referências de
aplicação apontando para registros inexistentes) e de **duplicatas** (violações das 20+ unicidades
compostas que o legado só validava em aplicação), e **MUST** abortar com relatório se qualquer
contagem for maior que zero sem decisão prévia registrada.

#### Scenario: órfãos detectados no dry-run
- **GIVEN** um banco legado com recebíveis apontando para empresas inexistentes
- **WHEN** a contagem prévia roda
- **THEN** o relatório informa tabela, coluna, quantidade e amostra de ids, e a carga não avança

#### Scenario: duplicatas de unicidade composta
- **GIVEN** duas `availability_entries` com a mesma data, projeto, empresa e template
- **WHEN** a contagem prévia roda
- **THEN** o par é listado como duplicata e a criação do índice único no ai9 fica bloqueada até a resolução

#### Scenario: decisão registrada libera a carga
- **GIVEN** órfãos já analisados e uma decisão de tratamento registrada
- **WHEN** o ETL roda com essa decisão aplicada
- **THEN** a carga prossegue e o relatório final informa quantas linhas foram descartadas ou corrigidas por essa decisão

> Nota: corrige D-12 e D-103 (legado: domínio financeiro sem FK nem índice, com órfãos e duplicatas prováveis em produção)

### Requirement: DB-ETL-04 — Conversão de timestamps para UTC por faixa de data
O ETL **MUST** converter todo timestamp do legado — que grava em horário de Brasília
(`config/application.rb:28-29`, `default_timezone = :local`) — para UTC, usando as transições do fuso
`America/Sao_Paulo` da tz database — **nunca** um offset fixo — porque houve horário de verão até 2019
(último fim em 2019-02-16) e depois UTC-3 constante.

#### Scenario: registro anterior a 2019 dentro do horário de verão
- **GIVEN** um timestamp legado de 2017-01-15 10:00 (período de horário de verão, BRST = UTC-2)
- **WHEN** o ETL converte para UTC
- **THEN** o instante gravado é 2017-01-15 12:00 UTC, e reexibido em `America/Sao_Paulo` volta a mostrar 10:00

#### Scenario: registro posterior a 2019 sem horário de verão
- **GIVEN** um timestamp legado de 2022-01-15 10:00 (sem DST, BRT = UTC-3)
- **WHEN** o ETL converte para UTC
- **THEN** o instante gravado é 2022-01-15 13:00 UTC, e reexibido volta a mostrar 10:00

#### Scenario: hora ambígua na virada do horário de verão
- **GIVEN** um timestamp legado que caia na hora que aconteceu duas vezes no fim do horário de verão
- **WHEN** o ETL converte para UTC
- **THEN** a ambiguidade é resolvida pela regra padrão da tz database e a linha é listada no relatório do dry-run para conferência manual

#### Scenario: reconciliação amostral por ano
- **GIVEN** uma amostra de registros de cada ano de 2016 a 2026
- **WHEN** os instantes convertidos são reexibidos no fuso de Brasília
- **THEN** cada um mostra exatamente a mesma hora local que o legado mostra hoje na tela

> Nota: corrige D-102 (legado: `default_timezone = :local` com offset não constante, deslocando todo o histórico ao ser lido por um app UTC)

### Requirement: DB-ETL-05 — Colunas `legacy_*` preservadas, ETL Django descartado
O ai9 **MUST** preservar todas as colunas `legacy_id`, `legacy_project_id`, `legacy_user_id`,
`legacy_carrier_id` e `legacy_password` das tabelas de destino — são a única prova de proveniência dos
borderôs de 2016-2021. Em contrapartida, **MUST NOT** portar `app/models/legacy.rb`,
`app/models/legacy/**` (11 models-espelho e 4 interceptors), a conexão `sfg_legacy` nem o dump
`db/seed_assets/sfg_legacy_full.sql` (9 MB): era um ETL Django→Rails de mão única já executado em 2021
(DEC-12, D-105; o banco de origem `SG20210329` traz a data no nome).

#### Scenario: proveniência preservada
- **GIVEN** um borderô importado em 2021 com `legacy_id` preenchido
- **WHEN** ele é migrado para o ai9
- **THEN** o `legacy_id` continua gravado e permite rastrear o registro até o sistema Django anterior

#### Scenario: código do ETL antigo não é portado
- **GIVEN** o diretório `app/models/legacy/**` e a conexão secundária `sfg_legacy` no legado
- **WHEN** o backend do ai9 é escrito
- **THEN** não existe nenhum model espelho, nenhuma segunda conexão de banco e nenhum dump de 9 MB versionado

#### Scenario: verificação da suposição de que o pipeline não roda
- **GIVEN** a suposição registrada de que `Legacy::execute` não é executado desde 2021
- **WHEN** o ETL consulta `SELECT max(created_at) WHERE legacy_id IS NOT NULL` nas tabelas de destino
- **THEN** uma data máxima em 2021 confirma a suposição no relatório; qualquer data recente é sinalizada como contradição a decidir antes do cutover

### Requirement: DB-ETL-06 — Precisão financeira replicada
O ai9 **MUST** reproduzir a aritmética financeira do legado de modo que os totais fiquem **idênticos**
na verificação de paridade: a mesma sequência de operações, os mesmos casts e os mesmos pontos de
arredondamento, incluindo `remunerations.value` e `receipts.fee` em float multiplicando colunas
`decimal(15,2)` e as ~30 taxas em float de `receivable_entries`.

#### Scenario: total do borderô bate com o legado
- **GIVEN** um borderô de produção com todas as tarifas e taxas carregadas
- **WHEN** o ai9 recalcula os valores derivados
- **THEN** cada valor é igual ao do legado, e um teste golden trava esse resultado

#### Scenario: valor faturado do recibo bate com o legado
- **GIVEN** um recibo com `fee` float sobre um `operation_value` decimal
- **WHEN** o valor é recalculado no ai9
- **THEN** o resultado é idêntico ao registrado no legado, sem arredondamento intermediário adicional

#### Scenario: divergência de centavo é falha de teste
- **GIVEN** a suíte de paridade financeira
- **WHEN** um cálculo do ai9 diverge do legado em qualquer casa decimal
- **THEN** o teste falha, porque a decisão é replicar e não "melhorar" a precisão

> Nota: DEC-02 — precisao legada preservada por decisao do usuario

### Requirement: OPS-540 — Semeadura da aplicação é versionada e idempotente
O ai9 **MUST** substituir o seed principal do legado — um script controlado por **21 flags booleanas
hardcoded** no topo do arquivo — por semeadura versionada, **idempotente** e separada entre **dado de
referência obrigatório** e **dado de demonstração**. Fonte legada: `db/seeds.rb:1-358`, executado à mão
com `rails db:seed`.

- Estado das flags no repositório legado: **ativas** `should_seed_app_theme_in_existing_entities`
  (`:5`), `should_seed_risk_operation_type` (`:18`), `should_seed_risk_movement_type` (`:19`),
  `should_seed_structured_operation_type` (`:20`) e `should_update_abilities` (`:21`). **Desligadas**:
  seed das engines, de usuários, de contratos, de temas, de segmentos, carteiras, tipos de recebível,
  fontes e tipos de recurso, portadores, tipos de movimentação, ETL legado, disponibilidades de teste,
  empresa/risco de teste e projeto sandbox.
- Os blocos ativos usam `create` puro, **sem `find_or_create`**: rodar o seed duas vezes **duplica** os
  tipos de operação e de movimentação. Essa não-idempotência **MUST NOT** ser reproduzida.
- Há dependência de ordem declarada em comentário (`db/seeds.rb:22-23`): `AppTheme.default_theme`
  precisa existir **antes** de qualquer seed de usuário, senão a validação de tema do usuário falha
  (ver OPS-543).
- No ai9 o dado de referência obrigatório **MUST** ser aplicado pelo deploy, não por decisão manual de
  ligar uma flag.

#### Scenario: seed rodado duas vezes
- **GIVEN** um banco já semeado
- **WHEN** a semeadura é executada de novo
- **THEN** nenhum registro é duplicado e o resultado é idêntico ao da primeira execução

#### Scenario: dado obrigatório no dia 1
- **GIVEN** um ambiente novo recém-provisionado
- **WHEN** o deploy termina
- **THEN** todo o dado de referência obrigatório existe, sem depender de alguém editar flags no código

#### Scenario: dado de demonstração fora de produção
- **GIVEN** a semeadura em ambiente de produção
- **WHEN** ela é executada
- **THEN** projetos sandbox, disponibilidades de teste e empresa/risco de teste não são criados

### Requirement: OPS-541 — Papéis e permissões nascem de configuração versionada
O ai9 **MUST** definir os papéis e suas permissões em **configuração versionada e única**, eliminando o
ciclo do legado em que a engine cria papéis genéricos e o seed da aplicação em seguida os **destrói**
para recriar os papéis do produto. Fonte legada: `engines/auth19/db/seeds.rb:1-180`, carregado por
`Livetat::Auth::Engine.load_seed` sob `should_perform_engine_seed` (hoje `false`); destruição e
recriação em `db/seeds.rb:34-94`, sob `should_perform_user_seed` (hoje `false`).

- A engine cria os `RoleType` genéricos `OG` (hierarchy 1111), `Admin` (999), `Manager` (888) e
  `Visitor`, cada um com 16 `Ability`.
- O seed da aplicação então executa
  `Livetat::Auth::RoleType.where(name: "Admin"/"Manager"/"Visitor").first.destroy` e cria
  `U.ADMIN` (998), `U.MANAGER` (888) e `U.COLAB` (799).
- **É este o seed que destrói os RoleTypes que a configuração da engine referencia**: a engine aponta
  `default_role_type = "Visitor"` e `minimal_type_to_sign_up_through_web = "Manager"` para papéis que
  deixam de existir. No ai9 **MUST NOT** existir configuração apontando para papel inexistente, e a
  hierarquia **MUST** ser resolvida na carga da configuração, falhando o boot se o papel não existir.
- O seed legado usa `where(...).first.destroy` sem guarda: em um banco onde os papéis genéricos não
  existam, ele levanta `NoMethodError` e **aborta a semeadura no meio**.

> Nota: corrige D-36 (legado: `default_role_type = "Visitor"` e `minimal_type_to_sign_up_through_web = "Manager"` apontam para `RoleType`s que o `db/seeds.rb` destrói)

> Nota: DEC-04 — os `RoleType` passam a ser **configuração explícita versionada** no ai9, em vez de
> dependerem de linhas soltas no banco legado; a hierarquia proposta é submetida ao usuário antes da
> implementação (ver também DEC-08).

#### Scenario: configuração aponta para papel inexistente
- **GIVEN** uma configuração que referencia um papel que não está na configuração de papéis
- **WHEN** a aplicação sobe
- **THEN** o boot falha apontando o papel ausente, em vez de quebrar mais tarde no corte de hierarquia do login

#### Scenario: papéis do produto sem ciclo de criar e destruir
- **GIVEN** um banco novo
- **WHEN** a semeadura é aplicada
- **THEN** apenas os papéis do produto são criados, e nenhum papel é criado para ser destruído em seguida

#### Scenario: repetição da semeadura de permissões
- **GIVEN** os papéis já semeados com suas permissões
- **WHEN** a semeadura roda de novo
- **THEN** as permissões convergem para o valor declarado, sem duplicar papel nem perder permissão

### Requirement: OPS-542 — Estados e contextos de mensagem como dado de referência
O ai9 **MUST** tratar os 8 estados e os 4 contextos do módulo de mensagens como **dado de referência
obrigatório**, semeado de forma idempotente, e **MUST** executar o backfill dos registros antigos como
migração de dados única e verificável, não como efeito colateral do seed. Fonte legada:
`engines/feedback19/db/seeds.rb:1-67`, carregado por `Livetat::Feedback19::Engine.load_seed` sob
`should_perform_engine_seed` (hoje `false`).

- O seed legado cria 8 `State` (`code` 1..8) e 4 `Context` (`code` 1..4), e em seguida faz **backfill**
  dos feedbacks antigos cujos `state_id`, `context_id` e `is_intern` estão nulos.
- É **dado de produção obrigatório** se a feature de mensagens for migrada (ver DB-509 e DB-510 em
  `openspec/specs/engines/spec.md`): sem os estados, a máquina de estados da mensagem não resolve.
- O seed legado usa `create` puro e **não é idempotente**.

#### Scenario: estados presentes antes do primeiro uso
- **GIVEN** um ambiente novo
- **WHEN** a primeira mensagem é criada
- **THEN** os 8 estados e os 4 contextos já existem, com os mesmos códigos do legado

#### Scenario: repetição da semeadura
- **GIVEN** os estados e contextos já semeados
- **WHEN** a semeadura roda de novo
- **THEN** nenhum estado ou contexto é duplicado

#### Scenario: registros históricos sem estado
- **GIVEN** mensagens migradas com estado, contexto ou marcação interna nulos
- **WHEN** o backfill roda
- **THEN** cada registro recebe o valor padrão correspondente, e a quantidade ajustada é reportada

### Requirement: OPS-543 — Tema padrão obrigatório no dia 1
O ai9 **MUST** garantir a existência de **um** tema global padrão desde o primeiro boot de um ambiente
novo, porque sem ele **nenhum usuário passa na validação de tema** e a criação de usuários falha. Fonte
legada: `db/factories/app_theme_factory.rb:1-30`, autoload por `config/application.rb:31`, invocado em
`db/seeds.rb:25` sob `should_seed_app_themes`.

- O legado cria **um** `GlobalTheme` com `title: "Tema padrão"`, `is_default: 1`, estilo Light, fundo de
  login padrão e fonte "Baloo Thambi 2", anexando três logos via Paperclip a partir de
  `SFG::Theme.LOGO__FULL`, `LOGO__TEXT` e `LOGO__SYMBOL`.
- `theme.user_id` fica **NULL de propósito** (comentário em `app_theme_factory.rb:11`: o tema é criado
  antes de existirem usuários). Esse contrato **MUST** ser preservado: o tema global não pertence a
  usuário.
- **Atenção — é aqui que nasce o terceiro "primário" da marca**: a factory grava
  `primary_color = SFG::Theme.COLOR__ACCENT_INVERSE`, isto é **#373435**, que não coincide com o
  `COLOR__PRIMARY` canônico **#2D2D2A** (`app/definitions/SFG/theme.rb`) nem com o `$primary` **#050517**
  que o SCSS de fato compila (`app/frontend/css/pub/colors.scss:1`). Ver
  `.migration-ai9/brand-and-metadata.md` e BE-382.
- No ai9 o valor semeado **MUST** vir dos design tokens, que são a fonte única da marca — não de uma
  constante duplicada na factory.

> AMBIGUIDADE: qual dos valores é a marca correta — **#2D2D2A** (definição canônica), **#050517** (o que
> compila) ou **#373435** (o que está gravado no banco de produção pelo tema semeado)? A decisão muda a
> aparência do produto no dia 1 e precisa do usuário. Ver também OPS-750, que traz um **quarto** valor
> (#504746).

#### Scenario: ambiente novo sem tema
- **GIVEN** um banco recém-criado
- **WHEN** o primeiro usuário é criado
- **THEN** o tema padrão já existe e a criação passa, em vez de falhar na validação de tema

#### Scenario: tema padrão não pertence a usuário
- **GIVEN** o tema global padrão
- **WHEN** seu vínculo com usuário é inspecionado
- **THEN** ele não tem dono, e continua válido mesmo sem nenhum usuário no banco

#### Scenario: um único padrão
- **GIVEN** o tema padrão já semeado
- **WHEN** a semeadura roda de novo
- **THEN** continua existindo exatamente um tema marcado como padrão

### Requirement: OPS-544 — Textos de contrato semeados e versionados
O ai9 **MUST** portar os textos dos contratos aceitos pelo usuário (Termos de Uso e Política de
Privacidade) como conteúdo versionado, e **MUST** criar um contrato por tipo apenas quando ainda não
houver nenhum, gerando o vínculo de aceite pendente para os usuários que ainda não aceitaram. Fonte
legada: `db/seed_assets/contracts/privacy.html`, `tou.html` e `user.html`; consumidos em
`db/seeds.rb:112-158` sob `should_perform_contract_seed` (hoje `false`) **e** `Contract.count == 0`.

- O legado lê o HTML com `FileToStringDecoder.parse_and_fix_new_lines` (`lib/file_to_string_decoder.rb`,
  ver OPS-477) e depois cria um `ContractDeal` para todo usuário que ainda não aceitou.
- `user.html` **não é referenciado por nenhum seed** — é um arquivo órfão. Ele **MUST NOT** ser portado
  sem que se identifique um consumidor.
- O conteúdo é HTML de terceiros renderizado ao usuário: no ai9 ele **MUST** ser tratado como conteúdo
  confiável versionado, e **MUST NOT** ser concatenado com entrada de usuário.

> AMBIGUIDADE: os textos versionados no repositório podem estar defasados em relação aos contratos
> efetivamente aceitos em produção. Antes do cutover é preciso confirmar com o usuário se o vigente é o
> do arquivo ou o da linha em `contracts` (ver DB-546), e se um novo aceite deve ser exigido.

#### Scenario: primeiro provisionamento
- **GIVEN** um ambiente sem nenhum contrato cadastrado
- **WHEN** a semeadura roda
- **THEN** existe um contrato por tipo, com o texto versionado, e cada usuário sem aceite ganha um vínculo pendente

#### Scenario: contratos já existentes
- **GIVEN** contratos já cadastrados em produção
- **WHEN** a semeadura roda
- **THEN** nada é sobrescrito, preservando a guarda `Contract.count == 0` do legado

#### Scenario: arquivo órfão
- **GIVEN** o arquivo de contrato sem nenhum consumidor no legado
- **WHEN** o escopo da migração é fechado
- **THEN** ele consta como descartado com evidência de zero referências

### Requirement: OPS-545 — Textos de ajuda de campo são mecanismo, não conteúdo
O ai9 **MUST** portar apenas o **mecanismo** de ajuda contextual por campo de formulário, e **MUST NOT**
portar o conteúdo dos arquivos do legado, que é integralmente placeholder. Fonte legada:
`db/seed_assets/receivables_help_inputs.yml`, `db/seed_assets/risk_operations_help_inputs.yml` e
`db/seed_assets/structured_operations_help_inputs.yml`, lidos em runtime pela interface (não por
`db:seed`).

- Os arquivos são mapas `coluna → texto de ajuda`. As ~60 chaves do arquivo de recebíveis têm
  literalmente o texto "Só um teste de informações do campo pra descrever para que serve cada campo".
- Não são dados de produção: são um contrato de interface vazio.
- Se a interface do ai9 depender do mecanismo, ele **MUST** tolerar chave ausente sem quebrar a tela, e o
  conteúdo real **MUST** ser fornecido pelo usuário.

> AMBIGUIDADE: o usuário precisa decidir se quer a ajuda de campo no ai9. Se sim, o texto de cada campo
> é conteúdo novo a ser escrito por ele — não há nada a migrar.

#### Scenario: campo sem texto de ajuda
- **GIVEN** um campo cuja chave não existe no mapa de ajuda
- **WHEN** o formulário é renderizado
- **THEN** o campo aparece sem indicador de ajuda, sem erro e sem espaço vazio

#### Scenario: conteúdo placeholder não vai para produção
- **GIVEN** os textos de ajuda do legado
- **WHEN** o conteúdo do ai9 é revisado
- **THEN** nenhum texto placeholder do legado está presente

### Requirement: OPS-546 — Dump do banco pré-Rails não é portado
O ai9 **MUST NOT** portar o dump `db/seed_assets/sfg_legacy_full.sql` (**9,0 MB**, commitado no
repositório do legado) nem qualquer procedimento que dependa dele. Fonte legada:
`db/seed_assets/sfg_legacy_full.sql`, aplicado à mão com `psql` para popular o banco `SG20210329` antes
de rodar `Legacy::execute`.

- O dump é o banco completo do sistema **Django/Python** anterior ao Rails, com tabelas
  `authentication_user`, `dprojeto`, `dbanco`, `fbordero`, `dtarifa`, `dcarteira`, `dsegmento`,
  `dtiporecebivel`, `durecliq`, `fbancoproj`, `fbortarifa` e `authentication_user_projetos`.
- É a fonte original dos dados históricos que **já estão** no banco Rails de produção: portar o dump
  seria reimportar dados que já foram importados em 2021.
- A proveniência desses dados **MUST** continuar resolvível pelas colunas `legacy_*` (ver OPS-547 e
  DB-ETL-05), não pelo dump.

> Nota: DEC-12 — o pipeline `Legacy::execute` é assumido como não executado desde 2021; o dump, a
> conexão secundária e o código do ETL **não são portados** (D-105).

#### Scenario: repositório do ai9 sem dump
- **GIVEN** o repositório do ai9
- **WHEN** ele é inspecionado
- **THEN** nenhum dump de banco está versionado, nem do sistema anterior nem de qualquer outro

#### Scenario: pergunta sobre origem de um registro de 2016
- **GIVEN** um borderô importado em 2021
- **WHEN** sua origem é consultada
- **THEN** a resposta vem do identificador legado preservado, sem precisar do dump

### Requirement: OPS-547 — ETL Django→Rails não é portado, mas sua proveniência é preservada
O ai9 **MUST NOT** portar o pipeline `Legacy::execute` como código de aplicação, e **MUST** preservar
todas as colunas `legacy_*` das tabelas de destino, que são a **única prova de proveniência** dos
borderôs de 2016-2021. Fonte legada: `app/models/legacy.rb:1-112` e os 17 arquivos em
`app/models/legacy/`; acionado por `db/seeds.rb:258-260` sob `should_migrate_legacy_database` (hoje
`false`).

- O pipeline migra 12 entidades em **ordem fixa** (`legacy.rb:2-15`): Carrier → Segment →
  ReceivableKind → Wallet → ResourceSource → MovementKind → U → Project → Membership →
  ProjectToCarrierConnection → ReceivableEntry → ReceivableTax, cada uma por um `Adapter.adapt` que
  cria o registro novo gravando `legacy_id`.
- Em seguida rodam 4 **interceptors** de correção (`legacy.rb:17-22`): projeto padrão do usuário,
  responsável do projeto, membership do responsável e recálculo de todos os recebíveis. O comportamento
  que **produziu** os dados históricos fica registrado (ver BE-450..BE-454 em
  `openspec/specs/misc-domain/spec.md`), mas o código não é migrado.
- Foi executado **uma única vez**, em 2021 — o próprio nome do banco de origem (`SG20210329`) carrega a
  data.

> Nota: DEC-12 — assumido como não executado desde 2021 (D-105). Risco baixo e registrado: se o
> pipeline ainda rodar em produção, algum fluxo de importação pararia no cutover. Confirmação barata:
> `SELECT max(created_at) FROM <tabela> WHERE legacy_id IS NOT NULL` — data máxima em 2021 confirma a
> suposição (ver DB-ETL-05).

#### Scenario: identificador legado sobrevive à migração
- **GIVEN** registros com `legacy_id` preenchido
- **WHEN** o ETL para o ai9 roda
- **THEN** o valor de `legacy_id` é copiado sem alteração, e nenhuma coluna `legacy_*` é descartada

#### Scenario: código do ETL antigo ausente
- **GIVEN** o código-fonte do ai9
- **WHEN** ele é varrido por modelos-espelho do sistema Django
- **THEN** nenhum existe, e nenhum adaptador ou interceptor daquele pipeline foi portado

#### Scenario: verificação da suposição antes do cutover
- **GIVEN** a suposição de que o pipeline não roda desde 2021
- **WHEN** a data máxima de criação de registros com `legacy_id` é consultada
- **THEN** uma data de 2021 confirma a suposição, e qualquer data recente é sinalizada como contradição a decidir

### Requirement: OPS-548 — Conexão secundária com o banco do sistema anterior não existe
O ai9 **MUST** operar com **uma única** conexão de banco, eliminando a conexão secundária `sfg_legacy`
do legado, e **MUST** tratar a credencial dela como comprometida e rotacionada. Fonte legada:
`config/database.linux.yml:10-16`, `database.centos.yml:9-15`, `database.osx.yml:9-15`,
`database.win.yml:19-25`, `database.arch.yml:1-7`; usada por `establish_connection :sfg_legacy` em cada
`app/models/legacy/*.rb`.

- A conexão aponta para o segundo banco PostgreSQL `SG20210329` (o dump Django de OPS-546) e é aberta
  sempre que uma classe `Legacy::*` é carregada.
- Ela está declarada nos **5** arquivos de exemplo de `database.yml`, inclusive no de produção: se o
  banco não existir, qualquer referência a `Legacy::*` levanta erro de conexão.
- A senha dessa conexão está **commitada em texto puro** nos arquivos de exemplo do legado.

> Nota: DEC-12 — a conexão não é portada (D-105). Ver também BE-434 e DB-434 em
> `openspec/specs/misc-domain/spec.md`.

#### Scenario: configuração de banco do ai9
- **GIVEN** a configuração de banco do ai9
- **WHEN** ela é inspecionada
- **THEN** existe uma única conexão, e nenhuma credencial está versionada em texto puro

#### Scenario: ausência do banco antigo não afeta o boot
- **GIVEN** um ambiente onde o banco do sistema anterior não existe
- **WHEN** a aplicação sobe e opera
- **THEN** nada falha, porque nenhum código tenta abrir aquela conexão

### Requirement: OPS-549 — Esquema reprodutível a partir do repositório
O ai9 **MUST** manter o esquema do banco **versionado e reprodutível a partir do repositório**,
corrigindo a situação do legado, onde `/db/schema.rb` está no `.gitignore:15` e não existe
`structure.sql`. Fonte legada: `.gitignore:15`; as 139 migrations do app mais as das 4 engines que
criam tabela.

- No legado o esquema **só** se reconstrói rodando `rails db:migrate` sobre todas as migrations, e a
  reconstrução **não é garantida**: várias migrations foram escritas contra MySQL (`limit: 16777214`,
  `socket: /tmp/mysql.sock`) e outras declaram `Migration[4.2]`; o alvo é PostgreSQL 16 com Rails 8
  (ver DEC-05).
- As migrations das engines não estão em `db/migrate`: são injetadas no boot pelo initializer
  `append_migrations` de cada engine, então **o histórico do banco depende da ordem de montagem das
  engines** (ver DB-599 e OPS-749).
- A verificação de que a reconstrução corresponde ao banco real **MUST** ser feita pela **etapa de
  introspecção** já especificada em **DB-ETL-01**, que lê o esquema real no momento da execução e aborta
  com relatório ao encontrar tabela, coluna ou índice desconhecido. Este requisito **não** duplica esse
  contrato: ele o referencia.
- DEC-04 registra o risco aceito: já há **duas provas** de estrutura fora das migrations —
  `default_position` (D-06) e `contracts.description` (D-108) são usadas em código e nenhuma migration
  as cria.

#### Scenario: esquema versionado
- **GIVEN** o repositório do ai9 recém-clonado
- **WHEN** o banco é criado a partir dele
- **THEN** o esquema resultante é o esperado, sem depender de replay de migrations de outra stack

#### Scenario: divergência entre repositório e banco real
- **GIVEN** o banco legado com uma coluna que nenhuma migration cria
- **WHEN** a etapa de introspecção de DB-ETL-01 roda no dry-run
- **THEN** a divergência é reportada antes do cutover, e não descoberta durante ele

#### Scenario: ordem de montagem não define mais o esquema
- **GIVEN** o esquema do ai9
- **WHEN** ele é reconstruído
- **THEN** o resultado independe de ordem de carregamento de dependências, porque não há migrations injetadas por engine
