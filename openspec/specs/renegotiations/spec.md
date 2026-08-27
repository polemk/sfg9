# Renegotiations Specification

## Purpose
Gestão das renegociações de dívida com fornecedores dentro de um projeto Safegold:
cadastro do acordo (valor original, deságio, taxa acordada), lançamento das previsões
(parcelas) em lote ou avulsas, registro dos pagamentos com mora, os agregados derivados
que alimentam a lista e os cards de resumo, e os anexos documentais do acordo.

## Requirements

### Requirement: BE-190 — Buscar e listar renegociações
O sistema SHALL se comportar conforme os cenários desta seção.
`GET /pub/renegotiations/search` lista as renegociações do projeto corrente com busca
textual, filtros, ordenação e paginação. Fonte legada:
`app/controllers/pub/renegotiations_controller.rb:14-58`; `config/routes.rb:115`.

#### Scenario: Listagem escopada ao projeto corrente
- **GIVEN** um usuário cujo projeto corrente é `P1` e renegociações em `P1` e `P2`
- **WHEN** ele chama a busca sem filtros
- **THEN** somente as renegociações de `P1` são retornadas, com o total filtrado

#### Scenario: Busca por id não escapa do projeto
- **GIVEN** uma renegociação `R` do projeto `P2`
- **WHEN** o usuário de `P1` chama a busca informando `renegotiation_id = R`
- **THEN** o resultado vem vazio e nenhum dado de `P2` é exposto
> Nota: corrige o vazamento de escopo da mesma família de D-16/D-76/D-100 (comportamento legado: `renegotiation_id` reatribuía a query para `Renegotiation.where(id: ...)` e descartava o filtro de projeto)

#### Scenario: Busca textual cobre nome e fornecedor
- **GIVEN** uma renegociação com `title = "Acordo 2026"` e `provider_name = "Fornecedor Alfa"`
- **WHEN** o usuário busca por "Acordo"
- **THEN** a renegociação é encontrada
> Nota: corrige comportamento legado (a busca só casava `provider_name`, embora "Nome" fosse a primeira coluna da tabela — buscar pelo nome não retornava nada)

### Requirement: BE-191 — Filtro por estado
O sistema SHALL se comportar conforme os cenários desta seção.
O parâmetro `state` restringe a lista aos estados Liquidado, Pago, Inconsistente ou Sem
parcela cadastrada. Fonte legada: `app/controllers/pub/renegotiations_controller.rb:22-31`;
`app/models/renegotiation.rb:2-5`.

#### Scenario: Filtro por estado liquidado
- **GIVEN** renegociações em vários estados
- **WHEN** o usuário filtra por `closed`
- **THEN** só as renegociações com `state = "Liquidado"` são listadas

#### Scenario: Filtro "Sem parcela cadastrada"
- **GIVEN** renegociações com e sem parcelas
- **WHEN** o usuário escolhe o filtro `empty`, oferecido no seletor da tela
- **THEN** só as renegociações sem nenhuma parcela são listadas
> Nota: corrige D-49 (comportamento legado: o `case` não tinha `when "empty"`, caía no `else` com `return`, abortava a action sem render e a tela quebrava com 500)

#### Scenario: Estado desconhecido
- **GIVEN** um valor de `state` fora do domínio
- **WHEN** a busca é executada
- **THEN** o filtro é ignorado e a lista completa do projeto é retornada

### Requirement: BE-192 — Filtro por tipo de renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
O parâmetro `kind` restringe a lista aos tipos Financeiro, Operacional, Tributario e
Trabalhista. Fonte legada: `app/controllers/pub/renegotiations_controller.rb:53`;
`app/models/renegotiation.rb:46-49`.

#### Scenario: Filtro por tipo
- **GIVEN** renegociações dos quatro tipos
- **WHEN** o usuário filtra por `Tributario`
- **THEN** só as renegociações desse tipo são listadas, e o total informado reflete o filtro

#### Scenario: Tipo fora do domínio
- **GIVEN** um `kind` inexistente
- **WHEN** a busca é executada
- **THEN** o resultado vem vazio, sem erro

### Requirement: BE-193 — Ordenação multi-coluna da lista
O sistema SHALL se comportar conforme os cenários desta seção.
A lista aceita ordenação acumulada por nome e por fornecedor. Fonte legada:
`app/controllers/pub/renegotiations_controller.rb:44-50`; `app/models/renegotiation.rb:195-223`.

#### Scenario: Ordenação por duas chaves
- **GIVEN** a busca com `ordering_keys = [provider, title]` e `ordering_style = [up, down]`
- **WHEN** ela é executada
- **THEN** o resultado vem ordenado por `provider_name` ascendente e, dentro de cada fornecedor, por `title` descendente

#### Scenario: Chave de ordenação desconhecida
- **GIVEN** uma chave de ordenação fora de `title` e `provider`
- **WHEN** a busca é executada
- **THEN** a chave é ignorada e a ordenação padrão por fornecedor ascendente é aplicada
> Nota: corrige comportamento legado (chave desconhecida virava `nil` e a concatenação `nil + " "` levantava `NoMethodError`)

### Requirement: BE-194 — Paginação da lista de renegociações
O sistema SHALL se comportar conforme os cenários desta seção.
`l` e `o` limitam e deslocam o resultado, com padrão de 20 registros. Fonte legada:
`app/controllers/pub/renegotiations_controller.rb:35-51`, `:133-141`.

#### Scenario: Paginação aplicada de verdade
- **GIVEN** 80 renegociações no projeto e uma busca com `l = 20` e `o = 20`
- **WHEN** ela é executada
- **THEN** vêm 20 registros, começando pelo 21º, e o total informado é 80
> Nota: corrige D-20 (comportamento legado: o padrão `where!(...).order(...).limit(...).offset(...)` descartava a relação nova, então a listagem devolvia todas as renegociações do projeto e a paginação da tela era decorativa)

#### Scenario: Paginação combinada com ordenação
- **GIVEN** a mesma busca com ordenação por fornecedor
- **WHEN** ela é executada
- **THEN** a ordenação e a paginação são aplicadas juntas

#### Scenario: Parâmetros ausentes
- **GIVEN** uma busca sem `l` nem `o`
- **WHEN** ela é executada
- **THEN** o limite padrão é 20 e o deslocamento é 0

### Requirement: BE-195 — Recálculo e leitura dos valores gerais da renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
O endpoint de valores gerais devolve os agregados atualizados da renegociação para os
cards de resumo. Fonte legada: `app/controllers/pub/renegotiations_controller.rb:60-81`;
`config/routes.rb:114`.

#### Scenario: Valores recalculados na leitura
- **GIVEN** uma renegociação cujas parcelas mudaram desde a última gravação
- **WHEN** os valores gerais são solicitados
- **THEN** a resposta traz os agregados recalculados, incluindo `paid_value`, `remaining_value`, `total_debt`, `installments_value`, `unposted_value`, `installment_status` e a indicação de "remover todas", já formatados
> Nota: corrige D-48 (comportamento legado: o hash de 7 valores formatados era montado e descartado; a resposta era o JSON cru do registro, sem `unposted_value` nem a flag de "remover todas")

#### Scenario: Renegociação inexistente
- **GIVEN** um `renegotiation_id` que não existe
- **WHEN** os valores gerais são solicitados
- **THEN** a resposta é 404, e não um erro interno
> Nota: corrige comportamento legado (`@renegotiation` nulo levava a `NoMethodError` e 500)

#### Scenario: Renegociação de outro projeto
- **GIVEN** uma renegociação de outro projeto
- **WHEN** o usuário solicita seus valores gerais
- **THEN** a requisição é recusada por autorização
> Nota: corrige o vazamento de escopo da mesma família de D-16/D-76/D-100 (comportamento legado: leitura cross-tenant sem escopo)

### Requirement: BE-196 — Representação da renegociação com o status de lançamento
O sistema SHALL se comportar conforme os cenários desta seção.
A representação da renegociação inclui o campo derivado `installment_status`. Fonte
legada: `app/models/renegotiation.rb:226-234`.

#### Scenario: Status incluído na representação
- **GIVEN** uma renegociação consultada pela API
- **WHEN** a resposta é montada
- **THEN** ela inclui todas as colunas e o campo derivado `installment_status`

#### Scenario: Serialização com opções
- **GIVEN** uma chamada de serialização que informa opções (campos incluídos ou excluídos)
- **WHEN** a resposta é montada
- **THEN** as opções são respeitadas
> Nota: corrige comportamento legado (o `to_json` sobrescrito quebrava a assinatura padrão e levantava `ArgumentError` quando recebia options)

### Requirement: BE-197 — Rotas REST mortas de renegociação, parcela e pagamento
O sistema SHALL se comportar conforme os cenários desta seção.
As actions `index` e `show` dos três controllers apontam para templates inexistentes e
não são portadas. Fonte legada: `app/controllers/pub/renegotiations_controller.rb:6-12`;
`renegotiation_installments_controller.rb:6-12`; `renegotiation_payments_controller.rb:6-12`.

#### Scenario: Navegação servida pelas rotas do console
- **GIVEN** o ai9 em execução
- **WHEN** o usuário abre a lista ou o detalhe de uma renegociação
- **THEN** as telas são servidas pelas rotas de navegação do console, e as 6 rotas REST mortas não existem
> Nota: DEC-09 — as rotas são comprovadamente mortas (nenhum dos 6 templates existe no disco) e entram no ledger como `dropped` com evidência

### Requirement: BE-198 — Criar renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
`POST /pub/renegotiations` cria o acordo e já calcula seus agregados iniciais. Fonte
legada: `app/controllers/pub/renegotiations_controller.rb:83-93`.

#### Scenario: Criação bem-sucedida
- **GIVEN** um formulário válido com fornecedor, empresa, tipo, valores e taxa acordada
- **WHEN** a renegociação é criada
- **THEN** o registro é persistido com os agregados calculados a partir das parcelas (nenhuma, no momento da criação) e o estado correspondente
> Nota: corrige comportamento legado (não chamava `update_values!` após criar, então o registro nascia com todos os agregados zerados e `state = "Inconsistente"` até a primeira parcela)

#### Scenario: Mensagem distingue criação de atualização
- **GIVEN** a criação concluída com sucesso
- **WHEN** a resposta é apresentada
- **THEN** a mensagem informa que a renegociação foi criada
> Nota: corrige comportamento legado (a mensagem dizia "foi atualizada com sucesso" também na criação)

### Requirement: BE-199 — Derivações, validações e normalização da renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
Na criação o sistema copia o nome do fornecedor, gera a chave de integração e carimba a
gestão do projeto; as validações exigem os campos do acordo. Fonte legada:
`app/models/renegotiation.rb:13-36`; `app/controllers/pub/renegotiations_controller.rb:143-188`.

#### Scenario: Derivações na criação
- **GIVEN** um fornecedor "Fornecedor Alfa" e o nome da renegociação em branco
- **WHEN** a renegociação é criada
- **THEN** `provider_name = "Fornecedor Alfa"`, `title = "Fornecedor Alfa"`, `correct_value = total_debt`, `integration_key = "fornecedor_alfa"` e `has_safegold_management` é copiado do projeto

#### Scenario: Campos obrigatórios ausentes
- **GIVEN** um payload sem `kind` e sem `renegotiation_date`
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 listando os dois campos com nomes em pt-BR

#### Scenario: Chave de integração duplicada
- **GIVEN** dois fornecedores com o mesmo título
- **WHEN** renegociações são criadas para os dois
- **THEN** cada uma recebe uma chave de integração distinta
> Nota: corrige comportamento legado (a chave era derivada do nome do fornecedor e não era única — homônimos colidiam em silêncio)

#### Scenario: Valores zerados ou negativos
- **GIVEN** `original_value = 0`, `total_debt = -100` e `operation_interest_rate = -2`
- **WHEN** a criação é submetida
- **THEN** os valores são aceitos, como no legado
> AMBIGUIDADE: o legado só valida presença de `original_value`, `total_debt` e `operation_interest_rate`; confirmar se o ai9 deve exigir valores positivos

### Requirement: BE-200 — Editar renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
`PATCH/PUT /pub/renegotiations/:id` atualiza o acordo e recalcula todos os agregados.
Fonte legada: `app/controllers/pub/renegotiations_controller.rb:95-106`, `:190-192`.

#### Scenario: Edição recalcula os agregados
- **GIVEN** uma renegociação com parcelas lançadas
- **WHEN** o valor da dívida é alterado
- **THEN** os agregados e o estado são recalculados e persistidos

#### Scenario: Edição de renegociação de outro projeto
- **GIVEN** uma renegociação de outro projeto
- **WHEN** a edição é submetida por id
- **THEN** a requisição é recusada por autorização
> Nota: corrige o vazamento de escopo da mesma família de D-16/D-76/D-100 (comportamento legado: sem escopo, qualquer usuário logado editava qualquer renegociação por id)

#### Scenario: Edição inválida não altera os agregados
- **GIVEN** uma edição que falha na validação
- **WHEN** ela é submetida
- **THEN** nada é alterado e a resposta é 422
> Nota: corrige comportamento legado (o recálculo rodava mesmo após a falha e mutava os agregados em memória)

### Requirement: BE-201 — Excluir renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
`DELETE /pub/renegotiations/:id` remove o acordo apenas quando não há parcelas nem
pagamentos vinculados. Fonte legada:
`app/controllers/pub/renegotiations_controller.rb:109-118`; `app/models/renegotiation.rb:6-8`.

#### Scenario: Exclusão de renegociação sem parcelas
- **GIVEN** uma renegociação sem parcelas e com 2 anexos
- **WHEN** a exclusão é confirmada
- **THEN** a renegociação e os 2 anexos são removidos

#### Scenario: Exclusão barrada por parcela existente
- **GIVEN** uma renegociação com parcelas
- **WHEN** a exclusão é tentada
- **THEN** a resposta é um erro explicando o vínculo, e a renegociação permanece
> Nota: corrige D-24 (comportamento legado: `@renegotiation.errors.any? ? :ok : :ok` respondia 200 nos dois casos e o template de retorno era um arquivo vazio, então a tela mostrava sucesso e o registro reaparecia na lista)

### Requirement: BE-202 — Exclusão de parcelas em lote
O sistema SHALL se comportar conforme os cenários desta seção.
A exclusão em lote remove as parcelas selecionadas, recalcula os agregados e renumera as
restantes, em uma transação. Fonte legada:
`app/controllers/pub/renegotiations_controller.rb:120-129`; `app/models/renegotiation.rb:61-70`.

#### Scenario: Exclusão de um lote válido
- **GIVEN** uma renegociação com 12 parcelas sem pagamento e 4 delas selecionadas
- **WHEN** a exclusão em lote é executada
- **THEN** as 4 parcelas são removidas, as 8 restantes são renumeradas de 1 a 8 por vencimento e os agregados são recalculados

#### Scenario: Lote com parcela que tem pagamento
- **GIVEN** um lote em que uma das parcelas tem pagamento vinculado
- **WHEN** a exclusão em lote é executada
- **THEN** nenhuma parcela é removida, os agregados permanecem intactos e a resposta explica qual parcela impediu a operação
> Nota: corrige D-51 (comportamento legado: as demais parcelas já haviam sido apagadas e a renumeração já havia rodado quando o 422 era devolvido — remoção parcial reportada como falha total)

#### Scenario: Lote vazio
- **GIVEN** uma chamada sem nenhum identificador de parcela
- **WHEN** ela é executada
- **THEN** a resposta indica que nada foi selecionado, em vez de sucesso
> Nota: corrige comportamento legado (lista vazia produzia `nil.blank? == true` e retornava sucesso sem remover nada)

#### Scenario: Identificadores de outra renegociação
- **GIVEN** um lote contendo o identificador de uma parcela de outra renegociação
- **WHEN** ele é executado
- **THEN** a operação é recusada por identificador inválido
> Nota: corrige comportamento legado (identificadores estranhos eram ignorados em silêncio, produzindo sucesso parcial invisível)

### Requirement: BE-203 — Renumeração das parcelas
O sistema SHALL se comportar conforme os cenários desta seção.
Após qualquer alteração no conjunto de parcelas, elas são renumeradas de 1 a N por data
de vencimento. Fonte legada: `app/models/renegotiation.rb:73-81`.

#### Scenario: Renumeração após inserir parcela no meio
- **GIVEN** parcelas com vencimentos em jan, fev e abr, numeradas 1, 2 e 3
- **WHEN** uma parcela com vencimento em mar é criada
- **THEN** as parcelas passam a ser numeradas 1 (jan), 2 (fev), 3 (mar) e 4 (abr)

#### Scenario: Renumeração após excluir parcela
- **GIVEN** 5 parcelas numeradas de 1 a 5
- **WHEN** a segunda é excluída
- **THEN** as restantes passam a ser numeradas de 1 a 4, na ordem de vencimento

### Requirement: BE-204 — Agregados de principal, juros e correção monetária
O sistema SHALL se comportar conforme os cenários desta seção.
Os totais lançados da renegociação são somas das parcelas, e o valor total do acordo é
derivado delas. Fonte legada: `app/models/renegotiation.rb:95-101`.

#### Scenario: Soma das parcelas
- **GIVEN** 3 parcelas com principal 1.000, juros 100 e correção 50 cada
- **WHEN** os agregados são recalculados
- **THEN** `installments_main_value = 3.000,00`, `installments_interest_value = 300,00`, `installments_main_value_with_interest = 3.300,00`, `installments_monetary_correction_value = 150,00`, `installments_main_value_with_interest_cm = 3.450,00` e `main_value = 3.450,00`

#### Scenario: Renegociação sem parcelas
- **GIVEN** uma renegociação sem nenhuma parcela
- **WHEN** os agregados são recalculados
- **THEN** todos os agregados de parcelas ficam em `0,00`, inclusive `main_value`

### Requirement: BE-205 — Agregados de valor pago, mora e pendente
O sistema SHALL se comportar conforme os cenários desta seção.
Os valores pagos e a mora são somados a partir dos pagamentos, e o pendente é a diferença
contra o valor total. Fonte legada: `app/models/renegotiation.rb:102-106`.

#### Scenario: Soma dos pagamentos
- **GIVEN** `main_value = 3.450,00` e pagamentos somando 1.000,00 de principal com juros e correção, mais 80,00 de mora
- **WHEN** os agregados são recalculados
- **THEN** `paid_value_with_interest_cm = 1.000,00`, `late_payment_value = 80,00`, `pending_main_value = 2.450,00` e `paid_value = 1.080,00`

#### Scenario: Pagamento a maior deixa o pendente negativo
- **GIVEN** `main_value = 1.000,00` e pagamentos somando 1.200,00
- **WHEN** os agregados são recalculados
- **THEN** `pending_main_value = −200,00`, enquanto `remaining_value` permanece em `0,00`
> Nota: DEC-02 — a assimetria do legado entre `pending_main_value` (que pode ficar negativo) e `remaining_value` (que tem piso em zero) é preservada
> AMBIGUIDADE: os dois campos medem "o que falta pagar" com regras diferentes; confirmar qual é o número que o negócio considera correto

### Requirement: BE-206 — Percentual pago
O sistema SHALL se comportar conforme os cenários desta seção.
`paid_percent` é a razão entre o pago com juros e correção e o valor total lançado.
Fonte legada: `app/models/renegotiation.rb:103`.

#### Scenario: Percentual pago
- **GIVEN** `paid_value_with_interest_cm = 1.000,00` e `main_value = 4.000,00`
- **WHEN** o agregado é recalculado
- **THEN** `paid_percent = 25,0`

#### Scenario: Valor total zerado
- **GIVEN** `main_value = 0`
- **WHEN** o agregado é recalculado
- **THEN** `paid_percent = 0`, sem divisão por zero

#### Scenario: Percentual acima de 100
- **GIVEN** `paid_value_with_interest_cm = 1.200,00` e `main_value = 1.000,00`
- **WHEN** o agregado é recalculado
- **THEN** `paid_percent = 120,0`, aceito como no legado
> Nota: DEC-02 — resultado do legado preservado; a mora não entra no numerador e a dívida contratada não entra no denominador

### Requirement: BE-207 — Valor remanescente e contadores de parcelas
O sistema SHALL se comportar conforme os cenários desta seção.
O remanescente soma o pendente de cada parcela, e os contadores classificam as parcelas
em pagas, vencidas e a vencer. Fonte legada: `app/models/renegotiation.rb:107-110`.

#### Scenario: Contadores das parcelas
- **GIVEN** 10 parcelas, 3 pagas, 2 vencidas não pagas e 5 futuras
- **WHEN** os agregados são recalculados
- **THEN** `paid_installments = 3`, `overdue_installments = 2` e `due_installments = 7`
> AMBIGUIDADE: `due_installments` é `installments_count − paid_installments`, então a coluna "A vencer" inclui as vencidas não pagas; confirmar se essa é a semântica desejada

#### Scenario: Excedente de uma parcela não abate outra
- **GIVEN** uma parcela paga a maior e outra ainda pendente
- **WHEN** o remanescente é recalculado
- **THEN** `remaining_value` é o pendente da segunda parcela, sem desconto do excedente da primeira

#### Scenario: Contagem de vencidas sempre atual
- **GIVEN** uma parcela cujo vencimento passou desde a última gravação
- **WHEN** a renegociação é consultada
- **THEN** ela já aparece como vencida, sem depender de uma varredura noturna
> Nota: corrige D-54 (comportamento legado: `overdue_installments` era uma fotografia do último `update_values!`, atualizada só pelo cron diário)

### Requirement: BE-208 — Valor corrigido, deságio, datas e contagem de parcelas
O sistema SHALL se comportar conforme os cenários desta seção.
O sistema deriva a contagem real de parcelas, o primeiro e o último vencimento, o valor
corrigido e o valor após deságio. Fonte legada: `app/models/renegotiation.rb:91-93`, `:113`.

#### Scenario: Datas e contagem
- **GIVEN** parcelas com vencimentos entre 10/04/2026 e 10/03/2027
- **WHEN** os agregados são recalculados
- **THEN** `installments_count` é a contagem real de parcelas, `first_due_date = 10/04/2026` e `last_due_date = 10/03/2027`

#### Scenario: Valor após deságio
- **GIVEN** `original_value = 100.000,00` e `desagio_value = 20.000,00`
- **WHEN** os agregados são recalculados
- **THEN** `total_value_with_desagio = 80.000,00`

#### Scenario: Deságio maior que o valor original
- **GIVEN** `original_value = 10.000,00` e `desagio_value = 15.000,00`
- **WHEN** os agregados são recalculados
- **THEN** `total_value_with_desagio = −5.000,00`, sem validação
> AMBIGUIDADE: o legado não valida `desagio_value <= original_value`; confirmar se o ai9 deve rejeitar

#### Scenario: Valor corrigido sem correção monetária real
- **GIVEN** `total_debt = 120.000,00`, `interest_rate_correction = 1,5` e `grace_period = 3`
- **WHEN** os agregados são recalculados
- **THEN** `correct_value = 120.000,00` — a taxa de correção e a carência não são aplicadas
> AMBIGUIDADE: D-47 — a tela promete correção monetária e carência, mas `interest_rate_correction` e `grace_period` nunca são lidos; confirmar se devem ser implementados de fato ou removidos da UI

### Requirement: BE-209 — Estado da renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
O estado é derivado das parcelas e do saldo remanescente, com quatro valores possíveis.
Fonte legada: `app/models/renegotiation.rb:115-124`, `:129-135`.

#### Scenario: Renegociação sem parcelas
- **GIVEN** uma renegociação sem nenhuma parcela
- **WHEN** o estado é recalculado
- **THEN** `state = "Sem parcela cadastrada"`

#### Scenario: Renegociação quitada
- **GIVEN** parcelas cujo remanescente é zero
- **WHEN** o estado é recalculado
- **THEN** `state = "Liquidado"`

#### Scenario: Renegociação inconsistente permanece inconsistente
- **GIVEN** uma renegociação cujo total lançado em parcelas é menor que o valor corrigido
- **WHEN** o estado é recalculado
- **THEN** `state = "Inconsistente"`, e o filtro "Inconsistente" da lista a encontra
> Nota: corrige D-45 (comportamento legado: a linha que calculava o estado inconsistente era sobrescrita incondicionalmente pela linha seguinte, então o estado só existia no instante da criação e o filtro da tela nunca retornava nada)

#### Scenario: Estado apresentado com percentual
- **GIVEN** uma renegociação parcialmente paga, com 25% pago
- **WHEN** o estado apresentado é montado
- **THEN** ele mostra "25% Pago"

### Requirement: BE-210 — Valor a lançar e consistência do lançamento
O sistema SHALL se comportar conforme os cenários desta seção.
`unposted_value` e `installment_status` comparam o que foi lançado em parcelas com a
dívida contratada. Fonte legada: `app/models/renegotiation.rb:140-142`, `:145-155`.

#### Scenario: Lançamento consistente
- **GIVEN** `total_debt = 3.300,00` e `installments_main_value_with_interest = 3.300,00`
- **WHEN** os derivados são calculados
- **THEN** `unposted_value = 0,00` e `installment_status = "Consistente"`

#### Scenario: Lançamento a maior
- **GIVEN** `total_debt = 3.000,00` e `installments_main_value_with_interest = 3.300,00`
- **WHEN** os derivados são calculados
- **THEN** `unposted_value = −300,00` e `installment_status = "Inconsistente"`

#### Scenario: Renegociação sem parcelas e sem dívida
- **GIVEN** `total_debt = 0,00` e nenhuma parcela
- **WHEN** os derivados são calculados
- **THEN** `installment_status = "Consistente"`

### Requirement: BE-211 — Parcela do mês corrente e próxima parcela
O sistema SHALL se comportar conforme os cenários desta seção.
A lista mostra o valor das parcelas do mês corrente e o valor e a data da próxima parcela
em aberto. Fonte legada: `app/models/renegotiation.rb:157-173`.

#### Scenario: Parcela do mês corrente
- **GIVEN** duas parcelas vencendo no mês corrente, uma paga e outra não, de 1.000,00 cada
- **WHEN** o valor do mês é calculado
- **THEN** ele soma as duas, resultando em 2.000,00, incluindo a já paga

#### Scenario: Próxima parcela
- **GIVEN** uma parcela vencida não paga e outra futura não paga
- **WHEN** a próxima parcela é calculada
- **THEN** a parcela futura é a escolhida — parcelas vencidas nunca aparecem como próxima

#### Scenario: Sem parcela futura em aberto
- **GIVEN** todas as parcelas pagas
- **WHEN** a próxima parcela é calculada
- **THEN** o valor é `0,00` e a data fica vazia, apresentada como `-`

#### Scenario: Cálculo da lista não multiplica consultas
- **GIVEN** uma página com 20 renegociações
- **WHEN** a lista é montada
- **THEN** os valores de parcela do mês e próxima parcela são obtidos sem uma consulta por linha
> Nota: corrige comportamento legado (os dois valores eram calculados a cada render, gerando N+2 consultas por linha da listagem)

### Requirement: BE-212 — Valor presente da dívida
O sistema SHALL se comportar conforme os cenários desta seção.
`current_value` traz a dívida remanescente a valor presente pela taxa acordada. Fonte
legada: `app/models/renegotiation.rb:175-183`.

#### Scenario: Valor presente com juros
- **GIVEN** `remaining_value = 12.000,00`, `operation_interest_rate = 1`, parcela do mês de 1.000,00 e 12 parcelas a vencer
- **WHEN** o valor presente é calculado
- **THEN** `current_value = 11.255,08`
> Nota: DEC-02 — a aritmética em ponto flutuante e o arredondamento final do legado são replicados

#### Scenario: Sem saldo remanescente
- **GIVEN** `remaining_value = 0`
- **WHEN** o valor presente é calculado
- **THEN** `current_value = 0`

#### Scenario: Taxa acordada zero
- **GIVEN** `operation_interest_rate = 0` e `remaining_value = 12.000,00`
- **WHEN** o valor presente é calculado
- **THEN** `current_value = 12.000,00`

#### Scenario: Valor da parcela sobrescrito pelo valor presente
- **GIVEN** uma renegociação com juros maiores que zero e saldo em aberto
- **WHEN** os agregados são recalculados
- **THEN** a coluna "Valor Parcela" (`current_installment_value`) passa a conter o valor presente, ficando igual a `current_value`, exatamente como no legado
> Nota: DEC-02 — o resultado do legado é travado para bater os totais
> AMBIGUIDADE: D-46 — a reatribuição de `current_installment_value` dentro do cálculo do valor presente parece bug e muda um número exibido ao cliente; precisa de reconciliação antes de mudar

### Requirement: BE-213 — Listar parcelas e abrir o formulário de parcela
O sistema SHALL se comportar conforme os cenários desta seção.
A busca de parcelas devolve as parcelas da renegociação ordenadas por vencimento, e as
ações de criação e edição montam o formulário lateral. Fonte legada:
`app/controllers/pub/renegotiation_installments_controller.rb:14-21`, `:23-32`, `:78-84`.

#### Scenario: Parcelas ordenadas por vencimento
- **GIVEN** uma renegociação com 12 parcelas
- **WHEN** a busca é executada
- **THEN** as parcelas vêm ordenadas por data de vencimento crescente, com os pagamentos de cada uma

#### Scenario: Paginação das parcelas
- **GIVEN** uma renegociação com 60 parcelas e uma busca com limite 20
- **WHEN** ela é executada
- **THEN** vêm 20 parcelas e o total informado é 60
> Nota: corrige D-20 (comportamento legado: `l`/`o` eram calculados e ignorados — a busca sempre devolvia todas as parcelas)

#### Scenario: Renegociação inexistente
- **GIVEN** um `renegotiation_id` inválido ao abrir o formulário de nova parcela
- **WHEN** a requisição é processada
- **THEN** a resposta é 404, e não um erro interno
> Nota: corrige comportamento legado (`@renegotiation` nulo levava a `NoMethodError`)

### Requirement: BE-214 — Criar parcelas
O sistema SHALL se comportar conforme os cenários desta seção.
`POST /pub/renegotiation_installments` cria uma parcela única ou um lote de parcelas
conforme o modo escolhido. Fonte legada:
`app/controllers/pub/renegotiation_installments_controller.rb:34-74`.

#### Scenario: Modo de criação
- **GIVEN** um payload com o indicador de múltiplas parcelas ligado, repetições, intervalo e período
- **WHEN** a criação é submetida
- **THEN** o lote é gerado conforme as regras de BE-216

#### Scenario: Data ausente
- **GIVEN** um payload sem a data da parcela
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 com erro de validação, e não um erro interno
> Nota: corrige comportamento legado (a ausência do bloco de data levantava `NoMethodError` e devolvia 500)

#### Scenario: Repetições não numéricas
- **GIVEN** um payload cujo número de repetições não é numérico
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 explicando o campo inválido
> Nota: corrige comportamento legado (`to_i` transformava o valor em 0, nenhuma parcela era criada e a resposta era 200 com "criada com sucesso")

### Requirement: BE-215 — Criação de parcela única
O sistema SHALL se comportar conforme os cenários desta seção.
No modo de parcela única, uma parcela é criada na data informada, desde que não haja
outra parcela na mesma data. Fonte legada:
`app/models/renegotiation_installment.rb:117-180`, `:254-261`.

#### Scenario: Criação de uma parcela
- **GIVEN** uma renegociação com parcelas em 10/04 e 10/05
- **WHEN** uma parcela é criada para 10/06
- **THEN** a parcela é criada, as parcelas são renumeradas por vencimento e os agregados da renegociação são recalculados

#### Scenario: Data já ocupada
- **GIVEN** uma renegociação com parcela em 10/05
- **WHEN** outra parcela é criada para 10/05
- **THEN** nada é criado e a resposta explica "Parcelas sobrepostas à parcelas já existentes"

#### Scenario: Falha de criação não dispara recálculo
- **GIVEN** uma criação recusada por validação
- **WHEN** ela é processada
- **THEN** os agregados e a numeração da renegociação permanecem inalterados
> Nota: corrige comportamento legado (o recálculo e a renumeração rodavam sempre ao final, inclusive quando nada havia sido criado)

### Requirement: BE-216 — Criação de parcelas em lote
O sistema SHALL se comportar conforme os cenários desta seção.
No modo de múltiplas parcelas, N parcelas são geradas a partir da data inicial, com
intervalo em dias, semanas ou meses. Fonte legada:
`app/models/renegotiation_installment.rb:182-252`.

#### Scenario: Geração mensal
- **GIVEN** data inicial 10/04/2026, 3 repetições, intervalo 1 e período "Meses"
- **WHEN** o lote é criado
- **THEN** são criadas parcelas em 10/04/2026, 10/05/2026 e 10/06/2026 — a primeira é na própria data inicial

#### Scenario: Fim de mês
- **GIVEN** data inicial 31/01/2026, 2 repetições, intervalo 1 e período "Meses"
- **WHEN** o lote é criado
- **THEN** a segunda parcela vence em 28/02/2026, ajustada ao último dia do mês

#### Scenario: Colisão com parcelas existentes
- **GIVEN** um lote cujas datas geradas intersectam vencimentos já existentes
- **WHEN** ele é criado
- **THEN** nenhuma parcela é criada e a resposta explica a sobreposição

#### Scenario: Intervalo zero gera datas repetidas
- **GIVEN** intervalo 0 e 5 repetições
- **WHEN** o lote é submetido
- **THEN** a resposta é 422 explicando que o intervalo precisa ser maior que zero
> Nota: corrige comportamento legado (duplicatas dentro do próprio lote não eram checadas: a primeira parcela era criada, as demais falhavam na unicidade em silêncio e a resposta era sucesso)

#### Scenario: Período desconhecido
- **GIVEN** um período fora de "Dias", "Semanas" e "Meses"
- **WHEN** o lote é submetido
- **THEN** a resposta é 422, e não um erro interno

### Requirement: BE-217 — Derivações da parcela, identidade do lote e reporte de erros
O sistema SHALL se comportar conforme os cenários desta seção.
Cada parcela criada deriva seus totais dos valores informados e recebe a identidade
visual do lote. Fonte legada: `app/models/renegotiation_installment.rb:96-114`, `:148-180`.

#### Scenario: Derivação dos valores da parcela
- **GIVEN** principal 1.000,00, juros 100,00 e correção 50,00
- **WHEN** a parcela é criada
- **THEN** `main_value_with_interest = 1.100,00`, `main_value_with_interest_cm = 1.150,00`, `late_payment_value = 0,00`, `installment_total_value = 1.150,00`, `paid_value = 0,00`, `saldo = −1.150,00`, `pending_value = 1.150,00` e `is_paid = 0`

#### Scenario: Identidade do lote
- **GIVEN** um lote de 6 parcelas criado de uma vez
- **WHEN** ele é persistido
- **THEN** as 6 parcelas compartilham o mesmo identificador de lote e a mesma cor, distinta das cores dos demais lotes da mesma renegociação

#### Scenario: Parcela inválida é reportada
- **GIVEN** um lote em que uma parcela tem principal zero
- **WHEN** ele é submetido
- **THEN** a resposta é 422 explicando qual parcela falhou
> Nota: corrige D-52 e o silêncio de criação do legado (o retorno do `create` era ignorado: parcela zerada ou com data duplicada falhava em silêncio e a API respondia 200 com "A previsão foi criada com sucesso")

### Requirement: BE-218 — Validações e derivações do modelo de parcela
O sistema SHALL se comportar conforme os cenários desta seção.
A parcela exige principal maior que zero e uma única parcela por data em cada
renegociação. Fonte legada: `app/models/renegotiation_installment.rb:5-15`, `:17-35`.

#### Scenario: Principal maior que zero
- **GIVEN** uma parcela com principal 0
- **WHEN** ela é submetida
- **THEN** a resposta é 422

#### Scenario: Unicidade da data de vencimento
- **GIVEN** duas requisições simultâneas criando parcelas para a mesma data na mesma renegociação
- **WHEN** ambas são processadas
- **THEN** apenas uma é criada e a outra recebe erro de unicidade
> Nota: corrige D-12 (comportamento legado: a unicidade era só do ActiveRecord, sem índice único no banco, sujeita a corrida)

#### Scenario: Mudança de data redefine mês e ano
- **GIVEN** uma parcela com vencimento em 10/05/2026
- **WHEN** o vencimento é alterado para 10/06/2026
- **THEN** os campos derivados de mês e ano acompanham a nova data

### Requirement: BE-219 — Recálculo da parcela a partir dos pagamentos
O sistema SHALL se comportar conforme os cenários desta seção.
A parcela recalcula mora, total, pago, saldo e situação de quitação a partir dos seus
pagamentos. Fonte legada: `app/models/renegotiation_installment.rb:59-69`.

#### Scenario: Quitação parcial
- **GIVEN** uma parcela de 1.150,00 e um pagamento de 500,00 sem mora
- **WHEN** os valores são recalculados
- **THEN** `paid_value = 500,00`, `installment_total_value = 1.150,00`, `pending_value = 650,00` e `is_paid = 0`

#### Scenario: Mora aumenta o total devido e o valor pago
- **GIVEN** uma parcela de 1.150,00 e um pagamento de 1.150,00 com 80,00 de mora
- **WHEN** os valores são recalculados
- **THEN** `late_payment_value = 80,00`, `installment_total_value = 1.230,00`, `paid_value = 1.230,00`, `pending_value = 0,00` e `is_paid = 1`
> Nota: DEC-02 — a fórmula do legado, em que a mora entra dos dois lados da conta, é preservada
> AMBIGUIDADE: pagar apenas a mora pode quitar a parcela, porque a mora soma ao devido e ao pago; validar a regra com o negócio

#### Scenario: Pagamento a maior não vira crédito
- **GIVEN** uma parcela de 1.000,00 e um pagamento de 1.200,00
- **WHEN** os valores são recalculados
- **THEN** `pending_value = 0,00`, `saldo = 200,00` e o excedente não abate nenhuma outra parcela

### Requirement: BE-220 — Cascata de recálculo da parcela para a renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
Qualquer alteração de pagamento renumera os pagamentos da parcela, recalcula a parcela e
propaga para os agregados da renegociação. Fonte legada:
`app/models/renegotiation_installment.rb:71-76`, `:82-90`.

#### Scenario: Cascata completa
- **GIVEN** uma parcela com 2 pagamentos
- **WHEN** um terceiro pagamento é registrado
- **THEN** os pagamentos são renumerados de 1 a 3 por ordem de criação, a parcela é recalculada e os agregados da renegociação refletem o novo pagamento

#### Scenario: Falha de gravação da parcela é reportada
- **GIVEN** um recálculo que deixaria a parcela inválida
- **WHEN** ele é executado
- **THEN** a operação é revertida e o erro é reportado
> Nota: corrige comportamento legado (o `save` sem bang descartava o recálculo em silêncio, deixando parcela e renegociação divergentes)

### Requirement: BE-221 — Editar e excluir parcela
O sistema SHALL se comportar conforme os cenários desta seção.
A parcela pode ser editada com recálculo e renumeração, e só pode ser excluída quando não
tem pagamento. Fonte legada:
`app/controllers/pub/renegotiation_installments_controller.rb:86-108`, `:144-158`;
`app/models/renegotiation_installment.rb:37-40`.

#### Scenario: Edição de valores
- **GIVEN** uma parcela de 1.150,00 sem pagamento
- **WHEN** o principal é alterado para 2.000,00
- **THEN** os derivados da parcela e os agregados da renegociação são recalculados

#### Scenario: Edição do vencimento renumera o conjunto
- **GIVEN** a segunda de 5 parcelas
- **WHEN** seu vencimento passa a ser posterior ao da quinta
- **THEN** ela passa a ser a parcela número 5 e as demais são renumeradas

#### Scenario: Exclusão barrada por pagamento
- **GIVEN** uma parcela com pagamento vinculado
- **WHEN** a exclusão é tentada
- **THEN** ela é recusada com a razão do bloqueio

#### Scenario: Aumento de valor reabre parcela quitada
- **GIVEN** uma parcela quitada de 1.000,00
- **WHEN** o principal é alterado para 2.000,00
- **THEN** `pending_value` volta a ser positivo e `is_paid` volta a 0

### Requirement: BE-222 — Listar pagamentos e abrir o formulário de pagamento
O sistema SHALL se comportar conforme os cenários desta seção.
A busca de pagamentos devolve os pagamentos da renegociação, e as ações de criação e
edição montam o formulário lateral. Fonte legada:
`app/controllers/pub/renegotiation_payments_controller.rb:14-20`, `:22-32`, `:45-54`.

#### Scenario: Pagamentos com ordem determinística
- **GIVEN** uma renegociação com 8 pagamentos
- **WHEN** a busca é executada
- **THEN** os pagamentos vêm em ordem determinística, paginados conforme o limite pedido
> Nota: corrige D-20 (comportamento legado: sem `ORDER BY` e sem paginação — a ordem dependia do banco e `l`/`o` eram ignorados)

#### Scenario: Pré-seleção da parcela
- **GIVEN** a criação de pagamento aberta a partir de uma parcela
- **WHEN** o formulário é montado
- **THEN** a parcela vem pré-selecionada; sem essa origem, todas as parcelas são oferecidas com número, vencimento e valor pendente

#### Scenario: Edição não muda a parcela pela URL
- **GIVEN** um pagamento vinculado à parcela `I1`
- **WHEN** a edição é aberta informando outra parcela na URL
- **THEN** o pagamento continua vinculado a `I1`
> Nota: corrige comportamento legado (a action de edição reatribuía a parcela a partir do parâmetro, movendo o pagamento de parcela sem intenção do usuário)

### Requirement: BE-223 — Registrar pagamento
O sistema SHALL se comportar conforme os cenários desta seção.
`POST /pub/renegotiation_payments` registra o pagamento de uma parcela, com mora e dias
de atraso derivados. Fonte legada:
`app/controllers/pub/renegotiation_payments_controller.rb:34-43`; `app/models/renegotiation_payment.rb:1-22`.

#### Scenario: Pagamento com atraso
- **GIVEN** uma parcela com vencimento em 10/05/2026 e um pagamento de 1.150,00 com 80,00 de mora em 20/05/2026
- **WHEN** o pagamento é registrado
- **THEN** `days_late = 10`, `total_paid_value = 1.230,00` e a parcela e a renegociação são recalculadas

#### Scenario: Pagamento em dia
- **GIVEN** um pagamento na data de vencimento
- **WHEN** ele é registrado
- **THEN** `days_late = 0`

#### Scenario: Pagamento maior que a parcela é recusado
- **GIVEN** uma parcela com pendente de 500,00
- **WHEN** um pagamento de 800,00 é registrado
- **THEN** a resposta é 422 explicando que o valor excede o pendente da parcela
> Nota: corrige D-52 (comportamento legado: não havia teto — o excedente deixava `paid_percent` acima de 100% e `pending_main_value` negativo)

#### Scenario: Mora negativa é recusada
- **GIVEN** um pagamento com mora de −50,00
- **WHEN** ele é registrado
- **THEN** a resposta é 422
> Nota: corrige D-52 (comportamento legado: a mora negativa era aceita e reduzia o total pago)

#### Scenario: Renegociação divergente da parcela
- **GIVEN** um pagamento cuja renegociação informada não é a da parcela escolhida
- **WHEN** ele é registrado
- **THEN** a resposta é 422
> Nota: corrige D-52 (comportamento legado: o vínculo não era validado e o pagamento poluía os agregados das duas renegociações)

#### Scenario: Data ou parcela ausente
- **GIVEN** um pagamento sem data, ou com parcela inexistente
- **WHEN** ele é submetido
- **THEN** a resposta é 422 com erro de validação, e não um erro interno
> Nota: corrige comportamento legado (o callback rodava antes da validação e levantava `NoMethodError`, devolvendo 500)

#### Scenario: Não existe imputação automática
- **GIVEN** várias parcelas em aberto
- **WHEN** um pagamento é registrado
- **THEN** ele é aplicado exclusivamente à parcela escolhida pelo usuário, sem quitação da mais antiga, rateio ou transbordo para a parcela seguinte

### Requirement: BE-224 — Editar e excluir pagamento
O sistema SHALL se comportar conforme os cenários desta seção.
A alteração e a remoção de um pagamento propagam o recálculo para a parcela e a
renegociação. Fonte legada:
`app/controllers/pub/renegotiation_payments_controller.rb:57-78`, `:101-103`.

#### Scenario: Edição recalcula uma única vez
- **GIVEN** um pagamento existente
- **WHEN** seu valor é alterado
- **THEN** a parcela e a renegociação são recalculadas exatamente uma vez
> Nota: corrige comportamento legado (o `update` era seguido de um `save` redundante, disparando a cascata de recálculo em duplicidade)

#### Scenario: Exclusão reabre a parcela
- **GIVEN** uma parcela quitada por um único pagamento
- **WHEN** o pagamento é excluído
- **THEN** a parcela volta a `is_paid = 0` com `pending_value` positivo, os pagamentos restantes são renumerados e os agregados são recalculados

#### Scenario: Pagamento de outro projeto
- **GIVEN** um pagamento de uma renegociação de outro projeto
- **WHEN** a exclusão é tentada por id
- **THEN** a requisição é recusada por autorização
> Nota: corrige o vazamento de escopo da mesma família de D-16/D-76/D-100

### Requirement: BE-225 — Listar anexos da renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
A busca de anexos devolve os arquivos da renegociação, com filtro e paginação. Fonte
legada: `app/controllers/pub/renegotiation_attachments_controller.rb:6-16`;
`config/routes.rb:117`.

#### Scenario: Listagem de anexos
- **GIVEN** uma renegociação com 3 anexos
- **WHEN** a busca é executada
- **THEN** os 3 anexos são retornados com título, formato e autor
> Nota: corrige comportamento legado (a rota nunca funcionou: a view passava o local `la:` enquanto o parcial usava `ra`, levantando `NameError` em runtime)

#### Scenario: Filtro e limite aplicados
- **GIVEN** uma renegociação com 10 anexos e uma busca com termo e limite 5
- **WHEN** ela é executada
- **THEN** vêm no máximo 5 anexos que casam com o termo
> Nota: corrige D-20 (comportamento legado: limite, deslocamento e termo eram calculados e nunca aplicados)

### Requirement: BE-226 — Enviar anexos da renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
`POST /pub/renegotiation_attachments` recebe um ou mais arquivos e os vincula à
renegociação, respeitando limites de quantidade, tamanho e tipo. Fonte legada:
`app/controllers/pub/renegotiation_attachments_controller.rb:29-48`;
`app/models/renegotiation_attachment.rb:2-13`.

#### Scenario: Envio de arquivos válidos
- **GIVEN** uma renegociação sem anexos
- **WHEN** 2 arquivos PDF de 1 MB são enviados
- **THEN** os 2 anexos são criados com o autor da sessão, título igual ao nome do arquivo sem extensão, e o contador de anexos passa a 2

#### Scenario: Limite de quantidade aplicado no servidor
- **GIVEN** uma renegociação que já tem 4 anexos
- **WHEN** um quinto arquivo é enviado
- **THEN** o envio é recusado com a razão do limite
> Nota: corrige D-50 (comportamento legado: o limite de 4 arquivos existia só no JavaScript e estava quebrado por seletor errado; o servidor não tinha limite algum)

#### Scenario: Limite de tamanho aplicado no servidor
- **GIVEN** um arquivo de 8 MB
- **WHEN** ele é enviado
- **THEN** o envio é recusado com a razão do limite de 5 MB
> Nota: corrige D-50 (comportamento legado: o limite de tamanho existia só no cliente)

#### Scenario: Tipo de arquivo validado pelo conteúdo
- **GIVEN** um arquivo executável renomeado para `.pdf`
- **WHEN** ele é enviado
- **THEN** o envio é recusado por tipo não permitido
> Nota: corrige D-82 (comportamento legado: `do_not_validate_attachment_file_type` mais o detector de spoof desligado globalmente aceitavam qualquer conteúdo com qualquer extensão)

#### Scenario: Envio sem arquivos
- **GIVEN** uma requisição sem nenhum arquivo
- **WHEN** ela é submetida
- **THEN** a resposta é 422 explicando a ausência, e não um erro interno

### Requirement: BE-227 — Baixar e visualizar anexo
O sistema SHALL se comportar conforme os cenários desta seção.
O download do anexo é autorizado e serve o arquivo de forma segura. Fonte legada:
`app/controllers/pub/renegotiation_attachments_controller.rb:18-27`; `config/routes.rb:110-112`.

#### Scenario: Download autorizado
- **GIVEN** um anexo de uma renegociação do projeto do usuário
- **WHEN** ele solicita o download
- **THEN** o arquivo é entregue com o nome original

#### Scenario: Anexo de outro projeto
- **GIVEN** um anexo de uma renegociação de outro projeto
- **WHEN** o usuário solicita o download por id
- **THEN** a requisição é recusada por autorização
> Nota: corrige D-82 (comportamento legado: nenhuma verificação de permissão — qualquer usuário autenticado baixava qualquer anexo por id)

#### Scenario: Conteúdo não é renderizado na origem da aplicação
- **GIVEN** um anexo HTML ou SVG
- **WHEN** ele é acessado
- **THEN** ele é entregue como download, sem ser renderizado no contexto da aplicação
> Nota: corrige D-82 (comportamento legado: `disposition: 'inline'` com content-type controlado pelo uploader permitia XSS armazenado na mesma origem)

#### Scenario: Arquivo ausente no armazenamento
- **GIVEN** um registro de anexo cujo arquivo não existe mais
- **WHEN** o download é solicitado
- **THEN** a resposta é 404 com mensagem legível, e não um erro interno

### Requirement: BE-228 — Renomear anexo
O sistema SHALL se comportar conforme os cenários desta seção.
A action de renomear anexo do legado é inexecutável e não corresponde a nenhuma tela.
Fonte legada: `app/controllers/pub/renegotiation_attachments_controller.rb:50-60`.

#### Scenario: Rota inexecutável não é portada
- **GIVEN** a action legada de renomear anexo
- **WHEN** o escopo do ai9 é definido
- **THEN** ela não é portada, e nenhuma tela do legado a exercita
> Nota: DEC-11 — o uso de `update_attributes` funcionaria em produção (Ruby 2.6.1 / Rails 6.0.3.2), mas a action continua morta pelo segundo motivo: ela chama `renegotiation_params`, método inexistente nesse controller, o que levanta `NameError` em qualquer execução
> AMBIGUIDADE: renomear anexo é funcionalidade pretendida e nunca entregue; confirmar se entra no escopo do ai9 ou fica de fora por DEC-09

### Requirement: BE-229 — Excluir anexo
O sistema SHALL se comportar conforme os cenários desta seção.
`DELETE /pub/renegotiation_attachments/:id` remove o anexo e atualiza o contador da
renegociação. Fonte legada:
`app/controllers/pub/renegotiation_attachments_controller.rb:62-71`.

#### Scenario: Exclusão pelo autor
- **GIVEN** um anexo enviado pelo próprio usuário
- **WHEN** ele confirma a exclusão
- **THEN** o anexo e o arquivo são removidos e o contador de anexos é decrementado

#### Scenario: Exclusão por quem não é o autor
- **GIVEN** um anexo enviado por outro usuário
- **WHEN** a exclusão é tentada diretamente na API
- **THEN** a requisição é recusada por autorização
> Nota: corrige D-82 (comportamento legado: a regra de dono era só visual — a view escondia o botão, mas a rota aceitava qualquer id de qualquer usuário)

#### Scenario: Registro cujo arquivo já sumiu
- **GIVEN** um anexo cujo arquivo não existe mais no armazenamento
- **WHEN** a exclusão é executada
- **THEN** o registro é removido normalmente e o contador é atualizado

### Requirement: FE-190 — Tela de lista de renegociações
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Renegociações" lista os acordos do projeto com 13 colunas de resumo. Fonte
legada: `app/views/pub/console/parts/renegotiations/_body.html.erb:1-104`;
`list/_widget.html.erb:1-31`.

#### Scenario: Colunas da lista
- **GIVEN** renegociações cadastradas no projeto corrente
- **WHEN** o usuário abre a área
- **THEN** a tela mostra Nome, Fornecedor, Consistência, Tipo, Estado, Pago, Remanescente, Data próxima, Próxima, Parcelas, Pagas, Vencidas e A vencer

#### Scenario: Data da próxima parcela ausente
- **GIVEN** uma renegociação sem parcela futura em aberto
- **WHEN** a linha é renderizada
- **THEN** a coluna "Data próxima" mostra `-`

### Requirement: FE-191 — Estados do container da lista
O sistema SHALL se comportar conforme os cenários desta seção.
A lista tem estados de carregamento, vazio, vazio com busca e erro. Fonte legada:
`.../renegotiations/_body.js.erb:202-203`, `:187-189`; `list/body.js.erb:15-19`.

#### Scenario: Carregando e vazio
- **GIVEN** a lista sendo carregada
- **WHEN** a busca responde sem resultados e sem termo
- **THEN** a tela passa de "Buscando .." para "Nenhum resultado encontrado"

#### Scenario: Vazio com termo de busca
- **GIVEN** o termo "Alfa" no campo de busca
- **WHEN** nenhuma renegociação casa
- **THEN** a tela mostra "Não encontramos nenhum resultado para a busca **Alfa**.."

#### Scenario: Falha ao carregar
- **GIVEN** a busca retornando erro
- **WHEN** a resposta chega
- **THEN** a tela mostra um estado de erro com opção de tentar novamente
> Nota: corrige comportamento legado (o `failure` do proxy era vazio e a tela ficava no último estado, sem qualquer mensagem)

### Requirement: FE-192 — Busca incremental na lista
O sistema SHALL se comportar conforme os cenários desta seção.
O campo de busca filtra a lista com debounce de 300 ms. Fonte legada:
`.../renegotiations/_body.js.erb:121-134`.

#### Scenario: Debounce e reexecução
- **GIVEN** o usuário digitando no campo "Procurar"
- **WHEN** ele para por 300 ms
- **THEN** uma única busca é disparada com o termo

#### Scenario: Busca pelo nome da renegociação
- **GIVEN** uma renegociação chamada "Acordo 2026"
- **WHEN** o usuário busca por "Acordo"
- **THEN** ela é encontrada
> Nota: corrige comportamento legado (a busca só casava o nome do fornecedor, então digitar o nome da renegociação não encontrava nada — ver BE-190)

### Requirement: FE-193 — Filtros de estado e tipo
O sistema SHALL se comportar conforme os cenários desta seção.
Um botão revela os seletores de estado e tipo, que refazem a busca ao mudar. Fonte
legada: `.../renegotiations/_body.html.erb:33-42`; `_body.js.erb:136-146`.

#### Scenario: Filtros ocultos por padrão
- **GIVEN** a lista recém-aberta
- **WHEN** a tela é exibida
- **THEN** os seletores ficam escondidos até o usuário acionar "Filtros"

#### Scenario: Filtro "Sem parcela cadastrada"
- **GIVEN** o seletor de estado aberto
- **WHEN** o usuário escolhe "Sem parcela cadastrada"
- **THEN** a lista mostra as renegociações sem parcelas
> Nota: corrige D-49 (comportamento legado: essa opção quebrava a requisição com 500)

#### Scenario: Filtro "Inconsistente"
- **GIVEN** renegociações com lançamento inconsistente
- **WHEN** o usuário escolhe "Inconsistente"
- **THEN** elas são listadas
> Nota: corrige D-45 (comportamento legado: o estado inconsistente era sobrescrito no recálculo e o filtro sempre voltava vazio)

### Requirement: FE-194 — Ordenação pelo cabeçalho da lista
O sistema SHALL se comportar conforme os cenários desta seção.
O clique nos cabeçalhos ordenáveis cicla entre ascendente, descendente e neutro,
acumulando colunas. Fonte legada: `.../renegotiations/_body.js.erb:14-116`.

#### Scenario: Ciclo de ordenação
- **GIVEN** a coluna "Nome" neutra
- **WHEN** o usuário clica três vezes
- **THEN** a ordenação passa por ascendente, descendente e volta ao neutro, com o ícone acompanhando

#### Scenario: Ordenação acumulada
- **GIVEN** "Fornecedor" já ordenado ascendente
- **WHEN** o usuário ordena "Nome" descendente
- **THEN** as duas chaves são aplicadas na ordem em que foram escolhidas

### Requirement: FE-195 — Navegação e paginação da lista
O sistema SHALL se comportar conforme os cenários desta seção.
Botões de primeiro, anterior, próximo e último e um campo de tamanho de página navegam a
lista. Fonte legada: `.../renegotiations/_body.js.erb:213-335`, `:386-434`.

#### Scenario: Navegação altera o conteúdo
- **GIVEN** 80 renegociações e página de 20
- **WHEN** o usuário avança uma página
- **THEN** a lista mostra registros diferentes dos da primeira página
> Nota: corrige D-20 (comportamento legado: a paginação não alterava o resultado porque `LIMIT`/`OFFSET` se perdiam no servidor)

#### Scenario: Campo de tamanho de página vazio
- **GIVEN** o campo de tamanho apagado
- **WHEN** o usuário sai do campo
- **THEN** o tamanho volta ao padrão de 50

#### Scenario: Botões desabilitados nos extremos
- **GIVEN** a primeira página
- **WHEN** a lista é exibida
- **THEN** os botões de primeiro e anterior ficam desabilitados

### Requirement: FE-196 — Widget da renegociação e menu de ações
O sistema SHALL se comportar conforme os cenários desta seção.
A linha abre o detalhe e o menu oferece ver mais, editar e remover. Fonte legada:
`list/_widget.html.erb:1-53`; `list/_widget.js.erb:1-98`.

#### Scenario: Abrir o detalhe
- **GIVEN** uma renegociação na lista
- **WHEN** o usuário clica na linha
- **THEN** a navegação vai para o detalhe daquela renegociação

#### Scenario: Remover só sem parcelas
- **GIVEN** uma renegociação com parcelas
- **WHEN** o menu de ações é aberto
- **THEN** a ação de remover não é oferecida

#### Scenario: Título da navegação
- **GIVEN** uma renegociação com nome "Acordo 2026" e fornecedor "Fornecedor Alfa"
- **WHEN** o detalhe é aberto
- **THEN** o título da navegação identifica a renegociação de forma consistente com a coluna "Nome" da lista
> AMBIGUIDADE: o legado usa `provider_name` como título da rota enquanto a lista mostra `title`; confirmar qual identificação deve prevalecer

### Requirement: FE-197 — Botão "Cadastrar" com guarda de fornecedor
O sistema SHALL se comportar conforme os cenários desta seção.
O cadastro só é oferecido a quem pode escrever e exige fornecedor no projeto. Fonte
legada: `.../renegotiations/_body.js.erb:355-372`.

#### Scenario: Projeto sem fornecedor
- **GIVEN** um projeto corrente sem fornecedores
- **WHEN** o usuário aciona "Cadastrar"
- **THEN** a tela mostra "É necessário cadastrar fornecedores no projeto padrão..." e a navegação é bloqueada

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** a lista é exibida
- **THEN** o botão "Cadastrar" não existe

### Requirement: FE-198 — Exclusão de renegociação com confirmação
O sistema SHALL se comportar conforme os cenários desta seção.
A remoção pede confirmação e reflete o resultado real da operação. Fonte legada:
`list/_widget.js.erb:70-96`.

#### Scenario: Confirmação
- **GIVEN** uma renegociação sem parcelas
- **WHEN** o usuário aciona "Remover"
- **THEN** aparece "Excluir renegociação — A operação não pode ser desfeita. Tem certeza?" e nada é excluído até o aceite

#### Scenario: Exclusão barrada mostra erro
- **GIVEN** uma exclusão recusada pelo servidor
- **WHEN** a resposta chega
- **THEN** a tela mostra a razão da recusa e a renegociação continua na lista
> Nota: corrige D-24 (comportamento legado: o servidor respondia 200 mesmo barrando, então o usuário via "sucesso" e o registro reaparecia)

### Requirement: FE-199 — Formulário de cadastro e edição de renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
O formulário captura empresa, fornecedor, tipo, identificação, datas e valores do acordo.
Fonte legada: `new/_body.html.erb:1-133`.

#### Scenario: Campos do formulário
- **GIVEN** o formulário aberto
- **WHEN** ele é exibido
- **THEN** estão presentes Empresa, Fornecedor, Tipo, Nome da renegociação, Chave de integração, Indexador de correção monetária, Data da negociação, Observação, Origem, Valor da renegociação, Valor com juros projetados, Valor do deságio e Taxa de juros acordada

#### Scenario: Título na edição
- **GIVEN** a edição de uma renegociação do fornecedor "Fornecedor Alfa"
- **WHEN** o formulário é aberto
- **THEN** o título mostra "Editar Fornecedor Alfa"

#### Scenario: Campos de carência e taxa de correção
- **GIVEN** as colunas `grace_period` e `interest_rate_correction` existentes no banco
- **WHEN** o formulário é exibido
- **THEN** elas não aparecem na tela, como no legado
> AMBIGUIDADE: D-47 — os dois campos existem no banco, não têm tela e não são lidos por nenhum cálculo; confirmar se viram campos reais ou se são removidos

### Requirement: FE-200 — Estados de bloqueio do formulário
O sistema SHALL se comportar conforme os cenários desta seção.
Sem fornecedor ou sem empresa no projeto, o formulário é substituído por uma explicação.
Fonte legada: `new/_body.html.erb:3-5`, `:119-131`.

#### Scenario: Projeto sem fornecedor
- **GIVEN** um projeto sem fornecedores
- **WHEN** o formulário é aberto
- **THEN** a tela mostra "É necessário ter um fornecedor no projeto padrão..." e retorna à lista

#### Scenario: Projeto sem empresa
- **GIVEN** um projeto sem empresas
- **WHEN** o formulário é aberto
- **THEN** a tela mostra "Esse projeto não possui empresa, clique aqui para cadastrar..." com o atalho de cadastro de empresa

### Requirement: FE-201 — Máscaras de dinheiro e percentual
O sistema SHALL se comportar conforme os cenários desta seção.
Os campos monetários e de percentual normalizam a digitação e formatam na saída do foco.
Fonte legada: `.../renegotiation_installments/helper/_body.js.erb:43-99`.

#### Scenario: Formatação monetária
- **GIVEN** o campo de valor da renegociação
- **WHEN** o usuário digita `100000,00` e sai do campo
- **THEN** o campo exibe `R$ 100.000,00`

#### Scenario: Mais de um separador decimal
- **GIVEN** o campo em foco
- **WHEN** um segundo separador é digitado
- **THEN** a tela avisa "Você só precisa inserir 1 separador para as casas decimais"

#### Scenario: Terceira casa decimal
- **GIVEN** o usuário digitando `1,239`
- **WHEN** o campo perde o foco
- **THEN** o valor fica `1,23` — a terceira casa é truncada, não arredondada
> Nota: DEC-02 — o truncamento do legado é preservado, porque ele é o primeiro passo da cadeia de arredondamento que produz os totais atuais

#### Scenario: Campo vazio
- **GIVEN** um campo monetário deixado em branco
- **WHEN** ele perde o foco
- **THEN** o valor passa a ser `0,00`

### Requirement: FE-202 — Seletor de datas dos formulários
O sistema SHALL se comportar conforme os cenários desta seção.
As datas usam seletor em pt-BR no formato `dd/mm/aaaa`. Fonte legada:
`.../renegotiation_installments/helper/_body.js.erb:101-139`.

#### Scenario: Seleção de data
- **GIVEN** o campo de data da negociação
- **WHEN** o usuário abre o seletor e escolhe 10/04/2026
- **THEN** o campo exibe `10/04/2026` e o valor enviado corresponde a essa data

#### Scenario: Limpar o campo
- **GIVEN** uma data já escolhida
- **WHEN** o usuário limpa o campo
- **THEN** o seletor também é limpo e nenhuma data é enviada

### Requirement: FE-203 — Retorno do salvamento da renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
Erros vêm com o nome do campo em pt-BR e o sucesso distingue criação de atualização.
Fonte legada: `new/handle.js.erb:1-13`; `renegotiations_controller.rb:143-188`.

#### Scenario: Erros traduzidos
- **GIVEN** um formulário recusado por falta de tipo e de data
- **WHEN** a resposta chega
- **THEN** a tela mostra um aviso por erro, com o nome do campo em pt-BR

#### Scenario: Mensagem de criação
- **GIVEN** a criação concluída para o fornecedor "Fornecedor Alfa"
- **WHEN** a resposta chega
- **THEN** a mensagem informa que a renegociação foi criada
> Nota: corrige comportamento legado (a mesma frase "foi atualizada com sucesso" era usada na criação)

### Requirement: FE-204 — Tela de detalhe da renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
O detalhe tem cabeçalho com nome e fornecedor, as abas GERAL e PREVISÕES e o retorno para
a lista. Fonte legada: `detail/_body.html.erb:1-25`; `detail/_body.js.erb:1-34`.

#### Scenario: Aba padrão
- **GIVEN** o detalhe recém-aberto
- **WHEN** a tela carrega
- **THEN** a aba GERAL está ativa

#### Scenario: Endereço da tela
- **GIVEN** o detalhe de uma renegociação aberto
- **WHEN** o usuário copia o endereço e o abre em outra aba
- **THEN** o mesmo detalhe é carregado
> Nota: corrige D-92 (comportamento legado: o estado de navegação vivia só em memória JS e a URL era apenas espelhada, sem deep-link nem histórico)

### Requirement: FE-205 — Card de cadastro do detalhe
O sistema SHALL se comportar conforme os cenários desta seção.
O card "CADASTRO" mostra os dados contratados do acordo, somente leitura. Fonte legada:
`detail/tabs/_tab_geral.html.erb:5-68`.

#### Scenario: Campos do card
- **GIVEN** uma renegociação completa
- **WHEN** o card é exibido
- **THEN** ele mostra Renegociação, Tipo, Fornecedor, Origem, Projeto, Data da negociação em `dd/mm/aaaa`, Valor original, Valor com juros projetados, Valor do deságio, Valor após deságio, Taxa de juros com duas casas e `%`, Indexador CM e Observação

#### Scenario: Campo vazio
- **GIVEN** uma renegociação sem observação
- **WHEN** o card é exibido
- **THEN** o campo mostra `-`

### Requirement: FE-206 — Cards de resumo financeiro do detalhe
O sistema SHALL se comportar conforme os cenários desta seção.
Quatro cards resumem principal, juros, correção, pagos, pendentes, status e percentual.
Fonte legada: `detail/tabs/_tab_geral.html.erb:97-188`.

#### Scenario: Conteúdo dos quatro cards
- **GIVEN** uma renegociação com parcelas e pagamentos
- **WHEN** os cards são exibidos
- **THEN** o primeiro traz Valor principal, Valor dos juros e Principal + Juros; o segundo, Correção monetária, Principal + Juros + CM e Valor total da renegociação; o terceiro, Valor Pago Mora + Juros por Atraso, Valor Pago Principal + Juros + CM e Pendente; o quarto, Status, % Pago e Valor Pago Total

#### Scenario: Status antes da resposta
- **GIVEN** o detalhe recém-aberto
- **WHEN** os valores ainda não chegaram
- **THEN** o campo Status mostra `-`

### Requirement: FE-207 — Atualização assíncrona dos cards
O sistema SHALL se comportar conforme os cenários desta seção.
Os cards são atualizados ao abrir a tela e após qualquer alteração de parcela ou
pagamento. Fonte legada: `detail/_body.js.erb:41-83`.

#### Scenario: Atualização após registrar pagamento
- **GIVEN** o detalhe aberto
- **WHEN** um pagamento é registrado
- **THEN** os quatro cards são atualizados com os valores recalculados, formatados como moeda ou percentual conforme o campo

#### Scenario: Campo ausente na resposta
- **GIVEN** uma resposta em que um dos campos esperados não vem
- **WHEN** os cards são atualizados
- **THEN** aquele campo fica vazio e os demais continuam sendo atualizados
> Nota: corrige comportamento legado (um valor indefinido lançava `TypeError` e interrompia a atualização de todos os cards seguintes)

#### Scenario: Falha na atualização é sinalizada
- **GIVEN** a chamada de atualização retornando erro
- **WHEN** a resposta chega
- **THEN** a tela sinaliza a falha em vez de deixar valores desatualizados sem aviso
> Nota: corrige comportamento legado (o tratamento de erro era vazio e a falha era silenciosa)

### Requirement: FE-208 — Galeria de imagens dos anexos
O sistema SHALL se comportar conforme os cenários desta seção.
Anexos de imagem aparecem como miniaturas que abrem em visualizador. Fonte legada:
`_tab_geral.html.erb:70-93`; `_tab_geral.js.erb:36-83`.

#### Scenario: Galeria com imagens
- **GIVEN** uma renegociação com 3 anexos de imagem e 2 PDFs
- **WHEN** o detalhe é aberto
- **THEN** a galeria mostra as 3 imagens e o clique abre o visualizador

#### Scenario: Sem anexos de imagem
- **GIVEN** uma renegociação só com PDFs
- **WHEN** o detalhe é aberto
- **THEN** a seção de galeria não é exibida

#### Scenario: Imagem ausente ou corrompida
- **GIVEN** um anexo de imagem cujo arquivo sumiu do armazenamento
- **WHEN** o detalhe é aberto
- **THEN** a tela carrega normalmente e apenas aquela miniatura é substituída por um marcador de indisponível
> Nota: corrige comportamento legado (a leitura das dimensões abria o arquivo em disco por imagem e uma falha derrubava a página de detalhe inteira com 500)

#### Scenario: Miniatura em tamanho adequado
- **GIVEN** um anexo de imagem de alta resolução
- **WHEN** a miniatura é exibida
- **THEN** é servida uma versão reduzida, não o arquivo original
> Nota: corrige comportamento legado (nenhum estilo de imagem era declarado, então a miniatura resolvia para o arquivo original em tamanho cheio)

### Requirement: FE-209 — Seção de arquivos do detalhe
O sistema SHALL se comportar conforme os cenários desta seção.
A seção "Arquivos" lista os anexos com título, formato e ações, e sinaliza o limite.
Fonte legada: `_tab_geral.html.erb:191-229`;
`renegotiation_attachments/list/_widget.html.erb:1-17`.

#### Scenario: Lista de arquivos
- **GIVEN** uma renegociação com 3 anexos
- **WHEN** a seção é exibida
- **THEN** o título mostra a contagem e cada linha traz o nome sem extensão, o formato e as ações

#### Scenario: Renegociação sem arquivos
- **GIVEN** uma renegociação sem anexos
- **WHEN** a seção é exibida
- **THEN** a tela mostra "Essa renegociação não possui arquivos"

#### Scenario: Limite de anexos atingido
- **GIVEN** uma renegociação com 4 anexos
- **WHEN** a seção é exibida
- **THEN** a área de envio fica bloqueada e o motivo é comunicado
> Nota: corrige D-50 (comportamento legado: o indicador de bloqueio era escrito no HTML e nunca lido pelo JavaScript)

### Requirement: FE-210 — Envio de anexos por arrastar e soltar
O sistema SHALL se comportar conforme os cenários desta seção.
O usuário envia arquivos arrastando sobre a área ou escolhendo pelo seletor múltiplo,
com os limites aplicados. Fonte legada: `_tab_geral.js.erb:11-33`, `:85-127`;
`app/definitions/SFG/metadata.rb:21-23`.

#### Scenario: Envio bem-sucedido
- **GIVEN** a área de anexos
- **WHEN** o usuário solta 2 arquivos válidos
- **THEN** a tela mostra "Os anexos foram adicionados com sucesso" e a lista é atualizada

#### Scenario: Arquivo acima do tamanho permitido
- **GIVEN** um arquivo de 8 MB
- **WHEN** ele é solto na área
- **THEN** a tela avisa o limite de 5 MB e o envio não ocorre

#### Scenario: Quantidade acima do permitido
- **GIVEN** uma renegociação com 3 anexos
- **WHEN** o usuário tenta enviar mais 3 arquivos
- **THEN** a tela avisa o limite de 4 arquivos por renegociação e o envio não ocorre
> Nota: corrige D-50 (comportamento legado: a checagem de quantidade lia o seletor `.lesson_attachment_content_wrapper`, de outro produto, resultando em comparação com `NaN` que nunca disparava — e o servidor também não tinha limite)

### Requirement: FE-211 — Exclusão de anexo pela tela
O sistema SHALL se comportar conforme os cenários desta seção.
O anexo é excluído com confirmação, e a ação só é oferecida a quem pode excluí-lo. Fonte
legada: `renegotiation_attachments/list/_widget.js.erb:9-35`.

#### Scenario: Exclusão confirmada
- **GIVEN** um anexo do próprio usuário
- **WHEN** ele confirma "Excluir o arquivo"
- **THEN** a tela mostra "O arquivo foi excluido com sucesso" e a lista é atualizada

#### Scenario: Anexo de outro usuário
- **GIVEN** um anexo enviado por outro usuário
- **WHEN** a lista é exibida
- **THEN** a ação de excluir não é oferecida, e o servidor também recusa a operação
> Nota: corrige D-82 (comportamento legado: a regra de dono era apenas visual)

### Requirement: FE-212 — Visualizar e baixar anexo pela tela
O sistema SHALL se comportar conforme os cenários desta seção.
Cada anexo tem uma ação de abrir o arquivo. Fonte legada:
`renegotiation_attachments/list/_widget.html.erb:9-11`.

#### Scenario: Abrir o arquivo
- **GIVEN** um anexo PDF
- **WHEN** o usuário aciona a visualização
- **THEN** o arquivo é aberto a partir do endereço autorizado de download

#### Scenario: Anexo de tipo executável não é aberto na aplicação
- **GIVEN** um anexo cujo conteúdo não é um tipo visualizável permitido
- **WHEN** o usuário aciona a visualização
- **THEN** o arquivo é entregue como download
> Nota: corrige D-82 (ver BE-227)

### Requirement: FE-213 — Aba de previsões: cabeçalho e colunas
O sistema SHALL se comportar conforme os cenários desta seção.
A aba PREVISÕES lista as parcelas em 12 colunas, com uma barra de ações de escrita.
Fonte legada: `detail/tabs/_tab_renegotiation_installment.html.erb:1-90`.

#### Scenario: Colunas das previsões
- **GIVEN** a aba PREVISÕES aberta
- **WHEN** a lista é exibida
- **THEN** as colunas são número da parcela, Vencimento, Principal, Juros, Principal + Juros, CM, Principal + Juros + CM, Mora e Atraso, Total, Pago e Pendente, além das ações

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** a aba é exibida
- **THEN** a barra com "Remover Parcela", "Cadastrar", "Selecionar", "Cancelar" e "Selecionar todos" não existe

### Requirement: FE-214 — Lista de parcelas
O sistema SHALL se comportar conforme os cenários desta seção.
A lista de parcelas carrega as previsões da renegociação com valores em reais e datas em
`dd/mm/aaaa`. Fonte legada: `.../renegotiation_installments/list/_widget.html.erb:1-64`.

#### Scenario: Carregamento e estado vazio
- **GIVEN** uma renegociação sem parcelas
- **WHEN** a aba é aberta
- **THEN** a tela passa de "Buscando .." para "Nenhum resultado encontrado"

#### Scenario: Parcela com pagamento não é selecionável
- **GIVEN** uma parcela com pagamento vinculado
- **WHEN** a lista é exibida
- **THEN** a linha é marcada como não selecionável

#### Scenario: Falha ao carregar as parcelas
- **GIVEN** a busca de parcelas retornando erro
- **WHEN** a resposta chega
- **THEN** a tela mostra um estado de erro
> Nota: corrige comportamento legado (a lista de parcelas não tinha tratamento de erro)

### Requirement: FE-215 — Pagamentos aninhados na parcela
O sistema SHALL se comportar conforme os cenários desta seção.
Cada parcela expande para mostrar seus pagamentos. Fonte legada:
`.../renegotiation_installments/list/_widget.html.erb:65-102`.

#### Scenario: Expandir e recolher
- **GIVEN** uma parcela com 2 pagamentos
- **WHEN** o usuário clica na linha
- **THEN** as duas sublinhas de pagamento aparecem, com número, data, valor pago de principal com juros e correção, mora e total pago; um novo clique recolhe

#### Scenario: Clique ignorado no modo de seleção
- **GIVEN** o modo de seleção ativo e uma parcela não selecionável
- **WHEN** o usuário clica na linha
- **THEN** nada é expandido

### Requirement: FE-216 — Menu de ações da parcela
O sistema SHALL se comportar conforme os cenários desta seção.
O menu da parcela oferece gerar pagamento, editar e remover. Fonte legada:
`.../renegotiation_installments/list/_widget.js.erb:70-92`, `:105-182`.

#### Scenario: Gerar pagamento
- **GIVEN** uma parcela em aberto
- **WHEN** o usuário aciona "Gerar pagamento"
- **THEN** o painel lateral de pagamento abre já vinculado àquela parcela

#### Scenario: Remover só sem pagamento
- **GIVEN** uma parcela com pagamento
- **WHEN** o menu é aberto
- **THEN** a ação de remover não é oferecida

#### Scenario: Remoção confirmada
- **GIVEN** uma parcela sem pagamento
- **WHEN** o usuário confirma "Excluir previsão — A operação não pode ser desfeita. Tem certeza?"
- **THEN** a parcela é removida, a lista é recarregada e os cards de resumo são atualizados

### Requirement: FE-217 — Modo de seleção múltipla de parcelas
O sistema SHALL se comportar conforme os cenários desta seção.
O modo de seleção permite marcar várias parcelas para remoção em lote. Fonte legada:
`_tab_renegotiation_installment.js.erb:71-89`, `:179-289`.

#### Scenario: Entrar e sair do modo
- **GIVEN** a aba PREVISÕES
- **WHEN** o usuário aciona "Selecionar"
- **THEN** aparecem as caixas de seleção, somem "Cadastrar", "Selecionar" e os menus de linha; "Cancelar" desfaz tudo e limpa a seleção

#### Scenario: Selecionar todos
- **GIVEN** o modo de seleção ativo com 8 parcelas, 2 delas com pagamento
- **WHEN** o usuário aciona "Selecionar todos"
- **THEN** apenas as 6 parcelas sem pagamento são marcadas

#### Scenario: Rótulo do botão de remoção
- **GIVEN** 3 parcelas marcadas
- **WHEN** a barra é exibida
- **THEN** o botão mostra "REMOVER 3 PARCELAS"

### Requirement: FE-218 — Remoção de parcelas em lote pela tela
O sistema SHALL se comportar conforme os cenários desta seção.
A remoção em lote pede confirmação explícita e reflete o resultado do servidor. Fonte
legada: `_tab_renegotiation_installment.js.erb:91-167`.

#### Scenario: Nada selecionado
- **GIVEN** o modo de seleção sem nenhuma parcela marcada
- **WHEN** o usuário aciona a remoção
- **THEN** a tela avisa "Selecione alguma previsão" e nada é enviado

#### Scenario: Confirmação sem expiração
- **GIVEN** parcelas marcadas
- **WHEN** o usuário aciona a remoção
- **THEN** a confirmação "A operação não pode ser desfeita. Tem certeza?" permanece disponível até o usuário decidir
> Nota: corrige comportamento legado (a confirmação de uma operação irreversível se autodescartava em 6 segundos)

#### Scenario: Remoção concluída
- **GIVEN** a confirmação aceita
- **WHEN** o servidor conclui a remoção
- **THEN** o modo de seleção fecha, a lista é recarregada do início e os cards de resumo são atualizados

### Requirement: FE-219 — Bloqueio de seleção para parcela com pagamento
O sistema SHALL se comportar conforme os cenários desta seção.
Parcelas com pagamento não podem entrar na remoção em lote. Fonte legada:
`.../renegotiation_installments/list/_widget.html.erb:1`, `:55-63`;
`_tab_renegotiation_installment.js.erb:191-206`.

#### Scenario: Parcela com pagamento sem caixa de seleção
- **GIVEN** uma parcela com pagamento
- **WHEN** o modo de seleção é ativado
- **THEN** ela não recebe caixa de seleção

#### Scenario: Tentativa de remover parcela bloqueada
- **GIVEN** uma seleção que inclui parcela com pagamento
- **WHEN** o usuário aciona a remoção
- **THEN** a tela mostra "Não é possível remover previsões com pagamentos" e nada é enviado

### Requirement: FE-220 — Painel lateral de parcela
O sistema SHALL se comportar conforme os cenários desta seção.
O painel alterna entre criação de parcela única, criação em lote e edição. Fonte legada:
`.../renegotiation_installments/helper/_body.html.erb:1-145`.

#### Scenario: Modo parcela única
- **GIVEN** o painel aberto para criação
- **WHEN** o usuário escolhe "Parcela Única"
- **THEN** aparecem os valores principal, juros e correção, os campos somente leitura de totais, e a data da parcela com padrão no primeiro vencimento da renegociação ou hoje

#### Scenario: Modo múltiplas parcelas
- **GIVEN** o painel aberto para criação
- **WHEN** o usuário escolhe "Múltiplas Parcelas"
- **THEN** aparecem Data início (padrão no último vencimento ou hoje), Repetições (padrão 1), A cada (padrão 1) e Período com Dias, Semanas e Meses

#### Scenario: Modo edição
- **GIVEN** o painel aberto para editar uma parcela
- **WHEN** ele é exibido
- **THEN** o bloco de criação múltipla some, aparece o valor pago de mora somente leitura e a data da parcela

#### Scenario: Campos de repetição inteiros
- **GIVEN** o campo de repetições
- **WHEN** o usuário digita `0` ou um valor não inteiro
- **THEN** o valor é ajustado para o mínimo de 1

### Requirement: FE-221 — Cálculo em tempo real do painel de parcela
O sistema SHALL se comportar conforme os cenários desta seção.
O painel mostra os totais derivados enquanto o usuário preenche os valores. Fonte
legada: `.../renegotiation_installments/helper/_body.js.erb:192-220`.

#### Scenario: Totais derivados
- **GIVEN** principal 1.000,00, juros 100,00 e correção 50,00
- **WHEN** os campos perdem o foco
- **THEN** o painel mostra Principal + Juros de 1.100,00, Principal + Juros + CM de 1.150,00 e Valor total da parcela de 1.150,00

#### Scenario: Prévia e gravação coincidem
- **GIVEN** os totais exibidos na prévia
- **WHEN** a parcela é salva sem alteração
- **THEN** os valores gravados são idênticos aos exibidos
> Nota: corrige D-09 (comportamento legado: as fórmulas eram reimplementadas em JavaScript, duplicando a regra financeira entre browser e servidor)

### Requirement: FE-222 — Habilitação do salvar no painel de parcela
O sistema SHALL se comportar conforme os cenários desta seção.
O botão de salvar só fica disponível quando o valor principal é maior que zero. Fonte
legada: `.../renegotiation_installments/helper/_body.js.erb:11-27`.

#### Scenario: Principal zerado
- **GIVEN** o painel com principal 0
- **WHEN** os campos perdem o foco
- **THEN** o botão de salvar continua indisponível

#### Scenario: Guarda também no servidor
- **GIVEN** uma parcela com principal 0 enviada diretamente à API
- **WHEN** a requisição é processada
- **THEN** a resposta é 422
> Nota: corrige D-52 (comportamento legado: a tela era a única barreira real; o servidor tinha a validação, mas o erro era engolido e a resposta era 200)

### Requirement: FE-223 — Envio e estados do painel de parcela
O sistema SHALL se comportar conforme os cenários desta seção.
O envio converte os valores formatados, mostra o progresso e fecha o painel em caso de
sucesso. Fonte legada: `.../renegotiation_installments/helper/_mount.js.erb:14-33`, `:95-150`.

#### Scenario: Salvamento bem-sucedido
- **GIVEN** o painel preenchido
- **WHEN** o usuário salva
- **THEN** a tela mostra a mensagem de criação ou atualização conforme o modo, os cards de resumo são atualizados, a lista é recarregada e o painel fecha restaurando o endereço anterior

#### Scenario: Falha mantém o painel aberto
- **GIVEN** um envio recusado por validação
- **WHEN** a resposta chega
- **THEN** os erros são exibidos por campo e o painel permanece aberto com os valores digitados

### Requirement: FE-224 — Painel lateral de pagamento
O sistema SHALL se comportar conforme os cenários desta seção.
O painel captura a parcela, os valores pagos e a data do pagamento. Fonte legada:
`.../renegotiation_payments/helper/_body.html.erb:1-54`.

#### Scenario: Campos do painel
- **GIVEN** o painel aberto sem parcela pré-selecionada
- **WHEN** ele é exibido
- **THEN** aparece o seletor de previsão com número, vencimento e valor pendente de cada parcela, mais Parcela + Juros + CM, Mora e Juros por Atraso, Pago Total somente leitura e Data do pagamento

#### Scenario: Parcela pré-selecionada
- **GIVEN** o painel aberto a partir de uma parcela
- **WHEN** ele é exibido
- **THEN** o seletor de previsão não é oferecido e a parcela vinculada é a de origem

#### Scenario: Pagamento retroativo
- **GIVEN** um pagamento que ocorreu há 5 dias
- **WHEN** o painel é preenchido
- **THEN** é possível informar a data real do pagamento, e os dias de atraso são calculados a partir dela
> Nota: corrige comportamento legado (a data era somente leitura e sempre igual a hoje na criação, contradizendo a existência do cálculo de dias de atraso)

### Requirement: FE-225 — Cálculo e habilitação do salvar no painel de pagamento
O sistema SHALL se comportar conforme os cenários desta seção.
O painel calcula o total pago e só libera o salvamento com valor positivo. Fonte legada:
`.../renegotiation_payments/helper/_body.js.erb:63-76`, `:93-111`.

#### Scenario: Total pago
- **GIVEN** 1.150,00 de parcela com juros e correção e 80,00 de mora
- **WHEN** os campos perdem o foco
- **THEN** o Pago Total mostra 1.230,00

#### Scenario: Valor zerado
- **GIVEN** o valor de parcela com juros e correção em zero
- **WHEN** os campos perdem o foco
- **THEN** o botão de salvar continua indisponível

#### Scenario: Pagamento maior que o pendente da parcela
- **GIVEN** uma parcela com pendente de 500,00
- **WHEN** o usuário informa 800,00
- **THEN** a tela sinaliza que o valor excede o pendente e o salvamento é bloqueado
> Nota: corrige D-52 (comportamento legado: não havia checagem em nenhuma camada; o pendente aparecia apenas como rótulo no seletor)

### Requirement: FE-226 — Envio e fechamento do painel de pagamento
O sistema SHALL se comportar conforme os cenários desta seção.
Salvar um pagamento atualiza a lista de parcelas, os cards e fecha o painel. Fonte
legada: `.../renegotiation_payments/helper/_mount.js.erb:14-33`, `:95-149`.

#### Scenario: Painel fecha após salvar
- **GIVEN** o painel de pagamento preenchido
- **WHEN** o usuário salva com sucesso
- **THEN** a lista de parcelas é recarregada, os cards são atualizados, o endereço é restaurado e o painel fecha
> Nota: corrige comportamento legado (o callback tentava atualizar um container de pagamentos que nunca era definido — porque a aba de pagamentos estava comentada — levantando `TypeError` e deixando o painel aberto após salvar)

#### Scenario: Mensagem correta de pagamento
- **GIVEN** um pagamento salvo
- **WHEN** a mensagem é exibida
- **THEN** ela fala em pagamento criado ou atualizado
> Nota: corrige comportamento legado (a mensagem dizia "A previsão foi criada/atualizada")

### Requirement: FE-227 — Editar e excluir pagamento pela lista
O sistema SHALL se comportar conforme os cenários desta seção.
As sublinhas de pagamento permitem edição e exclusão diretamente na aba de previsões.
Fonte legada: `.../renegotiation_installments/list/_widget.js.erb:5-68`.

#### Scenario: Editar pagamento
- **GIVEN** uma sublinha de pagamento
- **WHEN** o usuário clica nela
- **THEN** o painel de pagamento abre em modo edição e o endereço da tela reflete o pagamento aberto
> Nota: corrige comportamento legado (o endereço era montado com um marcador não substituído e ficava literalmente com `{pid}`)

#### Scenario: Confirmação com o rótulo correto
- **GIVEN** a exclusão de um pagamento
- **WHEN** a confirmação aparece
- **THEN** ela identifica a exclusão de um pagamento
> Nota: corrige comportamento legado (o título da confirmação era "Excluir previsão")

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** as sublinhas são exibidas
- **THEN** a edição e a exclusão de pagamento não são oferecidas

### Requirement: FE-228 — Regras de permissão na tela de renegociações
O sistema SHALL se comportar conforme os cenários desta seção.
Com `user_is_readonly`, todas as ações de escrita da área de renegociações são
suprimidas. Fonte legada: `_body.html.erb:13`, `:18`;
`_tab_renegotiation_installment.html.erb:3`, `:35`.

#### Scenario: Ações suprimidas na tela
- **GIVEN** um usuário somente-leitura
- **WHEN** ele percorre lista, detalhe, previsões e anexos
- **THEN** não são oferecidos cadastro, edição, remoção, envio de anexo, seleção de parcelas nem exclusão de pagamento

#### Scenario: Servidor também recusa
- **GIVEN** o mesmo usuário chamando diretamente qualquer endpoint de escrita da área
- **WHEN** a requisição chega ao servidor
- **THEN** ela é recusada por autorização
> Nota: corrige D-17 (comportamento legado: a proteção era apenas visual; nenhum controller checava a permissão e todas as rotas continuavam acessíveis)

### Requirement: FE-229 — Superfícies desabilitadas do detalhe
O sistema SHALL se comportar conforme os cenários desta seção.
A aba dedicada de pagamentos e a ação de excluir todas as parcelas existem no código do
legado mas estão desativadas. Fonte legada: `detail/_body.html.erb:22`;
`detail/_body.js.erb:6`, `:31-38`; `detail/tabs/_tab_renegotiation_payment.*`.

#### Scenario: Pagamentos visíveis apenas aninhados
- **GIVEN** o detalhe de uma renegociação
- **WHEN** o usuário procura os pagamentos
- **THEN** eles aparecem aninhados nas parcelas, e não há aba dedicada
> AMBIGUIDADE: D-53 — a aba PAGAMENTOS (com colunas Previsão, Número, Data, Valor e Atraso) está comentada na view e é a causa do painel não fechar (FE-226); confirmar se ela entra no escopo do ai9

#### Scenario: Ação de excluir todas as parcelas
- **GIVEN** uma renegociação com parcelas e sem pagamentos
- **WHEN** o detalhe é exibido
- **THEN** nenhuma ação de "excluir todas as parcelas" é oferecida, como no legado
> AMBIGUIDADE: a lógica de habilitação continua sendo calculada no legado, mas o botão está comentado; confirmar se a ação deve existir no ai9

### Requirement: DB-190 — Tabela `renegotiations`
O sistema SHALL se comportar conforme os cenários desta seção.
A renegociação guarda o cadastro do acordo, os valores contratados e cerca de vinte
agregados derivados das parcelas e pagamentos. Fonte legada:
`db/migrate/20210324173930_create_renegotiations.rb:3-34`; `app/models/renegotiation.rb`.

#### Scenario: Integridade referencial garantida pelo banco
- **GIVEN** uma tentativa de gravar renegociação com `provider_id` inexistente
- **WHEN** a gravação é executada
- **THEN** o banco recusa a operação
> Nota: corrige D-103 (comportamento legado: nenhum índice e nenhuma chave estrangeira em nenhuma das migrations de renegociação)

#### Scenario: Agregados sempre coerentes com as parcelas
- **GIVEN** uma renegociação cujas parcelas foram alteradas
- **WHEN** ela é consultada
- **THEN** os agregados refletem as parcelas atuais

#### Scenario: Estado e tipo com domínio fechado
- **GIVEN** um payload com `kind` ou `state` fora do domínio conhecido
- **WHEN** a gravação é tentada
- **THEN** ela é recusada
> Nota: corrige comportamento legado (`kind` e `state` eram strings livres sem restrição no banco)

### Requirement: DB-191 — Tabela `renegotiation_installments`
O sistema SHALL se comportar conforme os cenários desta seção.
A parcela guarda vencimento, ordinal, valores derivados, identidade do lote e a situação
de quitação. Fonte legada:
`db/migrate/20210324174436_create_renegotiation_installments.rb:3-17`.

#### Scenario: Unicidade da data por renegociação no banco
- **GIVEN** duas gravações concorrentes com a mesma data na mesma renegociação
- **WHEN** ambas são processadas
- **THEN** apenas uma é aceita
> Nota: corrige D-103 (comportamento legado: a unicidade existia só na aplicação, sem índice único no banco)

#### Scenario: Consultas de parcela indexadas
- **GIVEN** uma renegociação com dezenas de parcelas
- **WHEN** a lista e os agregados são montados
- **THEN** as consultas usam índices por renegociação, vencimento e situação de quitação
> Nota: corrige D-12 (comportamento legado: sem índice em `renegotiation_id`, `due_date`, `batch_token` ou `is_paid`)

#### Scenario: Semântica de saldo e pendente
- **GIVEN** uma parcela de 1.150,00 sem pagamento
- **WHEN** ela é consultada
- **THEN** `saldo = −1.150,00` (pago menos total, negativo enquanto há dívida) e `pending_value = 1.150,00`, com a diferença de sinal documentada

### Requirement: DB-192 — Tabela `renegotiation_payments`
O sistema SHALL se comportar conforme os cenários desta seção.
O pagamento guarda o valor pago de principal com juros e correção, a mora, o total, a
data, os dias de atraso e o ordinal. Fonte legada:
`db/migrate/20210324174615_create_renegotiation_payments.rb:3-12`.

#### Scenario: Consultas de pagamento indexadas
- **GIVEN** uma parcela com vários pagamentos
- **WHEN** os agregados são recalculados
- **THEN** as consultas usam índice por parcela e por renegociação
> Nota: corrige D-12 (comportamento legado: nenhum índice na tabela)

#### Scenario: Renegociação do pagamento coerente com a da parcela
- **GIVEN** um pagamento cuja renegociação diverge da parcela
- **WHEN** a gravação é tentada
- **THEN** ela é recusada
> Nota: corrige D-52 (comportamento legado: `renegotiation_id` era redundante e não era validado contra a parcela)

#### Scenario: Ausência de forma de pagamento
- **GIVEN** a estrutura do pagamento
- **WHEN** ela é migrada
- **THEN** ela preserva os campos existentes, sem forma de pagamento nem dados de conciliação bancária
> AMBIGUIDADE: o legado não registra forma de pagamento nem conciliação; confirmar se é lacuna a preencher ou ausência intencional

### Requirement: DB-193 — Tabela `renegotiation_attachments`
O sistema SHALL se comportar conforme os cenários desta seção.
O anexo guarda a renegociação, o autor, o título e os metadados do arquivo. Fonte
legada: `db/migrate/20210503195535_create_renegotiation_attachments.rb:3-11`.

#### Scenario: Metadados preservados na migração
- **GIVEN** anexos legados com nome, tipo e tamanho gravados
- **WHEN** a carga é executada
- **THEN** os metadados são preservados e o tipo é revalidado a partir do conteúdo real do arquivo
> Nota: corrige D-82 (comportamento legado: o tipo declarado nunca foi validado, com o detector de spoof desligado)

#### Scenario: Binários migrados junto
- **GIVEN** os arquivos gravados no disco do legado
- **WHEN** a migração é executada
- **THEN** os binários são transferidos para o armazenamento privado do ai9 e cada registro aponta para o arquivo correspondente

### Requirement: DB-194 — Renomes de colunas de 2022
O sistema SHALL se comportar conforme os cenários desta seção.
Três colunas foram renomeadas em 29/04/2022, com mudança de semântica. Fonte legada:
`db/migrate/20220429122226:4`; `20220429122346:3`; `20220429122419:3`.

#### Scenario: Mapeamento pelo nome novo
- **GIVEN** o mapeamento `renegotiations.total_value` → `installments_main_value`, `renegotiation_installments.value` → `main_value` e `renegotiation_payments.value` → `installment_paid_value_with_interest_cm`
- **WHEN** a carga de dados é escrita
- **THEN** ela usa os nomes novos e a semântica nova, em que o valor da parcela é apenas o principal

#### Scenario: Consumidor externo anterior à mudança
- **GIVEN** relatórios ou integrações que usam os nomes antigos
- **WHEN** a migração é planejada
- **THEN** o mapeamento antigo para novo fica registrado para conferência
> AMBIGUIDADE: não se sabe se existem consumidores externos lendo os nomes antigos; confirmar antes do cutover

### Requirement: DB-195 — Contador de anexos
O sistema SHALL se comportar conforme os cenários desta seção.
`attachments_count` foi adicionado sem valor padrão nem preenchimento retroativo. Fonte
legada: `db/migrate/20210503202015_add_attachments_count_to_renegotiation.rb:3`.

#### Scenario: Contador preenchido para registros antigos
- **GIVEN** renegociações criadas antes de 03/05/2021, com o contador nulo
- **WHEN** a carga é executada
- **THEN** o contador é preenchido com a contagem real de anexos e a coluna passa a ser obrigatória com padrão zero
> Nota: corrige comportamento legado (o nulo fazia `has_attachments?` executar `nil > 0` e levantar `NoMethodError`)

#### Scenario: Contador sempre coerente
- **GIVEN** uma renegociação com 3 anexos
- **WHEN** um anexo é adicionado ou removido
- **THEN** o contador acompanha imediatamente

### Requirement: DB-196 — Precisão numérica e política de arredondamento
O sistema SHALL se comportar conforme os cenários desta seção.
O domínio usa `decimal(15,2)` para dinheiro e ponto flutuante para percentuais e taxas.
Fonte legada: `db/migrate/20210324173930_create_renegotiations.rb:9-30`;
`config/initializers/type_casting.rb:30-90`.

#### Scenario: Totais idênticos aos do legado
- **GIVEN** uma renegociação cujos agregados no legado são conhecidos
- **WHEN** os mesmos lançamentos são reproduzidos no ai9
- **THEN** os agregados produzidos são idênticos aos do legado
> Nota: DEC-02 — a cadeia de arredondamento do legado é replicada: truncamento em 2 casas na entrada, conversão para ponto flutuante no cálculo e arredondamento final na gravação

#### Scenario: Valor acima do teto da coluna
- **GIVEN** um valor acima de R$ 9.999.999.999.999,99
- **WHEN** a gravação é tentada
- **THEN** a operação é recusada com erro de validação

### Requirement: DB-197 — Carimbo de gestão do projeto na renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
`has_safegold_management` é copiado do projeto na criação e nunca ressincronizado. Fonte
legada: `app/models/renegotiation.rb:24`; `app/models/project.rb:298-302`.

#### Scenario: Carimbo gravado na criação
- **GIVEN** um projeto com a gestão ligada
- **WHEN** uma renegociação é criada
- **THEN** ela guarda o carimbo do momento da criação

#### Scenario: Alteração posterior no projeto
- **GIVEN** renegociações já criadas e o projeto tendo a gestão desligada depois
- **WHEN** as renegociações são consultadas
- **THEN** elas mantêm o carimbo original, como no legado
> AMBIGUIDADE: D-30 — a propagação em massa alcança apenas `companies`, nunca `renegotiations`, e nenhum código de renegociações lê essa coluna; confirmar se o carimbo é fotografia intencional ou defeito, e se deve ser portado

### Requirement: DB-198 — Índices e chaves estrangeiras do domínio de renegociações
O sistema SHALL se comportar conforme os cenários desta seção.
As quatro tabelas nascem no ai9 com integridade referencial e os índices das consultas
efetivamente usadas. Fonte legada: `db/migrate/*renegotiation*` (nenhuma contém
`add_index` nem `add_foreign_key`).

#### Scenario: Índices das consultas quentes
- **GIVEN** as consultas de lista, detalhe e recálculo
- **WHEN** o schema é criado
- **THEN** existem chaves estrangeiras em todas as referências, índice único em `(renegotiation_id, due_date)` e índices em `renegotiation_installments(renegotiation_id)`, `renegotiation_payments(renegotiation_installment_id)` e `renegotiations(project_id, state)`
> Nota: corrige D-103 (comportamento legado: nenhuma das migrations criava índice ou chave estrangeira)

#### Scenario: Listagem sem custo quadrático
- **GIVEN** uma página de renegociações com muitas parcelas
- **WHEN** a lista é montada
- **THEN** o número de consultas não cresce com o número de linhas
> Nota: corrige comportamento legado (busca sem limite somada a cálculos por linha tornava a listagem quadrática em número de consultas)

### Requirement: DB-199 — Integridade referencial e auditoria antes da carga
O sistema SHALL se comportar conforme os cenários desta seção.
As regras de bloqueio de exclusão existem apenas na aplicação legada, então dados órfãos
e divergentes são possíveis. Fonte legada: `app/models/renegotiation.rb:6-8`;
`renegotiation_installment.rb:2`; `renegotiation_payment.rb:2-3`.

#### Scenario: Auditoria de divergências antes da carga
- **GIVEN** a base legada
- **WHEN** a etapa de introspecção do ETL roda
- **THEN** ela reporta pagamentos cuja renegociação diverge da parcela, parcelas com vencimento duplicado, contadores de anexo divergentes da contagem real e renegociações cujo estado é incoerente com o remanescente
> Nota: corrige D-103 (comportamento legado: sem chaves estrangeiras, órfãos e divergências são prováveis e passariam despercebidos na carga)

#### Scenario: Bloqueios preservados
- **GIVEN** as regras de bloqueio de exclusão do legado
- **WHEN** o modelo é portado
- **THEN** renegociação com parcelas ou pagamentos, parcela com pagamentos, projeto com renegociações e fornecedor com renegociações continuam protegidos contra exclusão

### Requirement: OPS-190 — Recálculo periódico dos contadores de renegociação
O sistema SHALL se comportar conforme os cenários desta seção.
O legado roda uma varredura diária que recalcula todas as renegociações não liquidadas,
existindo apenas para atualizar a contagem de parcelas vencidas. Fonte legada:
`lib/cron_facade.rb:1-7`; `config/schedule.prod.rb:4-6`.

#### Scenario: Contagem de vencidas sempre atual
- **GIVEN** uma parcela que venceu hoje
- **WHEN** a renegociação é consultada a qualquer momento
- **THEN** ela já aparece com a contagem de vencidas atualizada, sem depender de varredura noturna
> Nota: corrige D-54 (comportamento legado: `overdue_installments` era coluna persistida, atualizada só pelo cron das 00:01, ficando até 24 h desatualizada)

#### Scenario: Renegociação liquidada volta a ser reprocessada
- **GIVEN** uma renegociação liquidada cujo pagamento é estornado
- **WHEN** os agregados são consultados
- **THEN** o estado volta a refletir o saldo em aberto
> Nota: corrige comportamento legado (o cron só percorria renegociações não liquidadas, então uma liquidada nunca mais era reprocessada e o estorno não a trazia de volta)

#### Scenario: Falha de recálculo é visível
- **GIVEN** uma renegociação que fica inválida durante o recálculo
- **WHEN** o processamento roda
- **THEN** a falha é registrada e visível
> Nota: corrige D-79 (comportamento legado: o `save` sem bang pulava o registro em silêncio e o log só tinha a saída padrão do runner)

### Requirement: OPS-191 — Agendamento por ambiente
O sistema SHALL se comportar conforme os cenários desta seção.
O legado tem três arquivos de agendamento, e o padrão não agenda nada. Fonte legada:
`config/schedule.rb:1-3`; `config/schedule.dev.rb:4-6`; `config/schedule.prod.rb:1-6`.

#### Scenario: Processamento agendado é versionado e único
- **GIVEN** qualquer processamento periódico do domínio no ai9
- **WHEN** ele é definido
- **THEN** existe uma única definição versionada, com retry e alerta em caso de falha

#### Scenario: Execução em mais de um host
- **GIVEN** a aplicação rodando em dois hosts
- **WHEN** um processamento periódico dispara
- **THEN** ele é executado uma única vez
> Nota: corrige comportamento legado (o agendamento vivia no crontab do host, sem trava de concorrência — dois hosts significavam processamento em duplicidade)

### Requirement: OPS-192 — Armazenamento dos anexos
O sistema SHALL se comportar conforme os cenários desta seção.
Os anexos do legado ficam em disco local dentro do diretório público, servidos
diretamente pelo servidor web. Fonte legada:
`app/models/renegotiation_attachment.rb:4-6`.

#### Scenario: Arquivo só acessível por caminho autorizado
- **GIVEN** um anexo armazenado
- **WHEN** alguém tenta acessá-lo por um endereço direto de arquivo
- **THEN** o acesso é negado — o arquivo só é servido pelo caminho autorizado de download
> Nota: corrige D-82 (comportamento legado: os arquivos ficavam sob `public/system/...` e eram servidos pelo webserver sem passar por controller, tornando a rota de download contornável)

#### Scenario: Perda de volume não derruba a tela
- **GIVEN** um ambiente em que os arquivos não estão disponíveis
- **WHEN** o detalhe da renegociação é aberto
- **THEN** a tela carrega e os anexos indisponíveis são sinalizados
> Nota: corrige comportamento legado (container sem volume persistente perdia os anexos e derrubava o detalhe)

### Requirement: OPS-193 — Leitura de dimensões de imagem dos anexos
O sistema SHALL se comportar conforme os cenários desta seção.
O legado lê as dimensões de cada imagem com um processo externo, duas vezes por imagem, a
cada render. Fonte legada: `app/models/renegotiation_attachment.rb:19-36`.

#### Scenario: Dimensões obtidas sem custo por render
- **GIVEN** uma renegociação com anexos de imagem
- **WHEN** o detalhe é aberto repetidamente
- **THEN** as dimensões vêm de metadados já persistidos, sem abrir processo externo por render
> Nota: corrige comportamento legado (duas chamadas de processo externo por imagem, a cada renderização)

#### Scenario: Falha na leitura não derruba a tela
- **GIVEN** um arquivo corrompido ou o utilitário externo ausente
- **WHEN** o detalhe é aberto
- **THEN** a tela carrega e apenas aquela imagem é marcada como indisponível

### Requirement: OPS-194 — Validação de tipo de arquivo enviado
O sistema SHALL se comportar conforme os cenários desta seção.
No legado a detecção de falsificação de tipo está desligada globalmente. Fonte legada:
`config/initializers/paperclip.rb:1-8`.

#### Scenario: Tipo verificado pelo conteúdo
- **GIVEN** um arquivo cujo conteúdo real não corresponde à extensão nem ao tipo declarado
- **WHEN** ele é enviado
- **THEN** o envio é recusado
> Nota: corrige D-82 (comportamento legado: o detector de falsificação era sobrescrito para sempre retornar falso, e qualquer arquivo com qualquer extensão era aceito e depois servido em linha)

#### Scenario: Lista de tipos permitidos
- **GIVEN** a política de anexos do domínio
- **WHEN** um arquivo é enviado
- **THEN** somente os tipos da lista permitida são aceitos

### Requirement: OPS-195 — Escritas em massa sem callbacks
O sistema SHALL se comportar conforme os cenários desta seção.
A renumeração de parcelas e de pagamentos grava em lote sem validações e sem disparar
callbacks, evitando recursão de recálculo. Fonte legada:
`app/models/renegotiation.rb:79`; `renegotiation_installment.rb:88`.

#### Scenario: Renumeração não dispara recálculo em cascata
- **GIVEN** uma renegociação com 60 parcelas
- **WHEN** a renumeração é executada
- **THEN** os ordinais são atualizados em uma única operação, sem disparar novo recálculo dos agregados

#### Scenario: Somente o ordinal é alterado
- **GIVEN** parcelas com valores e situações diversas
- **WHEN** a renumeração roda
- **THEN** apenas a coluna de ordinal muda

### Requirement: OPS-196 — Geração da cor do lote de parcelas
O sistema SHALL se comportar conforme os cenários desta seção.
Cada lote recebe uma cor distinta das já usadas na mesma renegociação. Fonte legada:
`app/models/renegotiation_installment.rb:105-114`.

#### Scenario: Cores distintas por lote
- **GIVEN** uma renegociação com 3 lotes de parcelas
- **WHEN** um quarto lote é criado
- **THEN** ele recebe uma cor distinta das três anteriores

#### Scenario: Espaço de cores esgotado
- **GIVEN** uma renegociação com muitos lotes
- **WHEN** um novo lote é criado
- **THEN** a criação conclui em tempo limitado, reaproveitando cores se necessário
> Nota: corrige comportamento legado (o sorteio rodava em laço de rejeição potencialmente infinito quando o espaço de cores se esgotava)

### Requirement: OPS-197 — Rotinas de correção de dados do domínio
O sistema SHALL se comportar conforme os cenários desta seção.
O legado tem três rotinas manuais de correção usadas após as migrations de 2022. Fonte
legada: `app/models/renegotiation.rb:294-313`; `renegotiation_installment.rb:265-276`.

#### Scenario: Renegociação sem empresa
- **GIVEN** renegociações legadas sem empresa e projetos sem nenhuma empresa cadastrada
- **WHEN** a carga de dados é executada
- **THEN** uma empresa padrão é criada por projeto sem empresa, as renegociações são vinculadas e o relatório lista quantas foram corrigidas

#### Scenario: Recálculo geral pós-carga em lotes
- **GIVEN** todos os pagamentos, parcelas e renegociações migrados
- **WHEN** o recálculo geral é executado
- **THEN** ele processa em lotes, com progresso e falhas visíveis, sem carregar tudo em memória
> Nota: corrige comportamento legado (as rotinas re-salvavam todos os registros sem particionamento, carregando a base inteira em memória)

#### Scenario: Renumeração de pagamentos pós-carga
- **GIVEN** pagamentos migrados
- **WHEN** a renumeração é executada
- **THEN** cada parcela fica com seus pagamentos numerados de 1 a N por ordem de criação
