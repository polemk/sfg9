## ADDED Requirements

### Requirement: S7-C2 — Serviço único da cadeia de saldos
A cadeia de saldos dos movimentos de risco SHALL viver em um único serviço
(`Risk::Calculator#recalculate_chain`), chamado tanto pela leitura das telas de extrato e
de última movimentação quanto por todo caminho de gravação que a dispare. Nenhuma outra
camada — endpoint, model, componente React — SHALL reimplementar o algoritmo de saldo.

Este requisito é o contrato transversal **C2** aplicado à cadeia de saldos. Ele não
substitui as regras já especificadas (BE-265, BE-272…BE-276): ele define **onde elas moram
e quem as chama**, que é o que impede o defeito **D-09** (a tela mostrando um número e o
extrato outro) de renascer no ai9.

#### Scenario: Extrato e saldo gravado nunca divergem
- **GIVEN** uma operação com vários movimentos
- **WHEN** o extrato é exibido e, em seguida, a operação é gravada novamente sem alteração de dados
- **THEN** o saldo de cada movimento e o saldo da operação são os mesmos antes e depois, produzidos pelo mesmo serviço

#### Scenario: Uma regra da cadeia sem golden não entra
- **GIVEN** uma regra da cadeia de saldos implementada no serviço
- **WHEN** a fatia é dada por concluída
- **THEN** existe um teste golden dedicado àquela regra, com os valores de referência do comportamento legado, e ele passa

#### Scenario: Otimização não muda saldo
- **GIVEN** os testes golden verdes
- **WHEN** índices ou escrita em lote são aplicados ao recálculo
- **THEN** a ordenação por data e criação, a renumeração da sequência a partir de 1 e todos os saldos permanecem idênticos

#### Scenario: O front não recalcula
- **GIVEN** qualquer tela de operação, extrato ou última movimentação
- **WHEN** um saldo é exibido
- **THEN** ele foi recebido do servidor e apenas formatado em pt-BR, sem nenhuma aritmética de saldo no cliente
