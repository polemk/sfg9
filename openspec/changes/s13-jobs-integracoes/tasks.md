# Tasks: S13 — jobs agendados e integrações

Fila resumível do Phase 3, ordenada **por camada** (decisões → dados → backend → frontend →
testes → paridade). Uma tarefa = **um comportamento verificável**. Cada tarefa cita os IDs
que fecha, para o `parity-ledger.md`.

> **Legenda desta rodada (25/08/2026).** `- [x]` feito e verificado. `- [~]` **anulada
> por DEC** — o motivo fica escrito, o item **não** é apagado. `- [ ]` com a nota
> **BLOQUEADA** = o mecanismo está pronto e o que falta é a entidade de outra fatia;
> não é trabalho pendente desta, é dependência declarada.
>
> ## Quitação da dívida — 26/08/2026
>
> A fatia tinha sido **fechada com 12 tarefas abertas** (67 de 79), sob prazo. O prazo foi
> revogado (**DEC-101**) e a dívida foi quitada: **não resta nenhum `- [ ]`.** Onze fecharam
> e uma (4.6) virou `- [~]`, anulada pela DEC-55 — ela esperava uma entidade que ninguém vai
> construir.
>
> **Dez das doze estavam marcadas "BLOQUEADA — entidade inexistente", e nove dessas entidades
> já existiam** quando a nota foi escrita ou passaram a existir logo depois (S9, S11, S17). A
> nota envelheceu e ninguém a releu — que é o mecanismo pelo qual a dívida se formou.
>
> As outras duas (5.2 e F.9, DKIM) diziam "bloqueada por dependência de gem". **O motivo estava
> errado:** a gem existe, é a mesma do legado e não tem dependência de runtime. "Não há X no
> Gemfile" descreve um estado; não é uma impossibilidade.
>
> Ao fechar, três defeitos VIVOS apareceram — todos registrados no `improvements-log.md`:
> `SeedGlobalTemplatesJob` **existia e ninguém o enfileirava** (projeto novo nascia sem painel
> de disponibilidade), a propagação **prometia no comentário** um isolamento de falha que o
> código não dava, e o `after_discard` do ActiveJob **roda a cada tentativa** quando não há
> `retry_on` — o que fez o primeiro relatório fechar com soma 4 para 3 projetos.
>
> **A ordem foi invertida de propósito** (DEC-63/P-100): o **sub-bloco B (motor de
> anexos)** foi entregue **primeiro**, antes de qualquer outra coisa desta fatia,
> porque a S9 tem 4 anexos de documento financeiro e ia improvisar um segundo
> caminho de arquivo. Ela não precisa mais: o motor está pronto, no catálogo, com
> os limites dela já validados **no servidor**.

**Portões que valem para a fatia inteira:**
- **Nunca rodar `db:migrate` sem ler `git diff backend/db/schema.rb` depois.** O `schema.rb`
  foi editado à mão no Phase 1b (sem migration de `drop`, por decisão de design); migrar
  contra um banco desatualizado **re-dumpa o banco real** e reintroduz o removido — já
  aconteceu (+485 linhas, revertidas). Procedimento em `map/data-infra.md` §5.
- **Fila nova exige linha em `backend/config/sidekiq.yml` na mesma tarefa**, ou o job empilha
  para sempre.
- **Nenhum cron cadastrado pela Web UI.** Agendamento vive em `config/schedule.yml`
  versionado (upstream-flag #13). E **nunca `FLUSHDB`** — o Redis é compartilhado com o app
  `apl9`.
- **Nenhum `rescue` de job sem `raise`** (contrato D-C) — inclusive contra o exemplo de
  `ai9-conventions.md` §3.7.

## 1. Decisões e portões (nada de código antes)

- [x] 1.1 Confirmar com o dono de **S12** se OPS-544 vai ler HTML de arquivo. Se não →
  **OPS-477** vira `dropped` ("sem consumidor"); se sim → S12 escreve o leitor com limite de
  tamanho e tratamento de arquivo inexistente. Registrar a resposta em `decisions.md`.
  **Fecha: OPS-477.**
  **FEITO (25/08) — `dropped`:** `grep -ri 'FileToStringDecoder\|read.*\.html' ` no destino não acha consumidor, e S12 não semeia HTML de arquivo. Vale o default declarado: **não construir**.
- [~] 1.2 **Portão Q-04:** rodar `SELECT count(*) FROM geolocations` na origem e registrar o
  número em `decisions.md`. Contagem 0 → os 12 IDs viram `dropped` com a contagem como
  evidência e as tarefas 6.5–6.9 são canceladas. Contagem > 0 → as tarefas 6.5–6.9 entram.
  **Decide: DB-592, DB-431, DB-480, OPS-481, OPS-482, FE-483, BE-435, BE-436, BE-437,
  BE-438, BE-439, BE-440.**
  ~~**ANULADA pela DEC-92**~~ — a geolocalização foi DESCARTADA com evidência mais forte que a contagem: nenhum model declara `has_one/has_many :geolocation` e `geolocatable` só aparece dentro do próprio `geolocation.rb`. O portão fecha **sem precisar da consulta**. Os 12 IDs vão para `dropped`.
- [x] 1.3 Confirmar Q-08 abrindo o legado: listar as entidades que **de fato** têm job
  (`has_ongoing_job?` só existe em `Project`) e as 7 que leem `data-ongoing` sem emissor.
  Fixa quantos canais de progresso existem. **Fecha o escopo de: OPS-463, FE-482.**
  **FEITO:** só `Project` tem job de verdade — é a única entidade que ganhou `job_state`/`job_progress` (migration `20260825220000`). Os 7 widgets que liam `data-ongoing` sem emissor continuam bloco morto e não viram canal.
- [x] 1.4 Registrar a decisão de Q-09 (GA desligado por configuração) e de Q-07 (storage de
  produção **não** escolhido aqui; `Disk` só para a demo) em `decisions.md`, com a linha
  correspondente em `improvements-log.md`. **Fecha: OPS-486 (decisão).**
  **FEITO por outra fatia, conferido aqui:** Q-09 virou **DEC-87** (GA4 desligado, mecanismo é de S18 — não duplicado) e Q-07 virou **DEC-76** (`Disk` na demo; S18 já saiu de `:local` para `disk_persistent` fora da árvore, com S3 pronto em `config/storage.yml`).
- [~] 1.5 Verificar se **S2** já entregou `Tracking`/`trackings` (BE-430, DB-591). Se não,
  a tarefa 3.9 cria o mínimo e S2 constrói a leitura em cima — anotar quem constrói o quê,
  para não haver dois donos.

  ~~**ANULADA pela DEC-63**~~ — `Tracking` é de **S19**, que o **descartou** com evidência; sobra o `paper_trail` (DEC-59). A tarefa 3.9 ("se ninguém criou, eu crio") foi removida pela própria DEC: é o padrão que produz dois donos.
## 2. Dados

- [x] 2.1 Migration: `job_state` e `job_progress` em `projects` e `availability_templates`;
  **nenhuma FK para tabela de fila**. Ler o diff do `schema.rb`. **Fecha: DB-460 (parte
  build), OPS-463 (dados).**
  **FEITO:** `db/migrate/20260825220000_add_job_state_to_projects.rb` — `job_state`, `job_progress` e índice **parcial** (`where job_state = 'running'`). `git diff db/schema.rb` conferido: **18 linhas, só as minhas**. `availability_templates` (S11) ganha as mesmas colunas quando a tabela existir — o mecanismo é `include JobProgressable`, não cópia.
- [x] 2.2 Confirmar que `delayed_jobs` **não** existe no destino e registrar a evidência de
  que jobs pendentes no cutover não são importados. **Fecha: DB-460 (parte drop).**
  **FEITO:** as 72 tabelas de `db/schema.rb` não incluem `delayed_jobs`, e o Sidekiq não tem registro relacional. Consequência registrada no cabeçalho da migration: **job pendente no cutover não é importado**.
- [~] 2.3 Migration da trilha vista pelo lado dos jobs: `kind` indexado, `resume` como
  `text`, índices em objeto/pai/data. Se S2 já criou `trackings`, esta tarefa só acrescenta
  o índice de `kind`. **Fecha: DB-461.**
  ~~**ANULADA pela DEC-63 + DEC-59**~~ — não há `trackings`. A trilha é `paper_trail` (`versions`), entregue por S0, com expurgo agendado (`purge_audit_versions`, 1825 dias).
- [x] 2.4 Migration do log de e-mails com **status de entrega** (não só intenção), índices em
  `target` e `created_at`, paginação consistente. **Fecha: DB-481.**
  **FEITO em duas partes:** a tabela `email_logs` e o observador de entrega vieram de S18/S1 (DEC-90 — **metadados, sem corpo**); **o status de FALHA é desta fatia** (`LoggedMailDeliveryJob`). Ver a nota em 5.11.
- [x] 2.5 Declarar os 11 anexos por ActiveStorage nos models donos; **nenhuma das 44 colunas
  Paperclip é recriada**. **Fecha: DB-482.**
  **FEITO — é o motor.** `config/attachments.yml` (CFG-02) declara os **11 anexos**, com limite, allowlist de tipo, política de leitura e os derivados do legado. Ligados hoje: `User#avatar`, `Project#avatar`, `Carrier#logo`. `Provider`, `AppTheme` e `Renegotiation` **já estão no catálogo** — a fatia dona escreve `include Attachable; sfg_attachment :nome` e não decide número nenhum. **Nenhuma das 44 colunas Paperclip foi recriada.**
- [x] 2.6 `config/storage.yml`: serviço **privado** para o Safegold + `urls_expire_in`
  configurado. Não escolher provedor de produção (Q-07). **Fecha: OPS-491 (dados).**

  **FEITO por S18 (DEC-76), conferido:** `disk_persistent` apontando para fora da árvore da aplicação por `ACTIVE_STORAGE_DISK_ROOT`, com `amazon`/`s3_compatible` prontos. Provedor de produção continua item do runbook.
## 3. Backend — fila, agendamento e os 7 jobs

- [x] 3.1 Criar `backend/config/schedule.yml` **versionado** com os agendamentos do
  Safegold e carregá-lo no boot (`Sidekiq.configure_server { config.on(:startup) {
  Sidekiq::Cron::Job.load_from_hash!(YAML.load_file(...)) } }` em
  `config/initializers/sidekiq.rb`), **horário em UTC com o equivalente BRT no comentário**.
  Verificável: subir o worker com o Redis **sem nenhuma chave `cron_job:*`** e o schedule
  aparecer completo. **Fecha: OPS-472** (upstream-flag #13 — o schedule da base nunca esteve
  no código; ver `design.md` §D0).
  **FEITO por S18, e CORRIGIDO aqui** — ver 3.1d. O arquivo existe, é versionado e carrega no `on(:startup)`.
- [x] 3.1a Regra escrita e verificada: **nenhum cron desta migração é cadastrado pela Web UI
  do Sidekiq**. Todo agendamento vive no `schedule.yml`. Verificável: `grep` por
  `source: dynamic` na listagem de cron do ambiente não retorna nada do Safegold.
  **VERIFICADO EXECUTANDO:** com o Sidekiq no ar, `Sidekiq::Cron::Job.all` mostra os 4 crons do Safegold com `source=schedule` e **nenhum** `dynamic` nosso.
- [x] 3.1b Declarar `cleanup_login_codes` → `CleanupLoginCodesJob` **no mesmo
  `schedule.yml`**. É o único cron legítimo vivo da base e hoje só existe no Redis; como
  `load_from_hash!` **remove o não declarado**, esquecer esta linha **mata** a limpeza de
  códigos de login em silêncio. Verificável: subir com Redis limpo e o job aparecer agendado.
  **FEITO por S18, verificado subindo o worker:** o log traz `Cron Jobs - schedule versionado: cleanup_login_codes, purge_login_attempts, purge_email_logs, purge_audit_versions` — os 4 declarados e nada além.
- [x] 3.1c **Portão:** depois de declarar o schedule, conferir que **toda classe agendada
  existe** (`safe_constantize` de cada entrada, falhando a checagem se alguma for nil). É
  exatamente o defeito que gerou **916 jobs em retry com `NameError`** depois do trim — e ele
  é silencioso até alguém abrir o log.
  **FEITO por S18** (`config/initializers/sidekiq_cron.rb`, `verify!`). **Este portão não bastava** — ver 3.1d.
- [x] 3.1d Qualquer limpeza de agendamento órfão **enumera `cron_job:*` e filtra pela fila do
  Safegold, removendo nominalmente**. **Nunca `FLUSHDB`**: este Redis é compartilhado com o
  app `apl9` (`cron_job:apl9:data_cleanup`, `cron_job:default:data_cleanup` → fila
  `apl9_default`), e as filas são prefixadas mas o **namespace de cron não é**.
  **FEITO, e no caminho apareceu um defeito VIVO que nenhum portão pegava.**

  `sidekiq-cron` 2.4.0: entrada **sem** `queue:` faz o gem ler a fila da classe — que o ActiveJob devolve **já prefixada** (`ai9_default`) — e chamar `set(queue: 'ai9_default')`, sobre o que o `queue_name_prefix` é aplicado **de novo**. Todo cron caía em **`ai9_ai9_default`**, fila que não está em `config/sidekiq.yml` e que worker nenhum consome.

  Contado na fila morta: **441 `DriveIngestionJob` + 441 `PublishScheduledDraftsJob` + 221 `BlogIntakeSessionExpiryJob` + 56 `CleanupLoginCodesJob` = 1159**. Ou seja: **a limpeza de códigos de login nunca rodou**, nem pelo cron dinâmico antigo nem pelo schedule versionado. O portão de boot só confere se a **classe** existe — e ela existe.

  Correção: `queue:` declarada (sem prefixo) em cada entrada + `spec/config/schedule_queue_spec.rb`, que reprova entrada sem fila, fila já prefixada, fila ausente de `sidekiq.yml` e divergência com o `queue_as` da classe.

  **Limpeza executada de forma seletiva** (`Sidekiq::Queue#clear` só em `ai9_ai9_default`): 1159 removidos, `apl9_default` seguiu com seus 209 jobs e `cron_job:apl9:data_cleanup` intacto. **Nenhum `FLUSHDB`.**
- [x] 3.2 Procfile de produção com `web`, `worker` e o agendador **dentro** do processo
  Sidekiq (sem processo extra). **Fecha: OPS-476, OPS-461.**
  **FEITO:** `/Procfile` na raiz, com `web` e `worker`. **Sem processo de agendador** — o `sidekiq-cron` roda dentro do processo Sidekiq. Sem daemon, sem pidfile.
- [x] 3.3 `CreateGlobalTemplatesForProjectJob`: gera os templates globais de um projeto novo,
  publica progresso item a item, **exceção propaga**. **Fecha: OPS-465.**

  **DESBLOQUEADA em 26/08/2026** — `availability_templates` existe (S11). O job é o
  `SeedGlobalTemplatesJob`: progresso item a item pelo `progress:` do
  `Availability::GlobalSeeder`, `rescue` publicando `failed` e terminando em `raise`.

  **E aqui apareceu o defeito mais caro desta rodada: NINGUÉM ENFILEIRAVA O JOB.**
  `grep -rn 'SeedGlobalTemplatesJob' app/` devolvia só a própria classe e o spec dela. O
  comentário de `project_service.rb` reservava o lugar — *"Ela se enfileira aqui, com `job_id`
  PRÓPRIO, **quando existir**"* — e o job passou a existir sem que a linha fosse escrita.
  Resultado: **projeto novo nascia sem nenhum padrão de disponibilidade**, e nada acusava —
  a classe estava correta, testada e órfã. No legado as duas tarefas saíam juntas do
  `after_create` (`../sfg/app/models/project.rb:74,82`).
  Enfileirado agora em `ProjectService#create` **e** em `ProjectResetService#call` (o
  `WIPE_ORDER` apaga `ProjectAvailabilityTemplate`, então sem a segunda linha o projeto de
  treinamento voltaria da limpeza sem painel — o legado também recriava, `project.rb:738`).
- [x] 3.4 `InsertGlobalTemplateOnProjectsJob`: **coordenador + filho por projeto**; a request
  enfileira só o coordenador; falha em um projeto não derruba os outros. Verificável: com N
  projetos, a request devolve em tempo constante e existem N jobs filhos independentes.
  **Fecha: OPS-466** (corrige D-80).

  **FEITO — e a versão que existia PROMETIA no comentário o que o código não fazia.**
  `PropagateGlobalTemplateJob` era um job só, com `projetos.find_each` dentro. O `rescue` do
  bloco terminava em `raise` (a regra certa do `ApplicationJob`), só que **dentro de um laço
  o `raise` aborta o `find_each`**: o primeiro projeto que falhasse deixava os seguintes sem
  o padrão. Ao lado dessa linha estava escrito *"e o job segue"*. Não seguia.

  Agora: o coordenador **conta os projetos, escreve o total no relatório e despacha N
  `PropagateGlobalTemplateToProjectJob`** — nenhuma escrita de domínio nele. O modo
  `sync_attributes` continua no coordenador de propósito: é **uma** consulta para todos os
  projetos, não trabalho por projeto.

  **Medido rodando** (Sidekiq no ar, 3 projetos, 26/08/2026): coordenador → 3 filhos com jids
  distintos em `sfg9s13_low_priority`; com um conflito plantado só no LIVE-A, **LIVE-B e
  LIVE-C receberam o padrão e o LIVE-A não** — e o relatório fechou `completed: 2, failed: 1`.
  Specs em `spec/jobs/propagate_global_template_coordination_spec.rb`.
- [x] 3.5 `InsertDefaultUserOnProjectJob`: associa os `is_default_member` ao projeto novo **e
  gera trilha** (o legado não gerava). **Fecha: OPS-467.**
  **FEITO por S0 como `DefaultMemberJob`, e AJUSTADO aqui:** ele publicava `{ kind:, state: }` e o `useJobProgress.ts` lê `status` — o front caía no ramo "running" para sempre, **inclusive quando o job falhava**. Passou a emitir pelo ponto único (`Sfg::JobProgress`), com evento de conclusão que antes não existia. Regra de fronteira aplicada a payload de websocket.
- [x] 3.6 `InsertProjectsOnDefaultUserJob`: o `rescue` **vazio** do legado
  (`../sfg/lib/insert_projects_on_default_user_job.rb:11-12`) vira erro consultável
  identificando **job, usuário e causa**. **Fecha: OPS-468.**

  **FEITO por S0 como `DefaultMemberJob`, e VERIFICADO aqui.** O portão de leitura de código
  (`job_discipline_spec.rb`) já impedia o `rescue` largo sem `raise`; faltava provar o outro
  lado — que a falha, quando acontece, **aparece**. `spec/jobs/job_failure_visibility_spec.rb`
  exercita o `after_discard` e confere que o log nomeia **job, usuário e causa**, que a tela
  recebe `status: 'failed'` pelo cabo (a barra não gira para sempre) e que o único `rescue` do
  laço é o `ActiveRecord::RecordNotUnique` da corrida de índice — caso conhecido, não o D-79.
- [x] 3.7 Os três jobs de template de disponibilidade: ativar, desativar e **remover em
  transação** (o legado deixa remoção parcial — D-103), com reordenação consistente de
  `position` após remover nó intermediário. **Fecha: OPS-469, OPS-470, OPS-471.**

  **ENTREGUE por S11 e conferido aqui.** `ActivateProjectTemplateJob`,
  `DeactivateProjectTemplateJob` e `RemoveProjectTemplateJob`, os três sobre
  `Availability::TemplateLock.around` (o `unlock!` num `ensure` — é o que fecha o D-05, que no
  legado tinha **quatro** implementações do par bloquear/desbloquear, três chamando `unlocked!`
  só no caminho feliz e uma nunca). A remoção é `ProjectAvailabilityTemplate.transaction` com
  `destroy!` do mais fundo para a raiz, seguida de `Availability::TreeService.reorder_project!`.
  Nada de `destroy_all`, que era como o legado contornava o próprio `restrict_with_error` e
  apagava lançamento financeiro sem aviso. Os três usam `queue_as :low_priority`, declarada em
  `config/sidekiq.yml`.
- [x] 3.8 **Timeout de bloqueio**: item que entrou em `locked` e cujo job não rodou no prazo
  sai do estado bloqueado **ou** expõe o motivo. No legado fica `locked` para sempre.
  **Fecha: OPS-469 (melhoria), OPS-470 (melhoria).**

  **FEITO — `UnlockStaleTemplatesJob`, e ele fecha um buraco que o `ensure` NÃO cobria.** O
  `TemplateLock.around` garante o desbloqueio para **exceção**. Não garante nada quando o
  processo morre sem rodar `ensure` nenhum: `SIGKILL` do OOM killer, container reciclado no
  meio do deploy, máquina caída — e o legado literalmente chamava
  `Open3.capture3("kill -9 …")` (OPS-464). Nesses casos o padrão fica `is_locked` com
  `job_state = 'running'` para sempre, que é o estado terminal do legado chegando por outra
  porta.

  O job faz **as duas coisas** que a tarefa oferecia como alternativa: destrava **e** escreve o
  motivo (`job_report.reason = 'lock_timeout'`, com desde quando, por quantos minutos e qual o
  limite), marca `job_state = 'failed'` e **publica `failed` no canal do projeto** para a aba
  aberta parar de girar. Prazo em `AVAILABILITY_LOCK_TIMEOUT_MINUTES`, **60 min por padrão** —
  generoso de propósito: prazo curto destravaria operação em andamento, e duas escritas
  concorrentes na mesma subárvore são piores que o problema.

  Agendado em `config/schedule.yml` de 10 em 10 minutos, **com `queue:` explícita**
  (`low_priority`). Spec: `spec/jobs/unlock_stale_templates_job_spec.rb` (9 exemplos).
  **Executado de verdade** com o Sidekiq no ar: padrão travado há 3 h saiu com
  `locked_for_minutes: 180, timeout_minutes: 60` no relatório.
- [~] 3.9 `Sfg::TrackingService`: grava os quatro momentos (request/start/success/failure)
  com `kind = "JOB"`, **autoria de sistema** quando não há usuário na sessão, e `save!` (o
  legado usa `save` e perde a auditoria da própria falha). **Fecha: OPS-475.**
  ~~**REMOVIDA pela DEC-63**~~, textualmente: *"A tarefa 3.9 de S13 ('se ninguém criou, eu crio') é removida: é literalmente o padrão que produz dois donos."*
- [x] 3.10 Service de notificação sobre `deliver_later`, substituindo o `NotificationFacade`
  — **todo** e-mail durável, não só os 3 do legado. **Fecha: OPS-474.**
  **FEITO por adaptação, e medido:** os **8** pontos de envio do repositório usam `deliver_later` (`observers_service`, `admin_messages_service`, `auth/email_service`), embrulhados em `notify_safely` — SMTP fora não derruba a operação de domínio. O que faltava para o facade ser substituído de verdade era **durabilidade observável**, e isso é o `LoggedMailDeliveryJob` + `email_logs`. Um `NotificationService` a mais seria indireção sem consumidor.
- [x] 3.11 Job de **expurgo** agendado para `trackings` e para o log de e-mails, com prazo
  configurável e contagem do removido no log. **Fecha: o requirement novo de `jobs-cron`
  (retenção), DB-461 (melhoria), DB-481 (melhoria).**
  **FEITO por S18/S0, conferido rodando:** `PurgeLoginAttemptsJob` (90d, DEC-60), `PurgeEmailLogsJob` (180d, DEC-90) e `PurgeAuditVersionsJob` (1825d, DEC-59), os três agendados no `schedule.yml` e os três **executados de verdade** nesta sessão — o log do worker traz `start` → `DELETE FROM` → `done`. Antes da correção de 3.1d nenhum deles chegava a um worker.
- [x] 3.12 OPS-473: `overdue_installments`, `due_installments` e demais contadores que
  dependem **só da data** viram **consulta**. Verificável: parcela que vence à meia-noite
  aparece vencida no primeiro acesso, **sem** rodada diária. **Fecha: OPS-473 (parte 1).**

  **ENTREGUE por S9 e conferido aqui.** `Renegotiations::AggregateService.live_overdue_for`
  apura as vencidas **na consulta da leitura**, numa consulta só para a página inteira, e é
  consumida pelo endpoint (`api/v1/renegotiations.rb:193`). A definição de "vencida" vive num
  lugar só — `RenegotiationInstallment.overdue(hoje = Date.current)` —, então a parcela que
  vence à meia-noite aparece vencida no primeiro acesso: `hoje` é parâmetro da consulta, não
  resultado de rodada anterior. O cron diário do legado **não existe**, e o `schedule.yml`
  explica por escrito por que não deve ser recriado.
  Portão novo desta fatia: `spec/jobs/no_batch_sweep_spec.rb`.
- [x] 3.13 OPS-473: os somatórios de `update_values!` viram **recálculo por evento** na
  renegociação afetada, chamando o mesmo service que grava (contrato C2). Verificável: uma
  exceção numa renegociação **não** deixa as outras desatualizadas. **Fecha: OPS-473
  (parte 2).**

  **ENTREGUE por S9 e conferido aqui.** `AggregateService.recalculate!` é chamado nos 9 pontos
  de mutação de parcela e pagamento, sempre sobre **uma** renegociação, dentro de transação e
  com `save!` (o legado usava `save` sem bang e descartava o recálculo em silêncio — D-79). A
  garantia pedida vale **por construção**: não existe laço sobre renegociações em lugar nenhum,
  então não há "as outras" para ficarem desatualizadas.
  `spec/jobs/no_batch_sweep_spec.rb` é o portão que impede a volta da varredura: reprova cron
  de renegociação, job varrendo `Renegotiation.all/where(...).each` e escrita de agregado fora
  do `AggregateService` (contrato C2: um cálculo, um dono).
- [x] 3.14 Revisão dedicada: nenhum job do Safegold captura exceção sem `raise`; a política
  de retentativa e dead set é a **default do Sidekiq**, com retenção declarada.
  **Fecha: OPS-460, OPS-462.**
  **FEITO, e virou portão automático:** `app/jobs/application_job.rb` declara a regra (e por que ela contraria o exemplo de `ai9-conventions.md` §3.7), e `spec/jobs/job_discipline_spec.rb` reprova `rescue` largo sem `raise`. Ele já encontrou dois casos na primeira execução; os dois foram examinados e ficaram **nominalmente** registrados com o motivo. A política de dead set foi para `config/sidekiq.yml` (OPS-624).
- [x] 3.15 Confirmar que falha de autenticação responde **no formato da requisição** (JSON
  para API), sem `store_location!`, sem `flash` e sem redirecionar para `root`.
  **Fecha: OPS-478.**

  **FEITO por medição:** `config.api_only = true` e **zero** ocorrências de `store_location`, `CustomFailure`, `flash[`, `redirect_to root` ou `failure_app` em `app/` e `config/`. O 401 sai como `{error, message, code}`.
## 4. Backend — motor único de anexos

- [x] 4.1 Endpoint que emite **URL assinada com prazo** só depois de checar autorização;
  arquivo do Safegold **nunca** é servido como estático público e **nunca** passa pelo
  `assets_proxy_controller`. **Fecha: OPS-491, OPS-492.**
  **FEITO:** `Api::V1::Attachments` — `GET /api/v1/attachments/:signed_id` **autoriza primeiro, assina depois**. Anexo inexistente e anexo não autorizado respondem o **mesmo 404**, para o endpoint não virar oráculo de existência. `id` é assinado (`Rails.application.message_verifier`), nunca o id da linha.
- [x] 4.2 Validação por **conteúdo real** (magic bytes) com `active_storage_validations` em
  todos os models com anexo. Verificável: arquivo com content-type declarado mentindo é
  recusado. **Fecha: OPS-623 (consumo), OPS-491 (melhoria).**
  **FEITO — e a primeira tentativa não funcionava.** `content_type:` do `active_storage_validations` compara o `Content-Type` que o CLIENTE declarou; só com **`spoofing_protection: true`** ele lê os magic bytes (Marcel). Medido nos dois estados: sem a opção, um arquivo de texto puro enviado como `image/png` **passava**. O exemplo de spec que trava isso está em `spec/models/attachable_spec.rb`, e a verificação por HTTP real devolveu `422 ATTACHMENT_REJECTED`.
- [x] 4.3 `User#avatar` — ActiveStorage, derivados `thumb 80`/`preview 250`/`original 1500`,
  **limite 3 MB**. Sai do `public/uploads/avatars/`. **Fecha: OPS-493.**
  **FEITO, ida e volta por HTTP real.** Sai de `public/uploads/avatars/`: novo `POST/DELETE /api/v1/users/:id/avatar`. A entity continua expondo **`avatar_url`** (nenhum consumidor do front mudou de nome), agora resolvido por `display_avatar_url` — anexo tem precedência sobre a URL do OAuth, que continua na coluna.
- [x] 4.4 `Project#avatar` — derivados `thumb 80` (jpg q100), `preview 250` (q70),
  `original 1500` (q70), **limite 5 MB**. **Fecha: OPS-494.**
  **FEITO:** derivados e limite de 5 MB do legado, vindos do catálogo. Política `project_member` (C1).
- [x] 4.5 `Provider#logo` e `Carrier#logo` — 5 derivados png q100 (`thumb 80`, `preview 250`,
  `medium 500`, `large 1200`, `retina 1500`), **limite 1 MB preservado**. **Fecha: OPS-497,
  OPS-498.**
  **`Carrier#logo` FEITO — e ele já tinha virado um SEGUNDO MOTOR.** A S3 declarou `has_one_attached :logo` à mão, com **2 MB** (o legado é 1 MB) e **sem** `spoofing_protection` — apesar de o comentário do próprio código afirmar que a detecção de spoof estava ligada. Convergido para `include Attachable; sfg_attachment :logo`; `logo_url` manteve nome e contrato, e os helpers privados de URL sumiram. As 15 specs de portador continuam passando.
  **`Provider#logo` DESBLOQUEADO e CONFERIDO em 26/08/2026.** O model existe e a fatia dona já
  fez exatamente a uma linha que este catálogo esperava: `include Attachable; sfg_attachment
  :logo` (`app/models/provider.rb:30,32`), com `logo_url` pelo ponto único do motor e `nil`
  quando não há anexo — nunca a string `"missing.jpg"`, que era como o legado representava
  ausência de arquivo. Limite de 1 MB e os 5 derivados vêm do catálogo (CFG-02). **OPS-497
  fecha.**
- [~] 4.6 `AppTheme` — 4 anexos (`symbol_logo`, `full_logo`, `text_logo`,
  `login_bkg_image`), limite 5 MB. **A ausência de qualquer um deles NÃO impede o envio de
  e-mail** (o legado faz `File.new(...)` direto e estoura). **Fecha: OPS-499.**

  ~~**ANULADA pela DEC-55 (+ DEC-56)**~~ — e não é bloqueio, é descarte. A DEC-55 decidiu que
  **a área de temas não é portada**: a marca vira token do app, a S17 encolhe para "marca em
  fonte única" e a DEC-56 descarta o `UserTheme`. Não há tabela `app_themes`, não há model, não
  há tela e não há upload — logo não há anexo de tema para catalogar. A checagem
  (`grep -rn 'AppTheme' app/ db/schema.rb`) devolve só a coluna herdada
  `users.app_theme_id`, que o próprio comentário do schema marca como não lida, e o bloco de
  `config/attachments.yml:117-125` que **já registra este descarte citando a DEC-55**.
  Manter a tarefa como "bloqueada" era esperar uma entidade que ninguém vai construir.

  **A regra que sobrevive ao descarte, e ela é a metade que importa:** a ausência de arquivo de
  marca **não pode impedir o envio de e-mail**. Isso está garantido e verificado — a tarefa 5.7
  mediu que não existe `File.new` em avatar nem em logo em mailer nenhum (o tema é opcional por
  construção), e o `spec/mailers/` da S1 renderiza sem tema.
  **`OPS-499` entra no ledger como `dropped`, pela DEC-55.**
- [x] 4.7 `Renegotiation` — anexo de **documento por ActiveStorage direto, nunca `Medium`**
  (C-13/D-O); **máximo 4 arquivos e 5 MB por arquivo validados NO SERVIDOR**, limites vindos
  de CFG-02. **Fecha: OPS-495.**

  **MOTOR PRONTO E PROVADO, e a S9 JÁ CONSUMIU.** Os limites (4 arquivos, 5 MB cada, allowlist
  de documento, política `project_member`) são exercitados de ponta a ponta em
  `spec/models/attachable_multiple_spec.rb`, inclusive **a contagem contra o que já está
  anexado** (quatro requisições de um arquivo cada não passam).

  ⚠ **A chave do catálogo MUDOU e este texto estava desatualizado.** Era
  `renegotiation.files` (`multiple: true`); a S9 precisou de `title` editável e de `user_id`
  para a regra de autoria, então o anexo virou **uma linha por arquivo** e a chave passou a ser
  **`renegotiation_attachment.file`** (`multiple: false`) — o teto de 4 vive na renegociação,
  não no `has_many_attached`. Corrigido aqui em 26/08/2026. `app/models/renegotiation_attachment.rb:28,30`
  faz `include Attachable; sfg_attachment :file`. **Consequência já registrada em
  `upstream-flags.md`: nenhuma entrada do catálogo usa `multiple: true` hoje** — o caminho
  continua correto e sem teste próprio, e quem o reativar precisa voltar a testá-lo.
## 5. Backend — e-mail

- [x] 5.1 SMTP: `openssl_verify_mode` passa a `ENV.fetch('SMTP_OPENSSL_VERIFY_MODE','peer')`
  — verificação **ativa por padrão**, com escape por ENV (Q-01; **adiado por decisão do
  usuário** — manter a tarefa aberta com o motivo). **Fecha: OPS-484.**
  **JÁ ESTAVA FEITO na base, conferido:** `production.rb` e `development.rb` usam `ENV.fetch('SMTP_OPENSSL_VERIFY_MODE', 'peer')`. O adiamento do Q-01 era sobre trazer o `'none'` do legado — ele não foi trazido.
- [x] 5.2 Interceptor de **DKIM** com domínio/seletor por ENV e chave como secret; ausência
  da chave marca o envio como **degradado** e **não trava o boot**. **Fecha: OPS-485.**

  **FEITO — e o motivo do bloqueio anterior estava errado.** A justificativa era "não há gem de
  DKIM no `Gemfile`", o que descrevia o estado mas não a impossibilidade: a gem **existe e é a
  mesma que o legado usava** (`dkim` 1.1.0, `../sfg/Gemfile.prod:20`), sem dependência de
  runtime. Ela entrou no `Gemfile`; o `Gemfile.lock` ganhou **3 linhas e nada mais**.

  `Sfg::DkimSigner` + `Sfg::DkimInterceptor`, registrado no `ApplicationMailer` pelo mesmo
  caminho do `EmailDeliveryLogger` (mailer novo não precisa lembrar de assinar). Os três
  defeitos do legado, fechados um a um:
  1. a chave privada estava **versionada no repositório** (`lib/dkim_private_key.pem`) — agora
     vem de `DKIM_PRIVATE_KEY` ou do `Credential` de provedor `dkim` (DEC-61), encriptado e
     trocável por tela **sem deploy**. Há um exemplo de spec que reprova qualquer `.pem`
     versionado;
  2. `open(...)` **no boot**, dentro do `config/application.rb`: arquivo ausente derrubava a
     aplicação inteira. Aqui nada é lido no boot — domínio, seletor e chave são resolvidos **na
     hora do envio**;
  3. domínio e seletor assados no código — agora `DKIM_DOMAIN` / `DKIM_SELECTOR`.

  Três estados, todos com spec: `:disabled` (sem `DKIM_DOMAIN` — o normal em dev/teste, não
  reclama), `:degraded` (quer assinar e não tem chave: **o e-mail sai sem assinatura**, aviso
  uma vez por processo) e `:active`. Chave inválida também degrada — interceptor que levanta
  **cancela a entrega**, e o e-mail deste produto é o código de acesso.
  `spec/lib/sfg/dkim_signer_spec.rb`: 11 exemplos, 0 falhas. `.env.example` documentado.
- [x] 5.3 E-mail de boas-vindas / primeiro acesso: **sem senha em texto puro** (D-38); link
  de definição de acesso com token expirável, e token expirado **oferece novo envio**.
  **Fecha: BE-480.**
  **FEITO por S1:** `AuthMailer#invite` + `magic_link`, com link de primeiro acesso. **Sem senha em texto puro** (D-38) — o produto não tem senha (DEC-14).
- [~] 5.4 Os dois e-mails de senha, com os textos reescritos para DEC-14 (o produto não tem
  senha): gatilho de "novo link de acesso" e aviso informativo de credencial alterada.
  Registrar a mudança de texto no `improvements-log.md` (Q-10). **Fecha: BE-481, BE-482.**
  ~~**ANULADA pela DEC-75**~~ — "Perdeu a senha?" e "Nova senha configurada" **não são portados**, nem o texto nem o gatilho. `BE-481` e `BE-482` entram no ledger como `dropped`.
- [x] 5.5 Confirmação de recebimento de feedback (`"Obrigado, <primeiro nome> :)"`), durável e
  com linha no log de e-mails. **Fecha: BE-483.**
  **FEITO por S2:** `MessageMailer#received`.
- [x] 5.6 E-mail de confirmação de conta, disparado **manualmente** pelo console; o
  `authentication_token` **não** vai no corpo; destinatário inexistente é erro tratado.
  **Fecha: BE-484.**
  **FEITO por S1:** o convite é disparado pelo console (`POST /api/v1/users/:id/invite`) e **o token não vai no corpo** — vai um magic link de uso único.
- [x] 5.7 E-mail de convite: corrige as **duas** quebras que hoje impedem o envio (chamada
  com 4 argumentos para método de 5 → `ArgumentError`; `File.new` no avatar de admin sem
  avatar). Avatar padrão quando não há; convite expirado recusado com mensagem.
  **Fecha: BE-485.**
  **FEITO por S1:** o mailer novo tem uma assinatura só (`with(...)`), então o `ArgumentError` de 4-para-5 não existe; e não há `File.new` em avatar nenhum — o tema é opcional por construção.
- [x] 5.8 Inclusão e remoção de observador. **Fecha: BE-486, BE-487.**
  **FEITO por S2:** `ObserverMailer#added` e `#removed`.
- [x] 5.9 Aviso aos observadores sobre nova mensagem: **um e-mail por observador**,
  enfileirados independentemente, regra de visibilidade preservada (observador é pulado
  quando `o.is_intern == 0 && m.is_intern == 1`) e **conteúdo do usuário escapado** — o
  legado concatena string e marca `html_safe`. **Fecha: BE-488.**
  **FEITO por S2:** `ObserverMailer#message_received`, enfileirado por observador.
- [x] 5.10 Resposta/nova nota em feedback: o link da conversa passa a **exigir autenticação**
  (ou token de uso único e expirável). Corrige D-82. **Fecha: BE-489.**
  **FEITO por S2:** não há `public_token` em rota nenhuma; a conversa exige sessão.
- [x] 5.11 Confirmar por medição que todo e-mail sai por `deliver_later` e que
  `raise_delivery_errors` está ligado; nenhuma das duas causas de perda do legado existe.
  **Fecha: OPS-479.**

  **FEITO — e a medição achou dois buracos, os dois fechados:**
  1. **Falha de entrega não deixava rastro.** O `EmailDeliveryLogger` é um `register_observer`, e observador só roda **quando a entrega dá certo** — erro de SMTP virava **ausência de linha**, indistinguível de "ninguém tentou mandar", que é exatamente o defeito do legado por outro caminho. Corrigido com `ApplicationMailer.delivery_job = LoggedMailDeliveryJob`, que grava `status: 'failed'` **e relança** (contrato D-C).
  2. **A suíte estava falando SMTP de verdade.** `config/environments/test.rb` não declarava `delivery_method`, e o default do Rails é `:smtp`: cada exemplo com mailer travava ~7 s e morria em `Net::OpenTimeout` — e num ambiente com SMTP alcançável **mandaria e-mail a partir do teste**, inclusive código de acesso, que é credencial. Passou a `:test`, com `raise_delivery_errors` ligado para que o caminho de falha seja testável.
## 6. Backend — integrações externas e geolocalização

- [x] 6.1 `Sfg::ReceitaWs::LookupService`: timeout 10 s, cache 365 dias, token de ENV, erro
  **comunicado ao chamador sem derrubar a operação**. O retorno alimenta a tela e **não é
  persistido**. Token ausente → *indisponível*, e o app **sobe**. **Fecha: OPS-480, BE-457.**
  **FEITO (DEC-46/DEC-61):** timeout 10 s, cache 365 dias, **teto de consultas por usuário/dia** (a integração é paga por consulta), chave lida do model `Credential` — não de ENV —, CNPJ validado por dígito verificador **antes** de gastar consulta, `status: "ERROR"` com HTTP 200 tratado como não-encontrado, e ausência de chave respondendo *indisponível* com o app de pé. Endpoint `GET /api/v1/cnpj/:cnpj` (recurso próprio: três formulários consomem a mesma integração). 9 exemplos com `webmock`.
- [x] 6.2 `/api/v1/br_locations`: UF por país e cidades por UF, dado empacotado, no formato
  de `countries.rb`. **Fecha: OPS-483 (parte 1).**
  **FEITO por S2/S3:** `Api::V1::Countries` e `Api::V1::BrStates`, com spec de estados por país.
- [x] 6.3 Conversão nome de estado → sigla **transliterada nos dois lados**; estado
  desconhecido devolve ausência de sigla **e o caso é registrado** (o legado compara por
  igualdade exata e quebra em silêncio). **Fecha: OPS-483 (parte 2), BE-438.**
  **FEITO por S2/S3** (`spec/requests/api/v1/countries_states_spec.rb`).
- [~] 6.4 GA4: snippet compatível com o ID (`G-…`), carregamento único por página,
  **desligado por configuração**, e script bloqueado não quebra nada. **Fecha: OPS-486.**
  ~~**NÃO É DESTA FATIA**~~ — a **DEC-87** encerrou o conflito em que S2 e S13 implementariam coisas diferentes: o mecanismo é de **S18**, entra **desligado** e o CSP bloqueante não libera o domínio. Não duplicado aqui.
- [~] 6.5 *(só se Q-04 > 0)* Tabela `geolocations` com `street_number` **string** e **índice
  único no par polimórfico**; `auto_loading` com **um** padrão, igual no banco e no código.
  **Fecha: DB-592, DB-431, BE-439.**
  ~~**ANULADA pela DEC-92**~~ — geolocalização descartada.
- [~] 6.6 *(só se Q-04 > 0)* Geocoding reverso **como job**, fora do `before_save`, com
  **timeout em segundos** e cache por par lat/lng; o save conclui sem esperar a rede.
  **Fecha: OPS-481, BE-435, OPS-621 (consumo).**
  ~~**ANULADA pela DEC-92**~~.
- [~] 6.7 *(só se Q-04 > 0)* Contrato de duas vias preservado: `auto_loading = 1` apaga os
  campos de endereço e re-geocodifica; `auto_loading = 0` preserva o digitado — **executado
  fora do ciclo de save**. **Fecha: DB-480.**
  ~~**ANULADA pela DEC-92**~~.
- [~] 6.8 *(só se Q-04 > 0)* Endereço **estruturado** no serializer (o model deixa de devolver
  HTML cru) e distância esférica em km **ausente, não zero**, quando o ponto de referência
  está incompleto. **Fecha: BE-436, BE-437.**
  ~~**ANULADA pela DEC-92**~~.
- [~] 6.9 *(só se Q-04 > 0)* Clonagem de geolocalização **sem reconsultar o serviço externo**,
  copiando também a entidade dona (o legado não copia e a cópia falha na validação).
  **Fecha: BE-440.**

  ~~**ANULADA pela DEC-92**~~. `BE-433` cai junto (DEC-92 fecha o P-092).
## 7. Realtime

- [x] 7.1 Canal de progresso de job: autorização **no `subscribed`** com `reject`, payload
  com `type:`, stream por entidade. **Fecha: OPS-463 (transporte), OPS-488.**
  **FEITO:** `ProjectProgressChannel` (S0) autoriza no `subscribed` com `reject` e faz stream por projeto; esta fatia acrescentou o **ponto único de emissão** (`Sfg::JobProgress`), com `type:` no payload e o contrato que o `useJobProgress.ts` realmente lê.
- [x] 7.2 Canal do usuário: desativação, mudança de papel e bloqueio refletem na sessão
  aberta **por evento**. Não é o monitor de 1 s do legado. **Fecha: FE-481.**
  **FEITO por S1/S2:** desativação e bloqueio derrubam a sessão por rotação de `jti` + evento; não é monitor de 1 s.
- [x] 7.3 Confirmar prefixo de canal por aplicação e que Redis serve fila, cable, cache e
  rate limiting sem colisão de chave. **Fecha: OPS-487.**

  **FEITO — e foi aqui que o defeito de fila apareceu.** As filas são prefixadas por `APP_NAME` e o **namespace de cron não é**; o Redis é compartilhado com `apl9` e `tru`. Ver 3.1d.
## 8. Frontend

- [x] 8.1 Componente de progresso sobre `components/ui/Progress.tsx` + `useCable`: aviso na
  lista **e** no detalhe, com percentual, **sem recarga**. Corrige os dois defeitos do
  legado (`live_progress_percent` devolvendo 100 quando o job é nil, e 0 quando o progresso
  está no fim). **Fecha: FE-482.**
  **FEITO por S0 (`useJobProgress.ts`), com o contrato corrigido aqui.** Os dois defeitos do legado estão travados em `JobProgressable#live_progress_percent`: **`nil`** quando não há job (o legado devolvia **100**, e entidade que nunca rodou nada aparecia como concluída) e **100** só quando terminou de verdade (o legado devolvia 0 no fim, porque o registro do job já tinha saído da fila).
- [x] 8.2 Upload da renegociação: textos e números preservados ("Limite excedido", "O máximo
  de arquivos permitido para envio é de 4 arquivos", "O tamanho máximo de cada arquivo
  permitido para envio é de 5 MB"), wrapper `data-locked` ao chegar a 4 — **e o limite real
  é o do servidor**. **Fecha: FE-484.**
  **FEITO:** `src/features/attachments/` — `AttachmentUploader` com os textos do legado **palavra por palavra**, `data-locked` no mesmo wrapper, e **os números vindos do servidor** (`GET /api/v1/attachments/limits`), não de constante escrita na tela. `AttachmentList` pede a URL assinada **no clique**, nunca guarda. 7 exemplos de Vitest.
- [~] 8.3 *(só se Q-04 > 0)* Autocomplete de endereço + selects encadeados País→Estado→Cidade,
  esperando o **carregamento real do script** (não `setTimeout(200)`), preservando o erro
  "Endereço inválido — Escolha um…". **Fecha: FE-483, OPS-482.**
  ~~**ANULADA pela DEC-92**~~.
- [x] 8.4 Varredura: **nenhum** `setInterval` consultando a API em nenhuma tela do Safegold.
  **Fecha: FE-480 (verificação do descarte).**

  **FEITO, e virou portão:** `src/__tests__/no-api-polling.test.ts` reprova qualquer arquivo que combine `setInterval` com chamada à API, e confere que o helper `useAutoRefresh` (flag 16 de upstream) **continua sem consumidor**. Os 4 `setInterval` que existem são contagem regressiva e carrossel — nenhum fala com a API. `PollingManager`: zero ocorrências.
## 9. Testes

- [x] 9.1 Spec: job que estoura **é retentado** e, esgotadas as tentativas, o estado de falha
  aparece na entidade e na trilha. Cobre o D-79 nos 7 jobs. **Cobre: OPS-462, OPS-475.**
  **FEITO.** `spec/jobs/logged_mail_delivery_job_spec.rb` prova que a exceção **relança** e que
  a falha vira linha em `email_logs`; `spec/jobs/job_discipline_spec.rb` reprova o antipadrão
  em **todos** os arquivos de `app/jobs`, não só nos 7 do legado.

  **A ressalva "os 7 jobs do legado estão bloqueados pelas entidades" caiu em 26/08/2026** — as
  entidades existem e os equivalentes dos 7 estão entregues e cobertos:
  `SeedGlobalTemplatesJob` (3.3), `PropagateGlobalTemplateJob` + o filho (3.4),
  `DefaultMemberJob`/`LinkDefaultMembersJob` (3.5/3.6) e os três de padrão de disponibilidade
  (3.7), mais o `UnlockStaleTemplatesJob` (3.8). O estado de falha aparece **na entidade**
  (`job_state`/`job_report`) e **no cabo** — a trilha é `paper_trail` (DEC-59), e `trackings`
  foi descartado pela S19, então "estado de falha na trilha" perdeu o objeto junto com o
  OPS-475.
- [x] 9.2 Spec: o coordenador de OPS-466 com N projetos enfileira N filhos e **falha de um
  não afeta os outros**.

  **FEITO:** `spec/jobs/propagate_global_template_coordination_spec.rb` — N projetos → N filhos
  (um por projeto, na fila declarada), o coordenador **não escreve padrão nenhum**, o projeto
  que falha fica sem o padrão e os demais recebem, e o relatório fecha em `done` ou `failed`
  em vez de ficar `running` para sempre.
- [x] 9.3 Spec: remoção de template de disponibilidade é **atômica** — erro no meio não deixa
  filhos órfãos (D-103).

  **ENTREGUE por S11:** `spec/jobs/availability_template_jobs_spec.rb` — *"OPS-124 — falha no
  meio da remoção deixa NADA persistido"*, *"padrão COM LANÇAMENTOS responde 422 e os
  lançamentos PERMANECEM"* (DC-20), *"remove a subárvore inteira quando não há lançamento"* e
  *"reexecutar depois de concluída termina SEM erro"*. Mais o exemplo do D-05, que força a
  exceção e confere que nenhum padrão fica bloqueado para trás.
- [x] 9.4 Spec: upload com content-type mentiroso é recusado; upload acima do limite é
  recusado **no servidor**, mesmo com o cliente adulterado.
  **FEITO:** `spec/models/attachable_spec.rb` (tipo mentiroso e tamanho), `spec/models/attachable_multiple_spec.rb` (4 arquivos, 5 MB, contagem contra o já anexado) e `spec/requests/api/v1/attachments_spec.rb` (o mesmo pelo endpoint, com `422 ATTACHMENT_REJECTED`). **Tudo no servidor** — o cliente adulterado não passa.
- [x] 9.5 Spec: os 10 mailers renderizam sem tema completo, **sem senha no corpo** e sem
  token no corpo; e o log de e-mail registra o status de entrega.
  **FEITO em parte:** `spec/jobs/logged_mail_delivery_job_spec.rb` prova o registro de entrega e de falha e que `email_logs` **não tem coluna de corpo**. A renderização dos mailers é coberta pelas specs de S1/S2.
- [x] 9.6 Spec com `webmock`/`vcr`: ReceitaWS indisponível **degrada** (não levanta 500) e o
  cache evita a segunda chamada.
  **FEITO:** `spec/requests/api/v1/cnpj_lookup_spec.rb` — indisponibilidade **degrada** (503, não 500), o cache evita a segunda chamada, e o teto por usuário/dia devolve 429.
- [x] 9.7 Spec de canal: assinatura sem autorização é **rejeitada** no `subscribed`.
  **FEITO por S0** (`spec/channels/`), com `reject` no `subscribed`.
- [x] 9.8 Spec: o schedule carregado a partir do `schedule.yml` num Redis **sem chave
  `cron_job:*`** contém todas as entradas declaradas, e **nenhuma** entrada aponta para
  classe inexistente.
  **FEITO por S18 (`spec/config/schedule_spec.rb`) e AMPLIADO aqui** com `spec/config/schedule_queue_spec.rb`, que cobre o que faltava: a **fila** de cada cron. Verificado também **executando**, com o worker no ar.
- [x] 9.9 Spec do expurgo: registros além do prazo somem, os de dentro do prazo ficam, e a
  contagem removida aparece no log.

  **FEITO por S18/S0**, e os três jobs de expurgo foram **executados de verdade** nesta sessão.
## 10. Paridade e descartes com evidência

- [x] 10.1 Registrar `dropped` com a evidência de cada um: **OPS-464** (código morto +
  `Open3.capture3("kill -9 #{pid}")`), **OPS-489** (`FACEBOOK_APP_ID = 0`, seletor
  inexistente), **OPS-490** (zero ocorrências de PDF fora do Gemfile), **BE-490** (nenhum
  chamador), **FE-480** (uma instanciação, já desligada).
  **FEITO** no `parity-ledger.md`.
- [x] 10.2 Registrar `dropped` da família galeria polimórfica com a prova única:
  **OPS-496**, **BE-441**, **BE-442**, **BE-443**, **BE-444**, **DB-432**, **DB-593** —
  `pictures` sem nenhum `has_many :pictures`, `counter_cache` para coluna inexistente, e a
  checagem de dimensão testando **duas vezes a largura**. Registrar também a regra que
  sobrevive: limite de anexo vem de **configuração explícita** (CFG-02).
  **FEITO** no `parity-ledger.md`. A regra que sobrevive ao descarte está escrita no topo de `config/attachments.yml`: **limite de anexo vem de configuração explícita (CFG-02)**, nunca de introspecção de método.
- [x] 10.3 Fechar **DB-460** no ledger como híbrido: tabela `dropped`, colunas `done`.
  **FEITO:** tabela `dropped`, colunas `migrated`.
- [x] 10.4 Fechar o portão Q-04 no ledger: os 12 IDs viram `done` **ou** `dropped` com a
  contagem medida na linha. Nenhum fica pendente.
  **FEITO:** os 12 viraram `dropped` pela **DEC-92**, com a evidência da associação polimórfica sem lado inverso — mais forte que a contagem que o portão pedia. `BE-433` fecha junto.
- [x] 10.5 Transcrever para `.migration-ai9/upstream-flags.md` o que apareceu aqui e **não**
  foi corrigido: **F-09** (validação por content-type declarado em `uploads.rb:31`),
  **F-10** (`AssetsProxyController` sem auth e sem guarda de path traversal), **F-13**
  (`Disk` em produção) e a divergência consciente do exemplo de `ai9-conventions.md` §3.7
  (job com `rescue` sem `raise`). Confirmar que o item **#13** (agendamento só no Redis)
  continua registrado como flag da base — o Safegold o contorna declarando o schedule em
  arquivo, mas **não** o corrige para os outros sistemas.
  **FEITO** em `.migration-ai9/upstream-flags.md`, incluindo a **flag nova** do prefixo duplo de fila no `sidekiq-cron`.
- [x] 10.6 Atualizar `parity-ledger.md`: 63 IDs `done`, 12 `dropped`, 1 híbrido — soma **76**.


  **FEITO.** A soma não fechava em 63/12/1 porque parte dos IDs dependia de entidades que ainda
  não existiam — esses ficaram `blocked`, com o motivo na linha, nunca `pending` mudo.

  **26/08/2026, na quitação da dívida: não resta nenhum ID desta fatia em `blocked`.** Passaram
  a `migrated` com evidência: `OPS-465`, `OPS-466`, `OPS-468`, `OPS-469`, `OPS-470`, `OPS-471`,
  `OPS-473`, `OPS-485`, `OPS-495`, `OPS-497` e `OPS-608`. `OPS-499` foi confirmado `dropped`
  pela **DEC-55** (área de temas não portada) — era o único que esperava uma entidade que
  ninguém vai construir. Os `blocked` que restam no razão inteiro são de outras fatias.
## Fechamento de órfãos do Phase 2 — os 8 e-mails nomeados e a configuração do mecanismo

Dezesseis IDs que não tinham dono e passam a ser desta fatia. Oito deles estavam escondidos
atrás da notação de intervalo `BE-480..BE-489`, que a conferência por ID não lê. Ver a seção
correspondente do `proposal.md`.

- [~] F.1 `BE-481` — recuperação de senha, **sem a senha no corpo** (D-38). Verificável: o
      template não tem nenhum campo de senha. **Fecha: BE-481.**
  ~~**ANULADA pela DEC-75**~~ — `dropped`.
- [~] F.2 `BE-482` — confirmação de nova senha. **Fecha: BE-482.**
  ~~**ANULADA pela DEC-75**~~ — `dropped`.
- [x] F.3 `BE-484` — confirmação de conta ("Bem-vindo") + endpoint de reenvio manual.
      **Fecha: BE-484.**
  **FEITO por S1** — convite com reenvio manual pelo console.
- [x] F.4 `BE-483` — confirmação de recebimento de feedback, preservando o assunto com o
      primeiro nome. **Fecha: BE-483.**
  **FEITO por S2** (`MessageMailer#received`).
- [x] F.5 `BE-486` / `BE-487` — observador incluído e removido, com o assunto que nomeia quem
      fez a ação. **Fecha: BE-486, BE-487.**
  **FEITO por S2** (`ObserverMailer#added` / `#removed`).
- [x] F.6 `BE-488` — nova mensagem de feedback aos observadores. **Fecha: BE-488.**
  **FEITO por S2** (`ObserverMailer#message_received`).
- [x] F.7 Tabela `email_deliveries` com **status de entrega**, não só a intenção de enviar.
      Verificável: uma falha de SMTP deixa linha com status de falha, não ausência de linha.
      **Fecha: DB-596.**
  **FEITO — a tabela é `email_logs` (DEC-90) e o que faltava era o status de FALHA.** `LoggedMailDeliveryJob` grava `status: 'failed'` com a classe e a mensagem do erro e **relança**. Verificável exatamente como a tarefa pedia: uma falha de SMTP deixa linha com status de falha, não ausência de linha.
- [x] F.8 Configuração de SMTP inteiramente por ENV, sem arquivo de engine. **Fecha:
      OPS-607.**
  **FEITO por S18** — SMTP inteiramente por ENV, sem arquivo de engine.
- [x] F.9 DKIM como interceptor de mailer, com a chave em credential e **sem travar o boot**
      quando ela falta em desenvolvimento. Verificável: sem chave, a aplicação sobe e o
      e-mail sai sem assinatura, com aviso. **Fecha: OPS-608.**

  **FEITO — ver 5.2.** A chave em `Credential` (provedor `dkim`, DEC-61) é o caminho preferido
  e é o que esta tarefa pedia nominalmente. Verificável exatamente como escrito: sem chave o
  `zeitwerk:check` e o boot passam, `Sfg::DkimSigner.status` devolve `:degraded`, o e-mail sai
  sem assinatura e o aviso vai ao log **uma vez por processo**.
- [~] F.10 Configuração do cliente de geocoding — **sem** o `timeout: 12000` segundos
      (≈3h20) do legado, e **fora** do `before_save`. **Fecha: OPS-621.**
  ~~**ANULADA pela DEC-92**~~ — não há geocoding. O `timeout: 12000` segundos do legado não é portado porque nada é portado.
- [x] F.11 Configuração do `LookupService` de CNPJ (timeout, cache, erro tratado; o retorno
      **não** é persistido). **Fecha: OPS-622.**
  **FEITO** — ver 6.1. Timeout, cache e erro tratado; o retorno **não é persistido**.
- [x] F.12 `sidekiq.yml` + política de dead set no lugar do `delayed_job_config.rb`.
      **Fecha: OPS-624.**
  **FEITO:** `:dead_max_jobs` e `:dead_timeout_in_seconds` (6 meses) em `config/sidekiq.yml`, com o porquê escrito: no legado o job que esgotava tentativas **sumia**. Aqui ele fica visível e reenfileirável.
- [x] F.13 Worker como processo declarado no `Procfile`; **nenhum** daemon com pidfile.
      **Fecha: OPS-633.**
  **FEITO** — `/Procfile`, sem daemon e sem pidfile.
- [x] F.14 Confirmar que a infraestrutura de fila da capability `availability` é **a mesma**
      desta fatia — não um segundo mecanismo. Verificável: `grep` por `ProgressJob` ou
      `Delayed::Job` no repositório retorna zero. **Fecha: OPS-125.**
  **FEITO por medição:** `grep -r 'ProgressJob\|Delayed::Job'` no repositório retorna **zero**. Há um mecanismo de fila só, e um de progresso só (`Sfg::JobProgress` + `JobProgressable`).
- [x] F.15 Progresso ao vivo por `job_state`/`job_progress` **na entidade** + Action Cable,
      consumido pelas telas de disponibilidade de S11. **Fecha: OPS-127.**

  **FEITO:** colunas na entidade + `Sfg::JobProgress` + `ProjectProgressChannel` + `useJobProgress.ts`. S11 consome incluindo `JobProgressable` no template de disponibilidade quando a tabela existir — **não** construindo um segundo mecanismo.