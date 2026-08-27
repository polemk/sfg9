# Receivables Specification

## Purpose
Registro e precificação dos recebíveis (borderôs) descontados pelas empresas de um
projeto Safegold: cadastro do borderô, tarifas por tipo de movimentação, o motor de
cálculo de custo efetivo total (CET), os catálogos de carteira / tipo de recebível /
tipo de movimentação, e o ciclo de cobrança (`charges`) com os recibos de remuneração
que faturam as operações liquidáveis e estruturadas.

## Requirements

### Requirement: BE-150 — Buscar e listar recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
`GET /pub/console/receivables/search` lista os recebíveis do projeto corrente com
filtros de texto, carteira, portador e período, paginação e ordenação por coluna.
Fonte legada: `app/controllers/pub/receivables_controller.rb:15-49`, `:142-150`, `:167-179`; `config/routes.rb:64`.

#### Scenario: Listagem escopada ao projeto corrente
- **GIVEN** um usuário autenticado cujo projeto corrente é `P1`, e recebíveis existentes em `P1` e em `P2`
- **WHEN** ele chama a busca sem filtros
- **THEN** somente os recebíveis de `P1` são retornados, com o total de registros que satisfazem o filtro

#### Scenario: Busca por id não escapa do projeto
- **GIVEN** um recebível `R` pertencente ao projeto `P2`
- **WHEN** o usuário do projeto `P1` chama a busca informando `receivable_id = R`
- **THEN** o resultado vem vazio e nenhum dado de `P2` é exposto
> Nota: corrige D-16 (comportamento legado: `receivable_id` substituía a query inteira por `ReceivableEntry.where(id: ...)` e perdia o filtro de projeto, vazando recebível de outro projeto)

#### Scenario: Paginação e ordenação por coluna funcionam de verdade
- **GIVEN** 120 recebíveis no projeto corrente
- **WHEN** o usuário pede limite 50, offset 50 e ordenação por `cet` descendente
- **THEN** vêm 50 registros ordenados por CET descendente, e o total informado é 120 (a contagem do filtro, não da página)
> Nota: corrige D-20 (comportamento legado: `where!` descartava `limit`/`offset`, `@total_count` era contado depois de paginar e um `order(date: :desc)` final anulava a ordenação escolhida)

#### Scenario: Período ausente não limita a busca
- **GIVEN** nenhuma data informada em `from`/`to`
- **WHEN** a busca é executada
- **THEN** todos os recebíveis do projeto são considerados, sem cláusula de data
> Nota: corrige comportamento legado das datas-sentinela `DateTime.dinosaurs` / `DateTime.mars` (OPS-158)

#### Scenario: Data inválida é rejeitada com erro de validação
- **GIVEN** `from = "31/02/2026"`
- **WHEN** a busca é executada
- **THEN** a resposta é um erro de validação legível, não um erro interno
> Nota: corrige comportamento legado (`Date.parse` levantava `ArgumentError` e devolvia 500)

### Requirement: BE-151 — Criar recebível
O sistema SHALL se comportar conforme os cenários desta seção.
`POST /pub/console/receivables` cria o borderô e suas tarifas em uma única transação,
com todo o cálculo derivado no servidor. Fonte legada: `app/controllers/pub/receivables_controller.rb:73-98`, `:181-251`.

#### Scenario: Criação com tarifas em uma única transação
- **GIVEN** um formulário válido com 2 tarifas
- **WHEN** o recebível é criado
- **THEN** recebível e as 2 tarifas são persistidos, e os campos calculados (tarifas por bucket, valor líquido, CET) já refletem as 2 tarifas
> Nota: corrige D-11 (comportamento legado: dois `save` em sequência — o primeiro gravava um estado intermediário com `tarifas_* = 0` e disparava o `after_commit` de risco com valor errado)

#### Scenario: Tarifa inválida aborta a criação
- **GIVEN** um formulário cuja segunda tarifa tem `movement_kind_id` inexistente
- **WHEN** a criação é submetida
- **THEN** nada é persistido e a resposta lista o erro da tarifa
> Nota: corrige comportamento legado (o `save` da tarifa não era checado — a tarifa era descartada em silêncio e o total do recebível ficava errado)

#### Scenario: Autoria é sempre do usuário da sessão
- **GIVEN** um payload que informa `user_id` de outro usuário
- **WHEN** o recebível é criado
- **THEN** o registro fica com o usuário autenticado como autor e o `user_id` do payload é ignorado

### Requirement: BE-152 — Atualizar recebível
O sistema SHALL se comportar conforme os cenários desta seção.
`PATCH/PUT /pub/console/receivables/:id` atualiza o borderô, faz upsert das tarifas
enviadas e recalcula os derivados uma única vez. Fonte legada: `app/controllers/pub/receivables_controller.rb:100-127`.

#### Scenario: Upsert de tarifas
- **GIVEN** um recebível com as tarifas `T1` (id conhecido) e `T2`
- **WHEN** a atualização envia `T1` com novo valor e uma tarifa nova sem id
- **THEN** `T1` é atualizada, a nova é criada, e os totais são recalculados uma vez

#### Scenario: Payload sem tarifas preserva as tarifas existentes
- **GIVEN** um recebível com 3 tarifas persistidas
- **WHEN** a atualização é enviada sem a lista de tarifas
- **THEN** as 3 tarifas permanecem e os totais são recalculados a partir delas

### Requirement: BE-153 — Excluir recebível
O sistema SHALL se comportar conforme os cenários desta seção.
`DELETE /pub/console/receivables/:id` remove o borderô, suas tarifas e a operação de
risco vinculada, reportando falha quando a exclusão é barrada. Fonte legada:
`app/controllers/pub/receivables_controller.rb:129-138`.

#### Scenario: Exclusão bem-sucedida
- **GIVEN** um recebível do projeto corrente com 2 tarifas
- **WHEN** o usuário com permissão de escrita o exclui
- **THEN** o recebível, as 2 tarifas e a operação de risco vinculada deixam de existir

#### Scenario: Usuário somente-leitura é barrado no servidor
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** ele chama a exclusão diretamente na API
- **THEN** a requisição é recusada por falta de permissão e o recebível continua existindo
> Nota: corrige D-17 (comportamento legado: nenhum controller checava `user_is_readonly`; o bloqueio existia só na view)

#### Scenario: Exclusão barrada é reportada como erro
- **GIVEN** um recebível cuja exclusão é impedida por vínculo
- **WHEN** a exclusão é tentada
- **THEN** a resposta é um erro com a razão, não uma confirmação de sucesso
> Nota: corrige D-24 (comportamento legado: os dois ramos do ternário respondiam `:ok`, então a falha era invisível)

### Requirement: BE-154 — Rotas REST mortas de recebível
O sistema SHALL se comportar conforme os cenários desta seção.
As actions `index`, `show`, `new`, `edit` e `search_receivable` do controller legado
apontam para templates e associações inexistentes e não são portadas. Fonte legada:
`app/controllers/pub/receivables_controller.rb:7-9`, `:11-13`, `:51-55`, `:57-71`.

#### Scenario: Telas de recebível são servidas pela navegação do console
- **GIVEN** o ai9 em execução
- **WHEN** o usuário abre a área de recebíveis
- **THEN** a lista e o formulário são servidos pelas rotas de navegação do console, e não existem endpoints REST `index`/`show`/`new`/`edit` de recebível
> Nota: DEC-09 — as 5 rotas são comprovadamente mortas no legado (templates ausentes; `current_user.receivables` é associação inexistente) e entram no ledger como `dropped` com evidência

### Requirement: BE-155 — Classificação e soma das tarifas por tipo
O sistema SHALL se comportar conforme os cenários desta seção.
As tarifas do recebível são somadas em quatro buckets — ad valorem, deságio, IOF e
outras — a partir das flags do tipo de movimentação. Fonte legada:
`app/models/receivable_entry.rb:42-45`.

#### Scenario: Soma por bucket
- **GIVEN** tarifas de R$ 100 (ad valorem), R$ 300 (deságio), R$ 50 (IOF) e R$ 20 (sem flag)
- **WHEN** o recebível é gravado
- **THEN** `tarifas_ad_valorem = 100`, `tarifas_desagio = 300`, `tarifas_iof = 50` e `tarifas_outras = 20` (total 470 menos os três buckets)

#### Scenario: Tarifa com mais de uma flag ligada
- **GIVEN** um registro legado cuja tarifa tem `is_advalorem` e `is_iof` ligados ao mesmo tempo
- **WHEN** o recebível é recalculado
- **THEN** o valor é contado nos dois buckets e `tarifas_outras` fica negativa, exatamente como no legado
> Nota: DEC-01/DEC-02 — resultado do legado preservado; o dado inconsistente é reportado pela etapa de introspecção do ETL, não corrigido em silêncio
> AMBIGUIDADE: o `MovementKind` proíbe múltiplas flags (BE-186), mas dados legados podem violar a regra — confirmar se o ai9 deve rejeitar, reclassificar ou apenas reportar esses registros

### Requirement: BE-156 — Valor bruto final
O sistema SHALL se comportar conforme os cenários desta seção.
`vlr_bruto_final = valor_bruto − vlr_bruto_recusado`. Fonte legada: `app/models/receivable_entry.rb:48`.

#### Scenario: Cálculo do bruto final
- **GIVEN** `valor_bruto = 100.000,00` e `vlr_bruto_recusado = 5.000,00`
- **WHEN** o recebível é gravado
- **THEN** `vlr_bruto_final = 95.000,00`

#### Scenario: Recusado maior que o bruto
- **GIVEN** `valor_bruto = 1.000,00` e `vlr_bruto_recusado = 1.500,00`
- **WHEN** o recebível é gravado
- **THEN** `vlr_bruto_final = −500,00` e o valor negativo propaga para as fórmulas seguintes sem validação
> AMBIGUIDADE: o legado não valida `vlr_bruto_recusado <= valor_bruto`; confirmar se o ai9 deve rejeitar o borderô ou seguir aceitando bruto final negativo

### Requirement: BE-157 — Quantidade final de títulos
O sistema SHALL se comportar conforme os cenários desta seção.
`qtd_final = qtd_titulos − qtd_recusada`. Fonte legada: `app/models/receivable_entry.rb:49`.

#### Scenario: Cálculo da quantidade final
- **GIVEN** `qtd_titulos = 40` e `qtd_recusada = 3`
- **WHEN** o recebível é gravado
- **THEN** `qtd_final = 37`

#### Scenario: Quantidade recusada maior que a informada
- **GIVEN** `qtd_titulos = 5` e `qtd_recusada = 8`
- **WHEN** o recebível é gravado
- **THEN** `qtd_final = −3`, sem validação
> AMBIGUIDADE: quantidade final negativa é aceita hoje; confirmar se o ai9 deve validar

### Requirement: BE-158 — Float calculado
O sistema SHALL se comportar conforme os cenários desta seção.
`float_calculado = prz_med_pond_bco − prz_med_pond_emp`. Fonte legada: `app/models/receivable_entry.rb:50`.

#### Scenario: Float positivo
- **GIVEN** `prz_med_pond_bco = 32` e `prz_med_pond_emp = 28`
- **WHEN** o recebível é gravado
- **THEN** `float_calculado = 4`

#### Scenario: Float negativo é preservado
- **GIVEN** `prz_med_pond_bco = 20` e `prz_med_pond_emp = 28`
- **WHEN** o recebível é gravado
- **THEN** `float_calculado = −8`

### Requirement: BE-159 — Diferença de float com piso em zero
O sistema SHALL se comportar conforme os cenários desta seção.
`diferenca_float = max(float_calculado − float_acordado, 0)`. Fonte legada:
`app/models/receivable_entry.rb:51-52`.

#### Scenario: Diferença positiva
- **GIVEN** `float_calculado = 6` e `float_acordado = 2`
- **WHEN** o recebível é gravado
- **THEN** `diferenca_float = 4`

#### Scenario: Diferença negativa é zerada
- **GIVEN** `float_calculado = 2` e `float_acordado = 6`
- **WHEN** o recebível é gravado
- **THEN** `diferenca_float = 0` — a tela nunca mostra float acordado maior que o calculado
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário

### Requirement: BE-160 — Checagem de IOF
O sistema SHALL se comportar conforme os cenários desta seção.
`checagem_iof` estima o IOF devido a partir da base bruta líquida de ad valorem e
deságio, usando alíquota diária e alíquota adicional. Fonte legada:
`app/models/receivable_entry.rb:53-54`.

#### Scenario: Cálculo do IOF esperado
- **GIVEN** `vlr_bruto_final = 100.000,00`, `tarifas_ad_valorem = 500,00`, `tarifas_desagio = 2.000,00` e `prz_med_pond_bco = 30`
- **WHEN** o recebível é gravado
- **THEN** `checagem_iof = round(97.500 × (30 × 0,000041) + 97.500 × 0,0038; 2) = 490,52`

#### Scenario: Alíquota vigente na data da operação
- **GIVEN** uma tabela de alíquotas de IOF com vigências, e um recebível com data de operação anterior à vigência atual
- **WHEN** o recebível é recalculado
- **THEN** as alíquotas usadas são as vigentes na data da operação
> Nota: corrige D-15 (comportamento legado: alíquotas 0,000041 e 0,0038 hardcoded no model, sem vigência — recálculo histórico usava a alíquota de hoje)

#### Scenario: Base de cálculo negativa
- **GIVEN** tarifas de ad valorem + deságio maiores que `vlr_bruto_final`
- **WHEN** o recebível é gravado
- **THEN** o IOF calculado fica negativo, como no legado, e o registro é aceito
> Nota: DEC-02 — resultado do legado preservado para bater os totais na verificação de paridade

### Requirement: BE-161 — Valor total das tarifas
O sistema SHALL se comportar conforme os cenários desta seção.
`valor_total_tarifas` é a soma dos quatro buckets, equivalente à soma bruta de todas as
tarifas do recebível. Fonte legada: `app/models/receivable_entry.rb:55`.

#### Scenario: Soma dos buckets
- **GIVEN** buckets 100 / 300 / 50 / 20
- **WHEN** o recebível é gravado
- **THEN** `valor_total_tarifas = 470,00`

#### Scenario: Recebível sem tarifas
- **GIVEN** um recebível sem nenhuma tarifa
- **WHEN** ele é gravado
- **THEN** `valor_total_tarifas = 0,00` e `valor_liquido = vlr_bruto_final`

### Requirement: BE-162 — Valor líquido
O sistema SHALL se comportar conforme os cenários desta seção.
`valor_liquido = vlr_bruto_final − valor_total_tarifas`, com o zero rejeitado pelo
servidor porque é divisor de todas as fórmulas de CET. Fonte legada:
`app/models/receivable_entry.rb:56`.

#### Scenario: Cálculo do líquido
- **GIVEN** `vlr_bruto_final = 95.000,00` e `valor_total_tarifas = 3.500,00`
- **WHEN** o recebível é gravado
- **THEN** `valor_liquido = 91.500,00`

#### Scenario: Valor líquido zero é rejeitado pelo servidor
- **GIVEN** um payload em que `vlr_bruto_final` iguala `valor_total_tarifas`
- **WHEN** a criação é submetida diretamente na API, sem passar pela tela
- **THEN** a resposta é 422 com erro de validação e nenhum registro com `Infinity`/`NaN` é gravado
> Nota: corrige D-10 (comportamento legado: a guarda de divisão por zero existia só no cliente — o servidor aceitava e gravava `Infinity`/`NaN` nas colunas de CET)

### Requirement: BE-163 — Percentuais das deduções
O sistema SHALL se comportar conforme os cenários desta seção.
Cada dedução (recompra, retenção, fomento, outros) tem seu percentual sobre o valor
líquido. Fonte legada: `app/models/receivable_entry.rb:59-62`.

#### Scenario: Percentual de uma dedução
- **GIVEN** `valor_liquido = 100.000,00` e `recompra = 2.500,00`
- **WHEN** o recebível é gravado
- **THEN** `recompra_percent = 2,5`

#### Scenario: Dedução em branco
- **GIVEN** `fomento` em branco
- **WHEN** o recebível é gravado
- **THEN** `fomento_percent = 0`

#### Scenario: Valor líquido negativo produz percentual negativo
- **GIVEN** `valor_liquido = −10.000,00` e `retencao = 1.000,00`
- **WHEN** o recebível é gravado
- **THEN** `retencao_percent = −10,0`, exatamente como no legado
> Nota: DEC-02 — sequência de operações e resultado do legado preservados

### Requirement: BE-164 — Total das deduções
O sistema SHALL se comportar conforme os cenários desta seção.
`total_deducoes = recompra + retencao + fomento + outros`. Fonte legada:
`app/models/receivable_entry.rb:63`.

#### Scenario: Soma das quatro deduções
- **GIVEN** deduções 1.000 / 500 / 0 / 250
- **WHEN** o recebível é gravado
- **THEN** `total_deducoes = 1.750,00`

#### Scenario: Dedução nula em registro legado
- **GIVEN** um registro migrado com `outros` nulo
- **WHEN** ele é recalculado
- **THEN** o nulo é tratado como zero e o total é calculado sem erro
> Nota: corrige comportamento legado (o código não tratava `nil` e o `+` levantava `NoMethodError` em registros com `NULL`)

### Requirement: BE-165 — Valor líquido recebido
O sistema SHALL se comportar conforme os cenários desta seção.
`vlr_liq_recebido = valor_liquido − recompra − retencao − fomento − outros`. Fonte
legada: `app/models/receivable_entry.rb:65`.

#### Scenario: Líquido recebido
- **GIVEN** `valor_liquido = 91.500,00` e deduções somando 1.750,00
- **WHEN** o recebível é gravado
- **THEN** `vlr_liq_recebido = 89.750,00`

#### Scenario: Deduções maiores que o líquido
- **GIVEN** `valor_liquido = 1.000,00` e deduções somando 1.500,00
- **WHEN** o recebível é gravado
- **THEN** `vlr_liq_recebido = −500,00` e o registro é aceito
> Nota: DEC-02 — resultado do legado preservado

### Requirement: BE-166 — Taxas de desconto nominal na visão do banco
O sistema SHALL se comportar conforme os cenários desta seção.
Três variantes de taxa nominal mensal calculadas sobre o prazo médio ponderado do banco.
Fonte legada: `app/models/receivable_entry.rb:67-69`.

#### Scenario: Variante deságio + ad valorem
- **GIVEN** `tarifas_ad_valorem = 500`, `tarifas_desagio = 2.000`, `vlr_bruto_final = 100.000`, `prz_med_pond_bco = 30` e `valor_liquido = 97.500`
- **WHEN** o recebível é gravado
- **THEN** `taxa_desconto_nominal_desagio_advalorem_bancos = round(100 × ((2.500/100.000)/30) × 30; 2) = 2,5`

#### Scenario: Guarda pelo limiar de um real
- **GIVEN** `tarifas_desagio = 0,80` (menor que 1)
- **WHEN** o recebível é gravado
- **THEN** `taxa_desconto_nominal_desagio_advalorem_bancos` fica nula, como no legado
> Nota: DEC-02 — sequência de guardas do legado preservada
> AMBIGUIDADE: o limiar é `< 1` (um real / uma unidade) e não `<= 0`, então valores entre 0 e 1 são tratados como ausentes; confirmar a regra de negócio pretendida

#### Scenario: Variante sem guarda com prazo zero
- **GIVEN** `prz_med_pond_bco = 0` e a variante `taxa_desconto_nominal_despesas_iof_bancos`, que não tem guarda no legado
- **WHEN** o recebível é submetido
- **THEN** o servidor rejeita o registro por validação em vez de gravar `Infinity`
> Nota: corrige D-10 (comportamento legado: a terceira variante não tinha guarda e gravava `Infinity`/`NaN`)

### Requirement: BE-167 — Custo efetivo por prazo médio do banco, sem IOF
O sistema SHALL se comportar conforme os cenários desta seção.
`custo_efetivo_pz_med_banco_sem_iof` capitaliza a razão bruto/líquido acrescido de IOF
sobre 30 dias divididos pelo prazo do banco mais o float acordado. Fonte legada:
`app/models/receivable_entry.rb:71-74`.

#### Scenario: Cálculo do CET sem IOF
- **GIVEN** `vlr_bruto_final = 100.000`, `valor_liquido = 96.000`, `tarifas_iof = 400`, `prz_med_pond_bco = 30` e `float_acordado = 0`
- **WHEN** o recebível é gravado
- **THEN** `custo_efetivo_pz_med_banco_sem_iof = round(((1 + (100.000 − 96.400)/96.400) ^ (30/30) − 1) × 100; 4) = 3,7344`

#### Scenario: Guarda usa o prazo da empresa
- **GIVEN** `prz_med_pond_emp = 0` e `prz_med_pond_bco = 30`
- **WHEN** o recebível é recalculado
- **THEN** `custo_efetivo_pz_med_banco_sem_iof = 0`, porque a guarda do legado olha o prazo da **empresa** numa fórmula do **banco**
> Nota: DEC-02 — a sequência de guardas do legado é replicada para os totais baterem
> AMBIGUIDADE: a guarda parece copy/paste (deveria olhar `prz_med_pond_bco`); confirmar antes de trocar, porque muda o valor exibido

### Requirement: BE-168 — Custo efetivo por prazo médio do banco com IOF
O sistema SHALL se comportar conforme os cenários desta seção.
`custo_efetivo_pz_med_banco`, exibido na lista como "CET PM BCO". Fonte legada:
`app/models/receivable_entry.rb:76-78`.

#### Scenario: Cálculo do CET PM BCO
- **GIVEN** `vlr_bruto_final = 100.000`, `valor_liquido = 96.000`, `prz_med_pond_bco = 30`, `float_acordado = 0`
- **WHEN** o recebível é gravado
- **THEN** `custo_efetivo_pz_med_banco = round(((1 + 4.000/96.000) ^ 1 − 1) × 100; 4) = 4,1667`

#### Scenario: Prazo do banco zero
- **GIVEN** `prz_med_pond_bco = 0`
- **WHEN** o recebível é recalculado
- **THEN** `custo_efetivo_pz_med_banco = 0`
> Nota: DEC-02 — guarda do legado preservada

### Requirement: BE-169 — Taxas de desconto nominal na visão da empresa
O sistema SHALL se comportar conforme os cenários desta seção.
As três variantes de BE-166 recalculadas com `prz_med_pond_emp`. Fonte legada:
`app/models/receivable_entry.rb:81-83`.

#### Scenario: Variante despesas na visão da empresa
- **GIVEN** `valor_total_tarifas = 3.500`, `tarifas_iof = 400`, `vlr_bruto_final = 100.000`, `prz_med_pond_emp = 30`, `valor_liquido = 96.500`
- **WHEN** o recebível é gravado
- **THEN** `taxa_desconto_nominal_despesas_emp = round(100 × ((3.100/100.000)/30) × 30; 2) = 3,1`

#### Scenario: Mesmas guardas assimétricas da visão banco
- **GIVEN** `tarifas_iof = 0,50`
- **WHEN** o recebível é gravado
- **THEN** as duas primeiras variantes ficam nulas pela guarda `< 1` e a terceira é barrada por validação quando o prazo é zero
> Nota: DEC-02 — guardas do legado preservadas
> AMBIGUIDADE: mesma dúvida de BE-166 sobre o limiar `< 1`

### Requirement: BE-170 — Custo efetivo por prazo médio da empresa, sem IOF
O sistema SHALL se comportar conforme os cenários desta seção.
`custo_efetivo_pz_med_emp_sem_iof`. Fonte legada: `app/models/receivable_entry.rb:85-87`.

#### Scenario: Cálculo do CET da empresa sem IOF
- **GIVEN** `vlr_bruto_final = 100.000`, `valor_liquido = 96.000`, `tarifas_iof = 400`, `prz_med_pond_emp = 30`, `float_acordado = 0`
- **WHEN** o recebível é gravado
- **THEN** `custo_efetivo_pz_med_emp_sem_iof = 3,7344`

#### Scenario: Prazo da empresa zero
- **GIVEN** `prz_med_pond_emp = 0` em um registro legado sendo recalculado
- **WHEN** o recálculo roda
- **THEN** o campo é gravado como `0`
> Nota: DEC-02 — guarda do legado preservada

### Requirement: BE-171 — Custo efetivo por prazo médio da empresa com IOF
O sistema SHALL se comportar conforme os cenários desta seção.
`custo_efetivo_pz_med_emp`, a coluna "CET PM EMP" e a chave de ordenação `cet`. Fonte
legada: `app/models/receivable_entry.rb:90-92`.

#### Scenario: Cálculo do CET PM EMP
- **GIVEN** `vlr_bruto_final = 100.000`, `valor_liquido = 96.000`, `prz_med_pond_emp = 30`, `float_acordado = 0`
- **WHEN** o recebível é gravado
- **THEN** `custo_efetivo_pz_med_emp = 4,1667` (4 casas decimais)

#### Scenario: Float acordado alonga o prazo
- **GIVEN** os mesmos valores com `float_acordado = 30`
- **WHEN** o recebível é gravado
- **THEN** o expoente passa a `30/60` e o CET cai para `2,0605`

### Requirement: BE-172 — Custo efetivo sem float
O sistema SHALL se comportar conforme os cenários desta seção.
`custo_efetivo_sem_float`, coluna "CET S/ Float" e chave de ordenação `cetsf`. Fonte
legada: `app/models/receivable_entry.rb:95-97`.

#### Scenario: Cálculo do CET sem float
- **GIVEN** `vlr_bruto_final = 100.000`, `valor_liquido = 96.000`, `prz_med_pond_emp = 30`
- **WHEN** o recebível é gravado
- **THEN** `custo_efetivo_sem_float = 4,1667`

#### Scenario: Prazo médio da empresa zero é barrado antes do cálculo
- **GIVEN** um payload com `prz_med_pond_emp = 0`
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 pela validação `greater_than: 0` e nenhum cálculo é executado
> Nota: corrige D-10 (comportamento legado: o `before_validation` calculava antes da validação rodar, então a divisão por zero acontecia antes de o registro ser barrado)

### Requirement: BE-173 — Custo efetivo com float total
O sistema SHALL se comportar conforme os cenários desta seção.
`custo_efetivo_com_float_total`, mesma base de BE-171 porém arredondado em 2 casas.
Fonte legada: `app/models/receivable_entry.rb:99`.

#### Scenario: Cálculo com arredondamento em 2 casas
- **GIVEN** `vlr_bruto_final = 100.000`, `valor_liquido = 96.000`, `prz_med_pond_emp = 30`, `float_acordado = 0`
- **WHEN** o recebível é gravado
- **THEN** `custo_efetivo_com_float_total = 4,17` (2 casas), enquanto `custo_efetivo_pz_med_emp` fica `4,1667`
> Nota: DEC-02 — pontos de arredondamento do legado preservados
> AMBIGUIDADE: por que esta coluna arredonda em 2 casas e BE-171 em 4, se a base é a mesma?

#### Scenario: Sem guarda de zero
- **GIVEN** `prz_med_pond_emp + float_acordado = 0` em um registro legado
- **WHEN** o recálculo é executado pelo ETL
- **THEN** o registro é reportado como inválido no relatório de introspecção, e não gravado com `Infinity`
> Nota: corrige D-10 (comportamento legado: esta fórmula não tinha guarda nenhuma)

### Requirement: BE-174 — Custo efetivo com float, sem IOF
O sistema SHALL se comportar conforme os cenários desta seção.
`custo_efetivo_com_float_sem_iof`, nulo quando não há IOF relevante. Fonte legada:
`app/models/receivable_entry.rb:101`.

#### Scenario: Recebível com IOF
- **GIVEN** `vlr_bruto_final = 100.000`, `valor_liquido = 96.000`, `tarifas_iof = 400`, `prz_med_pond_emp = 30`, `float_acordado = 0`
- **WHEN** o recebível é gravado
- **THEN** `custo_efetivo_com_float_sem_iof = 3,73` (2 casas)

#### Scenario: Recebível sem IOF fica nulo
- **GIVEN** `tarifas_iof = 0`
- **WHEN** o recebível é gravado
- **THEN** `custo_efetivo_com_float_sem_iof` fica nulo — a coluna é sempre vazia para borderôs sem IOF
> Nota: DEC-02 — guarda `< 1` do legado preservada

### Requirement: BE-175 — Multiplicadores de prazo médio
O sistema SHALL se comportar conforme os cenários desta seção.
`multiplicador_pm_empresa` e `multiplicador_pm_float` alimentam os relatórios de prazo
médio ponderado da carteira. Fonte legada: `app/models/receivable_entry.rb:104-105`.

#### Scenario: Cálculo dos multiplicadores
- **GIVEN** `vlr_bruto_final = 100.000,00`, `prz_med_pond_emp = 28,5` e `prz_med_pond_bco = 31,2`
- **WHEN** o recebível é gravado
- **THEN** `multiplicador_pm_empresa = 2.850.000,00` e `multiplicador_pm_float = 3.120.000,00`, truncados em 2 casas

#### Scenario: Prazo da empresa em branco
- **GIVEN** `prz_med_pond_emp` em branco
- **WHEN** o recebível é gravado
- **THEN** `multiplicador_pm_empresa` fica nulo e `multiplicador_pm_float` continua sendo calculado

### Requirement: BE-176 — Valor líquido correto a partir do CET acordado
O sistema SHALL se comportar conforme os cenários desta seção.
`calc_valor_liq_correto` traz o bruto final a valor presente usando a taxa diária
equivalente ao CET acordado. Fonte legada: `app/models/receivable_entry.rb:107-112`.

#### Scenario: Valor presente pelo CET acordado
- **GIVEN** `cst_efetivo_acordado = 4`, `vlr_bruto_final = 100.000,00`, `prz_med_pond_emp = 30` e `float_acordado = 0`
- **WHEN** o recebível é gravado
- **THEN** `calc_valor_liq_correto = round(100.000 − (((1,04 ^ 0,0333…) − 1) × 100.000) × 30; 2) = 96.078,54`
> Nota: DEC-02 — expoente literal `0.0333…` e aproximação linear do legado replicados para os totais baterem
> AMBIGUIDADE: D-14 — a fórmula é aproximação linear (juros simples sobre a taxa diária equivalente), não desconto composto exato, e alimenta o `status` (BE-178); confirmar se é proposital

#### Scenario: CET acordado negativo
- **GIVEN** `cst_efetivo_acordado = −5`
- **WHEN** o recebível é submetido
- **THEN** o servidor rejeita o valor por validação, em vez de gravar `NaN` na coluna
> Nota: corrige D-10 (comportamento legado: raiz de número negativo produzia `NaN` gravado no banco)

### Requirement: BE-177 — Diferença entre o líquido apurado e o líquido correto
O sistema SHALL se comportar conforme os cenários desta seção.
`dif_calc_vlr_liq = round(valor_liquido − calc_valor_liq_correto, 2)`. Fonte legada:
`app/models/receivable_entry.rb:114`.

#### Scenario: Diferença positiva
- **GIVEN** `valor_liquido = 96.500,00` e `calc_valor_liq_correto = 96.078,54`
- **WHEN** o recebível é gravado
- **THEN** `dif_calc_vlr_liq = 421,46`

#### Scenario: Diferença negativa
- **GIVEN** `valor_liquido = 95.000,00` e `calc_valor_liq_correto = 96.078,54`
- **WHEN** o recebível é gravado
- **THEN** `dif_calc_vlr_liq = −1.078,54`

### Requirement: BE-178 — Status do recebível
O sistema SHALL se comportar conforme os cenários desta seção.
O recebível tem exatamente dois estados derivados da diferença de líquido: "OK" e
"Diferença". Fonte legada: `app/models/receivable_entry.rb:115`; `app/models/entry.rb:10-12`.

#### Scenario: Diferença negativa marca "Diferença"
- **GIVEN** `dif_calc_vlr_liq = −1.078,54`
- **WHEN** o recebível é gravado
- **THEN** `status = "Diferença"`

#### Scenario: Diferença exatamente zero é OK
- **GIVEN** `dif_calc_vlr_liq = 0`
- **WHEN** o recebível é gravado
- **THEN** `status = "OK"`
> AMBIGUIDADE: D-19 — não existe no legado nenhum estado de baixa, liquidação ou vencimento do recebível (`MovementKind.is_liquidation` só classifica a tarifa); confirmar se a ausência é real ou se falta uma funcionalidade inteira

### Requirement: BE-179 — Checagem da taxa nominal sem float
O sistema SHALL se comportar conforme os cenários desta seção.
`nominal_tax_check` recalcula a taxa nominal mensal implícita no deságio. Fonte legada:
`app/models/receivable_entry.rb:117`.

#### Scenario: Cálculo da checagem
- **GIVEN** `tarifas_desagio = 2.000,00`, `vlr_bruto_final = 100.000,00` e `prz_med_pond_emp = 30`
- **WHEN** o recebível é gravado
- **THEN** `nominal_tax_check = round(100 × (2.000 / (100.000 × 1)); 2) = 2,0`

#### Scenario: Denominador zero é barrado no servidor
- **GIVEN** `vlr_bruto_final = 0`
- **WHEN** o recebível é submetido
- **THEN** a resposta é 422 e nada é gravado
> Nota: corrige D-10 (comportamento legado: divisão por zero sem guarda no servidor)

### Requirement: BE-180 — Checagem da taxa nominal com float
O sistema SHALL se comportar conforme os cenários desta seção.
`nominal_tax_check_with_float` repete BE-179 somando o float acordado ao prazo. Fonte
legada: `app/models/receivable_entry.rb:118`.

#### Scenario: Cálculo com float
- **GIVEN** `tarifas_desagio = 2.000,00`, `vlr_bruto_final = 100.000,00`, `prz_med_pond_emp = 30` e `float_acordado = 30`
- **WHEN** o recebível é gravado
- **THEN** `nominal_tax_check_with_float = round(100 × (2.000 / (100.000 × 2)); 2) = 1,0`

#### Scenario: Taxa nominal informada divergente da checagem
- **GIVEN** `nominal_tax = 3,5` informada pelo usuário e checagens calculadas em 2,0 e 1,0
- **WHEN** o recebível é gravado
- **THEN** o recebível é aceito e as três taxas ficam visíveis para comparação; o servidor não bloqueia a divergência
> AMBIGUIDADE: `nominal_tax` nunca é validada contra as checagens no servidor; confirmar se a divergência deve virar erro, alerta ou continuar apenas informativa

### Requirement: BE-181 — Validações do recebível e limite de risco cadastrado
O sistema SHALL se comportar conforme os cenários desta seção.
Campos obrigatórios, prazos positivos e a exigência de um controle de risco ativo quando
o borderô é associado a um subtipo de operação. Fonte legada:
`app/models/receivable_entry.rb:10-23`, `:25-36`.

#### Scenario: Campos obrigatórios ausentes
- **GIVEN** um payload sem `carrier_id` e sem `wallet_id`
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 listando os dois campos, com mensagens em pt-BR

#### Scenario: Subtipo de risco sem limite cadastrado
- **GIVEN** um `risk_operation_subtype_id` informado e nenhum `RiskControl` ativo para a combinação empresa + portador + tipo de operação + projeto
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 com a mensagem "Não possui limite cadastrado"

#### Scenario: Data de operação em passado remoto ou futuro
- **GIVEN** `date` no ano 1900 ou no ano 2100
- **WHEN** a criação é submetida
- **THEN** o recebível é aceito — não existe validação de janela de data no legado
> AMBIGUIDADE: o legado também não valida `valor_bruto > 0` nem valor mínimo; confirmar se o ai9 deve introduzir essas validações

### Requirement: BE-182 — Derivações automáticas e defaults
O sistema SHALL se comportar conforme os cenários desta seção.
O tipo de operação de risco é derivado do subtipo, o carimbo `has_safegold_management` é
copiado do projeto e as quantidades recusadas recebem zero. Fonte legada:
`app/models/receivable_entry.rb:38-40`, `:121`, `:226-229`.

#### Scenario: Tipo derivado do subtipo
- **GIVEN** um subtipo de operação de risco cujo tipo é `T`
- **WHEN** o recebível é gravado
- **THEN** `risk_operation_type_id = T`, sem o usuário informar o tipo

#### Scenario: Carimbo do projeto
- **GIVEN** um projeto com `has_safegold_management` ligado
- **WHEN** o recebível é criado
- **THEN** o recebível guarda o carimbo do projeto no momento da criação

#### Scenario: Registro legado com quantidades nulas
- **GIVEN** um registro migrado com `qtd_recusada` e `vlr_bruto_recusado` nulos
- **WHEN** ele é carregado
- **THEN** os dois passam a valer zero para efeito de cálculo, e a persistência do zero ocorre na próxima gravação

### Requirement: BE-183 — Integração automática com o controle de risco
O sistema SHALL se comportar conforme os cenários desta seção.
Após gravar, um recebível associado a subtipo de operação gera movimento ou operação de
risco correspondente, com o valor líquido já definitivo. Fonte legada:
`app/models/receivable_entry.rb:124-175`.

#### Scenario: Subtipo com pré-faturamento gera movimento de liberação
- **GIVEN** um subtipo cujo tipo de operação tem pré-faturamento, e uma operação de risco estática para projeto + empresa + portador + tipo + subtipo
- **WHEN** o recebível é gravado com `valor_liquido = 91.500,00`
- **THEN** é criado um `RiskMovement` de liberação de recurso com `movement_value = 91.500,00`, `balance = 0` e a observação "Gerado automaticamente a partir de recebível"

#### Scenario: Subtipo sem pré-faturamento cria operação de risco com o valor final
- **GIVEN** um subtipo sem pré-faturamento e um recebível novo com 2 tarifas
- **WHEN** o recebível é criado
- **THEN** é criada uma única `RiskOperation` com `operation_value` igual ao valor líquido **já com as tarifas descontadas**, `due_date = data_credito`, `agreed_rate = nominal_tax` e `contract_number = nro_bordero`
> Nota: corrige D-11 (comportamento legado: o `after_commit` disparava duas vezes — a operação era criada no primeiro commit com o líquido ainda sem tarifas, e o segundo commit só atualizava tipo/subtipo, deixando a operação de risco com valor bruto)

#### Scenario: Operação estática ausente é reportada
- **GIVEN** um subtipo com pré-faturamento e nenhuma operação estática correspondente
- **WHEN** o recebível é gravado
- **THEN** a gravação falha com erro explicando a ausência da operação estática
> Nota: corrige comportamento legado (o callback não fazia nada em silêncio, e o recebível ficava sem contrapartida no risco)

### Requirement: BE-184 — Tarifa do recebível: denormalização e exclusão
O sistema SHALL se comportar conforme os cenários desta seção.
A tarifa copia título e flags do tipo de movimentação e, ao ser removida, dispara o
recálculo do recebível no servidor. Fonte legada: `app/models/receivable_tax.rb:1-17`;
`app/controllers/pub/receivable_taxes_controller.rb:15-24`, `:42-44`.

#### Scenario: Título e flags copiados do tipo de movimentação
- **GIVEN** um `MovementKind` "Deságio" com `is_desagio` ligado
- **WHEN** uma tarifa desse tipo é criada
- **THEN** a tarifa guarda `title = "Deságio"` e `is_desagio` ligado

#### Scenario: Exclusão de tarifa recalcula o recebível no servidor
- **GIVEN** um recebível com 3 tarifas e `valor_total_tarifas = 3.500,00`
- **WHEN** uma tarifa de R$ 500,00 é excluída
- **THEN** o servidor recalcula e devolve o recebível com `valor_total_tarifas = 3.000,00` e todos os CETs atualizados, sem depender de nenhuma chamada extra do cliente
> Nota: corrige D-09 (comportamento legado: o `destroy` só removia o registro e o recálculo dependia do front chamar `update_and_save()`)

#### Scenario: Tarifa de valor zero
- **GIVEN** uma tarifa com valor 0,00
- **WHEN** ela é gravada
- **THEN** é aceita e não altera nenhum bucket

### Requirement: BE-185 — Carteiras e tipos de recebível: CRUD e busca
O sistema SHALL se comportar conforme os cenários desta seção.
Dois catálogos gêmeos com título único, chave de integração e flag de atividade. Fonte
legada: `app/controllers/pub/wallets_controller.rb:1-127`;
`app/controllers/pub/receivable_kinds_controller.rb:1-128`.

#### Scenario: Criação com chave de integração derivada do título
- **GIVEN** o título "Carteira ABC" e a chave de integração em branco
- **WHEN** a carteira é criada
- **THEN** a chave gravada é `carteira_abc` (transliterada, minúscula, espaços por `_`)

#### Scenario: Título duplicado é rejeitado com resposta consistente
- **GIVEN** uma carteira "Desconto" já existente
- **WHEN** outra carteira "Desconto" é criada
- **THEN** a resposta é 422 com o erro de unicidade — para carteiras **e** para tipos de recebível
> Nota: corrige comportamento legado (`receivable_kinds#create` respondia 200 em caso de erro, ao contrário de `wallets#create`)

#### Scenario: Exclusão bloqueada por uso
- **GIVEN** uma carteira referenciada por recebíveis
- **WHEN** a exclusão é tentada
- **THEN** a resposta é um erro explicando o vínculo e a carteira permanece

#### Scenario: Ordenação por chave desconhecida
- **GIVEN** uma busca com chave de ordenação inexistente
- **WHEN** a busca é executada
- **THEN** a chave é ignorada e a lista volta na ordenação padrão
> Nota: corrige comportamento legado (chave desconhecida produzia `nil + " "` e 500)

#### Scenario: Catálogo desativado
- **GIVEN** uma carteira com `is_active` desligado
- **WHEN** o formulário de recebível é aberto
- **THEN** ela continua selecionável, como no legado
> AMBIGUIDADE: D-19 — `is_active` é gravado e exibido mas nunca aplicado em nenhum filtro ou select; confirmar se o ai9 deve passar a esconder catálogos desativados

### Requirement: BE-186 — Tipos de movimentação: CRUD, busca e classificador único
O sistema SHALL se comportar conforme os cenários desta seção.
O catálogo de tarifas classifica cada tipo como ad valorem, deságio, IOF ou liquidação,
com no máximo uma classificação por tipo. Fonte legada:
`app/controllers/pub/movement_kinds_controller.rb:1-135`; `app/models/movement_kind.rb:1-79`.

#### Scenario: Classificação única
- **GIVEN** um tipo de movimentação com `is_advalorem` e `is_iof` marcados
- **WHEN** ele é gravado
- **THEN** a resposta é 422 com mensagem em pt-BR explicando que só uma classificação é permitida
> Nota: corrige comportamento legado (o erro era adicionado com a chave literal "Múltiplos tipos" e chegava cru na tela)

#### Scenario: Coluna de classificação nula em registro legado
- **GIVEN** um registro migrado com `is_desagio` nulo
- **WHEN** ele é validado
- **THEN** o nulo conta como zero e a validação roda sem erro
> Nota: corrige comportamento legado (a soma sobre `NULL` levantava `NoMethodError`)

#### Scenario: Somente tipos de operação aparecem no formulário de tarifas
- **GIVEN** tipos com `is_operation` ligado e desligado
- **WHEN** o formulário de tarifas do recebível é montado
- **THEN** apenas os tipos com `is_operation` ligado são oferecidos
> AMBIGUIDADE: D-74 — `is_title` e `is_liquidation` não têm consumidor visível em nenhuma tela; confirmar se são campos vivos ou resíduo

### Requirement: BE-187 — Cobranças: CRUD e busca
O sistema SHALL se comportar conforme os cenários desta seção.
`GET /pub/console/charges/search` e o CRUD de `charges` gerenciam os pacotes de cobrança
do projeto, com estados "Edição", "Disponível" e "Faturado". Fonte legada:
`app/controllers/pub/charges_controller.rb:6-21`, `:52-106`, `:119-134`; `app/models/charge.rb:1-32`.

#### Scenario: Busca por mês e ano
- **GIVEN** cobranças em vários meses do projeto corrente
- **WHEN** a busca informa mês 3 e ano 2026
- **THEN** somente as cobranças com data em março de 2026 são retornadas

#### Scenario: Paginação da lista de cobranças funciona
- **GIVEN** 200 cobranças no projeto
- **WHEN** a busca pede limite 50 e offset 0
- **THEN** vêm 50 cobranças e o total informado é 200
> Nota: corrige D-20 (comportamento legado: `fetch_loq` nunca era chamado neste controller, então `limit(nil).offset(nil)` trazia todas as cobranças)

#### Scenario: Estado inválido é rejeitado
- **GIVEN** um payload com `state = "Qualquer coisa"`
- **WHEN** a cobrança é criada pela API
- **THEN** a resposta é 422 — só os três estados conhecidos são aceitos
> Nota: corrige comportamento legado (`state` era string livre, aceita sem validação via API)

#### Scenario: Exclusão bloqueada por recibos
- **GIVEN** uma cobrança com recibos vinculados
- **WHEN** a exclusão é tentada
- **THEN** a resposta é um erro de negócio legível, não um erro interno
> Nota: corrige comportamento legado (o `restrict_with_error` voltava como JSON 500)

### Requirement: BE-188 — Recibo: geração a partir da operação e fórmula do valor
O sistema SHALL se comportar conforme os cenários desta seção.
O recibo materializa a remuneração devida por uma operação liquidável (LIQ) ou
estruturada (EST), com `value = operation_value × (fee / 100)`. Fonte legada:
`app/models/receipt.rb:8-14`, `:23-35`, `:41-70`; `app/models/remuneration.rb:25-46`.

#### Scenario: Cálculo do valor do recibo
- **GIVEN** uma operação de risco com `operation_value = 100.000,00` e uma remuneração do projeto com `fee = 1,5`
- **WHEN** o recibo é gerado
- **THEN** `value = 1.500,00`, `kind = "LIQ"`, `date = operation.issue_date`, `operation_title = operation.title` e `temp_id = "RCP-{project_id}-LIQ-{remuneration_id}-{operation_id}"`
> Nota: DEC-02 — a multiplicação `decimal × float` e o truncamento para `decimal(15,2)` do legado são replicados para os totais baterem
> AMBIGUIDADE: D-72 — a fórmula é percentual flat: nem `agreed_rate`, nem `issue_date`/`due_date`, nem `balance` entram no cálculo; confirmar com o negócio qual é a fórmula pretendida

#### Scenario: Operação estruturada
- **GIVEN** uma operação estruturada com remuneração cadastrada
- **WHEN** o recibo é gerado
- **THEN** `kind = "EST"`

#### Scenario: Tipo de operação desconhecido
- **GIVEN** uma remuneração cujo tipo de operação não é de risco nem estruturada
- **WHEN** o recibo é gerado
- **THEN** a geração falha com erro explicando o tipo inválido
> Nota: corrige comportamento legado (o `kind` virava `"???"`, passava a validação e o recibo ficava fora da soma de BE-189 mas dentro da contagem)

#### Scenario: Operação já com recibo ou sem remuneração cadastrada
- **GIVEN** uma operação que já tem recibo, ou um tipo de operação sem remuneração no projeto
- **WHEN** a geração em lote é executada
- **THEN** a operação é reportada como não processada e as demais seguem normalmente
> Nota: corrige comportamento legado (`fetch` levantava `ArgumentError` não tratado em `bulk_update_receipts` e derrubava a requisição inteira)

### Requirement: BE-189 — Consolidação da cobrança e atualização em lote de recibos
O sistema SHALL se comportar conforme os cenários desta seção.
`POST /pub/console/charges/:id/receipts` cria os recibos selecionados, remove os
desmarcados e recalcula os totais da cobrança em uma transação. Fonte legada:
`app/models/charge.rb:48-63`; `app/controllers/pub/charges_controller.rb:29-50`.

#### Scenario: Consolidação dos totais
- **GIVEN** uma cobrança com 2 recibos LIQ (R$ 1.500 e R$ 800, operações de 100.000 e 60.000) e 1 recibo EST (R$ 400, operação de 40.000)
- **WHEN** `calc!` é executado
- **THEN** `value = 2.700,00`, `risk_operations_value = 160.000,00`, `structured_operations_value = 40.000,00`, `total_operations_value = 200.000,00`, `receipts_count = 3`, `risk_operations_count = 2`, `structured_operations_count = 1`

#### Scenario: Cobrança faturada não aceita alteração de recibos
- **GIVEN** uma cobrança no estado "Faturado"
- **WHEN** a atualização em lote de recibos é chamada diretamente na API
- **THEN** a requisição é recusada e os recibos permanecem intactos
> Nota: corrige D-18 (comportamento legado: o bloqueio existia só na UI e a API alterava recibos de cobrança já faturada)

#### Scenario: Falha no meio do lote não deixa estado parcial
- **GIVEN** um lote de 5 candidatos em que o terceiro falha
- **WHEN** o lote é processado
- **THEN** nenhum recibo é criado, a cobrança mantém os totais anteriores e o erro é reportado
> Nota: corrige comportamento legado (sem transação: os recibos anteriores ficavam gravados e `calc!` nem rodava)

### Requirement: FE-150 — Tela de lista de recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Recebíveis" do console lista os borderôs do projeto com 9 colunas de dados, todas
ordenáveis. Fonte legada: `app/views/pub/console/parts/receivables/_body.html.erb:1-133`.

#### Scenario: Colunas da lista
- **GIVEN** recebíveis cadastrados no projeto corrente
- **WHEN** o usuário abre a área de recebíveis
- **THEN** a tela mostra o título "Recebíveis" e as colunas Portador, Carteira, Data, Bruto, Custo Financeiro, Vlr Liquido, Títulos, PMR, CET S/ Float e CET PM EMP

#### Scenario: Ordenação por qualquer coluna de dados
- **GIVEN** a lista carregada
- **WHEN** o usuário clica no cabeçalho de qualquer uma das 9 colunas
- **THEN** a lista é reordenada por aquela coluna

### Requirement: FE-151 — Estado de carregamento da lista
O sistema SHALL se comportar conforme os cenários desta seção.
A lista sinaliza o carregamento inicial e recarrega em silêncio quando disparada por
filtro ou ordenação. Fonte legada: `.../receivables/_body.js.erb:298`.

#### Scenario: Carregamento inicial
- **GIVEN** a área de recebíveis sendo aberta
- **WHEN** a busca ainda não respondeu
- **THEN** a tela exibe o indicador de carregamento "Buscando .."

#### Scenario: Recarga por filtro não pisca a tela
- **GIVEN** a lista já carregada
- **WHEN** o usuário troca um filtro
- **THEN** a lista é atualizada sem exibir o indicador de carregamento

### Requirement: FE-152 — Estado vazio da lista sem busca
O sistema SHALL se comportar conforme os cenários desta seção.
Quando a coleção volta vazia sem termo de busca, a tela mostra o estado vazio.
Fonte legada: `.../receivables/list/body.js.erb:16-20`.

#### Scenario: Projeto sem recebíveis
- **GIVEN** um projeto sem nenhum recebível
- **WHEN** a lista é carregada
- **THEN** a tela mostra "Nenhum resultado encontrado" no lugar da tabela

#### Scenario: Filtro que não casa com nada
- **GIVEN** um filtro de carteira sem recebíveis correspondentes
- **WHEN** a lista é recarregada
- **THEN** o mesmo estado vazio é exibido

### Requirement: FE-153 — Estado vazio com termo de busca
O sistema SHALL se comportar conforme os cenários desta seção.
Com termo de busca ativo, o estado vazio ecoa o termo pesquisado. Fonte legada:
`.../receivables/_body.js.erb:283-285`.

#### Scenario: Busca sem resultado
- **GIVEN** o termo "Banco XPTO" digitado no campo de busca
- **WHEN** nenhum recebível casa
- **THEN** a tela mostra "Não encontramos nenhum resultado para a busca **Banco XPTO**.."

#### Scenario: Limpar o termo volta ao estado vazio genérico
- **GIVEN** o estado vazio com termo
- **WHEN** o usuário limpa o campo de busca
- **THEN** a mensagem volta a ser "Nenhum resultado encontrado"

### Requirement: FE-154 — Estado de erro da lista de recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
Falhas de exclusão e falhas de carregamento da lista são comunicadas ao usuário.
Fonte legada: `.../receivables/list/_widget.js.erb:121-123`.

#### Scenario: Falha ao excluir
- **GIVEN** uma exclusão que falha no servidor
- **WHEN** a resposta chega
- **THEN** a tela mostra "Houve um problema, tente novamente" e a linha permanece na lista

#### Scenario: Falha ao carregar a lista
- **GIVEN** a busca de recebíveis retornando erro
- **WHEN** a resposta chega
- **THEN** a tela mostra um estado de erro com opção de tentar novamente
> Nota: corrige comportamento legado (falha no `search` deixava a tela como estava, sem qualquer sinal ao usuário)

### Requirement: FE-155 — Busca textual de recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
O campo de busca filtra a lista com debounce e escopo explicitado ao usuário. Fonte
legada: `.../receivables/_body.js.erb:224-237`.

#### Scenario: Debounce da digitação
- **GIVEN** o usuário digitando no campo de busca
- **WHEN** ele para de digitar por 300 ms
- **THEN** uma única busca é disparada com o termo digitado

#### Scenario: Entrada só com espaços é ignorada
- **GIVEN** o campo contendo apenas espaços
- **WHEN** o debounce expira
- **THEN** nenhuma busca é disparada

#### Scenario: Escopo da busca é comunicado
- **GIVEN** a busca textual, que casa apenas o título do portador
- **WHEN** o campo é exibido
- **THEN** o rótulo indica que a busca é por portador
> Nota: corrige comportamento legado (rótulo genérico "Procurar" sem indicar que só o título do portador é pesquisado)

### Requirement: FE-156 — Filtro de período por intervalo de datas
O sistema SHALL se comportar conforme os cenários desta seção.
O botão "Periodo" abre um seletor de intervalo em pt-BR e rotula o intervalo escolhido.
Fonte legada: `.../receivables/_body.js.erb:131-200`.

#### Scenario: Seleção de intervalo
- **GIVEN** o seletor aberto
- **WHEN** o usuário escolhe 01/03/2026 e 31/03/2026
- **THEN** o rótulo mostra "De 01/03/2026 a 31/03/2026" e a lista é filtrada por esse intervalo

#### Scenario: Seleção de um dia só
- **GIVEN** o seletor aberto
- **WHEN** o usuário escolhe apenas a data inicial
- **THEN** a data final recebe o mesmo dia e o filtro cobre um único dia

#### Scenario: Intervalo que cruza o ano
- **GIVEN** o intervalo 20/12/2025 a 10/01/2026
- **WHEN** o rótulo é montado
- **THEN** o rótulo mostra os dois anos corretos
> Nota: corrige comportamento legado (o rótulo lia `from.getYear()` no lugar de `to.getYear()` e exibia o ano errado no fim do intervalo)

### Requirement: FE-157 — Filtro por carteira
O sistema SHALL se comportar conforme os cenários desta seção.
Um select filtra a lista por carteira. Fonte legada: `.../receivables/_body.js.erb:202-211`.

#### Scenario: Filtrar por carteira
- **GIVEN** o select "Filtrar por carteira" com as carteiras ordenadas por título
- **WHEN** o usuário escolhe uma carteira
- **THEN** a lista passa a mostrar só os recebíveis daquela carteira

#### Scenario: Carteiras inativas no select
- **GIVEN** uma carteira com `is_active` desligado
- **WHEN** o select é montado
- **THEN** ela aparece na lista de opções, como no legado
> AMBIGUIDADE: mesma questão de BE-185 — `is_active` nunca é aplicado; confirmar se o filtro deve passar a esconder catálogos desativados

### Requirement: FE-158 — Filtro por portador
O sistema SHALL se comportar conforme os cenários desta seção.
Um select oferece os portadores do projeto corrente, dentro do bloco de filtros
recolhível. Fonte legada: `.../receivables/_body.js.erb:213-222`.

#### Scenario: Filtrar por portador
- **GIVEN** o bloco de filtros aberto pelo botão "Filtros"
- **WHEN** o usuário escolhe um portador do projeto
- **THEN** a lista mostra só os recebíveis daquele portador

#### Scenario: Portadores de outro projeto não aparecem
- **GIVEN** portadores vinculados a outro projeto
- **WHEN** o select é montado
- **THEN** eles não são oferecidos

### Requirement: FE-159 — Ordenação multi-coluna
O sistema SHALL se comportar conforme os cenários desta seção.
O clique no cabeçalho cicla entre ascendente, descendente e sem ordenação, acumulando
chaves. Fonte legada: `.../receivables/_body.js.erb:21-126`.

#### Scenario: Ciclo de ordenação de uma coluna
- **GIVEN** a coluna Data sem ordenação
- **WHEN** o usuário clica três vezes no cabeçalho
- **THEN** a ordenação passa por ascendente, descendente e volta a sem ordenação, com o ícone refletindo cada estado

#### Scenario: Ordenação por duas colunas
- **GIVEN** a ordenação por Portador ascendente ativa
- **WHEN** o usuário adiciona Data descendente
- **THEN** a lista volta ordenada por portador e, dentro de cada portador, por data descendente
> Nota: corrige D-20 (comportamento legado: a UI mostrava o estado de ordenação mas o servidor reordenava tudo por `date DESC` no fim, tornando a funcionalidade decorativa)

### Requirement: FE-160 — Paginação da lista de recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
Botões de primeira/anterior/próxima/última página e um campo de limite navegam a lista.
Fonte legada: `.../receivables/_body.js.erb:300-306`, `:323-444`.

#### Scenario: Navegação entre páginas
- **GIVEN** 120 recebíveis e limite 50
- **WHEN** o usuário clica em "próxima"
- **THEN** a lista mostra os registros 51 a 100 e o botão "anterior" fica habilitado

#### Scenario: Última página com contagem correta
- **GIVEN** 120 recebíveis, limite 50 e ordenação por coluna ativa
- **WHEN** o usuário clica em "última página"
- **THEN** a lista mostra os registros 101 a 120
> Nota: corrige D-20 (comportamento legado: `@total_count` vinha paginado quando havia ordenação, então "última página" navegava para o lugar errado)

#### Scenario: Campo de limite vazio
- **GIVEN** o campo de limite apagado
- **WHEN** o usuário sai do campo
- **THEN** o limite volta ao padrão de 50

### Requirement: FE-161 — Botão "Cadastrar" com guarda de portador
O sistema SHALL se comportar conforme os cenários desta seção.
O botão de cadastro só aparece para quem pode escrever e exige que o projeto tenha
portador. Fonte legada: `.../receivables/_body.js.erb:447-462`.

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** a lista é exibida
- **THEN** o botão "Cadastrar" não aparece

#### Scenario: Projeto sem portador
- **GIVEN** um projeto corrente sem nenhum portador
- **WHEN** o usuário clica em "Cadastrar"
- **THEN** a tela exibe "É necessário ter um portador no projeto padrão, para que seja possível cadastrar um recebível"
> Nota: corrige comportamento legado (a mensagem falava em "cadastrar um controle de risco" numa tela de recebível)

### Requirement: FE-162 — Widget de linha do recebível
O sistema SHALL se comportar conforme os cenários desta seção.
Cada linha formata data, valores monetários e percentuais, e sinaliza a existência de
descrição. Fonte legada: `.../receivables/list/_widget.html.erb:1-60`.

#### Scenario: Formatação de data e moeda
- **GIVEN** um recebível de 05/03/2026 com bruto 100000, tarifas 3500 e líquido 96500
- **WHEN** a linha é renderizada
- **THEN** a data aparece como `05/03/2026` e os valores como `R$ 100.000,00`, `R$ 3.500,00` e `R$ 96.500,00`

#### Scenario: Formatação dos percentuais de CET
- **GIVEN** `custo_efetivo_sem_float = 4.1667`
- **WHEN** a linha é renderizada
- **THEN** o valor aparece formatado no padrão pt-BR com vírgula decimal e sufixo de percentual
> Nota: corrige comportamento legado (CET S/ Float e CET PM EMP eram impressos crus, com ponto decimal, destoando do resto da tela)

#### Scenario: Recebível com descrição
- **GIVEN** um recebível com `description` preenchida
- **WHEN** a linha é renderizada
- **THEN** um indicador de informação exibe o texto da descrição
> Nota: corrige comportamento legado (o tooltip era montado a partir do seletor `.risk_operation_info_tippy_content`, inexistente nesse widget, e saía vazio)

### Requirement: FE-163 — Menu de ações do recebível
O sistema SHALL se comportar conforme os cenários desta seção.
Cada linha oferece "Editar" e "Remover", com confirmação antes da exclusão. Fonte legada:
`.../receivables/list/_widget.js.erb:81-126`.

#### Scenario: Confirmação antes de remover
- **GIVEN** um recebível na lista
- **WHEN** o usuário aciona "Remover"
- **THEN** aparece a confirmação "Excluir recebível — A operação não pode ser desfeita. Tem certeza?" e nada é excluído até o aceite

#### Scenario: Exclusão confirmada recarrega a lista
- **GIVEN** a confirmação aceita
- **WHEN** a exclusão retorna sucesso
- **THEN** a lista é recarregada sem o recebível removido

### Requirement: FE-164 — Modo somente leitura nas telas de recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
Com `user_is_readonly` as ações de escrita somem das telas de recebíveis, cobranças e
catálogos. Fonte legada: `.../receivables/_body.html.erb:16`, `:21`;
`.../charges/list/_widget.html.erb:22-45`.

#### Scenario: Ações escondidas
- **GIVEN** um usuário somente-leitura
- **WHEN** ele abre recebíveis, cobranças, carteiras ou tipos
- **THEN** os botões de cadastro e os menus de ação das linhas não são exibidos

#### Scenario: Servidor também recusa a escrita
- **GIVEN** o mesmo usuário chamando um endpoint de escrita diretamente
- **WHEN** a requisição chega ao servidor
- **THEN** ela é recusada por autorização
> Nota: corrige D-17 (comportamento legado: era apenas ocultação visual; nenhum controller checava a permissão)

### Requirement: FE-165 — Formulário de recebível
O sistema SHALL se comportar conforme os cenários desta seção.
O formulário de cadastro e edição agrupa os campos em Cadastro, Datas, Prazos, Títulos,
Valores, Deduções, CET, TX Nominal, Checagem IOF e Tarifas, com os campos calculados
somente leitura. Fonte legada: `.../receivables/new/_body.html.erb:1-505`.

#### Scenario: Campos calculados não são editáveis
- **GIVEN** o formulário aberto
- **WHEN** o usuário tenta editar bruto final, valor líquido ou qualquer CET
- **THEN** os campos são somente leitura e refletem o cálculo do servidor

#### Scenario: Tipo de operação é imutável na edição
- **GIVEN** um recebível já criado com subtipo de operação de risco
- **WHEN** ele é aberto para edição
- **THEN** o campo de tipo de operação é somente leitura

#### Scenario: Catálogo vazio não quebra a tela
- **GIVEN** um projeto em que não há nenhuma carteira cadastrada
- **WHEN** o formulário é aberto
- **THEN** a tela abre com o select vazio e uma mensagem indicando o catálogo faltante
> Nota: corrige comportamento legado (o formulário fazia `Wallet.first.id` e levantava `NoMethodError`, derrubando a tela)

#### Scenario: Textos de ajuda dos campos
- **GIVEN** o formulário aberto
- **WHEN** o usuário aciona a ajuda de um campo
- **THEN** o texto exibido descreve o campo
> AMBIGUIDADE: no legado todo o conteúdo de `receivables_help_inputs.yml` é placeholder ("Só um teste de informações do campo..."); é preciso o texto real de cada um dos ~40 campos

### Requirement: FE-166 — Estado vazio do formulário: projeto sem portador
O sistema SHALL se comportar conforme os cenários desta seção.
Sem portador no projeto, o formulário inteiro é suprimido e a razão é explicada. Fonte
legada: `.../receivables/new/_body.html.erb:492-497`.

#### Scenario: Projeto sem portador
- **GIVEN** um projeto corrente sem portador
- **WHEN** o formulário de recebível é aberto
- **THEN** o formulário não é renderizado e a tela mostra "É necessário ter um portador no projeto padrão, para que seja possível cadastrar um recebível"

#### Scenario: Portador cadastrado libera o formulário
- **GIVEN** um portador vinculado ao projeto
- **WHEN** o formulário é reaberto
- **THEN** o formulário completo é exibido

### Requirement: FE-167 — Estado vazio do formulário: projeto sem empresa
O sistema SHALL se comportar conforme os cenários desta seção.
Sem empresa no projeto, o formulário oferece a criação inline da empresa. Fonte legada:
`.../receivables/new/_body.js.erb:8-37`.

#### Scenario: Atalho para cadastrar empresa
- **GIVEN** um projeto corrente sem empresa
- **WHEN** o formulário de recebível é aberto
- **THEN** a tela mostra "Esse projeto não possui empresa, clique aqui para cadastrar uma empresa no projeto e liberar a experiencia" e o link abre o cadastro de empresa

#### Scenario: Atalho funciona também na edição
- **GIVEN** o mesmo estado a partir da edição de um recebível
- **WHEN** o usuário aciona o atalho
- **THEN** o cadastro de empresa abre normalmente
> Nota: corrige comportamento legado (na variante de edição a URL usava a variável `id`, não definida no escopo)

### Requirement: FE-168 — Máscara de campos monetários
O sistema SHALL se comportar conforme os cenários desta seção.
Os campos de dinheiro aceitam apenas dígitos e um separador decimal, e exibem o prefixo
`R$` fora do foco. Fonte legada: `.../receivables/new/_body.js.erb:186-231`.

#### Scenario: Digitação e formatação
- **GIVEN** o campo de valor bruto em foco
- **WHEN** o usuário digita `100000,00` e sai do campo
- **THEN** o campo exibe `R$ 100.000,00`

#### Scenario: Mais de um separador decimal
- **GIVEN** o campo em foco
- **WHEN** o usuário digita um segundo separador decimal
- **THEN** a tela avisa "Você só precisa inserir 1 separador para as casas decimais" e o segundo separador é descartado

### Requirement: FE-169 — Máscara de campos decimais
O sistema SHALL se comportar conforme os cenários desta seção.
Prazos, floats e taxas usam a mesma máscara decimal, sem prefixo monetário. Fonte legada:
`.../receivables/new/_body.js.erb:138-183`.

#### Scenario: Formatação com vírgula decimal
- **GIVEN** o campo de prazo médio
- **WHEN** o usuário digita `28.5` e sai do campo
- **THEN** o campo exibe `28,5`

#### Scenario: Envio com ponto decimal
- **GIVEN** o campo exibindo `28,5`
- **WHEN** o formulário é submetido
- **THEN** o valor enviado ao servidor é `28.5`

### Requirement: FE-170 — Máscara de campos inteiros
O sistema SHALL se comportar conforme os cenários desta seção.
Quantidades aceitam apenas dígitos; o número do borderô é texto livre numérico. Fonte
legada: `.../receivables/new/_body.js.erb:110-136`.

#### Scenario: Quantidade aceita só dígitos
- **GIVEN** o campo de quantidade de títulos
- **WHEN** o usuário digita `12a3`
- **THEN** o campo fica com `123`

#### Scenario: Número do borderô
- **GIVEN** o campo de borderô, que é `string` no banco desde `db/migrate/20210403171744`
- **WHEN** o usuário digita um identificador com ponto
- **THEN** o valor é aceito e o texto de exemplo do campo reflete o formato aceito
> Nota: corrige comportamento legado (dois handlers conflitantes no mesmo campo — um só dígitos, outro dígitos e ponto — com o exemplo "Ex: 789" contradizendo o comportamento)

### Requirement: FE-171 — Prévia de cálculo em tempo real
O sistema SHALL se comportar conforme os cenários desta seção.
Ao alterar qualquer campo de entrada, a tela mostra os derivados recalculados, obtidos do
mesmo motor de cálculo do servidor. Fonte legada: `.../receivables/new/_body.js.erb:339-504`.

#### Scenario: Prévia acompanha a digitação
- **GIVEN** o formulário com bruto, prazos e tarifas preenchidos
- **WHEN** o usuário altera o valor de uma tarifa
- **THEN** valor total de tarifas, valor líquido, CETs, checagens e percentuais das deduções são atualizados na tela

#### Scenario: Prévia e gravação sempre coincidem
- **GIVEN** uma prévia exibida na tela
- **WHEN** o recebível é salvo sem alterações adicionais
- **THEN** os valores gravados são idênticos aos exibidos na prévia
> Nota: corrige D-09 (comportamento legado: as 26 fórmulas eram reimplementadas em JavaScript com divergências conhecidas — o JS não calculava `taxa_desconto_nominal_*`, `custo_efetivo_com_float_*`, `multiplicador_*` nem os `*_percent`, e arredondava o total de tarifas de forma diferente do servidor)

### Requirement: FE-172 — Bloqueio de salvamento por incongruência
O sistema SHALL se comportar conforme os cenários desta seção.
A tela impede o envio quando uma combinação de valores tornaria o cálculo indefinido, e o
servidor aplica as mesmas regras. Fonte legada: `.../receivables/new/_body.js.erb:259-274`.

#### Scenario: Combinações bloqueadas
- **GIVEN** o formulário em que `valor_liquido = 0`, ou `prz_med_pond_bco + float_acordado = 0`, ou `prz_med_pond_emp + float_acordado = 0`, ou `prz_med_pond_emp = 0`, ou `vlr_bruto_final = 0`
- **WHEN** o usuário tenta salvar
- **THEN** a tela mostra "Alguns campos podem estar incongruentes" e o botão de salvar não fica disponível

#### Scenario: Mesma guarda no servidor
- **GIVEN** a mesma combinação enviada diretamente à API
- **WHEN** a requisição é processada
- **THEN** o servidor responde 422 com o mesmo motivo
> Nota: corrige D-10 (comportamento legado: nenhuma dessas guardas existia no servidor)

### Requirement: FE-173 — Salvamento pela barra inferior
O sistema SHALL se comportar conforme os cenários desta seção.
O botão de salvar da barra inferior revalida os campos-chave antes de enviar e retorna à
lista em caso de sucesso. Fonte legada: `.../receivables/new/_body.js.erb:275-337`.

#### Scenario: Campos-chave em branco
- **GIVEN** o formulário com prazo médio da empresa vazio
- **WHEN** o usuário aciona salvar
- **THEN** a tela mostra "Alguns campos do recebível não foram preenchidos" e nada é enviado

#### Scenario: Salvamento bem-sucedido
- **GIVEN** o formulário válido
- **WHEN** o usuário aciona salvar
- **THEN** o recebível é gravado uma única vez e a navegação volta para a lista de recebíveis
> Nota: corrige comportamento legado (os handlers de `ajax:*` eram religados a cada recálculo, sem remoção prévia, acumulando bindings e podendo disparar o envio múltiplas vezes)

### Requirement: FE-174 — Conversão de valores no envio do formulário
O sistema SHALL se comportar conforme os cenários desta seção.
Os campos formatados são convertidos para o formato numérico antes do envio e
reformatados depois. Fonte legada: `.../receivables/new/_body.js.erb:311-333`.

#### Scenario: Conversão na submissão
- **GIVEN** os campos exibindo `R$ 100.000,00` e `28,5`
- **WHEN** o formulário é enviado
- **THEN** os valores transmitidos são `100000.00` e `28.5`

#### Scenario: Reexibição após o envio
- **GIVEN** o envio concluído
- **WHEN** a tela volta a ficar interativa
- **THEN** os campos voltam ao formato de exibição, sem divergir dos valores enviados

### Requirement: FE-175 — Tarifas: adicionar linha
O sistema SHALL se comportar conforme os cenários desta seção.
O botão "Adicionar" insere uma linha de tarifa com select de tipo e campo de valor.
Fonte legada: `.../receivables/new/_body.js.erb:506-660`.

#### Scenario: Nova linha de tarifa
- **GIVEN** a seção Tarifas com 2 linhas
- **WHEN** o usuário clica em "Adicionar"
- **THEN** uma nova linha aparece no topo, com os tipos de movimentação de operação ordenados por título, e os totais são recalculados

#### Scenario: Adicionar várias linhas seguidas
- **GIVEN** o usuário clicando em "Adicionar" cinco vezes
- **WHEN** ele digita em um campo monetário
- **THEN** a máscara aplica a formatação uma única vez por evento
> Nota: corrige comportamento legado (cada clique re-registrava as máscaras em todos os campos do formulário, multiplicando handlers)

#### Scenario: Tipo de tarifa duplicado
- **GIVEN** uma linha já com o tipo "Deságio"
- **WHEN** o usuário adiciona outra linha com o mesmo tipo
- **THEN** as duas são aceitas e somadas no mesmo bucket
> AMBIGUIDADE: o legado não valida duplicidade de tipo de tarifa no mesmo recebível; confirmar se deve passar a bloquear

### Requirement: FE-176 — Tarifas: remover linha
O sistema SHALL se comportar conforme os cenários desta seção.
Linhas ainda não salvas somem do formulário; linhas persistidas exigem confirmação.
Fonte legada: `.../receivables/new/_body.js.erb:529-533`, `:661-690`.

#### Scenario: Remover linha não salva
- **GIVEN** uma linha de tarifa recém-adicionada
- **WHEN** o usuário aciona a lixeira
- **THEN** a linha some e os totais são recalculados, sem chamar o servidor

#### Scenario: Remover tarifa persistida
- **GIVEN** uma tarifa já gravada
- **WHEN** o usuário aciona a lixeira e confirma "Excluir taxa — A operação não pode ser desfeita. Tem certeza?"
- **THEN** a tarifa é excluída, o recebível é recalculado pelo servidor e a tela reflete os novos totais

#### Scenario: Cancelar a edição depois de remover
- **GIVEN** uma tarifa persistida já excluída
- **WHEN** o usuário cancela a edição do recebível
- **THEN** a exclusão permanece efetivada
> AMBIGUIDADE: a exclusão de tarifa não é transacional com o formulário; confirmar se o ai9 deve manter o efeito imediato ou postergá-lo até salvar

### Requirement: FE-177 — Seletores de data de operação e de crédito
O sistema SHALL se comportar conforme os cenários desta seção.
Os dois seletores em pt-BR se restringem mutuamente e vêm pré-preenchidos com a data de
hoje no cadastro. Fonte legada: `.../receivables/new/_body.js.erb:74-108`.

#### Scenario: Restrição mútua das datas
- **GIVEN** a data de operação definida como 10/03/2026
- **WHEN** o seletor de data de crédito é aberto
- **THEN** datas anteriores a 10/03/2026 não podem ser escolhidas

#### Scenario: Pré-preenchimento no cadastro
- **GIVEN** o formulário aberto para um recebível novo
- **WHEN** a tela carrega
- **THEN** data de operação e data de crédito vêm com a data de hoje

#### Scenario: Data em passado remoto ou futuro
- **GIVEN** o seletor de data de operação
- **WHEN** o usuário escolhe uma data muito antiga ou muito futura
- **THEN** a data é aceita, como no legado
> AMBIGUIDADE: não há limite de janela de datas; confirmar se o ai9 deve restringir (ver BE-181)

### Requirement: FE-178 — Retorno do salvamento do recebível
O sistema SHALL se comportar conforme os cenários desta seção.
Erros e sucesso do salvamento são comunicados em pt-BR e distinguem cadastro de edição.
Fonte legada: `.../receivables/new/handle.js.erb:1-11`.

#### Scenario: Erros de validação
- **GIVEN** um recebível recusado por falta de limite de risco cadastrado
- **WHEN** a resposta chega
- **THEN** a tela mostra o erro com o nome do campo em pt-BR, e não o identificador `risk_operation_subtype_id`
> Nota: corrige comportamento legado (o `translate_every_key` existia mas nunca era chamado no fluxo de recebíveis)

#### Scenario: Mensagem de sucesso na edição
- **GIVEN** a edição de um recebível existente
- **WHEN** o salvamento tem sucesso
- **THEN** a mensagem indica atualização, não cadastro
> Nota: corrige comportamento legado ("Recebível foi cadastrado com sucesso!" era exibido também na edição)

### Requirement: FE-179 — Tela de lista de cobranças
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Cobranças" lista os pacotes do projeto com data, situação, valor e contagem de
operações. Fonte legada: `.../charges/_body.html.erb:1-64`.

#### Scenario: Colunas da lista de cobranças
- **GIVEN** cobranças no projeto corrente
- **WHEN** o usuário abre a área de cobranças
- **THEN** a tela mostra as colunas Data, Situação, Valor e OPERAÇÕES, além das ações

#### Scenario: Lista paginada
- **GIVEN** 200 cobranças no projeto
- **WHEN** a lista é aberta
- **THEN** a tela traz uma página de resultados com navegação, e não todas as cobranças de uma vez
> Nota: corrige D-20 (comportamento legado: limite fixo de 1000 no cliente e nenhum limite no servidor)

### Requirement: FE-180 — Filtros de cobrança
O sistema SHALL se comportar conforme os cenários desta seção.
Três seletores filtram por situação, mês e ano. Fonte legada:
`.../charges/_body.js.erb:13-41`.

#### Scenario: Filtro por situação
- **GIVEN** cobranças em "Edição", "Disponível" e "Faturado"
- **WHEN** o usuário escolhe "Faturado"
- **THEN** só as cobranças faturadas são listadas

#### Scenario: Remover o filtro de ano
- **GIVEN** o seletor de ano
- **WHEN** o usuário escolhe a opção em branco
- **THEN** as cobranças de todos os anos são listadas
> Nota: corrige comportamento legado (o seletor vinha pré-selecionado no ano corrente e não tinha opção em branco, tornando impossível ver todas as cobranças)

### Requirement: FE-181 — Widget e menu da cobrança
O sistema SHALL se comportar conforme os cenários desta seção.
Cada linha mostra data, valor e situação, com menu de ações oculto para somente-leitura.
Fonte legada: `.../charges/list/_widget.html.erb:1-47`.

#### Scenario: Formatação e indicador de faturado
- **GIVEN** uma cobrança de 05/03/2026 no estado "Faturado" com valor 2.700
- **WHEN** a linha é renderizada
- **THEN** a data aparece como `05/03/26`, o valor como `R$ 2.700,00` e a situação traz o indicador de faturado

#### Scenario: Menu oculto para somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** a lista é exibida
- **THEN** o menu "Ver mais / Editar / Remover" não aparece

### Requirement: FE-182 — Detalhe da cobrança
O sistema SHALL se comportar conforme os cenários desta seção.
O detalhe resume a cobrança, as remunerações do projeto e o extrato por remuneração.
Fonte legada: `.../charges/detail/_body.html.erb:1-151`.

#### Scenario: Cabeçalho e blocos do detalhe
- **GIVEN** uma cobrança com 2 operações liquidáveis e 1 estruturada
- **WHEN** o detalhe é aberto
- **THEN** o cabeçalho mostra "Cobrança #id" com "2 ops liquidáveis e 1 estruturadas", e a tela traz data, situação, valor total, valores por classe de operação e o valor total das operações

#### Scenario: Extrato por remuneração
- **GIVEN** remunerações cadastradas no projeto
- **WHEN** o detalhe é aberto
- **THEN** o cartão de extrato mostra a soma dos recibos por remuneração em reais, obtida em uma única consulta agregada
> Nota: corrige comportamento legado (uma consulta por remuneração, com "TODO #7388 otimizar a busca" no próprio código)

### Requirement: FE-183 — Ações do detalhe da cobrança
O sistema SHALL se comportar conforme os cenários desta seção.
O detalhe oferece selecionar operações, editar e remover a cobrança, respeitando o estado.
Fonte legada: `.../charges/detail/_body.js.erb:14-77`.

#### Scenario: Cobrança faturada bloqueia a seleção de operações
- **GIVEN** uma cobrança no estado "Faturado"
- **WHEN** o detalhe é aberto
- **THEN** a ação "Selecionar operações" fica indisponível na tela e também é recusada pelo servidor
> Nota: corrige D-18 (comportamento legado: o bloqueio era apenas visual)

#### Scenario: Remover a cobrança
- **GIVEN** uma cobrança sem recibos
- **WHEN** o usuário confirma "Remover pacote — A operação não pode ser desfeita. Tem certeza?"
- **THEN** a cobrança é removida e a tela mostra "O pacote foi removido com sucesso"

### Requirement: FE-184 — Tela de seleção de operações da cobrança
O sistema SHALL se comportar conforme os cenários desta seção.
A tela lista candidatos e recibos já vinculados, ordenados por data decrescente. Fonte
legada: `.../charges/receipts/_body.html.erb:1-43`.

#### Scenario: Colunas e pré-seleção
- **GIVEN** operações candidatas e recibos já vinculados à cobrança
- **WHEN** a tela é aberta
- **THEN** cada linha mostra Classe (LIQ/EST), Data, Tipo, Valor da operação e Valor da remuneração, e as operações já vinculadas vêm marcadas

#### Scenario: Recibo legado sem data
- **GIVEN** um recibo criado antes de `db/migrate/20220804195335`, com `date` nulo
- **WHEN** a tela é aberta
- **THEN** a linha é exibida com a data vazia, sem quebrar a tela
> Nota: corrige comportamento legado (a view chamava `receipt.date.strftime` sem guarda e a tela quebrava)

### Requirement: FE-185 — Seleção e persistência em lote de recibos
O sistema SHALL se comportar conforme os cenários desta seção.
O clique alterna a seleção e o envio persiste inclusões e remoções em um único lote.
Fonte legada: `.../charges/receipts/list/_body.js.erb:1-63`.

#### Scenario: Persistência do lote
- **GIVEN** 2 operações marcadas e 1 recibo desmarcado
- **WHEN** o usuário confirma
- **THEN** os 2 recibos são criados, o desmarcado é removido, os totais da cobrança são recalculados e a tela volta ao detalhe

#### Scenario: Falha no envio reverte a marcação
- **GIVEN** um lote que falha no servidor
- **WHEN** o erro chega
- **THEN** a tela mostra "Houve um problema, tente novamente" e a marcação visual volta ao estado anterior ao clique
> Nota: corrige comportamento legado (a marcação já havia sido alternada e não era revertida, deixando a tela fora de sincronia com o servidor)

### Requirement: FE-186 — Painel de criação e edição de cobrança
O sistema SHALL se comportar conforme os cenários desta seção.
O painel lateral captura situação e data de cobrança, com estados restritos na criação.
Fonte legada: `.../charges/helper/_body.html.erb:1-26`.

#### Scenario: Criação sem o estado Faturado
- **GIVEN** o painel aberto para uma cobrança nova
- **WHEN** o seletor de situação é exibido
- **THEN** só "Edição" e "Disponível" são oferecidos

#### Scenario: Data padrão da nova cobrança
- **GIVEN** o painel aberto para uma cobrança nova
- **WHEN** a tela carrega
- **THEN** a data de cobrança vem preenchida com hoje mais 30 dias

### Requirement: FE-187 — Tela de carteiras
O sistema SHALL se comportar conforme os cenários desta seção.
Lista e painel lateral de cadastro do catálogo de carteiras. Fonte legada:
`.../wallets/helper/_body.html.erb:1-32`.

#### Scenario: Cadastro de carteira
- **GIVEN** o painel lateral aberto
- **WHEN** o usuário informa título, chave de integração e situação e salva
- **THEN** a carteira é criada e aparece na lista

#### Scenario: Carteira sem chave de integração
- **GIVEN** uma carteira cuja chave de integração não foi informada
- **WHEN** a linha é renderizada
- **THEN** a coluna de chave mostra `-`

### Requirement: FE-188 — Tela de tipos de recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
Mesma estrutura de FE-187 para o catálogo de tipos de recebível. Fonte legada:
`.../receivable_kinds/helper/_body.html.erb:1-36`.

#### Scenario: Cadastro de tipo de recebível
- **GIVEN** o painel lateral aberto
- **WHEN** o usuário informa título, chave de integração e situação e salva
- **THEN** o tipo é criado e aparece na lista

#### Scenario: Busca por título
- **GIVEN** vários tipos cadastrados
- **WHEN** o usuário busca por parte do título
- **THEN** só os tipos correspondentes são listados

### Requirement: FE-189 — Tela de tipos de movimentação
O sistema SHALL se comportar conforme os cenários desta seção.
O painel lateral tem os 9 campos do tipo de movimentação, incluindo os classificadores
mutuamente exclusivos. Fonte legada: `.../movement_kinds/helper/_body.html.erb:1-101`.

#### Scenario: Campos do painel
- **GIVEN** o painel aberto
- **WHEN** ele é exibido
- **THEN** estão presentes título, chave de integração, Ativo, Tarifa da operação, Tarifa de título, AdValorem, Deságio, IOF, Tarifa de Liquidação e Tipo (Crédito/Débito)

#### Scenario: Classificadores mutuamente exclusivos na tela
- **GIVEN** "AdValorem" já marcado
- **WHEN** o usuário marca "IOF"
- **THEN** a tela impede a segunda marcação e explica a regra em pt-BR
> Nota: corrige comportamento legado (a UI não impedia, e o erro só voltava do servidor com o rótulo cru "Múltiplos tipos")

### Requirement: DB-150 — Tabela `receivable_entries`
O sistema SHALL se comportar conforme os cenários desta seção.
O borderô é uma entidade única e larga (60 colunas no legado), com ~7,7 mil registros a
migrar. Fonte legada: `db/migrate/20210315183541_create_receivable_entries.rb:1-69`.

#### Scenario: Migração completa dos borderôs
- **GIVEN** os 7.746 registros de `fbordero` no dump legado
- **WHEN** a carga de dados é executada
- **THEN** todos os borderôs existem no ai9 com os mesmos valores de identificação, valores e métricas calculadas

#### Scenario: Consulta de um borderô
- **GIVEN** um borderô migrado
- **WHEN** ele é consultado pela API
- **THEN** identificação, datas, prazos, valores, deduções e métricas calculadas são devolvidos juntos

### Requirement: DB-151 — Chaves e identificação de `receivable_entries`
O sistema SHALL se comportar conforme os cenários desta seção.
O borderô referencia usuário, projeto, portador, carteira, tipo de recebível, fonte de
recurso, empresa e tipo/subtipo de operação de risco, além do número do borderô. Fonte
legada: `db/migrate/20210315183541...:4-13`; `20210403171744_change_bordero_type_at_receivable_entries.rb:3`.

#### Scenario: Integridade referencial garantida pelo banco
- **GIVEN** uma tentativa de gravar um borderô com `wallet_id` inexistente
- **WHEN** a gravação é executada
- **THEN** o banco recusa a operação por violação de chave estrangeira
> Nota: corrige D-12 (comportamento legado: zero foreign keys e um único índice em todo o domínio financeiro)

#### Scenario: Número do borderô como texto
- **GIVEN** um borderô com número `000123`
- **WHEN** ele é gravado e relido
- **THEN** o valor volta como `000123`, sem perda de zeros à esquerda

#### Scenario: Coluna `resource_kind_id` sem consumidor
- **GIVEN** a coluna `resource_kind_id` existente na tabela legada
- **WHEN** o mapeamento de dados é definido
- **THEN** a coluna é migrada como dado bruto de proveniência
> AMBIGUIDADE: D-74 — `receivable_entries.resource_kind_id` nunca é preenchido e não tem associação nem uso visível; confirmar se deve ser portada ou descartada

### Requirement: DB-152 — Colunas monetárias de `receivable_entries`
O sistema SHALL se comportar conforme os cenários desta seção.
Dezoito colunas monetárias em `decimal(15,2)`, em reais implícitos, com deduções e
tarifas com padrão zero. Fonte legada: `db/migrate/20210315183541...:14-17`, `:25-26`, `:31-40`.

#### Scenario: Precisão e escala preservadas
- **GIVEN** um borderô com `valor_bruto = 1.234.567,89`
- **WHEN** ele é gravado e relido
- **THEN** o valor volta exatamente como `1.234.567,89`

#### Scenario: Valor acima do teto da coluna
- **GIVEN** um valor acima de R$ 9.999.999.999.999,99
- **WHEN** a gravação é tentada
- **THEN** a operação é recusada com erro de validação, e não truncada em silêncio

### Requirement: DB-153 — Colunas de prazo, taxa e CET
O sistema SHALL se comportar conforme os cenários desta seção.
Prazos, floats, taxas nominais e os sete custos efetivos são armazenados como ponto
flutuante no legado. Fonte legada: `db/migrate/20210315183541...:19-24`, `:49-61`.

#### Scenario: Resultados idênticos aos do legado
- **GIVEN** um borderô cujo CET no legado é `4.1667`
- **WHEN** o mesmo borderô é recalculado no ai9
- **THEN** o valor produzido é `4.1667`
> Nota: DEC-02 — a sequência de operações, casts e pontos de arredondamento do legado é replicada, ainda que o tipo de armazenamento no ai9 seja `decimal`

#### Scenario: Valores em reais guardados como float
- **GIVEN** `checagem_iof` e `dif_calc_vlr_liq`, que são valores em reais armazenados como float no legado
- **WHEN** eles são migrados
- **THEN** o valor exibido é idêntico ao do legado
> Nota: DEC-02 — D-13 fica subordinado à decisão do usuário; a divergência de precisão vai junto para a base nova, registrada no `improvements-log.md`

### Requirement: DB-154 — Empresa e taxa nominal em `receivable_entries`
O sistema SHALL se comportar conforme os cenários desta seção.
A empresa e as três colunas de taxa nominal foram adicionadas em 03/2022, deixando
registros anteriores sem empresa. Fonte legada:
`db/migrate/20220322123523_add_company_to_receivable_entries.rb:3-6`.

#### Scenario: Borderô anterior a 03/2022 sem empresa
- **GIVEN** borderôs migrados com `company_id` nulo
- **WHEN** a carga de dados é executada
- **THEN** cada um recebe a empresa do projeto (ou a "Empresa Padrão" criada para o projeto) antes da inserção, e o relatório da carga lista quantos foram corrigidos

#### Scenario: Empresa obrigatória no ai9
- **GIVEN** um borderô novo sem empresa
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 e o banco também recusa o nulo

### Requirement: DB-155 — Campos de texto livre do borderô
O sistema SHALL se comportar conforme os cenários desta seção.
`description` é exibida como informação adicional na lista; `observacoes` é um segundo
campo livre sem tela. Fonte legada:
`db/migrate/20220330140334_add_description_to_receivable_entries.rb:3`.

#### Scenario: Descrição exibida na lista
- **GIVEN** um borderô com `description` preenchida
- **WHEN** a lista é exibida
- **THEN** o texto aparece como informação adicional da linha

#### Scenario: Campo `observacoes` migrado sem tela
- **GIVEN** borderôs legados com `observacoes` preenchida
- **WHEN** a carga é executada
- **THEN** o conteúdo é preservado
> AMBIGUIDADE: `observacoes` não é lida nem escrita por nenhuma tela do legado; confirmar se vira campo visível, se é fundida com `description` ou se é descartada

### Requirement: DB-156 — Vínculo do borderô com tipo e subtipo de risco
O sistema SHALL se comportar conforme os cenários desta seção.
`risk_operation_type_id` e `risk_operation_subtype_id` são opcionais — a tela oferece "Não
associar". Fonte legada: `db/migrate/20220610122917_add_risk_operation_type_to_receivable_entries.rb:3-4`.

#### Scenario: Borderô sem associação de risco
- **GIVEN** um borderô criado com "Não associar"
- **WHEN** ele é gravado
- **THEN** a gravação é aceita, tipo e subtipo ficam nulos e nenhuma operação de risco é gerada

#### Scenario: Subtipo inexistente
- **GIVEN** um `risk_operation_subtype_id` que não existe
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 por associação inválida

### Requirement: DB-157 — Rastro de proveniência `legacy_id`
O sistema SHALL se comportar conforme os cenários desta seção.
Borderôs e catálogos guardam o identificador do sistema Django anterior. Fonte legada:
`db/migrate/20210402111120_add_legacy_id_to_entries_and_projects.rb`.

#### Scenario: Proveniência preservada
- **GIVEN** um borderô importado do sistema anterior
- **WHEN** ele é migrado para o ai9
- **THEN** o `legacy_id` original é preservado e permite reconciliar o registro com os borderôs de 2016-2021
> Nota: DEC-12 — o código do ETL Django não é portado, mas as colunas `legacy_*` são preservadas por serem a única prova de proveniência

#### Scenario: Registro sem proveniência
- **GIVEN** um borderô criado diretamente no sistema
- **WHEN** ele é migrado
- **THEN** o `legacy_id` fica nulo, distinguindo-o dos importados

### Requirement: DB-158 — Tabela `wallets`
O sistema SHALL se comportar conforme os cenários desta seção.
Catálogo global de carteiras, com título, chave de integração e situação; ~8 registros no
dump. Fonte legada: `db/migrate/20210317140156_create_wallets.rb:3-9`.

#### Scenario: Unicidade garantida pelo banco
- **GIVEN** duas requisições simultâneas criando a carteira "Desconto"
- **WHEN** ambas são processadas
- **THEN** apenas uma carteira é criada e a outra recebe erro de unicidade
> Nota: corrige D-12 (comportamento legado: a unicidade era só do ActiveRecord, sem índice único no banco, sujeita a corrida)

#### Scenario: Exclusão bloqueada por uso
- **GIVEN** uma carteira com recebíveis vinculados
- **WHEN** a exclusão é tentada
- **THEN** ela é recusada com a razão do bloqueio

### Requirement: DB-159 — Tabela `receivable_kinds`
O sistema SHALL se comportar conforme os cenários desta seção.
Catálogo global de tipos de recebível (Cheque, Duplicata, Cartão de crédito, ACC, PAC),
com as mesmas regras de `wallets`. Fonte legada:
`db/migrate/20210317140206_create_receivable_kinds.rb:3-10`.

#### Scenario: Migração dos tipos legados
- **GIVEN** os 4 registros de `dtiporecebivel` no dump
- **WHEN** a carga é executada
- **THEN** os 4 tipos existem no ai9 com título, chave de integração e situação preservados

#### Scenario: Unicidade e bloqueio de exclusão
- **GIVEN** um tipo de recebível já usado por borderôs
- **WHEN** um duplicado é criado ou a exclusão é tentada
- **THEN** as duas operações são recusadas com erro explicativo

### Requirement: DB-160 — Tabela `movement_kinds`
O sistema SHALL se comportar conforme os cenários desta seção.
Catálogo de tipos de movimentação (tarifas) com seis flags de classificação e o campo
`kind`. Fonte legada: `db/migrate/20210317151301_create_movement_kinds.rb:3-17`.

#### Scenario: Migração dos tipos de tarifa
- **GIVEN** os 17 registros de `dtarifa` no dump
- **WHEN** a carga é executada
- **THEN** os 17 tipos existem com título, chave, situação, classificadores e `kind` preservados

#### Scenario: Associação morta não é portada
- **GIVEN** a associação legada `has_many :receivables, foreign_key: :movement_kind_id`, que aponta para uma coluna inexistente em `receivable_entries`
- **WHEN** o modelo é portado
- **THEN** a associação não existe no ai9, e o vínculo com borderôs se dá apenas por `receivable_taxes`

#### Scenario: Campo `kind` com domínio fechado
- **GIVEN** um payload com `kind = "Outro"`
- **WHEN** a gravação é submetida
- **THEN** a resposta é 422 — só "Crédito" e "Débito" são aceitos
> Nota: corrige comportamento legado (`kind` era string livre, sem validação de inclusão)

### Requirement: DB-161 — Tabela `receivable_taxes`
O sistema SHALL se comportar conforme os cenários desta seção.
Tarifas do borderô, com título e flags denormalizados do tipo de movimentação; ~15,7 mil
registros. Fonte legada: `db/migrate/20210323134328_create_receivable_taxes.rb:3-13`.

#### Scenario: Leitura das tarifas de um borderô é indexada
- **GIVEN** um borderô com tarifas
- **WHEN** os buckets de tarifa são calculados
- **THEN** a leitura usa índice em `receivable_entry_id`
> Nota: corrige D-12 (comportamento legado: sem índice, apesar de a tabela ser lida quatro vezes a cada gravação de borderô)

#### Scenario: Tarifa órfã na carga
- **GIVEN** uma tarifa legada cujo `receivable_entry_id` não existe
- **WHEN** a carga é executada
- **THEN** a tarifa é reportada como órfã no relatório e não é inserida em silêncio
> Nota: corrige D-103 (comportamento legado: zero foreign keys em todo o schema, órfãos prováveis)

#### Scenario: Título denormalizado preservado
- **GIVEN** uma tarifa cujo título foi copiado do tipo de movimentação
- **WHEN** ela é migrada
- **THEN** o título gravado no momento da operação é preservado
> AMBIGUIDADE: manter a cópia (histórico fiel) ou normalizar contra `movement_kinds` é decisão de modelagem ainda aberta; note que `receivable_taxes` não tem a coluna `is_liquidation` que existe em `movement_kinds`

### Requirement: DB-162 — Tabela `charges`
O sistema SHALL se comportar conforme os cenários desta seção.
A cobrança guarda data, estado e um conjunto de totais denormalizados recalculados por
`Charge#calc!`. Fonte legada: `db/migrate/20220707164909_create_charges.rb:5-21`.

#### Scenario: Cobrança nunca referencia operações diretamente
- **GIVEN** uma cobrança e suas operações
- **WHEN** o modelo de dados é definido
- **THEN** a ligação passa obrigatoriamente por `receipts`, sem nenhuma referência direta de cobrança para operação
> Nota: restrição arquitetural registrada na própria migration legada ("jamais relacionar cobranças e ops diretamente... para evitar problemas de escalabilidade") e preservada no ai9

#### Scenario: Totais são cache derivado
- **GIVEN** uma cobrança cujos recibos mudaram
- **WHEN** os totais são consultados
- **THEN** eles refletem os recibos atuais, recalculados a partir deles

#### Scenario: Estado com domínio fechado
- **GIVEN** um estado fora de "Edição", "Disponível" e "Faturado"
- **WHEN** a gravação é tentada
- **THEN** ela é recusada pelo banco e pela aplicação
> Nota: corrige comportamento legado (`state` era string livre, sem check constraint)

### Requirement: DB-163 — Tabela `receipts`
O sistema SHALL se comportar conforme os cenários desta seção.
O recibo liga cobrança, remuneração e operação polimórfica, com `fee` percentual e os
valores de operação e de remuneração. Fonte legada:
`db/migrate/20220802225011_create_receipts.rb:3-21`.

#### Scenario: Unicidade por operação e projeto
- **GIVEN** um recibo já existente para a operação `O` no projeto `P`
- **WHEN** outro recibo para a mesma operação e projeto é criado
- **THEN** a criação é recusada pelo banco por violação de unicidade
> Nota: corrige D-12 (comportamento legado: a unicidade de `operation_id` + `project_id` + `operation_type` existia só no ActiveRecord)

#### Scenario: Consulta de recibos por operação
- **GIVEN** uma operação com recibo
- **WHEN** o recibo é buscado pela operação
- **THEN** a busca usa o índice polimórfico de `operation_type` + `operation_id`

### Requirement: DB-164 — Data e título da operação no recibo
O sistema SHALL se comportar conforme os cenários desta seção.
O recibo guarda uma fotografia da operação no momento da emissão. Fonte legada:
`db/migrate/20220804195335_add_date_and_operation_title_to_receipts.rb:3-4`.

#### Scenario: Fotografia da operação
- **GIVEN** uma operação com título "Desconto ACC" e data de emissão 01/03/2026
- **WHEN** o recibo é gerado e a operação é renomeada depois
- **THEN** o recibo continua mostrando "Desconto ACC" e 01/03/2026

#### Scenario: Recibos anteriores à migration
- **GIVEN** recibos criados entre 02 e 04/08/2022, com data e título nulos
- **WHEN** a carga de dados é executada
- **THEN** os dois campos são preenchidos a partir da operação vinculada antes da inserção, e o relatório informa quantos foram completados

### Requirement: DB-165 — Vínculo reverso `receipt_id` nas operações
O sistema SHALL se comportar conforme os cenários desta seção.
`structured_operations.receipt_id` e `risk_operations.receipt_id` marcam a operação já
faturada e são a base da busca de candidatos. Fonte legada:
`db/migrate/20220802225011_create_receipts.rb:19-20`.

#### Scenario: Vínculo consistente nos dois lados
- **GIVEN** a criação de um recibo para uma operação
- **WHEN** a gravação da operação falha depois de criado o recibo
- **THEN** nada é persistido e os dois lados permanecem consistentes
> Nota: corrige comportamento legado (a referência circular era mantida por callbacks sem transação nem FK — uma falha no meio deixava recibo sem operação ou operação sem recibo, escondendo ou duplicando candidatos na tela de seleção)

#### Scenario: Operação faturada sai da lista de candidatos
- **GIVEN** uma operação com recibo vinculado
- **WHEN** a lista de candidatos da cobrança é montada
- **THEN** ela não aparece como candidata

### Requirement: DB-166 — Índices e chaves estrangeiras do domínio
O sistema SHALL se comportar conforme os cenários desta seção.
O domínio nasce no ai9 com integridade referencial e os índices das colunas efetivamente
filtradas. Fonte legada: `db/` (sem `schema.rb` nem `structure.sql` versionados).

#### Scenario: Índices das consultas quentes
- **GIVEN** as consultas de lista e cálculo do domínio
- **WHEN** o schema é criado
- **THEN** existem índices em `receivable_entries(project_id, date)`, `receivable_entries(wallet_id)`, `receivable_entries(carrier_id)`, `receivable_taxes(receivable_entry_id)`, `charges(project_id, date)`, `receipts(charge_id)` e `receipts(remuneration_id)`
> Nota: corrige D-12 (comportamento legado: um único índice em todo o domínio e zero foreign keys)

#### Scenario: Estrutura versionada
- **GIVEN** o repositório do ai9
- **WHEN** alguém precisa conhecer a estrutura do domínio
- **THEN** ela está versionada no repositório, sem depender de rodar as migrations
> Nota: corrige comportamento legado (não havia `schema.rb` nem `structure.sql` versionado)

### Requirement: DB-167 — Volume e mapeamento dos dados legados
O sistema SHALL se comportar conforme os cenários desta seção.
O dump legado traz 7.746 borderôs, 15.712 tarifas, 17 tipos de tarifa, 8 carteiras e 4
tipos de recebível. Fonte legada: `db/seed_assets/sfg_legacy_full.sql`.

#### Scenario: Reconciliação de contagem após a carga
- **GIVEN** o mapeamento `fbordero`→`receivable_entries`, `fbortarifa`→`receivable_taxes`, `dcarteira`→`wallets`, `dtiporecebivel`→`receivable_kinds`, `dtarifa`→`movement_kinds`
- **WHEN** a carga é concluída
- **THEN** o relatório compara as contagens de origem e destino e aponta qualquer divergência

#### Scenario: Carga em lote única
- **GIVEN** o volume total do domínio
- **WHEN** a carga é planejada
- **THEN** ela cabe em uma execução única, sem particionamento

### Requirement: OPS-150 — Importação do sistema Django anterior
O sistema SHALL se comportar conforme os cenários desta seção.
O legado tem um ETL manual de mão única que trouxe o sistema Django anterior, executado em
2021. Fonte legada: `app/models/legacy.rb:1-48`; `app/models/legacy/receivable_entry.rb`.

#### Scenario: ETL Django não é portado
- **GIVEN** o pipeline `Legacy::execute`, a conexão `sfg_legacy` e o dump de 9 MB
- **WHEN** a migração para o ai9 é executada
- **THEN** nenhum deles é portado, e apenas as colunas `legacy_*` dos registros de destino são preservadas
> Nota: DEC-12 — assumido que o pipeline não roda mais desde 2021; a confirmação barata é verificar se existe registro com `legacy_id` criado depois de 2021

#### Scenario: Distorções deixadas pelo ETL antigo
- **GIVEN** que o ETL antigo forçava `user_id = 1` e `company_id = 1` em todos os borderôs importados
- **WHEN** a carga para o ai9 é executada
- **THEN** o relatório identifica os registros com essa marca para conferência
> AMBIGUIDADE: os borderôs de 2016-2021 têm autor e empresa artificiais; confirmar se devem ser reatribuídos ou mantidos como estão

### Requirement: OPS-151 — Recálculo em massa dos borderôs
O sistema SHALL se comportar conforme os cenários desta seção.
Existe uma rotina de recálculo de todos os borderôs, usada como último passo da
importação. Fonte legada: `app/models/legacy/receivable_entry_calculate_interceptor.rb:1-18`.

#### Scenario: Recálculo em lotes
- **GIVEN** ~7,7 mil borderôs
- **WHEN** o recálculo em massa é executado
- **THEN** ele processa em lotes, sem carregar todos os registros de uma vez, e reporta progresso e falhas
> Nota: corrige comportamento legado (percorria `ReceivableEntry.all` de uma vez, sem `find_each` e silenciando o logger)

#### Scenario: Recálculo não duplica operações de risco
- **GIVEN** borderôs com subtipo de operação de risco já vinculados a uma operação
- **WHEN** o recálculo em massa roda
- **THEN** nenhuma operação ou movimento de risco duplicado é criado
> Nota: corrige D-11 (comportamento legado: cada `save` disparava os `after_commit`, podendo criar `RiskOperation`/`RiskMovement` duplicados para cada borderô)

### Requirement: OPS-152 — Conexão com o banco legado
O sistema SHALL se comportar conforme os cenários desta seção.
As classes de importação do legado abriam conexão com um banco separado, quebrando o boot
quando ele não existia. Fonte legada: `app/models/legacy/*.rb`.

#### Scenario: Aplicação não depende do banco legado
- **GIVEN** o ai9 em execução
- **WHEN** a aplicação inicializa
- **THEN** nenhuma conexão com banco legado é aberta e a ausência de um banco legado não afeta o boot
> Nota: DEC-12 — a conexão `sfg_legacy` não é portada

#### Scenario: Extração de dados é externa à aplicação
- **GIVEN** a necessidade de ler o banco legado durante a migração
- **WHEN** o ETL é executado
- **THEN** ele roda como processo próprio, fora do ciclo de vida da aplicação

### Requirement: OPS-153 — Seeds dos catálogos de recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
Existem seeds para carteiras, tipos de recebível e tipos de movimentação, desligados por
padrão no legado. Fonte legada: `db/seeds.rb:7-12`, `:166-205`.

#### Scenario: Seed executável e idempotente
- **GIVEN** um ambiente novo do ai9
- **WHEN** o seed dos catálogos é executado duas vezes
- **THEN** os catálogos ficam com um único conjunto de registros, sem duplicatas
> Nota: corrige comportamento legado (as flags `should_seed_*` vinham `false` e exigiam editar o arquivo para rodar)

#### Scenario: Conteúdo do seed
- **GIVEN** o seed de carteiras
- **WHEN** ele é executado
- **THEN** as carteiras ACC, ACE, Antecipação, Caução, Cheque, Comissária, Conta Garantida, Desconto, Domicilio e Fomento existem

### Requirement: OPS-154 — Textos de ajuda do formulário de recebível
O sistema SHALL se comportar conforme os cenários desta seção.
Os textos de ajuda dos ~40 campos do formulário vêm de um arquivo de conteúdo. Fonte
legada: `db/seed_assets/receivables_help_inputs.yml`.

#### Scenario: Ajuda carregada sem custo por render
- **GIVEN** o formulário sendo aberto muitas vezes
- **WHEN** os textos de ajuda são resolvidos
- **THEN** o conteúdo é servido de cache, sem leitura de disco a cada renderização
> Nota: corrige comportamento legado (`YAML.load_file` a cada render, e arquivo ausente derrubava a tela)

#### Scenario: Campo sem texto de ajuda
- **GIVEN** um campo cuja chave não existe no conteúdo
- **WHEN** o formulário é renderizado
- **THEN** o campo é exibido sem indicador de ajuda, em vez de uma ajuda vazia

### Requirement: OPS-155 — Geração de PDF no domínio de recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
O legado declara `wicked_pdf` mas não gera nenhum PDF de recibo, cobrança ou recebível.
Fonte legada: `Gemfile.linux:34`.

#### Scenario: Nenhuma geração de PDF é portada
- **GIVEN** o domínio de recebíveis no ai9
- **WHEN** o escopo é definido
- **THEN** não existe geração de PDF, e a dependência do legado não é portada
> Nota: DEC-09 — D-84 fica fora de escopo: a gem estava declarada e a feature nunca existiu; criar PDF seria feature nova

### Requirement: OPS-156 — Exportação de dados de recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
Não existe nenhuma exportação (CSV, XLSX ou outra) para recebíveis, carteiras, cobranças
ou recibos no legado. Fonte legada: busca em `app/` por `send_data`, `to_csv`, `xlsx`.

#### Scenario: Nenhuma exportação é portada
- **GIVEN** o domínio de recebíveis no ai9
- **WHEN** o escopo é definido
- **THEN** não existe endpoint nem ação de exportação
> Nota: DEC-09 — só o que existe no legado é portado; o resquício de UI do `exportingMonitor` em `.../receivables/_body.js.erb:4-6` não corresponde a nenhuma funcionalidade

### Requirement: OPS-157 — Portabilidade da busca textual entre bancos
O sistema SHALL se comportar conforme os cenários desta seção.
A busca textual do legado montava o fragmento SQL conforme o adaptador detectado em
runtime. Fonte legada: `config/initializers/dev.rb:3-21`.

#### Scenario: Busca insensível a maiúsculas
- **GIVEN** um portador cadastrado como "Banco Alfa"
- **WHEN** o usuário busca por "banco alfa"
- **THEN** o recebível correspondente é retornado

#### Scenario: Termo com caractere especial de SQL
- **GIVEN** um termo de busca contendo `%` ou `_`
- **WHEN** a busca é executada
- **THEN** o termo é tratado como texto literal, sem alterar a semântica da consulta
> Nota: corrige comportamento legado (o fragmento SQL era interpolado direto na string do `where`)

### Requirement: OPS-158 — Filtros de período sem limite informado
O sistema SHALL se comportar conforme os cenários desta seção.
O legado usava datas-sentinela (hoje ± 2000 anos) como limites abertos dos filtros de
período. Fonte legada: `config/initializers/date_overload.rb:1-17`.

#### Scenario: Limite ausente omite a cláusula
- **GIVEN** uma busca de recebíveis ou cobranças sem data inicial nem final
- **WHEN** a consulta é montada
- **THEN** nenhuma cláusula de data é aplicada, em vez de um intervalo de 4000 anos
> Nota: corrige comportamento legado (`DateTime.dinosaurs` / `DateTime.mars`, que podem estourar a faixa de data do banco)

#### Scenario: Apenas um dos limites informado
- **GIVEN** somente a data inicial informada
- **WHEN** a consulta é montada
- **THEN** apenas a condição de data mínima é aplicada

### Requirement: OPS-159 — Formatação monetária em reais
O sistema SHALL se comportar conforme os cenários desta seção.
Toda exibição monetária do produto usa reais com separador de milhar `.`, decimal `,`,
2 casas e símbolo antes. Fonte legada: `config/initializers/type_casting.rb:31-91`.

#### Scenario: Formatação padrão
- **GIVEN** o valor 100000
- **WHEN** ele é exibido
- **THEN** aparece como `R$ 100.000,00`

#### Scenario: Valor nulo e valor zero são distinguíveis
- **GIVEN** um campo monetário nulo e outro com zero
- **WHEN** os dois são exibidos
- **THEN** o nulo aparece como ausência de dado e o zero aparece como `R$ 0,00`
> Nota: corrige D-117 (comportamento legado: `format_money` renderizava nulo como `R$ 0,00`, tornando campo faltante e campo zerado indistinguíveis num sistema financeiro)

#### Scenario: Arredondamento de exibição coincide com o de cálculo
- **GIVEN** um valor cujo arredondamento na segunda casa é ambíguo
- **WHEN** ele é exibido e recalculado
- **THEN** o valor exibido e o valor gravado coincidem
> Nota: corrige comportamento legado (`with_precision` usava `"%1.Nf"`, com arredondamento half-up do C, divergindo do `round` do Ruby em até um centavo)
