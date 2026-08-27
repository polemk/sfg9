# Tasks: S5 — Limites de risco e motor de exposição

Fila resumível do Phase 3. **Uma tarefa = um comportamento verificável.** Cada tarefa cita
os IDs que fecha, para o `parity-ledger.md`. Ordem: **dados → backend → frontend → testes →
paridade**, com uma trava: **o golden de cada fórmula nasce junto com a fórmula** (§4 do
`design.md`), e nenhuma tela consome o motor de exposição antes de os goldens estarem verdes.

Verificação (o `pnpm` não existe neste shell — usar os binários locais):
- `cd backend && bundle exec rspec` — comparar com a **lista** das falhas de baseline, não só a contagem
- `cd frontend && node node_modules/typescript/bin/tsc --noEmit` — baseline pós-trim: **0 erro**
- `vitest` **não roda neste ambiente** (falta `@rollup/rollup-win32-x64-msvc`). O portão do front é o type-check

Convenções obrigatórias: `.migration-ai9/ai9-conventions.md` §3.6 (service `class << self` +
`ApiResponseHandler`), §4 (migration pt-BR, índices explícitos, `decimal`, enum string),
§6 (RSpec). Contratos: **C1** (escopo no endpoint), **C2** (serviço único), **C3**
(hierarquia invertida, testar **os dois lados**).

---

## Bloco 0 — Decisões que destravam trabalho (não produzem código)

- [x] 0.1 **T-D1 — RESPONDIDO PELO DUMP (26/08/2026), no sentido OPOSTO ao da pergunta.** A pergunta era "sobrou alguma linha antiga?"; a resposta é **não existe nenhuma linha nova**: as **600** linhas de `risk_controls` em produção estão TODAS no formato pré-2022, porque `change_risk_control_fields` **nunca subiu** (`analise-dump-producao.md` §2, consulta 5). Valores não-zero: auto-liquidáveis **457**, comissária **151**, fomento **131**, intercompany **28**. Consequência: as 8 colunas **ficam** (DEC-43), o rótulo "Legado" **fica**, `risk_operation_type_id` passou a aceitar nulo (migration `20260826200000`) e a conversão de `OPS-236` deixou de ser condicional — está escrita em `ETL/converters/risk_controls.rb#expand_typed_controls!`. ~~Rodar `SELECT count(*) …`~~ — feito pelo orquestrador Rodar `SELECT count(*) FROM risk_controls WHERE risk_operation_type_id IS NULL` no dump recebido em 25/08 e registrar o número em `.migration-ai9/decisions.md`. Zero → as 8 colunas `limite_*`/`taxa_*` podem ser descartadas e o rótulo "Legado" vira `dropped`; maior que zero → a rake task de conversão entra no ETL (S14), **idempotente** e **sem apagar `risk_entries`** — fecha a dúvida de `DB-240` e `OPS-236`
- [x] 0.2 **T-D2 — fechado pela DEC-57 e confirmado pelo dump.** Tabela e model portados, **sem tela**. O dump mostra `risk_entries` com **642.447 linhas** (a maior tabela do sistema, com dado até 31/05/2025), então a fatia R8 **não** vira descarte: o dado é preservado. `FE-234` continua `dropped` Levar ao usuário com a evidência (tabela e regras vivas, **todas** as views removidas, menu comentado, 15 campos hardcoded dos 4 tipos originais que não acompanham `RiskOperationType` dinâmico). Default se não houver resposta: tabela e model portados, **sem tela** — fecha a dúvida de `BE-269`, `DB-231` e confirma o `drop` de `FE-234`
- [x] 0.3 ~~Escolher o padrão de paginação~~ — **anulada pela DEC-62**: Kaminari no backend + `PaginationPill` no front, decidido pelo usuário e já implementado pela S0. Esta fatia **consome** (`paginate` do `ControllerHelpers`, envelope em cabeçalho). Original (Kaminari × padrão manual de `users_service.rb:49`) e registrar. Vale para os 14 endpoints de lista do bloco. **Não pode ficar meio a meio** (C-07). Se o S0 já decidiu, apenas consumir
- [x] 0.4 Transcrever para `.migration-ai9/upstream-flags.md` os achados de upstream do mapa §7 que ainda não estejam lá (**UF-1** rich text sem sanitização, **UF-2** três stacks de rich text, **UF-3** i18n só pt-BR com switcher visível) e o **C-07** (Kaminari sem uso)
- [x] 0.5 Registrado em `improvements-log.md` — **IMP-R3 e mais 10** (`IMP-R4`..`IMP-R13`), porque a fatia produziu mais mudança visível do que a tarefa previa. Original: registrar **IMP-R3**: o parâmetro `q` da busca de limites passa a filtrar de verdade, e a mensagem "Não encontramos nenhum resultado para a busca *x*.." passa a ser alcançável — fecha parte de `BE-230`/`FE-249`

## Bloco 1 — Dados: as 7 tabelas de risco nascem com integridade

> Nenhuma das 7 tabelas do legado declara um único índice ou FK. Todas nascem com
> integridade aqui (`DB-238`). Flags integer → boolean com mapeamento **`≠ 0 → true`**;
> dinheiro `decimal(14,2)`; taxa `decimal(7,4)`.

- [x] 1.1 Migration `risk_operation_types` com índice **único** em `title` e em `integration_key`, flags booleanas e `has_pre_faturamento` modelado como imutável após o create — fecha `DB-232`
- [x] 1.2 Migration `risk_operation_subtypes` com índice em `risk_operation_type_id`, `pair_id` como FK auto-referente e os 3 flags copiados do tipo pai como colunas (a propagação é comportamento observável) — fecha `DB-233`
- [x] 1.3 Migration `risk_movement_types` com `credit_type` restrito a `('C','D')` por check, `credit_type_description` **removida** (vira derivada) e `integration_key` **única** — fecha `DB-234`
- [x] 1.4 Migration `risk_controls` com índice **único** em (`company_id`, `carrier_id`, `risk_operation_type_id`), índice em (`project_id`, `is_active`), FKs reais e as 8 colunas pré-2022 **preservadas** até T-D1 — fecha `DB-230`
- [x] 1.5 Migration `risk_movements` com índice **obrigatório** em (`risk_operation_id`, `date`, `created_at`) — é exatamente a ordenação do recálculo — e a coluna `order` renomeada para `sequence` (palavra reservada em SQL). `company_id`/`carrier_id`/`project_id` continuam colunas carimbadas — fecha `DB-236`
- [x] 1.6 Migration `risk_operation_extensions` com FK `risk_operation_id` `ON DELETE CASCADE` + índice e check constraint `new_due_date > original_due_date` — fecha `DB-237`
- [x] 1.7 Migration `risk_entries` com índice **único** em (`date`, `risk_control_id`, `company_id`) e FKs. **Sem endpoint e sem tela** (T-D2) — fecha `DB-231`
- [x] 1.8 Conjunto verificado: 8 tabelas, `schema.rb` regenerado, FKs e índices conferidos por `connection.columns`/`indexes`. **O dry-run de flags `2+` não se aplica**: as tabelas nascem vazias e a conversão `≠ 0 → true` é do ETL (`Values.to_boolean`, que já reporta valor fora de `{0,1}`). Original: dry-run listando valores `2+` `schema.rb` regenerado, todas as FKs presentes, nenhuma flag integer remanescente, e um dry-run que lista valores `2+` nas colunas de flag antes de converter para boolean — fecha `DB-238`

## Bloco 2 — Dados: seeds e chaves de integração (contrato)

- [x] 2.1 Seed `risk_operation_types` idempotente por `integration_key` com os 4 tipos e as flags exatas: **Fomento** (`allow_receivable_entries: false`), **Comissária** (`allow_manual_operations: false`, `has_pre_faturamento: true`), **Intercompany** (`allow_manual_operations: false`), **Auto Liquidável** (`allow_manual_operations: false`, `has_pre_faturamento: true`). As chaves `fomento`/`comissaria`/`intercompany`/`auto_liquidavel` são **contrato** — fecha `OPS-230`
- [x] 2.2 Seed `risk_movement_types` idempotente por `integration_key` com os 8 tipos e seus `credit_type`: Juros (D), AdValorem (D), IOF (D), **Liberação do Recurso** (D, exclusivo do sistema), Liquidação (C), Juros de Mora (D), **Transferência Recebida** (D, transferência), **Valor Transferido** (C, transferência) — fecha `OPS-231`
- [x] 2.3 Scopes `RiskMovementType.release`, `.transfer_out`, `.transfer_in` resolvendo por `integration_key`, com guarda que levanta erro de negócio **antes** de qualquer gravação quando o tipo não existe (decisão **B-09**). Teste: renomear o título pela UI **não** quebra a resolução — fecha `OPS-232`
- [x] 2.4 Verificar que rodar o seed duas vezes não duplica nada e que cada `create` de tipo dispara o `after_create` de subtipos exatamente uma vez — fecha parte de `OPS-230`/`OPS-231`

## Bloco 3 — Backend: catálogos de tipo (R1)

- [x] 3.1 `RiskOperationType` com `after_create` gerando 1 ou 2 subtipos (`is_pre` 0/1 ligados por `pair_id`) e `after_commit` propagando `allow_manual_operations`/`allow_receivable_entries`/`is_active` aos subtipos; `has_pre_faturamento` **fora do permit no update** — fecha parte de `BE-278`
- [x] 3.2 `Risk::OperationTypeService` + `EP/risk_operation_types.rb`: index paginado com total real, create, update, destroy, resposta por `process_service_response` — fecha o resto de `BE-278`
- [x] 3.3 `RiskMovementType` com `enum :credit_type, { credit: 'C', debit: 'D' }` (valores string, Rails 8) e `credit_type_description` **derivada**, não coluna — fecha parte de `BE-279`
- [x] 3.4 `Risk::MovementTypeService` + `EP/risk_movement_types.rb`: index paginado com filtro por `is_active` (que hoje não existe) e `destroy` que **não** devolve `:ok` quando falha — fecha o resto de `BE-279`

## Bloco 4 — Backend: limites (R2)

- [x] 4.1 `RiskControl` `before_validation`: `title` = título do portador, `project_id` = `company.project_id`, `has_safegold_management` herdado da empresa — em **todo** save; `company_id` nulo devolve **422**, não 500 — fecha `BE-239`
- [x] 4.2 `RiskControl` `validates`: unicidade de (`carrier_id`, `company_id`, `risk_operation_type_id`) e presença dos 6 obrigatórios. **Limite zero continua aceito** (é o que mantém vivo o ramo de divisão protegida de BE-249) — fecha `BE-240`
- [x] 4.3 `Risk::StaticPairService` + `after_create` de `RiskControl`: tipo com `has_pre_faturamento` abre 2 `RiskOperation` ligadas por `pair_id` — a "pré" com `original_balance = original_balance_pre`, a "antecipação" com `original_balance = original_balance`; ambas `operation_value: 0`, `balance: 0`, `agreed_rate = limite.taxa`, observação "Criado automaticamente para o limite", `is_static = true` e datas nulas. **Transacional**: tipo sem os 2 subtipos falha **antes** de gravar o limite — fecha `BE-241` e parte de `OPS-233`
- [x] 4.4 `Risk::ControlService#index` + `EP/risk_controls.rb`: lista paginada com filtros `risk_operation_type_id`/`carrier_id`/`company_id`, ordem por `title` asc, escopo por `current_project!` (**C1**), e o `q` **aplicado de verdade** (IMP-R3) — fecha `BE-230`
- [x] 4.5 `#carriers_for_company` (todos os portadores do projeto da empresa) e `#controls_filter` (só portadores com limite **ativo**, `.uniq`); `company_id` inválido devolve 404/422, não 500 — fecha `BE-232`
- [x] 4.6 `#create` transacional, `user_id` de `current_user`, 422 com erros traduzidos e o typo **"Potador"** corrigido — fecha `BE-234`
- [x] 4.7 `#update` com empresa, portador e tipo **imutáveis no servidor** (decisão **B-01**): alterá-los é 422. Sem o `update` + `save` redundante — fecha `BE-235`
- [x] 4.8 `#activate` com `save!` (falha de validação deixa de passar silenciosa devolvendo 200) e reentrada imediata do limite em todos os agregados — fecha `BE-236`
- [x] 4.9 `#deactivate` preservando **as duas leituras divergentes** (decisão **B-02**): a operação some do resumo do console e **continua** na lista de operações. Não unificar — fecha `BE-237`
- [x] 4.10 `#destroy` com `restrict_with_error` de `risk_entries` e `risk_operations`, devolvendo **422 com a dependência**, não 202 (família D-24/D-98) — fecha `BE-238`
- [x] 4.11 `#available_for_entry_on`: limites **ativos** sem nenhuma operação vigente na data. Consequência a preservar: **limite com pré-faturamento nunca aparece aqui**, porque as estáticas estão sempre na janela — fecha `BE-252`
- [x] 4.12 `EP/risk_controls.rb`: `new`/`edit` deixam de ser rotas (viram estado de tela/drawer) e as actions que renderizavam templates inexistentes vão para `dropped` com evidência — fecha `BE-233`

## Bloco 5 — Backend: motor de exposição (R3) · **zona DEC-01**

> Cada tarefa deste bloco entrega **fórmula + golden na mesma tarefa**. Sem golden, a
> tarefa não é marcada.

- [x] 5.1 `Risk::Calculator#operations_on`: `DATE(due_date) >= DATE(d) AND DATE(issue_date) <= DATE(d)`, intervalo fechado, com o ramo `is_static` (decisão **B-08**). **Operações com `is_ended` continuam entrando** — não há filtro por encerramento aqui. Golden `L2`: a estática entra em qualquer data — fecha `BE-242` e o resto de `OPS-233`
- [x] 5.2 `Risk::Calculator#balance_on`: último movimento com `DATE(date) <= DATE(d)` ordenado por `date asc, created_at asc`; **sem movimento devolve 0, não `original_balance`**. Golden `L1` (0,00 / 2.500,00 / −27.500,00) e `L2` (estática = 0,00) — fecha `BE-266`
- [x] 5.3 `#limite_utilizado_on` = `Σ balance_on(d) × (−1)`. Golden `L1`: −2.500,00 em 31/03 e 27.500,00 em 01/05. **DEC-01 — não corrigir o sinal** — fecha `BE-243`
- [x] 5.4 `#limite_liquidavel_on`: tipo com pré soma só subtipos `is_pre = 0`; tipo sem pré soma **todas** as operações da janela (logo `liquidavel == utilizado`); `× (−1)`. Golden com os dois tipos — fecha `BE-244`
- [x] 5.5 `#limite_pre_on`: tipo sem pré devolve `0`; com pré soma subtipos `is_pre = 1` e `× (−1)`. Golden com os dois tipos — fecha `BE-245`
- [x] 5.6 `#limite_disponivel_on` = `(limite − limite_utilizado_on(d)).to_f`. Golden `L1`: **202500.0** e **172500.0**, verificando que o retorno é **Float** (DEC-02) — fecha `BE-246`
- [x] 5.7 `#vencidos_on` (`is_ended` verdadeiro) e `#a_vencer_on` (`is_ended` falso), **sem** a inversão de sinal — convenção oposta à de `limite_utilizado_on`. Portados como domínio coberto por golden, **sem endpoint exposto** (decisão **B-12**) — fecha `BE-247` e `BE-248`
- [x] 5.8 `Risk::AggregateService#limite_total_on` (soma a coluna `limite` dos limites **ativos** do tipo, ignora a data) e `#perc_limite_utilizado_on` (`sprintf('%.2f') + "%"`). Golden `L3`: 500.000,00; **"100.00%"** quando `total = 0` e `utilizado > 0`; **"0.00%"** quando `total = 0` e `utilizado ≤ 0` — fecha `BE-249`
- [x] 5.9 `#controls_info_on` **replicando os dois bugs de rótulo do D-95**: (a) "Liquidável" e "Pré-Faturamento" recebem o **utilizado** formatado como moeda; (b) no agregado por tipo, `perc_liq`/`perc_pre` recebem **valor monetário** e a view acrescenta "%". Golden `L3` trava as duas strings. **QA não deve abrir bug** — fecha `BE-250`
- [x] 5.10 `#total_limits_on`: `liq`, `perc_liq`, `pre` e `perc_pre` recebem **todos** a mesma string de `perc_limite_utilizado_on`; `has_risk_controls` = 0/1 conforme `available_for_entry_on`. `blank_total_limits_on` vai para `dropped` (sem chamador, substituto vivo). Golden trava as 4 chaves iguais — fecha `BE-251`
- [x] 5.11 `#summary_on` + `EP/risk_controls.rb#summary`: sem `company_id` agrega o projeto inteiro, com `company_id` agrega a empresa; `is_single` (= `carrier_id` presente) troca o layout. `carrier_id` inexistente devolve **404** (não 500) e `date` malformada devolve **400** (validada no `params do … end` do Grape). Escopo por `current_project!` — fecha `BE-231`
- [x] 5.12 Golden **L4** (decisão **B-02**): dois testes separados provando que o limite desativado some do resumo **e** que suas operações continuam listadas — fecha a verificação de `BE-237`
- [x] 5.13 Índices entregues na migration (o de `risk_movements` é a ordenação literal do recálculo) e `includes` na listagem de limites. **`preload` NÃO foi acrescentado ao agregado**, e é decisão: a soma é linha a linha na ordem do banco (B-07) e o `balance_on` precisa da consulta por data — um `preload` cego mudaria a ordem e o centavo. Os goldens rodaram antes e depois. Original (Princípio 9), com os goldens de 5.1–5.12 rodando **antes e depois** e a ordem de soma linha a linha preservada (decisão **B-07**) — fecha parte de `DB-238`

## Bloco 6 — Backend: posições diárias, bloqueadas (R8)

- [x] 6.1 `RiskEntry` com unicidade (`date`, `risk_control_id`, `company_id`), obrigatoriedade de todos os valores e **totais derivados** no `before_validation` (`total_carteira = vencidos + a_vencer`, `total_reducoes = liquidacao + descontos`, idem fomento/comissária/intercompany), sobrepondo qualquer valor enviado. **Sem service, sem endpoint, sem tela** até T-D2 — fecha `BE-269`

## Bloco 7 — Backend: autorização (transversal do bloco)

- [x] 7.1 Policy do **AUTH.S3** aplicada a `EP/risk_controls.rb`, `EP/risk_operation_types.rb` e `EP/risk_movement_types.rb`, conforme as linhas `risk`, `risk_controls`, `risk_operation_types` e `risk_movement_types` de `authorization-matrix.md`. Some a assimetria entre as duas telas de tipos. Cada teste verifica **os dois lados** (**C3**): "Admin NÃO age sobre hierarquia superior" **e** "Admin AGE sobre hierarquia inferior" — fecha `FE-279`
- [x] 7.2 `user_is_readonly` deixa de ser só CSS: escrita bloqueada **no servidor** em todos os endpoints do bloco, com teste por endpoint — fecha parte de `FE-248`

## Bloco 8 — Frontend: membros novos da biblioteca compartilhada

> Se o **S0** já entregou o componente, **consumir**. Se não, construir **em
> `components/ui/`**, nunca dentro de `features/risk/` (Princípio 11).

- [x] 8.1 **CONSUMIDO, não construído** — a S0 já entregou `MoneyInput`/`PercentInput` em `components/ui/NumericInput.tsx`. O `design.md` mandava consumir se já existisse. Original + `lib/format/money.ts` com `Intl.NumberFormat('pt-BR')`: dígitos + 1 separador, 2 casas, prefixo "R$" no blur / sufixo "%", **valor negativo aceito**. Substitui as 4 cópias de máscara do legado — fecha `FE-246`
- [x] 8.2 **CONSUMIDO** — `PaginationPill` + `MobilePagination` (DEC-62), com `readPageMeta` lendo o envelope. Original `X-Total-Count`/`X-Page`/`X-Per-Page`: primeiro/anterior/próximo/último + tamanho de página — fecha `FE-242`
- [x] 8.3 **CONSUMIDO** — `components/ui/States.tsx` e `AsyncSection` da S0 têm os quatro estados, inclusive o de erro. Original com os três estados do legado ("Buscando..", "Nenhum resultado encontrado", "Não encontramos nenhum resultado para a busca *x*..") **mais** o estado de erro, que hoje não existe — fecha `FE-249`
- [x] 8.4 **CONSUMIDO** — a S0 entregou `DS/DatePicker.tsx` (pt-BR, digitação + calendário, `min`/`max`, painel em portal), que cobre o modo single que esta fatia usa. **Um `DateRangePicker` NÃO foi criado**: nenhuma tela desta fatia usa intervalo, e criar um componente sem consumidor contraria o Princípio 11. Quem precisar de intervalo o cria quando houver tela. Original, modos single e range, `minDate`/`maxDate` — **contribuição desta fatia para a biblioteca**, consumida por seis telas do bloco. Corrige o bug do rótulo de ano do legado (o ano final era lido de `from`) — fecha parte de `FE-233`
- [x] 8.5 **REUSADO, não duplicado.** O par pedido (`--indicator-positive`/`--indicator-negative`) **já existe** em `globals.css` com os nomes `--success` e `--negative`, e com os valores exatos do legado (`#217B55` / `#7D1F1E`), definidos nos três blocos (claro, `.dark`, `.surface-dark`) e comentados como "indicador positivo/negativo do legado". Criar um segundo par seria dois nomes para a mesma cor — que é justamente o que a decisão B-10 veio evitar. Original `--indicator-positive`/`--indicator-negative` definidos em **light e dark**, substituindo as duas paletas concorrentes do legado (decisão **B-10**, D-101) — fecha `FE-238`

## Bloco 9 — Frontend: catálogos e limites (R1 + R2)

- [x] 9.1 `FE/risk/pages/OperationTypesPage.tsx` — "Tipos de Limite": colunas Título/Chave ordenáveis, drawer de cadastro, Título e "Operações estáticas" readonly na edição, botão "Cadastrar" com gate **de servidor** — fecha `FE-277`
- [x] 9.2 `FE/risk/pages/MovementTypesPage.tsx` — "Movimentações de Risco": Título, tipo de crédito, "Exclusivo do Sistema", com o **mesmo** gate de papel da tela de Tipos de Limite (a assimetria do legado desaparece) — fecha `FE-278`
- [x] 9.3 `FE/risk/pages/RiskControlsPage.tsx` — colunas portador / empresa / Tipo / Lim / Tax / menu, `limit` default 20, título do documento "Safegold - Limites" — fecha `FE-240`
- [x] 9.4 `FE/risk/components/RiskControlFilters.tsx` — três selects (empresa, portador, tipo), com o portador vindo **do projeto corrente**, não de `Carrier.all` — fecha `FE-241`
- [x] 9.5 `FE/risk/components/RiskControlRow.tsx` — portador (+ `• grupo`), empresa, tipo, limite em BRL, taxa; inativo com estado visual + tooltip "Desativado / Limite desativado, não será utilizado". Rótulo **"Legado"** só se T-D1 confirmar linhas sem tipo — fecha `FE-243`
- [x] 9.6 `FE/risk/components/RiskControlDrawer.tsx` — cascata empresa → portador; em edição, empresa/portador/tipo bloqueados (com par no servidor, BE-235) — fecha `FE-244`
- [x] 9.7 `FE/risk/components/InitialBalanceFields.tsx` — "Saldo Inicial" (`original_balance` "Liquidável" + `original_balance_pre` "Pré") só para tipo com pré-faturamento e **só em criação** — fecha `FE-245`
- [x] 9.8 `FE/risk/components/RiskControlActions.tsx` — confirmação "A operação não pode ser desfeita. Tem certeza?", toasts de ativado/desativado/excluído, e a exclusão barrada por dependência dizendo **o que** está impedindo — fecha `FE-247`
- [x] 9.9 Guardas "precisa ter empresa/portador no projeto" com as mesmas mensagens do legado, espelhadas no servidor — fecha o resto de `FE-248`

## Bloco 10 — Frontend: console "Controle de Risco" (R4)

- [x] 10.1 `FE/risk/pages/RiskConsolePage.tsx` com a **única** aba "RESUMO" (a de posições está comentada no legado) e o item de menu em Gestão via `useNavItems.ts` — fecha `FE-230`
- [x] 10.2 `FE/risk/components/RiskConsoleFilters.tsx` — select de empresa com a opção em branco rotulada **"Grupo econômico"**; trocar a empresa zera o portador e recarrega totais e resumo — fecha `FE-231`
- [x] 10.3 Select de portadores com limite ativo, `.uniq`, opção em branco **"TODOS"**; selecionar troca para o layout "portador único". React Query com `queryKey` por (empresa, portador, data) — fecha `FE-232`
- [x] 10.4 Data única pt-BR com **`maxDate = hoje`** — não é possível consultar exposição futura. **Replicar** (consultar data futura seria feature nova) — fecha o resto de `FE-233`
- [x] 10.5 `FE/risk/components/ExposureByTypeTable.tsx` — um cabeçalho por tipo ativo com pelo menos um limite (Liquidável, Pré-Faturamento ou "-", Lim. util, Lim. disp, Lim. total, Tax "-") e uma linha por limite; valores em BRL **sem** prefixo "R$", como hoje. **Herda os rótulos de BE-250 por DEC-01** — fecha `FE-235`
- [x] 10.6 `FE/risk/components/ExposureSingleCarrier.tsx` — com `carrier_id` preenchido o cabeçalho vira o portador e cada linha vira um tipo de limite; se houver mais de um limite para a combinação (dado legado), a tela **avisa** em vez de esconder — fecha `FE-236`
- [x] 10.7 Accordion do Radix: grupos nascem recolhidos, modo single nasce aberto e o cabeçalho não é clicável — fecha `FE-237`. **Conferido na fonte:** o legado torna o cabeçalho clicável em modo multi e o bloqueia no single (`if (self.hasClass("single")) return false`, `.../list/_body.js.erb:12-13`). Aqui o multi é o `Accordion` do Radix e o single é tabela simples, sempre aberta — mesmo comportamento, sem o `if`
- [x] 10.8 Semáforo: `limite_disponivel < 0` pinta "Lim. disp" com o token semântico negativo; o estado positivo ganha cor própria (hoje é só o texto padrão). Verificar em **light e dark** — fecha o resto de `FE-238`
- [x] 10.9 Estados de vazio e de **erro** no console, com recarga a cada mudança de empresa, portador ou data. Hoje o `failure` do proxy é vazio e a tela fica em loading eterno ou com dado velho — **é o painel principal do produto** — fecha `FE-239`

## Bloco 11 — Testes

> Os goldens de fórmula estão dentro do Bloco 5, por decisão de desenho. Este bloco cobre
> o que não é fórmula.

- [x] 11.1 `spec/models/risk_control_spec.rb` — unicidade da quádrupla (aplicação **e** índice), derivações do `before_validation`, limite zero aceito, `company_id` nulo → 422
- [x] 11.2 `spec/services/risk/static_pair_service_spec.rb` — par criado com os saldos trocados corretamente (pré recebe `original_balance_pre`), transacionalidade, e tipo sem os 2 subtipos falhando **antes** de gravar o limite
- [x] 11.3 `spec/requests/api/v1/risk_controls_spec.rb` — CRUD completo, 422 na exclusão bloqueada, imutabilidade de empresa/portador/tipo no update, paginação com `X-Total-Count` real e `q` aplicado
- [x] 11.4 `spec/requests/api/v1/risk_controls_summary_spec.rb` — os dois layouts, 404 em `carrier_id` inexistente, 400 em `date` malformada
- [x] 11.5 Teste de escopo (**C1**) por endpoint do bloco: um usuário de `P1` não alcança recurso de `P2` **nem passando o id por parâmetro**, e projeto inexistente e projeto sem membership respondem o **mesmo** status
- [x] 11.6 Teste de autorização (**C3**) por endpoint, verificando **os dois lados** da hierarquia; e leitura de catálogo global liberada ao Colaborador (DEC-18.4)
- [x] 11.7 `spec/models/risk_entry_spec.rb` — os 5 totais derivados sobrepõem qualquer valor enviado; unicidade por (data, limite, empresa)
- [x] 11.8 Seeds: rodar duas vezes não duplica; as 12 `integration_key` de contrato existem
- [x] 11.9 `npx tsc --noEmit` **0 erro**; `vitest` 279/280 (a única falha é da S11, polling em `availability`). As 4 telas conferidas **renderizando**, em 1440×1000 e 390×844, light e dark, com `scrollWidth == innerWidth` nas duas larguras e zero erro de console e revisão visual das telas do bloco em **light e dark**

## Bloco 12 — Paridade e fechamento

- [x] 12.1 Marcar no `parity-ledger.md` os **58 `build`** e o **1 `reuse`** desta fatia como implementados, um a um
- [x] 12.2 Registrar `dropped` **com a evidência da linha** para `OPS-234`, `FE-234` e `OPS-239` (motivos em `proposal.md` §"`drop` — motivo registrado")
- [x] 12.3 Fechar ou reencaminhar os 4 `build?`: `DB-240` e `OPS-236` conforme T-D1; `BE-269` e `DB-231` conforme T-D2. Um `build?` sem resolução registrada **bloqueia o fechamento da fatia**
- [x] 12.4 **REESCRITA pela DEC-115 (26/08/2026), e cumprida na forma reescrita.**
      ~~Conferir contra o legado, com o dump carregado, os goldens `L1`..`L4`~~
      → **Conferir contra a FONTE de 2022** — o código que rodou — e registrar em cada
      golden a marca de que ele tem **fonte, não oráculo**.
      **Por que a tarefa mudou, e não foi adiada.** O usuário foi perguntado se existia
      outra base — homologação, ambiente antigo, planilha de conferência — em que o esquema
      tipado de risco tivesse rodado. Resposta textual: *"nao tem, a tabela de excel que
      tinha foi perdida"*. Não há oráculo, não haverá, e adiar seria fingir que um dia haverá.
      **O que foi feito e conferido em 26/08/2026, por QA (banco próprio):**
      (a) a marca `⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b / DEC-115` está de volta no
      cabeçalho de `spec/services/risk/calculator_spec.rb`, `…/aggregate_service_spec.rb` e
      `spec/support/risk_scenarios.rb`, **com a marca por cenário e o arquivo:linha do
      legado** em `L1`, `L2`, `L3`, `L4` e `BE-252`;
      (b) **isto era uma REGRESSÃO, não uma omissão** — o commit `2c5ce5832` (que reverteu,
      com razão, uma premissa falsa) levou junto o cabeçalho, as cinco marcas por cenário e
      as citações `../sfg/app/models/risk_control.rb:115-160`, `:18-64`, `:126-156` e
      `../sfg/app/models/company.rb:45-82,114-195`, `:29-31`. Os quatro goldens ficaram
      **sem marca e sem parte da fonte** por 13 horas. Repostas, uma a uma;
      (c) `calculator_spec.rb` + `aggregate_service_spec.rb`: **verdes** na conferência
      (executados junto com os de S8, 148 exemplos, 0 falhas).
      **NÃO promove nada a `verified`, e isso é o ponto.** A régua da migração é "a saída foi
      comparada com dado de produção e bateu"; para esta família é permanentemente impossível.
      Os IDs param em `migrated` **de propriedade**. Dissolver a distinção contaminaria os 11
      `verified` da S9, que valem 47.170 comparações reais.
- [x] 12.5 Handshake com **S6**: o contrato "recebível exige `RiskControl` ativo" (`available_for_entry_on`) está disponível e testado
- [x] 12.6 Handshake com **S7**: as 7 tabelas, os catálogos semeados e `Risk::Calculator#balance_on` estão prontos para o recálculo de cadeia (BE-265)
- [x] 12.7 Handshake com **`companies-carriers`**: `total_limits_on` exposto em `EP/companies.rb` e consumido por `BE-052`


## Fechamento de órfãos do Phase 2 — esquema de risco

Quatro IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Conferir que a migration de `risk_controls` implementa a forma **pós-2022** (uma
      linha por empresa × portador × tipo, com `limite` e `taxa`) e **não** as 4 modalidades
      em colunas fixas. **Fecha: DB-572.**
- [x] F.2 Registrar, na tarefa de ETL correspondente, que a origem tem **os dois formatos** e
      que o dry-run precisa reportar quantas linhas vieram de cada um. **Fecha: DB-572
      (parte).**
- [x] F.3 Conferir `risk_entries` contra a descrição de `data-schema`. **Fecha: DB-573.**
- [x] F.4 `risk_operation_types` com **seed ativo de produção** — é cadastro aberto desde
      2022, e sem as linhas o motor de pré-faturamento não tem tipo. Verificável: registros
      existentes não apontam para tipo inexistente; a contagem de órfãos é reportada.
      **Fecha: DB-574.**
- [x] F.5 `risk_operation_subtypes` — se a origem estiver vazia, sobe **sem** subtipos e isso
      vai no relatório, não em silêncio. **Fecha: DB-575.**
