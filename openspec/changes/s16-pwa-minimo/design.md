# Design: S16 — PWA mínimo

> Feature **nova** (DEC-21) — `NEW-003`. Origem: achado nº 5 de
> `.migration-ai9/migration-map.md` ("PWA foi decidido SIM no Phase 0 e não está em nenhuma
> fatia"). Coordena com **OPS-635** (`.migration-ai9/map/data-infra.md` §2.2), que é da fatia
> de marca.

## Context

Medido na base, não suposto: `frontend/public/` tem `favicon.ico`, `robots.txt`,
`sitemap.xml` e assets de outros produtos (`og-goat.png`, `crash_*.jpg`, `martha_avatar.jpg`)
— **nenhum manifest**. `frontend/index.html` traz título, descrição, Open Graph, Twitter card
e JSON-LD do **GOAT/polemk**. Não há `vite-plugin-pwa` no `package.json`, nem nenhuma
referência a `standalone` ou `apple-touch-icon` no código.

O legado não tem nada disso tampouco — e nem poderia: é uma aplicação Rails com Webpacker de
2019.

## Goals / Non-Goals

**Goals**
- O console **instalável** e abrindo em **janela própria**, com ícone e nome da Safegold.
- **Zero dependência nova** e zero build step.

**Non-Goals**
- **Service worker, offline, cache de app shell, push, background sync.** Nada disso.
- Não redefinir a marca — isso é da tematização.
- Não disputar `index.html` com OPS-635: as duas fatias escrevem no mesmo arquivo e a ordem
  está declarada abaixo.

## Decisions

### P1. Manifest estático em `public/`, não plugin

`vite-plugin-pwa` existe para gerar service worker e precache — que é justamente o que **não**
queremos. Um `manifest.webmanifest` em `frontend/public/` é copiado como está pelo Vite,
funciona em dev e em produção e não acrescenta nada ao bundle nem ao build.

Conteúdo:

| Campo | Valor | Por quê |
| ----- | ----- | ------- |
| `name` / `short_name` | Nome da marca / forma curta | `short_name` é o que aparece sob o ícone; nome longo é truncado |
| `start_url` | `/` | A raiz já aponta para o login (DEC-13.3) — correto para sistema interno |
| `scope` | `/` | Tudo dentro do app abre na janela; link externo abre no navegador |
| `display` | `standalone` | Janela própria, sem barra de endereço |
| `theme_color` / `background_color` | Tokens da marca | `background_color` é a cor da tela de abertura; errado aqui = flash branco num tema escuro |
| `lang` | `pt-BR` | DEC-09 |
| `icons` | 192, 512 e **512 `maskable`** | Ver P2 |

### P2. Ícone maskable não é detalhe

Sem um ícone `purpose: maskable`, o Android **recorta o ícone dentro de um círculo branco** —
o logo aparece cortado, com moldura errada. O maskable precisa da **zona segura**: o
conteúdo visível dentro de ~80% do quadro, com a margem preenchida pela cor de fundo da
marca, e não transparente.

O `apple-touch-icon` (180×180) é lido do **HTML**, não do manifest — o iOS ignora o array de
`icons` para "Adicionar à Tela de Início". Esquecer essa tag é o erro clássico que faz o iOS
usar uma **captura da página** como ícone.

Os assets vêm da tematização, que já resolve a **Q-14** (`app_symbol.png` e `app_text.png`
são referenciados pelo tema do legado e **não existem no repositório**, sendo gerados a
partir do logo cheio). S16 **não** desenha logo.

### P3. Sem service worker: o que isso custa, dito na cara

**Corrigido depois de medir (25/08/2026, Chromium 151).** Este parágrafo dizia que os
navegadores Chromium condicionam o `beforeinstallprompt` à existência de um service worker.
**Isso não se confirma no Chromium atual** — o requisito foi relaxado. Medido por CDP no build
de produção: `Page.getInstallabilityErrors` volta **vazio** e o `beforeinstallprompt`
**dispara** com zero service workers (controle: uma página sem manifest devolve `no-manifest`,
então a API não é stub). A escolha de não ter service worker continua valendo — pelo motivo do
parágrafo seguinte, que é de produto e não de instalabilidade.

| Caminho | Funciona? |
| ------- | --------- |
| iOS/iPadOS Safari → Compartilhar → "Adicionar à Tela de Início" | **Sim** — usa manifest + `apple-touch-icon` |
| Chrome/Edge desktop → menu → "Instalar página como aplicativo" | **Sim** — janela própria, ícone e nome corretos |
| Prompt automático "Instalar" no Chromium | **Sim** — o evento dispara. O que não existe é **convite dentro do app**: nada trata o `beforeinstallprompt`, então quem instala vai pelo menu do navegador |

A escolha é deliberada (DEC-21). O que um service worker traz junto é **versionamento de
cache, invalidação em deploy e a classe de bug "o usuário está vendo a versão de ontem"** —
num sistema financeiro, um número em cache de ontem exibido como se fosse de hoje é pior do
que não ter ícone na tela inicial. Se o prompt automático virar requisito, é outra fatia, com
esse custo assumido de propósito.

**Isto precisa estar registrado no ledger junto com o `new`**: senão, um QA testa "instalar"
no Chrome Android, não vê o convite e abre um defeito contra uma decisão de escopo.

### P4. Ordem com OPS-635, porque as duas fatias escrevem no mesmo `index.html`

A fatia de marca (OPS-635) troca título, descrição, Open Graph, favicon e `robots.txt` — hoje
tudo do GOAT, com `Allow: /` e sitemap apontando para `goat.polemk.com`, o que está **errado
para uma aplicação privada de gestão financeira** (decisão **D-T**: `Disallow: /`).

**A marca vai primeiro.** S16 entra depois e acrescenta **só** as três linhas que são dela:
`<link rel="manifest">`, `apple-touch-icon` e as metas `apple-mobile-web-app-*`. O
`theme-color` é da marca; S16 apenas garante que o valor do manifest **é o mesmo** do HTML —
divergência entre os dois produz uma barra de status de uma cor e uma tela de abertura de
outra.

## Risks / Trade-offs

| Risco | Mitigação |
| ----- | --------- |
| **Instalar com o ícone do produto errado** numa demo comercial | S16 depende dos assets da marca. Sem eles, a fatia espera — é a única dependência real |
| **QA abrindo defeito porque não aparece o prompt no Chrome** | Registrado no ledger e no `proposal.md`: é escopo, não bug (P3) |
| **Ícone recortado no Android** | Ícone `maskable` com zona segura de ~80% e margem na cor da marca |
| **iOS usando captura de tela como ícone** | `apple-touch-icon` 180×180 declarado no HTML, não só no manifest |
| **Conflito de edição em `index.html`** com OPS-635 | Ordem declarada: marca primeiro, S16 acrescenta só as três linhas dela |
| **A fatia crescer para service worker** | O `proposal.md` lista os não-objetivos nominalmente. Offline é outra fatia, com outro custo |
