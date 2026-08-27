# Structured Operations Specification

## Purpose
Operações estruturadas do Safegold: o cadastro das operações de um projeto (capital,
saldo inicial, datas, taxa acordada) e seu catálogo de tipos; as remunerações, que
definem o percentual cobrado por tipo de operação em cada projeto e alimentam a fórmula
do recibo; e os catálogos de recursos (`resource_kinds` e `resource_sources`) usados na
classificação de recebíveis.

## Requirements

### Requirement: BE-280 — Buscar e listar operações estruturadas
O sistema SHALL se comportar conforme os cenários desta seção.
`GET /structured_operations/search` lista as operações do projeto corrente, com filtros,
ordenação e paginação. Fonte legada:
`app/controllers/pub/structured_operations_controller.rb:15-25`; `config/routes.rb:104`.

#### Scenario: Listagem escopada ao projeto corrente
- **GIVEN** operações em `P1` e `P2` e um usuário do projeto `P1`
- **WHEN** a busca é executada
- **THEN** só as operações de `P1` são retornadas

#### Scenario: Busca por id não escapa do projeto
- **GIVEN** uma operação do projeto `P2`
- **WHEN** o usuário de `P1` informa o identificador dessa operação na busca
- **THEN** o resultado vem vazio e nenhum dado de `P2` é exposto
> Nota: corrige D-76 (comportamento legado: o parâmetro descartava todo o escopo anterior e consultava diretamente pelo id, permitindo leitura cross-project a qualquer usuário autenticado)

#### Scenario: Operação com relacionamento ausente continua visível
- **GIVEN** uma operação cujo portador foi removido
- **WHEN** a lista é montada
- **THEN** ela aparece na lista, com o portador sinalizado como ausente
> Nota: corrige comportamento legado (os três `INNER JOIN` do escopo base faziam a operação desaparecer da lista em silêncio)

### Requirement: BE-281 — Filtros combináveis da busca de operações
O sistema SHALL se comportar conforme os cenários desta seção.
Empresa, portador, tipo de operação e termo textual recortam a lista, e cada filtro em
branco é ignorado. Fonte legada:
`app/controllers/pub/structured_operations_controller.rb:27-30`.

#### Scenario: Filtros combinados
- **GIVEN** operações de várias empresas e tipos
- **WHEN** a busca informa empresa e tipo
- **THEN** só as operações que casam com os dois são retornadas

#### Scenario: Escopo da busca textual
- **GIVEN** operações cujo portador ou título contêm "Alfa", e uma operação com contrato "ALFA-2026"
- **WHEN** o usuário busca por "alfa"
- **THEN** as três são retornadas
> Nota: corrige comportamento legado (a busca só casava título do portador e título da operação, apesar de o número do contrato e o nome da empresa aparecerem na tabela)

#### Scenario: Filtro em branco
- **GIVEN** um filtro enviado como texto vazio
- **WHEN** a busca é executada
- **THEN** ele é ignorado

### Requirement: BE-282 — Filtro de período da busca de operações
O sistema SHALL se comportar conforme os cenários desta seção.
O período seleciona as operações vigentes no intervalo informado, comparando o vencimento
com o início e a emissão com o fim. Fonte legada:
`app/controllers/pub/structured_operations_controller.rb:31`, `:140-152`.

#### Scenario: Operação vigente no período
- **GIVEN** uma operação emitida em 01/02/2026 com vencimento em 30/04/2026
- **WHEN** a busca informa o período de 01/03/2026 a 31/03/2026
- **THEN** ela é retornada, porque o intervalo do período intersecta o intervalo da operação
> AMBIGUIDADE: D-75 — o cruzamento é invertido em relação à leitura intuitiva de "operações do período" (o início é comparado com o vencimento e o fim com a emissão); pode ser intencional ("operações vigentes no período") ou erro; precisa de validação de negócio antes de portar

#### Scenario: Operação encerrada antes do período
- **GIVEN** uma operação com vencimento em 31/01/2026
- **WHEN** a busca informa o período de 01/03/2026 a 31/03/2026
- **THEN** ela não é retornada

#### Scenario: Período não informado
- **GIVEN** uma busca sem data inicial nem final
- **WHEN** ela é executada
- **THEN** nenhuma restrição de período é aplicada, e operações sem emissão ou sem vencimento também aparecem
> Nota: corrige comportamento legado (o filtro era sempre aplicado com as datas-sentinela, e a comparação sobre datas nulas excluía essas operações mesmo sem filtro do usuário)

#### Scenario: Data malformada
- **GIVEN** um período com data inválida
- **WHEN** a busca é executada
- **THEN** a resposta é um erro de validação legível, e não um erro interno

### Requirement: BE-283 — Ordenação multi-coluna da busca de operações
O sistema SHALL se comportar conforme os cenários desta seção.
A lista aceita ordenação acumulada por título, empresa, tipo, portador, contrato,
emissão, capital, saldo, vencimento e taxa. Fonte legada:
`app/controllers/pub/structured_operations_controller.rb:33-42`;
`app/models/structured_operation.rb:60-107`.

#### Scenario: Ordenação por duas chaves
- **GIVEN** a busca com ordenação por portador ascendente e emissão descendente
- **WHEN** ela é executada
- **THEN** o resultado vem ordenado por portador e, dentro de cada portador, por emissão descendente

#### Scenario: Chave de ordenação desconhecida
- **GIVEN** uma chave fora da lista aceita
- **WHEN** a busca é executada
- **THEN** ela é ignorada e a ordenação padrão é aplicada
> Nota: corrige comportamento legado (chave desconhecida produzia `NoMethodError` e devolvia 500 — ver OPS-288)

#### Scenario: Busca sem ordenação informada
- **GIVEN** uma busca sem chaves de ordenação
- **WHEN** ela é executada
- **THEN** o resultado vem em ordem determinística e paginado
> Nota: corrige D-20 (comportamento legado: sem chaves de ordenação nem a ordenação nem o limite e o deslocamento eram aplicados, e a lista voltava inteira em ordem indefinida)

### Requirement: BE-284 — Paginação e contagem total da busca de operações
O sistema SHALL se comportar conforme os cenários desta seção.
`l` e `o` limitam e deslocam o resultado, e a contagem informada é a do filtro. Fonte
legada: `app/controllers/pub/structured_operations_controller.rb:44`, `:117-125`.

#### Scenario: Total correto com paginação
- **GIVEN** 300 operações no projeto e uma busca com limite 50
- **WHEN** ela é executada
- **THEN** vêm 50 operações e o total informado é 300
> Nota: corrige D-20 (comportamento legado: o total era contado depois de aplicar limite e deslocamento, então nunca passava do tamanho da página e a navegação calculava limites errados)

#### Scenario: Limite acima do teto permitido
- **GIVEN** uma busca pedindo um limite muito alto
- **WHEN** ela é executada
- **THEN** o limite é reduzido ao teto máximo definido
> Nota: corrige comportamento legado (não havia teto — o cliente podia pedir qualquer limite, e o padrão sem parâmetro era mil registros)

### Requirement: BE-285 — Criar operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
`POST /structured_operations` cria a operação com o autor da sessão. Fonte legada:
`app/controllers/pub/structured_operations_controller.rb:69-82`, `:154-174`.

#### Scenario: Criação bem-sucedida
- **GIVEN** empresa, portador, tipo, emissão, vencimento, capital e taxa informados
- **WHEN** a operação é criada
- **THEN** ela é persistida com o autor da sessão, ignorando qualquer autor informado no payload

#### Scenario: Identificador informado no payload
- **GIVEN** um payload de criação que informa um identificador de registro
- **WHEN** a criação é submetida
- **THEN** o identificador é ignorado e um novo registro é criado
> Nota: corrige comportamento legado (o identificador estava entre os parâmetros permitidos na criação, abrindo caminho para sobrescrita de registro)

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** ele submete a criação diretamente à API
- **THEN** a requisição é recusada por autorização
> Nota: corrige D-17 (comportamento legado: a restrição existia apenas na interface)

### Requirement: BE-286 — Atualizar operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
A edição altera os dados da operação em uma única gravação, dentro do escopo do projeto.
Fonte legada: `app/controllers/pub/structured_operations_controller.rb:86-100`, `:132`.

#### Scenario: Edição com gravação única
- **GIVEN** uma operação existente
- **WHEN** a observação é alterada
- **THEN** a gravação ocorre uma única vez
> Nota: corrige comportamento legado (a ação chamava atualização e gravação em sequência, gerando escritas redundantes e reexecutando todos os callbacks)

#### Scenario: Operação de outro projeto
- **GIVEN** uma operação do projeto `P2`
- **WHEN** o usuário de `P1` submete a edição por identificador
- **THEN** a requisição é recusada por autorização
> Nota: corrige D-76 (comportamento legado: a busca do registro não tinha escopo de projeto, permitindo **escrita** cross-project)

### Requirement: BE-287 — Excluir operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
`DELETE /structured_operations/:id` remove a operação, exceto quando ela já tem recibo
emitido. Fonte legada: `app/controllers/pub/structured_operations_controller.rb:102-111`.

#### Scenario: Exclusão de operação sem recibo
- **GIVEN** uma operação sem recibo
- **WHEN** a exclusão é confirmada
- **THEN** ela é removida

#### Scenario: Exclusão barrada por recibo
- **GIVEN** uma operação com recibo emitido
- **WHEN** a exclusão é tentada
- **THEN** a resposta é um erro explicando o vínculo, e a operação permanece
> Nota: corrige D-24 (comportamento legado: o ternário degenerado respondia sucesso nos dois ramos, então a interface recarregava a lista como se tivesse excluído e a operação continuava lá)

#### Scenario: Operação de outro projeto
- **GIVEN** uma operação de outro projeto
- **WHEN** a exclusão é tentada por identificador
- **THEN** a requisição é recusada por autorização
> Nota: corrige D-76

### Requirement: BE-288 — Abrir o formulário de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
O formulário de cadastro e de edição é montado com as empresas, portadores e tipos ativos
do projeto. Fonte legada: `app/controllers/pub/console_controller.rb:206-231`;
`app/controllers/pub/structured_operations_controller.rb:49-67`.

#### Scenario: Formulário de nova operação
- **GIVEN** um projeto com empresas, portadores e tipos ativos
- **WHEN** o formulário é aberto
- **THEN** ele vem com a primeira empresa, o primeiro portador e o primeiro tipo ativo pré-selecionados, e com emissão e vencimento na data de hoje

#### Scenario: Somente tipos ativos são oferecidos
- **GIVEN** tipos de operação ativos e desativados
- **WHEN** o formulário é montado
- **THEN** apenas os tipos ativos são oferecidos

#### Scenario: Ações duplicadas do controller dedicado
- **GIVEN** as ações de novo e edição do controller dedicado, que não definem as variáveis exigidas pela tela
- **WHEN** o escopo do ai9 é definido
- **THEN** elas não existem, e o formulário é servido por um único caminho
> Nota: DEC-09 — as ações são comprovadamente quebradas no legado (a tela exige variáveis que elas não definem) e entram no ledger como `dropped` com evidência

### Requirement: BE-289 — Rotas REST mortas da unidade
O sistema SHALL se comportar conforme os cenários desta seção.
Cinco ações de índice e três de detalhe do legado apontam para templates inexistentes.
Fonte legada: `structured_operations_controller.rb:7-9`, `:11-13`;
`structured_operation_types_controller.rb:5-7`, `:41-47`; `remunerations_controller.rb:4-6`;
`resource_kinds_controller.rb:5-7`, `:27-33`; `resource_sources_controller.rb:5-7`, `:40-46`.

#### Scenario: Navegação servida por rotas reais
- **GIVEN** o ai9 em execução
- **WHEN** o usuário abre qualquer tela da unidade
- **THEN** ela é servida por uma rota real, e as ações mortas do legado não existem
> Nota: DEC-09 — nenhum dos templates existe no repositório legado; as rotas entram no ledger como `dropped` com evidência

### Requirement: BE-290 — Título padrão da operação
O sistema SHALL se comportar conforme os cenários desta seção.
Quando o título não é informado, a operação assume o título do portador. Fonte legada:
`app/models/structured_operation.rb:31-33`.

#### Scenario: Título derivado do portador
- **GIVEN** o portador "Banco Alfa" e o título em branco
- **WHEN** a operação é criada
- **THEN** `title = "Banco Alfa"`

#### Scenario: Portador inválido
- **GIVEN** um identificador de portador inexistente
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 dizendo que o portador é obrigatório ou inválido
> Nota: corrige comportamento legado (a derivação rodava antes da validação de presença e levantava `NoMethodError`, devolvendo 500 em vez da mensagem amigável)

### Requirement: BE-291 — Projeto derivado da empresa
O sistema SHALL se comportar conforme os cenários desta seção.
O projeto da operação é sempre o projeto da empresa escolhida, e não é informado pelo
usuário. Fonte legada: `app/models/structured_operation.rb:35-36`.

#### Scenario: Projeto derivado
- **GIVEN** uma empresa do projeto `P1` e um payload informando o projeto `P2`
- **WHEN** a operação é gravada
- **THEN** o projeto gravado é `P1`

#### Scenario: Empresa ausente ou inválida
- **GIVEN** uma gravação sem empresa
- **WHEN** ela é submetida
- **THEN** a resposta é 422 pela validação de presença, e não um erro interno
> Nota: corrige comportamento legado (a derivação acessava o projeto da empresa nula e levantava `NoMethodError` antes das validações)

#### Scenario: Troca de empresa move a operação de projeto
- **GIVEN** uma operação do projeto `P1` com recibo já emitido
- **WHEN** a empresa é trocada por uma do projeto `P2`
- **THEN** a alteração é recusada enquanto houver recibo emitido
> Nota: corrige comportamento legado (a troca movia a operação de projeto em silêncio, podendo invalidar remunerações e recibos já emitidos)

### Requirement: BE-292 — Saldo inicial e saldo corrente da operação
O sistema SHALL se comportar conforme os cenários desta seção.
O saldo inicial é armazenado sempre como valor negativo, e o saldo corrente é sempre
igual ao saldo inicial. Fonte legada: `app/models/structured_operation.rb:37-38`.

#### Scenario: Sinal do saldo inicial
- **GIVEN** o usuário informando saldo inicial de 50.000,00
- **WHEN** a operação é gravada
- **THEN** `original_balance = −50.000,00` e `balance = −50.000,00`
> Nota: DEC-02 — a normalização de sinal e a cópia do legado são replicadas para os totais baterem na verificação de paridade

#### Scenario: Qualquer edição reseta o saldo corrente
- **GIVEN** uma operação gravada com saldo inicial −50.000,00
- **WHEN** apenas a observação é alterada
- **THEN** o saldo corrente volta a ser −50.000,00
> AMBIGUIDADE: D-73 — a cópia roda em toda gravação e não existe, em lugar nenhum do legado, código que movimente o saldo corrente; é preciso descobrir com o negócio se falta a funcionalidade de baixa de saldo (e a cópia é bug) ou se a coluna é decorativa

#### Scenario: Apresentação do saldo inicial
- **GIVEN** uma operação com saldo inicial armazenado como −50.000,00
- **WHEN** o formulário e o detalhe são exibidos
- **THEN** o formulário mostra o valor absoluto e o detalhe mostra o valor negativo, como no legado
> AMBIGUIDADE: D-73 — a mesma grandeza aparece com sinais diferentes em duas telas; confirmar qual apresentação é a correta

### Requirement: BE-293 — Validações da operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
A operação exige empresa, projeto, portador, tipo, autor, emissão, capital e vencimento.
Fonte legada: `app/models/structured_operation.rb:13-20`.

#### Scenario: Campos obrigatórios ausentes
- **GIVEN** um payload sem vencimento
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 com o nome do campo em pt-BR

#### Scenario: Vencimento anterior à emissão
- **GIVEN** emissão em 10/03/2026 e vencimento em 01/03/2026
- **WHEN** a criação é submetida
- **THEN** a operação é aceita, como no legado
> AMBIGUIDADE: o legado só amarra as datas pelo seletor da tela, sem validação no servidor; confirmar se o ai9 deve exigir vencimento maior ou igual à emissão

#### Scenario: Capital negativo e taxa fora da faixa
- **GIVEN** capital de −10.000,00 e taxa acordada de 250
- **WHEN** a criação é submetida
- **THEN** os valores são aceitos, como no legado
> AMBIGUIDADE: não há validação de capital positivo nem de taxa entre 0 e 100; confirmar se o ai9 deve validar

#### Scenario: Número de contrato repetido
- **GIVEN** uma operação com o contrato "ABC-123"
- **WHEN** outra operação é criada com o mesmo contrato
- **THEN** ela é aceita, como no legado

### Requirement: BE-294 — Elegibilidade da operação a recibo
O sistema SHALL se comportar conforme os cenários desta seção.
Uma operação é candidata a recibo enquanto não tiver recibo emitido. Fonte legada:
`app/models/structured_operation.rb:7`, `:10`; `app/models/receipt.rb:27-35`, `:42`.

#### Scenario: Operação sem recibo é candidata
- **GIVEN** uma operação sem recibo emitido
- **WHEN** os candidatos de uma cobrança são montados
- **THEN** ela aparece como candidata

#### Scenario: Operação já faturada
- **GIVEN** uma operação com recibo emitido
- **WHEN** um novo recibo é solicitado para ela
- **THEN** a solicitação é recusada com a mensagem "Já existe um recibo associado a essa operação", tratada como erro de negócio
> Nota: corrige comportamento legado (a exceção não era tratada e derrubava o fluxo de cobrança com 500 — ver BE-188 em receivables)

#### Scenario: Recibo excluído libera a operação
- **GIVEN** uma operação com recibo emitido
- **WHEN** o recibo é excluído
- **THEN** ela volta a ser candidata

### Requirement: BE-295 — Indicadores de negócio da operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
A operação guarda os indicadores de encerrada e de considerar no variável, além da taxa
acordada. Fonte legada: `app/models/structured_operation.rb:23-27`, `:43-55`.

#### Scenario: Rótulos dos indicadores
- **GIVEN** uma operação com os dois indicadores desligados
- **WHEN** ela é apresentada
- **THEN** os rótulos são "Não encerrado" e "Não considerar no variável"

#### Scenario: Operação encerrada continua ativa
- **GIVEN** uma operação marcada como encerrada
- **WHEN** a lista e os candidatos a recibo são montados
- **THEN** ela continua aparecendo e continua elegível a recibo, como no legado
> AMBIGUIDADE: D-74 — os três campos não são lidos por nenhum cálculo, relatório, filtro ou processamento; em especial "considerar no variável" sugere uma remuneração variável que não existe no legado, e a taxa acordada **não** é a taxa usada para remunerar (ver BE-305)

### Requirement: BE-296 — Buscar e listar tipos de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
A busca lista o catálogo de tipos, com termo textual, ordenação e paginação. Fonte
legada: `app/controllers/pub/structured_operation_types_controller.rb:9-39`.

#### Scenario: Listagem paginada e ordenada
- **GIVEN** 60 tipos cadastrados e uma busca com limite 20 e ordenação por título
- **WHEN** ela é executada
- **THEN** vêm 20 tipos ordenados por título, com o total informado
> Nota: corrige D-20 (comportamento legado: o limite e o deslocamento eram descartados nos dois ramos, e não havia total)

#### Scenario: Tipos desativados
- **GIVEN** um tipo desativado
- **WHEN** a lista é montada
- **THEN** ele aparece com a situação de desativado, permitindo reativá-lo
> Nota: corrige comportamento legado (a listagem filtrava apenas os ativos, então um tipo desativado sumia da tela e não podia ser reativado pela interface)

#### Scenario: Chave de ordenação desconhecida
- **GIVEN** uma chave fora de título e chave de integração
- **WHEN** a busca é executada
- **THEN** ela é ignorada e a ordenação padrão é aplicada
> Nota: corrige comportamento legado (produzia `NoMethodError` e 500)

### Requirement: BE-297 — Criar tipo de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
A criação exige título único e deriva a chave de integração quando ela não é informada.
Fonte legada: `app/controllers/pub/structured_operation_types_controller.rb:67-80`;
`app/models/structured_operation_type.rb:6-9`.

#### Scenario: Chave derivada do título
- **GIVEN** o título "Auto Liquidável" e a chave em branco
- **WHEN** o tipo é criado
- **THEN** a chave gravada é `auto_liquidavel`

#### Scenario: Título duplicado
- **GIVEN** um tipo "Fomento" já existente
- **WHEN** outro tipo "Fomento" é criado
- **THEN** a resposta é 422

#### Scenario: Chave de integração duplicada
- **GIVEN** dois títulos diferentes cuja transliteração produz a mesma chave
- **WHEN** o segundo tipo é criado
- **THEN** a resposta é 422 por chave já usada
> Nota: corrige comportamento legado (a chave não tinha unicidade, então títulos distintos podiam colidir na mesma chave de integração)

#### Scenario: Falha de criação não deixa efeitos
- **GIVEN** uma criação recusada por validação
- **WHEN** ela é processada
- **THEN** nenhum registro é criado e nenhuma remoção é tentada
> Nota: corrige comportamento legado (o controller chamava a remoção sobre um registro nunca persistido, disparando a guarda de tipo padrão sem necessidade)

#### Scenario: Indicadores sem tela
- **GIVEN** os indicadores de padrão, lançamento manual, lançamento por recebível e pré-faturamento
- **WHEN** o tipo é criado pela tela
- **THEN** eles assumem os valores padrão, porque não são oferecidos no formulário
> AMBIGUIDADE: D-74 — os quatro são aceitos pela API mas não existem no formulário, e os de lançamento manual e por recebível não têm nenhum consumidor para tipos estruturados; confirmar se as colunas devem ser portadas

### Requirement: BE-298 — Atualizar tipo de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
A edição altera a chave de integração e a situação, preservando a identidade do tipo.
Fonte legada: `app/controllers/pub/structured_operation_types_controller.rb:82-95`.

#### Scenario: Título e indicador de padrão são imutáveis
- **GIVEN** um tipo existente
- **WHEN** uma requisição direta tenta alterar o título ou o indicador de tipo padrão
- **THEN** a alteração é recusada
> Nota: corrige comportamento legado (o formulário travava o título mas a API aceitava alterá-lo, assim como o indicador de tipo padrão)

#### Scenario: Alteração da chave de integração
- **GIVEN** um tipo cuja chave é usada por integrações
- **WHEN** a chave é alterada
- **THEN** a operação exige confirmação explícita e registra a mudança
> Nota: corrige comportamento legado (a chave podia ser alterada livremente após a criação, quebrando integrações sem qualquer aviso)

#### Scenario: Desativação pela API
- **GIVEN** um tipo ativo
- **WHEN** ele é desativado
- **THEN** ele continua visível na lista com a situação de desativado, e pode ser reativado (ver BE-296)

### Requirement: BE-299 — Excluir tipo de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
Tipos padrão do sistema e tipos com operações vinculadas não podem ser removidos. Fonte
legada: `app/controllers/pub/structured_operation_types_controller.rb:98-113`;
`app/models/structured_operation_type.rb:4`, `:10-15`.

#### Scenario: Tipo padrão do sistema
- **GIVEN** um dos quatro tipos padrão
- **WHEN** a exclusão é tentada
- **THEN** ela é recusada com a mensagem "Não pode remover tipo padrão"

#### Scenario: Tipo com operações vinculadas
- **GIVEN** um tipo usado por operações
- **WHEN** a exclusão é tentada
- **THEN** ela é recusada explicando o vínculo

#### Scenario: Tipo removível
- **GIVEN** um tipo não padrão e sem operações
- **WHEN** a exclusão é confirmada
- **THEN** ele é removido

### Requirement: BE-300 — Buscar e listar remunerações
O sistema SHALL se comportar conforme os cenários desta seção.
A busca lista as remunerações do projeto corrente, com termo textual, ordenação e
paginação. Fonte legada: `app/controllers/pub/remunerations_controller.rb:8-17`.

#### Scenario: Listagem escopada ao projeto
- **GIVEN** remunerações em `P1` e `P2` e um usuário do projeto `P1`
- **WHEN** a busca é executada
- **THEN** só as remunerações de `P1` são retornadas, com as duas classes de operação

#### Scenario: Lista ordenada e paginada
- **GIVEN** 40 remunerações no projeto e uma busca com limite 20
- **WHEN** ela é executada
- **THEN** vêm 20 remunerações em ordem determinística, com o total informado
> Nota: corrige D-20 (comportamento legado: a busca ignorava limite e deslocamento, não tinha ordenação nem total, e a lista voltava inteira em ordem indefinida)

#### Scenario: Busca textual
- **GIVEN** remunerações cujos títulos vêm dos tipos de operação
- **WHEN** o usuário busca por parte do título
- **THEN** só as correspondentes são retornadas

### Requirement: BE-301 — Criar remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
Existe no máximo uma remuneração por projeto, classe de operação e tipo de operação.
Fonte legada: `app/controllers/pub/remunerations_controller.rb:37-49`;
`app/models/remuneration.rb:6-11`.

#### Scenario: Criação bem-sucedida
- **GIVEN** um tipo de operação estruturada sem remuneração no projeto e a taxa 2,55
- **WHEN** a remuneração é criada
- **THEN** ela é persistida no projeto corrente com o título derivado do tipo

#### Scenario: Combinação duplicada
- **GIVEN** uma remuneração já existente para o projeto, a classe e o tipo
- **WHEN** outra é criada para a mesma combinação
- **THEN** a criação é recusada, inclusive em requisições simultâneas
> Nota: corrige D-103 (comportamento legado: a unicidade existia só na aplicação, sem índice único no banco, sujeita a corrida — e é ela que garante que a busca da taxa em BE-305 encontre uma única remuneração)

#### Scenario: Projeto forçado ao do usuário
- **GIVEN** um payload informando outro projeto
- **WHEN** a remuneração é criada
- **THEN** ela é gravada no projeto corrente do usuário
> Nota: corrige o vazamento de escopo da mesma família de D-76 (comportamento legado: o projeto vinha de um campo escondido do formulário e não era forçado, permitindo criar remuneração em outro projeto)

#### Scenario: Classe de operação inválida
- **GIVEN** um payload com uma classe de operação fora das duas conhecidas
- **WHEN** a criação é submetida
- **THEN** a resposta é 422
> Nota: corrige comportamento legado (não havia validação de inclusão, e a classe inválida só quebrava depois, na resolução do tipo e na sigla)

#### Scenario: Taxa fora da faixa
- **GIVEN** uma taxa de −5 ou de 250
- **WHEN** a criação é submetida
- **THEN** a resposta é 422
> Nota: corrige comportamento legado (a taxa não tinha validação de faixa, e uma taxa negativa geraria remuneração negativa no recibo)

### Requirement: BE-302 — Atualizar remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
A edição altera a taxa, mantendo a identidade da combinação. Fonte legada:
`app/controllers/pub/remunerations_controller.rb:51-64`, `:82-84`.

#### Scenario: Alteração da taxa
- **GIVEN** uma remuneração de 2,55
- **WHEN** a taxa é alterada para 3,00
- **THEN** a nova taxa passa a valer para os próximos recibos, sem alterar os recibos já emitidos

#### Scenario: Troca da combinação
- **GIVEN** uma remuneração existente
- **WHEN** uma requisição direta tenta trocar a classe ou o tipo de operação
- **THEN** a alteração é recusada
> Nota: corrige comportamento legado (a tela desabilitava os dois seletores na edição mas a API aceitava a troca — cobranças futuras mudavam de tipo sem aviso)

#### Scenario: Remuneração de outro projeto
- **GIVEN** uma remuneração de outro projeto
- **WHEN** a edição é submetida por identificador
- **THEN** a requisição é recusada por autorização
> Nota: corrige o vazamento de escopo da mesma família de D-76

### Requirement: BE-303 — Excluir remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
A remuneração não pode ser removida enquanto houver recibos emitidos com ela. Fonte
legada: `app/controllers/pub/remunerations_controller.rb:68-78`.

#### Scenario: Exclusão barrada por recibos
- **GIVEN** uma remuneração com recibos emitidos
- **WHEN** a exclusão é tentada
- **THEN** ela é recusada explicando o vínculo
> Nota: corrige comportamento legado (a associação não declarava dependência, e apagar a remuneração deixava recibos órfãos apontando para um registro inexistente, quebrando qualquer gravação posterior desses recibos)

#### Scenario: Exclusão de remuneração sem recibos
- **GIVEN** uma remuneração nunca usada
- **WHEN** a exclusão é confirmada
- **THEN** ela é removida

### Requirement: BE-304 — Título, classe e sigla da remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
A remuneração deriva seu título do tipo de operação e expõe a classe e a sigla usadas
pelo recibo. Fonte legada: `app/models/remuneration.rb:17-19`, `:31-46`.

#### Scenario: Título derivado
- **GIVEN** um tipo de operação "Fomento"
- **WHEN** a remuneração é gravada
- **THEN** `title = "Fomento"`

#### Scenario: Sigla por classe de operação
- **GIVEN** uma remuneração de operação liquidável e outra de operação estruturada
- **WHEN** as siglas são resolvidas
- **THEN** elas são `LIQ` e `EST`, e é essa sigla que o recibo grava e a cobrança usa para separar os totais

#### Scenario: Tipo de operação inválido
- **GIVEN** uma remuneração cujo tipo referenciado não existe
- **WHEN** a gravação é submetida
- **THEN** a resposta é 422 pela validação de presença, e não um erro interno
> Nota: corrige comportamento legado (a derivação do título acessava o tipo nulo e levantava `NoMethodError` antes das validações)

#### Scenario: Renomear o tipo não altera recibos emitidos
- **GIVEN** recibos já emitidos com o título "Fomento"
- **WHEN** o tipo de operação é renomeado
- **THEN** os recibos emitidos mantêm o título congelado no momento da emissão

### Requirement: BE-305 — Fórmula da remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
O valor a cobrar por uma operação é um percentual simples sobre o capital, definido pela
remuneração do projeto para o tipo daquela operação. Fonte legada:
`app/models/receipt.rb:41-66`, em especial `:59-63`.

#### Scenario: Cálculo do valor
- **GIVEN** uma operação estruturada com capital de 200.000,00 e a remuneração do projeto para o tipo dela com taxa 2,55
- **WHEN** o recibo é gerado
- **THEN** `value = 5.100,00`, `fee = 2,55`, `operation_value = 200.000,00`, `kind = "EST"`, `title` e `date` copiados da remuneração e da operação, e `temp_id = "RCP-{project_id}-EST-{remuneration_id}-{operation_id}"`
> Nota: DEC-02 — a multiplicação de decimal por ponto flutuante e o arredondamento implícito na gravação são replicados para os totais baterem
> AMBIGUIDADE: D-72 — a remuneração é percentual flat sobre o capital, sem prazo nem proporcionalidade: nem emissão, nem vencimento, nem prazo em dias, nem taxa acordada, nem saldo entram no cálculo, embora o modelo guarde todos esses campos sugerindo o contrário; confirmar a fórmula pretendida com o negócio antes de reimplementar

#### Scenario: Operação já faturada
- **GIVEN** uma operação com recibo emitido
- **WHEN** um novo recibo é solicitado
- **THEN** a solicitação é recusada como erro de negócio, com a mensagem "Já existe um recibo associado a essa operação"

#### Scenario: Projeto sem remuneração para o tipo
- **GIVEN** uma operação cujo tipo não tem remuneração cadastrada no projeto
- **WHEN** o recibo é solicitado
- **THEN** a solicitação é recusada como erro de negócio, com a mensagem "Não existe remuneração no projeto para esse tipo de operação"
> Nota: corrige comportamento legado (as duas situações levantavam exceção não tratada e derrubavam a requisição — ver BE-188 em receivables)

#### Scenario: Política de arredondamento explícita
- **GIVEN** um capital e uma taxa cujo produto tem mais de duas casas decimais
- **WHEN** o recibo é gerado
- **THEN** o valor é arredondado exatamente como no legado, produzindo o mesmo centavo
> Nota: DEC-02 — o arredondamento do legado é acidental (vem do cast na gravação) e é replicado para manter a paridade dos totais de cobrança

### Requirement: BE-306 — Candidatos a recibo por remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
Para cada remuneração do projeto, as operações do tipo correspondente ainda não faturadas
são candidatas a entrar em uma cobrança. Fonte legada:
`app/models/remuneration.rb:25-29`; `app/models/charge.rb:34-46`.

#### Scenario: Candidatos com valores já calculados
- **GIVEN** uma remuneração de 2,55 e três operações do tipo dela sem recibo
- **WHEN** os candidatos são montados
- **THEN** as três aparecem com o valor da remuneração já calculado

#### Scenario: Operação já faturada
- **GIVEN** uma operação com recibo emitido
- **WHEN** os candidatos são montados
- **THEN** ela não aparece

#### Scenario: Lista de candidatos paginada
- **GIVEN** um projeto com centenas de operações em aberto
- **WHEN** a tela de seleção de operações é montada
- **THEN** os candidatos vêm paginados, ordenados por data decrescente
> Nota: corrige D-20 (comportamento legado: todos os candidatos eram instanciados em memória a cada abertura da tela, sem paginação)

#### Scenario: Operação encerrada continua candidata
- **GIVEN** uma operação marcada como encerrada e sem recibo
- **WHEN** os candidatos são montados
- **THEN** ela aparece como candidata, como no legado
> AMBIGUIDADE: D-74 — operação encerrada continuar elegível a faturamento parece indesejado; validar com o negócio

### Requirement: BE-307 — Buscar tipos de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
`GET /resource_kinds/search` lista o catálogo de tipos de recurso, com termo textual e
paginação. Fonte legada: `app/controllers/pub/resource_kinds_controller.rb:9-25`.

#### Scenario: Listagem paginada
- **GIVEN** tipos de recurso cadastrados e uma busca com limite 20
- **WHEN** ela é executada
- **THEN** vêm no máximo 20 registros, ordenados por título, com o total informado
> Nota: corrige D-20 (comportamento legado: o limite e o deslocamento eram descartados)

#### Scenario: Tipos desativados aparecem com sua situação
- **GIVEN** o tipo "Antecipacao de Recebíveis", semeado como desativado
- **WHEN** a lista é montada
- **THEN** ele aparece com a situação de desativado

#### Scenario: Escopo da entidade
- **GIVEN** o catálogo de tipos de recurso
- **WHEN** o escopo do ai9 é definido
- **THEN** ele é portado com os dados existentes
> AMBIGUIDADE: D-74 — a entidade é praticamente morta: não tem item de menu (FE-307), a coluna que a ligaria a recebíveis nunca é preenchida (DB-289) e dois de seus campos não têm consumidor; confirmar se deve ser portada ou descartada com evidência

### Requirement: BE-308 — Buscar fontes de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
`GET /resource_sources/search` lista o catálogo de fontes de recurso, com termo textual,
ordenação e paginação. Fonte legada:
`app/controllers/pub/resource_sources_controller.rb:9-38`.

#### Scenario: Listagem ordenada e paginada
- **GIVEN** fontes cadastradas e uma busca com ordenação por título e limite 20
- **WHEN** ela é executada
- **THEN** vêm no máximo 20 registros ordenados, com o total informado
> Nota: corrige D-20 (comportamento legado: o limite e o deslocamento eram descartados)

#### Scenario: Fonte desativada continua selecionável em recebíveis
- **GIVEN** uma fonte de recurso desativada
- **WHEN** o formulário de recebível é montado
- **THEN** ela continua sendo oferecida, como no legado
> AMBIGUIDADE: D-19 — a situação é gravada e exibida mas nunca filtra nada; confirmar se o ai9 deve passar a esconder fontes desativadas, mudança visível ao usuário

#### Scenario: Papel classificatório
- **GIVEN** um recebível com fonte de recurso informada
- **WHEN** seus valores são calculados
- **THEN** a fonte não altera nenhum cálculo de tarifa, IOF, custo efetivo ou remuneração

### Requirement: BE-309 — Rotas órfãs de taxas de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
As rotas de taxas de operação estruturada não têm controller, modelo, tela nem tabela.
Fonte legada: `config/routes.rb:107-108`.

#### Scenario: Rotas não são portadas
- **GIVEN** as oito rotas geradas para taxas de operação estruturada
- **WHEN** o escopo do ai9 é definido
- **THEN** elas não existem
> Nota: DEC-09 — código morto comprovado por varredura exaustiva: as duas únicas ocorrências da expressão em todo o repositório são as próprias linhas de rota; entra no ledger como `dropped` com evidência. Qualquer funcionalidade de "taxas por operação estruturada" seria feature nova

### Requirement: BE-720 — Abrir o formulário de novo tipo de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A ação monta o painel lateral de cadastro de tipo de recurso. Fonte legada:
`app/controllers/pub/resource_kinds_controller.rb:35-43`; `config/routes.rb:167`.

#### Scenario: Painel de cadastro
- **GIVEN** o usuário acionando o cadastro
- **WHEN** o painel é montado
- **THEN** ele vem vazio, com título, chave de integração, situação e os dois indicadores

#### Scenario: Autorização no servidor
- **GIVEN** um usuário sem permissão de escrita
- **WHEN** ele aciona a ação diretamente
- **THEN** a requisição é recusada por autorização
> Nota: corrige D-17 (comportamento legado: não havia checagem de permissão no servidor)

### Requirement: BE-721 — Abrir o formulário de edição de tipo de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A ação monta o painel lateral com os dados do tipo de recurso escolhido. Fonte legada:
`app/controllers/pub/resource_kinds_controller.rb:45-51`, `:97-100`.

#### Scenario: Painel preenchido
- **GIVEN** um tipo de recurso existente
- **WHEN** o painel de edição é aberto
- **THEN** ele vem com os valores atuais do registro

#### Scenario: Identificador inexistente
- **GIVEN** um identificador que não existe
- **WHEN** o painel é aberto
- **THEN** a resposta é 404

### Requirement: BE-722 — Criar tipo de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A criação exige título único e deriva a chave de integração quando não informada. Fonte
legada: `app/controllers/pub/resource_kinds_controller.rb:53-66`, `:102-116`.

#### Scenario: Criação com chave derivada
- **GIVEN** o título "Desconto de Títulos" e a chave em branco
- **WHEN** o tipo de recurso é criado
- **THEN** a chave gravada é `desconto_de_titulos`

#### Scenario: Título duplicado
- **GIVEN** um tipo de recurso "Fomento" já existente
- **WHEN** outro é criado com o mesmo título
- **THEN** a resposta é 422

#### Scenario: Falha de criação não deixa efeitos
- **GIVEN** uma criação recusada por validação
- **WHEN** ela é processada
- **THEN** nenhum registro é criado e nenhuma remoção é tentada
> Nota: corrige comportamento legado (o controller chamava a remoção sobre um registro nunca persistido)

#### Scenario: Indicadores de conta corrente e registro único
- **GIVEN** os dois indicadores do formulário
- **WHEN** o tipo de recurso é gravado
- **THEN** os valores informados são persistidos
> AMBIGUIDADE: D-74 — nenhum código do legado lê esses dois indicadores; a semântica se perdeu e precisa vir do negócio antes de decidir se são portados (ver DB-294)

### Requirement: BE-723 — Atualizar tipo de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A edição altera título, chave, situação e os dois indicadores em uma única gravação.
Fonte legada: `app/controllers/pub/resource_kinds_controller.rb:68-82`.

#### Scenario: Edição com gravação única
- **GIVEN** um tipo de recurso existente
- **WHEN** o título é alterado
- **THEN** a gravação ocorre uma única vez
> Nota: corrige comportamento legado (a ação chamava atualização e gravação em sequência, gerando escrita redundante)

#### Scenario: Chave após renomear
- **GIVEN** um tipo de recurso renomeado
- **WHEN** ele é gravado
- **THEN** a chave de integração permanece a mesma, e a alteração da chave é uma ação explícita do usuário

### Requirement: BE-724 — Excluir tipo de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A exclusão é bloqueada quando o tipo está em uso, e a falha é reportada. Fonte legada:
`app/controllers/pub/resource_kinds_controller.rb:84-95`.

#### Scenario: Exclusão bem-sucedida
- **GIVEN** um tipo de recurso não utilizado
- **WHEN** a exclusão é confirmada
- **THEN** ele é removido

#### Scenario: Exclusão bloqueada é reportada
- **GIVEN** um tipo de recurso referenciado por recebíveis
- **WHEN** a exclusão é tentada
- **THEN** a resposta é um erro explicando o vínculo
> Nota: corrige D-24 (comportamento legado: os dois ramos respondiam sucesso, e a interface não distinguia exclusão de bloqueio; na prática a proteção nunca disparava porque a coluna que ligaria recebíveis a tipos de recurso nunca é preenchida — ver DB-289)

### Requirement: BE-725 — Abrir o formulário de nova fonte de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A ação monta o painel lateral de cadastro de fonte de recurso. Fonte legada:
`app/controllers/pub/resource_sources_controller.rb:48-56`; `config/routes.rb:206`.

#### Scenario: Painel de cadastro
- **GIVEN** o usuário acionando o cadastro
- **WHEN** o painel é montado
- **THEN** ele vem vazio, com título, chave de integração e situação

#### Scenario: Autorização no servidor
- **GIVEN** um usuário sem permissão de escrita
- **WHEN** ele aciona a ação diretamente
- **THEN** a requisição é recusada por autorização
> Nota: corrige D-17 (comportamento legado: não havia checagem de permissão no servidor)

### Requirement: BE-726 — Abrir o formulário de edição de fonte de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A ação monta o painel lateral com os dados da fonte escolhida. Fonte legada:
`app/controllers/pub/resource_sources_controller.rb:58-64`, `:110-113`.

#### Scenario: Painel preenchido
- **GIVEN** uma fonte de recurso existente
- **WHEN** o painel de edição é aberto
- **THEN** ele vem com os valores atuais do registro

#### Scenario: Identificador inexistente
- **GIVEN** um identificador que não existe
- **WHEN** o painel é aberto
- **THEN** a resposta é 404

### Requirement: BE-727 — Criar fonte de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A criação exige título único e deriva a chave de integração quando não informada. Fonte
legada: `app/controllers/pub/resource_sources_controller.rb:66-79`, `:115-127`.

#### Scenario: Criação com chave derivada
- **GIVEN** o título "Utilização De Recurso" e a chave em branco
- **WHEN** a fonte é criada
- **THEN** a chave gravada é `utilizacao_de_recurso`

#### Scenario: Título duplicado
- **GIVEN** uma fonte "Fomento" já existente
- **WHEN** outra é criada com o mesmo título
- **THEN** a resposta é 422

#### Scenario: Falha de criação não deixa efeitos
- **GIVEN** uma criação recusada por validação
- **WHEN** ela é processada
- **THEN** nenhum registro é criado e nenhuma remoção é tentada
> Nota: corrige comportamento legado (o controller chamava a remoção sobre um registro nunca persistido)

#### Scenario: Situação da fonte
- **GIVEN** uma fonte criada como desativada
- **WHEN** o formulário de recebível é montado
- **THEN** ela continua sendo oferecida, como no legado
> AMBIGUIDADE: D-19 — a situação não filtra nada em lugar nenhum; confirmar se o ai9 deve passar a aplicá-la (ver BE-308)

### Requirement: BE-728 — Atualizar fonte de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A edição altera título, chave e situação em uma única gravação. Fonte legada:
`app/controllers/pub/resource_sources_controller.rb:81-95`.

#### Scenario: Edição com gravação única
- **GIVEN** uma fonte existente
- **WHEN** o título é alterado
- **THEN** a gravação ocorre uma única vez
> Nota: corrige comportamento legado (a ação chamava atualização e gravação em sequência)

#### Scenario: Chave de integração após renomear
- **GIVEN** uma fonte renomeada de "Caixa" para "Caixa Central"
- **WHEN** ela é gravada
- **THEN** a chave de integração permanece `caixa`, e a tela sinaliza a divergência entre o título e a chave usada pelos relatórios
> Nota: corrige comportamento legado (a chave ficava defasada sem qualquer aviso, e é ela que os relatórios usam)

### Requirement: BE-729 — Excluir fonte de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A exclusão é bloqueada quando a fonte está em uso por recebíveis, e a falha é reportada.
Fonte legada: `app/controllers/pub/resource_sources_controller.rb:97-108`.

#### Scenario: Exclusão bem-sucedida
- **GIVEN** uma fonte não utilizada
- **WHEN** a exclusão é confirmada
- **THEN** ela é removida

#### Scenario: Exclusão bloqueada é reportada
- **GIVEN** uma fonte referenciada por recebíveis
- **WHEN** a exclusão é tentada
- **THEN** a resposta é um erro explicando o vínculo
> Nota: corrige D-24 (comportamento legado: os dois ramos respondiam sucesso — aqui a proteção realmente dispara, então o usuário via a lista recarregar como se tivesse excluído e o registro continuava lá)

### Requirement: FE-280 — Tela de lista de operações estruturadas
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Operações Estruturadas" lista as operações do projeto com dez colunas. Fonte
legada: `app/views/pub/console/parts/structured_operations/_body.html.erb:1-132`.

#### Scenario: Colunas da lista
- **GIVEN** operações cadastradas no projeto corrente
- **WHEN** o usuário abre a área pelo menu "Gestão"
- **THEN** a tela mostra Portador, Tipo de operação, Titulo, Contrato, Emissão, Capital, Saldo, Vencimento e Tx acordada

#### Scenario: Identificação correta da tela
- **GIVEN** a área aberta
- **WHEN** o título da página e o endereço são exibidos
- **THEN** eles identificam operações estruturadas
> Nota: corrige comportamento legado (o título da aba do navegador era "Safegold - Garantias do Projeto" e o rótulo do endereço era "Recebívels", ambos copiados de outras telas)

#### Scenario: Acesso pelo menu
- **GIVEN** um usuário sem nenhum projeto
- **WHEN** o menu é montado
- **THEN** o item de operações estruturadas não aparece

### Requirement: FE-281 — Estado de carregamento da lista de operações
O sistema SHALL se comportar conforme os cenários desta seção.
A lista sinaliza o carregamento inicial e recarrega em silêncio nas navegações. Fonte
legada: `.../structured_operations/_body.js.erb:275`.

#### Scenario: Carregamento inicial
- **GIVEN** a área sendo aberta
- **WHEN** a busca ainda não respondeu
- **THEN** a tela exibe "Buscando .."

#### Scenario: Recarga silenciosa
- **GIVEN** a lista já carregada
- **WHEN** o usuário troca um filtro
- **THEN** a lista é atualizada sem o indicador de carregamento, mantendo os dados anteriores visíveis até a resposta

### Requirement: FE-282 — Estados vazios da lista de operações
O sistema SHALL se comportar conforme os cenários desta seção.
A lista distingue o vazio sem busca do vazio com termo pesquisado. Fonte legada:
`.../structured_operations/_body.js.erb:260-262`, `:276`.

#### Scenario: Vazio sem busca
- **GIVEN** nenhuma operação para os filtros ativos
- **WHEN** a lista carrega
- **THEN** a tela mostra "Nenhum resultado encontrado"

#### Scenario: Vazio com termo
- **GIVEN** o termo "alfa" no campo de busca e nenhuma operação correspondente
- **WHEN** a lista carrega
- **THEN** a tela mostra "Não encontramos nenhum resultado para a busca **alfa**.."

#### Scenario: Projeto sem nenhuma operação
- **GIVEN** um projeto que nunca teve operação estruturada
- **WHEN** a lista carrega
- **THEN** a tela apresenta um estado de primeiro uso, distinto do vazio por filtro
> Nota: corrige comportamento legado (não existia estado de primeiro uso — o projeto novo via a mesma mensagem de busca sem resultado)

### Requirement: FE-283 — Estado de erro da lista de operações
O sistema SHALL se comportar conforme os cenários desta seção.
Falhas de carregamento da lista são comunicadas ao usuário. Fonte legada:
`.../structured_operations/_body.js.erb:232-234`.

#### Scenario: Falha ao carregar
- **GIVEN** a busca retornando erro
- **WHEN** a resposta chega
- **THEN** a tela mostra um estado de erro com opção de tentar novamente
> Nota: corrige comportamento legado (o tratamento de falha era um bloco vazio: a tela ficava em carregamento eterno ou com dados antigos, sem nenhuma mensagem)

#### Scenario: Falha ao excluir
- **GIVEN** uma exclusão que falha
- **WHEN** a resposta chega
- **THEN** a tela mostra a razão da falha e a operação permanece na lista

### Requirement: FE-284 — Busca textual da lista de operações
O sistema SHALL se comportar conforme os cenários desta seção.
O campo de busca filtra a lista com debounce de 300 ms. Fonte legada:
`.../structured_operations/_body.js.erb:200-213`.

#### Scenario: Debounce
- **GIVEN** o usuário digitando no campo de busca
- **WHEN** ele para por 300 ms
- **THEN** uma única busca é disparada

#### Scenario: Entrada só com espaços
- **GIVEN** o campo contendo apenas espaços
- **WHEN** o debounce expira
- **THEN** nenhuma busca é disparada

### Requirement: FE-285 — Filtro de período da lista de operações
O sistema SHALL se comportar conforme os cenários desta seção.
O botão de período abre um seletor de intervalo em pt-BR e rotula o intervalo escolhido.
Fonte legada: `.../structured_operations/_body.js.erb:97-166`.

#### Scenario: Seleção de intervalo
- **GIVEN** o seletor aberto
- **WHEN** o usuário escolhe 01/03/2026 e 31/03/2026
- **THEN** o rótulo mostra "De 01/03/2026 a 31/03/2026" e a lista é filtrada

#### Scenario: Um dia só
- **GIVEN** o seletor aberto
- **WHEN** apenas a data inicial é escolhida
- **THEN** a data final recebe o mesmo dia

#### Scenario: Intervalo que cruza o ano
- **GIVEN** o intervalo 20/12/2025 a 10/01/2026
- **WHEN** o rótulo é montado
- **THEN** ele mostra os dois anos corretos
> Nota: corrige comportamento legado (o ano final era lido da data inicial, então o rótulo exibia o ano errado — o valor enviado ao servidor estava correto)

### Requirement: FE-286 — Filtros de empresa, portador e tipo de operação
O sistema SHALL se comportar conforme os cenários desta seção.
Três seletores em painel recolhível recortam a lista. Fonte legada:
`.../structured_operations/_body.html.erb:42-55`; `_body.js.erb:168-198`.

#### Scenario: Filtros combinados
- **GIVEN** o painel de filtros aberto
- **WHEN** o usuário escolhe empresa e portador
- **THEN** só as operações que casam com os dois são listadas

#### Scenario: Tipos oferecidos no filtro
- **GIVEN** tipos de operação ativos e desativados
- **WHEN** o seletor de tipo é montado
- **THEN** os tipos oferecidos são os mesmos do formulário de cadastro
> Nota: corrige comportamento legado (o filtro oferecia todos os tipos, inclusive inativos, enquanto o formulário só oferecia os ativos)

#### Scenario: Filtro limpo
- **GIVEN** um filtro com valor escolhido
- **WHEN** o usuário volta à opção em branco
- **THEN** o filtro deixa de ser aplicado

### Requirement: FE-287 — Ordenação pelo cabeçalho da lista de operações
O sistema SHALL se comportar conforme os cenários desta seção.
O clique nos cabeçalhos cicla entre ascendente, descendente e neutro, acumulando colunas.
Fonte legada: `.../structured_operations/_body.js.erb:22-92`.

#### Scenario: Ciclo de ordenação
- **GIVEN** a coluna Emissão neutra
- **WHEN** o usuário clica três vezes
- **THEN** a ordenação passa por ascendente, descendente e volta ao neutro

#### Scenario: Uma requisição por clique
- **GIVEN** a lista carregada
- **WHEN** o usuário clica em um cabeçalho
- **THEN** uma única busca é disparada
> Nota: corrige comportamento legado (cada clique disparava duas requisições idênticas ao servidor)

#### Scenario: Colunas ordenáveis correspondem às exibidas
- **GIVEN** a lista de operações
- **WHEN** os cabeçalhos ordenáveis são montados
- **THEN** cada chave de ordenação disponível tem uma coluna correspondente na tela
> Nota: corrige comportamento legado (a chave de ordenação por empresa existia no servidor sem coluna correspondente na tela)

### Requirement: FE-288 — Navegação e paginação da lista de operações
O sistema SHALL se comportar conforme os cenários desta seção.
Botões de primeiro, anterior, próximo e último e um campo de tamanho de página navegam a
lista. Fonte legada: `.../structured_operations/_body.js.erb:300-421`, `:453-505`.

#### Scenario: Navegação com total correto
- **GIVEN** 300 operações e tamanho de página 50
- **WHEN** o usuário avança para a segunda página e depois para a última
- **THEN** a lista mostra os registros corretos em cada página
> Nota: corrige D-20 (comportamento legado: todas as habilitações dependiam de um total truncado pelo servidor, então em qualquer lista maior que uma página os botões ficavam desabilitados ou levavam a deslocamentos errados)

#### Scenario: Campo de tamanho vazio
- **GIVEN** o campo de tamanho apagado
- **WHEN** o usuário sai do campo
- **THEN** o tamanho volta ao padrão de 50 e a lista recomeça da primeira página

### Requirement: FE-289 — Widget de linha da operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
Cada linha formata datas, valores monetários e a taxa acordada. Fonte legada:
`.../structured_operations/list/_widget.html.erb:1-25`.

#### Scenario: Formatação da linha
- **GIVEN** uma operação emitida em 05/03/2026, com capital 200.000,00, saldo −50.000,00 e taxa 15,5
- **WHEN** a linha é renderizada
- **THEN** a data aparece como `05/03/2026`, os valores como `R$ 200.000,00` e `R$ -50.000,00`, e a taxa com duas casas seguida de `%`
> Nota: corrige comportamento legado (a taxa era impressa crua na lista, com as casas que o Ruby produzisse, enquanto o detalhe já usava duas casas — a mesma grandeza tinha formatos diferentes em duas telas)

#### Scenario: Contrato vazio
- **GIVEN** uma operação sem número de contrato
- **WHEN** a linha é renderizada
- **THEN** a coluna mostra `-`
> Nota: corrige comportamento legado (a coluna ficava em branco, sem indicar ausência de dado)

#### Scenario: Datas nulas
- **GIVEN** uma operação legada sem emissão ou sem vencimento
- **WHEN** a linha é renderizada
- **THEN** as colunas mostram `-` e a tela carrega normalmente
> Nota: corrige comportamento legado (a formatação de data nula quebrava a renderização com 500)

#### Scenario: Tipo com pré-faturamento
- **GIVEN** uma operação de tipo com pré-faturamento
- **WHEN** a linha é renderizada
- **THEN** emissão e vencimento são substituídos por `-`
> AMBIGUIDADE: D-74 — a regra esconde as datas sem explicação e nenhum tipo semeado tem pré-faturamento, tornando o caminho praticamente inalcançável hoje; é preciso entender o conceito de pré-faturamento para operações estruturadas com o negócio

### Requirement: FE-290 — Menu de ações da linha de operação
O sistema SHALL se comportar conforme os cenários desta seção.
A linha abre o detalhe e o menu oferece ver mais, editar e remover. Fonte legada:
`.../structured_operations/list/_widget.html.erb:26-44`; `list/_widget.js.erb:1-98`.

#### Scenario: Abrir o detalhe
- **GIVEN** uma operação na lista
- **WHEN** o usuário clica na linha
- **THEN** a navegação vai para o detalhe daquela operação

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** o menu é aberto
- **THEN** apenas "Ver mais" é oferecido

### Requirement: FE-291 — Guarda do cadastro de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
O cadastro exige portador no projeto e não é oferecido a usuários somente-leitura. Fonte
legada: `.../structured_operations/_body.js.erb:424-439`.

#### Scenario: Projeto sem portador
- **GIVEN** um projeto corrente sem portadores
- **WHEN** o usuário aciona "Cadastrar"
- **THEN** a tela mostra "É necessário ter um portador no projeto padrão, para que seja possível cadastrar uma operação estruturada" e a navegação é bloqueada

#### Scenario: Rótulo da tela de cadastro
- **GIVEN** um projeto com portador
- **WHEN** o usuário aciona "Cadastrar"
- **THEN** a tela aberta se identifica como cadastro de operação estruturada
> Nota: corrige comportamento legado (o rótulo da navegação era "Cadastrar recebível")

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** a lista é exibida
- **THEN** o botão de cadastro não existe

### Requirement: FE-292 — Remoção de operação estruturada pela tela
O sistema SHALL se comportar conforme os cenários desta seção.
A remoção pede confirmação e reflete o resultado real da operação. Fonte legada:
`.../structured_operations/list/_widget.js.erb:70-96`; `destroy/handle.js.erb:1-11`.

#### Scenario: Confirmação com o rótulo correto
- **GIVEN** uma operação estruturada
- **WHEN** o usuário aciona "Remover"
- **THEN** a confirmação identifica a exclusão de uma operação estruturada e traz "A operação não pode ser desfeita. Tem certeza?"
> Nota: corrige comportamento legado (o título da confirmação era "Excluir renegociação", texto de outra tela)

#### Scenario: Exclusão barrada por recibo
- **GIVEN** uma operação com recibo emitido
- **WHEN** a exclusão é confirmada
- **THEN** a tela explica em pt-BR que a operação já foi faturada e a lista permanece com o registro
> Nota: corrige D-24 (comportamento legado: o servidor respondia sucesso, a lista recarregava com a operação ainda lá e a única pista era uma mensagem crua com a chave técnica em inglês)

### Requirement: FE-293 — Formulário de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
O formulário agrupa cadastro, datas, valores, taxa e indicadores em duas colunas. Fonte
legada: `.../structured_operations/new/_body.html.erb:1-217`.

#### Scenario: Campos do formulário
- **GIVEN** o formulário aberto
- **WHEN** ele é exibido
- **THEN** aparecem Contrato, Titulo, Empresa, Portador, Tipo de operação, Observação, as datas, Capital da Operação, Saldo Inicial, Taxa acordada, Considerar no variável e Encerrada

#### Scenario: Título dinâmico
- **GIVEN** o formulário aberto para uma operação existente
- **WHEN** ele é exibido
- **THEN** o título é "Editar operação"

#### Scenario: Textos de ajuda dos campos
- **GIVEN** o formulário aberto
- **WHEN** o usuário aciona a ajuda de um campo
- **THEN** o texto exibido descreve o campo
> AMBIGUIDADE: no legado as 13 entradas de ajuda contêm o mesmo texto placeholder ("Só um teste de informações do campo..."); é preciso o conteúdo real de cada campo

### Requirement: FE-294 — Máscaras do formulário de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
Capital e saldo inicial usam máscara monetária, e a taxa usa máscara decimal. Fonte
legada: `.../structured_operations/new/_body.js.erb:98-221`.

#### Scenario: Máscara monetária
- **GIVEN** o campo de capital
- **WHEN** o usuário digita `200000,00` e sai do campo
- **THEN** o campo exibe `R$ 200.000,00` e o valor enviado é `200000.00`

#### Scenario: Mais de um separador decimal
- **GIVEN** um campo mascarado
- **WHEN** um segundo separador decimal é digitado
- **THEN** a tela avisa "Você só precisa inserir 1 separador para as casas decimais" e o segundo separador não é aceito
> Nota: corrige comportamento legado (o aviso aparecia mas a digitação não era impedida)

#### Scenario: Campo esvaziado
- **GIVEN** um campo monetário deixado sem nenhum dígito
- **WHEN** ele perde o foco
- **THEN** o valor passa a ser `0,00`

### Requirement: FE-295 — Salvamento e campos obrigatórios do formulário
O sistema SHALL se comportar conforme os cenários desta seção.
O formulário valida os campos obrigatórios antes de permitir o salvamento. Fonte legada:
`.../structured_operations/new/_body.js.erb:211-302`.

#### Scenario: Campos obrigatórios pendentes
- **GIVEN** o formulário com o capital em branco
- **WHEN** o usuário procura salvar
- **THEN** a ação não está disponível e a tela indica quais campos faltam
> Nota: corrige comportamento legado (a ação de salvar era simplesmente removida da barra inferior, sem nenhuma mensagem — o usuário perdia a possibilidade de salvar sem entender por quê)

#### Scenario: Vencimento obrigatório
- **GIVEN** o formulário sem data de vencimento
- **WHEN** o usuário procura salvar
- **THEN** o vencimento é indicado como obrigatório na própria tela
> Nota: corrige comportamento legado (o vencimento não era obrigatório no formulário mas era no servidor, então salvar sem ele produzia um erro cru do servidor)

#### Scenario: Salvamento concluído
- **GIVEN** o formulário completo
- **WHEN** o usuário salva
- **THEN** a operação é gravada e a navegação volta para a lista

### Requirement: FE-296 — Prévia de saldo no formulário
O sistema SHALL se comportar conforme os cenários desta seção.
O formulário mostra o saldo resultante do que foi informado, coerente com o que o
servidor grava. Fonte legada: `.../structured_operations/new/_body.js.erb:304-320`.

#### Scenario: Prévia coerente com a gravação
- **GIVEN** o usuário informando saldo inicial de 50.000,00
- **WHEN** a prévia é atualizada
- **THEN** ela mostra o mesmo saldo que o servidor vai gravar
> Nota: corrige comportamento legado (a rotina de cálculo do cliente tentava copiar o capital para um campo de saldo que não existe no formulário, então era um comando sem efeito, e o único valor efetivamente enviado era o saldo inicial digitado — ver BE-292)
> AMBIGUIDADE: D-73 — a intenção original do cliente era `saldo = capital`, enquanto o servidor grava `saldo = −|saldo inicial|`; as duas regras se contradizem e é preciso decisão de negócio

#### Scenario: Aviso de incongruência
- **GIVEN** uma combinação de valores considerada incongruente
- **WHEN** o usuário procura salvar
- **THEN** a tela explica a incongruência
> Nota: corrige comportamento legado (o indicador de erro nunca era ligado, tornando morta a mensagem "Alguns campos podem estar incongruentes")

### Requirement: FE-297 — Datas do formulário de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
As datas são escolhidas por seletor em pt-BR e se restringem mutuamente. Fonte legada:
`.../structured_operations/new/_body.html.erb:92-128`; `new/_body.js.erb:61-95`.

#### Scenario: Restrição mútua
- **GIVEN** a emissão definida como 01/03/2026
- **WHEN** o seletor de vencimento é aberto
- **THEN** datas anteriores a 01/03/2026 não podem ser escolhidas

#### Scenario: Datas na edição
- **GIVEN** uma operação existente
- **WHEN** o formulário é aberto para edição
- **THEN** as datas não são editáveis pela tela, e a API aplica a mesma regra
> AMBIGUIDADE: a imutabilidade das datas é hoje apenas regra de interface, enquanto a API aceita alterá-las; confirmar se ela deve virar regra de domínio

#### Scenario: Operação legada com datas nulas
- **GIVEN** uma operação sem emissão ou sem vencimento
- **WHEN** o formulário é aberto
- **THEN** os campos aparecem vazios e a tela carrega normalmente
> Nota: corrige comportamento legado (a formatação de data nula quebrava a tela com 500)

### Requirement: FE-298 — Estados vazios bloqueantes do formulário
O sistema SHALL se comportar conforme os cenários desta seção.
Sem portador ou sem empresa no projeto, o formulário é substituído por uma explicação.
Fonte legada: `.../structured_operations/new/_body.html.erb:3-5`, `:204-215`.

#### Scenario: Projeto sem portador
- **GIVEN** um projeto sem portadores
- **WHEN** o formulário é aberto
- **THEN** a tela mostra que é necessário ter um portador no projeto padrão para cadastrar uma operação estruturada

#### Scenario: Projeto sem empresa
- **GIVEN** um projeto com portador e sem empresa
- **WHEN** o formulário é aberto
- **THEN** a tela mostra "Esse projeto não possui empresa, clique aqui para cadastrar uma empresa no projeto e liberar a experiencia", e o atalho abre o cadastro de empresa e recarrega o formulário ao concluir

#### Scenario: Precedência das mensagens
- **GIVEN** um projeto sem portador e sem empresa
- **WHEN** o formulário é aberto
- **THEN** a mensagem sobre portador tem precedência

### Requirement: FE-299 — Detalhe da operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
O detalhe mostra o cadastro da operação em um único painel. Fonte legada:
`.../structured_operations/detail/_body.html.erb:1-26`; `detail/tabs/_tab_geral.html.erb:1-71`.

#### Scenario: Campos do detalhe
- **GIVEN** uma operação completa
- **WHEN** o detalhe é aberto
- **THEN** ele mostra Operação, Tipo, Portador, Contrato, Projeto, Data de emissão, Data vencimento, Saldo Inicial, Capital da operação, Saldo, Taxa acordada com duas casas e Observação, com `-` nos campos vazios

#### Scenario: Operação inexistente
- **GIVEN** um identificador de operação que não existe
- **WHEN** o detalhe é aberto
- **THEN** a resposta é 404 com mensagem legível, e não um erro interno
> Nota: corrige comportamento legado (o registro nulo levava a `NoMethodError` e 500 em vez de 404)

#### Scenario: Saldos exibidos com sinal
- **GIVEN** uma operação com saldo inicial e saldo armazenados como negativos
- **WHEN** o detalhe é aberto
- **THEN** os dois aparecem negativos, como no legado
> AMBIGUIDADE: D-73 — o detalhe mostra saldos negativos ao usuário enquanto o formulário mostra o valor absoluto; confirmar qual apresentação é a correta

### Requirement: FE-300 — Tela de tipos de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Tipos de OP Estruturada" lista e mantém o catálogo de tipos. Fonte legada:
`.../structured_operation_types/_body.html.erb:1-40`; `_body.js.erb:1-198`.

#### Scenario: Lista e estados
- **GIVEN** a área aberta pelo menu "Cadastro"
- **WHEN** ela é exibida
- **THEN** a lista mostra Título e Chave, ordenáveis, com estados de carregamento, vazio ("Não existem tipos de operação cadastrados") e vazio com termo de busca

#### Scenario: Estado de erro
- **GIVEN** a busca retornando erro
- **WHEN** a resposta chega
- **THEN** a tela mostra um estado de erro
> Nota: corrige comportamento legado (o tratamento de falha era um bloco vazio)

#### Scenario: Tipo padrão do sistema
- **GIVEN** um tipo marcado como padrão
- **WHEN** o menu da linha é aberto
- **THEN** a ação de excluir não é oferecida

#### Scenario: Permissão para cadastrar
- **GIVEN** um usuário que não é administrador, dono nem gerente, ou é somente-leitura
- **WHEN** a área é exibida
- **THEN** o botão de cadastro não é oferecido, e o servidor também recusa a criação
> Nota: corrige D-23 (comportamento legado: a exigência de papel existia apenas na interface)

### Requirement: FE-301 — Painel de tipo de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
O painel lateral captura título, chave de integração e situação. Fonte legada:
`.../structured_operation_types/helper/_body.html.erb:1-41`; `helper/_mount.js.erb:1-90`.

#### Scenario: Campos do painel
- **GIVEN** o painel aberto
- **WHEN** ele é exibido
- **THEN** aparecem Título (não editável na edição), Chave de integração e Ativo, e o cabeçalho identifica cadastro ou edição de tipo de operação estruturada
> Nota: corrige comportamento legado (o cabeçalho dizia "Cadastrar uma taxa"/"Editar uma taxa", rótulo herdado do painel de remunerações, e o estado vazio dizia "Essa construtora não pode ser alterada", texto de outro domínio)

#### Scenario: Confirmação de sucesso
- **GIVEN** um tipo salvo com sucesso
- **WHEN** a resposta chega
- **THEN** a tela confirma o salvamento, recarrega a lista e fecha o painel
> Nota: corrige comportamento legado (o sucesso não emitia nenhuma confirmação — só o ramo de erro produzia mensagem)

#### Scenario: Erros legíveis
- **GIVEN** um salvamento recusado por validação
- **WHEN** a resposta chega
- **THEN** a mensagem usa o nome do campo em pt-BR
> Nota: corrige comportamento legado (a chave técnica do atributo aparecia crua para o usuário)

#### Scenario: Indicadores sem tela
- **GIVEN** os indicadores de padrão, lançamento manual, lançamento por recebível e pré-faturamento
- **WHEN** o painel é exibido
- **THEN** eles não são oferecidos, como no legado
> AMBIGUIDADE: D-74 — ver BE-297; os quatro são aceitos pela API e só configuráveis por carga inicial

### Requirement: FE-302 — Exclusão de tipo de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
A exclusão pede confirmação e comunica o motivo do bloqueio quando ele existe. Fonte
legada: `.../structured_operation_types/list/_widget.js.erb:26-41`; `helper/destroy.js.erb:1-13`.

#### Scenario: Exclusão bloqueada é explicada
- **GIVEN** um tipo com operações vinculadas, ou um tipo padrão
- **WHEN** a exclusão é confirmada
- **THEN** a tela mostra a razão do bloqueio
> Nota: corrige comportamento legado (a chamada não definia tratamento de erro, então a resposta de recusa nunca era processada e, para o usuário, acionar "Remover" simplesmente não fazia nada)

#### Scenario: Exclusão bem-sucedida
- **GIVEN** um tipo removível
- **WHEN** a exclusão é confirmada
- **THEN** ele some da lista e a tela confirma a remoção

### Requirement: FE-303 — Tela de remunerações
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Remunerações" lista as taxas por tipo de operação do projeto. Fonte legada:
`.../remunerations/_body.html.erb:1-41`; `_body.js.erb:1-138`.

#### Scenario: Colunas da lista
- **GIVEN** remunerações cadastradas
- **WHEN** a área é aberta pelo menu "Projeto"
- **THEN** a lista mostra Classe (LIQ ou EST), Operação e Taxa em percentual

#### Scenario: Lista ordenável e paginada
- **GIVEN** muitas remunerações no projeto
- **WHEN** a lista é exibida
- **THEN** ela pode ser ordenada e navegada por páginas
> Nota: corrige D-20 (comportamento legado: sem ordenação e sem paginação — o cliente enviava os parâmetros e o servidor os ignorava)

#### Scenario: Estado de erro
- **GIVEN** a busca retornando erro
- **WHEN** a resposta chega
- **THEN** a tela mostra um estado de erro
> Nota: corrige comportamento legado (o tratamento de falha era um bloco vazio)

#### Scenario: Permissão para cadastrar
- **GIVEN** um usuário sem papel de administração ou somente-leitura
- **WHEN** a área é exibida
- **THEN** o botão de cadastro não é oferecido, e o servidor recusa a criação
> Nota: corrige D-23

### Requirement: FE-304 — Painel de remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
O painel captura a classe de operação, o tipo e a taxa. Fonte legada:
`.../remunerations/helper/_body.html.erb:1-35`; `helper/_body.js.erb:1-25`.

#### Scenario: Escolha da classe e do tipo
- **GIVEN** o painel aberto para cadastro
- **WHEN** o usuário escolhe "Operações estruturadas"
- **THEN** o seletor de tipo passa a oferecer os tipos de operação estruturada ativos, e apenas o tipo escolhido é enviado

#### Scenario: Edição só da taxa
- **GIVEN** uma remuneração existente
- **WHEN** o painel é aberto para edição
- **THEN** a classe e o tipo não são editáveis e apenas a taxa pode ser alterada

#### Scenario: Tipo desativado depois de cadastrado
- **GIVEN** uma remuneração cujo tipo de operação foi desativado
- **WHEN** o painel de edição é aberto
- **THEN** o tipo é exibido, ainda que desativado, e a taxa pode ser alterada
> Nota: corrige comportamento legado (os seletores só listavam tipos ativos, então a remuneração de um tipo desativado não conseguia exibir seu próprio tipo)

### Requirement: FE-305 — Máscara de percentual da remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
O campo de taxa normaliza a digitação e valida a faixa permitida. Fonte legada:
`.../remunerations/helper/_body.js.erb:27-74`.

#### Scenario: Formatação
- **GIVEN** o campo de taxa
- **WHEN** o usuário digita `2,55` e sai do campo
- **THEN** o campo exibe `2,55%` e o valor enviado é `2.55`

#### Scenario: Taxa fora da faixa
- **GIVEN** o usuário digitando `250`
- **WHEN** o campo perde o foco
- **THEN** a tela sinaliza que a taxa precisa estar entre 0 e 100, e o servidor aplica a mesma regra
> Nota: corrige comportamento legado (não havia limite em nenhuma camada, e é essa taxa que multiplica todo o faturamento — ver BE-301 e BE-305)

#### Scenario: Campo vazio
- **GIVEN** o campo deixado em branco
- **WHEN** ele perde o foco
- **THEN** o valor passa a ser `0,00`

### Requirement: FE-306 — Acesso direto às telas de remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
As telas de cadastro e edição de remuneração são alcançáveis por endereço direto. Fonte
legada: `.../remunerations/_body.js.erb:94-116`; `list/_widget.js.erb:43-66`.

#### Scenario: Abrir a edição pelo endereço
- **GIVEN** o endereço de edição de uma remuneração
- **WHEN** ele é aberto diretamente
- **THEN** o painel de edição carrega com os dados daquela remuneração
> Nota: corrige comportamento legado (o identificador era gravado com um nome e lido com outro, então pelo endereço direto o painel montava uma requisição com identificador indefinido e falhava; só o caminho pelo menu da linha funcionava)

#### Scenario: Endereço exibido após abrir o editor
- **GIVEN** o painel de edição aberto
- **WHEN** o endereço da tela é atualizado
- **THEN** ele é um endereço válido da aplicação
> Nota: corrige comportamento legado (um trecho de template escapado colocava a expressão literal do caminho na barra de endereços)

### Requirement: FE-307 — Tela de tipos de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A área de tipos de recurso lista e mantém o catálogo. Fonte legada:
`.../resource_kinds/_body.html.erb:1-32`; `helper/_body.html.erb:1-55`.

#### Scenario: Acesso pelo menu
- **GIVEN** um usuário com permissão de cadastro
- **WHEN** o menu é montado
- **THEN** existe um item que leva à tela de tipos de recurso
> Nota: corrige comportamento legado (a tela não tinha nenhum item de menu e só era alcançável digitando o endereço diretamente)

#### Scenario: Campos do painel
- **GIVEN** o painel aberto
- **WHEN** ele é exibido
- **THEN** aparecem Título, Chave de integração, Ativo, Conta Corrente e Registro único, e o estado vazio identifica o tipo de recurso
> Nota: corrige comportamento legado (o texto do painel dizia "Essa construtora não pode ser alterada", de outro domínio)

#### Scenario: Permissão de escrita
- **GIVEN** um usuário somente-leitura
- **WHEN** a área é exibida
- **THEN** o botão de cadastro e o menu de ações não são oferecidos
> Nota: corrige D-17 (comportamento legado: esta era a única tela da unidade que não respeitava a permissão somente-leitura na interface)

#### Scenario: Ordenação da lista
- **GIVEN** a lista de tipos de recurso
- **WHEN** o usuário clica em um cabeçalho
- **THEN** a lista é reordenada por aquela coluna
> Nota: corrige comportamento legado (esta lista não tinha ordenação, ao contrário da lista de fontes de recurso)

### Requirement: FE-308 — Tela de fontes de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
A área de fontes de recurso lista e mantém o catálogo usado pelos recebíveis. Fonte
legada: `.../resource_sources/_body.html.erb:1-40`; `helper/_body.html.erb:1-36`.

#### Scenario: Lista e ordenação
- **GIVEN** a área aberta pelo menu "Cadastro"
- **WHEN** ela é exibida
- **THEN** a lista mostra Título e Chave, ordenáveis, com os estados de carregamento, vazio e vazio com termo

#### Scenario: Nomenclatura distinta de tipos de recurso
- **GIVEN** as duas telas de catálogo de recursos
- **WHEN** os menus e os títulos de página são exibidos
- **THEN** cada uma tem um nome próprio, que a distingue da outra
> Nota: corrige comportamento legado (as duas telas usavam o mesmo rótulo de menu e o mesmo título de página, tornando as entidades indistinguíveis para o usuário, embora só uma seja usada pelos recebíveis)

#### Scenario: Textos do painel
- **GIVEN** o painel aberto
- **WHEN** ele é exibido
- **THEN** aparecem Título, Chave de integração e Ativo, com textos que identificam a fonte de recurso
> Nota: corrige comportamento legado (o estado vazio dizia "Essa construtora não pode ser alterada" e a lista vazia dizia "Não existem utilização de recurso cadastrado")

### Requirement: FE-309 — Permissões e sessão nas telas da unidade
O sistema SHALL se comportar conforme os cenários desta seção.
As telas da unidade dependem de sessão ativa, usuário habilitado e permissão de escrita.
Fonte legada: `app/controllers/pub_application_controller.rb:12`, `:38-54`;
`app/controllers/pub/console_controller.rb:5-7`.

#### Scenario: Sem sessão
- **GIVEN** um visitante sem sessão
- **WHEN** ele acessa qualquer tela ou endpoint da unidade
- **THEN** ele é redirecionado para o login e nenhum dado é retornado
> Nota: corrige D-23 (comportamento legado: os controllers dedicados da unidade não exigiam login pelo filtro — as ações de busca, criação, atualização e exclusão só falhavam por acidente, quando o código tocava o usuário corrente)

#### Scenario: Usuário desativado
- **GIVEN** um usuário desativado com sessão ativa
- **WHEN** ele acessa a unidade
- **THEN** a sessão é encerrada e a tela de bloqueio é exibida

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** ele percorre as cinco telas da unidade
- **THEN** nenhuma ação de escrita é oferecida, e o servidor recusa qualquer endpoint de escrita chamado diretamente
> Nota: corrige D-17 e D-23 (comportamento legado: a restrição era puramente visual, sem nenhuma verificação no servidor)

### Requirement: DB-280 — Tabela `structured_operations`
O sistema SHALL se comportar conforme os cenários desta seção.
A operação estruturada guarda identificação, datas, capital, saldos, taxa e indicadores.
Fonte legada: `db/migrate/20220701125757_create_structured_operations.rb`.

#### Scenario: Integridade referencial garantida pelo banco
- **GIVEN** uma gravação com portador inexistente
- **WHEN** ela é executada
- **THEN** o banco recusa a operação
> Nota: corrige D-103 (comportamento legado: nenhum índice além da chave primária e nenhuma chave estrangeira)

#### Scenario: Consultas da lista indexadas
- **GIVEN** a busca com filtros e janela de datas
- **WHEN** ela é executada
- **THEN** a consulta usa índices por projeto, empresa, portador, tipo e pela janela de datas
> Nota: corrige D-12 (comportamento legado: a busca fazia três junções e um intervalo de datas sem nenhum índice)

#### Scenario: Sinal do saldo inicial na carga
- **GIVEN** operações legadas com saldo inicial gravado sempre negativo
- **WHEN** a carga é executada
- **THEN** o sinal é preservado exatamente como está no legado
> Nota: DEC-02 — os números do legado são replicados (ver BE-292)
> AMBIGUIDADE: D-73 — a decisão de normalizar ou não o sinal depende da resposta sobre a movimentação de saldo

### Requirement: DB-281 — Vínculo da operação com o recibo
O sistema SHALL se comportar conforme os cenários desta seção.
`structured_operations.receipt_id` marca a operação já faturada e é a base da busca de
candidatos. Fonte legada: `db/migrate/20220802225011_create_receipts.rb:19`.

#### Scenario: Busca de candidatos indexada
- **GIVEN** um projeto com muitas operações
- **WHEN** os candidatos a recibo são montados
- **THEN** a consulta pela ausência de recibo usa índice
> Nota: corrige D-12 (comportamento legado: a coluna não tinha índice nem chave estrangeira, apesar de ser consultada em todo cálculo de candidatos)

#### Scenario: Referência circular resolvida
- **GIVEN** a dupla referência entre operação e recibo
- **WHEN** o modelo do ai9 é definido
- **THEN** a relação é mantida de forma consistente, sem estado parcial entre os dois lados
> Nota: corrige comportamento legado (ver DB-165 em receivables)

### Requirement: DB-282 — Índices e integridade referencial da unidade
O sistema SHALL se comportar conforme os cenários desta seção.
Nenhuma das cinco migrations da unidade declara chave estrangeira, e há um único índice
implícito. Fonte legada: `db/migrate/20220701125757_*`, `20220701123654_*`,
`20220629123512_*`, `20210317140213_*`, `20210317140220_*`.

#### Scenario: Chaves estrangeiras reais
- **GIVEN** o schema do ai9
- **WHEN** ele é criado
- **THEN** todas as referências entre as tabelas da unidade são chaves estrangeiras com restrição de exclusão
> Nota: corrige D-103 (comportamento legado: todas eram inteiros soltos, o que produzia recibos órfãos ao apagar remuneração e operações invisíveis quando o portador era removido)

#### Scenario: Auditoria antes da carga
- **GIVEN** a base legada
- **WHEN** a etapa de introspecção do ETL roda
- **THEN** ela reporta recibos apontando para remunerações inexistentes e operações apontando para portadores, empresas ou tipos inexistentes

### Requirement: DB-283 — Tabela `structured_operation_types`
O sistema SHALL se comportar conforme os cenários desta seção.
O tipo guarda título, chave de integração, situação e quatro indicadores. Fonte legada:
`db/migrate/20220701123654_create_structured_operation_types.rb`.

#### Scenario: Unicidade no banco
- **GIVEN** duas gravações concorrentes com o mesmo título ou a mesma chave
- **WHEN** ambas são processadas
- **THEN** apenas uma é aceita
> Nota: corrige D-103 (comportamento legado: a unicidade do título existia só na aplicação e a chave de integração não tinha unicidade alguma)

#### Scenario: Filtro por situação
- **GIVEN** tipos ativos e desativados
- **WHEN** a consulta por tipos ativos é executada
- **THEN** ela usa uma condição parametrizada sobre a coluna de situação
> Nota: corrige comportamento legado (a condição era um fragmento de SQL literal, não portável)

### Requirement: DB-284 — Tabela `remunerations`
O sistema SHALL se comportar conforme os cenários desta seção.
A remuneração guarda o projeto, a referência polimórfica ao tipo de operação e a taxa.
Fonte legada: `db/migrate/20220629123512_create_remunerations.rb`.

#### Scenario: Unicidade da combinação no banco
- **GIVEN** duas gravações concorrentes para o mesmo projeto, classe e tipo
- **WHEN** ambas são processadas
- **THEN** apenas uma é aceita
> Nota: corrige D-103 (comportamento legado: a unicidade existia só na aplicação, sujeita a corrida — e é ela que garante que a busca da taxa encontre uma única remuneração)

#### Scenario: Consulta por projeto indexada
- **GIVEN** a listagem e a busca de taxa por projeto
- **WHEN** elas são executadas
- **THEN** a consulta usa índice por projeto

#### Scenario: Precisão da taxa
- **GIVEN** a taxa que multiplica todo o faturamento
- **WHEN** ela é gravada e usada no cálculo
- **THEN** o resultado é idêntico ao do legado
> Nota: DEC-02 — a taxa é armazenada em ponto flutuante no legado e a sequência de operações é replicada para os totais baterem

### Requirement: DB-285 — Título da remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
`remunerations.title` é uma cópia do título do tipo de operação, reescrita a cada
gravação. Fonte legada: `db/migrate/20220802165837_add_title_to_remuneration.rb`.

#### Scenario: Título acompanha o tipo
- **GIVEN** uma remuneração cujo tipo foi renomeado
- **WHEN** ela é gravada novamente
- **THEN** o título acompanha o novo nome do tipo

#### Scenario: Remunerações anteriores à coluna
- **GIVEN** remunerações criadas antes da introdução da coluna, com título nulo
- **WHEN** a carga é executada
- **THEN** o título é preenchido a partir do tipo antes da inserção

### Requirement: DB-286 — Tabela `resource_kinds`
O sistema SHALL se comportar conforme os cenários desta seção.
O tipo de recurso guarda título, chave, situação e dois indicadores. Fonte legada:
`db/migrate/20210317140213_create_resource_kinds.rb`.

#### Scenario: Unicidade no banco
- **GIVEN** duas gravações com o mesmo título
- **WHEN** ambas são processadas
- **THEN** apenas uma é aceita
> Nota: corrige D-103 (comportamento legado: sem índice único em título nem em chave de integração)

#### Scenario: Origem dos registros
- **GIVEN** os cinco registros semeados do legado
- **WHEN** a carga é executada
- **THEN** eles são migrados com título, chave, situação e os dois indicadores preservados
> AMBIGUIDADE: D-74 — a entidade não tem coluna de proveniência do sistema anterior e é praticamente morta (ver BE-307 e DB-289); confirmar o descarte antes de migrar

### Requirement: DB-287 — Tabela `resource_sources`
O sistema SHALL se comportar conforme os cenários desta seção.
A fonte de recurso guarda título, chave e situação, e é obrigatória em todo recebível.
Fonte legada: `db/migrate/20210317140220_create_resource_sources.rb`.

#### Scenario: Unicidade no banco
- **GIVEN** duas gravações com o mesmo título
- **WHEN** ambas são processadas
- **THEN** apenas uma é aceita
> Nota: corrige D-103 (comportamento legado: sem índice único em título)

#### Scenario: Exclusão bloqueada por uso
- **GIVEN** uma fonte referenciada por recebíveis
- **WHEN** a exclusão é tentada
- **THEN** ela é recusada

#### Scenario: Papel na modelagem
- **GIVEN** a fonte de recurso de um recebível
- **WHEN** os valores do recebível são calculados
- **THEN** ela não participa de nenhuma fórmula, servindo apenas para classificação e relatório

### Requirement: DB-288 — Proveniência das fontes de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
As fontes de recurso trazem o identificador do sistema anterior, com índice único. Fonte
legada: `db/migrate/20210402111120_add_legacy_id_to_entries_and_projects.rb:2`, `:6-7`;
`app/models/legacy/resource_source.rb`.

#### Scenario: Proveniência preservada
- **GIVEN** fontes importadas do sistema anterior
- **WHEN** a carga para o ai9 é executada
- **THEN** o identificador de origem é preservado
> Nota: DEC-12 — o código do ETL não é portado, mas as colunas de proveniência são preservadas

#### Scenario: Colisão entre semeados e importados
- **GIVEN** fontes semeadas e fontes importadas com o mesmo título
- **WHEN** a carga é executada
- **THEN** a colisão é reportada antes da inserção, em vez de falhar no meio da carga

### Requirement: DB-289 — Coluna órfã de tipo de recurso em recebíveis
O sistema SHALL se comportar conforme os cenários desta seção.
`receivable_entries.resource_kind_id` existe e é aceita pelos parâmetros de recebível,
mas nunca é preenchida. Fonte legada:
`db/migrate/20210315183541_create_receivable_entries.rb:11`;
`app/controllers/pub/receivables_controller.rb:191`.

#### Scenario: Verificação antes do descarte
- **GIVEN** a base legada
- **WHEN** a etapa de introspecção do ETL roda
- **THEN** ela reporta quantos recebíveis têm tipo de recurso preenchido
> AMBIGUIDADE: D-74 — não há campo no formulário, não há validação e nenhuma consulta lê a coluna, o que torna a proteção de exclusão de tipos de recurso inoperante; o descarte só pode ser decidido depois dessa contagem

#### Scenario: Coluna sem consumidor
- **GIVEN** um recebível gravado pela tela
- **WHEN** ele é consultado
- **THEN** o tipo de recurso vem vazio, como no legado

### Requirement: DB-290 — Tabela `receipts` como materialização da remuneração
O sistema SHALL se comportar conforme os cenários desta seção.
O recibo congela taxa, título, sigla, capital e valor no momento da emissão. Fonte
legada: `db/migrate/20220802225011_create_receipts.rb`.

#### Scenario: Valores congelados
- **GIVEN** um recibo emitido com taxa 2,55
- **WHEN** a remuneração é alterada depois
- **THEN** o recibo mantém a taxa, o título e o valor do momento da emissão

#### Scenario: Unicidade por operação e projeto no banco
- **GIVEN** duas gravações concorrentes de recibo para a mesma operação e projeto
- **WHEN** ambas são processadas
- **THEN** apenas uma é aceita
> Nota: corrige D-103 (comportamento legado: a unicidade existia só na aplicação)

#### Scenario: Precisão do valor
- **GIVEN** a taxa em ponto flutuante multiplicando um capital decimal
- **WHEN** o valor é gravado
- **THEN** o resultado é idêntico ao do legado
> Nota: DEC-02 — o arredondamento implícito da gravação é replicado (ver BE-305)

### Requirement: DB-291 — Tabela de taxas de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
Não existe tabela de taxas de operação estruturada no legado. Fonte legada: busca em
`db/migrate/`, `db/seeds.rb` e `app/models/`.

#### Scenario: Nada a migrar
- **GIVEN** as rotas órfãs de taxas de operação estruturada (BE-309)
- **WHEN** a carga de dados é planejada
- **THEN** não existe tabela nem dado correspondente
> Nota: DEC-09 — qualquer funcionalidade de taxas por operação estruturada seria feature nova, não paridade

### Requirement: DB-292 — Carga inicial dos tipos de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
O legado semeia quatro tipos, todos marcados como padrão do sistema. Fonte legada:
`db/seeds.rb:334-339`.

#### Scenario: Tipos e chaves preservados
- **GIVEN** um ambiente novo do ai9
- **WHEN** a carga inicial é executada
- **THEN** existem Fomento, Comissária, Intercompany e Auto Liquidável, com as chaves `fomento`, `comissaria`, `intercompany` e `auto_liquidavel`, sem pré-faturamento e sem lançamento por recebível

#### Scenario: Nenhum tipo padrão é removível
- **GIVEN** os quatro tipos semeados
- **WHEN** a exclusão de qualquer um é tentada
- **THEN** ela é recusada

#### Scenario: Autoria dos registros semeados
- **GIVEN** os registros da carga inicial
- **WHEN** eles são criados
- **THEN** a autoria é consistente entre os quatro
> Nota: corrige comportamento legado (três tipos eram criados com um autor e o quarto com outro, ambos identificadores fixos no arquivo)

### Requirement: DB-293 — Carga inicial das fontes de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
O legado semeia sete fontes de recurso, que convivem com as importadas do sistema
anterior. Fonte legada: `db/seeds.rb:187-195`.

#### Scenario: Fontes semeadas
- **GIVEN** um ambiente novo do ai9
- **WHEN** a carga inicial é executada
- **THEN** existem Caixa, Comissária, Defasagem, Fomento, Garantia, Recompra e Retenção, ativas, com as chaves derivadas dos títulos

#### Scenario: Coexistência com registros importados
- **GIVEN** um ambiente que também recebe as fontes importadas do sistema anterior
- **WHEN** a carga inicial é executada
- **THEN** títulos coincidentes são reconciliados em vez de gerarem falha de unicidade

### Requirement: DB-294 — Carga inicial dos tipos de recurso
O sistema SHALL se comportar conforme os cenários desta seção.
O legado semeia cinco tipos de recurso, o único lugar em que os dois indicadores recebem
valores distintos. Fonte legada: `db/seeds.rb:197-203`.

#### Scenario: Tipos semeados
- **GIVEN** um ambiente novo do ai9
- **WHEN** a carga inicial é executada
- **THEN** existem Antecipação de Recebíveis (desativado, com conta corrente e registro único ligados) e Comissária, Desconto de Títulos, Fomento e Intercompany (ativos, com os dois indicadores desligados)
> AMBIGUIDADE: D-74 — como nenhum código lê os dois indicadores, a semântica desses valores está perdida e precisa vir do negócio

#### Scenario: Grafia dos títulos
- **GIVEN** o título semeado sem acentuação no legado
- **WHEN** a carga inicial do ai9 é executada
- **THEN** o título é gravado com a grafia correta em pt-BR

### Requirement: DB-295 — Representação de indicadores booleanos
O sistema SHALL se comportar conforme os cenários desta seção.
Todos os indicadores da unidade são inteiros no legado, consultados ora como verdade
lógica ora por comparação com um. Fonte legada: as quatro migrations de criação da
unidade.

#### Scenario: Conversão na carga
- **GIVEN** indicadores gravados como inteiros no legado
- **WHEN** a carga é executada
- **THEN** qualquer valor diferente de zero vira verdadeiro e zero vira falso, e o relatório lista os registros com valores fora de zero e um

#### Scenario: Indicadores no ai9
- **GIVEN** o schema do ai9
- **WHEN** ele é criado
- **THEN** os indicadores são booleanos obrigatórios com valor padrão

### Requirement: DB-296 — Precisão de valores monetários e de taxas
O sistema SHALL se comportar conforme os cenários desta seção.
A unidade mistura valores decimais com taxas em ponto flutuante, e a fórmula do recibo
multiplica os dois. Fonte legada: `create_structured_operations.rb:12-14`, `:16`;
`create_remunerations.rb:6`; `create_receipts.rb:11-13`.

#### Scenario: Totais idênticos aos do legado
- **GIVEN** operações e remunerações migradas
- **WHEN** os recibos e os totais de cobrança são recalculados no ai9
- **THEN** os valores produzidos são idênticos aos do legado
> Nota: DEC-02 — a sequência de operações, os casts e os pontos de arredondamento do legado são replicados; o tipo de armazenamento no ai9 pode ser decimal desde que o resultado bata

#### Scenario: Política de arredondamento documentada
- **GIVEN** um produto com mais de duas casas decimais
- **WHEN** o valor é gravado
- **THEN** a política de arredondamento aplicada é explícita e testada, e não um efeito colateral do tipo da coluna

### Requirement: DB-297 — Autoria dos registros da unidade
O sistema SHALL se comportar conforme os cenários desta seção.
As quatro tabelas guardam um identificador de usuário sem associação declarada, exceto na
operação estruturada. Fonte legada: `create_structured_operations.rb:5`;
`create_structured_operation_types.rb:7`; `create_resource_kinds.rb:7`;
`create_resource_sources.rb:7`.

#### Scenario: Autoria não forjável
- **GIVEN** um payload informando outro usuário como autor
- **WHEN** o registro é gravado
- **THEN** a autoria registrada é a do usuário da sessão
> Nota: corrige comportamento legado (nos catálogos o autor vinha de um campo escondido do formulário e nunca era verificado, sendo possível forjá-lo)

#### Scenario: Autoria e última edição
- **GIVEN** uma operação criada por um usuário e editada por outro
- **WHEN** ela é consultada
- **THEN** é possível distinguir quem criou de quem editou por último
> Nota: corrige comportamento legado (o mesmo campo era sobrescrito na criação e na edição, então o autor virava o último editor)

### Requirement: OPS-280 — Rotas órfãs de taxas de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
As oito rotas geradas para taxas de operação estruturada não têm nenhum código de
suporte. Fonte legada: `config/routes.rb:107-108`.

#### Scenario: Rotas removidas
- **GIVEN** o ai9 em execução
- **WHEN** as rotas da aplicação são inspecionadas
- **THEN** nenhuma rota de taxas de operação estruturada existe
> Nota: DEC-09 — código morto comprovado por varredura exaustiva (ver BE-309)

### Requirement: OPS-281 — Templates ausentes das rotas REST da unidade
O sistema SHALL se comportar conforme os cenários desta seção.
Cinco ações de índice e três de detalhe do legado renderizam templates que não existem no
repositório. Fonte legada: `app/views/pub/` comparado com os controllers da unidade.

#### Scenario: Caminhos de tela são rotas reais
- **GIVEN** o ai9 em execução
- **WHEN** o usuário acessa o endereço de qualquer tela da unidade
- **THEN** a tela correspondente é carregada
> Nota: corrige comportamento legado (esses endereços produziam erro por template ausente, e toda a navegação real passava por um único controller de console)

### Requirement: OPS-282 — Busca textual insensível a maiúsculas
O sistema SHALL se comportar conforme os cenários desta seção.
Todas as buscas textuais da unidade montavam o fragmento de consulta conforme o adaptador
detectado em execução. Fonte legada: `config/initializers/dev.rb:1-21`.

#### Scenario: Busca insensível a maiúsculas
- **GIVEN** um tipo cadastrado como "Auto Liquidável"
- **WHEN** o usuário busca por "auto liquidavel"
- **THEN** o registro é encontrado

#### Scenario: Termo com caractere especial
- **GIVEN** um termo contendo `%` ou `_`
- **WHEN** a busca é executada
- **THEN** ele é tratado como texto literal
> Nota: corrige comportamento legado (o fragmento era interpolado direto na consulta; o valor ia por vínculo, então não havia injeção pelo termo, mas o padrão é frágil)

### Requirement: OPS-283 — Datas-sentinela nos filtros da unidade
O sistema SHALL se comportar conforme os cenários desta seção.
O legado usa datas de hoje menos e mais 2000 anos como limites abertos do filtro de
período. Fonte legada: `config/initializers/date_overload.rb:1-17`.

#### Scenario: Limites ausentes omitem a condição
- **GIVEN** uma busca de operações sem data inicial nem final
- **WHEN** a consulta é montada
- **THEN** nenhuma condição de período é aplicada
> Nota: corrige comportamento legado (as datas-sentinela podem estourar a faixa de data do banco e excluíam operações com datas nulas — ver BE-282)

#### Scenario: Apenas um limite informado
- **GIVEN** somente a data inicial informada
- **WHEN** a consulta é montada
- **THEN** apenas a condição correspondente é aplicada

### Requirement: OPS-284 — Textos de ajuda do formulário de operação estruturada
O sistema SHALL se comportar conforme os cenários desta seção.
Os textos de ajuda dos 13 campos do formulário vêm de um arquivo de conteúdo lido a cada
renderização. Fonte legada: `db/seed_assets/structured_operations_help_inputs.yml`.

#### Scenario: Ajuda servida de cache
- **GIVEN** o formulário sendo aberto muitas vezes
- **WHEN** os textos são resolvidos
- **THEN** eles vêm de cache, e a ausência do arquivo de conteúdo não derruba a tela
> Nota: corrige comportamento legado (leitura síncrona de disco a cada requisição, e ausência do arquivo produzia erro na abertura do formulário)

#### Scenario: Conteúdo dos textos
- **GIVEN** os 13 campos do formulário
- **WHEN** a ajuda é exibida
- **THEN** cada campo tem seu próprio texto explicativo
> AMBIGUIDADE: no legado as 13 entradas contêm o mesmo texto placeholder; é preciso o conteúdo real

### Requirement: OPS-285 — Importação das fontes de recurso do sistema anterior
O sistema SHALL se comportar conforme os cenários desta seção.
As fontes de recurso foram importadas por um ETL manual do sistema Django anterior. Fonte
legada: `app/models/legacy/resource_source.rb`; `app/models/legacy.rb:2-48`.

#### Scenario: ETL não é portado
- **GIVEN** o pipeline legado de importação
- **WHEN** a migração para o ai9 é executada
- **THEN** ele não é portado, e apenas as colunas de proveniência dos registros são preservadas
> Nota: DEC-12 — assumido que o pipeline não roda desde 2021

#### Scenario: Autoria artificial dos importados
- **GIVEN** que o ETL antigo forçava um autor fixo em todas as fontes importadas
- **WHEN** a carga para o ai9 é executada
- **THEN** o relatório identifica os registros com essa marca
> AMBIGUIDADE: confirmar se a autoria desses registros deve ser reatribuída ou mantida

#### Scenario: Tipos de recurso fora da importação
- **GIVEN** o catálogo de tipos de recurso
- **WHEN** a proveniência é avaliada
- **THEN** fica registrado que ele nunca participou da importação do sistema anterior (ver DB-286)

### Requirement: OPS-286 — Presença das telas da unidade no menu do console
O sistema SHALL se comportar conforme os cenários desta seção.
Quatro das cinco telas da unidade têm item de menu, com títulos de página que se repetem
entre telas diferentes. Fonte legada: `app/helpers/application_helper.rb:115`, `:133`,
`:153`, `:155`; `app/controllers/pub/console_controller.rb:348-349`, `:358-359`, `:394-399`.

#### Scenario: Itens de menu da unidade
- **GIVEN** um usuário com projeto e papel de administração
- **WHEN** o menu é montado
- **THEN** existem itens para operações estruturadas, remunerações, tipos de operação estruturada, fontes de recurso e tipos de recurso
> Nota: corrige comportamento legado (a tela de tipos de recurso não tinha item de menu — ver FE-307)

#### Scenario: Títulos de página distintos
- **GIVEN** as telas da unidade
- **WHEN** os títulos de página são montados
- **THEN** cada tela tem um título próprio que a identifica
> Nota: corrige comportamento legado (operações estruturadas e tipos de operação recebiam o título de outra área, e as duas telas de recursos recebiam títulos idênticos)

### Requirement: OPS-287 — Cobertura de testes da unidade
O sistema SHALL se comportar conforme os cenários desta seção.
O legado não tem nenhum teste automatizado para as entidades da unidade nem para a
fórmula de remuneração. Fonte legada: ausência de `spec/` e `test/` no repositório legado.

#### Scenario: Fórmula coberta por testes de paridade
- **GIVEN** a fórmula de remuneração e os totais de cobrança
- **WHEN** o slice é implementado no ai9
- **THEN** existem testes que travam os valores extraídos do legado, executados antes de qualquer refatoração
> Nota: corrige D-114 (comportamento legado: nenhuma verificação automática da fórmula que define todo o faturamento)

### Requirement: OPS-288 — Parâmetros de ordenação das listas da unidade
O sistema SHALL se comportar conforme os cenários desta seção.
A cláusula de ordenação é montada por concatenação, a partir de uma lista fechada de
chaves. Fonte legada: `app/models/structured_operation.rb:60-107`;
`app/models/structured_operation_type.rb:30-58`; `app/models/resource_source.rb:22-50`.

#### Scenario: Chave desconhecida
- **GIVEN** uma chave de ordenação fora da lista aceita
- **WHEN** a busca é executada
- **THEN** a resposta é um erro de requisição inválida, e não um erro interno
> Nota: corrige comportamento legado (a chave desconhecida produzia `NoMethodError` não tratado, devolvendo 500 a cada requisição — um vetor de indisponibilidade)

#### Scenario: Parâmetro em formato inesperado
- **GIVEN** a lista de chaves de ordenação enviada como texto em vez de lista
- **WHEN** a busca é executada
- **THEN** a resposta é um erro de requisição inválida

### Requirement: OPS-289 — Formatação de valores e percentuais da unidade
O sistema SHALL se comportar conforme os cenários desta seção.
Valores e taxas são exibidos em reais e em percentual no padrão brasileiro. Fonte legada:
`config/initializers/type_casting.rb:31-90`.

#### Scenario: Formatação monetária
- **GIVEN** o valor 200000
- **WHEN** ele é exibido
- **THEN** aparece como `R$ 200.000,00`

#### Scenario: Formatação da taxa
- **GIVEN** a taxa 2,55
- **WHEN** ela é exibida na lista de remunerações e no detalhe da operação
- **THEN** os dois lugares usam o mesmo formato, com duas casas e indicação de percentual
> Nota: corrige comportamento legado (a taxa da lista de remunerações era exibida sem símbolo de percentual na célula e a taxa acordada da lista de operações era impressa crua — ver FE-289)

#### Scenario: Falha de formatação
- **GIVEN** um valor inesperado
- **WHEN** a formatação é aplicada
- **THEN** a falha é registrada em vez de silenciosamente devolver o número cru
> Nota: corrige comportamento legado (a formatação engolia qualquer exceção e devolvia o número sem formato, escondendo o problema)
