## ADDED Requirements

### Requirement: S8-C2 — Serviço único de cálculo da remuneração
O cálculo do valor a cobrar por uma operação SHALL viver em um único serviço
(`Structured::RemunerationCalculator`), chamado tanto pela prévia exibida na tela quanto
pela gravação do recibo. Nenhuma outra camada — endpoint, model, componente React — SHALL
reimplementar a fórmula de remuneração nem sua política de arredondamento.

Este requisito é o contrato transversal **C2** aplicado ao faturamento. Ele não substitui a
fórmula já especificada (BE-305, BE-306): ele define **onde ela mora e quem a chama**, que é
o que impede o defeito **D-09** de renascer — e é o que torna o **DEC-02** auditável em vez
de aspiracional, já que esta é a única fórmula de faturamento do sistema e hoje tem **zero
cobertura de teste**.

#### Scenario: Prévia e recibo gravado são o mesmo número
- **GIVEN** uma operação candidata a cobrança e a remuneração do projeto para o tipo dela
- **WHEN** a tela exibe a prévia do valor e, em seguida, o recibo é gerado
- **THEN** o valor exibido e o valor gravado são idênticos até o centavo, produzidos pela mesma chamada de serviço

#### Scenario: Cada fórmula tem golden
- **GIVEN** a fórmula de remuneração e a apuração de candidatos implementadas no serviço
- **WHEN** a fatia é dada por concluída
- **THEN** existe um teste golden por fórmula, com os valores de referência do comportamento legado, e ele passa

#### Scenario: Mudar o armazenamento não muda o resultado
- **GIVEN** os testes golden verdes
- **WHEN** as colunas de valor e de taxa passam a decimal com precisão padronizada
- **THEN** a sequência de operações do cálculo permanece a mesma e todos os goldens continuam verdes, inclusive nos casos de fronteira de arredondamento

#### Scenario: O front não recalcula
- **GIVEN** qualquer tela que exiba valor de remuneração ou de recibo
- **WHEN** o valor é exibido
- **THEN** ele foi recebido do servidor e apenas formatado em pt-BR, sem nenhuma aritmética de faturamento no cliente
