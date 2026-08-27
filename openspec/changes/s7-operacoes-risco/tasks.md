# Tasks: S7 — Operações de risco: movimentos, prorrogação e renovação

Fila resumível do Phase 3. **Uma tarefa = um comportamento verificável.** Cada tarefa cita
os IDs que fecha, para o `parity-ledger.md`. Ordem: **dados → backend → frontend → testes →
paridade**, com a trava do `design.md` §7: **o golden nasce junto com a regra**, e nenhuma
tela de extrato existe antes de `M1` e `M2` estarem verdes.

> ## Estado final: **88 de 88 marcadas** (26/08/2026)
>
> A última era a **11.4**, que estava aberta por ser **impossível como escrita**: os goldens
> `M1`…`M5` não tinham contra o que ser conferidos, porque as seis migrations desta família
> **nunca subiram em produção**. A pergunta que a fecharia foi levada ao usuário, e a
> resposta dele — *"nao tem, a tabela de excel que tinha foi perdida"* — virou a **DEC-115**,
> que **reescreveu** a tarefa: a conferência é contra a **FONTE de 2022**, com a marca de
> fonte-e-não-oráculo em cada golden. Auditada por QA em 26/08/2026 e **conforme**.
>
> **Nenhum ID desta fatia foi promovido a `verified` — e isso é deliberado.** Pela régua da
> migração, `verified` exige comparação com dado de produção, que para esta família é
> permanentemente impossível.
>
> ### Três decisões do usuário anularam tarefas escritas aqui — leia antes de "consertar"
>
> | Tarefa | Decisão que venceu | Onde está riscado |
> | --- | --- | --- |
> | 0.4 e 6.3 — **IMP-R1**, "renovar encerra a original" | **DEC-35**: replicar o ciclo de vida. *"Um teste que exija encerramento automático está errado contra esta DEC."* | 0.4, 6.3, 10.4, 11.7, `improvements-log.md`, `legacy-defects.md` (D-94) |
> | 0.1 e 2.2 — **T-D3**, "recusar com 422 sem subtipo" | **DEC-67**: subtipo padrão declarado no tipo | 0.1, 2.2 |
> | 5.7 e 8.10 — **Q-R9**, "conteúdo dos tooltips em branco" | **DEC-88**: os 91 textos foram **escritos** | 5.7, 8.10 |
>
> Nenhuma linha foi apagada: cada uma está riscada com o número da decisão que a anulou.
>
> ### O que "verificado" significa em cada portão desta fatia
>
> - **Backend:** goldens `M1`…`M5` verdes, com a marca `⚠ NUNCA EXECUTADO EM PRODUÇÃO`
>   e arquivo:linha do legado em cada um.
> - **Frontend:** `tsc --noEmit` 0 erro; `vitest` 412 passando (388 da base + 24 novos).
> - **Renderizando e executando:** operação criada pela tela, dois movimentos lançados,
>   prorrogação e renovação feitas — os três saldos do golden `M1` apareceram na tela
>   (0,00 / 2.500,00 / −27.500,00). Light **e** dark, 1440×900 **e** 390×844, zero erro de
>   console, zero rolagem horizontal.

**Pré-requisito duro:** S5 entregue (as 7 tabelas, os catálogos semeados com
`integration_key`, `Risk::Calculator#balance_on`, `RiskControl`, `is_static`). Sem isso, nada
deste arquivo começa.

Verificação: `cd backend && bundle exec rspec` (comparar com a **lista** de falhas do
baseline) · `cd frontend && node node_modules/typescript/bin/tsc --noEmit` (baseline pós-trim
**0 erro**) · `vitest` não roda neste ambiente.

Contratos: **C1** (escopo no endpoint), **C2** (serviço único), **C3** (hierarquia
invertida, testar **os dois lados**). Convenções: `ai9-conventions.md` §3.6, §4, §6.

---

## Bloco 0 — Decisões que destravam trabalho (não produzem código)

- [x] 0.1 ~~**T-D3 — Q-R6: subtipo padrão em tipo com pré-faturamento.** Levar ao usuário o conflito… Default: **spec** (recusar com 422)~~ — **ANULADA pela DEC-67 (25/08/2026).** O usuário decidiu depois: opção (c) — `RiskOperationType` ganha **subtipo padrão explícito** (`is_default_for_type`) e o formulário só pergunta quando há mais de um. O padrão semeado **reproduz o que o `.first` sem `order` escolhia** no legado, então nada muda para quem já opera. A S5 já implementou `default_subtype`; a S7 consome em `RiskOperation#reconcile_type_and_subtype`. **Nada foi levado ao usuário porque ele já decidiu.** Fecha `BE-262`
- [x] 0.2 **T-D4 — Q-R8: encerrar bloqueia movimento e prorrogação?** — **RESOLVIDA pela DEC-35**, que confirma o default (spec): `is_ended` é rótulo, não bloqueia nada e **não** retira a operação de `operations_on`. As três não-consequências têm teste em `spec/models/risk_operation_spec.rb`. Texto original: Levar ao usuário o conflito: o mapa propõe bloquear (D-94) e a spec diz que a operação encerrada continua na janela, consumindo limite e aceitando movimentos (DEC-01). Default: **spec**. Registrar explicitamente que **retirar a operação encerrada de `operations_on` está fora de qualquer default** — mudaria a exposição do histórico inteiro — fecha a dúvida de `BE-268`
- [x] 0.3 **T-D5 — Q-R10: as datas de operação existente são editáveis?** — **adotado o default (regra de servidor nos dois módulos).** `PUT /risk_operations/:id` ignora `issue_date`/`due_date`; esticar prazo é prorrogação. Teste na borda HTTP. Texto original: Hoje a UI trava e a API aceita, em risco (`FE-260`) e em estruturadas (`FE-297`). Default: **regra de servidor nos dois módulos**, alinhado à spec de `FE-297` — fecha a dúvida de `FE-260` e alinha com S8
- [x] 0.4 ~~Registrar em `improvements-log.md` a mudança visível **IMP-R1**: renovar passa a **encerrar a operação original**…~~ — **ANULADA pela DEC-35 (25/08/2026).** O usuário decidiu **replicar** o ciclo de vida: *"renovar NÃO encerra a original; as duas ficam vivas e as duas consomem limite ao mesmo tempo"*, e a DEC diz com todas as letras que *"um teste que exija encerramento automático está errado contra esta DEC"*. **O registro foi feito ao contrário**: `IMP-R1` está no `improvements-log.md` como melhoria **DECLINADA**, e o veredito "corrigir" do `D-94` foi riscado em `legacy-defects.md` com a nota da DEC. **QA não deve abrir bug para a exposição em dobro**
- [x] 0.5 Transcrever para `.migration-ai9/upstream-flags.md`: `aasm` (`Gemfile:45`) e `pg_search` (`Gemfile:87`). **Feito e MEDIDO** — seção `#S7-1`: **0 ocorrências** de cada uma em `backend/app`. Registrado também por que nenhuma foi ativada nesta fatia (a DEC-35 tira o sentido da máquina de estados; `ILIKE` nativo é o dialeto de busca já vivo na S5/S6)

## Bloco 1 — Dados

- [x] 1.1 Migration `risk_operations` com índices em (`project_id`, `issue_date`, `due_date`), `risk_control_id`, `operation_subtype_id`, `original_id`, `receivable_id`, `receipt_id`; FKs reais; `is_ended`/`is_on_variable` → boolean; `is_static` boolean com datas nulas para o par estático; **`original_balance` migra com o sinal negativo preservado**; `balance` permanece coluna **cache derivada**, não coluna gerada — fecha `DB-235` — **CONFERIDA, não reescrita.** A tabela já existe: a S5 a criou em `db/migrate/20260826160400_operacoes_de_risco.rb` por dependência de FK, com o cabeçalho pedindo explicitamente que a S7 não a recrie (armadilha 2 do checkpoint). Conferido item a item: índices `(project_id, issue_date, due_date)`, `risk_control_id`, `operation_subtype_id`, `original_id`, `receivable_id`, `receipt_id`; FKs reais; `is_ended`/`is_on_variable` boolean; `is_static` com datas nulas e `check_constraint`; `original_balance` com o sinal negativo preservado; `balance` como coluna cache (não gerada). **Nenhuma migration nova nesta fatia**
- [x] 1.2 Contrato de fronteira: `receivable_entries.risk_operation_type_id`/`risk_operation_subtype_id`, `receipts.operation_id`/`operation_type` polimórfico, `ReceivableEntry has_one :risk_operation (dependent: :destroy)`, `RiskOperation has_one :receipt (restrict_with_error)` e o escopo `available_for_receipt`. **Escrito aqui, implementado por `receivables` e `charges`** — fecha `DB-239` — o contrato existe nos dois lados: `receivable_entries.risk_operation_type_id`/`risk_operation_subtype_id` (S6), `receipts.operation_id`/`operation_type` polimórfico com `check_constraint`, `ReceivableEntry has_one :risk_operation (dependent: :destroy)`, `RiskOperation has_one :receipt (restrict_with_error)` e `scope :available_for_receipt`. Teste executável em `spec/services/risk/receivable_contract_spec.rb`

## Bloco 2 — Backend: o model da operação e a cascata de criação

- [x] 2.1 `RiskOperation` `before_validation on: :create`: resolve o `RiskControl` pela quádrupla (projeto, empresa, portador, tipo) **sem filtrar `is_active`** (é possível abrir operação em limite desativado — replicar); carimba `original_due_date = due_date`; `title` cai para o portador quando vazio. Erro passa a dizer "não existe limite cadastrado para esta combinação" — fecha `BE-261` — `resolve_risk_control` + `stamp_original_due_date` + `fallback_title_to_carrier`, os três `on: :create`. **Sem filtrar `is_active`** (teste próprio, e a DEC-105 confirma o critério). Mensagem: "não existe limite cadastrado para esta combinação de empresa, portador e tipo de operação"
- [x] 2.2 `RiskOperation` `before_validation`: subtipo informado **sobrescreve** o tipo; ~~tipo com pré-faturamento **sem** subtipo informado é **recusado com 422** pedindo a escolha explícita (T-D3)~~ **→ a DEC-67 anulou esta metade**: sem subtipo informado entra o **padrão do tipo** (`is_default_for_type`), que reproduz o que o `subtypes.…pluck(:id).first` **sem `order`** escolhia no legado. A S5 já implementou `default_subtype`; a S7 consome. Tipo sem nenhum subtipo continua recusado com erro explicativo — fecha `BE-262`
- [x] 2.3 `RiskOperation` `before_validation`: `original_balance = -(|original_balance|)` em **todo** save. **DEC-01 — não corrigir.** Golden: entrada 100.000,00 → gravado −100.000,00 — fecha `BE-263` — `normalize_original_balance` em todo save. Golden: entrada 100.000,00 → gravado −100.000,00, **verificado também executando pela tela** (SALDO INICIAL exibe −R$ 100.000,00)
- [x] 2.4 `RiskOperation` `after_create`: só para tipo **sem** pré-faturamento, cria o `RiskMovement` "Liberação do Recurso" com `date = issue_date` e `movement_value = operation_value`, resolvido por **`integration_key`** com guarda que falha **antes** de gravar a operação (B-09). Operações estáticas nascem **sem movimento** — fecha `BE-264` — `create_release_movement`. Resolvido por `integration_key` (`RiskMovementType.release`), que levanta `MissingFunctionalType` **dentro** da transação. Operação estática nasce sem movimento (guarda explícita). **Uma escolha declarada:** o legado usa `RiskMovement.create` **sem bang** (`:41`), e há um caminho real em que o movimento é inválido (janela invertida, que o `BE-267` manda continuar aceitando) — nesse caso a operação é gravada **sem** movimento, em silêncio. Espelhado (DEC-103b), com o motivo em log. Ver o relatório
- [x] 2.5 `RiskOperation` `validates`: obrigatórios company, project, carrier, operation_type, user, issue_date, operation_value, due_date, risk_control. **Replicar as ausências**: sem `due_date >= issue_date`, sem `operation_value > 0` — operação de capital zero continua aceita (Q-R7) — fecha `BE-267` — as ausências replicadas têm teste que as trava: capital zero entra, vencimento anterior à emissão entra, taxa negativa entra. Registrado também que `validates :operation_value, presence: true` é **inalcançável** nos dois lados (a coluna tem `default: 0`)
- [x] 2.6 `is_ended` e `is_on_variable` como `enum` string + service (não `aasm`). Conforme T-D4, `is_ended` **continua rótulo**: não bloqueia movimento, não bloqueia prorrogação e **não** retira a operação de `operations_on`. Teste que trava as três não-consequências — fecha `BE-268` — `is_ended`/`is_on_variable` continuam `boolean` + serviço, **não `aasm`** (ver 0.5). As três não-consequências têm teste próprio, e a quarta (continua faturável) também

## Bloco 3 — Backend: a cadeia de saldos (R6) · **zona DEC-01/DEC-02**

> Cada tarefa deste bloco entrega **regra + golden na mesma tarefa**.

- [x] 3.1 `Risk::Calculator#recalculate_chain`: ordena por `date asc, created_at asc`; `balance_n = balance_{n-1} + sinal × movement_value` com `balance_0 = original_balance` e **crédito = −1, débito = +1**; `sequence` reatribuído a partir de 1; `operation.balance` recebe o último saldo (ou `original_balance` se não houver movimento). Roda no `before_validation` de **todo** save da operação. **Golden `M1`** (0,00 / 2.500,00 / −27.500,00) — fecha `BE-265` — `Risk::Calculator.recalculate_chain`. **Golden `M1` verde** (0,00 / 2.500,00 / −27.500,00) e **verificado executando pela tela**, com os mesmos três números
- [x] 3.2 Persistência da cadeia por `RiskMovement.upsert_all` (Rails 8) — `activerecord-import` **não existe** no Gemfile (correção C-03). **Preservar o pulo de validações**: a janela de datas de `BE-274` **não** é reaplicada nesse caminho. Teste que prova o pulo — fecha `OPS-235` — `upsert_all` com `update_only: %i[balance sequence]` e `record_timestamps: false`. Teste que prova o pulo: encolher a janela por baixo e recalcular **não** levanta
- [x] 3.3 Golden `M1` derivado: inserir um movimento **no meio** renumera a sequência e reescreve os saldos seguintes (0,00 → 1.000,00 → 3.500,00 → −26.500,00) — fecha a verificação de `BE-265` — movimento no meio (10/03, 1.000,00) renumera e produz 0,00 → 1.000,00 → 3.500,00 → −26.500,00
- [x] 3.4 Golden `M1` derivado: excluir o movimento automático de "Liberação do Recurso" **é permitido** e ele **não é recriado**; a cadeia passa a partir de −100.000,00. **Replicar** — fecha parte de `BE-273` — excluir a liberação é permitido e ela **não** volta; a cadeia passa a −97.500,00 → −127.500,00
- [x] 3.5 Golden `M1` derivado: movimento que **zera** o saldo, saldo negativo e movimento em operação **encerrada** continuam permitidos (T-D4) — fecha a verificação de `BE-268` — o mesmo exemplo cobre os três casos, com a operação marcada `is_ended`
- [x] 3.6 `Risk::Calculator#last_movement`: último movimento por **`sequence` asc** (não por data), devolvendo `movement_value_sign` (−1 crédito / +1 débito), `total_balance` e `original_balance`. **Golden `M5`**: operação sem movimento nenhum devolve **payload vazio**, não 500 — fecha `BE-255` — `last_movement` por `sequence` asc. **Golden `M5`**: operação sem movimento devolve `{}`, e a borda HTTP devolve 200 com corpo vazio
- [x] 3.7 Índice de `risk_movements` exercitado pelo recálculo e recálculo em **um único** `upsert_all` (Princípio 9). Os goldens de 3.1–3.6 rodam **antes e depois** e continuam idênticos — fecha parte de `BE-265` — teste conta as instruções `INSERT` contra `risk_movements` num save e exige **≤ 1**; e um segundo exemplo prova que uma cadeia já correta **não** é reescrita (nem `updated_at`). Os goldens de 3.1–3.6 rodam sobre o mesmo caminho

## Bloco 4 — Backend: movimentos (R6)

- [x] 4.1 `RiskMovement` `validate` de janela: rejeita `date < operation.issue_date` **ou** `date > operation.due_date`, fechado nas duas pontas; **nunca dispara** para operação `is_static`; `risk_operation` nulo devolve 422, não 500 — fecha `BE-274` — a validação de janela é da S5 e foi conferida: fechada nas duas pontas, nunca dispara para `is_static`, e `risk_operation` nulo cai na validação de presença (422, não 500)
- [x] 4.2 `Risk::MovementService#index`: lista os movimentos de uma operação ordenada por `sequence` asc, **com paginação** (hoje `l`/`o`/`q` são preenchidos e ignorados) e **com escopo de projeto** (hoje qualquer `risk_operation_id` é aceito — IDOR) — fecha `BE-270` — `Risk::MovementService#index`, ordenado por `sequence`, paginado por Kaminari e **escopado**: a operação é resolvida por `OperationService.find(project, id)` antes de qualquer consulta a movimento
- [x] 4.3 `Risk::MovementService#create`: `user_id` de `current_user`; `company_id`/`carrier_id`/`project_id` **sempre copiados da operação**, descartando o que vier no payload; combo usa `RiskMovementType.manual` (`is_transfer = false AND is_active = true`); **`movement_value > 0` passa a valer no servidor** (decisão **B-05**) — fecha `BE-272` — `#create`. `user_id` da sessão; escopo carimbado da operação; `movement_value > 0` no servidor (B-05); combo por `RiskMovementType.manual`
- [x] 4.4 Helpers de movimento novo e de transferência (com `movement_type` fixado em "Valor Transferido", readonly); operação inexistente devolve **404**, não `NoMethodError` — fecha `BE-271` — `#form_options`, com `mode=new` e `mode=transfer`. Operação inexistente → **404**
- [x] 4.5 `Risk::MovementService#update` e `#destroy`: `after_destroy` salva a operação, refaz a cadeia e renumera o `sequence` dos restantes — fecha o resto de `BE-273` — `#update` e `#destroy`; o `after_destroy` do model salva a operação, refaz a cadeia e renumera. Teste na borda HTTP
- [x] 4.6 `Risk::TransferService`: movimento "Valor Transferido" numa operação `is_pre` gera a contrapartida "Transferência Recebida" na `pair_operation`, mesma data/valor/observação, `pair_id` cruzado. **Validado antes, em transação**: sem par, nada é gravado (hoje fica meia transferência). Transferir **a partir da antecipação não gera contrapartida** — replicar (Q-R11). **Golden `M2`**: pré = −10.000,00 e antecipação = +10.000,00 — fecha `BE-275` — `Risk::TransferService`, validado **antes** e em transação. **Golden `M2` verde**: pré −10.000,00 e antecipação +10.000,00. Sem par, nada é gravado. Transferir a partir da antecipação → 422 (Q-R11, replicado)
- [x] 4.7 `after_commit` do movimento: salva a operação (dispara o recálculo) e espelha `date` **e** `movement_value` no par. **Corrige D-97** — hoje `movement_value` está sem os dois-pontos e é variável local inexistente: editar movimento com par levanta `NameError` **em produção**. Excluir um movimento de transferência passa a apagar o par — fecha `BE-276` — `after_commit` espelha **data e valor** no par (a correção do D-97) e o `destroy` leva o par junto. Teste que edita e confere as duas pontas

## Bloco 5 — Backend: operações, CRUD e listagem (R5)

- [x] 5.1 `Risk::OperationService#index` + `EP/risk_operations.rb`: joins carrier/company/type, filtros de empresa/portador/tipo, janela `from`/`to` (mesma regra de `BE-242`), busca em `carriers.title` **ou** `risk_operations.title`, `order_mode=dash` → `issue_date desc`. **Corrige D-100**: `risk_operation_id` filtra **dentro** do escopo de projeto, nunca substitui a relation. `X-Total-Count` calculado **antes** do limit/offset — fecha `BE-253` — `Risk::OperationService#index` + `Api::V1::RiskOperations`. **D-100 corrigido** com teste; `X-Total-Count` antes do recorte, com teste
- [x] 5.2 Allowlist de ordenação no servidor (carrier, operation_type, title, issue_date, operation_value, balance, due_date, agreed_rate), com **400** para chave desconhecida (hoje `nil + " "` → 500) e acúmulo de `ordering_keys[]`/`ordering_style[]` — fecha parte de `BE-253`/`FE-254` — `RiskOperation::ORDERING` (`Sfg::Sortable`), com **400** para chave desconhecida (`ORDERING.rejected`) e acúmulo de `ordering_keys[]`/`ordering_style[]`. A allowlist tem as **dez** chaves do legado, não oito — tirar `company` e `contract_number` reduziria a tela sem motivo
- [x] 5.3 `#filter_options`: `search_type=company` → portadores com limite ativo de tipo `allow_manual_operations`; `search_type=carrier` → tipos manuais com limite ativo para (projeto, empresa, portador). `search_type` desconhecido → **400**; id inexistente → **404** — fecha `BE-254` — `#filter_options`. `search_type` desconhecido → **400**; empresa de outro projeto → **404**
- [x] 5.4 `#create` **em transação** em volta da cascata (`BE-261` → `BE-262` → `BE-263` → `BE-264` → `BE-265`), com `user_id` de `current_user`, `balance` fora do permit e 422 estruturado. Teste: falha em qualquer elo desfaz tudo — fecha `BE-256` — `#create` em transação, `user_id` da sessão, `balance` fora do permit, 422 estruturado. **Uma trava a mais que a tarefa não previa:** replicar `self.project_id = self.company.project_id` do legado sem guarda deixava a operação nascer no projeto da empresa enviada — o teste de C1 pegou, e empresa/portador passaram a ser resolvidos **dentro** do projeto corrente (EXCEÇÃO-2 do DEC-30)
- [x] 5.5 `#update`: **um** save e **um** recálculo (hoje são três passagens pelo `before_validation`). Encolher `issue_date`/`due_date` deixando movimentos fora da janela é **recusado com a lista dos movimentos conflitantes** (decisão **B-03**). Editar `operation_value` **não** regenera o movimento de liberação — replicar — fecha `BE-257` — `#update` com **um** save. As datas não são editáveis (T-D5) e por isso a recusa de B-03 vive no caminho que efetivamente encurta prazo, a prorrogação — com a lista dos movimentos conflitantes. Editar `operation_value` **não** regenera o movimento de liberação (teste)
- [x] 5.6 `#destroy`: `dependent: :destroy` nos movimentos, `restrict_with_error` no recibo, e **422 de verdade** — hoje a resposta é literalmente `errors.any? ? :ok : :ok` e a UI diz "Operação foi removida com sucesso!" mesmo quando barrada (D-98). Extensões deixam de ficar órfãs (FK cascade de `DB-237`) — fecha `BE-258` — `#destroy` com 422 real; teste que grava um recibo e prova que a operação sobrevive; teste que prova que a prorrogação some junto (FK cascade)
- [x] 5.7 Textos de ajuda do formulário carregados **uma vez** (config, não `YAML.load_file` por render — hoje sumir do deploy dá 500 no formulário). Conteúdo permanece em branco até o negócio escrever (Q-R9) — fecha `OPS-237` — **já entregue pela S12**: `Help::FieldHelp` lê o YAML **uma vez** (memoizado fora de desenvolvimento) e `GET /help/fields?scope=risk_operations` serve o mapa. O front consome pelo `<FieldHelp>` da biblioteca. **A Q-R9 foi superada pela DEC-88**: os textos foram ESCRITOS. Dos 13 campos deste formulário, **12 têm texto** em `db/seed_assets/risk_operations_help_inputs.yml`; o 13.º (`is_on_variable`) segue marcado `TODO:` porque a pergunta "o que é o variável e quem apura?" continua aberta com o usuário — e o servidor filtra as chaves `TODO:`, então ele não ganha ícone

## Bloco 6 — Backend: prorrogação e renovação (R7)

- [x] 6.1 `Risk::RenewalService#prepare`: monta a nova operação em memória com `original_id` da clicada, `issue_date = hoje` e `due_date = due_date_original + (hoje − issue_date_original)` — preserva o prazo em dias. `risk_operation_id` inexistente → **404**. **Golden `M3`**: 01/03→30/06 renovada em 20/05 produz **18/09/2026** — fecha `BE-259` — `#prepare`. **Golden `M3` verde**: 01/03→30/06 renovada em 20/05 sugere **18/09/2026** (80 dias). Id inexistente → 404
- [x] 6.2 `Risk::RenewalService#create`: copia os 13 campos verificados na fonte, força `is_ended = false`, guarda `original_due_date` e **encadeia sempre na raiz** (`original.original_id || original.id`) — fecha parte de `BE-260` — `#create` copia os 13 campos, força `is_ended = false` e encadeia na raiz (`original.original_id || original.id`), com teste de dois elos
- [x] 6.3 ~~**D-94 (IMP-R1)**: a renovação **encerra a operação original**… a exposição em 01/06/2026 conta **uma** operação, não duas~~ — **ANULADA pela DEC-35 (25/08/2026).** *"Renovar NÃO encerra a original. As duas operações ficam vivas e as duas consomem limite de risco ao mesmo tempo. […] Um teste que exija encerramento automático está errado contra esta DEC."* O orquestrador levantou a objeção (o `legacy-defects.md` trazia o veredito "corrigir") e o usuário **reafirmou replicar**.
      **O que foi entregue no lugar, com golden:** a original **fica aberta** (`expect(operacao.reload.is_ended).to be(false)`) e a exposição em 01/06/2026 conta **duas** operações. As duas outras metades da tarefa foram avaliadas separadamente: `due_date > issue_date` **foi implementada** no caminho de renovação (mais estrita que o `create`, que segue permissivo por `BE-267`/Q-R7 — a divergência está escrita em `renewal_service.rb`), e a **recusa de renovar operação encerrada NÃO foi implementada**, porque o legado não a tem e a DEC-35 manda replicar o ciclo de vida. Fecha o resto de `BE-260`
- [x] 6.4 `Risk::ExtensionService`: `before_validation on: :create` carimba `original_due_date` **da operação** (o valor do form é ignorado); `after_create` sobrescreve `operation.due_date` e reexecuta o recálculo; o log é **imutável** (sem update exposto). Validação `new_due_date > original_due_date` **no servidor** — hoje só o `minDate` do datepicker impede, e por requisição direta dá para **encurtar** o vencimento. **Golden `M4`** — fecha `BE-277` — `Risk::ExtensionService` + `RiskOperationExtension`. `original_due_date` carimbado da operação (o do form é ignorado — teste na borda); `after_create` sobrescreve o vencimento e recalcula; log imutável (sem update/destroy expostos, com teste); `new_due_date > original_due_date` no servidor. **Golden `M4` verde**

## Bloco 7 — Backend: contrato com recebíveis

- [x] 7.1 `Risk::ReceivableIntegrationService` como **contrato executável**: subtipo de tipo **com** pré localiza a operação estática de (projeto, empresa, portador, tipo, subtipo) e cria "Liberação do Recurso" com `movement_value = valor_liquido`; sem pré, cria (ou revincula) `RiskOperation` "Operação do recebível #id" com `operation_value = valor_liquido`, `due_date = data_credito`, `agreed_rate = nominal_tax`, `contract_number = nro_bordero`; validação prévia rejeita com "Não possui limite cadastrado" se não houver `RiskControl` ativo. **Implementação do borderô é de S6**; aqui entra o serviço e o teste de integração — fecha `OPS-238` — o contrato é **executável**: `spec/services/risk/receivable_contract_spec.rb`, os dois ramos. A implementação é da S6 (`Receivables::RiskSyncService`) e foi exercitada, não estubada — inclusive a costura em que o `after_create` da S7 dispara dentro do `RiskOperation.create!` da S6

## Bloco 8 — Frontend: lista e formulário de operações (R5)

- [x] 8.1 `FE/risk/pages/RiskOperationsPage.tsx` — colunas menu, Portador, Tipo (mostra o **subtipo**), Título, Emissão, Capital, Saldo, Vencimento, Prorrogações, Tx acordada; `limit` default 50; tipo com pré-faturamento mostra Emissão/Vencimento como "-" — fecha `FE-250` — `RiskOperationsPage.tsx`. Coluna Tipo mostra o **subtipo**; `per_page` default 50; tipo com pré mostra Emissão/Vencimento como "-" (verificado renderizando)
- [x] 8.2 `FE/risk/components/RiskOperationSearch.tsx` — **um** campo (o legado tem dois com a mesma classe), debounce 300 ms, busca em título do portador ou da operação — fecha `FE-251` — **um** campo, `SearchInput` com o `useDebouncedSearch` de 300 ms, buscando em portador **ou** título
- [x] 8.3 `FE/risk/components/RiskOperationFilters.tsx` — empresa e portador do projeto corrente; o filtro de tipo usa `.all` (inclui inativos) enquanto o formulário usa `.active`. **Replicar a divergência** (decisão **B-04**): é o que permite achar operação histórica — fecha `FE-252` — filtros de empresa/portador do projeto; o filtro de tipo usa a lista **completa** e marca "(inativo)", enquanto o formulário usa a cascata `.manual`+`.active` do servidor (**B-04**, replicado)
- [x] 8.4 `DS/DateRangePicker.tsx` em modo range no filtro: escolhendo só a inicial, `from = to`; sem período, o backend usa a janela aberta. Corrige o rótulo de ano do legado — fecha `FE-253` — `DS/DateRangePicker` em modo range; escolhendo só a inicial, o filtro manda `from = to`
- [x] 8.5 `DS/DataTable.tsx` com ordenação multi-coluna tri-state acumulando `ordering_keys[]`, espelhada pela allowlist do servidor — fecha `FE-254` — `DS/DataTable` em `sortMode="server"`, mandando `ordering_keys[]`/`ordering_style[]`. A allowlist do cliente é a mesma do servidor, que responde 400 ao que não conhece
- [x] 8.6 Paginação da lista com tamanho default 50, funcionando porque o total agora é real — fecha `FE-255` — `PaginationPill` no desktop e `MobilePagination` no telefone. **Verificado renderizando: 1/5 páginas** — o total agora é real
- [x] 8.7 `FE/risk/components/RiskOperationRow.tsx` — Ver mais, Editar, Renovar, Prorrogar, Remover; Renovar/Prorrogar só para tipo sem pré-faturamento; ações de escrita somem para readonly. Corrige o título de modal "Excluir renegociação" (rótulo de outro módulo) e troca `history.replaceState` por rota real (D-92) — fecha `FE-256` — Ver mais / Editar / Renovar / Prorrogar / Remover; os dois últimos só para tipo **sem** pré (verificado renderizando); rota real (`/risk-operations/:id`), não `history.replaceState`; título "Excluir operação de risco". Ações de escrita somem para quem não escreve
- [x] 8.8 Guardas `carrier_available` + `manual_control` com as mesmas mensagens, espelhadas no servidor — fecha `FE-257`. No legado os dois predicados são calculados **na view** e despejados em `data-` para o JavaScript decidir (`_body.html.erb:19`, `_body.js.erb:440-453`) — regra que mora só na tela é regra que a API não tem. Agora `GET /risk_operations/availability` os calcula onde o dado está, e a tela mostra um `EmptyState` com a **mesma mensagem** do legado, mais o link para "Limites"
- [x] 8.9 `FE/risk/components/RiskOperationForm.tsx` — cascata empresa (só com limite ativo de tipo manual) → portador → tipo; em edição, ou quando a operação veio de recebível, os três viram texto readonly — fecha `FE-258` — cascata empresa → portador → tipo, cada degrau vindo do servidor com o mesmo `where` do `POST`. Em edição os três viram texto readonly com cadeado
- [x] 8.10 Blocos Cadastro / Datas / Valores / Taxa Acordada / Outros; em edição, "Capital da Operação" readonly e "Saldo Inicial" editável; as 13 tooltips existem como mecanismo, com conteúdo em branco (Q-R9) — fecha `FE-259` — blocos Cadastro / Datas / Valores / Taxa Acordada / Outros; capital readonly na edição, saldo inicial editável; o mecanismo dos tooltips é o `<FieldHelp>` da biblioteca, e **os textos existem** (DEC-88 supera a Q-R9): 12 dos 13 preenchidos, `is_on_variable` ainda `TODO:` e por isso sem ícone
- [x] 8.11 Tipo com pré-faturamento: bloco Datas inteiro e campo "Encerrada" somem; em edição, as datas são readonly **e o servidor aplica a mesma regra** (T-D5) — fecha `FE-260` — o bloco Datas e o campo "Encerrada" somem em tipo com pré; em edição as datas são readonly **e o servidor ignora** (T-D5)
- [x] 8.12 Barra de ação inferior: Salvar habilita com todos os obrigatórios preenchidos e, quando não, **diz o que falta** em vez de o botão sumir. Converte pt-BR → número antes do submit — fecha `FE-261` — a barra diz o que falta ("Falta preencher: empresa, portador, tipo de operação, capital da operação, data de emissão, data de vencimento" — capturado renderizando) em vez de o botão sumir. `MoneyInput` já entrega número
- [x] 8.13 Capital e Saldo Inicial com `DS/MoneyInput`; Taxa acordada com `DS/PercentInput` — quarta e última cópia de máscara do legado eliminada — fecha `FE-262` — `MoneyInput` no capital e no saldo, `PercentInput` na taxa. Verificado executando: digitando `10000000` sai `R$ 100.000,00` (§5.4.9, direita para a esquerda)
- [x] 8.14 Dois bloqueios com `DS/EmptyState`: sem portador com limite manual; sem empresa (com link para criar empresa inline) — fecha `FE-263`. O segundo aparece **também** dentro do formulário, como aviso no campo Portador, quando a cascata volta vazia para a empresa escolhida — visto renderizando: era o caso silencioso que fazia o operador descobrir o critério por tentativa e erro

## Bloco 9 — Frontend: detalhe, extrato e prorrogações (R5 + R6 + R7)

- [x] 9.1 `FE/risk/pages/RiskOperationDetailPage.tsx` — abas GERAL / MOVIMENTAÇÕES / PRORROGAÇÕES (esta só para tipo sem pré-faturamento), com deep-link real por aba (D-92) — fecha `FE-264` — abas GERAL / MOVIMENTAÇÕES / PRORROGAÇÕES, a última só para tipo sem pré. **Deep-link real por `?aba=`** (D-92), verificado: a URL vira `…?aba=movimentacoes`
- [x] 9.2 `FE/risk/components/OperationGeneralTab.tsx` — **"Saldo Inicial" exibido com o sinal negativo gravado**, enquanto o formulário exibe o valor absoluto. **DEC-01 — replicar** e registrar no `improvements-log.md` para o QA não abrir bug — fecha `FE-265` — a aba GERAL mostra **−R$ 100.000,00** enquanto o formulário edita 100.000,00. Registrado no `improvements-log.md`; há teste de front que reprova quem trocar o campo
- [x] 9.3 Chips "Recebível" e "Operação Original" como `<Link>` reais para os respectivos registros — fecha `FE-268` — chips "Recebível" e "Operação original" como `<Link>`
- [x] 9.4 `FE/risk/components/LastMovementCard.tsx` — Data, Tipo e Valor do último movimento (por `sequence`), com o par único de tokens semânticos (débito negativo, crédito positivo) em **light e dark** (D-101) — fecha `FE-266` — `LastMovementCard`, com o par único de tokens (`--success`/`--negative`, D-101). Conferido nos dois modos
- [x] 9.5 `FE/risk/components/MovementsTab.tsx` — colunas sequência, Data, Tipo, Valor Movimento, Saldo, Observação, menu, **paginada** — fecha `FE-269` — `MovementsTab` com sequência, Data, Tipo, Valor, Saldo, Observação e menu, paginada
- [x] 9.6 `FE/risk/components/MovementRow.tsx` — valor renderizado como `R$ 1.234,56C` / `…D` (sufixo do `credit_type`, **replicado**), célula colorida pelos tokens semânticos — fecha `FE-270` — valor renderizado como `R$ 30.000,00C` / `R$ 2.500,00D`, com o sufixo vindo do `credit_type` do servidor e a cor pelos tokens. Verificado renderizando
- [x] 9.7 `FE/risk/components/MovementDrawer.tsx` — Data (datepicker **alinhado ao servidor**, fim do off-by-one de `issue_date + 1`/`due_date + 1`), Tipo (`.manual`, readonly em transferência/edição), Valor, Observação; Salvar só habilita com valor > 0. Toasts corretos (hoje dizem "A previsão foi criada/atualizada com sucesso", de outro módulo) — fecha `FE-271` — `MovementDrawer` com a janela vinda do servidor (fim do off-by-one), tipo readonly em transferência, Salvar só com valor > 0 e toasts que falam de movimento
- [x] 9.8 Botão "Transferir" só para operação de subtipo pré-faturamento, abrindo o drawer com o tipo fixado — fecha `FE-272` — "Transferir" só aparece quando `is_pre`
- [x] 9.9 Confirmação de exclusão de movimento + recarga da lista e do cartão de última movimentação; corrige o título "Excluir previsão" — fecha `FE-273` — confirmação com título "Excluir movimento", recarga da lista e do cartão pela invalidação das três chaves
- [x] 9.10 Estados vazio e de **erro** nas listas de movimentos e prorrogações — hoje **não há estado de erro em nenhuma das duas** — fecha `FE-276` — as duas listas passam pelo `AsyncSection`: carregando, vazio, **erro** e conteúdo. Há teste de front que reprova quem tirar
- [x] 9.11 `FE/risk/components/RenewalsCard.tsx` — tabela de renovações (ID, Emissão, Vencimento) por `original_id`, só quando existem, mostrando **o estado de cada elo** da cadeia (consequência de IMP-R1) — fecha `FE-267` — `RenewalsCard` por `original_id`, só quando há mais de um elo, **mostrando o estado de cada um**. Verificado renderizando: "2 operações · 2 em aberto" — a consequência da DEC-35 fica visível na tela, e não numa diferença de número no painel
- [x] 9.12 `FE/risk/components/ExtensionDrawer.tsx` — lista (Prorrogado Em, Data Original, Nova Data, Observação) + drawer com nova data (`minDate = due_date + 1`) e observação — fecha `FE-274` — `ExtensionDrawer` + `ExtensionsTab` (Prorrogado em, Data original, Nova data, Por, Observação), com `min` vindo do servidor
- [x] 9.13 `FE/risk/components/RenewalDrawer.tsx` — nova emissão (default hoje) e novo vencimento (default = vencimento original + mesmo prazo), com `minDate`/`maxDate` que hoje **não existem** (dá para escolher vencimento anterior à emissão). Toasts corretos (hoje dizem "O tipo de operação foi criado/atualizado com sucesso") — fecha `FE-275` — `RenewalDrawer` com as duas datas sugeridas pelo **servidor** e `min` no vencimento. Toasts corretos. O aviso da DEC-35 está na tela

## Bloco 10 — Testes

> Os goldens estão dentro dos Blocos 3, 4 e 6, por decisão de desenho. Este bloco cobre o
> que não é golden.

- [x] 10.1 `spec/models/risk_operation_spec.rb` — a cascata de 5 callbacks; resolução do limite pela quádrupla **sem** filtrar `is_active`; as validações ausentes que continuam ausentes (Q-R7) — `spec/models/risk_operation_spec.rb`, 20 exemplos
- [x] 10.2 `spec/services/risk/calculator_spec.rb` — os goldens `M1` e `M5` reunidos, incluindo o caso de operação sem movimento (`balance = original_balance` **e** `balance_on = 0`) — `spec/services/risk/chain_spec.rb`, 17 exemplos (M1 e M5, incluindo `balance = original_balance` × `balance_on = 0`)
- [x] 10.3 `spec/services/risk/transfer_service_spec.rb` — golden `M2`; sem par nada é gravado; transferir a partir da antecipação não gera contrapartida — `spec/services/risk/transfer_service_spec.rb`, 10 exemplos
- [x] 10.4 `spec/services/risk/renewal_service_spec.rb` — golden `M3`, com a asserção explícita de que a original fica encerrada e a exposição deixa de dobrar — `spec/services/risk/renewal_and_extension_spec.rb`. **A asserção é a INVERSA da que a tarefa pedia**, por DEC-35: `expect(operacao.reload.is_ended).to be(false)` e a exposição em 01/06/2026 conta **duas** operações
- [x] 10.5 `spec/services/risk/extension_service_spec.rb` — golden `M4`, incluindo a recusa de encurtar o vencimento — o mesmo arquivo, incluindo a recusa de encurtar e a de data igual
- [x] 10.6 `spec/requests/api/v1/risk_operations_spec.rb` — CRUD, 422 na exclusão bloqueada por recibo, 400 em chave de ordenação inválida, paginação com `X-Total-Count` real — `spec/requests/api/v1/risk_operations_spec.rb`, 47 exemplos
- [x] 10.7 Teste de escopo (**C1**) provando as duas IDORs fechadas: um usuário de `P1` não alcança operação nem movimento de `P2` **nem passando `risk_operation_id`** — três exemplos: operação, extrato e prorrogações de `P2` respondem 404 a partir de `P1`, **e** `risk_operation_id` de `P2` na lista devolve vazio
- [x] 10.8 Teste de autorização (**C3**) por endpoint, verificando **os dois lados** da hierarquia, e `user_is_readonly` bloqueando escrita **no servidor** — os dois lados: Colaborador **com** participação lê e escreve; **sem** participação não alcança; Admin alcança sem participação (DEC-99); sem sessão, 401
- [x] 10.9 Teste de integração do contrato `OPS-238`/`DB-239` com o bloco `receivables`, nos dois ramos (com pré → movimento na estática; sem pré → operação nova) — `spec/services/risk/receivable_contract_spec.rb`, 10 exemplos nos dois ramos
- [x] 10.10 Front: `tsc --noEmit` **0 erro**; `vitest` **388 + 24 = 412 passando**. Revisão visual **renderizando**, com captura: lista, formulário (com o combobox ABERTO), detalhe, extrato e prorrogações, em **light e dark** × **1440×900 e 390×844**. `document.documentElement.scrollWidth == window.innerWidth` nas cinco telas, nas duas larguras. **Zero erro de console.** No telefone: `MobileCard`, `MobileRowActions` no rodapé e `MobilePagination` — verificados abrindo a folha de ações

## Bloco 11 — Paridade e fechamento

- [x] 11.1 Marcar no `parity-ledger.md` — **59 IDs** `pending` → `migrated`, um a um, cada um com alvo, teste e nota. São 52 `build` + os 3 `build?` resolvidos + os 4 órfãos adotados no Phase 2 (`DB-576`..`DB-579`), com os 2 `adapt` (`OPS-238`, `DB-239`) contados entre eles. Seção própria no topo do razão, dizendo que **nenhum dos 59 tem oráculo de produção**
- [x] 11.2 Esta fatia **não tem nenhum `drop`** — confirmar que nada foi descartado por omissão (os 3 `drop` de `risk` pertencem a S5) — confirmado: nenhum ID desta fatia foi descartado. Os 3 `drop` de `risk` (`FE-234`, `OPS-234`, `OPS-239`) são da S5
- [x] 11.3 Os 3 `build?` estão **fechados**, e nenhum ficou como o `proposal.md` previa:
      **`BE-262`** — a resolução prevista era a spec (422 pedindo escolha). **A DEC-67 decidiu diferente** e vence: entra o subtipo padrão declarado do tipo.
      **`BE-268`** — a resolução prevista era a spec (`is_ended` sem consequência). **A DEC-35 confirmou**, e as três não-consequências têm teste.
      **`FE-260`** — adotada a regra de servidor, igual à `FE-297` da S8: as datas não são editáveis **e a API as ignora**.
      Os três entram no razão como `build`, com a decisão citada na nota.
- [x] 11.4 **REESCRITA pela DEC-115 (26/08/2026), e cumprida na forma reescrita.**
      ~~Conferir contra o legado, com o dump carregado, os valores dos goldens `M1`…`M5`~~
      → **Conferir contra a FONTE de 2022**, registrando em cada golden a marca de que ele
      tem **fonte, não oráculo**.
      **Por que mudou:** as seis migrations desta família estão entre as **24 que nunca
      subiram** (`analise-dump-producao.md` §1) — a última aplicada em produção é de
      **25/05/2022** e o sistema rodou em uso até **31/05/2025**. O dump não tem uma única
      operação de risco tipada, um único movimento nem uma única prorrogação. Perguntado se
      existia outra base, o usuário respondeu *"nao tem, a tabela de excel que tinha foi
      perdida"*. Sem oráculo, adiar seria fingir.
      **Auditoria de QA em 26/08/2026 — esta fatia já estava conforme, e é a única das três
      que estava.** Os cinco goldens carregam a marca e a fonte, conferido arquivo por
      arquivo: `chain_spec.rb:8` (`M1` em `:24`, `M5` em `:180`),
      `transfer_service_spec.rb:7` (`M2` em `:25`), `renewal_and_extension_spec.rb:7`
      (`M3` em `:27`, `M4` em `:164`) e `support/risk_operation_scenarios.rb:5`, com
      `FONTE_CADEIA = '../sfg/app/models/risk_operation.rb:98-111'` e `FONTE_SINAL`
      declarados como constante — que é a forma mais difícil de apagar por acidente, e a
      S5 acabou de provar por que isso importa.
      **O que sustenta os números, e que continua não sendo oráculo:** `M1` conferido
      **executando pela tela** (0,00 / 2.500,00 / −27.500,00); `M3` **medido no banco**;
      e o cruzamento com a segunda implementação independente da mesma cadeia — o seed da
      S20 — com **855 operações, 855 cadeias, 0 divergência**.
      **NÃO promove nada a `verified`.** Os 59 IDs desta fatia param em `migrated`, e a
      seção própria no topo do razão já diz que nenhum deles tem oráculo de produção.
- [x] 11.5 Handshake com **S6**: `SR-5`/`SR-6` conseguem criar operação e movimento pelo borderô, e a validação "não possui limite cadastrado" dispara — o handshake é o próprio `receivable_contract_spec.rb`: o borderô cria operação e movimento pelos dois ramos, e a validação "não tem limite de risco ativo" dispara com o limite desativado
- [x] 11.6 Handshake com **S8**: `RiskOperation` responde como `operation_class` da classe **LIQ** de remuneração, e `available_for_receipt` funciona — teste no mesmo arquivo: `Receipt::KIND_BY_OPERATION['RiskOperation'] == 'LIQ'`, `has_one :receipt` com `restrict_with_error` e `available_for_receipt` filtrando por `receipt_id`
- [x] 11.7 ~~Reconferir os goldens de exposição de **S5** depois de IMP-R1~~ — **o IMP-R1 não existe** (DEC-35), então não há mudança de exposição a conferir. A reconferência foi feita mesmo assim, porque a S7 mexeu no que a S5 lê, e **três goldens da S5 mudaram de valor**, todos por motivo escrito:
      1. **`static_pair_service_spec`** — o par estático nasce com `balance = original_balance`, não `0`. O `0` era o valor de ENTRADA; o `update_values` do legado (que é da S7) o sobrescreve antes do INSERT. O mesmo exemplo agora prova as duas coisas juntas: `balance == original_balance` **e** `balance_on == 0` (golden `L2` intacto).
      2. **`cenario_l1`** — deixou de criar o primeiro movimento à mão, porque o `after_create` da S7 passou a criá-lo. Os três saldos golden (0,00 / 2.500,00 / −27.500,00) **não mudaram** — era o contrato que o próprio helper da S5 anunciava.
      3. **`aggregate_service_spec`** (2 exemplos) — passaram a criar a operação com `operation_value: 0`, senão o movimento automático de liberação entraria na conta e o exemplo deixaria de medir o que mede.
      **Nenhuma fórmula de exposição foi tocada.** `spec/services/risk` + `spec/models/risk_control_spec.rb` + `spec/requests/api/v1/risk_controls_spec.rb`: **95 exemplos, 0 falhas**


## Fechamento de órfãos do Phase 2 — esquema de operações e movimentos

Quatro IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Conferir `risk_operations` contra a descrição de `data-schema`, incluindo o vínculo
      com `risk_control` que o legado validava como obrigatório **sem** nenhuma associação
      declarada. **Fecha: DB-576.** — conferida contra `data-schema`. O vínculo com `risk_control` que o legado validava **sem associação declarada** agora é `belongs_to :risk_control` + coluna `NOT NULL` + FK
- [x] F.2 `risk_operation_extensions` com FK em cascata e **check** `new_due_date >
      original_due_date` — que o legado não tinha. **Fecha: DB-577.** — conferida: FK `on_delete: :cascade`, índice e `check_constraint` `new_due_date > original_due_date`, mais a validação de model que dá a mensagem
- [x] F.3 `risk_movement_types` + seed de 8 linhas, plugado no arcabouço de S3. **Fecha:
      DB-578.** — conferido: as 8 linhas são semeadas por `Seeds::Reference::RiskMovementTypes`, com as três chaves funcionais como contrato. A factory de operação semeia o catálogo, então toda criação exercita o caminho real
- [x] F.4 `risk_movements` com índice em (operação, `date`, `created_at`) e `order`
      renomeado para `sequence`. **Fecha: DB-579.** — conferido: índice `(risk_operation_id, date, created_at)` e `sequence` no lugar de `order`. O recálculo usa exatamente essa ordenação
- [x] F.5 Registrar, na tarefa de ETL correspondente, que a carga de movimentos **tem** de
      respeitar a ordem de `sequence` — o saldo depende dela. **Fecha: DB-579 (parte).** —
      registrado em `app/lib/sfg/etl/converters/risk_movements.rb`. O requisito de ordem já
      estava lá (S14); a S7 acrescentou **o que só se sabe com o motor pronto**: (a) o
      `created_at` de origem tem de ser preservado, porque é o desempate de movimentos na
      mesma data; (b) o `sequence` carregado **pode ser sobrescrito** — ele é recalculado no
      `before_validation` de todo save, então a reconciliação precisa conferir **a ordem**, e
      não só o saldo final; (c) **não salvar a operação durante a carga**, porque isso
      dispara o recálculo e reescreve o extrato migrado
