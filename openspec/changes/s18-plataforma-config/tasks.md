# Tasks: S18 — Plataforma: configuração, segredos, boot, i18n e assets

Ordenada por dependência (contrato de config → segredos → segurança → coerção → i18n →
runtime → bases de endpoint → provas de descarte → paridade). Uma tarefa = **um comportamento
verificável**.

**Portões que valem para a fatia inteira:**
- **Nenhum segredo entra no repositório.** O único arquivo de configuração versionado é
  `*.example`. Toda tarefa que cria configuração cria também a linha correspondente no
  `.env.example`.
- **Princípio 6b.** Esta fatia constrói **sobre** o mecanismo de env do ai9
  (`dotenv-rails`, `bin/switch_env`), não o substitui. O único arquivo compartilhado tocado é
  o de TLS (`OPS-626`), e é uma linha.
- **`dropped` só com prova.** Todo ID `reuse` que não gera código gera **linha de evidência**
  no ledger: arquivo, contagem ou grep.
- Esta fatia **não** toca em `frontend/` além do par de coerção de moeda da tarefa 5.3.

## 1. Ambiente reproduzível

- [x] 1.1 `config/database.yml` único, com bancos `sfg9_dev` e `sfg9_test` por ENV.
  Verificável: `bin/rails db:version` roda em ambos sem arquivo por plataforma. **Fecha:
  OPS-613.**
- [x] 1.2 Confirmar que o repositório tem **um** `Gemfile` + `Gemfile.lock` versionados e
  nenhum lock ignorado. Verificável: `git check-ignore Gemfile Gemfile.lock pnpm-lock.yaml`
  não retorna nada. **Fecha: OPS-614.**
- [x] 1.3 Registrar no runbook que **Ruby 2.6.1 / Rails 6.0.3.2** é o ambiente de
  **referência do legado** (DEC-11) do qual saem os valores golden do contrato C2 — e que ele
  **não** é reproduzido no repositório ai9. **Fecha: OPS-614 (parte).**
- [x] 1.4 Conferir que nada de `development.rb` / `new_framework_defaults_6_0.rb` /
  autoload paths do legado foi portado, e registrar a substituição (Rails 8 + Zeitwerk).
  **Fecha: OPS-600, OPS-602, OPS-615, OPS-625.**
- [x] 1.5 `production.rb`: `storage.yml` com serviço que **sobrevive a redeploy**. Se Q-07
  não estiver respondida, o serviço fica **parametrizado** e o runbook o marca como
  **bloqueado por dependência externa** — nunca como concluído. **Fecha: OPS-616.**
- [x] 1.6 `test.rb`: ambiente de teste que existe para os testes de caracterização
  financeira (C2). Verificável: a suíte roda sem nenhuma variável de integração externa
  definida. **Fecha: OPS-617.**

## 2. Segredos e o contrato de boot

- [x] 2.1 `.env.example` completo e versionado, cobrindo os três ambientes, **sem nenhum
  valor real**. Verificável: varredura de segredo (`brakeman` / `bundler-audit`, já no
  Gemfile de dev) passa. **Fecha: OPS-609, OPS-610, OPS-612.**
- [x] 2.2 Initializer de variáveis obrigatórias: **o boot falha** se faltar qualquer uma, e a
  mensagem nomeia **todas** as ausentes de uma vez, não a primeira. A lista é **por
  ambiente**. **Fecha: OPS-611.**
- [x] 2.3 Teste do fail-fast: remover uma obrigatória e verificar que o processo **não sobe**
  — e que a mensagem cita o nome da variável.
- [x] 2.4 Registrar `config/development_credentials.yml:1` (`secret_key_base` de 128 hex
  commitado) no ledger como **defeito do legado corrigido**, com a citação de arquivo e
  linha. Não é funcionalidade portada. **Fecha: OPS-610 (parte).**
- [x] 2.5 Registrar que `paperclip_path` foi **descartada** com a evidência de **zero
  leituras** no legado. **Fecha: OPS-612 (parte).**

## 3. Segurança de plataforma

- [x] 3.1 `ENV.fetch('SMTP_OPENSSL_VERIFY_MODE', 'peer')` — verificação de certificado
  **ativa por padrão**, escape explícito por ENV. Elimina o `ssl_for_win.rb` do legado **e**
  corrige `production.rb:83` / `development.rb:58` da própria base (**C-05**). Uma linha por
  arquivo; nada mais é refatorado. **Fecha: OPS-626.**
- [x] 3.2 Registrar 3.1 em `improvements-log.md` como mudança **intencional** de
  comportamento — quem tiver SMTP com certificado interno precisa da ENV.
- [x] 3.3 `filter_parameter_logging` acrescido de `cpf`, `cnpj`, `cpf_cnpj`. Verificável: um
  request com CPF no corpo não deixa o número no log. **Fecha: OPS-627.**
- [x] 3.4 Initializer de **CSP + headers de segurança**, ~~em `report-only`~~ **BLOQUEANTE**.
  ⚠ **O DEC-48 veio depois deste `tasks.md` e inverteu a tarefa**: o usuário recusou
  conscientemente o modo permissivo. Feito bloqueante, e o que a decisão exige em troca
  foi cumprido: a política é montada a partir do que a aplicação **realmente carrega**
  (`frontend/csp.config.ts` — Google Fonts, `data:`/`blob:`, WebSocket do Action Cable,
  host da API), o domínio do Google Analytics **não** é liberado (DEC-87), e houve
  varredura de console. O backend `api_only` tem política própria
  (`config/initializers/security_headers.rb`: `default-src 'none'`, com exceção escrita
  para `/docs`, que carrega Stoplight do unpkg).
  **Verificado executando**: 10 rotas × light/dark, **0 violações** de
  `securitypolicyviolation`; Work Sans carregada de `fonts.gstatic.com`; WebSocket do
  Action Cable **aberto**; `curl -D -` mostra CSP, `nosniff`, `DENY`, `Referrer-Policy` e
  `Permissions-Policy` na resposta. **Fecha: OPS-628.**
- [x] 3.5 ~~Abrir no runbook a tarefa datada de virar o CSP para modo bloqueante~~ —
  **Q-20 foi respondida pelo DEC-48: já nasceu bloqueante, não há prazo a agendar.**
  O que entrou no runbook (`.migration-ai9/platform-runbook.md` §1) é a obrigação
  permanente que isso cria: **toda vez que uma tela passar a carregar recurso externo
  novo, a varredura de console tem de rodar de novo, em light e dark** — `tsc` limpo e
  `rspec` verde não pegam recurso bloqueado por CSP.
- [x] 3.6 Login social permanece **desligado**, agora por flag booleana em ENV. Verificável:
  a flag existe, o default é `false`, e nenhum caminho de código de OAuth de Facebook é
  alcançável. **Fecha: OPS-605.** (O descarte do mecanismo legado é `OPS-489`, de S13.)

## 4. Banco de dados e SQL

- [x] 4.1 Remover qualquer dependência de abstração de dialeto: busca insensível usa `ILIKE`
  e `unaccent` nativos do PostgreSQL (DEC-05). Verificável: `grep` por `Dev.ilike` ou
  equivalente retorna zero. **Fecha: OPS-620.**

## 5. Coerção e sentinelas (o initializer com regra de negócio)

- [x] 5.1 `Sfg::DateBounds` — sentinelas de data do domínio como constantes nomeadas, **sem**
  monkey patch de `Date`. Verificável: `grep` por reabertura de `Date`/`Time` retorna zero.
  **Fecha: OPS-618.**
- [x] 5.2 `Sfg::Coercion` — coerção booleana e de moeda explícita, **sem** reabrir `String`
  nem `Numeric`. **Fecha: OPS-619 (parte).**
- [x] 5.3 Teste golden de coerção de moeda alimentado com valores extraídos do legado
  (`"1.234,56"`, negativos, zero, vazio, nulo), exercitado **nos dois lados** — Ruby e o
  utilitário TS que o frontend usa. Verificável: os dois leem o **mesmo** conjunto de casos.
  **Fecha: OPS-619.**
- [x] 5.4 Registrar em `improvements-log.md` que a coerção deixou de ser monkey patch — e o
  que isso muda para quem lia `"false".to_bool` no legado.

## 6. i18n

- [x] 6.1 `config/locales/pt-BR.yml` — **um** catálogo, realmente lido. Verificável: uma
  string de erro do servidor vem do catálogo, não de literal. **Fecha: OPS-629.**
- [x] 6.2 Portão: texto novo **não entra hardcoded**. Entregue como **item de revisão
  escrito** (a opção que a própria tarefa admite), no cabeçalho de
  `config/locales/pt-BR.yml` e em `.migration-ai9/platform-runbook.md` §3.
  **Honestidade sobre o alcance:** não há verificação de CI — o backend hoje tem **zero**
  chamadas a `I18n.t` fora do catálogo do Grape, então um linter de literal apontaria o
  app inteiro e seria desligado na primeira semana. O que existe é o caminho real
  funcionando (as validações do Grape saem do catálogo) e a regra escrita; o linter faz
  sentido quando houver texto de servidor suficiente para ele ter alvo.
- [x] 6.3 Registrar que os 6 arquivos e 2 idiomas do legado **não** são portados, com a
  evidência de que a UI legada é 100% hardcoded — o catálogo lá era adorno.

## 7. Runtime e processos

- [x] 7.1 `config/puma.rb` com `RAILS_ENV` vindo de ENV (o legado o fixa em `development`, o
  que em produção significa código recarregável, log verboso e segredo de desenvolvimento) e
  `workers` configurável. **Fecha: OPS-631.**
- [x] 7.2 `Procfile` de produção, `config.ru`, `Rakefile` e `bin/` conferidos; criar os
  alvos `lib/tasks/sfg_etl.rake` e `lib/tasks/demo.rake` **vazios e nomeados**, que S14 e o
  seed de demo preenchem. Verificável: `bin/rails -T` lista os dois namespaces. **Fecha:
  OPS-632.**
- [x] 7.3 Locale, fuso (`America/Sao_Paulo`) e formatação de data globais definidos em **um**
  lugar. Verificável: uma data renderizada no servidor e uma no cliente concordam. **Fecha:
  OPS-601.**

## 8. Base dos endpoints

- [x] 8.1 Os filtros globais da área logada do legado (layout `preloaded`, contexto de
  usuário, gate de sessão) ficam em **um** lugar — os *before* de `api/v1/base.rb` /
  `controller_helpers.rb`. Verificável: nenhum endpoint repete o gate. **Fecha: BE-458.**
- [x] 8.2 Bases de API: sessão exigida na base privada; o token de aplicação cliente do
  legado corresponde a `client_applications` (DB-543, de S1). Verificável: um endpoint
  privado sem sessão responde 401 pela base, não por checagem local. **Fecha: BE-459.**

## 9. Pipeline de assets — provas, não código

- [x] 9.1 Registrar no ledger, com evidência, que Webpacker 5, `config/webpack/`,
  `babel.config.js` / `postcss.config.js` e os shims de vendor **não** são portados (o ai9 é
  Vite + pnpm). **Fecha: OPS-637, OPS-638, OPS-639, OPS-746.**
- [x] 9.2 Registrar especificamente `lvt-doughnut.js` como a **prova** de que o legado
  carregava uma biblioteca de gráfico que **nenhuma view instancia** — evidência do achado nº
  1 do `migration-map.md`, base do DEC-10 e da decisão de que gráfico é feature nova
  (`NEW-001`, S15). Sem esta linha, o QA do Phase 4 procura gráficos no legado. **Fecha:
  OPS-746 (parte).**

## 10. Paridade e fechamento

- [x] 10.1 Conferir os **29 IDs** desta fatia contra `.migration-ai9/parity-ledger.md`: todos
  em `implemented`, `dropped` **com a prova na linha**, ou `blocked` com a pergunta nomeada
  (Q-07, Q-20). **Nenhum `dropped` por omissão.**
- [x] 10.2 Registrar em `improvements-log.md` as **5 mudanças visíveis** do `proposal.md` — em
  especial o boot fail-fast e o TLS, que mudam o comportamento de quem já roda o ambiente.
- [x] 10.3 Conferir que os initializers apontados para outras fatias **não** foram
  implementados aqui: `OPS-621`, `OPS-622`, `OPS-624`, `OPS-633`, `OPS-607`, `OPS-608` (S13);
  `OPS-604` (S1); `OPS-603`, `OPS-606` (S17); `OPS-634` (S2).

## 11. Bloco pós-decisões (as 111 DEC vieram depois deste `tasks.md`; onde divergir, vale a DEC)

### 11.A Agendamento de jobs versionado (`upstream-flags.md` #13, DEC-60, DEC-90)

O achado: `grep -rI "Sidekiq::Cron\|sidekiq_cron\|cleanup_login_codes"` em `backend/` dava
**zero**, e mesmo assim havia 10 crons registrados, todos `source: dynamic`, persistidos só
em chaves `cron_job:*` do Redis.

- [x] 11.1 `config/schedule.yml` **versionado**, carregado no startup do servidor Sidekiq via
  `Sidekiq::Cron::Job.load_from_hash!(schedule, source: "schedule")`, que também **remove** o
  que não está declarado. `config/initializers/sidekiq_cron.rb` aponta o caminho **absoluto**
  do arquivo (o default do gem é relativo ao CWD do processo — Sidekiq iniciado de fora de
  `backend/` não carregaria cron nenhum, sem erro).
  Verificado **executando**: `bundle exec sidekiq` → `Cron Jobs - added job with name
  purge_login_attempts…` e os 3 crons em `cron_job:default:*` com `source: schedule`.
- [x] 11.2 `cleanup_login_codes` **declarado no mesmo arquivo**, na mesma tarefa. Sem isso a
  correção mataria o único cron legítimo que existe hoje, porque o `load_from_hash!` remove o
  não-declarado. Verificado: a chave do Redis passou de `source: dynamic` para
  `source: schedule`, mantendo `CleanupLoginCodesJob` e `0 * * * *`.
- [x] 11.3 `PurgeLoginAttemptsJob` — **DEC-60**, retenção de 90 dias, em lote, com a retenção
  parametrizada por `LOGIN_ATTEMPTS_RETENTION_DAYS`. Verificado **executando**: um registro de
  200 dias foi removido e um recente sobreviveu.
- [x] 11.4 `PurgeEmailLogsJob` — **DEC-90**, retenção de 180 dias
  (`EMAIL_LOGS_RETENTION_DAYS`). A tabela `email_logs` é de outra fatia; o job é tolerante à
  ausência dela (registra e sai com 0) para que o agendamento nasça junto com o do DEC-60,
  como a decisão pede. Verificado executando: devolve `0` e loga a ausência, sem erro.
- [x] 11.5 **Portão** que reprova o boot se alguma classe agendada não existir ou se alguma
  expressão cron for inválida — o `NameError` do cron órfão é silencioso até alguém abrir o
  log. Verificado **executando**: com uma entrada `class: JobQueNaoExiste`, `bin/rails runner`
  aborta com `a classe agendada 'JobQueNaoExiste' não existe`.
- [x] 11.6 Limpeza dos membros órfãos dos conjuntos `cron_jobs:*` (nomes cujo hash já não
  existe — sobra do trim do Phase 1b). **Filtrada por existência de hash**, nunca `FLUSHDB`
  nem `destroy_all`: este Redis é compartilhado com o `apl9`. Verificado: `cron_jobs:default`
  caiu de 10 para 4 membros e `cron_job:apl9:data_cleanup` + `cron_job:default:data_cleanup`
  (fila `apl9_default`) continuam intactos.
- [x] 11.7 `spec/config/schedule_spec.rb` — portão em suíte.

### 11.B CSP bloqueante e Google Analytics (DEC-48, DEC-87)

- [x] 11.8 **DEC-48 inverte a tarefa 3.4**: o CSP nasce bloqueante. Ver a nota em 3.4 —
  política montada do que a aplicação carrega, varredura executada, 0 violações.
- [x] 11.9 O CSP **não** libera o domínio do Google Analytics enquanto a flag estiver
  desligada (**DEC-87**, condição 3). `googletagmanager.com` e `google-analytics.com` só
  entram na política quando `VITE_GA_ENABLED=true` **e** há `VITE_GA_MEASUREMENT_ID`
  (`frontend/csp.config.ts`). São duas travas, não uma.
- [x] 11.10 Snippet **GA4 correto** no repositório, **desligado** por ENV
  (`frontend/public/analytics-ga4.js`). O do legado é Universal Analytics com ID GA4
  (`G-7E78XXZX5X` + `ga('create', …)`): não coleta nada hoje.
- [x] 11.11 **Consentimento antes da primeira coleta** (DEC-87, condição 2): Consent Mode
  v2 nega tudo por default e o `gtag.js` **não é carregado** até
  `window.sfgAnalytics.grantConsent()`. Pendência declarada no runbook: a interface que
  pede o consentimento — enquanto ela não existir, nada é coletado, que é o correto para
  quem está desligado.
- [x] 11.12 Varredura de console versionada como **portão**:
  `frontend/scripts/csp-console-sweep.mjs` sai com código ≠ 0 se houver violação de CSP,
  erro de página ou falha de navegação. Executada: 10 rotas × light/dark, 0 violações,
  Work Sans e Fira Mono carregadas de `fonts.gstatic.com`, WebSocket do Action Cable
  aberto.

### 11.C A chave do Google Maps chega ao navegador (DEC-61)

- [x] 11.13 `Credential::PROVIDERS` estendido com `receitaws` e `google_maps`
  (`app/models/credential.rb`), e o `values:` do endpoint passa a derivar da constante em
  vez de repetir a lista — duas listas para a mesma regra é como elas divergem.
  ⚠ **Fora da minha trilha** (`app/models`, `app/controllers`): duas linhas, feitas
  porque sem elas o resto do DEC-61 não funciona. Avisado no relatório.
- [x] 11.14 `GET /api/v1/runtime_config` — endpoint **autenticado** que devolve a chave em
  runtime (`app/controllers/api/v1/runtime_config.rb`), que é a saída **recomendada** pelo
  DEC-61. Lê o `Credential`, com `GOOGLE_MAPS_API_KEY` como degrau para ambiente que ainda
  não cadastrou a chave. `Cache-Control: private, no-store`.
  Verificado executando: sem sessão responde **401** pela base.
  Registrado em `runtime_config.rb` e no runbook: isto **não é cofre** — chave que vai ao
  navegador é pública por construção, e a proteção real é a restrição por referrer/IP no
  Google Cloud (ação externa).
- [x] 11.15 `VITE_GOOGLE_API_KEY` deixa de ser o caminho e vira degrau documentado
  (`frontend/.env.example`), com o motivo: no build ela fica assada no bundle e trocá-la
  exige deploy.

### 11.D Achado adicional na base, corrigido aqui

- [x] 11.16 As três chaves do **Active Record Encryption** vinham COMMITADAS como default
  em `config/initializers/active_record_encryption.rb`. É a cifra que protege
  `Credential#api_key` — exatamente onde o DEC-61 põe as chaves de terceiro. Em produção
  não há mais default (o `fetch` levanta) e as três entraram na lista de obrigatórias do
  `RequiredEnv`. O default sobrevive em dev/test porque trocá-lo torna ilegível o que já
  está gravado no banco local.

### 11.E Coordenação entre fatias

- [x] 11.17 `PurgeAuditVersionsJob` (**DEC-59**/DEC-78, criado pela fatia S0) entrou no
  `config/schedule.yml`. A S0 deixou o agendamento explicitamente para cá — está escrito
  no cabeçalho do próprio job. Sem esta linha o job existiria e **nunca rodaria**, e
  ninguém perceberia, porque nada falha. Retenção corrigida no `.env.example` de 365 para
  **1825 dias** (5 anos), que é o default do job.
- [x] 11.18 Portão contra esse mesmo buraco em `spec/config/schedule_spec.rb`: reprova se
  existir `app/jobs/purge_*_job.rb` que não esteja declarado no schedule.
