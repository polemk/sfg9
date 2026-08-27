# Runbook de cutover — Safegold (`sfg`) → ai9 (`sfg9`)

**Fatia S14 · tarefa 9.1.** Versionado de propósito: runbook que não está no repositório
não é revisado, e runbook não ensaiado é rascunho.

Este documento é o que o time executa **na janela**. Cada passo tem: quem faz, o comando
exato, o artefato que produz e o critério de go/no-go. Um passo sem artefato anexado
**não está concluído**.

> **Relido inteiro em 27/08/2026 com o olho da DEC-124.** Ele descrevia "baixe o dump e
> rode aqui"; passa a descrever **execução no servidor de produção**, por quem tem acesso
> lá. Mudaram: a §0 (nova, e é a primeira a ler), a §1.0 (pré-requisitos da máquina), o
> Passo 3 (caminho do legado no servidor), o Passo 4 (`SOURCE=db` é produção), o Passo 6
> (`SYSTEM_ROOT`, não `SYSTEM_TAR`), a §5 (relatório sai do servidor e não entra no
> repositório) e a §6 final (o bloco do dump é **ensaio**, com a tradução comando a comando).
> E nasceu o **Passo 7b**, que é onde a janela se dimensiona: `risk_entries` sozinha é 82% das
> linhas.

---

## 0. ONDE isto roda, e por quem — leia antes de qualquer outra coisa (DEC-124)

> **O cutover roda NO SERVIDOR DE PRODUÇÃO DO LEGADO. Nada é baixado.**
>
> É restrição **contratual**, não técnica, e são palavras do usuário:
> *"por questões de contrato o banco que está em produção hoje, o dump não vai do servidor
> pro computador de ninguém — ou seja, vamos rodar tudo lá quando for pra prod"*.

Isso muda **quem** executa e **de onde**, e por isso muda quase todo comando deste
documento. As três consequências, e cada uma reaparece no passo correspondente:

| | Ensaio (esta bancada) | **Cutover (o servidor)** |
| --- | --- | --- |
| Origem | `SOURCE=dump DUMP=…` sobre `sfg-31-may-25.sql`, ou `SOURCE=db` contra a cópia isolada `sfg_legacy_dump` | **`SOURCE=db SFG_LEGACY_URL=…` contra o banco VIVO**, na própria máquina |
| Acervo de anexos | `SYSTEM_TAR=…` (o `.tar` como veio, lido em fluxo) | **`SYSTEM_ROOT=/caminho/do/deploy/public/system`** — o diretório está lá, não há tar a copiar |
| Quem digita | qualquer um do time, aqui | **só quem tem acesso ao servidor.** Se essa pessoa não é quem escreveu isto, cada passo precisa ser executável sem contexto — é o motivo de todo comando aqui estar por extenso |

**O que a DEC-124 encerra:** não existe "esperar a carga". O dump de **31/05/2025** que
temos **é** o material de trabalho, e **não virá outro**. Os ~90 itens do razão que ficaram
`migrated` citando "espera a carga" são verificáveis **agora**, contra `sfg_legacy_dump`.

**O que ela NÃO encerra:** o dump é um **retrato de 31/05/2025**. Ele prova que as fórmulas
batem e que o pipeline funciona. A **reconciliação da virada acontece no servidor, contra o
dado de lá** — que terá mais linhas, e possivelmente anomalias que este retrato não tem.
Todo número deste runbook carrega a data em que foi medido, por isso.

**E o que a DEC-123 mantém:** dado real **não é commitado**. Relatório do ETL sai em
`backend/tmp/etl/`, que está no `.gitignore`. Nenhum arquivo gerado no servidor volta para
o repositório.

---

## 0.1 O que este runbook assume, e o que ele NÃO faz

- O ETL **não corrige dado do cliente**. Anomalia vira linha de relatório, nunca `UPDATE`
  silencioso. Autorizar uma anomalia é acrescentar uma linha assinada em
  `backend/db/etl/decisions.yml` — que aparece no diff e tem autor.
- Todo relatório é **arquivo** em `backend/tmp/etl/`, com carimbo de data e um
  `-latest.md` estável. É o que se anexa à aprovação.
- **Portão verde não prova que funciona.** `rspec` e `zeitwerk:check` provam que o código
  carrega. Nesta migração o login já ficou quebrado com a suíte inteira verde. O que vale
  é o **ensaio executado** (§8) e os três relatórios assinados.

---

## 1. PRÉ-REQUISITOS BLOQUEANTES — sem estes, não há janela

### 1.0 A máquina onde isto vai rodar (DEC-124) — conferir ANTES de marcar a janela

Estes seis não existiam neste runbook enquanto ele supunha "baixe o dump e rode aqui".
Todos são **do servidor**, e cada um deles, faltando, para a janela **depois** do Passo 1
(origem congelada) — que é o pior lugar possível para descobrir.

| # | Pré-requisito no servidor | Como conferir, em uma linha |
| - | ------------------------- | --------------------------- |
| 1.0a | **Ruby 3.4.9** (o que `.ruby-version` e o `Gemfile` pinam). ⚠ A instrução antiga de `rvm use 3.2.3` está morta e **quebra o `bundle exec`** | `ruby -v` |
| 1.0b | **O repositório `ai9` na branch `sfg9`, com `bundle install` já feito** | `git -C <repo> rev-parse --abbrev-ref HEAD && bundle check` |
| 1.0c | **O repositório do LEGADO acessível** — é dele que sai o baseline do Passo 3 (as 139 migrations). No servidor ele normalmente É o diretório de deploy da aplicação em produção | `ls <legado>/db/migrate \| wc -l` |
| 1.0d | **Credencial de LEITURA do banco vivo** (`SFG_LEGACY_URL`) e **de escrita do destino** (`DATABASE_URL`). Duas URLs diferentes, e nunca a mesma | `psql "$SFG_LEGACY_URL" -c 'select 1'` |
| 1.0e | **Disco livre** para os relatórios e para o destino. O de-para (`etl_id_map`) ganha **uma linha por registro migrado** — na ordem de **780 mil linhas**, das quais 642.447 são de `risk_entries` | `df -h` |
| 1.0f | **Uma sessão que sobreviva à queda do SSH** (`tmux`/`screen`/`nohup`). A carga de `risk_entries` é o passo longo da janela (**Passo 7b**): perder o terminal no meio dela é perder a janela | `tmux new -s cutover` |

⚠ **`bin/rails` e `bundle exec rake` são a mesma coisa aqui, e os dois pagam ~2 s de boot.**
Nos comandos abaixo está `bin/rails`; se o `bin/` do repositório não estiver no `PATH` do
servidor, `bundle exec rake <mesmo alvo>` serve.

⚠ **Cuidado com o `DATABASE_URL`.** Todo comando deste runbook escreve no banco apontado por
ele. Confira **antes de cada passo que escreve** com
`bin/rails runner 'puts ActiveRecord::Base.connection_db_config.database'` — o nome do banco
impresso é o que vai ser modificado.

### 1.1 Os do usuário e do time

Os quatro primeiros **dependem do usuário** e estão fora deste repositório.

| # | Pré-requisito | Estado | Por que bloqueia |
| - | ------------- | ------ | ---------------- |
| 1.1 | **Acesso de leitura ao banco de produção do legado** | ✅ **RESOLVIDO — mas o formato mudou de significado com a DEC-124.** Para o **ensaio** existe `sfg-31-may-25.sql` (133,4 MB, `pg_dump` 13.4, 56 tabelas com dados, faixa 27/02/2022–31/05/2025), restaurado no banco isolado `sfg_legacy_dump` e destruído ao fim. Para o **cutover** o que vale é `SFG_LEGACY_URL` apontando para o banco **vivo, no próprio servidor** — o dump **não sai de lá** | Sem isto a introspecção não roda contra dado real, e o único dump no repositório (`../sfg/db/seed_assets/sfg_legacy_full.sql`) é do **sistema Django anterior** (`SG20210329`, 89 tabelas, 48.744 linhas) e **não tem tabelas `risk_*`** |
| 1.2 | **`public/system/` do servidor legado** | ✅ **RESOLVIDO em 26/08/2026 (DEC-84 destravada).** No **ensaio** é o `sfg-31-may-25.tar`, 42,3 MB, **467 arquivos** (655 entradas contando diretórios), reconciliado sem extrair nada (`SYSTEM_TAR=…`). No **cutover** não há tar: o diretório está no servidor, e o parâmetro é **`SYSTEM_ROOT=<deploy>/public/system`** | São os 11 anexos, entre eles o **anexo de renegociação, que é documento financeiro**. Registro apontando para arquivo inexistente é pior que ausência declarada |
| 1.3 | **As 4 consultas de produção** da seção 5 de `perguntas-rodada-1.md` | ✅ **RESPONDIDAS em 26/08/2026** (8 consultas, 2 delas impossíveis como escritas porque a coluna não existe) | Resultado: limites pré-2022 = **todos os 600**, sem coluna de tipo (P-018, DEC-43); `resource_kinds` = **0 linhas e 0 de 28.131 borderôs** → 10 IDs `dropped` (DEC-82); **`username` = 0 de 135** → **DEIXA DE SER BLOQUEADOR DE CUTOVER** (P-049/DEC-45); `is_phone_checked` existe (DEC-74). ⚠ **Um bloqueador NOVO nasceu aqui e é decisão do usuário**: 24 migrations do repositório nunca rodaram em produção — 7 famílias de recurso sem comportamento validado a replicar (`analise-dump-producao.md`, seções 1 e 7) |
| 1.4 | **Storage de produção: `Disk` com volume persistente AFIRMADO** | ✅ **DECIDIDO pelo usuário (DEC-129.1)** — `Disk` fica, e o **deploy garante um volume que sobrevive**. O ETL deixou de recusar `Disk` cegamente e passou a exigir **afirmação com autor**: `ACTIVE_STORAGE_DISK_VOLUME_IS_PERSISTENT=1` **+** `ACTIVE_STORAGE_DISK_VOLUME_CONFIRMED_BY="quem conferiu"`. Sem as duas, ele continua abortando. **Volume medido para dimensionar**: 42,3 MB de binário no total, dos quais **39.424.330 B (37,6 MB) são os 44 anexos de renegociação**, que são documento financeiro; o resto são 138 avatares (3,2 MB) e 3 logos de tema (3,5 KB). Maior arquivo: **5.072.833 B**. ⚠ **A conferência do volume é o passo 1.4.1, logo abaixo, e acontece ANTES da carga** | `Disk` **sem volume** é o defeito do legado (OPS-616): grava no disco do container e **sem volume persistente o anexo desaparece no primeiro redeploy, em silêncio**. Com 37,6 MB de documento financeiro em jogo, o primeiro redeploy apaga o acervo inteiro. A afirmação **não elimina o risco** — ela dá **autor** a quem conferiu que o risco não se aplica aqui |
| 1.5 | **Backup RESTAURADO em ambiente separado** — não só criado | responsabilidade do time | Backup não restaurado é backup não testado. **Sem isto não há go** (tarefa 9.2) |
| 1.6 | **Credenciais comprometidas rotacionadas** | ação do usuário, fora deste repositório | Senha da conexão `sfg_legacy` e a de `database.linux.yml:8,25`, ambas em texto puro no legado. Mais o token da ReceitaWS versionado em `config/application.arch.yml:12` (DEC-46) |
| 1.7 | `backend/db/etl/legacy_schema.yml` gerado da versão de produção do legado | `rake sfg_etl:baseline SFG_LEGACY_ROOT=../sfg` | É o esperado contra o qual a introspecção compara |

### 1.4.1 Conferir o volume do storage — ANTES da carga, e de novo depois de um redeploy (DEC-129.1)

**Este passo existe porque o modo de falha é diferido.** Um volume que não é volume não dá
erro nenhum no dia da virada: a carga passa, a reconciliação fecha, alguém assina — e o
acervo some no primeiro deploy que troque o diretório, semanas depois, com o registro no
banco ainda apontando para um blob que não existe. Não há alarme para isso. A única
proteção é conferir enquanto ainda dá para escolher outra coisa.

O ETL **não confia**: ele aceita `Disk` só quando alguém afirma, com nome, que o volume é
persistente. Os três passos abaixo são o que essa assinatura significa.

**a) O caminho é um ponto de montagem, e não um diretório dentro do release**

```bash
# no SERVIDOR (DEC-124: nada disto roda na bancada de ninguém)
echo "$ACTIVE_STORAGE_DISK_ROOT"                 # esperado: FORA da árvore do app, ex. /var/lib/sfg9/storage
findmnt --target "$ACTIVE_STORAGE_DISK_ROOT"     # tem de LISTAR um ponto de montagem
df -h "$ACTIVE_STORAGE_DISK_ROOT"                # e ter espaço: o acervo são 42,3 MB, mas ele cresce
touch "$ACTIVE_STORAGE_DISK_ROOT/.sfg9-volume-probe" && echo "gravável ok"
```

`findmnt` sem saída significa que o caminho é **um diretório comum dentro do release** — e aí
`Disk` é exatamente o defeito que o legado tinha (OPS-616). **Pare aqui** e resolva o deploy,
ou aponte `ACTIVE_STORAGE_SERVICE` para `amazon`/`s3_compatible`, que já existem em
`config/storage.yml`.

**b) Ele SOBREVIVE a um redeploy — provado, não presumido**

O arquivo-sonda de (a) é o teste. Faça um redeploy (o mesmo comando que será usado depois da
virada) e confira que ele continua lá:

```bash
# depois do redeploy, no servidor:
ls -l "$ACTIVE_STORAGE_DISK_ROOT/.sfg9-volume-probe"   # tem de EXISTIR, com a data de antes
```

Sumiu = o volume não é persistente, e **o pré-requisito 1.4 volta a bloquear**. É melhor
descobrir isso com um arquivo de zero byte do que com 44 documentos financeiros.

**c) Só então, a afirmação — com autor**

```bash
export ACTIVE_STORAGE_DISK_VOLUME_IS_PERSISTENT=1
export ACTIVE_STORAGE_DISK_VOLUME_CONFIRMED_BY="Nome de quem conferiu"
```

Sem `ACTIVE_STORAGE_DISK_VOLUME_CONFIRMED_BY` o portão **continua bloqueando**, e diz por quê:
afirmação anônima some no histórico do deploy e não responde *"quem disse que isso estava
certo?"* seis meses depois. As duas variáveis vão para a seção **Storage de destino** do
relatório de `rake sfg_etl:relink_attachments`, que é a peça que se anexa e se assina.

Limpe a sonda ao fim: `rm -f "$ACTIVE_STORAGE_DISK_ROOT/.sfg9-volume-probe"`.

### O acervo, reconciliado contra o banco (medido em 26/08/2026)

`rake sfg_etl:attachments SOURCE=dump DUMP=… SYSTEM_TAR=…` — o tar é **indexado e lido em
fluxo**, nada é extraído para o disco.

| Anexo | Pasta Paperclip | No banco | No acervo | Sem arquivo | Tamanho divergente | Bytes |
| ----- | --------------- | -------: | --------: | ----------: | -----------------: | ----: |
| `livetat_auth_users.avatar` | `avatars/:id/` | 135 | 135 | 0 | 0 | 2.809.638 |
| `projects.avatar` | `avatars/:id/` | **3** | 3 | 0 | 0 | 342.414 |
| `renegotiation_attachments.file` | `files/:id/` | 44 | 44 | 0 | 0 | **39.424.330** |
| `app_themes.symbol_logo` / `full_logo` / `text_logo` | `symbol_logos/`, `full_logos/`, `text_logos/` | 1 cada | 1 cada | 0 | 0 | 3.520 |
| `carriers.logo`, `providers.logo`, `app_themes.login_bkg_image`, `pictures.image` | — | **0** | — | — | — | 0 |

**Arquivos no acervo sem linha no banco: 0.** Derivados (`_thumb`, `_preview`, `_medium`,
`_large`) não migram — o ai9 gera variante sob demanda (motor de S13). Só o `_original` viaja.

Quatro coisas medidas aqui que mudam o passo 6, e nenhuma delas aparece numa contagem simples:

1. **`User#avatar` e `Project#avatar` dividem `public/system/avatars/:id/`.** O `:attachment`
   do Paperclip é o nome do anexo pluralizado e **não inclui o model**: o usuário 62 e o
   projeto 62 gravam na mesma pasta. O ETL casa por **basename**, nunca por pasta.
2. **121 dos 135 avatares de usuário são o placeholder `missing.jpg`** (7.327 B). Só 14
   pessoas têm foto de verdade.
3. **`renegotiation_attachments#45` (`ANEXO_INSTRUMENTO_DE_GARANTIA.pdf`) tem 0 byte** — no
   banco e no disco. Reconciliação de contagem e de tamanho passa; o documento não existe.
   É documento financeiro e precisa de decisão antes do cutover (**D-133**).
4. **O maior anexo tem 5.072.833 B e o teto de `config/attachments.yml` é 5.242.880 B.**
   Passa por 170 KB. Baixar o teto quebra a carga.

---

## 2. Procedimento obrigatório de `db:migrate` (tarefa 1.1)

Vale para qualquer migration desta migração, na janela ou fora dela. **Já custou +485
linhas reintroduzidas.**

1. `git status --porcelain backend/db/schema.rb` — parta de um `schema.rb` limpo ou saiba
   exatamente o que já está sujo (e de quem é).
2. `cp backend/db/schema.rb /tmp/schema.before.rb`
3. `bin/rails db:migrate`
4. **Compare estruturalmente, não por número de linhas** — a inserção alfabética de uma
   tabela desloca o arquivo inteiro e o diff textual é ilegível:
   compare o conjunto de `create_table` e o **corpo** de cada tabela comum entre o antes e
   o depois. Tabela sumida ou corpo alterado = pare.

   ⚠ **Não use `diff` no PowerShell, e não confie em "saiu vazio".** Este passo não trazia
   comando escrito, e comando não escrito, numa janela de cutover, vira o `diff` que a
   pessoa tem à mão. No PowerShell — o shell padrão desta máquina — `diff` **é apelido de
   `Compare-Object`**, e isso reprova de três formas, todas **medidas em 26/08/2026**:

   | O que se espera | O que o PowerShell faz | Medido |
   | --- | --- | --- |
   | `diff a.rb b.rb` compara o **conteúdo** | compara as duas **strings de caminho** | devolveu os nomes dos arquivos como "diferença", sem abrir nenhum dos dois |
   | diferença ⇒ status de falha | `$?` é `True` **sempre** | `True` com diferença E sem diferença — não há código != 0 para um script travar |
   | compara linha a linha, na ordem | compara **conjuntos**, sem ordem | duas listas de `create_table` só reordenadas: **"nenhuma diferença"** — falso verde |

   **O que usar.** Em `bash` (Git Bash ou WSL) `diff` e `cmp` se comportam: saída 1 quando
   diferem, 0 quando são iguais — conferido nos dois nesta mesma data. O portão de um passo,
   que serve para script e para gente:

   ```sh
   # iguais → imprime OK e sai 0; diferentes → imprime e sai != 0
   cmp -s /tmp/schema.before.rb backend/db/schema.rb \
     && echo "OK: schema.rb intacto" \
     || { echo "PARE: o schema.rb MUDOU"; diff -u /tmp/schema.before.rb backend/db/schema.rb; exit 1; }
   ```

   Se só houver PowerShell: `fc.exe a b` (devolve `$LASTEXITCODE` 1 quando diferem — medido)
   ou `(Get-FileHash a).Hash -eq (Get-FileHash b).Hash`. **Nunca `diff`.** E a comparação
   por `cmp`/hash responde "mudou ou não"; a comparação **estrutural** do parágrafo acima
   continua sendo a que responde "mudou o quê" — as duas, nesta ordem.
5. `rake sfg_etl:schema_gate` — nenhuma tabela nova no `schema.rb` sem migration que a crie.
   ⏱ Ele leva **~67 s** (medido): reexecuta as migrations do destino, e o tempo **não**
   depende do volume de dado. Conte 1 minuto fixo por execução ao cronometrar a janela.

**Fechamento da migração (Phase 5, não a janela):** `rake sfg_etl:ledger_gate` faz a
terceira metade da conferência final — o **razão**. `schema_gate` responde por esquema,
a seção "Tabelas com dado e SEM dono declarado" da introspecção responde por dado, e
este responde por **ID de inventário**: nenhum `to-remove`, nenhum `build?` sem resolução
escrita, nenhum item aberto sem dono, nenhum `dropped` sem evidência, nenhum status fora
da legenda. Ele **não marca nada** — lê, conta e reprova.

**Recriar tabela por migration APAGA em silêncio as colunas que migrations POSTERIORES
acrescentaram** (aconteceu em 25/08/2026 e a S13 perdeu `job_state`/`job_progress`). Depois
de recriar qualquer tabela: extraia todo `add_column :tabela, :coluna` das migrations e
confira contra `ActiveRecord::Base.connection.columns(tabela)`.

**`TRUNCATE … CASCADE` é proibido.** Ele não para na tabela nomeada: segue as FKs.
`TRUNCATE projects CASCADE` levou `users` junto e **apagou as contas de login**. Use
`DELETE FROM` na ordem inversa das dependências — é o que `rake sfg_etl:rehearsal_reset` faz.

`ar_internal_metadata` é a guarda de ambiente de `db:drop`/`db:schema:load` (tarefa 1.4 /
DB-738). **Não é migrada do legado** — ela é do ambiente de destino, e é ela que impede um
`db:drop` de rodar contra produção por engano.

---

## 3. Sequência da janela

### Passo 1 — congelar a origem
Legado em modo leitura. Anotar o horário. **Jobs pendentes no legado não são importados**
(tarefa 9.8 / DB-460, DB-597): o que estiver em voo é reexecutado no ai9 ou descartado, por
decisão registrada. Anotar quantos havia.

### Passo 2 — backup e restauração de prova
Backup do destino **e** restauração dele num ambiente separado (§1.5). Anexar a evidência.

### Passo 3 — baseline do esquema esperado
```
cd backend && bin/rails sfg_etl:baseline SFG_LEGACY_ROOT=/caminho/absoluto/para/o/legado
```
Confere: número de migrations reexecutadas (**138** = 104 do app + 34 das engines) e número
de tabelas derivadas (**67**).

⚠ **`SFG_LEGACY_ROOT=../sfg` NÃO funciona, e estava escrito assim aqui até o ensaio de
26/08/2026.** O comando roda com `cwd = backend/`, então `../sfg` resolve para
`ai9/sfg` — que não existe. O legado é **irmão** do repositório ai9, o que daqui é
`../../sfg`. Falha limpa (`repositório do legado não encontrado: ../sfg`, `rc=1`), mas
falha — e é o **terceiro** comando da janela. **Use caminho absoluto**: ele não depende de
onde o operador está. O próprio `legacy_schema.yml` versionado registra
`legacy_root: "/home/vinao/workspace/sfg"`, prova de que quem o gerou já tinha corrigido o
caminho na mão sem corrigir o runbook.

⚠ **E no servidor esse caminho é OUTRO** (DEC-124). Lá o legado não é o clone de trabalho
de ninguém: é o **diretório de deploy da aplicação em produção** — o mesmo que serve o
sistema hoje. Descubra-o antes da janela (§1.0c) e escreva o caminho absoluto no plano da
janela; não deixe para resolver no terceiro comando, com a origem já congelada.

O baseline **só lê arquivo de migration** — não toca no banco do legado e não precisa de
credencial. É o único passo do runbook de que isso vale.

### Passo 4 — **PORTÃO 1: introspecção sem desconhecidos** (tarefa 9.3)
```
bin/rails sfg_etl:introspect SOURCE=db SFG_LEGACY_URL=…
```
⚠ **`SOURCE=db` é o modo de PRODUÇÃO** (DEC-124). `SOURCE=dump DUMP=…` é ensaio, e a única
diferença de comportamento é de onde as linhas vêm — os portões, os relatórios e os abortos
são os mesmos. Se alguém rodar `SOURCE=dump` na janela, estará conferindo o retrato de
31/05/2025 e assinando como se fosse o dado de hoje. O cabeçalho de todo relatório imprime
a origem em uso; **é a primeira linha a conferir antes de assinar qualquer um deles.**
Produz `tmp/etl/introspect-latest.md` com três seções: esquema real da origem (DB-073),
**volumetria por tabela** (DB-074 — é a linha de base da reconciliação) e a comparação.

- **Vermelho**: qualquer tabela ou coluna desconhecida. A tarefa aborta antes de qualquer
  escrita. Cada surpresa precisa de uma de duas decisões, registrada: mapear (vira
  conversor) ou descartar (vira linha em `removed-features.md`, com evidência).
- As duas divergências toleradas **não** abortam: `availability_templates.default_position`
  (D-06/D-126) e `contracts.description` (D-108). **Uma terceira aborta.**
  ⚠ **Medido em 26/08/2026: nenhuma das duas existe no dump de produção.**
  `default_position` aparece zero vez no arquivo inteiro; `contracts` tem 7 colunas e o
  `description` do contrato é `has_rich_text` (ActionText, 2 linhas em
  `action_text_rich_texts`) — **o D-108 muda de veredito e deixa de ser "schema fora do
  versionamento"**. A allowlist fica porque descreve o que é tolerado, não o que existe.
- **Cobertura**: a seção "Tabelas com dado e SEM dono declarado" lista tabela da origem com
  linhas que nenhum conversor reivindica e nenhum `do_not_migrate` explica. Em 26/08/2026
  eram **6**: `trackings` (6.076), `livetat_auth_abilities` (2.224),
  `livetat_feedback_states` (8), `livetat_feedback_contexts` (4),
  `livetat_auth_client_applications` (3) e `app_themes` (1). **Cada uma precisa de dono ou
  de descarte com motivo antes da janela.**
- **Anexar o relatório.**

**Resultado da execução de 26/08/2026 contra o dump de produção:** 56 tabelas, **782.742
linhas**, **0 surpresas**, 30 colunas/tabelas declaradas por migration e ausentes na origem
(são as **24 migrations que nunca rodaram** — `analise-dump-producao.md` §1).

### Passo 5 — **PORTÃO 2: dry-run com tudo zerado ou decidido** (tarefa 9.4)
```
bin/rails sfg_etl:dry_run SOURCE=db SFG_LEGACY_URL=…
```
Não escreve nada. Produz uma seção por tabela com contagem **e amostra de ids**:

- **órfãos** por coluna (o legado tem `belongs_to_required_by_default = false`: **todas** as
  associações são opcionais, então a contagem pode ser grande);
- **duplicatas** contra as unicidades compostas que o legado só validava em aplicação — o
  índice único correspondente fica **BLOQUEADO** até resolver;
- **booleanos fora de {0,1}**, **enums fora do de-para**, **timestamps ambíguos**,
  **truncamentos**;
- **papéis suspeitos do Q-16** — os usuários cuja atribuição de 2021 veio de
  `is_staff ? MANAGER : is_superuser ? ADMIN : COLAB` (`../sfg/app/models/legacy/u.rb:33`,
  **equipe tem precedência sobre superusuário**), com o par `(is_staff, is_superuser)` da
  origem. **DEC-16: não reprocessar.** Esta lista é **revisão humana** e a assinatura dela
  é parte do portão;
- **quem tem `username` e nenhum canal** (DEC-45) — ✅ **medido no dump de 26/08/2026: 0 de 135
  usuários.** O relatório continua imprimindo a contagem (o dado do cutover pode ser mais novo
  que o dump de 31/05/2025), mas **deixou de ser bloqueador**. Se voltar a ser maior que zero,
  a lista se **resolve** (cadastrar e-mail ou telefone), não se autoriza;
- **contas DESLIGADAS** que nascem com `blocked_at` (DEC-39) e **quem vem com
  `is_phone_checked = 1`** (DEC-74).

  ⚠ **`is_active` NÃO é o flag de bloqueio do legado — `deactivated` é**, e isso foi medido
  no dump: `deactivated` é o **único `boolean`** do schema do legado e é o que
  `sessions_decorator.rb:12` e `pub_application_controller.rb:45` leem. Cruzamento em
  produção: **50** contas ativas de verdade (`is_active=1, deactivated=f`), **72**
  (`is_active=1, deactivated=t`) e **13** (`is_active=0, deactivated=t`). Bloquear só por
  `is_active` deixaria **72 contas hoje impedidas de entrar no legado** entrarem no ai9. O
  conversor bloqueia pela **união** (85), e o motivo gravado em `blocked_reason` diz qual
  coluna desligou cada conta.

**Resultado da execução de 26/08/2026 contra o dump** (23 conversores rodáveis, **772.234
linhas lidas**, nenhuma escrita) — cada linha abaixo **aborta** e precisa de decisão ou de
correção na origem:

| Anomalia | Quantidade | Nota |
| -------- | ---------: | ---- |
| `memberships.role` fora do de-para | **669 de 1.134** | "Gerente" 655 e "Colaborador" 14 — valores que o **próprio model do legado nunca declarou** (`membership.rb:18-21` só tem Responsável/Participante/Coordenador/Gestor). Foram escritos pelo ETL de 2021 a partir de `is_staff ? MANAGER : is_superuser ? ADMIN : COLAB` (`legacy/membership.rb:17`) — é o **Q-16 sobrevivendo em produção**. O `CHECK` do ai9 recusa os dois. **Decisão pendente** |
| `carriers.bank_code` duplicado | **229 de 328** | `8888`×181, `999`×31, `9999`×13, `888`×4, mais **83 nulos**. Índice único em `bank_code` é impossível |
| `livetat_auth_users.username` duplicado | **72 de 135** | todos com string **vazia**, não nula. Índice único exige normalizar `''` → `NULL` |
| `livetat_auth_users.default_project_id` órfão | **7** | todos apontando para `projects#0` — o default do legado não era FK |
| `renegotiations` `(project_id, integration_key)` duplicado | **9 grupos** | o maior com 41 linhas (`project 20`, chave "Renegociação") |
| `risk_controls` com os 4 pares (limite, taxa) zerados | **38 de 600** | o limite não autoriza nada |
| `renegotiations.attachments_count` nulo | **134 de 169** | DB-195 |
| `receivable_entries` com autor/empresa forçados pelo ETL de 2021 ou atribuídos em bloco | **35.813 linhas de relatório** | Q-B19 + DB-154, conversor da S6. Não é anomalia nova: é o rastro do importador Django |
| Contas desligadas no legado que nascem com `blocked_at` | **85 de 135** | DEC-39 aplicada a `deactivated`, e não a `is_active` (que pegaria só 13) |
| `action_text_rich_texts` com dono ainda fora do de-para | **512** | é o esperado sem carga: os donos (`indicators`, `help_items`, `contracts`) entram antes na ordem |
| `availability_templates` `(project_id, parent_template_id, title)` duplicado | **2** | ambos com `title` vazio |
| `risk_entries` | **642.447 linhas, 0 anomalias** | a maior tabela do sistema passa limpa |

**Contagem maior que zero sem decisão registrada ABORTA.** Autorizar é acrescentar a chave
que o relatório imprime em `backend/db/etl/decisions.yml`, com decisão, efeito, assinatura e
data. **Anexar o relatório e a lista do Q-16 revisada.**

### Passo 6 — anexos (tarefa 9.6) — **DESTRAVADO em 26/08/2026**

Duas etapas, e a primeira **não escreve nada**:

```
# 6a. reconciliar banco × acervo (roda antes da carga, e de novo depois)
bin/rails sfg_etl:attachments SOURCE=db SYSTEM_ROOT=/caminho/do/deploy/public/system

# 6b. copiar o binário e REANEXAR por ActiveStorage — só depois do passo 7
bin/rails sfg_etl:relink_attachments SOURCE=db \
          SYSTEM_ROOT=/caminho/do/deploy/public/system RELINK=1
```

⚠ **No servidor é `SYSTEM_ROOT`, não `SYSTEM_TAR`** (DEC-124). O acervo **é** o
`public/system/` do deploy em produção — o diretório está ali, ao lado do banco. Empacotar
um tar para depois lê-lo em fluxo seria duplicar 42,3 MB no disco do servidor sem ganhar
nada. `SYSTEM_TAR=/caminho/acervo.tar` continua existindo e é o que o **ensaio** usa nesta
bancada, onde só o tar chegou: ele é indexado por `tar -tvf` e lido por `tar -xOf`, um
arquivo por vez, direto para a memória — nada é extraído para o disco.

⚠ **`SYSTEM_ROOT` aponta para `public/system`, e o ETL só LÊ dali.** Passar o diretório
errado não corrompe nada: o relatório sai com "sem arquivo" para tudo, que é falha alta e
visível. O modo de falha ruim é o oposto — apontar para uma cópia velha e reconciliar
contra o acervo errado. Confira `ls <SYSTEM_ROOT>` e a data de modificação antes.

**A ordem importa:** `relink_attachments` resolve o registro de destino **exclusivamente
pelo de-para** (`etl_id_map`). Rodado antes do passo 7 ele reporta "sem registro de destino"
para tudo e não anexa nada — o que é o comportamento certo, não um erro.

**Cada religação é PROVADA**, não presumida: o binário é baixado de volta do ActiveStorage e
conferido por **tamanho e SHA-256** contra o que saiu do acervo. Divergência levanta, e num
anexo `critical` (renegociação) a seção sai como **aborto**. Prova executada em 26/08/2026
com um PDF real de produção: `renegotiation_attachments#9` `Simulação.pdf`, **983.078 B**,
sha256 `126956878458bcf03c75af3bce7c15cb6cd8671a183b61de2e375515a2b70ee2`, idêntico ao de
`tar -xOf … | sha256sum` (spec `production_dump_spec.rb`, exemplo `acervo de produção`).

As 4 colunas Paperclip por anexo não são recriadas: o arquivo é copiado e **reanexado** por
ActiveStorage.

**Se o acervo não estiver disponível na janela**, o relatório sai com a seção "SEM ACERVO
NESTA EXECUÇÃO" e o passo fica **BLOQUEADO POR DEPENDÊNCIA EXTERNA — nunca concluído**, com
a declaração explícita de que **só os registros migram**.

### Passo 6c — **storage de destino conferido** (tarefa 9.7 / Q-07 / F-13)

O `relink_attachments` **confere sozinho**, e em produção ele **aborta** se o
ActiveStorage estiver apontado para um serviço `Disk`. Não é aviso: é seção
`X Storage de destino — Q-07 (F-13)` no relatório, e a tarefa sai com código diferente
de zero antes de copiar um único byte.

Por que o portão existe: a decisão *"`Disk` não serve para o cutover"* estava escrita em
três lugares e **conferida em nenhum**. São **37,6 MB de documento financeiro** (os 44
anexos de renegociação), e o modo de falha é silencioso e diferido — a carga passa, o
portão 3 fecha, alguém assina, e o acervo some no primeiro redeploy que troque o
diretório, com o registro no banco ainda apontando para um blob inexistente.

**Como passar:** apontar `ACTIVE_STORAGE_SERVICE` para `amazon` ou `s3_compatible`
(os dois alvos já existem em `config/storage.yml`) e preencher as ENV. Escolher o
provedor continua sendo do usuário (**DEC-76**) — o ETL não escolhe, só cobra.

**Desvio consciente:** `ALLOW_DISK_STORAGE=1` grava assim mesmo, e a autorização fica
**escrita no relatório** que vai para a assinatura. Quem assinar está assinando isto.

Fora de produção o portão não bloqueia (o ensaio precisa rodar, e dev é `Disk` por
definição), mas **o serviço em uso vai para o cabeçalho de todo relatório** — "em que
storage isto rodou?" é pergunta de um segundo.

### Passo 6d — **seeds de REFERÊNCIA no destino** (achado do ensaio de 26/08/2026)
```
cd backend && bin/rails reference:seed
```
⚠ **Sem este passo a carga MORRE no primeiro conversor**, e esta linha existe porque o
ensaio bateu nela: contra um destino recém-criado (`db:schema:load`, sem seed), o
`sfg_etl:load` levanta

```
ActiveRecord::RecordNotFound: Couldn't find UserType with [WHERE "user_types"."name" = $1]
    app/services/legacy/role_map.rb:67 → converters/users.rb:189
```

O conversor de usuários traduz o papel do legado para um `UserType` do ai9, e `UserType`
é **catálogo de referência**, não dado migrado: ele vem de `reference:seed`, que é
idempotente e feito para rodar no deploy. O runbook nunca mencionou o comando — nem aqui,
nem na §2 do `db:migrate` — e a falha aconteceria **com a origem já congelada**, dentro
da janela.

Ele é idempotente: rodar de novo não duplica nem desfaz alteração feita pela tela.

### Passo 7 — carga
```
bin/rails sfg_etl:load SOURCE=db SFG_LEGACY_URL=… RUN_ID=cutover BATCH=1000
```
Por tabela, em lotes, na ordem de `backend/db/etl/load_order.yml`. Transação por lote com o
checkpoint **dentro** dela. Se o processo morrer: `bin/rails sfg_etl:status RUN_ID=cutover`
diz onde parou e **o mesmo comando retoma** — não recomeça e não duplica.

⚠ **Rode dentro de `tmux`/`screen`** (§1.0f). Este é o passo longo, e ele é longo por causa
de **uma** tabela — ver **Passo 7b**, que é onde a janela se decide.

---

### Passo 7b — dimensionar e retomar `risk_entries`: 642.447 linhas, 82% do total

**A distribuição é o problema, não o total.** As 782.742 linhas da origem não estão
espalhadas: **82% delas estão numa tabela só**, e ela é **11× maior que a segunda**.

| Tabela | Linhas | Fração do total |
| ------ | -----: | --------------: |
| **`risk_entries`** | **642.447** | **82,1%** |
| `receivable_taxes` | 58.473 | 7,5% |
| `receivable_entries` | 28.131 | 3,6% |
| `availability_entries` | 23.674 | 3,0% |
| todas as outras 52 juntas | 30.017 | 3,8% |

Consequência prática: **cronometrar a janela pelo número de tabelas dá errado.** 53 das 56
tabelas terminam em minutos; o relógio da janela é o relógio de `risk_entries`.

#### Como dimensionar, com números medidos

O que **não** serve: os tempos da §6.2. Aquilo é fixture (40 linhas), mede a *mecânica* do
runbook e é dominado pelos ~2 s de boot do Rails.

O que serve é a **taxa por linha**, medida com carga de verdade. Contra
`sfg_legacy_dump` nesta bancada, `SOURCE=db BATCH=1000`, destino Postgres local:

| O que foi medido | Valor |
| ---------------- | ----- |
| Origem | `SOURCE=db` contra `sfg_legacy_dump` (o dump de 31/05/2025 restaurado) |
| Lote | `BATCH=1000` |
| **Taxa observada** | **≈ 170 a 250 linhas/s** (quatro amostras de 12 a 43 s, tiradas do `processed_count` do checkpoint durante a carga) |
| **Extrapolação para as 642.447** | **≈ 45 min a 1 h** só desta tabela |
| Quanto entrou antes de a carga ser interrompida | **123.000 linhas** (a carga foi morta de propósito, para conferir o próximo item) |
| **Consistência depois da morte do processo** | **exata**: checkpoint em `running` com `lidas 123.000` e `última pk 123120`, e `SELECT count(*) FROM risk_entries` = **123.000**. Sem meia linha, sem lote pela metade |

⚠ **A faixa é larga porque a bancada estava DISPUTADA** — duas suítes `rspec` e uma
segunda carga de ETL de outro trabalho rodando ao mesmo tempo. É a medição honesta que
existe, e ela serve para uma coisa só: dizer que **`risk_entries` é assunto de dezenas de
minutos, não de minutos**. Quem for cronometrar a janela de verdade **mede no servidor**,
com a máquina quieta, pelo procedimento abaixo.

**Como usar no servidor.** A taxa acima é **desta bancada**; o servidor é outra máquina e
pode ser mais lento (disco compartilhado, banco com carga) ou mais rápido. Não extrapole:
**meça lá, uma vez, antes da janela.** Cinco minutos de medição, com o comando abaixo, valem
mais que qualquer estimativa:

```
# amostra de dimensionamento: carrega 20.000 linhas e mede. RUN_ID próprio,
# para não sujar o checkpoint do cutover.
time bin/rails sfg_etl:load SOURCE=db SFG_LEGACY_URL=… \
     ONLY=risk_entries RUN_ID=amostra BATCH=1000
# … deixe correr ~2 min, mate com Ctrl-C, e veja quantas entraram:
bin/rails sfg_etl:status RUN_ID=amostra
```

`642447 ÷ (linhas por segundo medidas)` é o tempo de `risk_entries`. Some 10–15 min para
todo o resto (as outras 55 tabelas, os dois passos de anexo e os três portões) e **dobre**:
janela sem folga é janela que vira rollback pelo critério 3 da §4.

#### `BATCH`: o que ele troca

`BATCH` é o tamanho da **transação**, e as três coisas que ele move andam juntas:

| `BATCH` | Memória por lote | Quanto se perde ao morrer | Quantos `COMMIT` |
| ------: | ---------------- | ------------------------- | ---------------: |
| 100 | mínima | até 99 linhas | 6.425 |
| **1000** (padrão) | ~1.000 linhas de `risk_entries` em Ruby | até 999 linhas | 643 |
| 5000 | ~5× | até 4.999 linhas | 129 |

**Recomendação: fique em 1000, e só desça se a memória do servidor apertar.** Subir para
5000 troca `COMMIT` por memória, e o gargalo desta tabela não é `COMMIT`: é a conversão em
Ruby (a `risk_entries` tem ~30 colunas monetárias e **6 totais derivados por linha**,
calculados na carga porque o motor grava sem callbacks).

⚠ **`BATCH` não muda o resultado, só o risco.** Qualquer valor produz o mesmo estado final —
é o `RESUME` que garante isso, não o lote.

#### Se a janela acabar no meio: como retomar

**Retomar é o mesmo comando.** Não há alvo de "continuar", e isso é de propósito:

```
# 1. onde parou (não escreve nada)
bin/rails sfg_etl:status RUN_ID=cutover

# 2. retomar — MESMO comando, MESMO RUN_ID
bin/rails sfg_etl:load SOURCE=db SFG_LEGACY_URL=… RUN_ID=cutover BATCH=1000
```

O `status` mostra, por tabela, `estado` (`running`/`done`), `lidas`, `gravadas` e a **última
pk** processada. `risk_entries` em `running` com `última pk = 431200` significa: o lote que
terminou em 431200 foi confirmado, e a retomada começa em 431201.

Três coisas que valem saber **antes** de precisar delas:

1. **O checkpoint está DENTRO da transação do lote.** Matar o processo no meio de um lote
   desfaz o lote **e** o avanço do checkpoint, juntos. Não existe estado "gravou mas não
   anotou" — foi ensaiado com `SIGKILL` sobre a fixture (§6.3) e **conferido de novo em
   27/08/2026 sobre `risk_entries` de verdade**: carga morta no meio, checkpoint em
   `running` com `lidas 123.000` e `última pk 123120`, e a tabela de destino com
   **exatamente 123.000** linhas. Os dois números batendo é o que se confere.
2. **`RUN_ID` é o que amarra a retomada.** Retomar com `RUN_ID` diferente **recomeça do
   zero** — e não duplica (o de-para protege), mas relê 642 mil linhas por nada. Escreva o
   `RUN_ID` da janela no plano e não o mude.
3. **`RESUME=0` NÃO é "recomeçar".** Ele ignora o checkpoint e **relê a origem inteira**,
   gravando zero porque o de-para já tem as linhas. É a **prova de idempotência**, não uma
   ferramenta de retomada — e numa tabela de 642 mil linhas ele custa uma releitura
   completa. Na janela, use-o só depois de a carga fechar, se for usar.

**E se a janela acabar de verdade** (não deu para terminar): a decisão é do critério 3 da
§4 — rollback. **Não** existe "deixar a carga pela metade e continuar amanhã": a origem
ficaria congelada de um dia para o outro, ou descongelaria e o retrato deixaria de bater. O
checkpoint existe para sobreviver a **queda de processo dentro da janela**, não para
atravessar janelas.

#### O que `risk_entries` já provou, e o que ainda não

✅ **Dry-run contra o dump: 642.447 linhas, ZERO anomalias.** A maior tabela do sistema passa
limpa — não há duplicata em `(date, risk_control_id, company_id)`, não há booleano fora de
{0,1} em `has_safegold_management`, não há órfão de `risk_control_id`.

⚠ **O que ela carrega é DEC-112**: `has_safegold_management` é **carimbo histórico** e vem da
origem, não do projeto de hoje. `Converters::Base#write!` liga `preserve_safegold_stamp`
para impedir o callback de recopiá-lo — sem essa linha, a carga sobrescreveria o carimbo de
**642.447 posições de risco** pelo valor de hoje, em silêncio e sem erro.

⚠ **E os 6 totais são DERIVADOS na carga**, pela mesma regra de
`RiskEntry#derive_scope_and_totals`. Eles estão em `derived`, fora da comparação literal da
reconciliação — o que a reconciliação confere neles é o **somatório por ano** (§Passo 8),
que é justamente o que pega erro de cast e de sinal.

### Passo 8 — **PORTÃO 3: reconciliação assinada por um humano** (tarefa 9.5)
```
bin/rails sfg_etl:reconcile SOURCE=db SFG_LEGACY_URL=…
```
Seis seções: contagem origem × destino (**toda diferença explicada**), amostra determinística
campo a campo, **somatórios financeiros por tabela e por ano**, referências religadas por FK,
conferência de fuso ano a ano de 2016 a 2026 e proveniência por `legacy_id`.

**O fuso já foi conferido contra o dump real (tarefa 7.5, 26/08/2026)** e a regra medida
bate com a implementada: janeiro de 2016 a 2019 volta como **UTC-2** e de 2020 em diante
como **UTC-3**, com a hora local reexibida idêntica à da origem nos 11 anos. Sobre instantes
**reais** da origem, só há 2022–2025 — é a faixa que o sistema Rails tem (o primeiro
registro é de 27/02/2022). Anos anteriores só existem em coluna `date`, sem hora.

⚠ **Achado na seção de somatórios:** três renegociações têm ano impossível em
`renegotiation_date` — `0020-08-21` (id 24), `0020-09-21` (id 54) e `0009-12-21` (id 47).
Elas aparecem como buckets "0009" e "0020" na tabela por ano. É digitação de `21` como ano
no formulário, e envenena qualquer cálculo de idade/atraso (**D-129**).

**Sem assinatura humana no relatório de reconciliação, não há cutover.**

### Passo 9 — virar o apontamento
DNS/proxy para o ai9. Login verificado **executando**, com uma conta de cada papel
(OG, Admin, Gerente, Colaborador) — não por teste automatizado.

⚠ **Medido no dump: não existe conta com papel global "Gerente" em produção.**
`livetat_auth_roles` tem 135 linhas e a distribuição é **OG 6, Admin 11, Colaborador 118,
Gerente 0**. A hierarquia do legado é a que o C3 já mapeia (OG 1111 > Admin 998 > Gerente 888
> Colaborador 799, **maior = mais poder**, o inverso do ai9). Para exercitar o papel Gerente
na janela é preciso **criar** uma conta de teste no ai9 — não há conta migrada para usar.

---

## 4. Rollback (tarefa 9.9)

**Critério objetivo que dispara a decisão** — qualquer um destes, sem discussão:

1. Portão 3 não fecha e a divergência é financeira (somatório por ano não bate).
2. Login falha para qualquer um dos quatro papéis depois do passo 9.
3. Janela estourada em mais de 50% do tempo previsto sem o passo 7 concluído.

**Procedimento:**
1. Reverter o apontamento (DNS/proxy) para o legado.
2. Tirar o legado do modo leitura.
3. Restaurar o backup do destino (§1.5) — nunca "limpar à mão".
4. `bin/rails sfg_etl:status` do `RUN_ID` da janela, **arquivado junto com os relatórios**:
   é ele que diz até onde a carga chegou.
5. Registrar o motivo em `.migration-ai9/checkpoint.md` antes de marcar nova janela.

Rollback **não** é `DELETE` nas tabelas carregadas. O de-para (`etl_id_map`) permite
identificar exatamente o que entrou, mas restaurar backup é a única operação com garantia.

---

## 5. Depois do cutover

- [ ] **Tirar os relatórios do servidor** — e **não** para o repositório (DEC-123). Eles
      trazem id, valor e contagem de dado real; `backend/tmp/` está no `.gitignore` e é
      assim que fica. Copie para onde a aprovação é arquivada, e apague do servidor depois.
- [ ] Arquivar os três relatórios assinados junto com o `status` final.
- [ ] Derrubar as tabelas de apoio do ETL (`etl_id_map`, `etl_checkpoints`) — são
      infraestrutura de migração, não domínio. **Só depois de arquivar o de-para**: ele é a
      única prova de qual registro do legado virou qual `uuid`. `legacy_id` continua nas
      tabelas de destino como proveniência (DEC-12/BE-451).
- [ ] Confirmar a premissa do DEC-12 (`Legacy::execute` não roda mais):
      `SELECT max(created_at) FROM <tabela> WHERE legacy_id IS NOT NULL` — máximo em 2021
      confirma.
- [ ] Registrar a **fronteira temporal do DEC-36**: as operações históricas vieram com
      `operation_value` calculado **sem as tarifas** (D-11), e as criadas no ai9 nascem
      **com** elas. Convivem dois regimes, por escolha consciente do usuário. Isso **não é
      bug** e não deve ser "corrigido" depois.

---

## 6. Ensaio do runbook (tarefa 9.10)

> ## ✅ ENSAIADO em 26/08/2026, por QA — que não escreveu este runbook
>
> Ponta a ponta contra a fixture versionada, **cronometrado**, em **banco próprio**
> (`sfg9_qa_s14`, criado com `db:schema:load` e apagado ao fim). O ensaio **achou dois
> defeitos que teriam parado a janela com a origem já congelada** — está tudo abaixo, com
> os tempos medidos.
>
> As três etapas que não escrevem (introspecção, dry-run e reconciliação) já haviam rodado
> **contra o dump de produção** pelo autor, e os números estão nos passos 4, 5 e 8. A
> **carga contra produção** continua adiada pela **DEC-102**.

### 6.1 Os dois defeitos que o ensaio achou

Os dois são do mesmo tipo — **o runbook descrevia um caminho que ninguém tinha percorrido
inteiro** — e os dois falham **depois** do Passo 1 (congelar a origem), que é o pior lugar
possível para descobrir.

**(1) `SFG_LEGACY_ROOT=../sfg` não resolve.** Terceiro comando da janela, `rc=1`. O legado é
irmão do repositório ai9; de `backend/` são dois níveis. Corrigido no Passo 3, para caminho
absoluto. Ironia útil: o `legacy_schema.yml` versionado registra
`legacy_root: "/home/vinao/workspace/sfg"` — quem gerou o baseline já tinha corrigido o
caminho na mão e não corrigiu o runbook.

**(2) O runbook nunca mandou semear os catálogos de referência — e sem isso a carga morre no
primeiro conversor.** Contra um destino recém-criado, `sfg_etl:load` levanta
`ActiveRecord::RecordNotFound: Couldn't find UserType` em `converters/users.rb:189`. É o
defeito mais grave dos dois: acontece **no Passo 7**, com a origem congelada, o backup
feito e os dois portões já assinados. Virou o **Passo 6d**.

Nenhum dos dois aparece em `rspec`, em `tsc` ou no `schema_gate`. É a diferença entre
"existe um runbook" e "o runbook funciona".

### 6.2 Tempos medidos (fixture: 10 tabelas, 40 linhas)

⚠ **Leia a coluna de tempo pelo que ela é.** Cada `bin/rails` paga **~1,9 s só de boot**, e
o trabalho de ETL sobre 40 linhas é sub-segundo. Isto **não** dimensiona a janela real —
mede a *mecânica* do runbook: quantos comandos, em que ordem, quais abortam. Para volume,
os números de produção já medidos são outros: **782.742 linhas** introspectadas e **772.234
lidas** no dry-run. O único passo cujo tempo **não** depende de volume, e por isso é
extrapolável, é o `schema_gate`.

⛔ **Não use esta tabela para dimensionar a janela.** Quem precisa disso está procurando a
**Passo 7b**, que mede `risk_entries` com carga de verdade. A diferença entre as duas não é de
grau: aqui são 40 linhas em 2 s; lá são 642.447 linhas em horas.

| # | Passo | Comando | Tempo | rc |
| - | ----- | ------- | ----: | -: |
| — | preparo | `db:schema:load` (destino novo) | **6,0 s** | 0 |
| 0 | limpar ensaio | `sfg_etl:rehearsal_reset` | **2,0 s** | 0 |
| 1 | baseline | `sfg_etl:baseline SFG_LEGACY_ROOT=../sfg` | **1,8 s** | **1 — DEFEITO (1)** |
| 1' | baseline | idem, caminho corrigido — 138/138 migrations, 67 tabelas | **1,9 s** | 0 |
| 2 | **Portão 1** | `sfg_etl:introspect SOURCE=fixture` | **1,9 s** | 0 |
| 3 | **Portão 2** | `sfg_etl:dry_run SOURCE=fixture` | **1,9 s** | 0 |
| 4 | ensaio do portão | `sfg_etl:dry_run … DECISIONS=none` | **1,9 s** | 1 — **aborta, correto** |
| 5 | ensaio do portão | `sfg_etl:load … DECISIONS=none` | **2,0 s** | 1 — **bloqueado antes da 1ª escrita** |
| 6 | carga | `sfg_etl:load RUN_ID=ensaio` (1ª tentativa) | **2,0 s** | **1 — DEFEITO (2)** |
| 6d | seed de referência | `reference:seed` | **3,0 s** | 0 |
| 6' | carga | `sfg_etl:load RUN_ID=ensaio` | **2,6 s** | 0 — **20 linhas gravadas** |
| 7 | idempotência | `sfg_etl:load RUN_ID=ensaio2 RESUME=0` | **2,3 s** | 0 — **0 gravadas, 20 já mapeadas** |
| 8 | **Portão 3** | `sfg_etl:reconcile SOURCE=fixture` | **2,3 s** | 0 — sem bloqueio |
| 9 | onde parou | `sfg_etl:status RUN_ID=ensaio` | **2,1 s** | 0 |
| 10 | portão de schema | `sfg_etl:schema_gate` | **67,3 s** | 0 |

**Caminho feliz, ponta a ponta: ~1 min 33 s**, dos quais **67 s são o `schema_gate`** —
sozinho, 72% do relógio. Ele reexecuta as migrations do destino para conferir que nenhuma
tabela do `schema.rb` nasceu sem migration, e **não** encolhe com dado menor. Quem
cronometrar a janela deve contar 1 minuto fixo por execução dele.

### 6.3 Os dois ensaios extras — os dois foram feitos

**Ensaio do portão (a decisão que falta).** `dry_run` e `load` com `DECISIONS=none`
abortaram os dois, `rc=1`. Medido no banco antes e depois do `load`: de-para **20 → 20**,
`users` **7 → 7**, e **zero** checkpoints criados para aquela execução. O bloqueio é
`Run#run_converter`, que levanta `Blocked` **depois do `Scan` e antes do `load_rows`** — a
diferença entre um banco limpo e um banco pela metade.

**Ensaio de queda.** `load BATCH=1` morto com `SIGKILL` (PID anotado, nunca por padrão
amplo) após 4 usuários gravados. Estado logo depois: `etl_id_map` com 4 linhas, checkpoint
em `running`, `last_legacy_pk = 4` — consistente no último lote completo. **A reexecução do
mesmo comando, com o mesmo `RUN_ID`, chegou ao mesmo estado final**: 7 usuários, 2
portadores, 2 segmentos, 2 projetos, 3 empresas, 4 memberships. `rc=0`, 2,6 s.

> ⚠ **Armadilha de conferência, achada aqui:** os `uuid` do destino **mudam a cada carga**
> (são gerados no ai9), então comparar o estado final por hash de `ai9_id` sempre acusa
> divergência. A comparação certa é por **contagem e por conteúdo**, e a proveniência é o
> `legacy_id` — nunca o uuid. Vale para o Portão 3 no dia da janela.

### 6.4 Ensaios dirigidos dos portões — o que abortou, e com que texto

| Cenário plantado | Comando | Resultado |
| ---------------- | ------- | --------- |
| Tabela desconhecida na origem (`tabela_que_ninguem_declarou`) | `sfg_etl:introspect` | `rc=1`, seção `X Surpresas na origem — 1`, com as duas saídas escritas (mapear ou descartar com evidência) |
| Coluna desconhecida em tabela conhecida (`segments.coluna_que_ninguem_declarou`) | `sfg_etl:introspect` | `rc=1`, mesma seção |
| Duas linhas com a mesma quádrupla `(project_id, company_id, availability_template_id, date)` | `sfg_etl:dry_run` | `rc=1` — *"o índice único fica BLOQUEADO até resolver"* |
| idem | `sfg_etl:load` | `rc=1`, e `availability_entries` ficou com **0 linhas** no destino |
| ActiveStorage em `Disk`, produção, `RELINK=1` | `sfg_etl:relink_attachments` | **aborta** — Passo 6c (tarefa 9.7). Coberto por `spec/lib/sfg/etl/storage_gate_spec.rb`, 6 exemplos |

E a contraprova de que os portões não são "aborta sempre": os mesmos comandos contra a
fixture versionada, sem nada plantado, saem **verdes** — e as duas divergências conhecidas
(`availability_templates.default_position`, `contracts.description`) ficam na seção
"Divergências CONHECIDAS (não abortam)".

### 6.5 A receita, para quem ensaiar da próxima vez

Runbook não ensaiado é rascunho. O ensaio roda contra a fixture versionada, **por alguém que
não o escreveu**, cronometrado:

```
cd backend
bin/rails sfg_etl:rehearsal_reset
bin/rails sfg_etl:introspect  SOURCE=fixture
bin/rails sfg_etl:dry_run     SOURCE=fixture
bin/rails sfg_etl:load        SOURCE=fixture RUN_ID=ensaio
bin/rails sfg_etl:load        SOURCE=fixture RUN_ID=ensaio2 RESUME=0   # nada deve duplicar
bin/rails sfg_etl:reconcile   SOURCE=fixture
bin/rails sfg_etl:status      RUN_ID=ensaio
```

Dois ensaios adicionais, e os dois têm de ser feitos:

- **Ensaio do portão** (a decisão que falta): `bin/rails sfg_etl:dry_run SOURCE=fixture
  DECISIONS=none`. Tem de **abortar**, e a carga com o mesmo parâmetro tem de ser
  **bloqueada antes da primeira escrita**.
- **Ensaio de queda**: matar a carga no meio e reexecutar. O banco fica consistente no
  último lote completo e a reexecução chega ao **mesmo estado final**.

### E contra o dump de produção, sem escrever nada — **isto é ENSAIO, não cutover**

⚠ **O bloco abaixo é o ENSAIO nesta bancada** (DEC-124). O cutover não roda `SOURCE=dump`:
roda `SOURCE=db` contra o banco vivo, **no servidor**. A diferença não é de comando — é de
**qual dado está sendo assinado**. O que sai daqui prova que o pipeline funciona contra o
retrato de 31/05/2025; não é conferência de virada.

Estes rodam hoje, com o dump e o acervo em disco, e **nenhum deles escreve**:

```
cd backend
bin/rails sfg_etl:baseline    SFG_LEGACY_ROOT=/caminho/absoluto/para/sfg
bin/rails sfg_etl:introspect  SOURCE=dump DUMP=/caminho/sfg-31-may-25.sql
bin/rails sfg_etl:dry_run     SOURCE=dump DUMP=/caminho/sfg-31-may-25.sql
bin/rails sfg_etl:attachments SOURCE=dump DUMP=/caminho/sfg-31-may-25.sql \
                              SYSTEM_TAR=/caminho/sfg-31-may-25.tar
bin/rails sfg_etl:reconcile   SOURCE=dump DUMP=/caminho/sfg-31-may-25.sql
```

**A tradução para o servidor, comando a comando** — é a única diferença entre ensaiar e
virar:

| Ensaio (aqui) | Cutover (no servidor) |
| --- | --- |
| `SOURCE=dump DUMP=/caminho/sfg-31-may-25.sql` | `SOURCE=db SFG_LEGACY_URL=postgres://…` |
| `SYSTEM_TAR=/caminho/sfg-31-may-25.tar` | `SYSTEM_ROOT=<deploy>/public/system` |
| `SFG_LEGACY_ROOT=/home/vinao/workspace/sfg` | `SFG_LEGACY_ROOT=<diretório de deploy do legado>` |
| relatórios em `backend/tmp/etl/` desta máquina | relatórios em `backend/tmp/etl/` **do servidor** — copiar para a aprovação, **nunca para o repositório** (DEC-123) |

⚠ **O ensaio local com `sfg_legacy_dump` também é `SOURCE=db`** (é um banco Postgres como
outro qualquer), e é assim que ele fica mais próximo do cutover: mesmo caminho de código,
mesma leitura em lote, mesmos tempos por linha. **É o modo de ensaio a preferir.** O que
distingue ensaio de cutover não é a flag: é **para qual banco `SFG_LEGACY_URL` aponta**.

O `SqlDump` lê o arquivo **em fluxo**: uma passada guarda esquema, deslocamento do bloco
`COPY` de cada tabela e a contagem; o dado é lido depois, tabela por tabela. **Não restaura
banco e não infla nada** — a instrução do usuário em 26/08/2026 foi textual sobre isso.

⚠ **`pg_dump` grava dado em dois formatos e o padrão dele é `COPY`, não `INSERT`.** Até
26/08/2026 o `SqlDump` só entendia `INSERT`, que é o formato do dump Django antigo. Contra o
dump de produção ele **devolvia zero linha em toda tabela, sem erro nenhum**: volumetria,
dry-run e reconciliação saíam verdes e vazios. Se um dia a volumetria vier zerada com o
arquivo obviamente cheio, é isto. `sfg_etl:introspect` imprime o formato detectado no
cabeçalho de todo relatório justamente para que a pergunta se responda em um segundo.
