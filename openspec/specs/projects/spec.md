# Projects Specification

## Purpose
Projeto e a unidade de escopo de quase todo o Safegold: ele define o tenant corrente,
carrega membros, portadores conectados, indicadores, garantias e a arvore de padroes
de disponibilidade. Esta capacidade cobre o cadastro de projetos, seus efeitos
colaterais de criacao, as conexoes com portadores e indicadores, as garantias e seus
tipos, e o esquema e as rotinas de apoio.
Cobre os IDs 080–119 e 700–706 do inventario (`.migration-ai9/feature-inventory.md`).

## Requirements

### Requirement: BE-080 — Busca de projetos do usuario
O sistema DEVE (SHALL) listar apenas os projetos dos quais o usuario e membro, com filtro textual por nome, ordenacao e paginacao efetivas. Fonte legada: `config/routes.rb:57`; `app/controllers/pub/projects_controller.rb:14-37`, `:191-199`.

#### Scenario: Escopo de membership
- **GIVEN** um usuario que e membro de 3 dos 50 projetos existentes
- **WHEN** ele lista projetos
- **THEN** apenas os 3 projetos dos quais e membro sao devolvidos

#### Scenario: Paginacao aplicada
- **GIVEN** um usuario membro de 45 projetos
- **WHEN** ele pede `l=20`, `o=20`
- **THEN** sao devolvidos 20 projetos a partir do 21o, na ordem pedida, e o total informado e 45

> Nota: corrige D-20 (legado: no ramo nao-dash o `@projects.where!(...)` era encadeado com `.order/.limit/.offset` sem reatribuir — paginacao e ordenacao eram descartadas e a lista voltava inteira). Muda o que a tela faz: hoje traz tudo.

#### Scenario: Busca insensivel a caixa
- **GIVEN** um projeto chamado `Obra Central`
- **WHEN** o usuario busca por `central`
- **THEN** o projeto aparece no resultado

### Requirement: BE-081 — Modo "dash" da busca de projetos
O sistema DEVE (SHALL) oferecer um modo de resumo que devolve projetos ordenados por data de atualizacao ascendente, com limite e offset aplicados, ignorando o filtro textual. Fonte legada: `app/controllers/pub/projects_controller.rb:27-29`.

#### Scenario: Resumo por data de atualizacao
- **GIVEN** um usuario membro de varios projetos
- **WHEN** ele pede o modo dash com `l=5`
- **THEN** sao devolvidos 5 projetos ordenados por data de atualizacao ascendente e o termo de busca e ignorado

### Requirement: BE-082 — Filtro por identificador de importacao e por id de projeto
O sistema DEVE (SHALL) permitir filtrar a lista por identificador de importacao ou por id de projeto, sempre dentro do escopo de membership do usuario. Fonte legada: `app/controllers/pub/projects_controller.rb:15-23`.

#### Scenario: Id de projeto fora do escopo do usuario
- **GIVEN** um projeto do qual o usuario nao e membro
- **WHEN** ele lista projetos informando o id desse projeto
- **THEN** o resultado e vazio e nenhum dado do projeto alheio e devolvido

> Nota: corrige D-29 (legado: `Project.where(importing_id: ...)` e `Project.where(id: params[:project_id])` ignoravam completamente a associacao do usuario — qualquer usuario autenticado lia qualquer projeto informando o id). DEC-07: o escopo vem do JWT validado contra membership.

### Requirement: BE-083 — Autocomplete de escolha de projeto
O sistema DEVE (SHALL) oferecer um autocomplete de projetos do usuario, com busca textual consistente com a listagem principal e com limite de resultados. Fonte legada: `config/routes.rb:56`; `app/controllers/pub/projects_controller.rb:41-45`.

#### Scenario: Busca insensivel a caixa no autocomplete
- **GIVEN** um projeto chamado `Obra Central`
- **WHEN** o usuario digita `obra` no autocomplete
- **THEN** o projeto aparece nas sugestoes

> Nota: corrige a divergencia acidental do legado (o autocomplete usava `LIKE` cru, case-sensitive no Postgres, enquanto a listagem usava `Dev.ilike`; e nao havia limite — retornava todos os projetos do usuario).

### Requirement: BE-084 — Formulario de cadastro/edicao de projeto
O sistema DEVE (SHALL) fornecer os dados do formulario de projeto, incluindo a lista de usuarios que o solicitante pode indicar como responsavel, filtrada pela hierarquia de papeis. Fonte legada: `app/controllers/pub/projects_controller.rb:47-63`; `app/decorators/models/user_decorator.rb:167-177`.

#### Scenario: Usuarios disponiveis por papel
- **GIVEN** um usuario com papel `manager`
- **WHEN** ele abre o formulario de novo projeto
- **THEN** a lista de responsaveis possiveis contem apenas usuarios de papel `manager` e colaborador

### Requirement: BE-085 — Criar projeto criando um novo usuario responsavel
O sistema DEVE (SHALL) permitir criar um projeto junto com um novo usuario responsavel, definindo esse usuario como responsavel do projeto e enviando a ele um convite para definir a propria senha. Fonte legada: `app/controllers/pub/projects_controller.rb:65-127`, `:71-98`.

#### Scenario: Criacao conjunta bem-sucedida
- **GIVEN** um usuario autorizado a criar projetos
- **WHEN** ele cria um projeto informando nome e e-mail de um novo responsavel
- **THEN** o projeto e o usuario sao criados, o usuario fica registrado como responsavel e recebe um link para definir a senha

> Nota: corrige D-38 na parte que toca este fluxo (legado: o `@data_hash` montado em `:71-98` carregava **username e senha em texto plano** para a view). No ai9 nenhuma senha e montada, exibida ou enviada.

#### Scenario: Erro na criacao do usuario nao cria projeto pela metade
- **GIVEN** um e-mail de responsavel ja usado por outro usuario
- **WHEN** a criacao conjunta e submetida
- **THEN** nem o projeto nem o usuario sao criados e os erros sao devolvidos identificando o campo do responsavel

### Requirement: BE-086 — Criar projeto sem responsavel
O sistema DEVE (SHALL) permitir criar um projeto sem responsavel vinculado, guardando apenas nome e e-mail informados como texto. Fonte legada: `app/controllers/pub/projects_controller.rb:99-105`.

#### Scenario: Projeto sem responsavel
- **GIVEN** um usuario autorizado
- **WHEN** ele cria um projeto escolhendo a opcao sem responsavel
- **THEN** o projeto e criado, pertence a quem o criou, e o detalhe apresenta o responsavel como nao definido

### Requirement: BE-087 — Criar projeto com responsavel existente
O sistema DEVE (SHALL) permitir criar um projeto indicando um usuario existente como responsavel, copiando dele o nome e o e-mail de exibicao. Fonte legada: `app/controllers/pub/projects_controller.rb:106-112`.

#### Scenario: Responsavel nao informado
- **GIVEN** a opcao "responsavel existente" escolhida sem selecionar nenhum usuario
- **WHEN** a criacao e submetida
- **THEN** a resposta e 422 pedindo a selecao do responsavel, e nao um erro interno

> Nota: corrige o `NoMethodError` do legado (`@project.responsible.formal` com `responsible_id` em branco resultava em 500).

#### Scenario: Posse do projeto apos indicar responsavel
- **GIVEN** um usuario A criando um projeto e indicando o usuario B como responsavel
- **WHEN** o projeto e criado
- **THEN** a posse do projeto segue a regra definida e ambos, A e B, tem acesso ao projeto

> AMBIGUIDADE: no legado o criador **perdia a posse** (`user_id = responsible_id`), ficando sem `Membership` de responsavel proprio. Confirmar se e o comportamento desejado ou se o criador deve permanecer com acesso explicito.

### Requirement: BE-088 — Efeitos colaterais automaticos da criacao de projeto
Ao criar um projeto o sistema DEVE (SHALL) registrar o vinculo de responsavel, vincular os usuarios marcados como membro padrao, criar a empresa padrao do projeto e gerar os padroes de disponibilidade globais, com o progresso de cada tarefa rastreado separadamente. Fonte legada: `app/models/project.rb:69-89`.

#### Scenario: Projeto novo nasce utilizavel
- **GIVEN** um usuario autorizado e usuarios marcados como membro padrao
- **WHEN** um projeto e criado
- **THEN** o responsavel tem vinculo de responsavel, os membros padrao tem vinculo de participante, existe a empresa padrao e os padroes de disponibilidade globais sao replicados para o projeto

#### Scenario: Progresso de duas tarefas simultaneas
- **GIVEN** um projeto recem-criado com duas tarefas em segundo plano em andamento
- **WHEN** o usuario consulta o progresso
- **THEN** o progresso de cada tarefa e informado separadamente

> Nota: corrige o legado, onde os dois jobs gravavam no **mesmo** `job_id`/`job_state` do projeto — o segundo sobrescrevia o primeiro e o painel mostrava so um. Corrige tambem a criacao duplicada dos vinculos padrao (inline no callback e depois pelo job, com a segunda barrada pela validacao de unicidade).

### Requirement: BE-089 — Atualizar projeto
O sistema DEVE (SHALL) atualizar os dados do projeto e, quando o responsavel mudar, garantir o vinculo do novo responsavel. Fonte legada: `app/controllers/pub/projects_controller.rb:129-148`, `:236-267`; `app/models/project.rb:95-100`.

#### Scenario: Troca de responsavel cria o vinculo
- **GIVEN** um projeto com responsavel A
- **WHEN** o responsavel e alterado para B
- **THEN** B passa a ter vinculo com o projeto e o nome e o e-mail de exibicao do responsavel sao sincronizados a partir de B

#### Scenario: Marca de BI nao muda por este endpoint
- **GIVEN** um projeto com a marca de BI desligada
- **WHEN** a atualizacao geral e enviada tentando ligar a marca de BI
- **THEN** a marca permanece desligada (ela so muda pelo endpoint dedicado, BE-094)

### Requirement: BE-090 — Registro de progresso de onboarding do projeto
O sistema DEVE (SHALL) registrar o progresso de onboarding informado para o projeto. Fonte legada: `app/controllers/pub/projects_controller.rb:134-136`; `lib/tracking_facade.rb`.

#### Scenario: Registro de etapa concluida
- **GIVEN** um projeto em onboarding
- **WHEN** o cliente informa a ultima etapa concluida
- **THEN** o registro de progresso e gravado e fica disponivel na trilha de auditoria do projeto

> **RESOLVIDA em 27/08/2026 — e a resposta e: ninguem, porque nunca rodou.**
>
> `pub/projects_controller.rb:135` chama `TrackingFacade.track_new_project`, e
> a classe **nao define esse metodo**: sao 22 `def self.` em
> `lib/tracking_facade.rb` e nenhum e ele, sem `method_missing` nem
> `define_method`. E **ninguem envia `update_type=update_progress`** — o `grep`
> no `app/` inteiro so encontra a propria condicional (os outros
> `update_progress` sao o delegate da barra de job, outra coisa).
>
> Ramo inalcancavel que, se alcancado, levantaria `NoMethodError`. **Nao ha
> comportamento a replicar**, entao DEC-30 nao se aplica. O requisito e
> `dropped`; a trilha de auditoria do projeto vive em `has_paper_trail`
> (DEC-59 / DC-15), que cobre o update inteiro em vez de uma etapa avulsa.

### Requirement: BE-091 — Remover projeto
O sistema DEVE (SHALL) remover um projeto sem dados dependentes e DEVE (SHALL) bloquear a remocao, com erro visivel, quando houver portadores, indicadores, recebiveis, renegociacoes, empresas, controles de risco ou lancamentos de disponibilidade vinculados. Fonte legada: `app/controllers/pub/projects_controller.rb:175-188`; `app/models/project.rb:12-22`.

#### Scenario: Remocao bloqueada por dados dependentes
- **GIVEN** um projeto com recebiveis lancados
- **WHEN** o usuario solicita a remocao
- **THEN** a resposta e 422 informando o que bloqueia, o projeto continua existindo e a interface nao navega para fora

> Nota: corrige D-24 (legado: o status era `:ok` mesmo com erro (`:185`) e o JS do widget redirecionava para a lista de qualquer jeito — o usuario via "removido com sucesso" sem ter removido).

#### Scenario: Remocao permitida
- **GIVEN** um projeto sem nenhum dado dependente
- **WHEN** o usuario solicita a remocao
- **THEN** o projeto e removido junto com seus vinculos de membro e fornecedores

### Requirement: BE-092 — Limpar projeto de treinamento
O sistema DEVE (SHALL) permitir limpar (zerar) um projeto marcado como treinamento, apagando todo o dado transacional e recriando o estado inicial, e DEVE (SHALL) impedir a remocao definitiva desse tipo de projeto. Fonte legada: `app/controllers/pub/projects_controller.rb:176-177`; `app/models/project.rb:102-107`, `:687-745`.

#### Scenario: Limpeza de projeto de treinamento
- **GIVEN** um projeto de treinamento com lancamentos, empresas, fornecedores e templates
- **WHEN** o usuario aciona a limpeza
- **THEN** o dado transacional e removido, a empresa padrao e os padroes de disponibilidade globais sao recriados, os vinculos de membro sao restabelecidos e a mensagem informa que o projeto foi limpo

#### Scenario: Segmento apos a limpeza
- **GIVEN** um projeto de treinamento associado a um segmento
- **WHEN** a limpeza e executada
- **THEN** o segmento resultante e resolvido pela configuracao do ambiente, nunca por um identificador fixo

> Nota: corrige D-26 (legado: `Project#reset` forcava `segment_id = 1` — id fixo hardcoded que depende de uma linha especifica existir no banco).

#### Scenario: Projeto de treinamento nao pode ser removido
- **GIVEN** um projeto marcado como treinamento
- **WHEN** o usuario tenta remove-lo definitivamente
- **THEN** a operacao e recusada com a mensagem de que projeto de treinamento nao pode ser removido

### Requirement: BE-093 — Marca "Gerido pela Safegold"
O sistema DEVE (SHALL) permitir ligar e desligar a marca de gestao Safegold do projeto, refletindo o novo valor de forma consistente para os registros do projeto. Fonte legada: `config/routes.rb:59`; `app/controllers/pub/projects_controller.rb:150-160`; `app/models/project.rb:298-304`.

#### Scenario: Desligar a marca no projeto
- **GIVEN** um projeto com a marca ligada, com empresas e com lancamentos historicos
- **WHEN** o usuario desliga a marca
- **THEN** a nova marca vale para o projeto e a regra definida para os registros existentes e aplicada de forma uniforme

> AMBIGUIDADE: D-30 — no legado a marca e um carimbo denormalizado copiado no `before_validation` de `Company`, `AvailabilityEntry`, `ReceivableEntry`, `Renegotiation`, `RiskControl` e `RiskEntry`, mas **so `companies` e atualizado em massa** quando a flag muda; os demais registros ficam com o carimbo antigo. Confirmar se o carimbo e intencional (foto do momento, para relatorio historico) ou bug — a resposta define se no ai9 o valor e derivado do projeto ou armazenado por lancamento. Nenhum consumidor a jusante foi encontrado no repositorio.

### Requirement: BE-094 — Marca "BI contratado"
O sistema DEVE (SHALL) permitir ligar e desligar a marca de BI contratado do projeto. Fonte legada: `config/routes.rb:60`; `app/controllers/pub/projects_controller.rb:162-172`; `app/models/project.rb:307-310`.

#### Scenario: Alternar a marca de BI
- **GIVEN** um projeto com a marca de BI desligada
- **WHEN** um usuario autorizado a liga
- **THEN** o detalhe do projeto passa a apresentar a marca ligada

> AMBIGUIDADE: D-31 — `has_bi` **nao e lido em nenhum ponto** do repositorio (`app/`, `engines/`, `config/`); hoje e apenas um marcador comercial exibido no detalhe. Confirmar se existe consumidor externo (BI de terceiro lendo o banco) antes de porta-la; se nao houver, e candidata a remocao.

### Requirement: BE-095 — Identificadores e cor gerados do projeto
O sistema DEVE (SHALL) gerar um identificador amigavel unico a partir do nome do projeto, uma chave de integracao e uma cor de exibicao. Fonte legada: `app/models/project.rb:62,64-67,91-93,749-764`.

#### Scenario: Nomes que geram o mesmo identificador
- **GIVEN** um projeto chamado `Obra Central` ja existente
- **WHEN** outro projeto `Obra Central!` e criado
- **THEN** o segundo recebe um identificador amigavel diferente e unico

#### Scenario: Renomear o projeto
- **GIVEN** um projeto ja em uso, referenciado por seu identificador amigavel
- **WHEN** o nome do projeto e alterado
- **THEN** o comportamento do identificador amigavel segue a regra definida e nenhuma referencia existente fica invalida sem aviso

> AMBIGUIDADE: no legado `set_smart_id` rodava em **todo** `before_validation`, inclusive no update — renomear o projeto mudava o identificador amigavel (e as URLs baseadas nele). Confirmar se o identificador deve ser imutavel apos a criacao.

### Requirement: BE-096 — Validacoes e logo do projeto
O sistema DEVE (SHALL) exigir nome unico, dono, identificador amigavel e situacao do projeto, e DEVE (SHALL) aceitar um logo de imagem dentro do limite de tamanho, devolvendo os erros identificados em pt-BR. Fonte legada: `app/models/project.rb:48-58,126-131`; `app/controllers/pub/projects_controller.rb:201-225`.

#### Scenario: Nome duplicado
- **GIVEN** um projeto chamado `Obra Central`
- **WHEN** outro projeto com o mesmo nome e criado
- **THEN** a criacao e rejeitada com 422 e a mensagem nomeia o campo em pt-BR

> Nota: corrige o legado, onde `translate_every_key` existia mas **nunca era chamado** no `ProjectsController` — os erros chegavam com a chave tecnica.

#### Scenario: Logo acima do limite
- **GIVEN** um arquivo de imagem maior que o limite aceito
- **WHEN** o usuario o envia como logo do projeto
- **THEN** a resposta e 422 informando o limite

### Requirement: BE-097 — Observacao de disponibilidade do projeto
O sistema DEVE (SHALL) permitir registrar um texto formatado de observacao sobre a disponibilidade do projeto, exibido no detalhe. Fonte legada: `app/models/project.rb:60`; `app/views/.../projects/new/_body.html.erb:127`.

#### Scenario: Conteudo com marcacao nao confiavel
- **GIVEN** um texto de observacao contendo marcacao arbitraria ou anexos
- **WHEN** ele e salvo e depois exibido
- **THEN** apenas a marcacao permitida e preservada e nenhum conteudo executavel e renderizado

> Nota: corrige o legado, onde anexos eram bloqueados apenas no cliente (`trix-file-accept` com `preventDefault` e botao escondido) e nao no servidor.

### Requirement: BE-098 — Projeto corrente do usuario
O sistema DEVE (SHALL) resolver o projeto corrente a partir da sessao autenticada, validando que o usuario e membro do projeto, e DEVE (SHALL) permitir troca-lo apenas entre os projetos dos quais ele e membro. Fonte legada: `config/routes.rb:54`; `app/controllers/pub/console_controller.rb:277-281`, `:285-312`; `app/decorators/models/user_decorator.rb:43-46`.

#### Scenario: Tentativa de assumir projeto sem membership
- **GIVEN** um usuario que nao e membro do projeto X
- **WHEN** ele tenta definir o projeto X como corrente
- **THEN** a operacao e recusada e o projeto corrente permanece inalterado

> Nota: corrige D-28 (legado: o projeto corrente vinha do cookie `cached_info` do cliente e o servidor validava apenas que o projeto **existe** (`Project.exists?`), nao que o usuario tem membership — trocar o cookie trocava de tenant). DEC-07: no ai9 o projeto corrente vem do JWT validado contra membership a cada request.

#### Scenario: Usuario sem projeto corrente definido
- **GIVEN** um usuario que e membro de pelo menos um projeto e nao tem projeto corrente
- **WHEN** ele acessa o console
- **THEN** um dos projetos dos quais e membro passa a ser o corrente, de forma deterministica

### Requirement: BE-099 — Membros do projeto
O sistema DEVE (SHALL) permitir buscar usuarios para adicionar ao projeto, adicionar e remover membros, com papel padrao de participante e vinculo unico por usuario e projeto. Fonte legada: `config/routes.rb:50-51`; `app/controllers/pub/memberships_controller.rb:13-59`; `app/models/membership.rb:31`.

#### Scenario: Busca de membros sem termo
- **GIVEN** a tela de membros de um projeto
- **WHEN** a busca e feita com termo vazio
- **THEN** a resposta e uma lista valida (possivelmente vazia), sem erro

> Nota: corrige o legado, onde com `query` em branco `@memberships` ficava `nil` e a view estourava.

#### Scenario: Remocao de vinculo inexistente
- **GIVEN** um pedido de remocao de um vinculo que ja nao existe
- **WHEN** ele e processado
- **THEN** a resposta e 404, e nao um erro interno

#### Scenario: Vinculo duplicado
- **GIVEN** um usuario ja membro do projeto
- **WHEN** ele e adicionado novamente
- **THEN** nenhum vinculo duplicado e criado

### Requirement: BE-100 — Projetos de um usuario
O sistema DEVE (SHALL) informar, para um usuario, quais projetos ele participa, dentro do que o solicitante tem permissao de ver. Fonte legada: `config/routes.rb:15`; `app/controllers/pub/users_controller.rb:58-66`.

#### Scenario: Listagem de projetos de um usuario
- **GIVEN** um usuario que participa de 3 projetos
- **WHEN** um administrador consulta os projetos desse usuario
- **THEN** a resposta indica claramente de quais projetos ele participa

> AMBIGUIDADE: no legado a action listava **todos** os projetos (`Project.all`) marcando os que o usuario participa, e a interface mostrava o controle como somente leitura. Confirmar se essa aba deve permitir vincular/desvincular ou permanecer informativa.

### Requirement: BE-101 — Rotas mortas do dominio de projetos
Os endpoints do dominio de projetos DEVEM (SHALL) responder de fato ou nao existir; nenhum caminho DEVE (SHALL) resultar em erro por template ausente. Fonte legada: `app/controllers/pub/projects_controller.rb:6-12`; `project_guarantees_controller.rb:6-12`; `project_availabilities_controller.rb:6-8`; `project_to_carrier_connections_controller.rb:7-9`; `project_indicator_connections_controller.rb:7-9`; `config/routes.rb:75`.

#### Scenario: Endpoint de detalhe de projeto
- **GIVEN** um projeto do qual o usuario e membro
- **WHEN** o cliente pede o detalhe do projeto
- **THEN** a resposta traz os dados do projeto, com status 200

> AMBIGUIDADE: no legado nenhum dos templates `index`/`detail/body` existia (so parciais `_body`), a rota `config/routes.rb:75` apontava para um controller inexistente (`project_to_availability_connections`) e as views `projects/detail/connection_template/**` chamavam helpers e metodos inexistentes. Confirmar que nada externo consome essas rotas antes de descarta-las (DEC-09: o que e comprovadamente morto vai para `dropped` com evidencia).

### Requirement: BE-102 — Listar conexoes projeto-portador
O sistema DEVE (SHALL) listar os portadores conectaveis a um projeto (e, no sentido inverso, os projetos conectaveis a um portador), indicando quais ja estao conectados, com busca e paginacao. Fonte legada: `config/routes.rb:86-90`; `app/controllers/pub/project_to_carrier_connections_controller.rb:42-64`.

#### Scenario: Tipo de entidade fora do conjunto permitido
- **GIVEN** um cliente que informa um tipo de entidade arbitrario nos parametros
- **WHEN** a requisicao e processada
- **THEN** a resposta e 400 e nenhuma classe fora do conjunto permitido e resolvida

> Nota: corrige a falha de seguranca do legado — `owner_type` e `connection_type` eram `constantize` de parametro do usuario, permitindo enumeracao de classes e execucao de codigo indireta.

#### Scenario: Marcacao de conectados sem consulta por linha
- **GIVEN** um projeto com 200 portadores candidatos
- **WHEN** a lista e carregada
- **THEN** o estado de conectado de cada item vem resolvido em consulta unica, dentro do limite de performance definido

> Nota: corrige o N+1 do legado (`o.carriers.include?(t)` por linha).

### Requirement: BE-103 — Conectar e desconectar portadores do projeto
O sistema DEVE (SHALL) conectar e desconectar portadores de um projeto em lote, garantindo unicidade da conexao e reportando o resultado de cada item. Fonte legada: `config/routes.rb:89`; `app/controllers/pub/project_to_carrier_connections_controller.rb:66-102`; `app/models/project_to_carrier_connection.rb`.

#### Scenario: Lote vazio
- **GIVEN** uma requisicao de conexao sem nenhum portador informado
- **WHEN** ela e processada
- **THEN** a resposta e 400, e nao um erro interno

> Nota: corrige o legado, onde `connector_id` vazio deixava `@connection` como `nil` e resultava em 500.

#### Scenario: Lote parcialmente invalido
- **GIVEN** um lote com 3 portadores, dos quais 1 ja esta conectado
- **WHEN** a conexao e submetida
- **THEN** a resposta informa o resultado de cada item e o estado final de cada conexao e correto

> Nota: corrige os erros engolidos do legado — a condicao `@connection.errors.add(...) unless @connection.errors.blank?` (`:93`) estava invertida e apenas o ultimo item era avaliado.

#### Scenario: Desconectar item que ja nao esta conectado
- **GIVEN** um portador que nao esta conectado ao projeto
- **WHEN** a desconexao e solicitada
- **THEN** a resposta indica que nada havia a desconectar, sem erro interno

> Nota: corrige o legado, onde `@connections.select{...}.first` podia ser `nil` e gerava 500.

### Requirement: BE-104 — Busca de candidatos a conexao de portador
O sistema DEVE (SHALL) oferecer a busca de portadores candidatos a conexao por um unico endpoint, com limite configuravel. Fonte legada: `app/controllers/pub/project_to_carrier_connections_controller.rb:19-40`.

#### Scenario: Busca de candidatos
- **GIVEN** um projeto e um termo de busca
- **WHEN** os candidatos sao consultados
- **THEN** a lista de portadores que casam com o termo e devolvida, com o estado de conexao de cada um

> Nota: no legado havia dois endpoints praticamente identicos (este e BE-102), diferindo apenas no nome do parametro de dono e no limite padrao — consolidados em um so no ai9.

### Requirement: BE-105 — Remover uma conexao de portador isolada
O sistema DEVE (SHALL) permitir remover uma conexao projeto-portador especifica. Fonte legada: `app/controllers/pub/project_to_carrier_connections_controller.rb:144-161`.

#### Scenario: Remocao de conexao por identificador
- **GIVEN** uma conexao existente entre um projeto e um portador
- **WHEN** o cliente solicita a remocao dessa conexao
- **THEN** a conexao e removida e a resposta e 200

> Nota: corrige a action morta do legado — `@connection` nunca era atribuido pelo `before_action` (que preenchia `@connections`, no plural), resultando em `NoMethodError`; a interface usava o endpoint em lote.

### Requirement: BE-106 — Listar conexoes projeto-indicador
O sistema DEVE (SHALL) listar os indicadores conectaveis a um projeto, indicando quais ja estao conectados, com busca e paginacao. Fonte legada: `config/routes.rb:92-96`; `app/controllers/pub/project_indicator_connections_controller.rb:42-64`.

#### Scenario: Tipo de entidade fora do conjunto permitido
- **GIVEN** um cliente que informa um tipo de entidade arbitrario nos parametros
- **WHEN** a requisicao e processada
- **THEN** a resposta e 400 e nenhuma classe fora do conjunto permitido e resolvida

> Nota: corrige a mesma falha de `constantize` de parametro do usuario descrita em BE-102.

### Requirement: BE-107 — Indicadores candidatos: globais e do projeto
O sistema DEVE (SHALL) oferecer, como candidatos a conexao, os indicadores globais e os especificos do projeto corrente. Fonte legada: `app/controllers/pub/project_indicator_connections_controller.rb:19-40`, `:30`.

#### Scenario: Escopo dos candidatos
- **GIVEN** indicadores globais e indicadores especificos de dois projetos distintos
- **WHEN** os candidatos do projeto A sao consultados
- **THEN** aparecem os globais e os especificos do projeto A, e nenhum especifico do projeto B

### Requirement: BE-108 — Conectar e desconectar indicadores do projeto
O sistema DEVE (SHALL) conectar e desconectar indicadores de um projeto em lote, garantindo unicidade da conexao e reportando o resultado de cada item. Fonte legada: `config/routes.rb:95`; `app/controllers/pub/project_indicator_connections_controller.rb:67-116`; `app/models/project_indicator_connection.rb`.

#### Scenario: Lote vazio ou item ja no estado pedido
- **GIVEN** uma requisicao de conexao sem itens, ou com um indicador ja conectado
- **WHEN** ela e processada
- **THEN** a resposta descreve o resultado por item, sem erro interno e sem duplicar conexoes

> Nota: corrige os mesmos quatro defeitos descritos em BE-103, repetidos neste controller.

### Requirement: BE-109 — Excluir indicador especifico do projeto
O sistema DEVE (SHALL) permitir excluir um indicador especifico do projeto, removendo antes a conexao, e DEVE (SHALL) recusar a exclusao de indicadores globais. Fonte legada: `app/controllers/pub/project_indicator_connections_controller.rb:94-105`.

#### Scenario: Tentativa de excluir indicador global
- **GIVEN** um indicador global conectado ao projeto
- **WHEN** o usuario tenta exclui-lo
- **THEN** a resposta e 422 informando que indicadores globais nao podem ser removidos, sem erro interno

> Nota: corrige o legado, onde nesse ramo `@connection` podia ser `nil` e gerava 500.

#### Scenario: Exclusao de indicador especifico
- **GIVEN** um indicador criado especificamente para o projeto
- **WHEN** o usuario o exclui
- **THEN** a conexao e o indicador sao removidos

### Requirement: BE-110 — Listar padroes de disponibilidade do projeto
O sistema DEVE (SHALL) devolver a arvore de padroes de disponibilidade do projeto corrente, ordenada por posicao hierarquica. Fonte legada: `config/routes.rb:76`; `app/controllers/pub/project_availabilities_controller.rb:10-14`; `app/models/project_availability_template.rb:200-226`.

#### Scenario: Usuario sem projeto corrente
- **GIVEN** um usuario autenticado sem projeto corrente resolvido
- **WHEN** ele pede a arvore de padroes
- **THEN** a resposta e um erro de pre-condicao explicito, e nao um erro interno

> Nota: corrige o legado, onde a action usava **sempre** `current_user.default_project` e levantava `NoMethodError` sem projeto padrao.

#### Scenario: Ordenacao da arvore em base grande
- **GIVEN** um projeto com centenas de padroes em tres niveis
- **WHEN** a arvore e carregada
- **THEN** ela vem ordenada por posicao hierarquica dentro do limite de performance definido

> Nota: corrige o `1+N` por nivel do legado (`all_ids_by_position`) e a ordenacao final via `join (VALUES ...)` dependente de sintaxe especifica do Postgres.

### Requirement: BE-111 — Formulario de padrao de disponibilidade
O sistema DEVE (SHALL) fornecer os dados do formulario de criacao e edicao de padrao de disponibilidade, incluindo os possiveis padroes-pai. Fonte legada: `app/controllers/pub/project_availabilities_controller.rb:16-34`, `:228-240`.

#### Scenario: Opcoes de padrao-pai
- **GIVEN** um projeto com padroes em tres niveis
- **WHEN** o formulario e aberto
- **THEN** as opcoes de "faz parte de" contem apenas padroes que podem receber um filho no nivel pretendido

### Requirement: BE-112 — Criar e editar padrao de disponibilidade
O sistema DEVE (SHALL) criar e editar padroes de disponibilidade com titulo, tipo de operacao, tipo de prazo, acumulavel, corrigido e padrao-pai, mantendo a hierarquia de ate tres niveis coerente. Fonte legada: `app/controllers/pub/project_availabilities_controller.rb:36-63`, `:142-156`; `app/models/project_availability_template.rb:28-61`; `app/models/availability_template.rb:2-8`.

#### Scenario: Hierarquia limitada a tres niveis
- **GIVEN** um padrao ja no terceiro nivel
- **WHEN** o usuario tenta criar um filho dele
- **THEN** a criacao e rejeitada com 422 informando o limite de niveis

#### Scenario: Titulo repetido no mesmo nivel
- **GIVEN** um padrao chamado `Receitas` no primeiro nivel do projeto
- **WHEN** outro padrao com o mesmo titulo e criado no mesmo nivel e projeto
- **THEN** a criacao e rejeitada com 422

#### Scenario: Padrao obrigatorio exige cadeia obrigatoria
- **GIVEN** um padrao-pai que nao e obrigatorio
- **WHEN** o usuario tenta criar sob ele um padrao obrigatorio
- **THEN** a criacao e rejeitada informando que a cadeia superior precisa ser obrigatoria

#### Scenario: Nivel numerico derivado do pai
- **GIVEN** um padrao-pai de primeiro nivel numero 2
- **WHEN** um filho e criado
- **THEN** o nivel numerico do filho e derivado do pai de forma deterministica

> Nota: corrige o legado, que usava ` |= ` (ou bit-a-bit) para atribuir `numeric_first_level` (`:41-51`) — funcionava por acidente quando o valor era `0`/`nil`. Corrige tambem o `destroy` do registro nao persistido no caminho de erro (`:44`).

### Requirement: BE-113 — Ativar padrao de disponibilidade
O sistema DEVE (SHALL) ativar um padrao de disponibilidade em segundo plano, bloqueando o padrao e seus filhos durante o processamento, recalculando os lancamentos afetados e liberando o bloqueio ao final — inclusive em caso de falha. Fonte legada: `config/routes.rb:78`; `app/controllers/pub/project_availabilities_controller.rb:65-82`; `app/models/project_availability_template.rb:697-742`.

#### Scenario: Falha no processamento libera o bloqueio
- **GIVEN** um padrao cuja ativacao falha no processamento em segundo plano
- **WHEN** a falha ocorre
- **THEN** a tarefa e reexecutada conforme a politica de retentativa, o bloqueio e liberado ao final e a falha fica visivel para o usuario

> Nota: corrige D-05 (legado: os cinco jobs de template engoliam a excecao no `rescue`, `destroy_failed_jobs?` era `false`, nao havia retry, e so o caminho feliz chamava `unlocked!` — o template ficava **travado para sempre**). No ai9: Sidekiq com retry, liberacao do bloqueio em `ensure` e falha visivel.

#### Scenario: Enfileiramento recusado
- **GIVEN** um padrao ja bloqueado por outra operacao em andamento
- **WHEN** o usuario aciona a ativacao
- **THEN** a resposta e 409 informando que ha operacao em andamento

> Nota: corrige o legado, que respondia sempre `:ok` mesmo com erro (`:79`).

### Requirement: BE-114 — Desativar padrao de disponibilidade
O sistema DEVE (SHALL) desativar um padrao de disponibilidade em segundo plano, aplicando no servico as regras de negocio que impedem desativar padrao obrigatorio ou padrao com dependentes obrigatorios, e recalculando os somatorios afetados. Fonte legada: `config/routes.rb:79`; `app/controllers/pub/project_availabilities_controller.rb:84-101`; `app/models/project_availability_template.rb:139-172`, `:744-800`.

#### Scenario: Padrao obrigatorio nao pode ser desativado
- **GIVEN** um padrao marcado como obrigatorio
- **WHEN** o usuario aciona a desativacao
- **THEN** a operacao e recusada com a mensagem de que nao e possivel desativar um padrao obrigatorio, e nenhum recalculo ocorre

> Nota: corrige D-04/D-33 (legado: a guarda vivia em `project_availability_template.rb:141-169` — e ainda filtrava por `project_id: self.id`, o que e bug — mas a rota `deactivate` enfileirava um job que chamava `background_deactivate` (`:744`), o qual so fazia `is_active = 0`. A regra **nunca rodava no fluxo real**). No ai9 a regra e aplicada no servico, antes de enfileirar.

#### Scenario: Padrao com dependentes obrigatorios
- **GIVEN** um padrao que possui filhos obrigatorios
- **WHEN** o usuario aciona a desativacao
- **THEN** a operacao e recusada informando que existem dependentes obrigatorios

#### Scenario: Desativacao valida
- **GIVEN** um padrao nao obrigatorio e sem dependentes obrigatorios
- **WHEN** a desativacao e processada
- **THEN** o padrao fica inativo, os somatorios dos padroes superiores sao recalculados nas datas com lancamento e o bloqueio e liberado

### Requirement: BE-115 — Remover padrao de disponibilidade
O sistema DEVE (SHALL) remover um padrao de disponibilidade e seus filhos em segundo plano, e DEVE (SHALL) tratar de forma explicita o caso em que existem lancamentos vinculados. Fonte legada: `app/controllers/pub/project_availabilities_controller.rb:103-120`; `app/models/project_availability_template.rb:598-695`.

#### Scenario: Padrao com lancamentos vinculados
- **GIVEN** um padrao que possui lancamentos de disponibilidade
- **WHEN** o usuario aciona a remocao
- **THEN** o sistema informa explicitamente que ha lancamentos e a operacao segue a regra definida, sem apagar dado financeiro silenciosamente

> Nota: corrige a divergencia do legado — `is_deletable?` (`:598-600`, verdadeiro so sem lancamentos) era usado apenas como dica na interface, enquanto `background_removal` removia recursivamente filhos **e suas entradas** (`entries.destroy_all`) mesmo com lancamentos.

#### Scenario: Falha na remocao libera o bloqueio
- **GIVEN** uma remocao que falha no processamento em segundo plano
- **WHEN** a falha ocorre
- **THEN** a tarefa e reexecutada conforme a politica de retentativa, o bloqueio e liberado e a falha fica visivel

> Nota: corrige D-05.

### Requirement: BE-116 — Reordenacao e recalculo em cascata dos padroes
O sistema DEVE (SHALL) manter a ordenacao hierarquica dos padroes de disponibilidade do projeto consistente apos criacao, ativacao, desativacao, remocao e mudanca de posicao. Fonte legada: `app/models/project.rb:236-296`; `app/models/project_availability_template.rb:294-592`.

#### Scenario: Reordenacao em projeto grande
- **GIVEN** um projeto com milhares de padroes em tres niveis
- **WHEN** um padrao e removido e a arvore e reordenada
- **THEN** as posicoes ficam consistentes e a operacao termina dentro do limite de performance definido

> Nota: corrige o custo quadratico do legado — `reorder_project_availability_templates!` chamava os tres `import` **dentro** do loop de primeiro nivel, reimportando o acumulado a cada iteracao.

#### Scenario: Mover um padrao de posicao
- **GIVEN** dois padroes irmaos no mesmo nivel
- **WHEN** o usuario troca a posicao entre eles
- **THEN** a nova ordem e persistida e refletida na arvore

> AMBIGUIDADE: no legado `set_new_position!` so permitia mover dentro do mesmo nivel/familia e **nao tinha rota HTTP** — nao foi possivel identificar de onde e chamado. Confirmar se a reordenacao manual e um caso de uso real no ai9.

### Requirement: BE-117 — API de disponibilidades por projeto
O sistema DEVE (SHALL) expor os totais de disponibilidade de um projeto por periodo e por empresa, exigindo autenticacao e escopo de tenant. Fonte legada: `config/routes.rb:235-240`; `app/controllers/api/v1/project_availability_controller.rb:6-26`; `app/models/project.rb:393-422`.

#### Scenario: Requisicao sem autenticacao
- **GIVEN** um cliente sem credencial valida
- **WHEN** ele consulta as disponibilidades de um projeto por id
- **THEN** a resposta e 401 e nenhum valor financeiro e devolvido

> Nota: corrige D-01 (legado: `Api::V1::ProjectAvailabilityController` herdava de `ApplicationController`, que estava **vazio**, e fazia `Project.find(params[:id])` sem escopo — qualquer requisicao lia os valores financeiros de qualquer projeto por id). Nao se replica um IDOR.

#### Scenario: Projeto fora do escopo do solicitante
- **GIVEN** um cliente autenticado que nao e membro do projeto X
- **WHEN** ele consulta as disponibilidades do projeto X
- **THEN** a resposta e 403 ou 404, sem devolver dados

#### Scenario: Empresa inexistente no filtro
- **GIVEN** uma consulta com um identificador de empresa que nao existe no projeto
- **WHEN** ela e processada
- **THEN** a resposta e 422 informando o filtro invalido

> Nota: corrige o legado, onde `company_id` invalido resultava em `@company = nil` e a consulta passava a filtrar `company_id IS NULL`, devolvendo numeros errados sem aviso.

### Requirement: BE-118 — Buscar, filtrar e ordenar garantias do projeto
O sistema DEVE (SHALL) listar as garantias do projeto corrente com busca por titulo da garantia ou do portador, filtros por portador e por tipo de garantia, ordenacao por qualquer coluna apresentada e paginacao efetiva. Fonte legada: `config/routes.rb:215`; `app/controllers/pub/project_guarantees_controller.rb:14-44`, `:105-113`; `app/models/project_guarantee.rb:17-52`.

#### Scenario: Ordenar por titulo
- **GIVEN** uma lista de garantias do projeto corrente
- **WHEN** o usuario ordena pela coluna "Titulo"
- **THEN** a lista volta ordenada por titulo da garantia, com status 200

> Nota: corrige D-32 (legado: a ordenacao por `title` mapeava para `risk_operations.title` (`app/models/project_guarantee.rb:33`), tabela **fora do join** — erro SQL ao ordenar por titulo).

#### Scenario: Garantia de outro projeto nao e alcancavel por id
- **GIVEN** uma garantia que pertence a um projeto do qual o usuario nao e membro
- **WHEN** ele lista garantias informando o id dessa garantia
- **THEN** o resultado e vazio e nenhum dado da garantia alheia e devolvido

> Nota: corrige D-29 (legado: `project_guarantee_id` **sobrepunha** o escopo de projeto em `project_guarantees_controller.rb:22`).

#### Scenario: Paginacao aplicada sem ordenacao explicita
- **GIVEN** 300 garantias no projeto corrente
- **WHEN** o cliente pede `l=50`, `o=100` sem informar ordenacao
- **THEN** sao devolvidas 50 garantias a partir da 101a e o total informado e 300

> Nota: corrige D-20 (legado: sem `ordering_keys` nenhum `limit`/`offset` era aplicado, e o limite padrao era 1000).

### Requirement: BE-119 — CRUD de garantias do projeto
O sistema DEVE (SHALL) criar, editar e remover garantias do projeto corrente com titulo, portador, tipo de garantia, valor e observacao, oferecendo apenas portadores conectados ao projeto. Fonte legada: `config/routes.rb:216`; `app/controllers/pub/project_guarantees_controller.rb:46-101`, `:128-139`; `app/models/project_guarantee.rb:1-13`.

#### Scenario: Campos obrigatorios
- **GIVEN** o formulario de nova garantia
- **WHEN** o usuario salva sem informar portador
- **THEN** a resposta e 422 identificando o campo faltante

#### Scenario: Abrir a edicao de uma garantia
- **GIVEN** uma garantia existente do projeto corrente
- **WHEN** o cliente pede os dados para edicao
- **THEN** a resposta traz os dados da garantia e as opcoes de portador e de tipo de garantia

> Nota: corrige o legado, onde a action `edit` fazia `@operation_types = @companies.first.id` com `@companies` nunca definido, resultando em `NoMethodError` — a interface contornava usando a rota do console.

#### Scenario: Remocao bloqueada e comunicada
- **GIVEN** uma garantia que nao pode ser removida por regra de negocio
- **WHEN** o usuario solicita a remocao
- **THEN** a resposta e 422 informando o motivo

> Nota: corrige D-24 (legado: `destroy` respondia `:ok` mesmo com erro).

### Requirement: FE-080 — Tela "Projetos"
A tela de projetos DEVE (SHALL) listar os projetos com nome, chave de integracao, indicador de atualizacao em andamento e menu de acoes, com recarga manual e estados de carregamento, vazio e falha. Fonte legada: `app/views/pub/console/parts/projects/_body.html.erb:1-36`; `_body.js.erb:76-101`.

#### Scenario: Falha ao carregar a lista
- **GIVEN** uma falha ao consultar os projetos
- **WHEN** o erro ocorre
- **THEN** a tela apresenta o estado de falha com opcao de tentar novamente

> Nota: corrige o legado, onde o erro era silencioso.

### Requirement: FE-081 — Busca incremental de projetos
O campo de busca DEVE (SHALL) aguardar a pausa de digitacao antes de consultar e ignorar entradas compostas apenas de espacos. Fonte legada: `app/views/.../projects/_body.js.erb:15-28`.

#### Scenario: Busca sem resultados
- **GIVEN** um termo que nao casa com nenhum projeto do usuario
- **WHEN** a busca retorna
- **THEN** a tela mostra a mensagem de vazio citando o termo buscado

### Requirement: FE-082 — Card de projeto e menu de contexto
Cada projeto na lista DEVE (SHALL) oferecer acesso ao detalhe, a tela de portadores, a edicao e a remocao, conforme papel e condicao de somente-leitura. Fonte legada: `app/views/.../projects/list/_widget.html.erb:1-57`; `list/_widget.js.erb:1-198`.

#### Scenario: Usuario sem papel administrativo
- **GIVEN** um usuario que nao e `og`, `admin` nem `manager`
- **WHEN** ele abre o menu de contexto de um projeto
- **THEN** as acoes de editar e remover nao sao oferecidas

### Requirement: FE-083 — Indicador de atualizacao em andamento
O card do projeto DEVE (SHALL) indicar quando ha uma atualizacao em andamento e apresentar o percentual de progresso, atualizado sem intervencao do usuario. Fonte legada: `app/views/.../projects/list/_widget.html.erb:10-22`; `list/_widget.js.erb:24-39`; `app/models/project.rb:672-684`.

#### Scenario: Progresso avanca sozinho
- **GIVEN** um projeto com uma tarefa em segundo plano em andamento
- **WHEN** a tarefa progride
- **THEN** o percentual exibido avanca sem que o usuario precise recarregar a tela

> Nota: corrige D-86 (legado: nao havia polling nem push — o percentual so mudava ao recarregar a lista manualmente). No ai9 a atualizacao chega por Action Cable.

### Requirement: FE-084 — Remocao de projeto pela lista
A remocao pela lista DEVE (SHALL) pedir confirmacao e refletir o resultado real da operacao. Fonte legada: `app/views/.../projects/list/_widget.js.erb:170-196`.

#### Scenario: Remocao bloqueada
- **GIVEN** um projeto com dados dependentes
- **WHEN** o usuario confirma a remocao
- **THEN** a tela mostra o erro devolvido pelo servidor e o projeto permanece na lista

> Nota: corrige D-24 (legado: o tratamento de erro estava comentado (`:192`) e, em "sucesso", a tela recarregava para a lista — como o backend respondia 200 mesmo falhando (BE-091), a remocao sempre parecia ter dado certo).

### Requirement: FE-085 — Formulario de projeto (campos)
O formulario DEVE (SHALL) oferecer nome, chave de integracao, situacao, segmento, subsegmento, endereco completo, observacao de disponibilidade, responsavel, data de baixa e logo. Fonte legada: `app/views/.../projects/new/_body.html.erb:1-213`.

#### Scenario: Edicao mostra o projeto correto
- **GIVEN** um projeto existente
- **WHEN** o usuario abre a edicao
- **THEN** o titulo da tela identifica o projeto e os campos vem preenchidos com os valores atuais

### Requirement: FE-086 — Seletor de responsavel no formulario
O formulario DEVE (SHALL) permitir escolher entre criar um novo usuario responsavel, indicar um usuario existente ou nao definir responsavel, alternando os campos conforme a escolha. Fonte legada: `app/views/.../projects/new/_body.html.erb:132-178`; `new/_body.js.erb:18-103`.

#### Scenario: Sem usuarios disponiveis
- **GIVEN** um solicitante para o qual nenhum usuario esta disponivel como responsavel
- **WHEN** ele abre o seletor
- **THEN** a opcao de escolher usuario existente nao e oferecida

#### Scenario: Sem responsavel
- **GIVEN** a opcao "sem responsavel" escolhida
- **WHEN** o formulario e submetido
- **THEN** os campos de responsavel sao ignorados e o projeto e criado sem responsavel

### Requirement: FE-087 — Upload e preview do logo do projeto
O formulario DEVE (SHALL) mostrar o preview do logo escolhido e preservar a escolha do usuario quando outros campos falharem na validacao. Fonte legada: `app/views/.../projects/new/_body.html.erb:194-207`; `new/_body.js.erb:106-131`, `:13-16`.

#### Scenario: Erro de validacao em outro campo
- **GIVEN** um logo ja escolhido e o campo de nome vazio
- **WHEN** o usuario salva e recebe o erro de nome
- **THEN** o logo escolhido continua selecionado

> Nota: corrige o legado, onde qualquer `ajax:error` resetava o input de arquivo e o usuario perdia o anexo escolhido.

### Requirement: FE-088 — Campo de data de baixa
O formulario DEVE (SHALL) oferecer selecao de data de baixa em formato pt-BR. Fonte legada: `app/views/.../projects/new/_body.html.erb:181-192`; `new/_body.js.erb:134-145`.

#### Scenario: Escolher a data de baixa
- **GIVEN** o formulario de projeto
- **WHEN** o usuario escolhe uma data no seletor
- **THEN** a data e exibida no formato `dd/mm/aaaa` e enviada corretamente ao servidor

### Requirement: FE-089 — Salvamento do formulario de projeto
O formulario DEVE (SHALL) deixar claro quando as alteracoes sao salvas e nao DEVE (SHALL NOT) enviar uma requisicao a cada tecla digitada. Fonte legada: `app/views/.../projects/new/_body.js.erb:152-179`.

#### Scenario: Edicao de varios campos
- **GIVEN** o formulario de projeto aberto
- **WHEN** o usuario preenche cinco campos e salva
- **THEN** uma unica requisicao de salvamento e enviada e a tela informa o resultado sem sair abruptamente da pagina

> AMBIGUIDADE: no legado qualquer `keyup`/`change` registrava a acao de salvar na fila do rodape, e o sucesso redirecionava para a lista de projetos. Confirmar se o autosave e comportamento desejado pelo negocio ou efeito colateral indesejado.

### Requirement: FE-090 — Retorno de erro e sucesso do formulario de projeto
As mensagens de resultado DEVEM (SHALL) identificar os campos em pt-BR e distinguir cadastro de edicao. Fonte legada: `app/views/.../projects/new/handle.js.erb:1-12`.

#### Scenario: Salvar uma edicao
- **GIVEN** um projeto existente sendo editado
- **WHEN** o salvamento tem sucesso
- **THEN** a mensagem informa que o projeto foi **atualizado**

> Nota: corrige o legado, que usava o mesmo template no create e no update e dizia "cadastrado com sucesso" mesmo ao editar, e exibia a chave tecnica em negrito nos erros.

### Requirement: FE-091 — Detalhe do projeto (dados)
O detalhe DEVE (SHALL) apresentar responsavel, endereco formatado, segmento, subsegmento e data de criacao, alem de sinalizar quando ha atualizacao em andamento. Fonte legada: `app/views/.../projects/detail/_body.html.erb:1-24`; `detail/tabs/_tab_geral.html.erb:4-70`; `app/models/project.rb:149-184`.

#### Scenario: Projeto sem responsavel
- **GIVEN** um projeto criado sem responsavel
- **WHEN** o detalhe e aberto
- **THEN** o campo de responsavel indica a ausencia de forma explicita

#### Scenario: Data de criacao formatada
- **GIVEN** um projeto criado
- **WHEN** o detalhe e aberto
- **THEN** a data de criacao e apresentada corretamente formatada

> Nota: corrige o formato quebrado do legado (`dd/mm/aaaa- HH:MM`, com o hifen colado e sem espaco).

### Requirement: FE-092 — Alternar "Gerido pela Safegold" no detalhe
O detalhe DEVE (SHALL) permitir alternar a marca de gestao Safegold, com confirmacao visual do novo estado e bloqueio para usuario somente-leitura. Fonte legada: `app/views/.../projects/detail/tabs/_tab_geral.js.erb:93-157`.

#### Scenario: Usuario somente-leitura
- **GIVEN** um usuario somente-leitura
- **WHEN** ele tenta alternar a marca
- **THEN** a alteracao e recusada e a tela informa a falta de permissao

### Requirement: FE-093 — Alternar "Possui BI contratado" no detalhe
O detalhe DEVE (SHALL) permitir alternar a marca de BI contratado, com confirmacao visual do novo estado e bloqueio para usuario somente-leitura. Fonte legada: `app/views/.../projects/detail/tabs/_tab_geral.html.erb:24-37`; `_tab_geral.js.erb:160-229`.

#### Scenario: Alternar a marca correta
- **GIVEN** o detalhe do projeto com os dois interruptores (gestao Safegold e BI)
- **WHEN** o usuario clica no rotulo do interruptor de BI
- **THEN** apenas a marca de BI e alterada

> Nota: corrige o legado, onde os dois interruptores usavam o mesmo identificador HTML (`id="is_active_{project.id}"`) e o rotulo era ambiguo.

### Requirement: FE-094 — Acoes rapidas do detalhe do projeto
O detalhe DEVE (SHALL) oferecer atalhos para portadores, edicao e remocao (ou limpeza, em projeto de treinamento), visiveis apenas para papeis autorizados. Fonte legada: `app/views/.../projects/detail/tabs/_tab_geral.html.erb:112-148`; `_tab_geral.js.erb:8-91`.

#### Scenario: Projeto de treinamento
- **GIVEN** um projeto marcado como treinamento
- **WHEN** o usuario autorizado abre as acoes rapidas
- **THEN** a acao oferecida e "limpar projeto", nao "remover projeto"

### Requirement: FE-095 — Lista de membros no detalhe do projeto
O detalhe DEVE (SHALL) listar os membros com avatar (ou iniciais), nome e papel, sem oferecer remocao do dono do projeto nem do proprio usuario logado. Fonte legada: `app/views/.../projects/detail/tabs/_tab_geral.html.erb:72-109`; `detail/memberships/list/_widget.html.erb:1-30`.

#### Scenario: Dono do projeto na lista
- **GIVEN** o dono do projeto na lista de membros
- **WHEN** o usuario visualiza a lista
- **THEN** a acao de remover nao e oferecida para o dono

### Requirement: FE-096 — Adicionar membro por autocomplete
O detalhe DEVE (SHALL) permitir adicionar membros por busca incremental de usuarios, restrita a quem tem permissao. Fonte legada: `app/views/.../projects/detail/tabs/_tab_geral.html.erb:75-89`; `_tab_geral.js.erb:234-366`.

#### Scenario: Busca sem resultados
- **GIVEN** um termo que nao casa com nenhum usuario
- **WHEN** a busca retorna
- **THEN** a tela informa que nao ha resultados

#### Scenario: Usuario sem permissao
- **GIVEN** um usuario somente-leitura ou sem permissao de alterar registros publicos
- **WHEN** ele abre o detalhe do projeto
- **THEN** o campo de adicionar membro nao e oferecido

### Requirement: FE-097 — Remover membro no detalhe do projeto
O detalhe DEVE (SHALL) permitir remover um membro com confirmacao e mensagens que se refiram ao projeto. Fonte legada: `app/views/.../projects/detail/memberships/list/_widget.js.erb:12-51`.

#### Scenario: Confirmacao de remocao
- **GIVEN** um membro do projeto
- **WHEN** o usuario confirma a remocao
- **THEN** o membro sai da lista e a mensagem informa que ele foi removido do **projeto**

> Nota: corrige o texto errado do legado, que dizia "O membro foi removido da empresa".

### Requirement: FE-098 — Cartao "Portadores" no detalhe do projeto
O detalhe DEVE (SHALL) listar os portadores conectados ao projeto, em ordem alfabetica, com o grupo de cada um, e indicar quando nao ha nenhum. Fonte legada: `app/views/.../projects/detail/tabs/_tab_geral.html.erb:149-176`.

#### Scenario: Projeto sem portadores
- **GIVEN** um projeto sem portadores conectados
- **WHEN** o detalhe e aberto
- **THEN** o cartao informa que o projeto ainda nao possui portadores

### Requirement: FE-099 — Cartao "Observacao - Disponibilidade"
O detalhe DEVE (SHALL) apresentar a observacao de disponibilidade formatada quando ela existir. Fonte legada: `app/views/.../projects/detail/tabs/_tab_geral.html.erb:178-189`.

#### Scenario: Projeto sem observacao
- **GIVEN** um projeto sem observacao de disponibilidade
- **WHEN** o detalhe e aberto
- **THEN** o cartao nao e apresentado

### Requirement: FE-100 — Tela de conexoes projeto-portador
A tela DEVE (SHALL) permitir buscar e conectar portadores a um projeto (e projetos a um portador, no sentido inverso), com titulo coerente com o sentido e caminho de volta para a origem. Fonte legada: `app/views/pub/console/parts/carrier_connections/_body.html.erb:1-23`; `_body.js.erb:1-109`.

#### Scenario: Voltar para a origem
- **GIVEN** a tela de conexoes aberta a partir do detalhe do projeto
- **WHEN** o usuario aciona "voltar"
- **THEN** ele retorna ao detalhe do projeto, e nao a uma tela arbitraria

### Requirement: FE-101 — Item de conexao de portador
Cada item DEVE (SHALL) permitir conectar e desconectar o portador, refletindo o estado real confirmado pelo servidor. Fonte legada: `app/views/.../carrier_connections/list/_widget.html.erb:1-16`; `list/_widget.js.erb:1-46`.

#### Scenario: Falha ao conectar
- **GIVEN** um item cuja conexao falha no servidor
- **WHEN** a resposta de erro chega
- **THEN** o item volta ao estado anterior e a falha e comunicada

> Nota: corrige o legado, onde o estado era otimista no cliente e nao havia recarregamento — em erro parcial a interface divergia do servidor.

### Requirement: FE-102 — Tela "Indicadores especificos"
A tela DEVE (SHALL) listar os indicadores do projeto corrente e permitir cadastrar novos, respeitando a condicao de somente-leitura. Fonte legada: `app/views/pub/console/parts/indicator_connections/_body.html.erb:1-28`.

#### Scenario: Usuario somente-leitura
- **GIVEN** um usuario somente-leitura
- **WHEN** ele abre a tela de indicadores especificos
- **THEN** o botao de cadastrar nao e oferecido

### Requirement: FE-103 — Item de indicador global x especifico
O item DEVE (SHALL) distinguir indicador global (conectar/desconectar) de indicador especifico do projeto (editar, ativar/desativar, excluir) e permitir expandir a descricao. Fonte legada: `app/views/.../indicator_connections/list/_widget.html.erb:1-58`.

#### Scenario: Indicador global
- **GIVEN** um indicador global na lista
- **WHEN** o usuario o visualiza
- **THEN** a acao oferecida e apenas conectar ou desconectar do projeto

#### Scenario: Indicador inativo
- **GIVEN** um indicador desativado
- **WHEN** ele e apresentado na lista
- **THEN** o estado inativo e visualmente distinguivel

### Requirement: FE-104 — Acoes do indicador especifico
As acoes de conectar, ativar/desativar, editar e excluir DEVEM (SHALL) permanecer utilizaveis apos a primeira execucao. Fonte legada: `app/views/.../indicator_connections/list/_widget.js.erb:22-165`.

#### Scenario: Duas acoes em sequencia
- **GIVEN** um indicador na lista
- **WHEN** o usuario aciona o interruptor e, apos a conclusao, o aciona de novo
- **THEN** a segunda acao e processada normalmente

> Nota: corrige o legado, onde `preventDoubleSubmit` era ativado mas **nunca restaurado** — apos uma acao o interruptor ficava inerte ate recarregar a tela.

#### Scenario: Usuario somente-leitura
- **GIVEN** um usuario somente-leitura
- **WHEN** ele tenta alterar o estado de um indicador
- **THEN** a acao e recusada e a tela informa a falta de permissao

### Requirement: FE-105 — Seletor de projeto na barra do console
A barra do console DEVE (SHALL) apresentar o seletor de projeto quando o usuario for membro de ao menos um projeto, listando apenas os projetos dele em ordem alfabetica. Fonte legada: `app/views/pub/console/base/handle_projects.js.erb:1-59`; `app/decorators/models/user_decorator.rb:159-163`.

#### Scenario: Trocar de projeto
- **GIVEN** um usuario membro de tres projetos
- **WHEN** ele escolhe outro projeto no seletor
- **THEN** o projeto corrente muda e as telas do console passam a refletir o novo escopo

### Requirement: FE-106 — Projeto corrente apos troca de usuario
O projeto corrente DEVE (SHALL) ser resolvido pela sessao do usuario autenticado, de forma deterministica, sem depender de estado armazenado no navegador. Fonte legada: `app/views/pub/console/base/handle_projects.js.erb:12-44`.

#### Scenario: Novo usuario no mesmo navegador
- **GIVEN** um navegador que acabou de ter a sessao trocada para outro usuario
- **WHEN** o console e aberto
- **THEN** o projeto corrente e um projeto do qual o novo usuario e membro

> Nota: corrige D-28 (legado: o cookie `cached_info` do cliente decidia o projeto corrente; quando o usuario mudava, o script apagava o cookie e forcava a **segunda** opcao do select — comportamento arbitrario e sem justificativa no codigo).

### Requirement: FE-107 — Tela "Disponibilidades" (padroes do projeto)
A tela DEVE (SHALL) apresentar a arvore de padroes de disponibilidade do projeto com titulo, tipo, prazo, acumulavel e corrigido, com indentacao por nivel, recarga manual e acesso ao cadastro. Fonte legada: `app/views/pub/console/parts/project_availabilities/_body.html.erb:1-40`; `list/_widget.html.erb:83-85`.

#### Scenario: Arvore de tres niveis
- **GIVEN** um projeto com padroes em tres niveis
- **WHEN** a tela e aberta
- **THEN** a hierarquia e visivel pela indentacao e a ordem segue a posicao dos padroes

### Requirement: FE-108 — Estados do padrao de disponibilidade na lista
Cada padrao DEVE (SHALL) indicar visualmente quando esta bloqueado, inativo ou especifico do projeto, e DEVE (SHALL) oferecer acoes coerentes com o seu estado. Fonte legada: `app/views/.../project_availabilities/list/_widget.html.erb:1-82`; `list/_widget.js.erb:16-45`.

#### Scenario: Padrao bloqueado
- **GIVEN** um padrao bloqueado por uma operacao em andamento
- **WHEN** ele e apresentado na lista
- **THEN** o bloqueio e visivel, a razao do bloqueio e consultavel e nenhuma acao e oferecida

#### Scenario: Padrao global com filhos
- **GIVEN** um padrao global que possui filhos e nao esta bloqueado
- **WHEN** o usuario abre suas acoes
- **THEN** as acoes disponiveis para esse estado sao apresentadas, sem menu vazio

> Nota: corrige o legado, onde a combinacao global + com filhos deixava o menu de contexto sem nenhum item (o interruptor simples so aparecia para global sem filhos, e o menu so tinha itens para nao-global).

### Requirement: FE-109 — Formulario de padrao de disponibilidade
O formulario DEVE (SHALL) permitir informar titulo, tipo de operacao, tipo de prazo, acumulavel, corrigido e padrao-pai, deixando claro o que pode ser alterado na edicao. Fonte legada: `app/views/.../project_availabilities/helper/_mount.js.erb:1-135`; `helper/_body.html.erb:1-107`.

#### Scenario: Edicao de padrao existente
- **GIVEN** um padrao ja existente com lancamentos
- **WHEN** o usuario abre a edicao
- **THEN** os campos que nao podem ser alterados sao apresentados como somente leitura, com a razao visivel

> AMBIGUIDADE: no legado **so o titulo e editavel** na edicao — todo o restante do formulario esta dentro de `if project_availability.id.blank?` (`helper/_body.html.erb:14-105`), sem nenhuma explicacao ao usuario. Confirmar se a restricao e intencional (mudar tipo/prazo invalidaria os lancamentos) ou limitacao acidental. A mensagem de estado vazio tambem e o texto herdado "Essa construtora nao pode ser alterada".

### Requirement: FE-110 — Dependencia entre padrao-pai e niveis no formulario
Ao escolher o padrao-pai, o formulario DEVE (SHALL) derivar e apresentar os niveis correspondentes, sem expor dados de outros projetos. Fonte legada: `app/views/.../project_availabilities/helper/_body.js.erb:1-39`; `helper/_body.html.erb:1`, `:25-40`.

#### Scenario: Escolher o padrao-pai
- **GIVEN** o formulario de novo padrao
- **WHEN** o usuario escolhe um padrao-pai de segundo nivel
- **THEN** os niveis superiores sao preenchidos automaticamente e apresentados como somente leitura

#### Scenario: Dados de outros projetos nao sao expostos
- **GIVEN** o formulario carregado para o projeto A
- **WHEN** a pagina e inspecionada
- **THEN** nenhum padrao de outro projeto esta presente no conteudo entregue

> Nota: corrige o vazamento do legado — todos os `AvailabilityTemplate` eram embutidos como JSON no atributo `data-templates` do wrapper, expondo templates de outros projetos e gerando um payload potencialmente grande.

### Requirement: FE-111 — Ativar e desativar padrao pela lista
A lista DEVE (SHALL) permitir ativar e desativar um padrao, com mensagens que se refiram a padrao de disponibilidade, e as acoes DEVEM (SHALL) permanecer utilizaveis apos a primeira execucao. Fonte legada: `app/views/.../project_availabilities/list/_widget.js.erb:47-95`, `:113-139`.

#### Scenario: Mensagem apos desativar
- **GIVEN** um padrao ativo
- **WHEN** o usuario o desativa com sucesso
- **THEN** a mensagem informa que o **padrao de disponibilidade** foi desativado

> Nota: corrige o texto errado do legado, que dizia "Indicador ativado/deasativado" (copiado da tela de indicadores, com erro de grafia). Corrige tambem o `preventDoubleSubmit` nunca restaurado.

### Requirement: FE-112 — Remover padrao de disponibilidade pela lista
A lista DEVE (SHALL) pedir confirmacao antes de remover um padrao e comunicar corretamente o resultado, coerente com a regra de lancamentos vinculados. Fonte legada: `app/views/.../project_availabilities/list/_widget.js.erb:171-200`.

#### Scenario: Confirmacao e retorno
- **GIVEN** um padrao sem lancamentos
- **WHEN** o usuario confirma a remocao
- **THEN** a tela informa que a remocao foi enfileirada e o padrao aparece como bloqueado ate a conclusao

> Nota: corrige o legado, onde a mensagem de sucesso usava a constante `M.SUCESS` (com erro de grafia, provavelmente `undefined`) e o atributo `data-deletable` era renderizado mas nunca consultado pelo JS.

### Requirement: FE-113 — Tela "Garantias do Projeto"
A tela DEVE (SHALL) listar as garantias com filtros por portador e tipo, busca, ordenacao por coluna e navegacao entre paginas, disparando uma unica consulta por interacao. Fonte legada: `app/views/pub/console/parts/project_guarantees/_body.html.erb:1-92`; `_body.js.erb:1-420`.

#### Scenario: Ordenar por uma coluna
- **GIVEN** a lista de garantias
- **WHEN** o usuario clica em um cabecalho ordenavel
- **THEN** uma unica consulta e enviada e a lista volta ordenada

> Nota: corrige o legado, onde o handler de ordenacao executava o proxy duas vezes (`_body.js.erb:65` e `:90`), duplicando a requisicao a cada clique.

#### Scenario: Navegar entre paginas
- **GIVEN** 300 garantias no projeto corrente
- **WHEN** o usuario avanca de pagina
- **THEN** a tela mostra o proximo conjunto de garantias e o total refletido corresponde a base completa

> Nota: corrige D-20.

### Requirement: FE-114 — Item de garantia e acoes
Cada garantia DEVE (SHALL) apresentar o valor formatado em reais e oferecer edicao e remocao conforme a permissao do usuario. Fonte legada: `app/views/.../project_guarantees/list/_widget.html.erb:1-34`; `list/_widget.js.erb:1-98`.

#### Scenario: Usuario somente-leitura
- **GIVEN** um usuario somente-leitura
- **WHEN** ele visualiza a lista de garantias
- **THEN** as acoes de editar e remover nao sao oferecidas

### Requirement: FE-115 — Formulario de garantia
O formulario DEVE (SHALL) oferecer titulo, portador, tipo de garantia, observacao e valor, e DEVE (SHALL) usar um unico criterio para determinar se o projeto tem portador disponivel. Fonte legada: `app/views/pub/console/parts/project_guarantees/new/_body.html.erb:1-102`.

#### Scenario: Projeto sem portador conectado
- **GIVEN** um projeto sem nenhum portador conectado
- **WHEN** o usuario tenta cadastrar uma garantia
- **THEN** a tela informa que e necessario ter um portador no projeto, e o mesmo criterio vale para o botao de cadastrar e para o formulario

> Nota: corrige a incoerencia do legado — o botao "Cadastrar" usava `active_risk_controls_carriers` (portadores **com limite de risco**) enquanto o formulario validava por `project.carriers` (todos os conectados).

### Requirement: FE-116 — Tela "Tipos de garantia"
A tela DEVE (SHALL) listar os tipos de garantia com busca, ordenacao por titulo e chave, e acoes de cadastro, edicao e exclusao restritas a papel autorizado. Fonte legada: `app/views/pub/console/parts/project_guarantee_types/_body.html.erb:1-40`; `list/_widget.html.erb:1-35`.

#### Scenario: Tipo desativado
- **GIVEN** um tipo de garantia desativado
- **WHEN** a lista e aberta
- **THEN** o comportamento segue a regra definida em BE-700 quanto a exibicao de tipos inativos

### Requirement: FE-117 — Formulario de tipo de garantia
O formulario DEVE (SHALL) oferecer titulo, chave de integracao e situacao, com mensagens de erro identificando o campo. Fonte legada: `app/views/.../project_guarantee_types/helper/_body.html.erb:1-36`; `helper/destroy.js.erb:1-13`.

#### Scenario: Exclusao de tipo em uso
- **GIVEN** um tipo de garantia usado por garantias existentes
- **WHEN** o usuario tenta exclui-lo
- **THEN** a tela informa que o tipo esta em uso, com a mensagem identificando o campo

> Nota: corrige o legado, onde o erro de dependencia era exibido sem prefixo de campo.

### Requirement: FE-118 — Aba "Projetos" no detalhe do usuario
O detalhe do usuario DEVE (SHALL) apresentar de quais projetos ele participa. Fonte legada: `app/views/pub/console/parts/users/detail/tabs/_tab_projects.html.erb`; `users/detail/projects/list/_widget.html.erb:1-21`.

#### Scenario: Visualizar os projetos de um usuario
- **GIVEN** um usuario que participa de 2 projetos
- **WHEN** um administrador abre a aba de projetos desse usuario
- **THEN** os projetos em que ele participa aparecem claramente identificados

> AMBIGUIDADE: no legado a aba listava **todos** os projetos com um interruptor `disabled readonly` (puramente informativo). Confirmar se ela deve permitir vincular/desvincular no ai9.

### Requirement: FE-119 — Visibilidade de menu do dominio de projetos
O menu do console DEVE (SHALL) apresentar os itens do dominio de projetos conforme papel do usuario e existencia de projeto. Fonte legada: `app/helpers/application_helper.rb:100-172`.

#### Scenario: Usuario sem projetos
- **GIVEN** um usuario que nao e membro de nenhum projeto
- **WHEN** ele abre o console
- **THEN** o grupo de itens do projeto (Disponibilidades, Garantias, Indicadores especificos) nao aparece

#### Scenario: Item bloqueado no menu
- **GIVEN** um item de menu marcado como bloqueado
- **WHEN** o usuario o visualiza
- **THEN** o motivo do bloqueio e comunicado de forma explicita

> AMBIGUIDADE: a semantica exata de `locked: true` no menu (aplicada a Disponibilidades) nao foi verificada no legado. Confirmar o que o bloqueio significa para o usuario.

### Requirement: DB-080 — Tabela `projects`
O modelo de dados DEVE (SHALL) conter projetos com nome unico, identificador amigavel unico, chave de integracao unica, dono, responsavel, segmento, subsegmento, endereco, situacao, marcas de gestao e BI, e dados de progresso de tarefa, com chaves estrangeiras e indices. Fonte legada: `db/migrate/20210301170412_create_projects.rb` e migrations posteriores; `app/models/project.rb`.

#### Scenario: Referencia de responsavel valida
- **GIVEN** um projeto com responsavel definido
- **WHEN** o registro e lido
- **THEN** o responsavel e um identificador de usuario valido, do mesmo tipo usado nas demais referencias de usuario

> Nota: corrige o legado, onde `responsible_id` era **string** apesar de ser uma referencia de usuario, e nao havia FK nem indice em `user_id`, `segment_id`, `smart_id` e `integration_key` (que deveriam ser unicos). As marcas booleanas eram inteiros 0/1, e `is_active` validava com `presence` (o valor `0` passava, `nil` nao).

#### Scenario: Nome e identificador amigavel unicos no banco
- **GIVEN** duas requisicoes concorrentes criando projetos com o mesmo nome
- **WHEN** ambas sao processadas
- **THEN** apenas uma persiste

### Requirement: DB-081 — Tabela `project_to_carrier_connections`
O modelo de dados DEVE (SHALL) conter a ponte projeto-portador com chaves estrangeiras e restricao unica de portador por projeto. Fonte legada: `db/migrate/20210301192607_create_project_to_carrier_connections.rb`.

#### Scenario: Conexao duplicada bloqueada no banco
- **GIVEN** duas requisicoes concorrentes conectando o mesmo portador ao mesmo projeto
- **WHEN** ambas sao processadas
- **THEN** apenas uma conexao persiste

> Nota: corrige o legado, onde a unicidade era apenas de aplicacao e uma corrida criava duplicatas. As colunas `legacy_*` sao residuo da importacao anterior — preservadas para reconciliacao (DEC-12).

### Requirement: DB-082 — Tabela `project_indicator_connections`
O modelo de dados DEVE (SHALL) conter a ponte projeto-indicador com chaves estrangeiras e restricao unica de indicador por projeto. Fonte legada: `db/migrate/20211026184044_create_project_indicator_connections.rb`.

#### Scenario: Conexao duplicada bloqueada no banco
- **GIVEN** duas requisicoes concorrentes conectando o mesmo indicador ao mesmo projeto
- **WHEN** ambas sao processadas
- **THEN** apenas uma conexao persiste

> Nota: corrige tambem o parametro `is_active` aceito pelo controller (`project_indicator_connections_controller.rb:196`) sem que a coluna exista.

### Requirement: DB-083 — Tabela `project_guarantees`
O modelo de dados DEVE (SHALL) conter garantias ligadas a projeto, portador, tipo de garantia e usuario, com titulo, valor decimal, observacao em texto longo, chaves estrangeiras e indices. Fonte legada: `db/migrate/20220627125026_create_project_guarantees.rb`.

#### Scenario: Observacao longa
- **GIVEN** uma garantia com observacao de mais de 255 caracteres
- **WHEN** ela e salva e lida de volta
- **THEN** o texto e preservado integralmente

> Nota: corrige o legado, onde `observation` era `string` (255) enquanto o formulario usava `textarea` — risco de truncamento.

### Requirement: DB-084 — Tabela `project_guarantee_types`
O modelo de dados DEVE (SHALL) conter tipos de garantia com titulo e chave de integracao unicos, situacao e usuario responsavel, bloqueando a exclusao de tipo em uso. Fonte legada: `db/migrate/20220627125208_create_project_guarantee_types.rb`; `app/models/project_guarantee_type.rb`.

#### Scenario: Titulo duplicado bloqueado no banco
- **GIVEN** duas requisicoes concorrentes criando tipos de garantia com o mesmo titulo
- **WHEN** ambas sao processadas
- **THEN** apenas uma persiste

### Requirement: DB-085 — Tabela de padroes de disponibilidade (`availability_templates`)
O modelo de dados DEVE (SHALL) representar a hierarquia de padroes de disponibilidade (ate tres niveis, globais e por projeto) de forma consultavel e ordenavel, com chaves estrangeiras e indices. Fonte legada: `db/migrate/20210420180734_create_availability_templates.rb` e migrations posteriores.

#### Scenario: Consulta da arvore de um projeto
- **GIVEN** um projeto com milhares de padroes
- **WHEN** a arvore ordenada e consultada
- **THEN** a consulta usa indices e responde dentro do limite de performance definido

> Nota: corrige o legado, onde a hierarquia era mantida por **tres colunas numericas mais uma string `position`** redundantes, `top_parent_id` tinha default `0` (nao nulo, gerando comparacoes ambiguas) e nao havia indice em `project_id` nem em `parent_template_id`, com a reordenacao em custo quadratico (BE-116).

### Requirement: DB-086 — Tabela `memberships`
O modelo de dados DEVE (SHALL) conter os vinculos entre usuario e projeto com papel definido em um conjunto estavel, unico por usuario e projeto. Fonte legada: `app/models/membership.rb`.

#### Scenario: Papel do vinculo
- **GIVEN** um vinculo de membro criado
- **WHEN** o registro e lido
- **THEN** o papel pertence ao conjunto conhecido (responsavel, participante, coordenador, gestor)

> Nota: corrige o legado, onde os papeis eram texto livre em pt-BR sem enum. A remocao de projeto usava `delete_all` nos vinculos, sem callbacks.

### Requirement: DB-087 — Projeto corrente do usuario no modelo de dados
O modelo de dados DEVE (SHALL) representar o projeto corrente do usuario com chave estrangeira e indice, e o valor DEVE (SHALL) sempre corresponder a um projeto do qual ele e membro. Fonte legada: `db/migrate/20210303182740_add_default_project_to_livetat_auth_users.rb`; `app/decorators/models/user_decorator.rb:46`.

#### Scenario: Projeto corrente sem membership
- **GIVEN** um usuario cujo vinculo com o projeto corrente foi removido
- **WHEN** ele faz a proxima requisicao
- **THEN** o projeto corrente e reavaliado e passa a ser um projeto do qual ele e membro, ou nenhum

> Nota: corrige D-28 (legado: sem FK, sem indice e sem validacao de membership; e este campo e o tenant de fato de quase todo o sistema — recebiveis, renegociacoes, risco, fornecedores, garantias, disponibilidades).

### Requirement: DB-088 — Texto formatado da observacao de disponibilidade
O modelo de dados DEVE (SHALL) guardar a observacao de disponibilidade do projeto como texto formatado sanitizado. Fonte legada: `app/models/project.rb:60`.

#### Scenario: Migracao do conteudo formatado
- **GIVEN** projetos legados com observacao formatada
- **WHEN** o conteudo e migrado
- **THEN** a marcacao permitida e preservada e nenhum conteudo executavel sobrevive

### Requirement: DB-089 — Logo do projeto
O modelo de dados DEVE (SHALL) guardar o logo do projeto e seus derivados no storage do ai9. Fonte legada: `app/models/project.rb:48-58,133-135`.

#### Scenario: Projeto sem logo
- **GIVEN** um projeto sem logo enviado
- **WHEN** o registro e lido
- **THEN** a ausencia de logo e representada explicitamente

> Nota: corrige o legado, onde `has_avatar?` tratava a string literal `"missing.jpg"` como ausencia e os arquivos ficavam em disco local via Paperclip (descontinuado).

### Requirement: DB-090 — Denormalizacao da marca de gestao nas tabelas filhas
O modelo de dados DEVE (SHALL) definir de forma unica como a marca de gestao Safegold e representada nos registros derivados do projeto. Fonte legada: `app/models/company.rb:13`; `availability_entry.rb:17`; `receivable_entry.rb:40`; `renegotiation.rb:24`; `risk_control.rb:15`; `risk_entry.rb:32`.

#### Scenario: Consulta historica filtrada pela marca
- **GIVEN** um projeto cuja marca foi alterada apos ja existirem lancamentos
- **WHEN** um relatorio filtra registros pela marca
- **THEN** o resultado corresponde a regra definida, de forma consistente entre todas as tabelas

> AMBIGUIDADE: D-30 — no legado a marca e copiada para 6 tabelas no `before_validation`, mas so `companies` e atualizada em massa quando a flag muda; os dados historicos ficam inconsistentes **por design** e qualquer relatorio que filtre por ela mente. Decidir entre derivar do projeto em tempo de consulta ou manter carimbo historico explicito e datado.

### Requirement: DB-091 — Rastros de importacao anterior
O modelo de dados DEVE (SHALL) preservar as chaves de correlacao com o sistema anterior enquanto forem necessarias a reconciliacao. Fonte legada: `db/migrate/20210402111120_add_legacy_id_to_entries_and_projects.rb`; `20210403154220`.

#### Scenario: Reconciliacao de projetos importados
- **GIVEN** projetos com identificador de origem preenchido
- **WHEN** a reconciliacao pos-migracao roda
- **THEN** cada projeto pode ser correlacionado ao registro de origem

> Nota: DEC-12 — as colunas `legacy_*` sao preservadas por serem a unica prova de proveniencia dos dados de 2016-2021; o pipeline que as gerou nao e portado.

### Requirement: DB-092 — Indicador global x indicador de projeto
O modelo de dados DEVE (SHALL) representar explicitamente se um indicador e global ou especifico de um projeto. Fonte legada: `db/migrate/20211029172624_add_project_to_indicator.rb`.

#### Scenario: Distincao entre global e especifico
- **GIVEN** um indicador global e um indicador especifico de projeto
- **WHEN** ambos sao lidos
- **THEN** o escopo de cada um e identificavel de forma explicita, sem depender de um campo nulo

> Nota: no legado a semantica "`project_id` nulo = global" governa toda a interface de indicadores especificos; preservar de forma explicita no ai9.

### Requirement: OPS-080 — Vinculo automatico de membros padrao ao projeto
A criacao de projeto DEVE (SHALL) vincular automaticamente os usuarios marcados como membro padrao, com o resultado observavel e com falhas visiveis. Fonte legada: `lib/insert_default_user_on_project_job.rb`; `app/models/project.rb:74-79,381-390`.

#### Scenario: Falha no vinculo automatico
- **GIVEN** uma falha ao vincular os membros padrao de um projeto novo
- **WHEN** a falha ocorre
- **THEN** a tarefa e reexecutada conforme a politica de retentativa e, esgotadas as tentativas, a falha fica visivel para o usuario

> Nota: corrige D-05 na familia de jobs (legado: `destroy_failed_jobs?` era `false` e o job falho ficava na fila sem visibilidade).

### Requirement: OPS-081 — Replicacao dos padroes globais para o projeto novo
A criacao de projeto (e a limpeza de projeto de treinamento) DEVE (SHALL) replicar todos os padroes de disponibilidade globais para o projeto, preservando a hierarquia, com progresso observavel. Fonte legada: `lib/create_global_template_for_project_job.rb`; `app/models/project.rb:82-88,312-347`.

#### Scenario: Hierarquia preservada na replicacao
- **GIVEN** padroes globais em tres niveis
- **WHEN** um projeto e criado
- **THEN** o projeto recebe todos os padroes com a mesma hierarquia e ordenacao

#### Scenario: Falha na replicacao
- **GIVEN** uma falha durante a replicacao
- **WHEN** ela ocorre
- **THEN** a tarefa e reexecutada e, esgotadas as tentativas, o projeto fica marcado com a falha visivel em vez de ficar silenciosamente incompleto

> Nota: corrige D-05.

### Requirement: OPS-082 — Processamento da ativacao de padrao
A ativacao de padrao DEVE (SHALL) ser processada em segundo plano com retentativa, liberacao garantida do bloqueio e falha visivel. Fonte legada: `lib/project_availability_template_activate_job.rb`; `app/models/project_availability_template.rb:697-742`.

#### Scenario: Falha no meio do recalculo
- **GIVEN** uma ativacao que falha durante o recalculo dos lancamentos
- **WHEN** a falha ocorre
- **THEN** o bloqueio do padrao e dos filhos e liberado e o erro fica registrado e visivel

> Nota: corrige D-05 (legado: `rescue` engolia a excecao, sem retry, e `unlocked!` so era chamado no caminho feliz — o template ficava travado para sempre).

### Requirement: OPS-083 — Processamento da desativacao de padrao
A desativacao de padrao DEVE (SHALL) ser processada em segundo plano com retentativa, liberacao garantida do bloqueio e falha visivel, aplicando o recalculo dos somatorios afetados. Fonte legada: `lib/project_availability_template_deactivate_job.rb`; `app/models/project_availability_template.rb:744-800`.

#### Scenario: Falha na desativacao
- **GIVEN** uma desativacao que falha no processamento
- **WHEN** a falha ocorre
- **THEN** o bloqueio e liberado e o erro fica visivel

> Nota: corrige D-05.

### Requirement: OPS-084 — Processamento da remocao de padrao
A remocao de padrao DEVE (SHALL) ser processada em segundo plano com retentativa, liberacao garantida do bloqueio e falha visivel, recalculando os somatorios e reordenando a arvore. Fonte legada: `lib/project_availability_template_removal_job.rb`; `app/models/project_availability_template.rb:601-695`.

#### Scenario: Falha na remocao deixa o padrao utilizavel
- **GIVEN** uma remocao que falha no processamento
- **WHEN** a falha ocorre
- **THEN** o bloqueio e liberado, o padrao volta a ser utilizavel e a falha fica visivel

> Nota: corrige D-05 (legado: se o job terminava em `FAILED`, o template permanecia **travado**, pois `unlocked!` nao era chamado no `rescue`).

### Requirement: OPS-085 — Vinculo de usuario padrao a todos os projetos
Ao marcar um usuario como membro padrao, o sistema DEVE (SHALL) vincula-lo aos projetos existentes com resultado observavel e falhas registradas. Fonte legada: `lib/insert_projects_on_default_user_job.rb`; `app/decorators/models/user_decorator.rb:243-262`.

#### Scenario: Falha no vinculo em massa
- **GIVEN** uma falha ao vincular o usuario padrao a um dos projetos
- **WHEN** a falha ocorre
- **THEN** o erro e registrado e fica visivel, e os demais vinculos nao sao perdidos

> Nota: corrige o legado, onde o `rescue` era **vazio** e os erros sumiam sem log.

### Requirement: OPS-086 — Trilha de auditoria do dominio de projetos
O sistema DEVE (SHALL) registrar em trilha de auditoria os eventos relevantes do projeto: criacao, replicacao de padroes globais, ativacao, desativacao e remocao de padrao, e progresso de onboarding. Fonte legada: `lib/tracking_facade.rb:15-260`; `config/routes.rb:237`.

#### Scenario: Consulta da trilha de um projeto
- **GIVEN** um projeto com varios eventos registrados
- **WHEN** a trilha do projeto e consultada por um usuario autorizado
- **THEN** os eventos sao devolvidos com descricao em pt-BR e referencia ao projeto

#### Scenario: Trilha exige autorizacao
- **GIVEN** um cliente sem autorizacao para o projeto
- **WHEN** ele consulta a trilha
- **THEN** a resposta e 403 ou 404, sem devolver eventos

### Requirement: OPS-087 — Progresso de tarefas exibido na interface
O progresso das tarefas em segundo plano do projeto DEVE (SHALL) ser consultavel e refletido na interface sem recarregamento manual. Fonte legada: `app/models/project.rb:145-147,672-684`; `app/models/project_availability_template.rb:802-814`.

#### Scenario: Acompanhar o progresso
- **GIVEN** uma tarefa em segundo plano em andamento para um projeto
- **WHEN** o usuario esta com a tela aberta
- **THEN** o percentual apresentado avanca ate a conclusao sem intervencao dele

> Nota: corrige D-86 (legado: sem polling nem push, o percentual so mudava em novo carregamento). No ai9 a atualizacao chega por Action Cable.

### Requirement: OPS-088 — Processamento de imagem do logo do projeto
O envio do logo do projeto DEVE (SHALL) gerar os tamanhos derivados usados pela interface. Fonte legada: `app/models/project.rb:48-58`.

#### Scenario: Derivados gerados no envio
- **GIVEN** um logo enviado no formulario do projeto
- **WHEN** o envio e concluido
- **THEN** os tamanhos derivados usados nas listas e no detalhe estao disponiveis

### Requirement: OPS-089 — Rotinas de correcao de dados do dominio de projetos
As correcoes de dados sobre padroes orfaos e lancamentos sem empresa DEVEM (SHALL) ser operacoes idempotentes, auditadas e com pre-visualizacao. Fonte legada: `app/models/project_availability_template.rb:604-614`; `app/models/availability_entry.rb:245-250`.

#### Scenario: Correcao de padroes orfaos
- **GIVEN** padroes que referenciam um padrao global ja removido
- **WHEN** a rotina de correcao e executada
- **THEN** ela reporta o que sera alterado antes de alterar, registra o resultado e pode ser executada de novo sem efeito adicional

> Nota: corrige o legado, onde as rotinas (`fix_after_global_remove`, `fix__7412`) eram executadas a mao no console, sem rake task, sem agendamento e sem log persistente.

### Requirement: BE-700 — Buscar e ordenar tipos de garantia
O sistema DEVE (SHALL) listar tipos de garantia com busca textual, ordenacao e paginacao efetivas, exigindo autenticacao e autorizacao. Fonte legada: `config/routes.rb:212`; `app/controllers/pub/project_guarantee_types_controller.rb:9-39`.

#### Scenario: Paginacao aplicada
- **GIVEN** 60 tipos de garantia cadastrados
- **WHEN** o cliente pede `l=20`, `o=20`
- **THEN** sao devolvidos 20 tipos a partir do 21o e o total informado e 60

> Nota: corrige D-20 (legado: no ramo sem `ordering_keys` o encadeamento apos `where!` era descartado (`:23-27`) e, no ramo com ordenacao, apenas `order!` era aplicado (`:29-33`) — limite e offset caiam nos dois casos).

#### Scenario: Requisicao sem autenticacao
- **GIVEN** um cliente sem credencial valida
- **WHEN** ele lista tipos de garantia
- **THEN** a resposta e 401

> Nota: corrige D-23 (legado: herdava `requires_current_user? == false` de `PubApplicationController` — sem autenticacao e sem checagem de permissao no backend).

#### Scenario: Tipo desativado na edicao de garantia existente
- **GIVEN** uma garantia que usa um tipo desativado
- **WHEN** o usuario abre a edicao dessa garantia
- **THEN** o tipo atual continua identificavel na tela

> AMBIGUIDADE: no legado o escopo era `ProjectGuaranteeType.active` (SQL cru `is_active = 1`) e o tipo desativado **nunca aparecia**, nem na edicao de uma garantia que ja o usava. Confirmar se tipo inativo deve continuar visivel nesse caso.

### Requirement: BE-701 — Formulario de novo tipo de garantia
O sistema DEVE (SHALL) fornecer os dados para abrir o formulario de novo tipo de garantia, exigindo autorizacao no servidor. Fonte legada: `config/routes.rb:213`; `app/controllers/pub/project_guarantee_types_controller.rb:49-57`.

#### Scenario: Usuario sem permissao
- **GIVEN** um usuario sem papel autorizado a cadastrar tipos de garantia
- **WHEN** ele pede o formulario de novo tipo
- **THEN** a resposta e 403

> Nota: corrige D-23 (legado: o gate `og`/`admin`/`manager` existia somente na view).

### Requirement: BE-702 — Formulario de edicao de tipo de garantia
O sistema DEVE (SHALL) fornecer os dados de um tipo de garantia existente para edicao. Fonte legada: `config/routes.rb:213`; `app/controllers/pub/project_guarantee_types_controller.rb:59-65`, `:112-115`.

#### Scenario: Tipo inexistente
- **GIVEN** um id de tipo de garantia que nao existe
- **WHEN** o cliente pede o formulario de edicao
- **THEN** a resposta e 404

### Requirement: BE-703 — Criar tipo de garantia
O sistema DEVE (SHALL) criar um tipo de garantia com titulo unico, chave de integracao derivada do titulo e situacao, atribuindo o usuario responsavel a partir da sessao. Fonte legada: `config/routes.rb:213`; `app/controllers/pub/project_guarantee_types_controller.rb:67-80`, `:117-129`.

#### Scenario: Usuario responsavel vem da sessao
- **GIVEN** um usuario autenticado criando um tipo de garantia
- **WHEN** ele envia um identificador de usuario diferente do seu no corpo da requisicao
- **THEN** o campo e ignorado e o responsavel registrado e o usuario da sessao

> Nota: corrige D-23 (legado: `user_id` vinha do formulario e **nao** era sobrescrito por `current_user`, diferente de outros controllers).

#### Scenario: Titulo duplicado
- **GIVEN** um tipo de garantia com o titulo `Aval` ja cadastrado
- **WHEN** outro com o mesmo titulo e criado
- **THEN** a resposta e 422 com a mensagem identificando o campo "Titulo"

### Requirement: BE-704 — Atualizar tipo de garantia
O sistema DEVE (SHALL) atualizar titulo, chave de integracao e situacao de um tipo de garantia. Fonte legada: `config/routes.rb:213`; `app/controllers/pub/project_guarantee_types_controller.rb:82-96`.

#### Scenario: Alterar o titulo
- **GIVEN** um tipo de garantia chamado `Aval` com chave `aval`
- **WHEN** o titulo e alterado para `Aval Bancario`
- **THEN** o titulo e atualizado e a chave de integracao segue a regra definida

> AMBIGUIDADE: no legado a chave de integracao e derivada do titulo **somente na criacao**, entao titulo e chave divergem apos a primeira edicao. Confirmar se a chave deve ser recalculada, permanecer congelada ou ser editavel explicitamente.

### Requirement: BE-705 — Excluir tipo de garantia
O sistema DEVE (SHALL) excluir um tipo de garantia e DEVE (SHALL) bloquear a exclusao, com erro visivel, quando existirem garantias que o utilizem. Fonte legada: `config/routes.rb:213`; `app/controllers/pub/project_guarantee_types_controller.rb:98-110`; `app/models/project_guarantee_type.rb`.

#### Scenario: Tipo em uso
- **GIVEN** um tipo de garantia usado por pelo menos uma garantia
- **WHEN** o usuario solicita a exclusao
- **THEN** a resposta e 422 informando o vinculo, e o tipo continua existindo

#### Scenario: Tipo sem uso
- **GIVEN** um tipo de garantia que nenhuma garantia utiliza
- **WHEN** o usuario solicita a exclusao
- **THEN** o tipo e removido e a resposta e 200

### Requirement: BE-706 — Listagem e detalhe de tipo de garantia
O sistema DEVE (SHALL) expor listagem e detalhe de tipo de garantia por endpoints que respondem de fato. Fonte legada: `config/routes.rb:213`; `app/controllers/pub/project_guarantee_types_controller.rb:5-7`, `:41-47`.

#### Scenario: Detalhe de tipo de garantia
- **GIVEN** um tipo de garantia cadastrado
- **WHEN** o cliente pede o detalhe
- **THEN** a resposta traz titulo, chave de integracao e situacao, com status 200

> Nota: corrige as rotas mortas do legado — `index` e `show` renderizavam templates inexistentes (`ActionView::MissingTemplate`, 500), mesmo padrao de BE-101; a navegacao real passava pelo console.
