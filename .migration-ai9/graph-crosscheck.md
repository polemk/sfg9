# Graph crosscheck — sfg (legado) × `feature-inventory.md`

> Passo anti-lacuna do Phase 1. Prova que nenhum arquivo do legado com representação
> no grafo AST do graphify ficou sem dono: ou tem um ID de inventário apontando para
> ele, ou tem um motivo escrito para estar fora de escopo.

## Método

1. `../sfg/graphify-out/graph.json` (**3480 nós**, **4336 arestas**, 3,2 MB) foi lido por
   script Python — nunca carregado inteiro em contexto. Os nós foram agrupados por
   `source_file`.
2. De cada uma das **1402 linhas** dos 16 fragmentos de `inventory/` foi extraída a
   coluna **Fonte** e dela todos os caminhos `arquivo:linha` (**646 referências
   distintas**). As abreviações do `data-schema` (`M/<timestamp>` = `db/migrate/...`,
   `E/<engine>/<timestamp>` = `engines/<engine>/db/migrate/...`) foram expandidas por
   casamento de timestamp.
3. Para cada arquivo do grafo, procurou-se casamento exato, por sufixo de caminho, por
   diretório citado ou por timestamp de migration.
4. Os arquivos sem nenhum ID apontando para eles foram **abertos e lidos um a um** e
   classificados em (a) feature não inventariada → ID novo na faixa 700–799, ou
   (b) fora de escopo com motivo.

Scripts usados: `parse.py` (extração das 1402 linhas), `graphck2.py`/`gaps.json`
(cruzamento), `crosscheck.py` (classificação) — em `%TMP%/scratchpad`, descartáveis.

## Totais

| Métrica | Valor |
| ------- | ----- |
| Nós no grafo | 3480 |
| Nós **sem** `source_file` (nós-deus / comunidades) | 59 |
| **Arquivos-fonte distintos representados no grafo** | **524** |
| Arquivos já cobertos por um ID preexistente | **443** (84.5%) |
| Arquivos **inventariados agora** pelo QA (faixa 700–799) | **47** |
| Arquivos conscientemente **fora de escopo** | **34** |
| Arquivos sem classificação | **0** |

Cobertura final: **524/524 = 100%** dos arquivos com nós no grafo têm destino escrito.

### Lacuna conhecida do grafo — não é lacuna de inventário

`app/definitions/SFG/theme.rb` e `app/definitions/SFG/metadata.rb` produziram **zero
nós**: o extractor procurou o caminho em minúsculas (`app/definitions/sfg/...`) e o
volume UNC é case-sensitive. Os dois arquivos **existem** e foram lidos à mão para
`brand-and-metadata.md`. Seu conteúdo está coberto por IDs:

| Conteúdo | IDs que cobrem |
| -------- | -------------- |
| `require` explícito dos dois arquivos no boot (fora do autoload, com `SFG` maiúsculo — a causa raiz da falha) | **OPS-603** |
| `SFG::Theme` — paleta, logos, `APP__NAME` | **OPS-543** (AppThemeFactory lê `LOGO__FULL/TEXT/SYMBOL`), **FE-410** (`COLOR__ACCENT` no loader dos toasts), **FE-443** (`tracking_color`), **BE-380** (precedência de tema) |
| `SFG::Metadata` — Google Maps, Analytics, Facebook, ReceitaWS, limites de upload, `PUBLIC_CREATE_USER`, SEO | **OPS-482**, **OPS-486**, **OPS-489**, **OPS-480**, **OPS-495**, **BE-442**, **FE-444**, **BE-011**, **FE-003**, **FE-518** |

Divergência de marca (três "primários" — `#2D2D2A`, `#050517`, `#373435`) fica
registrada em `brand-and-metadata.md`; este crosscheck acrescenta um **quarto**:
`#504746` em `Livetat::UxKit19::Configuration` (**OPS-750**).

## Lacunas encontradas e fechadas — 47 arquivos → 12 IDs (11 novos + DB-734)

| Arquivo (nós) | ID criado | O que é |
| ------------- | --------- | ------- |
| `app/frontend/js/toolbars.js` (53) | **FE-740** | A barra de contexto do console: título, voltar, loader, mensagens, busca, geolocalização. **751 linhas, 53 nós, nenhum fragmento a citava.** |
| `app/frontend/js/simple_menu.js` (11) | **FE-741** | Widget de menu com item ativo derivado da URL — o par JS do `create_console_menu` (FE-441). |
| `app/frontend/js/helpers.js` (15) | **FE-742** | `toastAlert`, `brazilianDate`, `extendedDate`, `parseAddress*`, `scriptLoader`, `requireSignIn` — helpers globais usados por quase todo `*.js.erb`. |
| `vendor/dialog/index.js` (6)<br>`vendor/dialog/package.json` (6)<br>`vendor/dialog/style.js` (2)<br>`vendor/dialog/template.js` (2) | **FE-743** | Componente proprietário `Dialog` (modal de confirmação/erro). Sem equivalente npm. |
| `vendor/doughnut/package.json` (12)<br>`vendor/doughnut/rollup.config.js` (1)<br>`vendor/doughnut/src/color.js` (4)<br>`vendor/doughnut/src/default-colors.js` (1)<br>`vendor/doughnut/src/doughnut-legend.js` (6)<br>`vendor/doughnut/src/doughnut.js` (41)<br>`vendor/doughnut/src/main.js` (1)<br>`vendor/doughnut/src/math-helper.js` (4)<br>`vendor/doughnut/src/series-legend.js` (3)<br>`vendor/doughnut/src/series.js` (3)<br>`vendor/doughnut/src/style-manager.js` (2) | **FE-744** | Componente proprietário `Doughnut` — **o único gráfico do legado** (61 nós). Sem equivalente npm. |
| `app/frontend/vendor/js/datepicker_overrides.js` (1) | **FE-745** | Locale pt-BR do `air-datepicker` + formato `dd/mm/yyyy` de todos os campos de data. |
| `app/frontend/vendor/js/dragula_wrapper.js` (1)<br>`app/frontend/vendor/js/lvt-dialog.js` (1)<br>`app/frontend/vendor/js/lvt-doughnut.js` (1)<br>`app/frontend/vendor/js/rails-action-text.js` (1)<br>`engines/auth_ux19/app/assets/javascripts/livetat/auth_ux19/application.js` (1)<br>`engines/mailer19/app/assets/javascripts/livetat/mailer19/application.js` (1)<br>`engines/navkit/app/frontend/css/init.js` (1) | **OPS-746** | Shims que reexportam vendor como global no Webpacker (`dragula`, `Dialog`, `Doughnut`, `trix`/actiontext) + entrypoints de asset das engines. |
| `engines/auth19/app/controllers/livetat/auth/passwords_controller.rb` (4)<br>`engines/auth19/app/controllers/livetat/auth/registrations_controller.rb` (4)<br>`engines/auth19/app/controllers/livetat/auth/sessions_controller.rb` (4) | **BE-747** | Controllers Devise vazios da `auth19` (sessions/registrations/passwords) — ancoragem das rotas de login/registro/reset. |
| `engines/auth19/lib/livetat/auth/class_level_inheritable_attributes.rb` (8) | **BE-748** | Mixin `ClassLevelInheritableAttributes`, base da `AbilityFactory` (herança de permissões por papel). |
| `engines/auth19/app/models/livetat/auth.rb` (3)<br>`engines/auth19/lib/livetat/auth.rb` (3)<br>`engines/auth19/lib/livetat/auth/engine.rb` (4)<br>`engines/auth19/lib/livetat_auth.rb` (1)<br>`engines/auth_omni19/lib/livetat/auth_omni19.rb` (4)<br>`engines/auth_omni19/lib/livetat/auth_omni19/engine.rb` (4)<br>`engines/auth_omni19/lib/livetat_auth_omni19.rb` (1)<br>`engines/auth_ux19/lib/livetat_auth_ux19.rb` (1)<br>`engines/feedback19/lib/livetat/feedback19.rb` (4)<br>`engines/feedback19/lib/livetat_feedback19.rb` (1)<br>`engines/mailer19/lib/livetat/mailer19.rb` (4)<br>`engines/mailer19/lib/livetat_mailer19.rb` (1)<br>`engines/ux_kit19/lib/livetat/ux_kit19.rb` (3)<br>`engines/ux_kit19/lib/livetat/ux_kit19/engine.rb` (4)<br>`engines/ux_kit19/lib/livetat_ux_kit19.rb` (1) | **OPS-749** | Bootstrap das 6 engines: entrypoints, `isolate_namespace`, injeção das migrations no app (a razão de `db/migrate` não ter as migrations das engines) e carga de decorators **com erro engolido**. |
| `engines/ux_kit19/lib/livetat/ux_kit19/configuration.rb` (6) | **OPS-750** | `UxKit19::Configuration` — `app_name` e `primary_color = #504746` (quarta fonte de marca). |

Uma lacuna a mais foi fechada **sem** ID novo:
`engines/feedback19/app/models/livetat/feedback19/observer_context.rb` (4 nós) entrou como fonte de
**DB-734** (`livetat_feedback_observer_contexts`), um dos IDs criados ao desagrupar DB-595.

> Todos os 11 IDs acima já estão em `feature-inventory.md` e em `parity-ledger.md` com estado `pending`.

## Fora de escopo — 34 arquivos, com motivo

| Arquivo (nós) | Motivo |
| ------------- | ------ |
| `bin/bundle` (1)<br>`bin/rails` (1)<br>`bin/rake` (1)<br>`bin/setup` (2)<br>`bin/update` (2)<br>`bin/webpack` (1)<br>`bin/webpack-dev-server` (1)<br>`bin/yarn` (1)<br>`engines/auth19/bin/rails` (1)<br>`engines/auth_omni19/bin/rails` (1)<br>`engines/auth_ux19/bin/rails` (1)<br>`engines/navkit/bin/rails` (1)<br>`engines/ux_kit19/bin/rails` (1) | Binstub gerado pelo Rails/Webpacker. O ai9 gera os seus. (`bin/webpack*` aparece como *gatilho* em OPS-508/OPS-746, não como comportamento.) |
| `engines/auth19/lib/livetat/auth/version.rb` (3)<br>`engines/auth_omni19/lib/livetat/auth_omni19/version.rb` (3)<br>`engines/auth_ux19/lib/livetat/auth_ux19/version.rb` (3)<br>`engines/feedback19/lib/livetat/feedback19/version.rb` (3)<br>`engines/mailer19/lib/livetat/mailer19/version.rb` (3)<br>`engines/ux_kit19/lib/livetat/ux_kit19/version.rb` (3) | `VERSION = "x.y.z"` — boilerplate de gem. Não há engine no ai9. |
| `app/frontend/vendor/js/foundation.js` (1)<br>`app/frontend/vendor/js/iv-viewer.js` (1)<br>`app/frontend/vendor/js/jquery_masked_input_plugin.min.js` (14)<br>`app/frontend/vendor/js/masonry.pkgd.min.js` (9) | Vendor de terceiros, minificado/importado como está — não é comportamento do produto. O ai9 não porta a lib, porta o comportamento das telas que a usam. |
| `app/frontend/site_gems/js/helper_builder.js` (5)<br>`app/frontend/site_gems/js/jquery.mobile.js` (68) | Pertence ao pack **`site_gems`**, importado só por `app/views/layouts/site.html.erb`, layout que **nenhum controller usa** (engines.md, BE-539/OPS-508). É o front do site público, já `dropped` no Phase 0 (FE-640..FE-645). |
| `config/boot.rb` (1)<br>`config/environment.rb` (1) | Boilerplate de boot do Rails (`Bundler.setup` + `bootsnap` + `Application.initialize!`). O conteúdo relevante — inicializadores, timezone, autoload, requires de marca — está em OPS-600..OPS-639 e OPS-603. |
| `engines/feedback19/app/controllers/livetat/feedback19/application_controller.rb` (4)<br>`engines/mailer19/app/controllers/livetat/mailer19/application_controller.rb` (4) | Subclasse **vazia** de `ActionController::Base` / `AuthUx19::ApplicationController`, só para dar namespace à engine. Sem código. |
| `engines/auth_ux19/app/helpers/livetat/auth_ux19/application_helper.rb` (4)<br>`engines/mailer19/app/helpers/livetat/mailer19/application_helper.rb` (4) | Módulo de helper **vazio** gerado pelo `rails plugin new`. Sem código. |
| `app/controllers/application_controller.rb` (2) | Classe **vazia** (`class ApplicationController < ActionController::Base; end`). Toda a área logada herda de `PubApplicationController` (BE-458). Nada a portar. |
| `app/frontend/pub_gems/js/jquery.mobile.js` (68) | Vendor de terceiros, minificado/importado como está — não é comportamento do produto. O ai9 não porta a lib, porta o comportamento das telas que a usam. (jQuery Mobile — vem via pack `pub_gems`) |
| `engines/ux_kit19/app/frontend/vendor/js/owl/owl.min.js` (6) | Vendor de terceiros, minificado/importado como está — não é comportamento do produto. O ai9 não porta a lib, porta o comportamento das telas que a usam. Além disso o Owl Carousel está listado como **não importado / morto** em FE-538. |

## Leitura do resultado

- O inventário estava **muito bom**: 84,5 % dos arquivos com nós no grafo já tinham ID
  antes desta passagem, e as 12 unidades não deixaram nenhum controller, model, view ou
  migration de fora.
- **O buraco era o front puro em JavaScript.** Todas as lacunas reais estão em
  `app/frontend/js/**` e `vendor/**`: as unidades inventariaram exaustivamente os
  `*.js.erb` (que são views) e passaram ao largo dos módulos ES6 importados pelos packs.
  `toolbars.js` sozinho tem 751 linhas e 53 nós — é o segundo componente mais pesado do
  legado e não tinha dono.
- **Dois componentes proprietários sem equivalente npm** (`vendor/dialog`,
  `vendor/doughnut`) são risco de escopo: o doughnut é o único gráfico do produto.
- Nenhum arquivo do grafo ficou sem destino. O que sobrou fora de escopo é binstub,
  boilerplate de engine, classe vazia ou vendor de terceiros — nunca comportamento de
  produto.
