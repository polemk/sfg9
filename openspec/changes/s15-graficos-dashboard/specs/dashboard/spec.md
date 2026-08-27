## ADDED Requirements

### Requirement: NEW-002 — Dashboard resumo da tela inicial (FEATURE NOVA, não paridade)
O ai9 **MUST** apresentar, na primeira tela do console depois do login, um resumo do projeto
corrente com quatro indicadores — **total operado** no período, **exposição** atual,
**limites no teto** e **renegociações em atraso** — e um gráfico de série do total operado
nos últimos meses.

> **Esta é uma feature nova (DEC-21), não paridade.** Ela **NÃO existe no legado** e **NÃO
> deve ser procurada lá** pelo QA do Phase 4: o `dash` do legado não referencia indicadores,
> e o dashboard que a base ai9 tinha era de vendas/assinaturas/leads e saiu no trim do
> Phase 1b (`frontend/src/app/pages/DashboardPage.tsx` documenta isso no próprio arquivo).
> No `parity-ledger.md` entra como **`new`**.

**Origem dos números.** Cada valor **MUST** vir do mesmo serviço de domínio que o calcula
para a tela de detalhe correspondente (contrato **C2**). O endpoint de resumo **MUST** ser um
compositor e **MUST NOT** conter agregação financeira própria — duas implementações da mesma
fórmula produzem dois números para a mesma coisa, que é o defeito **D-09**.

**Escopo.** O endpoint **MUST** aplicar `current_project!` (contrato **C1**), nunca
`default_scope`; projeto inexistente e projeto sem membership **MUST** responder o mesmo
status. Um agregado sem escopo vaza dado **sem mostrar a linha**.

**Permissão.** Cada indicador **MUST** respeitar a matriz de autorização da sua capability;
quando o solicitante não pode ver aquele dado, o cartão **MUST** ser omitido — **MUST NOT**
ser exibido zerado.

**Estados.** Ausência de dado **MUST** ser distinguível de zero; erro **MUST** ter estado
próprio com opção de tentar de novo; e a tela **MUST NOT** consultar a API em intervalo fixo
(Princípio 10) — atualização por refetch ou, se necessário, por Action Cable.

#### Scenario: resumo do projeto corrente
- **GIVEN** um usuário com membership em um projeto com operações no período
- **WHEN** ele entra no console
- **THEN** vê os quatro indicadores e o gráfico de série, todos referentes ao projeto corrente

#### Scenario: número igual ao da tela de detalhe
- **GIVEN** a exposição exibida no dashboard para uma data
- **WHEN** o usuário abre a tela de controle de risco na mesma data
- **THEN** o valor é exatamente o mesmo, porque veio do mesmo serviço

#### Scenario: troca de projeto troca os números
- **GIVEN** um usuário com membership em dois projetos
- **WHEN** ele troca o projeto corrente
- **THEN** os quatro indicadores passam a refletir o outro projeto

#### Scenario: sem permissão o cartão some
- **GIVEN** um usuário sem direito de ver renegociações
- **WHEN** o dashboard é carregado
- **THEN** o cartão de renegociações em atraso não aparece, em vez de aparecer zerado

#### Scenario: período sem operação
- **GIVEN** um projeto sem nenhuma operação no período
- **WHEN** o dashboard é carregado
- **THEN** os cartões mostram o estado de ausência de dado, e não `R$ 0,00`

#### Scenario: falha de carregamento
- **GIVEN** uma falha ao buscar o resumo
- **WHEN** a tela é renderizada
- **THEN** ela mostra um estado de erro com opção de tentar de novo, sem cartões em branco

#### Scenario: somente leitura enxerga o resumo
- **GIVEN** um usuário marcado como somente leitura
- **WHEN** ele entra no console
- **THEN** vê o dashboard completo, porque é leitura pura
