# Help & FAQ Specification

## Purpose
Central de ajuda do produto: arvore Grupo -> Categoria -> Item de ajuda com conteudo rico, mantida por administradores, e o FAQ consumido pelo usuario final com navegacao por categoria e busca por conteudo.

> Nota de escopo (DEC-09): so o que existe no legado. Nao ha publicacao/rascunho/agendamento, nao ha ordenacao configuravel e nao ha versionamento de conteudo no legado — nada disso e inventado aqui. i18n fica fora (D-115): pt-BR fixo.

## Requirements

### Requirement: BE-350 — Busca de itens de ajuda no FAQ
O sistema SHALL retornar os itens de ajuda de uma categoria, opcionalmente filtrados por termo, com ordem estavel e paginacao. Fonte legada: `config/routes.rb:38`; `app/controllers/pub/help_items_controller.rb:30-39`.

> Nota: corrige D-58 (legado: a busca faz `WHERE help_items.description ILIKE ...` na **coluna** `help_items.description`, mas `has_rich_text :description` sobrescreve o leitor e a coluna nunca mais e escrita — nada criado depois de 04/2019 e encontrado por busca de conteudo) e D-20 (legado: **sem `ORDER BY`**, ordem indeterminada do banco, e **sem paginacao**).

#### Scenario: Busca por conteudo encontra item recente
- **GIVEN** um item de ajuda criado hoje cujo corpo rico contem a palavra "boleto" e cujo titulo nao a contem
- **WHEN** o usuario busca por "boleto" dentro da categoria do item
- **THEN** o item aparece no resultado

#### Scenario: Categoria obrigatoria
- **GIVEN** uma requisicao de busca de FAQ sem categoria
- **WHEN** ela e processada
- **THEN** a resposta e um erro de parametro obrigatorio, e nao uma lista vazia silenciosa como no legado

#### Scenario: Termo numerico nao vira coringa
- **GIVEN** itens de ajuda cadastrados
- **WHEN** o usuario busca pelo termo `0`
- **THEN** apenas itens cujo titulo ou conteudo contem `0` sao retornados — o termo **nao** e convertido em identificador e nao casa a base inteira (legado: `q.to_i` transformava `"abc"` em `0` e `id = 0` entrava no `OR`)

#### Scenario: Ordem estavel e paginada
- **GIVEN** uma categoria com 200 itens
- **WHEN** a mesma busca e repetida
- **THEN** a ordem dos resultados e a mesma nas duas chamadas e a resposta traz no maximo o tamanho de pagina pedido, mais o total filtrado

### Requirement: BE-351 — Busca de itens na Central de ajuda administrativa
O sistema SHALL retornar itens de ajuda de **todos** os grupos e categorias para a arvore administrativa, com paginacao real e total. Fonte legada: `config/routes.rb:39`; `app/controllers/pub/help_items_controller.rb:9-28`.

> Nota: corrige D-20 (legado: usa `limit!`/`offset!` mas **nao devolve contagem total**, entao a UI nao tem "carregar mais" e o offset nunca avanca; o front pede `l = 30` ignorando o default 20 do servidor — qualquer instalacao com mais de 30 itens **perde itens silenciosamente na tela**).

#### Scenario: Instalacao com mais itens que a pagina
- **GIVEN** existem 250 itens de ajuda
- **WHEN** o administrador abre a Central de ajuda
- **THEN** a primeira pagina e exibida junto com o total, e ha como carregar as demais — nenhum item fica invisivel

#### Scenario: Busca administrativa nao filtra por categoria
- **GIVEN** itens em grupos e categorias diferentes casando com o termo
- **WHEN** o administrador busca por esse termo
- **THEN** todos aparecem, agrupados por grupo e categoria

### Requirement: BE-352 — Criar item de ajuda
O sistema SHALL criar um item de ajuda com titulo, categoria, autor e conteudo rico nao vazio. Fonte legada: `app/controllers/pub/help_items_controller.rb:41-52`, params `:96-104`; validacoes `app/models/help_item.rb:6-12`.

> Nota: corrige D-58 em cascata (legado: `has_rich_text :description` faz o leitor retornar sempre um `ActionText::RichText` construido na hora, entao a validacao de presenca **nunca falha** e itens com corpo vazio sao aceitos) e o rotulo trocado em `:89-94`, onde o erro de `:kind` era exibido com a string literal `"help_category_id"`.

#### Scenario: Corpo vazio e rejeitado
- **GIVEN** o formulario preenchido com titulo e categoria mas com o editor de conteudo vazio
- **WHEN** o administrador salva
- **THEN** a criacao e rejeitada com erro de conteudo obrigatorio

#### Scenario: Titulo duplicado na mesma categoria
- **GIVEN** ja existe um item "Como emitir boleto" na categoria Financeiro
- **WHEN** o administrador cria outro com o mesmo titulo na mesma categoria
- **THEN** a criacao e rejeitada por unicidade; o mesmo titulo em **outra** categoria e aceito

#### Scenario: Rotulos de erro em pt-BR
- **GIVEN** uma submissao invalida
- **WHEN** os erros sao exibidos
- **THEN** cada erro nomeia o campo pelo seu rotulo em pt-BR, nunca pelo nome da coluna

### Requirement: BE-353 — Editar item de ajuda
O sistema SHALL atualizar titulo, categoria e conteudo de um item de ajuda existente. Fonte legada: `app/controllers/pub/help_items_controller.rb:54-65`; `fetch_help_item` `:80-82`.

> Nota: corrige o carregamento por parametro inesperado (legado: `fetch_help_item` aceita `params[:help_item_id] || params[:account_id] || params[:id]` — o fallback `account_id` e residuo de copy/paste de outro CRUD e **nao e portado**) e o 500 em id inexistente (legado: `HelpItem.find` levantava `RecordNotFound` respondido como 500 no formato js).

#### Scenario: Identificacao pelo id da rota
- **GIVEN** uma requisicao de edicao que envia um parametro `account_id`
- **WHEN** ela e processada
- **THEN** o parametro e ignorado e o item alvo e o da rota

#### Scenario: Item inexistente
- **GIVEN** um identificador que nao corresponde a nenhum item
- **WHEN** a edicao e chamada
- **THEN** a resposta e 404

### Requirement: BE-354 — Excluir item de ajuda
O sistema SHALL excluir um item de ajuda e reportar corretamente sucesso ou falha. Fonte legada: `app/controllers/pub/help_items_controller.rb:67-76`.

> Nota: corrige a falha reportada como sucesso (legado: o ternario `status: @help_item.errors.any? ? :ok : :ok` devolve **200 sempre**, e o template `help_items/destroy/handle` e um arquivo **vazio de 0 bytes** — falha de exclusao chegava ao operador como sucesso).

#### Scenario: Exclusao bem-sucedida
- **GIVEN** um item de ajuda existente
- **WHEN** o administrador confirma a exclusao
- **THEN** o item e o seu conteudo rico associado sao removidos e a resposta e de sucesso

#### Scenario: Exclusao que falha
- **GIVEN** uma exclusao impedida por erro de persistencia
- **WHEN** a operacao termina
- **THEN** a resposta e de erro com o motivo, e a interface mostra a falha — nunca um sucesso falso

### Requirement: BE-355 — Criar categoria de ajuda
O sistema SHALL criar uma categoria dentro de um grupo, com titulo unico no grupo. Fonte legada: `app/controllers/pub/help_categories_controller.rb:10-21`, params `:67-73`; `app/models/help_category.rb:5-7`.

#### Scenario: Titulo unico no grupo
- **GIVEN** o grupo "Financeiro" ja tem a categoria "Boletos"
- **WHEN** o administrador cria outra "Boletos" no mesmo grupo
- **THEN** a criacao e rejeitada; a mesma "Boletos" em outro grupo e aceita

#### Scenario: Campos nao declarados sao ignorados
- **GIVEN** um payload contendo `is_editing`, campo que o formulario legado enviava sem estar no permit
- **WHEN** ele e processado
- **THEN** o campo e ignorado sem erro

### Requirement: BE-356 — Editar categoria de ajuda
O sistema SHALL renomear uma categoria e permitir move-la de grupo. Fonte legada: `app/controllers/pub/help_categories_controller.rb:23-34`; `fetch_help_category` `:51-53`.

> Nota: corrige o mesmo fallback `account_id` de BE-353, que tambem existe aqui e nao e portado.

#### Scenario: Renomear inline
- **GIVEN** uma categoria na arvore administrativa
- **WHEN** o administrador edita o titulo e confirma
- **THEN** o novo titulo persiste e a arvore e reordenada

#### Scenario: Mover de grupo
- **GIVEN** uma categoria com itens
- **WHEN** ela e movida para outro grupo
- **THEN** os itens acompanham a categoria

### Requirement: BE-357 — Excluir categoria de ajuda em cascata
O sistema SHALL excluir uma categoria e todos os seus itens, avisando no servidor o que sera perdido. Fonte legada: `app/controllers/pub/help_categories_controller.rb:36-47`; cascata em `app/models/help_category.rb:3`.

> Nota: corrige o aviso apenas no cliente (legado: `has_many :items, dependent: :destroy` apaga tudo e o unico aviso era um texto no JS, `help_items/list/_body.js.erb:128`; sem soft delete e sem lixeira).

#### Scenario: Confirmacao diz o que sera perdido
- **GIVEN** uma categoria com 14 itens de ajuda
- **WHEN** o administrador aciona a exclusao
- **THEN** a confirmacao informa a quantidade de itens que serao excluidos junto, antes de qualquer escrita

#### Scenario: Cascata efetiva
- **GIVEN** a exclusao confirmada
- **WHEN** a operacao termina
- **THEN** a categoria e os seus itens deixam de existir, em uma unica transacao

### Requirement: BE-358 — Criar grupo de ajuda
O sistema SHALL criar um grupo de ajuda com titulo unico globalmente. Fonte legada: `app/controllers/pub/help_groups_controller.rb:10-21`, params `:65-71`; `app/models/help_group.rb:6`.

> Nota: corrige o parametro fantasma (legado: `user_id` esta no `permit` mas a tabela `help_groups` **nao tem essa coluna** — `db/migrate/20180410131904_create_help_groups.rb` — entao um formulario que o enviasse causaria `UnknownAttributeError`).

#### Scenario: Titulo unico global
- **GIVEN** ja existe o grupo "Financeiro"
- **WHEN** o administrador cria outro com o mesmo titulo
- **THEN** a criacao e rejeitada

#### Scenario: Campo inexistente no payload
- **GIVEN** um payload com `user_id`
- **WHEN** ele e processado
- **THEN** o campo e ignorado e nenhum erro de atributo desconhecido ocorre

### Requirement: BE-359 — Editar grupo de ajuda
O sistema SHALL renomear um grupo de ajuda existente. Fonte legada: `app/controllers/pub/help_groups_controller.rb:23-34`; `fetch_help_group` `:51-53`.

> Nota: corrige o 500 por id inexistente (legado: `fetch_help_group` usa `.where(...).first` em vez de `find`, devolve `nil` e o `update` estoura `NoMethodError` — 500 onde deveria ser 404).

#### Scenario: Grupo inexistente
- **GIVEN** um identificador de grupo que nao existe
- **WHEN** a edicao e chamada
- **THEN** a resposta e 404

### Requirement: BE-360 — Excluir grupo de ajuda em cascata dupla
O sistema SHALL excluir um grupo com suas categorias e itens, avisando no servidor o alcance da perda. Fonte legada: `app/controllers/pub/help_groups_controller.rb:36-47`; cascata em `app/models/help_group.rb:3`.

> Nota: corrige o aviso apenas no cliente (legado: `has_many :categories, dependent: :destroy` somado a cascata de BE-357 apaga a subarvore inteira, com aviso so em `help_items/list/_body.js.erb:158`).

#### Scenario: Confirmacao quantifica a subarvore
- **GIVEN** um grupo com 5 categorias e 60 itens
- **WHEN** o administrador aciona a exclusao
- **THEN** a confirmacao informa que 5 categorias e 60 itens serao excluidos

#### Scenario: Cascata dupla efetiva
- **GIVEN** a exclusao confirmada
- **WHEN** a operacao termina
- **THEN** grupo, categorias e itens deixam de existir, em uma unica transacao

### Requirement: BE-361 — Navegacao e deep-link das areas de ajuda
As areas de Central de ajuda e FAQ SHALL ter rotas proprias, com deep-link para grupo, categoria e item, e historico do navegador funcionando. Fonte legada: `config/routes.rb:45`; `app/controllers/pub/console_controller.rb:38-50,376-377`.

> Nota: corrige D-92 e a sobrecarga de parametro (legado: em `section=new_item` o `:topic` e o id da **categoria** e nos demais casos e o id do **item** — mesmo parametro, dois significados; e `HelpCategory.where(...).first` sem guarda faz categoria inexistente estourar `NoMethodError`). No ai9 a navegacao usa roteador real com historico; o esquema `resource/topic/section` **nao e reproduzido**.

#### Scenario: Deep-link para um item de ajuda
- **GIVEN** a URL de um item de ajuda especifico
- **WHEN** ela e aberta em uma aba nova
- **THEN** o item abre diretamente, com seu grupo e categoria destacados

#### Scenario: Criar item dentro de uma categoria
- **GIVEN** a URL de criacao de item para uma categoria
- **WHEN** ela e aberta
- **THEN** a categoria vem pre-selecionada, identificada por um parametro proprio e nao reaproveitando o parametro de item

#### Scenario: Categoria inexistente na URL
- **GIVEN** uma URL apontando para uma categoria que nao existe
- **WHEN** ela e aberta
- **THEN** a tela mostra "nao encontrado" e a resposta e 404 — nunca um erro interno

### Requirement: BE-362 — Conteudo rico do item de ajuda como fonte unica
O item de ajuda SHALL ter **um unico** campo de conteudo rico, indexado para busca, com anexos e imagens. Fonte legada: `app/models/help_item.rb:12`; `db/migrate/20180410132354_create_help_items.rb:6`; `db/migrate/20190425020855_create_action_text_tables.action_text.rb`.

> Nota: corrige D-58 na raiz (legado: convivem **duas** fontes para o mesmo nome — a coluna `help_items.description`, escrita ate 04/2019, e a associacao ActionText que sobrescreve o leitor; a busca consultava a coluna e portanto era cega para tudo criado depois).

#### Scenario: Conteudo antigo e novo no mesmo campo
- **GIVEN** um item criado em 2018 (conteudo na coluna legada) e outro criado em 2024 (conteudo em ActionText)
- **WHEN** ambos sao abertos no ai9 apos a migracao de dados
- **THEN** os dois mostram o conteudo correto a partir do mesmo campo

#### Scenario: Busca cobre os dois acervos
- **GIVEN** os mesmos dois itens
- **WHEN** o usuario busca por um termo presente apenas no corpo de cada um
- **THEN** os dois sao encontrados

#### Scenario: Imagem dentro do conteudo
- **GIVEN** um item cujo conteudo tem uma imagem anexada pelo editor
- **WHEN** o item e exibido
- **THEN** a imagem e servida a partir do storage do ai9 e continua visivel apos a migracao

### Requirement: BE-363 — Autenticacao e autorizacao das areas de ajuda
Os endpoints de ajuda SHALL exigir sessao valida, e a escrita SHALL exigir papel administrativo. Fonte legada: `app/controllers/pub_application_controller.rb:34-36`; gates de menu em `app/helpers/application_helper.rb:163-164,169`.

> Nota: corrige D-57 (legado: nenhum dos 4 controllers de help sobrescreve `requires_current_user?`, entao **todos** respondem sem usuario logado — so o CSRF do Rails protegia as escritas; a unica restricao real era de menu: "Central de ajuda" so aparecia para `og?`/`admin?`, "Ajuda" aparecia para todo usuario).

#### Scenario: Anonimo e recusado
- **GIVEN** uma requisicao sem sessao
- **WHEN** ela chama qualquer endpoint de grupo, categoria ou item de ajuda
- **THEN** a resposta e 401

#### Scenario: Usuario comum le mas nao escreve
- **GIVEN** um usuario autenticado sem papel administrativo
- **WHEN** ele consulta o FAQ e depois tenta criar, editar ou excluir qualquer no da arvore
- **THEN** a leitura funciona e todas as escritas respondem 403

> AMBIGUIDADE: o legado **nao tem** flag de publicacao, rascunho, agendamento nem visibilidade por papel ou projeto — todo item criado fica imediatamente visivel no FAQ para qualquer usuario autenticado. Confirmar com o tech lead se "publicar/despublicar" e lacuna a corrigir no ai9 ou se a paridade estrita se mantem.

### Requirement: BE-364 — Rotas e actions mortas de ajuda nao sao portadas
O sistema SHALL nao expor as actions de ajuda que nunca funcionaram no legado. Fonte legada: `app/controllers/pub/help_controller.rb` (arquivo inteiro); `help_items_controller.rb:5-7`; `help_categories_controller.rb:5-7`; `help_groups_controller.rb:5-7`.

> Nota: corrige D-62 (legado: `Pub::HelpController` **nao tem rota alguma** e renderiza `pub/help/index` e `pub/help_items/list/body`, diretorios inexistentes; as tres actions `#index` renderizam `pub/help_items/index`, tambem inexistente, entao `GET /help_items`, `GET /help_categories` e `GET /help_groups` retornam 500). Nao ha feature a preservar: sao rotas mortas com evidencia.

#### Scenario: Superficie de rotas enxuta
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao existem as rotas de indice de item, categoria e grupo herdadas do legado, e a arvore administrativa e servida pela busca administrativa (BE-351)

### Requirement: FE-364 — Tela de FAQ do usuario final
A tela de FAQ SHALL apresentar a arvore de grupos e categorias com a lista de itens da categoria selecionada e busca por conteudo. Fonte legada: `app/views/pub/console/parts/faq/_body.html.erb`, `faq/fast_action/_body.html.erb` e `_body.js.erb`, `faq/help_items/list/_body.js.erb`.

> Nota: corrige tres defeitos observaveis do legado — (a) `lastQuery` era setado para `" "` (um espaco) ao trocar de categoria (`list/_body.js.erb:57`), string nao-blank que fazia o filtro rodar e **sumir com itens de titulo curto sem espaco**; (b) a busca disparava no `keyup` **sem debounce** (`:6-17`), um request por tecla; (c) o callback `failure` do proxy tinha corpo **vazio** (`help_items/_body.js.erb:14-15`), entao falha de rede nao mostrava nada e a lista simplesmente nao atualizava.

#### Scenario: Selecao inicial
- **GIVEN** o usuario abre o FAQ sem deep-link
- **WHEN** a tela termina de carregar
- **THEN** a primeira categoria (por ordem estavel e definida) e selecionada, seu grupo aparece expandido e seus itens sao listados

#### Scenario: Troca de categoria nao filtra por engano
- **GIVEN** uma categoria com itens de titulo de uma palavra so
- **WHEN** o usuario clica nessa categoria vindo de outra
- **THEN** todos os itens da categoria aparecem — nenhum filtro residual e aplicado

#### Scenario: Busca sem resultado
- **GIVEN** o usuario digita um termo que nao casa nada
- **WHEN** a busca retorna
- **THEN** a tela mostra "Nao encontramos nenhuma ajuda para a busca {termo}", com o termo destacado

#### Scenario: Falha de rede na busca
- **GIVEN** a requisicao de busca falha
- **WHEN** a resposta de erro chega
- **THEN** a tela mostra um estado de erro com opcao de tentar novamente, em vez de manter a lista anterior sem aviso

#### Scenario: Grupos e categorias vazios
- **GIVEN** um grupo sem nenhum item e uma categoria sem nenhum item
- **WHEN** o FAQ e renderizado
- **THEN** ambos ficam ocultos, sem deixar container vazio na tela

### Requirement: FE-365 — Tela da Central de ajuda administrativa
A Central de ajuda SHALL apresentar a arvore Grupo -> Categoria -> Item com criacao, renomeacao inline e exclusao em cada nivel. Fonte legada: `app/views/pub/console/parts/help_items/_body.html.erb`, `_body.js.erb`, `list/_body.html.erb`, `list/_body.js.erb`, `list/body.js.erb`.

> Nota: corrige dois bugs do legado — (a) `body.js.erb:13-17` chamava `setEmpty(false)` **nos dois ramos do `if`**, entao o estado vazio do container **nunca** era ativado; (b) o `focusout` de 200 ms **revertia** a edicao inline para o valor original e removia o save flutuante, competindo com o Enter que submetia (corrida observavel: renomear e clicar fora perde a edicao).

#### Scenario: Estado vazio aparece
- **GIVEN** uma instalacao sem nenhum grupo cadastrado
- **WHEN** a Central de ajuda e aberta
- **THEN** a tela mostra "Ainda nao ha grupos cadastrados"; grupos sem categoria mostram "Nao ha categorias no grupo" e categorias sem item mostram "Essa categoria nao possui itens de ajuda"

#### Scenario: Renomeacao inline sem corrida
- **GIVEN** o administrador clicou no titulo de um grupo e digitou um nome novo
- **WHEN** ele clica fora do campo
- **THEN** ou a alteracao e salva, ou e descartada com aviso explicito — o resultado e deterministico e nao depende de um temporizador

#### Scenario: Busca filtra a arvore
- **GIVEN** um termo digitado no campo de busca
- **WHEN** o resultado chega
- **THEN** grupos sem categorias correspondentes e categorias sem itens correspondentes sao ocultados, e sem resultado a tela mostra "Nao encontramos nenhum resultado para a busca {termo}"

#### Scenario: Ordenacao da arvore
- **GIVEN** grupos, categorias e itens cadastrados
- **WHEN** a arvore e renderizada
- **THEN** os tres niveis aparecem ordenados por titulo de forma ascendente e estavel

### Requirement: FE-366 — Formulario e detalhe do item de ajuda
O formulario de item de ajuda SHALL editar titulo e conteudo rico, e o detalhe SHALL exibir o item com autor, categoria e data. Fonte legada: `app/views/pub/console/parts/help_items/new_item/_body.html.erb`, `_body.js.erb`, `handle.js.erb`; `help_items/detail/_body.html.erb`, `_body.js.erb`.

> Nota: corrige tres bugs do legado — (a) `user_id` viajava em campo escondido sempre com o `current_user` (`_body.html.erb:12-13`), entao **editar item de outro autor reescrevia a autoria**; (b) o toast de sucesso dizia sempre "Item criado com sucesso" mesmo na edicao (`_body.js.erb:13`); (c) o avatar de fallback no detalhe usava `random_color`, mudando de cor **a cada render**.

#### Scenario: Autoria preservada na edicao
- **GIVEN** um item criado pelo usuario A
- **WHEN** o usuario B o edita
- **THEN** o autor permanece A e o registro guarda separadamente quem fez a ultima alteracao

#### Scenario: Mensagem correta por operacao
- **GIVEN** a edicao de um item existente
- **WHEN** o salvamento tem sucesso
- **THEN** a mensagem diz que o item foi **atualizado**; na criacao, que foi **criado**

#### Scenario: Detalhe de item inexistente
- **GIVEN** um identificador de item que nao existe
- **WHEN** o detalhe e aberto
- **THEN** a tela mostra "nao encontrado" — sem erro por objeto nulo

#### Scenario: Avatar de fallback estavel
- **GIVEN** um autor sem foto
- **WHEN** o detalhe e renderizado duas vezes
- **THEN** o avatar de iniciais tem a mesma cor nas duas vezes, derivada do proprio usuario

### Requirement: DB-367 — Modelo de dados de grupo de ajuda
A tabela de grupos SHALL guardar titulo unico e ordenacao explicita, com indices. Fonte legada: `db/migrate/20180410131904_create_help_groups.rb`; `app/models/help_group.rb`.

> Nota: corrige o modelo (legado: **nenhum indice** alem da chave primaria; `title` unico apenas por validacao de aplicacao; nenhuma coluna de ordenacao — a ordem era `title ASC` computada na view; e o `user_id` do `permit` do controller **nao existe** na tabela).

#### Scenario: Unicidade garantida pelo banco
- **GIVEN** um grupo "Financeiro"
- **WHEN** outra linha com o mesmo titulo e inserida diretamente
- **THEN** o banco recusa por indice unico

#### Scenario: Ordenacao persistida
- **GIVEN** grupos cadastrados
- **WHEN** o administrador define a ordem de exibicao
- **THEN** a ordem e persistida em coluna propria e respeitada nas duas telas

### Requirement: DB-368 — Modelo de dados de categoria de ajuda
A tabela de categorias SHALL guardar titulo unico no grupo, slug de navegacao persistido e chave estrangeira indexada para o grupo. Fonte legada: `db/migrate/20180410132114_create_help_categories.rb`; `app/models/help_category.rb`.

> Nota: corrige o modelo (legado: **sem FK real e sem indice** em `help_group_id`; unicidade de titulo no grupo so por validacao; e `normalized_title` — `I18n.transliterate` + downcase + espacos trocados por hifens, `help_category.rb:9-11` — era usado como slug de navegacao do FAQ calculado **em runtime**, sem persistencia nem garantia de unicidade).

#### Scenario: Slug estavel e unico
- **GIVEN** duas categorias cujos titulos normalizam para o mesmo slug
- **WHEN** a segunda e criada
- **THEN** o slug e desambiguado e persistido, e o deep-link de cada categoria continua valido mesmo depois de renomear a outra

#### Scenario: Integridade com o grupo
- **GIVEN** uma categoria vinculada a um grupo
- **WHEN** se tenta gravar uma categoria com grupo inexistente
- **THEN** o banco recusa pela chave estrangeira

### Requirement: DB-369 — Modelo de dados do item de ajuda e do conteudo rico
A tabela de itens SHALL guardar titulo, categoria, autor e um unico campo de conteudo rico com anexos, com chaves estrangeiras e indices. Fonte legada: `db/migrate/20180410132354_create_help_items.rb`; `db/migrate/20190425020855_create_action_text_tables.action_text.rb`; `app/models/help_item.rb`.

> Nota: corrige D-58 no dado (legado: `help_items.description` e coluna **orfa** — conteudo ate 04/2019 — enquanto o conteudo novo vive em `action_text_rich_texts.body` com `record_type='HelpItem'` e `name='description'`; a migracao de dados e obrigatoriamente de **dois passos**, unificando os dois acervos num unico campo e reindexando a busca sobre ele). Corrige tambem a ausencia de indices em `help_items` alem da chave primaria e a falta de FKs em `help_category_id` e `user_id`.

#### Scenario: Unificacao dos dois acervos
- **GIVEN** itens com conteudo na coluna legada e itens com conteudo em ActionText
- **WHEN** a migracao de dados executa
- **THEN** os dois conjuntos terminam no mesmo campo de conteudo rico, sem perda, e o relatorio de dry-run lista quantos vieram de cada origem

#### Scenario: Unicidade de titulo por categoria no banco
- **GIVEN** um item "Como emitir boleto" na categoria Financeiro
- **WHEN** outra linha com o mesmo par titulo e categoria e inserida
- **THEN** o banco recusa por indice unico composto

#### Scenario: Anexos do conteudo migrados
- **GIVEN** itens com imagens anexadas pelo editor, guardadas em disco local no legado
- **WHEN** a migracao termina
- **THEN** os anexos estao no storage do ai9 e as referencias dentro do conteudo apontam para eles
