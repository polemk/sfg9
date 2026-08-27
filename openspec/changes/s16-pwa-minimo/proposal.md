# Proposal: S16 — PWA mínimo (`NEW-003`): manifest, ícones, instalável

> Fatia **S16** da ordem de execução de `.migration-ai9/migration-map.md`, seção
> **"Adições de escopo aprovadas (DEC-21)"**. Depende de **S2** (console e navegação) e dos
> assets de marca produzidos pela tematização.

## ⚠️ Esta fatia é FEATURE NOVA, não paridade

**Não existe nada de PWA no legado, e não existe nada de PWA na base ai9.** No
`parity-ledger.md`, `NEW-003` entra como **`new`**.

**O QA do Phase 4 NÃO deve procurar isto no legado** — não está lá. Medição:
`frontend/` não tem `manifest.webmanifest`, `manifest.json`, `apple-touch-icon`, nenhuma
referência a `standalone` e nenhum plugin de PWA no `package.json`; e o `frontend/index.html`
da base descreve o **GOAT** (`<title>GOAT — CRM brasileiro…`, `og-goat.png`,
`fb:app_id` do polemk, `theme-color: #fff2f4`).

O PWA foi decidido **sim** no Phase 0 e não estava em nenhuma fatia — o Phase 2 registrou
isso como achado nº 5 justamente para a decisão não sumir. Esta fatia é o registro virando
entrega.

## Why

É um sistema de gestão que as pessoas abrem todo dia. Ícone na tela inicial e janela própria
custam **um arquivo de manifest e um conjunto de ícones**, e mudam a percepção de "site que
eu acesso" para "aplicativo que eu tenho" — que é exatamente o que uma demonstração
comercial precisa comunicar no primeiro segundo.

E é barato **agora**: os ícones da marca Safegold já vão ser produzidos pela tematização
(inclusive resolvendo a **Q-14** — `app_symbol.png` e `app_text.png` são referenciados pelo
tema do legado e **não existem no repositório**, então são gerados a partir do logo cheio).
Fazer o manifest na mesma passagem aproveita o trabalho; fazer depois significa reabrir a
geração de assets.

## What Changes

**Escopo deliberadamente pequeno. Três coisas:**

1. **`frontend/public/manifest.webmanifest`** com `name`, `short_name`, `start_url`, `scope`,
   `display: standalone`, `theme_color`, `background_color`, `lang: pt-BR` e o array de
   `icons`.
2. **Ícones da marca Safegold** nos tamanhos que os sistemas operacionais pedem — incluindo
   **512×512 `purpose: maskable`** (sem ele o Android recorta o logo dentro de um círculo
   branco) e o `apple-touch-icon`, que o iOS lê do HTML e não do manifest.
3. **`frontend/index.html`** ligando o manifest e trazendo as metas de iOS
   (`apple-mobile-web-app-capable`, `-status-bar-style`, `-title`) — e **substituindo a
   identidade GOAT herdada**, em coordenação com OPS-635 (que é da fatia de marca).

## Não faz parte desta fatia — e é decisão, não esquecimento

- **Sem service worker.**
- **Sem offline, sem cache de app shell, sem sincronização em segundo plano.**
- **Sem push notification.**
- **Sem `vite-plugin-pwa`** nem qualquer dependência nova — um manifest estático em `public/`
  resolve, e não introduz build step.

**Consequência honesta, que precisa estar escrita:** sem service worker, os navegadores que
exigem um para o **prompt automático** de instalação (a família Chromium) **não** vão exibir
o convite "Instalar". A instalação continua disponível pelos caminhos que não dependem de
service worker: **iOS/iPadOS Safari → "Adicionar à Tela de Início"** (que usa manifest +
`apple-touch-icon`) e **Chrome/Edge desktop → menu → "Instalar página como aplicativo"**. Em
qualquer um deles o app abre em **janela própria**, com o ícone e o nome da marca.

Isto é escolha de escopo (DEC-21 diz "sem service worker"), não limitação descoberta tarde.
Se o prompt automático virar requisito, é **outra fatia**, e ela precisa tratar o que um
service worker traz junto: versionamento de cache, invalidação em deploy e a classe de bug
"o usuário está vendo a versão de ontem" — que num sistema financeiro é grave.

## Fronteiras

- **A marca é da tematização.** S16 **consome** os assets; não define cor nem desenha logo.
  Se a marca ainda não estiver pronta, esta fatia **espera** — um PWA com o ícone do produto
  errado é pior que nenhum PWA.
- **OPS-635** (favicon, ícones, `robots.txt` com `Disallow: /`, metadados de OG) é da fatia de
  marca. S16 não duplica: **reusa** o mesmo conjunto de ícones e só acrescenta o manifest e
  as metas de iOS.
- **A rota `/`** já aponta para o login (DEC-13.3). `start_url` é `/`, e o app instalado abre
  na tela de login — comportamento correto para sistema interno.

## Dependências

- **S2** — o console e a navegação existem; instalar um app que abre numa tela quebrada não
  demonstra nada.
- **Tematização/OPS-635** — logo, cores e favicon da Safegold (e a **Q-14**, os dois assets
  inexistentes gerados a partir do logo cheio).

## Capabilities

### New Capabilities

- `pwa`: instalabilidade do console — manifest, ícones e o comportamento de janela própria.
  Deliberadamente **uma** requirement; não há capability equivalente na base nem no legado.

### Modified Capabilities

Nenhuma.

## Impact

- **Frontend:** `public/manifest.webmanifest`, `public/icons/*` e `index.html`
  (`<link rel="manifest">`, `apple-touch-icon`, metas de iOS, `theme-color` da marca).
- **Backend:** nada.
- **Dependências:** **nenhuma nova**. Sem plugin, sem build step.
- **Paridade:** 1 ID `new`. Nenhum item de paridade é fechado por esta fatia.
