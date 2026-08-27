# Perguntas ao usuário — rodada 1, **metade dos mapas de bloco**

> **DEC-23** decidiu fazer uma rodada completa antes/durante o Phase 3. Este é **metade** do
> documento: as perguntas que saíram dos **5 mapas de bloco** (`.migration-ai9/map/*.md`).
> A outra metade — as que os agentes de empacotamento levantaram nos 20 `openspec/changes/*/proposal.md` —
> vem num arquivo irmão e será fundida com este.
>
> **Toda entrada foi conferida abrindo o arquivo do legado** (`/home/vinao/workspace/sfg`) ou da
> base ai9. Onde o mapa e a fonte divergiram, **vale a fonte** e a correção está escrita dentro
> da entrada, marcada em negrito. Foram **25 correções** — a lista está no fim.

## Contagem

| | |
| - | - |
| **Perguntas neste documento** | **98** |
| Levantadas nos mapas (bruto) | 118 |
| Removidas por **já estarem decididas** | 7 (DEC-01, DEC-09, DEC-18.5, DEC-21.1, DEC-21.2, DEC-21.3, DEC-21.4) |
| Fundidas (a mesma pergunta em blocos diferentes) | 13 fusões, absorvendo 15 perguntas duplicadas |
| Desdobradas (uma entrada com duas decisões) | 2 |

### Por impacto — **e é nesta ordem que elas estão**

| Impacto | Quantas | Faixa | O que significa |
| ------- | ------- | ----- | --------------- |
| `muda número na tela` | **16** | Q-01 … Q-16 | A resposta muda um valor que o cliente lê. **Nenhuma dá para responder no automático.** |
| `muda comportamento observável` | **41** | Q-17 … Q-57 | A resposta muda o que a tela faz, quem entra, ou o que fica gravado. |
| `muda escopo` | **29** | Q-58 … Q-86 | A resposta decide se algo é construído ou descartado. |
| `só interno` | **12** | Q-87 … Q-98 | Retenção, esquema, nomes. O default resolve; a resposta melhora. |

**Se você só tiver tempo para uma parte:** as 16 primeiras. São dinheiro, e o default delas é
sempre "replicar o que está lá" — o que significa que o silêncio também é uma resposta, e ela
carrega o erro para dentro do produto novo.

### As sete consultas ao dump que resolvem sozinhas 20+ IDs

Você tem o dump desde 25/08 (DEC-15.3). Estas perguntas viram fato com uma consulta:

| Pergunta | Consulta | O que ela decide |
| -------- | -------- | ---------------- |
| Q-57 | `\d availability_templates` | Se `default_position` existe → fecha o DEC-04 |
| Q-61 | `SELECT count(*) FROM receivable_entries WHERE resource_kind_id IS NOT NULL` | 9 IDs |
| Q-82 | `SELECT count(*) FROM geolocations` | 9 IDs |
| Q-69 | `SELECT count(*) FROM risk_entries` | A fatia R8 inteira |
| Q-47 | usuários com `username` e sem e-mail válido | Bloqueador de cutover, ou não |
| Q-51 | usuários com `is_staff AND is_superuser` | Quem está com papel rebaixado desde a importação |
| Q-24 | remunerações com `value` fora de 0–100 | Se validar recusa dado existente |

---

## `muda número na tela` — Q-01 a Q-16

### Q-01 — Correção por dias úteis: o valor decai a cada salvamento repetido

- **Fatia:** S11 (disponibilidades). O ETL de S14 depende da resposta para reconstituir `original_value`.
- **Trava:** trava `BE-127`, `BE-123` e `DB-125`, e trava a reconstituição de `original_value` no ETL. Sem resposta, o motor de disponibilidades não pode ser escrito.
- **Impacto:** `muda número na tela`
- **Contexto:** No legado, o lançamento de disponibilidade com padrão "ajustado" é corrigido por `value = original_value × (dias úteis até a data ÷ dias úteis do mês)` (`app/models/availability_entry.rb:193`), e um `before_validation` regrava `original_value = value` sempre que `value` chega alterado (`:20`). O formulário da grade preenche o campo com **`e.value` — o valor já corrigido** (`app/views/pub/console/parts/availability/parts/availability_entries/list/_widget.html.erb:56` e `:131`), então **salvar a mesma célula de novo aplica o multiplicador sobre um número que já foi multiplicado**. É o defeito **D-02**: dois usuários salvando a mesma linha produzem valores diferentes, e parte da base pode ter sofrido a correção mais de uma vez.
- **Opções:** (a) corrigir — a correção passa a ser aplicada **uma vez só**, sempre sobre `original_value`, e o ETL reconstitui `original_value` onde der, reportando o resto; (b) replicar o decaimento exatamente como está, com teste golden, e nunca mais tocar; (c) corrigir a fórmula **e** reprocessar o histórico (números antigos mudam).
- **Default vigente:** (a) — foi escolhido porque **DEC-01** (sinal) e **DEC-02** (float) não cobrem este caso: não é convenção nem precisão, é o mesmo dado valendo coisas diferentes conforme quantas vezes alguém apertou "salvar".
- **Recomendação:** (a). Replicar um número que depende do número de salvamentos não é preservar comportamento — é preservar a impossibilidade de conferir a conta.

### Q-02 — Consolidação de disponibilidades: duas regras de soma na mesma tela (e dois "Total")

- **Fatia:** S11
- **Trava:** trava `BE-125`, `BE-126`, `BE-148`, `DB-126` e `DB-130` — o serviço de consolidação não pode ser escrito com duas semânticas.
- **Impacto:** `muda número na tela`
- **Contexto:** Quando o usuário escolhe uma empresa, um nó com filhos soma aplicando cumulatividade e sinal: filhos não cumulativos entram como zero e débito entra com `-1` (`app/models/availability_entry.rb:191`). Quando ele escolhe **"Consolidação geral"** (o item em branco do select, `app/views/pub/console/parts/availability/_body.html.erb:24`), a linha consolidada é a "mirror" e soma **bruto**: `self.value = self.mirrored_entries.sum(:value)` (`:188`), ignorando `is_cumulative` e `is_debit`. É o **D-08**. O mesmo painel ainda usa a palavra "Total" para duas métricas: o total geral vem de `base_entries.pluck(:value).sum` (`app/models/project.rb:406`) e cada card de padrão base vem de `be.virtual_value`, que é saldo acumulado com sinal (`app/models/project.rb:415`) — é o **DC-34**, e a mesma resposta resolve os dois.
- **Opções:** (a) uma regra só — cumulatividade e sinal aplicados igualmente em folha, subtotal e consolidação geral, e "Total" passa a significar a mesma coisa nos dois lugares; (b) replicar as duas semânticas exatamente como estão hoje, com golden test; (c) uma regra só, mas mantendo os dois rótulos com nomes diferentes na tela ("Total bruto" × "Saldo").
- **Default vigente:** (a) — duas semânticas de soma na mesma tela é a definição de número em que não se pode confiar.
- **Recomendação:** (a) com (c) no rótulo: unificar a regra e **renomear** o card para "Saldo acumulado", para que ninguém compare dois números que nunca foram comparáveis.

### Q-03 — Dias úteis passam a considerar feriados?

- **Fatia:** S11
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda número na tela`
- **Contexto:** O contador de dias úteis do legado descarta apenas sábado e domingo: `reject { |d| d.cwday == 7 || d.cwday == 6 }` (`app/decorators/models/date_decorator.rb:3` e `:7`). Não existe calendário de feriados em lugar nenhum do repositório. É o **D-03**: em todo mês com feriado, o multiplicador de correção do Q-01 está alto, e sempre esteve.
- **Opções:** (a) manter seg–sex sem feriados; (b) ligar feriados **nacionais** (gem/tabela versionada) valendo só para lançamentos novos; (c) ligar feriados e reprocessar o histórico.
- **Default vigente:** (a) — ligar feriados muda o resultado financeiro de **todo** o histórico e ainda obriga a escolher o calendário (nacional, estadual, bancário), que é decisão de negócio.
- **Recomendação:** (a) nesta entrega. O calendário é aditivo: entra depois sem refazer nada, e aí com a escolha do calendário feita conscientemente.
### Q-04 — Borderô: recalcular ou copiar o valor das operações de risco históricas?

- **Fatia:** S6 (motor de cálculo), consumida por S14 (ETL)
- **Trava:** trava a carga de `risk_operations` no ETL e o desenho de `BE-183`. O ai9 já nasce certo; o que falta decidir é o histórico.
- **Impacto:** `muda número na tela`
- **Contexto:** No cadastro de borderô o controller salva duas vezes: `receivables_controller.rb:77` (grava o recebível) e `:89` (grava de novo depois de criar as tarifas, com o comentário *"atualizar os calculos internos com os valores das taxas \o/"*). O `after_commit` de `receivable_entry.rb:124-175` dispara nas duas — e na primeira ainda não existe nenhuma `ReceivableTax`, então a `RiskOperation` nasce com `operation_value: self.valor_liquido` (`:161`) calculado **sem as tarifas**. **Correção ao mapa:** o segundo disparo **não conserta**; ele cai no ramo de `:168`, que só atualiza tipo e subtipo. O valor errado fica congelado para sempre. O próprio autor deixou o comentário `# aqui está o caso de bugar o save do recebível` em `receivable_entry.rb:123`. É o **D-11**, e é dado sujo em produção, não só bug de código.
- **Opções:** (a) recalcular o valor de operação dos borderôs históricos no ETL, com relatório de quantos mudaram e de quanto; (b) copiar o valor legado como está (bate com o que o cliente vê hoje, continua errado); (c) copiar como está **e** gravar em paralelo o valor recalculado numa coluna de auditoria, para o cliente decidir depois.
- **Default vigente:** (a) — o ai9 já nasce com a operação criada depois das tarifas, e manter dois regimes de verdade no mesmo painel de exposição seria pior que a correção.
- **Recomendação:** (a) com o relatório antes de qualquer carga definitiva. Se o delta agregado for material, (c) vira o caminho conservador — mas isso só se sabe com o número na mão.

### Q-05 — `calc_valor_liq_correto`: desconto linear é a regra pretendida?

- **Fatia:** S6
- **Trava:** nada — só muda o resultado (e o rótulo "OK"/"Diferença" que o usuário lê).
- **Impacto:** `muda número na tela`
- **Contexto:** A fórmula converte o custo efetivo acordado em taxa diária equivalente e desconta **linearmente**: `power_tx = ((cst_efetivo_acordado/100 + 1) ** 0.0333…) - 1`, depois `vp = (vlr_bruto_final - tx * (prz_med_pond_emp + float_acordado)).round(2)` (`app/models/receivable_entry.rb:107-112`). Não é desconto composto (`VF/(1+i)^n`). Esse número alimenta direto o carimbo que o operador vê: `dif_calc_vlr_liq` em `:114` e `status = dif < 0 ? "Diferença" : "OK"` em `:115`. A mesma fórmula está duplicada no JS da tela (`.../receivables/new/_body.js.erb:462-467`) — é o **D-14** e a origem do **D-09**.
- **Opções:** (a) replicar exatamente, com teste golden (nada muda); (b) trocar para desconto composto — o valor presente e a classificação OK/Diferença mudam em todo o histórico; (c) replicar e exibir os dois lado a lado por um período, para o negócio comparar.
- **Default vigente:** (a), por **DEC-02** — o resultado é replicado, incluindo os casts e os pontos de arredondamento.
- **Recomendação:** (a). Se a aproximação linear for um erro, trocá-la é uma linha depois — mas trocar junto com a migração torna impossível saber se um número novo veio do ai9 ou da fórmula nova.

### Q-06 — CET do banco: a guarda olha o prazo da **empresa**

- **Fatia:** S6
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda número na tela`
- **Contexto:** `app/models/receivable_entry.rb:74` zera o custo efetivo do banco quando o prazo médio ponderado da **empresa** é zero: `self.custo_efetivo_pz_med_banco_sem_iof = self.prz_med_pond_emp == 0 ? 0 : tx_banco_iof` — mas a base do cálculo (`power_bco_iof`, `:72`) usa `prz_med_pond_bco + float_acordado`. Quatro linhas abaixo, `:78` faz a guarda certa, com `prz_med_pond_bco == 0`. A assimetria não tem explicação no código e tem cara de copy/paste.
- **Opções:** (a) replicar exatamente; (b) corrigir a guarda para `prz_med_pond_bco == 0`, alinhando com `:78`.
- **Default vigente:** (a) — trocar muda o valor exibido em qualquer borderô com prazo de empresa zero e prazo de banco diferente de zero.
- **Recomendação:** (a) na entrega, **com a divergência registrada no `improvements-log.md`** e um golden que documenta o comportamento. É um caso raro e vale corrigir depois, com o cliente ciente.

### Q-07 — CET: 2 casas num campo, 4 no outro, com a mesma base

- **Fatia:** S6
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda número na tela`
- **Contexto:** `custo_efetivo_pz_med_emp` fecha com `.round(4)` (`app/models/receivable_entry.rb:90-92`) e `custo_efetivo_com_float_total` fecha com `.round(2)` (`:99`), sendo a expressão **algebricamente a mesma**. Os dois aparecem no mesmo bloco do formulário.
- **Opções:** (a) replicar os dois arredondamentos como estão; (b) padronizar em 4 casas nos dois; (c) padronizar em 2.
- **Default vigente:** (a), por **DEC-02** e porque o arredondamento faz parte da cadeia que produz o número que a tela mostra.
- **Recomendação:** (a). Padronizar é cosmética que muda dinheiro; se incomodar, é ajuste de uma linha com o cliente avisado.

### Q-08 — A remuneração é percentual flat sobre o capital, sem prazo?

- **Fatia:** S8 (remuneração e recibos); mesma fórmula citada por `receivables` e por `risk`
- **Trava:** trava `BE-305` e `BE-188` — é a **única fórmula de faturamento do sistema**.
- **Impacto:** `muda número na tela`
- **Contexto:** `app/models/receipt.rb:63` — `self.value = self.operation_value * (self.fee.to_f / 100.0)`, com `fee` vindo de `remuneration.value` (`:61`). Não entram `agreed_rate`, nem `issue_date`/`due_date`, nem `balance`: a tabela de recibos guarda `fee`, `operation_value`, `value`, `date` e o rótulo da operação (`db/migrate/20220802225011_create_receipts.rb:3-17` + `20220804195335_...`), e a `date` é só uma cópia do `issue_date` da operação (`receipt.rb:46`). O legado **não tem nenhum teste** (D-114), então essa fórmula nunca foi verificada por nada. É o **D-72**, levantado independentemente pelos blocos de recebíveis (Q-B14) e de risco (Q-R17).
- **Opções:** (a) replicar o flat exatamente, com golden (o valor faturado não muda); (b) implementar pro-rata por prazo, usando `issue_date`/`due_date` que já estão guardados — muda a receita reconhecida; (c) replicar agora e abrir um tipo de remuneração "pro-rata" como opção de cadastro depois.
- **Default vigente:** (a) — é dinheiro cobrado do cliente, e o modelo guardar `issue_date`/`due_date` **sugere** pro-rata sem provar que ela existia.
- **Recomendação:** (a), e a resposta a esta pergunta é a que mais vale a pena ter por escrito: é a linha que fatura.

### Q-09 — "A vencer" na renegociação inclui as parcelas já vencidas

- **Fatia:** S9
- **Trava:** nada — só muda o número da coluna.
- **Impacto:** `muda número na tela`
- **Contexto:** `app/models/renegotiation.rb:110` — `self.due_installments = self.installments_count - self.paid_installments`. Uma linha acima, `:109` calcula `overdue_installments` com `DATE(due_date) < hoje AND is_paid = 0`. Como "a vencer" é só "tudo que não foi pago", **as vencidas estão contadas dentro dela**. E `due_installments` não é só rótulo: é usado como **expoente do valor presente** em `:180`.
- **Opções:** (a) manter a semântica atual e renomear a coluna para "Em aberto"; (b) mudar a conta para `installments_count - paid_installments - overdue_installments` (o número na tela muda, e o VP de `:180` muda junto); (c) manter a conta e acrescentar uma coluna "Vencidas" ao lado, sem mexer no cálculo.
- **Default vigente:** (a) — mexer em `due_installments` mexe no valor presente, e valor presente é DEC-02.
- **Recomendação:** (a). Renomear resolve a confusão sem tocar em dinheiro; (c) como complemento se o negócio quiser ver os dois.

### Q-10 — Renegociação: dois números diferentes para "o que falta pagar"

- **Fatia:** S9
- **Trava:** trava `BE-205` — o serviço de agregação precisa de uma definição só.
- **Impacto:** `muda número na tela`
- **Contexto:** `renegotiation.rb:102` calcula `pending_main_value = main_value - paid_value_with_interest_cm`, **sem piso** — pagar a mais deixa o número negativo. `renegotiation.rb:107` calcula `remaining_value = installments.pluck(:pending_value).sum`, e `pending_value` tem piso em zero (`renegotiation_installment.rb:66` e `:24`). Os dois medem "o que falta" e podem discordar na mesma tela; só `remaining_value` decide o status da renegociação (`:122`).
- **Opções:** (a) `remaining_value` (soma das parcelas, com piso) é o número oficial e `pending_main_value` vira interno; (b) `pending_main_value` é o oficial, e o crédito por pagamento a maior passa a aparecer como saldo negativo; (c) manter os dois, com rótulos que expliquem a diferença.
- **Default vigente:** (a) — é o que já governa o status hoje, então é o que o sistema de fato considera verdade.
- **Recomendação:** (a). E o pagamento a maior merece tratamento explícito (crédito), não um número negativo escondido num campo secundário.

### Q-11 — Correção monetária e carência: a tela promete, o cálculo ignora

- **Fatia:** S9
- **Trava:** trava `BE-208` e `FE-199` — decide se dois campos existem ou não.
- **Impacto:** `muda número na tela`
- **Contexto:** `interest_rate_correction` e `grace_period` são criados na migration (`db/migrate/20210324173930_create_renegotiations.rb:17,19`), aparecem no formulário e **não são lidos por nenhum cálculo** no repositório inteiro — só por comentários (`renegotiation.rb:247,248,275,277`) e por mensagens de erro traduzidas. O valor corrigido é sempre cópia crua: `renegotiation.rb:93` — `self.correct_value = self.total_debt`. É o **D-47**.
- **Opções:** (a) implementar de verdade — os valores corrigidos passam a divergir do que o cliente vê hoje em toda renegociação que tenha esses campos preenchidos; (b) remover os dois campos da tela e registrar como funcionalidade nunca entregue; (c) manter os campos visíveis e somente leitura, marcados como "não aplicado", até o negócio definir a fórmula.
- **Default vigente:** (b) — DEC-09 manda portar o que **existe**, e o que existe é a coluna, não o cálculo.
- **Recomendação:** (b). Campo que promete correção monetária e não corrige nada num sistema de crédito é pior que campo ausente.

### Q-12 — "Valor Parcela" é sobrescrito pelo valor presente

- **Fatia:** S9
- **Trava:** nada — só muda o resultado, mas é a coluna mais lida da tela de renegociação.
- **Impacto:** `muda número na tela`
- **Contexto:** `renegotiation.rb:125` calcula `current_installment_value` pelo valor nominal da parcela do mês; **na linha seguinte**, `:126` chama `calculate_current_value`, que dentro de si faz `self.current_installment_value = vp.round(2)` (`:182`) — reatribuindo a mesma coluna com o **valor presente**. Resultado: sempre que há juros > 0 e saldo em aberto, a coluna "Valor Parcela" mostra outra coisa. É o **D-46**.
- **Opções:** (a) replicar o efeito exatamente, com golden; (b) separar em dois campos — "Valor da parcela" (nominal) e "Valor presente" — e mostrar os dois; (c) manter só o nominal na coluna e expor o VP no detalhe.
- **Default vigente:** (a) — mudar altera o número que o cliente lê hoje, e não há reconciliação feita.
- **Recomendação:** (b) **depois** de (a): replicar na entrega, e propor os dois campos no `improvements-log`. É reatribuição acidental, não regra de negócio — mas provar isso exige o cliente confirmar.

### Q-13 — Mora na parcela: entra dos dois lados da conta

- **Fatia:** S9
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda número na tela`
- **Contexto:** **Correção ao mapa.** O mapa afirma que "pagar só a mora pode quitar a parcela". Conferido na fonte, **não é isso que acontece**. A mora entra no devido (`renegotiation_installment.rb:62-63`: `installment_total_value = main_value_with_interest_cm + late_payment_value`) **e** no pago (`:64`, via `renegotiation_payment.rb:13`, onde `total_paid_value` já embute a mora). Como entra idêntica dos dois lados, ela **se cancela**: `pending_value = main_cm − pago_cm` (`:65-67`), e `is_paid` só vira 1 quando o principal com juros é coberto (`:67`). O efeito real é outro e continua sendo um problema: **a mora nunca é efetivamente cobrada** na parcela, e no nível da renegociação ela é contada como pagamento (`renegotiation.rb:105`), **inflando o "R$ Pago"** exibido.
- **Opções:** (a) replicar exatamente (mora neutra na parcela, inflando o pago no agregado); (b) tirar a mora do lado pago da parcela, para que ela passe a ser efetivamente devida — muda saldo de toda renegociação com atraso; (c) replicar na parcela e corrigir só o agregado `paid_value`, para o "R$ Pago" parar de contar mora como amortização.
- **Default vigente:** (a) — é dinheiro e não houve reconciliação.
- **Recomendação:** (c). É a correção de menor risco: não mexe em quitação de parcela nenhuma, e conserta o único número que hoje é claramente enganoso.
### Q-14 — Subtipo da operação de risco: o formulário não pergunta e o código escolhe "o primeiro"

- **Fatia:** S7 (operações de risco), com efeito direto em S5 (limites) e S6 (borderô)
- **Trava:** trava `BE-262`, `BE-244` e `BE-245` — é o subtipo que decide em qual bucket de limite a operação entra.
- **Impacto:** `muda número na tela`
- **Contexto:** Quando o subtipo não vem no formulário, `app/models/risk_operation.rb:32` faz `operation_subtype_id = operation_type.subtypes.where(...).pluck(:id).first` — **sem `order`**, ou seja, ordem de inserção no banco. E o formulário de operação de risco **não tem campo de subtipo** (zero ocorrências de `subtype` em `.../risk_operations/new/_body.html.erb`), então esse caminho é o padrão em toda criação manual. O subtipo decide o bucket: `is_pre = 0` entra em "liquidável" (`risk_control.rb:129-130`) e `is_pre = 1` entra em "pré-faturamento" (`:144-145`). Como `risk_operation_type.rb:23` cria o subtipo "pré" antes do de "antecipação" (`:31`), **o `.first` tende a cair no pré**. **Correção ao mapa:** o mapa de `auth-admin` (Q-B10) diz que os subtipos "estão comentados no legado" — **não estão**. Eles são infraestrutura viva (`risk_operation.rb:10,29-32,148-154`, `risk_control.rb:20,22,129,144`, `receivable_entry.rb`, e o select vivo em `.../receivables/new/_body.html.erb:95`). O que não existe é CRUD, item de menu e campo no formulário de risco; comentada há **uma** linha, `console_controller.rb:172`.
- **Opções:** (a) replicar o `.first` exatamente, com `order` explícito por id para pelo menos ser determinístico; (b) acrescentar o campo de subtipo ao formulário de operação de risco, e o usuário escolhe; (c) tornar o subtipo padrão uma **configuração do tipo** (`is_default` já existe nessa família), e o formulário só o mostra quando há mais de um.
- **Default vigente:** (a) — mexer aqui move operação de bucket, e bucket é exposição.
- **Recomendação:** (c). É a única opção em que o número deixa de depender da ordem de inserção de linhas num cadastro, sem obrigar o operador a responder uma pergunta que ele hoje não responde.

### Q-15 — "Encerrar" uma operação de risco deve tirá-la da exposição?

- **Fatia:** S7
- **Trava:** trava `BE-268` e `BE-277` (o **D-94** manda dar estado real a `is_ended`), e toca o núcleo protegido pelo DEC-01.
- **Impacto:** `muda número na tela`
- **Contexto:** Hoje `is_ended` não faz quase nada. Aparece em 6 lugares e nenhum é uma trava: a janela de exposição filtra **só** por data (`risk_control.rb:76-79`, `due_date >= d AND issue_date <= d`), então **operação encerrada continua somando** em `limite_utilizado_on` (`:115-124`), `limite_liquidavel_on` (`:126-140`) e `limite_pre_on` (`:141-156`). Lançar movimento numa operação encerrada é aceito (`risk_movement.rb:20-28` só valida a data) e prorrogar também (`risk_operation_extension.rb:8-16` empurra a `due_date` sem olhar nada). O único uso real de `is_ended` é bucketizar "vencidos" × "a vencer" (`risk_control.rb:94` e `:106`).
- **Opções:** (a) bloquear movimento e prorrogação em operação encerrada, **sem** mexer na janela de exposição (os números do painel não mudam); (b) (a) + retirar operações encerradas de `operations_on` — a exposição de **todo o histórico** muda; (c) não mexer em nada, "encerrar" continua sendo só um rótulo.
- **Default vigente:** (a) — o D-94 autoriza dar estado real ao encerramento, mas **não** autoriza mexer nos números que o DEC-01 protege.
- **Recomendação:** (a). Se (b) for o desejado, é uma mudança que precisa de reconciliação com o cliente antes, não junto com a migração.

### Q-16 — Transferência a partir da antecipação não gera contrapartida

- **Fatia:** S7
- **Trava:** nada — só muda o resultado, mas afeta o saldo dos dois lados da transferência.
- **Impacto:** `muda número na tela`
- **Contexto:** O `after_create` de `app/models/risk_movement.rb:45-65` só cria o movimento espelho quando a origem é pré-faturamento: `if self.movement_type_id == RiskMovementType.transferencia_enviada_id && self.risk_operation.is_pre?` (`:46`). Partindo da operação de antecipação (`is_pre = 0`), o "enviado" é gravado e **nenhum "recebido" nasce do outro lado** — o valor sai de uma operação e não entra em nenhuma.
- **Opções:** (a) replicar a assimetria exatamente; (b) espelhar nos dois sentidos; (c) recusar (422) a transferência a partir da antecipação, deixando explícito que o sentido não é suportado.
- **Default vigente:** (a) — espelhar cria movimento que hoje não existe, e movimento muda saldo, que muda exposição.
- **Recomendação:** (c) para lançamentos **novos** e (a) para o histórico. Aceitar em silêncio um lançamento que perde metade da contrapartida é o pior dos três.

---

## `muda comportamento observável` — Q-17 a Q-57

### Q-17 — `has_safegold_management`: carimbo histórico ou derivado do projeto?

- **Fatia:** S4 (projeto e empresas); atinge também S6, S9, S11 e S5
- **Trava:** trava `BE-093`, `DB-051`, `DB-090`, `DB-130` e `DB-197` — decide o desenho de **6 tabelas**.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O projeto tem a marca "gestão Safegold", e ela é **copiada** para 6 tabelas na criação de cada registro: `company.rb:13`, `availability_entry.rb:17`, `receivable_entry.rb:40`, `renegotiation.rb:24`, `risk_control.rb:15` e `risk_entry.rb:32`. Quando a marca do projeto muda, o único lugar atualizado em massa é `companies` (`project.rb:298-303`, `self.companies.update_all(...)`) — todas as outras cinco ficam com o carimbo velho para sempre. É o **D-30**. **Verificação na fonte que o mapa não tinha:** procurei um leitor e **não existe nenhum** — nenhum `where(has_safegold_management: …)`, nenhum scope, nenhum `if` de regra de negócio em `app/`, `engines/`, `lib/` ou `config/`. As únicas leituras são a exibição do próprio interruptor no projeto (`.../projects/detail/tabs/_tab_geral.html.erb:13-14`) e uma cópia interna em `risk_control.rb:184`. Ou seja: hoje a marca **não muda nada** dentro do sistema — o risco é só um consumidor externo (BI, planilha, relatório do cliente) lendo o banco.
- **Opções:** (a) derivar do projeto em tempo de consulta e **remover a coluna das 6 filhas** — a inconsistência acaba, e um registro de 2019 passa a refletir a marca **atual**; (b) manter o carimbo como está (foto do momento), inclusive a inconsistência; (c) manter o carimbo **e** passar a ressincronizar as 6 tabelas quando a marca muda (foto que se atualiza — o pior dos mundos, mas é o que a intenção do código sugeria).
- **Default vigente:** (a) — nenhum consumidor interno foi encontrado, e derivar simplifica 6 tabelas de uma vez.
- **Recomendação:** (a), **se** você confirmar que nenhum relatório externo lê essas colunas. Se houver, (b) — porque aí o carimbo é justamente o valor histórico que o relatório quer.


### Q-18 — Aceite de contrato: volta a ser explícito?

- **Fatia:** S12 (contratos), com dependência de S1 (convite)
- **Trava:** **bloqueia S12.** Sem resposta, não há como especificar o fluxo de Termos e Privacidade.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Em produção o aceite explícito está morto por **quatro** motivos independentes, todos conferidos: o bloqueio de acesso por contrato pendente está inteiramente comentado (`app/controllers/pub_application_controller.rb:55-63`); os dois botões "ACEITAR" estão comentados nas views (`app/views/pub/contracts/header/_body.html.erb:44` e `.../\_toolbar_body.html.erb:22`), embora os handlers JS e a rota `PUT` continuem vivos e inalcançáveis; o cálculo de pendência **levanta exceção** porque a associação está errada (`app/decorators/models/user_decorator.rb:40` declara `source: :contract_deal`, e `ContractDeal` só tem `:contract` e `:user`); e os checkboxes de cadastro e de "Minha Conta" vêm **pré-marcados** e não são lidos por controller nenhum (`.../sign_up/_sign_up.html.erb:57-58`, `.../my_account/parts/essential/_container.html.erb:114-115`). O aceite real é implícito: um `after_create` no usuário grava os dois (`user_decorator.rb:2` e `:234-240`). É o **D-64**, e a consequência é jurídica — **o sistema registra hoje um aceite que o usuário nunca deu conscientemente**.
- **Opções:** (a) reativar o aceite explícito, com bloqueio de acesso enquanto houver contrato pendente (é o comportamento que o código pretendia); (b) reativar o aceite explícito **sem** bloqueio de acesso — banner persistente até aceitar; (c) manter o aceite implícito de hoje.
- **Default vigente:** (b) — nenhum default seguro existe aqui, e (b) é o menos arriscado dos que corrigem o problema: registra consentimento real sem trancar ninguém fora no dia 1. Com **DEC-18.7** (cadastro público desligado, entrada só por convite), o consentimento passa naturalmente para o fluxo de convite (`BE-340`, `FE-337`).
- **Recomendação:** (b) na entrega e (a) no cutover, com o jurídico definindo o prazo de tolerância. Não é decisão de engenharia.


### Q-19 — O que fazer com os aceites implícitos que já estão gravados?

- **Fatia:** S14 (ETL), consumida por S12
- **Trava:** trava a carga de `contract_deals`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Além do `after_create` que grava aceite sem interação, o seed do legado **fabricou aceite retroativo para toda a base**: `db/seeds.rb:141-148` e `:150-157` pegam todos os usuários sem aceite e criam um `ContractDeal` para cada um. Ou seja, a base de aceites existente não distingue "aceitou" de "foi carimbado".
- **Opções:** (a) migrar como estão, sem marca; (b) migrar marcados como `implicit_legacy`, preservando a data mas registrando que não houve ato do usuário; (c) descartar e exigir novo aceite de todo mundo no primeiro login.
- **Default vigente:** (b) — preserva o dado e para de mentir sobre ele.
- **Recomendação:** (b). É a única que permite responder "quem realmente aceitou?" depois, e é aditiva em relação a (c) se o jurídico pedir reaceite.


### Q-20 — Quem pode publicar uma versão de contrato?

- **Fatia:** S12
- **Trava:** trava `BE-335` e a matriz de autorização (que é **contrato aprovado**, DEC-18).
- **Impacto:** `muda comportamento observável`
- **Contexto:** A matriz aprovada dá `contracts` como **`R` para os quatro papéis** (`authorization-matrix.md:197`), derivada dos links do rodapé da sidebar e do aceite — ela descreve **ler e aceitar os Termos**. A administração (criar versão, publicar) nunca entrou na matriz porque **não tem item de menu**. **Correção ao mapa, importante:** os dois mapas afirmam que "BE-335 exige papel administrativo para publicar". Conferido na fonte, **esse gate não existe**: `app/controllers/pub/contracts_controller.rb` não tem `before_action` de autorização nenhum, zero ocorrências de `may?`/`admin?`/`og?`, e as rotas não têm constraint (`config/routes.rb:30-31`). Hoje, **qualquer usuário autenticado que acerte a URL publica uma nova versão dos Termos de Uso**. Isso reclassifica a pergunta: não é "confirmar um gate existente", é "criar o gate que nunca existiu". Levantada em dois mapas (`auth-admin` Q-B12 e `receivables` Q-B3).
- **Opções:** (a) novo recurso `contract_versions` = **CRUD para OG + Admin**, `-` para Gerente e Colaborador (o gate do grupo "Admin", onde já moram os outros recursos globais administrativos); `contracts` (ler/aceitar) fica exatamente como aprovado — total passa de 45 para 46 recursos; (b) só **OG**; (c) deixar como está no legado (qualquer autenticado).
- **Default vigente:** (a) — publicar Termos vincula **todos** os usuários; não é operação de gestor, mas também não precisa ser exclusiva do fornecedor.
- **Recomendação:** (a). E uma armadilha para não repetir: `user_is_readonly` tira C/U/D de `contract_versions`, mas **não pode** bloquear o aceite dos Termos pelo próprio usuário — senão o readonly nunca aceita e fica trancado fora do sistema.


### Q-21 — `receipts` herda o gate de `charges` ou merece linha própria na matriz?

- **Fatia:** S11 (cobranças e recibos)
- **Trava:** trava o `authorize!` das rotas de recibo.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A matriz aprovada tem `charges` como **CRUD para os quatro papéis, com escopo por projeto** (`authorization-matrix.md:139`), e **não tem linha para `receipts`**. Recibo é sub-recurso de cobrança (o candidato a recibo sai de `Charge#receipt_candidates`, `app/models/charge.rb:34-46`), então a herança é a leitura natural — mas ela não está escrita em lugar nenhum, e "por inferência" é como se perde um gate.
- **Opções:** (a) `receipts` herda explicitamente o gate de `charges` (CRUD/4 papéis, escopo por projeto), escrito na matriz como linha derivada; (b) linha própria mais restrita (por exemplo, emitir recibo só OG/Admin/Gerente); (c) deixar implícito.
- **Default vigente:** (a) — é o comportamento do legado e não tira acesso de ninguém.
- **Recomendação:** (a), com a linha escrita. O custo de escrever é zero e o custo de não escrever é alguém decidir diferente no Phase 3.


### Q-22 — Textos de ajuda dos formulários: são 91 placeholders idênticos

- **Fatia:** S6, S7, S8 (e o mecanismo em S12)
- **Trava:** não trava código — o mecanismo é portado de qualquer forma. Trava só o conteúdo.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Três arquivos YAML alimentam os tooltips dos formulários financeiros: `db/seed_assets/receivables_help_inputs.yml` (**65 chaves**), `db/seed_assets/risk_operations_help_inputs.yml` (13) e `db/seed_assets/structured_operations_help_inputs.yml` (13). **As 91 chaves têm exatamente o mesmo texto**: *"Só um teste de informações do campo pra descrever para que serve cada campo"*. São lidos em runtime pela própria view (`.../receivables/new/_body.html.erb:14`, `.../risk_operations/new/_body.html.erb:15`, `.../structured_operations/new/_body.html.erb:15`) e exibidos via tippy. **Correção ao mapa:** os mapas falavam em "~40" (recebíveis) e "26" (risco + estruturadas) — o número real é **91**, e o de recebíveis sozinho é 65. Levantada em três mapas (`data-infra` Q-06, `receivables` Q-B20, `risk` Q-R9).
- **Opções:** (a) portar o mecanismo e **sair sem tooltip** onde não houver texto (o campo não mostra o ícone); (b) portar o mecanismo com o placeholder, como no legado; (c) você (ou quem conhece o produto) escreve os 91 textos — é conteúdo de negócio sobre campos financeiros, e eu não invento.
- **Default vigente:** (a) — mostrar "Só um teste…" numa demo comercial é pior que não mostrar nada.
- **Recomendação:** (a) na entrega, com (c) priorizado só para os campos do borderô que envolvem CET e float — que são os que o operador realmente erra.


### Q-23 — Introduzir as validações de faixa que o legado não tem?

- **Fatia:** S6, S7, S8, S9
- **Trava:** trava `BE-181`, `FE-177`, `BE-199`, `BE-267` e `BE-293`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Em quatro lugares o legado aceita dado que não deveria existir. Recebível: `date` tem só `presence` (`receivable_entry.rb:13`) — 1900 e 2100 passam, e o campo é texto livre no HTML (`.../receivables/new/_body.html.erb:129`); `valor_bruto` tem só `presence` (`:18`), embora as linhas vizinhas `:19-20` usem `numericality: {greater_than: 0}` para os prazos. Renegociação: `original_value`, `total_debt` e `operation_interest_rate` têm só `presence` (`renegotiation.rb:17,18,20`) — zero, dívida negativa e taxa negativa entram. Risco e estruturadas: nenhuma validação de `due_date >= issue_date` nem de `operation_value > 0` (`risk_operation.rb:54-62`, `structured_operation.rb:13-20`). Levantada em três mapas (`receivables` Q-B11 e Q-B21, `risk` Q-R7).
- **Opções:** (a) replicar as ausências — nada é recusado que hoje entra; (b) validar tudo em registros **novos** e deixar o histórico em paz; (c) validar tudo e reportar no dry-run quantos registros históricos violam cada regra, para o cliente decidir o que fazer com eles.
- **Default vigente:** (a) — para não recusar dado que hoje o sistema aceita.
- **Recomendação:** (c). É a única que responde à pergunta que você vai fazer de qualquer jeito: "quantos registros estão assim hoje?". Se a resposta for zero, (b) vira grátis.


### Q-24 — A taxa de remuneração pode ficar fora de 0–100?

- **Fatia:** S8
- **Trava:** trava `BE-301` e `FE-305`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A taxa que multiplica **todo** o faturamento não tem validação nenhuma: `app/models/remuneration.rb:9` tem só `presence: true`, o campo do formulário não tem `min`/`max`/`pattern` (`.../remunerations/helper/_body.html.erb:30`), e a coluna é **float** (`db/migrate/20220629123512_create_remunerations.rb:6`). No recibo, o `fee` copiado também é float, com um comentário que promete a faixa e não a impõe: `db/migrate/20220802225011_create_receipts.rb:11` — `t.float :fee # taxa em % 0-100`. Ou seja, `250%` passa pela UI e a API aceita mais casas ainda.
- **Opções:** (a) replicar a ausência; (b) validar `0 <= value <= 100`; (c) validar e permitir exceção explícita acima de 100 com confirmação.
- **Default vigente:** (a) — validar passa a recusar registro que hoje o sistema aceita.
- **Recomendação:** (b), com o dry-run listando antes quantas remunerações existentes estão fora da faixa. Um typo nessa taxa fatura dez vezes a mais e nada avisa.


### Q-25 — `is_active` dos catálogos passa a filtrar de verdade?

- **Fatia:** S6 (carteiras, tipos de recebível) e S8 (fontes de recurso)
- **Trava:** trava `BE-185`, `FE-157`, `BE-308` e `DB-287`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Três catálogos gravam e exibem um interruptor "Ativado/Desativado" que **não filtra nada**. Carteiras: gravado em `wallets_controller.rb:124`, exibido em `.../wallets/helper/_body.html.erb:26`, e os selects usam `Wallet.all` (`.../receivables/_body.html.erb:44` e `.../receivables/new/_body.html.erb:75`). Tipos de recebível: idem (`receivable_kinds_controller.rb:125`; `ReceivableKind.order(title: :asc).all` em `.../receivables/new/_body.html.erb:85`). Fontes de recurso: o select é `ResourceSource.all.order(title: :asc)` (`.../receivables/new/_body.html.erb:43`), e o model **nem tem scope `active`** — pior, o valor padrão do select é `ResourceSource.first.id`, que também ignora o interruptor. É o **D-19**, levantado em dois mapas (`receivables` Q-B12, `risk` Q-R19).
- **Opções:** (a) passar a filtrar: desativado some dos selects, mas continua visível em registros antigos; (b) manter como está (o interruptor continua decorativo); (c) filtrar apenas nos formulários de criação, mantendo o item disponível na edição de registros que já o usam.
- **Default vigente:** (a) — um interruptor que não desliga nada é pior que interruptor nenhum.
- **Recomendação:** (c). É (a) sem o efeito colateral do Q-26 abaixo, que é exatamente o que acontece quando se filtra sem pensar na edição.


### Q-26 — Editar uma remuneração cujo tipo foi desativado

- **Fatia:** S8
- **Trava:** trava `FE-304`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O formulário de remuneração monta os selects com `RiskOperationType.active` e `StructuredOperationType.active` (`.../remunerations/helper/_body.html.erb:20-21`). Na edição o select fica `disabled`, mas as opções continuam vindo do `.active` — então, se o tipo tiver sido desativado, o `selected` não casa com nada e **a tela mostra o primeiro tipo ativo, não o tipo real da remuneração**. O usuário vê um dado errado sem nenhum aviso.
- **Opções:** (a) na edição, incluir o tipo atual na lista mesmo desativado, marcado como "(desativado)"; (b) recusar a edição de remuneração cujo tipo foi desativado; (c) replicar o comportamento atual.
- **Default vigente:** (a) — é o menor conserto possível e elimina um dado exibido errado.
- **Recomendação:** (a). Vale como regra geral do ai9 para todo select de catálogo com `is_active`, não só aqui.


### Q-27 — `nominal_tax` diverge das checagens calculadas: erro, alerta ou nada?

- **Fatia:** S6
- **Trava:** trava `BE-180`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O usuário informa a taxa nominal no formulário (`.../receivables/new/_body.html.erb:389`) e o sistema calcula duas checagens ao lado (`receivable_entry.rb:117-118`), exibidas somente leitura (`:397,407`). **As três nunca são comparadas** — as validações do model terminam em `receivable_entry.rb:36` e não há nenhuma. O único consumo de `nominal_tax` é ser copiada como `agreed_rate` da `RiskOperation` (`:163`), o que significa que uma taxa digitada errada viaja direto para a exposição de risco.
- **Opções:** (a) informativo, como hoje; (b) alerta na tela quando a diferença passar de um limiar (a definir), sem bloquear; (c) erro de validação, bloqueando o salvamento.
- **Default vigente:** (a) — replicar.
- **Recomendação:** (b), com o limiar vindo de você. É o campo digitado à mão que alimenta o número calculado; um alerta é barato e pega o dedo trocado.


### Q-28 — Tarifa do mesmo tipo repetida no mesmo borderô

- **Fatia:** S6
- **Trava:** trava `FE-175`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Não há `validates_uniqueness_of` em `app/models/receivable_tax.rb`, o servidor faz um loop cego sobre as tarifas recebidas (`receivables_controller.rb:80-86` e `:105-115`) e o formulário deixa acrescentar quantas linhas quiser do mesmo tipo (`.../receivables/new/_body.js.erb:506-535`). As duas linhas somam no mesmo bucket (`receivable_entry.rb:42-45`, `taxes.where(is_iof: 1).pluck(:value).sum`), então o resultado é aritmeticamente coerente — mas o operador não tem como perceber que digitou o IOF duas vezes.
- **Opções:** (a) permitir, como hoje; (b) bloquear duplicata do mesmo tipo; (c) permitir com aviso na tela ("IOF já lançado nesta operação").
- **Default vigente:** (a) — pode haver caso legítimo de duas linhas do mesmo tipo com descrições diferentes.
- **Recomendação:** (c). Bloquear pode recusar um lançamento válido; avisar não recusa nada e resolve o caso real, que é o duplo clique.


### Q-29 — Excluir tarifa já gravada tem efeito imediato, mesmo se o usuário cancelar

- **Fatia:** S6
- **Trava:** trava `FE-176`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O botão de remover tarifa persistida (`.../receivables/new/_body.html.erb:484`) dispara um `DELETE` direto assim que o usuário confirma o modal (`.../receivables/new/_body.js.erb:663-681`, linha 674), **fora de qualquer submit do borderô**. O servidor apaga (`receivable_taxes_controller.rb:15-24`) e **não recalcula o borderô pai** — os agregados `tarifas_*` só se corrigem no próximo save do recebível. Ou seja: cancelar a edição não desfaz a exclusão, e entre a exclusão e o próximo save o borderô fica com totais desatualizados.
- **Opções:** (a) manter o efeito imediato, mas **recalcular o borderô na hora**; (b) postergar a exclusão até o salvamento do borderô (o formulário passa a ter estado pendente); (c) replicar exatamente, inclusive os totais desatualizados.
- **Default vigente:** (b) — é o que o usuário espera de um botão dentro de um formulário com "Salvar".
- **Recomendação:** (b). E (a) como piso inegociável, caso você prefira manter o imediato: um total que fica errado até alguém salvar de novo não pode sobreviver à migração.
### Q-30 — Datas de operação: a tela trava, a API aceita

- **Fatia:** S7 e S8
- **Trava:** trava `FE-260` e `FE-297`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Na edição de uma operação existente, os campos de data aparecem como `readonly` e, pior, **nem são os campos reais** — a view renderiza `issue_date_fake` e `due_date_fake` (`.../risk_operations/new/_body.html.erb:146,153` e `.../structured_operations/new/_body.html.erb:117,124`). Mas o `permit` do controller aceita `issue_date` e `due_date` no update (`risk_operations_controller.rb:227,230` e `structured_operations_controller.rb:164,168`). Em risco isso **fura o `RiskOperationExtension`**, que é o caminho oficial de prorrogação e o único que deixa rastro.
- **Opções:** (a) alinhar pelo servidor — as datas passam a ser imutáveis no update, e prorrogação só pela extensão; (b) alinhar pela API — o campo vira editável na tela também; (c) replicar a divergência.
- **Default vigente:** (a) — a UI expressa a intenção, e a API estar aberta é o furo, não a regra.
- **Recomendação:** (a). Uma data de vencimento que muda sem gerar extensão é exatamente o histórico que ninguém consegue reconstituir depois.


### Q-31 — Trocar a empresa de uma operação estruturada move a operação de projeto em silêncio

- **Fatia:** S8
- **Trava:** trava `BE-291`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/structured_operation.rb:36` faz `self.project_id = self.company.project_id` num `before_validation` **sem `on:`**, ou seja, também no update. `company_id` é editável no formulário (`.../structured_operations/new/_body.html.erb:53`) e permitido no controller (`structured_operations_controller.rb:161`). Trocar a empresa move a operação para outro projeto **sem aviso e sem log** — e pode invalidar remuneração e recibo já emitidos. O mesmo padrão existe em `risk_operation.rb:28`.
- **Opções:** (a) proibir a troca de empresa depois da criação (é o que o `projects` já decidiu para empresa→projeto, DC-04); (b) permitir com confirmação explícita e evento na trilha de auditoria; (c) replicar o comportamento atual.
- **Default vigente:** (a) — mover uma operação de projeto arrasta escopo, cobrança e recibo.
- **Recomendação:** (a). Se o caso de uso existir de verdade, ele merece um fluxo próprio com revalidação, não um select de formulário.


### Q-32 — Operação encerrada continua candidata a cobrança

- **Fatia:** S8
- **Trava:** trava `BE-306`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/remuneration.rb:26` monta os candidatos a recibo filtrando **só** por projeto, tipo de operação e `receipt_id: nil` — sem olhar `is_ended` nem `due_date`. Os scopes `available_for_receipt` (`risk_operation.rb:2`, `structured_operation.rb:10`) também são só `receipt_id: nil`. Isso alimenta `Charge#receipt_candidates` (`charge.rb:34-46`) e a tela de cobrança (`charges_controller.rb:24`). Uma operação marcada como encerrada continua aparecendo para faturar.
- **Opções:** (a) manter como está; (b) excluir operações encerradas da lista de candidatos; (c) mantê-las na lista, marcadas como "encerrada", e o operador decide.
- **Default vigente:** (a) — pode haver cobrança legítima de operação já encerrada.
- **Recomendação:** (c). É a resposta que não perde faturamento nem esconde informação — e depende do Q-15, porque é a mesma pergunta sobre o que "encerrar" significa.


### Q-33 — A busca de operações estruturadas ignora número de contrato e empresa

- **Fatia:** S8 (e S7, pelo mesmo motivo)
- **Trava:** trava `BE-281`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `structured_operations_controller.rb:30` busca por `carriers.title` e `structured_operations.title`, e nada mais — apesar de o `joins(:company)` já estar ali (`:22`) e de portador **e empresa** aparecerem lado a lado na tabela (`.../structured_operations/_body.html.erb:63`). O `contract_number` nem é buscável, embora seja chave de ordenação (`structured_operation.rb:82-83`). Empresa só se filtra por dropdown (`:27`). O mesmo acontece em risco (`risk_operations_controller.rb:30`).
- **Opções:** (a) replicar a busca como está; (b) ampliar para incluir `contract_number` e `companies.title` nas duas telas.
- **Default vigente:** (a) — ampliar é mudança visível que ninguém pediu.
- **Recomendação:** (b). Uma busca que não acha pelo que está escrito na coluna ao lado é lida como bug pelo usuário, não como escopo — e numa demo isso aparece.


### Q-34 — Renomear o indicador reescreve o histórico dos lançamentos

- **Fatia:** S10
- **Trava:** trava `BE-322` e `DB-310`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Cada `IndicatorEntry` guarda cópia de `title`, `key` e `value_type` do indicador (`indicator_entry.rb:23-27`). E um `after_save` no indicador faz `self.entries.update_all({title:, key:, value_type:})` (`app/models/indicator.rb:48-50`) — **sem callbacks, sem validação, atingindo todos os lançamentos de todos os projetos**. Renomear o indicador em 2026 faz o lançamento de 2023 dizer que sempre se chamou assim. Existe até um `Indicator.fix_titles` (`indicator.rb:88-92`) que dispara isso em massa. É o **D-70**, a mesma família do D-30 (Q-17).
- **Opções:** (a) foto do momento — o lançamento guarda o nome que o indicador tinha na época, e renomear **não** reescreve nada; (b) derivar sempre do indicador atual (a cópia desaparece e o lançamento nunca mente sobre o presente); (c) replicar o `update_all`.
- **Default vigente:** (a) — se a coluna existe e é copiada, a intenção era congelar; o `update_all` é que a contradiz.
- **Recomendação:** (b). É a única que não obriga a decidir "qual dos dois nomes é o certo" — e o nome de um indicador é rótulo, não dado histórico. Se o negócio quiser o histórico, (a); mas então o `update_all` tem que morrer.


### Q-35 — Na grade de indicadores, "não lançado" e "lançado como zero" são o mesmo `0`

- **Fatia:** S10
- **Trava:** trava `FE-326`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A grade instancia um `IndicatorEntry.new` quando não há lançamento (`.../indicator_entries/list/_widget.html.erb:14`) e renderiza `value: entry.value.blank? ? 0 : entry.value` nas quatro variantes (`:27,:32,:52,:57`). Como a coluna tem default `0.0`, ausência e zero saem idênticos — e nem a cor distingue (positivo verde, negativo vermelho, zero e vazio ambos neutros). Existe um `beauty_value` que devolveria `"N/A"` para entrada sem id (`indicator_entry.rb:29-33`) e **a grade não o usa**. É a leitura mais usada do módulo. **Verificado e relevante:** a grade **não tem nenhuma linha ou coluna de total** (`grep -i total` na pasta = 0), então distinguir os dois **não muda nenhuma soma** — muda só a célula.
- **Opções:** (a) distinguir: célula vazia (ou `—`) para não lançado, `0` para zero lançado — o `beauty_value` já existe para isso; (b) manter os dois como `0`; (c) distinguir e ainda destacar visualmente as células não lançadas do mês corrente.
- **Default vigente:** (a) — é a mesma disciplina do D-117 (`format_money` renderiza nulo como R$ 0,00): num sistema financeiro, campo nulo e campo zerado não podem ser indistinguíveis.
- **Recomendação:** (a), e o custo é usar um método que o legado já escreveu e esqueceu de chamar.


### Q-36 — O título do indicador continua em CAIXA ALTA sem acento?

- **Fatia:** S10
- **Trava:** trava `BE-321`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/indicator.rb:39` faz `self.title = I18n.transliterate(self.title).upcase` num `before_validation` **sem `on:`** — ou seja, em todo save, e duplicado em `:43` no callback de criação. `I18n.transliterate` remove o acento e `.upcase` força a maiúscula; a `key` deriva do mesmo (`:44`). É irreversível: os acentos originais **já se perderam no dado legado**, então "re-humanizar" seria adivinhação.
- **Opções:** (a) replicar (o título continua "RECEITA LIQUIDA"); (b) parar de transformar em títulos **novos**, deixando os antigos como estão (a tela passa a misturar dois estilos); (c) parar de transformar e passar a exibir o título com capitalização de apresentação, sem alterar o dado.
- **Default vigente:** (a) — mudar mistura estilos numa grade que o cliente olha todo mês.
- **Recomendação:** (c). Guarda o dado como está e resolve a aparência na camada certa, sem inventar acento nenhum.


### Q-37 — Reconectar um indicador recupera o histórico: é o desejado?

- **Fatia:** S10
- **Trava:** trava `BE-710`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/project_indicator_connection.rb` (9 linhas) não tem `dependent:` nem callback nenhum, e desconectar só destrói a linha de conexão (`project_indicator_connections_controller.rb:87-91`). Os lançamentos sobrevivem porque estão presos ao **indicador**, não à conexão (`indicator.rb:4`, `has_many :entries, dependent: :delete_all`). Reconectar recria a conexão (`:80-86`) e a grade reencontra tudo intacto.
- **Opções:** (a) replicar (desconectar esconde, reconectar traz de volta); (b) desconectar passa a apagar os lançamentos daquele projeto; (c) desconectar arquiva os lançamentos explicitamente, com aviso na tela do que vai acontecer.
- **Default vigente:** (a) — é conservador e não perde dado.
- **Recomendação:** (a) com o aviso de (c) na tela. O comportamento está certo; o que falta é a tela dizer que os lançamentos ficam guardados.


### Q-38 — Dois itens de menu chamados "Indicadores"

- **Fatia:** S2 (menu) e S10
- **Trava:** trava `FE-324`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/helpers/application_helper.rb:113` põe "Indicadores" no grupo **Gestão** (são os **lançamentos**) e `:142` põe "Indicadores" no grupo **Cadastro** (é o **catálogo**). Rótulo idêntico, telas diferentes. Há ainda um terceiro, esse distinguível: "Indicadores específicos" no grupo Projeto (`:131`). Os títulos de aba do navegador também colidem em parte (`console_controller.rb:353`).
- **Opções:** (a) "Indicadores" (catálogo) e **"Lançamentos de indicadores"** (gestão); (b) "Cadastro de indicadores" e "Indicadores"; (c) replicar os dois rótulos iguais.
- **Default vigente:** (a).
- **Recomendação:** (a). Custo zero e resolve um item que, numa demo, o cliente clica errado na primeira tentativa.


### Q-39 — `resource_kinds` e `resource_sources` são indistinguíveis

- **Fatia:** S8
- **Trava:** depende do Q-61 (se `resource_kinds` for descartado, esta pergunta desaparece).
- **Impacto:** `muda comportamento observável`
- **Contexto:** **Correção ao mapa.** O mapa afirma que os dois têm "o mesmo rótulo de menu e o mesmo título de aba". Conferido: o **título de aba é idêntico byte a byte** — `"Safegold - Tipos de Recursos"` para os dois (`console_controller.rb:348-349` e `:358-359`) — mas **rótulo de menu só existe para `resource_sources`** (`application_helper.rb:153`); `resource_kinds` **não tem item de menu nenhum** e só é alcançável digitando a URL. Os títulos das próprias páginas diferem por **uma letra**: "Tipos de Recurso" (`.../resource_kinds/_body.html.erb:3`) contra "Tipos de Recursos" (`.../resource_sources/_body.html.erb:3`).
- **Opções:** (a) se os dois sobreviverem, renomear — por exemplo "Naturezas de recurso" (`resource_kinds`) e "Fontes de recurso" (`resource_sources`); (b) manter os nomes atuais; (c) fundir os dois cadastros num só.
- **Default vigente:** (a) — mas só se aplica se o Q-61 mantiver `resource_kinds`.
- **Recomendação:** (a), com os nomes vindos de você: qual é a diferença de negócio entre os dois é a informação que falta, e o código não a tem.


### Q-40 — Renegociação: `provider_name` no detalhe, `title` na lista

- **Fatia:** S9
- **Trava:** trava `FE-196`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A lista de renegociações identifica cada linha por `r.title` em negrito (`.../renegotiations/list/_widget.html.erb:6`), com `provider_name` só como subtítulo (`:8`). Mas o detalhe grava o **`provider_name`** no histórico do navegador (`.../renegotiations/detail/_body.js.erb:87-91`), então o título da aba e o "voltar" mostram outra coisa. O cabeçalho do detalhe exibe os dois (`.../detail/_body.html.erb:10` e `:11`).
- **Opções:** (a) `title` prevalece em tudo (lista, aba, cabeçalho); (b) `provider_name` prevalece; (c) título composto ("`title` — `provider_name`").
- **Default vigente:** (a) — é o que a lista usa, e a lista é por onde o usuário entra.
- **Recomendação:** (c) na aba do navegador e (a) na tela. Quem tem várias renegociações abertas em abas precisa distinguir pelo fornecedor.


### Q-41 — URLs públicas de contrato com espaço e com erro de acento

- **Fatia:** S12
- **Trava:** trava `BE-331` e `FE-335`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O tipo do contrato viaja **cru na URL**, em português, com espaço e com o typo consolidado: `@@KIND__PRIVACY_POLICY = "Politicas de Privacidade"` (sem acento em "Políticas", `app/models/contract.rb:14`), e a rota recebe a string como parâmetro (`config/routes.rb:48`). No HTML aparece escapado — `/contract/Termos%20de%20Uso` e `/contract/Politicas%20de%20Privacidade` (`.../sign_up/_sign_up.html.erb:61`) — e interpolado com espaço literal no menu do console (`.../base/menu/_container.html.erb:37,40`) e em "Minha Conta" (`.../my_account/parts/essential/_container.html.erb:119,122`). Essas URLs existem em links externos.
- **Opções:** (a) adotar slug (`/contratos/termos-de-uso`, `/contratos/politica-de-privacidade`) com **redirect 301** das strings antigas, inclusive a com o typo; (b) preservar a string literal, typo incluído; (c) slug sem redirect.
- **Default vigente:** (a).
- **Recomendação:** (a). O redirect é barato e é o que impede que um link em contrato assinado ou em e-mail antigo pare de funcionar.


### Q-42 — O ETL do legado atribuiu todos os borderôs antigos ao usuário 1 e à empresa 1

- **Fatia:** S14
- **Trava:** trava `OPS-150`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O importador força a autoria: `app/models/legacy/receivable_entry.rb:65` — `user_id: 1, # forçado mestre dos magos` — e `:67` — `company_id: 1 # forçado por questão de portabilidade`. Todo borderô importado aparece como criado pela mesma pessoa e pertencente à mesma empresa. **Correções ao mapa:** (1) **não é um ETL Django** — é um módulo Ruby dentro do próprio Rails (`app/models/legacy.rb:1-111`, `establish_connection :sfg_legacy`, tabela `fbordero`); não há uma linha de Python no repositório; (2) a janela **não é 2016-2021** — o importador não filtra data (`legacy.rb:96` faz `klazz.all.each`) e o dump versionado tem registros também em 2022.
- **Opções:** (a) manter a atribuição como está (autoria e empresa "1" para ~62 mil registros); (b) reatribuir a partir do dado original do legado, se ele existir no dump; (c) manter e marcar explicitamente como "importado" — sem autor e sem empresa atribuída, em vez de atribuir a pessoa errada.
- **Default vigente:** (a) — o número não muda e a demo roda com seed próprio.
- **Recomendação:** (c). Atribuir a autoria de 62 mil borderôs a uma pessoa que não os criou é dado errado que ninguém consegue distinguir de dado certo depois.
### Q-43 — Contratos: vale o texto do repositório ou a linha que está no banco?

- **Fatia:** S12, semeada por S14
- **Trava:** trava o seed de contratos e o que o usuário lê no dia 1.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O legado carrega o texto dos contratos de arquivos versionados — `db/seeds.rb:113-116` referencia `privacy.html` e `tou.html` em `db/seed_assets/contracts/` — mas o texto que vale em produção é o que está gravado em `action_text_rich_texts` (`app/models/contract.rb:11`, `has_rich_text :description`), editável pelo console. Os dois podem ter divergido a qualquer momento nos últimos anos, e não há como saber qual foi aceito (ver Q-58).
- **Opções:** (a) semear a partir do arquivo versionado **apenas se não houver contrato no banco**, preservando o que já existe; (b) sobrescrever sempre com o arquivo versionado; (c) importar o texto do banco e ignorar os arquivos.
- **Default vigente:** (a) — preserva o que está no ar e não perde o que foi editado pelo console.
- **Recomendação:** (a). E vale conferir o diff entre as duas versões no dry-run: se divergirem muito, é sinal de que alguém editou pelo console e o repositório ficou para trás.

### Q-44 — Qual é a cor primária da marca?

- **Fatia:** transversal (o `theming-brand-engineer` roda antes de qualquer tela) e S17
- **Trava:** trava a paleta do produto inteiro. Não pode ser inferida do código.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Há **quatro** valores vivos ao mesmo tempo, em camadas diferentes, e um quinto de fallback. `#2D2D2A` está em `app/definitions/SFG/theme.rb:32` (`COLOR__PRIMARY`) e — verificado — **nunca é lido por nada**. `#050517` está em `app/frontend/css/pub/colors.scss:1` (`$primary`) e é o que **de fato compila** para `.primary-color` (`:103-108`). `#373435` é o que a factory grava no banco (`db/factories/app_theme_factory.rb:17`, apontando para `COLOR__ACCENT_INVERSE` em `theme.rb:28`). `#504746` está em `engines/ux_kit19/lib/livetat/ux_kit19/configuration.rb:14`. E quando `primary_color` é nulo, `app/models/app_theme.rb:200-201` cai em `#444444`. Como o motor de temas não pintava nada (o CSS inteiro está dentro de um comentário, `app/frontend/css/pub/templates/app_theme_template.css:1-167`), **nem o valor do banco chegava à tela**.
- **Opções:** (a) `#2D2D2A` (o valor canônico declarado, e o que o `brand-and-metadata.md` já registra); (b) `#050517` (o que o usuário de fato vê hoje, porque é o que compila); (c) você fornece o hex oficial da marca.
- **Default vigente:** (a), com confirmação **visual contra o app rodando** feita pelo `theming-brand-engineer`.
- **Recomendação:** (c) se existir manual de marca; senão (b), porque é a cor que o cliente reconhece como "o sistema dele". `#2D2D2A` e `#050517` são visualmente muito diferentes — isto não é detalhe.

### Q-45 — O login por Facebook continua existindo?

- **Fatia:** S1
- **Trava:** nada — só muda quem consegue entrar.
- **Impacto:** `muda comportamento observável`
- **Contexto:** No legado está morto por duas pontas: `app/definitions/SFG/metadata.rb:4-5` tem `FACEBOOK_APP_ID = 0` e `FACEBOOK_APP_SECRET = 0`, e **não existe nenhum botão de Facebook em nenhuma view** — o formulário de login (`.../sign_in/_sign_in.html.erb:12-43`) tem só login/senha. Os handlers JS ficaram órfãos, ligados a um seletor que nunca casa (`.../sign_in/_sign_in.js.erb:22,30`), e o provider Devise segue declarado (`engines/auth_omni19/app/decorators/user_decorator.rb:2`). É o **D-41**. No ai9, o login social **funciona** e vem com Google junto.
- **Opções:** (a) manter ligado no ai9 (custo zero, já existe) e anunciar na tela; (b) manter ligado e **não** anunciar até você confirmar; (c) desligar os dois provedores sociais.
- **Default vigente:** (b).
- **Recomendação:** (b), e provavelmente (c) para o Facebook: com **DEC-14** (entrada por código de e-mail ou WhatsApp) e **DEC-18.7** (só por convite), um provedor social a mais é uma superfície de identidade a mais para pouco ganho.

### Q-46 — ETL: o que acontece com `is_active` e com `legacy_password`?

- **Fatia:** S14
- **Trava:** trava a carga de usuários — define quem consegue entrar no dia 1.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O importador do legado copia a senha antiga para uma coluna `legacy_password` e ainda inventa uma senha determinística a partir do primeiro nome + `#6230` (`app/models/legacy/u.rb:28` e `:30`). O `is_active` vem do sistema Django antigo e nunca ficou claro se `0` significa "conta desligada" ou "nunca ativada". O ai9 não tem senha nenhuma (DEC-14: entrada por código), e o bloco de auth já decidiu que o bloqueio de conta vira `users.blocked_at` (DC-07).
- **Opções:** (a) `is_active = 0` nasce com `blocked_at` preenchido e o usuário sai numa **lista de exceções** para revisão humana antes do cutover (mesmo tratamento do papel vazio, DEC-18 #8); `legacy_password` **não é migrado**; (b) `is_active = 0` nasce ativo (assumindo "nunca ativado") — todos entram; (c) `is_active = 0` não é migrado de forma alguma.
- **Default vigente:** (a) — bloquear e revisar é reversível; liberar por engano não é.
- **Recomendação:** (a). E `legacy_password` não deve nem chegar ao banco novo: é hash de um sistema que não existe mais, num produto sem senha.

### Q-47 — Alguém entra hoje digitando **username** em vez de e-mail?

- **Fatia:** S14 (dry-run) e S1
- **Trava:** é um possível **bloqueador de cutover**, não de código.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O legado autentica por uma chave genérica: `engines/auth19/config/initializers/devise.rb:14` define `authentication_keys = [:login]`, e a resolução aceita os dois — `engines/auth19/app/models/livetat/auth/user.rb:108`: `where(["lower(username) = :value OR lower(email) = :value", …])`. O próprio campo anuncia: `placeholder="user ou e-mail"` (`.../sign_in/_sign_in.html.erb:22`). Há inclusive um caminho JSON alternativo por `user_name` (`engines/auth_ux19/.../sessions_controller.rb:86-88`). No ai9, a identificação é por **e-mail ou telefone** — quem só sabe o próprio `username` perde o acesso no dia 1.
- **Opções:** (a) assumir que ninguém usa e seguir; (b) o dry-run **conta** quantos usuários têm `username` e não têm e-mail válido, e o número decide; (c) portar `username` como identificador alternativo no ai9.
- **Default vigente:** (b) — se houver algum, isto vira bloqueador de cutover.
- **Recomendação:** (b). É uma consulta no dump e responde de vez; (c) só se o número for grande, porque acrescenta uma terceira chave de identidade a uma base compartilhada.

### Q-48 — "Verificação: {nível}" — o telefone verificado volta a existir?

- **Fatia:** S1
- **Trava:** trava o desenho do indicador de confiabilidade do perfil.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O nível é calculado numa escada de quatro degraus (`engines/auth19/app/models/livetat/auth/user_info.rb:53-74`) e o degrau mais alto — "Máxima" — depende **só** de `is_phone_checked` (`:59`). Só que **não existe fluxo de verificação de telefone no legado**: a única forma de a flag virar 1 é mass-assignment pelo formulário (`app/decorators/controllers/registrations_decorator.rb:104`), e, uma vez ligada, ela **trava o campo de telefone para sempre** (`.../my_account/parts/phone/_container.js.erb:14-16`, `prop('readonly')`). Ou seja: o degrau máximo é inalcançável e o campo fica preso sem saída. No ai9 o telefone **é verificado de verdade** — é canal de login (DEC-14). **Resolvido na fonte, e por isso não pergunto separado:** o mapa perguntava também se o nível decide alguma regra de negócio. Não decide: a única leitura fora da exibição é `app/decorators/models/user_decorator.rb:272`, que expõe `nice_info` num JSON. Nenhum limite, aprovação ou gate depende dele.
- **Opções:** (a) marcar como verificado quando a pessoa entrar por código de WhatsApp/SMS naquele número, e o campo deixa de travar sem saída; (b) remover o indicador de confiabilidade inteiro (ele não decide nada); (c) replicar como está — degrau máximo inalcançável, campo travado.
- **Default vigente:** (a).
- **Recomendação:** (a). O ai9 torna verdadeiro um indicador que no legado era decorativo, e o custo é zero porque a verificação já acontece no login.

### Q-49 — Onde ficam os arquivos em produção?

- **Fatia:** S18 (plataforma), com efeito em S9 (anexos de renegociação) e S13
- **Trava:** não trava a demo. **Trava o cutover.**
- **Impacto:** `muda comportamento observável`
- **Contexto:** A base ai9 só tem serviço de disco local: `backend/config/storage.yml` define apenas `local` e `test`, e `backend/config/environments/production.rb:10` usa `:local`. Em container sem volume persistente garantido pelo deploy, **anexo desaparece entre deploys** — avatar, logo e, principalmente, os documentos de renegociação. No legado tudo vive em `public/system/:attachment/:id/…` no disco da máquina, via kt-paperclip (11 anexos, 44 colunas). Levantada em dois mapas (`auth-admin` Q-B5, `data-infra` Q-07).
- **Opções:** (a) `Disk` com volume persistente garantido pelo deploy; (b) S3 (ou compatível), configurado antes do cutover; (c) `Disk` para a demo e a decisão de provedor fica como item obrigatório do runbook de cutover.
- **Default vigente:** (c).
- **Recomendação:** (b) para o cutover — documento financeiro privado em disco de container é o tipo de decisão que só aparece quando o arquivo já sumiu. Para a demo, (c) serve.

### Q-50 — Com DEC-14 (sem senha), o que dizem os e-mails "Perdeu a senha?" e "Nova senha configurada"?

- **Fatia:** S1
- **Trava:** trava `BE-481` e `BE-482`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** São dois e-mails cujo assunto e corpo falam de uma coisa que o produto **não tem mais**: o ai9 não tem senha em lugar nenhum (DC-01 do bloco de auth verificou: nenhuma coluna `encrypted_password`, `devise :omniauthable` e nada mais). Mas os gatilhos continuam fazendo sentido: "pedi um novo acesso" e "minha credencial mudou".
- **Opções:** (a) preservar os gatilhos e **reescrever os textos** ("Seu código de acesso" / "Seu acesso foi alterado"), registrando no `improvements-log`; (b) não portar os dois e-mails; (c) portar os textos como estão.
- **Default vigente:** (a).
- **Recomendação:** (a). Um e-mail que fala de senha num produto sem senha é o tipo de detalhe que o cliente nota numa demo.

### Q-51 — A precedência de papel do importador estava invertida — reprocessamos?

- **Fatia:** S14
- **Trava:** trava `BE-453` e o de-para de papéis no ETL.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/legacy/u.rb:29` decide o papel com um ternário aninhado: `o.role_type = i.is_staff ? ::U.MANAGER : i.is_superuser ? ::U.ADMIN : ::U.COLAB`. A marca de **equipe** é avaliada primeiro, então quem era `is_staff = true` **e** `is_superuser = true` foi importado como **Gerente**, nunca como Admin. Se isso aconteceu, há usuários em produção com papel rebaixado desde a importação — e é justamente o papel que a matriz do DEC-18 vai passar a **aplicar de verdade**.
- **Opções:** (a) não reprocessar; o dry-run **lista** os usuários nessa condição para revisão humana antes do cutover (mesma disciplina do DEC-19); (b) reprocessar automaticamente, promovendo quem tinha `is_superuser`; (c) ignorar (o papel atual é o papel válido).
- **Default vigente:** (a).
- **Recomendação:** (a). Promover papel automaticamente num sistema de crédito é exatamente o tipo de mudança que ninguém quer descobrir depois — e a lista custa uma consulta.

### Q-52 — O mapeamento de gênero está certo?

- **Fatia:** S14 e S1
- **Trava:** trava `FE-432` e a migração de `user_infos.gender`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/helpers/application_helper.rb:15-20` monta a concordância assim: `1` devolve `"a"` (feminino), `2` devolve `""` (neutro) e **qualquer outro valor, incluindo `nil` e `0`, devolve `"o"`** (masculino). A coluna é `integer` sem default e sem validação de domínio (`engines/auth19/db/migrate/20171020133117_create_livetat_user_infos.rb:7`). Ou seja: **quem nunca preencheu o campo é tratado como homem** em todo texto do sistema.
- **Opções:** (a) migrar os valores como estão e usar formulação **neutra** quando desconhecido — nunca masculino por padrão; (b) replicar o fallback masculino; (c) migrar como estão e perguntar o gênero no primeiro acesso.
- **Default vigente:** (a).
- **Recomendação:** (a). O dado migra intacto e o texto para de afirmar uma coisa que ninguém informou.

### Q-53 — Na tela de mensagens, pedir "Concluído" grava "Fechado"

- **Fatia:** S2
- **Trava:** trava `BE-527`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Os dois estados existem e são distintos (`engines/feedback19/app/models/livetat/feedback19/state.rb:11-12`). No `update`, escolher "Concluído" no select grava **"Fechado"**: `engines/feedback19/app/controllers/livetat/feedback19/messages_controller.rb:118-119` — `if message_params[:state_id].to_i == State.done.id then @message.state_id = State.closed.id`. **Achado que o mapa não tinha:** a inversão é dupla. A action chamada `close` (`:156-159`, rota `PUT /messages/:id/close`) grava **"Concluído"**. Os dois estados estão trocados **entre si**, não é um typo num lado só.
- **Opções:** (a) corrigir os dois — "Concluído" grava Concluído, "Fechar" grava Fechado; (b) replicar a inversão; (c) fundir os dois estados num só (a distinção nunca foi usada de forma coerente).
- **Default vigente:** (a), com linha no `improvements-log.md` porque é comportamento observável.
- **Recomendação:** (a). Com a inversão nos dois sentidos, "alguém se acostumou com o comportamento atual" deixa de ser plausível: não há comportamento coerente com que se acostumar.

### Q-54 — O envio anônimo de mensagem de feedback é usado?

- **Fatia:** S2
- **Trava:** trava `BE-531` e a allowlist pública de rotas.
- **Impacto:** `muda comportamento observável`
- **Contexto:** No legado o `POST` de mensagem é **público de propósito**: `engines/feedback19/app/controllers/livetat/feedback19/messages_controller.rb:6` isenta explicitamente o `create` da autenticação por token. A action não referencia `current_user` (`:85-105`). O único filtro restante, `lock_if_its_not_a_valid_client_app`, faz **bypass total** quando o formato é HTML ou JS (`engines/auth_ux19/.../application_controller.rb:21-27`) — e o console usa `format: :js`, então na prática não bloqueia nada. Vale lembrar que o próprio `api/root.rb:14-17` da base ai9 registra que um bypass por header já vazou a base inteira até 01/08/2026.
- **Opções:** (a) só autenticado; (b) público, mas **por rota na allowlist**, com throttle do Rack::Attack e captcha; (c) público sem throttle (como hoje).
- **Default vigente:** (a) — e, se o anônimo for necessário, (b).
- **Recomendação:** (a). Com o cadastro público desligado (DEC-18.7), não sobra visitante legítimo para usar o canal anônimo.

### Q-55 — O autopreenchimento por CNPJ (ReceitaWS) volta a funcionar?

- **Fatia:** S4 (empresas e fornecedores)
- **Trava:** nada — é um botão.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O backend está **vivo e configurado**: gem no `Gemfile.linux:39`, `config/initializers/receitaws.rb:5` (token), `:10` (cache de 365 dias), `:14` (timeout de 10 s), serviço em `app/helpers/cnpj_api.rb:3` e endpoint em `app/controllers/pub/providers_controller.rb:121-133`. A UI está **duplamente morta**: o botão está comentado (`.../providers/helper/_body.html.erb:54-56`) e a URL do JS tem ERB escapado (`.../providers/helper/_body.js.erb:155` usa `<%%=`, então o literal `<%= … %>` chega ao navegador). É o **D-27**, e a integração é paga. **Nota de segurança que sai junto:** o token real está versionado no repositório (`config/application.arch.yml:12`) e precisa ser rotacionado de qualquer forma.
- **Opções:** (a) ligar (o endpoint existe, o custo é reconectar o botão); (b) não portar; (c) ligar com limite de chamadas por usuário/dia, por causa do custo por consulta.
- **Default vigente:** (a).
- **Recomendação:** (c). É a mesma feature, com a única precaução que o legado não tinha — e o custo por consulta é seu, não nosso.

### Q-56 — O logo do Portador volta a existir?

- **Fatia:** S3 (cadastros globais)
- **Trava:** nada.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Está morto por metade: o bloco HTML do upload está comentado no formulário (`.../carriers/helper/_body.html.erb:13-23`, com o `file_field` na linha 21) e a exibição está comentada na lista (`.../carriers/list/_widget.html.erb:3-12`) — mas o handler JS está vivo, ligado a um input que não existe (`.../carriers/helper/_body.js.erb:12-13`), o `permit` aceita `logo` (`carriers_controller.rb:140`) e o model tem o anexo completo, com validações (`app/models/carrier.rb:16,32-33,79-80`). É o **DC-10**. **Nota de conferência:** o mapa fala em "os outros dois logos"; na fonte são **projeto** (`project.rb:48`, `avatar`) e **fornecedor** (`provider.rb:12`, `logo`) — **`Company` não tem anexo nenhum**.
- **Opções:** (a) ligar, reusando a mesma pilha ActiveStorage dos outros dois; (b) não portar; (c) ligar e acrescentar também logo de empresa (feature nova).
- **Default vigente:** (a).
- **Recomendação:** (a). É um campo, a coluna já existe, e o dry-run precisa contar quantos portadores têm arquivo antes de migrar binários.

### Q-57 — A coluna `default_position` existe no banco de produção?

- **Fatia:** S11 (padrões de disponibilidade)
- **Trava:** nada para começar; é uma consulta no dump.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/controllers/pub/availability_templates_controller.rb:22` ordena a busca por `default_position`, e a coluna aparece também em três views (`.../availability_templates/list/_child_widget.html.erb:4,40` e `.../projects/detail/connection_template/list/_widget.html.erb:4`). **Nenhuma migration a cria** — as migrations criam `position` e `parent_position` (`db/migrate/20210420180734_create_availability_templates.rb:22,24`). Se a coluna **não** existe, a busca de padrões globais está quebrada em produção há anos e ninguém reclamou; se **existe**, é a segunda prova de schema fora do versionamento (junto com `contracts.description`, D-108) e o **DEC-04** precisa ser revisitado com o dump em mãos. **Achado adjacente na mesma action:** a linha `:21` monta o `where!` com o fragmento SQL malformado (`"title #{Dev.ilike} "` sem o placeholder) — a busca por texto tem um segundo problema, independente da coluna.
- **Opções:** (a) assumir que não existe; a busca nasce ordenada pela hierarquia e registra-se para o dry-run confirmar; (b) rodar `\d availability_templates` no dump agora e decidir com o fato; (c) criar a coluna no ai9 de qualquer forma.
- **Default vigente:** (a).
- **Recomendação:** (b). Você tem o dump desde 25/08 (DEC-15.3) e a consulta leva um minuto — e ela também fecha o DEC-04, que hoje carrega o risco como "aceito e documentado".

---

## `muda escopo` — Q-58 a Q-86

### Q-58 — Qual é a prova mínima exigida de um aceite?

- **Fatia:** S12
- **Trava:** trava `DB-331` e `OPS-333`, e é pré-requisito de `BE-342`/`BE-343` (tolerância de 30 dias e bloqueio).
- **Impacto:** `muda escopo`
- **Contexto:** `contract_deals` guarda hoje **`user_id`, `contract_id`, `created_at` e `updated_at`** e nada mais (`db/migrate/20180405164055_create_contract_deals.rb:3-8`). Sem IP, sem user-agent, sem versão congelada e sem impressão do texto — e como o texto vive em `action_text_rich_texts` (`app/models/contract.rb:11`, `has_rich_text :description`) e pode ser editado no próprio registro, **não há garantia técnica de qual conteúdo foi aceito**. É o **D-65**.
- **Opções:** (a) manter o mínimo atual (usuário + contrato + data); (b) acrescentar IP, user-agent e **hash imutável do texto** no momento do aceite; (c) (b) + versionamento imutável do documento (nova versão = nova linha, edição proibida).
- **Default vigente:** (b) — é a recomendação técnica, mas o mínimo probatório é definição jurídica, não de engenharia.
- **Recomendação:** (c). Sem versão imutável, o hash prova o texto mas não prova qual versão estava publicada — e é justamente isso que se pergunta num litígio.


### Q-59 — Existe estado de baixa, liquidação ou vencimento do recebível?

- **Fatia:** S6
- **Trava:** trava `BE-178`.
- **Impacto:** `muda escopo`
- **Contexto:** O recebível tem **um** campo de estado e ele só assume dois valores: `"OK"` e `"Diferença"` (`app/models/entry.rb:10-12`), atribuídos em `receivable_entry.rb:115` a partir da diferença de valor presente. Não há `enum`, `aasm` nem máquina de estados; não há coluna de baixa, de liquidação nem de vencimento; e a tela só exibe esse carimbo, somente leitura (`.../receivables/new/_body.html.erb:448`). É o **D-19**. Ou a ausência é real (o borderô é registro de operação, não de cobrança) ou falta uma funcionalidade inteira.
- **Opções:** (a) replicar — o borderô continua sem ciclo de vida; (b) construir o ciclo (baixa, liquidação, vencimento) — é feature nova, contra DEC-09; (c) replicar e registrar como lacuna conhecida no ledger, para o pós-venda.
- **Default vigente:** (a)/(c) — DEC-09 manda portar o que existe.
- **Recomendação:** (c). Se o cliente controla baixa em planilha hoje, esse é o item de maior valor do pós-venda — e vale saber agora, não depois.

### Q-60 — `is_title` e `is_liquidation` em `movement_kinds`: campos vivos ou resíduo?

- **Fatia:** S6
- **Trava:** trava `BE-186`.
- **Impacto:** `muda escopo`
- **Contexto:** **Correção ao mapa.** O mapa trata os dois como igualmente órfãos; conferido, **só `is_title` é**. `is_title` aparece apenas no CRUD (`movement_kinds_controller.rb:126`, `.../movement_kinds/helper/_body.html.erb:48`), no importador (`app/models/legacy/movement_kind.rb:16`), no seed (`db/seeds.rb:206-222`) e na migration — nenhuma regra o lê. Já `is_liquidation` **tem consumidor**: `app/models/movement_kind.rb:14` faz `txks = [is_advalorem, is_desagio, is_iof, is_liquidation].sum` e valida a exclusividade mútua entre os quatro (`:13-18`). Ele não entra em cálculo de tarifa, mas é regra de negócio ativa. Nota relacionada: `receivable_taxes` **não** tem `is_liquidation`, embora `movement_kinds` tenha (D-B13).
- **Opções:** (a) portar os dois como estão (`is_liquidation` com a validação, `is_title` como coluna sem consumidor); (b) portar `is_liquidation` e descartar `is_title` com evidência no ledger; (c) descartar os dois.
- **Default vigente:** (a) — DEC-09 e o mesmo raciocínio do DC-16: pode haver consumidor externo.
- **Recomendação:** (b). `is_liquidation` fica porque é regra viva; `is_title` sai com evidência, e voltar é aditivo.

### Q-61 — `resource_kinds`: portar ou descartar?

- **Fatia:** S6 e S8 — são **9 IDs** (`BE-307`, `BE-720..724`, `DB-286`, `DB-289`, `DB-294`, `FE-307`)
- **Trava:** trava o escopo de S8. Um `SELECT COUNT(*)` resolve.
- **Impacto:** `muda escopo`
- **Contexto:** A entidade tem CRUD completo (controller, views, rotas) e é **inalcançável pelo menu**: `app/helpers/application_helper.rb:153` só tem `resource_sources`; `resource_kinds` só abre digitando a URL. A coluna `receivable_entries.resource_kind_id` existe (`db/migrate/20210315183541_create_receivable_entries.rb:11`) e está no `permit` (`receivables_controller.rb:191`), mas **não há campo no formulário** e `receivable_entry.rb` **não declara `belongs_to :resource_kind`** — o único lado da associação é o inverso, em `resource_kind.rb:2`, com `restrict_with_error`. Os dois flags da entidade (`is_conta_corrente`, `is_unique`) não têm nenhum leitor de regra. E ela **não participou da importação**: `app/models/legacy.rb:2-15` lista `ResourceSource` e não `ResourceKind`. Levantada em dois mapas (`receivables` Q-B17, `risk` Q-R5).
- **Opções:** (a) rodar `SELECT COUNT(*) FROM receivable_entries WHERE resource_kind_id IS NOT NULL` no dump — zero significa `dropped` com evidência, e S8 encolhe 9 IDs; (b) portar tudo por precaução; (c) descartar sem consultar.
- **Default vigente:** (a) — não descarto 9 IDs sem o número, nem porto 9 IDs por nada.
- **Recomendação:** (a). É a mesma consulta que resolve Q-39 (os nomes indistinguíveis): se `resource_kinds` cai, aquela pergunta desaparece junto.

### Q-62 — `receivable_entries.observacoes`: campo visível, fundido ou descartado?

- **Fatia:** S6
- **Trava:** trava `DB-155`.
- **Impacto:** `muda escopo`
- **Contexto:** A coluna existe (`db/migrate/20210315183541_create_receivable_entries.rb:43`) e está no `permit` (`receivables_controller.rb:223`), mas **não há input no formulário** e nenhuma view a lê. Tem até tooltip órfão no YAML de ajuda (`db/seed_assets/receivables_help_inputs.yml:35`). O **único escritor real** é o importador: `app/models/legacy/receivable_entry.rb:56` grava `observacoes: i.bor_obs` — ou seja, **há texto de negócio gravado ali que ninguém nunca viu na tela**.
- **Opções:** (a) tornar o campo visível (ele já tem conteúdo vindo do sistema antigo); (b) fundir com `description`; (c) descartar.
- **Default vigente:** (a) — há dado real dentro.
- **Recomendação:** (a). Um campo de observação importado do sistema anterior e invisível há anos é justamente o tipo de coisa que o cliente pergunta "cadê?" na primeira semana.

### Q-63 — Renomear anexo de renegociação entra no escopo?

- **Fatia:** S9
- **Trava:** trava `BE-228`.
- **Impacto:** `muda escopo`
- **Contexto:** A funcionalidade foi pretendida e **nunca entregue**. `app/controllers/pub/renegotiation_attachments_controller.rb:51` chama `@renegotiation_attachment.update_attributes(renegotiation_params)` — com **dois** erros na mesma linha: `renegotiation_params` não existe neste controller (só `renegotiation_attachment_params`, `:104`), e `update_attributes` foi removido no Rails 6.1. O `respond_to` da action está inteiramente comentado (`:54-59`). Nunca funcionou.
- **Opções:** (a) não portar (DEC-09: não existe); (b) implementar — é uma tela de renomear, custo baixo; (c) não portar agora e registrar no ledger como intenção não concluída.
- **Default vigente:** (c).
- **Recomendação:** (c). Nome de anexo importa em documento de renegociação, mas a decisão é sua: o legado nunca ofereceu isso a ninguém.

### Q-64 — A aba PAGAMENTOS da renegociação entra no escopo?

- **Fatia:** S9
- **Trava:** trava `FE-229`.
- **Impacto:** `muda escopo`
- **Contexto:** A aba está comentada na view (`.../renegotiations/detail/_body.html.erb:22`) e a lista de abas só declara "GERAL" e "PREVISÕES" (`:15`) — é o **D-53**, a causa de o painel não fechar. O botão "Excluir todas as parcelas" também está comentado (`.../detail/tabs/_tab_renegotiation_installment.html.erb:11-15`). Mas o **backend dos dois continua vivo e órfão**: `renegotiations_controller.rb:76` e `:125` (`show_remove_all_option`), `renegotiation.rb:61-70` (`batch_destroy_installments!`), e o JS que mostra/esconde um botão que não existe (`.../detail/_body.js.erb:34,37`).
- **Opções:** (a) portar a aba PAGAMENTOS (o backend está pronto) e **não** portar o botão de excluir em massa; (b) portar os dois; (c) não portar nenhum dos dois.
- **Default vigente:** (a) — a aba fecha um buraco visível no painel; excluir todas as parcelas de uma renegociação sem transação é operação destrutiva que ninguém pediu.
- **Recomendação:** (a). Se o excluir em massa for necessário, ele volta como ação explícita com confirmação e trilha — não como botão comentado que alguém descomenta.

### Q-65 — Pagamento de renegociação sem forma de pagamento nem conciliação

- **Fatia:** S9
- **Trava:** trava `DB-192`.
- **Impacto:** `muda escopo`
- **Contexto:** A tabela guarda apenas `renegotiation_id`, `renegotiation_installment_id`, valor, data, `days_late`, `payment_number`, `late_payment_value` e `total_paid_value` (`db/migrate/20210324174615_create_renegotiation_payments.rb:3-11` + `20210426130102_...` + `20220429122419_...`). **Nenhuma coluna de método, banco, documento ou conciliação.** O model confirma (`app/models/renegotiation_payment.rb:1-28`).
- **Opções:** (a) replicar (ausência intencional — o registro é de valor recebido, e a conciliação vive no banco); (b) acrescentar forma de pagamento como campo livre; (c) acrescentar forma + referência de conciliação bancária (feature nova).
- **Default vigente:** (a), por DEC-09.
- **Recomendação:** (a) nesta entrega. Conciliação bancária é subsistema, não campo — e se for necessária, merece escopo próprio.

### Q-66 — O percentual de aceite por contrato volta?

- **Fatia:** S12
- **Trava:** trava `BE-344`.
- **Impacto:** `muda escopo`
- **Contexto:** Está comentado nos **dois** únicos lugares em que aparecia: na lista (`.../contracts/list/_widget.html.erb:18`, *"Aceito por X dos usuários"*) e no detalhe (`.../contracts/detail/_body.html.erb:66`). O método que o calcula, `Contract#accept_users` (`app/models/contract.rb:23-25`), ficou sem nenhum chamador ativo. Não há comentário explicando por que foi desligado — pode ter sido performance (a conta é um `count` sobre `contract_deals`) ou pode ter sido por estar errada.
- **Opções:** (a) reativar, com a contagem feita em consulta e não em Ruby; (b) não portar; (c) reativar só no detalhe, não na lista (onde o custo por linha se multiplica).
- **Default vigente:** (b) — está comentado em produção e não sei por quê.
- **Recomendação:** (c). É a informação que dá sentido a ter um ciclo de aceite (Q-18), e no detalhe o custo é uma consulta por página.

### Q-67 — Tipos de contrato configuráveis pela UI?

- **Fatia:** S12
- **Trava:** trava `BE-339` e `OPS-332`.
- **Impacto:** `muda escopo`
- **Contexto:** Hoje os tipos são **literais em código**: `app/models/contract.rb:13-14` define as duas constantes e `:18-21` fecha a lista em `self.contract_kinds`. Não há CRUD de tipos; o formulário só oferece esse array. E existe um terceiro documento planejado e nunca ativado: `db/seed_assets/contracts/user.html` (20 bytes) — **nenhum seed o carrega** (`db/seeds.rb:113-116` só referencia `privacy.html` e `tou.html`), o que sugere um "contrato de adesão" que ficou pelo caminho.
- **Opções:** (a) manter os dois tipos fixos em código; (b) tornar os tipos configuráveis por cadastro; (c) manter fixos e acrescentar o terceiro tipo ("Contrato de adesão") se você confirmar que ele é necessário.
- **Default vigente:** (a).
- **Recomendação:** (a). Tipo de contrato muda uma vez por década; cadastro configurável para isso é complexidade que se paga todo dia por um ganho que quase nunca chega.

### Q-68 — O `balance` da operação estruturada deveria evoluir?

- **Fatia:** S8
- **Trava:** **bloqueia** o desenho de E1. É a diferença entre portar uma tela e construir um subsistema.
- **Impacto:** `muda escopo`
- **Contexto:** `app/models/structured_operation.rb:38` faz `self.balance = self.original_balance` num `before_validation` **sem `on:`** — ou seja, editar só a observação **zera o saldo de volta ao inicial**. A linha `:37` ainda força `original_balance` a ser negativo. E **nada no legado inteiro dá baixa nele**: não existe `StructuredMovement` — nem model, nem migration, nem tabela. `balance` só é escrito nessa linha e aceito no `permit` (`structured_operations_controller.rb:167`); todo o resto é ordenação (`:88-89`) e exibição. É o **D-73**. Ou falta uma feature inteira (baixa/liquidação de operação estruturada), ou a coluna é decorativa.
- **Opções:** (a) replicar o reset exatamente, cobrir com golden, e documentar a coluna como decorativa; (b) construir movimentação de operação estruturada, espelhando o que existe em risco (`RiskMovement`) — é subsistema novo; (c) remover a coluna da tela, já que ela nunca reflete nada além do valor inicial.
- **Default vigente:** (a).
- **Recomendação:** (a) na entrega. Mas esta é a pergunta que mais vale a pena você responder do bloco de estruturadas: se alguém dá baixa nessas operações fora do sistema, o produto tem um buraco que nenhuma migração conserta.

### Q-69 — A posição diária de risco (`RiskEntry`) volta?

- **Fatia:** S7 (a fatia R8 fica bloqueada sem resposta)
- **Trava:** trava `BE-269`, `DB-231` e `FE-234`.
- **Impacto:** `muda escopo`
- **Contexto:** A tabela e as regras estão vivas, mas **não existe nenhuma view** — não há `app/views/pub/risk_entries` nem `.../parts/risk_entries`, e o controller aponta para templates inexistentes (`risk_entries_controller.rb:6,29,39,47,56`), com as rotas ainda no ar (`config/routes.rb:163-164`). **Correção ao mapa:** não há "item de menu comentado" — **não há item de menu nenhum**; o que está comentado é a **aba** (`.../risk/_body.html.erb:30` e `_body.js.erb:32`) e o handler do botão "Cadastrar posição", renderizado com classe `deactive` (`.../risk/_body.html.erb:22`, handler em `_body.js.erb:34-40,127-134`). O problema de fundo: os **15 campos são hardcode dos 4 tipos originais** (Auto Liquidável, Fomento, Comissária, Intercompany — `db/migrate/20210510211736_create_risk_entries.rb:7-15`, `20220321180205_...:3-8`, `20220325145251_...:3-5`) e **não acompanham o `RiskOperationType` dinâmico** que existe desde 2022. Portar a tela como está entrega algo que não funciona com os tipos atuais.
- **Opções:** (a) portar tabela e model (o dado sobrevive) e deixar a fatia R8 **sem tela**, bloqueada; (b) remodelar por tipo dinâmico e entregar a tela — é feature nova; (c) descartar tudo com evidência.
- **Default vigente:** (a).
- **Recomendação:** (a), com uma consulta no dump: se `risk_entries` estiver vazia, isto vira (c) e a fatia some.

### Q-70 — Alerta de estouro de limite em tempo real entra?

- **Fatia:** S5
- **Trava:** nada — é escopo novo.
- **Impacto:** `muda escopo`
- **Contexto:** Confirmado na fonte: **o legado não faz polling em nenhuma tela deste bloco** e não renderiza gráfico nenhum (`vendor/doughnut` é pendurado no `global` em `app/frontend/vendor/js/index.js.erb:31,37` e **zero views o instanciam**; `grep "new Chart"` também é vazio). Logo, um alerta de estouro de limite é **feature nova** (DEC-09), não cumprimento do Princípio 10. Menciono porque é o candidato mais natural que o produto tem: o painel de risco existe, os limites existem, o cálculo de utilização existe.
- **Opções:** (a) não entra; (b) entra como aviso na própria tela quando a utilização passa do teto (custo baixo, o número já é calculado); (c) entra com notificação ativa (e-mail/WhatsApp) — subsistema novo.
- **Default vigente:** (a) — e coerente com **DEC-21.1**, que explicitamente deixou "utilização de limite" para depois da venda.
- **Recomendação:** (a). O `NEW-002` (dashboard) já mostra "limites próximos do teto", então a demo cobre a ideia sem abrir uma frente nova.

### Q-71 — `is_on_variable` ("Considerar no variável") — o que era isso?

- **Fatia:** S8 (e S7)
- **Trava:** trava `BE-295`.
- **Impacto:** `muda escopo`
- **Contexto:** É persistido, exibido no formulário e **nenhum cálculo do legado o lê**. Ocorrências completas: `permit` (`risk_operations_controller.rb:232`, `structured_operations_controller.rb:170`), formulário (`.../risk_operations/new/_body.html.erb:217,219` e `.../structured_operations/new/_body.html.erb:179,181`), cópia na renovação (`risk_operation.rb:131`) e as duas migrations. **Zero leituras** em cálculo, filtro, escopo ou relatório. O nome sugere uma remuneração variável que não existe no sistema.
- **Opções:** (a) portar como marca comercial (grava e exibe, como hoje); (b) descartar com evidência; (c) descobrir com o negócio o que era e implementar.
- **Default vigente:** (a) — mesmo raciocínio do `has_bi` (DC-16): pode haver consumidor externo, e manter custa uma coluna.
- **Recomendação:** (a) até você responder (c). Se a remuneração variável era feita em planilha, o campo é a pista de que alguém queria trazê-la para dentro.

### Q-72 — Os 4 flags de `structured_operation_types` migram?

- **Fatia:** S8
- **Trava:** trava `BE-297` e `DB-283`.
- **Impacto:** `muda escopo`
- **Contexto:** **Correção ao mapa.** O mapa diz que os quatro são "aceitos pelo `permit`, ausentes do formulário, sem consumidor". Os dois primeiros fatos estão certos (`structured_operation_types_controller.rb:132-135`; o formulário só tem título, chave e `is_active`). O terceiro não: **`is_default` e `has_pre_faturamento` têm consumidor também no lado estruturado** — `is_default` em `structured_operation_type.rb:11` (`before_destroy`), no controller (`:99`) e na listagem (`.../structured_operation_types/list/_widget.html.erb:23`); `has_pre_faturamento` em `.../structured_operations/list/_widget.html.erb:16,22`, onde **esconde as datas da listagem**. Realmente órfãos no lado estruturado são só `allow_manual_operations` e `allow_receivable_entries` (que, no lado de **risco**, são scopes centrais — `risk_operation_type.rb:2-3`).
- **Opções:** (a) migrar os quatro; (b) migrar `is_default` e `has_pre_faturamento` (que têm consumidor) e descartar os outros dois **do tipo estruturado**, mantendo-os no tipo de risco; (c) migrar os quatro e **expor** os relevantes no formulário, que hoje não os mostra.
- **Default vigente:** (a).
- **Recomendação:** (c) para `has_pre_faturamento`: hoje ele nunca pode virar `1` pela UI, mas se virar por outro caminho a listagem de estruturadas **passa a esconder as datas** — um comportamento que ninguém consegue explicar depois.

### Q-73 — Excluir lançamento de indicador é feature viva?

- **Fatia:** S10
- **Trava:** trava `BE-328`.
- **Impacto:** `muda escopo`
- **Contexto:** A rota existe (`config/routes.rb:84`, `resources :indicator_entries`) e a action também (`indicator_entries_controller.rb:75-85`), mas **nenhuma tela a chama**: zero ocorrências de excluir/remover/`data-method: :delete` em toda a pasta de views de lançamentos. O controller nem tem o template do formulário que renderiza em `:34` e `:42`. Na prática, "zerar" é digitar `0` no campo inline e submeter — o registro continua existindo.
- **Opções:** (a) não portar a exclusão (só zerar, como hoje); (b) portar a exclusão com confirmação; (c) portar como "limpar lançamento", que apaga de verdade e passa a distinguir de zero (casa com o Q-35).
- **Default vigente:** (a).
- **Recomendação:** (c), **se** o Q-35 for respondido com "distinguir". As duas perguntas são a mesma moeda: só faz sentido apagar um lançamento se "não lançado" for visualmente diferente de "zero".

### Q-74 — O indicador precisa de tipos além de "Dinheiro"?

- **Fatia:** S10
- **Trava:** trava `BE-715`.
- **Impacto:** `muda escopo`
- **Contexto:** Só existe um tipo, e o próprio código diz por quê: `app/models/indicator.rb:24-35` define `VALUE_TYPE__MONEY = "Dinheiro"` como **único** valor de `self.value_types`, com o comentário *"prevendo expansão futura para tipos diferentes de indicadores, no momento usamos apenas o tipo dinheiro, sendo forçado"*. Não há campo no formulário nem no `permit`; é forçado na criação (`:45`) e usado só para formatação (`indicator_entry.rb:35-37`).
- **Opções:** (a) só "Dinheiro", como hoje; (b) acrescentar percentual e quantidade (a estrutura já foi desenhada para isso); (c) acrescentar sob demanda depois.
- **Default vigente:** (a), por DEC-09.
- **Recomendação:** (a) com (c) planejado. Se o cliente acompanha inadimplência em % ou volume em unidades, hoje ele grava isso como "dinheiro" — e vale perguntar antes de a demo mostrar um R$ na frente de um percentual.

### Q-75 — Existe consumidor externo dos headers `X-LAA-Agent` / `X-LAA-Token`?

- **Fatia:** S1
- **Trava:** trava a decisão de descartar o contrato de token da engine (`BE-004`).
- **Impacto:** `muda escopo`
- **Contexto:** O par de headers é definido em `engines/auth19/lib/livetat/auth/configuration.rb:15-16` e validado por inteiro em `engines/auth_ux19/.../application_controller.rb:16-17,23-25` (via `Auth::ClientApplication.find_through_token`). Mas os dois controllers de API do próprio app leem **só o token**, sem o agent: `app/controllers/api_application_controller.rb:7` e `app/controllers/api_private_application_controller.rb:7`. Só você sabe quem chama essa API de fora — descartar um contrato vivo quebra um consumidor que não está neste repositório.
- **Opções:** (a) descartar o contrato de token de usuário (o JWT o substitui) e **manter** `ClientApplication` funcionando por `Authorization: Bearer`; (b) manter os dois headers durante um período de transição, com prazo definido; (c) descartar tudo.
- **Default vigente:** (a).
- **Recomendação:** (a), mas a resposta é sua: se houver app móvel ou integração externa, precisamos do prazo de transição antes do cutover, não depois.

### Q-76 — A área de temas existe no ai9 como CRUD, ou a marca vira configuração?

- **Fatia:** S17 (a fatia inteira depende desta resposta)
- **Trava:** trava `S17` inteira — pode economizar a fatia.
- **Impacto:** `muda escopo`
- **Contexto:** O motor de temas do legado **não pinta nada**: o CSS do template está integralmente dentro de um comentário — `app/frontend/css/pub/templates/app_theme_template.css`, 167 linhas, abre `/*` na linha 1 e fecha `*/` na 167, sem uma única regra fora dele (**D-55**). E o parser continua rodando em cima disso: `app_theme.rb:207-231` lê o arquivo, substitui as variáveis de cor e grava em `cached_css`, que as views injetam num `<style>` (ex.: `.../sign_in/_sign_in.html.erb:55`) — sempre um comentário CSS inteiro. Além disso a área **não tem item de menu** (zero ocorrências de "themes" em `application_helper.rb` e no `_container.html.erb` do menu) e o `else` do `fetch_resource` redireciona para `dash` (`console_controller.rb:402-405`) — **D-63**. Na prática, o tema só controlava logos e o branding de 3 e-mails. Levantada em dois mapas (`auth-admin` Q-B9, `data-infra` Q-12).
- **Opções:** (a) implementar a área completa (CRUD de tema, precedência, tokens em runtime), como o inventário pede; (b) **não** portar a tela: marca e paleta viram tokens do app, light/dark fica no `ThemeToggle` que já existe no ai9, e S17 encolhe para "marca em fonte única"; (c) meio-termo: tema como **configuração única** editável (uma tela, um tema), sem CRUD nem precedência.
- **Default vigente:** divergem entre os dois mapas — `auth-admin` propõe (b), `data-infra` propõe (a). **Preciso da sua palavra.**
- **Recomendação:** (c). Multi-tema num sistema de um cliente só é complexidade sem uso; mas o cliente vai querer trocar o logo sem abrir um chamado.

### Q-77 — `UserTheme` (tema por usuário): requisito abandonado ou feature a ressuscitar?

- **Fatia:** S17
- **Trava:** trava `BE-379` e metade de `BE-380`.
- **Impacto:** `muda escopo`
- **Contexto:** O tipo existe de verdade: `app/models/user_theme.rb:2` declara `has_many :users` e a coluna está criada (`db/migrate/20200206191948_add_app_theme_column_to_livetat_auth_user.rb:3`). Mas o `select` do formulário oferece **apenas** `GlobalTheme` (`.../themes/form/_body.html.erb:36` e `.../themes/helper/_body.html.erb:16`) — `UserTheme` **nunca aparece em nenhuma opção** e é inalcançável pela UI. Só `GlobalTheme` é referenciado em runtime.
- **Opções:** (a) portar o **tipo** (a coluna e o STI, porque pode haver dado) e **não** expor a criação de `UserTheme` na UI — igual ao legado; (b) descartar o tipo inteiro; (c) implementar tema por usuário de verdade.
- **Default vigente:** (a).
- **Recomendação:** (b), **se** o Q-76 for respondido com (b) ou (c). Portar um STI para um subtipo que nunca teve UI é carregar complexidade de graça; e no ai9 a preferência por usuário já existe como light/dark.

### Q-78 — `generic_rating` (avaliação por estrelas) é usado em alguma tela?

- **Fatia:** S19 / S2
- **Trava:** trava `BE-013` do inventário de componentes.
- **Impacto:** `muda escopo`
- **Contexto:** **Correção ao mapa.** O mapa trata como componente possivelmente vivo. Conferido: só existe o **CSS** — `app/frontend/css/pub/recyclable/generic_rating.scss` (classe `.app_rating_widget`), importado em `recyclable.scss:7`. **Zero ocorrências** de `app_rating_widget` ou `generic_rating` em qualquer `.erb`, `.rb` ou `.js` do repositório. Não há model, controller, rota nem partial. É CSS morto, provável resquício de outro produto da Livetat.
- **Opções:** (a) descartar com evidência no ledger; (b) portar o componente para a biblioteca do ai9 mesmo sem consumidor.
- **Default vigente:** (a).
- **Recomendação:** (a). Com a evidência acima, não há nem o que discutir — e se aparecer uso, é um componente pequeno de recuperar.

### Q-79 — A citação aninhada em respostas de mensagem (`quoted_note_id`) é usada?

- **Fatia:** S2
- **Trava:** trava `DB` da tabela de notas do feedback.
- **Impacto:** `muda escopo`
- **Contexto:** O backend está completo e vivo: `engines/feedback19/app/models/livetat/feedback19/note.rb:6` (`belongs_to :quoted`), a lógica que deriva `top_parent_quote_id` (`:17-23`), o `permit` (`notes_controller.rb:90`) e a coluna (`db/migrate/20170516185759_create_livetat_feedback_notes.rb:9`). Mas a UI **nunca a preenche**: zero ocorrências de `quoted` em qualquer view ou JS do engine ou do app. Nenhum campo, hidden input ou parâmetro AJAX a envia.
- **Opções:** (a) não portar a citação aninhada (uma coluna e uma associação a menos numa tabela nova); (b) portar o esquema sem UI; (c) portar com UI (feature nova).
- **Default vigente:** (a).
- **Recomendação:** (a). Acrescentar depois é aditivo e não quebra nada — e uma thread de mensagens interna raramente precisa de citação aninhada.

### Q-80 — Mantemos Google Analytics no console?

- **Fatia:** S18
- **Trava:** trava `OPS` de analytics e o CSP.
- **Impacto:** `muda escopo`
- **Contexto:** Hoje é injetado **na primeira linha de cada entrypoint, sem nenhum consentimento**: `.../console/_index.js.erb:1`, `.../start/_index.js.erb:1`, `.../users/sessions/_new.js.erb:1` e `.../contracts/_index.js.erb:2` (este sem nem o guard de deduplicação). E está **quebrado**: o ID é GA4 (`GOOGLE_ANA_APP_ID = "G-7E78XXZX5X"`, `app/definitions/SFG/metadata.rb:7`) mas o snippet é Universal Analytics — carrega `analytics.js` e chama `ga('create', …)` (`app/views/livetat/analytics/_google.js.erb:1-8`). Um ID `G-` não funciona com `ga()`: **na prática não coleta nada hoje**. Levantada em dois mapas (`auth-admin` Q-B15, `data-infra` Q-09).
- **Opções:** (a) não injetar; usar a camada de analytics própria do ai9 se for preciso; (b) portar desligado por configuração, com o snippet GA4 correto pronto para ligar; (c) portar ligado e corrigido.
- **Default vigente:** (a)/(b) — nenhuma paridade real se perde ao remover, porque nada é coletado hoje.
- **Recomendação:** (a). Sistema interno corporativo com dado financeiro mandando telemetria de uso para terceiro é decisão do **cliente**, não nossa — e o custo de ligar depois é um script.

### Q-81 — O item de menu `reports` entra?

- **Fatia:** S2
- **Trava:** trava `NAV`.
- **Impacto:** `muda escopo`
- **Contexto:** **Correção ao mapa, e ela muda a pergunta.** O mapa descreve `reports` como um item de menu marcado `inactive`. Conferido: (1) não está no helper — está na **view** do menu, `app/views/pub/console/base/menu/_container.html.erb:24`, como `<%= 'inactive' if i[:identifier] == "reports" %>`; (2) **o item nem existe** — a lista é montada em `application_helper.rb:103-171` e nenhum item tem `identifier: "reports"`, então a condição nunca é verdadeira; (3) não há rota, controller nem `when "reports"` no `fetch_resource`. É código morto guardando um identificador fantasma. O item mais próximo, `{ identifier: "results", title: "Resultados" }`, está **comentado** em `application_helper.rb:118`.
- **Opções:** (a) não portar nada (nem o item, nem o mecanismo `inactive`); (b) portar o mecanismo de item inativo, sem item marcado; (c) descobrir o que era "Relatórios"/"Resultados" e escopar.
- **Default vigente:** (a).
- **Recomendação:** (a), e vale a pergunta lateral: havia uma tela de **Resultados** planejada (`application_helper.rb:118`, comentada). Se o cliente sente falta de relatórios, isso é escopo de pós-venda, não paridade.

### Q-82 — A tabela `geolocations` tem linhas?

- **Fatia:** S19
- **Trava:** um `SELECT count(*)` decide **9 IDs de uma vez**: `DB-592`, `DB-431`, `DB-480`, `BE-435..440`, `OPS-481`, `OPS-621`, `OPS-482`, `FE-483`, `OPS-483`.
- **Impacto:** `muda escopo`
- **Contexto:** O model existe e é grande (`app/models/geolocation.rb`, com cálculo de distância via Geocoder em `:164-171`), mas **nenhum model declara `has_one`/`has_many :geolocation`** — zero resultados no repositório inteiro. E `geolocatable` só aparece dentro do próprio `geolocation.rb` (`:6,7,9,175`) e na migration (`db/migrate/20160302002809_create_geolocations.rb:4`). A associação polimórfica **não tem lado inverso nenhum**.
- **Opções:** (a) rodar a contagem no dump — vazia significa `drop` de 9 IDs e S19 encolhe; (b) portar por precaução; (c) descartar sem consultar.
- **Default vigente:** (b) — assumi que há dado e mapeei como `build?`.
- **Recomendação:** (a). É a consulta de melhor retorno da lista inteira: um número, nove IDs decididos.

### Q-83 — Trilha de auditoria com geolocalização: implementar a intenção ou descartar?

- **Fatia:** S19
- **Trava:** trava `BE-433`.
- **Impacto:** `muda escopo`
- **Contexto:** Existe uma assinatura que aceita coordenadas para recalcular distância — `app/controllers/api/v1/trackings_controller.rb:39-45` lê `params[:lat]` e `params[:lng]` (`:40`) e atribui em `@tracking.geolocation.ref_lat`/`ref_lng` (`:42-43`). Só que a action está **quebrada em três frentes**: `@tracking` nunca é carregado (o `fetch_tracking` de `:54-56` está **vazio** e nem é registrado como `before_action`), `Tracking` **não declara** associação `geolocation` (`app/models/tracking.rb`), e nada é salvo nem recalculado. O recálculo real vive em `geolocation.rb:164-171`, fora do alcance desse controller. É uma feature **nunca entregue**, só a assinatura existe.
- **Opções:** (a) descartar o caminho morto e implementar só o detalhe do evento; (b) implementar a intenção (evento de trilha com coordenadas); (c) descartar e registrar no ledger com a evidência.
- **Default vigente:** (a)/(c) — DEC-09 diz "só o que existe", e isto não existe.
- **Recomendação:** (c). Vale registrar junto o achado colateral: `GET /api/v1/trackings` parte de `Tracking.all` **sem escopo nenhum** (D-110), e isso **tem** veredito `corrigir`.

### Q-84 — O aviso de "atualização em andamento" vale para quais entidades?

- **Fatia:** S13
- **Trava:** trava `FE-482` e o número de canais Action Cable.
- **Impacto:** `muda escopo`
- **Contexto:** Só `Project` implementa `has_ongoing_job?` (`app/models/project.rb:145`), e `data-ongoing` é emitido **num único lugar** (`.../projects/list/_widget.html.erb:1`). Mas **7 outros widgets leem `data("ongoing")`** e recebem sempre `undefined`: garantias de projeto, recebíveis, operações estruturadas, renegociações, operações de risco, padrões de disponibilidade e empresas (todos na linha 10 do respectivo `list/_widget.js.erb`). É bloco morto — parece intenção não concluída.
- **Opções:** (a) implementar só para as entidades que de fato têm job (projeto e template de disponibilidade), registrando o resto como intenção não concluída; (b) implementar para as 8; (c) não portar o mecanismo.
- **Default vigente:** (a).
- **Recomendação:** (a). Um indicador de "processando" em tela que nunca processa nada é ruído, e a infra de Action Cable custa por canal.

### Q-85 — Tipos de garantia: você quer, e qual é o conteúdo?

- **Fatia:** S3
- **Trava:** trava `DB-558` e o seed de referência.
- **Impacto:** `muda escopo`
- **Contexto:** A tabela existe (`db/migrate/20220627125208_create_project_guarantee_types.rb`) e **nenhum seed a popula** — zero ocorrências de "guarantee" em `db/seeds.rb`, nenhuma referência em `db/factories/`. Mas a UI e o backend dependem dela: CRUD completo (`project_guarantee_types_controller.rb`), o select do formulário de garantias é alimentado por `ProjectGuaranteeType.all` (`project_guarantees_controller.rb:52`), e há item de menu (`application_helper.rb:157`). Resultado no legado: **o select de tipo de garantia sobe vazio** até alguém cadastrar à mão pelo console. Não há nada a migrar — o conteúdo é novo e é seu.
- **Opções:** (a) portar só o mecanismo e semear **tipos plausíveis** no seed de demo, marcados como provisórios; (b) portar o mecanismo e subir vazio, como o legado; (c) você fornece a lista de tipos de garantia reais.
- **Default vigente:** (a).
- **Recomendação:** (c) se você tiver a lista — numa demo, um select de garantias vazio na tela de projeto é exatamente onde o cliente vai clicar. (a) é o plano B.

### Q-86 — Teremos acesso ao disco do servidor legado?

- **Fatia:** S14
- **Trava:** trava a migração de **arquivos** (não a de registros).
- **Impacto:** `muda escopo`
- **Contexto:** São **11 anexos** (44 colunas de paperclip) vivendo em `public/system/:attachment/:id/…` **no disco da máquina do legado** — avatar de usuário, imagem de `Picture`, anexo de renegociação, logo de fornecedor e de portador, avatar de projeto e os 4 arquivos de tema (`app/models/{picture,provider,project,carrier,app_theme,renegotiation_attachment}.rb` + `user_decorator.rb:11-13` + `engines/auth19/.../user.rb:4-6`). O path é configurado inline em cada model, não num initializer. Sem acesso a esse disco, **os arquivos não migram** — só os registros, que passam a apontar para nada. É dependência externa, como o dump.
- **Opções:** (a) construir o ETL de arquivos com o caminho parametrizado e testar contra o seed de demo; o passo real fica no runbook de cutover; (b) obter uma cópia do diretório `public/system/` antes do cutover; (c) aceitar a perda dos binários históricos.
- **Default vigente:** (a).
- **Recomendação:** (b) marcado como pré-requisito de cutover. Anexo de renegociação é documento financeiro — perder o binário e manter o registro é pior que não migrar.

---

## `só interno` — Q-87 a Q-98

### Q-87 — Por quanto tempo guardamos IP e user-agent das tentativas de login?

- **Fatia:** S1
- **Trava:** nada — só muda a política de retenção.
- **Impacto:** `só interno`
- **Contexto:** **Correção ao mapa, e ela inverte a origem do problema.** O mapa diz que "o legado guardava IP e nunca exibia, sem política". Conferido: **o legado não tem essa tabela** — zero ocorrências de `login_attempt`/`LoginAttempt` em `app/`, `lib/`, `config/`, `db/migrate/` e nos engines. O único rastro de login é o contador `failed_attempts` do Devise (`engines/auth19/db/migrate/20160409121830_create_users.rb:16`), sem IP e sem user-agent. Quem tem a tabela é a **base ai9**: `backend/db/schema.rb:451-460` cria `login_attempts` com `identifier`, `method`, `ip_address` (`inet`), `user_agent`, `success`, `error_reason` e `user_id`, com 9 índices — e **nenhum job de expurgo**. Ou seja: não é um passivo herdado do legado, é um passivo que o Safegold **adota** ao nascer sobre a base.
- **Opções:** (a) 90 dias, com job de expurgo (`sidekiq-cron` já está no Gemfile e o bloco de cron está vazio); (b) 180 dias; (c) retenção indefinida, como está hoje na base.
- **Default vigente:** (a) — suficiente para investigar incidente, curto o bastante para não virar passivo de LGPD.
- **Recomendação:** (a). E vale registrar como flag de upstream: a tabela é da base compartilhada, então a política ideal é decidida uma vez para todos os sistemas.

### Q-88 — Guardamos o corpo de todo e-mail enviado?

- **Fatia:** S13
- **Trava:** nada.
- **Impacto:** `só interno`
- **Contexto:** No legado, `livetat_mailer_contacts` guarda `sender`, `target`, `target_name`, `subject`, `message` e `type` (`engines/mailer19/db/migrate/20160409121840_...:3-12`), e a coluna `message` foi **promovida de `string` para `text` justamente para caber o corpo** (`20170519223014_...` + `20170519223026_...`). Cada envio grava o corpo antes de enfileirar (`engines/mailer19/lib/livetat/mailer19/grind_mailer.rb:5-13`, e igualmente `:27,47,67,85`, mais 4 pontos em `engines/feedback19/app/decorators/grind_mailer_decorator.rb`) — **inclusive e-mails de credenciais** (`app/decorators/models/mailer_decorator.rb:4`). **Não há expurgo**: zero ocorrências de purge/cleanup/`destroy_all` em `lib/`, `app/jobs` ou no engine. Retenção infinita, e o único leitor é uma listagem paginada.
- **Opções:** (a) **metadados sem corpo** (remetente, destinatário, assunto, status, timestamp) com expurgo de 180 dias; (b) corpo incluído, com expurgo curto; (c) replicar (corpo, para sempre).
- **Default vigente:** (a).
- **Recomendação:** (a). Guardar para sempre o corpo de e-mails que contêm credencial é o passivo mais barato de eliminar desta lista.

### Q-89 — Quem assina DKIM no ai9: a aplicação ou o provedor de envio?

- **Fatia:** S18
- **Trava:** nada — mas é obrigatório antes do cutover.
- **Impacto:** `só interno`
- **Contexto:** No legado a aplicação assina, e **a chave privada está versionada no repositório**: `lib/dkim_private_key.pem` (1,7 KB, rastreada pelo git), carregada em `config/application.rb:112`, com domínio `safegold.com.br` (`:110`) e seletor `dk` (`:111`). É o **D-85**, e a chave precisa ser **rotacionada de qualquer forma** — está exposta a quem tiver o repositório.
- **Opções:** (a) assinatura no provedor de envio, chave fora do repositório; (b) assinatura na aplicação, com a chave em ENV/credentials e rotacionada; (c) não assinar.
- **Default vigente:** (a).
- **Recomendação:** (a). E, independentemente da escolha, **rotacionar a chave atual** é item de runbook, não de decisão: ela já vazou por definição.

### Q-90 — Chaves de terceiro vivem em ENV/credentials ou no model `Credential`?

- **Fatia:** S18
- **Trava:** trava `CFG-01`.
- **Impacto:** `só interno`
- **Contexto:** O catálogo da base sugeria o model `Credential`, mas `backend/app/models/credential.rb:7` restringe `provider` a provedores de IA — e a chave do Google Maps precisa chegar ao **navegador** de qualquer forma. No legado, a situação é pior do que o mapa registrava: o token da ReceitaWS vem de ENV (`config/initializers/receitaws.rb:5`) **mas o valor real está versionado** em `config/application.arch.yml:12`; e a chave do Google Maps está **hardcoded em código-fonte**, duplicada, em `app/definitions/SFG/metadata.rb:8` e `:9` (a segunda dentro da própria URL, que vai para o HTML). O `secret_key_base` também está em texto puro em `config/development_credentials.yml:1`.
- **Opções:** (a) ENV/credentials, com `VITE_GOOGLE_API_KEY` para o front; não estender o `Credential`; (b) estender o `Credential` para aceitar provedores não-IA (mexe num model compartilhado, Princípio 6b); (c) misto.
- **Default vigente:** (a).
- **Recomendação:** (a), com uma regra inegociável: **nenhum segredo do legado entra no repositório novo**, e todos os três acima (ReceitaWS, Maps, `secret_key_base`) precisam ser rotacionados no cutover.

### Q-91 — O logo da marca precisa de versões branca e monocromática de verdade?

- **Fatia:** S17 / tematização
- **Trava:** nada.
- **Impacto:** `só interno`
- **Contexto:** **Correção ao mapa — a premissa estava errada.** O mapa afirma que `app_symbol.png` e `app_text.png` "não existem no repositório" e que por isso o seed de tema estoura. **Os dois existem**: `app/frontend/images/brand/app_symbol.png` (1,1 KB) e `app_text.png` (1,3 KB), junto de `app_logo_full.png` e várias variantes de tamanho — e a factory de tema os usa (`db/factories/app_theme_factory.rb:22-24`), o que só funciona porque estão lá. O defeito real é outro: em `app/definitions/SFG/theme.rb:47-57`, as variantes `_WHITE` e `_MONO` apontam **todas para o mesmo arquivo** da versão normal. Não existe logo branco nem monocromático de verdade.
- **Opções:** (a) o `theming-brand-engineer` deriva as versões branca e monocromática a partir do logo existente, registrando que são derivadas; (b) você fornece os originais do manual de marca; (c) usar o mesmo arquivo nas três variantes, como o legado.
- **Default vigente:** (a).
- **Recomendação:** (b) se existirem; senão (a). Um logo colorido sobre fundo escuro é a coisa que mais rápido faz uma demo parecer improvisada.

### Q-92 — Logos: `Medium` ou `has_one_attached` direto nos models?

- **Fatia:** S3 e S4
- **Trava:** trava `DB-056`, `DB-062`, `DB-089`, `FE-074` e `FE-087`.
- **Impacto:** `só interno`
- **Contexto:** No legado tudo é kt-paperclip em disco local. No ai9 há duas rotas: usar o model `Medium` (que a base já tem) ou `has_one_attached` direto nos models novos. O problema do `Medium` é que a tabela `media` **não tem dono nem escopo** — um logo criado por lá aparece na galeria `/media` para **qualquer autenticado**, e filtrar a galeria significaria mexer em `MediumService`, que é da base compartilhada (Princípio 6b). Nas duas opções, **Paperclip não é portado**.
- **Opções:** (a) `has_one_attached` direto em `Project#logo`, `Carrier#logo` e `Provider#logo`, reusando a mesma pilha ActiveStorage + `image_processing` que o `Medium` usa; (b) usar `Medium`, aceitando que os logos apareçam na galeria; (c) usar `Medium` e autorizar tocar no `MediumService` para filtrar por escopo.
- **Default vigente:** (a).
- **Recomendação:** (a). Nota de conferência: os anexos de logo do legado são **projeto** (`project.rb:48`, `avatar`), **portador** (`carrier.rb:16`) e **fornecedor** (`provider.rb:12`) — **`Company` não tem anexo nenhum**, ao contrário do que se poderia supor.

### Q-93 — Ativar `paper_trail` na base ou criar `AuditEvent` só do Safegold?

- **Fatia:** S19
- **Trava:** trava o desenho da trilha de auditoria.
- **Impacto:** `só interno`
- **Contexto:** `paper_trail` está declarada no `backend/Gemfile:47` da base ai9 e **não é usada por nenhum sistema** (é a mesma família de `aasm`, `Gemfile:45`, e `pg_search`, `Gemfile:87`). Ativá-la é decisão de **plataforma**; criar um `AuditEvent` é escopo desta migração. **Contexto do legado que ajuda a decidir:** o legado **não tem `paper_trail`** — a trilha dele é caseira (`app/models/tracking.rb` + `lib/tracking_facade.rb`) e cobre **só** jobs de template de disponibilidade e criação de projeto (`project_availabilities_controller.rb:72,91,110`, `projects_controller.rb:135`, `project.rb:87,743`, `global_availability_template.rb:34`, e os dois jobs em `lib/`). Não cobre CRUD de cadastros, lançamentos, valores, permissões nem login. Ou seja: **não há trilha financeira a preservar** — o que houver no ai9 é novo.
- **Opções:** (a) criar `AuditEvent` só do Safegold, no formato de `permission_audit_logs` (que já tem o esquema certo e **zero produtores** na base), e deixar o `paper_trail` como flag de upstream; (b) ativar `paper_trail` na base; (c) só portar o `Tracking` do legado, com o mesmo escopo estreito.
- **Default vigente:** (a).
- **Recomendação:** (a). Duplicar trilha depois custa mais caro que decidir agora, e ativar uma gem na base compartilhada afeta todos os sistemas — não é decisão de uma migração.

### Q-94 — As colunas renomeadas em 2022 têm leitores externos?

- **Fatia:** S9 e S14
- **Trava:** nada — é informação que você tem e o repositório não.
- **Impacto:** `só interno`
- **Contexto:** **Correção ao mapa:** ele fala em "três colunas renomeadas em `renegotiations`". São **três renomeações, em três tabelas diferentes**, todas em 29/04/2022 — e só **uma** é em `renegotiations`: `rename_column :renegotiations, :total_value, :installments_main_value` (`db/migrate/20220429122226_...:4`), com mudança real de semântica (era "R$ Total da dívida", virou "soma do principal das parcelas" — o comentário legado em `renegotiation.rb:273` confirma). As outras duas: `renegotiation_installments.value → main_value` (`20220429122346_...:3`) e `renegotiation_payments.value → installment_paid_value_with_interest_cm` (`20220429122419_...:3`).
- **Opções:** (a) adotar os nomes novos e pronto; (b) adotar os nomes novos e manter uma *view* de compatibilidade com os antigos; (c) manter os nomes antigos.
- **Default vigente:** (a).
- **Recomendação:** (a), a menos que você saiba de relatório ou integração externa lendo `total_value`. A mudança de semântica de `total_value` é a que mais importa: um relatório antigo que some essa coluna passou a somar outra coisa desde 2022.

### Q-95 — A "Chave de Integração" do indicador tem consumidor fora do repositório?

- **Fatia:** S10
- **Trava:** trava `OPS-312` — decide se a chave pode virar única, mudar de formato ou sumir.
- **Impacto:** `só interno`
- **Contexto:** Dentro do repositório, **nada lê `indicator.key`** para integrar coisa nenhuma. As ocorrências são todas de encanamento: geração a partir do título (`indicator.rb:44`), denormalização (`indicator.rb:49` e `indicator_entry.rb:25`), o próprio campo no formulário (`.../indicators/helper/_body.html.erb:19`), `permit` e mensagem de erro. A ordenação por chave está inclusive **quebrada** — `indicator.rb:68-69` devolve `"integration_key"`, coluna que **não existe** em `indicators` (a coluna é `key`), num `prepare_ordering` copiado do `Segment` (`:53-61`). O campo se chama "Chave de Integração" e não integra nada aqui dentro.
- **Opções:** (a) manter como está (campo livre, sem unicidade); (b) tornar única e imutável após a criação, como chave de integração de verdade (mesma disciplina do DC-17 e DC-22); (c) remover o campo.
- **Default vigente:** (a).
- **Recomendação:** (b) **se** houver consumidor externo (BI, planilha, ETL); (c) se não houver. O que não faz sentido é manter um campo chamado "Chave de Integração" que ninguém garante ser estável nem única.

### Q-96 — `is_active` está no `permit` do indicador mas não no formulário

- **Fatia:** S10
- **Trava:** trava `BE-316`.
- **Impacto:** `só interno`
- **Contexto:** `app/controllers/pub/indicators_controller.rb:144` permite `:is_active`, mas o formulário só tem título, chave e descrição (`.../indicators/helper/_body.html.erb`). Existe ainda uma action paralela `activated` (`indicators_controller.rb:86-98`) que grava direto de `params[:is_active]`, **fora do `permit`** — ou seja, há dois caminhos de escrita e nenhum deles é o formulário.
- **Opções:** (a) manter os dois caminhos (o `permit` e a action `activated`); (b) só a action explícita de ativar/desativar, tirando `is_active` do `permit` do update; (c) expor o campo no formulário.
- **Default vigente:** (a) — pode haver cliente externo postando.
- **Recomendação:** (b). Um campo com dois caminhos de escrita, sendo um deles fora do `permit`, é a receita de "ninguém sabe quem desativou".

### Q-97 — `month`/`year` do lançamento: inteiros soltos ou `date`?

- **Fatia:** S10
- **Trava:** trava `BE-329` e `DB-311`.
- **Impacto:** `só interno`
- **Contexto:** `db/migrate/20211027140815_create_indicator_entries.rb:9-10` cria `t.integer :month` e `t.integer :year` — sem `null: false`, sem default, sem CHECK e sem índice. No model há só `presence` (`indicator_entry.rb:10-11`) e a unicidade composta (`:6`). **Nada impede `month = 47`**, e o único guarda-corpo é indireto e tardio: `Date.new(self.year, self.month)` em `indicator_entry.rb:57` **estoura em runtime** na hora de exibir.
- **Opções:** (a) manter inteiros, acrescentando `CHECK (month BETWEEN 1 AND 12)` e `NOT NULL`; (b) trocar por uma coluna `date` normalizada no primeiro dia do mês; (c) replicar como está.
- **Default vigente:** (a).
- **Recomendação:** (a). Preserva a forma que a grade já usa para montar as colunas do ano e fecha o buraco no banco, que é onde ele precisa ser fechado.

### Q-98 — O `user_id` do lançamento é "quem lançou" ou "quem alterou por último"?

- **Fatia:** S10
- **Trava:** trava `BE-327`.
- **Impacto:** `só interno`
- **Contexto:** É o segundo, e por acidente: o formulário da grade é o mesmo para criar e atualizar, e reenvia `current_user.id` num `hidden_field` a cada submissão (`.../indicator_entries/list/_widget.html.erb:18` e `:44`). O `permit` aceita (`indicator_entries_controller.rb:107`) e o `update` aplica (`:61`), sem nenhum `on: [:create]` protegendo o campo. **Verificado, e isso muda o peso da pergunta:** o autor **não é exibido em lugar nenhum** — as únicas ocorrências de `user` em toda a pasta de views de lançamentos são esses dois `hidden_field`. Não há coluna "lançado por", tooltip nem tela de detalhe. O dado é sobrescrito e ninguém sequer o vê.
- **Opções:** (a) `created_by` imutável na criação + `updated_by` atualizado a cada alteração (dois campos, cada um dizendo a verdade); (b) manter um campo só, com a semântica de "quem alterou por último", agora **documentada**; (c) replicar sem mudar nada.
- **Default vigente:** (b).
- **Recomendação:** (a). São duas colunas e resolvem de vez uma pergunta ("quem lançou isto?") que num sistema financeiro sempre acaba sendo feita.
---

## Já decididas, removidas desta rodada

Estas apareciam como pergunta em algum mapa e **já têm resposta registrada**. Ficam aqui
para que ninguém as reabra por engano — e para provar que a lista acima não repete nada.

| Pergunta original | O que ela perguntava | Decisão que já a fechou |
| ----------------- | -------------------- | ----------------------- |
| `auth-admin` Q-B11 | "O cliente espera um dashboard? Não existe nenhum no legado (D-87)" | **DEC-21.2** — `NEW-002`: dashboard resumo na tela inicial **entra**, como feature nova (fatia S15) |
| `auth-admin` Q-B20 | "PWA entra nesta entrega? Phase 0 decidiu SIM e a base não tem nada" | **DEC-21.3** — `NEW-003`: **entra o mínimo instalável** (manifest + ícones), sem service worker (fatia S16) |
| `data-infra` Q-01 | "TLS do SMTP: posso trocar `openssl_verify_mode: 'none'` por `peer` na base ai9?" | **DEC-21.4** — *"esquece isso por enquanto"*. Não mexer; fica como flag 11 de upstream, com OPS-484 e OPS-626 **explicitamente não atendidos** |
| `projects` Q-11 | "Quem gerencia membership? O dono do projeto vira papel com poder?" | **DEC-18.5** — criam/removem **OG, Admin e Gerente**; o dono do projeto **não** vira papel. O próprio mapa já registra que era confirmação, não pergunta |
| `risk-indicators` Q-R1 | "A grade de indicadores ganha um gráfico?" | **DEC-21.1** — `NEW-001`: **sim**, série mensal + volume por portador com Recharts, nos indicadores (fatia S15). E **não** no risco |
| `risk-indicators` Q-R20 | "O detalhe de operação estruturada exibe Saldo Inicial e Saldo negativos — confirmar que é o esperado" | **DEC-01** — a convenção de sinal é **replicada exatamente**. O negativo é o comportamento aprovado, e já está no `improvements-log` como melhoria recusada |
| `risk-indicators` Q-R23 | "Houve uma tela de detalhe / série histórica de indicador planejada e abandonada — o negócio sente falta?" | **DEC-09** ("série histórica de indicadores: fora") + **DEC-21.1**, que entrega exatamente a série mensal por outra porta, como `NEW-001` |

---

## Onde o mapa e o legado divergiram

Conferi cada contexto abrindo o arquivo. Nestes pontos o mapa estava impreciso ou errado, e a
entrada acima já traz a versão correta. **Vale a fonte.**

| # | Entrada | O que o mapa dizia | O que a fonte diz |
| - | ------- | ------------------ | ----------------- |
| 1 | Q-01 | O decaimento composto vem do `update` seguido de `save` no controller (`availability_entries_controller.rb:42,44`) | O segundo `save` não recalcula (as mudanças já foram limpas). O decaimento vem do **formulário preencher o campo com `e.value`, o valor já corrigido** (`.../availability_entries/list/_widget.html.erb:56` e `:131`), enquanto `availability_entry.rb:20` re-carimba `original_value` com o que chegar |
| 2 | Q-02 | As duas regras de soma estão em `project_availability_template.rb` / `global_availability_template.rb` | Estão em `project.rb:406` (soma bruta da consolidação geral) e `availability_entry.rb:188` / `:191`. Nenhum dos dois models de template soma valor. **Agravante:** `values[:total]` é calculado e **nunca renderizado** — o painel só usa `by_entry[].total` (= `virtual_value`) |
| 3 | Q-04 | O `after_commit` dispara duas vezes e o segundo disparo atualiza tipo/subtipo | Confirmado, **e o segundo disparo nunca corrige `operation_value`** (`receivable_entry.rb:168` só toca tipo e subtipo). O valor sem tarifas fica congelado para sempre |
| 4 | Q-08 | A fórmula de faturamento está em `remuneration.rb` | Está em `receipt.rb:63`. `remuneration.rb` só guarda o percentual |
| 5 | Q-13 | "Pagar só a mora pode quitar a parcela" | **Não acontece.** A mora entra idêntica nos dois lados e **se cancela** (`renegotiation_installment.rb:62-67`); `is_paid` só vira 1 com o principal coberto. O efeito real é outro: a mora **nunca é efetivamente cobrada** na parcela e **infla o "R$ Pago"** no agregado (`renegotiation.rb:105`) |
| 6 | Q-14 | Os subtipos de operação de risco "estão comentados no legado" | **Estão vivos e são infraestrutura central** (`risk_operation.rb:10,29-32,148-154`, `risk_control.rb:20,22,129,144`, `receivable_entry.rb`, select em `.../receivables/new/_body.html.erb:95`). Comentada há **uma** linha: `console_controller.rb:172`. O que falta é CRUD, menu e campo no formulário de risco |
| 7 | Q-17 | "Nenhum consumidor foi encontrado no repositório" (dito com dúvida) | **Confirmado por varredura exaustiva**: as 6 colunas denormalizadas são **write-only**. Não há nenhum `where`, scope ou `if` de regra que as leia. As únicas leituras são a exibição do interruptor no projeto e uma cópia em `risk_control.rb:184` |
| 8 | Q-20 | "BE-335 exige papel administrativo para publicar contrato" | **Esse gate não existe.** `contracts_controller.rb` não tem `before_action` de autorização, zero `may?`/`admin?`/`og?`, rotas sem constraint (`routes.rb:30-31`). Hoje **qualquer autenticado que acerte a URL publica uma nova versão dos Termos** |
| 9 | Q-22 | "~40 textos de ajuda" (recebíveis) e "26 tooltips" (risco + estruturadas) | **91 chaves**, em 3 arquivos: 65 em `receivables_help_inputs.yml`, 13 + 13 nos outros. 100% com o mesmo placeholder |
| 10 | Q-39 | `resource_kinds` e `resource_sources` têm "o mesmo rótulo de menu e o mesmo título de aba" | **Título de aba idêntico byte a byte** (`console_controller.rb:348-349` e `:358-359`), mas **só `resource_sources` tem item de menu**; `resource_kinds` não tem nenhum. E os títulos das páginas diferem por **uma letra** ("Tipos de Recurso" × "Tipos de Recursos") |
| 11 | Q-42 | "O ETL Django forçava `user_id = 1`… nos borderôs de 2016-2021" | **Não é Django** — é um módulo Ruby dentro do próprio Rails (`app/models/legacy.rb`, `establish_connection :sfg_legacy`, tabela `fbordero`); não há uma linha de Python no repositório. E **não é 2016-2021**: o importador não filtra data e o dump versionado tem registros também em 2022 |
| 12 | Q-53 | Pedir "Concluído" grava "Fechado" (um typo num lado só) | **A inversão é dupla**: o `update` grava Fechado quando se pede Concluído (`messages_controller.rb:118-119`) **e** a action `close` grava **Concluído** (`:156-159`). Os dois estados estão trocados entre si |
| 13 | Q-56 e Q-92 | "os outros dois logos" / logos de projeto e empresa | Os anexos são **projeto** (`project.rb:48`, `avatar`) e **fornecedor** (`provider.rb:12`, `logo`). **`Company` não tem anexo nenhum** |
| 14 | Q-57 | `default_position` usado em `availability_templates_controller.rb:22` | Confirmado, **e há um segundo problema na mesma action**: `:21` monta o `where!` com fragmento SQL malformado (`"title #{Dev.ilike} "` sem o placeholder). A busca por texto tem dois defeitos independentes |
| 15 | Q-60 | `is_title` e `is_liquidation` "não têm consumidor visível" | Só `is_title` é órfão. **`is_liquidation` tem consumidor**: `movement_kind.rb:14` o soma com `is_advalorem`/`is_desagio`/`is_iof` para validar exclusividade mútua (`:13-18`) |
| 16 | Q-69 | O item de menu da posição diária de risco "está comentado" | **Não há item de menu nenhum** para `risk_entries` em `application_helper.rb`. O que está comentado é a **aba** (`.../risk/_body.html.erb:30`, `_body.js.erb:32`) e o handler do botão "Cadastrar posição" (`_body.js.erb:34-40,127-134`) |
| 17 | Q-72 | Os 4 flags de `structured_operation_types` estão "sem consumidor" | **`is_default` e `has_pre_faturamento` têm consumidor no lado estruturado** (`structured_operation_type.rb:11`, `.../structured_operation_types/list/_widget.html.erb:23`, `.../structured_operations/list/_widget.html.erb:16,22`). Órfãos mesmo são só `allow_manual_operations` e `allow_receivable_entries` |
| 18 | Q-78 | `generic_rating` "pode ser resquício; não achei consumidor claro" | **Só existe o CSS** (`app/frontend/css/pub/recyclable/generic_rating.scss`). Zero ocorrências de `app_rating_widget`/`generic_rating` em qualquer `.erb`, `.rb` ou `.js`. Sem model, controller, rota ou partial |
| 19 | Q-81 | Item de menu `reports` marcado `inactive` em `application_helper.rb` | Está na **view** (`.../base/menu/_container.html.erb:24`), não no helper — **e o item nem existe**: nenhum item da lista tem `identifier: "reports"`, então a condição nunca é verdadeira. Código morto guardando um identificador fantasma |
| 20 | Q-87 | "O legado guardava IP e user-agent das tentativas de login, sem política" | **O legado não tem essa tabela.** Zero ocorrências de `login_attempt` no repositório inteiro; só o contador `failed_attempts` do Devise. Quem tem `login_attempts` com `ip_address` e `user_agent` é a **base ai9** (`backend/db/schema.rb:451-460`), sem expurgo. O passivo é adotado, não herdado |
| 21 | Q-90 | Chaves de terceiro vêm de ENV/credentials | Parcialmente. O token da ReceitaWS vem de ENV **mas o valor real está versionado** (`config/application.arch.yml:12`); a chave do **Google Maps está hardcoded e duplicada** em `app/definitions/SFG/metadata.rb:8-9` (a segunda dentro da URL que vai para o HTML); e o `secret_key_base` está em texto puro em `config/development_credentials.yml:1` |
| 22 | Q-91 | `app_symbol.png` e `app_text.png` "não existem no repositório" e o seed de tema estoura | **Os dois existem** (`app/frontend/images/brand/`), e a factory de tema os usa (`app_theme_factory.rb:22-24`) — se não existissem, o seed quebraria. O defeito real é outro: as variantes `_WHITE` e `_MONO` apontam **todas para o mesmo arquivo** (`SFG/theme.rb:47-57`) |
| 23 | Q-93 | (implícito) o legado tem trilha de auditoria a preservar | O legado **não tem `paper_trail`**. A trilha é caseira (`app/models/tracking.rb` + `lib/tracking_facade.rb`) e cobre **só** jobs de template de disponibilidade e criação de projeto. Não cobre CRUD, lançamentos, valores, permissões nem login — **não há trilha financeira a preservar** |
| 24 | Q-94 | "Três colunas de `renegotiations` renomeadas em 29/04/2022" | São **três renomeações em três tabelas**, e só **uma** é em `renegotiations` (`total_value → installments_main_value`). As outras são em `renegotiation_installments` e `renegotiation_payments` |
| 25 | Q-98 | O `user_id` do lançamento de indicador é "quem alterou por último" | Confirmado, **e o autor não é exibido em nenhuma tela** — as únicas ocorrências de `user` nas views de lançamentos são dois `hidden_field`. O dado é sobrescrito e ninguém sequer o vê |

**Achados colaterais** que apareceram na conferência e não viraram pergunta (vão para
`legacy-defects.md` / `improvements-log.md`): a action `TrackingsController#show` está quebrada
em três frentes (`fetch_tracking` vazio e não registrado, `Tracking` sem associação
`geolocation`, nada é salvo); `Indicator.prepare_ordering` devolve `"integration_key"`, coluna
que não existe (`indicator.rb:68-69`); e `Contract#description` sofre `URI.unescape` sobre um
`ActionText::RichText` (`contract.rb:28`), método removido no Ruby 3.

---

## De-para: ID original do mapa → `Q-xx` deste documento

Para quem vier conferir contra os mapas, e para a fusão com a outra metade.

### `map/auth-admin.md`

| Original | Aqui | | Original | Aqui |
| -------- | ---- | - | -------- | ---- |
| Q-B1 | Q-75 | | Q-B11 | **removida** — DEC-21.2 |
| Q-B2 | Q-45 | | Q-B12 | Q-20 *(fundida)* |
| Q-B3 | Q-46 | | Q-B13 | Q-78 |
| Q-B4 | Q-48 *(fundida)* | | Q-B14 | Q-79 |
| Q-B5 | Q-49 *(fundida)* | | Q-B15 | Q-80 *(fundida)* |
| Q-B6 | Q-87 | | Q-B16 | Q-53 |
| Q-B7 | Q-47 | | Q-B17 | Q-54 |
| Q-B8 | Q-48 *(fundida)* | | Q-B18 | Q-88 |
| Q-B9 | Q-76 *(fundida)* | | Q-B19 | Q-89 |
| Q-B10 | Q-14 *(fundida)* | | Q-B20 | **removida** — DEC-21.3 |

### `map/data-infra.md`

| Original | Aqui | | Original | Aqui |
| -------- | ---- | - | -------- | ---- |
| Q-01 | **removida** — DEC-21.4 | | Q-10 | Q-50 |
| Q-02 | Q-44 | | Q-11 | Q-86 |
| Q-03 | Q-90 | | Q-12 | Q-76 *(fundida)* |
| Q-04 | Q-82 | | Q-13 | Q-77 |
| Q-05 | Q-43 *(parte foi para Q-18)* | | Q-14 | Q-91 |
| Q-06 | Q-22 *(fundida)* **+** Q-85 *(desdobrada)* | | Q-15 | Q-83 |
| Q-07 | Q-49 *(fundida)* | | Q-16 | Q-51 |
| Q-08 | Q-84 | | Q-17 | Q-52 |
| Q-09 | Q-80 *(fundida)* | | Q-18 | Q-81 |

### `map/projects-cadastros.md`

| Original | Aqui | | Original | Aqui |
| -------- | ---- | - | -------- | ---- |
| Q-01 | Q-57 | | Q-07 | Q-01 |
| Q-02 | Q-17 *(fundida)* | | Q-08 | Q-02 *(fundida)* |
| Q-03 | Q-55 | | Q-09 | Q-03 |
| Q-04 | Q-56 | | Q-10 | Q-02 *(fundida)* |
| Q-05 | Q-92 | | Q-11 | **removida** — DEC-18.5 |
| Q-06 | Q-93 | | | |

### `map/receivables-renegotiations.md`

| Original | Aqui | | Original | Aqui | | Original | Aqui |
| -------- | ---- | - | -------- | ---- | - | -------- | ---- |
| Q-B1 | Q-18 **+** Q-19 *(desdobrada)* | | Q-B13 | Q-60 | | Q-B25 | Q-12 |
| Q-B2 | Q-58 | | Q-B14 | Q-08 *(fundida)* | | Q-B26 | Q-13 |
| Q-B3 | Q-20 *(fundida)* | | Q-B15 | Q-28 | | Q-B27 | Q-63 |
| Q-B4 | Q-21 | | Q-B16 | Q-29 | | Q-B28 | Q-40 |
| Q-B5 | Q-04 | | Q-B17 | Q-61 *(fundida)* | | Q-B29 | Q-64 |
| Q-B6 | Q-05 | | Q-B18 | Q-62 | | Q-B30 | Q-65 |
| Q-B7 | Q-06 | | Q-B19 | Q-42 | | Q-B31 | Q-94 |
| Q-B8 | Q-07 | | Q-B20 | Q-22 *(fundida)* | | Q-B32 | Q-17 *(fundida)* |
| Q-B9 | Q-59 | | Q-B21 | Q-23 *(fundida)* | | Q-B33 | Q-66 |
| Q-B10 | Q-27 | | Q-B22 | Q-10 | | Q-B34 | Q-41 |
| Q-B11 | Q-23 *(fundida)* | | Q-B23 | Q-09 | | Q-B35 | Q-67 |
| Q-B12 | Q-25 *(fundida)* | | Q-B24 | Q-11 | | | |

### `map/risk-indicators.md`

| Original | Aqui | | Original | Aqui | | Original | Aqui |
| -------- | ---- | - | -------- | ---- | - | -------- | ---- |
| Q-R1 | **removida** — DEC-21.1 | | Q-R13 | Q-31 | | Q-R25 | Q-36 |
| Q-R2 | Q-70 | | Q-R14 | Q-71 | | Q-R26 | Q-95 |
| Q-R3 | Q-68 | | Q-R15 | Q-72 | | Q-R27 | Q-34 |
| Q-R4 | Q-69 | | Q-R16 | Q-24 | | Q-R28 | Q-98 |
| Q-R5 | Q-61 *(fundida)* | | Q-R17 | Q-08 *(fundida)* | | Q-R29 | Q-73 |
| Q-R6 | Q-14 *(fundida)* | | Q-R18 | Q-32 | | Q-R30 | Q-97 |
| Q-R7 | Q-23 *(fundida)* | | Q-R19 | Q-25 *(fundida)* | | Q-R31 | Q-37 |
| Q-R8 | Q-15 | | Q-R20 | **removida** — DEC-01 | | Q-R32 | Q-74 |
| Q-R9 | Q-22 *(fundida)* | | Q-R21 | Q-26 | | Q-R33 | Q-38 |
| Q-R10 | Q-30 | | Q-R22 | Q-39 | | Q-R34 | Q-35 |
| Q-R11 | Q-16 | | Q-R23 | **removida** — DEC-09 + DEC-21.1 | | | |
| Q-R12 | Q-33 | | Q-R24 | Q-96 | | | |
