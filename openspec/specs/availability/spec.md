# Availability Specification

## Purpose
Disponibilidade e o modulo de lancamento e consolidacao de valores diarios do projeto:
uma arvore de ate tres niveis de padroes (globais e especificos do projeto) sobre a
qual o usuario lanca valores por empresa e por data, com totais consolidados, saldo
acumulado, correcao por dias uteis e consolidacao geral do projeto.
Cobre os IDs 120–149 do inventario (`.migration-ai9/feature-inventory.md`).

## Requirements

### Requirement: BE-120 — Busca de lancamentos de disponibilidade de uma data
O sistema DEVE (SHALL) devolver os lancamentos de disponibilidade de um projeto, empresa e data, na ordem hierarquica dos padroes, com busca textual e paginacao efetivas. Fonte legada: `config/routes.rb:67`; `app/controllers/pub/availability_entries_controller.rb:9-25`; `app/models/project.rb:212-234`.

#### Scenario: Data nao informada
- **GIVEN** um projeto e uma empresa selecionados sem data
- **WHEN** a consulta e feita
- **THEN** a resposta e vazia e a tela orienta a selecionar uma data

#### Scenario: Busca e paginacao aplicadas
- **GIVEN** um projeto com 300 padroes ativos numa data
- **WHEN** o cliente consulta com `l=50`, `o=50`
- **THEN** sao devolvidos 50 itens a partir do 51o, respeitando a ordem hierarquica

> Nota: corrige D-07/D-20 (legado: `q`, `l` e `o` eram lidos mas **nunca aplicados** — nao havia filtro textual nem paginacao real de lancamentos). Muda o que a tela faz: hoje ela traz tudo.

#### Scenario: Empresa inexistente no filtro
- **GIVEN** uma consulta com um identificador de empresa que nao existe no projeto
- **WHEN** ela e processada
- **THEN** a resposta e 422 informando o filtro invalido

> Nota: corrige o legado, onde `company_id` invalido resultava em `@company = nil` e a consulta caia silenciosamente no modo "consolidacao geral", devolvendo numeros de outra visao.

#### Scenario: Projeto inexistente
- **GIVEN** um identificador de projeto que nao existe ou do qual o usuario nao e membro
- **WHEN** a consulta e feita
- **THEN** a resposta e 404 ou 403, sem erro interno

#### Scenario: Montagem da grade em projeto grande
- **GIVEN** um projeto com centenas de padroes ativos
- **WHEN** a grade de uma data e montada
- **THEN** a montagem ocorre em consultas agregadas, dentro do limite de performance definido

> Nota: corrige o N+1 do legado (uma consulta por padrao em `ordered_availability_templates`).

### Requirement: BE-121 — Acesso a tela de lancamentos
A tela de lancamentos de disponibilidade DEVE (SHALL) ser alcancavel por um unico caminho. Fonte legada: `app/controllers/pub/availability_entries_controller.rb:5-7`; `config/routes.rb:68`.

#### Scenario: Abrir o painel de disponibilidade
- **GIVEN** um usuario autenticado com projeto corrente
- **WHEN** ele abre o painel de disponibilidade
- **THEN** a tela carrega os filtros e a grade de lancamentos

> AMBIGUIDADE: no legado a rota `index` do controller de lancamentos parece vestigial — a tela real e servida pelo console (`/console/availability`). Confirmar se algo externo ainda alcanca `pub/availability_entries/index` antes de descarta-la (DEC-09: descartar so com evidencia).

### Requirement: BE-122 — Criar lancamento de disponibilidade
O sistema DEVE (SHALL) criar um lancamento de disponibilidade para um padrao, empresa e data, disparando o recalculo da hierarquia e da consolidacao, e DEVE (SHALL) recusar duplicidade. Fonte legada: `app/controllers/pub/availability_entries_controller.rb:28-39`, `:88-98`; `app/models/availability_entry.rb:7-12`.

#### Scenario: Lancamento duplicado
- **GIVEN** um lancamento ja existente para o mesmo projeto, empresa, padrao e data
- **WHEN** outro e criado com os mesmos dados
- **THEN** a resposta e 422 com a mensagem em pt-BR e nenhum registro duplicado e criado

#### Scenario: Lancamento valido
- **GIVEN** uma celula ainda sem lancamento
- **WHEN** o usuario digita um valor e salva
- **THEN** o lancamento e criado e os totais dos niveis superiores e a consolidacao geral refletem o novo valor

#### Scenario: Falha de validacao nao deixa residuo
- **GIVEN** um lancamento sem padrao informado
- **WHEN** a criacao e submetida
- **THEN** a resposta e 422 e nenhum registro parcial permanece

> Nota: corrige o codigo de compensacao fragil do legado (`@availability_entry.destroy` sobre registro nao persistido).

### Requirement: BE-123 — Atualizar lancamento de disponibilidade
O sistema DEVE (SHALL) atualizar o valor de um lancamento em uma unica gravacao, recusando alteracao em lancamento de consolidacao geral e em padrao bloqueado por operacao em andamento. Fonte legada: `app/controllers/pub/availability_entries_controller.rb:41-54`.

#### Scenario: Gravacao unica
- **GIVEN** um lancamento de um padrao corrigido por dias uteis
- **WHEN** o usuario altera o valor uma vez
- **THEN** o valor gravado corresponde a uma unica aplicacao da regra de correcao

> Nota: corrige a dupla gravacao do legado (`update` seguido de `save`, `:42`/`:44`), que reexecutava `before_validation`/`after_save` inteiros e era o gatilho do decaimento composto descrito em BE-127.

#### Scenario: Lancamento de consolidacao geral
- **GIVEN** um lancamento de consolidacao geral (sem empresa)
- **WHEN** um cliente envia diretamente uma atualizacao de valor para ele
- **THEN** a resposta e 422 e o valor consolidado continua sendo derivado das empresas

> Nota: corrige o legado, onde o bloqueio existia **apenas na interface** (FE-132) e um envio direto gravava um valor que seria sobrescrito no proximo recalculo.

#### Scenario: Padrao bloqueado por operacao em andamento
- **GIVEN** um padrao bloqueado por uma ativacao, desativacao ou remocao em andamento
- **WHEN** o usuario tenta alterar um lancamento desse padrao
- **THEN** a resposta e 409 informando a operacao em andamento

> Nota: corrige o legado, que nao checava `is_locked` no update.

### Requirement: BE-124 — Excluir lancamento de disponibilidade
O sistema DEVE (SHALL) excluir um lancamento e reconsolidar os totais dos niveis superiores e da consolidacao geral, sem criar registros como efeito colateral da exclusao. Fonte legada: `app/controllers/pub/availability_entries_controller.rb:57-70`; `app/models/availability_entry.rb:105-126`.

#### Scenario: Exclusao reconsolida sem criar registro
- **GIVEN** um lancamento em um padrao de terceiro nivel
- **WHEN** o usuario o exclui
- **THEN** o lancamento some, os totais dos niveis superiores e da consolidacao geral sao recalculados e nenhum lancamento novo e criado no processo

> Nota: corrige o legado, onde `parent_entry` era chamado **antes** do destroy e **criava** o lancamento-pai quando ele nao existia — excluir podia criar registro.

#### Scenario: Exclusao de lancamento de primeiro nivel
- **GIVEN** um lancamento em um padrao de primeiro nivel, que nao tem pai
- **WHEN** o usuario o exclui
- **THEN** o lancamento some e a consolidacao geral e o saldo acumulado dos demais itens de primeiro nivel sao recalculados

> AMBIGUIDADE: no legado, sem `parent_template_id`, `parent_entry` montava um lancamento com padrao nulo cujo `save` falhava em silencio, e nada era recalculado — o proprio codigo tem um `TODO #7408` admitindo que o comportamento no cenario multi-empresa nao foi fechado. Confirmar qual e a reconsolidacao correta neste caso.

### Requirement: BE-125 — Consolidacao geral do projeto (mirror)
O sistema DEVE (SHALL) manter, para cada padrao e data, um valor de consolidacao geral do projeto derivado dos lancamentos das empresas. Fonte legada: `app/models/availability_entry.rb:40-78`, `:186-223`.

#### Scenario: Consolidacao acompanha as empresas
- **GIVEN** duas empresas com lancamentos no mesmo padrao e data
- **WHEN** o valor de uma delas e alterado
- **THEN** o valor da consolidacao geral daquele padrao e data reflete a alteracao

#### Scenario: Projeto sem empresas
- **GIVEN** um projeto sem nenhuma empresa
- **WHEN** a consolidacao geral e consultada
- **THEN** os valores consolidados sao zero, sem erro

#### Scenario: Consolidacao de itens nao cumulativos e de debito
- **GIVEN** um padrao marcado como nao cumulativo, ou como debito, com lancamentos em duas empresas
- **WHEN** a consolidacao geral e calculada
- **THEN** o valor consolidado segue a regra definida para cumulatividade e sinal

> AMBIGUIDADE: D-08 — no legado a consolidacao geral e uma **soma bruta** que ignora `is_cumulative` e `is_debit`, divergindo da regra aplicada a nos com filhos (BE-126); e o sinal de debito so e aplicado em folhas, nunca em subtotais. Isso muda numero exibido ao cliente. Precisa de decisao do tech lead.

### Requirement: BE-126 — Valor de um padrao com filhos
O sistema DEVE (SHALL) calcular o valor de um padrao que tem filhos a partir dos filhos ativos, aplicando cumulatividade e sinal por tipo de operacao. Fonte legada: `app/models/availability_entry.rb:80-91`, `:190-192`; `app/models/availability_template.rb:73-87`.

#### Scenario: Filho nao cumulativo
- **GIVEN** um padrao-pai com dois filhos, um deles marcado como nao cumulativo
- **WHEN** o total do pai e calculado
- **THEN** o filho nao cumulativo contribui com zero para o total

#### Scenario: Filho de debito
- **GIVEN** um padrao-pai com um filho folha de credito e um filho folha de debito
- **WHEN** o total do pai e calculado
- **THEN** o filho de debito entra com sinal negativo e o de credito com sinal positivo

#### Scenario: No intermediario marcado como debito
- **GIVEN** um padrao intermediario marcado como debito, com filhos proprios
- **WHEN** o total do avo e calculado
- **THEN** o sinal aplicado ao subtotal desse intermediario segue a regra definida

> AMBIGUIDADE: D-08 — no legado o sinal de debito e aplicado **apenas no nivel folha**; um no intermediario marcado como Debito nao inverte o proprio subtotal. Alem disso, `is_credit?`/`is_debit?` comparam a string traduzida em vez do codigo `C`/`D`, entao qualquer `operation_type` fora de `C`/`D`/`S`/`M` e tratado como credito. Esta em producao e muda numero exibido ao cliente.

#### Scenario: Filho de padrao bloqueado
- **GIVEN** um padrao filho bloqueado por operacao em andamento
- **WHEN** o total do pai e calculado
- **THEN** a participacao desse filho segue a regra definida, de forma consistente com o que a tela apresenta

> AMBIGUIDADE: no legado o calculo usa `ignore_lock_active_child_templates`, que filtra por `is_active = 1` **ignorando** `is_locked` — filhos bloqueados por job continuam entrando na conta enquanto a tela os apresenta como indisponiveis.

### Requirement: BE-127 — Correcao por dias uteis
Para padroes marcados como corrigidos, o sistema DEVE (SHALL) interpretar o valor digitado como total do mes e gravar o valor proporcional aos dias uteis decorridos ate a data do lancamento, preservando o valor originalmente digitado. Fonte legada: `app/models/availability_entry.rb:16-23`, `:93-99`, `:193`; `app/decorators/models/date_decorator.rb:1-9`.

#### Scenario: Correcao aplicada uma unica vez
- **GIVEN** um lancamento em padrao corrigido, com valor digitado de 30.000 numa data com metade dos dias uteis do mes decorridos
- **WHEN** o usuario salva o lancamento e, em seguida, salva de novo sem alterar o valor
- **THEN** o valor gravado e 15.000 nas duas vezes

> AMBIGUIDADE: D-02 — no legado ocorre **decaimento composto**: `original_value` e regravado a cada mudanca de `value` e `update_value` reescreve `value`, entao um save subsequente reaplica o multiplicador sobre o valor ja corrigido. O duplo `save` do controller (BE-123) e a propagacao em cascata (BE-129) tornam isso reproduzivel. Pode haver dependencia contabil no valor atual — precisa de reconciliacao com dados reais antes de decidir se o ai9 corrige ou replica.

#### Scenario: Dias uteis e feriados
- **GIVEN** um mes com feriado em dia util
- **WHEN** a proporcao de dias uteis e calculada
- **THEN** a contagem segue a regra definida de dias uteis

> AMBIGUIDADE: D-03 — no legado dias uteis sao apenas segunda a sexta, **sem calendario de feriados**. Incluir feriados muda resultado financeiro; precisa de decisao do negocio.

#### Scenario: Data no primeiro dia do mes em fim de semana
- **GIVEN** um lancamento com data no dia 1 que cai em sabado ou domingo
- **WHEN** a correcao e aplicada
- **THEN** o valor resultante segue a regra definida para zero dias uteis decorridos

> AMBIGUIDADE: no legado o resultado e zero, sem aviso ao usuario.

#### Scenario: Padrao marcado como corrigido depois de ja ter lancamentos
- **GIVEN** lancamentos existentes em um padrao que passa a ser marcado como corrigido
- **WHEN** o proximo recalculo ocorre
- **THEN** o valor originalmente digitado de cada lancamento continua conhecido e a correcao e aplicada sobre ele

> AMBIGUIDADE: no legado `original_value` so e capturado quando o valor muda **e** o padrao ja e corrigido — lancamentos anteriores ficam com `original_value` zerado e caem para zero no recalculo seguinte.

### Requirement: BE-128 — Saldo acumulado nos padroes de primeiro nivel
O sistema DEVE (SHALL) apresentar, para cada padrao de primeiro nivel, um saldo que acumula os valores com sinal de todos os padroes de primeiro nivel anteriores. Fonte legada: `app/models/availability_entry.rb:128-134`, `:167-184`, `:199-223`; `app/models/project_availability_template.rb:71-81`.

#### Scenario: Acumulado nao depende de quais lancamentos ja existem
- **GIVEN** tres padroes de primeiro nivel, sendo que o segundo nao tem lancamento na data
- **WHEN** o saldo acumulado do terceiro e calculado
- **THEN** o resultado e o mesmo que seria obtido se o segundo tivesse lancamento de valor zero

> Nota: corrige o comportamento nao deterministico do legado — `previous_level_entries` so empilhava os lancamentos **existentes**, entao o acumulado variava conforme quais celulas o usuario ja havia preenchido.

#### Scenario: Saldo nos niveis 2 e 3
- **GIVEN** um padrao de segundo ou terceiro nivel
- **WHEN** o saldo e apresentado
- **THEN** ele corresponde ao proprio valor do padrao

#### Scenario: Padroes desativados no acumulado
- **GIVEN** um padrao de primeiro nivel desativado
- **WHEN** o saldo acumulado dos padroes seguintes e calculado
- **THEN** o padrao desativado nao entra na conta

> Nota: corrige o legado, onde `next_level_templates`/`previous_level_templates` nao filtravam por `is_active` e a ordenacao declarada nas linhas 73/79 era descartada (resultado nao reatribuido).

### Requirement: BE-129 — Propagacao em cascata apos salvar um lancamento
Ao salvar um lancamento o sistema DEVE (SHALL) recalcular, de forma atomica, os totais dos niveis superiores, os saldos dos niveis seguintes e a consolidacao geral. Fonte legada: `app/models/availability_entry.rb:26-36`, `:225-242`.

#### Scenario: Falha no meio da propagacao
- **GIVEN** um lancamento cuja propagacao falha ao recalcular um dos niveis
- **WHEN** a falha ocorre
- **THEN** nenhuma alteracao parcial permanece e o erro e devolvido ao usuario

> Nota: corrige o legado, onde cada `save` disparava uma arvore de saves recursivos mais um upsert em massa **sem transacao** — uma falha no meio deixava a hierarquia parcialmente recalculada, e o upsert usava `validate: false`, contornando todas as validacoes.

#### Scenario: Hierarquia com referencia circular
- **GIVEN** uma configuracao de padroes em que um padrao referencia a si mesmo como pai
- **WHEN** um lancamento e salvo
- **THEN** a operacao termina com erro explicito, sem recursao infinita

> Nota: corrige a ausencia de guarda de ciclo no legado.

### Requirement: BE-130 — Materializacao de lancamentos derivados
O sistema DEVE (SHALL) definir de forma explicita quando lancamentos derivados (pai, niveis seguintes e consolidacao geral) sao persistidos, e a leitura da grade NAO DEVE (SHALL NOT) criar registros. Fonte legada: `app/models/availability_entry.rb:56-78`, `:105-165`; `app/models/project.rb:212-234`.

#### Scenario: Abrir a grade nao cria dados
- **GIVEN** uma data sem nenhum lancamento
- **WHEN** o usuario abre a grade dessa data
- **THEN** nenhum registro e criado no banco

#### Scenario: Autoria dos lancamentos derivados
- **GIVEN** um lancamento derivado criado como efeito de um recalculo
- **WHEN** o registro e lido
- **THEN** fica claro que ele e derivado, e nao um lancamento feito pelo usuario que disparou o recalculo

> AMBIGUIDADE: no legado a leitura apenas instancia em memoria, mas `parent_entry`, `next_level_entries` e `update_mirror!` **salvam no banco**, e os registros criados herdam o autor de quem editou. Confirmar se o ai9 mantem a materializacao implicita ou passa a calcular sob demanda.

### Requirement: BE-131 — Validacoes do lancamento de disponibilidade
O sistema DEVE (SHALL) exigir autor, projeto, padrao, data e valor no lancamento, garantir unicidade por projeto, empresa, padrao e data, e derivar o titulo do padrao. Fonte legada: `app/models/availability_entry.rb:1-23`; `app/models/entry.rb:1-14`; `app/controllers/pub/availability_entries_controller.rb:78-86`.

#### Scenario: Unicidade garantida sob concorrencia
- **GIVEN** duas requisicoes concorrentes criando o mesmo lancamento
- **WHEN** ambas sao processadas
- **THEN** apenas uma persiste e a outra recebe 422

> Nota: corrige o legado, onde a unicidade existia **apenas em nivel de aplicacao**, sem indice unico (ver DB-133) e portanto sujeita a corrida.

#### Scenario: Titulo derivado do padrao
- **GIVEN** um lancamento criado com um titulo arbitrario no corpo da requisicao
- **WHEN** ele e salvo
- **THEN** o titulo registrado e o do padrao correspondente

### Requirement: BE-132 — Busca dos padroes globais
O sistema DEVE (SHALL) listar os padroes globais na ordem hierarquica, com busca textual funcional e paginacao efetiva. Fonte legada: `config/routes.rb:70`; `app/controllers/pub/availability_templates_controller.rb:9-29`; `app/models/global_availability_template.rb:85-106`.

#### Scenario: Busca por texto
- **GIVEN** padroes globais cadastrados, entre eles um chamado `Receitas Operacionais`
- **WHEN** o usuario busca por `operacionais`
- **THEN** o padrao aparece no resultado, com status 200

> AMBIGUIDADE: D-06 — no legado a busca com texto ordena por `default_position`, **coluna que nao existe em nenhuma migration** (ver DB-134), entao qualquer texto digitado derruba a requisicao com erro de SQL. Confirmar contra o banco real se a coluna existe fora do versionamento de migrations (DEC-04 registra o risco). Alem disso o filtro usa apenas prefixo (`"q%"`), sem casar substring no meio.

#### Scenario: Catalogo global vazio
- **GIVEN** nenhum padrao global cadastrado
- **WHEN** a lista e consultada
- **THEN** a resposta e uma lista vazia, sem erro

> Nota: corrige o legado, onde a ordenacao hierarquica montava um `JOIN (VALUES ...)` sem tuplas e gerava SQL invalido com a tabela vazia.

#### Scenario: Paginacao aplicada
- **GIVEN** 120 padroes globais
- **WHEN** o cliente pede `l=50`, `o=50`
- **THEN** sao devolvidos 50 padroes a partir do 51o e o total informado e 120

> Nota: corrige D-07/D-20.

### Requirement: BE-133 — Detalhe e formularios de padrao global
O sistema DEVE (SHALL) fornecer os dados de detalhe, criacao e edicao de padrao global, e o detalhe DEVE (SHALL) funcionar tambem para padroes especificos de projeto. Fonte legada: `app/controllers/pub/availability_templates_controller.rb:31-55`; `config/routes.rb:71`; `app/controllers/pub/console_controller.rb:148-151`.

#### Scenario: Detalhe de padrao especifico de projeto
- **GIVEN** um padrao especifico de um projeto
- **WHEN** o cliente pede o detalhe
- **THEN** a resposta traz os dados do padrao e a informacao de a qual projeto ele pertence, com status 200

> Nota: corrige o legado, onde o detalhe chamava `.projects` — associacao **inexistente** em `ProjectAvailabilityTemplate` — resultando em `NoMethodError`; e a action `show` do controller nao carregava o registro (o `before_action` cobria apenas `edit`/`update`/`destroy`).

### Requirement: BE-134 — Criar padrao global
O sistema DEVE (SHALL) criar padroes globais com titulo, tipo de operacao, tipo de prazo, obrigatoriedade, cumulatividade, correcao por dias uteis e posicao na hierarquia, propagando-os para os projetos conforme a opcao escolhida. Fonte legada: `config/routes.rb:70`; `app/controllers/pub/availability_templates_controller.rb:57-69`, `:119-132`; `app/models/global_availability_template.rb:23-70`.

#### Scenario: Obrigatoriedade informada e respeitada
- **GIVEN** o formulario de novo padrao global com a obrigatoriedade desmarcada
- **WHEN** o padrao e criado
- **THEN** o padrao criado nao e obrigatorio

> Nota: corrige o legado, onde `is_mandatory |= 1` (OR bit a bit, `:45`) fazia com que **todo** padrao global nascesse obrigatorio, descartando silenciosamente a escolha do formulario.

#### Scenario: Titulo repetido no mesmo nivel
- **GIVEN** um padrao global `Receitas` no primeiro nivel
- **WHEN** outro com o mesmo titulo e criado no mesmo nivel
- **THEN** a resposta e 422

#### Scenario: Propagacao para projetos existentes
- **GIVEN** cinco projetos existentes
- **WHEN** um novo padrao global e criado com a opcao de inserir nos projetos existentes
- **THEN** o padrao passa a existir nos cinco projetos, e o progresso de cada insercao e observavel separadamente

> Nota: corrige o legado, onde `should_insert_on_existing_projects` (default 1) nao era exposto em nenhuma tela — **toda** criacao disparava jobs em **todos** os projetos, todos escrevendo no mesmo campo de progresso do projeto (OPS-121).

### Requirement: BE-135 — Atualizar padrao global
O sistema DEVE (SHALL) atualizar titulo, tipo de operacao, tipo de prazo, cumulatividade, correcao e obrigatoriedade de um padrao global, mantendo posicao e projetos derivados coerentes. Fonte legada: `config/routes.rb:70`; `app/controllers/pub/availability_templates_controller.rb:71-84`.

#### Scenario: Alterar a correcao por dias uteis de um padrao global
- **GIVEN** um padrao global ja replicado em varios projetos
- **WHEN** a marca de correcao por dias uteis e alterada
- **THEN** os padroes derivados nos projetos seguem a regra de propagacao definida, sem divergir silenciosamente do padrao

> AMBIGUIDADE: no legado a alteracao de `is_adjusted`/`is_cumulative` de um global **nao se propaga** para os `ProjectAvailabilityTemplate` ja derivados — os projetos ficam divergentes do catalogo. Confirmar se a propagacao e desejada.

#### Scenario: Alterar o nivel numerico
- **GIVEN** um padrao global no primeiro nivel numero 2
- **WHEN** o numero e alterado para 5, valor ja usado por outro padrao
- **THEN** a alteracao e recusada ou a renumeracao dos irmaos e feita, sem deixar dois padroes com a mesma posicao

> Nota: corrige o legado, onde o `before_validation` de posicionamento era `on: [:create]` — a edicao gravava o numero direto, sem recalcular posicoes e sem impedir colisao (a unicidade cobria apenas titulo mais niveis).

### Requirement: BE-136 — Excluir padrao global
O sistema DEVE (SHALL) excluir um padrao global e seus descendentes, desvinculando de forma completa os padroes de projeto derivados, e DEVE (SHALL) comunicar falhas. Fonte legada: `config/routes.rb:70`; `app/controllers/pub/availability_templates_controller.rb:87-97`; `app/models/global_availability_template.rb:8`, `:11`, `:72-74`.

#### Scenario: Desvinculo completo em cascata
- **GIVEN** um padrao global com filhos e netos, replicados em varios projetos
- **WHEN** o padrao global e excluido
- **THEN** todos os padroes de projeto derivados dele e de seus descendentes passam a ser especificos do projeto, sem restar referencia ao global removido

> Nota: corrige o legado, onde o desvinculo em cascata dependia de cada callback disparar e por isso existia a rotina manual de conserto `ProjectAvailabilityTemplate.fix_after_global_remove` (OPS-129).

#### Scenario: Falha na exclusao e comunicada
- **GIVEN** uma exclusao que falha
- **WHEN** a resposta chega
- **THEN** o status e de erro e a mensagem explica o motivo

> Nota: corrige D-24 (legado: o ramo de erro respondia `:ok` — a interface nunca via a falha).

### Requirement: BE-137 — Numeracao e posicionamento hierarquico dos padroes
O sistema DEVE (SHALL) derivar de forma deterministica o nivel e a posicao de um padrao a partir do seu pai, em ate tres niveis. Fonte legada: `app/models/global_availability_template.rb:43-70`, `:337-370`; `app/models/project_availability_template.rb:28-60`, `:243-276`.

#### Scenario: Nivel derivado do pai
- **GIVEN** um padrao-pai de segundo nivel, numeros 5 e 2
- **WHEN** um filho e criado sob ele
- **THEN** o filho fica no terceiro nivel com os numeros superiores 5 e 2

> Nota: corrige o legado, que usava ` |= ` (OR bit a bit) para herdar `numeric_first_level`/`numeric_second_level` — funcionava so quando o campo era nulo ou zero; com valor previo o resultado era um OR de inteiros (2 herdando de 5 virava 7), produzindo numeros irreproduziveis.

#### Scenario: Pai inexistente
- **GIVEN** uma criacao que referencia um padrao-pai que nao existe
- **WHEN** ela e processada
- **THEN** a resposta e 422, e nao um erro interno

> Nota: corrige o `NoMethodError` do legado em `ensure_top_parent` (o uso de `pn.id` vinha **antes** da checagem `unless pn.blank?`).

#### Scenario: Criacao concorrente de irmaos
- **GIVEN** duas criacoes concorrentes de padroes no mesmo nivel
- **WHEN** ambas sao processadas
- **THEN** cada padrao recebe um numero distinto

> Nota: corrige o legado, que usava contagem de irmaos como numero, gerando colisao sob concorrencia.

### Requirement: BE-138 — Reordenacao de padroes
O sistema DEVE (SHALL) permitir reordenar padroes dentro do mesmo nivel, renumerando os irmaos e reescrevendo as posicoes da subarvore de forma consistente. Fonte legada: `app/models/global_availability_template.rb:120-331`, `:373-474`; `app/models/project_availability_template.rb:279-595`; `app/models/project.rb:236-273`.

#### Scenario: Mover um padrao para outra posicao
- **GIVEN** cinco padroes irmaos no mesmo nivel
- **WHEN** o terceiro e movido para a primeira posicao
- **THEN** os cinco ficam renumerados em sequencia e as posicoes de toda a subarvore refletem a nova ordem

#### Scenario: Movimento invalido
- **GIVEN** uma tentativa de mover um padrao para outro nivel ou outra familia
- **WHEN** ela e submetida
- **THEN** a operacao e recusada com erro explicito

> Nota: corrige o legado, onde a restricao existia apenas como comentario e garantia de interface — nao havia validacao no servidor.

#### Scenario: Reordenacao em projeto grande
- **GIVEN** um projeto com milhares de padroes
- **WHEN** a arvore e reordenada
- **THEN** a operacao termina dentro do limite de performance definido

> Nota: corrige o custo quadratico do legado (os tres `import` rodavam **dentro** do loop de primeiro nivel, `project.rb:269-271`) e o uso de `import` com `validate: false`.

> AMBIGUIDADE: no legado a reordenacao **nao e exposta em nenhuma tela** do console. Confirmar se e feature a portar ou rotina usada apenas por console Rails.

### Requirement: BE-139 — Obrigatoriedade hierarquica dos padroes
O sistema DEVE (SHALL) recusar marcar um padrao como obrigatorio quando o pai ou o topo da cadeia nao forem obrigatorios. Fonte legada: `app/models/availability_template.rb:2-8`.

#### Scenario: Cadeia superior nao obrigatoria
- **GIVEN** um padrao-pai nao obrigatorio
- **WHEN** o usuario tenta marcar um filho como obrigatorio
- **THEN** a operacao e recusada com a mensagem de que os niveis acima tambem precisam ser obrigatorios

#### Scenario: Cadeia superior obrigatoria
- **GIVEN** um padrao-pai e um topo ambos obrigatorios
- **WHEN** o usuario marca o filho como obrigatorio
- **THEN** a operacao e aceita

### Requirement: BE-140 — Listar padroes de disponibilidade do projeto
O sistema DEVE (SHALL) devolver a arvore de padroes do projeto corrente, ativos e inativos, na ordem hierarquica, com busca e paginacao efetivas. Fonte legada: `config/routes.rb:76`; `app/controllers/pub/project_availabilities_controller.rb:10-14`; `app/models/project_availability_template.rb:200-226`.

#### Scenario: Projeto sem nenhum padrao
- **GIVEN** um projeto que ainda nao tem padroes
- **WHEN** a arvore e consultada
- **THEN** a resposta e uma lista vazia, sem erro

> Nota: corrige o legado, onde `all_by_position` montava um `JOIN (VALUES ...)` sem tuplas e gerava SQL invalido em projeto zerado.

#### Scenario: Usuario sem projeto corrente
- **GIVEN** um usuario autenticado sem projeto corrente resolvido
- **WHEN** ele consulta a arvore
- **THEN** a resposta e um erro de pre-condicao explicito, e nao um erro interno

#### Scenario: Busca e paginacao aplicadas
- **GIVEN** um projeto com centenas de padroes
- **WHEN** o cliente envia termo de busca e limite
- **THEN** o resultado respeita o termo e o limite

> Nota: corrige D-07/D-20 (legado: os parametros `q`/`l`/`o` enviados pela tela eram completamente ignorados pelo servidor).

#### Scenario: Padroes inativos permanecem visiveis
- **GIVEN** um projeto com padroes ativos e inativos
- **WHEN** a arvore e consultada
- **THEN** os inativos aparecem identificados como tal

### Requirement: BE-141 — Formularios de padrao de disponibilidade do projeto
O sistema DEVE (SHALL) fornecer os dados dos formularios de criacao e edicao de padrao do projeto, deixando explicito o que pode ser alterado apos a criacao. Fonte legada: `config/routes.rb:77`; `app/controllers/pub/project_availabilities_controller.rb:16-34`.

#### Scenario: Usuario sem projeto corrente
- **GIVEN** um usuario sem projeto corrente resolvido
- **WHEN** ele abre o formulario de novo padrao
- **THEN** a resposta e um erro de pre-condicao explicito

> Nota: corrige o `NoMethodError` do legado quando `current_user.default_project` era nulo.

#### Scenario: Campos imutaveis na edicao
- **GIVEN** um padrao ja criado
- **WHEN** o formulario de edicao e aberto
- **THEN** os campos que nao podem ser alterados sao identificados como somente leitura, com a razao visivel ao usuario

> AMBIGUIDADE: no legado apenas o titulo e editavel — tipo de operacao, prazo, cumulativo, corrigido e hierarquia sao imutaveis apos a criacao, sem nenhuma explicacao na tela. Confirmar se a restricao e intencional.

### Requirement: BE-142 — Criar padrao de disponibilidade do projeto
O sistema DEVE (SHALL) criar padroes especificos do projeto corrente com titulo, tipo de operacao, tipo de prazo, cumulatividade, correcao e posicao na hierarquia, sempre no escopo do tenant do solicitante. Fonte legada: `config/routes.rb:76`; `app/controllers/pub/project_availabilities_controller.rb:36-48`, `:142-156`; `app/models/project_availability_template.rb:16-60`.

#### Scenario: Projeto definido pelo servidor
- **GIVEN** um usuario cujo projeto corrente e o projeto A
- **WHEN** ele cria um padrao enviando o identificador do projeto B no corpo
- **THEN** o padrao e criado no projeto A

> Nota: corrige D-29/D-23 (legado: `project_id` vinha de campo escondido do formulario e nao era validado contra o projeto do usuario — era possivel criar padrao em projeto alheio forjando o campo).

#### Scenario: Identificador nao pode ser imposto pelo cliente
- **GIVEN** uma criacao que informa explicitamente um identificador de registro
- **WHEN** ela e processada
- **THEN** o identificador enviado e ignorado e o registro recebe um identificador gerado pelo sistema

> Nota: corrige o legado, onde `:id` estava nos parametros permitidos (`:144`), abrindo mass assignment de chave primaria.

#### Scenario: Erros identificados em pt-BR
- **GIVEN** uma criacao sem tipo de operacao
- **WHEN** ela e submetida
- **THEN** a resposta e 422 e a mensagem nomeia o campo em pt-BR

> Nota: corrige o legado, onde `translate_every_key` estava **vazio** neste controller e os erros voltavam com as chaves tecnicas em ingles.

#### Scenario: Titulos iguais entre netos irmaos
- **GIVEN** dois padroes de terceiro nivel sob o mesmo pai
- **WHEN** o segundo e criado com o mesmo titulo do primeiro
- **THEN** a criacao e rejeitada

> Nota: no legado a unicidade nao incluia o terceiro nivel, entao a rejeicao acontecia por acidente entre netos de pais diferentes e nao entre irmaos reais.

### Requirement: BE-143 — Atualizar padrao de disponibilidade do projeto
O sistema DEVE (SHALL) atualizar um padrao do projeto em uma unica gravacao, recusando alteracao em padrao bloqueado por operacao em andamento e mantendo a posicao coerente. Fonte legada: `config/routes.rb:76`; `app/controllers/pub/project_availabilities_controller.rb:50-63`.

#### Scenario: Padrao bloqueado
- **GIVEN** um padrao bloqueado por uma operacao em andamento
- **WHEN** o usuario tenta renomea-lo
- **THEN** a resposta e 409 informando a operacao em andamento

> Nota: corrige o legado, que nao checava `is_locked` no update.

#### Scenario: Renomear nao renumera o padrao
- **GIVEN** um padrao na posicao 2.1
- **WHEN** apenas o titulo e alterado
- **THEN** a posicao permanece 2.1

> AMBIGUIDADE: no legado o `before_validation` de posicionamento roda tambem no update para padroes de projeto (diferente do global, que e `on: [:create]`) — um update pode renumerar o item. Confirmar se a assimetria e proposital.

### Requirement: BE-144 — Ativar padrao de disponibilidade do projeto
O sistema DEVE (SHALL) ativar um padrao do projeto em segundo plano, bloqueando o padrao e seus filhos durante o processamento, recalculando os lancamentos afetados e liberando o bloqueio ao final, inclusive em caso de falha. Fonte legada: `config/routes.rb:78`; `app/controllers/pub/project_availabilities_controller.rb:65-82`; `app/models/project_availability_template.rb:87-95`, `:702-742`.

#### Scenario: Ativacao ja em andamento
- **GIVEN** um padrao com uma ativacao ja enfileirada
- **WHEN** o usuario aciona a ativacao de novo
- **THEN** a resposta e 409 e nenhuma segunda tarefa e enfileirada

> Nota: corrige o legado, que nao tinha idempotencia — ativar duas vezes enfileirava dois jobs, o segundo sobrescrevia o identificador de tarefa e o primeiro ficava orfao.

#### Scenario: Falha ao enfileirar
- **GIVEN** uma falha ao enfileirar a tarefa de ativacao
- **WHEN** a resposta chega
- **THEN** o status e de erro e a interface nao indica sucesso

> Nota: corrige D-24 (legado: o ramo de erro respondia `:ok`, `:79`, e se o enfileiramento retornasse nulo a interface ainda mostrava sucesso).

#### Scenario: Falha no processamento libera o bloqueio
- **GIVEN** uma ativacao que falha durante o recalculo
- **WHEN** a falha ocorre
- **THEN** a tarefa e reexecutada conforme a politica de retentativa, o bloqueio e liberado ao final e a falha fica visivel

> Nota: corrige D-05.

#### Scenario: Ativar com o pai inativo
- **GIVEN** um padrao filho de um padrao inativo
- **WHEN** o usuario o ativa
- **THEN** o resultado segue a regra definida para a cadeia superior

> AMBIGUIDADE: no legado o job so marca o proprio padrao, sem subir a hierarquia; o metodo que subia (`active_and_reorder!`, junto com `activate!`/`active_parent!`) **nao e chamado por nenhuma rota** e aparenta ser codigo morto. Confirmar qual e a regra correta.

### Requirement: BE-145 — Desativar padrao de disponibilidade do projeto
O sistema DEVE (SHALL) desativar um padrao do projeto em segundo plano, aplicando no servico as regras que impedem desativar padrao obrigatorio ou padrao com dependentes obrigatorios, reconsolidando os totais e liberando o bloqueio ao final. Fonte legada: `config/routes.rb:79`; `app/controllers/pub/project_availabilities_controller.rb:84-101`; `app/models/project_availability_template.rb:139-172`, `:744-796`.

#### Scenario: Padrao obrigatorio nao pode ser desativado
- **GIVEN** um padrao marcado como obrigatorio
- **WHEN** o usuario aciona a desativacao pela tela
- **THEN** a operacao e recusada com a mensagem de que nao e possivel desativar um padrao obrigatorio, e nenhuma tarefa e enfileirada

> Nota: corrige D-04/D-33 (legado: a guarda vive em `deactive_and_reorder!` (`:141-169`) mas **essa rota nao a usa** — o job chamava `background_deactivate`, que apenas fazia `is_active = 0` e salvava; era possivel desativar um padrao obrigatorio pela tela. A propria guarda ainda filtrava por `project_id: self.id`, usando o id do padrao como id de projeto, o que a tornaria inocua mesmo se chamada).

#### Scenario: Padrao com dependentes obrigatorios
- **GIVEN** um padrao que possui filhos obrigatorios
- **WHEN** o usuario aciona a desativacao
- **THEN** a operacao e recusada informando que existem dependentes obrigatorios

#### Scenario: Desativacao valida reconsolida os totais
- **GIVEN** um padrao nao obrigatorio, sem dependentes obrigatorios, com lancamentos em varias datas
- **WHEN** a desativacao e processada
- **THEN** o padrao fica inativo, os totais das datas afetadas sao reconsolidados, os lancamentos existentes sao preservados e o bloqueio e liberado

### Requirement: BE-146 — Remover padrao de disponibilidade do projeto
O sistema DEVE (SHALL) tratar de forma explicita a remocao de padrao com lancamentos vinculados e, quando a remocao ocorrer, DEVE (SHALL) executa-la de forma atomica com reconsolidacao dos totais. Fonte legada: `config/routes.rb:76`; `app/controllers/pub/project_availabilities_controller.rb:103-120`; `app/models/project_availability_template.rb:598-600`, `:619-700`.

#### Scenario: Padrao com lancamentos vinculados
- **GIVEN** um padrao que possui lancamentos de disponibilidade
- **WHEN** o usuario aciona a remocao
- **THEN** o sistema informa explicitamente que ha lancamentos e aplica a regra definida, sem apagar dado financeiro silenciosamente

> Nota: corrige a divergencia do legado — `is_deletable?` (verdadeiro so sem lancamentos) era consultado **apenas na interface** e nem sequer usado no JS; o servidor nunca checava e o job destruia todas as entradas dos descendentes (`entries.destroy_all`), contornando o `restrict_with_error` da associacao.

#### Scenario: Falha no meio da remocao
- **GIVEN** uma remocao que falha depois de ja ter apagado parte da subarvore
- **WHEN** a falha ocorre
- **THEN** nenhuma alteracao parcial permanece e a falha fica visivel para o usuario

> Nota: corrige D-05 e a ausencia de transacao (legado: destrutivo, irreversivel e sem rollback; alem disso `recalculate_entry.id` era chamado sem checar nulo no ramo com pai, abortando o job no meio com os padroes ja apagados e o recalculo por fazer).

#### Scenario: Padrao global nao e removivel pela tela do projeto
- **GIVEN** um padrao global replicado no projeto
- **WHEN** um cliente envia diretamente a remocao pela rota do projeto
- **THEN** a resposta e 422

> Nota: corrige o legado, onde a interface escondia a opcao mas o servidor nao a bloqueava.

### Requirement: BE-147 — Bloqueio de padroes durante operacoes
Enquanto uma operacao esta em andamento sobre um padrao, o sistema DEVE (SHALL) marcar o padrao e seus descendentes como bloqueados, com motivo consultavel, e DEVE (SHALL) garantir que o bloqueio termine junto com a operacao, com ou sem sucesso. Fonte legada: `app/models/project_availability_template.rb:83-106`.

#### Scenario: Falha da operacao nao deixa padrao travado
- **GIVEN** um padrao bloqueado por uma operacao que falha
- **WHEN** a operacao termina em falha
- **THEN** o bloqueio e liberado e o padrao volta a ser utilizavel pela tela

> Nota: corrige D-05 (legado: o desbloqueio so acontecia em `background_activate` e `background_deactivate`; `background_removal` nunca desbloqueava e, se o job falhasse antes de apagar, o padrao ficava **bloqueado para sempre**, sem caminho de recuperacao pela interface).

#### Scenario: Bloqueio vale tambem no servidor
- **GIVEN** um padrao bloqueado
- **WHEN** um cliente envia diretamente uma alteracao de valor ou de padrao
- **THEN** a alteracao e recusada

> Nota: corrige o legado, onde o bloqueio apenas escondia controles na interface (BE-123/BE-143).

### Requirement: BE-148 — Consolidacao por padrao base e indicadores do painel
O sistema DEVE (SHALL) devolver, para um projeto, empresa e periodo, as datas com lancamento, o total por padrao base, a contagem de lancamentos e o total geral, com semantica unica de "total". Fonte legada: `app/models/project.rb:28-42`, `:393-422`; `app/controllers/api/v1/project_availability_controller.rb:15-26`.

#### Scenario: Datas com lancamento no mes
- **GIVEN** um projeto com lancamentos em cinco dias do mes
- **WHEN** o painel do mes e consultado
- **THEN** as cinco datas sao devolvidas para marcar o calendario

#### Scenario: Consulta por dia especifico
- **GIVEN** uma consulta com data especifica
- **WHEN** ela e processada
- **THEN** os totais e a contagem correspondem a data pedida, e as datas marcadas correspondem ao periodo apresentado no calendario

> Nota: corrige o legado, onde com `date` preenchido as datas marcadas continuavam sendo calculadas a partir do mes inteiro.

#### Scenario: Total geral e total por padrao base
- **GIVEN** padroes base com valores de credito e de debito
- **WHEN** os totais sao apresentados no painel
- **THEN** o total geral e os totais por padrao base usam a mesma definicao de valor

> AMBIGUIDADE: no legado o total geral usa `value` (soma bruta, sem sinal de debito) enquanto cada card de padrao base usa `virtual_value` (saldo acumulado) — duas metricas com semanticas diferentes na mesma tela. Precisa de decisao de produto.

### Requirement: BE-149 — API de disponibilidade do projeto
O sistema DEVE (SHALL) expor a consulta de disponibilidade de um projeto por periodo e empresa, exigindo autenticacao e escopo de tenant, com validacao dos parametros de periodo. Fonte legada: `config/routes.rb:238`; `app/controllers/api/v1/project_availability_controller.rb:1-34`.

#### Scenario: Requisicao sem autenticacao
- **GIVEN** um cliente sem credencial valida
- **WHEN** ele consulta a disponibilidade de um projeto por id
- **THEN** a resposta e 401 e nenhum valor financeiro e devolvido

> Nota: corrige D-01 (legado: `Api::V1::ProjectAvailabilityController` herdava de `ApplicationController`, que estava vazio, e fazia `Project.find(params[:id])` sem escopo — qualquer requisicao lia a disponibilidade de qualquer projeto por id). Nao se replica um IDOR.

#### Scenario: Projeto fora do escopo do solicitante
- **GIVEN** um cliente autenticado que nao e membro do projeto X
- **WHEN** ele consulta a disponibilidade do projeto X
- **THEN** a resposta e 403 ou 404, sem devolver dados

#### Scenario: Mes invalido
- **GIVEN** uma consulta com mes 13
- **WHEN** ela e processada
- **THEN** a resposta e 422 informando o parametro invalido

> Nota: corrige o legado, onde `Date.new` com mes invalido levantava `ArgumentError` e resultava em 500.

#### Scenario: Formato da resposta
- **GIVEN** uma consulta valida e autorizada
- **WHEN** a resposta e devolvida
- **THEN** o corpo e um objeto JSON legivel diretamente, sem dupla serializacao

> Nota: corrige o legado, que devolvia uma string JSON dentro de uma resposta JSON, e cujo ramo 404 era inalcancavel.

### Requirement: FE-120 — Painel de Disponibilidade
O painel DEVE (SHALL) apresentar, em duas colunas, os filtros e indicadores a esquerda e a grade de lancamentos a direita, com a URL coerente com a secao aberta e falhas comunicadas. Fonte legada: `app/views/pub/console/parts/availability/_body.html.erb:1-64`; `_body.js.erb:274-280`.

#### Scenario: Falha ao carregar os indicadores
- **GIVEN** uma falha ao consultar os indicadores do painel
- **WHEN** o erro ocorre
- **THEN** a tela apresenta o estado de falha, com opcao de tentar novamente

> Nota: corrige o legado, onde o callback de erro do request de indicadores era **vazio** — a falha nao mostrava nada.

#### Scenario: URL da secao
- **GIVEN** o painel de disponibilidade aberto
- **WHEN** o usuario observa a URL
- **THEN** ela corresponde a secao efetivamente aberta

> Nota: corrige o legado, que reescrevia a URL para `/console/availability_entries` enquanto a rota real da secao era `availability`.

### Requirement: FE-121 — Seletor de visao por empresa
O painel DEVE (SHALL) permitir escolher entre a consolidacao geral do projeto e uma empresa especifica, recarregando indicadores e grade. Fonte legada: `app/views/pub/console/parts/availability/_body.html.erb:20-26`; `_body.js.erb:192-200`.

#### Scenario: Trocar de empresa
- **GIVEN** o painel com a consolidacao geral selecionada
- **WHEN** o usuario escolhe uma empresa
- **THEN** os indicadores e a grade passam a refletir apenas os lancamentos daquela empresa

### Requirement: FE-122 — Calendario de selecao de data
O painel DEVE (SHALL) oferecer um calendario em pt-BR para escolher a data dos lancamentos, marcando os dias que ja possuem lancamento. Fonte legada: `app/views/pub/console/parts/availability/_body.html.erb:28-31`; `_body.js.erb:83-85`, `:149-187`.

#### Scenario: Trocar de mes
- **GIVEN** o calendario aberto em um mes
- **WHEN** o usuario navega para outro mes
- **THEN** os dias com lancamento do novo mes sao marcados

#### Scenario: Faixa de datas permitida
- **GIVEN** o calendario aberto
- **WHEN** o usuario tenta navegar para fora da faixa permitida
- **THEN** a navegacao e impedida de forma consistente com a faixa anunciada

### Requirement: FE-123 — Selecao de data em telas estreitas
Em telas estreitas o painel DEVE (SHALL) oferecer a selecao de data por um controle proprio no cabecalho, com a mesma faixa e o mesmo efeito da versao ampla. Fonte legada: `app/views/pub/console/parts/availability/_body.html.erb:3-12`; `_body.js.erb:87-147`.

#### Scenario: Selecao de data em tela estreita
- **GIVEN** o painel aberto em uma tela estreita
- **WHEN** o usuario escolhe uma data pelo controle do cabecalho
- **THEN** o rotulo e atualizado e a grade recarrega para a data escolhida

> Nota: corrige a dupla fonte de verdade do legado — a decisao de "e mobile" era tomada no servidor pelo user agent e no cliente por deteccao propria, que podiam discordar.

### Requirement: FE-124 — Indicador de quantidade de lancamentos
O painel DEVE (SHALL) apresentar a quantidade de lancamentos com valor diferente de zero no periodo. Fonte legada: `app/views/pub/console/parts/availability/_body.html.erb:36-39`; `app/models/project.rb:409-411`.

#### Scenario: Contagem apresentada
- **GIVEN** um periodo com sete lancamentos folha de valor diferente de zero
- **WHEN** o painel carrega
- **THEN** o indicador apresenta sete

### Requirement: FE-125 — Indicadores de total por padrao base
O painel DEVE (SHALL) apresentar um indicador por padrao base com o valor consolidado, distinguindo valores positivos e negativos de forma inequivoca. Fonte legada: `app/views/pub/console/parts/availability/_body.html.erb:40-45`; `_body.js.erb:34-54`.

#### Scenario: Valor negativo
- **GIVEN** um padrao base com total negativo
- **WHEN** o indicador e apresentado
- **THEN** o sinal negativo e visivel no proprio valor, alem de qualquer diferenciacao por cor

> Nota: corrige o legado, que exibia o valor em **modulo** e sinalizava o negativo apenas pela cor vermelha — leitura ambigua e inacessivel para quem nao distingue as cores.

### Requirement: FE-126 — Bloco de observacao do projeto no painel
O painel DEVE (SHALL) apresentar a observacao de disponibilidade do projeto quando ela existir. Fonte legada: `app/views/pub/console/parts/availability/_body.html.erb:48-53`.

#### Scenario: Projeto sem observacao
- **GIVEN** um projeto sem observacao de disponibilidade
- **WHEN** o painel carrega
- **THEN** o bloco de observacao nao e apresentado

### Requirement: FE-127 — Grade hierarquica de lancamentos
A grade DEVE (SHALL) apresentar os padroes em ate tres niveis, com indentacao por nivel, valor editavel nas folhas, total calculado nos nos com filhos e saldo acumulado. Fonte legada: `app/views/pub/console/parts/availability/parts/availability_entries/list/_widget.html.erb:1-142`; `list/body.js.erb:1-26`.

#### Scenario: No com filhos
- **GIVEN** um padrao que possui filhos
- **WHEN** a grade e apresentada
- **THEN** a linha desse padrao mostra o total calculado, com a indicacao de credito ou debito, e nao um campo editavel

#### Scenario: Expandir e recolher niveis
- **GIVEN** uma arvore com tres niveis
- **WHEN** o usuario visualiza a grade
- **THEN** o comportamento de expandir e recolher segue a regra definida

> AMBIGUIDADE: no legado o codigo de colapsar/expandir esta **comentado** no HTML e no SCSS — a arvore e sempre totalmente expandida. Confirmar se foi desligado deliberadamente ou e regressao.

### Requirement: FE-128 — Estados da grade de lancamentos
A grade DEVE (SHALL) apresentar estados distintos de carregamento, sem data selecionada, sem padroes configurados, sem resultado de busca e falha, com textos corretos em pt-BR. Fonte legada: `app/views/.../availability_entries/list/body.js.erb:17-24`; `app/views/pub/console/parts/availability/_body.js.erb:245-251`.

#### Scenario: Falha de carregamento
- **GIVEN** uma falha ao carregar a grade
- **WHEN** o erro ocorre
- **THEN** a tela apresenta o estado de falha com opcao de tentar novamente

> Nota: corrige o legado, onde o callback de falha era vazio — nenhuma mensagem aparecia.

#### Scenario: Projeto sem padroes configurados
- **GIVEN** um projeto sem padroes de disponibilidade
- **WHEN** o usuario seleciona uma data
- **THEN** a tela orienta a configurar os padroes, com o texto correto em pt-BR

> Nota: corrige os erros de portugues do legado no texto de vazio ("Voce", "possui" com acento indevido).

### Requirement: FE-129 — Campo de valor do lancamento
O campo de valor DEVE (SHALL) aplicar mascara monetaria, aceitar virgula ou ponto como separador decimal, limitar a duas casas e apresentar a natureza da operacao de forma legivel. Fonte legada: `app/views/.../availability_entries/list/_widget.js.erb:5-72`.

#### Scenario: Mais de um separador decimal
- **GIVEN** o usuario digita `1,23,45` no campo de valor
- **WHEN** o campo perde o foco
- **THEN** a tela avisa que basta um separador decimal e o valor nao e enviado malformado

#### Scenario: Natureza da operacao no campo
- **GIVEN** um padrao de debito
- **WHEN** o campo e apresentado
- **THEN** a natureza da operacao aparece de forma legivel, e nao apenas como codigo bruto

> Nota: corrige o legado, que exibia o codigo `C`/`D` cru em vez do rotulo.

### Requirement: FE-130 — Salvamento do valor na grade
Alterar o valor de uma celula e sair do campo DEVE (SHALL) salvar o lancamento e atualizar totais e indicadores, sem afetar outros formularios da pagina. Fonte legada: `app/views/.../availability_entries/list/_widget.js.erb:161-199`; `helper/handle.js.erb:1-8`.

#### Scenario: Salvar um valor
- **GIVEN** uma celula editavel na grade
- **WHEN** o usuario altera o valor e sai do campo
- **THEN** o lancamento e salvo, os totais dos niveis superiores e os indicadores do painel sao atualizados e uma confirmacao e exibida

#### Scenario: Guarda de envio duplo nao trava outros formularios
- **GIVEN** a grade aberta com varios formularios de celula
- **WHEN** o usuario salva uma celula e em seguida edita outra
- **THEN** a segunda celula e salva normalmente

> Nota: corrige o legado, onde a guarda `preventDoubleSubmission` era aplicada a **todos** os formularios da pagina (`$('form')`), com efeito colateral global, e o formulario da celula era localizado por travessia rigida do DOM.

#### Scenario: Mensagem coerente com a acao
- **GIVEN** uma celula ainda sem lancamento
- **WHEN** o usuario informa um valor pela primeira vez
- **THEN** a mensagem informa que o lancamento foi **criado**

> Nota: corrige o legado, que usava o mesmo texto de alteracao para criacao e edicao.

### Requirement: FE-131 — Excluir lancamento pela grade
A grade DEVE (SHALL) oferecer a exclusao de um lancamento existente, com confirmacao, apenas quando aplicavel. Fonte legada: `app/views/.../availability_entries/list/_widget.js.erb:106-135`; `list/_widget.html.erb:31-37`.

#### Scenario: Exclusao nao oferecida
- **GIVEN** uma linha de consolidacao geral, ou um no com filhos, ou um usuario somente-leitura
- **WHEN** a grade e apresentada
- **THEN** a acao de excluir nao e oferecida nessa linha

#### Scenario: Exclusao confirmada
- **GIVEN** um lancamento folha de uma empresa
- **WHEN** o usuario confirma a exclusao
- **THEN** o lancamento some, os totais e os indicadores sao atualizados e uma confirmacao e exibida

### Requirement: FE-132 — Modo somente-leitura e consolidacao na grade
A grade DEVE (SHALL) impedir a edicao de valores para usuario somente-leitura e na visao de consolidacao geral, com o mesmo criterio aplicado no servidor. Fonte legada: `app/views/.../availability_entries/list/_widget.html.erb:55-59`, `:130-134`.

#### Scenario: Visao de consolidacao geral
- **GIVEN** a visao de consolidacao geral selecionada
- **WHEN** o usuario visualiza a grade
- **THEN** nenhum campo e editavel, e um envio direto ao servidor tambem e recusado

> Nota: corrige D-23 (legado: o bloqueio era **exclusivamente de interface** — o servidor aceitava o envio, ver BE-123).

### Requirement: FE-133 — Marcador de padrao nao cumulativo
A grade DEVE (SHALL) indicar visualmente os padroes que nao entram nos totais, com explicacao consultavel. Fonte legada: `app/views/.../availability_entries/list/_widget.html.erb:25-27`, `:89-91`; `list/_widget.js.erb:138-147`.

#### Scenario: Padrao nao cumulativo
- **GIVEN** um padrao marcado como nao cumulativo
- **WHEN** a linha e apresentada
- **THEN** um marcador identifica a condicao e a explicacao esta disponivel ao usuario

### Requirement: FE-134 — Marcador de padrao corrigido por dias uteis
A grade DEVE (SHALL) indicar os padroes corrigidos por dias uteis, com explicacao consultavel, e DEVE (SHALL) deixar claro qual valor foi digitado e qual foi gravado. Fonte legada: `app/views/.../availability_entries/list/_widget.html.erb:28-30`, `:92-94`; `list/_widget.js.erb:149-158`.

#### Scenario: Valor digitado e valor corrigido
- **GIVEN** um padrao corrigido por dias uteis
- **WHEN** o usuario digita o total do mes e o lancamento e salvo
- **THEN** o valor corrigido e apresentado no campo e o valor originalmente digitado permanece consultavel na tela

> Nota: corrige o legado, onde o usuario digitava X e via Y no campo, sem nenhuma indicacao do valor original (BE-127).

### Requirement: FE-135 — Tela "Tipos de disponibilidade"
A tela DEVE (SHALL) listar o catalogo global de padroes com titulo, tipo, prazo, acumulavel e corrigido. Fonte legada: `app/views/pub/console/parts/availability_templates/_body.html.erb:1-50`.

#### Scenario: Abrir o catalogo global
- **GIVEN** um usuario autorizado
- **WHEN** ele abre a tela de tipos de disponibilidade
- **THEN** os padroes globais sao listados na ordem hierarquica com as colunas indicadas

### Requirement: FE-136 — Busca de padroes globais
O campo de busca DEVE (SHALL) aguardar a pausa de digitacao e devolver os padroes que casam com o termo. Fonte legada: `app/views/pub/console/parts/availability_templates/_body.js.erb:25-38`, `:60-86`.

#### Scenario: Buscar por texto
- **GIVEN** o catalogo global aberto
- **WHEN** o usuario digita um termo
- **THEN** a lista e filtrada pelo termo

> AMBIGUIDADE: D-06 — no legado **qualquer texto digitado** quebra a requisicao no servidor (ordenacao por `default_position`, coluna inexistente, ver BE-132/DB-134) e o container cai num tratamento de falha vazio: a lista simplesmente para de atualizar, sem mensagem. Confirmar contra o banco real se a coluna existe fora das migrations.

### Requirement: FE-137 — Estados da lista de padroes globais
A lista DEVE (SHALL) apresentar estados distintos de carregamento, vazio, busca sem resultado e falha. Fonte legada: `app/views/.../availability_templates/list/body.js.erb:13-17`; `_body.js.erb:80-96`.

#### Scenario: Falha ao carregar
- **GIVEN** uma falha ao consultar o catalogo global
- **WHEN** o erro ocorre
- **THEN** a tela apresenta o estado de falha com opcao de tentar novamente

> Nota: corrige o legado, onde a falha era silenciosa.

### Requirement: FE-138 — Linha de padrao global e acoes
Cada linha DEVE (SHALL) apresentar a indentacao por nivel e oferecer detalhe, edicao e remocao conforme a permissao do usuario. Fonte legada: `app/views/.../availability_templates/list/_widget.html.erb:1-46`.

#### Scenario: Usuario somente-leitura
- **GIVEN** um usuario somente-leitura
- **WHEN** ele abre o menu de uma linha
- **THEN** as acoes de editar e remover nao sao oferecidas

#### Scenario: Remocao confirmada
- **GIVEN** um padrao global sem uso
- **WHEN** o usuario confirma a remocao
- **THEN** o padrao sai da lista e o resultado e comunicado

> Nota: no legado existe um parcial alternativo (`_child_widget.html.erb`) que referencia a coluna inexistente `default_position` e nao e renderizado por ninguem — codigo morto, nao portado (DB-134).

### Requirement: FE-139 — Formulario de padrao global
O formulario DEVE (SHALL) oferecer titulo, padrao-pai, niveis, tipo de operacao, prazo, cumulatividade, correcao por dias uteis e obrigatoriedade, sem expor dados de outros projetos. Fonte legada: `app/views/.../availability_templates/helper/_body.html.erb:1-90`.

#### Scenario: Opcao de obrigatoriedade disponivel
- **GIVEN** o formulario de novo padrao global
- **WHEN** o usuario o abre
- **THEN** a obrigatoriedade pode ser escolhida e a escolha e respeitada no salvamento

> Nota: corrige o legado, onde o campo nem existia na tela e o servidor forcava obrigatorio (BE-134).

#### Scenario: Dados de outros projetos nao sao expostos
- **GIVEN** o formulario aberto
- **WHEN** o conteudo entregue ao navegador e inspecionado
- **THEN** nenhum padrao de outro projeto esta presente

> Nota: corrige o vazamento do legado — `AvailabilityTemplate.all` era serializado em JSON dentro de um atributo `data-` do HTML, incluindo todos os padroes de todos os projetos, com custo de performance e exposicao de dados.

### Requirement: FE-140 — Detalhe do padrao
O detalhe DEVE (SHALL) apresentar titulo, tipo, escopo, prazo, obrigatoriedade, cumulatividade, correcao, autoria e datas, alem dos projetos em que o padrao esta ativo quando aplicavel. Fonte legada: `app/views/.../availability_templates/detail/_body.html.erb:1-95`.

#### Scenario: Detalhe de padrao especifico de projeto
- **GIVEN** um padrao especifico de projeto
- **WHEN** o detalhe e aberto
- **THEN** a tela carrega normalmente e identifica o projeto ao qual o padrao pertence

> Nota: corrige o legado, onde esse bloco chamava a associacao inexistente `.projects` e quebrava a tela (BE-133).

### Requirement: FE-141 — Permissao de cadastro no catalogo global
A tela do catalogo global DEVE (SHALL) apresentar a acao de cadastro apenas para papeis autorizados, com o mesmo criterio aplicado no servidor. Fonte legada: `app/views/.../availability_templates/_body.html.erb:10-18`.

#### Scenario: Usuario sem papel autorizado
- **GIVEN** um usuario sem papel autorizado a cadastrar padroes globais
- **WHEN** ele tenta criar um padrao global diretamente pela API
- **THEN** a resposta e 403

> Nota: corrige D-23 (legado: a regra de papel existia **apenas na view**; o `create` do controller nao checava papel algum).

### Requirement: FE-142 — Tela "Disponibilidades" do projeto
A tela DEVE (SHALL) apresentar a arvore de padroes do projeto corrente com titulo, tipo, prazo, acumulavel e corrigido, com recarga manual e acesso ao cadastro conforme permissao. Fonte legada: `app/views/pub/console/parts/project_availabilities/_body.html.erb:1-40`.

#### Scenario: Usuario somente-leitura
- **GIVEN** um usuario somente-leitura
- **WHEN** ele abre a tela
- **THEN** a acao de cadastrar nao e oferecida

### Requirement: FE-143 — Estados da lista de disponibilidades do projeto
A lista DEVE (SHALL) apresentar estados de carregamento, vazio e falha coerentes com os controles realmente oferecidos na tela. Fonte legada: `app/views/.../project_availabilities/list/body.js.erb:13-17`; `_body.js.erb:74-80`.

#### Scenario: Falha ao carregar
- **GIVEN** uma falha ao consultar a arvore do projeto
- **WHEN** o erro ocorre
- **THEN** a tela apresenta o estado de falha com opcao de tentar novamente

> Nota: corrige o legado, onde a falha era silenciosa e existia uma mensagem de "busca sem resultado" inalcancavel, pois a tela nao tem campo de busca.

### Requirement: FE-144 — Ligar e desligar padrao pela lista do projeto
A lista DEVE (SHALL) permitir ativar e desativar um padrao, com mensagens do dominio de disponibilidade, e o controle DEVE (SHALL) permanecer utilizavel apos a primeira acao. Fonte legada: `app/views/.../project_availabilities/list/_widget.html.erb:43-51`; `list/_widget.js.erb:44-95`.

#### Scenario: Duas acoes em sequencia
- **GIVEN** um padrao na lista
- **WHEN** o usuario aciona o interruptor e, apos a conclusao, o aciona de novo
- **THEN** a segunda acao e processada normalmente

> Nota: corrige o legado, onde a guarda `preventDoubleSubmit` **nunca era resetada** — o interruptor ficava inerte ate recarregar a lista.

#### Scenario: Mensagem de resultado
- **GIVEN** um padrao ativo
- **WHEN** o usuario o desativa com sucesso
- **THEN** a mensagem informa que a **disponibilidade** foi desativada

> Nota: corrige o texto do legado, que dizia "Indicador ativado/deasativado" — vocabulario de outro modulo, com erro de grafia.

#### Scenario: Usuario somente-leitura
- **GIVEN** um usuario somente-leitura
- **WHEN** ele tenta alterar o estado de um padrao
- **THEN** a acao e recusada e a tela informa a falta de permissao

### Requirement: FE-145 — Menu de contexto do padrao na lista do projeto
O menu de contexto DEVE (SHALL) oferecer as acoes aplicaveis ao estado do padrao, sem itens vazios nem acoes que resultem em erro. Fonte legada: `app/views/.../project_availabilities/list/_widget.html.erb:52-79`; `list/_widget.js.erb:96-201`.

#### Scenario: Padrao global bloqueado
- **GIVEN** um padrao global bloqueado
- **WHEN** o usuario abre o menu de contexto
- **THEN** as acoes aplicaveis a esse estado sao apresentadas, sem menu vazio

> Nota: corrige o legado, onde todo o bloco de itens estava condicionado a `unless at.is_global?` e o menu de um global bloqueado renderizava vazio.

#### Scenario: Abrir o detalhe pela linha
- **GIVEN** um padrao na lista
- **WHEN** o usuario clica na linha
- **THEN** o detalhe do padrao abre

> Nota: corrige o legado, onde o handler chamava `openDetail(id, title)` com `title` **indefinido** nesse escopo (a variavel local era `template`), gerando `ReferenceError` ao clicar. Corrige tambem a mensagem de sucesso que usava a constante inexistente `M.SUCESS`.

### Requirement: FE-146 — Estados visuais do padrao na lista do projeto
Cada linha DEVE (SHALL) indicar visualmente quando o padrao e especifico do projeto, esta bloqueado ou esta desativado, com explicacao consultavel e indentacao por nivel. Fonte legada: `app/views/.../project_availabilities/list/_widget.html.erb:1-40`; `app/frontend/css/pub/components/project_availabilities/widget.scss:1-291`.

#### Scenario: Padrao bloqueado
- **GIVEN** um padrao bloqueado por operacao em andamento
- **WHEN** a linha e apresentada
- **THEN** o bloqueio e visivel e o motivo esta disponivel ao usuario

#### Scenario: Padrao especifico do projeto
- **GIVEN** um padrao criado especificamente no projeto
- **WHEN** a linha e apresentada
- **THEN** um marcador identifica a condicao, com autor e data de criacao consultaveis

> AMBIGUIDADE: no legado existem estilos `.disabled` e `.project_availability_completed` sem nenhum emissor no HTML. Confirmar se havia um estado "concluido" removido do produto.

### Requirement: FE-147 — Formulario de padrao de disponibilidade do projeto
O formulario DEVE (SHALL) oferecer os campos de criacao e deixar claro, na edicao, o que pode ser alterado, com textos do proprio dominio. Fonte legada: `app/views/.../project_availabilities/helper/_body.html.erb:1-107`; `helper/_mount.js.erb:1-135`.

#### Scenario: Texto de estado vazio
- **GIVEN** o painel que nao consegue carregar o padrao pedido
- **WHEN** o estado vazio e apresentado
- **THEN** a mensagem se refere a padrao de disponibilidade

> Nota: corrige o texto herdado do legado ("Essa construtora nao pode ser alterada", copiado de outro produto).

#### Scenario: Dados de outros projetos nao sao expostos
- **GIVEN** o formulario aberto para o projeto A
- **WHEN** o conteudo entregue ao navegador e inspecionado
- **THEN** nenhum padrao de outro projeto esta presente

> Nota: corrige o mesmo vazamento descrito em FE-139.

### Requirement: FE-148 — Preenchimento automatico dos niveis pelo padrao-pai
Ao escolher o padrao-pai, o formulario DEVE (SHALL) derivar e apresentar os niveis superiores, usando apenas padroes do projeto corrente. Fonte legada: `app/views/.../project_availabilities/helper/_body.js.erb:1-39`.

#### Scenario: Escolher o padrao-pai
- **GIVEN** o formulario de novo padrao do projeto
- **WHEN** o usuario escolhe um padrao-pai de segundo nivel
- **THEN** os niveis superiores sao preenchidos automaticamente e apresentados como somente leitura

#### Scenario: Identificador de padrao de outro projeto
- **GIVEN** um cliente que manipula o identificador do padrao-pai para apontar a outro projeto
- **WHEN** o formulario e submetido
- **THEN** a operacao e recusada

> Nota: corrige o vazamento do legado — o filtro usava o JSON completo de todos os padroes de todos os projetos, entao um identificador manipulado preenchia o formulario com dados alheios.

### Requirement: FE-149 — Recarregar a lista de disponibilidades do projeto
A tela DEVE (SHALL) oferecer um unico controle de recarga da lista, funcional. Fonte legada: `app/views/.../project_availabilities/_body.html.erb:31-33`; `_body.js.erb:2-5`, `:137-140`.

#### Scenario: Recarregar a lista
- **GIVEN** a tela de disponibilidades do projeto
- **WHEN** o usuario aciona a recarga
- **THEN** a lista e atualizada

> Nota: corrige o legado, que registrava **dois** handlers — um deles para um seletor inexistente e referenciando a variavel do container antes da declaracao.

### Requirement: DB-120 — Tabela de padroes de disponibilidade
O modelo de dados DEVE (SHALL) conter os padroes de disponibilidade (globais e de projeto) com titulo, escopo, situacao, obrigatoriedade, tipo de operacao, tipo de prazo, cumulatividade, correcao e hierarquia, com chaves estrangeiras e indices. Fonte legada: `db/migrate/20210420180734_create_availability_templates.rb:1-29`.

#### Scenario: Consulta dos padroes ativos de um projeto
- **GIVEN** uma base com muitos projetos e dezenas de padroes por projeto
- **WHEN** os padroes ativos de um projeto sao consultados na ordem hierarquica
- **THEN** a consulta usa indices e responde dentro do limite de performance definido

> Nota: corrige o legado, onde nao havia **nenhum indice e nenhuma chave estrangeira**; os campos booleanos eram inteiros 0/1 e `top_parent_id` tinha default `0` (nao nulo), gerando "orfaos apontando para o id 0".

### Requirement: DB-121 — Padrao global no modelo de dados
O modelo de dados DEVE (SHALL) representar o padrao global, sem projeto associado, com seus descendentes e com os padroes de projeto derivados dele. Fonte legada: `app/models/global_availability_template.rb:1-11`, `:43-70`.

#### Scenario: Verificar se um padrao global tem filhos
- **GIVEN** um padrao global que possui filhos globais
- **WHEN** a existencia de filhos e consultada
- **THEN** a resposta considera os filhos globais

> Nota: corrige o erro de tipagem do legado — `ignore_lock_active_child_templates` estava declarado com `class_name: "ProjectAvailabilityTemplate"` dentro do model **global** (`:10`), fazendo a checagem consultar a classe errada.

### Requirement: DB-122 — Padrao de projeto no modelo de dados
O modelo de dados DEVE (SHALL) representar o padrao especifico de projeto, com projeto obrigatorio, vinculo opcional ao padrao global de origem, estado de bloqueio e estado de tarefa, com restricoes unicas equivalentes as validacoes. Fonte legada: `app/models/project_availability_template.rb:1-26`.

#### Scenario: Titulo unico no mesmo caminho da arvore
- **GIVEN** dois padroes irmaos de terceiro nivel no mesmo projeto
- **WHEN** o segundo e criado com o mesmo titulo do primeiro
- **THEN** a criacao e recusada pelo banco

> Nota: corrige o legado, onde a unicidade era apenas de aplicacao e **nao incluia o terceiro nivel**.

#### Scenario: Um padrao de projeto por padrao global
- **GIVEN** um padrao global ja replicado em um projeto
- **WHEN** uma segunda replicacao do mesmo global e tentada no mesmo projeto
- **THEN** a operacao e recusada pelo banco

### Requirement: DB-123 — Tabela de lancamentos de disponibilidade
O modelo de dados DEVE (SHALL) conter os lancamentos de disponibilidade por projeto, empresa, padrao e data, com valor decimal, chaves estrangeiras e os indices necessarios as consultas por projeto e data. Fonte legada: `db/migrate/20210420180813_create_availability_entries.rb:1-13`.

#### Scenario: Consulta da grade de uma data
- **GIVEN** uma base com centenas de milhares de lancamentos
- **WHEN** os lancamentos de um projeto, empresa e data sao consultados
- **THEN** a consulta usa indices e responde dentro do limite de performance definido

> Nota: corrige o legado, que nao tinha **nenhum indice e nenhuma chave estrangeira** na maior tabela do modulo. Indices necessarios: por projeto e data, por padrao e data, e o unico por projeto, empresa, padrao e data.

### Requirement: DB-124 — Marca de correcao por dias uteis no padrao
O modelo de dados DEVE (SHALL) representar, no padrao, se o valor lancado e corrigido pela proporcao de dias uteis. Fonte legada: `db/migrate/20220818194956_add_is_adjusted_column_to_availability_templates.rb:1-5`.

#### Scenario: Leitura da marca de correcao
- **GIVEN** um padrao marcado como corrigido
- **WHEN** o registro e lido
- **THEN** a marca e devolvida como valor booleano

> Nota: no legado a marca e um inteiro 0/1; migrar como booleano, atento ao par obrigatorio com o valor originalmente digitado (DB-125).

### Requirement: DB-125 — Valor originalmente digitado no lancamento
O modelo de dados DEVE (SHALL) preservar o valor como o usuario o digitou, ao lado do valor corrigido, para os padroes corrigidos por dias uteis. Fonte legada: `db/migrate/20220818201713_add_original_value_column_to_availability_entries.rb:1-5`; `app/models/availability_entry.rb:20`, `:193`.

#### Scenario: Migracao de lancamentos ja corrigidos
- **GIVEN** lancamentos legados de padroes corrigidos cujo valor original esta zerado ou ja contaminado por reaplicacoes da correcao
- **WHEN** a migracao de dados roda
- **THEN** os casos divergentes sao reportados no dry-run antes de qualquer insercao

> AMBIGUIDADE: D-02 — o decaimento composto descrito em BE-127 significa que parte da base pode ter valor corrigido multiplas vezes. A reconstrucao (`original_value = value / multiplicador`) so pode ser aplicada apos a decisao sobre corrigir ou replicar o comportamento.

### Requirement: DB-126 — Empresa do lancamento e consolidacao geral
O modelo de dados DEVE (SHALL) distinguir explicitamente o lancamento de uma empresa do registro de consolidacao geral do projeto. Fonte legada: `db/migrate/20220818150945_add_company_column_to_availability_entries.rb:1-9`; `app/models/availability_entry.rb:40-53`.

#### Scenario: Identificar um registro de consolidacao
- **GIVEN** um registro de consolidacao geral e um lancamento de empresa
- **WHEN** ambos sao lidos
- **THEN** e possivel distingui-los de forma explicita, sem inferir pela ausencia de empresa

> Nota: no legado a relacao consolidacao-lancamento e implicita (empresa nula), sem chave estrangeira e sem coluna de marcacao; a migration usa `after:`, sintaxe especifica de MySQL, embora o banco seja PostgreSQL (DEC-05). Existe ainda a rotina manual `fix__7412`, que reatribui lancamentos de empresa nula a primeira empresa do projeto (OPS-129) — a migracao precisa distinguir consolidacao legitima de dado sujo.

### Requirement: DB-127 — Saldo acumulado persistido no lancamento
O modelo de dados DEVE (SHALL) manter o saldo acumulado de cada lancamento consistente com o calculo definido. Fonte legada: `db/migrate/20210804175519_add_virtual_value_to_availability_entries.rb:1-5`; `app/models/availability_entry.rb:199-223`.

#### Scenario: Reconciliacao do saldo
- **GIVEN** uma base migrada com saldos acumulados persistidos
- **WHEN** a rotina de reconciliacao recalcula os saldos
- **THEN** as divergencias sao reportadas

> Nota: e um valor derivado persistido — no legado pode divergir do calculo quando um recalculo falha no meio (BE-129).

### Requirement: DB-128 — Estado de bloqueio do padrao
O modelo de dados DEVE (SHALL) representar o bloqueio temporario de um padrao com o motivo e o instante, de forma que nenhum padrao permaneca bloqueado apos o fim da operacao. Fonte legada: `db/migrate/20220224142653_add_locked_to_availability_templates.rb:1-6`; `20220325134030_add_locked_message_to_availability_template.rb:1-5`.

#### Scenario: Padroes bloqueados na migracao
- **GIVEN** padroes legados que ficaram bloqueados por falha de job
- **WHEN** a migracao de dados roda
- **THEN** eles sao reportados e migram desbloqueados

> Nota: corrige D-05/BE-147 (legado: nao havia caminho de destravamento apos falha).

### Requirement: DB-129 — Estado das tarefas do padrao
O modelo de dados DEVE (SHALL) representar o estado das operacoes em segundo plano sobre um padrao em um conjunto estavel de valores, com o relato de falha estruturado. Fonte legada: `db/migrate/20220225133130_add_job_info_to_availability_template.rb:1-7`.

#### Scenario: Estado de uma tarefa
- **GIVEN** uma operacao em segundo plano concluida com falha
- **WHEN** o estado e lido
- **THEN** o estado pertence ao conjunto conhecido e a mensagem de falha e legivel

> Nota: corrige o legado, onde o estado era texto livre em pt-BR ("Pendente", "Em progresso", "Concluido" sem acento, "Falhou"), o relato era um array Ruby atribuido a uma coluna de texto, e a referencia apontava para a tabela do executor de tarefas, que e purgada — deixando a referencia pendurada.

### Requirement: DB-130 — Marca de gestao Safegold no lancamento
O modelo de dados DEVE (SHALL) definir de forma unica como a marca de gestao Safegold se relaciona com o lancamento de disponibilidade. Fonte legada: `db/migrate/20210511211918_add_safegold_managed_bool_to_projects.rb:4`; `app/models/availability_entry.rb:17`.

#### Scenario: Consulta historica filtrada pela marca
- **GIVEN** lancamentos anteriores e posteriores a uma alteracao da marca no projeto
- **WHEN** um relatorio filtra lancamentos pela marca
- **THEN** o resultado corresponde a regra definida

> AMBIGUIDADE: D-30 — no legado a marca e reescrita a cada validacao do lancamento a partir do projeto, mas quando a flag muda no projeto **so `companies`** e atualizado em massa; os lancamentos ficam com o carimbo do momento em que foram tocados pela ultima vez. Decidir entre derivar do projeto ou manter carimbo historico explicito (ver DB-090 na capacidade `projects`).

### Requirement: DB-131 — Representacao da hierarquia dos padroes
O modelo de dados DEVE (SHALL) representar a hierarquia e a ordem dos padroes por uma unica estrutura ordenavel corretamente. Fonte legada: `db/migrate/20210420180734_create_availability_templates.rb:15-25`.

#### Scenario: Ordenacao com mais de nove irmaos
- **GIVEN** um nivel com doze padroes irmaos
- **WHEN** eles sao ordenados
- **THEN** a ordem apresentada e 1, 2, ..., 10, 11, 12

> Nota: corrige o legado, onde a posicao era uma string ("1.2.3") ordenada lexicograficamente — com dez ou mais itens no mesmo nivel, "10" vinha antes de "2". A hierarquia era mantida por **nove colunas redundantes**, todas atualizadas por callbacks e importacoes em massa sem validacao.

### Requirement: DB-132 — Opcao de inserir o padrao global nos projetos existentes
O modelo de dados DEVE (SHALL) representar, por padrao global, se ele deve ser inserido nos projetos ja existentes, e essa opcao DEVE (SHALL) ser controlavel pelo usuario. Fonte legada: `db/migrate/20210420180734_create_availability_templates.rb:21`; `app/models/global_availability_template.rb:27`.

#### Scenario: Criar um padrao global sem propagar
- **GIVEN** o formulario de novo padrao global com a opcao de propagacao desmarcada
- **WHEN** o padrao e criado
- **THEN** ele nao e inserido nos projetos existentes e nenhuma tarefa por projeto e enfileirada

> Nota: corrige o legado, onde a coluna tinha default 1 e nao era exposta em tela nem nos parametros permitidos — **toda** criacao propagava para todos os projetos (BE-134/OPS-121).

### Requirement: DB-133 — Integridade referencial e unicidade das tabelas de disponibilidade
As tabelas de padroes e de lancamentos DEVEM (SHALL) nascer com chaves estrangeiras, colunas obrigatorias e indices unicos que reflitam as regras de negocio. Fonte legada: migrations de `availability_templates` e `availability_entries`.

#### Scenario: Limpeza antes das restricoes
- **GIVEN** dados legados com lancamentos duplicados, padroes orfaos e referencias ao id zero
- **WHEN** a migracao de dados roda
- **THEN** a etapa de limpeza e deduplicacao reporta e trata esses casos antes de aplicar as restricoes

> Nota: corrige o legado, onde nao havia nenhum `add_index`, nenhum `add_foreign_key` e nenhum `null: false` — toda a integridade era de aplicacao.

### Requirement: DB-134 — Coluna inexistente referenciada em codigo
A migracao NAO DEVE (SHALL NOT) portar codigo que dependa de estrutura inexistente no esquema de origem. Fonte legada: `app/controllers/pub/availability_templates_controller.rb:22`; `app/views/.../availability_templates/list/_child_widget.html.erb:4`, `:40`.

#### Scenario: Introspecao do esquema de origem
- **GIVEN** o codigo legado que ordena por `default_position`
- **WHEN** a etapa de introspecao do esquema real roda
- **THEN** o relatorio informa se a coluna existe no banco de producao ou nao

> AMBIGUIDADE: D-06 — `default_position` **nao e criada por nenhuma migration**, e e uma das duas provas registradas no DEC-04 de que o banco real pode ter estrutura fora do versionamento. Confirmar contra o banco de producao. O parcial `_child_widget.html.erb` que a usa nao e renderizado por ninguem — codigo morto, nao portado.

### Requirement: DB-135 — Ausencia de esquema consolidado no legado
A migracao de dados DEVE (SHALL) comecar por uma introspecao do esquema real de origem e abortar com relatorio quando encontrar estrutura desconhecida. Fonte legada: `db/` do legado (sem `schema.rb` nem `structure.sql`).

#### Scenario: Estrutura desconhecida no banco de origem
- **GIVEN** o banco legado contem coluna, indice ou tabela que nenhuma migration cria
- **WHEN** a etapa de introspecao roda
- **THEN** o processo aborta e o relatorio lista a estrutura desconhecida

> Nota: DEC-04 — seguimos apenas com as migrations, com o risco registrado e mitigado pela introspecao no dry-run.

### Requirement: OPS-120 — Semeadura dos padroes globais em projeto novo
A criacao de projeto DEVE (SHALL) replicar a arvore completa de padroes globais para o projeto, de forma atomica, idempotente e com falha visivel. Fonte legada: `lib/create_global_template_for_project_job.rb:1-59`; `app/models/project.rb:82-88`, `:312-347`.

#### Scenario: Falha no meio da semeadura
- **GIVEN** uma falha durante a replicacao dos padroes globais para um projeto novo
- **WHEN** a falha ocorre
- **THEN** a tarefa e reexecutada conforme a politica de retentativa; esgotadas as tentativas, o projeto nao fica parcialmente semeado e a falha e visivel

> Nota: corrige D-05 (legado: o `rescue` engolia a excecao, gravava "Falhou" e **nao relancava** — o executor considerava o job bem-sucedido e nao havia retry; alem disso a replicacao dependia da ordem de criacao dos globais e um pai criado depois do filho gerava `NoMethodError` no meio, deixando o projeto parcialmente semeado sem rollback).

#### Scenario: Reexecucao nao duplica
- **GIVEN** uma semeadura ja concluida para um projeto
- **WHEN** a tarefa e executada de novo
- **THEN** nenhum padrao duplicado e criado e nenhum erro silencioso ocorre

#### Scenario: Correcao por dias uteis replicada
- **GIVEN** um padrao global marcado como corrigido por dias uteis
- **WHEN** ele e replicado para um projeto novo
- **THEN** o padrao do projeto tambem nasce marcado como corrigido

> Nota: corrige o legado, onde `is_adjusted` **nao era copiado** na lista de atributos (`project.rb:319-340`) — os padroes de projeto nasciam sempre nao ajustados, mesmo derivando de um global ajustado.

### Requirement: OPS-121 — Propagacao de um padrao global novo para projetos existentes
A criacao de um padrao global DEVE (SHALL) propaga-lo aos projetos existentes conforme a opcao escolhida, com progresso por projeto, idempotencia e falha visivel, copiando fielmente os atributos do global. Fonte legada: `lib/insert_global_template_on_projects_job.rb:1-60`; `app/models/project.rb:349-379`.

#### Scenario: Progresso por projeto nao se atropela
- **GIVEN** um padrao global sendo propagado para cinquenta projetos
- **WHEN** as tarefas rodam em paralelo
- **THEN** o progresso de cada projeto e observavel separadamente

> Nota: corrige o legado, onde cada tarefa sobrescrevia o mesmo campo de progresso do projeto e, em criacao de globais em lote, os estados se atropelavam.

#### Scenario: Atributos copiados fielmente
- **GIVEN** um padrao global nao obrigatorio e corrigido por dias uteis
- **WHEN** ele e propagado a um projeto existente
- **THEN** o padrao do projeto reflete a obrigatoriedade e a correcao do global

> Nota: corrige duas divergencias do legado — a obrigatoriedade era **forcada a 1** (`project.rb:359`, divergindo de OPS-120, que copiava) e `is_adjusted` nao era copiado.

#### Scenario: Falha na propagacao
- **GIVEN** uma falha ao propagar o padrao a um projeto
- **WHEN** ela ocorre
- **THEN** a tarefa e reexecutada e, esgotadas as tentativas, a falha fica visivel

> Nota: corrige D-05 (legado: mesma politica de engolir excecao, sem retry; a unicidade evitava duplicata visivel mas a criacao falhava em silencio e a tarefa reportava sucesso).

### Requirement: OPS-122 — Processamento da ativacao de padrao do projeto
A ativacao de padrao DEVE (SHALL) ser processada em segundo plano com retentativa, progresso observavel, liberacao garantida do bloqueio e falha visivel, sem efeitos colaterais no processo de execucao. Fonte legada: `lib/project_availability_template_activate_job.rb:1-62`; `app/models/project_availability_template.rb:702-742`.

#### Scenario: Falha durante o recalculo
- **GIVEN** uma ativacao que falha durante o recalculo dos lancamentos
- **WHEN** a falha ocorre
- **THEN** o bloqueio do padrao e dos descendentes e liberado, a falha fica visivel e o processo de execucao continua integro para as demais tarefas

> Nota: corrige D-05 (legado: sem retry, sem destravamento na falha e — por a restauracao do logger ficar dentro do bloco protegido — uma falha deixava o **logger global desligado** para o worker inteiro).

### Requirement: OPS-123 — Processamento da desativacao de padrao do projeto
A desativacao de padrao DEVE (SHALL) ser processada em segundo plano com retentativa, liberacao garantida do bloqueio, falha visivel e reconsolidacao dos totais das datas afetadas. Fonte legada: `lib/project_availability_template_deactivate_job.rb:1-62`; `app/models/project_availability_template.rb:744-796`.

#### Scenario: Pai sem lancamento na data
- **GIVEN** uma desativacao cujo padrao-pai nao tem lancamento em alguma das datas afetadas
- **WHEN** a reconsolidacao roda
- **THEN** a tarefa conclui normalmente, sem erro interno

> Nota: corrige o legado, que chamava `recalculate_entry.id` sem checar nulo (`:768`) e abortava com `NoMethodError`.

#### Scenario: Falha na desativacao
- **GIVEN** uma falha durante o processamento
- **WHEN** ela ocorre
- **THEN** o bloqueio e liberado e a falha fica visivel

> Nota: corrige D-05.

### Requirement: OPS-124 — Processamento da remocao de padrao do projeto
A remocao de padrao DEVE (SHALL) ser processada em segundo plano de forma atomica, com retentativa, falha visivel e sem deixar dado parcialmente apagado. Fonte legada: `lib/project_availability_template_removal_job.rb:1-61`; `app/models/project_availability_template.rb:619-700`.

#### Scenario: Falha no meio da remocao
- **GIVEN** uma remocao que falha depois de ja ter apagado parte da subarvore e dos lancamentos
- **WHEN** a falha ocorre
- **THEN** nenhuma alteracao permanece e a falha fica visivel

> Nota: corrige D-05 e a ausencia de transacao (legado: destrutivo e irreversivel; os padroes e lancamentos ja apagados nao voltavam e o recalculo podia nao ter ocorrido, deixando totais errados). Corrige tambem duas falhas silenciosas: a gravacao final do estado era feita sobre um registro ja destruido (0 linhas afetadas, estado "Concluido" nunca persistido) e a desestruturacao do retorno de `background_remove_templates` produzia um valor nulo que sobrevivia ao achatamento da lista.

#### Scenario: Reexecucao apos conclusao
- **GIVEN** uma remocao ja concluida
- **WHEN** a tarefa e reexecutada
- **THEN** ela termina sem erro, reconhecendo que nao ha o que remover

### Requirement: OPS-125 — Infraestrutura de execucao das tarefas de disponibilidade
As tarefas em segundo plano do modulo DEVEM (SHALL) expor tipo, entidade, autor e progresso, com politica de retentativa e retencao definida. Fonte legada: `lib/*_job.rb`; `app/models/project_availability_template.rb:7`, `:829-841`.

#### Scenario: Acompanhamento de uma tarefa
- **GIVEN** uma tarefa de disponibilidade em andamento
- **WHEN** o usuario consulta o acompanhamento
- **THEN** o tipo da operacao, a entidade afetada, o autor e o percentual de progresso sao apresentados

### Requirement: OPS-126 — Trilha de auditoria do modulo de disponibilidade
O sistema DEVE (SHALL) registrar em trilha de auditoria a solicitacao, o inicio e o desfecho de cada operacao de ativacao, desativacao, remocao e replicacao de padroes. Fonte legada: `lib/tracking_facade.rb:15-295`; `app/controllers/pub/project_availabilities_controller.rb:72,91,110`.

#### Scenario: Consulta da trilha de um padrao
- **GIVEN** um padrao que passou por ativacao e desativacao
- **WHEN** a trilha e consultada por um usuario autorizado
- **THEN** os marcos de solicitacao, inicio e desfecho aparecem com descricao em pt-BR

#### Scenario: Trilha exige autorizacao
- **GIVEN** um cliente sem autorizacao para o projeto
- **WHEN** ele consulta a trilha
- **THEN** a resposta e 403 ou 404

### Requirement: OPS-127 — Progresso das operacoes visivel ao usuario
O progresso das operacoes de disponibilidade DEVE (SHALL) ser apresentado ao usuario na propria tela, sem recarregamento manual. Fonte legada: `app/models/project_availability_template.rb:797-841`.

#### Scenario: Acompanhar uma ativacao pela tela
- **GIVEN** uma ativacao de padrao em andamento
- **WHEN** o usuario esta com a lista de disponibilidades aberta
- **THEN** o progresso avanca na tela ate a conclusao, quando o padrao volta a ficar utilizavel

> Nota: corrige D-86 e o legado, onde o delegate padrao apenas imprimia no stdout e **nenhuma tela do modulo** consumia o progresso — o unico retorno ao usuario era o cadeado com a mensagem de bloqueio.

### Requirement: OPS-128 — Politica de retentativa e retencao das tarefas
As tarefas de disponibilidade DEVEM (SHALL) ter retentativa automatica em caso de falha e as falhas definitivas DEVEM (SHALL) ficar visiveis para operacao. Fonte legada: `lib/*_job.rb` (todos com `destroy_failed_jobs? false` e `rescue` que engole a excecao).

#### Scenario: Falha transitoria
- **GIVEN** uma tarefa que falha por indisponibilidade momentanea do banco
- **WHEN** a falha ocorre
- **THEN** a tarefa e reexecutada automaticamente e conclui com sucesso

> Nota: corrige D-05 (legado: **nenhum** dos cinco jobs tinha retry — o `rescue` engolia a excecao, entao o executor nunca marcava o job como falho nem reagendava; a falha so aparecia no estado gravado na entidade).

#### Scenario: Falha definitiva
- **GIVEN** uma tarefa que falha em todas as tentativas
- **WHEN** a ultima tentativa termina
- **THEN** a falha fica registrada e visivel, com o motivo, e a entidade afetada nao permanece bloqueada

### Requirement: OPS-129 — Rotinas de conserto de dados do modulo de disponibilidade
As correcoes de dados do modulo DEVEM (SHALL) ser operacoes idempotentes, auditadas, com pre-visualizacao e com protecao contra execucao destrutiva acidental. Fonte legada: `app/models/availability_entry.rb:245-250`; `app/models/project_availability_template.rb:603-612`; `app/models/global_availability_template.rb:477-498`; `app/models/availability_template.rb:173-177`.

#### Scenario: Correcao de padroes orfaos
- **GIVEN** padroes de projeto que referenciam um padrao global ja removido
- **WHEN** a rotina de correcao e executada
- **THEN** ela reporta o que sera alterado antes de alterar, registra o resultado e pode ser executada de novo sem efeito adicional

> Nota: corrige o legado, onde essas rotinas rodavam a mao no console de producao, sem log persistente e sem idempotencia real — e onde `destroy_existing` apagava **todos** os lancamentos e **todos** os padroes sem nenhuma guarda. A propria existencia dessas rotinas indica que os fluxos automaticos deixam inconsistencias recorrentes.
