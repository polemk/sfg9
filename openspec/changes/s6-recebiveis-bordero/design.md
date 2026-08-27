# Design: S6 — Recebíveis / borderô em ai9

> O mapa item-a-item **não é duplicado aqui**. Cada grupo abaixo referencia a seção
> correspondente de `.migration-ai9/map/receivables-renegotiations.md`:
> §2.1 backend · §2.2 frontend · §2.3 dados · §2.4 operação · §3 decisões de comportamento
> (D-B1…D-B15) · §4 lacunas do ai9 · §5 perguntas · §6 correções ao catálogo.

## 1. O `Receivables::Calculator` — o coração da fatia (C2, D-B1)

### O problema que ele resolve

No legado a conta acontece em **dois lugares**:

- `app/models/receivable_entry.rb:38-120` — um `before_validation` gigante que atribui ~30
  colunas derivadas antes de qualquer validação rodar;
- `app/views/pub/receivables/new/_body.js.erb:339-504` — uma reimplementação **parcial** em
  JavaScript que não calcula `taxa_desconto_nominal_*`, `custo_efetivo_com_float_*`,
  `multiplicador_*` nem os `*_percent`, e arredonda o total de tarifas de forma diferente.

Resultado: **D-09** — a prévia da tela e o valor gravado divergem, e não há como dizer qual
está certo. Além disso, calcular **antes** de validar é a raiz do **D-10**: com
`prz_med_pond_emp = 0` ou `valor_liquido = 0`, o `before_validation` grava `Infinity`/`NaN`
no banco, porque a única guarda existia no cliente.

### Forma no ai9

`backend/app/services/receivables/calculator.rb` — **função pura**, sem `ActiveRecord`,
sem I/O, sem `save`. Segue o padrão de service do ai9
(`ai9-conventions.md` §3.6: `class << self` + `ApiResponseHandler`), mas **sem**
`ApiResponseHandler`: o calculador não responde a HTTP, ele devolve números.

```ruby
# backend/app/services/receivables/calculator.rb
module Receivables
  class Calculator
    Input = Struct.new(
      # entradas do usuário
      :valor_bruto, :vlr_bruto_recusado, :qtd_titulos, :qtd_recusada,
      :prz_med_pond_emp, :prz_med_pond_bco, :float_acordado, :cst_efetivo_acordado,
      :recompra, :retencao, :fomento, :outros, :nominal_tax,
      # tarifas: [{ value:, is_advalorem:, is_desagio:, is_iof: }, ...]
      :taxes,
      # contexto para a alíquota vigente (BE-160)
      :operation_date,
      keyword_init: true
    )

    # Devolve um Hash congelado com as ~30 colunas derivadas, nas mesmas chaves
    # das colunas de `receivable_entries`.
    def self.call(input, iof_rate: nil) = new(input, iof_rate).call
  end
end
```

**Assinatura e contrato:**

| Item | Regra |
| ---- | ----- |
| Entrada | `Receivables::Calculator::Input` — **só** os campos digitáveis + as tarifas + a data da operação. Nunca um `ReceivableEntry` |
| Saída | `Hash` congelado, chaveado pelo **nome da coluna** (`:valor_liquido`, `:custo_efetivo_pz_med_emp`, …). Nenhum efeito colateral |
| Alíquota de IOF | Resolvida **fora** do calculador (`IofRate.effective_on(date)`) e injetada — o calculador continua puro e o golden test fixa a alíquota (BE-160) |
| Aritmética | **Float**, na mesma ordem de operações do legado, com os mesmos casts e `round` (DEC-02 / D-104). Nada de `BigDecimal` |
| Armazenamento | `decimal` nas colunas (D-B2) — o DEC-02 permite explicitamente replicar o **resultado** sem replicar o **tipo de armazenamento** |
| Guardas | As guardas que **produzem número** (`< 1`, `== 0` → `0`/`nil`) são replicadas tal e qual. As que produziriam `Infinity`/`NaN` viram **validação 422 antes de calcular** (D-10) |

### Quem chama

```
POST /api/v1/receivables/preview  ─┐
                                   ├─→ Receivables::Calculator.call(input) ─→ Hash
Receivables::CreateService ────────┤        (uma implementação, zero duplicatas)
Receivables::UpdateService ────────┤
Receivables::TaxService ───────────┤
Receivables::BulkRecalculateJob ───┘
```

- **A prévia (FE-171/`#preview`)** monta o `Input` a partir do formulário, chama
  `Calculator.call` e devolve o Hash **sem persistir nada**. Não há transação, não há
  `ReceivableEntry` instanciado.
- **A gravação (BE-151/BE-152)** monta **o mesmo `Input`** a partir dos mesmos parâmetros,
  chama `Calculator.call`, e faz `entry.assign_attributes(result)` dentro da transação que
  grava borderô + tarifas. Recálculo acontece **uma vez** por operação (corrige D-11: o
  legado salvava duas vezes e a `RiskOperation` nascia com o líquido sem as tarifas).
- **A verificação de que os dois coincidem** é um teste de request, não uma convenção:
  mesmo payload → `#preview` e `#create` devolvem os mesmos ~30 derivados, campo a campo
  (tarefa 4.30).

O front **não recalcula nada**. `hooks/useReceivablePreview.ts` é um `useQuery` com
debounce sobre o payload do formulário; os campos derivados são somente-leitura.

### Por que isto torna o DEC-02 auditável

Com a fórmula em um lugar só, "replicar o float" deixa de ser intenção e vira **um arquivo
com 26 métodos e 26 golden tests**. Qualquer futura troca por `BigDecimal` quebra os
goldens de forma visível — que é exatamente o comportamento desejado, já que a decisão do
usuário é manter o float.

### As 26 fórmulas e sua origem legada

Todas em `app/models/receivable_entry.rb:38-120`, na **ordem em que o legado as executa** —
a ordem importa porque cada uma consome o resultado da anterior:

| # | Método no ai9 | ID | Origem (linha legada) |
| - | ------------- | -- | --------------------- |
| 1 | `tax_buckets` | BE-155 | `:42-45` |
| 2 | `vlr_bruto_final` | BE-156 | `:48` |
| 3 | `qtd_final` | BE-157 | `:49` |
| 4 | `float_calculado` | BE-158 | `:50` |
| 5 | `diferenca_float` | BE-159 | `:51-52` |
| 6 | `checagem_iof` | BE-160 | `:53-54` |
| 7 | `valor_total_tarifas` | BE-161 | `:55` |
| 8 | `valor_liquido` | BE-162 | `:56` |
| 9 | `deduction_percents` | BE-163 | `:59-62` |
| 10 | `total_deducoes` | BE-164 | `:63` |
| 11 | `vlr_liq_recebido` | BE-165 | `:65` |
| 12 | `nominal_rates_bank` | BE-166 | `:67-69` |
| 13 | `cet_pm_banco_sem_iof` | BE-167 | `:71-74` |
| 14 | `cet_pm_banco` | BE-168 | `:76-78` |
| 15 | `nominal_rates_company` | BE-169 | `:81-83` |
| 16 | `cet_pm_emp_sem_iof` | BE-170 | `:85-87` |
| 17 | `cet_pm_emp` | BE-171 | `:90-92` |
| 18 | `cet_sem_float` | BE-172 | `:95-97` |
| 19 | `cet_com_float_total` | BE-173 | `:99` |
| 20 | `cet_com_float_sem_iof` | BE-174 | `:101` |
| 21 | `pm_multipliers` | BE-175 | `:104-105` |
| 22 | `valor_liq_correto` | BE-176 | `:107-112` |
| 23 | `dif_calc_vlr_liq` | BE-177 | `:114` |
| 24 | `status` | BE-178 | `:115` |
| 25 | `nominal_tax_check` | BE-179 | `:117` |
| 26 | `nominal_tax_check_with_float` | BE-180 | `:118` |

**Três armadilhas que os goldens travam** (todas replicadas por DEC-02, todas com pergunta
aberta no mapa §5):

1. `custo_efetivo_pz_med_banco_sem_iof` guarda em `prz_med_pond_emp == 0` numa fórmula que
   usa `prz_med_pond_bco` — parece copy/paste, **não é corrigido** (Q-B7).
2. `custo_efetivo_com_float_total` arredonda em **2** casas; `custo_efetivo_pz_med_emp`
   arredonda em **4**, sobre a mesma base (Q-B8).
3. O expoente literal `0.03333333333333333333333333333333333` de `calc_valor_liq_correto`
   e a aproximação linear (juros simples, não desconto composto) alimentam o `status`
   "OK"/"Diferença" (Q-B6).

## 2. Escopo por projeto (C1) — como cai em cada endpoint

Contrato definido em `migration-map.md` §C1. Aqui vale a forma concreta:

- Todo endpoint de `api/v1/receivables.rb`, `charges.rb`, `receipts` chama
  `current_project!` no `before` do namespace e **filtra pela associação**, nunca por
  `default_scope`.
- **A regra que o legado quebrava:** quando chega um id por parâmetro
  (`receivable_id`, `charge_id`, `receipt_id`), o filtro de projeto **continua valendo**. O
  legado substituía a query inteira por `ReceivableEntry.where(id: ...)` e vazava borderô de
  outro projeto (**D-16**, família D-01/D-29/D-76/D-100).
- **Resposta uniforme:** id inexistente e id de outro projeto respondem **o mesmo status**
  (404). Distinguir 403 de 404 vira oráculo de existência de id (condição acrescentada pelo
  bloco de auth ao C1).
- Consequência de teste: **toda** tarefa de endpoint que aceita id por parâmetro carrega um
  teste de rejeição cross-project. Está escrito em cada tarefa de §2 do `tasks.md`.

## 3. Grupos de IDs → camada alvo em ai9

### Dados (DB-150…DB-167 — mapa §2.3)

| Grupo | Alvo | Equivalente ai9 reaproveitado | Decisão |
| ----- | ---- | ----------------------------- | ------- |
| Borderô (DB-150…157) | `db/migrate/*_create_receivable_entries.rb` + `models/receivable_entry.rb` | Padrão `id: :uuid, default: gen_random_uuid()` do `schema.rb`; pgcrypto | Tabela larga de 60 colunas, mantida larga — normalizar mudaria o que telas antigas mostram. `nro_bordero` é **string** (zeros à esquerda). `comment:` em cada coluna (convenção §4) |
| Dinheiro (DB-152, DB-153) | 18 colunas `decimal(15,2)`; prazos/taxas/CETs em `decimal` | — | **D-B4**: diverge conscientemente do `decimal(14,2)` de `ai9-conventions.md` §4. Estouro → 422, nunca truncamento silencioso |
| Catálogos (DB-158…160) | `wallets`, `receivable_kinds`, `movement_kinds` | — | Escopo **global** (DEC-07), não por projeto. Índice único em título — corrige D-12 (unicidade só no AR, sujeita a corrida) |
| Tarifas (DB-161) | `receivable_taxes` | — | Índice em `receivable_entry_id` (o legado lia a tabela 4× por save, sem índice). Título e flags **denormalizados** de propósito (D-B13) |
| Cobrança (DB-162…165) | `charges`, `receipts`, `receipt_id` nas operações | — | **D-B11**: cobrança **nunca** referencia operação diretamente, só via `receipts`. Restrição arquitetural documentada na própria migration legada — preservada |
| Alíquotas (BE-160) | `iof_rates` (`valid_from`/`valid_to`) | — | Padrão novo, reaproveitável por qualquer taxa regulada. Seed: 0,000041 e 0,0038 com vigência aberta desde 2016 |
| Índices e ETL (DB-166, DB-167) | migrations de índice + `scripts/etl/receivables/` | — | O salto `integer` → `uuid` exige tabela de correspondência (D-103) |

### Backend (BE-150…BE-189 — mapa §2.1)

| Grupo | Alvo | Equivalente ai9 reaproveitado |
| ----- | ---- | ----------------------------- |
| Endpoints REST | `api/v1/{receivables,wallets,receivable_kinds,movement_kinds,charges}.rb` | **Grape** — `api/v1/base.rb` (mount + namespace), `controller_helpers.rb` (`process_service_response`, `authenticate_user!:25`, `set_pagination_headers:18`), `api/v1/media.rb` como endpoint-modelo. `params do…end` dá validação declarativa **de verdade** (corrige as 422 que o legado devolvia como 200) |
| Serialização | `api/entities/{receivable_entry,charge,receipt}.rb` | `Grape::Entity` com `documentation:` em todo `expose` (padrão de `api/entities/`) |
| Regra de negócio | `services/receivables/*.rb`, `services/charges/*.rb` | Padrão `medium_service.rb` / `users_service.rb` (`class << self` + `ApiResponseHandler`) |
| Paginação | `limit`/`offset` + `set_pagination_headers` | `kaminari` está no `Gemfile:85` **e não é usado em lugar nenhum na base**; o padrão vivo é `controller_helpers.rb:18` + CORS já expondo `X-Total-Count`. **Decisão desta fatia: reusar o padrão vivo**, não estrear o Kaminari (Princípio 6b). Corrige D-20 |
| Busca | `services/receivables/search_service.rb` | `ILIKE` do PostgreSQL (DEC-05 fixou o banco) com `sanitize_sql_like` — o legado interpolava fragmento SQL na string do `where` (injeção) |
| Autorização | gate por rota + `user_is_readonly` no servidor | `Permission`/`UserPermission`, `api/v1/permissions.rb`, `PermissionAuditLog`. **Não criar mecanismo paralelo** |
| Recálculo em massa | `jobs/receivables/bulk_recalculate_job.rb` | Sidekiq + `find_each`. Não dispara sincronia de risco duas vezes (D-11) |
| Sincronia com risco | `services/receivables/risk_sync_service.rb` | Chamada **explícita** dentro da transação — **não** `after_commit`. Roda uma vez, com o líquido já definitivo |

### Frontend (FE-150…FE-189 — mapa §2.2)

| Grupo | Alvo | Equivalente ai9 reaproveitado |
| ----- | ---- | ----------------------------- |
| Tabela, filtros, paginação | `ReceivablesPage.tsx`, `ChargesPage.tsx` | `ui/Table.tsx`, `PageHeader.tsx`, `Layout.tsx`, `ui/SearchableSelect.tsx`, `mobile/MobilePagination.tsx`; **React Query** para `isLoading`/`isFetching`/`isError`/`refetch`; `sonner` para toast |
| Formulário de borderô | `ReceivableFormPage.tsx` + `hooks/useReceivableForm.ts` | `ui/{Input,Label,Card,tabs}.tsx` + `useState` controlado. **Decisão: não introduzir `react-hook-form`/`zod`** — Princípio 6b e proporcionalidade; a validação forte fica no Grape e no model. Registrado como risco de manutenção (mapa §4), não como bloqueio |
| Prévia | `hooks/useReceivablePreview.ts` | React Query com debounce sobre `#preview`. **Zero fórmula em JS** |
| Máscaras e formatação | `ui/{MoneyInput,DecimalInput,IntegerInput}.tsx`, `lib/format/money.ts` | `Intl.NumberFormat` já usado em `mobile/MobileKPI.tsx` e `charts/RechartsBar.tsx`. **Nulo ≠ zero** (D-117: o legado renderizava nulo como `R$ 0,00` num sistema financeiro) |
| Datas | `ui/{DatePicker,DateRangePicker}.tsx` | `date-fns@4` (instalado, sem componente) + `ui/dialog.tsx`, locale pt-BR |
| Ações e permissão | `ui/RowActionsMenu.tsx`, `ui/ConfirmDialog.tsx`, `hooks/usePermission.ts` | `ui/dialog.tsx`, `mobile/MobileMenuActions.tsx`, `hooks/useAuth.ts`. **A confirmação não pode expirar sozinha** — o legado descartava em 6 s |
| KPI de cobrança | `ChargeDetailPage.tsx` | `components/kpi/KpiCard.tsx` |

### Operação (OPS-150…OPS-159 — mapa §2.4)

Seeds idempotentes em `db/seeds/receivables_catalogs.rb` (as flags `should_seed_*` do legado
vinham `false` — o seed nunca rodava); ajuda de campo servida de `Rails.cache`, não
`YAML.load_file` por render; três IDs entram como `dropped` com evidência (OPS-152, OPS-155,
OPS-156) porque a funcionalidade **nunca existiu** no legado apesar da gem declarada.

## 4. O que fica registrado, não corrigido (Princípio 6b)

Achados na base ai9 que **não** são consertados nesta fatia e vão para
`.migration-ai9/upstream-flags.md` (já mapeados em §6 do mapa de bloco):

- **F-3** — `Api::V1::Base` (`base.rb:57-75`) tem `rescue_from :all` que devolve
  **backtrace ao cliente** e cita "API ERROR - POLEMK WHATS". Consequência para esta fatia:
  os endpoints financeiros precisam de `rescue_from` próprio para não vazar caminho de
  arquivo num 500. Isso **é** trabalho desta fatia (tarefa 2.31); mudar o `rescue_from`
  global **não é**.
- Correções ao `ai9-base-catalog.md` (C-7, C-8): `kaminari`, `sidekiq-cron`,
  `image_processing` e o ActiveStorage em Disk não estão catalogados. Transcrever, não
  corrigir código.

## 5. Ordem de execução e critério de pronto

Ordem das sub-fatias: **SR-1 → SR-2 → SR-3 → SR-4**, com **SR-5/SR-6** entrando quando
`risk` e `structured-operations` estiverem prontos, e **SR-7** (carga) por último — é o gate
do Phase 4.

Uma sub-fatia só fecha quando **backend + frontend + teste** dela existem e rodam. Não há
sub-fatia "só de model".

**Baselines a respeitar** (medidos no Phase 1b, `trim-ai9-safegold/design.md`): `rspec` no
máximo com as falhas pré-existentes conhecidas — uma falha nova é desta fatia; type-check do
front em **0 erro**.
