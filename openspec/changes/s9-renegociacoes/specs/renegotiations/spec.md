# Renegotiations — deltas da fatia S9

> Os 98 requirements de inventário desta capability **já existem** em
> `openspec/specs/renegotiations/spec.md` (BE-190…BE-229, FE-190…FE-229, DB-190…DB-199,
> OPS-190…OPS-197). **Não são recriados aqui.**
>
> O que segue são os requirements **novos**, sem ID de inventário: os contratos
> transversais **C1** e **C2** aplicados a esta fatia, e o requisito de configuração dos
> limites de anexo — que é uma melhoria **registrada** em
> `.migration-ai9/improvements-log.md`, não um comportamento legado.

## ADDED Requirements

### Requirement: C2-S9 — Agregados calculados por um serviço único, chamado pela tela e pela gravação
O sistema SHALL calcular os agregados da renegociação, da parcela e do pagamento em um
único serviço, `Renegotiations::AggregateService`, usado tanto pela prévia dos painéis de
lançamento quanto pelo caminho de gravação. O recálculo SHALL ser explícito e transacional,
e SHALL levantar em caso de falha — nunca descartar o resultado em silêncio.

Contexto: no legado `update_values!` (`app/models/renegotiation.rb:83-86`) fazia `save` sem
bang, e a cascata rodava por `after_save` em duplicidade (D-79, D-09).

#### Scenario: Prévia e gravação produzem os mesmos derivados
- **GIVEN** um rascunho de parcela com principal, juros e correção monetária
- **WHEN** o mesmo rascunho é enviado à prévia e depois gravado
- **THEN** os valores derivados exibidos e os gravados são idênticos, campo a campo

#### Scenario: Falha de recálculo é revertida e reportada
- **GIVEN** uma alteração de pagamento que torna o agregado inválido
- **WHEN** a gravação é tentada
- **THEN** a transação é revertida, o erro é devolvido ao usuário, e nem a parcela nem a
  renegociação ficam com valores parcialmente atualizados

#### Scenario: A cascata roda uma vez por operação
- **GIVEN** um pagamento sendo criado, editado ou excluído
- **WHEN** a operação é concluída
- **THEN** o recálculo da parcela e o da renegociação acontecem **exatamente uma vez**, e um
  único evento de atualização é publicado no canal

### Requirement: GOLD-S9 — Golden test por agregado da renegociação
O sistema SHALL manter, para cada agregado da renegociação, da parcela e do pagamento, um
teste golden com valores extraídos do legado. A suíte SHALL falhar se qualquer agregado
mudar de resultado.

Contexto: o legado não tem nenhum teste (D-114) e a aritmética em float é **replicada por
decisão do usuário** (DEC-02 / D-104, melhoria declinada).

#### Scenario: As três assimetrias conhecidas ficam travadas
- **GIVEN** os agregados em que o legado é reconhecidamente estranho — a mora que entra dos
  dois lados da conta da parcela, o "quanto falta" que tem piso em zero num agregado e pode
  ficar negativo em outro, e o valor presente que sobrescreve o valor da parcela
- **WHEN** a suíte de goldens roda
- **THEN** cada um tem um exemplo dedicado que fixa o comportamento legado, de modo que
  "consertar" reprove o teste em vez de mudar um número em silêncio

#### Scenario: Estados antes inalcançáveis passam a ser exercitados
- **GIVEN** uma renegociação sem parcelas e outra cujas parcelas não cobrem a dívida
- **WHEN** o estado é derivado
- **THEN** os estados "Sem parcela cadastrada" e "Inconsistente" são produzidos e os filtros
  correspondentes retornam esses registros

### Requirement: C1-S9 — Escopo por projeto e coerência de pai em todo id recebido por parâmetro
O sistema SHALL aplicar o escopo por projeto no endpoint, via `current_project!`, e NUNCA
por `default_scope`. Todo identificador recebido por parâmetro — renegociação, parcela,
pagamento ou anexo — SHALL ser resolvido **dentro** do escopo do projeto corrente, e SHALL
ser validado contra o registro pai declarado.

#### Scenario: Id de outro projeto é recusado em qualquer verbo
- **GIVEN** uma renegociação, parcela, pagamento ou anexo do projeto `P2`
- **WHEN** um usuário cujo projeto corrente é `P1` o referencia por parâmetro
- **THEN** a operação é recusada, nenhum dado de `P2` é exposto e nenhum registro de `P2` é
  alterado ou removido

#### Scenario: Inexistente e inacessível respondem igual
- **GIVEN** um identificador inexistente e um identificador de outro projeto
- **WHEN** ambos são usados na mesma rota pelo mesmo usuário
- **THEN** as duas respostas têm o mesmo status

#### Scenario: Parcela de outra renegociação é recusada
- **GIVEN** um lote de exclusão de parcelas, ou um pagamento, que referencia uma parcela
  pertencente a **outra** renegociação
- **WHEN** a operação é submetida
- **THEN** ela é recusada por inteiro, nada é apagado nem criado, e a restrição vale também
  no banco

#### Scenario: Posse da URL não é autorização
- **GIVEN** o endereço de download de um anexo de renegociação
- **WHEN** ele é acessado por quem não tem acesso ao projeto do anexo
- **THEN** o download é recusado, e o arquivo não é alcançável por nenhum caminho direto de
  servidor de arquivos estáticos

### Requirement: CFG-S9 — Limites de anexo como configuração, aplicados no servidor
O sistema SHALL tratar o número máximo de arquivos por renegociação e o tamanho máximo de
arquivo como **configuração**, com os valores padrão de 4 arquivos e 5 MB, e SHALL aplicá-los
**no servidor**.

Contexto: no legado eram constantes Ruby em `SFG::Metadata`, e a checagem só existia na
tela — lendo um seletor de outro produto e comparando com `NaN` (D-50). A mudança para
configuração está registrada em `.migration-ai9/improvements-log.md` como melhoria
intencional: mesmo comportamento, ajustável sem deploy.

#### Scenario: O limite é aplicado mesmo sem passar pela tela
- **GIVEN** uma renegociação que já tem 4 anexos
- **WHEN** um quinto arquivo é enviado direto à API
- **THEN** o envio é recusado com a razão, e o anexo não é criado

#### Scenario: O limite muda sem deploy
- **GIVEN** a configuração de limite de arquivos alterada para outro valor
- **WHEN** a aplicação lê a configuração
- **THEN** o novo limite passa a valer sem alteração de código
