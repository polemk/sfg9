# Design: S11 — Disponibilidades em ai9

> **Este documento não duplica o mapa.** As 101 linhas item-a-item estão em
> `.migration-ai9/map/projects-cadastros.md`, seções **§2.6** (BE-110..117), **§2.8**
> (FE-107..112), **§2.11** (BE-120..131), **§2.12** (BE-132..139), **§2.13** (BE-140..149),
> **§2.14** (FE-120..149), **§2.15** (DB-120..135) e **§2.16** (OPS-120..129), mais
> OPS-081..084 em **§2.10** e DB-085 em **§2.9**.
> As decisões de comportamento estão em **§3** (DC-20 a DC-37) e as perguntas em **§6**
> (Q-01, Q-07, Q-08, Q-09, Q-10). Aqui está só a **decisão de desenho da fatia**.

## 1. O contrato C1 nesta fatia

O escopo é aplicado **no endpoint**, por `current_project!`, **nunca** por `default_scope`.
`availability_templates` de projeto, `availability_entries` e o bloqueio de padrão incluem
`ProjectScoped`; o **catálogo global** de padrões (`project_id IS NULL` + marca explícita)
**não** é escopado — mesma regra da S3.

**Esta fatia carrega o pior caso da família D-01/D-16/D-29/D-76/D-100**, e ele é diferente
dos outros: não é "o filtro é descartado quando chega um id", é **não havia filtro nenhum**.

`app/controllers/api/v1/project_availability_controller.rb` do legado herda de
`ApplicationController` (não do `PubApplicationController`) e faz `Project.find(params[:id])`
sem escopo. **Qualquer requisição, sem sessão, lê a disponibilidade de qualquer projeto por
id.** É o **D-01**, e é a origem do nome que a família inteira leva.

No ai9 esse endpoint (BE-117, BE-149) nasce montado em `api/v1/base.rb`, que já roda
`before { restrict_visitor_access! }`, e resolve o projeto por `current_project!` — o
`params[:id]` da rota é **validado contra a membership**, nunca usado para buscar.

Os ids por parâmetro do módulo que precisam de teste de escopo cruzado:
`template_id`, `entry_id`, `company_id`, `parent_id` (o pai de um padrão) e o `:id` do
projeto na rota de disponibilidade. **Um teste por endpoint** — está na seção 6 do
`tasks.md`.

Além disso, dois **vazamentos de payload** que não são escopo de banco e sim de
serialização, e por isso escapam de qualquer teste de model:

- O legado embutia **`AvailabilityTemplate.all`** — todos os padrões de todos os projetos —
  num atributo `data-templates` do HTML (FE-110, FE-139).
- O filtro de "níveis derivados do pai" rodava sobre esse JSON global (FE-148).

No ai9 os níveis vêm de **busca sob demanda no servidor**, e um `parent_id` de outro projeto
faz a operação ser **recusada**.

## 2. A remodelagem que o resto depende: uma estrutura hierárquica ordenável
`§2.9 DB-085` · `§2.15 DB-120, DB-121, DB-131` · `§2.12 BE-137, BE-138` · DC-21

O legado representa a árvore de 3 níveis com **três colunas numéricas + uma coluna
`position` do tipo string + nove colunas redundantes**, e `top_parent_id` com default `0`.
Consequências medidas:

- **Ordenação lexicográfica**: 12 irmãos ordenam `1, 10, 11, 12, 2, 3…` — "10" antes de "2".
- **Órfãos apontando para o id 0**, porque o default `0` não é FK.
- **Reordenação quadrática**: os três `import` rodavam **dentro** do laço de 1º nível.
- **Nível derivado com ` |= `** (OR **bit a bit**): um filho de nível 2 herdando de 5 virava
  **7**. Funcionava por acidente quando os valores eram `0`/`nil`.

**Desenho no ai9:** uma estrutura hierárquica ordenável — `parent_template_id` (FK real, sem
default `0`), `top_parent_id` (FK), `position` **inteira** dentro do irmãozio, índices em
`project_id` e `parent_template_id`, profundidade máxima 3 validada no serviço. O nível é
**derivado do pai de forma determinística** (`parent.level + 1`), pai inexistente → 422, e a
criação concorrente **não colide** (posição atribuída dentro de transação).

**Esta é a primeira tarefa da fila e a mais consequente.** Toda regra de consolidação, de
obrigatoriedade hierárquica e de propagação lê essa estrutura.

## 3. Os quatro jobs — o bloqueio termina junto com a operação
`§2.6 BE-113..115` · `§2.13 BE-144..147` · `§2.10 OPS-081..084` · `§2.16 OPS-120..124`

O legado tem quatro jobs (ativar, desativar, remover, propagar) e **todos** compartilham o
mesmo defeito estrutural (**D-05**):

| Defeito no legado | Desenho no ai9 |
| ----------------- | -------------- |
| Exceção engolida; `destroy_failed_jobs? false`; sem retry — o job falho **sumia da fila** | Sidekiq com **retry por default** (`reuse`, OPS-128) e dead set visível ao esgotar |
| `unlocked!` chamado **só no caminho feliz** → padrão **bloqueado para sempre**, sem recuperação | Bloqueio liberado em **`ensure`**, com ou sem sucesso (BE-147) |
| Sem transação; remoção fazia `entries.destroy_all` contornando `restrict_with_error` | Remoção **atômica** em `AR transaction`; lançamentos vinculados tratados **explicitamente** (DC-20: o servidor **recusa 422**) |
| A guarda de obrigatoriedade existia e **nunca era executada** no fluxo real | A regra roda **no serviço, antes de enfileirar** (BE-114, BE-145) |
| Logger global restaurado **dentro** do bloco protegido: uma falha deixava o logger desligado para o **worker inteiro** | Restauração fora do bloco protegido (OPS-122) |
| Estado gravado sobre registro já destruído; nulo sobrevivente do achatamento da lista | Estado como `enum` string (`pending`/`running`/`done`/`failed`, Lacuna **L-10**), gravado antes do destroy |
| `is_adjusted` **não** era copiado do global para o padrão de projeto (OPS-120), e a propagação **forçava obrigatoriedade a 1** (OPS-121), divergindo do seed | Atributos copiados **fielmente**, pelos dois caminhos, com o mesmo código |

**Decisão de desenho:** um único serviço de bloqueio (`lock!`/`unlock!` com motivo, autor e
instante — DB-128) usado pelos quatro jobs, e um único `enum` de estado de tarefa (DB-129).
Quatro implementações do mesmo `ensure` é como o legado chegou onde chegou.

**Padrões travados no legado migram desbloqueados e são reportados** (DB-128) — não se
importa um estado que só existe porque um job morreu em 2019.

**Idempotência** (BE-144): segunda ativação → **409**, não um segundo job. Reexecutar a
remoção depois de concluída termina **sem erro** (OPS-124).

## 4. Progresso: Action Cable, nunca polling
`§2.8 FE-108` · `§2.16 OPS-121, OPS-127`

Princípio 10. O progresso chega por `JobProgressChannel` invalidando query
(`useCable`/`useChannel` já existem; o canal e o `useJobProgress` vêm da **S0**, Lacuna L-08).

**Progresso é por projeto**, não global (OPS-121) — no legado as propagações se atropelavam
escrevendo no mesmo lugar, e o delegate padrão apenas imprimia no stdout: **nenhuma tela
consumia o progresso**.

## 5. O motor de números — onde as quatro perguntas mordem
`§2.11 BE-125..131` · `§2.13 BE-148` · DC-25, DC-27, DC-28, DC-29, DC-30, DC-34

Esta é a parte da fatia que **muda número exibido**, e é a que fica atrás das respostas.

### 5.1 Ler a grade nunca cria registro (DC-30) — decidido, sem pergunta

No legado a leitura instancia em memória, mas `parent_entry`, `next_level_entries` e
`update_mirror!` **salvam no banco**, e os derivados herdam o autor de quem **abriu a tela**.
No ai9 **abrir a grade nunca cria registro**; os derivados são materializados por gravação
explícita e são **identificáveis como derivados**.

Corolário (DC-26): excluir lançamento de 1º nível **não cria** o pai. No legado
`parent_entry` era chamado **antes** do destroy e criava o registro pai — havia inclusive um
`TODO #7408` admitindo que o cenário multiempresa não foi fechado.

### 5.2 Correção por dias úteis — aplicada **uma única vez** (DC-25, Q-07)

O **D-02** é decaimento composto: `original_value` é regravado a cada mudança de `value`, e a
correção é reaplicada sobre o valor **já corrigido**. Salvar duas vezes o mesmo valor produz
números diferentes.

Desenho: `original_value` guarda o **valor digitado** e nunca é sobrescrito por valor
corrigido (DB-125); a correção é função de `original_value`, não de `value`; o cálculo é
**no servidor** (`date-fns` no front é só formatação). Na tela, **os dois valores ficam
visíveis** (FE-134) — hoje o usuário digita X e vê Y, sem indicação.

**Feriados (DC-29, Q-09): default é manter seg–sex sem feriados.** Incluir feriados muda o
resultado financeiro de **todo o histórico** e exige escolher o calendário (nacional,
estadual, bancário).

**O ETL precisa reportar** quanta base já tem valor corrigido mais de uma vez (DB-125). Sem
esse relatório não dá para saber o tamanho do estrago.

### 5.3 Consolidação e "total" — duas regras de soma na mesma tela (DC-27/DC-34, Q-08/Q-10)

Hoje convivem, na mesma tela:

- a **consolidação geral** soma **bruto**, ignorando `is_cumulative` e `is_debit`;
- os **nós com filhos** aplicam cumulatividade e sinal;
- o **total geral** usa `value` e cada **card de padrão base** usa `virtual_value` — mesma
  palavra, duas métricas.

Desenho: **uma definição só de "total"**, subordinada à resposta de Q-08. A marca de
consolidação passa a ser **explícita** (DB-126), não inferida por `company_id` nulo — porque
a rotina `fix__7412` do legado **reatribuiu empresa nula à primeira empresa**, e o ETL
precisa distinguir consolidação legítima de dado sujo.

**DC-28 — sem pergunta:** `is_credit?`/`is_debit?` do legado comparam a **string traduzida**,
então qualquer `operation_type` fora de `C`/`D`/`S`/`M` era tratado como **crédito**. No ai9
compara-se o **código**, e `operation_type` vira `enum` de conjunto fechado.

### 5.4 Saldo acumulado determinístico (BE-128)

No legado o acumulado dependia de **quais células já haviam sido preenchidas** — o mesmo
conjunto de lançamentos produzia números diferentes conforme a ordem de digitação.
No ai9 é função do conjunto, não da ordem, e os desativados ficam **fora** da conta.

### 5.5 Propagação em cascata atômica (BE-129)

O legado fazia saves recursivos + upsert em massa **sem transação** e com `validate: false`.
No ai9: `AR transaction` + **guarda de ciclo**.

## 6. Catálogo global de padrões — a busca que derruba a requisição
`§2.12 BE-132` · `§2.14 FE-136` · `§2.15 DB-134` · **Q-01**

`availability_templates_controller.rb:22` do legado usa a coluna **`default_position`** na
busca com texto. **Nenhuma migration a cria.** Se ela não existe em produção, a busca de
padrões globais está **quebrada há anos** e ninguém reportou — e o parcial que a usa
(`_child_widget.html.erb`) **não é renderizado por ninguém**.

Desenho: `default_position` **não é portada** (DB-134); a busca é por **substring** (não só
prefixo) e catálogo vazio **não gera SQL inválido**. É uma das **duas provas** que sustentam
o **DEC-04** (o ETL aborta com relatório diante de estrutura desconhecida) e por isso
**Q-01 é uma pergunta de confirmação contra o banco de produção**, não de decisão.

### Criação de padrão global — duas coisas escondidas do usuário

- `is_mandatory |= 1`: **todo global nascia obrigatório**, ignorando o formulário.
- `should_insert_on_existing_projects` com default `1` e **nunca exposto**: **toda criação
  disparava job em todos os projetos**.

No ai9 as duas viram escolha do usuário, na tela (BE-134, DB-132, FE-139), e alterar
`is_adjusted`/`is_cumulative` de um global **propaga** aos derivados, em segundo plano, com
progresso por projeto (DC-31) — hoje não propaga, e o catálogo mente sobre os padrões que
gerou.

## 7. Frontend — o que muda de forma visível

| Decisão | Onde | Por quê |
| ------- | ---- | ------- |
| **Nasce habilitado** | FE-142, e o item de menu em FE-119 (S4) | DEC-15.1/DC-37: `locked` passa a ser lido do **item**, e nenhum dos quatro nasce marcado. Fecha **D-90** pelo efeito |
| **Grade sempre expandida** | FE-127, DC-35 | O código de colapsar/expandir está **comentado** no HTML e no SCSS do legado. Porta-se o que roda; expandir/recolher entra como comportamento **novo do `DataTable`** (S0), não como paridade |
| **Sinal negativo no próprio valor** | FE-125 | O legado exibia em **módulo** e sinalizava só por vermelho — ambíguo e inacessível |
| **Natureza da operação legível** | FE-129 | O legado exibia o código `C`/`D` cru |
| **Menu de contexto nunca vazio** | FE-145, FE-108 | O legado deixava o menu de "global + com filhos" **sem nenhum item**, e tinha `ReferenceError` em `openDetail` e a constante inexistente `M.SUCESS` |
| **Uma fonte de verdade para "é estreito"** | FE-123 | O legado decidia no servidor por *user agent* **e** no cliente por detecção própria, que podiam discordar. No ai9: `hooks/useMobile.ts`, no cliente |
| **Campos imutáveis explicados** | FE-109, DC-24 | Na edição só o título é editável (todo o resto está dentro de `if id.blank?`), sem nenhuma explicação. Mantém-se a restrição, agora **com a razão na tela** |
| **Estado "concluído" não é portado** | FE-146, DC-36 | Os estilos `.disabled` e `.project_availability_completed` **não têm emissor**: sem coluna, sem controller, sem o que preservar |
| **Guarda de envio duplo por célula** | FE-130 | O legado usava `$('form')` global, com efeito colateral em toda a tela |
| **Calendário pt-BR** | FE-122, Lacuna **L-06** | Não há date-picker em `components/ui/`; nasce `Calendar.tsx` sobre `react-day-picker`, com dias marcados |

## 8. O que o ETL desta fatia precisa reportar antes do cutover

Não é tarefa do ETL (S14) inventar critério; é desta fatia declará-lo:

1. Quantos lançamentos têm valor corrigido **mais de uma vez** (DB-125 / D-02).
2. Quais consolidações são **legítimas** e quais são resíduo do `fix__7412`, que reatribuiu
   empresa nula à primeira empresa (DB-126).
3. Quais padrões estão **travados** — migram destravados e o relatório sai (DB-128).
4. Duplicatas de `(project_id, company_id, template_id, date)` — limpeza e deduplicação
   **antes** de aplicar o índice único (DB-133).
5. Órfãos apontando para `top_parent_id = 0` (DB-120).

## 9. Riscos assumidos

| Risco | Mitigação |
| ----- | --------- |
| **D-01 replicado** — o endpoint de disponibilidade volta a ser IDOR | Montado em `api/v1/base.rb` (autenticação global) + `current_project!`; teste explícito de requisição **sem sessão** → 401 e de id de outro projeto → 404 (tarefas 6.1 e 6.2) |
| **Remoção destrutiva** — `entries.destroy_all` contornando `restrict_with_error` | Servidor **recusa 422** (DC-20); remoção em transação; teste de que **nada permanece** em falha |
| **Padrão bloqueado para sempre** | `ensure` obrigatório nos quatro jobs, um único serviço de bloqueio, teste que **força a falha** e confere o desbloqueio |
| **Q-07/Q-08/Q-10 sem resposta** travariam a fatia inteira | Não travam: as seções 1 a 4 do `tasks.md` são independentes. Só as tarefas de cálculo (5.x) ficam atrás, e estão marcadas |
| **Remodelagem da hierarquia** é a maior mudança estrutural do bloco | É a **primeira** tarefa da fila, com o ETL reportando órfãos antes; nenhuma regra de consolidação é escrita antes de ela fechar |
| **`availability_entries` é a maior tabela do módulo** e nunca teve índice | Índices `(project_id, date)`, `(template_id, date)` e o único composto na mesma migration da tabela; carga só depois da deduplicação |
