# Engines (plataforma livetat) Specification

## Purpose

As 7 engines locais que o legado `sfg` monta (`engines/`, declaradas em `Gemfile.linux:6-12`)
como **capacidades de plataforma**: `auth19` (núcleo de identidade), `auth_ux19` (camada
HTTP/UX de auth), `feedback19` (mensagens/tickets), `mailer19` (envio de e-mail), `ux_kit19`
(kit de UI e utilitários), `auth_omni19` (login social) e `navkit` (navegação matricial).
Cobre os IDs **500–539** do `feature-inventory.md` (BE, FE, DB, OPS). O comportamento de auth
do ponto de vista do produto está na capability `auth-users` (IDs 001–049); aqui a
sobreposição aponta para lá em vez de duplicar a regra.

Duas engines estão **mortas** — `navkit` (D-120) e `auth_omni19` — e ficam registradas como
código morto **com evidência**, para o Phase 2 decidir o descarte. A navegação real do
console **não vem da navkit**: vem de `create_console_menu`
(`app/helpers/application_helper.rb:100-172`), especificada em NAV-001 (D-118).

> LACUNA DE DADOS: o **dump de `livetat_auth_role_types` não existe** (DEC-04). Toda regra
> que depende de `hierarchy` — inclusive os gates de menu do NAV-001 — é inferida do código
> e de `db/seeds.rb:40-84` (`OG` = 1111, `Admin` = 998, `Gerente` = 888, `Colaborador` = 799).

## Requirements

### Requirement: ENG-navkit — A engine `navkit` é código morto (descarte com evidência)

O ai9 SHALL descartar a engine `navkit`, que **não carrega** no legado: nada do seu
comportamento é portado. Fonte legada: `Gemfile.linux:12`; `engines/navkit/lib/`;
`engines/navkit/lib/livetat/navkit.rb:1`; `app/views/layouts/site.html.erb:120-121`.

Evidência registrada, três provas independentes:
1. **Falta o arquivo de entrada** `engines/navkit/lib/livetat_navkit.rb` — o `Bundler.require`
   pede `livetat_navkit`, recebe `LoadError` cujo `path` bate com o nome pedido e (por o nome
   não conter `-`) **engole o erro em silêncio**; `Livetat::Navkit::Engine` nunca é registrada.
2. `engines/navkit/lib/livetat/navkit.rb:1` faz `require "livetat_ux_kit"` — arquivo
   inexistente (o correto seria `livetat_ux_kit19`).
3. O JS/CSS só é importado pelo pack `site_gems`, referenciado **apenas** pelo layout
   `app/views/layouts/site.html.erb`, que **nenhum controller usa**.

Além disso, o conteúdo configurado é de **outro produto**: os itens são de um site de
colégio ("conheça o nosso time", "MATRICULAR", "tour 360"), sem relação com o Safegold.

> Nota: corrige D-120 — a engine inteira é descartada. A navegação do console do ai9 se
> baseia no NAV-001 (`create_console_menu`), nunca na navkit.

> AMBIGUIDADE: confirmação em runtime pendente — vale checar `Rails.application.railties`
> num ambiente do legado antes do descarte definitivo. As três provas convergem, mas nenhuma
> foi executada.

#### Scenario: Navegação do console no ai9
- **GIVEN** o ai9 em produção
- **WHEN** o menu do console é renderizado
- **THEN** ele vem da configuração declarativa do NAV-001, e nenhum componente de navegação matricial existe no produto

#### Scenario: Remoção da dependência
- **GIVEN** o build de assets do legado, que resolve `Gem.loaded_specs['livetat_navkit'].full_gem_path`
- **WHEN** o ai9 é construído
- **THEN** não existe nenhuma dependência de build sobre a navkit (ver OPS-508)

### Requirement: ENG-auth_omni19 — A engine `auth_omni19` é código morto (descarte com evidência)

O ai9 SHALL descartar a engine `auth_omni19`, cujo login social **não funciona** no legado e
não é portado. Fonte legada: `app/definitions/SFG/metadata.rb:4-5`; `config/routes.rb:245`; `config/application.rb:75-80`;
`app/views/pub/base/nav/sign_in/_sign_in.js.erb:22-52`.

Evidência registrada:
1. As credenciais são placeholders: `FACEBOOK_APP_ID = 0` e `FACEBOOK_APP_SECRET = 0` — o
   `FB.init` falha e o cookie do SDK vira `fbsr_0`.
2. **O seletor `.facebook_button` não existe em nenhum HTML** do app — os handlers JS que
   chamam `signWithFacebook` nunca se ligam a nada (FE-522).
3. `User.from_omniauth` está quebrado: `engines/auth_omni19/app/decorators/user_decorator.rb:25`
   lê `Livetat::Auth.config.facebook_default_role_type_for_sign_up`, config que só existe em
   `Livetat::AuthOmni19` → `NoMethodError`.
4. O SDK carregado (`//connect.facebook.net/pt_BR/all.js`) está descontinuado.

> Nota: corrige D-40 (legado: `provider_ignores_state: true` desligava a proteção CSRF do
> OAuth) e D-39 (legado: `facebook_default_role_type_for_sign_up = "Admin"` — conta social
> nova virava Admin). Se a capacidade for reativada, ambos nascem corrigidos (ver
> `auth-users`, BE-023 e OPS-007).

> AMBIGUIDADE: D-41 permanece **aberto** — o usuário não decidiu entre descartar de vez ou
> reativar o login social. Enquanto isso, a engine fica registrada como morta.

#### Scenario: Login social no ai9
- **GIVEN** o ai9 em produção
- **WHEN** a tela de login é renderizada
- **THEN** nenhum botão ou fluxo de login social é oferecido

#### Scenario: Dados do provedor social
- **GIVEN** a tabela de vínculos sociais do legado
- **WHEN** o ETL avalia a migração
- **THEN** a contagem de linhas é reportada e o descarte só ocorre se ela for vazia (ver DB-506)

### Requirement: NAV-001 — Menu do console (a especificação de fato da navegação)

O ai9 SHALL garantir que o menu do console é definido por uma configuração declarativa de **grupos** e **itens**, com
gate por projeto, por papel e por permissão, e com o estado `locked`. Fonte legada:
`app/helpers/application_helper.rb:100-172` (dados);
`app/views/pub/console/base/menu/_container.html.erb:1-43` (render);
`app/frontend/js/simple_menu.js:1-60+` (estado ativo); `config/routes.rb:44` (rota canônica
`/u/console(/:resource)(/:topic)(/:section)`).

Estrutura: cada **grupo** tem `identifier`, `title`, ícone, `default_topic`, `resource` e uma
lista de `items` (`identifier`, `title`, `resource`, `topic`, e opcionalmente `locked` e
`target`). Grupo sem itens vira link direto; grupo com itens abre submenu.

Grupos e gates (`application_helper.rb:103-169`):
- **`dash` — "Início"**: sempre visível, sem itens.
- **`results_group` — "Gestão"**: só se `current_user.projects.count > 0`. Itens: Controle de
  Risco, Painel de Disponibilidade (`locked`), Recebíveis, Renegociações, Indicadores,
  Operações de Risco, Operações Estruturadas.
- **`project_group` — "Projeto"**: o **grupo aparece sempre**, mas os itens só se
  `projects.count > 0`. Itens: Cobranças (`locked`), Disponibilidades (`locked`), Empresas,
  Fornecedores, Garantias, Indicadores específicos, Limites, Remunerações.
- **`management` — "Cadastro"**: só se `og? || admin? || manager?`. 17 itens: Projetos,
  Carteiras, Contas, Grupos de Portadores, Indicadores, Padrões de Disponibilidade
  (`locked`), **Permissões — só se `!current_user.may?("user_is_readonly")`**, Portadores,
  Segmentos, Subsegmentos, Tipos de Movimentação, Tipos de Recebíveis, Tipos de Recursos,
  Tipos de Limite, Tipos de OP Estruturada, Movimentações de Risco, Tipos de garantia.
- **`admin_settings` — "Admin"**: só se `og? || admin?`. Item: Central de ajuda.
- **`account` — "Perfil"**: item Minha conta. **`faq` — "Ajuda"**: sem itens.

Estados por item: `locked` (herdado do grupo, vira classe CSS `locked` + `data-locked`) e
`inactive` (hard-coded para o identifier `reports`, `_container.html.erb:24`). O item ativo é
resolvido casando o `data-url` com a URL corrente. O rodapé do menu mostra a versão do build
(`SFG::Metadata::DESCRIPTION`) e os links de termos de uso e políticas de privacidade
(`/contract/{KIND}`).

> Nota: corrige D-118 quanto ao **lugar** (a regra se preserva): no legado a especificação da
> navegação está escondida num helper de view. No ai9 vira configuração declarativa de rotas
> + permissões, e é a base da matriz de autorização do DEC-08.

> Nota: corrige D-120 — o menu **não** vem da navkit.

> Nota: corrige D-34 — os gates de papel e permissão que hoje só existem aqui, na view,
> passam a valer também no servidor: esconder o item do menu deixa de ser a única proteção.

> AMBIGUIDADE: os 4 itens marcados `locked` e o `reports` marcado `inactive` não têm
> semântica documentada (D-90 registra que o `locked` está quebrado). Sem decisão do usuário
> sobre o que "locked" deve fazer no ai9: esconder, exibir desabilitado com explicação, ou
> abrir normalmente.

> AMBIGUIDADE: os gates `og?`/`admin?`/`manager?` dependem dos nomes e `hierarchy` reais dos
> `RoleType`, cujo dump não existe (DEC-04).

#### Scenario: Usuário sem projetos
- **GIVEN** um usuário autenticado que não é membro de nenhum projeto
- **WHEN** o menu do console é renderizado
- **THEN** o grupo "Gestão" não aparece, e o grupo "Projeto" aparece **sem itens**

#### Scenario: Colaborador não vê "Cadastro" nem "Admin"
- **GIVEN** um usuário de papel `Colaborador`
- **WHEN** o menu é renderizado
- **THEN** os grupos "Cadastro" e "Admin" não aparecem

#### Scenario: Operador somente-leitura
- **GIVEN** um usuário `Admin` com a permissão `user_is_readonly` ligada
- **WHEN** o menu é renderizado
- **THEN** o grupo "Cadastro" aparece **sem** o item "Permissões"

#### Scenario: Item de menu escondido não é rota aberta
- **GIVEN** um usuário que não vê determinado item no menu
- **WHEN** ele chama diretamente a rota daquele recurso
- **THEN** a resposta é 403 — o gate vale no servidor, não só no menu

#### Scenario: Item ativo
- **GIVEN** o usuário numa tela cujo recurso corresponde a um item do menu
- **WHEN** a tela é renderizada
- **THEN** aquele item aparece como selecionado

### Requirement: BE-500 — Configuração global da engine de identidade

O ai9 SHALL garantir que a engine de identidade expõe configuração global (headers de aplicação cliente, remetente de
e-mail, realm, segredo, controllers e layouts de autenticação, aliases de entidade, limites
default e papel default), consumida por modelos, controllers e seeds. Fonte legada:
`engines/auth19/lib/livetat/auth/configuration.rb:1-60`; sobrescrita em `config/application.rb:64-73`.

Valores efetivos no Safegold: `private_entities_alias = "Projetos"`,
`public_entities_alias = "Módulos"`, limites default 1000, headers `X-LAA-Agent`/`X-LAA-Token`.

> AMBIGUIDADE: o Safegold define `default_role_type = ""` (string vazia), o que faz **qualquer**
> usuário criado sem `role_type` explícito falhar em `validate_role_type`
> (`user.rb:64-68`). Não há decisão: é intencional (forçar escolha explícita) ou é o bug
> D-36? Ver `auth-users` (BE-049, OPS-009).

#### Scenario: Configuração explícita no boot
- **GIVEN** o ai9 subindo
- **WHEN** a configuração de identidade é carregada
- **THEN** os valores vêm de configuração declarada e versionada, e a ausência de um valor obrigatório falha o boot com mensagem clara

### Requirement: BE-501 — Modelo de usuário da plataforma

O ai9 SHALL garantir que o modelo de usuário concentra identidade (`formal`, `username`, `email`), credencial e os
parâmetros permitidos por operação, com login aceitando username **ou** e-mail. Fonte legada:
`engines/auth19/app/models/livetat/auth/user.rb:1-284`;
`engines/auth19/app/validators/livetat/auth/username_convention_validator.rb:1-11`.

Regras: `formal` obrigatório 3..60; `username` opcional, único, 3..20, alfanumérico
(`[[:alnum:]._-]`), começa com letra e ASCII-only, com mensagens em pt-BR. Ver `auth-users`
(DB-014) para a regra consolidada.

> Nota: corrige o legado — `create_fast` (`user.rb:175-185`) chama `use_random_password`,
> método **inexistente** na engine e no decorator: caminho quebrado, não portar. E o
> validator usa `record.errors[field] << ...`, API removida no Rails 6.1+.

> Nota: corrige o alias global `U` (`user.rb:286`) — o ai9 não define aliases globais de
> constante.

#### Scenario: Criação por caminho "rápido"
- **GIVEN** qualquer fluxo do ai9 que crie usuário
- **WHEN** o registro é criado
- **THEN** ele passa pelo mesmo caminho validado de criação, sem atalhos que gerem senha aleatória silenciosamente

### Requirement: BE-502 — Token de API por usuário

O ai9 SHALL garantir que cada usuário pode ter um token de API único, gerado sob demanda e revogável. Fonte legada:
`engines/auth19/app/models/livetat/auth/user.rb:84-103`.

> Nota: corrige o legado — o token era gerado em `before_save` sempre que estivesse em
> branco, o logout JSON o **zerava** e o login JSON o **regenerava regravando a senha**
> (`sessions_controller.rb:44-47,63`). No ai9 emitir ou revogar token **nunca** altera a
> credencial do usuário (ver `auth-users`, BE-004 e BE-006).

#### Scenario: Emissão de token
- **GIVEN** um usuário autenticado que solicita um token de API
- **WHEN** o token é emitido
- **THEN** ele é único e o hash da senha do usuário permanece inalterado

### Requirement: BE-503 — Avatar do usuário com variantes de imagem

O ai9 SHALL garantir que o sistema aceita upload de avatar (imagem, até 3 MB), gera variantes de tamanho e serve o
avatar padrão para quem não enviou nenhum. Fonte legada:
`engines/auth19/app/models/livetat/auth/user.rb:4-20,60-61,75-77,245-249`;
`engines/auth19/config/initializers/paperclip.rb:1-8`.

Variantes do legado: `thumb` 80, `preview` 250, `medium` 500, `large` 1200, `retina` 1500,
todas convertidas para JPG com perfil sRGB.

> Nota: corrige D-56 (legado: a engine **monkey-patcheia**
> `Paperclip::MediaTypeSpoofDetector#spoofed?` para sempre `false`, desligando a detecção de
> spoof **no app inteiro**, com os arquivos indo para `public/system/`, servido
> publicamente). No ai9 o tipo real do arquivo é verificado e o storage é privado com URL
> assinada (ver OPS-506 e `auth-users`, BE-017/DB-003).

#### Scenario: Arquivo com content-type falsificado
- **GIVEN** um arquivo executável renomeado como `.jpg`
- **WHEN** o upload é tentado
- **THEN** a resposta é 422 e nada é gravado no storage

#### Scenario: Arquivo acima do limite
- **GIVEN** uma imagem de 5 MB
- **WHEN** o upload é tentado
- **THEN** a resposta é 422 informando o limite de 3 MB

### Requirement: BE-504 — Tipos de usuário e vínculo de papel

O ai9 SHALL garantir que o sistema mantém tipos de usuário com `name` único e `hierarchy` inteira, e vincula cada
usuário a um tipo; a hierarquia define quais tipos um operador pode conceder. Fonte legada:
`engines/auth19/app/models/livetat/auth/role_type.rb:1-45`; `role.rb:1-54`; `db/seeds.rb:40-84`.

Regra de subordinação (`role_type.rb:15-26`): se o tipo pode `may_create_users`, ele alcança
tipos com `hierarchy <= a sua`; senão, apenas `< a sua`.

> Nota: corrige D-35 (legado: trocar `role_type` no `Role` **clonava** as abilities do novo
> tipo, e o clone só acrescentava nomes ainda inexistentes — valores customizados antigos
> sobreviviam e abilities do tipo anterior **não eram removidas**, deixando o usuário com uma
> mistura dos dois papéis). No ai9 a permissão efetiva é resolvida por consulta.

> AMBIGUIDADE: nomes e `hierarchy` reais dependem do dump ausente de
> `livetat_auth_role_types` (DEC-04).

#### Scenario: Troca de tipo de usuário
- **GIVEN** um usuário `Gerente` com permissões do tipo `Gerente`
- **WHEN** ele passa a ser `Colaborador`
- **THEN** as permissões efetivas passam a ser exatamente as de `Colaborador`, sem resíduo do tipo anterior

#### Scenario: Concessão de tipo
- **GIVEN** um operador de hierarquia 888
- **WHEN** ele lista os tipos que pode conceder
- **THEN** a lista respeita a regra de subordinação declarada acima

### Requirement: BE-505 — Catálogo de permissões (`AbilityFactory`)

O ai9 SHALL garantir que o catálogo de permissões tem 12 condicionais, 4 limites e a condicional `user_is_readonly`
acrescentada pela aplicação, com descrições em pt-BR parametrizadas pelos aliases de entidade.
Fonte legada: `engines/auth19/lib/livetat/auth/ability_factory.rb:1-215`;
`app/decorators/models/ability_factory_decorator.rb:1-35`;
`engines/auth19/app/models/livetat/auth/ability.rb:1-29`.

> Nota: corrige o legado, em que o decorator do app **reescreve o `init` inteiro**, copiando
> as 16 linhas originais só para acrescentar 1 permissão. No ai9 o catálogo é um ponto de
> extensão, não uma cópia.

> Nota: ver `auth-users` (DB-008) para o conteúdo do catálogo e para o D-17
> (`user_is_readonly` não checado em nenhum controller).

#### Scenario: Extensão do catálogo
- **GIVEN** a necessidade de acrescentar uma permissão nova
- **WHEN** ela é declarada
- **THEN** o catálogo base permanece intacto e a nova entrada é adicionada sem duplicá-lo

### Requirement: BE-506 — Resolução de permissões do usuário

O ai9 SHALL garantir que o sistema responde se um usuário tem uma permissão condicional e qual é o valor de um limite.
Fonte legada: `engines/auth19/app/models/livetat/auth/user.rb:206-242`;
uso em `app/helpers/application_helper.rb:145`.

> Nota: corrige D-35 (legado: `include_ability_methods` rodava em **todo** `after_initialize`
> e fazia `define_method` na **classe** `User` — mutação global de classe em runtime, com
> custo por instância e com o efeito colateral de que remover uma permissão do banco fazia os
> métodos dinâmicos deixarem de existir, quebrando as views com `NoMethodError`). No ai9 a
> consulta é explícita e determinística.

#### Scenario: Permissão desconhecida
- **GIVEN** uma consulta a um nome de permissão fora do catálogo
- **WHEN** a autorização é resolvida
- **THEN** o resultado é "negado", sem erro de execução

#### Scenario: Limite consultado
- **GIVEN** um usuário e uma permissão do tipo limite
- **WHEN** o valor é consultado
- **THEN** o número configurado é devolvido (0 quando não há limite definido)

### Requirement: BE-507 — Perfil estendido do usuário (modelo da plataforma)

O ai9 SHALL garantir que o modelo de perfil estendido guarda os dados pessoais e de contato e calcula o nível de
confiabilidade. Fonte legada:
`engines/auth19/app/models/livetat/auth/user_info.rb:1-188`.

> Nota: corrige o legado, que usa `self.errors[:cpf] << ...` (`:176,184`), API removida no
> Rails 6.1+ — quebra na migração.

> Nota: ver `auth-users` (DB-004, DB-015, DB-016) para os campos, o cálculo de confiabilidade
> e as validações.

#### Scenario: Recálculo automático
- **GIVEN** um perfil sendo salvo
- **WHEN** a gravação ocorre
- **THEN** o nível de confiabilidade e os indicadores derivados são recalculados a partir dos dados, ignorando o que o cliente enviou nesses campos

### Requirement: BE-508 — Aplicação cliente e autenticação por headers

O ai9 SHALL garantir que o sistema autentica aplicações cliente pelo par agente + token enviado em headers. Fonte
legada: `engines/auth19/app/models/livetat/auth/client_application.rb:1-31`;
`app/decorators/models/livetat_auth_client_application_decorator.rb:1-38`;
`engines/auth_ux19/app/controllers/livetat/auth_ux19/application_controller.rb:15-33`.

> Nota: corrige D-34/D-57 (legado: a guarda `lock_if_its_not_a_valid_client_app` **só era
> aplicada quando o formato não era HTML nem JS**). Ver `auth-users` (BE-047).

> Nota: corrige o legado, em que o decorator do app **manipula os `_validators` internos do
> ActiveRecord** para remover as validações de unicidade da engine — frágil e dependente de
> versão (ver `auth-users`, DB-009).

#### Scenario: Par agente/token inválido
- **GIVEN** uma rota que exige aplicação cliente
- **WHEN** a chamada traz um par inválido, em qualquer formato
- **THEN** a resposta é 401 com erro estruturado

### Requirement: BE-509 — Rotas e configuração do Devise pela engine

O ai9 SHALL garantir que a engine define as rotas de sessão e a configuração de autenticação (chave de login,
normalização de e-mail, custo de hash, comprimento de senha, prazo de recuperação e verbo de
logout). Fonte legada: `engines/auth19/config/routes.rb:1-9`;
`engines/auth19/config/initializers/devise.rb:1-36`; montada em `config/routes.rb:244`.

> Nota: corrige o legado — `sign_out_via = :delete` conflita com a chamada do app
> (`app/views/pub/base/nav/sign_out/_sign_out.js.erb:4` usa `/users/sign_out.html`); e
> `reconfirmable = true` é **inerte**, porque `:confirmable` e `:lockable` não estão na lista
> de módulos do usuário (`user.rb:27-28`). No ai9 não há configuração inerte: o que está
> declarado tem efeito.

> Nota: ver `auth-users` (DB-013) para as regras de senha e token.

#### Scenario: Configuração sem efeito
- **GIVEN** a configuração de autenticação do ai9
- **WHEN** ela é revisada
- **THEN** não existe opção declarada cujo módulo correspondente esteja desligado

### Requirement: BE-510 — Fluxo de reset de senha no modelo

O ai9 SHALL garantir que o modelo gera o token de recuperação, registra quando foi enviado, compara senha e
confirmação e consome o token ao concluir. Fonte legada:
`engines/auth19/app/models/livetat/auth/user.rb:119-162`.

> Nota: corrige D-37 (legado: a expiração de 6 horas **nunca é verificada** no fluxo custom
> do auth_ux19 — ver BE-521). No ai9 o token é de uso único, expira e rotaciona a cada
> solicitação (ver `auth-users`, BE-020 e BE-022).

> AMBIGUIDADE: o legado reaproveita `remember_created_at` como "data da última troca de
> senha". Sem decisão sobre criar um campo próprio no ai9.

#### Scenario: Token consumido
- **GIVEN** um token usado com sucesso
- **WHEN** ele é apresentado de novo
- **THEN** é recusado

### Requirement: BE-511 — Locales fornecidos pela engine

O ai9 SHALL garantir que a engine fornece traduções de datas e das mensagens de autenticação em pt-BR. Fonte legada:
`engines/auth19/config/locales/{pt-BR.yml, en.yml, devise.pt-BR.yml, devise.en.yml}`;
consumo em `app/helpers/application_helper.rb:59,175`.

> Nota (DEC-09): i18n **fica fora do escopo** — o ai9 nasce em pt-BR fixo, como o legado
> (0 de 717 views usam `t()`). O que se preserva é o conteúdo pt-BR de nomes de dias e meses,
> usado na formatação de datas.

> AMBIGUIDADE: o app também carrega `my/locales/*` (`config/application.rb:26`) — a
> precedência entre os dois conjuntos não foi verificada.

#### Scenario: Formatação de data
- **GIVEN** uma data exibida na interface
- **WHEN** ela é formatada com nome de mês ou de dia
- **THEN** o nome aparece em pt-BR


### Requirement: BE-512 — Configuração do provedor OAuth (código morto)

O ai9 SHALL garantir que a configuração do provedor social **não é portada** enquanto o D-41 estiver aberto. Fonte
legada: `engines/auth_omni19/lib/livetat/auth_omni19/configuration.rb:1-23`;
`engines/auth_omni19/config/initializers/devise.rb:1-11`; `config/application.rb:75-80`.

> Nota: corrige D-40 (legado: **`provider_ignores_state: true`** desliga a proteção CSRF do
> fluxo OAuth — **não replicar**) e D-39 (legado: papel default de cadastro social = `Admin`).

> Nota: evidência de código morto — o Safegold passa `app_id = 0`, `secret = 0` e
> `default_role_type_for_sign_up = ""` (ver ENG-auth_omni19).

#### Scenario: Provedor não configurado
- **GIVEN** o ai9 em produção
- **WHEN** a configuração de autenticação é carregada
- **THEN** nenhum provedor social é registrado

### Requirement: BE-513 — Callback OAuth em três modos (código morto)

O ai9 SHALL garantir que o controller de callback com os modos `sign_in`, `sign_up` e `both` **não é portado**. Fonte
legada: `engines/auth_omni19/app/controllers/livetat/auth_omni19/callbacks_controller.rb:1-114`;
`engines/auth_omni19/config/routes.rb:1-9`.

> Nota: evidência de código morto — o app sempre chama com `kind = "both"`
> (`app/views/pub/base/nav/sign_in/_sign_in.js.erb:31`), mas o botão que dispararia a chamada
> não existe (FE-522). Os hooks `before/after_sign_in/up` (`:3-17`) estão **vazios** — ponto
> de extensão nunca usado.

> Nota: corrige o **contrato de resposta inconsistente** do legado: `omni_both` renderiza o
> payload canônico de usuário, enquanto `omni_sign_in`/`omni_sign_up` devolvem um JSON inline
> diferente.

#### Scenario: Rota de callback social
- **GIVEN** o ai9 em produção
- **WHEN** a rota de callback social é acessada
- **THEN** ela não existe (404)

### Requirement: BE-514 — Vínculo de usuário com provedor social (código morto)

O ai9 SHALL garantir que a busca/criação de usuário a partir do payload do provedor **não é portada**. Fonte legada:
`engines/auth_omni19/app/decorators/user_decorator.rb:1-35`;
`engines/auth_omni19/app/models/livetat/auth_omni19/provider.rb:1-5`.

> Nota: corrige D-39/D-40 e a falha grave de casamento de conta: o legado busca em cascata
> por (provider, uid) → e-mail → **`formal` (nome completo)**, o que é **account takeover por
> homônimo**. Não portar em nenhuma hipótese.

> Nota: evidência de código morto — `user_decorator.rb:25` lê
> `Livetat::Auth.config.facebook_default_role_type_for_sign_up`, config que só existe em
> `Livetat::AuthOmni19` → `NoMethodError` garantido se o caminho fosse executado.

#### Scenario: Vínculo por nome completo
- **GIVEN** um payload de provedor social cujo nome completo coincide com o de um usuário existente
- **WHEN** ele é processado por qualquer fluxo do ai9
- **THEN** **nenhum** vínculo de conta é criado com base no nome

### Requirement: BE-515 — Hierarquia de controllers base da engine de auth

O ai9 SHALL garantir que as guardas de acesso (exige usuário, exige aplicação cliente, ou aceita ambos) são
declaradas de forma explícita por rota. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/application_controller.rb:1-36`;
`{app_required,user_required,app_or_user_required}_application_controller.rb`.

> Nota: corrige o legado — o `AppOrUserRequiredApplicationController` define um handler de
> fallback que **nunca é registrado** no `acts_as_token_authentication_handler_for`: código
> morto que dava a impressão de existir um fallback aplicação-ou-usuário.

> Nota: nenhum controller do Safegold herda dessas classes (o app usa
> `PubApplicationController`) — no ai9 a guarda vira middleware/policy explícito por rota.

#### Scenario: Rota que aceita usuário ou aplicação
- **GIVEN** uma rota declarada como "usuário ou aplicação cliente"
- **WHEN** ela recebe apenas credencial de aplicação válida
- **THEN** a requisição é aceita, e o comportamento do fallback é o declarado (não um caminho morto)

### Requirement: BE-516 — Login: os dois formatos e a sobrescrita da aplicação

O ai9 SHALL garantir que o login existe em **um** contrato no ai9, consolidando o caminho HTML e o caminho JSON do
legado. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/sessions_controller.rb:17-52,85-113`;
`app/decorators/controllers/sessions_decorator.rb:1-30`.

> Nota: corrige D-42 (legado: dois caminhos com **regras diferentes** — o corte por
> hierarquia mínima só existia no HTML e o caminho JSON, que é o do produto, o **bypassava**;
> na prática a regra não valia).

> AMBIGUIDADE: sem decisão sobre manter o corte "só quem é ≥ Admin entra pela web" no ai9
> (ver `auth-users`, BE-002).

> Nota: ver `auth-users` (BE-002, BE-003) para o comportamento consolidado.

#### Scenario: Regra única de login
- **GIVEN** dois clientes diferentes (navegador e integração)
- **WHEN** ambos autenticam
- **THEN** as mesmas regras de bloqueio e de autorização se aplicam aos dois

### Requirement: BE-517 — Logout nos dois formatos

O ai9 SHALL garantir que o logout encerra a sessão e, quando aplicável, revoga o token, sem exigir a senha e sem
alterar a credencial. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/sessions_controller.rb:54-76`.

> Nota: corrige o legado — o logout JSON exigia a senha, **zerava o token** e o reatribuía,
> e deixava `puts resource.id`/`puts resource.errors` em produção (`:66,71`). Ver
> `auth-users` (BE-005, BE-006).

#### Scenario: Logout sem senha
- **GIVEN** uma sessão válida
- **WHEN** o logout é solicitado
- **THEN** a sessão é encerrada sem que a senha seja pedida ou reprocessada

### Requirement: BE-518 — Listagem de usuários da engine

O ai9 SHALL garantir que a listagem de usuários da plataforma aplica busca, ordenação por `formal` e paginação real.
Fonte legada: `engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:11-43,208-228`.

> Nota: corrige D-20 (legado: `@offset = params[:limit].blank? ? 0 : params[:offset]` — o
> offset era decidido testando o **limit**). Ver `auth-users` (BE-009).

> Nota: o `slicer` que distribuía a coleção em colunas é responsabilidade de apresentação e
> não é portado para o backend.

#### Scenario: Paginação aplicada
- **GIVEN** uma listagem com `limit` e `offset`
- **WHEN** ela é executada
- **THEN** os dois parâmetros são respeitados de forma independente

### Requirement: BE-519 — CRUD de usuário e de perfil da engine

O ai9 SHALL garantir que o CRUD de usuário e de perfil da plataforma é o mesmo consolidado na capability `auth-users`
(BE-012 a BE-016), com autorização no servidor. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:45-174,230-335`;
`app/decorators/controllers/registrations_decorator.rb:1-125`.

> Nota: corrige D-124 — o método `decorate_if_new_password_or_fck_this_nigger`
> (`registrations_controller.rb:113,189`) tem **nome ofensivo** e é **renomeado
> obrigatoriamente** para um identificador descritivo em inglês.

> Nota: corrige D-38 — o `create` bem-sucedido dispara, no legado,
> `NotificationFacade.send_welcome_email_to_new_user` **com as credenciais**
> (`registrations_decorator.rb:24-39`). No ai9 envia-se link de definição de senha
> (ver `auth-users`, OPS-001).

> Nota (DEC-11): `update_info` usa `update_attributes` (`:140`), que **funciona** em Ruby
> 2.6.1 / Rails 6.0.3.2 — é feature real a migrar, não código morto (ver `auth-users`, BE-016).

> Nota: corrige o `puts` de debug em produção (`:143`).

#### Scenario: Nome de método ofensivo
- **GIVEN** a base de código do ai9
- **WHEN** ela é inspecionada
- **THEN** não existe nenhum identificador com o termo ofensivo herdado do legado

### Requirement: BE-520 — Alteração pontual de uma permissão pela engine

O ai9 SHALL garantir que a alteração do valor de uma permissão exige autorização verificada no servidor. Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/registrations_controller.rb:58-72`;
`engines/auth_ux19/config/routes.rb:12`.

> Nota: corrige D-34 (legado: **falha de autorização** — o endpoint não checava hierarquia
> nem permissão do chamador; a proteção era **apenas visual**, calculada em
> `show/_abilities.html.erb:1`, e o `:id` da URL era ignorado). Ver `auth-users` (BE-018).

#### Scenario: Chamada direta sem autorização
- **GIVEN** um usuário autenticado sem direito de administrar permissões
- **WHEN** ele chama o endpoint diretamente
- **THEN** a resposta é 403 e nenhuma permissão é alterada

### Requirement: BE-521 — Fluxo custom de recuperação de senha da engine

O ai9 SHALL garantir que o fluxo de recuperação (solicitar, abrir o link, definir a nova senha) é o consolidado na
capability `auth-users` (BE-019 a BE-022). Fonte legada:
`engines/auth_ux19/app/controllers/livetat/auth_ux19/passwords_controller.rb:1-81`;
`engines/auth_ux19/config/routes.rb:14-21`.

> Nota: corrige D-37 — no legado a **expiração do token nunca é verificada** (`reset` e
> `set_new` só fazem `where(reset_password_token: token)`), o token só é gerado na primeira
> solicitação (`:49-51`) e com token inválido o `set_new` estoura `NoMethodError` sobre nil.

> Nota: corrige a enumeração de contas (`:59` — "O e-mail não está associado a nenhuma
> conta. Quer tentar novamente?").

> Nota: corrige D-123 — a tela de link expirado quebrava antes de renderizar (ver FE-507).

#### Scenario: Token expirado
- **GIVEN** um link de recuperação fora do prazo
- **WHEN** o usuário tenta definir a nova senha por ele
- **THEN** a operação é recusada com mensagem de link inválido e nenhuma senha é alterada

### Requirement: BE-522 — Fachada de notificações de senha

O ai9 SHALL garantir que os e-mails do fluxo de senha são enviados por uma fachada única, com os templates temáticos
do produto. Fonte legada: `engines/auth_ux19/lib/livetat/auth_ux19/notification.rb:1-35`;
`app/decorators/facades/auth_ux19_notification_decorator.rb:1-14`.

> Nota: corrige D-37 — o texto default da engine promete expiração em **24 horas**, o Devise
> está configurado para **6 horas** e o código **não expira nunca**: três verdades
> divergentes. No ai9 há **uma** e o texto do e-mail a informa (ver `auth-users`, OPS-002).

> Nota: corrige o legado — o decorator cria aliases `old_*` (`:3-4`) que **nunca são usados**:
> código morto.

#### Scenario: Prazo comunicado
- **GIVEN** um e-mail de recuperação enviado
- **WHEN** o usuário o lê
- **THEN** o prazo informado no texto é exatamente o prazo aplicado pelo sistema

### Requirement: BE-523 — Efeitos colaterais globais da engine de UX de auth

O ai9 SHALL garantir que as configurações que afetam a aplicação inteira são **declaradas explicitamente** no ai9, não
transferidas por hook de engine. Fonte legada:
`engines/auth_ux19/lib/livetat/auth_ux19/engine.rb:33-45` e `:19-21`;
equivalente em `engines/feedback19/lib/livetat/feedback19/engine.rb:21-23`.

Dois efeitos globais no legado: (1) um `before_initialize` transfere para a engine de
identidade os controllers e layouts de sessão/cadastro/senha — é isso que faz a autenticação
usar as telas da engine de UX; (2) o `field_error_proc` é substituído para devolver o HTML
cru, de modo que campos inválidos **não recebem** o wrapper de erro do Rails: os erros só
aparecem por mensagem/JS.

> Nota: o próprio legado registra `#TODO: Desnecessauro essa transferência aqui` (`:34`).

#### Scenario: Exibição de erro de campo
- **GIVEN** um formulário enviado com campo inválido
- **WHEN** a resposta é renderizada
- **THEN** o erro é exibido junto ao campo por um mecanismo declarado da própria aplicação

### Requirement: BE-524 — Rotas da engine de UX de auth

O ai9 SHALL garantir que as rotas de autenticação, cadastro, perfil, avatar, permissões e senha existem uma única vez.
Fonte legada: `engines/auth_ux19/config/routes.rb:1-22`; montada em `config/routes.rb:246`.

> Nota: corrige o legado — a engine de identidade é montada **duas vezes** (em
> `config/routes.rb:244` e dentro das rotas da engine de UX, `:2`), o que duplica helpers e
> caminhos e torna impossível saber qual está em uso sem rodar `rails routes`.

> AMBIGUIDADE: quais helpers/paths estão efetivamente em uso não foi verificado (exigiria
> `rails routes` no legado).

#### Scenario: Um caminho por capacidade
- **GIVEN** o mapa de rotas do ai9
- **WHEN** ele é inspecionado
- **THEN** cada capacidade de identidade tem exatamente um caminho canônico

### Requirement: BE-525 — Configuração da engine de mensagens

O ai9 SHALL garantir que a engine de mensagens expõe configuração de rótulos dos campos extras e de uma persona de
atendimento genérica. Fonte legada:
`engines/feedback19/lib/livetat/feedback19/configuration.rb:1-29`.

> Nota: evidência de código morto — **o Safegold nunca chama
> `Livetat::Feedback19.configure`**, então `is_generic_admin_active` é falso e **todos** os
> ramos que dependem dele (`grind_mailer_decorator.rb:7,41`, `mailing_decorator.rb:3`,
> `notification.rb:78`) são código morto no produto. A persona "Equipe da Livetat"/"Help"
> não é portada.

#### Scenario: Persona genérica
- **GIVEN** o ai9 em produção
- **WHEN** uma notificação de mensagem é enviada
- **THEN** ela usa a identidade do próprio produto, sem persona genérica de terceiros

### Requirement: BE-526 — Mensagem (ticket) com campos extras e tokens de acesso

O ai9 SHALL garantir que o sistema registra uma mensagem com remetente, e-mail, texto (até 500 caracteres), contexto,
situação e dois campos extras opcionais, gerando um token público e um privado e criando a
primeira nota da conversa. Fonte legada:
`engines/feedback19/app/models/livetat/feedback19/message.rb:1-169`.

Regras: `formal` 3..40; e-mail validado por formato; rótulos extras 2..40 e valores extras
3..300, **obrigatórios quando o campo extra está habilitado**; situação default "Não lido";
contexto default "Outros"; marcar como lida ou favorita exige o usuário que marcou.

> Nota: os nomes `hadouken`/`shoryuken` são piadas internas e **são renomeados** no ai9 para
> nomes semânticos (ex.: rótulo/valor do campo extra 1 e 2), preservando o mapeamento com os
> dados existentes.

#### Scenario: Campo extra habilitado sem valor
- **GIVEN** uma mensagem cujo campo extra está habilitado
- **WHEN** ela é enviada sem o valor desse campo
- **THEN** a resposta é 422 exigindo o preenchimento

#### Scenario: Tokens de acesso
- **GIVEN** uma mensagem criada
- **WHEN** ela é persistida
- **THEN** ela recebe um token público e um privado, ambos únicos

### Requirement: BE-527 — Máquina de estados da mensagem

O ai9 SHALL garantir que a mensagem percorre 8 situações — Não lido, Lido, Aberto, Avaliado, Respondido, Concluído,
Fechado e Rejeitado — com transições automáticas. Fonte legada:
`engines/feedback19/app/models/livetat/feedback19/state.rb:1-40`;
`message.rb:102-115`; `note.rb:66-83`; `messages_controller.rb:107-137,156-169`.

Transições do legado: administrador abre mensagem "Não lido" sem notas próprias → **"Lido"**;
primeira resposta do administrador numa mensagem "Lido" → **"Respondido"**; resposta do
usuário quando a nota anterior foi do administrador → **"Aberto"**. São situações finais:
Concluído, Fechado e Rejeitado.

> AMBIGUIDADE: **em `update`, pedir "Concluído" grava "Fechado"** (`messages_controller.rb:118-122`),
> enquanto a ação dedicada de fechamento grava "Concluído" (`:156-159`) — os dois estados
> estão trocados entre os dois caminhos. Sem decisão do usuário sobre qual é o correto.

> Nota: corrige o legado, em que as situações são resolvidas em **variáveis de classe no load
> da classe** (`state.rb:6-13`, `context.rb:9-12`): se o seed não rodou antes do boot, ficam
> nulas e a aplicação quebra. No ai9 as situações são enumeração em código.

#### Scenario: Primeira leitura pelo atendente
- **GIVEN** uma mensagem em "Não lido" e um atendente que ainda não respondeu
- **WHEN** ele a abre
- **THEN** a situação passa a "Lido"

#### Scenario: Resposta do atendente
- **GIVEN** uma mensagem em "Lido"
- **WHEN** o atendente responde pela primeira vez
- **THEN** a situação passa a "Respondido"

#### Scenario: Resposta do usuário
- **GIVEN** uma mensagem cuja última nota é do atendente
- **WHEN** o usuário responde
- **THEN** a situação passa a "Aberto"

#### Scenario: Boot sem dados de referência
- **GIVEN** um ambiente sem os dados de referência de situação carregados
- **WHEN** a aplicação sobe
- **THEN** ela sobe normalmente (as situações são código, não linhas de banco)


### Requirement: BE-528 — Notas: thread de respostas, citação, não-lidas e limite de envio

O ai9 SHALL garantir que o sistema registra respostas (notas) de até 500 caracteres numa conversa, com citação
"achatada" para a raiz da cadeia, controle de não-lidas por lado da conversa e limite de
envio para remetente anônimo. Fonte legada:
`engines/feedback19/app/models/livetat/feedback19/note.rb:1-84`; `message.rb:117-145`;
`notes_controller.rb:1-70`.

Regras: remetente anônimo pode criar no máximo **5 notas em 30 minutos**; atendente não tem
limite. O autor vem do usuário autenticado ou, quando anônimo, dos dados da própria mensagem.

> AMBIGUIDADE: `may_send_email?` (`note.rb:33-59`) implementa um cooldown de 30 minutos entre
> notificações usando índices negativos de coleção (`[-2]`) — a regra exata é difícil de
> reproduzir e não foi confirmada.

#### Scenario: Limite do remetente anônimo
- **GIVEN** um remetente anônimo que já enviou 5 respostas nos últimos 30 minutos
- **WHEN** ele envia a sexta
- **THEN** a resposta é recusada com a mensagem de limite

#### Scenario: Citação encadeada
- **GIVEN** uma nota que cita outra nota que já era uma citação
- **WHEN** ela é salva
- **THEN** a referência de citação aponta para a raiz da cadeia

### Requirement: BE-529 — Contextos, observadores e vínculo observador ↔ contexto

O ai9 SHALL garantir que o sistema classifica mensagens por contexto e mantém observadores que são notificados por
contexto. Fonte legada:
`engines/feedback19/app/models/livetat/feedback19/context.rb:1-48`; `observer.rb:1-38`;
`observer_context.rb:1-12`; `observers_controller.rb:1-80+`.

Contextos do legado: Outros, Problema, Contato e Sugestão, cada um com uma cor. Observador
tem e-mail único e validado, título obrigatório, e por default é notificado tanto de mensagens
internas quanto externas. Criar ou atualizar observador exige **pelo menos um contexto**.

> Nota: corrige o legado — `Context.updates_for_context` (`:23-30`) referencia
> `Livetat::Feedback19::context.other` (minúsculo), método inexistente: código morto.

> Nota (DEC-11): a edição de observador usa `update_attributes` e **funciona** em produção
> (D-91); o `@total_count` que ignora filtros e a troca de `companyId`/`observerId` **seguem
> defeitos** e são corrigidos.

#### Scenario: Observador sem contexto
- **GIVEN** o cadastro de um observador
- **WHEN** nenhum contexto é selecionado
- **THEN** a resposta é 422 exigindo a seleção

#### Scenario: Vínculo duplicado
- **GIVEN** um observador já vinculado a um contexto
- **WHEN** o mesmo vínculo é criado de novo
- **THEN** a resposta é 422 com "Definição já existente"

### Requirement: BE-530 — Notificações por e-mail do módulo de mensagens

O ai9 SHALL garantir que o sistema envia quatro notificações: confirmação ao remetente com aviso aos observadores do
contexto, inclusão de observador, remoção de observador e nova resposta na conversa. Fonte
legada: `engines/feedback19/lib/livetat/feedback19/notification.rb:1-109`.

Regra: observadores marcados como não-internos **não são notificados** de mensagens internas.
O assunto da notificação de resposta muda conforme quem respondeu.

> Nota: corrige o legado, em que todo o HTML dos e-mails é montado por **concatenação de
> string em Ruby** (`:50-64`) — no ai9 são templates.

#### Scenario: Mensagem interna
- **GIVEN** uma mensagem marcada como interna e um observador não-interno
- **WHEN** as notificações são disparadas
- **THEN** esse observador **não** recebe e-mail

#### Scenario: Nova resposta
- **GIVEN** uma resposta registrada numa conversa
- **WHEN** a notificação é enviada
- **THEN** o destinatário recebe o assunto correspondente ao seu lado da conversa e um link para a conversa

### Requirement: BE-531 — Endpoints de mensagens

O ai9 SHALL garantir que o sistema expõe a criação pública de mensagem, a consulta da conversa por token e a gestão
(listar, atualizar, encerrar) para atendentes autorizados. Fonte legada:
`engines/feedback19/app/controllers/livetat/feedback19/messages_controller.rb:1-264`;
`engines/feedback19/config/routes.rb:1-13`.

Regras a preservar: sem usuário autenticado, a conversa só é acessível pelo **token público**;
com usuário autenticado, também pelo token privado ou pelo identificador. A listagem só
devolve mensagens para quem tem a permissão correspondente.

> Nota: corrige D-57 (legado: a guarda de aplicação cliente estava declarada no
> `before_action` mas **só bloqueava formatos que não fossem HTML/JS** — na prática o `create`
> via JS era livre; o que é intencional para o envio público, mas não para as demais ações).

#### Scenario: Envio público
- **GIVEN** um visitante não autenticado
- **WHEN** ele envia uma mensagem válida
- **THEN** a mensagem é criada e ele recebe o link com o token público

#### Scenario: Acesso à conversa por token privado sem sessão
- **GIVEN** um visitante não autenticado
- **WHEN** ele tenta abrir a conversa pelo token privado
- **THEN** o acesso é recusado

#### Scenario: Listagem sem permissão
- **GIVEN** um usuário autenticado sem permissão de gerir mensagens
- **WHEN** ele consulta a listagem
- **THEN** a resposta é 403

### Requirement: BE-532 — Roteamento de resposta das ações de mensagens e observadores

O ai9 SHALL garantir que cada ação de mensagem e de observador tem uma resposta **explícita**, escolhida pelo contexto
de origem do envio. Fonte legada:
`app/decorators/controllers/feedback_messages_decorator.rb:1-36`;
`app/decorators/controllers/observers_decorator.rb:1-20`.

No legado a origem é indicada por um parâmetro com três valores (sugestão na página inicial,
feedback no console, e o formulário do site) e determina qual partial responde.

> Nota: corrige o **bug estrutural** do legado: o `if` externo (`:4`) **não tem `else`**, de
> modo que qualquer ação que não seja a criação devolve `nil` e o Rails cai no **render
> implícito** por nome de ação. Funciona por acaso em `update`/`destroy` e **não funciona** em
> `show`; e torna a edição de observador inalcançável, porque o template que ela tenta
> renderizar não existe nem na engine nem no app.

#### Scenario: Ação sem resposta declarada
- **GIVEN** qualquer ação de mensagem ou de observador no ai9
- **WHEN** ela é executada
- **THEN** existe uma resposta declarada para ela, sem depender de render implícito

#### Scenario: Edição de observador
- **GIVEN** um atendente autorizado
- **WHEN** ele abre a edição de um observador
- **THEN** a tela abre normalmente

### Requirement: BE-533 — Configuração de envio de e-mail

O ai9 SHALL garantir que a configuração de e-mail (identidade visual e parâmetros do servidor) é centralizada e vem de
variáveis de ambiente. Fonte legada:
`engines/mailer19/lib/livetat/mailer19/configuration.rb:1-36`; `smtp_settings.rb:1-20`;
`engines/mailer19/lib/livetat/mailer19/engine.rb:33-52`; `config/application.rb:92-115`.

> Nota: corrige o legado — (1) a **porta nunca é configurada** pelo Safegold, caindo no
> default da engine; (2) o default da engine embute **credenciais em texto puro**
> (`smtp_settings.rb:8-13`) — **não portar**; (3) `openssl_verify_mode: VERIFY_NONE`
> desabilita a verificação do certificado do servidor; (4) `raise_delivery_errors = false`
> **esconde falhas de envio**.

#### Scenario: Falha de entrega
- **GIVEN** o servidor de e-mail recusando a mensagem
- **WHEN** o envio é tentado
- **THEN** a falha é registrada e visível para operação

#### Scenario: Credencial ausente
- **GIVEN** uma variável de configuração de e-mail obrigatória não definida
- **WHEN** a aplicação sobe
- **THEN** ela falha com mensagem clara, sem cair em credencial embutida no código

### Requirement: BE-534 — API de alto nível de envio de e-mail e registro de envios

O ai9 SHALL garantir que o sistema oferece uma API de envio (confirmação de mensagem recebida, confirmação de conta,
convite, mensagem genérica e mensagem genérica com link), registra cada envio e despacha o
envio de forma assíncrona. Fonte legada:
`engines/mailer19/lib/livetat/mailer19/grind_mailer.rb:1-103`;
`engines/feedback19/app/decorators/grind_mailer_decorator.rb:1-74`.

> AMBIGUIDADE: o modo de entrega vem do ambiente como **String** e é comparado com um
> **Symbol** (`:async`) — a condição **nunca é verdadeira**, então não se sabe qual caminho de
> despacho roda de fato em produção. Precisa ser confirmado antes de replicar.

> Nota: corrige o legado — `grind_mailer_decorator.rb:59` faz `sender[:email]` assumindo um
> Hash, mas o chamador passa um objeto de usuário (`notification.rb:66-72`) → `NoMethodError`
> no ramo não-genérico.

#### Scenario: Registro do envio
- **GIVEN** qualquer e-mail enviado pelo produto
- **WHEN** o envio é despachado
- **THEN** existe um registro do envio com destinatário, assunto e origem

#### Scenario: Modo de despacho
- **GIVEN** a configuração de modo de entrega
- **WHEN** ela é lida
- **THEN** o valor é interpretado corretamente e o caminho de despacho usado é o configurado

### Requirement: BE-535 — Mailer com anexos inline

O ai9 SHALL garantir que os e-mails são enviados com o logo do produto embutido e, quando aplicável, com o avatar do
remetente. Fonte legada:
`engines/mailer19/app/mailers/livetat/mailer19/mailing.rb:1-68`;
`engines/feedback19/app/decorators/mailing_decorator.rb:1-35`;
`app/decorators/models/mailer_decorator.rb:1-46`.

> Nota: corrige o legado — (1) `File.new(...).read` sem tratamento de erro: **arquivo ausente
> derruba o envio**; (2) `mailing_decorator.rb:19` compara `sender.class` com uma **String**
> (`Livetat::Auth::User.name`), comparação **sempre falsa**, então o ramo que anexaria o
> avatar do remetente nunca executou.

#### Scenario: Recurso visual ausente
- **GIVEN** um logo indisponível no momento do envio
- **WHEN** o e-mail é montado
- **THEN** ele é enviado sem o anexo, e a ausência é registrada — o envio não falha

### Requirement: BE-536 — Os três e-mails próprios do produto (temáticos)

O ai9 SHALL garantir que o produto envia três e-mails com a identidade visual do tema do usuário: boas-vindas ao novo
usuário, instruções de recuperação de senha e confirmação de senha alterada. Fonte legada:
`app/decorators/models/mailer_decorator.rb:3-43`; `lib/notification_facade.rb:1-15`.

> Nota: corrige D-38 — o e-mail de boas-vindas do legado tem assunto "Credenciais pra acesso
> ao ..." e leva **e-mail e senha em texto puro**. No ai9 ele leva **link de definição de
> senha** (ver `auth-users`, OPS-001).

> Nota: corrige o legado, em que a fachada **sempre** despacha de forma assíncrona, ignorando
> a configuração de modo de entrega (ver BE-534), e em que o envio depende de o tema ter os
> dois logos anexados — sem eles, o envio quebra.

#### Scenario: Tema sem logo
- **GIVEN** um usuário cujo tema não tem logo configurado
- **WHEN** um dos três e-mails é enviado
- **THEN** ele é enviado com a identidade padrão do produto, sem falhar

### Requirement: BE-537 — Endpoints HTTP da engine de e-mail (código morto)

O ai9 SHALL garantir que os endpoints HTTP de contatos da engine de e-mail **não são portados**. Fonte legada:
`engines/mailer19/app/controllers/livetat/mailer19/contacts_controller.rb:1-48`;
`engines/mailer19/config/routes.rb:1-6`; montada em `config/routes.rb:248`.

> Nota: evidência de código morto — não existe **nenhuma** referência a `livetat_mailer19.`
> ou a `/mailer/` fora da montagem; a ação de convite chama o método de envio com 4
> argumentos quando ele exige 5 (`ArgumentError` garantido); e o template de resposta não
> existe. **Rota pública exposta e quebrada — remover.**

#### Scenario: Rotas de e-mail expostas
- **GIVEN** o ai9 em produção
- **WHEN** o mapa de rotas é inspecionado
- **THEN** não existe nenhuma rota pública de disparo de e-mail

### Requirement: BE-538 — Utilitários de data e helper de view do kit de UI

O ai9 SHALL garantir que os utilitários de data que representam "sem limite" em filtros de período são preservados
como constantes explícitas; o helper de view do kit **não é portado**. Fonte legada:
`engines/ux_kit19/config/initializers/date_utils.rb:1-17`;
`engines/ux_kit19/app/helpers/livetat/ux_kit19/application_helper.rb:1-50`.

Vivos: os limites inferior e superior "infinitos" de data e os limites de início/fim do dia,
usados por 4 controllers e 1 model como valor default de filtros de período.

> Nota: corrige o legado — o helper de view está **duplicado** no app
> (`app/helpers/application_helper.rb:2-9,22-37,48-53,76-88`, com dois métodos marcados
> `#FIXME: ta no ux_kit19`) e a versão do app **vence por precedência**, com regra
> **diferente** para nome de uma palavra. No ai9 há uma implementação só.

> Nota: risco explícito — se os utilitários de data sumirem sem substituto, os filtros de
> período quebram **silenciosamente** (passam a filtrar por um intervalo errado em vez de
> falhar).

#### Scenario: Filtro de período sem datas informadas
- **GIVEN** uma consulta com filtro de período e nenhuma data informada
- **WHEN** ela é executada
- **THEN** o intervalo default abrange todo o histórico, com o mesmo resultado do legado

### Requirement: BE-539 — A engine de navegação matricial não carrega

O ai9 SHALL registrar como código morto a engine `navkit`, que **não é registrada** pela
aplicação legada, e não portá-la. Fonte legada:
`Gemfile.linux:12`; `engines/navkit/lib/` (sem `livetat_navkit.rb`);
`engines/navkit/lib/livetat/navkit.rb:1`; `engines/navkit/lib/livetat/navkit/engine.rb:1-18`;
`engines/navkit/lib/livetat/navkit/configuration.rb:1-13` (vazia).

> Nota: corrige D-120 — ver ENG-navkit para as três provas e o descarte com evidência. O JS/CSS
> ainda é resolvido pelo empacotador via caminho da gem, mas só no pack usado por um layout que
> **nenhum controller carrega**.

> AMBIGUIDADE: confirmação em runtime pendente (`Rails.application.railties` num ambiente do
> legado).

#### Scenario: Registro de engines no ai9
- **GIVEN** o ai9 em produção
- **WHEN** as dependências carregadas são inspecionadas
- **THEN** não existe nenhuma dependência de navegação matricial

#### Scenario: Erro de carregamento silencioso
- **GIVEN** uma dependência declarada que não pode ser carregada
- **WHEN** a aplicação sobe
- **THEN** o erro é explícito e o boot falha — nenhum `LoadError` é engolido (ver OPS-509)


### Requirement: BE-747 — Controllers de autenticação vazios são apenas ponto de ancoragem das rotas

O ai9 SHALL registrar que os três controllers de autenticação da engine `auth19`
(`Livetat::Auth::SessionsController`, `RegistrationsController` e `PasswordsController`) são **classes
vazias** — herança pura do Devise, sem nenhum override — e **MUST** reimplementar o comportamento
correspondente (login, registro e reset de senha) em Grape + JWT, sem herdar nada do Devise. Fonte
legada: `engines/auth19/app/controllers/livetat/auth/sessions_controller.rb:1-6`;
`registrations_controller.rb:1-5`; `passwords_controller.rb:1-5`; `engines/auth19/config/routes.rb`.

- As três classes existem **só para dar namespace às rotas `devise_for`**. O comportamento é 100%
  padrão do Devise.
- Quem realmente customiza o fluxo é a engine `auth_ux19`
  (`engines/auth_ux19/app/controllers/livetat/auth_ux19/*_controller.rb`, ver BE-516..BE-521): é lá que
  está o comportamento observável, e é ele que define a paridade.
- No ai9 **não há Devise**. Estes três pontos são a âncora a substituir: sessão (login/logout),
  registro e recuperação de senha passam a ser endpoints Grape com JWT (ver
  `openspec/specs/auth-users/spec.md`).

> AMBIGUIDADE: é preciso confirmar, no roteador do legado em runtime, se alguma rota ainda resolve para
> a versão `auth19` em vez da `auth_ux19`. Se alguma resolver, o comportamento efetivo daquele caminho é
> o padrão do Devise, não o customizado — e a paridade daquele caminho muda.

#### Scenario: nenhum comportamento perdido no descarte
- **GIVEN** os três controllers vazios da engine
- **WHEN** o inventário de comportamento a portar é fechado
- **THEN** consta a evidência de que eles não contêm lógica própria, e a paridade é definida pelos controllers da engine de UX

#### Scenario: fluxos de autenticação existem no ai9
- **GIVEN** o ai9 em operação
- **WHEN** login, registro e recuperação de senha são exercitados
- **THEN** os três funcionam por endpoints próprios com JWT, sem nenhuma dependência de framework de autenticação do legado

#### Scenario: rota residual apontando para a engine
- **GIVEN** a tabela de rotas do legado
- **WHEN** ela é inspecionada em runtime
- **THEN** cada rota de autenticação é atribuída ao controller que de fato a atende, e o caso é registrado antes de o slice de auth ser fechado

### Requirement: BE-748 — Herança de permissões vira dado, não metaprogramação

O ai9 SHALL descartar o mixin `Livetat::Auth::ClassLevelInheritableAttributes` e **MUST** expressar a
herança do catálogo de permissões como **dado versionado**, não como atributos de classe copiados por
metaprogramação. Fonte legada:
`engines/auth19/lib/livetat/auth/class_level_inheritable_attributes.rb:1-29`; incluído por
`engines/auth19/lib/livetat/auth.rb:10` e usado por `livetat/auth/ability_factory.rb`.

- Mecanismo legado: `inheritable_attributes(*args)` gera um `attr_accessor` de classe por atributo
  usando `class_eval` de **string**, e o hook `inherited` copia o valor de cada atributo para a
  subclasse no momento da definição.
- É a infraestrutura sobre a qual a `AbilityFactory` (BE-505) monta o catálogo de permissões herdado por
  papel: a herança de permissões do legado é, literalmente, cópia de variável de classe.
- Não tem superfície de usuário — é mecanismo interno. O que **MUST** ser preservado é o **resultado**:
  quais permissões cada papel herda (ver OPS-541 e DEC-08).
- Cópia por `inherited` acontece uma única vez, na definição da subclasse: alterar o atributo da classe
  pai depois disso **não propaga**. Essa armadilha **MUST NOT** ser reproduzida.

#### Scenario: catálogo de permissões inspecionável
- **GIVEN** o catálogo de permissões do ai9
- **WHEN** se pergunta quais permissões um papel herda
- **THEN** a resposta é lida da configuração versionada, sem depender de ordem de carregamento de classes

#### Scenario: nenhuma avaliação de código gerado em string
- **GIVEN** o código do ai9
- **WHEN** ele é varrido por definição dinâmica de acessores a partir de string
- **THEN** nenhum ponto do modelo de permissões usa esse mecanismo

#### Scenario: mudança na permissão de um papel base
- **GIVEN** uma permissão alterada em um papel do qual outros derivam
- **WHEN** a resolução de permissões roda
- **THEN** os papéis derivados refletem a mudança, em vez de manterem a cópia feita no momento da definição

### Requirement: FE-500 — Layout base da engine de auth (inerte)

O ai9 SHALL garantir que o layout base da engine **não é portado**. Fonte legada:
`engines/auth_ux19/app/views/layouts/livetat/auth_ux19/application.html.erb:1-21`.

> Nota: evidência de código morto — o legado desligou o pipeline de assets clássico, e o
> layout usa exatamente as tags desse pipeline: se ele fosse usado, quebraria. Além disso o
> app o sobrescreve (FE-501).

#### Scenario: Layout das telas de autenticação
- **GIVEN** o ai9 em produção
- **WHEN** uma tela de autenticação é renderizada
- **THEN** ela usa o layout da própria aplicação, não o da plataforma

### Requirement: FE-501 — Layout real das telas de autenticação

O ai9 SHALL garantir que o layout efetivo das telas de autenticação é o da aplicação, com estados de carregamento
(splash + "carregou"/"vai carregar") e pontos de extensão de cabeçalho e rodapé. Fonte legada:
`app/views/layouts/livetat/auth_ux19/application.html.erb:110-136`.

> Nota: é **este** layout — e não o da engine — que o ai9 precisa reproduzir. Ele tem
> dependência explícita de um componente do app (o rodapé), documentada no próprio arquivo.

#### Scenario: Carregamento da tela de autenticação
- **GIVEN** um visitante abrindo a tela de login
- **WHEN** a página carrega
- **THEN** o estado de carregamento é exibido até o conteúdo estar pronto, e então a tela aparece

### Requirement: FE-502 — Tela de login da engine (inalcançável)

O ai9 SHALL garantir que a tela de login da engine **não é portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/sessions/new.html.erb:1-87`.

> Nota: evidência de código morto — o controller de sessões exige autenticação em tudo exceto
> a criação (`sessions_controller.rb:7`), então a rota que renderiza esta tela **exige estar
> logado**: ela é inalcançável para quem precisa dela. O login real é a tela do app; da
> engine, só o **endpoint** de criação de sessão é usado (ver `auth-users`, BE-001).

> Nota: os campos honeypot (`fakeusrn`/`fakepasswd`) são comportamento anti-robô a preservar
> na tela canônica.

#### Scenario: Tela de login única
- **GIVEN** o ai9 em produção
- **WHEN** o usuário acessa a autenticação
- **THEN** existe uma única tela de login, a do produto

### Requirement: FE-503 — Tela de login obsoleta da engine

O ai9 SHALL garantir que a tela explicitamente marcada como obsoleta **não é portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/sessions/obsolete_new.html.erb`.

> Nota: evidência de código morto — nome autoexplicativo e **nenhuma referência** no
> repositório.

#### Scenario: Descarte
- **GIVEN** o inventário do Phase 2
- **WHEN** esta tela é avaliada
- **THEN** ela é marcada como descartada com a evidência acima

### Requirement: FE-504 — Tela "esqueci a senha" da engine

O ai9 SHALL garantir que a tela de solicitação de recuperação da engine **não é portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/passwords/remember.html.erb:1-86`.

> Nota: corrige D-42 — é uma das **duas** páginas de "esqueci a senha" do legado; o fluxo
> canônico é o painel embutido na tela de login (ver `auth-users`, FE-004).

#### Scenario: Solicitação de recuperação
- **GIVEN** um usuário que perdeu a senha
- **WHEN** ele inicia a recuperação
- **THEN** existe um único caminho para isso

### Requirement: FE-505 — Cópia da tela "esqueci a senha" dentro do app

O ai9 SHALL garantir que a cópia byte a byte da tela anterior, mantida no app, **não é portada**. Fonte legada:
`app/views/livetat/auth_ux19/users/passwords/remember.html.erb:1-86`.

> Nota: corrige D-42 — a única diferença em relação à FE-504 é a precedência de resolução de
> view. **Nenhuma tela aponta para ela**, embora a rota siga acessível.

#### Scenario: Rota órfã
- **GIVEN** o ai9 em produção
- **WHEN** o mapa de rotas é inspecionado
- **THEN** não existe rota de recuperação de senha sem tela que aponte para ela

### Requirement: FE-506 — Tela "nova senha" da engine

O ai9 SHALL garantir que a tela de definição de nova senha da engine **não é portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/passwords/reset.html.erb:1-95`.

> Nota: corrige D-42 — é uma das **duas** telas de reset; a canônica é a FE-507.

#### Scenario: Definição de nova senha
- **GIVEN** um link de recuperação válido
- **WHEN** o usuário o abre
- **THEN** ele chega à única tela de definição de nova senha do produto

### Requirement: FE-507 — Tela "nova senha" do produto (a que está no ar)

O ai9 SHALL garantir que a tela canônica de nova senha saúda o usuário pelo primeiro nome, mostra a data da última
troca, exige senha e confirmação iguais para habilitar o envio, aplica o tema do usuário e
tem um estado dedicado para link inválido ou expirado. Fonte legada:
`app/views/livetat/auth_ux19/users/passwords/reset.html.erb:1-86`; `.../_reset.js.erb`; `_after_reset.js.erb:1-24`.

> Nota: corrige D-123 (legado: a aplicação do tema (`:85`) chama `@user.app_theme` **fora** da
> guarda de usuário nulo, então a própria tela de "link expirado" quebra com `NoMethodError`
> — o estado existia no código e era inalcançável na prática).

> Nota: corrige D-37 — o estado "expirado" passa a acontecer de verdade, porque o token
> passa a expirar.

#### Scenario: Link expirado
- **GIVEN** um link de recuperação inválido ou vencido
- **WHEN** o usuário o abre
- **THEN** a tela mostra a mensagem de link expirado e o caminho para pedir um novo, sem erro de servidor

#### Scenario: Senhas coincidentes
- **GIVEN** o formulário com senha e confirmação iguais e preenchidas
- **WHEN** o usuário revisa a tela
- **THEN** o botão de trocar senha está habilitado

### Requirement: FE-508 — Tela padrão de troca de senha do framework

O ai9 SHALL garantir que a tela padrão do framework, em inglês, **não é portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/passwords/edit.html.erb:1-27`.

> Nota: evidência de código morto — o Safegold não expõe essa rota, e o inglês num produto
> pt-BR confirma o abandono. Usa ainda `devise_error_messages!`, API removida em versões
> posteriores.

#### Scenario: Telas em inglês
- **GIVEN** o ai9 em produção
- **WHEN** qualquer tela é renderizada
- **THEN** ela está em pt-BR (DEC-09: sem i18n, pt-BR fixo)

### Requirement: FE-509 — Tela de cadastro da engine

O ai9 SHALL garantir que a tela de cadastro da engine **não é portada**; o **endpoint** correspondente é usado pelo
console. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/new.html.erb:1-6`;
`new/_form.html.erb:1-30`.

> Nota: o Safegold usa telas próprias de criação de usuário no console
> (`app/views/pub/console/parts/users/helper/body.js.erb:6-7`) que postam no endpoint da
> engine — o endpoint é vivo, a tela não.

#### Scenario: Criação de usuário
- **GIVEN** um operador autorizado
- **WHEN** ele cria um usuário
- **THEN** usa a tela do console (ver `auth-users`, FE-019)

### Requirement: FE-510 — Tela "cadastro concluído" da engine

O ai9 SHALL garantir que a tela de conclusão de cadastro **não é portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/done.html.erb:1-21`.

> Nota: evidência de código morto — renderizada apenas na resposta HTML da criação; como o
> produto sempre usa JSON/JS, ela nunca aparece. O conteúdo é um placeholder ("Deu boa!").

#### Scenario: Conclusão do cadastro
- **GIVEN** um cadastro concluído
- **WHEN** a resposta chega
- **THEN** a própria interface do produto informa a conclusão

### Requirement: FE-511 — Lista de usuários da engine

O ai9 SHALL garantir que a lista de usuários da engine **não é portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/index.html.erb:1-39`.

> Nota: evidência de código morto — a variável que habilitaria o cabeçalho com contagem
> (`@may_invite_users`) **nunca é atribuída** no controller, então esse ramo é morto. O
> produto usa a lista do console.

#### Scenario: Lista de usuários
- **GIVEN** um operador autorizado
- **WHEN** ele lista usuários
- **THEN** usa a lista do console (ver `auth-users`, FE-011)

### Requirement: FE-512 — Perfil de usuário da engine

O ai9 SHALL garantir que a tela de perfil da engine **não é portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/show.html.erb:1-29`.

> Nota: substituída pelas telas de detalhe do console (ver `auth-users`, FE-022 a FE-024).

#### Scenario: Detalhe do usuário
- **GIVEN** um operador autorizado
- **WHEN** ele abre o detalhe de um usuário
- **THEN** usa a tela do console

### Requirement: FE-513 — Painel de permissões do usuário na engine

O ai9 SHALL garantir que o painel de permissões da engine **não é portado**, mas a **regra de edição** que ele carrega
é preservada e passa a valer no servidor. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/show/_abilities.html.erb:1-19`.

Regra (linha 1): o operador **não pode editar as próprias permissões** e só edita usuários de
hierarquia **estritamente inferior** à sua.

> Nota: corrige D-34 — no legado essa regra só aplicava `readonly` no campo; **o backend não
> validava nada** (BE-520). No ai9 ela é a regra de autorização do servidor (ver `auth-users`,
> BE-018).

> AMBIGUIDADE: a seção "Plano" (permissões do tipo limite) tem interface aqui e não tem no
> console; ver `auth-users` (DB-008, FE-024) — sem decisão sobre portar o conceito de limites.

#### Scenario: Edição das próprias permissões
- **GIVEN** um operador de qualquer papel
- **WHEN** ele tenta alterar uma permissão da própria conta
- **THEN** a operação é recusada pelo servidor

### Requirement: FE-514 — Tela de edição de conta do framework

O ai9 SHALL garantir que a tela padrão de edição de conta, em inglês, **não é portada**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/edit.html.erb:1-41`.

> Nota: evidência de código morto — textos em inglês, rota não exposta pelo produto.

#### Scenario: Edição da própria conta
- **GIVEN** um usuário autenticado
- **WHEN** ele edita a própria conta
- **THEN** usa a tela "Minha conta" do console (ver `auth-users`, FE-028)

### Requirement: FE-515 — Widget de usuário (card) da engine

O ai9 SHALL garantir que o card de usuário da engine **não é portado**. Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/widget/_user.html.erb:1-38`.

> Nota: substituído pelos componentes de avatar e pelos widgets do console do produto.

#### Scenario: Representação de usuário na interface
- **GIVEN** qualquer lista de usuários no ai9
- **WHEN** um usuário é exibido
- **THEN** o componente usado é o da biblioteca do produto, com avatar ou iniciais

### Requirement: FE-516 — Contrato de serialização do usuário (vivo e crítico)

O ai9 SHALL garantir que o payload canônico de usuário é a forma única de serializar usuário em toda a plataforma.
Fonte legada:
`engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/{show,index,_show,_extra,_user_info}.json.jbuilder`;
`_extra` sobrescrito em `app/views/livetat/auth_ux19/users/registrations/_extra.json.jbuilder`.

Consumidores no legado: resposta do login (`app/decorators/controllers/sessions_decorator.rb:17`),
callback social (`callbacks_controller.rb:41`), payload de mensagem
(`engines/feedback19/app/views/livetat/feedback19/messages/_show.json.jbuilder:12`), API de
rastreamento (`app/views/api/v1/trackings/_show.json.jbuilder:12,18`) e reset de senha
(`passwords_controller.rb:29`). O partial de extensão modula o conteúdo por contexto
("enxuto" e "usuário corrente").

> Nota: **VIVO e crítico** — o ai9 precisa de um DTO equivalente, com o mesmo contrato e os
> mesmos modos de projeção, porque 5 consumidores dependem dele.

> Nota: corrige o vazamento potencial — o payload inclui dados do perfil e indicadores de
> papel (`is_admin`, `is_og`); no ai9 o modo "enxuto" é o default em contextos públicos, como
> o payload de mensagem.

#### Scenario: Serialização em contexto público
- **GIVEN** um payload de mensagem que embute o autor
- **WHEN** ele é serializado para um destinatário não autenticado
- **THEN** só os campos públicos do usuário aparecem

#### Scenario: Serialização para o próprio usuário
- **GIVEN** a resposta do login
- **WHEN** o payload é montado
- **THEN** ele traz o conjunto completo esperado pelo cliente (ver `auth-users`, BE-003)

### Requirement: FE-517 — Resposta do formulário de perfil

O ai9 SHALL garantir que a atualização do perfil devolve uma resposta declarada, coerente com a origem do envio. Fonte
legada: `engines/auth_ux19/app/views/livetat/auth_ux19/users/registrations/info/new.js.erb`;
`app/decorators/controllers/registrations_decorator.rb:11-21`.

> Nota: no legado a origem do envio é sinalizada por um parâmetro que redireciona a resposta
> para as telas do app — no ai9 a resposta é o resultado da operação, e a decisão de
> apresentação é do cliente.

#### Scenario: Perfil atualizado
- **GIVEN** uma atualização de perfil bem-sucedida
- **WHEN** a resposta chega
- **THEN** o cliente recebe o estado atualizado do perfil e decide como apresentá-lo

### Requirement: FE-518 — Metadados e SEO das telas de autenticação

O ai9 SHALL garantir que as telas de autenticação publicam os metadados do produto (título, empresa, URL, palavras-chave
e imagem de compartilhamento). Fonte legada:
`app/views/livetat/auth_ux19/base/_metadata.html.erb:1-16`; `app/views/preloaders/_meta.html.erb:47-48`.

> Nota: corrige o legado — o identificador de aplicação social sai como `0` na meta tag,
> porque a integração social está desativada (ver ENG-auth_omni19). No ai9 metadados de
> integração desativada **não são emitidos**.

#### Scenario: Compartilhamento de link
- **GIVEN** a tela de login compartilhada em uma rede social
- **WHEN** o link é renderizado pelo destino
- **THEN** aparecem título, descrição e imagem do produto, sem metadados de integrações inativas

### Requirement: FE-519 — Injeções de menu por sobreposição de view (mortas)

O ai9 SHALL garantir que as injeções de chip do usuário e do item "sair" via biblioteca de sobreposição de views
**não são portadas**. Fonte legada:
`engines/auth_ux19/app/overrides/user_chip_without_preload.rb:1-7`; `exit_from_app_without_preload.rb:1-7`;
`engines/auth_ux19/app/views/livetat/auth_ux19/overrides/menu/_{user_chip,exit_from_app_item}.html.erb`.

> Nota: evidência de código morto — as sobreposições apontam para um layout de uma engine que
> **não existe** no repositório, e o partial de confirmação que elas renderizam também não
> existe. O "Sair" real do produto está em `app/views/pub/base/nav/user/_menu.html.erb:40`
> (ver `auth-users`, FE-036).

#### Scenario: Composição do menu
- **GIVEN** o menu do produto
- **WHEN** ele é renderizado
- **THEN** todos os itens vêm de declaração explícita, sem injeção por sobreposição

### Requirement: FE-520 — Views padrão do framework na engine de identidade (mortas)

O ai9 SHALL garantir que as views padrão do framework de autenticação, em inglês, e os três e-mails que as acompanham
**não são portados**. Fonte legada:
`engines/auth19/app/views/livetat/auth/users/**` (10 arquivos);
`engines/auth19/app/views/layouts/livetat/auth/application.html.erb`.

> Nota: evidência de código morto — o produto substitui controllers e layouts (BE-523) e os
> e-mails de senha pelos próprios (FE-536/FE-537); além disso, confirmação de e-mail e
> desbloqueio de conta **não estão habilitados**, então essas telas nunca são alcançadas.

#### Scenario: Confirmação de e-mail
- **GIVEN** o ai9 em produção
- **WHEN** um usuário é criado
- **THEN** não existe fluxo de confirmação de e-mail (coerente com o legado — ver `auth-users`, DB-001)


### Requirement: FE-521 — Componentes JS do SDK social (mortos)

O ai9 SHALL garantir que os partials que injetam e inicializam o SDK social **não são portados**. Fonte legada:
`engines/auth_omni19/app/views/livetat/auth_omni19/facebook/_{component,initializer,sign}.js.erb`.

> Nota: evidência de código morto — o identificador de aplicação é `0`, então a
> inicialização falha e o cookie do SDK vira um nome inválido; o SDK carregado é uma versão
> **descontinuada**, servida por URL sem protocolo explícito.

#### Scenario: Carregamento de SDK de terceiro
- **GIVEN** qualquer tela do ai9
- **WHEN** ela carrega
- **THEN** nenhum SDK social de terceiro é injetado

### Requirement: FE-522 — Botões de login social no produto (prova de que a engine está morta)

O ai9 SHALL garantir que os botões de entrar/cadastrar com provedor social **não existem** na interface do legado e não
são portados. Fonte legada:
`app/views/pub/base/nav/sign_in/_sign_in.js.erb:22-52`; `app/views/pub/base/nav/sign_up/_sign_up.js.erb:6,32`;
estilos em `app/frontend/css/pub/components/base/forms.scss:236,367,392` e
`app/frontend/css/pub/recyclable/button.scss:389-392`.

> Nota: evidência de código morto — **o seletor `.facebook_button` não existe em nenhum
> HTML**: os handlers JS nunca se ligam a nada. Restam apenas os estilos e um arquivo de
> contorno para um bug de renderização do provedor. **É a prova prática de que a engine
> `auth_omni19` está morta** (ver ENG-auth_omni19).

#### Scenario: Tela de login
- **GIVEN** o ai9 em produção
- **WHEN** a tela de login é renderizada
- **THEN** nenhum botão de provedor social aparece, e nenhum estilo órfão é carregado

### Requirement: FE-523 — Formulário de envio de mensagem

O ai9 SHALL garantir que o formulário de mensagem coleta nome, e-mail de contato, texto, contexto e, quando
habilitados, os dois campos extras. Fonte legada:
`engines/feedback19/app/views/livetat/feedback19/messages/_form.html.erb:1-52`;
`app/views/pub/console/parts/feedbacks/_body.html.erb:1-40`.

O formulário do produto oferece o contexto num seletor, com "Problema" como default, e mantém
campos honeypot anti-robô.

#### Scenario: Envio com contexto default
- **GIVEN** o formulário aberto sem alteração do contexto
- **WHEN** a mensagem é enviada
- **THEN** ela é registrada com o contexto "Problema"

#### Scenario: Preenchimento de honeypot
- **GIVEN** um robô que preenche os campos ocultos
- **WHEN** o envio é feito
- **THEN** a mensagem é descartada sem criar registro

### Requirement: FE-524 — Telas placeholder da engine de mensagens

O ai9 SHALL garantir que as telas de scaffold da engine **não são portadas**. Fonte legada:
`engines/feedback19/app/views/livetat/feedback19/messages/index.html.erb:1-21`; `new/new.html.erb:1-19`.

> Nota: evidência de código morto — a tela de índice renderiza literalmente o **caminho do
> próprio template** num título: é scaffold, não tela de produto.

#### Scenario: Telas de mensagens
- **GIVEN** o ai9 em produção
- **WHEN** um atendente gerencia mensagens
- **THEN** usa apenas as telas do console (FE-528)

### Requirement: FE-525 — Respostas alcançadas por render implícito

O ai9 SHALL garantir que toda ação de mensagem tem resposta **declarada**. Fonte legada:
`engines/feedback19/app/views/livetat/feedback19/messages/update.js.erb`; `destroy.js.erb`.

> Nota: corrige o legado — esses templates são alcançados **por acaso**, pelo render implícito
> que resulta do bug estrutural do BE-532. Dependência acidental: tornar explícita no ai9.

#### Scenario: Ação sem template correspondente
- **GIVEN** uma ação de mensagem
- **WHEN** ela é executada
- **THEN** a resposta é a declarada, e a ausência de um template não muda o comportamento

### Requirement: FE-526 — Payload de mensagem

O ai9 SHALL garantir que o payload de mensagem traz identificador, remetente, e-mail, indicadores de lida e favorita,
texto, autor (quando houver), datas de leitura e de criação. Fonte legada:
`engines/feedback19/app/views/livetat/feedback19/messages/_show.json.jbuilder:1-17`.

> Nota: o payload **acopla** o contrato de mensagem ao contrato de usuário (FE-516) — no ai9 o
> autor é serializado no modo enxuto, para não vazar dados de perfil em contexto público.

#### Scenario: Mensagem de remetente anônimo
- **GIVEN** uma mensagem enviada sem usuário autenticado
- **WHEN** o payload é montado
- **THEN** o bloco de autor não aparece

### Requirement: FE-527 — Telas do produto que enviam mensagem

O ai9 SHALL garantir que o produto envia mensagem a partir de três origens: sugestão na página inicial, feedback no
console e o formulário do site. Fonte legada:
`app/views/pub/console/parts/feedbacks/{_body.html.erb,_body.js.erb,handle.js.erb}`;
`pub/start/parts/ads/handle`; `site/join/handle`.

> AMBIGUIDADE: a origem "site" depende do namespace `site/`, cujo layout está **órfão**
> (nenhum controller o usa) — sem confirmação de que essa terceira origem ainda existe em
> produção.

#### Scenario: Envio pelo console
- **GIVEN** um usuário autenticado no console
- **WHEN** ele envia um feedback
- **THEN** a mensagem é criada com a origem correspondente e a confirmação aparece na própria tela

### Requirement: FE-528 — Console de mensagens e de observadores

O ai9 SHALL garantir que o console permite listar e filtrar mensagens por situação e por tipo, abrir a conversa,
responder, encerrar, e gerenciar observadores com seus contextos. Fonte legada:
`app/views/pub/console/parts/admin_messages/_body.html.erb:26,31`; `list/_widget.js.erb:26`;
`observers/helper/_body.html.erb:47`; `observers/list/_widget.js.erb:61`;
`app/controllers/pub/admin_messages_controller.rb:15-18`; `pub/console_observers_controller.rb:15-39`.

> Nota: são telas do app que dependem inteiramente dos modelos da engine — as duas migrações
> **precisam andar juntas**.

> Nota (DEC-11): a edição de observador funciona em produção (D-91); o total de registros que
> **ignora os filtros** e a troca de identificadores continuam defeitos a corrigir.

#### Scenario: Filtro por situação
- **GIVEN** mensagens em várias situações
- **WHEN** o atendente filtra por "Aberto"
- **THEN** apenas essas aparecem, e o total exibido corresponde ao filtro aplicado

#### Scenario: Observador com contextos
- **GIVEN** um observador em edição
- **WHEN** o atendente marca os contextos e salva
- **THEN** o observador passa a ser notificado apenas desses contextos

### Requirement: FE-529 — Layout web da engine de e-mail (inerte)

O ai9 SHALL garantir que o layout web da engine de e-mail **não é portado**. Fonte legada:
`engines/mailer19/app/views/layouts/livetat/mailer19/application.html.erb:1-14`.

> Nota: evidência de código morto — usa o pipeline de assets desligado no legado, e os
> templates de e-mail são HTML completo que não o utiliza.

#### Scenario: Renderização de e-mail
- **GIVEN** qualquer e-mail do produto
- **WHEN** ele é montado
- **THEN** o HTML vem do próprio template, sem layout web intermediário

### Requirement: FE-530 — Template de confirmação de mensagem recebida

O ai9 SHALL garantir que o remetente de uma mensagem recebe a confirmação de recebimento. Fonte legada:
`engines/mailer19/app/views/livetat/mailer19/mailing/confirm_feedback_to.html.erb`;
`confirm_feedback_to.text.erb:1-10`.

> Nota: é o **único** template com versão em texto puro; os outros cinco são só HTML. O texto
> efetivamente enviado no produto vem do decorator da engine de mensagens (BE-534), não deste
> corpo.

#### Scenario: Confirmação ao remetente
- **GIVEN** uma mensagem enviada
- **WHEN** ela é registrada
- **THEN** o remetente recebe a confirmação, com versão em texto puro além do HTML

### Requirement: FE-531 — Template de confirmação de conta (morto)

O ai9 SHALL garantir que o template de confirmação de conta **não é portado**. Fonte legada:
`engines/mailer19/app/views/livetat/mailer19/mailing/confirm_account_of.html.erb`.

> Nota: evidência de código morto — o único chamador é o controller inalcançável do BE-537. O
> texto original ainda tem erro de português.

#### Scenario: Criação de conta
- **GIVEN** um usuário criado no ai9
- **WHEN** ele é notificado
- **THEN** recebe o e-mail de boas-vindas do produto (BE-536), não este

### Requirement: FE-532 — Template de convite (morto)

O ai9 SHALL garantir que o template de convite para trabalhar em um projeto **não é portado**. Fonte legada:
`engines/mailer19/app/views/livetat/mailer19/mailing/account_invitation.html.erb`.

> Nota: evidência de código morto — não há chamador válido: o único ponto de chamada passa 4
> argumentos para um método que exige 5 (BE-537).

> AMBIGUIDADE: existem permissões de convite no catálogo (`may_invite_users`,
> `max_invitations_amount`) sem nenhum fluxo de convite implementado — ver `auth-users`
> (DB-008).

#### Scenario: Convite de usuário
- **GIVEN** o ai9 em produção
- **WHEN** um operador quer dar acesso a alguém
- **THEN** ele cria o usuário (que recebe link de definição de senha), pois não existe fluxo de convite

### Requirement: FE-533 — Template de mensagem genérica (vivo)

O ai9 SHALL garantir que o template de mensagem genérica é o veículo de **todas** as notificações do módulo de
mensagens. Fonte legada:
`engines/mailer19/app/views/livetat/mailer19/mailing/generic_message.html.erb`.

> Nota: **VIVO** — sustenta as 4 notificações do BE-530 (novo observador, observador removido,
> nova mensagem para observadores e nova resposta).

#### Scenario: Notificação de observador
- **GIVEN** um observador incluído num contexto
- **WHEN** a notificação é enviada
- **THEN** ele recebe a mensagem com a identidade visual do produto e o conteúdo específico do evento

### Requirement: FE-534 — Template de mensagem genérica com ação

O ai9 SHALL garantir que o template com botão de ação existe e é usado apenas por chamadas explícitas. Fonte legada:
`engines/mailer19/app/views/livetat/mailer19/mailing/generic_message_with_link.html.erb`.

> Nota: era o template default dos e-mails de senha, substituído pelos templates próprios do
> produto (BE-522, FE-536, FE-537) — hoje só roda se alguém chamar o método diretamente.

#### Scenario: E-mail com ação
- **GIVEN** uma notificação que precisa de um botão de ação
- **WHEN** ela é enviada
- **THEN** o botão leva ao destino informado, com rótulo explícito

### Requirement: FE-535 — Template de boas-vindas do produto

O ai9 SHALL garantir que o novo usuário recebe um e-mail de boas-vindas com a identidade visual do tema, indicando quem
o cadastrou, o papel concedido e o caminho para acessar o produto. Fonte legada:
`app/views/livetat/mailer19/mailing/send_welcome_email_to_new_generic_user.html.erb` (conteúdo em `:736-771`).

> Nota: corrige D-38 (legado: o corpo traz **cards com e-mail e senha em texto puro**
> (`:751,755`) e o assunto anuncia "Credenciais pra acesso ao ..."). No ai9 o e-mail leva
> **link de definição de senha** e nenhuma credencial (ver `auth-users`, OPS-001).

> Nota: corrige o legado, que carrega a fonte do e-mail por **http://** (`:6`) — conteúdo
> misto num e-mail.

#### Scenario: E-mail de boas-vindas
- **GIVEN** um usuário recém-criado por um operador
- **WHEN** o e-mail é recebido
- **THEN** ele contém um link de definição de senha e **nenhuma** senha em texto

### Requirement: FE-536 — Template de instruções de recuperação de senha

O ai9 SHALL garantir que o e-mail de recuperação leva o link para definir a nova senha, com a identidade visual do tema
do usuário. Fonte legada:
`app/views/livetat/mailer19/mailing/send_email_to_recovery_password_user.html.erb` (conteúdo em `:736-761`).

> Nota: corrige o legado — o título HTML do template diz "Credenciais pra acesso ao ..."
> (`:7`), copiado do template de boas-vindas e nunca corrigido.

> Nota: corrige D-37 — o texto passa a informar o prazo real de validade do link.

#### Scenario: E-mail de recuperação
- **GIVEN** uma solicitação de recuperação
- **WHEN** o e-mail chega
- **THEN** o assunto e o título correspondem ao conteúdo, e o link leva à tela de definição de senha

### Requirement: FE-537 — Template de confirmação de senha alterada

O ai9 SHALL garantir que o e-mail de confirmação avisa que a senha foi alterada e leva ao login. Fonte legada:
`app/views/livetat/mailer19/mailing/send_email_to_reset_password_user.html.erb` (conteúdo em `:736-761`).

> Nota: corrige o legado — mesmo título HTML errado do FE-536.

#### Scenario: Confirmação de troca
- **GIVEN** uma senha trocada com sucesso
- **WHEN** o e-mail chega
- **THEN** ele informa a alteração e oferece o caminho para o login

### Requirement: FE-538 — Biblioteca de componentes e utilitários de interface

O ai9 SHALL garantir que os componentes e utilitários efetivamente usados pelo produto são portados para a biblioteca
de componentes do ai9. Fonte legada:
`engines/ux_kit19/app/frontend/util/js/**` e `util/css/**`; importados em
`app/frontend/pub_gems/js/index.js.erb:10-48` e `pub_gems/css/index.js.erb:5`.

Vivos (13): observador de mudança de campo, detecção de dispositivo, utilitários genéricos
(checagem de vazio, voltar/avançar com segurança), redimensionamento, cookies, extensões de
texto (formatação por template, usada em dezenas de telas) e de coleção, o **agrupador**
(título, ação "ver mais", lista de containers), o **container** com **4 estados**
(pendente/vazio/falha/carregado) e mensagens default, o construtor de estado vazio, os proxies
de carregamento assíncrono (inclusive o cancelável, com `abort()`) e o indicador de
carregamento com dependentes. Do CSS, apenas o de usuário é importado.

Mortos no produto (não portar): construtores de coleção/galeria/tabela, o componente de
scroll, e as folhas de estilo de animações, tabela, botões, agrupador, carregamento e legado,
além do carrossel de terceiro. Os widgets ERB do kit também não têm nenhuma referência no app.

> Nota: corrige o legado — tudo é exposto como **variável global**; no ai9 vira módulo e
> componente com importação explícita.

> Nota (DEC-10): o gráfico e o diálogo proprietários do legado são substituídos pelos
> equivalentes da base ai9, não portados 1:1.

#### Scenario: Estados do container
- **GIVEN** um container de conteúdo assíncrono
- **WHEN** a carga está pendente, retorna vazia, falha ou conclui
- **THEN** cada um dos 4 estados tem apresentação própria, com as mensagens default do produto

#### Scenario: Carregamento cancelável
- **GIVEN** uma busca em andamento
- **WHEN** o usuário dispara outra busca
- **THEN** a anterior é cancelada e não sobrescreve o resultado da nova

### Requirement: FE-539 — Componentes de navegação matricial (mortos)

O ai9 SHALL garantir que os componentes de navegação matricial **não são portados**. Fonte legada:
`engines/navkit/app/frontend/js/**`; `app/frontend/css/**`;
`app/views/livetat/navkit/base/_body.js.erb:1-341`.

O modelo do legado é uma matriz M×N de "holders" (no Safegold 6×1, com centro numa célula
fixa), navegada por gestos e por controles direcionais, com barras superior e inferior geradas
a partir dos itens, **sem nenhuma permissão por item**.

> Nota: corrige D-120 — engine morta (ver ENG-navkit e BE-539). Os itens configurados são de
> **um site de colégio**, resíduo de outro produto. **A navegação do console do produto não
> vem daqui** — vem do NAV-001.

#### Scenario: Navegação do console
- **GIVEN** o ai9 em produção
- **WHEN** o usuário navega pelo console
- **THEN** a navegação é a do NAV-001, com gate por projeto, papel e permissão — nunca uma matriz sem controle de acesso


### Requirement: DB-500 — Tabela de usuários da plataforma

O ai9 SHALL garantir que a tabela de usuários da plataforma é a base da identidade, com índices únicos de e-mail e dos
tokens, e recebe 10 colunas próprias da aplicação. Fonte legada:
`engines/auth19/db/migrate/20160409121830_create_users.rb:3-35`;
`20160409121831_add_attachment_avatar_to_users.rb`; migrations do app.

> Nota: ver `auth-users` (DB-001, DB-002) para o detalhe das colunas, para o D-109
> (`legacy_password`, senha determinística) e para a ambiguidade `is_active` × `deactivated`.

#### Scenario: Estrutura no ai9
- **GIVEN** o schema do ai9
- **WHEN** ele é criado
- **THEN** a identidade do usuário está em uma tabela só, com as colunas da aplicação já integradas e indexadas

### Requirement: DB-501 — Tabela de vínculo usuário ↔ tipo

O ai9 SHALL garantir que a tabela que liga usuário e tipo de usuário mantém a relação 1:1 com o usuário. Fonte legada:
`engines/auth19/db/migrate/20160409121832_create_livetat_roles.rb:3`.

> Nota: ver `auth-users` (DB-005) — no ai9 esta tabela deixa de carregar cópia congelada de
> permissões (D-35).

#### Scenario: Um tipo por usuário
- **GIVEN** um usuário
- **WHEN** seu tipo é consultado
- **THEN** existe exatamente um vínculo ativo

### Requirement: DB-502 — Tabela de tipos de usuário

O ai9 SHALL garantir que a tabela de tipos de usuário guarda o nome e a `hierarchy`, que é **o eixo de autorização de
todo o produto**. Fonte legada:
`engines/auth19/db/migrate/20160409121833_create_livetat_role_types.rb:3`;
`20160409121836_add_hierarchy_column_to_role_type.rb:3`.

> AMBIGUIDADE — lacuna de dados: o **dump desta tabela não existe** (DEC-04). Nomes e
> hierarquias são inferidos de `db/seeds.rb:40-84`. Ver `auth-users` (DB-006).

#### Scenario: Origem dos tipos no ai9
- **GIVEN** um ambiente ai9
- **WHEN** os tipos de usuário são carregados
- **THEN** eles vêm de seed versionado, e qualquer divergência com o banco legado aborta o ETL no dry-run

### Requirement: DB-503 — Tabela de permissões

O ai9 SHALL garantir que a tabela de permissões é polimórfica (aplicável a tipo de usuário ou a usuário) e guarda nome,
valor, natureza (condicional ou limite) e descrição. Fonte legada:
`engines/auth19/db/migrate/20160409121834_create_livetat_ability.rb:3`;
`20160824171513_add_description_column_to_ability.rb:3-4`.

> Nota: corrige o legado, que precisa desligar a herança única de tabela porque a coluna se
> chama `type` sem sê-lo. Ver `auth-users` (DB-007).

#### Scenario: Volume de permissões
- **GIVEN** uma base com muitos usuários
- **WHEN** as permissões são consultadas
- **THEN** o volume da tabela não cresce proporcionalmente ao número de usuários, porque só overrides são persistidos

### Requirement: DB-504 — Tabela de aplicações cliente

O ai9 SHALL garantir que a tabela de aplicações cliente guarda nome, agente e token, mais as colunas próprias da
aplicação. Fonte legada:
`engines/auth19/db/migrate/20160409121835_create_livetat_client_applications.rb:3`.

> Nota: ver `auth-users` (DB-009) — unicidade de agente removida pelo decorator e ausência de
> CRUD.

#### Scenario: Identificação da aplicação
- **GIVEN** um par agente/token
- **WHEN** ele é apresentado
- **THEN** ele identifica no máximo uma aplicação cliente

### Requirement: DB-505 — Tabela de perfil estendido

O ai9 SHALL garantir que a tabela de perfil estendido evoluiu em 5 migrations; os telefones foram decompostos em país,
DDD e número, e o nível de confiabilidade tem default "Baixa". Fonte legada:
`engines/auth19/db/migrate/20171020133117_create_livetat_user_infos.rb:3` e as migrations
`20171201171447`, `20171201171448`, `20171204213707`, `20171206031439`, `20171213170127`.

> Nota: o default do código de país mudou de `"+55"` para `"55"` ao longo da história — o ETL
> precisa normalizar os dois formatos.

#### Scenario: Normalização de telefone na migração
- **GIVEN** registros legados com código de país gravado como `"+55"` e como `"55"`
- **WHEN** o ETL roda
- **THEN** ambos chegam ao ai9 no mesmo formato

### Requirement: DB-506 — Tabela de vínculos sociais

O ai9 SHALL garantir que a tabela de vínculos com provedor social **provavelmente está vazia** e só é migrada se
contiver dados. Fonte legada:
`engines/auth_omni19/db/migrate/20170722163911_create_livetat_auth_omni_providers.rb:3`;
`20170722164423_add_index_to_provider.rb:3`.

> Nota: evidência — o login social nunca funcionou (ver ENG-auth_omni19). Ver `auth-users`
> (DB-010) para o defeito do índice único, que inclui o usuário e permite o mesmo `uid` em
> contas diferentes.

#### Scenario: Contagem antes do descarte
- **GIVEN** a tabela no banco legado
- **WHEN** o ETL roda o dry-run
- **THEN** a contagem de linhas é reportada, e o descarte só é confirmado se ela for zero

### Requirement: DB-507 — A engine de UX de auth não cria tabelas

O ai9 SHALL garantir que a camada de UX de autenticação **não tem esquema próprio**: reusa as tabelas da engine de
identidade. Fonte legada: `engines/auth_ux19/lib/livetat/auth_ux19.rb:11-13`.

#### Scenario: Esquema de autenticação
- **GIVEN** o schema do ai9
- **WHEN** ele é inspecionado
- **THEN** as tabelas de identidade existem uma única vez, sem duplicação por camada

### Requirement: DB-508 — Tabela de mensagens

O ai9 SHALL garantir que a tabela de mensagens guarda remetente, texto, situação, contexto, marcação de interna, os
dois campos extras (rótulo, valor e habilitação) e os tokens público e privado. Fonte legada:
`engines/feedback19/db/migrate/20160826200511_create_feedback_messages.rb:3` e 6 migrations de evolução.

> Nota: os nomes de coluna dos campos extras são as piadas internas citadas no BE-526 e são
> **renomeados** no ai9, com mapeamento explícito no ETL. A coluna `tag`, substituída por
> eles, é histórico morto.

#### Scenario: Migração dos campos extras
- **GIVEN** mensagens legadas com valores nos campos extras
- **WHEN** o ETL roda
- **THEN** os valores chegam nas colunas renomeadas, sem perda

### Requirement: DB-509 — Tabela de situações da mensagem

O ai9 SHALL garantir que as 8 situações da mensagem são dados de referência obrigatórios no legado. Fonte legada:
`engines/feedback19/db/migrate/20170505143940_create_livetat_feedback_states.rb:3`;
seed em `engines/feedback19/db/seeds.rb`.

> Nota: corrige o legado — **sem essas linhas o boot da aplicação quebra**, porque as
> situações são resolvidas em variáveis de classe no carregamento (BE-527). No ai9 são
> enumeração em código.

#### Scenario: Ambiente sem dados de referência
- **GIVEN** um ambiente ai9 sem nenhum dado carregado
- **WHEN** a aplicação sobe
- **THEN** ela sobe normalmente

### Requirement: DB-510 — Tabela de contextos da mensagem

O ai9 SHALL garantir que os 4 contextos (Outros, Problema, Contato, Sugestão) são dados de referência. Fonte legada:
`engines/feedback19/db/migrate/20170505214502_create_livetat_feedback_contexts.rb:3`.

> Nota: mesma correção do DB-509 — no ai9 os contextos são configuração versionada, não
> dependência de boot.

#### Scenario: Contexto de uma mensagem
- **GIVEN** uma mensagem sem contexto informado
- **WHEN** ela é criada
- **THEN** recebe o contexto default "Outros"

### Requirement: DB-511 — Tabela de observadores

O ai9 SHALL garantir que a tabela de observadores guarda o usuário responsável, o título, o e-mail único, as marcações
de interno e externo e quem alterou por último. Fonte legada:
`engines/feedback19/db/migrate/20170505211325_create_livetat_feedback_observers.rb:3`.

#### Scenario: E-mail duplicado
- **GIVEN** um observador já cadastrado com um e-mail
- **WHEN** outro é cadastrado com o mesmo e-mail
- **THEN** a gravação é recusada

### Requirement: DB-512 — Tabela de vínculo observador ↔ contexto

O ai9 SHALL garantir que a tabela de junção liga observadores aos contextos que eles acompanham. Fonte legada:
`engines/feedback19/db/migrate/20170505225555_create_livetat_feedback_observer_contexts.rb:3`.

#### Scenario: Vínculo único
- **GIVEN** um observador já vinculado a um contexto
- **WHEN** o mesmo par é gravado de novo
- **THEN** a gravação é recusada

### Requirement: DB-513 — Tabela de notas (thread de respostas)

O ai9 SHALL garantir que a tabela de notas guarda o texto, o autor (identificador, nome e e-mail), a mensagem de
origem, a citação, a raiz da cadeia de citação e o indicador de não lida. Fonte legada:
`engines/feedback19/db/migrate/20170516185759_create_livetat_feedback_notes.rb:3`;
`20181005020904_add_unread_to_note.rb:3`.

> Nota: o autor é desnormalizado (nome e e-mail copiados) para suportar remetente anônimo —
> comportamento a preservar.

#### Scenario: Nota de remetente anônimo
- **GIVEN** uma resposta enviada sem usuário autenticado
- **WHEN** ela é gravada
- **THEN** o nome e o e-mail vêm da própria mensagem de origem

### Requirement: DB-514 — Registro de e-mails enviados

O ai9 SHALL garantir que o sistema registra cada e-mail enviado com remetente, destinatário, nome do destinatário,
assunto e conteúdo. Fonte legada:
`engines/mailer19/db/migrate/20160409121840_create_livetat_mailer_contacts.rb:3`;
`20170519223014` e `20170519223026`.

> AMBIGUIDADE: a tabela **cresce indefinidamente, sem política de expurgo**, e o volume real
> não foi levantado. Sem decisão sobre retenção — e o conteúdo inclui corpos de e-mail, que
> hoje contêm senhas em texto puro (D-38), o que torna a retenção um problema de segurança
> além de volume.

#### Scenario: Migração do log de envios
- **GIVEN** o log de envios do legado, que contém corpos com credenciais
- **WHEN** o ETL avalia a migração
- **THEN** o volume é reportado e nenhum corpo com credencial é copiado para o ai9

### Requirement: DB-515 — Tabela da fila de jobs

O ai9 SHALL garantir que a fila de processamento assíncrono é infraestrutura da aplicação, não de e-mail. Fonte legada:
`engines/mailer19/db/migrate/20170505110720_create_mailer_delayed_jobs.rb:4-17`;
`20170505114146_add_progress_to_mailer_delayed_jobs.rb`.

> Nota: corrige o legado — a fila é criada **pela engine de e-mail** e com `force: true` (o
> que apaga a tabela existente), embora o app use a mesma fila para outros jobs. No ai9 a fila
> é infraestrutura declarada uma vez, sem `force`.

> Nota (DEC-11): a produção usa um **fork** da biblioteca de fila
> (`github.com/livetat/delayed_job`, branch `rails-6-compatibility`) — o comportamento de
> retry/falha pode divergir do inventariado.

#### Scenario: Criação do schema
- **GIVEN** um ambiente ai9 sendo provisionado
- **WHEN** o schema é criado
- **THEN** nenhuma migration apaga uma tabela existente

### Requirement: DB-516 — Kit de UI e navegação matricial não têm esquema

O ai9 SHALL garantir que nem o kit de interface nem a engine de navegação matricial criam tabelas. Fonte legada:
`engines/ux_kit19/**`; `engines/navkit/**` (sem migrations).

#### Scenario: Descarte sem impacto de dados
- **GIVEN** o descarte da engine de navegação matricial (ENG-navkit)
- **WHEN** o ETL é planejado
- **THEN** não há nenhum dado a migrar por conta dela


### Requirement: OPS-500 — Configuração do servidor de e-mail

O ai9 SHALL garantir que os parâmetros do servidor de e-mail vêm do ambiente e valem para toda a aplicação. Fonte
legada: `engines/mailer19/lib/livetat/mailer19/engine.rb:33-52`; `config/application.rb:101-108`.

> Nota: corrige o legado — a verificação do certificado do servidor é desligada
> (`VERIFY_NONE`) e os erros de entrega são suprimidos, o que esconde falhas (ver BE-533).

#### Scenario: Certificado do servidor
- **GIVEN** um servidor de e-mail com certificado inválido
- **WHEN** o envio é tentado
- **THEN** a conexão é recusada e a falha é registrada

### Requirement: OPS-501 — Assinatura criptográfica dos e-mails

O ai9 SHALL garantir que os e-mails do produto são assinados com a chave do domínio. Fonte legada:
`config/application.rb:110-114`; chave em `lib/dkim_private_key.pem`.

> Nota: corrige um risco grave do legado — a **chave privada está versionada no
> repositório**. No ai9 ela é segredo de ambiente, e a chave atual deve ser **rotacionada**
> no cutover, com o registro de DNS atualizado.

#### Scenario: Chave de assinatura
- **GIVEN** o repositório do ai9
- **WHEN** ele é inspecionado
- **THEN** nenhuma chave privada está versionada

#### Scenario: E-mail assinado
- **GIVEN** um e-mail enviado pelo produto
- **WHEN** o destinatário o valida
- **THEN** a assinatura confere com o registro de DNS do domínio

### Requirement: OPS-502 — Processamento assíncrono de e-mails e jobs

O ai9 SHALL garantir que o envio de e-mail e os jobs do produto são processados por um worker separado, com retry e
falha visível. Fonte legada:
`engines/mailer19/lib/livetat/mailer19/delayed_job:1-4`; `bin/delayed_job`;
`config/initializers/delayed_job_config.rb:1-2`.

> Nota: corrige o legado — os jobs falhos **não são descartados nem reprocessados**
> (`destroy_failed_jobs = false`, sem retry configurado), acumulando na tabela; e o processo
> do worker **não está declarado** no arquivo de processos da aplicação, que só declara o
> servidor e os assets.

#### Scenario: Worker declarado
- **GIVEN** o ai9 sendo implantado
- **WHEN** os processos são iniciados
- **THEN** o worker de background está declarado junto com os demais processos

#### Scenario: Job com falha
- **GIVEN** um job que falha
- **WHEN** o worker o processa
- **THEN** há retry com política definida e, esgotada, a falha fica visível para operação

### Requirement: OPS-503 — Instalação do runner do worker

O ai9 SHALL garantir que a tarefa de instalação do runner do worker **não é portada**. Fonte legada:
`engines/mailer19/lib/tasks/livetat/mailer_tasks.rake:1-9`.

> Nota: evidência de código morto — o caminho de origem da tarefa está **errado** (aponta para
> um diretório sem o sufixo de versão da engine), então ela falharia se executada; o binário
> já está versionado no app.

#### Scenario: Provisionamento do worker
- **GIVEN** um ambiente ai9 novo
- **WHEN** ele é provisionado
- **THEN** o worker é iniciado pela declaração de processos, sem tarefa de cópia de arquivo

### Requirement: OPS-504 — Recursos visuais dos e-mails lidos do sistema de arquivos

O ai9 SHALL garantir que os logos embutidos nos e-mails são obtidos de forma resiliente. Fonte legada:
`engines/mailer19/lib/livetat/mailer19/engine.rb:33-36`; `config/application.rb:95`;
`app/decorators/models/mailer_decorator.rb:9-11,23-25,38-40`.

> Nota: corrige o legado — os arquivos são lidos direto do disco do servidor de aplicação
> (inclusive os logos do tema, gerenciados por anexo), sem tratamento de erro: **arquivo
> ausente derruba o envio** (ver BE-535).

#### Scenario: Logo do tema indisponível
- **GIVEN** um tema cujo logo não está acessível
- **WHEN** um e-mail temático é enviado
- **THEN** ele é enviado com a identidade padrão e a ausência é registrada

### Requirement: OPS-505 — Armazenamento de avatares

O ai9 SHALL garantir que os avatares são guardados em armazenamento de objetos, não no disco do servidor de aplicação.
Fonte legada: `engines/auth19/app/models/livetat/auth/user.rb:4-6`.

> Nota: corrige o legado — armazenamento **local** em `public/system/avatars/`, servido
> publicamente, exigindo volume persistente no servidor de aplicação (ver D-56 e BE-503).

> Nota: o processamento de imagem do legado depende de um binário externo instalado no
> servidor; no ai9 essa dependência é explícita na infraestrutura.

#### Scenario: Servidor de aplicação sem volume persistente
- **GIVEN** uma instância nova da aplicação
- **WHEN** um avatar já existente é solicitado
- **THEN** ele é servido normalmente, porque não depende do disco daquela instância

### Requirement: OPS-506 — Detecção de tipo real de mídia

O ai9 SHALL garantir que a verificação do tipo real dos arquivos enviados está **ativa**. Fonte legada:
`engines/auth19/config/initializers/paperclip.rb:1-8`.

> Nota: corrige D-56 (legado: um `monkey-patch` faz a detecção de spoof retornar sempre
> `false`, desligando a verificação **no app inteiro** — qualquer arquivo podia se passar por
> imagem e ficar acessível publicamente, inclusive com risco de execução se o servidor
> interpretasse o tipo).

#### Scenario: Arquivo com tipo falsificado
- **GIVEN** um arquivo cujo conteúdo não corresponde à extensão declarada
- **WHEN** o upload é tentado em qualquer ponto do produto
- **THEN** ele é recusado

### Requirement: OPS-507 — Dados de referência das engines

O ai9 SHALL garantir que os dados de referência (tipos de usuário, permissões, situações e contextos de mensagem) são
configuração versionada e idempotente. Fonte legada:
`engines/auth19/db/seeds.rb`; `engines/feedback19/db/seeds.rb`; `db/seeds.rb:35-84,342-350`.

> Nota: corrige o legado — **a ordem importa e é frágil**: as situações e contextos são
> resolvidos em variáveis de classe no carregamento, então sem o seed o boot quebra; e o seed
> do app **destrói** os tipos criados pela engine para recriá-los com outros nomes (ver D-36 e
> `auth-users`, OPS-009).

> Nota: o backfill de mensagens antigas (situação "Fechado", contexto "Outros") é operação de
> migração de dados, não de seed — no ai9 fica no ETL, com relatório.

#### Scenario: Ambiente novo
- **GIVEN** um ambiente ai9 sem dados
- **WHEN** a aplicação sobe e os dados de referência são carregados
- **THEN** o resultado é o mesmo independentemente da ordem de execução, e nada é destruído

### Requirement: OPS-508 — Build de assets acoplado às gems das engines

O ai9 SHALL garantir que o build de assets do ai9 **não depende** de resolver caminhos de gems em tempo de compilação.
Fonte legada: `app/frontend/pub_gems/js/index.js.erb:8`; `app/frontend/site_gems/js/index.js.erb:8,52`;
`app/frontend/packs/*.js.erb`.

> Nota: corrige o legado — o build resolve o caminho físico das gems (`full_gem_path`) e
> importa arquivos de dentro delas, criando **acoplamento build ↔ gerenciador de dependências**:
> remover a dependência da navegação matricial sem remover o pack correspondente **quebra o
> build** (ver ENG-navkit).

#### Scenario: Remoção de uma dependência morta
- **GIVEN** o descarte da engine de navegação matricial
- **WHEN** o build do ai9 roda
- **THEN** ele conclui normalmente, sem referência a caminhos de gems

### Requirement: OPS-509 — Carregamento de extensões de classe com erro silencioso

O ai9 SHALL garantir que as extensões de comportamento carregam de forma explícita, e qualquer falha de carregamento
**falha o boot**. Fonte legada: `config/application.rb:39-55` e o bloco equivalente em cada
engine (`auth19:17-25`, `auth_omni19:21-29`, `auth_ux19:23-31`, `feedback19:25-33`,
`mailer19:23-31`, `ux_kit19:6-14`, `navkit:7-15`).

> Nota: corrige o **risco mais alto de perda silenciosa de comportamento na migração**: o
> legado varre um padrão de arquivos e carrega cada um capturando exceções, transformando o
> erro numa mensagem impressa ("Não conseguiu definir os decorators na engine ..."). Somado ao
> carregador de classes clássico, isso significa que um decorator pode simplesmente **não ter
> sido aplicado** em produção sem ninguém saber.

> Nota: é a mesma classe de erro que faz a engine de navegação matricial não carregar
> silenciosamente (ENG-navkit).

#### Scenario: Extensão que não carrega
- **GIVEN** uma extensão de comportamento com erro de sintaxe ou dependência ausente
- **WHEN** a aplicação sobe
- **THEN** o boot falha com o erro original, em vez de continuar sem aquele comportamento

#### Scenario: Auditoria das extensões do legado
- **GIVEN** o conjunto de decorators do legado
- **WHEN** a migração é planejada
- **THEN** cada um é verificado quanto a ter efeito real em produção, antes de ser portado

### Requirement: OPS-749 — O bootstrap das engines desaparece

O ai9 SHALL absorver como código de primeira classe tudo o que hoje é bootstrap das seis engines
`livetat` (`auth19`, `auth_omni19`, `auth_ux19`, `ux_kit19`, `feedback19`, `mailer19`) — entrypoints
`lib/livetat_*.rb`, `isolate_namespace`, `paths["app/views"]`, injeção das migrations da engine no app,
prefixo de tabela e carga de decorators no `to_prepare` — e **MUST NOT** reproduzir nenhum dos quatro
acoplamentos abaixo. Fonte legada: `engines/auth19/lib/livetat/auth/engine.rb:1-31`;
`engines/auth_omni19/lib/livetat/auth_omni19/engine.rb`;
`engines/ux_kit19/lib/livetat/ux_kit19/engine.rb`; entrypoints `engines/auth19/lib/livetat_auth.rb`,
`engines/auth_omni19/lib/livetat_auth_omni19.rb`, `engines/auth_ux19/lib/livetat_auth_ux19.rb`,
`engines/ux_kit19/lib/livetat_ux_kit19.rb`, `engines/feedback19/lib/livetat_feedback19.rb`,
`engines/mailer19/lib/livetat_mailer19.rb`; namespaces `engines/auth19/lib/livetat/auth.rb:1-17` e
equivalentes; prefixo de tabela em `engines/auth19/app/models/livetat/auth.rb:1-4`.

- **(a) Migrations injetadas no boot.** O initializer `:append_migrations` copia
  `config.paths["db/migrate"]` de cada engine para o app — é por isso que as migrations das engines
  **não existem em `db/migrate`** e o histórico do banco depende da **ordem de montagem** das engines.
  No ai9 as migrations **MUST** viver todas no repositório da aplicação, em ordem determinística (ver
  DB-599 e OPS-549).
- **(b) Decorators carregados com erro engolido.** `config.to_prepare` faz `Dir.glob` dos
  `*_decorator*.rb` e captura qualquer exceção, imprimindo
  "Não conseguiu definir os decorators na engine auth: …". **Falha de decorator é silenciosa em
  produção.** No ai9 falha de carregamento **MUST** falhar o boot (ver OPS-509).
- **(c) Prefixo de tabela.** `Livetat::Auth.table_name_prefix = 'livetat_auth_'` é o que dá nome a todas
  as tabelas `livetat_auth_*`. No ai9 os nomes de tabela **MUST** ser declarados explicitamente, sem
  prefixo derivado de namespace de engine.
- **(d) Dependências escondidas no namespace.** `engines/auth19/lib/livetat/auth.rb` é quem exige
  `devise`, `simple_token_authentication`, `validates_email_format_of`, `cpf_cnpj`, `phone`,
  `iso_country_codes` e `kt-paperclip` — dependências do produto declaradas dentro de uma engine. No ai9
  elas **MUST** ser declaradas (ou substituídas) no manifesto da própria aplicação.
- O ai9 é um monolito Rails 8 em modo API: **não haverá engines**.

> Nota: corrige D-120 e a classe de erro de OPS-509 (legado: carregamento de extensões com exceção
> engolida, o que permite um decorator não ter sido aplicado em produção sem ninguém saber).

#### Scenario: origem de uma tabela do esquema
- **GIVEN** uma tabela hoje criada por migration de engine
- **WHEN** o esquema do ai9 é reconstruído
- **THEN** a migration correspondente está no repositório da aplicação, e o resultado independe de ordem de montagem de dependências

#### Scenario: extensão de comportamento que não carrega
- **GIVEN** um arquivo de extensão com erro de sintaxe ou dependência ausente
- **WHEN** a aplicação sobe
- **THEN** o boot falha com o erro original, em vez de imprimir uma mensagem e continuar sem aquele comportamento

#### Scenario: dependências do produto declaradas onde se lê
- **GIVEN** o manifesto de dependências do ai9
- **WHEN** ele é lido
- **THEN** toda dependência de runtime do produto está nele, e nenhuma entra transitivamente por um pacote de engine
