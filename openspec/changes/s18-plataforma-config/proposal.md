# Proposal: S18 — Plataforma: configuração, segredos, boot, i18n e pipeline de assets

> Fatia **S18** da ordem de execução de `.migration-ai9/migration-map.md`.
> Bloco de origem: `.migration-ai9/map/data-infra.md` — capability `ops-config` (§2.2), fatia
> interna **S-01** ("Config, segredos e boot"), mais os dois controllers base de `misc-domain`
> (§2.7) e o shim de vendor de §2.8.
> **Não depende de nenhuma outra fatia** e **é dependência de todas** — por isso roda cedo,
> junto de S0.
>
> **Por que esta fatia existe:** a conferência consolidada do fim do Phase 2 encontrou
> **29 IDs de plataforma sem dono**. S13 os apontava para "S1"; S1 conta 179 IDs, **todos do
> bloco `auth-admin`**, e nunca os reivindicou. Duas fatias apontando uma para a outra é
> exatamente o modo de falha que o contrato C4 existe para impedir — e aqui produziu um vão
> de 29 itens.

## Why

Esta é a fatia menos vistosa e a que mais segura o resto de pé. Três razões concretas, todas
medidas na origem:

1. **Segredo commitado em texto puro.** `config/development_credentials.yml:1` versiona um
   `secret_key_base` de 128 hex. Quem tem o repositório **forja sessão** em qualquer ambiente
   que use esse arquivo. E `config/credentials.yml.enc` existe **sem `master.key`**: o
   arquivo cifrado é inútil e ninguém percebe, porque o Rails cai no caminho não cifrado.
2. **Verificação de certificado TLS desligada.** `config/initializers/ssl_for_win.rb`
   desabilita `VERIFY_PEER` no Windows — e a **própria base ai9** repete o defeito em
   `backend/config/environments/production.rb:83` e `development.rb:58`
   (`openssl_verify_mode: 'none'`, achado **C-05**). O legado tinha desculpa de plataforma;
   a base não tem nenhuma.
3. **Configuração multiplicada por plataforma de desenvolvimento.** Quatro
   `config/application.{arch,centos,osx,win}.yml`, cinco `config/database.{...}.yml`, **três
   Gemfiles** (com `Gemfile` no `.gitignore`) e o `yarn.lock` fora do versionamento. Não é
   estética: é a razão pela qual não existe um ambiente de referência reproduzível — e
   DEC-11 depende de existir um, porque é dele que saem os valores golden do contrato **C2**.

E há um quarto, que é o mais fácil de subestimar: **o `type_casting.rb` do legado é o
initializer com mais regra de negócio do sistema inteiro** (`OPS-619`). Coerção booleana e de
moeda em nível de linguagem — `String#to_bool`, conversão de "1.234,56" — reabertas em
classes do Ruby. Migrar isso para o ai9 como monkey patch reintroduziria, na base, a classe
de bug "por que este `"false"` virou `true` aqui e não ali". Vira helper explícito, e o
comportamento numérico é preservado **com teste**, porque ele decide centavo.

## What Changes

**29 IDs.** A tabela item-a-item está em `.migration-ai9/map/data-infra.md` §2.2, §2.7 e
§2.8 — aqui a estratégia e o alvo, sem duplicar as colunas do mapa.

### A. Boot e ambiente — 7 IDs

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| OPS-600 | reuse | `SFG::Application` e os defaults do Rails 6.0 do legado não vêm; a base ai9 já é Rails 8 com `application.rb` próprio |
| OPS-601 | reuse | Locale, fuso e formatação de data globais — `pt-BR`, `America/Sao_Paulo`, em **um** lugar |
| OPS-602 | reuse | Autoload paths customizados e recarga manual de decorators/libs **somem**: Zeitwerk resolve |
| OPS-615 | reuse | `development.rb` — o do ai9 já é melhor; nada é portado |
| OPS-616 | adapt | `production.rb` — inclui `storage.yml` com serviço que **sobrevive a redeploy** (Q-07 nomeia o provedor; o default é registrado, não escolhido aqui) |
| OPS-617 | adapt | `test.rb` — o legado tem ambiente de teste e **nenhum teste** (D-114). Aqui o ambiente existe para os testes de caracterização financeira do contrato **C2** |
| OPS-625 | reuse | `new_framework_defaults_6_0.rb` não é portado |

### B. Segredos e configuração — 7 IDs

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| OPS-609 | reuse | `CredentialsByEnvironment` (credenciais em dois níveis) some; ENV + `dotenv-rails` é o mecanismo do ai9 |
| OPS-610 | reuse | ⚠ `secret_key_base` commitado — no ai9 vem de ENV, e o versionado é `.env.example`. Registrado como **defeito do legado**, não como funcionalidade a portar |
| OPS-611 | build | `credentials.yml.enc` sem `master.key` vira o oposto: **initializer que falha o boot** quando falta segredo obrigatório. O contrato desta fatia |
| OPS-612 | reuse | As 4 variantes de `application.*.yml` somem; `paperclip_path` é **descartada** (zero leituras confirmadas) |
| OPS-613 | adapt | As 5 variantes de `database.*.yml` viram uma; bancos `sfg9_dev` / `sfg9_test` |
| OPS-614 | reuse | Um `Gemfile` + `Gemfile.lock` versionados. **Médio para a paridade**: DEC-11 fixa Ruby 2.6.1 / Rails 6.0.3.2 como ambiente de **referência do legado** para extrair valores golden |
| OPS-627 | reuse | `filter_parameter_logging` incompleto — acrescentar `cpf`, `cnpj`, `cpf_cnpj` à máscara |

### C. Initializers com regra — 6 IDs

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| OPS-618 | build | `date_overload.rb` — as sentinelas de data do domínio viram `Sfg::DateBounds` explícito, não monkey patch de `Date` |
| OPS-619 | build | `type_casting.rb` — **o initializer com mais regra de negócio do legado**. Coerção booleana e de moeda vira helper explícito, back e front, **com teste de valor** |
| OPS-620 | adapt | `dev.rb` — a abstração de dialeto SQL e DNS morre; `ILIKE`/`unaccent` nativos do PostgreSQL (DEC-05) |
| OPS-626 | adapt | ⚠ `ssl_for_win.rb` — verificação TLS volta a ser **ativa por padrão**, com escape por ENV. Corrige também **C-05**, que é da própria base ai9 |
| OPS-628 | build | Os initializers neutros do legado não vêm; entra o de **CSP + headers de segurança**, que não existe em lado nenhum |
| OPS-605 | adapt | Login social do Facebook — permanece **desligado**, agora como flag booleana em ENV em vez de configuração morta |

### D. i18n — 1 ID

`OPS-629` (adapt): o legado tem `config/locales/` com 6 arquivos e 2 idiomas, e a **UI é 100%
hardcoded** — os catálogos nunca foram usados. Aqui nasce **um** catálogo `pt-BR` de verdade,
que é também onde o `gender_prefix` e o `pluralize_for` do legado vão parar (helpers de S19).

### E. Runtime e processos — 2 IDs

`OPS-631` (adapt — ⚠ `puma.rb` com `RAILS_ENV` **hardcoded como development**, o que em
produção significa código recarregável, log verboso e `secret_key_base` de desenvolvimento;
aqui vem de ENV, com `workers` configurável) e `OPS-632` (adapt — `Procfile` de produção,
`config.ru`, `Rakefile` e `bin/`, incluindo os alvos `lib/tasks/sfg_etl.rake` e
`lib/tasks/demo.rake` que S14 e o seed de demo consomem).

### F. Pipeline de assets — 4 IDs

`OPS-637`, `OPS-638`, `OPS-639` e `OPS-746` — todos `reuse`. Webpacker 5, os loaders, a
estratégia de chunks e os shims de vendor (`dragula_wrapper.js`, `lvt-dialog.js`,
`lvt-doughnut.js`, `rails-action-text`) **não são portados**: o ai9 é Vite + pnpm. O que
esta fatia entrega é a **evidência registrada** de que cada um foi lido e tem equivalente —
em especial `lvt-doughnut.js`, que é a prova de que o legado **carregava** uma biblioteca de
gráfico e **nenhuma view a instanciava** (achado nº 1 do `migration-map.md`, base do DEC-10).

### G. Base dos endpoints — 2 IDs

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| BE-458 | adapt | `PubApplicationController` — os filtros globais de toda a área logada (layout `preloaded`, contexto de usuário, gate de sessão) viram os *before* do Grape/`controller_helpers` do ai9, **um** lugar |
| BE-459 | adapt | Controllers base de API: `ApiApplicationController` exigia token de aplicação cliente e `ApiPrivateApplicationController` a sessão. No ai9 é a base Grape de `api/v1/base.rb` + `api/auth/v1/base.rb`, com `client_applications`, cuja tabela é de S1 |

## Mudanças visíveis, decididas e registradas

Para `improvements-log.md`, todas intencionais:

1. **O boot falha** quando falta segredo obrigatório, em vez de subir com default silencioso.
2. **Verificação de certificado TLS ativa por padrão** — inclusive corrigindo a base ai9
   (`C-05`). Escape por ENV para quem tem SMTP com certificado interno.
3. **`cpf`/`cnpj` deixam de aparecer no log.**
4. **CSP e headers de segurança passam a existir** — não existiam nem no legado nem na base.
5. **Um ambiente reproduzível**: um Gemfile, um `database.yml`, um `.env.example`.

## Descartes com evidência

| ID | Motivo registrado |
| -- | ----------------- |
| OPS-612 (parcial) | `paperclip_path` — **zero leituras** confirmadas no legado; a chave some junto com as 4 variantes de plataforma |
| OPS-637, OPS-638, OPS-639, OPS-746 | Webpacker 5 e seus shims não são portados: o ai9 é Vite. `lvt-doughnut.js` fica registrado como a prova do achado nº 1 (biblioteca de gráfico carregada, **nenhuma** view a instancia) |
| OPS-600, OPS-602, OPS-625 | Defaults e autoload do Rails 6.0: substituídos por Rails 8 + Zeitwerk, não descartados por omissão |

**Nenhum destes sai do ledger como `dropped` sem a linha de prova.** `dropped` por omissão é
indistinguível de esquecimento.

## Fronteiras — dono único de cada ID (contrato C4)

- **Os initializers de integração não estão aqui.** `OPS-621` (Geocoder) e `OPS-622`
  (ReceitaWS) são de **S13**, que constrói os serviços que os usam. `OPS-624`
  (`delayed_job_config.rb`) e `OPS-633` (`bin/delayed_job`) também são de **S13**, dona da
  fila. S18 fornece o mecanismo de ENV que os três consomem.
- **A configuração de e-mail não está aqui.** `OPS-607` (SMTP) e `OPS-608` (DKIM) são de
  **S13**. `OPS-626` fica aqui porque é o initializer que **desliga TLS globalmente**, não só
  para SMTP; a linha específica do SMTP é tarefa de S13 (**Q-01**, adiada por decisão do
  usuário).
- **A configuração do engine de autenticação (`OPS-604`) é de S1.**
- **A marca não está aqui.** `OPS-603` (definições de marca) e `OPS-606` (UI de autenticação)
  são de **S17**; `OPS-635` (favicon, OG, `robots.txt`) é da fatia de marca; `OPS-634`
  (páginas 404/422/500) é de **S2**, dona dos estados de erro do console.
- **Os helpers de formatação são de S19.** `OPS-619` entrega o **mecanismo** de coerção;
  `FE-431` (`format_money`) e companhia são as chamadas, e vivem em S19.
- **O catálogo `pt-BR` nasce aqui** (`OPS-629`) e é **preenchido** por S19 (`FE-432`
  `gender_prefix`, `FE-438` `pluralize_for`) e pelas fatias de feature.

## Dependências

- **Nenhuma.** É a fatia mais a montante do grafo, junto de S0.
- **Ordem recomendada:** roda **antes** de S13 (que consome ENV para fila, SMTP e
  integrações) e antes de qualquer fatia que grave migration, para que `sfg9_dev`/`sfg9_test`
  já existam.

## Perguntas em aberto (defaults declarados em `map/data-infra.md` §6)

| # | Pergunta | Default |
| - | -------- | ------- |
| **Q-01** | Trocar `openssl_verify_mode: 'none'` por `ENV.fetch('SMTP_OPENSSL_VERIFY_MODE','peer')`? | Troco. **Adiado por decisão do usuário** — a linha de SMTP é de S13; o initializer global (`OPS-626`) segue aqui |
| **Q-07** | Qual serviço de storage em produção? | Não escolho provedor. `Disk` serve para a demo, **não** para o cutover (F-13) |
| **Q-20** | O CSP nasce em `report-only` ou bloqueando? | **`report-only` primeiro**, com prazo escrito para virar bloqueio. CSP bloqueando numa base que nunca teve um quebra tela em silêncio |

## Capabilities

### New Capabilities

- `platform-config`: o contrato de configuração da aplicação — de onde vem cada valor, o que
  acontece quando falta, e o que nunca entra no repositório. **Uma** requirement genuinamente
  nova: **boot fail-fast por segredo ausente**, que não existe no legado (que sobe com
  `secret_key_base` commitado) nem na base ai9.

### Modified Capabilities

Nenhuma. Os requirements de paridade dos 29 IDs já existem em `openspec/specs/` e são
**referenciados por ID**, não recriados.

## Impact

- **Backend:** `config/environments/{development,production,test}.rb`, `config/puma.rb`,
  `config/database.yml`, `config/storage.yml`, `config/locales/pt-BR.yml`,
  `config/initializers/{required_env,content_security_policy,filter_parameter_logging}.rb`,
  `app/lib/sfg/date_bounds.rb`, `app/lib/sfg/coercion.rb`, `api/v1/base.rb`,
  `api/auth/v1/base.rb`, `Procfile`, `lib/tasks/`.
- **Repositório:** `.env.example` (o único versionado), `.gitignore`.
- **Frontend:** nada além do par de coerção de moeda usado por S19 — esta fatia **não** toca
  em `frontend/` fora disso.
- **Paridade:** 29 IDs de inventário que **não tinham dono** passam a ter.
