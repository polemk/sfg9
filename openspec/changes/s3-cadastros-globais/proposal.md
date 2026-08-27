# Proposal: S3 — Cadastros globais (portadores, grupos, segmentos, subsegmentos, tipos)

> Fatia **S3** da ordem de execução de `.migration-ai9/migration-map.md`.
> Bloco de origem: `.migration-ai9/map/projects-cadastros.md` (fatia interna **§1 S1** +
> a parte de catálogo global da **§1 S8**).
> Depende de **S0** (fundação). Desbloqueia **S4** (projeto e empresas) e **S5** (limites de risco).

## Why

Nada no Safegold tem FK antes desta fatia. `projects` aponta para `segments` e
`sub_segments`; `project_to_carrier_connections`, `risk_controls`, `receivable_entries` e
`project_guarantees` apontam para `carriers`; `project_guarantees` aponta para
`project_guarantee_types`. Enquanto os cinco catálogos globais não existirem, toda fatia
posterior escreve FK contra tabela inexistente.

**A base ai9 não tem nenhum deles.** O veredito do bloco (`§0.1` do mapa) é literal: não
existe portador, segmento, subsegmento nem tipo de garantia — nem model, nem tabela, nem
tela. A estratégia é `build` em 46 dos 51 IDs. **O reuso está dentro de cada `build`**, e a
coluna "Equivalente ai9" do mapa está preenchida linha a linha: Grape + `controller_helpers`
+ Kaminari no servidor, design system + `SideDrawer` + React Query no cliente, ActiveStorage
+ `ImageCropper` nos logos, Postgres `ILIKE` com bind na busca.

Além de "não existir no destino", **três destes cadastros estão quebrados na origem** e a
paridade aqui é com o *comportamento pretendido*, não com o defeito:

- **D-21** — criar segmento falhava **100% das vezes** no legado (`user_id` fora do `permit`),
  e ordenar a lista de portadores por "Grupo" respondia **500**.
- **D-23** — `project_guarantee_types` declarava `requires_current_user? == false`: o
  endpoint respondia **para anônimo**. O gate og/admin/gerente só existia na view.
- **D-24** — excluir um portador **cascateava** e apagava os `risk_controls` dele. É a
  assimetria mais perigosa do bloco, e não se replica.

## What Changes

Cinco catálogos **globais** (DEC-07: catálogo global **não** recebe escopo de projeto —
`§0.6` regra 4 do mapa), com `R` liberado ao Colaborador (DEC-18.4) e escrita por papel
verificada **no servidor**:

| Recurso | Tabela | Endpoint |
| ------- | ------ | -------- |
| Segmentos | `segments` | `api/v1/segments.rb` |
| Subsegmentos | `sub_segments` | `api/v1/sub_segments.rb` |
| Grupos de portadores | `carrier_groups` | `api/v1/carrier_groups.rb` |
| Portadores (contraparte financiadora, com estrutura de FIDC) | `carriers` | `api/v1/carriers.rb` |
| Tipos de garantia | `project_guarantee_types` | `api/v1/project_guarantee_types.rb` |

Mudanças visíveis ao usuário, todas decididas no Phase 2 e registradas em
`.migration-ai9/improvements-log.md` como intencionais (para o QA do Phase 4 não as ler
como regressão):

1. **Paginação e ordenação passam a funcionar** (D-20 / DC-38). Hoje as telas trazem tudo.
2. **Criar segmento passa a funcionar** (D-21).
3. **Detalhe de portador passa a ser alcançável** (D-22 / DC-08) — o HTML e o SCSS já
   existem no legado e nenhuma rota chega neles.
4. **Exclusão bloqueada responde 422 de verdade** em vez de `:ok` (D-24).
5. **`bank_code` vira string** e preserva `001` (DC-12).
6. **`subordinated_accounts_percent` passa a ser derivado no servidor** (DC-09).
7. **Tipo de garantia deixa de responder para anônimo** (D-23).

## IDs de inventário cobertos (51)

Estratégia copiada de `.migration-ai9/map/projects-cadastros.md`. Requirements
correspondentes já existem em `openspec/specs/companies-carriers/spec.md` e
`openspec/specs/projects/spec.md` — **referenciados por ID, não recriados**.

### Backend — 19

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| BE-067 | build | `api/v1/carriers.rb` — catálogo global, busca simétrica, paginação real |
| BE-068 | build | `#form` e `GET /carriers/:id` — detalhe alcançável (DC-08) |
| BE-069 | build | `CarrierService.create/update` — `bank_code` string, `financial_agent` por inclusão |
| BE-070 | build | `CarrierService.destroy` — bloqueia, **nunca** cascateia (D-24) |
| BE-071 | build | `app/models/carrier.rb` — título duplicado **continua permitido** (preservado) |
| BE-072 | build | `api/v1/carrier_groups.rb` — ordenação por título funciona (D-21) |
| BE-073 | build | `CarrierGroupService` — grupo com portadores → 422 |
| BE-074 | build | `app/models/carrier_group.rb` — `carriers_count` consistente |
| BE-075 | build | `api/v1/segments.rb` — ordenação por título **e** chave, paginação real |
| BE-076 | build | `SegmentService` — criação passa a funcionar, `user_id` da sessão (D-21) |
| BE-077 | build | `api/v1/sub_segments.rb` — ordenação pelo próprio subsegmento |
| BE-078 | build | `SubSegmentService` — exclusão bloqueada por projetos vinculados → 422 |
| BE-700 | build | `api/v1/project_guarantee_types.rb` — global, `R` ao Colaborador, **401 sem credencial** |
| BE-701 | build | `#form` (criação) — 403 no servidor sem papel |
| BE-702 | build | `#form` (edição) — inexistente → 404 |
| BE-703 | build | `create` — `user_id` da sessão, título único |
| BE-704 | build | `update` — chave de integração congelada (DC-22) |
| BE-705 | build | `destroy` — tipo em uso → 422 |
| BE-706 | build | `GET /project_guarantee_types(/:id)` — rotas que respondem |

### Frontend — 13

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| FE-060 | build | `CarriersPage` — Título/Grupo/Agente/Cidade/# Projetos, com paginação |
| FE-062 | build | busca de portadores — vazio cita o termo |
| FE-063 | build | linha de portador — fallback `-`, clique abre "Relações" |
| FE-064 | build | formulário de portador — 13 campos, incluindo a estrutura de FIDC |
| FE-065 | build | "% contas subordinadas" derivado, sem divisão por zero (DC-09) |
| FE-067 | **build?** | logo do portador — **pendente de Q-04**; default: ligar |
| FE-068 | build | `CarrierDetailPage` — tela alcançável (DC-08) |
| FE-075 | build | `CarrierGroupsPage` — toast se refere ao grupo |
| FE-076 | build | painel lateral de grupo |
| FE-077 | build | `SegmentsPage` — criação funciona, bloqueio comunicado |
| FE-078 | build | `SubSegmentsPage` — textos próprios de subsegmento |
| FE-116 | build | tela "Tipos de garantia" — busca, ordenação, ações por papel |
| FE-117 | build | formulário de tipo de garantia — erro de dependência nomeia o campo |

### Dados — 12

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| DB-057 | build | `carriers` — `bank_code` string, percentual decimal, `bank_name` fora |
| DB-058 | build | `carriers.group_id` — FK + índice |
| DB-059 | build | `carriers.financial_agent` — enum string fechado |
| DB-060 | build | `carriers.city`/`.uf` — UF normalizada |
| DB-061 | build | `carriers.legacy_id` — preservada (DEC-12), única |
| DB-062 | **adapt** | `Carrier#logo` — ActiveStorage (DC-02) |
| DB-063 | build | `carrier_groups` — `carriers_count` default 0 |
| DB-064 | build | `segments` — `title` único **no banco** |
| DB-065 | build | `segments.legacy_id` — preservada (DEC-12) |
| DB-066 | build | `sub_segments` — catálogo independente (DC-13) |
| DB-072 | build | FK + índices dos cadastros (o legado tinha **zero** `add_foreign_key`) |
| DB-084 | build | `project_guarantee_types` — título e chave únicos no banco |

### Operação — 7

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| OPS-051 | **adapt** | validação e storage de logos por ActiveStorage — tipo **real** verificado |
| OPS-052 | build (mínimo) | só `carriers.legacy_id`; pipeline `Legacy::execute` **não** é portado (DEC-12) |
| OPS-053 | build (mínimo) | só `segments.legacy_id` (DEC-12) |
| OPS-054 | **adapt** | `db/seeds/catalogos.rb` separado de `db/seeds/demo.rb` |
| OPS-056 | build | `scope :search` com `ILIKE` e bind — sem `Dev.ilike` interpolando SQL |
| OPS-057 | build | `api/v1/br_states.rb` (constante `UF`) no padrão de `countries.rb`; sem geocoder |
| OPS-058 | build | `carrier_groups.carriers_count` por `counter_cache` |

**Placar:** 46 `build` · 4 `adapt` (BE-nenhum; DB-062, OPS-051, OPS-054, e FE-067 é `build?`)
· 1 `build?` (FE-067, pendente de Q-04) · 0 `reuse` puro · 0 `drop`.

## Fronteiras — o que este change **não** cobre

- **Carteiras (`wallets`)**, tipos de recebível e tipos de movimentação. O título global da
  fatia S3 as menciona, mas os IDs (**BE-185, BE-186, DB-158, DB-159, DB-160, FE-187,
  FE-188, FE-189, OPS-153**) pertencem ao bloco `receivables-renegotiations`, fatia **SR-1**
  daquele mapa. São catálogos globais irmãos, com exatamente a mesma forma; ficam no change
  do bloco de recebíveis para não haver dois donos. **Ver "Ambiguidade" no relatório.**
- **Empresas e fornecedores** — S4. São escopados por projeto, não são catálogo global.
- **Garantias do projeto** (BE-118, BE-119, FE-113..115, DB-083) — S4. Aqui só entra o
  **catálogo de tipos**.
- **Componentes compartilhados** `DataTable` (FE-061), `Pagination` (FE-053),
  `useDebouncedSearch` (FE-052), `MoneyInput`/`PercentInput` (FE-066),
  `EmptyState`/`ErrorState` (FE-079) e os helpers `require_role!`/`require_not_readonly!`
  (BE-079) — **S0**. Esta fatia os **consome**; não os cria.
- **DB-073 / DB-074** (introspecção e volumetria do ETL) — S14.

## Dependências

- **Depende de S0**: `require_role!`, `require_not_readonly!`, `DataTable`, `Pagination`,
  `useDebouncedSearch`, `EmptyState`/`ErrorState`, `MoneyInput`/`PercentInput`.
- **Depende do bloco `auth-users`**: papéis e hierarquia (contrato **C3** — a escala é
  invertida entre os dois sistemas).
- **É dependência de S4**: `projects.segment_id`/`.sub_segment_id`, conexões
  projeto↔portador, `project_guarantees.guarantee_type_id`.
- **É dependência de S5**: `risk_controls.carrier_id`.
- **Toca o bloco `risk`**: BE-070 só fecha quando existir `risk_controls` para bloquear a
  exclusão. Até lá o bloqueio cobre conexões e recebíveis, e a regra do portador fica com um
  teste pendente — registrado na tarefa 5.7.

## Perguntas em aberto

| # | Pergunta | Default se não houver resposta |
| - | -------- | ------------------------------ |
| **Q-04** | O logo do Portador volta a existir? (FE-067, DC-10) | **Ligo**, reusando a pilha dos outros dois logos |
| **Q-05** | Logos em `Medium` mesmo assim? (DC-02) | **Não** — `has_one_attached` direto; `media` não tem dono nem escopo |

## Capabilities

### New Capabilities

Nenhuma. Os requirements desta fatia já existem em `openspec/specs/` desde o Phase 1 e são
referenciados por ID (BE-###/FE-###/DB-###/OPS-###).

### Modified Capabilities

- `companies-carriers`: acréscimo de **um** requirement transversal (contrato **C1**, regra 4
  de `§0.6`) que o spec por ID não cobre — catálogo global **não** recebe escopo de projeto,
  e a escrita é negada **no servidor**, não na view. É a regra que impede alguém de "consertar"
  um catálogo global aplicando `for_project` nele, e a que fecha o D-23.

## Impact

- **Backend**: `app/controllers/api/v1/{carriers,carrier_groups,segments,sub_segments,project_guarantee_types,br_states}.rb`;
  `app/controllers/api/entities/{carrier,carrier_group,segment,sub_segment,project_guarantee_type}.rb`;
  `app/services/{carrier,carrier_group,segment,sub_segment,project_guarantee_type}_service.rb`;
  `app/models/{carrier,carrier_group,segment,sub_segment,project_guarantee_type}.rb`;
  registro dos novos módulos em `app/controllers/api/v1/base.rb`.
- **Dados**: 5 tabelas novas + `db/seeds/catalogos.rb`. Nenhuma tabela existente do ai9 é alterada.
- **Frontend**: `src/app/pages/carriers/`, `carrier-groups/`, `segments/`, `sub-segments/`,
  `guarantee-types/`; rotas em `src/app/App.tsx`; itens de menu em `src/hooks/useNavItems.ts`.
- **Nada da base ai9 é refatorado** (Princípio 6b). O que pareceu errado na base virou linha
  em `.migration-ai9/upstream-flags.md`.


## IDs adotados no fechamento do Phase 2 (conferência consolidada)

> A conferência **no consolidado** — a única que vale — encontrou **175 IDs de inventário sem
> dono nenhum**: cada fatia estava correta dentro de si, e ninguém pegou o que ficava entre
> elas. Os IDs abaixo já estavam **mapeados** (estratégia e alvo ai9 decididos em
> `.migration-ai9/map/`); o que faltava era **dono**. Passam a ser desta fatia, com tarefa
> própria em `tasks.md`.

| ID | Estratégia | O que é | Por que aqui |
| -- | ---------- | ------- | ------------ |
| DB-550 | build | `segments` | S3 é dona dos 5 catálogos globais |
| DB-551 | build | `sub_segments` | idem |
| DB-552 | build | `carriers` | idem |
| DB-553 | build | `carrier_groups` | idem |
| DB-558 | build | `project_guarantee_types` — tabela + **seed obrigatório** | idem |
| OPS-540 | build | O seed principal da app vira `backend/db/seeds/reference/`, **idempotente**, aplicado pelo deploy — o arcabouço que os catálogos das outras fatias também usam | S3 é a primeira fatia que semeia catálogo |

**Os cinco `DB-55x` são as tabelas dos cinco recursos que esta fatia já entrega**, vistas
pelo inventário de `data-schema`. Não são catálogos novos: são as mesmas tabelas de
`segments`, `sub_segments`, `carriers`, `carrier_groups` e `project_guarantee_types`. Ficam
aqui para o ledger fechar pelos dois lados.

**`OPS-540` é o que muda de escopo.** Ele não é "o seed do S3": é o **arcabouço de seed de
referência** — idempotente, aplicado pelo deploy — que S5, S6, S8 e S17 plugam os seus
catálogos dentro. Sem dono, cada fatia inventaria o seu, e o deploy passaria a ter cinco
formas de semear.
