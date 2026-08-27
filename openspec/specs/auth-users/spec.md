# Auth & Users Specification

## Purpose

Identidade do produto migrada do legado `sfg`: login e sessão, cadastro, recuperação
de senha, perfil estendido, impersonation, permissões (`RoleType` → `Role` → `Ability`)
e memberships de projeto. Cobre os IDs **001–049** do `feature-inventory.md` (BE, FE, DB, OPS).
Esta é a fatia mais comprometida do legado em segurança: onde o comportamento observável
do legado é uma falha (IDOR, escalação de privilégio, senha em texto puro, token eterno),
o cenário aqui descreve o **comportamento corrigido** e a nota `> Nota: corrige D-xx`
registra o que o legado fazia.

> LACUNA DE DADOS (registrada por decisão): o **dump de `livetat_auth_role_types`
> (nomes + `hierarchy`) não existe** — o DEC-04 dispensou o `pg_dump`. Toda hierarquia
> de papéis nesta spec é **inferida do código e dos seeds** (`db/seeds.rb:40-84`:
> `OG` = 1111, `Admin` = 998, `Gerente` = 888, `Colaborador` = 799). No ai9 os RoleTypes
> nascem como **seed versionado** e a etapa de introspecção do ETL aborta se o banco real
> divergir.

## Requirements

### Requirement: BE-001 — Tela de login (`GET /users/sign_in`)

O ai9 SHALL garantir que o sistema renderiza a tela de login para usuário anônimo. Fonte legada:
`engines/auth19/config/routes.rb:2`; `engines/auth_ux19/app/controllers/livetat/auth_ux19/sessions_controller.rb:11`.

> Nota: corrige D-42 (legado: `before_action :authenticate_user!, except: [:create]` fazia
> `GET /users/sign_in` exigir sessão, tornando a tela da engine inalcançável — o login real
> acontecia em `/u/sign_in`). No ai9 existe **um único** endpoint de tela de login.

#### Scenario: Usuário anônimo abre a tela de login
- **GIVEN** nenhuma sessão ativa
- **WHEN** o usuário acessa a rota de login
- **THEN** a tela de login é renderizada com status 200

#### Scenario: Usuário já autenticado abre a tela de login
- **GIVEN** uma sessão válida
- **WHEN** o usuário acessa a rota de login
- **THEN** ele é redirecionado para a página inicial do console, sem ver o formulário

### Requirement: BE-002 — Autenticação por `login` (username ou e-mail) + senha

O ai9 SHALL garantir que o sistema autentica aceitando `login` como username **ou** e-mail (e-mail primeiro,
depois username), case-insensitive no e-mail. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/sessions_controller.rb:17-39,101-113`.

> AMBIGUIDADE: o corte por hierarquia mínima (`minimal_type_to_sign_up_through_web`,
> default `"Manager"`) aponta para um RoleType que o seed do app destrói
> (`db/seeds.rb:36`) e só era aplicado no caminho HTML — o caminho JSON, que é o do
> produto, **nunca** aplicava. Não há decisão do usuário: manter o corte (e com qual
> hierarquia mínima) ou eliminá-lo?

#### Scenario: Login com e-mail e senha corretos
- **GIVEN** um usuário ativo com e-mail e senha conhecidos
- **WHEN** ele envia `login` = e-mail e a senha correta
- **THEN** uma sessão autenticada é criada e ele é levado à página inicial do console

#### Scenario: Login com username e senha corretos
- **GIVEN** um usuário ativo que possui `username`
- **WHEN** ele envia `login` = username e a senha correta
- **THEN** a sessão é criada da mesma forma que no login por e-mail

#### Scenario: Senha incorreta
- **GIVEN** um usuário existente
- **WHEN** ele envia a senha errada
- **THEN** a resposta é 401 com mensagem genérica de credencial inválida, sem revelar se o login existe

### Requirement: BE-003 — Login da aplicação web devolve o payload do usuário

O ai9 SHALL garantir que o login usado pelo front devolve 201 com o payload canônico do usuário
(`id`, `username`, `formal`, `email`, `role_type`, `avatar`, `last_sign_in_at`,
`is_admin`, `is_og`, `app_theme_id`, `default_project_id`, `info{...}`) e cria a sessão.
Fonte legada: `app/decorators/controllers/sessions_decorator.rb:6-29`;
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/_show.json.jbuilder:1-18`.

> Nota: corrige D-28 (legado: o "projeto corrente" vinha do cookie `cached_info` e o
> servidor só validava que o projeto existia). No ai9 o `default_project_id` entra no
> **JWT** emitido no login e é validado contra `memberships` a cada request.

#### Scenario: Login bem-sucedido devolve o payload canônico
- **GIVEN** credenciais válidas
- **WHEN** o cliente autentica
- **THEN** a resposta é 201 com o payload do usuário e um token de sessão cujo tenant corrente é um projeto em que o usuário tem membership ativa

#### Scenario: Conta desativada
- **GIVEN** um usuário com `deactivated = true`
- **WHEN** ele envia credenciais corretas
- **THEN** a resposta é 401 com corpo **JSON estruturado** informando que a conta foi desativada, e nenhuma sessão é criada

#### Scenario: Credencial inválida devolve erro estruturado
- **GIVEN** um e-mail inexistente ou senha errada
- **WHEN** o cliente autentica
- **THEN** a resposta é 401 com corpo JSON (nunca string crua) e mensagem genérica

### Requirement: BE-004 — Contrato de login por token da engine (descontinuado)

O ai9 SHALL garantir que o contrato antigo `{user_email, user_token}` aceito com as chaves `user_name`/`user_email`/
`user_password` **não é portado**: no ai9 existe um único contrato de login (BE-003).
Fonte legada: `engines/auth_ux19/app/controllers/livetat/auth_ux19/sessions_controller.rb:40-50,85-99`.

> Nota: corrige D-109/D-37 por tabela (legado: quando `authentication_token` era nulo, o
> endpoint **regravava a senha enviada** no usuário antes de responder — efeito colateral
> de escrita num endpoint de leitura de token).

> AMBIGUIDADE: o inventário marca `Ambiguidade? = sim` — não foi possível confirmar se
> algum app móvel ou integração ainda consome esse contrato. Antes do cutover é preciso
> checar o log de acesso por `X-User-Token`.

#### Scenario: Chamada ao contrato antigo
- **GIVEN** um cliente que envia `user_name` + `user_password` no formato antigo
- **WHEN** a requisição chega ao ai9
- **THEN** a resposta é 410/404 documentado, e **nenhuma senha do usuário é alterada** pelo processamento da requisição

### Requirement: BE-005 — Logout de sessão (`DELETE /users/sign_out`)

O ai9 SHALL garantir que o sistema encerra a sessão do usuário e responde de forma explícita (sem depender de
template default). Logout de quem já está deslogado não é erro. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/sessions_controller.rb:54-58`;
`engines/auth19/config/initializers/devise.rb:26`.

#### Scenario: Logout com sessão ativa
- **GIVEN** um usuário autenticado
- **WHEN** ele solicita o logout
- **THEN** a sessão é encerrada e a resposta indica sucesso explicitamente

#### Scenario: Logout sem sessão ativa
- **GIVEN** nenhuma sessão
- **WHEN** o logout é solicitado
- **THEN** a resposta é sucesso (idempotente), sem erro

### Requirement: BE-006 — Revogação de token de API

O ai9 SHALL garantir que o sistema revoga o token de API do usuário autenticado. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/sessions_controller.rb:59-74`.

> Nota: corrige D-34 (legado: a revogação exigia `user_password` no corpo e **reatribuía a
> senha** ao usuário, reprocessando o hash; além disso havia `puts resource.id` em
> produção). No ai9 a revogação usa a **sessão autenticada** e não toca na senha.

#### Scenario: Revogar o próprio token
- **GIVEN** um usuário autenticado
- **WHEN** ele revoga seu token de API
- **THEN** o token deixa de autenticar novas requisições e o hash da senha permanece inalterado

#### Scenario: Revogar token de outro usuário
- **GIVEN** um usuário autenticado sem permissão administrativa
- **WHEN** ele tenta revogar o token de outro usuário
- **THEN** a resposta é 403 e nenhum token é alterado

### Requirement: BE-007 — Tela de login forçado com retorno (`redirect_url`)

O ai9 SHALL garantir que ao acessar uma página protegida sem sessão, o usuário chega à tela de login com o destino
original preservado e é levado de volta a ele após autenticar. Fonte legada:
`config/routes.rb:225`; `app/controllers/pub/start_controller.rb:11-18`.

#### Scenario: Retorno ao destino original
- **GIVEN** um usuário anônimo que tentou abrir uma página protegida
- **WHEN** ele autentica na tela de login exibida
- **THEN** é redirecionado para a página que tentou abrir originalmente

#### Scenario: Destino de retorno externo é rejeitado
- **GIVEN** um `redirect_url` apontando para outro domínio
- **WHEN** o login é concluído
- **THEN** o usuário é levado para a página inicial do console, e não para o domínio externo

### Requirement: BE-008 — Rota catch-all `GET /:identifier` de login por identificador

O ai9 SHALL garantir que a rota catch-all de um segmento que caía na tela de login **não é portada**: no ai9 não
existe rota coringa na raiz. Fonte legada: `config/routes.rb:232`;
`app/controllers/pub/start_controller.rb:11`.

> AMBIGUIDADE: o `identifier` era **ignorado** pela action. Ou é resquício de um
> multi-tenant "por escritório" abandonado, ou o handler correto se perdeu. Sem decisão
> do usuário; o DEC-07 mantém o escopo por projeto, o que sugere descarte.

#### Scenario: Caminho não mapeado
- **GIVEN** uma URL de um segmento que não corresponde a nenhuma rota
- **WHEN** ela é acessada
- **THEN** a resposta é 404, e não a tela de login

### Requirement: BE-009 — Listagem e busca de usuários (API)

O ai9 SHALL garantir que o sistema lista usuários com busca textual em `email`, `username` e `formal` (e igualdade
por `id`), ordenados por `formal ASC`, com paginação real e total de registros. Fonte
legada: `engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:15-43`.

> Nota: corrige D-34 (legado: sem qualquer filtro de autorização — qualquer usuário
> autenticado por token listava **todos**) e D-20 (legado: `@offset` era zerado quando
> **`limit`** estava em branco, não quando `offset` estava; e a paginação não era aplicada).

#### Scenario: Busca com paginação
- **GIVEN** uma base com mais usuários do que o tamanho da página
- **WHEN** o cliente pede a segunda página com `limit` e `offset`
- **THEN** a resposta traz exatamente os registros daquela faixa, ordenados por `formal`, e o total de registros que casam com o filtro

#### Scenario: `offset` sem `limit`
- **GIVEN** uma requisição com `offset` informado e `limit` omitido
- **WHEN** a busca é executada
- **THEN** o `offset` informado é respeitado e o `limit` assume o default documentado

#### Scenario: Escopo por autorização
- **GIVEN** um usuário sem permissão de leitura de usuários
- **WHEN** ele chama a listagem
- **THEN** a resposta é 403 (e nunca a lista completa da base)

### Requirement: BE-010 — Detalhe de um usuário

O ai9 SHALL garantir que o sistema devolve o detalhe de um usuário identificado por `id`. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:45-56`.

> Nota: corrige D-34 (legado: sem autorização) e o fallback em cascata
> `find_by_id → find_by_username → find_by_email → find_by_id(user_params[:id])`, que
> levantava `ActionController::ParameterMissing` (500) quando o id não existia e nenhum
> parâmetro `user` era enviado.

#### Scenario: Usuário existente
- **GIVEN** um operador autorizado
- **WHEN** ele consulta um usuário por `id`
- **THEN** a resposta é 200 com o payload canônico do usuário

#### Scenario: Usuário inexistente
- **GIVEN** um `id` que não existe
- **WHEN** a consulta é feita
- **THEN** a resposta é 404 estruturada (nunca 500)

### Requirement: BE-011 — Formulário/rota de cadastro público

O ai9 SHALL garantir que a rota de cadastro público só existe quando o cadastro público está habilitado por
configuração; desabilitado, ela responde 404. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:80-84`.

> Nota: corrige D-39 (legado: `acts_as_token_authentication_handler_for ... except:
> [:new, :create]` deixava a rota **sempre acessível**, mesmo com o botão escondido pela
> flag `SFG::Metadata::PUBLIC_CREATE_USER`).

#### Scenario: Cadastro público desabilitado
- **GIVEN** a configuração de cadastro público desligada
- **WHEN** alguém acessa a rota de cadastro diretamente
- **THEN** a resposta é 404 e nenhum usuário pode ser criado por esse caminho

### Requirement: BE-012 — Criação de usuário

O ai9 SHALL garantir que o sistema cria um usuário com `email`, `formal`, `username` opcional, `role_type`,
`kind`, `manager_id`, `is_default_member` e `info_attributes`, gerando o esqueleto do
BE-049. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:86-110,230-243`;
`app/decorators/controllers/registrations_decorator.rb:22-56,64-125`.

> Nota: corrige D-39 (legado: o cadastro público enviava `user[role_type] = "Admin"` fixo —
> qualquer pessoa da internet virava Admin). No ai9 o cadastro público, quando habilitado,
> cria o **papel de menor privilégio** e nunca aceita `role_type` vindo do cliente.

> Nota: corrige D-38 (legado: o e-mail de boas-vindas levava a **senha em texto puro**).
> No ai9 o usuário criado por um operador recebe um **link de definição de senha** de uso
> único e expiração; nenhuma senha trafega por e-mail.

> Nota: corrige D-34 (legado: nenhuma checagem de autorização — qualquer sessão criava
> usuário com qualquer papel). No ai9 só quem tem permissão de criar usuários cria, e
> apenas papéis **estritamente inferiores** ao seu na hierarquia.

#### Scenario: Operador autorizado cria usuário
- **GIVEN** um operador com permissão de criar usuários
- **WHEN** ele cria um usuário informando um papel inferior ao seu
- **THEN** o usuário é criado com papel, permissões, perfil, tema e contratos iniciais, e recebe um e-mail com link de definição de senha

#### Scenario: Tentativa de escalar privilégio na criação
- **GIVEN** um operador de papel `Gerente`
- **WHEN** ele tenta criar um usuário com papel `Admin` ou `OG`
- **THEN** a resposta é 403 e nenhum usuário é criado

#### Scenario: Cadastro público habilitado
- **GIVEN** o cadastro público habilitado por configuração
- **WHEN** um visitante se cadastra
- **THEN** o usuário é criado com o papel de menor privilégio, independentemente de qualquer `role_type` enviado na requisição

#### Scenario: Erros de validação em pt-BR
- **GIVEN** um cadastro com e-mail já usado e `formal` com menos de 3 caracteres
- **WHEN** o envio é feito
- **THEN** a resposta é 422 com um erro por campo, com rótulos em pt-BR


### Requirement: BE-013 — Atualização de usuário e troca de senha

O ai9 SHALL garantir que o sistema atualiza os dados de um usuário e, quando a nova senha é informada, exige a
senha atual correta e recusa nova senha igual à anterior. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:112-136,189-206`.

> Nota: corrige D-34 (legado: **nenhuma checagem de permissão** — qualquer usuário
> autenticado fazia PATCH em qualquer `:id`). No ai9 só o próprio dono ou um operador
> autorizado de hierarquia estritamente superior altera o registro.

> Nota: corrige D-124 (legado: o método privado
> `decorate_if_new_password_or_fck_this_nigger`, `registrations_controller.rb:113,189`,
> tem **nome ofensivo**). No ai9 o identificador é descritivo e em inglês.

#### Scenario: Usuário altera a própria senha
- **GIVEN** um usuário autenticado
- **WHEN** ele envia a senha atual correta e uma nova senha diferente
- **THEN** a senha é trocada e a resposta é 200

#### Scenario: Senha atual incorreta
- **GIVEN** um usuário autenticado
- **WHEN** ele envia a senha atual errada junto com a nova
- **THEN** a resposta é 422 com o erro "senha incorreta" e a senha permanece a mesma

#### Scenario: Nova senha igual à anterior
- **GIVEN** um usuário autenticado
- **WHEN** ele envia como nova senha exatamente a senha atual
- **THEN** a resposta é 422 informando que a nova senha não pode ser igual à anterior

#### Scenario: Alteração de outro usuário sem autorização
- **GIVEN** um usuário autenticado sem permissão administrativa
- **WHEN** ele envia PATCH para o `id` de outro usuário
- **THEN** a resposta é 403 e nenhum dado do alvo é alterado

### Requirement: BE-014 — Remoção da própria conta exigindo a senha

O ai9 SHALL garantir que o sistema remove a conta do próprio usuário mediante confirmação da senha, removendo em
cascata papel, perfil, permissões, memberships e vínculos sociais. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:160-174`.

> Nota: corrige D-34 (legado: não validava se quem pedia era o dono do `:id`).

#### Scenario: Remoção com senha correta
- **GIVEN** um usuário autenticado
- **WHEN** ele solicita a remoção da própria conta com a senha correta
- **THEN** a conta e seus registros dependentes são removidos e a sessão é encerrada

#### Scenario: Remoção com senha incorreta
- **GIVEN** um usuário autenticado
- **WHEN** ele informa a senha errada
- **THEN** a resposta é 422 com "senha incorreta para remover a conta" e nada é removido

#### Scenario: Remoção da conta de terceiro por essa via
- **GIVEN** um usuário autenticado
- **WHEN** ele envia a remoção apontando o `id` de outro usuário
- **THEN** a resposta é 403 e a conta alvo permanece intacta

### Requirement: BE-015 — Leitura do perfil estendido (`UserInfo`)

O ai9 SHALL garantir que o sistema devolve o perfil estendido de um usuário. Fonte legada:
`engines/auth_ux19/config/routes.rb:5`;
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:8-9,185-187`.

> Nota: corrige D-43 (legado: a rota apontava para a action `show_info`, que **não existe**
> no controller → `AbstractController::ActionNotFound`; e quando o `UserInfo` não existia a
> view quebrava com `@info` nil). A **rota morta `show_info` não é portada**; o que fica é
> a leitura do perfil por um endpoint que existe.

#### Scenario: Perfil existente
- **GIVEN** um usuário com perfil estendido
- **WHEN** o perfil é consultado por quem tem autorização
- **THEN** a resposta é 200 com os campos do perfil

#### Scenario: Perfil ainda não preenchido
- **GIVEN** um usuário sem dados de perfil preenchidos
- **WHEN** o perfil é consultado
- **THEN** a resposta é 200 com o perfil vazio/padrão, nunca um erro de servidor

### Requirement: BE-016 — Atualização do perfil estendido

O ai9 SHALL garantir que o sistema atualiza os 41 campos do perfil estendido (CPF/CNPJ, telefones, endereço de
entrega, contato de emergência, documento fiscal, biografia) e recalcula o
`confiability_level`. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:138-158,245-286`.

> Nota (DEC-11): a produção roda **Ruby 2.6.1 / Rails 6.0.3.2**, onde `update_attributes`
> (`registrations_controller.rb:140`) **funciona** — portanto este endpoint é **feature real
> a preservar**, não código morto. Migra-se o comportamento, com a API atual do Rails 8.

> Nota: corrige D-34 (legado: quando o alvo não era o próprio usuário, respondia **200 sem
> alterar nada, silenciosamente**). No ai9 a tentativa não autorizada é 403 explícito.

#### Scenario: Usuário atualiza o próprio perfil
- **GIVEN** um usuário autenticado
- **WHEN** ele altera CPF, telefone e endereço de entrega com dados válidos
- **THEN** o perfil é atualizado e o `confiability_level` é recalculado na mesma operação

#### Scenario: Tentativa de atualizar o perfil de outro usuário
- **GIVEN** um usuário autenticado sem permissão administrativa
- **WHEN** ele envia a atualização apontando outro `user_id`
- **THEN** a resposta é 403 (nunca 200 silencioso) e nada é gravado

#### Scenario: Campo inválido
- **GIVEN** um CPF que não passa na validação de dígito
- **WHEN** o perfil é salvo
- **THEN** a resposta é 422 com o erro traduzido para pt-BR no campo `cpf`

### Requirement: BE-017 — Avatar do usuário servido por URL

O ai9 SHALL garantir que o sistema serve a imagem de avatar do usuário; quem não tem upload recebe o avatar padrão.
Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:74-78`;
`engines/auth19/app/models/livetat/auth/user.rb:245-249`.

> Nota: corrige D-56 (legado: arquivos gravados em `public/system/` servidos publicamente,
> com a detecção de spoof de mídia desligada). No ai9 o binário vai para object storage e a
> URL é assinada.

#### Scenario: Usuário com avatar
- **GIVEN** um usuário que enviou um avatar
- **WHEN** a imagem é requisitada
- **THEN** o arquivo é entregue com o content-type real da imagem

#### Scenario: Usuário sem avatar
- **GIVEN** um usuário que nunca enviou avatar
- **WHEN** a imagem é requisitada
- **THEN** a imagem padrão é entregue com status 200 (nunca 500 por arquivo ausente)

### Requirement: BE-018 — Alteração de uma permissão individual do usuário

O ai9 SHALL garantir que o sistema altera o valor de **uma ability pertencente ao usuário indicado na URL**,
mediante autorização do operador. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:58-72`;
`engines/auth_ux19/config/routes.rb:12`.

> Nota: corrige D-34 (legado: `PUT /users/:id/abilities` **ignorava o `:id`** e alterava
> qualquer ability do sistema pelo `ability_id`, sem checar quem chamava — qualquer sessão
> autenticada virava admin por POST direto). No ai9 a ability precisa **pertencer** ao
> usuário da URL e o operador precisa de hierarquia estritamente superior à do alvo,
> conforme a regra que hoje só existe na view (`show/_abilities.html.erb:1`).

> Nota: corrige o `NoMethodError` do legado quando `ability_id` não existia
> (`ability.errors` sobre `nil`, linha 70).

#### Scenario: Operador autorizado altera a permissão de um subordinado
- **GIVEN** um operador de hierarquia superior à do usuário alvo
- **WHEN** ele altera o valor de uma ability que pertence ao alvo
- **THEN** o novo valor é gravado e a resposta é 200

#### Scenario: Ability não pertence ao usuário da URL
- **GIVEN** um `ability_id` que pertence a outro usuário ou a um `RoleType`
- **WHEN** o operador envia a alteração para `/users/:id/abilities`
- **THEN** a resposta é 404/403 e **nenhuma** ability é alterada

#### Scenario: Operador tenta alterar as próprias permissões
- **GIVEN** um operador autenticado
- **WHEN** ele tenta alterar uma ability da própria conta
- **THEN** a resposta é 403 e nada é gravado

#### Scenario: Ability inexistente
- **GIVEN** um `ability_id` que não existe
- **WHEN** a alteração é enviada
- **THEN** a resposta é 404 estruturada, nunca erro de servidor

### Requirement: BE-019 — Página "esqueci minha senha"

O ai9 SHALL garantir que o sistema oferece **uma única** tela de solicitação de recuperação de senha. Fonte legada:
`engines/auth_ux19/config/routes.rb:16`;
`engines/auth_ux19/app/controllers/livetat/auth_ux19/passwords_controller.rb:6-8`.

> Nota: corrige D-42 (legado: **duas** páginas de "esqueci a senha" — a standalone
> `/users/password/remember` e o painel embutido na tela de login — vivendo em paralelo,
> ver FE-004, FE-009 e FE-505). No ai9 o fluxo é **um só**: o painel embutido na tela de
> login. Esta spec consolida os dois.

#### Scenario: Acesso ao fluxo de recuperação
- **GIVEN** um usuário na tela de login
- **WHEN** ele escolhe "esqueci a senha"
- **THEN** o formulário de solicitação por e-mail é exibido na mesma tela

### Requirement: BE-020 — Solicitação de recuperação de senha (geração do token)

O ai9 SHALL garantir que o sistema gera um token de recuperação **novo a cada solicitação**, com expiração, e envia
o e-mail com o link. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/passwords_controller.rb:37-78`;
`engines/auth19/app/models/livetat/auth/user.rb:119-139`.

> Nota: corrige D-37 (legado: o token só era gerado **se `reset_password_sent_at` fosse
> nil**, então reenvios reaproveitavam o token antigo indefinidamente; o
> `reset_password_within = 6.hours` do Devise nunca era aplicado no fluxo custom e o texto
> do e-mail prometia 24 horas — três verdades divergentes). No ai9: **um prazo único,
> token de uso único, rotacionado a cada solicitação**.

> Nota: corrige a enumeração de contas (legado: e-mail inexistente respondia 404 com
> "O e-mail não está associado a nenhuma conta").

#### Scenario: Solicitação para e-mail existente
- **GIVEN** um e-mail cadastrado
- **WHEN** a recuperação é solicitada
- **THEN** um token novo é gerado, o anterior deixa de valer e o e-mail com o link é enfileirado

#### Scenario: Solicitação para e-mail inexistente
- **GIVEN** um e-mail que não está na base
- **WHEN** a recuperação é solicitada
- **THEN** a resposta é a **mesma** do caso anterior, sem revelar se a conta existe, e nenhum e-mail é enviado

#### Scenario: Segunda solicitação rotaciona o token
- **GIVEN** uma solicitação já feita há poucos minutos
- **WHEN** o usuário solicita novamente
- **THEN** o link do primeiro e-mail deixa de funcionar e só o mais recente é aceito

#### Scenario: Formato de e-mail inválido
- **GIVEN** um valor que não é um e-mail
- **WHEN** a solicitação é enviada
- **THEN** a resposta é 422 com mensagem de formato inválido

### Requirement: BE-021 — Tela de definição de nova senha a partir do token

O ai9 SHALL garantir que o sistema exibe o formulário de nova senha quando o token é válido e não expirado, e uma
tela de "link expirado" com o caminho para pedir um novo link quando não é. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/passwords_controller.rb:10-15`;
`app/views/livetat/auth_ux19/users/passwords/reset.html.erb:37,84`.

> Nota: corrige D-123 e D-37 (legado: a tela de "link expirado" existia no texto, mas
> `reset.html.erb:84` chamava `@user.app_theme` **fora** da guarda de `@user` nil e o
> toolbar fazia `user.app_theme.text_logo` — o usuário com link vencido recebia **500** em
> vez da mensagem).

> Nota: corrige D-42 (legado: **duas** telas de definição de nova senha — FE-007 do app e
> FE-008/FE-506 da engine, com visuais diferentes). Esta spec consolida em uma.

#### Scenario: Token válido
- **GIVEN** um link de recuperação dentro do prazo e ainda não usado
- **WHEN** o usuário o abre
- **THEN** o formulário de nova senha é exibido, identificando o usuário pelo primeiro nome

#### Scenario: Token expirado, já usado ou inexistente
- **GIVEN** um link vencido, já consumido ou adulterado
- **WHEN** o usuário o abre
- **THEN** a tela de "link expirado" é renderizada com status 200 e um botão para solicitar novo link — nunca um erro de servidor

### Requirement: BE-022 — Gravação da nova senha

O ai9 SHALL garantir que o sistema grava a nova senha quando o token é válido, **consome o token** (uso único),
registra a data da troca e notifica o usuário por e-mail. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/passwords_controller.rb:17-35`;
`engines/auth19/app/models/livetat/auth/user.rb:141-162`.

> Nota: corrige D-37 (legado: token nunca expirava nem era invalidado após o uso) e o
> `NoMethodError` (500) quando o token era inválido.

> AMBIGUIDADE: o legado reaproveita `remember_created_at` como "data da última troca de
> senha" (exibida na tela de reset). Não há decisão do usuário sobre manter esse campo
> semanticamente sobrecarregado ou criar `password_changed_at` no ai9.

#### Scenario: Nova senha aceita
- **GIVEN** um token válido e senha + confirmação iguais e com o comprimento mínimo
- **WHEN** o usuário confirma
- **THEN** a senha é trocada, o token deixa de valer para qualquer nova tentativa e um e-mail de confirmação é enfileirado

#### Scenario: Confirmação diferente
- **GIVEN** senha e confirmação divergentes
- **WHEN** o usuário confirma
- **THEN** a resposta é 422 com "deve ser igual a senha" e a senha não é trocada

#### Scenario: Reuso do mesmo link
- **GIVEN** um link já usado com sucesso
- **WHEN** o usuário tenta usá-lo de novo
- **THEN** a resposta é a tela/erro de link inválido e nenhuma senha é alterada

### Requirement: BE-023 — Login social por OAuth (Facebook)

O ai9 SHALL garantir que o login social do legado **não é portado como está**. Fonte legada:
`engines/auth_omni19/app/controllers/livetat/auth_omni19/callbacks_controller.rb:19-89`;
`engines/auth_omni19/app/decorators/user_decorator.rb:13-34`.

> Nota: corrige D-40 (legado: `provider_ignores_state: true` desligava a proteção CSRF do
> fluxo OAuth), D-39 (legado: usuário novo por OAuth recebia `role_type = "Admin"` por
> default) e o casamento de conta **por `formal` (nome completo)**, que permite account
> takeover por homônimo.

> AMBIGUIDADE: D-41 permanece **aberto** — as credenciais são placeholders
> (`FACEBOOK_APP_ID = 0`) e nenhum botão é renderizado (FE-522). Não há decisão do usuário
> entre descartar de vez ou reativar; enquanto isso, a capacidade fica registrada como
> código morto (ver spec `engines`, BE-513/BE-514).

#### Scenario: Fluxo OAuth no ai9, se reativado
- **GIVEN** um provedor OAuth configurado
- **WHEN** o callback chega sem o parâmetro `state` emitido pelo próprio servidor
- **THEN** a autenticação é recusada

#### Scenario: Vínculo de conta
- **GIVEN** um payload de provedor cujo nome completo coincide com o de um usuário existente
- **WHEN** o callback é processado
- **THEN** **nenhum** vínculo é feito por nome — só por `provider + uid` ou por e-mail verificado

### Requirement: BE-024 — Falha no callback OAuth

O ai9 SHALL garantir que quando o provedor social recusa ou falha, o sistema responde 401 com erro estruturado e não
cria sessão. Fonte legada:
`engines/auth_omni19/app/controllers/livetat/auth_omni19/callbacks_controller.rb:91-113`.

#### Scenario: Provedor recusa o consentimento
- **GIVEN** um usuário que nega a permissão no provedor
- **WHEN** o callback de falha é recebido
- **THEN** a resposta é 401 com mensagem de falha e nenhuma sessão é criada

### Requirement: BE-025 — Busca de usuários no console restrita à hierarquia

O ai9 SHALL garantir que o sistema devolve a lista de usuários que o operador pode ver, conforme a hierarquia do seu
papel, com busca textual, filtro por tipo, paginação real e total de registros. Fonte legada:
`app/controllers/pub/users_controller.rb:14-26,159-167`;
`app/decorators/models/user_decorator.rb:166-177`.

Regra de visibilidade inferida do código: `OG` vê todos; `Admin` vê `Admin`/`Gerente`/
`Colaborador`; `Gerente` vê `Gerente`/`Colaborador`; os demais veem apenas `Colaborador`.

> AMBIGUIDADE: essa regra depende dos nomes e das `hierarchy` reais de
> `livetat_auth_role_types`, cujo **dump não existe** (DEC-04). Os valores usados aqui vêm
> de `db/seeds.rb:40-84`.

> Nota: corrige D-20 (legado: `@total_count` era contado antes do limit — aqui isso é o
> comportamento correto e fica explícito: o total é o total do filtro, não o da página).

#### Scenario: Gerente busca usuários
- **GIVEN** um operador de papel `Gerente`
- **WHEN** ele busca por um termo que casa com usuários `Admin` e `Colaborador`
- **THEN** apenas os `Gerente` e `Colaborador` aparecem no resultado

#### Scenario: Total de registros com filtro
- **GIVEN** um filtro que casa com 57 usuários e uma página de 20
- **WHEN** a busca é executada
- **THEN** a resposta traz 20 registros e o total 57

### Requirement: BE-026 — Índice de usuários do console

O ai9 SHALL garantir que a tela de usuários do console exige sessão autenticada e permissão de leitura de usuários.
Fonte legada: `config/routes.rb:16,226`; `app/controllers/pub/users_controller.rb:6-8`.

> Nota: corrige D-57/D-34 (legado: `requires_current_user?` era `false` por default no
> `PubApplicationController` e o `Pub::UsersController` **não sobrescrevia** — a página
> respondia sem sessão e só quebrava depois, ao usar `current_user` nas views).

> Nota: corrige D-42 (legado: **duas rotas** distintas, `/u/users` e `/u`, para a mesma
> tela). No ai9 existe uma rota canônica.

#### Scenario: Acesso sem sessão
- **GIVEN** nenhuma sessão ativa
- **WHEN** a tela de usuários é acessada
- **THEN** o usuário é redirecionado ao login, sem qualquer dado de usuário exposto

### Requirement: BE-027 — Detalhe do usuário no console

O ai9 SHALL garantir que o sistema exibe o detalhe de um usuário com seu perfil e suas permissões individuais, para
operadores autorizados. Fonte legada: `app/controllers/pub/users_controller.rb:10-12,174-176`.

> Nota: corrige D-43 (legado: a rota `GET /u/console/users/:id` apontava para
> `users#detail`, action **inexistente**). A rota morta não é portada; o detalhe fica em uma
> rota só.

#### Scenario: Detalhe de usuário existente
- **GIVEN** um operador autorizado
- **WHEN** ele abre o detalhe de um usuário
- **THEN** vê os dados do perfil e a lista de permissões individuais do alvo

#### Scenario: Usuário inexistente
- **GIVEN** um `id` inexistente
- **WHEN** o detalhe é aberto
- **THEN** a resposta é 404 tratada, com mensagem ao usuário

### Requirement: BE-028 — Formulário de novo usuário no console

O ai9 SHALL garantir que o sistema abre **um único** formulário de criação de usuário, sempre com o mesmo estado
inicial. Fonte legada: `app/controllers/pub/users_controller.rb:84-104`.

> Nota: corrige D-42 (legado: **duas actions** para a mesma tela — `new_user` criava
> `User.new()` sem gestor e `new` criava `User.new(manager_id: current_user.id)`,
> divergindo em `manager_id`). No ai9 fica **um** fluxo: o novo usuário nasce com o
> operador corrente como gestor.

#### Scenario: Abertura do formulário de criação
- **GIVEN** um operador com permissão de criar usuários
- **WHEN** ele abre o formulário de novo usuário
- **THEN** o formulário abre em modo de criação com o operador corrente já definido como gestor

### Requirement: BE-029 — Formulário de edição de usuário no console

O ai9 SHALL garantir que o sistema abre o mesmo formulário em modo de edição, pré-preenchido com os dados do alvo.
Fonte legada: `app/controllers/pub/users_controller.rb:92-96,129-133`.

> Nota: corrige D-42 (legado: `edit_user` e `edit` eram actions **idênticas** servindo duas
> rotas). Consolidado em um fluxo.

#### Scenario: Abertura em modo de edição
- **GIVEN** um operador autorizado e um usuário existente
- **WHEN** ele abre a edição desse usuário
- **THEN** o formulário abre preenchido, em modo de edição, e o envio atualiza o registro (BE-013)

### Requirement: BE-030 — Remoção de usuário pelo console

O ai9 SHALL garantir que o sistema remove um usuário pelo console apenas para operadores com permissão de exclusão,
após confirmação explícita. Fonte legada: `app/controllers/pub/users_controller.rb:135-144`.

> Nota: corrige D-34 (legado: **não pedia senha** — diferente do BE-014 — e **não
> verificava permissão** no backend; `may_delete_users` só era consultado na view).

#### Scenario: Operador autorizado remove usuário
- **GIVEN** um operador com permissão de excluir usuários e hierarquia superior à do alvo
- **WHEN** ele confirma a remoção
- **THEN** o usuário e seus registros dependentes são removidos e a resposta indica sucesso

#### Scenario: Operador sem permissão
- **GIVEN** um operador sem permissão de excluir usuários
- **WHEN** ele envia a requisição de remoção diretamente
- **THEN** a resposta é 403 e o usuário alvo permanece na base


### Requirement: BE-031 — Impersonation (assumir a identidade de outro usuário)

O ai9 SHALL garantir que o sistema permite que um operador autorizado passe a operar como outro usuário, mantendo o
registro do usuário real, com a ação **auditada**. Fonte legada:
`config/routes.rb:14,17`; `app/controllers/pub/users_controller.rb:107-116`;
`app/controllers/pub_application_controller.rb:18-20`.

> Nota: corrige D-34 (legado: **nenhuma verificação de permissão no backend** — o gate
> `admin?`/`og?` + `!may?("user_is_readonly")` existia apenas nas views, então qualquer
> sessão autenticada podia se passar por qualquer usuário via POST direto; e a rota estava
> duplicada em GET e POST). No ai9: só `OG`/`Admin` sem `user_is_readonly`, apenas sobre
> usuários de hierarquia estritamente inferior, por verbo que altera estado, com registro
> de auditoria.

#### Scenario: Administrador impersona um subordinado
- **GIVEN** um operador `Admin` sem `user_is_readonly`
- **WHEN** ele assume a identidade de um `Colaborador`
- **THEN** as requisições seguintes operam como o alvo, o usuário real continua identificado e o evento fica registrado na auditoria

#### Scenario: Usuário comum tenta impersonar
- **GIVEN** um operador `Colaborador`
- **WHEN** ele envia a requisição de impersonation diretamente
- **THEN** a resposta é 403 e a sessão continua sendo a dele

#### Scenario: Tentativa de impersonar alguém de hierarquia igual ou superior
- **GIVEN** um operador `Admin`
- **WHEN** ele tenta impersonar um `OG`
- **THEN** a resposta é 403

#### Scenario: Alvo inexistente
- **GIVEN** um `id` que não existe
- **WHEN** a impersonation é solicitada
- **THEN** a resposta é 404 tratada

### Requirement: BE-032 — Encerrar a impersonation

O ai9 SHALL garantir que o sistema devolve a sessão ao usuário real. Fonte legada:
`config/routes.rb:18`; `app/controllers/pub/users_controller.rb:118-127`.

#### Scenario: Voltar ao usuário real
- **GIVEN** uma sessão em impersonation
- **WHEN** o operador encerra a impersonation
- **THEN** as requisições seguintes voltam a operar como o usuário real

#### Scenario: Encerrar sem impersonation ativa
- **GIVEN** uma sessão comum
- **WHEN** o encerramento é solicitado
- **THEN** a operação é um no-op com resposta de sucesso

### Requirement: BE-033 — Autocomplete de usuários para impersonation

O ai9 SHALL garantir que o sistema devolve sugestões de usuários que o operador **pode** impersonar, buscando por
`formal`, com limite pequeno de resultados. Fonte legada:
`config/routes.rb:12`; `app/controllers/pub/users_controller.rb:28-56`;
`app/decorators/models/user_decorator.rb:102-113`.

> Nota: corrige D-34 (legado: a lista de candidatos era montada por papel — `OG` via todos,
> `Admin` excluía `OG`, demais recebiam lista vazia — mas o endpoint de impersonation em si
> não checava nada; no ai9 a lista e a ação usam **a mesma** regra de autorização).

> Nota: corrige a busca acentuada (legado: `I18n.transliterate` era aplicado ao termo mas
> **não** à coluna, então nome com acento nunca casava).

#### Scenario: Busca por nome com acento
- **GIVEN** um usuário chamado "Vinícius"
- **WHEN** o operador digita "vinicius" sem acento
- **THEN** o usuário aparece nas sugestões

#### Scenario: Operador sem direito a impersonar
- **GIVEN** um operador `Colaborador`
- **WHEN** ele consulta o autocomplete
- **THEN** a resposta é 403 ou lista vazia, coerente com o que a ação de impersonation permitiria

### Requirement: BE-034 — Lista de projetos de um usuário para associação

O ai9 SHALL garantir que o sistema lista os projetos disponíveis marcando aqueles em que o usuário alvo já é membro,
de forma paginada. Fonte legada:
`config/routes.rb:15`; `app/controllers/pub/users_controller.rb:58-66`.

> Nota: corrige D-20 (legado: carregava `Project.all` sem paginação nem filtro de
> permissão) e D-34 (sem autorização; `find` levantava 404 não tratado).

#### Scenario: Listagem marcando os projetos do usuário
- **GIVEN** um operador autorizado e um usuário membro de 2 de 40 projetos
- **WHEN** ele abre a lista de projetos do usuário
- **THEN** a página traz os projetos paginados com os 2 marcados como associados

### Requirement: BE-035 — Validação de CPF em tempo real (formato e unicidade)

O ai9 SHALL garantir que o sistema valida o CPF informado quanto ao formato e à unicidade na base, devolvendo status
HTTP convencional. Fonte legada:
`config/routes.rb:10`; `app/controllers/pub/users_controller.rb:68-82`.

> Nota: corrige o uso de códigos HTTP não convencionais do legado (**405** para "CPF já
> registrado" e **406** para "não é um número de CPF válido") e o branch que não renderizava
> nada quando `user[cpf]` vinha em branco.

#### Scenario: CPF válido e livre
- **GIVEN** um CPF válido que ninguém usa
- **WHEN** ele é verificado
- **THEN** a resposta é 200 indicando que o CPF pode ser usado

#### Scenario: CPF já registrado
- **GIVEN** um CPF já vinculado a outro usuário
- **WHEN** ele é verificado
- **THEN** a resposta é 422 com a mensagem "CPF já registrado"

#### Scenario: CPF inválido
- **GIVEN** uma sequência de 11 dígitos que não passa no dígito verificador
- **WHEN** ela é verificada
- **THEN** a resposta é 422 com a mensagem de CPF inválido

#### Scenario: CPF em branco
- **GIVEN** o campo vazio
- **WHEN** a verificação é chamada
- **THEN** a resposta é 422 com mensagem de campo obrigatório (nunca resposta vazia)

### Requirement: BE-036 — Bloquear (desativar) uma conta

O ai9 SHALL garantir que o sistema marca a conta como desativada e **encerra imediatamente** as sessões e tokens
ativos do alvo. Fonte legada:
`config/routes.rb:19`; `app/controllers/pub/users_controller.rb:147-151`.

> Nota: corrige D-34 (legado: sem verificação de permissão) e o comportamento que
> contradizia o nome da action `deactivate_and_force_logout`: **nada era invalidado na
> hora** — a sessão e o `authentication_token` continuavam válidos até a próxima chamada
> AJAX (BE-038). Corrige também o `save` sem checagem de erro, que fazia o bloqueio falhar
> em silêncio quando o registro estava inválido.

#### Scenario: Operador autorizado bloqueia uma conta
- **GIVEN** um operador com permissão e um usuário alvo com sessão ativa
- **WHEN** ele bloqueia a conta
- **THEN** a conta fica desativada e a próxima requisição do alvo, em qualquer formato, é recusada com 401

#### Scenario: Falha ao gravar o bloqueio
- **GIVEN** um registro que não passa na validação ao ser salvo
- **WHEN** o bloqueio é tentado
- **THEN** a resposta é um erro explícito ao operador (nunca sucesso silencioso)

#### Scenario: Operador sem permissão
- **GIVEN** um operador sem permissão administrativa
- **WHEN** ele tenta bloquear uma conta
- **THEN** a resposta é 403 e a conta segue ativa

### Requirement: BE-037 — Desbloquear (reativar) uma conta

O ai9 SHALL garantir que o sistema reativa a conta desativada, com as mesmas garantias de autorização e de erro
explícito do BE-036. Fonte legada: `app/controllers/pub/users_controller.rb:152-156`.

> Nota: corrige D-34 (legado: sem autorização, sem resposta definida e com `save` sem
> checagem de erro).

#### Scenario: Reativação
- **GIVEN** uma conta desativada e um operador autorizado
- **WHEN** ele reativa a conta
- **THEN** o usuário volta a conseguir autenticar

### Requirement: BE-038 — Sessão de conta desativada é encerrada em qualquer requisição

O ai9 SHALL garantir que quando a conta é desativada, qualquer requisição subsequente do usuário — em qualquer
formato — é recusada e a sessão encerrada, com mensagem explicando o bloqueio. Fonte legada:
`app/controllers/pub_application_controller.rb:38-64`.

> Nota: corrige o legado, que só respondia no formato **`js`**: em navegação HTML direta o
> `respond_to` sem bloco correspondente levantava `ActionController::UnknownFormat`.

#### Scenario: Requisição de API após o bloqueio
- **GIVEN** um usuário cuja conta foi desativada durante a sessão
- **WHEN** ele faz qualquer chamada autenticada
- **THEN** a resposta é 401 com motivo do bloqueio e a sessão é encerrada

#### Scenario: Navegação HTML após o bloqueio
- **GIVEN** o mesmo usuário navegando por links
- **WHEN** ele abre uma página do console
- **THEN** é levado ao login com a mensagem de conta bloqueada (nunca um erro de formato)

### Requirement: BE-039 — Autenticação obrigatória em todo o domínio autenticado

O ai9 SHALL garantir que toda rota do domínio autenticado exige sessão válida por padrão; a exceção é explícita, rota
a rota. Fonte legada:
`app/controllers/pub_application_controller.rb:34-43`; `app/controllers/pub/console_controller.rb:5-7`.

> Nota: corrige D-57 e D-34 (legado: `requires_current_user?` era `false` por default e
> **apenas** o `Pub::ConsoleController` retornava `true` — users, permissions, memberships,
> temas e os 4 controllers de help respondiam sem sessão).

> AMBIGUIDADE: o legado tem um bloco comentado (`pub_application_controller.rb:55-63`) que
> forçava o aceite de contrato expirado antes de liberar a navegação. Não há decisão sobre
> reativar essa trava no ai9.

#### Scenario: Rota autenticada sem sessão
- **GIVEN** nenhuma sessão
- **WHEN** qualquer rota do domínio autenticado é acessada
- **THEN** a resposta é 401/redirect para o login, preservando o destino original (BE-007)

#### Scenario: Rota pública explicitamente marcada
- **GIVEN** uma rota declarada como pública (ex.: login, recuperação de senha)
- **WHEN** ela é acessada sem sessão
- **THEN** responde normalmente

### Requirement: BE-040 — Tela de permissões

O ai9 SHALL garantir que o sistema renderiza a tela de gestão de permissões por tipo de usuário. Fonte legada:
`config/routes.rb:122`; `app/controllers/pub/permissions_controller.rb:5-7`.

> Nota: corrige D-43 (legado: a action renderizava `pub/permissions/index`, caminho de view
> **inexistente** — as views reais estavam em `pub/console/parts/permissions/`; a rota é
> **rota morta** e não é portada como tal, mas a tela de permissões é feature real e existe
> no ai9 em rota única).

#### Scenario: Abertura da tela de permissões
- **GIVEN** um operador autorizado a gerir permissões
- **WHEN** ele abre a tela
- **THEN** a lista de tipos de usuário e suas permissões é exibida

### Requirement: BE-041 — Listagem dos tipos de usuário e suas permissões

O ai9 SHALL garantir que o sistema lista os `RoleType` visíveis ao operador com suas abilities condicionais,
respeitando busca e paginação. Fonte legada:
`config/routes.rb:121`; `app/controllers/pub/permissions_controller.rb:9-24`.

> Nota: corrige D-20 (legado: `q`, `l` e `o` eram lidos e **nunca aplicados** na query).

> Nota (comportamento a preservar, com autorização corrigida): o legado decide a
> visibilidade pelo **`true_user`** (usuário real, não o impersonado) — `OG` vê todos os
> tipos, os demais não veem o tipo `OG`. No ai9 essa regra é mantida e passa a valer também
> no servidor.

> AMBIGUIDADE: a lista completa de `RoleType` e suas `hierarchy` depende do dump ausente de
> `livetat_auth_role_types` (DEC-04).

#### Scenario: Operador não-OG lista os tipos
- **GIVEN** um operador `Admin`
- **WHEN** ele abre a listagem de tipos de usuário
- **THEN** todos os tipos aparecem **exceto** `OG`

#### Scenario: Impersonation não amplia a visibilidade
- **GIVEN** um operador `Admin` impersonando um `OG`
- **WHEN** ele abre a listagem
- **THEN** a visibilidade continua sendo a do usuário real (`Admin`), sem o tipo `OG`

#### Scenario: Busca e paginação aplicadas
- **GIVEN** um termo de busca e um limite de página
- **WHEN** a listagem é pedida
- **THEN** o resultado respeita o filtro e o tamanho da página

### Requirement: BE-042 — Alterar uma permissão de um tipo de usuário

O ai9 SHALL garantir que o sistema altera a permissão de um `RoleType`, e a mudança passa a valer **imediatamente
para todos os usuários daquele tipo**. Fonte legada:
`config/routes.rb:122`; `app/controllers/pub/permissions_controller.rb:26-39,55-57,69-79`.

> Nota: corrige D-35 (legado: as abilities eram **materializadas** no `Role` de cada usuário
> no momento da atribuição — alterar a ability do `RoleType` **não propagava** para os
> usuários existentes; o administrador achava que tinha revogado um acesso e não tinha). No
> ai9 a permissão efetiva é **resolvida por consulta** (tipo + overrides individuais), nunca
> congelada no usuário.

> Nota: corrige D-34 (legado: sem verificação de permissão) e a **semântica dupla** do
> endpoint, que servia tanto para ability de `RoleType` quanto de usuário individual — no
> ai9 são dois endpoints distintos (este e o BE-018).

#### Scenario: Revogar uma permissão do tipo
- **GIVEN** usuários existentes do tipo `Gerente` que hoje podem criar usuários
- **WHEN** o operador desliga essa permissão no tipo `Gerente`
- **THEN** na requisição seguinte esses usuários já **não** conseguem criar usuários

#### Scenario: Override individual prevalece
- **GIVEN** um usuário com override individual ligado para uma permissão
- **WHEN** a permissão é desligada no tipo
- **THEN** o override individual do usuário continua valendo e a decisão é auditável

#### Scenario: Operador sem permissão
- **GIVEN** um operador sem direito de administrar permissões
- **WHEN** ele envia a alteração
- **THEN** a resposta é 403 e nada muda

### Requirement: BE-043 — Remoção de uma ability

O ai9 SHALL garantir que o catálogo de permissões é **fechado e versionado** no ai9: não existe endpoint que remova
uma ability do catálogo. Fonte legada:
`config/routes.rb:122`; `app/controllers/pub/permissions_controller.rb:42-52`.

> Nota: corrige D-35 (legado: `DELETE /permissions/:id` respondia **200 em ambos os
> branches**, e remover uma ability fazia `user.may?("...")` virar `false` e os métodos
> dinâmicos `user.may_create_users?` **deixarem de existir**, quebrando as views com
> `NoMethodError`). Não havia UI para essa rota.

#### Scenario: Tentativa de remover uma permissão do catálogo
- **GIVEN** qualquer operador
- **WHEN** ele tenta remover uma permissão do catálogo por API
- **THEN** a rota não existe (404) e o catálogo permanece íntegro

#### Scenario: Permissão desconhecida consultada
- **GIVEN** uma consulta a um nome de permissão que não está no catálogo
- **WHEN** a autorização é resolvida
- **THEN** o resultado é "negado" de forma determinística, sem erro de execução

### Requirement: BE-044 — Busca de candidatos a membro de um projeto

O ai9 SHALL garantir que o sistema busca usuários que **ainda não são membros** do projeto alvo, por `formal`,
`username` ou `identifier`. Fonte legada:
`config/routes.rb:50`; `app/controllers/pub/memberships_controller.rb:13-27`.

> Nota: corrige o legado, em que as variáveis com os membros atuais (`cms`/`ids`) eram
> calculadas e **descartadas** — usuários já membros apareciam na busca; e em que `query` em
> branco deixava a coleção `nil`, quebrando a renderização. Corrige também o `puts` de
> debug em produção (linha 22).

> AMBIGUIDADE: o legado só responde para `memberable_type == 'Project'`; o suporte a
> `Company` está inacabado (qualquer outro tipo caía em template ausente). Não há decisão
> sobre portar o conceito de membership de empresa.

#### Scenario: Candidato já membro não aparece
- **GIVEN** um projeto com o usuário "Ana" já como membro
- **WHEN** o operador busca por "Ana"
- **THEN** ela **não** aparece na lista de candidatos

#### Scenario: Busca vazia
- **GIVEN** o campo de busca em branco
- **WHEN** a busca é executada
- **THEN** a resposta é uma lista vazia bem formada (nunca erro)

### Requirement: BE-045 — Vincular usuário a um projeto

O ai9 SHALL garantir que o sistema cria a membership de um usuário em um projeto, com papel default `Participante`,
garantindo unicidade por usuário e entidade. Fonte legada:
`config/routes.rb:51`; `app/controllers/pub/memberships_controller.rb:29-43`; `app/models/membership.rb:9-31`.

> Nota: corrige D-34 (legado: sem autorização — qualquer sessão vinculava qualquer usuário a
> qualquer projeto, o que, combinado com D-28, dava acesso ao dado de outro tenant).

> AMBIGUIDADE: o modelo prevê os papéis `Responsável`, `Coordenador` e `Gestor`, mas
> **nenhuma tela os define** — todos entram como `Participante`. Não há decisão sobre portar
> os outros papéis ou reduzir o conjunto.

#### Scenario: Vínculo criado
- **GIVEN** um operador autorizado no projeto e um usuário ainda não membro
- **WHEN** ele adiciona o usuário
- **THEN** a membership é criada com papel `Participante` e o usuário passa a enxergar o projeto

#### Scenario: Vínculo duplicado
- **GIVEN** um usuário que já é membro do projeto
- **WHEN** o vínculo é tentado de novo
- **THEN** a resposta é 422 com "já é membro da entidade" e nada é duplicado

#### Scenario: Operador sem autorização no projeto
- **GIVEN** um operador sem permissão de gerir membros do projeto alvo
- **WHEN** ele envia o vínculo
- **THEN** a resposta é 403

### Requirement: BE-046 — Desvincular usuário de um projeto

O ai9 SHALL garantir que o sistema remove a membership identificada pelo próprio recurso. Fonte legada:
`config/routes.rb:51`; `app/controllers/pub/memberships_controller.rb:45-59`.

> Nota: corrige D-34 (sem autorização) e o legado que **ignorava o `:id` da rota**, buscando
> pela trinca `user_id + memberable_id + memberable_type`; quando não achava, `@membership`
> ficava nil e a remoção repetida virava **500**.

#### Scenario: Remoção do vínculo
- **GIVEN** um operador autorizado e uma membership existente
- **WHEN** ele remove o vínculo pelo identificador da membership
- **THEN** o usuário deixa de enxergar o projeto

#### Scenario: Remoção repetida
- **GIVEN** uma membership já removida
- **WHEN** a remoção é enviada de novo
- **THEN** a resposta é 404 tratada (nunca 500)

### Requirement: BE-047 — Autenticação de API por token de usuário e de aplicação cliente

O ai9 SHALL garantir que o sistema autentica chamadas de API por credencial de usuário e, quando exigido, também por
credencial da aplicação cliente, aplicando a regra **em todos os formatos de resposta**.
Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/application_controller.rb:4-33`;
`engines/auth19/app/models/livetat/auth/client_application.rb:28-30`.

> Nota: corrige D-34/D-57 (legado: `lock_if_its_not_a_valid_client_app` **só era aplicado
> quando o formato não era HTML nem JS** — todas as requisições da própria UI passavam sem
> credencial de aplicação; e o `AppOrUserRequiredApplicationController` definia um fallback
> que **nunca era registrado**, sendo código morto).

> Nota: corrige D-28 (legado: o tenant corrente vinha do cookie `cached_info`). No ai9 o
> projeto corrente é uma claim do **JWT** e é validada contra `memberships` a cada request.

> AMBIGUIDADE: não se sabe **quais integrações** usam os headers `X-LAA-Agent`/`X-LAA-Token`
> nem como as `ClientApplication` são criadas hoje (não há CRUD na aplicação — ver DB-009).

#### Scenario: Chamada autenticada válida
- **GIVEN** um token de usuário válido
- **WHEN** uma rota de API é chamada
- **THEN** a requisição é processada no contexto daquele usuário e do projeto da claim de tenant

#### Scenario: Tenant da claim sem membership
- **GIVEN** um token cujo projeto corrente não corresponde a nenhuma membership ativa do usuário
- **WHEN** qualquer rota escopada por projeto é chamada
- **THEN** a resposta é 403 e nenhum dado do projeto é devolvido

#### Scenario: Credencial de aplicação inválida
- **GIVEN** uma rota que exige aplicação cliente e um par agente/token inválido
- **WHEN** a chamada é feita em **qualquer** formato, inclusive HTML
- **THEN** a resposta é 401 com erro estruturado

### Requirement: BE-048 — Identificador público de 6 caracteres por usuário

O ai9 SHALL garantir que cada usuário recebe um `identifier` público, único, de 6 caracteres `A-Z0-9`, atribuído na
criação. Fonte legada: `app/decorators/models/user_decorator.rb:4,115-141`.

> Nota: corrige o algoritmo do legado, que gerava por **recursão** até casar
> `/^[A-Z\d]{6}$/` (risco de estouro de pilha), buscava unicidade num loop cujo resultado
> **não era usado**, e não tinha índice único no banco — colisão era possível.

#### Scenario: Identificador atribuído na criação
- **GIVEN** a criação de um usuário
- **WHEN** o registro é persistido
- **THEN** ele tem um `identifier` de 6 caracteres `A-Z0-9` distinto de todos os existentes

#### Scenario: Colisão de identificador
- **GIVEN** um valor gerado que já existe
- **WHEN** a criação é processada
- **THEN** outro valor é atribuído e a unicidade é garantida também no banco

### Requirement: BE-049 — Esqueleto criado junto com o usuário

O ai9 SHALL garantir que ao criar um usuário, o sistema cria seu papel, suas permissões efetivas, o perfil estendido
com `first_name`/`last_name` derivados de `formal`, avatar padrão, cor, tema padrão, os
contratos de Termos de Uso e Política de Privacidade e, se marcado como membro padrão, as
memberships de projeto. Fonte legada:
`engines/auth19/app/models/livetat/auth/user.rb:35-40,245-283`;
`app/decorators/models/user_decorator.rb:2-8,234-262`;
`engines/auth19/lib/livetat/auth/ability_factory.rb:52-85`.

> Nota: corrige D-35 (legado: `after_initialize :include_ability_methods` **definia métodos
> na classe `User` em runtime** a cada instância carregada — mutação global de classe; e
> `create_default_role` rodava em toda inicialização, inclusive em `User.new` não
> persistido).

> Nota: corrige D-36 (legado: o `default_role_type` configurado — `"Visitor"` na engine,
> string vazia no SFG — aponta para um tipo que o seed **destrói**, tornando impossível
> criar usuário sem `role_type` explícito). No ai9 o papel default é um valor **válido e
> versionado no seed**.

> AMBIGUIDADE: os nomes e hierarquias reais dos `RoleType` dependem do dump ausente de
> `livetat_auth_role_types` (DEC-04).

#### Scenario: Criação completa o esqueleto
- **GIVEN** a criação de um usuário com papel válido
- **WHEN** o registro é persistido
- **THEN** ele já tem permissões efetivas resolvidas, perfil, avatar padrão, tema e os contratos pendentes de aceite

#### Scenario: Criação sem papel informado
- **GIVEN** uma criação que não informa `role_type`
- **WHEN** o registro é salvo
- **THEN** o papel default versionado é aplicado, sem erro de "tipo não existe"

#### Scenario: Usuário marcado como membro padrão
- **GIVEN** a criação de um usuário com `is_default_member` verdadeiro
- **WHEN** o registro é persistido
- **THEN** ele passa a ser membro de todos os projetos, e a conclusão (ou falha) desse processamento é observável (ver OPS-005)


### Requirement: FE-001 — Tela de login do produto

O ai9 SHALL garantir que a tela de login apresenta o fundo temático, a barra com o logo do tema e os fluxos de
entrar, cadastrar-se e recuperar senha na mesma página. Fonte legada:
`app/views/pub/users/sessions/new.html.erb:1-51`; `app/views/pub/users/sessions/_new.js.erb:1-50`.

#### Scenario: Abertura da tela
- **GIVEN** um visitante anônimo
- **WHEN** ele abre a tela de login
- **THEN** vê o formulário de entrada e os acessos para cadastro (quando habilitado) e recuperação de senha, com o logo do tema corrente

### Requirement: FE-002 — Painel "Entrar"

O ai9 SHALL garantir que o painel de entrada envia `login` e senha, mostra estado de carregamento no botão, aceita
Enter e leva o usuário à página inicial do console em caso de sucesso. Fonte legada:
`app/views/pub/base/nav/sign_in/_sign_in.html.erb:1-55`; `.../_sign_in.js.erb:54-108`.

> Nota: corrige D-43 (legado: o sucesso redirecionava para **`/u/console/profile`**, rota
> que **não existe** — resource ausente em `pub/console/parts/`). No ai9 o destino default é
> a página inicial do console; a rota morta não é portada.

> Nota: corrige o erro exibido como `xhr.responseText` cru (legado) — no ai9 a mensagem de
> erro é a mensagem estruturada do backend.

#### Scenario: Login por Enter
- **GIVEN** o painel de entrada preenchido
- **WHEN** o usuário pressiona Enter
- **THEN** o envio ocorre com o botão em estado de carregamento

#### Scenario: Sucesso
- **GIVEN** credenciais válidas
- **WHEN** o login conclui
- **THEN** o usuário é levado ao destino solicitado (BE-007) ou à página inicial do console

#### Scenario: Falha
- **GIVEN** credenciais inválidas
- **WHEN** o login falha
- **THEN** uma mensagem legível é exibida e o botão volta ao estado normal

### Requirement: FE-003 — Painel "Cadastre-se" (cadastro público)

O ai9 SHALL garantir que o painel de cadastro público só é exibido quando o cadastro público está habilitado e exige
o aceite dos contratos para enviar. Fonte legada:
`app/views/pub/base/nav/sign_up/_sign_up.html.erb:1-68`; `app/helpers/application_helper.rb:192-194`.

> Nota: corrige D-39 (legado: o formulário enviava `user[role_type] = "Admin"` num campo
> oculto — qualquer pessoa da internet virava Admin). No ai9 o cliente **não envia papel**.

> Nota: corrige o aceite de contrato do legado, que vinha **marcado por default e não
> bloqueava o submit**.

#### Scenario: Cadastro sem aceitar os contratos
- **GIVEN** o painel de cadastro aberto com os campos preenchidos
- **WHEN** o usuário tenta enviar sem marcar o aceite
- **THEN** o envio é bloqueado com aviso, e o aceite começa **desmarcado**

#### Scenario: Cadastro concluído
- **GIVEN** dados válidos e contratos aceitos
- **WHEN** o cadastro é enviado
- **THEN** a conta é criada com o papel de menor privilégio (BE-012) e o usuário recebe a orientação de próximo passo

### Requirement: FE-004 — Painel "Esqueceu a senha"

O ai9 SHALL garantir que o painel de recuperação valida o formato do e-mail antes de habilitar o envio e, após
enviar, troca para a mensagem de "verifique sua caixa de entrada". Fonte legada:
`app/views/pub/base/nav/reset_password/_reset_password.html.erb:1-52`; `.../_reset_password.js.erb:1-112`.

> Nota: corrige D-42 — este é o **fluxo canônico** de recuperação no ai9; a página
> standalone (FE-009/FE-505) é descontinuada.

> Nota: corrige a enumeração de contas (legado: exibia ao usuário o erro do backend
> "O e-mail não está associado a nenhuma conta").

#### Scenario: E-mail com formato inválido
- **GIVEN** um texto que não é e-mail
- **WHEN** o campo perde o foco
- **THEN** o botão de envio permanece desabilitado com aviso de formato

#### Scenario: Solicitação enviada
- **GIVEN** um e-mail com formato válido
- **WHEN** o envio conclui
- **THEN** o painel exibe a mesma mensagem neutra de "enviamos as instruções", exista ou não a conta

### Requirement: FE-005 — Login com Facebook (interface)

O ai9 SHALL garantir que o botão de login social **não existe** na interface do legado e não é portado. Fonte legada:
`app/views/pub/base/nav/sign_in/_sign_in.js.erb:1,22-52`.

> Nota: corrige D-40/D-41 (legado: apenas o handler JS `signWithFacebook` sobrevive — o
> seletor `.facebook_button` não existe em nenhum HTML). Registrado como código morto; ver a
> spec `engines` (FE-522).

> AMBIGUIDADE: D-41 segue aberto — descartar de vez ou reativar o login social no ai9?

#### Scenario: Tela de login no ai9
- **GIVEN** a tela de login
- **WHEN** ela é renderizada
- **THEN** nenhum botão de login social é exibido enquanto a decisão do D-41 não for tomada

### Requirement: FE-006 — Aviso de "é preciso entrar para acessar essa página"

O ai9 SHALL garantir que quando o usuário é levado ao login por tentar abrir uma página protegida, a tela exibe o
aviso correspondente. Fonte legada:
`app/views/pub/users/sessions/_new.js.erb:45-50`; `app/views/pub/base/nav/sign_in/_sign_in.html.erb:1`.

> Nota: corrige o legado, em que o texto era injetado mas o container `.warning_message`
> estava **comentado no HTML** — a mensagem nunca aparecia.

#### Scenario: Redirecionado ao login
- **GIVEN** um visitante que tentou abrir uma página protegida
- **WHEN** a tela de login é exibida
- **THEN** o aviso "você precisa entrar na sua conta antes de acessar essa página" está visível

### Requirement: FE-007 — Tela de definição de nova senha (canônica)

O ai9 SHALL garantir que a tela de nova senha exibe o nome do usuário, exige senha e confirmação iguais para habilitar
o envio, e ao concluir leva o usuário ao login. Fonte legada:
`app/views/livetat/auth_ux19/users/passwords/reset.html.erb:1-85`; `.../_reset.js.erb:1-103`.

> Nota: corrige D-42 (legado: **duas** telas de reset, esta e a da engine em Materialize —
> FE-008/FE-506). Esta é a canônica; a outra é descontinuada.

#### Scenario: Confirmação divergente
- **GIVEN** os dois campos preenchidos com valores diferentes
- **WHEN** o usuário tenta enviar
- **THEN** o envio fica bloqueado com aviso de que a confirmação difere

#### Scenario: Troca concluída
- **GIVEN** senha e confirmação iguais e válidas
- **WHEN** o envio conclui
- **THEN** o usuário vê a confirmação e é levado ao login

### Requirement: FE-008 — Tela de nova senha da engine (descontinuada)

O ai9 SHALL garantir que a segunda tela de definição de nova senha, com visual Materialize da engine, **não é
portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/passwords/reset.html.erb:1-95`.

> Nota: corrige D-42 — consolidado no FE-007.

#### Scenario: Rota da tela da engine
- **GIVEN** o ai9 em produção
- **WHEN** a rota da tela antiga é acessada
- **THEN** ela não existe (404) e o único caminho de definição de senha é o do FE-007

### Requirement: FE-009 — Página standalone "esqueci a senha" (descontinuada)

O ai9 SHALL garantir que a página independente de recuperação de senha **não é portada**. Fonte legada:
`app/views/livetat/auth_ux19/users/passwords/remember.html.erb:1-70`;
`engines/auth_ux19/app/views/livetat/auth_ux19/users/passwords/remember.html.erb`.

> Nota: corrige D-42 — o fluxo canônico é o painel embutido (FE-004).

#### Scenario: Rota standalone
- **GIVEN** o ai9 em produção
- **WHEN** a rota da página standalone é acessada
- **THEN** o usuário é levado ao fluxo canônico de recuperação

### Requirement: FE-010 — Estado "link de recuperação expirado"

O ai9 SHALL garantir que quando o token é inválido, expirado ou já usado, a tela mostra a mensagem de link expirado e
um caminho para pedir um novo link. Fonte legada:
`app/views/livetat/auth_ux19/users/passwords/reset.html.erb:43-45`.

> Nota: corrige D-123 (legado: a mesma view usava `@user.app_theme` fora da guarda de nil —
> `reset.html.erb:84` — e o toolbar `_toolbar_reset_body.html.erb:5` usava
> `user.app_theme.text_logo`, então o estado **era inalcançável**: dava 500 antes de
> renderizar).

#### Scenario: Link vencido
- **GIVEN** um link de recuperação fora do prazo
- **WHEN** o usuário o abre
- **THEN** vê a mensagem de link expirado e o botão para solicitar um novo, com a página renderizando normalmente

### Requirement: FE-011 — Console → Usuários: cabeçalho, contadores e lista

O ai9 SHALL garantir que a tela de usuários mostra o cabeçalho com contadores, o estado de carregamento, o estado
vazio e a ação de cadastrar quando o operador tem permissão. Fonte legada:
`app/views/pub/console/parts/users/_body.html.erb:1-42`.

#### Scenario: Lista vazia após busca
- **GIVEN** um termo de busca sem resultados
- **WHEN** a busca conclui
- **THEN** a tela mostra a mensagem de nenhum resultado, citando o termo buscado

#### Scenario: Operador somente-leitura
- **GIVEN** um operador com `user_is_readonly`
- **WHEN** ele abre a tela
- **THEN** a ação de cadastrar não é exibida

### Requirement: FE-012 — Busca de usuários com debounce

O ai9 SHALL garantir que a busca dispara após uma pausa na digitação e ignora termos compostos apenas de espaços.
Fonte legada: `app/views/pub/console/parts/users/_body.js.erb:22-35`.

#### Scenario: Digitação contínua
- **GIVEN** o operador digitando rapidamente
- **WHEN** ele para de digitar
- **THEN** uma única busca é executada com o termo final

### Requirement: FE-013 — Filtro por tipo de usuário

O ai9 SHALL garantir que a tela oferece filtro por tipo de usuário, com as opções limitadas ao que o operador pode
ver. Fonte legada:
`app/views/pub/console/parts/users/_body.html.erb:33-38`; `.../_body.js.erb:15-19`.

> AMBIGUIDADE: as opções vêm de `role_types_for_filter`, cuja regra depende das `hierarchy`
> reais dos `RoleType` — dump ausente (DEC-04).

#### Scenario: Opções do filtro para um Gerente
- **GIVEN** um operador `Gerente`
- **WHEN** ele abre o filtro de tipo
- **THEN** só aparecem os tipos que ele pode enxergar (`Gerente` e `Colaborador`)

### Requirement: FE-014 — Paginação da lista de usuários

O ai9 SHALL garantir que a lista oferece navegação por páginas (primeira, anterior, próxima, última) e ajuste do
tamanho da página, refletindo o total real de registros. Fonte legada:
`app/views/pub/console/parts/users/_body.js.erb:104-226,289-337`.

> Nota: corrige D-20 (legado: `limit`/`offset` eram descartados no backend — a UI de
> paginação era **decorativa** e a tela sempre trazia tudo). No ai9 a paginação é real
> (Q-04, decidido).

#### Scenario: Navegar para a última página
- **GIVEN** 57 usuários e páginas de 20
- **WHEN** o operador vai para a última página
- **THEN** vê os 17 registros finais e os controles de "próxima"/"última" desabilitados

### Requirement: FE-015 — Widget do usuário na lista

O ai9 SHALL garantir que cada item da lista mostra avatar (ou iniciais), nome, tipo, e-mail, último login (ou "nunca
logou"), identificador e os indicadores de membro padrão e conta bloqueada. Fonte legada:
`app/views/pub/console/parts/users/list/_widget.html.erb:1-44`.

> Nota: corrige os atributos HTML malformados do legado (`class=default_member"`,
> `class=blocked_user"`).

#### Scenario: Usuário que nunca acessou
- **GIVEN** um usuário sem registro de último acesso
- **WHEN** a lista é renderizada
- **THEN** o item mostra "Nunca logou" no lugar da data

#### Scenario: Conta bloqueada
- **GIVEN** um usuário desativado
- **WHEN** a lista é renderizada
- **THEN** o item exibe o indicador de conta bloqueada

### Requirement: FE-016 — Ações do item da lista de usuários

O ai9 SHALL garantir que o menu de ações do item oferece ver detalhe, editar, ver como (impersonation), bloquear e
desbloquear, exibindo **apenas** as ações que o operador tem direito de executar. Fonte
legada: `app/views/pub/console/parts/users/list/_widget.html.erb:44-86`; `.../_widget.js.erb:1-169`.

> Nota: corrige D-34 (legado: a UI escondia as ações mas o backend não checava nada; e o
> item "Ver como" aparecia para **qualquer** papel, contradizendo o menu da toolbar, que
> só liberava Admin/OG). No ai9 a UI reflete exatamente a regra do servidor (BE-031).

#### Scenario: Operador sem direito de impersonar
- **GIVEN** um operador `Colaborador`
- **WHEN** ele abre o menu de ações de outro usuário
- **THEN** a ação "Ver como" **não** é oferecida

#### Scenario: Ação concluída
- **GIVEN** uma ação de bloqueio executada com sucesso
- **WHEN** a resposta chega
- **THEN** apenas o item afetado é atualizado na lista, sem recarregar a página inteira

### Requirement: FE-017 — Copiar o identificador do usuário

O ai9 SHALL garantir que o identificador exibido pode ser copiado para a área de transferência com um clique,
com confirmação visual. Fonte legada:
`app/views/pub/console/parts/users/list/_widget.js.erb:163-167`.

#### Scenario: Cópia do identificador
- **GIVEN** um item de usuário na lista
- **WHEN** o operador clica no identificador
- **THEN** o valor vai para a área de transferência e uma confirmação é exibida

### Requirement: FE-018 — Abertura do editor de usuário (criar/editar)

O ai9 SHALL garantir que a ação de cadastrar e os links diretos abrem o editor com o título correto e mantêm a URL
sincronizada com o estado da tela. Fonte legada:
`app/views/pub/console/parts/users/_body.js.erb:44-53,254-275`; `.../helper/_mount.js.erb:1-128`.

> Nota: corrige a mensagem de erro com erro de digitação do legado ("Esse ussuario não pode
> ser alterada").

#### Scenario: Link direto para edição
- **GIVEN** uma URL apontando diretamente para a edição de um usuário
- **WHEN** a página carrega
- **THEN** o editor abre em modo de edição com o título "Editar usuário"

#### Scenario: Falha ao montar o editor
- **GIVEN** uma falha ao carregar os dados do editor
- **WHEN** a tentativa termina
- **THEN** uma mensagem de falha legível é exibida e a tela permanece utilizável

### Requirement: FE-019 — Formulário de cadastro/edição de usuário no console

O ai9 SHALL garantir que o formulário oferece tipo, membro padrão, nome, username, e-mail e, na criação, definição de
senha; o campo "membro padrão" só aparece para quem pode defini-lo. Fonte legada:
`app/views/pub/console/parts/users/helper/_body.html.erb:1-76`.

> Nota: corrige D-39 (legado: um campo **oculto** `role_type` com default `Admin` coexistia
> com o `select` de tipo no mesmo formulário). No ai9 há um único controle de papel, com as
> opções limitadas ao que o operador pode conceder.

> Nota: corrige D-38 (legado: criar usuário definia a senha e a enviava por e-mail em texto
> puro). No ai9 a criação dispara **link de definição de senha**.

#### Scenario: Opções de papel limitadas
- **GIVEN** um operador `Gerente`
- **WHEN** ele abre o formulário de criação
- **THEN** o seletor de papel só oferece papéis inferiores ao dele

#### Scenario: Edição da própria conta
- **GIVEN** o operador editando o próprio registro
- **WHEN** o formulário é exibido
- **THEN** os campos de definição de senha de terceiros não aparecem (a troca da própria senha é o FE-032)

### Requirement: FE-020 — Validação de senha e confirmação no formulário

O ai9 SHALL garantir que o botão de salvar só é habilitado quando senha e confirmação coincidem; se a senha for
deixada em branco na edição, ela não é enviada. Fonte legada:
`app/views/pub/console/parts/users/helper/_body.js.erb:1-72`.

#### Scenario: Senhas divergentes
- **GIVEN** senha e confirmação diferentes
- **WHEN** o operador tenta salvar
- **THEN** o salvamento é bloqueado com aviso

#### Scenario: Edição sem alterar a senha
- **GIVEN** os campos de senha vazios em uma edição
- **WHEN** o formulário é salvo
- **THEN** os dados são atualizados e a senha permanece inalterada

### Requirement: FE-021 — Upload e pré-visualização do avatar

O ai9 SHALL garantir que o formulário permite escolher uma imagem, mostrar a pré-visualização e informa os limites
antes do envio. Fonte legada:
`app/views/pub/console/parts/users/helper/_body.js.erb:78-103`;
`engines/auth19/app/models/livetat/auth/user.rb:60-61`.

> Nota: corrige D-56 (legado: o front não validava nada e o backend tinha a detecção de
> spoof de mídia desligada). No ai9 tipo e tamanho (limite de 3 MB) são validados no cliente
> **e** no servidor, com verificação real do conteúdo.

#### Scenario: Arquivo acima do limite
- **GIVEN** uma imagem de 8 MB
- **WHEN** o operador a seleciona
- **THEN** a interface informa o limite antes de qualquer envio e o arquivo não é enviado

#### Scenario: Arquivo que não é imagem
- **GIVEN** um arquivo com extensão de imagem mas conteúdo de outro tipo
- **WHEN** o envio é tentado
- **THEN** o servidor recusa com 422

### Requirement: FE-022 — Detalhe do usuário: abas Geral e Projetos

O ai9 SHALL garantir que o detalhe organiza os dados em abas, e a aba de projetos só aparece para quem pode
gerenciá-la. Fonte legada:
`app/views/pub/console/parts/users/detail/_body.html.erb:1-28`.

> Nota: corrige o legado, em que a condição da aba (linha 14) e a do conteúdo (linha 22)
> estavam em lugares diferentes — um `Gerente` podia ver a aba **sem conteúdo**.

#### Scenario: Operador sem direito de gerir projetos do usuário
- **GIVEN** um operador `Gerente`
- **WHEN** ele abre o detalhe de um usuário
- **THEN** a aba de projetos não é exibida

### Requirement: FE-023 — Detalhe do usuário: card "Dados do usuário"

O ai9 SHALL garantir que o card mostra nome, sobrenome, tipo, CPF, e-mail, código, telefone formatado e data de
criação, com "-" nos campos vazios, e a ação de editar sujeita à permissão de **edição**.
Fonte legada:
`app/views/pub/console/parts/users/detail/tabs/_tab_geral.html.erb:11-60`.

> Nota: corrige D-34 (legado: o botão "Editar" era gateado por `may_delete_users?` —
> permissão de **excluir**, não de editar).

#### Scenario: Campos vazios
- **GIVEN** um usuário sem CPF e sem telefone
- **WHEN** o card é exibido
- **THEN** esses campos mostram "-"

#### Scenario: Gate correto do botão editar
- **GIVEN** um operador que pode editar mas não excluir usuários
- **WHEN** ele abre o detalhe
- **THEN** a ação de editar está disponível

### Requirement: FE-024 — Painel de permissões individuais do usuário

O ai9 SHALL garantir que o detalhe do usuário lista suas permissões condicionais com um controle de ligar/desligar
por permissão, escondendo o painel quando o operador não pode alterá-las. Fonte legada:
`app/views/pub/console/parts/users/detail/tabs/_tab_geral.html.erb:63-90`; `.../_tab_geral.js.erb:36-82`.

> Nota: corrige D-34 (legado: os controles eram `disabled readonly` na UI mas o endpoint
> aceitava qualquer chamada — ver BE-018).

> AMBIGUIDADE: as abilities do tipo `limit` (`max_*_amount`) existem no modelo e nos seeds
> mas o bloco de UI está **comentado** (linhas 92-109) e elas não gateiam nada. Sem decisão
> sobre portar o conceito de limites ou removê-lo.

#### Scenario: Alterar uma permissão do usuário
- **GIVEN** um operador com hierarquia superior à do alvo
- **WHEN** ele liga uma permissão no painel
- **THEN** o novo valor é gravado e uma confirmação é exibida

#### Scenario: Alvo de hierarquia igual ou superior
- **GIVEN** um operador `Admin` vendo o detalhe de um `OG`
- **WHEN** a tela é renderizada
- **THEN** o painel de permissões não oferece alteração

### Requirement: FE-025 — Aba Projetos: associar e desassociar projetos

O ai9 SHALL garantir que a aba lista os projetos com um controle por linha que associa ou desassocia o usuário,
atualizando a lista e confirmando a ação. Fonte legada:
`app/views/pub/console/parts/users/detail/projects/list/_widget.html.erb:1-17`; `.../_widget.js.erb:1-68`.

> Nota: corrige D-34 (legado: a remoção enviava o id da membership mas o backend o
> **ignorava**, usando a trinca — ver BE-046) e a mensagem de erro genérica ("No momento,
> não é possível adicionar o usuario"), substituída pelo erro real do servidor.

#### Scenario: Associar projeto
- **GIVEN** um projeto em que o usuário não é membro
- **WHEN** o operador ativa o controle daquela linha
- **THEN** a membership é criada e a confirmação é exibida

#### Scenario: Desassociar projeto
- **GIVEN** um projeto em que o usuário é membro
- **WHEN** o operador desativa o controle
- **THEN** a membership é removida e a lista reflete o novo estado


### Requirement: FE-026 — Console → Permissões: lista de tipos de usuário

O ai9 SHALL garantir que a tela lista um card por tipo de usuário com suas permissões condicionais, com estado de
carregamento e estado vazio. Fonte legada:
`app/views/pub/console/parts/permissions/_body.html.erb:1-8`; `.../permissions/list/_widget.html.erb:1-20`.

> Nota: corrige o legado, em que o JS referenciava `.search_permission` e
> `permission_add_button`/`openEdit` **sem UI correspondente** — busca e criação declaradas
> e inexistentes. No ai9 o catálogo é fechado (BE-043) e a busca só existe se houver campo.

#### Scenario: Listagem dos tipos
- **GIVEN** um operador autorizado
- **WHEN** ele abre a tela de permissões
- **THEN** vê um card por tipo de usuário visível a ele, com as permissões e seus estados

### Requirement: FE-027 — Alternar permissão de um tipo de usuário

O ai9 SHALL garantir que o controle de cada permissão liga ou desliga o valor para o tipo, com confirmação e
atualização da lista. Fonte legada:
`app/views/pub/console/parts/permissions/list/_widget.js.erb:13-58`.

> Nota: corrige D-35 (legado: a mudança **não propagava** para os usuários existentes — a
> tela dizia que a permissão tinha sido desativada e nada mudava para quem já existia).
> No ai9 o efeito é imediato para todos os usuários do tipo (BE-042).

#### Scenario: Desligar uma permissão do tipo
- **GIVEN** um tipo com a permissão ligada e usuários existentes desse tipo
- **WHEN** o operador desliga a permissão
- **THEN** a confirmação é exibida e o efeito vale imediatamente para os usuários existentes

### Requirement: FE-028 — Console → Minha conta: dados do perfil

O ai9 SHALL garantir que a tela de conta mostra e edita avatar, nome, sobrenome, CPF, e-mail (somente leitura),
código (somente leitura) e telefone. Fonte legada:
`app/views/pub/console/parts/my_account/_body.html.erb:1-8`;
`.../my_account/parts/essential/_container.html.erb:1-133`.

> AMBIGUIDADE: existem no diretório os containers `identity`, `phone` e `address` que **não
> são renderizados** pelo `_body`. Sem decisão sobre se foram descontinuados ou se a tela
> deveria expor o perfil estendido completo (BE-016 aceita 41 campos).

#### Scenario: Edição do perfil
- **GIVEN** o usuário autenticado na tela da própria conta
- **WHEN** ele altera o nome e salva
- **THEN** o dado é atualizado e a confirmação é exibida

#### Scenario: Campos não editáveis
- **GIVEN** a tela da própria conta
- **WHEN** ela é exibida
- **THEN** e-mail e código aparecem como somente leitura

### Requirement: FE-029 — Minha conta: validação de CPF em tempo real

O ai9 SHALL garantir que o campo de CPF é validado ao completar os 11 dígitos, mostrando estado válido ou o erro
correspondente, e impede o salvamento enquanto estiver inválido. Fonte legada:
`app/views/pub/console/parts/my_account/parts/essential/_container.js.erb:19-62`.

#### Scenario: CPF inválido bloqueia o salvamento
- **GIVEN** um CPF inválido digitado
- **WHEN** a validação retorna erro
- **THEN** a mensagem é exibida no campo e o salvamento automático do formulário fica suspenso até a correção

### Requirement: FE-030 — Minha conta: máscara e bloqueio do telefone

O ai9 SHALL garantir que o campo de telefone aplica máscara para 8 ou 9 dígitos. Fonte legada:
`app/views/pub/console/parts/my_account/parts/essential/_container.js.erb:4-17`.

> AMBIGUIDADE: quando `info.is_phone_checked == 1` o campo fica **permanentemente somente
> leitura**, mas **não existe fluxo de verificação de telefone** em lugar nenhum do legado
> (nenhuma tela usa `phone_confirmation_code`). Sem decisão: portar o bloqueio sem o fluxo,
> implementar a verificação, ou remover o conceito?

#### Scenario: Máscara aplicada
- **GIVEN** o usuário digitando o telefone
- **WHEN** ele informa 9 dígitos
- **THEN** a máscara se ajusta ao formato de 9 dígitos

### Requirement: FE-031 — Minha conta: copiar o "Código" (identifier)

O ai9 SHALL garantir que o código público do usuário pode ser copiado com um clique. Fonte legada:
`app/views/pub/console/parts/my_account/parts/essential/_container.js.erb:64-72`.

> Nota: corrige o legado, em que o campo era renderizado como `fi.text_field :identifier`
> dentro de `fields_for :info`, mas `UserInfo` **não tem a coluna `identifier`** — o campo
> estava no formulário errado e o valor vinha de um `value:` explícito.

#### Scenario: Cópia do código
- **GIVEN** a tela da própria conta
- **WHEN** o usuário clica no ícone de cópia do código
- **THEN** o `identifier` do usuário vai para a área de transferência

### Requirement: FE-032 — Minha conta: trocar a própria senha

O ai9 SHALL garantir que a seção de troca de senha pede a senha atual e a nova, e o comportamento após a troca
corresponde ao que a tela promete. Fonte legada:
`app/views/pub/console/parts/my_account/_body.html.erb:24-53`; `.../my_account/_body.js.erb:132-146`.

> Nota: corrige o legado, cujo texto avisava que o usuário "será direcionado para a página
> inicial e terá que realizar o login novamente" — **nada no código fazia esse logout**. No
> ai9 a troca de senha encerra as demais sessões e o texto passa a ser verdadeiro.

#### Scenario: Troca de senha na própria conta
- **GIVEN** o usuário com a senha atual correta
- **WHEN** ele confirma a nova senha
- **THEN** a senha é trocada, as outras sessões do usuário são encerradas e a tela informa o que aconteceu

### Requirement: FE-033 — Minha conta: remover a própria conta

O ai9 SHALL garantir que a remoção da própria conta exige confirmação explícita e a senha. Fonte legada:
`app/views/pub/console/parts/my_account/_body.html.erb:12-22`; `.../my_account/_body.js.erb:74-130`.

> Nota: corrige D-34 (legado: o botão só aparecia se `current_user.may_create_users?` —
> permissão de **criar**, não de remover — e não havia confirmação explícita, só um duplo
> clique).

#### Scenario: Remoção confirmada
- **GIVEN** o usuário na tela da própria conta
- **WHEN** ele pede a remoção, confirma explicitamente e informa a senha correta
- **THEN** a conta é removida (BE-014) e ele é levado à página inicial pública

#### Scenario: Confirmação cancelada
- **GIVEN** o diálogo de confirmação aberto
- **WHEN** o usuário cancela
- **THEN** nada é removido

### Requirement: FE-034 — Minha conta: aceite de Termos de Uso e Política de Privacidade

O ai9 SHALL garantir que quando os contratos ainda não foram aceitos, a tela exige o aceite explícito antes de
prosseguir. Fonte legada:
`app/views/pub/console/parts/my_account/parts/essential/_container.html.erb:106-130`; `.../my_account/_body.js.erb:22-28`.

> Nota: corrige o legado: o checkbox vinha **marcado por default** e a checagem
> `if (jbb.val()==false)` comparava string com boolean, então o aviso "Você precisa aceitar
> o contrato para continuar" **nunca aparecia** — a trava estava quebrada.

#### Scenario: Contratos ainda não aceitos
- **GIVEN** um usuário sem aceite registrado
- **WHEN** ele abre a tela da conta
- **THEN** o aceite aparece **desmarcado** e é obrigatório para salvar

### Requirement: FE-035 — Minha conta: salvamento automático das alterações

O ai9 SHALL garantir que as alterações do formulário de conta são enfileiradas e salvas, com confirmação e
atualização do avatar exibido na barra. Fonte legada:
`app/views/pub/console/parts/my_account/_body.js.erb:9-72`.

> Nota: corrige o erro genérico do legado ("ERRO, houve uma falha no sistema"), substituído
> pela mensagem estruturada do servidor.

#### Scenario: Alteração salva
- **GIVEN** o usuário editando um campo do perfil
- **WHEN** o salvamento conclui
- **THEN** a confirmação é exibida e o avatar/identidade na barra reflete o novo valor

#### Scenario: Falha ao salvar
- **GIVEN** um campo com valor inválido
- **WHEN** o salvamento falha
- **THEN** o erro específico do campo é exibido

### Requirement: FE-036 — Menu do usuário na barra

O ai9 SHALL garantir que o menu oferece página inicial, minha conta, trocar de usuário, voltar ao usuário real e
sair, exibindo cada item conforme a permissão real do operador. Fonte legada:
`app/views/pub/base/nav/user/_menu.html.erb:1-45`; `.../user/_menu.js.erb:1-39`.

> Nota: corrige D-34 (legado: o gate de "Trocar de usuário" existia apenas aqui, na view).

#### Scenario: Operador sem direito de impersonar
- **GIVEN** um operador `Colaborador`
- **WHEN** ele abre o menu
- **THEN** "Trocar de usuário" não aparece

#### Scenario: Em impersonation
- **GIVEN** uma sessão em impersonation
- **WHEN** o menu é aberto
- **THEN** aparece a opção de voltar ao usuário real

### Requirement: FE-037 — Chip do usuário e indicador "Vendo como"

O ai9 SHALL garantir que a barra exibe a identidade corrente e, durante a impersonation, deixa explícito o usuário
real e o usuário sendo representado. Fonte legada:
`app/views/pub/base/nav/user/_widget.html.erb:1-14`.

#### Scenario: Impersonation ativa
- **GIVEN** um operador impersonando outro usuário
- **WHEN** qualquer tela do console é exibida
- **THEN** a barra mostra o nome real e a indicação "Vendo como <nome do alvo>"

### Requirement: FE-038 — Busca de impersonation na barra

O ai9 SHALL garantir que a barra oferece um campo de busca que sugere usuários e, ao escolher um, assume a identidade
dele. Fonte legada:
`app/views/pub/base/nav/_bar.js.erb:51-120`; `app/views/pub/console/parts/users/impersonate_search/list/_widget.{html,js}.erb`.

> Nota: corrige D-34 — a busca só é oferecida a quem realmente pode impersonar (BE-031/BE-033).

#### Scenario: Escolha de um usuário
- **GIVEN** um operador autorizado com resultados na busca
- **WHEN** ele escolhe um usuário
- **THEN** a sessão passa a operar como o alvo e a interface reflete o novo contexto

#### Scenario: Busca sem resultados
- **GIVEN** um termo sem correspondência
- **WHEN** a busca conclui
- **THEN** a mensagem de "sem resultados" é exibida

### Requirement: FE-039 — Sair (logout) pela interface

O ai9 SHALL garantir que a ação de sair encerra a sessão e leva o usuário à página pública, informando quando falha.
Fonte legada:
`app/views/pub/base/nav/sign_out/_sign_out.js.erb:1-14`.

> Nota: corrige o legado, em que o erro do logout era **silenciosamente ignorado** — o
> usuário continuava logado sem qualquer aviso.

#### Scenario: Logout com falha de rede
- **GIVEN** uma falha ao chamar o encerramento de sessão
- **WHEN** a resposta de erro chega
- **THEN** a interface informa que não foi possível sair e oferece nova tentativa

### Requirement: FE-040 — Projeto: adicionar membro por autocomplete

O ai9 SHALL garantir que a tela de projeto permite buscar e adicionar um usuário como membro, com confirmação. Fonte
legada: `app/views/pub/console/parts/projects/detail/memberships/new/list/_widget.{html,js}.erb`.

> Nota: corrige o legado, em que usuários **já membros apareciam** na busca (ver BE-044).

#### Scenario: Adicionar membro
- **GIVEN** um projeto e um usuário ainda não membro
- **WHEN** o operador o escolhe na busca
- **THEN** o vínculo é criado e a confirmação nomeia o membro adicionado

### Requirement: FE-041 — Projeto: lista de membros e remoção

O ai9 SHALL garantir que a lista de membros mostra cada usuário com o **papel dele dentro do projeto** e oferece a
remoção apenas quando permitida. Fonte legada:
`app/views/pub/console/parts/projects/detail/memberships/list/_widget.html.erb:1-30`.

> Nota: corrige o legado, que exibia o **`role_type` global** do usuário no lugar do `role`
> da membership (origem da inconsistência descrita em DB-018).

#### Scenario: Papel exibido
- **GIVEN** um usuário `Admin` global que é `Participante` no projeto
- **WHEN** a lista de membros é exibida
- **THEN** o papel mostrado é `Participante`

#### Scenario: Remoção bloqueada
- **GIVEN** o membro que é o responsável do projeto, ou o próprio operador
- **WHEN** a lista é exibida
- **THEN** a ação de remover não é oferecida para esses itens

### Requirement: FE-042 — Feedback de erros nas operações de usuário

O ai9 SHALL garantir que os erros de criação e atualização de usuário e de perfil são exibidos por campo, com
rótulos em pt-BR. Fonte legada:
`app/views/pub/console/parts/users/helper/handle.js.erb:1-7`; `app/views/pub/users/new/{handle,info_handle}.js.erb`.

#### Scenario: Múltiplos erros de validação
- **GIVEN** um envio com e-mail duplicado e CPF inválido
- **WHEN** a resposta 422 chega
- **THEN** cada erro é exibido separadamente, em pt-BR, junto ao campo correspondente

### Requirement: FE-043 — Feedback de erros nas operações de permissão

O ai9 SHALL garantir que os erros ao alterar permissões são exibidos ao operador. Fonte legada:
`app/views/pub/console/parts/permissions/list/handle.js.erb:1-8`.

> Nota: corrige o legado, cujo branch de sucesso era **vazio** nesta tela.

#### Scenario: Falha ao alterar permissão
- **GIVEN** uma alteração recusada pelo servidor
- **WHEN** a resposta chega
- **THEN** o motivo é exibido e o controle volta ao estado anterior

### Requirement: FE-044 — Bloqueio da interface quando a conta é desativada

O ai9 SHALL garantir que quando a conta do usuário é desativada durante a sessão, a interface o leva ao login com a
explicação. Fonte legada:
`app/views/pub/console/parts/users/helper/lock.js.erb:1-3`; `app/controllers/pub_application_controller.rb:45-54`.

> Nota: corrige o legado, que apenas recarregava a página **sem qualquer mensagem** — o
> usuário bloqueado não recebia explicação.

#### Scenario: Conta desativada durante o uso
- **GIVEN** um usuário com a tela aberta e a conta desativada por um administrador
- **WHEN** a próxima interação acontece
- **THEN** ele é levado ao login com a mensagem de conta bloqueada

### Requirement: FE-045 — Barra das telas de autenticação

O ai9 SHALL garantir que as telas de autenticação exibem a barra com o logo do tema aplicável. Fonte legada:
`app/views/pub/users/sessions/_toolbar_body.html.erb`; `.../_toolbar_reset_body.html.erb:1-19`.

> Nota: corrige D-123 (legado: a barra da tela de reset lia `user.app_theme.text_logo` sem
> guarda, contribuindo para o 500 do link expirado).

#### Scenario: Tela de reset sem usuário identificado
- **GIVEN** um link de recuperação inválido
- **WHEN** a tela é renderizada
- **THEN** a barra usa o logo do tema padrão e a página carrega normalmente

### Requirement: FE-046 — Tela "cadastro concluído" da engine

O ai9 SHALL garantir que a tela de conclusão de cadastro renderizada apenas no formato HTML da engine **não é
portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/done.html.erb`.

> AMBIGUIDADE: o inventário marca `Ambiguidade? = sim` — como o fluxo do produto sempre usa
> JSON/JS, a tela provavelmente nunca aparece, mas isso não foi confirmado em produção.

#### Scenario: Conclusão do cadastro no ai9
- **GIVEN** um cadastro concluído com sucesso
- **WHEN** a resposta chega ao cliente
- **THEN** a própria interface do produto mostra a conclusão, sem redirecionar para uma tela da plataforma

### Requirement: FE-047 — Telas de usuário da engine (new/index/show/edit)

O ai9 SHALL garantir que o conjunto de telas Materialize da engine, paralelo às telas do console, **não é portado**.
Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/{new,index,show,edit}.html.erb`.

> AMBIGUIDADE: são o "contrato da engine", provavelmente inativas no Safegold, mas não
> confirmadas em produção. Ver spec `engines` (FE-509, FE-511, FE-512, FE-513).

#### Scenario: Telas de usuário no ai9
- **GIVEN** o ai9 em produção
- **WHEN** um operador gerencia usuários
- **THEN** existe **um único** conjunto de telas de usuário, o do console (FE-011 a FE-025)

### Requirement: FE-048 — Telas Devise cruas da engine auth19

O ai9 SHALL garantir que as views padrão do Devise em inglês **não são portadas**. Fonte legada:
`engines/auth19/app/views/livetat/auth/users/**`.

> Nota: as rotas de confirmação e desbloqueio nem existem no legado
> (`devise_for ... only: [:sessions]`), então a maior parte dessas telas é inalcançável.

#### Scenario: Fluxos de confirmação e desbloqueio
- **GIVEN** o ai9 em produção
- **WHEN** um usuário tenta acessar confirmação de e-mail ou desbloqueio de conta
- **THEN** essas rotas não existem, coerentemente com o legado (ver DB-001)

### Requirement: FE-049 — Overrides de UI injetados pela engine no app hospedeiro

O ai9 SHALL garantir que os overrides que injetavam o chip do usuário e o item "sair" via `deface` **não são
portados**. Fonte legada:
`engines/auth_ux19/app/overrides/*.rb`; `engines/auth_ux19/app/views/livetat/auth_ux19/overrides/**`.

> Nota: no legado esses overrides apontam para o layout
> `layouts/livetat/materialize_wrapper19/**`, engine que **não existe** no repositório —
> nenhum deles tem efeito (ver spec `engines`, FE-519). No ai9 o chip e o "sair" são
> componentes explícitos da interface (FE-036, FE-037).

#### Scenario: Composição da barra no ai9
- **GIVEN** qualquer tela autenticada
- **WHEN** a barra é renderizada
- **THEN** o chip do usuário e a ação de sair vêm de componentes declarados na própria aplicação, sem injeção implícita


### Requirement: DB-001 — Tabela de usuários (`livetat_auth_users`)

O ai9 SHALL garantir que o sistema persiste o usuário com identidade (`formal`, `username`, `email`), credencial
(`encrypted_password`), tokens e colunas de rastreio de acesso, com unicidade de `email` e
dos tokens. Fonte legada:
`engines/auth19/db/migrate/20160409121830_create_users.rb`;
`engines/auth19/app/models/livetat/auth/user.rb`.

> Nota: as colunas `failed_attempts`, `locked_at`, `unlock_token`, `confirmation_token`,
> `confirmed_at` e `unconfirmed_email` existem mas os módulos correspondentes **nunca foram
> habilitados** — nunca houve bloqueio por tentativas nem confirmação de e-mail. São dados
> mortos: não portar as colunas sem portar a capacidade.

> Nota: corrige D-109 (legado: usuários importados do Django receberam senha determinística).
> Os hashes bcrypt existentes migram, **mas** todo usuário com `legacy_password` preenchido
> ou sem troca de senha registrada entra com **reset obrigatório** (ver DB-017).

#### Scenario: Unicidade de e-mail
- **GIVEN** um e-mail já cadastrado
- **WHEN** outro usuário tenta usar o mesmo e-mail
- **THEN** a gravação é recusada com erro de unicidade

#### Scenario: Migração de credencial
- **GIVEN** um usuário legado com hash bcrypt válido
- **WHEN** o ETL o importa
- **THEN** ele consegue autenticar com a senha atual, exceto quando marcado para reset obrigatório

### Requirement: DB-002 — Colunas do usuário acrescentadas pela aplicação

O ai9 SHALL garantir que o usuário carrega ainda `kind`, `manager_id`, `identifier`, `color`, `app_theme_id`,
`default_project_id`, `is_default_member` e o estado de conta bloqueada. Fonte legada:
`db/migrate/20171120004723`, `20190121164730`, `20190207025722`, `20190419000711`,
`20200206191948`, `20210303182740`, `20210402134709`, `20210402135252`, `20220523124957`, `20220525124802`.

> AMBIGUIDADE: **`is_active` e `deactivated` coexistem** e significam coisas parecidas —
> `is_active` veio da migração do Django e `deactivated` é o bloqueio pela UI; só
> `deactivated` participa do login. Sem decisão do usuário sobre unificar em um único estado
> de conta.

> Nota: corrige D-109 (legado: `legacy_password` guarda o **hash Django em texto** — dado
> sensível). A coluna **não é portada**; o que se preserva é a marca de "precisa trocar a
> senha".

> Nota: corrige D-28 (legado: `default_project_id` era efetivamente controlado pelo cookie
> `cached_info`). No ai9 ele é a preferência persistida do usuário, mas o projeto **em uso**
> vem do JWT validado contra membership.

#### Scenario: Projeto default sem membership
- **GIVEN** um usuário cujo `default_project_id` aponta para um projeto em que ele não é membro
- **WHEN** ele autentica
- **THEN** o projeto corrente cai para um projeto válido dele (ou nenhum), nunca para o projeto sem membership

### Requirement: DB-003 — Avatar do usuário

O ai9 SHALL garantir que o sistema guarda a referência do arquivo de avatar e seus metadados. Fonte legada:
`engines/auth19/db/migrate/20160409121831_add_attachment_avatar_to_users.rb`.

> Nota: corrige D-56 (legado: arquivos em `public/system/avatars/:id/...`, servidos
> publicamente, com o valor sentinela `"missing.jpg"` marcando "sem avatar"). No ai9 o
> binário vai para object storage e "sem avatar" é ausência de referência, não uma string
> mágica.

#### Scenario: Migração de avatares
- **GIVEN** um usuário legado com avatar real
- **WHEN** o ETL migra o registro
- **THEN** o arquivo é transferido para o storage e a referência aponta para ele

#### Scenario: Sentinela do legado
- **GIVEN** um usuário legado com `avatar_file_name = "missing.jpg"`
- **WHEN** o ETL migra o registro
- **THEN** o usuário fica **sem avatar**, e a interface mostra as iniciais

### Requirement: DB-004 — Perfil estendido (`livetat_auth_user_infos`)

O ai9 SHALL garantir que o perfil estendido guarda nome, gênero, aniversário, e-mails, dois telefones, CPF, CNPJ,
documento fiscal, contato de emergência, endereço de entrega, biografia, graduação, trabalho
e idioma, 1:1 com o usuário. Fonte legada:
`engines/auth19/db/migrate/20171020133117_create_livetat_user_infos.rb` e as 5 migrations de evolução.

> Nota: corrige o legado — **sem índice** em `user_id` apesar da unicidade; `gender` é
> `integer` no banco enquanto o modelo usa strings; `tax_document_issue_date` é **string**
> e não data; booleanos modelados como `integer` 0/1. No ai9 os tipos são corrigidos e a
> unicidade é garantida por índice.

#### Scenario: Um perfil por usuário
- **GIVEN** um usuário que já tem perfil
- **WHEN** um segundo perfil é criado para ele
- **THEN** a gravação é recusada pelo banco

### Requirement: DB-005 — Vínculo usuário ↔ tipo de usuário (`livetat_auth_roles`)

O ai9 SHALL garantir que o sistema registra o tipo (papel) de cada usuário. Fonte legada:
`engines/auth19/db/migrate/20160409121832_create_livetat_roles.rb`;
`engines/auth19/app/models/livetat/auth/role.rb`.

> Nota: corrige D-35 (legado: essa tabela carregava a **cópia congelada** das abilities do
> tipo no momento da atribuição). No ai9 o papel do usuário é o vínculo, e as permissões
> efetivas são resolvidas por consulta — os registros individuais existem apenas como
> **overrides explícitos**.

#### Scenario: Troca de papel
- **GIVEN** um usuário que muda de `Colaborador` para `Gerente`
- **WHEN** a mudança é salva
- **THEN** as permissões efetivas passam a ser as do novo papel na requisição seguinte

### Requirement: DB-006 — Tipos de usuário (`livetat_auth_role_types`)

O ai9 SHALL garantir que os tipos de usuário têm `name` único e `hierarchy` inteira; a `hierarchy` é o eixo de toda a
autorização do produto. Fonte legada:
`engines/auth19/db/migrate/20160409121833` e `20160409121836`;
`engines/auth19/app/models/livetat/auth/role_type.rb`; `db/seeds.rb:40-84`.

> AMBIGUIDADE — **lacuna de dados registrada explicitamente**: o **dump de
> `livetat_auth_role_types` não existe** (DEC-04 dispensou o `pg_dump`). Os nomes e
> hierarquias usados nesta spec — `OG` = 1111, `Admin` = 998, `Gerente` = 888,
> `Colaborador` = 799 — são **inferidos do seed do app**, e o inventário registra que a
> hierarquia de `Gerente` não aparece explicitamente no trecho lido. Todas as regras que
> dependem de comparação de hierarquia (BE-002, BE-025, BE-031, BE-041, FE-013, FE-024)
> herdam essa incerteza. No ai9 os tipos viram **seed versionado** e a etapa de introspecção
> do ETL aborta se o banco real divergir.

> Nota: corrige D-36 (legado: os tipos genéricos da engine — `Admin`, `Manager`, `Visitor` —
> são **destruídos** pelo seed do app, deixando as configurações `default_role_type` e
> `minimal_type_to_sign_up_through_web` apontando para tipos inexistentes).

#### Scenario: Seed versionado
- **GIVEN** um ambiente ai9 recém-provisionado
- **WHEN** o seed roda
- **THEN** os tipos de usuário existem com nomes e hierarquias determinísticos, sem depender de linhas soltas do banco legado

#### Scenario: Divergência com o banco legado
- **GIVEN** o banco real com um tipo de usuário fora da lista esperada
- **WHEN** o ETL roda o dry-run
- **THEN** a execução aborta com relatório do que divergiu, antes de qualquer escrita

### Requirement: DB-007 — Permissões (`livetat_auth_abilities`)

O ai9 SHALL garantir que cada permissão tem `name`, `description`, `type` (`conditional` ou `limit`) e `value`, e é
associada a um tipo de usuário ou a um usuário. Fonte legada:
`engines/auth19/db/migrate/20160409121834` e `20160824171513`.

> Nota: corrige D-35 (legado: a tabela materializava ~17 linhas **por usuário**, o que faz o
> volume crescer com a base e impede que uma mudança no tipo se propague). No ai9 o catálogo
> é código versionado (DB-008) e a tabela guarda somente o que é **override**.

> Nota: o legado precisa de `self.inheritance_column = nil` porque a coluna se chama `type`
> sem ser STI — no ai9 a coluna tem outro nome.

#### Scenario: Consulta de permissão efetiva
- **GIVEN** um usuário sem overrides
- **WHEN** uma permissão é avaliada
- **THEN** o valor vem do tipo de usuário, sem exigir linha própria do usuário

### Requirement: DB-008 — Catálogo de permissões (dados de referência)

O ai9 SHALL garantir que o catálogo tem 17 entradas: 12 condicionais
(`may_{create,modify,read,delete}_{private,public}_entries`,
`may_{create,read,invite,delete}_users`), 4 limites
(`max_private_entries_amount`, `max_public_entries_amount`, `max_invitations_amount`,
`max_users_amount`) e a condicional `user_is_readonly` acrescentada pela aplicação. Fonte
legada: `engines/auth19/lib/livetat/auth/ability_factory.rb:26-47`;
`app/decorators/models/ability_factory_decorator.rb:30`.

> Nota: corrige D-17 (legado: `user_is_readonly` **não é checado em nenhum controller** — o
> usuário somente-leitura conseguia escrever). No ai9 essa permissão bloqueia escrita no
> servidor.

> AMBIGUIDADE: apenas `may_create_users`, `may_delete_users` e `user_is_readonly` são
> consultados nas views do Safegold; as outras 14 existem e **não gateiam nada** observável,
> e as do tipo `limit` não têm interface. Sem decisão sobre portar o conceito completo ou
> reduzir o catálogo ao que é usado.

#### Scenario: Usuário somente-leitura tenta escrever
- **GIVEN** um usuário com `user_is_readonly` ligado
- **WHEN** ele envia qualquer requisição de escrita
- **THEN** a resposta é 403

### Requirement: DB-009 — Aplicações cliente (`livetat_auth_client_applications`)

O ai9 SHALL garantir que o sistema registra aplicações cliente com nome, agente e token de autenticação. Fonte
legada: `engines/auth19/db/migrate/20160409121835` e `db/migrate/20200211205426`;
`app/decorators/models/livetat_auth_client_application_decorator.rb`.

> Nota: corrige o legado, em que o decorator **removia** as validações de unicidade de
> `name` e `agent` manipulando os `_validators` internos do ActiveRecord — dois apps podiam
> ter o mesmo `agent` e `find_through_token` pegava o primeiro.

> AMBIGUIDADE: **não existe CRUD de aplicações cliente na aplicação**. Não se sabe como os
> registros são criados hoje (console? seed? insert manual?) nem quais integrações usam
> `X-LAA-Agent`/`X-LAA-Token` (ver BE-047).

#### Scenario: Agente duplicado
- **GIVEN** uma aplicação cliente já registrada com um agente
- **WHEN** outra tenta registrar o mesmo agente
- **THEN** a gravação é recusada

### Requirement: DB-010 — Vínculos de provedor social (`livetat_auth_omni_providers`)

O ai9 SHALL garantir que o sistema guarda o vínculo entre usuário e provedor social (`name`, `uid`). Fonte legada:
`engines/auth_omni19/db/migrate/20170722163911` e `20170722164423`.

> Nota: corrige o índice único do legado, que inclui `user_id` — o **mesmo `uid`** do
> provedor podia ser vinculado a usuários diferentes.

> AMBIGUIDADE: a tabela provavelmente está vazia (o login social nunca funcionou); a decisão
> de descartar depende do D-41, ainda aberto. Contar as linhas antes de migrar.

#### Scenario: Mesmo uid em dois usuários
- **GIVEN** um `uid` de provedor já vinculado a um usuário
- **WHEN** ele é vinculado a outro
- **THEN** a gravação é recusada

### Requirement: DB-011 — Memberships (`memberships`)

O ai9 SHALL garantir que o sistema registra o vínculo de um usuário a uma entidade (na prática, projeto), com um
papel e unicidade por usuário e entidade. Fonte legada:
`db/migrate/20210301171119_create_memberships.rb` e `20210403175036`; `app/models/membership.rb`.

> Nota: corrige D-28 — a membership passa a ser a **fonte de verdade do escopo de tenant**:
> o projeto do JWT é validado contra ela a cada request (DEC-07: escopo por projeto para
> empresas, fornecedores, disponibilidades, recebíveis, renegociações, operações de risco e
> estruturadas; catálogos globais para portadores, grupos, segmentos e subsegmentos).

> Nota: corrige o legado, que não tinha **nenhum índice** apesar da validação de unicidade
> composta, numa tabela de volume grande (usuários × projetos).

> AMBIGUIDADE: `is_active` **nunca é setado** e os papéis `Responsável`, `Coordenador` e
> `Gestor` não têm interface (ver BE-045).

#### Scenario: Escopo por membership
- **GIVEN** um usuário membro do projeto A e não do projeto B
- **WHEN** ele consulta dados escopados por projeto
- **THEN** só vê os do projeto A, independentemente do que enviar na requisição

### Requirement: DB-012 — Colunas de rastreio de acesso

O ai9 SHALL garantir que o sistema registra contagem de acessos, datas e IPs do último e do acesso corrente. Fonte
legada: `engines/auth19/db/migrate/20160409121830_create_users.rb:16-25`.

> AMBIGUIDADE: `last_sign_in_at` é exibido na lista de usuários, mas os **IPs não são
> exibidos em lugar nenhum**. Sem decisão sobre retenção de IP no ai9 (questão de LGPD).

#### Scenario: Registro do último acesso
- **GIVEN** um usuário que autentica
- **WHEN** o login conclui
- **THEN** a data do acesso é registrada e passa a ser exibida na lista de usuários

### Requirement: DB-013 — Regras de senha e tokens

O ai9 SHALL garantir que o sistema define comprimento mínimo de senha, chaves de autenticação, normalização de e-mail
e o prazo do token de recuperação. Fonte legada:
`engines/auth19/config/initializers/devise.rb:14-29`;
`engines/auth19/app/models/livetat/auth/user.rb:84-103,119-162`.

> Nota: corrige D-37 (legado: `reset_password_within = 6.hours` configurado e **não aplicado**
> no fluxo custom). No ai9 existe **um único prazo**, aplicado de fato, e o token é de uso
> único.

> Nota: corrige o legado, em que a `secret_key` era gerada com `SecureRandom.hex(64)` **a
> cada boot** — todo deploy invalidava os tokens assinados. No ai9 o segredo vem de
> configuração persistente.

#### Scenario: Senha abaixo do mínimo
- **GIVEN** uma senha com menos caracteres que o mínimo definido
- **WHEN** o usuário tenta salvá-la
- **THEN** a resposta é 422 com a mensagem de comprimento mínimo

#### Scenario: Reinício da aplicação
- **GIVEN** uma sessão válida emitida antes de um deploy
- **WHEN** a aplicação é reiniciada
- **THEN** a sessão continua válida até a sua expiração normal

### Requirement: DB-014 — Validações de identidade do usuário

O ai9 SHALL garantir que `formal` é obrigatório (3 a 60 caracteres); `username` é opcional, único, alfanumérico,
começa com letra e não pode ser um nome reservado. Fonte legada:
`engines/auth19/app/models/livetat/auth/user.rb:55-68`;
`app/decorators/models/user_decorator.rb:48-52`; `app/validators/username_convention_validator.rb`.

> Nota: corrige o legado, em que **duas validações contraditórias** de `username` rodavam
> juntas: a da engine (3..20, permite `_`) e a do decorator do app (2..45, regex sem `_`).
> No ai9 vale **uma** regra.

> Nota: a lista de usernames reservados (`panel start api users mailer console feedbacks u h
> contract geo ads progress-job observers notes search sign_in sign_out`) é comportamento a
> preservar, porque protege as rotas.

> Nota: `FormalnameConventionValidator` existe no legado e **não é aplicado a nenhum campo**
> — código morto, não portar.

#### Scenario: Username reservado
- **GIVEN** um cadastro com `username` igual a uma palavra reservada de rota
- **WHEN** o envio é feito
- **THEN** a resposta é 422 informando que o username não está disponível

#### Scenario: Username com underscore
- **GIVEN** um `username` contendo `_`
- **WHEN** o cadastro é enviado
- **THEN** o resultado é determinístico conforme a regra única definida, sem depender de qual validação roda primeiro

### Requirement: DB-015 — Nível de confiabilidade do perfil

O ai9 SHALL garantir que o sistema calcula o nível de confiabilidade do perfil em quatro faixas (Baixa, Média, Alta,
Máxima) a partir do preenchimento e validade dos dados. Fonte legada:
`engines/auth19/app/models/livetat/auth/user_info.rb:6-13,49-74,159-171`.

> Nota: comportamento a preservar — `is_emergency_contact_active` e
> `is_delivery_location_active` são **recalculados a cada gravação** e o valor enviado pelo
> cliente é sempre ignorado.

#### Scenario: Subida para "Média"
- **GIVEN** um perfil com nome, sobrenome, aniversário e CPF válido
- **WHEN** o perfil é salvo
- **THEN** o nível passa a "Média"

#### Scenario: Subida para "Máxima"
- **GIVEN** um perfil de nível "Alta" cujo telefone é marcado como verificado
- **WHEN** o perfil é salvo
- **THEN** o nível passa a "Máxima"

### Requirement: DB-016 — Validações de CPF, CNPJ, telefone e e-mail do perfil

O ai9 SHALL garantir que o sistema valida CPF e CNPJ por dígito verificador, telefones por formato e e-mails por
formato; UF do endereço tem 2 caracteres e país tem o código de 3 letras. Fonte legada:
`engines/auth19/app/models/livetat/auth/user_info.rb:18-31,76-135,173-187`.

> AMBIGUIDADE: **não há validação de unicidade de CPF no modelo** — a checagem existe apenas
> no endpoint de verificação em tempo real (BE-035), então dois perfis podem terminar com o
> mesmo CPF. Sem decisão do usuário sobre tornar o CPF único no ai9.

#### Scenario: CNPJ inválido
- **GIVEN** um CNPJ que não passa no dígito verificador
- **WHEN** o perfil é salvo
- **THEN** a resposta é 422 com "não é um CNPJ válido"

### Requirement: DB-017 — Origem legada (Django): usuários

O ai9 SHALL garantir que o ETL importa os usuários da base Django preservando a proveniência
(`legacy_id`), mapeando `first_name + last_name` para `formal` (com fallback do prefixo do
e-mail) e o papel a partir das flags de origem. Fonte legada:
`app/models/legacy/u.rb:1-44`; `app/models/legacy.rb:2-48`.

> Nota: corrige D-109 (legado: a importação gerava a senha determinística
> `"<primeiro nome sem acento>#6230"`, adivinhável a partir do nome, e guardava o hash Django
> em `legacy_password`). No ai9 **nenhum** usuário importado herda senha utilizável: todos
> entram com **reset obrigatório** e recebem link de definição de senha; a coluna
> `legacy_password` não é portada.

> Nota (DEC-12): o pipeline `Legacy::execute` é assumido como **não executado** hoje — o
> código de ETL Django não é portado, mas as colunas `legacy_*` de proveniência são
> preservadas.

#### Scenario: Usuário importado tenta autenticar com a senha determinística
- **GIVEN** um usuário migrado do Django que nunca trocou a senha
- **WHEN** alguém tenta autenticar com `<primeiro nome>#6230`
- **THEN** a autenticação falha e o usuário só entra após definir uma senha nova pelo link

#### Scenario: Proveniência preservada
- **GIVEN** um registro importado
- **WHEN** ele é consultado no ai9
- **THEN** o identificador de origem continua disponível para rastrear os borderôs de 2016-2021

### Requirement: DB-018 — Origem legada (Django): memberships

O ai9 SHALL garantir que o ETL importa os vínculos de usuário com projeto preservando `legacy_id`,
`legacy_project_id` e `legacy_user_id`. Fonte legada:
`app/models/legacy/membership.rb:1-30`;
`app/models/legacy/{default_project_interceptor,project_responsible_interceptor,membership_interceptor}.rb`.

> AMBIGUIDADE: na importação o `role` da membership recebeu o papel **global** do usuário
> (`Gerente`/`Admin`/`Colaborador`) em vez de um papel de projeto — é a origem da
> inconsistência do FE-041. Sem decisão sobre normalizar esses valores durante a migração ou
> preservá-los como estão.

#### Scenario: Papel de projeto herdado do papel global
- **GIVEN** memberships importadas com `role` igual a um papel global
- **WHEN** o ETL roda o dry-run
- **THEN** esses casos são listados no relatório para decisão, e não convertidos silenciosamente


### Requirement: OPS-001 — E-mail ao usuário recém-criado

O ai9 SHALL garantir que quando um operador cria um usuário, o sistema envia um e-mail de boas-vindas com um **link
de definição de senha** de uso único e prazo, identificando quem o cadastrou e o papel
concedido. Fonte legada:
`app/decorators/controllers/registrations_decorator.rb:24-39`; `lib/notification_facade.rb:2-4`;
`app/views/livetat/mailer19/mailing/send_welcome_email_to_new_generic_user.html.erb`.

> Nota: corrige D-38 (legado: o e-mail continha o **e-mail e a senha em texto puro**, em
> cards no corpo da mensagem — a senha trafegava e ficava arquivada na caixa do usuário).
> No ai9 **nenhuma senha é enviada por e-mail**.

> Nota: corrige D-37 (legado: o link usava o mesmo mecanismo de token que nunca expira).
> O link de definição de senha é de uso único e expira.

#### Scenario: Usuário criado por um operador
- **GIVEN** um operador que cadastra um novo usuário
- **WHEN** a criação conclui
- **THEN** o novo usuário recebe um e-mail com link para **definir** a senha, e o corpo da mensagem não contém nenhuma credencial

#### Scenario: Link de definição usado
- **GIVEN** o link recebido
- **WHEN** o usuário define a senha
- **THEN** o link deixa de funcionar para qualquer nova tentativa

### Requirement: OPS-002 — E-mail de instruções de recuperação de senha

O ai9 SHALL garantir que o sistema envia, de forma assíncrona, o e-mail com o link de recuperação, com a identidade
visual do tema do usuário. Fonte legada:
`app/decorators/facades/auth_ux19_notification_decorator.rb:7-9`;
`app/decorators/models/mailer_decorator.rb:17-28`;
`app/views/livetat/mailer19/mailing/send_email_to_recovery_password_user.html.erb`.

> Nota: corrige D-37 (legado: três prazos divergentes — o texto do e-mail dizia 24 horas, o
> Devise estava em 6 horas e o código não expirava nunca). No ai9 o texto do e-mail informa
> **o mesmo** prazo que o sistema aplica.

#### Scenario: E-mail enfileirado
- **GIVEN** uma solicitação de recuperação para e-mail existente
- **WHEN** ela é processada
- **THEN** o e-mail é enfileirado com o link e com o prazo real de validade no texto

#### Scenario: Falha de envio
- **GIVEN** o servidor de e-mail indisponível
- **WHEN** o envio falha
- **THEN** a falha é registrada e visível para operação (nunca engolida)

### Requirement: OPS-003 — E-mail de confirmação de senha alterada

O ai9 SHALL garantir que após a troca de senha, o sistema notifica o usuário por e-mail. Fonte legada:
`app/decorators/facades/auth_ux19_notification_decorator.rb:11-13`;
`app/decorators/models/mailer_decorator.rb:32-43`.

#### Scenario: Senha trocada
- **GIVEN** uma troca de senha concluída (BE-022)
- **WHEN** a operação conclui
- **THEN** o usuário recebe a confirmação por e-mail, com o caminho para o login

### Requirement: OPS-004 — Notificações de senha originais da engine (descontinuadas)

O ai9 SHALL garantir que os textos genéricos de recuperação e confirmação fornecidos pela engine **não são portados**
— valem os e-mails temáticos do produto (OPS-002 e OPS-003). Fonte legada:
`engines/auth_ux19/lib/livetat/auth_ux19/notification.rb:4-32`.

> Nota: corrige D-37 (o texto original prometia expiração em "24 horas") e o legado que
> guardava os métodos originais em aliases `old_*` **nunca usados** — código morto.

#### Scenario: Um único conjunto de e-mails de senha
- **GIVEN** o ai9 em produção
- **WHEN** qualquer e-mail de senha é enviado
- **THEN** ele vem do conjunto único do produto, sem caminho alternativo genérico

### Requirement: OPS-005 — Associação do "membro padrão" a todos os projetos

O ai9 SHALL garantir que quando um usuário é marcado como membro padrão, o sistema cria a membership dele em todos os
projetos, de forma assíncrona, com progresso e falha observáveis. Fonte legada:
`app/decorators/models/user_decorator.rb:3,242-262`; `lib/insert_projects_on_default_user_job.rb`.

> Nota: corrige o legado, em que **as exceções eram engolidas** (`rescue => e` vazio) e
> `destroy_failed_jobs? = false` — a falha ficava invisível e o usuário podia terminar sem
> as memberships prometidas.

#### Scenario: Membro padrão criado
- **GIVEN** um usuário marcado como membro padrão e 40 projetos existentes
- **WHEN** o processamento conclui
- **THEN** ele é membro dos 40 projetos com papel `Participante`

#### Scenario: Falha no processamento
- **GIVEN** uma falha no meio do processamento
- **WHEN** o job termina em erro
- **THEN** o erro é registrado e visível, com possibilidade de reprocessar

### Requirement: OPS-006 — Reprocessamento a cada atualização do usuário

O ai9 SHALL garantir que a associação em massa do membro padrão só é disparada quando o estado de "membro padrão"
efetivamente muda. Fonte legada: `app/decorators/models/user_decorator.rb:3`.

> Nota: corrige o legado, em que o `after_commit` rodava em **todo** update do usuário,
> reenfileirando o job inteiro; as memberships duplicadas falhavam na unicidade em silêncio.

#### Scenario: Atualização que não muda o estado
- **GIVEN** um usuário membro padrão
- **WHEN** apenas o telefone dele é atualizado
- **THEN** nenhuma associação em massa é reprocessada

#### Scenario: Novo projeto criado
- **GIVEN** usuários marcados como membros padrão
- **WHEN** um projeto novo é criado
- **THEN** eles passam a ser membros dele

### Requirement: OPS-007 — Configuração do provedor OAuth

O ai9 SHALL garantir que se o login social for reativado, a configuração do provedor exige validação do parâmetro
`state` e não define papel administrativo por default. Fonte legada:
`engines/auth_omni19/config/initializers/devise.rb:1-11`;
`engines/auth_omni19/lib/livetat/auth_omni19/configuration.rb:12-20`.

> Nota: corrige D-40 (legado: **`provider_ignores_state: true`** desligava a proteção CSRF
> do fluxo OAuth) e D-39 (legado: `facebook_default_role_type_for_sign_up = "Admin"`).

> AMBIGUIDADE: D-41 aberto — as credenciais são placeholders (`app_id = "0"`) e o segredo
> vinha de `config/application.yml`, **não versionado**. Sem decisão entre descartar ou
> reativar.

#### Scenario: Callback sem `state` válido
- **GIVEN** o provedor OAuth habilitado
- **WHEN** um callback chega sem o `state` emitido pelo servidor
- **THEN** a autenticação é recusada

### Requirement: OPS-008 — Configuração de autenticação de aplicação cliente

O ai9 SHALL garantir que a configuração de headers de aplicação cliente, remetente de e-mail e realm é explícita e
vem de configuração persistente. Fonte legada:
`engines/auth19/lib/livetat/auth/configuration.rb:12-33`;
`engines/auth19/config/initializers/devise.rb:3-8`.

> Nota: corrige o legado, em que a `secret_key` era **regenerada a cada boot** (ver DB-013) e
> em que a substituição dos controllers de sessão/cadastro/senha acontecia num
> `before_initialize` de outra engine — configuração implícita que o ai9 declara de forma
> explícita.

#### Scenario: Configuração ausente
- **GIVEN** uma variável de configuração obrigatória não definida
- **WHEN** a aplicação sobe
- **THEN** ela falha no boot com mensagem clara, em vez de assumir um default inseguro

### Requirement: OPS-009 — Seeds de tipos de usuário e permissões

O ai9 SHALL garantir que os tipos de usuário e o catálogo de permissões são criados por seed versionado e
idempotente, sem operações destrutivas sobre dados existentes. Fonte legada:
`db/seeds.rb:1-22,33-104,341-358`; `engines/auth19/db/seeds.rb:1-60`.

> Nota: corrige D-36 (legado: o seed do app **destrói** os tipos `Admin`, `Manager` e
> `Visitor` criados pela engine e recria `Admin`/`Gerente`/`Colaborador` — deixando as
> configurações default apontando para tipos inexistentes).

> Nota: corrige D-35 (legado: com `should_update_abilities = true`, o seed zera
> `user_is_readonly` nos três tipos e roda `reset_permissions` + `save` em **todos** os
> usuários — operação O(n) que reescreve todas as abilities e pode apagar overrides
> deliberados). No ai9, como a permissão é resolvida por consulta, o seed não precisa tocar
> em usuário nenhum.

> AMBIGUIDADE: as hierarquias reais dependem do dump ausente de `livetat_auth_role_types`
> (DEC-04) — ver DB-006.

#### Scenario: Seed executado duas vezes
- **GIVEN** um ambiente já populado
- **WHEN** o seed roda novamente
- **THEN** nada é destruído e nenhum override de permissão de usuário é sobrescrito

#### Scenario: Ordem de execução
- **GIVEN** um ambiente novo
- **WHEN** o seed roda
- **THEN** os dados de referência ficam consistentes independentemente da ordem interna dos blocos
