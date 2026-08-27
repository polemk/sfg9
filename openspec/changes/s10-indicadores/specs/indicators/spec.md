## ADDED Requirements

### Requirement: S10-C2 — Serviço único da grade mensal e do lançamento
A montagem da grade mensal e a gravação de cada célula SHALL passar pelo mesmo serviço
(`Indicators::EntryService`). O valor que a grade exibe para um par (indicador, mês) e o
valor que a gravação daquela célula persiste SHALL ser produzidos pela mesma regra, de modo
que a tela nunca mostre um estado que o banco não tem.

Este requisito é o contrato transversal **C2** aplicado aos lançamentos. Ele não substitui
as regras já especificadas (BE-324, BE-326, BE-327, BE-716): ele define **onde elas moram**,
que é o que impede a divergência entre leitura e escrita — a origem dos dois piores estados
do módulo legado, o autosave que falha em silêncio e a célula não lançada indistinguível de
um zero real.

#### Scenario: Grade e gravação concordam
- **GIVEN** uma grade de 12 meses exibida para um indicador
- **WHEN** uma célula é gravada e a grade é recarregada
- **THEN** o valor exibido é exatamente o valor persistido, sem nenhuma segunda regra de apresentação no cliente

#### Scenario: Falha de gravação é sempre visível
- **GIVEN** uma célula cuja gravação é recusada pelo servidor
- **WHEN** o autosave termina
- **THEN** o usuário recebe uma mensagem dizendo o motivo, a célula não fica em estado de "salvo" e uma nova tentativa é possível sem recarregar a tela

#### Scenario: Não lançado é distinguível de zero
- **GIVEN** um indicador com o mês de março lançado com valor zero e o mês de abril nunca lançado
- **WHEN** a grade é exibida
- **THEN** os dois meses são visualmente distinguíveis

#### Scenario: Otimização de consulta não muda a grade
- **GIVEN** a grade montada com uma única consulta em vez de uma consulta por indicador e mês
- **WHEN** os mesmos dados são comparados com a montagem anterior
- **THEN** o conteúdo e a ordenação alfabética dos indicadores são idênticos
