# Delta: console-admin — o que a casca do ai9 ainda não tem

> **Não recria requisitos.** Os requisitos de paridade dos IDs BE-390…BE-429,
> FE-390…FE-410, DB-390…DB-399 e OPS-390…OPS-399 já existem em
> `openspec/specs/console-admin/spec.md` e estão listados no `proposal.md` desta mudança.
> Aqui estão apenas os requisitos que **nascem da base ai9**.

## ADDED Requirements

### Requirement: NAV-01 — O roteador tem rota curinga de não encontrado

O roteador do console SHALL ter uma rota curinga que renderiza uma tela de não encontrado
para qualquer URL desconhecida, e SHALL **nunca** rebaixar silenciosamente a navegação para
outra área.

> Nota: requisito da base ai9 — `App.tsx` não tem rota `*` hoje, e sem ela uma área
> desconhecida vira tela em branco. No legado o vício equivalente era o rebaixamento
> silencioso para o `dash`.

#### Scenario: URL desconhecida
- **GIVEN** uma URL que não corresponde a nenhuma área
- **WHEN** ela é aberta por um usuário autenticado
- **THEN** a tela de não encontrado é exibida, com caminho de volta para o console

#### Scenario: Nada de rebaixamento silencioso
- **GIVEN** a mesma URL desconhecida
- **WHEN** ela é aberta
- **THEN** o usuário não é levado a outra área como se tivesse chegado ao lugar certo

### Requirement: NAV-02 — Pareamento de WhatsApp alcançável por rota

O console SHALL expor por rota, restrita a papel administrativo, a tela de pareamento da
instância de WhatsApp de que o envio de mensagens depende.

> Nota: requisito da base ai9. A tela existe no repositório e **não está roteada**; o envio
> resolve a instância por `PolemkInstance.first`, que exige o pareamento por QR. Sem rota,
> ninguém pareia e o login por WhatsApp para de funcionar quando a sessão da instância
> expira.

#### Scenario: Administrador pareia a instância
- **GIVEN** um usuário com papel administrativo
- **WHEN** ele abre a área de pareamento de WhatsApp
- **THEN** a tela carrega e permite parear a instância

#### Scenario: Papel sem direito
- **GIVEN** um usuário sem papel administrativo
- **WHEN** ele tenta abrir a mesma área
- **THEN** o acesso é negado e o item não aparece no menu

### Requirement: NAV-03 — Item de menu travado é decidido no item, e nenhum nasce travado

O menu SHALL avaliar a marca de item travado **no próprio item** e SHALL entregar todos os
itens do produto **destravados** por padrão.

> Nota: no legado a marca era declarada no item e lida do **grupo** (D-90), então nunca teve
> efeito — as telas ficaram em uso. Porta-se o efeito observado em produção, não a intenção
> aparente do código (DEC-15.1).

#### Scenario: Disponibilidades e cobranças visíveis
- **GIVEN** um usuário cujo papel dá acesso a disponibilidades e cobranças
- **WHEN** o menu é montado
- **THEN** os dois itens aparecem habilitados

#### Scenario: Mecanismo de travamento funciona quando usado
- **GIVEN** um item marcado como travado explicitamente
- **WHEN** o menu é montado
- **THEN** aquele item aparece travado, e apenas ele
