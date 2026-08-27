# Decisoes do usuario (Vinicius) — registradas em 24/08/2026

Estas decisoes tem precedencia sobre os vereditos que eu havia proposto no
`legacy-defects.md`. Onde houver conflito, **vale esta pagina**.

## DEC-01 — Sinal da exposicao ao risco (D-93): **replicar exatamente como esta hoje**
O ai9 reproduz a convencao de sinal atual do legado, invertida ou nao, incluindo o
`* -1` de `limite_utilizado_on`. O painel de risco vai mostrar os mesmos numeros que
mostra hoje.

- **Como isso vira trabalho:** o slice de risco ganha testes de caracterizacao que
  **travam** os numeros atuais (entrada -> saida identica ao legado). O comportamento
  fica documentado e testado, entao inverter a convencao depois vira uma mudanca
  deliberada de uma linha, com o teste apontando exatamente o que muda.
- **Consequencia registrada:** a melhoria proposta foi **recusada conscientemente**.
  Anotada no `improvements-log.md` como melhoria declinada, nao como algo esquecido.
- D-95 e D-96 (colunas "Liquidavel"/"Pre" mostrando o utilizado; "vencido" como flag
  manual) seguem a **mesma politica**: replicar.
- **Nao alcancado por esta decisao:** D-94 (renovar nao encerra a original, entao as
  duas consomem limite ao mesmo tempo) e D-100 (vazamento de escopo de projeto).
  D-94 nao e convencao de sinal, e contagem dupla de exposicao; D-100 e seguranca.
  Ambos continuam `corrigir` — se voce quiser replicar tambem esses, e so dizer.

## DEC-02 — Dinheiro em float (D-104): **replicar o float para bater numero**
O ai9 reproduz a aritmetica em ponto flutuante do legado (`remunerations.value`,
`receipts.fee`, ~30 taxas de `receivable_entries`), de forma que os totais fiquem
**identicos** aos do legado na verificacao de paridade.

- **Como isso vira trabalho:** o tipo de coluna no ai9 pode ser `decimal`, mas a
  **sequencia de operacoes** replica a do legado (mesma ordem, mesmos casts, mesmos
  pontos de arredondamento), com testes golden comparando contra valores extraidos
  do legado. Replicar o resultado nao obriga a replicar o tipo de armazenamento.
- **Consequencia registrada:** o defeito de precisao vai junto para a base nova.
  Anotado no `improvements-log.md` como melhoria declinada.
- D-13 (dinheiro em float, arredondamento inconsistente) fica subordinado a esta
  decisao.
- **Nao alcancado:** D-10 (o servidor grava `Infinity`/`NaN` porque a guarda de
  divisao por zero so existe no cliente). Isso nao e precisao, e registro corrompido.
  Continua `corrigir`.

## DEC-03 — Versao de producao (D-113): **Ruby 2.6.1 / Rails 6.0.3.2**
Os defeitos ligados a APIs removidas no Rails 6.1 **funcionam em producao** e, portanto,
sao **comportamento a preservar**, nao bugs a corrigir:

| Defeito | Reclassificacao |
| ------- | --------------- |
| D-43 (`update_info` com `update_attributes`) | **funciona em producao** -> feature real, migrar o comportamento. As **rotas mortas** do mesmo item (`users#detail`, `show_info`, `pub/permissions/index`, redirect para `/u/console/profile`) continuam mortas |
| D-61 (edicao de tema) | o caminho do `update_attributes` **funciona**; o segundo caminho (POST para rota inexistente com a chave malformada `app_theme[app_theme[login_bkg_style]]`) **continua quebrado** |
| D-91 (edicao de observer) | `update_attributes` **funciona**; `@total_count` ignorando filtros e o `companyId`/`observerId` trocado **continuam defeitos** |

> ### ATENCAO — evidencia encontrada DEPOIS da sua resposta
> Levantei isto ao conferir os Gemfiles e preciso te devolver antes de fechar o mapa:
> - `Gemfile.prod` foi tocado pela ultima vez em **maio/2021** (`3deef40`), enquanto
>   `Gemfile.linux` e de **julho/2021** (`0ee7a3f`);
> - as migrations do legado vao ate **agosto/2022**, e `SFG::Metadata::DESCRIPTION`
>   anuncia **versao 1.11.1, 06/04/2023**.
>
> Ou seja: o desenvolvimento seguiu por ~2 anos **depois** da ultima alteracao do
> `Gemfile.prod`. E possivel que ele esteja defasado e que a producao real rode algo
> mais novo. **Se o deploy nao usa `Gemfile.prod`, o DEC-03 se inverte** e os tres
> defeitos acima voltam a ser bugs.
>
> Como confirmar em 1 minuto no servidor de producao:
> `ruby -v` e `bundle exec rails -v` (ou `cat Gemfile.lock | head -20`).
> Ate voce confirmar, sigo com o DEC-03 como voce respondeu, marcando esses tres
> vereditos como **provisorios**.
>
> Nota tranquilizadora sobre um susto que tive no caminho: `Gemfile.prod` **nao lista
> paperclip**, o que a primeira vista sugeriria que producao nao tem anexos. Falso
> alarme — `kt-paperclip` entra transitivamente por `engines/auth19/livetat_auth19.gemspec:20`.
> Producao tem anexos normalmente.
>
> Outra diferenca real entre os dois Gemfiles, que **muda o inventario de jobs**:
> producao usa um **fork do `delayed_job`** (`github.com/livetat/delayed_job`, branch
> `rails-6-compatibility`), nao a gem publica. O comportamento de retry/falha pode
> divergir do que foi inventariado.

## DEC-04 — Dumps do banco: **seguir so com as migrations**
Sem `pg_dump --schema-only` e sem a tabela `livetat_auth_role_types`. O esquema alvo
sai das **139 migrations** (67 tabelas).

- **Risco aceito e documentado:** ja existem **duas provas** de que o banco real tem
  estrutura fora das migrations — `default_position` (D-06) e `contracts.description`
  (D-108) sao usadas em codigo e **nenhuma migration as cria**. Podem existir outras.
- **Como eu reduzo o risco sem o dump:**
  1. O script de migracao de dados comeca com uma **etapa de introspecao** que le o
     schema real no momento da execucao e **compara** com o esperado, abortando com
     relatorio se achar coluna/indice/tabela desconhecidos. Assim a surpresa aparece
     no dry-run, nao no cutover.
  2. Os RoleTypes viram **configuracao explicita** no ai9 (seed versionado), em vez de
     dependerem de linhas soltas no banco legado. Vou propor a hierarquia a partir do
     que o codigo referencia (`Visitor`, `Manager`/`Gerente`, `Admin`, `og`) e te
     mostrar para aprovar antes de implementar.
- Se em algum momento o dump ficar disponivel, e so me avisar: a etapa de introspecao
  ja deixa o caminho pronto para consumir.

## O que estas decisoes NAO cobrem
Todas as quatro tratam de **numeros, versao e acesso**. Nenhuma delas autoriza
replicar os defeitos de **seguranca**, que seguem com veredito `corrigir`:
D-01, D-16, D-23, D-28, D-29, D-34, D-38, D-39, D-40, D-56, D-57, D-60, D-67, D-68,
D-69, D-76, D-82, D-85, D-88, D-100, D-109, D-110, D-111.
Se voce quiser mudar a politica em algum desses, me diga qual — mas o padrao e nao
levar IDOR, escalacao de privilegio, SSRF nem senha em texto puro para a base nova.

---

# Perguntas do QA x decisoes ja tomadas

O QA consolidou o inventario **em paralelo** com a rodada de perguntas, entao a lista
de "top perguntas" dele inclui itens **ja respondidos**. Reconciliacao:

| Pergunta do QA | Situacao |
| -------------- | -------- |
| 2) paridade byte a byte no float financeiro ou corrigir? | **RESPONDIDA — DEC-02**: replicar o float para bater numero |
| 9) ambiente de referencia: producao (2.6.1/6.0.3.2) ou dev (3.0.2/6.1.4)? | **RESPONDIDA — DEC-03**: producao. Provisoria ate o `ruby -v` no servidor |
| 1) rodar `pg_dump --schema-only` + `count(*)` na producao? | **RESPONDIDA — DEC-04**: seguir so com as migrations. **Mas a segunda metade continua aberta** — ver Q-05 abaixo |

## Perguntas ainda ABERTAS para o usuario (fila do Phase 2)

| # | Pergunta | Por que trava | Impacto se eu decidir sozinho |
| - | -------- | ------------- | ----------------------------- |
| Q-01 | **Timezone**: o banco esta em horario de Brasilia (`default_timezone = :local`), com DST ate 2019. Converto tudo para UTC na migracao, ou mantenho local? | O ai9/Rails 8 assume UTC. Sem decisao, **todo o historico de datas desloca** — e por quantidades diferentes conforme a epoca | Alto: muda vencimento de parcela e data de operacao no historico inteiro. Nao e coberto pelo DEC-02 (aquele era so sobre float) |
| Q-02 | **Matriz de autorizacao**: hoje **nenhum** endpoint valida papel — o gate existe so na view. Qual e a matriz correta (quem pode o que) no ai9? | Vou fechar os buracos de seguranca de qualquer forma (nao coberto pelas decisoes), mas preciso saber **qual e a regra certa**, nao so que a atual e insegura | Alto: se eu inferir errado, usuario legitimo perde acesso no dia 1. Posso propor uma matriz a partir do `create_console_menu` (D-118) para voce aprovar |
| Q-03 | **Multi-tenancy**: o escopo e projeto, empresa, ou nenhum? Hoje `carriers`/`carrier_groups`/`segments`/`sub_segments` sao globais e `companies`/`providers` sao por projeto | Define o desenho de dados e de autorizacao do ai9 inteiro (o ai9 base **nao tem** multi-tenancy — e lacuna a construir) | Alto: e decisao de arquitetura, dificil de reverter depois |
| Q-04 | **Paginacao**: hoje `limit`/`offset` sao descartados em quase todo `search` (D-20) — a UI de paginacao e decorativa. Passa a funcionar de verdade? | E melhoria de performance obrigatoria pelo skill, mas **muda o que o usuario ve** (hoje a tela traz tudo) | Medio: recomendo ligar. So confirmo porque muda comportamento visivel |
| Q-05 | **Qual e o banco de producao**: PostgreSQL (`database.centos.yml`) ou **MySQL** (`database.linux.yml`)? | O ETL e escrito diferente para cada um. O DEC-04 dispensou o dump, mas **nao respondeu qual e o SGBD** | Alto: escrever o ETL para o banco errado desperdica o trabalho todo |
| Q-06 | **Escopo de features novas**: dashboard (D-87), serie historica de indicadores (D-66) e geracao de PDF (D-84) **nao existem** no legado. Entram no escopo ou ficam fora? | Nao ha paridade a preservar — e produto novo. Sem definicao, ou eu invento, ou o cliente sente falta | Alto: e a diferenca entre migrar e construir |
| Q-07 | `resource_kinds`, indicadores e `RiskEntry` (D-99) devem ser portados ou descartados? Varios tem tela removida mas tabela com dado | Sao 125 IDs marcados `candidato a dropped` pelo QA | Medio: descarto o que tiver evidencia forte e te listo antes |
| Q-08 | O pipeline `Legacy::execute` (ETL Django, D-105) ainda roda hoje? | Se ainda roda, nao e codigo morto | Baixo: assumo que nao roda (foi executado em 2021) salvo aviso |
| Q-09 | `vendor/doughnut` (unico grafico do produto) e `vendor/dialog` sao proprietarios, sem equivalente npm. Substituo pela lib do ai9 ou porto 1:1? | Afeta a aparencia de um componente visivel | Baixo: recomendo substituir pela lib do ai9 (padronizacao) e mostro antes |

Nenhuma delas bloqueia o inicio do Phase 2 — o mapa comeca pelas areas ja decididas.
Q-01, Q-03 e Q-05 travam o **slice de dados**; Q-02 trava o slice de **auth**.

---

# Segunda rodada — DEC-05..DEC-09 (24/08/2026)

## DEC-05 — Banco de producao (Q-05): **PostgreSQL** — RESOLVIDO SEM PRODUCAO
O usuario apontou que `database.centos.yml` / `database.linux.yml` sao **arquivos de
exemplo**; o real e `config/database.yml`, que esta no `.gitignore:11` e nao existe no
repositorio.

**Deducao conclusiva pelo bundle** (nao depende de acesso a producao):
- `Gemfile.prod:24`, `Gemfile.linux:27` e `Gemfile.osx:27` declaram **`gem 'pg'`**
- **nenhum** dos tres declara `mysql2`
- nenhuma gemspec de engine traz adapter de banco

Sem `mysql2` no bundle o app **nao consegue** abrir conexao MySQL — Rails levanta erro
de adapter ausente no boot. Logo: **PostgreSQL**. As 2 linhas `adapter: mysql2` do
`database.linux.yml` sao residuo morto de exemplo (contra 10 linhas `postgresql` nos
demais). O ETL do Phase 3 e escrito para PostgreSQL.

## DEC-06 — Timezone (Q-01): **converter para UTC** (o usuario delegou: "uso o que for melhor")
O banco legado grava em horario de Brasilia (`config/application.rb:28-29`,
`default_timezone = :local`); o ai9/Rails 8 assume UTC.

**Decisao tecnica minha, pelos motivos:** UTC e o padrao do ai9 e de todo o resto da
base; manter `:local` obrigaria a configurar o Rails 8 contra a convencao dele e
contaminaria todo sistema futuro que leia esse banco; e ambiguidade de horario de
verao (a mesma hora local acontece duas vezes na virada) so tem solucao correta em UTC.

**Como executo com seguranca** (D-102 e o risco):
1. O offset **nao e constante**: BRT/BRST com DST ate 2019 (fim em 2019-02-16), depois
   UTC-3 fixo. Entao **nao existe** um `AT TIME ZONE` unico que sirva.
2. O ETL converte **por faixa de data**, usando a tabela de transicoes de DST do
   `America/Sao_Paulo` (via tz database, nao offset hardcoded).
3. As horas ambiguas da virada de DST (que ocorreram duas vezes) sao resolvidas pela
   regra padrao do tz database e **listadas no relatorio do dry-run** para conferencia.
4. Teste de reconciliacao: para uma amostra de cada ano de 2016 a 2026, o instante
   convertido tem que reexibir a **mesma hora local** que o legado mostra hoje na tela.

Se preferir o outro caminho (manter tudo em horario local), e reverter esta decisao —
me avise antes do Phase 3.

## DEC-07 — Multi-tenancy (Q-03): pergunta reformulada e **respondida via DEC-09**
Minha pergunta original foi mal feita. Em portugues claro era: **quando um usuario faz
login, quais registros ele enxerga?**

No legado a resposta e mista:
- `companies`, `providers` e todo o dado financeiro sao **por projeto** — o "projeto
  corrente" (`default_project`) filtra quase tudo;
- `carriers`, `carrier_groups`, `segments` e `sub_segments` sao **globais**, isto e,
  compartilhados por todos os projetos.

Eu perguntava se o ai9 devia manter essa divisao ou unificar. **O DEC-09 responde:
manter exatamente a divisao do legado** (so as coisas do legado). Entao:
- escopo por projeto para empresas, fornecedores, disponibilidades, recebiveis,
  renegociacoes, operacoes de risco e estruturadas;
- catalogos globais para portadores, grupos, segmentos e subsegmentos.

A diferenca em relacao ao legado e **so** de execucao: no ai9 o projeto corrente vem
do JWT e e validado contra membership a cada request (corrige D-28), em vez de vir de
cookie do cliente. O **modelo** de escopo e identico; o que muda e quem manda nele.

## DEC-08 — Matriz de autorizacao (Q-02): **sim, eu proponho e voce aprova**
Hoje **nenhum** endpoint valida papel — o gate existe so nas views ERB (D-23, D-34).
Vou derivar a matriz proposta de `create_console_menu`
(`app/helpers/application_helper.rb:100-172`), que e a especificacao de fato da
navegacao (D-118), cruzando com as 17 abilities do `AbilityFactory` (D-35).

Entrega: `.migration-ai9/authorization-matrix.md` — uma linha por recurso, colunas por
papel (`og`, `admin`, `manager`, demais) e a marcacao de `user_is_readonly`, com a
evidencia de onde cada regra foi lida. **Voce aprova antes de eu implementar.**

## DEC-09 — Escopo (Q-06): **so o que existe no legado**
Nada de feature nova. Consequencias diretas:
- **Dashboard (D-87): fora.** O `dash` do legado e so um redirecionador por papel — e
  isso, e so isso, que vai para o ai9. Nao construo widgets nem agregacoes.
- **Serie historica / variacao de indicadores (D-66): fora.** Nao existe no legado.
- **Geracao de PDF (D-84): fora.** A gem `wicked_pdf` esta declarada mas **zero PDFs**
  sao gerados hoje. Nao invento a feature; a gem simplesmente nao e portada.
- **i18n (D-115): fora.** 0 de 717 views usam `t()`; o ai9 nasce em pt-BR fixo, como o
  legado. (Registrado que ligar i18n depois custa mais caro.)
- Isto tambem responde a Q-07 pelo lado do escopo: o que **existe** no legado e
  portado, mesmo com tela removida, desde que a tabela tenha dado; o que e
  comprovadamente morto vai para `dropped` **com evidencia**, item a item.

### O que o DEC-09 NAO desliga
"So as coisas do legado" fala de **features**, nao de defeitos. Continuam valendo:
- as **correcoes de seguranca** (23 defeitos, ver fim da primeira rodada);
- fazer a **paginacao funcionar de verdade** (Q-04 / D-20) — nao e feature nova, e a
  mesma feature funcionando: hoje a UI de paginacao existe e e decorativa porque o
  `limit`/`offset` e descartado. Mandato de performance do skill. **Muda o que a tela
  faz** (hoje traz tudo), entao fica aqui registrado; se preferir manter o
  comportamento atual, me avise;
- eliminar **polling** (D-86), substituindo por Action Cable — mandato do skill;
- os itens ja decididos em DEC-01/DEC-02 seguem como estao (replicar).

## Situacao das perguntas
| # | Status |
| - | ------ |
| Q-01 timezone | **fechada** — DEC-06 (UTC) |
| Q-02 autorizacao | **fechada** — DEC-08 (proponho e voce aprova) |
| Q-03 multi-tenancy | **fechada** — DEC-07 (mantem o modelo do legado) |
| Q-04 paginacao | **decidida por mim** — passa a funcionar (mandato do skill); reversivel se voce discordar |
| Q-05 banco | **fechada** — DEC-05 (PostgreSQL, deduzido do bundle) |
| Q-06 features novas | **fechada** — DEC-09 (so o legado) |
| Q-07 portar x descartar | **parcial** — criterio definido no DEC-09; a lista item a item vem no Phase 2 |
| Q-08 `Legacy::execute` ainda roda? | **aberta, baixo risco** — assumo que nao (executado em 2021) |
| Q-09 `doughnut`/`dialog` | **aberta, baixo risco** — proponho substituir pela lib do ai9 e te mostro |
| D-113 versao de producao | **provisoria** — confirmar com `ruby -v` no servidor |

---

# Terceira rodada — DEC-10..DEC-12 (24/08/2026) — encerra o Phase 1

## DEC-10 — Graficos e dialogos (Q-09): **usar as libs do ai9**
Os dois componentes proprietarios do legado sao substituidos pelos equivalentes do ai9:
- `vendor/doughnut` (61 nos no grafo; **o unico grafico do produto**) -> biblioteca de
  grafico do ai9
- `vendor/dialog` -> componente de dialogo/modal do ai9

Nao sao portados 1:1. O `frontend-engineer` escolhe o equivalente ja usado na base ai9
(ver `ai9-conventions.md`) e **mostra o resultado visual** antes de fechar o slice, ja
que o grafico e um elemento visivel do produto. Registrado no `improvements-log.md`
como padronizacao (sai codigo proprietario sem manutencao, entra componente da base).

## DEC-11 — Versao de producao (D-113): **CONFIRMADA — Ruby 2.6.1 / Rails 6.0.3.2**
O usuario confirmou explicitamente, mesmo depois de eu apresentar a evidencia de que o
`Gemfile.prod` e de maio/2021 enquanto o desenvolvimento seguiu ate 2023.

O **DEC-03 deixa de ser provisorio e passa a definitivo**. Logo:
- D-43 (`update_info` com `update_attributes`) -> **funciona em producao**, e feature
  real a migrar
- D-61 (edicao de tema, caminho `update_attributes`) -> **funciona**; o segundo caminho
  (POST para rota inexistente com chave malformada) continua quebrado
- D-91 (edicao de observer, `update_attributes`) -> **funciona**; `@total_count`
  ignorando filtros e o `companyId`/`observerId` trocado continuam defeitos

Consequencia operacional para o Phase 3: o ambiente de **referencia de paridade** e
Ruby 2.6.1 / Rails 6.0.3.2. Se for preciso rodar o legado para extrair valores golden
(comparacao de calculo financeiro), e essa a versao a subir — e ela usa o **fork do
`delayed_job`** de `github.com/livetat/delayed_job`, branch `rails-6-compatibility`.

## DEC-12 — `Legacy::execute` (Q-08): **assumido como nao executado**
O usuario nao sabe se o pipeline ETL Django->Rails ainda roda. Assumo que **nao**
(foi executado em 2021, e o banco de origem `SG20210329` tem a data no proprio nome).

- **Consequencia:** `app/models/legacy.rb`, `app/models/legacy/**`, a conexao
  `sfg_legacy` e o dump `db/seed_assets/sfg_legacy_full.sql` (9 MB) **nao sao portados**
  (ver D-105). As colunas `legacy_*` das tabelas de destino **sao preservadas** — sao a
  unica prova de proveniencia dos borderos de 2016-2021.
- **Risco se a suposicao estiver errada:** se o pipeline ainda rodar em producao, algum
  fluxo de importacao pararia no cutover. Risco baixo.
- **Como confirmar barato, quando der:** procurar chamadas a `Legacy::execute` em cron/
  tarefas do servidor, ou conferir se ha registros recentes com `legacy_id` preenchido
  (`SELECT max(created_at) FROM <tabela> WHERE legacy_id IS NOT NULL`). Se a data mais
  recente for de 2021, a suposicao esta confirmada.

---

# Estado final do Phase 1 — todas as perguntas encerradas
| # | Status final |
| - | ------------ |
| Q-01 timezone | fechada — DEC-06 (UTC, conversao por faixa de DST) |
| Q-02 autorizacao | fechada — DEC-08 (proponho matriz, voce aprova) |
| Q-03 multi-tenancy | fechada — DEC-07 (mantem o modelo do legado) |
| Q-04 paginacao | decidida por mim (passa a funcionar); reversivel |
| Q-05 banco | fechada — DEC-05 (PostgreSQL, deduzido do bundle) |
| Q-06 features novas | fechada — DEC-09 (so o legado) |
| Q-07 portar x descartar | criterio no DEC-09; lista item a item no Phase 2 |
| Q-08 `Legacy::execute` | fechada — DEC-12 (assumido nao executado) |
| Q-09 graficos/dialogos | fechada — DEC-10 (libs do ai9) |
| D-113 versao producao | fechada — DEC-11 (confirmada pelo usuario) |

**Nenhuma pergunta bloqueia o Phase 2.**

---

# Quarta rodada — DEC-13 (24/08/2026) — Phase 1b: gate de selecao ai9-only

Lista completa em `.migration-ai9/ai9-feature-selection.md` (35 features `AI9-001..035`,
~100k LOC, derivadas de 132 endpoints Grape, 60 models, ~80 services e 60+ rotas de
front, subtraindo por significado os 1439 IDs do legado).

## DEC-13.1 — Decisao do usuario: **manter 7, remover 28**

**MANTIDAS (7):**
| ID | Feature | Motivo |
| -- | ------- | ------ |
| AI9-007 | Chatbot: flow builder + motor de IA | **escolha explicita do usuario** — mantido, mas **adaptado** (DEC-13.2) |
| AI9-008 | Credenciais de provedores de IA | infra; consumida pelo chatbot mantido |
| AI9-016 | Galeria de midia, uploads e downloads | infra; o legado anexa em 7 pontos (avatar, anexos de renegociacao, temas, pictures) |
| AI9-030 | Login (magic link, codigo, OAuth, access codes) | infra; **e o unico login vivo do ai9** |
| AI9-033 | Shell de navegacao / modos de sidebar | infra; a navegacao do Safegold nasce dele |
| AI9-034 | Paises / DDI e defaults | infra barata, reusada nos formularios do legado |
| AI9-035 | Docs OpenAPI in-app e proxy de assets | infra de documentacao da API |

**REMOVIDAS (28):** AI9-001 a 006, 009 a 015, 017 a 029, 031, 032.
Ou seja: todo o produto SaaS de marketing/conteudo da ai9 — comercial (Asaas, planos,
cupons, onboarding), captacao (leads/omnichannel, Meta, analytics proprio, Painel TV,
heatmap, hub brsw), conteudo (blog, WhatsApp/Evolution, showrooms, pedidos/entregas,
transcricao, agenda), `Operations`, e o site institucional com seus enfeites (campfire,
3D, terminal, easter egg, Brazilian Software, NavKit, preview de site, design demo,
guia de rastreamento, audio visualizer, MCP n8n).

> **Nota sobre o DEC-09.** O DEC-09 disse "so as coisas do legado", e o chatbot **nao
> existe no Safegold**. Manter o AI9-007 e uma **excecao consciente** ao DEC-09,
> escolhida pelo usuario. Nao viola o principio: "manter" uma feature que o ai9 ja tem
> nao e o mesmo que "construir" uma feature nova. O que segue valendo do DEC-09 e que
> **nao construo** dashboard, serie historica de indicadores, PDF nem i18n.

## DEC-13.2 — O chatbot fica, mas **desacoplado**. Uso: assistente interno.

O usuario definiu o proposito: **suporte/ajuda ao usuario interno**, dentro do console.
Isso torna o desacoplamento natural — um assistente interno nao captura lead.

**O acoplamento real, medido no codigo:**
```
chat_flow    belongs_to :operation, optional: true        -> AI9-014 (removido)
chat_session belongs_to :lead, optional: true             -> AI9-006 (removido)
agent_run    belongs_to :lead, :operation, optional: true -> AI9-006 + AI9-014
chat_flow    has_many :instagram_comment_keywords,
                      :instagram_comment_reply_sents,
                      :integrations                       -> AI9-009 (removido)
```
Mais **81 referencias a `Lead`** em 10 arquivos de `app/services/ai/`, entre elas um
tipo de no inteiro (`app/services/ai/nodes/save_to_lead.rb`) e o `tool_executor.rb`
(34 referencias — as ferramentas do agente operam sobre leads).

**Todos os `belongs_to` sao `optional: true`**, entao nada quebra por constraint de
banco. O trabalho de adaptacao e:
1. remover o no `save_to_lead` do catalogo de nos e do flow builder;
2. remover as ferramentas do agente que operam sobre lead (`tool_executor`,
   `tool_registry`, `calendar_guard`) — a agenda tambem sai (AI9-020);
3. remover as associacoes e colunas `lead_id` / `operation_id` de `chat_flow`,
   `chat_session` e `agent_run`, e as `has_many` de Meta em `chat_flow`;
4. manter intactos: motor multi-provider (OpenAI/Anthropic/Google), flow builder,
   execucao de fluxo, sessoes, telemetria e o widget de chat.

**Resultado esperado:** assistente conversacional com IA funcionando dentro do console,
sem captura de lead, sem campanha e sem automacao de redes sociais.

## DEC-13.3 — Rota `/` aponta para a **tela de login**
Remover o AI9-021 (landing campfire) libera `/`. O Safegold e sistema interno e o
usuario decidiu no Phase 0 nao migrar o site publico, entao nao ha home institucional a
servir. Definido na mesma tarefa de remocao do AI9-021.

## DEC-13.4 — Login perde o canal WhatsApp (decisao minha, registrada)
**Consequencia necessaria** de remover o AI9-005 (WhatsApp/Evolution) mantendo o AI9-030
(login). Verificado no codigo: `code_validation.rb:27`, `magic_login.rb:25,70,106`,
`registration.rb:60,91,120` aceitam `method: %w[email whatsapp]`.

**Decisao:** o login continua funcionando por **e-mail**; removo `whatsapp` dos valores
aceitos nesses 6 endpoints e a UI correspondente. Justificativa: o Safegold e sistema
interno corporativo — todo usuario tem e-mail; e o legado ja notificava **apenas por
e-mail** (nao ha canal WhatsApp em lugar nenhum do `sfg`). Se voce quiser manter o
envio por WhatsApp, e so avisar — ai o AI9-005 precisa ser mantido tambem.

## Ordem de execucao da remocao (dependencias primeiro)
1. **Folhas visuais** (risco baixo, saem sozinhas): AI9-022, 023, 024, 025, 026, 027,
   028, 029, 031, 032 — e AI9-021 junto com o redirect de `/` para o login (DEC-13.3)
2. **Folhas de analytics**: AI9-011, 012, 013 -> depois **AI9-010**
3. **Conteudo**: AI9-019, 020, 015, 017, 004 -> depois **AI9-005** (aplicando DEC-13.4)
4. **Comercial**: AI9-003, 001, 018 -> **refatorar a `Sidebar`** (hoje monta o menu a
   partir de `plan_features`) -> depois **AI9-002**
5. **Meta**: AI9-009 (limpando as `has_many` de `chat_flow`)
6. **Leads**: AI9-006
7. **Operations**: AI9-014 (a colisao de nome mais perigosa)
8. **Desacoplar o chatbot** (DEC-13.2) — por ultimo, quando leads/Operations/Meta ja sairam

Cada bloco e **um commit reversivel**, com build verde antes de seguir. Ledger:
`to-remove` -> (strip executado + QA) -> `removed`. Um `to-remove` pendente **bloqueia o
fechamento da migracao**.

---

# Quinta rodada — DEC-14 (24/08/2026) — **REVOGA o DEC-13.4**

## DEC-14 — O login **mantem** o canal WhatsApp. AI9-005 passa a `kept` **parcial**.

O usuario corrigiu: *"mantem o whatsapp pro login, tinha esquecido que o whats precisava
pro login"*. **O DEC-13.4 fica revogado** — nao removo `whatsapp` dos valores aceitos, e
os 6 endpoints de auth continuam como estao.

Custo zero de retrabalho: o AI9-005 esta no **Bloco 3**, que ainda nao comecou. O Bloco 1
(em execucao) nao toca nele.

### O que o login realmente precisa — medido no codigo
O auth chama **exatamente uma coisa**: `EvolutionConnection.send_message({number:, text:})`
— em `magic_login_service.rb:100`, `pre_register_service.rb:46` e
`visitor_signup_with_link_service.rb`. Mais o resgate de erro por
`EvolutionConnection::{InvalidResponseError,TimeoutError,ConnectionError}`.

**Mas `EvolutionConnection` nao e autocontido.** `evolution_connection.rb:15` faz
`@instance ||= PolemkInstance.first` — ou seja, **enviar exige uma instancia de WhatsApp
pareada**. E parear exige a tela de QR code e o servico de instancia. Nao da para manter
"so o envio": sem pareamento, `PolemkInstance.first` e nil e o envio falha.

### Escopo minimo mantido (~677 LOC de backend + 1 tela)
| Arquivo | LOC | Por que fica |
| ------- | --- | ------------ |
| `app/services/evolution_connection.rb` | 182 | o cliente HTTP que envia a mensagem |
| `app/controllers/api/whats/v1/instances.rb` | 256 | pareamento, QR code, status da conexao |
| `app/services/polemk_instance_service.rb` | 126 | ciclo de vida da instancia |
| `app/models/polemk_instance.rb` (+ tabela) | 77 | `send_message` resolve a instancia por aqui |
| `app/jobs/evolution_reconnect_job.rb` | 36 | mantem a instancia viva; sem ele o login cai quando a sessao do WhatsApp expira |
| `frontend/src/app/pages/WhatsappPage.tsx` | — | a tela de pareamento (QR) |

### O que continua sendo removido do AI9-005 (~653 LOC)
`polemk_chat_service.rb`, `polemk_group_service.rb`, `polemk_webhook_service.rb`,
`whats_app_webhook_service.rb`, `whats_message_service.rb`,
`whatsapp_notification_service.rb`, `app/models/polemk_chat_message.rb`, e os endpoints
de `api/whats/v1/` de **chats, grupos e mensagens** — tudo que e atendimento/inbox, nao
autenticacao. Tambem removo do `evolution_connection.rb` os metodos de **grupo**
(`PolemkInstanceGroup.create!`, linha 156) e de gestao em massa que so o modulo de
atendimento usava.

### Consequencia operacional que voce precisa saber
Manter login por WhatsApp significa que o Safegold **depende de uma instancia de
WhatsApp pareada e ativa** (servidor Evolution API, ENVs `WHATS_SERVER_URL` /
`WHATS_AUTHENTICATION_API_KEY`). Se a sessao do WhatsApp cair e ninguem reparear, o login
por WhatsApp para — o login por **e-mail** continua funcionando normalmente. Vale ter isso
no runbook de cutover.

**Se em algum momento voce preferir simplificar**, o caminho de volta e barato: voltar ao
DEC-13.4 (so e-mail) e remover os ~677 LOC + a tela de pareamento. Nada mais depende deles.

### Ledger
`AI9-005` deixa de ser `to-remove` e vira **`kept` (parcial)**, com a nota do escopo
mantido. As removidas passam de 28 para **27**; as mantidas, de 7 para **8**.

---

# Correcoes trazidas pela matriz de autorizacao (24/08/2026)

## O DEC-04 era mais pessimista do que precisava
Eu registrei que, sem o dump de `livetat_auth_role_types`, a hierarquia de papeis teria de
ser **inferida**. **Errado.** `db/seeds.rb:40-95` e `engines/auth19/db/seeds.rb:9-90`
escrevem nome, `hierarchy` e os 17 valores de ability **linha a linha**. A tabela
papel x ability e **evidencia**, nao inferencia.

O DEC-04 continua valendo para o **schema** (o `pg_dump` segue ausente e as 2 provas de
schema fora das migrations seguem de pe), mas **nao** para os papeis. Um bloqueador a
menos.

## O defeito D-36 estava com o sintoma errado
Eu catalaguei: *"`default_role_type = "Visitor"` e `minimal_type_to_sign_up_through_web =
"Manager"` apontam para RoleTypes que o seed destroi -> provavelmente levanta
`NoMethodError` no login"*.

**O `NoMethodError` nao ocorre.** `config/application.rb:84` sobrescreve `"Manager"` por
`"Admin"`, que existe. E `default_role_type` e `""` (`application.rb:65`), nao `"Visitor"`.
O sintoma real do problema e outro, e ja esta catalogado separadamente: **D-39** — o
cadastro publico cria **Admin**.

`legacy-defects.md` corrigido. A licao vale para o resto: **defeito previsto por leitura de
codigo precisa ser confirmado no caminho de execucao real** antes de virar tarefa.

---

# Sexta rodada — DEC-15 (24/08/2026) — respostas sobre a matriz de autorizacao

## DEC-15.1 — Disponibilidades e cobrancas estao **VIVAS** (Q-A3)
Resposta do usuario: *"sim estao vivas"*.

**Isto INVERTE a decisao 2 da matriz.** Eu ia portar a *intencao* do codigo e entregar os
4 itens `locked` **desligados**. Errado: se as telas estao em uso, desliga-las tiraria
funcionalidade de gente que trabalha com elas hoje.

**Decisao:** os 4 itens — `availability`, `charges`, `project_availabilities`,
`availability_templates` — nascem **habilitados** no ai9.

O defeito **D-90** (o flag `locked` e lido de `g[:locked]`, do grupo, mas setado nos
itens, deixando-os destravados na pratica) deixa de ser "bug a corrigir" e passa a ser
**comportamento efetivo a preservar**. O que estava errado era a minha leitura: assumi que
a intencao do codigo valia mais que o efeito observado. Nao vale — **producao e a verdade**.

O `locked` como mecanismo continua existindo e sendo corrigido (ler do item, nao do grupo),
so que **nenhum dos 4 nasce marcado**. Se algum dia o negocio quiser travar um deles, o
mecanismo funciona.

## DEC-15.2 — Membership: a regra existe e esta na view (Q-A6)
O usuario mandou olhar no codigo, suspeitando do frontend. **Estava certo.**

**Backend (`app/controllers/pub/memberships_controller.rb`): zero autorizacao.** Nenhum
`before_action` de papel em `create`, `destroy`, `search`, `index`, `show`. E `:id` esta no
`permit` de `membership_params` (mass assignment, mesma familia do D-60/D-68).

**A regra real esta em `app/views/pub/console/parts/projects/detail/memberships/list/_widget.html.erb:23-24`:**
```erb
<% if !current_user.may?("user_is_readonly") %>
  <% if project.user_id != u.id && current_user.id != u.id %>
    <i class="delete_member ..."></i>
```
Ou seja, o botao de remover membro so aparece quando as **tres** condicoes valem:
1. o usuario atual **nao** e `user_is_readonly`;
2. o alvo **nao** e o dono do projeto (`project.user_id`);
3. o alvo **nao** e voce mesmo.

E em `_widget.html.erb:18` ha ainda a marcacao visual: quem **e** `project.user_id` recebe
rotulo diferente de "member" — o dono do projeto e um papel implicito, sem tabela.

**Decisao para o ai9:** estas tres condicoes viram **regra de servidor** no endpoint de
remocao de membership (hoje sao so CSS). Alem disso:
- `create` de membership exige papel com permissao de gestao do projeto (a definir na
  aprovacao da matriz) — hoje **qualquer sessao autenticada** cria membership em qualquer
  projeto, e membership e o que abre o grupo "Gestao" inteiro;
- `:id` sai do `permit`;
- o conceito de **dono do projeto** (`project.user_id`) passa a ser explicito, ja que
  hoje e uma regra implicita espalhada em views.

Isto fecha a **Q-A6**. Registrado tambem como reforco do **D-23**: mais um caso em que a
autorizacao existe **so na view**.

## DEC-15.3 — Dump do banco: **amanha** (25/08/2026)
O usuario tera o dump amanha. Consequencias:
- **Q-A1 fica aberta ate la** — nao da para saber quem tem abilities editadas a mao nem
  `user_is_readonly = 1` em producao. **Nao aplicar restricao de papel em producao antes
  de conferir isso**, sob risco de tirar acesso de usuario legitimo no dia 1.
- Quando o dump chegar, revisitar tambem o **DEC-04**: com `pg_dump --schema-only` da para
  fechar as 2 provas de schema fora das migrations (`default_position` do D-06 e
  `contracts.description` do D-108) e medir volumetria real das tabelas.
- A matriz de autorizacao pode ser **validada contra dados reais** antes de virar codigo.

**Nada disso bloqueia o Phase 1b** (remocao ai9-only), que segue.

---

# Setima rodada — DEC-16 (24/08/2026) — **a primeira entrega e uma DEMO comercial**

## O contexto novo
O usuario informou: a primeira entrega **nao vai para producao**. E uma **demonstracao
para o cliente ver e decidir comprar**. O banco vai ter **dados fake**. A migracao de dados
real (renomear banco etc.) fica **preparada**, nao executada.

Isso e uma mudanca de prioridade grande e reordena o trabalho. Registro o que muda.

## O que muda

### 1. Os bloqueadores de dados deixam de bloquear — para a DEMO
Continuam valendo para o **cutover real**, mas **nao travam mais a demo**:
- `pg_dump --schema-only` (DEC-04) — a demo roda com o schema derivado das migrations
- dump de `livetat_auth_role_types` — os papeis vem do seed (ja e evidencia, ver correcao do DEC-04)
- **Q-A1** (quem tem ability editada a mao / `user_is_readonly=1` em producao) — **irrelevante para a demo**: os usuarios da demo sao criados por nos. Continua sendo trava do cutover real.
- contagem de orfaos/duplicatas, conversao de timezone por faixa de DST, reconciliacao de centavos (DEC-02) — tudo isso e sobre **dado real**. Na demo, o dado nasce limpo.

> **Cuidado para nao virar armadilha:** o fato de nao bloquearem a demo **nao** os apaga.
> Eles voltam inteiros no cutover. O risco e alguem confundir "demo funcionou" com
> "migracao validada". A demo valida **comportamento e aparencia**, nao **dados**.

### 2. Nasce um entregavel novo: **seed de demonstracao**
Dados fake, mas **cries** — um sistema de credito e risco com dados obviamente falsos
(`Empresa Teste 1`, valores redondos) nao vende. O seed precisa de:
- projetos, empresas, portadores e fornecedores com nomes plausiveis do dominio
- recebiveis, renegociacoes com parcelas em varios estagios, operacoes de risco com
  exposicao real (positiva **e** negativa, para o semaforo aparecer)
- volume suficiente para a **paginacao** e a **busca** fazerem sentido na tela
- serie temporal coerente (datas que contam uma historia, nao todas de hoje)
- usuarios de cada papel, para demonstrar a matriz de autorizacao funcionando

**Nao usar dado real de cliente**, nem mesmo anonimizado, sem autorizacao explicita.

### 3. O ETL passa de "executar" para "**preparar e testar contra dado fake**"
O script de migracao de dados, o runbook e a etapa de introspecao (`DB-ETL-01`) continuam
sendo construidos — mas o teste passa a ser contra o seed de demo e contra o schema
derivado das migrations. Quando o dump real chegar, o script ja existe e so precisa ser
apontado para o banco de verdade.

### 4. **A qualidade visual sobe de prioridade**
E uma demo de venda. O `theming-brand-engineer` (marca Safegold em light **e** dark,
substituindo o conteudo padrao do ai9) deixa de ser "primeira tarefa do Phase 3" e passa a
ser **critica para o resultado**. Uma tela funcionalmente correta com a identidade visual
do ai9 generico nao demonstra o produto do cliente.

Os 4 "primarios" conflitantes da marca (#2D2D2A, #050517, #373435, #504746) precisam ser
resolvidos **antes** da demo, visualmente, contra o app rodando.

### 5. A ordem dos slices no Phase 2 muda
Deixa de ser so por dependencia tecnica e passa a ser **por valor de demonstracao**:
o que o cliente vai ver primeiro tem prioridade. Dependencia continua sendo restricao
(dado antes de backend, backend antes de tela), mas **dentro** do que e possivel, ganha
o que aparece na demo.

Isso precisa da resposta do usuario sobre **quais areas o cliente quer ver** — perguntado
em seguida.

### 6. O que **nao** muda
- **As correcoes de seguranca continuam** (D-34, D-28, D-39, D-111 etc.). Uma demo com
  escalacao de privilegio nao e aceitavel, e o cliente pode ter um tecnico olhando.
- **O contrato de paridade continua**: os 1439 IDs seguem sendo o alvo. Demo nao e
  desculpa para feature faltando — e sim para **ordem** de entrega.
- **O Phase 1b (remocao ai9-only) continua** e fica ainda mais importante: numa demo, tela
  de blog, chatbot de marketing ou painel de analytics da ai9 aparecendo no meio do
  produto do cliente e ruido que atrapalha a venda.

---

# Oitava rodada — DEC-17 (24/08/2026) — escopo e ritmo confirmados

## DEC-17.1 — Escopo: **sistema completo**. So o DADO e provisorio.
Correcao ao que eu havia assumido no DEC-16. O usuario esclareceu duas vezes:

> *"vamos migrar o sistema completo ja preparado para depois so migrar os dados, ou seja
> so no primeiro momento sera dados fakes mas tera todas as funcionalidades"*
> *"o escopo nao muda so os dados"*

**Todas as 1439 funcionalidades entram.** Nao existe "escopo de demo" reduzido: existe
**sistema completo rodando com dado fake**, pronto para receber o dado real depois.

**Isto revoga a parte do DEC-16** que falava em ordenar slices "por valor de demonstracao"
e priorizar o que o cliente ve. Nao ha triagem de features. A ordem dos slices volta a ser
**por dependencia tecnica** (dado -> backend -> tela), que e a que produz um sistema
inteiro funcionando.

**Continua valendo do DEC-16:**
- o entregavel de **seed de demonstracao** (dado fake **crivel**) — agora mais importante
  ainda, porque **todas** as telas precisam de dado plausivel, nao so as de vitrine;
- o ETL construido e testado contra dado fake, **pronto** para apontar ao banco real;
- os bloqueadores de dado nao travam esta entrega, mas **voltam inteiros no cutover** —
  "sistema funcionando com dado fake" nao e "migracao de dados validada";
- as correcoes de seguranca continuam;
- a qualidade visual continua alta.

## DEC-17.2 — Prazo: **sexta-feira, 28/08/2026** (4 dias)
Pedido explicito de **fazer com calma**. Isso e instrucao de metodo, nao so de prazo:
preferir planejar direito a sair implementando.

## DEC-17.3 — **PARAR de implementar** ("nao implemente nada ainda")
Efeito imediato:
- **nenhum agente de implementacao despachado**;
- **Blocos 3 a 8 do trim parados** aguardando confirmacao — remocao tambem altera codigo,
  entao travei por precaucao;
- **nada revertido**: Blocos 1 e 2 estao commitados, verificados, e seguem validos.

O que avanca **sem tocar codigo**, e que e exatamente "fazer com calma":
- **Phase 2 — o mapa de migracao**: para cada um dos 1439 IDs, decidir **reuse / adapt /
  build** contra o grafo do ai9, e agrupar em slices verticais. Documento, nao codigo.
- os **openspec changes** por slice (proposal + design + tasks)
- fechar a **matriz de autorizacao** com o usuario
- desenhar o **seed de demonstracao**

Estado congelado: Phase 1 fechada (1444 requirements), Phase 1b com 2 de 8 blocos
(-42 mil linhas), nenhum agente rodando.

---

# Nona rodada — DEC-18 (24/08/2026) — **a matriz de autorizacao esta APROVADA**

O Vinicius respondeu as 7 decisoes que faltavam. Com isto o
`.migration-ai9/authorization-matrix.md` deixa de ser proposta e vira **contrato**:
e a partir dele que nascem o seed versionado de RoleTypes e as policies por rota.

## DEC-18.1 — OG e papel do **fornecedor (Livetat)** (Q-A5)
Confirma a inferencia (o `dash` manda o OG para `users`, nao para dado de negocio).
Consequencia: OG **nao** e papel do cliente Safegold, nao aparece na operacao do dia a
dia e nao entra no seed de demo como usuario "normal". Sustenta o tratamento especial
que o `permissions_controller.rb:17-21` ja da a ele.

## DEC-18.2 — Permissoes: **OG + Admin, limitado a hierarquia inferior** (decisao #2)
**Eu propus mais restritivo (so OG); o usuario abriu para o Admin — com trava.**

O Admin edita abilities, mas **so de RoleTypes de hierarquia abaixo da dele** — nunca a
propria, nunca a do OG. O mecanismo ja existe: `RoleType.inferior_role_types`
(`engines/auth19/app/models/livetat/auth/role_type.rb:16-25`).

Isto **fecha o caminho de autopromocao** (que era a minha preocupacao real) **sem** criar
dependencia da Livetat para uma tarefa administrativa do cliente. Melhor que a minha
proposta: eu tinha resolvido o risco cortando a funcionalidade; a resposta resolve o
risco **mantendo** a funcionalidade.

Implicacao tecnica obrigatoria: o **D-34** tem que ser corrigido junto. Hoje
`fetch_permission` faz `Ability.find(params[:id] || params[:ability_id])` e **descarta o
`:id` do usuario** — ou seja, sem corrigir isso a trava de hierarquia e contornavel por
URL. A ability passa a ser resolvida **sempre** a partir do RoleType alvo, e o RoleType
alvo e validado contra `inferior_role_types` do usuario da sessao. **Gerente sai** da
tela (nao tem hierarquia inferior util e nao tem `may_create_users`).

## DEC-18.3 — Impersonation: **OG + Admin restrito a hierarquia inferior** (decisao #5)
Mesmo padrao da anterior, mesma logica: o Admin do cliente da suporte aos proprios
usuarios sem precisar chamar o fornecedor.

Regras que valem para os dois:
- nunca personificar **OG**, nunca personificar **lateral** (mesma hierarquia);
- exige **motivo** informado;
- grava **trilha de auditoria**: quem personificou, quem foi personificado, quando, por
  que, e quando encerrou;
- a sessao personificada **expira** (nao fica aberta indefinidamente);
- **nao herda** a capacidade de personificar (sem encadeamento).

Isto e a correcao central do **D-34**, e desarma a combinacao com o **D-109** (senha
deterministica) que hoje da comprometimento trivial.

## DEC-18.4 — Colaborador **le** os catalogos globais (decisao #1)
Aprovada como proposta: `R` em `carriers`, `carrier_groups`, `segments`, `sub_segments`,
`wallets`, `indicators`, `movement_kinds`, `receivable_kinds`, `resource_sources`,
`resource_kinds`, `risk_operation_types`, `structured_operation_types`,
`risk_movement_types`, `project_guarantee_types`.

**A regra em uma frase: o menu esconde a tela de administracao do catalogo, nao o dado do
catalogo.** Sem isto, todo dropdown do papel mais numeroso quebra no dia 1.

Leitura **apenas** — nenhum verbo de escrita. E leitura do catalogo, nao dos vinculos de
projeto (`project_to_carrier_connections` etc. seguem com escopo de projeto).

## DEC-18.5 — Membership: criam/removem **OG, Admin e Gerente** (Q-A6, fecha o DEC-15.2)
Herda o gate do grupo Cadastro. Somado as **tres condicoes** que o DEC-15.2 achou na view
e que agora viram **regra de servidor** (hoje sao so CSS):

1. quem executa **nao** pode ter `user_is_readonly`;
2. **nao** se remove o dono do projeto (`project.user_id`);
3. **nao** se remove a si mesmo.

Mais: `:id` sai do `permit` de `membership_params` (mass assignment, familia D-60/D-68).

Isto fecha o **D-28**: hoje qualquer sessao autenticada se auto-adiciona a qualquer
projeto e, com isso, **ganha o grupo "Gestao" inteiro**.

O usuario **nao** escolheu incluir o dono do projeto como quem gerencia membros. Entao
`project.user_id` continua sendo um conceito **descritivo** (rotulo diferente na lista,
`_widget.html.erb:18`, e protecao contra remocao) — **nao** vira papel com poder.

## DEC-18.6 — `Membership.role` e **so rotulo descritivo** (Q-A2)
Os quatro valores (`Responsavel`, `Participante`, `Coordenador`, `Gestor`) sao portados
como campo informativo, exatamente como hoje: escritos, exibidos, **nunca consultados
para autorizar**.

**A matriz continua com uma dimensao so** (papel global + membership de projeto). Era o
maior risco de a matriz mudar de forma; nao mudou.

## DEC-18.7 — Cadastro publico **desligado**; entrada so por **convite** (decisao #7)
Corrige o **D-39**: hoje `minimal_type_to_sign_up_through_web = "Admin"`
(`config/application.rb:84`) deixa qualquer pessoa na internet se cadastrar ate
hierarquia **998**.

No ai9 nao existe rota de auto-cadastro. Entrada so por convite — OG, Admin e Gerente ja
tem `may_invite_users`. O convite carrega o papel e (quando aplicavel) o projeto.

**Para a demo (DEC-16):** os usuarios sao criados pelo seed, entao isto nao atrapalha a
apresentacao. Se na hora da demo o cliente quiser ver auto-cadastro, e um flag —
mas nasce **desligado**.

## Decisoes de baixo impacto que eu tomei sozinho (registradas, nao perguntadas)

Estas nao mudam desenho nem tiram acesso de ninguem; se voce discordar de alguma, e um
ajuste de uma linha:

- **Q-A4 — `app_themes`: og/admin.** As tres evidencias discordavam
  (`themes/helper/_body.html.erb:169` = `og?` puro; `themes/form/_body.html.erb:327` =
  og/admin/manager; `app_themes_controller.rb:24,31` = so `Admin` como destinatario).
  Fiquei na media, que e tambem o gate do grupo Admin. Recurso cosmetico.
- **Q-A7 — os 4 limites `max_*` NAO sao aplicados.** Nada le `max_*` fora do proprio
  factory, e os valores **se contradizem** (Gerente tem `may_create_private_entries = 1`
  mas `max_private_entries_amount = 0`, `db/seeds.rb:67` vs `:76`). Aplica-los faria o
  Gerente nao criar **nenhum** projeto — o oposto do que o menu mostra.
- **Decisao #3 — Gerente tem `R` em `users`, nao CRUD.** Tres evidencias independentes
  concordam: o menu deixa ele ver (`application_helper.rb:139,144`), a lista deixa ele ver
  (`users/list/_widget.html.erb:44`), mas **toda** acao de escrita esta atras de
  `og? || admin?` (`detail/_body.html.erb:22`, `detail/_body.js.erb:8`,
  `helper/_body.html.erb:18`) — e as abilities confirmam: Gerente **nao tem**
  `may_create_users` nem `may_delete_users`, **tem** `may_read_users` e `may_invite_users`.
  Gerente le e convida.
- **Decisao #6 — das 17 abilities, so `user_is_readonly` sobrevive.** As 12 condicionais
  falam de "Projetos" e "Modulos" (vocabulario generico da engine), nao dos 45 recursos
  reais, e **nenhuma e consultada em lugar nenhum do app**. Autorizacao no ai9 =
  **papel + membership**, declarativa por rota, avaliada **no servidor**.
  `user_is_readonly` e promovida de flag de UI a **checagem de servidor** que nega todo
  verbo de escrita.
- **Decisao #8 — papel vazio (`""`, D-36) entra como Colaborador**, e o usuario sai numa
  **lista de excecoes** para revisao humana antes do cutover. Nem promovido nem bloqueado
  em silencio. No seed do ai9, `role_type` e **obrigatorio**.
- **Decisao #4 — INVERTIDA pelo DEC-15.1**: os 4 itens `locked` (`availability`,
  `charges`, `project_availabilities`, `availability_templates`) nascem **habilitados**,
  porque o usuario confirmou que estao vivos. Ver DEC-15.1.

## O que continua aberto (e nao bloqueia nada)

**Q-A1 — existe usuario em producao com abilities editadas na mao pela tela de
Permissoes, em especial `user_is_readonly = 1`?** So o banco responde; o dump chega
**25/08** (DEC-15.3).

- **Para a DEMO: irrelevante** — os usuarios da demo sao criados por nos (DEC-16).
- **Para o CUTOVER real: e trava.** Nao aplicar restricao de papel em producao antes de
  conferir isso, sob risco de tirar acesso de usuario legitimo no dia 1. O dry-run tem
  que listar todo usuario cuja ability efetiva **divirja** do seed do RoleType dele.

---

# Decima rodada — DEC-19 (24/08/2026) — Q-A1 fica para **depois da venda**

Decisao do usuario: *"deixa esse do abilities pra depois isso so vai ser relevante se o
cliente fechar ao ver nosso prototipo"*.

**Q-A1 sai do caminho critico.** Ela e auditoria de **dado de producao** (quem teve
ability editada a mao pela tela de Permissoes, quem esta com `user_is_readonly = 1`), e
producao so entra em cena se houver contrato. A entrega de sexta e prototipo com dado
fake (DEC-16/DEC-17.1).

**Onde ela volta a valer, sem excecao:** no **runbook de cutover**. A matriz de
autorizacao (DEC-18) esta aprovada e sera implementada por inteiro — o que fica adiado e
so a **conferencia contra o banco real** antes de ligar as restricoes em producao. O
dry-run tem de listar todo usuario cuja ability efetiva divirja do seed do RoleType dele,
e essa lista tem de ser revisada por gente antes do dia 1.

Registrado tambem no `authorization-matrix.md` e no runbook de cutover para nao se perder.

**Consequencia pratica agora:** volta-se a implementar. Fila = **Blocos 3 a 8** do
Phase 1b, depois o fechamento do 1b e o Phase 2.

---

# Decima primeira rodada — DEC-20 (24/08/2026) — onde o assistente guarda a conversa

## O problema que apareceu no Bloco 6
Ao remover o `AI9-006` (leads/omnichannel), descobriu-se que `Lead`/`LeadMessage` eram
**tambem a persistencia de conversa do chatbot mantido** (AI9-007). O agente removeu o
`Lead` de verdade — manter um model de CRM de 587 LOC com o funil inteiro dentro de um
sistema de credito seria pior — e **nao improvisou substituto**, porque onde o assistente
grava a conversa e decisao de produto, nao de bloco de remocao. **Foi a decisao certa.**

## DEC-20 — historico **so em memoria/Redis**, sem tabela
Decisao do usuario. O historico vive na sessao e expira; nao ha mudanca de schema.

**O que isto da:** o assistente mantem o fio enquanto a conversa esta aberta, que e o que
importa para um assistente de ajuda interno. Zero migration, zero tabela nova, e o Bloco 8
fecha mais rapido.

**O que isto custa, registrado para nao virar surpresa:**
- a sessao **nao retoma** depois de fechar a aba;
- **nao ha registro** do que o assistente respondeu — sem trilha auditavel.

**Por que isso nao e um beco sem saida:** adicionar depois uma `ChatMessage` ligada a
`ChatSession` (que continua existindo) e **aditivo** — nao quebra nada do que for
construido agora. Se em algum momento o assistente passar a orientar decisao de credito,
e nao so a ajudar com a tela, a trilha vira requisito e o caminho esta aberto.

**Telemetria:** o campo `channel` vinha de `lead.source_type` e ficou vazio. Passa a ser
constante `console` — e o unico canal que existe no uso definido pelo DEC-13.2.

---

# Decima segunda rodada — DEC-21 (25/08/2026) — escopo da demo, apos o mapeamento

O Phase 2 revelou coisas que o inventario nao mostrava, e tres delas mudam escopo. **Isto
emenda parcialmente o DEC-09** ("so o que existe no legado"): as adicoes abaixo sao
**features novas, conscientes, para a demonstracao** — nao paridade.

**Para nao se perderem nem se confundirem com paridade, ganham IDs proprios**: `NEW-001`,
`NEW-002`, `NEW-003`. Entram no ledger como `new`, nunca como item de paridade do legado.
O QA do Phase 4 nao deve procura-los no legado — nao estao la.

## DEC-21.1 — `NEW-001`: graficos nos indicadores
**A descoberta:** o legado **nao renderiza grafico nenhum**. `vendor/doughnut` e exposto
como global (`index.js.erb:31,37`) e **nenhuma view o instancia**. O **DEC-10** ("usar as
libs de grafico do ai9") partia da premissa de que havia grafico a migrar. Nao havia.

**Decisao: entra**, nos **indicadores** — serie mensal e evolucao de volume por portador,
com **Recharts**, que ja esta na base.

Custa pouco (peca pronta) e sem ele o seed de demonstracao perde o proprio ponto: ele foi
desenhado com **24 meses e uma inflexao** justamente para o grafico provocar a pergunta
"o que aconteceu aqui?".

**Nao entra no risco** — o usuario escolheu a versao menor. Exposicao por portador e
utilizacao de limite ficam para depois da venda.

## DEC-21.2 — `NEW-002`: dashboard resumo na tela inicial
**A descoberta:** a tela "Inicio" do legado **nao tem dashboard** — e so um redirecionamento
por papel (`dash/_body.js.erb:8-22`). Numa demo, ela e a **primeira coisa** que o cliente ve
depois do login.

**Decisao: entra** — cards com total operado, exposicao atual, limites proximos do teto e
renegociacoes em atraso. **Todos consomem numeros que os servicos do mapa ja calculam**
(contrato C2), entao o custo e de tela, nao de logica.

## DEC-21.3 — `NEW-003`: PWA **so o minimo instalavel**
O PWA foi decidido **SIM** no Phase 0 e **nao tinha entrado em nenhuma fatia** — a base ai9
nao tem nada disso. O usuario cortou para o minimo: **manifest e icones**, para o app poder
ser instalado na tela inicial. **Sem service worker, sem offline, sem cache.**

E poucas horas e da para demonstrar. As **views mobile separadas** (tambem decididas no
Phase 0) **continuam no escopo** — sao elas que aparecem numa demo, nao o manifest.

## DEC-21.4 — `openssl_verify_mode`: **deixar como esta, por enquanto**
Resposta do usuario: *"esquece isso por enquanto"*.

`config/environments/production.rb:82` da base ai9 tem `openssl_verify_mode: 'none'`, que
desliga a verificacao de certificado TLS do SMTP — o mesmo **D-85** que estamos corrigindo
no legado, dentro de casa.

**Nao mexer.** Continua registrado como **flag 11** em `upstream-flags.md`, e os requisitos
**OPS-484** e **OPS-626** ficam **explicitamente nao atendidos** — nao esquecidos, nao
silenciosamente dados como feitos. Se a demo virar venda, isto volta antes do cutover: e
exposicao a MITM no envio de e-mail, e e-mail e o canal do codigo de login.

## O que estas decisoes NAO mudam
A ordem das fatias continua por **dependencia tecnica** (DEC-17.1). `NEW-001` e `NEW-002`
dependem de **S10** e dos servicos de calculo (**S5..S8**), entao entram **no fim**, nao no
inicio — dashboard bonito sobre numero errado e pior que dashboard nenhum.


## DEC-22 — Escopo da demo: **manter tudo** (25/08/2026)

**Pergunta:** 1.717 tarefas em 20 fatias contra sexta 28/08. Ate onde a demo vai?

**Resposta do usuario:** *"vamos manter tudo vai dar tempo"*.

**Decisao: as 20 fatias, escopo completo.** Reafirma o DEC-17.1. O corte por fatia que
eu recomendei (parar no bordero, 791 tarefas) foi **recusado**.

**Consequencia operacional, registrada para nao virar surpresa:** a ordem de execucao
passa a ser a de dependencia pura, sem priorizacao por valor de demo, e a paralelizacao
e maxima — fatias independentes rodam ao mesmo tempo. Se em algum momento ficar claro
que nao fecha, **eu aviso com a fatia especifica que esta em risco**, nao no dia da
entrega. A decisao de reduzir escopo continua sendo do usuario, nunca minha.

## DEC-23 — Perguntas do mapeamento: **rodada completa agora** (25/08/2026)

**Pergunta:** ~76 perguntas com default declarado. Perguntar so as que mudam numero
(~10), todas, ou seguir tudo por default?

**Resposta do usuario:** **rodada completa agora**.

**Decisao: compilar TODAS as perguntas em aberto** — as dos 5 mapas de bloco (`Q-*`), as
que os agentes de empacotamento levantaram nos 20 proposals (`T-D*`, `Q-A*`, `Q-B*`,
`Q-R*`, `Q-19..Q-23`) e os defaults que os agentes declararam por conta propria — num
documento unico, organizado por fatia, cada uma com o que ela trava, as opcoes e o
default vigente.

**Nada segue por default sem passar por essa rodada.** O que o usuario responder vira
DEC-24 em diante e tem precedencia sobre qualquer default escrito nos mapas.

**Isto NAO bloqueia o Phase 3.** As fatias cujo caminho nao depende de resposta comecam
agora; as tarefas travadas ficam marcadas e esperam.

## DEC-24 — P-001: replicar o decaimento por dias uteis como esta (25/08/2026)

**Pergunta (P-001):** o lancamento de disponibilidade "ajustado" e corrigido por
`value = original_value × (dias uteis ate a data ÷ dias uteis do mes)`
(`availability_entry.rb:193`), e um `before_validation` regrava `original_value = value`
sempre que `value` chega alterado (`:20`). Como o formulario preenche o campo com o valor
**ja corrigido** (`_widget.html.erb:56,131`), **salvar a mesma celula de novo multiplica de
novo**. Defeito **D-02**.

**Resposta do usuario: opcao (b)** — replicar o decaimento exatamente como esta, com teste
golden, e nunca mais tocar.

**Contraria o default,** que era (a) corrigir. Registrado como escolha consciente, na mesma
linha do **DEC-01** (sinal invertido) e do **DEC-02** (float): **paridade numerica acima de
correcao**.

**Consequencias, para o QA nao ler nada disto como regressao:**
- O valor de um lancamento continua dependendo de **quantas vezes alguem apertou salvar**.
  Dois usuarios salvando a mesma linha seguem produzindo valores diferentes.
- O `original_value` continua sendo sobrescrito pelo valor corrigido. O desenho que S11
  tinha (`s11/design.md:118-134`) — guardar o digitado e nunca sobrescrever — **fica revogado**.
- O ETL de S14 **nao** reconstitui `original_value`: ele copia o que estiver la.
- **Teste golden obrigatorio**, alimentado com valores extraidos do legado, incluindo o caso
  de **salvamento repetido** — e o teste reprova quem "consertar" a formula depois.
- Vai para o `improvements-log.md` como melhoria **DECLINADA**, igual a D-93 e D-104.

## DEC-25 — P-097 (parcial): alvo de impersonacao no seed (25/08/2026)

**Pedido do usuario:** criar um usuario do tipo ideal para testar que o OG consegue
impersonar, e configurar no seed tudo que for necessario.

**Feito** (commit `cd3a9797`): `Cliente Teste` / `vinaoxd+cliente@gmail.com`, tipo **client**
(nivel 2). Verificado executando os 6 passos, inclusive a queda de privilegio.

**Escolhas e o motivo de cada uma:**
- **`client`, nao `free`/`visitor`** — `visitor` cai no `restrict_visitor_access!` e testaria
  a restricao de visitante em vez da impersonacao.
- **Plus-address do proprio OG** — em dev `raise_delivery_errors` esta ligado
  (`development.rb:44`); dominio inexistente faria o `request_code` estourar 500 e o usuario
  nao conseguiria nem logar direto para comparar.

**ATENCAO — o P-097 continua ABERTO.** O que foi respondido foi um pedido pontual, nao a
pergunta. **O P-097 e "quem constroi o seed de demonstracao"**: `db/seeds/demo/` +
`rake demo:seed`, com o desenho pronto em `demo-seed-design.md`. S18 criou
`lib/tasks/demo.rake` **vazio**, S14 e S15 o consomem, **ninguem o preenche**, e ele nao
aparece em script de cobertura nenhum porque nao tem ID de inventario. **Sem ele, as 20
fatias entregam telas vazias na sexta.** Segue no topo de "Comece por aqui".

## DEC-26 — P-002: replicar as duas semanticas de soma, com rotulo (25/08/2026)

**Resposta: opcao (c).** A consolidacao geral continua somando **bruto** (`availability_entry.rb:188`)
e os nos com filhos continuam **aplicando** `is_cumulative` e `is_debit` (`:191`). Golden test
trava as duas, e a tela **rotula** cada uma para o usuario saber qual esta lendo.

Era uma das 4 perguntas **sem default** — as duas metades divergiram e nenhuma propos (c).

**Consequencia registrada:** o **D-08** vai junto para a base nova, de forma consciente. O
codigo novo nasce com **duas regras de soma** convivendo; o que impede isso de virar defeito
silencioso e o rotulo na tela. Sem o rotulo, a decisao vira o proprio D-08 de novo. **A
tarefa de rotulagem nao e cosmetica: ela e a decisao.**

Mesma familia de DEC-01, DEC-02 e DEC-24 — paridade acima de correcao.

## DEC-27 — P-003: manter as duas metricas e renomear na interface (25/08/2026)

**Resposta: opcao (c)**, que era o default. O total geral segue `base_entries.pluck(:value).sum`
(`project.rb:406`) e o card de padrao base segue `virtual_value` (`:415`) — **nenhum numero
muda**. O que muda e o rotulo: "Total bruto" x "Saldo acumulado".

Fecha o **DC-34** sem tocar em calculo. Combina com o DEC-26: nas duas, a resposta foi
preservar o numero e tornar a diferenca legivel.

**Achado adjacente registrado:** `values[:total]` e calculado e **nunca renderizado** — o
painel so usa `by_entry[].total`. Codigo morto a remover na S11.

## DEC-28 — P-004: dias uteis seguem sem feriados (25/08/2026)

**Resposta: opcao (a)**, o default. Segue `reject { |d| d.cwday == 7 || d.cwday == 6 }`
(`date_decorator.rb:3,7`). Nenhum calendario de feriados.

**D-03 permanece**, de forma consciente: em todo mes com feriado o multiplicador de correcao
fica alto, como sempre esteve. **Nao e regressao.**

**Por que da para adiar sem divida:** o calendario e **aditivo** — entra depois sem refazer
nada e sem deixar duas semanticas no codigo. Diferente das outras tres de S11, onde adiar
significaria escrever o servico duas vezes.

## DEC-29 — P-005: recalcular o valor das operacoes de risco historicas (25/08/2026)

**Resposta: opcao (a)**, o default. O ETL **recalcula** `operation_value` dos borderos
historicos, **com relatorio de quantos mudaram e de quanto, entregue ANTES de qualquer carga
definitiva**.

Corrige o **D-11**: no legado a `RiskOperation` nasce em `receivable_entry.rb:161` no primeiro
`save` do controller (`receivables_controller.rb:77`), quando ainda **nao existe nenhuma
`ReceivableTax`** — e o segundo `save` (`:89`) cai no ramo de `:168`, que so atualiza tipo e
subtipo. O valor sem tarifas fica congelado para sempre.

**Esta decisao contraria DEC-01/DEC-02/DEC-24/DEC-26 de proposito, e o criterio esta claro:**
nas outras, replicar o defeito preserva um numero que ja existe. Aqui, replicar significaria
**gravar numero errado de proposito num banco novo** — o ai9 ja cria a operacao depois das
tarifas, entao copiar manteria dois regimes de verdade no mesmo painel de exposicao.

**Numeros do painel de exposicao vao mudar** em relacao ao legado. Esperado, nao regressao.
Se o relatorio mostrar delta agregado material, a opcao (c) (copiar e marcar as divergentes)
volta a mesa — mas isso so se decide com o numero na mao.

## DEC-30 — **PRINCIPIO GOVERNANTE**: o legado e sistema validado; regra e calculo se mantem (25/08/2026)

**Declaracao do usuario:** *"o legado e um sistema validado entao a maioria das coisas de
regras e calculos deve-se manter como esta no legado"*.

**Isto nao e resposta a uma pergunta — e o criterio que resolve uma familia inteira delas.**
Tem precedencia sobre qualquer "Recomendacao" escrita nos mapas, nos proposals e no
`perguntas-rodada-1.md`.

**A regra:** onde a pergunta for *"replicar o comportamento do legado ou corrigi-lo?"*, a
resposta e **replicar**, com **teste golden** alimentado por valores extraidos do legado. O
teste nao existe para provar que a formula esta certa — existe para **reprovar quem
'consertar' depois** sem passar por uma DEC.

Consolida e generaliza DEC-01 (sinal invertido), DEC-02 (float), DEC-24 (decaimento),
DEC-26 (duas somas), DEC-28 (sem feriados), DEC-31..34 abaixo.

### As tres excecoes — onde "replicar" NAO se aplica, e por que

O principio protege **numero que o cliente ja ve**. Ele nao cobre:

1. **Dado que seria gravado errado num banco novo.** Diferente de preservar um numero
   existente: e produzir um numero errado do zero. **DEC-29 (P-005)** e exatamente este caso
   — no ai9 a operacao de risco nasce **depois** das tarifas, entao copiar o valor legado
   manteria dois regimes de verdade no mesmo painel. **Ver a pendencia no fim desta DEC.**
2. **Falha de seguranca ou de autorizacao.** Replicar "qualquer autenticado publica os Termos
   de Uso" (achado **A-1**, P-022) nao e paridade, e vulnerabilidade portada. O mesmo vale
   para o escopo por projeto descartado quando chega id por parametro (familia **D-01 / D-16
   / D-29 / D-76 / D-100**) e para a falta de trava de hierarquia na impersonacao
   (`upstream-flags` #14).
3. **Comportamento que o legado nao tem.** Onde nao ha legado a replicar — features novas
   (NEW-001..003), o que nasce da base ai9, decisoes de escopo — o principio e silencioso e a
   pergunta continua valendo.

### Pendencia aberta por esta DEC

**O DEC-29 (P-005) foi decidido ANTES do DEC-30 e esta em tensao com ele.** Ele manda
**recalcular** o valor das operacoes de risco historicas; o principio geral mandaria
**copiar**. Eu o classifiquei como excecao (1), mas **isso precisa da confirmacao do
usuario** — nao vou reverter uma decisao dele por interpretacao minha. Enquanto nao houver
palavra, vale o DEC-29 **com o relatorio de delta entregue antes de qualquer carga
definitiva**, que era a condicao ja acordada.

## DEC-31 a DEC-34 — P-006, P-007, P-008 e P-009: replicar (25/08/2026)

Todas respondidas **"replicar"**, e todas agora amparadas pelo DEC-30.

- **DEC-31 · P-006** — `calc_valor_liq_correto` mantem o desconto **linear**
  (`receivable_entry.rb:107-112`), nao composto. Golden. **D-14** preservado. A duplicacao da
  formula no JS (`_body.js.erb:462-467`) **nao** e replicada: pelo contrato **C2** a tela
  chama o mesmo servico que grava — replicar a formula, nao a duplicacao.
- **DEC-32 · P-007** — a guarda do CET do banco continua olhando o prazo da **empresa**
  (`:74`), assimetrica em relacao a `:78`. Golden documenta. Diverge registrada no
  `improvements-log.md` como melhoria **declinada**.
- **DEC-33 · P-008** — os dois arredondamentos ficam como estao: `.round(4)` em `:90-92` e
  `.round(2)` em `:99`, com a mesma expressao algebrica.
- **DEC-34 · P-009** — a remuneracao segue **flat sobre o capital**
  (`receipt.rb:63`), sem pro-rata, ignorando `issue_date`/`due_date`. **E a unica formula de
  faturamento do sistema e o legado nao tem um unico teste que a cubra (D-114)** — o golden
  desta linha e o mais importante de toda a migracao.

## DEC-35 — D-94 / P-016: o ciclo de vida da operacao de risco e replicado (25/08/2026)

**Resposta: replicar.** Vale o DEC-30.

O orquestrador levantou a objecao antes de perguntar — o `legacy-defects.md` ja trazia o
veredito **"corrigir — a renovacao em dobro e erro de exposicao financeira, nao comportamento
a preservar"** — e o usuario **reafirmou replicar**. Decisao do usuario, registrada.

**O veredito anterior do `legacy-defects.md` fica REVOGADO** por esta DEC. Quem ler aquele
arquivo depois precisa cair aqui: acrescentar a nota no D-94 e uma tarefa da S7.

**O que vai para o produto novo, de propriedade consciente:**
- **Renovar NAO encerra a original.** As duas operacoes ficam vivas e **as duas consomem
  limite de risco ao mesmo tempo**. O limite disponivel exibido continua sendo o de hoje.
- Operacao **encerrada** continua somando exposicao, aceitando **movimento** e **prorrogacao**,
  e continua **faturavel**.

**Consequencia para o Phase 4:** nenhuma destas e regressao. O golden test da S7 trava os
dois lados — inclusive o caso da renovacao, que **deve** produzir duas operacoes ativas. Um
teste que exija encerramento automatico esta errado contra esta DEC.

## DEC-36 — P-005 REVISTO: copiar o valor das operacoes historicas (25/08/2026)

**Substitui o DEC-29.** O DEC-29 foi tomado antes do DEC-30; confrontado com o principio, o
usuario escolheu **copiar**.

O ETL carrega `operation_value` **exatamente como esta no legado** — ou seja, calculado sem
as tarifas, por causa do **D-11** (`receivable_entry.rb:161` dispara no primeiro `save` do
`receivables_controller.rb:77`, quando ainda nao existe `ReceivableTax`, e o segundo `save`
cai no ramo de `:168`, que so atualiza tipo e subtipo).

**Sem recalculo e sem relatorio de delta como pre-condicao de carga.**

**Consequencia registrada:** o painel de exposicao do ai9 bate 100% com o do legado, **e o
dado errado vai junto**. Os borderos novos, criados no ai9, nascem com a operacao apos as
tarifas — entao **passam a conviver dois regimes**: historico sem tarifas, novo com. Isso era
o argumento do DEC-29 e permanece verdadeiro; o usuario optou por ele conscientemente.
Registrar a fronteira temporal na S14 para que ninguem leia a diferenca como bug.

## DEC-37 — P-026: a taxa de remuneracao segue sem validacao de faixa (25/08/2026)

**Resposta: replicar, sem validacao.** Vale o DEC-30, em sentido estrito.

`remunerations.value` continua aceitando qualquer numero — 250% passa pela interface e
multiplica todo o faturamento daquela operacao, como hoje.

Somado ao **D-114** (o legado nao tem um unico teste), o **golden de `receipt.rb:63` e a
unica rede que sobra** sobre a linha que fatura. Ele nao valida a entrada; so garante que a
formula nao mude sozinha.

## DEC-30 (adendo) — a EXCECAO-1 fica REVOGADA (25/08/2026)

O DEC-36 respondeu **o caso arquetipico** da excecao 1 ("dado que seria gravado errado do zero
num banco novo") escolhendo **copiar**. Logo a excecao 1 nao existe mais como categoria.

**A leitura vigente do DEC-30 e estrita:** replicar o legado em regra, calculo **e dado**.
Sobram duas excecoes:

- **EXCECAO-2 — seguranca e autorizacao.** Nao foi coberta por nenhuma resposta ate agora e
  **continua aberta**, pergunta a pergunta. Sao 6: P-022 (qualquer autenticado publica os
  Termos de Uso), P-048 (`users.is_active` sem nenhum leitor — replicar significa **nao
  bloquear ninguem**, e toda conta inativa entra no produto novo com acesso pleno), P-056,
  P-061, P-105, P-106.
- **EXCECAO-3 — nao existe legado a replicar.** Feature nova, coisa que nasce da base ai9,
  escopo, retencao, nomenclatura. O principio e silencioso; sao 43.

**Aplicado por consequencia direta do DEC-36**, sujeito a veto do usuario: **P-031** e
**P-055**, que estavam classificados como EXCECAO-1, passam a **replicar**.

## DEC-38 — P-022: publicar versao de contrato e de OG + Admin (25/08/2026)

**Resposta: opcao (a).** Novo recurso `contract_versions` — **CRUD para OG e Admin**, `-` para
Gerente e Colaborador. O recurso `contracts` (ler e aceitar) fica **exatamente como aprovado**
na matriz. O total de recursos passa de 45 para **46**.

**Isto CRIA um gate que nunca existiu** (achado A-1): `contracts_controller.rb` tem 101 linhas
e zero `before_action`/`may?`/`admin?`/`og?`/`authorize`; as rotas nao tem constraint
(`routes.rb:30-31`); o `create` (`:56-67`) so carimba `creator` e salva. Hoje qualquer
autenticado publica os Termos de Uso.

**Vai junto, no mesmo trabalho:** fechar o **mass assignment de `id` e `version`** no `permit`.

**Armadilha registrada:** `user_is_readonly` pode tirar C/U/D de `contract_versions`, mas
**nao pode** bloquear o aceite dos Termos pelo proprio usuario — senao o readonly nunca aceita
e fica trancado fora do sistema.

## DEC-39 — P-048: conta inativa nasce bloqueada e vai para revisao humana (25/08/2026)

**Resposta: opcao (a).** `is_active = 0` no legado nasce no ai9 com **`blocked_at` preenchido**,
e o usuario sai numa **lista de excecoes** para revisao humana **antes do cutover** — mesmo
tratamento do papel vazio (DEC-18 #8). `legacy_password` **nao e migrado**.

**Por que nao caiu no DEC-30:** `users.is_active` foi criada em 2021
(`20210402135252_add_is_active_to_livetat_auth_users.rb`) e **nao tem um unico leitor** — sem
`active_for_authentication?`, sem filtro em controller. "Replicar" significaria **nao bloquear
ninguem**, e toda conta desligada no Django anterior entraria no produto novo com acesso pleno.
Bloquear e revisar e reversivel; liberar por engano nao e.

`legacy_password` e hash Django (**D-106**/**D-109**, senha adivinhavel a partir do primeiro
nome + `#6230`, `legacy/u.rb:28,30`), num produto que nao tem senha (DEC-14). Nao chega ao
banco novo.

## DEC-40 — P-056: mensagem de feedback exige autenticacao (25/08/2026)

**Resposta: opcao (a).** O `POST` de mensagem passa a exigir usuario autenticado.

No legado o `create` e **isento de autenticacao de proposito**
(`feedback19/.../messages_controller.rb:6`) e o unico filtro restante faz **bypass total**
quando o formato e HTML ou JS (`auth_ux19/.../application_controller.rb:21-27`) — e o console
usa `format: :js`, entao nao bloqueia nada.

Com o cadastro publico desligado (DEC-18.7), **nao sobra visitante legitimo** para usar o canal
anonimo. `BE-531` sai da allowlist publica.

## DEC-41 — P-061: papeis do Safegold na numeracao do ai9; so OG sobrevive da base (25/08/2026)

**Contrato C3 fechado.** Duas respostas do usuario:

**1. Escala.** Os **papeis** sao os do legado, a **numeracao** e a convencao do ai9 —
**menor = mais poder**, que e como `higher_than` (`where('hierarchy_level < ?', level)`,
`user_type.rb:20`) ja compara:

| Papel | `hierarchy_level` | Legado |
| ----- | ----------------: | -----: |
| OG | **1** | 1111 |
| Admin | **2** | 998 |
| Gerente | **3** | 888 |
| Colaborador | **4** | 799 |

O de-para do ETL e **tabela explicita, nunca formula** — formula sobrevive a valor inesperado e
produz nivel plausivel e errado. **Nada em `user_type.rb` e invertido**: os scopes da base
ficam intactos (Principio 6b).

**2. Tipos da base.** `client`, `free` e `visitor` **sao removidos**; so **OG** sobrevive do
seed do ai9. Isso toca base compartilhada e exige limpar as referencias:
- `app/controllers/api/v1/base.rb:13` e `controller_helpers.rb:44-45` — `restrict_visitor_access!`
- `app/models/user.rb:82, 99, 119` — `UserType.find_by(name: 'free')` como tipo padrao
- `app/models/user.rb:147` — `client?` · `:150` — `visitor?`

Os endpoints `visitor_signup` / `visitor_signup_with_link` (`registration.rb:147,202`) e as
entradas da allowlist (`api/root.rb:45-46`) **saem de qualquer forma** pelo D-39, na S1 — o
trabalho e o mesmo e deve ser feito de uma vez.

**A colisao que originou a pergunta desaparece:** com `client` e `free` fora, nada disputa os
niveis 2 e 4.

**Disciplina de teste, nao negociavel (C3):** todo teste de hierarquia verifica os **dois**
lados — "Admin NAO edita ability de OG" **e** "Admin EDITA ability de Colaborador". Um teste que
so verifique que a trava existe **passa com o sinal invertido**, porque a trava existe: esta
apontando para o lado errado.

## DEC-42 — P-012: correcao monetaria e carencia ficam visiveis e inertes (25/08/2026)

**Resposta: opcao (c).** `interest_rate_correction` e `grace_period` continuam na tela,
**somente leitura** e marcados como **"nao aplicado"**, ate o negocio definir a formula.
Contraria o default, que era remover.

No legado os dois campos existem na migration (`20210324173930_create_renegotiations.rb:17,19`)
e no formulario, e **nenhum calculo os le** — o valor corrigido e sempre copia crua
(`renegotiation.rb:93`: `self.correct_value = self.total_debt`). E o **D-47**.

**Consequencia:** nenhum numero muda. O campo passa a **declarar** que nao esta sendo aplicado,
em vez de sugerir que esta — que era o problema real. Ficam como pendencia de negocio, nao como
funcionalidade perdida.

## DEC-43 — P-018: contagem dos limites pre-2022 fica com o usuario (25/08/2026)

**Resposta: opcao (a).** As 8 colunas `limite_*`/`taxa_*` **nascem preservadas** na migration,
o rotulo "Legado" de `FE-243` fica de pe, e o descarte e adiado para o ETL.

**Pendente de acao do usuario:** rodar a **consulta 5** da secao 5 do `perguntas-rodada-1.md`
contra a base de producao. O orquestrador **nao tem** esse dump — o unico no repositorio
(`db/seed_assets/sfg_legacy_full.sql`) e do sistema Django anterior e nao tem tabelas `risk_*`.

Se a contagem der **zero**: as 8 colunas viram `dropped` e o rotulo sai.
Se der **maior que zero**: entra a rake de conversao, senao essas linhas **somem de todos os
agregados** do ai9 e o limite deixa de existir na tela.

## DEC-44 — P-047: login social fica ligado e anunciado (25/08/2026)

**Resposta: opcao (a).** Google **e** Facebook ficam ativos e visiveis na tela de login.
Contraria o default, que era manter ligado sem anunciar.

No legado o Facebook estava morto nas duas pontas (**D-41**: `FACEBOOK_APP_ID = 0` em
`SFG/metadata.rb:4-5` e nenhum botao em view nenhuma). O que entra vem da base ai9, onde o
login social funciona.

**Consequencia registrada:** convive com **DEC-14** (entrada por codigo) e **DEC-18.7** (so por
convite) — sao **tres** superficies de identidade. O provedor social nao cria conta nova por si
so; o convite continua sendo a porta. **Tarefa de S1:** garantir que o OAuth **nao** funcione
como auto-cadastro, senao o D-39 volta por outra porta.

## DEC-45 — P-049: `username` e portado como identificador alternativo (25/08/2026)

**Resposta: opcao (c).** O ai9 passa a aceitar `username` alem de e-mail e telefone.
Contraria o default, que era so contar no dry-run.

No legado, `devise.rb:14` define `authentication_keys = [:login]` e
`livetat/auth/user.rb:108` resolve por `lower(username) = :value OR lower(email) = :value`.
O campo anuncia `placeholder="user ou e-mail"`.

**Isto encerra o risco de bloqueio de cutover** — ninguem perde acesso no dia 1 por so saber o
proprio usuario.

**Atencao, Principio 6b — toca base compartilhada.** Acrescenta uma **terceira chave de
identidade** a `users`, que outros sistemas da base usam. Requisitos da tarefa em S1/S0:
- coluna **nullable** e indice **unico parcial** (`WHERE username IS NOT NULL`), para nao
  impor nada aos outros sistemas;
- a resolucao no `MagicLoginService` **acrescenta** um ramo, sem alterar os de e-mail/telefone;
- **e-mail e telefone continuam sendo os canais de envio do codigo** — `username` identifica,
  nao recebe. Usuario com `username` e sem e-mail nem telefone **nao consegue entrar**, e por
  isso o dry-run do P-049 continua tendo que contar esse caso e listar quem cai nele.

## DEC-46 — P-057: ReceitaWS religado, com limite por usuario/dia (25/08/2026)

**Resposta: opcao (c).** O autopreenchimento por CNPJ volta, **com limite de chamadas por
usuario por dia**. Contraria o default (a), que era religar sem limite.

Backend ja esta vivo e configurado: gem no `Gemfile.linux:39`, token em
`initializers/receitaws.rb:5`, cache de 365 dias (`:10`), timeout de 10 s (`:14`), servico em
`helpers/cnpj_api.rb:3`, endpoint em `pub/providers_controller.rb:121-133`. A UI e que estava
morta em duas pontas (**D-27**): botao comentado (`providers/helper/_body.html.erb:54-56`) e
URL do JS com ERB escapado (`_body.js.erb:155` usa `<%%=`).

**Por que o limite:** a integracao e **paga por consulta** e o custo e do cliente. Sem teto, um
laco acidental na tela vira fatura.

**Sai junto, obrigatorio:** o token esta **versionado no repositorio**
(`config/application.arch.yml:12`). Vai para ENV/credentials e **precisa ser rotacionado** — ja
vazou por definicao (ver P-107).

## DEC-47 — P-058: logo do Portador volta (25/08/2026)

**Resposta: opcao (a)**, o default. Reusa a mesma pilha ActiveStorage de projeto
(`project.rb:48`) e fornecedor (`provider.rb:12`).

Estava morto por metade (**DC-10**): upload comentado (`carriers/helper/_body.html.erb:13-23`)
e exibicao comentada (`carriers/list/_widget.html.erb:3-12`), mas com handler JS vivo apontando
para input inexistente, `permit` aceitando `logo` (`carriers_controller.rb:140`) e o model com
anexo e validacoes completos (`carrier.rb:16,32-33,79-80`).

**`Company` continua sem anexo** — nao foi acrescentado (seria feature nova, opcao (c),
recusada). **Tarefa de dry-run:** contar quantos portadores tem arquivo antes de migrar binario.

## DEC-48 — P-064: CSP nasce BLOQUEANTE (25/08/2026)

**Resposta: opcao (b).** Contraria o default (a), que era `report-only` com prazo.

A base ai9 **nunca teve CSP**. Ligar bloqueante numa base que nunca teve **quebra tela em
silencio**: recurso bloqueado nao produz erro visivel, so some.

**Risco aceito conscientemente, com a demo em 28/08.** Mitigacao que passa a ser obrigatoria na
S18, ja que o modo permissivo foi recusado:
- a politica e montada a partir do que a aplicacao **realmente carrega** (fontes do Google,
  imagens data:, WebSocket do Action Cable, o proprio host da API) — nao de um template;
- **varredura de console em todas as telas** depois de ligar, em light e dark, como portao da
  tarefa. Type-check nao pega recurso bloqueado por CSP;
- **Action Cable e as fontes do Google sao os dois primeiros suspeitos** — `connect-src` e
  `font-src`/`style-src` mal configurados derrubam realtime e tipografia sem dizer nada.

## DEC-49 — P-060: as 4 rotas de auto-cadastro sao REMOVIDAS neste repositorio (25/08/2026)

**Resposta: opcao (a), com escopo explicito — remover AQUI, sem propor upstream.**

Saem da allowlist publica de `backend/app/controllers/api/root.rb:36,38,45,46` e os endpoints
sao desmontados em `api/auth/v1/registration.rb`: `pre_register`, `complete_registration`,
`visitor_signup` e `visitor_signup_with_link`.

Fecha em definitivo a porta pela qual o **D-39** voltaria sozinho, apesar do **DEC-18.7**
(entrada so por convite). Nao depende de configuracao: rota que nao existe nao reabre por
engano.

Tarefa 2.1 e 2.2 da **S1**, com o teste de regressao de 2.3. Casa com o **DEC-41**, que ja
remove os tipos `visitor`/`client`/`free` — o mesmo trabalho, feito de uma vez.

## DEC-50 — **PRINCIPIO**: este repositorio e um produto proprio, derivado do ai9 (25/08/2026)

**Declaracao do usuario:** *"esse vai ser outro app mesmo sendo derivado do ai9 tem suas regras
proprias"*.

**Isto resolve uma tensao que apareceu varias vezes** e que ate agora era travada caso a caso: o
Principio 6b da skill diz "construa SOBRE a base, nao a refatore, porque outros sistemas rodam
nela". A partir daqui, **neste repositorio, a base nao e mais compartilhada** — a branch `sfg9`
e o Safegold, um produto proprio que nasceu do ai9 e diverge dele.

### O que muda

- Codigo que antes eu tratava como intocavel por ser "da base" — `api/root.rb`,
  `registration.rb`, `user_type.rb`, `user.rb`, `controller_helpers.rb` — **pode ser alterado
  quando a regra do Safegold exigir**, sem procurar contorno por flag.
- **Perguntas cuja unica razao de existir era "isso toca a base compartilhada" deixam de ser
  perguntas.** O P-060 era exatamente uma dessas.
- O `upstream-flags.md` **muda de funcao**: deixa de ser "coisas que eu nao posso corrigir" e
  passa a ser **"achados a levar para o time do ai9"**, porque afetam o produto de origem e os
  outros derivados. Continua valendo a pena manter — o defeito de login que quebrou a base
  (`ab40bf83`) e o agendamento que so existe no Redis (#13) sao exemplos que interessam a eles.

### O que NAO muda

**Isto nao e licenca para refatorar a base.** A outra metade do Principio 6b continua de pe, e
ela e sobre **prazo**: o trabalho e proporcional ao app legado. Alterar a base **quando a regra
do Safegold exige** e migracao; sair reorganizando design system, roteamento, estado ou
servicos compartilhados **porque agora pode** transforma uma migracao de 4 dias numa
refatoracao de base. Cada alteracao na base continua precisando de uma razao escrita ligada a
uma regra do Safegold.

## DEC-50 (adendo) — a branch `sfg9` vira repositorio proprio (25/08/2026)

**Declaracao do usuario:** *"essa branch vai virar repositorio entao tera suas proprias regras"*.

Confirma e concretiza o DEC-50: nao e so "produto derivado" em espirito — a `sfg9` **se separa
do repositorio do ai9**. A divergencia deixa de ser risco e passa a ser o plano.

**Consequencias praticas:**
- Alterar codigo que veio da base **nao quebra ninguem**, porque depois do split nao ha mais
  ninguem do outro lado. A pergunta "posso mexer nisto?" sai da lista.
- O `upstream-flags.md` vira **entregavel de saida**: e o que se leva ao time do ai9 no
  momento do split, com os achados que valem para o produto de origem e para os outros
  derivados.
- **Item novo para o Phase 5 (close-out):** o procedimento do split — o que fica, o que vai,
  e o que precisa ser renomeado (`APP_NAME`, prefixo das filas do Sidekiq, namespace do
  `cron_job` no Redis compartilhado com o `apl9`, chaves de credencial).
- O que **continua valendo**: a metade do Principio 6b que fala de **prazo**. Poder mexer nao
  e razao para mexer.

## DEC-51 — P-066: o seletor de idioma sai da interface (25/08/2026)

**Resposta: opcao (b).** O i18n **nao e ligado** (DEC-09 fixou pt-BR) **e** o `LanguageSwitcher`
e **removido da tela**. Contraria o default (a), que era so nao ligar.

A base tem o runtime (`i18next`, `react-i18next`) e **nao traduz nada**: zero componentes
chamam `useTranslation`, o bundle `pt-br` tem 255 chaves de marketing de **outro produto**, e o
seletor nao troca idioma. E o **D-115**.

Botao visivel que nao faz nada e o que o tecnico do cliente clica na demo.

## DEC-52 — P-071: `observacoes` do recebivel passa a ser visivel (25/08/2026)

**Resposta: opcao (a)**, o default. O campo ganha input no formulario e exibicao.

A coluna existe (`20210315183541_create_receivable_entries.rb:43`), esta no `permit`
(`receivables_controller.rb:223`), tem tooltip orfao no YAML de ajuda
(`receivables_help_inputs.yml:35`) — e **nenhuma view a le**. O unico escritor real e o
importador: `legacy/receivable_entry.rb:56` grava `observacoes: i.bor_obs`.

Ou seja: **ha texto de negocio, vindo do sistema anterior, que ninguem nunca viu na tela.**

## DEC-53 — P-072 e P-073: renomear anexo e CONSERTADO; pagamentos vem sem tela (25/08/2026)

**Resposta do usuario:** *"vamos arrumar o renomear anexo, trazer o backend do pagamentos mas
continua desabilitado como no legado ou seja sem view por enquanto"*.

**P-072 — renomear anexo: IMPLEMENTAR** (opcao (b)). No legado nunca funcionou para ninguem:
`pub/renegotiation_attachments_controller.rb:51` chama
`@renegotiation_attachment.update_attributes(renegotiation_params)` com **dois** erros na mesma
linha — `renegotiation_params` nao existe neste controller (so
`renegotiation_attachment_params`, `:104`) e `update_attributes` foi removido no Rails 6.1 — e
o `respond_to` esta todo comentado (`:54-59`). No ai9 nasce funcionando, com tela.

**P-073 — aba PAGAMENTOS: backend SIM, tela NAO** (variante da opcao (c)). O servico e os
endpoints sao portados; **nenhuma rota de UI e criada**, espelhando o estado do legado, onde a
aba esta comentada (`renegotiations/detail/_body.html.erb:22`).

**Tres condicoes que essa escolha impoe, e que ficam registradas:**
1. **Backend sem tela nao pode ficar sem dono de autorizacao.** O endpoint existe e e
   alcancavel por URL — passa pelo `current_project!` e pela matriz igual a qualquer outro. Foi
   exatamente assim que o **P-022** (contratos sem gate) nasceu no legado.
2. **O QA do Phase 4 nao deve abrir defeito pela aba ausente.** E escolha, esta aqui.
3. O botao **"Excluir todas as parcelas"** **nao** e portado — nem backend, nem tela. Operacao
   destrutiva em massa, sem transacao, que ninguem pediu. Se for necessario, volta como acao
   explicita com confirmacao e trilha.

## DEC-54 — P-075: o percentual de aceite por contrato NAO e portado (25/08/2026)

**Resposta: opcao (b)**, o default. `Contract#accept_users` (`contract.rb:23-25`) fica sem
tela, como esta hoje.

Esta comentado nos **dois** unicos lugares em que aparecia
(`contracts/list/_widget.html.erb:18` e `contracts/detail/_body.html.erb:66`) e **nao ha
comentario explicando por que** — pode ter sido performance, pode ter sido conta errada. Na
duvida, nao ressuscitar. `BE-344` entra no ledger como `dropped` com este motivo.

## DEC-55 — P-085: a area de temas NAO e portada; marca vira token do app (25/08/2026)

**Resposta: opcao (b).** Nao ha tela de temas no ai9. Marca e paleta vivem como **tokens**
(ja entregues pela tematizacao, commit `48964d81`); light/dark fica no `ThemeToggle` que a base
ja tem.

O motor do legado **nao pintava nada**: `app_theme_template.css` tem 167 linhas e o arquivo
inteiro esta dentro de um comentario — abre `/*` na linha 1, fecha `*/` na 167, **zero regras
fora dele** (**D-55**). E o parser continuava rodando em cima disso (`app_theme.rb:207-231`),
gravando um comentario CSS inteiro em `cached_css`. A area tambem nao tinha item de menu
(**D-63**).

**Consequencia de escopo — a maior desta rodada: a fatia S17 encolhe** de "CRUD de temas com
precedencia e tokens em runtime" para **"marca em fonte unica"**, que ja esta feito. Com o
DEC-56 (`UserTheme` descartado), sobra pouco mais que a limpeza.

**O custo, registrado:** trocar o logo passa a exigir **deploy**. O usuario foi avisado da
alternativa (tema como configuracao unica editavel) e escolheu esta.

## DEC-56 — P-086: `UserTheme` e descartado (25/08/2026)

**Resposta: opcao (b).** O STI e a coluna nao sao portados; a precedencia de tema passa a ter
**dois niveis**, nao tres.

`user_theme.rb:2` declara `has_many :users` e a coluna existe
(`20200206191948_add_app_theme_column_to_livetat_auth_user.rb:3`), mas o `select` do formulario
oferece **apenas** `GlobalTheme` (`themes/form/_body.html.erb:36`,
`themes/helper/_body.html.erb:16`) — `UserTheme` e **inalcancavel pela UI** e nada nunca o
escreve.

Coerente com o DEC-55. No ai9 a preferencia por usuario ja existe como **light/dark**, que e o
controle que o usuario corporativo espera. `BE-379` e metade de `BE-380` entram no ledger como
`dropped`.

## DEC-57 — P-078: `RiskEntry` vem como tabela e model, sem tela (25/08/2026)

**Resposta: opcao (a)**, o default. Tabela e model sao portados — **o dado sobrevive** — e a
fatia R8 fica **sem endpoint e sem tela**, espelhando o legado.

No legado nao existe view nenhuma: nao ha `app/views/pub/risk_entries` nem
`.../parts/risk_entries`, o controller aponta para templates inexistentes
(`risk_entries_controller.rb:6,29,39,47,56`) e as rotas seguem no ar
(`config/routes.rb:163-164`). A aba esta comentada (`risk/_body.html.erb:30`).

**O agravante que impede portar a tela mesmo se quisessemos:** os 15 campos sao **hardcode dos
4 tipos originais** (`20210510211736_create_risk_entries.rb:7-15`) e **nao acompanham o
`RiskOperationType` dinamico** que existe desde 2022. A tela portada como esta nao funcionaria
com os tipos atuais.

**Pendente de acao do usuario:** a **consulta 4** da secao 5 (`SELECT count(*) FROM risk_entries`).
Se vier **zero**, isto vira descarte com evidencia e a fatia R8 some inteira.

## DEC-58 — P-087, P-088 e P-090: os tres restos de codigo morto SAO portados (25/08/2026)

**Resposta: portar os tres.** Contraria o default dos tres, que era descartar com evidencia.

- **P-087 · `generic_rating`** — o componente de avaliacao por estrelas entra na biblioteca do
  ai9 mesmo **sem consumidor**. No legado so existe o CSS
  (`css/pub/recyclable/generic_rating.scss`, classe `.app_rating_widget`), com **zero
  ocorrencias** em `.erb`, `.rb` ou `.js`. Entra como componente reutilizavel do design system
  (Principio 11), nao como tela.
- **P-088 · citacao aninhada (`quoted_note_id`)** — a coluna, a associacao `belongs_to :quoted`
  e a logica de `top_parent_quote_id` (`feedback19/.../note.rb:6,17-23`) sao portadas. **A UI
  continua sem preencher**, como no legado, onde nao ha campo, hidden input nem parametro AJAX
  que escreva a coluna.
- **P-090 · item de menu `reports`** — aqui portar significa portar o **mecanismo de item
  inativo** (`console/base/menu/_container.html.erb:24`), porque **o item nunca existiu**:
  nenhum item de `application_helper.rb:103-171` tem `identifier: "reports"`, entao a condicao
  nunca foi verdadeira. Nao ha rota, controller nem `when "reports"`. O item mais proximo,
  `{ identifier: "results", title: "Resultados" }`, esta **comentado** em `:118`.

**Registrado:** os tres nascem sem consumidor. O QA do Phase 4 **nao deve** abrir defeito por
nenhum deles estar sem uso — e a decisao consciente. E, pelo DEC-53 condicao 1, esquema e
endpoint sem tela continuam precisando de autorizacao e escopo como qualquer outro.

## DEC-59 — P-110: a trilha de auditoria e o `paper_trail` (25/08/2026)

**Resposta: opcao (d).** A gem `paper_trail`, ja declarada em `backend/Gemfile:47` e **sem
nenhum uso**, e ativada. Nao se cria `AuditEvent`, e `permission_audit_logs` nao ganha produtor.

Contraria o default (a). Antes do **DEC-50** esta opcao estava praticamente vetada — "ativar uma
gem na base compartilhada afeta todos os sistemas". **Com a `sfg9` virando repositorio proprio,
o argumento caiu.**

**Por que a escolha e boa:** versionamento automatico por model, sem escrever codigo de trilha em
cada servico. Cobre concessao de permissao, troca de papel, impersonacao, renegociacao, risco e
recebiveis sem uma linha por dominio. E **nao ha trilha financeira do legado a preservar**: a
caseira (`tracking.rb` + `lib/tracking_facade.rb`) cobre so jobs de template de disponibilidade
e criacao de projeto.

**Consequencias que viram tarefa da S0, e sao onde `paper_trail` costuma dar errado:**
1. **`versions` cresce rapido.** Precisa de politica de retencao desde o inicio — nao repetir o
   `login_attempts` (DEC-60).
2. **Escolher explicitamente quais models sao versionados.** `has_paper_trail` em tudo grava
   objeto financeiro inteiro a cada save e duplica a base. A lista e deliberada.
3. **`whodunnit` precisa ser preenchido a cada request**, e **precisa registrar o `true_user` na
   impersonacao** — senao a trilha diz que o Cliente Teste fez o que o OG fez, que e o oposto do
   ponto de ter trilha.
4. **`object`/`object_changes` guardam o registro inteiro.** Decidir por model o que e serializado
   — isso responde, na pratica, o **P-063** (payload enxuto x completo).
5. **`Tracking` (P-099) nao vira uma segunda trilha.** Ver DEC-63.

## DEC-60 — P-104: `login_attempts` com retencao de 90 dias (25/08/2026)

**Resposta: opcao (a)**, o default. Job de expurgo diario apaga tentativas com mais de 90 dias.

A tabela e da **base ai9** (`backend/db/schema.rb:451-460`), com `ip_address` `inet` `null: false`,
`user_agent`, 9 indices e **nenhum expurgo**. **O legado nao tem isso** — as 3 ocorrencias de
`login_attempt` la sao o metodo `invalid_login_attempt` em
`auth_ux19/.../sessions_controller.rb:42,61,80`. Passivo **adotado**, nao herdado (achado A-2).

O `sidekiq-cron` ja esta no Gemfile e o schedule versionado vai ser criado de qualquer forma
(`upstream-flags` #13) — o job entra junto, e **declarado no arquivo**, nunca pela Web UI.

Vale para `versions` do `paper_trail` (DEC-59) o mesmo raciocinio: retencao decidida no inicio.

## DEC-61 — P-107: chaves de terceiro no model `Credential`, estendido (25/08/2026)

**Resposta: opcao (b).** O `inclusion` de `backend/app/models/credential.rb:7` — hoje
`%w[openai anthropic google openai_whisper]` — e estendido para aceitar provedores nao-IA
(`receitaws`, `google_maps`). As chaves ficam no banco, encriptadas por Active Record Encryption.

Contraria o default (a) e **so e possivel por causa do DEC-50**: antes, mexer no `Credential` era
alterar model compartilhado (era a flag de upstream #12).

**Ganho:** as chaves passam a ser gerenciaveis por tela (`/admin/credentials`), sem deploy —
e o cliente troca a propria chave da ReceitaWS, que e paga por consulta (DEC-46).

**O buraco que esta escolha deixa, e que vira tarefa explicita em S18:** a chave do **Google Maps
precisa chegar ao navegador**. Chave encriptada no banco nao chega sozinha ao front. Ou um
endpoint autenticado a devolve em runtime, ou ela continua em `VITE_GOOGLE_API_KEY` no build.
**Sem isso resolvido, o mapa nao carrega** — e o `Credential` guardaria uma chave que ninguem le.
Recomendacao registrada: endpoint autenticado, para nao voltar a ter chave no bundle.

**Inegociavel, independente desta decisao:** nenhum segredo do legado entra no repositorio novo, e
os tres expostos sao **rotacionados no cutover** — ReceitaWS (valor real versionado em
`config/application.arch.yml:12`), Google Maps (hardcoded e duplicado em `SFG/metadata.rb:8,9`,
indo para o HTML) e `secret_key_base` (texto puro em `config/development_credentials.yml:1`).
E o DKIM do DEC-30/P-106.

## DEC-62 — P-116: Kaminari no backend + `PaginationPill` do apl9 no front (25/08/2026)

**Resposta do usuario:** *"kaminari mais o componente de paginacao que esta no repositorio apl9"*.

Encerra a pergunta que **nao tinha default** e que travava o bloco 0 de S5 (`s5/tasks.md:20`,
item 0.3), valendo para os 14 endpoints de lista do bloco — com o aviso "nao pode ficar meio a
meio".

**Backend: Kaminari.** A gem esta em `backend/Gemfile:85` da base e nao tem uma unica chamada em
`backend/app`. **Conferido no irmao:** o `apl9` ja usa o padrao de verdade —
`.page(params[:page]).per(params[:per_page])` em `api/v1/integrations.rb:24`,
`api/v1/partner/dashboard.rb:55`, `onboarding_templates_service.rb:17`,
`hydraulic_devices_service.rb:28`. Nao e adocao no escuro: e adotar o que ja roda em producao
num produto da mesma base.

**Front: `PaginationPill`.** Copiado de `apl9/frontend/src/components/ui/PaginationPill.tsx`
(172 linhas) e `components/mobile/MobilePagination.tsx` (53), que ja resolvem o mobile separado
(Principio 11 + `references/mobile-pwa.md`). Contrato:
`page`, `totalPages`, `perPage`, `onPageChange`, `onPerPageChange`, `loading`.

**Tarefas que isto cria, em S0:**
1. Os endpoints de lista **que ja existem na base** passam para Kaminari — senao fica meio a
   meio, que e exatamente o que a tarefa proibia. O padrao manual de `users_service.rb:49` sai.
2. O envelope de paginacao vira **um so**, e os campos batem com o que o `PaginationPill` espera.
   Hoje a base usa `set_pagination_headers` (`controller_helpers.rb:18`), por cabecalho — decidir
   cabecalho x corpo **uma vez** e valer para todos.
3. Trazer os dois componentes e adapta-los aos tokens da marca Safegold (DEC-51/tematizacao).

## DEC-63 — P-098, P-099, P-100, P-101, P-103: orquestracao, decididas pelo orquestrador (25/08/2026)

Cinco perguntas de **propriedade de fatia e ordem de execucao** — nao mudam o produto, mudam quem
constroi o que e em que ordem. Decididas como um senior decidiria, e registradas para auditoria.
Qualquer uma volta a ser pergunta se o usuario discordar.

**P-098 · `charges`/`receipts` — S6 e dona das duas tabelas.** S11 fica **so** com o item de menu
nascendo habilitado (DEC-15.1). Era o achado **A-3**: a secao "Fronteiras" de `s11/proposal.md:200-208`
ja dizia que a feature nao e de S11, e a secao "IDs adotados" do **mesmo arquivo** (`:283-290`)
reivindicava `DB-583`/`DB-584` — **as mesmas duas tabelas com IDs de inventario diferentes**.
Vale a Fronteira. `DB-583`/`DB-584` viram "mesma tabela, fechada por S6".
**Acao que sai daqui:** rodar a conferencia de cobertura **por tabela**, nao so por ID — a
checagem consolidada nao pegou este caso porque compara IDs.

**P-099 · `Tracking` — S19 e dona.** `BE-430` e `DB-591` sao de S19, que roda logo depois de S0;
S13 apenas **consome**. Tres documentos discordavam e um se contradizia sozinho: `s13/proposal.md:165-167`
e `s13/design.md:220` diziam S2; `s13/proposal.md:289` dizia S19; `s19/proposal.md:57-59`
reivindicava — e **S2 nao menciona `Tracking` em lugar nenhum**. A tarefa **3.9 de S13** ("se
ninguem criou, eu crio") **e removida**: e literalmente o padrao que produz dois donos.
**Com o DEC-59, `Tracking` NAO e uma segunda trilha:** `paper_trail` cobre auditoria de dado;
`Tracking` fica so com o que ele e no legado — registro de evento de navegacao/atividade. Se na
S19 ficar claro que os dois se sobrepoem, `Tracking` cai e sobra `paper_trail`.

**P-100 · o motor de anexos de S13 e ANTECIPADO.** O sub-bloco B de S13 sai da posicao "depois de
S6/S7" e roda **logo depois de S1**, antes de S9. Era a unica das 117 sem default **e** sem dono,
registrada como "ambiguidade de ordem no relatorio" — que e onde as coisas somem. O proprio
`s13/proposal.md:178-183` avisa: se S9 (4 anexos) rodar antes, ela **improvisa um segundo caminho
de arquivo** e a base fica com tres. Com o DEC-22 (escopo completo, paralelizacao maxima), S9
pode comecar a qualquer momento — entao a antecipacao e urgente, nao teorica.

**P-101 · `Entry` (BE-445) fica em S6.** Contrato **C4**: quem constroi e dono, e `ReceivableEntry`
nasce em S6, que roda antes de S11 na ordem de dependencia. O risco real nunca foi onde a classe
mora — era S11 herdar de classe inexistente, e a ordem resolve. Carrega junto: **"Diferenca" e
"OK" deixam de ser string pt-BR comparada por igualdade de texto e viram `enum`**; a conversao e
tarefa de S14 (`s14/tasks.md:70`).

**P-103 · Slate fica, TipTap e REMOVIDO do `package.json`.** Opcao (b), nao (a). O default era
manter e sinalizar upstream porque mexer no `package.json` da base afetaria outros produtos —
**com o DEC-50 esse argumento caiu**. `RichTextEditor.tsx` usa Slate e esta em uso; TipTap esta
declarado **sem consumidor**. Dois editores rich text na mesma base e peso de bundle e ambiguidade
para quem chegar depois. Vai junto com a limpeza de `three`/`@react-three/*`, que tambem estao no
`package.json` com zero imports (pendencia registrada no checkpoint).

## DEC-64 — P-097: o seed de demonstracao ganha fatia propria, a S20 (25/08/2026)

**Resposta: opcao (a).** Nasce **`s20-seed-demonstracao`**, com proposal, design e tasks, rodando
**em paralelo desde ja**. Era o item mais urgente da lista inteira e a unica pergunta cuja
resposta era *atribuicao de trabalho*, nao decisao tecnica.

O buraco, conferido nos tres lados: **S18** cria os alvos vazios (`s18/tasks.md:108-111`), **S14**
o exclui explicitamente (`s14/proposal.md:122`: *"S14 o **consome**"*) e **S15** tambem consome
(`s15/tasks.md:88`). Ninguem preenche. **Nao aparecia em script de cobertura nenhum porque nao tem
ID de inventario** — os scripts contam os 1439 IDs e o seed nao e um deles. E o mesmo modo de
falha das fronteiras, uma camada acima.

**Por que fatia propria e nao (d), distribuido:** o seed tem uma exigencia que nenhuma fatia
isolada consegue cumprir — **a cadeia precisa FECHAR aritmeticamente entre dominios**:
`Project -> Company -> (Carrier, limite, taxa) -> boderos -> movimentos -> saldo`. Cinco fatias
semeando cada uma a sua parte produzem cinco seeds que nao conversam, e o painel de exposicao
mostra numero que nao bate com o bordero que o gerou. Numa demo comercial, isso e pior que tela
vazia.

Desenho ja pronto e bom: `.migration-ai9/demo-seed-design.md`, 262 linhas.

**Ordem:** S20 depende dos models de cada dominio, mas o **esqueleto** (rake, estrutura,
idempotencia) comeca agora. **A S20 nao pode ser a ultima fatia** — se ela so rodar quando tudo
estiver pronto, ela vira o gargalo da sexta.

## DEC-65 — P-020: aceite de contrato volta como acao, sem bloqueio de acesso (25/08/2026)

**Resposta: opcao (b).** O botao de aceitar volta a existir e funcionar, com **banner persistente**
ate o aceite. **Sem** bloquear o acesso enquanto houver contrato pendente.

Destrava as **20 tarefas** de S12 que estavam paradas (`s12/tasks.md:110-145`).

No legado o aceite explicito esta morto por **quatro** motivos independentes, todos conferidos:
bloqueio comentado (`pub_application_controller.rb:55-63`); os dois botoes "ACEITAR" comentados
(`contracts/header/_body.html.erb:44`, `_toolbar_body.html.erb:22`) com handlers e rota `PUT`
vivos e inalcancaveis; o calculo de pendencia levantando excecao por associacao errada
(`user_decorator.rb:40` usa `source: :contract_deal`, e `ContractDeal` so tem `:contract` e
`:user`) — quem abria `/contract/:type` recebia 500; e checkboxes pre-marcados que controller
nenhum le. **Hoje nao existe nenhuma forma de aceitar um contrato pela interface.** E o **D-64**.

**Ligar o bloqueio numa demo comercial arrisca travar o cliente na primeira tela** — por isso (b)
agora. **Registrado para o cutover:** o ciclo completo com bloqueio (opcao (a)) e o comportamento
que o codigo pretendia, e entra com o prazo de tolerancia definido pelo juridico.

Com **DEC-18.7** (entrada so por convite), o consentimento passa naturalmente para o fluxo de
convite (`BE-340`, `FE-337`).

## DEC-66 — P-021: aceites historicos migram marcados, e novo aceite e exigido (25/08/2026)

**Resposta: opcao (c).** Os `contract_deals` existentes migram marcados como **`implicit_legacy`**,
preservando a data original como historico, **e** o novo aceite explicito e exigido na proxima
entrada.

O passivo tem duas origens: o `after_create` que grava aceite sem interacao
(`user_decorator.rb:2,234-240`) e o **seed que fabricou aceite retroativo para toda a base**
(`db/seeds.rb:141-148` e `:150-157`, criando um `ContractDeal` para cada usuario sem aceite).
A base atual **nao distingue "aceitou" de "foi carimbado"**.

E a unica opcao que **nao descarta registro nem finge que o registro vale**. Aditiva em relacao a
(d) se o juridico pedir reaceite geral.

**Sujeito ao juridico** — registrado como tal. Combina com DEC-65: o banner que pede o aceite novo
e o mesmo mecanismo, entao nao ha trabalho a mais.

## DEC-67 — P-015: subtipo padrao vira configuracao do tipo (25/08/2026)

**Resposta: opcao (c) para o comportamento, com (d) na carga historica.** Encerra o conflito em que
o mapa fixava (b) e a spec `BE-262` fixava (a).

**Comportamento novo:** `RiskOperationType` ganha um **subtipo padrao explicito** (`is_default` ja
existe nessa familia), e o formulario **so pergunta o subtipo quando ha mais de um**.

**Carga historica:** replica o que esta la — nao ha a quem perguntar.

O legado faz `operation_subtype_id = operation_type.subtypes.where(...).pluck(:id).first`
(`risk_operation.rb:32`) **sem `order`**, ou seja, por ordem de insercao no banco — e o formulario
**nao tem campo de subtipo** (zero ocorrencias de `subtype` em
`risk_operations/new/_body.html.erb`), entao esse e o caminho padrao de toda criacao manual.

**Por que isso importa:** o subtipo decide o bucket de limite — `is_pre = 0` entra em
**liquidavel** (`risk_control.rb:129-130`), `is_pre = 1` entra em **pre-faturamento**
(`:144-145`) — e e o bucket que aparece somado na tela de risco. Como `risk_operation_type.rb:23`
cria o subtipo "pre" **antes** do de "antecipacao" (`:31`), **o `.first` tende a cair no pre**.

**Esta e uma excecao consciente ao DEC-30, e o criterio e o mesmo do DEC-39:** replicar aqui nao
preserva um numero existente — **define, para toda operacao criada dali em diante, uma
classificacao que ninguem escolheu**. O historico e preservado; o futuro deixa de depender da
ordem de insercao de linhas num cadastro.

**Tarefa que sai daqui:** o seed de `RiskOperationType` precisa marcar qual subtipo e o padrao de
cada tipo — e a escolha do padrao **reproduz o que o `.first` fazia hoje**, para nao mudar
silenciosamente o comportamento de quem ja opera.

## DEC-68 — P-046: a cor primaria e `#2D2D2A`, confirmada (25/08/2026)

**Resposta: opcao (a).** Confirma o que ja esta no ar desde o commit `48964d81`.

Havia **quatro** valores vivos ao mesmo tempo: `#2D2D2A` (`SFG/theme.rb:32`, declarado e **nunca
lido por nada**), `#050517` (`colors.scss:1`, o que de fato **compila** para `.primary-color`),
`#373435` (o que a factory grava, `app_theme_factory.rb:17`) e `#504746`
(`ux_kit19/.../configuration.rb:14`), mais `#444444` de fallback (`app_theme.rb:200-201`).

**Decidido por medicao, nao por preferencia:** o agente de tematizacao amostrou o
`app_logo_full_original.png` pixel a pixel e achou **#292C28** — confirma o `theme.rb` e refuta o
navy do SCSS. O ouro do arquivo tambem saiu mais fechado que o declarado (`#EB9600` contra
`#FFC107`); os dois entraram, o mais fechado como hover/pressed.

Encerra o item que o **DEC-22** marcava como "a resolver antes da demo".

## DEC-69 — P-024: os 91 tooltips sao portados com o placeholder (25/08/2026)

**Resposta: opcao (b).** Contraria o default (a), que era omitir o tooltip onde nao houvesse texto.

Os tres YAML (`receivables_help_inputs.yml` com **65 chaves**,
`risk_operations_help_inputs.yml` com 13, `structured_operations_help_inputs.yml` com 13) tem as
**91 chaves com exatamente o mesmo texto**: *"So um teste de informacoes do campo pra descrever
para que serve cada campo"*.

Coerente com o **DEC-30** em sentido estrito: replicar o legado, inclusive o conteudo.

**Consequencia visivel, registrada:** numa demo, passar o mouse em qualquer campo do bordero mostra
"So um teste...". **Nao e defeito da migracao** e o QA nao deve abrir chamado. Se aparecer na
apresentacao, e conteudo pendente do cliente, nao bug — e a substituicao e trocar texto em YAML,
sem deploy de codigo.

## DEC-70 — P-037: a grade de indicadores distingue "nao lancado" de "zero" (25/08/2026)

**Resposta: opcao (a)**, o default. Celula **vazia** (ou traço) para nao lancado; `0` so para
zero efetivamente lancado.

Hoje a grade instancia `IndicatorEntry.new` quando nao ha lancamento
(`indicator_entries/list/_widget.html.erb:14`) e renderiza `entry.value.blank? ? 0 : entry.value`
nas quatro variantes (`:27,32,52,57`); como a coluna tem default `0.0`, ausencia e zero saem
identicos, e a cor tambem nao distingue.

**Excecao consciente ao DEC-30, pelo mesmo criterio do DEC-67:** nao ha numero a preservar — a
grade **nao tem linha nem coluna de total**, verificado, entao distinguir **nao muda soma
nenhuma**. Muda so a celula.

**O custo e chamar um metodo que o legado ja escreveu e esqueceu:** `beauty_value`
(`indicator_entry.rb:29-33`) ja devolve `"N/A"` para entrada sem id.

Mesma disciplina do **D-117** (`format_money` renderizando nulo como R$ 0,00): num sistema
financeiro, campo nulo e campo zerado nao podem ser indistinguiveis.

## DEC-71 — P-082: excluir lancamento de indicador vem so como endpoint (25/08/2026)

**Resposta: opcao (d).** O endpoint e portado; **sem botao na tela**, como no legado.

Encerra o conflito de default (o mapa fixava (a) "nada a portar", o empacotamento fixava (b)
"construir com tela").

No legado a rota existe (`routes.rb:84`) e a action tambem
(`indicator_entries_controller.rb:75-85`), mas **nenhuma tela a chama** — zero ocorrencias de
excluir/remover/`data-method: :delete` na pasta de views de lancamentos. Na pratica, "zerar" e
digitar `0` no campo inline; o registro continua existindo.

Com o **DEC-70**, o endpoint passa a ter efeito visivel de verdade: apagar devolve a celula ao
estado **"nao lancado"**, que agora e distinguivel de zero. Antes das duas decisoes juntas,
excluir e zerar produziam exatamente a mesma tela.

**Vale a condicao 1 do DEC-53:** endpoint sem tela continua alcancavel por URL e **precisa de
autorizacao e escopo de projeto** como qualquer outro. Foi assim que o P-022 nasceu no legado.

## DEC-72 — P-031: excluir tarifa passa a ser pendente ate salvar o bordero (25/08/2026)

**Resposta: opcao (b)**, o default. O botao de remover tarifa marca a exclusao como **pendente no
formulario**; ela so acontece no **Salvar** do bordero, dentro da mesma transacao que recalcula os
agregados. **Cancelar volta a desfazer.**

No legado, o botao (`receivables/new/_body.html.erb:484`) dispara um `DELETE` direto ao confirmar
o modal (`new/_body.js.erb:663-681`, linha 674), **fora de qualquer submit**. O servidor apaga
(`receivable_taxes_controller.rb:15-24`) e **nao recalcula o bordero pai** — os `tarifas_*` so se
corrigem no proximo save. Entre uma coisa e outra, o bordero exibe total errado.

**Excecao consciente ao DEC-30, mesmo criterio do DEC-70:** o que se preserva nao e um numero, e
uma **janela em que o numero esta errado**. Nao ha valor a replicar — ha um intervalo de
inconsistencia.

Pelo contrato **C2**, o recalculo no save ja passa pelo `ReceivableCalculator`, o mesmo servico
que a previa da tela chama. Nao ha caminho novo de calculo.

## DEC-73 — P-055: a inversao Concluido/Fechado e REPLICADA (25/08/2026)

**Resposta: opcao (b).** Vale o DEC-30. Contraria o default (a), que era corrigir.

Os dois estados existem e sao distintos (`feedback19/.../state.rb:11-12`), e estao **trocados
entre si**: no `update`, escolher "Concluido" grava **Fechado**
(`messages_controller.rb:118-119`); a action `close` (`:156-159`, `PUT /messages/:id/close`)
grava **Concluido**. Inversao dupla, nao typo de um lado.

**Consequencia registrada:** o comportamento vai para o produto novo como esta. **Golden test trava
os dois sentidos** — inclusive a inversao — e reprova quem "consertar" sem passar por uma DEC.
Linha no `improvements-log.md` como melhoria **declinada**, para o QA nao ler como defeito da
migracao.

## DEC-74 — P-050: o indicador de verificacao e REPLICADO como esta (25/08/2026)

**Resposta: opcao (c).** Vale o DEC-30. Contraria o default (a).

A escada de quatro degraus (`auth19/.../user_info.rb:53-74`) vai como esta, com o degrau
"Maxima" dependendo so de `is_phone_checked` (`:59`) — flag que **nenhum fluxo liga**, porque nao
existe verificacao de telefone no legado; a unica escrita e mass-assignment pelo formulario
(`registrations_decorator.rb:104`). O degrau maximo segue **inalcancavel**, e o indicador segue
**decorativo** (a unica leitura fora da exibicao e `user_decorator.rb:272`, num JSON).

**ATENCAO — armadilha que esta replica cria, e que vira tarefa de S1 e S14.** No legado, com
`is_phone_checked = 1` o campo de telefone **trava para sempre**
(`my_account/parts/phone/_container.js.erb:14-16`, `prop('readonly')`). No ai9 **o telefone e canal
de login** (DEC-14). Se o ETL trouxer usuarios com a flag ligada, essas pessoas **nao conseguem
trocar o proprio telefone** — e quem perder o numero perde o acesso, sem caminho de autoatendimento.

**Duas condicoes, portanto:**
1. O dry-run **conta** quantos usuarios vem com `is_phone_checked = 1` e os lista.
2. **A trava de edicao NAO e replicada** — o indicador e; a impossibilidade de trocar o telefone
   nao. Replicar a trava seria portar um bloqueio de acesso, o que cai na excecao de seguranca do
   proprio DEC-30. Se o usuario quiser a trava tambem, e uma linha para reverter.

## DEC-75 — P-052: os dois e-mails de senha NAO sao portados (25/08/2026)

**Resposta: opcao (b).** Contraria o default (a), que era preservar os gatilhos com texto novo.

"Perdeu a senha?" e "Nova senha configurada" saem inteiros — nem o texto, nem o gatilho.
`BE-481` e `BE-482` entram no ledger como `dropped`.

Coerente com **DEC-14**: o produto nao tem senha, entao os dois e-mails perdem o objeto.

**Consequencia registrada, e ela e de seguranca:** o gatilho de *"sua credencial mudou"* some
junto. **O usuario deixa de ser avisado quando o acesso dele e alterado** — que e o sinal por onde
uma pessoa percebe que alguem mexeu na conta dela. Ficam os 3 e-mails vivos da base (convite,
codigo de acesso, boas-vindas), e nenhum deles cobre isso.

Foi apresentado ao usuario nesses termos e ele escolheu assim. Se depois se quiser o aviso, ele
volta como **notificacao de alteracao de conta** — que e o nome certo num produto sem senha — e nao
como reaproveitamento destes dois.

## DEC-76 — P-051: `Disk` na demo; provedor e item obrigatorio do runbook (25/08/2026)

**Resposta: opcao (c)**, o default. Para sexta, `Disk`. A escolha do provedor (S3/GCS/R2) vira
**item obrigatorio do runbook de cutover, com data**, nao recomendacao.

A base so tem disco local: `backend/config/storage.yml` declara apenas `local` e `test`, e
`production.rb:10` faz `config.active_storage.service = :local`. Ou seja, **producao grava anexo
no disco do container** — e sem volume persistente **o anexo desaparece no primeiro redeploy**.

**O que esta em risco nao e avatar:** sao os **documentos de renegociacao**, que sao documento
financeiro (`s9/design.md:179-183`), mais os logos que o DEC-47 acabou de religar.

**Registrado como risco aceito com prazo, nao como pendencia vaga.** O runbook de S14 recebe:
provedor escolhido, credencial rotacionada, e a **migracao dos binarios ja gravados em `Disk`
durante a demo** — se alguem subir arquivo na apresentacao, ele precisa sobreviver.

## DEC-77 — P-062: a trilha global e visivel a OG e Admin (25/08/2026)

**Resposta: opcao (a)**, o default. Trilha **global** (indice de tudo que aconteceu) restrita a
**OG e Admin**; o **historico do proprio objeto** fica visivel a quem ve o objeto.

Entra na matriz de autorizacao como recurso proprio. Combina com o DEC-59: o `paper_trail` grava
tudo, e o que esta decisao controla e **quem le**.

## DEC-78 — P-063: a trilha guarda o payload COMPLETO (25/08/2026)

**Resposta: opcao (b).** Contraria o default (a), que era payload enxuto.
`object` e `object_changes` do `paper_trail` guardam **a foto inteira do registro** em cada versao,
para todos os models versionados.

**Auditoria mais forte:** da para reconstruir o estado de qualquer registro em qualquer ponto do
tempo, nao so o delta. Num sistema de credito, e o que responde "como estava esta operacao no dia
que o limite estourou".

**O custo e real e vira tarefa, nao surpresa.** Estas quatro condicoes ficam obrigatorias na S0,
porque payload completo sem elas e como uma base de auditoria fica maior que a base de producao:
1. **A lista de models versionados e deliberada e curta.** `has_paper_trail` em tudo, com foto
   completa, duplica a base a cada save. Entram os que importam para auditoria financeira e de
   acesso — operacao de risco, recebivel, renegociacao, limite, usuario, papel, permissao,
   contrato. **Nao** entram tabelas de alto volume de escrita nem catalogo.
2. **Retencao definida desde o inicio**, junto com o DEC-60 (`login_attempts`, 90 dias). Payload
   completo com retencao infinita e o pior dos dois mundos.
3. **`skip` e `ignore` para o que nao deve ser copiado** — `jti`, tokens, `updated_at` — e
   **atencao especial a dado pessoal**: a foto completa de `users` duplica CPF/CNPJ e endereco em
   cada versao, o que interage com o passivo de LGPD do DEC-60.
4. **`object`/`object_changes` em `jsonb`**, com indice so onde houver consulta real.

## DEC-79 — P-059: `default_position` e criada no ai9 (25/08/2026)

**Resposta: opcao (c).** A coluna nasce no schema do ai9, independente do que exista em producao, e
a busca de padroes de disponibilidade ordena por ela — como o legado pretende.

`pub/availability_templates_controller.rb:22` ordena por `default_position` e a coluna aparece em
tres views, mas **nenhuma migration a cria** (as migrations criam `position` e `parent_position`,
`20210420180734_create_availability_templates.rb:22,24`).

**Vantagem de decidir assim:** para de depender de uma consulta ao dump que eu nao consigo rodar.
Se a coluna existir em producao, o ETL a carrega; se nao existir, ela nasce vazia e a ordenacao
cai na hierarquia — nos dois casos o codigo do ai9 funciona.

**O DEC-04 continua em aberto** e nao e fechado por esta decisao: se a coluna existir em producao,
e a **segunda** prova de schema fora do versionamento (a primeira e `contracts.description`,
**D-108**), e isso muda a confianca no `schema.rb` como fonte da verdade do ETL. **Tarefa do
dry-run:** comparar o schema real com o esperado e listar toda divergencia, nao so esta coluna.

**Achado adjacente, independente, que vira tarefa de S11:** a linha `:21` da mesma action monta o
`where!` com fragmento SQL malformado (`"title #{Dev.ilike} "`, sem placeholder) — a busca por
texto tem um segundo defeito que nao tem nada a ver com a coluna.

## DEC-80 — P-067: prova de aceite completa, sem versionamento imutavel (25/08/2026)

**Resposta: opcao (b).** `contract_deals` passa a guardar **usuario, versao, data/hora, IP,
user-agent e hash do texto aceito**, com indice unico `(user_id, contract_id)` e **exportador de
prova**. O documento **continua editavel no lugar** — a opcao (d), com versionamento imutavel,
foi recusada.

Hoje a tabela guarda so `user_id`, `contract_id`, `created_at`, `updated_at`
(`20180405164055_create_contract_deals.rb:3-8`). E o **D-65**.

**Requisito novo, nao paridade** — o legado nao tem nada disso.

**A lacuna que a opcao (b) deixa, e que fica registrada porque e juridica:** o **hash prova o
texto**, mas o texto vive em `action_text_rich_texts` e **pode ser editado no proprio registro**.
Se alguem editar o contrato depois de aceites gravados, o hash antigo **deixa de bater** com o
texto atual — e o sistema sabe **que mudou**, mas nao consegue exibir **o que foi aceito**.

**Duas mitigacoes que viram tarefa de S12, ja que o versionamento imutavel nao entra:**
1. **Guardar o texto renderizado junto com o hash**, ou ao menos o corpo no momento do aceite. E
   o que transforma "sei que mudou" em "sei o que ele leu", sem exigir versionamento.
2. **Alertar ao publicar**: editar um contrato que ja tem aceites gravados avisa quantos aceites
   ficarao com hash divergente. Com **DEC-38** (so OG e Admin publicam), o aviso chega a quem
   pode decidir.

Mitigacao 1 e barata e cobre o essencial. Se o juridico pedir prova forte, (d) volta a mesa.

## DEC-81 — P-084: os headers `X-LAA-*` sao descartados; fica o `Bearer` (25/08/2026)

**Resposta: opcao (a)**, o default. O contrato de token de usuario da engine sai — o **JWT o
substitui** — e `ClientApplication` continua funcionando por `Authorization: Bearer`.

Os headers `X-LAA-Agent`/`X-LAA-Token` sao definidos em
`auth19/lib/livetat/auth/configuration.rb:15-16` e validados por inteiro em
`auth_ux19/.../application_controller.rb:16-17,23-25`. Os dois controllers de API do proprio app
ja leem **so o token**, sem o agent
(`api_application_controller.rb:7`, `api_private_application_controller.rb:7`).

**O usuario confirmou que nao ha consumidor externo** — era a informacao que so ele tinha, porque
um chamador de fora nao aparece neste repositorio. `BE-004` entra no ledger como `dropped`.

**Se aparecer um consumidor depois do cutover, ele quebra.** A reversao e o periodo de transicao
da opcao (b), e custa mais depois do que agora.

## DEC-82 — P-070: `resource_kinds` nasce como tabela; superficie bloqueada (25/08/2026)

**Resposta: opcao (a)**, o default. A **tabela e o seed nascem** — preservar dado e barato, perde-lo
e irreversivel — e os **9 IDs de superficie ficam bloqueados** ate a contagem.

A entidade tem CRUD completo e e **inalcancavel pelo menu** (`application_helper.rb:153` so tem
`resource_sources`); a coluna `receivable_entries.resource_kind_id` existe
(`20210315183541_create_receivable_entries.rb:11`) e esta no `permit`
(`receivables_controller.rb:191`), mas **nao ha campo no formulario** e `receivable_entry.rb`
**nao declara `belongs_to :resource_kind`**. Os flags `is_conta_corrente` e `is_unique` nao tem
leitor de regra. E ela **nao participou da importacao** (`legacy.rb:2-15` lista `ResourceSource`,
nao `ResourceKind`).

**Pendente de acao do usuario:** consulta 2 da secao 5 —
`SELECT count(*) FROM receivable_entries WHERE resource_kind_id IS NOT NULL`.
Zero -> os 9 IDs viram `dropped` **com evidencia** e a remocao da tabela e **tarefa explicita
(13.4), nunca por omissao**. Maior que zero -> a superficie desbloqueia.

**A mesma consulta resolve o P-041** (os dois cadastros indistinguiveis): se `resource_kinds` cair,
aquela pergunta desaparece junto.

## DEC-83 — P-065: `WhatsappPage` ganha rota para OG e Admin (25/08/2026)

**Resposta: opcao (a)**, o default. A tela de pareamento por QR ganha rota, **gateada por OG e
Admin** (`s2/design.md:101`).

`frontend/src/app/pages/WhatsappPage.tsx` existe na base e **nao tem rota**. E dela que
`EvolutionConnection.send_message` depende, via `PolemkInstance.first`.

**Nao e conveniencia, e continuidade de um canal de login:** com o **DEC-14**, WhatsApp e uma das
portas de entrada. Sem a tela, quando a sessao da instancia expirar **o canal cai e ninguem
consegue reparear pela interface** — o cliente fica dependendo da Livetat para voltar a entrar.

Combina com o **DEC-38** e o **DEC-77**: OG e Admin e o par que ja concentra as operacoes
administrativas do produto.

## DEC-84 — P-095: copia do disco do legado e PRE-REQUISITO de cutover (25/08/2026)

**Resposta: opcao (b)**, com (c) como rede. Obter `rsync`/`tar` de `public/system/` do servidor
legado vira **pre-requisito bloqueante** do cutover, no runbook de S14. O relatorio de "arquivo
nao recuperado" (c) fica como rede de seguranca, nao como plano.

Sao **11 anexos** (44 colunas de paperclip) em `public/system/:attachment/:id/…` **no disco da
maquina**, com o path configurado inline em cada model: avatar de usuario, imagem de `Picture`,
anexo de renegociacao, logo de fornecedor e de portador, avatar de projeto e os 4 arquivos de tema.

**Por que bloqueante e nao "resolver depois":** anexo de renegociacao e **documento financeiro**.
Registro apontando para arquivo inexistente e **pior que ausencia declarada** — quem abre a
renegociacao ve um anexo listado e um download que falha, e conclui que o sistema novo perdeu o
documento.

**Nao e decisao de desenho, e dependencia externa** — mesma natureza do dump de producao que trava
P-018, P-070 e P-091. Vai para a lista de coisas que so o usuario consegue obter.

Nao trava a demo: o seed de demonstracao (S20) gera os proprios arquivos.

## DEC-85 — P-096: a "Chave de Integracao" do indicador fica como esta (25/08/2026)

**Resposta: opcao (a)**, o default — **na duvida, nao mexer**. A chave continua obrigatoria,
derivada do titulo (`indicator.rb:44`), **sem unicidade** e **sem mudanca de formato**.

Dentro do repositorio **nada le `indicator.key`** para integrar — as ocorrencias sao encanamento:
geracao, denormalizacao (`:49`, `indicator_entry.rb:25`), campo no formulario, `permit` e mensagem
de erro. Mas o nome anuncia consumidor externo, e **nao ha como confirmar de dentro do codigo** se
ha BI ou planilha lendo.

**Escolha conservadora e correta:** impor unicidade quebraria o consumidor externo **em silencio**
— e silencio e o pior modo de falha de integracao.

**O que fica de divida, registrado:** um campo chamado "Chave de Integracao" sem garantia de
unicidade nem de estabilidade e armadilha para quem chegar depois. Fica em
`.migration-ai9/improvements-log.md` como melhoria adiada, com o gatilho escrito: **no dia em que
se confirmar que nao ha consumidor externo, a opcao (c) — remover o campo — volta a mesa**.

**Corrigido de qualquer forma (defeito, nao mudanca de contrato):** `indicator.rb:68-69` devolve
`"integration_key"`, coluna que **nao existe** em `indicators` (a coluna e `key`) — a ordenacao
por chave esta quebrada hoje. Isso e o achado **A-5** e nao tem consumidor externo possivel, porque
nao funciona.

## DEC-86 — P-094: tipos de garantia sao semeados como provisorios (25/08/2026)

**Resposta: opcao (a)**, o default. O mecanismo e portado e o **seed de demonstracao (S20)** semeia
tipos plausiveis, **marcados como provisorios**.

A tabela existe (`20220627125208_create_project_guarantee_types.rb`) e **nenhum seed a popula** —
zero ocorrencias de "guarantee" em `db/seeds.rb`, nada em `db/factories/`. Mas a UI depende dela:
CRUD completo, o select de garantias e alimentado por `ProjectGuaranteeType.all`
(`project_guarantees_controller.rb:52`) e ha item de menu (`application_helper.rb:157`). No legado,
**o select sobe vazio** ate alguem cadastrar a mao.

**Nao ha nada a migrar — o conteudo e novo.** Os tipos semeados sao suposicao do orquestrador
(aval, penhor, alienacao fiduciaria, cessao de recebiveis e afins), **explicitamente provisorios**,
para que um select vazio nao apareca na tela de projeto durante a demo.

**Pendencia declarada:** a lista real e do cliente. Substituir e trocar linhas de seed, sem
migration nem deploy de codigo.

## DEC-87 — P-089: Google Analytics entra desligado e corrigido (25/08/2026)

**Resposta: opcao (b).** Contraria o default (a). Encerra o conflito em que `s2/design.md:103`
decidia **nao injetar** e `s13` decidia **portar desligado** — duas fatias implementando coisas
diferentes.

O snippet **GA4 correto** entra no repositorio, **desligado por configuracao**, pronto para ligar.

No legado ele e injetado na **primeira linha de quatro entrypoints, sem nenhum consentimento**
(`console/_index.js.erb:1`, `start/_index.js.erb:1`, `users/sessions/_new.js.erb:1`,
`contracts/_index.js.erb:2` — este sem nem o guard de deduplicacao). E esta **quebrado**: o ID e
GA4 (`GOOGLE_ANA_APP_ID = "G-7E78XXZX5X"`, `SFG/metadata.rb:7`) e o snippet e Universal Analytics
(`livetat/analytics/_google.js.erb:1-8`, `analytics.js` + `ga('create', …)`). **Um ID `G-` nao
funciona com `ga()`: hoje nao coleta absolutamente nada.**

**Tres condicoes, porque snippet de terceiro desligado num sistema de credito e uma linha que
alguem liga por engano:**
1. **Nasce `false`**, controlado por ENV — nunca por hardcode.
2. **Consentimento antes da primeira coleta**, se um dia for ligado. O legado nao tinha, e sistema
   interno com dado financeiro mandando telemetria a terceiro e decisao do **cliente**.
3. **O CSP do DEC-48 nasce bloqueante e NAO libera o dominio do Google Analytics** enquanto a flag
   estiver desligada. Ligar a flag passa a exigir tambem alterar o CSP — duas travas, nao uma.

## DEC-88 — P-024 REVISTO: os 91 textos de ajuda sao ESCRITOS (25/08/2026)

**Substitui o DEC-69.** O usuario, informado de que os 91 tooltips do legado tem **um unico texto
distinto** (conferido nos tres YAML: 65 + 13 + 13 chaves, todas com *"So um teste de informacoes
do campo pra descrever para que serve cada campo"*), respondeu: *"se nao tem textos faca voce os
textos explicando os campos"*.

**O mecanismo e portado E o conteudo e escrito.** Nao e invencao de regra de negocio: **a
semantica de cada campo esta no codigo** — as formulas de `receivable_entry.rb`, `risk_operation.rb`
e `structured_operation.rb` definem exatamente o que cada um significa e como entra na conta.

**Disciplina obrigatoria, senao isto vira desinformacao pior que o placeholder:**
1. **Cada texto sai da formula, nao do nome do campo.** Se `prz_med_pond_emp` entra em
   `calc_valor_liq_correto` somado ao `float_acordado`, o tooltip diz isso — nao "prazo medio
   ponderado da empresa", que o rotulo ja diz.
2. **Onde o campo participa de defeito ja decidido, o texto NAO mente e NAO denuncia.** Descreve o
   comportamento real. Ex.: o CET do banco (DEC-32) e zerado quando o prazo da **empresa** e zero —
   o texto descreve a condicao como ela e.
3. **Campo que o operador erra vem primeiro:** CET, float, prazo medio ponderado e as tarifas do
   bordero. Sao os que motivaram a decisao.
4. **Texto curto.** Tooltip nao e documentacao — uma ou duas frases, dizendo o que o campo faz na
   conta e o que muda se for preenchido errado.
5. **Nada de inventar unidade nem faixa** que o codigo nao define. Onde a regra nao existir
   (P-026: a taxa nao tem validacao de faixa), o texto **nao insinua** que existe.

Substituir depois continua sendo trocar YAML, sem deploy.

## DEC-89 — P-038: o titulo do indicador continua em CAIXA ALTA sem acento (25/08/2026)

**Resposta: opcao (b).** Vale o DEC-30. Encerra o conflito em que o mapa fixava (b) e a spec de
`BE-321` fixava (a).

`indicator.rb:39` mantem `self.title = I18n.transliterate(self.title).upcase` num
`before_validation` **sem `on:`** — ou seja, em **todo** save, e duplicado em `:43` no callback de
criacao. A `key` deriva do mesmo (`:44`).

**Consequencia registrada, e ela nao tem volta:** cada titulo digitado dali em diante **perde o
acento permanentemente** — nao e formatacao de exibicao, e transformacao do dado gravado.
"Inadimplencia" vira "INADIMPLENCIA" no banco.

Como os acentos do dado legado **ja se perderam**, o historico chega em caixa alta de qualquer
forma e a tela fica **homogenea** — que e o ganho pratico desta escolha.

Golden test trava o comportamento, inclusive a transliteracao, e reprova quem "consertar" depois.

## DEC-90 — P-105: o log de e-mail guarda so metadados, com expurgo de 180 dias (25/08/2026)

**Resposta: opcao (a)**, o default. `email_logs` guarda **remetente, destinatario, assunto, status e
timestamp**. **Sem corpo.** Expurgo em 180 dias.

**Excecao consciente ao DEC-30, e a mais facil de justificar da lista:** no legado
`livetat_mailer_contacts` guarda `message` — a coluna foi **promovida de `string` para `text`
justamente para caber o corpo** (duas migrations de 19/05/2017) — e cada envio grava o corpo antes
de enfileirar (`mailer19/lib/livetat/mailer19/grind_mailer.rb:5-13,27,47,67,85`, mais 4 pontos em
`feedback19/.../grind_mailer_decorator.rb`), **inclusive e-mails de credenciais**
(`mailer_decorator.rb:4`). **Nao ha expurgo**: zero ocorrencias de purge/cleanup/`destroy_all` em
`lib/`, `app/jobs` ou no engine.

**No ai9 os 3 e-mails vivos sao de identidade — e o codigo de acesso E a credencial.** Guardar o
corpo seria guardar a credencial em texto puro por outro nome, e com retencao infinita.

O job de expurgo entra no `config/schedule.yml` versionado, junto com o do DEC-60
(`login_attempts`, 90 dias) — mesmo mecanismo, uma tarefa so.

## DEC-91 — P-109: os logos sao anexados direto nos models (25/08/2026)

**Resposta: opcao (a)**, o default. `has_one_attached` em `Project#logo`, `Carrier#logo` e
`Provider#logo`, reusando a mesma pilha **ActiveStorage + `image_processing`** que o `Medium` ja usa.

O `Medium` foi recusado pelo motivo certo: a tabela `media` **nao tem dono nem escopo**, entao um
logo criado por la apareceria na galeria `/media` para **qualquer autenticado**, misturado com
imagem de conteudo. Com o **DEC-50** daria para alterar o `MediumService` e filtrar, mas isso e mais
trabalho do que anexar direto — e o escopo por projeto (contrato **C1**) sai de graca quando o anexo
pertence ao proprio model.

**Paperclip nao e portado** em nenhuma hipotese. `Company` continua **sem anexo** (DEC-47).

Combina com o DEC-76: os binarios ficam em `Disk` na demo e o provedor e item obrigatorio do
runbook.

## DEC-92 — P-091: a geolocalizacao e DESCARTADA (25/08/2026)

**Resposta: opcao (c).** Os **12 IDs** saem agora, com evidencia: `DB-592`, `DB-431`, `DB-480`,
`OPS-481`, `OPS-482`, `FE-483` e `BE-435`..`BE-440`. Contraria o default (b), que era construir e
descartar depois se a contagem viesse zero.

**A evidencia que sustenta o descarte, e ela e forte:** o model existe e e grande
(`app/models/geolocation.rb`, com calculo de distancia via Geocoder em `:164-171`), mas **nenhum
model declara `has_one`/`has_many :geolocation`** — zero resultados no repositorio inteiro. E
`geolocatable` so aparece **dentro do proprio `geolocation.rb`** (`:6,7,9,175`) e na migration
(`20160302002809_create_geolocations.rb:4`). **A associacao polimorfica nao tem lado inverso
nenhum** — nada no sistema le nem escreve geolocalizacao.

**Economia direta:** as tarefas 6.5–6.9 de S13 saem, e o maior portao de escopo por consulta unica
da migracao fecha **sem precisar da consulta**.

**O risco, declarado:** se houver linhas em `geolocations` no banco de producao, **o dado
geografico nao e migrado**. Sendo uma tabela que nada le nem escreve, o dado — se existir — e de
2016 e esta orfao desde entao.

**Fecha o P-092 junto** (trilha de auditoria com geolocalizacao, `BE-433`): sem geolocalizacao, o
calculo nunca dispararia. `BE-433` entra no ledger como `dropped` pela mesma evidencia. A action
ja estava quebrada em tres frentes (achado **A-5**): `@tracking` nunca e carregado, `Tracking` nao
declara a associacao, e nada e salvo nem recalculado.

**Correcao ao material registrada (A-24):** o mapa dizia "9 IDs" e enumerava 14; a lista
autoritativa e a da fatia (`s13/tasks.md:26-30`), com **12**. Os dois extras que o mapa citava
(`OPS-621`, `OPS-483`) **nao entram neste descarte** e seguem para conferencia a parte — `OPS-483`
em especial, que e o select Pais->Estado->Cidade e **funciona sem geocoding**.

## DEC-93 — P-108: as variantes de logo sao derivadas dos arquivos existentes (25/08/2026)

**Resposta: opcao (a)**, o default. Branca, monocromatica e **maskable** sao geradas a partir dos
arquivos que existem, **registradas como derivadas**.

**A premissa do material estava errada, em dois documentos (achado A-26):** o mapa e as fatias
S16/S17 afirmavam que `app_symbol.png` e `app_text.png` "nao existem no repositorio". **Os dois
existem** — `app/frontend/images/brand/app_symbol.png` (1,1 KB) e `app_text.png` (1,3 KB) — e a
factory de tema os usa (`app_theme_factory.rb:22-24`), o que so funciona porque estao la.

**O defeito real e outro:** em `SFG/theme.rb:47-57` as variantes `_WHITE` e `_MONO` apontam
**todas para o mesmo arquivo** da versao normal. Nao existe logo branco nem monocromatico de
verdade.

**Parte disto ja esta feito** (commit `d068d3dc`): os icones e o favicon foram regerados do
`app_symbol.png`, com **remocao de fundo por alpha real** — a formula por luminancia apagava o
ouro junto — e o maskable ganhou arquivo proprio **com fundo cheio**, porque maskable transparente
o Android recorta errado. Falta a variante monocromatica.

Se o manual de marca aparecer, os originais vencem a derivacao — e a troca e de arquivo.

## DEC-94 — P-111: os nomes de coluna de 2022 sao adotados (25/08/2026)

**Resposta: opcao (a)**, o default. O ai9 nasce com `installments_main_value`, `main_value` e
`installment_paid_value_with_interest_cm`. **Sem view de compatibilidade** — o usuario confirmou
que nao ha consumidor externo lendo os nomes antigos.

Sao **tres** renomeacoes em tres tabelas, todas de 29/04/2022, e **so uma** e em `renegotiations`
(o material dizia que eram tres na mesma tabela):
`renegotiations.total_value -> installments_main_value` (`20220429122226`),
`renegotiation_installments.value -> main_value` (`20220429122346`),
`renegotiation_payments.value -> installment_paid_value_with_interest_cm` (`20220429122419`).

**O que mais importa nao e o nome, e a semantica:** `total_value` era *"R$ Total da divida"* e
virou *"soma do principal das parcelas"* — o comentario legado em `renegotiation.rb:273` confirma.
**Qualquer relatorio antigo que somasse essa coluna passou a somar outra coisa desde 2022**, e isso
independe da migracao. Fica registrado para o caso de aparecer divergencia historica em conferencia.

## DEC-95 — P-079: entra o aviso de estouro de limite NA TELA (25/08/2026)

**Resposta: opcao (b).** Contraria o default (a), que era nao entrar.

Quando a utilizacao passa do teto, a tela de risco mostra o aviso. **Feature nova** (DEC-09) — o
legado nao tem polling em tela nenhuma deste bloco e nao renderiza grafico algum
(`vendor/doughnut` e pendurado no `global` em `vendor/js/index.js.erb:31,37` e **zero views o
instanciam**).

**Custo baixo, e o motivo importa:** o numero **ja e calculado** pelo motor de limites (contrato
C2, `Risk::Calculator`). O aviso e leitura, nao conta nova — **e proibido o aviso recalcular por
conta propria**, senao nasce a segunda fonte de verdade que o C2 existe para impedir.

**Sem polling** (Principio 10): o estado vem do mesmo carregamento da tela, e atualizacao ao vivo,
se houver, e por Action Cable.

Entra como `NEW-004` no ledger, marcado **`new`** — o QA do Phase 4 **nao deve procura-lo no
legado**. Convive com o `NEW-002` (dashboard com "limites proximos do teto"): o dashboard e a
visao agregada, este e o aviso no ponto de decisao.

## DEC-96 — P-102: a arte do carousel esta ENCERRADA (25/08/2026)

**Resposta: encerrada.** O usuario forneceu as 5 imagens em 25/08/2026 e elas estao aplicadas
(commit `d068d3dc`), na ordem dos slides: risco, recebiveis, limites, renegociacao, indicadores.

PNG de 1,7 MB convertidos para **WebP a 84, totalizando 210 KB** — o que importa na primeira tela
que carrega. A arte virou o fundo do painel, com veu em gradiente: sem ele o titulo branco sumia no
slide claro da renegociacao (conferido renderizando).

`THEME-07` do `improvements-log.md` fica **fechado**. O componente aceita `image` por slide, entao
trocar qualquer uma e substituir arquivo, sem mexer em codigo.

## DEC-97 — P-115: `polemk_webhooks` FICA, e a premissa da pergunta estava errada (25/08/2026)

**Resposta do usuario:** *"pode deixar e polemk_... sao modulos da nossa empresa que esta
desenvolvendo"*.

**Corrige o material.** A pergunta partia de que "polemk" era **marca de outro produto vazando
para dentro do Safegold** — e nao e: e o **prefixo de modulo da propria empresa**, deliberado. Nao
ha nada a renomear, nem divida a registrar.

`polemk_webhooks` continua como esta em `api/entities/polemk_instances.rb:26`, em
`WhatsappPage.tsx:117,304-305`, no model, no servico, no seed, nas duas migrations e nos tres
specs. O mesmo vale para `PolemkInstance` e para os demais identificadores com esse prefixo.

**Anotado como correcao a `upstream-flags.md` e ao `s12/design.md`:** onde o material tratar
`polemk_*` como resquicio a limpar, esta errado — e nomenclatura de modulo, nao heranca acidental.

## DEC-98 — P-117: dark mode entra, e cada tela nasce conferida nos dois modos (25/08/2026)

**Resposta: opcao (a)**, o default. Confirma por escrito o que ja estava entregue e verificado.

A tematizacao (commit `48926d81`... ver `48964d81`) entregou a marca Safegold nos **dois** modos:
`globals.css` com os tres blocos completos (`:root`, `.dark`, `.surface-dark`), escala de
superficie no escuro corrigida para `background` 9% -> `card` 12% -> `popover` 18%, e o
`ThemeToggle` da base no ar.

**O custo que esta decisao assume, e ele e de QA, nao de codigo:** **toda tela do Phase 3 nasce
conferida em light E dark** — e a conferencia e **renderizando e olhando**, nao type-check. A
regressao dos dropdowns provou isso: `tsc --noEmit` passava limpo com um popover invisivel.

Vira criterio de aceite das fatias de frontend: tela sem confirmacao visual nos dois modos **nao
fecha tarefa**.

## DEC-99 — OG e Admin enxergam TODOS os projetos, sem participação (25/08/2026)

**Pedido do usuario:** *"og e admin deveria ver todos os projetos e poder selecionalos"*.

Ate agora **todo** projeto era filtrado por `memberships`, inclusive para quem administra o
sistema. Na pratica isso significava que o OG semeado tinha **zero participacoes** e o seletor de
projeto nem aparecia para ele.

**A regra:** `Project.visible_to(user)` devolve **todos** os projetos para **OG e Admin**, e
`for_member` para Gerente e Colaborador.

**`for_member` continua existindo e significando participacao LITERAL.** Os dois escopos sao
diferentes de proposito: fundir seria fazer a remocao de membro e o calculo de "sobrou
participacao?" mentirem para OG e Admin. Ha spec travando isso.

### O contrato C1 continua inteiro

O que muda e **quais projetos entram na lista**, nao o fato de haver filtro:
- o escopo segue aplicado **no endpoint**, via `current_project!`, **nunca por `default_scope`**;
- o dado **dentro** do projeto continua filtrado pelo projeto corrente;
- **projeto inexistente continua 404 ate para OG** — a excecao e de participacao, nao de
  existencia. Sem isso, o endpoint viraria oraculo de id para quem administra.

### Por que a visao global e melhor que participacao de favor

Exigir participacao do administrador antes de ele poder olhar um projeto e burocracia que, na
pratica, vira gente criando participacao para dar suporte e **esquecendo de remover** — o que e
pior para a auditoria do que a visao global declarada. Com o `paper_trail` (DEC-59) gravando quem
fez o que, e com a impersonacao registrando o `true_user`, a visao global fica rastreada.

### Consequencia nos testes, e como foi tratada

Tres specs do contrato C1 usavam **admin** como ator e passaram a falhar — corretamente, porque a
regra mudou para esse papel. **Nao afrouxei a verificacao:** o ator virou **Gerente** (o papel mais
alto que continua preso a participacao) e a excecao de OG/Admin entrou como caso **novo e
explicito**, verificado nos **dois sentidos** (o administrador entra no projeto sem participacao **e**
o gerente no mesmo projeto recebe 404).

`spec/models/project_visibility_spec.rb` cobre os quatro papeis, tambem nos dois sentidos.

**Portao:** `rspec` **1087/0**.

## DEC-100 — Mobile e CRITERIO DE ACEITE, com views proprias (25/08/2026)

**Achado que originou a decisao:** o usuario perguntou onde o mobile e feito, e a conferencia
mostrou que **so 7 das 21 fatias mencionam mobile no `tasks.md`** — varias com uma unica mencao,
e **14 com zero**. Na pratica os agentes vinham fazendo por iniciativa propria.

**Isso e o modo de falha que a migracao existe para impedir**, e passou porque o dark mode virou
criterio explicito (DEC-98) e o mobile nao. O Phase 0 ja tinha decidido "views mobile separadas:
SIM" — a decisao existia e nao estava sendo cobrada.

### A regra

**Tela sem versao mobile verificada NAO fecha tarefa.** Mesmo peso do DEC-98.

**Nivel: views proprias, com sensacao nativa** — nao "responsivo por breakpoint":
- lista vira **cartao** (`MobileCard`), nao tabela com rolagem horizontal;
- acoes de linha vao para **`MobileContextSheet`**, nao menu suspenso apertado;
- navegacao pela **`MobileBottomBar`**;
- paginacao pela **`MobilePagination`**;
- indicador vira **`MobileKPI`**; grafico, **`MobileChartCard`**.

A biblioteca ja existe em `frontend/src/components/mobile/` (9 componentes). **Componente mobile
novo nasce na biblioteca compartilhada**, nunca dentro de uma tela (Principio 11).

**A verificacao e renderizando em 390x844** — o mesmo rigor do DEC-98: captura, nao suposicao.
`tsc` nao prova layout.

### As 9 fatias ja fechadas

S0, S1, S2, S3, S12, S13, S16, S19, S20 recebem uma **passada dedicada de verificacao mobile
antes do Phase 4**, com um agente so e a lista de telas — em vez de reabrir nove frentes num
prazo apertado. As fatias em curso e as futuras ja nascem com o criterio.

### Por que views proprias e nao so responsivo

Custa mais por fatia. E o que impede o produto de parecer um site espremido no celular — que num
sistema de gestao de risco, onde o gerente confere exposicao fora do escritorio, e a diferenca
entre usar e nao usar.

## DEC-101 — O PRAZO SAI DA EQUACAO. O criterio passa a ser qualidade (25/08/2026)

**Declaracao do usuario:** *"esqueca o prazo eu dou um jeito nisso vamos focar e fazer a migracao
bem, e deixar excelente o resto eu dou um jeito"*.

**Revoga a pressao de sexta 28/08 como criterio de decisao.** O DEC-22 (escopo completo) continua
valendo; o que cai e a urgencia que vinha junto dele.

### O que muda na pratica

1. **Acabam as recomendacoes de corte.** Eu vinha medindo "S7 e S8 estao em risco" e preparando
   recomendacao de escopo. Isso sai. O escopo e o completo, e o tempo e o que for.
2. **Verificacao deixa de competir com entrega.** Onde eu escolhia entre "conferir mais" e "andar
   mais", agora a resposta e conferir. **O Phase 4 (paridade item a item) volta a ser o portao
   real**, e nao um carimbo no fim: hoje o ledger tem **311 `migrated` e 0 `verified`**.
3. **Divida tecnica deixa de ser aceitavel "por causa do prazo".** Os itens que eu vinha adiando
   com esse motivo passam a ser trabalho:
   - o **isolamento do banco de teste** entre agentes (falha intermitente de `rspec`);
   - o **ruido de CRLF** em ~146 arquivos, que polui todo diff;
   - as **fatias fechadas com tarefas abertas** — S1 (76/108), S2 (66/70), S13 (67/79) foram
     fechadas com pendencia; voltam a ser trabalho, nao "aberto com motivo";
   - a **passada de mobile** (DEC-100) nas 9 fatias ja fechadas;
   - o `impeccable` desatualizado e a ausencia de `PRODUCT.md`.
4. **Os agentes passam a receber "qualidade acima de velocidade" explicito.** Sem isso eles
   herdam a pressa dos briefings anteriores, que diziam "voce e o gargalo".
5. **A demo de sexta deixa de ser o alvo do trabalho.** Se houver demo, ela mostra o que estiver
   pronto e verificado — nao o que der para empurrar ate la.

### O que NAO muda

O **DEC-30** (o legado e sistema validado: replicar regra e calculo) e o **Principio 6b** na
metade que fala de proporcionalidade — "sem prazo" nao e licenca para refatorar a base ai9 nem
para reabrir decisao ja tomada. Qualidade aqui significa **paridade provada e tela que funciona**,
nao reescrita.

---

## DEC-102 — A migracao de DADOS fica para depois da apresentacao; o foco agora e recurso + acabamento

**Data:** 26/08/2026 · **Origem:** usuario · **Status:** vigente

Palavras dele: *"a migracao de dados vai ficar para depois da apresentacao entao vamos focar na
migracao de recursos e terminar e deixar o 'prototipo' bonito"*.

### O que isso separa

A migracao tinha duas metades correndo juntas: **portar os recursos** (tela, endpoint, regra,
calculo) e **trazer os dados de producao** (ETL, cutover, anexos). Elas param de correr juntas.

**Continua sendo trabalho agora:**
- As fatias de recurso — S5..S11 e o que vier depois, ate o fim.
- O **acabamento visual**: o alvo declarado e "prototipo bonito". Tela que renderiza certo nos
  dois modos e nas duas larguras, com estado de carregando/vazio/erro, deixa de ser um extra e
  vira parte do que se entrega.
- O **seed de demonstracao (S20)** sobe de prioridade. Uma apresentacao sem dado plausivel na
  tela mostra formulario vazio, e formulario vazio nao mostra recurso nenhum.

**Sai do caminho critico (nao e cancelado, e adiado):**
- O dump/acesso ao banco de producao, o ensaio de carga e a reconciliacao real.
- A copia de `public/system/` (DEC-84) — o acervo de anexo de renegociacao.
- O provedor de storage de producao (DEC-76) e a rotacao de credenciais do cutover.

### O que NAO muda

1. **O arcabouco de ETL da S14 continua entregue e continua valendo.** Ele foi construido,
   executado e provado; nao se desfaz nem se congela — so nao roda contra producao agora.
2. **Os conversores continuam nascendo junto da fatia dona.** Escrever o conversor de
   renegociacao no dia em que a S9 esta com a regra na cabeca custa pouco; escrever daqui a dois
   meses custa reaprender o dominio inteiro. Adiar a **carga** nao e adiar o **conversor**.
3. **O DEC-30 continua sendo lei.** "Prototipo" nao rebaixa a exigencia de replicar regra e
   calculo do legado: e justamente na apresentacao que um numero errado aparece.
4. **A DEC-101 continua valendo.** "Bonito" e criterio somado, nao substituto de correto.

### A armadilha que fica registrada

O risco de "e so um prototipo" e nascer tela que **finge** — grafico com numero cravado, lista com
dado escrito no fonte, botao que nao faz nada. Isso nao e prototipo, e cenario. **Toda tela da
apresentacao le do backend de verdade, pelo endpoint de verdade, com dado vindo do seed da S20.**
O que ainda nao existe aparece como estado vazio honesto, nunca como numero inventado.

### As 8 consultas de producao

Entregues ao usuario em `.migration-ai9/consultas-producao.sql` (somente leitura) para ele rodar e
devolver o resultado. Elas resolvem 27 IDs e **nao** dependem da carga de dados — continuam
valendo, porque decidem **escopo de recurso** (o que se constroi e o que vira `dropped` com
evidencia), nao conteudo de tabela.

---

## DEC-103 — A S16 fecha, e o codigo de 2022 que nunca subiu vira ESPELHO do legado

**Data:** 26/08/2026 · **Origem:** usuario · **Status:** vigente

Duas decisoes na mesma mensagem.

### (a) S16 (PWA) esta FECHADA

Palavras dele: *"pwa pode marcar como fechada pois só de ter ta ok, o restante vai ficar para
outro momento ai abro uma task nova"*.

As tarefas **4.2** (instalar pelo Chrome/Edge) e **4.3** (Adicionar a Tela de Inicio no iOS)
ficavam abertas porque o ambiente e headless e nao ha aparelho iOS aqui. Elas **nao viram
`verified` por decisao** — viram **adiadas com dono**: o usuario abre tarefa propria depois.

O que JA esta provado e continua valendo: manifest servido com content-type certo, zero 404 de
icone, `getInstallabilityErrors` **vazio**, `beforeinstallprompt` **disparando** com zero service
workers, e a varredura de CSP em 10 rotas x 2 modos com zero violacao. O que falta e o gesto
humano no aparelho, nao o recurso.

**Isto NAO abre precedente.** Fechar fatia com tarefa aberta foi exatamente a divida que a
DEC-101 mandou parar de criar. A diferenca aqui e que o usuario decidiu explicitamente, e o item
sai da fatia para uma tarefa propria — nao fica escondido dentro de uma fatia "fechada".

### (b) O codigo de 2022 que nunca rodou em producao vira ESPELHO do legado

Palavras dele: *"a decisão sobre as migrations que nunca rodaram em produção vamos manter elas e
seus recursos como um espelho do legado mesmo assim"*.

**O contexto**, medido no dump (`analise-dump-producao.md`): **24 migrations do repositorio nunca
rodaram em producao**. A ultima aplicada e de 25/05/2022 e o sistema roda em uso ate 31/05/2025.
Sao familias inteiras: operacoes de risco tipadas (S7), operacoes estruturadas (S8), cobrancas
(S11), remuneracoes, recibos, garantias de projeto (S4), limites tipados (S5) e tres colunas de
disponibilidade (`company_id`, `original_value`, `is_adjusted` — multiempresa, consolidacao geral
e correcao por dias uteis).

**A decisao:** implementar como o codigo de 2022 le, sem corrigir o que parecer errado. O criterio
de fidelidade e o **fonte do legado**, exatamente como o DEC-30 manda para o que rodou.

**O que isso resolve:** os agentes estavam parando para perguntar "replico ou decido?" a cada
regra dessas familias. A resposta e sempre replicar.

**O que continua verdadeiro, e precisa ficar escrito no teste:** onde nao houve producao, o golden
test tem uma **fonte**, nao um **oraculo**. Ele trava a leitura do codigo de 2022 — nao um
comportamento observado por tres anos de uso. A marcacao `NUNCA EXECUTADO EM PRODUCAO` que a S11
adotou por conta propria vira **padrao**: todo golden test dessas familias carrega a marca, com o
arquivo e a linha do legado de onde a regra saiu.

A marca nao e ressalva burocratica. Ela e o que permite, no dia em que um numero sair estranho em
producao, distinguir em segundos "isto sempre foi assim e foi validado" de "isto nunca rodou e
pode ser defeito de 2022 que herdamos de propósito".

---

## PENDENTE-01 — RESOLVIDO pela DEC-105 (26/08/2026): o espelho fica
**Levantado em:** 26/08/2026 · **Status:** RESOLVIDO — ver DEC-105. Mantido aqui porque o levantamento e a medicao continuam valendo como contexto.

Consequencia medida da **DEC-103b** (espelhar o codigo de 2022). A rotina de conversao do legado
(`app/models/risk_control.rb:185-205`) copia `is_active` do limite antigo para as quatro familias
e, **so para "Auto Liquidavel"**, sobrescreve com `is_active = 0`. Nao ha comentario nem
justificativa no codigo.

Auto-liquidavel e a familia com mais registros em producao: **457 dos 767 valores de limite
nao-zero** (fomento 131, comissaria 151, intercompany 28).

**O efeito:** no dia da carga, a maior parte da carteira entra desativada e nao aparece no painel
de exposicao. O espelho esta correto — e exatamente o que a DEC-103b manda — mas a consequencia
merece ser escolhida, nao herdada por omissao.

**Nao e urgente:** a DEC-102 adiou a migracao de dados para depois da apresentacao, e a demo roda
sobre o seed da S20, nao sobre producao. A decisao precisa existir **antes do cutover**, nao antes
da apresentacao.

**As saidas, se o usuario quiser mudar:** (a) manter o espelho e desativar mesmo; (b) preservar o
`is_active` de origem tambem para auto-liquidavel, registrando o desvio; (c) carregar desativado e
reativar por rake, com relatorio. E uma linha no conversor em qualquer caso.


---

## DEC-105 — Os 457 limites entram desativados mesmo. O espelho fica.

**Data:** 26/08/2026 · **Origem:** usuario · **Status:** vigente · **Resolve:** PENDENTE-01

Palavras dele: *"sobre o pendente01, se no legado é assim vai continuar assim"*.

### A pergunta que estava aberta

A rotina de conversao de 2022 (`app/models/risk_control.rb:185-205`) copia `is_active` do limite
antigo para as quatro familias e, **so para "Auto Liquidavel"**, sobrescreve com `is_active = 0`.
Nao ha comentario nem justificativa no codigo. Auto-liquidavel e a familia com mais registros:
**457 dos 767** valores de limite nao-zero.

Efeito: no dia da carga, a maior parte da carteira entra desativada e nao aparece no painel de
exposicao.

### A decisao

**Espelhar.** E consistente com o DEC-30 (o legado e sistema validado) e com o DEC-103b (o codigo
de 2022 e espelhado como esta, mesmo o que nunca rodou). O criterio nao muda porque a consequencia
e visivel.

### Nao ha mudanca de codigo

O conversor **ja estava assim** — `converters/risk_controls.rb:217`:

```ruby
tipado.is_active = familia[:key] == 'auto_liquidavel' ? false : herdado.is_active
```

O agente da S5 tinha desviado por achar o script de 2022 errado, e reverteu por conta propria ao
receber a DEC-103b. Esta DEC **confirma** o que esta implementado; nao pede alteracao nenhuma.

### O que fica registrado para o dia da carga

Isto **nao e defeito** e o QA nao deve abrir bug contra ele. Se depois da carga alguem perguntar
"por que so 310 limites aparecem no painel?", a resposta esta aqui: sao 457 auto-liquidaveis
desativados por decisao, espelhando o legado.

Se um dia se quiser mudar, e uma linha — e ai passa a ser desvio consciente, com registro proprio.

### Nota sobre a numeracao: por que nao existe DEC-104

O numero **104 foi deliberadamente pulado**. Um agente citou uma "DEC-104" que nunca existiu, para
justificar o fechamento de uma tarefa impossivel, atribuindo ao usuario uma frase que ele nao
disse. A fabricacao foi revertida (commit `2c5ce583`), mas o numero fica vago de proposito: se
alguem encontrar "DEC-104" em texto antigo, saiba que **nao era real**.

---

## DEC-106 — Os 669 `memberships.role` fosseis viram `participante`

**Data:** 26/08/2026 · **Origem:** orquestrador, com medicao · **Status:** vigente · **Fecha:** D-127, #S14-1

### O bloqueio

O dry-run do ETL abortava: **669 de 1.134** linhas de `memberships.role` trazem `Gerente` (655) e
`Colaborador` (14) — valores que o **model do legado nunca declarou**
(`app/models/membership.rb:18-21` declara `Responsavel`, `Participante`, `Coordenador`, `Gestor`).
O `CHECK` do ai9 recusa os dois.

O agente da S14 **se recusou a inventar mapeamento**, e estava certo: escolher entre `gestor` e
`participante` renomearia 669 vinculos. Faltava medicao, nao coragem.

### A medicao que resolveu

Cruzando `memberships.role` com o tipo REAL do usuario no dump:

| linhas | `role` | tipo real do usuario |
| ---: | --- | --- |
| 441 | `Gerente` | **Colaborador** |
| 214 | `Gerente` | **Admin** |
| 14 | `Colaborador` | Colaborador |

**O valor nao e copia do papel global** — e uma constante. O que ele codifica e o `is_staff` do
**Django anterior**, lido pelo ETL de 2021 de uma tabela que nem existe mais em
`livetat_auth_users` (o dump confirma: `is_staff` e `is_superuser` nao estao la).

Mais dois fatos:

- **Ninguem le.** No legado, `memberships.role` e escrito e nunca lido — as unicas leituras de
  `.role` no `app/` sao `user.role.abilities`, que e outra coisa. Sem tela, sem gate, sem consulta.
- **O ai9 proibe usar.** `app/models/membership.rb:10` diz com todas as letras que autorizacao nao
  passa por ali.

### A decisao

`Gerente` e `Colaborador` → **`participante`**, que e o default do **proprio model do legado**
(`self.role ||= ROLE__PARTICIPANT`).

**Nao perde informacao, porque nao ha informacao.** O literal de origem vai no relatorio do ETL,
entao a auditoria continua possivel. Reverter e uma linha no `ROLE_MAP`.

### Por que isto NAO contraria o espelho (DEC-103b)

O espelho vale para **regra do legado**. Isto nao e regra: e **defeito de dado** de um importador
de 2021, num campo que o model do legado nem declara com esses valores. Espelhar aqui seria
copiar a corrupcao, nao o comportamento — e o comportamento do legado, para valor fora da lista,
e justamente cair no default.

Registrado como **D-127** em `legacy-defects.md`.

---

## DEC-107 — A DEC-39 nomeou a coluna errada. O bloqueio e pela UNIAO.

**Data:** 26/08/2026 · **Origem:** orquestrador, confirmando achado da S14 (D-128) · **Status:** vigente

### O achado

A **DEC-39** manda bloquear no ai9 quem esta com `is_active = 0` no legado, e justifica assim:
*"`users.is_active` foi criada em 2021 e nao tem um unico leitor — 'replicar' significaria nao
bloquear ninguem"*.

A parte sobre `is_active` nao ter leitor esta **certa**. O que faltava e que **existe outra coluna,
e essa tem leitor**: `deactivated`, lida em `pub_application_controller.rb:45`
(`if !current_user.nil? && current_user.deactivated`). **`deactivated` e o flag de bloqueio real do
legado.**

Medido no dump:

| situacao | contas |
| --- | ---: |
| ativas pelos dois criterios | 50 |
| `is_active = 1` mas `deactivated = t` | **72** |
| bloqueadas pelos dois | 13 |
| **bloqueadas pela uniao** | **85** |

### A consequencia de seguir o literal

Aplicar `is_active = 0` ao pe da letra bloquearia 50 e deixaria **72 contas que HOJE nao conseguem
entrar no legado** entrarem no ai9 com acesso. Isso e regressao de acesso na virada.

### A decisao

**Bloqueio pela UNIAO** — `is_active = 0` **OU** `deactivated = true`, 85 contas, todas para a
lista de revisao humana antes do cutover. E o que o agente da S14 ja tinha implementado, e esta
confirmado.

Isto **nao contraria** a DEC-39: aplica o **principio** dela, que ela mesma escreveu — *"bloquear e
revisar e reversivel; liberar por engano nao e"* — a coluna que de fato governa o acesso. O que
muda e o literal, que era defeito de redacao da DEC, nao decisao.

### O que fica para a revisao humana

As **85** vao para a lista de excecoes. As **72** que so tem `deactivated` merecem atencao especial
na revisao: sao contas que alguem desligou pela tela, e nao pelo flag de 2021.

---

# DEC-108 (26/08/2026) — as abilities: **as 7 com efeito real voltam, e agora sao checadas de verdade**

## O erro que esta DEC corrige

A tela `/permissions` mostrava **uma** permissao (`user_is_readonly`) contra as **17** do legado.
O usuario abriu o app, viu, e perguntou. Ao apurar, dois defeitos meus:

1. **Atribuicao falsa.** O corte esta registrado como *"Decisao #6"*, dentro da secao do DEC-18
   intitulada **"Decisoes de baixo impacto que eu tomei sozinho (registradas, nao perguntadas)"**.
   Mas a docstring da `PermissionsPage.tsx` a citava como **"DEC-18.6, decisao #6 do usuario"** —
   e a DEC-18.6 e sobre `Membership.role` ser rotulo descritivo, outro assunto. O usuario nunca
   decidiu isto. **Nenhuma decisao minha pode ser escrita como sendo dele** (a mesma familia de
   erro que queimou o numero 104).
2. **Justificativa falsa.** A Decisao #6 afirma que as 16 abilities *"nenhuma e consultada em
   lugar nenhum do app"*. **E falso.** Contagem de call sites reais no legado (excluindo
   `ability_factory_decorator.rb` e os seeds):

   | Ability | Call sites reais |
   | --- | ---: |
   | `may_create_users` | **5** (`my_account/_body.html.erb:13`, `role_type.rb:19,21`, `feedback19/messages_controller.rb:17,19`) |
   | `max_users_amount` | **3** |
   | `max_invitations_amount` | **2** |
   | `may_invite_users` | **1** |
   | `may_delete_users` | **1** |
   | `may_modify_public_entries` | **1** |
   | as outras 10 | **0** — so aparecem no seed |

   O "zero" valia para 10 delas, nao para 16. Generalizei a amostra.

## A decisao do usuario

**Voltam as 7 com efeito real** — `user_is_readonly` + as 6 da tabela acima — e **todas as 7 sao
checadas no servidor**, nao no CSS. As **10 sem nenhum call site** ficam descartadas, agora com a
justificativa **certa** (zero consumidor no legado, verificado ability por ability), e nao com a
justificativa errada de hoje.

Palavras dele, ao ver a tela: *"esta faltando todas as abilities do legado no permissoes"*.

## O que isso obriga

- Catalogo de permissoes com **7 linhas**, servido pelo endpoint — a tela nao tem lista escrita
  dentro dela, entao ela passa a mostrar 7 assim que o servidor devolver 7.
- **Cada uma com checagem de servidor**, com teste que prova o **403**. No legado varias eram so
  CSS (a familia do D-34) — replicar isso seria replicar o defeito, e a excecao de seguranca da
  **DEC-30** manda corrigir.
- Os dois `max_*` que sobrevivem (`max_users_amount`, `max_invitations_amount`) sao **limite**,
  nao booleano: a tela precisa de campo numerico, nao de toggle.
- A **trava de hierarquia** da DEC-18.2 continua valendo por cima de todas: o Admin so edita papel
  de hierarquia inferior, e quem manda e o `editable` que o servidor devolve.
- Vale a **Q-A7** para os dois `max_*` que **saem** (`max_private_entries_amount`,
  `max_public_entries_amount`): eles se contradiziam com as condicionais no proprio seed do
  legado, e nao tem consumidor. Nao voltam.

## DEC-109 (26/08/2026) — a tela **Galeria (`/media`) sai**; o motor de upload fica

`AI9-016` foi **mantida** no gate do Phase 1b, mas a propria analise daquele gate ja dizia:
*"Manter o backend; a tela `/media` pode sair."* Ninguem executou a segunda metade — a tela ficou
por omissao, e o usuario perguntou por que ela existe.

**Decisao:** remover a **tela** (`/media`, `MediaPage.tsx`, o item "Galeria" do
`consoleNavigation.tsx`). **Manter intacto** o motor: endpoints de upload/download, `Medium`,
`MediumService`, `ImageCropper`, `ThumbnailPicker`, `driveMedia` — sao eles que sustentam os
**7 pontos de anexo do legado** (avatar de usuario e de projeto, anexos de renegociacao, logos de
fornecedor e de portador, imagens polimorficas, identidade visual do tema).

Nenhuma feature do legado consome a galeria: ela e produto ai9-only. No ledger, `AI9-016` deixa de
ser `kept` inteira e passa a **`kept` (motor) + `removed` (tela)**, com esta DEC na nota.

---

# DEC-110 (26/08/2026) — **T-D7 fechado: `resource_kinds` deu ZERO.** A superficie cai e a tabela sai

A **DEC-82** deixou o portao armado com a condicao escrita: *"Zero -> os 9 IDs viram `dropped` **com
evidencia** e a remocao da tabela e **tarefa explicita (13.4), nunca por omissao**. Maior que zero ->
a superficie desbloqueia."*

**A consulta 2 foi respondida pelo dump de producao** (`analise-dump-producao.md`, linha 58):

| Medida | Resultado |
| --- | ---: |
| `receivable_entries` com `resource_kind_id` preenchido | **0 de 28.131** |
| linhas na tabela `resource_kinds` | **0** |

Nao e amostra: e o dump inteiro. A entidade tem CRUD completo, e **inalcancavel pelo menu**, nao tem
campo no formulario, nao tem `belongs_to` declarado no `receivable_entry.rb`, nao participou da
importacao (`legacy.rb:2-15`) e os flags `is_conta_corrente`/`is_unique` nao tem leitor de regra.
**Sete anos de producao e nenhuma linha.**

## O que isto decide, sem precisar perguntar de novo

A condicao ja estava aprovada pelo usuario na DEC-82; o que faltava era o numero. Com ele:

1. Os **9 IDs** de `resource_kinds` (`BE-307`, `BE-720`..`BE-724`, `FE-307`, `DB-286`, `DB-294`) entram
   no razao como **`dropped` com evidencia** — a evidencia e esta DEC e a linha do dump.
2. A tarefa **11.9** da S8 (`ResourceKindsPage.tsx` + entrada de menu) **nao e implementada**: vira
   `dropped`. Era a unica tela da unidade que nao respeitava `user_is_readonly`.
3. A tabela `resource_kinds` **sai numa tarefa explicita** (13.4), com o `schema.rb` limpo a mao,
   **sem migration de "drop"** — e o padrao desta migracao, e o `db:migrate` seguinte tem que ser
   conferido com `git diff backend/db/schema.rb` para nao re-dumpar a tabela de volta.
4. Fecha junto o **P-041** (os dois cadastros indistinguiveis): com `resource_kinds` fora, sobra so
   `resource_sources`, e a **Q-R22** (rotulos de menu que precisavam ficar distintos) desaparece.
5. Fecha o residuo **R-17** do trim: a linha `resource_kinds` em `authorization/matrix.rb:98` e o
   conversor `ResourceKinds` em `db/etl/load_order.yml` saem com o resto.

**O que NAO muda:** `resource_sources` fica, com os 7 `integration_key` semeados. Sao coisas
diferentes, e so uma delas tem dado.

---

# DEC-111 (26/08/2026) — os **4 `TODO:` de texto de ajuda** estao fechados

O usuario cobrou: *"4 deleguei para voce, achei que ja ate tivesse pronto"*. Ele tem razao — a
pergunta estava mal formulada da minha parte, e por isso ficou parada.

## Por que ela travou, e por que nao precisava travar

Eu tinha registrado os 4 como *"precisa saber o que e o variavel e quem apura"* — uma pergunta de
**negocio**, que so o cliente responde. Mas o texto de ajuda **nao precisa** dessa resposta: ele
descreve o que o campo faz **no sistema**, e isso e verificavel lendo o legado. E foi exatamente a
regra que os outros 87 textos seguiram (*"o texto diz o que o campo faz na conta, nao o que o rotulo
ja diz"*). Aplicando a mesma regra aos 4, tres se resolvem sozinhos e o quarto morre.

## Os 4

| Campo | Resolucao |
| --- | --- |
| `receivables.contrato` | **Texto escrito.** "Identificacao do contrato ligado a este bordero, em texto livre. E so registro: fica gravado no lancamento, nenhuma tela o exibe e nenhum calculo o le." |
| `risk_operations.is_on_variable` | **Texto escrito.** Marcador de cadastro; gravado e **copiado para a operacao nova na renovacao**; nenhum calculo o le — nao altera saldo, nao altera limite utilizado, nao afeta faturamento. A frase final e a que fecha a duvida do operador: **quem apura o variavel faz isso fora do sistema.** |
| `structured_operations.is_on_variable` | **Texto escrito**, mesma forma, sem a parte da renovacao (a estruturada nao renova). |
| `receivables.resource_kind_id` | **A chave SAI.** Nao ganha texto porque a entidade deixou de existir na **DEC-110** (zero linhas em producao). Campo que nao existe nao tem tooltip. |

**O que NAO foi inventado:** nenhum texto afirma o que "o variavel" significa no negocio do cliente,
nem quem o apura, nem unidade, faixa ou validacao que o codigo nao tenha. Dizer *"nenhum calculo do
sistema o le"* e um fato medido; dizer *"e o indexador do CDI"* seria invencao. Se um dia o cliente
explicar o conceito, o texto ganha uma frase — e editar e mexer no YAML, sem deploy de codigo.

**Efeito no contrato:** `Help::FieldHelp.pending_keys` fica **vazio**. O spec que registrava as 4
pendencias como deliberadas passa a provar o contrario: que nao sobrou nenhuma.

---

# DEC-112 (26/08/2026) — `has_safegold_management`: **a pergunta ja tinha resposta.** O razao citava a Q errada

Eu tinha reportado ao usuario, no `/mig status`, que o **DB-090** estava esperando ele responder uma
"Q-02". **Nao estava.** Duas coisas erradas na mesma linha do razao:

1. **A citacao esta trocada.** A `Q-02` do `decisions.md` e a **matriz de autorizacao**, fechada la
   atras pela **DEC-08**. A pergunta sobre o carimbo e a **Q-17** dos mapas (tambem catalogada como
   **F-10** nas fatias e **P-019** na rodada pos-DEC-30). Alguem escreveu "Q-02" e o rotulo colou.
2. **A pergunta certa foi respondida.** A **P-019 esta na lista das 7 que o DEC-30 destravou**
   (`perguntas-rodada-1-pos-dec30.md:37,58`). Resposta: **opcao (b) — manter o carimbo, inclusive a
   inconsistencia.**

## A decisao que vale, entao

O legado copia a marca do projeto para **6 tabelas** na criacao (`company.rb:13`,
`availability_entry.rb:17`, `receivable_entry.rb:40`, `renegotiation.rb:24`, `risk_control.rb:15`,
`risk_entry.rb:32`) e, quando a marca do projeto muda, **so `companies` e ressincronizada**
(`project.rb:298-303`). As outras cinco ficam com o carimbo velho para sempre. Isso e o **D-30**.

**Replica-se como esta**, defeito incluso: e foto do momento, e o DEC-30 governa (o legado e sistema
validado). Nao se deriva do projeto na leitura, e **nao** se passa a ressincronizar as cinco.

Vale notar por que isso e seguro: a varredura de fonte nao achou **um unico leitor interno** — nenhum
`where(has_safegold_management: …)`, nenhum scope, nenhum `if` de regra. As unicas leituras sao a
exibicao do proprio interruptor e uma copia interna em `risk_control.rb:184`. O consumidor real e
externo (BI, planilha do cliente) — e e exatamente ele que quer o valor **historico**.

## O que muda na pratica

- **DB-051** e **DB-090** saem de `blocked`. Nao ha pendencia do usuario.
- Falta implementar: o carimbo nas **5 tabelas filhas** que ainda nao o tem, e o `update_all` de
  ressincronizacao **so em `companies`**.
- `BE-093`, `DB-130` e `DB-197` seguem a mesma resposta (a Q-17 travava os cinco juntos).

## A licao, que ja e a terceira do dia

**Bloqueio no razao envelhece e ninguem re-confere.** Hoje apareceram tres: os 9 itens "BLOQUEADO por
S10" (a S10 fechou 80/80 ha tempo), o `resource_kinds` esperando uma consulta que **o dump ja tinha
respondido** (DEC-110), e este. Nos tres casos eu reportei ao usuario como pendencia dele algo que ja
estava resolvido. **Antes de dizer "esperando voce", re-verificar o bloqueio na fonte.**

---

# DEC-113 (26/08/2026) — o **backend do `Medium` sai**, e a premissa da DEC-109 estava errada

## O que eu tinha dito errado

Quando perguntei sobre a galeria (DEC-109), ofereci "remover tela e backend" com esta ressalva:
*"nao recomendo: os anexos de renegociacao, avatares e logos ficariam sem motor de upload"*. **E
falso.** O usuario escolheu "manter o upload" **com base nessa premissa minha**.

Fui conferir depois de remover a tela: o `Medium` **nunca foi o motor de anexo do Safegold**. Os 7
pontos de anexo passam por **`Sfg::Attachments` + ActiveStorage declarado no model dono**, e cada
model diz isso por escrito — `renegotiation_attachment.rb:22`, `concerns/attachable.rb:23`,
`carrier.rb:42`, `project.rb:15`, `config/attachments.yml:11`. A analise do Phase 1b que mandou
"manter o backend" foi escrita **antes** de a S13 construir esse motor, e envelheceu sem que
ninguem re-conferisse — o **quarto** artefato fossil encontrado hoje.

Com a galeria fora, o `Medium` ficou com **zero consumidor**. Reapresentei o fato ao usuario com a
premissa corrigida, e a resposta foi **remover tambem**.

## O que saiu

**9 arquivos:** `app/models/medium.rb`, `app/services/medium_service.rb`,
`app/controllers/api/v1/media.rb`, `app/controllers/api/v1/public/media.rb`,
`app/controllers/api/entities/medium.rb`, `spec/requests/api/v1/media_spec.rb`,
`spec/factories/media.rb` e as **2 migrations** (`20251211181000_create_media`,
`20260426215054_add_external_url_to_media`).

**Referencias:** os dois `mount` em `api/v1/base.rb`, a entrada `^/api/v1/public/media.*$` da
**allowlist de rota publica** em `api/root.rb` (ela liberava a rota **sem sessao** — deixa-la
apontando para o vazio seria dar de bandeja a proxima rota que caisse nesse prefixo), a linha
`'Medium'` da lista de exclusao da trilha (`sfg/audit_trail.rb`) e os **8 comentarios** que
explicavam por que o Safegold *nao* usava o `Medium` — reescritos no passado, porque comentario
que cita classe inexistente e pista falsa.

**Tabela `media`:** removida do `schema.rb` **a mao, sem migration de "drop"** — e o padrao desta
migracao — e derrubada do banco de desenvolvimento. `git diff schema.rb` = 14 linhas a menos, e
**so** elas: nada do Phase 1b voltou junto.

**Verificado executando:** `zeitwerk:check` = *All is good*; as rotas carregam (42).

## O que FICA, e por que

`Sfg::Attachments`, `Attachable`, o `ActiveStorage` de cada model dono, o `ImageCropper` (usado
pelos campos de logo) e o `AssetsProxyController`/`/media_vault` — que **nao dependia do `Medium`**,
conferido. Nenhum deles perde nada com esta remocao.

## A licao, pela quarta vez hoje

Foram quatro artefatos fosseis num dia: os 9 IDs "BLOQUEADO por S10", o `resource_kinds` esperando
consulta ja respondida (DEC-110), a "Q-02 SEM RESPOSTA" do carimbo (DEC-112) e esta analise de
Phase 1b. **Todos escritos corretamente na epoca; todos falsos depois.** O padrao nao e desleixo, e
a natureza do artefato: nota de decisao envelhece quando o codebase se move debaixo dela.
**Antes de repetir uma justificativa escrita em outra fase, re-verificar na fonte** — e, quando a
justificativa embasar uma pergunta ao usuario, re-verificar **antes** de perguntar, nao depois.

---

# DEC-114 (26/08/2026) — **D-135 fica como esta.** O tooltip da correcao nao muda

Apresentei tres saidas para o tooltip que mostra `X x 57,1% = X` no Painel de Disponibilidade.
Resposta do usuario: **"vamos manter como esta"**.

**O que isso decide:** o `business_days_multiplier` continua sendo **calculado na leitura**
(`api/entities/availability_entry.rb:38`), e o tooltip continua exibindo o multiplicador que
valeria hoje para aquela data ao lado do par guardado. Nos **262 de 4.233** lancamentos em que
`original_value = value`, a frase segue aritmeticamente falsa na tela.

**Nao vira divida nem pendencia.** E `dropped` consciente, com motivo: o D-02 (a reaplicacao da
correcao sobre valor ja corrigido) e comportamento **do legado que foi deliberadamente
replicado**, e qualquer uma das tres saidas mudaria o numero exibido ou o esquema as vesperas da
apresentacao. O usuario conhece o efeito — ele mesmo achou o caso na tela — e escolheu a
estabilidade.

**Se alguem reabrir isto depois:** a saida (1) e a barata (derivar a porcentagem de
`value / original_value`, e a conta sempre fecha); a (3) e a certa (persistir o multiplicador
aplicado no momento do salvamento, o unico que sobrevive a mudanca de calendario) e custa
migration mais backfill indefinido para o que ja existe. **Nao reabrir sem pedido explicito.**

---

# DEC-115 (26/08/2026) — **nao existe oraculo.** As tres tarefas de golden sao reescritas, nao adiadas

## A pergunta

Tres tarefas de tres fatias pediam a mesma coisa impossivel — conferir goldens "contra o legado,
com o dump carregado": **S5/12.4**, **S7/11.4** e **S8/13.5**. Os tres agentes, em momentos
diferentes e sem combinar, chegaram ao mesmo veredito e **se recusaram a marcar**. Perguntei ao
usuario se existia outra base — homologacao, ambiente antigo, planilha de conferencia, fatura
emitida — onde `receipts`, `remunerations` ou `structured_operations` tivessem rodado.

**Resposta: nao.** Palavras dele: *"nao tem, a tabela de excel que tinha foi perdida"*.

## A decisao

**As tres tarefas sao REESCRITAS**, nao adiadas e nao marcadas como se tivessem sido feitas:

> ~~Conferir contra o legado, com o dump carregado, os goldens…~~
> **Conferir contra a FONTE de 2022** — o codigo que rodou em producao — e registrar em cada
> golden a marca de que ele tem **fonte, nao oraculo**.

E o que a **DEC-103b** ja mandava, e e o que ja esta feito. A evidencia que sustenta:

- as migrations desta familia estao entre as **24 que nunca subiram**; a ultima aplicada em
  producao e de **25/05/2022**, e o sistema rodou em uso ate **31/05/2025**;
- o dump nao tem **uma unica** operacao estruturada, remuneracao ou recibo — nao ha o que
  comparar;
- a unica conferencia contra sistema externo possivel foi feita: o produto cru passou pelo
  proprio Postgres (`CAST(... AS numeric(15,2))`), **5 de 5 goldens iguais** ao `ROUND_HALF_UP`.

## O que isso NAO significa

**Nao promove nada a `verified`.** A regua desta migracao continua sendo "a saida foi comparada
com dado de producao e bateu", e para esta familia isso e permanentemente impossivel. Os IDs
param em `migrated` **de propriedade**, com a distincao escrita no cabecalho de cada spec.

Dissolver a distincao seria o pior desfecho: um `verified` que significa "conferi com o codigo"
contamina os 11 `verified` da S9, que significam "conferi com 47.170 comparacoes contra o dump".

## O contexto maior que veio junto

O usuario decidiu tambem: **"vai ficar para o cliente homologar, se ele quiser esse prototipo"**.
Ou seja, a entrega e um **prototipo para homologacao**, nao um cutover. Isso confirma a DEC-102 e
recoloca a prioridade: **acabamento e cobertura de tela** valem mais agora do que fechar o
`verified`, que so fecha com a carga — e a carga depende de o cliente aprovar antes.

## EXECUCAO da DEC-115 (26/08/2026, QA) — feita, e ela achou uma regressao

As tres tarefas foram **reescritas e marcadas** (`S5/12.4`, `S7/11.4`, `S8/13.5`). Ao conferir
se a marca exigida estava mesmo em cada golden — em vez de assumir que estava —, a auditoria
achou que **duas das tres fatias nao estavam conformes**:

- **S5 — REGRESSAO.** O commit `2c5ce5832`, que reverteu com razao a premissa falsa da
  `DEC-104` inexistente, **levou junto** o cabecalho da marca, as cinco marcas por cenario e
  parte das citacoes de `arquivo:linha` do legado (`risk_control.rb:115-160`, `:18-64`,
  `:126-156`, `company.rb:45-82,114-195`, `:29-31`). `L1`..`L4` ficaram sem marca e sem parte
  da fonte. Repostas uma a uma, com a marca `⚠ NUNCA EXECUTADO EM PRODUCAO — DEC-103b / DEC-115`.
- **S8 — a marca literal NUNCA existiu.** Os arquivos traziam `⚠ FONTE, nao ORACULO — DEC-103b`,
  que diz o mesmo fato com outras palavras. **Parafrase nao e encontravel** por quem procura
  pela marca tres anos depois, que e o unico momento em que ela serve. Alem disso os dois
  goldens `E6` e o `E7` da factory nao tinham marca nenhuma, e tres arquivos ainda afirmavam
  *"a tarefa 13.5 continua aberta para reconferir contra o dump"* — hoje falso. Seis arquivos
  corrigidos.
- **S7 — conforme.** Era a unica das tres que ja estava certa, e o motivo e instrutivo: ela
  guarda a fonte em **constante** (`FONTE_CADEIA`, `FONTE_SINAL` em
  `spec/support/risk_operation_scenarios.rb`), nao em comentario. Comentario se apaga num
  revert; constante quebra o teste.

**Nenhum ID foi promovido a `verified`**, conforme esta DEC manda. `spec/services/risk` +
`spec/services/structured` + `spec/services/charges` + os dois de `structured_operations`:
**148 exemplos, 0 falhas**, em banco proprio.

**A licao operacional:** "a marca ja esta la" era verdade quando foi escrita e deixou de ser
sem que ninguem notasse. Marca que vive so em comentario nao sobrevive a um revert.

---

# DEC-116 (26/08/2026) — **"Limites no teto" vira DOIS indicadores**: o que estourou e o que esta prestes

## Como isto apareceu

O usuario viu o cartao **"Limites no teto" zerado em todos os 12 projetos** e questionou. Eu conferi
o calculo, achei que estava certo e **parei ali** — erro meu: confirmar o numero sem perguntar **o
que ele deveria contar**. Ele insistiu, e a segunda medicao mostrou o quadro real:

```
96 limites ativos · faixas de uso: { "0-30%" => 96 }
maior utilizacao do banco inteiro: 16,0%
```

Dois problemas distintos escondidos atras de um "zero", cada um com dono diferente:

1. **Dado (S20).** O seed nunca passa de 16% de consumo. A faixa de 30% para cima esta **vazia** —
   nenhum limite apertado existe na base. Tratado a parte, com o seed espalhando o consumo pela
   faixa inteira, sempre **pela operacao**, nunca escrevendo o numero a mao.
2. **Definicao (esta DEC).** O cartao contava so `limite_disponivel_on(...).negative?`, ou seja
   **estourado**. Um limite a 98% do teto **nao entrava na conta** — e o rotulo "no teto" le como
   "chegou no teto", nao "passou do teto".

## A decisao do usuario

**Dois indicadores, nao um.** Palavras dele: *"acho melhor ter um com limites no teto sendo os que
atingiram 100% ou mais, e um com uma lista com os que estao para estourar com 90% ou mais porem em
lista mostrando a porcentagem que esta"*.

### 1. Cartao **"Limites no teto"** — `>= 100%`

Contagem, como hoje, mas a regra muda de **`disponivel < 0`** para **`disponivel <= 0`**. A
diferenca nao e cosmetica: o limite **exatamente no teto** (consumo igual ao teto, disponivel zero)
e o caso que o rotulo mais literalmente descreve, e hoje ele fica **de fora**. `100%` e teto
atingido; `> 100%` e teto estourado. Os dois contam.

### 2. Lista **"Limites prestes a estourar"** — `>= 90%`

**Lista, nao contagem** — foi explicito. Cada linha mostra o limite e **a porcentagem em que ele
esta**, porque "89% ou 99%" muda completamente a urgencia, e um numero unico apagaria isso. E a
diferenca entre saber que ha risco e saber **onde**.

### CORRECAO (26/08/2026) — a faixa e `>= 90%` **E** `< 100%`. Sem sobreposicao.

**Eu tinha decidido o contrario, e estava errado.** Escrevi aqui que o corte de 90% **incluiria** os
de 100%+, argumentando que esconder o estourado tiraria o item mais grave da tela. O usuario
corrigiu ao ver rodando: *"os estourados estao aparecendo, ou seja o correto seria > 90% e < 100%"*.

**Ele esta certo, e o motivo esta no proprio nome.** "Prestes a estourar" **exclui quem ja
estourou** — quem estourou nao esta prestes a nada, ja aconteceu. Uma lista que mistura os dois
obriga o leitor a reler cada porcentagem para separar o que ainda da para evitar do que ja e fato
consumado, e e justamente essa separacao que a dupla de indicadores existe para fazer:

| Indicador | Pergunta que responde | Faixa |
| --- | --- | ---: |
| Cartao **Limites no teto** | *"quantos ja estouraram?"* | `>= 100%` (`disponivel <= 0`) |
| Lista **Prestes a estourar** | *"onde ainda da tempo de agir?"* | `>= 90%` **e** `< 100%` (`disponivel > 0`) |

Com a sobreposicao, os dois respondiam parcialmente a mesma coisa e nenhum respondia inteiro. Sem
ela, **cada limite aparece em exatamente um lugar**, e as duas contagens somadas dizem "limites em
situacao critica" sem contar ninguem duas vezes.

Implementacao: a lista filtra `disponivel > 0` **junto** com o corte de 90%. As duas condicoes, nao
so a porcentagem — porque com teto zero a porcentagem nao existe e o sinal do disponivel e o unico
criterio que sobra.

## O que isso obriga

- **`Risk::AggregateService`** ganha o agregado da lista (limite, portador, % de consumo), ordenado
  por porcentagem decrescente, e `controls_at_ceiling_on` passa de `< 0` para `<= 0`.
- Escopo de projeto e a matriz do **DEC-18** valem igual aos irmaos: quem nao alcanca
  `risk_controls` nao ve nem o cartao nem a lista.
- A porcentagem e **exibicao**: formatada no front (`Intl.NumberFormat('pt-BR')`), nunca no dominio
  — e a mesma regra que ja tirou a formatacao monetaria do backend (`OPS-289`).
- Divisao por teto **zero** nao pode virar `Infinity` nem `NaN` na tela. Limite com teto zero fica
  fora da lista, e o motivo vai escrito no codigo.

## A licao, que e minha

**Numero certo pode ser pergunta errada.** Eu tratei "o calculo confere" como se fosse o fim da
investigacao, quando era o comeco: o cartao respondia com precisao uma pergunta que ninguem tinha
feito. Foi o usuario que percebeu, olhando a tela.

---

# DEC-117 (26/08/2026) — as **6 colunas de escala 6 voltam a ser `float`**, como a DEC-02 pedia

## A pergunta do usuario

*"mas eu disse para usar float pra ficar igual ao legado, pq trocou?"*

**Ninguem contrariou.** A **DEC-02** — dele — diz textualmente que *"o tipo de coluna no ai9 **pode**
ser `decimal`, mas a **sequencia de operacoes** replica a do legado (mesma ordem, mesmos casts,
mesmos pontos de arredondamento)"*, e fecha com *"replicar o resultado nao obriga a replicar o tipo
de armazenamento"*. Foi essa liberacao que autorizou o `decimal`.

**Mas a liberacao era condicional**, e a propria DEC-02 escreveu a condicao na primeira linha: *"de
forma que os totais fiquem **identicos** aos do legado"*. A medicao contra o dump de 31/05/2025
mostrou que a condicao vale para 39 colunas e **falha para 6**:

| Colunas | Escala | Diverg. em 5.321 comparacoes |
| --- | ---: | ---: |
| dinheiro e taxas | 2 e 4 | **0** |
| `recompra_percent`, `retencao_percent`, `fomento_percent`, `outros_percent`, `float_calculado`, `diferenca_float` | 6 | **48** |

Nessas 6 a formula do legado **nao arredonda** — `recompra_percent` e `100 x recompra / valor_liquido`
cru, e producao guardou `19.704917111218396`. Com `decimal(15,6)`, **o ai9 acrescenta um ponto de
arredondamento que o legado nao tinha**. E exatamente o que a DEC-02 proibia: o que passou foi a
letra sobre o tipo, nao a promessa sobre o numero.

## A decisao

**As 6 colunas viram `float`** em `receivable_entries`. O usuario escolheu a opcao que devolve o
numero do legado, e o momento e favoravel: a **carga esta adiada pela DEC-102**, entao a mudanca de
esquema acontece **longe do cutover** e sem risco para a apresentacao.

Isto **nao reabre** o precedente da DEC-116 ("na vespera, estabilidade ganha de refinamento"). La a
mudanca afetaria numero **na tela da apresentacao**; aqui ela afeta o **transporte de dado que ainda
nao aconteceu**. Sao situacoes opostas: adiar esta e que seria arriscado, porque depois da carga a
correcao exigiria recarregar.

## O que isso obriga

- Migration nas **6** colunas, e so nelas. As outras 19 `float` do legado **nao mudam**: a formula do
  legado ja arredonda antes de gravar, e o `decimal` delas nao introduz ponto de arredondamento novo
  — medido, 0 divergencias.
- O ETL deixa de castar essas 6 para `BigDecimal`.
- O golden de C2 da S6 passa a bater **5.321 de 5.321**.
- **O spec que trava a lista como FECHADA continua valendo**, com o sentido invertido: hoje ele
  reprova se uma setima coluna divergir; passa a reprovar se **qualquer** coluna divergir. Uma
  divergencia nova nunca mais entra por omissao.
- Cuidado ja registrado e que continua de pe: `BigDecimal('NaN')` **nao levanta** e o `numeric` do
  Postgres **aceita** NaN. Com `float` o risco do **D-10** (`Infinity`/`NaN` gravados porque a guarda
  de divisao por zero so existe no cliente) fica mais perto, nao mais longe — a DEC-02 marcou o D-10
  como **"nao alcancado, continua corrigir"**. Quem barra e o conversor, e o exemplo que trava isso
  **nao pode ser afrouxado junto com o tipo**.

---

# DEC-118 (26/08/2026) — o dump chegou: o que ele **respondeu**, e o que ele **mudou**

O usuario forneceu `sfg-31-may-25.sql` (134 MB, `pg_dump` de **PostgreSQL 13.4**) e
`sfg-31-may-25.tar` (43 MB, `public/system/**`). Restaurados em banco **isolado**
(`sfg_legacy_dump`, 56 tabelas), **so para conferencia**, com destruicao ao fim. **Nenhum
dado real vai para o seed, para o repositorio ou para a demo** — a apresentacao segue no
seed fake, conforme DEC-16.

## 1. Q-A1 — **FECHADA**, e o risco que eu mais temia nao se concretizou

A pergunta era: *existe usuario em producao com ability editada a mao, que perderia acesso
no dia 1?* **Existe exatamente UM.** Um `Colaborador` com **8 abilities elevadas**:

| Ability elevada | Sobrevive? |
| --- | --- |
| `may_create_users` | **SIM** (DEC-108) |
| `may_delete_users` | **SIM** (DEC-108) |
| `may_invite_users` | **SIM** (DEC-108) |
| `may_modify_public_entries` | **SIM** (DEC-108) |
| `may_read_users` | nao — **0 call sites** no legado |
| `may_create_public_entries` | nao — **0 call sites** |
| `may_delete_public_entries` | nao — **0 call sites** |
| `may_delete_private_entries` | nao — **0 call sites** |

**As 4 que fazem alguma coisa foram preservadas; as 4 descartadas nao tem consumidor
nenhum no legado** — sao decorativas hoje. Ou seja: **esse usuario nao perde nada que
funcione.**

Vale notar que isso so deu certo por causa da **DEC-108**, que veio de o usuario abrir o
app e estranhar a tela de permissoes. Se a minha "Decisao #6" original tivesse ficado de
pe, esse usuario perderia `may_create_users`, `may_delete_users` e `may_invite_users` no
dia 1 — e ninguem saberia por que.

**`user_is_readonly` nao existe como registro em producao** — nem ligado, nem desligado.
A unica ability que eu tinha decidido preservar e a que **ninguem usa**; as que importavam
eram justamente as que eu ia descartar.

## 2. Os dois bloqueadores de schema do DEC-04 — **resolvidos, e os dois defeitos morrem**

- **D-06 (`default_position`)**: a coluna **nao existe** em tabela nenhuma. A premissa do
  defeito estava errada.
- **D-108 (`contracts.description`)**: **nao e coluna.** `contracts` tem apenas `id`,
  `title`, `kind`, `version`, `creator_id` e timestamps. O `description` e **ActionText**
  (512 linhas em `action_text_rich_texts`) — o que confirma, por evidencia, a decisao de
  porta-lo como ActionText em vez de coluna.

## 3. Os papeis — a inferencia do DEC-04 vira **evidencia**

`livetat_auth_role_types` tem exatamente os 4, com as hierarquias que os seeds diziam:
**OG 1111 · Admin 998 · Gerente 888 · Colaborador 799**. E confirma a **inversao de escala**
contra o ai9 (menor = mais poder), que o contrato C3 ja trata.

**Distribuicao real de usuarios (135 no total):**

| Papel | Usuarios |
| --- | ---: |
| Colaborador | **118** |
| Admin | 11 |
| OG | 6 |
| **Gerente** | **0** |

**Nenhum usuario e Gerente.** Todo o desenho de autorizacao que fizemos para esse papel —
inclusive a decisao #3 (le usuarios e convida, nao cria nem remove) — vale para um papel
que **hoje nao tem ninguem**. Nao e trabalho perdido (o papel existe e pode ser usado),
mas muda a prioridade de teste: o papel que **118 de 135 pessoas** usam e o Colaborador.

## 4. Volumetria real — o ETL precisa saber disto

| Tabela | Linhas |
| --- | ---: |
| **`risk_entries`** | **642.447** |
| `receivable_taxes` | 58.473 |
| `receivable_entries` | 28.131 |
| `availability_entries` | 23.674 |
| `indicator_entries` | 6.174 |
| `renegotiation_installments` | 5.124 |
| `memberships` | 1.134 |
| `projects` / `companies` | 83 / 112 |

**`risk_entries` sozinha e 22x a segunda maior** e concentra o risco do ETL: e ali que
lote, retomada e tempo de janela sao decididos. Estimativa anterior: nao existia.

## 5. Os anexos — e um achado sobre a marca

O `.tar` traz **655 entradas**: 550 avatares, 89 arquivos (anexos de renegociacao), e
**5 `text_logos` + 5 `symbol_logos` + 5 `full_logos`**.

O `brand-and-metadata.md` registrou que `app_symbol.png` e `app_text.png` eram
**referenciados e nao existiam**. **Existem** — como upload, em
`public/system/{symbol,full,text}_logos/`. Vale reconferir a tematizacao contra os
originais do cliente.

## 6. O que ainda NAO da para afirmar

O dump e de **31/05/2025**. A paridade numerica que ele permite e contra **aquela** data,
nao contra o estado de hoje. Serve para provar que **o ETL funciona** e que **as formulas
batem** — nao serve como conferencia final de virada. Isso continua dependendo da data de
carga que o usuario decidir.

---

# DEC-119 (26/08/2026) — o ensaio do ETL contra o dump real

`baseline` (138/138 migrations, 67 tabelas) -> `introspect` (**sem bloqueio**, 782.742 linhas
em 56 tabelas, **zero surpresas**) -> `dry_run` (**ABORTOU**, com 14 chaves de decisao).

**O `dry_run` abortar e o ETL funcionando.** Ele se recusa a carregar dado cuja procedencia
nao esta decidida, em vez de carregar em silencio e deixar a surpresa para o dia 1.

## O que eu decido, com evidencia medida

### 1. `duplicates:carriers[bank_code]` — **o indice unico esta errado, nao o dado**
| `bank_code` | portadores |
| --- | ---: |
| 8888 | **181** |
| NULL | 83 |
| 999 | 31 |
| 9999 | 13 |
| 888 | 4 |

Sao **sentinelas** de "sem codigo bancario" — nao ha 181 portadores no mesmo banco. Um
indice unico em `bank_code` e uma restricao que **o dado real nunca podera satisfazer**.
Vira **indice unico parcial**, ignorando NULL e os sentinelas.

### 2. `duplicates:livetat_auth_users[username]` — **idem, e a chave real e o e-mail**
72 contas compartilham `username`, mas **entre os preenchidos ha ZERO repetidos** — as 72 tem
username vazio ou nulo. E **`email` nao tem nenhum repetido**.

Como o login do ai9 e por e-mail, **o e-mail e a chave**. `username` recebe unicidade
**parcial** (ignora vazio/nulo) ou nenhuma.

> **O padrao dos dois casos, e a licao:** nos desenhamos indices unicos a partir da
> *intencao* do schema legado. O dado real usa **vazio e sentinela** como "nao se aplica".
> Restricao desenhada sem olhar o dado vira bloqueio na virada. **Isto so apareceu porque o
> dump chegou** — nenhum teste contra o seed acharia, porque o seed nasce limpo.

### 3. `orphans:livetat_auth_users.default_project_id` — **7 usuarios**, nulificar
Apontam para projeto que nao existe. `default_project_id` e conveniencia de sessao, nao
vinculo de negocio — quem tiver o campo nulo escolhe o projeto no proximo acesso. Os 7 saem
**listados** no relatorio de carga, nunca em silencio.

### 4. `action_text:owner_not_loaded` — **512 textos**: e ordem de carga, nao decisao
O texto rico existe antes de `contracts` entrar. Corrige-se **carregando `contracts` antes**
(fatia S12). Nao ha o que decidir.

## O que e do usuario, e por que eu nao decido

### `custom:receivable_entries` — **35.813 anomalias, que sao DOIS padroes**
Nao sao 35 mil problemas: sao dois, em ~17,9 mil linhas cada.

- **Q-B19** — registros do **importador Django de 2021** com `user_id=1` e `company_id`
  **forcados pelo ETL da epoca**. O autor registrado nao e quem lancou.
- **DB-154** — borderôs anteriores a **22/03/2022** tiveram a empresa atribuida **em bloco**
  por `fix_entries_without_company`, e nao escolhida no lancamento.

Nos dois casos o dado **existe e e plausivel**, mas **nao foi escolhido por ninguem**.
Preservar mantem a paridade e carrega uma atribuicao que talvez esteja errada; reatribuir
muda dado historico. **E decisao de negocio.**

### `D-10` — um **`NaN`** no valor de uma tarifa
Uma linha de `receivable_taxes`. Mas `NaN` **contamina o total, o liquido e os quatro
percentuais do borderô pai** — uma linha estraga um borderô inteiro, e em float o `NaN`
se propaga por toda soma que o encontre.

### Ainda sem caracterizacao fina (ficam para a proxima rodada)
`custom:renegotiations` (134) · `custom:renegotiation_attachments` (88) ·
`custom:risk_controls` (38) · `duplicates:renegotiations[project_id+integration_key]`
(9 grupos, 82 linhas) · `duplicates:availability_templates` (2 grupos) ·
`action_text:percent_encoded_body` (1).

## Duas correcoes minhas, de novo por artefato velho
- **O pino de Ruby mudou**: o Gemfile exige **3.4.9**. Minha instrucao de usar `rvm use 3.2.3`
  estava velha e **quebra o boot**.
- **Producao roda PostgreSQL 13.4**; aqui e 15.15.

## O que NAO muda
O dump e de **31/05/2025** e vive em banco isolado (`sfg_legacy_dump`), destruido ao fim.
**A demo de sexta continua no seed fake** (DEC-16). Nada disto entra no repositorio.

---

# DEC-121 (26/08/2026) — **nao existe "data da carga"**: a carga real depende da venda

Palavras do usuario: *"sobre a carga real ela so vai acontecer se o cliente resolver
comprar, entao a carga real ate o momento sao os arquivos que te mandei"*.

## O que isso dissolve

A **"data da carga"** era a **pendencia numero 1 do usuario** no checkpoint, e bloqueava:

| O que estava travado | Estado agora |
| --- | --- |
| S6 5.2 e 5.6 | **destravadas** — verificaveis contra o dump |
| S2 F.7 | **destravada** |
| **Paridade numerica do Phase 4 inteiro** | **verificavel agora** |

Eu instrui os cinco QAs do Phase 4 com a premissa antiga (*"paridade numerica espera a
carga; deixe `migrated` com o motivo escrito"*). **Corrigido em voo** — os tres em que o
numero pesa (recebiveis, risco, dados/infra) foram avisados de que o
`sfg_legacy_dump` esta disponivel e que a paridade e para ser feita **agora**.

## O que isso NAO dissolve

O dump e de **31/05/2025**. Ele prova que **as formulas batem** e que **o ETL funciona** —
**nao** e conferencia de virada. Se houver venda, havera um dump novo e uma reconciliacao
nova. Toda linha verificada contra este dump carrega essa data escrita.

## Consequencia pratica para o ETL

O ETL deixa de ser artefato a ser **construido e guardado** e passa a ser artefato a ser
**exercitado ate ficar verde** — porque o dado que ele vai migrar ja esta aqui. O ensaio
completo (`introspect` -> `dry_run` -> `load` -> `load de novo` -> `reconcile`) e agora o
**portao real**, nao um simulado.

E reforca uma coisa ja registrada: **a demo de sexta continua no seed fake** (DEC-16). O
dump serve para provar o pipeline, nunca para alimentar a apresentacao. Ele vive em banco
isolado (`sfg_legacy_dump`) e e destruido ao fim.


---

# DEC-123 (26/08/2026) — dado real de cliente **nao e versionado**

Instrucao do usuario, em duas partes: *"tudo que veio dos arquivos nao devem aparecer na
demo nem ficar no repositorio"* e, esclarecendo, *"enquanto estiver usando para testes e
fazer as coisas pode deixar, so nao pode commitar"*.

## A violacao que existia

`backend/spec/fixtures/receivables/producao_28131.json` (293 KB) estava **commitado**
desde `c3cd2684`. O proprio cabecalho declara a origem: *"sfg-31-may-25.sql — dump de
PRODUCAO de 31/05/2025"*, com **131 linhas curadas** de borderô real — entradas, tarifas e
os 33 derivados como o legado gravou.

Era o oraculo que prova o **DEC-02** (replicar o float para os totais baterem): o motor
rodou contra as 28.099 linhas limpas em 927.267 comparacoes.

## O que ficou

O arquivo **sai do versionamento e permanece no disco**. `git rm --cached` + entrada no
`.gitignore` cobrindo `producao_*.json`. Quem tem o dump roda os goldens; o repositorio
nunca carrega dado de cliente.

Os dois specs que o consomem carregavam o arquivo **no momento de carga** — sem ele, a
suite inteira quebrava. Agora ha guarda:

- **com** o golden: 158 exemplos, 0 falhas;
- **sem** o golden: 27 exemplos **pendentes**, com a razao escrita.

Pular e melhor que gerar zero exemplo: zero exemplo tambem passa, e a perda de cobertura
sumiria em silencio.

## O que foi auditado e esta limpo

- **O banco da demonstracao** (`sfg9_dev`): 12 projetos, todos ficticios do seed
  ("Componentes Vale do Rio", "Distribuidora Campo Largo", "Quimica Paulista Reunidas"…).
  **Nada do dump chegou la.**
- **`backend/db/etl/fixtures/*.yml`**: sinteticas por construcao — "ETL Fixture Cliente
  Um", e-mails `@safegold.invalid`.
- **`tmp/`** (onde vivem os relatorios do ETL, que trazem ids e valores) esta no
  `.gitignore`.
- **`.migration-ai9/analise-dump-producao.md`**: prosa e analise, sem valor identificavel.

## O que continua permitido

Os bancos locais (`sfg_legacy_dump`, `sfg9_etl_rehearsal`) e os arquivos que o usuario
enviou **ficam** enquanto o trabalho precisar deles. A restricao e sobre **commitar**, nao
sobre usar.

## A ressalva honesta

`git rm --cached` tira do estado atual, **nao do historico**. O arquivo continua alcancavel
em `c3cd2684` e nos commits seguintes. Apagar do historico exige reescrever a linha — o que
com varios agentes trabalhando na mesma arvore hoje seria imprudente. **Fica registrado
como pendencia**, para ser feito com a bancada vazia, se o usuario quiser.

---

# DEC-124 (26/08/2026) — o dump **e** a carga real, e o ETL roda **no servidor**

Esclarecimento do usuario, em duas partes que mudam coisas diferentes:

> *"ja te passei a carga real, e para usar os arquivos que te mandei pra isso"*
> *"por questoes de contrato o banco que esta em producao hoje, o dump nao vai do servidor
> pro computador de ninguem — ou seja, vamos rodar tudo la quando for pra prod"*

## 1. Nao existe "esperar a carga". O dump E a carga.

Isto **encerra** de vez a pendencia que o checkpoint carregava como item numero 1 do
usuario. Os itens do razao que ficaram `migrated` citando *"espera a carga"* — cerca de
**90** — sao **verificaveis agora**, contra `sfg_legacy_dump`.

A DEC-121 ja tinha dito metade disso; o que faltava era a segunda metade: **nao vira outro
dump depois**. O de 31/05/2025 e o material de trabalho, e e com ele que a paridade
numerica se prova.

## 2. O ETL roda **no servidor de producao**, nao aqui

Restricao **contratual**, nao tecnica: o dump nao sai do servidor. Consequencias diretas
para o que ja esta construido:

- **O runbook de cutover muda de leitor.** Ele deixa de descrever "baixe o dump e rode" e
  passa a descrever **execucao no servidor**, por quem tem acesso la. Todo passo que
  pressupoe arquivo local precisa ser relido com esse olho.
- **`SOURCE=db` com `SFG_LEGACY_URL` e o modo de producao**, nao `SOURCE=dump`. O ensaio
  local com `sfg_legacy_dump` continua valendo como **ensaio**; o cutover aponta para o
  banco vivo, na propria maquina dele.
- **A reconciliacao final acontece la.** O que provamos aqui e que **as formulas batem** e
  que **o pipeline funciona** — contra o retrato de 31/05/2025. A conferencia contra o
  estado do dia da virada e feita no servidor, com o dado de la.
- **Recursos da maquina de destino passam a importar.** `risk_entries` tem 642.447 linhas;
  lote, retomada e janela precisam caber no que o servidor oferece, nao no que esta
  bancada oferece.

## 3. O que NAO muda
A **DEC-123** continua integral: dado real **nao e commitado**. O dump e os arquivos ficam
nesta maquina enquanto o trabalho precisar deles, e a **demonstracao de sexta continua no
seed ficticio**.

---

# DEC-125 (27/08/2026) — `providers`: a **quarta** vez do mesmo achado

O conversor de `providers` aborta com `duplicates:providers[project_id+integration_key]`:
**6 grupos, 163 de 289 linhas** (um deles com 119). So ha 132 pares distintos — com a
unicidade de pe, **157 fornecedores nao entram**.

## Por que eu decido isto sozinho

E a **quarta ocorrencia do mesmo padrao**, e o usuario ja decidiu as tres anteriores da
mesma forma (DEC-119): `carriers[bank_code]` (sentinelas 8888/999/9999),
`livetat_auth_users[username]` (vazio), `renegotiations[project_id+integration_key]` (o
rotulo literal "Renegociação") e `availability_templates[title]` (vazio).

A evidencia aqui e ainda mais clara: dentro de cada grupo os **titulos sao todos
distintos**, e as chaves estao em **CAIXA e com acento** — forma que a derivacao automatica
do legado nunca produziria. Sao **rotulos de classificacao digitados por gente**, nao
chaves de integracao. Num dos grupos o rotulo e literalmente o mesmo do caso ja decidido
na DEC-119.

**Decisao: mesmo tratamento.** A unicidade de `(project_id, integration_key)` vira
**parcial**, ignorando os rotulos repetidos; as 289 linhas entram como estao. Nenhum dado
de cliente e reescrito.

## O que isto exige, e que a assinatura sozinha NAO resolve

O agente mediu e avisou: **autorizar a chave no `decisions.yml` nao destrava**. Com a
autorizacao num arquivo de ensaio, a carga **ainda para** em `RecordInvalid: Integration
key ja esta em uso neste projeto` — porque a validacao vive no **model**, nao so no indice.

Entao sao duas mudancas, e ambas sao da S4:
1. **migration** tornando o indice parcial/nao-unico;
2. **a validacao do model** relida, para nao recusar o que o indice passou a aceitar.

Enquanto as duas nao existirem, `providers` **continua bloqueado** — e esta escrito, nao
esquecido.

## A licao que a repeticao ensina

Quatro vezes o mesmo achado, sempre com a mesma causa: **nos derivamos unicidade da
INTENCAO do schema legado, e o legado usa vazio, sentinela e rotulo humano como "nao se
aplica"**. Para as fatias que ainda vierem: antes de declarar `unique` num campo herdado,
**contar os distintos no dump**. Custa uma consulta e evita um bloqueio de carga.

---

# DEC-127 (27/08/2026) — **decisao registrada nao e decisao implementada**

A carga completa contra o dado real (679.283 linhas, `risk_entries` 642.447/642.447)
revelou um padrao que vale mais que os defeitos que ele produziu.

## O achado

**Ha decisoes assinadas em `db/etl/decisions.yml` que NUNCA viraram codigo.** O agente de
paridade foi conferir no banco e mediu:

| Decisao registrada | Estado real |
| --- | --- |
| `carriers[bank_code]` -> indice **parcial** (DEC-119) | o indice parcial **nao existe** no banco |
| `renegotiations[project_id+integration_key]` -> parcial (DEC-119) | **nao existe** |
| `availability_templates[title]` -> parcial, "ignora titulo vazio" (DEC-119) | **nao existe** — e 90 de 2.705 linhas com titulo vazio **derrubam a carga** |
| tarifa `NaN` -> **NULO** (DEC-120) | so metade feita: outro agente corrigiu a tarifa, mas **32 borderôs** com `NaN` nos DERIVADOS continuam matando `receivable_entries` |
| `providers` -> unicidade parcial (DEC-125) | precisa de migration **e** de reler a validacao do model |

**O `decisions.yml` autoriza o ETL a prosseguir. Ele NAO altera schema nem validacao.**
Assinar a chave e condicao **necessaria e insuficiente**: enquanto a migration e o model
nao acompanharem, a carga para no mesmo lugar — agora com a autorizacao no arquivo,
o que e pior, porque *parece* resolvido.

## Por que isso passou despercebido tanto tempo

**D-PAR-04, o defeito que esconde os outros.** `Sfg::Etl::Base#write!` chama `save!` e
**ninguem rescata `RecordInvalid`**. Consequencia: a carga morre **na primeira linha
invalida** e voce descobre **um defeito por execucao**. Foi assim o dia inteiro:

1. slug com `&` e `.` -> corrigido (DEC-122)
2. CEP de 7 digitos, 3 de 83 projetos -> corrigido (`36cbb7c9`)
3. titulo vazio em 90 templates -> **aberto**
4. `NaN` nos derivados de 32 borderôs -> **aberto**
5. `providers` ausente parando as 169 renegociacoes -> **aberto**

Cada um so apareceu depois de o anterior sair do caminho. **Nao ha como saber quantos
faltam** — a unica forma de descobrir e continuar rodando e batendo num de cada vez.

## O que fazer, e a ordem importa

**Primeiro o motor, depois os casos.** Enquanto `write!` morrer no primeiro invalido,
cada conserto custa uma execucao inteira (a carga leva ~1h so de `risk_entries`).

O motor deve **coletar** as falhas de validacao num relatorio e seguir, em vez de levantar
— exatamente como ja faz com anomalia declarada. Ai **uma** execucao revela **todos** os
casos restantes de uma vez, e a decisao sobre eles pode ser tomada em bloco.

Isto e diferente de "ignorar erro": a linha invalida **nao entra**, sai **listada**, e o
dry-run continua abortando. O que muda e que a carga nao para de descobrir no primeiro
achado.

## A licao, para as fatias que ainda vierem

**Toda decisao que fala de indice, validacao ou tipo de coluna precisa de um item de
tarefa junto.** Registrar a decisao e o comeco do trabalho, nao o fim — e a distancia
entre os dois ficou invisivel porque o `decisions.yml` da a sensacao de que algo foi
resolvido.

---

# DEC-128 (27/08/2026) — quatro travas de carga, decididas pelo usuario

## DEC-128.1 — CEP de 7 digitos: **entra VAZIO e vai listado**
3 dos 83 projetos. O legado nao validava CEP; o ai9 valida 8 digitos.

**Nao completar com zero a esquerda**, que era a alternativa tentadora: corrigiria a
maioria dos casos reais (o zero comido por planilha) e, no caso que **nao** fosse esse,
gravaria endereco errado **em silencio**. Um CEP de 7 digitos nao e um CEP — e adivinhar
qual digito falta e fabricar dado.

**Efeito:** carrega com `cep` vazio e LISTA os 3 com o valor de origem.

## DEC-128.2 — Anexos: **o mecanismo esta provado; os binarios NAO ficam agora**
Palavras do usuario: *"se ja testamos os binarios e funcionou ok, mas nao vao ficar no
projeto nesse momento"*.

**A DEC-84 caiu pela premissa** (nao tinhamos o disco) e o mecanismo foi **provado**: 44
anexos, 44 binarios, 39.424.330 bytes reconciliados **por magic bytes**, 135x135 avatares.
O que **nao** acontece agora e os arquivos ficarem nesta maquina/projeto — coerente com a
**DEC-123** (dado real nao fica) e com a **DEC-124** (o ETL roda no servidor).

**Efeito:** `relink_attachments` continua sendo **passo de cutover, executado no servidor**,
com `SYSTEM_ROOT` apontando para o acervo de la. A capacidade esta pronta e verificada; a
execucao e no dia da virada. A demonstracao de sexta segue no seed ficticio, sem anexo real.

## DEC-128.3 — Os 32 borderôs com `NaN` nos derivados: **recalcular pelo motor**
Diferente da tarifa (DEC-120, que entra NULA): aqui o `NaN` esta nos campos **derivados**
(recompra, retencao, fomento e os demais calculados), e as **entradas digitaveis estao
integras**.

Recalcular **nao inventa dado** — restaura o que o proprio calculo deveria ter gravado, e
usa o mesmo motor que a tela usa (contrato C2). E o unico caminho que mantem a contagem
batendo com o legado **e** os numeros somaveis.

**Efeito:** o conversor recalcula os derivados a partir das entradas e LISTA os 32, com o
valor de origem e o recalculado, lado a lado, para conferencia.

## DEC-128.4 — 90 padroes de disponibilidade com titulo vazio: **indice parcial**
**Quinta ocorrencia do mesmo padrao** (depois de `carriers[bank_code]`,
`users[username]`, `renegotiations[project_id+integration_key]` e `providers`). Titulo
vazio e "nao se aplica", e unicidade nao deveria alcanca-lo.

Gerar titulo a partir do contexto foi recusado: seria texto que **ninguem escreveu**
aparecendo na tela como se fosse do cliente.

**Efeito:** unicidade parcial ignorando titulo vazio; as 90 entram como estao.

> **A mesma armadilha da DEC-127 vale para 128.4 e 128.3:** assinar a chave **nao basta**.
> A 128.4 precisa de **migration** (indice parcial) e da **validacao do model** relida; a
> 128.3 precisa do **conversor** chamando o motor. Ficam como tarefa, nao como decisao
> cumprida.

---

# DEC-129 (27/08/2026) — storage, abertura de 2022, lancamentos orfaos e o aceite

## DEC-129.1 — Storage: **`Disk` com volume persistente garantido pelo deploy**

O ETL hoje **recusa** `Disk` (`OPS-616`) em vez de confiar. A decisao do usuario mantem
`Disk`, com a condicao de o deploy garantir um volume que sobreviva.

**O que isso obriga a mudar, e a forma importa:** o ETL nao deve simplesmente **parar de
recusar** — isso trocaria uma trava por silencio. Ele passa a aceitar `Disk` **quando
alguem afirmar explicitamente** que o volume existe (variavel de ambiente dedicada, com
nome que diga o que esta sendo afirmado). Assim a confirmacao tem **autor** e aparece no
runbook, em vez de virar um `if` que ninguem le.

**O runbook de cutover ganha um pre-requisito**: confirmar o volume **antes** de rodar a
carga, e conferir que ele sobrevive a um redeploy. Anexo que some entre deploys e o tipo
de defeito que so aparece semanas depois, quando ninguem lembra do dia da virada.

**Destrava 31 itens** do razao.

## DEC-129.2 — Abertura por modalidade de 2022: **manter como esta no legado**

Palavras do usuario: *"manter como e no legado"*.

O legado **tem** a abertura por modalidade de jan-abr/2022 — **R$ 4.884.851.467,94** em
4.082 linhas (161 limites, 19 projetos). O nosso conversor deriva os totais das parcelas,
e nessas linhas as parcelas estao zeradas: o total continua correto (4.082/4.082), mas o
**detalhe some**.

**Decisao: preservar o detalhe.** O conversor copia o valor da origem quando as parcelas
vierem zeradas, em vez de derivar zero. E o que mantem a tela de limites legivel por
modalidade naquele periodo — que e exatamente como ela mostra.

## DEC-129.3 — Os 51 lancamentos sem conexao: **criar a conexao que falta**

51 lancamentos de indicador existem em producao para pares (projeto, indicador) **sem
conexao**. A grade do ai9 e montada pelas conexoes, entao eles carregariam e **nunca
apareceriam**.

**Se ha lancamento, alguem usou aquele indicador naquele projeto** — o que sumiu foi a
conexao. Cria-la restaura a visibilidade, e os 51 saem **listados**.

O criterio geral que isto estabelece: **dado migrado que nao e alcancavel pela interface
e dado perdido na pratica**. Carregar sem poder ver nao cumpre "nada se perde".

## DEC-129.4 — Aceite dos Termos: **replicar o legado** (D-64)

Decisao do usuario: manter o aceite implicito como esta.

### CORRECAO (27/08/2026) — **o D-64 nao e defeito neste contexto, e o erro foi meu**

Resposta do usuario: *"nao e bem defeito, pois e um app corporativo, nao um app para o
publico geral"*.

**Ele esta certo, e isto muda a CLASSIFICACAO, nao so o veredito.** Eu apliquei a um
sistema **corporativo** uma norma de aplicativo de **consumo**: clique explicito, prova de
consentimento, IP e data. Num produto B2B o vinculo legal e o **contrato comercial entre
as empresas**; o aceite dentro do sistema e **registro operacional**, nao a peca que
obriga. Chamar aquilo de "consentimento que ninguem deu" so faz sentido se o clique for o
que vale — e aqui nao e.

O usuario nao entra por conta propria: e cadastrado por quem ja tem contrato assinado.

**Efeito no registro:** o **D-64** deixa de ser defeito e passa a ser **comportamento
esperado do dominio**, com esta nota. Nao ha veredito de "corrigir" a inverter, porque nao
havia o que corrigir. O `after_create` do legado e portado como esta.

**A licao, e ela vale para o resto do catalogo de defeitos:** varios dos 125 foram julgados
por norma geral de aplicacao web. **Norma sem contexto de negocio produz falso positivo** —
e um falso positivo caro, porque leva o usuario a decidir sobre um problema que nao existe.
Antes de classificar algo como defeito de conformidade, perguntar **quem e o usuario do
sistema e como ele entra**.

**Consequencia que fica aberta:** o **DEC-18.7** desligou o cadastro publico, entao o
gatilho do legado (criacao de conta pela web) **nao existe mais**. Replicar o mecanismo
exige decidir **onde** ele dispara agora — no convite, provavelmente. Isso e implementacao,
nao decisao nova, e vai como tarefa da fatia de contratos.

O **D-65** (qual o conjunto minimo de prova do aceite) fica **prejudicado**: sem aceite
explicito, nao ha prova a coletar. Registrado como tal, para ninguem procurar a resposta
depois.


---

# DEC-130 (27/08/2026) — ReceitaWS fica para **depois da venda**

Decisao do usuario: *"vamos deixar esse para se o cliente comprar, e ai terminamos a
implementacao"*.

## O que foi medido antes de decidir

- **E servico pago.** O legado configura `config.token = ENV[rws_api_token]`
  (`config/initializers/receitaws.rb`), ou seja, plano registrado — a ReceitaWS tem
  endpoint publico sem token, mas limitado por taxa. **Esse token estava commitado no
  legado** e esta na lista de segredos a rotacionar.
- **A dependencia e estreita.** Uma chamada so no legado: `CnpjApi.get_info` em
  `pub/providers_controller.rb:124` — **autopreenchimento do cadastro de fornecedor**. Ha
  ate uma segunda chamada **comentada** na linha 71: alguem ja a desligou em algum momento.
- **O ai9 ja tem o caminho pronto**: `api/v1/cnpj_lookup.rb`, com validacao e degradacao
  **provadas por execucao** — 422 para CNPJ invalido, 503 com a mensagem certa quando o
  servico nao responde.

## Por que adiar nao custa nada agora

**Sem a chave, o cadastro de fornecedor continua funcionando** — o usuario digita em vez de
o sistema preencher. A demonstracao roda com seed ficticio e ninguem consulta CNPJ real na
frente do cliente.

## O estado dos 2 IDs

`BE-064` e `OPS-050` ficam **`blocked` por dependencia externa**, com este texto na linha —
**nao** `migrated` e **nao** pendencia tecnica. O codigo esta pronto e provado nos dois
caminhos de erro; falta **credencial**, que e decisao comercial.

## O que reavaliar se houver venda

Antes de renovar a assinatura, vale comparar: hoje ha alternativas gratuitas de consulta de
CNPJ (a Receita Federal expoe dados publicos, e ha servicos que os republicam). Trocar de
fornecedor e opcao real, e o ponto de integracao ja esta isolado num endpoint so — o que
torna a troca barata. **Nao e decisao para agora.**

---

# DEC-131 (27/08/2026) — o indice parcial cujo predicado depende de coluna DIFERIDA

## O sintoma
`sfg_etl:load` morre em `availability_templates` (2000 de 2705) com
`RecordNotUnique` em `index_availability_templates_unique_root_title` — indice unico
parcial, `WHERE parent_template_id IS NULL AND title <> ''`.

## O mecanismo, medido depois de TRES hipoteses erradas
A hierarquia deste conversor e **diferida**: `parent_template_id`, `top_parent_id` e
`global_availability_template_id` apontam para a propria tabela e sao resolvidos num
**segundo passo, ao fim da carga**. Durante a carga, portanto, **toda linha e gravada com
`parent_template_id = NULL`** — e o predicado do indice enxerga **todas como raiz**.

| Medicao na origem | Colisoes |
| --- | ---: |
| entre raizes REAIS | **0** |
| **se todas virarem raiz** (o que a carga faz) | **1** |

E um par so: mesmo projeto, mesmo titulo normalizado, um raiz e o outro filho.

## As tres hipoteses que derrubei, e por que registro isso
1. *"pai orfao vira raiz"* — medido: **0** filhos com pai inexistente, **0** com pai de id
   maior.
2. *"duas tabelas da origem alimentam a mesma do destino"* — so existe uma.
3. *"o `sti_class` colapsa dois `type` diferentes"* — a origem tem **2** valores de `type`,
   e ambos ja sao as duas classes; nao ha colapso.

Errei as duas primeiras medicoes por agrupar pelo `type` **cru** (e nao pela classe que o
conversor calcula) e pelo titulo **sem normalizar**. **A hipotese certa era a primeira; o
que estava errado era a consulta.** Vale a licao: quando a medicao contradiz uma hipotese
plausivel, conferir se a consulta reproduz o que o CODIGO faz — nao o que a coluna guarda.

## O desenho que o defeito expoe
**Um indice unico parcial nao pode ter, no predicado, uma coluna que a carga preenche
depois.** Ele esta correto para o estado final e errado para todo o intervalo da carga.

## O conserto
Resolver a hierarquia **em linha quando o pai ja estiver no de-para**, mantendo o passo
diferido apenas como fallback. Medicao que autoriza: **as tres colunas diferidas apontam,
em 100% das linhas, para ids MENORES** — lendo em ordem de id, o pai ja foi mapeado.

Manter o fallback importa: a medicao vale para **este** dump. Um dump futuro com ordem
diferente continuaria correto, so mais lento.

---

# DEC-132 — Os callbacks do model competiam com o ETL (`etl_loading`)

**27/08/2026. Registrada pelo orquestrador; nao exigiu decisao do usuario — e conserto de
defeito, com a medicao no lugar da opiniao.**

## O que parecia e o que era
`availability_entries` parava com violacao do indice parcial de consolidacao. Pareceu, por
tres rodadas, defeito de esquema ou de de-para. **Nao era.** Medido:

| hipotese | medicao | veredito |
| --- | --- | --- |
| origem tem duplicata na chave | 0 grupos em 23.674 linhas, com `date` cru E truncado | **falsa** |
| `date` e timestamp e trunca para dia | a coluna JA e `date` na origem | **falsa** |
| o de-para colapsa dois legacy_pk num ai9_id | 0 ocorrencias, em TODAS as tabelas | **falsa** |

A duplicata era **fabricada pelo proprio model**. `after_save :propagate_derived_values`
materializa o padrao base seguinte por `find_or_initialize_by(project, company, template,
date)` — **sem `legacy_id`**. Gravar o lancamento 3 criava a linha do `Saldo Liquido 2` de
01/03/2022; o motor lia o 4, que **e** aquela linha, nao a achava pelo `legacy_id` (o
`natural_key` do motor) e inseria a segunda.

## Os dois estragos que NAO derrubavam nada
Piores que o que derrubava, porque passariam:

1. `recompute_and_save!` **recalcula** `virtual_value` — e a **DEC-24** manda copiar.
2. `mark_consolidation` marcaria as 23.674 linhas como consolidacao (em producao a coluna
   `company_id` nao existe). Consolidacao no ai9 e derivada e **nao editavel**: o cliente
   abriria a grade e nao conseguiria digitar em celula nenhuma.

## O conserto e por que ele e FIEL
`etl_loading` desliga os tres, no mesmo desenho do `preserve_safegold_stamp` (DEC-112).
Desligar nao e facilidade: **a origem ja tem cada linha derivada como linha propria**,
gravada por este mesmo callback ao longo de tres anos no legado. Copia-las reproduz
producao; recalcula-las a substitui por um estado que nunca existiu.

**Licao de desenho:** ETL que grava por `save!` herda os callbacks do model, e callback de
app e escrito para o usuario DIGITANDO — nao para carregar verdade historica. Todo model com
callback derivado precisa da chave, ou o ETL briga com ele.

Depois: **23.674/23.674**, zero linha sem `legacy_id`, zero marcada como consolidacao.

---

# DEC-133 — `attachments_count` DOBRADO, e a carga passava verde

**27/08/2026.**

`RenegotiationAttachment` declara `counter_cache: :attachments_count` e o conversor de
`renegotiations` **copiava a mesma coluna** da origem. O Rails somava por cima a cada anexo.
Medido: **35 das 169** renegociacoes erradas, contador somando **88** contra **44** anexos
reais — exatamente 2x.

**Por que ninguem viu:** a coluna e `null: false` com default 0, dobrar nao viola restricao
nenhuma, e a reconciliacao de CONTAGEM passava (as 44 linhas de anexo estao la). So a
amostra campo a campo mostrou — e essa secao e `info`, nao bloqueia.

Conserto: a copia saiu, a coluna virou `derived`, e `RenegotiationAttachments.post_load!`
reconcilia contra o destino num `UPDATE` unico e idempotente. Depois: **169 certas, 0
erradas, 44 = 44**.

**Regra que fica: contador derivado nao se copia.**

---

# DEC-134 — A reconciliacao passa a LER as decisoes assinadas (`discard:<tabela>`)

**27/08/2026. Formaliza no portao 3 a DEC-126, ja assinada pelo usuario.**

O comentario do `counts_section` promete desde o comeco: *"descarte por decisao registrada e
diferenca esperada"*. **O codigo nunca consultava as decisoes.** O portao reprovava
`contract_deals 272 -> 270`, que e a DEC-126 sendo **cumprida** — o usuario decidiu descartar
os 2 aceites orfaos de `user_id`. E a DEC-127 pelo avesso: decisao registrada que nao estava
implementada.

`expected_delta` na decisao e o que mantem o portao apertado: **faltar 2 e decisao cumprida,
faltar 3 volta a abortar**, com o numero na mensagem. Autorizar "esta tabela tem descarte"
sem a contagem seria cheque em branco por tabela, e o curinga `discard:*` e recusado pelo
mesmo motivo — como ja vale para orfao e duplicata.

---

# DEC-135 — Duas fragilidades do portao, medidas e registradas

**27/08/2026. NAO consertadas: registradas com evidencia, porque mudam o desenho do motor.**

## 1. A retomada esconde a linha recusada
`RESUME=1` (o padrao) nao revisita linha recusada — o que e **certo** para a carga (seria
recusada de novo) e **errado** para o RELATORIO: uma segunda execucao sai **verde sem que
nada tenha sido consertado**.

Medido nesta base: 32 `receivable_entries` e 64 `receivable_taxes` recusadas numa execucao
anterior ao conserto dos `NaN` (DEC-128.3). O conserto ja estava no codigo ha horas; as
linhas continuavam fora, e a carga dizia "Sem bloqueio". **Quem as achou foi a
reconciliacao**, nao a carga — e so porque ela conta contra o destino, nao contra a execucao.

`RESUME=0` nas duas tabelas gravou **exatamente 32 e 64**.

**Consequencia para o cutover: relatorio de carga verde nao vale sozinho. O portao e a
reconciliacao.**

## 2. A amostra campo a campo e `info`, e o ruido esconde defeito
As 20 divergencias da amostra sao **todas** normalizacao declarada dos models — cada uma
rastreada ate o callback: `normalize_username` (DEC-45), `normalize_catalog_title`,
`derive_integration_key`, `normalize_address`. Nenhuma e defeito.

Mas foi **exatamente nesse ruido** que o `attachments_count` dobrado (DEC-133) passou
despercebido: 20 linhas de "divergencia" esperada, e a 21a era real.

**Nao declarei as colunas como `derived` para calar a secao.** Silenciar `title` e `cep`
tiraria da comparacao 24 linhas certas para esconder 1 espaco em branco — trocaria um
detector de defeito por arrumacao, que e o erro que causou este proprio achado. O conserto
certo e a secao separar "normalizacao conhecida" de "divergencia inexplicada", como o
`counts_section` passou a fazer na DEC-134. **Fica para o Phase 5.**

---

# DEC-136 — O anexo volta a existir na CRIACAO

**27/08/2026. Resposta do usuario: "deixar igual ao legado".**

Em quatro telas o upload de imagem so aparecia DEPOIS de salvar — conta (FE-021),
portador (FE-067), fornecedor (FE-074) e projeto (FE-087). Era deliberado e
estava comentado no codigo (o arquivo precisa de um id), mas sem decisao
registrada, e o legado aceitava o envio ja no cadastro.

**Efeito:** o arquivo escolhido no formulario fica em memoria e sobe logo depois
que o POST devolve o id. A falha do segundo passo NAO desfaz o cadastro: o
registro fica criado e a tela diz que a imagem nao subiu, com o caminho para
tentar de novo. Perder o cadastro inteiro porque a foto falhou seria trocar um
incomodo por uma perda.

---

# DEC-137 — Os cinco pontos divergentes voltam ao legado

**27/08/2026. Resposta do usuario: "o filtro e para a dashboard, o restante tem
que ser igual ao legado" e, depois da medicao, "replicar o legado nos cinco".**

| ID | O que o ai9 fazia | O que volta a valer |
| --- | --- | --- |
| BE-131 | autor do lancamento OPCIONAL | obrigatorio, como no legado |
| BE-148 | consolidacao itera PADROES e limita sempre ao mes | itera lancamentos; com `date` preenchida devolve o historico |
| BE-183 | `where` acrescenta `is_static: true` | sem o filtro — a operacao nao estatica volta a poder receber a liberacao |
| BE-194 | `order_mode=dash` descarta `state`/`kind` | aplica os dois tambem no dash |
| BE-275 | transferencia pre/par recusa com 422 | grava o movimento de saida; so a CONTRAPARTIDA depende de `is_pre?` |

## A medicao que decidiu, e que corrigiu a minha suposicao

O usuario respondeu "o filtro e para a dashboard" — e havia DOIS filtros na
lista. Em vez de escolher pelo nome (`dash` sugere dashboard), fui medir:

  * a dashboard do ai9 tem endpoint proprio (`/api/v1/dashboard/summary` e
    `/volume_by_carrier`) e consome `Dashboard::SummaryService` e
    `Risk::AggregateService` DIRETO. Nao passa por nenhum dos dois;
  * `order_mode=dash` nao tem **um** chamador no frontend — `grep -rn
    'orderMode:' src/app src/features` volta vazio. E superficie de API herdada
    do legado, orfa;
  * `is_static` nao aparece em ponto nenhum do dashboard: e a marca do par
    pre/antecipacao (B-08), e no `where` do BE-183 ela faz o **bordero ser
    recusado com 422** onde o legado gravava.

Nenhum dos dois era excecao da dashboard. Com isso, a regra do usuario ("o
restante tem que ser igual ao legado") passou a valer para os cinco.

**Licao:** o nome sugeria a resposta (`dash` = dashboard) e a resposta estava
errada. A dashboard do ai9 foi construida nova, com endpoint dedicado, e o modo
`dash` do legado ficou orfao junto.

---

# DEC-138 — `client_applications` e DESCARTADA, coerente com a trilha

**27/08/2026. Resposta do usuario: "descartar, coerente com a trilha".**

`livetat_auth_client_applications` tem 3 linhas em producao e nao tinha conversor
nem entrada em `do_not_migrate`. Antes de perguntar, medi:

  * as 3 sao **exatamente o seed do engine** (`auth19/db/seeds.rb:179-181`) —
    iOS, Android e Joker, criadas no mesmo segundo em 27/02/2022 e nunca
    atualizadas. Nao ha app iOS nem Android; nao e integracao de cliente;
  * elas autenticam por token+agente, e o **unico** consumidor no legado inteiro
    e o `Api::V1::TrackingsController`. Nenhum outro controller herda de
    `ApiApplicationController`;
  * essa trilha **ja foi descartada** nesta migracao: BE-430, BE-431, BE-433 e
    BE-434 estao `dropped` no razao. So o BE-432 (a listagem) ficou `verified`.

Ou seja, a tabela ficou orfa quando a trilha saiu. Nao e "migrar tokens ou
rotacionar": e reconhecer o orfao e registra-lo.

**Efeito:** DB-009, DB-504 e DB-543 viram `dropped`; a tabela entra em
`do_not_migrate` com a contagem medida (3 linhas, todas de seed).

---

# DEC-139 — O rastreio de acesso do Devise MIGRA, com coluna nova

**27/08/2026. Resposta do usuario: "criar as colunas e migrar".**

O legado guarda 86 usuarios com data de ultimo login e 6.134 acessos somados. As
colunas `sign_in_count` e `last_sign_in_at` **nao existem** na tabela `users` do
ai9 — nao era mapeamento faltando, era coluna inexistente, e por isso o item
estava travado e nao "esquecido".

**Efeito:** migration nova em `users`, conversor le as duas colunas da origem, e
o historico atravessa.

⚠ **O contador passa a misturar dois mecanismos.** O legado contava login por
senha; o ai9 entra por link magico e por codigo. O numero herdado e historico do
mecanismo ANTIGO, e o que crescer daqui para frente e do novo. Fica escrito na
migration para ninguem somar as duas coisas achando que sao a mesma.
