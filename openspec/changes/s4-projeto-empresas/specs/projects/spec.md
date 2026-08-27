## ADDED Requirements

### Requirement: C1-S4 — Nenhum id por parametro fura o escopo de projeto
O sistema DEVE (SHALL) aplicar o escopo de projeto **no endpoint**, por `current_project!`, e DEVE aplicar todo filtro por id vindo do cliente **dentro** desse escopo. O sistema NAO DEVE (SHALL NOT) usar `default_scope` para escopo de projeto, e NAO DEVE aceitar `project_id` vindo do corpo da requisicao, nem no `create` nem no `update`.

Este requirement e transversal aos 123 IDs da fatia S4 e complementa — nao substitui — os requirements por ID ja existentes nesta capability. Ele existe porque a familia de defeitos **D-01 / D-16 / D-29 / D-76 / D-100** e um padrao repetido, nao um caso isolado: em `app/controllers/pub/project_guarantees_controller.rb:21-22` do legado a relacao escopada por projeto e **reatribuida**, nao filtrada, quando chega `project_guarantee_id`. Fonte normativa: `.migration-ai9/map/projects-cadastros.md` §0.6.

#### Scenario: Busca com id de outro projeto devolve vazio
- **GIVEN** um usuario membro do projeto A e um registro que pertence ao projeto B
- **WHEN** ele busca informando o id desse registro (`company_id`, `provider_id`, `project_guarantee_id`, `project_id` ou `importing_id`)
- **THEN** a resposta e 200 com lista vazia, e nenhum dado do projeto B e devolvido

> Nota: vazio, e nao 403 — responder 403 confirmaria a existencia do registro alheio.

#### Scenario: Detalhe e escrita com id de outro projeto respondem 404
- **GIVEN** um usuario membro do projeto A e um registro do projeto B
- **WHEN** ele pede o detalhe, altera ou exclui esse registro pelo id
- **THEN** a resposta e 404 e o registro do projeto B permanece inalterado

#### Scenario: project_id do corpo e ignorado na criacao
- **GIVEN** um usuario cujo projeto corrente e o A
- **WHEN** ele cria uma empresa, um fornecedor ou uma garantia enviando `project_id` do projeto B no corpo
- **THEN** o registro e criado no projeto A

#### Scenario: project_id do corpo e ignorado na atualizacao
- **GIVEN** uma empresa do projeto A e um usuario cujo projeto corrente e o A
- **WHEN** ele atualiza a empresa enviando `project_id` do projeto B no corpo
- **THEN** a empresa permanece no projeto A

> Nota: corrige D-23 (legado: o `project_id` era forcado no create e esquecido no update, entao era possivel mover fornecedor para outro projeto por campo escondido).

#### Scenario: Projeto inexistente e projeto sem membership respondem o mesmo status
- **GIVEN** um usuario autenticado
- **WHEN** ele referencia um projeto que nao existe, e depois um projeto que existe mas do qual nao e membro
- **THEN** as duas respostas tem o mesmo status

> Nota: distinguir 403 de 404 transformaria a API em oraculo de existencia de id.

#### Scenario: Membership revogada deixa de valer no request seguinte
- **GIVEN** um usuario com o projeto A como projeto corrente
- **WHEN** a membership dele no projeto A e revogada e ele faz a requisicao seguinte, sem novo login
- **THEN** o acesso ao projeto A e negado, porque `current_project!` revalida a membership a cada request

#### Scenario: Escopo nao vem de default_scope
- **GIVEN** os models escopados por projeto desta fatia
- **WHEN** o codigo e inspecionado
- **THEN** nenhum deles declara `default_scope`, e cada endpoint declara o escopo em uma linha visivel

> Nota: `default_scope` vaza para `unscoped`, quebra `joins` em silencio, contamina jobs e seeds que legitimamente cruzam projetos, e torna o escopo invisivel na leitura.
