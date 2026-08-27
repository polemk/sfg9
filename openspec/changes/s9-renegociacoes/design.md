# Design: S9 — Renegociações em ai9

> O mapa item-a-item **não é duplicado aqui**. Cada grupo referencia
> `.migration-ai9/map/receivables-renegotiations.md`: §2.5 backend · §2.6 frontend ·
> §2.7 dados · §2.8 operação · §3 decisões (D-B1…D-B15) · §4 lacunas do ai9 · §5 perguntas ·
> §6 correções ao catálogo e flags de upstream.

## 1. `Renegotiations::AggregateService` — o cálculo único (C2, D-B3)

### Onde a conta vive hoje

| Legado | Linhas | O que faz |
| ------ | ------ | --------- |
| `Renegotiation#update_values` | `app/models/renegotiation.rb:89-127` | ~20 agregados: somas de principal/juros/CM, pagos, pendente, percentual, contagens, datas, estado |
| `Renegotiation#unposted_value` / `#installment_status` | `:140-155` | Consistência de lançamento contra `total_debt` |
| `Renegotiation#calculate_current_installment_value` | `:157-161` | Parcela do mês corrente |
| `Renegotiation#calculate_next_installment_value/_date` | `:162-173` | Próxima parcela em aberto |
| `Renegotiation#calculate_current_value` | `:175-183` | **VP da dívida** — e **reatribui** `current_installment_value` (D-46) |
| `RenegotiationInstallment#update_values` | `app/models/renegotiation_installment.rb:59-69` | Mora, total, pago, saldo, `is_paid` |
| `RenegotiationPayment` `before_validation` | `app/models/renegotiation_payment.rb:11-14` | `days_late`, `total_paid_value` |

Três problemas estruturais nesse arranjo, todos com defeito catalogado:

- `update_values!` (`renegotiation.rb:83-86`) faz `save` **sem bang**: falha de validação
  **descarta o recálculo em silêncio** (D-79). O agregado e a parcela divergem e ninguém
  fica sabendo.
- `overdue_installments` (`:109`) é coluna persistida, atualizada por **cron diário** —
  até 24 h desatualizada, e a renegociação liquidada nunca mais era reprocessada (D-54).
- `after_save` no pagamento (`renegotiation_payment.rb:16-22`) dispara a cascata
  parcela → renegociação. Combinado com `update` + `save` redundante, **roda em
  duplicidade**.

### Forma no ai9

`backend/app/services/renegotiations/aggregate_service.rb` — segue o padrão de service do
ai9 (`ai9-conventions.md` §3.6, `class << self`), mas com a mesma disciplina do
`Receivables::Calculator`: **as fórmulas são funções puras** sobre valores já carregados; o
serviço faz **uma** consulta agregada para carregar o que precisa e **uma** gravação
transacional no fim.

```ruby
# backend/app/services/renegotiations/aggregate_service.rb
module Renegotiations
  class AggregateService
    # Recalcula e PERSISTE os ~20 agregados. Uma consulta agregada, uma transação,
    # broadcast único no fim. Levanta em caso de falha — nunca `save` sem bang.
    def self.recalculate!(renegotiation) = new(renegotiation).recalculate!

    # Mesmas fórmulas, SEM persistir. É o que a prévia da tela consome.
    def self.preview(renegotiation, draft:) = new(renegotiation).preview(draft)
  end
end
```

| Item | Regra |
| ---- | ----- |
| Aritmética | **Float**, na ordem do legado, com os mesmos `round` (DEC-02 / D-104). Armazenamento em `decimal(15,2)` para dinheiro e float para percentuais/taxas (D-B4 / DB-196) |
| `overdue_installments` | **Cálculo em consulta**, não coluna atualizada por cron (D-B6). O número não muda — muda **quando** fica correto |
| Persistência | `recalculate!` levanta em falha e é **revertida**; nunca `save` sem bang |
| Cascata | Pagamento → parcela → renegociação, **explícita e uma vez só**, dentro de uma transação. Não por `after_save` |
| Renumeração | `update_all`, **sem callbacks**, para não recursar no recálculo (OPS-195). Só o ordinal muda |
| Broadcast | Um `renegotiation_channel` no fim da transação (D-B5). **Polling é proibido** |

### Quem chama

```
POST /renegotiation_installments/preview ─┐
                                          ├─→ AggregateService.preview  (não persiste)
Renegotiations::CreateService ────────────┐
Renegotiations::UpdateService             │
Renegotiations::CreateInstallment(sBatch) ├─→ AggregateService.recalculate! ─→ broadcast
Renegotiations::RecalculateInstallment    │
Renegotiations::Create/Update/DestroyPayment ┘
Renegotiations::BatchDestroyInstallments ─┘
```

Como em S6, **a prévia da tela e a gravação passam pelo mesmo serviço** — é o mesmo D-09,
aplicado ao drawer de parcela (FE-221): os totais derivados da parcela vêm do servidor, não
de conta em JS.

### As fórmulas que ganham golden test, e as três que doem

Golden test por agregado, alimentado com valores extraídos do legado (D-B3; o legado não
tem nenhum teste, D-114). Três merecem destaque porque **parecem erro e são replicadas de
propósito**:

1. **A mora entra dos dois lados** (`renegotiation_installment.rb:62-64` +
   `renegotiation_payment.rb:13`): `late_payment_value` soma ao `installment_total_value`
   (o devido) **e** ao `total_paid_value` (o pago). Consequência observável: **pagar só a
   mora pode quitar a parcela** (BE-219, Q-B26).
2. **A assimetria do "quanto falta"** (`renegotiation.rb:102` × `:107`):
   `pending_main_value` pode ficar **negativo**, enquanto `remaining_value` é a soma de
   `pending_value` das parcelas, que tem **piso em zero** (`renegotiation_installment.rb:66`).
   São dois números que medem a mesma coisa com regras diferentes (BE-205, Q-B22).
3. **O VP sobrescreve a coluna "Valor Parcela"** (`renegotiation.rb:175-183`):
   `calculate_current_value` termina reatribuindo `current_installment_value = vp.round(2)`.
   Sempre que há juros > 0 e saldo em aberto, a coluna passa a mostrar outra coisa (BE-212,
   D-46, Q-B25). **É um número que o cliente lê** — mudar exige reconciliação, não
   iniciativa.

E uma que **é** corrigida: o estado "Inconsistente" (`renegotiation.rb:118-123`) é
sobrescrito pela linha seguinte, então o filtro da tela **nunca** retornava nada (D-45). No
ai9 os 4 estados são derivados numa única expressão, e "Sem parcela cadastrada" volta a
funcionar (D-49).

## 2. Escopo por projeto (C1) — como cai nesta fatia

Quatro superfícies aceitam id por parâmetro: `renegotiation_id`,
`renegotiation_installment_id`, `renegotiation_payment_id` e `attachment_id`. Todas passam
por `current_project!` **no endpoint**, nunca por `default_scope`.

Regras concretas, todas com defeito legado correspondente:

- **Busca:** `renegotiations#search` filtra por projeto **mesmo quando** `renegotiation_id`
  chega por parâmetro (BE-190 — o vazamento cross-tenant é o maior risco do bloco).
- **Coerência de pai:** um `renegotiation_installment_id` de **outra** renegociação é
  recusado no lote de exclusão (BE-202) e no pagamento (BE-223). Isso vale **também no
  banco** (DB-192: coerência renegociação × parcela garantida).
- **Edição por URL:** o `update` de pagamento **não** pode mudar a parcela pela URL
  (BE-222).
- **Download de anexo:** autorizado **por projeto**, não por posse de URL (BE-227).
- **Resposta uniforme:** id inexistente e id de outro projeto respondem **o mesmo status**.

## 3. Grupos de IDs → camada alvo em ai9

### Dados (DB-190…DB-199 — mapa §2.7)

| Grupo | Alvo | Decisão |
| ----- | ---- | ------- |
| Renegociação (DB-190, DB-196, DB-197) | `renegotiations` | ~20 agregados persistidos + cadastro; `kind` e `state` com **domínio fechado** (enum string + check constraint, D-B9); `decimal(15,2)` para dinheiro (D-B4). Corrige D-103 — **nenhuma** migration de renegociação do legado tem índice ou FK |
| Parcelas (DB-191) | `renegotiation_installments` | **Índice único** `(renegotiation_id, due_date)`; índices por renegociação, vencimento e `is_paid`. `saldo` negativo e `pending_value` positivo — a diferença de sinal fica documentada em `comment:` |
| Pagamentos (DB-192) | `renegotiation_payments` | Coerência renegociação × parcela **garantida no banco**, não só no serviço (corrige D-52 na raiz) |
| Anexos (DB-193, DB-195) | `renegotiation_attachments` + ActiveStorage | Metadados preservados, **tipo revalidado pelo conteúdo real** na carga, binários no armazenamento **privado**. `attachments_count` `null: false, default: 0` (o nulo fazia `nil > 0` → `NoMethodError`) |
| Índices e FKs (DB-198) | migrations de índice | A listagem deixa de ser quadrática em consultas |
| ETL (DB-194, DB-199) | `scripts/etl/renegotiations/` | **Auditoria antes da carga** é o gate: pagamentos com renegociação divergente, vencimentos duplicados, contadores errados, estados incoerentes |

### Backend (BE-190…BE-229 — mapa §2.5)

| Grupo | Alvo | Equivalente ai9 reaproveitado |
| ----- | ---- | ----------------------------- |
| Endpoints | `api/v1/{renegotiations,renegotiation_installments,renegotiation_payments,renegotiation_attachments}.rb` | Grape (`api/v1/base.rb`, `controller_helpers.rb`), `params do…end` declarativo, `set_pagination_headers` — corrige D-20 em **cinco** listagens |
| Serialização | `api/entities/renegotiation.rb` | `Grape::Entity` — substitui o `to_json` sobrescrito do legado, que quebrava a assinatura e levantava `ArgumentError` |
| Regra de negócio | `services/renegotiations/*.rb` | Padrão `class << self` + `ApiResponseHandler` |
| Realtime | `channels/renegotiation_channel.rb` | `application_cable/` + `permissions_channel.rb` como modelo; front `hooks/useCable.ts` (auth por cookie httpOnly `cable_token`). **Polling é proibido** (Princípio 10, D-B5) |
| Anexos | `models/renegotiation_attachment.rb` (`has_one_attached :file`) + `services/renegotiations/attachment_service.rb` | ActiveStorage (`config/storage.yml` → Disk) + Marcel (transitivo) + `image_processing`. `services/medium_service.rb` como **referência de estilo**, não como base |
| Download | `api/v1/renegotiation_attachments.rb#download` | `api/v1/downloads.rb:17-40` (entrega de binário atrás de checagem de permissão) como modelo |
| Agendamento | `sidekiq-cron` (`Gemfile:38`) + `config/initializers/sidekiq.rb` | Uma definição versionada, com retry, alerta e **trava de concorrência** — substitui o crontab por host sem trava (dois hosts = processamento em duplicidade) e os 3 arquivos de agendamento do legado |

### Anexos — o desenho de segurança (D-B7 / D-82 / OPS-192, OPS-194)

O que **não** é reusado, e por quê (mapa §6, C-1/C-2/C-3):

| Peça do ai9 | Por que não serve |
| ----------- | ----------------- |
| `models/medium.rb` | `:12` restringe `media_type` a `%w[image video]`; anexo de renegociação é majoritariamente **PDF**. A tabela `media` também não tem tamanho, nome original nem content-type |
| `AssetsProxyController` | `:5-27` serve qualquer arquivo sob `public/uploads/**` com `disposition: 'inline'` e **sem nenhuma autenticação**. É literalmente o padrão do D-82 |
| `api/v1/uploads.rb` | `:17-45` só trata `resource :avatar`, exige `image/*` e grava em `public/uploads/avatars` |

O que é construído no lugar:

1. `has_one_attached :file` com **serviço privado** — o binário nunca fica em `public/`.
2. Validação de tipo **pelo conteúdo** (Marcel), com allowlist — não pela extensão nem pelo
   content-type informado pelo uploader. O legado tinha
   `do_not_validate_attachment_file_type` **e** o spoof detector monkey-patchado para
   `false`.
3. Limites **no servidor**, vindos de configuração:
   `MAX_FILES_PER_RENEGOTIATION = 4` e `MAX_FILE_SIZE = 5.megabytes` — mesmos valores
   padrão das constantes de `SFG::Metadata`, agora **ajustáveis sem deploy**
   (`improvements-log.md`). No legado a checagem lia `.lesson_attachment_content_wrapper`,
   seletor **de outro produto**, comparando com `NaN` (D-50).
4. `#download` autorizado **por projeto**, nome original preservado,
   `Content-Disposition: attachment` **sempre**; arquivo ausente → 404 legível.
5. `#destroy` só pelo autor, **checado no servidor** — no legado a regra de dono era só
   visual.
6. Dimensões de imagem vindas de `blob.metadata` persistido, **nenhum processo externo por
   render** (o legado chamava 2 processos por imagem a cada renderização e derrubava o
   detalhe com 500 quando o arquivo sumia).

**Requisito de plataforma, não desta fatia:** `config/storage.yml` usa `service: Disk`
também em produção. Anexo de renegociação é documento financeiro — Disk em produção exige
**volume persistente garantido**. Registrado como flag **F-4** em
`.migration-ai9/upstream-flags.md`; sem isso, o cenário "perda de volume não derruba a tela"
não é atingível.

### Frontend (FE-190…FE-229 — mapa §2.6)

| Grupo | Alvo | Equivalente ai9 reaproveitado |
| ----- | ---- | ----------------------------- |
| Lista | `RenegotiationsPage.tsx` | `ui/Table.tsx`, `PageHeader.tsx` + os primitivos compartilhados de S6 (`SortableTableHeader`, `Pagination`, `EmptyState`, `useDebouncedValue`) |
| Formulário | `RenegotiationFormPage.tsx` | `ui/{Input,Label,SearchableSelect,textarea}.tsx`; `MoneyInput`/`DecimalInput` com o **truncamento da 3ª casa preservado** (FE-201 — é o primeiro passo da cadeia de arredondamento do DEC-02, não bug de máscara) |
| Detalhe | `RenegotiationDetailPage.tsx` | `ui/tabs.tsx` + `react-router-dom` — **deep-link e histórico reais** (corrige D-92: no legado o estado de navegação vivia só em memória JS e o Voltar saía do console) |
| Cards de resumo | `SummaryCards.tsx` + `useRenegotiationChannel.ts` | `kpi/KpiCard.tsx` + `hooks/useCable.ts`. Campo ausente na resposta não interrompe os demais (o legado lançava `TypeError` e parava tudo) |
| Parcelas e pagamentos | `InstallmentsTab.tsx`, `InstallmentRow.tsx`, `InstallmentDrawer.tsx`, `PaymentDrawer.tsx` | `ui/{Table,accordion,switch,Button,Tooltip}.tsx`, `SideDrawer.tsx`, `ConfirmDialog` (**que não expira** — o legado descartava a confirmação de operação irreversível em 6 s) |
| Anexos | `FilesSection.tsx`, `AttachmentGallery.tsx`, `ui/FileDropzone.tsx` | `components/ThumbnailPicker.tsx` como base do seletor; `react-photo-album@3` (já no `package.json`); variantes do ActiveStorage para as miniaturas (`Medium#small_url:60-72` como referência de padrão) |

### Operação (OPS-190…OPS-197 — mapa §2.8)

O cron diário **desaparece** (D-B6). Sobra um agendamento — versionado em `sidekiq-cron`,
com trava de concorrência — para o que legitimamente é periódico. A renumeração usa
`update_all` sem callbacks. A cor de lote (`batch_color.rb`) ganha **terminação garantida**:
o laço de rejeição do legado é potencialmente infinito quando o espaço de cores esgota.

## 4. O que fica registrado, não corrigido (Princípio 6b)

- **F-1** — `AssetsProxyController` serve `public/uploads/**` inline, sem auth e sem
  allowlist de tipo. **Não mexer**: é usado por outros sistemas da base. Esta fatia apenas
  **não o usa**.
- **F-2** — `api/v1/uploads.rb` grava arquivo de usuário dentro de `public/`.
- **F-4** — ActiveStorage em `Disk` também em produção; volume persistente é decisão de
  plataforma e **bloqueia** o cenário de OPS-192 se não for tratado no deploy.

## 5. Ordem de execução e critério de pronto

**SN-1 → SN-2 → SN-3**, com **SN-4** (detalhe + Action Cable) e **SN-5** (anexos) em
seguida, e **SN-6** (carga, com a auditoria como gate) por último.

Uma sub-fatia só fecha quando **backend + frontend + teste** dela existem e rodam.

**Portões:** `rspec` sem falha nova em relação ao baseline do Phase 1b; type-check do front
em **0 erro**.
