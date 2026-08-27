# Tasks: S20 — Seed de demonstração

Fila de trabalho da fatia **S20**. Ordenada por camada: **razão → orquestração → escritores
que rodam hoje → escritores que aguardam fatia → testes → prova pela tela**.

**Regras desta fila** (valem para toda tarefa):

1. **Nenhuma tarefa cria model, migration ou endpoint.** A trilha é
   `backend/db/seeds/demo/`, `backend/lib/tasks/demo.rake` e `backend/spec/`. Nada de
   `app/`, nada de `frontend/src`, nada de `config/`.
2. **Toda escrita usa `find_or_initialize_by` com chave natural.** `create` / `create!` sem
   chave é defeito, não estilo.
3. **Nenhuma data literal.** Tudo relativo à data-base.
4. Um escritor cuja tarefa está marcada mas cujo model ainda não existe **é validado pelo
   pulo**: `rake demo:seed` avisa e segue. A tarefa fecha assim; a gravação de verdade é
   conferida quando a fatia dona entregar.
5. Os portões de sempre: `bundle exec rspec` verde, `bin/rails zeitwerk:check` limpo, e
   `rake demo:seed` duas vezes seguidas com contagem idêntica na segunda.

## 1. Suporte determinístico

- [x] 1.1 `support/rng.rb` — `Demo::Support::Rng` com semente fixa `20260828` e **um gerador
  por seção** (`for(:receivables)`), para que acrescentar um módulo não mude os números dos
  outros. Amostragem uniforme em faixa, escolha ponderada e distribuição com cauda.
- [x] 1.2 `support/br.rb` — CNPJ com os dois dígitos verificadores calculados, raiz
  compartilhada por grupo com o número de ordem da filial variando; sufixos de razão
  social; formatação de CNPJ.
- [x] 1.3 `support/money.rb` — arredondamento monetário de 2 casas que **evita valor
  redondo**, e o IOF de crédito PJ pela regra real (0,0082%/dia limitado a 365 dias + 0,38%
  adicional).
- [x] 1.4 Data-base parametrizável: `Date.current` por padrão, `DEMO_SEED_BASE_DATE`
  sobrepondo. A série é `M-23` … `M0`.

## 2. O razão (`Demo::Ledger`) — Ruby puro, zero ActiveRecord

- [x] 2.0 `ledger/records.rb` — os `Struct` do razão, com nomes de **negócio**. A tradução
  para nome de coluna mora no escritor, e só lá.
- [x] 2.1 `ledger/cast.rb` — as **5 contrapartes** de `demo-seed-design.md` §5.1, com códigos
  bancários **não atribuídos** (894/907/912/923/936) e personalidade consistente: quem cobra
  taxa menor concede limite maior e recusa mais.
- [x] 2.2 `ledger/cast.rb` — os **12 clientes** de §5.2, com os 4 perfis (2 grandes, 4 médios,
  4 pequenos, 1 em recuperação, 1 recém-entrante), razão social autoral, CNPJ válido, cidade
  e `closing_date` variados.
- [x] 2.3 `ledger/cast.rb` — as **empresas do grupo** (~28), com sufixos plausíveis e CNPJ de
  filial da mesma raiz do grupo.
- [x] 2.4 `ledger/controls.rb` — a matriz **empresa × carrier × modalidade** com `limite` e
  `taxa`, dentro da faixa da contraparte. Duas combinações ficam em ~92% de utilização, de
  propósito, para o alerta de limite ter o que mostrar; **nenhuma estoura**.
- [x] 2.5 `ledger/timeline.rb` — os 24 meses com a história de §8: estabilidade nos meses
  1–8, entrada do FIDC Aurora no mês 9, retração sazonal em dez/jan, dificuldade do cliente
  #11 no mês 15, recuperação e entrada do cliente #12 nos meses 16–24.
- [x] 2.6 `ledger/receivables.rb` — os borderôs, com `vlr_bruto_final = valor_bruto −
  vlr_bruto_recusado`, `qtd_final = qtd_titulos − qtd_recusada`, recusa entre 0% e 12% com a
  maioria em zero, prazo médio ponderado da empresa e do banco, e
  `diferenca_float = float_calculado − float_acordado`.
- [x] 2.7 `ledger/operations.rb` — as operações de risco (~70% encerradas, ~25% vivas, ~5%
  vencidas), com `agreed_rate` a até 0,15 p.p. da taxa do controle.
- [x] 2.8 `ledger/operations.rb` — os movimentos, e o **saldo derivado deles** na ordem de
  `sequence`, respeitando a convenção de sinal do DEC-01. O saldo **não é sorteado**.
- [x] 2.9 `ledger/ancillary.rb` — renegociações concentradas nos clientes 3, 7 e 11, com
  `total_debt = original_pending_value + additional_value` e parcelas que somam o total.
- [x] 2.10 `ledger/ancillary.rb` — garantias e a série de indicadores mensais, com o
  indicador de **volume operado** igual à soma dos borderôs do mês.

## 3. Orquestração

- [x] 3.1 `writers/base.rb` — o contrato: `requires`, `owner_slice`, `call(ledger, io:)`
  devolvendo `{ created:, updated:, unchanged: }`.
- [x] 3.2 `orchestrator.rb` — lista ordenada por dependência real, execução com pulo ruidoso
  e relatório final em tabela.
- [x] 3.3 `lib/tasks/demo.rake` — `demo:seed`, `demo:reset`, `demo:reseed` deixam de abortar.
- [x] 3.4 `demo:status` — mostra o que está semeado e **qual fatia** cada módulo pendente
  aguarda, sem escrever nada.
- [x] 3.5 `demo:ledger` — imprime a prova aritmética (um borderô, a operação que ele gerou,
  os movimentos, o saldo e o total do painel) **sem tocar no banco**.

## 4. Escritores que rodam hoje

- [x] 4.1 `writers/scaffolding.rb` — remove os rastros de conferência de S0 (`alpha`, `beta`,
  `s0.*@sfg.test`), autorizado pela DEC-64, e garante os seeds de referência de papéis e
  permissões (idempotentes, já existentes em `Seeds::Reference::*`).
- [x] 4.2 `writers/users.rb` — o elenco de §9 nos papéis do DEC-41, com o sexto usuário
  recebendo `user_is_readonly` via `user_permissions`. E-mails em `@safegold.test`.
- [x] 4.3 `writers/projects.rb` — os 12 clientes. Chave natural `slug`. Preenche o que o
  model aceitar hoje (`name`, `slug`, `user_id`, `is_active`) e o que S4 acrescentar depois
  (`formal`, `closing_date`, `segment_id`, `integration_key`, `color`) **por detecção de
  coluna**, sem quebrar enquanto elas não existirem.
- [x] 4.4 `writers/memberships.rb` — a teia de participações que prova o escopo por
  membership: o Admin em todos, o Gerente num subconjunto, os dois Colaboradores em projetos
  **diferentes**, o readonly num só.

## 5. Escritores que aguardam a fatia dona

- [x] 5.1 `writers/guarantee_types.rb` — os tipos de garantia **marcados como provisórios**
  (DEC-86). Aguarda `ProjectGuaranteeType` (S3).
- [x] 5.2 `writers/carriers.rb` — as 5 contrapartes e o grupo. Aguarda `Carrier` (S3).
- [x] 5.3 `writers/segments.rb` — os 3 segmentos e os subsegmentos que o legado deixou
  vazios. Aguarda `Segment` / `SubSegment` (S3).
- [x] 5.4 `writers/companies.rb` — as empresas. Chave `(project_id, title)`. Aguarda
  `Company` (S4).
- [x] 5.5 `writers/carrier_connections.rb` — quais carriers cada projeto opera. Aguarda
  `ProjectToCarrierConnection` (S4).
- [x] 5.6 `writers/guarantees.rb` — as garantias por projeto. Aguarda `ProjectGuarantee` (S4).
- [x] 5.7 `writers/risk_controls.rb` — a matriz de limites, gravando `limite`/`taxa` +
  `risk_operation_type_id` e **deixando as 8 colunas pré-2022 nulas**. Aguarda `RiskControl`
  (S5).
- [x] 5.8 `writers/receivable_entries.rb` — os borderôs, com os nomes de coluna em pt-BR que
  a decisão **D-G** preservou (`nro_bordero`, `valor_bruto`, `vlr_bruto_recusado`…). Aguarda
  `ReceivableEntry` (S6).
- [x] 5.9 `writers/risk_operations.rb` — as operações. Aguarda `RiskOperation` (S7).
- [x] 5.10 `writers/risk_movements.rb` — os movimentos, gravando em **`sequence`** (o `order`
  do legado, renomeado por DB-236). Aguarda `RiskMovement` (S7).
- [x] 5.11 `writers/structured_operations.rb` — as operações estruturadas. Aguarda
  `StructuredOperation` (S8).
- [x] 5.12 `writers/renegotiations.rb` — renegociações e parcelas. Aguarda `Renegotiation`
  (S9).
- [x] 5.13 `writers/indicators.rb` — indicadores e as entradas mensais. Aguarda `Indicator` /
  `IndicatorEntry` (S10).
- [x] 5.14 Em todo escritor: se a fatia dona já entregou serviço de cálculo, **chamá-lo** em
  vez de confiar no número do razão (`demo-seed-design.md` §7).

## 6. Testes

- [x] 6.1 Spec do razão: as **7 regras de coerência** de §7 do desenho, uma expectativa por
  regra. Roda sem nenhum model de domínio existir.
- [x] 6.2 Spec do razão: as invariantes entre domínios — borderô, float, limite, taxa,
  renegociação e o indicador que bate com a soma dos borderôs.
- [x] 6.3 Spec do razão: determinismo — dois razões construídos com a mesma data-base
  produzem os mesmos números.
- [x] 6.4 Spec do orquestrador: módulo com model ausente **pula** e o seed prossegue.
- [x] 6.5 Spec de idempotência: rodar o orquestrador duas vezes não muda contagem.
- [x] 6.6 Spec de plausibilidade: CNPJ válido, sem rótulo de teste, sem código bancário
  atribuído, sem valor redondo.

## 7. Prova de execução

- [x] 7.1 `rake demo:seed` executado de verdade, com o relatório do que semeou e do que
  pulou.
- [x] 7.2 `rake demo:seed` executado **duas vezes**, com as contagens das duas execuções
  registradas lado a lado.
- [x] 7.3 A aplicação aberta no navegador depois de semear, conferindo que as telas que já
  existem mostram o dado (lista de clientes com paginação, troca de projeto, usuários).
- [x] 7.4 `bundle exec rspec` e `bin/rails zeitwerk:check` verdes.

## 8. Segunda onda — os models chegaram (26/08/2026, DEC-102)

Sete fatias entregaram model desde que esta fila foi escrita, e o que era "pula com aviso"
virou gravação de verdade. **Nenhuma tarefa acima foi desmarcada**: o que segue é o que a
entrega delas passou a exigir.

- [x] 8.1 `scaffolding` chama `Seeds::Reference::Runner.call!` — os **seis** catálogos de
  referência, e não a lista própria de dois. Os escritores de limite e de movimentação
  deixam de criar tipo e passam a **resolver por `integration_key`** (improvements-log
  DEMO-S20-01).
- [x] 8.2 `writers/risk_operations.rb` grava `operation_type_id` (do limite) e
  `operation_subtype_id` (o liquidável), e **exige** o limite: `risk_control_id` é
  `null: false` na S5. Era a causa das 11 falhas do `orchestrator_spec`.
- [x] 8.3 `writers/providers.rb` — **escritor novo**. `renegotiations.provider_id` é
  obrigatório e a chave de integração da renegociação deriva do nome do fornecedor; sem
  fornecedor não há renegociação. 75 linhas, escopadas por projeto (C1), com CNPJ válido.
- [x] 8.4 `writers/renegotiations.rb` reescrito: grava o contrato e as parcelas, cria **um
  pagamento por parcela paga** e chama `Renegotiations::AggregateService.recalculate!` —
  os ~20 agregados são da S9 (contrato C2), não do razão (DEMO-S20-05).
- [x] 8.5 `writers/indicators.rb` grava `value_type: "Dinheiro"` (único aceito hoje,
  Q-R32) e semeia **só os indicadores em dinheiro**, anunciando os três que aguardam a
  S10. `title`/`key`/`value_type` do lançamento não são escritos: o model os copia.
- [x] 8.6 O razão passou a falar a língua das tabelas entregues: `kind` da renegociação nos
  quatro valores do CHECK, `renegotiation_date`, `operation_interest_rate` e
  `original_value` (o "vencido", que ficava zerado na tela), e movimento **dentro** da
  janela da operação.
- [x] 8.7 `normalize_chain!` — a cadeia de movimentos ordenada por data, com saldo
  recalculado, para que o `balance` da operação e o `balance_on` do painel sejam o mesmo
  número (DEMO-S20-04).
- [x] 8.8 Idempotência restaurada com as tabelas reais: título de empresa único por
  projeto, `document_type` em caixa alta, título de indicador já normalizado
  (DEMO-S20-03). Prova: segunda execução `0 criados, 0 atualizados, 6.162 inalterados`.
- [x] 8.9 `Base#run` reporta `:failed` em vez de derrubar o seed; `rake demo:seed` sai com
  status ≠ 0 (DEMO-S20-02). Spec novo: `nenhum escritor falha`.
- [x] 8.10 O reset **descobre** as tabelas escopadas por projeto e as ordena por FK
  (DEMO-S20-06). Achado executando: `availability_entries`, de outra fatia, referencia
  `companies` e derrubava o reset no meio.
- [x] 8.11 Vitrine de estados: as quatro cores da renegociação têm exemplo no banco
  (DEMO-S20-07).
- [x] 8.13 **Um** estouro de limite, escolhido: o cliente em recuperação passa de 100% no
  Vértice/Fomento. Sem ele o aviso da tela de risco (NEW-005, DEC-95) era recurso entregue
  que a demonstração nunca conseguiria mostrar — a promessa original era "nenhum estoura".
  Os dois grupos em ~92% continuam, e agora o alvo vale para o **grupo**
  (cliente × portador × modalidade), porque é assim que a tela agrega.
- [x] 8.14 O alvo de utilização passou a ser medido pela **janela da data-base**
  (`RiskOperation.on_date`), que é o número que a tela mostra. O razão dizia 92% e o painel
  mostrava 53%: os dois estavam certos, medindo coisas diferentes.
- [x] 8.15 A liquidação é o **último** lançamento da cadeia. Datada antes dos juros, deixava
  o saldo positivo no meio do caminho e o painel exibia exposição **negativa** (−1,41% de um
  limite) para uma operação encerrada. Travado por spec.
- [x] 8.16 **Nota de disponibilidade** (ActionText) em 3 dos 12 projetos, vazia nos outros 9.
  Campo de texto rico que o seed deixa sempre vazio é onde mora o defeito que o `tsc` não vê
  — o detalhe de projeto já caiu inteiro por `null` numa nota vazia.
- [x] 8.17 O **OG é o único sem projeto corrente**, de propósito: é ele que demonstra o
  `409 PROJECT_NOT_SELECTED` (a tela de escolha), e é o usuário que a apresentação ao
  cliente não usa. Travado por spec.
- [x] 8.18 **Piso de 3 renegociações por cliente** (a concentração em 3/7/11 continua). A S9
  entregou a tela enquanto esta onda rodava, e o projeto que a apresentação abre primeiro
  não tinha nenhuma: quem clicasse em "Renegociações" na primeira tela via lista vazia.
  São 61 renegociações, 694 parcelas e 446 pagamentos.
- [x] 8.12 Execução real em `sfg9_dev`: seed → seed (0/0) → reset (6 do elenco removidos,
  5 de fora **preservados**, incluindo os OGs de login) → seed. Telas conferidas no
  navegador em 1440×900 e 390×844, claro e escuro, com três usuários do elenco.

## 9. Onda de 26/08 (tarde) — a fatia CRESCE, e isso é legítimo

A S20 fechou **66/66** antes de a S8 existir. Uma fatia de seed **não termina**: cada fatia
que entrega tabela nova acrescenta trabalho aqui, porque o seed é o único lugar onde as
tabelas de todas as fatias precisam conversar. Fechar a lista e recusar tarefa nova seria
transformar "66/66" em mentira — e o buraco desta onda foi achado pelo usuário **abrindo a
tela**, não por portão nenhum.

- [x] 9.1 `writers/remunerations.rb` — a **remuneração** (S8). Chave natural
  `(project_id, operation_type_type, operation_type_id)`, o índice único DB-284. Cobre as
  **duas** classes: `LIQ` → `RiskOperationType` e `EST` → `StructuredOperationType`.
  `title` **não** é escrito: o `before_validation` do model o reescreve em todo save
  (B-06), e propô-lo aqui deixaria "65 atualizados" para sempre.
- [x] 9.2 `ledger/billing.rb` — a **tabela de preço**. `Billing.fee_for` é a ÚNICA fonte da
  taxa: a remuneração e o `fee` do recibo saem dela, pela mesma chave. Antes o recibo
  sorteava a própria taxa e o mesmo cliente aparecia faturado a duas taxas na mesma
  modalidade. Bandas por porte **dentro** de `FEE_RANGE` (desconto por volume) e prêmio de
  18% na estruturada.
- [x] 9.3 Cobertura **derivada do que o cliente opera** — modalidades dos limites (LIQ) e
  das estruturadas (EST). 65 remunerações em 12 projetos, e toda linha da tela responde a
  "por que esta taxa existe?" com uma operação no banco.
- [x] 9.4 `orchestrator.rb` — `Writers::Remunerations` **depois** dos dois catálogos de
  tipo e **antes** de `Writers::Charges`.
- [x] 9.5 `writers/charges.rb` — `remuneration_id` deixa de ser `nil` hardcoded. Título,
  taxa e `temp_id` passam a sair da remuneração, como em
  `Charges::ReceiptGenerator#build_attributes`. **238 de 238** recibos com remuneração.
- [x] 9.6 `writers/charges.rb` — o outro lado do vínculo (DB-165): `operation.receipt_id`.
  Sem ele a operação já faturada continuava **listada como candidata**, e a mesma operação
  aparecia duas vezes na tela de recibos.
- [x] 9.7 `writers/structured_operations.rb` — o escritor **nunca tinha rodado** contra
  tabela de verdade. Duas correções: `user_id` é obrigatório (`structured_operation.rb:95`,
  o escritor inteiro voltava atrás e as 136 sumiam) e `balance` **não** é escrito (o
  `reset_balance_from_original` o reescreve em todo save, golden E6).
- [x] 9.8 O catálogo de tipos de operação estruturada deixa de ter **dois donos**: quem o
  semeia é `Seeds::Reference::StructuredOperationTypes`, e o escritor só o resolve pela
  `integration_key`. Antes a referência semeava os quatro com `is_default: true` e o seed
  de demonstração só o Fomento.
- [x] 9.9 **O seed CONVERGE, não acumula.** `charges`, `receipts` e `risk_operations`
  ganham poda por diff contra o razão. A chave natural do pacote é `(project_id, date)` e a
  data é relativa à data-base: rodar em outro dia criava um segundo pacote. Medido: o razão
  dizia 42 e a tela mostrava **76**, três gerações empilhadas.
- [x] 9.10 **O plano de utilização de limite** (`Controls::UTILIZATION_PLAN`). Medido antes:
  os 96 limites em 0–30%, máximo de 16,0% — o cartão "Limites no teto" zerado em todos os 12
  projetos e a tela de Controle de Risco sem um exemplo de limite apertado. Depois: 89 em
  0–30%, **3 em 70–90%**, **2 em 90–100%** e **2 acima de 100%** (um por projeto, em
  `alianca-metalurgica` e `serra-azul-textil`).
- [x] 9.11 `Operations.legacy_exposure` — a fórmula do **sistema** (`Σ liquidações −
  Σ encargos`, ver `legacy-defects.md` **D-B20**) replicada em Ruby puro. É contra ela que o
  plano mira. O mecanismo anterior mirava o saldo do razão, que usa a convenção **oposta**:
  92% no razão, 14% na tela. Mesmo modo de falha da 8.14, uma camada mais fundo.
- [x] 9.12 O consumo de limite nasce de **operação viva com amortização parcial**, nunca de
  saldo escrito à mão — é o caso real de limite apertado e o único que a fórmula enxerga.
- [x] 9.13 `spec/lib/demo/coverage_spec.rb` — 5 exemplos novos: faixa de mercado da taxa,
  as duas classes cobertas em todo projeto, nenhuma remuneração de modalidade não operada,
  `receipt.fee == remuneration.value` e o desconto por volume.
- [x] 9.14 `spec/lib/demo/orchestrator_spec.rb` — o exemplo que exigia `skipped` **não
  vazio** passou a reprovar o estado que a fatia perseguia: com S6 e S8 entregues, nenhum
  escritor pula mais. Ele agora exige que todo escritor termine em gravação **ou** em pulo
  explicado.
- [x] 9.15 `lib/tasks/demo.rake` — a seção 4/5 passa a medir pela fórmula do sistema e
  ganha a **distribuição por faixa de consumo**, que é o número que o cartão do dashboard lê.
- [x] 9.16 Execução real em `sfg9_dev`: `demo:seed` três vezes seguidas, a segunda e a
  terceira com **0 criados, 0 atualizados**. Telas conferidas no navegador com o Admin.

## Pendências declaradas (não são tarefas desta fatia)

- **A lista real de tipos de garantia é do cliente** (DEC-86). Os semeados são suposição
  marcada como provisória; substituir é trocar linhas de seed, sem migration.
- **Os catálogos globais** (carteiras, tipos de recebível, fontes e tipos de recurso, tipos
  de movimentação) são **`OPS-540`, da S3**, aplicados pelo deploy. O razão os referencia
  por título.
- **Os serviços de cálculo** (`Risk::*`, `Receivables::*`, `Renegotiations::*`) são das
  fatias donas. Enquanto não existirem, o razão é a fonte do número — e a tarefa 6.1 é o que
  garante que ele não desviou da fórmula.
