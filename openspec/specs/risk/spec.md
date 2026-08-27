# Risk Specification

## Purpose
Controle de risco de crédito do Safegold: os limites (`risk_controls`) por empresa,
portador e tipo de operação; as operações de risco que consomem esses limites, com sua
cadeia de movimentações, renovações e prorrogações; os catálogos de tipos de limite e de
movimentação; e o painel de exposição que mostra, para uma data, quanto de cada limite
está utilizado, disponível, liquidável e em pré-faturamento.

> Convenção de sinal: por DEC-01 o ai9 **replica exatamente** a convenção de sinal do
> legado — `original_balance` forçado a negativo, débitos somando e créditos subtraindo
> no saldo, e a multiplicação por `-1` na apuração do limite utilizado. Os cenários deste
> documento travam os números atuais do legado; inverter a convenção depois passa a ser
> uma mudança deliberada, com os testes apontando exatamente o que muda.

## Requirements

### Requirement: BE-230 — Buscar e listar limites
O sistema SHALL se comportar conforme os cenários desta seção.
`GET` de busca de limites lista os `RiskControl` do projeto corrente com filtros por tipo,
portador e empresa, e paginação. Fonte legada:
`app/controllers/pub/risk_controls_controller.rb:9-25`; `config/routes.rb:156`.

#### Scenario: Listagem escopada ao projeto corrente
- **GIVEN** limites em `P1` e `P2` e um usuário cujo projeto corrente é `P1`
- **WHEN** a busca é executada
- **THEN** só os limites de `P1` são retornados, ordenados pelo título do portador, com o total correto de registros

#### Scenario: Filtros combinados
- **GIVEN** limites de vários tipos e portadores
- **WHEN** a busca filtra por tipo de operação e por empresa
- **THEN** só os limites que casam com os dois filtros são retornados

#### Scenario: Busca textual por portador
- **GIVEN** um limite do portador "Banco Alfa"
- **WHEN** a busca informa o termo "alfa"
- **THEN** o limite é retornado
> Nota: corrige comportamento legado (o parâmetro de busca textual era lido e nunca aplicado ao filtro, então a mensagem de "nenhum resultado para a busca" nunca podia aparecer — ver FE-249)

### Requirement: BE-231 — Resumo de exposição por limite numa data
O sistema SHALL se comportar conforme os cenários desta seção.
O endpoint de resumo agrega a exposição do projeto ou de uma empresa numa data, opcionalmente
recortada por portador. Fonte legada: `app/controllers/pub/risk_controls_controller.rb:27-46`.

#### Scenario: Resumo do projeto inteiro
- **GIVEN** nenhuma empresa informada
- **WHEN** o resumo é solicitado para hoje
- **THEN** a resposta agrega todos os limites ativos do projeto corrente

#### Scenario: Resumo de uma empresa
- **GIVEN** uma empresa informada
- **WHEN** o resumo é solicitado
- **THEN** a resposta agrega apenas os limites daquela empresa

#### Scenario: Portador informado troca o recorte
- **GIVEN** um portador informado
- **WHEN** o resumo é solicitado
- **THEN** a resposta vem no formato de portador único, com uma linha por tipo de limite

#### Scenario: Portador inexistente
- **GIVEN** um identificador de portador que não existe
- **WHEN** o resumo é solicitado
- **THEN** a resposta é 404, e não um erro interno
> Nota: corrige comportamento legado (a busca do portador levantava exceção não tratada e devolvia 500)

### Requirement: BE-232 — Combos auxiliares de limite
O sistema SHALL se comportar conforme os cenários desta seção.
Dois endpoints alimentam os seletores de portador do formulário e do filtro de limites.
Fonte legada: `app/controllers/pub/risk_controls_controller.rb:89-115`.

#### Scenario: Portadores para o formulário de limite
- **GIVEN** uma empresa informada
- **WHEN** os portadores são solicitados para o formulário
- **THEN** vêm todos os portadores do projeto da empresa, inclusive os que ainda não têm limite

#### Scenario: Portadores para o filtro
- **GIVEN** uma empresa com limites ativos e inativos
- **WHEN** os portadores são solicitados para o filtro
- **THEN** vêm apenas os portadores com limite ativo, sem repetição

#### Scenario: Empresa inexistente
- **GIVEN** um identificador de empresa inválido
- **WHEN** qualquer um dos dois é solicitado
- **THEN** a resposta é 404, e não um erro interno
> Nota: corrige comportamento legado (empresa nula levava a `NoMethodError` e 500)

### Requirement: BE-233 — Abrir o formulário de limite e rotas REST mortas
O sistema SHALL se comportar conforme os cenários desta seção.
As ações de novo e edição montam o formulário lateral; as ações REST de índice e detalhe
apontam para templates inexistentes. Fonte legada:
`app/controllers/pub/risk_controls_controller.rb:5-7`, `:48-54`, `:56-72`.

#### Scenario: Formulário de novo limite
- **GIVEN** o usuário acionando o cadastro
- **WHEN** o formulário é montado
- **THEN** ele vem vinculado ao projeto corrente, com empresa, portador e tipo editáveis

#### Scenario: Formulário de edição
- **GIVEN** um limite existente
- **WHEN** o formulário é aberto para edição
- **THEN** empresa, portador e tipo não são editáveis

#### Scenario: Rotas REST mortas não são portadas
- **GIVEN** as ações de índice e detalhe do controller legado
- **WHEN** o escopo do ai9 é definido
- **THEN** elas não existem, e as telas são servidas pela navegação do console
> Nota: DEC-09 — nenhum dos dois templates existe no repositório legado; as rotas entram no ledger como `dropped` com evidência

### Requirement: BE-234 — Criar limite
O sistema SHALL se comportar conforme os cenários desta seção.
A criação de um `RiskControl` define o teto e a taxa para a trinca empresa, portador e
tipo de operação. Fonte legada: `app/controllers/pub/risk_controls_controller.rb:74-87`.

#### Scenario: Criação bem-sucedida
- **GIVEN** empresa, portador, tipo, limite e taxa informados
- **WHEN** o limite é criado
- **THEN** o registro é persistido com o autor da sessão e fica ativo

#### Scenario: Erros com nomes de campo corretos
- **GIVEN** uma criação recusada por falta de portador
- **WHEN** a resposta é apresentada
- **THEN** a mensagem identifica o campo como "Portador"
> Nota: corrige comportamento legado (a tabela de tradução trazia o rótulo "Potador")

#### Scenario: Falha de criação não deixa efeitos
- **GIVEN** uma criação recusada por validação
- **WHEN** ela é processada
- **THEN** nenhum registro e nenhuma operação automática são criados
> Nota: corrige comportamento legado (o controller chamava destruição sobre um registro nunca persistido, sinalizando uma intenção de rollback que não existia)

### Requirement: BE-235 — Atualizar limite
O sistema SHALL se comportar conforme os cenários desta seção.
A edição altera o teto, a taxa e a situação, preservando a identidade da trinca. Fonte
legada: `app/controllers/pub/risk_controls_controller.rb:118-131`.

#### Scenario: Edição do teto e da taxa
- **GIVEN** um limite existente
- **WHEN** o teto e a taxa são alterados
- **THEN** os novos valores passam a valer nos cálculos de exposição, em uma única gravação
> Nota: corrige comportamento legado (o `update` era seguido de um `save` redundante)

#### Scenario: Tentativa de trocar empresa, portador ou tipo
- **GIVEN** um limite com operações já criadas
- **WHEN** uma requisição direta tenta trocar o tipo de operação
- **THEN** a alteração é recusada
> Nota: corrige comportamento legado (os três campos continuavam no `permit` mesmo com o formulário desabilitando-os; trocar o tipo orfanava as operações, que resolvem o limite pela quádrupla projeto, empresa, portador e tipo)

### Requirement: BE-236 — Ativar limite
O sistema SHALL se comportar conforme os cenários desta seção.
A ativação recoloca o limite nos agregados de exposição. Fonte legada:
`app/controllers/pub/risk_controls_controller.rb:134-145`; `app/models/risk_control.rb:81-84`.

#### Scenario: Ativação
- **GIVEN** um limite desativado
- **WHEN** ele é ativado
- **THEN** ele volta a aparecer no resumo de exposição e a somar nos agregados por tipo

#### Scenario: Falha de ativação é reportada
- **GIVEN** uma ativação que não pode ser gravada
- **WHEN** ela é executada
- **THEN** a resposta é um erro, e o limite continua desativado
> Nota: corrige comportamento legado (a gravação sem bang deixava a falha passar em silêncio e o retorno ainda era de sucesso)

### Requirement: BE-237 — Desativar limite
O sistema SHALL se comportar conforme os cenários desta seção.
A desativação retira o limite dos agregados de exposição sem encerrar as operações
existentes. Fonte legada: `app/controllers/pub/risk_controls_controller.rb:147-158`.

#### Scenario: Desativação
- **GIVEN** um limite ativo com operações
- **WHEN** ele é desativado
- **THEN** ele deixa de aparecer no resumo de exposição

#### Scenario: Operações do limite desativado
- **GIVEN** o mesmo limite desativado
- **WHEN** o usuário abre a tela de operações de risco
- **THEN** as operações continuam listadas
> AMBIGUIDADE: no legado existem duas fontes divergentes de "operações do limite" — a do próprio limite ignora a situação e a da empresa passa por limites ativos, então a mesma operação some do resumo e permanece na lista; confirmar qual é o comportamento correto ao desativar

### Requirement: BE-238 — Excluir limite
O sistema SHALL se comportar conforme os cenários desta seção.
O limite só pode ser removido quando não tem operações nem posições vinculadas. Fonte
legada: `app/controllers/pub/risk_controls_controller.rb:160-171`; `app/models/risk_control.rb:5-6`.

#### Scenario: Exclusão de limite sem dependências
- **GIVEN** um limite sem operações e sem posições
- **WHEN** a exclusão é confirmada
- **THEN** o limite é removido

#### Scenario: Exclusão barrada por dependências
- **GIVEN** um limite com operações vinculadas
- **WHEN** a exclusão é tentada
- **THEN** a resposta é um erro que explica a dependência, e não um sucesso parcial
> Nota: corrige D-24 (comportamento legado: a falha voltava com status de aceito, tratado pela tela como sucesso parcial)

### Requirement: BE-239 — Normalização automática do limite
O sistema SHALL se comportar conforme os cenários desta seção.
Antes de validar, o limite copia o título do portador, resolve o projeto pela empresa e
herda o carimbo de gestão. Fonte legada: `app/models/risk_control.rb:12-16`.

#### Scenario: Derivações na gravação
- **GIVEN** uma empresa do projeto `P1` e o portador "Banco Alfa"
- **WHEN** o limite é gravado
- **THEN** `title = "Banco Alfa"`, `project_id = P1` e o carimbo de gestão é herdado da empresa

#### Scenario: Empresa ausente
- **GIVEN** uma gravação sem empresa
- **WHEN** ela é submetida
- **THEN** a resposta é 422 pela validação de presença, e não um erro interno
> Nota: corrige comportamento legado (a normalização acessava o projeto da empresa nula e levantava `NoMethodError` antes de as validações rodarem)

#### Scenario: Portador renomeado
- **GIVEN** um limite cujo portador foi renomeado
- **WHEN** o limite é consultado
- **THEN** o título exibido acompanha o nome atual do portador
> Nota: corrige comportamento legado (o título era cópia desnormalizada, reconciliada apenas por rotina manual — ver OPS-236)

### Requirement: BE-240 — Validações e unicidade do limite
O sistema SHALL se comportar conforme os cenários desta seção.
Existe no máximo um limite por trinca empresa, portador e tipo de operação. Fonte legada:
`app/models/risk_control.rb:4`, `:66-71`.

#### Scenario: Trinca duplicada
- **GIVEN** um limite já existente para a trinca
- **WHEN** outro limite é criado para a mesma trinca
- **THEN** a criação é recusada por unicidade, inclusive em requisições simultâneas
> Nota: corrige D-103 (comportamento legado: a unicidade era só da aplicação, sem índice único no banco)

#### Scenario: Campos obrigatórios
- **GIVEN** um payload sem tipo de operação
- **WHEN** a criação é submetida
- **THEN** a resposta é 422

#### Scenario: Limite zero
- **GIVEN** um limite com teto zero
- **WHEN** ele é criado
- **THEN** é aceito, e o percentual de utilização usa o ramo protegido de divisão por zero
> AMBIGUIDADE: teto zero passa na validação de presença por causa do valor padrão do banco; confirmar se o ai9 deve exigir teto maior que zero

### Requirement: BE-241 — Abertura automática do par de operações estáticas
O sistema SHALL se comportar conforme os cenários desta seção.
Ao criar um limite de tipo com pré-faturamento, o sistema abre duas operações estáticas
ligadas entre si: a de pré-faturamento e a de antecipação. Fonte legada:
`app/models/risk_control.rb:18-64`.

#### Scenario: Par criado com os saldos do limite
- **GIVEN** um tipo com pré-faturamento e um limite com saldo inicial liquidável 50.000,00 e saldo inicial pré 30.000,00
- **WHEN** o limite é criado
- **THEN** são criadas duas operações com valor de operação zero, saldo zero, taxa igual à do limite, observação "Criado automaticamente para o limite" e vínculo cruzado entre elas; a de pré recebe saldo inicial 30.000,00 e a de antecipação, 50.000,00

#### Scenario: Operações estáticas ficam sempre dentro da janela
- **GIVEN** o par recém-criado
- **WHEN** a exposição é apurada para qualquer data
- **THEN** as duas operações são consideradas vigentes
> Nota: DEC-01 — comportamento legado preservado; no legado a janela é obtida gravando emissão e vencimento com as datas-sentinela de hoje menos e mais 2000 anos (OPS-233)

#### Scenario: Tipo sem os dois subtipos
- **GIVEN** um tipo marcado com pré-faturamento cujo subtipo de pré foi removido
- **WHEN** um limite é criado
- **THEN** a criação é recusada com erro explicativo e nada é persistido
> Nota: corrige comportamento legado (o limite já estava gravado quando a busca do subtipo levantava `NoMethodError`, e as criações das operações não eram verificadas — o limite ficava sem par em silêncio)

### Requirement: BE-242 — Janela temporal das operações vigentes numa data
O sistema SHALL se comportar conforme os cenários desta seção.
Uma operação entra na apuração de um dia quando esse dia está no intervalo fechado entre
emissão e vencimento. Fonte legada: `app/models/risk_control.rb:76-79`;
`app/models/company.rb:20-23`.

#### Scenario: Data dentro da janela
- **GIVEN** uma operação com emissão em 01/03/2026 e vencimento em 30/04/2026
- **WHEN** a exposição é apurada para 15/03/2026
- **THEN** a operação é considerada

#### Scenario: Data nos extremos
- **GIVEN** a mesma operação
- **WHEN** a exposição é apurada para 01/03/2026 e para 30/04/2026
- **THEN** ela é considerada nos dois dias

#### Scenario: Operação encerrada continua na janela
- **GIVEN** uma operação marcada como encerrada, dentro da janela
- **WHEN** a exposição é apurada
- **THEN** ela continua sendo considerada
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; a apuração não filtra por operação encerrada

### Requirement: BE-243 — Limite utilizado numa data
O sistema SHALL se comportar conforme os cenários desta seção.
O limite utilizado é a soma dos saldos das operações vigentes na data, multiplicada por
`-1`. Fonte legada: `app/models/risk_control.rb:115-124`.

#### Scenario: Cálculo do utilizado
- **GIVEN** duas operações vigentes com saldo, na data, de −100.000,00 e −50.000,00
- **WHEN** o utilizado é apurado
- **THEN** `limite_utilizado_on = 150.000,00`
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário: `original_balance` é gravado negativo (BE-263), débitos somam e créditos subtraem (BE-265), e o resultado é multiplicado por `-1`; o número travado aqui é exatamente o que o painel mostra hoje

#### Scenario: Operação com saldo devedor positivo
- **GIVEN** uma operação vigente cujo saldo na data é 20.000,00
- **WHEN** o utilizado é apurado
- **THEN** `limite_utilizado_on = −20.000,00`
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; a inversão de sinal é a convenção atual e é replicada como está

#### Scenario: Nenhuma operação vigente
- **GIVEN** um limite sem operações na data
- **WHEN** o utilizado é apurado
- **THEN** `limite_utilizado_on = 0,00`

### Requirement: BE-244 — Limite liquidável numa data
O sistema SHALL se comportar conforme os cenários desta seção.
O liquidável considera somente as operações de subtipo não-pré quando o tipo tem
pré-faturamento. Fonte legada: `app/models/risk_control.rb:126-140`.

#### Scenario: Tipo com pré-faturamento
- **GIVEN** um limite de tipo com pré-faturamento, com uma operação de pré de saldo −30.000,00 e uma de antecipação de saldo −50.000,00
- **WHEN** o liquidável é apurado
- **THEN** `limite_liquidavel_on = 50.000,00`
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário (mesma inversão de sinal de BE-243)

#### Scenario: Tipo sem pré-faturamento
- **GIVEN** um limite de tipo sem pré-faturamento
- **WHEN** liquidável e utilizado são apurados
- **THEN** os dois valores são iguais

### Requirement: BE-245 — Limite de pré-faturamento numa data
O sistema SHALL se comportar conforme os cenários desta seção.
O pré considera somente as operações de subtipo pré, e é zero para tipos sem
pré-faturamento. Fonte legada: `app/models/risk_control.rb:141-156`.

#### Scenario: Tipo com pré-faturamento
- **GIVEN** uma operação de pré com saldo −30.000,00 na data
- **WHEN** o pré é apurado
- **THEN** `limite_pre_on = 30.000,00`
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário

#### Scenario: Tipo sem pré-faturamento
- **GIVEN** um limite de tipo sem pré-faturamento
- **WHEN** o pré é apurado
- **THEN** o resultado é `0`

### Requirement: BE-246 — Limite disponível numa data
O sistema SHALL se comportar conforme os cenários desta seção.
O disponível é o teto do limite menos o utilizado na data. Fonte legada:
`app/models/risk_control.rb:158-160`.

#### Scenario: Cálculo do disponível
- **GIVEN** teto de 500.000,00 e utilizado de 150.000,00
- **WHEN** o disponível é apurado
- **THEN** `limite_disponivel_on = 350.000,00`

#### Scenario: Limite estourado
- **GIVEN** teto de 100.000,00 e utilizado de 150.000,00
- **WHEN** o disponível é apurado
- **THEN** `limite_disponivel_on = −50.000,00`, e é esse sinal negativo que a tela sinaliza como estouro
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; herda integralmente a convenção de sinal de BE-243

### Requirement: BE-247 — Vencidos numa data
O sistema SHALL se comportar conforme os cenários desta seção.
Os vencidos somam os saldos das operações vigentes marcadas como encerradas, sem inverter
o sinal. Fonte legada: `app/models/risk_control.rb:91-101`.

#### Scenario: Soma dos encerrados
- **GIVEN** duas operações vigentes marcadas como encerradas, com saldos de −40.000,00 e −10.000,00
- **WHEN** os vencidos são apurados
- **THEN** o resultado é `−50.000,00`, sem inversão de sinal
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário: "vencido" no legado significa a marcação manual de encerramento, não `due_date` anterior a hoje, e esta apuração não inverte o sinal ao contrário de BE-243/244/245

#### Scenario: Operação vencida por data mas não marcada
- **GIVEN** uma operação cujo vencimento já passou e que não foi marcada como encerrada
- **WHEN** os vencidos são apurados
- **THEN** ela não entra no resultado
> Nota: DEC-01 — D-96 replicado: "vencido" continua sendo flag manual

### Requirement: BE-248 — A vencer numa data
O sistema SHALL se comportar conforme os cenários desta seção.
O a vencer é o complemento de BE-247: soma os saldos das operações vigentes não marcadas
como encerradas. Fonte legada: `app/models/risk_control.rb:103-113`.

#### Scenario: Soma dos não encerrados
- **GIVEN** operações vigentes não encerradas com saldos de −60.000,00 e −20.000,00
- **WHEN** o a vencer é apurado
- **THEN** o resultado é `−80.000,00`, sem inversão de sinal
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário

#### Scenario: Apuração disponível para consumo
- **GIVEN** vencidos e a vencer apurados para uma data
- **WHEN** o painel de risco é montado
- **THEN** os dois valores ficam disponíveis, ainda que hoje nenhuma tela do legado os consuma
> AMBIGUIDADE: D-99 — os dois cálculos não têm nenhum chamador vivo, porque a tela de posições diárias foi removida (BE-269); confirmar se são reintroduzidos ou descartados

### Requirement: BE-249 — Agregados de limite por tipo, na empresa e no projeto
O sistema SHALL se comportar conforme os cenários desta seção.
Para cada tipo de operação, o sistema soma o teto, o utilizado e o disponível dos limites
ativos, e calcula o percentual de utilização. Fonte legada:
`app/models/company.rb:35-42`, `:45-50`, `:52-54`, `:57-66`; `app/models/project.rb:462-493`.

#### Scenario: Agregado por tipo
- **GIVEN** dois limites ativos do mesmo tipo, com tetos de 300.000,00 e 200.000,00 e utilizados de 100.000,00 e 50.000,00
- **WHEN** o agregado do tipo é apurado
- **THEN** o teto total é 500.000,00, o utilizado é 150.000,00, o disponível é 350.000,00 e o percentual utilizado é "30.00%"

#### Scenario: Teto total zero com utilização
- **GIVEN** um tipo cujos limites somam teto zero e utilizado maior que zero
- **WHEN** o percentual é apurado
- **THEN** ele é "100.00%"

#### Scenario: Teto total zero sem utilização
- **GIVEN** um tipo cujos limites somam teto zero e utilizado menor ou igual a zero
- **WHEN** o percentual é apurado
- **THEN** ele é "0.00%"

#### Scenario: Limites inativos fora do agregado
- **GIVEN** um limite desativado do mesmo tipo
- **WHEN** o agregado é apurado
- **THEN** o teto e o utilizado desse limite não entram na conta

### Requirement: BE-250 — Payload detalhado do resumo de risco
O sistema SHALL se comportar conforme os cenários desta seção.
O resumo devolve, por tipo de operação ativo com pelo menos um limite, uma linha por
limite com utilizado, liquidável, pré, disponível, teto, taxa e os percentuais. Fonte
legada: `app/models/company.rb:114-195`; `app/models/project.rb:541+`.

#### Scenario: Estrutura do resumo
- **GIVEN** dois tipos ativos com limites
- **WHEN** o resumo é montado
- **THEN** os tipos vêm ordenados por título e cada um traz suas linhas de limite com os cinco valores e a taxa

#### Scenario: Percentuais por limite
- **GIVEN** um limite com teto 500.000,00 e utilizado 150.000,00
- **WHEN** o resumo é montado
- **THEN** o percentual utilizado da linha é 30

#### Scenario: Teto zero na linha
- **GIVEN** um limite com teto zero
- **WHEN** o resumo é montado
- **THEN** os percentuais da linha são 100

#### Scenario: Colunas liquidável e pré mostram o utilizado
- **GIVEN** um limite com utilizado 150.000,00, liquidável 100.000,00 e pré 50.000,00
- **WHEN** o resumo é montado
- **THEN** as colunas "Liquidavel" e "Pré-Faturamento" trazem o valor do utilizado, 150.000,00, com o percentual próprio ao lado, e o agregado do tipo apresenta esses dois campos como valores monetários exibidos com sufixo de percentual
> Nota: DEC-01 — D-95 replicado como está: os números que a tela mostra hoje ficam travados por estes cenários

### Requirement: BE-251 — Totais consolidados de limite
O sistema SHALL se comportar conforme os cenários desta seção.
O endpoint de totais devolve, por tipo, o teto, o disponível, o utilizado, o liquidável e
o pré com seus percentuais, mais o indicador de existência de limites. Fonte legada:
`app/models/company.rb:68-88`; `app/controllers/pub/companies_controller.rb:70-84`.

#### Scenario: Totais do projeto ou da empresa
- **GIVEN** nenhuma empresa informada
- **WHEN** os totais são solicitados
- **THEN** eles agregam o projeto corrente; informando a empresa, agregam apenas a empresa

#### Scenario: Indicador de limites disponíveis para lançamento
- **GIVEN** um projeto cujos limites ativos não têm operação vigente na data
- **WHEN** os totais são solicitados
- **THEN** o indicador de existência de limites vem ligado

#### Scenario: Campos de liquidável e pré do payload
- **GIVEN** um tipo com utilizado, liquidável e pré distintos
- **WHEN** os totais são montados
- **THEN** os quatro campos de liquidável e pré trazem o mesmo percentual do utilizado
> Nota: DEC-01 — D-95 replicado como está; os números atuais ficam travados por este cenário

### Requirement: BE-252 — Limites livres para lançamento de posição numa data
O sistema SHALL se comportar conforme os cenários desta seção.
São considerados livres os limites ativos que não têm nenhuma operação vigente na data.
Fonte legada: `app/models/company.rb:26-32`; `app/models/project.rb:454-460`.

#### Scenario: Limite sem operação na data
- **GIVEN** um limite ativo cujas operações não estão vigentes na data
- **WHEN** a lista de limites livres é montada
- **THEN** ele aparece, identificado pelo título do portador

#### Scenario: Limite de tipo com pré-faturamento
- **GIVEN** um limite de tipo com pré-faturamento, cujas operações estáticas estão sempre vigentes
- **WHEN** a lista de limites livres é montada
- **THEN** ele nunca aparece
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário
> AMBIGUIDADE: D-99 — a regra inviabiliza lançar posição diária em limites com pré-faturamento; como a tela de posições está removida, confirmar a regra junto com a decisão sobre reintroduzir a funcionalidade

### Requirement: BE-253 — Buscar e listar operações de risco
O sistema SHALL se comportar conforme os cenários desta seção.
A busca de operações do projeto aceita texto, empresa, portador, tipo, período,
ordenação multi-coluna e paginação. Fonte legada:
`app/controllers/pub/risk_operations_controller.rb:15-47`, `:180-215`.

#### Scenario: Listagem escopada e filtrada
- **GIVEN** operações em vários projetos e um usuário do projeto `P1`
- **WHEN** a busca filtra por empresa e período
- **THEN** só operações de `P1` que casam com os filtros são retornadas

#### Scenario: Busca por id não escapa do projeto
- **GIVEN** uma operação do projeto `P2`
- **WHEN** o usuário de `P1` informa o identificador dessa operação na busca
- **THEN** o resultado vem vazio e nenhum dado de `P2` é exposto
> Nota: corrige D-100 (comportamento legado: a relação era substituída por uma consulta direta pelo id, perdendo o escopo de projeto e os joins — vazamento não alcançado por DEC-01, que trata apenas de convenção de sinal)

#### Scenario: Total correto com paginação
- **GIVEN** 300 operações no projeto e uma busca com limite 50
- **WHEN** ela é executada
- **THEN** vêm 50 operações e o total informado é 300
> Nota: corrige D-98 (comportamento legado: o total era contado depois de aplicar limite e deslocamento, então a navegação nunca soube o total real)

#### Scenario: Busca textual
- **GIVEN** operações cujo portador ou título contêm "Alfa"
- **WHEN** a busca informa "alfa"
- **THEN** as duas formas de correspondência são retornadas

#### Scenario: Período ausente
- **GIVEN** uma busca sem data inicial nem final
- **WHEN** ela é executada
- **THEN** nenhuma restrição de período é aplicada
> Nota: corrige comportamento legado das datas-sentinela (OPS-233)

### Requirement: BE-254 — Cascata de filtros do formulário de operação
O sistema SHALL se comportar conforme os cenários desta seção.
Dois modos do mesmo endpoint alimentam os seletores de portador e de tipo de operação.
Fonte legada: `app/controllers/pub/risk_operations_controller.rb:144-161`.

#### Scenario: Portadores da empresa
- **GIVEN** uma empresa informada
- **WHEN** os portadores são solicitados
- **THEN** vêm apenas os portadores com limite ativo de tipo que permite lançamento manual

#### Scenario: Tipos do portador
- **GIVEN** empresa e portador informados
- **WHEN** os tipos são solicitados
- **THEN** vêm apenas os tipos manuais com limite ativo para a combinação

#### Scenario: Modo desconhecido ou identificador inválido
- **GIVEN** um modo fora dos dois conhecidos, ou uma empresa inexistente
- **WHEN** a requisição é processada
- **THEN** a resposta é um erro explícito, e não um seletor vazio nem um erro interno
> Nota: corrige comportamento legado (modo desconhecido devolvia objeto vazio e esvaziava o seletor; identificador inválido levantava exceção não tratada)

### Requirement: BE-255 — Última movimentação da operação
O sistema SHALL se comportar conforme os cenários desta seção.
O endpoint devolve os dados da última movimentação da operação para o cartão do detalhe.
Fonte legada: `app/controllers/pub/risk_operations_controller.rb:163-176`.

#### Scenario: Operação com movimentos
- **GIVEN** uma operação com 5 movimentos
- **WHEN** a última movimentação é solicitada
- **THEN** a resposta traz data, tipo, valor, sinal do tipo de crédito, saldo total e saldo inicial do último movimento da cadeia

#### Scenario: Operação sem movimentos
- **GIVEN** uma operação estática de pré-faturamento recém-criada, sem nenhum movimento
- **WHEN** o detalhe é aberto
- **THEN** a resposta indica ausência de movimentação e a tela carrega normalmente
> Nota: corrige comportamento legado (o acesso ao movimento nulo levantava `NoMethodError` e derrubava a abertura do detalhe com 500)

### Requirement: BE-256 — Criar operação de risco
O sistema SHALL se comportar conforme os cenários desta seção.
A criação registra a operação, resolve o limite, sincroniza tipo e subtipo, aplica a
convenção de sinal do saldo inicial e gera o movimento de liberação. Fonte legada:
`app/controllers/pub/risk_operations_controller.rb:69-83`, `:217-241`.

#### Scenario: Criação bem-sucedida
- **GIVEN** empresa, portador, tipo, contrato, datas, capital e taxa informados
- **WHEN** a operação é criada
- **THEN** ela é persistida com o autor da sessão, o limite resolvido, o saldo inicial armazenado conforme a convenção de sinal e o movimento de liberação criado

#### Scenario: Saldo enviado é sempre recalculado
- **GIVEN** um payload que informa um saldo arbitrário
- **WHEN** a operação é criada
- **THEN** o saldo gravado é o resultado do recálculo da cadeia de movimentos, não o valor enviado

### Requirement: BE-257 — Atualizar operação de risco
O sistema SHALL se comportar conforme os cenários desta seção.
A edição altera os dados da operação e recalcula a cadeia de saldos uma única vez. Fonte
legada: `app/controllers/pub/risk_operations_controller.rb:116-131`.

#### Scenario: Edição com recálculo único
- **GIVEN** uma operação com movimentos
- **WHEN** a observação é alterada
- **THEN** a gravação ocorre uma vez e a cadeia de saldos é recalculada uma vez
> Nota: corrige comportamento legado (a ação fazia até três gravações em sequência, com três recálculos completos)

#### Scenario: Encolher a janela deixando movimentos fora
- **GIVEN** uma operação com movimentos entre 01/03 e 30/04
- **WHEN** o vencimento é alterado para 15/03
- **THEN** a alteração é recusada enquanto houver movimentos fora da nova janela
> Nota: corrige comportamento legado (a validação de janela só rodava ao gravar o movimento, e o recálculo em massa a contornava — era possível deixar movimentos fora da janela da operação sem qualquer aviso)

#### Scenario: Alteração do capital não regenera o movimento de liberação
- **GIVEN** uma operação cujo movimento de liberação foi criado com o capital original
- **WHEN** o capital é alterado
- **THEN** o movimento de liberação existente permanece como está
> AMBIGUIDADE: alterar o capital deixa o movimento de liberação divergente do valor da operação; confirmar se o ai9 deve ajustar o movimento, bloquear a alteração ou manter o comportamento atual

### Requirement: BE-258 — Excluir operação de risco
O sistema SHALL se comportar conforme os cenários desta seção.
A exclusão remove a operação e toda a sua cadeia de movimentos, exceto quando há recibo
emitido. Fonte legada: `app/controllers/pub/risk_operations_controller.rb:133-142`.

#### Scenario: Exclusão de operação sem recibo
- **GIVEN** uma operação com 5 movimentos e sem recibo
- **WHEN** a exclusão é confirmada
- **THEN** a operação e os 5 movimentos são removidos, junto com suas prorrogações

#### Scenario: Exclusão barrada por recibo
- **GIVEN** uma operação com recibo emitido
- **WHEN** a exclusão é tentada
- **THEN** a resposta é um erro explicando o vínculo e a operação permanece
> Nota: corrige D-98 (comportamento legado: a resposta era sempre de sucesso e a tela exibia "Operação foi removida com sucesso!" mesmo quando a exclusão havia sido barrada)

#### Scenario: Prorrogações não ficam órfãs
- **GIVEN** uma operação com 3 prorrogações registradas
- **WHEN** ela é excluída
- **THEN** as 3 prorrogações são removidas junto
> Nota: corrige comportamento legado (a associação não declarava dependência e as prorrogações viravam linhas órfãs)

### Requirement: BE-259 — Preparar renovação de operação
O sistema SHALL se comportar conforme os cenários desta seção.
A preparação monta a renovação com a nova emissão em hoje e o vencimento preservando o
prazo original em dias. Fonte legada:
`app/controllers/pub/risk_operations_controller.rb:86-98`.

#### Scenario: Prazo preservado
- **GIVEN** uma operação emitida em 01/02/2026 com vencimento em 03/03/2026, ou seja 30 dias
- **WHEN** a renovação é preparada em 10/03/2026
- **THEN** a nova emissão é 10/03/2026 e o novo vencimento é 09/04/2026

#### Scenario: Operação inexistente
- **GIVEN** um identificador de operação inválido
- **WHEN** a renovação é preparada
- **THEN** a resposta é 404, e não um erro interno

### Requirement: BE-260 — Efetivar renovação de operação
O sistema SHALL se comportar conforme os cenários desta seção.
A renovação cria uma nova operação com os mesmos dados da original, encerrando a original
para que as duas não consumam limite ao mesmo tempo. Fonte legada:
`app/controllers/pub/risk_operations_controller.rb:100-113`; `app/models/risk_operation.rb:113-139`.

#### Scenario: Dados copiados na renovação
- **GIVEN** uma operação original com título, tipo, projeto, empresa, portador, contrato, capital, taxa, observação, recebível, subtipo e saldo inicial
- **WHEN** a renovação é efetivada
- **THEN** a nova operação copia todos esses dados, guarda o vencimento anterior e nasce não encerrada

#### Scenario: Encadeamento sempre na raiz
- **GIVEN** uma operação já renovada uma vez
- **WHEN** a renovação é renovada
- **THEN** a nova operação aponta para a operação raiz da cadeia

#### Scenario: Original é encerrada e sai da exposição
- **GIVEN** uma operação original vigente com capital de 100.000,00
- **WHEN** ela é renovada
- **THEN** a original é encerrada e deixa de consumir limite, e apenas a nova operação entra na apuração de exposição
> Nota: corrige D-94 (comportamento legado: a renovação não encerrava nem retirava a original da janela, então as duas consumiam limite simultaneamente enquanto as janelas se sobrepunham, dobrando a exposição; explicitamente não alcançado por DEC-01, que trata apenas de convenção de sinal)

#### Scenario: Renovar operação já encerrada
- **GIVEN** uma operação marcada como encerrada
- **WHEN** a renovação é tentada
- **THEN** ela é recusada com erro explicativo
> Nota: corrige D-94 (comportamento legado: nada impedia renovar operação encerrada)

#### Scenario: Vencimento anterior à emissão
- **GIVEN** uma renovação cujo vencimento informado é anterior à emissão
- **WHEN** ela é submetida
- **THEN** a resposta é 422
> Nota: corrige comportamento legado (a validação não existia em nenhuma camada — nem no formulário, ver FE-275)

### Requirement: BE-261 — Resolução do limite e carimbo inicial da operação
O sistema SHALL se comportar conforme os cenários desta seção.
Na criação, a operação resolve seu limite pela quádrupla projeto, empresa, portador e
tipo, e assume o título do portador quando não informado. Fonte legada:
`app/models/risk_operation.rb:20-25`.

#### Scenario: Limite resolvido
- **GIVEN** um limite ativo para a quádrupla
- **WHEN** a operação é criada
- **THEN** ela fica vinculada a esse limite e guarda o vencimento informado como vencimento original

#### Scenario: Nenhum limite para a quádrupla
- **GIVEN** nenhuma combinação correspondente
- **WHEN** a operação é criada
- **THEN** a resposta é 422 explicando que não há limite cadastrado para a combinação
> Nota: corrige comportamento legado (o erro dizia apenas que o limite "não pode ficar em branco", sem revelar que o problema era ausência de limite para a combinação)

#### Scenario: Limite existente porém desativado
- **GIVEN** um limite desativado para a quádrupla
- **WHEN** a operação é criada
- **THEN** a criação é recusada, explicando que o limite está desativado
> Nota: corrige comportamento legado (a busca não filtrava a situação do limite, então era possível abrir operação em limite desativado)

### Requirement: BE-262 — Sincronização entre tipo e subtipo da operação
O sistema SHALL se comportar conforme os cenários desta seção.
O tipo da operação é sempre coerente com o subtipo escolhido. Fonte legada:
`app/models/risk_operation.rb:27-33`.

#### Scenario: Subtipo informado define o tipo
- **GIVEN** um subtipo cujo tipo é `T`, e um tipo diferente informado no payload
- **WHEN** a operação é gravada
- **THEN** o tipo passa a ser `T`

#### Scenario: Tipo com pré-faturamento sem subtipo informado
- **GIVEN** um tipo com pré-faturamento, que tem os subtipos de pré e de antecipação, e nenhum subtipo informado
- **WHEN** a operação é gravada
- **THEN** a gravação é recusada pedindo a escolha explícita do subtipo
> Nota: corrige comportamento legado (o sistema escolhia o primeiro subtipo pela ordem de inserção, decidindo arbitrariamente entre pré e antecipação)

#### Scenario: Tipo sem nenhum subtipo
- **GIVEN** um tipo cujos subtipos foram removidos
- **WHEN** a operação é gravada
- **THEN** a gravação é recusada com erro explicativo
> Nota: corrige comportamento legado (o subtipo ficava nulo e as telas que exibem o título do subtipo levantavam exceção)

### Requirement: BE-263 — Convenção de sinal do saldo inicial da operação
O sistema SHALL se comportar conforme os cenários desta seção.
O saldo inicial é sempre armazenado como valor negativo, em todo salvamento. Fonte
legada: `app/models/risk_operation.rb:34`.

#### Scenario: Valor positivo digitado
- **GIVEN** o usuário informando saldo inicial de 50.000,00
- **WHEN** a operação é gravada
- **THEN** `original_balance = −50.000,00`
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; é a base da cadeia de saldos (BE-265) e a origem da inversão de BE-243

#### Scenario: Valor negativo digitado
- **GIVEN** o usuário informando saldo inicial de −50.000,00
- **WHEN** a operação é gravada
- **THEN** `original_balance = −50.000,00`

#### Scenario: Saldo inicial zero
- **GIVEN** saldo inicial 0
- **WHEN** a operação é gravada
- **THEN** `original_balance = 0`

#### Scenario: Exibição do mesmo valor em telas diferentes
- **GIVEN** uma operação com `original_balance = −50.000,00`
- **WHEN** o formulário e o detalhe são exibidos
- **THEN** o formulário mostra o valor absoluto e o detalhe mostra o valor negativo, como no legado
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; a divergência de apresentação entre as duas telas é a que existe hoje (FE-265)

### Requirement: BE-264 — Movimento automático de liberação do recurso
O sistema SHALL se comportar conforme os cenários desta seção.
Operações de tipo sem pré-faturamento nascem com um movimento de liberação no valor do
capital. Fonte legada: `app/models/risk_operation.rb:39-52`.

#### Scenario: Movimento criado
- **GIVEN** uma operação de tipo sem pré-faturamento, com capital de 100.000,00 e emissão em 01/03/2026
- **WHEN** ela é criada
- **THEN** é criado um movimento de "Liberação do Recurso" com data 01/03/2026 e valor 100.000,00

#### Scenario: Operação de tipo com pré-faturamento
- **GIVEN** uma operação de tipo com pré-faturamento
- **WHEN** ela é criada
- **THEN** nenhum movimento automático é criado

#### Scenario: Tipo de movimento de liberação ausente
- **GIVEN** um ambiente em que o tipo de movimento de liberação não existe ou foi renomeado
- **WHEN** uma operação é criada
- **THEN** a criação é recusada com erro explicativo e nada é persistido
> Nota: corrige comportamento legado (o tipo era resolvido por título literal e a busca falha levantava `NoMethodError` depois de a operação já estar gravada; além disso a criação do movimento não era verificada, e a operação podia ficar sem movimento em silêncio — ver OPS-232)

### Requirement: BE-265 — Recálculo da cadeia de saldos da operação
O sistema SHALL se comportar conforme os cenários desta seção.
Os saldos dos movimentos são recalculados em cadeia, partindo do saldo inicial e
aplicando o sinal do tipo de cada movimento. Fonte legada:
`app/models/risk_operation.rb:98-111`; `app/models/risk_movement_type.rb:53-61`.

#### Scenario: Cadeia com débito e crédito
- **GIVEN** saldo inicial −50.000,00 e, em ordem, um débito de 100.000,00 e um crédito de 30.000,00
- **WHEN** a cadeia é recalculada
- **THEN** os saldos ficam 50.000,00 e 20.000,00, e o saldo da operação passa a ser 20.000,00
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário: débito soma (+1) e crédito subtrai (−1) sobre o saldo inicial já negativo

#### Scenario: Ordenação e numeração dos movimentos
- **GIVEN** movimentos cadastrados fora de ordem cronológica
- **WHEN** a cadeia é recalculada
- **THEN** eles são ordenados por data e, dentro do mesmo dia, por ordem de criação, e recebem numeração sequencial a partir de 1

#### Scenario: Movimentos fora da janela não são gravados sem validação
- **GIVEN** o recálculo em massa da cadeia
- **WHEN** ele é executado
- **THEN** a validação de janela de datas dos movimentos continua valendo
> Nota: corrige comportamento legado (a gravação em massa pulava as validações do modelo, então movimentos fora da janela nunca eram revalidados quando a operação mudava de datas ou era prorrogada — ver BE-274 e OPS-235)

#### Scenario: Movimento em operação encerrada
- **GIVEN** uma operação marcada como encerrada
- **WHEN** um novo movimento é registrado
- **THEN** ele é aceito e entra na cadeia, como no legado
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; o encerramento não trava a movimentação (ver BE-268)

### Requirement: BE-266 — Saldo da operação numa data
O sistema SHALL se comportar conforme os cenários desta seção.
O saldo numa data é o saldo do último movimento cuja data é menor ou igual à data pedida.
Fonte legada: `app/models/risk_operation.rb:92-96`.

#### Scenario: Data posterior a movimentos
- **GIVEN** movimentos em 01/03 (saldo 50.000,00) e 10/03 (saldo 20.000,00)
- **WHEN** o saldo é apurado para 15/03
- **THEN** o resultado é 20.000,00

#### Scenario: Data anterior a qualquer movimento
- **GIVEN** o primeiro movimento em 01/03 e saldo inicial −50.000,00
- **WHEN** o saldo é apurado para 25/02
- **THEN** o resultado é `0`, e não o saldo inicial
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário
> AMBIGUIDADE: a consequência é que operação estática de pré-faturamento sem movimentos entra nos agregados como zero, ignorando o saldo inicial configurado no limite; confirmar se deveria cair para o saldo inicial

### Requirement: BE-267 — Validações de presença da operação
O sistema SHALL se comportar conforme os cenários desta seção.
A operação exige empresa, projeto, portador, tipo, autor, emissão, capital, vencimento e
limite. Fonte legada: `app/models/risk_operation.rb:54-62`.

#### Scenario: Campos obrigatórios ausentes
- **GIVEN** um payload sem emissão e sem vencimento
- **WHEN** a criação é submetida
- **THEN** a resposta é 422 listando os dois campos

#### Scenario: Vencimento anterior à emissão
- **GIVEN** emissão em 10/03/2026 e vencimento em 01/03/2026
- **WHEN** a criação é submetida
- **THEN** a resposta é 422
> Nota: corrige comportamento legado (não havia validação de ordem entre as duas datas)

#### Scenario: Capital zero
- **GIVEN** capital 0
- **WHEN** a operação é criada
- **THEN** ela é aceita, como no legado
> AMBIGUIDADE: a taxa acordada é obrigatória na tela e opcional no modelo, e capital zero é aceito; confirmar quais validações o ai9 deve exigir

### Requirement: BE-268 — Estados da operação
O sistema SHALL se comportar conforme os cenários desta seção.
A operação tem os indicadores de encerrada e de considerar no variável, ambos editáveis
pelo formulário. Fonte legada: `app/models/risk_operation.rb:66-89`.

#### Scenario: Marcar como encerrada
- **GIVEN** uma operação vigente e movimentada
- **WHEN** ela é marcada como encerrada
- **THEN** ela continua na janela de apuração, continua consumindo limite e continua aceitando movimentos
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; o encerramento é hoje apenas um rótulo, sem efeito colateral, e alimenta somente as apurações de vencidos e a vencer (BE-247/248)

#### Scenario: Tipo com pré-faturamento
- **GIVEN** uma operação de tipo com pré-faturamento
- **WHEN** o formulário é exibido
- **THEN** o indicador de encerrada não é oferecido e permanece desligado

#### Scenario: Considerar no variável
- **GIVEN** uma operação com o indicador de variável ligado
- **WHEN** ela é consultada
- **THEN** o rótulo apresentado é "Considerar no variável"
> AMBIGUIDADE: D-74 — o indicador de variável não tem nenhum consumidor no legado; confirmar se é campo vivo ou resíduo

### Requirement: BE-269 — Posições diárias de risco
O sistema SHALL se comportar conforme os cenários desta seção.
As posições diárias registram, por limite e por data, os valores vencidos, a vencer,
liquidação, descontos e os recortes de fomento, intercompany e comissária. Fonte legada:
`app/controllers/pub/risk_entries_controller.rb`; `app/models/risk_entry.rb`.

#### Scenario: Regras que sobrevivem no modelo
- **GIVEN** uma posição com vencidos 40.000,00, a vencer 60.000,00, liquidação 10.000,00 e descontos 5.000,00
- **WHEN** ela é gravada
- **THEN** o total da carteira é 100.000,00 e o total de reduções é 15.000,00, calculados pelo sistema e sobrepondo qualquer valor enviado; o mesmo vale para os totais de fomento, intercompany e comissária

#### Scenario: Unicidade por data, limite e empresa
- **GIVEN** uma posição já registrada para a data, o limite e a empresa
- **WHEN** outra é criada para a mesma combinação
- **THEN** a criação é recusada

#### Scenario: Telas de posição diária
- **GIVEN** o legado
- **WHEN** qualquer endpoint de posição diária é acionado
- **THEN** ele falha por template ausente, porque toda a árvore de telas foi removida e as abas de menu estão comentadas
> AMBIGUIDADE: D-99 — a funcionalidade está morta na tela mas viva no modelo e no banco; confirmar se as posições diárias voltam a existir no ai9, se são substituídas pelo cálculo automático de vencidos e a vencer (BE-247/248), ou se são descartadas com evidência

### Requirement: BE-270 — Listar movimentações de uma operação
O sistema SHALL se comportar conforme os cenários desta seção.
A busca devolve os movimentos de uma operação em ordem de cadeia. Fonte legada:
`app/controllers/pub/risk_movements_controller.rb:6-21`.

#### Scenario: Movimentos em ordem
- **GIVEN** uma operação com 12 movimentos
- **WHEN** a busca é executada
- **THEN** eles vêm na ordem da cadeia de saldos

#### Scenario: Paginação da lista de movimentos
- **GIVEN** uma operação com 200 movimentos e uma busca com limite 50
- **WHEN** ela é executada
- **THEN** vêm 50 movimentos e o total informado é 200
> Nota: corrige D-20 (comportamento legado: limite, deslocamento e termo eram preenchidos e nunca aplicados — a lista nunca paginava)

#### Scenario: Operação de outro projeto
- **GIVEN** uma operação de outro projeto
- **WHEN** seus movimentos são solicitados
- **THEN** a requisição é recusada por autorização
> Nota: corrige D-100 (comportamento legado: a busca filtrava apenas pela operação, sem escopo de projeto — qualquer identificador era aceito)

#### Scenario: Rotas REST mortas de movimentação
- **GIVEN** as ações de índice e detalhe do controller legado
- **WHEN** o escopo do ai9 é definido
- **THEN** elas não existem
> Nota: DEC-09 — os templates não existem no repositório legado; entram no ledger como `dropped` com evidência

### Requirement: BE-271 — Abrir o formulário de movimentação
O sistema SHALL se comportar conforme os cenários desta seção.
O formulário abre em modo de cadastro, edição ou transferência. Fonte legada:
`app/controllers/pub/risk_movements_controller.rb:23-44`, `:62-68`.

#### Scenario: Cadastro comum
- **GIVEN** uma operação
- **WHEN** o formulário de nova movimentação é aberto
- **THEN** ele vem vazio, vinculado à operação, com o tipo de movimentação editável

#### Scenario: Modo transferência
- **GIVEN** uma operação de subtipo pré-faturamento
- **WHEN** o formulário de transferência é aberto
- **THEN** o tipo já vem fixado como transferência enviada e não é editável

#### Scenario: Operação inexistente
- **GIVEN** um identificador de operação inválido
- **WHEN** qualquer um dos três modos é aberto
- **THEN** a resposta é 404, e não um erro interno
> Nota: corrige comportamento legado (a operação nula levava a `NoMethodError` nos três caminhos)

### Requirement: BE-272 — Criar movimentação
O sistema SHALL se comportar conforme os cenários desta seção.
A movimentação registra data, tipo, valor e observação, herdando empresa, portador e
projeto da operação. Fonte legada:
`app/controllers/pub/risk_movements_controller.rb:48-58`; `app/models/risk_movement.rb:15-19`, `:70-77`.

#### Scenario: Criação e herança de contexto
- **GIVEN** uma operação da empresa `E1`, portador `C1` e projeto `P1`
- **WHEN** uma movimentação é criada informando outra empresa no payload
- **THEN** a movimentação é gravada com `E1`, `C1` e `P1`, e o payload é ignorado

#### Scenario: Tipos oferecidos
- **GIVEN** o formulário de movimentação
- **WHEN** os tipos são listados
- **THEN** só aparecem os tipos ativos que não são de transferência

#### Scenario: Valor zero é recusado
- **GIVEN** uma movimentação com valor 0
- **WHEN** ela é submetida diretamente à API
- **THEN** a resposta é 422
> Nota: corrige comportamento legado (a regra existia só como botão desabilitado no cliente, e o servidor aceitava movimento de valor zero na cadeia — ver FE-271)

### Requirement: BE-273 — Atualizar e excluir movimentação
O sistema SHALL se comportar conforme os cenários desta seção.
Alterar ou remover um movimento refaz a cadeia de saldos e a numeração dos movimentos
restantes. Fonte legada: `app/controllers/pub/risk_movements_controller.rb:70-90`;
`app/models/risk_movement.rb:67-69`.

#### Scenario: Alteração recalcula a cadeia
- **GIVEN** uma cadeia de 5 movimentos
- **WHEN** o valor do terceiro é alterado
- **THEN** os saldos do terceiro em diante são recalculados e o saldo da operação é atualizado

#### Scenario: Exclusão recalcula e renumera
- **GIVEN** a mesma cadeia
- **WHEN** o terceiro movimento é excluído
- **THEN** os restantes são renumerados de 1 a 4 e os saldos são refeitos

#### Scenario: Exclusão do movimento de liberação
- **GIVEN** o movimento automático de liberação do recurso
- **WHEN** ele é excluído
- **THEN** a exclusão é permitida e o movimento não é recriado, como no legado
> AMBIGUIDADE: o movimento que representa a liberação do capital pode ser removido sem contrapartida; confirmar se o ai9 deve protegê-lo

### Requirement: BE-274 — Validação da janela do movimento
O sistema SHALL se comportar conforme os cenários desta seção.
A data do movimento precisa estar entre a emissão e o vencimento da operação, inclusive.
Fonte legada: `app/models/risk_movement.rb:20-28`.

#### Scenario: Data dentro da janela
- **GIVEN** uma operação com emissão em 01/03/2026 e vencimento em 30/04/2026
- **WHEN** um movimento é criado em 01/03/2026 ou em 30/04/2026
- **THEN** ele é aceito

#### Scenario: Data fora da janela
- **GIVEN** a mesma operação
- **WHEN** um movimento é criado em 28/02/2026 ou em 01/05/2026
- **THEN** a resposta é 422 com a mensagem "Deve estar entre as datas de emissão e de vencimento da operação"

#### Scenario: Operação estática
- **GIVEN** uma operação estática de pré-faturamento
- **WHEN** um movimento é criado em qualquer data
- **THEN** ele é aceito
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; a janela permanentemente aberta das operações estáticas é a que existe hoje (BE-241)

#### Scenario: Movimento sem operação
- **GIVEN** um movimento sem operação vinculada
- **WHEN** ele é submetido
- **THEN** a resposta é 422 pela validação de presença, e não um erro interno
> Nota: corrige comportamento legado (a validação de janela executava antes e levantava exceção)

### Requirement: BE-275 — Transferência entre a operação de pré e sua par
O sistema SHALL se comportar conforme os cenários desta seção.
Um movimento de transferência enviada na operação de pré gera a contrapartida de
transferência recebida na operação par. Fonte legada: `app/models/risk_movement.rb:45-65`.

#### Scenario: Transferência com contrapartida
- **GIVEN** uma operação de pré com par de antecipação
- **WHEN** um movimento de transferência enviada de 30.000,00 é criado em 10/03/2026
- **THEN** é criado na operação par um movimento de transferência recebida com a mesma data, valor e observação, e os dois ficam vinculados entre si

#### Scenario: Efeito nos saldos
- **GIVEN** a transferência acima
- **WHEN** as duas cadeias são recalculadas
- **THEN** a transferência enviada reduz o saldo da operação de pré e a transferência recebida aumenta o saldo da operação de antecipação
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário

#### Scenario: Operação de pré sem par
- **GIVEN** uma operação de pré criada fora do fluxo do limite, sem par
- **WHEN** uma transferência é tentada
- **THEN** ela é recusada antes de qualquer gravação
> Nota: corrige comportamento legado (o movimento original já estava gravado quando o acesso ao par nulo levantava `NoMethodError`, deixando meia transferência)

#### Scenario: Transferência a partir da operação de antecipação
- **GIVEN** uma operação de antecipação
- **WHEN** um movimento de transferência enviada é criado nela
- **THEN** nenhuma contrapartida é gerada, como no legado
> AMBIGUIDADE: só existe transferência no sentido pré para antecipação; confirmar se o sentido inverso deve ser suportado

### Requirement: BE-276 — Propagação em cascata dos movimentos
O sistema SHALL se comportar conforme os cenários desta seção.
Criar, alterar ou excluir um movimento propaga o recálculo da operação e mantém o
movimento par sincronizado. Fonte legada: `app/models/risk_movement.rb:30-42`, `:67-69`.

#### Scenario: Alteração de movimento com par
- **GIVEN** uma transferência com contrapartida na operação par
- **WHEN** a data e o valor do movimento original são alterados
- **THEN** o movimento par recebe a mesma data e o mesmo valor, e as duas cadeias de saldo são recalculadas
> Nota: corrige D-97 (comportamento legado: a lista de colunas do espelhamento referenciava uma variável local inexistente no lugar do símbolo da coluna de valor, então editar um movimento com par levantava `NameError` em produção)

#### Scenario: Exclusão de movimento com par
- **GIVEN** a mesma transferência
- **WHEN** o movimento original é excluído
- **THEN** a contrapartida também é removida e as duas cadeias são recalculadas
> Nota: corrige comportamento legado (não havia espelhamento na exclusão, e a contrapartida ficava solta na outra operação)

### Requirement: BE-277 — Prorrogações de operação
O sistema SHALL se comportar conforme os cenários desta seção.
A prorrogação registra o vencimento anterior e o novo, e passa a valer no vencimento da
operação. Fonte legada: `app/controllers/pub/risk_operation_extensions_controller.rb`;
`app/models/risk_operation_extension.rb`.

#### Scenario: Prorrogação registrada
- **GIVEN** uma operação com vencimento em 30/04/2026
- **WHEN** uma prorrogação para 31/05/2026 é criada
- **THEN** o registro guarda 30/04/2026 como vencimento anterior e 31/05/2026 como novo, e a operação passa a vencer em 31/05/2026

#### Scenario: Listagem das prorrogações
- **GIVEN** uma operação com 3 prorrogações
- **WHEN** a lista é solicitada
- **THEN** elas vêm em ordem cronológica de registro

#### Scenario: Retroceder o vencimento
- **GIVEN** uma operação com vencimento em 30/04/2026
- **WHEN** uma prorrogação para 15/04/2026 é submetida diretamente à API
- **THEN** a resposta é 422
> Nota: corrige D-94 (comportamento legado: só o seletor de data do formulário impedia; pela API era possível encurtar o vencimento e deixar movimentos existentes fora da janela sem que nada os rejeitasse)

#### Scenario: Prorrogar operação encerrada
- **GIVEN** uma operação marcada como encerrada
- **WHEN** uma prorrogação é submetida
- **THEN** a resposta é 422
> Nota: corrige D-94 (comportamento legado: a tela escondia o botão mas o endpoint aceitava)

#### Scenario: Prorrogar operação estática
- **GIVEN** uma operação estática de pré-faturamento
- **WHEN** uma prorrogação é submetida
- **THEN** a resposta é 422

### Requirement: BE-278 — Tipos de limite e seus subtipos
O sistema SHALL se comportar conforme os cenários desta seção.
O catálogo de tipos de operação define se o tipo permite lançamento manual, lançamento a
partir de recebíveis e se usa pré-faturamento, e mantém os subtipos correspondentes.
Fonte legada: `app/controllers/pub/risk_operation_types_controller.rb`;
`app/models/risk_operation_type.rb`; `app/models/risk_operation_subtype.rb`.

#### Scenario: Criação de tipo com pré-faturamento
- **GIVEN** um tipo "Auto Liquidável" com pré-faturamento
- **WHEN** ele é criado
- **THEN** são criados dois subtipos, "Auto Liquidável - pré-faturamento" e "Auto Liquidável - antecipação", ligados entre si

#### Scenario: Criação de tipo sem pré-faturamento
- **GIVEN** um tipo "Fomento" sem pré-faturamento
- **WHEN** ele é criado
- **THEN** é criado um único subtipo homônimo

#### Scenario: Propagação das flags para os subtipos
- **GIVEN** um tipo com subtipos
- **WHEN** as permissões de lançamento manual e por recebível ou a situação são alteradas
- **THEN** os subtipos recebem os mesmos valores

#### Scenario: Pré-faturamento é imutável
- **GIVEN** um tipo já criado
- **WHEN** uma requisição direta tenta alterar o indicador de pré-faturamento
- **THEN** a alteração é recusada
> Nota: corrige comportamento legado (o formulário travava o campo mas ele continuava aceito no `permit`, e alterá-lo deixava o tipo sem os subtipos correspondentes)

#### Scenario: Exclusão bloqueada
- **GIVEN** um tipo padrão do sistema, ou um tipo com operações
- **WHEN** a exclusão é tentada
- **THEN** ela é recusada com a razão do bloqueio

#### Scenario: Chave de integração derivada do título
- **GIVEN** o título "Auto Liquidável" e a chave em branco
- **WHEN** o tipo é criado
- **THEN** a chave gravada é `auto_liquidavel`

#### Scenario: Estrutura de subtipos limitada a dois
- **GIVEN** um tipo que já tem um subtipo de pré e um de não-pré
- **WHEN** um terceiro subtipo é criado
- **THEN** a criação é recusada pela unicidade do indicador de pré dentro do tipo
> AMBIGUIDADE: a modelagem limita cada tipo a exatamente dois subtipos; confirmar se essa restrição deve ser mantida no ai9

### Requirement: BE-279 — Tipos de movimentação
O sistema SHALL se comportar conforme os cenários desta seção.
O catálogo de tipos de movimentação define o sinal aplicado ao saldo e identifica os três
tipos usados pelos fluxos automáticos. Fonte legada:
`app/controllers/pub/risk_movement_types_controller.rb`; `app/models/risk_movement_type.rb`.

#### Scenario: Criação de tipo
- **GIVEN** o título "Juros" e o sinal de débito
- **WHEN** o tipo é criado
- **THEN** ele é persistido com a descrição "Débito", chave de integração derivada do título e o sinal que soma no saldo

#### Scenario: Alteração do sinal mantém a descrição coerente
- **GIVEN** um tipo com sinal de débito
- **WHEN** o sinal é alterado para crédito
- **THEN** a descrição apresentada acompanha a mudança
> Nota: corrige comportamento legado (a descrição só era derivada na criação e ficava desatualizada em alterações feitas pela API)

#### Scenario: Exclusão de tipo padrão
- **GIVEN** um tipo marcado como padrão do sistema
- **WHEN** a exclusão é tentada
- **THEN** ela é recusada com erro explícito, sem tentar remover o registro
> Nota: corrige D-98 (comportamento legado: o controller adicionava a mensagem de erro e ainda assim chamava a remoção, e respondia sucesso nos dois ramos — quem barrava de fato era o modelo)

#### Scenario: Tipos usados pelos fluxos automáticos são protegidos
- **GIVEN** os tipos "Liberação do Recurso", "Valor Transferido" e "Transferência Recebida"
- **WHEN** alguém tenta renomeá-los
- **THEN** a alteração de título é recusada, ou o vínculo funcional é preservado por chave estável
> Nota: corrige comportamento legado (os três eram localizados por título literal, então renomear qualquer um quebrava a criação de operação e a transferência em produção — ver OPS-232)

#### Scenario: Listagem do catálogo
- **GIVEN** tipos ativos, inativos e de transferência
- **WHEN** o catálogo é listado
- **THEN** todos são exibidos com sua situação, enquanto o seletor do formulário de movimentação oferece apenas os ativos que não são de transferência

### Requirement: FE-230 — Casca da tela de controle de risco
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Controle de risco" é o painel de exposição, com uma única aba de resumo. Fonte
legada: `app/views/pub/console/parts/risk/_body.html.erb:1-34`.

#### Scenario: Abertura da tela
- **GIVEN** o menu "Gestão"
- **WHEN** o usuário abre "Controle de Risco"
- **THEN** a tela mostra o título "Controle de risco" e a aba "RESUMO"

#### Scenario: Aba de posições
- **GIVEN** a tela aberta
- **WHEN** as abas são exibidas
- **THEN** não existe aba de posições diárias, como no legado
> AMBIGUIDADE: D-99 — a aba está comentada na view e depende da decisão sobre a funcionalidade de posições diárias (BE-269)

### Requirement: FE-231 — Filtro de grupo econômico
O sistema SHALL se comportar conforme os cenários desta seção.
Um seletor de empresa recorta o painel, com opção para o projeto inteiro. Fonte legada:
`risk/_body.js.erb:167-186`, `:203`.

#### Scenario: Filtro por empresa
- **GIVEN** o seletor com as empresas do projeto e a opção em branco rotulada "Grupo econômico"
- **WHEN** o usuário escolhe uma empresa
- **THEN** o portador selecionado é limpo, e tanto os totais quanto o resumo passam a considerar só aquela empresa

#### Scenario: Carga inicial
- **GIVEN** a tela recém-aberta sem empresa escolhida
- **WHEN** ela carrega
- **THEN** o painel mostra a exposição do projeto inteiro

### Requirement: FE-232 — Filtro de portador em cascata
O sistema SHALL se comportar conforme os cenários desta seção.
O seletor de portador é recarregado conforme a empresa e recorta o resumo. Fonte legada:
`risk/_body.js.erb:47-67`, `:91-111`.

#### Scenario: Recarga em cascata
- **GIVEN** o seletor de portador carregado com os portadores com limite ativo do projeto
- **WHEN** o usuário troca a empresa
- **THEN** o seletor fica indisponível durante a busca e volta com os portadores daquela empresa, mais a opção "TODOS"

#### Scenario: Escolha de portador troca o layout
- **GIVEN** o seletor com "TODOS" escolhido
- **WHEN** o usuário escolhe um portador
- **THEN** o resumo passa ao formato de portador único

### Requirement: FE-233 — Filtro de data do painel
O sistema SHALL se comportar conforme os cenários desta seção.
Um seletor de data define o dia da exposição apurada, limitado a hoje. Fonte legada:
`risk/_body.js.erb:204-234`.

#### Scenario: Consultar uma data passada
- **GIVEN** o seletor aberto
- **WHEN** o usuário escolhe 01/03/2026
- **THEN** o rótulo mostra `01/03/2026` e todo o painel é reapurado para essa data

#### Scenario: Data futura
- **GIVEN** o seletor aberto
- **WHEN** o usuário tenta escolher uma data posterior a hoje
- **THEN** a escolha não é permitida

### Requirement: FE-234 — Ação de cadastrar posição diária
O sistema SHALL se comportar conforme os cenários desta seção.
A ação de cadastrar posição diária existe no legado apenas como resíduo desativado.
Fonte legada: `risk/_body.html.erb:22-25`; `_body.js.erb:125-136`, `:164`.

#### Scenario: Ação indisponível
- **GIVEN** o painel de risco aberto
- **WHEN** a barra de ações é exibida
- **THEN** nenhuma ação de cadastrar posição é oferecida
> AMBIGUIDADE: D-99 — o elemento existe no documento, nunca é exibido e todo o bloco que o ativaria está comentado; depende da decisão sobre BE-269

### Requirement: FE-235 — Resumo de limites agrupado por tipo
O sistema SHALL se comportar conforme os cenários desta seção.
No modo de todos os portadores, o resumo mostra um bloco por tipo de limite com o
agregado do tipo e uma linha por limite. Fonte legada:
`risk/parts/risk_controls/list/_body.html.erb:33-78`.

#### Scenario: Estrutura do resumo
- **GIVEN** dois tipos de limite ativos com limites
- **WHEN** o painel é exibido
- **THEN** cada tipo tem um cabeçalho com Liquidavel, Pré-Faturamento, Lim. util, Lim. disp e Lim. total, e abaixo uma linha por limite com o portador, seu grupo e os mesmos cinco valores mais a taxa

#### Scenario: Tipo sem pré-faturamento
- **GIVEN** um tipo sem pré-faturamento
- **WHEN** o cabeçalho é exibido
- **THEN** a coluna Pré-Faturamento mostra `-`

#### Scenario: Colunas liquidável e pré do cabeçalho
- **GIVEN** um tipo com utilizado, liquidável e pré distintos
- **WHEN** o cabeçalho é exibido
- **THEN** ele apresenta os números atuais do legado, em que liquidável e pré repetem o utilizado e o percentual do cabeçalho é um valor monetário exibido com sufixo de percentual
> Nota: DEC-01 — D-95 replicado; os números que a tela mostra hoje ficam travados por este cenário (ver BE-250)

#### Scenario: Formatação dos valores
- **GIVEN** um valor de 150.000,00
- **WHEN** a linha é exibida
- **THEN** ele aparece no formato brasileiro sem o prefixo de moeda, e a taxa aparece com duas casas decimais

### Requirement: FE-236 — Resumo em modo de portador único
O sistema SHALL se comportar conforme os cenários desta seção.
Com um portador escolhido, o resumo passa a ter uma linha por tipo de limite. Fonte
legada: `risk/parts/risk_controls/list/_body.html.erb:3-31`.

#### Scenario: Layout de portador único
- **GIVEN** um portador escolhido
- **WHEN** o resumo é exibido
- **THEN** o cabeçalho mostra o nome do portador, cada linha é um tipo de limite e o bloco já vem expandido

#### Scenario: Cabeçalho não recolhe
- **GIVEN** o modo de portador único
- **WHEN** o usuário clica no cabeçalho
- **THEN** nada é recolhido

#### Scenario: Mais de um limite do mesmo tipo para o portador
- **GIVEN** dados legados com dois limites do mesmo tipo para o mesmo portador
- **WHEN** o resumo é exibido
- **THEN** apenas o primeiro é mostrado, como no legado
> AMBIGUIDADE: a situação é impossível pela unicidade de BE-240 mas existe em dados legados; confirmar se a carga deve consolidar ou reportar essas duplicatas

### Requirement: FE-237 — Expandir e recolher grupos por tipo
O sistema SHALL se comportar conforme os cenários desta seção.
Os blocos de tipo do resumo nascem recolhidos e abrem ao clique. Fonte legada:
`risk/parts/risk_controls/list/_body.js.erb:5-18`.

#### Scenario: Expandir um grupo
- **GIVEN** o resumo com todos os grupos recolhidos
- **WHEN** o usuário clica no cabeçalho de um tipo
- **THEN** as linhas daquele tipo são exibidas e o indicador de expansão muda

#### Scenario: Recolher novamente
- **GIVEN** um grupo expandido
- **WHEN** o usuário clica de novo no cabeçalho
- **THEN** as linhas são ocultadas

### Requirement: FE-238 — Indicador visual de limite estourado
O sistema SHALL se comportar conforme os cenários desta seção.
O limite disponível negativo é destacado como estouro. Fonte legada:
`risk/parts/risk_controls/list/_multi_widget.html.erb:12`; `app/frontend/css/pub/colors.scss:87-93`.

#### Scenario: Limite estourado
- **GIVEN** um limite cujo disponível é −50.000,00
- **WHEN** a linha é exibida
- **THEN** a célula de limite disponível recebe o destaque negativo

#### Scenario: Limite dentro do teto
- **GIVEN** um limite cujo disponível é positivo
- **WHEN** a linha é exibida
- **THEN** a célula recebe o tratamento visual positivo, com o mesmo par de tokens semânticos usado em todo o produto
> Nota: corrige D-101 (comportamento legado: existiam duas paletas concorrentes — as variáveis de indicador positivo e negativo do sistema de cores nunca foram usadas em nenhuma tela de risco, que pintava com um par próprio, e não havia tratamento positivo)

### Requirement: FE-239 — Estados do container de resumo
O sistema SHALL se comportar conforme os cenários desta seção.
O resumo tem estados de carregamento, vazio e erro, e recarrega a cada mudança de filtro.
Fonte legada: `risk/tabs/_tab_resume.js.erb:54-59`;
`risk/parts/risk_controls/list/body.js.erb:12-18`.

#### Scenario: Carregando e vazio
- **GIVEN** o painel sendo apurado
- **WHEN** não há nenhum limite para os filtros escolhidos
- **THEN** a tela passa de "Buscando .." para "Nenhum resultado encontrado" e o conteúdo do resumo é ocultado

#### Scenario: Falha na apuração
- **GIVEN** a apuração retornando erro
- **WHEN** a resposta chega
- **THEN** a tela mostra um estado de erro com opção de tentar novamente
> Nota: corrige comportamento legado (o tratamento de falha do container era vazio e a tela ficava sem qualquer sinal)

### Requirement: FE-240 — Tela de limites
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Limites" lista os limites do projeto com portador, empresa, tipo, teto e taxa.
Fonte legada: `app/views/pub/console/parts/risk_controls/_body.html.erb:1-65`.

#### Scenario: Colunas da lista
- **GIVEN** limites cadastrados
- **WHEN** o usuário abre a área pelo menu "Projeto"
- **THEN** a tela mostra as colunas de portador, empresa, tipo, limite e taxa

#### Scenario: Estado vazio
- **GIVEN** um projeto sem limites
- **WHEN** a lista é carregada
- **THEN** a tela mostra "Nenhum resultado encontrado"

### Requirement: FE-241 — Filtros da tela de limites
O sistema SHALL se comportar conforme os cenários desta seção.
Três seletores filtram por empresa, portador e tipo de limite. Fonte legada:
`risk_controls/_body.html.erb:27-40`.

#### Scenario: Filtro por empresa e tipo
- **GIVEN** o bloco de filtros aberto
- **WHEN** o usuário escolhe uma empresa e um tipo
- **THEN** só os limites que casam com os dois são listados

#### Scenario: Portadores oferecidos
- **GIVEN** portadores de vários projetos no sistema
- **WHEN** o seletor de portador é montado
- **THEN** só os portadores do projeto corrente são oferecidos
> Nota: corrige o vazamento de escopo da mesma família de D-16/D-100 (comportamento legado: o seletor listava todos os portadores do sistema, e o de tipo incluía tipos inativos)

### Requirement: FE-242 — Paginação da tela de limites
O sistema SHALL se comportar conforme os cenários desta seção.
Botões de navegação e um campo de tamanho de página percorrem a lista. Fonte legada:
`risk_controls/_body.js.erb:112`, `:127`, `:149`, `:162`.

#### Scenario: Navegação entre páginas
- **GIVEN** 60 limites e tamanho de página 20
- **WHEN** o usuário avança
- **THEN** a lista mostra os limites 21 a 40

#### Scenario: Alterar o tamanho da página
- **GIVEN** a lista carregada
- **WHEN** o usuário informa 50 no campo de tamanho
- **THEN** a lista é recarregada com 50 registros por página

### Requirement: FE-243 — Widget de limite
O sistema SHALL se comportar conforme os cenários desta seção.
Cada linha mostra portador com seu grupo, empresa, tipo, teto e taxa, e sinaliza limites
desativados. Fonte legada: `risk_controls/list/_widget.html.erb:1-60`.

#### Scenario: Conteúdo da linha
- **GIVEN** um limite do portador "Banco Alfa" do grupo "Grupo X", com teto 500.000,00 e taxa 1,5
- **WHEN** a linha é exibida
- **THEN** ela mostra "Banco Alfa • Grupo X", a empresa, o tipo, `R$ 500.000,00` e `1,50%`

#### Scenario: Limite desativado
- **GIVEN** um limite desativado
- **WHEN** a linha é exibida
- **THEN** ela recebe o tratamento visual de inativo e um indicador com "Desativado / Limite desativado, não será utilizado"

#### Scenario: Limite sem tipo de operação
- **GIVEN** um limite anterior à migração de 2022, sem tipo de operação
- **WHEN** a linha é exibida
- **THEN** o tipo aparece como "Legado"
> AMBIGUIDADE: DB-240 — é preciso confirmar se ainda restam limites sem tipo na base antes de decidir se esse estado é portado ou convertido

### Requirement: FE-244 — Painel de criar e editar limite
O sistema SHALL se comportar conforme os cenários desta seção.
O painel lateral captura empresa, portador, tipo, teto e taxa, com cascata entre empresa
e portador. Fonte legada: `risk_controls/helper/_body.js.erb:21-44`.

#### Scenario: Cascata empresa para portador
- **GIVEN** o painel aberto para criação
- **WHEN** o usuário troca a empresa
- **THEN** os portadores são recarregados para aquela empresa e o projeto associado é atualizado

#### Scenario: Edição com identidade travada
- **GIVEN** um limite existente
- **WHEN** o painel é aberto para edição
- **THEN** empresa, portador e tipo não são editáveis

### Requirement: FE-245 — Campo de saldo inicial condicional
O sistema SHALL se comportar conforme os cenários desta seção.
Os saldos iniciais liquidável e pré só são pedidos para tipos com pré-faturamento, e
somente na criação. Fonte legada: `risk_controls/helper/_body.html.erb:31`, `:57-79`.

#### Scenario: Tipo com pré-faturamento
- **GIVEN** o painel de criação
- **WHEN** o usuário escolhe um tipo com pré-faturamento
- **THEN** aparecem os campos "Liquidavel" e "Pré", que alimentam as operações estáticas criadas com o limite

#### Scenario: Tipo sem pré-faturamento
- **GIVEN** o painel de criação
- **WHEN** o usuário escolhe um tipo sem pré-faturamento
- **THEN** os campos de saldo inicial não são exibidos

#### Scenario: Edição de limite
- **GIVEN** um limite de tipo com pré-faturamento
- **WHEN** o painel é aberto para edição
- **THEN** os campos de saldo inicial não são exibidos

### Requirement: FE-246 — Máscaras do formulário de limite
O sistema SHALL se comportar conforme os cenários desta seção.
Os campos de teto e taxa normalizam a digitação e formatam na saída do foco. Fonte
legada: `risk_controls/helper/_body.js.erb:45-93`, `:112-160`.

#### Scenario: Máscara monetária
- **GIVEN** o campo de teto em foco
- **WHEN** o usuário digita `500000.00` e sai do campo
- **THEN** o campo exibe `R$ 500.000,00`

#### Scenario: Máscara percentual
- **GIVEN** o campo de taxa
- **WHEN** o usuário digita `1,5` e sai do campo
- **THEN** o campo exibe `1,50%`

#### Scenario: Mais de um separador decimal
- **GIVEN** qualquer um dos dois campos
- **WHEN** um segundo separador decimal é digitado
- **THEN** a tela avisa "Você só precisa inserir 1 separador para as casas decimais"

### Requirement: FE-247 — Ações do limite na lista
O sistema SHALL se comportar conforme os cenários desta seção.
O menu do limite oferece ativar, desativar e excluir, com confirmação para a exclusão.
Fonte legada: `risk_controls/list/_widget.js.erb:37-58`, `:90-128`.

#### Scenario: Ativar e desativar
- **GIVEN** um limite ativo
- **WHEN** o menu é aberto
- **THEN** apenas "Desativar" é oferecido, e ao acioná-lo a tela mostra "O controle de risco foi desativado com sucesso"

#### Scenario: Exclusão confirmada
- **GIVEN** um limite sem dependências
- **WHEN** o usuário confirma "Remover — A operação não pode ser desfeita. Tem certeza?"
- **THEN** o limite é removido e a tela mostra "O controle de risco foi excluido com sucesso"

#### Scenario: Exclusão barrada por dependências
- **GIVEN** um limite com operações vinculadas
- **WHEN** a exclusão é tentada
- **THEN** a tela explica que existem operações vinculadas
> Nota: corrige D-24 (comportamento legado: qualquer falha exibia a mensagem genérica "Houve um problema, tente novamente", inclusive o bloqueio por dependência)

### Requirement: FE-248 — Guardas do cadastro de limite
O sistema SHALL se comportar conforme os cenários desta seção.
O cadastro exige empresa e portador no projeto, e não é oferecido a usuários
somente-leitura. Fonte legada: `risk_controls/_body.js.erb:336-347`.

#### Scenario: Projeto sem empresa
- **GIVEN** um projeto sem empresas
- **WHEN** o usuário aciona "Cadastrar"
- **THEN** a tela mostra "É necessário ter uma empresa no projeto padrão, para que seja possível cadastrar um controle de risco"

#### Scenario: Projeto sem portador
- **GIVEN** um projeto com empresa e sem portador
- **WHEN** o usuário aciona "Cadastrar"
- **THEN** a tela mostra a mensagem equivalente sobre portador

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** a lista é exibida
- **THEN** o botão de cadastro não existe

### Requirement: FE-249 — Estados da lista de limites
O sistema SHALL se comportar conforme os cenários desta seção.
A lista tem estado de carregamento, vazio e vazio com termo de busca. Fonte legada:
`risk_controls/_body.js.erb:93`, `:107-108`.

#### Scenario: Vazio sem busca
- **GIVEN** nenhum limite para os filtros
- **WHEN** a lista carrega
- **THEN** a tela mostra "Nenhum resultado encontrado"

#### Scenario: Vazio com termo de busca
- **GIVEN** o termo "alfa" no campo de busca e nenhum limite correspondente
- **WHEN** a lista carrega
- **THEN** a tela mostra "Não encontramos nenhum resultado para a busca alfa.."
> Nota: corrige comportamento legado (a mensagem existia mas era inalcançável, porque o filtro textual não era aplicado no servidor — ver BE-230)

### Requirement: FE-250 — Tela de operações de risco
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Operações de Risco" lista as operações do projeto com portador, subtipo, título,
datas, capital, saldo, prorrogações e taxa. Fonte legada:
`app/views/pub/console/parts/risk_operations/_body.html.erb:1-131`.

#### Scenario: Colunas da lista
- **GIVEN** operações cadastradas
- **WHEN** o usuário abre a área pelo menu "Gestão"
- **THEN** a tela mostra Portador, Tipo de operação com o subtipo, Titulo, Emissão, Capital, Saldo, Vencimento, Prorrogações e Tx acordada

#### Scenario: Operação estática de pré-faturamento
- **GIVEN** uma operação de tipo com pré-faturamento
- **WHEN** a linha é exibida
- **THEN** as colunas de emissão e vencimento mostram `-`
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; as datas-sentinela não são exibidas ao usuário

### Requirement: FE-251 — Busca textual de operações
O sistema SHALL se comportar conforme os cenários desta seção.
O campo de busca casa o título do portador ou o título da operação. Fonte legada:
`risk_operations/_body.js.erb:265`, `:276`.

#### Scenario: Busca por portador ou título
- **GIVEN** operações do portador "Banco Alfa" e uma operação chamada "Alfa 2026"
- **WHEN** o usuário busca por "alfa"
- **THEN** as duas são retornadas

#### Scenario: Vazio com termo
- **GIVEN** um termo sem correspondência
- **WHEN** a lista carrega
- **THEN** a tela mostra "Não encontramos nenhum resultado para a busca ..."

### Requirement: FE-252 — Filtros de empresa, portador e tipo de operação
O sistema SHALL se comportar conforme os cenários desta seção.
Três seletores recortam a lista de operações. Fonte legada:
`risk_operations/_body.html.erb:43-56`.

#### Scenario: Filtros combinados
- **GIVEN** o bloco de filtros aberto
- **WHEN** o usuário escolhe empresa e portador
- **THEN** só as operações que casam com os dois são listadas

#### Scenario: Tipos oferecidos
- **GIVEN** tipos de operação ativos e inativos
- **WHEN** o seletor de tipo é montado
- **THEN** apenas os tipos ativos são oferecidos
> Nota: corrige comportamento legado (o seletor listava todos os tipos, inclusive os inativos)

### Requirement: FE-253 — Filtro de período de operações
O sistema SHALL se comportar conforme os cenários desta seção.
O seletor de intervalo recorta as operações vigentes no período. Fonte legada:
`risk_operations/_body.js.erb:112-175`.

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
> Nota: corrige comportamento legado (o ano final era lido da data inicial e o rótulo mostrava o ano errado)

### Requirement: FE-254 — Ordenação multi-coluna de operações
O sistema SHALL se comportar conforme os cenários desta seção.
O clique nos cabeçalhos ordena a lista, acumulando colunas. Fonte legada:
`risk_operations/_body.js.erb:37-107`.

#### Scenario: Colunas ordenáveis
- **GIVEN** a lista de operações
- **WHEN** o usuário clica em qualquer cabeçalho de portador, tipo, título, emissão, capital, saldo, vencimento ou taxa
- **THEN** a lista é reordenada por aquela coluna, com o indicador refletindo o sentido

#### Scenario: Ordenação acumulada
- **GIVEN** a ordenação por portador ativa
- **WHEN** o usuário adiciona ordenação por vencimento
- **THEN** as duas chaves são aplicadas na ordem escolhida

### Requirement: FE-255 — Paginação de operações
O sistema SHALL se comportar conforme os cenários desta seção.
Botões de navegação e campo de tamanho percorrem a lista de operações. Fonte legada:
`risk_operations/_body.js.erb:295`, `:332`, `:345`.

#### Scenario: Navegação com total correto
- **GIVEN** 300 operações e tamanho de página 50
- **WHEN** o usuário navega para a última página
- **THEN** a lista mostra as operações 251 a 300
> Nota: corrige D-98 (comportamento legado: o total vinha contado depois de paginar, então os controles de última página ficavam incorretos)

#### Scenario: Alterar o tamanho da página
- **GIVEN** a lista carregada
- **WHEN** o usuário informa outro tamanho
- **THEN** a lista é recarregada com o novo tamanho

### Requirement: FE-256 — Widget de operação e menu de ações
O sistema SHALL se comportar conforme os cenários desta seção.
A linha abre o detalhe e o menu oferece ver mais, editar, renovar, prorrogar e remover.
Fonte legada: `risk_operations/list/_widget.html.erb`; `list/_widget.js.erb`.

#### Scenario: Ações disponíveis
- **GIVEN** uma operação de tipo sem pré-faturamento
- **WHEN** o menu é aberto
- **THEN** são oferecidas as ações de ver mais, editar, renovar, prorrogar e remover

#### Scenario: Operação de tipo com pré-faturamento
- **GIVEN** uma operação estática
- **WHEN** o menu é aberto
- **THEN** renovar e prorrogar não são oferecidos

#### Scenario: Confirmação de remoção com o rótulo correto
- **GIVEN** uma operação de risco
- **WHEN** o usuário aciona "Remover"
- **THEN** a confirmação identifica a exclusão de uma operação de risco
> Nota: corrige comportamento legado (o título da confirmação era "Excluir renegociação", rótulo copiado de outro módulo)

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** a lista é exibida
- **THEN** nenhuma ação de escrita é oferecida

### Requirement: FE-257 — Guardas do cadastro de operação
O sistema SHALL se comportar conforme os cenários desta seção.
O cadastro exige portador com limite ativo de tipo manual. Fonte legada:
`risk_operations/_body.js.erb:440-453`.

#### Scenario: Projeto sem limite manual
- **GIVEN** um projeto sem nenhum limite ativo de tipo com lançamento manual
- **WHEN** o usuário aciona "Cadastrar"
- **THEN** a tela mostra "É necessário ter um portador no projeto padrão e ao menos um limite com lançamento manual associado ao mesmo, para que seja possível cadastrar uma operação de risco"

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** a lista é exibida
- **THEN** o botão de cadastro não existe

### Requirement: FE-258 — Cascata do formulário de operação
O sistema SHALL se comportar conforme os cenários desta seção.
Empresa, portador e tipo se restringem mutuamente e ficam travados na edição. Fonte
legada: `risk_operations/new/_body.js.erb:321-410`.

#### Scenario: Cascata na criação
- **GIVEN** o formulário de nova operação
- **WHEN** o usuário escolhe empresa e depois portador
- **THEN** o seletor de portador só oferece portadores com limite ativo manual da empresa, e o de tipo só oferece tipos manuais com limite ativo para a combinação

#### Scenario: Edição trava a identidade
- **GIVEN** uma operação existente, ou uma operação originada de recebível
- **WHEN** o formulário é aberto
- **THEN** empresa, portador e tipo são exibidos como texto não editável

### Requirement: FE-259 — Campos do formulário de operação
O sistema SHALL se comportar conforme os cenários desta seção.
O formulário agrupa os campos em cadastro, datas, valores, taxa e outros. Fonte legada:
`risk_operations/new/_body.html.erb:25-237`.

#### Scenario: Blocos do formulário
- **GIVEN** o formulário aberto
- **WHEN** ele é exibido
- **THEN** aparecem Contrato, Titulo, Empresa, Portador, Tipo, Observação, as datas, Capital da Operação, Saldo Inicial, Taxa Acordada, Considerar no variável e Encerrada

#### Scenario: Capital travado na edição
- **GIVEN** uma operação existente
- **WHEN** o formulário é aberto para edição
- **THEN** o capital não é editável e o saldo inicial continua editável

#### Scenario: Textos de ajuda dos campos
- **GIVEN** o formulário aberto
- **WHEN** o usuário aciona a ajuda de um campo
- **THEN** o texto exibido descreve o campo
> AMBIGUIDADE: no legado os 13 campos compartilham o mesmo texto placeholder ("Só um teste de informações do campo..."); é preciso o texto real de cada um

### Requirement: FE-260 — Regras do formulário para tipos com pré-faturamento
O sistema SHALL se comportar conforme os cenários desta seção.
Operações estáticas escondem o bloco de datas e o indicador de encerrada. Fonte legada:
`risk_operations/new/_body.html.erb:117-159`, `:223-234`.

#### Scenario: Tipo com pré-faturamento
- **GIVEN** o formulário para um tipo com pré-faturamento
- **WHEN** ele é exibido
- **THEN** o bloco de datas e o indicador de encerrada não aparecem

#### Scenario: Datas na edição
- **GIVEN** uma operação existente de tipo sem pré-faturamento
- **WHEN** o formulário é aberto para edição
- **THEN** as datas não são editáveis pela tela
> AMBIGUIDADE: as datas continuam aceitas pela API (BE-257) mas não são editáveis pela tela; confirmar se devem passar a ser editáveis, e sob quais regras em relação aos movimentos existentes

### Requirement: FE-261 — Habilitação do salvar no formulário de operação
O sistema SHALL se comportar conforme os cenários desta seção.
O salvamento só é oferecido com todos os campos obrigatórios preenchidos e sem
incongruências. Fonte legada: `risk_operations/new/_body.js.erb:225-302`.

#### Scenario: Campos obrigatórios pendentes
- **GIVEN** o formulário com a taxa acordada em branco
- **WHEN** o usuário procura salvar
- **THEN** a ação não está disponível e a tela indica os campos pendentes

#### Scenario: Salvamento concluído
- **GIVEN** o formulário completo
- **WHEN** o usuário salva
- **THEN** a operação é gravada e a navegação volta para a lista de operações

### Requirement: FE-262 — Máscaras numéricas do formulário de operação
O sistema SHALL se comportar conforme os cenários desta seção.
Capital e saldo inicial usam máscara monetária; a taxa usa máscara decimal. Fonte
legada: `risk_operations/new/_body.js.erb:98-140`, `:276-298`.

#### Scenario: Máscara monetária
- **GIVEN** o campo de capital
- **WHEN** o usuário digita `100000,00` e sai do campo
- **THEN** o campo exibe `R$ 100.000,00` e o valor enviado é `100000.00`

#### Scenario: Máscara decimal da taxa
- **GIVEN** o campo de taxa acordada
- **WHEN** o usuário digita `1,5`
- **THEN** o valor enviado é `1.5`

### Requirement: FE-263 — Estados vazios do formulário de operação
O sistema SHALL se comportar conforme os cenários desta seção.
Sem limite manual ou sem empresa, o formulário é substituído por uma explicação. Fonte
legada: `risk_operations/new/_body.html.erb:243-253`.

#### Scenario: Sem portador com limite manual
- **GIVEN** um projeto sem limite ativo de tipo manual
- **WHEN** o formulário é aberto
- **THEN** a tela mostra a mensagem sobre a necessidade de portador com limite de lançamento manual

#### Scenario: Sem empresa
- **GIVEN** um projeto sem empresas
- **WHEN** o formulário é aberto
- **THEN** a tela mostra "Esse projeto não possui empresa, clique aqui para cadastrar uma empresa no projeto e liberar a experiencia" com o atalho de cadastro

### Requirement: FE-264 — Casca do detalhe da operação
O sistema SHALL se comportar conforme os cenários desta seção.
O detalhe tem cabeçalho com título e portador e as abas geral, movimentações e
prorrogações. Fonte legada: `risk_operations/detail/_body.html.erb:1-33`.

#### Scenario: Abas disponíveis
- **GIVEN** uma operação de tipo sem pré-faturamento
- **WHEN** o detalhe é aberto
- **THEN** aparecem as abas GERAL, MOVIMENTAÇÕES e PRORROGAÇÕES, com GERAL ativa

#### Scenario: Operação estática
- **GIVEN** uma operação de tipo com pré-faturamento
- **WHEN** o detalhe é aberto
- **THEN** a aba de prorrogações não é oferecida

#### Scenario: Endereço da tela
- **GIVEN** o detalhe aberto
- **WHEN** o usuário copia o endereço e o abre em outra aba
- **THEN** o mesmo detalhe é carregado
> Nota: corrige D-92 (comportamento legado: a navegação vivia em memória e a URL era apenas espelhada, sem deep-link nem histórico)

### Requirement: FE-265 — Cartão de cadastro do detalhe da operação
O sistema SHALL se comportar conforme os cenários desta seção.
O cartão mostra os dados da operação, com campos ausentes exibidos como `-`. Fonte
legada: `risk_operations/detail/tabs/_tab_geral.html.erb:1-86`.

#### Scenario: Campos do cartão
- **GIVEN** uma operação completa
- **WHEN** o cartão é exibido
- **THEN** ele mostra Operação, Tipo, Portador, Contrato, Projeto, Data de emissão, Data vencimento, Saldo Inicial, Capital da operação, Saldo, Taxa acordada com duas casas e Observação, além de recebível, operação original e prorrogações quando existirem

#### Scenario: Operação estática
- **GIVEN** uma operação de tipo com pré-faturamento
- **WHEN** o cartão é exibido
- **THEN** datas e prorrogações são omitidas

#### Scenario: Saldo inicial exibido com sinal
- **GIVEN** uma operação com saldo inicial armazenado como −50.000,00
- **WHEN** o cartão é exibido
- **THEN** ele mostra o valor negativo, enquanto o formulário mostra o valor absoluto
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; a mesma grandeza aparecer com sinais diferentes em duas telas é o comportamento atual (ver BE-263)

### Requirement: FE-266 — Cartão de última movimentação
O sistema SHALL se comportar conforme os cenários desta seção.
O cartão mostra data, tipo e valor da última movimentação, com destaque por sinal do
tipo. Fonte legada: `_tab_geral.html.erb:90-115`; `detail/_body.js.erb:27-56`.

#### Scenario: Movimento de débito
- **GIVEN** uma operação cuja última movimentação é um débito
- **WHEN** o cartão é atualizado
- **THEN** o valor recebe o destaque negativo

#### Scenario: Movimento de crédito
- **GIVEN** uma operação cuja última movimentação é um crédito
- **WHEN** o cartão é atualizado
- **THEN** o valor recebe o destaque positivo, usando o mesmo par de tokens semânticos do restante do produto
> Nota: corrige D-101 (comportamento legado: o módulo pintava com um par de cores próprio, distinto das variáveis de indicador positivo e negativo do sistema de cores)

#### Scenario: Operação sem movimentação
- **GIVEN** uma operação estática recém-criada
- **WHEN** o detalhe é aberto
- **THEN** o cartão indica que ainda não há movimentação e a tela carrega normalmente
> Nota: corrige comportamento legado (ver BE-255)

### Requirement: FE-267 — Cartão de renovações
O sistema SHALL se comportar conforme os cenários desta seção.
O cartão lista as renovações da operação e permite navegar até elas. Fonte legada:
`_tab_geral.html.erb:117-158`; `_tab_geral.js.erb:34-46`.

#### Scenario: Operação com renovações
- **GIVEN** uma operação raiz com 2 renovações
- **WHEN** o detalhe é aberto
- **THEN** o cartão lista as duas com identificador, emissão e vencimento, e o clique navega para a renovação

#### Scenario: Operação sem renovações
- **GIVEN** uma operação nunca renovada
- **WHEN** o detalhe é aberto
- **THEN** o cartão não é exibido

#### Scenario: Cadeia de renovações
- **GIVEN** uma cadeia de três operações encadeadas
- **WHEN** o detalhe da operação intermediária é aberto
- **THEN** ela não lista renovações, porque todas apontam para a raiz da cadeia (BE-260)

### Requirement: FE-268 — Navegação para o recebível e para a operação original
O sistema SHALL se comportar conforme os cenários desta seção.
O detalhe oferece atalhos para o recebível de origem e para a operação renovada. Fonte
legada: `_tab_geral.html.erb:17-28`; `_tab_geral.js.erb:7-33`.

#### Scenario: Operação originada de recebível
- **GIVEN** uma operação com recebível vinculado
- **WHEN** o usuário aciona o atalho
- **THEN** a navegação abre a edição daquele recebível

#### Scenario: Operação sem vínculos
- **GIVEN** uma operação sem recebível e sem operação original
- **WHEN** o detalhe é exibido
- **THEN** nenhum dos dois atalhos aparece

### Requirement: FE-269 — Aba de movimentações
O sistema SHALL se comportar conforme os cenários desta seção.
A aba lista os movimentos da operação em ordem de cadeia, com paginação. Fonte legada:
`risk_operations/detail/tabs/_tab_movements.html.erb`.

#### Scenario: Colunas da lista
- **GIVEN** uma operação com movimentos
- **WHEN** a aba é aberta
- **THEN** a lista mostra número da ordem, Data, Tipo, Valor Movimento, Saldo e Observação, além das ações

#### Scenario: Lista paginada
- **GIVEN** uma operação com 200 movimentos
- **WHEN** a aba é aberta
- **THEN** a lista traz uma página com navegação
> Nota: corrige D-20 (comportamento legado: a lista declarava mensagens de busca mas nunca paginava — ver BE-270)

#### Scenario: Estado vazio
- **GIVEN** uma operação sem movimentos
- **WHEN** a aba é aberta
- **THEN** a tela mostra "Nenhum resultado encontrado"

### Requirement: FE-270 — Widget de movimentação
O sistema SHALL se comportar conforme os cenários desta seção.
Cada movimento mostra valor com o indicador do tipo de crédito e destaque por sinal.
Fonte legada: `detail/parts/risk_movements/list/_widget.html.erb`;
`app/frontend/css/pub/components/risk_movements/widget.scss:44-56`.

#### Scenario: Movimento de crédito
- **GIVEN** um movimento de crédito de 30.000,00
- **WHEN** a linha é exibida
- **THEN** o valor aparece como `R$ 30.000,00C` com destaque positivo, e o saldo aparece em negrito

#### Scenario: Movimento de débito
- **GIVEN** um movimento de débito
- **WHEN** a linha é exibida
- **THEN** o valor aparece com o sufixo `D` e destaque negativo, usando os mesmos tokens semânticos do restante do produto
> Nota: corrige D-101 (comportamento legado: o par de cores usado divergia das variáveis de indicador positivo e negativo do sistema de cores)

#### Scenario: Observação vazia
- **GIVEN** um movimento sem observação
- **WHEN** a linha é exibida
- **THEN** a coluna mostra `-`

### Requirement: FE-271 — Painel de cadastrar e editar movimentação
O sistema SHALL se comportar conforme os cenários desta seção.
O painel captura data, tipo, valor e observação, com o salvamento liberado apenas com
valor positivo. Fonte legada: `detail/parts/risk_movements/helper/_body.html.erb`;
`helper/_body.js.erb`.

#### Scenario: Campos e modos
- **GIVEN** o painel aberto
- **WHEN** ele é exibido
- **THEN** o título indica cadastro, edição ou transferência, e o tipo é editável apenas no cadastro comum

#### Scenario: Valor zero
- **GIVEN** o valor da movimentação em zero
- **WHEN** os campos perdem o foco
- **THEN** o salvamento continua indisponível, e o servidor aplica a mesma regra
> Nota: corrige D-52 e o comportamento legado do servidor (a regra existia só no cliente — ver BE-272)

#### Scenario: Datas permitidas no seletor
- **GIVEN** uma operação com emissão em 01/03/2026 e vencimento em 30/04/2026
- **WHEN** o seletor de data da movimentação é aberto
- **THEN** ele permite escolher de 01/03/2026 a 30/04/2026, inclusive
> Nota: corrige comportamento legado (o seletor abria a partir do dia seguinte à emissão e ia até o dia seguinte ao vencimento, desalinhado da validação do servidor em ambas as pontas)

#### Scenario: Mensagem de confirmação correta
- **GIVEN** uma movimentação salva
- **WHEN** a mensagem é exibida
- **THEN** ela fala em movimentação criada ou atualizada
> Nota: corrige comportamento legado (a mensagem dizia "A previsão foi criada/atualizada com sucesso", rótulo herdado de outro módulo)

### Requirement: FE-272 — Ação de transferir
O sistema SHALL se comportar conforme os cenários desta seção.
A transferência só é oferecida a partir da operação de pré-faturamento. Fonte legada:
`_tab_movements.html.erb:10-15`; `_tab_movements.js.erb:338-371`.

#### Scenario: Operação de pré
- **GIVEN** uma operação de subtipo pré-faturamento
- **WHEN** a aba de movimentações é exibida
- **THEN** a ação "Transferir" é oferecida e abre o painel com o tipo já fixado

#### Scenario: Demais operações
- **GIVEN** uma operação de qualquer outro subtipo
- **WHEN** a aba é exibida
- **THEN** a ação não é oferecida

#### Scenario: Usuário somente-leitura
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** a aba é exibida
- **THEN** nem "Transferir" nem "Cadastrar" são oferecidos

### Requirement: FE-273 — Excluir movimentação pela tela
O sistema SHALL se comportar conforme os cenários desta seção.
A exclusão pede confirmação e atualiza a lista e o cartão de última movimentação. Fonte
legada: `detail/parts/risk_movements/list/_widget.js.erb:40-67`.

#### Scenario: Confirmação com o rótulo correto
- **GIVEN** um movimento na lista
- **WHEN** o usuário aciona "Remover"
- **THEN** a confirmação identifica a exclusão de uma movimentação
> Nota: corrige comportamento legado (o título da confirmação era "Excluir previsão", rótulo herdado de outro módulo)

#### Scenario: Exclusão concluída
- **GIVEN** a confirmação aceita
- **WHEN** a exclusão retorna sucesso
- **THEN** a lista e o cartão de última movimentação são recarregados

### Requirement: FE-274 — Aba de prorrogações e painel de prorrogar
O sistema SHALL se comportar conforme os cenários desta seção.
A aba lista as prorrogações e o painel registra uma nova data de vencimento. Fonte
legada: `_tab_extensions.html.erb`; `risk_operations/extension_helper/_body.html.erb`.

#### Scenario: Colunas da lista
- **GIVEN** uma operação com prorrogações
- **WHEN** a aba é aberta
- **THEN** a lista mostra Prorrogado Em, Data Original, Nova Data e Observação

#### Scenario: Nova data restrita
- **GIVEN** uma operação com vencimento em 30/04/2026
- **WHEN** o painel de prorrogar é aberto
- **THEN** só é possível escolher datas posteriores a 30/04/2026, e o servidor aplica a mesma regra
> Nota: corrige D-94 (comportamento legado: apenas o seletor impedia; a API aceitava retroceder o vencimento — ver BE-277)

#### Scenario: Prorrogação registrada
- **GIVEN** o painel preenchido
- **WHEN** o usuário salva
- **THEN** a tela mostra "A prorrogação foi criada com sucesso" e a lista é atualizada

### Requirement: FE-275 — Painel de renovar operação
O sistema SHALL se comportar conforme os cenários desta seção.
O painel captura a nova emissão e o novo vencimento da renovação. Fonte legada:
`risk_operations/renew_helper/_body.html.erb`; `renew_helper/_mount.js.erb:9`, `:92-99`.

#### Scenario: Datas padrão
- **GIVEN** uma operação emitida em 01/02/2026 com vencimento em 03/03/2026
- **WHEN** o painel de renovar é aberto em 10/03/2026
- **THEN** a nova emissão vem com 10/03/2026 e o novo vencimento com 09/04/2026

#### Scenario: Vencimento anterior à emissão
- **GIVEN** o painel aberto
- **WHEN** o usuário tenta escolher vencimento anterior à emissão
- **THEN** a escolha é impedida
> Nota: corrige comportamento legado (nenhum dos dois seletores tinha limite, e o servidor também não validava — ver BE-260)

#### Scenario: Mensagem de confirmação correta
- **GIVEN** uma renovação concluída
- **WHEN** a mensagem é exibida
- **THEN** ela fala em renovação criada
> Nota: corrige comportamento legado (a mensagem dizia "O tipo de operação foi criado/atualizado com sucesso", texto copiado do painel de tipos)

### Requirement: FE-276 — Estados das listas de movimentações e prorrogações
O sistema SHALL se comportar conforme os cenários desta seção.
As duas listas do detalhe sinalizam vazio e erro. Fonte legada:
`detail/parts/risk_movements/list/body.js.erb:15-19`;
`detail/parts/risk_extensions/list/body.js.erb:15-19`.

#### Scenario: Lista vazia
- **GIVEN** uma operação sem movimentos ou sem prorrogações
- **WHEN** a aba correspondente é aberta
- **THEN** a tela mostra o estado vazio

#### Scenario: Falha ao carregar
- **GIVEN** a busca retornando erro
- **WHEN** a resposta chega
- **THEN** a tela mostra um estado de erro com opção de tentar novamente
> Nota: corrige comportamento legado (as duas listas apenas alternavam o estado vazio, sem tratamento de erro)

### Requirement: FE-277 — Tela de tipos de limite
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Tipos de Limite" lista e mantém o catálogo de tipos de operação. Fonte legada:
`risk_operation_types/_body.html.erb`; `helper/_body.html.erb`.

#### Scenario: Lista e formulário
- **GIVEN** a área aberta pelo menu "Cadastro"
- **WHEN** ela é exibida
- **THEN** a lista mostra Título e Chave, ambos ordenáveis, e o formulário traz Título, Chave de integração, Ativo, permissão de lançamento manual, permissão de lançamento a partir de recebíveis e o indicador de operações estáticas

#### Scenario: Campos travados na edição
- **GIVEN** um tipo existente
- **WHEN** o formulário é aberto para edição
- **THEN** Título e o indicador de operações estáticas não são editáveis

#### Scenario: Tipo padrão do sistema
- **GIVEN** um tipo marcado como padrão
- **WHEN** a linha é exibida
- **THEN** a ação de excluir não é oferecida

#### Scenario: Permissão para cadastrar
- **GIVEN** um usuário que não é administrador, dono nem gerente
- **WHEN** a área é exibida
- **THEN** o botão de cadastro não é oferecido, e o servidor também recusa a criação
> Nota: corrige D-23 (comportamento legado: a exigência de papel existia apenas na view — ver FE-279)

### Requirement: FE-278 — Tela de tipos de movimentação
O sistema SHALL se comportar conforme os cenários desta seção.
A área "Movimentações de Risco" lista e mantém o catálogo de tipos de movimentação.
Fonte legada: `risk_movement_types/_body.html.erb`; `helper/_body.html.erb`.

#### Scenario: Lista e formulário
- **GIVEN** a área aberta pelo menu "Cadastro"
- **WHEN** ela é exibida
- **THEN** a lista mostra Título, o tipo de crédito e o indicador de exclusivo do sistema, e o formulário traz Título, Chave de integração, Ativo, Tipo de crédito e Exclusivo do Sistema

#### Scenario: Tipo de crédito na edição
- **GIVEN** um tipo existente
- **WHEN** o formulário é aberto para edição
- **THEN** o tipo de crédito é apresentado sem edição pela tela

#### Scenario: Permissão para cadastrar
- **GIVEN** um usuário sem papel de administração
- **WHEN** a área é exibida
- **THEN** o botão de cadastro não é oferecido
> Nota: corrige D-23 (comportamento legado: esta tela não exigia papel algum, ao contrário da tela de tipos de limite, apesar de serem a mesma classe de cadastro)

### Requirement: FE-279 — Permissões de interface no módulo de risco
O sistema SHALL se comportar conforme os cenários desta seção.
As permissões que hoje só existem na interface passam a valer também no servidor. Fonte
legada: `risk_operations/_body.html.erb:18`; `risk_controls/list/_widget.html.erb:24`, `:31`;
`risk_operation_types/_body.html.erb:10-11`.

#### Scenario: Usuário somente-leitura em todas as telas de risco
- **GIVEN** um usuário com `user_is_readonly`
- **WHEN** ele percorre painel, limites, operações, movimentações, prorrogações e catálogos
- **THEN** nenhuma ação de cadastrar, editar, remover, prorrogar, renovar, transferir, ativar ou desativar é oferecida

#### Scenario: Servidor recusa a escrita
- **GIVEN** o mesmo usuário chamando diretamente qualquer endpoint de escrita do módulo
- **WHEN** a requisição chega ao servidor
- **THEN** ela é recusada por autorização
> Nota: corrige D-17 e D-23 (comportamento legado: a checagem era exclusivamente de interface e todos os endpoints permaneciam abertos)

#### Scenario: Regras de papel uniformes entre os catálogos
- **GIVEN** as telas de tipos de limite e de tipos de movimentação
- **WHEN** as permissões são aplicadas
- **THEN** as duas exigem o mesmo papel para cadastrar
> Nota: corrige D-23 (comportamento legado: só a tela de tipos de limite exigia papel de administração)

### Requirement: DB-230 — Tabela `risk_controls`
O sistema SHALL se comportar conforme os cenários desta seção.
O limite guarda empresa, portador, projeto, tipo, teto, taxa, saldos iniciais e situação,
além de oito colunas do modelo anterior a 2022. Fonte legada:
`db/migrate/20210510211438_create_risk_controls.rb`; `20220611152145_change_risk_control_fields.rb`.

#### Scenario: Integridade referencial e unicidade no banco
- **GIVEN** uma gravação com empresa inexistente, ou uma trinca já existente
- **WHEN** ela é executada
- **THEN** o banco recusa a operação
> Nota: corrige D-103 (comportamento legado: nenhum índice e nenhuma chave estrangeira em nenhuma das 7 tabelas de risco)

#### Scenario: Consultas do painel indexadas
- **GIVEN** o painel de exposição apurando um projeto
- **WHEN** os limites são carregados
- **THEN** a consulta usa índice por projeto e situação

#### Scenario: Colunas do modelo anterior
- **GIVEN** as oito colunas de limite e taxa por tipo fixo, substituídas pela modelagem de uma linha por tipo
- **WHEN** o schema do ai9 é definido
- **THEN** elas não existem, desde que a carga confirme que nenhum limite ficou sem tipo de operação (ver DB-240)

### Requirement: DB-231 — Tabela `risk_entries`
O sistema SHALL se comportar conforme os cenários desta seção.
A posição diária guarda, por limite e data, os valores de carteira e os recortes de
fomento, intercompany e comissária. Fonte legada:
`db/migrate/20210510211736_create_risk_entries.rb`; `20220325145251_change_total_fields_on_risk_entries.rb`.

#### Scenario: Totais derivados
- **GIVEN** uma posição gravada
- **WHEN** ela é consultada
- **THEN** os cinco totais são coerentes com suas parcelas, independentemente dos valores enviados

#### Scenario: Recortes hardcoded dos quatro tipos originais
- **GIVEN** as colunas de fomento, intercompany e comissária
- **WHEN** o modelo é avaliado
- **THEN** fica registrado que elas não acompanham o catálogo dinâmico de tipos de operação
> AMBIGUIDADE: D-99 — a tabela tem dado mas a funcionalidade está morta (BE-269); se voltar, os recortes precisam ser modelados por tipo em vez de colunas fixas

### Requirement: DB-232 — Tabela `risk_operation_types`
O sistema SHALL se comportar conforme os cenários desta seção.
O tipo de operação guarda título, chave, situação e as três permissões que definem seu
comportamento. Fonte legada: `db/migrate/20220606124734_create_risk_operation_types.rb`.

#### Scenario: Unicidade de título e chave no banco
- **GIVEN** duas gravações concorrentes com o mesmo título
- **WHEN** ambas são processadas
- **THEN** apenas uma é aceita
> Nota: corrige D-103 (comportamento legado: a unicidade existia só na aplicação)

#### Scenario: Tipos padrão migrados
- **GIVEN** os quatro tipos padrão do legado
- **WHEN** a carga é executada
- **THEN** Fomento, Comissária, Intercompany e Auto Liquidável existem com as mesmas permissões e o mesmo indicador de pré-faturamento

### Requirement: DB-233 — Tabela `risk_operation_subtypes`
O sistema SHALL se comportar conforme os cenários desta seção.
O subtipo guarda o vínculo com o tipo, o indicador de pré-faturamento e a referência ao
subtipo irmão. Fonte legada: `db/migrate/20220621131905_create_risk_operation_subtypes.rb`.

#### Scenario: Vínculo entre subtipos irmãos
- **GIVEN** um tipo com pré-faturamento
- **WHEN** seus subtipos são consultados
- **THEN** cada um aponta para o irmão, com a referência garantida pelo banco
> Nota: corrige D-103 (comportamento legado: a referência ao irmão era um inteiro solto, sem constraint)

#### Scenario: Um subtipo pré e um não-pré por tipo
- **GIVEN** um tipo que já tem os dois subtipos
- **WHEN** um terceiro é criado
- **THEN** o banco recusa a operação
> AMBIGUIDADE: a regra limita cada tipo a exatamente dois subtipos; confirmar se deve ser mantida (ver BE-278)

### Requirement: DB-234 — Tabela `risk_movement_types`
O sistema SHALL se comportar conforme os cenários desta seção.
O tipo de movimentação guarda o sinal aplicado ao saldo e os indicadores de padrão,
transferência e exclusividade do sistema. Fonte legada:
`db/migrate/20220606160027_create_risk_movement_types.rb`.

#### Scenario: Sinal com domínio fechado
- **GIVEN** um payload com sinal fora de crédito e débito
- **WHEN** a gravação é tentada
- **THEN** ela é recusada
> Nota: corrige comportamento legado (o sinal era string livre, sem restrição)

#### Scenario: Identificação estável dos tipos funcionais
- **GIVEN** os tipos usados pelos fluxos automáticos
- **WHEN** o modelo é portado
- **THEN** eles são identificados por chave estável, e não pelo título exibido
> Nota: corrige comportamento legado (os três eram localizados por título literal — ver OPS-232)

#### Scenario: Tipos padrão migrados
- **GIVEN** os oito tipos padrão do legado
- **WHEN** a carga é executada
- **THEN** Juros, AdValorem, IOF, Liberação do Recurso, Liquidação, Juros de Mora, Transferência Recebida e Valor Transferido existem com os mesmos sinais e indicadores

### Requirement: DB-235 — Tabela `risk_operations`
O sistema SHALL se comportar conforme os cenários desta seção.
A operação guarda identificação, datas, capital, saldo inicial, saldo, taxa, situação e
os vínculos com limite, subtipo, recebível, operação original, par e recibo. Fonte
legada: `db/migrate/20220607123547_create_risk_operations.rb`.

#### Scenario: Consultas de exposição indexadas
- **GIVEN** o painel apurando a exposição de um projeto numa data
- **WHEN** as operações vigentes são carregadas
- **THEN** a consulta usa índice por projeto e janela de datas, e por limite
> Nota: corrige D-12 (comportamento legado: nenhum índice, e a apuração fazia laço de limites por laço de operações por consulta de movimentos)

#### Scenario: Sinal do saldo inicial na carga
- **GIVEN** operações legadas com saldo inicial gravado negativo
- **WHEN** a carga é executada
- **THEN** o sinal é preservado exatamente como está no legado
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário (ver BE-263)

#### Scenario: Operações estáticas identificadas
- **GIVEN** operações criadas com as datas-sentinela de hoje menos e mais 2000 anos
- **WHEN** a carga é executada
- **THEN** elas continuam permanentemente vigentes na apuração, como no legado
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; a apuração precisa produzir os mesmos números de hoje

### Requirement: DB-236 — Tabela `risk_movements`
O sistema SHALL se comportar conforme os cenários desta seção.
O movimento guarda ordem, data, tipo, valor, saldo, observação e os vínculos com a
operação e o movimento par. Fonte legada:
`db/migrate/20220608162424_create_risk_movements.rb`.

#### Scenario: Ordenação estável da cadeia
- **GIVEN** movimentos com a mesma data
- **WHEN** a cadeia é recalculada
- **THEN** a ordem é determinística, definida pela data e depois pela ordem de criação

#### Scenario: Recálculo indexado
- **GIVEN** uma operação com centenas de movimentos
- **WHEN** a cadeia é recalculada
- **THEN** a consulta usa índice por operação, data e criação
> Nota: corrige D-12 (comportamento legado: sem índice, o recálculo degradava com o volume)

#### Scenario: Coluna de ordem com nome válido
- **GIVEN** a coluna que guarda a posição do movimento na cadeia
- **WHEN** o schema do ai9 é criado
- **THEN** ela não usa uma palavra reservada da linguagem de consulta

### Requirement: DB-237 — Tabela `risk_operation_extensions`
O sistema SHALL se comportar conforme os cenários desta seção.
A prorrogação é o registro de auditoria da mudança de vencimento da operação. Fonte
legada: `db/migrate/20220616181724_create_risk_operation_extensions.rb`.

#### Scenario: Prorrogação vinculada à operação
- **GIVEN** uma operação excluída
- **WHEN** a exclusão é executada
- **THEN** suas prorrogações são removidas junto, sem deixar registros órfãos
> Nota: corrige comportamento legado (a associação não declarava dependência)

#### Scenario: Registro imutável
- **GIVEN** uma prorrogação registrada
- **WHEN** alguém tenta alterá-la
- **THEN** a alteração é recusada — o registro é histórico

#### Scenario: Nova data sempre posterior
- **GIVEN** uma prorrogação cuja nova data não é posterior à original
- **WHEN** a gravação é tentada
- **THEN** o banco recusa a operação
> Nota: corrige D-94 (comportamento legado: não havia restrição em nenhuma camada — ver BE-277)

### Requirement: DB-238 — Índices e integridade referencial do módulo de risco
O sistema SHALL se comportar conforme os cenários desta seção.
As sete tabelas de risco nascem no ai9 com chaves estrangeiras e os índices das consultas
de exposição. Fonte legada: as migrations do módulo (nenhuma declara índice ou chave
estrangeira).

#### Scenario: Índices das consultas quentes
- **GIVEN** a apuração de exposição
- **WHEN** o schema é criado
- **THEN** existem índices em `risk_movements(risk_operation_id, date)`, `risk_operations(project_id, issue_date, due_date)`, `risk_operations(risk_control_id)` e `risk_controls(project_id, is_active)`
> Nota: corrige D-103 (comportamento legado: nenhuma das sete tabelas declarava índice ou chave estrangeira)

#### Scenario: Painel escala com o volume
- **GIVEN** um projeto com muitos limites e operações
- **WHEN** o painel de exposição é apurado para uma data
- **THEN** o número de consultas não cresce por limite e por operação
> Nota: corrige D-12 (comportamento legado: a apuração fazia laço de limites por laço de operações por consulta de movimentos por data)

### Requirement: DB-239 — Fronteiras do módulo de risco com outros domínios
O sistema SHALL se comportar conforme os cenários desta seção.
Duas fronteiras ligam risco a recebíveis e a cobranças: o recebível que abre operação ou
movimento, e o recibo que trava a exclusão da operação. Fonte legada:
`db/migrate/20220610122917_add_risk_operation_type_to_receivable_entries.rb`;
`app/models/receipt.rb:4`, `:14`.

#### Scenario: Recebível exige limite ativo
- **GIVEN** um recebível associado a subtipo de operação
- **WHEN** ele é gravado sem limite ativo para a combinação
- **THEN** a gravação é recusada com "Não possui limite cadastrado"

#### Scenario: Recibo trava a exclusão da operação
- **GIVEN** uma operação com recibo emitido
- **WHEN** a exclusão é tentada
- **THEN** ela é recusada

#### Scenario: Exclusão do recebível remove a operação vinculada
- **GIVEN** um recebível com operação de risco vinculada
- **WHEN** o recebível é excluído
- **THEN** a operação é removida junto

### Requirement: DB-240 — Limites do modelo anterior a 2022
O sistema SHALL se comportar conforme os cenários desta seção.
Antes de 2022 havia um único limite por empresa e portador, com quatro pares fixos de
teto e taxa. Fonte legada: `app/models/risk_control.rb:172-210`;
`db/migrate/20210510211438`.

#### Scenario: Conversão para o modelo por tipo
- **GIVEN** um limite legado sem tipo de operação, com os quatro pares de teto e taxa
- **WHEN** a conversão é executada
- **THEN** ele vira uma linha por tipo de operação, mapeada a partir dos quatro tipos originais, e a linha antiga deixa de existir

#### Scenario: Verificação antes de descartar as colunas
- **GIVEN** a base legada
- **WHEN** a etapa de introspecção do ETL roda
- **THEN** ela reporta quantos limites ainda estão sem tipo de operação, e a carga só descarta as colunas antigas quando não resta nenhum
> AMBIGUIDADE: a interface ainda rotula esses registros como "Legado" (FE-243); é preciso confirmar se ainda existem antes de decidir o descarte

### Requirement: OPS-230 — Seeds dos tipos de limite padrão
O sistema SHALL se comportar conforme os cenários desta seção.
O sistema depende de quatro tipos de limite padrão. Fonte legada: `db/seeds.rb:18`, `:315-321`.

#### Scenario: Tipos padrão criados
- **GIVEN** um ambiente novo
- **WHEN** o seed é executado
- **THEN** existem Fomento (sem lançamento por recebível), Comissária (sem lançamento manual, com pré-faturamento), Intercompany (sem lançamento manual) e Auto Liquidável (sem lançamento manual, com pré-faturamento), cada um com seus subtipos

#### Scenario: Seed idempotente
- **GIVEN** um ambiente já semeado
- **WHEN** o seed é executado de novo
- **THEN** nenhum tipo é duplicado
> Nota: corrige comportamento legado (o seed dependia de uma flag editada manualmente no arquivo)

### Requirement: OPS-231 — Seeds dos tipos de movimentação padrão
O sistema SHALL se comportar conforme os cenários desta seção.
O sistema depende de oito tipos de movimentação padrão, três deles usados pelos fluxos
automáticos. Fonte legada: `db/seeds.rb:19`, `:323-332`.

#### Scenario: Tipos padrão criados
- **GIVEN** um ambiente novo
- **WHEN** o seed é executado
- **THEN** existem Juros, AdValorem, IOF, Liberação do Recurso, Liquidação e Juros de Mora como débito, com Liquidação e Valor Transferido como crédito, e Transferência Recebida e Valor Transferido marcados como transferência

#### Scenario: Ausência dos tipos funcionais
- **GIVEN** um ambiente sem os tipos de liberação e de transferência
- **WHEN** uma operação ou uma transferência é criada
- **THEN** a operação é recusada com erro explicativo
> Nota: corrige comportamento legado (a ausência levantava exceção não tratada em produção — ver OPS-232)

### Requirement: OPS-232 — Identificação dos tipos usados pelos fluxos automáticos
O sistema SHALL se comportar conforme os cenários desta seção.
O legado localiza três tipos de movimentação pelo título literal, o que os torna frágeis a
qualquer edição. Fonte legada: `app/models/risk_movement_type.rb:73-82`.

#### Scenario: Tipo localizado por chave estável
- **GIVEN** o tipo de liberação do recurso renomeado pela tela de catálogo
- **WHEN** uma operação é criada
- **THEN** o movimento automático continua sendo gerado corretamente
> Nota: corrige comportamento legado (a busca era por título literal e a renomeação quebrava a criação de operação e a transferência em produção)

#### Scenario: Chave ausente
- **GIVEN** um ambiente em que a chave funcional não existe
- **WHEN** o fluxo automático é acionado
- **THEN** a operação é recusada com erro explicativo, sem estado parcial

### Requirement: OPS-233 — Datas-sentinela do módulo de risco
O sistema SHALL se comportar conforme os cenários desta seção.
O legado usa datas de hoje menos e mais 2000 anos para as operações estáticas e como
limites abertos do filtro de período. Fonte legada:
`config/initializers/date_overload.rb:1-8`.

#### Scenario: Operações estáticas sempre vigentes
- **GIVEN** o par de operações criado com um limite de tipo com pré-faturamento
- **WHEN** a exposição é apurada para qualquer data
- **THEN** as duas operações são consideradas
> Nota: DEC-01 — comportamento legado preservado por decisão do usuário; o mecanismo interno pode mudar desde que a apuração produza os mesmos números

#### Scenario: Filtro de período sem limites informados
- **GIVEN** uma busca de operações sem data inicial nem final
- **WHEN** ela é executada
- **THEN** nenhuma restrição de período é aplicada, em vez de um intervalo de 4000 anos
> Nota: corrige comportamento legado (as datas-sentinela podem estourar a faixa de data do banco)

### Requirement: OPS-234 — Busca textual insensível a maiúsculas
O sistema SHALL se comportar conforme os cenários desta seção.
Todas as buscas textuais do módulo montavam o fragmento de consulta conforme o adaptador
detectado em execução. Fonte legada: `config/initializers/dev.rb:3-5`.

#### Scenario: Busca insensível a maiúsculas
- **GIVEN** um portador cadastrado como "Banco Alfa"
- **WHEN** o usuário busca por "banco alfa" em qualquer tela do módulo
- **THEN** o registro é encontrado

#### Scenario: Termo com caractere especial
- **GIVEN** um termo contendo `%` ou `_`
- **WHEN** a busca é executada
- **THEN** ele é tratado como texto literal
> Nota: corrige comportamento legado (o fragmento era interpolado direto na consulta)

### Requirement: OPS-235 — Escritas em massa do módulo de risco
O sistema SHALL se comportar conforme os cenários desta seção.
O recálculo de saldos, o espelhamento do par e a reconciliação de títulos gravam em lote
sem validações. Fonte legada: `app/models/risk_operation.rb:109`;
`app/models/risk_movement.rb:40`; `app/models/risk_control.rb:168`.

#### Scenario: Recálculo em lote sem recursão
- **GIVEN** uma operação com centenas de movimentos
- **WHEN** a cadeia é recalculada
- **THEN** saldos e numeração são gravados em uma única operação, sem disparar novo recálculo

#### Scenario: Validações de negócio continuam valendo
- **GIVEN** um movimento cuja data ficaria fora da janela da operação
- **WHEN** a gravação em lote é executada
- **THEN** a situação é detectada e reportada, em vez de contornada
> Nota: corrige comportamento legado (a gravação em lote contornava todas as validações do modelo, inclusive a janela de datas — ver BE-274)

### Requirement: OPS-236 — Rotinas de conversão e reconciliação do módulo de risco
O sistema SHALL se comportar conforme os cenários desta seção.
O legado tem duas rotinas manuais: a reconciliação dos títulos copiados do portador e a
conversão dos limites anteriores a 2022. Fonte legada:
`app/models/risk_control.rb:162-169`, `:172-210`.

#### Scenario: Reconciliação de títulos
- **GIVEN** limites cujo título divergiu do nome atual do portador
- **WHEN** a carga é executada
- **THEN** o título passa a acompanhar o portador, sem depender de rotina manual (ver BE-239)

#### Scenario: Conversão de limites legados é reversível e auditável
- **GIVEN** limites do modelo anterior a 2022
- **WHEN** a conversão é executada
- **THEN** ela é idempotente, registra o que foi convertido e não descarta as posições associadas sem relatório
> Nota: corrige comportamento legado (a rotina apagava as posições de cada limite legado, destruía o registro antigo e não era idempotente)

### Requirement: OPS-237 — Textos de ajuda do formulário de operação
O sistema SHALL se comportar conforme os cenários desta seção.
Os textos de ajuda dos 13 campos do formulário vêm de um arquivo de conteúdo. Fonte
legada: `db/seed_assets/risk_operations_help_inputs.yml`.

#### Scenario: Ajuda servida de cache
- **GIVEN** o formulário sendo aberto muitas vezes
- **WHEN** os textos são resolvidos
- **THEN** eles vêm de cache, sem leitura de disco por renderização
> Nota: corrige comportamento legado (o arquivo era lido a cada renderização)

#### Scenario: Conteúdo dos textos
- **GIVEN** os 13 campos do formulário
- **WHEN** a ajuda é exibida
- **THEN** cada campo tem seu próprio texto explicativo
> AMBIGUIDADE: no legado todos os 13 campos compartilham o mesmo texto placeholder; é preciso o conteúdo real

### Requirement: OPS-238 — Integração de recebível com o módulo de risco
O sistema SHALL se comportar conforme os cenários desta seção.
Um recebível associado a subtipo de operação gera movimento ou operação de risco, e é
recusado quando não há limite ativo. Fonte legada:
`app/models/receivable_entry.rb:25-36`, `:124-175`.

#### Scenario: Subtipo com pré-faturamento
- **GIVEN** um recebível cujo subtipo é de tipo com pré-faturamento
- **WHEN** ele é gravado
- **THEN** é criado um movimento de liberação do recurso na operação estática correspondente, com o valor líquido do recebível e a observação "Gerado automaticamente a partir de recebível"

#### Scenario: Subtipo sem pré-faturamento
- **GIVEN** um recebível cujo subtipo é de tipo sem pré-faturamento
- **WHEN** ele é gravado
- **THEN** é criada uma operação de risco com o valor líquido definitivo, vencimento na data de crédito, taxa acordada igual à taxa nominal e contrato igual ao número do borderô
> Nota: corrige D-11 (comportamento legado: o disparo em duas etapas gravava a operação com o líquido ainda sem tarifas — ver BE-183 em receivables)

#### Scenario: Recebível sem limite ativo
- **GIVEN** um recebível cuja combinação não tem limite ativo
- **WHEN** ele é gravado
- **THEN** a gravação é recusada com "Não possui limite cadastrado"

### Requirement: OPS-239 — Relatórios e exportações do módulo de risco
O sistema SHALL se comportar conforme os cenários desta seção.
Não existe nenhuma exportação nem geração de documento no módulo de risco do legado.
Fonte legada: busca em `app/` por geração de PDF e de arquivos tabulares.

#### Scenario: Nenhuma exportação é portada
- **GIVEN** o módulo de risco no ai9
- **WHEN** o escopo é definido
- **THEN** não existe exportação nem geração de documento, e toda a saída é a interface do console
> Nota: DEC-09 — só o que existe no legado é portado; qualquer exportação do painel de risco seria feature nova
