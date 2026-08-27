# Design: S3 — Cadastros globais em ai9

> **Este documento não duplica o mapa.** As 51 linhas item-a-item, com "Equivalente ai9",
> "O que muda", risco e dependência, estão em `.migration-ai9/map/projects-cadastros.md`,
> seções **§2.1** (BE-067..078), **§2.2** (FE-060..078), **§2.3** (DB-057..066, DB-072),
> **§2.4** (OPS-051..058) e **§2.7** (BE-700..706).
> Aqui está só a **decisão de desenho da fatia** — o que vale para os cinco cadastros juntos.

## 1. A forma única dos cinco cadastros

Os cinco recursos são o **mesmo objeto** com colunas diferentes: lista paginada e ordenável,
busca por texto, painel lateral de criação/edição, exclusão bloqueável, detalhe. Escrever
cinco desenhos diferentes é a forma mais rápida de terminar com cinco semânticas de
paginação. **Um molde, cinco instâncias.**

### Backend — o molde

Herdado sem exceção (`§0.4` do mapa): `GRAPE` (`api/v1/base.rb`) + `CH`
(`controller_helpers.rb`: `process_service_response`, `set_pagination_headers`,
`authenticate_user!`) + `ARH` (`services/concerns/api_response_handler.rb`) + `ENT`
(`api/entities/`) + `KAM` (Kaminari; o CORS já expõe `X-Total-Count`).

```
api/v1/<recurso>.rb          # namespace Grape, desc/params/http_codes
app/services/<recurso>_service.rb   # regra; devolve success_response/error_response
app/controllers/api/entities/<recurso>.rb
app/models/<recurso>.rb      # validações + scope :search + scope :ordered
```

**Paginação é `reuse` no servidor e `build` no cliente.** Kaminari + `set_pagination_headers`
cobrem 100% do lado backend dos ~6 `search` desta fatia. No front, `MobilePagination` só tem
anterior/próxima e usa cor literal em vez de token de tema — generalizá-lo seria editar
componente da base (Princípio 6b). Por isso o controle de desktop é o `Pagination` novo,
entregue pela **S0**, e `MobilePagination` fica **intocado**.

### Frontend — o molde

Herdado sem exceção (`§0.3`): `ProtectedRoute` + `Layout` + `PageHeader` + `components/ui/`
+ tokens de tema (light **e** dark, marca Safegold) + React Query + `useNavItems` +
`components/mobile/` nas views estreitas.

Da **S0** vêm `DataTable` (FE-061), `Pagination` (FE-053), `useDebouncedSearch` (FE-052),
`MoneyInput`/`PercentInput` (FE-066) e `EmptyState`/`ErrorState`/`LoadingState` (FE-079).
**Esta fatia é a primeira consumidora dos cinco.** Se algum não servir, o conserto é na S0 —
nunca uma cópia local (Princípio 11).

O painel de criação/edição é o `SideDrawer` da base
(`frontend/src/components/SideDrawer.tsx`, props `open/onClose/title/children/footer`), o
mesmo nos cinco cadastros. `SearchableSelect` da base serve aqui porque as listas são
pequenas (grupos, UFs, agentes financeiros) — o `AsyncSearchableSelect` da S0 só é
necessário na S4.

## 2. O contrato C1 nesta fatia: catálogo global **não** recebe escopo

Esta é a decisão de desenho mais importante da S3, e é a mais fácil de errar na direção
oposta das outras fatias.

**Regra 4 de `§0.6`:** `carriers`, `carrier_groups`, `segments`, `sub_segments` e
`project_guarantee_types` são **catálogo global**. Não têm `project_id`, não incluem
`ProjectScoped`, e **nenhum endpoint desta fatia chama `current_project!`**.

> **A regra em uma frase, copiada do mapa: o menu esconde a tela de administração do
> catálogo, não o dado do catálogo.**

O que substitui o escopo, então:

1. **Leitura**: qualquer autenticado, inclusive Colaborador (DEC-18.4). Nunca anônimo —
   é o D-23, e é o defeito que o BE-700 fecha.
2. **Escrita**: `require_role!(:og, :admin, :gerente)` **no endpoint**, mais
   `require_not_readonly!`. Ambos vêm da S0 e estendem o `require_og!` /
   `restrict_visitor_access!` que já existem em `controller_helpers.rb:41-56`.
   `restrict_visitor_access!` já é **exatamente** a forma do `user_is_readonly` do legado —
   é o gancho, não um mecanismo paralelo.
3. **O que o cliente manda de `user_id` é ignorado.** `user_id` vem da sessão (BE-076,
   BE-703). No legado o `SegmentsController` tinha `user_id` **fora** do `permit` e a criação
   falhava sempre (D-21); o `ProjectGuaranteeTypesController`, ao contrário dos demais,
   **não** sobrescrevia o `user_id` do corpo (D-23). As duas pontas se resolvem com a mesma
   regra.

**Por que isto precisa estar escrito:** nas fatias S4 e S11 a leitura correta é
`Model.for_project(current_project!)`. Um implementador que venha da S4 para a S3 tende a
"consertar" o catálogo aplicando escopo — e aí um portador cadastrado no projeto A some da
tela do projeto B, quebrando o `risk_control` que já aponta para ele. O inverso também é
verdade: quem vier da S3 para a S4 tende a esquecer o `current_project!`. **São regras
opostas de propósito, e cada endpoint declara a sua em uma linha visível.**

## 3. Decisões por grupo de IDs

### 3.1 Portador — é contraparte financiadora, não "fornecedor genérico"
`§2.1 BE-067..071` · `§2.2 FE-060..068` · `§2.3 DB-057..062`

- **`bank_code` é string** (DC-12). O legado guardava `integer` e `001` virou `1`. O ETL
  reconstitui os zeros pelo comprimento 3 do código COMPE e **reporta** o que não conseguir.
  Replicar o inteiro seria replicar corrupção de dado.
- **`financial_agent` é enum string fechado** (FIDC / Securitizadora / Factoring / Cliente),
  sintaxe Rails 8. Valor divergente é reportado no dry-run, nunca inserido calado.
- **`subordinated_accounts_percent` passa a ser derivado no servidor** (DC-09), a partir de
  `senior_accounts`/`subordinated_accounts`, com o campo somente leitura na tela. No legado
  era calculado em JS a cada tecla **e** persistido como coluna editável — duas fontes de
  verdade para o mesmo número.
- **Título duplicado continua permitido** (BE-071). Isto **não** é bug: a base tem
  `Cloud #7036` e derivados legítimos. Só `title` é obrigatório. Está aqui porque um
  implementador zeloso adicionaria a unicidade sem perguntar.
- **Exclusão bloqueia, nunca cascateia** (BE-070, D-24). O legado apagava os `risk_controls`
  do portador junto. `dependent:` é explícito em toda associação, e para `risk_controls`,
  conexões e recebíveis é `:restrict_with_error`.
- **Logo por ActiveStorage** (`has_one_attached`), com `active_storage_validations` +
  `image_processing`, seguindo a receita viva de `backend/app/models/medium.rb`
  (`optimized_url`/`small_url`, `variant(resize_to_limit:, format: :webp)`, fallback no
  `rescue`). **Não** por `Medium` (DC-02/Q-05: `media` não tem dono nem escopo — um logo
  criado por lá aparece na galeria `/media` para qualquer autenticado). **Nunca** por
  `assets_proxy_controller.rb`, que não autentica nada (é achado de base compartilhada,
  registrado em `upstream-flags.md`, não refatorado aqui).

### 3.2 Grupo de portadores — a contagem decide o botão
`§2.1 BE-072..074` · `§2.2 FE-075..076` · `§2.3 DB-063`

`carriers_count` vira `counter_cache` do ActiveRecord com default `0` (OPS-058). No legado a
contagem divergia da lista e era ela que decidia se o botão de exclusão aparecia — o botão
some, mas a exclusão ainda passa. Agora o critério do botão **é** o critério do servidor: o
grupo com portadores responde 422 (BE-073), e o front reflete a resposta real.

### 3.3 Segmento e subsegmento — dois catálogos independentes
`§2.1 BE-075..078` · `§2.2 FE-077..078` · `§2.3 DB-064..066`

**DC-13: `sub_segments` não ganha FK para `segments`.** Apesar do nome, o legado não tem
associação nenhuma entre os dois, e criar a hierarquia agora exigiria **inventar** o
mapeamento para os dados existentes. Fica registrado como candidato a feature futura.

`segments.title` passa a ser único **no banco** (DB-064), fechando o caminho do D-26
(`segment_id = 1` codificado no reset de projeto — corrigido na S4, BE-092).

### 3.4 Tipos de garantia — o catálogo que respondia para anônimo
`§2.7 BE-700..706` · `§2.2 FE-116..117` · `§2.9 DB-084`

Único catálogo desta fatia com defeito de **autorização**, não de usabilidade: o legado
declarava `requires_current_user? == false`. No ai9 o endpoint nasce dentro do
`api/v1/base.rb`, que já roda `before { restrict_visitor_access! }` e exige sessão — **401
sem credencial é o comportamento padrão da base**, não um mecanismo novo.

**DC-22 — a chave de integração é congelada na criação e só muda por edição explícita.** No
legado era derivada do título só na criação, e título e chave divergiam depois da primeira
edição. É chave de **integração**: recalculá-la em silêncio quebra consumidor externo.

### 3.5 Busca — `ILIKE` com bind, nunca interpolação
`§2.4 OPS-056`

`scope :search` em cada model, com `where("title ILIKE ?", "%#{q}%")` **por bind**. O legado
usava `Dev.ilike` interpolando o operador conforme o adapter, o que fazia `100%` e `a'b`
serem tratados como padrão SQL em vez de texto literal. O alvo é Postgres (DEC-05), então
`ILIKE` é literal no código.

`§2.1 BE-067` acrescenta a **simetria da busca**: o mesmo termo devolve o mesmo conjunto com
e sem ordenação. No legado o ramo ordenado e o não-ordenado montavam consultas diferentes.

### 3.6 UF — cadastro, não geocodificação
`§2.4 OPS-057` · Lacuna **L-11**

`api/v1/br_states.rb` com uma constante `UF`, no mesmo padrão de `api/v1/countries.rb`
(constante `COUNTRIES` no próprio arquivo). **`geocoder` e `city-state` não são portados** —
no legado o geocoder rodava com timeout de ~3h20 e sem cache, e cidade/UF são dado de
cadastro, não resultado de geocodificação.

### 3.7 Seeds — catálogo separado de demonstração
`§2.4 OPS-054`

`db/seeds/catalogos.rb` (os cinco catálogos, idempotente, roda em qualquer ambiente) ×
`db/seeds/demo.rb` (dado de vitrine). O legado misturava os dois, a ponto de o bloco de
empresas estar marcado **no próprio código** como "seed feito somente para vídeo de
aprovação". Ver `.migration-ai9/demo-seed-design.md`.

## 4. Onde esta fatia toca outras

| Fronteira | Como fica |
| --------- | --------- |
| **S0** | Consome `require_role!`, `require_not_readonly!`, `DataTable`, `Pagination`, `useDebouncedSearch`, `EmptyState`/`ErrorState`. Se algum atrasar, a tarefa correspondente **para**; não se faz cópia local |
| **bloco `risk`** | BE-070 só bloqueia por `risk_controls` quando a tabela existir (S5). Até lá o bloqueio cobre conexões e recebíveis, e a tarefa 5.7 fica como teste pendente marcado |
| **S4** | `projects.segment_id`/`.sub_segment_id` (DB-067) e `project_guarantees.guarantee_type_id` (DB-083) são criados **lá**, apontando para as tabelas criadas **aqui** |
| **bloco `receivables` (SR-1)** | `wallets`, `receivable_kinds` e `movement_kinds` são catálogos globais irmãos, com o mesmo molde. **Quem implementar SR-1 deve reusar o molde desta fatia**, não inventar outro |
| **S14 (ETL)** | DB-061/DB-065 (`legacy_id`) e DC-12 (`bank_code`) são o contrato de proveniência que o ETL consome. O pipeline `Legacy::execute` do legado **não** é portado (DEC-12) |

## 5. Riscos assumidos

| Risco | Mitigação |
| ----- | --------- |
| **Mudança visível**: paginação real (BE-067, BE-072, BE-075) — hoje as telas trazem tudo | Registrado em `improvements-log.md` como intencional, para o QA do Phase 4 não ler como regressão |
| **ETL de `bank_code`** precisa reconstituir zeros à esquerda | Reconstituição por comprimento 3 do COMPE + relatório do que não converter. O que não converter **não** é inserido calado |
| **BE-070 replicado errado** volta a cascatear e apaga limite de risco | Teste explícito nas duas direções (tarefa 5.7), e `dependent: :restrict_with_error` no model, não só a checagem no serviço |
| **FE-067 (logo do portador)** depende de **Q-04** | Default declarado: ligar. A infra do DC-02 já cobre; é 1 campo |
