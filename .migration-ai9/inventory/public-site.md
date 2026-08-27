# Inventário — site público / landing (IDs 640–659) — **DROPPED**

Unidade inventariada pelo orquestrador (não é uma unidade de migração: o usuário
decidiu no Phase 0 tirar o site público do escopo). Registrada aqui para que a
decisão fique auditável e reversível — não é perda silenciosa.

## Frontend (FE)
| ID | Tela / fluxo | Fonte legado | Estados | Interações | Regras de UI | Ambiguidade? |
| -- | ------------ | ------------ | ------- | ---------- | ------------ | ------------ |
| FE-640 | Landing pública `/landing` (index) | `app/controllers/pub/start_controller.rb:7-9`, `app/views/pub/start/index.html.erb` | página estática montada via `_index.js.erb` | render inicial + mount dos parts | layout próprio (`css/pub/components/start/index.scss`, `base.scss`) | não |
| FE-641 | Header do site público | `app/views/pub/start/parts/header/_body.html.erb`, `_mount.js.erb` | — | navegação | `start/header.scss` | não |
| FE-642 | Bloco "app" do site público | `app/views/pub/start/parts/app/_body.html.erb`, `_widget.html.erb` | — | widget montado por js.erb | `start/app.scss` | não |
| FE-643 | Footer do site público | `app/views/pub/start/parts/footer/_container.html.erb` | — | — | `css/pub/footer.scss` | não |
| FE-644 | Toolbar do site público | `app/views/pub/start/toolbar/_body.html.erb`, `_after.js.erb` | — | — | — | não |
| FE-645 | Ações remanescentes sem view: `generic_search`, `generic_city`, `resume`, `tourist`, `reservation`, `refund`, `points`, `pay`, `account`, `info` | `app/controllers/pub/start_controller.rb:22-84` | — | — | — | **sim — código morto** |

## Evidência de que o drop é seguro
- `Pub::StartController` tem 11 actions que renderizam `pub/start/parts/<x>/body`,
  mas **só existem** os parts `header`, `app` e `footer` em `app/views/pub/start/parts/`.
  As demais (`generic_search`, `generic_city`, `resume`, `tourist`, `reservation`,
  `refund`, `points`, `pay`, `account`, `info`) apontam para views inexistentes →
  quebrariam se chamadas. São resíduo de um template de outro produto
  (turismo/reservas/pontos/pagamento), não features do SFG.
- As actions também não estão expostas em `config/routes.rb`: a única rota do
  controller é `resources :start, path: "/landing", only: [:index]`.

## ATENÇÃO — o que NÃO está dropado
`Pub::StartController#sign_in` (`start_controller.rb:11-20`) renderiza
`pub/users/sessions/new` com `AppTheme.default_theme`. **A tela de login continua
100% no escopo** e pertence à unidade `auth-users` (faixa 001–049), não a esta.
O mesmo vale para `AppTheme.default_theme`, que pertence à unidade `themes`
(faixa 370–389).

## Cobertura
- arquivos lidos: `app/controllers/pub/start_controller.rb`, `app/views/pub/start/**`,
  `app/frontend/css/pub/components/start/*`, `config/routes.rb`
- lacunas/dúvidas: nenhuma — unidade fechada como `dropped`
