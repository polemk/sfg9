# Receivables — deltas da fatia S6

> Os 108 requirements de inventário desta capability **já existem** em
> `openspec/specs/receivables/spec.md` (um por ID: BE-150…BE-189, FE-150…FE-189,
> DB-150…DB-167, OPS-150…OPS-159). **Não são recriados aqui.**
>
> O que segue são os requirements **novos**, que não vieram do inventário legado: os
> contratos transversais **C1** e **C2** do `migration-map.md`, que nasceram no Phase 2 e
> não têm ID de inventário porque não descrevem uma feature do `sfg` — descrevem como esta
> fatia é construída no ai9 para que os defeitos de família (D-09, D-16) não voltem.

## ADDED Requirements

### Requirement: C2-S6 — Motor de cálculo único para prévia e gravação
O sistema SHALL calcular todos os valores derivados do borderô em **um único serviço**,
`Receivables::Calculator`, chamado tanto pelo endpoint de prévia quanto pelo caminho de
gravação. Nenhuma fórmula financeira do borderô pode existir em mais de um lugar do código,
e em particular nenhuma pode ser reimplementada no frontend.

Contexto: no legado as 26 fórmulas viviam em `app/models/receivable_entry.rb:38-118` **e**
em `app/views/pub/receivables/new/_body.js.erb:339-504`, com divergências conhecidas (D-09).

#### Scenario: Prévia e gravação produzem exatamente os mesmos valores
- **GIVEN** um payload de borderô válido, com bruto, prazos, deduções e tarifas
- **WHEN** o mesmo payload é enviado ao endpoint de prévia e, em seguida, ao endpoint de
  criação
- **THEN** todos os valores derivados devolvidos pela prévia são **idênticos, campo a
  campo**, aos valores persistidos pela criação

#### Scenario: A prévia não persiste nada
- **GIVEN** um payload de borderô válido
- **WHEN** o endpoint de prévia é chamado
- **THEN** os valores derivados são devolvidos e **nenhum** registro de borderô, tarifa ou
  operação de risco é criado ou alterado

#### Scenario: O frontend não recalcula
- **GIVEN** o formulário de borderô aberto
- **WHEN** o usuário altera um campo de entrada
- **THEN** os campos derivados exibidos vêm da resposta do servidor, e o código do frontend
  não contém nenhuma das fórmulas do calculador

### Requirement: GOLD-S6 — Golden test por fórmula do calculador
O sistema SHALL manter, para **cada** fórmula do `Receivables::Calculator`, um teste golden
com valores extraídos do legado, cobrindo o caso nominal, o ramo de guarda e um caso
negativo ou extremo. A suíte SHALL falhar se qualquer fórmula mudar de resultado.

Contexto: o legado não tem nenhum teste (D-114), e a aritmética em float é **replicada por
decisão do usuário** (DEC-02 / D-104, melhoria declinada em
`.migration-ai9/improvements-log.md`). Sem golden test, "replicar o float" é intenção; com
ele, é contrato verificável.

#### Scenario: Trocar a aritmética quebra os goldens
- **GIVEN** a suíte de goldens verde
- **WHEN** alguém substitui a aritmética em float por `BigDecimal` em qualquer fórmula
- **THEN** os goldens correspondentes falham, tornando a mudança visível em vez de
  silenciosa

#### Scenario: Guardas assiméticas do legado ficam travadas
- **GIVEN** as fórmulas cujas guardas do legado são reconhecidamente estranhas — a guarda do
  CET do banco que olha o prazo da empresa, e o arredondamento em 2 casas sobre a mesma base
  que outra fórmula arredonda em 4
- **WHEN** a suíte de goldens roda
- **THEN** cada uma dessas guardas tem um exemplo dedicado que fixa o comportamento legado,
  de modo que "consertar" reprove o teste

### Requirement: C1-S6 — Escopo por projeto aplicado no endpoint, também quando chega id por parâmetro
O sistema SHALL aplicar o escopo por projeto **no endpoint**, via `current_project!`, e
NUNCA por `default_scope`. Todo endpoint que aceita um identificador por parâmetro
(`receivable_id`, `charge_id`, `receipt_id`) SHALL manter o filtro de projeto ativo ao
resolver esse identificador.

Contexto: o legado descartava o filtro de projeto sempre que chegava um id por parâmetro —
família D-01 / D-16 / D-29 / D-76 / D-100.

#### Scenario: Id de outro projeto é recusado em qualquer verbo
- **GIVEN** um recurso do domínio de recebíveis pertencente ao projeto `P2`
- **WHEN** um usuário cujo projeto corrente é `P1` o referencia por parâmetro em leitura,
  edição ou exclusão
- **THEN** a operação é recusada, nenhum dado de `P2` é exposto e nenhum registro de `P2` é
  alterado

#### Scenario: Inexistente e inacessível respondem igual
- **GIVEN** um identificador que não existe e um identificador que existe em outro projeto
- **WHEN** ambos são usados na mesma rota pelo mesmo usuário
- **THEN** as duas respostas têm o **mesmo status**, de forma que a API não funcione como
  oráculo de existência de id

#### Scenario: Nenhum model do domínio declara escopo implícito
- **GIVEN** os models do domínio de recebíveis
- **WHEN** o código é inspecionado
- **THEN** nenhum declara `default_scope`, e o escopo é legível no ponto onde a consulta é
  montada
