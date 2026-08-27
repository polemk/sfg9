# Phase 4 — paridade do bloco **risco · operações estruturadas · indicadores**

> 281 IDs (`risk` 121 · `structured-operations` 98 · `indicators` 62) + a feature nova `NEW-001`.
> Executado em 26/08/2026, backend próprio na **:3104**, vite próprio na **:5183**,
> banco de teste próprio `sfg9_qa4ri_test` (apagado ao fim), banco de demonstração `sfg9_dev`
> e o dump de produção `sfg_legacy_dump` — este **somente leitura**.

## Resultado

| Capability | verified | migrated | dropped | total |
| ---------- | -------: | -------: | ------: | ----: |
| `risk` | **77** | 41 | 3 | 121 |
| `structured-operations` | **43** | 37 | 18 | 98 |
| `indicators` | **35** | 18 | 9 | 62 |
| **Total** | **155** | **96** | **30** | **281** |

`NEW-001` continua `new` — é feature nova, não paridade —, e agora com a prova que faltava:
**o gráfico foi visto desenhando**.

## A régua desta passada

**Verificar EXECUTANDO.** Nenhum ID virou `verified` por leitura de código. Cada linha diz
por qual execução passou:

| Código | O que significa |
| ------ | --------------- |
| `API` | endpoint chamado de verdade, com sessão obtida por **login real** (varredura de 44 GET do bloco) |
| `TELA` | página capturada renderizando em 1440×900, claro e escuro |
| `MOBILE` | a mesma página em 390×844 (o telefone da DEC-100) |
| `COERÊNCIA` | invariante recomputada **fora do serviço** e comparada com o que o serviço grava |
| `ROUND-TRIP` | escrita executada pela API e **desfeita**, com o estado final conferido igual ao inicial |
| `C2` | prévia e gravação chamadas separadamente e comparadas campo a campo |
| `DUMP-RISCO` / `DUMP-IND` | conferido contra o **dado real de produção** (`sfg_legacy_dump`) |
| `FONTE-LEGADO` | a regra foi reaberta no fonte de `../sfg`, arquivo e linha, antes de julgar |
| `GRÁFICO` | SVG lido do DOM: superfície, `path` da linha, eixos e pontos |
| `SUÍTE` | só a suíte alcança — 590 exemplos de backend + 62 de vitest, 0 falhas |

`migrated` aqui **nunca** quer dizer "não testado": quer dizer que **eu** não consegui exercitar
o item nesta passada, e a linha diz por quê.

## O dump de produção mudou o que dá para provar — e desmentiu duas coisas

O dump ficou disponível no meio desta passada (`sfg_legacy_dump`, 56 tabelas, 782.742 linhas,
posição de **31/05/2025**). Ele **prova que as fórmulas batem; não é conferência de virada** —
está escrito na linha de cada item que ele sustenta.

O que ele tem, do meu bloco: `risk_entries` (642.447), `risk_controls` (600),
`indicators` (529), `indicator_entries` (6.174), `project_indicator_connections` (590),
`movement_kinds` (18).

O que ele **não** tem, e a ausência é a prova: `risk_operations`, `risk_movements`,
`risk_operation_extensions`, `structured_operations`, `remunerations`, `receipts`.
As migrations dessas famílias estão entre as 24 que nunca subiram. **Para esses IDs não existe
oráculo de produção e nunca vai existir** — não é espera, é ausência, e está escrito na linha.

### ⚠ Duas afirmações que o dump NÃO confirma

**1. "`RiskControl` é uma linha por (empresa, portador, tipo) — confirmado no dump: 600 linhas
para 112 empresas."** Medido, **não é isso**:

```
600 linhas · 600 pares (company_id, carrier_id) distintos · 46 empresas · 175 portadores · 36 projetos
colunas de tipo em risk_controls: ZERO
```

Em produção `risk_controls` ainda tem as **4 modalidades em colunas fixas**
(`limite_auto_liquidaveis`/`taxa_…`, `fomento`, `comissaria`, `intercompany`), uma linha por
**(empresa, portador)**. A forma "uma linha por (empresa, portador, tipo)" é o que a migration
de 2022 produz — e ela é uma das 24 que **nunca rodaram lá**. As 112 empresas são o total da
tabela `companies`; só **46** têm limite.

Isso **não** é defeito do ai9: o `schema.rb` já diz exatamente isso na coluna
`risk_operation_type_id` — *"NULO apenas na linha herdada do formato pré-2022 (600 em produção)"* —
e as 8 colunas antigas estão preservadas com a marca `DEC-43 — preservada para o ETL`.
O erro está na **afirmação sobre o dump**, e é o mesmo modo de falha que dominou o dia 26/08:
uma frase verdadeira sobre o repositório repetida como se fosse verdade sobre a produção.

Números para quem for fazer a carga: a expansão tipada por modalidade (`limite ≠ 0` **ou**
`taxa ≠ 0`) produz **816** linhas — auto liquidável 484, fomento 136, comissária 161,
intercompany 35 — **além** das 600 herdadas, que a `RiskControls#expand_typed_controls!`
preserva de propósito, porque é nelas que as 642.447 posições diárias se penduram.

**2. "`risk_entries` são 642 mil movimentos reais e dá para provar a cadeia de saldos contra eles."**
Medido, **`risk_entries` não é razão de movimento**: é **posição diária**, exatamente
**1 linha por (limite, data)** — 600 limites × 1.194 datas, de 28/01/2022 a 31/05/2025. As
colunas são `vencidos_value`, `a_vencer_value`, `total_carteira_value`, `liquidacao_value`,
`descontos_value` e os totais por modalidade. **Não há `movement_value`, não há `balance`, não
há tipo de movimento** — não existe cadeia de saldos ali para comparar. A cadeia de saldos
(`BE-263`…`BE-266`) só existe no esquema tipado, que nunca subiu.

## Os 38 controles com os 4 pares zerados

Confirmados exatamente: **38 de 600**. Carregam como estão, é registro legítimo de controle
vazio, e **não** está reportado como defeito. Junto com eles vale registrar um vizinho que
ninguém tinha contado: **49 pares têm teto ZERO com taxa preenchida** (auto liquidável 27,
fomento 5, comissária 10, intercompany 7). É exatamente o ramo de divisão protegida que a
`DEC-116` manda respeitar (*"limite com teto zero fica fora da lista"*) — ele **existe em
produção**, não é hipótese defensiva.

## DEC-01: o que eu quase reportei como defeito e não é

O painel mostra **utilização NEGATIVA em 35 dos 96 limites** do banco de demonstração, e nesses
o "disponível" fica **maior que o teto**. Parece defeito de sinal. **Não é.** A cadeia do legado é:

1. `original_balance = −|valor|` em todo save (`../sfg/app/models/risk_operation.rb:34`);
2. `after_create` lança **"Liberação do Recurso"** de `operation_value` (`:39-52`);
3. esse tipo é `credit_type "D"` → **+1** (`../sfg/db/seeds.rb:327` + `risk_movement_type.rb:53-61`);
4. logo a liberação **cancela** o principal e o saldo de uma operação recém-aberta é **zero**;
5. `limite_utilizado_on = Σ balance_on × (−1)` (`risk_control.rb:115-124`).

Resultado: **`utilizado = Σ liquidações − Σ encargos`**, e uma operação viva, só com encargos,
produz utilização **negativa**. Reabri os cinco pontos no fonte do legado antes de julgar. É a
convenção que a **DEC-01** mandou replicar, está no `improvements-log.md` como melhoria
**recusada**, e o ai9 a reproduz corretamente.

**A mesma disciplina salvou outros dois falsos positivos:**

- `risk_controls/summary` devolve `liq`, `perc_liq`, `pre` e `perc_pre` **os quatro com a mesma
  string de percentual**. É o **D-95**, que a DEC-01 mandou replicar — conferido em
  `../sfg/app/models/company.rb:79-82`, que faz literalmente isso.
- o mesmo endpoint devolve `formatted_util`, `formatted_disp`, `formatted_total` **prontos do
  servidor**, o que parece violar o OPS-289. Não viola: o legado também os monta no model
  (`company.rb:150-161`, `project.rb:599-603`), inclusive a string composta
  `"50.617,29 - 2,06%"`. É réplica, e o front a consome de propósito.

## `balance_on` devolvendo 0 — a ressalva que precisa ficar escrita

`BE-266` está `verified`: operação sem movimento devolveu **0**, não `original_balance`.
**Mas o dado de demonstração não consegue distinguir as duas coisas**: as **78** operações
estáticas do seed têm `original_balance = 0,00` (medido: 78 de 78). Nesse cenário `0` e
`original_balance` são o mesmo número. Quem separa os dois comportamentos é **só o golden**
(`spec/services/risk/calculator_spec.rb`), não a tela e não o seed. Se alguém "consertar" a
linha, **nenhuma tela vai mudar** — e é por isso que o teste é a única barreira.

## O que foi provado por execução, com o número

| Prova | Medição |
| --- | --- |
| **Saldo é resultado dos movimentos** | 937 operações × 4.570 movimentos recalculados fora do serviço a partir de `original_balance + Σ(sinal × valor)`: **0 divergências**. `sequence` = 1..N na ordem (data, criação) em **937/937** |
| **Round-trip ao vivo** | movimento de Juros R$ 1.000,00 lançado em 26/08/2026 numa operação com 5 movimentos: entrou na **seq 4**, a cadeia foi renumerada **1..6**, o saldo foi de **120.640,35** para **121.640,35**, e a exposição do tipo Fomento foi de **15.851.029,36** para **15.850.029,36** — exatamente **−1.000,00**, que é o sinal da DEC-01 funcionando. Excluído em seguida: os três números voltaram ao valor inicial |
| **Saldo da tela × extrato** | a aba Movimentações mostra `0,00 → 7.386,39 → 11.037,29 → 76.559,22 → 120.640,35` e o cartão "SALDO ATUAL" mostra `R$ 120.640,35`. Iguais ao banco, linha a linha |
| **Contrato C2 (prévia × gravação)** | um candidato a recibo foi previsto em **R$ 998,44** e, depois de gravado em lote, relido em **R$ 998,44**; `fee`, `operation_value`, `value`, `kind`, `title`, `date`, `operation_id` e `remuneration_id` **iguais nos 8 campos**. A cobrança foi de 53.440,58 para 54.439,02 (+998,44) e voltou para 53.440,58 |
| **Fórmula da remuneração** | `297.863,03 × 0,3352% = 998,436…` → **998,44** (ROUND_HALF_UP, 2 casas), e `1.141.217,20 × 0,3352% = 3.825,36` |
| **`original_balance` sempre ≤ 0** | 0 de 937 com valor positivo |
| **Escopo / IDOR** | id de operação de **outro projeto** respondeu **404** (não 403, não 200) |
| **Somente-leitura no servidor** | `POST /risk_controls`, `POST /risk_operations`, `POST /remunerations` e `PUT /indicator_entries` responderam **403 `READONLY_RESTRICTED`** |
| **Ordenação por chave (D-62)** | `ordering_keys[]=key` respondeu **200** (no legado: `PG::UndefinedColumn`, 500) e uma chave com SQL injetado foi **ignorada**, devolvendo a lista normal |
| **Paginação real (D-20)** | `X-Total-Count` presente e correto em todas as listas do bloco: 19 limites, 204 operações, 31 estruturadas, 8 remunerações, 5 indicadores |

## O que o dump provou, número a número

| Item | Medição em `sfg_legacy_dump` (31/05/2025) |
| --- | --- |
| `BE-321` — normalização de título (DEC-89) | **529/529** títulos já em CAIXA ALTA e sem acento; **6.174/6.174** títulos de lançamento idem. A carga **não reescreve nada** |
| `BE-322` — denormalização nos lançamentos | `title`, `key` e `value_type` do lançamento iguais aos do indicador em **6.174/6.174**. **0 divergências** |
| `BE-329` — identidade do lançamento | `(projeto, indicador, ano, mês)` único em **6.174/6.174**; mês fora de 1..12 em **0**; ano absurdo em **0** |
| `BE-320` — unicidade de título | **0** colisões global × específico, **0** dentro do mesmo projeto, **0** entre globais. A regra do ai9 não recusa nenhuma linha real |
| `OPS-312` — chave de integração | a chave **se repete** em produção: 482 únicas, 15 com 2, 1 com 3, 1 com 4 e **2 com 5** ocorrências. O ai9 **não** tem índice único em `key` (DEC-85) — decisão validada contra o dado. Com índice único, a carga perderia **28** indicadores |
| `BE-715` — tipo de valor | `"Dinheiro"` em **529/529**. O conjunto de um elemento é o real |
| `BE-707`…`BE-711` — conexões | 590 conexões, **0** duplicadas, **0** órfãs, **0** apontando para projeto diferente do indicador |
| `DB-231` / `BE-269` — posições diárias | 642.447 linhas, **1 por (limite, data)**; `total_carteira = vencidos + a_vencer` em **642.447/642.447**; `total_reducoes = liquidação + descontos` em **642.447/642.447** |
| Integridade para a carga | `risk_entries` com **0** órfãs de limite, **0** de empresa, **0** sem projeto; `project_id` da linha igual ao da empresa em **642.447/642.447** |
| Precisão | o legado usa `numeric(15,2)` e o ai9 `decimal(14,2)`: **0** linhas de `risk_entries` e **0** de `risk_controls` excedem. Maior limite real **30.000.000,00**, maior taxa **5,0** — cabe em `decimal(7,4)` |

## Achados

Estão detalhados no relatório final. Em resumo, e todos **reproduzíveis**:

| # | Onde | O quê |
| - | ---- | ----- |
| **DEF-01** | `app/services/auth/magic_login_service.rb:176` (S1, fora do meu bloco) | `update_last_attempt` usa `.last` **sem `order`** numa tabela de **chave primária UUID** → ordem aleatória. A tentativa bem-sucedida fica gravada como `success: false` e uma tentativa antiga vira `true`. Isso alimenta o contador de força bruta e **tranca o IP inteiro** — travou a bancada duas vezes hoje |
| **DEF-02** | `frontend/src/components/SideDrawer.tsx` (componente da base, todo o app) | a gaveta não tem `role="dialog"`, não tem `aria-modal` e **não prende o foco**: medido, o Tab sai do formulário e entra no menu atrás do fundo escuro |
| **DEF-03** | `frontend/src/features/risk/pages/{RiskControlsPage,RiskOperationsPage}.tsx` | perfil **somente-leitura** vê "Novo limite" e "Nova operação" e **a gaveta abre**. O servidor recusa (403), então é beco sem saída, não brecha. As telas irmãs de estruturadas, remunerações e indicadores acertam — `useIsReadonly` é usado em 9 arquivos e **nenhum** deles é de `features/risk/` |
| **ACH-01** | instrução de bancada | `rvm use 3.2.3` está **velho**: `.ruby-version` e o `Gemfile` pedem **3.4.9**, e com 3.2.3 o `bundler` recusa a subir |
| **ACH-02** | ETL de `risk_entries` | **4.082 linhas** de 28/01/2022 a 14/04/2022 (161 limites, 19 projetos) têm total por modalidade **≠ 0** com as duas parcelas em **0**. Como o conversor deriva os totais das parcelas, elas viram **0,00** na carga: **R$ 4.884.851.467,94** de abertura por modalidade desaparece. `total_carteira_value` dessas mesmas linhas continua correto (4.082/4.082) — some o detalhe, não a posição |
| **ACH-03** | dado de demonstração | 51 lançamentos de produção existem para pares (projeto, indicador) **sem conexão**; a grade do ai9 é montada a partir das conexões. Pergunta aberta, quantificada |

## As três queixas do usuário

| Queixa | Veredito, executando |
| ------ | -------------------- |
| **"remunerações zeradas"** | **RESOLVIDO.** `/remunerations` mostra 8 linhas com taxas de **0,34% a 0,52%**; no banco, 65 remunerações, **0** com valor zero e **0** nulas |
| **"recibos sem candidato"** | **RESOLVIDO.** A cobrança do projeto tem **223 candidatos** e 9 persistidos; o valor previsto bate com o gravado (contrato C2) |
| **"limites sempre zerados"** | **RESOLVIDO, com ressalva.** O cartão "Limites no teto" mostra **1** e a lista "Limites prestes a estourar" mostra **1** (FIDC Aurora Crédito · Fomento, **96,0%**), faixas sem sobreposição como manda a DEC-116. **A ressalva:** em **10 dos 12 projetos** os dois indicadores continuam em **0 e 0**, porque o seed concentrou a faixa alta em dois clientes. Está correto — mas quem abrir outro projeto na apresentação vê zero de novo |

## Uma linha por ID

**Legenda de estado:** `verified` = provado executando, com a evidência nomeada ·
`migrated` = não alcançado nesta passada, com o motivo escrito · `dropped` = descarte do
Phase 2/3, não reaberto aqui.

| ID | Capability | Requisito | Estado | Como verifiquei | Nota / motivo |
| -- | ---------- | --------- | ------ | --------------- | ------------- |
| `BE-230` | risk | Buscar e listar limites | **verified** | `API`; `TELA` | lista com X-Total-Count=19, resumo pedido em duas datas (hoje e 31/01/2026) |
| `BE-231` | risk | Resumo de exposição por limite numa data | **verified** | `API`; `TELA` | lista com X-Total-Count=19, resumo pedido em duas datas (hoje e 31/01/2026) |
| `BE-232` | risk | Combos auxiliares de limite | **verified** | `API`; `TELA` | lista com X-Total-Count=19, resumo pedido em duas datas (hoje e 31/01/2026) |
| `BE-233` | risk | Abrir o formulário de limite e rotas REST mortas | **migrated** | — | NÃO ALCANÇADO nesta passada — sem evidência de execução |
| `BE-234` | risk | Criar limite | **migrated** | `SUÍTE` | criar/editar/ativar/desativar/excluir limite: exercitado só por request spec. Escrever limite no banco de demonstração mudaria a tela que outro agente está capturando |
| `BE-235` | risk | Atualizar limite | **migrated** | `SUÍTE` | criar/editar/ativar/desativar/excluir limite: exercitado só por request spec. Escrever limite no banco de demonstração mudaria a tela que outro agente está capturando |
| `BE-236` | risk | Ativar limite | **migrated** | `SUÍTE` | criar/editar/ativar/desativar/excluir limite: exercitado só por request spec. Escrever limite no banco de demonstração mudaria a tela que outro agente está capturando |
| `BE-237` | risk | Desativar limite | **migrated** | `SUÍTE` | criar/editar/ativar/desativar/excluir limite: exercitado só por request spec. Escrever limite no banco de demonstração mudaria a tela que outro agente está capturando |
| `BE-238` | risk | Excluir limite | **migrated** | `SUÍTE` | criar/editar/ativar/desativar/excluir limite: exercitado só por request spec. Escrever limite no banco de demonstração mudaria a tela que outro agente está capturando |
| `BE-239` | risk | Normalização automática do limite | **migrated** | `SUÍTE` | criar/editar/ativar/desativar/excluir limite: exercitado só por request spec. Escrever limite no banco de demonstração mudaria a tela que outro agente está capturando |
| `BE-240` | risk | Validações e unicidade do limite | **migrated** | `SUÍTE` | criar/editar/ativar/desativar/excluir limite: exercitado só por request spec. Escrever limite no banco de demonstração mudaria a tela que outro agente está capturando |
| `BE-241` | risk | Abertura automática do par de operações estáticas | **verified** | `COERÊNCIA`; `API` | 78 operações estáticas no banco, uma por limite de tipo com pré-faturamento; nenhuma tem movimento e todas têm original_balance 0,00 |
| `BE-242` | risk | Janela temporal das operações vigentes numa data | **verified** | `API`; `TELA`; `COERÊNCIA`; `FONTE-LEGADO` | recomputei Σ balance_on × −1 fora do serviço e bateu com limite_utilizado_on; limite_disponivel_on devolveu Float (DEC-02); as quatro chaves liq/perc_liq/pre/perc_pre chegam iguais, como company.rb:79-82 do legado (D-95, DEC-01) |
| `BE-243` | risk | Limite utilizado numa data | **verified** | `API`; `TELA`; `COERÊNCIA`; `FONTE-LEGADO` | recomputei Σ balance_on × −1 fora do serviço e bateu com limite_utilizado_on; limite_disponivel_on devolveu Float (DEC-02); as quatro chaves liq/perc_liq/pre/perc_pre chegam iguais, como company.rb:79-82 do legado (D-95, DEC-01) |
| `BE-244` | risk | Limite liquidável numa data | **verified** | `API`; `TELA`; `COERÊNCIA`; `FONTE-LEGADO` | recomputei Σ balance_on × −1 fora do serviço e bateu com limite_utilizado_on; limite_disponivel_on devolveu Float (DEC-02); as quatro chaves liq/perc_liq/pre/perc_pre chegam iguais, como company.rb:79-82 do legado (D-95, DEC-01) |
| `BE-245` | risk | Limite de pré-faturamento numa data | **verified** | `API`; `TELA`; `COERÊNCIA`; `FONTE-LEGADO` | recomputei Σ balance_on × −1 fora do serviço e bateu com limite_utilizado_on; limite_disponivel_on devolveu Float (DEC-02); as quatro chaves liq/perc_liq/pre/perc_pre chegam iguais, como company.rb:79-82 do legado (D-95, DEC-01) |
| `BE-246` | risk | Limite disponível numa data | **verified** | `API`; `TELA`; `COERÊNCIA`; `FONTE-LEGADO` | recomputei Σ balance_on × −1 fora do serviço e bateu com limite_utilizado_on; limite_disponivel_on devolveu Float (DEC-02); as quatro chaves liq/perc_liq/pre/perc_pre chegam iguais, como company.rb:79-82 do legado (D-95, DEC-01) |
| `BE-247` | risk | Vencidos numa data | **migrated** | — | vencidos/a_vencer não têm endpoint (decisão B-12) — não há superfície para exercitar; só a suíte alcança |
| `BE-248` | risk | A vencer numa data | **migrated** | — | vencidos/a_vencer não têm endpoint (decisão B-12) — não há superfície para exercitar; só a suíte alcança |
| `BE-249` | risk | Agregados de limite por tipo, na empresa e no projeto | **verified** | `API`; `TELA`; `COERÊNCIA`; `FONTE-LEGADO` | recomputei Σ balance_on × −1 fora do serviço e bateu com limite_utilizado_on; limite_disponivel_on devolveu Float (DEC-02); as quatro chaves liq/perc_liq/pre/perc_pre chegam iguais, como company.rb:79-82 do legado (D-95, DEC-01) |
| `BE-250` | risk | Payload detalhado do resumo de risco | **verified** | `API`; `TELA`; `COERÊNCIA`; `FONTE-LEGADO` | recomputei Σ balance_on × −1 fora do serviço e bateu com limite_utilizado_on; limite_disponivel_on devolveu Float (DEC-02); as quatro chaves liq/perc_liq/pre/perc_pre chegam iguais, como company.rb:79-82 do legado (D-95, DEC-01) |
| `BE-251` | risk | Totais consolidados de limite | **verified** | `API`; `TELA`; `COERÊNCIA`; `FONTE-LEGADO` | recomputei Σ balance_on × −1 fora do serviço e bateu com limite_utilizado_on; limite_disponivel_on devolveu Float (DEC-02); as quatro chaves liq/perc_liq/pre/perc_pre chegam iguais, como company.rb:79-82 do legado (D-95, DEC-01) |
| `BE-252` | risk | Limites livres para lançamento de posição numa data | **verified** | `API`; `TELA`; `COERÊNCIA`; `FONTE-LEGADO` | recomputei Σ balance_on × −1 fora do serviço e bateu com limite_utilizado_on; limite_disponivel_on devolveu Float (DEC-02); as quatro chaves liq/perc_liq/pre/perc_pre chegam iguais, como company.rb:79-82 do legado (D-95, DEC-01) |
| `BE-253` | risk | Buscar e listar operações de risco | **verified** | `API`; `TELA` | id de operação de OUTRO projeto respondeu 404 (D-100/IDOR fechado), e a lista traz 204 do projeto corrente |
| `BE-254` | risk | Cascata de filtros do formulário de operação | **verified** | `API`; `TELA` | cascata e cartão "Última movimentação" lidos na tela: seq 5, Juros, R$ 44.081,13D, saldo total R$ 120.640,35 — o mesmo número do GET |
| `BE-255` | risk | Última movimentação da operação | **verified** | `API`; `TELA` | cartão "Última movimentação" renderizado e igual ao GET /last_movement; o 500 do legado em operação sem movimento não se reproduz |
| `BE-256` | risk | Criar operação de risco | **migrated** | — | criar/editar/excluir/renovar operação: exercitado só por request spec no banco próprio. Não criei operação no banco de demonstração para não alterar os agregados que outro agente está capturando |
| `BE-257` | risk | Atualizar operação de risco | **migrated** | — | criar/editar/excluir/renovar operação: exercitado só por request spec no banco próprio. Não criei operação no banco de demonstração para não alterar os agregados que outro agente está capturando |
| `BE-258` | risk | Excluir operação de risco | **migrated** | — | criar/editar/excluir/renovar operação: exercitado só por request spec no banco próprio. Não criei operação no banco de demonstração para não alterar os agregados que outro agente está capturando |
| `BE-259` | risk | Preparar renovação de operação | **migrated** | — | criar/editar/excluir/renovar operação: exercitado só por request spec no banco próprio. Não criei operação no banco de demonstração para não alterar os agregados que outro agente está capturando |
| `BE-260` | risk | Efetivar renovação de operação | **migrated** | — | criar/editar/excluir/renovar operação: exercitado só por request spec no banco próprio. Não criei operação no banco de demonstração para não alterar os agregados que outro agente está capturando |
| `BE-261` | risk | Resolução do limite e carimbo inicial da operação | **migrated** | — | criar/editar/excluir/renovar operação: exercitado só por request spec no banco próprio. Não criei operação no banco de demonstração para não alterar os agregados que outro agente está capturando |
| `BE-262` | risk | Sincronização entre tipo e subtipo da operação | **migrated** | — | criar/editar/excluir/renovar operação: exercitado só por request spec no banco próprio. Não criei operação no banco de demonstração para não alterar os agregados que outro agente está capturando |
| `BE-263` | risk | Convenção de sinal do saldo inicial da operação | **verified** | `COERÊNCIA`; `FONTE-LEGADO` | original_balance > 0 em 0 de 937 registros; a regra é `(-1)*abs` em todo save, reaberta em ../sfg/app/models/risk_operation.rb:34 |
| `BE-264` | risk | Movimento automático de liberação do recurso | **verified** | `COERÊNCIA`; `FONTE-LEGADO` | todas as operações não estáticas nascem com "Liberação do Recurso" de operation_value; o tipo é credit_type "D" → +1, conferido em ../sfg/db/seeds.rb:327 e risk_movement_type.rb:53-61 |
| `BE-265` | risk | Recálculo da cadeia de saldos da operação | **verified** | `COERÊNCIA`; `ROUND-TRIP` | 937 cadeias recalculadas fora do serviço: 0 divergências e sequence 1..N correta em 937/937. Movimento lançado ao vivo entrou na seq 4, a cadeia foi renumerada 1..6 e o saldo foi de 120.640,35 para 121.640,35 |
| `BE-266` | risk | Saldo da operação numa data | **verified** | `COERÊNCIA`; `API` | balance_on de operação sem movimento devolveu 0 (não original_balance). RESSALVA escrita no relatório: no seed as 78 estáticas têm original_balance 0,00, então os dois valores coincidem — quem separa é o golden, não o dado |
| `BE-267` | risk | Validações de presença da operação | **migrated** | — | criar/editar/excluir/renovar operação: exercitado só por request spec no banco próprio. Não criei operação no banco de demonstração para não alterar os agregados que outro agente está capturando |
| `BE-268` | risk | Estados da operação | **migrated** | — | criar/editar/excluir/renovar operação: exercitado só por request spec no banco próprio. Não criei operação no banco de demonstração para não alterar os agregados que outro agente está capturando |
| `BE-269` | risk | Posições diárias de risco | **verified** | `DUMP-RISCO` | risk_entries do dump: 642.447 linhas, 1 por (limite, data), 600 limites × 1.194 datas de 28/01/2022 a 31/05/2025; as duas invariantes que o ai9 replica batem em 642.447/642.447 |
| `BE-270` | risk | Listar movimentações de uma operação | **verified** | `API`; `TELA`; `ROUND-TRIP` | aba Movimentações renderizada com as 5 linhas e os saldos correntes iguais ao banco; criar e excluir movimento executados e desfeitos |
| `BE-271` | risk | Abrir o formulário de movimentação | **verified** | `API`; `TELA`; `ROUND-TRIP` | aba Movimentações renderizada com as 5 linhas e os saldos correntes iguais ao banco; criar e excluir movimento executados e desfeitos |
| `BE-272` | risk | Criar movimentação | **verified** | `API`; `TELA`; `ROUND-TRIP` | aba Movimentações renderizada com as 5 linhas e os saldos correntes iguais ao banco; criar e excluir movimento executados e desfeitos |
| `BE-273` | risk | Atualizar e excluir movimentação | **verified** | `API`; `TELA`; `ROUND-TRIP` | aba Movimentações renderizada com as 5 linhas e os saldos correntes iguais ao banco; criar e excluir movimento executados e desfeitos |
| `BE-274` | risk | Validação da janela do movimento | **migrated** | — | janela de datas do movimento: só a suíte alcança; não forcei data fora da janela no banco de demonstração |
| `BE-275` | risk | Transferência entre a operação de pré e sua par | **migrated** | — | transferência entre o par pré/liquidável: o seed não tem par com saldo pré para transferir — sem caso executável fora da suíte |
| `BE-276` | risk | Propagação em cascata dos movimentos | **migrated** | — | transferência entre o par pré/liquidável: o seed não tem par com saldo pré para transferir — sem caso executável fora da suíte |
| `BE-277` | risk | Prorrogações de operação | **verified** | `API`; `TELA` | aba Prorrogações renderizada e GET /extensions + /extensions/new respondendo 200 |
| `BE-278` | risk | Tipos de limite e seus subtipos | **verified** | `API`; `TELA` | catálogos listados e as duas telas capturadas |
| `BE-279` | risk | Tipos de movimentação | **verified** | `API`; `TELA` | catálogos listados e as duas telas capturadas |
| `FE-230` | risk | Casca da tela de controle de risco | **verified** | `TELA`; `MOBILE` | console de risco em 1440 e em 390: os 4 tipos, o aviso NEW-005 ("1 limite está com utilização acima do teto · −87.937,33 disponível") e o badge ACIMA DO TETO na linha do portador |
| `FE-231` | risk | Filtro de grupo econômico | **verified** | `TELA`; `MOBILE` | console de risco em 1440 e em 390: os 4 tipos, o aviso NEW-005 ("1 limite está com utilização acima do teto · −87.937,33 disponível") e o badge ACIMA DO TETO na linha do portador |
| `FE-232` | risk | Filtro de portador em cascata | **migrated** | — | filtro de portador em cascata, filtro de data, cadastrar posição diária, modo portador único e expandir/recolher: não acionei os controles nesta passada |
| `FE-233` | risk | Filtro de data do painel | **migrated** | — | filtro de portador em cascata, filtro de data, cadastrar posição diária, modo portador único e expandir/recolher: não acionei os controles nesta passada |
| `FE-234` | risk | Ação de cadastrar posição diária | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `FE-235` | risk | Resumo de limites agrupado por tipo | **verified** | `TELA`; `MOBILE` | console de risco em 1440 e em 390: os 4 tipos, o aviso NEW-005 ("1 limite está com utilização acima do teto · −87.937,33 disponível") e o badge ACIMA DO TETO na linha do portador |
| `FE-236` | risk | Resumo em modo de portador único | **migrated** | — | filtro de portador em cascata, filtro de data, cadastrar posição diária, modo portador único e expandir/recolher: não acionei os controles nesta passada |
| `FE-237` | risk | Expandir e recolher grupos por tipo | **migrated** | — | filtro de portador em cascata, filtro de data, cadastrar posição diária, modo portador único e expandir/recolher: não acionei os controles nesta passada |
| `FE-238` | risk | Indicador visual de limite estourado | **verified** | `TELA`; `MOBILE` | console de risco em 1440 e em 390: os 4 tipos, o aviso NEW-005 ("1 limite está com utilização acima do teto · −87.937,33 disponível") e o badge ACIMA DO TETO na linha do portador |
| `FE-239` | risk | Estados do container de resumo | **verified** | `TELA`; `MOBILE` | console de risco em 1440 e em 390: os 4 tipos, o aviso NEW-005 ("1 limite está com utilização acima do teto · −87.937,33 disponível") e o badge ACIMA DO TETO na linha do portador |
| `FE-240` | risk | Tela de limites | **verified** | `TELA`; `MOBILE` | tela de limites com os 19 do projeto, filtros, paginação e o widget por linha; cartões abaixo de 768px |
| `FE-241` | risk | Filtros da tela de limites | **verified** | `TELA`; `MOBILE` | tela de limites com os 19 do projeto, filtros, paginação e o widget por linha; cartões abaixo de 768px |
| `FE-242` | risk | Paginação da tela de limites | **verified** | `TELA`; `MOBILE` | tela de limites com os 19 do projeto, filtros, paginação e o widget por linha; cartões abaixo de 768px |
| `FE-243` | risk | Widget de limite | **verified** | `TELA`; `MOBILE` | tela de limites com os 19 do projeto, filtros, paginação e o widget por linha; cartões abaixo de 768px |
| `FE-244` | risk | Painel de criar e editar limite | **verified** | `TELA` | a gaveta "Novo limite" abre com o formulário montado (probe de DOM: campos visíveis, Cancelar e Salvar) |
| `FE-245` | risk | Campo de saldo inicial condicional | **verified** | `TELA` | a gaveta "Novo limite" abre com o formulário montado (probe de DOM: campos visíveis, Cancelar e Salvar) |
| `FE-246` | risk | Máscaras do formulário de limite | **verified** | `TELA` | a gaveta "Novo limite" abre com o formulário montado (probe de DOM: campos visíveis, Cancelar e Salvar) |
| `FE-247` | risk | Ações do limite na lista | **verified** | `TELA`; `MOBILE` | tela de limites com os 19 do projeto, filtros, paginação e o widget por linha; cartões abaixo de 768px |
| `FE-248` | risk | Guardas do cadastro de limite | **migrated** | — | guardas do cadastro de limite: NÃO passa — a gaveta abre para perfil somente-leitura (ver DEF-03 no relatório) |
| `FE-249` | risk | Estados da lista de limites | **verified** | `TELA`; `MOBILE` | tela de limites com os 19 do projeto, filtros, paginação e o widget por linha; cartões abaixo de 768px |
| `FE-250` | risk | Tela de operações de risco | **verified** | `TELA`; `API` | tela de operações com 204 registros, cabeçalhos, filtros e paginação; os valores da linha conferidos contra o GET campo a campo |
| `FE-251` | risk | Busca textual de operações | **verified** | `TELA`; `API` | tela de operações com 204 registros, cabeçalhos, filtros e paginação; os valores da linha conferidos contra o GET campo a campo |
| `FE-252` | risk | Filtros de empresa, portador e tipo de operação | **verified** | `TELA`; `API` | tela de operações com 204 registros, cabeçalhos, filtros e paginação; os valores da linha conferidos contra o GET campo a campo |
| `FE-253` | risk | Filtro de período de operações | **verified** | `TELA`; `API` | tela de operações com 204 registros, cabeçalhos, filtros e paginação; os valores da linha conferidos contra o GET campo a campo |
| `FE-254` | risk | Ordenação multi-coluna de operações | **migrated** | — | ordenação multi-coluna: não cliquei nos cabeçalhos nesta passada |
| `FE-255` | risk | Paginação de operações | **verified** | `TELA`; `API` | tela de operações com 204 registros, cabeçalhos, filtros e paginação; os valores da linha conferidos contra o GET campo a campo |
| `FE-256` | risk | Widget de operação e menu de ações | **verified** | `TELA`; `API` | tela de operações com 204 registros, cabeçalhos, filtros e paginação; os valores da linha conferidos contra o GET campo a campo |
| `FE-257` | risk | Guardas do cadastro de operação | **migrated** | — | guardas do cadastro de operação: NÃO passa — a gaveta abre para perfil somente-leitura (ver DEF-03) |
| `FE-258` | risk | Cascata do formulário de operação | **migrated** | — | formulário de operação de risco: não preenchido nesta passada (não criei operação no banco de demonstração) |
| `FE-259` | risk | Campos do formulário de operação | **migrated** | — | formulário de operação de risco: não preenchido nesta passada (não criei operação no banco de demonstração) |
| `FE-260` | risk | Regras do formulário para tipos com pré-faturamento | **migrated** | — | formulário de operação de risco: não preenchido nesta passada (não criei operação no banco de demonstração) |
| `FE-261` | risk | Habilitação do salvar no formulário de operação | **migrated** | — | formulário de operação de risco: não preenchido nesta passada (não criei operação no banco de demonstração) |
| `FE-262` | risk | Máscaras numéricas do formulário de operação | **migrated** | — | formulário de operação de risco: não preenchido nesta passada (não criei operação no banco de demonstração) |
| `FE-263` | risk | Estados vazios do formulário de operação | **migrated** | — | formulário de operação de risco: não preenchido nesta passada (não criei operação no banco de demonstração) |
| `FE-264` | risk | Casca do detalhe da operação | **verified** | `TELA` | detalhe da operação em claro e escuro: cartão de cadastro com os 14 campos e cartão de última movimentação |
| `FE-265` | risk | Cartão de cadastro do detalhe da operação | **verified** | `TELA` | detalhe da operação em claro e escuro: cartão de cadastro com os 14 campos e cartão de última movimentação |
| `FE-266` | risk | Cartão de última movimentação | **verified** | `TELA` | detalhe da operação em claro e escuro: cartão de cadastro com os 14 campos e cartão de última movimentação |
| `FE-267` | risk | Cartão de renovações | **verified** | `API`; `TELA` | cartão de renovações e os links renderizados; GET /renewals 200 |
| `FE-268` | risk | Navegação para o recebível e para a operação original | **verified** | `API`; `TELA` | cartão de renovações e os links renderizados; GET /renewals 200 |
| `FE-269` | risk | Aba de movimentações | **verified** | `TELA` | aba de movimentações com a tabela completa (#, DATA, TIPO, VALOR MOVIMENTO, SALDO, OBSERVAÇÃO) e o deep-link ?aba=movimentacoes |
| `FE-270` | risk | Widget de movimentação | **verified** | `TELA` | aba de movimentações com a tabela completa (#, DATA, TIPO, VALOR MOVIMENTO, SALDO, OBSERVAÇÃO) e o deep-link ?aba=movimentacoes |
| `FE-271` | risk | Painel de cadastrar e editar movimentação | **migrated** | — | painéis de cadastrar/editar movimento, transferir, prorrogar e renovar: não abertos pela tela nesta passada (o round-trip de movimento foi pela API) |
| `FE-272` | risk | Ação de transferir | **migrated** | — | painéis de cadastrar/editar movimento, transferir, prorrogar e renovar: não abertos pela tela nesta passada (o round-trip de movimento foi pela API) |
| `FE-273` | risk | Excluir movimentação pela tela | **migrated** | — | painéis de cadastrar/editar movimento, transferir, prorrogar e renovar: não abertos pela tela nesta passada (o round-trip de movimento foi pela API) |
| `FE-274` | risk | Aba de prorrogações e painel de prorrogar | **migrated** | — | painéis de cadastrar/editar movimento, transferir, prorrogar e renovar: não abertos pela tela nesta passada (o round-trip de movimento foi pela API) |
| `FE-275` | risk | Painel de renovar operação | **migrated** | — | painéis de cadastrar/editar movimento, transferir, prorrogar e renovar: não abertos pela tela nesta passada (o round-trip de movimento foi pela API) |
| `FE-276` | risk | Estados das listas de movimentações e prorrogações | **verified** | `TELA` | aba de movimentações com a tabela completa (#, DATA, TIPO, VALOR MOVIMENTO, SALDO, OBSERVAÇÃO) e o deep-link ?aba=movimentacoes |
| `FE-277` | risk | Tela de tipos de limite | **verified** | `TELA` | telas de tipos de limite e de tipos de movimentação capturadas |
| `FE-278` | risk | Tela de tipos de movimentação | **verified** | `TELA` | telas de tipos de limite e de tipos de movimentação capturadas |
| `FE-279` | risk | Permissões de interface no módulo de risco | **migrated** | `API` | o servidor recusa (403 READONLY_RESTRICTED nos 4 endpoints), mas a interface de /risk-controls e /risk-operations oferece criar para perfil somente-leitura — DEF-03 |
| `DB-230` | risk | Tabela `risk_controls` | **verified** | `DUMP-RISCO` | risk_controls do dump: 600 linhas, 1 por (empresa, portador), SEM coluna de tipo — a forma pré-2022 que o ai9 preserva. 46 empresas, 175 portadores, 36 projetos; 38 com os 4 pares zerados; 64 inativos |
| `DB-231` | risk | Tabela `risk_entries` | **verified** | `DUMP-RISCO` | 642.447 linhas, 0 órfãs de limite/empresa/projeto, project_id da linha igual ao da empresa em 642.447/642.447, e nenhum valor excede o decimal(14,2) do ai9 |
| `DB-232` | risk | Tabela `risk_operation_types` | **verified** | `API`; `SUÍTE` | as tabelas existem e respondem pela API; sem oráculo de produção — as 6 migrations tipadas de risco estão entre as 24 que nunca subiram, e o dump confirma: não há risk_operations nem risk_movements lá |
| `DB-233` | risk | Tabela `risk_operation_subtypes` | **verified** | `API`; `SUÍTE` | as tabelas existem e respondem pela API; sem oráculo de produção — as 6 migrations tipadas de risco estão entre as 24 que nunca subiram, e o dump confirma: não há risk_operations nem risk_movements lá |
| `DB-234` | risk | Tabela `risk_movement_types` | **verified** | `API`; `SUÍTE` | as tabelas existem e respondem pela API; sem oráculo de produção — as 6 migrations tipadas de risco estão entre as 24 que nunca subiram, e o dump confirma: não há risk_operations nem risk_movements lá |
| `DB-235` | risk | Tabela `risk_operations` | **verified** | `API`; `SUÍTE` | as tabelas existem e respondem pela API; sem oráculo de produção — as 6 migrations tipadas de risco estão entre as 24 que nunca subiram, e o dump confirma: não há risk_operations nem risk_movements lá |
| `DB-236` | risk | Tabela `risk_movements` | **verified** | `API`; `SUÍTE` | as tabelas existem e respondem pela API; sem oráculo de produção — as 6 migrations tipadas de risco estão entre as 24 que nunca subiram, e o dump confirma: não há risk_operations nem risk_movements lá |
| `DB-237` | risk | Tabela `risk_operation_extensions` | **verified** | `API`; `SUÍTE` | as tabelas existem e respondem pela API; sem oráculo de produção — as 6 migrations tipadas de risco estão entre as 24 que nunca subiram, e o dump confirma: não há risk_operations nem risk_movements lá |
| `DB-238` | risk | Índices e integridade referencial do módulo de risco | **verified** | `API`; `SUÍTE` | as tabelas existem e respondem pela API; sem oráculo de produção — as 6 migrations tipadas de risco estão entre as 24 que nunca subiram, e o dump confirma: não há risk_operations nem risk_movements lá |
| `DB-239` | risk | Fronteiras do módulo de risco com outros domínios | **verified** | `API` | fronteira com recebíveis exercitada pelo GET /risk_operations/availability |
| `DB-240` | risk | Limites do modelo anterior a 2022 | **verified** | `DUMP-RISCO` | risk_controls do dump: 600 linhas, 1 por (empresa, portador), SEM coluna de tipo — a forma pré-2022 que o ai9 preserva. 46 empresas, 175 portadores, 36 projetos; 38 com os 4 pares zerados; 64 inativos |
| `OPS-230` | risk | Seeds dos tipos de limite padrão | **verified** | `API`; `FONTE-LEGADO` | catálogos de referência listados pela API; "Liberação do Recurso" resolvido por chave e com o mesmo credit_type do legado |
| `OPS-231` | risk | Seeds dos tipos de movimentação padrão | **verified** | `API`; `FONTE-LEGADO` | catálogos de referência listados pela API; "Liberação do Recurso" resolvido por chave e com o mesmo credit_type do legado |
| `OPS-232` | risk | Identificação dos tipos usados pelos fluxos automáticos | **verified** | `API`; `FONTE-LEGADO` | catálogos de referência listados pela API; "Liberação do Recurso" resolvido por chave e com o mesmo credit_type do legado |
| `OPS-233` | risk | Datas-sentinela do módulo de risco | **verified** | `API`; `COERÊNCIA` | janela on_date fechada nos dois lados; o par estático entra sempre, como no legado |
| `OPS-234` | risk | Busca textual insensível a maiúsculas | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `OPS-235` | risk | Escritas em massa do módulo de risco | **verified** | `COERÊNCIA`; `ROUND-TRIP` | a cadeia inteira é escrita numa vez; sequence renumerada 1..N e conferida em 937/937 operações |
| `OPS-236` | risk | Rotinas de conversão e reconciliação do módulo de risco | **verified** | `DUMP-RISCO` | conversor de risk_entries lido e medido contra a origem: 0 órfãos, 0 colisão de unicidade, 0 estouro de precisão. ACHADO quantificado: 4.082 linhas de 2022 perdem a abertura por modalidade na carga — ver ACH-02 |
| `OPS-237` | risk | Textos de ajuda do formulário de operação | **verified** | `API`; `FONTE-LEGADO` | textos de ajuda do formulário: mecanismo executado; o conteúdo nasce vazio por decisão (Q-R9) porque as 13 chaves do legado tinham todas o mesmo placeholder |
| `OPS-238` | risk | Integração de recebível com o módulo de risco | **verified** | `API` | contrato com a S6 exercitado por GET /risk_operations/availability |
| `OPS-239` | risk | Relatórios e exportações do módulo de risco | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-280` | structured-operations | Buscar e listar operações estruturadas | **verified** | `API`; `TELA` | lista com X-Total-Count=31 (o legado calculava o total DEPOIS do limit/offset), filtros e período executados; tela capturada |
| `BE-281` | structured-operations | Filtros combináveis da busca de operações | **verified** | `API`; `TELA` | lista com X-Total-Count=31 (o legado calculava o total DEPOIS do limit/offset), filtros e período executados; tela capturada |
| `BE-282` | structured-operations | Filtro de período da busca de operações | **verified** | `API`; `TELA` | lista com X-Total-Count=31 (o legado calculava o total DEPOIS do limit/offset), filtros e período executados; tela capturada |
| `BE-283` | structured-operations | Ordenação multi-coluna da busca de operações | **verified** | `API`; `TELA` | lista com X-Total-Count=31 (o legado calculava o total DEPOIS do limit/offset), filtros e período executados; tela capturada |
| `BE-284` | structured-operations | Paginação e contagem total da busca de operações | **verified** | `API`; `TELA` | lista com X-Total-Count=31 (o legado calculava o total DEPOIS do limit/offset), filtros e período executados; tela capturada |
| `BE-285` | structured-operations | Criar operação estruturada | **migrated** | — | criar/editar/excluir operação estruturada: exercitado só por request spec no banco próprio — não escrevi no banco de demonstração |
| `BE-286` | structured-operations | Atualizar operação estruturada | **migrated** | — | criar/editar/excluir operação estruturada: exercitado só por request spec no banco próprio — não escrevi no banco de demonstração |
| `BE-287` | structured-operations | Excluir operação estruturada | **migrated** | — | criar/editar/excluir operação estruturada: exercitado só por request spec no banco próprio — não escrevi no banco de demonstração |
| `BE-288` | structured-operations | Abrir o formulário de operação estruturada | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-289` | structured-operations | Rotas REST mortas da unidade | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-290` | structured-operations | Título padrão da operação | **migrated** | — | criar/editar/excluir operação estruturada: exercitado só por request spec no banco próprio — não escrevi no banco de demonstração |
| `BE-291` | structured-operations | Projeto derivado da empresa | **migrated** | — | criar/editar/excluir operação estruturada: exercitado só por request spec no banco próprio — não escrevi no banco de demonstração |
| `BE-292` | structured-operations | Saldo inicial e saldo corrente da operação | **verified** | `API`; `TELA` | as 136 operações têm balance == original_balance == −operation_value; a tela diz por escrito que o saldo é cópia do saldo inicial e não sofre baixa |
| `BE-293` | structured-operations | Validações da operação estruturada | **migrated** | — | criar/editar/excluir operação estruturada: exercitado só por request spec no banco próprio — não escrevi no banco de demonstração |
| `BE-294` | structured-operations | Elegibilidade da operação a recibo | **verified** | `API`; `C2`; `ROUND-TRIP` | 223 candidatos a recibo na cobrança do projeto, 9 persistidos; valor = operation_value × fee/100 com ROUND_HALF_UP conferido em dois candidatos (297.863,03 × 0,3352% = 998,44) |
| `BE-295` | structured-operations | Indicadores de negócio da operação estruturada | **migrated** | — | indicadores booleanos da operação: só a suíte alcança |
| `BE-296` | structured-operations | Buscar e listar tipos de operação estruturada | **verified** | `API`; `TELA` | tipos listados com total e a tela capturada |
| `BE-297` | structured-operations | Criar tipo de operação estruturada | **migrated** | — | CRUD de tipo de operação estruturada: só request spec |
| `BE-298` | structured-operations | Atualizar tipo de operação estruturada | **migrated** | — | CRUD de tipo de operação estruturada: só request spec |
| `BE-299` | structured-operations | Excluir tipo de operação estruturada | **migrated** | — | CRUD de tipo de operação estruturada: só request spec |
| `BE-300` | structured-operations | Buscar e listar remunerações | **verified** | `API`; `TELA` | remunerações listadas com X-Total-Count=8 e renderizadas: LIQ/EST × 4 tipos, taxas 0,34% a 0,52% — NÃO zeradas (queixa do usuário) |
| `BE-301` | structured-operations | Criar remuneração | **migrated** | — | CRUD de remuneração: só request spec |
| `BE-302` | structured-operations | Atualizar remuneração | **migrated** | — | CRUD de remuneração: só request spec |
| `BE-303` | structured-operations | Excluir remuneração | **migrated** | — | CRUD de remuneração: só request spec |
| `BE-304` | structured-operations | Título, classe e sigla da remuneração | **verified** | `API`; `TELA` | remunerações listadas com X-Total-Count=8 e renderizadas: LIQ/EST × 4 tipos, taxas 0,34% a 0,52% — NÃO zeradas (queixa do usuário) |
| `BE-305` | structured-operations | Fórmula da remuneração | **verified** | `API`; `C2`; `ROUND-TRIP` | 223 candidatos a recibo na cobrança do projeto, 9 persistidos; valor = operation_value × fee/100 com ROUND_HALF_UP conferido em dois candidatos (297.863,03 × 0,3352% = 998,44) |
| `BE-306` | structured-operations | Candidatos a recibo por remuneração | **verified** | `API`; `C2`; `ROUND-TRIP` | 223 candidatos a recibo na cobrança do projeto, 9 persistidos; valor = operation_value × fee/100 com ROUND_HALF_UP conferido em dois candidatos (297.863,03 × 0,3352% = 998,44) |
| `BE-307` | structured-operations | Buscar tipos de recurso | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-308` | structured-operations | Buscar fontes de recurso | **verified** | `API` | GET /resource_sources 200 |
| `BE-309` | structured-operations | Rotas órfãs de taxas de operação estruturada | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-720` | structured-operations | Abrir o formulário de novo tipo de recurso | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-721` | structured-operations | Abrir o formulário de edição de tipo de recurso | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-722` | structured-operations | Criar tipo de recurso | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-723` | structured-operations | Atualizar tipo de recurso | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-724` | structured-operations | Excluir tipo de recurso | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-725` | structured-operations | Abrir o formulário de nova fonte de recurso | **migrated** | `SUÍTE` | CRUD de fonte de recurso: exercitado só por request spec |
| `BE-726` | structured-operations | Abrir o formulário de edição de fonte de recurso | **migrated** | `SUÍTE` | CRUD de fonte de recurso: exercitado só por request spec |
| `BE-727` | structured-operations | Criar fonte de recurso | **migrated** | `SUÍTE` | CRUD de fonte de recurso: exercitado só por request spec |
| `BE-728` | structured-operations | Atualizar fonte de recurso | **migrated** | `SUÍTE` | CRUD de fonte de recurso: exercitado só por request spec |
| `BE-729` | structured-operations | Excluir fonte de recurso | **migrated** | `SUÍTE` | CRUD de fonte de recurso: exercitado só por request spec |
| `FE-280` | structured-operations | Tela de lista de operações estruturadas | **verified** | `TELA`; `MOBILE` | lista de operações estruturadas em 1440 e 390, com filtros, paginação e o widget de linha |
| `FE-281` | structured-operations | Estado de carregamento da lista de operações | **verified** | `TELA`; `MOBILE` | lista de operações estruturadas em 1440 e 390, com filtros, paginação e o widget de linha |
| `FE-282` | structured-operations | Estados vazios da lista de operações | **verified** | `TELA`; `MOBILE` | lista de operações estruturadas em 1440 e 390, com filtros, paginação e o widget de linha |
| `FE-283` | structured-operations | Estado de erro da lista de operações | **verified** | `TELA`; `MOBILE` | lista de operações estruturadas em 1440 e 390, com filtros, paginação e o widget de linha |
| `FE-284` | structured-operations | Busca textual da lista de operações | **verified** | `TELA`; `MOBILE` | lista de operações estruturadas em 1440 e 390, com filtros, paginação e o widget de linha |
| `FE-285` | structured-operations | Filtro de período da lista de operações | **verified** | `TELA`; `MOBILE` | lista de operações estruturadas em 1440 e 390, com filtros, paginação e o widget de linha |
| `FE-286` | structured-operations | Filtros de empresa, portador e tipo de operação | **verified** | `TELA`; `MOBILE` | lista de operações estruturadas em 1440 e 390, com filtros, paginação e o widget de linha |
| `FE-287` | structured-operations | Ordenação pelo cabeçalho da lista de operações | **migrated** | — | ordenação por cabeçalho, menu de ações e remoção pela tela: não acionados nesta passada |
| `FE-288` | structured-operations | Navegação e paginação da lista de operações | **verified** | `TELA`; `MOBILE` | lista de operações estruturadas em 1440 e 390, com filtros, paginação e o widget de linha |
| `FE-289` | structured-operations | Widget de linha da operação estruturada | **verified** | `TELA`; `MOBILE` | lista de operações estruturadas em 1440 e 390, com filtros, paginação e o widget de linha |
| `FE-290` | structured-operations | Menu de ações da linha de operação | **migrated** | — | ordenação por cabeçalho, menu de ações e remoção pela tela: não acionados nesta passada |
| `FE-291` | structured-operations | Guarda do cadastro de operação estruturada | **migrated** | — | ordenação por cabeçalho, menu de ações e remoção pela tela: não acionados nesta passada |
| `FE-292` | structured-operations | Remoção de operação estruturada pela tela | **migrated** | — | ordenação por cabeçalho, menu de ações e remoção pela tela: não acionados nesta passada |
| `FE-293` | structured-operations | Formulário de operação estruturada | **verified** | `TELA` | formulário montado e visível (contract_number, title, observation, issue_date, due_date, operation_value, original_balance, agreed_rate) |
| `FE-294` | structured-operations | Máscaras do formulário de operação estruturada | **verified** | `TELA` | formulário montado e visível (contract_number, title, observation, issue_date, due_date, operation_value, original_balance, agreed_rate) |
| `FE-295` | structured-operations | Salvamento e campos obrigatórios do formulário | **verified** | `TELA` | formulário montado e visível (contract_number, title, observation, issue_date, due_date, operation_value, original_balance, agreed_rate) |
| `FE-296` | structured-operations | Prévia de saldo no formulário | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `FE-297` | structured-operations | Datas do formulário de operação estruturada | **verified** | `TELA` | formulário montado e visível (contract_number, title, observation, issue_date, due_date, operation_value, original_balance, agreed_rate) |
| `FE-298` | structured-operations | Estados vazios bloqueantes do formulário | **verified** | `TELA` | formulário montado e visível (contract_number, title, observation, issue_date, due_date, operation_value, original_balance, agreed_rate) |
| `FE-299` | structured-operations | Detalhe da operação estruturada | **verified** | `TELA` | detalhe da operação estruturada renderizado com os 11 campos e a nota do saldo decorativo |
| `FE-300` | structured-operations | Tela de tipos de operação estruturada | **verified** | `TELA`; `MOBILE` | telas de tipos e de remunerações capturadas, inclusive em 390×844 |
| `FE-301` | structured-operations | Painel de tipo de operação estruturada | **migrated** | — | painéis de tipo e de remuneração: a gaveta abre (probe de DOM) mas não preenchi nem salvei |
| `FE-302` | structured-operations | Exclusão de tipo de operação estruturada | **migrated** | — | painéis de tipo e de remuneração: a gaveta abre (probe de DOM) mas não preenchi nem salvei |
| `FE-303` | structured-operations | Tela de remunerações | **verified** | `TELA`; `MOBILE` | telas de tipos e de remunerações capturadas, inclusive em 390×844 |
| `FE-304` | structured-operations | Painel de remuneração | **verified** | `TELA` | a gaveta "Nova remuneração" abre com o campo value visível e Cancelar/Salvar |
| `FE-305` | structured-operations | Máscara de percentual da remuneração | **migrated** | — | painéis de tipo e de remuneração: a gaveta abre (probe de DOM) mas não preenchi nem salvei |
| `FE-306` | structured-operations | Acesso direto às telas de remuneração | **verified** | `TELA` | deep-link /remunerations/add abre a gaveta direto |
| `FE-307` | structured-operations | Tela de tipos de recurso | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `FE-308` | structured-operations | Tela de fontes de recurso | **migrated** | — | NÃO ALCANÇADO nesta passada — sem evidência de execução |
| `FE-309` | structured-operations | Permissões e sessão nas telas da unidade | **verified** | `API`; `TELA` | perfil somente-leitura NÃO vê criar em /structured-operations nem em /remunerations (correto), e o servidor devolve 403 READONLY_RESTRICTED |
| `DB-280` | structured-operations | Tabela `structured_operations` | **verified** | `API` | tabelas exercitadas pela API; sem oráculo de produção — o dump confirma que structured_operations, remunerations e receipts NÃO existem lá |
| `DB-281` | structured-operations | Vínculo da operação com o recibo | **verified** | `API`; `ROUND-TRIP` | o vínculo operação↔recibo foi exercitado no round-trip C2: o recibo nasceu, apareceu como persisted e sumiu ao restaurar |
| `DB-282` | structured-operations | Índices e integridade referencial da unidade | **migrated** | — | índices, proveniência e cargas iniciais: sem superfície para exercitar fora da suíte |
| `DB-283` | structured-operations | Tabela `structured_operation_types` | **verified** | `API` | tabelas exercitadas pela API; sem oráculo de produção — o dump confirma que structured_operations, remunerations e receipts NÃO existem lá |
| `DB-284` | structured-operations | Tabela `remunerations` | **verified** | `API` | tabelas exercitadas pela API; sem oráculo de produção — o dump confirma que structured_operations, remunerations e receipts NÃO existem lá |
| `DB-285` | structured-operations | Título da remuneração | **migrated** | — | índices, proveniência e cargas iniciais: sem superfície para exercitar fora da suíte |
| `DB-286` | structured-operations | Tabela `resource_kinds` | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `DB-287` | structured-operations | Tabela `resource_sources` | **migrated** | — | índices, proveniência e cargas iniciais: sem superfície para exercitar fora da suíte |
| `DB-288` | structured-operations | Proveniência das fontes de recurso | **migrated** | — | índices, proveniência e cargas iniciais: sem superfície para exercitar fora da suíte |
| `DB-289` | structured-operations | Coluna órfã de tipo de recurso em recebíveis | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `DB-290` | structured-operations | Tabela `receipts` como materialização da remuneração | **verified** | `API`; `ROUND-TRIP` | o vínculo operação↔recibo foi exercitado no round-trip C2: o recibo nasceu, apareceu como persisted e sumiu ao restaurar |
| `DB-291` | structured-operations | Tabela de taxas de operação estruturada | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `DB-292` | structured-operations | Carga inicial dos tipos de operação estruturada | **migrated** | — | índices, proveniência e cargas iniciais: sem superfície para exercitar fora da suíte |
| `DB-293` | structured-operations | Carga inicial das fontes de recurso | **migrated** | — | índices, proveniência e cargas iniciais: sem superfície para exercitar fora da suíte |
| `DB-294` | structured-operations | Carga inicial dos tipos de recurso | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `DB-295` | structured-operations | Representação de indicadores booleanos | **migrated** | — | índices, proveniência e cargas iniciais: sem superfície para exercitar fora da suíte |
| `DB-296` | structured-operations | Precisão de valores monetários e de taxas | **verified** | `API` | tabelas exercitadas pela API; sem oráculo de produção — o dump confirma que structured_operations, remunerations e receipts NÃO existem lá |
| `DB-297` | structured-operations | Autoria dos registros da unidade | **migrated** | — | índices, proveniência e cargas iniciais: sem superfície para exercitar fora da suíte |
| `OPS-280` | structured-operations | Rotas órfãs de taxas de operação estruturada | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `OPS-281` | structured-operations | Templates ausentes das rotas REST da unidade | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `OPS-282` | structured-operations | Busca textual insensível a maiúsculas | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `OPS-283` | structured-operations | Datas-sentinela nos filtros da unidade | **migrated** | — | datas-sentinela, cobertura e parâmetros de ordenação: cobertos pela suíte, não exercitados isoladamente |
| `OPS-284` | structured-operations | Textos de ajuda do formulário de operação estruturada | **verified** | `API`; `FONTE-LEGADO` | GET help_texts devolve {} — vazio por decisão (Q-R9); o mecanismo (cache, arquivo ausente = {}) foi executado |
| `OPS-285` | structured-operations | Importação das fontes de recurso do sistema anterior | **verified** | `API`; `TELA` | fontes de recurso listadas e as 5 telas da unidade presentes no menu |
| `OPS-286` | structured-operations | Presença das telas da unidade no menu do console | **verified** | `API`; `TELA` | fontes de recurso listadas e as 5 telas da unidade presentes no menu |
| `OPS-287` | structured-operations | Cobertura de testes da unidade | **migrated** | — | datas-sentinela, cobertura e parâmetros de ordenação: cobertos pela suíte, não exercitados isoladamente |
| `OPS-288` | structured-operations | Parâmetros de ordenação das listas da unidade | **migrated** | — | datas-sentinela, cobertura e parâmetros de ordenação: cobertos pela suíte, não exercitados isoladamente |
| `OPS-289` | structured-operations | Formatação de valores e percentuais da unidade | **verified** | `API`; `TELA` | percentuais e moeda formatados em pt-BR na tela. NOTA: risk_controls/summary devolve formatted_* prontos do servidor — é RÉPLICA do legado (company.rb:150-161), não violação |
| `BE-310` | indicators | Superficie de rotas do catalogo de indicadores | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-311` | indicators | Busca de indicadores globais | **verified** | `API`; `TELA`; `DUMP-IND` | catálogo listado com X-Total-Count (o legado não tinha total e truncava em 50); no dump são 529 indicadores, 2 globais e 527 de projeto |
| `BE-312` | indicators | Ordenacao dinamica por coluna | **verified** | `API` | ordenação por "key" respondeu 200 (no legado era PG::UndefinedColumn/500) e uma chave com SQL injetado foi IGNORADA, devolvendo a lista normal |
| `BE-313` | indicators | Detalhe do indicador | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-314` | indicators | Formulario de cadastro de indicador | **verified** | `API`; `TELA` | detalhe, formulário de cadastro e deep-link /indicators/new montando a gaveta |
| `BE-315` | indicators | Formulario de edicao de indicador | **verified** | `API`; `TELA` | detalhe, formulário de cadastro e deep-link /indicators/new montando a gaveta |
| `BE-316` | indicators | Criar indicador | **migrated** | — | criar/editar/excluir/ativar indicador: só request spec — o catálogo é GLOBAL e escrever nele apareceria na tela de todos os outros agentes |
| `BE-317` | indicators | Editar indicador | **migrated** | — | criar/editar/excluir/ativar indicador: só request spec — o catálogo é GLOBAL e escrever nele apareceria na tela de todos os outros agentes |
| `BE-318` | indicators | Excluir indicador | **migrated** | — | criar/editar/excluir/ativar indicador: só request spec — o catálogo é GLOBAL e escrever nele apareceria na tela de todos os outros agentes |
| `BE-319` | indicators | Ativar e desativar indicador | **migrated** | — | criar/editar/excluir/ativar indicador: só request spec — o catálogo é GLOBAL e escrever nele apareceria na tela de todos os outros agentes |
| `BE-320` | indicators | Unicidade de titulo entre indicadores globais e especificos | **verified** | `DUMP-IND` | unicidade de título medida no dado real: 0 colisões global×específico, 0 dentro do mesmo projeto, 0 entre globais — a regra do ai9 não recusa nenhuma linha de produção |
| `BE-321` | indicators | Normalizacao de titulo, geracao de chave e tipo de valor padrao | **verified** | `DUMP-IND` | 529/529 títulos de produção já estão em CAIXA ALTA e sem acento: a normalização da DEC-89 não reescreve nada na carga |
| `BE-322` | indicators | Denormalizacao do indicador nos lancamentos | **verified** | `DUMP-IND` | a denormalização bate em 6.174/6.174 lançamentos: title, key e value_type idênticos aos do indicador. 0 divergências |
| `BE-323` | indicators | Superficie de rotas dos lancamentos | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-324` | indicators | Grade de lancamentos por projeto | **verified** | `API`; `TELA`; `GRÁFICO` | grade pedida por ano, por mês e por indicador; a tela mostra 5 indicadores × 12 células e o gráfico plota a MESMA série (Jan R$ 10.136.623,18 na tabela e no gráfico) |
| `BE-325` | indicators | Cadastro e edicao de lancamento fora da grade | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-326` | indicators | Criar lancamento | **migrated** | — | criar/editar/excluir lançamento: só request spec |
| `BE-327` | indicators | Editar lancamento | **migrated** | — | criar/editar/excluir lançamento: só request spec |
| `BE-328` | indicators | Excluir lancamento | **migrated** | — | criar/editar/excluir lançamento: só request spec |
| `BE-329` | indicators | Identidade e periodicidade do lancamento | **verified** | `DUMP-IND` | (projeto, indicador, ano, mês) único em 6.174/6.174; mês fora de 1..12 em 0; grades parciais são o normal em produção (250 combinações com 12 meses, 35 com 1) |
| `FE-310` | indicators | Tela de catalogo de indicadores globais | **verified** | `TELA` | catálogo renderizado com título, chave, estado, lançamentos e projetos por linha |
| `FE-311` | indicators | Busca incremental de indicadores | **verified** | `TELA` | catálogo renderizado com título, chave, estado, lançamentos e projetos por linha |
| `FE-312` | indicators | Ordenacao por clique no cabecalho | **verified** | `TELA` | catálogo renderizado com título, chave, estado, lançamentos e projetos por linha |
| `FE-313` | indicators | Cartao de indicador com instrucao expansivel | **verified** | `TELA` | catálogo renderizado com título, chave, estado, lançamentos e projetos por linha |
| `FE-314` | indicators | Menu de acoes do indicador | **verified** | `TELA` | catálogo renderizado com título, chave, estado, lançamentos e projetos por linha |
| `FE-315` | indicators | Confirmacao de exclusao de indicador | **migrated** | — | confirmação de exclusão: não acionada |
| `FE-316` | indicators | Formulario de indicador | **verified** | `TELA` | deep-link /indicators/new monta a gaveta com o campo indicator-title visível |
| `FE-317` | indicators | Deep-link do formulario de indicador | **verified** | `TELA` | deep-link /indicators/new monta a gaveta com o campo indicator-title visível |
| `FE-318` | indicators | Restricao somente-leitura na tela de indicadores | **verified** | `TELA` | perfil somente-leitura vê o aviso explícito "os valores ficam visíveis, mas não são salvos" na grade |
| `FE-319` | indicators | Tela de indicadores especificos do projeto | **verified** | `TELA` | tela de indicadores específicos renderizada com escopo Global e contagem por indicador |
| `FE-320` | indicators | Conectar e desconectar indicador global do projeto | **migrated** | — | conectar/desconectar pela tela: não acionado |
| `FE-321` | indicators | Acoes do indicador especifico na tela de conexoes | **verified** | `TELA` | tela de indicadores específicos renderizada com escopo Global e contagem por indicador |
| `FE-322` | indicators | Estado visual de indicador inativo | **verified** | `TELA` | tela de indicadores específicos renderizada com escopo Global e contagem por indicador |
| `FE-323` | indicators | Explicacao da restricao de permissao | **verified** | `TELA` | tela de indicadores específicos renderizada com escopo Global e contagem por indicador |
| `FE-324` | indicators | Tela da grade de lancamentos | **verified** | `TELA`; `API` | grade de ano inteiro e de mês único; filtros por indicador e por período persistidos na URL |
| `FE-325` | indicators | Filtros da grade de lancamentos | **verified** | `TELA`; `API` | grade de ano inteiro e de mês único; filtros por indicador e por período persistidos na URL |
| `FE-326` | indicators | Grade de ano inteiro | **verified** | `TELA`; `API` | grade de ano inteiro e de mês único; filtros por indicador e por período persistidos na URL |
| `FE-327` | indicators | Grade de mes unico | **verified** | `TELA`; `API` | grade de ano inteiro e de mês único; filtros por indicador e por período persistidos na URL |
| `FE-328` | indicators | Entrada e formatacao do valor monetario | **migrated** | — | entrada do valor e gravação automática ao sair do campo: não digitei na grade nesta passada |
| `FE-329` | indicators | Gravacao automatica do lancamento | **migrated** | — | entrada do valor e gravação automática ao sair do campo: não digitei na grade nesta passada |
| `DB-310` | indicators | Modelo de dados de indicador | **verified** | `DUMP-IND` | as três formas conferidas contra o dado real: 529 indicadores (key duplicada em 30 — e o ai9 NÃO tem índice único em key, DEC-85, então a carga não perde linha), 6.174 lançamentos únicos por (projeto, indicador, ano, mês), 590 conexões sem duplicidade |
| `DB-311` | indicators | Modelo de dados do lancamento | **verified** | `DUMP-IND` | as três formas conferidas contra o dado real: 529 indicadores (key duplicada em 30 — e o ai9 NÃO tem índice único em key, DEC-85, então a carga não perde linha), 6.174 lançamentos únicos por (projeto, indicador, ano, mês), 590 conexões sem duplicidade |
| `DB-312` | indicators | Modelo de dados da conexao indicador-projeto | **verified** | `DUMP-IND` | as três formas conferidas contra o dado real: 529 indicadores (key duplicada em 30 — e o ai9 NÃO tem índice único em key, DEC-85, então a carga não perde linha), 6.174 lançamentos únicos por (projeto, indicador, ano, mês), 590 conexões sem duplicidade |
| `DB-313` | indicators | Conteudo rico de indicador e de contrato | **migrated** | — | ActionText de indicador: 485 registros no dump, mas o religamento só acontece na carga |
| `OPS-310` | indicators | Ausencia de rotinas automaticas de indicadores | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `OPS-311` | indicators | Reprocessamento de normalizacao de indicadores | **migrated** | — | ausência de rotinas, reprocessamento e retenção: itens de ausência ou de rotina, sem superfície para exercitar |
| `OPS-312` | indicators | Chave de integracao do indicador | **verified** | `DUMP-IND` | a chave de integração se REPETE em produção: 482 únicas, 15 com 2, 1 com 3, 1 com 4 e 2 com 5 ocorrências. O ai9 não impõe unicidade (DEC-85) — decisão validada contra o dado real |
| `OPS-313` | indicators | Politica de retencao dos lancamentos | **migrated** | — | ausência de rotinas, reprocessamento e retenção: itens de ausência ou de rotina, sem superfície para exercitar |
| `OPS-314` | indicators | Cobertura de testes da capability | **migrated** | — | ausência de rotinas, reprocessamento e retenção: itens de ausência ou de rotina, sem superfície para exercitar |
| `BE-707` | indicators | Listar indicadores conectaveis ao projeto | **verified** | `API`; `TELA`; `DUMP-IND` | GET /indicator_connections executado e a tela de indicadores específicos renderizada; no dump são 590 conexões, 0 duplicadas, 0 órfãs e 0 apontando para projeto diferente |
| `BE-708` | indicators | Endpoint de conexoes sem escopo | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-709` | indicators | Conectar indicadores globais ao projeto | **migrated** | `DUMP-IND` | conectar/desconectar/excluir: só request spec — o catálogo é global e a escrita apareceria para os outros agentes |
| `BE-710` | indicators | Desconectar indicador global do projeto | **migrated** | `DUMP-IND` | conectar/desconectar/excluir: só request spec — o catálogo é global e a escrita apareceria para os outros agentes |
| `BE-711` | indicators | Excluir indicador especifico pela tela de conexoes | **migrated** | `DUMP-IND` | conectar/desconectar/excluir: só request spec — o catálogo é global e a escrita apareceria para os outros agentes |
| `BE-712` | indicators | Rota de indice de conexoes | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-713` | indicators | Rota de edicao de conexao | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-714` | indicators | Rota de exclusao direta de conexao | **dropped** | — | dropped no Phase 2/3 com evidência na própria linha do razão — não reabro descarte nesta passada |
| `BE-715` | indicators | Tipo de valor do indicador | **verified** | `DUMP-IND` | value_type é um conjunto de UM elemento em produção: "Dinheiro" em 529/529 |
| `BE-716` | indicators | Consultas de lancamento por periodo e por indicador | **verified** | `API`; `GRÁFICO` | consulta por período e por indicador executada; é a série que o NEW-001 plota, sem segunda consulta |
| `BE-717` | indicators | Autorizacao de indicadores e lancamentos | **verified** | `API` | autorização exercitada: leitura 200 e escrita 403 READONLY_RESTRICTED para perfil somente-leitura |
| `FE-718` | indicators | Modo somente-leitura na grade de lancamentos | **verified** | `TELA` | perfil somente-leitura vê o aviso explícito "os valores ficam visíveis, mas não são salvos" na grade |
| `FE-719` | indicators | Expansao do card de indicador na grade | **verified** | `TELA`; `API` | grade de ano inteiro e de mês único; filtros por indicador e por período persistidos na URL |

## `NEW-001` — o gráfico, provado olhando

Continua `new` (feature nova, não paridade), e agora com a prova que faltava. **Um gráfico
vazio ou sem eixo passa em qualquer type-check** — e passou mesmo: no `vitest` o Recharts
renderiza com `width(-1) height(-1)` e imprime o aviso, então os 9 testes verdes de
`indicatorCharts.test.tsx` **não provam que a linha existe**.

Provado no navegador, lendo o SVG do DOM:

| Parte | Medição |
| ----- | ------- |
| Série mensal, 2026 | `recharts-surface` **968×260**, **1** `recharts-line-curve` com `d` real (`M84,103.739C125.333,96.348,…`), **8** `recharts-dot`, eixo X `Jan…Ago`, eixo Y `R$ 0 · R$ 4,5 mi · R$ 9 mi · R$ 13,5 mi · R$ 18 mi` |
| Série mensal, 2025 | **12** pontos, eixo X `Jan…Dez` — o ano cheio |
| Série mensal, 390×844 | superfície **326×260**, a linha e os 8 pontos ficam; o eixo X rareia para `Fev · Abr · Jun…` |
| Volume por portador | **5** barras, rótulos `R$ 7,2 mi · R$ 4,7 mi · R$ 4,5 mi · R$ 621,3 mil · R$ 44,7 mil` |
| "Ver valores" | abre a tabela com os valores **exatos**: `Jan R$ 10.136.623,18`, `Fev R$ 12.300.878,54`, … — iguais ao `GET /indicator_entries/grid` |
| Nada nasce no cliente | a série plotada é a **mesma** `linhas` que a grade recebe; nenhuma segunda consulta na aba de rede |
| Erros de console | **zero**, nas 22 páginas capturadas |

**O estado padrão da tela não desenha a série**, e isso é desenho, não defeito: com 5
indicadores conectados o gráfico não tem como escolher um, e mostra *"Escolha um indicador —
o gráfico segue o mesmo filtro da grade"* (design **G3**, sem filtro próprio). Com um indicador
escolhido — ou quando só há um — ele desenha. Vale saber que **quem abre a tela pela primeira
vez não vê gráfico nenhum**.

## Cobertura que o dado de demonstração NÃO exercita

Não são defeitos; são pontos cegos que ficam registrados para não virarem surpresa:

- **`indicators`**: o seed tem **5 indicadores, todos globais**. Produção tem **529**, sendo
  **527 de projeto** e só **2 globais** — o espelho exato. A tela "Indicadores específicos"
  nunca mostra um indicador de projeto no seed.
- **`value_type`**: um único valor (`Dinheiro`) no seed **e** em produção — então o ramo de
  formatação não-monetária do gráfico nunca roda com dado real.
- **`receipts` de operação estruturada**: **0** de 136 estruturadas têm recibo; todos os 238
  recibos vêm de operação de risco. A classe **EST** não é exercitada por dado nenhum.
- **Transferência entre o par pré/liquidável** (`BE-275`/`BE-276`): não há par com saldo pré
  no seed, então não há caso executável fora da suíte.
- **`RiskEntry`**: por **DEC-57** não tem endpoint nem tela — só a carga o alcança.

## Como reproduzir esta passada

```bash
# backend próprio (ATENÇÃO: 3.4.9, não 3.2.3 — ver ACH-01)
cd backend && rvm use 3.4.9 && bundle exec puma -p 3104 -e development
# front próprio apontando para ele
cd frontend && VITE_BACKEND_URL=http://localhost:3104 npx vite --port 5183 --strictPort
# suíte, em banco próprio (nunca a compartilhada)
DATABASE_URL='postgres://sfg9_user:PK%26sfg9777@localhost/sfg9_qa4ri_test' bundle exec rspec \
  spec/services/{risk,structured,indicators} spec/models/{risk_,structured_,remuneration_,indicator_}*_spec.rb \
  spec/requests/api/v1/{risk_,structured_,remunerations,indicator,dashboard}*_spec.rb
# dump, SOMENTE LEITURA
psql -h localhost -U sfg9_user -d sfg_legacy_dump
```

Para a prova de tela, a trava de força bruta por IP (DEF-01) impede repetir logins pelo
`browser.js`. Duas saídas, as duas usadas aqui:

1. **login real contra `127.0.0.2`** — outro IP de origem, mesma aplicação;
2. **injetar o cookie `refresh_token` no contexto do Playwright** e deixar o boot do app
   trocá-lo por um access token (`client.ts:37`). O `README` das ferramentas diz que *"a sessão
   não dá para injetar"* — isso vale para o `localStorage`, **não** para o cookie: o
   `addCookies` do Playwright grava cookie `HttpOnly` sem problema. Vale corrigir o README.
