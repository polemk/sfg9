# Delta: projects — contrato de escopo por projeto (C1)

> **Não recria requisitos.** Os requisitos de paridade do legado já existem em
> `openspec/specs/projects/spec.md` e são referenciados pelos IDs de inventário no
> `proposal.md` desta mudança. O que está aqui são os requisitos **que nascem da base ai9**
> — não têm origem no legado, portanto não existem lá: são as duas condições que o bloco
> `auth-admin` acrescentou ao desenho §0.6 (DC-08) e a proibição de `default_scope`.

## ADDED Requirements

### Requirement: C1-01 — O projeto corrente é revalidado a cada requisição

O sistema SHALL revalidar contra `memberships`, **a cada requisição**, o projeto corrente do
usuário — tanto o valor armazenado em `users.current_project_id` quanto o recebido em
`X-Project-Id`. O valor armazenado é preferência, nunca autorização.

> Nota: requisito da base ai9, não do legado. Sem ele, uma participação revogada continua
> valendo enquanto a coluna estiver preenchida.

#### Scenario: Participação revogada com projeto corrente ainda gravado
- **GIVEN** um usuário cujo `current_project_id` aponta para um projeto do qual a
  participação acabou de ser revogada
- **WHEN** ele faz a requisição seguinte a qualquer endpoint escopado
- **THEN** o projeto corrente não é aceito e nenhum dado daquele projeto é exposto, sem
  depender de logout ou de novo login

#### Scenario: Troca de projeto por cabeçalho, com participação
- **GIVEN** um usuário com participação em dois projetos
- **WHEN** ele envia `X-Project-Id` do segundo projeto
- **THEN** a resposta é escopada ao segundo projeto

#### Scenario: Troca de projeto por cabeçalho, sem participação
- **GIVEN** um usuário sem participação no projeto informado
- **WHEN** ele envia `X-Project-Id` daquele projeto
- **THEN** o escopo não é trocado e nenhum dado do projeto é exposto

### Requirement: C1-02 — Projeto inexistente e projeto sem participação respondem igual

O sistema SHALL responder **o mesmo status HTTP** quando o projeto pedido não existe e
quando existe mas o usuário não participa dele.

> Nota: requisito da base ai9. Distinguir 403 de 404 transformaria o resolvedor de projeto
> corrente num oráculo de existência de ids de projeto.

#### Scenario: Projeto inexistente
- **GIVEN** um id de projeto que não existe
- **WHEN** o usuário o informa como projeto corrente
- **THEN** a resposta é 404

#### Scenario: Projeto existente sem participação
- **GIVEN** um id de projeto que existe e no qual o usuário não participa
- **WHEN** o usuário o informa como projeto corrente
- **THEN** a resposta é 404, idêntica à do projeto inexistente, sem nenhuma diferença de
  corpo, cabeçalho ou tempo de resposta que revele a existência

### Requirement: C1-03 — O escopo é aplicado no endpoint, nunca por `default_scope`

O sistema SHALL aplicar o escopo por projeto explicitamente no endpoint, via
`current_project!` e o concern `ProjectScoped`, e SHALL ignorar sempre o `project_id`
recebido no corpo da requisição.

> Nota: requisito da base ai9 (desenho normativo em
> `.migration-ai9/map/projects-cadastros.md` §0.6). O legado descartava o filtro de projeto
> sempre que chegava um id por parâmetro — família D-01/D-16/D-29/D-76/D-100.

#### Scenario: Filtro por id de registro de outro projeto
- **GIVEN** um usuário escopado ao projeto A
- **WHEN** ele filtra por um id de registro que pertence ao projeto B
- **THEN** o resultado é vazio, e não um erro de autorização — a existência do registro
  alheio não é confirmada

#### Scenario: `project_id` enviado no corpo da requisição
- **GIVEN** uma criação ou atualização que traz `project_id` no corpo
- **WHEN** a requisição é processada
- **THEN** o valor recebido é ignorado e vale o projeto corrente do servidor

#### Scenario: Rotina que cruza projetos
- **GIVEN** um job, seed ou rake que legitimamente opera em vários projetos
- **WHEN** ele recebe `project_id` como argumento explícito
- **THEN** ele opera no projeto pedido, provando que não há escopo implícito de sessão
