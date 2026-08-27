# Proposal: S13 — Jobs agendados e integrações

> Fatia **S13** da ordem de execução de `.migration-ai9/migration-map.md`.
> Bloco de origem: `.migration-ai9/map/data-infra.md` — capabilities `jobs-cron` (§2.3) e
> `integrations` (§2.4), mais duas famílias que atravessam capability e não têm outro dono
> (geolocalização e galeria polimórfica, §2.7).
> Depende de **S6** (recebíveis) e **S7** (operações de risco). Ver a ressalva de ordem em
> "Dependências" — o sub-bloco de anexos **não** depende de S6/S7 e pode ser antecipado.

## Why

Depois do trim, a base ai9 tem a **infraestrutura assíncrona inteira montada e nenhum job
de negócio**: Sidekiq + Redis, `ApplicationJob`, filas prefixadas por `APP_NAME`, Action
Cable com 3 canais e handshake por cookie httpOnly, `deliver_later` já como padrão dos
services de auth. O que falta é o que o Safegold põe em cima — e o que o legado punha em
cima estava quebrado de três formas que esta fatia desfaz:

1. **Nenhuma falha de job é vista.** Os **7 jobs** do legado (`../sfg/lib/*_job.rb`)
   capturam `rescue => e` sem relançar; em `insert_projects_on_default_user_job.rb:11-12`
   o `rescue` é **literalmente vazio** — sem log, sem trilha. A fila marca sucesso, nada é
   retentado e um usuário fica sem projeto sem deixar rastro (**D-79**). No ai9 a exceção
   volta a propagar (contrato **D-C** do mapa) e o retry/backoff/dead set do Sidekiq passa
   a ser o comportamento real.
2. **Nenhum e-mail é durável, exceto três.** O adapter in-process do legado perde tudo em
   deploy (**D-78**), e o ramo durável é inalcançável porque compara a String `"async"` com
   o Symbol `:async`. No ai9 `deliver_later` + Sidekiq já resolve; o trabalho é portar os
   **10 e-mails** e passar a registrar **status de entrega**, não só a intenção (DB-481).
3. **Nenhuma integração externa existe na base**, e as do legado são inseguras ou inertes:
   geocoding com `timeout: 12000` segundos (≈3h20) dentro do `before_save`, chave do Maps
   commitada, snippet de Universal Analytics (descontinuado em jul/2023) servindo um ID GA4
   — na prática **não coleta nada hoje**.

Há ainda um quarto achado, do orquestrador (upstream-flag **#13**), que muda o desenho de
OPS-472: **o agendamento da base ai9 não existe no código — só no Redis.** Havia 10 cron jobs
registrados, todos `source: dynamic`, e `grep` por `Sidekiq::Cron` em `backend/` dá zero
ocorrência. Consequência dos dois lados: o único cron legítimo vivo (`cleanup_login_codes`)
**some em silêncio** num Redis limpo, e os jobs apagados pelo trim continuaram agendados,
re-enfileirando classes inexistentes — **916 jobs em retry com `NameError`**. Todo cron do
Safegold nasce **declarado em arquivo**, nunca pela Web UI.

Há ainda um defeito **da própria base ai9** que esta fatia é obrigada a tratar, porque é a
dona do motor de anexos: convivem dois mecanismos (**C-04**) — ActiveStorage em
`backend/app/models/medium.rb` e gravação crua em `public/uploads` servida sem autenticação
por `assets_proxy_controller.rb`. Portar os 11 anexos do legado pelo segundo caminho
reintroduziria o **D-82**. Os achados que **não** bloqueiam viraram flags de upstream
(**F-09**, **F-10**, **F-13**); os que bloqueiam entram como tarefa aqui.

## What Changes

Seis sub-blocos, **76 IDs** (mais **16 adotados no fechamento do Phase 2** — ver a seção
correspondente no fim deste documento). A tabela por ID está em `.migration-ai9/map/data-infra.md`
§2.3 e §2.4 — aqui só a estratégia e o alvo, sem duplicar as colunas do mapa.

### A. Fila, agendamento e os 7 jobs — 23 IDs (`jobs-cron`)

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| OPS-460 | reuse | Sidekiq + Redis substitui `delayed_job` + tabela com polling por `[priority, run_at]` |
| OPS-461 | reuse | Worker como processo declarado, sem daemon manual com pidfile |
| OPS-462 | reuse | Retentativa/backoff/dead set = **default do Sidekiq**; o trabalho é não repetir o `rescue` mudo (D-79) |
| OPS-463 | build | Progresso vira `job_state`/`job_progress` **na entidade** + Action Cable (fim da gem `progress_job`) |
| OPS-464 | **drop** | `lib/runner.rb`: código morto (zero chamadas) **e** injeção de shell latente (`Open3.capture3("kill -9 #{pid}")`) |
| OPS-465 | build | `CreateGlobalTemplatesForProjectJob` — templates globais num projeto novo, com progresso item a item |
| OPS-466 | build | `InsertGlobalTemplateOnProjectsJob` — fan-out **sai da request** (coordenador + filho por projeto); corrige D-80 |
| OPS-467 | build | `InsertDefaultUserOnProjectJob` — passa a gerar trilha |
| OPS-468 | build | `InsertProjectsOnDefaultUserJob` — o `rescue` **vazio** vira erro consultável |
| OPS-469 | build | `ProjectAvailabilityTemplateActivateJob` + **timeout de bloqueio** (hoje fica `locked` para sempre) |
| OPS-470 | build | `…DeactivateJob`, mesmo padrão |
| OPS-471 | build | `…RemovalJob` **em transação** — o legado deixa remoção parcial (D-103) |
| OPS-472 | build | Agendamento em **arquivo versionado** (`config/schedule.yml` + `load_from_hash!` no boot). Não é só recriar o bloco removido em `e06be801` (**C-06**): o schedule da base **nunca esteve no código** — ver upstream-flag **#13** |
| OPS-473 | build | A varredura diária das 00:01 **não é portada**: o que depende de data vira consulta, o que depende de escrita vira evento |
| OPS-474 | adapt | `NotificationFacade` → service de notificação sobre `deliver_later` |
| OPS-475 | build | `TrackingFacade` → `Sfg::TrackingService`, os 4 momentos (request/start/success/failure) com `kind = "JOB"` |
| OPS-476 | adapt | Procfile de produção **com worker e agendador** (o legado declara só `server` e `assets`) |
| OPS-477 | **build?** | `FileToStringDecoder` — só existe se OPS-544 (contratos, S12) continuar lendo HTML de arquivo |
| OPS-478 | reuse | Falha de autenticação responde no formato da requisição (fim do `CustomFailure` que redirecionava para `root`) |
| OPS-479 | reuse | Entrega de e-mail durável (`raise_delivery_errors` + `deliver_later` já são a base) |
| FE-482 | build | Progresso de job visível, por evento; corrige `live_progress_percent` retornando 100 quando o job é nil |
| DB-460 | **drop** (tabela) + build (colunas) | `delayed_jobs` some; `job_state`/`job_progress` nascem na entidade |
| DB-461 | build | Trilha vista pelo lado dos jobs (`kind = "JOB"`), com **retenção declarada** |

### B. Motor único de anexos — 11 IDs + 6 descartes

`OPS-491` `OPS-492` `OPS-493` `OPS-494` `OPS-495` `OPS-497` `OPS-498` `OPS-499` (todos
**adapt** sobre ActiveStorage), `DB-482` (build — 11 anexos, 44 colunas Paperclip que **não**
são recriadas), `FE-484` (adapt — limites 4 arquivos / 5 MB, validados **no servidor**),
`OPS-623` fica com S1 (config) mas é consumido aqui.

**Anexo de documento usa ActiveStorage direto, nunca `Medium`** — `medium.rb:12` restringe
`media_type` a `%w[image video]` (**C-13**, decisão **D-O**).

Descartes da família "galeria polimórfica", com evidência: **OPS-496**, **BE-441**,
**BE-442**, **BE-443**, **BE-444**, **DB-432**, **DB-593** — `pictures` nunca foi usada
(nenhum model declara `has_many :pictures` e o `counter_cache` aponta para coluna
inexistente). Fica registrada a regra que sobrevive ao descarte: **limite de anexo vem de
configuração explícita (CFG-02)**, nunca de introspecção de método.

### C. E-mail — 14 IDs

`OPS-484` (adapt — falta **um** valor: `openssl_verify_mode: 'none'` → verificação ativa,
**C-05**/Q-01), `OPS-485` (build — DKIM que **não trava o boot**), `BE-480`..`BE-489`
(3 adapt + 7 build — os 10 e-mails; a **senha em texto puro sai do corpo**, D-38),
`BE-490` (**drop** — mailer sem nenhum chamador), `DB-481` (build — log com **status de
entrega**, não só intenção).

Dois defeitos que impedem envio hoje e são corrigidos junto: **BE-485** é chamado com 4
argumentos onde o método exige 5 (`ArgumentError` garantido) e faz `File.new` no avatar do
admin; **BE-489** dá acesso à conversa por `public_token` na URL (**D-82**).

### D. Integrações externas — 6 IDs

`OPS-480` + `BE-457` (build — `Sfg::ReceitaWs::LookupService`, com timeout, cache e erro
tratado; o retorno **não é persistido**, como hoje), `OPS-483` (build — catálogo BR de
UF/cidade, comparação **transliterada nos dois lados**), `OPS-486` (build — GA4 com o
snippet certo, **desligado por configuração**; ver Q-09), `OPS-489` (**drop** — login social
permanece desativado), `OPS-490` (**drop** — geração de PDF não é portada; `grep -ri pdf` no
legado retorna zero fora do Gemfile).

### E. Realtime — 4 IDs

`OPS-487` (reuse — Redis já serve fila, cable, cache e rate limiting), `OPS-488` (reuse — os
canais existem e o cliente conecta), `FE-480` (**drop** — `PollingManager` deixa de existir;
seu único consumidor já está desligado), `FE-481` (build — estado do usuário na sessão chega
por evento, **não** é ressuscitar o monitor de 1 requisição por segundo).

### F. Família geolocalização — 8 IDs, **todos `build?`, bloqueados por Q-04**

`DB-592` `DB-431` `DB-480` `OPS-481` `OPS-482` `FE-483` `BE-435` `BE-436` `BE-437` `BE-438`
`BE-439` `BE-440` — dos quais 4 (`DB-480`, `OPS-481`, `OPS-482`, `FE-483`) já estão contados
em `integrations` e 8 vêm de `data-schema`/`misc-domain`. **Nenhum vira código** antes de
`SELECT count(*) FROM geolocations` na origem. Ver "Como cada `build?` foi resolvido".

## Como cada `build?` foi resolvido — 13 dos 16 do bloco

Um `build?` que ninguém resolve vira dívida silenciosa. Cada um vira **tarefa de decisão**
com medição definida, dono e default declarado.

| ID | Dúvida | Como se resolve | Default se ninguém responder |
| -- | ------ | --------------- | ---------------------------- |
| OPS-477 | Há consumidor para o leitor de arquivo? | O único é OPS-544 (contratos, **S12**). Perguntar ao dono de S12 antes de escrever | **Não construir.** Se S12 semear HTML de arquivo, S12 escreve o leitor com limite de tamanho |
| DB-592, DB-431, DB-480, BE-435, BE-436, BE-437, BE-438, BE-439, BE-440, OPS-481, OPS-482, FE-483 | A tabela `geolocations` tem linhas? Nenhum model do legado declara `has_one/has_many :geolocation` | **Uma consulta** (tarefa 1.2) decide os 12 de uma vez | O mapa assumiu **que existe dado**. Se vier 0, os 12 viram `dropped` com a contagem como evidência — e OPS-483 (catálogo BR) **sobrevive**, porque o select encadeado não depende de geocoding |

Os outros 3 `build?` do bloco **não são desta fatia**, e agora têm dono: a ajuda de campo é
de **S12** e os dois de tema são de **S17** — os IDs estão nomeados na seção "Fronteiras"
abaixo, com o dono ao lado. (Quando este proposal foi escrito, os dois de tema apontavam
para "tematização/S2", que não era fatia nenhuma; foi assim que eles ficaram com dois donos
e nenhum trabalho.)

## Descartes com evidência — 12 IDs + 1 híbrido

Todo `drop` sai do ledger como `dropped` **com a prova na linha**, nunca por omissão.

| ID | Motivo registrado |
| -- | ----------------- |
| OPS-464 | `lib/runner.rb` — zero chamadas **e** `Open3.capture3("kill -9 #{pid}")` / `rm -rf #{path}` interpolando entrada |
| OPS-489 | Login social do legado nunca funcionou (`FACEBOOK_APP_ID = 0`, seletor `.facebook_button` inexistente); no ai9 fica desligado por flag |
| OPS-490 | Zero ocorrências de PDF fora do Gemfile (**D-84**) |
| OPS-496, BE-441, BE-442, BE-443, BE-444, DB-432, DB-593 | `pictures` nunca foi usada; `counter_cache` aponta para coluna inexistente; a checagem de dimensão testa **duas vezes a largura** e nunca a altura |
| BE-490 | Mailer, método e template existem; `grep` em `app/` e `engines/` não acha **nenhum chamador** |
| FE-480 | `PollingManager` tem **uma** instanciação (monitor de usuário da navbar) e ela **já está desligada**; a capacidade equivalente é `useCable.ts` |
| DB-460 | A **tabela** `delayed_jobs` some (Sidekiq não tem registro relacional); as **colunas** de progresso nascem na entidade. **Dono único: S13** — S14 só a cita |

## Fronteiras — o que este change **não** cobre

- **`Tracking` / `trackings` (BE-430, DB-591) e a tela da trilha (BE-432, BE-433, FE-443,
  FE-445, FE-446)** — são de `misc-domain`, fatia de navegação/transversais (**S2**).
  OPS-475 e DB-461 **consomem** o model; se ele ainda não existir quando S13 rodar, a tarefa
  3.9 cria o **mínimo** (tabela + `Sfg::TrackingService`) e S2 constrói a leitura em cima.
- **Config, segredos, CSP, `.env.example` (OPS-600..639, CFG-01, CFG-02)** — **S1**. Esta
  fatia consome `CFG-02` (limites de anexo) e `OPS-623` (magic bytes).
- **Contratos e ajuda (OPS-544, OPS-545)** — **S12**. Só o `build?` de OPS-477 aponta para lá.
- **Anexos do tema (OPS-499)** está aqui como **motor**; as 4 telas de tema são da fatia de
  tematização.
- **Renegociação, disponibilidade e recebível** — os jobs desta fatia operam sobre eles, mas
  as entidades vêm de S6/S7/S9/S11.

## Dependências

- **Depende de S6 e S7** apenas nos sub-blocos que tocam recebível e operação de risco
  (OPS-473 e o gatilho de recálculo por evento).
- **NÃO depende de S6/S7:** o sub-bloco **B (anexos)** só precisa de S1 + das entidades
  donas, e o **C (e-mail)** precisa de S1 + auth. Se S9 (renegociações, com 4 anexos) rodar
  antes de S13, o motor de anexos **tem de ser antecipado** — senão S9 improvisa um segundo
  caminho e a base fica com três. Registrado como ambiguidade de ordem no relatório.
- **Depende de S0/S2** para `Tracking` e para o menu.
- **É dependência de S14**: o ETL de arquivos (DB-482) só existe depois do motor de anexos.

## Perguntas em aberto (defaults declarados em `map/data-infra.md` §6)

| # | Pergunta | Default |
| - | -------- | ------- |
| **Q-01** | Trocar `openssl_verify_mode: 'none'` por `ENV.fetch('SMTP_OPENSSL_VERIFY_MODE','peer')`? | Troco. É 1 linha, o padrão novo é o seguro e há escape por ENV. **Adiado por decisão do usuário** — ver `improvements-log` |
| **Q-04** | `geolocations` tem linhas? | Assumo que sim e implemento; se vier 0, 12 IDs viram `dropped` |
| **Q-07** | Qual serviço de storage em produção? | Não escolho provedor. `Disk` serve para a demo, **não** para o cutover (F-13) |
| **Q-08** | "Atualização em andamento" vale para todas as entidades? | Só para as que **têm** job; os 7 widgets que leem `data-ongoing` sem emissor são bloco morto |
| **Q-09** | GA numa aplicação privada de gestão financeira? | Porto **desligado**, com o snippet correto pronto |
| **Q-11** | Teremos acesso ao disco do servidor legado? | Caminho parametrizado, exercitado contra o seed de demo; o passo real fica no runbook de S14 |

## Capabilities

### New Capabilities

Nenhuma. As duas capabilities desta fatia (`jobs-cron`, `integrations`) existem em
`openspec/specs/` desde o Phase 1 e são referenciadas **por ID**.

### Modified Capabilities

- `jobs-cron`: **um** requirement novo — expurgo programado de trilha e de log de e-mail.
  DB-461 diz "política de retenção obrigatória" e DB-481 tem o mesmo problema, mas nenhum
  requirement descreve o expurgo. São **4 linhas de trilha por execução de job**; sem
  expurgo, a tabela cresce sem limite (lacuna registrada em `map/data-infra.md` §4).
- `integrations`: **um** requirement novo — o portão de decisão da família geolocalização.
  É o que impede 12 IDs `build?` de virarem código sem a medição de Q-04.

## Impact

- **Backend:** `app/jobs/` (7 jobs + coordenador + expurgo), `config/initializers/sidekiq.rb`
  (recriar `on(:startup)`), `config/sidekiq.yml` (**toda fila nova declarada aqui, ou o job
  empilha para sempre**), `app/mailers/`, `app/services/sfg/{receita_ws,br_locations}/`,
  `app/services/notification_service.rb`, `app/services/sfg/tracking_service.rb`,
  `app/channels/`, models com `has_one_attached`/`has_many_attached`, `config/storage.yml`.
- **Dados:** colunas `job_state`/`job_progress`, `email_logs` (DB-481), anexos por
  ActiveStorage (DB-482) — **nenhuma coluna Paperclip é recriada**.
- **Frontend:** `hooks/useCable.ts` (consumo), componente de progresso sobre
  `components/ui/Progress.tsx`, upload com limites, remoção de qualquer polling.
- **Não afetado:** nada da base ai9 é refatorado (Princípio 6b). `assets_proxy_controller.rb`
  e `api/v1/uploads.rb` **continuam existindo para os outros sistemas da base**; o Safegold
  simplesmente não os usa. Achados viraram **F-09**, **F-10**, **F-13**.
- **Paridade:** 63 IDs viram código, 12 viram `dropped` com evidência, 1 é híbrido.


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

### E-mail — 8 IDs que a notação de intervalo escondeu

O sub-bloco C escreve "`BE-480`..`BE-489` — os 10 e-mails". A conferência por ID **não lê
intervalo**, e oito deles saíram como órfãos. Ficam nomeados um a um, e cada um tem tarefa:

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| BE-481 | adapt | Recuperação de senha ("Perdeu a senha?") — **a senha em texto puro sai do corpo** (D-38) |
| BE-482 | adapt | Confirmação de nova senha ("Nova senha configurada") |
| BE-483 | build | Confirmação de recebimento de feedback — assunto `"Obrigado, <primeiro nome> :)"` |
| BE-484 | build | Confirmação de conta ("Bem-vindo") + endpoint de reenvio manual |
| BE-486 | build | Você foi incluído como observador |
| BE-487 | build | Você foi removido como observador |
| BE-488 | build | Nova mensagem de feedback, aos observadores |
| DB-596 | build | `livetat_mailer_contacts` → tabela `email_deliveries`: log com **status de entrega**, não só intenção |

### Configuração que pertence a quem constrói o mecanismo — 8 IDs

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| OPS-607 | adapt | Configuração do engine de e-mail + SMTP → ENV | S13 é dona do e-mail |
| OPS-608 | build | Assinatura DKIM de todos os e-mails — interceptor de mailer, chave em credential, **sem travar o boot** | idem |
| OPS-621 | build | `geocoding.rb` (Geocoder) → configuração do cliente de geocoding | S13 é dona das integrações |
| OPS-622 | build | `receitaws.rb` → configuração do `LookupService` de CNPJ | idem |
| OPS-624 | adapt | `delayed_job_config.rb` → `sidekiq.yml` + política de dead set | S13 é dona da fila |
| OPS-633 | adapt | `bin/delayed_job` (daemon com pidfile) → processo declarado no `Procfile` | idem |
| OPS-125 | build | Infraestrutura de fila `Delayed::Job` + `ProgressJob::Base`, vista pela capability `availability` | idem — o mecanismo é daqui, os jobs de disponibilidade o consomem |
| OPS-127 | adapt | Progresso ao vivo dos jobs → `job_state`/`job_progress` na entidade + Action Cable | idem |

**`OPS-125` e `OPS-127` estavam citados nas tarefas de S11 apenas por uma notação de
intervalo, e em nenhum `proposal.md`.** Ficam aqui por **C4**: o mecanismo de fila e de progresso é
construído nesta fatia; S11 é o primeiro consumidor.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`OPS-473` é de S13**, disputado com S15. A varredura diária das 00:01 vira **consulta** e
  recálculo por evento nesta fatia; S15 apenas consome o contador resultante no dashboard.
- **`DB-460` é de S13**, disputado com S14. A tabela `delayed_jobs` **não** existe no ai9 e as
  colunas de progresso nascem na entidade — o descarte e a prova ficam aqui. S14 cita o par
  (`DB-597`, a não importação da tabela) sem reivindicar o ID.
- **`BE-379` e `BE-382` são de S17.** Quando este proposal foi escrito eles apontavam para
  "tematização/S2", que **não era fatia nenhuma** — e S14 fazia o mesmo. Resultado: dois
  donos nominais e nenhum trabalho. Agora têm dono: a fatia de temas.
- **`OPS-545` é de S12.** Esta fatia só a cita pelo `build?` de `OPS-477`.
- **`OPS-126`** (auditoria via trilha) e o model `Tracking` são de **S19**. Se S19 ainda não
  tiver rodado quando S13 rodar, esta fatia cria o **mínimo** (tabela + serviço) e S19
  constrói a leitura em cima — como já estava escrito acima.
