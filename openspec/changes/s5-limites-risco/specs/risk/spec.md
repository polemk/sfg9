## ADDED Requirements

### Requirement: S5-C2 — Serviço único de apuração de exposição
A apuração de exposição ao risco SHALL viver em um único serviço (`Risk::Calculator` e
`Risk::AggregateService`), chamado tanto pela leitura das telas quanto pelos caminhos de
gravação que dependem dela. Nenhuma outra camada — endpoint, model, componente React —
SHALL reimplementar qualquer fórmula de exposição.

Este requisito é o contrato transversal **C2** aplicado ao módulo de risco. Ele não
substitui nenhuma fórmula já especificada (BE-242…BE-251, BE-266): ele define **onde elas
moram e quem as chama**, que é o que impede o defeito **D-09** (prévia e gravação
divergentes) de renascer no ai9.

#### Scenario: A tela e a gravação usam o mesmo cálculo
- **GIVEN** um limite com operações e movimentos
- **WHEN** o console de risco exibe a exposição para uma data e, em seguida, um caminho de gravação apura a mesma exposição para a mesma data
- **THEN** os dois números vêm do mesmo serviço e são idênticos até o centavo

#### Scenario: O front não recalcula
- **GIVEN** qualquer tela do módulo de risco
- **WHEN** um valor de exposição é exibido
- **THEN** ele foi recebido do servidor e apenas formatado em pt-BR, sem nenhuma aritmética de exposição no cliente

#### Scenario: Uma fórmula sem golden não entra
- **GIVEN** uma fórmula de exposição implementada no serviço
- **WHEN** a fatia é dada por concluída
- **THEN** existe um teste golden dedicado àquela fórmula, com os valores de referência do comportamento legado, e ele passa

#### Scenario: Otimização não muda número
- **GIVEN** os testes golden verdes
- **WHEN** índices, `preload` ou qualquer otimização de consulta são aplicados aos agregados
- **THEN** todos os goldens continuam verdes, inclusive a ordem de soma linha a linha
