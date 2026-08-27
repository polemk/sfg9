## ADDED Requirements

### Requirement: C1-S11 — Disponibilidade e autenticacao: o IDOR nao e replicado
O sistema DEVE (SHALL) exigir credencial valida em todo endpoint do modulo de disponibilidade, e DEVE resolver o projeto por `current_project!`, validado contra a membership, em vez de buscar o projeto pelo id recebido na rota ou no parametro. Todo filtro por id vindo do cliente (`template_id`, `entry_id`, `company_id`, `parent_id`) DEVE ser aplicado **dentro** do escopo do projeto corrente. O sistema NAO DEVE (SHALL NOT) usar `default_scope` para esse escopo, e NAO DEVE incluir no payload de nenhuma tela padroes pertencentes a outros projetos.

Este requirement e transversal aos 101 IDs da fatia S11 e complementa — nao substitui — os requirements por ID ja existentes nesta capability. Ele existe porque o **D-01** deste modulo e o pior caso da familia D-01/D-16/D-29/D-76/D-100: nao e "o filtro de projeto e descartado quando chega um id", e **nao havia filtro nem autenticacao**. Fonte legada: `app/controllers/api/v1/project_availability_controller.rb`, que herda de `ApplicationController` (nao do `PubApplicationController`) e faz `Project.find(params[:id])` sem escopo. Fonte normativa do desenho: `.migration-ai9/map/projects-cadastros.md` §0.6.

#### Scenario: Requisicao sem credencial e recusada
- **GIVEN** uma requisicao sem credencial
- **WHEN** ela chama `GET /api/v1/projects/:id/availability`
- **THEN** a resposta e 401 e nenhum valor financeiro e devolvido

> Nota: corrige D-01. No legado qualquer requisicao, sem sessao, lia a disponibilidade de qualquer projeto por id.

#### Scenario: Projeto de outro tenant na rota responde 404
- **GIVEN** um usuario autenticado, membro do projeto A, e um projeto B do qual ele nao e membro
- **WHEN** ele chama a disponibilidade informando o id do projeto B na rota
- **THEN** a resposta e 404 e nenhum dado do projeto B e devolvido

#### Scenario: Lancamento de outro projeto nao e alcancavel por id
- **GIVEN** um usuario membro do projeto A e um lancamento do projeto B
- **WHEN** ele busca informando o id desse lancamento
- **THEN** a lista devolvida e vazia
- **AND WHEN** ele tenta alterar ou excluir esse lancamento pelo id
- **THEN** a resposta e 404 e o lancamento do projeto B permanece inalterado

#### Scenario: Padrao pai de outro projeto e recusado
- **GIVEN** um usuario cujo projeto corrente e o A
- **WHEN** ele cria um padrao de disponibilidade informando como pai um padrao do projeto B
- **THEN** a operacao e recusada e nenhum padrao e criado

#### Scenario: Nenhum padrao de outro projeto viaja no payload
- **GIVEN** a tela de padroes de disponibilidade de um projeto
- **WHEN** o payload que a alimenta e inspecionado
- **THEN** ele contem apenas padroes globais e padroes do projeto corrente

> Nota: corrige o vazamento do legado, que embutia `AvailabilityTemplate.all` — todos os padroes de todos os projetos — num atributo `data-templates` do HTML, e ainda filtrava os niveis derivados do pai sobre esse JSON global.

#### Scenario: Catalogo global de padroes nao e escopado
- **GIVEN** o catalogo global de padroes de disponibilidade
- **WHEN** um usuario autenticado o consulta
- **THEN** a resposta e 200 e o catalogo nao e filtrado por projeto

> Nota: a regra do catalogo global e **oposta** a das entidades de projeto, e e assim de proposito. O menu esconde a tela de administracao do catalogo, nao o dado do catalogo.

#### Scenario: Escopo nao vem de default_scope
- **GIVEN** os models escopados por projeto deste modulo
- **WHEN** o codigo e inspecionado
- **THEN** nenhum deles declara `default_scope`, e cada endpoint declara o escopo em uma linha visivel

> Nota: jobs, seeds e rakes deste modulo cruzam projetos legitimamente — `SeedGlobalTemplatesJob` e `PropagateGlobalTemplateJob` replicam padroes em todos os projetos. Um `default_scope` os contaminaria em silencio.
