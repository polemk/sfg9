# Perguntas da rodada 1 — metade nascida no empacotamento (20 openspec changes)

> **Origem:** DEC-23 (rodada completa antes/durante o Phase 3). Este arquivo cobre **só** o
> que nasceu no empacotamento em fatias: as tarefas de decisão `T-D1..T-D13`, as decisões que
> os agentes tomaram por conta própria (`DS0-*`, `DS1-*`, `DS2-*`, `Q-19..Q-23`), os conflitos
> entre dois changes descobertos no fechamento do Phase 2, e as lacunas que só aparecem quando
> se olha os 20 changes juntos.
>
> **A outra metade** — as ~76 perguntas dos 5 mapas de bloco (`Q-A*`, `Q-B*`, `Q-R*`, `Q-01..Q-14`
> de `data-infra`) — está em `.migration-ai9/perguntas-rodada-1-mapas.md`, escrita por outro
> agente. Onde uma pergunta de proposal só repetia uma de mapa sem acrescentar nada, deixei
> lá e registrei aqui na seção "Duplicatas".
>
> **Nada aqui já foi decidido.** O cruzamento com `decisions.md` (DEC-01..DEC-23) está no fim.

## Contagem

| | |
| - | - |
| **Total de perguntas neste arquivo** | **51** |
| Removidas por já estarem decididas (DEC-01..DEC-23) | 24 |
| Deixadas para o outro agente por serem duplicata pura do mapa | 19 |
| Divergências proposal × fonte que encontrei e corrigi | 5 (ver fim) |

### Quebra por impacto

| Impacto | Quantidade | Faixa |
| ------- | ---------- | ----- |
| `muda número na tela` | 11 | F-01 … F-11 |
| `muda comportamento observável` | 21 | F-12 … F-32 |
| `muda escopo` | 16 | F-33 … F-48 |
| `só interno` | 3 | F-49 … F-51 |

---

## As que travam código AGORA

Estas impedem alguém de começar uma tarefa hoje. Não são as mais importantes — são as que
já estão com gente parada na frente.

| # | O que está parado | Onde |
| - | ----------------- | ---- |
| **F-33** | **O seed de demonstração não tem fatia nenhuma.** S18 já criou `lib/tasks/demo.rake` **vazio**; S14 e S15 o consomem; **ninguém o preenche**. A demo é sexta | `s18/tasks.md:108-111`, `s14/tasks.md:148`, `s15/tasks.md:88` |
| F-02 … F-05 | A **seção 5 inteira** de S11 (o motor de números de disponibilidade) está marcada em espera | `s11/tasks.md:31-33`, tarefas 5.3–5.7 e 6.5.8–6.5.10 |
| F-12 … F-14 | **20 tarefas** de S12 estão marcadas como bloqueadas por Q-B1/Q-B2 — o ciclo de aceite inteiro | `s12/tasks.md:10, 110-145, 230-245, 305-315` |
| F-06, F-16, F-17 | "Bloco 0 — Decisões que destravam trabalho (**nada de código antes**)" de S7 | `s7/tasks.md:21-25` |
| F-08, F-09, F-18, F-34 | Mesmo bloco 0 em S8; 9 IDs de `resource_kinds` atrás do portão T-D7 | `s8/tasks.md:22-28, 104, 146` |
| F-07, F-36 | Bloco 0 de S5; a tarefa 6.1 (`RiskEntry`) e o rótulo "Legado" de `FE-243` esperam | `s5/tasks.md:20-23, 93, 117` |
| F-19, F-20, F-44 | Bloco 0 de S10 | `s10/tasks.md:26-31` |
| F-10 | S4 tarefa 1.19: *"**Não implementar as tabelas filhas antes da resposta**"* | `s4/tasks.md:86-89` |
| F-35 | Portão Q-04 em S13: tarefas 6.5–6.9 e 12 IDs esperam uma contagem | `s13/tasks.md:26-30` |
| F-45 | S13 tarefa 1.1: OPS-477 só existe se S12 responder | `s13/tasks.md:22-25` |
| F-38 | S13 tarefa 1.5: "verificar se S2 já entregou `Tracking`" — e S2 não é mais o dono | `s13/tasks.md:37-39` |
| F-37 | Se S9 começar antes de S13, a base ganha um terceiro caminho de arquivo | `s13/proposal.md:178-183` |
| F-01 | S6 tarefa 5.5 (backfill dos borderôs históricos) | `s6/tasks.md:424-428` |
| F-42 | `LoginCarousel.tsx` é a **primeira tela** da demo e está com espaço reservado no lugar da arte | `frontend/src/components/LoginCarousel.tsx:11-16` |

---

# `muda número na tela`

### F-01 — Borderôs históricos: recalcular o valor da operação de risco, ou copiar o do legado?

- **Fatia:** S6 (executa no S14)
- **Trava:** a tarefa 5.5 de S6 e o backfill do ETL. Sem resposta o histórico não é carregado.
- **Impacto:** `muda número na tela`
- **Contexto:** o **D-11** é o legado gravar o borderô com dois `save` seguidos e criar a
  operação de risco entre os dois — a operação nasce com o valor **anterior** ao recálculo.
  O ai9 corrige a causa (recálculo uma vez só, dentro de transação — `s6/design.md:82`), mas o
  histórico já gravado continua errado no banco. A tarefa está escrita em
  `openspec/changes/s6-recebiveis-bordero/tasks.md:424-428`.
- **Opções:** (a) **recalcular** no ETL — os números mudam na tela e passam a estar certos, com
  relatório de quantos mudaram e de quanto; (b) **copiar** o valor legado — a tela do ai9 bate
  com a tela de hoje e segue errada; (c) copiar e marcar as linhas divergentes com um selo
  visível, deixando a correção para depois da venda.
- **Default vigente:** (a) recalcular. O mapa recomendou porque o número certo é o objetivo e o
  relatório torna a mudança auditável.
- **Recomendação:** (a), **com o relatório entregue antes do cutover** — é o único item desta
  lista em que replicar o defeito significa gravar número errado de propósito num banco novo.

### F-02 — Correção por dias úteis: aplicar uma vez ou replicar o decaimento composto?

- **Fatia:** S11
- **Trava:** as tarefas 5.3 e 6.5.8 de S11 (`s11/tasks.md:218, 326`).
- **Impacto:** `muda número na tela`
- **Contexto:** o **D-02**: `original_value` é regravado a cada mudança de `value` e a correção
  é reaplicada **sobre o valor já corrigido**. Salvar o mesmo valor duas vezes produz números
  diferentes. O desenho do ai9 (`s11/design.md:118-134`) guarda o valor digitado em
  `original_value`, nunca sobrescreve, e a correção passa a ser função dele.
- **Opções:** (a) **corrigir** — a correção passa a ser aplicada uma vez só; (b) replicar o
  decaimento composto para bater com a tela de hoje; (c) corrigir e rodar um backfill que
  desfaz as reaplicações históricas (o ETL precisa reportar quanta base já tem valor corrigido
  mais de uma vez — DB-125).
- **Default vigente:** (a) corrigir. Foi tratado como defeito, não como convenção, porque o
  mesmo lançamento produz resultados diferentes conforme quantas vezes foi salvo.
- **Recomendação:** (a) para os lançamentos novos e **(c) só se o relatório do dry-run mostrar
  volume relevante** — desfazer decaimento histórico é caro e pode não valer o ganho.

### F-03 — Consolidação geral: passa a respeitar `is_cumulative` e `is_debit`?

- **Fatia:** S11
- **Trava:** tarefas 5.4, 5.5 e 5.7 de S11.
- **Impacto:** `muda número na tela`
- **Contexto:** hoje convivem **duas regras de soma na mesma tela** (`s11/design.md:138-147`):
  a consolidação geral soma **bruto**, ignorando cumulatividade e sinal; os nós com filhos
  aplicam as duas coisas. O **D-08**. Uma das duas está errada, e não dá para saber qual sem o
  negócio.
- **Opções:** (a) a consolidação geral passa a respeitar `is_cumulative`/`is_debit`, ficando
  igual aos nós; (b) os nós passam a somar bruto, ficando iguais à consolidação; (c) replicar
  as duas semânticas como estão e rotulá-las na tela.
- **Default vigente:** nenhum fechado — o mapa remeteu ao usuário. O desenho só fixou que
  **existe uma definição só**, seja ela qual for.
- **Recomendação:** (a) — débito que soma como crédito é o tipo de erro que o cliente descobre
  sozinho na primeira conferência.

### F-04 — "Total": o total geral usa `value` e os cards usam `virtual_value`. Qual vale?

- **Fatia:** S11
- **Trava:** tarefas 5.7 e 6.5.10 de S11.
- **Impacto:** `muda número na tela`
- **Contexto:** `s11/design.md:141-143` — *"o total geral usa `value` e cada card de padrão base
  usa `virtual_value`: mesma palavra, duas métricas"*. O usuário lê "Total" em dois lugares da
  mesma tela e recebe dois números.
- **Opções:** (a) "Total" é sempre `value` (soma bruta); (b) "Total" é sempre `virtual_value`
  (saldo acumulado); (c) manter as duas e **renomear** uma delas na interface.
- **Default vigente:** subordinada a F-03 — o proposal declara que "a mesma resposta resolve os
  dois". Registro que **não resolve**: F-03 decide *como somar*, esta decide *o que somar*.
- **Recomendação:** (c) se as duas métricas forem legítimas — renomear é barato e não muda
  número nenhum; (a) se só uma for.

### F-05 — Dias úteis passam a considerar feriados?

- **Fatia:** S11
- **Trava:** tarefas 5.3 e 6.5.8 de S11.
- **Impacto:** `muda número na tela`
- **Contexto:** hoje o cálculo é seg–sex, sem feriado (**D-03**, DC-29). Incluir feriados muda
  o resultado financeiro de **todo o histórico** e obriga a escolher o calendário — nacional,
  estadual ou bancário (`s11/design.md:130-133`).
- **Opções:** (a) manter seg–sex sem feriados nesta entrega; (b) incluir feriados nacionais;
  (c) incluir o calendário bancário (Anbima), que é o que o mercado de crédito usa.
- **Default vigente:** (a). Escolhido porque é o comportamento atual e porque escolher
  calendário sem o negócio é adivinhação.
- **Recomendação:** (a) para a demo. É a única das quatro de S11 que dá para adiar sem deixar
  duas semânticas no código.

### F-06 — T-D3 (Q-R6): tipo com pré-faturamento sem subtipo informado — recusar ou escolher o primeiro?

- **Fatia:** S7
- **Trava:** bloco 0 de S7 (`s7/tasks.md:23`) — nada de código de operação de risco antes.
- **Impacto:** `muda número na tela`
- **Contexto:** **conflito mapa × spec**. O mapa manda replicar o legado ("o primeiro subtipo",
  pela ordem de inserção); `openspec/specs/risk/spec.md` → `BE-262` manda recusar com 422
  pedindo escolha explícita. **A escolha decide em qual bucket a operação entra — liquidável ou
  pré** —, e o bucket é o que aparece somado na tela de risco.
- **Opções:** (a) **spec** — recusar com 422 e obrigar a escolha; (b) **mapa** — replicar "o
  primeiro subtipo" pela ordem de inserção; (c) recusar só nas gravações novas e replicar na
  carga histórica.
- **Default vigente:** (a) spec. Escolhido porque uma escolha arbitrária feita pelo sistema
  decide número financeiro sem ninguém saber.
- **Recomendação:** (a) para gravação nova, (c) na prática — a carga histórica não tem como
  perguntar a ninguém.

### F-07 — T-D1: quantos `risk_controls` existem sem tipo (formato pré-2022)?

- **Fatia:** S5 (executa no S14)
- **Trava:** `DB-240` e `OPS-236` em S5, o rótulo "Legado" de `FE-243`, e a decisão de descartar
  ou não as 8 colunas `limite_*`/`taxa_*`.
- **Impacto:** `muda número na tela`
- **Contexto:** `RiskControl` **mudou de forma em 2022** (`20220611152145_change_risk_control_fields`):
  deixou de ser 4 modalidades em colunas fixas e passou a ser uma linha por
  (empresa, portador, tipo). Se sobrou linha sem `risk_operation_type_id`, ela **some de todos
  os agregados** do ai9. A tarefa é uma consulta: `SELECT count(*) FROM risk_controls WHERE
  risk_operation_type_id IS NULL` (`s5/tasks.md:22`).
- **Opções:** (a) rodar a contagem no dump agora e decidir com o número; (b) assumir zero e
  descartar as 8 colunas; (c) assumir maior que zero e escrever a rake de conversão sem saber
  se ela terá o que converter.
- **Default vigente:** (a) — as colunas nascem preservadas e o descarte fica adiado para o ETL.
- **Recomendação:** (a). É uma consulta de 5 segundos que fecha 2 IDs e um rótulo de tela.

### F-08 — T-D6 (Q-R3): o `balance` da operação estruturada deveria evoluir?

- **Fatia:** S8
- **Trava:** bloco 0 de S8 (`s8/tasks.md:24`) e a tarefa 5.3.
- **Impacto:** `muda número na tela`
- **Contexto:** no legado, `original_balance = -(|valor|)` e `balance = original_balance` rodam
  em **todo** save — inclusive quando só a observação muda. E a varredura completa confirma que
  **nada no legado inteiro dá baixa nesse saldo**: não existe movimento, liquidação nem baixa de
  operação estruturada. Ou falta uma feature inteira, ou a coluna é decorativa. É a maior
  ambiguidade financeira do bloco.
- **Opções:** (a) replicar o reset e documentar a coluna como decorativa; (b) construir o
  mecanismo de baixa que falta (feature nova, contra DEC-09); (c) remover a coluna.
- **Default vigente:** (a). Escolhido porque inventar mecanismo de baixa num saldo que o cliente
  vê seria criar número novo sem regra de negócio.
- **Recomendação:** (a) — mas vale perguntar ao negócio se a operação estruturada **deveria**
  ter baixa, porque a resposta muda o roadmap, não esta entrega.

### F-09 — T-D8 (Q-R17): a remuneração é mesmo percentual flat sobre o capital, sem prazo?

- **Fatia:** S8
- **Trava:** bloco 0 de S8 (`s8/tasks.md:26`).
- **Impacto:** `muda número na tela`
- **Contexto:** é **dinheiro cobrado do cliente**. O modelo guarda `issue_date`, `due_date` e
  `agreed_rate` — o que **sugere** um pro-rata que a fórmula não faz. O legado aplica percentual
  flat sobre o capital, ignorando o prazo.
- **Opções:** (a) replicar a fórmula exatamente, com golden test — nada muda no valor cobrado;
  (b) implementar o pro-rata que os campos sugerem — muda todo o faturamento.
- **Default vigente:** (a). Escolhido porque mudar fórmula de cobrança sem confirmação do
  negócio é a pior classe de erro possível.
- **Recomendação:** (a), e levar a pergunta ao negócio **em separado** — se a intenção era
  pro-rata, o legado vem cobrando errado há anos e isso é assunto comercial, não de migração.

### F-10 — Q-02: `has_safegold_management` é carimbo histórico ou derivado do projeto?

- **Fatia:** S4 (afeta S9 por `Q-B32`)
- **Trava:** S4 tarefa 1.19 diz literalmente *"**Não implementar as tabelas filhas antes da
  resposta**"* (`s4/tasks.md:86-89`). Afeta `DB-051`, `DB-090`, `DB-130`, `BE-093`.
- **Impacto:** `muda número na tela`
- **Contexto:** o **D-30**: a marca é copiada para **6 tabelas**, mas só `companies` é atualizada
  em massa quando ela muda. Qualquer relatório que filtre por ela mente hoje. Nenhum consumidor
  foi encontrado dentro do repositório — mas pode haver consumidor externo (BI, planilha).
- **Opções:** (a) **derivar do projeto** em tempo de consulta e remover a coluna das 6 filhas —
  elimina a inconsistência e simplifica 6 tabelas, mas muda o número de quem lia o carimbo;
  (b) preservar o carimbo como foto do momento nas 6 tabelas; (c) derivar, mas manter a coluna
  antiga preenchida e congelada como `legacy_*` para conferência.
- **Default vigente:** (a) derivar, com os 4 IDs marcados como pendentes.
- **Recomendação:** (c) — o custo da coluna congelada é uma migration, e é o único caminho que
  não perde a foto caso apareça um consumidor externo.

### F-11 — T-D11 (Q-R27): a denormalização reescreve o histórico do lançamento. Bug ou foto?

- **Fatia:** S10
- **Trava:** bloco 0 de S10 (`s10/tasks.md:29`) e a tarefa 2.4.
- **Impacto:** `muda número na tela`
- **Contexto:** hoje o `after_save` do indicador roda `update_all` e reescreve `title`, `key` e
  `value_type` em **todos** os lançamentos passados. Um lançamento de 2023 passa a mentir sobre
  como o indicador se chamava na época. O **D-70**.
- **Opções:** (a) replicar o resultado (o histórico continua sendo reescrito), tirando o
  `update_all` de dentro do request; (b) parar de reescrever — o lançamento passa a guardar o
  nome que o indicador tinha quando foi lançado, e o histórico muda de aparência no dia 1;
  (c) parar de denormalizar e ler sempre do indicador (perde a foto de vez).
- **Default vigente:** (a). Escolhido porque é o comportamento observado hoje.
- **Recomendação:** (a) — a foto do momento só é útil se alguém a usa, e ninguém usa hoje; mudar
  agora criaria uma inconsistência entre o dado migrado e o dado novo.

---

# `muda comportamento observável`

### F-12 — Q-B1: o aceite de Termos volta a ser explícito?

- **Fatia:** S12
- **Trava:** SC-2 inteiro de S12 — 20 tarefas marcadas como bloqueadas (`s12/tasks.md:110-145`).
- **Impacto:** `muda comportamento observável`
- **Contexto:** o fluxo está morto por **três causas independentes** (`s12/design.md:66-80`):
  o bloqueio de acesso está inteiramente comentado (BE-343); os dois botões "ACEITAR" estão
  comentados nas views, ou seja **hoje não existe nenhuma forma de aceitar um contrato pela
  interface** (FE-332/FE-333); e a associação `has_many :contracts, through: :contract_deals,
  source: :contract_deal` aponta para uma `source` inexistente, então quem abria `/contract/:type`
  recebia 500 (BE-332).
- **Opções:** (a) reativar o ciclo completo — aceite explícito, bloqueio de acesso enquanto
  houver pendência; (b) reativar só a **ação** de aceitar, sem bloquear acesso; (c) manter tudo
  desligado e portar apenas a página de leitura.
- **Default vigente:** nenhum. É a única pergunta desta lista sem default declarado — o desenho
  está escrito, mas as tarefas estão travadas de propósito.
- **Recomendação:** (b) para a demo, (a) antes do cutover — ligar o bloqueio numa demo
  comercial arrisca travar o cliente na primeira tela.

### F-13 — Q-B1a: o que fazer com os aceites implícitos que já estão na base?

- **Fatia:** S12 (executa no S14)
- **Trava:** o conversor de `contract_deals` do ETL e o seed de contratos (`s12/tasks.md:46`).
- **Impacto:** `muda comportamento observável`
- **Contexto:** **o sistema registra hoje um aceite que ninguém deu conscientemente.** Um
  `after_create` no usuário grava os dois aceites sem interação; o seed do legado fabrica aceite
  retroativo para toda a base; os checkboxes de cadastro e de "Minha Conta" vêm **pré-marcados** e
  não são lidos por controller nenhum (`s12/design.md:78-83`, **D-64**). Migrar esses registros
  é migrar uma prova jurídica que não existe.
- **Opções:** (a) migrar os aceites como estão, marcados como `origem: implícito` — quem já está
  na base não é incomodado; (b) **não migrar** — todo mundo fica pendente no dia 1 e aceita de
  verdade; (c) migrar marcados como implícitos **e** exigir novo aceite na próxima entrada,
  preservando o registro antigo como histórico.
- **Default vigente:** **nenhum, e não deve haver.** É decisão jurídica: qualquer escolha minha
  aqui é opinião sobre validade de consentimento.
- **Recomendação:** (c), sujeito ao jurídico. É a única que não descarta registro nem finge que
  o registro vale.

### F-14 — Q-B2: qual é o conjunto mínimo de prova do aceite?

- **Fatia:** S12
- **Trava:** a migration `create_contract_deals` (`s12/tasks.md:34`) — a forma da tabela depende
  da resposta.
- **Impacto:** `muda comportamento observável`
- **Contexto:** o desenho propõe guardar usuário, versão, data/hora, **IP, user-agent e
  impressão (hash) do texto aceito**, com índice único `(user_id, contract_id)` e o exportador de
  prova em `proof_export.rb` (`s12/design.md:88-92, 104`). Isso é **requisito novo, não
  paridade** — o legado guarda só o par usuário/contrato.
- **Opções:** (a) o conjunto completo proposto (IP, user-agent, hash do texto, exportador);
  (b) só usuário + versão + data/hora, como o legado; (c) o conjunto completo **menos o IP**
  (que é dado pessoal com custo de LGPD e retenção).
- **Default vigente:** (a). Escolhido porque "aceite" sem prova do texto aceito não sustenta
  nada, mas o proposal reconhece que a definição é do usuário.
- **Recomendação:** (a) — o hash do texto é o item que realmente importa; IP e user-agent são
  baratos de guardar e caros de recuperar depois.

### F-15 — Q-B3: quem pode publicar nova versão de contrato? A matriz aprovada diz "todos".

- **Fatia:** S12
- **Trava:** a tarefa 2.6 de S12 (`s12/tasks.md:80-86`), que está escrita com um aviso explícito
  de que não altera a matriz por iniciativa própria.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `.migration-ai9/authorization-matrix.md:197` dá `contracts` como **`R` para os
  quatro papéis** — a linha inteira é leitura. Mas o recurso tem publicação: hoje **qualquer
  logado publicava um novo Termos de Uso** (ausência total de autorização, mais mass assignment
  de `id` e `version`). A matriz aprovada (DEC-18) contradiz o desenho porque a matriz foi
  derivada do menu, e publicar contrato não tem item de menu.
- **Opções:** (a) publicação = **OG + Admin**, e a linha 197 da matriz ganha uma coluna de
  escrita; (b) publicação = **só OG** (é documento jurídico do fornecedor); (c) manter a matriz
  literal — todos leem, ninguém publica pela aplicação, e a versão nova entra por seed.
- **Default vigente:** (a), proposta, aguardando confirmação. A matriz **não foi alterada**.
- **Recomendação:** (a). É a única que mantém a matriz como contrato e ainda deixa o cliente
  operar sem chamar a Livetat.

### F-16 — T-D4 (Q-R8): "Encerrar" bloqueia movimento e prorrogação?

- **Fatia:** S7
- **Trava:** bloco 0 de S7 (`s7/tasks.md:24`), tarefas 2.6 e 3.5.
- **Impacto:** `muda comportamento observável`
- **Contexto:** **conflito mapa × spec**. O mapa propõe bloquear (é o **D-94**: renovar não
  encerra a original, então as duas consomem limite ao mesmo tempo); a spec diz que a operação
  encerrada **continua na janela, continua consumindo limite e continua aceitando movimentos**,
  por DEC-01. `is_ended` é rótulo, não estado.
- **Opções:** (a) **spec** — `is_ended` continua rótulo, sem efeito colateral; (b) **mapa** —
  encerrar bloqueia movimento e prorrogação; (c) bloquear só a prorrogação (que é a que gera a
  contagem dupla do D-94) e deixar o movimento passar.
- **Default vigente:** (a) spec, por DEC-01 (replicar a convenção atual).
- **Recomendação:** (a) para esta entrega. **Registrado explicitamente:** retirar a operação
  encerrada de `operations_on` está **fora de qualquer default** — mudaria a exposição do
  histórico inteiro e precisa de assinatura sua.

### F-17 — T-D5 (Q-R10): as datas de operação existente são editáveis?

- **Fatia:** S7 e S8 (a mesma decisão nos dois módulos irmãos)
- **Trava:** bloco 0 das duas fatias (`s7/tasks.md:25`, `s8/tasks.md:27`); tarefas 8.11 de S7 e
  10.4 de S8.
- **Impacto:** `muda comportamento observável`
- **Contexto:** hoje a UI trava e **a API aceita** — em risco (`FE-260`) e em estruturadas
  (`FE-297`). Ou seja: quem usa a tela não edita, quem chama a API edita. A spec de `FE-297` já
  resolve com "não editáveis pela tela **e a API aplica a mesma regra**".
- **Opções:** (a) regra de servidor nos dois módulos — datas imutáveis depois de criadas;
  (b) liberar a edição na tela também, alinhando pelo comportamento da API; (c) liberar a edição
  com trilha de auditoria obrigatória.
- **Default vigente:** (a). Escolhido porque manter duas semânticas para a mesma pergunta em
  módulos irmãos é pior que qualquer uma das duas.
- **Recomendação:** (a) — mas confirme com quem opera: se alguém corrige data errada por API
  hoje, (c) é o que preserva o trabalho dessa pessoa.

### F-18 — T-D9 (Q-R16): a taxa de remuneração aceita valor fora de 0–100?

- **Fatia:** S8
- **Trava:** tarefas 4.2 e 11.6 de S8.
- **Impacto:** `muda comportamento observável`
- **Contexto:** hoje **250% passa na UI** e a API aceita ainda mais casas. É a taxa que
  multiplica **todo** o faturamento da operação estruturada.
- **Opções:** (a) replicar — sem limite superior nem inferior; (b) validar 0–100 e recusar o que
  estiver fora; (c) aceitar, mas exigir confirmação na tela acima de um limiar (por exemplo 100%).
- **Default vigente:** (a). Escolhido porque validar a faixa recusaria registro que o sistema
  aceita hoje, e pode haver registro legítimo fora da faixa.
- **Recomendação:** (c) — é a única que impede o erro de digitação sem recusar dado existente.

### F-19 — T-D10 (Q-R25): o título do indicador continua em CAIXA ALTA sem acento?

- **Fatia:** S10
- **Trava:** bloco 0 de S10 (`s10/tasks.md:28`) e a tarefa 2.2.
- **Impacto:** `muda comportamento observável`
- **Contexto:** **conflito mapa × spec**. O mapa manda replicar (`I18n.transliterate(title).upcase`
  em todo save); a spec de `BE-321` diz que o título aparece **como digitado**, com a comparação
  de unicidade ignorando acento e caixa. **Ponto do ETL que não tem volta:** os acentos do dado
  legado **já se perderam**, então o dado migrado chega em caixa alta de qualquer forma —
  "re-humanizar" seria adivinhação. A diferença aparece só no que for digitado depois.
- **Opções:** (a) **spec** — preservar o que foi digitado, normalizar só para comparação;
  (b) **mapa** — continuar forçando caixa alta sem acento, e a tela fica homogênea;
  (c) spec, mais uma passagem manual de "re-humanização" dos títulos existentes feita por gente.
- **Default vigente:** (a) spec.
- **Recomendação:** (a) + (c) se forem poucos indicadores — a tela mista (uns em caixa alta,
  outros não) é feia e vai ser notada na demo.

### F-20 — T-D12 (Q-R29): excluir lançamento de indicador é feature viva ou resíduo?

- **Fatia:** S10
- **Trava:** bloco 0 de S10 (`s10/tasks.md:30`) e a tarefa 5.5.
- **Impacto:** `muda comportamento observável`
- **Contexto:** **nenhuma tela do legado chama a rota**. A grade só cria e atualiza, e zerar
  grava `0`. Mas a rota existe, e o DEC-09 manda portar o que existe. No legado, o ramo de erro
  referencia um template inexistente — dá 500 dentro de um 200.
- **Opções:** (a) construir, com confirmação e autorização, e a célula voltando ao estado "não
  lançado"; (b) `dropped` com evidência de que nenhuma tela a chama; (c) construir só o endpoint,
  sem botão na tela.
- **Default vigente:** (a) construir.
- **Recomendação:** (a) — **mas responda junto com `Q-R34`** (distinguir "não lançado" de
  "lançado como zero"), que está na metade do outro agente. Sem essa distinção, excluir e zerar
  produzem exatamente a mesma tela, e a feature não tem sentido nenhum.

### F-21 — Q-16: papéis herdados de 2021 com precedência invertida. Reprocessar ou preservar?

- **Fatia:** S14
- **Trava:** nada — só muda o resultado. Mas o dry-run precisa saber se lista ou corrige.
- **Impacto:** `muda comportamento observável`
- **Contexto:** conferido na fonte. `/home/vinao/workspace/sfg/app/models/legacy/u.rb:33`:
  ```ruby
  o.role_type = i.is_staff ? ::U.MANAGER : i.is_superuser ? ::U.ADMIN : ::U.COLAB
  ```
  A marca de **equipe** tem precedência sobre a de **superusuário**: quem era `is_superuser` e
  também `is_staff` virou **Gerente**, não Admin. Isso definiu papéis de usuários que **ainda
  estão ativos desde 2021**.
- **Opções:** (a) **não reprocessar** — o dry-run **lista** os usuários nessa condição para
  revisão humana antes do cutover; (b) reprocessar e promover a Admin quem era `is_superuser`;
  (c) reprocessar e pedir a cada um desses usuários que confirme o papel.
- **Default vigente:** (a). Escolhido porque promover papel por script é escalação de privilégio
  automatizada, ainda que bem-intencionada.
- **Recomendação:** (a). A lista é barata; a promoção automática não é reversível sem susto.

### F-22 — As 4 rotas públicas de auto-cadastro da base ai9: tirar da allowlist ou gatear pela flag?

- **Fatia:** S1 (a rota) e S19 (a flag `FE-444`)
- **Trava:** nada hoje — S1 tarefa 2.1 já manda tirar. O que falta é a **decisão de tocar a
  base compartilhada**.
- **Impacto:** `muda comportamento observável`
- **Contexto:** conferido em `backend/app/controllers/api/root.rb:36,38,45,46` — `pre_register`,
  `complete_registration`, `visitor_signup` e `visitor_signup_with_link` estão na allowlist
  pública. O **D-39** (auto-cadastro público) **volta sozinho** por essa porta, que não veio do
  legado. S1 tarefa 2.1 manda retirar as 4 e a 2.2 manda desmontar os endpoints em
  `api/auth/v1/registration.rb`; S19 constrói a flag `public_create_user?` nascendo `false`.
  **A tensão:** `api/root.rb` e `registration.rb` são da **base compartilhada** (Princípio 6b —
  não refatorar a base), e outros produtos ai9 podem usar essas rotas.
- **Opções:** (a) **remover** as 4 rotas da allowlist e desmontar os endpoints, como S1 escreveu
  — resolve de vez, mas altera a base para todo mundo; (b) manter as rotas e gateá-las pela flag
  `public_create_user?` de S19, que nasce `false` — a base fica intacta e o Safegold fica
  fechado; (c) (a) no Safegold e uma flag de upstream para a base decidir depois.
- **Default vigente:** (a), escrito nas tarefas de S1 — mas a decisão de mexer na base não foi
  tomada por ninguém.
- **Recomendação:** (b). A flag já vai ser construída de qualquer jeito, e ela é a única opção
  que não deixa o Safegold dependendo de uma remoção que outro produto pode reverter.

### F-23 — Q-21: a trilha de auditoria global é visível a que papéis?

- **Fatia:** S19
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** a trilha global é um **índice de tudo que aconteceu no sistema**: quem viu o quê,
  quem alterou o quê, quando. O histórico **do próprio objeto** é outra coisa.
- **Opções:** (a) trilha global só para OG/Admin; histórico do objeto para quem vê o objeto;
  (b) trilha global para todos os papéis; (c) trilha global para OG/Admin/Gerente.
- **Default vigente:** (a), declarado pelo agente por conta própria.
- **Recomendação:** (a). É o único caso desta lista em que o default mais restritivo também é o
  mais barato de afrouxar depois.

### F-24 — Q-23: a trilha guarda o payload completo do objeto?

- **Fatia:** S19
- **Trava:** nada — só muda o resultado. Mas a forma da tabela `trackings` depende disso.
- **Impacto:** `muda comportamento observável`
- **Contexto:** default declarado: **não**. A trilha guarda evento, entidade, autor e um payload
  `jsonb` enxuto. Trilha que copia o registro inteiro vira o maior objeto do banco em três meses,
  e num sistema financeiro isso significa duplicar dado pessoal e financeiro sem política de
  retenção. S13 já registrou que o expurgo é requirement novo.
- **Opções:** (a) payload enxuto (evento, entidade, autor, campos alterados); (b) payload
  completo (a foto inteira do registro); (c) payload enxuto por padrão e completo só para um
  conjunto nomeado de entidades críticas.
- **Default vigente:** (a).
- **Recomendação:** (a). Se aparecer necessidade de foto completa, (c) é aditivo e não quebra
  nada do que for construído agora.

### F-25 — Q-22: a distância geográfica de `BE-433` tem consumidor?

- **Fatia:** S19 (depende de F-35, o portão de geolocalização de S13)
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** default declarado: portar o cálculo **condicional** (só quando `lat`/`lng`
  vierem), **sem geocoding** — que está bloqueado pelo portão Q-04 de S13 (F-35). Se F-35 vier
  zero, o cálculo nunca dispara e vira código morto no dia 1.
- **Opções:** (a) portar condicional, como está; (b) não portar até F-35 responder;
  (c) descartar com evidência.
- **Default vigente:** (a).
- **Recomendação:** (b) — amarrar a F-35 evita nascer com uma função que nunca executa.

### F-26 — Q-20: o CSP nasce em `report-only` ou bloqueando?

- **Fatia:** S18
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** a base ai9 nunca teve CSP. Ligar bloqueante numa base que nunca teve **quebra
  tela em silêncio** — recurso bloqueado não dá erro visível, só some.
- **Opções:** (a) `report-only` primeiro, com **prazo escrito** para virar bloqueio;
  (b) bloqueante desde o início; (c) `report-only` sem prazo.
- **Default vigente:** (a), declarado pelo agente.
- **Recomendação:** (a). Numa demo comercial, tela quebrada em silêncio é o pior modo de falha
  possível — e (c) é como CSP nunca vira bloqueio em lugar nenhum.

### F-27 — Q-19: `UserTheme` fica como modelo sem tela?

- **Fatia:** S17
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** default declarado: **fica o modelo STI**, mas a interface expõe só o tema global
  nesta fatia. `UserTheme` sem tela é dado órfão — a precedência (usuário → global → fábrica) é
  implementada, mas nada nunca escreve o nível de usuário.
- **Opções:** (a) modelo fica, tela não; (b) modelo fica **e** ganha tela (tema por usuário);
  (c) o modelo sai e a precedência tem dois níveis em vez de três.
- **Default vigente:** (a).
- **Recomendação:** (a) para esta entrega. O dark mode já dá ao usuário o controle que ele
  espera; tema por usuário num sistema corporativo é raro valer o suporte.

### F-28 — DS2-2: `WhatsappPage.tsx` existe e não está roteada. Ganha rota?

- **Fatia:** S2 (dependência de S1)
- **Trava:** nada hoje — mas o login por WhatsApp (DEC-14) **cai** quando a sessão da instância
  expirar, e ninguém terá como parear.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `frontend/src/app/pages/WhatsappPage.tsx` existe na base e não tem rota. É a tela
  de pareamento por QR de que `EvolutionConnection.send_message` depende via
  `PolemkInstance.first`. Decisão declarada pelo agente: **ganha rota**, gateada por papel
  administrativo (`s2/design.md:101`).
- **Opções:** (a) rota gateada por OG/Admin; (b) sem rota — o pareamento é feito por console/rake
  pela equipe da Livetat; (c) rota gateada só por OG.
- **Default vigente:** (a).
- **Recomendação:** (a). Sem ela, um canal de login do produto tem prazo de validade e nenhuma
  forma de renovação pelo cliente.

### F-29 — Google Analytics: S2 diz "não injetar", S13 diz "porto desligado". Duas fatias discordam

- **Fatia:** S2 e S13
- **Trava:** nada — mas duas fatias vão implementar coisas diferentes.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `s2/design.md:103` (DS2-4) decide **não injetar** GA, porque é sistema interno
  corporativo com dado financeiro e há a camada de analytics do próprio ai9. `s13/proposal.md`
  (Q-09) decide **portar desligado, com o snippet correto pronto**. São decisões diferentes para
  o mesmo item: "não existe" versus "existe e está desligado".
- **Opções:** (a) não injetar, e o snippet não entra no repositório (S2 vence); (b) portar
  desligado por configuração, pronto para ligar (S13 vence); (c) usar a camada de analytics do
  ai9, se ela cobrir o caso.
- **Default vigente:** **os dois ao mesmo tempo** — é o conflito.
- **Recomendação:** (a). Snippet de terceiro desligado num sistema de crédito é uma linha que
  alguém liga por engano; se a medição for necessária, (c).

### F-30 — DS2-5: o i18n não é ligado, e o runtime fica no `package.json`

- **Fatia:** S2
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** a base **tem** o runtime (`i18next`, `react-i18next`, bundles) e **não traduz
  nada**: zero componentes chamam `useTranslation`, o bundle `pt-br` tem 255 chaves de marketing
  de outro produto, e o `LanguageSwitcher` não troca idioma. DEC-09 fixou pt-BR. A decisão
  declarada é **não ligar** (`s2/design.md:104`).
- **Opções:** (a) não ligar, e registrar como flag de upstream; (b) não ligar **e remover** o
  `LanguageSwitcher` da interface, para ninguém clicar num botão que não faz nada; (c) ligar.
- **Default vigente:** (a).
- **Recomendação:** (b). Um seletor de idioma visível que não troca idioma é exatamente o tipo de
  coisa que um técnico do cliente clica na demo.

### F-31 — DS1-3: guardar o corpo dos e-mails enviados?

- **Fatia:** S1
- **Trava:** a forma da tabela `email_logs` (`DB-514`, e `DB-481` em S13).
- **Impacto:** `muda comportamento observável`
- **Contexto:** o legado guarda o corpo de **todo** e-mail (`livetat_mailer_contacts`), sem
  política de expurgo. Decisão declarada pelo agente: **metadados sem corpo**, com expurgo de
  180 dias. Guardar corpo de e-mail transacional sem expurgo é passivo de LGPD; e os 3 e-mails
  vivos do produto são de identidade (convite, código de acesso, boas-vindas) — o código de
  acesso **é a credencial**.
- **Opções:** (a) metadados sem corpo, expurgo de 180 dias; (b) corpo completo com expurgo de
  30 dias; (c) corpo completo sem expurgo, como o legado.
- **Default vigente:** (a).
- **Recomendação:** (a). Guardar o corpo de um e-mail que contém código de login é guardar a
  credencial em texto puro por outro nome.

### F-32 — DS1-4: quem assina o DKIM?

- **Fatia:** S1
- **Trava:** nada no código — é infraestrutura. Mas `OPS-501` fica em aberto.
- **Impacto:** `muda comportamento observável`
- **Contexto:** no legado a chave privada estava **versionada no repositório** (**D-85**). Ela
  precisa ser rotacionada de qualquer forma, independentemente de quem assina. Decisão declarada:
  **assinatura no provedor**, chave fora do repositório, rotação obrigatória no runbook.
- **Opções:** (a) assinatura no provedor de e-mail; (b) assinatura na aplicação, com a chave em
  variável de ambiente; (c) sem DKIM nesta entrega.
- **Default vigente:** (a).
- **Recomendação:** (a), e **rotacionar a chave atual antes da demo** — ela está num repositório
  git e o histórico não esquece.

---

# `muda escopo`

### F-33 — URGENTE: o seed de demonstração não tem fatia. Ninguém o constrói

- **Fatia:** nenhuma — é o problema
- **Trava:** a demonstração de sexta (28/08). Sem ele, as 20 fatias entregam telas vazias.
- **Impacto:** `muda escopo`
- **Contexto:** conferido nos três lados. **S18** cria os alvos vazios:
  `s18/tasks.md:108-111` — *"criar os alvos `lib/tasks/sfg_etl.rake` e `lib/tasks/demo.rake`
  **vazios e nomeados**, que S14 e o seed de demo preenchem"*. **S14** o exclui explicitamente:
  `s14/proposal.md:122` — *"O seed de demonstração (`db/seeds/demo/` + `rake demo:seed`) — é a
  fatia S-16 do mapa de bloco… **S14 o consome**"*. **S15** o consome (`s15/tasks.md:88`). O
  desenho está pronto e é bom: `.migration-ai9/demo-seed-design.md`, 262 linhas, com a cadeia
  aritmética `Project → Company → (Carrier, limite, taxa) → borderôs → movimentos → saldo`.
  **Não aparece em nenhum script de cobertura porque não tem ID de inventário** — os scripts
  contam os 1439 IDs, e o seed não é um deles. Com DEC-22 (escopo completo aprovado) e a demo
  na sexta, é o item mais urgente desta lista.
- **Opções:** (a) criar uma fatia **S20 — seed de demonstração**, com proposal/design/tasks, e
  rodá-la em paralelo desde já; (b) atribuir o seed a S18 (que já criou o `demo.rake` vazio);
  (c) atribuir a S14 (que hoje o exclui e o consome); (d) cada fatia semeia o seu próprio
  domínio dentro de `db/seeds/demo/`.
- **Default vigente:** **nenhum** — é exatamente o problema. Sem dono, o `demo.rake` chega
  sexta-feira vazio.
- **Recomendação:** (a). O seed cruza todos os domínios e tem uma exigência que nenhuma fatia
  isolada consegue cumprir — **a cadeia tem de fechar aritmeticamente entre domínios**. (d) é
  o caminho para cinco seeds que não conversam.

### F-34 — T-D7 (Q-R5): `resource_kinds` é portado ou descartado? Uma contagem decide 9 IDs

- **Fatia:** S8
- **Trava:** 9 IDs atrás do portão (`BE-307`, `BE-720`…`BE-724`, `FE-307`, `DB-286`, `DB-289`,
  `DB-294`) — `s8/tasks.md:26, 104, 146, 168-169`.
- **Impacto:** `muda escopo`
- **Contexto:** a entidade **não tem item de menu** (a tela existe só por URL direta),
  `receivable_entries.resource_kind_id` **nunca é preenchido**, e os dois flags do seed
  (`is_conta_corrente`, `is_unique`) não têm consumidor nenhum. Construir 7 IDs de CRUD pode ser
  trabalho por nada; descartar sem o número pode ser perda de dado. A medição é
  `SELECT COUNT(*) FROM receivable_entries WHERE resource_kind_id IS NOT NULL`.
- **Opções:** (a) rodar a contagem no dump e decidir com o número; (b) construir a superfície de
  qualquer forma; (c) descartar de qualquer forma.
- **Default vigente:** (a) — tabela e seed nascem, superfície bloqueada até a contagem. A
  migration `resource_kinds` entra mesmo assim, porque preservar dado é barato e perdê-lo é
  irreversível.
- **Recomendação:** (a). Se vier zero, a tarefa 13.4 já está escrita: remover a tabela numa
  tarefa explícita, **nunca por omissão**.

### F-35 — Q-04: `geolocations` tem linhas? Um `SELECT count(*)` decide 12 IDs

- **Fatia:** S13 (e F-25 em S19)
- **Trava:** as tarefas 6.5–6.9 de S13 e 12 IDs: `DB-592`, `DB-431`, `DB-480`, `OPS-481`,
  `OPS-482`, `FE-483`, `BE-435`…`BE-440` (`s13/tasks.md:26-30`).
- **Impacto:** `muda escopo`
- **Contexto:** é o maior portão de escopo por consulta única da migração. Contagem 0 → os 12
  IDs viram `dropped` com a contagem como evidência e as tarefas somem. Contagem > 0 → a família
  de geolocalização é construída.
- **Opções:** (a) rodar `SELECT count(*) FROM geolocations` no dump agora; (b) assumir que tem e
  construir; (c) assumir que não tem e descartar.
- **Default vigente:** (b) — "assumo que sim e implemento; se vier 0, 12 IDs viram `dropped`".
- **Recomendação:** (a). É a consulta de melhor relação custo-benefício da lista inteira: cinco
  segundos decidem se 12 IDs viram código ou evidência.

### F-36 — T-D2 (Q-R4): a posição diária de risco (`RiskEntry`) volta a ter tela?

- **Fatia:** S5
- **Trava:** o bloco R8 de S5 e as tarefas 1.7 e 6.1 (`s5/tasks.md:23, 40, 93`).
- **Impacto:** `muda escopo`
- **Contexto:** a evidência é forte dos dois lados. A favor de descartar: **todas** as views
  foram removidas e o menu está comentado. Contra: a tabela e as regras estão vivas, tem dado em
  produção, e os **15 campos hardcoded** dos 4 tipos originais não acompanham o
  `RiskOperationType` dinâmico de 2022 — ou seja, a tela, se voltasse, voltaria errada.
- **Opções:** (a) tabela e model portados, **sem endpoint e sem tela**; (b) portar com tela,
  remodelando os 15 campos por tipo (feature nova, contra DEC-09); (c) descartar tabela e model.
- **Default vigente:** (a).
- **Recomendação:** (a). (b) é remodelagem, não migração; (c) perde dado que não volta.

### F-37 — Ordem: o motor de anexos (S13) está declarado depois de S9, que tem 4 anexos

- **Fatia:** S13 e S9
- **Trava:** se S9 começar antes de S13, ela improvisa um segundo caminho de arquivo **hoje**.
- **Impacto:** `muda escopo`
- **Contexto:** o próprio S13 registra a ambiguidade em `s13/proposal.md:178-183`: *"**NÃO
  depende de S6/S7:** o sub-bloco B (anexos) só precisa de S1 + das entidades donas… Se S9
  (renegociações, com 4 anexos) rodar antes de S13, o motor de anexos **tem de ser antecipado** —
  senão S9 improvisa um segundo caminho e a base fica com três."* Mas a ordem de
  `migration-map.md` põe S13 depois de S6/S7, e S9 depende só de S4. Com a paralelização máxima
  do DEC-22, S9 pode estar rodando agora.
- **Opções:** (a) **antecipar o sub-bloco B de S13** (motor de anexos) para logo depois de S1,
  antes de S9; (b) S9 espera S13; (c) S9 usa ActiveStorage diretamente e S13 depois unifica.
- **Default vigente:** nenhum — está registrado como "ambiguidade de ordem no relatório", que é
  onde as coisas somem.
- **Recomendação:** (a). "Depois unificamos" (c) é como uma base ganha três caminhos de upload;
  e (b) atrasa uma fatia inteira por causa de quatro campos de arquivo.

### F-38 — Dono de `Tracking`/`trackings` (BE-430, DB-591): S2, S13 ou S19?

- **Fatia:** S2, S13 e S19
- **Trava:** S13 tarefa 1.5 (*"verificar se S2 já entregou `Tracking`"*) e a tarefa 3.9, que cria
  "o mínimo" se ninguém tiver criado.
- **Impacto:** `muda escopo`
- **Contexto:** três documentos discordam. `s13/proposal.md:165-167` diz que `Tracking` é *"de
  `misc-domain`, fatia de navegação/transversais (**S2**)"*; `s13/design.md:220` repete
  ("são de **S2**, decisão **D-P**"); `s13/proposal.md:289` diz que *"`OPS-126` e o model
  `Tracking` são de **S19**"* — o próprio documento se contradiz. E `s19/proposal.md:57-59`
  reivindica `DB-591` e `BE-430` como seus, o que **é o certo**: o `migration-map.md` criou a S19
  justamente para isso, e ela roda logo depois de S0. S2 não menciona `Tracking` em lugar nenhum.
- **Opções:** (a) **S19 é dona**, e S13 consome (a fatia existe e roda antes de S13);
  (b) S13 cria o mínimo e S19 constrói a leitura em cima; (c) S2 é dona, como dois dos três
  documentos dizem.
- **Default vigente:** ambíguo — a tarefa 3.9 de S13 é um "se ninguém fez, eu faço", que é
  exatamente o padrão que produz dois donos.
- **Recomendação:** (a), e corrigir as três referências a S2 em S13. **S13 não deve ter tarefa
  de criar `Tracking`** — só de consumir.

### F-39 — `BE-445` (`Entry`, classe base abstrata): fica em S6 ou vai para S19?

- **Fatia:** S6 (alternativa: S19)
- **Trava:** nada agora — S6 roda antes de S11 de qualquer forma.
- **Impacto:** `muda escopo`
- **Contexto:** `Entry` é a classe base de `ReceivableEntry` (S6) e `AvailabilityEntry` (S11) —
  transversal por natureza, o que a tornava candidata à fatia de transversais. Ficou em S6 pelo
  contrato **C4** (quem constrói é dono): `ReceivableEntry` nasce lá, antes de S11
  (`s6/proposal.md:261`, `s19/proposal.md:131`). O que ela carrega junto: "Diferença" e "OK"
  deixam de ser strings em pt-BR gravadas na coluna e comparadas por igualdade de texto, e viram
  `enum`.
- **Opções:** (a) fica em S6, como está; (b) vai para S19, junto dos demais transversais de
  domínio; (c) fica em S6, mas a conversão dos enums-string é tarefa de S14 (já é —
  `s14/tasks.md:70`).
- **Default vigente:** (a), por C4.
- **Recomendação:** (a). O risco real não é onde a classe mora — é S11 herdar de uma classe que
  ainda não existe. Como S6 roda antes de S11 na ordem de dependência, (a) resolve.

### F-40 — Q-11: teremos acesso ao disco do servidor legado? Sem ele os anexos não migram

- **Fatia:** S9 e S14
- **Trava:** a tarefa 5.3 de S9 (`s9/tasks.md:419-422`) e o passo de arquivos do runbook de S14.
- **Impacto:** `muda escopo`
- **Contexto:** os anexos legados vivem em `public/system/…` **no disco do servidor legado**, não
  no banco. Sem acesso a esse disco, **os registros migram e os arquivos não** — o ai9 fica com
  anexos que apontam para nada. É dependência externa, não decisão de desenho.
- **Opções:** (a) conseguir acesso (rsync/tar do diretório) antes do cutover; (b) migrar só os
  registros e marcar cada anexo como "arquivo não recuperado", com relatório; (c) não migrar
  anexo nenhum e recomeçar do zero no ai9.
- **Default vigente:** (a) parametrizado — o caminho é configurável e exercitado contra o seed de
  demo; o passo real fica no runbook de S14 marcado como **bloqueado por dependência externa**.
- **Recomendação:** (a) + (b) como rede de segurança. Anexo de renegociação é documento
  financeiro; um anexo quebrado em silêncio é pior que a ausência declarada.

### F-41 — Q-07: qual é o serviço de storage em produção? Hoje é `Disk`, inclusive em produção

- **Fatia:** S13 e S18 (consequência em S9 e S17)
- **Trava:** o runbook de cutover de S14 e a flag F-13.
- **Impacto:** `muda escopo`
- **Contexto:** conferido na base: `backend/config/storage.yml` só declara `local` (Disk) e
  `test`, e `backend/config/environments/production.rb:10` faz
  `config.active_storage.service = :local`. Ou seja, **produção grava anexo no disco do
  container**. Serve para a demo; não serve para o cutover. Anexo de renegociação é documento
  financeiro (`s9/design.md:179-183`, flag **F-4**).
- **Opções:** (a) escolher provedor agora (S3, GCS, R2…) e configurar; (b) manter `Disk` com
  **volume persistente garantido** e documentar o requisito de infraestrutura; (c) manter `Disk`
  para a demo e decidir depois da venda.
- **Default vigente:** (c) — "não escolho provedor; `Disk` serve para a demo, não para o cutover".
- **Recomendação:** (c) para sexta, com (a) ou (b) **escrito no runbook com data**. É o tipo de
  pendência que vira incidente no primeiro redeploy depois da venda.

### F-42 — A arte do carousel de login: reusar do legado, gerar depois, ou você fornece?

- **Fatia:** tematização (aparece antes de S1)
- **Trava:** nada tecnicamente — mas é a **primeira tela** que o cliente vê na sexta.
- **Impacto:** `muda escopo`
- **Contexto:** conferido em `frontend/src/components/LoginCarousel.tsx:11-16`. Os 5 slides
  padrão do ai9 (imagens geradas por IA + copy sobre "Inteligência Artificial Nativa",
  "Conectividade Global") foram substituídos por 5 slides novos em pt-BR sobre o domínio real —
  risco, recebível/borderô, limite por portador, renegociação e indicadores. Mas **os slides
  estão sem fotografia**: a sessão de migração não tinha gerador de imagem e reusar arte do
  legado não foi autorizado. O fundo hoje é a marca tokenizada (grafite + ouro Safegold) com a
  marca d'água do símbolo. Está sóbrio e correto nos dois modos, mas é espaço reservado.
  Registrado como `THEME-07` em `improvements-log.md:19`.
- **Opções:** (a) você fornece 5 imagens (ou uma) da marca; (b) gerar arte por IA numa sessão com
  a ferramenta disponível; (c) reusar a arte do legado, se houver e se for autorizado;
  (d) manter o fundo tokenizado — é uma escolha estética defensável, não um buraco.
- **Default vigente:** (d), por ausência de ferramenta.
- **Recomendação:** (d) para sexta, e (a) depois. O fundo de marca sóbrio numa tela de login de
  sistema financeiro lê como decisão de design; foto genérica de banco de imagens lê como
  template.

### F-43 — `charges` e `receipts` têm dois donos: S6 (`DB-162`/`DB-163`) e S11 (`DB-583`/`DB-584`)

- **Fatia:** S6 e S11
- **Trava:** duas migrations para as mesmas duas tabelas, se as duas fatias rodarem em paralelo.
- **Impacto:** `muda escopo`
- **Contexto:** o próprio S11 diz, em "Fronteiras", que a feature de cobranças **não** é dela:
  `s11/proposal.md:203-206` — *"A feature de cobranças e recibos. Os IDs (**BE-187, BE-188,
  BE-189, DB-162, DB-163, DB-164, DB-165, FE-179..FE-186**) pertencem ao bloco
  `receivables-renegotiations`… O que desta fatia toca 'Cobranças' é **exclusivamente** o item de
  menu nascer habilitado"*. E S6 confirma, com todos esses IDs na sua lista
  (`s6/proposal.md:128-130, 165-172, 193-194`). Mas a seção "IDs adotados no fechamento do
  Phase 2" de S11 reivindica `DB-583` (`charges`) e `DB-584` (`receipts`) com a justificativa
  *"S11 é dona das cobranças (DEC-15.1: vivas)"* (`s11/proposal.md:286`). **São as mesmas duas
  tabelas com dois IDs de inventário diferentes** — a conferência consolidada não pegou porque
  ela compara IDs, não tabelas. É o mesmo erro do C4, por outra porta.
- **Opções:** (a) **S6 é dona das duas tabelas**; S11 fica só com o item de menu habilitado, e
  `DB-583`/`DB-584` são registrados como "mesma tabela, fechado por S6"; (b) S11 é dona das
  tabelas e S6 do comportamento; (c) as duas migrations existem, uma cria e a outra altera.
- **Default vigente:** contraditório dentro do mesmo documento — é o achado.
- **Recomendação:** (a). É o que a própria seção "Fronteiras" de S11 já diz; o que falta é a
  seção "IDs adotados" concordar com ela.

### F-44 — T-D13 (Q-R26): a "Chave de Integração" do indicador tem consumidor fora do repositório?

- **Fatia:** S10
- **Trava:** a tarefa 3.4 de S10 e a decisão de tornar `indicator.key` única
  (`s10/tasks.md:31, 64`).
- **Impacto:** `muda escopo`
- **Contexto:** **dentro do repositório, nada lê `indicator.key`** — nem API, nem job, nem
  export. Mas o nome do campo ("Chave de Integração") anuncia consumidor externo, e a chave
  **não é única hoje**. Se houver BI ou planilha lendo, mudar formato ou impor unicidade quebra
  do lado de fora, em silêncio.
- **Opções:** (a) **não mexer** — a chave continua obrigatória, derivada do título, sem
  unicidade, sem mudança de formato; (b) tornar única e corrigir as duplicatas; (c) remover o
  campo.
- **Default vigente:** (a).
- **Recomendação:** (a) até você confirmar. É uma pergunta de 30 segundos para quem conhece a
  operação — e a resposta "não, ninguém usa" libera (b), que é o desenho correto.

### F-45 — OPS-477: S12 vai semear HTML de arquivo? A resposta cria ou descarta o leitor

- **Fatia:** S12 e S13
- **Trava:** a tarefa 1.1 de S13, que é a **primeira** da fatia (`s13/tasks.md:22-25`).
- **Impacto:** `muda escopo`
- **Contexto:** existe `db/seed_assets/contracts/user.html` no legado que **nenhum seed carrega**
  — documento órfão. Se S12 decidir semear o conteúdo dos contratos a partir de arquivo, S13
  precisa construir `OPS-477` (leitor de arquivo com limite de tamanho e tratamento de arquivo
  inexistente). Se não, `OPS-477` vira `dropped` por "sem consumidor". A decisão precisa sair de
  S12 e S13 está parada esperando.
- **Opções:** (a) S12 semeia a partir de arquivo → S12 escreve o leitor (e não S13);
  (b) S12 semeia com conteúdo inline no seed → `OPS-477` vira `dropped`; (c) o documento órfão é
  **registrado** e não carregado, e o conteúdo real dos contratos vem de você.
- **Default vigente:** (c) — "catálogo fechado; o documento órfão é registrado, não carregado".
- **Recomendação:** (c) + (b). Termos de Uso de um produto que vai ser vendido não deve nascer de
  um HTML órfão de 2021 que ninguém revisou.

### F-46 — Q-14: `app_symbol.png` e `app_text.png` são referenciados pelo tema e não existem

- **Fatia:** S17 e S16
- **Trava:** os 4 anexos de tema de S17 e os ícones do manifest de S16.
- **Impacto:** `muda escopo`
- **Contexto:** os dois arquivos são referenciados pelo tema do legado e **não estão no
  repositório**. S16 depende deles para o `apple-touch-icon` e o ícone `maskable` 512×512 (sem o
  qual o Android recorta o logo dentro de um círculo branco).
- **Opções:** (a) gerar os dois a partir do logo cheio, na tematização; (b) você fornece os
  arquivos originais; (c) o tema passa a referenciar só o logo cheio, e os dois campos somem.
- **Default vigente:** (a), a mesma resposta em S16 e S17.
- **Recomendação:** (b) se existirem em algum lugar (site, apresentação, papelaria); (a) se não.
  Símbolo recortado de logo cheio raramente fica bom em 48×48.

### F-47 — Flag F-14 de S12: convivem dois editores rich text na base (Slate e TipTap)

- **Fatia:** S12
- **Trava:** nada — o desenho já escolheu.
- **Impacto:** `muda escopo`
- **Contexto:** `frontend/src/components/RichTextEditor.tsx` usa **Slate** e está em uso; **TipTap**
  está declarado no `package.json` sem consumidor. S12 decidiu usar **um só** — o que já está em
  uso (Slate) — e registrar o outro como flag de upstream (`s12/design.md:23-25`).
- **Opções:** (a) usar Slate e registrar TipTap como flag de upstream; (b) usar Slate e **remover**
  TipTap do `package.json`; (c) migrar para TipTap.
- **Default vigente:** (a).
- **Recomendação:** (b) se nenhum outro produto da base usar TipTap — mas isso é decisão de
  plataforma, não do Safegold, e o Princípio 6b diz para não mexer. Então (a), com a flag escrita.

### F-48 — Q-08 (data-infra): "Atualização em andamento" vale para todas as entidades?

- **Fatia:** S13
- **Trava:** o escopo de `OPS-463` e `FE-482` (`s13/tasks.md:33-35`).
- **Impacto:** `muda escopo`
- **Contexto:** `has_ongoing_job?` só existe em `Project`, mas **7 widgets** leem `data-ongoing`
  sem que nada emita o evento — bloco morto. A pergunta define quantos canais de progresso
  existem.
- **Opções:** (a) só as entidades que **têm** job (hoje: `Project` e `AvailabilityTemplate`), e os
  7 widgets viram `dropped` com evidência; (b) construir o mecanismo para todas as entidades que
  o legado sinalizava; (c) construir para todas, incluindo as que hoje não têm job.
- **Default vigente:** (a).
- **Recomendação:** (a). É medição, não opinião: abrir o legado e listar quem tem job resolve, e
  a tarefa 1.3 de S13 já está escrita para fazer isso.

---

# `só interno`

### F-49 — DS0-1: uma trilha de auditoria só, e é a genérica. Reversível barato agora, caro depois

- **Fatia:** S0 (consumida por S4, S9, S11, S12, S19)
- **Trava:** nada — a tarefa está escrita e vai ser executada.
- **Impacto:** `só interno`
- **Contexto:** **dois mapas divergiam.** `map/auth-admin.md` §4 mandava dar o **primeiro
  produtor** à tabela `permission_audit_logs`, que **já existe na base**, tem o formato certo
  (`actor_type`/`actor_id`/`reason`/`metadata`) e **zero produtores**. `map/projects-cadastros.md`
  (OPS-086) mandava criar uma trilha genérica `AuditEvent`. O agente escolheu **uma só, a
  genérica** (`s0/design.md:89-91`), usando o formato de `permission_audit_logs` como molde;
  `permission_audit_logs` continua sem produtor e virou linha em `upstream-flags.md`.
  **Por que é caro depois:** concessão de permissão, troca de papel, impersonation, renegociação,
  risco e recebíveis vão todos gravar em `AuditEvent`. Trocar de tabela depois é migrar dado de
  auditoria, que é o dado que não se pode reescrever.
- **Opções:** (a) `AuditEvent` genérica (o default) — uma trilha para todos os domínios;
  (b) usar `permission_audit_logs` para atos administrativos e `AuditEvent` para domínio — duas
  trilhas, cada uma com semântica própria; (c) dar produtor a `permission_audit_logs` e não criar
  `AuditEvent`.
- **Default vigente:** (a). Escolhido porque duas trilhas para o mesmo tipo de ato é exatamente o
  que os contratos transversais existem para evitar, e porque só a genérica permite que
  renegociação, risco e recebíveis auditem no mesmo lugar sem uma tabela por domínio.
- **Recomendação:** (a), e é agora ou nunca — a partir da primeira gravação, mudar vira migração
  de trilha. Note que **F-38** (`Tracking` de S19) é uma **terceira** trilha: vale conferir na
  mesma resposta se `AuditEvent` e `Tracking` deveriam ser a mesma coisa.

### F-50 — DS0-4: os papéis do Safegold colidem com os `hierarchy_level` que a base já semeia

- **Fatia:** S0
- **Trava:** o seed de `user_types` (`OPS-541`, `DB-730`) e, por tabela, o de-para do ETL.
- **Impacto:** `só interno`
- **Contexto:** a decisão declarada (`s0/design.md`, DS0-4) é **acrescentar** os 4 papéis do
  Safegold sem remover os da base, porque `UserType` é peça compartilhada (Princípio 6b) e
  `visitor` é usado por `restrict_visitor_access!`. Mas conferindo
  `backend/app/models/user_type.rb:37-41`, a base semeia `OG`=1, `client`=2, `free`=4,
  `visitor`=5. O de-para do Safegold é OG→1, Admin→2, Gerente→3, Colaborador→4 —
  **`Admin` colide com `client` e `Colaborador` colide com `free`**. Dois papéis no mesmo nível
  fazem `higher_than` (`where('hierarchy_level < ?', level)`) devolver conjuntos que ninguém
  esperava, e é o contrato **C3**, o item de maior risco da migração.
- **Opções:** (a) usar níveis que não colidem (por exemplo Admin=10, Gerente=20, Colaborador=30),
  deixando espaço entre eles; (b) reaproveitar `client` como Admin e `free` como Colaborador —
  não acrescenta papel, mas muda a semântica de peça compartilhada; (c) níveis colidentes, e a
  comparação passa a considerar nível **e** nome.
- **Default vigente:** (a) implícito — o desenho diz "acrescentar", mas não fixa os números, e
  o de-para escrito no `migration-map.md` usa 1/2/3/4.
- **Recomendação:** (a), com espaçamento. Colisão de nível num contrato onde inverter o sinal
  "dá poder de OG a um Colaborador" não é lugar para economizar números.

### F-51 — `polemk_webhooks`: renomear o campo exige coordenar front e backend

- **Fatia:** S2 (a tela) e a base
- **Trava:** nada — é a pergunta se vale a pena.
- **Impacto:** `só interno`
- **Contexto:** conferido: `polemk_webhooks` não é nome interno, é **campo de contrato de API**.
  Aparece em `backend/app/controllers/api/entities/polemk_instances.rb:26`
  (`expose :polemk_webhooks`) e é consumido em `frontend/src/app/pages/WhatsappPage.tsx:117` e
  `:304-305`. Mais o model, o serviço, o seed, duas migrations e três specs. "polemk" é a marca
  de outro produto da base aparecendo dentro do Safegold.
- **Opções:** (a) não renomear — é nome de peça compartilhada da base (Princípio 6b), e o campo
  não aparece para o usuário final; (b) renomear tudo de uma vez (entity, front, model, serviço,
  seed, migrations, specs) numa mudança coordenada; (c) manter o campo e expor um alias no
  entity, para o front usar o nome novo sem quebrar a base.
- **Default vigente:** (a) implícito — nenhuma fatia tem tarefa de renomear.
- **Recomendação:** (a). O nome não vaza para nenhuma tela do Safegold; renomear contrato de API
  compartilhado por estética é o tipo de mudança que quebra outro produto na sexta-feira.

---

## Já decididas — removidas desta rodada

Cruzamento com `decisions.md`. Nenhuma destas está acima.

| Pergunta que aparecia nos changes | Onde está decidida |
| --------------------------------- | ------------------ |
| Timezone: UTC ou horário local | **DEC-06** — UTC, convertido por faixa de DST |
| Multi-tenancy: escopo por projeto, empresa ou nenhum | **DEC-07** — mantém a divisão do legado (C1) |
| Banco de produção: PostgreSQL ou MySQL | **DEC-05** — PostgreSQL, deduzido do bundle |
| Dump do banco: `pg_dump --schema-only` | **DEC-04** — seguir só com as migrations |
| Versão de produção (Ruby/Rails) | **DEC-03** — 2.6.1 / 6.0.3.2 (provisória) |
| Sinal da exposição ao risco (D-93, D-95, D-96) | **DEC-01** — replicar |
| Dinheiro em float (D-104, D-13) | **DEC-02** — replicar para bater número |
| Paginação passa a funcionar de verdade (Q-04/D-20) | **DEC-09** |
| Features novas (dashboard, série histórica, PDF, i18n) | **DEC-09** — fora; parcialmente emendada por **DEC-21** |
| Gráficos nos indicadores (`NEW-001`) | **DEC-21.1** — entra, em S15 |
| Dashboard resumo (`NEW-002`) | **DEC-21.2** — entra, em S15 |
| PWA (`NEW-003`) | **DEC-21.3** — mínimo instalável, em S16 |
| `openssl_verify_mode: 'none'` (Q-01 de S13/S18) | **DEC-21.4** — deixar como está, por enquanto |
| Login mantém o canal WhatsApp | **DEC-14** (revoga DEC-13.4) |
| Rota `/` aponta para o login | **DEC-13.3** |
| Cadastro público desligado; entrada só por convite | **DEC-18.7** — mas ver **F-22**, que é sobre as rotas **da base ai9**, não do legado |
| Q-A1 — abilities editadas à mão em produção | **DEC-19** — adiada para depois da venda |
| Q-A2 — `Membership.role` é rótulo descritivo | **DEC-18.6** |
| Q-A3 — disponibilidades e cobranças estão vivas | **DEC-15.1** — os 4 itens nascem habilitados |
| Q-A4 — quem administra `app_themes` | **DEC-18** — og/admin |
| Q-A5 — OG é papel do fornecedor | **DEC-18.1** |
| Q-A6 / Q-11 de S4 — quem gerencia membership | **DEC-18.5** — OG, Admin e Gerente, com as 3 condições de servidor |
| Q-A7 — os 4 limites `max_*` não são aplicados | **DEC-18** |
| Escopo da demo: cortar fatias? | **DEC-22** — manter tudo, as 20 fatias |
| `Legacy::execute` ainda roda? | **DEC-09/DEC-12** — assumido como não executado desde 2021 |
| `vendor/doughnut` / `vendor/dialog` | **DEC-10** — substituir pela lib do ai9 (parcialmente revogado: não havia gráfico a migrar) |

## Duplicatas — deixadas para a metade dos mapas

Estas aparecem nos proposals mas **não acrescentam nada** ao que o mapa de bloco já pergunta.
Estão em `.migration-ai9/perguntas-rodada-1-mapas.md`.

`Q-01` (S11, `default_position` existe em produção) · `Q-03` (S4, autopreenchimento por CNPJ /
ReceitaWS) · `Q-04` e `Q-05` (S3/S4, logo do portador e logos em `Medium`) · `Q-06` (S4,
`paper_trail` × `AuditEvent`) · `Q-B6`…`Q-B20` (S6, as 15 de recebíveis com default "replicar") ·
`Q-B21`…`Q-B32` (S9, as 12 de renegociação com default "preservar") · `Q-B33`, `Q-B34`, `Q-B35`
(S12, percentual de aceite, URLs públicas em português, tipos de contrato configuráveis) ·
`Q-R1`, `Q-R2`, `Q-R7`, `Q-R9`, `Q-R11`…`Q-R15`, `Q-R18`…`Q-R24`, `Q-R28`, `Q-R30`…`Q-R34`
(S5/S7/S8/S10, todas com default "replicar" e sem conflito mapa × spec) · `Q-02` de S17
(dark mode entra) · `C-07` (Kaminari sem uso: escolher um padrão de paginação).

## Divergências entre proposal e fonte que encontrei

Registradas aqui porque o proposal pode estar impreciso — e esteve.

1. **`charges`/`receipts` com dois donos.** `s11/proposal.md:203-206` diz que a feature é de S6;
   `s11/proposal.md:286` reivindica `DB-583`/`DB-584` (as mesmas tabelas) para S11. Contradição
   dentro do mesmo documento — ver **F-43**.
2. **Dono de `Tracking`.** `s13/proposal.md:165` e `s13/design.md:220` dizem **S2**;
   `s13/proposal.md:289` diz **S19**; `s19/proposal.md:57-59` reivindica como seu; S2 não
   menciona o assunto em lugar nenhum. Vale S19 — ver **F-38**.
3. **Google Analytics.** `s2/design.md:103` decide **não injetar**; `s13/proposal.md` (Q-09)
   decide **portar desligado**. Duas decisões diferentes para o mesmo item — ver **F-29**.
4. **`hierarchy_level` dos papéis.** O de-para escrito no `migration-map.md` (OG→1, Admin→2,
   Gerente→3, Colaborador→4) **colide** com o seed que a base já tem em
   `backend/app/models/user_type.rb:37-41` (`client`=2, `free`=4). O DS0-4 diz "acrescentar sem
   remover", o que torna a colisão inevitável — ver **F-50**.
5. **Colisão do espaço de nomes `Q-B*`.** O mesmo identificador significa coisas diferentes em
   dois mapas de bloco. `Q-B1` é "existe app móvel consumindo os headers?" em
   `map/auth-admin.md:658` e "o aceite volta a ser explícito?" em `map/receivables-renegotiations.md:89`.
   `Q-B2` é "login por Facebook" em S1 e "mínimo probatório do aceite" em S12. `Q-B5` é "onde
   ficam os arquivos em produção" em `map/auth-admin.md:662`, "recalcular o histórico do borderô"
   em `map/receivables-renegotiations.md:490` e "tolerância de 30 dias" em `s12/tasks.md:134`.
   **Três significados para o mesmo identificador.** Nesta rodada eu desambiguei pelo assunto;
   ao responder, use o número **F-** deste documento, não o `Q-B`.
