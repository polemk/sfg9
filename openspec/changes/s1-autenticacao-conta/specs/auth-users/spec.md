# Delta: auth-users — a superfície pública da base ai9

> **Não recria requisitos.** Os requisitos de paridade dos IDs BE-001…BE-049,
> FE-001…FE-049, DB-001…DB-018 e OPS-001…OPS-009 já existem em
> `openspec/specs/auth-users/spec.md` e estão listados no `proposal.md` desta mudança.
> Aqui estão apenas os requisitos que **nascem da base ai9** — comportamentos que o legado
> não tem e que, se ninguém escrever, ninguém verifica.

## ADDED Requirements

### Requirement: SG-01 — Nenhuma rota de auto-cadastro na superfície pública

O sistema SHALL manter a superfície pública **sem nenhuma rota de auto-cadastro**: as rotas
`pre_register`, `complete_registration`, `visitor_signup` e `visitor_signup_with_link` SHALL
sair da allowlist pública (`backend/app/controllers/api/root.rb`) **e** deixar de responder,
sendo o **convite** a única forma de entrada (DEC-18.7).

> Nota: este requisito não vem do legado — vem da base ai9. No legado o defeito equivalente
> é o D-39 (`PUBLIC_CREATE_USER = 1` + `minimal_type_to_sign_up_through_web = "Admin"`
> faziam qualquer pessoa da internet virar Admin). Não portar a rota do legado fecha uma
> porta; a segunda porta já está aberta na base e precisa ser fechada explicitamente.

#### Scenario: Anônimo tenta se cadastrar
- **GIVEN** nenhuma sessão
- **WHEN** uma requisição é enviada a qualquer uma das quatro rotas de cadastro
- **THEN** a requisição é recusada e nenhum usuário é criado

#### Scenario: Allowlist pública auditada
- **GIVEN** a lista de rotas públicas do gate central
- **WHEN** ela é inspecionada
- **THEN** nenhuma rota de cadastro aparece nela

#### Scenario: Entrada por convite
- **GIVEN** um administrador com permissão de criar usuários
- **WHEN** ele convida uma pessoa informando o papel explicitamente
- **THEN** a pessoa recebe um link de primeiro acesso e entra com o papel definido no
  convite, nunca com um papel padrão administrativo

### Requirement: SG-02 — Bloqueio de conta encerra a sessão em vigor

O sistema SHALL, ao bloquear uma conta, invalidar imediatamente as credenciais de sessão em
vigor daquele usuário e SHALL explicar o bloqueio na tentativa seguinte de acesso.

> Nota: comportamento da base ai9. O legado apenas deslogava em silêncio na requisição
> seguinte, e só um dos seus dois campos de conta desativada era consultado (D-44).

#### Scenario: Sessão ativa no momento do bloqueio
- **GIVEN** um usuário com sessão ativa
- **WHEN** um administrador bloqueia a conta
- **THEN** a próxima requisição autenticada daquele usuário é recusada, sem esperar a
  expiração natural do token

#### Scenario: Tentativa de entrar com conta bloqueada
- **GIVEN** uma conta bloqueada
- **WHEN** a pessoa tenta entrar
- **THEN** ela recebe uma explicação estruturada do bloqueio, e não um logout mudo

### Requirement: SG-03 — Impersonation nega antes de revelar

O sistema SHALL avaliar a autorização para personificar **antes** de qualquer checagem de
existência ou validade do alvo, respondendo negação de autorização sem revelar se o usuário
alvo existe.

> Nota: comportamento da base ai9 (`impersonate_service.rb:13-18` responde 404/422 antes do
> 403). No legado não havia checagem nenhuma (D-34).

#### Scenario: Ator sem permissão informa um id inexistente
- **GIVEN** um usuário sem permissão de personificar
- **WHEN** ele tenta personificar um id que não existe
- **THEN** a resposta é a mesma negação de autorização que ele receberia para um id que
  existe, sem distinguir os dois casos

#### Scenario: Ator com permissão informa um id inexistente
- **GIVEN** um usuário com permissão de personificar
- **WHEN** ele tenta personificar um id que não existe
- **THEN** a resposta indica que o alvo não foi encontrado
