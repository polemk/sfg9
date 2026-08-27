# Design: S13 — jobs, anexos, e-mail e integrações sobre a infra do ai9

> O mapa item-a-item **não é duplicado aqui**. Fonte:
> `.migration-ai9/map/data-infra.md` §2.3 (`jobs-cron`, 23 linhas) e §2.4 (`integrations`,
> 38 linhas), mais §2.7 para a família de geolocalização e de galeria polimórfica.
> Decisões transversais: §3 (D-C, D-D, D-O, D-P), lacunas: §4, perguntas: §6, flags: §7.

## Context

A base ai9 pós-trim tem **toda a infra assíncrona** e **nenhum job de negócio**. Medido, não
suposto (§0 do mapa, correção **C-06**): a gem `sidekiq-cron` está em `backend/Gemfile:38`,
mas o bloco `Sidekiq.configure_server { config.on(:startup) … }` foi **removido inteiro** no
commit `e06be801` e não há `:cron:` em `sidekiq.yml`. Não existe schedule nenhum: OPS-472 é
**construção**, não configuração.

O legado, por sua vez, tem 7 jobs em `../sfg/lib/*_job.rb` sobre `ProgressJob::Base` +
`delayed_job`, uma única entrada de cron (`config/schedule.prod.rb`, `CRONFacade
.update_renegotiations_counters` às 00:01) e duas fachadas (`notification_facade.rb`,
`tracking_facade.rb`, 9,2 KB).

## Goals / Non-Goals

**Goals**
- Que **toda falha de job seja vista**: exceção propaga, Sidekiq retenta, o estado de falha
  aparece na entidade e na trilha.
- **Um** motor de anexos no Safegold: ActiveStorage privado, URL assinada com prazo, validação
  por conteúdo real.
- **Um** catálogo de e-mails, todos duráveis, todos com status de entrega registrado.
- Nenhuma tela do Safegold consultando a API em intervalo fixo (Princípio 10).

**Non-Goals**
- **Não** refatorar a base ai9 (Princípio 6b): `assets_proxy_controller.rb`,
  `api/v1/uploads.rb`, `db/seeds.rb` e `credentials_by_environment.rb` continuam como estão,
  para os outros sistemas da base. Viraram **F-09**, **F-10**, **F-11**, **F-12**.
- **Não** escolher provedor de storage de produção (Q-07 é decisão de infraestrutura).
- **Não** ressuscitar o monitor de usuário de 1 s do legado (FE-481 é evento, não polling).

## Decisions

### D0. O agendamento nasce em **arquivo versionado** — e o Redis é compartilhado

Achado do orquestrador em 25/08/2026, registrado como item **13** de
`.migration-ai9/upstream-flags.md`, e que **muda o desenho de OPS-472**.

**O agendamento da base ai9 não existe no código — só no Redis.**
`grep -rI "Sidekiq::Cron\|sidekiq_cron\|cleanup_login_codes"` em `backend/` inteiro dá
**zero ocorrência**, e ainda assim havia **10 cron jobs registrados**, todos com
`source: dynamic` — cadastrados em runtime (Web UI do Sidekiq ou um `runner` avulso) e
persistidos apenas em chaves `cron_job:*`.

Os dois lados do mesmo defeito:

- **Some sem avisar.** O único cron vivo e legítimo da base (`cleanup_login_codes` →
  `CleanupLoginCodesJob`, que existe em `backend/app/jobs/`) só roda porque uma chave
  sobrevive no Redis. **Redis limpo, deploy novo ou ambiente novo = o cron não existe**,
  em silêncio, sem nada no repositório denunciando a falta.
- **Não some quando devia.** O trim do Phase 1b apagou os jobs do código e as definições
  ficaram no Redis re-enfileirando classes inexistentes a cada 5 minutos: **916 jobs em
  retry com `NameError`** (`DriveIngestionJob`, `PublishScheduledDraftsJob`,
  `BlogIntakeSessionExpiryJob`, `KickoffNoShowJob`, `AgendaBriefingJob`). Já limpo pelo
  orquestrador. **Código apagado não desagenda nada, porque o agendamento nunca esteve no
  código.**

Decisão para o Safegold: **todo cron nasce declarado em arquivo versionado**
(`config/schedule.yml`, carregado no boot via `Sidekiq::Cron::Job.load_from_hash!`, que
**também remove o que não está declarado**). **Nenhum cron desta migração pode ser
cadastrado pela Web UI.** Isso fecha o ciclo "apagou a classe, o cron ficou" — que é o
mesmo defeito de manutenção que o **D-54** do legado tinha por outro caminho (schedule real
morando num arquivo que precisava ser apontado à mão no `whenever --load-file`).

**Consequência que precisa estar na mesma tarefa:** como `load_from_hash!` **remove** o não
declarado, o `cleanup_login_codes` da base **tem de estar declarado no arquivo**, senão a
correção mata o único cron legítimo que existe hoje. Isto **não é refatorar a base**
(Princípio 6b): é declarar, no arquivo que passa a ser a fonte, um agendamento que já
deveria estar lá. A flag de upstream continua aberta para a base decidir o resto.

**Armadilha do Redis compartilhado.** Este Redis é usado também pelo app **`apl9`**
(`cron_job:apl9:data_cleanup`, e um `cron_job:default:data_cleanup` apontando para a fila
`apl9_default`). As **filas** da ai9 são prefixadas por `APP_NAME` (`ai9_default`,
`ai9_mailers`, `ai9_webhooks`, `ai9_transcriptions`, `ai9_low_priority`), mas o **namespace
de cron não é** — e é aí que mora o risco. **`FLUSHDB`, ou qualquer limpeza que não filtre
por fila, derruba o cron do outro app.** Toda operação de limpeza desta fatia enumera
`cron_job:*`, filtra pela fila do Safegold e remove **nominalmente**.

### D1. Job: a exceção propaga. Inclusive contra o exemplo da convenção

`ai9-conventions.md` §3.7 traz como exemplo canônico um job que faz
`rescue StandardError => e; Rails.logger.error(...)` **sem `raise`** — exatamente o
antipadrão que produziu o **D-79** no legado. Os jobs do Safegold **não seguem esse
exemplo**: `rescue` em job só existe para enriquecer o log e **sempre termina em `raise`**.

Isto está escrito aqui, e não só na tarefa, porque é a decisão que alguém "conserta" de volta
por analogia com o resto do repositório. Registrado em `upstream-flags.md` como divergência
consciente do exemplo da convenção, não como refatoração da base.

### D2. Progresso vive na entidade, não numa tabela de fila

O legado guarda `progress_stage`/`progress_current`/`progress_max` na linha de `delayed_jobs`
e `projects.job_id` é FK para essa tabela. Sidekiq **não tem registro relacional**, então
esse acoplamento não pode sobreviver (DB-460): `job_state` e `job_progress` passam a ser
colunas de `projects` e `availability_templates`, e a evolução chega por Action Cable
(OPS-463, FE-482).

Consequência que o runbook de S14 precisa saber: **jobs pendentes no cutover não são
importados**; o que estiver em voo no legado é reexecutado ou descartado explicitamente.

### D3. Fan-out sai da requisição (OPS-466)

No legado, `Project.all.each` roda **dentro do request** e enfileira um job por projeto,
sobrescrevendo o `job_id` de cada um (**D-80**): com 500 projetos, 500 jobs de uma
requisição e um único ponteiro sobrevivente. No ai9 a request enfileira **um coordenador**;
o coordenador enfileira os filhos; **falha em um projeto não derruba os outros** e cada
filho tem estado próprio.

Este é o job que mais depende do contrato **D-D**: ele cruza projetos **de propósito**.
Escopo por projeto é aplicado **no endpoint** (`current_project!`), nunca por `default_scope`
— um `default_scope` quebraria OPS-466/467/468 em silêncio. Vale o mesmo para os seeds.

### D4. A varredura diária das 00:01 não é portada como varredura (OPS-473)

Decisão **D-B** do mapa. O `CRONFacade.update_renegotiations_counters` varre a tabela
inteira, sem batching, sem lock e sem tratamento de erro — **uma exceção aborta o laço** e
todas as renegociações seguintes ficam desatualizadas naquele dia.

Separação:
- **Depende só da passagem de data** (`overdue_installments`: `due_date < hoje AND is_paid =
  0`, `due_installments`, `current_installment_value`) → **consulta**, calculada na leitura.
  Efeito colateral desejado: uma parcela que vence à meia-noite já aparece vencida no
  primeiro acesso, sem esperar a rodada.
- **Depende de escrita** (os somatórios de `update_values!`) → **recálculo por evento** na
  renegociação afetada, disparado pelo mesmo service que grava (contrato **C2**).

O cron continua existindo (OPS-472), mas para o expurgo de retenção — não para recalcular
o mundo todo por precaução.

### D5. Anexos: ActiveStorage privado, e `Medium` fica de fora

Três medições governam este sub-bloco:
- **C-04** — o ai9 tem **dois** caminhos de arquivo; o segundo (`public/uploads` +
  `assets_proxy_controller`) é o mesmo defeito **D-82** do legado. O Safegold usa **só**
  ActiveStorage.
- **C-13** — `medium.rb:12` restringe `media_type` a `%w[image video]`. Anexo de renegociação
  é **documento**. Portanto `has_many_attached` direto (decisão **D-O**), sem tocar num model
  compartilhado.
- **§4** — falta storage privado com URL assinada de prazo curto e falta validação por magic
  bytes; `active_storage_validations` está no `Gemfile:8` **e não é usada em nenhum model**.

Alvo por entidade: `User#avatar` (3 MB), `Project#avatar` (5 MB), `Provider#logo` (1 MB),
`Carrier#logo` (1 MB), `AppTheme` (4 anexos, 5 MB), `Renegotiation#files` (**4 arquivos ×
5 MB, validados no servidor**, limites vindos de CFG-02). Os derivados e as qualidades JPEG
do legado estão linha a linha em §2.4 — não os repito.

**As 44 colunas Paperclip (4 por anexo × 11 anexos) não são recriadas.** O ETL copia o
arquivo e reanexa (DB-482); registro cujo arquivo não exista no disco de origem é **contado
no dry-run de S14**, não silenciado.

### D6. E-mail: a infra já é durável; o trabalho é o catálogo e o status

`production.rb:69` já tem `raise_delivery_errors = true`, `application.rb:38` já usa Sidekiq
como `queue_adapter`, e os services de auth já fazem `deliver_later`. Portanto OPS-479 é
`reuse` de verdade — as duas causas de perda do legado (a String `"async"` comparada com o
Symbol `:async`, e o adapter in-process) simplesmente não existem aqui.

O que se constrói: os 10 mailers, o interceptor de **DKIM** (que **falha de forma
diagnosticável, nunca no boot** — o legado faz `open(...)` no `before_initialize` e derruba
a aplicação se o arquivo sumir) e o **log de e-mails com status de entrega** (DB-481) —
o legado registra só a *intenção*, e nada distingue entregue de perdido.

Duas correções de segurança entram no mesmo lote: **a senha em texto puro sai do corpo**
(D-38, e por DEC-14 o produto nem tem senha) e o `public_token` na URL da conversa de
feedback deixa de dar acesso a quem tiver o link (D-82, BE-489).

### D7. Integrações externas: cliente HTTP com timeout curto, cache e falha que degrada

Não há nenhum service de integração na base — só as gems (`faraday`, `httparty`). O padrão
nasce aqui, em `backend/app/services/sfg/<provedor>/`, seguindo §3.6:

- **ReceitaWS** (OPS-480, BE-457): timeout 10 s, cache 365 dias, token em ENV. **O retorno
  alimenta a tela e não é persistido** — é o comportamento atual (o preenchimento de
  `cnaes`/`atividades` está comentado no legado). Token ausente → integração responde
  *indisponível* e **o app sobe**.
- **Catálogo BR** (OPS-483): dado empacotado + `/api/v1/br_locations`, no formato de
  `countries.rb` (que é **forma, não dado** — C-10). Comparação **transliterada nos dois
  lados**: o legado compara por igualdade exata e devolve `nil` em qualquer variação de
  acento, quebrando em silêncio.
- **GA4** (OPS-486): snippet compatível com o ID, **desligado por configuração** (Q-09).
  Script bloqueado não pode quebrar nada.

### D8. Realtime: reuso puro, e o fim do polling é barato

Medição do §0.4 do mapa de risco e do achado #2 do `migration-map.md`: o legado tem **uma**
instanciação de `PollingManager`, no monitor de usuário da navbar, **já desligada**. Então
"converter polling para Action Cable" é **um item pequeno** (FE-480 é `drop`, FE-481 é
`build`), não um tema de migração. O Princípio 10 continua valendo para tudo que
construirmos: nenhum componente novo consulta a API em intervalo fixo.

Canais novos seguem `ai9-conventions.md` §3.8: autorização **no `subscribed`** com `reject`,
payload sempre com `type:`, token pelo cookie httpOnly `cable_token` — **nunca na URL**.

### D9. Geolocalização é um portão, não um plano

12 IDs dependem de **uma** consulta. A tabela `geolocations` existe no legado, mas **nenhum
model declara `has_one/has_many :geolocation`** e não há referência a `geolocatable` fora do
próprio model. O mapa assumiu que há dado e marcou os 12 como `build?`.

O portão (tarefa 1.2) é `SELECT count(*) FROM geolocations` na origem, com o número
registrado em `decisions.md`. Se for 0, os 12 viram `dropped` com a contagem como prova. Se
for > 0, entram com três correções obrigatórias: geocoding **fora do `before_save`** (job),
`timeout` em **segundos** (o legado usa 12000 s ≈ 3h20, prendendo thread do Puma),
`street_number` **string** (int perde "123-A" e "S/N" — decisão **D-V**, e o dry-run de S14
lista o que já foi truncado na origem).

**OPS-483 não está no portão**: o select encadeado País→Estado→Cidade é útil com ou sem
geocoding.

### D10. Trilha: dependência declarada, não construção duplicada

`Sfg::TrackingService` (OPS-475) grava os **quatro momentos** (request/start/success/failure)
para OPS-465, 466, 469, 470, 471, com `kind = "JOB"`. O model `Tracking` e a tabela
`trackings` são de **S2** (BE-430/DB-591, decisão **D-P**: constrói-se `Tracking` próprio;
`paper_trail` **não** é ativado nesta migração).

Se S2 ainda não tiver entregue quando S13 rodar, a tarefa 3.9 cria o **mínimo** (tabela +
service de escrita) e S2 constrói a leitura em cima. O que **não** pode acontecer é os dois
construírem — é o risco do contrato **C4**, aplicado a outra peça.

Detalhe que o legado erra e não se replica: `t.save` sem `!` — a auditoria da própria falha
pode falhar em silêncio. E job sem usuário grava autor nulo num model que **exige** autor,
então a gravação falha sem ninguém saber: no ai9, operação disparada por rotina grava com
**autoria de sistema** explícita.

### D11. Retenção é parte do desenho, não uma limpeza futura

São **4 registros de trilha por execução de job**, mais uma linha por e-mail enviado. Sem
expurgo, as duas tabelas crescem sem limite — e a base ai9 não tem nenhum padrão de expurgo
(o único que existia, `PurgeDiscardedDraftsJob`, saiu no trim). Daí o **único requirement
novo** de `jobs-cron` nesta fatia: job agendado de expurgo, prazo configurável, contagem do
que foi removido no log.

## Risks / Trade-offs

| Risco | Mitigação |
| ----- | --------- |
| **Cron cadastrado pela Web UI** — vira agendamento que não existe no repositório e sobrevive à remoção da classe (upstream-flag #13: 916 jobs em retry com `NameError`) | `config/schedule.yml` versionado + `load_from_hash!` no boot (que remove o não declarado). Portão na tarefa 3.1c: nenhuma classe agendada pode ser inexistente |
| **`load_from_hash!` apagando o `cleanup_login_codes` da base** — é o único cron legítimo vivo hoje, e ele só existe no Redis | Declará-lo no `schedule.yml` **na mesma tarefa** que introduz o carregamento (tarefa 3.1b) |
| **Limpeza de Redis derrubando o cron do app `apl9`** — o Redis é compartilhado e o namespace de cron **não** é prefixado | Nunca `FLUSHDB`. Enumerar `cron_job:*`, filtrar pela fila do Safegold e remover nominalmente |
| **Fila nova sem declaração em `sidekiq.yml`** — o job empilha para sempre. Está escrito em comentário no próprio arquivo, com histórico ("mesmo defeito ja consertado no brsw e no facil") | Usar as filas existentes (`<APP_NAME>_default`, `_mailers`). Fila nova só com necessidade **e** com a linha no `sidekiq.yml` na **mesma** tarefa |
| **`db:migrate` re-dumpando o `schema.rb`** — já aconteceu (+485 linhas, revertidas). O `schema.rb` foi editado à mão no Phase 1b, sem migration de `drop` | Toda tarefa de dados desta fatia termina em `git diff backend/db/schema.rb` **lido**, não só rodado. Procedimento completo em `map/data-infra.md` §5 e no runbook de S14 |
| **Anexo desaparecendo entre deploys** — `storage.yml` só tem `Disk` e `production.rb:10` usa `:local` (**F-13**) | Não escolho provedor (Q-07). `Disk` com volume para a demo; o cutover exige decisão do usuário, e isso está no runbook |
| **Endurecer validação de upload recusa arquivo que hoje passa** nos outros sistemas da base (F-09) | A validação por magic bytes é aplicada **nos models do Safegold**, não em `Medium` nem no `uploads.rb` compartilhado |
| **DKIM travando o boot** se a chave sumir — é o defeito do legado | Chave lida sob demanda; ausência marca o envio como **degradado** e o app sobe |
| **12 IDs bloqueados por Q-04 paralisando a fatia** | O portão é uma consulta, e é a **tarefa 1.2**. Os outros 5 sub-blocos não dependem dele |
