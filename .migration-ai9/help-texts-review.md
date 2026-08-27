# Textos de ajuda dos formulários financeiros — para revisão

**DEC-88.** Os três YAML do legado tinham 91 chaves e **um único texto**
(*"Só um teste de informações do campo pra descrever para que serve cada campo"*). Não havia
conteúdo a migrar; os textos abaixo foram **escritos a partir das fórmulas**, não do rótulo do campo.

**Onde ficaram:** `backend/db/seed_assets/{receivables,risk_operations,structured_operations}_help_inputs.yml`.
Mesmas chaves, mesma ordem, mesma estrutura plana do legado — só o valor mudou. Trocar um texto é
editar o YAML; não há deploy de código envolvido.

**Como revisar:** leia a coluna do meio. Se discordar, a terceira coluna diz exatamente qual linha do
legado sustenta a afirmação — é lá que se confere se o texto está certo ou se eu li errado.

**Números:** 91 chaves · **87 textos escritos** · **4 `TODO:`** (campos sem nenhum leitor no legado).

**Regras seguidas:** o texto diz o que o campo faz *na conta*, não o que o rótulo já diz; onde o campo
participa de defeito já decidido (DEC-32, DEC-33, DEC-34, DEC-37), o texto descreve o comportamento
**real**, sem apontá-lo como erro; nenhuma unidade, faixa ou validação que o código não tenha foi
inventada — em especial a taxa de remuneração, que **não tem** validação de faixa (DEC-37).

---

## Os 4 TODO

Campos que o legado grava mas **nada lê**. Não inventei explicação; o texto no YAML diz o que falta saber.

| Arquivo | Campo | O que precisa ser respondido |
| --- | --- | --- |
| receivables | `contrato` | Qual contrato a coluna identifica e quem a consome. `t.string` na migration, permitida no controller, sem tela e sem leitor. |
| receivables | `resource_kind_id` | Se é a mesma classificação de *Utilização de recursos* ou outra coisa. Nunca é preenchida (D-74). |
| risk_operations | `is_on_variable` | O que é *o variável* e quem o apura. Só é gravado e copiado na renovação (D-74). |
| structured_operations | `is_on_variable` | Idem. |

---

## Onde a fórmula contradiz o nome do campo

Estes três são **achados**, não detalhe de redação: quem lê só o rótulo entende outra coisa.

| Campo | O nome sugere | A fórmula faz |
| --- | --- | --- |
| `multiplicador_pm_float` | que multiplica pelo float | multiplica o bruto final pelo **prazo médio do banco** (`receivable_entry.rb:105`); o float acordado não entra |
| `custo_efetivo_pz_med_banco_sem_iof` | um custo do **banco** | calcula com o prazo do banco, mas **zera pela guarda no prazo da empresa** (`:74`) — assimétrico em relação a `:78`, que guarda pelo prazo do banco. É a DEC-32 |
| `taxa_desconto_nominal_despesas_bancos` | taxa das despesas **sem** IOF (é o que a expressão calcula: `valor_total_tarifas - tarifas_iof`) | mas a guarda que a anula é `tarifas_iof < 1` (`:68`) — sem IOF lançado, a taxa **sem IOF** sai em branco. Mesmo par em `:82` |

---

## Recebíveis — 65 campos

| Campo | Texto escrito | Fundamento no código |
| --- | --- | --- |
| `date` | Data da operação, obrigatória. É ela que data o movimento de liberação de recurso e vira a data de emissão da operação de risco gerada por este borderô; não entra em nenhum cálculo de custo. | `receivable_entry.rb:13` (obrigatório), `:138` (data do movimento), `:153` (vira `issue_date` da operação de risco) |
| `project_id` | Projeto dono do borderô. Define a marca de gestão Safegold do lançamento e entra na chave que procura o limite de risco da empresa no portador. | `receivable_entry.rb:30` (chave do limite), `:40` (`has_safegold_management`) |
| `carrier_id` | Portador que comprou os títulos. Junto com empresa, projeto e tipo de operação, é a chave que localiza o limite de risco — sem limite cadastrado para essa combinação o borderô não salva. | `receivable_entry.rb:12` (obrigatório), `:28-31` (chave do limite + erro `Não possui limite cadastrado`) |
| `company_id` | Empresa cedente dos títulos. Entra na chave do limite de risco e é a empresa cujo prazo médio ponderado alimenta o custo efetivo. | `receivable_entry.rb:23` (obrigatório), `:28-31` (chave do limite) |
| `wallet_id` | Carteira em que o borderô é classificado. Serve para filtrar e ordenar a lista; não entra em nenhuma conta. | `receivable_entry.rb:14`; `receivables_controller.rb:27` (filtro); `receivable_entry.rb:194` (ordenação) |
| `receivable_kind_id` | Classificação do recebível. Obrigatória para salvar, mas não altera nenhum valor do borderô. | `receivable_entry.rb:15` (só `presence`; nenhum uso em cálculo) |
| `resource_source_id` | Origem e utilização dos recursos do borderô. Obrigatória para salvar; é classificação e não afeta os valores calculados. | `receivable_entry.rb:16` (só `presence`; nenhum uso em cálculo) |
| `nro_bordero` | Número do borderô no portador. Aceita apenas dígitos e é copiado como número de contrato da operação de risco gerada por este lançamento. | `receivable_entry.rb:160` (vira `contract_number` da operação de risco); migration `:12` (`t.integer`) |
| `qtd_titulos` | Quantidade de títulos enviados. Menos a quantidade recusada, dá a quantidade final; nenhum valor em dinheiro é derivado dela. | `receivable_entry.rb:17`, `:49` (`qtd_final = qtd_titulos - qtd_recusada`) |
| `valor_bruto` | Valor de face dos títulos enviados. Menos o bruto recusado, forma o bruto final — a base de todas as tarifas, do IOF e de todos os custos efetivos. | `receivable_entry.rb:18`, `:48` (`vlr_bruto_final = valor_bruto - vlr_bruto_recusado`) |
| `qtd_recusada` | Quantidade de títulos que o portador recusou. É subtraída da quantidade enviada; em branco vale zero. | `receivable_entry.rb:49`, `:227` (default 0) |
| `vlr_bruto_recusado` | Valor de face dos títulos recusados. É subtraído do valor bruto para formar o bruto final; em branco vale zero, e informar a mais encolhe a base de todo o cálculo. | `receivable_entry.rb:48`, `:228` (default 0) |
| `vlr_bruto_final` | Bruto menos bruto recusado, calculado automaticamente. É a base sobre a qual incidem tarifas, IOF e todos os custos efetivos. | `receivable_entry.rb:48`; base de `:54`, `:67-69`, `:76`, `:90`, `:104-105`, `:108` |
| `qtd_final` | Quantidade enviada menos a recusada, calculada automaticamente. | `receivable_entry.rb:49` |
| `prz_med_pond_emp` | Prazo médio ponderado dos títulos pela ótica da empresa, em dias. Somado ao float acordado, é o prazo que desconta o custo efetivo da empresa e o líquido correto — errar aqui move todos os percentuais de custo do borderô. | `receivable_entry.rb:19` (obrigatório, > 0), `:90-92` (CET empresa), `:109` (valor presente) |
| `prz_med_pond_bco` | Prazo médio ponderado pela ótica do portador, em dias. Define o float calculado, a base do IOF e o custo efetivo do banco; se ficar menor que o prazo da empresa, o float calculado sai negativo. | `receivable_entry.rb:20` (obrigatório, > 0), `:50` (float calculado), `:54` (IOF), `:67-69`, `:76-78` |
| `float_calculado` | Prazo do banco menos prazo da empresa, calculado automaticamente. É o float que o portador de fato praticou, para comparar com o acordado. | `receivable_entry.rb:50` (`prz_med_pond_bco - prz_med_pond_emp`) |
| `float_acordado` | Dias de float negociados com o portador. É somado ao prazo médio em todos os custos efetivos com float e no líquido correto — quanto maior o float, menor o custo mensal apurado. | `receivable_entry.rb:21`, `:72`, `:76`, `:85`, `:90`, `:99`, `:101`, `:109` (somado ao prazo em toda conta com float) |
| `diferenca_float` | Quanto o float calculado excede o acordado. Só mostra a diferença positiva: se o portador praticou float menor que o combinado, o campo fica zerado. | `receivable_entry.rb:51-52` (piso zero: só diferença positiva) |
| `checagem_iof` | IOF esperado, para conferir contra o IOF que o portador cobrou: 0,0041% ao dia sobre o prazo do banco mais 0,38% fixo, aplicados ao bruto final já sem ad valorem e sem deságio. | `receivable_entry.rb:54` (`0.000041` ao dia × prazo do banco + `0.0038` fixo, sobre bruto final − ad valorem − deságio) |
| `valor_total_tarifas` | Soma de todas as tarifas lançadas: ad valorem, deságio, IOF e outras. É o que se subtrai do bruto final para chegar ao líquido. | `receivable_entry.rb:55` |
| `valor_liquido` | Bruto final menos o total de tarifas. É o valor que o portador credita e o denominador de todos os custos efetivos — tarifa esquecida aparece como custo efetivo menor que o real. | `receivable_entry.rb:56`; denominador de `:76`, `:90`, `:95`, `:99` |
| `cst_efetivo_acordado` | Custo efetivo mensal combinado com o portador, em percentual. Dele sai o líquido correto, e a diferença contra o líquido apurado é o que classifica o borderô como OK ou Diferença. | `receivable_entry.rb:22` (obrigatório), `:107-112` (líquido correto), `:115` (status) |
| `calc_valor_liq_correto` | Líquido que o borderô deveria ter pelo custo efetivo acordado: a taxa é convertida para o dia, multiplicada pelo bruto final e pelo prazo da empresa mais o float, e esse desconto sai do bruto — é desconto linear, dia a dia, não composto. | `receivable_entry.rb:107-112` — desconto **linear** (DEC-31 / D-14) |
| `dif_calc_vlr_liq` | Líquido apurado menos líquido correto. Negativo significa que o portador creditou menos do que o custo acordado justifica, e é o que marca o borderô como Diferença. | `receivable_entry.rb:114-115` |
| `status` | Preenchido sozinho: Diferença quando o líquido apurado fica abaixo do líquido correto, OK em qualquer outro caso — inclusive quando o crédito veio acima do acordado. | `receivable_entry.rb:115`; `entry.rb:10-12` (`Diferença` / `OK`) |
| `recompra` | Valor devolvido ao portador a título de recompra. Sai do líquido para formar o líquido recebido e é convertido em percentual sobre o líquido. | `receivable_entry.rb:59` (percentual), `:63` (total), `:65` (líquido recebido) |
| `retencao` | Valor retido pelo portador. Sai do líquido para formar o líquido recebido e é convertido em percentual sobre o líquido. | `receivable_entry.rb:60`, `:63`, `:65` |
| `fomento` | Parcela do líquido lançada como fomento. Entra no total de deduções e reduz o líquido recebido. | `receivable_entry.rb:61`, `:63`, `:65` |
| `outros` | Qualquer outra dedução sobre o líquido. Entra no total de deduções e reduz o líquido recebido. | `receivable_entry.rb:62`, `:63`, `:65` |
| `total_deducoes` | Soma de recompra, retenção, fomento e outros, calculada automaticamente. | `receivable_entry.rb:63` |
| `vlr_liq_recebido` | Líquido menos as quatro deduções. É o dinheiro que efetivamente entra na empresa. | `receivable_entry.rb:65` |
| `data_credito` | Data em que o portador credita o líquido. É copiada como vencimento da operação de risco gerada pelo borderô; sem ela essa operação não chega a ser criada, porque exige vencimento. | `receivable_entry.rb:162` (vira `due_date` da operação de risco); `risk_operation.rb:61` (`due_date` é obrigatório) |
| `contrato` | TODO: precisa saber qual contrato este campo identifica e quem o consome — a coluna existe e o formulário a aceita, mas nenhuma tela a exibe e nenhum cálculo a lê. | **TODO.** Migration `20210315183541_create_receivable_entries.rb:42`; `receivables_controller.rb:222` (permitido). Zero leitores, zero telas |
| `observacoes` | Anotações livres sobre o borderô. Não entram em nenhuma conta. | Migration `:43` (`t.text`); `receivables_controller.rb:223`. Sem uso em cálculo e sem campo no formulário |
| `tarifas_ad_valorem` | Soma automática das tarifas cujo tipo está marcado como ad valorem. Entra no total de tarifas e, junto com o deságio, é o que se abate da base do IOF de checagem. | `receivable_entry.rb:42`, `:53-55`; `receivable_tax.rb:12` (`is_advalorem` vem do tipo de movimento) |
| `tarifas_desagio` | Soma automática das tarifas marcadas como deságio. É o juro do borderô: sozinha ela dá as duas checagens de taxa nominal, e se ficar zerada as taxas nominais de deságio saem em branco. | `receivable_entry.rb:43`, `:53-55`, `:67`, `:81`, `:117-118`; `receivable_tax.rb:13` |
| `tarifas_iof` | Soma automática das tarifas marcadas como IOF. É o valor a comparar com a checagem de IOF, e é o que volta para o líquido nos custos efetivos sem IOF. | `receivable_entry.rb:44`, `:55`, `:68`, `:71`, `:101`; `receivable_tax.rb:14` |
| `tarifas_outras` | Tudo que foi lançado como tarifa e não é ad valorem, deságio nem IOF. Sai por diferença, então tarifa com o tipo errado cai aqui em vez de entrar na conta certa. | `receivable_entry.rb:45` (total − ad valorem − deságio − IOF) |
| `custo_efetivo_pz_med_banco` | Custo efetivo mensal pela ótica do portador: o desconto do bruto final sobre o líquido, elevado a 30 dias sobre o prazo do banco mais o float. Fica zerado se o prazo do banco for zero. | `receivable_entry.rb:76-78` — `round(4)`, guarda em `prz_med_pond_bco == 0` |
| `custo_efetivo_pz_med_emp` | Custo efetivo mensal pela ótica da empresa: o mesmo desconto, elevado a 30 dias sobre o prazo da empresa mais o float. É o número por onde a lista de recebíveis ordena o CET. | `receivable_entry.rb:90-92` — `round(4)`; `:208` (chave de ordenação `cet`) |
| `custo_efetivo_sem_float` | Mesmo custo efetivo da empresa, sem somar o float ao prazo. Mostra o custo puro do prazo dos títulos, sem a diluição que o float provoca. | `receivable_entry.rb:95-97`; `:210` (ordenação `cetsf`) |
| `resource_kind_id` | TODO: precisa saber se é a mesma classificação de Utilização de recursos ou outra coisa — a coluna existe, mas nenhuma tela a preenche e nada a lê. | **TODO.** Migration `:11`; `receivables_controller.rb:191`. Nunca preenchido (D-74) |
| `movement_kind_id` | Tipo da tarifa lançada. É ele que decide em qual balde a tarifa cai — ad valorem, deságio, IOF ou outras — e, portanto, de quais taxas e custos efetivos ela participa. | `receivable_tax.rb:10-14`; `movement_kind.rb#tax_kind` (um só entre ad valorem / deságio / IOF / liquidação); formulário `:474` |
| `recompra_percent` | Recompra em percentual do líquido, calculada automaticamente. Fica zerada quando a recompra está em branco. | `receivable_entry.rb:59` |
| `retencao_percent` | Retenção em percentual do líquido, calculada automaticamente. Fica zerada quando a retenção está em branco. | `receivable_entry.rb:60` |
| `fomento_percent` | Fomento em percentual do líquido, calculado automaticamente. Fica zerado quando o fomento está em branco. | `receivable_entry.rb:61` |
| `outros_percent` | Outras deduções em percentual do líquido, calculadas automaticamente. Fica zerado quando o campo está em branco. | `receivable_entry.rb:62` |
| `taxa_desconto_nominal_desagio_advalorem_bancos` | Taxa nominal mensal do deságio somado ao ad valorem, sobre o bruto final, ao prazo do banco. Sai em branco quando não há deságio lançado ou o líquido é menor que R$ 1,00. | `receivable_entry.rb:67` — `nil` se `valor_liquido < 1` ou `tarifas_desagio < 1` |
| `taxa_desconto_nominal_despesas_bancos` | Taxa nominal mensal de todas as tarifas exceto o IOF, ao prazo do banco. Sai em branco quando não há IOF lançado ou o líquido é menor que R$ 1,00. | `receivable_entry.rb:68` — `nil` se `valor_liquido < 1` ou `tarifas_iof < 1` |
| `taxa_desconto_nominal_despesas_iof_bancos` | Taxa nominal mensal de todas as tarifas, IOF incluído, ao prazo do banco. É calculada sempre, sem a trava de valor mínimo que as outras duas têm. | `receivable_entry.rb:69` — sem guarda |
| `custo_efetivo_pz_med_banco_sem_iof` | Custo efetivo do banco desconsiderando o IOF: o IOF volta para o líquido antes do desconto, e o prazo é o do banco mais o float. Zera quando o prazo médio da empresa é zero. | `receivable_entry.rb:71-74` — base no prazo do **banco**, guarda no prazo da **empresa** (DEC-32 / P-007) |
| `taxa_desconto_nominal_desagio_advalorem_emp` | Mesma taxa nominal de deságio mais ad valorem, agora ao prazo da empresa. Sai em branco quando não há deságio lançado ou o líquido é menor que R$ 1,00. | `receivable_entry.rb:81` |
| `taxa_desconto_nominal_despesas_emp` | Taxa nominal mensal das tarifas exceto o IOF, ao prazo da empresa. Sai em branco quando não há IOF lançado ou o líquido é menor que R$ 1,00. | `receivable_entry.rb:82` |
| `taxa_desconto_nominal_despesas_iof_emp` | Taxa nominal mensal de todas as tarifas, IOF incluído, ao prazo da empresa. É calculada sempre, sem trava de valor mínimo. | `receivable_entry.rb:83` — sem guarda |
| `custo_efetivo_pz_med_emp_sem_iof` | Custo efetivo da empresa desconsiderando o IOF: o IOF volta para o líquido antes do desconto, ao prazo da empresa mais o float. Zera quando o prazo da empresa é zero. | `receivable_entry.rb:85-87` |
| `custo_efetivo_com_float_total` | Custo efetivo da empresa com float. É a mesma conta do Efetivo Empresa, fechada em duas casas decimais em vez de quatro. | `receivable_entry.rb:99` — mesma álgebra de `:90-92`, `round(2)` (DEC-33 / P-008) |
| `custo_efetivo_com_float_sem_iof` | Custo efetivo da empresa com float e sem IOF, fechado em duas casas. Sai em branco quando não há IOF lançado ou o líquido é menor que R$ 1,00. | `receivable_entry.rb:101` — mesma álgebra de `:85-87`, `round(2)`, com guarda de `nil` |
| `multiplicador_pm_empresa` | Bruto final multiplicado pelo prazo médio da empresa, gravado automaticamente. Fica em branco se faltar qualquer um dos dois. | `receivable_entry.rb:104` |
| `multiplicador_pm_float` | Bruto final multiplicado pelo prazo médio do banco. Apesar do nome, o float acordado não entra nesta conta. | `receivable_entry.rb:105` — usa `prz_med_pond_bco`, **não** o float |
| `nominal_tax` | Taxa nominal mensal combinada com o portador, em percentual. Não entra em nenhuma conta do borderô: é copiada como taxa acordada da operação de risco gerada e serve de referência para as duas checagens ao lado. | `receivable_entry.rb:163` (vira `agreed_rate` da operação de risco); formulário `:389` (entrada do usuário) |
| `nominal_tax_check` | Taxa nominal que o deságio de fato representa: deságio sobre o bruto final, dividido pelo prazo da empresa em meses. É o número a comparar com o nominal acordado. | `receivable_entry.rb:117` |
| `nominal_tax_check_with_float` | Mesma checagem, com o float acordado somado ao prazo da empresa. Quanto maior o float, menor a taxa que sai aqui. | `receivable_entry.rb:118` |
| `description` | Texto livre sobre o borderô. Não entra em nenhuma conta. | Formulário `:113-114` (`text_area`); `receivables_controller.rb` (permitido). Sem uso em cálculo |
| `risk_operation_type_id` | Tipo de operação de risco a que o borderô se vincula. Exige limite cadastrado para a empresa no portador — sem limite o borderô não salva — e decide se o líquido vira uma operação de risco nova ou um movimento de liberação na operação de pré-faturamento existente. | `receivable_entry.rb:25-36` (exige limite), `:39`, `:127-170` (pré-faturamento → movimento; senão → operação nova); formulário `:93-95` |

---

## Operações de risco — 13 campos

| Campo | Texto escrito | Fundamento no código |
| --- | --- | --- |
| `nro_contrato` | Número do contrato da operação no portador. É identificação — serve para localizar e ordenar a operação e não entra em nenhum cálculo. | `risk_operation.rb:125` (copiado na renovação), `:180` (ordenação); formulário `:35` (`contract_number`) |
| `titulo` | Nome da operação na lista. Se ficar em branco, a operação passa a se chamar como o portador. | `risk_operation.rb:24` (em branco recebe `carrier.title`) |
| `carrier_id` | Portador da operação. Junto com empresa e tipo, é a chave que localiza o limite de risco que a operação vai consumir — sem limite cadastrado para essa combinação a operação não salva. | `risk_operation.rb:21-22` (busca do `RiskControl`), `:56`, `:62` (`risk_control_id` obrigatório); `risk_control.rb:72` |
| `operation_type_id` | Tipo da operação. Define o limite consumido e o subtipo, que decide se o saldo entra no bloco liquidável ou no de pré-faturamento do painel de risco. Em tipo sem pré-faturamento, a criação já gera o movimento de liberação de recurso com o capital da operação. | `risk_operation.rb:21`, `:29-33` (subtipo), `:39-51` (movimento automático quando não há pré-faturamento); `risk_control.rb:129-130` (liquidável) e `:144-145` (pré) |
| `company_id` | Empresa que toma a operação. Define o projeto do registro e entra na chave do limite de risco. | `risk_operation.rb:28` (define o projeto), `:21` (chave do limite) |
| `description` | Texto livre sobre a operação, gravado como observação e copiado para a renovação. Não entra em nenhum cálculo. | Formulário `:111-112` — o campo é `observation`; `risk_operation.rb:130` (copiado na renovação) |
| `issue_date` | Data de emissão, obrigatória. A operação só conta na exposição do painel entre esta data e o vencimento, e é ela que data o movimento automático de liberação de recurso. | `risk_operation.rb:59` (obrigatória), `:42` (data do movimento); `risk_control.rb:76` (janela de exposição) |
| `due_date` | Vencimento, obrigatório. Fora da janela entre emissão e vencimento a operação deixa de somar no limite utilizado; prorrogar altera esta data e o vencimento original fica guardado. | `risk_operation.rb:23` (`original_due_date`), `:61`; `risk_control.rb:76`; `risk_operation_extension.rb:8-11` (prorrogação) |
| `operation_value` | Capital da operação, obrigatório. É o valor do movimento de liberação de recurso gerado na criação e a base do recibo — a remuneração é um percentual dele. | `risk_operation.rb:44` (valor do movimento), `:60`; `receipt.rb:62-63` (base da remuneração) |
| `balance` | Saldo com que a operação nasce. É sempre gravado como valor negativo, e os movimentos lançados depois somam sobre ele para dar o saldo que consome o limite. | `risk_operation.rb:34` (forçado negativo), `:98-111` (acumula os movimentos); formulário `:193` (`original_balance`) |
| `agreed_rate` | Taxa acordada da operação, em percentual. Vem preenchida com a taxa do limite quando a operação nasce do próprio limite, e com a taxa nominal do borderô quando nasce de um recebível; é registro, não base da remuneração. | `risk_control.rb:52` (vem da taxa do limite); `receivable_entry.rb:163` (vem da taxa nominal do borderô); `receipt.rb:61-63` não o usa (D-74 / DEC-34) |
| `is_on_variable` | TODO: precisa saber o que é o variável e quem o apura — o campo é gravado na operação e copiado para a renovação, mas nenhum cálculo do sistema o lê. | **TODO.** `risk_operation.rb:131` (só copiado na renovação); zero leitores no repositório (D-74) |
| `is_ended` | Marca a operação como encerrada. No painel de risco o saldo passa do bloco a vencer para o de vencidos; a operação continua somando no limite utilizado e continua aceitando movimento e prorrogação. | `risk_control.rb:94` (bloco `vencidos`) e `:106` (bloco `a vencer`); `:117-124` (`limite_utilizado` ignora o flag); DEC-35 / D-94 |

---

## Operações estruturadas — 13 campos

| Campo | Texto escrito | Fundamento no código |
| --- | --- | --- |
| `nro_contrato` | Número do contrato da operação no portador. É identificação — serve para localizar e ordenar a operação e não entra em nenhum cálculo. | `structured_operation.rb:83` (ordenação); formulário `:35` (`contract_number`) |
| `titulo` | Nome da operação na lista. Se ficar em branco, a operação passa a se chamar como o portador. | `structured_operation.rb:32` (em branco recebe `carrier.title`) |
| `carrier_id` | Portador da operação. Aqui é só o portador do contrato: operação estruturada não consome limite de risco. | `structured_operation.rb:3`, `:15`. Não há `RiskControl` no modelo — operação estruturada não consome limite |
| `operation_type_id` | Tipo da operação. É por ele que o recibo encontra a remuneração cadastrada no projeto — sem remuneração para este tipo, a operação não pode ser faturada. | `receipt.rb:47-53` (localiza a `Remuneration` do projeto; sem ela o faturamento levanta erro); `structured_operation.rb:16` |
| `company_id` | Empresa da operação. É ela que define o projeto do registro. | `structured_operation.rb:36` (`project_id = company.project_id`) |
| `description` | Texto livre sobre a operação, gravado como observação. Não entra em nenhum cálculo. | Formulário `:83-84` — o campo é `observation`; sem uso em cálculo |
| `issue_date` | Data de emissão, obrigatória. É a data que o recibo assume ao faturar a operação; não entra no cálculo da remuneração. | `structured_operation.rb:18` (obrigatória); `receipt.rb:46` (vira a data do recibo) |
| `due_date` | Vencimento, obrigatório. É informação de controle: não entra no valor da remuneração, que é um percentual fechado sobre o capital, sem proporção por prazo. | `structured_operation.rb:20` (obrigatório); `receipt.rb:63` não o usa — percentual flat (DEC-34 / D-72) |
| `operation_value` | Capital da operação, obrigatório. É a base inteira da remuneração — o recibo vale este capital multiplicado pelo percentual da remuneração do projeto. | `structured_operation.rb:19`; `receipt.rb:62-63` (`value = operation_value * fee / 100`) |
| `balance` | Saldo inicial da operação, sempre gravado como valor negativo. O saldo da operação é igual a ele e é reescrito a cada gravação: não existe baixa de saldo em operação estruturada. | `structured_operation.rb:37-38` — negativo forçado e reescrito a cada gravação; não há baixa de saldo no legado (D-73) |
| `agreed_rate` | Taxa acordada da operação, em percentual. É registro do que foi combinado — o valor faturado sai do percentual da remuneração do projeto, não desta taxa. | `receipt.rb:61-63` usa `remuneration.value`, não este campo (D-74 / DEC-34) |
| `is_on_variable` | TODO: precisa saber o que é o variável e quem o apura — o campo é gravado na operação, mas nenhum cálculo do sistema o lê. | **TODO.** `structured_operation.rb:50-55` (só as opções do select); zero leitores no repositório (D-74) |
| `is_ended` | Marca a operação como encerrada. É marcador de cadastro: não bloqueia o faturamento, não altera o saldo e não filtra a lista. | `structured_operation.rb:43-48` (só as opções do select); `structured_operations_controller.rb:171` (permitido). Zero leitores — `risk_control.rb` só trata `RiskOperation` |

---

## Notas de leitura que não couberam no tooltip

- **23 dos 65 campos de recebíveis não aparecem em tela nenhuma** — são calculados no
  `before_validation` e gravados: as 6 `taxa_desconto_nominal_*`, `custo_efetivo_com_float_total`,
  `custo_efetivo_com_float_sem_iof`, os dois `custo_efetivo_*_sem_iof`, os dois `multiplicador_pm_*`,
  os quatro `*_percent`, as quatro `tarifas_*` agregadas, `contrato`, `observacoes` e
  `resource_kind_id`. Escrevi o texto de todos assim mesmo: no ai9 o tooltip passa a existir se o
  campo for exibido, e o YAML é a fonte.
- **A chave `description` dos formulários de risco e de estruturadas aponta para o campo
  `observation`** (rotulado *Observação*), não para uma coluna `description`. O texto foi escrito
  para o campo que o operador vê.
- **A chave `balance` desses dois formulários é o `original_balance`**, rotulado *Saldo Inicial* —
  não o saldo corrente. Idem.
- **`risk_operation_type_id` no borderô controla o select de `risk_operation_subtype_id`.** O texto
  descreve o efeito real (limite exigido + destino do líquido), que é o que muda conforme a escolha.

## Defeitos novos encontrados ao ler as fórmulas

Nenhum deles muda os textos acima; ficam registrados porque saíram desta leitura.

1. **`data_credito` em branco impede, em silêncio, a criação da operação de risco.**
   `receivable_entry.rb:162` passa `due_date: self.data_credito`, e `risk_operation.rb:61` exige
   `due_date`. O `RiskOperation.create` do `after_commit` falha, não levanta exceção e não avisa
   ninguém — o borderô salva normalmente e a operação simplesmente não existe. Mesma família do
   D-11, mas é um caminho diferente (lá é valor errado; aqui é registro ausente).
2. **Cinco campos do formulário de recebíveis testam a variável errada para decidir o valor
   exibido.** `receivables/new/_body.html.erb:297,303,312,319,329` fazem
   `@receivable.checagem_iof.blank? ? 0 : @receivable.<campo>` para `recompra`, `retencao`,
   `fomento`, `outros` e `total_deducoes`. Copy-paste: a guarda deveria olhar o próprio campo. Numa
   edição em que a checagem de IOF esteja zerada/nula, os cinco aparecem como R$ 0,00 mesmo tendo
   valor gravado.
3. **`taxa_desconto_nominal_despesas_iof_bancos` (`:69`) e `_emp` (`:83`) não têm guarda alguma**,
   ao contrário das quatro irmãs. Com `vlr_bruto_final` zero elas dividem por zero e gravam
   `Infinity`/`NaN` no banco — é o D-10 concretizado em duas colunas específicas.
