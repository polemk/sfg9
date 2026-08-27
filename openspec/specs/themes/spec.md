# Themes Specification

## Purpose
Tema visual e marca do produto: catalogo de temas (STI `AppTheme` / `GlobalTheme` / `UserTheme`), tema padrao global, tema por usuario, logos, cores, fontes e CSS customizado, mais o pipeline de imagem dos anexos.

> Nota de escopo (DEC-09 / DEC-10): no legado o motor de temas **nao pinta nada** (D-55) — o `app_theme_template.css` esta 100% comentado e o `cached_css` injetado e so comentario. No ai9 o tema e **real**, implementado por tokens CSS light+dark; o dark mode nao existe no legado (`AppTheme.styles` tem "Escuro" comentado) e por isso e desenho novo derivado da marca Safegold, nao paridade. `cached_css` **nao e portado** — e cache derivado.
> Nota de escopo (DEC-09): nao ha tema por projeto no legado e nao se inventa um. i18n fica fora (D-115): pt-BR fixo.

## Requirements

### Requirement: BE-370 — Listar e buscar temas
O sistema SHALL listar os temas cadastrados com filtro, ordenacao e paginacao **funcionando**. Fonte legada: `app/controllers/pub/app_themes_controller.rb:14-18`, `fetch_loq` `:87-95`; rota `config/routes.rb:33`.

> Nota: corrige D-20 nesta capability (legado: `search_themes` normaliza `q`/`l`/`o` em `fetch_loq` e depois faz `AppTheme.all` cru — sem filtro, sem ordenacao, sem paginacao; o campo de busca do front esta comentado em `themes/_body.html.erb:6-9` e o `limit` de 50 nunca e aplicado).

#### Scenario: Busca por titulo com paginacao
- **GIVEN** existem 120 temas cadastrados e o operador esta autenticado como admin
- **WHEN** ele busca por `q=padrao` com `l=50` e `o=0`
- **THEN** a resposta traz apenas os temas cujo titulo casa com o termo, no maximo 50 itens, e o total informado e o total **filtrado**, nao o da pagina

#### Scenario: Lista mistura tipos de tema
- **GIVEN** existem temas do tipo `GlobalTheme` e do tipo `UserTheme`
- **WHEN** o operador abre a lista sem filtro de tipo
- **THEN** os dois tipos aparecem, cada um rotulado com seu tipo ("Tema global" / "Tema do usuario")

### Requirement: BE-371 — Criar tema
O sistema SHALL criar um tema com titulo unico, tipo, cores, estilo, fontes, textos de apresentacao e anexos de imagem. Fonte legada: `app/controllers/pub/app_themes_controller.rb:36-46`, permit `:125-148`, defaults `app/models/app_theme.rb:193-203`.

> Nota: corrige D-60 (legado: `:id` esta no `permit` de `app_theme_params` — mass assignment da propria chave primaria) e D-56/D-82 (legado: content-type validado so por `image/*` com o spoof detector do Paperclip monkey-patchado para `false`).

#### Scenario: Criacao com defaults
- **GIVEN** um admin autenticado
- **WHEN** ele cria um tema informando apenas titulo e tipo `GlobalTheme`
- **THEN** o tema e criado com `style = Light`, `login_bkg_style = Default`, `font_name` e `bar_font_name` = `Baloo Thambi 2`, as quatro cores em `#444444` e `is_default` falso

#### Scenario: Titulo duplicado
- **GIVEN** ja existe um tema com titulo "Tema padrao"
- **WHEN** o operador tenta criar outro com o mesmo titulo
- **THEN** a criacao e rejeitada com erro de unicidade no campo titulo (unicidade e **global**, nao por tipo)

#### Scenario: Tentativa de forjar o id
- **GIVEN** um payload de criacao contendo `id`
- **WHEN** a requisicao e processada
- **THEN** o campo `id` e ignorado e o tema recebe um identificador gerado pelo servidor

#### Scenario: Upload de arquivo que se passa por imagem
- **GIVEN** um arquivo cujo nome e content-type declaram `image/png` mas cujo conteudo real nao e imagem
- **WHEN** o operador o envia como logo
- **THEN** o upload e rejeitado por validacao de magic bytes no servidor e nada e gravado

### Requirement: BE-372 — Editar tema
O sistema SHALL atualizar um tema existente pelos mesmos campos da criacao. Fonte legada: `app/controllers/pub/app_themes_controller.rb:59-70`, `fetch_theme` `:116-118`.

> Nota: corrige D-61 (segundo caminho) — por DEC-11 producao roda Ruby 2.6.1 / Rails 6.0.3.2, entao o caminho `update_attributes` **funciona** e e feature a preservar; o segundo caminho, o save flutuante que faz `POST /app_themes/{id}` (rota inexistente) com a chave malformada `app_theme[app_theme[login_bkg_style]]`, continua quebrado e **nao e portado**: no ai9 existe uma unica rota de edicao e a chave e bem formada.

#### Scenario: Edicao salva todos os campos, inclusive o estilo de fundo
- **GIVEN** um tema existente com `login_bkg_style = Default`
- **WHEN** o operador muda para `Color`, escolhe `login_bkg_color` e salva
- **THEN** os dois campos persistem e a tela recarregada mostra o valor novo

#### Scenario: Edicao rejeitada
- **GIVEN** um tema existente
- **WHEN** o operador salva com titulo em branco
- **THEN** a resposta e 422, o tema nao muda e o erro e exibido no campo titulo

### Requirement: BE-373 — Excluir tema
O sistema SHALL excluir um tema, protegendo o tema padrao e sem deixar usuarios orfaos. Fonte legada: `app/controllers/pub/app_themes_controller.rb:72-84`; guarda no model `app/models/app_theme.rb:66-70`.

> Nota: corrige D-59 (legado: excluir um tema em uso deixa `livetat_auth_users.app_theme_id` orfao — nao ha `dependent:` e `belongs_to_required_by_default = false` — e o console quebra em `current_user.app_theme.cached_css`, `pub/console/base/_container.html.erb:28`, com `NoMethodError`) e o vazamento de arquivos Paperclip em `public/system/`, que o legado nunca removia.

#### Scenario: Tema padrao nao pode ser excluido
- **GIVEN** o tema marcado como padrao
- **WHEN** o operador tenta exclui-lo
- **THEN** a operacao e recusada com a mensagem "Nao e possivel remover o tema padrao" e nada e apagado

#### Scenario: Tema em uso por usuarios
- **GIVEN** um tema nao-padrao referenciado por 12 usuarios
- **WHEN** o operador confirma a exclusao
- **THEN** a confirmacao informa quantos usuarios serao afetados, e apos a exclusao esses usuarios passam a apontar para o tema padrao — nenhum deles fica sem tema e o console continua abrindo

#### Scenario: Anexos removidos junto
- **GIVEN** um tema com logo, simbolo, texto e papel de parede anexados
- **WHEN** o tema e excluido
- **THEN** os quatro arquivos e suas derivadas sao removidos do storage

### Requirement: BE-374 — Ativar tema (tornar padrao)
O sistema SHALL promover um tema a padrao global de forma atomica, garantindo exatamente um padrao. Fonte legada: `config/routes.rb:35`; `app/controllers/pub/app_themes_controller.rb:48-57`; `AppTheme#default!` `app/models/app_theme.rb:184-191`.

> Nota: corrige D-59 (legado: `default!` busca o padrao atual com `GlobalTheme.where(is_default: 1).first` — se o padrao for um `UserTheme` ou nao existir nenhum, da `NoMethodError`/500; se for `UserTheme` ele **continua** com `is_default = 1` e passam a existir **dois padroes**; os dois `save` nao estao em transacao, entao uma falha no meio deixa o sistema **sem** padrao) e D-57 (legado: `POST /app_themes/:id/active` responde sem sessao).

#### Scenario: Promocao troca o padrao atomicamente
- **GIVEN** o tema A e o padrao e o tema B nao e
- **WHEN** um admin promove o tema B
- **THEN** ao final da operacao B e o unico padrao e A deixa de ser — em uma unica transacao, e uma falha no meio nao deixa nem zero nem dois padroes

#### Scenario: Ativar nao muda o tema de quem ja tem um
- **GIVEN** usuarios com tema proprio atribuido
- **WHEN** o padrao global muda
- **THEN** o tema desses usuarios permanece o mesmo; o padrao novo vale para quem nao tem tema proprio e para novos cadastros

#### Scenario: Promocao exige papel de admin
- **GIVEN** uma requisicao sem sessao ou de usuario sem papel de admin
- **WHEN** ela chama a promocao de tema
- **THEN** a resposta e 401/403 e nenhum tema muda

### Requirement: BE-375 — Telas de tema pelas rotas REST (index, show, new, edit)
O sistema SHALL expor listagem, detalhe e formularios de tema por rotas proprias e funcionais. Fonte legada: `app/controllers/pub/app_themes_controller.rb:6-8,10-12,20-27,29-34`.

> Nota: corrige D-62 (legado: `index` e `show` renderizam templates que **nao existem** — so ha o parcial `_body.html.erb` — resultando em 500; `new`/`edit` renderizam `themes/helper/body` passando `locals: { theme: ... }` enquanto o parcial usa `app_theme`, resultando em `NameError`; alem disso `new`/`edit` carregavam **todos** os usuarios em memoria com `Livetat::Auth::User.order(formal: :asc).select{...}` para um `@users` que nenhum template usa).

#### Scenario: Detalhe de tema abre
- **GIVEN** um tema existente
- **WHEN** o operador abre a rota de detalhe desse tema
- **THEN** a tela renderiza titulo, tipo e cores, sem erro de template

#### Scenario: Formulario de edicao abre com o tema carregado
- **GIVEN** um tema existente
- **WHEN** o operador abre o formulario de edicao
- **THEN** os campos vem preenchidos com os valores atuais do tema e nenhuma consulta carrega a lista inteira de usuarios

### Requirement: BE-376 — Navegacao e deep-link da area de temas
A area de temas SHALL ter rota propria, entrada de navegacao visivel e deep-link com historico. Fonte legada: `config/routes.rb:45`; `app/controllers/pub/console_controller.rb:51-62`; menu em `app/helpers/application_helper.rb:100-172`.

> Nota: corrige D-92 e D-63 (legado: `themes` nao tem `when` no `fetch_resource`, o `else` reescreve `@resource[:id] = "dash"` e nao ha item de menu apontando para a area; o estado de navegacao vive so em memoria JS com a URL espelhada por `replaceState`). No ai9 a navegacao usa **roteador real com historico e deep-link por area**; o esquema `resource/topic/section` do legado **nao e reproduzido**.

#### Scenario: Deep-link direto para um tema
- **GIVEN** a URL de um tema especifico
- **WHEN** o operador a abre em uma aba nova
- **THEN** a tela do tema carrega diretamente, sem passar por dash e sem reescrever a URL

#### Scenario: Botao Voltar do navegador
- **GIVEN** o operador navegou da lista de temas para o detalhe de um tema
- **WHEN** ele aciona o botao Voltar
- **THEN** ele retorna a lista de temas, e nao para fora da area administrativa

> AMBIGUIDADE: D-63 — nao ha confirmacao em runtime de que `/u/console/themes` era alcancavel em producao (sem item de menu e com o `else` do `fetch_resource` redirecionando para `dash`). Se a tela estava morta, confirmar com o tech lead se a area de temas deve existir no ai9 ou se a marca e congelada em configuracao.

### Requirement: BE-377 — Geracao do CSS do tema
O sistema SHALL derivar do tema um conjunto de tokens CSS aplicados as telas autenticadas e as telas publicas de sessao. Fonte legada: `app/models/app_theme.rb:205-232`; template `app/frontend/css/pub/templates/app_theme_template.css`; injecao em `pub/console/base/_container.html.erb:28`, `pub/base/nav/sign_in/_sign_in.html.erb:55`, `pub/base/nav/sign_up/_sign_up.html.erb:68`, `livetat/auth_ux19/users/passwords/reset.html.erb:85`.

> Nota: corrige D-55 (legado: substituicao textual de placeholders num `.css` lido do disco a cada `before_validation`, com o mapeamento **invertido** `$accent_aux -> second_color`, `$accent_inverse -> primary_color`, `$accent -> accent_color`, gravado em `cached_css`; o console lia o cache e a tela de reset recomputava a cada request). No ai9 o CSS e gerado a partir de **tokens** em runtime, sem coluna de cache e sem leitura de arquivo do disco por requisicao.

#### Scenario: Cores do tema chegam a tela
- **GIVEN** um tema com `primary_color`, `second_color` e `accent_color` definidos
- **WHEN** um usuario com esse tema abre o console
- **THEN** os elementos da interface usam efetivamente essas cores, e nao as cores estaticas do SCSS

#### Scenario: Telas publicas de sessao
- **GIVEN** o tema padrao global
- **WHEN** um anonimo abre login, cadastro ou redefinicao de senha
- **THEN** as tres telas usam os tokens do tema padrao, sem recomputar o CSS a cada requisicao

### Requirement: BE-378 — CSS customizado do tema (`override_css`)
O sistema SHALL aceitar CSS customizado por tema e SHALL aplica-lo a interface, restrito a papel administrativo. Fonte legada: `app/controllers/pub/app_themes_controller.rb:144`; `app/models/app_theme.rb:156-162`; gate de view em `themes/form/_body.html.erb:327` e `themes/helper/_body.html.erb:169`.

> Nota: corrige D-55 em cascata (legado: `override_css` era aceito, validado e persistido mas **nunca renderizado** — so `cached_css` chegava ao HTML; `font_name`/`bar_font_name` eram coletados e nenhum template os consumia; `login_bkg_style`/`login_bkg_color`/`login_bkg_image` alimentavam `background_login`, usado apenas dentro do bloco comentado `.background_overlay`, enquanto a tela de login usava uma imagem estatica; `black_bar_font?`/`black_font?` liam as colunas fantasma `is_black_bar_font`/`is_black_font`, que nao existem em migration alguma).

#### Scenario: CSS customizado tem efeito
- **GIVEN** um tema com `override_css` definido
- **WHEN** um usuario com esse tema abre a interface
- **THEN** as regras do CSS customizado sao aplicadas depois dos tokens do tema

#### Scenario: Gate por papel e consistente
- **GIVEN** um usuario sem papel administrativo
- **WHEN** ele abre qualquer tela de edicao de tema
- **THEN** o campo de CSS customizado nao aparece em **nenhuma** delas e o servidor rejeita o campo se enviado — sem a divergencia do legado, em que uma tela liberava para `og?/admin?/manager?` e a outra so para `og?`

#### Scenario: Fontes do tema sao aplicadas
- **GIVEN** um tema com `font_name` e `bar_font_name` diferentes do default
- **WHEN** a interface e renderizada
- **THEN** o corpo e a barra usam as fontes configuradas

### Requirement: BE-379 — Tipos de tema (global e por usuario)
O sistema SHALL distinguir tema global de tema de usuario, e ambos sao criaveis pela interface. Fonte legada: `app/models/app_theme.rb:1`; `app/models/global_theme.rb`; `app/models/user_theme.rb`; form `themes/form/_body.html.erb:36`.

#### Scenario: Tipo e obrigatorio e rotulado
- **GIVEN** o formulario de tema
- **WHEN** o operador salva sem escolher o tipo
- **THEN** a operacao e rejeitada; com tipo escolhido, a lista e o detalhe exibem "Tema global" ou "Tema do usuario"

#### Scenario: Tipo desconhecido
- **GIVEN** uma requisicao com um tipo fora do conjunto conhecido (por exemplo `OfficeTheme`, residuo que o JS do legado ainda tratava em `form/_body.js.erb:67-76`)
- **WHEN** ela e processada
- **THEN** a resposta e 422 com erro de validacao, e nunca um erro de carga de classe

> AMBIGUIDADE: no legado o `select` do formulario oferece **apenas** `GlobalTheme`, entao `UserTheme` existe no codigo, tem `has_many :users` e coluna, mas e **inalcancavel pela UI**. Confirmar com o tech lead se "tema por usuario" era requisito abandonado (e some do ai9) ou feature a ressuscitar.

### Requirement: BE-380 — Precedencia e atribuicao de tema
O tema efetivo de um usuario SHALL seguir a ordem: tema do usuario, tema padrao global, constantes de marca. Fonte legada: `app/models/app_theme.rb:137-139`; `app/decorators/models/user_decorator.rb:7,38,48,76-80`; `app/decorators/controllers/registrations_decorator.rb:26`; `app/controllers/pub/start_controller.rb:16`; `db/seeds.rb:106-109`.

> Nota: corrige D-59 no ponto da resolucao (legado: `AppTheme.default_theme` usa `.first` **sem `ORDER BY`** — com dois `is_default = 1` o padrao e indeterminado; sem nenhum, retorna `nil` e `User#update_theme` estoura no valor default do argumento).

#### Scenario: Usuario sem tema proprio
- **GIVEN** um usuario cujo `app_theme_id` nao foi definido
- **WHEN** ele abre a interface
- **THEN** ele recebe o tema padrao global; se nao houver padrao, recebe as cores de marca embutidas e a interface **nao** quebra

#### Scenario: Cadastro publico herda o tema do gestor
- **GIVEN** um cadastro publico feito sob um `manager` que tem tema proprio
- **WHEN** o usuario e criado
- **THEN** ele nasce com o tema do seu `manager`

#### Scenario: Nao existe tema por projeto
- **GIVEN** um usuario que troca de projeto corrente
- **WHEN** a interface recarrega
- **THEN** o tema nao muda — o escopo do tema e usuario e global, nunca projeto

### Requirement: BE-381 — Modo claro e modo escuro
O sistema SHALL oferecer os modos claro e escuro, e o tema define tokens para os dois. Fonte legada: `app/models/app_theme.rb:72-73,85-86,106-111,126-135`.

> Nota: corrige D-55 no ponto do estilo (legado: `STYLE__DARK`/`STYLE__LIGHT` existem e `beauty_style` traduz os dois, mas a opcao "Escuro" esta **comentada** em `app_theme.rb:109`, `set_defaults` forca `Light` em `:194` e nenhum template ou SCSS reage a `style`). No ai9 o dark e desenho novo derivado da marca Safegold — nao ha referencia legada para comparar.

#### Scenario: Escolha do modo tem efeito
- **GIVEN** um tema
- **WHEN** o operador seleciona o modo escuro
- **THEN** a interface passa a usar os tokens escuros, com contraste minimo AA em texto e controles

#### Scenario: Default e claro
- **GIVEN** um tema recem-criado sem escolha explicita
- **WHEN** ele e aplicado
- **THEN** o modo e claro

### Requirement: BE-382 — Marca canonica como semente do tema padrao
O tema padrao do sistema SHALL nascer das constantes de marca `SFG::Theme`. Fonte legada: `db/factories/app_theme_factory.rb:8-29`; `db/seeds.rb:4,24-25`; `app/models/app_theme.rb:148`.

> Nota: corrige a falha de seed (legado: o factory instancia `File.new(SFG::Theme.LOGO__SYMBOL/_TEXT)` apontando para `app_symbol.png` e `app_text.png`, arquivos **inexistentes** no repositorio, entao o seed estoura `Errno::ENOENT` em instalacao nova; e o seed vinha desligado por `should_seed_app_themes = false`).

#### Scenario: Seed do tema padrao
- **GIVEN** uma instalacao nova
- **WHEN** o seed roda
- **THEN** existe exatamente um tema padrao, com `accent` `#FFC107`, `second` `#607D8B` e fundo de login `#FBFBFB`, e o seed **nao** falha por asset ausente

> AMBIGUIDADE: ha **tres** candidatos a cor primaria no legado — `SFG::Theme.COLOR__PRIMARY` `#2D2D2A` (arquivo canonico de marca), `colors.scss:1` `$primary` `#050517` (o que de fato compila) e `app_theme_factory.rb:17` `#373435` (o que o seed grava). Como o motor nao pintava nada, nem o valor do banco chegava a tela. A decisao registrada em `brand-and-metadata.md` e usar `#2D2D2A`, mas depende de confirmacao visual do tech lead.

### Requirement: BE-383 — Onde o tema aparece: logos, nome de exibicao e copyright
O tema SHALL controlar os logos da barra e das telas de sessao, e o branding dos e-mails transacionais. Fonte legada: `pub/console/base/_bar.html.erb:6`; `pub/users/sessions/_toolbar_body.html.erb:5`; `_toolbar_reset_body.html.erb:5`; `app/decorators/models/mailer_decorator.rb:3-11,17-25,32-40`.

> Nota: corrige a falha de e-mail (legado: o mailer faz `File.new(...)` direto no caminho do Paperclip para anexar `full_logo` e `symbol_logo` inline — tema sem logo derruba o job de welcome / recuperacao / redefinicao de senha com `Errno::ENOENT` no `Delayed::Job`).

#### Scenario: Logos por contexto
- **GIVEN** um tema com simbolo, texto e logo completo
- **WHEN** a interface e renderizada
- **THEN** a barra usa o simbolo no mobile e o texto no desktop; a toolbar de login usa o logo completo e a de redefinicao de senha usa o texto

#### Scenario: E-mail transacional sem logo no tema
- **GIVEN** um tema sem `full_logo` anexado
- **WHEN** um e-mail transacional e disparado
- **THEN** o e-mail e enviado com o logo de marca padrao, sem falhar o job

#### Scenario: Textos de apresentacao
- **GIVEN** um tema sem `display_name` e sem `copyright`
- **WHEN** um e-mail transacional e gerado
- **THEN** ele usa os fallbacks de marca ("Safegold" e o rodape de copyright), sem campo vazio no corpo

### Requirement: BE-384 — Autenticacao e autorizacao dos endpoints de tema
Todos os endpoints de tema SHALL exigir sessao valida e papel administrativo. Fonte legada: `app/controllers/pub/app_themes_controller.rb:1`; `app/controllers/pub_application_controller.rb:34-36`.

> Nota: corrige D-57 (legado: `Pub::AppThemesController` nao sobrescreve `requires_current_user?`, herda `false` e responde **sem sessao** — incluindo `POST /app_themes/:id/active` e `DELETE /app_themes/:id`; a unica barreira restante era o CSRF do Rails e a obscuridade de nao existir item de menu).

#### Scenario: Anonimo e recusado
- **GIVEN** uma requisicao sem sessao
- **WHEN** ela chama qualquer endpoint de tema, inclusive exclusao e ativacao
- **THEN** a resposta e 401 e nenhum efeito colateral ocorre

#### Scenario: Usuario autenticado sem papel administrativo
- **GIVEN** um usuario comum autenticado
- **WHEN** ele chama criacao, edicao, exclusao ou ativacao de tema
- **THEN** a resposta e 403

### Requirement: FE-385 — Tela de lista de temas
A lista SHALL mostrar os temas em cards com previa de cores e acoes por item. Fonte legada: `app/views/pub/console/parts/themes/_body.html.erb`, `_body.js.erb`, `list/_widget.html.erb`, `list/_widget.js.erb`.

> Nota: corrige a falha silenciosa (legado: os callbacks `success`/`failure` do proxy estao **vazios** em `_body.js.erb:65-66`, entao erro de carga nao produz nenhum aviso; e a mensagem de "sem resultado de busca" era inalcancavel porque o campo de busca estava comentado).

#### Scenario: Card sem logo
- **GIVEN** um tema sem `symbol_logo`
- **WHEN** a lista e renderizada
- **THEN** o card mostra as iniciais do titulo sobre a cor de destaque do tema

#### Scenario: Chips de cor
- **GIVEN** um tema com `login_bkg_style` igual a `Color`
- **WHEN** o card e renderizado
- **THEN** aparecem quatro chips (primaria, secundaria, destaque e fundo de login); com qualquer outro `login_bkg_style`, aparecem tres

#### Scenario: Autoria do tema
- **GIVEN** um tema sem usuario associado
- **WHEN** o card e renderizado
- **THEN** o rodape mostra "Criado automaticamente"; havendo usuario, mostra "Criado por {primeiro nome}"

#### Scenario: Falha de carga e visivel
- **GIVEN** a requisicao da lista falha
- **WHEN** a tela termina de carregar
- **THEN** um estado de erro e exibido com opcao de tentar novamente — a tela nao fica em branco nem presa em "Buscando .."

### Requirement: FE-386 — Formulario de tema
O formulario SHALL reunir identificacao, estilo, apresentacao, cores, imagens, fontes e CSS customizado. Fonte legada: `app/views/pub/console/parts/themes/form/_body.html.erb`, `form/_body.js.erb`, `form/handle.js.erb`.

> Nota: corrige os quatro bugs observaveis do legado — (a) os rotulos das cores secundaria/destaque/fundo renderizavam `@app_theme.primary_color` no primeiro paint (`:104,112,120`); (b) o save flutuante enviava `app_theme[app_theme[login_bkg_style]]` (`:131`), entao a mudanca de estilo de fundo **nunca persistia** (D-61); (c) o POST ia para `/app_themes/{id}` (`:148`), rota que o Rails nao expoe; (d) havia um `setTimeout(1500ms)` rotulado "FIX temporario" para os croppies (`:145-167`). Corrige tambem o `ajax:error` que **limpava todos os inputs de arquivo** (`:352-357`), obrigando o operador a reanexar tudo depois de um erro de validacao.

#### Scenario: Rotulos de cor corretos no primeiro paint
- **GIVEN** um tema com quatro cores distintas
- **WHEN** o formulario abre
- **THEN** cada rotulo mostra o valor da **sua** cor

#### Scenario: Estilo de fundo de login
- **GIVEN** o formulario aberto
- **WHEN** o operador muda "Fundo de login" entre `Default`, `Color` e imagem
- **THEN** o campo correspondente (chip de cor ou upload de papel de parede) aparece, o grid se reajusta, e o valor escolhido **persiste** ao salvar

#### Scenario: Extracao automatica de paleta
- **GIVEN** o operador sobe o logo principal
- **WHEN** o upload termina
- **THEN** os quatro campos de cor sao pre-preenchidos a partir da imagem (escuro-suave para primaria, suave para secundaria, vibrante para destaque, claro-suave para fundo de login) e o operador pode sobrescrever qualquer um

#### Scenario: Recorte de imagem por tipo
- **GIVEN** o operador sobe uma imagem
- **WHEN** o recorte abre
- **THEN** o logo e o texto usam proporcao 160x90 e o simbolo usa recorte circular 150x150

#### Scenario: Erro de validacao preserva os anexos
- **GIVEN** o operador anexou tres imagens e o salvamento falha por titulo duplicado
- **WHEN** a resposta de erro chega
- **THEN** as imagens anexadas continuam no formulario e apenas a mensagem do campo com erro e exibida

### Requirement: FE-387 — Tela de detalhe do tema
O detalhe SHALL mostrar o tema com suas cores e oferece editar, remover e voltar. Fonte legada: `app/views/pub/console/parts/themes/detail/_body.html.erb`, `detail/_body.js.erb`.

> Nota: corrige a divergencia de rota (legado: o botao "Editar" montava `/u/console/app_themes/{id}/edit` em `detail/_body.js.erb:28`, com prefixo `app_themes`, enquanto a lista usava `/u/console/themes/...` — dois caminhos para a mesma tela, um deles apontando para actions quebradas, BE-375) e a falha generica "Houve um problema, tente novamente" na exclusao.

#### Scenario: Chips de cor no detalhe
- **GIVEN** um tema com `login_bkg_style` igual a `Color`
- **WHEN** o detalhe e aberto
- **THEN** sao exibidos quatro chips rotulados "Primaria", "Secundaria", "Destaque" e "Fundo login"; caso contrario, tres

#### Scenario: Exclusao a partir do detalhe
- **GIVEN** um tema nao-padrao aberto no detalhe
- **WHEN** o operador confirma a remocao
- **THEN** o tema e removido e a navegacao volta para a lista; se a remocao falhar, a mensagem diz o motivo real (tema padrao, tema em uso), nao um texto generico

### Requirement: DB-388 — Modelo de dados de tema
A tabela de temas SHALL guardar identificacao, tipo, cores, estilo, textos de marca e referencias de anexo, e o usuario referencia seu tema com integridade. Fonte legada: `db/migrate/20200205130201_create_app_themes.rb`; `db/migrate/20200206191948_add_app_theme_column_to_livetat_auth_user.rb`; `app/models/app_theme.rb`.

> Nota: corrige D-59 e o modelo (legado: `is_default` e `integer` 0/1, **nenhum indice** em `app_themes` — nem em `type`, nem em `is_default`, nem unique em `title`; `livetat_auth_users.app_theme_id` e obrigatorio por validacao mas **sem FK e sem indice**; e o model chama as colunas fantasma `is_black_bar_font`/`is_black_font`, que nao existem em migration alguma). `cached_css` **nao e portado** — e cache derivado do motor inerte (D-55).

#### Scenario: Um unico padrao garantido pelo banco
- **GIVEN** um tema ja marcado como padrao
- **WHEN** uma segunda linha tenta gravar o flag de padrao
- **THEN** o banco recusa por indice unico parcial sobre o flag de padrao

#### Scenario: Referencia do usuario ao tema
- **GIVEN** um usuario apontando para um tema
- **WHEN** o tema e removido
- **THEN** a politica de `ON DELETE` declarada na chave estrangeira e aplicada e nenhum usuario fica com referencia orfa

#### Scenario: Titulo unico
- **GIVEN** um tema com titulo "Tema padrao"
- **WHEN** outra linha com o mesmo titulo e inserida
- **THEN** o banco recusa por indice unico

### Requirement: OPS-389 — Pipeline de imagem dos anexos de tema
O sistema SHALL processar os quatro anexos de tema gerando derivadas e guardando os arquivos em storage privado. Fonte legada: `app/models/app_theme.rb:6-46`; `config/initializers/paperclip.rb:1-14`.

> Nota: corrige D-56 e D-82 (legado: `Paperclip::MediaTypeSpoofDetector#spoofed?` sobrescrito para sempre retornar `false`, desabilitando **globalmente** a checagem de spoof, com os arquivos indo para `public/system/:attachment/:id/:basename_:style.:extension` e servidos por URL publica sem autenticacao — combinado com BE-384, um vetor de upload arbitrario; alem disso o storage e disco local do app, que nao sobrevive a container efemero nem a escala horizontal).

#### Scenario: Derivadas geradas por tipo de anexo
- **GIVEN** o operador sobe um logo e um papel de parede
- **WHEN** o processamento termina
- **THEN** os logos tem derivadas de miniatura, previa e original, e o papel de parede tem derivadas ate a maior resolucao, com fundo achatado e sem canal alfa

#### Scenario: Limite de tamanho
- **GIVEN** um arquivo de 8 MB
- **WHEN** o operador tenta anexa-lo
- **THEN** o upload e recusado pelo servidor com mensagem de limite de 5 MB — a validacao nao depende do cliente

#### Scenario: Acesso ao arquivo
- **GIVEN** a URL de um anexo de tema
- **WHEN** um anonimo tenta baixa-lo diretamente
- **THEN** o acesso e negado; os arquivos sao servidos por URL assinada e com prazo, a partir de storage privado

### Requirement: OPS-750 — Nome da aplicacao e cor da marca com fonte unica
O sistema SHALL manter **uma unica** fonte de verdade para o nome de exibicao da aplicacao e para a cor primaria da marca — os design tokens do ai9 — e SHALL **nao** portar a configuracao do kit de UI do legado, que declara os dois pela quarta vez com um valor que nao coincide com nenhum dos outros tres. Fonte legada: `engines/ux_kit19/lib/livetat/ux_kit19/configuration.rb:1-16`, carregada no boot da engine `ux_kit19`.

- O que a configuracao legada declara: `mattr_accessor :app_name` (nome de exibicao do kit) e `@@primary_color = "#504746"`.
- **#504746 e o quarto "primario" conflitante da marca.** Os outros tres: `SFG::Theme.COLOR__PRIMARY` = **#2D2D2A** (`app/definitions/SFG/theme.rb`, o arquivo canonico), `$primary` = **#050517** (`app/frontend/css/pub/colors.scss:1`, o que o SCSS de fato compila) e **#373435** (o que a factory de tema grava no banco, ver OPS-543 e BE-382). Nenhum dos quatro coincide.
- O nome de exibicao tambem e duplicado: o kit tem o seu `app_name`, e o produto tem o dele no motor de temas (ver BE-383).
- No ai9 a marca SHALL vir dos tokens, e o motor de temas SHALL ler o padrao dali (ver BE-382), sem constante de biblioteca competindo com o valor configurado.

> AMBIGUIDADE: qual dos quatro valores e a cor primaria correta da marca — #2D2D2A, #050517, #373435 ou #504746 — e uma decisao do usuario, registrada em `.migration-ai9/brand-and-metadata.md`. Ela muda a aparencia do produto no dia 1 e nao pode ser inferida do codigo, porque os quatro estao ativos ao mesmo tempo em camadas diferentes.

#### Scenario: Cor primaria consultada
- **GIVEN** qualquer camada do ai9 que precise da cor primaria da marca
- **WHEN** o valor e resolvido
- **THEN** ele vem do mesmo token, e nenhuma biblioteca traz um valor proprio concorrente

#### Scenario: Nome de exibicao consultado
- **GIVEN** o nome de exibicao da aplicacao mostrado ao usuario
- **WHEN** ele e alterado na configuracao
- **THEN** a mudanca aparece em todos os lugares, sem sobrar nenhum ponto lendo uma constante de biblioteca

#### Scenario: Varredura por cor literal
- **GIVEN** o codigo do ai9
- **WHEN** ele e varrido por cor de marca escrita literalmente
- **THEN** nenhuma ocorrencia existe fora da definicao dos tokens
