# Misc Domain Specification

## Purpose
Dominio residual transversal do legado: trilha de atividade (tracking), geolocalizacao e endereco, anexo de imagem polimorfico, cadastros e validadores compartilhados, o pipeline de importacao do sistema antigo, os controllers base da area logada e da API, e os helpers que carregam regra de negocio (formatacao, menu, pluralizacao, datas).

> Nota de escopo (DEC-09): so o que existe no legado. i18n fica fora (D-115): pt-BR fixo — mas os textos deixam de ser literais espalhados no codigo e passam a viver em um lugar so.
> Nota de escopo (DEC-12): o pipeline `Legacy::execute` e assumido como **nao executado** desde 2021; ele **nao e portado** como codigo de aplicacao. O que fica registrado aqui e o **comportamento** que produziu os dados historicos, mais a preservacao das colunas `legacy_*` como unica prova de proveniencia.

## Requirements

### Requirement: BE-430 — Registro de trilha de atividade
O sistema SHALL registrar eventos de trilha imutaveis, ligados ao objeto afetado e ao seu pai, com autor, tipo e resumo. Fonte legada: `app/models/tracking.rb:1-15`.

> Nota: corrige o truncamento silencioso (legado: `resume` e limitado a **300 caracteres**, e as mensagens de falha concatenam o texto da excecao — quando estouram o limite, a gravacao retorna falso e **ninguem verifica**, entao o evento simplesmente nao existe) e a ausencia de politica de retencao (legado: a tabela cresce indefinidamente, sem expurgo e sem indice).

#### Scenario: Resumo longo nao perde o evento
- **GIVEN** um evento cujo resumo excede o limite de tamanho
- **WHEN** ele e registrado
- **THEN** o resumo e truncado de forma explicita e o evento e gravado — a falha de gravacao nunca passa despercebida

#### Scenario: Destinatario opcional
- **GIVEN** um evento sem usuario destinatario
- **WHEN** ele e registrado
- **THEN** a gravacao e aceita; o autor, por sua vez, e obrigatorio

#### Scenario: Retencao
- **GIVEN** eventos de trilha mais antigos que o prazo de retencao configurado
- **WHEN** a rotina de expurgo executa
- **THEN** eles sao removidos e o volume da tabela permanece limitado

### Requirement: BE-431 — Eventos de ciclo de vida das operacoes de template
O sistema SHALL emitir eventos de trilha para as etapas de pedido, inicio, sucesso e falha das operacoes de template de disponibilidade. Fonte legada: `lib/tracking_facade.rb:15-295`; chamadores em `app/controllers/pub/project_availabilities_controller.rb:72,91,110`, `app/models/project.rb:87,743`, `app/models/global_availability_template.rb:34` e nos jobs de template.

> Nota: corrige a gravacao silenciosamente invalida (legado: o autor so e preenchido quando existe, mas o proprio model **exige** autor — entao jobs disparados sem usuario gravam autor nulo e a gravacao **falha em silencio**) e os textos com erro de digitacao preservados em producao ("A inercao do template", "concluida" sem acento), que passam a viver em um catalogo de mensagens em vez de literais no codigo.

#### Scenario: Quarteto completo por operacao
- **GIVEN** uma operacao de template de disponibilidade
- **WHEN** ela e pedida, iniciada, concluida ou falha
- **THEN** ha um evento de trilha para cada uma dessas etapas

#### Scenario: Operacao disparada pelo sistema
- **GIVEN** uma operacao disparada por rotina, sem usuario
- **WHEN** os eventos sao emitidos
- **THEN** eles sao gravados com autoria de sistema — nenhum evento e perdido por falta de autor

#### Scenario: Falha carrega o motivo
- **GIVEN** uma operacao que falha
- **WHEN** o evento de falha e gravado
- **THEN** ele traz o motivo da falha de forma legivel

### Requirement: BE-432 — Consulta da trilha de atividade
O sistema SHALL listar eventos de trilha filtrados por destinatario, grupo ou objeto, **escopados ao que o solicitante pode ver**, ordenados do mais recente e paginados com teto. Fonte legada: `app/controllers/api/v1/trackings_controller.rb:3-37`.

> Nota: corrige D-110 (legado: o endpoint parte da colecao completa de eventos e **nunca filtra por projeto nem por permissao** — qualquer sessao ou token autenticado lista a trilha do sistema inteiro, vazamento horizontal). Corrige tambem o filtro escrito errado (legado: a condicao testa **duas vezes o mesmo parametro** em vez de testar o par identificador e tipo), o parametro de busca lido e nunca usado, o limite sem teto vindo do cliente, e a paginacao aplicada apenas quando ha resultado — o que dispara uma contagem extra.

#### Scenario: Escopo obrigatorio
- **GIVEN** um usuario autenticado sem acesso a um projeto
- **WHEN** ele consulta a trilha
- **THEN** nenhum evento daquele projeto aparece no resultado

#### Scenario: Teto de pagina
- **GIVEN** uma requisicao pedindo um limite muito alto
- **WHEN** ela e processada
- **THEN** o limite e reduzido ao teto configurado e o total e informado

#### Scenario: Filtro por objeto ou por pai do objeto
- **GIVEN** um objeto com eventos proprios e eventos do seu pai
- **WHEN** a consulta filtra por objeto e por pai
- **THEN** os dois conjuntos sao retornados, ordenados do mais recente para o mais antigo

### Requirement: BE-433 — Detalhe do evento de trilha
O sistema SHALL retornar o detalhe de um evento de trilha. Fonte legada: `app/controllers/api/v1/trackings_controller.rb:39-51,54-56`.

> Nota: corrige codigo morto e quebrado (legado: o filtro de carga **nao carrega o evento**, o metodo de carga privado esta **vazio**, e o model **nao tem** associacao de geolocalizacao — chamar a rota resulta em `NoMethodError`; alem disso o ponto de referencia recalculado nunca era persistido, por falta de gravacao).

#### Scenario: Detalhe carrega
- **GIVEN** um evento de trilha existente e visivel ao solicitante
- **WHEN** o detalhe e pedido
- **THEN** os dados do evento sao retornados

#### Scenario: Evento inexistente ou fora do escopo
- **GIVEN** um identificador invalido ou fora do escopo do solicitante
- **WHEN** o detalhe e pedido
- **THEN** a resposta e 404

> AMBIGUIDADE: a assinatura do legado aceitava coordenadas de referencia para recalcular distancia, sugerindo que a intencao era associar geolocalizacao ao evento de trilha — feature nunca entregue. Confirmar com o tech lead se o ai9 deve implementar a intencao ou apenas descartar o caminho morto.

### Requirement: BE-434 — Evento de trilha na criacao de projeto
O sistema SHALL registrar um evento de trilha quando um projeto e criado. Fonte legada: `app/controllers/pub/projects_controller.rb:135`.

> Nota: corrige a chamada a metodo inexistente (legado: o controller chama um emissor de trilha que **nao existe** na fachada — criar projeto por esse caminho estoura `NoMethodError`). A chamada confirma a **intencao** de registrar a criacao de projeto: no ai9 a intencao e implementada, o defeito nao e portado.

#### Scenario: Criacao de projeto registrada
- **GIVEN** um usuario criando um projeto
- **WHEN** a criacao conclui
- **THEN** um evento de trilha e registrado com o autor, o projeto e o resumo da criacao — e a criacao **nao** falha por causa da trilha

### Requirement: BE-435 — Geocodificacao reversa do endereco
O sistema SHALL preencher os campos de endereco a partir das coordenadas, sem bloquear a gravacao. Fonte legada: `app/models/geolocation.rb:2,133-162`; `config/initializers/geocoding.rb:1-6`.

> Nota: corrige a chamada de rede sincrona dentro da gravacao (legado: a consulta ao servico externo acontece **dentro do `before_save`, sem tratamento de excecao**, com um tempo limite absurdo configurado — falha ou lentidao do servico **trava a gravacao**). Corrige tambem a chave de API do mapa embutida no codigo-fonte, que passa a ser configuracao de ambiente (ver `brand-and-metadata.md`).

#### Scenario: Servico externo indisponivel
- **GIVEN** o servico de geocodificacao fora do ar
- **WHEN** uma geolocalizacao e gravada
- **THEN** a gravacao conclui com as coordenadas, o preenchimento do endereco fica pendente e e reprocessado depois

#### Scenario: Preenchimento automatico ligado
- **GIVEN** uma geolocalizacao com preenchimento automatico ligado
- **WHEN** as coordenadas mudam
- **THEN** logradouro, numero, bairro, cidade, estado, CEP e pais sao recarregados a partir das novas coordenadas

#### Scenario: Preenchimento automatico desligado
- **GIVEN** uma geolocalizacao com endereco informado manualmente e preenchimento automatico desligado
- **WHEN** ela e gravada
- **THEN** os campos informados sao preservados

### Requirement: BE-436 — Endereco formatado para exibicao
O sistema SHALL montar o endereco formatado a partir dos campos disponiveis, omitindo separadores de partes ausentes. Fonte legada: `app/models/geolocation.rb:25-60`.

> Nota: corrige a montagem de marcacao no model (legado: o metodo **devolve HTML cru** com quebras de linha, construido a partir de dados fornecidos pelo usuario — risco de injecao se renderizado sem escape). No ai9 a montagem devolve dados estruturados e a apresentacao fica na interface.

#### Scenario: Endereco parcial
- **GIVEN** uma geolocalizacao com cidade e estado mas sem logradouro e sem numero
- **WHEN** o endereco formatado e montado
- **THEN** ele traz apenas cidade e estado, sem virgulas ou separadores soltos

#### Scenario: Conteudo do usuario nao vira marcacao
- **GIVEN** um complemento contendo marcacao
- **WHEN** o endereco e exibido
- **THEN** o texto aparece literalmente, sem ser interpretado

### Requirement: BE-437 — Distancia ate um ponto de referencia
O sistema SHALL calcular a distancia em linha reta entre a coordenada e o ponto de referencia, quando as quatro coordenadas existirem. Fonte legada: `app/models/geolocation.rb:86-104,164-172`; `config/initializers/geocoding.rb:3-4`.

#### Scenario: Coordenada de referencia incompleta
- **GIVEN** uma geolocalizacao sem ponto de referencia completo
- **WHEN** ela e gravada
- **THEN** a distancia fica ausente, em vez de zero

#### Scenario: Distancia calculada
- **GIVEN** as quatro coordenadas presentes
- **WHEN** a distancia e calculada
- **THEN** o valor e a distancia esferica em quilometros — nao distancia rodoviaria

### Requirement: BE-438 — Sigla da unidade federativa
O sistema SHALL converter o nome do estado por extenso na sigla de duas letras, tolerando variacoes de acento e caixa. Fonte legada: `app/models/geolocation.rb:67-76`.

> Nota: corrige a conversao fragil (legado: a comparacao e por **igualdade exata de string** contra a tabela da biblioteca, entao qualquer variacao de acento ou caixa vinda do servico externo **quebra a conversao em silencio**, devolvendo ausencia de sigla).

#### Scenario: Variacao de acentuacao
- **GIVEN** o estado gravado como "Sao Paulo", sem acento
- **WHEN** a sigla e resolvida
- **THEN** o resultado e `SP`

#### Scenario: Estado desconhecido
- **GIVEN** um valor que nao corresponde a nenhuma unidade federativa
- **WHEN** a sigla e resolvida
- **THEN** o resultado e ausencia de sigla e o caso e registrado

### Requirement: BE-439 — Uma geolocalizacao por entidade
O sistema SHALL garantir no banco que cada entidade tenha no maximo uma geolocalizacao. Fonte legada: `app/models/geolocation.rb:3,174-176`; `db/migrate/20160302002809_create_geolocations.rb`.

> Nota: corrige a condicao de corrida (legado: a checagem e **apenas de aplicacao e so na criacao**, sem indice unico no banco — duas gravacoes concorrentes criam duas coordenadas para a mesma entidade).

#### Scenario: Segunda coordenada recusada
- **GIVEN** uma entidade que ja tem geolocalizacao
- **WHEN** outra e inserida para a mesma entidade
- **THEN** o banco recusa por indice unico e a mensagem ao usuario e "Coordenadas ja existentes para essa entidade"

### Requirement: BE-440 — Clonagem de geolocalizacao
O sistema SHALL duplicar as coordenadas e o endereco de uma geolocalizacao para outra entidade, sem reconsultar o servico externo. Fonte legada: `app/models/geolocation.rb:106-130`.

> Nota: corrige a copia manual campo a campo (legado: dois campos sao atribuidos **duas vezes**, sem efeito, e a entidade dona **nao e copiada** — a copia falha na validacao se for gravada sem reassociacao).

#### Scenario: Copia nao consulta o servico externo
- **GIVEN** uma geolocalizacao com endereco preenchido
- **WHEN** ela e clonada e associada a outra entidade
- **THEN** os campos sao copiados integralmente e nenhuma chamada externa e feita

### Requirement: BE-441 — Anexo de imagem polimorfico
O sistema SHALL anexar imagens a qualquer entidade, gerando as variantes de miniatura, previa e original em storage privado. Fonte legada: `app/models/picture.rb:6-18`; `db/migrate/20160124203946_create_pictures.rb`.

> Nota: corrige D-56 e D-82 (legado: a deteccao de spoof de tipo esta **desligada globalmente**, entao a validacao de content-type por expressao regular e contornavel; e os arquivos vao para um diretorio **publico** em disco local, servidos sem autenticacao e sem sobreviver a container efemero).

#### Scenario: Arquivo que se passa por imagem
- **GIVEN** um arquivo cujo content-type declara imagem mas cujo conteudo nao e
- **WHEN** ele e enviado
- **THEN** o envio e rejeitado por validacao de magic bytes no servidor

#### Scenario: Acesso ao arquivo
- **GIVEN** a URL de uma imagem anexada
- **WHEN** um anonimo tenta baixa-la
- **THEN** o acesso e negado; o arquivo e servido por URL assinada com prazo

#### Scenario: Transparencia
- **GIVEN** uma imagem com fundo transparente
- **WHEN** ela e processada
- **THEN** a transparencia e preservada nas variantes — o legado convertia tudo para um formato sem canal alfa, achatando sobre fundo branco

### Requirement: BE-442 — Limites de envio de imagem
O sistema SHALL aplicar limites de quantidade e de tamanho de imagem a partir de **uma unica** configuracao. Fonte legada: `app/models/picture.rb:21-38`; constantes em `SFG::Metadata`.

> Nota: corrige a duplicacao de configuracao (legado: os limites sao perguntados a entidade dona, com um fallback de 5 MB e **sem limite de quantidade** quando ela nao os define, enquanto as constantes de metadados definem os mesmos limites em outro lugar — dois lugares definindo o mesmo). Corrige tambem a checagem de existencia de metodo, que avalia a chamada e estoura quando a entidade dona e nula, e a mensagem de erro com aspas sobrando.

#### Scenario: Limite de tamanho
- **GIVEN** um arquivo acima do tamanho maximo configurado
- **WHEN** ele e enviado
- **THEN** o envio e rejeitado pelo servidor com a mensagem do limite

#### Scenario: Limite de quantidade
- **GIVEN** uma entidade que ja atingiu o numero maximo de imagens
- **WHEN** outra e enviada
- **THEN** o envio e rejeitado

#### Scenario: Entidade sem configuracao propria
- **GIVEN** uma entidade que nao define limites proprios
- **WHEN** uma imagem e enviada
- **THEN** os limites padrao da configuracao unica se aplicam

### Requirement: BE-443 — Dimensoes da imagem anexada
O sistema SHALL registrar largura e altura da imagem anexada e indicar se ela serve para uso em previa de link. Fonte legada: `app/models/picture.rb:3-4,44-75`.

> Nota: corrige um bug confirmado (legado: a checagem de adequacao testa **duas vezes a largura** e nunca a altura, entao uma imagem de 300 por 10 pixels passa como adequada para previa de link) e a gravacao dentro do callback de commit, que dispara um novo ciclo de commit e so nao entra em laco por causa de uma marca de estado.

#### Scenario: Imagem desproporcional
- **GIVEN** uma imagem larga e muito baixa
- **WHEN** a adequacao para previa de link e avaliada
- **THEN** ela e considerada inadequada, porque largura **e** altura sao avaliadas

#### Scenario: Dimensoes calculadas
- **GIVEN** uma imagem recem-enviada
- **WHEN** o processamento conclui
- **THEN** largura, altura e o momento do calculo estao registrados

### Requirement: BE-444 — Clonagem de imagem anexada
O sistema SHALL duplicar uma imagem anexada, com arquivo, dimensoes e descricao, para outra entidade. Fonte legada: `app/models/picture.rb:77-89`.

#### Scenario: Copia completa
- **GIVEN** uma imagem anexada com descricao e dimensoes calculadas
- **WHEN** ela e clonada para outra entidade
- **THEN** o arquivo, a descricao e as dimensoes acompanham a copia

### Requirement: BE-445 — Status de conferencia dos lancamentos
O sistema SHALL representar o status de conferencia dos lancamentos por um valor estavel, independente do texto exibido. Fonte legada: `app/models/entry.rb:1-14`; consumo em `app/models/receivable_entry.rb:115`.

> Nota: corrige a persistencia de texto de interface (legado: os status "Diferenca" e "OK" sao **strings em pt-BR gravadas na coluna** e comparadas por igualdade de texto — qualquer mudanca de rotulo quebra as comparacoes e o historico).

#### Scenario: Status estavel
- **GIVEN** um lancamento com diferenca de conferencia
- **WHEN** o status e gravado e depois lido
- **THEN** o valor persistido e estavel e o rotulo exibido vem da camada de apresentacao

#### Scenario: Migracao dos valores legados
- **GIVEN** registros legados com os textos "Diferenca" e "OK"
- **WHEN** a migracao executa
- **THEN** cada um e convertido no valor estavel correspondente, sem perda

### Requirement: BE-446 — Chave de integracao do tipo de movimentacao
O sistema SHALL gerar a chave de integracao do tipo de movimentacao a partir do titulo na criacao, e mante-la estavel depois. Fonte legada: `app/models/movement_kind.rb:5-7`; `db/migrate/20210317151301_create_movement_kinds.rb`.

> Nota: corrige a ausencia de unicidade (legado: a chave **nao tem unicidade validada nem indice**, entao dois titulos que normalizam igual — por exemplo com e sem acento — geram chave duplicada).

#### Scenario: Chave estavel apos renomear
- **GIVEN** um tipo de movimentacao com chave gerada
- **WHEN** o titulo e alterado
- **THEN** a chave permanece a mesma — ela e o contrato com integracoes

#### Scenario: Chave duplicada
- **GIVEN** um tipo cujo titulo normaliza para uma chave ja existente
- **WHEN** ele e criado
- **THEN** a criacao e recusada com erro de unicidade

### Requirement: BE-447 — Exclusividade de classificacao fiscal do tipo de movimentacao
O sistema SHALL permitir no maximo uma classificacao fiscal por tipo de movimentacao. Fonte legada: `app/models/movement_kind.rb:10-18`.

#### Scenario: Duas classificacoes
- **GIVEN** um tipo marcado ao mesmo tempo como desagio e como IOF
- **WHEN** ele e salvo
- **THEN** a operacao e recusada com a mensagem de multiplos tipos

#### Scenario: Nenhuma classificacao
- **GIVEN** um tipo sem nenhuma classificacao fiscal
- **WHEN** ele e salvo
- **THEN** a operacao e aceita — ausencia de classificacao e valida

### Requirement: BE-448 — Dependencias e vocabulario do tipo de movimentacao
O sistema SHALL impedir a exclusao de tipo de movimentacao com recebiveis ou taxas vinculados, e SHALL representar estado e natureza por valores estaveis. Fonte legada: `app/models/movement_kind.rb:2-3,21-46`.

> Nota: corrige a persistencia de texto de interface (legado: estado e natureza sao **strings em pt-BR** gravadas na coluna, com a natureza indo crua do rotulo para o banco).

#### Scenario: Exclusao bloqueada
- **GIVEN** um tipo de movimentacao com recebiveis vinculados
- **WHEN** a exclusao e tentada
- **THEN** ela e recusada com o motivo e nada e apagado

#### Scenario: Natureza estavel
- **GIVEN** um tipo de natureza credito
- **WHEN** o valor e gravado e depois lido
- **THEN** o valor persistido e estavel e o rotulo exibido vem da camada de apresentacao

### Requirement: BE-449 — Ordenacao dirigida pelo cliente
O sistema SHALL ordenar listagens por campos vindos do cliente apenas a partir de uma allowlist compartilhada. Fonte legada: `app/models/movement_kind.rb:50-78`.

> Nota: corrige o 500 por chave desconhecida (legado: uma chave fora da lista devolve ausencia de valor e, ao ser concatenada, estoura `NoMethodError`; um estilo invalido produz um trecho de SQL com espaco solto) e a repeticao do padrao em varios models, que passa a ser um utilitario unico compartilhado.

#### Scenario: Campo fora da allowlist
- **GIVEN** uma requisicao pedindo ordenacao por um campo desconhecido
- **WHEN** ela e processada
- **THEN** a resposta e 400 e nenhum trecho do parametro chega ao SQL

#### Scenario: Ordenacao por multiplos campos
- **GIVEN** dois campos suportados com sentidos diferentes
- **WHEN** a listagem e ordenada
- **THEN** a ordenacao aplica os dois na ordem informada

### Requirement: BE-450 — Pipeline de importacao do sistema antigo
O comportamento do pipeline de importacao do sistema antigo SHALL ficar documentado, e o pipeline **nao** SHALL ser portado como codigo de aplicacao. Fonte legada: `app/models/legacy.rb:1-48`.

> Nota de escopo (DEC-12): assume-se que o pipeline **nao roda** desde 2021 — a base de origem tem a data no proprio nome. Os modelos de importacao, a segunda conexao de banco e o dump de origem **nao sao portados**. Registrado o comportamento por sua consequencia nos dados historicos: a ordem obrigatoria de doze entidades, o desligamento do log durante a execucao, e o fato de que **erros de validacao eram apenas impressos, sem abortar nem reverter** — nao havia transacao nem idempotencia, entao rodar duas vezes duplicava tudo, exceto usuarios, que faziam busca por e-mail.

#### Scenario: Pipeline ausente do ai9
- **GIVEN** a base de codigo do ai9
- **WHEN** ela e inspecionada
- **THEN** nao existem modelos de importacao do sistema antigo, nem a segunda conexao de banco

#### Scenario: Consequencia nos dados verificada
- **GIVEN** os dados importados pelo pipeline
- **WHEN** a migracao para o ai9 executa o passo de introspecao
- **THEN** duplicatas e registros sem relacao obrigatoria sao reportados no dry-run

### Requirement: BE-451 — Rastreabilidade de origem pelo identificador legado
O sistema SHALL preservar o identificador de origem de cada registro importado. Fonte legada: `app/models/legacy.rb:63-87`; uso em `app/models/legacy/receivable_entry.rb:12-16`, `project.rb:21-23`.

> Nota de escopo (DEC-12): as colunas de identificador legado **sao preservadas** — sao a unica prova de proveniencia dos registros de 2016 a 2021. As funcoes de traducao entre os dois lados nao sao portadas, porque a base de origem nao existe mais no ai9.

#### Scenario: Identificador preservado
- **GIVEN** registros com identificador de origem preenchido
- **WHEN** a migracao para o ai9 conclui
- **THEN** o identificador de origem continua presente e consultavel

### Requirement: BE-452 — Regras costuradas nos adaptadores de importacao
As regras costuradas nos adaptadores de importacao SHALL ficar registradas como origem de anomalias nos dados historicos. Fonte legada: `app/models/legacy/carrier.rb:10-29`, `receivable_entry.rb:10-74`, `project.rb:19-51`.

> Nota: registra tres anomalias que **estao nos dados de producao** e precisam ser tratadas na migracao — (a) autor forcado para um identificador fixo em portadores e recebiveis; (b) empresa forcada para um identificador fixo em recebiveis, "por questao de portabilidade"; (c) o responsavel do projeto caindo em cascata ate um **endereco de e-mail de pessoa real embutido no codigo-fonte** e, por fim, ao primeiro usuario. Registra tambem que o adaptador de projeto **destruia todas as associacoes de membro logo apos cria-las**.

#### Scenario: Anomalias reportadas no dry-run
- **GIVEN** registros historicos com autor ou empresa apontando para o identificador fixo herdado da importacao
- **WHEN** a migracao para o ai9 executa
- **THEN** o dry-run lista quantos registros estao nessa condicao, para decisao antes do cutover

#### Scenario: Nenhum dado pessoal embutido no codigo
- **GIVEN** a base de codigo do ai9
- **WHEN** ela e inspecionada
- **THEN** nao ha endereco de e-mail de pessoa real nem identificador de usuario embutido em codigo

### Requirement: BE-453 — Senhas geradas na importacao de usuarios
As senhas geradas pela importacao de usuarios SHALL ser tratadas como comprometidas. Fonte legada: `app/models/legacy/u.rb:15-42`, em especial `:28`.

> Nota: achado de seguranca do legado — a senha de **todo usuario importado** e derivada do primeiro nome com um sufixo fixo, portanto **previsivel a partir do nome**; e a senha do sistema antigo foi preservada em uma coluna propria. O esquema **nao e portado**. Registrada tambem a precedencia de papel do adaptador, em que a marca de equipe vence a de superusuario — provavelmente invertida.

#### Scenario: Redefinicao obrigatoria
- **GIVEN** usuarios cuja senha veio da importacao
- **WHEN** eles tentam entrar no ai9
- **THEN** a senha herdada nao e aceita e a redefinicao e obrigatoria

#### Scenario: Senha antiga eliminada
- **GIVEN** a coluna que guardava a senha do sistema antigo
- **WHEN** a migracao conclui
- **THEN** ela nao existe no ai9

> AMBIGUIDADE: a precedencia de papel do adaptador dava a marca de equipe prioridade sobre a de superusuario, o que parece invertido e definiu o papel de usuarios que ainda estao ativos. Confirmar com o tech lead antes de reprocessar papeis.

### Requirement: BE-454 — Correcoes pos-importacao
As correcoes aplicadas depois da importacao SHALL ficar registradas, com a ordem em que foram executadas. Fonte legada: `app/models/legacy/{default_project_interceptor,project_responsible_interceptor,membership_interceptor,receivable_entry_calculate_interceptor}.rb`.

> Nota: registra que as quatro correcoes **desligavam o log e devolviam sucesso cego**, nunca sinalizando falha; que a comparacao de papel era por **texto literal**; e que a ultima delas carregava **todos** os recebiveis em memoria e os re-gravava um a um, disparando o recalculo em massa da carteira. Registra tambem que a terceira correcao **sobrescreve** o responsavel definido pela segunda — a ordem importa e nao estava documentada.

#### Scenario: Efeito da ordem documentado
- **GIVEN** projetos cujo responsavel foi definido pela segunda correcao e depois trocado pela terceira
- **WHEN** a migracao para o ai9 executa
- **THEN** o dry-run lista esses projetos, para conferencia do responsavel correto

### Requirement: BE-455 — Validacao de faixa de valores
O sistema SHALL validar que o valor minimo e o valor maximo de uma faixa sao numeros inteiros, distintos e na ordem correta. Fonte legada: `app/validators/interval_validator.rb:1-18`.

> Nota: corrige um validador provavelmente quebrado (legado: a checagem de "e inteiro" **exige que o valor ja seja texto** — um numero vindo do formulario e acusado indevidamente de nao ser inteiro; as comparacoes seguintes misturam texto e numero e estouram quando os tipos divergem; e o validador usa uma API de erros removida no Rails 6.1, portanto tende a levantar excecao na versao de referencia).

#### Scenario: Valores invertidos
- **GIVEN** um minimo maior que o maximo
- **WHEN** a validacao roda
- **THEN** a operacao e recusada com a mensagem correspondente

#### Scenario: Valores iguais
- **GIVEN** minimo e maximo iguais
- **WHEN** a validacao roda
- **THEN** a operacao e recusada

#### Scenario: Valor numerico do formulario
- **GIVEN** um minimo enviado como numero
- **WHEN** a validacao roda
- **THEN** ele e aceito como inteiro valido — sem exigir que seja texto

### Requirement: BE-456 — Validacao de URL
O sistema SHALL validar o formato de uma URL **sem** acessa-la. Fonte legada: `app/validators/uri_validator.rb:1-19`.

> Nota: corrige D-111 (legado: o validador faz **uma requisicao HTTP real** a URL fornecida pelo usuario e so aceita se a resposta for de sucesso — **SSRF**: o servidor pode ser usado para varrer a rede interna ou atingir servicos de metadados de nuvem; alem disso a gravacao fica bloqueada esperando a rede, qualquer falha de DNS ou tempo limite vira "URL invalida", e a chave de mensagem usada **nao existe** no catalogo, o que levanta excecao em ambiente de desenvolvimento).

#### Scenario: URL de rede interna
- **GIVEN** uma URL apontando para um endereco de rede interna ou para um servico de metadados de nuvem
- **WHEN** ela e validada
- **THEN** nenhuma requisicao e feita a esse endereco; a validacao avalia apenas o formato

#### Scenario: URL de formato invalido
- **GIVEN** um valor que nao e uma URL bem formada
- **WHEN** ele e validado
- **THEN** a operacao e recusada com mensagem existente no catalogo de mensagens

#### Scenario: Servico externo fora do ar nao bloqueia a gravacao
- **GIVEN** uma URL valida cujo destino esta indisponivel
- **WHEN** o registro e gravado
- **THEN** a gravacao conclui normalmente

### Requirement: BE-457 — Consulta de dados cadastrais por CNPJ
O sistema SHALL consultar dados cadastrais de empresa por CNPJ em servico externo, com cache e tempo limite, tratando falhas. Fonte legada: `app/helpers/cnpj_api.rb:1-5`; `config/initializers/receitaws.rb:1-15`.

> Nota: corrige o encapsulamento e o tratamento de falha (legado: e um invólucro de uma linha **sem tratamento de erro** — a falha do servico propaga para quem chamou — e vive no diretorio de helpers de view embora seja uma classe de servico). Registrado: o token de acesso vem de variavel de ambiente, o cache e de um ano em relacao a ultima consulta e o tempo limite e de dez segundos.

#### Scenario: Servico indisponivel
- **GIVEN** o servico de consulta fora do ar
- **WHEN** uma consulta e feita
- **THEN** a falha e tratada e comunicada ao chamador de forma previsivel, sem derrubar a operacao em andamento

#### Scenario: Consulta repetida
- **GIVEN** um CNPJ ja consultado recentemente
- **WHEN** a consulta e repetida
- **THEN** o resultado vem do cache, sem nova chamada externa

### Requirement: BE-458 — Filtros globais da area autenticada
A area autenticada SHALL exigir sessao por padrao, expulsar usuario desativado em qualquer formato de requisicao e registrar a personificacao de usuario. Fonte legada: `app/controllers/pub_application_controller.rb:1-84`.

> Nota: corrige D-23 na raiz (legado: a exigencia de sessao devolve **falso por padrao** — o padrao da base e **nao exigir login**, e so os controllers que sobrescrevem o comportamento ficam protegidos; e o usuario desativado so e expulso corretamente no formato JavaScript, entao uma requisicao HTML de usuario desativado cai em erro de formato desconhecido). Corrige tambem a deteccao de dispositivo movel por expressao regular estreita sobre o agente do cliente.

#### Scenario: Padrao e exigir sessao
- **GIVEN** um endpoint novo da area autenticada
- **WHEN** ele e chamado sem sessao
- **THEN** a resposta e 401 — a protecao e o padrao, e a excecao e explicita

#### Scenario: Usuario desativado em requisicao HTML
- **GIVEN** um usuario desativado enquanto navega
- **WHEN** ele faz qualquer requisicao, em qualquer formato
- **THEN** ele e desconectado e recebe a tela de conta bloqueada — sem erro de formato

#### Scenario: Personificacao registrada
- **GIVEN** um administrador personificando outro usuario
- **WHEN** ele realiza qualquer acao
- **THEN** a acao registra tanto o usuario personificado quanto o administrador que a executou

### Requirement: BE-459 — Controllers base de API
Os endpoints de API SHALL autenticar por token de aplicacao cliente, e os endpoints privados SHALL aceitar token de aplicacao **ou** sessao de usuario. Fonte legada: `app/controllers/api_application_controller.rb:1-22`; `app/controllers/api_private_application_controller.rb:1-22`.

> Nota: corrige a duplicacao e o gate fragil (legado: os dois controllers base sao **identicos byte a byte**, a resolucao da aplicacao cliente pode devolver ausencia **sem bloquear a requisicao** — o bloqueio real fica na superclasse do engine — e todos os helpers de view sao expostos as respostas de API). Corrige tambem a traducao manual de chaves de erro, marcada no proprio codigo como provisoria ate a instalacao de internacionalizacao.

#### Scenario: Token invalido
- **GIVEN** uma requisicao de API com token de aplicacao invalido
- **WHEN** ela e processada
- **THEN** a resposta e 401 e nenhum handler e executado

#### Scenario: Endpoint privado por sessao
- **GIVEN** uma requisicao a endpoint privado com sessao valida e sem token de aplicacao
- **WHEN** ela e processada
- **THEN** ela e aceita

### Requirement: FE-430 — Tempo relativo em pt-BR
A interface SHALL exibir tempo relativo em pt-BR, distinguindo passado de futuro. Fonte legada: `app/helpers/application_helper.rb:2-9`.

> Nota: corrige a supressao do sufixo em datas futuras (legado: datas futuras perdem o prefixo e sao renderizadas como se fossem uma duracao solta — "em 3 dias" vira "3 dias" — e datas passadas tem a palavra de aproximacao removida do texto).

#### Scenario: Data futura
- **GIVEN** uma data tres dias a frente
- **WHEN** ela e exibida como tempo relativo
- **THEN** o texto indica que e no futuro

#### Scenario: Data passada
- **GIVEN** uma data duas horas atras
- **WHEN** ela e exibida como tempo relativo
- **THEN** o texto indica que e no passado

### Requirement: FE-431 — Formatacao de valor monetario
A interface SHALL formatar valores monetarios em reais e **distinguir valor ausente de valor zero**. Fonte legada: `app/helpers/application_helper.rb:11-13`.

> Nota: corrige D-117 (legado: valor em branco ou nulo e renderizado como **R$ 0,00** — num sistema financeiro, campo nulo e campo zerado ficam **indistinguiveis**). Corrige tambem a duplicacao da definicao de moeda, que existia no helper e no inicializador de tipos.

#### Scenario: Valor ausente
- **GIVEN** um campo monetario nulo ou em branco
- **WHEN** ele e exibido
- **THEN** a interface mostra ausencia de valor, e nao zero

#### Scenario: Valor zero
- **GIVEN** um campo monetario com valor zero
- **WHEN** ele e exibido
- **THEN** a interface mostra zero, visualmente distinto da ausencia

#### Scenario: Formato brasileiro
- **GIVEN** o valor mil duzentos e trinta e quatro reais e cinquenta e seis centavos
- **WHEN** ele e exibido
- **THEN** o separador decimal e a virgula e o separador de milhar e o ponto

### Requirement: FE-432 — Concordancia de genero em textos
A interface SHALL concordar em genero nos textos dirigidos ao usuario, com neutro seguro quando o genero nao e conhecido. Fonte legada: `app/helpers/application_helper.rb:15-20`.

> Nota: corrige a suposicao de masculino (legado: qualquer valor desconhecido, inclusive ausencia de informacao, cai em masculino) e o erro por perfil ausente (legado: o helper estoura se o usuario nao tem perfil).

#### Scenario: Genero desconhecido
- **GIVEN** um usuario sem genero informado
- **WHEN** um texto dirigido a ele e exibido
- **THEN** o texto usa uma formulacao neutra, sem assumir masculino

#### Scenario: Usuario sem perfil
- **GIVEN** um usuario sem perfil associado
- **WHEN** o texto e montado
- **THEN** ele e exibido em formulacao neutra, sem erro

> AMBIGUIDADE: o mapeamento numerico do legado — um para feminino, dois para neutro, qualquer outro para masculino — precisa ser confirmado contra a capability de usuarios antes da migracao de dados.

### Requirement: FE-433 — Iniciais para avatar
A interface SHALL derivar iniciais do nome para o avatar quando nao ha foto. Fonte legada: `app/helpers/application_helper.rb:23-37`.

> Nota: corrige a duplicacao (o proprio legado marca o helper como duplicado de um componente do kit de interface). No ai9 essa logica existe em **um** lugar, na biblioteca de componentes.

#### Scenario: Nome com uma palavra
- **GIVEN** o nome "Ana"
- **WHEN** as iniciais sao geradas
- **THEN** o resultado tem duas letras maiusculas derivadas dessa palavra

#### Scenario: Nome com varias palavras
- **GIVEN** o nome "Ana Maria da Silva"
- **WHEN** as iniciais sao geradas
- **THEN** o resultado usa a primeira letra das duas primeiras palavras

#### Scenario: Nome ausente
- **GIVEN** um nome vazio
- **WHEN** as iniciais sao geradas
- **THEN** o resultado e um marcador neutro

### Requirement: FE-434 — Nome abreviado
A interface SHALL abreviar nomes longos para primeiro e ultimo nome. Fonte legada: `app/helpers/application_helper.rb:39-46`.

#### Scenario: Nome composto
- **GIVEN** o nome "Ana Maria da Silva Souza"
- **WHEN** ele e abreviado
- **THEN** o resultado e "Ana Souza"

#### Scenario: Nome de uma palavra
- **GIVEN** o nome "Ana"
- **WHEN** ele e abreviado
- **THEN** o resultado e "Ana"

### Requirement: FE-435 — Cor de identificacao de entidade
A interface SHALL atribuir a cada entidade sem cor propria uma cor **deterministica**, derivada da sua identidade, a partir de uma unica paleta. Fonte legada: `app/helpers/application_helper.rb:49-53`; usos em `app/models/project.rb:65`, `app/decorators/models/user_decorator.rb:6`, `app/models/renegotiation_installment.rb:108`, `app/decorators/models/livetat_auth_client_application_decorator.rb:23`.

> Nota: corrige a inconsistencia visual (legado: a cor e **aleatoria**, com **cinco combinacoes diferentes** de saturacao e luminosidade convivendo entre helper, projeto, usuario, aplicacao cliente, parcela de renegociacao e o engine de feedback; em alguns lugares a cor e persistida, em outros e volatil e muda a cada renderizacao).

#### Scenario: Cor estavel entre renderizacoes
- **GIVEN** uma entidade sem cor propria
- **WHEN** ela e renderizada duas vezes
- **THEN** a cor e a mesma nas duas

#### Scenario: Paleta unica
- **GIVEN** entidades de tipos diferentes exibidas na mesma tela
- **WHEN** suas cores de identificacao sao geradas
- **THEN** todas vem da mesma paleta, com contraste adequado nos dois modos de tema

### Requirement: FE-436 — Lista de meses
A interface SHALL oferecer os doze meses em pt-BR para selecao. Fonte legada: `app/helpers/application_helper.rb:55-63`.

#### Scenario: Meses em pt-BR
- **GIVEN** um seletor de mes
- **WHEN** ele e renderizado
- **THEN** os doze meses aparecem em pt-BR, com o valor correspondente de um a doze

### Requirement: FE-437 — Janela de anos
A interface SHALL oferecer uma janela de anos centrada no ano corrente. Fonte legada: `app/helpers/application_helper.rb:65-69`.

#### Scenario: Faixa da janela
- **GIVEN** um seletor de ano
- **WHEN** ele e renderizado
- **THEN** a faixa vai de cinco anos antes ate cinco anos depois do ano corrente, com o ano corrente selecionado

### Requirement: FE-438 — Pluralizacao de textos
A interface SHALL pluralizar corretamente as palavras em portugues, inclusive plurais irregulares. Fonte legada: `app/helpers/application_helper.rb:71-74`.

> Nota: corrige D-117 (legado: a regra e acrescentar a letra "s" para qualquer contagem diferente de um, inclusive zero — o que gera "mess" para mes e "papels" para papel).

#### Scenario: Plural irregular
- **GIVEN** a contagem tres e a palavra "mes"
- **WHEN** o texto e montado
- **THEN** o resultado e "3 meses"

#### Scenario: Contagem zero
- **GIVEN** a contagem zero
- **WHEN** o texto e montado
- **THEN** o plural e usado corretamente

### Requirement: FE-439 — Distribuicao de itens em colunas
A interface SHALL distribuir itens em colunas preservando a ordem de leitura. Fonte legada: `app/helpers/application_helper.rb:76-88`.

> Nota: corrige D-117 (legado: a distribuicao e **circular**, item a item entre as colunas, e nao sequencial — o que muda a ordem de leitura percebida; e o filtro opcional aplicado durante a distribuicao **desbalanceia** as colunas).

#### Scenario: Ordem de leitura
- **GIVEN** doze itens distribuidos em tres colunas
- **WHEN** o usuario le a tela
- **THEN** a ordem percebida corresponde a ordem da colecao

#### Scenario: Colunas equilibradas com filtro
- **GIVEN** uma colecao em que parte dos itens e filtrada
- **WHEN** a distribuicao acontece
- **THEN** as colunas ficam equilibradas em relacao aos itens efetivamente exibidos

### Requirement: FE-440 — Formato de data na fronteira com o calendario
A interface SHALL trocar datas com o componente de calendario em formato nao ambiguo. Fonte legada: `app/helpers/application_helper.rb:90-98`.

> Nota: corrige D-117 (legado: a lista de datas e emitida em **mes/dia/ano, formato americano**, enquanto toda a interface exibe dia/mes/ano — armadilha classica em que inverter o formato **quebra o calendario em silencio**, sem erro visivel).

#### Scenario: Data ambigua
- **GIVEN** o dia 3 de fevereiro
- **WHEN** ele e enviado ao calendario e devolvido
- **THEN** ele continua sendo 3 de fevereiro, e nao 2 de marco — o formato de troca e ISO-8601

### Requirement: FE-441 — Navegacao principal por papel e permissao
A navegacao principal SHALL ser montada a partir de configuracao declarativa de rotas e permissoes, com grupos que so aparecem quando tem conteudo. Fonte legada: `app/helpers/application_helper.rb:100-172`.

> Nota: corrige D-118 e D-90 (legado: o helper de montagem do menu **e a especificacao de fato da navegacao**, escondida em codigo — seis grupos com portao por projeto, por papel e por permissao; o cabecalho do grupo de projeto e adicionado **fora do portao**, entao usuario sem projeto ve um grupo **vazio**; a contagem de projetos e feita **duas vezes** por renderizacao; e ha itens comentados no meio do codigo). Corrige tambem o portao de bloqueio: no legado ele le a marca no **grupo** enquanto ela e definida nos **itens**, entao as quatro areas que deveriam estar bloqueadas — painel de disponibilidade, cobrancas, disponibilidades e padroes de disponibilidade — estao **destravadas**.

#### Scenario: Usuario sem projeto
- **GIVEN** um usuario que nao participa de nenhum projeto
- **WHEN** ele abre a navegacao
- **THEN** os grupos que dependem de projeto nao aparecem — nem os itens nem os cabecalhos vazios

#### Scenario: Areas bloqueadas
- **GIVEN** as areas marcadas como bloqueadas na configuracao
- **WHEN** um usuario abre a navegacao
- **THEN** elas aparecem sinalizadas como indisponiveis e o acesso direto pela rota tambem e recusado

#### Scenario: Portao por papel
- **GIVEN** um usuario sem papel administrativo
- **WHEN** ele abre a navegacao
- **THEN** os grupos de cadastro e de administracao nao aparecem, e chamar as rotas correspondentes responde 403

#### Scenario: Custo de montagem
- **GIVEN** a navegacao sendo montada
- **WHEN** a pagina e renderizada
- **THEN** a contagem de projetos do usuario e resolvida uma unica vez

### Requirement: FE-442 — Nome do dia da semana
A interface SHALL exibir o nome do dia da semana em pt-BR, sem sufixo duplicado. Fonte legada: `app/helpers/application_helper.rb:174-180`.

> Nota: corrige D-117 (legado: o helper acrescenta o sufixo "-feira" aos dias uteis, mas o catalogo de traducoes **ja traz** o nome completo — o resultado e "Segunda-feira-feira"; e o indice recebe modulo sete, aceitando qualquer inteiro em silencio).

#### Scenario: Dia util
- **GIVEN** o indice da segunda-feira
- **WHEN** o nome e exibido
- **THEN** o resultado e "Segunda-feira", uma unica vez

#### Scenario: Indice fora da faixa
- **GIVEN** um indice fora da faixa de zero a seis
- **WHEN** o nome e pedido
- **THEN** o pedido e recusado com erro, em vez de devolver um dia arbitrario

### Requirement: FE-443 — Aparencia do item de trilha
Cada item da trilha SHALL ter cor e icone correspondentes ao tipo do evento. Fonte legada: `app/helpers/application_helper.rb:182-190`; consumo em `app/views/api/v1/trackings/widgets/_widget.html.erb:3`.

> Nota: corrige D-117 (legado: as duas funcoes **recebem o evento e o ignoram** — a cor e sempre a cor de destaque da marca e o icone e sempre o mesmo; a assinatura revela a intencao de variar por tipo, nunca implementada; hoje so existe um tipo de evento).

#### Scenario: Tipo conhecido
- **GIVEN** um evento de trilha de um tipo conhecido
- **WHEN** ele e renderizado
- **THEN** a cor e o icone correspondem ao tipo

#### Scenario: Tipo desconhecido
- **GIVEN** um evento de um tipo sem mapeamento
- **WHEN** ele e renderizado
- **THEN** cor e icone neutros sao usados, sem erro

### Requirement: FE-444 — Chave de recurso do auto-cadastro publico
O auto-cadastro publico SHALL ser controlado por configuracao de ambiente. Fonte legada: `app/helpers/application_helper.rb:192-194`; valor em `SFG::Metadata::PUBLIC_CREATE_USER`.

> Nota: corrige a chave embutida no codigo (legado: e uma **constante de codigo**, nao configuracao — mudar exige alterar e reimplantar; e **esta ligada** em producao, ou seja, o auto-cadastro publico esta habilitado hoje).

#### Scenario: Auto-cadastro desligado
- **GIVEN** a configuracao com auto-cadastro publico desligado
- **WHEN** a tela publica e aberta
- **THEN** o acesso ao cadastro nao aparece e a rota de cadastro publico e recusada pelo servidor

#### Scenario: Auto-cadastro ligado
- **GIVEN** a configuracao com auto-cadastro publico ligado
- **WHEN** a tela publica e aberta
- **THEN** o acesso ao cadastro aparece

### Requirement: FE-445 — Item da linha do tempo de atividade
A linha do tempo SHALL exibir cada evento com icone, autor, resumo e tempo relativo. Fonte legada: `app/views/api/v1/trackings/widgets/_widget.html.erb:1-13`; `collection/body.js.erb:1-17`.

> Nota: corrige o padrao de injecao (legado: o parametro de destino, **controlado pelo cliente**, e interpolado direto num seletor dentro do JavaScript renderizado no servidor — o mesmo padrao se repete em toda a aplicacao; no ai9 a linha do tempo e um componente e nao ha HTML gerado dentro de JavaScript). Registra tambem que um dos parciais renderizados e um **arquivo vazio**.

#### Scenario: Parametro hostil nao vira codigo
- **GIVEN** um parametro de destino contendo aspas e marcacao
- **WHEN** a linha do tempo e renderizada
- **THEN** nada e executado e o parametro e tratado como dado

#### Scenario: Lista vazia
- **GIVEN** nenhum evento para o filtro atual
- **WHEN** a linha do tempo e renderizada
- **THEN** um estado vazio explicito e exibido

### Requirement: FE-446 — Representacao do evento de trilha nas respostas
As respostas de trilha SHALL expor apenas os dados necessarios do autor e do destinatario. Fonte legada: `app/views/api/v1/trackings/{index,show}.json.jbuilder`, `_show.json.jbuilder:1-21`.

> Nota: corrige o vazamento de dados pessoais (legado: cada item da lista carrega **o registro de usuario inteiro** do autor — combinado com o endpoint sem escopo de BE-432, isso expoe a base de usuarios).

#### Scenario: Dados minimos do autor
- **GIVEN** uma lista de eventos de trilha
- **WHEN** ela e retornada
- **THEN** cada item traz do autor apenas identificador, nome de exibicao e avatar — nenhum outro dado pessoal

#### Scenario: Destinatario opcional
- **GIVEN** um evento sem destinatario
- **WHEN** ele e retornado
- **THEN** o bloco de destinatario e omitido

### Requirement: DB-430 — Modelo de dados da trilha
A tabela de trilha SHALL guardar autor, destinatario, objeto, pai do objeto, tipo e resumo, com indices para as consultas de listagem e politica de retencao. Fonte legada: `db/migrate/20180724162731_create_trackings.rb:3-17`; `app/models/tracking.rb`.

> Nota: corrige o modelo (legado: **nenhum indice foi criado** — nem no objeto, nem no pai do objeto, nem no grupo de destino, nem na data — exatamente as colunas por que a consulta filtra e ordena; o resumo e uma coluna de texto curto enquanto a validacao permite mais caracteres, com risco de truncamento; e existe uma coluna de tipo que **nunca e usada** e colide com o mecanismo de heranca do ORM).

#### Scenario: Consulta indexada
- **GIVEN** milhoes de eventos de trilha
- **WHEN** a lista de um objeto e consultada
- **THEN** a consulta usa indice e responde em tempo constante em relacao ao tamanho da tabela

#### Scenario: Coluna sem uso removida
- **GIVEN** o esquema do ai9
- **WHEN** ele e inspecionado
- **THEN** nao existe a coluna de tipo herdada que colidia com o mecanismo de heranca

### Requirement: DB-431 — Modelo de dados de geolocalizacao
A tabela de geolocalizacao SHALL guardar coordenadas, ponto de referencia, distancia e campos de endereco, com indice unico por entidade. Fonte legada: `db/migrate/20160302002809_create_geolocations.rb:3-38`.

> Nota: corrige o modelo (legado: **sem indice unico** apesar da regra de uma coordenada por entidade; o campo de preenchimento automatico tem valor padrao zero no banco enquanto o codigo forca um quando nulo — divergencia de padrao; e o numero do endereco e inteiro, o que **perde** valores como "123-A" e "S/N").

#### Scenario: Numero de endereco nao numerico
- **GIVEN** um endereco cujo numero e "123-A"
- **WHEN** ele e gravado
- **THEN** o valor e preservado integralmente

#### Scenario: Padrao unico de preenchimento automatico
- **GIVEN** uma geolocalizacao criada sem a marca de preenchimento automatico
- **WHEN** ela e gravada
- **THEN** o valor aplicado e o mesmo definido no banco e no codigo

### Requirement: DB-432 — Modelo de dados de imagem anexada
A tabela de imagens SHALL guardar a entidade dona, a referencia do arquivo, a descricao e as dimensoes, com os arquivos em storage do ai9. Fonte legada: `db/migrate/20160124203946_create_pictures.rb:3-13`.

> Nota: a biblioteca de anexos do legado esta **descontinuada**; a migracao exige mover os arquivos do diretorio publico do servidor e reescrever as URLs, mapeando o layout de caminho do legado um para um. Registrado que a contagem em cache exige uma coluna dedicada em **cada** tabela dona.

#### Scenario: Arquivos migrados
- **GIVEN** imagens no diretorio publico do legado
- **WHEN** a migracao executa
- **THEN** cada arquivo e suas variantes existem no storage do ai9 e as referencias apontam para os novos caminhos

#### Scenario: Arquivo ausente na origem
- **GIVEN** um registro de imagem cujo arquivo nao existe no disco de origem
- **WHEN** a migracao executa
- **THEN** o dry-run reporta o registro orfao antes do cutover

### Requirement: DB-433 — Modelo de dados do tipo de movimentacao
A tabela de tipos de movimentacao SHALL guardar titulo, chave de integracao, natureza, estado e classificacoes fiscais, com tipos adequados e indices. Fonte legada: `db/migrate/20210317151301_create_movement_kinds.rb:3-17`.

> Nota: corrige o modelo (legado: os campos logicos sao **inteiros zero ou um**, padrao do legado inteiro; a natureza guarda **texto em pt-BR**; a chave de integracao nao tem indice unico; e a tabela nao declara indice algum).

#### Scenario: Campos logicos
- **GIVEN** o esquema do ai9
- **WHEN** ele e inspecionado
- **THEN** os campos logicos sao booleanos, nao inteiros

#### Scenario: Migracao de valores fora de zero e um
- **GIVEN** registros legados com valores fora de zero e um em campos logicos
- **WHEN** a migracao executa
- **THEN** o dry-run os reporta antes da conversao

### Requirement: DB-434 — Conexao com o banco do sistema antigo
O sistema SHALL **nao** manter conexao com o banco do sistema antigo. Fonte legada: blocos de conexao secundaria em `config/database.*.yml`; uso em `app/models/legacy/*.rb`.

> Nota de escopo (DEC-12): a aplicacao legada mantem **duas conexoes de banco abertas em producao**, sendo a segunda a base historica do cliente, com tabelas de nomenclatura em portugues. Essa conexao **nao e portada**. Registrado ainda que a senha dessa conexao esta **commitada em texto puro** nos arquivos de exemplo de configuracao do legado — credencial a ser considerada comprometida e rotacionada.

#### Scenario: Uma unica conexao
- **GIVEN** a configuracao de banco do ai9
- **WHEN** ela e inspecionada
- **THEN** existe uma unica conexao, e nenhuma credencial esta versionada em texto puro

#### Scenario: Rastreabilidade sem a conexao
- **GIVEN** registros importados do sistema antigo
- **WHEN** a proveniencia e consultada
- **THEN** ela e resolvida pelo identificador de origem preservado (BE-451), sem depender da base antiga

### Requirement: OPS-746 — Shims de vendor do empacotador
O sistema SHALL substituir os shims de vendor do empacotador legado — arquivos que apenas reexportam pacotes locais e de npm como variaveis globais — por importacao explicita de modulo, e SHALL **nao** reproduzir a varredura de diretorio que inclui no bundle qualquer arquivo solto. Fonte legada: `app/frontend/vendor/js/dragula_wrapper.js:1-2`; `lvt-dialog.js:1-2`; `lvt-doughnut.js:1-3`; `rails-action-text.js:1-2`; `engines/navkit/app/frontend/css/init.js:1`; `engines/auth_ux19/app/assets/javascripts/livetat/auth_ux19/application.js`; `engines/mailer19/app/assets/javascripts/livetat/mailer19/application.js`; agregacao em `app/frontend/vendor/js/index.js.erb:22-31`.

- O que os shims fazem hoje: expor `global.dragula`, `global.Dialog` (aponta para `vendor/dialog`, ver FE-743), `global.Doughnut` (aponta para `vendor/doughnut`, ver FE-744) e importar `trix` mais `@rails/actiontext`.
- `index.js.erb:22-25` faz `Dir.glob` de **todo** `app/frontend/vendor/js/**/*.js` em tempo de compilacao: qualquer arquivo deixado nessa pasta entra no bundle final sem ninguem pedir. Isso SHALL deixar de existir — o grafo de dependencia do ai9 e explicito.
- `trix` e `@rails/actiontext` sao importados mas **nenhuma view do legado os usa** (ver DB-737): sao descarte com evidencia, nao portados.
- Os dois componentes proprietarios expostos por shim (`dialog` e `doughnut`) sao substituidos pelos equivalentes da base ai9, e nao portados 1:1.

> Nota de escopo (DEC-10): grafico e dialogo passam a usar as bibliotecas do ai9. O `frontend-engineer` mostra o resultado visual antes de fechar o slice, porque o grafico e o unico elemento de visualizacao do produto.

#### Scenario: Dependencia resolvida por importacao
- **GIVEN** um componente do ai9 que precisa da biblioteca de arrastar e soltar
- **WHEN** o modulo e construido
- **THEN** a dependencia e importada pelo proprio modulo, e nenhuma variavel global e criada para atende-lo

#### Scenario: Arquivo solto na pasta de vendor
- **GIVEN** um arquivo JavaScript deixado numa pasta de terceiros sem ser referenciado
- **WHEN** o bundle e gerado
- **THEN** ele nao entra no resultado, ao contrario da varredura de diretorio do legado

#### Scenario: Bibliotecas sem consumidor
- **GIVEN** as bibliotecas de editor de texto rico importadas pelo legado
- **WHEN** o escopo do frontend do ai9 e fechado
- **THEN** elas nao estao presentes, com a evidencia de zero uso em views registrada
