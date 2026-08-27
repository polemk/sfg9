# Tasks: S10 — Indicadores e séries mensais

Fila resumível do Phase 3. **Uma tarefa = um comportamento verificável.** Cada tarefa cita
os IDs que fecha, para o `parity-ledger.md`. Ordem: **dados → backend → frontend → testes →
paridade**, com as duas travas do `design.md` §8: **o soft delete vem antes de qualquer tela
de exclusão**, e **a caracterização `G1`…`G4` vem antes de qualquer refatoração** de
normalização ou de grade.

**Pré-requisito duro:** S0 (escopo por projeto, papéis) e S4 (`Project`). Não depende de
S5/S7/S8.

Verificação: `cd backend && bundle exec rspec` (comparar com a **lista** de falhas do
baseline) · `cd frontend && node node_modules/typescript/bin/tsc --noEmit` (baseline
**0 erro**) · `vitest` não roda neste ambiente.

Contratos: **C1** (escopo no endpoint; **catálogo global é sem escopo**), **C2** (serviço
único da grade), **C3** (hierarquia invertida, testar **os dois lados**). Convenções:
`ai9-conventions.md` §3.6, §4, §6.

**Fora de escopo por DEC-09 e pela nota da própria spec:** série histórica calculada,
variação (MoM/YoY/percentual), acumulado, média e **gráfico**. Gráfico é `NEW-001`, fatia
**S15**, e entra no ledger como `new` — **o QA não deve procurá-lo no legado**.

---

## Bloco 0 — Decisões que destravam trabalho (não produzem código)

- [x] 0.1 **RISCADA PELA DEC-89.** ~~Default: **spec** (título como digitado).~~ A **DEC-89** respondeu a pergunta antes desta fatia começar e escolheu a **opção (b): o título CONTINUA em CAIXA ALTA sem acento**, valendo o DEC-30. O que está implementado é a DEC, não o default desta tarefa. Golden test `G2` trava a transliteração e reprova quem "consertar". · Texto original: **T-D10 — Q-R25: o título continua em CAIXA ALTA sem acento?** Levar o conflito: o mapa manda replicar (`transliterate(...).upcase` em todo save) e a spec aprovada diz que o título aparece **como digitado**, com a comparação de unicidade ignorando acentos e caixa. Default: **spec**. Registrar que o dado **migrado** chega em caixa alta — os acentos originais já se perderam de forma irreversível, e "re-humanizar" seria adivinhação — fecha a dúvida de `BE-321`
- [x] 0.2 **T-D11 — Q-R27: a denormalização de `title`/`key`/`value_type` no lançamento é "foto do momento" ou bug?** Hoje o `update_all` **reescreve o histórico**: um lançamento de 2023 passa a mentir sobre como o indicador se chamava na época. Default: **replicar** o resultado, tirando o `update_all` de dentro do request — fecha a dúvida de `BE-322`
- [x] 0.3 **RISCADA PELA DEC-71.** ~~Default: **construir com confirmação e tela**.~~ A **DEC-71** escolheu a **opção (d): o endpoint é portado, SEM botão na tela**, como no legado. Implementado assim: `DELETE /api/v1/indicator_entries/:id` existe, com autorização e escopo (condição 1 do DEC-53), e **nenhuma tela o chama**. · Texto original: **T-D12 — Q-R29: excluir lançamento é feature viva ou resíduo?** Nenhuma tela do legado chama a rota; a grade só cria e atualiza, e zerar grava `0`. Default: **construir** com confirmação e autorização (a rota existe e o DEC-09 manda portar o que existe). Se o negócio disser que é resíduo, vira `dropped` com evidência — fecha a dúvida de `BE-328`
- [x] 0.4 **FECHADA PELA DEC-85** (mesma resposta do default): a chave fica **como está** — obrigatória, derivada do título, **sem unicidade** e sem mudança de formato. · **T-D13 — Q-R26: a "Chave de Integração" tem consumidor fora do repositório?** (BI, planilha, ETL). Dentro do repo, **nada** lê `indicator.key`. Enquanto não houver resposta, **não mexer**: não tornar única, não mudar formato, não remover — fecha a dúvida de `OPS-312`
- [x] 0.5 **FECHADA PELA DEC-70** (confirma o default): célula **vazia** para não lançado, `0` só para zero lançado. Exceção consciente ao DEC-30 pelo critério da própria decisão — a grade **não tem total**, então distinguir não muda soma nenhuma. · **Q-R34** Default: **sim**. É a leitura mais usada do módulo e hoje os dois aparecem como `0`. Confirmar a semântica com o negócio, porque **muda o que o usuário vê**
- [x] 0.6 **Q-R33 — dois itens de menu chamados "Indicadores"** (Cadastro = catálogo, Gestão = lançamentos). Default: "Indicadores" e "Lançamentos de indicadores"
- [x] 0.7 Transcrever para `.migration-ai9/upstream-flags.md`, se ainda não estiverem lá: **UF-1** (`RichTextInput` com `dangerouslySetInnerHTML` **sem sanitização** e sem DOMPurify — a Instrução é HTML de um usuário lido por todos os outros do projeto), **UF-2** (três implementações de rich text, duas stacks no `package.json`, zero consumidores) e **UF-3** (i18next só com pt-BR, com `LanguageSwitcher` visível)
- [x] 0.8 Registrar em `.migration-ai9/improvements-log.md`: a lista de indicadores globais **passa a paginar** (hoje trunca em 50 sem aviso nenhum) e a grade passa a distinguir vazio de zero

## Bloco 1 — Dados

- [x] 1.1 **[CORREÇÃO À TAREFA]** o mapeamento de `is_active` **não** é `≠ 0 → true`: medi as duas leituras do legado (`indicator.rb:83-85` e `indicator_entries_controller.rb:23`) e **as duas comparam com 1**. A regra do ETL é **`= 1 → true`, todo o resto `false`** (um `is_active = 2` conta como inativo no legado). Está escrita no cabeçalho da migration, que é onde o ETL a lê. · Migration `indicators` com índices em `project_id`, `title` e `key` (hoje **nenhum além da PK**), FK real para `projects`, `is_active` integer → boolean com mapeamento `≠ 0 → true` e a lista de exceções no dry-run, e a coluna **`discarded_at`** para o soft delete. **A `key` não é única hoje**: contar duplicatas antes de qualquer constraint (T-D13) — fecha `DB-310`
- [x] 1.2 Migration `indicator_entries` com **índice único composto obrigatório** em (`project_id`, `indicator_id`, `year`, `month`) — hoje a unicidade só existe na aplicação e **há corrida** — mais índice de leitura em (`project_id`, `year`, `month`, `indicator_id`) para a grade, CHECK de faixa em `month` (`1..12`), `value` aceitando **negativos**, e `created_by`/`updated_by`. É **a maior tabela da unidade** — fecha `DB-311`
- [x] 1.3 **[FRONTEIRA]** a tabela **já tinha sido criada pela S4** (`20260826100300_create_project_connections.rb:52`), que deixou escrito no comentário da coluna que a FK para `indicators` era desta fatia. A migration `20260826210100` **não recria a tabela** (recriar derruba em silêncio coluna que outra fatia acrescente): ela só acrescenta a **FK** e o `legacy_id`. Registrado em `upstream-flags.md` #S4-6. · Migration `project_indicator_connections` — join table pura, sem payload, índice **único** em (`project_id`, `indicator_id`) + FKs. **Não criar** a coluna `is_active` que o permit do controller aceita: **ela não existe** na tabela do legado e o param é descartado em silêncio — fecha `DB-312`
- [x] 1.4 `Indicator has_rich_text :description` sobre o **ActionText que a base já tem** (`config/application.rb:13`, `schema.rb:30`, `user.rb:18`). **Não criar coluna `description_html` paralela.** Documentar no runbook do ETL que `action_text_rich_texts` **tem de viajar junto**, e que os corpos podem estar **URL-escapados** — validação de codificação **item por item** — fecha `DB-313`

## Bloco 2 — Backend: catálogo global (I1)

- [x] 2.1 `Indicator` `validate` com as **3 regras de unicidade**, comparação case-insensitive e accent-insensitive: (a) global não repete título de **nenhum** outro → "Já utilizado"; (b) específico não repete título de global → "Já utilizado por indicador global"; (c) específico não repete título de outro específico **no mesmo projeto** → "Já utilizado nesse projeto". `errors.add` no lugar do `self.errors[:title] <<` depreciado. **Caracterização `G1`**, incluindo o efeito colateral replicado: dois projetos podem ter específicos homônimos, mas nenhum global pode usar esse nome depois — fecha `BE-320`
- [x] 2.2 `Indicator` `before_validation`: **título preservado como digitado** (T-D10), normalização só para comparação; `key` derivada do título no create (minúsculas, sem acento, espaços → sublinhado) e **não** recalculada no update; `value_type` default. `title` nil devolve **422**, não 500. **Caracterização `G2`** — fecha `BE-321`
- [x] 2.3 `enum :value_type` com **um** valor ("Dinheiro"), modelado como enum extensível sem migração de dados. `beauty_value` formata BRL; entry sem id devolve `"N/A"`. **Não inventar** percentual nem quantidade (Q-R32) — fecha `BE-715`
- [x] 2.4 `Indicator` `after_save`: propaga `title`, `key` e `value_type` para as entries. **Replicar o resultado** (o histórico é reescrito, T-D11), mas **fora do request**: acima de N linhas vira job Sidekiq. **Caracterização `G4`**: indicador com 20.000 lançamentos não trava a edição do título — fecha `BE-322`
- [x] 2.5 `Indicators::IndicatorService#index` + `EP/indicators.rb`: filtra **somente `project_id: nil`** (globais); busca `ILIKE` em `title`; ordem default `title ASC`; **paginação real com `X-Total-Count`** — hoje o front manda `l=50, o=0` fixos e nunca incrementa o offset, então **a lista trunca em 50 sem aviso**. **Catálogo global: sem escopo de projeto** (C1, regra 4) — fecha `BE-311`
- [x] 2.6 Allowlist de ordenação (`title`, `key`) no `params do … end`. **Corrige 3 bugs**: `prepare_ordering` chamava `Segment.get_ordering_key`/`get_ordering_style`; `get_ordering_key("key")` devolvia `"integration_key"`, **coluna que não existe** → `PG::UndefinedColumn` (500); e a chave era interpolada no SQL sem allowlist real — fecha `BE-312`
- [x] 2.7 `#create` **transacional** com a `ProjectIndicatorConnection`: hoje, se o `Indicator.create` falha, o legado ainda tenta `ProjectIndicatorConnection.create(indicator_id: nil, …)`, que **falha em silêncio** por validação de presença — sem feedback nenhum. Sai o `destroy` em objeto não persistido; `user_id` do form é descartado e vira `created_by` do servidor (Q-R24) — fecha `BE-316`
- [x] 2.8 `#update` com **um** save (hoje são dois, e o `after_save` de propagação roda **duas vezes**) e **sincronização da conexão**: trocar `project_id` de um indicador existente hoje **não** cria nem remove a `ProjectIndicatorConnection`, e o indicador vira "específico" sem conexão e **some da tela do projeto** — fecha `BE-317`
- [x] 2.9 `#activate` com `is_active` boolean e guarda: id inexistente deixa de ser `nil.is_active=` → **500**. A coluna deixa de ser integer livre (hoje `is_active?` só considera `== 1`, então 2 ou −1 contam como inativo) — fecha `BE-319`
- [x] 2.10 `EP/indicators.rb`: drawer (`new`) com `project_id` → específico, sem → global; `#show` → 404 estruturado; o formulário continua **sem** expor `value_type` e `is_active` — replicar — fecha `BE-314` e `BE-315`

## Bloco 3 — Backend: exclusão lógica, o fechamento do D-66 (I1)

> **Esta tarefa vem antes de qualquer tela de exclusão.**

- [x] 3.1 `#destroy` vira **exclusão lógica** (`discarded_at`), seguindo o padrão vivo da base (`PostDraft` + job de purga) — **não inventar gem**, porque **não existe soft delete na base ai9**. `has_many :entries` **perde o `dependent: :delete_all`**, que hoje apaga **toda a série histórica** sem callbacks, sem backup e sem confirmação específica. `restrict_with_error` de `project_indicator_connections` mantido. O caminho de erro deixa de responder 200 — fecha `BE-318`
- [x] 3.2 Job de purga dos indicadores descartados, no padrão de `PurgeDiscardedDraftsJob`, com trilha de auditoria das exclusões — fecha `OPS-313`
- [x] 3.3 `Indicators::BackfillService` como **rake task idempotente com log**, substituindo `Indicator.fix_titles` (que re-salva todos os indicadores para forçar normalização e propagação, sem rake task, sem log e sem idempotência declarada). Em base grande, job em vez de `UPDATE` em massa síncrono — fecha `OPS-311`
- [x] 3.4 **T-D13 aplicada:** a `key` permanece obrigatória, derivada do título e **sem** constraint de unicidade, sem mudança de formato e sem remoção, até a resposta sobre consumidor externo — fecha `OPS-312`

## Bloco 4 — Backend: conexões e indicadores específicos (I2)

- [x] 4.1 `Indicators::ConnectionService#connectable`: `Indicator.where(project_id: [projeto, nil])` — globais **mais** os específicos do projeto. **Fecha o risco de execução de código**: `params[:owner_type].constantize` e `params[:connection_type].constantize` viram **allowlist fechada**. **Corrige** também os ramos `if connection_type == "Carrier"/"Project"` que **nunca casam** com `"Indicator"` — hoje o `q` é ignorado e limit/offset não são aplicados, então a busca da tela **não filtra nada** (o front chama com `l=200`) — fecha `BE-707`
- [x] 4.2 `#connect`: uma `ProjectIndicatorConnection` por conector, duplicata barrada pela unicidade. **Transação + relatório por item**: hoje o erro **não é agregado** — só a última conexão do laço é inspecionada, então conectar 3 indicadores com 1 falha **pode reportar sucesso** — e o `save` nem é verificado. Nomes de coluna deixam de ser montados por `underscore + "_id"` sobre input do usuário. Membership validado — fecha `BE-709`
- [x] 4.3 `#disconnect`: destrói a conexão e **não apaga os `indicator_entries`** — desconectar esconde o indicador da tela e os lançamentos históricos continuam no banco; reconectar os traz de volta (Q-R31, replicar). Par inexistente vira **404/no-op idempotente**, não `nil.destroy` → 500 — fecha `BE-710`
- [x] 4.4 `#destroy_specific`: destrói a conexão e **depois** o indicador (ordem obrigatória por causa do `restrict_with_error`), passando pelo soft delete de 3.1. **Corrige o ramo defeituoso**: quando o indicador é global, `@connection` vem do `before_action` e pode ser uma **`Relation`**, não um record — `.errors` estoura. O `FIXME` registra que a issue #7102 corrigia um id errado que **deletava o indicador incorreto** — fecha `BE-711`

## Bloco 5 — Backend: grade mensal e lançamentos (I3)

- [x] 5.1 `Indicators::EntryService#grid`: devolve **indicadores** (não entries), `project.indicators` filtrado por `is_active`, para o ano corrente ou mês único. **Corrige N+1 severo sem mudar resultado**: hoje as entries são buscadas **dentro da view**, uma query por (indicador × mês) — **12 queries por indicador**. Passa a **uma** query com a grade montada em memória. **Corrige** também a ordenação alfabética **descartada em silêncio** (`@indicators.order(title: :asc)` não é atribuído) e o `project_id` inválido que é `nil.indicators` → 500. `q` some (não há busca); `l`/`o` passam a valer. **Caracterização `G3`** — fecha `BE-324`
- [x] 5.2 `#grid` distingue **"não lançado" (`nil`) de "lançado como zero" (`0`)** no payload — a distinção nasce **no serviço**, não numa heurística do componente (Q-R34) — fecha parte de `BE-324`/`FE-326`
- [x] 5.3 `#upsert`: um lançamento por (mês, ano, projeto, indicador), `value` decimal. **Corrige falha de segurança**: `user_id` vem **do formulário** e está no permit — dá para registrar lançamento em nome de outro usuário forjando o campo. Passa a vir do servidor. **Corrige** também a corrida (sem índice único no banco havia duplicatas) e o caso de outra aba já ter criado a entry: o POST falhava com "já está em uso" em vez de atualizar — vira **upsert** — fecha `BE-326`
- [x] 5.4 `#update`: um save; `title`/`key`/`value_type` continuam sobrescritos pelo `before_validation` a partir do indicador; `indicator_id` nil devolve **422**, não 500. `user_id` separado em `created_by`/`updated_by` (Q-R28), e trocar `month`/`year`/`indicator_id`/`project_id` — que hoje **move o lançamento de período sem trilha** — passa a registrar auditoria — fecha `BE-327`
- [x] 5.5 **RISCADA EM PARTE PELA DEC-71:** o endpoint existe com autorização e escopo, **sem confirmação e sem tela** (nenhuma view do legado o chama). · `#destroy` com confirmação e autorização, a célula voltando ao estado "não lançado" (T-D12). No legado, o ramo de erro referencia um template que **não existe** → 500 dentro de um 200 — fecha `BE-328`
- [x] 5.6 `IndicatorEntry`: identidade por (projeto, indicador, mês, ano), **periodicidade sempre mensal** (não há diário, semanal nem trimestral), `month`/`year` inteiros **com CHECK `1..12`** — hoje mês 13 ou ano 0 passam pela validação e explodem depois em `Date.new(year, month)`. `value` decimal com `presence` e default 0: **zero é válido, `nil` não** — fecha `BE-329`
- [x] 5.7 Portar **só** as 4 consultas que existem — `entry_on_month_and_indicator`, `entries_on_month`, `entries_on_indicator` e `all_entries_on_month` (que materializa os meses não lançados). As duas **sem chamador** são portadas como domínio coberto por teste, **sem endpoint**. **Nada de variação, acumulado, média ou gráfico** (DEC-09) — fecha `BE-716`

## Bloco 6 — Backend: autorização (transversal do módulo)

- [x] 6.1 Policy do **AUTH.S3** aplicada a `EP/indicators.rb`, `EP/indicator_entries.rb` e `EP/indicator_connections.rb`, conforme as linhas `indicators`, `indicator_entries`, `indicator_connections` e `project_indicator_connections` de `authorization-matrix.md`. **Corrige gap de segurança confirmado**: hoje **toda a autorização é de view** — nenhum dos três controllers tem `before_action` de permissão, e qualquer autenticado pode `POST /indicators`, `PUT .../connections` ou `POST /indicator_entries` direto. Catálogo global: **leitura liberada ao Colaborador** (DEC-18.4), escrita por papel; lançamentos por projeto. Cada teste verifica **os dois lados** da hierarquia (**C3**) — fecha `BE-717`

## Bloco 7 — Frontend: catálogo global (I1)

- [x] 7.1 `FE/indicators/pages/IndicatorsPage.tsx` — menu "Cadastro › Indicadores", só admin/og/manager; coluna "Título" ordenável; **paginação real** e **estado de erro** (o `failure` do proxy legado é vazio) — fecha `FE-310`
- [x] 7.2 `IndicatorSearch.tsx` — debounce 300 ms, requisição anterior cancelada, busca só de espaços não dispara, **botão de limpar** (hoje não existe) — fecha `FE-311`
- [x] 7.3 `DS/DataTable.tsx` com ciclo `default → up → down → default` e múltiplas chaves acumuladas; a ordenação por "Chave" **passa a funcionar** (hoje daria `PG::UndefinedColumn` se a coluna fosse clicável); estado da ordenação **persistido na URL** — fecha `FE-312`
- [x] 7.4 `IndicatorCard.tsx` com `ui/accordion.tsx` do Radix em modo exclusivo (abrir um fecha os outros), chevron só quando há descrição — **`reuse`, serve como está**, com teclado e ARIA de graça — fecha `FE-313`
- [x] 7.5 Dropdown Editar / Excluir, escondido inteiro para `user_is_readonly`, com o gate **espelhado no servidor** — fecha `FE-314`
- [x] 7.6 Confirmação de exclusão que **diz quantos lançamentos e quais projetos** serão afetados, **antes** de qualquer escrita, sobre a exclusão lógica de 3.1. **Corrige o D-66 na copy**: hoje a confirmação **não avisa que todos os lançamentos históricos serão apagados junto**, e o `$.ajax` sem callback de `error` fazia a lista recarregar com o item ainda lá — fecha `FE-315`
- [x] 7.7 `IndicatorDrawer.tsx` + **promover um** dos componentes de rich text existentes (`RichTextInput.tsx` ou `RichTextEditor.tsx`, ambos hoje **sem nenhum consumidor**) a `DS/RichTextField.tsx`, membro da biblioteca. **Sanitizar na borda de leitura deste componente** (UF-1), sem tocar no compartilhado. Título, Chave, Instrução + toasts; ao salvar, recarrega a lista **e** a aba de lançamentos se estiver montada. Corrige a copy "Essa construtora não pode ser alterada" — fecha `FE-316`
- [x] 7.8 Deep-links `/indicators/add` e `/indicators/:id/edit` com abertura automática do drawer — **no legado isso já funciona**, mas por `history.replaceState`: passa a rota real com histórico, e o botão Voltar deixa de sair do console (D-92) — fecha `FE-317`
- [x] 7.9 `user_is_readonly` no front: some "Cadastrar", some o ⋮ e somem Editar/Excluir; "Cadastrar" exige **adicionalmente** admin/og/manager — **agora com par no backend** (6.1) — fecha `FE-318`
- [x] 7.10 Estado ativo/inativo exibido **nas duas** telas: hoje esse estado **só existe na de específicos**, embora `is_active` valha para todos — fecha `FE-322`

## Bloco 8 — Frontend: conexões e específicos (I2)

- [x] 8.1 `ProjectIndicatorsPage.tsx` — tela "Indicadores específicos", grupo "Projeto", passando pelo **`current_project!`** em vez do projeto padrão **hardcoded no data-attribute e na URL do proxy** (quem não tem projeto padrão quebra hoje). O listener de busca **sem input correspondente no HTML** vira busca real — fecha `FE-319`
- [x] 8.2 `ConnectionRow.tsx` com `ui/switch.tsx` do Radix (**`reuse`**) só para indicadores **globais**, e React Query `isPending` no lugar do `preventDoubleSubmit`, que hoje bloqueia o **segundo** clique **para sempre** enquanto o widget não é re-renderizado. Corrige a concordância ("a relação foi ativado") — fecha `FE-320`
- [x] 8.3 Menu do indicador **específico** (Editar / Ativar-Desativar / Excluir) **com a mesma confirmação informada de `FE-315`**. **Corrige inconsistência grave**: aqui "Excluir" **não tem diálogo de confirmação nenhum** e apaga o indicador **e todos os seus lançamentos**. Corrige os typos "deasativado" e "Falhou ao ativado/deasativado" e o rótulo em minúscula — fecha `FE-321`
- [x] 8.4 Mensagem "Você não possui permissão para alterar o estado do indicador" no clique, **com o controle visível**. Este é o **único ponto do módulo legado que explica a restrição em vez de esconder o controle** — generalizar como padrão para as telas do bloco — fecha `FE-323`

## Bloco 9 — Frontend: grade mensal (I3)

- [x] 9.1 `IndicatorEntriesPage.tsx` — grade à esquerda, card de FILTROS à direita, menu "Gestão › Lançamentos de indicadores" (rótulo distinto do catálogo, Q-R33). O modo `silent` vira `keepPreviousData`; o listener de busca **sem input** é removido ou implementado — fecha `FE-324`
- [x] 9.2 `EntryFilters.tsx` — POR INDICADOR: só os **ativos** do projeto, com "Todos"; POR PERÍODO: mês (12 meses pt-BR, "Todos") e ano (**ano atual −5 a +5**, sem blank, default = ano atual). Filtros **persistidos na URL** (hoje se perdem entre visitas) — é deep-link, não feature nova — fecha `FE-325`
- [x] 9.3 `MonthlyGrid.tsx` — um card por indicador, 12 linhas (Jan..Dez), cada uma com submit independente, instrução (rich text) exibida acima da grade. **Distingue visualmente vazio de zero** (Q-R34) — hoje mês não lançado monta um `IndicatorEntry.new` e mostra **`0`**, indistinguível de um lançamento real de zero — fecha `FE-326`
- [x] 9.4 Modo mês único: cada indicador vira **uma linha só**, rotulada com o título do indicador em vez do nome do mês, **e com a instrução exibida** — hoje o bloco de instrução só existe no ramo de 12 meses — fecha `FE-327`
- [x] 9.5 `DS/MoneyInput` na célula: pt-BR, 2 casas, **valores negativos permitidos** (sinal só na primeira posição). Quarta e última cópia de máscara do legado eliminada; o lookbehind `(?<!^)\-`, que quebra em Safari antigo, some junto — fecha `FE-328`
- [x] 9.6 Autosave por célula com React Query `useMutation` + **`onError`**. **Corrige o pior estado de UI do bloco inteiro**: hoje **não há handler de erro nenhum** — em 422 o usuário vê o campo destravar sem mensagem e **acredita que salvou** — e `preventDoubleSubmission` marca o form como enviado e **nunca limpa a flag**, então após o primeiro auto-save o mesmo campo não envia de novo até a lista recarregar. Input readonly durante o envio; cor ao vivo pelos tokens semânticos (D-101) — fecha `FE-329`
- [x] 9.7 Readonly na célula **com a mensagem explicativa** do padrão de `FE-323`, e o backend passando a **impedir** o POST (hoje não impede) — fecha `FE-718`
- [x] 9.8 Accordion exclusivo no card do indicador; no modo mês único **não há título clicável** — interação inexistente nesse modo, replicar — fecha `FE-719`

## Bloco 10 — Testes

- [x] 10.1 `spec/models/indicator_spec.rb` — caracterização **`G1`** (as 5 combinações de unicidade, incluindo o efeito colateral replicado) e **`G2`** (título preservado, chave derivada, `title` nil → 422)
- [x] 10.2 `spec/services/indicators/entry_service_spec.rb` — caracterização **`G3`**: uma consulta em vez de 12 por indicador, ordenação alfabética aplicada, e vazio distinguível de zero
- [x] 10.3 `spec/models/indicator_entry_spec.rb` — unicidade por (projeto, indicador, ano, mês) na aplicação **e** no índice; CHECK de mês; `value = 0` válido e `nil` inválido; negativos aceitos
- [x] 10.4 `spec/services/indicators/indicator_service_spec.rb` — caracterização **`G4`**: o histórico é reescrito **e** a resposta não espera 20.000 updates; e a exclusão lógica **preserva** os lançamentos
- [x] 10.5 `spec/services/indicators/connection_service_spec.rb` — allowlist no lugar do `constantize`; erro **agregado por item** ao conectar vários; desconectar não apaga lançamentos e reconectar os recupera
- [x] 10.6 `spec/requests/api/v1/indicators_spec.rb` — CRUD, paginação com `X-Total-Count` real, 400 em chave de ordenação inválida, 404 estruturado
- [x] 10.7 `spec/requests/api/v1/indicator_entries_spec.rb` — upsert idempotente, `user_id` **ignorado** quando vem do payload, 422 em mês fora de faixa
- [x] 10.8 Teste de escopo (**C1**): lançamentos e conexões escopados por projeto; **catálogo global acessível sem escopo**, com leitura liberada ao Colaborador
- [x] 10.9 Teste de autorização (**C3**) por endpoint, verificando **os dois lados** da hierarquia — é a correção do gap de `BE-717`
- [x] 10.10 Teste de que a Instrução em rich text sobrevive a um ciclo de escrita e leitura, e de que o conteúdo é **sanitizado na borda de leitura** (UF-1)
- [x] 10.11 Front: type-check em **0 erro**; revisão visual do catálogo, dos específicos e da grade em **light e dark**

## Bloco 11 — Paridade e fechamento

- [x] 11.1 Marcar no `parity-ledger.md` os **39 `build`**, os **5 `adapt`** e os **4 `reuse`** desta fatia, um a um
- [x] 11.2 Registrar `dropped` **com a evidência da varredura** para os 9 `drop`: `BE-310`, `BE-313`, `BE-323`, `BE-325`, `BE-708`, `BE-712`, `BE-713`, `BE-714` e `OPS-310` (motivos em `proposal.md` §"`drop` — motivo registrado")
- [x] 11.3 Fechar ou reencaminhar os **5 `build?`**: `BE-321` (T-D10), `BE-322` (T-D11), `BE-328` (T-D12), `BE-329` (resolvido pela spec: inteiros + CHECK) e `OPS-312` (T-D13). Um `build?` sem resolução registrada **bloqueia o fechamento da fatia**
- [x] 11.4 **PARCIAL, e o motivo está declarado.** As quatro caracterizações foram verificadas **contra a FONTE do legado** (arquivo e linha citados em cada exemplo de `spec/models/indicator_spec.rb` e `spec/services/indicators/entry_service_spec.rb`), que é a evidência disponível. **Contra o DUMP não foi possível: o dump de produção não existe neste repositório** (checkpoint, "pendente do usuário") e a **DEC-102** adiou a carga de dados para depois da apresentação. O conversor de ETL foi escrito mesmo assim (`Sfg::Etl::Converters::Indicators` e irmãos), com spec próprio · Verificar contra o legado as caracterizações `G1`…`G4`
- [x] 11.5 Runbook do ETL: confirmar que `action_text_rich_texts` viaja junto com `indicators` e que a codificação dos corpos foi validada **item por item** (podem estar URL-escapados) — sem isso **a Instrução se perde**
- [x] 11.6 Confirmar que **nada** de série calculada, variação, acumulado, média ou gráfico entrou nesta fatia (DEC-09). O gráfico é `NEW-001`, de **S15**, e entra no ledger como `new` — **o QA do Phase 4 não deve procurá-lo no legado**
- [x] 11.7 Handshake com **S15**: a série mensal está disponível pelo endpoint da grade, no formato que `NEW-001` vai consumir


## Fechamento de órfãos do Phase 2 — esquema de indicadores

Três IDs que não tinham dono e passam a ser desta fatia. Ver a seção correspondente do
`proposal.md`.

- [x] F.1 Conferir `indicators`, `project_indicator_connections` e `indicator_entries` contra
      a descrição de `data-schema` — mesmas tabelas, sem segunda família. **Fecha: DB-585,
      DB-586, DB-587.**
- [x] F.2 Confirmar que os índices da grade mensal existem (o N+1 severo que a fatia corrige
      depende deles) e que a série por período não faz varredura completa.
