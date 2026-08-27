# Jobs & Cron Specification

## Purpose
Define o processamento assíncrono do ai9 para o domínio migrado do legado `sfg`: a fila, os 7 jobs de
negócio, o agendamento diário e as fachadas (`NotificationFacade`, `TrackingFacade`, `CRONFacade`).
No legado a fila é `delayed_job` sobre a tabela `delayed_jobs` do PostgreSQL, sem supervisor, sem
retentativa efetiva e sem visibilidade de falha; no ai9 é **Sidekiq + Redis** com `ApplicationJob`,
filas prefixadas por `APP_NAME` e cron por `sidekiq-cron` (ver `.migration-ai9/ai9-conventions.md`
§3.7). Progresso de job deixa de ser polling e passa a **Action Cable**.

> AMBIGUIDADE — DEC-11: a produção roda **Ruby 2.6.1 / Rails 6.0.3.2** com um **fork do `delayed_job`**
> (`github.com/livetat/delayed_job`, branch `rails-6-compatibility`), não a gem pública. O
> comportamento real de retry, backoff e marcação de falha pode divergir do que foi inventariado a
> partir da gem pública. Todo requisito abaixo que descreva retentativa ou falha da fila legada é
> **provisório** até que o fork seja lido ou o comportamento observado em produção.

## Requirements

### Requirement: OPS-460 — Backend de fila
O ai9 **MUST** substituir o backend de fila `delayed_job` + `delayed_job_active_record` (fila na tabela
`delayed_jobs` do PostgreSQL, com o worker fazendo polling por `[priority, run_at]`) por **Sidekiq
sobre Redis**, com filas nomeadas e prioridade real. Fonte legada: `Gemfile.linux:22-23`;
`engines/mailer19/db/migrate/20170505110720_create_mailer_delayed_jobs.rb:4-18`.

- No legado **nenhuma fila nomeada** é usada (a coluna `queue` é sempre nula) e a prioridade é sempre 0.
- No ai9 cada job declara `queue_as`, e a fila **MUST** estar registrada em
  `backend/config/sidekiq.yml` — fila declarada e não registrada empilha para sempre.

#### Scenario: job enfileirado sem worker disponível
- **GIVEN** nenhum worker Sidekiq em execução
- **WHEN** um job é enfileirado
- **THEN** o job permanece visível na fila com contagem de pendências observável, em vez de ficar indefinidamente numa tabela sem nenhum sinal, como no legado

#### Scenario: fila nova registrada
- **GIVEN** um job que declara uma fila ainda não listada em `sidekiq.yml`
- **WHEN** o CI roda a verificação de configuração
- **THEN** a build falha apontando a fila não registrada

> Nota: corrige D-79 (legado: fila sem visibilidade — registro fica com `job_state = "Em progresso"` para sempre se não houver worker)

### Requirement: OPS-461 — Execução do worker
O ai9 **MUST** subir o worker como processo supervisionado do deploy, com healthcheck e métricas,
substituindo o daemon manual `bin/delayed_job` (gem `daemons`), iniciado à mão com
`RAILS_ENV=... bin/delayed_job -i worker_N start` e pidfile em `tmp/pids/delayed_job.<worker>.pid`.
Fonte legada: `bin/delayed_job:1-5`; `Gemfile.linux:45`.

#### Scenario: worker morto é reiniciado
- **GIVEN** o processo do worker é encerrado inesperadamente
- **WHEN** o supervisor detecta a queda
- **THEN** o worker é reiniciado e o evento fica registrado, em vez de a fila parar silenciosamente

#### Scenario: fila observável
- **GIVEN** o ambiente em operação
- **WHEN** o operador consulta o estado do processamento assíncrono
- **THEN** há métrica de pendências, de falhas e de latência de fila disponível

> Nota: corrige D-79 (legado: worker morto deixava a fila parada sem healthcheck, métrica ou alerta)

### Requirement: OPS-462 — Política de retentativa e falha
O ai9 **MUST** usar retentativa real com falha visível: erro no job **MUST** propagar para o
runtime da fila, que retenta com backoff e, esgotadas as tentativas, registra a falha em local
consultável e notificável. Fonte legada: `config/initializers/delayed_job_config.rb:1-2`
(`max_run_time = 7.days`, `destroy_failed_jobs = false`, `max_attempts` no default 3 com backoff
`attempts**4 + 5` segundos).

- No legado, além disso, **todos** os jobs de negócio (OPS-465..471) capturam `rescue => e`
  internamente, então a fila **nunca vê o erro** e nunca retenta: a falha só aparece em `job_report` no
  próprio registro e em `Tracking`.

#### Scenario: job falha e é retentado
- **GIVEN** um job cuja execução levanta exceção
- **WHEN** a exceção ocorre
- **THEN** a exceção propaga, o job é marcado como falho e retentado com backoff, em vez de ser marcado como sucesso

#### Scenario: tentativas esgotadas
- **GIVEN** um job que falhou em todas as tentativas
- **WHEN** a última tentativa termina
- **THEN** a falha fica registrada com a mensagem de erro e é notificável, em vez de ficar apenas numa linha de tabela que ninguém consulta

#### Scenario: job travado
- **GIVEN** um job que trava durante a execução
- **WHEN** o tempo limite de execução é atingido
- **THEN** o job é liberado em minutos e não ocupa um worker por 7 dias como no legado

> Nota: corrige D-79 (legado: `rescue` interno sem relançar fazia o delayed_job marcar sucesso e nunca retentar)

### Requirement: OPS-463 — Progresso de job
O ai9 **MUST** reimplementar o contrato de progresso hoje fornecido pela gem `progress_job`
(`progress_stage`, `progress_current`, `progress_max` na tabela `delayed_jobs`) em colunas da **própria
entidade processada**, transmitindo a evolução por **Action Cable**. Fonte legada: `Gemfile.linux:46`;
`engines/mailer19/db/migrate/20170505114146_add_progress_to_mailer_delayed_jobs.rb:29-33`;
`app/models/project.rb:312-345`; `app/models/project_availability_template.rb:619-700`.

#### Scenario: progresso chega sem recarregar a tela
- **GIVEN** um projeto com job de criação de templates em andamento
- **WHEN** o job avança de etapa
- **THEN** a interface recebe a atualização por Action Cable, sem polling e sem recarga manual

#### Scenario: job morre no meio
- **GIVEN** um job interrompido com progresso parcial
- **WHEN** a entidade é consultada
- **THEN** o estado indica falha explicitamente, em vez de contadores congelados apontando para um job que não avança

> Nota: corrige D-86 (legado: progresso de job por `live_progress_percent`, que só atualizava com recarga manual)

### Requirement: OPS-464 — Orquestrador caseiro de workers descartado
O ai9 **MUST NOT** portar `lib/runner.rb` (classe `Runner`, `@@max_workers = 4`, attach/start/kill/
force_start): é código morto — grep no repositório legado mostra que a classe é definida e **nunca
chamada** — e contém injeção de shell latente (`Open3.capture3("kill -9 #{pid}")`, `rm -rf #{path}`).
Fonte legada: `lib/runner.rb:1-99`.

#### Scenario: nenhuma execução de shell para controlar workers
- **GIVEN** o backend do ai9
- **WHEN** o ciclo de vida dos workers é gerenciado
- **THEN** ele é feito pelo supervisor do deploy, sem nenhuma chamada de shell interpolando pid ou caminho

#### Scenario: descarte com evidência
- **GIVEN** a decisão de não portar o `Runner`
- **WHEN** o registro da migração é consultado
- **THEN** consta a evidência de zero chamadas à classe no legado

### Requirement: OPS-465 — CreateGlobalTemplateForProjectJob
O ai9 **MUST** portar o job que gera, dentro de um projeto recém-criado, todos os templates de
disponibilidade globais, com registro de auditoria de início e fim e falha visível. Fonte legada:
`lib/create_global_template_for_project_job.rb:1-59`; enfileirado em `app/models/project.rb:82-88`
(`after_create`) e `app/models/project.rb:738-742`; execução em `project.rb:312-345`.

- Gatilho: criação de projeto, e ação explícita de regeneração.
- Comportamento: itera os templates globais, publica progresso item a item, ordena os templates ao
  final e conclui gravando o estado na própria entidade.

#### Scenario: projeto novo recebe os templates globais
- **GIVEN** um projeto recém-criado e N templates globais ativos
- **WHEN** o job termina com sucesso
- **THEN** o projeto tem N templates correspondentes e o estado de processamento fica concluído

#### Scenario: falha é visível e retentada
- **GIVEN** o job falha na metade da geração
- **WHEN** a exceção ocorre
- **THEN** ela propaga para a fila, o job é retentado e, esgotadas as tentativas, o estado de falha aparece no projeto e na trilha de auditoria

> Nota: corrige D-79 (legado: `rescue => e` gravava `job_state = "Falhou"` sem relançar, então a fila marcava sucesso e o usuário só descobria abrindo o projeto)

### Requirement: OPS-466 — InsertGlobalTemplateOnProjectsJob
O ai9 **MUST** portar a propagação de um template global recém-criado para os projetos existentes, e
**MUST** fazer o fan-out **dentro do próprio job**, nunca dentro da requisição web. Fonte legada:
`lib/insert_global_template_on_projects_job.rb:1-59`; enfileirado em
`app/models/global_availability_template.rb:23-38` (`after_create`, quando
`should_insert_on_existing_projects?`); execução em `project.rb:349-379`.

- No legado, `Project.all.each` roda **dentro da request** e enfileira um job por projeto,
  sobrescrevendo o `job_id` de cada um — com 500 projetos, 500 jobs disparados de uma requisição.

#### Scenario: fan-out fora da requisição
- **GIVEN** um template global criado com propagação habilitada
- **WHEN** a requisição de criação responde
- **THEN** a resposta não espera a iteração sobre os projetos: um único job coordenador é enfileirado e ele distribui o trabalho

#### Scenario: falha por projeto não derruba os demais
- **GIVEN** a propagação para N projetos, com falha em um deles
- **WHEN** o processamento termina
- **THEN** os demais projetos recebem o template, o projeto com falha fica marcado e o erro é retentável individualmente

> Nota: corrige D-79 (legado: `rescue` silencioso por projeto) e D-80 (legado: o fan-out sobrescrevia `projects.job_id`, FK para a tabela da fila)

### Requirement: OPS-467 — InsertDefaultUserOnProjectJob
O ai9 **MUST** portar o job que associa a um projeto novo todos os usuários marcados como "membro
padrão", **com** registro de auditoria — que o legado não gerava para este job. Fonte legada:
`lib/insert_default_user_on_project_job.rb:1-53`; enfileirado em `app/models/project.rb:74-79`
(`after_create`); execução em `project.rb:381-390`.

#### Scenario: membros padrão associados
- **GIVEN** um projeto novo e usuários com `is_default_member` ligado
- **WHEN** o job termina
- **THEN** cada um desses usuários tem membership no projeto

#### Scenario: falha registrada na trilha
- **GIVEN** o job falha ao criar uma membership
- **WHEN** a exceção ocorre
- **THEN** a falha propaga, é retentada e fica registrada na trilha de auditoria

> Nota: corrige D-79 (legado: `rescue => e` marcava `job_state = FAILED` sem relançar e, diferente dos demais jobs, **sem gerar Tracking** — não havia trilha da falha)

### Requirement: OPS-468 — InsertProjectsOnDefaultUserJob
O ai9 **MUST** portar o job que associa todos os projetos a um usuário que passou a ser "membro
padrão", e **MUST** registrar log e trilha de auditoria em qualquer desfecho. Fonte legada:
`lib/insert_projects_on_default_user_job.rb:1-49`; enfileirado em
`app/decorators/models/user_decorator.rb:249` (`after_commit :create_memberships`); execução em
`user_decorator.rb:255-262`.

- É o pior caso de observabilidade do legado: o `rescue` do job é **vazio**
  (`lib/insert_projects_on_default_user_job.rb:11-12`) — sem log, sem `job_report`, sem `Tracking`.

#### Scenario: usuário sem acesso e sem explicação
- **GIVEN** o job falha ao criar as memberships de um usuário
- **WHEN** o usuário entra no sistema e não vê projetos
- **THEN** existe registro de erro consultável identificando o job, o usuário e a causa, em vez de nenhum rastro

#### Scenario: usuário vira membro padrão
- **GIVEN** um usuário atualizado para `is_default_member`
- **WHEN** o job termina com sucesso
- **THEN** ele tem membership de participante em todos os projetos existentes

> Nota: corrige D-79 (legado: `rescue` vazio — o erro era engolido sem log, sem `job_report` e sem `Tracking`)

### Requirement: OPS-469 — ProjectAvailabilityTemplateActivateJob
O ai9 **MUST** portar a ativação assíncrona de um template de disponibilidade, que recalcula as
entradas e mantém o item bloqueado na interface durante o processamento, com a mensagem "Esse item foi
ativado e ficará bloqueado até a conclusão da atualização das entradas". Fonte legada:
`lib/project_availability_template_activate_job.rb:1-62`; enfileirado em
`app/controllers/pub/project_availabilities_controller.rb:66-73`; execução em
`ProjectAvailabilityTemplate.background_activate`.

#### Scenario: bloqueio é liberado ao fim
- **GIVEN** um template ativado e bloqueado
- **WHEN** o job conclui
- **THEN** o bloqueio é liberado e a interface é atualizada por Action Cable

#### Scenario: fila indisponível não trava o item para sempre
- **GIVEN** o job não é processado dentro do prazo esperado
- **WHEN** o limite é atingido
- **THEN** o item sai do estado bloqueado ou expõe o motivo do bloqueio ao operador, em vez de ficar travado indefinidamente como no legado

> Nota: corrige D-79 e D-80 (legado: `rescue` sem relançar e item `locked` para sempre se o worker não estivesse rodando)

### Requirement: OPS-470 — ProjectAvailabilityTemplateDeactivateJob
O ai9 **MUST** portar a desativação assíncrona do template de disponibilidade, com recálculo das
entradas e bloqueio do item durante o processamento, com a mensagem "Esse item foi desativado…".
Fonte legada: `lib/project_availability_template_deactivate_job.rb:1-62`; enfileirado em
`app/controllers/pub/project_availabilities_controller.rb:85-92`.

#### Scenario: desativação recalcula entradas
- **GIVEN** um template ativo com entradas associadas
- **WHEN** a desativação é concluída
- **THEN** as entradas são recalculadas e o template fica inativo

#### Scenario: falha deixa rastro
- **GIVEN** a desativação falha
- **WHEN** as tentativas se esgotam
- **THEN** o estado de falha aparece no template e na trilha, e o item não permanece bloqueado sem explicação

> Nota: corrige D-79 e D-80 (legado: mesmo padrão de `rescue` silencioso e bloqueio permanente do OPS-469)

### Requirement: OPS-471 — ProjectAvailabilityTemplateRemovalJob
O ai9 **MUST** portar a remoção assíncrona de um template, dos seus templates-filhos e das entradas
correspondentes, **MUST** envolver a remoção em transação e **MUST** manter o comportamento de que o
`destroy` da interface apenas enfileira e bloqueia o item, sem apagar nada de forma síncrona. Fonte
legada: `lib/project_availability_template_removal_job.rb:1-61`; enfileirado em
`app/controllers/pub/project_availabilities_controller.rb:104-111`; execução em
`app/models/project_availability_template.rb:619-700` (inclui remoção de templates correlatos e
reordenação).

#### Scenario: remoção parcial não persiste
- **GIVEN** a remoção falha após apagar parte dos templates-filhos
- **WHEN** a exceção ocorre
- **THEN** a transação é revertida e a árvore permanece consistente, em vez de ficar parcialmente removida como no legado

#### Scenario: reordenação após remoção
- **GIVEN** uma árvore de templates com posições `1`, `1.2`, `1.2.3`
- **WHEN** um nó intermediário é removido com sucesso
- **THEN** as posições remanescentes são reordenadas de forma consistente

> Nota: corrige D-79 (legado: `rescue` sem relançar) e D-103 (legado: remoção sem transação envolvendo tudo, deixando remoção parcial)

### Requirement: OPS-472 — Agendamento declarado em um único lugar
O ai9 **MUST** declarar o agendamento em **um único lugar versionado** (`sidekiq-cron` carregado em
`config.on(:startup)`, ver `ai9-conventions.md` §3.7), eliminando o esquema do legado, em que
`config/schedule.rb` não declara nenhuma tarefa e os agendamentos reais vivem em `schedule.dev.rb` /
`schedule.prod.rb`, que precisam ser apontados manualmente no `whenever --load-file`. Fonte legada:
`config/schedule.rb:1-3`; `Gemfile.linux:35`.

#### Scenario: deploy não perde o agendamento
- **GIVEN** um deploy do ai9
- **WHEN** a aplicação sobe
- **THEN** as tarefas agendadas são carregadas da configuração versionada, sem depender de qual arquivo foi apontado na linha de comando

#### Scenario: horário em UTC com equivalente local documentado
- **GIVEN** uma tarefa que no legado rodava às 00:01 de Brasília
- **WHEN** ela é declarada no ai9
- **THEN** o horário é expresso em UTC, com o equivalente em BRT no comentário

> Nota: corrige D-54 (legado: se o deploy usasse o `schedule.rb` default, nenhum cron era instalado e o recálculo diário sumia silenciosamente)

### Requirement: OPS-473 — Contadores de renegociação sem varredura diária
O ai9 **MUST NOT** portar a varredura diária `CRONFacade.update_renegotiations_counters` das 00:01 como
está: os contadores que dependem apenas da passagem de data — em especial `overdue_installments`
(parcelas com `due_date < hoje` e `is_paid = 0`) — **MUST** ser calculados **em consulta**, e os
recálculos que dependem de escrita **MUST** ser disparados por evento (Sidekiq + Action Cable) na
renegociação afetada. Fonte legada: `config/schedule.prod.rb:4-6`, `config/schedule.dev.rb:4-6`;
`lib/cron_facade.rb:1-8`; `app/models/renegotiation.rb:83-127`.

- Campos recalculados por `update_values!` no legado: `installments_count`, `first_due_date`,
  `last_due_date`, `correct_value`, os somatórios de parcelas (`installments_main_value`,
  `installments_interest_value`, `installments_main_value_with_interest`,
  `installments_monetary_correction_value`, `installments_main_value_with_interest_cm`), `main_value`,
  `paid_value_with_interest_cm`, `pending_main_value`, `paid_percent`, `late_payment_value`,
  `paid_value`, `remaining_value`, `paid_installments`, `overdue_installments`, `due_installments`,
  `total_value_with_desagio`, `current_installment_value`, `current_value` e o `state`
  (`Sem parcela cadastrada` / `Inconsistente` / `Pago` / `Liquidado`).

#### Scenario: parcela vence hoje
- **GIVEN** uma parcela não paga que vence hoje à meia-noite
- **WHEN** a renegociação é consultada logo depois da virada do dia
- **THEN** o contador de parcelas vencidas já reflete a nova situação, sem esperar a rodada diária

#### Scenario: uma renegociação com erro não afeta as outras
- **GIVEN** uma renegociação cujo recálculo levanta exceção
- **WHEN** o recálculo roda
- **THEN** apenas essa renegociação fica marcada com erro e é retentada, enquanto as demais permanecem atualizadas

#### Scenario: edição concorrente não perde dado
- **GIVEN** um usuário editando uma renegociação enquanto o recálculo dispara para o mesmo registro
- **WHEN** as duas escritas concorrem
- **THEN** a atualização é feita sob bloqueio ou por operação atômica, sem *lost update*

> Nota: corrige D-54 (legado: o cron diário existia só para reprocessar `overdue_installments`, varria a tabela inteira com `.each` sem batching, sem lock e sem tratamento de erro — uma exceção abortava o laço e todas as renegociações posteriores ficavam desatualizadas no dia)

### Requirement: OPS-474 — NotificationFacade (porta assíncrona dos e-mails transacionais)
O ai9 **MUST** portar a fachada de notificação (`NF`) que dispara de forma assíncrona os 3 e-mails
transacionais do app base, e **MUST** garantir que **todo** e-mail — não apenas esses três — seja
durável, enfileirado em Sidekiq com retentativa. Fonte legada: `lib/notification_facade.rb:1-15`;
chamadores `app/decorators/controllers/registrations_decorator.rb:38` e
`app/decorators/facades/auth_ux19_notification_decorator.rb:8,12`.

- No legado esses 3 e-mails são os **únicos** duráveis, porque usam `Mailing.delay.<método>` sobre
  `delayed_jobs`; todos os demais caem no adapter in-process (ver OPS-479).

#### Scenario: worker parado não perde o e-mail
- **GIVEN** o worker indisponível quando um e-mail transacional é disparado
- **WHEN** o worker volta
- **THEN** o e-mail é entregue, porque ficou persistido na fila

#### Scenario: falha de envio é observável
- **GIVEN** um e-mail cujo envio falha no SMTP
- **WHEN** as tentativas se esgotam
- **THEN** a falha fica registrada e notificável, em vez de sumir sem aviso na interface

> Nota: corrige D-78 (legado: só 3 e-mails eram duráveis; os demais se perdiam em deploy/restart)

### Requirement: OPS-475 — TrackingFacade (trilha de auditoria dos jobs)
O ai9 **MUST** portar a trilha de auditoria dos jobs (`kind = "JOB"`), registrando os quatro momentos
— *request*, *start*, *success* e *failure* — para os jobs OPS-465, 466, 469, 470 e 471, e **MUST**
gravar a trilha de forma que a falha de gravação seja detectada, não engolida. Fonte legada:
`lib/tracking_facade.rb:1-296` (usa `t.save` sem `!`).

- O `resume` é texto livre em pt-BR (ex.: "A criação de templates no novo projeto #12 finalizou com
  sucesso, gerando 40 novos templates"); os typos gravados em produção
  ("A inerção do template…", `tracking_facade.rb:78,90,103,117`) **MUST** ser corrigidos nos textos
  novos, sem reescrever o histórico já gravado.

#### Scenario: quatro momentos registrados
- **GIVEN** um job de template que roda até o fim
- **WHEN** a trilha é consultada
- **THEN** existem registros de solicitação, início e conclusão, com o resumo em pt-BR

#### Scenario: falha ao gravar a trilha
- **GIVEN** um registro de trilha que não passa na validação
- **WHEN** a gravação é tentada
- **THEN** o erro é logado e visível, em vez de a auditoria se perder silenciosamente como no legado

#### Scenario: histórico legado preservado
- **GIVEN** registros de trilha migrados com os typos originais
- **WHEN** o histórico é exibido
- **THEN** o texto original é mostrado como está, sem reescrita retroativa

> Nota: corrige D-79 (legado: `t.save` sem `!` — a auditoria da falha podia ela mesma falhar em silêncio)

### Requirement: OPS-476 — Processos declarados do ambiente
O ai9 **MUST** declarar todos os processos necessários para a aplicação funcionar — servidor web,
worker da fila e agendador —, corrigindo o legado, cujo `Procfile` declara apenas `server` e `assets`,
sem worker nem cron. Fonte legada: `Procfile:1-2`; `Gemfile.linux:49`.

#### Scenario: subir o ambiente liga a fila
- **GIVEN** o ambiente iniciado pelos processos declarados
- **WHEN** um job é enfileirado
- **THEN** ele é processado, em vez de ficar pendente porque o worker não foi declarado

#### Scenario: agendador incluído
- **GIVEN** o ambiente iniciado pelos processos declarados
- **WHEN** chega o horário de uma tarefa agendada
- **THEN** a tarefa executa

> Nota: corrige D-79 (legado: rodar pelo `Procfile` deixava fila e cron desligados, com todo job pendente)

### Requirement: OPS-477 — FileToStringDecoder
O ai9 **MUST** portar a leitura de arquivo para string (abertura com `'r:bom | utf-8'`, variantes que
trocam `\n` por `<br/>` e que escapam o conteúdo) **apenas se houver consumidor**, e nesse caso
**MUST** tratar erro de arquivo inexistente e **MUST** impor limite de tamanho. Fonte legada:
`lib/file_to_string_decoder.rb:1-24`.

#### Scenario: arquivo inexistente
- **GIVEN** um caminho que não existe
- **WHEN** a leitura é solicitada
- **THEN** o erro é tratado e devolvido de forma controlada, em vez de propagar `Errno::ENOENT` sem contexto

#### Scenario: arquivo grande
- **GIVEN** um arquivo maior que o limite configurado
- **WHEN** a leitura é solicitada
- **THEN** a operação é recusada, em vez de carregar o arquivo inteiro na memória

### Requirement: OPS-478 — Falha de autenticação responde no formato da requisição
O ai9 **MUST** responder a falhas de autenticação com **401 JSON**, substituindo o `CustomFailure`
(`Devise::FailureApp`) do legado, que faz `store_location!`, seta `flash[:alert]` e **redireciona
sempre para `root_path`** — inclusive em requisições `.json`/`.js`. Fonte legada:
`lib/custom_failure.rb:1-16`.

#### Scenario: requisição de API sem sessão válida
- **GIVEN** uma chamada à API sem token válido
- **WHEN** a autenticação falha
- **THEN** a resposta é 401 com corpo JSON estruturado, e não um redirect HTML

#### Scenario: mensagem de erro estruturada
- **GIVEN** uma falha de autenticação
- **WHEN** o cliente lê a resposta
- **THEN** o corpo segue o formato de erro padrão do ai9, com código e mensagem

### Requirement: OPS-479 — Entrega de e-mail durável
O ai9 **MUST** entregar **todo** e-mail por Sidekiq com retentativa, eliminando as duas causas
independentes de perda do legado: (a) `config/application.rb:106` atribui a **String** `"async"` a
`smtp_settings.delivering`, que o código compara com o **Symbol** `:async`
(`engines/mailer19/lib/livetat/mailer19/grind_mailer.rb:17,37,57,77,95`;
`engines/feedback19/app/decorators/grind_mailer_decorator.rb:29,68`) — a comparação é sempre falsa e o
ramo `Mailing.delay.…` **nunca executa**; (b) `config.active_job.queue_adapter` está **comentado** em
`config/environments/production.rb:32-34`, então o Rails usa o adapter `:async`, uma fila em memória
no próprio processo.

#### Scenario: deploy no meio de uma fila de e-mails
- **GIVEN** e-mails de feedback, convite e observador pendentes
- **WHEN** o processo da aplicação é reiniciado por um deploy
- **THEN** todos continuam pendentes na fila persistente e são entregues depois, em vez de se perderem com o processo

#### Scenario: modo de entrega comparado corretamente
- **GIVEN** a configuração de modo de entrega vinda do ambiente como string
- **WHEN** o código decide como entregar
- **THEN** a comparação normaliza o valor e o caminho assíncrono é de fato tomado

#### Scenario: e-mail com falha é retentado
- **GIVEN** um envio que falha por indisponibilidade temporária do SMTP
- **WHEN** a fila reprocessa
- **THEN** o e-mail é entregue numa tentativa posterior e a falha final, se houver, fica registrada

> Nota: corrige D-78 (legado: `"async"` String comparada com `:async` Symbol tornava o ramo `.delay` inalcançável e quase todo e-mail se perdia em deploy/restart)

### Requirement: FE-482 — Progresso de job visível ao usuário
O ai9 **MUST** entregar o progresso de um job em andamento **por evento de Action Cable** (canal da
entidade processada, ver OPS-488), atualizando a interface sem recarga, e **MUST** preservar o mesmo
conteúdo informativo do legado: sinalização de "atualização em andamento" na lista e no detalhe da
entidade, com o percentual concluído. Fonte legada:
`app/views/pub/console/parts/projects/list/_widget.html.erb:1,10-19`;
`app/views/pub/console/parts/projects/detail/_body.html.erb:12-15`;
`app/models/project.rb:145-147,672-684`.

- Comportamento legado: `has_ongoing_job?` é `!job_id.blank?`; `live_progress_percent` é
  `progress_current / progress_max * 100` arredondado em 2 casas, retornando **100 quando `job` é nil**
  e **0 quando `progress_max == 0`**. Na lista, ícone `zmdi-alarm` vermelho abre um dropdown com
  "Existe uma atualização em andamento sobre os dados financeiros da projeto: **<X>%**"; no detalhe,
  subtítulo vermelho "Atualização em andamento", sem percentual.
- O percentual legado é renderizado no servidor e **nunca se atualiza sozinho** — não há polling nem
  websocket; o usuário precisa recarregar ou renavegar para ver o número mudar.
- No ai9 o progresso **MUST** vir das colunas de progresso da própria entidade processada (ver DB-460
  e DB-597), nunca de uma linha da tabela da fila.

#### Scenario: progresso avança com a tela aberta
- **GIVEN** um projeto com job de template em execução e a tela de lista aberta
- **WHEN** o job avança de 20% para 60%
- **THEN** o indicador passa a mostrar 60% por evento no canal, sem recarga e sem nenhum `setInterval` consultando a API

#### Scenario: job termina
- **GIVEN** a mesma tela aberta durante a execução
- **WHEN** o job conclui
- **THEN** o indicador de "atualização em andamento" desaparece por evento, e a entidade volta ao estado normal

#### Scenario: entidade sem job em andamento
- **GIVEN** uma entidade sem job associado
- **WHEN** a lista é renderizada
- **THEN** nenhum indicador de progresso é exibido, em vez de exibir 100% como o legado faz quando `job` é nil

> Nota: corrige D-86 (legado: progresso renderizado no servidor, sem polling e sem websocket — o número só mudava com recarga manual da página)

> AMBIGUIDADE: no legado apenas `Project` implementa `has_ongoing_job?`. Os widgets de receivables,
> renegotiations, risk_operations, structured_operations, companies, availability_templates e
> project_guarantees leem `w.data("ongoing")` (`.../list/_widget.js.erb:10`), mas o atributo
> `data-ongoing` **não é emitido** nesses HTMLs — o bloco é morto e o alerta nunca aparece. Parece
> intenção não concluída. Confirmar com o usuário se o aviso de "atualização em andamento" deve valer
> para as demais entidades no ai9.

### Requirement: DB-460 — Fila e progresso saem da tabela `delayed_jobs`
O ai9 **MUST NOT** portar a tabela `delayed_jobs` como esquema, e **MUST** substituir o par
(fila relacional + progresso na linha da fila) por **Sidekiq/Redis** para a fila e por **colunas de
progresso na própria entidade processada** para o progresso. Fonte legada:
`engines/mailer19/db/migrate/20170505110720_create_mailer_delayed_jobs.rb:4-18`;
`engines/mailer19/db/migrate/20170505114146_add_progress_to_mailer_delayed_jobs.rb:29-33`. O contrato
de colunas está registrado em DB-597 (`openspec/specs/data-schema/spec.md`) e não é repetido aqui.

- Colunas legadas de fila: `priority` int d0, `attempts` int d0, `handler` text (YAML do objeto job),
  `last_error` text, `run_at`, `locked_at`, `failed_at`, `locked_by`, `queue`; índice
  `delayed_jobs_priority` em `[priority, run_at]`.
- Colunas legadas de progresso: `progress_stage`, `progress_current` int d0, `progress_max` int d0 —
  é delas que sai o `live_progress_percent` de FE-482.
- `projects.job_id` e `project_availability_templates.job_id` são **FKs para a tabela da fila**
  (`belongs_to :job, class_name: Delayed::Job.name` em `app/models/project.rb:4` e
  `app/models/project_availability_template.rb:7`). No ai9 esse acoplamento **MUST** desaparecer: o
  Sidekiq não tem registro relacional, então o estado (`job_state`, `job_progress`) vive na entidade.
- Jobs pendentes no cutover **MUST NOT** ser importados: o `handler` é YAML de classes Rails 6.

#### Scenario: entidade referencia execução, não linha de fila
- **GIVEN** o esquema do ai9
- **WHEN** as colunas de projeto e de template de disponibilidade são inspecionadas
- **THEN** nenhuma delas é FK para a tabela da fila, e o estado de processamento é coluna própria da entidade

#### Scenario: fila com trabalho pendente no cutover
- **GIVEN** linhas em `delayed_jobs` pendentes ou com `failed_at` preenchido no momento da migração
- **WHEN** o ETL roda
- **THEN** elas são reportadas como trabalho não concluído para reprocessamento manual, e nenhum `handler` YAML é desserializado

#### Scenario: jobs falhos não se acumulam
- **GIVEN** o legado com `destroy_failed_jobs = false`, que guarda toda falha na própria tabela da fila
- **WHEN** o ai9 opera
- **THEN** falhas ficam na dead set do Sidekiq com política de retenção declarada, em vez de crescerem sem limite numa tabela de negócio

### Requirement: DB-461 — Trilha de auditoria de jobs e ações (`trackings`)
O ai9 **MUST** preservar a trilha de auditoria que o legado grava em `trackings` — inclusive os
registros de `kind = "JOB"` escritos pelas fachadas de job (ver OPS-475) — e **MUST** armazená-la com
campos estruturados em vez de uma frase montada em `string`. Fonte legada:
`db/migrate/20180724162731_create_trackings.rb:3-18`; escrita por `lib/tracking_facade.rb`. O contrato
de colunas está registrado em DB-591 (`openspec/specs/data-schema/spec.md`).

- Colunas legadas: `user_id`, `target_id`, `trackable_type`/`trackable_id`, `resume` string,
  `type` string (STI), `target_group_id`/`target_group_type`, `trackable_parent_id`/
  `trackable_parent_type`, `kind` string, timestamps. Polimorfismo duplo (`trackable` +
  `trackable_parent`) e **nenhum índice declarado na migration**.
- `resume` é `string` (limite 255 no PostgreSQL) e recebe frases montadas como
  `"… falhou com o erro: #{e}"` — mensagens de erro longas são truncadas ou fazem o insert falhar,
  ou seja, **a auditoria da falha pode se perder exatamente quando mais importa**.
- No ai9: `resume` **MUST** ser `text`, e o evento **MUST** ser gravado em campos estruturados
  (evento, entidade, payload JSON), com índices nas colunas polimórficas e em `kind`.
- Volume: 4 registros por execução de job; a tabela cresce com o uso e **MUST** ter política de
  retenção declarada.

#### Scenario: job falha com mensagem de erro longa
- **GIVEN** um job que levanta uma exceção com mensagem e backtrace extensos
- **WHEN** a trilha é gravada
- **THEN** o erro completo fica registrado em campo `text`, em vez de ser truncado ou derrubar o insert

#### Scenario: consulta da trilha de um objeto
- **GIVEN** milhares de eventos gravados
- **WHEN** a trilha de um objeto específico é consultada
- **THEN** a consulta usa índice sobre as colunas polimórficas, em vez de varrer a tabela inteira

#### Scenario: eventos de job distinguíveis
- **GIVEN** eventos de ação de usuário e eventos de execução de job na mesma tabela
- **WHEN** a trilha é filtrada por origem
- **THEN** os eventos de job são selecionados por `kind` indexado, preservando a semântica de `kind = "JOB"` do legado
