# Design: S10 — Indicadores e séries mensais em ai9

> As 62 linhas item-a-item **não são duplicadas aqui**. A fonte é
> `.migration-ai9/map/risk-indicators.md` **§2.5** (`indicators` — catálogo, conexões e
> grade mensal). Cada linha lá traz "Equivalente ai9", "O que muda", "Melhoria proposta" e
> "Risco". Este documento descreve **o desenho**.

## 1. `Indicators::EntryService` — o serviço único da grade (C2)

### O problema que ele resolve

No legado a grade é montada **dentro da view**: uma query por (indicador × mês) — **12
queries por indicador** no modo "todos os meses" — e para os meses não lançados a view
materializa em memória um `IndicatorEntry.new(value: 0)`. O autosave, do outro lado, é um
`$.ajax` por célula **sem handler de erro**. Leitura e escrita não se conhecem: é por isso
que uma célula pode mostrar `0` para um mês que nunca foi lançado, e mostrar "salvo" para
uma gravação que foi recusada.

### Forma no ai9

```ruby
# backend/app/services/indicators/entry_service.rb
module Indicators
  class EntryService
    class << self
      include ApiResponseHandler

      # Monta a grade em UMA consulta. Devolve indicadores com as células
      # do período, distinguindo "não lançado" (nil) de "lançado como zero" (0).
      def grid(project:, year:, month: nil, indicator_id: nil)   # BE-324

      # Grava UMA célula. Upsert por (projeto, indicador, ano, mês).
      def upsert(project:, indicator:, year:, month:, value:, user:)  # BE-326

      def update(entry, attrs, user)                              # BE-327
      def destroy(entry, user)                                    # BE-328

      # As 4 consultas que existem no legado — e só elas (BE-716)
      def entry_on_month_and_indicator(...)
      def entries_on_month(...)
      def entries_on_indicator(...)
      def all_entries_on_month(...)   # materializa os meses não lançados
    end
  end
end
```

### Quem chama

| Chamador | Caminho |
| -------- | ------- |
| **Grade** (`MonthlyGrid`) | `GET /api/v1/indicator_entries/grid` → `grid` |
| **Autosave da célula** | `PUT /api/v1/indicator_entries` → `upsert` — o **mesmo** serviço |
| **Exclusão de lançamento** | `DELETE …` → `destroy` (atrás de T-D12) |

**A regra que não pode ser quebrada:** a distinção entre "não lançado" e "zero" nasce **no
serviço** (`nil` × `0`), não numa heurística do componente. Se o front tivesse que adivinhar,
a ambiguidade voltaria na primeira refatoração.

### Escopo (DEC-09) — o que este serviço NÃO faz

**Não existe** cálculo de variação (mês a mês, ano a ano, percentual), acumulado, média nem
gráfico em lugar nenhum do legado, e o `dash` não referencia indicadores. Isso é **requisito
novo** (`NEW-001`, fatia **S15**), não paridade — o QA do Phase 4 **não deve procurá-lo no
legado**. Duas das quatro consultas portadas (`entries_on_month` nas suas duas formas) **não
têm nenhum consumidor** hoje: são portadas como domínio coberto por teste, **sem endpoint**.

## 2. Caracterização — os valores que travam o comportamento atual

Este módulo não tem fórmula financeira, mas tem **quatro regras que produzem resultado
observável** e hoje têm **zero cobertura** (`OPS-314`: 5 models, 4 controllers e ~40 views
sem um único teste). Cada uma ganha teste de caracterização com valores explícitos.

**`G1` — as três regras de unicidade (`BE-320`).** Comparação case-insensitive e
accent-insensitive, exata:

| Situação | Resultado esperado | Mensagem |
| -------- | ------------------ | -------- |
| global "MARGEM" e novo global "margem" | recusado | "Já utilizado" |
| global "MARGEM" e novo específico "Margem" em `P1` | recusado | "Já utilizado por indicador global" |
| específico "Margem" em `P1` e novo específico "margem" em `P1` | recusado | "Já utilizado nesse projeto" |
| específico "Margem" em `P1` e novo específico "Margem" em `P2` | **aceito** | — |
| específico "Margem" em `P1` e novo **global** "Margem" | recusado | "Já utilizado" |

A última linha é o efeito colateral da regra (a): dois projetos podem ter específicos
homônimos, mas nenhum global pode usar esse nome depois. **Replicado.**

**`G2` — normalização e derivação da chave (`BE-321`).**

| Entrada | `title` gravado | `key` derivada |
| ------- | --------------- | -------------- |
| "Rentabilidade média" | **"Rentabilidade média"** (spec — preserva o digitado) | **`rentabilidade_media`** |
| `nil` | — | **422**, não 500 (hoje `I18n.transliterate(nil)` estoura **antes** da validação de presença) |
| título com chave informada | como digitado | a informada, **não** recalculada no update |

> O dado **migrado** chega em CAIXA ALTA sem acento — os acentos originais já se perderam
> de forma irreversível no legado. A regra nova vale para o que for digitado a partir de
> agora. Ver T-D10.

**`G3` — a grade (`BE-324`, `BE-716`, `FE-326`).**

| Situação | Hoje | No ai9 |
| -------- | ---- | ------ |
| março lançado com `0` | exibe `0` | exibe `0`, marcado como lançado |
| abril nunca lançado | exibe `0` (indistinguível) | exibe **vazio**, distinguível |
| 3 indicadores × 12 meses | **36 queries** (uma por célula) | **1 query**, grade montada em memória |
| ordenação alfabética | **descartada em silêncio** (`@indicators.order(title: :asc)` não é atribuído) | aplicada |
| `project_id` inválido | `nil.indicators` → **500** | 404/422 |

**`G4` — a denormalização (`BE-322`).** Renomear um indicador reescreve `title`, `key` e
`value_type` de **todas** as suas entries via `update_all` — **pulando validações e
callbacks e sem atualizar `updated_at`**. Resultado replicado; o que muda é que, acima de N
linhas, isso sai do request e vira job. O teste trava as duas coisas: o histórico é
reescrito **e** a resposta ao usuário não espera 20.000 updates.

## 3. Exclusão lógica — como o D-66 é fechado

**Não existe soft delete na base ai9** (nem gem, nem coluna `deleted_at`). O que existe é o
padrão de `PostDraft`: status explícito + `discarded_at` + `PurgeDiscardedDraftsJob`. É esse
o padrão seguido — **não inventar gem** (Princípio 6b).

| Camada | O que muda |
| ------ | ---------- |
| Dados (`DB-310`) | coluna `discarded_at` no `indicators` |
| Serviço (`BE-318`, `OPS-313`) | `#destroy` marca `discarded_at`; `has_many :entries` **perde o `dependent: :delete_all`**; `restrict_with_error` de `project_indicator_connections` é mantido |
| UI global (`FE-315`) | a confirmação passa a dizer **quantos lançamentos e quais projetos** serão afetados, **antes** de qualquer escrita |
| UI específicos (`FE-321`) | ganha a **mesma** confirmação — hoje esta tela **não tem diálogo nenhum** e apaga indicador e lançamentos direto |
| Purga | job, no padrão da base |

`BE-711` tem um agravante próprio: quando o indicador é **global**, o legado adiciona o erro
"não é possível remover indicadores globais com associação", mas nesse ramo `@connection` vem
do `before_action` e pode ser uma **`Relation`**, não um record — `.errors` estoura. O
`FIXME` no código registra que a issue #7102 corrigia um id errado que **deletava o indicador
incorreto**. Fechar isso é parte da fatia.

## 4. Escopo por projeto (C1) — o que é global e o que não é

```ruby
# lançamentos e conexões: por projeto
project = current_project!
scope   = IndicatorEntry.for_project(project)

# catálogo global: SEM escopo (regra 4 do §0.6)
Indicator.where(project_id: nil)
```

| Recurso | Escopo |
| ------- | ------ |
| `indicators` com `project_id IS NULL` | **catálogo global** — leitura liberada ao Colaborador (DEC-18.4), escrita por papel |
| `indicators` **específicos** | por projeto |
| `indicator_entries`, `project_indicator_connections` | por projeto |

Duas correções de segurança caem aqui:
- **`BE-707`** — `params[:owner_type].constantize` e `params[:connection_type].constantize`
  viram **allowlist fechada**. E os ramos `if connection_type == "Carrier"/"Project"`
  **nunca casam** com `"Indicator"`, então hoje o `q` é ignorado e limit/offset não são
  aplicados: a busca da tela **não filtra nada** (o front chama com `l=200`).
- **`FE-319`** — o escopo é `current_user.default_project` **hardcoded no data-attribute e
  na URL do proxy**, sem seletor de projeto; quem não tem projeto padrão quebra em
  `default_project.id`. Passa pelo `current_project!`.

## 5. Rich text — o reuso real, e a flag que ele levanta

`DB-313`/`FE-316` são **`adapt`, não `build`**, e isso foi medido: `action_text/engine` está
em `backend/config/application.rb:13`, a tabela `action_text_rich_texts` (PK uuid, índice
único em `record_type`/`record_id`/`name`) está em `backend/db/schema.rb:30`, e
`backend/app/models/user.rb:18` já faz `has_rich_text :biography`. A "Instrução" do
indicador vira `has_rich_text :description` na tabela que a base **já tem**.

No **front**, porém, o reuso não é "apontar e usar": `components/RichTextInput.tsx` e
`components/RichTextEditor.tsx` (Slate) **têm zero consumidor**, e o editor vivo é uma função
local dentro de `app/pages/ProfilePage.tsx:200`. **Promover um dos dois a membro da
biblioteca** faz parte do `FE-316` (Princípio 11).

**Upstream flags levantadas aqui, não corrigidas nesta migração:**

| # | Achado | O que esta fatia faz |
| - | ------ | -------------------- |
| **UF-1** | `RichTextInput.tsx` renderiza com **`dangerouslySetInnerHTML` sem sanitização**, e não há DOMPurify no `package.json`. A "Instrução" é HTML escrito por um usuário e lido por **todos os outros** do projeto — é XSS armazenado com alcance de tenant | **Sanitizar na borda de leitura do próprio componente desta fatia**, sem tocar no compartilhado. Sanitizar o compartilhado afeta todo consumidor de rich text da base |
| **UF-2** | Três implementações de rich text para um caso de uso; o `package.json` carrega **duas** stacks (`slate*` e `@tiptap/*`) | Registrar. Consolidar é refactor da base |

**Ponto crítico do ETL:** o texto **não vive** em `indicators`. Qualquer export/import
precisa levar `action_text_rich_texts` junto, ou **o conteúdo se perde**. E os corpos podem
estar **URL-escapados** (daí o `CGI.unescape` nas views de contrato do legado), então a
codificação precisa ser validada **item por item**, não em lote.

## 6. Grupos de IDs → camada alvo em ai9

### Dados — `DB-310…DB-313`
- `indicators`: índices em `project_id`, `title` e `key` (hoje **nenhum além da PK**), FK
  real para `projects`, `is_active` integer → boolean, `discarded_at`. A `key` **não é única
  hoje**: checar duplicatas antes de aplicar qualquer constraint (**Q-R26** decide se ela
  pode virar única).
- `indicator_entries`: **índice único composto obrigatório** em (`project_id`,
  `indicator_id`, `year`, `month`) — hoje a unicidade só existe na aplicação e **há corrida**
  — mais um índice de leitura em (`project_id`, `year`, `month`, `indicator_id`) para a
  grade. **É a maior tabela da unidade** (~projetos × indicadores × 12 × anos). CHECK de
  faixa em `month`. `value` **aceita negativos** — replicar.
- `project_indicator_connections`: join table pura, único (`project_id`, `indicator_id`) +
  FKs. **Não migrar** o `is_active` do permit do controller — **essa coluna não existe** na
  tabela e o param é descartado em silêncio.

### Backend — `BE-311…BE-329`, `BE-707…BE-717`
`backend/app/models/{indicator,indicator_entry,project_indicator_connection}.rb`,
`backend/app/services/indicators/{indicator_service,connection_service,entry_service,backfill_service}.rb`,
`backend/app/controllers/api/v1/{indicators,indicator_entries,indicator_connections}.rb` +
entities. Padrão `class << self` + `ApiResponseHandler`.

### Frontend — `FE-310…FE-329`, `FE-718`, `FE-719`
`frontend/src/features/indicators/{pages,components,api,types}/`, React Query v5.
Quatro `reuse` verificados: `ui/accordion.tsx` (duas vezes), `ui/switch.tsx` e
`react-router-dom` — os únicos casos do bloco inteiro em que a peça da base serve **como
está**, sem uma linha de adaptação.

O padrão de UX que esta fatia **generaliza**: `FE-323` é o **único ponto do módulo legado que
explica a restrição em vez de esconder o controle** ("Você não possui permissão para alterar
o estado do indicador", com o switch visível). Esse é o padrão certo, e passa a valer para as
telas do bloco em vez de o botão simplesmente sumir.

### Operação — `OPS-311…OPS-314`
`Indicator.fix_titles` (que re-salva todos os indicadores para forçar normalização e
propagação) vira **rake task idempotente com log**, e em base grande vira job em vez de
`UPDATE` em massa síncrono.

## 7. O que fica registrado, não corrigido (Princípio 6b)

| Achado | Ação |
| ------ | ---- |
| **UF-1** e **UF-2** (rich text) | Linha em `upstream-flags.md`; sanitização só na borda desta fatia |
| **UF-3** — `lib/i18n.ts` inicializa i18next só com pt-BR embora `locales/en` exista e o `LanguageSwitcher` esteja na navegação | Registrar. Um seletor de idioma que não troca idioma é enganoso numa demo comercial, mas ligar i18n é escopo de plataforma |
| `sidekiq-cron` com bloco de cron **vazio** após o trim | Registrar que a infra de agendamento existe se o negócio pedir lembrete depois (`OPS-310`) |

## 8. Ordem de execução e critério de pronto

Ordem: **dados → backend → frontend → testes → paridade**. Duas travas próprias desta fatia:

1. **O soft delete vem antes de qualquer tela de exclusão.** Publicar a tela de exclusão
   sobre o `delete_all` atual seria entregar o D-66 na base nova.
2. **A caracterização `G1`…`G4` vem antes de qualquer refatoração de normalização ou de
   grade.** As regras de unicidade e a normalização de título não têm um único teste hoje;
   mexer nelas sem rede é adivinhação.

Uma tarefa está pronta quando o comportamento existe ponta a ponta, o teste que a cobre
passa, o gate de autorização foi verificado **nos dois lados** (C3) e o `parity-ledger.md`
recebeu o ID.
