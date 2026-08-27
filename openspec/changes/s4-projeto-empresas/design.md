# Design: S4 — Projeto e empresas em ai9

> **Este documento não duplica o mapa.** As 123 linhas item-a-item estão em
> `.migration-ai9/map/projects-cadastros.md`, seções **§2.1** (BE-050..066), **§2.2**
> (FE-051..074), **§2.3** (DB-050..056, DB-067..071), **§2.4** (OPS-050, OPS-055),
> **§2.5** (BE-080..101), **§2.6** (BE-102..109, BE-118, BE-119), **§2.8** (FE-080..119),
> **§2.9** (DB-080..092) e **§2.10** (OPS-080, OPS-085, OPS-088, OPS-089).
> As decisões de comportamento estão em **§3** (DC-01..DC-24) e as lacunas em **§4**
> (L-01..L-12). Aqui está só a **decisão de desenho da fatia**.

## 1. O contrato C1 — escopo por projeto **no endpoint**, nunca `default_scope`

Esta é a razão de a fatia existir, e o desenho normativo é o **§0.6** do mapa, que vale para
os quatro blocos da migração. Repetido aqui só o que muda o código desta fatia.

### As quatro peças

| # | Peça | Onde | Papel |
| - | ---- | ---- | ----- |
| 1 | `memberships` (`user_id`, `project_id`, `role`, único `(user_id, project_id)`) | DB-086 | A verdade sobre quem enxerga o quê. **`role` é rótulo descritivo, nunca consultado para autorizar** (DEC-18.6) |
| 2 | `users.current_project_id` (FK + índice) | DB-087 | O projeto corrente, resolvido **no servidor** |
| 3 | `current_project!` em `api/v1/controller_helpers.rb` | S0 / BE-098 | Resolve e **revalida contra membership a cada request** |
| 4 | Concern `ProjectScoped` em `app/models/concerns/` (hoje **vazio**) | S0 | `belongs_to :project` + `scope :for_project` + validação de presença |

### A forma canônica — copie esta, não invente outra

```ruby
# 1. o endpoint declara o escopo — uma linha, sempre visível
project = current_project!            # 403/404 se não houver membership
scope   = Company.for_project(project)

# 2. TODO filtro por id do cliente é aplicado DENTRO do escopo, nunca fora
scope = scope.where(id: params[:company_id]) if params[:company_id]

# 3. o project_id que vem do corpo da requisição é SEMPRE ignorado
```

### Por que **não** `default_scope`

Ele vaza para `unscoped`, quebra `joins`/`includes` em silêncio, contamina jobs e seeds que
**legitimamente** cruzam projetos (OPS-081, OPS-085, OPS-121 replicam padrões em **todos** os
projetos) e — o pior — torna o escopo **invisível na leitura do código**. O legado errou
exatamente por o escopo ser implícito.

**A prova, medida na fonte** (`/home/vinao/workspace/sfg`,
`app/controllers/pub/project_guarantees_controller.rb:21-22`):

```ruby
@project_guarantees = ProjectGuarantee.joins(:carrier).joins(:guarantee_type)
                                      .where(project_id: current_user.default_project_id)
@project_guarantees = ProjectGuarantee.where(id: params[:project_guarantee_id]) unless params[:project_guarantee_id].nil?
```

A segunda linha **reatribui** a relação inteira. O filtro de projeto simplesmente
desaparece. É a família **D-01 / D-16 / D-29 / D-76 / D-100**, e é por isso que **toda
tarefa de endpoint desta fatia que aceita id por parâmetro leva um teste de que um id de
OUTRO projeto é rejeitado** — o caminho feliz passa com o código errado.

### As cinco regras que valem para os quatro blocos

1. **`project_id` do cliente é sempre ignorado**, no `create` **e** no `update`. O legado
   forçava no create e esquecia no update (BE-062, D-23).
2. **Filtro por id nunca sobrepõe o escopo.** Resultado esperado quando o id é de outro
   projeto: **vazio**, não 403 — não se confirma a existência de registro alheio.
3. **`:id` fora do `permit`** em todo recurso (família D-60/D-68; DEC-15.2 exige para membership).
4. **Catálogo global não recebe escopo** — é a regra da S3, oposta a esta, e de propósito.
5. **Job, seed e rake não usam `current_project!`** — recebem `project_id` como argumento
   explícito. É por isso que o escopo não pode ser `default_scope`.

### As duas condições que o bloco de auth acrescentou, e que ficam valendo

- O valor de `current_project_id` é **revalidado a cada request** — senão membership
  revogada continua valendo.
- **Projeto inexistente e projeto sem membership respondem o mesmo status.** Distinguir 403
  de 404 vira oráculo de existência de id.

### Onde o projeto corrente mora (DC-03)

Fonte de verdade = **`users.current_project_id`**, no banco, com FK e índice. O header
`X-Project-Id` é aceito **só** se houver membership — é o suporte a duas abas, não uma
segunda fonte de verdade. **Nunca cookie** (era o D-28: no legado trocar o cookie trocava de
tenant) e **nunca campo escondido de formulário**.

No front (FE-106), a resolução vem da sessão, no padrão de `tokenStore.ts` (access token só
em memória). O legado apagava o cookie e forçava a **segunda** opção do select, sem
justificativa no código.

## 2. Decisões de desenho por grupo de IDs

### 2.1 Projeto — o agregado central
`§2.5 BE-080..101` · `§2.8 FE-080..099` · `§2.9 DB-080..091`

- **`responsible_id` vira referência de usuário de verdade** (DB-080). Era `string`.
- **Slug imutável após a criação** (DC-17). `set_smart_id` rodava em todo
  `before_validation` no legado: renomear o projeto mudava o slug e as URLs baseadas nele.
  O padrão `smart_id`/`by_any_id` está documentado em `ai9-conventions.md §4` mas **não tem
  implementação viva** na base (0 ocorrências em `backend/app` — os models que o tinham
  saíram no trim). É a **Lacuna L-09**: a implementação nasce aqui, no padrão documentado.
- **Criar projeto com responsável novo** (BE-085) cria projeto + usuário e **envia link para
  a pessoa definir a própria credencial**, em transação atômica, reusando `Auth::` do bloco
  de auth. O legado montava **username e senha em texto plano** para a view (D-38).
  Nenhuma senha é montada, exibida ou enviada.
- **DC-14 — o criador não perde a posse.** Ao indicar um responsável existente, a posse
  (`project.user_id`) vai para o responsável, mas **o criador permanece com membership
  explícita**. No legado ele ficava de fora do próprio projeto.
- **Observação em ActionText** (BE-097, DB-088) — **`reuse` de ponta a ponta, zero
  migration**. O caminho `biography` do `User` já existe e é copiado linha a linha:
  `user.rb:18` (`has_rich_text`) → `api/v1/users.rb:190` (param) →
  `api/entities/user.rb:33-49` (`*_html` = `body.to_s`, `*_text` = `to_plain_text`). A tabela
  `action_text_rich_texts` já está no `schema.rb`. No front, `RichTextEditor` (Slate) fala
  **HTML nos dois sentidos** (`serializeToHTML:75` / `deserializeHTML:102`) e casa exatamente
  com o `*_html` — FE-099 é `reuse` puro, **nenhum componente novo**.
  O **único** trabalho novo é **bloquear anexo no servidor**: o ActionText os aceita por
  padrão e o legado bloqueava só no cliente (`trix-file-accept` + botão escondido).
- **Logo por ActiveStorage** (DB-089, OPS-088) na receita de `medium.rb#optimized_url`
  (`variant(resize_to_limit:, format: :webp)` + fallback no `rescue`). **Não** por `Medium`
  (Q-05: `media` não tem dono nem escopo) e **nunca** por `assets_proxy_controller.rb`, que
  não autentica nada. Ausência de logo passa a ser explícita — o legado tratava a string
  literal `"missing.jpg"` como ausência.
- **Reset do projeto de treinamento** (BE-092): o segmento é resolvido **por configuração**,
  nunca por id fixo. O legado tinha `segment_id = 1` codificado (D-26).
- **DC-19 — rotas mortas não são portadas**, com evidência: `config/routes.rb:75` aponta
  para controller inexistente (`project_to_availability_connections`) e as views
  `projects/detail/connection_template/**` chamam helpers inexistentes (BE-101).

### 2.2 Membership — a peça que nasce aqui (contrato C4)
`§2.5 BE-099` · `§2.9 DB-086`

Dois blocos reivindicaram `Membership`; **vale este desenho** e o de `auth-admin` aponta
para cá. O risco nunca foi construir duas vezes — era os dois blocos apontarem um para o
outro.

**As três condições da view viram regra de servidor** (DEC-15.2 / DEC-18.5): não-readonly,
**não remove o dono** (`project.user_id`), **não remove a si mesmo**. `:id` fora do `permit`.
Criar e remover: OG/Admin/Gerente. Fecha **D-28 + D-34** — hoje qualquer sessão se
auto-adiciona a qualquer projeto e **ganha o grupo "Gestão" inteiro**.

**`role` é enum estável** (responsavel / participante / coordenador / gestor) e **rótulo
descritivo — nunca consultado para autorizar** (DEC-18.6). Quem autoriza é `UserType` +
`require_role!`. Remoção deixa de ser `delete_all` sem callbacks.

### 2.3 Empresas e fornecedores — o primeiro consumidor do escopo
`§2.1 BE-050..066` · `§2.2 FE-051..074` · `§2.3 DB-050..056, DB-067..071`

- **`companies.title` único por projeto**, por **índice composto** `(project_id, title)`
  (DB-050) — fecha a corrida que a unicidade só-de-aplicação deixava aberta.
- **DC-04 — mover empresa entre projetos não é caso de uso.** `project_id` é ignorado no
  update: mover a empresa arrastaria `risk_controls`, recebíveis e renegociações para outro
  tenant.
- **DC-11 — documento é o par `(document_type, document)` e continua opcional.** A regra
  "ao menos um" está **comentada** no model legado, e a base quase certamente tem
  fornecedores sem documento.
- **`cnaes` e `atividades` em UM `jsonb`** (DB-055, D-25). O legado guardava YAML e JSON na
  mesma tabela. A leitura do YAML legado no ETL usa carga **segura** (classes permitidas).
- **ReceitaWS (BE-064, OPS-050) é `adapt` sobre `Credential`** — o token sai de
  `ENV['rws_api_token']` (que estava **commitado** no legado) e vai para
  `app/models/credential.rb`, com timeout, cache e rate-limit. CNPJ validado no servidor
  antes de chamar o provedor; resposta normalizada, não crua. **Depende de Q-03.**
- **DC-05, DC-06, DC-07 — três coisas do legado que não são portadas**, cada uma com
  evidência: os filtros `kind`/`state` (os selects não existem no HTML e o backend os
  ignora), a aba "Controles de Risco" (parcial vazio, não listada, sem action) e as "relações
  de fornecedor" (handler aponta para seletor inexistente).

### 2.4 Conexões — sem `constantize` de parâmetro, sem N+1
`§2.6 BE-102..109` · `§2.8 FE-100..104` · `§2.9 DB-081, DB-082, DB-092`

O tipo de entidade vem de **conjunto fechado**, nunca de `constantize` sobre parâmetro do
cliente — o legado permitia enumerar classes da aplicação. O estado "conectado" é resolvido
em **uma consulta**, não em `o.carriers.include?(t)` por linha.

Lote: vazio → 400, resultado **por item**, desconectar o que não está conectado não dá 500.
O legado tinha a condição invertida (`unless errors.blank?`) e só avaliava o último item.

`project_to_carrier_connections` é a **única ponte** (DB-068): os portadores da empresa são
**derivados do projeto**. Nenhuma tabela empresa↔portador é inventada.

`indicators.scope` passa a ser explícito (DB-092) — hoje `project_id IS NULL` governa a
interface inteira. Indicador **global** não é excluível pela rota do projeto: 422, não 500.

### 2.5 Garantias do projeto
`§2.6 BE-118, BE-119` · `§2.8 FE-113..115` · `§2.9 DB-083`

`project_guarantee_id` **não fura** o escopo (é o exemplo literal do D-29, citado na §1
deste documento). Ordenar por "Título" funciona — o legado ordenava por
`risk_operations.title`, tabela fora do join, e o SQL falhava (D-32).

`observation` vira `text` (era `string(255)` com `textarea` na tela — risco de truncamento) e
`value` vira `decimal(14,2)`. Só portadores **conectados ao projeto** são oferecidos, com
**um único critério** de "o projeto tem portador" (o legado usava
`active_risk_controls_carriers` no botão e `project.carriers` no formulário — dois critérios).

### 2.6 Jobs e progresso — Action Cable, nunca polling
`§2.10 OPS-080, OPS-085` · `§2.8 FE-083`

Princípio 10: **polling é proibido**. Progresso de criação de projeto chega por
`ProjectProgressChannel` invalidando query (`useCable`/`useChannel` já existem em
`frontend/src/hooks/useCable.ts`); o canal e o `useJobProgress` vêm da **S0** (Lacuna L-08).
Fecha **D-86** — no legado não havia nem polling nem push: só recarregando a lista à mão.

Sidekiq entrega **retry por default** e as filas (inclusive `_low_priority`) já estão em
`config/sidekiq.yml`. Fecha **D-05**: no legado `destroy_failed_jobs? false` e o job falho
sumia da fila. `LinkDefaultUserToProjectsJob` (OPS-085) passa a **registrar** o erro — o
`rescue` do legado era vazio.

`ProjectCreationJob` e `SeedGlobalTemplatesJob` têm **progresso próprio** (BE-088). No legado
as duas tarefas escreviam no mesmo `job_id` e se atropelavam.

### 2.7 Componentes de frontend que esta fatia consome da S0

| Lacuna | Componente | Por que a base não serve |
| ------ | ---------- | ------------------------ |
| **L-01** | `DataTable` | `components/ui/Table.tsx` é só o primitivo shadcn; não há tabela com ordenação por cabeçalho |
| **L-01** | `Pagination` | `MobilePagination` só tem anterior/próxima, sem primeiro/último nem limite por página, e usa cor literal em vez de token — generalizá-lo seria editar a base (Princípio 6b) |
| **L-02** | `AsyncSearchableSelect` | `SearchableSelect.tsx` filtra **client-side** sobre `options` já carregadas (linhas 41-44). Serve para listas pequenas; **não serve** para a base de usuários (FE-086, FE-096) |
| **L-03** | `MoneyInput` / `PercentInput` | Não há input monetário nem lib de máscara no `package.json` |
| **L-07** | `EmptyState` / `ErrorState` / `LoadingState` | Cada página da base implementa o seu |
| **L-08** | `useJobProgress` + `JobProgressChannel` | `useCable`/`useChannel` existem, mas não há canal de progresso |

**Se algum não servir, o conserto é na S0** — nunca uma cópia local (Princípio 11).

## 3. O que fica pendente de outros blocos

| Pendência | Quem entrega | Efeito nesta fatia |
| --------- | ------------ | ------------------ |
| `risk_controls` | bloco `risk` (S5) | BE-052 (resumo de limites) e as contagens de "controles de risco" nas telas de Empresa e Portador; DB-069 (FK simétrica) |
| catálogo de `indicators` | bloco `indicators` (S10) | BE-106..109, DB-092 |
| `renegotiations` | bloco `renegotiations` (S9) | checagem de dependentes em BE-063, FK em DB-071 |
| `receivable_entries` | bloco `receivables` (S6) | FK em DB-070 |

**Desenho aplicado:** as FKs de DB-069/DB-070/DB-071 são declaradas na migration **do bloco
que cria a tabela**, não aqui — aqui fica registrado o **contrato** (bloquear, nunca
cascatear) e o teste que o verifica quando a tabela existir. A alternativa (migration
condicional) esconde a dependência.

## 4. Riscos assumidos

| Risco | Mitigação |
| ----- | --------- |
| **`current_project!` implementado errado** vaza tenant no sistema inteiro | Uma única implementação, em `controller_helpers.rb`; teste de escopo cruzado em **cada** endpoint com id por parâmetro (seção 5 do `tasks.md`); revalidação de membership a cada request |
| **Distinguir 403 de 404** vira oráculo de existência de id alheio | Projeto inexistente e projeto sem membership respondem **o mesmo status** — teste explícito |
| **BE-085** montava senha em texto plano no legado; um port literal reintroduz o D-38 | Nenhuma senha é montada; link de definição de credencial pelo fluxo `Auth::` do bloco de auth. Teste que verifica que a resposta e o e-mail **não contêm** credencial |
| **Mudança visível**: paginação real em 4 listas | Registrada em `improvements-log.md` como intencional |
| **DC-01 (Q-02)** muda o significado de relatório em 6 tabelas | Não implementar a marca de gestão nas tabelas filhas antes da resposta; a coluna do `projects` (BE-093) pode ir na frente |
| **`AsyncSearchableSelect` atrasar na S0** trava FE-086 e FE-096 | Não se faz cópia local; a tarefa fica bloqueada e visível na fila |
