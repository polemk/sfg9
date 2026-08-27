## ADDED Requirements

### Requirement: C1-S3 — Catalogo global nao recebe escopo de projeto
O sistema DEVE (SHALL) tratar `carriers`, `carrier_groups`, `segments`, `sub_segments` e `project_guarantee_types` como catalogo **global**: nenhum destes recursos tem `project_id`, nenhum inclui o concern `ProjectScoped` e nenhum endpoint destes recursos chama `current_project!`. A leitura e liberada a qualquer usuario autenticado, inclusive o Colaborador (DEC-18.4); a escrita e negada **no servidor** por `require_role!` e `require_not_readonly!`, nunca apenas na view.

Este requirement e transversal aos 51 IDs da fatia S3 e complementa — nao substitui — os requirements por ID (BE-067..078, BE-700..706) ja existentes nesta capability. Ele existe porque a regra desta fatia e **oposta** a das fatias S4 e S11, onde todo endpoint declara `current_project!`. Fonte normativa: `.migration-ai9/map/projects-cadastros.md` §0.6, regra 4. Regra em uma frase: **o menu esconde a tela de administracao do catalogo, nao o dado do catalogo.**

#### Scenario: Usuario sem projeto corrente le o catalogo
- **GIVEN** um usuario autenticado que ainda nao e membro de nenhum projeto
- **WHEN** ele lista portadores, grupos, segmentos, subsegmentos ou tipos de garantia
- **THEN** a resposta e 200 com o catalogo completo, e nenhum endpoint exige projeto corrente

#### Scenario: Colaborador le mas nao escreve
- **GIVEN** um usuario com papel Colaborador
- **WHEN** ele lista qualquer um dos cinco catalogos
- **THEN** a resposta e 200
- **AND WHEN** ele tenta criar, alterar ou excluir em qualquer um dos cinco
- **THEN** a resposta e 403, decidida no servidor

#### Scenario: Somente-leitura nao escreve nem sendo Admin
- **GIVEN** um usuario com papel Admin e `user_is_readonly` verdadeiro
- **WHEN** ele tenta criar, alterar ou excluir em qualquer um dos cinco catalogos
- **THEN** a resposta e 403

#### Scenario: Hierarquia verificada nos dois sentidos
- **GIVEN** a escala de hierarquia do ai9, em que menor `hierarchy_level` significa mais poder (contrato C3, escala invertida em relacao ao legado)
- **WHEN** um Admin cria um portador
- **THEN** a criacao e aceita
- **AND WHEN** um Colaborador cria um portador
- **THEN** a criacao e recusada com 403

> Nota: os dois sentidos sao obrigatorios. Um teste que verifique apenas que "a trava existe" continua passando se o sinal da comparacao de hierarquia estiver invertido — e o sinal invertido da poder de OG a um Colaborador.

#### Scenario: Anonimo nao le o catalogo de tipos de garantia
- **GIVEN** uma requisicao sem credencial
- **WHEN** ela chama `GET /api/v1/project_guarantee_types`
- **THEN** a resposta e 401

> Nota: corrige D-23 (legado: `requires_current_user? == false` no `project_guarantee_types_controller`, o endpoint respondia para anonimo).

#### Scenario: Id por parametro nao amplia nem quebra o conjunto
- **GIVEN** o catalogo de portadores e um `group_id` que nao existe
- **WHEN** o cliente busca portadores filtrando por esse `group_id`
- **THEN** a resposta e 200 com lista vazia, nunca a lista inteira nem um erro 500
