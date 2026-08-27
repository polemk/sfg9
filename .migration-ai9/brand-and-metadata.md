# Marca & metadados canônicos do legado (Safegold / SFG)

Fonte canônica: `../sfg/app/definitions/SFG/theme.rb` e `../sfg/app/definitions/SFG/metadata.rb`.
**Estes dois arquivos NÃO estão no grafo do graphify** (falha de case-sensitivity no
caminho UNC: o extractor procurou `app/definitions/sfg/...` minúsculo e produziu zero
nós — ver aviso do graphify #1666). Foram lidos manualmente pelo orquestrador. QA:
não trate a ausência deles no grafo como "não existe".

## Identidade
- Nome do produto: **Safegold** (`METADATA.COMPANY`, `TITLE`, `SITE_NAME`)
- App id interno: `sfg` (`Theme.APP__NAME`)
- Keywords: `safegold, sfg, lvt, livetat apps, livetat`
- Versão exibida no legado: 1.11.1 — 06.04.2023 (string de changelog em `DESCRIPTION`)

## Cores canônicas (`SFG::Theme`)
| Token legado | Valor |
| ------------ | ----- |
| `COLOR__PRIMARY` | **#2D2D2A** |
| `COLOR__ACCENT` | **#FFC107** (+ lighten/darken 5%) |
| `COLOR__ACCENT_AUX` | #607D8B (+ lighten/darken 5%) |
| `COLOR__ACCENT_INVERSE` | #373435 (+ lighten/darken 5%) |
| `COLOR__RED` | #F8333C |
| `COLOR__GREEN` | #31D86C |
| `COLOR__BLUE` | #3454D1 |
| `COLOR__YELLOW` | #FFBE0B |
| `COLOR__FACEBOOK` | #235789 |
| `COLOR__INDICATOR_POSITIVE` | #217B55 |
| `COLOR__INDICATOR_NEGATIVE` | #7D1F1E |
| `COLOR__LOGIN_BKG` | #FBFBFB |

### ⚠ Divergência a resolver no Phase 2 — são TRÊS primários, não dois
| Fonte | Valor | Peso |
| ----- | ----- | ---- |
| `app/definitions/SFG/theme.rb` (`COLOR__PRIMARY`) | **#2D2D2A** | arquivo canônico de definição da marca |
| `app/frontend/css/pub/colors.scss:1` (`$primary`) | #050517 | o que o SCSS realmente compila |
| `db/factories/app_theme_factory.rb:17` | #373435 | o que o tema semeado grava no banco |

Três "primários" diferentes convivendo. Agrava o quadro o **D-55**: o motor de temas
não pinta nada (o CSS template está inteiramente comentado), então **nem o valor do
banco chega à tela** — na prática hoje vale o `colors.scss` compilado.
**Decisão do orquestrador:** `SFG::Theme` é a fonte canônica (é o arquivo de
definição da marca, consumido pelo motor de temas), então o token `primary` do ai9
recebe **#2D2D2A**; #050517 fica registrado como variante herdada do SCSS. O
`theming-brand-engineer` deve confirmar visualmente contra o app rodando/screenshots
antes de fechar, e registrar a escolha no improvements-log.

### Dark mode: o legado **não tem**
As constantes `STYLE__DARK`/`STYLE__LIGHT` existem e `beauty_style` sabe traduzir as
duas, mas a opção "Escuro" está **comentada** em `app/models/app_theme.rb:109`,
`set_defaults` força `Light` (`:194`) e nenhum template/SCSS reage a `style`.
**Consequência para a migração:** o dark mode do ai9 não é "portar o dark do legado"
— é **desenho novo**, derivado da marca Safegold. O `theming-brand-engineer` decide a
paleta dark e registra no improvements-log; não há referência legada para comparar.

## Logos (`SFG::Theme`)
Todos em `../sfg/app/frontend/images/brand/`:
- `LOGO__FULL` / `_WHITE` / `_MONO` → `app_logo_full.png` (os três apontam para o mesmo arquivo no legado)
- `LOGO__SYMBOL` / `_WHITE` / `_MONO` → `app_symbol.png`
- `LOGO__TEXT` / `_WHITE` / `_MONO` → `app_text.png`
- Avatar/OG: `brand/app_symbol_250.png`, 250×250, image/png
- **CORREÇÃO (25/08/2026, `theming-brand-engineer`):** `app_symbol.png` e `app_text.png`
  **existem sim** — a listagem anterior estava incompleta. O diretório tem
  `app_logo_full_original.png` (2527×893, o único em resolução útil), `app_logo_full.png`,
  `app_logo_400.png`, `app_logo_250.png`, `app_symbol.png` (150×150), `app_symbol_250.png`,
  `app_symbol_400.png`, `app_text.png`, `app_text_{150,250,400}.png` e `favicon.ico`.
  Não há referência quebrada. Nenhum asset precisou ser pedido ao usuário.
- **O que foi gerado para o ai9** (`frontend/public/images/brand/`), a partir do
  `app_logo_full_original.png`: fundo branco removido com alpha real (`alpha = 255 - min(r,g,b)`,
  desfazendo a composição sobre branco, o que preserva o ouro — a fórmula ingênua por
  luminância apaga o #EB9600), recorte por bounding box, e uma variante clara para o modo
  escuro. Saída: `safegold-logo{,-white}.png` (1638×215), `safegold-wordmark{,-white}.png`,
  `safegold-symbol{,-white}.png`, `safegold-icon-{32,180,192,512}.png` (símbolo claro sobre
  o grafite da marca), `favicon.ico` multi-resolução e `og-safegold.png` (1200×630).
- **Cor real do arquivo de logo, amostrada pixel a pixel:** grafite **#292C28**, ouro
  **#EB9600**. O grafite confirma o `COLOR__PRIMARY` #2D2D2A do `theme.rb` (e refuta o
  #050517 navy do SCSS). O ouro do arquivo é mais fechado que o #FFC107 declarado — os dois
  entraram: `--brand-gold` = #FFC107 (declarado), `--brand-gold-deep` = #EB9600 (do arquivo,
  usado em hover/pressed e onde o ouro precisa de contraste sobre claro).

## Constantes de negócio (`SFG::Metadata`) — viram configuração no ai9
| Constante | Valor | Onde importa |
| --------- | ----- | ------------ |
| `MAX_FILES_PER_RENEGOTIATION` | 4 | regra de upload de anexos de renegociação |
| `MAX_FILE_SIZE` | 5 MB | idem |
| `PUBLIC_CREATE_USER` | 1 | permite auto-cadastro público de usuário |
| `GOOGLE_MAPS_DEFAULT_PLACE` | lat -27.1740121, lng -51.5053261 | centro padrão do mapa |
| `AUTOCOMPLETE_BIAS_LAT/LNG/RADIUS` | -27.1748947 / -51.5500562 / 10 km | viés do autocomplete de endereço |
| `GOOGLE_ANA_APP_ID` | G-7E78XXZX5X | Google Analytics |
| `RWS_TOKEN` | `ENV['rws_api_token']` | ReceitaWS (consulta de CNPJ) |
| `URL` | `ENV['alias']` | host público |
| `FACEBOOK_APP_ID/SECRET` | 0 | login Facebook **desativado** no legado |

## 🔒 Achado de segurança (não propagar para o ai9)
`metadata.rb` traz uma **Google Maps API key hardcoded no código-fonte**
(`GOOGLE_MAPS_API_KEY` / `GOOGLE_MAPS_API_URL`), commitada no repositório. No ai9 ela
**deve** virar variável de ambiente/credential, nunca constante em código. Como a chave
já esteve versionada, recomenda-se **rotacionar a chave no console do Google Cloud** e
restringi-la por referrer/IP. Registrado também no `improvements-log.md`.
