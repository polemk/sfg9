# Indicators Specification

## Purpose
Indicadores de gestao: catalogo de indicadores globais e especificos de projeto, conexao indicador-projeto, e a grade mensal de lancamentos de valor por indicador, projeto, mes e ano.

> Nota de escopo (DEC-09): **serie historica calculada, variacao (mes a mes, ano a ano, percentual), acumulado, media e grafico de indicador NAO existem no legado** e ficam **fora do escopo**. O `dash` do legado nao referencia indicadores. O que existe sao consultas pontuais de lancamento por mes e por indicador (BE-716) — e so isso vira spec.
> Nota de escopo (DEC-09): i18n fica fora (D-115): pt-BR fixo. Nao ha rotina automatica, lembrete, fechamento de mes, import, export nem API publica de indicadores (OPS-310) — nada disso e inventado.
> Nota de escopo (DEC-10): a formatacao monetaria e os componentes visuais usam as libs do ai9, nao os do legado.

## Requirements

### Requirement: BE-310 — Superficie de rotas do catalogo de indicadores
O sistema SHALL expor a listagem de indicadores apenas pela rota que tem tela implementada. Fonte legada: `app/controllers/pub/indicators_controller.rb:5-7`; rota `config/routes.rb:170`.

> Nota: corrige D-62 nesta capability (legado: `GET /indicators` renderiza `pub/indicators/index`, template que **nao existe no repositorio** — `ActionView::MissingTemplate`, 500; e nao ha `before_action` de autorizacao, entao qualquer usuario logado bate na rota).

#### Scenario: Rota sem tela nao existe
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao ha rota de indicadores sem tela correspondente, e o catalogo e servido pela area do console

### Requirement: BE-311 — Busca de indicadores globais
O sistema SHALL buscar indicadores globais por texto, com ordenacao, paginacao real e total. Fonte legada: `app/controllers/pub/indicators_controller.rb:9-39`; rota `config/routes.rb:169`.

> Nota: corrige D-20 (legado: **nao ha contagem total**, entao a paginacao nao sabe quando parar; o front manda `l=50, o=0` fixos e nunca incrementa o offset — **a lista trunca em 50 indicadores globais sem aviso**).

#### Scenario: Mais de 50 indicadores globais
- **GIVEN** 130 indicadores globais cadastrados
- **WHEN** o administrador abre o catalogo
- **THEN** a primeira pagina e exibida com o total informado, e ha como carregar as demais — nenhum indicador fica invisivel

#### Scenario: Escopo da lista
- **GIVEN** indicadores globais e indicadores especificos de projeto
- **WHEN** a busca do catalogo global executa
- **THEN** apenas os globais sao retornados; os especificos aparecem na tela de indicadores especificos do projeto

### Requirement: BE-312 — Ordenacao dinamica por coluna
O sistema SHALL ordenar a lista de indicadores pelas colunas suportadas, a partir de uma allowlist de campos. Fonte legada: `app/models/indicator.rb:53-81`; uso em `app/controllers/pub/indicators_controller.rb:30`.

> Nota: corrige tres bugs do legado — (a) `prepare_ordering` chama `Segment.get_ordering_key`/`get_ordering_style` em vez dos metodos do proprio `Indicator`, dependendo de outra classe responder por chaves de indicador; (b) `Indicator.get_ordering_key("key")` devolve `"integration_key"`, coluna que **nao existe** na tabela, entao ordenar por "Chave" gera `PG::UndefinedColumn` (500); (c) a chave e interpolada direto no SQL sem allowlist real — **risco de SQL injection**. Na UI so o cabecalho "Titulo" era clicavel, o que mascarava (b) e (c).

#### Scenario: Ordenacao por campo suportado
- **GIVEN** a lista de indicadores
- **WHEN** o administrador ordena por titulo, ascendente e depois descendente
- **THEN** a lista e reordenada corretamente nos dois sentidos

#### Scenario: Campo de ordenacao desconhecido
- **GIVEN** uma requisicao pedindo ordenacao por um campo fora da allowlist
- **WHEN** ela e processada
- **THEN** o pedido e recusado com 400 e nenhum trecho do parametro chega ao SQL

### Requirement: BE-313 — Detalhe do indicador
O sistema SHALL exibir o detalhe de um indicador com seus dados e instrucao. Fonte legada: `app/controllers/pub/indicators_controller.rb:41-47`; rota `config/routes.rb:170`.

> Nota: corrige D-62 nesta capability (legado: o diretorio `pub/console/parts/indicators/detail/` **nao existe** — 500; e o `#show` **nem carrega** o indicador, porque o `before_action` de carga so roda em `edit`, `update` e `destroy`; ha CSS orfao para essa tela, sinal de que ela foi planejada e abandonada). No ai9 o detalhe existe e mostra o que o legado tem; **nao** ha serie historica nem variacao (DEC-09).

#### Scenario: Detalhe carrega
- **GIVEN** um indicador existente
- **WHEN** o detalhe e aberto
- **THEN** titulo, chave, tipo de valor, estado ativo e a instrucao sao exibidos

#### Scenario: Indicador inexistente
- **GIVEN** um identificador que nao corresponde a nenhum indicador
- **WHEN** o detalhe e aberto
- **THEN** a resposta e 404

### Requirement: BE-314 — Formulario de cadastro de indicador
O sistema SHALL abrir o formulario de cadastro em modo global ou em modo especifico de projeto. Fonte legada: `app/controllers/pub/indicators_controller.rb:49-60`.

> Nota: corrige a autorizacao apenas de view (legado: a restricao a admin, og e manager existe **so no botao** da tela — o endpoint nao valida papel; ver BE-717).

#### Scenario: Modo especifico de projeto
- **GIVEN** o administrador aciona o cadastro a partir da tela de um projeto
- **WHEN** o formulario abre
- **THEN** o indicador em criacao ja e especifico daquele projeto

#### Scenario: Modo global
- **GIVEN** o administrador aciona o cadastro a partir do catalogo global
- **WHEN** o formulario abre
- **THEN** o indicador em criacao e global

### Requirement: BE-315 — Formulario de edicao de indicador
O sistema SHALL abrir o formulario de edicao com os dados do indicador. Fonte legada: `app/controllers/pub/indicators_controller.rb:62-68`.

> Nota: corrige o erro por identificador invalido (legado: `Indicator.find` levanta `RecordNotFound`, respondido como 500 no formato js). Registrado: no legado o formulario **nao permite editar** `value_type` nem o estado ativo.

#### Scenario: Edicao de indicador inexistente
- **GIVEN** um identificador que nao existe
- **WHEN** o formulario de edicao e aberto
- **THEN** a resposta e 404

#### Scenario: Campos editaveis
- **GIVEN** um indicador existente
- **WHEN** o formulario abre
- **THEN** titulo, chave e instrucao vem preenchidos e sao editaveis

### Requirement: BE-316 — Criar indicador
O sistema SHALL criar um indicador e, quando especifico de projeto, criar a conexao com o projeto de forma atomica. Fonte legada: `app/controllers/pub/indicators_controller.rb:70-84`; `app/models/project_indicator_connection.rb:5-6`.

> Nota: corrige a criacao parcial silenciosa (legado: se a criacao do indicador falha, o codigo tenta criar a conexao com identificador nulo, que **falha silenciosamente** por validacao de presenca sem nenhum retorno ao usuario; e chama `destroy` num objeto nao persistido, no-op confuso). Corrige tambem o `user_id` enviado pelo formulario e descartado sem aviso.

#### Scenario: Indicador especifico nasce conectado
- **GIVEN** um cadastro de indicador especifico de um projeto
- **WHEN** ele e salvo com sucesso
- **THEN** o indicador e a conexao com o projeto existem, criados na mesma transacao

#### Scenario: Falha nao deixa residuo
- **GIVEN** um cadastro invalido de indicador especifico
- **WHEN** ele e submetido
- **THEN** a resposta e 422 com os erros, e nenhum indicador e nenhuma conexao sao criados

### Requirement: BE-317 — Editar indicador
O sistema SHALL atualizar um indicador em uma unica operacao, mantendo coerente a conexao com o projeto. Fonte legada: `app/controllers/pub/indicators_controller.rb:100-113`.

> Nota: corrige a gravacao dupla (legado: chama `update` e depois `save` de novo — dois roundtrips, e o callback de propagacao para os lancamentos, BE-322, roda **duas vezes**) e a incoerencia de escopo (legado: trocar o projeto de um indicador existente **nao** cria nem remove a conexao, entao o indicador vira "especifico" sem conexao e **some da tela do projeto**).

#### Scenario: Uma unica gravacao
- **GIVEN** uma edicao valida de indicador
- **WHEN** ela e processada
- **THEN** ha uma unica gravacao e um unico disparo de propagacao

#### Scenario: Mudanca de escopo mantem a conexao coerente
- **GIVEN** um indicador global
- **WHEN** ele e alterado para especifico de um projeto
- **THEN** a conexao com esse projeto passa a existir e o indicador aparece na tela do projeto

### Requirement: BE-318 — Excluir indicador
O sistema SHALL excluir um indicador por remocao logica, preservando a serie de lancamentos, com confirmacao que informa o alcance da operacao. Fonte legada: `app/controllers/pub/indicators_controller.rb:116-126`; `app/models/indicator.rb:2,4`.

> Nota: corrige D-66 (legado: `has_many :entries, dependent: :delete_all` **apaga toda a serie historica de lancamentos** sem callbacks, sem backup e sem confirmacao especifica; a confirmacao da UI so dizia "A operacao nao pode ser desfeita"). Corrige tambem o status enganoso (legado: o template de resposta e sempre `:ok`, mesmo no caminho de erro, entao o front recarrega a lista como se tivesse dado certo).

#### Scenario: Exclusao nao apaga lancamentos
- **GIVEN** um indicador com 48 lancamentos historicos
- **WHEN** o administrador o exclui
- **THEN** o indicador deixa de aparecer nas telas, os 48 lancamentos permanecem recuperaveis e a operacao e reversivel

#### Scenario: Confirmacao diz o que sera perdido
- **GIVEN** o mesmo indicador
- **WHEN** o administrador aciona a exclusao
- **THEN** a confirmacao informa quantos lancamentos e quais projetos serao afetados, antes de qualquer escrita

#### Scenario: Indicador conectado a projeto
- **GIVEN** um indicador conectado a pelo menos um projeto
- **WHEN** a exclusao e tentada
- **THEN** ela e recusada com o motivo e a resposta e de erro — nao 200

### Requirement: BE-319 — Ativar e desativar indicador
O sistema SHALL alternar o estado ativo de um indicador, aceitando apenas os valores validos. Fonte legada: `app/controllers/pub/indicators_controller.rb:86-98`; rota `config/routes.rb:171`; `app/models/indicator.rb:83-85`.

> Nota: corrige o 500 por identificador invalido (legado: `Indicator.where(id: ...).first` sem guarda, entao id inexistente estoura `NoMethodError`) e o estado ambiguo (legado: a coluna e `integer` e aceita qualquer valor, mas `is_active?` so considera `== 1`, entao 2 ou -1 contam como inativo). Corrige tambem a ausencia de autorizacao no servidor (ver BE-717).

#### Scenario: Valor invalido de estado
- **GIVEN** uma requisicao pedindo estado `2`
- **WHEN** ela e processada
- **THEN** a resposta e 422 — o estado e booleano e so aceita ativo ou inativo

#### Scenario: Indicador inexistente
- **GIVEN** um identificador que nao existe
- **WHEN** a alternancia e chamada
- **THEN** a resposta e 404

### Requirement: BE-320 — Unicidade de titulo entre indicadores globais e especificos
O sistema SHALL impedir titulos colidentes segundo tres regras: global nao colide com nenhum outro; especifico nao colide com global; especifico nao colide com outro especifico do mesmo projeto. Fonte legada: `app/models/indicator.rb:12-23`.

#### Scenario: Global colide com especifico
- **GIVEN** um indicador especifico chamado "RENTABILIDADE" no projeto A
- **WHEN** alguem cria um indicador global com o mesmo titulo
- **THEN** a criacao e recusada com "Ja utilizado"

#### Scenario: Especifico colide com global
- **GIVEN** um indicador global chamado "RENTABILIDADE"
- **WHEN** alguem cria um especifico com o mesmo titulo em qualquer projeto
- **THEN** a criacao e recusada com "Ja utilizado por indicador global"

#### Scenario: Especificos de projetos diferentes coexistem
- **GIVEN** um indicador especifico "MARGEM" no projeto A
- **WHEN** alguem cria "MARGEM" especifico no projeto B
- **THEN** a criacao e aceita; repetir no proprio projeto A e recusado com "Ja utilizado nesse projeto"

### Requirement: BE-321 — Normalizacao de titulo, geracao de chave e tipo de valor padrao
O sistema SHALL normalizar o titulo para comparacao, gerar a chave a partir do titulo quando ausente e aplicar o tipo de valor padrao. Fonte legada: `app/models/indicator.rb:38-46`.

> Nota: corrige o 500 por titulo ausente (legado: `I18n.transliterate(nil)` levanta erro **antes** da validacao de presenca — criar sem titulo da 500 em vez de 422) e a normalizacao destrutiva (legado: o titulo e gravado em **CAIXA ALTA sem acentos** a cada save, inclusive em updates, e os acentos originais ja foram perdidos de forma irreversivel).

#### Scenario: Titulo ausente
- **GIVEN** uma criacao sem titulo
- **WHEN** ela e processada
- **THEN** a resposta e 422 com erro de campo obrigatorio

#### Scenario: Titulo preserva o que o usuario digitou
- **GIVEN** um indicador criado como "Rentabilidade média"
- **WHEN** ele e exibido
- **THEN** o titulo aparece como digitado, e a comparacao de unicidade continua ignorando acentos e caixa

#### Scenario: Chave gerada
- **GIVEN** uma criacao sem chave informada
- **WHEN** ela e processada
- **THEN** a chave e derivada do titulo, em minusculas, sem acentos e com espacos trocados por sublinhado

### Requirement: BE-322 — Denormalizacao do indicador nos lancamentos
O sistema SHALL manter, em cada lancamento, a identificacao do indicador vigente no momento do lancamento. Fonte legada: `app/models/indicator.rb:48-50`.

> Nota: corrige o `UPDATE` em massa sincrono (legado: um `update_all` que **pula validacoes e callbacks e nao atualiza `updated_at`** roda em **todo save** do indicador, inclusive na alternancia de estado e duas vezes na edicao — em indicador com milhares de lancamentos e um update em massa dentro do request).

#### Scenario: Edicao de indicador nao trava o request
- **GIVEN** um indicador com 20.000 lancamentos
- **WHEN** o titulo e alterado
- **THEN** a resposta ao usuario nao depende de reescrever os 20.000 registros

> AMBIGUIDADE: D-70 — a denormalizacao de titulo, chave e tipo de valor dentro de `indicator_entries` pode ser **intencional** (foto do indicador na epoca do lancamento) ou bug. Hoje o `update_all` **reescreve o historico**, entao um lancamento antigo passa a mentir sobre como o indicador era na epoca. Confirmar com o tech lead: congelar a foto no momento do lancamento, ou resolver sempre por join com o indicador atual.

### Requirement: BE-323 — Superficie de rotas dos lancamentos
O sistema SHALL expor os lancamentos apenas pelas rotas que tem tela implementada. Fonte legada: `app/controllers/pub/indicator_entries_controller.rb:5-7`; rota `config/routes.rb:84`.

> Nota: corrige D-62 nesta capability (legado: `GET /indicator_entries` renderiza um diretorio de views que **nao existe** — 500; a tela real e a do console).

#### Scenario: Rota morta ausente
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao existe rota de indice de lancamentos sem tela

### Requirement: BE-324 — Grade de lancamentos por projeto
O sistema SHALL retornar, para um projeto, os indicadores ativos com seus lancamentos do periodo, em uma unica consulta eficiente. Fonte legada: `app/controllers/pub/indicator_entries_controller.rb:9-26`.

> Nota: corrige o N+1 severo (legado: o endpoint devolve **indicadores**, nao lancamentos, e as entries sao buscadas **dentro da view**, uma consulta por par indicador-mes — **12 consultas por indicador** no modo de ano inteiro), a ordenacao descartada (legado: `@indicators.order(title: :asc)` **nao e atribuido**, entao a ordem alfabetica e silenciosamente perdida), os parametros aceitos e ignorados (`q`, `l` e `o`) e o 500 por projeto invalido (legado: `Project.where(id:).first` sem guarda estoura `nil.indicators`).

#### Scenario: Consulta unica
- **GIVEN** um projeto com 30 indicadores ativos e o filtro de ano inteiro
- **WHEN** a grade e carregada
- **THEN** o numero de consultas ao banco nao cresce com o numero de indicadores nem de meses

#### Scenario: Ordem alfabetica respeitada
- **GIVEN** indicadores com titulos variados
- **WHEN** a grade e carregada
- **THEN** os indicadores aparecem em ordem alfabetica

#### Scenario: Projeto invalido
- **GIVEN** um identificador de projeto que nao existe ou ao qual o usuario nao tem acesso
- **WHEN** a grade e solicitada
- **THEN** a resposta e 404 ou 403 — nunca erro interno

#### Scenario: Indicador desativado
- **GIVEN** um indicador desativado que tem lancamentos historicos
- **WHEN** a grade e carregada
- **THEN** ele nao aparece na grade e os lancamentos permanecem no banco, reaparecendo se o indicador for reativado

### Requirement: BE-325 — Cadastro e edicao de lancamento fora da grade
O sistema SHALL nao expor rotas de formulario de lancamento que nao existem. Fonte legada: `app/controllers/pub/indicator_entries_controller.rb:28-44`.

> Nota: corrige D-62 nesta capability (legado: as rotas de novo e de edicao renderizam um parcial que **nao existe** — 500; o cadastro e a edicao de lancamento acontecem **inline na grade**, nunca por formulario separado).

#### Scenario: Edicao acontece na grade
- **GIVEN** a grade de lancamentos
- **WHEN** o usuario altera o valor de uma celula
- **THEN** o lancamento e criado ou atualizado ali mesmo, sem navegar para outra tela

### Requirement: BE-326 — Criar lancamento
O sistema SHALL criar um lancamento para um par indicador, projeto, mes e ano, atribuido ao usuario da sessao. Fonte legada: `app/controllers/pub/indicator_entries_controller.rb:46-58`; `app/models/indicator_entry.rb:6`.

> Nota: corrige D-68 (legado: `user_id` vem **do formulario** e esta no `permit` — **e possivel registrar lancamento em nome de outro usuario forjando o campo** — e nao ha checagem de que o projeto pertence ao usuario) e a condicao de corrida (legado: a unicidade de mes por ano, projeto e indicador existe **so na aplicacao, sem indice unico no banco**, entao chamadas concorrentes criam duplicatas).

#### Scenario: Autoria e sempre do usuario da sessao
- **GIVEN** um payload de lancamento com identificador de outro usuario
- **WHEN** ele e processado
- **THEN** o campo e ignorado e o lancamento fica atribuido ao usuario da sessao

#### Scenario: Projeto fora do escopo do usuario
- **GIVEN** um payload apontando para um projeto ao qual o usuario nao tem acesso
- **WHEN** ele e processado
- **THEN** a resposta e 403 e nada e gravado

#### Scenario: Lancamento ja existente para o periodo
- **GIVEN** outra aba ja criou o lancamento daquele mes
- **WHEN** a submissao chega
- **THEN** ela atualiza o lancamento existente em vez de falhar com erro de duplicidade, e o banco impede duplicatas por indice unico

### Requirement: BE-327 — Editar lancamento
O sistema SHALL atualizar o valor de um lancamento existente, registrando quem alterou sem sobrescrever quem lancou. Fonte legada: `app/controllers/pub/indicator_entries_controller.rb:60-73`; `app/models/indicator_entry.rb:13,23-27`.

> Nota: corrige a gravacao dupla (legado: `update` seguido de `save` redundante), o 500 por indicador ausente (legado: `self.indicator.title` estoura `NoMethodError` **antes** da validacao de presenca) e a perda de autoria (legado: `user_id` vem do formulario, entao **o ultimo editor sobrescreve o autor original** e nao ha trilha de quem alterou).

#### Scenario: Autor preservado
- **GIVEN** um lancamento feito pelo usuario A
- **WHEN** o usuario B altera o valor
- **THEN** o autor continua sendo A e o registro guarda B como ultimo editor, com data e hora

#### Scenario: Mover lancamento de periodo
- **GIVEN** um lancamento existente
- **WHEN** o mes ou o ano e alterado
- **THEN** a mudanca fica registrada na trilha de auditoria, ou e recusada — nunca acontece em silencio

#### Scenario: Payload sem indicador
- **GIVEN** uma edicao sem indicador informado
- **WHEN** ela e processada
- **THEN** a resposta e 422 com erro de campo obrigatorio

### Requirement: BE-328 — Excluir lancamento
O sistema SHALL permitir remover um lancamento, com confirmacao e autorizacao. Fonte legada: `app/controllers/pub/indicator_entries_controller.rb:75-85`.

> Nota: corrige o erro dentro do sucesso (legado: no ramo de erro o template referenciado **nao existe** — 500 dentro de uma resposta 200) e a ausencia de confirmacao e de autorizacao.

#### Scenario: Remocao confirmada
- **GIVEN** um lancamento existente
- **WHEN** o usuario com permissao aciona a remocao e confirma
- **THEN** o lancamento e removido e a celula volta ao estado "nao lancado"

> AMBIGUIDADE: nenhuma tela do legado chama essa rota — a grade so cria e atualiza, e zerar um valor grava `0` em vez de apagar. Confirmar com o tech lead se a exclusao de lancamento e feature viva ou residuo a descartar.

### Requirement: BE-329 — Identidade e periodicidade do lancamento
O lancamento SHALL ser identificado por projeto, indicador, mes e ano, com periodicidade mensal e faixa de mes validada. Fonte legada: `app/models/indicator_entry.rb:1-27,57`.

> Nota: corrige a ausencia de validacao de faixa (legado: `month` e `year` sao inteiros soltos sem `date` e **sem validacao de faixa** — mes 13 ou ano 0 passam pela validacao e so explodem depois em `Date.new(year, month)`, usado na formatacao). Registrado: `value` e obrigatorio com default 0, entao **valor zero e valido e valor nulo nao**.

#### Scenario: Mes fora da faixa
- **GIVEN** um payload com mes 13
- **WHEN** ele e processado
- **THEN** a resposta e 422 — nao ha registro gravado que so falhe depois na exibicao

#### Scenario: Periodicidade
- **GIVEN** um par indicador e projeto
- **WHEN** os lancamentos sao consultados
- **THEN** existe no maximo um lancamento por mes e ano — nao ha suporte a periodicidade diaria, semanal ou trimestral

### Requirement: FE-310 — Tela de catalogo de indicadores globais
A tela de indicadores SHALL listar os indicadores globais com busca, ordenacao e acoes por item. Fonte legada: `app/views/pub/console/parts/indicators/_body.html.erb`, `_body.js.erb`.

> Nota: corrige a ausencia de estado de erro (legado: o callback de falha do proxy e **vazio**, entao falha de rede nao produz aviso) e a paginacao fixa em 50 sem scroll (ver BE-311).

#### Scenario: Estados da lista
- **GIVEN** a tela aberta
- **WHEN** a carga esta em andamento, retorna vazia, retorna vazia para uma busca, ou falha
- **THEN** a tela mostra respectivamente carregando, "Nao existem indicadores cadastrados", "Nao encontramos nenhum resultado para a busca {termo}" e um estado de erro com opcao de tentar novamente

#### Scenario: Visibilidade por papel
- **GIVEN** um usuario sem papel administrativo, de gestao ou de operador
- **WHEN** ele abre a navegacao
- **THEN** a entrada do catalogo de indicadores nao aparece

### Requirement: FE-311 — Busca incremental de indicadores
A busca SHALL filtrar a lista conforme o usuario digita, cancelando requisicoes obsoletas. Fonte legada: `app/views/pub/console/parts/indicators/_body.js.erb:57-70`.

#### Scenario: Digitacao rapida
- **GIVEN** o usuario digita seis caracteres rapidamente
- **WHEN** as respostas chegam
- **THEN** apenas o resultado do termo final e exibido, e requisicoes anteriores sao canceladas

#### Scenario: Limpar a busca
- **GIVEN** um termo digitado
- **WHEN** o usuario aciona limpar
- **THEN** a lista volta ao estado sem filtro — o legado nao tinha esse controle

### Requirement: FE-312 — Ordenacao por clique no cabecalho
O cabecalho da lista SHALL alternar a ordenacao entre padrao, ascendente e descendente, com indicacao visual. Fonte legada: `app/views/pub/console/parts/indicators/_body.js.erb:10-54`.

> Nota: corrige a perda de estado (legado: a ordenacao escolhida **nao e persistida** e se perde ao sair da tela).

#### Scenario: Ciclo de ordenacao
- **GIVEN** a coluna de titulo
- **WHEN** o usuario clica tres vezes
- **THEN** a ordenacao passa por padrao, ascendente e descendente, com o icone acompanhando cada estado

#### Scenario: Ordenacao lembrada
- **GIVEN** o usuario ordenou por titulo descendente e saiu da tela
- **WHEN** ele volta
- **THEN** a ordenacao escolhida e restaurada

### Requirement: FE-313 — Cartao de indicador com instrucao expansivel
Cada item da lista SHALL permitir expandir a instrucao do indicador. Fonte legada: `app/views/pub/console/parts/indicators/list/_widget.html.erb`, `list/_widget.js.erb:68-80`.

#### Scenario: Indicador sem instrucao
- **GIVEN** um indicador sem instrucao cadastrada
- **WHEN** o item e renderizado
- **THEN** nao ha controle de expansao

#### Scenario: Expansao exclusiva
- **GIVEN** dois indicadores com instrucao
- **WHEN** o usuario expande o segundo
- **THEN** o primeiro se recolhe

### Requirement: FE-314 — Menu de acoes do indicador
Cada item SHALL oferecer editar e excluir, ocultos para usuario somente-leitura. Fonte legada: `app/views/pub/console/parts/indicators/list/_widget.html.erb:7-27`.

#### Scenario: Usuario somente-leitura
- **GIVEN** um usuario com permissao somente-leitura
- **WHEN** a lista e renderizada
- **THEN** o menu de acoes nao aparece em nenhum item

### Requirement: FE-315 — Confirmacao de exclusao de indicador
A confirmacao de exclusao SHALL declarar exatamente o que sera perdido antes da operacao. Fonte legada: `app/views/pub/console/parts/indicators/list/_widget.js.erb:26-41`.

> Nota: corrige D-66 na UI (legado: a confirmacao dizia apenas "A operacao nao pode ser desfeita. Tem certeza?" e **nao avisava que todos os lancamentos historicos seriam apagados junto**; alem disso a chamada nao tinha tratamento de erro e o servidor respondia 200 mesmo em falha, entao a lista recarregava e o item continuava la sem explicacao).

#### Scenario: Texto da confirmacao
- **GIVEN** um indicador com lancamentos historicos
- **WHEN** o usuario aciona a exclusao
- **THEN** a confirmacao informa o numero de lancamentos e os projetos afetados, e que a operacao e reversivel (BE-318)

#### Scenario: Falha visivel
- **GIVEN** a exclusao e recusada pelo servidor
- **WHEN** a resposta chega
- **THEN** a tela informa o motivo e o item continua na lista com explicacao

### Requirement: FE-316 — Formulario de indicador
O formulario SHALL permitir informar titulo, chave e instrucao em conteudo rico, com mensagens coerentes. Fonte legada: `app/views/pub/console/parts/indicators/helper/_body.html.erb`, `helper/_mount.js.erb`.

> Nota: corrige a copia herdada de outro modulo (legado: o estado vazio do formulario diz **"Essa construtora nao pode ser alterada"**, texto claramente residual de copy/paste).

#### Scenario: Titulo por modo
- **GIVEN** o formulario aberto
- **WHEN** ele esta em criacao ou em edicao
- **THEN** o cabecalho diz respectivamente "Cadastrar um indicador" e "Editar um indicador", e a mensagem de sucesso diz "criado" ou "atualizado" conforme o caso

#### Scenario: Mensagens pertencem ao dominio
- **GIVEN** qualquer estado do formulario
- **WHEN** uma mensagem e exibida
- **THEN** ela fala de indicador, nunca de outro dominio

#### Scenario: Reflexo nas outras telas
- **GIVEN** a grade de lancamentos aberta em outra aba do console
- **WHEN** um indicador e salvo
- **THEN** a grade reflete a alteracao

### Requirement: FE-317 — Deep-link do formulario de indicador
As acoes de criar e editar indicador SHALL ter URL propria com historico do navegador. Fonte legada: `app/views/pub/console/parts/indicators/_body.js.erb:162-192`.

> Nota: corrige D-92 nesta capability (legado: a URL era espelhada por `replaceState`, sem entrada de historico — o botao Voltar sai do console).

#### Scenario: Abrir edicao por URL
- **GIVEN** a URL de edicao de um indicador
- **WHEN** ela e aberta em uma aba nova
- **THEN** o formulario de edicao abre com o indicador carregado

#### Scenario: Voltar fecha o formulario
- **GIVEN** o formulario de edicao aberto a partir da lista
- **WHEN** o usuario aciona Voltar no navegador
- **THEN** o formulario fecha e a lista reaparece — sem sair da area do console

### Requirement: FE-318 — Restricao somente-leitura na tela de indicadores
A tela SHALL ocultar as acoes de escrita para usuario somente-leitura, e o servidor SHALL recusa-las. Fonte legada: `app/views/pub/console/parts/indicators/_body.html.erb:10-17`.

> Nota: corrige D-23 nesta capability (legado: **nada disso e reforcado no servidor** — esconder o botao era toda a protecao; ver BE-717).

#### Scenario: Chamada direta com permissao somente-leitura
- **GIVEN** um usuario somente-leitura
- **WHEN** ele chama diretamente a criacao, edicao ou exclusao de indicador
- **THEN** a resposta e 403

### Requirement: FE-319 — Tela de indicadores especificos do projeto
A tela SHALL listar os indicadores conectaveis e conectados do projeto selecionado, com seletor de projeto explicito. Fonte legada: `app/views/pub/console/parts/indicator_connections/_body.html.erb`, `_body.js.erb`.

> Nota: corrige a dependencia do projeto padrao (legado: o escopo e sempre o projeto padrao do usuario, **fixado no atributo do HTML e na URL do proxy** — nao ha seletor de projeto, e quem nao tem projeto padrao quebra em `current_user.default_project.id`) e a busca inacessivel (legado: existe listener de busca mas **o campo nao existe no HTML**).

#### Scenario: Usuario sem projeto padrao
- **GIVEN** um usuario sem projeto padrao definido
- **WHEN** ele abre a tela
- **THEN** a tela pede que ele selecione um projeto, em vez de falhar

#### Scenario: Busca utilizavel
- **GIVEN** um projeto com muitos indicadores
- **WHEN** o usuario digita um termo
- **THEN** o campo de busca existe e a lista e filtrada no servidor

### Requirement: FE-320 — Conectar e desconectar indicador global do projeto
A tela SHALL permitir ligar e desligar um indicador global do projeto por controle de alternancia, com feedback. Fonte legada: `app/views/pub/console/parts/indicator_connections/list/_widget.js.erb:22-93`.

> Nota: corrige o bloqueio permanente (legado: a protecao contra duplo envio bloqueia o **segundo** clique **para sempre** enquanto o item nao for re-renderizado) e a concordancia da mensagem ("a relacao ... foi ativado").

#### Scenario: Alternar duas vezes
- **GIVEN** um indicador global desconectado
- **WHEN** o usuario o conecta e em seguida o desconecta
- **THEN** as duas operacoes funcionam, com feedback claro em cada uma

#### Scenario: Falha da operacao
- **GIVEN** a operacao falha no servidor
- **WHEN** a resposta chega
- **THEN** o controle volta ao estado anterior e a mensagem explica a falha

### Requirement: FE-321 — Acoes do indicador especifico na tela de conexoes
A tela SHALL oferecer editar, ativar ou desativar e excluir para indicadores especificos, com confirmacao na exclusao. Fonte legada: `app/views/pub/console/parts/indicator_connections/list/_widget.html.erb:25-50`, `list/_widget.js.erb:95-165`.

> Nota: corrige D-66 na UI (legado: a exclusao aqui **nao tem dialogo de confirmacao**, ao contrario da lista global, e apaga o indicador **e todos os seus lancamentos**) e as mensagens com erro de digitacao e concordancia ("deasativado", "Falhou ao ativado/deasativado o indicador", rotulo "desativar" em minuscula).

#### Scenario: Exclusao pede confirmacao
- **GIVEN** um indicador especifico com lancamentos
- **WHEN** o usuario aciona excluir nesta tela
- **THEN** a mesma confirmacao de FE-315 e exibida, informando o que sera perdido

#### Scenario: Mensagens corretas
- **GIVEN** qualquer acao desta tela
- **WHEN** a mensagem de resultado aparece
- **THEN** ela esta escrita corretamente e concorda com o objeto da acao

### Requirement: FE-322 — Estado visual de indicador inativo
As telas de indicador SHALL indicar visualmente quando um indicador esta inativo. Fonte legada: `app/views/pub/console/parts/indicator_connections/list/_widget.html.erb:4`.

> Nota: corrige a inconsistencia entre telas (legado: o estado inativo so aparece na tela de conexoes; na lista global **nao ha nenhuma indicacao**, embora o estado valha para todos os indicadores).

#### Scenario: Inativo na lista global
- **GIVEN** um indicador global desativado
- **WHEN** o catalogo global e aberto
- **THEN** ele aparece marcado como inativo, com a mesma linguagem visual da tela de conexoes

### Requirement: FE-323 — Explicacao da restricao de permissao
A interface SHALL explicar por que uma acao esta indisponivel, em vez de apenas ocultar o controle. Fonte legada: `app/views/pub/console/parts/indicator_connections/list/_widget.js.erb:25-31`.

#### Scenario: Acao bloqueada por permissao
- **GIVEN** um usuario somente-leitura
- **WHEN** ele aciona um controle de escrita
- **THEN** a interface informa "Voce nao possui permissao para alterar o estado do indicador"

### Requirement: FE-324 — Tela da grade de lancamentos
A grade SHALL apresentar os lancamentos do projeto por indicador e periodo, com filtros ao lado e rotulo distinguivel do catalogo. Fonte legada: `app/views/pub/console/parts/indicator_entries/_body.html.erb`, `_body.js.erb`.

> Nota: corrige o rotulo ambiguo (legado: a secao se chama **"Indicadores"**, o mesmo rotulo da tela de cadastro — dois itens de menu com o mesmo nome em grupos diferentes) e a busca inacessivel (legado: ha listener de busca **sem campo correspondente no HTML**). Corrige tambem a ausencia de estado de erro.

#### Scenario: Rotulos distintos
- **GIVEN** a navegacao do console
- **WHEN** as duas areas de indicador aparecem
- **THEN** cada uma tem um rotulo distinto e inequivoco

#### Scenario: Falha de carga
- **GIVEN** a requisicao da grade falha
- **WHEN** a resposta chega
- **THEN** um estado de erro e exibido com opcao de tentar novamente

### Requirement: FE-325 — Filtros da grade de lancamentos
A grade SHALL oferecer filtros por indicador, mes e ano, com os filtros lembrados entre visitas. Fonte legada: `app/views/pub/console/parts/indicator_entries/_body.html.erb:11-29`; helpers `app/helpers/application_helper.rb:55-69`.

> Nota: corrige a ausencia de persistencia (legado: os filtros nao sao lembrados entre visitas).

#### Scenario: Opcoes dos filtros
- **GIVEN** a grade aberta
- **WHEN** os filtros sao exibidos
- **THEN** o filtro de indicador lista apenas os indicadores ativos do projeto em ordem alfabetica com a opcao "Todos"; o de mes lista os 12 meses em pt-BR com "Todos"; e o de ano cobre a faixa de cinco anos antes ate cinco depois do ano atual, com o ano atual selecionado

#### Scenario: Filtros lembrados
- **GIVEN** o usuario filtrou por um indicador e um ano e saiu da tela
- **WHEN** ele volta
- **THEN** os filtros escolhidos sao restaurados

### Requirement: FE-326 — Grade de ano inteiro
No modo de ano inteiro, a grade SHALL mostrar, para cada indicador, as doze linhas de mes com o valor lancado, distinguindo "nao lancado" de "lancado como zero". Fonte legada: `app/views/pub/console/parts/indicator_entries/list/_widget.html.erb:3-38`.

> Nota: corrige D-117 nesta capability (legado: meses nao lancados montam um lancamento em branco e exibem **`0`**, indistinguivel de um lancamento real de zero — o tratamento de "N/A" que existe no model nao e usado nesta tela).

#### Scenario: Mes nao lancado
- **GIVEN** um indicador sem lancamento em marco e com lancamento de valor zero em abril
- **WHEN** a grade e exibida
- **THEN** marco aparece vazio ou marcado como nao lancado, e abril aparece como zero — os dois estados sao visualmente distintos

#### Scenario: Instrucao do indicador
- **GIVEN** um indicador com instrucao cadastrada
- **WHEN** o card e expandido
- **THEN** a instrucao aparece acima da grade de meses

### Requirement: FE-327 — Grade de mes unico
No modo de mes selecionado, a grade SHALL mostrar uma linha por indicador, com as mesmas informacoes do modo de ano inteiro. Fonte legada: `app/views/pub/console/parts/indicator_entries/list/_widget.html.erb:39-63`.

> Nota: corrige a inconsistencia entre modos (legado: no modo de mes unico a instrucao do indicador **nao e exibida**, porque o bloco expansivel so existe no ramo de doze meses).

#### Scenario: Instrucao disponivel nos dois modos
- **GIVEN** um indicador com instrucao
- **WHEN** o usuario alterna entre ano inteiro e mes unico
- **THEN** a instrucao continua acessivel nos dois modos

### Requirement: FE-328 — Entrada e formatacao do valor monetario
O campo de valor SHALL aceitar entrada monetaria em formato pt-BR, com no maximo duas casas decimais e sinal negativo apenas na primeira posicao. Fonte legada: `app/views/pub/console/parts/indicator_entries/list/_widget.js.erb:5-61`.

> Nota: corrige a dependencia de recurso de navegador (legado: a regra usa lookbehind em expressao regular, que quebra em navegadores antigos e deixa o campo sem validacao nenhuma nesses casos).

#### Scenario: Mais de um separador decimal
- **GIVEN** o usuario digita dois separadores decimais
- **WHEN** o campo valida
- **THEN** a interface avisa que so e necessario um separador e o valor nao e corrompido

#### Scenario: Valor negativo
- **GIVEN** o usuario digita um valor negativo
- **WHEN** o campo perde o foco
- **THEN** o valor e aceito e formatado como negativo

### Requirement: FE-329 — Gravacao automatica do lancamento
A grade SHALL gravar o lancamento ao concluir a edicao da celula, com feedback de sucesso e de erro. Fonte legada: `app/views/pub/console/parts/indicator_entries/list/_widget.js.erb:63-128`.

> Nota: corrige o **pior estado de interface da capability** (legado: **nao ha tratamento de erro** na gravacao automatica — se o servidor responde 422, por exemplo por duplicidade de mes, o campo simplesmente destrava e o usuario **acredita que salvou**) e o bloqueio permanente (legado: a marca de "ja enviado" **nunca e limpa**, entao apos a primeira gravacao o mesmo campo **nao envia de novo** ate a lista recarregar).

#### Scenario: Falha de gravacao e visivel
- **GIVEN** o servidor recusa a gravacao de uma celula
- **WHEN** a resposta chega
- **THEN** a celula e marcada como nao salva, o motivo e exibido e o valor digitado e preservado

#### Scenario: Edicoes sucessivas na mesma celula
- **GIVEN** uma celula ja gravada uma vez
- **WHEN** o usuario altera o valor de novo
- **THEN** a nova gravacao acontece normalmente, sem recarregar a tela

#### Scenario: Cor por sinal do valor
- **GIVEN** valores positivo, negativo e zero
- **WHEN** eles sao exibidos
- **THEN** a cor do texto distingue os tres casos

### Requirement: DB-310 — Modelo de dados de indicador
A tabela de indicadores SHALL guardar titulo, chave, tipo de valor, escopo de projeto e estado ativo, com indices e chave estrangeira. Fonte legada: `db/migrate/20211026165448_create_indicators.rb`; `20211029172624_add_project_to_indicator.rb`; `20220223145902_add_is_active_to_indicator.rb`; `app/models/indicator.rb`.

> Nota: corrige o modelo (legado: **nenhum indice alem da chave primaria e nenhuma chave estrangeira**; `project_id` e inteiro solto; `is_active` e inteiro em que so `1` conta como ativo, com valores fora de 0 e 1 possiveis; e a chave **nao e unica**). Corrige tambem D-66 no dado: a associacao com os lancamentos deixa de ser `delete_all`.

#### Scenario: Escopo por projeto integro
- **GIVEN** um indicador especifico apontando para um projeto
- **WHEN** um projeto inexistente e referenciado
- **THEN** o banco recusa pela chave estrangeira

#### Scenario: Estado ativo binario
- **GIVEN** a migracao de dados
- **WHEN** valores fora de 0 e 1 sao encontrados na coluna de estado ativo
- **THEN** o dry-run os reporta antes da conversao para booleano

> AMBIGUIDADE: no legado o titulo esta **sempre em caixa alta e sem acentos**, e os acentos originais foram perdidos de forma irreversivel. Confirmar com o tech lead se o ai9 preserva o texto como esta ou se ha uma lista de titulos a re-humanizar manualmente.

### Requirement: DB-311 — Modelo de dados do lancamento
A tabela de lancamentos SHALL guardar projeto, indicador, periodo, valor e autoria, com indice unico por periodo e indices para as consultas da grade. Fonte legada: `db/migrate/20211027140815_create_indicator_entries.rb`; `app/models/indicator_entry.rb`.

> Nota: corrige a condicao de corrida (legado: a unicidade de mes por ano, projeto e indicador e **so de aplicacao**, sem indice unico), a ausencia de indices para as consultas da grade, e a falta de restricao de faixa em mes e ano. Corrige tambem a semantica de autoria: no legado o campo de usuario e o **ultimo editor**, nao o autor.

#### Scenario: Duplicata recusada pelo banco
- **GIVEN** um lancamento de janeiro de 2025 para um par projeto e indicador
- **WHEN** outra linha com o mesmo periodo e inserida
- **THEN** o banco recusa por indice unico composto

#### Scenario: Faixa de mes validada na migracao
- **GIVEN** registros legados com mes fora da faixa de 1 a 12
- **WHEN** a migracao de dados executa
- **THEN** o dry-run os reporta antes de qualquer insercao

#### Scenario: Ausencia de linha e o unico "nao lancado"
- **GIVEN** um mes sem lancamento
- **WHEN** a grade e consultada
- **THEN** nao existe linha para aquele periodo — o "nao lancado" nunca e representado por um valor zero gravado

### Requirement: DB-312 — Modelo de dados da conexao indicador-projeto
A tabela de conexoes SHALL ligar projeto e indicador com indice unico e chaves estrangeiras. Fonte legada: `db/migrate/20211026184044_create_project_indicator_connections.rb`; `app/models/project_indicator_connection.rb`.

> Nota: corrige o modelo (legado: **sem indices e sem chaves estrangeiras**; a unicidade e so de aplicacao) e registra que o `permit` do controller aceita um campo de estado ativo que **nao existe nesta tabela** e e descartado em silencio — o campo nao e portado.

#### Scenario: Conexao duplicada recusada
- **GIVEN** uma conexao entre um projeto e um indicador
- **WHEN** outra linha com o mesmo par e inserida
- **THEN** o banco recusa por indice unico

#### Scenario: Regra de conexao automatica preservada
- **GIVEN** um indicador especifico de projeto sendo criado
- **WHEN** ele e salvo
- **THEN** a conexao com o projeto e criada automaticamente; um indicador global so se conecta pelo controle de alternancia

### Requirement: DB-313 — Conteudo rico de indicador e de contrato
O conteudo rico da instrucao do indicador SHALL ser migrado junto com o registro, sem perda nem corrupcao de codificacao. Fonte legada: `db/migrate/20190425020855_create_action_text_tables.action_text.rb`; `app/models/indicator.rb:10`; `app/models/contract.rb:11`.

> Nota: ponto critico da migracao — os textos de instrucao dos indicadores **e os textos juridicos completos dos contratos** vivem na mesma tabela polimorfica de conteudo rico, e nao nas tabelas de indicador e de contrato. Qualquer exportacao que a ignore **perde o conteudo dos contratos**. Os contratos vieram de HTML seedado e possivelmente escapado, o que exige validacao item a item da codificacao (liga com BE-345 e FE-331 da capability de contratos).

#### Scenario: Conteudo migrado com codificacao correta
- **GIVEN** instrucoes de indicador e textos de contrato com acentuacao e marcacao
- **WHEN** a migracao executa
- **THEN** cada conteudo e conferido item a item e nenhum termina com escape duplicado ou caractere corrompido

### Requirement: OPS-310 — Ausencia de rotinas automaticas de indicadores
O sistema SHALL nao ter rotina automatica de indicadores. Fonte legada: `app/jobs/` (diretorio vazio no legado); nenhuma referencia a indicador fora de models, controllers, views e helpers.

> Nota de escopo (DEC-09): nao existe lembrete de lancamento pendente, fechamento de mes, importacao, exportacao nem API publica de indicadores no legado, e nada disso e criado. Todo lancamento e manual, celula a celula.

#### Scenario: Nenhuma automacao herdada
- **GIVEN** a configuracao de tarefas agendadas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao ha nenhuma tarefa relacionada a indicadores

### Requirement: OPS-311 — Reprocessamento de normalizacao de indicadores
O sistema SHALL oferecer uma rotina operacional de reprocessamento de indicadores, idempotente e registrada em log. Fonte legada: `app/models/indicator.rb:88-92`.

> Nota: corrige a rotina informal (legado: `Indicator.fix_titles` re-salva **todos** os indicadores para forcar normalizacao e propagacao, **sem rake task, sem log e sem idempotencia declarada**, exigindo acesso a console em producao — em base grande e um update em massa por indicador).

#### Scenario: Reprocessamento seguro
- **GIVEN** a rotina de reprocessamento
- **WHEN** ela e executada duas vezes seguidas
- **THEN** o resultado e o mesmo e o log registra quantos registros foram tocados

### Requirement: OPS-312 — Chave de integracao do indicador
O sistema SHALL manter a chave de integracao do indicador com formato estavel. Fonte legada: `app/models/indicator.rb:7,44`; rotulo em `app/controllers/pub/indicators_controller.rb:136`.

#### Scenario: Chave estavel
- **GIVEN** um indicador com chave gerada
- **WHEN** o titulo e alterado
- **THEN** a chave permanece a mesma, para nao quebrar um consumidor externo

> AMBIGUIDADE: D-71 — a chave e obrigatoria, gerada automaticamente e exposta na interface como "Chave de Integracao", mas **nenhum codigo do legado a le** — nao ha API, job nem exportacao que a consuma. Pode haver um consumidor **fora do repositorio** (BI, planilha, ETL). Confirmar com o tech lead antes de mudar o formato ou torna-la unica.

### Requirement: OPS-313 — Politica de retencao dos lancamentos
O sistema SHALL preservar a serie de lancamentos diante de qualquer exclusao de indicador, com trilha de auditoria. Fonte legada: `app/models/indicator.rb:4`.

> Nota: corrige D-66 (legado: a exclusao apaga toda a serie via remocao em massa, **sem callbacks, sem remocao logica, sem backup, sem confirmacao especifica na interface e sem trilha de auditoria de exclusoes**).

#### Scenario: Auditoria da exclusao
- **GIVEN** a exclusao de um indicador
- **WHEN** ela e concluida
- **THEN** o evento registra quem excluiu, quando, qual indicador e quantos lancamentos ficaram retidos

### Requirement: OPS-314 — Cobertura de testes da capability
A capability SHALL ter testes automatizados cobrindo os comportamentos desta especificacao. Fonte legada: o repositorio legado **nao tem** diretorio de testes.

> Nota: corrige a ausencia total de cobertura (legado: zero testes para os cinco models, quatro controllers e cerca de quarenta telas da unidade — toda a verificacao de paridade depende do comportamento observado e descrito aqui).

#### Scenario: Cobertura das regras criticas
- **GIVEN** a suite de testes do ai9
- **WHEN** ela e executada
- **THEN** ha teste para unicidade de titulo, para a nao perda de lancamentos na exclusao de indicador e para a gravacao da grade com falha do servidor

### Requirement: BE-707 — Listar indicadores conectaveis ao projeto
O sistema SHALL listar os indicadores conectaveis a um projeto — globais mais os especificos daquele projeto — com filtro por texto e paginacao. Fonte legada: `app/controllers/pub/project_indicator_connections_controller.rb:19-40`; rota `config/routes.rb:92-93`.

> Nota: corrige D-67 (legado: `params[:owner_type].constantize` e `params[:connection_type].constantize` fazem **carga de classe a partir de entrada do usuario** — caminho para execucao de codigo arbitrario e negacao de servico; no ai9 o tipo vem de allowlist, nunca de `constantize`) e o filtro morto (legado: os ramos de tratamento so casam com outros tipos, entao com indicador **o parametro de busca e ignorado e nao ha limite nem deslocamento aplicados** — a lista vem inteira).

#### Scenario: Tipo fora da allowlist
- **GIVEN** uma requisicao com um tipo de recurso arbitrario
- **WHEN** ela e processada
- **THEN** a resposta e 400 e nenhuma classe e carregada a partir do parametro

#### Scenario: Filtro por texto funciona
- **GIVEN** um projeto com 200 indicadores conectaveis
- **WHEN** o usuario busca por um termo
- **THEN** apenas os correspondentes sao retornados, paginados e com total

### Requirement: BE-708 — Endpoint de conexoes sem escopo
O sistema SHALL nao expor um endpoint de listagem de indicadores sem escopo de projeto. Fonte legada: `app/controllers/pub/project_indicator_connections_controller.rb:42-64`; rota `config/routes.rb:94`.

> Nota: corrige o vazamento entre projetos (legado: este endpoint usa a colecao completa de indicadores, **sem escopo algum**, e responde **sem verificacao de autorizacao**; nenhuma tela do console o chama hoje, mas ele esta acessivel — mesma familia de D-01 e D-110).

#### Scenario: Endpoint ausente
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao existe endpoint de indicadores sem escopo de projeto, e a listagem passa exclusivamente por BE-707

### Requirement: BE-709 — Conectar indicadores globais ao projeto
O sistema SHALL conectar um ou mais indicadores globais a um projeto, reportando o resultado de cada um. Fonte legada: `app/controllers/pub/project_indicator_connections_controller.rb:67-86`.

> Nota: corrige o resultado agregado incorreto (legado: os nomes de coluna sao montados por manipulacao de string sobre a entrada do usuario; o retorno da gravacao **nao e verificado**; e o erro **nao e agregado** — apenas o ultimo item do laco e inspecionado, entao conectar tres indicadores com uma falha pode **reportar sucesso**) e a ausencia de verificacao de que o usuario pertence ao projeto.

#### Scenario: Resultado por item
- **GIVEN** uma conexao em lote de tres indicadores, sendo um deles ja conectado
- **WHEN** a operacao termina
- **THEN** o resultado informa quais foram conectados e qual falhou, com o motivo

#### Scenario: Projeto fora do escopo do usuario
- **GIVEN** uma requisicao apontando para um projeto ao qual o usuario nao tem acesso
- **WHEN** ela e processada
- **THEN** a resposta e 403

### Requirement: BE-710 — Desconectar indicador global do projeto
O sistema SHALL desconectar um indicador global de um projeto sem apagar os lancamentos ja realizados. Fonte legada: `app/controllers/pub/project_indicator_connections_controller.rb:87-91,172-176`.

> Nota: corrige o 500 por par inexistente (legado: se a conexao nao existe, o codigo chama a remocao sobre um valor nulo — `NoMethodError`) e a montagem de consulta a partir de entrada do usuario com escape manual de nome de coluna.

#### Scenario: Desconexao preserva o historico
- **GIVEN** um indicador conectado com 24 lancamentos no projeto
- **WHEN** ele e desconectado
- **THEN** ele some da grade do projeto e os 24 lancamentos permanecem no banco

#### Scenario: Reconexao recupera o historico
- **GIVEN** o mesmo indicador desconectado
- **WHEN** ele e reconectado ao projeto
- **THEN** os lancamentos anteriores voltam a aparecer na grade

#### Scenario: Par inexistente
- **GIVEN** um pedido de desconexao de um par que nao existe
- **WHEN** ele e processado
- **THEN** a resposta e 404

### Requirement: BE-711 — Excluir indicador especifico pela tela de conexoes
O sistema SHALL excluir um indicador especifico de projeto pela tela de conexoes, com as mesmas garantias de BE-318. Fonte legada: `app/controllers/pub/project_indicator_connections_controller.rb:94-104`.

> Nota: corrige D-66 e o ramo defeituoso (legado: quando o indicador e **global**, o codigo tenta adicionar erro sobre um valor que pode ser uma **colecao**, nao um registro, e estoura; alem disso ha um `FIXME` no proprio codigo registrando que uma correcao anterior tratava de um identificador errado que **excluia o indicador errado**; e a exclusao dispara a remocao em massa dos lancamentos).

#### Scenario: Indicador global nao e excluivel aqui
- **GIVEN** um indicador global listado na tela de conexoes
- **WHEN** a exclusao e tentada
- **THEN** a operacao e recusada com mensagem clara, sem erro interno

#### Scenario: Exclusao do indicador correto
- **GIVEN** varios indicadores especificos no projeto
- **WHEN** um deles e excluido
- **THEN** apenas o indicador escolhido e afetado, e seus lancamentos sao preservados conforme BE-318

### Requirement: BE-712 — Rota de indice de conexoes
O sistema SHALL nao expor rota de indice de conexoes sem tela. Fonte legada: `app/controllers/pub/project_indicator_connections_controller.rb:7-9`; rota `config/routes.rb:92`.

> Nota: corrige D-62 nesta capability (legado: a action renderiza um template que **nao existe** — 500; a tela real e a do console).

#### Scenario: Rota morta ausente
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** a rota de indice de conexoes nao existe

### Requirement: BE-713 — Rota de edicao de conexao
O sistema SHALL nao expor rota de edicao de conexao sem tela. Fonte legada: `app/controllers/pub/project_indicator_connections_controller.rb:11-17`.

> Nota: corrige D-62 nesta capability (legado: a action renderiza um diretorio de views que **nao existe** — 500).

#### Scenario: Rota morta ausente
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** a rota de edicao de conexao nao existe; a conexao e alterada pelos comandos de conectar e desconectar

### Requirement: BE-714 — Rota de exclusao direta de conexao
O sistema SHALL nao expor rota de exclusao direta de conexao sem tela. Fonte legada: `app/controllers/pub/project_indicator_connections_controller.rb:119-168`.

> Nota: corrige D-62 nesta capability (legado: a action renderiza um diretorio inexistente e, antes disso, opera sobre uma variavel que **nunca e definida** — `NoMethodError`; as actions de criacao e atualizacao do mesmo controller estao **inteiramente comentadas**).

#### Scenario: Rota morta ausente
- **GIVEN** a lista de rotas do ai9
- **WHEN** ela e inspecionada
- **THEN** a rota de exclusao direta de conexao nao existe

### Requirement: BE-715 — Tipo de valor do indicador
O sistema SHALL suportar o tipo de valor do legado — dinheiro em reais — como catalogo declarado. Fonte legada: `app/models/indicator.rb:24-35`; `app/models/indicator_entry.rb:17-19,29-39`.

> Nota de escopo (DEC-09): o legado tem **um unico** tipo de valor, "Dinheiro", como texto literal e nao enumeracao; o seletor foi omitido do cadastro exatamente por isso. Nao ha unidade percentual, quantidade nem casas decimais configuraveis, e nada disso e inventado.

#### Scenario: Formatacao monetaria
- **GIVEN** um lancamento com valor
- **WHEN** ele e exibido
- **THEN** o valor aparece formatado em reais

#### Scenario: Tipo desconhecido
- **GIVEN** um registro legado com tipo de valor fora do catalogo
- **WHEN** ele e exibido
- **THEN** o valor aparece sem formatacao especifica e o caso e registrado — o legado devolvia o valor cru silenciosamente

> AMBIGUIDADE: confirmar com o tech lead se o ai9 ja deve nascer suportando percentual e quantidade, ou replicar o "so dinheiro" do legado.

### Requirement: BE-716 — Consultas de lancamento por periodo e por indicador
O sistema SHALL oferecer as consultas de lancamento que o legado tem: lancamento de um mes para um indicador, lancamentos de um mes e lancamentos de um indicador. Fonte legada: `app/models/project.rb:14-16,424-446`.

> Nota de escopo (DEC-09): **calculo de variacao mes a mes ou ano a ano, percentual, acumulado, media e grafico NAO existem no legado** e ficam fora do escopo. Duas das quatro consultas do legado (lancamentos de um mes, em suas duas formas) **nao tem nenhum consumidor** no codigo atual. Corrige tambem a materializacao de lancamentos em branco: o legado cria em memoria um lancamento de valor zero para os meses nao lancados, o que apaga a distincao entre "nao lancado" e "zero" (ver FE-326).

#### Scenario: Consulta de um mes para um indicador
- **GIVEN** um projeto, um indicador e um periodo
- **WHEN** a consulta e feita
- **THEN** ela devolve o lancamento daquele periodo, ou a indicacao explicita de que nao ha lancamento

#### Scenario: Nenhuma agregacao inventada
- **GIVEN** a superficie de consultas do ai9
- **WHEN** ela e inspecionada
- **THEN** nao ha endpoint de variacao, acumulado, media ou grafico de indicador

### Requirement: BE-717 — Autorizacao de indicadores e lancamentos
Os endpoints de indicador, lancamento e conexao SHALL validar papel e permissao no servidor. Fonte legada: `app/helpers/application_helper.rb:136-142`; `app/decorators/models/ability_factory_decorator.rb:3,30`; gates de view em `indicators/_body.html.erb:10-17` e `indicator_entries/list/_widget.html.erb:24,29`.

> Nota: corrige D-23 e D-17 nesta capability (legado: **toda a autorizacao e de view** — nenhum dos tres controllers tem verificacao de permissao, entao qualquer usuario autenticado pode criar indicador, conectar indicador a projeto ou lancar valor chamando o endpoint direto; a permissao somente-leitura apenas desabilita botoes e marca o campo de valor como nao editavel).

#### Scenario: Escrita sem papel
- **GIVEN** um usuario autenticado sem papel administrativo, de gestao ou de operador
- **WHEN** ele chama diretamente a criacao de indicador ou a conexao com projeto
- **THEN** a resposta e 403

#### Scenario: Somente-leitura no servidor
- **GIVEN** um usuario com permissao somente-leitura
- **WHEN** ele chama diretamente a gravacao de um lancamento
- **THEN** a resposta e 403 e nada e gravado

#### Scenario: Leitura da grade por membro do projeto
- **GIVEN** um usuario membro de um projeto sem papel administrativo
- **WHEN** ele abre a grade de lancamentos daquele projeto
- **THEN** a leitura e permitida

### Requirement: FE-718 — Modo somente-leitura na grade de lancamentos
A grade SHALL indicar por que os campos estao bloqueados para usuario somente-leitura. Fonte legada: `app/views/pub/console/parts/indicator_entries/list/_widget.html.erb:24-34,49-60`.

> Nota: corrige a restricao muda (legado: o campo fica nao editavel, com a formatacao e as cores intactas, **sem nenhuma mensagem explicando**, e o servidor **nao impede** o envio).

#### Scenario: Explicacao visivel
- **GIVEN** um usuario somente-leitura na grade
- **WHEN** ele tenta editar uma celula
- **THEN** a interface informa que ele tem acesso apenas de leitura

### Requirement: FE-719 — Expansao do card de indicador na grade
A grade SHALL permitir expandir e recolher o card de cada indicador. Fonte legada: `app/views/pub/console/parts/indicator_entries/list/_widget.js.erb:129-140`.

> Nota: corrige a interacao ausente no modo de mes unico (legado: nesse modo nao ha titulo clicavel, entao a expansao simplesmente nao existe — ver FE-327).

#### Scenario: Expansao exclusiva
- **GIVEN** varios indicadores na grade de ano inteiro
- **WHEN** o usuario expande um card
- **THEN** os demais se recolhem

#### Scenario: Expansao no modo de mes unico
- **GIVEN** a grade no modo de mes unico
- **WHEN** o usuario aciona a expansao de um indicador
- **THEN** a instrucao e os detalhes aparecem, com a mesma interacao do modo de ano inteiro
