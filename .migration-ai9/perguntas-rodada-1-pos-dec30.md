# Perguntas da rodada 1 — depois do DEC-30

> O **DEC-30** (`decisions.md`) declarou o princípio governante: *"o legado é um sistema validado
> então a maioria das coisas de regras e cálculos deve-se manter como está no legado"*. Este
> documento aplica o princípio às **108 perguntas ainda em aberto** (P-010 … P-117; P-001 a P-009
> já têm DEC) e devolve só o que continua precisando da sua palavra.
>
> **Não edita nada.** `perguntas-rodada-1.md` continua sendo o documento de origem; as entradas
> aqui são cópias verbatim, com um campo a mais explicando por que o princípio alcança ou não.

**Como responder:** uma linha por pergunta — `P-020: b` — e, na tabela da seção 2, só o que você
**vetar**: `P-016: não, quero (b)`. O silêncio na tabela confirma a leitura do DEC-30.

---

## 1. Placar

| Balde | Quantas | O que significa |
| ----- | ------: | --------------- |
| `RESOLVIDA-30` | **39** | O DEC-30 responde: replicar, com golden test. Vão para a tabela da seção 2, para você passar o olho e vetar |
| `EXCEÇÃO-1` | **2** | Replicar gravaria dado errado do zero num banco novo (padrão P-005/DEC-29) |
| `EXCEÇÃO-2` | **6** | Falha de segurança ou de autorização — replicar seria portar a vulnerabilidade |
| `EXCEÇÃO-3` | **43** | Não existe legado a replicar: feature nova, base ai9, escopo, retenção, plataforma |
| `AINDA-PRECISA` | **18** | Escolha de negócio, jurídica, comercial ou de conteúdo que só você tem |
| **Total** | **108** | |

### De 108, **69 ainda precisam de você**.

O DEC-30 fechou **39** — e é honesto dizer onde ele fechou: das 39, **27 estão nas duas primeiras
faixas de impacto** (`muda número na tela` e `muda comportamento observável`), que é exatamente
onde moram regra e cálculo. Nas faixas `muda escopo` (37 perguntas) e `só interno` (14) o princípio
quase não alcança: são 9 e 3 fechadas. **Um princípio sobre cálculo não decide escopo.**

Das 69 que sobram, o recorte que interessa para hoje:

- **16 travam código hoje** e continuam sem resposta: **P-015**, **P-020**, **P-021**, **P-038**, **P-067**, **P-096**, **P-097** (de `AINDA-PRECISA`), mais P-018, P-022, P-070, P-078, P-082, P-091, P-099, P-100 e P-116 (das exceções). Fora da conta, **P-102** não trava código mas é a primeira tela da demo de sexta.
- **O DEC-30 destravou 7 itens da lista "travam código HOJE"** da seção 3.1 do documento de origem: P-016, P-019, P-026, P-032, P-036, P-045 e P-077. Com P-001..P-005 e P-009 já decididas, o bloco 0 de S5 e o de S7 ficam a uma resposta de fechar (P-018 e P-015).
- **4 não têm default nenhum**: P-020, P-021, P-097, P-116 — e P-100, que está registrada como "ambiguidade de ordem no relatório".
- **5 continuam com default em conflito** depois do DEC-30: P-015, P-038, P-082, P-085 e P-089. *(P-016 e P-036 saíram do conflito — o princípio desempatou as duas a favor de replicar.)*
- **8 dependem de um número do dump**, não de opinião: P-018, P-049, P-053, P-059, P-070, P-078, P-091 e — como otimização — P-026. **Conferido:** o único dump neste repositório é `db/seed_assets/sfg_legacy_full.sql` (8,6 MB), que é do sistema **Django anterior** e nem tem tabelas `risk_*`. As consultas da seção 5 do documento de origem só rodam do seu lado.

---

## 2. `RESOLVIDA-30` — 39 fechadas pelo princípio

Uma linha cada, para passar o olho. **O que você não vetar, é isso que vai ser construído**, com
teste golden alimentado por valores extraídos do legado. Os defeitos que ficam preservados de
propósito estão consolidados na seção 6.

| P | O que é | Opção que o princípio escolhe | O que isso preserva |
| - | ------- | ----------------------------- | ------------------- |
| **P-010** | "A vencer" da renegociação inclui as vencidas | (a) mantém a conta e renomeia a coluna para "Em aberto" | `due_installments` continua somando as vencidas — e continua sendo o expoente do valor presente (`renegotiation.rb:180`) |
| **P-011** | Dois números para "o que falta pagar" | (c) mantém os dois, com rótulo que explica a diferença | mesma forma do **DEC-26**: `pending_main_value` sem piso (pode ficar negativo) convive com `remaining_value` com piso |
| **P-013** | "Valor Parcela" sobrescrito pelo valor presente | (a) replicar, com golden | **D-46** — a coluna mais lida da renegociação mostra o VP sempre que há juros > 0 e saldo em aberto |
| **P-014** | Mora entra dos dois lados da conta | (a) replicar exatamente | **A-10** — a mora nunca é efetivamente cobrada na parcela e infla o "R$ Pago" no agregado (`renegotiation.rb:105`) |
| **P-016** | "Encerrar" operação de risco | (a) `is_ended` continua sendo rótulo (o que a spec já fixou por DEC-01) | **D-94** — encerrada continua somando exposição, movimento e prorrogação continuam aceitos, e renovar não encerra a original |
| **P-017** | Transferência da antecipação sem contrapartida | (a) replicar a assimetria | com `is_pre = 0` o valor sai de uma operação e não entra em nenhuma (`risk_movement.rb:46`) |
| **P-019** | `has_safegold_management`: carimbo ou derivado | (b) manter o carimbo, inclusive a inconsistência | **D-30** — 6 tabelas carimbadas na criação e só `companies` ressincronizada quando a marca muda |
| **P-023** | `receipts` herda o gate de `charges` | (a) herda, escrito na matriz como linha derivada | é o comportamento do legado e não tira acesso de ninguém; o custo de escrever a linha é zero |
| **P-025** | Validações de faixa que o legado não tem | (a) replicar as ausências | data em 1900/2100, `valor_bruto` zero, dívida negativa e taxa negativa continuam entrando |
| **P-026** | Taxa de remuneração fora de 0–100 | (a) replicar a ausência | a taxa que multiplica **todo** o faturamento segue sem validação — 250% passa pela UI (`remuneration.rb:9`) |
| **P-027** | `is_active` dos catálogos filtra? | (b) o interruptor continua decorativo | **D-19** — desativar carteira, tipo de recebível ou fonte de recurso não tira nada de nenhum select |
| **P-028** | Remuneração com tipo desativado | (c) replicar o comportamento atual | a edição continua exibindo o primeiro tipo **ativo** em vez do tipo real da remuneração |
| **P-029** | `nominal_tax` × checagens calculadas | (a) informativo, como hoje | as três nunca são comparadas, e a taxa digitada viaja direto para `agreed_rate` da operação de risco |
| **P-030** | Tarifa do mesmo tipo repetida no borderô | (a) permitir, como hoje | duplo clique lança o IOF duas vezes e o operador não tem como perceber |
| **P-032** | Datas: a tela trava, a API aceita | (a) alinhar pelo servidor — a UI é o comportamento validado | prorrogação continua só pela extensão; o `permit` aberto não é comportamento que alguém use pela tela |
| **P-033** | Trocar a empresa move a operação de projeto | (c) replicar o comportamento atual | a operação muda de projeto em silêncio e sem log, podendo invalidar remuneração e recibo já emitidos |
| **P-034** | Operação encerrada continua faturável | (a) manter como está | par de P-016 — encerrada segue na lista de candidatos a recibo (`remuneration.rb:26`) |
| **P-035** | Busca de estruturadas ignora contrato e empresa | (a) replicar a busca como está | não se acha pelo número de contrato nem pela empresa que está na coluna ao lado |
| **P-036** | Renomear indicador reescreve o histórico | (a) replicar o resultado, tirando o `update_all` de dentro do request | **D-70** — o lançamento de 2023 passa a dizer que sempre se chamou assim. *(c) é observacionalmente idêntica e também não viola o DEC-30)* |
| **P-039** | Reconectar indicador recupera o histórico | (a) replicar, com o aviso de (c) na tela | desconectar esconde, reconectar traz tudo de volta — comportamento conservador, não perde dado |
| **P-040** | Dois itens de menu "Indicadores" | (a) renomear — rótulo, não regra (calibração **DEC-27**) | nada de cálculo muda; o DEC-27 já aceitou renomear métrica |
| **P-042** | `provider_name` no detalhe, `title` na lista | (a) `title` prevalece — rótulo, não regra | nada de cálculo muda |
| **P-043** | URLs de contrato com espaço e typo | (a) slug com **301** das strings antigas, typo incluído | o 301 é o que preserva o link externo já existente; a string crua não é regra de negócio |
| **P-044** | ETL atribuiu tudo ao usuário 1 e à empresa 1 | (a) manter a atribuição como está | ~62 mil borderôs continuam atribuídos a quem não os criou e à empresa 1 |
| **P-045** | Texto do contrato: arquivo ou banco | (a) semear do arquivo só se não houver contrato no banco, com (d) para o `user.html` órfão | preserva o texto que está no ar e mantém `OPS-477` vivo. **A revisão jurídica do conteúdo continua aberta em P-020/P-021** |
| **P-053** | Precedência de papel invertida no importador | (a) não reprocessar; o dry-run lista para revisão humana | promoção automática é escalação de privilégio por script; a lista custa uma consulta |
| **P-054** | Gênero: quem não preencheu é tratado como homem | (a) migrar os valores intactos e usar formulação neutra quando desconhecido | o dado migra igual — muda só o texto (rótulo, calibração **DEC-27**) |
| **P-068** | Estado de baixa/liquidação do recebível | (a) + (c) replicar e registrar a lacuna no ledger | **D-19** — o borderô continua sem ciclo de vida; só "OK"/"Diferença" |
| **P-069** | `is_title` e `is_liquidation` | (a) portar os dois como estão | `is_title` continua coluna sem consumidor — mantida porque pode haver leitor externo (mesmo critério do DC-16) |
| **P-074** | Pagamento sem forma nem conciliação | (a) replicar a ausência | nenhuma coluna de método, banco, documento ou conciliação bancária |
| **P-076** | Tipos de contrato configuráveis pela UI | (a) manter os dois tipos fixos em código | sem CRUD de tipos; o terceiro documento (`user.html`) continua não carregado |
| **P-077** | `balance` da operação estruturada | (a) replicar o reset, golden, e documentar a coluna como decorativa | **D-73** — *conferido na fonte:* `structured_operation.rb:38` é o **único** escritor de `balance` e não existe `StructuredMovement` em lugar nenhum, então o reset é inócuo na prática |
| **P-080** | `is_on_variable` | (a) portar como marca comercial (grava e exibe) | zero leituras em cálculo, filtro, escopo ou relatório — mantida pelo mesmo critério do `has_bi` (DC-16) |
| **P-081** | Os 4 flags de `structured_operation_types` | (a) migrar os quatro | `allow_manual_operations` e `allow_receivable_entries` continuam órfãos no lado estruturado |
| **P-083** | Tipos de indicador além de "Dinheiro" | (a) só "Dinheiro", como hoje | percentual e quantidade continuam sendo gravados como R$ |
| **P-093** | Aviso de "atualização em andamento" | (a) só para quem tem job; os 7 widgets viram `dropped` com evidência | é literalmente o que o legado faz: só `Project` emite `data-ongoing` |
| **P-112** | `is_active` no `permit` e fora do formulário | (a) manter os dois caminhos | continua havendo escrita fora do `permit`, pela action `activated` |
| **P-113** | `month`/`year` inteiros soltos | (a) inteiros + `CHECK (1..12)` + `NOT NULL` | não altera regra nem cálculo: o CHECK só recusa o que já estoura em runtime em `Date.new(year, 47)` |
| **P-114** | `user_id` do lançamento de indicador | (b) um campo só, semântica "quem alterou por último", agora documentada | o autor continua sendo sobrescrito a cada submissão — e continua não aparecendo em tela nenhuma |

---

## 3. `EXCEÇÃO-1` — replicar gravaria dado errado do zero (2)

É o padrão do **P-005/DEC-29**: não se trata de preservar um número que já existe no banco do
cliente, e sim de o sistema novo **produzir** um valor errado a cada gravação.

### P-031 — Excluir tarifa já gravada tem efeito imediato, mesmo se o usuário cancelar

- **Por que o DEC-30 não resolve:** Replicar não é preservar um número existente: é deixar o borderô **pai** com `tarifas_*` desatualizadas no banco novo a cada exclusão de tarifa, até alguém salvar de novo. É o sistema gravando um agregado que ele mesmo sabe estar inconsistente com as linhas filhas — o padrão do DEC-29. A opção (a) é a exceção mínima: preserva o efeito imediato do legado e só recalcula o pai na hora.
- **Origem:** `Q-29`
- **Fatia:** S6
- **Trava:** trava `FE-176`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O botão de remover tarifa persistida (`.../receivables/new/_body.html.erb:484`) dispara um `DELETE` direto assim que o usuário confirma o modal (`.../new/_body.js.erb:663-681`, linha 674), **fora de qualquer submit do borderô**. O servidor apaga (`receivable_taxes_controller.rb:15-24`) e **não recalcula o borderô pai** — os agregados `tarifas_*` só se corrigem no próximo save do recebível. Cancelar a edição não desfaz a exclusão, e entre a exclusão e o próximo save o borderô fica com totais desatualizados.
- **Opções:** (a) manter o efeito imediato, mas **recalcular o borderô na hora**; (b) postergar a exclusão até o salvamento do borderô (o formulário passa a ter estado pendente); (c) replicar exatamente, inclusive os totais desatualizados.
- **Default vigente:** (b) — é o que o usuário espera de um botão dentro de um formulário com "Salvar".
- **Recomendação:** (b), com (a) como piso inegociável caso você prefira manter o imediato. Um total que fica errado até alguém salvar de novo não pode sobreviver à migração.

### P-055 — Na tela de mensagens, pedir "Concluído" grava "Fechado" (e vice-versa)

- **Por que o DEC-30 não resolve:** Replicar significa gravar, num banco novo, um estado que **contradiz o que o usuário escolheu**: pedir "Concluído" grava `Fechado` e a action `close` grava `Concluído`. Não é preservar um número existente, é produzir dado errado do zero em cada gravação nova. Agravante: com a inversão nos **dois** sentidos, não existe comportamento coerente ao qual alguém pudesse ter se acostumado.
- **Origem:** `Q-53`
- **Fatia:** S2
- **Trava:** trava `BE-527`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Os dois estados existem e são distintos (`engines/feedback19/app/models/livetat/feedback19/state.rb:11-12`). No `update`, escolher "Concluído" no select grava **"Fechado"**: `messages_controller.rb:118-119` — `if message_params[:state_id].to_i == State.done.id then @message.state_id = State.closed.id`. **A inversão é dupla:** a action chamada `close` (`:156-159`, rota `PUT /messages/:id/close`) grava **"Concluído"**. Os dois estados estão trocados **entre si**, não é um typo num lado só.
- **Opções:** (a) corrigir os dois — "Concluído" grava Concluído, "Fechar" grava Fechado; (b) replicar a inversão; (c) fundir os dois estados num só (a distinção nunca foi usada de forma coerente).
- **Default vigente:** (a), com linha no `improvements-log.md` porque é comportamento observável.
- **Recomendação:** (a). Com a inversão nos dois sentidos, "alguém se acostumou com o comportamento atual" deixa de ser plausível: não há comportamento coerente com que se acostumar.

---

## 4. `EXCEÇÃO-2` — segurança e autorização (6)

O DEC-30 é explícito: *"Replicar 'qualquer autenticado publica os Termos de Uso' não é paridade,
é vulnerabilidade portada"*. Estas seis são dessa família.

**Fora desta lista, mas da mesma família e já com veredito `corrigir` no `legacy-defects.md`**
(não viraram pergunta e não precisam virar): o escopo por projeto descartado quando chega id por
parâmetro (**D-01 / D-16 / D-29 / D-76 / D-100**), a falta de trava de hierarquia na impersonação
(`upstream-flags` #14), `Tracking.all` sem escopo (**D-110**) e o tenant definido por cookie do
cliente (**D-28**).

### P-022 — Quem pode publicar uma versão de contrato? (hoje: qualquer autenticado)

- **Por que o DEC-30 não resolve:** Nomeada dentro do próprio **DEC-30** como exceção 2 (achado **A-1**). Replicar "qualquer autenticado publica os Termos de Uso" não é paridade, é vulnerabilidade portada — some-se o mass assignment de `id` e `version` no mesmo `permit`.
- **Origem:** `Q-20` + `F-15` (fundidas; levantada em dois mapas)
- **Fatia:** S12
- **Trava:** trava `BE-335`, a tarefa 2.6 de S12 (`s12/tasks.md:80-86`) e a matriz de autorização, que é **contrato aprovado** (DEC-18).
- **Impacto:** `muda comportamento observável`
- **Contexto:** **Ver o achado A-1.** A matriz aprovada dá `contracts` como **`R` para os quatro papéis** (`authorization-matrix.md:197`), derivada dos links do rodapé da sidebar e do aceite — ela descreve **ler e aceitar os Termos**. A administração (criar versão, publicar) nunca entrou na matriz porque **não tem item de menu**. E o gate que os dois mapas afirmavam existir **não existe**: `contracts_controller.rb` tem 101 linhas e zero ocorrências de `before_action`/`may?`/`admin?`/`og?`/`authorize`; as rotas não têm constraint (`config/routes.rb:30-31`); o `create` (`:56-67`) só carimba `creator = current_user` e salva. Some-se o mass assignment de `id` e `version` no mesmo `permit`. **Hoje qualquer usuário autenticado que acerte a URL publica uma nova versão dos Termos de Uso.** A pergunta não é "confirmar um gate", é **"criar o gate que nunca existiu"**.
- **Opções:** (a) novo recurso `contract_versions` = **CRUD para OG + Admin**, `-` para Gerente e Colaborador; `contracts` (ler/aceitar) fica exatamente como aprovado — o total passa de 45 para 46 recursos; (b) publicação só para **OG** (é documento jurídico do fornecedor); (c) manter a matriz literal — todos leem, ninguém publica pela aplicação, e versão nova entra por seed; (d) deixar como está no legado (qualquer autenticado).
- **Default vigente:** (a), proposta e **aguardando confirmação**. A matriz não foi alterada por iniciativa própria.
- **Recomendação:** (a). Publicar Termos vincula **todos** os usuários — não é operação de gestor, mas também não precisa ser exclusiva do fornecedor, e (b) obriga o cliente a chamar a Livetat para trocar uma vírgula. Uma armadilha para não repetir: `user_is_readonly` pode tirar C/U/D de `contract_versions`, mas **não pode** bloquear o aceite dos Termos pelo próprio usuário — senão o readonly nunca aceita e fica trancado fora do sistema.

### P-048 — ETL: o que acontece com `is_active` e com `legacy_password`?

- **Por que o DEC-30 não resolve:** **Conferido na fonte, e o resultado inverte a leitura do material:** `users.is_active` foi criada em 2021 (`db/migrate/20210402135252_add_is_active_to_livetat_auth_users.rb`) pela mesma leva do importador e **não tem um único leitor** — não há `active_for_authentication?`, não há filtro em controller nenhum. Ou seja, "replicar" aqui significa **não bloquear ninguém**: toda conta que o sistema Django anterior marcou como inativa entra no produto novo com acesso pleno. Isso é decisão de acesso a sistema financeiro, não regra de negócio. Junto vai `legacy_password` (hash Django, **D-106**/**D-109**, senha adivinhável a partir do nome), que não pode chegar ao banco novo.
- **Origem:** `Q-46`
- **Fatia:** S14
- **Trava:** trava a carga de usuários — define quem consegue entrar no dia 1.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O importador do legado copia a senha antiga para uma coluna `legacy_password` e ainda inventa uma senha determinística a partir do primeiro nome + `#6230` (`app/models/legacy/u.rb:28` e `:30`). O `is_active` vem do sistema Django antigo e nunca ficou claro se `0` significa "conta desligada" ou "nunca ativada". O ai9 não tem senha nenhuma (DEC-14: entrada por código), e o bloco de auth já decidiu que o bloqueio de conta vira `users.blocked_at` (DC-07).
- **Opções:** (a) `is_active = 0` nasce com `blocked_at` preenchido e o usuário sai numa **lista de exceções** para revisão humana antes do cutover (mesmo tratamento do papel vazio, DEC-18 #8); `legacy_password` **não é migrado**; (b) `is_active = 0` nasce ativo (assumindo "nunca ativado") — todos entram; (c) `is_active = 0` não é migrado de forma alguma.
- **Default vigente:** (a) — bloquear e revisar é reversível; liberar por engano não é.
- **Recomendação:** (a). E `legacy_password` não deve nem chegar ao banco novo: é hash de um sistema que não existe mais, num produto sem senha.

### P-056 — O envio anônimo de mensagem de feedback é usado?

- **Por que o DEC-30 não resolve:** O `create` de mensagem é **isento de autenticação de propósito** e o único filtro restante faz bypass total quando o formato é HTML/JS. Replicar é portar um endpoint de escrita público e sem throttle — e o próprio `api/root.rb:14-17` da base ai9 registra que um bypass por header já vazou a base inteira até 01/08/2026.
- **Origem:** `Q-54`
- **Fatia:** S2
- **Trava:** trava `BE-531` e a allowlist pública de rotas.
- **Impacto:** `muda comportamento observável`
- **Contexto:** No legado o `POST` de mensagem é **público de propósito**: `engines/feedback19/app/controllers/livetat/feedback19/messages_controller.rb:6` isenta explicitamente o `create` da autenticação por token, e a action não referencia `current_user` (`:85-105`). O único filtro restante, `lock_if_its_not_a_valid_client_app`, faz **bypass total** quando o formato é HTML ou JS (`engines/auth_ux19/.../application_controller.rb:21-27`) — e o console usa `format: :js`, então na prática não bloqueia nada. Vale lembrar que o próprio `api/root.rb:14-17` da base ai9 registra que um bypass por header já vazou a base inteira até 01/08/2026.
- **Opções:** (a) só autenticado; (b) público, mas **por rota na allowlist**, com throttle do Rack::Attack e captcha; (c) público sem throttle (como hoje).
- **Default vigente:** (a) — e, se o anônimo for necessário, (b).
- **Recomendação:** (a). Com o cadastro público desligado (DEC-18.7), não sobra visitante legítimo para usar o canal anônimo.

### P-061 — Os papéis do Safegold colidem com os `hierarchy_level` que a base já semeia (contrato C3)

- **Por que o DEC-30 não resolve:** É o contrato **C3** e é autorização pura: `Admin` colide com `client` e `Colaborador` com `free` nos `hierarchy_level` que a base já semeia, e `higher_than` (`where('hierarchy_level < ?', level)`) passa a devolver conjuntos que ninguém espera. Num contrato onde inverter o sinal significa "dar poder de OG a um Colaborador", não há default seguro.
- **Origem:** `F-50` (DS0-4)
- **Fatia:** S0
- **Trava:** trava o seed de `user_types` (`OPS-541`, `DB-730`) e, por tabela, o de-para de papéis do ETL.
- **Impacto:** `muda comportamento observável` — **reclassificada** (o empacotamento a tinha como `só interno`; ela decide quem pode o quê)
- **Contexto:** **Ver o achado A-4.** A decisão declarada (DS0-4) é **acrescentar** os 4 papéis do Safegold sem remover os da base, porque `UserType` é peça compartilhada (Princípio 6b) e `visitor` é usado por `restrict_visitor_access!`. Mas a base já semeia, em `backend/app/models/user_type.rb:37-41`: `OG`=1, `client`=2, `free`=4, `visitor`=5. O de-para escrito no `migration-map.md` é OG→1, Admin→2, Gerente→3, Colaborador→4 — logo **Admin colide com `client`** e **Colaborador colide com `free`**. Dois papéis no mesmo nível fazem `higher_than` (`where('hierarchy_level < ?', level)`) devolver conjuntos que ninguém esperava. É o contrato **C3**, o item de maior risco da migração.
- **Opções:** (a) usar níveis que não colidem, com espaçamento (por exemplo Admin=10, Gerente=20, Colaborador=30); (b) reaproveitar `client` como Admin e `free` como Colaborador — não acrescenta papel, mas muda a semântica de peça compartilhada; (c) manter os níveis colidentes e fazer a comparação considerar nível **e** nome.
- **Default vigente:** (a) implícito — o desenho diz "acrescentar", mas não fixa os números, e o de-para escrito usa 1/2/3/4.
- **Recomendação:** (a), com espaçamento. Colisão de nível num contrato onde inverter o sinal significa "dar poder de OG a um Colaborador" não é lugar para economizar números.

### P-105 — Guardamos o corpo de todo e-mail enviado?

- **Por que o DEC-30 não resolve:** Replicar é guardar o **corpo** de todo e-mail para sempre, sem expurgo — e no ai9 os e-mails vivos são de identidade, com o **código de acesso** dentro. Guardar o corpo de um e-mail que contém a credencial é guardar a credencial em texto puro por outro nome. O legado ainda grava e-mail de credenciais (`mailer_decorator.rb:4`) e não tem uma única rotina de expurgo.
- **Origem:** `Q-88` + `F-31` (fundidas; DS1-3)
- **Fatia:** S1 e S13
- **Trava:** a forma da tabela `email_logs` (`DB-514`, e `DB-481` em S13).
- **Impacto:** `só interno`
- **Contexto:** No legado, `livetat_mailer_contacts` guarda `sender`, `target`, `target_name`, `subject`, `message` e `type` (`engines/mailer19/db/migrate/20160409121840_...:3-12`), e a coluna `message` foi **promovida de `string` para `text` justamente para caber o corpo** (duas migrations de 19/05/2017). Cada envio grava o corpo antes de enfileirar (`engines/mailer19/lib/livetat/mailer19/grind_mailer.rb:5-13`, e igualmente `:27,47,67,85`, mais 4 pontos em `engines/feedback19/app/decorators/grind_mailer_decorator.rb`) — **inclusive e-mails de credenciais** (`app/decorators/models/mailer_decorator.rb:4`). **Não há expurgo**: zero ocorrências de purge/cleanup/`destroy_all` em `lib/`, `app/jobs` ou no engine. Retenção infinita, e o único leitor é uma listagem paginada. No ai9, os 3 e-mails vivos do produto são de identidade (convite, código de acesso, boas-vindas) — e **o código de acesso é a credencial**.
- **Opções:** (a) **metadados sem corpo** (remetente, destinatário, assunto, status, timestamp), com expurgo de 180 dias; (b) corpo incluído, com expurgo curto (30 dias); (c) replicar (corpo, para sempre).
- **Default vigente:** (a).
- **Recomendação:** (a). Guardar o corpo de um e-mail que contém código de login é guardar a credencial em texto puro por outro nome — e é o passivo mais barato de eliminar desta lista.

### P-106 — Quem assina DKIM no ai9: a aplicação ou o provedor de envio?

- **Por que o DEC-30 não resolve:** **D-85** — a chave privada DKIM está **versionada no repositório** (`lib/dkim_private_key.pem`, rastreada pelo git). Não há o que replicar: a chave já vazou por definição e precisa ser rotacionada independentemente da resposta. O que resta decidir (aplicação × provedor) é a forma, não o *se*.
- **Origem:** `Q-89` + `F-32` (fundidas; DS1-4)
- **Fatia:** S18 e S1
- **Trava:** nada no código — é infraestrutura. Mas `OPS-501` fica em aberto, e é **obrigatório antes do cutover**.
- **Impacto:** `só interno`
- **Contexto:** No legado a aplicação assina, e **a chave privada está versionada no repositório**: `lib/dkim_private_key.pem` (1,7 KB, rastreada pelo git), carregada em `config/application.rb:112`, com domínio `safegold.com.br` (`:110`) e seletor `dk` (`:111`). É o **D-85**. A chave precisa ser **rotacionada de qualquer forma** — está exposta a quem tiver o repositório, e o histórico do git não esquece.
- **Opções:** (a) assinatura no provedor de envio, chave fora do repositório; (b) assinatura na aplicação, com a chave em ENV/credentials e rotacionada; (c) não assinar nesta entrega.
- **Default vigente:** (a).
- **Recomendação:** (a). E, independentemente da escolha, **rotacionar a chave atual antes da demo** é item de runbook, não de decisão: ela já vazou por definição.

---

## 5. `EXCEÇÃO-3` — não existe legado a replicar (43)

Feature nova, coisa que nasce da base ai9, escopo, retenção, nomenclatura ou decisão de
plataforma. O princípio é silencioso e a pergunta continua exatamente como estava — a maioria
com um default seguro escrito, que continua valendo se você não responder.

### P-012 — Correção monetária e carência: a tela promete, o cálculo ignora

- **Por que o DEC-30 não resolve:** O DEC-30 **elimina a opção (a)**: a correção monetária e a carência nunca existiram como cálculo (`correct_value = self.total_debt` sempre), então não há regra a implementar sem inventar. O que sobra — remover os dois campos da tela (b) ou mantê-los inertes e rotulados (c) — é decisão de escopo de UI, e nenhuma das opções é "replicar exatamente". O princípio é silencioso.
- **Origem:** `Q-11`
- **Fatia:** S9
- **Trava:** trava `BE-208` e `FE-199` — decide se dois campos existem ou não.
- **Impacto:** `muda número na tela`
- **Contexto:** `interest_rate_correction` e `grace_period` são criados na migration (`db/migrate/20210324173930_create_renegotiations.rb:17,19`), aparecem no formulário e **não são lidos por nenhum cálculo** no repositório inteiro — só por comentários (`renegotiation.rb:247,248,275,277`) e por mensagens de erro traduzidas. O valor corrigido é sempre cópia crua: `renegotiation.rb:93` — `self.correct_value = self.total_debt`. É o **D-47**.
- **Opções:** (a) implementar de verdade — os valores corrigidos passam a divergir do que o cliente vê hoje em toda renegociação com esses campos preenchidos; (b) remover os dois campos da tela e registrar como funcionalidade nunca entregue; (c) manter os campos visíveis e somente leitura, marcados como "não aplicado", até o negócio definir a fórmula.
- **Default vigente:** (b) — DEC-09 manda portar o que **existe**, e o que existe é a coluna, não o cálculo.
- **Recomendação:** (b). Campo que promete correção monetária e não corrige nada num sistema de crédito é pior que campo ausente.

### P-018 — Sobrou limite de risco no formato pré-2022, sem tipo?

- **Por que o DEC-30 não resolve:** Decisão de escopo resolvida por um **fato**, não por opinião: a contagem do dump diz se as 8 colunas `limite_*`/`taxa_*` e o rótulo "Legado" existem ou viram `dropped`. Conferido: o único dump acessível no repositório é `db/seed_assets/sfg_legacy_full.sql` (8,6 MB), que é do sistema **Django anterior** e não tem tabelas `risk_*` — a consulta só pode ser rodada por quem tem o dump de produção.
- **Origem:** `F-07` (T-D1)
- **Fatia:** S5 (executa em S14)
- **Trava:** trava `DB-240`, `OPS-236`, o rótulo "Legado" de `FE-243` e o bloco 0 de S5 (`s5/tasks.md:20`, item 0.1) — mais a decisão de descartar ou não as 8 colunas `limite_*`/`taxa_*`.
- **Impacto:** `muda número na tela`
- **Contexto:** `RiskControl` **mudou de forma em 2022** (`db/migrate/20220611152145_change_risk_control_fields`): deixou de ser 4 modalidades em colunas fixas e passou a ser uma linha por (empresa, portador, tipo). Se sobrou linha sem `risk_operation_type_id`, **ela some de todos os agregados** do ai9 — o limite simplesmente deixa de existir na tela. Isto não é opinião, é uma consulta: **ver a consulta 5 da seção 5**.
- **Opções:** (a) rodar a contagem no dump agora e decidir com o número; (b) assumir zero e descartar as 8 colunas; (c) assumir maior que zero e escrever a rake de conversão sem saber se ela terá o que converter.
- **Default vigente:** (a) — as colunas nascem preservadas e o descarte fica adiado para o ETL.
- **Recomendação:** (a). São cinco segundos de consulta e fecham 2 IDs, um rótulo de tela e o destino de 8 colunas.

### P-047 — O login por Facebook continua existindo?

- **Por que o DEC-30 não resolve:** Não há legado a replicar: no legado o Facebook está morto nas duas pontas (**D-41**, `FACEBOOK_APP_ID = 0` e nenhum botão em view nenhuma). A pergunta é sobre um recurso que **nasce da base ai9** (login social funcionando, com Google junto) — o princípio não alcança.
- **Origem:** `Q-45`
- **Fatia:** S1
- **Trava:** nada — só muda quem consegue entrar.
- **Impacto:** `muda comportamento observável`
- **Contexto:** No legado está morto por duas pontas: `app/definitions/SFG/metadata.rb:4-5` tem `FACEBOOK_APP_ID = 0` e `FACEBOOK_APP_SECRET = 0`, e **não existe nenhum botão de Facebook em nenhuma view** — o formulário de login (`.../sign_in/_sign_in.html.erb:12-43`) tem só login/senha. Os handlers JS ficaram órfãos, ligados a um seletor que nunca casa (`:22,30`), e o provider Devise segue declarado (`engines/auth_omni19/app/decorators/user_decorator.rb:2`). É o **D-41**. No ai9, o login social **funciona** e vem com Google junto.
- **Opções:** (a) manter ligado no ai9 (custo zero, já existe) e anunciar na tela; (b) manter ligado e **não** anunciar até você confirmar; (c) desligar os dois provedores sociais.
- **Default vigente:** (b).
- **Recomendação:** (b), e provavelmente (c) para o Facebook: com **DEC-14** (entrada por código de e-mail ou WhatsApp) e **DEC-18.7** (só por convite), um provedor social a mais é uma superfície de identidade a mais para pouco ganho.

### P-049 — Alguém entra hoje digitando **username** em vez de e-mail?

- **Por que o DEC-30 não resolve:** É decisão de plataforma de identidade: o legado autentica por `username` **ou** e-mail; o ai9 identifica por e-mail ou telefone (DEC-14). Replicar seria acrescentar uma terceira chave de identidade a uma base compartilhada. E precisa do número do dump antes: é possível bloqueador de cutover.
- **Origem:** `Q-47`
- **Fatia:** S14 (dry-run) e S1
- **Trava:** é um possível **bloqueador de cutover**, não de código.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O legado autentica por uma chave genérica: `engines/auth19/config/initializers/devise.rb:14` define `authentication_keys = [:login]`, e a resolução aceita os dois — `engines/auth19/app/models/livetat/auth/user.rb:108`: `where(["lower(username) = :value OR lower(email) = :value", …])`. O próprio campo anuncia: `placeholder="user ou e-mail"` (`.../sign_in/_sign_in.html.erb:22`). Há inclusive um caminho JSON alternativo por `user_name`. No ai9, a identificação é por **e-mail ou telefone** — quem só sabe o próprio `username` perde o acesso no dia 1. **Consulta 6 da seção 5** resolve.
- **Opções:** (a) assumir que ninguém usa e seguir; (b) o dry-run **conta** quantos usuários têm `username` e não têm e-mail válido, e o número decide; (c) portar `username` como identificador alternativo no ai9.
- **Default vigente:** (b) — se houver algum, isto vira bloqueador de cutover.
- **Recomendação:** (b). É uma consulta no dump e responde de vez; (c) só se o número for grande, porque acrescenta uma terceira chave de identidade a uma base compartilhada.

### P-050 — "Verificação: {nível}" — o telefone verificado volta a existir?

- **Por que o DEC-30 não resolve:** O comportamento em questão **não existe no legado**: não há fluxo de verificação de telefone, a flag só vira 1 por mass-assignment e, uma vez ligada, trava o campo para sempre sem saída. No ai9 o telefone é verificado de verdade porque é canal de login (DEC-14) — é coisa que nasce da base, não paridade.
- **Origem:** `Q-48` (funde duas perguntas do mesmo mapa)
- **Fatia:** S1
- **Trava:** trava o desenho do indicador de confiabilidade do perfil.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O nível é calculado numa escada de quatro degraus (`engines/auth19/app/models/livetat/auth/user_info.rb:53-74`) e o degrau mais alto — "Máxima" — depende **só** de `is_phone_checked` (`:59`). Só que **não existe fluxo de verificação de telefone no legado**: a única forma de a flag virar 1 é mass-assignment pelo formulário (`app/decorators/controllers/registrations_decorator.rb:104`), e, uma vez ligada, ela **trava o campo de telefone para sempre** (`.../my_account/parts/phone/_container.js.erb:14-16`, `prop('readonly')`). O degrau máximo é inalcançável e o campo fica preso sem saída. **Verificado, e por isso não pergunto separado:** o nível **não decide nenhuma regra de negócio** — a única leitura fora da exibição é `user_decorator.rb:272`, que expõe `nice_info` num JSON. No ai9 o telefone **é verificado de verdade**, porque é canal de login (DEC-14).
- **Opções:** (a) marcar como verificado quando a pessoa entrar por código de WhatsApp/SMS naquele número, e o campo deixa de travar sem saída; (b) remover o indicador de confiabilidade inteiro (ele não decide nada); (c) replicar como está.
- **Default vigente:** (a).
- **Recomendação:** (a). O ai9 torna verdadeiro um indicador que no legado era decorativo, e o custo é zero porque a verificação já acontece no login.

### P-051 — Onde ficam os arquivos em produção?

- **Por que o DEC-30 não resolve:** Infraestrutura da base ai9: `backend/config/storage.yml` só declara `local`. Não há legado a replicar (o legado grava em disco da máquina via kt-paperclip) — é decisão de plataforma, e trava o cutover, não a demo.
- **Origem:** `Q-49` + `F-41` (fundidas; levantada em dois mapas)
- **Fatia:** S18 e S13, com efeito em S9 (anexos de renegociação) e S17
- **Trava:** não trava a demo. **Trava o cutover**, e o runbook de S14.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A base ai9 só tem serviço de disco local: `backend/config/storage.yml` declara apenas `local` e `test`, e `backend/config/environments/production.rb:10` faz `config.active_storage.service = :local`. Ou seja, **produção grava anexo no disco do container**. Sem volume persistente garantido pelo deploy, **anexo desaparece entre deploys** — avatar, logo e, principalmente, os documentos de renegociação, que são documento financeiro (`s9/design.md:179-183`). No legado tudo vive em `public/system/:attachment/:id/…` no disco da máquina, via kt-paperclip (11 anexos, 44 colunas).
- **Opções:** (a) escolher provedor agora (S3, GCS, R2…) e configurar; (b) `Disk` com **volume persistente garantido** pelo deploy, com o requisito de infraestrutura documentado; (c) `Disk` para a demo, e a decisão de provedor vira item **obrigatório** do runbook de cutover.
- **Default vigente:** (c).
- **Recomendação:** (c) para sexta, com (a) ou (b) **escrito no runbook com data**. Documento financeiro privado em disco de container é o tipo de decisão que só aparece quando o arquivo já sumiu — normalmente no primeiro redeploy depois da venda.

### P-052 — Com DEC-14 (sem senha), o que dizem os e-mails "Perdeu a senha?" e "Nova senha configurada"?

- **Por que o DEC-30 não resolve:** Nasce da DEC-14: o produto não tem mais senha. Não há regra do legado a preservar — o que se decide é o texto de dois e-mails cujos gatilhos continuam válidos.
- **Origem:** `Q-50`
- **Fatia:** S1
- **Trava:** trava `BE-481` e `BE-482`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** São dois e-mails cujo assunto e corpo falam de uma coisa que o produto **não tem mais**: o ai9 não tem senha em lugar nenhum (verificado — nenhuma coluna `encrypted_password`, `devise :omniauthable` e nada mais). Mas os gatilhos continuam fazendo sentido: "pedi um novo acesso" e "minha credencial mudou".
- **Opções:** (a) preservar os gatilhos e **reescrever os textos** ("Seu código de acesso" / "Seu acesso foi alterado"), registrando no `improvements-log`; (b) não portar os dois e-mails; (c) portar os textos como estão.
- **Default vigente:** (a).
- **Recomendação:** (a). Um e-mail que fala de senha num produto sem senha é o tipo de detalhe que o cliente nota numa demo.

### P-057 — O autopreenchimento por CNPJ (ReceitaWS) volta a funcionar?

- **Por que o DEC-30 não resolve:** Escopo: a UI está morta em duas pontas (**D-27**, botão comentado e ERB escapado), então não existe comportamento a replicar — existe um backend pago e configurado esperando um botão. Decidir religar é decidir escopo, e o custo por consulta é do cliente.
- **Origem:** `Q-55`
- **Fatia:** S4 (empresas e fornecedores)
- **Trava:** nada — é um botão.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O backend está **vivo e configurado**: gem no `Gemfile.linux:39`, `config/initializers/receitaws.rb:5` (token), `:10` (cache de 365 dias), `:14` (timeout de 10 s), serviço em `app/helpers/cnpj_api.rb:3` e endpoint em `app/controllers/pub/providers_controller.rb:121-133`. A UI está **duplamente morta**: o botão está comentado (`.../providers/helper/_body.html.erb:54-56`) e a URL do JS tem ERB escapado (`.../helper/_body.js.erb:155` usa `<%%=`, então o literal chega ao navegador). É o **D-27**, e a integração é **paga**. **Nota de segurança que sai junto:** o token real está versionado no repositório (`config/application.arch.yml:12`) e precisa ser rotacionado de qualquer forma (ver P-107).
- **Opções:** (a) ligar (o endpoint existe, o custo é reconectar o botão); (b) não portar; (c) ligar com limite de chamadas por usuário/dia, por causa do custo por consulta.
- **Default vigente:** (a).
- **Recomendação:** (c). É a mesma feature, com a única precaução que o legado não tinha — e o custo por consulta é seu, não nosso.

### P-058 — O logo do Portador volta a existir?

- **Por que o DEC-30 não resolve:** Escopo: o upload está comentado no formulário e a exibição comentada na lista (**DC-10**). Não há comportamento a replicar; o que se decide é se um campo morto volta a existir.
- **Origem:** `Q-56`
- **Fatia:** S3 (cadastros globais)
- **Trava:** nada.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Está morto por metade: o bloco HTML do upload está comentado no formulário (`.../carriers/helper/_body.html.erb:13-23`, com o `file_field` na linha 21) e a exibição está comentada na lista (`.../carriers/list/_widget.html.erb:3-12`) — mas o handler JS está vivo, ligado a um input que não existe (`.../helper/_body.js.erb:12-13`), o `permit` aceita `logo` (`carriers_controller.rb:140`) e o model tem o anexo completo, com validações (`app/models/carrier.rb:16,32-33,79-80`). É o **DC-10**. Os outros anexos de logo do legado são **projeto** (`project.rb:48`, `avatar`) e **fornecedor** (`provider.rb:12`, `logo`) — **`Company` não tem anexo nenhum**.
- **Opções:** (a) ligar, reusando a mesma pilha ActiveStorage dos outros dois; (b) não portar; (c) ligar e acrescentar também logo de empresa (feature nova).
- **Default vigente:** (a).
- **Recomendação:** (a). É um campo, a coluna já existe, e o dry-run precisa contar quantos portadores têm arquivo antes de migrar binários.

### P-059 — A coluna `default_position` existe no banco de produção?

- **Por que o DEC-30 não resolve:** Fato, não opinião — e o fato revisita o **DEC-04**. Se `default_position` não existe no banco, a busca de padrões globais está quebrada há anos; se existe, é a segunda prova de schema fora do versionamento. *(Achado adjacente independente: `:21` monta o `where!` com fragmento SQL malformado.)*
- **Origem:** `Q-57`
- **Fatia:** S11 (padrões de disponibilidade)
- **Trava:** nada para começar. É uma consulta no dump — **consulta 1 da seção 5**.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/controllers/pub/availability_templates_controller.rb:22` ordena a busca por `default_position`, e a coluna aparece também em três views. **Nenhuma migration a cria** — as migrations criam `position` e `parent_position` (`db/migrate/20210420180734_create_availability_templates.rb:22,24`). Se a coluna **não** existe, a busca de padrões globais está quebrada em produção há anos e ninguém reclamou; se **existe**, é a segunda prova de schema fora do versionamento (junto com `contracts.description`, D-108) e o **DEC-04** precisa ser revisitado com o dump em mãos. **Achado adjacente na mesma action:** a linha `:21` monta o `where!` com um fragmento SQL malformado (`"title #{Dev.ilike} "`, sem o placeholder) — a busca por texto tem um segundo problema, independente da coluna.
- **Opções:** (a) assumir que não existe; a busca nasce ordenada pela hierarquia e registra-se para o dry-run confirmar; (b) rodar `\d availability_templates` no dump agora e decidir com o fato; (c) criar a coluna no ai9 de qualquer forma.
- **Default vigente:** (a).
- **Recomendação:** (b). A consulta leva um minuto e também fecha o DEC-04, que hoje carrega o risco como "aceito e documentado".

### P-060 — As 4 rotas públicas de auto-cadastro da base ai9: tirar da allowlist ou gatear pela flag?

- **Por que o DEC-30 não resolve:** As 4 rotas **nunca vieram do legado** — são da base ai9 (`api/root.rb:36,38,45,46`). As duas opções vivas fecham o buraco; o que continua aberto é a decisão de **tocar a base compartilhada** (Princípio 6b), que é plataforma, não paridade.
- **Origem:** `F-22`
- **Fatia:** S1 (a rota) e S19 (a flag `FE-444`)
- **Trava:** nada hoje — S1 tarefa 2.1 já manda tirar. O que falta é a **decisão de tocar a base compartilhada**.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Conferido em `backend/app/controllers/api/root.rb:36,38,45,46` — `pre_register`, `complete_registration`, `visitor_signup` e `visitor_signup_with_link` estão na **allowlist pública**. Ou seja: o **D-39** (auto-cadastro público), que o DEC-18.7 desligou do lado do legado, **volta sozinho** por essa porta, que nunca veio do legado. S1 tarefa 2.1 manda retirar as 4 e a 2.2 manda desmontar os endpoints em `api/auth/v1/registration.rb`; S19 constrói a flag `public_create_user?` nascendo `false`. **A tensão:** `api/root.rb` e `registration.rb` são da **base compartilhada** (Princípio 6b — não refatorar a base), e outros produtos ai9 podem usar essas rotas.
- **Opções:** (a) **remover** as 4 rotas da allowlist e desmontar os endpoints, como S1 escreveu — resolve de vez, mas altera a base para todo mundo; (b) manter as rotas e gateá-las pela flag `public_create_user?` de S19, que nasce `false` — a base fica intacta e o Safegold fica fechado; (c) (a) no Safegold e uma flag de upstream para a base decidir depois.
- **Default vigente:** (a), escrito nas tarefas de S1 — **mas a decisão de mexer na base não foi tomada por ninguém.**
- **Recomendação:** (b). A flag vai ser construída de qualquer jeito, e é a única opção que não deixa o Safegold dependendo de uma remoção que outro produto pode reverter na semana seguinte.

### P-062 — A trilha de auditoria global é visível a que papéis?

- **Por que o DEC-30 não resolve:** Feature nova: o legado não tem trilha global (a caseira cobre só 2 jobs). Quem enxerga uma trilha que não existia é decisão de escopo e autorização de algo novo.
- **Origem:** `F-23`
- **Fatia:** S19
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A trilha global é um **índice de tudo que aconteceu no sistema**: quem viu o quê, quem alterou o quê, quando. O histórico **do próprio objeto** (o "quem mexeu nesta renegociação") é outra coisa, e não está em questão aqui.
- **Opções:** (a) trilha global só para OG/Admin; histórico do objeto para quem vê o objeto; (b) trilha global para todos os papéis; (c) trilha global para OG/Admin/Gerente.
- **Default vigente:** (a), declarado pelo agente por conta própria.
- **Recomendação:** (a). É o único caso desta lista em que o default mais restritivo também é o mais barato de afrouxar depois.

### P-063 — A trilha guarda o payload completo do objeto?

- **Por que o DEC-30 não resolve:** Feature nova + **retenção**. Não há payload legado a replicar.
- **Origem:** `F-24`
- **Fatia:** S19
- **Trava:** nada no código, mas a forma da tabela `trackings` depende disso.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Trilha que copia o registro inteiro vira o maior objeto do banco em três meses, e num sistema financeiro isso significa **duplicar dado pessoal e financeiro sem política de retenção**. S13 já registrou que o expurgo é requisito novo.
- **Opções:** (a) payload enxuto (evento, entidade, autor, campos alterados); (b) payload completo (a foto inteira do registro); (c) payload enxuto por padrão e completo só para um conjunto **nomeado** de entidades críticas.
- **Default vigente:** (a).
- **Recomendação:** (a). Se aparecer necessidade de foto completa, (c) é aditivo e não quebra nada do que for construído agora.

### P-064 — O CSP nasce em `report-only` ou bloqueando?

- **Por que o DEC-30 não resolve:** A base ai9 nunca teve CSP. Não há legado a replicar; é decisão de plataforma.
- **Origem:** `F-26`
- **Fatia:** S18
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A base ai9 **nunca teve CSP**. Ligar bloqueante numa base que nunca teve **quebra tela em silêncio** — recurso bloqueado não dá erro visível, só some.
- **Opções:** (a) `report-only` primeiro, com **prazo escrito** para virar bloqueio; (b) bloqueante desde o início; (c) `report-only` sem prazo.
- **Default vigente:** (a), declarado pelo agente.
- **Recomendação:** (a). Numa demo comercial, tela quebrada em silêncio é o pior modo de falha possível — e (c) é como CSP nunca vira bloqueio em lugar nenhum.

### P-065 — `WhatsappPage.tsx` existe e não está roteada. Ganha rota?

- **Por que o DEC-30 não resolve:** `WhatsappPage.tsx` é componente **da base ai9** sem rota. Nada disso existe no legado.
- **Origem:** `F-28` (DS2-2)
- **Fatia:** S2 (dependência de S1)
- **Trava:** nada hoje — mas o login por WhatsApp (DEC-14) **cai** quando a sessão da instância expirar, e ninguém terá como parear.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `frontend/src/app/pages/WhatsappPage.tsx` existe na base e **não tem rota**. É a tela de pareamento por QR de que `EvolutionConnection.send_message` depende via `PolemkInstance.first`. Sem ela, um canal de login do produto tem prazo de validade e nenhuma forma de renovação pelo cliente. Decisão declarada pelo agente: **ganha rota**, gateada por papel administrativo (`s2/design.md:101`).
- **Opções:** (a) rota gateada por OG/Admin; (b) sem rota — o pareamento é feito por console/rake pela equipe da Livetat; (c) rota gateada só por OG.
- **Default vigente:** (a).
- **Recomendação:** (a).

### P-066 — O seletor de idioma fica visível numa interface que não traduz nada?

- **Por que o DEC-30 não resolve:** O runtime de i18n é da base ai9 e não traduz nada; o legado é 100% pt-BR hardcoded (**D-115**). É decisão de plataforma sobre um componente que não veio do legado.
- **Origem:** `F-30` (DS2-5)
- **Fatia:** S2
- **Trava:** nada — só muda o resultado.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A base **tem** o runtime de i18n (`i18next`, `react-i18next`, bundles) e **não traduz nada**: zero componentes chamam `useTranslation`, o bundle `pt-br` tem 255 chaves de marketing de **outro produto**, e o `LanguageSwitcher` não troca idioma. DEC-09 fixou pt-BR. A decisão declarada é **não ligar** (`s2/design.md:104`).
- **Opções:** (a) não ligar, e registrar como flag de upstream; (b) não ligar **e remover** o `LanguageSwitcher` da interface, para ninguém clicar num botão que não faz nada; (c) ligar o i18n.
- **Default vigente:** (a).
- **Recomendação:** (b). Um seletor de idioma visível que não troca idioma é exatamente o tipo de coisa que um técnico do cliente clica na demo.

### P-070 — `resource_kinds`: portar ou descartar? Uma contagem decide 9 IDs

- **Por que o DEC-30 não resolve:** Escopo por contagem: zero significa 9 IDs `dropped` **com evidência** e S8 encolhe. O default já resolve o conservador (a tabela e o seed nascem, a superfície fica bloqueada) — falta o número.
- **Origem:** `Q-61` + `F-34` (fundidas; levantada em dois mapas)
- **Fatia:** S6 e S8 — são **9 IDs** (`BE-307`, `BE-720`…`BE-724`, `FE-307`, `DB-286`, `DB-289`, `DB-294`)
- **Trava:** trava o escopo de S8 e o bloco 0 (`s8/tasks.md:26, 104, 146, 168-169`). **Consulta 2 da seção 5** resolve.
- **Impacto:** `muda escopo`
- **Contexto:** A entidade tem CRUD completo (controller, views, rotas) e é **inalcançável pelo menu**: `application_helper.rb:153` só tem `resource_sources`; `resource_kinds` só abre digitando a URL. A coluna `receivable_entries.resource_kind_id` existe (`db/migrate/20210315183541_create_receivable_entries.rb:11`) e está no `permit` (`receivables_controller.rb:191`), mas **não há campo no formulário** e `receivable_entry.rb` **não declara `belongs_to :resource_kind`** — o único lado da associação é o inverso, em `resource_kind.rb:2`. Os dois flags da entidade (`is_conta_corrente`, `is_unique`) não têm nenhum leitor de regra. E ela **não participou da importação**: `app/models/legacy.rb:2-15` lista `ResourceSource` e não `ResourceKind`.
- **Opções:** (a) rodar a contagem no dump — zero significa `dropped` **com evidência**, e S8 encolhe 9 IDs; (b) portar tudo por precaução; (c) descartar sem consultar.
- **Default vigente:** (a) — a tabela e o seed nascem de qualquer forma (preservar dado é barato, perdê-lo é irreversível), com a **superfície** bloqueada até a contagem.
- **Recomendação:** (a). Se vier zero, a tarefa 13.4 já está escrita: remover a tabela numa tarefa explícita, **nunca por omissão**. É a mesma consulta que resolve P-041: se `resource_kinds` cai, aquela pergunta desaparece junto.

### P-071 — `receivable_entries.observacoes`: campo visível, fundido ou descartado?

- **Por que o DEC-30 não resolve:** O DEC-30 **elimina a opção (c)**: há texto de negócio real gravado por `legacy/receivable_entry.rb:56` (`observacoes: i.bor_obs`), e descartar perderia dado. Mas nenhuma das opções restantes é "replicar" — o legado nem exibe o campo. Tornar visível (a) ou fundir com `description` (b) é escopo de tela.
- **Origem:** `Q-62`
- **Fatia:** S6
- **Trava:** trava `DB-155`.
- **Impacto:** `muda escopo`
- **Contexto:** A coluna existe (`db/migrate/20210315183541_create_receivable_entries.rb:43`) e está no `permit` (`receivables_controller.rb:223`), mas **não há input no formulário** e nenhuma view a lê. Tem até tooltip órfão no YAML de ajuda (`receivables_help_inputs.yml:35`). O **único escritor real** é o importador: `app/models/legacy/receivable_entry.rb:56` grava `observacoes: i.bor_obs` — ou seja, **há texto de negócio gravado ali que ninguém nunca viu na tela**.
- **Opções:** (a) tornar o campo visível (ele já tem conteúdo vindo do sistema antigo); (b) fundir com `description`; (c) descartar.
- **Default vigente:** (a) — há dado real dentro.
- **Recomendação:** (a). Um campo de observação importado do sistema anterior e invisível há anos é justamente o tipo de coisa que o cliente pergunta "cadê?" na primeira semana.

### P-072 — Renomear anexo de renegociação entra no escopo?

- **Por que o DEC-30 não resolve:** Nunca funcionou para ninguém: `update_attributes` (removido no Rails 6.1) sobre uma variável que não existe naquele controller, com o `respond_to` comentado. Não há comportamento a replicar.
- **Origem:** `Q-63`
- **Fatia:** S9
- **Trava:** trava `BE-228`.
- **Impacto:** `muda escopo`
- **Contexto:** A funcionalidade foi pretendida e **nunca entregue**. `app/controllers/pub/renegotiation_attachments_controller.rb:51` chama `@renegotiation_attachment.update_attributes(renegotiation_params)` — com **dois** erros na mesma linha: `renegotiation_params` não existe neste controller (só `renegotiation_attachment_params`, `:104`), e `update_attributes` foi removido no Rails 6.1. O `respond_to` da action está inteiramente comentado (`:54-59`). Nunca funcionou para ninguém.
- **Opções:** (a) não portar (DEC-09: não existe); (b) implementar — é uma tela de renomear, custo baixo; (c) não portar agora e registrar no ledger como intenção não concluída.
- **Default vigente:** (c).
- **Recomendação:** (c). Nome de anexo importa em documento de renegociação, mas a decisão é sua: o legado nunca ofereceu isso a ninguém.

### P-073 — A aba PAGAMENTOS da renegociação entra no escopo?

- **Por que o DEC-30 não resolve:** Aba comentada na view — não existe comportamento em produção a replicar. O que se decide é se um backend órfão ganha tela.
- **Origem:** `Q-64`
- **Fatia:** S9
- **Trava:** trava `FE-229`.
- **Impacto:** `muda escopo`
- **Contexto:** A aba está comentada na view (`.../renegotiations/detail/_body.html.erb:22`) e a lista de abas só declara "GERAL" e "PREVISÕES" (`:15`) — é o **D-53**, a causa de o painel não fechar. O botão "Excluir todas as parcelas" também está comentado (`.../tabs/_tab_renegotiation_installment.html.erb:11-15`). Mas o **backend dos dois continua vivo e órfão**: `renegotiations_controller.rb:76` e `:125` (`show_remove_all_option`), `renegotiation.rb:61-70` (`batch_destroy_installments!`) e o JS que mostra/esconde um botão que não existe.
- **Opções:** (a) portar a aba PAGAMENTOS (o backend está pronto) e **não** portar o botão de excluir em massa; (b) portar os dois; (c) não portar nenhum dos dois.
- **Default vigente:** (a) — a aba fecha um buraco visível no painel; excluir todas as parcelas de uma renegociação sem transação é operação destrutiva que ninguém pediu.
- **Recomendação:** (a). Se o excluir em massa for necessário, ele volta como ação explícita com confirmação e trilha — não como botão comentado que alguém descomenta.

### P-075 — O percentual de aceite por contrato volta?

- **Por que o DEC-30 não resolve:** Comentado nos dois únicos lugares em que aparecia, **sem comentário explicando por quê**. Não há comportamento vivo a replicar.
- **Origem:** `Q-66`
- **Fatia:** S12
- **Trava:** trava `BE-344`.
- **Impacto:** `muda escopo`
- **Contexto:** Está comentado nos **dois** únicos lugares em que aparecia: na lista (`.../contracts/list/_widget.html.erb:18`, *"Aceito por X dos usuários"*) e no detalhe (`.../contracts/detail/_body.html.erb:66`). O método que o calcula, `Contract#accept_users` (`app/models/contract.rb:23-25`), ficou sem nenhum chamador ativo. **Não há comentário explicando por que foi desligado** — pode ter sido performance (a conta é um `count` sobre `contract_deals`) ou pode ter sido por estar errada.
- **Opções:** (a) reativar, com a contagem feita em consulta e não em Ruby; (b) não portar; (c) reativar só no detalhe, não na lista (onde o custo por linha se multiplica).
- **Default vigente:** (b) — está comentado em produção e não se sabe por quê.
- **Recomendação:** (c). É a informação que dá sentido a ter um ciclo de aceite (P-020), e no detalhe o custo é uma consulta por página.

### P-078 — A posição diária de risco (`RiskEntry`) volta a ter tela?

- **Por que o DEC-30 não resolve:** Escopo por contagem, e com um agravante que não é opinião: os 15 campos são hardcode dos 4 tipos originais e **não acompanham o `RiskOperationType` dinâmico** de 2022 — portar a tela como está entregaria algo que não funciona com os tipos atuais. Não existe view nenhuma no legado.
- **Origem:** `Q-69` + `F-36` (fundidas; T-D2)
- **Fatia:** S5/S7 — a fatia R8 fica bloqueada sem resposta
- **Trava:** trava `BE-269`, `DB-231`, `FE-234`, o bloco R8 e as tarefas 1.7 e 6.1 de S5 (`s5/tasks.md:23, 40, 93`).
- **Impacto:** `muda escopo`
- **Contexto:** A tabela e as regras estão vivas e há dado em produção, mas **não existe nenhuma view** — não há `app/views/pub/risk_entries` nem `.../parts/risk_entries`, e o controller aponta para templates inexistentes (`risk_entries_controller.rb:6,29,39,47,56`), com as rotas ainda no ar (`config/routes.rb:163-164`). **Não há item de menu nenhum**; o que está comentado é a **aba** (`.../risk/_body.html.erb:30`) e o handler do botão "Cadastrar posição". O problema de fundo: os **15 campos são hardcode dos 4 tipos originais** (Auto Liquidável, Fomento, Comissária, Intercompany — `db/migrate/20210510211736_create_risk_entries.rb:7-15` e duas alterações de 2022) e **não acompanham o `RiskOperationType` dinâmico** que existe desde 2022. Portar a tela como está entrega algo que **não funciona com os tipos atuais**. **Consulta 4 da seção 5** diz se há dado.
- **Opções:** (a) portar tabela e model (o dado sobrevive) e deixar a fatia R8 **sem endpoint e sem tela**; (b) remodelar por tipo dinâmico e entregar a tela — é feature nova, contra DEC-09; (c) descartar tudo com evidência.
- **Default vigente:** (a).
- **Recomendação:** (a), com a consulta rodada: se `risk_entries` estiver vazia, isto vira (c) e a fatia some com evidência. (b) é remodelagem, não migração; (c) sem a consulta perde dado que não volta.

### P-079 — Alerta de estouro de limite em tempo real entra?

- **Por que o DEC-30 não resolve:** Feature nova, e o legado nem faz polling nem renderiza gráfico. **DEC-21.1** já deixou "utilização de limite" para depois da venda.
- **Origem:** `Q-70`
- **Fatia:** S5
- **Trava:** nada — é escopo novo.
- **Impacto:** `muda escopo`
- **Contexto:** Confirmado na fonte: **o legado não faz polling em nenhuma tela deste bloco** e não renderiza gráfico nenhum (`vendor/doughnut` é pendurado no `global` em `app/frontend/vendor/js/index.js.erb:31,37` e **zero views o instanciam**; `grep "new Chart"` também é vazio). Logo, um alerta de estouro é **feature nova** (DEC-09), não paridade. Menciono porque é o candidato mais natural que o produto tem: o painel de risco existe, os limites existem, o cálculo de utilização existe.
- **Opções:** (a) não entra; (b) entra como **aviso na própria tela** quando a utilização passa do teto (custo baixo, o número já é calculado); (c) entra com notificação ativa (e-mail/WhatsApp) — subsistema novo.
- **Default vigente:** (a) — coerente com **DEC-21.1**, que explicitamente deixou "utilização de limite" para depois da venda.
- **Recomendação:** (a). O `NEW-002` (dashboard) já mostra "limites próximos do teto", então a demo cobre a ideia sem abrir uma frente nova.

### P-082 — Excluir lançamento de indicador é feature viva?

- **Por que o DEC-30 não resolve:** Escopo com default **conflitante** (mapa (a) × empacotamento (b)) e nenhuma tela chama a action hoje. Não há comportamento a replicar — a rota existe e nada a alcança. **Responda junto com P-037**: sem distinguir "não lançado" de "lançado como zero", excluir e zerar produzem exatamente a mesma tela.
- **Origem:** `Q-73` + `F-20` (fundidas; T-D12)
- **Fatia:** S10
- **Trava:** trava `BE-328`, o bloco 0 de S10 (`s10/tasks.md:30`) e a tarefa 5.5.
- **Impacto:** `muda escopo`
- **Contexto:** A rota existe (`config/routes.rb:84`) e a action também (`indicator_entries_controller.rb:75-85`), mas **nenhuma tela a chama**: zero ocorrências de excluir/remover/`data-method: :delete` em toda a pasta de views de lançamentos. O controller nem tem o template do formulário que renderiza em `:34` e `:42`; e o ramo de erro referencia um template inexistente — dá 500 dentro de um 200. Na prática, "zerar" é digitar `0` no campo inline e submeter — o registro continua existindo.
- **Opções:** (a) não portar a exclusão (só zerar, como hoje); (b) construir, com confirmação e autorização, e a célula voltando ao estado "não lançado"; (c) `dropped` com evidência de que nenhuma tela a chama; (d) construir só o endpoint, sem botão na tela.
- **Default vigente:** conflitante — o mapa fixou (a) (nada a portar), o empacotamento fixou (b) (a rota existe e DEC-09 manda portar o que existe). **Precisa da sua palavra.**
- **Recomendação:** (b), **mas responda junto com P-037**. As duas são a mesma moeda: sem distinguir "não lançado" de "lançado como zero", excluir e zerar produzem exatamente a mesma tela, e a feature não tem sentido nenhum.

### P-085 — A área de temas existe no ai9 como CRUD, ou a marca vira configuração?

- **Por que o DEC-30 não resolve:** Não há motor de tema a replicar: o CSS do template está **inteiramente dentro de um comentário** (**D-55**), e a área não tem item de menu (**D-63**). A pergunta é de escopo puro — e é a que pode economizar a fatia S17 inteira. Default **divergente entre os dois mapas**.
- **Origem:** `Q-76` (levantada em dois mapas, **com defaults divergentes**)
- **Fatia:** S17 — a fatia inteira depende desta resposta
- **Trava:** trava **S17 inteira**; pode economizar a fatia.
- **Impacto:** `muda escopo`
- **Contexto:** O motor de temas do legado **não pinta nada**: o CSS do template está integralmente dentro de um comentário — `app/frontend/css/pub/templates/app_theme_template.css`, 167 linhas, abre `/*` na linha 1 e fecha `*/` na 167, **sem uma única regra fora dele** (**D-55**). E o parser continua rodando em cima disso: `app_theme.rb:207-231` lê o arquivo, substitui as variáveis de cor e grava em `cached_css`, que as views injetam num `<style>` — sempre um comentário CSS inteiro. Além disso, a área **não tem item de menu** (zero ocorrências de "themes" em `application_helper.rb` e no menu) e o `else` do `fetch_resource` redireciona para `dash` (`console_controller.rb:402-405`) — **D-63**. Na prática, o tema só controlava logos e o branding de 3 e-mails.
- **Opções:** (a) implementar a área completa (CRUD de tema, precedência, tokens em runtime), como o inventário pede; (b) **não** portar a tela: marca e paleta viram tokens do app, light/dark fica no `ThemeToggle` que já existe no ai9, e S17 encolhe para "marca em fonte única"; (c) meio-termo: tema como **configuração única** editável (uma tela, um tema), sem CRUD nem precedência.
- **Default vigente:** **divergente entre os dois mapas** — um propõe (b), o outro propõe (a). **Precisa da sua palavra.**
- **Recomendação:** (c). Multi-tema num sistema de um cliente só é complexidade sem uso; mas o cliente vai querer trocar o logo sem abrir um chamado.

### P-086 — `UserTheme` (tema por usuário): requisito abandonado ou feature a ressuscitar?

- **Por que o DEC-30 não resolve:** Escopo, e dependente de P-085: `UserTheme` **nunca aparece em nenhuma opção** da UI. Portar um STI para um subtipo que nunca teve tela é decisão de escopo, não de paridade.
- **Origem:** `Q-77` + `F-27` (fundidas; Q-19 de S17)
- **Fatia:** S17
- **Trava:** trava `BE-379` e metade de `BE-380`.
- **Impacto:** `muda escopo`
- **Contexto:** O tipo existe de verdade: `app/models/user_theme.rb:2` declara `has_many :users` e a coluna está criada (`db/migrate/20200206191948_add_app_theme_column_to_livetat_auth_user.rb:3`). Mas o `select` do formulário oferece **apenas** `GlobalTheme` (`.../themes/form/_body.html.erb:36` e `.../themes/helper/_body.html.erb:16`) — `UserTheme` **nunca aparece em nenhuma opção** e é inalcançável pela UI. Só `GlobalTheme` é referenciado em runtime. No ai9, mantê-lo significa implementar uma precedência de três níveis (usuário → global → fábrica) em que o nível de usuário **nunca é escrito por nada**.
- **Opções:** (a) portar o **tipo** (a coluna e o STI, porque pode haver dado) e **não** expor a criação de `UserTheme` na UI — igual ao legado; (b) descartar o tipo inteiro, e a precedência passa a ter dois níveis; (c) implementar tema por usuário de verdade, com tela.
- **Default vigente:** (a).
- **Recomendação:** (b), **se** P-085 for respondida com (b) ou (c). Portar um STI para um subtipo que nunca teve UI é carregar complexidade de graça; e no ai9 a preferência por usuário já existe como light/dark, que é o controle que o usuário corporativo espera.

### P-087 — `generic_rating` (avaliação por estrelas) é usado em alguma tela?

- **Por que o DEC-30 não resolve:** Só existe o **CSS**: zero ocorrências de `app_rating_widget`/`generic_rating` em `.erb`, `.rb` ou `.js`. Não há comportamento a replicar. *O default (a) resolve; a confirmação é formalidade.*
- **Origem:** `Q-78`
- **Fatia:** S19 / S2
- **Trava:** trava `BE-013` do inventário de componentes.
- **Impacto:** `muda escopo`
- **Contexto:** Só existe o **CSS** — `app/frontend/css/pub/recyclable/generic_rating.scss` (classe `.app_rating_widget`), importado em `recyclable.scss:7`. **Zero ocorrências** de `app_rating_widget` ou `generic_rating` em qualquer `.erb`, `.rb` ou `.js` do repositório. Não há model, controller, rota nem partial. É CSS morto, provável resquício de outro produto da Livetat.
- **Opções:** (a) descartar com evidência no ledger; (b) portar o componente para a biblioteca do ai9 mesmo sem consumidor.
- **Default vigente:** (a).
- **Recomendação:** (a). Com a evidência acima não há nem o que discutir — e se aparecer uso, é um componente pequeno de recuperar.

### P-088 — A citação aninhada em respostas de mensagem (`quoted_note_id`) é usada?

- **Por que o DEC-30 não resolve:** A coluna **nunca foi escrita**: a UI não tem campo, hidden input nem parâmetro AJAX que a preencha. É a diferença em relação a P-069/P-080/P-081 — lá há dado gravado a preservar, aqui não há dado nenhum. Escopo de esquema.
- **Origem:** `Q-79`
- **Fatia:** S2
- **Trava:** trava o desenho da tabela de notas do feedback.
- **Impacto:** `muda escopo`
- **Contexto:** O backend está completo e vivo: `engines/feedback19/app/models/livetat/feedback19/note.rb:6` (`belongs_to :quoted`), a lógica que deriva `top_parent_quote_id` (`:17-23`), o `permit` (`notes_controller.rb:90`) e a coluna (`db/migrate/20170516185759_create_livetat_feedback_notes.rb:9`). Mas a UI **nunca a preenche**: zero ocorrências de `quoted` em qualquer view ou JS do engine ou do app. Nenhum campo, hidden input ou parâmetro AJAX a envia.
- **Opções:** (a) não portar a citação aninhada (uma coluna e uma associação a menos numa tabela nova); (b) portar o esquema sem UI; (c) portar com UI (feature nova).
- **Default vigente:** (a).
- **Recomendação:** (a). Acrescentar depois é aditivo e não quebra nada — e uma thread de mensagens interna raramente precisa de citação aninhada.

### P-090 — O item de menu `reports` entra?

- **Por que o DEC-30 não resolve:** **O item nem existe**: nenhum item da lista tem `identifier: "reports"`, então a condição nunca é verdadeira. Código morto guardando um identificador fantasma — não há comportamento a replicar.
- **Origem:** `Q-81`
- **Fatia:** S2
- **Trava:** trava `NAV`.
- **Impacto:** `muda escopo`
- **Contexto:** O material descrevia `reports` como um item de menu marcado `inactive`. Conferido: (1) não está no helper — está na **view** do menu, `app/views/pub/console/base/menu/_container.html.erb:24`, como `<%= 'inactive' if i[:identifier] == "reports" %>`; (2) **o item nem existe** — a lista é montada em `application_helper.rb:103-171` e nenhum item tem `identifier: "reports"`, então a condição nunca é verdadeira; (3) não há rota, controller nem `when "reports"` no `fetch_resource`. É código morto guardando um identificador fantasma. O item mais próximo, `{ identifier: "results", title: "Resultados" }`, está **comentado** em `application_helper.rb:118`.
- **Opções:** (a) não portar nada (nem o item, nem o mecanismo `inactive`); (b) portar o mecanismo de item inativo, sem item marcado; (c) descobrir o que era "Relatórios"/"Resultados" e escopar.
- **Default vigente:** (a).
- **Recomendação:** (a), e vale a pergunta lateral: havia uma tela de **Resultados** planejada e comentada. Se o cliente sente falta de relatórios, isso é escopo de pós-venda, não paridade.

### P-091 — A tabela `geolocations` tem linhas? Um `SELECT count(*)` decide 12 IDs

- **Por que o DEC-30 não resolve:** O maior portão de escopo por consulta única da migração: 12 IDs. E a associação polimórfica **não tem lado inverso nenhum** no repositório inteiro. Precisa do número do dump.
- **Origem:** `Q-82` + `F-35` (fundidas)
- **Fatia:** S13 (e S19, por P-092)
- **Trava:** trava as tarefas 6.5–6.9 de S13 e **12 IDs**: `DB-592`, `DB-431`, `DB-480`, `OPS-481`, `OPS-482`, `FE-483`, `BE-435`…`BE-440` (`s13/tasks.md:26-30`). **Consulta 3 da seção 5.**
- **Impacto:** `muda escopo`
- **Contexto:** O model existe e é grande (`app/models/geolocation.rb`, com cálculo de distância via Geocoder em `:164-171`), mas **nenhum model declara `has_one`/`has_many :geolocation`** — zero resultados no repositório inteiro. E `geolocatable` só aparece dentro do próprio `geolocation.rb` (`:6,7,9,175`) e na migration (`db/migrate/20160302002809_create_geolocations.rb:4`). A associação polimórfica **não tem lado inverso nenhum**. É o maior portão de escopo por consulta única da migração. **Correção ao material (A-24):** o mapa dizia "9 IDs" mas enumerava 14; a lista autoritativa é a da fatia, com 12. Os dois extras que o mapa cita (`OPS-621`, `OPS-483`) precisam ser conferidos à parte.
- **Opções:** (a) rodar a contagem no dump agora e decidir com o número; (b) assumir que tem e construir; (c) assumir que não tem e descartar.
- **Default vigente:** (b) — "assumo que sim e implemento; se vier 0, os 12 IDs viram `dropped`".
- **Recomendação:** (a). É a consulta de melhor relação custo-benefício da lista inteira: cinco segundos decidem se 12 IDs viram código ou evidência.

### P-092 — Trilha de auditoria com geolocalização (`BE-433`): implementar a intenção ou descartar?

- **Por que o DEC-30 não resolve:** Feature **nunca entregue** — só a assinatura existe, e a action está quebrada em três frentes (**A-5**). Depende de P-091. Registrar junto o achado colateral: `GET /api/v1/trackings` parte de `Tracking.all` **sem escopo** (**D-110**), e esse tem veredito `corrigir` — é da família EXCEÇÃO-2.
- **Origem:** `Q-83` + `F-25` (fundidas)
- **Fatia:** S19 — depende de **P-091**
- **Trava:** trava `BE-433`.
- **Impacto:** `muda escopo`
- **Contexto:** Existe uma assinatura que aceita coordenadas para recalcular distância — `app/controllers/api/v1/trackings_controller.rb:39-45` lê `params[:lat]` e `params[:lng]` (`:40`) e atribui em `@tracking.geolocation.ref_lat`/`ref_lng` (`:42-43`). Só que a action está **quebrada em três frentes** (ver A-5): `@tracking` nunca é carregado (o `fetch_tracking` de `:54-56` está **vazio** e nem é registrado como `before_action`), `Tracking` **não declara** associação `geolocation`, e nada é salvo nem recalculado. O recálculo real vive em `geolocation.rb:164-171`, fora do alcance desse controller. É uma feature **nunca entregue** — só a assinatura existe. E se P-091 vier zero, o cálculo nunca dispara e vira código morto no dia 1.
- **Opções:** (a) portar o cálculo **condicional** (só quando `lat`/`lng` vierem), sem geocoding; (b) não portar até P-091 responder; (c) descartar o caminho morto e registrar no ledger com a evidência.
- **Default vigente:** (a).
- **Recomendação:** (b) — amarrar a P-091 evita nascer com uma função que nunca executa; se a contagem der zero, vira (c). Vale registrar junto o achado colateral: `GET /api/v1/trackings` parte de `Tracking.all` **sem escopo nenhum** (D-110), e isso **tem** veredito `corrigir`.

### P-098 — `charges` e `receipts` têm dois donos: S6 e S11

- **Por que o DEC-30 não resolve:** Conflito interno de **propriedade de fatia** dentro do mesmo documento (**A-3**): as mesmas duas tabelas com dois IDs de inventário. Não há legado envolvido — é escopo de quem constrói.
- **Origem:** `F-43`
- **Fatia:** S6 e S11
- **Trava:** duas migrations para as mesmas duas tabelas, se as duas fatias rodarem em paralelo — e com DEC-22 elas rodam.
- **Impacto:** `muda escopo`
- **Contexto:** **Ver o achado A-3.** `s11/proposal.md:200-208` diz, na seção "Fronteiras", que a feature de cobranças e recibos **não é de S11**: *"os IDs (BE-187, BE-188, BE-189, DB-162…DB-165, FE-179..FE-186) pertencem ao bloco `receivables-renegotiations`… o que desta fatia toca 'Cobranças' é **exclusivamente** o item de menu nascer habilitado"*. E S6 confirma, com todos esses IDs na sua lista. Mas a seção "IDs adotados no fechamento do Phase 2" do mesmo `s11/proposal.md:283-290` reivindica `DB-583` (`charges`) e `DB-584` (`receipts`) com a justificativa *"S11 é dona das cobranças (DEC-15.1: vivas)"*. São as **mesmas duas tabelas com dois IDs de inventário diferentes**, e a conferência consolidada não pegou porque ela compara IDs, não tabelas.
- **Opções:** (a) **S6 é dona das duas tabelas**; S11 fica só com o item de menu habilitado, e `DB-583`/`DB-584` são registrados como "mesma tabela, fechado por S6"; (b) S11 é dona das tabelas e S6 do comportamento; (c) as duas migrations existem, uma cria e a outra altera.
- **Default vigente:** contraditório dentro do mesmo documento — é o achado.
- **Recomendação:** (a). É o que a própria seção "Fronteiras" de S11 já diz; o que falta é a seção "IDs adotados" concordar com ela. E vale rodar a conferência **por tabela**, não só por ID, para descobrir se há outros casos.

### P-099 — Quem é o dono de `Tracking`/`trackings` (`BE-430`, `DB-591`): S2, S13 ou S19?

- **Por que o DEC-30 não resolve:** Propriedade de fatia: três documentos discordam e um se contradiz sozinho. Escopo interno, sem legado a replicar. Interage com P-110 (`Tracking` seria uma **terceira** trilha).
- **Origem:** `F-38`
- **Fatia:** S2, S13 e S19
- **Trava:** trava a tarefa 1.5 de S13 (*"verificar se S2 já entregou `Tracking`"*) e a tarefa 3.9, que cria "o mínimo" se ninguém tiver criado.
- **Impacto:** `muda escopo`
- **Contexto:** **Três documentos discordam, e um se contradiz sozinho.** `s13/proposal.md:165-167` diz que `Tracking` é *"de `misc-domain`, fatia de navegação/transversais (**S2**)"*; `s13/design.md:220` repete ("são de **S2**, decisão **D-P**"); `s13/proposal.md:289` diz que *"`OPS-126` e o model `Tracking` são de **S19**"*. E `s19/proposal.md:57-59` reivindica `DB-591` e `BE-430` como seus — o que **é o certo**: o `migration-map.md` criou a S19 justamente para isso, e ela roda logo depois de S0. S2 **não menciona `Tracking` em lugar nenhum**.
- **Opções:** (a) **S19 é dona**, e S13 apenas consome (a fatia existe e roda antes de S13); (b) S13 cria o mínimo e S19 constrói a leitura em cima; (c) S2 é dona, como dois dos três documentos dizem.
- **Default vigente:** ambíguo — a tarefa 3.9 de S13 é um "se ninguém fez, eu faço", que é exatamente o padrão que produz dois donos.
- **Recomendação:** (a), e corrigir as três referências a S2 dentro de S13. **S13 não deve ter tarefa de criar `Tracking`** — só de consumir. Note que isto interage com P-110: `AuditEvent`, `Tracking` e `permission_audit_logs` seriam **três** trilhas.

### P-100 — Ordem: o motor de anexos (S13) está declarado depois de S9, que tem 4 anexos

- **Por que o DEC-30 não resolve:** Ordem de execução das fatias, com **nenhum default** — está registrado como "ambiguidade de ordem no relatório", que é onde as coisas somem. Se S9 rodar antes de S13, a base ganha um terceiro caminho de upload.
- **Origem:** `F-37`
- **Fatia:** S13 e S9
- **Trava:** se S9 começar antes de S13, ela improvisa um segundo caminho de arquivo **hoje**.
- **Impacto:** `muda escopo`
- **Contexto:** O próprio S13 registra a ambiguidade em `s13/proposal.md:178-183`: *"**NÃO depende de S6/S7:** o sub-bloco B (anexos) só precisa de S1 + das entidades donas… Se S9 (renegociações, com 4 anexos) rodar antes de S13, o motor de anexos **tem de ser antecipado** — senão S9 improvisa um segundo caminho e a base fica com três."* Mas a ordem do `migration-map.md` põe S13 depois de S6/S7, e S9 depende só de S4. **Com a paralelização máxima do DEC-22, S9 pode estar rodando agora.**
- **Opções:** (a) **antecipar o sub-bloco B de S13** (motor de anexos) para logo depois de S1, antes de S9; (b) S9 espera S13; (c) S9 usa ActiveStorage diretamente e S13 depois unifica.
- **Default vigente:** **nenhum** — está registrado como "ambiguidade de ordem no relatório", que é onde as coisas somem.
- **Recomendação:** (a). "Depois unificamos" (c) é como uma base ganha três caminhos de upload; e (b) atrasa uma fatia inteira por causa de quatro campos de arquivo.

### P-101 — `BE-445` (`Entry`, a classe base abstrata): fica em S6 ou vai para S19?

- **Por que o DEC-30 não resolve:** Escopo interno (contrato C4, quem constrói é dono). Sem legado envolvido.
- **Origem:** `F-39`
- **Fatia:** S6 (alternativa: S19)
- **Trava:** nada agora — S6 roda antes de S11 de qualquer forma.
- **Impacto:** `muda escopo`
- **Contexto:** `Entry` é a classe base de `ReceivableEntry` (S6) e `AvailabilityEntry` (S11) — transversal por natureza, o que a tornava candidata à fatia de transversais. Ficou em S6 pelo contrato **C4** (quem constrói é dono): `ReceivableEntry` nasce lá, antes de S11 (`s6/proposal.md:261`, `s19/proposal.md:131`). O que ela carrega junto: **"Diferença" e "OK" deixam de ser strings em pt-BR gravadas na coluna e comparadas por igualdade de texto, e viram `enum`**.
- **Opções:** (a) fica em S6, como está; (b) vai para S19, junto dos demais transversais de domínio; (c) fica em S6, mas a conversão dos enums-string é tarefa de S14 (já é — `s14/tasks.md:70`).
- **Default vigente:** (a), por C4.
- **Recomendação:** (a). O risco real não é onde a classe mora — é S11 herdar de uma classe que ainda não existe. Como S6 roda antes de S11 na ordem de dependência, (a) resolve.

### P-103 — Convivem dois editores rich text na base (Slate e TipTap)

- **Por que o DEC-30 não resolve:** Decisão de **plataforma** sobre a base compartilhada (Slate × TipTap), Princípio 6b. Nada disso vem do legado.
- **Origem:** `F-47` (flag F-14 de S12)
- **Fatia:** S12
- **Trava:** nada — o desenho já escolheu.
- **Impacto:** `muda escopo`
- **Contexto:** `frontend/src/components/RichTextEditor.tsx` usa **Slate** e está em uso; **TipTap** está declarado no `package.json` **sem consumidor**. S12 decidiu usar **um só** — o que já está em uso — e registrar o outro como flag de upstream (`s12/design.md:23-25`).
- **Opções:** (a) usar Slate e registrar TipTap como flag de upstream; (b) usar Slate e **remover** TipTap do `package.json`; (c) migrar para TipTap.
- **Default vigente:** (a).
- **Recomendação:** (b) se nenhum outro produto da base usar TipTap — mas isso é decisão de plataforma, não do Safegold, e o Princípio 6b diz para não mexer. Então (a), com a flag escrita.

### P-104 — Por quanto tempo guardamos IP e user-agent das tentativas de login?

- **Por que o DEC-30 não resolve:** **A-2** inverte a premissa: o legado **não tem** essa tabela. Quem tem é a base ai9 (`backend/db/schema.rb:451-460`), com 9 índices e **nenhum job de expurgo**. É passivo **adotado**, e a pergunta é de retenção — o princípio é silencioso.
- **Origem:** `Q-87`
- **Fatia:** S1
- **Trava:** nada — só muda a política de retenção.
- **Impacto:** `só interno`
- **Contexto:** **Ver o achado A-2 — a origem do problema é o contrário do que o material dizia.** O legado **não tem** essa tabela: as 3 ocorrências de `login_attempt` no repositório inteiro são o método `invalid_login_attempt` em `engines/auth_ux19/.../sessions_controller.rb:42,61,80`. O único rastro de login é o contador `failed_attempts` do Devise, sem IP e sem user-agent. Quem tem a tabela é a **base ai9**: `backend/db/schema.rb:451-460` cria `login_attempts` com `identifier`, `method`, `ip_address` (`inet`, `null: false`), `user_agent`, `success`, `error_reason` e `user_id`, com 9 índices — e **nenhum job de expurgo**. Não é passivo herdado, é passivo **adotado**.
- **Opções:** (a) 90 dias, com job de expurgo (`sidekiq-cron` já está no Gemfile e o bloco de cron está vazio); (b) 180 dias; (c) retenção indefinida, como está hoje na base.
- **Default vigente:** (a) — suficiente para investigar incidente, curto o bastante para não virar passivo de LGPD.
- **Recomendação:** (a). E vale registrar como **flag de upstream**: a tabela é da base compartilhada, então a política ideal é decidida uma vez para todos os sistemas.

### P-107 — Chaves de terceiro vivem em ENV/credentials ou no model `Credential`?

- **Por que o DEC-30 não resolve:** Decisão de plataforma (ENV/credentials × model `Credential`, que hoje só aceita provedores de IA). **A parte de segurança não está em discussão e não depende desta resposta:** nenhum segredo do legado entra no repositório novo, e ReceitaWS, Google Maps e `secret_key_base` precisam ser **rotacionados no cutover** (**D-85**, **A-25**).
- **Origem:** `Q-90`
- **Fatia:** S18
- **Trava:** trava `CFG-01`.
- **Impacto:** `só interno`
- **Contexto:** O catálogo da base sugeria o model `Credential`, mas `backend/app/models/credential.rb:7` restringe `provider` a provedores de IA — e a chave do Google Maps precisa chegar ao **navegador** de qualquer forma. No legado a situação é pior do que o material registrava (A-25): o token da ReceitaWS vem de ENV (`config/initializers/receitaws.rb:5`) **mas o valor real está versionado** em `config/application.arch.yml:12`; a chave do **Google Maps está hardcoded e duplicada** em `app/definitions/SFG/metadata.rb:8` e `:9` (a segunda dentro da própria URL, que vai para o HTML); e o `secret_key_base` está em texto puro em `config/development_credentials.yml:1`.
- **Opções:** (a) ENV/credentials, com `VITE_GOOGLE_API_KEY` para o front; **não** estender o `Credential`; (b) estender o `Credential` para aceitar provedores não-IA (mexe num model compartilhado, Princípio 6b); (c) misto.
- **Default vigente:** (a).
- **Recomendação:** (a), com uma regra inegociável: **nenhum segredo do legado entra no repositório novo**, e os três acima (ReceitaWS, Maps, `secret_key_base`) precisam ser **rotacionados no cutover**.

### P-109 — Logos: model `Medium` ou `has_one_attached` direto nos models?

- **Por que o DEC-30 não resolve:** Decisão de plataforma sobre peça da base (`Medium` × `has_one_attached`). Nota que reforça o default (a): a tabela `media` **não tem dono nem escopo** — um logo criado por lá aparece na galeria `/media` para qualquer autenticado, e filtrar significaria mexer no `MediumService` compartilhado.
- **Origem:** `Q-92`
- **Fatia:** S3 e S4
- **Trava:** trava `DB-056`, `DB-062`, `DB-089`, `FE-074` e `FE-087`.
- **Impacto:** `só interno`
- **Contexto:** No legado tudo é kt-paperclip em disco local. No ai9 há duas rotas: usar o model `Medium` (que a base já tem) ou `has_one_attached` direto nos models novos. O problema do `Medium` é que a tabela `media` **não tem dono nem escopo** — um logo criado por lá aparece na galeria `/media` para **qualquer autenticado**, e filtrar a galeria significaria mexer em `MediumService`, que é da base compartilhada (Princípio 6b). Nas duas opções, **Paperclip não é portado**. Os anexos em questão são **projeto** (`project.rb:48`, `avatar`), **portador** (`carrier.rb:16`) e **fornecedor** (`provider.rb:12`) — **`Company` não tem anexo nenhum**.
- **Opções:** (a) `has_one_attached` direto em `Project#logo`, `Carrier#logo` e `Provider#logo`, reusando a mesma pilha ActiveStorage + `image_processing` que o `Medium` usa; (b) usar `Medium`, aceitando que os logos apareçam na galeria; (c) usar `Medium` e autorizar tocar no `MediumService` para filtrar por escopo.
- **Default vigente:** (a).
- **Recomendação:** (a).

### P-110 — Uma trilha de auditoria só, e qual: `AuditEvent`, `paper_trail` ou `permission_audit_logs`?

- **Por que o DEC-30 não resolve:** **Não há trilha financeira a preservar** (**A-27**): o legado não tem `paper_trail`, e a trilha caseira cobre só jobs de template e criação de projeto. O que existir no ai9 é novo — é decisão de plataforma, e **é agora ou nunca**: a partir da primeira gravação, mudar vira migração de trilha.
- **Origem:** `Q-93` + `F-49` (fundidas; DS0-1)
- **Fatia:** S0 (consumida por S4, S9, S11, S12, S19)
- **Trava:** trava o desenho da trilha de auditoria. **Não trava tarefa nenhuma hoje — e é exatamente esse o risco.**
- **Impacto:** `só interno`
- **Contexto:** Há três candidatos e dois documentos internos que divergiam. `paper_trail` está declarada no `backend/Gemfile:47` da base ai9 e **não é usada por nenhum sistema** (mesma família de `aasm`, `Gemfile:45`, e `pg_search`, `Gemfile:87`) — ativá-la é decisão de **plataforma**, não de uma migração. `permission_audit_logs` **já existe na base**, tem o formato certo (`actor_type`/`actor_id`/`reason`/`metadata`) e **zero produtores**. `AuditEvent` é a trilha genérica que o desenho de S0 escolheu criar (`s0/design.md:89-91`), usando o formato de `permission_audit_logs` como molde. **Contexto do legado que ajuda a decidir:** o legado **não tem `paper_trail`**; a trilha dele é caseira (`app/models/tracking.rb` + `lib/tracking_facade.rb`) e cobre **só** jobs de template de disponibilidade e criação de projeto — não cobre CRUD, lançamentos, valores, permissões nem login. **Não há trilha financeira a preservar**: o que houver no ai9 é novo. **Por que é caro depois:** concessão de permissão, troca de papel, impersonation, renegociação, risco e recebíveis vão todos gravar nessa tabela. Trocar de tabela depois é migrar dado de auditoria, que é o dado que não se pode reescrever.
- **Opções:** (a) `AuditEvent` genérica — uma trilha para todos os domínios, e `paper_trail`/`permission_audit_logs` viram linhas em `upstream-flags.md`; (b) `permission_audit_logs` para atos administrativos e `AuditEvent` para domínio — duas trilhas, cada uma com semântica própria; (c) dar produtor a `permission_audit_logs` e **não** criar `AuditEvent`; (d) ativar `paper_trail` na base.
- **Default vigente:** (a).
- **Recomendação:** (a), **e é agora ou nunca** — a partir da primeira gravação, mudar vira migração de trilha. Duas trilhas para o mesmo tipo de ato é exatamente o que os contratos transversais existem para evitar, e ativar uma gem na base compartilhada afeta todos os sistemas. **Confira na mesma resposta o P-099:** `Tracking` seria uma **terceira** trilha, e vale decidir se ela e `AuditEvent` deveriam ser a mesma coisa.

### P-115 — `polemk_webhooks`: renomear o campo exige coordenar front e backend

- **Por que o DEC-30 não resolve:** Nomenclatura de **contrato de API da base compartilhada** (Princípio 6b). Não vem do legado.
- **Origem:** `F-51`
- **Fatia:** S2 (a tela) e a base compartilhada
- **Trava:** nada — é a pergunta se vale a pena.
- **Impacto:** `só interno`
- **Contexto:** Conferido: `polemk_webhooks` **não é nome interno, é campo de contrato de API**. Aparece em `backend/app/controllers/api/entities/polemk_instances.rb:26` (`expose :polemk_webhooks`) e é consumido em `frontend/src/app/pages/WhatsappPage.tsx:117` e `:304-305`. Mais o model, o serviço, o seed, duas migrations e três specs. "polemk" é a marca de **outro produto da base** aparecendo dentro do Safegold.
- **Opções:** (a) não renomear — é nome de peça compartilhada (Princípio 6b), e o campo não aparece para o usuário final; (b) renomear tudo de uma vez (entity, front, model, serviço, seed, migrations, specs) numa mudança coordenada; (c) manter o campo e expor um **alias** no entity, para o front usar o nome novo sem quebrar a base.
- **Default vigente:** (a) implícito — nenhuma fatia tem tarefa de renomear.
- **Recomendação:** (a). O nome não vaza para nenhuma tela do Safegold; renomear contrato de API compartilhado por estética é o tipo de mudança que quebra outro produto na sexta-feira.

### P-116 — Qual é o padrão de paginação do backend? (Kaminari está no Gemfile sem uso)

- **Por que o DEC-30 não resolve:** Decisão de plataforma, **sem default**, e trava código hoje (bloco 0 de S5, item 0.3, valendo para 14 endpoints). É diferente do DEC-09/Q-04, que decidiu o *comportamento* da paginação; isto é a *forma*.
- **Origem:** `C-07` — **recuperada** (a metade das fatias a descartou como "duplicata do mapa", e o mapa não a tem; ver 4.3)
- **Fatia:** S0, consumida por todas as fatias com lista
- **Trava:** **trava código hoje** — bloco 0 de S5, item 0.3 (`s5/tasks.md:20`): *"Escolher o padrão de paginação do backend (Kaminari × padrão manual de `users_service.rb:49`) e registrar. Vale para os 14 endpoints de lista do bloco. **Não pode ficar meio a meio.**"* O mesmo vale para os outros blocos.
- **Impacto:** `só interno`
- **Contexto:** `kaminari` está declarada no `backend/Gemfile:85` da base ai9 e **não tem uma única chamada em `backend/app`** (`s5/design.md:257`). O padrão que de fato existe hoje é manual, com `limit`/`offset` calculados à mão em `users_service.rb:49`. Se cada fatia escolher sozinha, metade dos endpoints vai devolver um envelope de paginação e a outra metade outro — e o front vai ter que lidar com dois contratos. **Isto é diferente de DEC-09/Q-04**, que decidiu que *a paginação passa a funcionar de verdade* (hoje `limit`/`offset` são descartados em quase todo `search`, D-20); aquilo é o comportamento, isto é a forma.
- **Opções:** (a) usar **Kaminari**, já que a gem está no Gemfile, e registrar como consumo de uma peça que a base já declarou; (b) padronizar o **manual** de `users_service.rb:49` e registrar Kaminari como flag de upstream ("gem declarada sem uso"); (c) deixar cada fatia escolher.
- **Default vigente:** **nenhum** — a tarefa está escrita como "escolher", e ninguém escolheu.
- **Recomendação:** (b) se o padrão manual já for o de fato usado pelos endpoints existentes da base (é o caso hoje), porque adotar Kaminari agora significaria reescrever os endpoints que já existem. (c) está fora de questão: é literalmente o cenário que a tarefa proíbe.

### P-117 — Dark mode entra?

- **Por que o DEC-30 não resolve:** Nasce da base ai9 (`ThemeToggle`), não do legado. Na prática já está respondida em dois lugares (`decisions.md:602`) — falta só virar DEC numerado, porque "conferir toda tela nos dois modos" é custo real de QA no plano da sexta.
- **Origem:** `Q-02` de S17 — **recuperada** (descartada como "duplicata do mapa", e o mapa não a tem; ver 4.3)
- **Fatia:** S17 e a tematização
- **Trava:** nada — o mecanismo já existe na base (`ThemeToggle`).
- **Impacto:** `só interno`
- **Contexto:** `s17/proposal.md:141` registra a pergunta com default "entra: o mecanismo já está na base; o custo é a paleta". E `decisions.md:602` já manda o `theming-brand-engineer` entregar "a marca Safegold em light **e** dark" como item **crítico para o resultado** da demo. Na prática a resposta já está dada em dois lugares — só nunca virou DEC numerado, e cada tela precisa ser conferida nos dois modos.
- **Opções:** (a) entra — a marca é tokenizada e conferida nos dois modos; (b) só light nesta entrega, e dark depois.
- **Default vigente:** (a).
- **Recomendação:** (a). Confirmar com uma letra é mais barato que deixar implícito, porque "conferir toda tela nos dois modos" é custo real de QA e precisa estar no plano da sexta.

---

## 6. O que o DEC-30 custa

Os defeitos abaixo ficam **preservados de propósito** por causa do princípio. Nenhum deles é
acidente da migração: são escolhas que esta rodada está fazendo em nome do DEC-30, e cada uma
volta a ser pergunta se você disser "esse aqui não".

### Os três mais caros

1. **D-94 — o ciclo de vida da operação de risco continua decorativo** (P-016 + P-034). Encerrar
   não bloqueia movimento, não bloqueia prorrogação e não tira a operação da janela de exposição;
   **renovar não encerra a original, então as duas consomem limite ao mesmo tempo**, e a encerrada
   continua aparecendo como candidata a faturamento. É o único item desta lista cujo veredito no
   `legacy-defects.md` é literalmente *"corrigir — a renovação em dobro é erro de exposição
   financeira, não comportamento a preservar"*: **o DEC-30 está revertendo um veredito já escrito.**
2. **A taxa que fatura continua sem validação** (P-026). `remuneration.rb:9` tem só `presence`, a
   coluna é `float`, o campo não tem `min`/`max`/`pattern` — **250% passa pela UI** e multiplica
   todo o faturamento. Somado ao **D-114** (o legado não tem um único teste), o golden do
   `receipt.rb:63` passa a ser a única rede.
3. **D-46 — "Valor Parcela" mostra o valor presente** (P-013). `renegotiation.rb:126` reatribui a
   coluna logo depois de calculá-la; sempre que há juros > 0 e saldo em aberto, a coluna mais lida
   da tela de renegociação exibe outra coisa. Menção honrosa na mesma tela: a mora entra dos dois
   lados, **nunca é efetivamente cobrada** e **infla o "R$ Pago"** (P-014, A-10).

### A lista completa

| Defeito | Pergunta | O que o usuário vai continuar vendo |
| ------- | -------- | ----------------------------------- |
| **D-94** | P-016, P-034 | Operação encerrada soma exposição, aceita movimento e prorrogação, e continua faturável; renovar consome limite em dobro |
| **D-46** | P-013 | "Valor Parcela" exibe o valor presente sempre que há juros > 0 e saldo em aberto |
| **A-10** | P-014 | A mora nunca é efetivamente cobrada na parcela e infla o "R$ Pago" no agregado da renegociação |
| **D-30** | P-019 | O carimbo `has_safegold_management` continua copiado para 6 tabelas e só `companies` é ressincronizada — registro de 2019 mente sobre a marca atual |
| **D-70** | P-036 | Renomear um indicador reescreve `title`/`key`/`value_type` de **todos** os lançamentos, de todos os projetos |
| **D-19** (catálogos) | P-027 | Carteira, tipo de recebível e fonte de recurso "desativados" continuam aparecendo em todos os selects |
| **D-19** (ciclo) | P-068 | O borderô continua sem baixa, liquidação nem vencimento — só "OK" e "Diferença" |
| **D-73** | P-077 | `balance` da operação estruturada volta ao inicial a cada save e nunca é movimentado *(inócuo na prática: conferido que nada mais o escreve)* |
| — | P-011 | `pending_main_value` continua sem piso e pode ficar negativo ao lado de um `remaining_value` com piso, na mesma tela |
| — | P-010 | "A vencer" continua incluindo as vencidas — e continua sendo o expoente do valor presente |
| — | P-017 | Transferência a partir da antecipação continua gravando o "enviado" sem nenhum "recebido" do outro lado |
| — | P-025 | Data em 1900/2100, `valor_bruto` zero, dívida negativa e taxa de juros negativa continuam sendo aceitas |
| — | P-026 | Taxa de remuneração de 250% continua passando e multiplicando todo o faturamento |
| — | P-028 | Editar remuneração cujo tipo foi desativado continua mostrando o **primeiro tipo ativo**, não o tipo real |
| — | P-029 | `nominal_tax` nunca é comparada com as duas checagens calculadas, e viaja direto para `agreed_rate` da operação de risco |
| — | P-030 | IOF lançado duas vezes no mesmo borderô continua entrando sem aviso |
| — | P-033 | Trocar a empresa move a operação de projeto em silêncio e sem log, podendo invalidar remuneração e recibo já emitidos |
| — | P-035 | A busca de operações não acha pelo número de contrato nem pela empresa que está na coluna ao lado |
| — | P-044 | ~62 mil borderôs continuam atribuídos ao usuário 1 e à empresa 1 |
| — | P-069, P-080, P-081 | `is_title`, `is_on_variable`, `allow_manual_operations` e `allow_receivable_entries` continuam gravados sem nenhum leitor de regra |
| — | P-074 | Pagamento de renegociação continua sem forma de pagamento, banco, documento ou conciliação |
| — | P-083 | Indicador de percentual ou de quantidade continua sendo gravado e exibido como R$ |
| — | P-112 | `is_active` do indicador continua com dois caminhos de escrita, um deles fora do `permit` |
| — | P-114 | O autor do lançamento continua sendo sobrescrito a cada alteração — e continua não aparecendo em tela nenhuma |

**O que o DEC-30 explicitamente *não* está preservando**, ainda que a pergunta pareça da mesma
família: os 6 itens de `EXCEÇÃO-2`, os 2 de `EXCEÇÃO-1`, e — dentro de perguntas que ficaram em
`EXCEÇÃO-3` — o cálculo de correção monetária e carência (P-012), que **não** será implementado,
porque implementá-lo seria inventar uma fórmula que o legado nunca teve.

---

## 7. `AINDA-PRECISA` — 18 perguntas, ordenadas por impacto

Mesma escala do documento de origem: `muda número na tela` → `muda comportamento observável` →
`muda escopo` → `só interno`. **⛔ marca as que travam código hoje.**

| Ordem | P | Faixa | Trava código hoje |
| ----: | - | ----- | ----------------- |
| 1 | **P-015** — Subtipo da operação de risco: o formulário não pergunta e o… | `muda número na tela` | ⛔ **sim** |
| 2 | **P-020** — Aceite de contrato volta a ser explícito? | `muda comportamento observável` | ⛔ **sim** |
| 3 | **P-021** — O que fazer com os aceites implícitos que já estão gravados? | `muda comportamento observável` | ⛔ **sim** |
| 4 | **P-024** — Os 91 textos de ajuda dos formulários são todos o mesmo pla… | `muda comportamento observável` | não |
| 5 | **P-037** — Na grade de indicadores, "não lançado" e "lançado como zero… | `muda comportamento observável` | não |
| 6 | **P-038** — O título do indicador continua em CAIXA ALTA sem acento? | `muda comportamento observável` | ⛔ **sim** |
| 7 | **P-041** — `resource_kinds` e `resource_sources` são indistinguíveis | `muda comportamento observável` | não |
| 8 | **P-046** — Qual é a cor primária da marca? | `muda comportamento observável` | não |
| 9 | **P-067** — Qual é a prova mínima exigida de um aceite? | `muda escopo` | ⛔ **sim** |
| 10 | **P-084** — Existe consumidor externo dos headers `X-LAA-Agent` / `X-LA… | `muda escopo` | não |
| 11 | **P-089** — Mantemos Google Analytics no console? | `muda escopo` | não |
| 12 | **P-094** — Tipos de garantia: você quer, e qual é o conteúdo? | `muda escopo` | não |
| 13 | **P-095** — Teremos acesso ao disco do servidor legado? | `muda escopo` | não |
| 14 | **P-096** — A "Chave de Integração" do indicador tem consumidor fora do… | `muda escopo` | ⛔ **sim** |
| 15 | **P-097** — URGENTE: o seed de demonstração não tem dono. Ninguém o con… | `muda escopo` | ⛔ **sim** |
| 16 | **P-102** — A arte do carousel de login: reusar do legado, gerar, ou vo… | `muda escopo` | ⚠ não tecnicamente — mas é a **primeira tela da demo de sexta** |
| 17 | **P-108** — O logo da marca precisa de versões branca e monocromática d… | `só interno` | não |
| 18 | **P-111** — As colunas renomeadas em 2022 têm leitores externos? | `só interno` | não |

### P-015 — Subtipo da operação de risco: o formulário não pergunta e o código escolhe "o primeiro"

- **Faixa de impacto:** `muda número na tela`  ·  ⛔ **trava código hoje**
- **Por que o DEC-30 não resolve:** Uma das **4 sem default consolidado** (o mapa fixou (b), a spec fixou (a)) e uma das 3 que o próprio documento destaca como "valem a resposta por escrito". O legado escolhe o subtipo por `.first` **sem `order`** — ordem de inserção de linhas num cadastro — e o subtipo decide o **bucket de limite** que aparece somado na tela. Replicar não preserva um número existente: define, para toda operação criada dali em diante, uma classificação que ninguém escolheu. E a pergunta de fundo — o formulário passa a perguntar o subtipo? — é de operação, não de código.
- **Origem:** `Q-14` + `F-06` (fundidas)
- **Fatia:** S7, com efeito direto em S5 (limites) e S6 (borderô)
- **Trava:** trava `BE-262`, `BE-244`, `BE-245` e o bloco 0 de S7 (`s7/tasks.md:23`) — nada de código de operação de risco antes.
- **Impacto:** `muda número na tela`
- **Contexto:** Quando o subtipo não vem no formulário, `app/models/risk_operation.rb:32` faz `operation_subtype_id = operation_type.subtypes.where(...).pluck(:id).first` — **sem `order`**, ou seja, pela ordem de inserção no banco. E o formulário de operação de risco **não tem campo de subtipo** (zero ocorrências de `subtype` em `.../risk_operations/new/_body.html.erb`), então esse caminho é o padrão em toda criação manual. O subtipo decide o bucket de limite: `is_pre = 0` entra em "liquidável" (`risk_control.rb:129-130`) e `is_pre = 1` entra em "pré-faturamento" (`:144-145`) — e é o bucket que aparece somado na tela de risco. Como `risk_operation_type.rb:23` cria o subtipo "pré" antes do de "antecipação" (`:31`), **o `.first` tende a cair no pré**. **Conflito interno registrado:** o mapa manda replicar o legado; a spec `BE-262` manda **recusar com 422** pedindo escolha explícita.
- **Opções:** (a) recusar com 422 e obrigar a escolha explícita (a spec); (b) replicar o `.first`, com `order` explícito por id para pelo menos ser determinístico (o mapa); (c) tornar o subtipo padrão uma **configuração do tipo** (`is_default` já existe nessa família), e o formulário só o mostra quando há mais de um; (d) recusar nas gravações novas e replicar na carga histórica.
- **Default vigente:** conflitante — o mapa fixou (b), a spec fixou (a). **Precisa da sua palavra.**
- **Recomendação:** (c) para o comportamento, com (d) na prática — a carga histórica não tem a quem perguntar. (c) é a única opção em que o número deixa de depender da ordem de inserção de linhas num cadastro, sem obrigar o operador a responder uma pergunta que ele hoje não responde.

### P-020 — Aceite de contrato volta a ser explícito?

- **Faixa de impacto:** `muda comportamento observável`  ·  ⛔ **trava código hoje**
- **Por que o DEC-30 não resolve:** **Sem default, e não deve haver.** É consequência **jurídica** (**D-64**): o sistema registra hoje um aceite que o usuário nunca deu conscientemente. O princípio não decide validade de consentimento.
- **Origem:** `Q-18` + `F-12` (fundidas)
- **Fatia:** S12, com dependência de S1 (convite)
- **Trava:** **bloqueia S12** — o SC-2 inteiro, 20 tarefas marcadas como bloqueadas (`s12/tasks.md:110-145`).
- **Impacto:** `muda comportamento observável`
- **Contexto:** Em produção o aceite explícito está morto por **quatro** motivos independentes, todos conferidos: (1) o bloqueio de acesso por contrato pendente está inteiramente comentado (`app/controllers/pub_application_controller.rb:55-63`); (2) os dois botões "ACEITAR" estão comentados nas views (`.../contracts/header/_body.html.erb:44` e `.../_toolbar_body.html.erb:22`), embora os handlers JS e a rota `PUT` continuem vivos e inalcançáveis — **hoje não existe nenhuma forma de aceitar um contrato pela interface**; (3) o cálculo de pendência **levanta exceção** porque a associação está errada (`app/decorators/models/user_decorator.rb:40` declara `source: :contract_deal`, e `ContractDeal` só tem `:contract` e `:user`), então quem abria `/contract/:type` recebia 500; (4) os checkboxes de cadastro e de "Minha Conta" vêm **pré-marcados** e não são lidos por controller nenhum. O aceite real é implícito: um `after_create` no usuário grava os dois (`user_decorator.rb:2` e `:234-240`). É o **D-64**, e a consequência é jurídica — **o sistema registra hoje um aceite que o usuário nunca deu conscientemente**.
- **Opções:** (a) reativar o ciclo completo — aceite explícito **com** bloqueio de acesso enquanto houver contrato pendente (é o comportamento que o código pretendia); (b) reativar só a **ação** de aceitar, sem bloqueio — banner persistente até aceitar; (c) manter tudo desligado e portar apenas a página de leitura.
- **Default vigente:** **nenhum.** As tarefas estão travadas de propósito. Nenhum default seguro existe aqui.
- **Recomendação:** (b) para a demo e (a) antes do cutover, com o jurídico definindo o prazo de tolerância. Ligar o bloqueio numa demo comercial arrisca travar o cliente na primeira tela. Com **DEC-18.7** (cadastro público desligado, entrada só por convite), o consentimento passa naturalmente para o fluxo de convite (`BE-340`, `FE-337`).

### P-021 — O que fazer com os aceites implícitos que já estão gravados?

- **Faixa de impacto:** `muda comportamento observável`  ·  ⛔ **trava código hoje**
- **Por que o DEC-30 não resolve:** **Sem default, e não deve haver** — decisão jurídica sobre prova de consentimento já gravada. Qualquer escolha nossa aqui é opinião sobre validade jurídica.
- **Origem:** `Q-19` + `F-13` (fundidas)
- **Fatia:** S12, executada em S14 (ETL)
- **Trava:** trava o conversor de `contract_deals` do ETL e o seed de contratos (`s12/tasks.md:46`).
- **Impacto:** `muda comportamento observável`
- **Contexto:** Além do `after_create` que grava aceite sem interação (P-020), o seed do legado **fabricou aceite retroativo para toda a base**: `db/seeds.rb:141-148` e `:150-157` pegam todos os usuários sem aceite e criam um `ContractDeal` para cada um. A base de aceites existente **não distingue "aceitou" de "foi carimbado"** — migrar esses registros é migrar uma prova jurídica que não existe.
- **Opções:** (a) migrar como estão, sem marca; (b) migrar marcados como `implicit_legacy`, preservando a data mas registrando que não houve ato do usuário — quem já está na base não é incomodado; (c) migrar marcados como implícitos **e** exigir novo aceite na próxima entrada, preservando o registro antigo como histórico; (d) descartar e exigir novo aceite de todo mundo no primeiro login.
- **Default vigente:** **nenhum, e não deve haver.** É decisão jurídica: qualquer escolha nossa aqui é opinião sobre validade de consentimento.
- **Recomendação:** (c), sujeito ao jurídico. É a única que não descarta registro nem finge que o registro vale, e é aditiva em relação a (d) se o jurídico pedir reaceite geral.

### P-024 — Os 91 textos de ajuda dos formulários são todos o mesmo placeholder

- **Faixa de impacto:** `muda comportamento observável`
- **Por que o DEC-30 não resolve:** Replicar seria mostrar *"Só um teste de informações do campo…"* em 91 campos financeiros numa demo comercial. Mas o que falta não é regra nem cálculo — é **conteúdo de negócio** sobre campos de CET, float e IOF, e só quem conhece o produto escreve.
- **Origem:** `Q-22` (levantada em três mapas)
- **Fatia:** S6, S7, S8 (o mecanismo em S12)
- **Trava:** não trava código — o mecanismo é portado de qualquer forma. Trava só o conteúdo.
- **Impacto:** `muda comportamento observável`
- **Contexto:** Três YAML alimentam os tooltips dos formulários financeiros: `db/seed_assets/receivables_help_inputs.yml` (**65 chaves**), `risk_operations_help_inputs.yml` (13) e `structured_operations_help_inputs.yml` (13). **As 91 chaves têm exatamente o mesmo texto:** *"Só um teste de informações do campo pra descrever para que serve cada campo"*. São lidos em runtime pela própria view (`.../receivables/new/_body.html.erb:14`, `.../risk_operations/new/_body.html.erb:15`, `.../structured_operations/new/_body.html.erb:15`) e exibidos via tippy.
- **Opções:** (a) portar o mecanismo e **sair sem tooltip** onde não houver texto (o campo não mostra o ícone); (b) portar o mecanismo com o placeholder, como no legado; (c) você (ou quem conhece o produto) escreve os 91 textos — é conteúdo de negócio sobre campos financeiros, e eu não invento.
- **Default vigente:** (a) — mostrar "Só um teste…" numa demo comercial é pior que não mostrar nada.
- **Recomendação:** (a) na entrega, com (c) priorizado só para os campos do borderô que envolvem CET e float — que são os que o operador realmente erra.

### P-037 — Na grade de indicadores, "não lançado" e "lançado como zero" são o mesmo `0`

- **Faixa de impacto:** `muda comportamento observável`
- **Por que o DEC-30 não resolve:** O DEC-30 responderia (b) — não distinguir — e é verdade que nenhuma soma muda (a grade não tem linha nem coluna de total). **Mas ela é a mesma moeda de P-082**, que está em aberto: se a exclusão de lançamento for construída, excluir e zerar produzem exatamente a mesma tela e a feature não tem sentido. Responder as duas juntas é o pedido do próprio documento.
- **Origem:** `Q-35`
- **Fatia:** S10
- **Trava:** trava `FE-326`.
- **Impacto:** `muda comportamento observável`
- **Contexto:** A grade instancia um `IndicatorEntry.new` quando não há lançamento (`.../indicator_entries/list/_widget.html.erb:14`) e renderiza `value: entry.value.blank? ? 0 : entry.value` nas quatro variantes (`:27,:32,:52,:57`). Como a coluna tem default `0.0`, ausência e zero saem idênticos — e nem a cor distingue (positivo verde, negativo vermelho, zero e vazio ambos neutros). Existe um `beauty_value` que devolveria `"N/A"` para entrada sem id (`indicator_entry.rb:29-33`) e **a grade não o usa**. **Verificado:** a grade **não tem nenhuma linha ou coluna de total**, então distinguir os dois **não muda nenhuma soma** — muda só a célula.
- **Opções:** (a) distinguir: célula vazia (ou `—`) para não lançado, `0` para zero lançado; (b) manter os dois como `0`; (c) distinguir e ainda destacar visualmente as células não lançadas do mês corrente.
- **Default vigente:** (a) — é a mesma disciplina do D-117 (`format_money` renderiza nulo como R$ 0,00): num sistema financeiro, campo nulo e campo zerado não podem ser indistinguíveis.
- **Recomendação:** (a), e o custo é usar um método que o legado já escreveu e esqueceu de chamar. **Responda junto com P-082**: só faz sentido apagar um lançamento se "não lançado" for visualmente diferente de "zero".

### P-038 — O título do indicador continua em CAIXA ALTA sem acento?

- **Faixa de impacto:** `muda comportamento observável`  ·  ⛔ **trava código hoje**
- **Por que o DEC-30 não resolve:** Uma das **6 com default em conflito** (mapa (b) × spec (a)), e o princípio não desempata porque as duas pontas têm custo real: replicar (b) mantém a tela homogênea mas **destrói acento de tudo que for digitado dali em diante, sem volta**; corrigir (a) preserva o dado novo mas deixa a tela **mista** (histórico em caixa alta, novos como digitados) — e isso vai ser notado na demo. A opção (c) exige trabalho humano que só você autoriza.
- **Origem:** `Q-36` + `F-19` (fundidas)
- **Fatia:** S10
- **Trava:** trava `BE-321`, o bloco 0 de S10 (`s10/tasks.md:28`) e a tarefa 2.2.
- **Impacto:** `muda comportamento observável`
- **Contexto:** `app/models/indicator.rb:39` faz `self.title = I18n.transliterate(self.title).upcase` num `before_validation` **sem `on:`** — em todo save, e duplicado em `:43` no callback de criação. A `key` deriva do mesmo (`:44`). **Ponto do ETL que não tem volta:** os acentos originais **já se perderam no dado legado**, então o dado migrado chega em caixa alta de qualquer forma; "re-humanizar" seria adivinhação. A diferença aparece só no que for digitado depois. **Conflito interno:** o mapa manda replicar; a spec de `BE-321` diz que o título aparece **como digitado**, com a comparação de unicidade ignorando acento e caixa.
- **Opções:** (a) preservar o que foi digitado, normalizando só para comparação (a spec); (b) continuar forçando caixa alta sem acento, e a tela fica homogênea (o mapa); (c) (a) mais uma passagem manual de "re-humanização" dos títulos existentes, feita por gente; (d) parar de transformar o dado e resolver a aparência só na camada de apresentação.
- **Default vigente:** conflitante — o mapa fixou (b), a spec fixou (a). **Precisa da sua palavra.**
- **Recomendação:** (a) + (c) se forem poucos indicadores. A tela mista (uns em caixa alta, outros não) é feia e vai ser notada na demo; e (d) guarda o dado como está e resolve a aparência na camada certa, sem inventar acento nenhum.

### P-041 — `resource_kinds` e `resource_sources` são indistinguíveis

- **Faixa de impacto:** `muda comportamento observável`
- **Por que o DEC-30 não resolve:** Depende de P-070. E o que falta é informação que o código não tem: **qual é a diferença de negócio** entre `resource_kinds` e `resource_sources`. Os nomes têm de vir de você.
- **Origem:** `Q-39`
- **Fatia:** S8
- **Trava:** depende de **P-070** — se `resource_kinds` for descartado, esta pergunta desaparece.
- **Impacto:** `muda comportamento observável`
- **Contexto:** O **título de aba é idêntico byte a byte** — `"Safegold - Tipos de Recursos"` para os dois (`console_controller.rb:348-349` e `:358-359`) — mas **rótulo de menu só existe para `resource_sources`** (`application_helper.rb:153`); `resource_kinds` **não tem item de menu nenhum** e só é alcançável digitando a URL. Os títulos das próprias páginas diferem por **uma letra**: "Tipos de Recurso" (`.../resource_kinds/_body.html.erb:3`) contra "Tipos de Recursos" (`.../resource_sources/_body.html.erb:3`).
- **Opções:** (a) se os dois sobreviverem, renomear — por exemplo "Naturezas de recurso" (`resource_kinds`) e "Fontes de recurso" (`resource_sources`); (b) manter os nomes atuais; (c) fundir os dois cadastros num só.
- **Default vigente:** (a) — mas só se aplica se P-070 mantiver `resource_kinds`.
- **Recomendação:** (a), com os nomes vindos de você: qual é a diferença de negócio entre os dois é a informação que falta, e o código não a tem.

### P-046 — Qual é a cor primária da marca?

- **Faixa de impacto:** `muda comportamento observável`
- **Por que o DEC-30 não resolve:** **Não pode ser inferida do código** — há quatro valores vivos ao mesmo tempo e um quinto de fallback, e `#2D2D2A` e `#050517` são visualmente muito diferentes. É marca, e o DEC-22 marcou como item a resolver antes da demo.
- **Origem:** `Q-44`
- **Fatia:** transversal (a tematização roda antes de qualquer tela) e S17
- **Trava:** trava a paleta do produto inteiro. **Não pode ser inferida do código.**
- **Impacto:** `muda comportamento observável`
- **Contexto:** Há **quatro** valores vivos ao mesmo tempo, em camadas diferentes, e um quinto de fallback. `#2D2D2A` está em `app/definitions/SFG/theme.rb:32` (`COLOR__PRIMARY`) e — verificado — **nunca é lido por nada**. `#050517` está em `app/frontend/css/pub/colors.scss:1` (`$primary`) e é o que **de fato compila** para `.primary-color` (`:103-108`). `#373435` é o que a factory grava no banco (`db/factories/app_theme_factory.rb:17`). `#504746` está em `engines/ux_kit19/lib/livetat/ux_kit19/configuration.rb:14`. E quando `primary_color` é nulo, `app/models/app_theme.rb:200-201` cai em `#444444`. Como o motor de temas não pintava nada (todo o CSS do template está dentro de um comentário), **nem o valor do banco chegava à tela**.
- **Opções:** (a) `#2D2D2A` (o valor canônico declarado, e o que `brand-and-metadata.md` já registra); (b) `#050517` (o que o usuário de fato vê hoje, porque é o que compila); (c) você fornece o hex oficial da marca.
- **Default vigente:** (a), com confirmação **visual contra o app rodando**.
- **Recomendação:** (c) se existir manual de marca; senão (b), porque é a cor que o cliente reconhece como "o sistema dele". `#2D2D2A` e `#050517` são visualmente muito diferentes — isto não é detalhe, e o DEC-22 marcou como item a resolver antes da demo.

### P-067 — Qual é a prova mínima exigida de um aceite?

- **Faixa de impacto:** `muda escopo`  ·  ⛔ **trava código hoje**
- **Por que o DEC-30 não resolve:** O mínimo probatório de um aceite é definição **jurídica**, não de engenharia — e o conjunto proposto (IP, user-agent, hash do texto, versionamento imutável) é **requisito novo, não paridade** (**D-65**).
- **Origem:** `Q-58` + `F-14` (fundidas)
- **Fatia:** S12
- **Trava:** trava `DB-331`, `OPS-333`, a migration `create_contract_deals` (`s12/tasks.md:34`) e é pré-requisito de `BE-342`/`BE-343` (tolerância e bloqueio).
- **Impacto:** `muda escopo`
- **Contexto:** `contract_deals` guarda hoje **`user_id`, `contract_id`, `created_at` e `updated_at`** e nada mais (`db/migrate/20180405164055_create_contract_deals.rb:3-8`). Sem IP, sem user-agent, sem versão congelada e sem impressão do texto — e como o texto vive em `action_text_rich_texts` e pode ser editado no próprio registro, **não há garantia técnica de qual conteúdo foi aceito**. É o **D-65**. O desenho de S12 propõe guardar usuário, versão, data/hora, IP, user-agent e **hash do texto aceito**, com índice único `(user_id, contract_id)` e um exportador de prova (`s12/design.md:88-92, 104`) — o que é **requisito novo, não paridade**.
- **Opções:** (a) manter o mínimo atual (usuário + contrato + data); (b) o conjunto completo proposto: IP, user-agent, **hash imutável do texto** e exportador de prova; (c) (b) **menos o IP**, que é dado pessoal com custo de LGPD e retenção; (d) (b) + versionamento imutável do documento (nova versão = nova linha, edição proibida).
- **Default vigente:** (b) — é a recomendação técnica, mas o mínimo probatório é definição **jurídica**, não de engenharia.
- **Recomendação:** (d). O hash prova o texto, mas sem versão imutável ele não prova **qual versão estava publicada** — e é justamente isso que se pergunta num litígio. IP e user-agent são baratos de guardar e caros de recuperar depois.

### P-084 — Existe consumidor externo dos headers `X-LAA-Agent` / `X-LAA-Token`?

- **Faixa de impacto:** `muda escopo`
- **Por que o DEC-30 não resolve:** **Só você sabe quem chama essa API de fora.** Descartar um contrato de token vivo quebra um consumidor que não está neste repositório — e se houver app móvel ou integração, o prazo de transição precisa ser definido **antes** do cutover.
- **Origem:** `Q-75`
- **Fatia:** S1
- **Trava:** trava a decisão de descartar o contrato de token da engine (`BE-004`).
- **Impacto:** `muda escopo`
- **Contexto:** O par de headers é definido em `engines/auth19/lib/livetat/auth/configuration.rb:15-16` e validado por inteiro em `engines/auth_ux19/.../application_controller.rb:16-17,23-25` (via `Auth::ClientApplication.find_through_token`). Mas os dois controllers de API do próprio app leem **só o token**, sem o agent (`app/controllers/api_application_controller.rb:7` e `api_private_application_controller.rb:7`). **Só você sabe quem chama essa API de fora** — descartar um contrato vivo quebra um consumidor que não está neste repositório.
- **Opções:** (a) descartar o contrato de token de usuário (o JWT o substitui) e **manter** `ClientApplication` funcionando por `Authorization: Bearer`; (b) manter os dois headers durante um período de transição, com prazo definido; (c) descartar tudo.
- **Default vigente:** (a).
- **Recomendação:** (a), mas a resposta é sua: se houver app móvel ou integração externa, precisamos do prazo de transição **antes** do cutover, não depois.

### P-089 — Mantemos Google Analytics no console? (duas fatias decidiram coisas diferentes)

- **Faixa de impacto:** `muda escopo`
- **Por que o DEC-30 não resolve:** Não há paridade a preservar (o ID é GA4 e o snippet é Universal Analytics: **não coleta nada hoje**), mas o próprio documento é explícito: sistema interno corporativo com dado financeiro mandando telemetria de uso para terceiro é **decisão do cliente**, não nossa. E há um conflito entre duas fatias a fechar.
- **Origem:** `Q-80` + `F-29` (fundidas; levantada em dois mapas)
- **Fatia:** S18, S2 e S13
- **Trava:** trava `OPS` de analytics e o CSP — e, hoje, **duas fatias vão implementar coisas diferentes**.
- **Impacto:** `muda escopo`
- **Contexto:** Hoje o snippet é injetado **na primeira linha de cada entrypoint, sem nenhum consentimento**: `.../console/_index.js.erb:1`, `.../start/_index.js.erb:1`, `.../users/sessions/_new.js.erb:1` e `.../contracts/_index.js.erb:2` (este sem nem o guard de deduplicação). E está **quebrado**: o ID é GA4 (`GOOGLE_ANA_APP_ID = "G-7E78XXZX5X"`, `app/definitions/SFG/metadata.rb:7`) mas o snippet é Universal Analytics — carrega `analytics.js` e chama `ga('create', …)` (`app/views/livetat/analytics/_google.js.erb:1-8`). Um ID `G-` não funciona com `ga()`: **na prática não coleta nada hoje**. **O conflito interno:** `s2/design.md:103` (DS2-4) decide **não injetar**; `s13/proposal.md` (Q-09) decide **portar desligado, com o snippet correto pronto**. "Não existe" versus "existe e está desligado" são coisas diferentes.
- **Opções:** (a) não injetar, e o snippet **não entra no repositório**; se for preciso medir, usar a camada de analytics do próprio ai9; (b) portar desligado por configuração, com o snippet GA4 correto pronto para ligar; (c) portar ligado e corrigido.
- **Default vigente:** **os dois ao mesmo tempo** — é o conflito. Nenhuma paridade real se perde ao remover, porque nada é coletado hoje.
- **Recomendação:** (a). Sistema interno corporativo com dado financeiro mandando telemetria de uso para terceiro é decisão do **cliente**, não nossa; e snippet de terceiro desligado num sistema de crédito é uma linha que alguém liga por engano. O custo de ligar depois é um script.

### P-094 — Tipos de garantia: você quer, e qual é o conteúdo?

- **Faixa de impacto:** `muda escopo`
- **Por que o DEC-30 não resolve:** **Não há nada a migrar — o conteúdo é novo e é seu.** Nenhum seed popula `project_guarantee_types`, e no legado o select de tipo de garantia sobe vazio. Numa demo, é exatamente onde o cliente vai clicar.
- **Origem:** `Q-85`
- **Fatia:** S3
- **Trava:** trava `DB-558` e o seed de referência.
- **Impacto:** `muda escopo`
- **Contexto:** A tabela existe (`db/migrate/20220627125208_create_project_guarantee_types.rb`) e **nenhum seed a popula** — zero ocorrências de "guarantee" em `db/seeds.rb`, nenhuma referência em `db/factories/`. Mas a UI e o backend dependem dela: CRUD completo (`project_guarantee_types_controller.rb`), o select do formulário de garantias é alimentado por `ProjectGuaranteeType.all` (`project_guarantees_controller.rb:52`) e há item de menu (`application_helper.rb:157`). Resultado no legado: **o select de tipo de garantia sobe vazio** até alguém cadastrar à mão pelo console. **Não há nada a migrar — o conteúdo é novo e é seu.**
- **Opções:** (a) portar só o mecanismo e semear **tipos plausíveis** no seed de demo, marcados como provisórios; (b) portar o mecanismo e subir vazio, como o legado; (c) você fornece a lista de tipos de garantia reais.
- **Default vigente:** (a).
- **Recomendação:** (c) se você tiver a lista — numa demo, um select de garantias vazio na tela de projeto é exatamente onde o cliente vai clicar. (a) é o plano B.

### P-095 — Teremos acesso ao disco do servidor legado?

- **Faixa de impacto:** `muda escopo`
- **Por que o DEC-30 não resolve:** **Dependência externa**, como o dump: sem acesso ao disco do legado (`public/system/`), os 11 anexos não migram — só os registros, apontando para nada. Anexo de renegociação é documento financeiro.
- **Origem:** `Q-86` + `F-40` (fundidas)
- **Fatia:** S14 (e S9)
- **Trava:** trava a migração de **arquivos** (não a de registros), a tarefa 5.3 de S9 (`s9/tasks.md:419-422`) e o passo de arquivos do runbook.
- **Impacto:** `muda escopo`
- **Contexto:** São **11 anexos** (44 colunas de paperclip) vivendo em `public/system/:attachment/:id/…` **no disco da máquina do legado** — avatar de usuário, imagem de `Picture`, anexo de renegociação, logo de fornecedor e de portador, avatar de projeto e os 4 arquivos de tema. O path é configurado inline em cada model, não num initializer. Sem acesso a esse disco, **os arquivos não migram** — só os registros, que passam a apontar para nada. É dependência **externa**, como o dump, não decisão de desenho.
- **Opções:** (a) construir o ETL de arquivos com o caminho parametrizado e testar contra o seed de demo; o passo real fica no runbook de cutover, marcado como bloqueado por dependência externa; (b) obter uma cópia do diretório `public/system/` (rsync/tar) antes do cutover; (c) migrar só os registros e marcar cada anexo como "arquivo não recuperado", com relatório; (d) aceitar a perda dos binários históricos.
- **Default vigente:** (a) parametrizado.
- **Recomendação:** (b) marcado como **pré-requisito de cutover**, com (c) como rede de segurança. Anexo de renegociação é documento financeiro — perder o binário e manter o registro é pior que não migrar, e um anexo quebrado em silêncio é pior que a ausência declarada.

### P-096 — A "Chave de Integração" do indicador tem consumidor fora do repositório?

- **Faixa de impacto:** `muda escopo`  ·  ⛔ **trava código hoje**
- **Por que o DEC-30 não resolve:** **Pergunta de 30 segundos para quem conhece a operação**, e o repositório não tem a resposta: o campo se chama "Chave de Integração", nada aqui dentro o lê, e se houver BI ou planilha lendo, impor unicidade ou mudar formato quebra do lado de fora **em silêncio**. (b) se houver consumidor externo; (c) se não houver.
- **Origem:** `Q-95` + `F-44` (fundidas; T-D13)
- **Fatia:** S10
- **Trava:** trava `OPS-312`, a tarefa 3.4 de S10 e a decisão de tornar `indicator.key` única (`s10/tasks.md:31, 64`).
- **Impacto:** `muda escopo` — **reclassificada** (o mapa a tinha como `só interno`; a opção (c) remove o campo e a (b) pode quebrar um consumidor externo em silêncio)
- **Contexto:** Dentro do repositório, **nada lê `indicator.key`** para integrar coisa nenhuma — nem API, nem job, nem export. As ocorrências são todas de encanamento: geração a partir do título (`indicator.rb:44`), denormalização (`:49` e `indicator_entry.rb:25`), o próprio campo no formulário, `permit` e mensagem de erro. A chave **não é única hoje**. E a ordenação por chave está inclusive **quebrada**: `indicator.rb:68-69` devolve `"integration_key"`, coluna que **não existe** em `indicators` (a coluna é `key`) — ver A-5. O campo se chama "Chave de Integração" e não integra nada aqui dentro; mas o nome anuncia consumidor externo, e se houver BI ou planilha lendo, mudar formato ou impor unicidade quebra do lado de fora, **em silêncio**.
- **Opções:** (a) **não mexer** — a chave continua obrigatória, derivada do título, sem unicidade e sem mudança de formato; (b) tornar única e imutável após a criação, corrigindo as duplicatas (mesma disciplina do DC-17 e DC-22); (c) remover o campo.
- **Default vigente:** (a).
- **Recomendação:** É uma pergunta de 30 segundos para quem conhece a operação. **(b) se houver consumidor externo; (c) se não houver.** O que não faz sentido é manter um campo chamado "Chave de Integração" que ninguém garante ser estável nem única.

### P-097 — URGENTE: o seed de demonstração não tem dono. Ninguém o constrói

- **Faixa de impacto:** `muda escopo`  ·  ⛔ **trava código hoje**
- **Por que o DEC-30 não resolve:** **URGENTE e sem default — é exatamente o problema.** S18 cria o `demo.rake` vazio, S14 e S15 o consomem, ninguém o preenche. Sem dono, ele chega sexta-feira vazio e as 20 fatias entregam telas vazias. Não é decisão técnica, é atribuição de trabalho.
- **Origem:** `F-33`
- **Fatia:** nenhuma — **é o problema**
- **Trava:** trava a demonstração de **sexta (28/08)**. Sem ele, as 20 fatias entregam telas vazias.
- **Impacto:** `muda escopo`
- **Contexto:** Conferido nos três lados. **S18** cria os alvos vazios: `s18/tasks.md:108-111` — *"criar os alvos `lib/tasks/sfg_etl.rake` e `lib/tasks/demo.rake` **vazios e nomeados**, que S14 e o seed de demo preenchem"*. **S14** o exclui explicitamente: `s14/proposal.md:122` — *"O seed de demonstração (`db/seeds/demo/` + `rake demo:seed`) — é a fatia S-16 do mapa de bloco… S14 o **consome**"*. **S15** também o consome (`s15/tasks.md:88`). O desenho está pronto e é bom: `.migration-ai9/demo-seed-design.md`, 262 linhas, com a cadeia aritmética `Project → Company → (Carrier, limite, taxa) → borderôs → movimentos → saldo`. **Não aparece em nenhum script de cobertura porque não tem ID de inventário** — os scripts contam os 1439 IDs, e o seed não é um deles. Com DEC-22 (escopo completo) e a demo na sexta, é o item mais urgente desta lista inteira.
- **Opções:** (a) criar uma fatia **S20 — seed de demonstração**, com proposal/design/tasks, e rodá-la em paralelo desde já; (b) atribuir o seed a S18 (que já criou o `demo.rake` vazio); (c) atribuir a S14 (que hoje o exclui e o consome); (d) cada fatia semeia o seu próprio domínio dentro de `db/seeds/demo/`.
- **Default vigente:** **nenhum — é exatamente o problema.** Sem dono, o `demo.rake` chega sexta-feira vazio.
- **Recomendação:** (a). O seed cruza todos os domínios e tem uma exigência que nenhuma fatia isolada consegue cumprir: **a cadeia tem de fechar aritmeticamente entre domínios**. (d) é o caminho para cinco seeds que não conversam.

### P-102 — A arte do carousel de login: reusar do legado, gerar, ou você fornece?

- **Faixa de impacto:** `muda escopo`  ·  ⚠ **primeira tela da demo de sexta**
- **Por que o DEC-30 não resolve:** Arte de marca: ou você fornece as imagens, ou se gera, ou fica o fundo tokenizado. É a **primeira tela** que o cliente vê na sexta.
- **Origem:** `F-42`
- **Fatia:** tematização (aparece antes de S1)
- **Trava:** nada tecnicamente — mas é a **primeira tela** que o cliente vê na sexta.
- **Impacto:** `muda escopo`
- **Contexto:** Conferido em `frontend/src/components/LoginCarousel.tsx:11-16`. Os 5 slides padrão do ai9 (imagens geradas por IA + copy sobre "Inteligência Artificial Nativa", "Conectividade Global") foram substituídos por 5 slides novos em pt-BR sobre o domínio real — risco, recebível/borderô, limite por portador, renegociação e indicadores. Mas **os slides estão sem fotografia**: a sessão de migração não tinha gerador de imagem, e reusar arte do legado não foi autorizado. O fundo hoje é a marca tokenizada (grafite + ouro Safegold) com a marca d'água do símbolo — sóbrio e correto nos dois modos, mas é espaço reservado. Registrado como `THEME-07` em `improvements-log.md:19`.
- **Opções:** (a) você fornece 5 imagens (ou uma) da marca; (b) gerar arte por IA numa sessão com a ferramenta disponível; (c) reusar a arte do legado, se houver e se for autorizado; (d) manter o fundo tokenizado — é uma escolha estética defensável, não um buraco.
- **Default vigente:** (d), por ausência de ferramenta.
- **Recomendação:** (d) para sexta, e (a) depois. Fundo de marca sóbrio numa tela de login de sistema financeiro lê como decisão de design; foto genérica de banco de imagens lê como template.

### P-108 — O logo da marca precisa de versões branca e monocromática de verdade?

- **Faixa de impacto:** `só interno`
- **Por que o DEC-30 não resolve:** **A-26 corrige a premissa** (os dois PNG existem); o defeito real é que as variantes `_WHITE` e `_MONO` apontam todas para o mesmo arquivo. O que falta é material de marca que só você pode fornecer — ou a autorização para derivar.
- **Origem:** `Q-91` + `F-46` (fundidas; Q-14 de S17/S16)
- **Fatia:** S17 e S16
- **Trava:** os 4 anexos de tema de S17 e os ícones do manifest de S16.
- **Impacto:** `só interno`
- **Contexto:** **A premissa do material estava errada, em dois documentos (A-26).** O mapa e as fatias S16/S17 afirmavam que `app_symbol.png` e `app_text.png` "não existem no repositório". **Os dois existem**: `app/frontend/images/brand/app_symbol.png` (1,1 KB) e `app_text.png` (1,3 KB), junto de `app_logo_full.png` e várias variantes de tamanho — e a factory de tema os usa (`db/factories/app_theme_factory.rb:22-24`), o que só funciona porque estão lá. **O defeito real é outro:** em `app/definitions/SFG/theme.rb:47-57`, as variantes `_WHITE` e `_MONO` apontam **todas para o mesmo arquivo** da versão normal. Não existe logo branco nem monocromático de verdade — e S16 depende de um símbolo limpo para o `apple-touch-icon` e para o ícone `maskable` 512×512 (sem o qual o Android recorta o logo dentro de um círculo branco).
- **Opções:** (a) derivar as versões branca e monocromática (e o maskable) a partir dos arquivos existentes, registrando que são derivadas; (b) você fornece os originais do manual de marca; (c) usar o mesmo arquivo nas três variantes, como o legado.
- **Default vigente:** (a).
- **Recomendação:** (b) se existirem em algum lugar (site, apresentação, papelaria); senão (a). Um logo colorido sobre fundo escuro é a coisa que mais rápido faz uma demo parecer improvisada.

### P-111 — As colunas renomeadas em 2022 têm leitores externos?

- **Faixa de impacto:** `só interno`
- **Por que o DEC-30 não resolve:** **É informação que você tem e o repositório não**: se algum relatório ou integração externa lê `total_value`, a renomeação de 2022 já mudou a semântica dele desde então (era "R$ Total da dívida", virou "soma do principal das parcelas").
- **Origem:** `Q-94`
- **Fatia:** S9 e S14
- **Trava:** nada — é informação que você tem e o repositório não.
- **Impacto:** `só interno`
- **Contexto:** São **três renomeações, em três tabelas diferentes**, todas em 29/04/2022 — e só **uma** é em `renegotiations`: `rename_column :renegotiations, :total_value, :installments_main_value` (`db/migrate/20220429122226_...:4`), **com mudança real de semântica** (era "R$ Total da dívida", virou "soma do principal das parcelas" — o comentário legado em `renegotiation.rb:273` confirma). As outras duas: `renegotiation_installments.value → main_value` (`20220429122346_...:3`) e `renegotiation_payments.value → installment_paid_value_with_interest_cm` (`20220429122419_...:3`).
- **Opções:** (a) adotar os nomes novos e pronto; (b) adotar os nomes novos e manter uma *view* de compatibilidade com os antigos; (c) manter os nomes antigos.
- **Default vigente:** (a).
- **Recomendação:** (a), a menos que você saiba de relatório ou integração externa lendo `total_value`. A mudança de **semântica** de `total_value` é a que mais importa: um relatório antigo que some essa coluna passou a somar outra coisa desde 2022.

---

## 8. Validação

```
1) IDS P-010..P-117 ............... OK  esperados 108, encontrados 108
2) CADA ID EXATAMENTE 1x .......... OK  sem repeticao
3) SEM FALTANTE / SEM EXTRA ....... OK  faltando=[] extras=[]
4) SOMA DOS BALDES = 108 .......... OK  108
     RESOLVIDA-30 ................. 39
     EXCECAO-1 .................... 2
     EXCECAO-2 .................... 6
     EXCECAO-3 .................... 43
     AINDA-PRECISA ................ 18
5) PLACAR x CONTAGEM REAL ......... OK  {'RESOLVIDA-30': 39, 'EXCEÇÃO-1': 2, 'EXCEÇÃO-2': 6, 'EXCEÇÃO-3': 43, 'AINDA-PRECISA': 18}
6) 'N AINDA PRECISAM' .............. OK  declarado=69 real=69
7) ENTRADAS COMPLETAS ............. OK  69 entradas x 8 campos
8) AINDA-PRECISA POR IMPACTO ...... OK  P-015 P-020 P-021 P-024 P-037 P-038 P-041 P-046 P-067 P-084 P-089 P-094 P-095 P-096 P-097 P-102 P-108 P-111
9) CONTEXTO VERBATIM x ORIGEM ..... OK  69 entradas conferidas

RESULTADO: TODAS AS 9 VERIFICACOES PASSARAM
```

