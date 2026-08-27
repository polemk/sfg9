## ADDED Requirements

### Requirement: SFG-S14-01 — Carga em lotes, idempotente e retomável
O ETL **MUST** executar a carga **por tabela, em lotes** de tamanho configurável, ordenados
pela chave primária da origem, com **transação por lote** e **checkpoint gravado na mesma
transação**; **MUST** poder ser reexecutado depois de uma interrupção continuando **do último
checkpoint**; e **MUST** ser idempotente — rodar duas vezes **MUST NOT** duplicar registro
nenhum, porque a tabela de-para (DB-ETL-02) é consultada antes de qualquer inserção.

Motivo: `DB-ETL-01..06` descrevem *o que* converter, mas nenhum descreve *como executar sem
estragar*. O precedente é explícito: o ETL Django→Rails de 2021
(`../sfg/app/models/legacy.rb`) não tinha transação nem idempotência — **rodar duas vezes
duplicava tudo**, exceto usuários, que eram buscados por e-mail. Transação única sobre a
tabela inteira também não serve: segura lock e, ao cair no fim, joga fora horas de carga.

#### Scenario: segunda execução não duplica
- **GIVEN** uma carga concluída com sucesso
- **WHEN** `sfg_etl:load` é executado de novo sobre o mesmo destino
- **THEN** as contagens por tabela permanecem idênticas e nenhuma linha nova aparece na tabela de-para

#### Scenario: retomada depois de queda
- **GIVEN** uma carga interrompida no meio de uma tabela
- **WHEN** `sfg_etl:load` é executado novamente
- **THEN** ele continua do último lote confirmado e o estado final é igual ao de uma execução sem interrupção

#### Scenario: interrupção deixa o banco consistente
- **GIVEN** um lote em andamento
- **WHEN** o processo é morto
- **THEN** o destino reflete exatamente os lotes completos, sem lote parcialmente aplicado

### Requirement: SFG-S14-02 — Conversão de hierarquia de papel por tabela de-para explícita
O ETL **MUST** converter a hierarquia de papel do legado para a do ai9 por **tabela de-para
explícita**, consumida do seed de papéis, e **MUST NOT** derivar o nível por fórmula,
cálculo ou complemento aritmético. Valor de origem que não conste da tabela **MUST** abortar
o lote e aparecer no relatório, nunca produzir um nível aproximado.

Motivo: contrato **C3**. A escala é **invertida** — no legado maior = mais poder (OG 1111 >
Admin 998 > Gerente 888 > Colaborador 799); no ai9 menor = mais poder
(`backend/app/models/user_type.rb:38-41`, OG = 1). Uma fórmula **sobrevive a valor
inesperado e produz nível plausível e errado**, e o erro **dá poder de OG a um Colaborador**
sem falhar em nenhum teste que verifique apenas que a trava existe — porque a trava existe,
apontando para o lado errado.

Todo teste de hierarquia **MUST** verificar os **dois** lados da comparação.

#### Scenario: valor conhecido converte pela tabela
- **GIVEN** um usuário legado com hierarquia de Colaborador
- **WHEN** o ETL o migra
- **THEN** o `hierarchy_level` gravado é o do Colaborador no ai9, lido da tabela de-para

#### Scenario: valor desconhecido aborta em vez de aproximar
- **GIVEN** um usuário legado com um valor de hierarquia que não consta da tabela de-para
- **WHEN** o ETL processa o lote
- **THEN** o lote aborta e o relatório nomeia o usuário e o valor encontrado, sem gravar nível algum

#### Scenario: os dois lados da comparação são testados
- **GIVEN** um Admin migrado
- **WHEN** a autorização é exercitada
- **THEN** ele **não** edita ability de OG **e** edita ability de Colaborador

### Requirement: SFG-S14-03 — Runbook de cutover com reconciliação aprovada
O cutover **MUST** ser executado a partir de um **runbook versionado** com pré-requisitos,
sequência, portões de go/no-go, responsáveis e rollback; e **MUST NOT** prosseguir sem: (a)
backup **restaurado em ambiente separado**, (b) relatório de introspecção sem desconhecidos,
(c) relatório de dry-run com toda contagem zerada ou com decisão registrada, e (d) relatório
de reconciliação **aprovado por um humano**.

A reconciliação **MUST** conter, por tabela, **contagem** origem × destino **e** amostra
determinística comparada **campo a campo**, além dos somatórios financeiros por ano —
contagem sozinha não distingue 1000 linhas migradas de 1000 linhas migradas erradas.

O runbook **MUST** ser ensaiado ponta a ponta contra o banco do seed de demonstração antes do
cutover real (DEC-16, item 3), e **MUST** declarar como bloqueada, e não como concluída,
qualquer etapa que dependa de acesso externo ainda não concedido (Q-11: disco do servidor
legado; Q-07: serviço de storage de produção).

#### Scenario: reconciliação não aprovada barra o cutover
- **GIVEN** um relatório de reconciliação com diferença não explicada
- **WHEN** o time chega ao portão de go/no-go
- **THEN** o cutover não prossegue e a diferença é investigada antes de qualquer nova carga

#### Scenario: contagem certa com valor errado é detectada
- **GIVEN** uma tabela migrada com a contagem correta mas com um cast financeiro errado
- **WHEN** a reconciliação roda
- **THEN** a amostra campo a campo e o somatório por ano acusam a divergência

#### Scenario: dependência externa não vira "concluído"
- **GIVEN** que o acesso ao disco do servidor legado não foi concedido
- **WHEN** o runbook é executado
- **THEN** a etapa de arquivos aparece como bloqueada por dependência externa e o relatório final diz explicitamente que só os registros foram migrados

### Requirement: SFG-S14-04 — Portão de `db:migrate` contra o `schema.rb`
O repositório **MUST** ter um portão automatizado que falhe quando `backend/db/schema.rb`
declarar tabela que **nenhuma migration** cria, com **allowlist explícita** das tabelas
órfãs herdadas da base ai9; e o procedimento de migration **MUST** exigir a leitura de
`git diff backend/db/schema.rb` imediatamente após cada `db:migrate`.

Motivo: os blocos do Phase 1b editaram o `schema.rb` **à mão**, sem migration de `drop` (por
decisão de design). Rodar `db:migrate` contra um banco desatualizado faz o Rails **re-dumpar
o banco real** por cima do arquivo, reintroduzindo o que foi removido — **já aconteceu, +485
linhas, revertidas**. A allowlist é explícita, e não um filtro por prefixo, para que uma
órfã **nova** falhe a build enquanto as ~25 herdadas ficam visíveis em vez de esquecidas.

#### Scenario: órfã nova falha a build
- **GIVEN** uma tabela no `schema.rb` que nenhuma migration cria e que não está na allowlist
- **WHEN** o portão roda
- **THEN** ele falha nomeando a tabela

#### Scenario: órfãs herdadas não falham, mas ficam visíveis
- **GIVEN** as tabelas órfãs herdadas da base ai9, listadas na allowlist
- **WHEN** o portão roda
- **THEN** ele passa e a allowlist continua sendo o registro explícito de que elas existem

#### Scenario: migration não reintroduz o removido
- **GIVEN** uma migration nova sendo aplicada
- **WHEN** o desenvolvedor roda `db:migrate` e lê o diff do `schema.rb`
- **THEN** o diff contém apenas o que a migration cria, e qualquer linha além disso dispara a reversão do arquivo e a recriação do banco a partir do schema
