# Migration checkpoint

- **Phase:** 3 — migracao por camada. **EM EXECUCAO.**
- **Legacy:** `sfg` (`../sfg`, Rails 6.1 / Ruby 3.0.2, monolito + 7 engines)
- **Target:** cwd (`ai9`, branch `sfg9` — **vira repositorio proprio**, DEC-50)

- **Last completed (25/08/2026):**
  - **Phase 2 fechado** (`dbafcaa4`): 20 fatias openspec, **1717 tarefas**, 1433/1439 IDs com dono
    unico, 0 com dois donos, `openspec validate` 20 passed.
  - **Tematizacao entregue e verificada renderizando** (`48964d81` + `d068d3dc`): marca Safegold em
    light e dark, botoes de 9 variantes para 5, carousel com as 5 artes do cliente, favicon
    transparente, tooltip em portal.
  - **RODADA 1 DE PERGUNTAS FECHADA: 117 perguntas, ZERO em aberto.** 41 pelo DEC-30, 76 respondidas
    pelo usuario. **111 DECs** em `.migration-ai9/decisions.md`.
  - **91 textos de ajuda escritos** (`7142ffd5`), e a varredura formula-por-formula achou 3 defeitos
    novos: **D-121, D-122, D-123**.

- **CARGA COMPLETA FECHADA — 27/08/2026 12:06.** A cascata do ETL rodou ate o fim contra o
  dump de producao e a **reconciliacao passou sem bloqueio**. 32 tabelas, **774.035 linhas**,
  e um unico delta — os 2 `contract_deals` que a DEC-126 mandou descartar, agora reconhecidos
  pelo portao como descarte assinado.

  | tabela | origem | destino |
  | --- | ---: | ---: |
  | `risk_entries` | 642.447 | 642.447 |
  | `receivable_taxes` | 58.473 | 58.473 |
  | `receivable_entries` | 28.131 | 28.131 |
  | `availability_entries` | 23.674 | 23.674 |
  | `indicator_entries` | 6.174 | 6.174 |
  | `availability_templates` | 2.705 | 2.705 |
  | `action_text_rich_texts` | 512 | 512 |
  | `contract_deals` | 272 | **270** (DEC-126) |
  | *as outras 24* | — | delta 0 |

  Quatro defeitos consertados e medidos nesta rodada — **DEC-132** (callbacks do model
  fabricando duplicata), **DEC-133** (`attachments_count` dobrado), **DEC-134** (a
  reconciliacao passa a ler as decisoes assinadas) e a ordem invertida de `help_groups` /
  `help_categories` no `load_order.yml`. Commits `357a4cd1` e `8eef045d`.

  **`post_load!` E chamado pelo motor** — visto rodando em `indicator_entries` e
  `renegotiation_attachments` nesta carga. A anotacao antiga que dizia o contrario estava
  desatualizada e fica corrigida aqui.

- **Next action:** **Phase 4 — verificacao de paridade.** E o que sobrou de verdade: os
  **699 `migrated`** esperando conferencia contra o legado (o razao fecha em 52,4%). As 4
  tarefas de fatia em aberto sao 3 que esperam a **data da carga** (dono: usuario) e 1 que e
  o portao de fechamento reprovando de proposito.

  **Ler antes: DEC-135.** Duas fragilidades do portao ficaram REGISTRADAS e nao consertadas,
  e uma delas muda como se le um relatorio verde: **a retomada nao revisita linha recusada**,
  entao uma segunda execucao sai "Sem bloqueio" sem que nada tenha sido consertado. Foi assim
  que 32 recebiveis e 64 tarifas ficaram fora por horas com o conserto ja no codigo. **O
  portao e a reconciliacao, nao o relatorio de carga.**

  **A demonstracao e 28/08.**

### O que os 12 commits entregaram (02:11 a 02:54)
- **`c8a93627` — o motor coleta** em vez de morrer na primeira linha invalida (DEC-127).
  Acabou o "um defeito por execucao de uma hora".
- **`6c53d9d7` — as cinco unicidades viram parciais no banco E NO MODEL.** Era a armadilha
  registrada: assinar a chave nao bastava.
- **`3c40995f`** — `post_load!` provado **pelo efeito no banco**, e o volume de storage
  afirmado **com autor**.
- **`b3f879d6` + `5ab85466`** — os 32 `NaN` recalculados, e o defeito que **so apareceu ao
  consertar**: uma linha de raiz `NaN` produzia `Infinity` e o borderô era recusado.
- **`e6c1304d`** — o `NOT IN` do indice parcial fazia o `schema.rb` **alternar sozinho**.
- **`7210c92e`, `b9aee987`** — abertura de 2022 preservada; 51 lancamentos ganham conexao.
- **`91a3a4f3`** — `OPS-616` deixa de esperar a Q-07 (respondida) e **continua `blocked`
  pelo que falta MEDIR**. Separar "a pergunta foi respondida" de "a coisa foi verificada".

### Prova acidental de que o motor novo funciona
Na carga do motor, `receivable_entries` esta em **28.099 de 28.131** — faltam exatamente as
**32 linhas com `NaN`**, que ele esta **listando como recusadas em vez de morrer**. O
conserto delas ainda nao estava no codigo quando aquela carga comecou.

## ESTADO EM 27/08/2026 02:15

### Todas as decisoes pendentes foram FECHADAS
Dez, em tres rodadas: **DEC-125 a DEC-130**. Nenhuma pergunta em aberto para o usuario,
exceto marcar (ou nao) os aceites de contrato no seed — deixado para ele decidir **vendo a
tela**, porque a instrucao admitia duas leituras.

| Decisao | O que ficou |
| --- | --- |
| CEP de 7 digitos (3 projetos) | entra vazio e listado |
| Anexos (44) | mecanismo **provado**; binarios so no cutover, no servidor |
| 32 `NaN` nos derivados | **recalculados pelo motor** |
| 90 titulos vazios | indice parcial (**quinta** vez do padrao) |
| `providers` (6 grupos, 163 linhas) | indice parcial, por precedente |
| Storage | `Disk` **com afirmacao explicita** do volume |
| Abertura por modalidade de 2022 | **preservada** como no legado |
| 51 lancamentos orfaos | ganham a conexao que falta |
| Aceite dos Termos | replicado — **e nao era defeito** |
| ReceitaWS | **depois da venda**; 2 IDs `blocked` por dependencia externa |

### Duas correcoes de classificacao minhas
1. **O D-64 nao e defeito.** Apliquei norma de app de **consumo** a um sistema
   **corporativo**: o vinculo legal e o contrato entre as empresas, e ninguem se cadastra
   sozinho. **Norma sem contexto de negocio produz falso positivo — e caro, porque leva o
   usuario a decidir sobre problema que nao existe.**
2. **`value_type` nunca foi lacuna do seed**: em producao e "Dinheiro" em **529 de 529**.
   O `demo-seed-design.md` dizia "entram quando a S10 aceitar os tipos"; nao ha esse dia.

### O seed da demonstracao esta pronto (13 commits)
`121 fornecedores / 61 renegociacoes` (folga de 60 — "Nova renegociacao" volta a
funcionar), 4 indicadores de projeto (eram 0), 277 recibos, 9 de 12 projetos com indicador
de limite (eram 2). Seed rodado no `sfg9_dev`: **1.029 criados, 1.971 atualizados, 22.126
inalterados**; app conferido renderizando depois.

**Seis defeitos achados varrendo 645 renderizacoes** (43 rotas x 5 papeis x claro/escuro/
390x844) — nenhum aparecia em portao verde. O melhor deles: o `select` de fornecedor agora
**desabilita o ja usado com a razao escrita**, porque folga resolve "nao ha o que escolher"
e nao "qual opcao vai dar 422".

### ARMADILHA CONFIRMADA — `db:migrate` re-dumpa o `schema.rb`
Aconteceu de novo agora: aplicar **uma** migration de comentario mudou **15 linhas de
`check_constraint`**, porque o PostgreSQL local renderiza cast de array diferente de quem
dumpou por ultimo. **Nao reintroduziu tabela removida desta vez, mas o risco e o mesmo.**
Procedimento: aplicar, conferir `git diff db/schema.rb`, e restaurar com
`git show HEAD:<arquivo> > <arquivo>` se for so ruido — isso **nao precisa do indice**, o
que importa quando ha `index.lock` de outro agente.

## ONDE ESTA (26/08, noite) — leia isto primeiro

### Phase 4: **~470 `verified`**, de 43 no inicio do dia
Os cinco QAs de bloco fecharam. Cada linha do razao carrega o **comando que a provou** —
nenhuma foi promovida por leitura.

| Bloco | verified | commit |
| --- | ---: | --- |
| auth-users / engines / console-admin | 57 | `e6da9d46`, `0b683187` |
| projects / companies-carriers / availability | 125 | `556375ac` |
| receivables / renegotiations / contracts | 84 | `6f3f10f9` |
| risk / structured / indicators | 155 | `14d8189e` |
| data-schema / ops / misc / integrations / help / jobs / themes | 47 | `09f75934`, `8bdb09a8` |

Portoes: `rspec` **2.701 / 0** · `vitest` **491 / 0** · `zeitwerk` ok · `vite build` ok ·
**`rake sfg_etl:ledger_gate` passa nos 5 criterios (saida 0)** — era o que travava a S14 10.7.

### O DUMP CHEGOU (DEC-118 a DEC-123)
`sfg-31-may-25.sql` (134 MB, PostgreSQL **13.4**) + `sfg-31-may-25.tar` (43 MB,
`public/system/**`, 655 arquivos). Restaurado em `sfg_legacy_dump` — **56 tabelas,
782.742 linhas**.

**Regra do usuario (DEC-123):** os bancos e os arquivos **podem ficar** enquanto o
trabalho precisar. O que **nao pode e COMMITAR** dado real. Ja auditado: a demo esta
limpa (12 projetos ficticios), as fixtures do ETL sao sinteticas, `tmp/` esta ignorado, e
o unico arquivo commitado com dado de producao (`producao_28131.json`, 131 borderôs
reais) **saiu do versionamento** e ficou no disco.

**O que o dump respondeu:**
- **Q-A1 fechada:** existe **1** usuario com abilities editadas a mao (8 elevadas). As 4
  que tem efeito real foram preservadas pela DEC-108; as 4 descartadas tem **zero call
  site**. Ele nao perde nada que funcione. **A DEC-108 so existiu porque o usuario abriu o
  app e estranhou a tela** — sem ela, esse usuario perderia 3 permissoes no dia 1.
- **D-06 e D-108 morrem:** `default_position` **nao existe**; `contracts.description`
  **nao e coluna** (e ActionText, 512 linhas).
- **Papeis confirmados** (1111/998/888/799) — a inferencia do DEC-04 virou evidencia. E
  **ZERO usuarios sao Gerente**: 118 Colaborador, 11 Admin, 6 OG. O papel que 118 de 135
  pessoas usam e o Colaborador.
- **Volumetria:** `risk_entries` = 642.447 linhas, **11x** a segunda maior.

### O ensaio do ETL — o que ele provou e o que falta
`baseline` (138/138 migrations) -> `introspect` (**sem bloqueio, zero surpresas**) ->
`dry_run` (**abortou**, que e o comportamento correto) -> 10 decisoes registradas e
assinadas em `db/etl/decisions.yml`.

**Quatro dos "problemas de dado" eram erro NOSSO de desenho.** Os indices unicos de
`carriers[bank_code]`, `users[username]`, `renegotiations[project_id+integration_key]` e
`availability_templates[title]` sao restricoes que o dado real **nunca poderia
satisfazer**: o legado usa **sentinela e vazio** como "nao se aplica" (181 portadores com
`bank_code=8888`; `integration_key` = a string "Renegociação"). Viraram parciais.
**Contra o seed, que nasce limpo, nenhum teste acharia isso.**

**BLOQUEADOR RESOLVIDO:** `sfg_etl:load` morria na 3a tabela (`Slug aceita apenas
minusculas`) — 503 linhas de 782.742. Dois projetos tem `&` e `.` no identificador.
DEC-122: aceitos como estao, por paridade (`033f6e47`).

**AINDA FALTA no ETL:** **14 conversores nunca escritos**, com o recado *"o model chega na
S4/S7/S8/S11/S12"* — fatias que **ja fecharam**, e **os 15 models existem**. Sao **1.803
linhas de dado real sem como viajar**. O agente que os escrevia foi **parado por mim** (eu
li a instrucao do usuario de forma mais restritiva do que ela era) — **retomar**.

### O que foi CONSERTADO hoje
- **`b35aa5e3` — a trava de forca bruta contava login BEM-SUCEDIDO como falha.** `.last`
  sem `order` em PK **uuid** = linha aleatoria (29% a 72,5% de acerto, medido por tres
  agentes). Um escritorio atras de NAT se trancava sozinho com ~10 logins normais, e uma
  falha real podia ser reescrita como sucesso **na trilha de auditoria**. O model ganhou
  `implicit_order_column`.
- **`033f6e47`** — slug com `&` e `.`; **`99398bc7`** — dado real fora do versionamento.

### O que esta RODANDO (deixar terminar; nao despachar mais nada)
1. **Tempo real do WhatsApp.** O usuario achou usando o app: *"o socket com cable nao ta
   atualizando"*. **Causa raiz medida:** o webhook estava registrado para `https://tst`,
   `enabled: false`, `events: []`, e **nenhum dos 3 eventos era de conexao**. O usuario
   abriu **ngrok**, configurou, conectou — e o `connection_status` mudou de `unknown` para
   `connected`. **O primeiro elo funciona.** Falta o ultimo: o `subscribed` do canal
   **rejeita em silencio** se `find_for_cable(params[:instance_id])` nao resolver.
   Detalhe achado: `update_instance_connection_status` usa `update_columns`, por isso o
   `updated_at` nao muda — nao bloqueia o broadcast (que e explicito), mas mata qualquer
   coisa naquele caminho que dependa de callback.
2. **Tres defeitos visiveis na demo:** contador de portadores inflado 7x (o seed usa
   `delete_all`, que nao decrementa `counter_cache`), somente-leitura vendo botoes que o
   servidor recusa em 14 telas, e **nenhum worker Sidekiq servindo o banco de dev** (a
   tela trava na frente do cliente).

### FILA PARA DEPOIS (o usuario pediu para deixar)
1. **Retomar os 14 conversores do ETL** (agente parado por mim).
2. ~~**Folga de fornecedor no seed**~~ — **FEITO** (`104280a3`). `PROVIDER_SLACK = 5` por
   projeto; provado pela tela: 8 fornecedores oferecidos, POST 201 nos nao usados. E o
   `select` passou a **desabilitar** os ja usados, com a razao escrita (`166e450e`) —
   porque a folga resolve "nao ha o que escolher", nao "qual das opcoes da 422".
3. ~~**Implementar a decisao do `NaN`** (DEC-120)~~ — **FEITO** (`772f7495`). Coluna
   nullable, `Values.to_decimal_finite`, somas ignorando tarifa nula, e a tela sinalizando
   o bordero. **Fica aberto e e do usuario:** o proprio bordero `22424` tem `NaN` em
   quatro colunas SUAS e continua no grupo das 32 linhas de `receivable_entries` sem
   disposicao (DEC-119) — ele NAO carrega enquanto isso nao for decidido.
4. **Retomar o conserto do logout** — o WIP esta em `.migration-ai9/wip-auth-backup/`
   (5 arquivos + patch de 257 linhas). **Fazer em `git worktree` isolada.**
5. **Aceite de contrato (BE-333/335/336)** — o usuario **liberou** o seed compartilhado.
6. **Fechar o tunel ngrok** quando o teste do WhatsApp terminar (expoe o app a internet).
7. Apagar do **historico** o `producao_28131.json`, se o usuario quiser — exige reescrita
   de linha, so com a bancada vazia.

### PASSADA DE 27/08/2026 — seed da demo + varredura de telas

**645 renderizacoes** (43 rotas x 5 papeis x claro/escuro/390x844) e o seed rodado ate
convergir. Nenhum dos achados abaixo aparecia em portao verde.

**O seed:** folga de fornecedor (o 422 da fila), DEC-120 no codigo, 4 indicadores de
projeto (producao tem 527 de projeto e 2 globais; o seed tinha 5 globais e zero), 33
recibos `EST` (a classe nao era exercitada por dado nenhum), os dois indicadores da
DEC-116 saindo de **2 de 12** para **9 de 12** projetos, e o par pre/antecipacao ganhando
a transferencia de verdade (as 78 operacoes estaticas tinham saldo zero e zero
movimentos, e o razao lancava 105 "Transferencia Recebida" SOLTAS, que o sistema nao
produz).

**As telas** (6 defeitos, todos achados abrindo o app):
1. `/admin/credentials` e `/platform/whatsapp` — o menu oferece ao Admin, a API recusava
   (403 e 401). As DECs 61 e 83 dizem que o Admin entra; a API e que estava errada.
2. O 409 de escopo de projeto era pintado como FALHA vermelha em 4 das 18 telas escopadas.
3. Somente-leitura via botao de escrita em **8 telas** — a mesma familia das 14 de ontem.
4. No telefone, as faixas de aceite e de impersonacao nasciam ATRAS da barra fixa, em
   todas as telas.
5. "Instancia nao encontrado" / "Renegociacao nao encontrado(a)" — concordancia de genero
   em dois helpers de 404.
6. O `select` de fornecedor da renegociacao oferecia opcao que o servidor recusa.

**Licao repetida:** o `demo-seed-design.md` §14 tinha **quatro** linhas ja falsas em 24
horas — duas por entrega de fatia, uma por conserto, e uma **por premissa errada** ("os
indicadores de percentual entram quando a S10 aceitar os tipos": no dump, `value_type` e
"Dinheiro" em **529 de 529**). A §15 registra o que foi medido.

**Armadilha de bancada:** o `vitest` reprova por TIMEOUT (5 s) quando a maquina esta
ocupada com varios agentes — quatro arquivos diferentes falharam em tres execucoes
seguidas, e **todos passam** com `--testTimeout=25000`. Nao trate como regressao sem
repetir com o teto maior.

### DECISOES DO USUARIO AINDA EM ABERTO (nenhuma bloqueia a demo)
- **ACH-02** — os R$ 4,88 bi de abertura por modalidade de 2022 viram 0,00 na carga (o
  total continua correto; some o detalhe).
- **ACH-03** — os 51 lancamentos de producao para pares (projeto, indicador) **sem
  conexao** devem aparecer na grade?
- **Provedor de storage** (`OPS-616`) — o ETL **recusa `Disk`** em vez de confiar.
- **Anexo `#45` com 0 byte** — decidido: migra o registro sem arquivo.

---

## ERROS MEUS DE HOJE, para o proximo nao repetir

**1. Deixei sete agentes na mesma arvore, um deles editando AUTENTICACAO — e o usuario
perdeu acesso ao app.** O servidor de desenvolvimento recarrega codigo a cada requisicao;
"arquivo salvo" e "no ar" sao a mesma coisa. Todo token passou a ser rejeitado, inclusive
num login novo. **Regra: trabalho em auth nao roda em paralelo com uso do app** — ou em
`git worktree` isolada, ou com a bancada vazia.

**2. Fiz uma pergunta ao usuario com premissa falsa.** Reportei "a validacao aceita so
minusculas" sem olhar o dado; ele decidiu em cima disso. Os 2 projetos nao tinham
maiuscula nenhuma — tinham `&` e `.`. **Conferir o dado ANTES de formular a pergunta**, nao
depois.

**3. Interpretei uma instrucao de forma mais restritiva do que ela era** e parei um agente
sem necessidade. Quando a instrucao admite duas leituras e uma delas destroi trabalho,
**perguntar custa menos que refazer**.

**4. Afirmei numeros que nao medi:** disse `risk_entries` = 22x a segunda maior (**e 11x**)
e descrevi o `RiskControl` no formato pre-2022. Um QA mediu e desmentiu os dois.

## CORRECOES DE AMBIENTE (varias instrucoes minhas estavam velhas)
- **`rvm use 3.2.3` esta ERRADO.** `.ruby-version` e `Gemfile` dizem **3.4.9** e concordam;
  a instrucao antiga **quebra todo `bundle exec`**.
- **`pnpm` existe** (10.32.1) e **`vitest` roda e serve de portao**.
- **O `diff` mente so no PowerShell** (`Compare-Object`), nao no bash. O buraco real no
  runbook era outro: o passo 4 **nao trazia comando nenhum**. Corrigido.
- **`git add` por caminho explicito NAO BASTA** quando dois agentes editam o mesmo arquivo:
  e preciso `git commit -- <caminho>` **e** conferir com `git show HEAD -- <arquivo>`.
- **`.git/index.lock` fica orfao** com frequencia (o hook do graphify dispara rebuild em
  segundo plano). Confirmar que esta orfao (0 byte, nenhum git vivo, `lsof` vazio) antes de
  remover.
- **Editar arquivo pelo Windows reescreve em CRLF** — conferir com `git diff
  --ignore-cr-at-eol` e normalizar com `sed -i 's/\r$//'`.

## FIM DO DIA 26/08/2026 — leia isto antes de qualquer coisa

**Tarefas: 1918/1922.** 50 commits hoje. As **4 abertas nao sao divida**:

| Tarefa | Por que esta aberta | Dono |
| --- | --- | --- |
| S6 5.2 e 5.6 | dependem da **data da carga** (DEC-102) | **usuario** |
| S2 F.7 | depende do ETL rodar | usuario (mesma data) |
| S14 10.7 | o portao automatico de fechamento **REPROVA**: 37 linhas `pending` sem dono | **orquestrador, Phase 5** |

A 10.7 merece cuidado: o agente **construiu** `rake sfg_etl:ledger_gate` e ele reprova. Varios dos
37 IDs tem irmaos identicos ja `migrated`, o que faz "esqueceram de marcar" parecer a resposta — e
foi exatamente por isso que ele **nao marcou**. Nao marque sem conferir um a um.

### A licao que dominou o dia: **artefato envelhece, e ninguem re-confere**

Foram **seis** achados do mesmo tipo, e cinco deles eu repassei ao usuario como se fossem verdade:

1. **9 IDs "BLOQUEADO por S10"** — a S10 tinha fechado 80/80 ha tempo.
2. **`resource_kinds` esperando consulta** — o dump ja tinha respondido (DEC-110).
3. **"Q-02 SEM RESPOSTA"** do carimbo — citacao trocada; a pergunta certa fora fechada pelo DEC-30
   (DEC-112).
4. **A analise do Phase 1b sobre o `Medium`** — escrita antes de a S13 construir o motor de anexos
   (DEC-113). **Eu dei essa premissa falsa ao usuario numa pergunta**, e ele decidiu com base nela.
5. **"`pnpm` nao existe / `vitest` nao roda"** — as duas falsas. Custou o dia inteiro tratando
   `tsc --noEmit` como portao unico do front. **O `vitest` roda e SERVE DE PORTAO.**
6. **Os 4 bloqueios de S2/S3** — todos esperando algo entregue ha fatias.

**A regra:** antes de repetir uma justificativa escrita noutra fase, **re-verificar na fonte**. E
quando a justificativa embasa uma pergunta ao usuario, verificar **antes** de perguntar.

### O que o usuario achou ABRINDO O APP, que nenhum portao pegou

`Sheet` sem `SheetContent` (o detalhe da trilha nao abria) · a galeria orfa · as abilities faltando ·
remuneracoes zeradas · recibos sem candidato · limites sempre zerados · tooltip fora da tela ·
tabelas cortando valor no meio · filtros amontoados · KPI grande demais no telefone.

**Nenhum desses aparece em type-check nem em suite.** A conclusao pratica virou ferramenta:
`.migration-ai9/tools/browser.js` — pela primeira vez esta migracao consegue **provar tela**.

### DECs de hoje: **108 a 117**
108 abilities · 109 galeria · 110 `resource_kinds` · 111 textos de ajuda · 112 carimbo ·
113 `Medium` · 114 D-135 fica como esta · 115 nao existe oraculo · 116 dois indicadores de limite ·
**117 as 6 colunas de escala 6 voltam a `float`**.

### Pendencias do USUARIO (nada aqui bloqueia o Phase 4)
1. **Data da carga** — destrava S6 5.2/5.6, S2 F.7 e a paridade numerica inteira.
2. **Provedor de storage** para o cutover (`OPS-616`) — o ETL agora **recusa** `Disk` em vez de
   confiar.
3. **Filtro de periodo da trilha so tem data inicial**; o `to` existe na API e nao tem controle.
4. **Regra de permissao para `rails runner`**, se quiser que agente possa limpar `login_attempts`
   (a trava de forca bruta por IP atrapalha verificacao visual com varios agentes).

### AVISO DE FERRAMENTA — o `diff` deste shell MENTE
Ele passa por um proxy que imprimiu **"[ok] Files are identical" para dois arquivos com md5
diferentes**, e **nunca devolve codigo != 0**. O `runbook-cutover.md` manda o operador comparar o
`schema.rb` com `diff` — **usar `cmp` ou `md5sum`**, senao a virada recebe um verde falso.

### Bancada, com varios agentes na mesma arvore
- **`git add` por CAMINHO EXPLICITO.** Aconteceu **quatro** vezes hoje de um agente varrer trabalho
  de outro; eu fui um deles. `git add` seguido de `git commit` **nao e atomico** aqui.
- **A suite compartilhada nao serve de portao**: o `sfg9_test` e apagado no meio da corrida por
  `db:test:purge` alheio. **Suba banco proprio** via `DATABASE_URL` e apague ao fim.
- **Mate processo pelo PID que voce anotou.** Um `pgrep` amplo hoje quase derrubou a verificacao
  visual de outro agente.
- **Reciclar o `puma` entre ondas** — chega a 7 GB depois de algumas horas.


## Rodada de uso do app pelo usuario (26/08/2026) — 3 queixas, 3 vereditos

O usuario abriu o app e apontou tres coisas. Nenhuma era o que parecia:

1. **"Faltando todas as abilities do legado no permissoes"** — **procedente, e o erro era meu.**
   A tela mostrava 1 de 17. O corte estava registrado como "Decisao #6" do DEC-18, que e uma
   decisao **minha** ("tomei sozinho"), mas a docstring da `PermissionsPage.tsx` a citava como
   **"decisao #6 do usuario"**. E a justificativa ("nenhuma e consultada em lugar nenhum do app")
   era **falsa**: 6 das 16 tem call site real no legado. Virou a **DEC-108** — voltam as 7 com
   efeito real, checadas no servidor. Em execucao pelo agente de S1.
2. **"O ver detalhe da trilha de auditoria nao faz nada"** — **procedente. Consertado**
   (`d942f93e`). O botao chamava certo; o `Sheet` estava sem `SheetContent`. `Sheet` e o `Root`
   do Radix, que so carrega contexto — o detalhe era montado no fluxo da pagina, embaixo da
   tabela. **Licao:** `Sheet` sem `SheetContent` nao levanta erro nem quebra o type-check.
3. **"Nao sei pq ficou a tela galeria"** — **ficou por omissao.** A `AI9-016` foi `kept` no gate
   do Phase 1b, mas a propria analise dizia "manter o backend; a tela `/media` pode sair" — e
   ninguem executou a segunda metade. Virou a **DEC-109**, tela removida (`d6397561`).
   **Achado que veio junto:** o `Medium` **nao** e o motor de anexos do Safegold. Os 7 pontos de
   anexo passam por `Sfg::Attachments` + ActiveStorage, e cada model diz isso por escrito. A
   analise do Phase 1b foi escrita **antes** de a S13 construir esse motor. O backend de `Medium`
   esta hoje **sem consumidor** — decisao de remove-lo tambem e do usuario, ainda em aberto.

**O padrao das tres:** duas nasceram de artefato meu envelhecido ou mal atribuido, e nenhuma
apareceu em portao verde. **O usuario usando o app achou em minutos o que a suite nao acha.**

## S6 — fechada (137/140), e as 3 abertas sao da S8

Confirmado em 26/08/2026, a pedido do usuario. As tres nao sao divida da S6:
`1.15` (`structured_operations.receipt_id` — a tabela e da S8), `3.24` e `3.25`
(`ChargeReceiptsPage` precisa de `Remuneration`; o `PUT /charges/:id/receipts` **ja existe no
servidor**, falta a tela). Todas com dono nomeado: **S8**.

## ATENCAO — os `tasks.md` foram escritos ANTES das decisoes

> **Numeracao (conferida em 26/08/2026):** as DECs vao ate a **DEC-105**, e o numero **104 foi
> deliberadamente pulado** — um agente citou uma "DEC-104" que nunca existiu para fechar uma
> tarefa impossivel, e o numero ficou queimado de proposito. A nota esta no fim de
> `decisions.md`. **Se voce encontrar "DEC-104" em texto antigo, nao era real.**

Todo agente de implementacao **le `.migration-ai9/decisions.md` ANTES do `tasks.md` da sua fatia**,
e **a DEC vence a tarefa** onde divergirem. As que mais mudam tarefa ja escrita:

| DEC | O que muda |
| --- | ---------- |
| **DEC-30** | **Principio governante:** o legado e sistema validado — replicar regra, calculo **e dado**, com golden test. Excecoes: seguranca/autorizacao e "nao existe legado a replicar" |
| **DEC-50** | A `sfg9` vira **repositorio proprio**. Codigo "da base" **pode** ser alterado quando a regra do Safegold exigir. Nao e licenca para refatorar |
| **DEC-41** | **C3 fechado:** OG=1, Admin=2, Gerente=3, Colaborador=4 (menor = mais poder). `client`/`free`/`visitor` **removidos** |
| **DEC-59** | Trilha = **`paper_trail`** (nao `AuditEvent`, nao `permission_audit_logs`) |
| **DEC-62** | Paginacao = **Kaminari** + `PaginationPill`/`MobilePagination` copiados do `apl9` |
| **DEC-61** | Chaves de terceiro no model **`Credential` estendido** |
| **DEC-48** | **CSP nasce BLOQUEANTE** |
| **DEC-55/56** | **S17 encolhe** para "marca em fonte unica"; `UserTheme` descartado |
| **DEC-92** | **Geolocalizacao descartada** — 12 IDs, e o P-092 cai junto |
| **DEC-64** | **S20 — seed de demonstracao** e fatia nova |
| **DEC-63** | Donos: `charges`/`receipts` = S6 · `Tracking` = S19 · `Entry` = S6 · motor de anexos **antecipado** para depois de S1 |

## Pendente do usuario (nao bloqueia a onda 1)

- **4 consultas ao banco de producao** — o orquestrador **nao tem** o dump (o unico no repo e do
  Django anterior e nem tem tabelas `risk_*`). Destravam: limites pre-2022 (DEC-43),
  `resource_kinds` (DEC-82, 9 IDs), quem so tem `username` (DEC-45, possivel bloqueador de cutover)
  e quem vem com telefone travado (DEC-74). SQL pronto na secao 5 de `perguntas-rodada-1.md`.
- **Copia de `public/system/`** do servidor legado — **pre-requisito bloqueante de cutover**
  (DEC-84). Sao os anexos de renegociacao, que sao documento financeiro.
- **4 TODO nos textos de ajuda:** `contrato`, `resource_kind_id` e o `is_on_variable` das duas
  operacoes. A pergunta curta: **o que e "o variavel" e quem apura?**
- **Duas instalacoes de PWA so provaveis no aparelho** (S16, tarefas 4.2 e 4.3). O ambiente aqui e
  headless: provei pelo protocolo CDP que `getInstallabilityErrors` volta vazio e que o
  `beforeinstallprompt` dispara, mas **clicar em "Instalar" no Chrome/Edge** e **"Adicionar a Tela
  de Inicio" no Safari do iPhone** ninguem provou. Ficam desmarcadas de proposito — marcar seria
  registrar como verificado o que so foi inferido. O que se olha: janela propria, icone da
  Safegold (nao uma captura da tela), nome curto certo e a tela de login em `/`.

## Regra de bancada — NUNCA derrubar processo por padrao amplo

**26/08/2026.** Um agente usou `pkill -f 'sidekiq 8.0.10 backend'` para derrubar o proprio worker
e o padrao pegou **os quatro** que estavam de pe, de outras fatias. Foi `SIGTERM` (desligamento
gracioso, jobs em voo voltam a fila), entao foi recuperavel — e ele confessou por conta propria,
que e o comportamento certo.

**A regra:** mate **pelo PID que voce anotou ao subir o processo**, nunca por padrao de linha de
comando. Se precisar de padrao, torne-o unico ao seu processo (por exemplo `APP_NAME=sfg9s13`, que
o proprio agente usou para isolar as FILAS — bastava usar o mesmo criterio para matar).

Vale para `pkill`, `killall` e qualquer `xargs kill`. Vale em dobro nesta maquina, onde **o Redis e
compartilhado com o app `apl9`**.

### O que foi medido depois, para nao ficar mito

- **O acumulo do `apl9` NAO e nosso.** `apl9_default` tem 210 jobs, e o mais antigo e de
  **18/08 (7,7 dias)** — muito antes desta sessao. O worker daquele app simplesmente nao roda nesta
  maquina ha mais de uma semana, e o cron dele continua enfileirando (o mais recente e de 1,6 h).
  Nada disso foi causado pelo `pkill`.
- **`ai9_default` tem 16 jobs parados e nenhum worker de pe.** Sao de teste desta sessao (o mais
  antigo e um `LoggedMailDeliveryJob` de codigo de login). Em desenvolvimento o codigo volta na
  resposta, entao isso nao trava login — mas **quem for verificar job precisa subir um worker**.

### Reciclar o `puma` entre ondas de agente

**26/08/2026.** O servidor de desenvolvimento acumulou **24 GB** em 10h42 de trafego de agente —
sozinho, 74% da memoria da maquina. Com ~700 MB livres tudo passou a dar timeout, e o usuario
sentiu antes de eu perceber.

Nao e defeito do codigo migrado: e o `puma` de desenvolvimento nao ter sido feito para maratona.
Cada requisicao de verificacao, cada recarga de codigo e cada `rails runner` deixa residuo, e com
varios agentes batendo nele o dia inteiro isso cresce sem teto.

**A regra:** ao fechar uma onda de agentes, **derrube e suba o `puma`**. Custa segundos.

**Como diagnosticar quando "tudo esta lento":** `free -h` e
`ps -eo pid,pmem,rss,etime,args --sort=-rss | head`. O culpado aparece na primeira linha.
`kill` simples pode nao bastar num processo que ja esta trocando memoria com o disco — ai e `-9`.

**Duas coisas que eu mesmo errei nesse episodio, e valem como aviso:**

1. **Processo de fundo sem vigia.** Um script meu tinha laco infinito (linha de comentario vazia
   nao avancava o indice). Corrigi o bug e rodei a versao certa, mas **nao voltei para matar as
   duas execucoes travadas** — ficaram 2 horas a 100% de CPU cada. Quem manda algo para segundo
   plano e dono de conferir que morreu.
2. **Despachar sem olhar a carga.** Soltei mais um agente com `load average` ja em 5, tendo visto
   esse numero minutos antes noutro diagnostico. Antes de despachar onda nova: `uptime` e
   `free -h`.

## FILA DE DESPACHO — autorizacao permanente do usuario (26/08/2026)

Palavras dele: *"conforme os agentes forem terminando e desbloqueando as outras pode ir liberando
e executando o que der"*. **Nao e preciso perguntar antes de despachar** o que a fila abaixo
autoriza; e preciso continuar verificando que a dependencia caiu de verdade antes de soltar.

### Rodando agora
S1 (divida, 32) · S13 (divida, 12) · S14 (divida, 15 — destravada pelo dump) ·
trim+ledger (divida, 4 + aplicar o dump no ledger) · **S6** (140, caminho critico)

### Solta assim que a dependencia cair

| Espera | Dispara | Por que |
| --- | --- | --- |
| **S6** | **S7** (88) | as operacoes de risco consomem o bordero |
| **S7** | **S8** (113) | operacoes estruturadas dependem das de risco |
| **S6 + S7 + S8** | **S15** (28) | o `proposal.md` da S15 diz: depende de S5..S8 e S10 |
| **S6** | reexecutar o **seed da S20** | ha 2.668 linhas de bordero paradas no razao; hoje nenhuma lista passa de uma pagina |
| tudo fechado | **Phase 4** | **761** `migrated`, **0 `verified`** — e o portao que decide se acabou. O numero sobe a cada fatia; o que nao se move e o `verified` |

### Solto agora, porque nao depende de ninguem
- **Passada de mobile (DEC-100)** nas fatias ja fechadas.
- **Os 19 residuos do trim (`R-01` a `R-19`)**, catalogados em `removed-features.md` na secao
  "Fechamento do Phase 1b". Nenhum foi corrigido pelo QA de proposito. Donos propostos:

  | Residuo | Onde | Dono |
  | --- | --- | --- |
  | **R-01** 3 entradas de **bypass de auth** para rotas removidas | `api/root.rb:23,25,26` | **S1** (auth) — 3 linhas, com teste que prove 401 |
  | **R-02** canal `public_events` sem autorizacao + `Connection` que aceita anonimo | `app/channels/public_events_channel.rb`, `application_cable/connection.rb` | **S1** |
  | **R-03** `VisitorRoute` decidindo por `visitor`/`client`/`cliente` (DEC-41) | `frontend/src/components/VisitorRoute.tsx:31-36` | **S2** (console) — trocar por `RoleRoute roles={['og','admin']}` |
  | **R-04** endpoint de download de plano, 403 permanente | `api/v1/downloads.rb` + `api/v1/base.rb:159` | **S2** ou limpeza de orfaos |
  | **R-05** import morto que mantem `lib/analytics/` vivo | `frontend/src/lib/api/endpoints.ts:3-6` | limpeza de orfaos |
  | **R-06/R-07** fila `_transcriptions` sem job; 4 `add_filter` do SimpleCov para caminhos apagados | `config/sidekiq.yml:8`, `spec/spec_helper.rb:7,8,10,11` | **S13** / limpeza |
  | **R-08 a R-11** 4 orfaos de front (`ClientDashboardPage`, `OgRoute`, `useIsDemoMode`, `ChatCTA`+`ChatOverlay`+`useFinaleStore`) | `frontend/src/**` | limpeza de orfaos |
  | **R-12 a R-16** `config/goat-robot.json` (137 KB), `specs/{blog_vsl,n8n_lma_refactor}.md`, 7 arquivos na raiz, `README.md`, `.env.secrets.example`, `backend/.env.example` (N8N) | raiz e `config/` | limpeza — **espera a bancada esvaziar** |
  | **R-17/R-18** linhas `app_themes` e `resource_kinds` na matriz do DEC-18; conversor `ResourceKinds` no `load_order.yml` | `authorization/matrix.rb:91,98`, `db/etl/load_order.yml` | **S0 + usuario** (matriz e contrato aprovado) e **S6/S8** |
  | **R-19** politicas `owner` e `og_admin` sem consumidor | `app/lib/sfg/attachments.rb:67,75` | so registrado — nao sao armadilha |

### Espera a bancada esvaziar (conflitaria com quem edita agora)
- **Ruido de CRLF** em ~146 arquivos. Reescrever tudo com 5 agentes editando geraria conflito em
  massa — e o ganho e de legibilidade de diff, nao de comportamento. **Rodar com a bancada vazia.**
- `impeccable` desatualizado e `PRODUCT.md` ausente.

### Aberto por dependencia REAL, nao por divida
S4 (14), S9 (5), S11 (4) e S2 (4) tem tarefas presas na carga de dados, que a **DEC-102** adiou,
ou em fatia que ainda nao existe. Nao sao divida: sao espera com dono escrito.
S5 12.4 esta aberta porque nao ha oraculo — ver o registro na propria tarefa.

## Onda em curso (26/08/2026)

**Fechadas e commitadas:** S16 (`f7c7823c6`), S17 (`24e423281`), S14 (`3e66552bb`),
S4 158/172 (`180a6115f`), **S10 80/80**, **S9 119/124**.

**Ainda rodando:** S5 (limites, caminho critico — bloqueia S6 -> S7 -> S8), S11
(disponibilidades/cobrancas, 156 tarefas), S20 (seed de demonstracao).

**O `db/schema.rb` continua FORA dos commits de proposito** — ele carrega as tabelas das
tres fatias ainda em voo. Vai no commit de fechamento da onda, com as migrations delas.
Conferido estruturalmente mais de uma vez: os `check_constraint` que somem do diff so
mudam de posicao no dump.

### O numero de `rspec` que vale e o do orquestrador, sem agente ativo

Tres relatorios seguidos (S10, S9 e uma execucao minha de fundo) bateram na MESMA parede:
com 6 a 14 processos de `rspec` de agentes diferentes contra o `sfg9_test`, a suite trava
em lock ou falha de um jeito que parece dependencia de ordem e nao e. Uma execucao de
fundo minha terminou em **1836 exemplos / 8 falhas**, mas comecou antes de S9 e S10
entregarem — **numero defasado, nao usar como portao**.

Cada fatia passou isolada, em banco proprio: S10 216/0, S9 166/0, sanitizacao 261/0.
**A rodada que vale roda quando os tres ultimos fecharem.** O padrao que funcionou e o que
S20 e S10 adotaram sozinhos: `DATABASE_URL` apontando para banco proprio da fatia.

### Divida aberta que EU tenho que resolver quando S5 e S11 fecharem

**Dois componentes fazendo a mesma coisa:** `components/ProjectScopeNotice.tsx` (S9 + S10) e
`components/ProjectScopeState.tsx` (S5 + S11). Os dois nasceram no mesmo dia consumindo os
codigos 409 novos (`PROJECT_NOT_SELECTED` / `PROJECT_NONE_AVAILABLE`). A S9 apontou e fez
certo em NAO colapsar: mexeria em quatro fatias em voo. **Colapsar depois, escolhendo o
melhor dos dois, e nao o que veio primeiro.**

## Quatro armadilhas de banco que JA morderam — leia antes de tocar no schema

> A quarta foi acrescentada pela S13 em 26/08/2026 (ver o item 4). O titulo dizia "Tres".

**1. `db:migrate` contra banco desatualizado re-dumpa o banco real** e reintroduz o que o trim
removeu. Ja aconteceu (+485 linhas, revertidas). **Sempre confira `git diff db/schema.rb` depois.**

**2. Recriar tabela por migration APAGA em silencio as colunas que migrations POSTERIORES
acrescentaram.** Aconteceu em 25/08/2026 (`55aceac3`): para converter `projects` para uuid,
apaguei a tabela e removi tres versoes do `schema_migrations` para elas re-rodarem. As migrations
posteriores que acrescentavam coluna a `projects` **continuaram marcadas como executadas**, entao
as colunas delas nao voltaram. A S13 perdeu `job_state`/`job_progress` assim — e `rspec`,
`zeitwerk:check` e o `schema.rb` **passavam**, porque cada peca estava coerente sozinha.

**Como conferir depois de recriar qualquer tabela** (foi o que achou o dano): extrair todo
`add_column :tabela, :coluna` das migrations e checar contra
`ActiveRecord::Base.connection.columns(tabela)`. Coluna declarada e ausente = perdida.
Rodado em 25/08: so `users.discord_id` faltava, e ela tem migration propria de remocao — nada
alem do que a S13 ja reaplicou.

**3. `TRUNCATE ... CASCADE` NAO para na tabela nomeada.** Segue as FKs e trunca tudo que
referencia. `TRUNCATE projects CASCADE` levou `users` junto, porque `users.current_project_id`
aponta para `projects` — **apagou as contas de login**, e o seed de demo recriou so o elenco da
demo. O certo e `DELETE FROM` na ordem das dependencias.

**4. Rodar o job DE VERDADE contra o banco de TESTE da fatia envenena a suite.** (S13,
26/08/2026.) O portao "execute o job, nao so o spec" mandou subir Sidekiq e enfileirar de
verdade; usei o proprio `sfg9_s13_test` porque ele tinha o schema em dia. As linhas criadas
pelo `rails runner` ficam **commitadas**, e o `DatabaseCleaner` desta suite usa estrategia de
**transacao**: ele desfaz o que o exemplo fez, nao o que ja estava la. Resultado: 9 falhas em
`spec/jobs` que **nao eram do codigo** — os specs contavam 3 projetos e viam 6.

O sintoma engana porque parece dependencia de ordem. Como distinguir em 30 segundos:
`SELECT count(*) FROM projects` no banco da fatia **antes** de rodar a suite. Se nao for zero,
o banco tem dado de origem desconhecida.

**A regra:** banco de execucao real e banco de suite sao **bancos diferentes**. Se tiver de ser
o mesmo, limpe depois com `DELETE FROM` na ordem das dependencias (nunca `TRUNCATE ... CASCADE`
— ver o item 3) e reconfira a contagem.

## Falha intermitente de `rspec` — o culpado costuma ser VOCE MESMO (S7, 26/08/2026)

A secao seguinte diz que a causa e "dois agentes contra o mesmo `sfg9_test`". **A S7 viveu
o mesmo sintoma com banco proprio e nenhum outro agente envolvido** — e a causa merece
ficar escrita, porque custou ~50 minutos.

**O sintoma:** a suite inteira travou. Depois de 46 minutos ela terminou com **19 exemplos**
e a mensagem `Finished in 46 minutes 52 seconds`. Nada no codigo explicava isso.

**A causa:** eu tinha **duas execucoes minhas anteriores ainda vivas**, contra o meu proprio
`sfg9_s7_test`. Elas tinham sido lancadas em segundo plano, o `ps` do harness nao as mostrava
(a saida vinha vazia) e eu as dei por mortas. As tres se bloqueavam no `INSERT` de
`user_types`, que todo request spec semeia.

**Como diagnosticar em 30 segundos — e o `ps` do harness NAO serve:**

```sh
# 1. quem esta travado, e ha quanto tempo
psql -tc "select pid,state,wait_event_type,now()-query_start,left(query,60)
          from pg_stat_activity where datname='<seu_banco>'"

# 2. quais rspec existem DE VERDADE (o `ps` filtrado do harness devolveu vazio
#    com tres processos vivos; /proc nao mente)
for p in $(ls /proc | grep -E '^[0-9]+$'); do
  c=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$c" in *rspec*) echo "$p :: ${c:0:90}";; esac
done
```

`wait_event_type = Lock` com duracao em **minutos** e `application_name = rspec` em mais de
uma conexao: sao processos, nao um spec ruim.

**A regra, que estende a de bancada:** antes de lancar `rspec` em segundo plano, **liste o
que ja esta rodando por `/proc`** e mate o que for seu **pelo PID** — nunca por padrao. Na
varredura de `/proc` desta vez havia tambem um `rspec spec/lib/demo/orchestrator_spec.rb`
**de outro agente**; um `pkill -f rspec` teria levado ele junto, que e exatamente o episodio
que criou a regra de bancada.

**Consequencia pratica:** rodar a suite **inteira** de uma vez, em segundo plano, e o que
torna esse acumulo possivel. Rodar em **fatias** (`spec/models spec/services …`, depois
`spec/requests`) da numero utilizavel em minutos e falha barulhenta em vez de silenciosa.

---

## Falha intermitente de `rspec` — NAO e dependencia de ordem

Aparece como "passa isolado, falha em suite", em specs diferentes a cada vez
(`users_service`, `reference_seeds`, `impersonate_service`, `memberships`). **A causa e
ambiente, nao codigo:** dois ou mais agentes rodam `bundle exec rspec` ao mesmo tempo contra o
**mesmo `sfg9_test`**, e um limpa a tabela que o outro esta usando. A S13 viu o mesmo como
`PG::TRDeadlockDetected` entre **dois processos** no indice de `user_types`.

**Como confirmar em 10 segundos**, antes de investigar o spec:
`pgrep -af rspec` e `SELECT count(*) FROM pg_stat_activity WHERE datname = 'sfg9_test'`.
Com zero processos e zero conexoes, rode de novo: se passar, era isso.

**Regra para o orquestrador:** a rodada de portao que vale e a que roda **sem agente
trabalhando**. Falha de suite com agente ativo nao e sinal — e ruido.

## Estado do ambiente (verificado em 25/08/2026)

- **Banco `sfg9_dev`**, 54 tabelas, versao `20260824120000`. Semeado: 4 OG + **`Cliente Teste`**
  (`vinaoxd+cliente@gmail.com`, tipo `client`) para testar impersonacao.
- **Login verificado EXECUTANDO**: `POST /auth/v1/magic_login/request_code` -> 200,
  `validate_code` -> 200 com token. Em dev a resposta traz o `code`
  (`magic_login_service.rb:48`). **A rota nao tem prefixo `/api`**; a de usuarios **tem**
  (`/api/v1/users`, parametro `per_page`).
- **Impersonacao verificada nos 6 passos**, inclusive a queda de privilegio. **OG impersona outro
  OG sem trava de hierarquia** — `upstream-flags` #14, vira risco real quando o Admin existir.
- Backend `:3000` e frontend `:5173` rodando. **Sidekiq limpo** (8 crons orfaos e 916 retries).
- **Redis compartilhado com o `apl9`** — `FLUSHDB` derruba o outro app.
- **Ruido de CRLF/LF** no working tree: usar `git diff --ignore-cr-at-eol`; **nunca `git add -A`**.

## Para renderizar e conferir (o portao que vale)

Chromium headless em `~/.cache/ms-playwright/chromium-1234/chrome-linux64/chrome`; script de
captura por CDP em `<scratchpad>/shot.mjs`, e `<scratchpad>/prep2.js` faz login na propria pagina.
**`tsc --noEmit` nao e portao de UI** — passou limpo com um popover invisivel.

## Phase 1b — FECHAMENTO (tarefas 9.1 a 9.4, 26/08/2026)

As 4 ultimas tarefas de `openspec/changes/trim-ai9-safegold/tasks.md` estao fechadas: o change
esta **74/74**. O detalhe inteiro esta em `.migration-ai9/removed-features.md`, secao
"Fechamento do Phase 1b".

- **9.1** — o commit de **cada** bloco entrou no `removed-features.md` (ate aqui so havia o
  *baseline* de cada bloco, e o `git revert` prometido nao tinha alvo escrito).
- **9.2** — QA pelo avesso, **1.122 arquivos** varridos, 29 familias de termo (uma por feature
  removida), procurando: rota de back e de front, codigo morto, tabela orfa, item de menu,
  traducao orfa, job agendado, politica de autorizacao sem dono e entrada em `attachments.yml`.
  Portoes: `tsc` **0 erros**, `eslint` **0 findings**, `rspec` **1887/2** (baseline do trim era
  1362/6, e as 2 falhas de hoje sao de fatia).
  **Limpo:** nenhuma tabela de feature removida no `schema.rb`, nenhuma traducao orfa, nenhum
  job agendado orfao, nenhuma entrada orfa em `attachments.yml`, nenhuma rota de front orfa
  (menu e roteador sao o MESMO registro).
  **19 residuos NOVOS** catalogados como **R-01 a R-19**, com arquivo e linha. Os tres que
  importam agora, porque sao da natureza do `public_brand`:
  - **R-01** `api/root.rb:23,25,26` — **3 entradas de bypass de autenticacao** apontando para
    rotas que sairam com AI9-005/006 (`messages-upsert`, `send-message`, `messages-update`).
    Hoje 404, mas quem redeclarar o `resource` amanha o faz nascer **sem auth**.
  - **R-02** `app/channels/public_events_channel.rb` — canal orfao, `stream_from "public_events"`
    **sem autorizacao nenhuma**, e `ApplicationCable::Connection` **nao** chama
    `reject_unauthorized_connection`: conexao anonima entra.
  - **R-03** `frontend/src/components/VisitorRoute.tsx:31-36` — guard **VIVO** nas 3 rotas
    `/admin/chat/*` decidindo por `visitor`/`client`/`cliente`, tipos que o **DEC-41 removeu**.
    O backend do DEC-41 foi limpo; o front nao. `cliente` e palavra corrente do dominio.
  - **Nenhum deles foi corrigido aqui** — sao mudanca de comportamento de autenticacao e de
    autorizacao, e o QA registra; quem corrige e a fatia dona, com teste.
- **9.3** — o razao **nao tem nenhum `to-remove`**. Os 35 IDs `AI9-*`: **28 `removed`**
  (AI9-005 e `removed (parcial)`, DEC-14) e **7 `kept`** (AI9-007 e `kept (adaptado)`, mais 008,
  016, 030, 033, 034, 035). O gate do trim diz "8 mantidas, 27 removidas" porque conta o AI9-005
  entre as mantidas — **e o mesmo conjunto**: 28 + 7 = 27 + 8 = 35.
- **9.4** — este checkpoint. **O grafo NAO foi regravado nesta passagem**: quem regrava e o hook
  do `graphify` no commit, e este agente **nao commita**. `graphify-out/` esta em 26/08/2026 e
  ja indexa o `analise-dump-producao.md`.

## O dump de producao foi APLICADO ao razao (26/08/2026)

`.migration-ai9/analise-dump-producao.md` respondeu 8 consultas em 26/08 e **nada disso estava
no razao**. Agora esta, e tem secao propria no topo de `parity-ledger.md`.

| Medicao | Efeito |
| ------- | ------ |
| `resource_kinds` 0 linhas, 0 de 28.131 borderos | **10 IDs** `pending` -> **`dropped`** (a analise diz "9" e lista 10) · fecha **P-041** |
| `geolocations` 0 linhas | os 12 IDs **ja eram** `dropped` (DEC-92, por leitura de codigo) — ganharam a **medicao**, o estado nao mudou |
| `risk_entries` 642.447 linhas | confirma a **DEC-57**: R8 nao e descartada, tabela e model sem tela |
| `risk_controls` 600, todos pre-2022 | fecha **P-018** — e no sentido oposto: **nao existe linha no formato novo** |
| **0 de 135** usuarios so com `username` | fecha **P-049**. **DEIXA DE SER BLOQUEADOR DE CUTOVER** (runbook 1.3 e passo 5) |
| `remunerations` nao existe em producao | fecha **P-026 por falta de objeto**. Os 15 IDs **continuam `pending`**, com a pergunta escrita |
| `availability_templates.default_position` nao existe | responde o **D-06** e vira o defeito **D-126** |
| `public/system/` reconciliado 100% | **DEC-84 destravada** — runbook 1.1, 1.2 e 1.3 saem de BLOQUEADO |

**Razao antes -> depois (so o que ESTE agente moveu):** `dropped` **123 -> 133**, `pending`
**535 -> 525**, FECHADOS **158 -> 168** de 1.479. **Nada foi marcado `verified`** — e veredito
do Phase 4, que nao rodou.

> **O `migrated` mudou por outra mao, nao por esta.** No comeco desta passagem o razao tinha
> **752 `migrated` / 29 `blocked`**; ao fim, **761 / 20**. Os 9 que se moveram sao
> `OPS-465`, `466`, `468`, `469`, `470`, `471`, `473`, `485` e `608`, escritos por outro agente
> **enquanto este rodava**. Fica registrado para que ninguem atribua o delta ao fechamento do
> trim nem ao dump.

### Colisao de identificador desfeita: o defeito do dump e **D-126**, nao D-125

`analise-dump-producao.md` batizou o defeito de `default_position` como "D-125 (novo)", mas o
**D-125 ja existia** desde o inventario — e o `ux_kit19` parcialmente vivo. O defeito do dump
passou a **D-126** em `legacy-defects.md`, `improvements-log.md`, `s11/tasks.md`,
`parity-ledger.md` e na propria analise. **O D-125 do `ux_kit19` nao foi tocado.** E o D-126
nao e "defeito novo": e a **resposta do D-06**, que estava em "perguntar" exatamente sobre esta
coluna desde o inventario.

### O que o dump NAO resolveu, e continua aberto — dono: **usuario**

**24 migrations do repositorio do legado nunca rodaram em producao** (114 aplicadas x 138 no
repositorio; a ultima subiu em 25/05/2022). Sao **7 familias inteiras de recurso**: operacoes de
risco tipadas (S7), limites tipados (S5), operacoes estruturadas (S8), cobrancas (S11),
remuneracoes e recibos (S7/S8) e garantias de projeto (S4). O **DEC-30** ("o legado e validado,
replique") **vale para o que rodou**; para codigo de 2022 nunca executado nao ha comportamento
validado e o golden test **nao tem oraculo**. Nao tira nada de escopo (DEC-22 de pe) — muda o
criterio de verificacao, e a escolha e do usuario.

### Portao vermelho encontrado de passagem: `Sfg::Etl::TargetBaseline` (dono S14)

`spec/lib/sfg/etl/engine_spec.rb:319` acusa `user_types` como tabela sem migration — e ela
**tem** migration. `migration_tables` faz replay do DSL com `rescue StandardError; next`
(`app/lib/sfg/etl/target_baseline.rb:48-56`); a migration usa `enable_extension` e
`reversible ... execute <<-SQL`, o replay levanta e **o arquivo inteiro e descartado calado**.
Alem do falso positivo: **migration que o replay nao consiga ler faz o portao deixar de
enxergar as tabelas dela**.

## Phase 1b — resultado final (fechado em 25/08/2026)

| Bloco | Commit | O que saiu |
| ----- | ------ | ---------- |
| 1 | `b6e65303` + `774d44b0` | Folhas visuais + landing (11 features), -23.196 |
| 2 | `dbcca3c9` | Analytics, -18.844 |
| 3 | `e06be801` | Conteudo + WhatsApp parcial, -19.353 · **resolve a colisao `Project`** |
| 4 | `f2de14af` | Comercial, -20.985 · **desacopla a nav de `plan_features`** |
| 5 | `779473df` | Meta/Instagram, -3.036 |
| 6 | `586f3b65` | Leads/omnichannel, -17.311 |
| 7 | `96517a1a` | Operations/embeddings, -7.463 · **o rspec zerou** |
| 8 | `483ee19a` | Chatbot **adaptado** para assistente interno |

**Total: ~-110 mil linhas.** Portoes finais, todos conferidos pelo orquestrador:
`rspec` **440 exemplos / 0 falhas** · `tsc --noEmit` **0 erros** · `zeitwerk:check`
**All is good!** · `vitest` 5 falhas de auth, pre-existentes · eslint limpo.

### Correcoes fora do trim que entraram no caminho
- **`ab40bf83` + `e938ab42`** — o **login estava quebrado na base**: 4 metodos chamados e
  inexistentes, `request_code` respondia 500. Cherry-pick de `38475439` (pika9) + o
  `mask_destination` que eu esqueci de portar junto. **Aplicado tambem na `main`**
  (`aaa05101` + `f464169d`, locais, sem push).
- **Bloco 8** — o `DEFAULT_MODEL` do provider Anthropic era `claude-3-5-sonnet-20241022`,
  **modelo que nao existe mais**: o assistente errava 100% dos turnos. Agora `claude-opus-5`.
- **Isolamento de conversa** — a pergunta do usuario ("cada usuario tera sua conversa
  separada?") revelou que `/chat/*` estava **publico**, a `ChatSession` estava **sem dono**
  e a busca era `ChatSession.find(params[:session_id])`. Corrigido: auth obrigatoria,
  `chat_sessions.user_id`, escopo por dono, chave do Redis com o usuario.
- **Banco de dev recriado do schema** — tinha **73 tabelas contra 52** no `schema.rb`
  (19 tabelas de features removidas ainda fisicamente la). Agora 54 = 52 + 2 internas.

### A licao que se repetiu tres vezes e virou regra
**Portao verde prova que o codigo CARREGA, nao que ele FUNCIONA.** Login, `mask_destination`
e o modelo do Anthropic passaram por `ruby -c`, `zeitwerk:check` e `rspec` inteiros e
estavam quebrados — dois deles porque os specs **estubavam** exatamente o que faltava.
**Caminho critico se verifica EXECUTANDO.**

### Armadilha registrada para o Phase 3
**Nunca rodar `db:migrate` sem conferir `git diff db/schema.rb` depois.** Os blocos
editaram o `schema.rb` a mao (sem migration de `drop`, por decisao de design), entao um
`db:migrate` contra um banco desatualizado **re-dumpa o banco real** e reintroduz o que
foi removido. Aconteceu no Bloco 8: +485 linhas, revertidas.

## Phase 1 — resultado final (fechada em 24/08/2026)
- **1439 IDs** inventariados -> **1444 requirements** openspec em **19 capabilities**
- **Cobertura verificada por script:** 1433/1439. Os 6 restantes sao `FE-640..645`
  (site publico), legitimamente `dropped` por decisao do usuario no Phase 0.
- `openspec validate --specs`: **19 passed, 0 failed**
- **125 defeitos** do legado catalogados, cada um com veredito
- Licao registrada: cada um dos 5 agentes reportou "cobertura conferida, zero faltando"
  e cada um estava certo **dentro da sua fatia** — a checagem no artefato consolidado
  revelou **31 IDs orfaos nas fronteiras**. Verificacao se faz no consolidado, nunca na
  soma dos relatorios.

## Phase 1b — andamento (remocao ai9-only)
- Gate decidido: **8 mantidas, 27 removidas** (DEC-13 + DEC-14)
- [x] **Bloco 1** — 11 features (AI9-021..029, 031, 032). 167 arquivos apagados,
      **-23.196 linhas**, type-check **305 -> 0** (reconferido pelo orquestrador).
      Rota `/` aponta para `LoginPage`. Commits `b6e65303` e `774d44b0`.
- [x] **Bloco 2** — Analytics (011, 012, 013 -> 010). Commit `dbcca3c9`
- [x] **Bloco 3** — Conteudo (019, 020, 015, 017, 004 -> 005 **parcial**, DEC-14). Commit `e06be801`
- [x] **Bloco 4** — Comercial (003, 001, 018 -> refatorar Sidebar -> 002). Commit `f2de14af`
- [x] **Bloco 5** — Meta (009), `779473df` · [x] **Bloco 6** — Leads (006), `586f3b65` ·
      [x] **Bloco 7** — Operations (014), `96517a1a`
- [x] **Bloco 8** — Desacoplar o chatbot (007 fica, adaptado). Commit `483ee19a`
- [x] **9.1 a 9.4 — fechamento do Phase 1b (26/08/2026).** Ver a secao "Phase 1b — fechamento"
      mais abaixo e o `removed-features.md`

### Limitacoes de ambiente — **REVOGADAS em 26/08/2026. AS DUAS ERAM FALSAS.**

> **Nao repita o que esta riscado abaixo.** O bloco ficou 2 dias no checkpoint e **todo
> agente o leu como verdade**, inclusive eu — que ainda repassei "nao instale biblioteca,
> o `pnpm` nao roda" a um agente. O usuario questionou (*"pq nao usa a lib do masonry ao
> inves de fazer no braco?"*), eu fui medir, e as duas afirmacoes caem:
>
> | Afirmacao antiga | Medido em 26/08/2026 |
> | --- | --- |
> | ~~`pnpm` nao existe neste shell~~ | **existe**: `/home/vinao/.local/bin/pnpm`, versao **10.32.1**. `npm` 10.9.7 tambem. Ha `package-lock.json` E `pnpm-lock.yaml`, os dois no repo |
> | ~~`vitest` nao roda~~ | **roda**: `npx vitest run` em `src/features/dashboard` deu **12 passed** em 2,3 s. O agente da S15 ja tinha rodado **433/433 em 48 arquivos** e ninguem atualizou esta nota |
>
> **Consequencias praticas:** (1) **da para instalar dependencia** — o argumento "nao tem
> como" nunca foi verdadeiro; (2) **a suite do front SERVE de portao**, e tratar
> `tsc --noEmit` como portao unico foi decisao baseada em premissa falsa. O type-check
> continua sendo o portao **minimo**, nao o teto.
>
> Cuidado real que sobra: **ha dois lockfiles**. Instalar com o gerenciador errado gera
> divergencia — conferir qual esta atualizado antes de mexer.

- `three` / `@react-three/*` seguem no `package.json` com zero imports. **Removivel agora**
  que o `pnpm` esta disponivel; segue como pendencia, mas o bloqueio declarado nao existia.

### ATENCAO — a skill mudou durante esta execucao (24/08/2026)
O gate de selecao de features ai9-only **era Phase 2b** e passou a ser **Phase 1b**,
com duas consequencias praticas que mudam o plano:

1. **Roda ANTES do mapa**, nao depois. Motivo declarado na skill: enxugar a base ai9
   primeiro evita tematizar, padronizar e ajustar telas/backend que serao deletados,
   e o repo comeca **menor**. O Phase 2 passa a mapear contra o que **sobrou**.
2. **A remocao e executada na hora**, dentro do proprio 1b — nao vira tarefa adiada
   para o Phase 3 como na versao anterior da skill. Cada feature marcada para remover
   e removida completamente (front + back + dados, das folhas para a raiz, protegendo
   infra compartilhada, sem referencia solta, build verde, **apagando as migrations
   que ficaram desnecessarias** e limpando o schema — nunca uma migration de "drop").
3. Estado no ledger: `kept` / `to-remove` / `removed`. Um item `to-remove` que ainda
   nao foi removido **bloqueia o fechamento da migracao**, igual a uma feature nao
   migrada.

Referencias atualizadas: `SKILL.md:249`, `references/workflow.md:61`,
`references/ai9-feature-selection.md`.

Obs. menor: `references/tools-setup.md` ganhou uma 5a ferramenta (**website-cloner**,
para clone 1:1 de site publico). **Nao se aplica a esta migracao** — o usuario decidiu
no Phase 0 nao migrar o site publico (ver `project-options.md`).
- **Updated commit:** (ver git log)

## Worklist — Phase 1 (inventário; marque ao concluir)
- [x] graphify no legado — `../sfg/graphify-out/graph.json` pronto: 3480 nos, 4336 edges,
      461 communities (rodado com `--code-only` + `cluster-only --no-label`, sem chave LLM;
      comunidades ficam sem nome, o que nao afeta o cruzamento no-a-no do QA).
      GAP CONHECIDO: `app/definitions/SFG/{theme,metadata}.rb` produziram zero nos
      (case-sensitivity no path UNC) e foram lidos a mao -> `brand-and-metadata.md`.
- [x] inv: auth & users (engines auth19/auth_omni19/auth_ux19, users, impersonation, permissions, memberships) — 125 IDs (BE49/FE49/DB18/OPS9)
- [x] inv: companies, providers, carriers, segments — 94 IDs (BE30/FE30/DB25/OPS9)
- [x] inv: projects (guarantees, connections, templates de projeto) — 103 IDs (BE40/FE40/DB13/OPS10); faixa esgotou, overflow em 700–799
- [x] inv: availability (entries, templates, global templates) — 86 IDs (BE30/FE30/DB16/OPS10)
- [x] inv: receivables (entries, kinds, taxes, wallets, charges, receipts) — 108 IDs (BE40/FE40/DB18/OPS10)
- [x] inv: renegotiations (attachments, installments, payments) — 98 IDs (BE40/FE40/DB10/OPS8)
- [x] inv: risk (controls, entries, movements, operations + tipos/subtipos/extensões) - 121 IDs (BE50/FE50/DB11/OPS10)
- [x] inv: structured operations (+ types, taxes) — 88 IDs (BE30/FE30/DB18/OPS10)
- [x] inv: indicators (indicator, indicator_entry, connections) — 62 IDs (BE31/FE22/DB4/OPS5)
- [x] inv: contracts (contract, contract_deal, aceite) — 40 IDs (BE20/FE13/DB2/OPS5)
- [x] inv: help / FAQ (categories, groups, items) - 21 IDs (BE15/FE3/DB3)
- [x] inv: themes (app_theme, global_theme, user_theme) - 20 IDs (BE15/FE3/DB1/OPS1)
- [x] inv: console admin (console, console_observers, admin_messages, dash) - 100 IDs (BE40/FE40/DB10/OPS10)
- [x] inv: misc dominio (tracking, geolocation, picture, helpers, controllers base) - 52 IDs
- [x] inv: jobs & cron (lib/*_job.rb, CRONFacade, delayed_job, whenever) - 61 IDs junto com integracoes (OPS40/BE11/FE5/DB5)
- [x] inv: integrações (ReceitaWS/CNPJ, geocoder, DKIM/mailer19, wicked_pdf, paperclip/storage) - ver jobs-integrations.md
- [x] inv: engines (auth19, auth_ux19, feedback19, mailer19 vivas; navkit e auth_omni19 mortas) - 97 IDs
- [x] inv: data/schema (139 migrations: 104 app + 35 engines; 67 tabelas) - 70 IDs (DB60/OPS10)
- [x] inv: OPS (Procfile, daemons, resources.yml, locales, config flags) - 40 IDs + 20 chaves de config + 9 feature flags
- [x] inv: site público `/landing` — **DROPPED por decisão do usuário** (registrado em inventory/public-site.md + ledger)
- [x] QA: consolidado — 1439 IDs (BE530/FE464/DB245/OPS200) em feature-inventory.md;
      graph-crosscheck.md: 524 arquivos do grafo 100% classificados (443 ja cobertos,
      47 lacunas fechadas com 12 IDs novos, 34 fora de escopo com motivo);
      parity-ledger.md semeado com 1433 pending + 6 dropped
- [ ] capturar inventário como specs openspec

## Decisoes do usuario
Ver `.migration-ai9/decisions.md` (DEC-01..DEC-12, 24/08/2026 — todas as perguntas encerradas). Elas tem precedencia
sobre os vereditos propostos em `legacy-defects.md`.

## Fases  (ordem corrigida conforme a skill atualizada)
- [x] Phase 0 — setup, calibração & tooling
- [x] Phase 1 — inventário → specs  (1439 IDs -> 1444 requirements, 19 capabilities,
      cobertura 1433/1439 verificada, validate 19/0)
- [x] **Phase 1b — seleção de features ai9-only + REMOÇÃO IMEDIATA** — 8 blocos, 27
      features removidas, ~-110 mil linhas, nenhum `to-remove` no ledger
- [x] Phase 2 — mapa + 20 openspec changes, 1717 tarefas, 1433 IDs com dono unico
- [x] **Phase 3 — FECHADA (26/08/2026).** 20 fatias, **1918/1922 tarefas (99,8%)**. As 4
      abertas nao sao divida da fase: 3 esperam a **data da carga** (dono: usuario) e 1 e o
      portao de fechamento que **reprova de proposito** (dono: orquestrador, Phase 5)
- [ ] Phase 4 — verificação de paridade
- [ ] Phase 5 — close-out
