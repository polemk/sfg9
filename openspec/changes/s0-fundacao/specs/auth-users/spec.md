# Delta: auth-users — hierarquia de papel (C3) e readonly no servidor

> **Não recria requisitos.** Os requisitos de paridade dos IDs BE/FE/DB/OPS já existem em
> `openspec/specs/auth-users/spec.md`. Aqui estão apenas os requisitos que **nascem da base
> ai9**: a convenção de hierarquia é invertida entre os dois sistemas, e a checagem de
> `user_is_readonly` passa a ser de servidor.

## ADDED Requirements

### Requirement: C3-01 — Hierarquia de papel na convenção do ai9 (menor = mais poder)

O sistema SHALL usar a convenção de hierarquia do ai9 — `hierarchy_level` **menor** significa
**mais** poder (OG=1, Admin=2, Gerente=3, Colaborador=4) — e SHALL converter os valores do
legado (OG=1111, Admin=998, Gerente=888, Colaborador=799) por **tabela de-para explícita**,
nunca por fórmula.

> Nota: o legado usa a escala oposta. Inverter o sinal da comparação dá poder de OG a um
> Colaborador e passa em qualquer verificação que só constate que a trava existe.

#### Scenario: Admin não alcança papel superior
- **GIVEN** um usuário Admin
- **WHEN** ele tenta alterar a permissão de um papel OG
- **THEN** a operação é negada com 403

#### Scenario: Admin alcança papel inferior
- **GIVEN** o mesmo usuário Admin
- **WHEN** ele altera a permissão de um papel Colaborador
- **THEN** a operação é aceita e registrada na trilha de auditoria

#### Scenario: Admin não alcança papel lateral
- **GIVEN** um usuário Admin
- **WHEN** ele tenta alterar a permissão de outro Admin
- **THEN** a operação é negada com 403

#### Scenario: Valor de hierarquia desconhecido na conversão
- **GIVEN** um registro legado com um valor de `hierarchy` que não está na tabela de-para
- **WHEN** a conversão é executada
- **THEN** ela falha explicitamente e o registro sai numa lista de exceções para revisão
  humana, sem receber nível inferido

### Requirement: C3-02 — Listagem de usuários filtrada pela hierarquia do solicitante

O sistema SHALL filtrar a listagem de usuários pela hierarquia de quem consulta: cada papel
enxerga o seu nível e os inferiores, nunca os superiores.

#### Scenario: Gerente não vê papéis superiores
- **GIVEN** um usuário Gerente
- **WHEN** ele lista usuários
- **THEN** nenhum OG nem Admin aparece no resultado

#### Scenario: Gerente vê papéis inferiores
- **GIVEN** o mesmo usuário Gerente
- **WHEN** ele lista usuários
- **THEN** os Colaboradores aparecem normalmente

### Requirement: RO-01 — `user_is_readonly` é negação de escrita no servidor

O sistema SHALL negar todo verbo de escrita a quem tiver concessão ativa de
`user_is_readonly`, no servidor, respondendo 403 com um `code` que o cliente reconheça — e
SHALL continuar permitindo leitura.

> Nota: no legado a ability só existia na view (D-23/D-34). Na base ai9 o mecanismo já
> existe (`restrict_visitor_access!`) e é generalizado; o predicado é novo.

#### Scenario: Escrita negada
- **GIVEN** um usuário com concessão ativa de `user_is_readonly`
- **WHEN** ele envia qualquer requisição de criação, atualização ou remoção
- **THEN** a resposta é 403 com `code` de somente leitura

#### Scenario: Leitura permitida
- **GIVEN** o mesmo usuário
- **WHEN** ele faz uma requisição de leitura
- **THEN** a resposta é normal

#### Scenario: Aceite dos Termos não é bloqueado
- **GIVEN** o mesmo usuário, que ainda não aceitou os Termos de Uso
- **WHEN** ele registra o próprio aceite
- **THEN** a operação é aceita — o modo somente leitura não pode trancá-lo fora do sistema
