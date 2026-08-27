# Tasks: S19 — Trilha de auditoria e transversais

> **⚠ ESTE ARQUIVO FOI ESCRITO ANTES DAS DECISÕES. A DEC VENCE.**
>
> O `tasks.md` original supunha uma trilha própria (`trackings` + `Tracking` +
> `Sfg::TrackingService`) e dizia, como portão da fatia, que **"`paper_trail` não
> é adotada"**. A **DEC-59** decidiu o contrário: **a trilha de auditoria É o
> `paper_trail`**. A S0 já criou a tabela `versions`, já preenche o `whodunnit`
> com o `true_user` e já entregou o `PurgeAuditVersionsJob`; a S18 já o agendou.
>
> As tarefas anuladas ficam **riscadas com o motivo**, nunca apagadas.
>
> **Portões que valem para a fatia inteira (revistos):**
> - **A trilha é imutável.** Nenhuma tarefa introduz caminho de edição ou
>   exclusão de evento. O `paper_trail` não expõe nenhum, e o endpoint é só
>   leitura.
> - **Evento nunca se perde.** Resolvido de forma mais forte que o previsto: a
>   frase em pt-BR é **derivada na leitura** (`Sfg::AuditSummary`), não gravada.
>   Não existe coluna de texto para estourar, então o defeito do legado (resumo
>   > 300 → `save` devolve `false` → evento some) **não tem onde acontecer**.
> - **Um utilitário por conceito.** Antes de criar qualquer helper, conferir o
>   design system do ai9. Três dos treze eram reuso: `initials` e a cor
>   determinística já são o `UserAvatar`; a moeda já é `formatMoney` (S18).
> - ~~**`paper_trail` não é adotada.** Vira linha em `upstream-flags.md`~~ →
>   **ANULADO pela DEC-59**: é adotada, e é a única trilha do sistema.
> - O **menu** (S2), o **`MovementKind`** e o **`Entry`** (S6) não são tocados aqui.

---

## 0. A decisão que esta fatia tomou: `Tracking` × `paper_trail`

A **DEC-63** delegou: *"`Tracking` fica só com o que ele é no legado — registro
de evento de navegação/atividade. Se na S19 ficar claro que os dois se sobrepõem,
`Tracking` cai e sobra `paper_trail`."*

- [x] 0.1 **`Tracking` CAI. Sobra o `paper_trail`.** A premissa da ressalva é
  falsa: **não existe evento de navegação nem de atividade no legado**. As seis
  evidências, todas verificáveis no repositório de origem:
  1. **Os 20 emissores do `TrackingFacade` gravam `kind = "JOB"` e nada mais**, sobre
     exatamente **dois** tipos de registro — `Project` e
     `ProjectAvailabilityTemplate` (`lib/tracking_facade.rb`). É uma feature só:
     criação de projeto e ciclo de vida de padrão de disponibilidade.
  2. **`Tracking.new` não é chamado em nenhum outro lugar.** Fora do
     `TrackingFacade`, a única menção a `Tracking` no repositório inteiro é
     `Tracking.all` no controller.
  3. **`target_id`, `target_group_id` e `target_group_type` nunca são escritos**
     por nenhum dos 20 emissores — e são justamente as colunas dos três filtros do
     `index` e do bloco `target` do `_show.json.jbuilder`. A dimensão
     "destinatário", que o `proposal.md` descreve como parte do modelo, é
     **coluna morta**.
  4. **`GET /api/v1/trackings` não tem consumidor.** Nenhum `trackings_path`,
     nenhuma URL de ajax, nenhum `render` do widget fora da própria pasta
     `views/api/v1/trackings`. O botão que abriria a trilha de um card
     (`.app_card_tracking_button`) existe em **5 arquivos SCSS e em zero HTML** —
     foi estilizado e nunca construído.
  5. **`tracking_color(t)` e `tracking_icon(t)` ignoram o argumento**
     (`application_helper.rb:182-190`): devolvem, sempre, a mesma cor e o mesmo
     ícone. Não havia mapa tipo→aparência a portar.
  6. **O `show` já estava quebrado em três frentes** (achado **A-5**) e a
     **DEC-92** já descartou o `BE-433`.

  O que sobra de valor nos 20 emissores se divide em duas metades, e **nenhuma
  delas é uma segunda trilha**: "o template foi ativado / removido / criado" é
  **mudança de registro**, que o `paper_trail` grava com mais fidelidade (qual
  registro, foto completa antes e depois, autor real inclusive na impersonação);
  e "solicitado / iniciou / falhou com o erro X" é **estado de execução de job**,
  que é o `OPS-127` (progresso ao vivo) da **S13**, não auditoria.

  **Consequência:** `DB-591`, `DB-430`, `BE-430`, `BE-431`, `BE-434` e `OPS-126`
  saem como `dropped` com esta evidência. `BE-432`, `FE-443`, `FE-445` e `FE-446`
  **não caem** — passam a apontar para a trilha real (`versions`), que é o que
  preserva a capacidade que o usuário veria.

---

## 1. Esquema da trilha

- [x] ~~1.1 Migration `create_trackings`~~ — **ANULADA (DEC-59 + tarefa 0.1).** A
  trilha é a tabela `versions`, criada pela **S0**
  (`db/migrate/20260825110300_create_versions.rb`), com `object`/`object_changes`
  em `jsonb`, `impersonated_id`, `reason` e `ip_address`. **`DB-591`/`DB-430`
  saem como `dropped`.** Conferido: o schema segue com **56** tabelas e nenhuma
  `trackings` foi criada.
- [x] ~~1.2 Índices polimórficos~~ — **ANULADA.** `versions` tem
  `[item_type, item_id]`, `whodunnit`, `created_at` e `event`, que são os quatro
  filtros do endpoint.
- [x] ~~1.3 Não criar a coluna `type`~~ — **ANULADA junto com a tabela.** A
  evidência (STI sempre `NULL`, e o nome colide com o mecanismo de herança do
  Rails) fica registrada em `removed-features.md`; não há mais dry-run de S14 a
  esperar, porque não há coluna a decidir.

## 2. Serviço e imutabilidade

- [x] ~~2.1 `Tracking` imutável~~ — **ANULADA.** O `paper_trail` não expõe
  caminho de edição nem de exclusão de versão; o endpoint é só leitura
  (`GET`), e a única remoção é o expurgo por retenção
  (`PurgeAuditVersionsJob`, DEC-59 #1).
- [x] ~~2.2 `Sfg::TrackingService`~~ — **ANULADA.** Não há serviço de escrita: o
  `paper_trail` grava por callback do model, e a lista de models é declarada em
  `Sfg::AuditTrail::VERSIONED`.
- [x] 2.3 **Resumo longo não perde o evento** — **FEITA, e melhor que o
  previsto.** Em vez de truncar, a frase é **derivada na leitura**
  (`app/lib/sfg/audit_summary.rb`), montada a partir de `item_type` + `event` com
  o rótulo e o gênero vindos do catálogo pt-BR. Não existe coluna de texto, logo
  não existe o limite que fazia o `save` devolver `false`. Verificável:
  `spec/lib/sfg/audit_summary_spec.rb` — tipo e evento desconhecidos continuam
  produzindo frase, nunca exceção e nunca ausência de registro.

## 3. Emissão

- [x] ~~3.1 Os 20 emissores do `TrackingFacade` (BE-431)~~ — **ANULADA (tarefa
  0.1).** O quarteto `request → start → progress → finish` é **estado de job**, e
  o dono disso é o `OPS-127` da **S13**. A metade que é mudança de registro é
  gravada pelo `paper_trail` quando os models de S11 nascerem.
- [x] ~~3.2 `track_new_project` (BE-434)~~ — **ANULADA: a chamada sai.** Era
  `NoMethodError` garantido no legado (`pub/projects_controller.rb:135`, três
  argumentos, método inexistente). Sem `TrackingFacade`, não há chamada nem
  método a criar.
- [x] ~~3.3 Auditoria dos jobs de disponibilidade (OPS-126)~~ — **ANULADA pela
  mesma evidência.** Verificável: `grep` por gravação em `trackings` no
  repositório ai9 devolve **zero** — a tabela não existe.

## 4. Leitura

- [x] 4.1 **`GET /api/v1/audit_trail`** — filtros por `item_type`, `item_id`,
  autor (`whodunnit`), `event` e período, **combináveis**, com paginação em
  cabeçalho. **Fecha: BE-432** (adaptado: a rota é `audit_trail`, não
  `trackings`). Verificável **executando**: sem filtro `X-Total-Count: 97`, com
  `item_type=UserPermission` → 10, com `+event=create` → 3.
- [x] 4.2 **Autorização da listagem global (DEC-77 / Q-21).** Verificado
  executando, com quatro sessões reais: OG 200, Admin 200, Gerente **403**,
  Colaborador **403**, sem sessão **401**. O histórico **do próprio objeto** é de
  quem vê o objeto, e é servido pela fatia dona com `Sfg::AuditTrail.for_record`
  (documentado no módulo, com exemplo de uso).
- [x] 4.3 **`GET /api/v1/audit_trail/:id`** — detalhe, com a foto **completa** do
  estado anterior (DEC-78), que não vai na listagem. ~~A distância geográfica~~ —
  **ANULADA pela DEC-92: `BE-433` é `dropped`.** A geolocalização inteira foi
  descartada (a associação polimórfica não tem lado inverso nenhum no
  repositório); sem ela o cálculo nunca dispararia.
- [x] 4.4 **Entity do payload JSON da trilha.** `Api::Entities::AuditVersion`.
  **Fecha: FE-446.** Expõe o autor **real** resolvido, o impersonado, o motivo,
  o `summary` em pt-BR e o `occurred_at` em ISO-8601 UTC.

## 5. Tela

- [x] 5.1 **Mapa `event` → cor/ícone como DADO, não `case`**
  (`components/audit/auditAppearance.ts`). Verificável: acrescentar um evento é
  acrescentar uma linha do mapa; nenhum componente muda, e evento desconhecido
  cai no padrão sem quebrar a tela. As cores são **tokens semânticos** — o teste
  reprova cor literal. **Fecha: FE-443.** *(Registrado: no legado não havia mapa
  a portar — as duas funções devolviam constante. Isto é comportamento novo, e
  está no `improvements-log.md`.)*
- [x] 5.2 **Widget de item da trilha e a timeline** —
  `components/audit/AuditTrailItem.tsx` e `AuditTrailTimeline.tsx`, consumindo a
  entity. **Fecha: FE-445.** Inclui o quarto estado (erro), que o legado não
  tinha: numa trilha de auditoria, "falhou ao carregar" e "nada aconteceu" não
  podem se parecer.
- [x] 5.3 **Tela da trilha global** — `app/pages/admin/AuditTrailPage.tsx`, com
  os filtros e o `PaginationPill`. **Pendência declarada nas duas pontas:** a
  **rota e o item de menu são da S2** (`App.tsx`, `useNavItems.ts`, que esta
  fatia não toca). As duas linhas exatas estão no cabeçalho do arquivo da página.

## 6. Utilitários de formatação — um por conceito

- [x] 6.1 `timeAgo` — tempo relativo em pt-BR, **um** utilitário
  (`lib/utils/date.ts`). **Fecha: FE-430.** A duplicação já tinha recomeçado
  nesta base: `formatDistanceToNow` inline em `ExecutionViewerPage.tsx` e em
  `ExecutionDetailPage.tsx`; os dois passaram a chamar o utilitário.
- [x] 6.2 `format_money` — **REUSO.** Já existe como `formatMoney` em
  `lib/utils/number.ts` (S18), com o parse que desfaz a formatação. **Fecha:
  FE-431** como `reuse`, não `build`.
- [x] 6.3 Concordância de gênero vira **verbete de catálogo** —
  `pt-BR.audit_trail.entidades` (par `rotulo`/`genero`) e `pt-BR.audit_trail.artigos`.
  **Fecha: FE-432.**
- [x] 6.4 `initials` — **não implementado.** O `UserAvatar` do design system já
  faz (`initialsOf`, `components/ui/UserAvatar.tsx`). **Fecha: FE-433** como
  `reuse`, com a citação do componente.
- [x] 6.5 `chopMiddleWords` — nome curto (`lib/utils/text.ts`). **Fecha: FE-434.**
- [x] 6.6 Cor de identificação determinística — **REUSO.** É `avatarTone`
  (`components/ui/UserAvatar.tsx`), hash djb2 sobre a chave. A gem
  `color-generator` não é substituída por outra. Verificável: o teste renderiza
  duas vezes e compara. **Fecha: FE-435.**
- [x] 6.7 Meses localizados (`monthOptions`) e dias da semana
  (`nomeDoDiaDaSemanaPorIndice`) vêm do catálogo `pt-BR` do `date-fns`, não de
  array literal. **Fecha: FE-436, FE-442.**
- [x] 6.8 Janela de anos (`yearWindow`). **Fecha: FE-437.** *(Registrado: o
  `ten_years_array` do legado devolvia **onze** anos. O intervalo é preservado; o
  nome é que era errado.)*
- [x] 6.9 Plural vira **forma plural no catálogo** (`pt-BR.audit_trail.plurais`)
  mais três regras regulares em `Sfg::Inflection`. **Fecha: FE-438.** O
  `+ "s"` do legado produzia "permissãos" e "papels".
- [x] 6.10 `sliceIn` — distribuição em N colunas, utilitário e não helper de
  string. **Fecha: FE-439.** *(O legado tinha **três** cópias, duas delas dentro
  de controllers; e `slice_in(lista, 0)` descartava a lista inteira em silêncio.)*
- [x] 6.11 **Contrato ISO-8601 em toda a fronteira.** `toIsoDate` (dia de
  calendário) e `toIsoDateTime` (instante); os filtros de período do endpoint são
  `DateTime` do Grape, que recusa `dd/mm/aaaa`. Verificável: teste que reprova
  formato brasileiro na saída. **Fecha: FE-440.**
- [x] ~~6.12 Flag de auto-cadastro público, nascendo `false` (FE-444)~~ —
  **ANULADA: a flag virou redundante, e construí-la seria um risco.** Três
  evidências:
  1. **As 4 rotas não existem mais** (DEC-49, entregue pela S1). Verificado
     executando: `pre_register`, `complete_registration`, `visitor_signup` e
     `visitor_signup_with_link` respondem **404**.
  2. **A quinta porta também fechou.** `Auth::VisitorAuthService` ainda criava
     conta (com JWT emitido) pelo nó `Ai::Nodes::Redirect`; a S1 a substituiu por
     `Auth::ExistingUserSessionService`, que **só casa** e devolve 404 para
     contexto sem usuário. Conferido nesta fatia — ver a seção 9.
  3. **No legado a flag era invertida e já estava ligada.**
     `SFG::Metadata::PUBLIC_CREATE_USER = 1` e as views fazem
     `unless public_create_user?` — ou seja, `true` **esconde** o botão
     "Cadastre-se agora". Portar o nome portaria a mentira.

  Uma flag cujo único trabalho é fechar uma rota que não existe é convite a
  reconstruir a rota ("existe a flag, então deve existir o fluxo"). A trava do
  **D-39** passa a ser **estrutural**, que é o que a própria DEC-49 pediu:
  *"rota que não existe não reabre por engano"*. **`FE-444` sai como `dropped`.**
- [x] 6.13 **Dependência registrada nas duas pontas — e já resolvida.** As rotas
  públicas de `api/root.rb` saíram da allowlist e os endpoints foram desmontados
  em `api/auth/v1/registration.rb`; o frontend que chamava `pre_register` dentro
  do login foi corrigido junto (é o defeito que gerou a "Regra de fronteira").
  Conferido executando: **D-39 fechado**.

## 7. Utilitários de servidor

- [x] 7.1 **`Sfg::Sortable`** — ordenação multi-coluna dirigida pelo cliente, com
  **allowlist de colunas**. **Fecha: BE-449.** Verificável: chave fora da
  allowlist é ignorada (não interpolada), estilo desconhecido cai em `asc` em vez
  de derrubar o request, e o `to_sql` não contém nada vindo do cliente.
  *(O legado tinha o mesmo trio de métodos copiado em **18 models**.)*
- [x] 7.2 **`IntervalValidator`** — inteiro, e mínimo não maior nem igual ao
  máximo. **Fecha: BE-455.** Corrige os **três** defeitos do original, que juntos
  faziam o validador não validar: comparação `String`×`Integer` que recusava todo
  inteiro; `errors[field] <<` que no Rails 8 escreve num array descartado; e
  comparação com a outra ponta nula, que levantava dentro do `valid?`.
- [x] 7.3 **`UriValidator`** — **só formato** `http(s)`. A verificação de
  disponibilidade por HTTP **sai** (D6). **Fecha: BE-456.** Verificável: validar
  um registro com host inexistente **não faz nenhuma chamada de rede** — o
  `webmock` está ligado na suíte e levantaria.

## 8. Paridade e fechamento

- [x] 8.1 Os **27 IDs** conferidos contra `.migration-ai9/parity-ledger.md`:
  **17 `migrated`** e **10 `dropped` com a prova na linha**. Nenhum `blocked`
  (Q-21 fechada pela DEC-77, Q-22 pela DEC-92, Q-23 pela DEC-78) e **nenhum
  `dropped` por omissão**.
- [x] 8.2 Registradas em `improvements-log.md` as mudanças visíveis — em especial
  "eventos deixam de sumir" (por construção, não por truncamento) e "a aparência
  do item da trilha passa a distinguir os eventos", que o QA do Phase 4 leria
  como divergência.
- [x] ~~8.3 Registrar `paper_trail` em `upstream-flags.md` como não adotada~~ —
  **ANULADA pela DEC-59**, que a adotou. O que foi registrado lá é o oposto: a
  gem saiu de "achado C-12, declarada sem uso" para "é a trilha do produto".
- [x] 8.4 Conferido que o menu (S2), o `MovementKind` e o `Entry` (S6) **não**
  foram tocados, e que nenhum utilitário criado duplica o design system —
  três dos treze IDs de formatação fecharam como **`reuse`** exatamente por isso.

## 9. O que a DEC-59/DEC-78 tornaram obrigatório (o coração da fatia)

- [x] 9.1 **A lista de models versionados é declarada num lugar só** —
  `app/lib/sfg/audit_trail.rb`, com **fatia dona e motivo escrito por linha**, e
  a metade igualmente importante: `EXCLUDED`, com o motivo de cada exclusão. A
  fatia dona acrescenta a linha e escreve `include Auditable` no model.
- [x] 9.2 **Um portão reprova a lista fora de sincronia** —
  `spec/lib/sfg/audit_trail_spec.rb` falha em quatro casos: model versionado sem
  declaração, model declarado sem versionar, opções divergentes, e model
  declarado sem verbete pt-BR. **Pegou um caso real na primeira execução** —
  `AdminMessage`, `MessageNote` e `Observer` haviam ganhado `has_paper_trail` sem
  declaração; os três são atendimento, não auditoria financeira nem de acesso, e
  saíram com o motivo escrito em `EXCLUDED`.
- [x] 9.3 **`skip`/`ignore` conferidos.** `jti` é `skip` (não é **copiado** para a
  trilha); `updated_at`, `last_login_at` e `login_count` são `ignore` (não geram
  versão). Verificado por spec: login não produz versão, e o `jti` não aparece
  em `object` nem em `object_changes`.
- [x] 9.4 **`whodunnit` registra o `true_user` na impersonação (DEC-59 #3).**
  Conferido — e **não quebrado**. Verificado **executando**: uma alteração real
  feita dentro de uma sessão personificada gravou `author = Suporte Livetat` (o
  OG que iniciou) e `impersonated = Gustavo Lins`.
- [x] 9.5 **Retenção conferida.** `PurgeAuditVersionsJob` (S0) apaga versões com
  mais de `AUDIT_VERSIONS_RETENTION_DAYS` (padrão 1825 dias / 5 anos) e **está
  agendado** em `config/schedule.yml` (S18), às 03:50 `America/Sao_Paulo`. Bate
  com o DEC-59 #1 e o DEC-78 #2.
- [x] 9.6 **A impersonação ganhou verbete próprio.** `Auth::ImpersonateService`
  grava `impersonate_start`/`impersonate_stop` na **mesma** tabela (a trilha é
  uma só). Sem verbete, a frase cairia no `update` e diria "a conta de usuário
  foi alterada" — a informação errada sobre o ato mais sensível do sistema. Os
  dois eventos entraram no catálogo, no filtro do endpoint e no mapa de
  aparência.
- [x] 9.7 **Não há segunda trilha.** `AuditEvent` não existe e
  `permission_audit_logs` continua **sem produtor** — conferido por spec.
