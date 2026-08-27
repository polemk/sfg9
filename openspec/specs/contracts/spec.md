# Contracts Specification

## Purpose
Documentos juridicos do produto (Termos de Uso e Politicas de Privacidade): publicacao versionada com conteudo rico, paginas publicas de leitura, registro de aceite por usuario, calculo de pendencia e o bloqueio de acesso associado.

> Nota de escopo (DEC-09): so o que existe no legado. Nao ha assinatura eletronica, nao ha contrato por projeto e nao ha exclusao de contrato — nada disso e inventado aqui. i18n fica fora (D-115): pt-BR fixo.
> Alerta juridico registrado (D-64 / D-65 / OPS-334): no legado o fluxo de aceite esta **morto por tres motivos independentes** e o aceite real e **implicito** no `after_create` do usuario. As decisoes marcadas AMBIGUIDADE nesta capability tem consequencia juridica e precisam do tech lead antes da implementacao.

## Requirements

### Requirement: BE-330 — Pagina publica do contrato
O sistema SHALL servir uma pagina publica de leitura por tipo de contrato, acessivel sem sessao. Fonte legada: `app/controllers/pub/contracts_controller.rb:2-13`; rota `config/routes.rb:48`.

> Nota: corrige D-69 (legado: `:redirect_url` chega como segmento de path, sem validacao nem allowlist, e o JS faz `goForwardSafely(redirect_url)` — open redirect; alem disso o valor e interpolado direto no JS, o que e tambem XSS refletido, ver FE-334). No ai9 o destino de retorno so e aceito se estiver em allowlist interna e nunca e interpolado em codigo.

#### Scenario: Leitura sem sessao
- **GIVEN** um visitante anonimo
- **WHEN** ele abre a pagina de um contrato pelo tipo
- **THEN** o texto vigente e exibido, sem exigir login

#### Scenario: Destino de retorno externo
- **GIVEN** uma URL de contrato com um destino de retorno apontando para um host externo
- **WHEN** o usuario conclui a leitura
- **THEN** o destino e recusado e o retorno cai na rota interna padrao

### Requirement: BE-331 — Resolucao do contrato vigente pelo tipo
O sistema SHALL resolver o contrato vigente de um tipo pela **maior versao publicada**, e responder 404 para tipo desconhecido. Fonte legada: `app/controllers/pub/contracts_controller.rb:4`; `app/models/contract.rb:13-14`.

> Nota: corrige a resolucao por id (legado: `Contract.where("kind ILIKE LOWER(?)", params[:type]).last` ordena por **`id`**, nao por `version` — versoes criadas fora de ordem servem a versao errada) e o 500 sem 404 (legado: tipo desconhecido deixa `@contract` nil e a linha 7 estoura `nil.kind`).

#### Scenario: Versao vigente e a maior
- **GIVEN** um tipo com as versoes 1, 2 e 3 publicadas, sendo a 2 a de maior `id` por ter sido re-salva
- **WHEN** a pagina publica desse tipo e aberta
- **THEN** a versao 3 e exibida

#### Scenario: Tipo desconhecido
- **GIVEN** uma URL com um tipo de contrato que nao existe
- **WHEN** ela e aberta
- **THEN** a resposta e 404 com pagina de nao encontrado, nunca erro interno

> AMBIGUIDADE: no legado o tipo viaja na URL como string em portugues com espacos e com typo consolidado (`Termos de Uso`, `Politicas de Privacidade` — sem acento em "Politicas"), e essas URLs existem em links externos. Confirmar com o tech lead se o ai9 adota slug (`termos-de-uso`) com redirect permanente das URLs antigas, ou preserva a string literal.

### Requirement: BE-332 — Calculo do sinalizador de aceitabilidade
O sistema SHALL determinar se o contrato exibido esta pendente de aceite para o usuario da sessao. Fonte legada: `app/controllers/pub/contracts_controller.rb:6-10`; `app/decorators/models/user_decorator.rb:40`.

> Nota: corrige D-64 na raiz tecnica (legado: `is_pending` -> `pending_contracts` -> `self.contracts`, e a associacao e declarada como `has_many :contracts, through: :contract_deals, source: :contract_deal` — `source: :contract_deal` **nao existe** em `ContractDeal`, a correta e `:contract` — entao **qualquer usuario logado que abra `/contract/:type` sem passar `:acceptable` explicitamente recebe 500**).

#### Scenario: Usuario logado com pendencia
- **GIVEN** um usuario que aceitou a versao 1 e existe a versao 2 publicada
- **WHEN** ele abre a pagina do contrato
- **THEN** a pagina carrega e indica que ha aceite pendente

#### Scenario: Anonimo
- **GIVEN** um visitante sem sessao
- **WHEN** ele abre a pagina do contrato
- **THEN** a pagina carrega em modo somente leitura, sem sinalizar aceite

### Requirement: BE-333 — Registrar o aceite de contrato
O sistema SHALL registrar o aceite de um contrato pelo usuario da sessao, com trilha de auditoria. Fonte legada: `app/controllers/pub/contracts_controller.rb:15-26`; rota `config/routes.rb:47`; `app/models/contract_deal.rb:9`.

> Nota: corrige D-68 (legado: `ContractDeal.create(contract_deal_params)` usa o `user_id` **do params** e so **depois** sobrescreve com `current_user.id` e salva de novo — o primeiro `create` pode persistir um aceite em nome de outro usuario; e `id` tambem esta no `permit`, permitindo sobrescrita por id forjado) e o 500 por sessao ausente (legado: `current_user` nil estoura `NoMethodError`, pois o controller nao exige sessao). Corrige tambem o template de resposta `pub/contracts/parts/handle.js.erb`, arquivo **vazio de 0 bytes**, que fazia o aceite nao ter efeito visivel na tela.

#### Scenario: Aceite e sempre do usuario da sessao
- **GIVEN** um payload de aceite contendo `user_id` de outro usuario e um `id` forjado
- **WHEN** a requisicao e processada
- **THEN** os dois campos sao ignorados e o registro criado pertence ao usuario da sessao

#### Scenario: Aceite exige sessao
- **GIVEN** uma requisicao de aceite sem sessao
- **WHEN** ela e processada
- **THEN** a resposta e 401 e nada e gravado

#### Scenario: Aceite duplicado
- **GIVEN** um usuario que ja aceitou a versao vigente
- **WHEN** ele envia o aceite de novo
- **THEN** a operacao e idempotente e nenhum registro duplicado e criado

#### Scenario: So a versao vigente e aceitavel
- **GIVEN** um payload apontando para uma versao antiga do mesmo tipo
- **WHEN** ele e processado
- **THEN** a operacao e recusada — o legado nao validava isso e permitia aceitar versao antiga

### Requirement: BE-334 — Lista de contratos no console
O sistema SHALL listar os contratos no console mostrando a versao mais recente de cada tipo, com busca e paginacao coerentes. Fonte legada: `app/controllers/pub/contracts_controller.rb:28-54`; rota `config/routes.rb:30`.

> Nota: corrige D-20 nesta capability (legado: o `limit`/`offset` e aplicado **antes** do filtro em Ruby que mantem so a versao mais alta de cada tipo, entao a pagina 2 pode vir vazia havendo contratos e um contrato cuja ultima versao caiu fora da janela **some da lista**) e o filtro por lista fixa (legado: `@availabe_kinds` — typo do proprio legado — vem de `Contract.contract_kinds`, entao contratos com `kind` fora dos dois literais **nunca aparecem no console**, ficando invisiveis e ineditaveis).

#### Scenario: Paginacao correta com agrupamento por tipo
- **GIVEN** 3 tipos de contrato com muitas versoes cada
- **WHEN** o administrador abre a lista
- **THEN** aparece exatamente uma linha por tipo, com a versao mais recente, e o total informado e o numero de tipos — nenhuma pagina vem vazia por efeito do filtro

#### Scenario: Contrato de tipo inesperado continua visivel
- **GIVEN** um contrato gravado com um tipo fora do conjunto conhecido
- **WHEN** a lista e aberta
- **THEN** ele aparece, sinalizado como tipo desconhecido, em vez de desaparecer silenciosamente

### Requirement: BE-335 — Publicar nova versao de contrato
O sistema SHALL publicar uma nova versao de contrato, restrita a papel administrativo, preservando as versoes anteriores. Fonte legada: `app/controllers/pub/contracts_controller.rb:56-68`; rota `config/routes.rb:31`; `app/models/contract.rb:11`.

> Nota: corrige a ausencia total de autorizacao (legado: **nenhuma verificacao de papel** — qualquer usuario logado podia publicar um novo Termos de Uso) e o mass assignment (legado: `id` e `version` estao no `permit`, ainda que `version` seja sobrescrito pelo `version_guess`).

#### Scenario: Publicacao exige papel administrativo
- **GIVEN** um usuario autenticado sem papel administrativo
- **WHEN** ele tenta publicar uma nova versao
- **THEN** a resposta e 403 e nada e criado

#### Scenario: Versoes anteriores sao imutaveis
- **GIVEN** um tipo com a versao 1 publicada
- **WHEN** uma nova versao e publicada
- **THEN** um registro novo e criado, a versao 1 permanece intacta e legivel, e nao ha rota de edicao ou exclusao de versao publicada

#### Scenario: Autor da versao
- **GIVEN** um administrador publicando
- **WHEN** a versao e criada
- **THEN** o criador registrado e o usuario da sessao, ignorando qualquer criador enviado no payload

### Requirement: BE-336 — Numeracao automatica de versao
O sistema SHALL atribuir o numero de versao **apenas na criacao**, como sucessor da maior versao existente do mesmo tipo. Fonte legada: `app/models/contract.rb:2,50-53`.

> Nota: corrige o versionamento acidental (legado: `version_guess` roda em **todo `save`**, nao so no create — re-salvar um contrato existente **incrementa a versao dele** e pode colidir com a unicidade; alem disso `.last` ordena por **`id`**, nao por `version`, entao o "ultimo" pode ter numero menor e gerar versao duplicada; nao ha transacao nem garantia de sequencia sem buracos).

#### Scenario: Numeracao na criacao
- **GIVEN** um tipo cuja maior versao publicada e 4
- **WHEN** uma nova versao e publicada
- **THEN** ela recebe o numero 5

#### Scenario: Re-salvar nao renumera
- **GIVEN** uma versao ja publicada
- **WHEN** qualquer operacao de gravacao a toca (por exemplo, correcao de metadado permitida)
- **THEN** o numero de versao permanece o mesmo

#### Scenario: Publicacoes concorrentes
- **GIVEN** duas publicacoes simultaneas do mesmo tipo
- **WHEN** ambas sao processadas
- **THEN** elas recebem numeros distintos e consecutivos, garantido pelo banco

### Requirement: BE-337 — Unicidade de tipo e versao
O sistema SHALL garantir no banco que nao existam duas versoes com o mesmo numero para o mesmo tipo, e SHALL exigir tipo e versao presentes. Fonte legada: `app/models/contract.rb:8-9`; `db/migrate/20180405163859_create_contracts.rb`.

> Nota: corrige a garantia apenas na aplicacao (legado: `validates_uniqueness_of :kind, scope: [:version]` **sem indice unico no banco** — duas publicacoes simultaneas geram versoes duplicadas) e a ausencia de validacao de presenca (legado: so `title` tinha `validates presence`, entao era possivel criar contrato com `kind` nulo, que depois nunca aparecia na busca).

#### Scenario: Duplicata recusada pelo banco
- **GIVEN** a versao 2 de um tipo ja gravada
- **WHEN** outra linha com o mesmo par tipo e versao e inserida
- **THEN** o banco recusa por indice unico

#### Scenario: Tipo obrigatorio
- **GIVEN** uma tentativa de criar contrato sem tipo
- **WHEN** ela e processada
- **THEN** a operacao e rejeitada com erro de campo obrigatorio

### Requirement: BE-338 — Pre-preenchimento da nova versao
O sistema SHALL pre-preencher o formulario de nova versao com titulo, conteudo e tipo da versao anterior. Fonte legada: `app/models/contract.rb:31-39`; uso em `app/controllers/pub/console_controller.rb:32-37`.

> Nota: corrige a chamada sem guarda (legado: `where(kind:).last.version + 1` estoura `nil.version` se nao houver nenhum contrato do tipo; nao acontecia na pratica so porque o metodo sempre partia de um contrato existente).

#### Scenario: Copia do conteudo anterior
- **GIVEN** um tipo com a versao 3 publicada
- **WHEN** o administrador inicia uma nova versao
- **THEN** o formulario abre com o titulo e o conteudo rico da versao 3 e o tipo travado

#### Scenario: Primeiro contrato de um tipo
- **GIVEN** um tipo sem nenhuma versao publicada
- **WHEN** o administrador inicia a primeira versao
- **THEN** o formulario abre vazio, sem erro

### Requirement: BE-339 — Tipos de contrato suportados
O sistema SHALL suportar os tipos de contrato do legado — Termos de Uso e Politicas de Privacidade — como catalogo declarado. Fonte legada: `app/models/contract.rb:13-21`; formulario `app/views/pub/console/parts/contracts/new_version/_body.html.erb:12`.

#### Scenario: Catalogo fechado
- **GIVEN** o formulario de nova versao
- **WHEN** o administrador escolhe o tipo
- **THEN** apenas os tipos declarados sao ofertados e o tipo nao e editavel apos a criacao

> AMBIGUIDADE: no legado nao ha UI para criar um tipo novo — o tipo e literal em codigo e adicionar um terceiro exige mudanca de codigo. Existe ainda o arquivo `db/seed_assets/contracts/user.html` (OPS-332), um terceiro documento que nenhum seed carrega, sugerindo um "contrato de adesao" planejado e nunca ativado. Confirmar com o tech lead se o ai9 deve permitir tipos configuraveis.

### Requirement: BE-340 — Aceite no cadastro do usuario
O sistema SHALL registrar o aceite dos contratos vigentes no momento do cadastro do usuario, a partir de consentimento **explicito**. Fonte legada: `app/decorators/models/user_decorator.rb:2,234-240`; `app/models/contract.rb:55-61`.

> Nota: corrige D-64 (legado: `after_create :create_contracts` grava os dois aceites **automaticamente**, sem qualquer interacao — os checkboxes de sign-up `contract[tou_agreed]` e de Minha Conta `contract[agreed_by_user]` **nao sao lidos por nenhum controller** e servem apenas de gate visual; se nao houver contrato cadastrado, o metodo e no-op e o usuario fica sem nenhum aceite).

#### Scenario: Consentimento lido pelo servidor
- **GIVEN** um cadastro publico com a caixa de aceite desmarcada
- **WHEN** o formulario e submetido
- **THEN** o servidor recusa o cadastro por falta de consentimento — a checagem nao depende do cliente

#### Scenario: Aceite gravado com o cadastro
- **GIVEN** um cadastro com o consentimento marcado
- **WHEN** o usuario e criado
- **THEN** sao registrados os aceites das versoes vigentes de cada tipo, com a trilha de auditoria de BE-333

#### Scenario: Sem contrato publicado
- **GIVEN** uma instalacao sem nenhuma versao de contrato publicada
- **WHEN** um usuario e criado
- **THEN** o cadastro conclui e o usuario fica com aceite pendente assim que a primeira versao for publicada

> AMBIGUIDADE: D-64 — o aceite hoje e implicito e automatico, com **consequencia juridica** (o sistema registra um aceite que o usuario nunca deu conscientemente). A decisao entre reativar o aceite explicito ou assumir o implicito e de produto **e juridica**, nao tecnica, e precisa do tech lead.

### Requirement: BE-341 — Calculo de contratos pendentes
O sistema SHALL calcular, para um usuario, quais tipos de contrato tem versao vigente ainda nao aceita. Fonte legada: `app/decorators/models/user_decorator.rb:188-217`.

> Nota: corrige D-64 e o N+1 (legado: todo esse caminho passa por `self.contracts`, associacao quebrada por `source: :contract_deal` — **os metodos levantam excecao**; e `pending_contracts` faz `self.contracts.where(kind:).last` dentro do loop). Corrige tambem a consequencia nao obvia: no legado, os tipos considerados vem apenas do que o usuario **ja aceitou alguma vez**, entao um usuario que nunca aceitou um tipo (contrato criado depois da conta) **nunca ficava pendente** dele.

#### Scenario: Contrato publicado depois da conta
- **GIVEN** um usuario criado antes de existir qualquer versao de Politicas de Privacidade
- **WHEN** a primeira versao desse tipo e publicada
- **THEN** o usuario passa a constar como pendente desse tipo

#### Scenario: Nova versao reabre a pendencia
- **GIVEN** um usuario que aceitou a versao 1 de um tipo
- **WHEN** a versao 2 e publicada
- **THEN** o usuario volta a constar como pendente daquele tipo

#### Scenario: Consulta sem N+1
- **GIVEN** um usuario com aceites em varios tipos
- **WHEN** a pendencia e calculada
- **THEN** o numero de consultas ao banco nao cresce com o numero de tipos

### Requirement: BE-342 — Janela de tolerancia de contrato pendente
O sistema SHALL considerar um contrato pendente como expirado apos 30 dias corridos da publicacao da versao. Fonte legada: `app/decorators/models/user_decorator.rb:219-232`.

#### Scenario: Dentro da tolerancia
- **GIVEN** uma versao publicada ha 10 dias e nao aceita pelo usuario
- **WHEN** a pendencia e avaliada
- **THEN** ela consta como pendente, mas nao expirada

#### Scenario: Fora da tolerancia
- **GIVEN** uma versao publicada ha 31 dias e nao aceita pelo usuario
- **WHEN** a pendencia e avaliada
- **THEN** ela consta como expirada

> AMBIGUIDADE: a regra de 30 dias e a **unica** politica de prazo do modulo e hoje esta inerte, porque o bloqueio que a consumia esta comentado (BE-343). Confirmar com o tech lead se o prazo se mantem, muda ou some.

### Requirement: BE-343 — Bloqueio de acesso por contrato pendente expirado
O sistema SHALL redirecionar o usuario com contrato pendente expirado para a pagina de aceite, sem laco de redirecionamento. Fonte legada: `app/controllers/pub_application_controller.rb:55-63`.

> Nota: corrige D-64 (legado: o bloqueio esta **inteiramente comentado** — hoje **nao existe bloqueio algum** e o usuario navega normalmente com contratos pendentes ou expirados; o bloco comentado cobria apenas requests HTML e comparava `request.original_url` com `ENV['alias'] + pub_contracts_path(kind)` para evitar loop).

#### Scenario: Usuario com pendencia expirada
- **GIVEN** um usuario com contrato pendente expirado
- **WHEN** ele acessa qualquer tela autenticada
- **THEN** ele e levado a pagina de aceite daquele contrato

#### Scenario: Sem laco de redirecionamento
- **GIVEN** o mesmo usuario ja na pagina de aceite
- **WHEN** a pagina carrega
- **THEN** nenhum redirecionamento adicional ocorre

#### Scenario: Chamadas de API
- **GIVEN** o mesmo usuario
- **WHEN** um cliente faz uma chamada de API
- **THEN** a resposta indica a pendencia de forma explicita, em vez de redirecionar

> AMBIGUIDADE: D-64 — reativar o bloqueio e o comportamento **pretendido** pelo codigo, mas nao e o comportamento atual em producao. Decisao de produto obrigatoria antes da implementacao.

### Requirement: BE-344 — Percentual de aceite por contrato
O sistema SHALL informar quantos usuarios aceitaram a versao vigente de cada contrato, sem custo por item renderizado. Fonte legada: `app/models/contract.rb:23-25`.

> Nota: corrige o calculo (legado: `(contract_deals.count / User.all.count * 100).round(0)` faz **duas queries COUNT sem cache por widget renderizado**, divide por zero quando nao ha usuarios, e por ser divisao inteira em Ruby o resultado e sempre 0 ou 100).

#### Scenario: Percentual correto
- **GIVEN** 200 usuarios e 87 aceites da versao vigente
- **WHEN** a metrica e exibida
- **THEN** ela mostra 44%, e nao 0%

#### Scenario: Base vazia
- **GIVEN** nenhum usuario cadastrado
- **WHEN** a metrica e exibida
- **THEN** ela mostra ausencia de dado, sem erro de divisao por zero

> AMBIGUIDADE: a metrica esta **comentada em todas as views** do legado (`contracts/list/_widget.html.erb:18`, `detail/_body.html.erb:64-67`). Confirmar com o tech lead se foi desligada por performance (e volta corrigida) ou por estar errada (e sai do escopo).

### Requirement: BE-345 — Renderizacao do texto do contrato
O sistema SHALL renderizar o conteudo do contrato com a **mesma fidelidade** na pagina publica e no console. Fonte legada: `app/models/contract.rb:27-29`; `app/views/pub/contracts/header/_body.html.erb:19`; `detail/_body.html.erb:36`.

> Nota: corrige a divergencia de fidelidade (legado: a pagina publica usa `CGI.unescape(c.description.to_plain_text).html_safe`, e `to_plain_text` **descarta toda a formatacao** — titulos, listas, negrito — enquanto o console mostra o rich text formatado; ou seja, a tela que o usuario juridicamente le e a **menos fiel** das duas). Corrige tambem o metodo morto `decoded_description`, que usa `URI.unescape`, removido no Ruby 3.0.

#### Scenario: Mesma fidelidade nas duas telas
- **GIVEN** um contrato com titulos, listas e negrito no conteudo
- **WHEN** ele e aberto na pagina publica e no console
- **THEN** as duas telas exibem a mesma formatacao

#### Scenario: Conteudo nao e injetado sem sanitizacao
- **GIVEN** um conteudo com marcacao arbitraria
- **WHEN** a pagina publica e renderizada
- **THEN** o HTML e sanitizado por allowlist antes de ser exibido

### Requirement: BE-346 — Codigo morto de contrato nao e portado
O sistema SHALL nao portar o metodo `set_info`, que nunca funcionou. Fonte legada: `app/models/contract.rb:41-48`.

> Nota: corrige D-62 nesta capability (legado: `set_info` referencia a variavel local inexistente `cont` na linha 45, `where(kind: cont.kind)`, e estouraria `NameError` se chamado; nao tem nenhum consumidor).

#### Scenario: Ausencia verificada
- **GIVEN** a base de codigo do ai9
- **WHEN** ela e inspecionada
- **THEN** nao existe equivalente de `set_info`, e a criacao de nova versao usa somente o caminho de BE-338

### Requirement: BE-347 — Criacao do registro de aceite
O sistema SHALL criar o registro de aceite verificando o resultado da gravacao e propagando falhas. Fonte legada: `app/models/contract.rb:55-61`; consumidores em `user_decorator` e `db/seeds.rb:146-157`.

> Nota: corrige a falha silenciosa (legado: `deal_for(user)` **nao checa o retorno do `save`** — se a unicidade barrar, devolve um objeto com erros que ninguem le, e o chamador segue como se tivesse gravado).

#### Scenario: Falha propagada
- **GIVEN** uma tentativa de registrar aceite que viola a unicidade
- **WHEN** ela e processada
- **THEN** a falha e propagada ao chamador e registrada, nunca ignorada

### Requirement: BE-348 — Superficie de rotas de contrato
O sistema SHALL expor apenas as rotas de contrato que tem implementacao. Fonte legada: `config/routes.rb:31` e `:48` versus `app/controllers/pub/contracts_controller.rb`.

> Nota: corrige D-62 nesta capability (legado: `resources :contracts` gera `show`, `new`, `edit`, `update` e `destroy`, **nenhuma delas existe no controller** — `GET /contracts/1`, `PUT /contracts/1` e `DELETE /contracts/1` respondem 500 por `AbstractController::ActionNotFound`; e `resources :contracts` e declarado **duas vezes**, nas linhas 31 e 48, com paths diferentes, gerando helpers homonimos em que a linha 31 vence).

#### Scenario: Rotas sem implementacao nao existem
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao ha rota de contrato sem handler, e nenhuma rota e declarada duas vezes

### Requirement: BE-349 — Rota de indice de contratos sem tipo
O sistema SHALL responder de forma util a uma requisicao de contrato sem tipo informado. Fonte legada: `config/routes.rb:31` com `app/controllers/pub/contracts_controller.rb:2-13`.

> Nota: corrige o 500 garantido (legado: sem `params[:type]` a busca vira `kind ILIKE LOWER('')`, `@contract` fica nil e a linha 7 estoura `NoMethodError` — existe uma rota publica que **sempre** falha).

#### Scenario: Requisicao sem tipo
- **GIVEN** uma requisicao a rota publica de contratos sem informar o tipo
- **WHEN** ela e processada
- **THEN** a resposta e uma pagina que lista os tipos disponiveis, ou 404 — nunca erro interno

### Requirement: FE-330 — Tela publica do contrato
A tela publica SHALL exibir o contrato com titulo, identificacao da versao e data, em pagina propria fora do console. Fonte legada: `app/views/pub/contracts/index.html.erb:1-34`; `header/_container.html.erb`; `header/_body.html.erb:1-49`.

> Nota: corrige a identificacao da versao (legado: o cabecalho mostra apenas "Atualizado em: dd/mm/aaaa" a partir de `updated_at` e **nao mostra o numero da versao** — o usuario nao sabe qual versao esta lendo) e a ausencia de estados de erro e vazio (legado: contrato inexistente resulta em 500).

#### Scenario: Versao visivel
- **GIVEN** a versao 3 vigente de um tipo
- **WHEN** a pagina publica e aberta
- **THEN** o cabecalho mostra o numero da versao e a data de publicacao

#### Scenario: Contrato inexistente
- **GIVEN** a URL de um contrato que nao existe
- **WHEN** ela e aberta
- **THEN** a tela mostra "nao encontrado", com link para os contratos disponiveis

### Requirement: FE-331 — Formatacao do texto na tela publica
A tela publica SHALL renderizar o conteudo rico com sua formatacao original. Fonte legada: `app/views/pub/contracts/header/_body.html.erb:15-22`.

> Nota: corrige a perda de formatacao (legado: `CGI.unescape(c.description.to_plain_text).html_safe` descarta titulos, listas e negrito e injeta o resultado como HTML confiavel; o console mostra o mesmo contrato **formatado**, o que faz as duas telas discordarem sobre o mesmo documento juridico).

#### Scenario: Formatacao preservada
- **GIVEN** um contrato com secoes numeradas e listas
- **WHEN** a tela publica e aberta
- **THEN** a estrutura aparece formatada, identica a exibida no console

### Requirement: FE-332 — Acao de aceite na barra da tela de contrato
A barra da tela de contrato SHALL oferecer a acao de aceitar quando houver aceite pendente. Fonte legada: `app/views/pub/contracts/header/_toolbar_body.html.erb:18-25`; handler em `_after.js.erb:24-81`.

> Nota: corrige D-64 (legado: o botao "ACEITAR" da barra esta **totalmente comentado**, junto com o `if acceptable == 1` que o envolvia, mas o handler JS continua registrado sobre um seletor que **nunca casa com nada** — handler orfao).

#### Scenario: Acao visivel quando pendente
- **GIVEN** um usuario logado com aceite pendente daquele contrato
- **WHEN** ele abre a tela
- **THEN** a acao de aceitar aparece na barra e funciona

#### Scenario: Acao oculta quando nao ha pendencia
- **GIVEN** um visitante anonimo, ou um usuario que ja aceitou a versao vigente
- **WHEN** ele abre a tela
- **THEN** a acao de aceitar nao aparece

### Requirement: FE-333 — Acao de aceite no rodape do documento
O rodape do documento SHALL oferecer a acao de aceitar apos a leitura, com indicacao de progresso. Fonte legada: `app/views/pub/contracts/header/_body.html.erb:24-48`; handler em `header/_container.js.erb:1-59`.

> Nota: corrige D-64 (legado: o bloco do rodape, incluindo o indicador de progresso, esta **totalmente comentado**, e o handler correspondente tambem ficou orfao — somando com FE-332, **nao existe hoje nenhuma forma de aceitar um contrato pela interface**; so o `PUT /contract/accept` manual ou o aceite automatico no cadastro).

#### Scenario: Aceite pelo rodape
- **GIVEN** um usuario com aceite pendente que rolou ate o fim do documento
- **WHEN** ele aciona a acao no rodape
- **THEN** o aceite e registrado, com indicacao de progresso durante a operacao

### Requirement: FE-334 — Retorno apos leitura ou aceite
A tela de contrato SHALL confirmar o resultado da operacao e retornar o usuario ao ponto de origem de forma segura. Fonte legada: `app/views/pub/contracts/_after.js.erb:17-23,55-61`; `header/_container.js.erb:34-40`.

> Nota: corrige D-69 (legado: o `redirect_url` e interpolado **direto no JS** sem escapar — **XSS refletido** — e sem allowlist — **open redirect**; ambos no mesmo parametro).

#### Scenario: Confirmacao de sucesso
- **GIVEN** um aceite registrado com sucesso
- **WHEN** a resposta chega
- **THEN** a tela confirma "O contrato foi aceito com sucesso" e informa que o usuario sera levado de volta

#### Scenario: Destino de retorno hostil
- **GIVEN** um destino de retorno contendo aspas e marcacao de script
- **WHEN** a tela carrega
- **THEN** o valor e recusado, nada e executado e o retorno usa a rota interna padrao

#### Scenario: Falha no aceite
- **GIVEN** o registro do aceite falha
- **WHEN** a resposta de erro chega
- **THEN** a tela informa a falha e mantem o usuario na pagina, com opcao de tentar de novo

### Requirement: FE-335 — Links de contrato na navegacao
A navegacao SHALL oferecer links para Termos de Uso e Politicas de Privacidade. Fonte legada: `app/views/pub/console/base/menu/_container.html.erb:36-41`.

> Nota: corrige a montagem manual da URL (legado: os links sao concatenacoes de `ENV['alias']` com o tipo em portugues cru, sem escape — o espaco so vira `%20` por conta do navegador; ver OPS-331).

#### Scenario: Links validos
- **GIVEN** qualquer tela autenticada
- **WHEN** o rodape da navegacao e renderizado
- **THEN** os dois links apontam para as paginas publicas corretas, com a URL corretamente codificada

### Requirement: FE-336 — Consentimento na tela de conta do usuario
A tela de conta SHALL permitir ao usuario aceitar contratos pendentes e ver o que ja aceitou. Fonte legada: `app/views/pub/console/parts/my_account/parts/essential/_container.html.erb:106-130`.

> Nota: corrige D-64 (legado: a caixa de aceite so aparece se o usuario nao tem nenhum registro de Termos de Uso, ja vem **pre-marcada**, e o campo `contract[agreed_by_user]` **nao e lido por nenhum controller** — caixa puramente decorativa).

#### Scenario: Caixa nao vem pre-marcada
- **GIVEN** um usuario com aceite pendente abrindo a tela de conta
- **WHEN** a tela carrega
- **THEN** a caixa de consentimento aparece **desmarcada** e o aceite so e gravado apos acao deliberada

#### Scenario: Historico de aceites
- **GIVEN** um usuario que ja aceitou versoes anteriores
- **WHEN** ele abre a tela de conta
- **THEN** ele ve quais contratos e versoes aceitou e quando

### Requirement: FE-337 — Consentimento no cadastro publico
A tela de cadastro SHALL exigir consentimento deliberado antes de permitir o envio. Fonte legada: `app/views/pub/base/nav/sign_up/_sign_up.html.erb:53-64`; `_sign_up.js.erb:13-22`.

> Nota: corrige D-64 (legado: a caixa vem **pre-marcada**, o gate e 100% no cliente — desmarcar so desabilita o botao — e `contract[tou_agreed]` **nao e lido pelo backend**; o aceite real e o `after_create`).

#### Scenario: Caixa desmarcada por padrao
- **GIVEN** a tela de cadastro recem-aberta
- **WHEN** ela carrega
- **THEN** a caixa de consentimento esta desmarcada e o envio esta bloqueado

#### Scenario: Gate validado no servidor
- **GIVEN** um envio de cadastro sem o consentimento, feito por fora da interface
- **WHEN** ele chega ao servidor
- **THEN** o cadastro e recusado

### Requirement: FE-338 — Tela de lista de contratos no console
A lista de contratos SHALL apresentar os contratos com busca, estados de carregamento, vazio e erro, e acesso restrito. Fonte legada: `app/views/pub/console/parts/contracts/_body.html.erb`, `_body.js.erb`.

> Nota: corrige a tela orfa (legado: **nao existe item de menu** para Contratos em `create_console_menu` — so se chega por URL direta; o JS le `holder.getData().lastQuery` mas **o HTML nao tem campo de busca**, entao a busca e inacessivel; e nao ha estado de erro).

#### Scenario: Acesso pelo menu
- **GIVEN** um administrador autenticado
- **WHEN** ele abre a navegacao
- **THEN** existe uma entrada para Contratos, visivel apenas para quem tem permissao

#### Scenario: Busca utilizavel
- **GIVEN** a lista aberta
- **WHEN** o administrador digita um termo
- **THEN** o campo de busca existe na tela e a lista e filtrada

#### Scenario: Falha de carga
- **GIVEN** a requisicao da lista falha
- **WHEN** a tela termina de carregar
- **THEN** um estado de erro e exibido com opcao de tentar novamente

### Requirement: FE-339 — Cartao de contrato na lista
Cada cartao SHALL mostrar tipo, titulo, versao vigente e autor, com as acoes permitidas ao papel do usuario. Fonte legada: `app/views/pub/console/parts/contracts/list/_widget.html.erb`, `list/_widget.js.erb`.

> Nota: corrige a ausencia de gate (legado: **nenhuma checagem de permissao nesta tela** — qualquer usuario que chegue a URL ve os contratos e pode publicar nova versao) e o item "Excluir" **inteiramente comentado** no JS (`:60-83`), que anunciava uma acao que nao existe nem no backend.

#### Scenario: Acoes conforme o papel
- **GIVEN** um usuario sem papel administrativo que chegue a tela
- **WHEN** o cartao e renderizado
- **THEN** as acoes de publicar nova versao nao aparecem e sao recusadas pelo servidor se chamadas

#### Scenario: Nenhuma acao inexistente e anunciada
- **GIVEN** o menu de acoes de um cartao
- **WHEN** ele e aberto
- **THEN** so aparecem acoes implementadas — nao ha opcao de excluir contrato

### Requirement: FE-340 — Tela de detalhe do contrato com historico de versoes
O detalhe SHALL listar todas as versoes do tipo em ordem decrescente, com o conteudo formatado de cada uma, e um painel de informacoes gerais. Fonte legada: `app/views/pub/console/parts/contracts/detail/_body.html.erb`; roteamento em `app/controllers/pub/console_controller.rb:27-31`.

> Nota: corrige o 500 por identificador invalido (legado: `@contract` nil resulta em `nil.kind`) e a ausencia de estados de carregamento, vazio e erro.

#### Scenario: Historico completo
- **GIVEN** um tipo com 4 versoes publicadas
- **WHEN** o detalhe e aberto
- **THEN** as 4 versoes aparecem da mais recente para a mais antiga, cada uma com numero, titulo, autor e conteudo formatado

#### Scenario: Identificador invalido
- **GIVEN** a URL de um contrato que nao existe
- **WHEN** ela e aberta
- **THEN** a tela mostra "nao encontrado"

### Requirement: FE-341 — Expansao do conteudo por versao no detalhe
O detalhe SHALL permitir expandir e recolher o conteudo de cada versao de forma independente. Fonte legada: `app/views/pub/console/parts/contracts/detail/_body.js.erb:4-11`.

#### Scenario: Multiplas versoes abertas
- **GIVEN** o detalhe com varias versoes listadas
- **WHEN** o usuario expande duas delas
- **THEN** ambas permanecem abertas ao mesmo tempo, permitindo comparacao lado a lado

### Requirement: FE-342 — Formulario de nova versao de contrato
O formulario SHALL editar titulo e conteudo rico da nova versao, avisando o impacto da publicacao. Fonte legada: `app/views/pub/console/parts/contracts/new_version/_body.html.erb`, `_body.js.erb`; roteamento em `console_controller.rb:32-37`.

> Nota: corrige a publicacao sem aviso (legado: **nao existe botao "Salvar"** — qualquer `keyup`/`change` registra a acao na barra global inferior; nao ha preview, nao ha diff contra a versao anterior, o campo de versao nunca e mostrado e **nao ha aviso de que publicar incrementa a versao e reabre o aceite para todos os usuarios**).

#### Scenario: Aviso de impacto antes de publicar
- **GIVEN** o formulario preenchido
- **WHEN** o administrador aciona publicar
- **THEN** uma confirmacao informa o numero da nova versao e que todos os usuarios voltarao a ter aceite pendente

#### Scenario: Comparacao com a versao anterior
- **GIVEN** o formulario pre-preenchido a partir da versao anterior
- **WHEN** o administrador pede a comparacao
- **THEN** as diferencas em relacao a versao anterior sao exibidas antes da publicacao

#### Scenario: Salvamento explicito
- **GIVEN** alteracoes no formulario
- **WHEN** o administrador sai da tela sem publicar
- **THEN** ele e avisado de que ha alteracoes nao publicadas — a publicacao nunca acontece como efeito colateral de digitar

### Requirement: DB-330 — Modelo de dados de contrato
A tabela de contratos SHALL guardar tipo, versao, titulo, autor e conteudo rico, com indice unico por tipo e versao e chave estrangeira para o autor. Fonte legada: `db/migrate/20180405163859_create_contracts.rb:3-10`; `app/models/contract.rb`.

> Nota: corrige o modelo (legado: **sem indices alem da chave primaria e sem chaves estrangeiras**; a unicidade de tipo e versao e so de aplicacao; `creator_id` sem FK, com orfaos provaveis). A migracao e **append-only**: todas as versoes sao preservadas, porque o detalhe mostra o historico completo, e o `version` — hoje recalculado em todo `save` (BE-336) — e **congelado** no valor que tem no legado.

#### Scenario: Historico preservado na migracao
- **GIVEN** um tipo com 4 versoes no legado
- **WHEN** a migracao de dados executa
- **THEN** as 4 versoes existem no ai9 com os mesmos numeros de versao, titulos, autores e datas

#### Scenario: Autor orfao detectado
- **GIVEN** contratos cujo autor nao existe mais na base de usuarios
- **WHEN** a migracao executa
- **THEN** o dry-run reporta os orfaos antes de qualquer insercao

### Requirement: DB-331 — Modelo de dados do aceite de contrato
A tabela de aceites SHALL guardar quem aceitou, qual versao, quando, e a trilha de auditoria do aceite, com indice unico e chaves estrangeiras. Fonte legada: `db/migrate/20180405164055_create_contract_deals.rb:3-9`; `app/models/contract_deal.rb`.

> Nota: corrige D-65 (legado: o registro guarda **apenas** `user_id`, `contract_id` e `created_at` — **nao ha IP, user-agent nem snapshot do texto aceito**; como o texto vive em `action_text_rich_texts` e pode ser alterado no proprio registro, nao ha garantia tecnica de qual conteudo foi aceito) e a associacao quebrada `Livetat::Auth::User#contracts` com `source: :contract_deal` (`user_decorator.rb:40`), que e corrigida para apontar ao contrato.

#### Scenario: Trilha de auditoria completa
- **GIVEN** um aceite registrado
- **WHEN** o registro e consultado
- **THEN** ele traz usuario, versao aceita, data e hora, endereco de origem, agente do cliente e a impressao do texto aceito

#### Scenario: Texto aceito e imutavel
- **GIVEN** um aceite registrado e uma alteracao posterior no conteudo daquela versao
- **WHEN** o aceite e auditado
- **THEN** e possivel demonstrar que o texto mudou apos o aceite

#### Scenario: Unicidade garantida pelo banco
- **GIVEN** um aceite de um usuario para uma versao
- **WHEN** outra linha com o mesmo par e inserida
- **THEN** o banco recusa por indice unico

> AMBIGUIDADE: D-65 — registrar IP, user-agent e snapshot do texto e **novo requisito**, nao paridade. A recomendacao registrada e incluir os tres, mas a decisao e juridica e cabe ao tech lead.

### Requirement: OPS-330 — Carga inicial dos contratos
A carga inicial SHALL publicar a versao 1 de cada tipo a partir dos documentos de origem, sem fabricar aceites. Fonte legada: `db/seeds.rb:3,112-158`; assets em `db/seed_assets/contracts/`.

> Nota: corrige D-64 no dado (legado: alem de criar as versoes, o seed **re-salva todos os usuarios** e cria retroativamente um registro de aceite para todo usuario que ainda nao tinha — ou seja, **marca a base inteira como tendo aceito, sem nenhuma interacao**).

#### Scenario: Carga cria apenas os documentos
- **GIVEN** uma instalacao sem contratos
- **WHEN** a carga inicial executa
- **THEN** a versao 1 de cada tipo e criada e **nenhum** registro de aceite e gerado

#### Scenario: Carga e idempotente
- **GIVEN** os contratos ja carregados
- **WHEN** a carga executa de novo
- **THEN** nada e duplicado

### Requirement: OPS-331 — Host publico para as URLs de contrato
O sistema SHALL montar as URLs publicas de contrato a partir de configuracao validada na inicializacao. Fonte legada: `app/views/pub/console/base/menu/_container.html.erb:37,40`; `my_account/parts/essential/_container.html.erb:119,122`; `sign_up/_sign_up.html.erb:61`.

> Nota: corrige a dependencia silenciosa (legado: os links absolutos sao `ENV['alias'] + "/contract/" + kind`; **se `alias` nao estiver definido, todos os links de Termos de Uso e Politica de Privacidade quebram**, e a variavel nao esta documentada em lugar nenhum do codigo).

#### Scenario: Configuracao ausente e detectada cedo
- **GIVEN** o host publico nao configurado
- **WHEN** a aplicacao inicia
- **THEN** a inicializacao falha com mensagem clara, em vez de gerar links quebrados em producao

### Requirement: OPS-332 — Documento de origem sem tipo correspondente
A carga inicial SHALL ignorar documentos de origem cujo tipo nao esta declarado, registrando o fato. Fonte legada: `db/seed_assets/contracts/user.html`; `db/seeds.rb:113-116`.

#### Scenario: Documento nao declarado
- **GIVEN** um documento de origem cujo tipo nao consta do catalogo de tipos
- **WHEN** a carga executa
- **THEN** ele e ignorado e o log registra que existe um documento sem tipo correspondente

> AMBIGUIDADE: `user.html` existe no diretorio de seeds desde o legado, nenhum seed o carrega e o seu tipo nao consta de `Contract.contract_kinds`. Pode ser um contrato de adesao planejado e nunca ativado — confirmar com o tech lead (liga com BE-339).

### Requirement: OPS-333 — Valor probatorio do aceite
O registro de aceite SHALL ter valor probatorio: identifica o texto exato aceito e as circunstancias do aceite. Fonte legada: `app/models/contract_deal.rb`; `db/migrate/20180405164055_create_contract_deals.rb`; `app/controllers/pub/contracts_controller.rb:15-26`.

> Nota: corrige D-65 (legado: e o **principal gap de compliance** da capability — o aceite grava o minimo possivel e o texto aceito nao tem garantia de imutabilidade).

#### Scenario: Exportacao de prova
- **GIVEN** um aceite registrado
- **WHEN** a area juridica pede a comprovacao
- **THEN** o sistema exporta usuario, versao, texto integral aceito, data e hora e origem da requisicao

> AMBIGUIDADE: D-65 — cabe ao tech lead e a area juridica definir o conjunto minimo de prova exigido. A recomendacao tecnica registrada e IP, user-agent e snapshot do texto.

### Requirement: OPS-334 — Estado operacional do fluxo de aceite
O fluxo de aceite SHALL estar **ativo e completo** — bloqueio, acao de aceitar na interface e calculo de pendencia funcionando. Fonte legada: `app/controllers/pub_application_controller.rb:55-63`; `app/views/pub/contracts/header/_toolbar_body.html.erb:18-25`; `header/_body.html.erb:24-48`; `app/decorators/models/user_decorator.rb:40`.

> Nota: corrige D-64 no agregado (legado: somando os tres pontos — bloqueio comentado, botoes comentados e associacao quebrada — **nao ha bloqueio, nao ha botao de aceitar e o calculo de pendencia levanta excecao**; o produto so tem paginas publicas de leitura e o aceite implicito no cadastro; toda a maquinaria de versionamento, pendencia e expiracao existe no codigo mas esta inerte).

#### Scenario: Ciclo completo de aceite
- **GIVEN** um usuario com aceite pendente de uma nova versao
- **WHEN** ele acessa o sistema, e levado a pagina do contrato, le e aceita
- **THEN** o aceite e registrado com trilha de auditoria, a pendencia desaparece e o acesso e liberado

> AMBIGUIDADE: D-64 — reativar o fluxo e o comportamento pretendido pelo codigo, mas nao e o comportamento de producao. **Tem consequencia juridica**: hoje o sistema registra um aceite que o usuario nunca deu conscientemente. Decisao de produto e juridica obrigatoria antes da implementacao.
