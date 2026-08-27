# Tasks: S9 — Renegociações: parcelas, pagamentos, anexos

Fila de trabalho do Phase 3. Ordenada **por camada**: dados → backend → frontend → testes →
paridade. Uma tarefa só é marcada quando o comportamento existe, roda e tem teste passando —
e o ID vira `implemented` em `.migration-ai9/parity-ledger.md`.

**Regras desta fila:**

- **Uma tarefa = um comportamento verificável.** Cada tarefa cita os IDs que fecha.
- **Toda tarefa de endpoint que aceita id por parâmetro** (`renegotiation_id`,
  `renegotiation_installment_id`, `renegotiation_payment_id`, `attachment_id`) carrega o
  sub-item `⛔ cross-project`: um id de **outro projeto** é rejeitado, e a resposta é
  idêntica à de um id inexistente (C1; família D-01/D-16/D-29/D-76/D-100).
- **DEC-02 / D-104:** a aritmética em float é **replicada**, não corrigida. Melhoria
  **declinada** pelo usuário (`.migration-ai9/improvements-log.md`). Isso inclui o
  truncamento da 3ª casa na máscara de entrada, a assimetria
  `pending_main_value` × `remaining_value`, e o VP que sobrescreve
  `current_installment_value`.
- **Golden test por agregado** (§4.1–4.11): valores extraídos do legado
  (`app/models/renegotiation.rb:89-183`, `renegotiation_installment.rb:59-69`,
  `renegotiation_payment.rb:11-14`), que **não tem nenhum teste** (D-114).
- **Polling é proibido** (Princípio 10): atualização de card é Action Cable.

**Portões:** `cd backend && bundle exec rspec` sem falha nova ·
`cd frontend && node node_modules/typescript/bin/tsc --noEmit` — **0 erro**.

**Pré-requisitos:** S0 (`current_project!`, `Membership`, papéis) e S4 (projeto, empresas,
**fornecedores**). Os primitivos compartilhados de S6 são reusados; se S9 rodar primeiro,
nascem aqui (tarefas 3.1–3.3 marcadas como *compartilhado*).

---

## 1. Dados — schema, índices e configuração

- [x] 1.1 Migration `create_renegotiations`: cadastro + os ~20 agregados, `id: :uuid`,
  `kind` e `state` com **domínio fechado** (enum string + check constraint, D-B9), `comment:`
  nas colunas. Corrige **D-103** (nenhuma migration de renegociação do legado tem índice ou
  FK) — **DB-190**
- [x] 1.2 FKs de `renegotiations` para `projects`, `providers` e `companies` — **DB-190,
  DB-198 (parte)**
- [x] 1.3 Dinheiro em **`decimal(15,2)`**, percentuais e taxas em float, divergindo
  conscientemente do `decimal(14,2)` da convenção §4 (D-B4). A cadeia truncamento na entrada
  → float no cálculo → arredondamento na gravação é **replicada** (DEC-02) — **DB-196**
- [x] 1.4 Migration `create_renegotiation_installments` com **índice único**
  `(renegotiation_id, due_date)` e índices por renegociação, vencimento e `is_paid`;
  `comment:` documentando que `saldo` é negativo e `pending_value` é positivo — **DB-191**
- [x] 1.5 Migration `create_renegotiation_payments` com índices por parcela e por
  renegociação, e **coerência renegociação × parcela garantida no banco** (corrige D-52 na
  raiz) — **DB-192**
- [x] 1.6 Migration `create_renegotiation_attachments` sobre ActiveStorage
  (`active_storage_attachments`/`_blobs` já no `schema.rb`), com metadados preservados e
  binários no **armazenamento privado** — **DB-193**
- [x] 1.7 `attachments_count` `null: false, default: 0`, preenchido na carga e sempre
  coerente (o nulo do legado fazia `nil > 0` → `NoMethodError`) — **DB-195**
- [x] 1.8 Coluna `has_safegold_management` — carimbo copiado na criação, **nunca
  ressincronizado**, sem consumidor (D-30, Q-B32) — **DB-197**
- [x] 1.9 Migrations de índice das consultas quentes; a listagem deixa de ser quadrática em
  número de consultas — **DB-198**
- [x] 1.10 Configuração `MAX_FILES_PER_RENEGOTIATION = 4` e `MAX_FILE_SIZE = 5.megabytes`
  em config/ENV, com os **mesmos valores padrão** das constantes Ruby de `SFG::Metadata` —
  ajustáveis **sem deploy** (`improvements-log.md`) — **BE-226 (parte de config), OPS-194**

## 2. Backend — agregados, serviços, endpoints, anexos e realtime

### 2a. Agregados (C2 / D-B3)

- [x] 2.1 `services/renegotiations/aggregate_service.rb`: `.recalculate!` (persiste, em
  transação, **levantando** em falha) e `.preview` (não persiste). Uma consulta agregada,
  uma gravação, um broadcast. **Nunca `save` sem bang** — corrige **D-79** (o legado pulava
  registro em silêncio) — **BE-195, C2**
- [x] 2.2 `#general_values` — recalcula **de verdade** e devolve os 7 valores +
  `unposted_value` + a flag de "remover todas"; 404 para renegociação inexistente. Corrige
  **D-48** (o hash era montado e **descartado**; a resposta era o JSON cru) — **BE-195**
  - ⛔ cross-project: `renegotiation_id` de outro projeto é recusado
- [x] 2.3 Somas de principal, juros e correção monetária; `main_value` derivado
  (`renegotiation.rb:95-100`) — **BE-204**
- [x] 2.4 `paid_value_with_interest_cm`, `late_payment_value`, `pending_main_value` e
  `paid_value` (`:101-105`). **A assimetria é preservada:** `pending_main_value` pode ficar
  **negativo**, enquanto `remaining_value` tem piso em zero (Q-B22) — **BE-205**
- [x] 2.5 `paid_percent` sem divisão por zero, aceitando > 100% (`:103`). A mora fica **fora
  do numerador** e a dívida contratada **fora do denominador** — replicado (DEC-02) —
  **BE-206**
- [x] 2.6 `remaining_value`, `paid_installments`, `overdue_installments` e
  `due_installments`, com as **vencidas calculadas na consulta** (`:107-110`). Corrige
  **D-54** (era fotografia do último `update_values!`, até 24 h desatualizada, dependente do
  cron). `due_installments` **continua incluindo** as vencidas (Q-B23) — **BE-207, OPS-190**
- [x] 2.7 `installments_count`, `first/last_due_date`, `total_value_with_desagio` e
  `correct_value` (`:90-93`, `:113`). **`correct_value = total_debt` sempre** —
  `interest_rate_correction` e `grace_period` continuam sem uso (D-47, Q-B24). Deságio maior
  que o original é aceito — **BE-208**
- [x] 2.8 `#state` — os 4 estados derivados numa única expressão. Corrige **D-45** (a linha
  do estado "Inconsistente" era sobrescrita pela seguinte em `:118-123`, e o filtro da tela
  **nunca** retornava nada) — **BE-209**
- [x] 2.9 `unposted_value` e `installment_status` (`:140-155`) — **BE-210**
- [x] 2.10 Parcela do mês (**inclui a já paga**) e próxima parcela em aberto (**vencidas
  nunca são "próxima"**), em consulta agregada (`:157-173`). Corrige N+2 consultas por linha
  da listagem **sem alterar o número** — **BE-211**
- [x] 2.11 `#current_value` — VP da dívida pela taxa acordada, float e arredondamento final
  replicados (`:175-183`). **O VP sobrescreve `current_installment_value`** — replicado
  (D-46, Q-B25); é um número que o cliente lê — **BE-212**
- [x] 2.12 `services/renegotiations/recalculate_installment.rb` — mora, total, pago, saldo,
  `is_paid` (`renegotiation_installment.rb:59-69`). **A mora entra dos dois lados da conta**
  — replicado (DEC-02); consequência: pagar só a mora pode quitar a parcela (Q-B26) —
  **BE-219**
- [x] 2.13 Cascata **explícita e transacional**: renumera pagamentos → recalcula parcela →
  propaga para a renegociação; falha é **revertida e reportada**. Substitui o `after_save`
  de `renegotiation_payment.rb:16-22` que rodava em duplicidade — **BE-220**
- [x] 2.14 `services/renegotiations/renumber_installments.rb` e `renumber_payments.rb` com
  `update_all`, **sem callbacks** (evita recursão de recálculo); só o ordinal muda —
  **BE-203, OPS-195**

### 2b. Model e serviços de escrita

- [x] 2.15 `models/renegotiation.rb`: `provider_name` e `title` derivados do fornecedor,
  `correct_value = total_debt`, `integration_key` **única** (homônimos colidiam em silêncio),
  carimbo do projeto. Valores zerados/negativos continuam aceitos (Q-B21) — **BE-199**
- [x] 2.16 `models/renegotiation_installment.rb`: principal **> 0**, **índice único**
  `(renegotiation_id, due_date)`, mês e ano acompanhando a data. Corrige **D-12** (unicidade
  só no AR, sujeita a corrida) — **BE-218**
- [x] 2.17 `services/renegotiations/create_service.rb` — recalcula os agregados **na
  criação**. Corrige o registro que nascia com tudo zerado e `state = "Inconsistente"`; a
  mensagem distingue criação de atualização — **BE-198**
- [x] 2.18 `services/renegotiations/update_service.rb` — recalcula e persiste; **edição
  inválida não muta agregado** (o legado recalculava mesmo após falha de validação) —
  **BE-200**
- [x] 2.19 `services/renegotiations/create_installment.rb` — uma parcela por data; falha
  **não** dispara recálculo nem renumeração — **BE-215**
- [x] 2.20 `services/renegotiations/create_installments_batch.rb` — N parcelas, intervalo em
  Dias/Semanas/Meses, ajuste de fim de mês; intervalo 0 → 422; período desconhecido → 422.
  Duplicatas **dentro do próprio lote** deixam de falhar em silêncio com resposta de sucesso
  — **BE-216**
- [x] 2.21 Derivações da parcela + identidade e cor do lote; parcela inválida é
  **reportada** (corrige **D-52** e o `create` cujo retorno era ignorado) — **BE-217**
- [x] 2.22 `services/renegotiations/batch_color.rb` — cor distinta por lote **com terminação
  garantida** (o laço de rejeição do legado é potencialmente infinito quando o espaço de
  cores esgota) — **OPS-196**
- [x] 2.23 `services/renegotiations/batch_destroy_installments.rb` — lote inteiro **numa
  transação**; lote vazio **não** é sucesso. Corrige **D-51**: remoção parcial reportada
  como falha total fazia o usuário reexecutar e apagar parcelas a mais (perda de dado) —
  **BE-202**
  - ⛔ cross-project: ids de parcela de **outra renegociação** (ou de outro projeto) são
    recusados e **nada é apagado**
- [x] 2.24 `services/renegotiations/create_payment.rb` — `days_late` e `total_paid_value`
  (`renegotiation_payment.rb:11-14`); **teto no pendente da parcela**; mora negativa
  recusada; renegociação divergente da parcela recusada. **Sem imputação automática**: o
  pagamento vai só para a parcela escolhida. Corrige as três faces do **D-52** —
  ⚠️ *muda o que hoje é aceito e pode barrar lançamento que o operador fazia* — **BE-223**

### 2c. Endpoints

- [x] 2.25 `api/v1/renegotiations.rb#search`: escopo por projeto validado **no servidor**;
  a busca cobre **`title` e `provider_name`** (o legado só casava fornecedor apesar de
  "Nome" ser a 1ª coluna). Corrige o vazamento por `renegotiation_id` — **BE-190**
  - ⛔ cross-project: `renegotiation_id` de outro projeto não expõe nada
- [x] 2.26 Filtro por estado com `params values:` incluindo **`empty`**. Corrige **D-49**
  (o `case` sem `when "empty"` abortava a action e a tela dava 500); junto com 2.8, "Sem
  parcela cadastrada" e "Inconsistente" passam a **funcionar** — **BE-191**
- [x] 2.27 Filtro por tipo (Financeiro / Operacional / Tributario / Trabalhista) —
  **BE-192**
- [x] 2.28 Ordenação acumulada por `title` e `provider_name`; chave desconhecida **ignorada**
  (corrige o `nil + " "` → `NoMethodError`) — **BE-193**
- [x] 2.29 Paginação real com `l`/`o` aplicados de fato, padrão 20. Corrige **D-20** (o
  `where!` descartava a relação nova) — **BE-194**
- [x] 2.30 `api/entities/renegotiation.rb` com `installment_status` derivado e opções de
  serialização respeitadas — substitui o `to_json` sobrescrito que quebrava a assinatura e
  levantava `ArgumentError` — **BE-196**
- [x] 2.31 `#create/#update` sobre os serviços 2.17/2.18, com `params do…end` declarativo —
  **BE-198, BE-200**
  - ⛔ cross-project: editar renegociação de outro projeto é recusado
- [x] 2.32 `#destroy` — só sem parcelas e sem pagamentos; anexos vão junto. Corrige **D-24**
  (`errors.any? ? :ok : :ok` + template de retorno **vazio**: a tela mostrava sucesso e o
  registro voltava) — **BE-201**
  - ⛔ cross-project: excluir renegociação de outro projeto é recusado e nada é apagado
- [x] 2.33 `api/v1/renegotiation_installments.rb#search` — ordenadas por vencimento, com os
  pagamentos; **paginação funciona**; renegociação inexistente → 404. Corrige **D-20**
  (`l`/`o` calculados e ignorados) — **BE-213**
  - ⛔ cross-project: listar parcelas de renegociação de outro projeto é recusado
- [x] 2.34 `#create` de parcela — data ausente → **422** (não 500); repetições não numéricas
  → 422. Corrige o `to_i` que virava 0 e respondia 200 "criada com sucesso" **sem criar
  nada** — **BE-214**
- [x] 2.35 `#update/#destroy` de parcela — edição recalcula e renumera; exclusão barrada por
  pagamento; aumento **reabre** parcela quitada — **BE-221**
  - ⛔ cross-project: parcela de outra renegociação/projeto é recusada
- [x] 2.36 `api/v1/renegotiation_payments.rb#search` — ordem determinística e paginação
  (corrige **D-20**: sem `ORDER BY`, a ordem dependia do banco). A edição **não** pode mudar
  a parcela pela URL — **BE-222**
  - ⛔ cross-project: pagamento de outro projeto é recusado
- [x] 2.37 `#update/#destroy` de pagamento — recalcula **uma vez** (o legado fazia `update` +
  `save` redundante e disparava a cascata em duplicidade); a exclusão **reabre** a parcela —
  **BE-224**
  - ⛔ cross-project: excluir pagamento de outro projeto é recusado

### 2d. Anexos (D-82 / D-B7)

- [x] 2.38 `models/renegotiation_attachment.rb` com `has_one_attached :file` e serviço de
  armazenamento **privado**; `services/renegotiations/attachment_service.rb` aplicando os
  limites **no servidor** (4 arquivos, 5 MB, da config de 1.10). Corrige **D-50** (a
  checagem do legado lia `.lesson_attachment_content_wrapper`, seletor **de outro produto**,
  comparando com `NaN`). **`Medium` não é reusado**: `medium.rb:12` só aceita
  `image`/`video` — **BE-226, OPS-192**
- [x] 2.39 Validação de tipo **pelo conteúdo real** (Marcel, transitivo do ActiveStorage),
  com allowlist. Corrige **D-82** (`do_not_validate_attachment_file_type` + spoof detector
  monkey-patchado para `false`) — **OPS-194**
- [x] 2.40 `#download` — **autorizado por projeto**, nome original preservado,
  `Content-Disposition: attachment` **sempre**, arquivo ausente → 404 legível. Modelo:
  `api/v1/downloads.rb:17-40`. **`AssetsProxyController` NÃO é reusado** (serve
  `public/uploads/**` inline e sem auth — é literalmente o D-82) — **BE-227**
  - ⛔ cross-project: baixar anexo de renegociação de outro projeto é recusado; posse da URL
    **não** é autorização
- [x] 2.41 `#search` de anexos — lista com título, formato e autor; filtro e limite
  aplicados. Corrige a rota que **nunca funcionou** (`la:` vs `ra` → `NameError`) e **D-20**
  — **BE-225**
- [x] 2.42 `#destroy` de anexo — **só o autor**, checado no servidor; contador decrementado;
  registro sem arquivo é removido normalmente. Corrige **D-82** (a regra de dono era só
  visual) — **BE-229**
  - ⛔ cross-project: anexo de outro projeto é recusado antes mesmo da checagem de autoria
- [x] 2.43 Dimensões de imagem vindas de `blob.metadata` persistido; **nenhum processo
  externo por render**; falha marca **só aquela** imagem. Corrige as 2 chamadas de processo
  externo por imagem a cada renderização, que derrubavam o detalhe com 500 — **OPS-193**

### 2e. Realtime e agendamento

- [x] 2.44 `channels/renegotiation_channel.rb` com autorização no `subscribed`; broadcast
  **no fim da transação** de qualquer alteração de parcela/pagamento. **Polling é proibido**
  (Princípio 10, D-B5) — **FE-207 (backend)**
- [x] 2.45 `sidekiq-cron` — **uma** definição versionada, com retry, alerta e **trava de
  concorrência**, substituindo o crontab por host sem trava (dois hosts = processamento em
  duplicidade) e os 3 arquivos de agendamento do legado. O cron diário de vencidas **não é
  recriado** (D-B6/OPS-190) — **OPS-191**

## 3. Frontend

### 3a. Primitivos compartilhados

- [x] 3.1 *(compartilhado — reusar de S6 se já existir)* `EmptyState`, `ErrorState`,
  `SortableTableHeader`, `Pagination`, `RowActionsMenu`, `ConfirmDialog`,
  `useDebouncedValue`, `usePermission`, `DatePicker`, `MoneyInput`, `DecimalInput`,
  `lib/format/money.ts` — **FE-191, FE-192, FE-193, FE-194, FE-195, FE-198, FE-201, FE-202,
  FE-203, FE-228**
- [x] 3.2 `components/ui/FileDropzone.tsx` (**novo compartilhado**) — arrastar e soltar +
  seletor múltiplo, com os limites aplicados e comunicados. Base: `ThumbnailPicker.tsx` —
  **FE-210**
- [x] 3.3 Máscaras: o **truncamento da 3ª casa** (`1,239` → `1,23`) é **preservado de
  propósito** — é o primeiro passo da cadeia de arredondamento que produz os totais atuais
  (DEC-02). Campo vazio vira `0,00` — **FE-201**

### 3b. Lista e cadastro

- [x] 3.4 `app/pages/renegotiations/RenegotiationsPage.tsx` — 13 colunas de resumo; "Data
  próxima" vazia mostra `-` — **FE-190**
- [x] 3.5 Os 4 estados do container (carregando / vazio / erro / conteúdo). Corrige o
  `failure` **vazio** do proxy legado, que deixava a tela no último estado, sem mensagem —
  **FE-191**
- [x] 3.6 Busca com debounce de 300 ms casando **nome e fornecedor**; filtros de estado e
  tipo ocultos até "Filtros", com "Sem parcela cadastrada" e "Inconsistente" **funcionando**
  (D-49, D-45) — **FE-192, FE-193**
- [x] 3.7 Ordenação acumulada (asc → desc → neutro) e paginação padrão 50, com botões
  desabilitados nos extremos (D-20) — **FE-194, FE-195**
- [x] 3.8 `components/renegotiations/RenegotiationRow.tsx` — a linha abre o detalhe; remover
  só sem parcelas; confirmação exibindo o **erro real do servidor** (corrige D-24, em que o
  usuário via sucesso e o registro voltava). Q-B28 registrada: o legado usa `provider_name`
  na rota e `title` na lista — **FE-196, FE-198**
- [x] 3.9 Guarda de fornecedor e botão que some para somente-leitura; escrita suprimida na
  tela **e recusada no servidor** (corrige D-17) — **FE-197, FE-228**
- [x] 3.10 `app/pages/renegotiations/RenegotiationFormPage.tsx` — 13 campos, título "Editar
  {fornecedor}". `grace_period` e `interest_rate_correction` continuam **fora da tela**
  (D-47, Q-B24) — **FE-199**
- [x] 3.11 Sem fornecedor / sem empresa → explicação + atalho para cadastrar — **FE-200**
- [x] 3.12 Erros com nome do campo em pt-BR e mensagem de **criação** distinta da de edição
  (corrige "foi atualizada com sucesso" aparecendo na criação) — **FE-203**

### 3c. Detalhe, parcelas e pagamentos

- [x] 3.13 `app/pages/renegotiations/RenegotiationDetailPage.tsx` — abas GERAL/PREVISÕES com
  **deep-link e histórico reais**. Corrige **D-92** (o estado de navegação vivia só em
  memória JS e o Voltar saía do console) — **FE-204**
- [x] 3.14 `components/renegotiations/RegistrationCard.tsx` — 13 campos somente leitura,
  vazio mostra `-` — **FE-205**
- [x] 3.15 `components/renegotiations/SummaryCards.tsx` — 4 cards de resumo financeiro;
  Status mostra `-` antes da resposta — **FE-206**
- [x] 3.16 `hooks/useRenegotiationChannel.ts` — cards atualizam **por Action Cable** após
  qualquer alteração de parcela ou pagamento. Campo ausente na resposta **não interrompe os
  demais** (o legado lançava `TypeError` e parava tudo); falha é sinalizada. **Sem polling**
  — **FE-207**
- [x] 3.17 `components/renegotiations/InstallmentsTab.tsx` — 12 colunas; barra de ações some
  para somente-leitura; valores em reais e datas `dd/mm/aaaa`; estados de carga, vazio e
  **erro** (a lista de parcelas do legado não tinha tratamento de erro) — **FE-213, FE-214**
- [x] 3.18 `components/renegotiations/InstallmentRow.tsx` — pagamentos aninhados
  expandem/recolhem sobre `ui/accordion.tsx`; clique ignorado no modo seleção; parcela com
  pagamento **não** recebe caixa de seleção (com tooltip explicando) — **FE-215, FE-219**
- [x] 3.19 Menu de linha: gerar pagamento / editar / remover (remover só sem pagamento) —
  **FE-216**
- [x] 3.20 Modo seleção: "Selecionar todos" pega **só as sem pagamento**; rótulo "REMOVER N
  PARCELAS" — **FE-217**
- [x] 3.21 Nada selecionado → aviso; **a confirmação não expira** (o legado descartava em
  6 s a confirmação de uma operação irreversível) — **FE-218**
- [x] 3.22 `components/renegotiations/InstallmentDrawer.tsx` — 3 modos (única / lote /
  edição), repetições com mínimo 1 — **FE-220**
- [x] 3.23 `hooks/useInstallmentPreview.ts` — os totais derivados vêm **do servidor**
  (`AggregateService.preview`). Corrige **D-09** na renegociação: a regra financeira deixa de
  existir em dois lugares — **FE-221, C2**
- [x] 3.24 Salvar só com principal > 0 **e** o servidor respondendo 422 pelo mesmo motivo
  (corrige D-52: o servidor tinha a validação, mas o erro era engolido e a resposta era 200)
  — **FE-222**
- [x] 3.25 Fecha em sucesso restaurando o endereço; falha mantém o painel aberto com os
  valores digitados — **FE-223**
- [x] 3.26 `components/renegotiations/PaymentDrawer.tsx` — seletor de previsão com
  nº/vencimento/pendente e **data do pagamento editável** (D-B12: o campo travado em "hoje"
  tornava o cálculo de `days_late` inútil; pagamento retroativo passa a ser possível) —
  **FE-224**
- [x] 3.27 Pago Total calculado; salvar bloqueado com zero **e** com valor acima do pendente
  (corrige D-52: não havia checagem em camada nenhuma; o pendente era só rótulo do seletor)
  — **FE-225**
- [x] 3.28 Painel **fecha** após salvar, com lista e cards atualizados. Corrige o `TypeError`
  causado pela aba de pagamentos comentada (D-53) e a mensagem que dizia "A previsão foi
  criada" — **FE-226**
- [x] 3.29 Editar/excluir pagamento pela sublinha, com o endereço refletindo o pagamento
  aberto. Corrige a URL que ficava literalmente com `{pid}` e o título de confirmação
  "Excluir previsão" — **FE-227**

### 3d. Anexos

- [x] 3.30 `components/renegotiations/FilesSection.tsx` — contagem no título, vazio
  explicado, **limite comunicado de verdade**. Corrige **D-50** (o indicador de bloqueio era
  escrito no HTML e nunca lido pelo JS) — **FE-209**
- [x] 3.31 `components/renegotiations/AttachmentGallery.tsx` — miniaturas **de variante**,
  não do arquivo original; imagem indisponível vira marcador em vez de derrubar a tela —
  **FE-208**
- [x] 3.32 Ação de excluir visível **só para o autor** — e o servidor recusa (D-82) —
  **FE-211**
- [x] 3.33 Download pelo endereço **autorizado**; tipo não visualizável vem como download
  (D-82) — **FE-212**

## 4. Testes

### 4a. Golden test por agregado (D-B3 / D-114)

Valores extraídos do legado. Cada tarefa cobre o caso nominal, o ramo de guarda e um caso
negativo/extremo.

- [x] 4.1 Golden: somas de principal, juros e CM; `main_value`
  (`renegotiation.rb:95-100`) — **BE-204**
- [x] 4.2 Golden: `paid_value_with_interest_cm`, `late_payment_value`, `paid_value` e
  `pending_main_value` — incluindo o caso em que `pending_main_value` fica **negativo**
  enquanto `remaining_value` fica em **zero** (Q-B22) (`:101-107`) — **BE-205**
- [x] 4.3 Golden: `paid_percent` — divisão por zero devolve 0; resultado acima de 100% é
  aceito (`:103`) — **BE-206**
- [x] 4.4 Golden: `remaining_value`, `paid/overdue/due_installments`, com as vencidas vindas
  da **consulta** e `due_installments` **incluindo** as vencidas (Q-B23) (`:107-110`) —
  **BE-207, OPS-190**
- [x] 4.5 Golden: `installments_count`, `first/last_due_date`, `total_value_with_desagio` e
  `correct_value = total_debt` **sempre** (Q-B24) (`:90-93`, `:113`) — **BE-208**
- [x] 4.6 Golden: os 4 estados — inclusive "Inconsistente" e "Sem parcela cadastrada", que
  no legado eram inalcançáveis (D-45/D-49) (`:118-123`) — **BE-209**
- [x] 4.7 Golden: `unposted_value` e `installment_status` (`:140-155`) — **BE-210**
- [x] 4.8 Golden: parcela do mês (**inclui a paga**) e próxima parcela em aberto (**vencida
  nunca é "próxima"**) (`:157-173`) — **BE-211**
- [x] 4.9 Golden: `current_value` (VP) — e o exemplo que **prova** que
  `current_installment_value` é sobrescrito pelo VP quando há juros > 0 e saldo em aberto
  (D-46, Q-B25) (`:175-183`) — **BE-212**
- [x] 4.10 Golden: recálculo da parcela — mora, total, pago, saldo, `is_paid`. Inclui o caso
  em que **pagar só a mora quita a parcela**, porque a mora entra dos dois lados (Q-B26)
  (`renegotiation_installment.rb:59-69`) — **BE-219**
- [x] 4.11 Golden: `days_late` e `total_paid_value` do pagamento, inclusive pagamento
  **retroativo** e pagamento em dia (`renegotiation_payment.rb:11-14`) — **BE-223**

### 4b. Contratos transversais

- [x] 4.12 **Teste de fonte única (C2/D-09):** o drawer de parcela e o de pagamento não
  recalculam nada localmente; os derivados exibidos vêm da resposta do servidor —
  **FE-221, FE-225**
- [x] 4.13 **Teste de que a prévia e a gravação passam pelo mesmo serviço (C2):** mesmo
  rascunho de parcela enviado ao endpoint de prévia e ao de criação produz derivados
  **idênticos, campo a campo** — **BE-217, FE-221**
- [x] 4.14 **Suíte cross-project (C1):** um exemplo por endpoint que aceita id por
  parâmetro — renegociação (search/show/update/destroy/general_values), parcela
  (search/create/update/destroy/batch_destroy), pagamento (search/create/update/destroy) e
  anexo (search/download/destroy) — provando recusa e **resposta idêntica** à de id
  inexistente. Prova junto que nenhum model do domínio declara `default_scope` —
  **D-01/D-16/D-29/D-76/D-100**
- [x] 4.15 **Teste de coerência de pai:** parcela de **outra** renegociação é recusada no
  lote de exclusão e no pagamento — na aplicação **e** no banco — **BE-202, BE-223, DB-192**
- [x] 4.16 **Teste de perda de dado (D-51):** exclusão em lote com um id inválido no meio
  **não apaga nada** e reporta o motivo; nenhuma reexecução apaga parcela a mais — **BE-202**
- [x] 4.17 **Teste de exclusão honesta (D-24):** `destroy` de renegociação com parcelas
  responde **erro** com o motivo, e o registro continua existindo — **BE-201**
- [x] 4.18 **Teste de cascata única:** criar, editar e excluir pagamento dispara o recálculo
  **exatamente uma vez** por operação, e a falha é **revertida** — **BE-220, BE-224**
- [x] 4.19 **Teste de paginação e ordenação reais (D-20)** nas cinco listagens
  (renegociações, parcelas, pagamentos, anexos, resumo): `l`/`o` respeitados,
  `X-Total-Count` correto, ordem determinística — **BE-194, BE-213, BE-222, BE-225**
- [x] 4.20 **Teste de segurança de anexo (D-82)** — cinco asserções numa suíte só:
  (a) download **sem** permissão é recusado; (b) `Content-Disposition` é sempre
  `attachment`; (c) o arquivo **não** é alcançável por caminho direto em `public/`;
  (d) arquivo `.svg`/`.html` renomeado para `.pdf` é rejeitado pela verificação **de
  conteúdo**; (e) só o autor exclui, checado no servidor — **BE-226, BE-227, BE-229,
  OPS-192, OPS-194**
- [x] 4.21 **Teste dos limites de anexo:** o 5º arquivo é recusado **no servidor**, e um
  arquivo de 5 MB + 1 byte é recusado; alterar a configuração muda o limite **sem deploy** —
  **BE-226, OPS-194**
- [x] 4.22 **Teste de autorização no servidor:** `user_is_readonly` não cria, não edita e não
  exclui nada do domínio — mesmo chamando a API direto (D-17) — **FE-228**
- [x] 4.23 **Teste do canal (D-B5):** alterar parcela ou pagamento emite **um** broadcast no
  fim da transação; assinante de outro projeto **não** recebe; **nenhum** `setInterval` de
  polling existe na área (Princípio 10) — **FE-207**
- [x] 4.24 Vitest: `useInstallmentPreview` não recalcula localmente; `ConfirmDialog` de
  remoção em lote **não** se autodescarta; `FileDropzone` comunica o limite antes do upload
  — **FE-221, FE-218, FE-210**

## 5. Paridade — auditoria, carga e ledger

- [x] 5.1 `scripts/etl/renegotiations/audit.rb` — **auditoria ANTES da carga** e gate dela:
  pagamentos com renegociação divergente da parcela, vencimentos duplicados na mesma
  renegociação, contadores errados, estados incoerentes. Corrige **D-103** — **DB-199**
- [x] 5.2 Mapeamento de carga com a **semântica nova** das três colunas renomeadas em
  29/04/2022: `total_value` → `installments_main_value`, `installments.value` →
  `main_value`, `payments.value` → `installment_paid_value_with_interest_cm`. O valor da
  parcela passa a ser **só o principal** (Q-B31) — **DB-194**
- [x] 5.3 Migração dos binários de anexo: cada arquivo é copiado de `public/system/…` e
  **reanexado** via ActiveStorage, com o tipo revalidado pelo conteúdo; **todo registro cujo
  arquivo não existe mais no disco é reportado**, em vez de virar anexo quebrado em silêncio.
  ~~⚠️ **Dependência externa**~~ — **o acervo chegou em 26/08/2026**
  (`sfg-31-may-25.tar`, 42,3 MB, 467 arquivos), lido **em fluxo** por `SYSTEM_TAR=`, sem
  extrair nada para o disco. Executado contra o acervo real: **44 anexos no banco, 44 no
  acervo, 43 religados, 39.424.330 bytes**, tipo vindo dos **magic bytes** (0 fora da
  allowlist do catálogo), cada religação provada por tamanho **e** SHA-256, e a segunda
  passada não cria um segundo blob. O 44º é o achado da execução:
  `#45 ANEXO_INSTRUMENTO_DE_GARANTIA.pdf` tem **0 byte no acervo e 0 no banco** (o Paperclip
  gravou `inode/x-empty` em 2022) — fica **sem binário e nomeado**, porque carimbá-lo pela
  extensão daria um download de 0 byte com cara de PDF válido. Documento financeiro sem
  binário deixa o relatório **vermelho** (`:abort`). Trava:
  `spec/lib/sfg/etl/production_dump_spec.rb` — *"os 44 anexos"* — **DB-193**
- [x] 5.4 `attachments_count` preenchido e conferido na carga — **DB-195**.
  **Conferido nos dois lados.** Na ORIGEM, `Sfg::Etl::Parity::Renegotiations` mediu o dump de
  produção: das 169 renegociações, **134 têm o contador NULO** (é o `nil > 0` que derrubava o
  detalhe com `NoMethodError`) e **0 estão fora do real** — 44 anexos em 35 renegociações.
  No ai9 a coluna é `null: false, default: 0`, então o NULO vira 0, que é o número certo para
  quem não tem anexo. No DESTINO, a etapa `counters` de `fixups.rb` reconcilia contador ×
  `COUNT(*)` das linhas de fato migradas e reporta cada divergência antes de corrigir
- [x] 5.5 `scripts/etl/renegotiations/fixups.rb` — empresa padrão para projeto sem empresa,
  recálculo geral **em lotes** com `find_each`, renumeração de pagamentos. Substitui as
  rotinas do legado que re-salvavam tudo sem particionamento, carregando a base em memória —
  **OPS-197**.
  Entregue como `Sfg::Etl::Fixups::Renegotiations` (`rake sfg_etl:renegotiation_fixups`), com
  o ponto de entrada nomeado em `scripts/etl/renegotiations/fixups.rb`: a rotina precisa dos
  serviços do ai9 (C2 — não pode haver uma segunda definição das mesmas contas) e de estar
  numa suíte. Quatro etapas — `company`, `renumber`, `recalculate`, `counters` —, **uma**
  transação e **um** recálculo de agregado por renegociação (o legado reentrava na cascata
  uma vez por parcela, BE-220), **ensaio por padrão** que grava e reverte para reconciliar de
  verdade, e retomada por pulo (quem já está coerente não é regravado) mais `AFTER=<uuid>`.
  **Desvio declarado:** `fix_renegotiations_without_company` do legado terminava com
  `p.renegotiations.update_all(company_id:)` **sem condição**, reescrevendo a empresa CERTA
  das demais — aqui só o que está errado é tocado (exceção (1) do DEC-30).
  Trava: `spec/lib/sfg/etl/renegotiation_fixups_spec.rb`, 11 exemplos que **estragam o dado
  de propósito** e provam o conserto, a idempotência (2ª passada em zero), o ensaio que não
  grava e a leitura em lotes (contagem de SELECTs, não leitura do código)
- [x] 5.6 Preservar os **bloqueios de exclusão** do legado (renegociação ↔ parcela ↔
  pagamento, projeto, fornecedor): `restrict_with_error`, não soft delete — **DB-199**
- [x] 5.7 Verificação de paridade numérica: amostra de renegociações do legado × ai9, nos
  ~20 agregados. **Divergência de precisão não é regressão** — DEC-02/D-104 é melhoria
  **declinada** (`improvements-log.md`). O que **é** regressão: um agregado que mudou de
  fórmula, um estado que mudou de valor, um total que mudou de sinal.
  **Fechada com o dump de produção como ORÁCULO** (26/08/2026):
  `Sfg::Etl::Parity::Renegotiations` (`rake sfg_etl:renegotiation_parity SOURCE=dump DUMP=…`)
  rodou a **população inteira** — 169 renegociações, 5.124 parcelas, 1.230 pagamentos —
  medindo **47.170 comparações · 47.162 iguais · 0 de precisão · 0 REGRESSÕES**, e
  **8 mudanças de estado declaradas** (D-45, `Pago` → `Inconsistente`: #65, #136, #137, #140,
  #163, #178, #180, #202). Nada é escrito no banco: a DEC-102 adiou a **carga**, não a
  **conferência**. Trava: `spec/lib/sfg/etl/renegotiation_parity_spec.rb` (7 exemplos do
  classificador + 1 contra o artefato real via `SFG_DUMP=`)
- [x] 5.8 Fechar o ledger: os 98 IDs em `implemented` → `verified`; os 3 `dropped` (BE-197
  rotas mortas, BE-228 renomear anexo, FE-229 aba comentada) com **evidência escrita** —
  **`.migration-ai9/parity-ledger.md`**.
  **Fechado com a régua escrita antes da promoção** (seção *"S9 — renegociações: o razão
  fechado"* no razão). Os números da tarefa estavam defasados: são **102 IDs — 11 `verified`,
  89 `migrated`, 2 `dropped`**, porque **BE-228 deixou de ser `dropped`** quando a DEC-53
  mandou consertar o "renomear anexo".
  A régua: **`verified` = a saída foi comparada com o DADO DE PRODUÇÃO e bateu** — nada menos.
  Promover os 89 restantes só porque a suíte está verde seria carimbar; portão verde prova que
  o código carrega, não que ele produz o número do legado. Os 11 são os que ganharam oráculo
  em 26/08/2026: 9 pelas 47.170 comparações contra o dump (BE-204..209, BE-212, BE-219,
  BE-223), 1 pela religação dos binários contra o acervo (DB-193) e 1 pelo contador conferido
  nos dois lados (DB-195). **BE-210 e BE-211 ficaram de fora de propósito**: são derivados de
  leitura que o legado nunca persistiu — não há coluna em produção para comparar, e meia prova
  não é prova.
  Os 2 `dropped` receberam a evidência **na própria linha**, com arquivo e linha do legado:
  BE-197 (6 actions renderizando template que não existe em disco — conferidos os 6, 6 de 6
  ausentes; acessá-las é `ActionView::MissingTemplate` → 500) e FE-229 (aba PAGAMENTOS
  comentada com `<%#=` e fora da barra de abas; "excluir todas as parcelas" dentro de
  comentário HTML, com JS procurando um seletor que casa com zero elementos e um
  `show_remove_all_option` no controller alimentando esse no-op — **e nenhuma rota ou action**
  para "remover todas", então não existe backend dele a portar).
  O `verified` dos outros 89 exige a carga rodada contra o destino: **Phase 4, adiada pela
  DEC-102, dono = o usuário**, que decide a data
- [x] 5.9 Transcrever para `.migration-ai9/upstream-flags.md`: **F-1** (`AssetsProxyController`
  serve `public/uploads/**` inline, sem auth — **não mexer**, é usado por outros sistemas da
  base), **F-2** (`api/v1/uploads.rb` grava em `public/`) e **F-4** (ActiveStorage em `Disk`
  também em produção — volume persistente é requisito de deploy e **bloqueia** o cenário de
  OPS-192)


## Fechamento de órfãos do Phase 2 — esquema de renegociação

Quatro IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Conferir `renegotiations`, `renegotiation_installments` e `renegotiation_payments`
      contra a descrição de `data-schema`, sem criar uma segunda família de tabelas.
      **Fecha: DB-568, DB-569, DB-570.**
- [x] F.2 `renegotiation_attachments` com `has_one_attached :file`; **nenhuma** coluna
      Paperclip é criada. Verificável: `grep` por colunas `*_file_name`/`*_content_type`
      retorna zero. **Fecha: DB-571.**
- [x] F.3 Os limites (4 arquivos, 5 MB) vêm da configuração de anexos, não de constante
      local. Se S13 ainda não tiver entregado o motor, esta tarefa **espera** — S9 não abre
      um segundo caminho de upload. **Fecha: DB-571 (parte).**


---

## Fechamento — o que foi entregue, o que mudou de rumo e o que fica aberto

> Escrito ao fechar a fatia. **Lido junto com o `tasks.md`, não no lugar dele.**

### 124 de 124. As 5 que estavam abertas fecharam em 26/08/2026, e o que as destravou

O fechamento anterior listava 5 tarefas abertas e o motivo de cada uma. **Quatro dos cinco
motivos eram a mesma coisa: dependência externa.** Elas caíram no dia em que o usuário
entregou os dois artefatos de produção — `sfg-31-may-25.sql` (133,4 MB) e `sfg-31-may-25.tar`
(42,3 MB) —, e o quinto era paperwork que dependia deles.

**A DEC-102 continua respeitada.** Nada foi carregado no banco de destino: adiar a **CARGA**
não é adiar a **CONFERÊNCIA**. Todo número abaixo saiu de leitura em fluxo do dump e do tar,
com o motor do ai9 rodando sobre eles.

| # | O que dizia | O que fechou |
| - | ----------- | ------------ |
| **5.3** | *"Bloqueada pela DEC-84: os arquivos vivem no disco do servidor legado."* | **O acervo chegou.** 44 anexos no banco, 44 no acervo, **43 religados, 39.424.330 bytes**, tipo pelos magic bytes (0 fora da allowlist), cada um provado por tamanho e SHA-256, 2ª passada sem blob novo. O 44º tem **0 byte** e fica sem binário, nomeado |
| **5.4** | *"'Conferido na carga' só existe quando a carga roda."* | **Conferido contra a origem, que é onde o número nasce.** Das 169 renegociações, **134 com o contador NULO** e **0 fora do real** (44 anexos em 35 renegociações). No destino, a etapa `counters` do `fixups.rb` reconcilia contra `COUNT(*)` |
| **5.5** | *"É rotina de pós-carga; adiada com ela."* | **A rotina não depende da carga para existir nem para ser provada.** `Sfg::Etl::Fixups::Renegotiations` com 4 etapas, `find_each`, uma transação por renegociação, ensaio que grava e reverte, retomada por pulo. 11 exemplos que **estragam o dado de propósito** e provam o conserto e a idempotência |
| **5.7** | *"Exige um banco de produção do legado, que não existe neste ambiente."* | **Passou a existir.** `Sfg::Etl::Parity::Renegotiations` rodou sobre a população inteira: **47.170 comparações · 47.162 iguais · 0 de precisão · 0 REGRESSÕES**. As 8 divergências são a mudança declarada do D-45, agora com a lista nominal de quem muda no cutover |
| **5.8** | *"`verified` é veredito do Phase 4; antecipá-lo seria carimbar."* | **Continua verdade — para 89 dos 102.** A régua ficou escrita antes da promoção: `verified` = comparado com o DADO DE PRODUÇÃO e bateu. **11 ganharam oráculo** (9 pelo dump, DB-193 pelo acervo, DB-195 pelo contador); os outros 89 continuam `migrated` com o motivo escrito e o dono nomeado |

### Três coisas que só apareceram EXECUTANDO

1. **Um documento financeiro de produção está vazio.** `renegotiation_attachments#45`
   `ANEXO_INSTRUMENTO_DE_GARANTIA.pdf` tem 0 byte no banco **e** no acervo — o próprio
   Paperclip gravou `inode/x-empty` na coluna de tipo em 2022. Reconciliação de contagem e de
   tamanho passa; o documento não existe. Ele **não** é reanexado.
2. **A produção roda um commit anterior a 20/06/2022.** A hipótese natural era que
   `update_values` estivesse quebrado em produção, porque `renegotiation.rb:113` lê
   `self.desagio_value` e a migration que cria a coluna nunca subiu. A medição **reprovou**:
   os agregados batem, inclusive `overdue_installments` na data do `updated_at`. Logo o
   recálculo rodava — e o repositório está à frente do que está no ar **também no código**,
   não só nas migrations. Registrado em `analise-dump-producao.md`.
3. **`total_value_with_desagio` não tem oráculo.** A coluna não existe em produção, então
   BE-208 fica `verified` **com ressalva escrita** em vez de silenciosamente completo.

### O que fica aberto, e de quem é

`verified` para os 89 restantes exige a **carga** contra o destino e a reconciliação real —
**Phase 4, adiada pela DEC-102**. **Dono: o usuário**, que decide a data. O arcabouço está
pronto e provado, e a ordem do runbook é `sfg_etl:load` → `sfg_etl:reconcile` →
`sfg_etl:relink_attachments RELINK=1` → `sfg_etl:renegotiation_fixups DRY_RUN=0`.

### Cinco desvios do que estava escrito, e por quê

1. **DEC-53 anula duas linhas do `proposal.md`.** O mapa marcava **BE-228** (renomear anexo) como `dropped` por DEC-09/Q-B27. A **DEC-53** decidiu o contrário — *"vamos arrumar o renomear anexo"* —, e a DEC vence a tarefa. **Renomear está entregue, com tela.** Já **FE-229** continua `dropped`, mas pela razão da DEC-53 e não pela do mapa: a aba PAGAMENTOS **não** tem tela (o backend é completo), e o botão "excluir todas as parcelas" **não é portado nem no backend**.

2. **A chave do catálogo de anexos mudou** de `renegotiation.files` para `renegotiation_attachment.file`. O anexo precisa de `title` (o usuário renomeia — DEC-53) e de `user_id` (só o autor exclui — BE-229), e nenhum dos dois cabe num blob. Uma **linha por arquivo**, que é também o que `Sfg::Etl::Attachments::MAP` (S14) já declarava e o que dá sentido ao contador `attachments_count`. **Os três consumidores da chave antiga foram ajustados no mesmo passo** (regra de fronteira): `attachment_engine_gate_spec`, `attachments_spec` e `attachable_multiple_spec` — este último retargetado do andaime para o domínio real, como o próprio cabeçalho dele previa.

3. **Os serviços de CRUD não seguem os nomes de arquivo do `tasks.md`.** As tarefas 2.17/2.18 pedem `services/renegotiations/create_service.rb` e `update_service.rb`; a entrega é `app/services/renegotiation_service.rb < ProjectScopedService`, que é o molde **vivo** da base (S4) e o que dá o contrato C1 de graça — escopo na primeira linha, `project_id` do corpo ignorado, id de outro projeto em 404 igual a inexistente. As regras das duas tarefas estão lá, com teste. O que é genuinamente de domínio (agregado, lote, cor, renumeração, cascata, anexo) ficou em `services/renegotiations/`.

4. **OPS-191 entrega uma AUSÊNCIA documentada, não um cron.** A tarefa pede "uma definição versionada com trava de concorrência". Conferido no legado: o **único** cron que existe é `CRONFacade.update_renegotiations_counters` (`config/schedule.{dev,prod}.rb`), e a **D-B6/OPS-190 o elimina**. Não sobra nada periódico. Criar um cron vazio seria pior que nada; o que entrou foi um bloco em `config/schedule.yml` explicando os quatro defeitos daquele cron e por que ele não volta — no arquivo em que alguém procuraria antes de recriá-lo.

5. **`renegotiation_installments.installment` virou `number`.** Uma coluna que se nomeia a si mesma, e o escritor do seed de demonstração (S20) já gravava `number` — o que a execução confirmou: as 34 renegociações do seed vieram com os 24 ordinais preenchidos. O ETL mapeia coluna a coluna de qualquer forma (todo id inteiro do legado vira uuid), então a renomeação não custa nada e está declarada no conversor.

### Uma afirmação do material desta fatia que a extração REPROVOU

O `tasks.md` (4.10) e o `design.md` (§1, item 1) afirmam que, por a mora entrar dos dois lados da conta, **"pagar só a mora pode quitar a parcela"**. **Não pode.** Executando a fórmula do legado: a mora entra no devido (`installment_total_value`) e no pago (`total_paid_value`) **pelo mesmo valor** e **se cancela** — o pendente de uma parcela de R$ 1.000,00 que recebeu R$ 0,01 de principal e R$ 500,00 de mora é **R$ 999,99**, e ela **não** fica quitada.

O efeito real da mora está um nível acima, no agregado: **`paid_value` conta a mora e `remaining_value` a ignora**. São dois números que o cliente lê lado a lado e que não fecham entre si. É esse comportamento que o cenário E do golden test trava, e é ele que a tela explica no tooltip do cartão "R$ Pago".
