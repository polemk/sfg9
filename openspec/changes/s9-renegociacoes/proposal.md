# Proposal: S9 — Renegociações: parcelas, pagamentos, anexos

## Why

A renegociação é o outro lado do balcão do Safegold: a dívida negociada com um fornecedor,
parcelada, paga ao longo do tempo e documentada por anexos. São **98 IDs de inventário** na
capability `renegotiations`, e **nada disso existe na base ai9** depois do trim.

Esta fatia existe por quatro razões:

1. **Os ~20 agregados derivados são o painel que o cliente lê.** `main_value`,
   `paid_percent`, `remaining_value`, `current_value` e companhia são recalculados a cada
   alteração de parcela ou pagamento. No legado eles vivem em `Renegotiation#update_values`
   (`app/models/renegotiation.rb:89-127`) e em `RenegotiationInstallment#update_values`
   (`:59-69`), com um `save` sem bang que **descartava o recálculo em silêncio**. No ai9
   vão para um serviço único, `Renegotiations::AggregateService`, com **golden test por
   agregado** (C2 / D-B3).
2. **Há perda de dado documentada.** O `batch_destroy_installments!` do legado
   (`renegotiation.rb:61-70`) reporta remoção **parcial** como falha total — o usuário
   reexecutava e apagava parcelas a mais (**D-51**). E o `destroy` da renegociação usa o
   ternário `errors.any? ? :ok : :ok` com template de resposta **vazio**: a tela mostrava
   sucesso e o registro voltava (**D-24**).
3. **Os anexos carregam cinco defeitos de segurança (D-82).** Sem verificação de permissão
   no download, `disposition: inline` com content-type do uploader (XSS armazenado na mesma
   origem), arquivo alcançável por caminho direto em `public/system/…`, validação de tipo
   desligada (`do_not_validate_attachment_file_type` + spoof detector monkey-patchado para
   `false`), e regra de dono apenas visual.
4. **O escopo por projeto (C1).** Como em recebíveis, o legado descartava o filtro de
   projeto ao receber `renegotiation_id` — família **D-01 / D-16 / D-29 / D-76 / D-100**.

## What Changes

Entrega ponta a ponta as sub-fatias **SN-1 … SN-6** do mapa de bloco
(`.migration-ai9/map/receivables-renegotiations.md` §1): modelo e agregados, lista e CRUD,
previsões (parcelas) e pagamentos, detalhe com cards em tempo real, anexos privados, e a
carga de dados com auditoria prévia.

### Dependências

| Direção | O quê |
| ------- | ----- |
| S9 depende de | **S0** (`Project`, `Membership`, `current_project!`, papéis), **S4** (projeto, empresas e **fornecedores**) |
| S9 depende de infra ai9 | ActiveStorage (privado), Action Cable (`useCable.ts`), `sidekiq-cron` |
| S9 reusa de S6 | Os primitivos compartilhados criados em S6: `EmptyState`, `SortableTableHeader`, `Pagination`, `RowActionsMenu`, `ConfirmDialog`, `MoneyInput`, `DecimalInput`, `DatePicker`, `useDebouncedValue`, `usePermission`, `lib/format/money.ts`. **Se S9 rodar antes de S6, esses primitivos nascem aqui** — são biblioteca compartilhada, não peça de tela |
| Dependem de S9 | **S14** (ETL) |

S9 é **independente de `risk`, `structured-operations` e `receivables`** no backend — pode
correr em paralelo a S6.

### Decisões que governam esta fatia

- **DEC-02 / D-104 — aritmética em float é REPLICADA.** Melhoria **declinada** pelo usuário
  (`.migration-ai9/improvements-log.md`). Inclui: o truncamento da 3ª casa na máscara de
  entrada (`1,239` → `1,23`), que é o **primeiro passo** da cadeia de arredondamento que
  produz os totais atuais; a assimetria entre `pending_main_value` (pode ficar negativo) e
  `remaining_value` (piso em zero); e o valor presente que **sobrescreve**
  `current_installment_value`. QA **não** deve ler nada disso como regressão.
- **Limites de arquivo viram configuração.** `MAX_FILES_PER_RENEGOTIATION` (**4**) e
  `MAX_FILE_SIZE` (**5 MB**) eram constantes Ruby em `SFG::Metadata`; no ai9 viram config /
  ENV com **os mesmos valores padrão** — comportamento idêntico, ajustável **sem deploy**
  (registrado em `improvements-log.md`). O limite passa a valer **no servidor**, não só na
  tela (D-50).
- **D-B7 — `Medium` NÃO é reusado como está** (`medium.rb:12` restringe `media_type` a
  `image`/`video`, e anexo de renegociação é majoritariamente PDF), e
  `AssetsProxyController` **não é reusado de forma alguma** (serve `public/uploads/**`
  inline e sem auth — é literalmente o D-82).
- **D-B5 / D-B6 — os cards de resumo atualizam por Action Cable, e o cron diário some.**
  `overdue_installments` deixa de ser coluna atualizada por cron e vira **cálculo em
  consulta**: o número não muda, muda **quando** fica correto (elimina a janela de 24 h e o
  caso da renegociação liquidada que nunca mais era reprocessada). Polling é proibido
  (Princípio 10).

## Impact

- **Afetado:** `backend/app/{controllers/api/v1,controllers/api/entities,models,services,channels}`,
  `backend/db/migrate` + `schema.rb`, `backend/spec/**`,
  `frontend/src/{app/pages/renegotiations,components/renegotiations,hooks}`,
  `scripts/etl/renegotiations/`.
- **Migração de binários de disco:** os anexos legados vivem em `public/system/…` no disco
  do servidor legado. Sem acesso a esse disco, os arquivos não migram — dependência externa.
- **Novo canal:** `channels/renegotiation_channel.rb` + `hooks/useRenegotiationChannel.ts`.
- **Não afetado:** o legado `sfg` (read-only).
- **Requirements:** já existem em `openspec/specs/renegotiations/spec.md` (98 requirements,
  um por ID). **Não são recriados aqui.**

## IDs de inventário cobertos (98)

Estratégia copiada de `.migration-ai9/map/receivables-renegotiations.md` §2.5–§2.8.
**Placar: 73 `build` · 13 `adapt` · 12 `reuse`** (dos quais 3 entram no ledger como
`dropped` com evidência).

### `renegotiations` — backend (§2.5)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| BE-190 | build | `api/v1/renegotiations.rb#search` (busca cobre `title` **e** `provider_name`) |
| BE-191 | build | Filtro por 4 estados, incluindo `empty` (corrige D-49) |
| BE-192 | build | Filtro por Financeiro/Operacional/Tributario/Trabalhista |
| BE-193 | build | Ordenação acumulada por `title` e `provider_name` |
| BE-194 | build | `l`/`o` aplicados de fato, padrão 20 (corrige D-20) |
| BE-195 | build | `#general_values` + `services/renegotiations/aggregate_service.rb` (corrige D-48) |
| BE-196 | build | `api/entities/renegotiation.rb` com `installment_status` derivado |
| BE-197 | **reuse** → `dropped` | 6 rotas REST mortas (nenhum template existe em disco) |
| BE-198 | build | `services/renegotiations/create_service.rb` (recalcula na criação) |
| BE-199 | build | `models/renegotiation.rb` — `correct_value = total_debt`, `integration_key` única |
| BE-200 | build | `services/renegotiations/update_service.rb` |
| BE-201 | build | `#destroy` — só sem parcelas/pagamentos; anexos vão junto (corrige D-24) |
| BE-202 | build | `services/renegotiations/batch_destroy_installments.rb` (corrige D-51) |
| BE-203 | build | `services/renegotiations/renumber_installments.rb` |
| BE-204 | build | `aggregate_service.rb` — somas de principal, juros e CM; `main_value` |
| BE-205 | build | `paid_value_with_interest_cm`, `late_payment_value`, `pending_main_value`, `paid_value` |
| BE-206 | build | `paid_percent` sem divisão por zero; > 100% aceito |
| BE-207 | build | `remaining_value`, `paid/overdue/due_installments` (vencidas na consulta) |
| BE-208 | build | `installments_count`, `first/last_due_date`, `total_value_with_desagio` |
| BE-209 | build | `aggregate_service.rb#state` — 4 estados (corrige D-45) |
| BE-210 | build | `unposted_value` e `installment_status` |
| BE-211 | build | Parcela do mês e próxima parcela em aberto, em consulta agregada |
| BE-212 | build | `aggregate_service.rb#current_value` — VP da dívida (D-46) |
| BE-213 | build | `api/v1/renegotiation_installments.rb#search` |
| BE-214 | build | `#create` — data ausente → 422; repetições não numéricas → 422 |
| BE-215 | build | `services/renegotiations/create_installment.rb` |
| BE-216 | build | `services/renegotiations/create_installments_batch.rb` (Dias/Semanas/Meses) |
| BE-217 | build | Derivações da parcela + identidade e cor do lote (corrige D-52) |
| BE-218 | build | `models/renegotiation_installment.rb` + índice único `(renegotiation_id, due_date)` |
| BE-219 | build | `services/renegotiations/recalculate_installment.rb` — mora, total, pago, saldo |
| BE-220 | build | Renumera pagamentos, recalcula parcela, propaga; falha é revertida |
| BE-221 | build | `#update/#destroy` de parcela |
| BE-222 | build | `api/v1/renegotiation_payments.rb#search` — ordem determinística |
| BE-223 | build | `services/renegotiations/create_payment.rb` — `days_late`, teto no pendente |
| BE-224 | build | `#update/#destroy` de pagamento — recalcula **uma vez** |
| BE-225 | build | `api/v1/renegotiation_attachments.rb#search` (a rota do legado nunca funcionou) |
| BE-226 | **adapt** | `models/renegotiation_attachment.rb` (`has_one_attached :file`) + `attachment_service.rb` |
| BE-227 | **adapt** | `#download` autorizado, `Content-Disposition: attachment` sempre |
| BE-228 | **reuse** → `dropped` | Renomear anexo não é portado (D-62/DEC-11: `NameError` garantido) |
| BE-229 | build | `#destroy` de anexo — só o autor, **checado no servidor** |

### `renegotiations` — frontend (§2.6)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| FE-190 | build | `app/pages/renegotiations/RenegotiationsPage.tsx` (13 colunas) |
| FE-191 | adapt | `EmptyState` + React Query — 4 estados do container |
| FE-192 | **reuse** | `hooks/useDebouncedValue.ts` |
| FE-193 | **reuse** | `ui/SearchableSelect.tsx` — filtros de estado e tipo |
| FE-194 | **reuse** | `components/ui/SortableTableHeader.tsx` |
| FE-195 | **reuse** | `components/ui/Pagination.tsx` |
| FE-196 | build | `components/renegotiations/RenegotiationRow.tsx` |
| FE-197 | build | Guarda de fornecedor; botão some para somente-leitura |
| FE-198 | **reuse** | `ui/dialog.tsx` + `sonner` — erro real do servidor exibido |
| FE-199 | build | `app/pages/renegotiations/RenegotiationFormPage.tsx` (13 campos) |
| FE-200 | build | `EmptyState` — sem fornecedor / sem empresa, com atalho |
| FE-201 | **reuse** | `MoneyInput`/`DecimalInput` — **truncamento da 3ª casa preservado** |
| FE-202 | **reuse** | `components/ui/DatePicker.tsx` |
| FE-203 | **reuse** | `sonner` + formato de erro de `lib/api/client.ts` |
| FE-204 | adapt | `RenegotiationDetailPage.tsx` — abas com **deep-link real** (corrige D-92) |
| FE-205 | build | `components/renegotiations/RegistrationCard.tsx` |
| FE-206 | adapt | `components/renegotiations/SummaryCards.tsx` sobre `kpi/KpiCard.tsx` |
| FE-207 | build | `hooks/useRenegotiationChannel.ts` + `channels/renegotiation_channel.rb` |
| FE-208 | adapt | `components/renegotiations/AttachmentGallery.tsx` — miniatura **de variante** |
| FE-209 | build | `components/renegotiations/FilesSection.tsx` — limite comunicado de verdade |
| FE-210 | adapt | `components/ui/FileDropzone.tsx` (**novo compartilhado**) |
| FE-211 | build | Ação de excluir só para o autor — **e o servidor recusa** |
| FE-212 | build | Download pelo endereço **autorizado** |
| FE-213 | build | `components/renegotiations/InstallmentsTab.tsx` (12 colunas) |
| FE-214 | build | Estados de carga / vazio / **erro** na lista de parcelas |
| FE-215 | adapt | `components/renegotiations/InstallmentRow.tsx` sobre `ui/accordion.tsx` |
| FE-216 | build | Gerar pagamento / editar / remover (só sem pagamento) |
| FE-217 | build | Modo seleção; "Selecionar todos" pega só as sem pagamento |
| FE-218 | build | Confirmação de remoção em lote que **não expira** |
| FE-219 | build | Parcela com pagamento não recebe caixa de seleção |
| FE-220 | adapt | `components/renegotiations/InstallmentDrawer.tsx` (3 modos) |
| FE-221 | build | `hooks/useInstallmentPreview.ts` — totais derivados vêm **do servidor** |
| FE-222 | build | Salvar só com principal > 0 — **e o servidor responde 422** |
| FE-223 | build | Fecha em sucesso restaurando o endereço; falha mantém os valores |
| FE-224 | adapt | `components/renegotiations/PaymentDrawer.tsx` — **data editável** (D-B12) |
| FE-225 | build | Pago Total calculado; salvar bloqueado com zero e acima do pendente |
| FE-226 | build | Painel **fecha** após salvar; lista e cards atualizados |
| FE-227 | build | Editar/excluir pagamento pela sublinha, com endereço correto |
| FE-228 | **reuse** | `hooks/usePermission.ts` — escrita suprimida **e** recusada |
| FE-229 | **reuse** → `dropped` | Aba PAGAMENTOS e "excluir todas as parcelas" (comentados no legado) |

### `renegotiations` — dados (§2.7)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| DB-190 | build | `create_renegotiations` — ~20 agregados, FKs, `kind`/`state` fechados |
| DB-191 | build | `create_renegotiation_installments` — único `(renegotiation_id, due_date)` |
| DB-192 | build | `create_renegotiation_payments` — coerência renegociação × parcela no banco |
| DB-193 | build | `create_renegotiation_attachments` — ActiveStorage, armazenamento privado |
| DB-194 | build | ETL: renomeações de 29/04/2022 com mudança de semântica |
| DB-195 | build | `attachments_count` `null: false, default: 0`, sempre coerente |
| DB-196 | build | `decimal(15,2)` para dinheiro, float para percentuais/taxas (D-B4) |
| DB-197 | build | `has_safegold_management` — carimbo copiado, nunca ressincronizado |
| DB-198 | build | FKs em todas as referências + índices das consultas quentes |
| DB-199 | build | `scripts/etl/renegotiations/audit.rb` — auditoria **antes** da carga |

### `renegotiations` — operação (§2.8)

| ID | Estratégia | Alvo ai9 |
| -- | ---------- | -------- |
| OPS-190 | build | Vencidas em consulta; **o cron diário deixa de existir** (D-54, D-B6) |
| OPS-191 | **adapt** | `sidekiq-cron` — uma definição versionada, com **trava de concorrência** |
| OPS-192 | **adapt** | ActiveStorage com serviço privado; arquivo **não** fica em `public/` |
| OPS-193 | **adapt** | Dimensões vindas de `blob.metadata`; **nenhum processo externo por render** |
| OPS-194 | build | Tipo verificado **pelo conteúdo** (Marcel), com allowlist |
| OPS-195 | build | `renumber_installments.rb` / `renumber_payments.rb` com `update_all`, sem callbacks |
| OPS-196 | build | `services/renegotiations/batch_color.rb` — cor por lote, **com terminação garantida** |
| OPS-197 | build | `scripts/etl/renegotiations/fixups.rb` — empresa padrão, recálculo em lotes |

## Perguntas em aberto que afetam esta fatia

Todas com default declarado no mapa §5; nenhuma bloqueia o início.

| # | Assunto | Default adotado | Muda número? |
| - | ------- | --------------- | ------------ |
| Q-B21 | Renegociação aceita `original_value = 0`, `total_debt` negativo, taxa negativa | continua aceitando | não |
| Q-B22 | `pending_main_value` pode ficar negativo; `remaining_value` tem piso em zero | preservar a assimetria | não |
| Q-B23 | "A vencer" (`due_installments`) **inclui** as vencidas | preservar a semântica | não |
| Q-B24 | `interest_rate_correction` e `grace_period` nunca são lidos (D-47) | `correct_value = total_debt` sempre; campos fora da tela | não |
| Q-B25 | O VP **sobrescreve** `current_installment_value` (D-46) | replicar; é número que o cliente lê | não |
| Q-B26 | A mora entra **dos dois lados** da conta da parcela | replicar (pagar só a mora pode quitar) | não |
| Q-B27 | Renomear anexo nunca foi entregue (`NameError` garantido) | fora de escopo por DEC-09 | não |
| Q-B28 | O detalhe usa `provider_name` na rota e a lista mostra `title` | manter, sinalizar ao usuário | não |
| Q-B29 | Aba PAGAMENTOS e "excluir todas as parcelas" estão comentadas (D-53) | não portar (DEC-09) | não |
| Q-B30 | Pagamento não registra forma de pagamento nem conciliação bancária | ausência preservada | não |
| Q-B31 | Três colunas renomeadas em 29/04/2022 com mudança de semântica | migrar com os nomes novos | não |
| Q-B32 | `has_safegold_management` copiado, nunca lido (D-30) | portar a coluna | não |


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-568 | build | `renegotiations` | S9 é dona da renegociação |
| DB-569 | build | `renegotiation_installments` | idem |
| DB-570 | build | `renegotiation_payments` | idem |
| DB-571 | build | `renegotiation_attachments` + `has_one_attached :file` — as colunas Paperclip somem; os limites (4 arquivos, 5 MB) vêm da configuração de anexos | idem |

**Os quatro são as mesmas tabelas que a fatia já constrói**, vistas pelo inventário de
`data-schema`. `DB-571` é o único com dependência externa: o motor único de anexos é de
**S13**, e esta fatia **consome** — não abre um segundo caminho de upload.

## Fronteiras — dono único dos IDs em disputa (contrato C4)

> O fechamento do Phase 2 encontrou **27 IDs com dois donos**. A regra é **um ID, um dono**:
> quem constrói a coisa é dono, quem consome referencia. A outra fatia pode citar o ID, mas
> **nunca com tarefa própria**. O risco nunca foi construir duas vezes — foi as duas fatias
> apontarem uma para a outra e ninguém construir.

- **`BE-207` é de S9**, disputado com S15. `Renegotiation#update_values` —
  `remaining_value`, `paid`/`overdue`/`due_installments` — é cálculo de domínio da
  renegociação e nasce aqui, com teste. **S15 consome**: o cartão "Renegociações em atraso"
  do dashboard lê este contador; não o recalcula.
