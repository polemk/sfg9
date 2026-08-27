# Inventário — esquema de dados (IDs 540–599)

## Visão geral

- **Fonte usada:** **as migrations** (`db/migrate/*.rb` + `engines/*/db/migrate/*.rb`) e os
  models (`app/models/`, `engines/*/app/models/`). **Não existe `db/schema.rb` nem
  `db/structure.sql` versionado** — `/db/schema.rb` está no `.gitignore`
  (`.gitignore:15`) e `structure.sql` não existe no repositório. **O esquema neste
  documento é uma reconstrução determinística das migrations**, não uma leitura do banco.
- **Total de migrations:** 104 na app (`db/migrate/`) + 35 nas engines = **139**.
  - `engines/auth19` 14 · `auth_omni19` 2 · `feedback19` 13 · `mailer19` 5 ·
    `auth_ux19` 0 · `ux_kit19` 0 · `navkit` 0 (essas três engines **não criam tabelas**).
- **Período:** `20160124203946` (2016-01-24, `create_pictures`) → `20220818201713`
  (2022-08-18, `add_original_value_column_to_availability_entries`).
  As migrations mais antigas do conjunto são das engines (`20160409121830`), mas a
  numeração da app começa antes.
- **Total de tabelas: 67** (52 da app + 15 das engines), mais 2 tabelas internas do Rails
  (`schema_migrations`, `ar_internal_metadata`) → **69 objetos no banco**.
- **Banco:** PostgreSQL (`gem 'pg'`, `config/database.centos.yml:1-7` production =
  postgresql). ⚠️ `config/database.linux.yml:18-26` declara `production:` com
  `adapter: mysql2` — resíduo. Ver risco DR-06.
- **Chaves primárias:** todas `id` serial/bigint auto-incremento (nenhuma migration usa
  `id: :uuid`). ⚠️ O ai9 usa **UUID** em 34 das 96 tabelas
  (`backend/db/schema.rb:19`) — decisão de PK é do Phase 3, ver risco DR-01.
- **Foreign keys no banco: exatamente 1** —
  `active_storage_attachments.blob_id → active_storage_blobs.id`
  (`db/migrate/20190310025434_create_active_storage_tables.active_storage.rb:24`).
  **Todo o resto do relacionamento é apenas de aplicação.**
- **`belongs_to` opcional por padrão:** `config/application.rb:24` faz
  `belongs_to_required_by_default = false`. Nenhum `belongs_to` valida presença por si.
- **Timezone:** `config/application.rb:28-29` — `default_timezone = :local` e
  `time_zone = 'Brasilia'`. **Datetimes estão gravados em horário local, não em UTC.**
  Ver risco DR-02.

### Legenda de fontes
Todos os caminhos são relativos à raiz do legado (`../sfg`).
`M/<timestamp>` abrevia `db/migrate/<timestamp>_*.rb`;
`E/<engine>/<timestamp>` abrevia `engines/<engine>/db/migrate/<timestamp>_*.rb`.

---

## Data (DB)

### Auth & identidade

| ID | Tabela / model | Fonte | Colunas / tipos | Relações & índices | Volume aprox. | Notas de migração |
| -- | -------------- | ----- | --------------- | ------------------ | ------------- | ----------------- |
| DB-540 | `livetat_auth_users` / `Livetat::Auth::User` (alias global `U`, `engines/auth19/app/models/livetat/auth/user.rb:286`) | `E/auth19/20160409121830:3-35` (base) · `E/auth19/20160409121831:3-5` (avatar) · `M/20171120004723:3` (kind) · `M/20190121164730:3` (manager_id) · `M/20190207025722:3` (identifier) · `M/20190419000711:3` (color) · `M/20200206191948:3` (app_theme_id) · `M/20210303182740:3` (default_project_id) · `M/20210402111120:2-8` (legacy_id) · `M/20210402134709:3` (legacy_password) · `M/20210402135252:3` (is_active) · `M/20220523124957:3` (deactivated) · `M/20220525124802:3` (is_default_member) | `id` PK · `formal` string · `username` string · `unconfirmed_email` string · `email` string NOT NULL default `""` · `encrypted_password` string NOT NULL default `""` · `authentication_token`/`reset_password_token`/`confirmation_token`/`unlock_token` string · `sign_in_count` int NOT NULL d0 · `failed_attempts` int NOT NULL d0 · `current_sign_in_ip`/`last_sign_in_ip` string · `current_sign_in_at`/`last_sign_in_at`/`confirmation_sent_at`/`reset_password_sent_at`/`remember_created_at`/`locked_at`/`confirmed_at` datetime · `created_at`/`updated_at` · **Paperclip:** `avatar_file_name`, `avatar_content_type`, `avatar_file_size` (int), `avatar_updated_at` (datetime) · `kind` string · `manager_id` int · `identifier` string · `color` string · `app_theme_id` int · `default_project_id` int · `legacy_id` int · `legacy_password` string · `is_active` int d1 · `deactivated` boolean d false · `is_default_member` int d0 | `has_one :role` (dep. destroy) · `has_one :info` (dep. destroy) · `belongs_to :app_theme` · `belongs_to :default_project` (Project) · `belongs_to :dependent` (self, `manager_id`) / `has_many :dependents` · `has_many :memberships` **dep. delete_all** · `has_many :projects, through: :memberships, source_type: 'Project'` · `has_many :contract_deals` · `has_many :receivables` (`app/decorators/models/user_decorator.rb:37-46`) · **Índices únicos:** `email`, `reset_password_token`, `confirmation_token`, `unlock_token`, `authentication_token`, `legacy_id` | desconhecido — tabela pequena (usuários internos Safegold) | `role_type` **não é coluna** — é atributo virtual (`user.rb:191-196`, persistido via `livetat_auth_roles`). Devise: `database_authenticatable, registerable, recoverable, rememberable, trackable, validatable, omniauthable` (`user.rb:27-28`). Dois flags de desativação concorrentes: `is_active` (int 0/1) e `deactivated` (boolean) — reconciliar. `legacy_password` guarda o hash **Django** do sistema pré-2021 (ver DB-599/OPS-547). |
| DB-541 | `livetat_auth_user_infos` / `Livetat::Auth::UserInfo` | `E/auth19/20171020133117:3-38` · `E/auth19/20171201171447:3-5` · `E/auth19/20171201171448:3-11` · `E/auth19/20171204213707:3` · `E/auth19/20171206031439:3` · `E/auth19/20171213170127:3-6` | `id` · `user_id` int · `first_name`/`last_name` string · `gender` int · `birthday` timestamp · `public_email`/`professional_email` string · `cpf`/`cnpj` string · `phone_confirmation_code`/`complementary_phone_confirmation_code` string · `is_phone_checked`/`is_complementary_phone_checked` int · `language` string · `living_address` string · `biography` text · `graduation`/`work` string · `is_emergency_contact_active` int · `emergency_contact_name`/`_phone`/`_email`/`_relation` string · `is_delivery_location_active` int · `delivery_location_country`/`_address`/`_complement`/`_city`/`_state`/`_cep`/`_address_number` string · `tax_document_number`/`_issuer`/`_issue_date` string · `phone_country_code` string d`"55"` · `phone_area_code`/`phone_number` string · `complementary_phone_country_code` string d`"55"` · `complementary_phone_area_code`/`_number` string · `confiability_level` string d`"Baixa"` · timestamps | `belongs_to :user` · validação de unicidade de `user_id` (app-level, `user_info.rb:18`) · **sem índice em `user_id`** | desconhecido — 1:1 com usuários, pequena | Colunas `phone` e `complementary_phone` foram **criadas e removidas** (`E/auth19/20171201171448:6,11`); `phone_country_code` foi removida/recriada 2× (`E/auth19/20171213170127`). `confiability_level` é enum-string PT-BR com default `"Baixa"`. Tabela largamente não usada pelo produto Safegold (herança da engine genérica) — candidata a poda no Phase 2. |
| DB-542 | `livetat_auth_roles` + `livetat_auth_role_types` + `livetat_auth_abilities` / `Livetat::Auth::Role`, `::RoleType`, `::Ability` **(3 tabelas agrupadas — modelo de permissão da engine)** | `E/auth19/20160409121832:3-8` (roles) · `E/auth19/20160409121833:3-7` (role_types) · `E/auth19/20160409121836:3` (hierarchy) · `E/auth19/20160409121834:3-10` (abilities) · `E/auth19/20160824171513:3-4` (description, type) | **roles:** `id`, `role_type_id` int, `user_id` int, timestamps · **role_types:** `id`, `name` string, `hierarchy` int, timestamps · **abilities:** `id`, `name` string, `value` int, `abilitable_id` int, `abilitable_type` string, `description` string, `type` string, timestamps | `Role belongs_to :role_type, :livetat_auth_user` · `Role has_many :abilities, as: :abilitable` (dep. delete_all) · `RoleType has_many :roles` + `has_many :abilities, as: :abilitable` (dep. delete_all) · `Ability belongs_to :abilitable` polimórfico (`abilitable_type ∈ {Livetat::Auth::Role, Livetat::Auth::RoleType}`) · `RoleType.name` único (app-level) · ⚠️ **sem índice em `abilitable`**: a migration é `Migration[4.2]`, onde `t.references ... polymorphic: true` **não** cria índice | desconhecido — role_types ~4 linhas (seed), roles 1:1 com usuários, abilities ≈ 16 × role_types + 16 × roles | `Ability` faz `self.inheritance_column = nil` (`ability.rb:2`) — **`type` NÃO é STI**, é um campo livre com valores `"conditional"`/`"limit"` (`engines/auth19/lib/livetat/auth/ability_factory.rb:56-74`). Migrar como enum. `RoleType.name` guarda os papéis do produto (`Administrador`/`Gestor`/`Colaborador` — ver OPS-540/OPS-541). |
| DB-543 | `livetat_auth_client_applications` / `Livetat::Auth::ClientApplication` | `E/auth19/20160409121835:3-9` · `M/20200211205426:3-5` | `id`, `name` string, `agent` string, `authentication_token` string, timestamps, `external_id` int, `color` string, `default_user_id` int | `name` e `agent` únicos (app-level, `client_application.rb:4-5`) · **sem índices no banco** | desconhecido — muito pequena (poucas apps cliente) | Colide por nome com `client_applications` já existente no ai9 (`backend/db/schema.rb`). Renomear ou fundir no Phase 2. |
| DB-544 | `livetat_auth_omni_providers` / `Livetat::AuthOmni19::Provider` | `E/auth_omni19/20170722163911:3-10` · `E/auth_omni19/20170722164423:3` | `id`, `name` string, `uid` string, `user_id` int, timestamps | `belongs_to :user` · **índice único `[name, uid, user_id]`** | desconhecido — provavelmente vazia (login social não usado no Safegold) | `uid` aqui é o UID do provedor OAuth (Facebook), **não** tem relação com a gem `public_uid`. Confirmar com o dono se o login social está ativo antes de migrar. |
| DB-545 | `memberships` / `Membership` | `M/20210301171119:3-10` · `M/20210402111120:2-8` (legacy_id) · `M/20210403175036:3-4` | `id`, `user_id` int, `memberable_id` int, `memberable_type` string, `role` string, `is_active` int, timestamps, `legacy_id` int, `legacy_project_id` int, `legacy_user_id` int | `belongs_to :memberable` polimórfico · `belongs_to :user` · unicidade app-level `user_id` × `[memberable_id, memberable_type]` (`membership.rb:31`) · **índice único `legacy_id`** · ⚠️ **sem índice em `[memberable_type, memberable_id]` nem em `user_id`** | desconhecido — média (usuários × projetos) | `role` é **string PT-BR** com default aplicado no `after_initialize`: `"Responsável"`, `"Participante"`, `"Coordenador"`, `"Gestor"` (`membership.rb:9-21`). Na prática o único `memberable_type` gravado é `"Project"` (`app/decorators/models/user_decorator.rb:43`). `is_active` não tem default. |

### Núcleo do domínio — projetos, empresas, cedentes

| ID | Tabela / model | Fonte | Colunas / tipos | Relações & índices | Volume aprox. | Notas de migração |
| -- | -------------- | ----- | --------------- | ------------------ | ------------- | ----------------- |
| DB-546 | `contracts` / `Contract` | `M/20180405163859:3-10` | `id`, `title` string, `creator_id` int, `version` int, `kind` string, timestamps (NOT NULL) | `has_many :contract_deals` · `has_many :users, through: :contract_deals` · `belongs_to :creator` (User) · unicidade app-level `kind` × `version` (`contract.rb:9`) · sem índices | desconhecido — muito pequena (2 registros: TOU + Política) | `kind` é enum-string PT-BR: `"Termos de Uso"`, `"Politicas de Privacidade"` (`contract.rb:13-14`, note a falta de acento em "Politicas"). O corpo do contrato **não está numa coluna** desta migration — o seed grava em `description` (`db/seeds.rb:124`) ⚠️ **coluna `description` não é criada por nenhuma migration** → ver risco DR-08. |
| DB-547 | `contract_deals` / `ContractDeal` | `M/20180405164055:3-8` | `id`, `user_id` int, `contract_id` int, timestamps (NOT NULL) | `belongs_to :contract`, `belongs_to :user` · unicidade app-level `contract_id` × `user_id` (`contract_deal.rb:9`) · sem índices | desconhecido — 1 linha por usuário × contrato | Tabela de aceite. Sem índice em `user_id`/`contract_id` — a consulta do seed (`db/seeds.rb:144`) faz full scan. |
| DB-548 | `app_themes` / `AppTheme` (**STI**: `GlobalTheme`, `UserTheme`) | `M/20200205130201:3-25` | `id`, `user_id` int, `title` string, **`type` string (STI)**, `primary_color`/`second_color`/`accent_color` string, `style` string, `login_bkg_style`/`login_bkg_color` string, `bar_font_name`/`font_name` string, `is_default` int, **Paperclip ×4:** `symbol_logo_*`, `full_logo_*`, `text_logo_*`, `login_bkg_image_*` (cada um: `_file_name` string, `_content_type` string, `_file_size` int, `_updated_at` datetime), `override_css` text, `cached_css` text, `display_name` string, `copyright` string, timestamps | `belongs_to :user` · `UserTheme has_many :users` (`app_themes.id ← livetat_auth_users.app_theme_id`) · `title` único (app-level) · sem índices | desconhecido — muito pequena (1 tema global + temas por usuário) | **16 colunas Paperclip** só nesta tabela. `type` é STI real (`GlobalTheme`/`UserTheme`). `style`/`login_bkg_style`/`font_name` são enum-strings em inglês: `"Dark"`/`"Light"`, `"Color"`/`"Image"`/`"Default"`, `"Helvetica"`/`"Arial"`/`"Tahoma"`/`"Baloo Thambi 2"`/`"Lato"` (`app_theme.rb:75-86`). `cached_css` é **CSS gerado e cacheado no banco** — decidir se recalcula no ai9 em vez de migrar. |
| DB-549 | `projects` / `Project` | `M/20210301170412:3-32` · `M/20210402111120:2-8` · `M/20210511211918:3` · `M/20211025163624:3` · `M/20220524121821:3` · `M/20220620140220:3` | `id`, `formal` string, `integration_key` string, `user_id` int, `smart_id` string, `segment_id` int, `is_active` int d1, `color` string, **Paperclip:** `avatar_file_name`/`_content_type`/`_file_size`/`_updated_at`, `address_type`/`address`/`address_number`/`address_complement`/`neighborhood`/`cep`/`address_state`/`address_city`/`city` string, `closing_date` date, `importing_id` int, `responsible_email` string, `responsible_formal` string, **`responsible_id` string ⚠️**, `job_state` string, `job_report` text, `job_id` int, timestamps, `legacy_id` int, `has_safegold_management` int d1, `sub_segment_id` int, `is_sandbox` int d0, `has_bi` int d0 | `belongs_to :responsible` (User, via `responsible_id`), `:job` (`Delayed::Job`), `:segment`, `:sub_segment`, `:user` · `has_many :memberships (as: :memberable, dep. delete_all)`, `:users through`, `:project_to_carrier_connections (restrict_with_error)`, `:carriers through`, `:project_indicator_connections (restrict)`, `:indicators through`, `:indicator_entries (restrict)`, `:receivables (restrict)`, `:renegotiations (restrict)`, `:providers (destroy)`, `:companies (restrict)`, `:risk_controls (restrict)`, `:availability_entries (restrict)`, `:availability_templates (destroy)`, `:remunerations` (`app/models/project.rb:3-46`) · **índice único `legacy_id`** · sem outros índices | desconhecido — pequena/média (dezenas a poucas centenas de projetos) | ⚠️ **`responsible_id` é `string`** (`M/20210301170412:25`) mas é usado como FK inteira para `livetat_auth_users` — ver risco DR-03. Endereço duplicado: existem `address_city` **e** `city`. `has_safegold_management`, `is_sandbox`, `has_bi`, `is_active` são booleanos-inteiros. Colide por nome com `projects` do ai9 (`backend/db/schema.rb`, PK uuid, domínio totalmente diferente) — ver risco DR-01. |
| DB-550 | `segments` / `Segment` | `M/20210317140228:3-11` · `M/20210402111120:2-8` | `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int, timestamps, `legacy_id` int | `has_many :projects (restrict_with_error)` · `title` único (app-level) · **índice único `legacy_id`** | desconhecido — tabela de domínio pequena (≈3 linhas de seed) | Seed de produção em `db/seeds.rb:160-164` (Comércio, Indústria, Serviços) — está atrás de flag `false`, dado já em produção. |
| DB-551 | `sub_segments` / `SubSegment` | `M/20211025163246:3-11` | `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int, timestamps | `has_many :projects (restrict_with_error)` · `title` único (app-level) · sem índices | desconhecido — tabela de domínio pequena | **Não recebeu `legacy_id`** (criada depois do ETL). Sem seed — populada só pela UI. |
| DB-552 | `carriers` / `Carrier` | `M/20210301192131:3-18` · `M/20210402111120:2-8` · `M/20210819194535:3` · `M/20220620135412:3` · `M/20220810142317:3-4` | `id`, `title` string, `resume` text, `user_id` int, `is_active` int d1, **Paperclip:** `logo_*` ×4, `integration_key` string, `bank_code` int, `bank_name` string, `senior_accounts` int d0, `subordinated_accounts` int d0, `net_worth` **decimal(15,2)** d0, `subordinated_accounts_percent` **float** d0.0, timestamps, `legacy_id` int, `group_id` int, `financial_agent` string, `city` string, `uf` string | `has_many :project_to_carrier_connections (restrict)`, `:projects through`, `:companies through: :projects`, `:receivables (restrict)`, `:risk_controls (destroy)` · `belongs_to :group` (CarrierGroup) · **índice único `legacy_id`** | desconhecido — pequena (dezenas de bancos/FIDCs) | `financial_agent` é enum-string: `"FIDC"`, `"Securitizadora"`, `"Factoring"`, `"Cliente"` (`carrier.rb:46-49`). `risk_controls` é `dependent: :destroy` (**apaga em cascata**) enquanto os demais são `restrict_with_error` — importante na migração/limpeza. `net_worth` decimal vs `subordinated_accounts_percent` float — ver DR-04. |
| DB-553 | `carrier_groups` / `CarrierGroup` | `M/20210819193736:3-11` | `id`, `title` string, `user_id` int, `carriers_count` int, timestamps | `has_many :carriers` com **`counter_cache: :carriers_count`** · `belongs_to :user` · sem índices | desconhecido — muito pequena | `carriers_count` **sem default** → NULL nas linhas antigas; o counter cache do Rails quebra com NULL. Ver risco DR-09. |
| DB-554 | `project_to_carrier_connections` / `ProjectToCarrierConnection` | `M/20210301192607:3-8` · `M/20210402111120:2-8` · `M/20210403154220:3-4` | `id`, `project_id` int, `carrier_id` int, timestamps, `legacy_id` int, `legacy_project_id` int, `legacy_carrier_id` int | tabela de junção projeto↔cedente · unicidade app-level `carrier_id` × `project_id` · **índice único `legacy_id`** · ⚠️ **sem índice em `project_id`/`carrier_id`** | desconhecido — média (projetos × bancos) | Junção explícita (tem `id` e timestamps), **não** é HABTM. Nenhum HABTM existe no legado. |
| DB-555 | `companies` / `Company` | `M/20210510211117:3-9` · `M/20210511211918:7` | `id`, `project_id` int, `title` string, timestamps, `has_safegold_management` int d1 | `belongs_to :project` · `has_many :carriers, through: :project` · `has_many :risk_controls (restrict)`, `:receivables (restrict)` · unicidade app-level `title` × `project_id` · sem índices | desconhecido — média (empresas por projeto) | Unidade de risco/operação abaixo do projeto. Sem `is_active` — não tem desativação. |
| DB-556 | `providers` / `Provider` | `M/20210325141909:3-15` · `M/20210426135539:3` · `M/20210504151249:3-18` | `id`, `title` string, `resume` text, `user_id` int, `project_id` int, `is_active` int d1, **Paperclip:** `logo_*` ×4, `integration_key` string, `cnpj` string, `cpf` string, `abertura` date, `bairro` string, `cep` string, `data_situacao` date, `email` string, `fantasia` string, `logradouro` string, `complemento` string, `municipio` string, `nome` string, `numero` string, `situacao` string, `telefone` string, `uf` string, **`atividades` text (JSON)**, **`cnaes` text (YAML)**, timestamps | `belongs_to :project` · `has_many :renegotiations (restrict)` · unicidade app-level de `cnpj` e `cpf` por `project_id` (`provider.rb:42-43`) · sem índices | desconhecido — média | ⚠️ **Dois formatos de serialização na mesma tabela:** `cnaes` usa `serialize :cnaes` (YAML, `provider.rb:2`) e `atividades` usa JSON à mão (`provider.rb:97-110`). Ver risco DR-05. Campos `nome`/`fantasia`/`logradouro`/… são o payload denormalizado da ReceitaWS. `limit: 16777214` nas duas colunas text é resquício MySQL (ignorado no PG). |
| DB-557 | `project_guarantees` / `ProjectGuarantee` | `M/20220627125026:3-12` | `id`, `project_id` int, `carrier_id` int, `user_id` int, `guarantee_type_id` int, `title` string, `value` decimal(15,2) d0, `observation` string, timestamps | `belongs_to :project, :carrier, :user, :guarantee_type` · sem índices | desconhecido — pequena | `observation` é `string` (varchar) e não `text` — limite de 255 no PG? Não: no PG `string` sem limite vira `character varying` sem limite. Ok, mas inconsistente com `observacoes`/`observation` de outras tabelas (algumas `text`). |
| DB-558 | `project_guarantee_types` / `ProjectGuaranteeType` | `M/20220627125208:3-10` | `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int, timestamps | `has_many :guarantee (restrict)` · `title` único (app-level) · scope `active` = `is_active = 1` · sem índices | desconhecido — tabela de domínio muito pequena | **Sem seed** — se o ai9 subir vazio, não dá para cadastrar garantia. Ver DR-10. |

### Recebíveis

| ID | Tabela / model | Fonte | Colunas / tipos | Relações & índices | Volume aprox. | Notas de migração |
| -- | -------------- | ----- | --------------- | ------------------ | ------------- | ----------------- |
| DB-559 | `wallets` / `Wallet` | `M/20210317140156:3-10` · `M/20210402111120:2-8` | `id`, `title` string, `user_id` int, `integration_key` string, `is_active` int d1, timestamps, `legacy_id` int | `has_many :receivables (restrict)` · `title` único (app-level) · **índice único `legacy_id`** | desconhecido — domínio pequeno (≈10 linhas) | Seed em `db/seeds.rb:166-177` (ACC, ACE, Antecipação, Caução, Cheque, Comissária, Conta Garantida, Desconto, Domicílio, Fomento) — **dado de produção obrigatório**. |
| DB-560 | `receivable_kinds` / `ReceivableKind` | `M/20210317140206:3-11` · `M/20210402111120:2-8` | `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int, timestamps, `legacy_id` int | `has_many :receivables (restrict)` · `title` único · **índice único `legacy_id`** | desconhecido — domínio pequeno (≈5 linhas) | Seed em `db/seeds.rb:179-185` (Cheque, Duplicata, Cartão de crédito, ACC, PAC) — **obrigatório**. |
| DB-561 | `resource_kinds` / `ResourceKind` | `M/20210317140213:3-12` | `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int, `is_conta_corrente` int d1, `is_unique` int d1, timestamps | `has_many :receivables (restrict)` · `title` único · sem índices | desconhecido — domínio pequeno (≈5 linhas) | **Sem `legacy_id`** (não veio do ETL). Seed em `db/seeds.rb:197-203` — **obrigatório**. `receivable_entries.resource_kind_id` referencia esta tabela mas **não é validado** (`receivable_entry.rb` valida `resource_source_id`, não `resource_kind_id`). |
| DB-562 | `resource_sources` / `ResourceSource` | `M/20210317140220:3-11` · `M/20210402111120:2-8` | `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int, timestamps, `legacy_id` int | `has_many :receivables (restrict)` · `title` único · **índice único `legacy_id`** | desconhecido — domínio pequeno (≈7 linhas) | Seed em `db/seeds.rb:187-195` — **obrigatório**. |
| DB-563 | `movement_kinds` / `MovementKind` | `M/20210317151301:3-16` · `M/20210402111120:2-8` | `id`, `title` string, `user_id` int, `integration_key` string, `is_operation` int d0, `is_title` int d0, `is_active` int d1, `is_advalorem` int d0, `is_desagio` int d0, `is_iof` int d0, `is_liquidation` int d0, `kind` string, timestamps, `legacy_id` int | `has_many :receivable_taxes (restrict)` · ⚠️ `has_many :receivables, foreign_key: :movement_kind_id, class_name: "ReceivableEntry"` (`movement_kind.rb:2`) **aponta para coluna inexistente** · `title` único · **índice único `legacy_id`** | desconhecido — domínio pequeno (≈17 linhas) | ⚠️ **Associação quebrada** — `receivable_entries` não tem `movement_kind_id`. Ver risco DR-07. `kind` é enum-string PT-BR: `"Crédito"`/`"Débito"` (`movement_kind.rb:27-28`). Seed em `db/seeds.rb:205-223` — **obrigatório** (17 tipos de tarifa). |
| DB-564 | `receivable_entries` / `ReceivableEntry` (< `Entry`, abstrato) | `M/20210315183541:3-67` · `M/20210402111120:2-8` · `M/20210403171744:3` · `M/20210511211918:6` · `M/20220322123523:3-6` · `M/20220330140334:3` · `M/20220610122917:3-4` | `id`, `user_id`/`project_id`/`carrier_id`/`wallet_id`/`receivable_kind_id`/`resource_source_id`/`resource_kind_id` int, `date` date, **`nro_bordero` string** (era int, alterada em `M/20210403171744`), `qtd_titulos`/`qtd_recusada`/`qtd_final` int, **decimal(15,2):** `valor_bruto`, `vlr_bruto_recusado`, `vlr_bruto_final`, `valor_total_tarifas`, `valor_liquido`, `calc_valor_liq_correto`, `recompra` d0, `retencao` d0, `fomento` d0, `outros` d0, `total_deducoes` d0, `vlr_liq_recebido`, `tarifas_ad_valorem` d0, `tarifas_desagio` d0, `tarifas_iof` d0, `tarifas_outras` d0, `multiplicador_pm_empresa`, `multiplicador_pm_float` · **float:** `prz_med_pond_emp`, `prz_med_pond_bco`, `float_calculado`, `float_acordado`, `diferenca_float`, `checagem_iof`, `cst_efetivo_acordado`, `dif_calc_vlr_liq`, `recompra_percent`, `retencao_percent`, `fomento_percent`, `outros_percent`, `taxa_desconto_nominal_desagio_advalorem_bancos`, `taxa_desconto_nominal_despesas_bancos`, `taxa_desconto_nominal_despesas_iof_bancos`, `custo_efetivo_pz_med_banco`, `custo_efetivo_pz_med_banco_sem_iof`, `taxa_desconto_nominal_desagio_advalorem_emp`, `taxa_desconto_nominal_despesas_emp`, `taxa_desconto_nominal_despesas_iof_emp`, `custo_efetivo_pz_med_emp`, `custo_efetivo_pz_med_emp_sem_iof`, `custo_efetivo_sem_float`, `custo_efetivo_com_float_total`, `custo_efetivo_com_float_sem_iof`, `nominal_tax`, `nominal_tax_check`, `nominal_tax_check_with_float` · `status` string, `data_credito` date, `contrato` string, `observacoes` text, `description` text, timestamps, `legacy_id` int, `has_safegold_management` int d1, `company_id` int, `risk_operation_type_id` int, `risk_operation_subtype_id` int | `belongs_to :user, :project, :carrier, :wallet` (herdado de `Entry`), `:company`, `:risk_operation_type`, `:risk_operation_subtype` · `has_many :taxes` (ReceivableTax, **dep. destroy**) · `has_one :risk_operation` (`risk_operations.receivable_id`, **dep. destroy**) · **índice único `legacy_id`** · ⚠️ **nenhum outro índice** apesar de ser a maior tabela transacional | desconhecido — **maior tabela transacional** (borderôs históricos desde 2016 via ETL) | ~70 colunas, quase todas **derivadas** (recalculadas em `receivable_entry.rb`). `self.inheritance_column = :_type_disabled` (`receivable_entry.rb:2`) — não é STI. `status` é enum-string PT-BR `"Diferença"`/`"OK"` (`entry.rb:11-12`). Nomes de coluna em português abreviado (`vlr_`, `prz_`, `cst_`) — o Phase 3 precisa decidir se renomeia (impacta o mapa de ETL). Colunas monetárias `decimal(15,2)` mas taxas em `float` — ver DR-04. |
| DB-565 | `receivable_taxes` / `ReceivableTax` | `M/20210323134328:3-13` · `M/20210402111120:2-8` | `id`, `receivable_entry_id` int, `movement_kind_id` int, `value` decimal(15,2) d0, `title` string, `is_advalorem` int d0, `is_desagio` int d0, `is_iof` int d0, timestamps, `legacy_id` int | `belongs_to :receivable` (`receivable_entry_id`), `:movement_kind` · **índice único `legacy_id`** · ⚠️ sem índice em `receivable_entry_id` | desconhecido — **grande** (N tarifas por borderô) | `title` é **denormalizado** de `movement_kinds.title`; `is_advalorem`/`is_desagio`/`is_iof` também são cópias das flags do `MovementKind`. Ver DR-11. |
| DB-566 | `availability_templates` / `AvailabilityTemplate` (**STI**: `GlobalAvailabilityTemplate`, `ProjectAvailabilityTemplate`) | `M/20210420180734:3-27` · `M/20220224142653:3-4` · `M/20220225133130:3-5` · `M/20220325134030:3` · `M/20220818194956:3` | `id`, `title` string, `project_id` int, **`type` string (STI)**, `is_global` int d0, `is_mandatory` int d0, `is_active` int d1, `global_availability_template_id` int, `operation_type` string, `deadline_type` string, `user_id` int, `is_cumulative` int d1, `numeric_first_level`/`numeric_second_level`/`numeric_third_level` int, `max_level` int d0, `is_upper_level` int d0, `top_parent_id` int d0, `should_insert_on_existing_projects` int d1, **`position` string**, `parent_level` int, **`parent_position` string**, `parent_template_id` int, timestamps, `is_locked` int d0, `locked_at` datetime, `job_id` int, `job_report` text, `job_state` string, `locked_message` string, `is_adjusted` int d0 | Auto-relacionamentos: `belongs_to :parent_template`, `:top_parent` · `has_many :child_templates (destroy)`, `:availability_templates (top_parent_id, destroy)` · `GlobalAvailabilityTemplate has_many :project_templates` · `ProjectAvailabilityTemplate belongs_to :project, :global_template, :job` + `has_many :entries (restrict)` · unicidades app-level distintas por subclasse (`global_availability_template.rb:20`, `project_availability_template.rb:24-25`) · **sem índices** | desconhecido — **grande** (N templates globais × N projetos, hierarquia de 3 níveis) | ⚠️ **Hierarquia materializada em string**: `position` = `"1"`, `"1.2"`, `"1.2.3"` (`project_availability_template.rb:33,44,52`) além dos 3 inteiros `numeric_*_level` e de `parent_template_id`/`top_parent_id` — **quatro representações redundantes da mesma árvore**. `operation_type` guarda **siglas** `"C"`/`"D"`/`"S"`/`"M"` e `deadline_type` `"CP"`/`"LP"` (`availability_template.rb:32-46`). `top_parent_id` tem default `0` (**não NULL**) — valor mágico. |
| DB-567 | `availability_entries` / `AvailabilityEntry` (< `Entry`) | `M/20210420180813:3-12` · `M/20210511211918:4` · `M/20210804175519:3` · `M/20220818150945:3` · `M/20220818201713:3` | `id`, `title` string, `user_id` int, `project_id` int, `availability_template_id` int, `value` decimal(15,2) d0, `date` date, timestamps, `has_safegold_management` int d1, `virtual_value` decimal(15,2) d0, `company_id` int, `original_value` decimal(15,2) d0 | `belongs_to :project`, `:availability_template` (aponta para `ProjectAvailabilityTemplate`) · unicidade app-level `date` × `[project_id, company_id, availability_template_id]` (`availability_entry.rb:12`) · **sem índices** | desconhecido — **a maior tabela do sistema** (1 linha por template × projeto × data) | `self.inheritance_column = :_type_disabled` (`availability_entry.rb:2`). Três colunas de valor (`value`, `virtual_value`, `original_value`) com semânticas diferentes — mapear com o `data-engineer`. A unicidade composta **não** tem índice único no banco → duplicatas possíveis em concorrência (ver DR-12). |

### Renegociações

| ID | Tabela / model | Fonte | Colunas / tipos | Relações & índices | Volume aprox. | Notas de migração |
| -- | -------------- | ----- | --------------- | ------------------ | ------------- | ----------------- |
| DB-568 | `renegotiations` / `Renegotiation` | `M/20210324173930:3-35` · `M/20210503202015:3` · `M/20210511211918:5` · `M/20210512151746:3` · `M/20220407163633:3` · `M/20220429122226:3-13` · `M/20220620134050:3-4` | `id`, `provider_name` string, `provider_id` int, `project_id` int, `kind` string, `integration_key` string, **decimal(15,2) d0:** `original_value`, `original_pending_value`, `additional_value`, `total_debt`, `paid_value`, `remaining_value`, `installments_main_value` (renomeada de `total_value` em `M/20220429122226:4`), `correct_value`, `current_installment_value`, `current_value`, `installments_interest_value`, `installments_main_value_with_interest`, `installments_monetary_correction_value`, `installments_main_value_with_interest_cm`, `main_value`, `paid_value_with_interest_cm`, `pending_main_value`, `late_payment_value`, `desagio_value`, `total_value_with_desagio` · `renegotiation_date`/`first_due_date`/`last_due_date` date · **float:** `interest_rate_correction` d0, `operation_interest_rate`, `paid_percent` d0 · `grace_period` int d0 · `observation` text · `origin` string · `installments_count` int · `paid_installments`/`overdue_installments`/`due_installments` int d0 · `state` string · timestamps · `attachments_count` int · `has_safegold_management` int d1 · `title` string · `company_id` int · `monetary_correction` string | `belongs_to :project`, `:provider` · `has_many :installments (restrict)`, `:payments (restrict)`, `:attachments (destroy)` · scopes por `state` · **sem índices** | desconhecido — média | ⚠️ **`company_id` é validado como obrigatório (`renegotiation.rb:21`) mas NÃO existe nenhum `belongs_to :company`** no model. `provider_name` denormalizado de `providers.title`. `state` é enum-string PT-BR: `"Liquidado"`, `"Pago"`, `"Inconsistente"`, `"Sem parcela cadastrada"`; `kind`: `"Financeiro"`, `"Operacional"`, `"Tributario"` (sem acento), `"Trabalhista"` (`renegotiation.rb:41-49`). `attachments_count` **sem default** (counter cache) — ver DR-09. 20 colunas monetárias derivadas. |
| DB-569 | `renegotiation_installments` / `RenegotiationInstallment` | `M/20210324174436:3-18` · `M/20220429122346:3-10` | `id`, `renegotiation_id` int, `due_date` date, `installment` int, **decimal(15,2) d0:** `main_value` (renomeada de `value`), `paid_value`, `pending_value`, `saldo`, `interest_value`, `main_value_with_interest`, `monetary_correction_value`, `main_value_with_interest_cm`, `late_payment_value`, `installment_total_value` · `month`/`year` int · `batch_token` string · `is_paid` int d0 · `color` string · timestamps | `belongs_to :renegotiation` · `has_many :payments (restrict)` · unicidade app-level `due_date` × `renegotiation_id` · **sem índices** | desconhecido — grande (N parcelas × renegociações) | `batch_token` é um token aleatório de lote gerado em app com verificação de colisão por SELECT (`renegotiation_installment.rb:96-100`) — **sem índice único no banco**, corrida possível. `saldo` (PT) convive com `pending_value` (EN) na mesma tabela. `color` é apresentação persistida no banco. |
| DB-570 | `renegotiation_payments` / `RenegotiationPayment` | `M/20210324174615:3-12` · `M/20210426130102:3` · `M/20220429122419:3-6` | `id`, `renegotiation_id` int, `renegotiation_installment_id` int, `installment_paid_value_with_interest_cm` decimal(15,2) d0 (renomeada de `value`), `date` date, `days_late` int, timestamps, `payment_number` int d1, `late_payment_value` decimal(15,2) d0, `total_paid_value` decimal(15,2) d0 | `belongs_to :renegotiation`, `:renegotiation_installment` · **sem índices** | desconhecido — grande | Renomeação de `value`→`installment_paid_value_with_interest_cm` (`M/20220429122419:3`): dados anteriores a 04/2022 podem ter semântica diferente da atual (o valor "com juros e CM" era só o principal). ⚠️ Ver DR-13. |
| DB-571 | `renegotiation_attachments` / `RenegotiationAttachment` | `M/20210503195535:3-11` | `id`, `renegotiation_id` int, `user_id` int, `title` string, **Paperclip:** `file_file_name`, `file_content_type`, `file_file_size` int, `file_updated_at` datetime, timestamps | `belongs_to :renegotiation` com **`counter_cache: :attachments_count`** · sem índices | desconhecido — média | Binários no filesystem (`public/system/...`, ver DR-14), não no banco. |

### Risco e operações

| ID | Tabela / model | Fonte | Colunas / tipos | Relações & índices | Volume aprox. | Notas de migração |
| -- | -------------- | ----- | --------------- | ------------------ | ------------- | ----------------- |
| DB-572 | `risk_controls` / `RiskControl` | `M/20210510211438:3-16` · `M/20210511211918:8-9` · `M/20210603125803:3` · `M/20220223143338:3` · `M/20220611152145:3-8` | `id`, `company_id` int, `carrier_id` int, **decimal(15,2) d0:** `limite_auto_liquidaveis`, `limite_fomento`, `limite_comissaria`, `limite_intercompany`, `limite`, `original_balance`, `original_balance_pre` · **float d0:** `taxa_auto_liquidaveis`, `taxa_fomento`, `taxa_comissaria`, `taxa_intercompany`, `taxa` · timestamps · `has_safegold_management` int d1 · `project_id` int · `title` string · `is_active` int d1 · `risk_operation_type_id` int · `user_id` int | `belongs_to :company, :carrier, :project, :risk_operation_type` · `has_many :risk_entries (restrict)`, `:risk_operations (restrict)` · unicidade app-level `carrier_id` × `[company_id, risk_operation_type_id]` · scopes `active`/`inactive` · **sem índices** | desconhecido — média | ⚠️ **Modelo antigo e novo coexistem**: as 8 colunas `limite_*`/`taxa_*` (por tipo fixo, 2021) foram substituídas por `limite`/`taxa` + `risk_operation_type_id` (2022, `M/20220611152145`) **sem remover as antigas nem migrar os dados**. Ver risco DR-15. |
| DB-573 | `risk_entries` / `RiskEntry` | `M/20210510211736:3-19` · `M/20210511211918:10-11` · `M/20210603125803:4` · `M/20220321180205:3-8` · `M/20220325145251:3-5` | `id`, `risk_control_id` int, `company_id` int, `date` date, **decimal(15,2) d0:** `vencidos_value`, `a_vencer_value`, `total_carteira_value`, `liquidacao_value`, `descontos_value`, `total_reducoes_value`, `fomento_total_value` (ren. de `fomento_value`), `intercompany_total_value` (ren.), `comissaria_total_value` (ren.), `comissaria_vencidos_value`, `comissaria_a_vencer_value`, `fomento_vencidos_value`, `fomento_a_vencer_value`, `intercompany_vencidos_value`, `intercompany_a_vencer_value` · `observacoes` string · timestamps · `has_safegold_management` int d1 · `project_id` int · `risk_control_title` string | `belongs_to :company, :risk_control, :project` · unicidade app-level `date` × `[risk_control_id, company_id]` · **sem índices** | desconhecido — grande (1 linha por controle × dia) | Renomeações em `M/20220325145251` (`*_value` → `*_total_value`). `risk_control_title` **denormalizado** de `risk_controls.title`. `observacoes` é `string` (as outras tabelas usam `text`). |
| DB-574 | `risk_operation_types` / `RiskOperationType` | `M/20220606124734:3-17` | `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int, `is_default` int d0, `allow_manual_operations` int d1, `allow_receivable_entries` int d1, `has_pre_faturamento` int d0, timestamps | `has_many :operations (restrict)`, `:subtypes (destroy)` · `title` único · scopes `manual`, `receivable`, `active`, `with_pre` · sem índices | desconhecido — domínio pequeno (4 linhas) | **Seed ativo (`should_seed_risk_operation_type = true`, `db/seeds.rb:18,315-321`)**: Fomento, Comissária, Intercompany, Auto Liquidável — **dado de produção obrigatório no dia 1**. `user_id: 1` hardcoded no seed. |
| DB-575 | `risk_operation_subtypes` / `RiskOperationSubtype` | `M/20220621131905:3-18` | `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int, `is_default` int d0, `pair_id` int, `risk_operation_type_id` int, `is_pre` int d0, `allow_manual_operations` int d1, `allow_receivable_entries` int d1, timestamps | `belongs_to :operation_type` (RiskOperationType) · `has_many :operations (restrict)` · unicidade app-level `title` × `risk_operation_type_id` e `is_pre` × `risk_operation_type_id` · sem índices | desconhecido — domínio pequeno | **Sem seed** — se o ai9 subir vazio não há subtipos. `pair_id` aponta para outro subtipo (par pré/pós-faturamento) sem `belongs_to` declarado. |
| DB-576 | `risk_operations` / `RiskOperation` | `M/20220607123547:3-30` · `M/20220802225011:20` | `id`, `title` string, `user_id` int, `operation_type_id` int, `project_id` int, `company_id` int, `carrier_id` int, `risk_control_id` int, `contract_number` string, `issue_date` date, `operation_value` decimal(15,2) d0, `original_balance` decimal(15,2) d0, `balance` decimal(15,2) d0, `due_date` date, `agreed_rate` float d0, `observation` string, `is_on_variable` int d0, `is_ended` int d0, `original_id` int, `original_due_date` date, `receivable_id` int, `operation_subtype_id` int, `pair_id` int, timestamps, `receipt_id` int | `belongs_to :company, :carrier, :project, :user, :operation_type, :operation_subtype, :receivable, :original_operation (original_id)` · `has_one :pair_operation (pair_id)` · `has_one :receipt (operation_id, restrict)` · `has_many :movements (destroy)`, `:renovations (original_id)`, `:extensions` · scope `available_for_receipt` (`receipt_id: nil`) · **sem índices** | desconhecido — grande | ⚠️ `risk_control_id` é validado obrigatório (`risk_operation.rb:62`) mas **não há `belongs_to :risk_control`** no model. Duas direções de recibo: `risk_operations.receipt_id` **e** `receipts.operation_id/operation_type` — redundância bidirecional (DR-16). `has_one :pair_operation, foreign_key: :pair_id` é auto-relacionamento invertido, frágil. |
| DB-577 | `risk_operation_extensions` / `RiskOperationExtension` | `M/20220616181724:3-12` | `id`, `risk_operation_id` int, `user_id` int, `original_due_date` date, `new_due_date` date, `observation` string, timestamps | `belongs_to :operation` (`risk_operation_id`) · sem índices | desconhecido — pequena | Histórico de prorrogação. Sem `dependent:` no lado da operação (`RiskOperation has_many :extensions` sem `dependent`) → **órfãos** ao apagar operação. Ver DR-17. |
| DB-578 | `risk_movement_types` / `RiskMovementType` | `M/20220606160027:3-16` | `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int, `is_default` int d0, `is_system_exclusive` int d0, `credit_type_description` string, `credit_type` string, `is_transfer` int d0, timestamps | `has_many` via RiskMovement · `title` único · scope `manual` · sem índices | desconhecido — domínio pequeno (8 linhas) | **Seed ativo (`db/seeds.rb:19,323-332`)**: Juros, AdValorem, IOF, Liberação do Recurso, Liquidação, Juros de Mora, Transferência Recebida, Valor Transferido — **obrigatório no dia 1**. `credit_type` guarda siglas `"C"`/`"D"`; `credit_type_description` guarda `"Crédito"`/`"Débito"` — **duas colunas para o mesmo enum** (`risk_movement_type.rb:29-33`). |
| DB-579 | `risk_movements` / `RiskMovement` | `M/20220608162424:3-21` | `id`, `user_id` int, **`order` int** ⚠️, `date` date, `movement_type_id` int, `movement_value` decimal(15,2) d0, `balance` decimal(15,2) d0, `observation` string, `project_id` int, `company_id` int, `carrier_id` int, `risk_operation_id` int, `receivable_id` int, `pair_id` int, timestamps | `belongs_to :company, :carrier, :project, :user, :movement_type, :risk_operation` · `has_one :pair_movement (pair_id)` · `delegate :credit_type, to: :movement_type` · **sem índices** | desconhecido — **grande** (movimentos por operação) | ⚠️ Coluna chamada **`order`** — palavra reservada em SQL; exige aspas no PG e quebra em query builders. Renomear no ai9 (`sequence`/`position`). `balance` é saldo acumulado **persistido**, recalculado em app — sensível a ordem de migração (DR-18). |

### Operações estruturadas, remuneração e cobrança

| ID | Tabela / model | Fonte | Colunas / tipos | Relações & índices | Volume aprox. | Notas de migração |
| -- | -------------- | ----- | --------------- | ------------------ | ------------- | ----------------- |
| DB-580 | `structured_operation_types` / `StructuredOperationType` | `M/20220701123654:3-14` | `id`, `title` string, `integration_key` string, `is_active` int d1, `user_id` int, `is_default` int d0, `allow_manual_operations` int d1, `allow_receivable_entries` int d0, `has_pre_faturamento` int d0, timestamps | `has_many :operations (restrict)` · `title` único · scope `active` · sem índices | desconhecido — domínio pequeno (4 linhas) | **Seed ativo (`db/seeds.rb:20,334-339`)**: Fomento, Comissária, Intercompany, Auto Liquidável — **obrigatório**. ⚠️ `db/seeds.rb:338` usa `user_id: 11` (os outros usam `1`) — provável typo já em produção. |
| DB-581 | `structured_operations` / `StructuredOperation` | `M/20220701125757:3-23` · `M/20220802225011:19` | `id`, `title` string, `user_id` int, `operation_type_id` int, `project_id` int, `company_id` int, `carrier_id` int, `contract_number` string, `issue_date` date, `operation_value` decimal(15,2) d0, `original_balance` decimal(15,2) d0, `balance` decimal(15,2) d0, `due_date` date, `agreed_rate` float d0, `observation` string, `is_on_variable` int d0, `is_ended` int d0, timestamps, `receipt_id` int | `belongs_to :company, :carrier, :project, :user, :operation_type` · `has_one :receipt (operation_id, restrict)` · scope `available_for_receipt` · **sem índices** | desconhecido — média | Espelha `risk_operations` com menos colunas (sem `risk_control_id`, `receivable_id`, `pair_id`, `original_id`, subtipo). Candidata a unificação no ai9 — decisão do Phase 2. |
| DB-582 | `remunerations` / `Remuneration` | `M/20220629123512:3-11` · `M/20220802165837:3` | `id`, `project_id` int, `operation_type_id` int + `operation_type_type` string (**polimórfico**), **`value` float d0**, timestamps, `title` string | `belongs_to :project`, `belongs_to :operation_type` polimórfico (`RiskOperationType` \| `StructuredOperationType`) · `has_many :receipts` · unicidade app-level `operation_type_id` × `[operation_type_type, project_id]` · **índice em `[operation_type_type, operation_type_id]`** (`M/20220629123512:5`, `index: true`) | desconhecido — pequena (tipos × projetos) | `Project` filtra por `operation_type_type` em scopes inline (`project.rb:45-46`). `value` é **float** (taxa % 0–100) usada para calcular dinheiro — ver DR-04. |
| DB-583 | `charges` / `Charge` | `M/20220707164909:5-21` | `id`, `project_id` int, `user_id` int, `date` date, `state` string, **decimal(15,2) d0:** `value`, `structured_operations_value`, `risk_operations_value`, `total_operations_value` · **int d0:** `receipts_count`, `risk_operations_count`, `structured_operations_count` · timestamps | `belongs_to :project, :user` · `has_many :receipts (restrict)` · sem índices | desconhecido — pequena/média | `state` é enum-string PT-BR: `"Edição"`, `"Disponível"`, `"Faturado"` (`charge.rb:14-16`), default aplicado em callback. Os 3 contadores **não** são `counter_cache` do Rails — são mantidos à mão. Comentário na migration (`M/20220707164909:2-3`) documenta a decisão de nunca ligar cobrança↔operação direto, só via recibo. |
| DB-584 | `receipts` / `Receipt` | `M/20220802225011:3-17` · `M/20220804195335:3-4` | `id`, `temp_id` string, `project_id` int, `charge_id` int, `operation_id` int + `operation_type` string (**polimórfico**), `remuneration_id` int, `kind` string, `title` string, **`fee` float**, `operation_value` decimal(15,2), `value` decimal(15,2), `user_id` int, timestamps, `date` date, `operation_title` string | `belongs_to :charge, :project, :remuneration`, `belongs_to :operation` polimórfico (`RiskOperation` \| `StructuredOperation`) · unicidade app-level `operation_id` × `[project_id, operation_type]` · **índice em `[operation_type, operation_id]`** | desconhecido — média | `kind` (`"LIQ"`/`"EST"`, `receipt.rb:17-18`), `title` e `operation_title` são **denormalizados** de remuneração/operação. `temp_id` é id efêmero de UI persistido no banco — ver DR-19. |

### Indicadores

| ID | Tabela / model | Fonte | Colunas / tipos | Relações & índices | Volume aprox. | Notas de migração |
| -- | -------------- | ----- | --------------- | ------------------ | ------------- | ----------------- |
| DB-585 | `indicators` / `Indicator` | `M/20211026165448:3-9` · `M/20211027150648:3` · `M/20211029172624:3` · `M/20220223145902:3` | `id`, `title` string, `key` string, timestamps, `value_type` string, `project_id` int, `is_active` int d1 | `has_many :project_indicator_connections (restrict)`, `:projects through`, `:entries` (**dep. `delete_all`**, `indicator.rb:4`) · sem índices | desconhecido — pequena | `value_type` é enum-string PT-BR (`"Dinheiro"`, `indicator.rb:26`). `dependent: :delete_all` nas entries é **destrutivo e sem callbacks** — comentário `#7102` no código explica que foi para quebrar dependência cíclica. `key` sem unicidade no banco. |
| DB-586 | `project_indicator_connections` / `ProjectIndicatorConnection` | `M/20211026184044:3-9` | `id`, `project_id` int, `indicator_id` int, timestamps | junção projeto↔indicador · unicidade app-level `indicator_id` × `project_id` · **sem índices** | desconhecido — média | Mesma forma de `project_to_carrier_connections` (junção explícita). |
| DB-587 | `indicator_entries` / `IndicatorEntry` | `M/20211027140815:3-15` · `M/20211027150857:3` | `id`, `title` string, `user_id` int, `project_id` int, `indicator_id` int, `value` decimal(15,2) d0, `month` int, `year` int, `key` string, timestamps, `value_type` string | `belongs_to :project, :indicator, :user` · unicidade app-level `month` × `[year, project_id, indicator_id]` · **sem índices** | desconhecido — média/grande (indicadores × projetos × meses) | `title`, `key` e `value_type` **denormalizados** de `indicators`. `month`/`year` como inteiros separados em vez de `date` — cuidado no ETL. |

### Ajuda / FAQ

| ID | Tabela / model | Fonte | Colunas / tipos | Relações & índices | Volume aprox. | Notas de migração |
| -- | -------------- | ----- | --------------- | ------------------ | ------------- | ----------------- |
| DB-588 | `help_groups` / `HelpGroup` | `M/20180410131904:3-7` | `id`, `title` string, timestamps NOT NULL | `has_many :categories (destroy)`, `:items through` · `title` único (app-level) · sem índices | desconhecido — muito pequena | Model herda de `ActiveRecord::Base` direto (não de `ApplicationRecord`) — `help_group.rb:1`. Sem seed. |
| DB-589 | `help_categories` / `HelpCategory` | `M/20180410132114:3-8` | `id`, `title` string, `help_group_id` int, timestamps NOT NULL | `belongs_to :group`, `has_many :items (destroy)` · unicidade app-level `title` × `help_group_id` · sem índices | desconhecido — muito pequena | idem (herda de `ActiveRecord::Base`). |
| DB-590 | `help_items` / `HelpItem` | `M/20180410132354:3-10` | `id`, `title` string, `help_category_id` int, `description` text, `user_id` int, timestamps NOT NULL | `belongs_to :category, :user`, `has_one :group, through: :category` · unicidade app-level `title` × `help_category_id` · sem índices | desconhecido — pequena | idem. Os arquivos `db/seed_assets/*_help_inputs.yml` **não** alimentam estas tabelas (são help de campo de formulário, ver OPS-545). |

### Infra de domínio / código morto

| ID | Tabela / model | Fonte | Colunas / tipos | Relações & índices | Volume aprox. | Notas de migração |
| -- | -------------- | ----- | --------------- | ------------------ | ------------- | ----------------- |
| DB-591 | `trackings` / `Tracking` | `M/20180724162731:3-18` | `id`, `user_id` int, `target_id` int, `trackable_type` string + `trackable_id` int (**polimórfico**), `resume` string, **`type` string (STI)**, `target_group_id` int, `target_group_type` string, `trackable_parent_id` int + `trackable_parent_type` string (**polimórfico**), `kind` string, timestamps NOT NULL | `belongs_to :user, :target` (ambos User), `:trackable` polimórfico, `:trackable_parent` polimórfico · **sem índices** ⚠️ | desconhecido — **grande e crescente** (log de auditoria de todas as ações) | ⚠️ `type` é coluna STI (sem `inheritance_column = nil`) mas **nenhuma subclasse existe** e `lib/tracking_facade.rb` nunca a preenche → sempre NULL. Sem índice em `trackable_*` apesar de a query do controller filtrar exatamente por eles (`app/controllers/api/v1/trackings_controller.rb:21-23`) — full scan. `resume` limitado a 300 chars só em app. Valores de `trackable_type`: `"Project"`, `"ProjectAvailabilityTemplate"` (`lib/tracking_facade.rb`). |
| DB-592 | `geolocations` / `Geolocation` | `M/20160302002809:3-38` | `id`, `geolocatable_id` int + `geolocatable_type` string (**polimórfico**), `lat`/`lng` decimal(10,6), `city`/`state`/`cep`/`neighborhood`/`country`/`address`/`complement`/`full_address`/`distance_unity` string, `street_number` int, `auto_loading` int d0, `distance` float, `ref_lat`/`ref_lng` decimal(10,6), timestamps | `belongs_to :geolocatable` polimórfico · **índice em `[geolocatable_type, geolocatable_id]`** | desconhecido — **provavelmente vazia** | ⚠️ **CÓDIGO MORTO**: `grep` por `Geolocation`/`geolocatable` fora de `app/models/geolocation.rb` retorna **zero** ocorrências em `app/`, `lib/` e `engines/`. Nenhum model declara `has_one/has_many :geolocation`. Não migrar sem confirmar contagem no banco. |
| DB-593 | `pictures` / `Picture` | `M/20160124203946:3-13` | `id`, `imageable_id` int + `imageable_type` string (**polimórfico**), **Paperclip:** `image_file_name`, `image_content_type`, `image_file_size` int, `image_updated_at` datetime, `description` text, `width` int d0, `height` int d0, `last_calc_at` timestamp, timestamps | `belongs_to :imageable` polimórfico com **`counter_cache: :pictures_count`** · **índice em `[imageable_type, imageable_id]`** | desconhecido — **provavelmente vazia** | ⚠️ **CÓDIGO MORTO**: nenhum `has_many :pictures` no repositório. Pior: o `counter_cache: :pictures_count` (`picture.rb:2`) aponta para uma coluna **que não existe em nenhuma tabela** → qualquer `Picture.create` explodiria. Confirma que a tabela nunca foi usada. Não migrar. |

### Engines auxiliares

| ID | Tabela / model | Fonte | Colunas / tipos | Relações & índices | Volume aprox. | Notas de migração |
| -- | -------------- | ----- | --------------- | ------------------ | ------------- | ----------------- |
| DB-594 | `livetat_feedback_messages` / `Livetat::Feedback19::Message` | `E/feedback19/20160826200511:3-16` · `20170413135718:3-7` · `20170413143721:3-4` · `20170505145152:3` · `20170505222143:3` · `20170506000127:3` · `20181005020002:3-4` | `id`, `formal` string, `email` string, `message` string, `user_id` int, `is_read` int d0, `is_favorite` int d0, `read_at` timestamp, timestamps, `hadouken_label`/`hadouken_value`/`shoryuken_label`/`shoryuken_value` string, `uses_hadouken_field`/`uses_shoryuken_field` int, `state_id` int, `context_id` int, `is_intern` int, `public_token`/`private_token` string | `belongs_to :state, :context, :user` · `has_many :notes (destroy)` · **sem índices** | desconhecido — pequena | Coluna `tag` foi **removida** e substituída por `hadouken_*`/`shoryuken_*` (`E/feedback19/20170413135718`). ⚠️ Nomes `hadouken`/`shoryuken` são placeholders genéricos da engine — no Safegold guardam rótulo+valor de dois campos livres configuráveis. `message` é `string` (não `text`) com limite de 500 só em app. `public_token`/`private_token` são os **únicos tokens públicos** do sistema (o mais próximo de um "public uid"), **sem índice nem unicidade**. |
| DB-595 | `livetat_feedback_states` + `livetat_feedback_contexts` + `livetat_feedback_observers` + `livetat_feedback_observer_contexts` + `livetat_feedback_notes` **(5 tabelas auxiliares da engine feedback19 agrupadas)** | `E/feedback19/20170505143940:3-8` (states) · `20170505214502:3-8` (contexts) · `20170505211325:3-12` (observers) · `20170505225555:3-8` (observer_contexts) · `20170516185759:3-13` + `20181005020904:3` (notes) | **states:** `id`, `name` string, `code` int, timestamps · **contexts:** `id`, `name` string, `code` int, timestamps NOT NULL · **observers:** `id`, `user_id` int, `last_updated_user_id` int, `email` string, `title` string, `is_intern` int, `is_extern` int, timestamps · **observer_contexts:** `id`, `observer_id` int, `context_id` int, timestamps · **notes:** `id`, `description` text, `user_formal` string, `user_email` string, `user_id` int, `top_parent_quote_id` int, `quoted_note_id` int, `feedback_id` int, timestamps NOT NULL, `unread` int d1 | `State/Context has_many :messages` · `Context has_many :observer_contexts (destroy)`, `:observers through` · `Observer has_many :observer_contexts (destroy)`, `:contexts through`, `belongs_to :user` · `Note belongs_to :feedback, :quoted, :top_parent` + `has_many :quotes` · `name` único em states e contexts (app-level) · `email` único em observers (app-level) · **nenhum índice no banco** | desconhecido — todas pequenas | `states` e `contexts` são **tabelas de domínio com seed obrigatório** (`engines/feedback19/db/seeds.rb:2-18` e `:32-45`): 8 estados PT-BR (Não lido…Rejeitado) e 4 contextos (Outros, Problema, Contato, Sugestão), ambos com `code` inteiro estável. `notes.user_formal`/`user_email` são **denormalizados** do usuário. |
| DB-596 | `livetat_mailer_contacts` / `Livetat::Mailer19::Contact` | `E/mailer19/20160409121840:3-13` · `20170519223014:3` · `20170519223026:3` | `id`, `sender` string, `target` string, `target_name` string, `subject` string, **`type` string (STI)**, timestamps NOT NULL, `message` **text** | model sem associações (`contact.rb`) · sem índices | desconhecido — cresce com cada e-mail enviado | `message` foi `string` e virou `text` (remove+add, `E/mailer19/20170519223014`+`20170519223026`) — **os dados anteriores foram perdidos nessa troca**. `type` é coluna STI nunca preenchida (`grind_mailer_decorator.rb:9-24` não define `type`) → sempre NULL. Log de e-mails; avaliar se migra histórico ou só recomeça. |
| DB-597 | `delayed_jobs` / `Delayed::Job` (gem `delayed_job_active_record` + `progress_job`) | `E/mailer19/20170505110720:4-17` · `20170505114146:3-7` | `id`, `priority` int NOT NULL d0, `attempts` int NOT NULL d0, `handler` **text NOT NULL (YAML)**, `last_error` text, `run_at`/`locked_at`/`failed_at` datetime, `locked_by` string, `queue` string, timestamps (nullable), `progress_stage` string, `progress_current` int d0, `progress_max` int d0 | referenciada por `projects.job_id` e `availability_templates.job_id` (`belongs_to :job, class_name: Delayed::Job.name`) · **índice `delayed_jobs_priority` em `[priority, run_at]`** | desconhecido — transitória, mas `projects.job_id`/`availability_templates.job_id` guardam referências **permanentes** | ⚠️ `handler` é **YAML serializado de objetos Ruby** — inmigrável entre stacks. As colunas `progress_*` são da gem `progress_job` e o produto **exibe progresso ao usuário** a partir delas (`project.rb:313-388`). Se o ai9 usar Solid Queue / Sidekiq, esse contrato de progresso precisa ser reimplementado, e `projects.job_id`/`availability_templates.job_id` viram FKs órfãs. Migration é idempotente (`table_exists?`). |
| DB-598 | `active_storage_blobs` + `active_storage_attachments` + `action_text_rich_texts` **(3 tabelas de framework agrupadas)** | `M/20190310025434:4-25` · `M/20190425020855:4-13` | **blobs:** `id`, `key` string NOT NULL, `filename` string NOT NULL, `content_type` string, `metadata` text, `byte_size` bigint NOT NULL, `checksum` string NOT NULL, `created_at` NOT NULL · **attachments:** `id`, `name` string NOT NULL, `record_type`/`record_id` NOT NULL (polimórfico), `blob_id` NOT NULL, `created_at` NOT NULL · **rich_texts:** `id`, `name` string NOT NULL, `body` text, `record_type`/`record_id` NOT NULL (polimórfico), timestamps | **blobs:** índice único em `key` · **attachments:** índice único `index_active_storage_attachments_uniqueness` em `[record_type, record_id, name, blob_id]`, índice em `blob_id`, **e a ÚNICA FK real do banco**: `blob_id → active_storage_blobs.id` · **rich_texts:** índice único `index_action_text_rich_texts_uniqueness` em `[record_type, record_id, name]` | desconhecido — **provavelmente vazias** | ⚠️ O produto usa **Paperclip (`kt-paperclip 7.0`), não Active Storage**, para todos os anexos (avatar de usuário/projeto, logos de cedente/fornecedor/tema, anexo de renegociação). Nenhum model declara `has_one_attached`/`has_rich_text`. Estas 3 tabelas são resíduo de instalação do framework. `active_storage_variant_records` **não existe** (migration é da versão 5.2). O ai9 já tem as três — não recriar. |
| DB-599 | `schema_migrations` + `ar_internal_metadata` **(infra Rails, não vêm de migration)** | geradas pelo Rails; a lista de versões vive implicitamente nos 139 arquivos de `db/migrate` e `engines/*/db/migrate` | **schema_migrations:** `version` string PK · **ar_internal_metadata:** `key` string PK, `value` string, timestamps | — | 139 linhas em `schema_migrations` (se todas as engine migrations foram instaladas na app) | ⚠️ **As migrations das engines não têm cópia em `db/migrate`** — elas são carregadas via `Engine.paths["db/migrate"]` do Rails. Isso significa que o histórico de versões no banco de produção depende da ordem em que as engines foram montadas. Para o Phase 3 isso é irrelevante (o ai9 terá schema próprio), mas é o que impede reconstruir o schema com `rails db:migrate` fora do legado. |

---

## Operacional (OPS) — seeds e scripts de dados

| ID | Item | Fonte | Gatilho | Comportamento | Dependência externa |
| -- | ---- | ----- | ------- | ------------- | ------------------- |
| OPS-540 | Seed principal da app | `db/seeds.rb:1-358` | `rails db:seed` (manual) | Arquivo controlado por **21 flags booleanas hardcoded** nas linhas 1-21. Estado atual no repositório: **ativas** → `should_seed_app_theme_in_existing_entities` (:5), `should_seed_risk_operation_type` (:18), `should_seed_risk_movement_type` (:19), `should_seed_structured_operation_type` (:20), `should_update_abilities` (:21). **Desligadas** → engine seed, user seed, contract seed, app themes, segments, wallets, receivable_kinds, resource_sources, resource_kinds, carriers, movement_kinds, legacy ETL, availabilities de teste, company/risk de teste, sandbox. ⚠️ **Não é idempotente**: os blocos ativos fazem `create` sem `find_or_create` → rodar 2× duplica tipos de operação/movimento. | `AppTheme.default_theme` precisa existir antes de qualquer seed de usuário (comentário `db/seeds.rb:22-23`) |
| OPS-541 | Seed da engine auth19 (papéis + habilidades) | `engines/auth19/db/seeds.rb:1-180` | `Livetat::Auth::Engine.load_seed` (só se `should_perform_engine_seed`, hoje `false`) | Cria os `RoleType` genéricos da engine (`OG` hierarchy 1111, `Admin` 999, `Manager` 888, `Visitor`) e suas 16 `Ability` por tipo. Em seguida `db/seeds.rb:34-94` **destrói** `Admin`/`Manager`/`Visitor` e recria os papéis do produto Safegold (`U.ADMIN`, `U.MANAGER`, `U.COLAB` com hierarchy 998/888/799). | — |
| OPS-542 | Seed da engine feedback19 (estados + contextos) | `engines/feedback19/db/seeds.rb:1-67` | `Livetat::Feedback19::Engine.load_seed` (idem, hoje `false`) | Cria 8 `State` (`code` 1..8) e 4 `Context` (`code` 1..4), depois **faz backfill** dos feedbacks antigos com `state_id`/`context_id`/`is_intern` nulos. **Dado de produção obrigatório** se a feature de feedback for migrada. ⚠️ Não idempotente (`create` puro). | — |
| OPS-543 | `AppThemeFactory` (tema global padrão) | `db/factories/app_theme_factory.rb:1-30`; autoload via `config/application.rb:31` | `AppThemeFactory.instance.execute` a partir de `db/seeds.rb:25` | Cria **um** `GlobalTheme` (`title: "Tema padrão"`, `is_default: 1`, style Light, fonte "Baloo Thambi 2") e anexa 3 logos via Paperclip lendo `SFG::Theme.LOGO__FULL/TEXT/SYMBOL`. **Dado de produção obrigatório no dia 1** — sem tema padrão nenhum usuário passa na validação (`user.rb`). ⚠️ `theme.user_id` fica NULL de propósito (comentário `:11`). | Arquivos de imagem apontados por `app/definitions/SFG/theme.rb` |
| OPS-544 | Textos de contrato (TOU / Política de Privacidade) | `db/seed_assets/contracts/privacy.html`, `tou.html`, `user.html`; consumidos em `db/seeds.rb:112-158` | `should_perform_contract_seed` (hoje `false`) **e** `Contract.count == 0` | Cria 1 `Contract` por tipo lendo o HTML via `FileToStringDecoder.parse_and_fix_new_lines` (`lib/file_to_string_decoder.rb`), depois gera `ContractDeal` para todo usuário que ainda não aceitou. `user.html` **não é referenciado por nenhum seed** — órfão. | `lib/file_to_string_decoder.rb` |
| OPS-545 | Help de campo dos formulários | `db/seed_assets/receivables_help_inputs.yml`, `risk_operations_help_inputs.yml`, `structured_operations_help_inputs.yml` | lidos em runtime pela UI (não por `db:seed`) | Mapas `coluna → texto de ajuda`. ⚠️ **Todo o conteúdo é placeholder** — as ~60 chaves do arquivo de recebíveis têm literalmente o texto `"Só um teste de informações do campo pra descrever para que serve cada campo"`. Não são dados de produção; são um contrato de UI vazio. **Não migrar o conteúdo**, migrar só o mecanismo se a UI depender dele. | — |
| OPS-546 | Dump do banco pré-Rails (`sfg_legacy_full.sql`) | `db/seed_assets/sfg_legacy_full.sql` (**9,0 MB**, commitado no repo) | manual (`psql < arquivo`), para popular o banco `SG20210329` antes de rodar `Legacy::execute` | Dump completo do sistema **Django/Python** anterior ao Rails (tabelas `authentication_user`, `dprojeto`, `dbanco`, `fbordero`, `dtarifa`, `dcarteira`, `dsegmento`, `dtiporecebivel`, `durecliq`, `fbancoproj`, `fbortarifa`, `authentication_user_projetos`). É a **fonte original** dos dados históricos hoje em produção. | PostgreSQL |
| OPS-547 | ETL `Legacy::execute` (migração Django → Rails, 2021) | `app/models/legacy.rb:1-112` + 17 arquivos em `app/models/legacy/`; acionado por `db/seeds.rb:258-260` (`should_migrate_legacy_database`, hoje `false`) | manual, **uma única vez** em 2021 | Migra 12 entidades **em ordem fixa** (`legacy.rb:2-15`: Carrier → Segment → ReceivableKind → Wallet → ResourceSource → MovementKind → U → Project → Membership → ProjectToCarrierConnection → ReceivableEntry → ReceivableTax), cada uma via um `Adapter.adapt` que faz `create` no model novo gravando `legacy_id`. Depois roda 4 **interceptors** de correção (`legacy.rb:17-22`): projeto padrão do usuário, responsável do projeto, membership do responsável, recálculo de todos os recebíveis. Ver seção dedicada abaixo. | Conexão `sfg_legacy` (OPS-548) |
| OPS-548 | Conexão secundária `sfg_legacy` | `config/database.linux.yml:10-16`, `database.centos.yml:9-15`, `database.osx.yml:9-15`, `database.win.yml:19-25`, `database.arch.yml:1-7`; usada por `establish_connection :sfg_legacy` em cada `app/models/legacy/*.rb` | carregada sempre que uma classe `Legacy::*` é autoloadada | Segundo banco PostgreSQL (`database: SG20210329`) apontando para o dump Django. ⚠️ **Presente em todos os 5 arquivos de database.yml**, inclusive o de produção — se o banco não existir, qualquer referência a `Legacy::*` levanta erro de conexão. | PostgreSQL `SG20210329` |
| OPS-549 | Ausência de `schema.rb` versionado | `.gitignore:15` (`/db/schema.rb`); nenhum `structure.sql` | — | O esquema **não é reproduzível a partir do repositório sozinho** de forma verificável: só `rails db:migrate` sobre as 139 migrations (incluindo as das 4 engines que criam tabela) reconstrói o banco. Como várias migrations foram escritas contra MySQL (`limit: 16777214`, `socket: /tmp/mysql.sock`) e outras usam `Migration[4.2]`, a reconstrução em PG 16 / Rails 8 **não é garantida**. Antes do Phase 3, o `data-engineer` deve extrair um `pg_dump --schema-only` do banco real e conferir contra esta reconstrução. | acesso ao banco de produção |

---

## `app/models/legacy.rb` e `app/models/legacy/` — o que é

**Não é um pacote de dados do Safegold. É um ETL de mão única, já executado, que trouxe o
sistema *anterior* (Django/Python) para dentro deste Rails em 2021.**

Estrutura (`app/models/legacy/`, 17 arquivos):

- **11 "models espelho"** — cada um é um `ActiveRecord::Base` que faz
  `establish_connection :sfg_legacy` + `self.table_name = "<tabela django>"`, apontando
  para o banco **`SG20210329`** (outro banco, não o do Safegold):

  | Classe Ruby | Tabela Django | Vira |
  | ----------- | ------------- | ---- |
  | `Legacy::Carrier` (`carrier.rb:4`) | `dbanco` | `carriers` |
  | `Legacy::Segment` (`segment.rb:4`) | `dsegmento` | `segments` |
  | `Legacy::ReceivableKind` (`receivable_kind.rb:4`) | `dtiporecebivel` | `receivable_kinds` |
  | `Legacy::Wallet` (`wallet.rb:4`) | `dcarteira` | `wallets` |
  | `Legacy::ResourceSource` (`resource_source.rb:4`) | `durecliq` | `resource_sources` |
  | `Legacy::MovementKind` (`movement_kind.rb:4`) | `dtarifa` | `movement_kinds` |
  | `Legacy::U` (`u.rb:4`) | `authentication_user` | `livetat_auth_users` |
  | `Legacy::Project` (`project.rb:4`) | `dprojeto` | `projects` |
  | `Legacy::Membership` (`membership.rb:4`) | `authentication_user_projetos` | `memberships` |
  | `Legacy::ProjectToCarrierConnection` (`project_to_carrier_connection.rb:4`) | `fbancoproj` | `project_to_carrier_connections` |
  | `Legacy::ReceivableEntry` (`receivable_entry.rb:4`) | `fbordero` | `receivable_entries` |
  | `Legacy::ReceivableTax` (`receivable_tax.rb:4`) | `fbortarifa` | `receivable_taxes` |

  Cada um carrega uma classe interna `Adapter` com `self.adapt(i)` que faz o
  `create` no model novo (ex.: `carrier.rb:11-28`), gravando `legacy_id` como
  ponte entre os dois mundos.

- **4 interceptors** (`interceptor.rb`, `default_project_interceptor.rb`,
  `project_responsible_interceptor.rb`, `membership_interceptor.rb`,
  `receivable_entry_calculate_interceptor.rb`) — passes de correção rodados **depois**
  de tudo, para resolver dependências circulares (projeto padrão do usuário,
  responsável do projeto) e recalcular todos os recebíveis (`re.save` em loop).

- **O orquestrador** `Legacy` (`app/models/legacy.rb:40-48`) roda as 12 tabelas em ordem
  e depois os 4 interceptors. `Legacy::find` / `find_by_old` (`legacy.rb:63-87`) são
  utilitários de tradução id-antigo ↔ id-novo via `legacy_id`.

**Sujeira que ficou no código de produção por causa dele:**
`legacy_id` (12 tabelas, com índice único), `legacy_password` (hash Django em
`livetat_auth_users`), `legacy_project_id`/`legacy_user_id` em `memberships`,
`legacy_project_id`/`legacy_carrier_id` em `project_to_carrier_connections`, o
`user_id: 1` hardcoded ("forçado mestre dos magos") em 6 adapters, e um e-mail
hardcoded (`morello@safegold.com.br`, `legacy/project.rb:24`).

**Precisa migrar?** **Não** — nem o código nem a conexão `sfg_legacy`, nem o dump
`sfg_legacy_full.sql`. É um script de uso único já consumido.
**MAS:** as colunas `legacy_*` **precisam ser preservadas na migração de dados**, porque
são a única prova de proveniência dos registros históricos (borderôs de 2016–2021).
Recomendação para o Phase 3: manter `legacy_id` como coluna de rastreio (ou consolidar
num campo `external_ref` junto com o novo `sfg_id`), e **descartar** `legacy_password`
depois de confirmar que nenhum usuário ainda depende dele para login.
⚠️ **Dúvida para o Phase 2:** `legacy_password` guarda o hash Django em claro na coluna —
confirmar com o Vinícius se pode ser dropado (é dado sensível parado no banco).

---

## Padrões herdados a reconciliar no ai9

### `public_uid` — **não existe**
A gem `public_uid ~> 2.1` está declarada nos três Gemfiles (`Gemfile.linux:28`,
`Gemfile.osx`, `Gemfile.prod`) mas **nenhuma linha de código a usa**: `grep -rn
"public_uid\|generate_public_uid"` em `app/`, `engines/`, `lib/` e `db/` retorna zero
ocorrências, e nenhuma migration cria coluna `uid`/`public_uid`. **Nenhuma tabela tem
identificador público.** A gem é dependência morta.

Os únicos identificadores não-sequenciais do sistema são:
- `livetat_feedback_messages.public_token` / `private_token` (`E/feedback19/20181005020002`) — sem índice, sem unicidade;
- `renegotiation_installments.batch_token` — token de lote com checagem de colisão em app (`renegotiation_installment.rb:96-100`), sem unique index;
- `livetat_auth_users.authentication_token` — token Devise, esse **sim** com índice único;
- `projects.smart_id` / `integration_key`, e `integration_key` em 10 tabelas de domínio — slugs textuais, sem unicidade no banco.

**Consequência para o ai9:** hoje **todas as URLs e payloads da API expõem IDs sequenciais**
(`app/controllers/api/v1/*`). Se o ai9 adotar UUID (34 das suas 96 tabelas já usam),
isso é uma melhoria, não uma paridade — registrar em `improvements-log.md`, não como perda.
`livetat_auth_omni_providers.uid` é o UID do provedor OAuth, **sem relação** com isso.

### Paperclip — 24 colunas em 6 tabelas
O legado usa `kt-paperclip 7.0` (`Gemfile.linux:38`), **não** Active Storage. Cada
`has_attached_file` gera 4 colunas (`*_file_name` string, `*_content_type` string,
`*_file_size` integer, `*_updated_at` datetime):

| Tabela | Anexo(s) | Origem |
| ------ | -------- | ------ |
| `livetat_auth_users` | `avatar` | `E/auth19/20160409121831:3-5` |
| `projects` | `avatar` | `M/20210301170412:11` |
| `carriers` | `logo` | `M/20210301192131:8` |
| `providers` | `logo` | `M/20210325141909:9` |
| `renegotiation_attachments` | `file` | `M/20210503195535:7` |
| `app_themes` | `symbol_logo`, `full_logo`, `text_logo`, `login_bkg_image` (**4×**) | `M/20200205130201:16-19` |
| `pictures` (morta) | `image` | `M/20160124203946:5` |

Total: **7 anexos × 4 = 28 colunas** (24 vivas + 4 na tabela morta `pictures`).
Todos gravam em disco local: `:rails_root/public/system/:attachment/:id/:basename_:style.:extension`
(ex.: `app_theme.rb:7-8`, `user.rb:5-6`), com variantes geradas por ImageMagick
(`thumb`/`preview`/`medium`/`large`/`retina`). **`public/system/*` está no `.gitignore:5`** →
os binários não estão no repositório; a migração de arquivos é um passo separado da
migração de linhas.

**Reconciliação:** o ai9 já tem `active_storage_blobs`/`attachments`/`variant_records`
(`backend/db/schema.rb`). Portar cada `has_attached_file` para `has_one_attached` e
escrever um passo de ETL de binários (ler `public/system/...`, `attach`) — é trabalho
de Phase 3, não de Phase 1. **Não migrar as 24 colunas `*_file_name` para o ai9.**

### Soft delete — **não existe**
`grep` por `deleted_at`, `acts_as_paranoid`, `paranoia` retorna **zero** em `app/`,
`engines/`, `lib/` e `db/`. Nenhuma tabela tem `deleted_at`. O legado usa em vez disso:
- **flags de ativação inteiras**: `is_active` (int, default 1) em 15 tabelas
  (`carriers`, `projects`, `segments`, `sub_segments`, `wallets`, `receivable_kinds`,
  `resource_kinds`, `resource_sources`, `movement_kinds`, `providers`,
  `availability_templates`, `risk_controls`, `indicators`, `risk_operation_types`,
  `risk_operation_subtypes`, `risk_movement_types`, `structured_operation_types`,
  `project_guarantee_types`, `memberships`, `livetat_auth_users`);
- **`dependent: :restrict_with_error`** em quase toda associação de domínio — o produto
  simplesmente **impede** apagar o que tem dependente. As exceções (`destroy` /
  `delete_all`) são as que realmente removem em cascata e precisam de atenção no ETL:
  `Project#memberships (delete_all)`, `Project#providers (destroy)`,
  `Project#availability_templates (destroy)`, `Carrier#risk_controls (destroy)`,
  `Indicator#entries (delete_all)`, `ReceivableEntry#taxes (destroy)`,
  `ReceivableEntry#risk_operation (destroy)`, `RiskOperation#movements (destroy)`,
  `Renegotiation#attachments (destroy)`, `AvailabilityTemplate#child_templates (destroy)`,
  `HelpGroup#categories (destroy)`, `HelpCategory#items (destroy)`,
  `User#role/#info (destroy)`, `Role/RoleType#abilities (delete_all)`,
  `Feedback::Message#notes (destroy)`, `Context/Observer#observer_contexts (destroy)`.

### Enums — **nenhum `enum` do Rails; tudo string PT-BR ou inteiro 0/1**
Zero ocorrências de `enum ` nos models. Dois padrões, ambos problemáticos:

1. **Booleanos como `integer` 0/1** — `is_active`, `is_default`, `is_mandatory`,
   `is_global`, `is_cumulative`, `is_locked`, `is_adjusted`, `is_upper_level`,
   `is_operation`, `is_title`, `is_advalorem`, `is_desagio`, `is_iof`, `is_liquidation`,
   `is_conta_corrente`, `is_unique`, `is_pre`, `is_paid`, `is_sandbox`, `is_ended`,
   `is_on_variable`, `is_transfer`, `is_system_exclusive`, `is_intern`, `is_extern`,
   `is_read`, `is_favorite`, `is_phone_checked`, `has_safegold_management`, `has_bi`,
   `has_pre_faturamento`, `allow_manual_operations`, `allow_receivable_entries`,
   `should_insert_on_existing_projects`, `is_default_member`, `unread`, `auto_loading`.
   **Exceção única:** `livetat_auth_users.deactivated` é `boolean` de verdade
   (`M/20220523124957:3`) — inconsistência dentro da própria tabela de usuários.
   Os scopes fazem SQL literal (`where('is_active = 1')`, ex. `risk_control.rb:10`),
   o que quebra se a coluna virar boolean sem reescrever os scopes.

2. **Enums como string em português (com acento), definidos em `@@CONSTANTE`**, não no banco:

   | Coluna | Valores | Fonte |
   | ------ | ------- | ----- |
   | `memberships.role` | Responsável, Participante, Coordenador, Gestor | `membership.rb:18-21` |
   | `renegotiations.state` | Liquidado, Pago, Inconsistente, Sem parcela cadastrada | `renegotiation.rb:41-44` |
   | `renegotiations.kind` | Financeiro, Operacional, **Tributario** (sem acento), Trabalhista | `renegotiation.rb:46-49` |
   | `charges.state` | Edição, Disponível, Faturado | `charge.rb:14-16` |
   | `receivable_entries.status` | Diferença, OK | `entry.rb:11-12` |
   | `movement_kinds.kind` | Crédito, Débito | `movement_kind.rb:27-28` |
   | `contracts.kind` | Termos de Uso, **Politicas de Privacidade** (sem acento) | `contract.rb:13-14` |
   | `carriers.financial_agent` | FIDC, Securitizadora, Factoring, Cliente | `carrier.rb:46-49` |
   | `providers` (doc) | CPF, CNPJ | `provider.rb:50-51` |
   | `receipts.kind` | LIQ, EST | `receipt.rb:17-18` |
   | `indicators.value_type` / `indicator_entries.value_type` | Dinheiro | `indicator.rb:26`, `indicator_entry.rb:19` |
   | `app_themes.style` / `login_bkg_style` / `font_name` | Dark/Light · Color/Image/Default · Helvetica/Arial/Tahoma/Baloo Thambi 2/Lato | `app_theme.rb:75-86` |
   | `livetat_auth_user_infos.confiability_level` | Baixa (default no banco) | `E/auth19/20171204213707:3` |
   | **Siglas de 1–2 letras** | `availability_templates.operation_type` = C/D/S/M · `deadline_type` = CP/LP · `risk_movement_types.credit_type` = C/D | `availability_template.rb:37-46`, `risk_movement_type.rb:32-33` |

   ⚠️ **Duas grafias já divergem do "correto"** (`Tributario`, `Politicas`) e estão
   gravadas assim em produção — qualquer normalização no ETL precisa mapear a grafia
   real, não a esperada. E como os valores são **texto de UI**, mudar o rótulo na tela
   do ai9 sem tabela de tradução corrompe o filtro dos dados históricos.

3. **Colunas `type` (STI) — 5 tabelas, 3 comportamentos diferentes:**
   - STI real e usado: `app_themes.type` (`GlobalTheme`/`UserTheme`),
     `availability_templates.type` (`GlobalAvailabilityTemplate`/`ProjectAvailabilityTemplate`);
   - `type` **desabilitado** como STI: `livetat_auth_abilities` (`inheritance_column = nil`,
     valores `conditional`/`limit`), `receivable_entries` e `availability_entries`
     (`inheritance_column = :_type_disabled` — nem têm coluna `type`, herdam do abstrato `Entry`);
   - `type` existente, **STI ativo, mas nunca preenchido** (sempre NULL, nenhuma subclasse):
     `trackings.type`, `livetat_mailer_contacts.type` — bomba armada.

### Moeda — decimal(15,2) para valores, **float para taxas** (perigoso)
- **Valores em R$**: `decimal(15, 2)` em **todas** as ~70 colunas monetárias
  (`valor_bruto`, `main_value`, `operation_value`, `balance`, `limite`, `value`, …).
  Máximo representável: 9.999.999.999.999,99 — folgado. **Não há centavos-em-inteiro
  em lugar nenhum.** Boa notícia para o ETL: mapeia direto para `decimal(15,2)` no ai9.
- **Taxas, percentuais e prazos**: **`float`** (dupla precisão IEEE) —
  `agreed_rate`, `taxa`, `taxa_*`, `operation_interest_rate`, `interest_rate_correction`,
  `paid_percent`, `recompra_percent`, `retencao_percent`, `fomento_percent`,
  `outros_percent`, `subordinated_accounts_percent`, `prz_med_pond_emp/bco`,
  `float_calculado`/`float_acordado`/`diferenca_float`, `checagem_iof`,
  todos os `custo_efetivo_*` e `taxa_desconto_nominal_*` (14 colunas em
  `receivable_entries`), `remunerations.value`, `receipts.fee`.
  ⚠️ **`remunerations.value` e `receipts.fee` são floats que multiplicam valores
  decimais para produzir dinheiro** (`receipts.value` decimal). Isso significa que o
  valor faturado do Safegold hoje passa por aritmética de ponto flutuante. Ver DR-04.
- **Sem coluna de moeda/câmbio** em nenhum lugar — tudo é BRL implícito.
- Formatação PT-BR (`R$ 1.234,56`) é feita na view; o `gem 'extensobr'` converte valor
  por extenso (uso em relatório PDF).

### Timezone — `:local` + `Brasilia` (não UTC)
`config/application.rb:28-29`:
```ruby
config.active_record.default_timezone = :local
config.time_zone = 'Brasilia'
```
**Todos os `created_at`/`updated_at`/`datetime` do banco estão em horário de Brasília,
gravados como `timestamp without time zone`.** O Rails 8 usa `:utc` por padrão. Ao ler
esses dados no ai9 sem conversão explícita, todo timestamp desloca 3 horas (e a janela
de horário de verão 2016–2019 desloca 2 horas, não 3). Ver DR-02 — é o risco #1.
Colunas `date` (`date`, `due_date`, `issue_date`, `renegotiation_date`, `data_credito`,
`closing_date`, `abertura`, `data_situacao`, `original_due_date`, `new_due_date`,
`first_due_date`, `last_due_date`) **não** são afetadas.

### Auditoria — parcial e inconsistente
- `created_at`/`updated_at`: presentes em **todas** as 67 tabelas (`t.timestamps`).
  Em 8 delas com `null: false` explícito; nas demais, nullable.
  `active_storage_blobs` e `active_storage_attachments` têm **só `created_at`**.
- **Não existe `created_by`/`updated_by` padronizado.** O que existe é `user_id` como
  "quem criou", em 24 tabelas (`projects`, `carriers`, `wallets`, `segments`,
  `receivable_entries`, `availability_entries`, `risk_operations`, `risk_movements`,
  `receipts`, `charges`, …), **sem nenhum campo de "quem alterou por último"** —
  exceto `livetat_feedback_observers.last_updated_user_id` (único do repositório).
- A trilha de auditoria real é a tabela `trackings` (DB-591), preenchida manualmente por
  `lib/tracking_facade.rb` só para `Project` e `ProjectAvailabilityTemplate`. **Nenhuma
  das tabelas financeiras (recebíveis, renegociações, risco, cobrança) é auditada.**
  Isso é um gap de produto, não só de dado — anotar em `improvements-log.md`.
- Devise dá auditoria de login em `livetat_auth_users` (`sign_in_count`,
  `current_sign_in_at/ip`, `last_sign_in_at/ip`, `failed_attempts`, `locked_at`).

---

## Riscos de migração de dados

Priorizados por impacto financeiro/irreversibilidade.

**DR-01 — Salto de PK: `integer` sequencial → `uuid`.**
Evidência: nenhuma migration do legado usa `id: :uuid`; o ai9 usa
`id: :uuid, default: gen_random_uuid()` em 34 das 96 tabelas
(`backend/db/schema.rb:19` e adiante), incluindo `users` e `projects`.
Impacto se ignorado: sem uma **tabela de correspondência id-antigo→uuid-novo mantida
durante todo o ETL**, as ~40 FKs implícitas (que não têm constraint no banco para
detectar o erro) ligam registros errados silenciosamente — um borderô de um projeto vai
parar em outro. Além disso, as colunas `legacy_id` já ocupam o papel de "id de outra
era" (do Django), então o ai9 vai precisar de **duas** colunas de proveniência
(`legacy_id` do Django + `sfg_id` do Rails 6) ou de um `external_refs` jsonb.
Mitigação obrigatória antes de qualquer carga.

**DR-02 — Timestamps em horário de Brasília, não em UTC.**
Evidência: `config/application.rb:28` (`default_timezone = :local`) e `:29`
(`time_zone = 'Brasilia'`); colunas criadas com `t.timestamps` = `timestamp without time zone`.
Impacto se ignorado: **todo** `created_at`/`updated_at` do sistema desloca ao ser lido
por um Rails 8 padrão (`:utc`). Pior: o Brasil teve horário de verão até 2019, então o
offset correto **não é constante** (−02:00 no verão até 2019, −03:00 no resto). Uma
conversão com offset fixo corrompe 3 anos de histórico. Relatórios por data de
criação e a ordenação de `risk_movements` (que dependem de `date` + `order`) ficam errados.

**DR-03 — `projects.responsible_id` é `string`, não `integer`.**
Evidência: `db/migrate/20210301170412_create_projects.rb:25` (`t.string :responsible_id`)
usado como FK em `app/models/project.rb:3`
(`belongs_to :responsible, foreign_key: :responsible_id, class_name: "Livetat::Auth::User"`).
Impacto se ignorado: o PG faz cast implícito na comparação, então em produção "funciona";
mas o ETL vai encontrar `"12"`, `12`, `""`, `NULL` e possivelmente lixo na mesma coluna.
Se o alvo for `uuid NOT NULL`, a carga quebra ou (pior, se o `NOT NULL` não existir)
zera o responsável de parte dos projetos. **Auditar `SELECT DISTINCT responsible_id`
antes de migrar.**

**DR-04 — Dinheiro calculado com `float`.**
Evidência: `remunerations.value` é `t.float` (`M/20220629123512:6`) e `receipts.fee` é
`t.float` (`M/20220802225011:11`), ambos multiplicando `operation_value`
(`decimal(15,2)`) para produzir `receipts.value` (`decimal(15,2)`). Idem os ~30 floats de
taxa em `receivable_entries` (`M/20210315183541:19-24,27,29,32,34,36,49-61`) e
`risk_controls.taxa*` (`M/20210510211438:7,9,11,13`; `M/20220611152145:6`).
Impacto se ignorado: se o ai9 recalcular esses valores com `BigDecimal` (correto), os
totais **não vão bater** com os do legado na verificação de paridade do Phase 4, e o
time vai perseguir um "bug" que é na verdade a correção do erro antigo. Decidir
explicitamente no Phase 2: **replicar o float (paridade byte a byte) ou corrigir e
documentar a divergência**. Não descobrir isso no Phase 4.

**DR-05 — `providers` guarda JSON e YAML em colunas `text`, com dois mecanismos diferentes.**
Evidência: `providers.cnaes` usa `serialize :cnaes` (**YAML**, `app/models/provider.rb:2`)
e `providers.atividades` usa `JSON.generate`/`JSON.parse` escrito à mão
(`app/models/provider.rb:97-110`); ambas criadas em `M/20210504151249:17-18` como
`t.text ..., limit: 16777214`.
Impacto se ignorado: (a) o Rails 7.1+ **exige coder explícito** em `serialize` — o
`serialize :cnaes` como está **não roda** no Rails 8, então a coluna vira ilegível;
(b) YAML desserializado sem allowlist é vetor de RCE; (c) duas colunas irmãs, dois
formatos — um ETL genérico vai tratar as duas igual e corromper uma.
Migrar ambas para `jsonb` com conversão explícita.

**DR-06 — Configuração de produção contraditória (PostgreSQL vs MySQL).**
Evidência: `config/database.centos.yml:1-7` define `production:` com `adapter: postgresql`;
`config/database.linux.yml:18-26` define `production:` com `adapter: mysql2`,
`encoding: utf8` e `socket: /tmp/mysql.sock`. Migrations carregam resíduo MySQL
(`limit: 16777214` em `M/20210504151249:17-18`, típico de `MEDIUMTEXT`).
Impacto se ignorado: o `data-engineer` pode extrair o dump do banco errado, ou assumir
semântica MySQL (`utf8` de 3 bytes trunca emoji e alguns caracteres) onde a produção é PG.
**Confirmar com o Vinícius qual arquivo reflete a produção real antes do dump.**
⚠️ Ambos os arquivos com `production:` também contêm **senhas em texto puro** commitadas
(`database.linux.yml:8,25`) — reportar, não replicar no ai9.

**DR-07 — Associação `MovementKind#receivables` aponta para coluna inexistente.**
Evidência: `app/models/movement_kind.rb:2`
(`has_many :receivables, foreign_key: :movement_kind_id, class_name: "ReceivableEntry"`),
mas `receivable_entries` não tem `movement_kind_id` em nenhuma das suas migrations
(`M/20210315183541`, `M/20210402111120`, `M/20210403171744`, `M/20210511211918`,
`M/20220322123523`, `M/20220330140334`, `M/20220610122917`) — a coluna só existe em
`receivable_taxes` (`M/20210323134328:5`).
Impacto se ignorado: qualquer chamada a `movement_kind.receivables` levanta
`PG::UndefinedColumn`. Se o Phase 3 portar o grafo de associações "como está", carrega o
bug. **Corrigir para `has_many :receivables, through: :receivable_taxes`** ou remover.

**DR-08 — `contracts.description` é gravada por seed mas não existe no schema.**
Evidência: `db/seeds.rb:124` faz `Contract.create(..., description: ...)`, mas
`db/migrate/20180405163859_create_contracts.rb:3-10` cria apenas
`title`, `creator_id`, `version`, `kind`.
Impacto se ignorado: ou existe uma coluna criada fora de migration no banco de produção
(e a reconstrução deste documento está incompleta), ou o seed de contrato **nunca rodou
com sucesso** e os textos de TOU/Privacidade não estão no banco. As duas hipóteses são
ruins de formas diferentes. **Verificar no banco real** — é a evidência mais forte de
que faltam migrations não versionadas.

**DR-09 — Counter caches sem default → `NULL` em vez de `0`.**
Evidência: `carrier_groups.carriers_count` (`M/20210819193736:7`, sem `default: 0`) com
`counter_cache: :carriers_count` em `app/models/carrier_group.rb:2`;
`renegotiations.attachments_count` (`M/20210503202015:3`, sem default) com
`counter_cache: :attachments_count` em `app/models/renegotiation_attachment.rb:2`.
Impacto se ignorado: linhas criadas antes da adição do contador têm `NULL`;
`NULL + 1 = NULL` no PG, então o contador **nunca se recupera** e a UI mostra vazio.
Rodar `reset_counters` no ETL e criar as colunas com `default: 0, null: false` no ai9.
⚠️ Relacionado: `Picture` declara `counter_cache: :pictures_count` para uma coluna que
**não existe em tabela nenhuma** (`app/models/picture.rb:2`) — prova de que `pictures` é morta.

**DR-10 — Tabelas de domínio sem seed: o ai9 sobe quebrado no dia 1.**
Evidência: têm seed (obrigatório) → `wallets`, `receivable_kinds`, `resource_kinds`,
`resource_sources`, `movement_kinds`, `segments` (`db/seeds.rb:160-223`, hoje atrás de
flags `false` porque o dado já está em produção), `risk_operation_types`,
`risk_movement_types`, `structured_operation_types` (`db/seeds.rb:315-339`, flags `true`),
`livetat_feedback_states`/`contexts` (`engines/feedback19/db/seeds.rb`),
`livetat_auth_role_types` (`engines/auth19/db/seeds.rb` + `db/seeds.rb:34-94`),
`app_themes` (`db/factories/app_theme_factory.rb`).
**Não têm seed nenhum** → `sub_segments`, `risk_operation_subtypes`,
`project_guarantee_types`, `help_groups`/`categories`/`items`, `indicators`.
Impacto se ignorado: se o Phase 3 migrar só as tabelas transacionais e esquecer as de
domínio, o ai9 sobe sem tipo de operação, sem carteira, sem tipo de tarifa — e nada pode
ser cadastrado. E as que não têm seed **só existem via migração de dados**: se o ETL não
as trouxer, a feature de garantias/subtipos fica inutilizável mesmo com o código pronto.

**DR-11 — Denormalização em toda parte: rótulos copiados que já divergem.**
Evidência: `receivable_taxes.title` + `is_advalorem`/`is_desagio`/`is_iof` (cópia de
`movement_kinds`, `M/20210323134328:7-10`); `risk_entries.risk_control_title`
(`M/20210603125803:4`); `renegotiations.provider_name` (`M/20210324173930:4`);
`receipts.kind`/`title`/`operation_title` (`M/20220802225011:9-10`, `M/20220804195335:4`);
`indicator_entries.title`/`key`/`value_type` (`M/20211027140815:4,11`, `M/20211027150857:3`);
`projects.responsible_formal`/`responsible_email` (`M/20210301170412:23-24`);
`livetat_feedback_notes.user_formal`/`user_email` (`E/feedback19/20170516185759:5-6`).
Impacto se ignorado: essas cópias **não são atualizadas** quando a origem muda (nenhum
callback de sincronização existe). Um ETL que reconstrua o rótulo a partir da origem
"conserta" dados históricos e **muda o que o usuário vê num relatório de 2021**. Decidir
por tabela: preservar a cópia (fidelidade histórica) ou normalizar (consistência).
Para documentos financeiros emitidos (`receipts`), a cópia é provavelmente correta —
é o valor no momento da emissão.

**DR-12 — Nenhuma unicidade composta existe no banco; só em app.**
Evidência: 20+ `validates_uniqueness_of ... scope:` nos models
(`availability_entry.rb:12`, `risk_entry.rb:4`, `indicator_entry.rb:6`,
`renegotiation_installment.rb:15`, `membership.rb:31`, `receipt.rb:14`,
`remuneration.rb:11`, `provider.rb:42-43`, `company.rb:10`, `risk_control.rb:4`,
`project_to_carrier_connection.rb:8`, `project_indicator_connection.rb:8`,
`contract_deal.rb:9`, `contract.rb:9`, `risk_operation_subtype.rb:11-12`, …) e
**zero** `add_index ..., unique: true` correspondente nas migrations (os únicos uniques
são `legacy_id`, os 5 tokens do Devise, `[name,uid,user_id]` do omni, e os 2 do
Active Storage/Action Text).
Impacto se ignorado: o banco de produção **provavelmente já tem duplicatas** (validação
de unicidade em Rails tem corrida conhecida, e jobs em background gravam em paralelo —
`lib/insert_global_template_on_projects_job.rb` etc.). Ao criar os índices únicos
corretos no ai9, a carga **falha no meio**. Rodar detecção de duplicatas por cada escopo
acima **antes** do Phase 3 e decidir a regra de desempate.

**DR-13 — Renomeações de coluna que mudaram semântica sem migrar os dados.**
Evidência: `M/20220429122226:4` (`renegotiations.total_value` → `installments_main_value`),
`M/20220429122346:3` (`renegotiation_installments.value` → `main_value`),
`M/20220429122419:3` (`renegotiation_payments.value` → `installment_paid_value_with_interest_cm`),
`M/20220325145251:3-5` (`risk_entries.{comissaria,fomento,intercompany}_value` → `*_total_value`).
Impacto se ignorado: o nome novo promete "valor com juros e correção monetária", mas as
linhas anteriores a abril/2022 contêm o valor **antigo** (só principal). Nenhuma
migration de dados acompanhou a renomeação. Um ETL que confie no nome vai somar maçãs
com laranjas em relatórios que cruzam períodos. Marcar o corte por `created_at` e
tratar as duas eras.

**DR-14 — Anexos Paperclip vivem no disco e não estão versionados.**
Evidência: `has_attached_file` com
`path: ":rails_root/public/system/:attachment/:id/:basename_:style.:extension"`
(ex.: `app/models/app_theme.rb:7`, `engines/auth19/app/models/livetat/auth/user.rb:5`);
`.gitignore:5` ignora `public/system/*`.
Impacto se ignorado: migrar as 24 colunas `*_file_name` sem migrar os arquivos produz
avatares, logos e anexos de renegociação **quebrados** (nome no banco, byte nenhum no
storage). Os anexos de renegociação são documentos de dívida — perda é grave.
O ETL precisa de acesso ao filesystem do servidor legado, não só ao banco.
⚠️ **Nota:** o caminho usa `:id` — se o ai9 mudar as PKs (DR-01), o mapeamento
arquivo→registro tem que ser feito **antes** da renumeração.

**DR-15 — `risk_controls` carrega dois modelos de dados sobrepostos.**
Evidência: `M/20210510211438:6-13` cria `limite_auto_liquidaveis`/`taxa_auto_liquidaveis`,
`limite_fomento`/`taxa_fomento`, `limite_comissaria`/`taxa_comissaria`,
`limite_intercompany`/`taxa_intercompany` (4 tipos hardcoded); `M/20220611152145:3-6`
adiciona `risk_operation_type_id` + `limite` + `taxa` (modelo genérico) **sem remover as
8 colunas antigas nem migrar os valores**.
Impacto se ignorado: linhas criadas antes de 06/2022 têm limite/taxa **só** nas colunas
antigas; as posteriores, só nas novas. Um ETL que leia `limite`/`taxa` perde todos os
limites de crédito históricos (silenciosamente, como zero). **Determinar a data de corte
e escrever o backfill.**

**DR-16 — Referência bidirecional operação↔recibo, sem constraint.**
Evidência: `risk_operations.receipt_id` e `structured_operations.receipt_id`
(`M/20220802225011:19-20`) **e** `receipts.operation_id`/`operation_type` polimórfico
(`M/20220802225011:7`), com `has_one :receipt, foreign_key: :operation_id` do outro lado
(`risk_operation.rb:12`, `structured_operation.rb:7`) e o scope
`available_for_receipt = where(receipt_id: nil)`.
Impacto se ignorado: os dois lados podem divergir (operação aponta para recibo A,
recibo B aponta para a operação). Nada no banco impede. O scope `available_for_receipt`
usa **só** o lado da operação, então uma divergência faz uma operação já faturada
reaparecer como faturável — **cobrança duplicada**. Auditar a consistência dos dois
lados no ETL e escolher uma direção canônica no ai9.

**DR-17 — Órfãos prováveis por falta de `dependent:` e de FK no banco.**
Evidência: `RiskOperation has_many :extensions` sem `dependent:`
(`app/models/risk_operation.rb:18`); `RiskOperation has_many :renovations` idem (`:17`);
`Remuneration has_many :receipts` sem `dependent:` (`remuneration.rb:4`);
`Project has_many :remunerations` sem `dependent:` (`project.rb:44`);
`RiskMovementType`/`State`/`Context` `has_many :messages` sem `dependent:`.
Somado à **ausência total de FK no banco** (só 1 em todo o schema), a única barreira é o
`restrict_with_error` das associações que o têm — e `delete_all`/`delete` puros o burlam.
Impacto se ignorado: ao criar FKs de verdade no ai9 (correto), a carga aborta em cada
órfão. **Contar órfãos por FK implícita antes do Phase 3** — o levantamento tem que
cobrir as ~40 colunas `*_id` sem constraint listadas nas tabelas acima.

**DR-18 — `risk_movements.balance` e `risk_operations.balance` são saldos acumulados persistidos.**
Evidência: `M/20220608162424:9` (`balance` em movimentos), `M/20220607123547:15`
(`balance` em operações), com a coluna de ordenação chamada **`order`** (`:5`), palavra
reservada em SQL.
Impacto se ignorado: se o ETL inserir movimentos fora da ordem original de `order`/`date`,
ou se um recálculo rodar durante a carga, o saldo de todas as operações de risco fica
errado — e esse saldo é o que define o limite de crédito disponível de cada empresa.
Migrar `balance` **como valor**, nunca recalcular durante a carga, e renomear `order`.

**DR-19 — Sujeira estrutural que não deve atravessar para o ai9.**
Evidência agrupada:
`pictures` e `geolocations` são **tabelas mortas** (zero referências fora dos próprios
models — `app/models/picture.rb`, `app/models/geolocation.rb`);
`active_storage_*` e `action_text_rich_texts` estão criadas mas o produto usa Paperclip
(nenhum `has_one_attached`/`has_rich_text` no repositório);
`receipts.temp_id` é id efêmero de UI persistido (`M/20220802225011:4`);
`app_themes.cached_css` é CSS gerado guardado no banco (`M/20200205130201:21`);
`renegotiation_installments.color` é apresentação no banco (`M/20210324174436:15`);
`projects.job_id`/`job_report`/`job_state` e `availability_templates.job_id`/`job_report`/
`job_state` acoplam o domínio ao `delayed_jobs` (`M/20210301170412:26-28`, `M/20220225133130`);
`livetat_auth_user_infos` (44 colunas de perfil pessoal) e `livetat_feedback_messages.hadouken_*`/`shoryuken_*`
são herança de uma engine genérica sem uso no Safegold;
`livetat_auth_users.legacy_password` guarda hash Django em coluna própria;
`db/seed_assets/sfg_legacy_full.sql` são 9 MB de dump de terceiro sistema commitados.
Impacto se ignorado: o ai9 nasce carregando ~10 tabelas e ~60 colunas que ninguém usa,
e o Phase 4 gasta tempo verificando paridade de features que não existem.
**Recomendação:** cada item acima vira uma decisão explícita no Phase 2 (migrar / dropar),
registrada em `improvements-log.md` — nunca um esquecimento.

---

## Cobertura

### Arquivos lidos (todos relativos a `../sfg`)
- **Migrations (139, todas lidas integralmente):** `db/migrate/*.rb` (104),
  `engines/auth19/db/migrate/*.rb` (14), `engines/auth_omni19/db/migrate/*.rb` (2),
  `engines/feedback19/db/migrate/*.rb` (13), `engines/mailer19/db/migrate/*.rb` (5).
  Verificado que `engines/auth_ux19`, `engines/ux_kit19` e `engines/navkit`
  **não possuem `db/migrate`**.
- **Models da app (52):** `app/models/*.rb` — lidos integralmente `entry.rb`,
  `membership.rb`, `provider.rb`, `legacy.rb`; nos demais foram extraídas todas as
  declarações estruturais (`class`, `belongs_to`, `has_many`, `has_one`,
  `has_attached_file`, `validates*`, `scope`, `serialize`, `self.table_name`,
  `self.inheritance_column`, `@@CONSTANTE`).
- **Models do pacote Legacy (17):** `app/models/legacy.rb` + `app/models/legacy/*.rb` — integrais.
- **Models das engines (15):** `engines/*/app/models/**/*.rb` — declarações estruturais;
  `livetat/auth/user.rb` e `livetat/auth/ability.rb` lidos integralmente nas partes relevantes.
- **Decorators:** `app/decorators/models/user_decorator.rb` (associações que a engine não declara).
- **Config:** `config/application.rb`, `config/database.{linux,centos,osx,win,arch}.yml`, `.gitignore`.
- **Gemfiles:** `Gemfile.linux` (referência), confirmado `public_uid` também em `Gemfile.osx`/`Gemfile.prod`.
- **Seeds e factories:** `db/seeds.rb`, `db/factories/app_theme_factory.rb`,
  `engines/auth19/db/seeds.rb`, `engines/feedback19/db/seeds.rb`
  (`engines/auth_omni19/db/seeds.rb` está **vazio**, 0 linhas).
- **Seed assets:** `db/seed_assets/` (listagem + amostra de `receivables_help_inputs.yml`;
  `sfg_legacy_full.sql` **não foi lido** — 9 MB, identificado por tamanho e por quem o consome).
- **Auxiliares:** `engines/auth19/lib/livetat/auth/ability_factory.rb`,
  `lib/tracking_facade.rb`, `engines/feedback19/app/decorators/grind_mailer_decorator.rb`.
- **Alvo (para reconciliação):** `backend/db/schema.rb` do ai9 (96 tabelas, `ActiveRecord::Schema[8.0]`, version `2026_08_08_070000`).

### Lacunas e dúvidas para o Phase 2
1. **[bloqueante] Não há `schema.rb`/`structure.sql` versionado.** Este documento é uma
   reconstrução das migrations. **É obrigatório rodar um `pg_dump --schema-only` do banco
   de produção e diferenciá-lo contra este inventário antes do Phase 3.** DR-08 é
   evidência concreta de que pode haver coluna no banco sem migration correspondente.
2. **[bloqueante] Volumes.** Nenhuma contagem de linhas foi possível (sem acesso ao banco).
   Todos os "Volume aprox." são `desconhecido` com estimativa qualitativa. Antes do Phase 3,
   levantar `count(*)` de pelo menos: `availability_entries`, `receivable_entries`,
   `receivable_taxes`, `risk_movements`, `renegotiation_installments`, `trackings`,
   `livetat_mailer_contacts` (as candidatas a "grandes"), e confirmar que `pictures` e
   `geolocations` estão vazias.
3. **[bloqueante] Duplicatas e órfãos.** Rodar as consultas de detecção para cada um dos
   20+ escopos de unicidade app-level (DR-12) e para cada FK implícita (DR-17).
   Sem isso não dá para dimensionar o ETL.
4. **Qual `database.yml` é a produção real** (DR-06) — `centos` (PostgreSQL) ou `linux`
   (MySQL)? Pergunta direta para o Vinícius.
5. **`contracts.description` existe no banco?** (DR-08) — decide se o inventário está completo.
6. **`legacy_password` pode ser dropado?** Hash Django em texto no banco; algum usuário
   ainda depende dele para autenticar?
7. **Política de PK do ai9** (DR-01): as tabelas do SFG entram com `uuid` (alinhando com as
   34 tabelas uuid do ai9) ou com `bigint` (alinhando com as outras 62)? Decisão do Phase 2,
   mas define o formato da tabela de correspondência do ETL.
8. **Float vs BigDecimal nos cálculos financeiros** (DR-04): paridade byte a byte com o
   legado, ou corrigir e documentar a divergência? Precisa de decisão do Vinícius antes
   do Phase 4, senão a verificação de paridade acusa falso-positivo em massa.
9. **`livetat_auth_omni_providers` (login social) está ativo em produção?** Se estiver
   vazio, a engine `auth_omni19` inteira sai do escopo.
10. **`structured_operations` vs `risk_operations`**: são quase idênticas (DB-576/DB-581).
    Unificar numa tabela com discriminador no ai9, ou preservar as duas? Impacta o ETL
    de `receipts` (que é polimórfico sobre as duas).
11. **Renomeação de colunas PT-BR → EN** (`vlr_bruto_final`, `qtd_titulos`, `prz_med_pond_emp`,
    `saldo`, `observacoes`, `contrato`, `data_credito`, …): se o ai9 padronizar em inglês,
    o mapa de-para vira artefato de Phase 2, não improviso de Phase 3.
12. **`risk_controls`: data de corte do modelo antigo→novo** (DR-15) — precisa ser
    determinada consultando o banco (`WHERE risk_operation_type_id IS NULL`).
13. **Sobreposição com outras unidades:** os `DB-` criados dentro das faixas de
    `auth-users` (001–049), `receivables` (150–189), `risk` (230–279) etc. devem ser
    cruzados contra este documento no QA de consolidação. **Onde houver divergência de
    coluna/tipo/relação, este arquivo é a referência canônica para o `data-engineer`.**
