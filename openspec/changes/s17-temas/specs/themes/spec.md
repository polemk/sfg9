## ADDED Requirements

### Requirement: THEME-C1 — Tema efetivo resolvido em fonte única, com override_css sob gate de servidor

O sistema **MUST** tratar o tema como dado administrável, com uma resolução de precedência
única e um gate de papel verificado no servidor, conforme detalhado abaixo.

> **Contrato transversal desta fatia, não item de paridade.** Ele **não existe no legado** —
> lá a precedência está espalhada entre `app/models/app_theme.rb:137-139` e três decorators
> (`app/decorators/models/user_decorator.rb:7, 38, 48, 76-80`), e o motor de CSS produz folha
> vazia porque `app/frontend/css/pub/templates/app_theme_template.css` está 100% comentado.
> E **não existe na base ai9**, onde o tema é código (`globals.css` + `useTheme.ts`), sem
> nenhuma entidade de tema. Os 25 IDs de paridade desta fatia têm requirements próprios em
> `openspec/specs/` e são referenciados por ID; este requirement é o contrato que os une.

O sistema **MUST** resolver o tema efetivo em **um único** serviço de servidor, na ordem
`UserTheme` do usuário → `GlobalTheme` padrão → tokens de fábrica, e o cliente **MUST**
consumir o resultado dessa resolução — **MUST NOT** reimplementar a precedência.

O sistema **MUST** garantir **no banco**, por índice único parcial, que existe no máximo um
`GlobalTheme` marcado como padrão; a garantia **MUST NOT** depender apenas de callback de
model, porque callback não vale para seed, ETL nem escrita concorrente.

O tema efetivo **MUST** ser aplicado como custom properties em tempo de execução. O sistema
**MUST NOT** gerar nem cachear folha de estilo por tema.

O campo `override_css` **MUST** ser renderizado depois dos tokens, e **MUST** ser aceito
somente de usuários com papel `og` ou `admin`, verificado **no servidor**; enviado por
qualquer outro papel, o sistema **MUST** rejeitar a requisição nomeando o campo, e **MUST
NOT** ignorá-lo em silêncio. O conteúdo aceito **MUST** ser sanitizado, sem `@import` e sem
`url()` apontando para host externo.

Todos os endpoints de tema **MUST** exigir sessão autenticada, e os de escrita **MUST**
exigir papel `og`/`admin` — fechando o comportamento do legado, em que o controlador não
declarava `requires_current_user?` nem checava papel.

#### Scenario: precedência com tema de usuário definido
- **GIVEN** um usuário com `UserTheme` próprio e um `GlobalTheme` padrão diferente
- **WHEN** o tema efetivo é resolvido
- **THEN** vence o `UserTheme` do usuário

#### Scenario: precedência sem nenhum tema cadastrado
- **GIVEN** nenhum `UserTheme` e nenhum `GlobalTheme` marcado como padrão
- **WHEN** o tema efetivo é resolvido
- **THEN** os tokens de fábrica são devolvidos, e nenhum erro é levantado

#### Scenario: dois padrões globais simultâneos são impossíveis
- **GIVEN** um `GlobalTheme` já marcado como padrão
- **WHEN** uma segunda gravação concorrente tenta marcar outro como padrão
- **THEN** o banco recusa a segunda gravação pelo índice único parcial

#### Scenario: `override_css` enviado por papel insuficiente
- **GIVEN** um usuário com papel Colaborador
- **WHEN** ele envia `override_css` na criação ou edição de um tema
- **THEN** a requisição é rejeitada nomeando o campo, e nada é persistido

#### Scenario: endpoint de tema acessado sem sessão
- **GIVEN** nenhuma sessão autenticada
- **WHEN** qualquer verbo dos endpoints de tema é chamado
- **THEN** a resposta é 401, e o tema global permanece inalterado

#### Scenario: troca do tema padrão sem rebuild
- **GIVEN** o console carregado com o tema padrão vigente
- **WHEN** um administrador ativa outro `GlobalTheme` e o console é recarregado
- **THEN** as cores mudam pelas custom properties, sem rebuild e sem invalidação de cache de CSS
