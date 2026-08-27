# Proposal: S6 — Recebíveis / borderô, com o motor de cálculo

## Why

O borderô é o registro central do Safegold: é onde o dinheiro entra no sistema. Toda a
capability `receivables` (108 IDs de inventário) existe hoje no legado `sfg` e **nada dela
existe na base ai9** — o trim do Phase 1b deixou a base sem nenhum domínio financeiro.

Esta fatia existe por três razões que nenhuma outra fatia resolve:

1. **O motor de cálculo (C2).** As 26 fórmulas de CET vivem hoje em **dois lugares** no
   legado — `app/models/receivable_entry.rb:38-120` (Ruby, no `before_validation`) e uma
   reimplementação parcial em JavaScript (`.../receivables/new/_body.js.erb:339-504`) — com
   divergências conhecidas e catalogadas (**D-09**). No ai9 a fórmula passa a viver em
   **um serviço só**, `Receivables::Calculator`, chamado tanto pelo endpoint de prévia
   quanto pela gravação. É a única forma de a prévia da tela e o valor gravado nunca
   divergirem.
2. **O legado não tem nenhum teste (D-114).** Replicar a aritmética em float (**DEC-02**,
   melhoria **declinada** pelo usuário) só é honesto se for verificável. Cada fórmula ganha
   um **golden test** alimentado com valores extraídos do legado. É a primeira
   especificação executável que o Safegold vai ter.
3. **O escopo por projeto (C1).** No legado, sempre que chegava um id por parâmetro
   (`receivable_id`), o filtro de projeto era descartado — família
   **D-01 / D-16 / D-29 / D-76 / D-100**. No ai9 o escopo é aplicado **no endpoint** via
   `current_project!`, nunca por `default_scope`.

## What Changes

Entrega ponta a ponta as sub-fatias **SR-1 … SR-7** do mapa de bloco
(`.migration-ai9/map/receivables-renegotiations.md` §1): catálogos de recebível, motor de
cálculo, lista e CRUD, formulário de borderô com prévia em tempo real, integração com o
controle de risco, cobranças e recibos, e a carga de dados.

**Não** entrega: nada de `risk` (S5/S7), nada de `structured-operations` (S8), nada de
renegociações (S9). Onde este bloco toca esses domínios (`risk_operation_subtype_id`,
`receipts.remuneration_id`) a dependência está declarada abaixo.

### Dependências

| Direção | O quê |
| ------- | ----- |
| S6 depende de | **S0** (`Project`, `Membership`, `current_project!`, `ProjectScoped`, papéis/C3), **S3** (portadores, segmentos, carteiras), **S4** (projeto, empresas), **S5** (`RiskControl` — validação de limite ativo de BE-181 e a operação de risco de BE-183) |
| S6 depende parcialmente de | **S8** (`structured-operations` — remunerações que alimentam `receipts`, BE-188/DB-165). Se S8 atrasar, SR-1..SR-4 entregam valor sozinhos e SR-6 fica em espera |
| Dependem de S6 | **S7** (operações de risco consomem o borderô), **S13** (jobs), **S14** (ETL) |

**SR-5 e SR-6 dependem de R5/R6** (risco), dependência já registrada no
`migration-map.md` §"Dependências entre blocos".

### Decisões que governam esta fatia

- **DEC-02 / D-104 — aritmética em float é REPLICADA, não corrigida.** Melhoria
  **declinada** pelo usuário, registrada em `.migration-ai9/improvements-log.md`. QA **não**
  deve tratar divergência de precisão como regressão. O armazenamento vira `decimal` no ai9
  (D-B2), mas a **sequência de cálculo, os casts e os pontos de arredondamento** são os do
  legado.
- **O que o DEC-02 NÃO cobre:** `Infinity`/`NaN` gravado porque a guarda só existia no
  cliente (**D-10**) é registro corrompido, não precisão — continua sendo corrigido, com
  rejeição 422 no servidor.
- **D-B4** — `decimal(15,2)` para dinheiro, divergindo da recomendação de `decimal(14,2)` de
  `ai9-conventions.md` §4: o teto do legado é R$ 9.999.999.999.999,99 e estreitar a coluna
  truncaria dado histórico em silêncio.
- **Performance nunca muda resultado.** Índice, FK, `find_each` e agregação são bem-vindos;
  uma query "otimizada" que muda um centavo é defeito.

## Impact

- **Afetado:** `backend/app/{controllers/api/v1,controllers/api/entities,models,services,jobs}`,
  `backend/db/migrate` + `schema.rb`, `backend/spec/**`, `frontend/src/{app/pages,components,hooks,lib}`,
  `scripts/etl/receivables/`.
- **Novos membros da biblioteca compartilhada do ai9** (Princípio 11 — não são peça de uma
  tela só): `EmptyState`, `ErrorState`, `DateRangePicker`, `DatePicker`,
  `SortableTableHeader`, `Pagination`, `RowActionsMenu`, `ConfirmDialog`, `MoneyInput`,
  `DecimalInput`, `IntegerInput`, `FileDropzone` (este último nasce em S9),
  `hooks/useDebouncedValue.ts`, `hooks/usePermission.ts`, `lib/format/money.ts`.
- **Volume de carga:** 7.746 borderôs e 15.712 tarifas.
- **Não afetado:** o legado `sfg` (read-only) e as capabilities de outros blocos.
- **Requirements:** já existem em `openspec/specs/receivables/spec.md` (108 requirements,
  um por ID). **Não são recriados aqui** — o `specs/` desta change traz apenas os
  requirements **novos**, de contrato transversal, que não vieram do inventário.

## IDs de inventário cobertos (108)

Estratégia copiada de `.migration-ai9/map/receivables-renegotiations.md` §2.1–§2.4.
**Placar: 88 `build` · 10 `adapt` · 10 `reuse`** (dos quais 5 `reuse` entram no ledger como
`dropped` com evidência, por DEC-09).

### `receivables` — backend (§2.1)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-150 | build | `api/v1/receivables.rb#search` + `services/receivables/search_service.rb` |
| BE-151 | build | `services/receivables/create_service.rb` (borderô + tarifas em uma transação) |
| BE-152 | build | `services/receivables/update_service.rb` (upsert de tarifas) |
| BE-153 | build | `api/v1/receivables.rb#destroy` |
| BE-154 | **reuse** → `dropped` | 5 rotas REST mortas; a navegação é do React Router (DEC-09) |
| BE-155 | build | `calculator.rb#tax_buckets` |
| BE-156 | build | `calculator.rb#vlr_bruto_final` |
| BE-157 | build | `calculator.rb#qtd_final` |
| BE-158 | build | `calculator.rb#float_calculado` |
| BE-159 | build | `calculator.rb#diferenca_float` |
| BE-160 | build | `calculator.rb#checagem_iof` + `models/iof_rate.rb` (alíquota com vigência) |
| BE-161 | build | `calculator.rb#valor_total_tarifas` |
| BE-162 | build | `calculator.rb#valor_liquido` + validação (zero rejeitado, 422) |
| BE-163 | build | `calculator.rb#deduction_percents` |
| BE-164 | build | `calculator.rb#total_deducoes` |
| BE-165 | build | `calculator.rb#vlr_liq_recebido` |
| BE-166 | build | `calculator.rb#nominal_rates_bank` (3 variantes, guardas `< 1`) |
| BE-167 | build | `calculator.rb#cet_pm_banco_sem_iof` (guarda em `prz_med_pond_emp` — Q-B7) |
| BE-168 | build | `calculator.rb#cet_pm_banco` |
| BE-169 | build | `calculator.rb#nominal_rates_company` |
| BE-170 | build | `calculator.rb#cet_pm_emp_sem_iof` |
| BE-171 | build | `calculator.rb#cet_pm_emp` |
| BE-172 | build | `calculator.rb#cet_sem_float` |
| BE-173 | build | `calculator.rb#cet_com_float_total` (2 casas — Q-B8) |
| BE-174 | build | `calculator.rb#cet_com_float_sem_iof` |
| BE-175 | build | `calculator.rb#pm_multipliers` |
| BE-176 | build | `calculator.rb#valor_liq_correto` (aproximação linear — Q-B6) |
| BE-177 | build | `calculator.rb#dif_calc_vlr_liq` |
| BE-178 | build | `calculator.rb#status` ("OK" / "Diferença" — Q-B9) |
| BE-179 | build | `calculator.rb#nominal_tax_check` |
| BE-180 | build | `calculator.rb#nominal_tax_check_with_float` |
| BE-181 | build | `models/receivable_entry.rb` (validações, mensagens pt-BR) |
| BE-182 | build | `create_service.rb` (tipo derivado do subtipo, `has_safegold_management`) |
| BE-183 | build | `services/receivables/risk_sync_service.rb` (chamada explícita, uma vez) |
| BE-184 | build | `models/receivable_tax.rb` + `services/receivables/tax_service.rb` |
| BE-185 | build | `api/v1/wallets.rb`, `api/v1/receivable_kinds.rb` |
| BE-186 | build | `api/v1/movement_kinds.rb` + `models/movement_kind.rb` |
| BE-187 | build | `api/v1/charges.rb` + `models/charge.rb` |
| BE-188 | build | `services/charges/receipt_generator.rb` + `models/receipt.rb` |
| BE-189 | build | `services/charges/bulk_receipts_service.rb` |

### `receivables` — frontend (§2.2)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| FE-150 | build | `app/pages/receivables/ReceivablesPage.tsx` (9 colunas ordenáveis) |
| FE-151 | **reuse** | React Query `isLoading` vs `isFetching` |
| FE-152 | build | `components/ui/EmptyState.tsx` (**novo compartilhado**) |
| FE-153 | adapt | `EmptyState` variante com termo pesquisado |
| FE-154 | **reuse** | React Query `isError`/`refetch` + `sonner` |
| FE-155 | adapt | `hooks/useDebouncedValue.ts` (extraído de `ImpersonateSearch.tsx:46-52`) |
| FE-156 | build | `components/ui/DateRangePicker.tsx` (**novo compartilhado**) |
| FE-157 | **reuse** | `ui/SearchableSelect.tsx` — filtro por carteira |
| FE-158 | **reuse** | `ui/SearchableSelect.tsx` — portadores do projeto corrente |
| FE-159 | adapt | `components/ui/SortableTableHeader.tsx` |
| FE-160 | adapt | `components/ui/Pagination.tsx` (desktop) + `mobile/MobilePagination.tsx` |
| FE-161 | build | Guarda de portador + botão oculto para somente-leitura |
| FE-162 | build | `components/receivables/ReceivableRow.tsx` (data, moeda e CET em pt-BR) |
| FE-163 | build | `components/ui/RowActionsMenu.tsx` + `ConfirmDialog.tsx` (**novos**) |
| FE-164 | build | `hooks/usePermission.ts` (**novo compartilhado**) |
| FE-165 | build | `app/pages/receivables/ReceivableFormPage.tsx` (10 grupos, ~40 campos) |
| FE-166 | build | `EmptyState` — sem portador, formulário suprimido com a razão |
| FE-167 | build | `EmptyState` + atalho para cadastrar empresa (também na edição) |
| FE-168 | adapt | `components/ui/MoneyInput.tsx` (**novo compartilhado**) |
| FE-169 | adapt | `components/ui/DecimalInput.tsx` |
| FE-170 | adapt | `components/ui/IntegerInput.tsx` |
| FE-171 | build | `api/v1/receivables.rb#preview` + `hooks/useReceivablePreview.ts` — **C2** |
| FE-172 | build | 5 combinações bloqueiam salvar **e** o servidor responde 422 |
| FE-173 | build | Barra inferior; grava **uma vez** e volta à lista |
| FE-174 | build | Conversão numérica no envio + reformatação depois |
| FE-175 | build | `components/receivables/TaxRows.tsx` |
| FE-176 | build | Exclusão de tarifa com confirmação, recálculo no servidor |
| FE-177 | build | `components/ui/DatePicker.tsx` (**novo compartilhado**) |
| FE-178 | **reuse** | `sonner` + formato de erro de `lib/api/client.ts` |
| FE-179 | build | `app/pages/charges/ChargesPage.tsx` (lista paginada) |
| FE-180 | **reuse** | 3× `ui/SearchableSelect.tsx` (situação, mês, ano com opção em branco) |
| FE-181 | build | `components/charges/ChargeRow.tsx` |
| FE-182 | adapt | `app/pages/charges/ChargeDetailPage.tsx` sobre `kpi/KpiCard.tsx` |
| FE-183 | build | "Faturado" bloqueia seleção na tela **e** no servidor |
| FE-184 | build | `app/pages/charges/ChargeReceiptsPage.tsx` |
| FE-185 | build | Inclusões/remoções num único lote; falha reverte a marcação |
| FE-186 | adapt | `components/charges/ChargeDrawer.tsx` sobre `SideDrawer.tsx` |
| FE-187 | build | `app/pages/catalogs/WalletsPage.tsx` |
| FE-188 | build | `app/pages/catalogs/ReceivableKindsPage.tsx` |
| FE-189 | build | `app/pages/catalogs/MovementKindsPage.tsx` |

### `receivables` — dados (§2.3)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| DB-150 | build | `receivable_entries` (60 colunas, UUID PK, ~7,7 mil registros) |
| DB-151 | build | FKs de `receivable_entries`; `nro_bordero` como **string** |
| DB-152 | build | 18 colunas `decimal(15,2)` (D-B4) |
| DB-153 | build | Prazos, floats, taxas e 7 CETs em `decimal` — resultado idêntico ao float |
| DB-154 | build | `company_id` obrigatório; empresa padrão para borderôs anteriores a 03/2022 |
| DB-155 | build | `description` visível; `observacoes` migrada sem tela (Q-B18) |
| DB-156 | build | Tipo/subtipo de operação **opcionais** ("Não associar") |
| DB-157 | build | Colunas `legacy_id`/`legacy_*` (proveniência Django, DEC-12) |
| DB-158 | build | `wallets` — catálogo global, índice único em título |
| DB-159 | build | `receivable_kinds` |
| DB-160 | build | `movement_kinds` (`kind` com domínio fechado) |
| DB-161 | build | `receivable_taxes` + índice em `receivable_entry_id` |
| DB-162 | build | `charges` (`state` com check constraint) |
| DB-163 | build | `receipts` (operação polimórfica, índice único) |
| DB-164 | build | `date` e `operation_title` como fotografia da operação |
| DB-165 | build | `receipt_id` em `risk_operations` e `structured_operations` |
| DB-166 | build | Migrations de índice |
| DB-167 | build | `scripts/etl/receivables/` (5 mapeamentos de origem) |

### `receivables` — operação (§2.4)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| OPS-150 | build | `scripts/etl/receivables/report.rb` (registros marcados pelo ETL Django) |
| OPS-151 | build | `jobs/receivables/bulk_recalculate_job.rb` |
| OPS-152 | **reuse** → `dropped` | Não há `establish_connection` alternativo; nada a fazer (DEC-12) |
| OPS-153 | build | `db/seeds/receivables_catalogs.rb` (idempotente, 10 carteiras) |
| OPS-154 | build | `config/receivables_help_inputs.yml` + `services/receivables/help_texts.rb` |
| OPS-155 | **reuse** → `dropped` | Sem geração de PDF (DEC-09 / D-84) |
| OPS-156 | **reuse** → `dropped` | Sem exportação de planilha (DEC-09) |
| OPS-157 | build | `ILIKE` com termo sanitizado (`%`/`_` literais) |
| OPS-158 | build | Limite ausente **omite** a cláusula (fim de `DateTime.dinosaurs`/`.mars`) |
| OPS-159 | adapt | `lib/format/money.ts` + helper equivalente no backend (D-117) |

## Perguntas em aberto que afetam esta fatia

Todas com default declarado no mapa (§5); nenhuma bloqueia o início. As que mudam número
exibido estão marcadas.

| # | Assunto | Default adotado | Muda número? |
| - | ------- | --------------- | ------------ |
| Q-B5 | Reprocessar o histórico de operações de risco geradas por borderô (D-11) | **recalcular**, com relatório de quantos mudaram e de quanto | **sim** |
| Q-B6 | `calc_valor_liq_correto` é aproximação linear proposital? (D-14) | replicar como está | não |
| Q-B7 | Guarda do CET do banco olha o prazo da empresa | replicar como está | não |
| Q-B8 | 2 casas em `custo_efetivo_com_float_total` vs 4 em `custo_efetivo_pz_med_emp` | replicar como está | não |
| Q-B9 | Não existe baixa/liquidação/vencimento de recebível (D-19) | não inventar (DEC-09) | não |
| Q-B10 | `nominal_tax` informada não é validada contra as checagens | continua informativa | não |
| Q-B11 | Sem janela de data e sem `valor_bruto > 0` | manter como hoje | não |
| Q-B12 | `is_active` de carteira/tipo nunca aplicado (D-19) | continua sem efeito | não |
| Q-B13 | `is_title`/`is_liquidation` sem consumidor (D-74) | portar as colunas, sem consumidor | não |
| Q-B14 | Remuneração é percentual flat, sem prazo (D-72) | replicar a fórmula | não |
| Q-B15 | Tipo de tarifa duplicado no mesmo borderô | continua permitido | não |
| Q-B16 | Excluir tarifa persistida tem efeito imediato | manter | não |
| Q-B17 | `resource_kind_id` nunca preenchido | migrar como proveniência | não |
| Q-B18 | `observacoes` sem tela | migrar sem tela | não |
| Q-B19 | ETL Django forçava `user_id = 1` / `company_id = 1` (2016-2021) | manter, com relatório | não |
| Q-B20 | Os ~40 textos de ajuda do formulário são placeholder no legado | portar o **mecanismo**; conteúdo fica em branco | não |


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| BE-445 | build | **`Entry` — a classe base abstrata dos lançamentos.** "Diferença" e "OK" deixam de ser strings em pt-BR gravadas na coluna e comparadas por igualdade de texto; viram `enum` em `ReceivableEntry`, com o rótulo na apresentação | **C4**: quem constrói é dono. `ReceivableEntry` nasce aqui, antes de `AvailabilityEntry` (S11) |
| BE-446 | build | `MovementKind` — chave de integração derivada do título quando `integration_key` vem em branco | S6 é dona de `movement_kinds` |
| BE-447 | build | Exclusividade de tipo de taxa: um tipo de movimentação é **no máximo um** entre AdValorem, Deságio e os demais | idem |
| BE-448 | build | Dependências protegidas de `MovementKind`: não pode ser removido se tiver recebíveis ou taxas | idem |
| DB-433 | build | `movement_kinds` visto pela capability `misc-domain` | idem |
| DB-563 | build | `movement_kinds` visto por `data-schema` — tabela + seed (17 linhas) | idem |
| DB-559 | build | `wallets` — tabela + seed (10 linhas) | as carteiras são do bloco de recebíveis, e ficaram com S6 |
| DB-560 | build | `receivable_kinds` — tabela + seed (5: Cheque, Duplicata, Cartão de crédito, ACC, PAC) | idem |
| DB-564 | build | `receivable_entries` (~70 colunas) | S6 é dona do borderô |
| DB-565 | build | `receivable_taxes` | idem |

**`BE-445` foi o caso mais discutível dos 175, e a decisão está escrita.** `Entry` é
transversal — `AvailabilityEntry` (S11) herda dele —, o que o tornava candidato a uma fatia
de transversais. Fica aqui pelo contrato **C4**: `ReceivableEntry` é construído nesta fatia,
que roda antes de S11, e **quem constrói é dono**. S11 consome e referencia.

**A conversão dos textos é tarefa de ETL com relatório linha a linha:** a coluna do legado
guarda pt-BR comparado por igualdade de texto, e qualquer mudança de rótulo quebrava a
comparação em silêncio.
