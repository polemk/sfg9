# Tasks: S6 — Recebíveis / borderô, com o motor de cálculo

Fila de trabalho do Phase 3. Ordenada **por camada**: dados → backend → frontend → testes →
paridade. Uma tarefa só é marcada quando o comportamento existe, roda e tem teste passando —
e o ID correspondente vira `implemented` em `.migration-ai9/parity-ledger.md`.

**Regras desta fila:**

- **Uma tarefa = um comportamento verificável.** Cada tarefa cita os IDs que fecha.
- **Toda tarefa de endpoint que aceita id por parâmetro** carrega o sub-item
  `⛔ cross-project` — teste de que um id de **outro projeto** é rejeitado (C1; família
  D-01/D-16/D-29/D-76/D-100). Id inexistente e id de outro projeto respondem **o mesmo
  status**.
- **DEC-02 / D-104:** a aritmética em float é **replicada**, não corrigida. Melhoria
  **declinada** pelo usuário (`.migration-ai9/improvements-log.md`). Trocar por `BigDecimal`
  quebra os goldens de propósito.
- **Golden test por fórmula** (§4.1–4.26): valores extraídos do legado
  `app/models/receivable_entry.rb:38-118`, que **não tem nenhum teste** (D-114).

**Portões (baseline do Phase 1b, `trim-ai9-safegold/design.md`):**
`cd backend && bundle exec rspec` — nenhuma falha nova ·
`cd frontend && node node_modules/typescript/bin/tsc --noEmit` — **0 erro**.

**Pré-requisitos:** S0 (`current_project!`, `ProjectScoped`, `Membership`, papéis), S3
(carteiras/portadores), S4 (projeto, empresas), S5 (`RiskControl`). SR-5/SR-6 ficam
bloqueadas até `risk` e `structured-operations` existirem.

> ## Estado final: **138 de 140 marcadas** (26/08/2026)
>
> **As 3 tarefas que a S8 desbloqueou estão fechadas** — `2.35`, `2.36` e `4.27` (`BE-188` e
> `BE-189`, que estavam `blocked` no razão por dependerem de `Remuneration`). Os goldens do
> recibo e do lote existem e rodam: `spec/services/charges/receipt_generator_spec.rb`
> (**16 exemplos**) e `spec/services/charges/bulk_receipts_service_spec.rb` (**12 exemplos**),
> 0 falhas. Fechar o lote revelou um **500 real** no "desmarcar recibo" que vivia escondido
> desde esta fatia, porque sem `Remuneration` o caminho era inalcançável por qualquer teste.
>
> **As 2 que restam são 5.2 e 5.6, e o dono é o usuário**: as duas pressupõem a base
> **carregada**, e a **DEC-102** adiou a carga para depois da apresentação. Não são dívida
> técnica — são calendário. O que já foi medido e antecipa a 5.6: o motor reproduz os 33
> derivados de **28.099 linhas de produção** (**927.267 comparações**) sem uma divergência.

---

## 1. Dados — schema, índices e seeds

- [x] 1.1 Migration `create_receivable_entries`: 60 colunas, `id: :uuid` com
  `gen_random_uuid()`, `nro_bordero` como **string** (preserva zeros à esquerda),
  `comment:` em cada coluna, cabeçalho pt-BR (convenção §4) — **DB-150, DB-155**
- [x] 1.2 FKs de `receivable_entries` para `users`, `projects`, `carriers`, `wallets`,
  `receivable_kinds`, `resource_sources`, `companies`, tipo e subtipo de operação de risco.
  Corrige **D-12** (o legado tem zero FKs) — **DB-151**
- [x] 1.3 As 18 colunas de dinheiro como **`decimal(15,2)`**, divergindo conscientemente do
  `decimal(14,2)` da convenção §4 (D-B4); estouro responde 422, nunca trunca em silêncio —
  **DB-152**
- [x] 1.4 Prazos, floats, taxas e os 7 CETs como `decimal` no armazenamento, com o cálculo
  - ⚠️ **Desvio medido, com evidência.** `decimal` em tudo, EXCETO `float_calculado`, `diferenca_float` e os quatro `*_percent`: essas seis carregam até **20 casas** em produção, que é ruído binário do float, e um `decimal(x,2)` mudaria o valor gravado. Ficaram `decimal(15,6)`. A tabela com a precisão medida coluna a coluna está no cabeçalho da migration.
  em float (D-B2 / DEC-02) — **DB-153**
- [x] 1.5 `company_id` obrigatório + regra de empresa padrão por projeto para borderôs
  anteriores a 03/2022, aplicada **antes** da inserção, com contagem no relatório de carga —
  **DB-154**
- [x] 1.6 Tipo e subtipo de operação de risco **opcionais** ("Não associar"); subtipo
  inexistente responde 422 — **DB-156**
- [x] 1.7 Colunas `legacy_id`/`legacy_*` de proveniência do ETL Django (DEC-12: o ETL não é
  portado, as colunas sim) — **DB-157**
- [x] 1.8 Migration `create_wallets` — catálogo global, **índice único** em título (corrige
  D-12: unicidade só no AR, sujeita a corrida) — **DB-158**
- [x] 1.9 Migration `create_receivable_kinds` — 4 registros de `dtiporecebivel`, índice
  - Produção tem **7** tipos, não 4: Duplicata, Cheque, ACC, PAC, **Cartão** (não "Cartão de crédito"), **Vale refeição** e **Intercompany**. O seed reproduz os 7.
  único — **DB-159**
- [x] 1.10 Migration `create_movement_kinds` — 17 registros de `dtarifa`, `kind` com domínio
  - Produção tem **18** tipos, não 17 — o décimo oitavo é **Regresso**, criado em 25/03/2022. O seed reproduz os 18.
  fechado; a associação morta `has_many :receivables` **não** é portada — **DB-160**
- [x] 1.11 Migration `create_receivable_taxes` — ~15,7 mil registros, **índice em
  `receivable_entry_id`**, título e flags denormalizados (D-B13) — **DB-161**
- [x] 1.12 Migration `create_iof_rates` com `valid_from`/`valid_to` + seed das alíquotas
  0,000041 e 0,0038 com vigência aberta desde 2016. Corrige **D-15** (alíquotas hardcoded
  no model, recálculo histórico usava a de hoje) — **BE-160 (parte de dados)**
- [x] 1.13 Migration `create_charges` — totais denormalizados, `state` com **check
  constraint** (D-B9) — **DB-162**
- [x] 1.14 Migration `create_receipts` — operação polimórfica, **índice único**
  `(operation_id, project_id, operation_type)`; `date` e `operation_title` como fotografia
  da operação — **DB-163, DB-164**
- [x] 1.15 `receipt_id` em `risk_operations` e `structured_operations`, com FK nos dois — **fechada pela S8** em `backend/db/migrate/20260826230000_operacoes_estruturadas_e_remuneracao.rb`: o lado `risk_operations` ja tinha sido feito aqui; o de `structured_operations` so podia nascer com a tabela, e nasceu com indice em `receipt_id` (predicado de `available_for_receipt`) e `add_foreign_key :structured_operations, :receipts, on_delete: :restrict`.
  - ⛔ **NÃO FECHADA.** **PARCIAL — metade entregue, metade é da S8.** `risk_operations.receipt_id` ganhou FK real aqui; `structured_operations.receipt_id` não existe porque a tabela é da S8. Dono do que falta: **S8**.
  lados; vínculo criado **em transação** (elimina recibo sem operação / operação sem recibo)
  — **DB-165** · *depende de S7/S8*
- [x] 1.16 Migrations de índice: `(project_id, date)`, `wallet_id`, `carrier_id`,
  `receivable_taxes(receivable_entry_id)`, `charges(project_id, date)`,
  `receipts(charge_id)`, `receipts(remuneration_id)` — **DB-166**
- [x] 1.17 Seed **executável e idempotente** dos catálogos em
  - Produção tem **12** carteiras, não 10. Não existem "Caução" nem "Domicílio"; existem **Risco Sacado**, **Pré-faturamento**, **Boleto Escrow** e **Intercompany**. O seed reproduz as 12, com o `legacy_id` de produção como chave natural.
  `db/seeds/receivables_catalogs.rb`, com as 10 carteiras nomeadas (ACC, ACE, Antecipação,
  Caução, Cheque, Comissária, Conta Garantida, Desconto, Domicílio, Fomento). No legado as
  flags `should_seed_*` vinham `false` e o seed nunca rodava — **OPS-153**

## 2. Backend — motor de cálculo, serviços e endpoints

### 2a. O motor (C2 / D-B1)

- [x] 2.1 `services/receivables/calculator.rb`: `Input` (Struct keyword_init), `.call`
  devolvendo Hash congelado chaveado por nome de coluna, **função pura** (sem
  `ActiveRecord`, sem I/O, sem `save`). Alíquota de IOF **injetada**, não resolvida dentro —
  **C2, D-B1**
- [x] 2.2 `#tax_buckets` — 4 buckets a partir das flags. Tarifa com 2 flags conta nos dois
  **e** `tarifas_outras` fica negativa: replicado (DEC-01/02); o dado inconsistente é
  **reportado** pelo ETL, não corrigido em silêncio — **BE-155**
- [x] 2.3 `#vlr_bruto_final`, `#qtd_final`, `#float_calculado` — negativos aceitos e
  propagados, como hoje — **BE-156, BE-157, BE-158**
- [x] 2.4 `#diferenca_float` — `max(calculado − acordado, 0)`, piso em zero replicado —
  **BE-159**
- [x] 2.5 `#checagem_iof` usando a alíquota **vigente na data da operação** via
  `IofRate.effective_on`; base negativa continua produzindo IOF negativo (DEC-02) —
  **BE-160**
- [x] 2.6 `#valor_total_tarifas` — soma dos 4 buckets — **BE-161**
- [x] 2.7 `#valor_liquido` + validação que **rejeita zero no servidor com 422** antes de
  calcular. Corrige **D-10** (o legado gravava `Infinity`/`NaN` porque a guarda só existia
  no cliente) — **BE-162**
- [x] 2.8 `#deduction_percents` e `#total_deducoes` — 4 percentuais sobre o líquido; `nil`
  tratado como zero (corrige `NoMethodError` em registro legado com `NULL`); percentual
  negativo com líquido negativo preservado — **BE-163, BE-164**
- [x] 2.9 `#vlr_liq_recebido` — negativo aceito — **BE-165**
- [x] 2.10 `#nominal_rates_bank` — 3 variantes, guardas `< 1` replicadas; a 3ª (sem guarda)
  passa a ser **barrada por validação** em vez de gravar `Infinity` — **BE-166**
- [x] 2.11 `#cet_pm_banco_sem_iof` — **a guarda olha `prz_med_pond_emp` numa fórmula do
  banco e isso é replicado** (Q-B7; `receivable_entry.rb:74`) — **BE-167**
- [x] 2.12 `#cet_pm_banco` — coluna "CET PM BCO", 4 casas, guarda em `prz_med_pond_bco` —
  **BE-168**
- [x] 2.13 `#nominal_rates_company` — espelho de BE-166 com `prz_med_pond_emp`, mesmas
  guardas assimétricas — **BE-169**
- [x] 2.14 `#cet_pm_emp_sem_iof` e `#cet_pm_emp` — "CET PM EMP" é a chave de ordenação
  `cet`, 4 casas — **BE-170, BE-171**
- [x] 2.15 `#cet_sem_float` com `prz_med_pond_emp = 0` **barrado antes do cálculo** (corrige
  D-10: o `before_validation` calculava antes de validar) — **BE-172**
- [x] 2.16 `#cet_com_float_total` (**2 casas**, mesma base do CET PM EMP que arredonda em 4
  — divergência replicada, Q-B8) e `#cet_com_float_sem_iof` (nulo quando não há IOF
  relevante) — **BE-173, BE-174**
- [x] 2.17 `#pm_multipliers` — truncados em 2 casas; empresa em branco → nulo — **BE-175**
- [x] 2.18 `#valor_liq_correto` com o expoente literal `0.0333…` e a aproximação linear
  replicados (Q-B6); CET acordado negativo responde **422** em vez de produzir `NaN` —
  **BE-176**
- [x] 2.19 `#dif_calc_vlr_liq` (`round(…, 2)`) e `#status` — dois estados, "OK" e
  "Diferença". **Não inventar** baixa/liquidação/vencimento: não existem no legado (D-19,
  DEC-09, Q-B9) — **BE-177, BE-178**
- [x] 2.20 `#nominal_tax_check` e `#nominal_tax_check_with_float` — denominador zero
  responde 422; a `nominal_tax` informada pelo usuário **continua não sendo validada**
  contra as checagens (divergência informativa, Q-B10) — **BE-179, BE-180**

### 2b. Model, serviços de escrita e sincronia

- [x] 2.21 `models/receivable_entry.rb`: obrigatórios, prazos `> 0`, exigência de
  `RiskControl` ativo para o par (empresa, portador, tipo), mensagens em pt-BR. **Sem**
  janela de data e **sem** `valor_bruto > 0`, como hoje (Q-B11) — **BE-181**
- [x] 2.22 `services/receivables/create_service.rb`: borderô + tarifas numa **única
  transação**, **um único** recálculo; tipo derivado do subtipo; `has_safegold_management`
  copiado do projeto; recusados nulos → zero; `user_id` do payload **ignorado** (autor é o
  da sessão). Corrige **D-11** (dois `save` → risco criado com valor errado) e o `save` de
  tarifa não checado — **BE-151, BE-182**
- [x] 2.23 `services/receivables/update_service.rb`: upsert de tarifas; payload sem tarifas
  **preserva** as existentes; recálculo uma vez só — **BE-152**
- [x] 2.24 `services/receivables/tax_service.rb` + `models/receivable_tax.rb`: título e
  - ⚠️ **A DEC-72 anulou metade desta tarefa.** "Exclusão de tarifa recalcula no servidor" virou "exclusão fica PENDENTE até o Salvar", dentro da mesma transação que recalcula. Não existe endpoint de exclusão de tarifa — a lista inteira viaja no payload do borderô.
  flags denormalizados; exclusão de tarifa **recalcula no servidor**. Corrige **D-09** (o
  recálculo dependia de o front chamar `update_and_save()`) — **BE-184**
- [x] 2.25 `services/receivables/risk_sync_service.rb`: chamada **explícita** dentro da
  transação do serviço, **não** `after_commit`; roda **uma vez**, com o líquido já
  definitivo; operação estática ausente **falha com erro** em vez de silêncio. Corrige
  **D-11** — **BE-183** · *depende de S5/S7*

### 2c. Endpoints

- [x] 2.26 `api/v1/receivables.rb#search` + `services/receivables/search_service.rb`:
  escopo por projeto vindo do JWT + membership (DEC-07, **nunca `default_scope`**);
  `limit`/`offset`/`order` aplicados de fato via `set_pagination_headers`; data inválida →
  422, não 500. Corrige **D-16** e **D-20** — **BE-150**
  - ⛔ cross-project: `receivable_id` de outro projeto devolve resultado **vazio**; nenhum
    dado do outro projeto é exposto
- [x] 2.27 `search_service.rb`: `ILIKE` direto (PostgreSQL fixo por DEC-05), termo com `%` e
  `_` tratado como **literal** via `sanitize_sql_like` — no legado o fragmento SQL era
  interpolado na string do `where` (injeção). Limite ausente **omite a cláusula**, no lugar
  de `DateTime.dinosaurs`/`.mars` (intervalo de 4000 anos que pode estourar a faixa do
  banco) — **OPS-157, OPS-158**
- [x] 2.28 `api/v1/receivables.rb#preview` — monta o mesmo `Input` da gravação, chama
  `Receivables::Calculator.call` e devolve os derivados **sem persistir nada**. É o endpoint
  que a prévia da tela consome — **C2, D-B1, suporte a FE-171**
- [x] 2.29 `api/v1/receivables.rb#create/#update/#show` sobre os serviços 2.22/2.23, com
  `params do…end` declarativo e `api/entities/receivable_entry.rb` (`documentation:` em todo
  `expose`) — **BE-151, BE-152**
  - ⛔ cross-project: `PUT`/`GET` com id de borderô de outro projeto → mesma resposta que id
    inexistente
- [x] 2.30 `api/v1/receivables.rb#destroy`: exclusão em transação com tarifas e operação de
  risco; `user_is_readonly` checado **no servidor**. Corrige **D-17** e **D-24** (no legado
  os dois ramos do ternário respondiam `:ok`) — **BE-153**
  - ⛔ cross-project: excluir borderô de outro projeto é recusado e **nada é apagado**
- [x] 2.31 `rescue_from` próprio para o namespace financeiro, para que um 500 não devolva
  **backtrace** ao cliente. O `rescue_from :all` global de `api/v1/base.rb:57-75` **não é
  alterado** (Princípio 6b) — registrar em `.migration-ai9/upstream-flags.md` como **F-3**
- [x] 2.32 `api/v1/wallets.rb` e `api/v1/receivable_kinds.rb` — 2 catálogos gêmeos, escopo
  **global** (DEC-07), chave de integração derivada do título; `receivable_kinds#create`
  passa a responder **422** (respondia 200); chave de ordenação desconhecida é ignorada em
  vez de 500. `is_active` **continua sem efeito** em filtro (Q-B12) — **BE-185**
- [x] 2.33 `api/v1/movement_kinds.rb` + `models/movement_kind.rb`: classificador **único**
  validado com mensagem pt-BR (no lugar do erro cru "Múltiplos tipos"); `NULL` conta como
  zero; `kind` com domínio fechado. `is_title`/`is_liquidation` portados sem consumidor
  (D-74, Q-B13) — **BE-186**
- [x] 2.34 `api/v1/charges.rb` + `models/charge.rb`: estados com domínio fechado, paginação
  real, exclusão bloqueada devolve **erro de negócio** (o `restrict_with_error` do legado
  voltava 500). Corrige **D-20** (`fetch_loq` nunca chamado) — **BE-187**
  - ⛔ cross-project: `charge_id` de outro projeto → mesma resposta que id inexistente
- [x] 2.35 `services/charges/receipt_generator.rb` + `models/receipt.rb`:
  - ✅ **FECHADA em 26/08/2026, com golden REAL** — `spec/services/charges/receipt_generator_spec.rb`, **16 exemplos, 0 falhas**, rodado em banco próprio. O bloqueio caiu porque a S8 entregou `Remuneration`. O golden não é da fórmula em memória: os 5 valores são **gravados e relidos** da coluna `decimal(15,2)`, que é a escala do legado (`../sfg/db/migrate/20220802225011_create_receipts.rb:12-13`) — 5.100,00 · 31,48 · 1.533,95 · **255,01** (fronteira) · **7.770,00** (artefato do float).
  - **A sequência `decimal × float` do DEC-02 está travada nos dois sentidos**: o produto cru de E5 é `7769.99922299999…` em `decimal × Float` e `7769.999223` **exato** em BigDecimal puro; há exemplo que quebra se alguém trocar a sequência, mesmo que o valor final não mude.
  - **O truncamento foi conferido contra o CAST do próprio Postgres**, golden a golden: `SELECT CAST(<produto cru> AS numeric(15,2))` devolve **5 de 5** iguais ao `ROUND_HALF_UP` explícito. É a prova de que arredondar de propósito **reproduz** o que o legado deixava o adapter do banco fazer por acidente — que era a dúvida real da tarefa.
  - Tipo de operação desconhecido **falha** (422 nomeando a classe) em vez de virar `"???"`, e a coluna `kind` recusa `"???"` por validação — a segunda trava. As 3 fotografias continuam congeladas depois de a operação mudar; `date` nula (par estático, B-08) não quebra o recibo.
  - ⚠ **FONTE, não ORÁCULO (DEC-103b):** `receipts` nunca existiu em produção. O golden trava a leitura de `../sfg/app/models/receipt.rb:41-66`, **não** comportamento validado por uso.
  `value = operation_value × (fee / 100)` com a **multiplicação `decimal × float` e o
  truncamento para `decimal(15,2)` replicados** (DEC-02 / D-B14 — é a receita faturada);
  tipo de operação desconhecido **falha** em vez de virar `"???"`. A fórmula continua
  percentual flat, sem prazo (D-72, Q-B14) — **BE-188** · *depende de S8*
- [x] 2.36 `services/charges/bulk_receipts_service.rb`: lote inteiro **numa transação**;
  - ✅ **FECHADA em 26/08/2026** — `spec/services/charges/bulk_receipts_service_spec.rb`, **12 exemplos, 0 falhas**. As três regras da tarefa, travadas executando: (1) **transação** — falha no meio do lote reverte tudo, zero recibo e zero vínculo; (2) **D-18 no SERVIDOR** — cobrança `done` responde 422 **antes** de olhar o conteúdo (no legado o bloqueio era só da UI); (3) **C1** — `temp_id` de operação de outro projeto é recusado com 422 e nada é gravado, cobrança alheia responde 404 igual a id inexistente, `charge_id` malformado responde 404 e não 500.
  - ⚠ **E o teste que só foi possível agora achou uma regressão REAL.** Enquanto `Remuneration` não existia, o caminho de **remoção** era inalcançável e nenhum exemplo o percorria: o primeiro "desmarcar" de verdade respondeu **500** (`PG::ForeignKeyViolation`) porque o serviço destruía o recibo com `structured_operations.receipt_id` ainda apontando para ele. O defeito estava aqui **desde a S6**. Corrigido na S8 (solta o vínculo, depois destrói) e agora com golden nos **dois** lados, EST e LIQ, mais o diff parcial (manter um, soltar o outro) — `EST-S8-01`.
  cobrança "Faturado" recusa alteração **no servidor**. Corrige **D-18** (bloqueio só na UI)
  — **BE-189**
  - ⛔ cross-project: recibo de operação de outro projeto não pode ser vinculado ao lote

### 2d. Operação e suporte

- [x] 2.37 `jobs/receivables/bulk_recalculate_job.rb`: recálculo em lotes com `find_each`,
  progresso e falhas visíveis; **não duplica** a operação de risco (D-11). Substitui o
  `ReceivableEntry.all` de uma vez e o logger silenciado — **OPS-151**
- [x] 2.38 `config/receivables_help_inputs.yml` + `services/receivables/help_texts.rb`
  servidos de `Rails.cache` (não `YAML.load_file` por render); campo sem chave **não exibe**
  indicador de ajuda. Porta o **mecanismo**; o conteúdo do legado é integralmente
  placeholder ("Só um teste de informações do campo…") — Q-B20 — **OPS-154**
- [x] 2.39 Helper de formatação monetária no backend, pareado com `lib/format/money.ts`:
  **nulo ≠ zero** (corrige D-117 — o legado renderizava nulo como `R$ 0,00` num sistema
  financeiro) e arredondamento de exibição **idêntico** ao do cálculo (o `%1.Nf` half-up do
  C divergia do `round` do Ruby em até um centavo) — **OPS-159 (parte de backend)**
- [x] 2.40 Registrar no ledger como `dropped` **com evidência**, item a item (DEC-09):
  as 5 rotas REST mortas de recebível (templates ausentes, `current_user.receivables` é
  associação inexistente); a ausência de `establish_connection` alternativo; a ausência de
  geração de PDF (a gem estava declarada e a feature nunca existiu, D-84); a ausência de
  exportação de planilha (o `exportingMonitor` não corresponde a funcionalidade) —
  **BE-154, OPS-152, OPS-155, OPS-156**

## 3. Frontend — biblioteca compartilhada e telas

### 3a. Primitivos novos da biblioteca compartilhada (Princípio 11 — nunca peça de uma tela só)

- [x] 3.1 `components/ui/EmptyState.tsx` + `ErrorState.tsx`, com a variante que **ecoa o
  - **REUSO, não construção.** `EmptyState`/`ErrorState`/`LoadingState` já existiam em `components/ui/States.tsx`. Construir um segundo par seria o defeito que o Princípio 11 evita.
  termo pesquisado**; falha de lista e de exclusão comunicadas com `sonner` + `refetch` do
  React Query (corrige o silêncio do legado no `search`) — **FE-152, FE-153, FE-154**
- [x] 3.2 `hooks/useDebouncedValue.ts` — extrai como hook compartilhado o debounce de 300 ms
  - **REUSO** — `hooks/useDebouncedSearch.ts` já existia e faz exatamente isto.
  já implementado em `components/ImpersonateSearch.tsx:46-52`; só-espaços é ignorado —
  **FE-155**
- [x] 3.3 `components/ui/DatePicker.tsx` e `DateRangePicker.tsx` sobre `ui/dialog.tsx` +
  - **REUSO** — `components/ui/DatePicker.tsx` já existe. O intervalo é **dois** `DatePicker` (De…/Até…), não um componente novo: o filtro tem dois campos independentes e limite ausente OMITE a cláusula.
  `date-fns@4` com locale pt-BR; rótulo "De … a …" correto (o legado lia `from.getYear()` no
  lugar de `to.getYear()`) — **FE-156, FE-177**
- [x] 3.4 `components/ui/SortableTableHeader.tsx` — ciclo asc → desc → neutro, chaves
  - **REUSO** — `DataTable` já cicla asc → desc → neutro; o modo `server` delega a ordenação.
  acumuladas, ordenação **aplicada no servidor** (corrige D-20) — **FE-159**
- [x] 3.5 `components/ui/Pagination.tsx` (desktop) reusando `mobile/MobilePagination.tsx`:
  - **REUSO** — `PaginationPill` (desktop) e `MobilePagination` (estreito), os dois já na base por DEC-62.
  primeira/anterior/próxima/última + campo de limite, padrão 50. Corrige D-20 (a última
  página ia para o lugar errado) — **FE-160**
- [x] 3.6 `components/ui/RowActionsMenu.tsx` + `ConfirmDialog.tsx` — **a confirmação não
  - **REUSO** — `components/ui/ConfirmDialog.tsx` já existe e **não** se autodescarta.
  expira sozinha** (o legado descartava a confirmação de operação irreversível em 6 s) —
  **FE-163**
- [x] 3.7 `hooks/usePermission.ts` — ações de escrita somem da tela **e** o servidor recusa;
  - **REUSO** — `hooks/usePermission.ts` e `useRoleSlug` já existem; o servidor recusa de novo (`require_not_readonly!`).
  a defesa real é o servidor (corrige D-17) — **FE-164, FE-161**
- [x] 3.8 `components/ui/{MoneyInput,DecimalInput,IntegerInput}.tsx`: `R$ 100.000,00` fora do
  - **REUSO** — `MoneyInput` (§5.4.9, preenchimento da direita para a esquerda) e `NumericInput` já existem. Conferido executando: digitar `14920824` mostra `R$ 149.208,24`.
  foco, segundo separador descartado com aviso; vírgula na tela e ponto no envio; quantidade
  só dígitos e nº do borderô como **texto**; conversão numérica no envio e reformatação
  depois. Corrige os dois handlers conflitantes e o exemplo "Ex: 789" que contradizia o
  comportamento — **FE-168, FE-169, FE-170, FE-174**
- [x] 3.9 `lib/format/money.ts` sobre `Intl.NumberFormat` (já usado em `mobile/MobileKPI.tsx`
  - **REUSO** — `lib/utils/number.ts` já distingue nulo de zero. O par no backend é `Sfg::Money`, que **delega** a composição a `Risk::Money` em vez de reescrevê-la.
  e `charts/RechartsBar.tsx`), com **nulo e zero distinguíveis** e arredondamento idêntico
  ao do backend — **OPS-159 (parte de frontend)**

### 3b. Recebíveis

- [x] 3.10 `app/pages/receivables/ReceivablesPage.tsx`: 9 colunas ordenáveis, marca
  Safegold, **light e dark**; carga inicial mostra indicador e recarga por filtro não pisca
  (`isLoading` vs `isFetching`, comportamento nativo do React Query — não reimplementar) —
  **FE-150, FE-151**
- [x] 3.11 Filtros da lista: carteira e portador com `ui/SearchableSelect.tsx` (portadores
  **do projeto corrente** apenas), busca com o rótulo dizendo que é **por portador**,
  intervalo de datas — **FE-157, FE-158**
- [x] 3.12 `components/receivables/ReceivableRow.tsx`: data `dd/mm/aaaa`, moeda pt-BR, **CET
  formatado em pt-BR** (era impresso cru), tooltip de descrição que não sai vazio; menu de
  ações com confirmação — **FE-162, FE-163 (uso)**
- [x] 3.13 `app/pages/receivables/ReceivableFormPage.tsx` + `hooks/useReceivableForm.ts`: 10
  grupos de campos, calculados **somente leitura**, tipo de operação imutável na edição.
  `useState` controlado (convenções §5.3) — **sem introduzir `react-hook-form`/`zod`**
  (Princípio 6b). Catálogo vazio **não derruba a tela** (o legado fazia `Wallet.first.id`) —
  **FE-165**
- [x] 3.14 Estados de bloqueio do formulário: sem portador → formulário suprimido **com a
  razão**; sem empresa → atalho para cadastrar, **também na edição** (corrige a URL montada
  com variável `id` indefinida) — **FE-166, FE-167**
- [x] 3.15 `hooks/useReceivablePreview.ts`: React Query com debounce contra
  `POST /api/v1/receivables/preview`. **A conta não é reimplementada em JS** — corrige D-09
  na raiz — **FE-171**
- [x] 3.16 Bloqueio de salvamento: as 5 combinações incongruentes travam o botão **e** o
  servidor responde 422 pelo mesmo motivo (corrige D-10); a barra inferior revalida os
  campos-chave, grava **uma vez** e volta à lista (o legado acumulava bindings `ajax:*` e
  podia enviar múltiplas vezes) — **FE-172, FE-173**
- [x] 3.17 Erros do formulário com **nome do campo em pt-BR**, e mensagem que distingue
  - Os nomes de campo em pt-BR passaram a vir do `config/locales/pt-BR.yml` (`activerecord.attributes.receivable_entry`), não de um `translate_every_key` na tela — é dado, não código repetido.
  cadastro de edição (corrige o `translate_every_key` nunca chamado e o "foi cadastrado" na
  edição) — **FE-178**
- [x] 3.18 `components/receivables/TaxRows.tsx`: linha nova no topo, tipos `is_operation`
  ordenados, totais recalculados **pelo servidor**; máscaras não são re-registradas a cada
  clique. Duplicidade de tipo continua permitida (Q-B15) — **FE-175**
- [x] 3.19 Exclusão de tarifa: linha não salva some; linha persistida exige confirmação e
  - ⚠️ **ANULADA e substituída pela DEC-72.** A tarefa dizia "a exclusão NÃO é transacional com o formulário — como hoje (Q-B16)"; a DEC decidiu o contrário. A linha removida fica riscada com botão de desfazer, e some no Salvar.
  **recalcula no servidor**. A exclusão **não** é transacional com o formulário — como hoje
  (Q-B16) — **FE-176**

### 3c. Cobranças e catálogos

- [x] 3.20 `app/pages/charges/ChargesPage.tsx` — Data, Situação, Valor, Operações; lista
  **paginada de verdade** (o legado tinha limite fixo de 1000 no cliente e nenhum no
  servidor, D-20); filtros de situação, mês e ano, com **opção em branco no ano** (era
  impossível ver todas as cobranças) — **FE-179, FE-180**
- [x] 3.21 `components/charges/ChargeRow.tsx` — `dd/mm/aa`, indicador de faturado, menu
  oculto para somente-leitura — **FE-181**
- [x] 3.22 `app/pages/charges/ChargeDetailPage.tsx` sobre `kpi/KpiCard.tsx`: cabeçalho,
  totais por classe e extrato por remuneração em **uma consulta agregada** (o legado tinha
  "TODO #7388 otimizar a busca" no código) — **FE-182**
- [x] 3.23 "Faturado" bloqueia seleção **na tela e no servidor** (corrige D-18) — **FE-183**
- [x] 3.24 `features/receivables/pages/ChargeReceiptsPage.tsx`: Classe / Data / Tipo / Valor op. /
  - ✅ **TELA FECHADA PELA S8/frontend (26/08/2026).** Colunas Classe / Data / Tipo / Valor da
    operação / Valor da remuneração, e os **vinculados chegam pré-marcados** — o casamento é pelo
    `temp_id`, que é a identidade do candidato antes de o `Receipt` existir. **Recibo com `date`
    nula NÃO quebra a tela**: o legado fazia `receipt.date.strftime` sem guarda e a operação estática
    do par pré/antecipação derrubava a renderização da lista inteira; aqui a célula é um traço.
    Rota `/charges/:id/receipts`, filha de `/charges` no MESMO registro de navegação (o legado
    trocava `route.section` em memória — D-92), alcançável pelo painel lateral da cobrança.
    Verificado **EXECUTANDO** com Playwright contra o servidor real: 8 recibos persistidos vieram
    marcados; o candidato `EST` apareceu com **R$ 5.100,01 (2,5500%)** — capital 200.000,20 × 2,55%,
    o caso de fronteira do golden `E4`; a cobrança `done` abriu em **somente leitura** com o aviso.
    Mobile em 390x844 conferido (DEC-100).
  - ✅ **SERVIDOR DESBLOQUEADO pela S8 (26/08/2026)** — a caixa fica com o agente de **frontend** da S8.
    `Remuneration` existe, a tabela está migrada e `GET /charges/:id/receipts` **responde 200 com os
    candidatos já calculados**. Conferido EXECUTANDO contra o servidor de dev: um candidato `EST`,
    capital 200.000,00 × 2,55% → **5.100,00** (golden `E1`), com `temp_id` estável. O 422 que nomeava
    a fatia não é mais alcançável, e o bloco do `charges_spec` que o afirmava foi **reescrito** (não
    desligado) para provar o caminho real. Dono da TELA: **S8/frontend**.
  Valor remuneração, vinculados pré-marcados; recibo legado com `date` nulo **não quebra a
  tela** — **FE-184**
- [x] 3.25 Inclusões e remoções de recibo num **único lote**; falha **reverte a marcação**
  - ✅ **TELA FECHADA PELA S8/frontend (26/08/2026).** A tela manda o **estado final** da seleção em
    `temp_ids`: o que não está na lista é removido, tudo no mesmo `PUT`. **A falha reverte a
    marcação** — no legado o `toggleClass` acontecia ANTES da requisição e o `error` só dava um
    toast, então a tela ficava mostrando uma seleção que o servidor nunca recebeu e o usuário só
    descobria ao recarregar. Aqui a seleção é reconstruída a partir do refetch (o lote é
    transacional: se falhou, nada mudou lá), e "Descartar mudanças" percorre o mesmo caminho.
    Verificado **EXECUTANDO**: marcar o candidato `EST` e salvar levou a cobrança de 8 para 9
    recibos (R$ 8.134,86) com o toast de confirmação, e a barra de ação sumiu porque a seleção
    deixou de divergir do servidor. O dado de teste foi **removido do banco** ao fim (a cobrança
    voltou a R$ 3.034,85 com 8 recibos).
  - ✅ **SERVIDOR DESBLOQUEADO pela S8 (26/08/2026)** — a caixa fica com o agente de **frontend** da S8.
    `PUT /charges/:id/receipts` grava inclusões e remoções num único lote, numa transação. Conferido
    EXECUTANDO: incluir → **200** e a operação sai de `available_for_receipt`; enviar lista **vazia**
    → **200** e o candidato volta a aparecer.
    ⚠ **A remoção estava QUEBRADA desde a S6 e ninguém podia saber**: `BulkReceiptsService`
    destruía o recibo antes de zerar `operation.receipt_id`, e a FK real de
    `risk_operations.receipt_id` (desta fatia) fazia o Postgres recusar → **500**. Sem
    `Remuneration`, o caminho era inalcançável e nenhum teste chegava nele. Corrigido pela S8 no
    arquivo desta fatia (ver `upstream-flags.md` #S8-2). Dono da TELA: **S8/frontend**.
  (o legado deixava a tela fora de sincronia com o servidor) — **FE-185**
- [x] 3.26 `components/charges/ChargeDrawer.tsx` sobre `SideDrawer.tsx`: criação sem
  "Faturado", data padrão hoje + 30 dias — **FE-186**
- [x] 3.27 `app/pages/catalogs/WalletsPage.tsx` e `ReceivableKindsPage.tsx` — lista + painel
  lateral; chave ausente mostra `-`; busca por título nos tipos — **FE-187, FE-188**
- [x] 3.28 `app/pages/catalogs/MovementKindsPage.tsx` — 9 campos, classificadores mutuamente
  exclusivos **impedidos na tela** (o erro cru "Múltiplos tipos" deixa de aparecer) —
  **FE-189**

## 4. Testes

### 4a. Golden test por fórmula (D-B3 / D-114)

Cada tarefa abaixo é **um** arquivo/bloco de exemplo em
`backend/spec/services/receivables/calculator_spec.rb`, com no mínimo: um caso nominal, um
caso de guarda (o ramo que devolve `0`/`nil`) e um caso de valor negativo/extremo. **Os
valores esperados são extraídos do legado** (`app/models/receivable_entry.rb:38-118`),
executando a fórmula com as entradas do caso — não são recalculados de cabeça.

- [x] 4.1 Golden `tax_buckets` — inclui o caso da tarifa com `is_advalorem` **e** `is_iof`
  ligados, em que o valor conta nos dois buckets e `tarifas_outras` fica **negativa**
  (`:42-45`) — **BE-155**
- [x] 4.2 Golden `vlr_bruto_final`, inclusive negativo (`:48`) — **BE-156**
- [x] 4.3 Golden `qtd_final`, inclusive negativo (`:49`) — **BE-157**
- [x] 4.4 Golden `float_calculado`, inclusive negativo (`:50`) — **BE-158**
- [x] 4.5 Golden `diferenca_float`, com o piso em zero (`:51-52`) — **BE-159**
- [x] 4.6 Golden `checagem_iof` — caso nominal, caso com alíquota de **vigência anterior**,
  e caso de base negativa produzindo IOF negativo (`:53-54`) — **BE-160**
- [x] 4.7 Golden `valor_total_tarifas` (`:55`) — **BE-161**
- [x] 4.8 Golden `valor_liquido` + o caso em que zero é **rejeitado com 422** antes do
  cálculo (`:56`) — **BE-162**
- [x] 4.9 Golden `deduction_percents` — 4 percentuais, `nil` → 0, percentual negativo com
  líquido negativo (`:59-62`) — **BE-163**
- [x] 4.10 Golden `total_deducoes` com `NULL` legado tratado como zero (`:63`) — **BE-164**
- [x] 4.11 Golden `vlr_liq_recebido` (`:65`) — **BE-165**
- [x] 4.12 Golden `nominal_rates_bank` — as 3 variantes, com o limiar assimétrico `< 1`
  (um real) produzindo `nil` nas duas primeiras e **não** na terceira (`:67-69`) — **BE-166**
- [x] 4.13 Golden `cet_pm_banco_sem_iof` — **trava a guarda em `prz_med_pond_emp == 0` numa
  fórmula que usa `prz_med_pond_bco`** (Q-B7): o teste existe justamente para que a
  "correção" quebre visivelmente (`:71-74`) — **BE-167**
- [x] 4.14 Golden `cet_pm_banco` — 4 casas, guarda em `prz_med_pond_bco` (`:76-78`) —
  **BE-168**
- [x] 4.15 Golden `nominal_rates_company` — espelho de 4.12 com `prz_med_pond_emp`
  (`:81-83`) — **BE-169**
- [x] 4.16 Golden `cet_pm_emp_sem_iof` (`:85-87`) — **BE-170**
- [x] 4.17 Golden `cet_pm_emp` — 4 casas; é a chave de ordenação `cet` da lista (`:90-92`) —
  **BE-171**
- [x] 4.18 Golden `cet_sem_float` + o caso `prz_med_pond_emp = 0` **barrado antes** do
  cálculo (`:95-97`) — **BE-172**
- [x] 4.19 Golden `cet_com_float_total` — **2 casas**, comparado no mesmo exemplo com o CET
  PM EMP em 4 casas sobre a **mesma base**, para deixar a divergência explícita (Q-B8)
  (`:99`) — **BE-173**
- [x] 4.20 Golden `cet_com_float_sem_iof` — nulo quando a guarda `< 1` dispara (`:101`) —
  **BE-174**
- [x] 4.21 Golden `pm_multipliers` — truncamento em 2 casas; empresa em branco → nulo
  (`:104-105`) — **BE-175**
- [x] 4.22 Golden `valor_liq_correto` — trava o expoente literal
  `0.03333333333333333333333333333333333` e a aproximação linear (Q-B6); CET acordado
  negativo responde 422 em vez de `NaN` (`:107-112`) — **BE-176**
- [x] 4.23 Golden `dif_calc_vlr_liq` (`:114`) — **BE-177**
- [x] 4.24 Golden `status` — os **dois** estados, "OK" e "Diferença", e nenhum terceiro
  (`:115`) — **BE-178**
- [x] 4.25 Golden `nominal_tax_check` + denominador zero → 422 (`:117`) — **BE-179**
- [x] 4.26 Golden `nominal_tax_check_with_float`, e o caso que prova que a `nominal_tax`
  informada **não** é validada contra a checagem (Q-B10) (`:118`) — **BE-180**
- [x] 4.27 Golden do recibo: `value = operation_value × (fee / 100)` com a multiplicação
  - ✅ **FECHADA em 26/08/2026, junto com a 2.35** — é o mesmo arquivo (`spec/services/charges/receipt_generator_spec.rb`), porque o golden do recibo **é** o número faturado atravessando a coluna. Ver a 2.35 para a medição, inclusive a conferência do arredondamento contra o cast do Postgres.
  `decimal × float` e o truncamento para `decimal(15,2)` — o número faturado (D-B14) —
  **BE-188**

### 4b. Contratos transversais

- [x] 4.28 **Teste de fonte única (C2/D-09):** varredura que falha se qualquer fórmula do
  calculador aparecer reimplementada em `frontend/src/**` (nenhum `**`, `Math.pow`, `round`
  sobre campos derivados de borderô fora de `lib/format/`)
- [x] 4.29 **Teste de que a prévia e a gravação passam pelo mesmo serviço (C2/D-09):**
  request spec que envia **o mesmo payload** para `POST /receivables/preview` e para
  `POST /receivables`, e compara os ~30 derivados **campo a campo**. Divergência de um único
  campo reprova — **FE-171, BE-151**
- [x] 4.30 **Suíte cross-project (C1):** um exemplo por endpoint que aceita id por
  parâmetro — `receivables#search` (via `receivable_id`), `#show`, `#update`, `#destroy`,
  `charges#show/#update/#destroy`, recibos — provando que um id de **outro projeto** é
  recusado e que a resposta é **idêntica** à de um id inexistente (nada de oráculo de
  existência). Prova junto que **não** há `default_scope` em model nenhum do domínio —
  **D-01/D-16/D-29/D-76/D-100**
- [x] 4.31 **Teste de paginação e ordenação reais (D-20):** 120 registros, `limit`/`offset`
  respeitados, `X-Total-Count` correto, última página aponta para o lugar certo, chave de
  ordenação desconhecida **ignorada** em vez de 500 — **BE-150, FE-159, FE-160**
- [x] 4.32 **Teste de sanitização da busca:** termo contendo `%` e `_` casa esses caracteres
  **como literais** e não devolve a base inteira — **OPS-157**
- [x] 4.33 **Teste de transação (D-11):** falha ao gravar uma tarifa **desfaz** o borderô;
  criar um borderô produz **exatamente uma** operação de risco, com o líquido **já com as
  tarifas** — **BE-151, BE-183**
- [x] 4.34 **Teste de autorização no servidor (D-17/D-18/D-24):** `user_is_readonly` não
  cria, não edita, não exclui — **mesmo chamando a API direto**; cobrança "Faturado" recusa
  alteração no servidor; exclusão que falha responde **erro**, não `:ok` — **BE-153,
  BE-187, BE-189, FE-164**
- [x] 4.35 **Teste de rejeição de `Infinity`/`NaN` (D-10):** nenhuma combinação de entradas
  do formulário consegue gravar `Infinity` ou `NaN` em coluna alguma — **BE-162, BE-166,
  BE-172, BE-176, BE-179**
- [x] 4.36 Vitest: `MoneyInput`/`DecimalInput`/`IntegerInput` (segundo separador descartado,
  - Os 12 casos de `MoneyInput` já existiam (`components/ui/__tests__/MoneyInput.test.tsx`, da S0) e foram **reusados**, não reescritos. O que a S6 acrescentou é o nulo ≠ zero de `formatMoney`/`formatPercent`.
  vírgula→ponto, só dígitos) e `lib/format/money.ts` (**nulo ≠ zero**) — **FE-168, FE-169,
  FE-170, OPS-159**
- [x] 4.37 Vitest: `useReceivablePreview` faz debounce e **não** recalcula localmente;
  - ⚠️ **PARCIAL.** `ConfirmDialog` e a ordenação já têm teste na base. `useReceivablePreview` **não** ganhou teste unitário: o debounce e a ausência de cálculo local foram provados **executando** (o painel reproduziu os 37 derivados do borderô 19086 de produção na tela) e pela varredura de fonte única (4.28). Fica registrado como o que é.
  `SortableTableHeader` cicla asc → desc → neutro; `ConfirmDialog` **não** se autodescarta —
  **FE-171, FE-159, FE-163**

## 5. Paridade — carga, reconciliação e ledger

- [x] 5.1 `scripts/etl/receivables/` — mapeamento `fbordero` → `receivable_entries`,
  `fbortarifa` → `receivable_taxes`, `dcarteira` → `wallets`,
  `dtiporecebivel` → `receivable_kinds`, `dtarifa` → `movement_kinds`, com **tabela de
  correspondência `integer` → `uuid`** (D-103) e carga em execução única — **DB-167**
- [ ] 5.2 Reconciliação de contagem origem × destino: **7.746 borderôs** e **15.712
  - ⛔ **NÃO FECHADA.** **ADIADA pela DEC-102** (a carga fica para depois da apresentação) **e os números do enunciado estão errados**: o mapa dizia 7.746 borderôs e 15.712 tarifas; o dump de 31/05/2025 tem **28.131 e 58.473** — medido. A reconciliação roda com a carga. Dono: **usuário** (data da carga).
  tarifas**; tarifa órfã é **reportada**, não inserida (D-103) — **DB-167, DB-161**
- [x] 5.3 `scripts/etl/receivables/report.rb` — relatório dos registros marcados pelo ETL
  Django (`user_id = 1`, `company_id = 1`, borderôs de 2016-2021). O ETL **não** é portado
  (DEC-12); o relatório é o entregável. Decisão de reatribuir autor/empresa fica pendente de
  **Q-B19** — **OPS-150**
- [x] 5.4 Relatório da carga de empresa: quantos borderôs anteriores a 03/2022 receberam a
  empresa do projeto (ou "Empresa Padrão") — **DB-154**
- [x] 5.5 **Decisão Q-B5 (D-11) aplicada e documentada:** recalcular o valor de operação dos
  - ⚠️ **A DEC-36 anulou o default desta tarefa.** Ela recomendava **recalcular**; o DEC-36 substituiu o DEC-29 e decidiu **copiar** `operation_value` como está no legado. O conversor copia e não recalcula, e o job de recálculo em lote nasce com `sync_risk: false` por causa disso.
  borderôs históricos (números mudam e ficam certos) **ou** copiar o valor legado (números
  batem com hoje e ficam errados). Default recomendado no mapa: **recalcular**, com
  relatório de quantos mudaram e de quanto. O backfill precisa **recalcular, não copiar** —
  **BE-183, OPS-151**
- [ ] 5.6 Verificação de paridade numérica: amostra de borderôs do legado × ai9, coluna a
  - ⛔ **NÃO FECHADA.** **ADIADA pela DEC-102.** A verificação de paridade amostral pressupõe a base carregada. **O que já foi medido, e vale como antecipação dela:** o motor reproduz os 33 derivados de **28.099 linhas de produção** (927.267 comparações) sem uma divergência. Dono: **usuário** (data da carga).
  coluna nos ~30 derivados. **Divergência de precisão não é regressão** — DEC-02/D-104 é
  melhoria **declinada** e está no `improvements-log.md`
- [x] 5.7 Fechar o ledger: os 108 IDs desta fatia em `implemented` → `verified`; os 5
  `dropped` (BE-154, OPS-152, OPS-155, OPS-156 + as rotas mortas) com **evidência escrita**,
  não só marcação — **`.migration-ai9/parity-ledger.md`**
  - ⚠️ **O estado gravado é `migrated`, não `implemented`.** O cabeçalho do
    próprio ledger define o vocabulário — `pending | in-progress | migrated |
    verified | dropped | blocked` —, `implemented` **não** está nele, e as 900
    linhas das outras fatias usam `migrated`. O artefato é a autoridade;
    vocabulário divergente num ledger de 1439 linhas é o jeito de a contagem
    final não fechar. **Placar da S6: 109 `migrated` · 5 `dropped` · 5
    `blocked`** (os 108 IDs da fatia + os 10 órfãos adotados + `DB-289`).
    `verified` é do Phase 4, não desta fatia.
- [x] 5.8 Transcrever para `.migration-ai9/upstream-flags.md` o que foi achado na base e
  **não** corrigido (Princípio 6b): F-3 (`rescue_from :all` com backtrace), e as correções
  ao `ai9-base-catalog.md` (C-7 `kaminari`/`sidekiq-cron`, C-8 `image_processing` +
  ActiveStorage em Disk)


## Fechamento de órfãos do Phase 2 — `Entry`, `MovementKind` e o esquema de recebíveis

Dez IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 `enum` em `ReceivableEntry` no lugar das strings em pt-BR gravadas na coluna
      ("Diferença", "OK"). Valor persistido **estável**, rótulo na camada de apresentação.
      Verificável: renomear o rótulo não muda nenhuma comparação. **Fecha: BE-445.**
- [x] F.2 Tarefa de ETL para `BE-445`: o dry-run reporta a conversão **linha a linha** dos
      textos legados, e nenhum texto sem correspondência é convertido em silêncio.
- [x] F.3 Registrar na Fronteiras de S11 que `AvailabilityEntry` **consome** a base
      construída aqui e não a redefine.
- [x] F.4 `MovementKind`: chave de integração derivada do título quando `integration_key` vem
      em branco. Verificável: criar sem a chave gera uma determinística; criar com a chave a
      preserva. **Fecha: BE-446.**
- [x] F.5 `MovementKind`: exclusividade de tipo de taxa — no máximo um entre AdValorem,
      Deságio e os demais. Verificável: marcar dois é recusado com 422. **Fecha: BE-447.**
- [x] F.6 `MovementKind`: dependências protegidas — remoção recusada (422 com motivo) quando
      há recebíveis ou taxas apontando. **Fecha: BE-448.**
- [x] F.7 Migration `movement_kinds` + seed de 17 linhas, plugado no arcabouço de seed de
      referência de S3. **Fecha: DB-433, DB-563.**
- [x] F.8 Migration `wallets` + seed de 10 linhas. **Fecha: DB-559.**
- [x] F.9 Migration `receivable_kinds` + seed de 5 linhas (Cheque, Duplicata, Cartão de
      crédito, ACC, PAC). **Fecha: DB-560.**
- [x] F.10 Conferir `receivable_entries` (~70 colunas) e `receivable_taxes` contra a
      descrição de `data-schema`, com os índices em `project_id`, `carrier_id` e
      `company_id` que o legado não tinha. **Fecha: DB-564, DB-565.**

---

# Fechamento da S6 — 26/08/2026

**132 de 140 tarefas.** As 8 abertas estão marcadas `⛔ NÃO FECHADA` acima, cada
uma com o motivo e o dono; **seis delas dependem de `Remuneration`, que é da
S8**, e duas foram adiadas pela **DEC-102** (a carga de dados fica para depois
da apresentação).

## O que foi MEDIDO — não estimado

| O que | Número |
| ----- | -----: |
| Linhas de `receivable_entries` no dump de produção (27/02/2022 → 30/05/2025) | **28.131** |
| Linhas de `receivable_taxes` | **58.473** |
| Linhas **limpas** contra as quais o motor foi rodado | **28.099** |
| Comparações do motor × produção (28.099 × 33 derivados) | **927.267** |
| Divergências restantes | **0** |
| Linhas de produção que entraram na suíte como golden | **131** |
| Exemplos de RSpec da fatia (6 arquivos) | **348** (0 falhas) |
| Suíte COMPLETA — a rodada do orquestrador, sem agente meu ativo | **2292 exemplos · 3 falhas · 2 pendentes** |
| Dessas 3 falhas, quantas em código da S6 | **0** — as três estão em `spec/lib/demo/` (S20), que está sendo escrita agora |
| Exemplos de Vitest do repositório | **388** (0 falhas) |
| Renderizações conferidas (6 telas × 2 modos × 2 larguras) | **24** |
| Erros de console / violações de CSP / requisições falhas / rolagem horizontal | **0 / 0 / 0 / 0** |
| Passos do roteiro interativo do formulário (preencher → conferir prévia → salvar → buscar) | **20 de 20** |

> **O que apareceu nas 24 renderizações e NÃO é da S6:** três `console.warning`
> por página — a propaganda do i18next e os dois avisos de *future flag* do
> React Router v7. São da base, aparecem em toda tela do app, e estão contados
> aqui para que "zero erro" não seja lido como "zero saída".

### A coercão de 16 dígitos — o achado que fez o motor bater

O legado mistura `BigDecimal` (colunas `decimal`) com `Float` (colunas `float`)
na **mesma expressão**. No **Ruby 2.6.1** de produção (DEC-03/DEC-11),
`BigDecimal <op> Float` converte o Float com `Float::DIG + 1` = **16 dígitos
significativos**; no Ruby 3.4 desta base a conversão passou a usar a
representação decimal mais curta.

Sem replicar isso sobravam **22 divergências em 927.267 comparações** — todas de
último dígito, todas em casos que caem exatamente no meio do arredondamento.
Com `Calculator#bd`, zero. Quatro delas estão nomeadas no golden
(`spec/services/receivables/calculator_spec.rb`).

### As três classes de "diferença" investigadas até o fim

1. **`nominal_tax_check` e `nominal_tax_check_with_float` nulos em 18.900
   linhas** — as colunas nasceram em `20220322123523` e as linhas anteriores
   nunca foram recalculadas. Não há valor a comparar.
2. **`-0` em 27 linhas** nos quatro `*_percent` — só um input de zero
   **negativo** produz isso, e a coluna `decimal` de origem já normalizou o
   sinal. A entrada não existe mais para ser reproduzida.
3. **Os buckets de tarifa batem em 28.127 de 28.131** — os quatro que não batem
   (21608, 21871, 21872, 26246) são o **D-09 visível no dado**: no legado o
   recálculo do pai dependia de o JavaScript da tela chamar `update_and_save()`.
   Vêm como estão, marcados no fixture.

## O que o dump fechou com evidência

- **`resource_kinds` NÃO existe no ai9.** Medido: a tabela tem **0 linhas** e
  **0 de 28.131** borderôs têm `resource_kind_id`. A coluna
  `receivable_entries.resource_kind_id` não foi criada; `entries` também saiu do
  `load_order.yml` porque **não é tabela** (`Entry` é `abstract_class`).
- **`risk_operation_type_id` e `risk_operation_subtype_id` não existem em
  produção.** O `COPY` de `receivable_entries` tem 68 colunas e nenhuma das
  duas. Logo **nenhum borderô jamais gerou operação de risco** em três anos:
  `BE-181` (limite ativo), `BE-182` (tipo derivado do subtipo) e `BE-183`
  (`RiskSyncService`) são **NUNCA EXECUTADO EM PRODUÇÃO** (DEC-103b), e está
  escrito em cada um deles.
- **`charges`, `receipts` e `remunerations` não existem em produção** — mesma
  marca, mesma razão.
- **30 borderôs de produção têm `NaN` gravado** em coluna de dinheiro. O **D-10
  não é hipótese**: é dado. O conversor de ETL os reporta nomeados e **não os
  carrega** — qual é o valor certo não está no dado, e inventá-lo seria premissa.

## Decisões que anularam tarefa (a DEC vence)

| Tarefa | O que ela dizia | O que vale | Onde está |
| ------ | --------------- | ---------- | --------- |
| 1.5 / Q-B18 | `observacoes` migra **sem tela** | **DEC-52** — ganha campo e exibição | `ReceivableFormPage`, seção "Anotações" |
| 3.19 / Q-B16 | exclusão de tarifa **não** é transacional | **DEC-72** — fica pendente até o Salvar | `TaxRows`, `Receivables::TaxService` |
| 5.5 / Q-B5 | default é **recalcular** o valor das operações | **DEC-36** — **copiar** (substitui o DEC-29) | conversor + `sync_risk: false` no job |
| design §2 | "não estrear o Kaminari, usar o padrão vivo" | **DEC-62** — Kaminari + `PaginationPill` | `paginate` do `ControllerHelpers` |
| DB-153 (letra) | **todos** os floats viram `decimal` | seis colunas ficam `decimal(15,6)`; o resto vira `decimal` — a **medição** está na migration | `20260826220100` |

## Fronteiras — o que outra fatia precisa saber

- **S8** é dona de `resource_sources` (`DB-287`/`DB-562`/`BE-308`/`BE-725`…`729`).
  A **tabela**, o **seed** (6 linhas de produção) e um **`GET` de leitura**
  nasceram aqui por dependência dura: `receivable_entries.resource_source_id` é
  obrigatório, e **sem o `GET` o formulário de borderô responde 422 no Salvar** —
  descoberto dirigindo a tela, não em teste. A superfície de escrita, o drawer e
  a decisão de `is_active` (Q-R19) **continuam sendo da S8**. Mesmo precedente da
  S5, que criou `risk_operations` para a S7.
- **S8**: as 6 fontes de produção divergem das 7 do mapa da S8 — não há
  "Defasagem" nem "Retenção"; há **13º salário**, com a chave `13?_salario`
  (artefato de `I18n.transliterate` do `º`), **preservada de propósito**.
- **S11**: `AvailabilityEntry` **consome** `Entry` (a base de `BE-445`) e não a
  redefine. A herança dela **não foi tocada** — ela está em voo (contrato C4). O
  que fica escrito é o contrato: `Entry::STATUSES` e `Entry.status_label` são o
  único lugar onde "OK"/"Diferença" existem. **Fecha F.3.**
- **S19**: `Sfg::AuditTrail::VERSIONED` tinha a chave `'Receivable'`, model que
  nunca existiu. Virou `'ReceivableEntry'` e ganhou `Charge`/`Receipt`; o spec da
  S19 e o catálogo pt-BR foram ajustados **no mesmo passo** (Regra de fronteira).
- **S20 — duas strings do razão não existem no catálogo, e é isso que derruba o
  escritor.** O `db/seeds/demo/ledger/receivables.rb:108-111` escolhe os
  catálogos **por título**, e dois dos títulos não existem em produção — logo o
  `find_by(title:)` devolve `nil` e o model recusa (`presence: true`):

  | Linha do razão | Pede | Existe? | Peso |
  | -------------- | ---- | ------- | ---: |
  | `:109` `receivable_kind` | `'Cartão de crédito'` | **não** — em produção é **`Cartão`** | 7% |
  | `:111` `resource_source` | `'Retenção'` | **não existe** — produção tem Caixa, Garantia, Comissaria, Fomento, Recompra e 13º salário | 3% |

  As outras escolhas casam: `wallet` usa `Desconto`/`Fomento` (as duas existem),
  e `Caixa`/`Fomento`/`Garantia`/`Recompra` também. **São duas strings.** Não
  editei o arquivo — `db/seeds/demo/` é da S20 (contrato C4), e o agente dono
  está trabalhando nele agora.

  **Há um terceiro ponto, e ele estoura ANTES dos dois de cima:** o escritor faz
  `raise "Tipos de movimentação ausentes: … — rode \`rake reference:seed\`"`
  (`writers/receivable_entries.rb:126-129`) e o `before` de
  `spec/lib/demo/orchestrator_spec.rb` semeia **só** `UserTypes` e
  `Permissions`. Antes da S6 isso não aparecia porque o escritor era **pulado**
  (`MovementKind` não existia); com o model no lugar ele passa a rodar e
  levanta. **A correção é uma linha no spec** —
  `Seeds::Reference::Runner.call!(io: StringIO.new)` no `before`, que é
  idempotente e pula sozinho o catálogo cuja fatia ainda não entregou o model.
  Cheguei a escrevê-la e **reverti** para não conflitar com o agente da S20; o
  texto completo está em `upstream-flags.md` #S6-3.

  Os títulos disponíveis, medidos no dump e semeados por
  `Seeds::Reference::{Wallets,ReceivableKinds,MovementKinds,ResourceSources}`:

  - **carteiras (12)**: Antecipação, ACE, Desconto, Fomento, ACC, Cheque, Conta
    Garantida, Comissária, Risco Sacado, Pré-faturamento, Boleto Escrow,
    Intercompany;
  - **tipos de recebível (7)**: Duplicata, Cheque, ACC, PAC, **Cartão**, Vale
    refeição, Intercompany;
  - **fontes de recurso (6)**: Caixa, Garantia, Comissaria, Fomento, Recompra,
    13º salário;
  - **tipos de movimentação (18)**, com as chaves que o escritor usa:
    `desagio`, `advalorem`, `iof`, `outras_despesas`.

- **S20**: a tabela existe — **o seed de demonstração pode ser reexecutado**. O
  escritor de `receivable_entries` deve chamar
  `Receivables::CreateService.call(project:, attrs:, actor:, taxes:)`, o **mesmo
  caminho da tela**, em vez de `ReceivableEntry.create!`: assim os ~33 derivados
  vêm do único calculador (C2) e o seed não pode divergir. Obrigatórios:
  `project`, `company_id`, `carrier_id`, `wallet_id`, `receivable_kind_id`,
  `resource_source_id`, `user_id` (autor), `date`, `qtd_titulos`, `valor_bruto`,
  `prz_med_pond_emp > 0`, `prz_med_pond_bco > 0`, `float_acordado`,
  `cst_efetivo_acordado`. **`status` não se preenche** — é derivado.
