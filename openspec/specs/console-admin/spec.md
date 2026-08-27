# Console Admin Specification

## Purpose
Casca administrativa do produto: roteamento e navegacao das areas do console, projeto corrente, topbar, menu lateral, gavetas e barra de acoes, area de "Inicio", mensagens administrativas e observadores de feedback, mais a biblioteca de componentes reutilizaveis de interface.

> Nota de escopo (DEC-09) — **nao existe dashboard**. O `dash` do legado e apenas um **redirecionador por papel**: `og?` vai para usuarios; `admin?`/`manager?` vao para projetos quando nao ha projeto e para recebiveis quando ha; os demais vao para minha conta quando nao ha projeto e para resultados quando ha. Isso, e so isso, e o que vira spec (FE-404). **Nao** ha widget, periodo, filtro nem agregacao, e nada disso e inventado — nao ha tabela, view materializada nem rotina que alimente indicadores (DB-399).
> Nota de escopo (D-92 / DEC-09) — o esquema de navegacao `resource/topic/section` do legado, com estado so em memoria JS e URL espelhada por `replaceState`, **nao e reproduzido**. O ai9 usa **roteador real, com historico do navegador e deep-link por area**. Os requisitos de despacho abaixo descrevem **quais areas existem e o que cada uma carrega**, nao o mecanismo legado.
> Nota de escopo (DEC-10) — os componentes proprietarios `vendor/doughnut` (unico grafico do produto) e `vendor/dialog` sao substituidos pelas **libs do ai9**, nao portados um para um. O que se preserva e o **comportamento**.
> Nota de escopo (DEC-09) — i18n fica fora (D-115): pt-BR fixo.

## Requirements

### Requirement: BE-390 — Areas do console e deep-link
O console SHALL organizar as areas administrativas em rotas proprias, cada uma com URL estavel e compartilhavel. Fonte legada: `config/routes.rb:45,242`; `app/controllers/pub/console_controller.rb`.

> Nota: corrige D-92 (legado: um unico ponto de entrada com segmentos opcionais `resource`, `topic` e `section`, em que `topic` e **polimorfico** — pode ser identificador numerico, a palavra `new`, a palavra `detail` ou um UUID — e a resposta muda entre a casca completa e apenas o miolo conforme o formato pedido).

#### Scenario: URL de area e compartilhavel
- **GIVEN** a URL de uma area do console com um registro selecionado
- **WHEN** ela e aberta em uma aba nova
- **THEN** a area abre com o registro carregado, sem passar por nenhuma tela intermediaria

#### Scenario: Area desconhecida
- **GIVEN** uma URL apontando para uma area que nao existe
- **WHEN** ela e aberta
- **THEN** a resposta e 404 com tela de nao encontrado

### Requirement: BE-391 — Projeto corrente do usuario
O console SHALL resolver o projeto corrente do usuario de forma explicita e validada contra a participacao dele no projeto. Fonte legada: `app/controllers/pub/console_controller.rb:2,285-312`.

> Nota: corrige D-28 nesta capability e tres defeitos operacionais (legado: o projeto corrente vem de um **cookie do cliente** com JSON sem tratamento de excecao — cookie corrompido derruba a requisicao com 500; a resolucao **grava no banco** o projeto padrao do usuario **a cada requisicao GET**; e o cookie e reescrito tanto pelo servidor quanto pelo cliente, com formatos de codificacao diferentes). No ai9 o projeto corrente vem do token e e validado contra a participacao a cada requisicao (DEC-07).

#### Scenario: Projeto invalido no estado do cliente
- **GIVEN** um estado de cliente apontando para um projeto que nao existe ou do qual o usuario nao participa
- **WHEN** uma requisicao do console e feita
- **THEN** o projeto corrente e recalculado, a requisicao conclui normalmente e nenhum dado de outro projeto e exposto

#### Scenario: Leitura nao grava
- **GIVEN** qualquer navegacao de leitura no console
- **WHEN** ela e processada
- **THEN** nenhuma gravacao no cadastro do usuario acontece como efeito colateral

#### Scenario: Usuario sem projeto
- **GIVEN** um usuario que nao participa de nenhum projeto
- **WHEN** ele abre o console
- **THEN** as areas que dependem de projeto ficam indisponiveis com explicacao, sem erro

### Requirement: BE-392 — Titulo e identidade da area
Cada area do console SHALL ter titulo proprio e ser alcancavel por URL. Fonte legada: `app/controllers/pub/console_controller.rb:314-406`.

> Nota: corrige D-88 e D-92 (legado: as areas `admin_messages`, `contracts`, `themes`, `feedbacks`, `verification` e `privacy` **nao constam da lista de titulos**, e o ramo final **rebaixa a area para `dash`** — acessar essas URLs leva o usuario ao redirecionador, e a secao nunca abre por URL; alem disso tres areas distintas compartilham o **mesmo titulo errado**, "Garantias do Projeto").

#### Scenario: Toda area tem titulo proprio
- **GIVEN** a lista de areas do console
- **WHEN** cada uma e aberta
- **THEN** o titulo da aba do navegador identifica corretamente a area, sem duplicidade entre areas distintas

#### Scenario: Areas antes inalcancaveis
- **GIVEN** as URLs de mensagens administrativas, contratos e temas
- **WHEN** elas sao abertas
- **THEN** cada uma abre a sua propria area — nenhuma e rebaixada para o redirecionador

### Requirement: BE-393 — Resolucao da tela de listagem por area
O console SHALL resolver a tela de listagem de cada area a partir da configuracao de rotas, falhando de forma explicita quando a area nao tem tela. Fonte legada: `app/controllers/pub/console_controller.rb:244-246`.

> Nota: corrige D-62 nesta capability (legado: o caminho da view e montado por concatenacao com o nome da area — se o diretorio nao existir, o resultado e um erro de template ausente com 500).

#### Scenario: Area sem tela
- **GIVEN** uma area configurada sem tela correspondente
- **WHEN** a configuracao e validada na inicializacao
- **THEN** a inicializacao falha com mensagem clara — o erro nao chega ao usuario em tempo de execucao

### Requirement: BE-394 — Visualizacao no contexto de outro usuario
O console SHALL nao expor um modo de visualizacao no contexto de outro usuario baseado em token. Fonte legada: `app/controllers/pub/console_controller.rb:10-19`.

> Nota: corrige D-89 (legado: quando o segmento de topico casa com um formato de UUID, o codigo chama `current_user.viewing`, associacao que **nao existe em lugar nenhum do codigo** — qualquer URL do console com UUID no topico levanta `NoMethodError` e responde 500; e o mesmo trecho acessa o usuario de uma conexao sem verificar ausencia).

#### Scenario: Identificador em formato inesperado
- **GIVEN** uma URL do console com um identificador em formato de UUID onde se espera um registro
- **WHEN** ela e aberta
- **THEN** a resposta e 404 — nunca erro interno

> AMBIGUIDADE: o trecho revela a intencao de um modo "visualizar como outro usuario" por token, feature morta ou removida pela metade. Confirmar com o tech lead se o ai9 deve implementar a intencao ou descarta-la — lembrando que a personificacao ja existe por outro caminho (OPS-395).

### Requirement: BE-395 — Area de usuarios
A area de usuarios SHALL abrir o detalhe de um usuario existente. Fonte legada: `app/controllers/pub/console_controller.rb:21-24`.

> Nota: corrige a ausencia de verificacao (legado: a busca do usuario nao trata ausencia, entao identificador inexistente renderiza o detalhe com o registro nulo e **a tela quebra**).

#### Scenario: Usuario inexistente
- **GIVEN** o identificador de um usuario que nao existe
- **WHEN** o detalhe e aberto
- **THEN** a resposta e 404

### Requirement: BE-396 — Area de changelog
A area de changelog SHALL ser alcancavel a partir da navegacao. Fonte legada: `app/controllers/pub/console_controller.rb:25-26`; handler em `base/menu/_container.js.erb:186-188`.

> Nota: corrige o link morto (legado: a area so e acionada por um seletor que **nao existe no HTML do menu atual** — o acesso esta morto).

#### Scenario: Acesso pela navegacao
- **GIVEN** um usuario com permissao
- **WHEN** ele abre a navegacao
- **THEN** ha um caminho funcional para a area de changelog

### Requirement: BE-397 — Area de contratos
A area de contratos SHALL abrir o detalhe com o historico de versoes e o formulario de nova versao. Fonte legada: `app/controllers/pub/console_controller.rb:27-37`.

> Nota: corrige D-92 (legado: a area **nao consta da lista de titulos** e por isso e rebaixada para o redirecionador — so era alcancavel por navegacao programatica no JavaScript). O comportamento das telas esta especificado na capability de contratos.

#### Scenario: Detalhe com historico
- **GIVEN** um contrato com varias versoes
- **WHEN** o detalhe e aberto pela URL
- **THEN** todas as versoes do mesmo tipo aparecem, da mais recente para a mais antiga

### Requirement: BE-398 — Area de itens de ajuda
A area de ajuda SHALL abrir o detalhe de um item e os formularios de criacao e edicao. Fonte legada: `app/controllers/pub/console_controller.rb:38-50`.

> Nota: corrige a condicao redundante do legado (`section == 'edit' && section != 'new_item'`, tautologia na linha 47) e a sobrecarga do parametro de topico, ja tratada na capability de ajuda.

#### Scenario: Criacao dentro de uma categoria
- **GIVEN** a URL de criacao de item para uma categoria
- **WHEN** ela e aberta
- **THEN** o formulario abre em modo de criacao com a categoria pre-selecionada

### Requirement: BE-399 — Area de temas
A area de temas SHALL abrir o detalhe e o formulario de tema. Fonte legada: `app/controllers/pub/console_controller.rb:51-62`.

> Nota: corrige D-63 e D-92 (legado: a area **nao consta da lista de titulos** e e rebaixada para o redirecionador, e nao ha item de menu apontando para ela; alem disso o detalhe e o formulario usam **duas variaveis diferentes** para o mesmo tema, o que quebra a tela conforme o caminho).

#### Scenario: Formulario de criacao e de edicao
- **GIVEN** as URLs de criacao e de edicao de tema
- **WHEN** cada uma e aberta
- **THEN** o formulario abre no modo correspondente, com o tema carregado no caso da edicao

### Requirement: BE-400 — Area de projetos
A area de projetos SHALL abrir listagem, detalhe, criacao, edicao e a tela de conexoes com portadores. Fonte legada: `app/controllers/pub/console_controller.rb:63-96`.

> Nota: corrige o uso de operador bit a bit onde se pretendia operador logico (legado: linha 85 e outras usam `&` em vez de `&&` — funciona por acaso com valores logicos e e fragil) e registra que ha um modo de detalhe para colaborador **desativado por comentario** no codigo.

#### Scenario: Criacao com lista de responsaveis filtrada
- **GIVEN** um usuario com permissao criando um projeto
- **WHEN** o formulario abre
- **THEN** a lista de possiveis responsaveis vem filtrada pelos papeis que ele pode atribuir

#### Scenario: Projeto inexistente na edicao
- **GIVEN** o identificador de um projeto que nao existe
- **WHEN** a edicao e aberta
- **THEN** a resposta e 404

> AMBIGUIDADE: o modo de detalhe de projeto para colaborador esta comentado no legado. Confirmar com o tech lead se ele deve voltar no ai9.

### Requirement: BE-401 — Tela de conexoes com portadores
A tela de conexoes com portadores SHALL servir a projetos, portadores e recebiveis, com o dono da conexao explicito. Fonte legada: `app/controllers/pub/console_controller.rb:89-92`.

#### Scenario: Dono da conexao
- **GIVEN** a tela de conexoes aberta a partir de um projeto e depois a partir de um portador
- **WHEN** cada uma carrega
- **THEN** a tela mostra as conexoes do dono correspondente, com a mesma interface

### Requirement: BE-402 — Area de recebiveis
A area de recebiveis SHALL abrir listagem, detalhe, criacao e edicao, com o contexto de projeto resolvido. Fonte legada: `app/controllers/pub/console_controller.rb:97-122`.

> Nota: corrige o erro por ausencia de projeto padrao (legado: na criacao, se o usuario nao tem projeto padrao, o codigo estoura `NoMethodError`) e o uso de operador bit a bit da linha 115.

#### Scenario: Criacao sem projeto
- **GIVEN** um usuario sem projeto corrente
- **WHEN** ele tenta abrir a criacao de recebivel
- **THEN** a tela pede a selecao de um projeto, sem erro

#### Scenario: Listas do formulario escopadas
- **GIVEN** a criacao de recebivel em um projeto
- **WHEN** o formulario abre
- **THEN** portadores e empresas ofertados sao apenas os do projeto, em ordem alfabetica

### Requirement: BE-403 — Area de renegociacoes
A area de renegociacoes SHALL abrir listagem, detalhe, criacao e edicao, explicando quando a criacao nao e possivel. Fonte legada: `app/controllers/pub/console_controller.rb:123-147`.

> Nota: corrige a falha silenciosa (legado: criar renegociacao em projeto **sem fornecedores** devolve a listagem, **sem nenhuma mensagem** — o usuario clica em criar e simplesmente volta para a lista).

#### Scenario: Projeto sem fornecedores
- **GIVEN** um projeto sem nenhum fornecedor cadastrado
- **WHEN** o usuario tenta criar uma renegociacao
- **THEN** a tela explica que e preciso cadastrar um fornecedor antes, com caminho para faze-lo

### Requirement: BE-404 — Areas de disponibilidade
As areas de padroes de disponibilidade e de disponibilidade SHALL abrir com o contexto de projeto resolvido. Fonte legada: `app/controllers/pub/console_controller.rb:148-155`.

#### Scenario: Contexto de projeto
- **GIVEN** um usuario com projeto corrente definido
- **WHEN** ele abre a area de disponibilidade
- **THEN** a tela carrega no contexto desse projeto

### Requirement: BE-405 — Area de empresas
A area de empresas SHALL abrir listagem e detalhe. Fonte legada: `app/controllers/pub/console_controller.rb:156-160`.

> Nota: corrige o uso de operador bit a bit da linha 156.

#### Scenario: Detalhe de empresa
- **GIVEN** o identificador de uma empresa do projeto corrente
- **WHEN** o detalhe e aberto
- **THEN** os dados da empresa sao exibidos; identificador fora do escopo do usuario responde 403

### Requirement: BE-406 — Area de operacoes de risco
A area de operacoes de risco SHALL abrir a criacao com a cascata de dependencias resolvida — empresa, portador e tipo de operacao — e explicar quando ela nao pode ser satisfeita. Fonte legada: `app/controllers/pub/console_controller.rb:161-190`.

> Nota: corrige o erro por cascata vazia (legado: se nao houver nenhuma empresa com controle ativo, a variavel da primeira empresa fica nula e a linha 168 estoura `NoMethodError`). Registra que os subtipos de operacao de risco estao **desativados por comentario** no codigo.

#### Scenario: Nenhuma empresa com controle ativo
- **GIVEN** um projeto sem nenhuma empresa com controle de risco ativo
- **WHEN** o usuario tenta criar uma operacao de risco
- **THEN** a tela explica o que falta configurar, sem erro

#### Scenario: Cascata coerente
- **GIVEN** a criacao aberta
- **WHEN** o usuario troca a empresa
- **THEN** as opcoes de portador e de tipo de operacao sao recalculadas para a nova empresa

> AMBIGUIDADE: os subtipos de operacao de risco foram desativados no legado. Confirmar com o tech lead se voltam no ai9.

### Requirement: BE-407 — Area de garantias de projeto
A area de garantias de projeto SHALL abrir criacao e edicao com os portadores do projeto correspondente. Fonte legada: `app/controllers/pub/console_controller.rb:191-205`.

#### Scenario: Portadores por projeto
- **GIVEN** a edicao de uma garantia de um projeto
- **WHEN** o formulario abre
- **THEN** os portadores ofertados sao os do projeto do registro, e nao os do projeto corrente do usuario

### Requirement: BE-408 — Area de operacoes estruturadas
A area de operacoes estruturadas SHALL abrir criacao e edicao com a cascata de empresa e portador e os tipos de operacao ativos. Fonte legada: `app/controllers/pub/console_controller.rb:206-235`.

> Nota: registra a divergencia com as operacoes de risco — aqui **nao** ha filtro por controle ativo, ao contrario de BE-406.

#### Scenario: Tipos ativos
- **GIVEN** a criacao aberta
- **WHEN** os tipos de operacao sao ofertados
- **THEN** apenas os tipos ativos aparecem

### Requirement: BE-409 — Area de cobrancas
A area de cobrancas SHALL abrir listagem, detalhe e a tela de recibos. Fonte legada: `app/controllers/pub/console_controller.rb:236-243`.

#### Scenario: Recibos de uma cobranca
- **GIVEN** uma cobranca com recibos
- **WHEN** a tela de recibos e aberta
- **THEN** os recibos daquela cobranca sao listados

### Requirement: BE-410 — Formato de resposta das telas do console
As telas do console SHALL responder com o codigo de status correspondente ao resultado. Fonte legada: `app/controllers/pub/console_controller.rb:249-252`.

> Nota: corrige o status enganoso (legado: a resposta e **sempre 200**, mesmo quando o despacho nao encontrou o registro pedido).

#### Scenario: Registro nao encontrado
- **GIVEN** uma URL de detalhe cujo registro nao existe
- **WHEN** ela e requisitada
- **THEN** a resposta e 404, e nao 200 com tela vazia

### Requirement: BE-411 — Contrato de renderizacao das areas
As areas do console SHALL ser renderizadas por componentes no cliente, a partir de dados. Fonte legada: `app/views/pub/console/base/body.js.erb:1-17`.

> Nota: corrige o padrao de renderizacao do legado, que **e substituido inteiro** (legado: o servidor devolve uma string de JavaScript que limpa um seletor **vindo do cliente e interpolado cru**, renderiza a mesma tela **duas vezes** — uma em HTML para injetar e outra em JavaScript para religar os handlers — e so entao marca o estado do container; ha ainda um ramo de "funcionalidade desativada" que e **codigo morto**, porque a variavel que o dispara nunca e definida).

#### Scenario: Nenhum seletor vindo do cliente
- **GIVEN** uma requisicao com um parametro de destino contendo marcacao
- **WHEN** ela e processada
- **THEN** o valor e tratado como dado e nada e executado

#### Scenario: Renderizacao unica
- **GIVEN** a abertura de uma area
- **WHEN** ela carrega
- **THEN** os dados sao buscados uma unica vez e a tela e montada no cliente

### Requirement: BE-412 — Recarga do seletor de projetos
O console SHALL atualizar a lista de projetos e o projeto corrente apos criacao ou remocao de projeto. Fonte legada: `config/routes.rb:54`; `app/controllers/pub/console_controller.rb:277-281`; `app/views/pub/console/base/handle_projects.js.erb`.

> Nota: corrige a heuristica fragil (legado: quando o usuario do estado de cliente nao e o atual, o codigo apaga o estado e seleciona a **segunda** opcao da lista, heranca de quando havia uma opcao em branco — na pratica seleciona o segundo projeto, nao o primeiro) e o efeito colateral de gravacao em requisicao de leitura, ja tratado em BE-391.

#### Scenario: Troca de usuario
- **GIVEN** um estado de cliente de outro usuario
- **WHEN** a lista de projetos e recarregada
- **THEN** o primeiro projeto do usuario atual e selecionado

#### Scenario: Usuario com um unico projeto
- **GIVEN** um usuario com apenas um projeto
- **WHEN** a topbar e renderizada
- **THEN** o seletor de projetos nao e exibido

### Requirement: BE-413 — Selecao encadeada de pais, estado e cidade
O sistema SHALL oferecer selecao encadeada de pais, estado e cidade nos formularios de endereco. Fonte legada: `app/controllers/pub/console_controller.rb:255-275`.

> Nota: corrige codigo inalcancavel (legado: as duas actions existem mas **nao ha rota para nenhuma delas** — a funcionalidade de selecao encadeada esta morta, e o formulario de endereco de minha conta provavelmente a perdeu em algum momento).

#### Scenario: Encadeamento funciona
- **GIVEN** o formulario de endereco
- **WHEN** o usuario escolhe o pais e depois o estado
- **THEN** as opcoes de estado e depois as de cidade sao carregadas de acordo com a escolha anterior

### Requirement: BE-414 — Autenticacao das areas administrativas
Todas as areas administrativas e seus endpoints SHALL exigir sessao valida. Fonte legada: `app/controllers/pub/console_controller.rb:5-7`; `app/controllers/pub_application_controller.rb:12,38-64`.

> Nota: corrige D-88 e D-57 (legado: **so a casca do console exige login** — os controllers de redirecionador, de mensagens administrativas e de observadores herdam a exigencia como falsa, entao seus endpoints de busca respondem a **anonimos**; e o caminho de usuario desativado responde apenas no formato JavaScript, entao uma requisicao HTML de usuario desativado levanta erro de formato desconhecido).

#### Scenario: Endpoint de busca sem sessao
- **GIVEN** uma requisicao anonima
- **WHEN** ela chama qualquer endpoint de busca das areas administrativas
- **THEN** a resposta e 401 e nenhum dado e retornado

#### Scenario: Usuario desativado durante a navegacao
- **GIVEN** um usuario desativado enquanto usa o console
- **WHEN** ele faz a proxima requisicao, em qualquer formato
- **THEN** ele e desconectado e recebe a tela de conta bloqueada

### Requirement: BE-415 — Protecao contra requisicao forjada
O console SHALL manter a protecao contra requisicao forjada em todas as rotas. Fonte legada: `app/controllers/pub/console_controller.rb:3`.

> Nota: corrige a excecao desnecessaria (legado: a protecao e desligada explicitamente na tela principal; e inocua por ser leitura, mas nao e portada).

#### Scenario: Nenhuma excecao a protecao
- **GIVEN** a configuracao do ai9
- **WHEN** ela e inspecionada
- **THEN** nao ha rota do console com a protecao desligada

### Requirement: BE-416 — Casca da aplicacao e carregamento inicial
A casca do console SHALL exibir um estado de carregamento inicial que **sempre** termina. Fonte legada: `app/controllers/pub_application_controller.rb:2`; `app/views/layouts/preloaded.html.erb:1-143`.

> Nota: corrige o carregamento que pode nunca terminar (legado: uma tela de abertura preta cobre o conteudo e so sai quando o documento reporta carregamento completo, verificado por sondagem a cada dez milissegundos — se algum recurso nunca terminar, **a tela de abertura nunca sai**).

#### Scenario: Recurso que nao carrega
- **GIVEN** um recurso da pagina que nao termina de carregar
- **WHEN** o tempo limite e atingido
- **THEN** a interface e liberada com aviso, em vez de ficar presa na tela de abertura

### Requirement: BE-417 — Raiz da aplicacao
A raiz da aplicacao SHALL levar o usuario autenticado ao console e o anonimo ao login. Fonte legada: `config/routes.rb:242`.

#### Scenario: Anonimo na raiz
- **GIVEN** um visitante sem sessao
- **WHEN** ele acessa a raiz
- **THEN** ele e levado ao login, e apos entrar retorna a raiz

### Requirement: BE-418 — Definicao da navegacao por papel
A navegacao do console SHALL ser definida por configuracao declarativa de grupos, itens, papeis e permissoes. Fonte legada: `app/helpers/application_helper.rb:100-172`.

> Nota: corrige D-118 (legado: a montagem do menu **e a especificacao de fato da navegacao**, escondida em um helper — seis grupos com portao por projeto, por papel e por permissao; o grupo de projeto aparece **vazio** para quem nao tem projeto, porque o cabecalho e adicionado fora do portao). O detalhamento comportamental esta em FE-441 da capability de dominio residual; aqui fica a exigencia de que a navegacao seja configuracao, e nao codigo.

#### Scenario: Navegacao e configuracao
- **GIVEN** a definicao da navegacao do ai9
- **WHEN** ela e inspecionada
- **THEN** grupos, itens, papeis e permissoes estao declarados em configuracao, e a mesma definicao alimenta a interface e a autorizacao no servidor

### Requirement: BE-419 — Areas bloqueadas na navegacao
As areas marcadas como bloqueadas SHALL ser efetivamente inacessiveis. Fonte legada: `app/helpers/application_helper.rb:110,126,127,144`; `app/views/pub/console/base/menu/_container.html.erb:24`.

> Nota: corrige D-90 (legado: a marca de bloqueio e definida nos **itens**, mas a tela le a marca do **grupo**, que nunca existe — o resultado e que **todos** os itens ficam clicaveis, e as quatro areas que deveriam estar bloqueadas — painel de disponibilidade, cobrancas, disponibilidades e padroes de disponibilidade — estao **destravadas**). Registra tambem uma marca de item inativo que nenhum item usa: codigo morto.

#### Scenario: Area bloqueada nao abre
- **GIVEN** uma area marcada como bloqueada
- **WHEN** o usuario tenta abri-la pela navegacao ou digitando a URL
- **THEN** o acesso e recusado nos dois caminhos, com explicacao

#### Scenario: Sinalizacao visivel
- **GIVEN** a navegacao renderizada
- **WHEN** ha areas bloqueadas
- **THEN** elas aparecem visualmente sinalizadas como indisponiveis

### Requirement: BE-420 — Rota de indice do redirecionador
O sistema SHALL nao expor rota de indice do redirecionador sem tela. Fonte legada: `config/routes.rb:24`; `app/controllers/pub/dash_controller.rb:5-8`.

> Nota: corrige D-87 e D-62 (legado: a action renderiza um template que **nao existe** — erro de template ausente; e define uma variavel de depuracao esquecida no codigo).

#### Scenario: Rota morta ausente
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao existe a rota de indice do redirecionador

### Requirement: BE-421 — Rota de detalhe do redirecionador
O sistema SHALL nao expor rota de detalhe do redirecionador sem tela. Fonte legada: `app/controllers/pub/dash_controller.rb:10-12`.

> Nota: corrige D-87 e D-62 (legado: o diretorio de views nao existe).

#### Scenario: Rota morta ausente
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao existe a rota de detalhe do redirecionador

### Requirement: BE-422 — Rota de busca do redirecionador
O sistema SHALL nao expor rota de busca do redirecionador. Fonte legada: `config/routes.rb:23`; `app/controllers/pub/dash_controller.rb:15-25`.

> Nota: corrige D-87 (legado: a action calcula um periodo a partir de parametros de data — sem tratamento de excecao, entao uma data invalida responde 500 — e renderiza um parcial que **nao existe**; **nenhuma agregacao acontece**: o periodo calculado nao alimenta nenhuma consulta). Nao ha feature a preservar: e o vestigio de um dashboard que nunca foi implementado (DEC-09).

#### Scenario: Rota morta ausente
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao existe rota de busca do redirecionador, e nenhuma consulta de agregacao por periodo e criada

### Requirement: BE-423 — Padroes de listagem e teto de paginacao
Os endpoints de listagem do console SHALL aplicar valores padrao de pagina e um **teto** maximo. Fonte legada: `app/controllers/pub/dash_controller.rb:29-42`.

> Nota: corrige D-20 (legado: limite e deslocamento chegam como **texto**, sem conversao, ao contrario de outro controller da mesma area que converte — comportamento divergente entre endpoints; e **nao ha teto**, entao o cliente pode pedir uma pagina arbitrariamente grande).

#### Scenario: Pedido de pagina gigante
- **GIVEN** uma requisicao pedindo um limite muito acima do teto
- **WHEN** ela e processada
- **THEN** o limite e reduzido ao teto configurado

#### Scenario: Parametros ausentes
- **GIVEN** uma requisicao sem limite e sem deslocamento
- **WHEN** ela e processada
- **THEN** os valores padrao sao aplicados de forma identica em todos os endpoints de listagem

### Requirement: BE-424 — Busca de mensagens administrativas
O sistema SHALL listar mensagens de feedback com filtro por situacao e por tipo, busca textual, ordenacao por recencia e **total coerente com os filtros**. Fonte legada: `config/routes.rb:26`; `app/controllers/pub/admin_messages_controller.rb:8-28`.

> Nota: corrige D-91 (legado: o total e a contagem **global**, calculada **antes** dos filtros — a paginacao do cliente usa um total errado sempre que ha filtro ou busca) e a ordenacao (legado: ordena por **nome, alfabetica descendente**, e nao por data, entao a mensagem mais recente nao aparece primeiro). Corrige tambem D-88: o endpoint responde sem sessao.

#### Scenario: Total respeita o filtro
- **GIVEN** 500 mensagens no total e 12 no filtro de situacao escolhido
- **WHEN** a lista e carregada com esse filtro
- **THEN** o total informado e 12, e a navegacao entre paginas se comporta de acordo

#### Scenario: Ordem por recencia
- **GIVEN** mensagens de datas diferentes
- **WHEN** a lista e carregada sem ordenacao explicita
- **THEN** a mais recente aparece primeiro

#### Scenario: Busca vazia
- **GIVEN** um termo de busca em branco
- **WHEN** a lista e carregada
- **THEN** nenhum filtro textual e aplicado — o termo em branco nao e convertido em identificador

### Requirement: BE-425 — Rota de indice de mensagens administrativas
O sistema SHALL nao expor rota de indice de mensagens administrativas sem tela. Fonte legada: `app/controllers/pub/admin_messages_controller.rb:4-6`.

> Nota: corrige D-62 e D-88 (legado: a action e **duplamente morta** — nao ha rota declarada para ela e o diretorio de views tambem nao existe).

#### Scenario: Rota morta ausente
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao existe rota de indice de mensagens administrativas; a tela e servida pela area do console

### Requirement: BE-426 — Busca de observadores
O sistema SHALL listar observadores de feedback **apenas para usuarios com papel administrativo**, com paginacao real. Fonte legada: `config/routes.rb:27`; `app/controllers/pub/console_observers_controller.rb:9-18`.

> Nota: corrige D-88 (legado: o endpoint **lista todos os e-mails de observadores**, le limite e deslocamento mas **nunca os aplica**, **nao verifica papel** e — herdando a exigencia de sessao como falsa — responde **a anonimos**: vazamento de base de e-mails sem autenticacao). Corrige tambem o erro de digitacao na propria URL do legado, `console_observes`.

#### Scenario: Anonimo e recusado
- **GIVEN** uma requisicao sem sessao
- **WHEN** ela chama a lista de observadores
- **THEN** a resposta e 401 e nenhum e-mail e retornado

#### Scenario: Usuario sem papel administrativo
- **GIVEN** um usuario autenticado sem papel administrativo
- **WHEN** ele chama a lista de observadores
- **THEN** a resposta e 403

#### Scenario: Paginacao aplicada
- **GIVEN** 300 observadores cadastrados
- **WHEN** um administrador lista a primeira pagina
- **THEN** apenas o tamanho de pagina pedido e retornado, junto com o total

### Requirement: BE-427 — Formulario de criacao de observador
O sistema SHALL abrir o formulario de criacao de observador. Fonte legada: `config/routes.rb:28`; `app/controllers/pub/console_observers_controller.rb:20-28`.

> Nota: corrige o formato unico (legado: a action so responde no formato JavaScript — uma requisicao HTML levanta erro de formato desconhecido).

#### Scenario: Formulario abre
- **GIVEN** um administrador autenticado
- **WHEN** ele aciona a criacao de observador
- **THEN** o formulario abre em branco, independentemente do formato da requisicao

### Requirement: BE-428 — Formulario de edicao de observador
O sistema SHALL abrir o formulario de edicao com o observador carregado. Fonte legada: `app/controllers/pub/console_observers_controller.rb:3,30-40`.

> Nota: corrige a ausencia de verificacao (legado: a busca aceita o identificador por dois parametros diferentes e **nao trata ausencia** — identificador inexistente deixa o registro nulo e **a tela quebra** ao ler o titulo).

#### Scenario: Observador inexistente
- **GIVEN** o identificador de um observador que nao existe
- **WHEN** a edicao e aberta
- **THEN** a resposta e 404

### Requirement: BE-429 — Gravacao de observador
O sistema SHALL criar, atualizar e remover observadores, exigindo ao menos um tipo de mensagem e notificando o observador por e-mail. Fonte legada: `config/routes.rb:247`; `engines/feedback19/app/controllers/livetat/feedback19/observers_controller.rb:10-118`; `engines/feedback19/lib/livetat/feedback19/notification.rb:10-34`.

> Nota (DEC-11): producao roda Ruby 2.6.1 / Rails 6.0.3.2, entao o caminho de atualizacao com `update_attributes` **funciona** e e feature a preservar. Corrige D-62 na superficie de rotas (legado: o console declara rotas de exibicao, criacao, atualizacao e remocao que **nao existem no seu controller**, resultando em erro de action nao encontrada) e a traducao manual de chaves de erro.

#### Scenario: Ao menos um tipo de mensagem
- **GIVEN** um formulario de observador sem nenhum tipo de mensagem marcado
- **WHEN** ele e enviado
- **THEN** a gravacao e recusada com a mensagem de que ao menos um tipo deve ser selecionado

#### Scenario: E-mail unico
- **GIVEN** um observador ja cadastrado com um e-mail
- **WHEN** outro e criado com o mesmo e-mail
- **THEN** a criacao e recusada por unicidade

#### Scenario: Notificacao ao observador
- **GIVEN** a criacao e depois a remocao de um observador
- **WHEN** cada operacao conclui
- **THEN** o observador recebe o e-mail correspondente, e uma falha de envio nao desfaz nem bloqueia a operacao

#### Scenario: Ultimo editor registrado
- **GIVEN** a atualizacao de um observador
- **WHEN** ela conclui
- **THEN** o registro guarda quem fez a ultima alteracao

### Requirement: FE-390 — Estrutura da casca do console
A casca do console SHALL organizar topbar, navegacao lateral, area de conteudo, gaveta inferior e gaveta lateral, com comportamento responsivo definido por CSS. Fonte legada: `app/views/pub/console/base/_container.html.erb:1-28`; `app/frontend/css/pub/components/console/base.scss`.

> Nota: corrige a dupla verdade de responsividade (legado: uma classe de modo movel e aplicada **no servidor**, a partir de expressao regular sobre o agente do cliente, **junto** com consultas de midia no CSS — duas fontes de verdade que podem discordar) e a injecao de estilo do tema em bloco embutido no fim do container, que inviabiliza politica de seguranca de conteudo estrita.

#### Scenario: Redimensionamento
- **GIVEN** o console aberto em uma janela larga
- **WHEN** a janela e reduzida abaixo do ponto de quebra de tablet
- **THEN** a navegacao lateral vira gaveta imediatamente, sem depender do agente do cliente e sem recarregar a pagina

#### Scenario: Gavetas
- **GIVEN** uma gaveta aberta
- **WHEN** o usuario aciona o fundo escurecido
- **THEN** a gaveta fecha

### Requirement: FE-391 — Tela de abertura e inicializacao
A tela de abertura SHALL cobrir a interface ate que ela esteja pronta, e a area indicada pela URL SHALL abrir em seguida. Fonte legada: `app/views/layouts/preloaded.html.erb:14-116`; `app/views/pub/console/_after.js.erb`; `base/_after.js.erb:1-35`.

> Nota: corrige a ausencia de estado de erro na inicializacao e o comportamento de recuo (legado: se a area indicada pela URL nao existir no menu, a inicializacao cai no redirecionador **em silencio**).

#### Scenario: Area da URL nao existe
- **GIVEN** uma URL apontando para uma area inexistente
- **WHEN** o console inicializa
- **THEN** a tela de nao encontrado e exibida, em vez de um recuo silencioso

#### Scenario: Falha na inicializacao
- **GIVEN** uma falha ao carregar os dados iniciais
- **WHEN** ela ocorre
- **THEN** a tela de abertura sai e um estado de erro com opcao de tentar novamente e exibido

### Requirement: FE-392 — Topbar do console
A topbar SHALL reunir acionamento da navegacao, marca, seletor de projeto, busca global, menu do usuario e indicador de carregamento. Fonte legada: `app/views/pub/console/base/_bar.html.erb:1-67`; `base/_after.js.erb`.

> Nota: corrige o componente orfao (legado: existe no HTML uma faixa de mensagem com acao de aceitar que **nenhum codigo preenche** — provavelmente o vestigio do aceite de contrato, cujo bloco esta comentado no servidor; ver a capability de contratos).

#### Scenario: Indicador de carregamento
- **GIVEN** uma navegacao entre areas
- **WHEN** ela comeca e termina
- **THEN** a topbar mostra e depois esconde o indicador de carregamento

#### Scenario: Nenhum componente sem produtor
- **GIVEN** a topbar renderizada
- **WHEN** ela e inspecionada
- **THEN** nao ha faixa de mensagem sem conteudo que a alimente

### Requirement: FE-393 — Seletor de projeto na topbar
O seletor de projeto SHALL trocar o contexto de projeto e refletir criacao e remocao de projetos. Fonte legada: `app/views/pub/console/base/_bar.html.erb:9-14`, `_bar.js.erb`, `handle_projects.js.erb`.

> Nota: corrige a recarga de pagina inteira como mecanismo de atualizacao (legado: criar o primeiro projeto, remover o ultimo ou remover o projeto selecionado dispara um aviso de dois segundos seguido de **recarga completa da pagina**).

#### Scenario: Troca de projeto
- **GIVEN** o usuario em uma area com um registro aberto
- **WHEN** ele troca o projeto corrente
- **THEN** a area recarrega no contexto do novo projeto, sem recarregar a pagina inteira

#### Scenario: Remocao do projeto selecionado
- **GIVEN** o projeto atualmente selecionado e removido
- **WHEN** a interface reage
- **THEN** outro projeto e selecionado e a area atual e atualizada, sem recarga completa

#### Scenario: Um unico projeto
- **GIVEN** um usuario com apenas um projeto
- **WHEN** a topbar e renderizada
- **THEN** o seletor nao aparece

### Requirement: FE-394 — Busca global da topbar
A busca global SHALL sugerir usuarios conforme a digitacao, apenas para papeis autorizados. Fonte legada: `app/views/pub/console/base/_bar.html.erb:20-44`; `app/views/pub/base/nav/_bar.js.erb:41-162`.

#### Scenario: Estados da busca
- **GIVEN** o campo de busca global
- **WHEN** o usuario digita e o resultado retorna vazio
- **THEN** a sugestao mostra "Nao temos resultados para sua busca"; durante a consulta mostra o estado de carregamento

#### Scenario: Visibilidade por papel
- **GIVEN** um usuario sem papel administrativo, de gestao ou de operador
- **WHEN** a topbar e renderizada
- **THEN** a busca global nao aparece

#### Scenario: Requisicao repetida
- **GIVEN** o usuario digita e apaga voltando ao mesmo termo
- **WHEN** a busca dispara
- **THEN** nenhuma requisicao redundante e feita

### Requirement: FE-395 — Navegacao lateral do console
A navegacao lateral SHALL apresentar grupos expansiveis com seus itens, marcando o item ativo e reagindo ao tamanho da tela. Fonte legada: `app/views/pub/console/base/menu/_container.html.erb`, `_container.js.erb:1-192`.

> Nota: corrige D-90 na interface (legado: os estados visuais de bloqueado e de inativo existem no CSS e **nunca sao aplicados**) e o bloco de "abrir sub-secao padrao ao expandir o grupo", que esta **vazio** no legado, com o atributo correspondente nunca consumido.

#### Scenario: Item ativo
- **GIVEN** uma area aberta
- **WHEN** a navegacao e renderizada
- **THEN** o item correspondente aparece selecionado e seu grupo, expandido

#### Scenario: Fechamento automatico em tela pequena
- **GIVEN** a navegacao em modo gaveta
- **WHEN** o usuario abre um item
- **THEN** a gaveta se fecha

#### Scenario: Estado de bloqueio visivel
- **GIVEN** um item de area bloqueada
- **WHEN** a navegacao e renderizada
- **THEN** o item aparece com o estado de bloqueado aplicado

### Requirement: FE-396 — Resumo do usuario na navegacao
O topo da navegacao SHALL mostrar avatar, nome abreviado e nivel de verificacao do usuario. Fonte legada: `app/views/pub/console/base/resume/_container.html.erb:1-23`.

> Nota: corrige a cor instavel (legado: as iniciais recebem cor **aleatoria a cada renderizacao**, entao a cor "pisca" entre recarregamentos — ver FE-435 da capability de dominio residual) e registra um bloco de contadores que fica **vazio** no legado, alem de um arquivo de comportamento tambem vazio.

#### Scenario: Cor estavel do avatar
- **GIVEN** um usuario sem foto
- **WHEN** a navegacao e renderizada duas vezes
- **THEN** as iniciais tem a mesma cor nas duas

#### Scenario: Nenhum bloco vazio
- **GIVEN** o resumo renderizado
- **WHEN** ele e inspecionado
- **THEN** nao ha area reservada sem conteudo

### Requirement: FE-397 — Area de conteudo e navegacao entre areas
A area de conteudo SHALL carregar cada area com estados de carregamento, vazio e **erro**, atualizando URL e titulo com entrada no historico. Fonte legada: `app/views/pub/console/base/_container.js.erb:1-77`.

> Nota: corrige D-92 (legado: a URL e reescrita **sem criar entrada no historico** — o botao Voltar do navegador **sai do console**) e a falha invisivel (legado: o callback de falha e **vazio**, entao um erro de rede deixa a tela no estado anterior sem nenhum aviso).

#### Scenario: Botao Voltar
- **GIVEN** o usuario navegou por tres areas do console
- **WHEN** ele aciona Voltar
- **THEN** ele retorna a area anterior, dentro do console

#### Scenario: Falha ao carregar a area
- **GIVEN** a requisicao de uma area falha
- **WHEN** a resposta chega
- **THEN** um estado de erro e exibido com opcao de tentar novamente

#### Scenario: Titulo da aba
- **GIVEN** uma area aberta
- **WHEN** ela termina de carregar
- **THEN** o titulo da aba do navegador reflete a area

### Requirement: FE-398 — Estado de navegacao do console
O estado de navegacao SHALL viver no roteador, e o cliente **nao** SHALL receber o registro completo do usuario. Fonte legada: `app/views/pub/console/base/_container.js.erb:79-219`.

> Nota: corrige D-92 e um vazamento (legado: **todo o estado de roteamento vive em memoria** num objeto global, e o registro do usuario e serializado **inteiro** e exposto no escopo global do navegador, com todos os seus atributos; alem disso cada area **pluga funcoes proprias** nesse mesmo objeto global, criando colisao de nomes entre areas).

#### Scenario: Dados do usuario no cliente
- **GIVEN** o console carregado
- **WHEN** o estado exposto ao cliente e inspecionado
- **THEN** ele contem apenas os campos necessarios a interface — nenhum atributo sensivel do registro do usuario

#### Scenario: Estado sobrevive ao recarregamento
- **GIVEN** o usuario em uma area com um registro aberto
- **WHEN** ele recarrega a pagina
- **THEN** a mesma area e o mesmo registro reaparecem, porque o estado esta na URL

### Requirement: FE-399 — Gaveta lateral de formularios
A gaveta lateral SHALL abrigar formularios de criacao e edicao, com estados proprios e fechamento explicito. Fonte legada: `app/views/pub/console/base/helper/_container.html.erb`, `_container.js.erb:1-76`.

> Nota: corrige a busca linear entre containers coexistentes (legado: varios formularios convivem no mesmo elemento e sao alternados por identificador, com varredura linear) e o fechamento automatico a cada navegacao, que pode descartar edicao em andamento.

#### Scenario: Edicao em andamento ao navegar
- **GIVEN** um formulario aberto na gaveta com alteracoes nao salvas
- **WHEN** o usuario navega para outra area
- **THEN** ele e avisado antes de perder as alteracoes

#### Scenario: Rolagem bloqueada
- **GIVEN** a gaveta aberta
- **WHEN** o usuario rola a tela
- **THEN** o conteudo de fundo nao rola

### Requirement: FE-400 — Barra de acoes pendentes
A barra inferior SHALL acumular alteracoes pendentes e permitir salvar ou descartar, executando as acoes em ordem e tratando falhas. Fonte legada: `app/views/pub/console/base/bottom_bar/_container.html.erb`, `_container.js.erb:1-229`.

> Nota: corrige um bug real (legado: no cancelamento, a funcao de recarga e **executada na hora de montar o objeto** em vez de ser passada como funcao — a recarga acontece antes do esperado), a recarga completa da pagina ao final de acoes marcadas para recarregar, e registros de depuracao deixados em producao.

#### Scenario: Falha ao salvar
- **GIVEN** duas alteracoes pendentes, sendo que a segunda falha
- **WHEN** o usuario aciona salvar
- **THEN** a primeira e mantida como salva, a segunda volta a pendencia com o motivo, e os controles voltam a ficar acionaveis

#### Scenario: Descartar alteracoes
- **GIVEN** alteracoes pendentes
- **WHEN** o usuario aciona descartar
- **THEN** as alteracoes sao desfeitas na interface e a barra some, sem recarregar a pagina inteira

#### Scenario: Alteracoes descartadas ao navegar
- **GIVEN** alteracoes pendentes
- **WHEN** o usuario navega para outra area
- **THEN** ele e avisado antes de perde-las — o legado as descartava em silencio

### Requirement: FE-401 — Estados padrao de bloco assincrono
Todo bloco assincrono do console SHALL ter estados de carregamento, vazio e **erro**, com mensagens proprias. Fonte legada: `engines/ux_kit19/app/frontend/util/js/components/builders/*`; `app/frontend/pub_gems/js/helper_builder.js`.

> Nota: corrige a ausencia sistematica de estado de erro (legado: o mecanismo **tem** mensagem de falha, mas os callbacks de falha das secoes desta capability sao **vazios**, entao o estado de erro **nunca e pintado** em lugar nenhum). Registra tambem o cancelamento de requisicao anterior, que evita corrida ao digitar e **deve ser preservado**.

#### Scenario: Erro visivel
- **GIVEN** qualquer bloco assincrono cuja requisicao falhe
- **WHEN** a falha ocorre
- **THEN** o bloco exibe o estado de erro com a sua mensagem e opcao de tentar novamente

#### Scenario: Requisicao obsoleta cancelada
- **GIVEN** o usuario digitando rapidamente em um campo de busca
- **WHEN** as respostas chegam fora de ordem
- **THEN** apenas o resultado do ultimo termo e exibido

### Requirement: FE-402 — Contrato de listagem das areas
As listagens do console SHALL consumir endpoints de dados e renderizar no cliente. Fonte legada: `config/routes.rb:23,26,27` e cerca de trinta e sete rotas de busca identicas; `app/views/pub/console/parts/*/list/body.js.erb`.

> Nota: corrige o contrato universal do legado, que **e substituido inteiro** (legado: o cliente envia um seletor CSS e um modo de destino; o servidor devolve JavaScript que limpa o seletor, injeta HTML item a item e religa os handlers — o **modo de destino e interpolado no caminho do template**, o que abre caminho para travessia de diretorio, e o **seletor e interpolado cru** no codigo).

#### Scenario: Nenhum parametro de cliente vira caminho de arquivo
- **GIVEN** uma requisicao de listagem com um modo de destino contendo segmentos de caminho
- **WHEN** ela e processada
- **THEN** ela e recusada e nenhum arquivo fora do esperado e lido

#### Scenario: Resposta de dados
- **GIVEN** uma listagem qualquer do console
- **WHEN** ela e carregada
- **THEN** a resposta e de dados, e a montagem visual acontece no cliente

### Requirement: FE-403 — Navegacao entre paginas nas listagens
As listagens SHALL oferecer navegacao entre paginas coerente com o total filtrado e com tamanho de pagina configuravel dentro de limites. Fonte legada: `app/views/pub/console/parts/admin_messages/_body.html.erb:14-20`, `_body.js.erb:114-236,374-421`.

> Nota: corrige D-91 e a inconsistencia de configuracao (legado: o tamanho de pagina padrao e cinquenta mas o valor inicial e **cinco**; o campo aceita quatro digitos e **nao tem teto**; e a navegacao depende de um total que, em mensagens administrativas, **ignora os filtros** — a "ultima pagina" erra sempre que ha filtro).

#### Scenario: Ultima pagina com filtro
- **GIVEN** uma lista filtrada
- **WHEN** o usuario aciona "ultima pagina"
- **THEN** ele chega a ultima pagina **do resultado filtrado**

#### Scenario: Tamanho de pagina
- **GIVEN** o campo de tamanho de pagina
- **WHEN** o usuario informa um valor acima do teto
- **THEN** o valor e limitado ao teto e a lista recarrega a partir do inicio

#### Scenario: Valor inicial coerente
- **GIVEN** uma listagem recem-aberta
- **WHEN** ela carrega
- **THEN** o tamanho de pagina inicial e o mesmo valor padrao configurado

### Requirement: FE-404 — Tela de Inicio como redirecionador por papel
A tela de Inicio SHALL encaminhar o usuario para a area adequada ao seu papel e a existencia de projeto. Fonte legada: `app/views/pub/console/parts/dash/_body.html.erb`, `dash/_body.js.erb:8-24`; `app/controllers/pub/dash_controller.rb`.

> Nota de escopo (DEC-09) — **isto e tudo o que o Inicio faz**. Nao ha widget, indicador, periodo, filtro nem agregacao (D-87), e nada disso e criado. Corrige apenas a experiencia de transicao: no legado uma aba "GERAL" e um bloco vazio chegam a ser pintados por um instante antes de serem descartados.

#### Scenario: Papel de operacao geral
- **GIVEN** um usuario com papel de operacao geral
- **WHEN** ele abre o Inicio
- **THEN** ele e levado a area de usuarios

#### Scenario: Papel administrativo ou de gestao
- **GIVEN** um usuario administrador ou gestor
- **WHEN** ele abre o Inicio
- **THEN** ele e levado a area de projetos quando nao tem nenhum projeto, e a area de recebiveis quando tem

#### Scenario: Demais papeis
- **GIVEN** um usuario de outro papel
- **WHEN** ele abre o Inicio
- **THEN** ele e levado a sua conta quando nao tem projeto, e a area de resultados quando tem

#### Scenario: Sem conteudo intermediario
- **GIVEN** o encaminhamento acontecendo
- **WHEN** a tela e observada
- **THEN** nenhum conteudo descartavel e exibido no caminho

### Requirement: FE-405 — Tela de mensagens administrativas
A tela SHALL apresentar as mensagens de feedback com busca, filtros e paginacao, ao lado da lista de observadores. Fonte legada: `app/views/pub/console/parts/admin_messages/_body.html.erb:1-53`.

> Nota: corrige D-88 e D-92 (legado: a secao **nao tem entrada no menu** e a URL que ela grava **nao e navegavel** — recarregar a pagina nesse ponto leva o usuario ao redirecionador; e as mensagens de falha existem mas **nunca sao exibidas**).

#### Scenario: Acesso pelo menu
- **GIVEN** um administrador autenticado
- **WHEN** ele abre a navegacao
- **THEN** existe uma entrada para mensagens administrativas

#### Scenario: Recarregar mantem a tela
- **GIVEN** a tela aberta com filtros aplicados
- **WHEN** o usuario recarrega a pagina
- **THEN** a mesma tela reabre com os mesmos filtros

#### Scenario: Estados da lista
- **GIVEN** a lista de mensagens
- **WHEN** ela carrega, volta vazia, volta vazia para uma busca, ou falha
- **THEN** cada estado tem a sua mensagem propria, inclusive o de falha

### Requirement: FE-406 — Item de mensagem administrativa
Cada mensagem SHALL exibir remetente, contato, tipo, situacao, corpo e recencia, com as acoes efetivamente disponiveis. Fonte legada: `app/views/pub/console/parts/admin_messages/list/_widget.html.erb:1-66`, `_widget.js.erb`.

> Nota: corrige a acao decorativa (legado: o botao de responder apenas exibe um aviso de que "a funcionalidade faz parte de um modulo que nao esta habilitado" — botao puramente decorativo) e os campos extras de nome inadequado, chamados no legado de `hadouken` e `shoryuken`, que sao na verdade **campos personalizaveis com rotulo configuravel**. Registra tambem selos de estado que existem no CSS e **nenhum HTML usa**.

#### Scenario: Nenhuma acao indisponivel e anunciada
- **GIVEN** um item de mensagem
- **WHEN** as acoes sao exibidas
- **THEN** so aparecem acoes implementadas

#### Scenario: Campos personalizados
- **GIVEN** uma mensagem com campos personalizados habilitados
- **WHEN** ela e exibida
- **THEN** cada campo aparece com o seu rotulo configurado, com nomes de dominio e nao de codinome

#### Scenario: Remocao
- **GIVEN** uma mensagem
- **WHEN** o administrador confirma a remocao
- **THEN** ela e removida e a lista atualiza, com mensagem de sucesso ou de falha conforme o resultado

### Requirement: FE-407 — Busca e filtros de mensagens administrativas
A tela SHALL filtrar por situacao e por tipo e buscar por texto, reiniciando a paginacao a cada mudanca. Fonte legada: `app/views/pub/console/parts/admin_messages/_body.js.erb:338-372`.

> Nota: corrige o deslocamento nao reiniciado (legado: trocar de filtro **nao zera** a posicao da pagina, entao e possivel ficar em uma pagina que nao existe no novo resultado).

#### Scenario: Troca de filtro na pagina 5
- **GIVEN** o usuario na quinta pagina de resultados
- **WHEN** ele muda um filtro
- **THEN** a lista volta para a primeira pagina do novo resultado

#### Scenario: Busca so com espacos
- **GIVEN** um termo composto apenas de espacos
- **WHEN** a busca dispara
- **THEN** nenhum filtro textual e aplicado

### Requirement: FE-408 — Lista de observadores
A lista de observadores SHALL exibir nome e contato com as acoes de editar e remover, com URLs navegaveis. Fonte legada: `app/views/pub/console/parts/admin_messages/observers/list/_widget.html.erb`, `_widget.js.erb:1-75`.

> Nota: corrige D-92 (legado: as URLs gravadas ao abrir a edicao e a criacao **nao existem como rota** — recarregar nelas leva o usuario ao redirecionador).

#### Scenario: Deep-link de edicao
- **GIVEN** a URL de edicao de um observador
- **WHEN** ela e aberta diretamente
- **THEN** o formulario de edicao abre com o observador carregado

#### Scenario: Remocao
- **GIVEN** um observador
- **WHEN** o administrador confirma a remocao
- **THEN** ele e removido, a lista atualiza e a mensagem de resultado e exibida

### Requirement: FE-409 — Formulario de observador
O formulario de observador SHALL editar nome, contato, recebimento de mensagens internas e os tipos de mensagem, abrindo com o registro correto. Fonte legada: `app/views/pub/console/parts/admin_messages/observers/helper/_body.html.erb:1-70`, `_mount.js.erb:1-128`, `handle.js.erb`.

> Nota: corrige D-91 (legado: o codigo que abre a edicao grava o identificador em um campo chamado `companyId` enquanto o consumidor le `observerId` — a URL montada fica com o identificador indefinido e **a edicao por esse caminho nao abre**). Corrige tambem a mensagem de estado vazio com concordancia errada, "Essa observador nao pode ser alterada".

#### Scenario: Abrir edicao pelo item da lista
- **GIVEN** um observador na lista
- **WHEN** o administrador aciona editar
- **THEN** o formulario abre com os dados desse observador

#### Scenario: Tipos de mensagem
- **GIVEN** o formulario aberto
- **WHEN** os tipos de mensagem sao exibidos
- **THEN** ha uma opcao por tipo cadastrado, e ao menos uma precisa ser marcada para salvar

#### Scenario: Erros do servidor
- **GIVEN** um envio invalido
- **WHEN** a resposta de erro chega
- **THEN** cada erro e exibido junto ao campo correspondente, com rotulo em pt-BR

### Requirement: FE-410 — Sistema de notificacao da interface
A interface SHALL ter um mecanismo unico de notificacao com os tipos sucesso, erro e confirmacao. Fonte legada: `app/views/pub/console/base/_container.js.erb:141-155,176-190`; `bottom_bar/_container.js.erb:171-186`.

#### Scenario: Confirmacao com acao
- **GIVEN** uma acao destrutiva
- **WHEN** ela e acionada
- **THEN** uma confirmacao e exibida e a acao so ocorre apos resposta afirmativa

#### Scenario: Notificacao acessivel
- **GIVEN** uma notificacao exibida
- **WHEN** um leitor de tela esta em uso
- **THEN** o conteudo e anunciado, e notificacoes nao fechaveis tem duracao limitada

### Requirement: FE-411 — Componente reutilizavel: botao de acao
A biblioteca de componentes SHALL fornecer um botao de acao com variantes de intencao, forma e tamanho, e estados de repouso, foco, sobrevoo, ativo, carregando e desabilitado. Fonte legada: `app/frontend/css/pub/recyclable/button.scss:1-285`.

> Nota: consolida as variantes do legado — redondo, de calendario, transparente, de destaque, verde, auxiliar, inverso, adicionar, remover, recarregar e voltar, mais combinacoes e modificadores de espacamento — em um unico componente com API de variantes. Registra que o botao de voltar **esconde o rotulo** abaixo de 480 pixels.

#### Scenario: Variantes de intencao
- **GIVEN** o botao de acao
- **WHEN** as variantes de destaque, neutra, auxiliar e destrutiva sao usadas
- **THEN** cada uma tem tratamento visual proprio, com contraste adequado nos modos claro e escuro

#### Scenario: Estado de carregamento
- **GIVEN** um botao em carregamento
- **WHEN** o usuario o aciona de novo
- **THEN** nenhuma acao adicional dispara, e o estado e anunciado a tecnologias assistivas

#### Scenario: Estado desabilitado
- **GIVEN** um botao desabilitado
- **WHEN** o usuario navega por teclado
- **THEN** ele nao recebe foco de acao e o motivo do bloqueio esta disponivel

### Requirement: FE-412 — Componente reutilizavel: botao de formulario
A biblioteca SHALL fornecer um botao de formulario com indicador de progresso embutido e variantes de cor. Fonte legada: `app/frontend/css/pub/recyclable/button.scss:334+`; uso em `base/helper/_container.html.erb` e `base/bottom_bar/_container.html.erb`.

> Nota: consolida as variantes do legado — redonda, inversa, de destaque, auxiliar, de rede social e destrutiva — e substitui o indicador de progresso com cor aplicada por estilo embutido.

#### Scenario: Progresso durante o envio
- **GIVEN** um formulario sendo enviado
- **WHEN** o envio esta em andamento
- **THEN** o botao mostra progresso e fica indisponivel ate a resposta

#### Scenario: Cor pelo tema
- **GIVEN** o botao em qualquer variante
- **WHEN** o tema muda
- **THEN** as cores vem dos tokens do tema, sem estilo embutido no elemento

### Requirement: FE-413 — Componente reutilizavel: indicador direcional
A biblioteca SHALL fornecer um indicador direcional com as orientacoes anterior e proximo. Fonte legada: `app/frontend/css/pub/recyclable/button.scss:287-332`.

#### Scenario: Orientacoes
- **GIVEN** o indicador direcional
- **WHEN** as orientacoes anterior e proximo sao usadas
- **THEN** cada uma aponta corretamente e tem rotulo acessivel

### Requirement: FE-414 — Componente reutilizavel: cartao de detalhe
A biblioteca SHALL fornecer um cartao de detalhe com titulo, linhas de rotulo e valor, linhas acionaveis e blocos de destaque. Fonte legada: `app/frontend/css/pub/recyclable/card.scss:1-193`.

> Nota: corrige a divergencia de convencao de nomes (legado: este componente usa uma convencao de modificadores diferente da do resto do projeto — duas convencoes convivendo). Variantes registradas: plano, compacto, em linha; estados: linha acionavel, linha desabilitada e linha destrutiva.

#### Scenario: Linha acionavel e desabilitada
- **GIVEN** um cartao com linhas acionaveis
- **WHEN** uma delas esta desabilitada
- **THEN** ela nao responde a acionamento e o estado e visualmente distinto

#### Scenario: Valores de destaque
- **GIVEN** um cartao com blocos de valor
- **WHEN** eles usam as variantes neutra, positiva, auxiliar e de selo
- **THEN** cada uma tem tratamento proprio e legivel nos dois modos de tema

### Requirement: FE-415 — Componente reutilizavel: cartao de listagem
A biblioteca SHALL fornecer um cartao de listagem com cabecalho, campos de resumo, selo, indicador de progresso e area acionavel. Fonte legada: `app/frontend/css/pub/recyclable/card.scss:195+`.

> Nota: corrige o indicador de progresso fragil (legado: o preenchimento e escolhido por **seletor de atributo com valor de texto exato**, formatado no servidor — qualquer mudanca de formatacao quebra a barra em silencio).

#### Scenario: Progresso em qualquer valor
- **GIVEN** um cartao com progresso de 37,5 por cento
- **WHEN** ele e renderizado
- **THEN** a barra reflete o valor proporcionalmente, sem depender de formatacao de texto

#### Scenario: Area acionavel
- **GIVEN** um cartao com area acionavel
- **WHEN** o usuario navega por teclado
- **THEN** a area recebe foco visivel e responde a acionamento por teclado

### Requirement: FE-416 — Componente reutilizavel: tabela
A biblioteca SHALL fornecer uma tabela com cabecalho, linhas, tipos de coluna e comportamento responsivo **legivel**. Fonte legada: `app/frontend/css/pub/recyclable/table.scss:1-109`.

> Nota: corrige a perda de semantica em tela pequena (legado: abaixo de 600 pixels o cabecalho e as linhas simplesmente **empilham, sem rotulo por celula** — a tabela perde a correspondencia entre valor e coluna e fica ilegivel).

#### Scenario: Tela estreita
- **GIVEN** uma tabela em tela estreita
- **WHEN** ela e renderizada
- **THEN** cada valor continua identificado pelo seu rotulo de coluna

#### Scenario: Conteudo largo
- **GIVEN** uma tabela mais larga que a area disponivel
- **WHEN** ela e renderizada
- **THEN** ela rola horizontalmente dentro do proprio container, sem rolar a pagina

#### Scenario: Tipos de coluna
- **GIVEN** colunas de data, compactas, largas e de acao
- **WHEN** a tabela e renderizada
- **THEN** cada tipo tem alinhamento e largura adequados

### Requirement: FE-417 — Componente reutilizavel: campo de selecao
A biblioteca SHALL fornecer um campo de selecao estilizado com marcador proprio, texto de espaco reservado e estados de foco, erro e desabilitado. Fonte legada: `app/frontend/css/pub/recyclable/select.scss:1-42`.

> Nota: corrige a solucao fragil do legado (a aparencia nativa **nao e removida** e o marcador e desenhado **por cima** do controle nativo, o que quebra conforme o navegador).

#### Scenario: Aparencia consistente
- **GIVEN** o campo de selecao
- **WHEN** ele e renderizado em navegadores diferentes
- **THEN** a aparencia e a mesma, sem sobreposicao de marcadores

#### Scenario: Estados
- **GIVEN** o campo em foco, com erro e desabilitado
- **WHEN** cada estado e aplicado
- **THEN** ele e visualmente distinto e comunicado a tecnologias assistivas

### Requirement: FE-418 — Componente reutilizavel: caixa de selecao e opcao unica
A biblioteca SHALL fornecer caixa de selecao e opcao unica com estados de repouso, sobrevoo, foco, marcado, indeterminado e desabilitado. Fonte legada: `app/frontend/css/pub/recyclable/checkbox.scss:1-102`.

> Nota: corrige duas propriedades invalidas no legado — uma diretiva de pre-processador que virou texto literal — que fazem **as transicoes nao funcionarem**.

#### Scenario: Estados completos
- **GIVEN** a caixa de selecao
- **WHEN** cada estado e aplicado
- **THEN** todos sao visualmente distintos, inclusive o indeterminado, que o legado nao tinha

#### Scenario: Acionamento por teclado
- **GIVEN** a caixa de selecao com foco
- **WHEN** o usuario aciona pelo teclado
- **THEN** o estado alterna e a mudanca e anunciada

### Requirement: FE-419 — Componente reutilizavel: alternador
A biblioteca SHALL fornecer um alternador com estados ligado, desligado, foco, pressionado, carregando e desabilitado. Fonte legada: `app/frontend/css/pub/recyclable/switches.scss:1-84`.

> Nota: corrige uma propriedade definida e **nunca aplicada** no legado (a escala do estado pressionado). Registra que as cores vem dos tokens de destaque do tema.

#### Scenario: Estado de carregamento
- **GIVEN** um alternador cuja mudanca depende do servidor
- **WHEN** o usuario o aciona
- **THEN** ele mostra carregamento e so assume o novo estado apos a confirmacao; em falha, volta ao estado anterior com aviso

#### Scenario: Rotulo acessivel
- **GIVEN** um alternador
- **WHEN** um leitor de tela o encontra
- **THEN** o rotulo e o estado atual sao anunciados

### Requirement: FE-420 — Componente reutilizavel: campo de busca
A biblioteca SHALL fornecer um campo de busca com icone, texto de espaco reservado, acao de limpar e estados de foco, carregando e desabilitado. Fonte legada: `app/frontend/css/pub/recyclable/search.scss:1-123`.

> Nota: corrige a largura fixa do legado, que impede o campo de se adaptar ao container, e a ausencia de acao de limpar. Variantes registradas: embutido em barra, isolado, e com botoes de acao adjacentes separados por divisor.

#### Scenario: Limpar a busca
- **GIVEN** um termo digitado
- **WHEN** o usuario aciona limpar
- **THEN** o campo esvazia, o foco permanece nele e a lista volta ao estado sem filtro

#### Scenario: Largura adaptavel
- **GIVEN** o campo dentro de containers de larguras diferentes
- **WHEN** eles sao renderizados
- **THEN** o campo se adapta a cada largura

### Requirement: FE-421 — Componente reutilizavel: sugestoes de busca
A biblioteca SHALL fornecer uma lista de sugestoes ancorada ao campo, com estados de carregando, vazio, erro e item destacado, navegavel por teclado. Fonte legada: `app/frontend/css/pub/recyclable/search.scss:125-204`.

> Nota: corrige o dimensionamento por numero magico (legado: a altura maxima e um valor fixo comentado como "numero magico" calibrado para exatamente cinco itens) e a duplicacao de cerca de quarenta linhas de estilo dentro de uma consulta de midia.

#### Scenario: Navegacao por teclado
- **GIVEN** a lista de sugestoes aberta
- **WHEN** o usuario usa as setas e confirma
- **THEN** o item destacado e selecionado, e a tecla de escape fecha a lista

#### Scenario: Quantidade variavel de itens
- **GIVEN** listas de tres e de vinte sugestoes
- **WHEN** cada uma e exibida
- **THEN** a altura se ajusta ate um maximo, com rolagem interna

### Requirement: FE-422 — Componente reutilizavel: item de resultado de busca
A biblioteca SHALL fornecer um item de resultado com icone, titulo, descricao opcional, estado de carregando por item e variante de acao rapida. Fonte legada: `app/frontend/css/pub/recyclable/generic_search.scss:1-84`.

#### Scenario: Carregando por item
- **GIVEN** um item cuja selecao dispara uma operacao
- **WHEN** ele e selecionado
- **THEN** apenas aquele item mostra progresso, e os demais permanecem acionaveis

#### Scenario: Acao rapida
- **GIVEN** uma sugestao de acao rapida
- **WHEN** a lista e exibida
- **THEN** ela e visualmente distinta dos resultados comuns

### Requirement: FE-423 — Componente reutilizavel: abas
A biblioteca SHALL fornecer abas com estados selecionado, sobrevoo, foco e desabilitado, com rolagem quando nao couberem. Fonte legada: `app/frontend/css/pub/recyclable/app_tabs.scss:1-58`; `app/views/pub/base/_tabs.html.erb`, `_tabs.js.erb:1-48`.

> Nota: corrige a colisao de escopo global (legado: cada secao que renderiza abas **sobrescreve** a mesma funcao global de troca de aba, e o parcial de interface ainda define outras funcoes globais de filtro — colisao entre secoes).

#### Scenario: Aba inicial
- **GIVEN** um conjunto de abas
- **WHEN** ele e montado
- **THEN** a primeira aba fica selecionada, sem simular um acionamento do usuario

#### Scenario: Dois conjuntos de abas na mesma tela
- **GIVEN** duas areas com abas na mesma tela
- **WHEN** o usuario troca a aba de uma delas
- **THEN** a outra nao e afetada

#### Scenario: Abas que nao cabem
- **GIVEN** mais abas do que a largura comporta
- **WHEN** elas sao renderizadas
- **THEN** o conjunto rola horizontalmente com indicacao de que ha mais

### Requirement: FE-424 — Componente reutilizavel: painel de aba
A biblioteca SHALL fornecer o painel de conteudo de aba, com apenas um painel visivel por vez e transicao de entrada. Fonte legada: `app/frontend/css/pub/recyclable/app_tabs.scss:60-71`; sobrescrita em `components/dash/base.scss:26-33`.

> Nota: corrige a implementacao concorrente (legado: a mesma classe tem **duas implementacoes** — uma por visibilidade e opacidade, outra por exibicao — e a segunda sobrescreve a primeira apenas na tela de Inicio).

#### Scenario: Uma unica implementacao
- **GIVEN** paineis de aba em telas diferentes
- **WHEN** eles sao renderizados
- **THEN** todos usam o mesmo comportamento de exibicao e transicao

#### Scenario: Conteudo oculto nao e lido
- **GIVEN** um painel nao selecionado
- **WHEN** um leitor de tela percorre a pagina
- **THEN** o conteudo oculto nao e anunciado

### Requirement: FE-425 — Componente reutilizavel: selo
A biblioteca SHALL fornecer um selo com variantes de intencao e a opcao de ser removivel. Fonte legada: `app/frontend/css/pub/recyclable/app_badge.scss:1-34`.

> Nota: corrige a cor fixa (legado: a cor base e um valor fixo que **nao vem do tema**), e o legado tinha apenas as variantes preenchida e contornada.

#### Scenario: Variantes de intencao
- **GIVEN** selos neutro, informativo, de sucesso, de alerta e de erro
- **WHEN** eles sao renderizados
- **THEN** cada um vem dos tokens do tema, com contraste adequado nos dois modos

#### Scenario: Selo removivel
- **GIVEN** um selo removivel
- **WHEN** o usuario aciona a remocao pelo teclado
- **THEN** o selo e removido e o foco vai para um destino previsivel

### Requirement: FE-426 — Componente reutilizavel: dica de contexto
A biblioteca SHALL fornecer uma dica de contexto com as quatro posicoes e acionamento por sobrevoo e por foco. Fonte legada: `app/frontend/css/pub/recyclable/app_tooltip.scss:1-44`.

> Nota: corrige dois defeitos visuais do legado — um raio de borda **sem unidade**, propriedade invalida e ignorada pelo navegador, e a cor da seta que **nao bate** com a cor do corpo da dica.

#### Scenario: Acionamento por teclado
- **GIVEN** um elemento com dica de contexto
- **WHEN** ele recebe foco pelo teclado
- **THEN** a dica aparece e e anunciada

#### Scenario: Posicionamento
- **GIVEN** um elemento proximo da borda da janela
- **WHEN** a dica abre
- **THEN** ela se reposiciona para permanecer visivel, com a seta apontando para o elemento

### Requirement: FE-427 — Componente reutilizavel: avatar
A biblioteca SHALL fornecer um avatar por imagem ou iniciais, com tamanhos configuraveis e cor deterministica. Fonte legada: `app/frontend/css/pub/recyclable/avatar.scss:1-37`; `app/views/pub/base/_avatar_or_initials.html.erb`.

> Nota: registra que este e o **unico** componente do legado que ja usa propriedade personalizada para tamanho — no ai9 todos passam a usar tokens. Corrige a cor aleatoria das iniciais (ver FE-396 e FE-435).

#### Scenario: Sem imagem
- **GIVEN** um usuario sem foto
- **WHEN** o avatar e renderizado
- **THEN** as iniciais aparecem com cor derivada da identidade do usuario, estavel entre renderizacoes

#### Scenario: Imagem que falha ao carregar
- **GIVEN** um avatar cuja imagem nao carrega
- **WHEN** a falha ocorre
- **THEN** ele recai para as iniciais, sem area quebrada

### Requirement: FE-428 — Componente reutilizavel: indicador de progresso
A biblioteca SHALL fornecer **um unico** indicador de progresso, com tamanhos e variantes de cor. Fonte legada: `app/frontend/css/pub/recyclable/loader.scss:1-53`.

> Nota: corrige a duplicacao (legado: convivem **duas implementacoes de indicador de progresso** no mesmo produto — a propria e a da biblioteca de terceiros usada nos containers e nos botoes de formulario).

#### Scenario: Implementacao unica
- **GIVEN** as telas do ai9
- **WHEN** elas exibem progresso
- **THEN** todas usam o mesmo componente

#### Scenario: Anuncio de carregamento
- **GIVEN** um indicador de progresso visivel
- **WHEN** um leitor de tela o encontra
- **THEN** o estado de carregamento e anunciado uma unica vez

### Requirement: FE-429 — Componentes reutilizaveis auxiliares
A biblioteca SHALL fornecer avaliacao por estrelas, visualizador de imagens em tela cheia e estilos de titulo, carregados apenas onde sao usados. Fonte legada: `app/frontend/css/pub/recyclable/generic_rating.scss`, `photo_swipe.scss`, `comp.scss`; `app/views/pub/console/index.html.erb:34`.

> Nota: corrige o carregamento incondicional (legado: o visualizador de imagens e incluido na casca do console **sempre**, mesmo em telas sem imagem) e registra a decisao tipografica global do legado de forcar **minusculas** nos titulos.

#### Scenario: Carregamento sob demanda
- **GIVEN** uma area sem imagens
- **WHEN** ela e aberta
- **THEN** o visualizador de imagens nao e carregado

#### Scenario: Avaliacao por estrelas
- **GIVEN** o componente de avaliacao
- **WHEN** o usuario navega por teclado
- **THEN** ele consegue definir a nota e o valor atual e anunciado

#### Scenario: Estilos de titulo
- **GIVEN** os titulos da interface
- **WHEN** eles sao renderizados
- **THEN** a caixa aplicada e uma decisao de estilo declarada em tokens, e o texto original permanece inalterado para leitores de tela

### Requirement: DB-390 — Modelo de dados de mensagem de feedback
A tabela de mensagens SHALL guardar remetente, contato, corpo, situacao, tipo, campos personalizados e marcadores de leitura, com tipos adequados e indices. Fonte legada: `engines/feedback19/db/migrate/*create_feedback_messages*`; `engines/feedback19/app/models/livetat/feedback19/message.rb`.

> Nota: corrige o modelo (legado: **nenhum indice declarado** em situacao, tipo, usuario, contato nem nos tokens; campos logicos como inteiros; o corpo e uma coluna de texto curto enquanto a validacao permite o dobro — **truncamento silencioso**; e os tokens sao gerados em laco com verificacao de colisao, sem indice unico). Corrige tambem os nomes dos campos personalizados, que no legado sao codinomes sem relacao com o dominio.

#### Scenario: Corpo longo
- **GIVEN** uma mensagem no tamanho maximo permitido pela validacao
- **WHEN** ela e gravada
- **THEN** o conteudo e preservado integralmente

#### Scenario: Token unico
- **GIVEN** um token de mensagem ja existente
- **WHEN** outro igual e inserido
- **THEN** o banco recusa por indice unico

### Requirement: DB-391 — Modelo de dados de observador
A tabela de observadores SHALL guardar nome, contato, criador, ultimo editor e a marca de recebimento de mensagens internas, com contato unico no banco. Fonte legada: `engines/feedback19/db/migrate/20170505211325_create_livetat_feedback_observers.rb`.

> Nota: corrige o modelo (legado: **sem indices**, inclusive **sem indice unico no contato** — a unicidade e so de aplicacao) e registra um campo morto: existe no banco, tem valor padrao e **nao e exposto em nenhuma tela nem aceito nos parametros**.

#### Scenario: Contato unico
- **GIVEN** um observador com um contato
- **WHEN** outra linha com o mesmo contato e inserida
- **THEN** o banco recusa por indice unico

#### Scenario: Campo morto ausente
- **GIVEN** o esquema do ai9
- **WHEN** ele e inspecionado
- **THEN** o campo sem uso do legado nao existe

### Requirement: DB-392 — Modelo de dados da ligacao observador e tipo de mensagem
A tabela de ligacao SHALL ligar observador e tipo de mensagem com indice unico e chaves estrangeiras. Fonte legada: `engines/feedback19/db/migrate/20170505225555_create_livetat_feedback_observer_contexts.rb`.

> Nota: corrige a condicao de corrida (legado: a prevencao de duplicata e feita por uma **contagem a cada gravacao**, sem indice unico — gravacoes concorrentes duplicam a ligacao).

#### Scenario: Ligacao duplicada
- **GIVEN** uma ligacao entre um observador e um tipo
- **WHEN** outra igual e inserida
- **THEN** o banco recusa por indice unico

### Requirement: DB-393 — Catalogo de tipos de mensagem
Os tipos de mensagem SHALL ser um catalogo semeado e resolvido em tempo de execucao. Fonte legada: `engines/feedback19/db/migrate/20170505214502_create_livetat_feedback_contexts.rb`; `.../context.rb`.

> Nota: corrige uma **armadilha de migracao** (legado: o model resolve os registros do catalogo em constantes **no carregamento da classe** — em um banco vazio essas constantes ficam nulas e a criacao de mensagem estoura `NoMethodError`; o seed e obrigatorio antes do primeiro uso) e as cores fixadas por identificador dentro do codigo.

#### Scenario: Banco sem seed
- **GIVEN** uma instalacao nova sem o catalogo semeado
- **WHEN** uma mensagem e criada
- **THEN** o erro e claro sobre o catalogo ausente, e nao um erro por objeto nulo

#### Scenario: Catalogo semeado
- **GIVEN** o seed executado
- **WHEN** o catalogo e consultado
- **THEN** ele contem os tipos do legado: Outros, Problema, Contato e Sugestao

### Requirement: DB-394 — Catalogo de situacoes de mensagem
As situacoes de mensagem SHALL ser um conjunto estavel de valores, com as situacoes finais identificadas. Fonte legada: `engines/feedback19/db/migrate/20170505143940_create_livetat_feedback_states.rb`; `.../state.rb`.

> Nota: corrige a mesma armadilha de resolucao em tempo de carregamento de DB-393 e um nome escrito errado no codigo do legado. Situacoes registradas: lido, nao lido, aberto, avaliado, respondido, concluido, fechado e rejeitado; as tres ultimas sao finais.

#### Scenario: Situacao final
- **GIVEN** uma mensagem em situacao concluida, fechada ou rejeitada
- **WHEN** a situacao e avaliada
- **THEN** ela e identificada como final

### Requirement: DB-395 — Modelo de dados das respostas de mensagem
A tabela de respostas SHALL guardar o texto, o autor, a mensagem de origem e a marca de nao lida. Fonte legada: `engines/feedback19/db/migrate/20170516185759_create_livetat_feedback_notes.rb`; `20181005020904_add_unread_to_note.rb`.

> Nota: registra que toda mensagem cria automaticamente a **primeira resposta** e que os campos de citacao aninhada **nunca sao preenchidos** pela interface do console — a tela de resposta esta desabilitada (FE-406). Registra tambem o limite de cinco respostas anonimas em trinta minutos, e a ausencia de indices.

#### Scenario: Primeira resposta automatica
- **GIVEN** uma mensagem recem-criada
- **WHEN** ela e gravada
- **THEN** a primeira resposta correspondente existe, ja marcada como lida

#### Scenario: Limite de respostas anonimas
- **GIVEN** cinco respostas anonimas nos ultimos trinta minutos
- **WHEN** uma sexta e tentada
- **THEN** ela e recusada

### Requirement: DB-396 — Persistencia do contexto de navegacao
O contexto de navegacao SHALL viver na URL e no token de sessao, **nao** em cookie escrito pelos dois lados. Fonte legada: `app/controllers/pub/console_controller.rb:286-302`; `app/views/pub/console/base/_container.js.erb:96-98,160-163`.

> Nota: corrige D-92 e a divergencia de codificacao (legado: o mesmo cookie e escrito **pelo servidor e pelo cliente com codificacoes diferentes**, guarda apenas o projeto e nao a area, vale quatro dias e **nao tem marcas de seguranca** — nem restrito a HTTP, nem restrito a conexao segura, nem restrito a mesma origem).

#### Scenario: Nenhum cookie de estado sem protecao
- **GIVEN** os cookies emitidos pelo ai9
- **WHEN** eles sao inspecionados
- **THEN** todos tem as marcas de seguranca adequadas e nenhum e escrito pelos dois lados

#### Scenario: Contexto na URL
- **GIVEN** o usuario em uma area de um projeto
- **WHEN** ele compartilha a URL com outro usuario que tem acesso
- **THEN** o outro usuario abre exatamente a mesma area e o mesmo projeto

### Requirement: DB-397 — Projeto padrao do usuario
O projeto padrao do usuario SHALL ser alterado apenas por acao deliberada. Fonte legada: `app/controllers/pub/console_controller.rb:307-310`.

> Nota: corrige a gravacao implicita (legado: o campo e **escrito em requisicoes de leitura**, a cada requisicao do console em que divergir do cookie, e e a fonte de verdade do projeto para todos os formularios de criacao).

#### Scenario: Troca deliberada
- **GIVEN** um usuario que troca o projeto corrente pelo seletor
- **WHEN** a troca conclui
- **THEN** o projeto padrao dele muda; navegar por areas nao muda o projeto padrao

### Requirement: DB-398 — Fonte das cores da interface
As cores dos componentes SHALL vir de **uma unica** fonte de tokens de tema. Fonte legada: `app/models/app_theme.rb:200,218-231`; `app/views/pub/console/base/_container.html.erb:28`.

> Nota: corrige a dupla fonte de cor (legado: existe uma coluna de CSS pre-computado injetada em bloco embutido **e** as cores compiladas no CSS estatico — duas fontes; e o CSS pre-computado fica desatualizado ate o tema ser gravado de novo). A coluna de cache **nao e portada** — ver a capability de temas.

#### Scenario: Troca de tema
- **GIVEN** o tema padrao alterado
- **WHEN** um usuario abre a interface
- **THEN** as cores refletem o tema imediatamente, sem depender de reprocessar cache

#### Scenario: Nenhum estilo embutido no documento
- **GIVEN** qualquer pagina do console
- **WHEN** o documento e inspecionado
- **THEN** nao ha bloco de estilo gerado em tempo de renderizacao

### Requirement: DB-399 — Ausencia de modelo de dados de dashboard
O sistema SHALL nao ter modelo de dados nem rotina de agregacao para dashboard. Fonte legada: `app/controllers/pub/dash_controller.rb:1-43`; `app/views/pub/console/parts/dash/**`.

> Nota de escopo (DEC-09 / D-87): **nao existe** nenhum model, view materializada ou rotina que alimente indicadores de dashboard no legado. A busca do redirecionador calcula um periodo e **nao consulta nada**. Nao ha paridade a preservar e nada e criado.

#### Scenario: Nenhuma estrutura de dashboard
- **GIVEN** o esquema e as tarefas agendadas do ai9
- **WHEN** eles sao inspecionados
- **THEN** nao ha tabela, view materializada nem rotina de agregacao para dashboard

### Requirement: OPS-390 — Empacotamento dos recursos do console
Os recursos do console SHALL ser empacotados sem expor componentes no escopo global do navegador. Fonte legada: `app/views/layouts/preloaded.html.erb:120-121`; `app/frontend/pub_gems/js/index.js.erb`.

> Nota: corrige a exposicao global (legado: o framework de componentes, construtores e proxies e carregado como **variaveis globais** no navegador, o que sustenta o padrao de colisao de nomes descrito em FE-398 e FE-423).

#### Scenario: Nenhum global
- **GIVEN** o console carregado
- **WHEN** o escopo global do navegador e inspecionado
- **THEN** nao ha componentes de aplicacao expostos nele

### Requirement: OPS-391 — Analytics
O console SHALL carregar analytics apenas com consentimento e por configuracao de ambiente. Fonte legada: `app/views/pub/console/_index.js.erb:1`; identificador em `SFG::Metadata::GOOGLE_ANA_APP_ID`.

> Nota: corrige o identificador embutido em codigo (legado: o identificador de analytics e uma **constante de codigo**, nao configuracao) e a ausencia de consentimento.

#### Scenario: Sem consentimento
- **GIVEN** um usuario que nao consentiu com analytics
- **WHEN** ele usa o console
- **THEN** nenhum script de analytics e carregado

### Requirement: OPS-392 — Cookies emitidos pelo console
Os cookies emitidos SHALL ter marcas de seguranca e prazo declarados. Fonte legada: `app/views/pub/console/base/_container.js.erb:160-163`; `app/controllers/pub/console_controller.rb:292,302`.

> Nota: corrige D-92 e a ausencia de marcas (legado: o cookie de contexto vale quatro dias e **nao tem** restricao a HTTP, a conexao segura nem a mesma origem).

#### Scenario: Inventario de cookies
- **GIVEN** os cookies do ai9
- **WHEN** eles sao inspecionados
- **THEN** cada um tem prazo, restricao a HTTP quando aplicavel, restricao a conexao segura e politica de mesma origem

### Requirement: OPS-393 — Historico do navegador
Toda navegacao entre areas SHALL criar entrada no historico do navegador. Fonte legada: `app/views/pub/console/base/_container.js.erb:15-19`; usos em mensagens administrativas e observadores.

> Nota: corrige D-92 (legado: a URL e reescrita **sem criar entrada no historico**, em toda navegacao e em toda abertura de gaveta — o botao Voltar sai do console).

#### Scenario: Historico completo
- **GIVEN** o usuario navegou por cinco areas
- **WHEN** ele aciona Voltar cinco vezes
- **THEN** ele percorre as cinco areas na ordem inversa antes de sair do console

### Requirement: OPS-394 — Notificacao por e-mail aos observadores
O sistema SHALL notificar observadores por e-mail na inclusao, na remocao e na chegada de mensagem do tipo que eles acompanham. Fonte legada: `engines/feedback19/lib/livetat/feedback19/notification.rb:10-60+`; `observers_controller.rb:20,70`.

> Nota: registra a regra de filtro do legado — observadores que **nao** recebem mensagens internas sao **pulados** quando a mensagem e interna.

#### Scenario: Mensagem interna
- **GIVEN** uma mensagem marcada como interna e observadores com e sem recebimento de mensagens internas
- **WHEN** a notificacao e disparada
- **THEN** apenas os que recebem mensagens internas sao notificados

#### Scenario: Falha de envio
- **GIVEN** o servico de e-mail indisponivel
- **WHEN** um observador e criado
- **THEN** a criacao conclui, a falha de envio e registrada e reprocessada

### Requirement: OPS-395 — Personificacao de usuario
O sistema SHALL permitir a papeis autorizados agir no contexto de outro usuario, com registro de auditoria e saida explicita. Fonte legada: `app/controllers/pub_application_controller.rb:18-20`; `config/routes.rb:12,14,17,18`; busca global em FE-394.

> Nota: corrige a ausencia de sinalizacao e de auditoria (legado: a busca global **e** o seletor de personificacao, e nao ha indicacao permanente na interface de que o usuario esta personificando).

#### Scenario: Indicacao permanente
- **GIVEN** um administrador personificando outro usuario
- **WHEN** ele navega
- **THEN** a interface indica de forma permanente quem esta sendo personificado, com acao de sair

#### Scenario: Auditoria
- **GIVEN** qualquer acao realizada durante a personificacao
- **WHEN** ela e registrada
- **THEN** o registro identifica tanto o usuario personificado quanto o administrador

### Requirement: OPS-396 — Recursos de desenvolvimento
Recursos de desenvolvimento SHALL nao aparecer em producao. Fonte legada: `app/views/pub/console/base/_container.html.erb:22-26`.

#### Scenario: Ambiente de producao
- **GIVEN** o console em producao
- **WHEN** ele e renderizado
- **THEN** nenhum controle de desenvolvimento aparece

### Requirement: OPS-397 — Host publico nas URLs da navegacao
Os links absolutos da navegacao SHALL usar configuracao validada na inicializacao. Fonte legada: `app/views/pub/console/base/menu/_container.html.erb:37,40`.

> Nota: corrige a dependencia silenciosa, a mesma de OPS-331 na capability de contratos (legado: se a variavel de ambiente do host publico nao estiver definida, os links de termos de uso e politica de privacidade ficam quebrados, sem aviso).

#### Scenario: Configuracao ausente
- **GIVEN** o host publico nao configurado
- **WHEN** a aplicacao inicia
- **THEN** a inicializacao falha com mensagem clara

### Requirement: OPS-398 — Aplicacao do tema no console
O tema SHALL ser aplicado sem estilo gerado em tempo de renderizacao. Fonte legada: `app/views/pub/console/base/_container.html.erb:28`.

> Nota: corrige a injecao de estilo embutido (legado: o CSS do tema e injetado em bloco embutido no fim do container, o que **inviabiliza politica de seguranca de conteudo estrita** e deixa a paleta desatualizada quando o cache do tema esta velho).

#### Scenario: Politica de seguranca de conteudo
- **GIVEN** o console em producao
- **WHEN** a politica de seguranca de conteudo e aplicada com restricao de origem para estilos
- **THEN** nenhuma tela quebra

### Requirement: OPS-399 — Ausencia de codigo executavel embutido
As paginas do console SHALL nao conter codigo executavel embutido nem avaliar codigo vindo de resposta de rede. Fonte legada: `app/views/layouts/preloaded.html.erb:10,138-141`.

> Nota: corrige a raiz do problema (legado: **todo o carregamento inicial do console** roda em bloco de codigo embutido gerado no servidor, e **cada navegacao avalia codigo vindo por requisicao assincrona** — nenhuma politica de seguranca restritiva e possivel hoje).

#### Scenario: Politica restritiva ativa
- **GIVEN** uma politica de seguranca de conteudo sem permissao para codigo embutido nem avaliacao dinamica
- **WHEN** o console e usado em todas as areas
- **THEN** nenhuma funcionalidade quebra

### Requirement: FE-740 — Componente reutilizavel: barra de contexto
A biblioteca SHALL fornecer uma barra de contexto com titulo, acao de voltar, indicador de progresso, area de mensagem, busca embutida e acoes contextuais. Fonte legada: `app/frontend/js/toolbars.js:1-751`; exportado em `app/frontend/js/index.js.erb:9-13,33-35`.

> Nota: e o componente de interface mais pesado do legado depois do menu — 751 linhas — e **nenhum identificador do inventario apontava para o arquivo** antes do cruzamento com o grafo. Corrige o acoplamento a medidas em pixels calculadas em codigo e a exposicao no escopo global; no ai9 e um componente com consultas de container.

#### Scenario: Variantes
- **GIVEN** as variantes de barra de contexto, barra simples e barra de busca
- **WHEN** cada uma e usada
- **THEN** ela expoe apenas os elementos da sua variante

#### Scenario: Colapso na rolagem
- **GIVEN** uma barra configurada para colapsar
- **WHEN** o usuario rola a pagina
- **THEN** ela colapsa e expande conforme a direcao da rolagem; configurada para nao colapsar, permanece fixa

#### Scenario: Adaptacao ao container
- **GIVEN** a barra em containers de larguras diferentes
- **WHEN** eles sao renderizados
- **THEN** o layout se adapta por CSS, sem calculo de largura em codigo

> AMBIGUIDADE: quais telas usam qual variante nao esta mapeado. Confirmar tela a tela antes de consolidar a API do componente.

### Requirement: FE-741 — Componente reutilizavel: menu de navegacao
A biblioteca SHALL fornecer o menu de navegacao com item ativo derivado da rota corrente. Fonte legada: `app/frontend/js/simple_menu.js:1-112`; render em `app/views/pub/console/base/menu/_container.html.erb`.

> Nota: corrige a resolucao do item ativo por comparacao de texto de URL (legado: o estado ativo e resolvido comparando a URL corrente com o destino de cada item) — no ai9 isso vem do roteador. E o par de comportamento da definicao de navegacao de BE-418.

#### Scenario: Item ativo por rota
- **GIVEN** uma area aberta por deep-link
- **WHEN** o menu e renderizado
- **THEN** o item correspondente aparece ativo, inclusive em sub-rotas da area

### Requirement: FE-742 — Utilitarios de interface do cliente
Os utilitarios de interface SHALL ter uma unica implementacao de formatacao de data e de montagem de endereco, compartilhada com o servidor. Fonte legada: `app/frontend/js/helpers.js:1-237`; globais em `app/frontend/js/index.js.erb:15-26,36-44`.

> Nota: corrige a duplicacao (legado: a formatacao de data em pt-BR existe **no cliente e no servidor**, com implementacoes independentes; o mesmo vale para a montagem de endereco, par de BE-436) e a exposicao no escopo global. Registra um utilitario que **injeta scripts em tempo de execucao**, cuja origem precisa ser verificada.

#### Scenario: Formatacao consistente
- **GIVEN** a mesma data formatada no servidor e no cliente
- **WHEN** as duas sao exibidas
- **THEN** o resultado e identico

#### Scenario: Nenhum script carregado em tempo de execucao
- **GIVEN** o console em uso
- **WHEN** as requisicoes de rede sao inspecionadas
- **THEN** nenhum script e injetado dinamicamente a partir de origem externa

### Requirement: FE-743 — Componente reutilizavel: dialogo
A biblioteca SHALL fornecer um dialogo com titulo, mensagem, variantes de intencao e botoes configuraveis. Fonte legada: `vendor/dialog/index.js:1-94`, `template.js`, `style.js`.

> Nota de escopo (DEC-10): o componente proprietario do legado — sem equivalente publico, trazendo o proprio HTML e o proprio CSS injetado — e **substituido pela lib de dialogo do ai9**, nao portado um para um. O que se preserva e o comportamento: e o dialogo por tras de **todas as confirmacoes de exclusao do console**.

#### Scenario: Variantes de intencao
- **GIVEN** as variantes de erro, informacao e alerta
- **WHEN** cada uma e exibida
- **THEN** ela tem tratamento visual proprio e anuncio adequado

#### Scenario: Confirmacao de exclusao
- **GIVEN** uma acao de exclusao
- **WHEN** o dialogo abre
- **THEN** ele descreve o que sera perdido e so executa apos confirmacao explicita

#### Scenario: Teclado e foco
- **GIVEN** o dialogo aberto
- **WHEN** o usuario navega por teclado
- **THEN** o foco fica preso no dialogo, a tecla de escape cancela e o foco retorna ao elemento de origem ao fechar

### Requirement: FE-744 — Componente reutilizavel: grafico de rosca
A biblioteca SHALL fornecer um grafico de rosca com series, legenda, valor central acionavel e interacao por ponteiro. Fonte legada: `vendor/doughnut/src/doughnut.js:1-657` e modulos irmaos.

> Nota de escopo (DEC-10): e o **unico grafico do produto** no legado, um componente proprietario sem equivalente publico. Ele e **substituido pela lib de graficos do ai9**, nao portado. A paridade a garantir e a **semantica das series, a paleta padrao e o acionamento do valor central** — nao o codigo. O resultado visual e mostrado antes de fechar o slice.

#### Scenario: Series e legenda
- **GIVEN** um conjunto de series com rotulos e valores
- **WHEN** o grafico e renderizado
- **THEN** cada serie aparece proporcional ao seu valor, com legenda correspondente e as cores da paleta padrao

#### Scenario: Valor central acionavel
- **GIVEN** o grafico com valor central
- **WHEN** o usuario o aciona
- **THEN** a acao associada dispara, tambem por teclado

#### Scenario: Interacao por serie
- **GIVEN** o grafico renderizado
- **WHEN** o usuario aponta ou aciona uma serie
- **THEN** a serie e destacada e a acao associada dispara

#### Scenario: Sem dados
- **GIVEN** nenhum dado para o grafico
- **WHEN** ele e renderizado
- **THEN** um estado vazio explicito e exibido

### Requirement: FE-745 — Localizacao do seletor de datas
O seletor de datas SHALL apresentar dias, meses e acoes em pt-BR, no formato dia/mes/ano, com a semana comecando no domingo. Fonte legada: `app/frontend/vendor/js/datepicker_overrides.js:1-11`.

> Nota: corrige as abreviacoes com acento faltando no legado e registra que este arquivo, do qual **dezenas de telas dependem**, nao era apontado por nenhum identificador do inventario antes do cruzamento com o grafo. E o par visual do formato de troca de datas de FE-440 na capability de dominio residual.

#### Scenario: Formato e idioma
- **GIVEN** qualquer campo de data do console
- **WHEN** o seletor abre
- **THEN** dias e meses aparecem em pt-BR corretamente acentuados, a semana comeca no domingo e a data escolhida e exibida como dia/mes/ano

#### Scenario: Entrada digitada
- **GIVEN** o usuario digitando a data diretamente no campo
- **WHEN** ele informa uma data no formato dia/mes/ano
- **THEN** ela e interpretada corretamente, sem ambiguidade com o formato mes/dia/ano
