# Companies & Carriers Specification

## Purpose
Cadastros de contraparte do Safegold: empresas e fornecedores (escopados por projeto)
e portadores, grupos de portadores, segmentos e subsegmentos (catalogos globais,
conforme DEC-07/DEC-09). Cobre busca, CRUD, regras de dominio, esquema de dados e as
integracoes de apoio (ReceitaWS, anexos, importadores do legado).
Cobre os IDs 050–079 do inventario de migracao (`.migration-ai9/feature-inventory.md`).

## Requirements

### Requirement: BE-050 — Busca de empresas do projeto corrente
O sistema DEVE (SHALL) listar empresas escopadas ao projeto corrente do usuario, aceitando termo de busca `q`, ordenacao e paginacao `l`/`o` que efetivamente se aplicam. Fonte legada: `config/routes.rb:131`; `app/controllers/pub/companies_controller.rb:14-32`, `:99-107`.

#### Scenario: Busca com termo e paginacao
- **GIVEN** um projeto corrente com 45 empresas e o usuario e membro desse projeto
- **WHEN** o cliente busca com `q=""`, `l=20`, `o=20`
- **THEN** a resposta traz exatamente 20 empresas, a partir da 21a, ordenadas conforme solicitado, e o total informado e 45 (contagem sem limite)

> Nota: corrige D-20 (legado: `where!` seguido de `.order/.limit/.offset` nao-bang descartava ordenacao, limite e offset — a lista voltava completa e nao ordenada, e `@total_count` era a contagem da pagina). Muda o que a tela faz: hoje ela traz tudo.

#### Scenario: Empresa de outro tenant nao e alcancavel por id
- **GIVEN** uma empresa que pertence a um projeto do qual o usuario nao e membro
- **WHEN** o cliente busca informando o `company_id` dessa empresa
- **THEN** o resultado e vazio e nenhum dado da empresa alheia e devolvido

> Nota: corrige D-29/D-23 (legado: com `company_id` preenchido o filtro de projeto era descartado e a busca ocorria em qualquer projeto). No ai9 o projeto corrente vem do JWT validado contra membership, nao de cookie (DEC-07).

#### Scenario: Busca textual insensivel a caixa
- **GIVEN** uma empresa de titulo `Livetat Apps`
- **WHEN** o usuario busca por `LIVETAT`
- **THEN** a empresa aparece no resultado

### Requirement: BE-051 — Modo "dash" da busca de empresas
O sistema DEVE (SHALL) oferecer um modo de resumo para o painel que devolve empresas ordenadas por titulo ascendente com limite e offset aplicados e ignora o filtro textual. Fonte legada: `app/controllers/pub/companies_controller.rb:20-22`.

#### Scenario: Resumo ordenado por titulo
- **GIVEN** um projeto corrente com empresas de titulos variados
- **WHEN** o cliente pede o modo dash com `l=5`, `o=0` e um `q` qualquer
- **THEN** sao devolvidas 5 empresas em ordem alfabetica de titulo e o termo `q` e ignorado

### Requirement: BE-052 — Resumo de limites de risco por empresa
O sistema DEVE (SHALL) devolver, para uma data, o resumo de limites por tipo de operacao de risco de uma empresa (ou do projeto inteiro quando nenhuma empresa e informada), incluindo o indicador de existencia de controles. Fonte legada: `config/routes.rb:130`; `app/controllers/pub/companies_controller.rb:70-84`; `app/models/company.rb:68-88`.

#### Scenario: Resumo do projeto quando nenhuma empresa e informada
- **GIVEN** um projeto corrente com controles de risco ativos
- **WHEN** o cliente consulta o resumo sem `company_id`, para a data de hoje
- **THEN** a resposta traz a lista de limites por tipo de operacao de risco ativo, ordenada por titulo, com os percentuais formatados com 2 casas, e o indicador de que existem controles

#### Scenario: Divisao por zero no percentual utilizado
- **GIVEN** uma empresa com limite total zero e limite utilizado maior que zero
- **WHEN** o cliente consulta o resumo
- **THEN** o percentual utilizado devolvido e 100%, sem erro

#### Scenario: Data invalida
- **GIVEN** um usuario autenticado no projeto corrente
- **WHEN** o cliente consulta o resumo com `date=31/02/2026`
- **THEN** a resposta e um erro de validacao de parametro (nao um erro interno)

> AMBIGUIDADE: no legado a data invalida ou ausente nao era tratada e estourava 500 dentro de `operations_on`; falta confirmar qual e a data-padrao esperada pelo negocio quando `date` nao vem.

### Requirement: BE-053 — Formulario de nova empresa / edicao
O sistema DEVE (SHALL) fornecer os dados necessarios para abrir o formulario de criacao (ja associado ao projeto corrente) e de edicao de uma empresa existente. Fonte legada: `app/controllers/pub/companies_controller.rb:34-45`, `:116-118`.

#### Scenario: Novo formulario sem projeto corrente
- **GIVEN** um usuario autenticado que nao tem projeto padrao definido
- **WHEN** ele pede o formulario de nova empresa
- **THEN** o sistema responde com um erro de pre-condicao explicito ("e necessario ter um projeto padrao"), e nao com um erro interno

#### Scenario: Edicao de empresa inexistente
- **GIVEN** um id de empresa que nao existe
- **WHEN** o cliente pede o formulario de edicao
- **THEN** a resposta e 404

### Requirement: BE-054 — Criacao de empresa
O sistema DEVE (SHALL) criar uma empresa no projeto corrente a partir do titulo informado, devolvendo os erros de validacao ja traduzidos quando houver. Fonte legada: `app/controllers/pub/companies_controller.rb:47-56`, `:125-131`.

#### Scenario: Projeto vem do servidor, nao do formulario
- **GIVEN** um usuario cujo projeto corrente e o projeto A
- **WHEN** ele envia a criacao com um `project_id` do projeto B no corpo
- **THEN** a empresa e criada no projeto A e o `project_id` enviado pelo cliente e ignorado

> Nota: corrige D-23/D-29 (legado: `project_id` vinha de campo escondido do formulario, permitindo criar empresa em projeto alheio; alem disso `id` era parametro permitido, permitindo tentativa de forcar a PK).

#### Scenario: Erro de validacao com mensagem em pt-BR
- **GIVEN** um usuario no projeto corrente
- **WHEN** ele envia a criacao sem titulo
- **THEN** a resposta e 422 e a mensagem de erro identifica o campo em pt-BR ("Nome"), nao a chave crua `Title`

> Nota: corrige D-21 na mesma familia de sintomas (legado: `translate_every_key` existia em `companies_controller.rb:109-114` mas nunca era chamado, entao as mensagens saiam com as chaves cruas).

### Requirement: BE-055 — Atualizacao de empresa
O sistema DEVE (SHALL) atualizar o titulo de uma empresa do projeto corrente. Fonte legada: `app/controllers/pub/companies_controller.rb:58-68`.

#### Scenario: Atualizacao dentro do escopo
- **GIVEN** uma empresa do projeto corrente
- **WHEN** o usuario altera o titulo para um valor ainda nao usado no projeto
- **THEN** a empresa e salva e a resposta e 200

#### Scenario: Troca de projeto de empresa com dados dependentes
- **GIVEN** uma empresa ligada a controles de risco e recebiveis
- **WHEN** o usuario envia um `project_id` diferente
- **THEN** o campo e ignorado e a empresa permanece no projeto atual

> AMBIGUIDADE: no legado a troca de projeto era permitida sem revalidar consistencia, e o `before_validation` recopiava `has_safegold_management` do novo projeto (`app/models/company.rb:12-14`). Falta confirmar se mover empresa entre projetos e um caso de uso real (se for, precisa de fluxo proprio com revalidacao dos dependentes).

### Requirement: BE-056 — Exclusao de empresa
O sistema DEVE (SHALL) excluir uma empresa do projeto corrente e DEVE (SHALL) bloquear a exclusao, com erro visivel, quando existirem controles de risco ou recebiveis vinculados. Fonte legada: `app/controllers/pub/companies_controller.rb:86-95`; `app/models/company.rb:4,9`.

#### Scenario: Exclusao bloqueada por dependentes responde erro
- **GIVEN** uma empresa com pelo menos um controle de risco vinculado
- **WHEN** o usuario solicita a exclusao
- **THEN** a resposta e 422 com a mensagem informando o vinculo que bloqueia, e a empresa continua existindo

> Nota: corrige D-24 (legado: o status era literalmente `@company.errors.any? ? :ok : :ok`, sempre 200, e o template `companies/destroy/handle.js.erb` tinha 0 bytes — a exclusao falhava em silencio e o usuario via a lista recarregar como se tivesse dado certo).

#### Scenario: Exclusao permitida
- **GIVEN** uma empresa sem controles de risco e sem recebiveis
- **WHEN** o usuario solicita a exclusao
- **THEN** a empresa e removida e a resposta e 200

### Requirement: BE-057 — Rotas de listagem e detalhe de empresa
O sistema DEVE (SHALL) expor listagem e detalhe de empresa por endpoints que respondem de fato, servindo os dados que a tela de detalhe consome. Fonte legada: `config/routes.rb:132`; `app/controllers/pub/companies_controller.rb:6-12`; `app/controllers/pub/console_controller.rb:155-160`.

#### Scenario: Detalhe de empresa
- **GIVEN** uma empresa do projeto corrente
- **WHEN** o cliente pede o detalhe dessa empresa
- **THEN** a resposta traz nome, contagem de portadores, contagem de controles de risco e a data de criacao

> Nota: corrige a rota morta do legado (`index` e `show` apontavam para templates inexistentes, resultando em `ActionView::MissingTemplate`; a tela real era servida por `Pub::ConsoleController`).

### Requirement: BE-058 — Regras de dominio de `Company`
O sistema DEVE (SHALL) exigir titulo unico dentro do projeto e projeto obrigatorio, e DEVE (SHALL) calcular os agregados de limite da empresa sem N+1 e sem formatacao de moeda no dominio. Fonte legada: `app/models/company.rb:1-18`; `app/models/project.rb:81,298-303,698-699,710,737`.

#### Scenario: Titulo unico por projeto
- **GIVEN** um projeto que ja tem a empresa "Empresa Padrao"
- **WHEN** o usuario cria outra empresa com o mesmo titulo no mesmo projeto
- **THEN** a criacao e rejeitada com 422, e o mesmo titulo continua permitido em outro projeto

#### Scenario: Projeto inexistente
- **GIVEN** um payload que referencia um projeto que nao existe
- **WHEN** a empresa e validada
- **THEN** a resposta e um erro de validacao de `project`, nao um erro interno

> Nota: corrige o `NoMethodError` do legado (o `before_validation` copiava `has_safegold_management` de `self.project` sem checar `nil`).

#### Scenario: Agregados de limite retornam numeros
- **GIVEN** uma empresa com controles de risco em varias datas
- **WHEN** os agregados de limite (total, utilizado, disponivel, percentual) sao calculados para uma data
- **THEN** os valores sao devolvidos como numeros, deixando a formatacao de moeda para a camada de apresentacao

> Nota: corrige a mistura de apresentacao no dominio (legado: `risk_controls_info_on` formatava com `to_currency.gsub("R$","")`) e o N+1 explicito dos agregados.

### Requirement: BE-059 — Busca de fornecedores
O sistema DEVE (SHALL) listar fornecedores escopados ao projeto corrente, com busca textual, ordenacao multi-coluna e paginacao efetivas, e DEVE (SHALL) informar o total. Fonte legada: `config/routes.rb:140`; `app/controllers/pub/providers_controller.rb:9-37`.

#### Scenario: Escopo obrigatorio de projeto
- **GIVEN** um usuario autenticado sem projeto corrente resolvido
- **WHEN** ele busca fornecedores
- **THEN** a resposta e um erro de pre-condicao e nenhum fornecedor de outro projeto e devolvido

> Nota: corrige D-23/D-29 (legado: o escopo por `default_project_id` so era aplicado se o usuario tivesse projeto padrao — sem ele, `providers_controller.rb:20` devolvia fornecedores de **todos** os projetos).

#### Scenario: Ordenacao e paginacao aplicadas juntas
- **GIVEN** 30 fornecedores no projeto corrente
- **WHEN** o cliente pede ordenacao por titulo descendente com `l=10`, `o=10`
- **THEN** sao devolvidos 10 fornecedores, os de posicao 11 a 20 na ordem pedida, e o total informado e 30

> Nota: corrige D-20 (legado: o ramo com ordenacao aplicava `order!` mas perdia `limit`/`offset`, e o ramo sem ordenacao perdia tudo; nao havia `@total_count`).

### Requirement: BE-060 — Formulario de novo fornecedor / edicao
O sistema DEVE (SHALL) fornecer os dados para abrir o formulario de criacao e de edicao de fornecedor. Fonte legada: `app/controllers/pub/providers_controller.rb:47-64`, `:137-139`.

#### Scenario: Edicao de fornecedor inexistente
- **GIVEN** um id de fornecedor que nao existe
- **WHEN** o cliente pede o formulario de edicao
- **THEN** a resposta e 404

### Requirement: BE-061 — Criacao de fornecedor
O sistema DEVE (SHALL) criar um fornecedor no projeto corrente com os dados cadastrais informados (documento, endereco, contato, resumo, logo, chave de integracao, situacao). Fonte legada: `app/controllers/pub/providers_controller.rb:66-90`, `:168-196`.

#### Scenario: Projeto definido pelo servidor
- **GIVEN** um usuario cujo projeto corrente e o projeto A
- **WHEN** ele cria um fornecedor enviando `project_id` do projeto B
- **THEN** o fornecedor e criado no projeto A

#### Scenario: Falha de validacao nao deixa residuo
- **GIVEN** um payload de fornecedor com CNPJ invalido
- **WHEN** a criacao e submetida
- **THEN** a resposta e 422 com as mensagens em pt-BR e nenhum registro parcial permanece gravado

> Nota: corrige o tratamento de erro do legado (chamava `@provider.destroy` sobre registro nao persistido — no-op que destruiria de verdade caso o save tivesse ocorrido parcialmente).

### Requirement: BE-062 — Atualizacao de fornecedor
O sistema DEVE (SHALL) atualizar um fornecedor do projeto corrente mantendo obrigatorios `title` e `integration_key` tambem na atualizacao. Fonte legada: `app/controllers/pub/providers_controller.rb:92-105`; `app/models/provider.rb:7-10`.

#### Scenario: Projeto nao pode ser trocado pelo cliente
- **GIVEN** um fornecedor do projeto A
- **WHEN** o usuario envia a atualizacao com `project_id` do projeto B
- **THEN** o campo e ignorado e o fornecedor permanece no projeto A

> Nota: corrige D-23 (legado: o `project_id` era forcado no create mas **nao** no update, entao era possivel mover fornecedor para outro projeto por campo escondido).

#### Scenario: Titulo nao pode ficar em branco na atualizacao
- **GIVEN** um fornecedor existente
- **WHEN** o usuario salva com titulo vazio
- **THEN** a resposta e 422 e o titulo anterior e preservado

> Nota: corrige o fallback `on: [:create]` do legado, que deixava `title`/`integration_key` ficarem em branco no update.

### Requirement: BE-063 — Exclusao de fornecedor
O sistema DEVE (SHALL) excluir um fornecedor do projeto corrente e DEVE (SHALL) bloquear a exclusao, com erro visivel, quando houver renegociacoes vinculadas. Fonte legada: `app/controllers/pub/providers_controller.rb:108-118`; `app/models/provider.rb:5`.

#### Scenario: Exclusao bloqueada por renegociacoes
- **GIVEN** um fornecedor com pelo menos uma renegociacao vinculada
- **WHEN** o usuario solicita a exclusao
- **THEN** a resposta e 422 informando o vinculo, e o fornecedor continua existindo

> Nota: corrige D-24 (legado: a exclusao era bloqueada por `restrict_with_error` mas a resposta era sempre 200 e a UI ja havia disparado o toast de sucesso — sucesso falso).

### Requirement: BE-064 — Consulta de CNPJ na ReceitaWS
O sistema DEVE (SHALL) oferecer a consulta de dados cadastrais por CNPJ para preencher o formulario de fornecedor, validando o CNPJ no servidor antes de chamar o provedor externo. Fonte legada: `config/routes.rb:141`; `app/controllers/pub/providers_controller.rb:121-133`; `app/helpers/cnpj_api.rb:1-5`.

#### Scenario: Consulta de CNPJ valido
- **GIVEN** um usuario autenticado no projeto corrente
- **WHEN** ele consulta um CNPJ valido
- **THEN** a resposta traz os campos cadastrais (abertura, bairro, cep, complemento, data de situacao, email, fantasia, logradouro, municipio, nome, numero, situacao, telefone, uf, cnaes, atividades)

#### Scenario: CNPJ nao encontrado
- **GIVEN** um CNPJ valido que o provedor nao conhece
- **WHEN** a consulta e feita
- **THEN** a resposta e 404 sem dados

> AMBIGUIDADE: D-27 — o endpoint esta vivo no backend mas **morto na UI** (o botao que o chama esta comentado no HTML e o JS tem ERB escapado, ver FE-073). O legado tambem nao validava o CNPJ no servidor, nao tinha rate-limit e repassava a resposta crua. Decidir se o autopreenchimento por CNPJ volta a ser ligado no ai9 ou se a integracao inteira e descartada.

### Requirement: BE-065 — Listagem e detalhe de fornecedor
O sistema DEVE (SHALL) expor listagem e detalhe de fornecedor por endpoints que respondem de fato. Fonte legada: `config/routes.rb:142`; `app/controllers/pub/providers_controller.rb:5-7`, `:39-45`.

#### Scenario: Detalhe de fornecedor
- **GIVEN** um fornecedor do projeto corrente
- **WHEN** o cliente pede o detalhe
- **THEN** a resposta traz os dados cadastrais do fornecedor e a contagem de renegociacoes

> AMBIGUIDADE: D-22 — no legado nenhum dos dois templates existia (`MissingTemplate`) e nao havia tela de detalhe de fornecedor acessivel no console, apesar do HTML e do SCSS completos no repositorio. Confirmar se a tela entra no escopo (recomendacao do inventario: portar, e barato).

### Requirement: BE-066 — Regras de dominio de `Provider`
O sistema DEVE (SHALL) validar fornecedor com titulo e projeto obrigatorios, documento (CPF ou CNPJ) validado quando informado e unico dentro do projeto, chave de integracao unica, e DEVE (SHALL) guardar `cnaes` e `atividades` em um unico formato estruturado. Fonte legada: `app/models/provider.rb:2,7-10,12-29,30-43,45-67,69-110`.

#### Scenario: Documento invalido e rejeitado
- **GIVEN** um fornecedor sendo salvo com CNPJ de digitos verificadores errados
- **WHEN** a validacao roda
- **THEN** a resposta e 422 indicando o documento invalido

#### Scenario: Documento duplicado no mesmo projeto
- **GIVEN** um fornecedor com CNPJ X ja cadastrado no projeto corrente
- **WHEN** outro fornecedor e criado com o mesmo CNPJ X no mesmo projeto
- **THEN** a criacao e rejeitada, e o mesmo CNPJ continua aceito em outro projeto

#### Scenario: Chave de integracao unica
- **GIVEN** dois fornecedores com titulos que transliteram para a mesma chave (`Acme S.A.` e `Acme SA`)
- **WHEN** o segundo e criado
- **THEN** a chave de integracao gerada nao colide com a existente

> Nota: corrige D-25 na parte de serializacao (legado: `cnaes` usava `serialize` YAML e `atividades` usava JSON manual na **mesma tabela**); no ai9 ambos sao JSON estruturado. Corrige tambem a chave de integracao gerada `on: :create` sem garantia de unicidade.

#### Scenario: Fornecedor sem documento
- **GIVEN** um payload de fornecedor sem CPF e sem CNPJ
- **WHEN** a criacao e submetida
- **THEN** o fornecedor e criado (documento e opcional)

> AMBIGUIDADE: no legado a regra "ao menos um documento" existe mas esta **comentada** (`app/models/provider.rb:34-36`). Confirmar se o negocio quer exigir ao menos um documento no ai9 — a base legada provavelmente tem fornecedores sem documento nenhum.

### Requirement: BE-067 — Busca de portadores
O sistema DEVE (SHALL) listar portadores (catalogo global, sem escopo de projeto) com busca textual consistente, ordenacao multi-coluna e paginacao efetivas. Fonte legada: `config/routes.rb:144`; `app/controllers/pub/carriers_controller.rb:9-40`.

#### Scenario: Busca insensivel a caixa e a acento nos dois ramos
- **GIVEN** um portador de titulo `Fomento Sao Paulo`
- **WHEN** o usuario busca por `SAO` com ordenacao ativa e, em seguida, sem ordenacao
- **THEN** o portador aparece nos dois casos, com o mesmo conjunto de resultados

> Nota: corrige o comportamento assimetrico do legado (o ramo sem ordenacao usava `"%#{@query.upcase}%"` contra `LOWER(?)`, o ramo ordenado usava o termo cru — buscas com maiuscula/acento davam resultados diferentes).

#### Scenario: Paginacao de portadores
- **GIVEN** 120 portadores cadastrados
- **WHEN** o cliente pede `l=50`, `o=50`
- **THEN** sao devolvidos 50 portadores a partir do 51o, e o total informado e 120

> Nota: corrige D-20 (legado: `where!` + `.limit.offset` descartados — a tela trazia todos os portadores). Muda o que a tela faz.

#### Scenario: Portadores sao globais
- **GIVEN** dois usuarios em projetos diferentes
- **WHEN** ambos listam portadores
- **THEN** ambos veem o mesmo catalogo completo de portadores (DEC-07: portadores sao globais)

### Requirement: BE-068 — Formulario e detalhe de portador
O sistema DEVE (SHALL) fornecer os dados para criar/editar um portador e DEVE (SHALL) expor a listagem e o detalhe de portador por endpoints que respondem de fato. Fonte legada: `app/controllers/pub/carriers_controller.rb:5-7,42-48,50-66,112-114`; `config/routes.rb:145`.

#### Scenario: Detalhe de portador
- **GIVEN** um portador cadastrado
- **WHEN** o cliente pede o detalhe
- **THEN** a resposta traz titulo, resumo, grupo, agente financeiro, cidade/UF e a contagem de projetos ligados

> AMBIGUIDADE: D-22 — no legado `index` e `show` apontavam para templates inexistentes (`MissingTemplate`) e o parcial `carriers/detail/_body.html.erb` existia mas nada o renderizava. Confirmar se a tela de detalhe de portador entra no escopo.

### Requirement: BE-069 — Criacao e atualizacao de portador
O sistema DEVE (SHALL) criar e atualizar portadores com titulo, chave de integracao, patrimonio liquido, codigo do banco, contas senior/subordinadas e percentual, agente financeiro, cidade/UF, situacao, grupo e resumo, validando os campos no servidor. Fonte legada: `app/controllers/pub/carriers_controller.rb:68-96`, `:134-152`.

#### Scenario: Valores monetarios rejeitam formato invalido
- **GIVEN** um formulario de portador
- **WHEN** o patrimonio liquido chega como `"R$ 1.234,56"` sem conversao previa
- **THEN** o servidor interpreta o valor corretamente ou responde 422, mas nunca grava `1` silenciosamente

> Nota: corrige o cast silencioso do legado (o ActiveRecord convertia `"R$ 1.234,56"` para `1` quando o JS de desformatacao falhava — ver FE-066).

#### Scenario: Agente financeiro fora da lista
- **GIVEN** um payload com `financial_agent = "Banco"` (fora de FIDC / Securitizadora / Factoring / Cliente)
- **WHEN** a criacao e submetida
- **THEN** a resposta e 422

> Nota: corrige a ausencia de validacao de inclusao no servidor (legado: a lista existia so no `<select>` do front; `city`/`uf` eram texto livre).

#### Scenario: Codigo de banco preserva zeros a esquerda
- **GIVEN** um portador sendo criado com codigo de banco `001`
- **WHEN** o registro e salvo e lido de volta
- **THEN** o codigo devolvido e `001`

> Nota: corrige D-25 (legado: `carriers.bank_code` era `integer` e `001` virava `1`).

### Requirement: BE-070 — Exclusao de portador
O sistema DEVE (SHALL) bloquear a exclusao de portador que tenha controles de risco, conexoes com projeto ou recebiveis vinculados, respondendo com erro visivel; a exclusao NAO DEVE (SHALL NOT) destruir controles de risco em cascata. Fonte legada: `app/controllers/pub/carriers_controller.rb:99-109`; `app/models/carrier.rb:2-7`.

#### Scenario: Portador com controles de risco nao pode ser excluido
- **GIVEN** um portador com controles de risco vinculados
- **WHEN** o usuario solicita a exclusao
- **THEN** a resposta e 422 informando os controles de risco que bloqueiam, e nenhum controle de risco e removido

> Nota: corrige D-24 (legado: `risk_controls` era `dependent: :destroy` — excluir um portador destruia em cascata todos os controles de risco/limites ligados a ele, sem confirmacao especifica; e as exclusoes bloqueadas respondiam 200).

#### Scenario: Exclusao permitida
- **GIVEN** um portador sem controles de risco, sem conexoes com projeto e sem recebiveis
- **WHEN** o usuario solicita a exclusao
- **THEN** o portador e removido e a resposta e 200

### Requirement: BE-071 — Regras de dominio de `Carrier`
O sistema DEVE (SHALL) exigir apenas titulo como obrigatorio, permitir titulos duplicados, gerar chave de integracao na criacao, tratar o grupo como opcional e expor a cidade formatada com fallbacks. Fonte legada: `app/models/carrier.rb:8,11-14,16-33,35-49,51-85`.

#### Scenario: Titulos duplicados sao aceitos
- **GIVEN** um portador de titulo `Factoring S.A` ja cadastrado
- **WHEN** outro portador com o mesmo titulo e criado
- **THEN** a criacao e aceita

> Nota: a unicidade de titulo foi desativada de proposito no legado (comentario "Cloud #7036": a importacao do dump do cliente trouxe portadores duplicados com usos distintos). Comportamento **preservado**.

#### Scenario: Cidade formatada com dados parciais
- **GIVEN** um portador com cidade preenchida e UF vazia
- **WHEN** a cidade formatada e lida
- **THEN** o resultado traz apenas a cidade, sem virgula pendurada; e com os dois campos vazios o resultado e `-`

### Requirement: BE-072 — Busca de grupos de portadores
O sistema DEVE (SHALL) listar grupos de portadores (catalogo global) com busca textual, ordenacao por titulo e paginacao efetivas. Fonte legada: `config/routes.rb:147`; `app/controllers/pub/carrier_groups_controller.rb:9-40`.

#### Scenario: Ordenacao por titulo funciona
- **GIVEN** grupos de portadores cadastrados
- **WHEN** o usuario clica no cabecalho "Titulo" para ordenar ascendente
- **THEN** a lista volta ordenada por titulo, com status 200

> Nota: corrige D-21 (legado: com `ordering_keys` presente o controller chamava `CarrierGroup.prepare_ordering` — metodo **inexistente** em `app/models/carrier_group.rb` — e a tela dava 500 ao clicar no cabecalho).

#### Scenario: Paginacao de grupos
- **GIVEN** 60 grupos cadastrados
- **WHEN** o cliente pede `l=20`, `o=40`
- **THEN** sao devolvidos os 20 ultimos grupos da ordem pedida e o total informado e 60

> Nota: corrige D-20 (legado: `where!` + `.limit.offset` descartados).

### Requirement: BE-073 — CRUD de grupo de portadores
O sistema DEVE (SHALL) criar, editar, listar, detalhar e excluir grupos de portadores, e DEVE (SHALL) impedir que a exclusao deixe portadores apontando para um grupo inexistente. Fonte legada: `app/controllers/pub/carrier_groups_controller.rb:5-7,42-66,68-109,112-114,121-126`; `config/routes.rb:148`.

#### Scenario: Exclusao de grupo com portadores
- **GIVEN** um grupo com pelo menos um portador vinculado
- **WHEN** o usuario chama a exclusao diretamente pela API (sem passar pela UI)
- **THEN** a resposta e 422 e o grupo continua existindo

> Nota: corrige D-24 na mesma familia (legado: `has_many :carriers` **sem `dependent:`** — excluir o grupo deixava `carriers.group_id` orfao apontando para id inexistente; a UI escondia o botao, mas o endpoint nao validava).

#### Scenario: Detalhe de grupo
- **GIVEN** um grupo cadastrado
- **WHEN** o cliente pede o detalhe
- **THEN** a resposta traz o titulo e a contagem de portadores

> Nota: corrige as rotas mortas do legado (`index` e `show` apontavam para templates inexistentes).

### Requirement: BE-074 — Regras de dominio de `CarrierGroup`
O sistema DEVE (SHALL) exigir titulo e usuario responsavel, permitir titulos repetidos e manter a contagem de portadores do grupo consistente. Fonte legada: `app/models/carrier_group.rb:1-7`; `db/migrate/20210819193736_create_carrier_groups.rb:7`.

#### Scenario: Contagem de portadores acompanha as movimentacoes
- **GIVEN** um grupo com 3 portadores
- **WHEN** um portador e movido para outro grupo
- **THEN** a contagem do grupo de origem passa a 2 e a do grupo de destino aumenta em 1, sem valor nulo

> Nota: corrige a coluna `carriers_count` criada sem default no legado (registros antigos podiam ficar `NULL` e o contador divergir da contagem real usada pela UI).

### Requirement: BE-075 — Busca de segmentos
O sistema DEVE (SHALL) listar segmentos (catalogo global) com busca textual, ordenacao por titulo e por chave de integracao, e paginacao efetiva. Fonte legada: `config/routes.rb:174`; `app/controllers/pub/segments_controller.rb:9-39`; `app/models/segment.rb:44-51`.

#### Scenario: Ordenacao por chave de integracao
- **GIVEN** segmentos cadastrados
- **WHEN** o usuario ordena pela coluna "Chave"
- **THEN** a lista volta ordenada por chave de integracao

#### Scenario: Paginacao de segmentos
- **GIVEN** 25 segmentos cadastrados
- **WHEN** o cliente pede `l=10`, `o=20`
- **THEN** sao devolvidos os 5 segmentos restantes e o total informado e 25

> Nota: corrige D-20 (legado: `where!` + `.limit.offset` descartados).

### Requirement: BE-076 — CRUD de segmento
O sistema DEVE (SHALL) criar, editar, listar, detalhar e excluir segmentos, com titulo unico global e chave de integracao. Fonte legada: `app/controllers/pub/segments_controller.rb:5-7,41-65,67-108,111-113,121-127`; `config/routes.rb:175`; `app/models/segment.rb:13-14`.

#### Scenario: Criacao de segmento funciona
- **GIVEN** um usuario com permissao de cadastro
- **WHEN** ele cria um segmento com titulo "Agronegocio" e chave "agronegocio"
- **THEN** o segmento e criado com sucesso e passa a aparecer na listagem

> Nota: corrige D-21 (legado: o model exigia `user_id` (`app/models/segment.rb:14`) e o formulario o enviava, mas `segment_params` **nao o permitia** (`:121-127`) — **toda** criacao de segmento falhava com "user can't be blank" e 422).

#### Scenario: Exclusao de segmento em uso
- **GIVEN** um segmento associado a pelo menos um projeto
- **WHEN** o usuario solicita a exclusao
- **THEN** a resposta e 422 informando o vinculo, e o segmento continua existindo

> Nota: corrige D-24 (legado: a exclusao era bloqueada por `restrict_with_error` mas a resposta continuava 200).

#### Scenario: Titulo unico global
- **GIVEN** um segmento "Comercio" ja existente
- **WHEN** outro segmento "Comercio" e criado
- **THEN** a criacao e rejeitada com 422

### Requirement: BE-077 — Busca de subsegmentos
O sistema DEVE (SHALL) listar subsegmentos (catalogo global) com busca textual, ordenacao por titulo e por chave de integracao, e paginacao efetiva. Fonte legada: `config/routes.rb:177`; `app/controllers/pub/sub_segments_controller.rb:9-39`; `app/models/sub_segment.rb:37`.

#### Scenario: Ordenacao propria de subsegmentos
- **GIVEN** subsegmentos cadastrados
- **WHEN** o usuario ordena pela coluna "Chave"
- **THEN** a lista volta ordenada por chave de integracao, resolvida pelas regras do proprio subsegmento

> Nota: corrige o acoplamento acidental do legado (`SubSegment.prepare_ordering` delegava a `Segment.get_ordering_key`/`get_ordering_style` e funcionava por coincidencia de nomes de chave).

#### Scenario: Paginacao de subsegmentos
- **GIVEN** 40 subsegmentos cadastrados
- **WHEN** o cliente pede `l=15`, `o=30`
- **THEN** sao devolvidos os 10 restantes e o total informado e 40

> Nota: corrige D-20.

### Requirement: BE-078 — CRUD de subsegmento
O sistema DEVE (SHALL) criar, editar, listar, detalhar e excluir subsegmentos, com titulo unico global, chave de integracao gerada na criacao e bloqueio de exclusao quando houver projetos vinculados. Fonte legada: `app/controllers/pub/sub_segments_controller.rb:5-7,41-65,67-108,111-113,121-128`; `config/routes.rb:178`; `app/models/sub_segment.rb:13-20`.

#### Scenario: Exclusao de subsegmento em uso
- **GIVEN** um subsegmento associado a pelo menos um projeto
- **WHEN** o usuario solicita a exclusao
- **THEN** a resposta e 422 e o subsegmento continua existindo

> Nota: corrige D-24 (legado: resposta 200 mesmo com a exclusao bloqueada).

#### Scenario: Detalhe de subsegmento
- **GIVEN** um subsegmento cadastrado
- **WHEN** o cliente pede o detalhe
- **THEN** a resposta traz titulo, chave de integracao e situacao

> Nota: corrige as rotas mortas do legado (`index`/`show` apontavam para templates inexistentes).

### Requirement: BE-079 — Comportamentos transversais dos seis cadastros
Todos os endpoints de busca e CRUD de empresas, fornecedores, portadores, grupos, segmentos e subsegmentos DEVEM (SHALL) exigir autenticacao, autorizar por papel no servidor e resolver o tenant a partir do JWT validado contra membership. Fonte legada: `app/controllers/pub_application_controller.rb:12,38-83`; `app/controllers/pub/console_controller.rb:5-7,340-355`; `config/initializers/dev.rb:3-5`.

#### Scenario: Requisicao sem autenticacao
- **GIVEN** um cliente sem token valido
- **WHEN** ele chama qualquer endpoint de busca ou CRUD destes seis cadastros
- **THEN** a resposta e 401, sem tocar em dados

> Nota: corrige D-23 (legado: `requires_current_user?` retornava `false` em `PubApplicationController` — os endpoints nao exigiam usuario logado; companies/providers quebravam com `NoMethodError` em `current_user.default_project_id` e carriers/segments/sub_segments/carrier_groups respondiam normalmente para anonimo).

#### Scenario: Usuario somente-leitura tenta escrever
- **GIVEN** um usuario marcado como somente-leitura
- **WHEN** ele chama criacao, atualizacao ou exclusao em qualquer um dos seis cadastros
- **THEN** a resposta e 403 e nada e alterado

> Nota: corrige D-17/D-23 (legado: `user_is_readonly` e os papeis `og?`/`admin?`/`manager?` eram checados **apenas nas views ERB**; nenhum endpoint validava papel).

#### Scenario: Usuario desativado
- **GIVEN** um usuario cuja conta foi desativada apos o login
- **WHEN** ele faz a proxima requisicao
- **THEN** a sessao e encerrada e a resposta e 401

#### Scenario: Parametro de apresentacao nao escolhe caminho de arquivo
- **GIVEN** um cliente que envia `target_mode` com um valor arbitrario contendo `../`
- **WHEN** a requisicao e processada
- **THEN** o valor e rejeitado ou ignorado e nenhum recurso fora do conjunto previsto e alcancado

> Nota: corrige o potencial path traversal de template do legado (`target_mode` era interpolado direto no caminho do parcial em `carriers/list/body.js.erb:5`).

### Requirement: FE-050 — Navegacao do console para os seis cadastros
A interface DEVE (SHALL) expor os seis cadastros no menu do console, respeitando visibilidade por papel e por existencia de projeto, e definir o titulo da aba do navegador. Fonte legada: `app/helpers/application_helper.rb:128,129,141,148,149,150`; `config/routes.rb:45`.

#### Scenario: Grupo "Cadastro" restrito por papel
- **GIVEN** um usuario que nao e `og`, `admin` nem `manager`
- **WHEN** ele abre o console
- **THEN** os itens "Grupos de Portadores", "Portadores", "Segmentos" e "Subsegmentos" nao aparecem no menu

#### Scenario: Grupo "Projeto" depende de ter projeto
- **GIVEN** um usuario sem nenhum projeto
- **WHEN** ele abre o console
- **THEN** os itens "Empresas" e "Fornecedores" nao aparecem no menu

### Requirement: FE-051 — Lista de Empresas (layout)
A tela de empresas DEVE (SHALL) mostrar as colunas Empresa, Portadores e Controles de risco, com estados de carregamento, vazio e falha, e o botao "Cadastrar" oculto para usuario somente-leitura. Fonte legada: `app/views/pub/console/parts/companies/_body.html.erb:1-55`.

#### Scenario: Busca sem resultados
- **GIVEN** um termo de busca que nao casa com nenhuma empresa
- **WHEN** a busca retorna vazia
- **THEN** a tela mostra a mensagem de vazio citando o termo buscado

### Requirement: FE-052 — Busca de Empresas com debounce
O campo de busca de empresas DEVE (SHALL) aguardar a pausa de digitacao antes de consultar o servidor e DEVE (SHALL) ignorar entradas compostas apenas por espacos. Fonte legada: `app/views/pub/console/parts/companies/_body.js.erb:21-34`.

#### Scenario: Digitacao rapida gera uma unica consulta
- **GIVEN** a lista de empresas aberta
- **WHEN** o usuario digita cinco caracteres em menos de 300 ms
- **THEN** apenas uma consulta e enviada ao servidor, com o termo completo

### Requirement: FE-053 — Paginacao de Empresas
Os controles de paginacao (primeiro, anterior, proximo, ultimo e limite por pagina) DEVEM (SHALL) alterar de fato a consulta enviada ao servidor e refletir o total real de registros. Fonte legada: `app/views/pub/console/parts/companies/_body.js.erb:105-119,121-243,296-344`.

#### Scenario: Navegar para a proxima pagina
- **GIVEN** uma lista com 45 empresas e limite 20 por pagina
- **WHEN** o usuario clica em "proximo"
- **THEN** a tela mostra as empresas 21 a 40, o indicador de pagina avanca e o botao "anterior" fica habilitado

> Nota: corrige D-20/D-53 (legado: o `navigationHandler` alterava `container.getData().limit/offset` mas o proxy enviava `holder.getData()`, fixo em `l=50`/`o=0`; o input exibia 20 enquanto o servidor recebia 50; e o backend descartava limite/offset de qualquer forma).

#### Scenario: Limpar o campo de limite
- **GIVEN** o campo de limite por pagina preenchido com 10
- **WHEN** o usuario limpa o campo
- **THEN** a lista volta ao limite padrao e a consulta enviada usa esse mesmo limite

### Requirement: FE-054 — Filtros de Empresas
A barra de filtros de empresas DEVE (SHALL) expor apenas filtros que existem e funcionam de ponta a ponta. Fonte legada: `app/views/pub/console/parts/companies/_body.html.erb:19-35`; `_body.js.erb:17-19,36-46,93-94`.

#### Scenario: Alternar a barra de filtros
- **GIVEN** a lista de empresas
- **WHEN** o usuario clica em "Filtros"
- **THEN** a barra de busca aparece e nenhum controle sem efeito e apresentado

> AMBIGUIDADE: no legado o JS ligava `change` em `#kind` e `#state` e enviava `kind`/`state` na busca, mas **esses selects nao existem no HTML** e o backend tambem os ignora. Confirmar se os filtros de tipo/estado eram uma feature planejada (implementar) ou removida (descartar).

### Requirement: FE-055 — Linha de Empresa e menu de contexto
Cada linha da lista DEVE (SHALL) mostrar nome, contagem de portadores e contagem de controles de risco ativos, e oferecer as acoes Ver mais, Editar e Remover conforme a permissao do usuario. Fonte legada: `app/views/pub/console/parts/companies/list/_widget.html.erb:1-31`; `list/_widget.js.erb:1-109`.

#### Scenario: Usuario somente-leitura
- **GIVEN** um usuario somente-leitura
- **WHEN** ele abre o menu de contexto de uma empresa
- **THEN** as acoes "Editar" e "Remover" nao sao oferecidas

#### Scenario: Remover so aparece quando a empresa pode ser removida
- **GIVEN** uma empresa que possui recebiveis mas nenhum controle de risco
- **WHEN** o usuario abre o menu de contexto
- **THEN** ou a acao "Remover" nao e oferecida, ou, se oferecida, a tentativa apresenta o erro do servidor

> Nota: corrige o criterio incompleto do legado (a acao "Remover" so era escondida quando `risk_controls` estava vazio — **nao** considerava recebiveis, que tambem bloqueiam a exclusao).

#### Scenario: Cadastrar sem projeto padrao
- **GIVEN** um usuario sem projeto padrao
- **WHEN** ele tenta cadastrar uma empresa
- **THEN** a tela informa que e necessario ter um projeto padrao antes de criar uma empresa

### Requirement: FE-056 — Painel de criar/editar Empresa
O painel lateral DEVE (SHALL) permitir informar o nome da empresa, salvar e recarregar a lista, exibindo mensagens de sucesso e de erro compreensiveis. Fonte legada: `app/views/pub/console/parts/companies/helper/_body.html.erb:1-16`; `helper/_mount.js.erb`; `helper/handle.js.erb:1-9`.

#### Scenario: Erro de validacao exibido em pt-BR
- **GIVEN** o painel de nova empresa aberto
- **WHEN** o usuario salva sem preencher o nome
- **THEN** a mensagem de erro nomeia o campo em pt-BR

> Nota: corrige o texto errado do legado — os erros usavam a chave crua como cabecalho, e a mensagem de estado vazio do painel dizia "Essa construtora nao pode ser alterada" (texto herdado de outro produto, repetido nas seis entidades).

#### Scenario: Salvar recarrega a lista
- **GIVEN** o painel de edicao aberto para uma empresa
- **WHEN** o usuario salva um novo nome
- **THEN** o painel fecha, a lista mostra o nome atualizado e uma confirmacao de sucesso e exibida

### Requirement: FE-057 — Exclusao de Empresa a partir da lista
A exclusao a partir da lista DEVE (SHALL) pedir confirmacao e DEVE (SHALL) refletir o resultado real da operacao. Fonte legada: `app/views/pub/console/parts/companies/list/_widget.js.erb:80-106`.

#### Scenario: Exclusao bloqueada e comunicada
- **GIVEN** uma empresa com controles de risco vinculados
- **WHEN** o usuario confirma a exclusao
- **THEN** a tela mostra a mensagem de erro devolvida pelo servidor e a empresa permanece na lista

> Nota: corrige D-24 (legado: o backend respondia sempre 200 e a exclusao bloqueada parecia bem-sucedida ate o item reaparecer na lista).

### Requirement: FE-058 — Detalhe de Empresa
A tela de detalhe DEVE (SHALL) apresentar o cartao-resumo (nome, numero de portadores, numero de controles de risco) e o bloco de dados da empresa, com a URL refletindo a empresa aberta. Fonte legada: `app/controllers/pub/console_controller.rb:155-160`; `app/views/pub/console/parts/companies/detail/_body.html.erb:1-22`; `detail/tabs/_tab_geral.html.erb:1-43`.

#### Scenario: Abrir o detalhe
- **GIVEN** uma empresa na lista
- **WHEN** o usuario clica em "Ver mais"
- **THEN** a tela de detalhe abre com a aba GERAL, a data de criacao formatada corretamente e um caminho de volta para a lista

> Nota: corrige a formatacao quebrada do legado (`%d/%m/%Y- %H:%M`, com o hifen colado a data e sem espaco).

### Requirement: FE-059 — Aba "Controles de Risco" da Empresa
O detalhe de empresa NAO DEVE (SHALL NOT) expor abas ou widgets sem funcao. Fonte legada: `app/views/pub/console/parts/companies/detail/tabs/_tab_company_risk_control.html.erb:1-3`; `detail/parts/company_risk_controls/list/_widget.html.erb:1-41`.

#### Scenario: Detalhe apresenta apenas abas funcionais
- **GIVEN** a tela de detalhe de empresa
- **WHEN** o usuario a abre
- **THEN** somente abas com conteudo real sao apresentadas

> AMBIGUIDADE: no legado a aba de controles de risco existia mas nao era listada em `detail/_body.html.erb:15` (so "GERAL"), o parcial estava vazio e os widgets de parcela/pagamento ("Gerar pagamento", "Remover") nao eram renderizados por nenhuma action. Confirmar se essa funcionalidade planejada e abandonada deve ser portada ou descartada.

### Requirement: FE-060 — Lista de Portadores (layout)
A tela de portadores DEVE (SHALL) mostrar as colunas Titulo, Grupo, Agente Financeiro, Cidade e numero de Projetos, com paginacao e com o botao "Cadastrar" restrito a papel e a usuario nao somente-leitura. Fonte legada: `app/views/pub/console/parts/carriers/_body.html.erb:1-49`; `_body.js.erb:122-150`.

#### Scenario: Controles de paginacao presentes
- **GIVEN** um catalogo com mais portadores do que cabe em uma pagina
- **WHEN** a tela e aberta
- **THEN** os controles de navegacao entre paginas sao apresentados e funcionam

> Nota: corrige D-20 (legado: limite fixo de 50 no holder e **sem** controles de paginacao na tela de portadores).

### Requirement: FE-061 — Ordenacao por cabecalho nas listas de cadastro
Nas listas de portadores, grupos, segmentos, subsegmentos e fornecedores, os cabecalhos apresentados como ordenaveis DEVEM (SHALL) ordenar de fato, com ciclo ascendente, descendente e sem ordenacao. Fonte legada: `app/views/pub/console/parts/carriers/_body.js.erb:10-53` e equivalentes.

#### Scenario: Ordenar por "Grupo" na lista de portadores
- **GIVEN** a lista de portadores
- **WHEN** o usuario clica no cabecalho "Grupo"
- **THEN** a lista e reordenada por grupo e nenhum erro ocorre

> Nota: corrige D-21 (legado: os cabecalhos "Grupo", "Agente Financeiro" e "# Projetos" tinham a classe `ordering_orderable_header` mas nenhum `data-key` — enviavam chave `undefined`, o servidor fazia `Carrier.get_ordering_key(nil)` e `nil + " "` levantava `NoMethodError` → **500** ao clicar).

#### Scenario: Cabecalho nao ordenavel nao parece ordenavel
- **GIVEN** uma coluna que o servidor nao sabe ordenar
- **WHEN** a lista e renderizada
- **THEN** essa coluna nao apresenta o indicador de ordenacao

### Requirement: FE-062 — Busca de Portadores
O campo de busca de portadores DEVE (SHALL) aguardar a pausa de digitacao e apresentar mensagem de vazio citando o termo buscado. Fonte legada: `app/views/pub/console/parts/carriers/_body.js.erb:57-70,92-120`.

#### Scenario: Busca sem resultado
- **GIVEN** um termo que nao casa com nenhum portador
- **WHEN** a busca retorna
- **THEN** a tela mostra a mensagem de vazio personalizada com o termo

### Requirement: FE-063 — Linha de Portador, menu e atalho para "Relacoes"
Cada linha DEVE (SHALL) mostrar titulo, grupo, agente financeiro, cidade formatada e contagem de projetos, com fallback `-` para vazios, e o clique na linha DEVE (SHALL) abrir a tela de relacoes projeto-portador. Fonte legada: `app/views/pub/console/parts/carriers/list/_widget.html.erb:1-59`; `list/_widget.js.erb:1-111`.

#### Scenario: Abrir as relacoes de um portador
- **GIVEN** a lista de portadores
- **WHEN** o usuario clica na linha de um portador
- **THEN** a tela de relacoes desse portador com projetos e aberta

#### Scenario: Menu oculto para somente-leitura
- **GIVEN** um usuario somente-leitura
- **WHEN** ele visualiza a lista de portadores
- **THEN** o menu de contexto da linha nao e oferecido

### Requirement: FE-064 — Formulario de Portador
O painel lateral de portador DEVE (SHALL) oferecer os campos titulo, chave de integracao, patrimonio liquido, codigo do banco, contas senior, contas subordinadas, percentual de contas subordinadas, agente financeiro, cidade, UF, situacao, grupo e resumo. Fonte legada: `app/views/pub/console/parts/carriers/helper/_body.html.erb:1-121`.

#### Scenario: Selecao de grupo
- **GIVEN** o formulario de portador aberto
- **WHEN** o usuario abre o select de grupo
- **THEN** os grupos existentes sao listados em ordem alfabetica, com a opcao de nenhum grupo

### Requirement: FE-065 — Calculo de "% contas subordinadas"
O percentual de contas subordinadas DEVE (SHALL) ser derivado das contas senior e subordinadas e apresentado ao usuario. Fonte legada: `app/views/pub/console/parts/carriers/helper/_body.js.erb:40-52`.

#### Scenario: Contas senior iguais a zero
- **GIVEN** o formulario com contas senior igual a 0 e contas subordinadas maior que 0
- **WHEN** o percentual e calculado
- **THEN** o percentual apresentado e 0, sem divisao por zero

> AMBIGUIDADE: no legado o campo e derivado (sobrescrito a cada digitacao em qualquer campo do formulario) mas ao mesmo tempo editavel e persistido como coluna propria (`subordinated_accounts_percent`). Confirmar se o valor deve ser calculado no servidor a partir dos dois campos ou continuar sendo um campo armazenado e editavel.

### Requirement: FE-066 — Formatacao de dinheiro, percentual e numero no formulario de Portador
Os campos monetarios, percentuais e numericos DEVEM (SHALL) ser apresentados formatados e enviados ao servidor em formato numerico sem depender de reformatacao concorrente no momento do envio. Fonte legada: `app/views/pub/console/parts/carriers/helper/_body.js.erb:53-172`; `helper/_mount.js.erb:130-152`.

#### Scenario: Valor monetario chega correto ao servidor
- **GIVEN** o usuario digita `1.234,56` no campo de patrimonio liquido
- **WHEN** ele salva o formulario
- **THEN** o servidor recebe o valor numerico 1234.56 e o registro salvo reflete esse valor

> Nota: corrige a condicao de corrida do legado (o JS convertia, disparava `Rails.fire(form,'submit')` e reformatava de volta — se a reformatacao rodasse antes do serialize, o valor formatado ia para o servidor e era castado silenciosamente).

#### Scenario: Mais de um separador decimal
- **GIVEN** o usuario digita `1,23,45` em um campo monetario
- **WHEN** o campo perde o foco
- **THEN** a tela avisa que basta um separador decimal e o valor nao e enviado malformado

### Requirement: FE-067 — Logo do Portador
A interface de portador NAO DEVE (SHALL NOT) manter controles de upload sem efeito. Fonte legada: `app/views/pub/console/parts/carriers/helper/_body.html.erb:13-23`; `helper/_body.js.erb:12-37`.

#### Scenario: Formulario de portador sem controle morto
- **GIVEN** o formulario de portador
- **WHEN** o usuario o abre
- **THEN** ou o upload de logo esta disponivel e funcional, ou nao ha nenhum vestigio dele na tela

> AMBIGUIDADE: no legado todo o bloco de avatar esta comentado no HTML e o widget da lista tambem comenta a exibicao do logo, mas o handler JS de preview continua vivo e o backend aceita `logo` normalmente (BE-069). Confirmar se o logo de portador deve ser reativado ou removido de vez.

### Requirement: FE-068 — Detalhe de Portador
A tela de detalhe de portador DEVE (SHALL) ser acessivel e apresentar titulo, resumo e as acoes de editar, excluir e configurar relacoes. Fonte legada: `app/views/pub/console/parts/carriers/detail/_body.html.erb:1-47`.

#### Scenario: Abrir o detalhe de um portador
- **GIVEN** um portador na lista
- **WHEN** o usuario escolhe ver o detalhe
- **THEN** a tela de detalhe abre com os dados do portador

> AMBIGUIDADE: D-22 — no legado a tela esta desenhada mas **inacessivel**: `Pub::CarriersController#show` renderiza template inexistente e `Pub::ConsoleController` so trata `section == 'carrier_connections'` (`:89-92`); `openDetail` existe em `carriers/_body.js.erb:152-160` mas nenhum elemento o chama. Decidir se a tela entra no escopo da migracao.

### Requirement: FE-069 — Lista de Fornecedores
A tela de fornecedores DEVE (SHALL) mostrar as colunas Titulo, Projeto, numero de Renegociacoes e o avatar, com busca, ordenacao por titulo e o botao "Cadastrar" respeitando permissao. Fonte legada: `app/views/pub/console/parts/providers/_body.html.erb:1-41`; `_body.js.erb:57-70,101-131`.

#### Scenario: Permissao de cadastro coerente com os demais cadastros
- **GIVEN** um usuario nao somente-leitura sem papel administrativo
- **WHEN** ele abre a lista de fornecedores
- **THEN** a disponibilidade do botao "Cadastrar" segue a mesma matriz de autorizacao aplicada no servidor

> AMBIGUIDADE: no legado "Cadastrar" em fornecedores exigia apenas `!user_is_readonly` (sem checagem de papel), diferente de portadores e segmentos, que exigiam admin/og/manager. A matriz correta vem do DEC-08 (a aprovar).

### Requirement: FE-070 — Linha de Fornecedor
Cada linha DEVE (SHALL) mostrar o projeto do fornecedor, a contagem de renegociacoes e o avatar (logo ou iniciais do titulo), com as acoes Editar e Excluir no menu. Fonte legada: `app/views/pub/console/parts/providers/list/_widget.html.erb:1-45`; `list/_widget.js.erb:1-92`.

#### Scenario: Fornecedor sem logo
- **GIVEN** um fornecedor sem logo
- **WHEN** a linha e renderizada
- **THEN** o avatar mostra as iniciais geradas a partir do titulo

#### Scenario: Clique na linha
- **GIVEN** a lista de fornecedores
- **WHEN** o usuario clica na linha
- **THEN** o comportamento e o mesmo apresentado pela interface, sem acoes inertes

> AMBIGUIDADE: no legado o handler de clique apontava para `.provider_widget_content`, seletor **inexistente** (a linha usa `.provider_content_flex`), entao a rota `provider_connections` nunca era aberta e o parcial correspondente nem existe. Confirmar se "relacoes de fornecedor" e feature a construir ou codigo morto a descartar.

### Requirement: FE-071 — Formulario de Fornecedor e alternancia CPF/CNPJ
O formulario DEVE (SHALL) alternar entre os blocos de CPF e de CNPJ conforme o tipo de documento escolhido, garantindo que apenas os campos do tipo selecionado sejam enviados. Fonte legada: `app/views/pub/console/parts/providers/helper/_body.html.erb:1-174`; `helper/_body.js.erb:10-58`.

#### Scenario: Trocar de CNPJ para CPF
- **GIVEN** um formulario com os 15 campos do bloco CNPJ preenchidos
- **WHEN** o usuario troca o tipo de documento para CPF
- **THEN** os campos do bloco CNPJ deixam de ser enviados ao servidor e o registro salvo nao os contem

> Nota: corrige o comportamento parcial do legado (o "desabilitar" era apenas uma classe CSS — os campos continuavam sendo enviados; a limpeza dependia de um `clear` em 15 campos no JS).

### Requirement: FE-072 — Mascara e validacao de CNPJ/CPF no formulario
O formulario DEVE (SHALL) aplicar mascara de CPF/CNPJ e avisar sobre documento invalido ou incompleto antes do envio, sem substituir a validacao do servidor. Fonte legada: `app/views/pub/console/parts/providers/helper/_body.js.erb:93-137,264-349`.

#### Scenario: Documento incompleto
- **GIVEN** o usuario digita apenas 9 digitos no campo de CNPJ
- **WHEN** o campo perde o foco
- **THEN** a tela avisa que o documento esta incompleto

> Nota: corrige o legado, que so validava quando o comprimento era exatamente 14/11 — documento incompleto passava sem aviso e so era rejeitado no servidor.

### Requirement: FE-073 — Autopreenchimento por CNPJ no formulario de Fornecedor
O formulario DEVE (SHALL) permitir buscar os dados cadastrais pelo CNPJ e preencher os campos correspondentes, com feedback de progresso, sucesso e falha. Fonte legada: `app/views/pub/console/parts/providers/helper/_body.js.erb:140-255`; `helper/_body.html.erb:54-56`.

#### Scenario: Buscar dados pelo CNPJ
- **GIVEN** um CNPJ valido digitado no formulario
- **WHEN** o usuario aciona a busca
- **THEN** os campos cadastrais sao preenchidos com o retorno da consulta e o titulo recebe o nome fantasia (ou, se vazio, a razao social)

> AMBIGUIDADE: D-27 — no legado o recurso esta **duplamente morto**: o botao `.cnpj_search_button` esta comentado no HTML e a URL no JS usa `<%%=` (ERB escapado, `:156`), sendo renderizada como texto. Confirmar se o autopreenchimento deve voltar a funcionar no ai9.

### Requirement: FE-074 — Upload de logo do Fornecedor
O formulario de fornecedor DEVE (SHALL) permitir enviar um logo com preview local e limpar a selecao em caso de falha no envio. Fonte legada: `app/views/pub/console/parts/providers/helper/_body.html.erb:15-25`; `helper/_body.js.erb:60-90`.

#### Scenario: Arquivo acima do limite
- **GIVEN** o usuario escolhe uma imagem maior que o limite aceito
- **WHEN** ele tenta salvar
- **THEN** a tela informa o limite antes de enviar o arquivo ao servidor

> Nota: corrige a ausencia de validacao no cliente do legado (tamanho e tipo eram checados apenas no servidor, 1 MB e `image/*`).

### Requirement: FE-075 — Lista de Grupos de Portadores
A tela DEVE (SHALL) mostrar Titulo (ordenavel) e numero de Portadores, com busca, cadastro conforme permissao e exclusao apenas para grupos sem portadores. Fonte legada: `app/views/pub/console/parts/carrier_groups/_body.html.erb:1-37`; `list/_widget.html.erb:1-31`; `list/_widget.js.erb:31-45`.

#### Scenario: Confirmacao de exclusao de grupo
- **GIVEN** um grupo sem portadores
- **WHEN** o usuario confirma a exclusao
- **THEN** a mensagem de sucesso se refere ao grupo excluido

> Nota: corrige a copia incorreta do legado (o toast de sucesso dizia "**O portador** foi excluido com sucesso", texto copiado da tela de portadores).

### Requirement: FE-076 — Painel de criar/editar Grupo de Portadores
O painel DEVE (SHALL) oferecer o campo de titulo e confirmar a criacao ou atualizacao do grupo. Fonte legada: `app/views/pub/console/parts/carrier_groups/helper/_body.html.erb:1-13`.

#### Scenario: Criar um grupo
- **GIVEN** o painel de novo grupo aberto
- **WHEN** o usuario informa o titulo e salva
- **THEN** o grupo aparece na lista e uma confirmacao de sucesso e exibida

### Requirement: FE-077 — Lista, linha e painel de Segmentos
A tela de segmentos DEVE (SHALL) mostrar Titulo e Chave (ambos ordenaveis), permitir buscar, cadastrar, editar e excluir, e DEVE (SHALL) comunicar o resultado da exclusao. Fonte legada: `app/views/pub/console/parts/segments/_body.html.erb:1-40`; `list/_widget.js.erb:25-40`; `helper/_body.html.erb:1-36`.

#### Scenario: Exclusao de segmento em uso e comunicada
- **GIVEN** um segmento associado a projetos
- **WHEN** o usuario confirma a exclusao
- **THEN** a tela mostra o erro devolvido pelo servidor e o segmento permanece na lista

> Nota: corrige D-24 (legado: `list/_widget.js.erb:30-39` so tratava `success`, recarregando a lista — a exclusao bloqueada falhava em silencio).

#### Scenario: Criar um segmento pela tela
- **GIVEN** o painel de novo segmento aberto
- **WHEN** o usuario informa titulo, chave de integracao e situacao e salva
- **THEN** o segmento e criado e aparece na lista

> Nota: corrige D-21 (legado: a criacao de segmento **sempre** falhava por causa de `user_id` nao permitido em `segment_params`).

### Requirement: FE-078 — Lista, linha e painel de Subsegmentos
A tela de subsegmentos DEVE (SHALL) espelhar a de segmentos (Titulo, Chave, Ativo), com textos proprios de subsegmento e tratamento de erro na exclusao. Fonte legada: `app/views/pub/console/parts/sub_segments/_body.html.erb:1-40`; `list/_widget.js.erb:26-41`; `helper/_body.html.erb:1-36`.

#### Scenario: Textos proprios do dominio
- **GIVEN** o painel de novo subsegmento
- **WHEN** o usuario o abre
- **THEN** os textos e exemplos se referem a subsegmento

> Nota: corrige o texto herdado do legado (o placeholder de titulo em subsegmentos ainda dizia "Ex: Segmento Comercial").

#### Scenario: Exclusao de subsegmento em uso e comunicada
- **GIVEN** um subsegmento associado a projetos
- **WHEN** o usuario confirma a exclusao
- **THEN** a tela mostra o erro devolvido pelo servidor e o subsegmento permanece na lista

> Nota: corrige D-24.

### Requirement: FE-079 — Estados de container e identidade visual dos seis cadastros
Todas as telas dos seis cadastros DEVEM (SHALL) apresentar estados consistentes de carregamento, vazio e falha, com textos pertencentes ao dominio. Fonte legada: `app/frontend/css/pub/components/{carriers,carrier_groups,companies,providers,segments,sub_segments}/`; `helper/_mount.js.erb` de cada entidade.

#### Scenario: Estado vazio do painel lateral
- **GIVEN** um painel lateral que nao consegue carregar o registro pedido
- **WHEN** o estado vazio e apresentado
- **THEN** a mensagem se refere a entidade correta

> Nota: corrige o texto herdado de outro produto no legado — a mensagem de vazio do painel era "Essa construtora nao pode ser alterada" nas **seis** entidades.

#### Scenario: Falha de carregamento
- **GIVEN** uma falha de rede ao carregar a lista
- **WHEN** o erro ocorre
- **THEN** a tela apresenta o estado de falha com opcao de tentar novamente

### Requirement: DB-050 — Tabela `companies`
O modelo de dados DEVE (SHALL) conter empresas ligadas a um projeto, com chave estrangeira, indices de busca e restricao unica que sustente a unicidade de titulo por projeto. Fonte legada: `db/migrate/20210510211117_create_companies.rb`; `app/models/company.rb`.

#### Scenario: Titulo duplicado no mesmo projeto bloqueado no banco
- **GIVEN** duas requisicoes concorrentes criando a mesma empresa no mesmo projeto
- **WHEN** ambas sao processadas
- **THEN** apenas uma persiste e a outra falha com erro de unicidade

> Nota: corrige a ausencia de indice unico composto `(project_id, title)` no legado (a unicidade era so de aplicacao, permitindo corrida) e a ausencia de FK/indice em `project_id`.

### Requirement: DB-051 — `companies.has_safegold_management`
O modelo de dados DEVE (SHALL) definir como a marca de gestao Safegold se relaciona com empresa e projeto. Fonte legada: `db/migrate/20210511211918_add_safegold_managed_bool_to_projects.rb:7`; `app/models/project.rb:298-303`.

#### Scenario: Alteracao da marca no projeto
- **GIVEN** um projeto com empresas e com a marca de gestao Safegold ligada
- **WHEN** a marca do projeto e desligada
- **THEN** o valor observado para as empresas desse projeto reflete a regra definida (derivado do projeto, ou carimbo com data de referencia)

> AMBIGUIDADE: D-30 — no legado `has_safegold_management` e um carimbo denormalizado propagado para 6 tabelas (companies, availability/receivable entries, renegotiations, risk_controls/entries), mas **so `companies` e atualizado em massa** quando a flag muda (via `update_all`, pulando validacoes e callbacks). Confirmar se o carimbo e intencional (foto do momento, para relatorio historico) ou bug — a resposta muda o desenho do modelo no ai9. Alem disso o campo e booleano modelado como inteiro.

### Requirement: DB-052 — Tabela `providers` (base)
O modelo de dados DEVE (SHALL) conter fornecedores ligados a um projeto, com titulo, resumo, usuario responsavel, situacao, logo, chave de integracao e documento, com FKs e indices de busca. Fonte legada: `db/migrate/20210325141909_create_providers.rb`; `app/models/provider.rb`.

#### Scenario: Busca por documento em base grande
- **GIVEN** uma base com dezenas de milhares de fornecedores
- **WHEN** a busca por CNPJ e executada
- **THEN** a consulta usa indice e responde dentro do limite de performance definido

> Nota: corrige a ausencia de indices no legado (`project_id`, `cnpj`, `cpf`, `integration_key` sem indice) e o uso de `is_active` inteiro como booleano.

### Requirement: DB-053 — `providers.cpf`
O modelo de dados DEVE (SHALL) representar o documento do fornecedor de forma que o tipo (CPF ou CNPJ) e o valor sejam consultaveis sem ambiguidade. Fonte legada: `db/migrate/20210426135539_add_cpf_to_providers.rb`.

#### Scenario: Fornecedor com CPF
- **GIVEN** um fornecedor cadastrado com CPF
- **WHEN** o registro e lido
- **THEN** o tipo de documento e o valor sao devolvidos de forma explicita

> AMBIGUIDADE: no legado o documento pode ser CPF **ou** CNPJ **ou nenhum** (a regra "ao menos um" esta comentada no model). A migracao precisa decidir se normaliza em um par `(tipo, documento)` — o que depende da mesma resposta pedida em BE-066.

### Requirement: DB-054 — Campos cadastrais vindos da ReceitaWS em `providers`
O modelo de dados DEVE (SHALL) guardar os campos cadastrais obtidos por consulta externa (abertura, bairro, cep, data de situacao, email, fantasia, logradouro, complemento, municipio, nome, numero, situacao, telefone, uf) com registro de quando foram obtidos. Fonte legada: `db/migrate/20210504151249_add_cnpj_api_fields_to_providers.rb:3-16`.

#### Scenario: Rastreabilidade do snapshot cadastral
- **GIVEN** um fornecedor cujos dados vieram de consulta externa
- **WHEN** o registro e lido
- **THEN** e possivel saber quando o snapshot foi obtido

> Nota: corrige a ausencia de carimbo de "consultado em" no legado; `abertura`/`data_situacao` eram `date` mas recebiam texto vindo da API.

### Requirement: DB-055 — `providers.atividades` e `providers.cnaes`
O modelo de dados DEVE (SHALL) armazenar atividades e CNAEs do fornecedor em um unico formato estruturado consultavel. Fonte legada: `db/migrate/20210504151249_add_cnpj_api_fields_to_providers.rb:17-18`; `app/models/provider.rb:2,97-110`.

#### Scenario: Leitura de atividades e CNAEs migrados
- **GIVEN** um fornecedor legado com `cnaes` em YAML e `atividades` em JSON
- **WHEN** o registro e migrado e lido no ai9
- **THEN** ambos os campos sao devolvidos como estruturas JSON equivalentes ao conteudo original

> Nota: corrige D-25 (legado: `cnaes` usava `serialize` YAML do Rails e `atividades` usava JSON manual na **mesma tabela**). A leitura do YAML legado exige carga segura com classes permitidas.

### Requirement: DB-056 — Anexo de logo de `providers`
O modelo de dados DEVE (SHALL) guardar o logo do fornecedor e seus derivados no storage do ai9. Fonte legada: `db/migrate/20210325141909_create_providers.rb:11`.

#### Scenario: Logo migrado com derivados
- **GIVEN** um fornecedor legado com logo em `public/system/logos/:id/...`
- **WHEN** o registro e migrado
- **THEN** o logo esta acessivel pelo storage do ai9 e os tamanhos derivados usados pela interface estao disponiveis

### Requirement: DB-057 — Tabela `carriers` (base)
O modelo de dados DEVE (SHALL) conter portadores como catalogo global, com titulo, resumo, situacao, logo, chave de integracao, codigo e nome do banco, contas senior e subordinadas, percentual e patrimonio liquido. Fonte legada: `db/migrate/20210301192131_create_carriers.rb`; `app/models/carrier.rb`.

#### Scenario: Codigo do banco com zero a esquerda
- **GIVEN** um portador cujo codigo de banco no legado e `1` mas o codigo real do banco e `001`
- **WHEN** o dado e migrado
- **THEN** o codigo armazenado e textual e preserva os zeros a esquerda

> Nota: corrige D-25 (legado: `bank_code` era `integer`, corrompendo zeros a esquerda). Corrige tambem `subordinated_accounts_percent` como `float` para percentual financeiro, e a redundancia de `bank_name` sempre igual a `title`.

### Requirement: DB-058 — `carriers.group_id`
O modelo de dados DEVE (SHALL) ligar portador a grupo com chave estrangeira e indice, definindo o comportamento na exclusao do grupo. Fonte legada: `db/migrate/20210819194535_add_group_column_to_carrier.rb`.

#### Scenario: Referencia de grupo sempre valida
- **GIVEN** portadores vinculados a um grupo
- **WHEN** alguem tenta remover esse grupo diretamente no banco
- **THEN** a operacao e recusada pela chave estrangeira

> Nota: corrige a ausencia de FK/indice no legado — excluir grupo deixava `group_id` orfao apontando para id inexistente (BE-073).

### Requirement: DB-059 — `carriers.financial_agent`
O modelo de dados DEVE (SHALL) restringir o agente financeiro ao conjunto conhecido (FIDC, Securitizadora, Factoring, Cliente). Fonte legada: `db/migrate/20220620135412_add_agent_to_carriers.rb`; `app/models/carrier.rb:46-49`.

#### Scenario: Valor fora do conjunto na migracao de dados
- **GIVEN** registros legados com `financial_agent` fora do conjunto conhecido ou em branco
- **WHEN** a migracao de dados roda
- **THEN** os registros divergentes sao reportados no relatorio de dry-run antes de qualquer insercao

> Nota: corrige a ausencia de constraint e de validacao no legado (o conjunto existia apenas no `<select>`).

### Requirement: DB-060 — `carriers.city` e `carriers.uf`
O modelo de dados DEVE (SHALL) guardar cidade e UF do portador com UF normalizada. Fonte legada: `db/migrate/20220810142317_add_city_column_to_carriers.rb`.

#### Scenario: UF normalizada na migracao
- **GIVEN** registros legados com UF em caixa e formatos variados
- **WHEN** a migracao de dados roda
- **THEN** a UF armazenada segue a sigla de dois caracteres em caixa alta, e valores nao reconhecidos sao reportados

### Requirement: DB-061 — `carriers.legacy_id`
O modelo de dados DEVE (SHALL) preservar a chave de correlacao com o sistema anterior. Fonte legada: `db/migrate/20210402111120_add_legacy_id_to_entries_and_projects.rb`.

#### Scenario: Reconciliacao pos-migracao
- **GIVEN** portadores importados do sistema anterior
- **WHEN** a reconciliacao e executada
- **THEN** cada portador migrado pode ser correlacionado ao registro de origem pelo identificador legado, que continua unico

### Requirement: DB-062 — Anexo de logo de `carriers`
O modelo de dados DEVE (SHALL) guardar o logo do portador quando ele existir. Fonte legada: `db/migrate/20210301192131_create_carriers.rb:9`.

#### Scenario: Verificacao antes de migrar binarios
- **GIVEN** as colunas de anexo de portador no legado
- **WHEN** a migracao de dados e planejada
- **THEN** o relatorio informa quantos portadores realmente possuem arquivo, ja que o upload esta desativado na interface (FE-067)

### Requirement: DB-063 — Tabela `carrier_groups`
O modelo de dados DEVE (SHALL) conter grupos de portadores com titulo, usuario responsavel e contagem de portadores consistente. Fonte legada: `db/migrate/20210819193736_create_carrier_groups.rb`; `app/models/carrier_group.rb`.

#### Scenario: Contagem sem valor nulo apos a migracao
- **GIVEN** grupos legados com `carriers_count` nulo
- **WHEN** a migracao de dados roda
- **THEN** todos os grupos terminam com a contagem recalculada a partir dos portadores reais

> Nota: corrige a coluna criada sem default no legado.

### Requirement: DB-064 — Tabela `segments`
O modelo de dados DEVE (SHALL) conter segmentos como catalogo global, com titulo unico, chave de integracao, situacao e usuario responsavel. Fonte legada: `db/migrate/20210317140228_create_segments.rb`; `app/models/segment.rb`.

#### Scenario: Unicidade de titulo garantida no banco
- **GIVEN** dois processos criando o segmento "Comercio" ao mesmo tempo
- **WHEN** ambos sao processados
- **THEN** apenas um persiste

> Nota: corrige a unicidade apenas de aplicacao do legado (sem indice unico). Ver tambem D-26: `Project#reset` forcava `segment_id = 1` (`app/models/project.rb:710`), id fixo que a migracao nao pode assumir.

### Requirement: DB-065 — `segments.legacy_id`
O modelo de dados DEVE (SHALL) preservar a correlacao dos segmentos com a tabela legada de origem. Fonte legada: `db/migrate/20210402111120_add_legacy_id_to_entries_and_projects.rb`.

#### Scenario: Correlacao de segmentos importados
- **GIVEN** segmentos importados do sistema anterior
- **WHEN** a reconciliacao e executada
- **THEN** cada segmento migrado pode ser correlacionado ao registro de origem

### Requirement: DB-066 — Tabela `sub_segments`
O modelo de dados DEVE (SHALL) conter subsegmentos como catalogo global independente, com titulo unico, chave de integracao e situacao. Fonte legada: `db/migrate/20211025163246_create_sub_segments.rb`; `app/models/sub_segment.rb`.

#### Scenario: Subsegmento nao pertence a um segmento
- **GIVEN** um subsegmento cadastrado
- **WHEN** o registro e lido
- **THEN** ele nao exige nem referencia um segmento pai

> AMBIGUIDADE: apesar do nome, no legado nao ha FK nem associacao entre `sub_segments` e `segments`, e `sub_segments` **nao tem** `legacy_id` (diferente de `segments`). Confirmar se a hierarquia segmento→subsegmento e desejada no ai9 ou se os dois catalogos permanecem independentes.

### Requirement: DB-067 — `projects.segment_id` e `projects.sub_segment_id`
O modelo de dados DEVE (SHALL) ligar projeto a segmento e subsegmento com chaves estrangeiras e indices, ambos opcionais. Fonte legada: `db/migrate/20211025163624_add_sub_segment_to_project.rb`; `app/models/project.rb:5-6`.

#### Scenario: Segmento inexistente nao pode ser referenciado
- **GIVEN** uma tentativa de gravar um projeto com um segmento que nao existe
- **WHEN** a gravacao ocorre
- **THEN** a operacao e recusada

> Nota: corrige D-26 (legado: sem FK nem indice, e `Project#reset` forcava `segment_id = 1` e zerava `sub_segment_id`).

### Requirement: DB-068 — Ponte `project_to_carrier_connections`
O modelo de dados DEVE (SHALL) manter a relacao entre projeto e portador como a unica ponte, da qual a relacao empresa-portador e derivada. Fonte legada: `db/migrate/20210301192607_create_project_to_carrier_connections.rb`; `app/models/project_to_carrier_connection.rb:3`.

#### Scenario: Portadores de uma empresa sao derivados do projeto
- **GIVEN** uma empresa em um projeto que tem 3 portadores conectados
- **WHEN** os portadores da empresa sao consultados
- **THEN** os 3 portadores do projeto sao devolvidos, sem que exista tabela propria empresa-portador

### Requirement: DB-069 — `risk_controls.company_id` e `risk_controls.carrier_id`
O modelo de dados DEVE (SHALL) aplicar a mesma politica de exclusao para empresa e portador em relacao aos controles de risco: bloquear, nunca apagar em cascata. Fonte legada: `db/migrate/20210510211438_create_risk_controls.rb`; `app/models/company.rb:4-7`; `app/models/carrier.rb:6-7`.

#### Scenario: Politica de exclusao simetrica
- **GIVEN** controles de risco vinculados a uma empresa e a um portador
- **WHEN** qualquer um dos dois e excluido
- **THEN** a exclusao e bloqueada e nenhum controle de risco e removido

> Nota: corrige D-24 (legado: assimetria perigosa — excluir empresa era bloqueado, excluir portador apagava os limites em cascata).

### Requirement: DB-070 — `receivable_entries.company_id` e `.carrier_id`
O modelo de dados DEVE (SHALL) exigir empresa e portador validos nos recebiveis, com FK e indice. Fonte legada: `db/migrate/20220322123523_add_company_to_receivable_entries.rb`.

#### Scenario: Recebiveis sem empresa detectados na migracao
- **GIVEN** recebiveis legados sem empresa associada
- **WHEN** a migracao de dados roda
- **THEN** eles sao reportados como orfaos no dry-run, antes de qualquer insercao

> Nota: no legado a rotina manual `ReceivableEntry.fix_entries_without_company` (`app/models/receivable_entry.rb:234-243`) criava "Empresa Padrao" e ligava tudo a ela — indicio de que existem recebiveis sem empresa.

### Requirement: DB-071 — `renegotiations.company_id` e `.provider_id`
O modelo de dados DEVE (SHALL) exigir empresa e fornecedor validos nas renegociacoes, com FK e indice. Fonte legada: `db/migrate/20220407163633_add_company_to_renegotiation.rb`; `app/models/provider.rb:5`.

#### Scenario: Renegociacoes sem empresa detectadas na migracao
- **GIVEN** renegociacoes legadas sem empresa associada
- **WHEN** a migracao de dados roda
- **THEN** elas sao reportadas como orfas no dry-run

### Requirement: DB-072 — Integridade referencial e indices dos cadastros
Todas as tabelas destes cadastros DEVEM (SHALL) nascer com chaves estrangeiras, indices nas colunas de busca e indices unicos que reflitam as regras de unicidade. Fonte legada: migrations de `companies`, `providers`, `carriers`, `carrier_groups`, `segments`, `sub_segments`.

#### Scenario: Verificacao do esquema alvo
- **GIVEN** o esquema do ai9 criado
- **WHEN** as tabelas destes cadastros sao inspecionadas
- **THEN** todas as colunas de relacionamento tem chave estrangeira e indice, e as colunas de busca (`title`, `project_id`, `cnpj`, `cpf`, `integration_key`, `group_id`) tem indice

> Nota: corrige o legado, onde nao havia nenhuma `add_foreign_key` e os unicos indices nao-PK eram `legacy_id` em `carriers` e `segments`.

### Requirement: DB-073 — Ausencia de esquema consolidado no legado
A migracao de dados DEVE (SHALL) comecar por uma introspecao do esquema real de origem e abortar com relatorio quando encontrar estrutura desconhecida. Fonte legada: `db/` do legado (sem `schema.rb`, apenas `migrate/`).

#### Scenario: Coluna fora das migrations
- **GIVEN** o banco legado contem uma coluna que nenhuma migration cria
- **WHEN** a etapa de introspecao roda
- **THEN** o processo aborta e o relatorio lista a estrutura desconhecida

> Nota: DEC-04 — seguimos apenas com as 139 migrations; ja ha duas provas de estrutura fora delas (`default_position`, ver BE-132/DB-134 na capacidade `availability`, e `contracts.description`).

### Requirement: DB-074 — Volumetria dos cadastros
A migracao de dados DEVE (SHALL) medir e reportar a volumetria destes cadastros antes do cutover. Fonte legada: nao medida no Phase 1 (sem acesso ao banco).

#### Scenario: Relatorio de volumetria
- **GIVEN** acesso ao banco legado
- **WHEN** a etapa de levantamento roda
- **THEN** o relatorio informa numero de empresas por projeto, portadores globais, fornecedores por projeto, segmentos e subsegmentos, e quantos fornecedores tem CPF, CNPJ ou nenhum documento

### Requirement: OPS-050 — Integracao ReceitaWS
A integracao de consulta de CNPJ DEVE (SHALL) ter credencial configurada por ambiente, tempo limite, cache e tratamento de indisponibilidade. Fonte legada: `config/initializers/receitaws.rb:1-16`; `app/helpers/cnpj_api.rb:1-5`.

#### Scenario: Provedor indisponivel
- **GIVEN** a ReceitaWS fora do ar
- **WHEN** o usuario aciona a consulta de CNPJ
- **THEN** a resposta e um erro tratado dentro do tempo limite configurado, sem derrubar o cadastro de fornecedor

> AMBIGUIDADE: D-27 — a integracao esta configurada (token em `ENV['rws_api_token']`, cache de 365 dias, timeout de 10 s) mas nao ha UI que a acione. Confirmar se ela e portada.

### Requirement: OPS-051 — Armazenamento de anexos de fornecedor e portador
O armazenamento de logos DEVE (SHALL) validar o tipo real do arquivo e usar o storage do ai9. Fonte legada: `app/models/provider.rb:12-24`; `app/models/carrier.rb:16-28`; `config/initializers/paperclip.rb:1-14`.

#### Scenario: Arquivo com tipo forjado
- **GIVEN** um arquivo executavel renomeado para `.png`
- **WHEN** o usuario tenta envia-lo como logo
- **THEN** o envio e recusado

> Nota: corrige o legado, onde `MediaTypeSpoofDetector#spoofed?` estava sobrescrito para retornar sempre `false` (deteccao de spoofing desativada). Corrige tambem o armazenamento em filesystem local em vez de object storage.

### Requirement: OPS-052 — Importador legado de Portadores
Os portadores importados do sistema anterior DEVEM (SHALL) ser preservados com sua correlacao de origem; o pipeline de importacao em si NAO e portado. Fonte legada: `app/models/legacy/carrier.rb:1-31`; `app/models/legacy.rb:2-15,40-48`.

#### Scenario: Portadores de origem legada apos a migracao
- **GIVEN** portadores criados pelo importador da tabela `dbanco`
- **WHEN** a migracao para o ai9 roda
- **THEN** os portadores e seus identificadores de origem sao preservados, e nenhum codigo do pipeline `Legacy::execute` e portado

> Nota: DEC-12 — o pipeline e assumido como nao executado desde 2021; as colunas `legacy_*` sao preservadas por serem a unica prova de proveniencia. O importador atribuia `user_id` fixo em 1.

### Requirement: OPS-053 — Importador legado de Segmentos
Os segmentos importados do sistema anterior DEVEM (SHALL) ser preservados com sua correlacao de origem; o pipeline de importacao NAO e portado. Fonte legada: `app/models/legacy/segment.rb:1-25`.

#### Scenario: Segmentos de origem legada apos a migracao
- **GIVEN** segmentos criados pelo importador da tabela `dsegmento`
- **WHEN** a migracao para o ai9 roda
- **THEN** os segmentos e seus identificadores de origem sao preservados

> Nota: DEC-12.

### Requirement: OPS-054 — Dados de semente de segmentos, portadores e empresas
O ambiente DEVE (SHALL) poder ser semeado com os catalogos minimos, separando semente de catalogo de semente de demonstracao. Fonte legada: `db/seeds.rb:160-163,225-236`.

#### Scenario: Semente de ambiente limpo
- **GIVEN** um ambiente novo
- **WHEN** a semente de catalogo e aplicada
- **THEN** os segmentos base existem e nenhum dado de demonstracao (empresas de teste, controles de risco aleatorios) e criado

> Nota: o legado misturava as duas coisas — o bloco de empresas e controles de risco esta marcado no proprio codigo como "seed feito somente para video de aprovacao".

### Requirement: OPS-055 — Rotinas de correcao de vinculo de empresa
Correcoes em massa de vinculo entre empresa e recebiveis/renegociacoes DEVEM (SHALL) ser operacoes idempotentes, auditadas e com pre-visualizacao. Fonte legada: `app/models/receivable_entry.rb:233-243`; `app/models/renegotiation.rb:294-304`.

#### Scenario: Correcao em massa auditada
- **GIVEN** recebiveis e renegociacoes sem empresa em varios projetos
- **WHEN** a rotina de correcao e executada
- **THEN** ela reporta o que sera alterado antes de alterar, registra o que alterou e pode ser executada novamente sem efeito adicional

> Nota: corrige o legado, onde as rotinas eram executadas a mao no console, faziam `update_all` ligando **todos** os recebiveis/renegociacoes do projeto a uma unica empresa, sem log e sem idempotencia real.

### Requirement: OPS-056 — Busca textual independente de adapter
A busca textual dos cadastros DEVE (SHALL) funcionar sem interpolar SQL especifico de adapter e sem concatenar entrada do usuario na consulta. Fonte legada: `config/initializers/dev.rb:2-21`.

#### Scenario: Termo de busca com caractere especial
- **GIVEN** um usuario que busca por `100%` ou `a'b`
- **WHEN** a busca e executada
- **THEN** o termo e tratado como texto literal e a consulta nao e alterada por ele

> Nota: corrige o legado, onde `Dev.ilike` trocava entre sintaxe Postgres e MySQL em runtime e era interpolado direto na string SQL. DEC-05: o banco e PostgreSQL.

### Requirement: OPS-057 — Cidade e UF nos cadastros
Cidade e UF de portador e de fornecedor DEVEM (SHALL) ser tratados como dados do proprio cadastro, sem dependencia de servicos de geolocalizacao. Fonte legada: `Gemfile.linux:17,26`; `config/initializers/geocoding.rb`; `app/controllers/pub/console_controller.rb:255-275`.

#### Scenario: Preenchimento de cidade e UF
- **GIVEN** o formulario de portador
- **WHEN** o usuario informa cidade e UF
- **THEN** os valores sao validados e salvos sem consultar servico externo de geolocalizacao

> Nota: no legado `city-state` e `geocoder` estavam configurados mas nao se aplicavam a estes cadastros, e as actions `state_select`/`city_select` sequer tinham rota.

### Requirement: OPS-058 — Contagem de portadores por grupo
A contagem de portadores exibida por grupo DEVE (SHALL) coincidir com a contagem real em qualquer momento. Fonte legada: `app/models/carrier_group.rb:2`; `db/migrate/20210819193736_create_carrier_groups.rb:7`.

#### Scenario: Contagem exibida coincide com a lista
- **GIVEN** um grupo cujo contador foi criado fora do fluxo normal
- **WHEN** a lista de grupos e aberta
- **THEN** o numero exibido coincide com o numero de portadores realmente vinculados

> Nota: corrige a divergencia do legado entre `counter_cache` (sem default, podendo ficar nulo) e a contagem real usada pela UI para decidir se mostra o botao de exclusao.
