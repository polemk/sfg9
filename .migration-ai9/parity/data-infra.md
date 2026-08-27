# Phase 4 — paridade do bloco `data-infra`

**Escopo:** `data-schema`, `ops-config`, `misc-domain`, `integrations`, `help-faq`, `jobs-cron`,
`themes` · transversais `DB-ETL-*`, `CFG-*`, `NAV-001` · `NEW-002` (dashboard) e `NEW-003` (PWA).
Mais as **37 linhas `pending` sem dono** que o `rake sfg_etl:ledger_gate` reprova (S14 10.7).

**Data:** 26/08/2026. **Regra desta passagem:** verificar **executando**. Nada aqui foi promovido
por leitura de código, de spec ou de nota de outra fase.

---

## 0. O que foi executado (é isto que sustenta cada linha abaixo)

| Execução | Resultado |
| --- | --- |
| `rake sfg_etl:ledger_gate` | **REPROVA**, saída **1** — 37 linhas abertas sem dono. Placar: `migrated` 1.173 · `dropped` 213 · `pending` 37 · `verified` 13 · `blocked` 3 |
| `rspec spec/lib/sfg/etl` (banco próprio) | **132 exemplos, 0 falhas**, 3 pendentes por falta de artefato |
| `rspec` os 3 pendentes **com `SFG_DUMP` e `SFG_SYSTEM_TAR` reais** | **32 exemplos, 0 falhas** — dump de 139.886.195 B e acervo de 44.318.720 B |
| `rspec spec/lib/sfg/etl/storage_gate_spec.rb --format doc` | **6 exemplos, 0 falhas** — o portão de `Disk` (OPS-616) |
| **Suíte do backend inteira, em banco próprio e sem agente concorrente** | `models` **390/0** · `lib` **346/0** (4 pend.) · `services` **678/0** · `jobs` **145/0** (1 pend.) · `config` **26/0** · `requests` **1.116/0** — **2.701 exemplos, 0 falhas** |
| `rspec spec/jobs spec/services/help spec/requests/api/v1/help_spec.rb` | **135 exemplos, 0 falhas** |
| `npx vitest run` (suíte inteira do front) | **55 arquivos, 491 testes, 0 falhas**, saída 0 |
| `npx vite build` | saída **0**, 1 min 12 s |
| `rake reference:seed` | 12 catálogos, e **idempotente** na segunda execução |
| ETL: `introspect` → `dry_run` → `load` → `load` → `load RESUME=0` → `reconcile` | ver §4 |
| `browser.js` — `/dashboard` 1440×900 claro e escuro, e 390×844 | ver §5 |
| `curl` — manifest, 3 ícones, apple-touch, favicon, `robots.txt` | ver §5 |

---

## 1. As 37 linhas `pending` — veredito de cada uma

> **Por que elas existem.** O agente da S14 construiu o portão, viu as 37 e **não as marcou de
> propósito**, porque várias têm irmãs idênticas já `migrated` — o que faz "esqueceram de marcar"
> parecer a resposta. Ele estava certo em não marcar em bloco: **uma delas não é omissão de
> marcação, é `dropped`, e a nota da própria S14 aponta para a família de irmãs ERRADA.**

### 1.1 O caso que desmente a leitura fácil — `BE-399`

A tarefa 10.7 registra: *"`BE-399` (despacho de temas — os 14 irmãos `BE-395`..`BE-409` estão
`migrated` pela S2/2.8)"*. **A família está trocada.** `BE-395`..`BE-409` é o despacho do
**console** (S2). O `BE-399` é o despacho de **`themes`**, e a família dele é
`BE-370`..`BE-379`, `BE-384`, `DB-388`, `DB-548`, `FE-385`..`FE-387`, `OPS-389`, `OPS-499`,
`OPS-543` — **todas `dropped`** pela DEC-55/DEC-56, cada uma com evidência escrita no razão.

**Medido executando** (`rails runner` contra o esquema do destino):

```
tabela app_themes existe?    false
tabela global_themes existe? false
tabela user_themes existe?   false
model AppTheme definido?     nao
model UserTheme definido?    nao
```

E `vitest src/__tests__/marca-fonte-unica.test.ts` tem o exemplo
*"DEC-55/DEC-56 — não existe área de tema para reconstruir › nenhuma rota, tela ou chamada de API
de CRUD de tema"*, que **passou**. Não há entidade, não há tela, não há rota.

**Veredito: `dropped`.** Marcá-lo `migrated` por analogia com os irmãos do console teria posto no
razão um recurso que não existe — exatamente a ficção que o portão foi feito para impedir.

### 1.2 As outras 36 — a leitura fácil está certa, mas só depois de conferida

Todas as 36 restantes têm **dono real e trabalho entregue**, em `S0-fundacao` (design system) e
nas fatias de marca/plataforma. O que faltava era a linha do razão, não o código. **Nenhuma foi
promovida por existir o arquivo:** o critério aplicado foi

- **`verified`** — rodei hoje uma prova que exercita **o comportamento daquele ID** e ela passou;
- **`migrated`** — a peça existe, está montada no produto e a suíte passa, mas **não há prova
  específica daquele ID**; a linha diz isso e nomeia o dono;
- **`dropped`** — medi a ausência.

| ID | Estado final | Como verifiquei (executando) |
| --- | --- | --- |
| **BE-399** | **dropped** | §1.1 — `app_themes`/`global_themes`/`user_themes` ausentes, `AppTheme`/`UserTheme` indefinidos, e o exemplo da DEC-55/56 passando |
| **BE-538** | migrated · S0 | `frontend/src/lib/utils/date.ts:100-141` traz as 4 sentinelas (`todayStart`, `todayEnd`, `dinosaurs`, `mars`) e é importado por **32** arquivos. `vitest` verde. **Não vira `verified`: `transversais.test.ts` cobre `FE-430`..`FE-442`, não as sentinelas.** O `todayEnd` diverge do legado **de propósito** (D-119: lá era `midnight + 23h59`, que engolia 23:59:00–23:59:59) |
| **FE-052** | migrated · S0 | `hooks/useDebouncedSearch.ts` existe e é importado por **17** telas. O debounce é exercitado de fato em `faqPage.test.tsx` ("faz DEBOUNCE da busca: digitar 5 letras não dispara 5 requisições"), que passou — mas por outra tela, então não conta como prova do ID |
| **FE-053** | **verified** | `components/ui/__tests__/Pagination.test.tsx` — **11 exemplos**, verdes hoje. `PaginationPill` importado por 24 arquivos |
| **FE-061** | **verified** | `DataTable.test.tsx` (7) + `dataTableArraste.test.tsx` (8) + `dataTableTransbordo.test.tsx` (11) — **26 exemplos**, verdes hoje |
| **FE-066** | **verified** | `MoneyInput.test.tsx` (12) + `NumericInput.test.tsx` (6) — **18 exemplos**, verdes hoje |
| **FE-079** | migrated · S0 | `components/ui/States.tsx` importado por **29** arquivos. Os estados são exercitados por `AsyncSection.test.tsx`, que é o `FE-401` — não há teste do `States` isolado |
| **FE-401** | **verified** | `AsyncSection.test.tsx` — **6 exemplos**, verdes hoje, incluindo o **estado de erro**, que é a lacuna do legado que este ID fechou (IMP-A63). Importado por 42 arquivos |
| **FE-410** | migrated · **COM DEFEITO** · S0/S1 | Ver §6, defeito **D-QA4-02**. O embrulho `lib/notify.ts` existe e está correto, mas é importado por **1** arquivo (`UiKitPage.tsx`, a vitrine). **70** arquivos chamam `sonner` direto, em **273** chamadas. As duas regras de comportamento que o port existe para preservar **não valem em lugar nenhum do produto** |
| **FE-411** | migrated · S1 | `components/ui/Button.tsx` importado por **107** arquivos |
| **FE-412** | migrated · S1 | mesma `Button.tsx`, com a prop de carregamento (IMP-A65); 5 testes a tocam indiretamente |
| **FE-413** | migrated · S1 | `lucide-react` no lugar do `app_arrow` de CSS puro. Reuso de biblioteca já presente |
| **FE-414** | migrated · S1 | `components/ui/DetailList.tsx` importado por **11** arquivos |
| **FE-415** | migrated · S1 | `components/ui/Card.tsx` importado por **23** arquivos |
| **FE-416** | migrated · S1 | `Table.tsx` (1 consumidor) + `DataTable.tsx` (19). A ordenação real está travada pelo `FE-061`, `verified` |
| **FE-417** | migrated · S1 | `components/ui/Select.tsx` importado por **33** arquivos; a `.glass-select` foi de fato removida do `globals.css` (comentário na linha 642 e o `ProjectSelector.tsx:25` registram a troca) |
| **FE-418** | migrated · S1 | `Checkbox.tsx` (7 consumidores) + `RadioGroup.tsx` (2) |
| **FE-419** | migrated · S1 | `components/ui/switch.tsx` importado por **14** arquivos |
| **FE-420** | migrated · S1 | `components/ui/SearchInput.tsx` importado por **20** arquivos |
| **FE-421** | migrated · S1 | `components/ui/Autocomplete.tsx` importado por **5** arquivos — **uma** implementação, como o mapa exigia |
| **FE-422** | migrated · S1 | `components/ui/ResultItem.tsx` importado por **2** arquivos |
| **FE-423** | migrated · S1 | `components/ui/tabs.tsx` importado por **6** arquivos |
| **FE-424** | migrated · S1 | mesma `tabs.tsx` (`TabsContent`) |
| **FE-425** | migrated · S1 | `components/ui/Badge.tsx` importado por **43** arquivos, com a variante removível que o `Autocomplete` consome |
| **FE-426** | migrated · S1 | `components/ui/Tooltip.tsx` importado por **28** arquivos — o Tippy.js saiu |
| **FE-427** | **verified** | `UserAvatar.test.tsx` — **5 exemplos**, verdes hoje, travando a **cor determinística** por `colorKey` (o legado sorteava a cada render) |
| **FE-428** | migrated · S1 | `components/ui/Spinner.tsx` importado por **12** arquivos |
| **FE-429** | **dropped** | Medido: **zero** ocorrências de `Rating`, `PhotoSwipe`, `photoswipe` ou `rateit` em todo o `frontend/src`. O `generic_rating`, o override do PhotoSwipe e o `comp.scss` não têm consumidor — é a resolução que a própria tarefa 4.29 da S0 previa |
| **FE-538** | migrated · S0 | O kit inteiro do `ux_kit19` virou a biblioteca do ai9. A prova agregada é a suíte: **55 arquivos / 491 testes** verdes. Nada foi para `window` |
| **FE-740** | migrated · S1 | `components/PageHeader.tsx` importado por **45** arquivos, no lugar das 751 linhas de `toolbars.js`. **Não há teste próprio do `PageHeader`** — por isso não é `verified` |
| **FE-742** | migrated · S0 | `lib/utils/{date,address,number,text}.ts` + `lib/notify.ts` + `ProtectedRoute.tsx` (2 testes). Ver o defeito do `notify` em `FE-410` |
| **FE-743** | migrated · S1 | `components/ui/dialog.tsx` (Radix) importado por **6** arquivos; o `vendor/dialog` proprietário não veio |
| **FE-744** | migrated · S1 | `components/charts/RechartsPie.tsx` existe, ao lado de `RechartsBar`, `RechartsLine`, `SeriesLineChart`, `CategoryBarChart`, `ChartPanel`. **Registro que precisa sobreviver:** o legado **não instanciava** o `Doughnut` em nenhuma view — isto é o componente ficando disponível, não uma tela portada (`OPS-746`, `NEW-001`) |
| **FE-745** | migrated · S1 | `DatePicker.tsx` (19 consumidores) + `Calendar.tsx` (14). Exercitados em `alturaSobrescrivel.test.tsx` e `mobileLibrary.test.tsx`, verdes — mas por outro ângulo, então fica `migrated` |
| **OPS-390** | **verified** | `npx vite build` saída **0** em 1 min 12 s, produzindo os chunks de vendor (`react-vendor` 141,41 kB, `ui-vendor` 102,03 kB, `query-vendor` 42,52 kB, `router-vendor` 23,33 kB, `http-vendor` 36,28 kB) mais um chunk por rota — o equivalente aos 3 packs do Webpacker, com code-splitting que o legado não tinha. **Dois achados de peso vão em §6 (D-QA4-03)** |
| **OPS-544** | **verified** | `rake reference:seed` cria **2** contratos a partir do HTML versionado — Políticas de Privacidade (3.267 caracteres) e Termos de Uso (5.651) —, versão 1, e **na segunda execução não duplica** (`0 criados · 0 atualizados · 2 inalterados`). O aceite pendente aparece **na tela**: o banner "Você ainda não aceitou os documentos vigentes" foi capturado no `/dashboard` (§5). `user.html` continua sem consumidor — ver §6 |
| **OPS-635** | **verified** | `manifest.webmanifest` servido e válido; os **3** ícones existem em disco com mime `image/png` real e respondem **HTTP 200**; `apple-touch-icon` 180 e `favicon.ico` **200**; `theme-color` por esquema claro/escuro; `robots.txt` com `Disallow: /`. Tudo **sobrevive ao build de produção**, e o `index.html` do build mantém os dois `<link>` |

**Placar das 37: 2 `dropped` · 7 `verified` · 28 `migrated` com dono escrito.**
Nenhuma continua sem dono — que é o critério do portão.

---

## 2. O bloco (275 IDs nas 7 capabilities)

Estado inicial: **188 `migrated` · 84 `dropped` · 2 `pending` · 1 `blocked`**.
(As 2 `pending` são `OPS-544` e `OPS-635`, já resolvidas na §1; a `blocked` é `OPS-616`, §4.)

### 2.1 O que virou `verified`, e a prova de cada família

| Família | IDs | Prova executada |
| --- | --- | --- |
| **Central de ajuda e FAQ** | BE-350…BE-363, DB-367, DB-368, DB-369, DB-588, DB-589, DB-590 | `spec/requests/api/v1/help_spec.rb` + `spec/services/help/*` verdes; no front `faqPage.test.tsx` (5), `helpCenterPage.test.tsx` (5), `helpItemEditor.test.tsx` (4), `fieldHelp.test.tsx` (4) — **todos verdes hoje**, cobrindo debounce da busca, estado vazio, erro com "tentar de novo", edição inline que grava no `blur` e cancela no `Escape`, e "salvar NÃO manda `user_id`" |
| **Ajuda de campo (DEC-111)** | OPS-545 | Medido executando: `Help::FieldHelp.all` devolve **90** textos (receivables 64, risk_operations 13, structured_operations 13) e **`pending_keys` é `{}`**. Os 3 textos que a DEC-111 mandou escrever estão lá; `receivables.resource_kind_id` **não existe no YAML**, como ela mandou (a entidade caiu na DEC-110) |
| **Marca e tema claro/escuro** | BE-380, BE-381, BE-382, BE-383 | `marca-fonte-unica.test.ts` — **26 exemplos verdes**: nenhuma cor em hex/rgb/hsl fora de comentário, nenhuma classe de paleta literal do Tailwind, nenhuma variante `dark:` consertando cor, os 15 arquivos de logo existem e não estão vazios, e nenhuma tela referencia o arquivo do logo direto. Confirmado **renderizando** em claro e escuro (§5) |
| **PWA e indexação** | OPS-635 (§1), NEW-003 | §5 |
| **Dashboard** | NEW-002 | §5 |
| **Motor de ETL** | ver §4 | §4 |

### 2.2 O que continua `migrated`, e por quê — sem repetir justificativa velha

**A premissa mudou durante esta passagem** e isso vale ser dito: o razão e o checkpoint diziam que
a paridade numérica esperava "a data da carga". **Não existe essa data** — a carga real só ocorre
se o cliente comprar, e o dump restaurado (`sfg_legacy_dump`, 56 tabelas, **782.742 linhas**) é o
dado real disponível. Toda linha que dizia "espera a carga" foi reexaminada contra ele (§4).

O que sobra em `migrated` sobra por **falta de prova específica do ID**, não por falta de dado:

- **Os 10 mailers `BE-480`…`BE-489`** (capability `integrations`) estão no razão com a coluna
  `Test` = `—`. **Dez IDs sem teste nomeado** é a maior lacuna de prova do bloco. Ver §6.
- **`DB-585`, `DB-586`, `DB-587`** (indicadores) trazem `db/schema.rb` na coluna `Test`.
  **`schema.rb` não é teste** — é o arquivo que descreve a tabela. Ver §6.
- Os componentes de biblioteca sem teste próprio, listados um a um na §1.2.

---

## 3. Transversais

| ID | Estado | Como verifiquei |
| --- | --- | --- |
| **DB-ETL-01…06** | ver §4 | Não são linhas do razão — são requisitos de spec, cumpridos pelos IDs `BE-451`, `DB-073`, `DB-074`, `DB-482`, `DB-598` e pelo motor. **`DB-ETL-05` diverge de propósito**: `legacy_password` **não** é preservada (DEC-14 — o produto não tem senha), e a divergência está registrada no `improvements-log.md` para não ser lida como item faltando |
| **CFG-01 / CFG-02** | migrated | `CFG-02` (catálogo de limites de anexo) é consumido por `OPS-491`, `OPS-497`, `DB-571` e `DB-593`; `spec/models/attachable_spec.rb` verde na rodada de `spec/models` (390/0). O limite vem de configuração explícita, nunca de introspecção de método |
| **NAV-001** | migrated | `hooks/__tests__/useNavItems.test.ts` — **19 exemplos verdes** hoje |
| **NEW-002** | new · **conferido renderizando** | §5 |
| **NEW-003** | new · **conferido executando** | §5. Continua `new` e **não** vira `verified`: a DEC-103a é aceite do usuário, não veredito de Phase 4 |

---

## 4. O ETL

*(preenchido em §4.2 depois do ensaio contra o dump real)*

### 4.1 O que dá para afirmar sem a carga real — e foi provado com a fixture

Ensaio em banco próprio (`sfg9_qadatainfra_test`), `BATCH=50`:

| Critério | Prova |
| --- | --- |
| **O dry-run roda e não escreve** | `rake sfg_etl:dry_run` saída **0**, relatório com resumo por conversor, "Sem bloqueio" |
| **Em lotes, com transação por lote** | `BATCH=50` respeitado; checkpoint gravado **dentro** da transação do lote |
| **Idempotente pelo checkpoint** | 2ª carga com o mesmo `RUN_ID`: saída 0, **de-para continua com 20 linhas** |
| **Idempotente pelo DE-PARA, não pelo checkpoint** | 3ª carga com **`RESUME=0`** (relê a origem inteira): saída 0, de-para **continua 20**, e os checkpoints mostram `lidas=4 gravadas=2 jamap=2` — leu tudo de novo, **gravou zero**, reconheceu os já mapeados. É a prova que a tarefa pedia |
| **Retomável** | `sfg_etl:status` mostra estado, lidas, gravadas, já mapeadas e **última pk** por tabela |
| **A reconciliação existe e fecha** | `rake sfg_etl:reconcile` saída **0**: contagem origem × destino, amostra determinística campo a campo, somatórios financeiros por ano, referências religadas por FK, conferência de fuso 2016–2026 e proveniência por `legacy_id` |
| **Recusa `Disk` em vez de confiar (OPS-616)** | `storage_gate_spec.rb --format doc`, **6 exemplos, 0 falhas**: *ABORTA quando é para gravar, em produção, com Disk* · *NÃO aborta no ensaio* · *NÃO aborta fora de produção* · *com `ALLOW_DISK_STORAGE=1` grava e a autorização fica ESCRITA no relatório* · *o serviço em uso vai para o cabeçalho de todo relatório* |

### 4.2 Contra o dump de produção restaurado — **e a premissa mudou no meio desta passagem**

O dump está restaurado em `sfg_legacy_dump` (**somente leitura**, dado real de cliente: nada aqui
traz nome, e-mail, documento ou valor identificável — só contagem e id do legado). Como **não
existe data futura de carga** — ela só acontece se o cliente comprar —, este é o dado real
disponível, e rodei o ensaio inteiro contra ele. Destino: banco próprio e descartável.

| Passo | Tempo | Saída | Resultado |
| --- | ---: | ---: | --- |
| `introspect` | 3,5 s | **0** | 56 tabelas, **782.742 linhas**, **0 surpresas** contra o baseline das migrations. "Sem bloqueio" |
| `dry_run` | 24,0 s | **1** | Aborta em **2** chaves sem decisão. Ver D-QA4-05 |
| `load` `BATCH=5000` | 6,3 s | **1** | **PARA no 3º grupo de tabelas** com exceção não tratada. Ver **D-QA4-04** |
| `load` de novo | 4,5 s | 1 | de-para **continua 503** — idempotente também em escala real, até onde chegou |
| `reconcile` | 65,6 s | 1 | Aborta na contagem origem × destino, **consequência** da carga interrompida |
| `relink_attachments` (ensaio, sem `RELINK=1`) | 3,7 s | 1 | **`livetat_auth_users.avatar` → User: 135 ok** contra o acervo real. `renegotiation_attachments`: **1 com 0 byte** (é o D-133 conhecido) e **43 sem religar** por falta do de-para dos donos. **44 = 43 + 1: o acervo tem todos**, e a DEC-84 cai como o coordenador disse |

**Volumetria real, para dimensionar lote e janela** (medida, não citada):

| tabela | linhas |
| --- | ---: |
| `risk_entries` | **642.447** |
| `receivable_taxes` | 58.473 |
| `receivable_entries` | 28.131 |
| `availability_entries` | 23.674 |
| `indicator_entries` | 6.174 |
| `trackings` | 6.076 |
| `renegotiation_installments` | 5.124 |
| **total** | **782.742** |

⚠ **Uma correção de número que importa para dimensionar:** `risk_entries` é **11,0×** a segunda
maior, não 22×. A segunda maior é `receivable_taxes` (58.473), não `receivable_entries` (28.131) —
contra esta última é que dá 22,8×. `risk_entries` sozinha é **82%** de todo o volume.

**O que o ensaio real DESMENTIU do material que eu recebi** — e é por isso que se re-verifica:

1. *"A ordem de carga precisa pôr `contracts` antes do texto rico."* **Já está.**
   `db/etl/load_order.yml` traz `Contracts` → `ContractDeals` → `Help*` → `ActionTextRichTexts`
   **por último**, com o comentário explicando por quê ("o religamento é polimórfico e sai do
   de-para"). Reordenar não era o conserto — ver D-QA4-06, que é o conserto de verdade.
2. *"`risk_entries` é 22× a segunda maior."* São 11,0× — ver acima.

---

## 5. Tela

Ferramenta: `.migration-ai9/tools/browser.js`, com **login de verdade**.

| Tela | Papel | Viewport | Resultado |
| --- | --- | --- | --- |
| `/` (pública) | none | 1440×900 | Login renderiza: "Acessar o painel", abas E-MAIL/WHATSAPP, OAuth Google/Facebook, e as seções de marca |
| `/dashboard` | gerente | 1440×900 **claro e escuro** | **NEW-002 renderiza com número real do seed**: TOTAL OPERADO R$ 43.201.301,30 · EXPOSIÇÃO R$ 35.291,19 · LIMITES NO TETO 0 · RENEGOCIAÇÕES EM ATRASO 2; série mensal, exposição por portador, consumo de limite por tipo, limites prestes a estourar e a tabela de renegociações vencidas. Escuro conferido na captura, sem cor fora do token |
| `/dashboard` | gerente | **390×844** | Cartões empilham, gráficos redimensionam, barra de abas inferior aparece. **Dois achados de layout em §6 (D-QA4-07 c e d)** |
| `/help/items` | og | 1440×900 **claro e escuro** | **Central de ajuda renderiza** com a árvore do seed: grupos ("Primeiros passos", "Operação"), categorias ("Dúvidas frequentes", "Acesso e conta", "Borderôs") com contagem por categoria, botão Criar, e o painel da direita explicando o que fazer sem categoria escolhida |

`NEW-003` / `OPS-635`, medidos por `curl` contra o servidor e contra o build de produção:

```
manifest.webmanifest  200 · JSON válido · display standalone · start_url "/" · lang pt-BR
safegold-icon-192.png             200 ·  3.555 B · image/png
safegold-icon-512.png             200 · 16.516 B · image/png
safegold-icon-maskable-512.png    200 ·  6.864 B · image/png · purpose maskable
safegold-icon-apple-touch-180.png 200
favicon.ico                       200
robots.txt                        200 · "Disallow: /"
CSP do index.html                 contém `manifest-src 'self'` — o manifest não é bloqueado
```

**O que continua sem prova, e é honesto dizer:** as duas instalações que só o aparelho prova
(botão "Instalar" no Chrome/Edge e "Adicionar à Tela de Início" no Safari do iPhone). Continuam
desmarcadas de propósito.

---

## 6. Defeitos e achados

Sete achados, todos **medidos executando**. Nenhum foi consertado aqui: QA registra, a fatia dona
conserta com teste — é o mesmo tratamento que os resíduos `R-01`..`R-03` receberam.

### D-QA4-01 — a trava de força bruta acusa **login bem-sucedido** como falha, e reescreve a trilha
**Dono: S1 (auth). Gravidade: alta — é trilha de segurança sendo alterada.**

`Auth::MagicLoginService` grava a tentativa **pessimista** (`create_login_attempt(success: false)`,
`magic_login_service.rb:57`) e, quando o código sai, vira o registro com
`update_last_attempt(success: true)` (`:73`). O `update_last_attempt` (`:152-160`) faz

```ruby
LoginAttempt.where(identifier:, method:, ip_address:).last
```

e a **PK de `login_attempts` é `uuid`**. Rails ordena `.last` por `id ASC`; num UUID v4 isso é
**ordem aleatória**, não cronológica — medido: `ORDER BY "login_attempts"."id" ASC`, e
`implicit_order_column` é `nil`.

**Medido em 200 ensaios de 3 tentativas: `.last` devolveu a errada 145 vezes — 72,5%**
(o acaso puro daria ~66,7%). Duas consequências, as duas observadas no banco de dev:

1. **A linha `false` de um login que DEU CERTO fica `false` para sempre.** Elas se acumulam, e
   `LoginAttempt.suspicious_activity?` conta `failed`: **5 identificadores distintos do mesmo IP em
   15 min travam o IP inteiro**. Não é "vários agentes atrapalhando" — são **logins normais**
   disparando a trava. Atrás de um NAT, cinco pessoas entrando com sucesso trancam a sexta.
2. **Uma tentativa realmente FALHA pode ser reescrita como `success: true`.** Nos registros de
   19:37:23 há dois `true` sem nenhum `false` criado no mesmo instante, enquanto os `false` de
   19:34:00 e 19:36:59 seguem sem par. A tabela que o próprio código chama de *"a mesma evidência
   que um incidente vai [querer]"* (`security_helpers.rb:39`) está sendo corrompida.

**O conserto é de uma linha** — `self.implicit_order_column = :created_at` no `LoginAttempt`, ou
`.order(:created_at).last` — mas a decisão e o teste são da S1.

**Isto reclassifica uma pendência.** O checkpoint pede ao usuário uma *"regra de permissão para
`rails runner`, se quiser que agente possa limpar `login_attempts`"*. **A limpeza não é o conserto,
é o curativo.** O item do usuário some quando este defeito for corrigido.

### D-QA4-02 — `FE-410`: o embrulho de toast existe, está certo, e **o produto não o usa**
**Dono: S0/S1. Gravidade: média — comportamento declarado que não vale em lugar nenhum.**

`frontend/src/lib/notify.ts` é o port do `M.push` do legado, com o de-para documentado e **duas
regras de comportamento** deliberadas: `info` fica até o usuário fechar (`duration: Infinity` +
`closeButton` — *"texto de ajuda que evapora em 3s não é ajuda"*) e `error` dura mais que `success`
(8000 ms contra 3000 ms).

**Medido:** `@/lib/notify` é importado por **1** arquivo — `app/pages/UiKitPage.tsx`, a vitrine do
design system. **70** arquivos importam `toast` de `sonner` **direto**, em **273 chamadas**
(151 `toast.error`, 110 `toast.success`, 9 `toast.info`, 3 `toast.warning`), das quais **1** passa
`duration`. E o `<Toaster>` do `App.tsx:24` **não define `duration`** — vale o padrão do `sonner`.

Resultado: as duas regras estão mortas. Erro e sucesso duram igual, e a orientação (`info`) some
sozinha. O arquivo passa em type-check, passa na suíte e não tem consumidor — é exatamente o
"parece certo lendo" que este phase existe para pegar.

### D-QA4-03 — o pacote de produção carrega **i18n que ninguém chama**
**Dono: S0/S18 (`ops-config`). Gravidade: baixa, mas é peso morto em toda visita.**

`vite build` gera `i18n-vendor` com **44,66 kB** (14,39 kB gzip). **Re-medido hoje na fonte, não
citado do mapa:** `useTranslation` é chamado por **zero** arquivos de `frontend/src`, e o
`LanguageSwitcher` **não é montado em lugar nenhum** — e mesmo assim `main.tsx:7` faz
`import './lib/i18n'`. É o **DC-17** confirmado, agora com o custo em kB.

Junto, do mesmo build: `index-*.js` sai com **868,57 kB** (235,96 kB gzip), acima do teto de aviso
de 500 kB, e `CategoryBarChart` (Recharts) com **350,88 kB**. Não é defeito de paridade; é o número
que alguém vai querer antes da demo.

### D-QA4-04 — **`sfg_etl:load` morre na 3ª tabela contra o dado real, com stack trace**
**Dono: S4 (`Project`) + S14 (ETL). Gravidade: ALTA — é bloqueador de cutover.**

```
rake aborted!
ActiveRecord::RecordInvalid: Registro inválido:
  Slug aceita apenas minúsculas, números, hífen e sublinhado
  → converters/base.rb:232 `write!` → converters/projects.rb
```

`Converters::Projects` grava `slug: Values.to_smart_id(row['smart_id'])`, e `to_smart_id`
(`values.rb:130-135`) só faz `strip`. O destino valida
`format: /\A[a-z0-9][a-z0-9\-_]*\z/` (`project.rb:74-76`), e o `normalize_slug` (`:228`) só faz
`strip.downcase`. Como o conversor **preenche** `slug`, o `derive_slug` (`:214`) sai na primeira
linha e nunca entra em ação.

**Medido na origem, sem expor valor:** dos **83** projetos de produção, **2** têm `smart_id` que a
validação recusa — legado **id=33** (11 caracteres, um deles fora de `[A-Za-z0-9_. -]`) e legado
**id=74** (8 caracteres, contém ponto). Zero nulos, zero vazios, zero maiúsculas, zero espaços.

**O dano não são os 2 projetos: é tudo depois deles.** A carga morre ali e **nenhuma** tabela
posterior roda — companies, memberships, recebíveis, risco, renegociações, disponibilidades,
indicadores. Chegou a **503** linhas de de-para de 782.742 do dump.

**E o dry-run NÃO prevê isto.** O dry-run existe para o operador descobrir a anomalia **antes** da
janela; ele listou 12 chaves e nenhuma sobre `slug`. Um dry-run limpo seguido de uma carga que
estoura é o pior arranjo possível para uma sexta-feira. É irmão dos quatro índices únicos que já
viraram parciais — a diferença é que **este não aparece no ensaio**.

### D-QA4-05 — `dry_run` real: 2 chaves sem decisão, e uma delas está **mal diagnosticada**
**Dono: S14.** Aborta em `renegotiation_attachments` (extração de binário) e em
`action_text:owner_not_loaded`. A segunda merece cuidado — ver D-QA4-06.

### D-QA4-06 — **14 conversores nunca escritos, com um recado que envelheceu**
**Dono: S14 + as fatias nomeadas. Gravidade: ALTA — 1.803 linhas de dado real sem como viajar.**

O ETL pula 14 tabelas dizendo, por escrito, *"conversor ainda não escrito — **o model chega na
S4 / S7 / S8 / S11 / S12**"*. **Conferido executando: os 15 models citados JÁ EXISTEM, com model e
tabela — 15 de 15.** As fatias entregaram; o recado ficou.

Esta é a **oitava** ocorrência do padrão que dominou o dia 26/08 — justificativa escrita numa fase
e repetida depois como verdade — e é a mais cara delas, porque está no caminho do cutover.

**Separando o que é lacuna do que é correto** (medido tabela a tabela na origem):

| Tabela sem conversor | Linhas na origem | Veredito |
| --- | ---: | --- |
| `project_to_carrier_connections` | **1.177** | **falta conversor** — S4 |
| `providers` | **289** | **falta conversor** — S4 |
| `contract_deals` | **272** | **falta conversor** — S11 |
| `help_items` | **25** | **falta conversor** — S12 |
| `sub_segments` | **20** | **falta conversor** — S4 |
| `help_categories` | **7** | **falta conversor** — S12 |
| `resource_sources` | **6** | **falta conversor** — S8 |
| `help_groups` | **5** | **falta conversor** — S12 |
| `contracts` | **2** | **falta conversor** — S11 |
| **soma** | **1.803** | |
| `charges`, `receipts`, `risk_operation_types`, `risk_operation_subtypes`, `risk_movement_types`, `risk_operations`, `risk_movements` | tabela **não existe** na origem | **pulo CORRETO** — são as famílias das 24 migrations que nunca rodaram em produção. Não mexer |
| `project_guarantee_types`, `project_guarantees`, `risk_operation_extensions`, `structured_operation_types`, `structured_operations`, `remunerations` | tabela **não existe** na origem | **pulo CORRETO**, mesma razão |

**E é isto que explica o abort do texto rico**, não a ordem de carga: `contracts` (2) e `help_items`
(25) não têm conversor, então **27** dos 512 corpos ficam órfãos. Composição medida na origem:
`Indicator` 485 · `HelpItem` 25 · `Contract` 2.

⚠ **Isto contradiz a DEC-119 §4, e a contradição é medida.** Ela diz: *"`action_text:owner_not_loaded`
— **512 textos**: é ordem de carga, não decisão. O texto rico existe antes de `contracts` entrar.
Corrige-se **carregando `contracts` antes** (fatia S12). Não há o que decidir."* **Três coisas estão
erradas aí**, e cada uma foi conferida na fonte:

1. **`contracts` já está antes.** `db/etl/load_order.yml` traz `Contracts` → `ContractDeals` →
   `Help*` → `ActionTextRichTexts` **por último**, com o comentário "POR ÚLTIMO, e não é detalhe de
   arrumação". Reordenar não conserta nada porque não há nada fora de ordem.
2. **`contracts` é da S11, não da S12.** O `load_order.yml` diz `owner_slice: S11`.
3. **Os órfãos reais são 27, não 512.** `Indicator` 485 · `HelpItem` 25 · `Contract` 2, medido na
   origem. Os 485 do `Indicator` têm conversor e dono; só os 27 não têm.

**E há o que decidir**, ao contrário do que a DEC afirma: os conversores de `contracts`,
`contract_deals` e dos três `help_*` **não existem** (D-QA4-06). Enquanto não existirem, nenhuma
reordenação faz os 27 corpos viajarem.

⚠ **Dois erros na própria mensagem do dry-run**, que são o que induziu o diagnóstico da DEC-119:

1. Ela diz *"carregue `contracts` antes (fatia S12)"* — mas `contracts` **já está antes** no
   `load_order.yml`, e é da **S11**, não da S12.
2. Ela acusa **512** órfãos quando os órfãos reais são **27**. O dry-run **nunca popula o de-para**,
   então no ensaio *todo* texto rico parece sem dono. O contador não distingue "vai ter dono" de
   "não vai ter dono nenhum" — e é justamente essa diferença que decide se alguém precisa agir.

### D-QA4-07 — achados menores, registrados para não virarem caça ao fantasma

| # | Achado | Medida | Dono |
| --- | --- | --- | --- |
| a | **10 mailers sem teste nomeado** — `BE-480`..`BE-489` estão no razão com `Test` = `—` | maior lacuna de prova do bloco | `integrations` |
| b | **`db/schema.rb` usado como "teste"** em `DB-585`, `DB-586`, `DB-587` | `schema.rb` descreve a tabela; não executa nada | `indicators` |
| c | **Barra de abas mobile quebra palavra**: "Painel de Disponibili-dade" hifenizado no meio | visto em 390×844, captura `dash-mobile.png` | S15 / DEC-100 |
| d | **Faixa de aceite de contrato cortada pelo cabeçalho** em 390×844 — a 1ª linha fica sob a barra fixa | mesma captura | S11 / DEC-100 |
| e | **"Limite utilizado" negativo** no painel de exposição por portador: dois portadores em −R$ 3,9 mil e −R$ 7,5 mil, eixo começando em −R$ 20 mil | pergunta, não acusação: "limite **utilizado**" negativo pode ser correto no domínio e errado no rótulo | S5 / S15 |
| f | **`db/seed_assets/contracts/user.html`**: 20 bytes, nenhum consumidor | o mapa já dizia "não é portado sem consumidor"; o arquivo ficou | S11 |
| g | **`rvm use 3.2.3` está obsoleto na bancada** | o `Gemfile` fixa `ruby '3.4.9'` e `.ruby-version` também; com 3.2.3 o `bundler` recusa (`Bundler::RubyVersionMismatch`) e **nada** roda. *Bati de frente nisto antes de ler a DEC-119, que já o registrou no mesmo dia — fica como confirmação independente, não como achado novo* | checkpoint |
| i | **`index.lock` órfão travou os commits de todos por 7 min** | 0 byte, 430 s de idade, **nenhum processo git vivo** (varredura por `/proc`). O `graphify` dispara "background rebuild" no commit; um hook que morre deixa o lock. Removido só depois de checar as quatro condições — nunca à mão sem checar, porque apagar um lock vivo aborta o commit alheio pela metade | bancada |
| j | **5 GB de Chromium parado na máquina — e NÃO é o `browser.js`** | Medido ao fim: **75 processos · 12 navegadores pai · 5.077 MB de RSS somado**, com idades de **20h33, 19h08, 18h39 e 14h36**. **Corrigi a minha própria atribuição:** escrevi primeiro que o `browser.js` vazava, fui ler, e ele **fecha certo** — `finally { await browser.close() }` (`browser.js:165-166`) envolve inclusive o `login()`, então até a falha da trava de força bruta fecha antes do `process.exit(1)`. As idades também não batem comigo: minha passagem foi 19:10–20:15, e nenhuma das antigas nasceu nela. O padrão bate com o **plano B do `cdp.js`**, em que o Chromium sobe solto (`--remote-debugging-port`) e o README manda *"ANOTE ESTE PID"* e matar por ele — quem esqueceu, deixou. **Não matei nenhum:** durante a medição apareceu um com 4 s de idade, que é captura VIVA de outro agente, e não há como separar. É o mesmo tipo de acúmulo que o `puma` de 24 GB do checkpoint — vale uma varredura com a bancada vazia | bancada / `cdp.js` |
| h | **O ETL não tem portão para a pré-condição de seed**: sem `reference:seed` o `load` morre em `RecordNotFound: Couldn't find UserType` | o runbook cobre no passo **6d**, e o passo está certo — mas quem pular o passo recebe stack trace, não "BLOQUEADO: rode `reference:seed`" | S14 |

### O `diff` deste shell — o aviso estava certo **e** estava generalizado demais

O checkpoint diz *"o `diff` deste shell MENTE… imprimiu 'Files are identical' para dois arquivos
com md5 diferente e nunca devolve código != 0"*. Fui medir antes de repetir:

| Onde | `diff` com arquivos DIFERENTES | com arquivos IGUAIS |
| --- | --- | --- |
| **bash** (Git Bash **e** WSL) | imprime o diff, **sai 1** | sem saída, **sai 0** — correto |
| **PowerShell** | `diff` é apelido de **`Compare-Object`** | — |

**Em bash o `diff` não mente** — conferido nos dois. **Em PowerShell ele nunca serve**, e por três
razões medidas: (a) com caminhos, compara as **strings de caminho**, não o conteúdo — devolveu os
nomes dos arquivos como "diferença"; (b) `$?` é `True` **sempre**, com e sem diferença — não há
código != 0 para gatilho de script; (c) compara **conjuntos**: duas listas de `create_table` só
reordenadas saíram como **"nenhuma diferença"**, que é o falso verde exato do aviso.

**O runbook já não mandava usar `diff`** — o passo 4 do §2 pedia comparação estrutural. O buraco
era outro e foi tapado: **o passo não trazia comando nenhum**, e comando não escrito, numa janela de
cutover, vira o `diff` que a pessoa tem à mão. O `docs/runbook-cutover.md` passa a trazer a tabela
acima, o portão de uma linha com `cmp` (`cmp -s … && echo OK || { …; exit 1; }`) e as alternativas
de PowerShell (`fc.exe`, `Get-FileHash`), com **"nunca `diff`"** escrito.

---

## 7. O que precisa do usuário

| # | O quê | Por quê |
| --- | --- | --- |
| 1 | **Provedor de storage (Q-07 / OPS-616)** | Continua `blocked`, e continua sendo decisão de infraestrutura do cliente (DEC-76). O portão está **provado funcionando**: em produção com `Disk` e `RELINK=1` ele **aborta**, e o desvio consciente (`ALLOW_DISK_STORAGE=1`) fica escrito no relatório assinado |
| 2 | **`renegotiation_attachments#45` com 0 byte** (D-133) | Reencontrado no ensaio contra o acervo real: dos 44 anexos, **43 religam e 1 tem 0 byte** — no banco e no disco. É documento financeiro; a decisão é do usuário |
| 3 | **Os 2 projetos com `slug` recusado** (D-QA4-04) | Trocar o `slug` muda a **URL** do projeto. Normalizar automático é decisão de produto, não de QA; precisa de chave em `db/etl/decisions.yml` com assinatura |
| 4 | ~~Regra de permissão para `rails runner` limpar `login_attempts`~~ | **Sai da lista.** Era curativo para o **D-QA4-01**; corrigido o defeito, a trava deixa de disparar em login normal |
| 5 | ~~Data da carga~~ | **Sai da lista.** Não existe data futura: a carga só ocorre se o cliente comprar, e o dump restaurado é o dado real. Toda linha que dizia "espera a carga" foi reexaminada contra ele (§4.2) |
| 6 | **Duas instalações de PWA** (Chrome/Edge e Safari iOS) | Só o aparelho prova. Continuam desmarcadas de propósito — DEC-103a já as tirou desta fatia |
