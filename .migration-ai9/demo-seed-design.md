# Seed de demonstracao — Safegold no ai9

> **Objetivo:** a apresentacao de sexta (28/08/2026) tem de parecer **um sistema de
> credito em producao ha anos**, nao um ambiente de teste. Dado fake, sistema completo
> (DEC-16 / DEC-17.1).
>
> **Status:** desenho. Nada implementado — vira codigo no Phase 3.

---

## 1. Que sistema e este (a leitura do dominio que sustenta o seed)

Um seed so parece real se quem o escreveu entendeu o negocio. Lendo as tabelas do legado,
o Safegold e uma ferramenta de **gestao de credito estruturado e risco sacado**, usada por
uma consultoria/gestora que acompanha, para cada cliente, o que ele opera junto a bancos,
factorings e FIDCs.

| Entidade | O que e, no vocabulario do mercado |
| -------- | ---------------------------------- |
| `Project` | **O cliente** da gestora. Tem razao social (`formal`), segmento, endereco, responsavel e data de fechamento |
| `Company` | As **empresas do grupo** do cliente (`project_id` + `title`) — o limite e por empresa, nao por grupo |
| `Carrier` | A **contraparte financiadora**: banco, factoring ou FIDC. Tem `bank_code`, `bank_name`, `net_worth`, `senior_accounts`, `subordinated_accounts`, `subordinated_accounts_percent` — a estrutura de cotas de um FIDC |
| `RiskControl` | O **limite e a taxa** negociados, por `company` x `carrier`, em 4 modalidades: auto-liquidaveis, fomento, comissaria e intercompany |
| `ReceivableEntry` | O **borderô** de desconto: `nro_bordero`, `qtd_titulos`, `valor_bruto`, quanto foi **recusado**, prazo medio ponderado da empresa e do banco, float calculado x acordado, IOF e tarifas |
| `RiskOperation` | A **operacao de credito** viva: contrato, valor, saldo devedor, taxa acordada, vencimento, se esta em variavel, se encerrou |
| `RiskMovement` | O **movimento** da operacao: juros, ad valorem, IOF, liberacao, liquidacao, mora, transferencias |
| `StructuredOperation` | Operacao **estruturada**, mesmas 4 modalidades |
| `Renegotiation` | Renegociacao de divida com **fornecedor**: valor original, correcao, carencia, parcelas pagas/vencidas, anexos |
| `ProjectGuarantee` | **Garantias** dadas ao carrier |
| `IndicatorEntry` | Indicador financeiro **mensal** por projeto (`month`/`year`/`value`) |

**Consequencia para o seed:** o eixo da historia e `Project -> Company -> (Carrier, limite,
taxa) -> borderôs e operacoes -> movimentos -> saldo`. Se essa cadeia fecha aritmeticamente,
o sistema parece real. Se nao fecha, nenhum nome bonito salva.

---

## 2. O anti-exemplo: o seed que o legado ja tem

`..\sfg\db\seeds.rb:243-268` — marcado no proprio codigo como
`#TODO: seed feito somente para video de aprovacao`:

```ruby
Company.create(title: "Company teste #{project.formal} #{index}", ...)
RiskControl.create(limite_auto_liquidaveis: rand(0..100000000),
                   taxa_auto_liquidaveis:   rand(0.00..100.00).round(2), ...)
```

Tres defeitos que **nao** podemos repetir, e que resumem o briefing:

1. **`"Company teste 0"`** — entrega que e teste na primeira tela.
2. **`rand(0..100_000_000)`** — limite uniforme entre R$ 0 e R$ 100 milhoes. Aparece
   empresa de fundo de quintal com limite de R$ 97 mi e grupo grande com R$ 12 mil.
3. **`rand(0.00..100.00)`** — taxa de **87% ao mes**. Qualquer pessoa do mercado de
   credito ve isso em dois segundos, e a partir dai ela nao confia em mais nada da tela.

**A regra que sai daqui: numero errado destroi mais credibilidade do que nome feio.**

---

## 3. Os sete principios de credibilidade

1. **Aritmetica fecha.** Saldo = valor original − liquidacoes + juros + encargos. Total do
   borderô = bruto − recusado. `paid_installments + overdue_installments <= installments_count`.
   Se a tela soma e o rodape nao bate, acabou.
2. **Nada de numero redondo.** `R$ 1.000.000,00` grita seed. `R$ 1.043.287,55` nao.
3. **Faixas de mercado, nao uniformes.** Taxa de fomento entre 1,8% e 3,2% a.m.; ad valorem
   0,3%–0,5%; IOF de credito PJ com a regra real (0,0082%/dia + 0,38% adicional). Nunca
   `rand(0..100)`.
4. **Distribuicao com cauda.** Poucos clientes grandes, muitos medios, alguns pequenos —
   nao 12 clientes do mesmo tamanho. Idem para volume de borderô.
5. **Historia no tempo.** Dado de **24 meses**, com sazonalidade (dezembro e janeiro caem),
   crescimento, e uma inflexao — nao tudo criado hoje.
6. **Estados misturados.** Operacoes vivas, encerradas, vencidas e renegociadas convivendo.
   Parcelas em dia, pagas e em atraso. Borderô com recusa parcial.
7. **Volume que justifica a interface.** Paginacao, busca e filtro tem de fazer sentido —
   uma lista de 6 linhas com paginador vazio parece protótipo.

---

## 4. Catalogos: copiar **literalmente** do legado

Os catalogos do `..\sfg\db\seeds.rb:161-222,316-338` **nao sao dado de cliente** — sao o
vocabulario do dominio. Copiar tal e qual e o maior ganho de credibilidade por esforco:

- **Carteiras (10):** ACC · ACE · Antecipacao · Caucao · Cheque · Comissaria · Conta
  Garantida · Desconto · Domicilio · Fomento
- **Tipos de recebivel (5):** Cheque · Duplicata · Cartao de credito · ACC · PAC
- **Fonte de recurso (7):** Caixa · Comissaria · Defasagem · Fomento · Garantia · Recompra
  · Retencao
- **Tipos de recurso (5):** Antecipacao de Recebiveis · Comissaria · Desconto de Titulos ·
  Fomento · Intercompany
- **Tipos de movimentacao (16):** AdValorem · Assinatura Digital · Consulta SERASA · Custas
  de Protesto · Desagio · Despesas com Prorrogacao · Despesas de Correio · Entrada de
  Titulos · IOF · Liberacao de Recursos · Liquidacao · Multas sobre Liquidacao em Cartorio
  · Outras Despesas · Outras despesas Bancarias · Outras despesas da Operacao · TAC · TED
- **Tipos de operacao de risco / estruturada (4):** Fomento · Comissaria · Intercompany ·
  Auto Liquidavel — com as flags reais (`has_pre_faturamento`, `allow_manual_operations`,
  `allow_receivable_entries`)
- **Movimentos de risco (8):** Juros (D) · AdValorem (D) · IOF (D) · Liberacao do Recurso
  (D, exclusivo do sistema) · Liquidacao (C) · Juros de Mora (D) · Transferencia Recebida
  (D) · Valor Transferido (C)
- **Segmentos (3):** Comercio · Industria · Servicos — **ampliar** com subsegmentos, que o
  legado deixou vazio

---

## 5. O elenco ficticio

### 5.1 Contrapartes (`Carrier`) — **ficticias, e por um motivo**

O seed do legado usa **CREFISA**, que e instituicao real. Numa demo comercial, carrier com
nome de banco real sugere relacao comercial que nao existe. Proposta: nomes plausiveis e
**codigos bancarios nao atribuidos** (nunca 001/237/341, que sao BB/Bradesco/Itau):

| Carrier | Codigo | PL | Subordinada | Perfil |
| ------- | ------ | -- | ----------- | ------ |
| Banco Meridiano S.A. | 894 | R$ 312,4 mi | 18,5% | Banco medio, taxa baixa, limite alto, exigente |
| FIDC Aurora Credito | 907 | R$ 148,7 mi | 22,0% | FIDC multicedente, taxa media |
| Vertice Fomento Mercantil | 912 | R$ 41,2 mi | — | Factoring, taxa alta, prazo curto |
| FIDC Solaris Recebiveis | 923 | R$ 96,8 mi | 25,0% | FIDC, foco em duplicata |
| Cooperativa de Credito Ipiranga | 936 | R$ 63,5 mi | — | Cooperativa, taxa boa, limite modesto |

Cada carrier tem **personalidade consistente**: quem cobra taxa baixa concede limite maior
e tem indice de recusa maior. Isso e o que faz a tela de comparacao entre carriers ter
sentido, e e onde o cliente vai olhar.

### 5.2 Clientes (`Project`) — 12, com cauda

Nomes ficticios, CNPJ com digito verificador valido (as telas podem validar), razao social
completa em `formal`, endereco real de cidade brasileira, `closing_date` variado.

| # | Perfil | Segmento | Empresas | Carriers | Volume/mes |
| - | ------ | -------- | -------- | -------- | ---------- |
| 1–2 | Grupo grande | Industria | 4–6 | 4–5 | R$ 8–14 mi |
| 3–6 | Medio | Industria / Comercio | 2–3 | 2–3 | R$ 1,8–4,5 mi |
| 7–10 | Pequeno | Comercio / Servicos | 1–2 | 1–2 | R$ 350–900 mil |
| 11 | **Em recuperacao** | Industria | 2 | 1 | caindo, renegociacoes ativas |
| 12 | **Recem-entrante** | Servicos | 1 | 1 | 2 meses de historico so |

Os dois ultimos existem de proposito: **um sistema real tem clientes em situacoes
diferentes**. O cliente #11 e o que faz a tela de renegociacao e o semaforo de risco terem
o que mostrar; o #12 prova que o sistema lida com historico curto sem quebrar grafico.

### 5.3 Empresas (`Company`)

Razao social derivada do grupo, com sufixo plausivel — `Industria e Comercio Ltda`,
`Participacoes S.A.`, `Logistica Ltda`, `Filial Nordeste`. Nunca `Company teste 1`.

---

## 6. Volumetria alvo

| Entidade | Volume | Por que |
| -------- | ------ | ------- |
| `Project` | 12 | Paginacao de 10 mostra 2 paginas |
| `Company` | ~28 | Media de 2,3 por projeto |
| `Carrier` | 5 | Comparacao entre contrapartes fica legivel |
| `RiskControl` | ~70 | Empresa x carrier — a matriz de limites tem densidade |
| `ReceivableEntry` (borderô) | **~2.900** | 24 meses x 12 clientes x 6–14 borderôs/mes. E o que justifica busca e filtro |
| `RiskOperation` | ~640 | ~70% encerradas, ~25% vivas, ~5% vencidas |
| `RiskMovement` | ~4.100 | 5–8 por operacao |
| `StructuredOperation` | ~90 | Menos frequente que a de risco |
| `Renegotiation` | 34 | Concentradas nos clientes 3, 7 e 11 |
| `RenegotiationInstallment` | ~380 | 6 a 24 parcelas cada |
| `ProjectGuarantee` | ~45 | Nem todo projeto tem |
| `IndicatorEntry` | ~1.700 | Indicadores x 24 meses x 12 projetos — enche os graficos |

**~10 mil registros.** Suficiente para o sistema respirar, pequeno o bastante para o seed
rodar em segundos e caber num dump leve.

---

## 7. As regras de coerencia (a parte que da trabalho e que ninguem ve — ate falhar)

1. **Limite x utilizacao.** A soma das operacoes vivas de uma empresa num carrier **nunca**
   ultrapassa o `RiskControl` da modalidade. Dois casos ficam em ~92% de proposito, para o
   alerta de limite aparecer. Nenhum estoura.
2. **Taxa da operacao = taxa do controle** (+/− 0,15 p.p. de negociacao pontual). Operacao
   a 2,1% num controle de 3,0% e incoerencia visivel.
3. **Borderô:** `vlr_bruto_final = valor_bruto − vlr_bruto_recusado` e
   `qtd_final = qtd_titulos − qtd_recusada`. Recusa entre 0% e 12%, com a maioria em 0.
4. **`diferenca_float = float_calculado − float_acordado`**, e nao um terceiro numero
   sorteado.
5. **Saldo da operacao** e o resultado dos `RiskMovement`, nao um campo independente.
6. **Renegociacao:** `total_debt = original_pending_value + additional_value + correct_value`;
   `remaining_value = total_debt − paid_value`; parcelas somam o total.
7. **`IndicatorEntry`** acompanha o volume operado do mesmo mes. Faturamento subindo com
   volume descendo, sem motivo, e o tipo de coisa que um analista percebe.

> **Como garantir isso na pratica:** onde o app tiver servico proprio de calculo, **o seed
> chama o servico** em vez de escrever o numero final. Assim o dado da demo nasce pelo
> mesmo caminho do dado real — e respeita o **DEC-01** (convencao de sinal do risco) e o
> **DEC-02** (aritmetica em float), que existem justamente para os totais baterem.

---

## 8. Serie temporal — 24 meses com historia

- **Meses 1–8:** operacao estavel, 3 carriers.
- **Mes 9:** entra o **FIDC Aurora** — o volume migra em parte, a taxa media cai.
- **Meses 12–14:** **retracao sazonal** (dez–jan), volume cai ~30%, recusa sobe.
- **Mes 15:** cliente #11 entra em dificuldade — atrasos, depois renegociacao.
- **Meses 16–24:** recuperacao, entra o cliente #12, volume total cresce ~40%.

Isso da aos graficos **forma**, e forma e o que faz o cliente perguntar "o que aconteceu
aqui?" — que e exatamente a pergunta que vende a ferramenta.

---

## 9. Usuarios — demonstram a matriz de autorizacao (DEC-18)

| Usuario | Papel | Para que serve na demo |
| ------- | ----- | ---------------------- |
| 1 (Livetat) | **OG** | Fornecedor. Mostra Permissoes e impersonation auditada. **Nao** usar na apresentacao ao cliente |
| 2 | **Admin** | O protagonista da demo. Ve tudo do cliente, administra usuarios e permissoes de hierarquia inferior |
| 3 | **Gerente** | Prova a matriz: ve Cadastro, **nao** ve Admin; le usuarios e convida, nao cria |
| 4 e 5 | **Colaborador** | Membros de projetos diferentes — provam o escopo por membership |
| 6 | **Colaborador + `user_is_readonly`** | Prova o modificador: os mesmos dados, **sem nenhum botao de escrita** |

Trocar de usuario ao vivo e a forma mais rapida de demonstrar governanca — que costuma ser
o que decide compra em ferramenta de credito. Senhas fortes e distintas (**nunca** o padrao
deterministico do D-109).

---

## 10. Determinismo, idempotencia e seguranca

- **Semente fixa** (`Random.new(20260828)`): rodar duas vezes da o **mesmo** banco. Sem
  isso, "estava R$ 4,2 mi ontem" vira uma conversa ruim no meio da apresentacao.
- **Idempotente**: `rake demo:seed` limpa e recria. Poder resetar entre ensaios importa.
- **Datas relativas a uma data-base parametrizavel** — o dado nao "envelhece" se a
  apresentacao mudar de dia.
- **Nenhum dado real de cliente**, nem anonimizado, sem autorizacao explicita.
- Separado do seed de producao: `db/seeds/demo/` + `rake demo:seed`, **nunca** dentro do
  `db/seeds.rb`. No cutover real, o seed de demo nao roda.

---

## 11. Roteiro sugerido (o que a demo mostra, em ordem)

1. **Login** com a marca Safegold — primeira impressao, e por isso o
   `theming-brand-engineer` roda antes de qualquer tela.
2. **Lista de clientes** — 12 linhas, paginacao viva, busca funcionando.
3. **Detalhe do cliente grande** — empresas, carriers, limites por modalidade, garantias.
4. **Borderôs** — volume real, filtro por periodo e carrier, recusa parcial visivel.
5. **Operacoes de risco** — vivas x encerradas, saldo, movimentos, alerta de limite em 92%.
6. **Cliente #11** — a historia: atraso, renegociacao, parcelas, recuperacao.
7. **Indicadores** — 24 meses de grafico com a inflexao do mes 9 e a sazonalidade.
8. **Troca de usuario** — Gerente e depois o readonly, provando a matriz.

---

## 12. Como isto vira codigo (Phase 3)

- Depende de: schema migrado (data engineer) e dos servicos de calculo (backend).
- Estrutura: `backend/db/seeds/demo/` — um arquivo por agregado, um orquestrador,
  `lib/tasks/demo.rake`.
- Testes: um spec que roda o seed e **verifica as 7 regras da secao 7**. Seed que gera
  numero incoerente e bug, nao "dado de exemplo".
- **Vale como teste do ETL** (DEC-16, item 3): o script de migracao de dados e exercitado
  contra este banco antes de ver dado real.

---

## 13. Estado da implementação — 26/08/2026 (DEC-102)

O desenho acima é de 25/08, quando quase nenhum model existia. O que mudou depois de
S3..S11 entregarem, e o que **ainda não** está semeado:

| Agregado | Estado | Linhas em `sfg9_dev` |
| -------- | ------ | -------------------- |
| Clientes, empresas, contrapartes, segmentos, participações, elenco | gravando | 12 · 28 · 5 · 15 · 30 · 6 |
| Limites (`risk_controls`) e garantias | gravando | 66 · 37 |
| Operações de risco e movimentos | gravando | 611 (+48 estáticas) · 3.252 |
| Fornecedores, renegociações, parcelas, pagamentos | gravando | 75 · 34 · 348 · 228 |
| Indicadores e lançamentos | gravando **em dinheiro** | 5 · 1.310 |
| **Borderôs** (`ReceivableEntry`) | **aguarda a S6** | 2.668 prontos no razão |
| **Operações estruturadas** | **aguarda a S8** | 101 prontos no razão |

### As três pendências que valem para a apresentação

1. **Os borderôs são o maior volume da demonstração e ainda não têm tabela.** São 2.668
   linhas prontas no razão — é o que dá busca, filtro por período e paginação de verdade.
   Enquanto a S6 não entrega, a lista mais longa que a demonstração tem é a de lançamentos
   de indicador.
2. **`Indicator::VALUE_TYPES` tem um elemento** (`"Dinheiro"`, Q-R32). Índice de recusa,
   custo efetivo médio e prazo médio ponderado ficam **fora** do banco: lançar um
   percentual como "Dinheiro" faria o gráfico imprimir "R$ 12,40" para 12,4% — a tela que
   finge que a DEC-102 proíbe. Os três estão prontos no razão e entram no dia em que a S10
   aceitar outro tipo. Para não empobrecer o gráfico, o razão ganhou dois indicadores em
   dinheiro que saem da mesma agregação: **Valor recusado** e **Custo total de tarifas**.
3. **A tela de operações de risco, a de recebíveis e a de renegociações ainda não existem
   no frontend** (`element: null` em `consoleNavigation.tsx`, fatias S6/S7/S9). O dado
   está no banco e a API responde; o que falta é a tela. As que já existem e mostram o
   seed: Projetos, Empresas, Fornecedores, Limites, Controle de Risco, Portadores do
   projeto, Garantias, Lançamentos de indicadores, Contas.

### O que mudou no desenho (e por quê)

Três promessas de §7 e §9 foram **revistas contra o sistema entregue**, e é honesto
registrar por quê:

1. **"Nenhum estoura" virou "um estoura, escolhido".** A S5 entregou o aviso de estouro
   (NEW-005): com a promessa original, ele era um recurso que a apresentação nunca
   mostraria. Um único grupo, no cliente em recuperação, passa de 100%.
2. **A utilização alvo é medida na JANELA da data-base**, não sobre todas as operações
   vivas — porque é a janela que o painel soma (`RiskOperation.on_date`). Antes disto o
   razão afirmava 92% e a tela mostrava 53%, os dois certos, medindo coisas diferentes.
3. **O elenco tem um usuário sem projeto corrente de propósito** (o OG): é o que demonstra
   o `409 PROJECT_NOT_SELECTED`, a tela de escolha de projeto. Nunca o usuário com que a
   apresentação começa.
4. **Renegociação tem piso de 3 por cliente**, e não zero fora dos três da história. A
   concentração continua (12, 9 e 13 nos clientes 3, 7 e 11), mas a tela existe desde que a
   S9 entregou e o projeto que a apresentação abre primeiro não pode ter lista vazia.
   Volume final: 61 renegociações, 694 parcelas, 446 pagamentos.

---

## 14. A passada de cobertura — 26/08/2026 (segunda medição)

A §13 mediu o que **existia**. Esta seção mede o que **aparece na tela**, que é outra
coisa — e é a que vale, porque **a apresentação não é conduzida por quem construiu o
sistema**. Quem apresenta não sabe desviar de tela vazia: o que estiver faltando vai
aparecer, e vai aparecer no meio da conversa.

### A regra de aceitação

Palavras do usuário: *"a maioria dos projetos tem que ter tudo preenchido; menos da metade
pode ficar faltando algumas coisas."*

Lacuna em minoria é realista — projeto novo, projeto pequeno — e até ajuda a demonstrar o
estado vazio. O que não pode é a lacuna ser **sobra**. Cada projeto sem uma área está numa
lista nomeada no razão, com o motivo escrito, e `spec/lib/demo/coverage_spec.rb` reprova
quem criar uma lacuna fora dessas listas.

### O que a medição encontrou (antes)

| projeto | empresas | limites | borderôs | renegoc | padrões | disponib | cobranças | indic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Agroinsumos Cerrado | 1 | 1 | 0 | 3 | **0** | **0** | **0** | 101 |
| Comercial Porto Belo | 2 | 4 | 0 | 9 | **0** | **0** | **0** | 120 |
| Componentes Vale do Rio | 2 | 4 | 0 | 3 | **0** | **0** | **0** | 120 |
| Distribuidora Campo Largo | 3 | 8 | 0 | 3 | **0** | **0** | **0** | 120 |
| Fundição Três Rios | 2 | 2 | 0 | 13 | **0** | **0** | **0** | 120 |
| Grupo Aliança Metalúrgica | 5 | 18 | 0 | 4 | 13 | 234 | **0** | 120 |
| Móveis Bento Gonçalves | 2 | 6 | 0 | 3 | **0** | **0** | **0** | 120 |
| Nordeste Alimentos | 4 | 10 | 0 | 3 | **0** | **0** | **0** | 120 |
| Química Paulista Reunidas | 2 | 4 | 0 | 3 | **0** | **0** | **0** | 120 |
| Serviços Litoral Norte | 1 | 1 | 0 | 3 | **0** | **0** | **0** | 120 |
| Tecnologia Ribeirão | 1 | 1 | 0 | 3 | **0** | **0** | **0** | 10 |
| Têxtil Serra Azul | 3 | 7 | 0 | 12 | 13 | 156 | **0** | 120 |
| Verificação S4 Alfa | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Zeradas no banco inteiro: `charges`, `receipts`, `admin_messages`, `observers`,
`observer_contexts`, `receivable_taxes`.

Os 234 e 156 lançamentos de disponibilidade **não vinham de escritor nenhum**: eram linhas
criadas à mão por quem verificou a S11 (nenhuma delas existe no repositório — a varredura
por título não encontra nada). Um resultado que nenhuma execução do seed reproduzia.

### O que a passada entregou (depois)

Medido em `sfg9_dev` com data-base 26/08/2026.

| projeto | empresas | limites | borderôs | operações | renegoc | padrões | disponib | datas | cobranças | recibos | indic |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Agroinsumos Cerrado | 2 | 5 | 194 | 43 | 3 | 17 | 255 | 5 | **0** | **0** | 120 |
| Comercial Porto Belo | 2 | 5 | 198 | 41 | 9 | 17 | 255 | 5 | 3 | 14 | 120 |
| Componentes Vale do Rio | 3 | 10 | 275 | 95 | 3 | 17 | 340 | 5 | 4 | 20 | 120 |
| Distribuidora Campo Largo | 3 | 7 | 261 | 63 | 3 | 17 | 340 | 5 | 4 | 27 | 120 |
| Fundição Três Rios | 2 | 4 | 185 | 49 | 13 | 17 | 255 | 5 | 3 | 17 | 120 |
| Grupo Aliança Metalúrgica | 6 | 19 | 340 | 219 | 3 | 17 | 833 | 7 | 7 | 43 | 120 |
| Móveis Bento Gonçalves | 2 | 6 | 186 | 54 | 3 | 17 | 255 | 5 | 3 | 14 | 120 |
| Nordeste Alimentos | 5 | 14 | 336 | 128 | 3 | 17 | 510 | 5 | 7 | 41 | 120 |
| Química Paulista Reunidas | 3 | 7 | 260 | 68 | 3 | 17 | 340 | 5 | 6 | 34 | 120 |
| Serviços Litoral Norte | 2 | 4 | 194 | 34 | 3 | 17 | 255 | 5 | **0** | **0** | 120 |
| Tecnologia Ribeirão | 1 | 2 | 13 | 3 | 3 | 17 | **0** | **0** | **0** | **0** | 10 |
| Têxtil Serra Azul | 4 | 13 | 264 | 136 | 12 | 17 | 595 | 7 | 5 | 30 | 120 |

Globais: 28 mensagens administrativas · 39 falas de thread · 6 observadores · 12 contextos
de observador · 16 padrões no catálogo global · 10.824 tarifas de borderô.

Cada projeto tem **17** padrões: os 16 do catálogo global mais **um específico do
projeto** (`Comissões de representantes`). Sem esse um, a coluna "Marcadores" da tela de
padrões seria dezessete linhas dizendo "Global" e o selo de escopo não demonstraria que
existe diferença entre catálogo e customização — foi o que a primeira renderização
mostrou, ao contrário: o escritor não copiava `is_global` e as dezesseis diziam
"Específico", que é a mesma tela monocromática pelo outro lado.

**Nove dos doze projetos têm tudo. Três têm lacuna, e as três são escolhidas.**

### As três lacunas, e por que cada uma existe

| projeto | falta | motivo |
| --- | --- | --- |
| **Tecnologia Ribeirão** (#12) | lançamento de disponibilidade e cobrança | Entrou há dois meses. Recebe a **árvore de padrões** (a grade abre com as dezesseis linhas certas e nenhum valor — o estado vazio honesto do painel) e não tem operação encerrada para faturar. É o cliente que prova que as telas sobem com histórico curto. |
| **Agroinsumos Cerrado** (#8) | cobrança | Um dos dois menores da carteira; faturado no contrato do grupo, não por pacote. |
| **Serviços Litoral Norte** (#10) | cobrança | Mesma razão. |

Um exemplo de tela vazia é **necessário**: sem ele a apresentação nunca mostra o que o
sistema diz quando não há nada, e essa é uma pergunta que o cliente faz.

### O que passou a ser semeado

1. **Disponibilidades** (`ledger/availability.rb`, dois escritores). Catálogo global de
   **16 padrões** em três níveis, copiado para os doze projetos com
   `global_availability_template_id` preenchido. Dois padrões `is_adjusted` — um de
   crédito, um de débito — para o par **base × corrigido** (FE-134 / DEC-24) ter o que
   mostrar, e um **não cumulativo** (`Carteira cedida`) para `is_cumulative` deixar de ser
   uma flag sem demonstração. O razão declara **só as folhas**: nó com filhos, padrão base
   e consolidação geral são materializados pelo `after_save` do model, que é o mesmo
   caminho por onde a tela grava — um cálculo, um dono.
   Três a quatro datas por mês (seis nos dois clientes que a apresentação abre primeiro),
   que é o que marca dias no calendário e faz o saldo acumulado variar.
2. **Mensagens administrativas e observadores** (`ledger/service_desk.rb`). 28 tickets
   cobrindo **as 8 situações e os 4 contextos**, 9 threads com resposta do administrador e
   duas com resposta do remetente depois dele, 4 mensagens internas, 6 observadores dos
   quais **dois não são internos** — que é o par que prova `Observer.for_message`.
   Chave natural: um **UUID v5 determinístico** em `public_token`. O model gera o token com
   `SecureRandom`, então sem isso cada execução criaria 28 mensagens novas; `legacy_id` não
   serve (DEC-12 reserva a coluna para proveniência do legado).
3. **Cobranças e recibos** (`ledger/billing.rb`). 42 pacotes e 240 recibos, com as três
   situações (`editing`/`available`/`done`) presentes em cada cliente que fatura. A cadeia
   é `charge → receipts → operation`, nunca um atalho (D-B11). Nenhum recibo `EST`:
   `StructuredOperation` é da S8 e os contadores de estruturada ficam em zero **por
   coerência**, não por esquecimento.
4. **Empresas e limites**. `company_count` e `carrier_keys` subiram: onze dos doze clientes
   passam a ter **duas ou mais** empresas e **duas ou mais** contrapartes. Sem duas
   empresas a consolidação do painel repete a linha da empresa única; com um limite só a
   tela de Limites não tem carteira para comparar. Total: **35 empresas** (era 28) e **96
   limites** (era 66).

### O escritor de borderôs estava FALHANDO, e isso valia 13.530 linhas

`rake demo:seed` terminava com status ≠ 0 e a mensagem
`Autor não pode ficar em branco, Situação não está incluído na lista`. Três exigências que
a S6 acrescentou depois de o escritor ter sido escrito:

- `validates :user_id, presence: true` (BE-182 — o autor é o da sessão, nunca o do corpo);
- `cst_efetivo_acordado` obrigatório — é entrada digitada, não derivado, e é dele que sai
  `calc_valor_liq_correto`;
- `status` virou domínio fechado `ok`/`difference` (`Entry::STATUSES`); o razão gravava
  `'OK'`, que é o **rótulo** pt-BR do legado, não o valor.

Mais duas colunas com o nome errado, descartadas em silêncio pelo `assign`
(`tarifas_advalorem` → `tarifas_ad_valorem`, `valor_liq_correto` →
`calc_valor_liq_correto`), e três títulos de catálogo que não existem no seed de
referência entregue (`Cartão de crédito` → `Cartão`, `Retenção` → `Comissaria`) — o
`find` devolvia `nil` e o model recusava por chave estrangeira em branco.

Resultado: **2.706 borderôs e 10.824 tarifas** passaram a ser gravados, e os ~30 derivados
saem do `Receivables::Calculator` — o motor do contrato C2, chamado uma vez por borderô
com a alíquota de IOF vigente na data. Preenchê-los à mão seria uma segunda implementação
da conta que o C2 existe para manter única, e a tela ordena por três deles.

### As duas armadilhas de idempotência que esta passada encontrou

1. **`Base#persist!` pergunta `changed?` ANTES de validar, e num padrão corrigido isso
   mente.** O que fica em `availability_entries.value` é o valor já multiplicado pelos dias
   úteis; o que o razão declara é a **base**. Atribuir a base marca `value` como alterado, a
   validação recalcula, o valor volta ao que estava — e o contador já registrou
   "atualizado". Eram **312 atualizações fantasmas por execução**, para sempre.
   A saída **não** é validar antes de contar: rodar o `before_validation` duas vezes num
   registro novo é exatamente o decaimento composto do BE-123 (`original_value` receberia o
   valor já corrigido e a célula encolheria a cada gravação). A pergunta passou a ser feita
   no campo certo — num padrão corrigido, a entrada digitada mora em `original_value`.
2. **A máquina de estados de `MessageNote` corrige a mensagem depois de o seed a gravar.**
   `after_create` move "Lido" → "Respondido" na primeira fala do administrador, e
   "Respondido" → "Aberto" quando o remetente responde depois dele — por `update_columns`,
   que carimba `updated_at`. O razão passou a declarar **o estado que a máquina produz**, e
   o escritor deixou de escrever `updated_at`.

Portão medido em banco recém-criado, com o schema do dia: **1ª execução 24.230 criados;
2ª, 0 criados, 0 atualizados, 24.737 inalterados.** O reset foi medido à parte: 6 usuários do elenco removidos, **3 de fora
preservados**, inclusive `vinaoxd@gmail.com`.

### A terceira armadilha: o painel abre com HOJE, e hoje não tinha lançamento

Renderizada, a primeira versão mostrou o pior estado possível: **a grade inteira em
`R$ 0,00`** com o calendário marcando pontos em quatro outros dias e os cards de saldo do
mês cheios de dinheiro. Não é vazio — é o que parece defeito. A causa era boba: as datas
eram os dias 4, 11, 18 e 25, e o painel abre com a **data-base** selecionada.

A data-base passou a entrar sempre na lista (`business_day_on_or_before(base_date)`), e há
um exemplo de spec que confere isso em três datas-base diferentes — um dia útil no meio do
mês, o **1º** (quando o mês corrente tem uma data só) e o **último dia do ano** (quando o
mês anterior é de outro ano).

### A trilha de auditoria crescia a cada ensaio, e o reset não a alcançava

`versions` (paper_trail, DEC-59) **não tem `project_id`**, então a varredura de tabelas
escopadas do reset passava ao largo dela. Medido depois de três `demo:reseed` no banco de
desenvolvimento: **14.993 linhas**, das quais 8.130 de `ReceivableEntry` para 2.706
borderôs — três gerações de registro apagado. Repetir a apresentação cinco vezes encheria a
tela de Trilha de auditoria de eventos de criação de registros que não existem mais.

O reset passou a remover as versões **órfãs**, tipo a tipo, com `NOT EXISTS` contra a
tabela do próprio model: nenhuma versão de registro vivo é tocada, e a garantia é a
consulta, não uma lista de tipos. Isto não apaga rastro de exclusão de negócio — o reset
usa `DELETE` cru, que não passa por callback e nunca gerou versão de `destroy`; o que sai é
a versão de `create` de um registro que o próprio seed inventou e removeu.

Depois: **4.255 versões, zero órfãs.**

### A S7 entregou no meio da passada, e levou o escritor de operações junto

Três coisas mudaram em `RiskOperation`/`RiskMovement` **depois** de o seed já estar rodando
verde, e as três quebraram o escritor de um jeito diferente. Todas foram consertadas **no
escritor** — nenhuma linha de model foi tocada.

1. **`validates :user_id, presence: true, unless: :is_static?`** (`risk_operation.rb:114`,
   BE-261). O escritor não gravava autor: as **933 operações** passaram a falhar em bloco,
   e com elas os movimentos, os recibos e as cobranças. Corrigido com o Admin do elenco,
   o mesmo autor que o borderô já usa.
2. **`balance` virou cache derivado do model.** `before_validation :refresh_balance_cache`
   chama `Risk::Calculator.recalculate_chain` em **todo** save (BE-265). O escritor
   propunha o saldo do razão, o model o reescrevia um instante depois, e a execução
   seguinte propunha de novo: **855 operações e 4.547 movimentos "atualizados" para
   sempre**. A coluna deixou de ser escrita pelo seed — quem calcula é quem é dono do
   cálculo, que é o §7 deste desenho.
3. **`sequence` também é reatribuída pelo recálculo**, na ordem `date ASC, created_at ASC`
   (`calculator.rb:208-214`), e essa é a **chave natural** do escritor de movimentos.
   Como o razão insere em ordem própria, 71 dos 4.547 movimentos ficavam com um número que
   o model reescrevia — e aí `(operação, sequence)` deixava de encontrar a linha que a
   gravou: **a execução seguinte reescrevia o movimento errado com os valores de outro.**
   Não era contador inflado; era dado trocado.
   O escritor passou a ordenar pela mesma chave que o model usa **e** a gravar `created_at`
   derivado da data do movimento — sem o desempate explícito, dois lançamentos do mesmo dia
   trocavam de lugar entre execuções, porque o Postgres devolve empate na ordem que quiser.

**A lição, para a próxima fatia que entregar em cima do seed:** coluna que o model
recalcula em `before_validation` **não pode** ser proposta pelo escritor, e chave natural
não pode ser coluna que o model reescreve.

### Aviso de bancada: `rubocop -a` reescreveu o gerador de aleatoriedade, de novo

`Support::Rng#sample` usa `list.shuffle(random:).first(n)` e **não**
`Array#sample(n, random:)`: as duas consomem o gerador de formas diferentes, e trocar uma
pela outra muda **todos** os números do seed. O arquivo tem um `rubocop:disable
Style/RedundantSort` e um comentário dizendo que isso já aconteceu uma vez por
autocorreção.

Aconteceu de novo nesta passada: `rubocop -a --only Layout,Style,Lint` sobre
`db/seeds/demo` reescreveu a linha apesar do `disable` (o cop que corrigiu foi outro).
Revertido. **Quem rodar autocorreção nesta pasta confere `git diff support/rng.rb` antes de
qualquer outra coisa.**

### `Verificação S4 Alfa` é resíduo solto, e NÃO é criada pelo seed

Varredura por `Verificação S4`, `S4 Alfa` e `verificacao-s4-alfa` em todo o repositório:
**nenhuma ocorrência em código, seed ou fixture** (o único acerto é um cache de bytecode do
`bootsnap`). O projeto foi criado em `sfg9_dev` às 02:46 de 26/08, uma hora e vinte antes
da primeira execução do seed (04:03) — é rastro de conferência da S4, do mesmo tipo dos
`alpha`/`beta` que a S0 deixou.

Ele **não foi apagado**: apagar projeto de outra fatia no banco compartilhado sem avisar é
o tipo de coisa que estraga a bancada de quem está trabalhando. O mecanismo para removê-lo
já existe e é uma linha — `Writers::Scaffolding::LEFTOVER_PROJECT_SLUGS` —, e a decisão é
do dono do banco. **Enquanto ele estiver lá, a lista de clientes da apresentação abre com
um projeto vazio chamado "Verificação S4 Alfa".**

### Custo de execução, e o que ele impôs ao spec

O seed passou de ~6,7 mil para **24,7 mil linhas** e de 32 s para ~3 min 40 s.

O spec do orquestrador grava o seed inteiro **uma vez por exemplo**, e por isso ele passou
a rodar em **modo amostra**: janela de 2 meses (`span: 2`) e a grade de disponibilidade
reduzida a um cliente e uma data. Os mesmos caminhos são exercitados — todos os
escritores, a cascata de derivados, a máquina de estados da mensagem, o reset — com uma
fração das gravações.

Com o modo amostra ligado, `spec/lib/demo` fecha em **7 min 15 s — 59 exemplos, 0
falhas**, contra 14 min 45 s da primeira medição, e isso com o seed tendo passado de 6,7
mil para 24,7 mil linhas.

Sem ele o custo explode, e há um número para provar: numa execução em que a linha
`span: 2` do spec se perdeu num commit e a série voltou aos 24 meses, **três exemplos
levaram 21 min 58 s**. Fora da suíte o mesmo seed em amostra leva **20 s** (medido writer a
writer, dentro de uma transação que volta atrás) — o custo é do ambiente de teste,
`SimpleCov` instrumentando 23 mil linhas mais a contenção com a suíte de outro agente na
mesma máquina, não do escritor.

Quem confere volumetria, cobertura e as regras de aceitação é `coverage_spec.rb`, que roda
**no razão**, sem banco: **46 exemplos em 5,6 s** junto com o `ledger_spec.rb`. É lá que se
acrescenta verificação nova; o spec do orquestrador é o que prova que o banco aceita.

**Os dois botões**, para quem precisar apertar mais: `Demo::Ledger.new(span:)` encurta a
série, e `Availability.entries(sample:)` reduz a grade a um cliente e uma data.

### O que continua pobre, e o que falta para melhorar

> ⚠ **A tabela abaixo é de 26/08/2026 e envelheceu em 24 horas.** Ela fica como
> registro do que foi medido naquele dia; o que vale hoje está na §15.

### O que continua pobre, e o que falta para melhorar

Medido renderizando, em 1440×900 e 390×844, claro e escuro, com o seed dentro.

| tela | o que está pobre | o que falta |
| --- | --- | --- |
| **Cobranças** | toda linha diz `0 est.` e o extrato por remuneração responde 422 | `StructuredOperation` e `Remuneration` são da **S8**. O razão já tem 136 operações estruturadas prontas; é um `select` a mais em `ledger/billing.rb` no dia em que a tabela existir |
| **Renegociações** | a lista mais longa tem **13** linhas e nunca chega à segunda página (`per_page` 20) | a `integration_key` da renegociação é única por projeto e derivada do nome do fornecedor: com 16 nomes em `Ancillary::PROVIDERS`, 16 é o teto por cliente. Passar de 20 exige ampliar a lista de fornecedores |
| **Limites** | 19 linhas no maior cliente — também uma página só | idem: subir empresas ou contrapartes do cliente #1 |
| **Recebíveis** | a coluna **Situação** fica cortada em 1440 px; a tabela rola na horizontal | é largura de tabela da **S6**, não dado |
| **Operações de Risco / Estruturadas / Remunerações** | `element: null` no `consoleNavigation.tsx` | as telas são de **S7** e **S8**. O dado está no banco (933 operações, 4.547 movimentos) e a API responde |
| **Indicadores** | três dos oito indicadores do razão não viram lançamento | `Indicator::VALUE_TYPES` tem um elemento (`Dinheiro`, Q-R32). Índice de recusa, custo efetivo médio e prazo médio ponderado entram no dia em que a **S10** aceitar percentual e dias |
| **Trilha de auditoria** | `permission_audit_logs` continua zerada | é o certo: a **DEC-59** decidiu que a trilha é `paper_trail`, e a tabela ficou sem escritor de propósito. O que alimenta a tela de trilha é `versions`, com 4.255 linhas |
| **Dashboard** | "Sem indicadores por enquanto" | a tela avisa que vai ser construída sobre os dados da operação; não é lacuna de seed |


---

## 15. A passada de 27/08/2026 — o que a tabela da §14 já não diz

Medido **executando**: `demo:seed` até convergir, os serviços do próprio sistema
para os agregados, e 645 renderizações (43 rotas × 5 papéis × claro/escuro/390×844).

### O que fechou

| §14 dizia | o que foi medido em 27/08 |
| --- | --- |
| **Cobranças**: "toda linha diz `0 est.` e o extrato por remuneração responde 422" | **fechado.** 33 recibos `EST` em 20 dos 42 pacotes; o extrato por remuneração abre com as duas classes. A divisão é por estado: pacote `done` leva `EST`, `editing`/`available` não — e sobram **79** estruturadas encerradas sem recibo, que são os candidatos que a apresentação marca ao vivo |
| **Indicadores**: "três dos oito não viram lançamento… entram no dia em que a S10 aceitar percentual e dias" | **a premissa estava errada.** No dump de 31/05/2025, `value_type` é `"Dinheiro"` em **529 de 529**. Não há esse dia: `VALUE_TYPES` de um elemento é o espelho da produção (DEC-30), e acrescentar percentual seria acrescentar recurso que o legado não tem (DEC-09) |
| **Operações de Risco / Estruturadas / Remunerações**: "`element: null` no `consoleNavigation.tsx`" | **fechado** pela entrega da S7/S8. As três abrem com dado nos cinco papéis e nos três modos |
| **Dashboard**: "Sem indicadores por enquanto" | **fechado.** O painel abre com total operado, exposição, "Limites no teto", "Renegociações em atraso", série de 12 meses com a inflexão sazonal, exposição por portador e consumo de limite por tipo |

### O que a passada acrescentou ao seed

- **Folga de fornecedor** — "Nova renegociação" dava **422 nos 3 fornecedores
  oferecidos** nos 12 projetos, porque o seed cadastrava exatamente os que as
  renegociações já usavam. `PROVIDER_SLACK = 5`.
- **Indicadores de projeto** — o espelho estava invertido (produção: 527 de
  projeto e 2 globais; o seed: 5 globais e zero específico). Entram 4 em 3
  clientes, cada um sendo outro recorte da **mesma** lista de borderôs.
- **Os dois indicadores da DEC-116** — davam `0` e `0` em **10 dos 12**
  projetos; agora 9 dos 12 têm algo, e **3 ficam limpos de propósito** (os dois
  menores da carteira e o entrante), porque sem um cliente tranquilo a base
  inteira parece um desastre.
- **A transferência pré ↔ antecipação** — as 78 operações estáticas tinham saldo
  zero e zero movimentos, e o razão lançava 105 "Transferência Recebida"
  **soltas** em operações comuns (dado que o sistema não produz). O par de
  verdade passa a existir, gravado pelo `Risk::TransferService`.

### O que continua pobre — a lista curta de hoje

| tela | o que está pobre | o que falta |
| --- | --- | --- |
| **Renegociações** | a lista mais longa tem **13** linhas e nunca chega à segunda página (`per_page` 20) | subir a volumetria de renegociações do cliente #11. A lista de fornecedores deixou de ser o teto (são 24 nomes agora), então é decisão de história, não de esquema |
| **Limites** | 19 linhas no maior cliente — também uma página só | subir empresas ou contrapartes do cliente #1 |
| **Recebíveis** | a coluna **Situação** fica cortada em 1440 px; a tabela rola na horizontal | é largura de tabela da **S6**, não dado |
| **Trilha de auditoria** | `permission_audit_logs` continua zerada | é o certo (DEC-59): o que alimenta a tela é `versions` |
| **Saldo inicial do limite** | `original_balance` e `original_balance_pre` são **0 nos 96 limites** | é o "saldo inicial" do par estático. Por desenho ele **não entra em agregado nenhum** enquanto não houver movimento (`Risk::StaticPairService`, golden `L2`), então preenchê-lo não muda número na tela — mas a ficha da operação estática mostra `R$ 0,00` onde caberia o valor negociado. **Decisão do usuário**, porque escolher um valor é inventar cadastro |

### A armadilha de convergência que esta passada descobriu

Mudar o **plano de utilização** exige **duas ou mais passadas** do seed para
convergir: `prune_stale_operations!` roda antes de `charges` e recusa apagar
operação que ainda tem `receipt_id`; quem solta o vínculo é o escritor de
cobranças, que roda depois. A mensagem dizia "removendo 29" e removia 14 —
agora ela conta o que **saiu** e explica o que ficou. Não é defeito: é a ordem
de dependência, e agora está escrita.
