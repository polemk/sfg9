# Proposal: S19 — Trilha de auditoria e transversais de domínio e UI

> Fatia **S19** da ordem de execução de `.migration-ai9/migration-map.md`.
> Bloco de origem: `.migration-ai9/map/data-infra.md` — capability `misc-domain` (§2.7) e a
> parte de trilha de `data-schema` (§2.1, `DB-591`), mais `OPS-126` de
> `map/projects-cadastros.md`.
> Depende de **S0** (papéis, `authorize!`) e de **S18** (catálogo `pt-BR`, coerção).
>
> **Por que esta fatia existe:** a conferência consolidada do fim do Phase 2 encontrou
> **27 IDs transversais sem dono**. S13 apontava a trilha para "S2"; S2 conta 100 IDs,
> **todos do bloco `auth-admin`**, e nunca a reivindicou. É o mesmo modo de falha do C4: duas
> fatias apontando uma para a outra, e um subsistema inteiro caindo no vão.

## Why

Duas famílias que não têm nada em comum além de **serem usadas por todo mundo** — e é
exatamente isso que faz um dono ser necessário.

**1. A trilha de auditoria (`Tracking`) é o único registro de "o que aconteceu" do
Safegold.** É polimórfica em dois níveis (objeto **e** pai), tem autor obrigatório,
destinatário opcional, e é alimentada por um `TrackingFacade` com **20 emissores** de evento
de ciclo de vida de job, sempre em quarteto `request → start → progress → finish`. É o que
alimenta a timeline de atividade da tela. Três coisas estão erradas nela hoje:

- **`resume` é limitado a 300 caracteres e a gravação simplesmente falha** quando o resumo é
  maior: `save` retorna `false` e ninguém verifica. **O evento desaparece**, e o registro que
  some é justamente o do caso complicado — o que tinha muito o que descrever.
- **`TrackingFacade.track_new_project` não existe.** É chamado com três argumentos num
  ponto do fluxo de criação de projeto (`BE-434`) e levanta `NoMethodError`.
- **A coluna `type` é STI que nunca foi usada** (sempre `NULL`) e colide com o mecanismo de
  herança do Rails.

No ai9 não há equivalente: `backend/app/models/permission_audit_log.rb` é auditoria **ad
hoc** de um assunto só, e `paper_trail` está no Gemfile **sem uso** (achado **C-12**). E
`paper_trail` **não serve**: a semântica do legado (`kind = "JOB"`, `resume` em pt-BR,
`target`) é **evento de negócio**, não versionamento de registro.

**2. Os 15 helpers de view são regra de negócio disfarçada de formatação.** O maior deles,
`create_console_menu`, monta o menu lateral inteiro por papel e permissão — é a
maior regra de autorização de UI do legado, e é de **S2**. Os outros 14 são pequenos, e é por
isso que ninguém os reivindicou: `format_money`, `time_ago`, `gender_prefix`, `initials`,
`random_color`, `pluralize_for`… Um a um parecem triviais. Juntos, são o vocabulário visual
do produto — e três deles (`format_money`, `days_js_array`, `pluralize_for`) decidem,
respectivamente, **centavo exibido**, **data enviada ao servidor** e **texto que o usuário
lê**. Deixá-los sem dono significa cada fatia reimplementando o seu, e o produto exibindo
`R$ 1.234,56` numa tela e `1234.56` na outra.

## What Changes

**27 IDs.** A tabela item-a-item está em `.migration-ai9/map/data-infra.md` §2.7 e §2.1 —
aqui a estratégia e o alvo, sem duplicar as colunas do mapa.

### A. Trilha de auditoria — 11 IDs

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| DB-591 | build | Tabela `trackings` + `Tracking`. Polimorfismo duplo (`trackable` + `trackable_parent`) **preservado**; a coluna `type` (STI sempre `NULL`) é **descartada**. Campos estruturados — evento, entidade, payload `jsonb` — **além** do `resume`; índices em `[trackable_type, trackable_id]` e `[trackable_parent_type, trackable_parent_id]` |
| DB-430 | build | O mesmo esquema visto do lado da capability `misc-domain` |
| BE-430 | build | `Tracking` + `Sfg::TrackingService`: eventos **imutáveis**, ligados a objeto e pai, com autor **obrigatório** e destinatário opcional. **Resumo longo não perde o evento**: truncamento explícito, em vez de gravação que retorna `false` e ninguém verifica |
| BE-431 | build | Os 20 emissores do `TrackingFacade` viram eventos de ciclo de vida emitidos **pelos jobs** — o quarteto `request → start → progress → finish` é preservado como vocabulário |
| BE-432 | build | `GET /api/v1/trackings` — listagem filtrável: por `target_id`, por tipo de alvo, por autor, por período; filtros **combináveis** |
| BE-433 | build | `GET /api/v1/trackings/:id` — detalhe, com a distância geográfica calculada **apenas** quando `lat`/`lng` vierem na query |
| BE-434 | build | O método inexistente (`track_new_project`, chamado com 3 argumentos) passa a existir — ou a chamada some. Hoje é `NoMethodError` garantido no fluxo de criação de projeto |
| OPS-126 | build | A auditoria dos jobs de disponibilidade passa pelo mesmo serviço — **não** por um segundo caminho |
| FE-443 | build | `tracking_color` / `tracking_icon` viram **mapa tipo → cor/ícone**, dado e não `case` |
| FE-445 | build | Widget de item da trilha (timeline de atividade) |
| FE-446 | build | Payload JSON da trilha (entity) |

### B. Helpers de formatação e apresentação — 13 IDs

Todos viram **utilitário único**, do lado certo da fronteira. O legado os tinha como helpers
de view Ruby; no ai9 a maior parte é do cliente.

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| FE-430 | adapt | `time_ago` — tempo relativo em pt-BR, **um** utilitário |
| FE-431 | build | `format_money` — moeda brasileira. Lê os mesmos casos golden de `Sfg::Coercion` (S18): **formatação e gravação não podem divergir** |
| FE-432 | adapt | `gender_prefix` — concordância de gênero deixa de ser função e vira **catálogo de mensagens** (S18) |
| FE-433 | reuse | `initials` — o `Avatar` do design system já faz |
| FE-434 | build | `chop_middle_words` — nome curto |
| FE-435 | build | `random_color` — cor de identificação **determinística** (mesma entrada, mesma cor), não aleatória. A gem `color-generator` some |
| FE-436 | adapt | `month_array` — 12 meses localizados, do catálogo |
| FE-437 | build | `ten_years_array` — janela de anos |
| FE-438 | adapt | `pluralize_for` — plural simplificado vira **formas plurais no catálogo** |
| FE-439 | build | `slice_in` — distribuição em N colunas: utilitário ou componente, não helper de string |
| FE-440 | build | `days_js_array` — o contrato de troca de datas passa a ser **ISO-8601** em toda a fronteira. Hoje o legado monta array de datas em formato próprio para o datepicker |
| FE-442 | adapt | `week_days` — dia da semana em pt-BR, do catálogo |
| FE-444 | build | `public_create_user?` — flag de auto-cadastro público. **Nasce `false`**: é a trava do **D-39**, que volta sozinho se as rotas públicas do ai9 ficarem abertas |

### C. Utilitários de servidor compartilhados — 3 IDs

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| BE-449 | build | Ordenação multi-coluna dirigida pelo cliente — o legado recebe **arrays paralelos** de chaves e estilos. Vira **um** utilitário compartilhado, com allowlist de colunas (array paralelo vindo do cliente e interpolado é injeção de SQL esperando acontecer) |
| BE-455 | build | `IntervalValidator` — coerência de faixa mín/máx: inteiro, e mínimo não maior que máximo |
| BE-456 | build | `UriValidator` — formato `http(s)`. **A verificação de disponibilidade sai**: o legado faz uma requisição HTTP dentro da validação do model, o que transforma salvar um registro em chamada de rede com timeout desconhecido |

## Mudanças visíveis, decididas e registradas

Para `improvements-log.md`:

1. **Eventos de trilha deixam de sumir.** Resumo longo é truncado explicitamente, não
   descartado.
2. **A trilha ganha campos estruturados** (evento, entidade, payload) além do texto em pt-BR
   — passa a ser filtrável de verdade.
3. **`random_color` vira determinística.** No legado a cor de identificação de um mesmo item
   mudava a cada renderização.
4. **Validar URL deixa de fazer requisição de rede.**
5. **Datas trafegam em ISO-8601** em toda a fronteira.

## Descartes com evidência

| ID | Motivo registrado |
| -- | ----------------- |
| `Tracking#type` | Coluna STI **sempre `NULL`** em todo o legado, e colide com o mecanismo de herança do Rails. Não vira coluna; a evidência é a contagem de distintos na origem, registrada pelo dry-run de S14 |
| `paper_trail` | Está no Gemfile do ai9 **sem nenhum uso** (**C-12**) e **não** é adotada: a semântica do legado é evento de negócio, não versionamento de registro. Vira flag de upstream, não dependência |
| `color-generator` | Gem substituída por hash determinístico; a saída aleatória do legado não é comportamento a preservar |
| `UriValidator` (parte) | A verificação de disponibilidade por HTTP dentro do `validate` não é portada — evidência: é chamada de rede sem timeout dentro da transação de gravação |

**Nenhum ID desta fatia sai do ledger como `dropped` por omissão.**

## Fronteiras — dono único de cada ID (contrato C4)

- **O menu do console é de S2.** `FE-441` (`create_console_menu`, a maior regra de
  autorização de UI do legado) e `FE-050` (as entradas das 6 entidades) têm dono em **S2**,
  que é dona de `useNavItems.ts`. S19 **não** toca no menu.
- **`MovementKind` é de S6.** As três regras de negócio dele (chave de integração derivada do
  título, exclusividade de tipo de taxa, dependências protegidas) e a tabela são de S6. O que
  fica aqui é **só** o utilitário de ordenação multi-coluna (`BE-449`), porque é compartilhado
  e S6 é apenas o primeiro consumidor.
- **`Entry` (classe base dos lançamentos) é de S6.** `BE-445` foi avaliado para cá por ser
  transversal — `AvailabilityEntry` (S11) herda dele — e **fica em S6** pelo contrato C4:
  quem constrói é dono, e `ReceivableEntry` nasce em S6, antes de S11. S11 **consome**.
- **O mecanismo de coerção é de S18.** `Sfg::Coercion` e o catálogo `pt-BR` (`OPS-629`)
  nascem lá; `FE-431`, `FE-432`, `FE-436`, `FE-438` e `FE-442` são as **chamadas** e os
  **verbetes**, e vivem aqui.
- **A fila e o progresso de job são de S13.** `OPS-125` (infraestrutura de fila) e `OPS-127`
  (progresso ao vivo) são de lá; `OPS-126` fica aqui porque é a **auditoria** do módulo, e
  auditoria é este serviço.
- **As bases de endpoint são de S18** (`BE-458`, `BE-459`).
- **O gate de auto-cadastro público:** `FE-444` é a flag; as rotas públicas do ai9
  (`pre_register`, `complete_registration`, `visitor_signup*` em `api/root.rb:35-46`) são de
  **S1**, que decide se saem da allowlist. As duas pontas são necessárias — a flag sozinha
  não impede o **D-39** se a rota continuar aberta.

## Dependências

- **S0** — papéis e `authorize!` (a trilha filtra por autor e alvo, e nem todo papel vê tudo).
- **S18** — catálogo `pt-BR` e `Sfg::Coercion`.
- **É dependência de S13** — os jobs emitem eventos de ciclo de vida por este serviço; se
  S13 rodar antes, cria o **mínimo** (tabela + `Sfg::TrackingService`) e S19 constrói a
  leitura em cima. Registrado assim porque já estava escrito na Fronteiras de S13.
- **É dependência de S11** — `OPS-126`.

## Perguntas em aberto (defaults declarados em `map/data-infra.md` §6)

| # | Pergunta | Default |
| - | -------- | ------- |
| **Q-21** | A trilha é visível a todo papel, ou só a og/admin? | **Só og/admin** para a trilha global; o histórico **do próprio objeto** é visível a quem vê o objeto. Trilha aberta a todos é um índice de tudo que aconteceu no sistema |
| **Q-22** | A distância geográfica de `BE-433` tem consumidor? | **Porto o cálculo condicional** (só quando `lat`/`lng` vierem), sem geocoding — que está bloqueado por Q-04 em S13 |
| **Q-23** | `Tracking` guarda payload completo do objeto? | **Não.** Guarda evento, entidade, autor e um payload `jsonb` **enxuto**. Trilha que copia o registro inteiro vira o maior objeto do banco em três meses |

## Capabilities

### New Capabilities

- `audit-trail`: a trilha de auditoria do produto — eventos imutáveis, com autor obrigatório
  e alvo polimórfico. **Uma** requirement genuinamente nova: **evento nunca se perde e nunca
  é editado**, que não existe no legado (onde `resume` longo faz o `save` retornar `false` em
  silêncio) nem na base ai9 (que tem auditoria ad hoc de um assunto só).

### Modified Capabilities

Nenhuma. Os requirements de paridade dos 27 IDs já existem em `openspec/specs/` e são
**referenciados por ID**, não recriados.

## Impact

- **Backend:** migration `create_trackings`, `app/models/tracking.rb`,
  `app/services/sfg/tracking_service.rb`, `api/v1/trackings.rb`,
  `api/entities/tracking.rb`, `app/validators/{interval,uri}_validator.rb`,
  `app/lib/sfg/sortable.rb`.
- **Frontend:** `components/ActivityTimeline/**`, `lib/format/**` (moeda, data relativa,
  iniciais, cor determinística), contrato ISO-8601 na camada de API.
- **Paridade:** 27 IDs de inventário que **não tinham dono** passam a ter.
