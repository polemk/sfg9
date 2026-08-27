# Opções do projeto — migração sfg → ai9

Definidas pelo usuário no Phase 0 (24/08/2026).

## Marca (branding)
- **Decisão:** usar a marca do legado SFG.
- Logos: `../sfg/app/frontend/images/brand/` (`app_logo_full_original.png`,
  `app_logo_full.png`, `app_logo_400.png`, `app_logo_250.png`).
- Cores (de `../sfg/app/frontend/css/pub/colors.scss`):
  - `primary` **#050517** (quase preto / navy)
  - `accent` **#FFC107** (dourado, usado como `rgba(255,193,7,.79)`)
  - `accent_aux` #607D8B · `accent_inverse` #373435
  - positivo #217B55 · negativo #7D1F1E · red #F8333C · green #31D86C · blue #3454D1 · yellow #FFBE0B
  - background #FAFAFA · texto #444 · título #222 · white #FFFFF3
- Aplicar nos tokens centrais do ai9 em **light E dark**; substituir conteúdo padrão
  do ai9 (carousel de login, taglines) pela marca SFG.

## Mobile / PWA
- **Views mobile separadas:** SIM (telas próprias com sensação nativa, compartilhando
  API, camada de dados e componentes com o desktop).
- **PWA:** SIM — habilitar (manifest, service worker, instalável).

## Site público
- **Decisão:** NÃO migrar o site público do legado (`pub/start` → `/landing`).
- Consequência: todos os IDs de inventário referentes ao site público entram no
  parity ledger como `dropped`, com motivo "decisão do cliente — fora de escopo
  (Phase 0)". Não é perda silenciosa: fica registrado e é reversível.

## Ferramentas
- openspec 1.4.1 — instalado
- graphify 0.9.11 — instalado; hook (post-commit + post-checkout) **já instalado**
  no target (verificado com `graphify hook status`)
- impeccable — skill presente em `~/.claude/skills/impeccable`
