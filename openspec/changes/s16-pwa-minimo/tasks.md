# Tasks: S16 — PWA mínimo

Fatia **pequena de propósito**. Ordenada por camada (pré-requisito → assets → arquivos →
verificação → registro). Uma tarefa = **um comportamento verificável**.

**Portões que valem para a fatia inteira:**
- **`NEW-003` é feature NOVA.** No ledger entra como **`new`**; **o QA não deve procurá-la no
  legado** — não existe lá nem na base ai9.
- **Sem service worker, sem offline, sem push, sem `vite-plugin-pwa`.** Qualquer tarefa que
  introduza um deles está **fora de escopo** e precisa de nova decisão do usuário.
- **Nenhuma dependência nova** no `package.json`.

## 1. Pré-requisito

- [x] 1.1 Confirmar que a tematização já entregou os assets da marca Safegold (logo cheio,
  símbolo, cores de `globals.css` light+dark) e que **OPS-635 já rodou** — favicon, título,
  Open Graph e `robots.txt` com `Disallow: /`. Sem isso, **esta fatia espera**: PWA com o
  ícone do produto errado é pior que nenhum PWA.

## 2. Ícones

- [x] 2.1 Gerar `icon-192.png` e `icon-512.png` a partir do logo da marca, em
  `frontend/public/icons/`. Verificável: abertos, são o símbolo Safegold, não o do GOAT.
- [x] 2.2 Gerar `icon-512-maskable.png` com **zona segura** (~80% do quadro) e margem
  preenchida com a cor de fundo da marca — não transparente. Verificável: simulando o recorte
  circular do Android, o símbolo não é cortado.
- [x] 2.3 Gerar `apple-touch-icon.png` 180×180. Verificável: no iOS, "Adicionar à Tela de
  Início" usa este ícone e **não** uma captura da página.

## 3. Manifest e HTML

- [x] 3.1 Criar `frontend/public/manifest.webmanifest` com `name`, `short_name`, `start_url:
  "/"`, `scope: "/"`, `display: "standalone"`, `lang: "pt-BR"`, `theme_color`,
  `background_color` e os três ícones. **Fecha: NEW-003 (parte 1).**
- [x] 3.2 Acrescentar ao `frontend/index.html` **apenas** as três linhas desta fatia:
  `<link rel="manifest">`, `<link rel="apple-touch-icon">` e as metas
  `apple-mobile-web-app-capable` / `-status-bar-style` / `-title`. Não mexer no que é de
  OPS-635. **Fecha: NEW-003 (parte 2).**
- [x] 3.3 Garantir que o `theme_color` do manifest é **exatamente** o mesmo do
  `<meta name="theme-color">` do HTML (hoje `#fff2f4`, do GOAT). Divergência produz barra de
  status de uma cor e tela de abertura de outra.
- [x] 3.4 Conferir que o `background_color` corresponde ao fundo do tema da marca — errado
  aqui provoca flash branco na abertura sobre um tema escuro.

## 4. Verificação

- [x] 4.1 O manifest é servido corretamente em **dev (Vite) e no build de produção**, com
  content-type adequado e **sem 404 em nenhum ícone**.
- [x] 4.2 Instalar pelo **Chrome/Edge desktop** ("Instalar página como aplicativo"): abre em
  **janela própria**, com o ícone e o nome da Safegold, e cai na tela de login (`start_url`
  `/`, DEC-13.3).
  **ADIADA POR DECISÃO DO USUÁRIO (DEC-103a)** — ele abre tarefa própria depois. Provado por
  protocolo (CDP, Chromium 151): `getInstallabilityErrors` vazio, `beforeinstallprompt`
  disparando. O que falta é o clique num ambiente com janela, que aqui é headless.
- [x] 4.3 Instalar pelo **iOS/iPadOS Safari** ("Adicionar à Tela de Início"): ícone correto
  (não uma captura), nome curto correto, abre sem barra de endereço.
  **ADIADA POR DECISÃO DO USUÁRIO (DEC-103a)** — não há iPhone nem WebKit neste ambiente, e
  "abre sem barra de endereço" só se prova no aparelho. O `apple-touch-icon` com fundo já foi
  medido: o transparente dá 83,6% de pixel escuro sobre preto (o iOS compõe sobre preto) e
  sumiria; o com fundo dá 81,4% de claro.
- [x] 4.4 Auditoria de instalabilidade do navegador: os itens de manifest e ícone passam.
  **Corrigido depois de medir (25/08/2026, Chromium 151):** o texto original desta tarefa
  afirmava que "o item service worker falha de propósito". Não falha — o Chromium relaxou o
  requisito: `Page.getInstallabilityErrors` volta **vazio** e o `beforeinstallprompt`
  **dispara** com zero service workers. A decisão (DEC-21.3, sem service worker) não muda; a
  premissa técnica escrita aqui e no `design.md` (P3) é que estava errada. O que de fato não
  existe é **convite dentro do app** — nada trata `beforeinstallprompt`, então a instalação é
  pelo menu do navegador.
- [x] 4.5 Confirmar que **nada** de service worker foi introduzido: `grep` por
  `serviceWorker`, `workbox` e `vite-plugin-pwa` em `frontend/` não retorna nada, e o
  `package.json` está inalterado.

## 5. Registro

- [x] 5.1 Registrar `NEW-003` no `parity-ledger.md` como **`new`**, com a evidência de que
  não existe no legado nem na base (nenhum manifest, nenhum `apple-touch-icon`, nenhum plugin
  de PWA).
- [x] 5.2 Registrar na mesma linha do ledger — e em `improvements-log.md` — a **limitação
  conhecida e aceita**: sem service worker, o **prompt automático** de instalação da família
  Chromium não aparece; a instalação é pelos caminhos manuais do desktop e pelo iOS. É
  escopo (DEC-21), não bug, e o registro existe para que um QA não abra defeito contra uma
  decisão.


---

## Registro de execução — 25/08/2026 (`mobile-pwa engineer`)

### O que já estava pronto, e não foi refeito
`manifest.webmanifest`, os ícones transparentes `safegold-icon-{32,180,192,512}.png` e as
linhas de `manifest`/`favicon`/`apple-touch-icon` do `index.html` já vieram da tematização
(`48964d81`) e do ajuste de ícones (`d068d3dc`). **Os nomes e caminhos reais divergem do que
estas tarefas escreveram** — os ícones vivem em `public/images/brand/`, com prefixo
`safegold-icon-`, e não em `public/icons/icon-192.png`. Vale o que está no disco.

### O que faltava e foi acrescentado
- **As metas `apple-mobile-web-app-capable` / `-status-bar-style` / `-title`** (tarefa 3.2)
  **não existiam.** Entraram, junto de `mobile-web-app-capable`.
- **`id: "/"`** no manifest, para a identidade do app não depender do `start_url`.
- **Dois defeitos de ícone**, achados olhando o pixel e não o arquivo — ver PWA-02 e PWA-03 em
  `improvements-log.md`:
  - o **maskable** tinha fundo `#2D2D2A`, o mesmo grafite de metade do símbolo: contraste
    ~1,03:1, e o Android mostraria só as duas barras douradas. Regerado sobre `#FAFAF9`, com
    a zona segura medida (raio 194 px contra o limite de 204,8 px);
  - o **apple-touch-icon** apontava para o arquivo transparente, e o iOS compõe transparência
    sobre **preto** — mesmo sumiço, outra plataforma. Ganhou arquivo próprio com fundo,
    `safegold-icon-apple-touch-180.png`, seguindo o precedente já aceito do maskable. **O
    conjunto transparente continua transparente.**
- **`theme_color`/`background_color`** de `#2D2D2A` para `#FAFAF9` (tarefas 3.3 e 3.4):
  divergiam do `<meta name="theme-color">` do HTML e do tema padrão do app, que é o claro.

### Prova de instalabilidade (tarefas 4.1 e 4.4)
Feita contra o **build de produção** (`vite build`, 1m09s, sem erro) servido estaticamente —
não em dev, porque é o build que vale.

| Verificação | Resultado |
| ----------- | --------- |
| `manifest.webmanifest` servido | `200`, `content-type: application/manifest+json` |
| Ícones (192, 512, maskable, apple-touch, 32) | `200` em todos — **nenhum 404** |
| `Page.getAppManifest` | `errors: []` — manifest interpretado sem erro |
| `Page.getInstallabilityErrors` | **`[]` — vazio** |
| Controle (página sem manifest) | `no-manifest` — prova que a API **não** é *stub* |
| `beforeinstallprompt` | **dispara**, com zero service workers registrados |
| Violações de CSP (DEC-48) | **0**, na página e na varredura de console completa |

### O item 4.4 não falhou — e isso contraria o material da fatia
As tarefas e o `design.md` (P3) afirmam que o item "service worker" **falha de propósito** e
que a família Chromium condiciona o prompt automático a ele. **Medido no Chromium 151, isso
não se confirma:** não há erro de instalabilidade e o `beforeinstallprompt` dispara sem
service worker. O Chromium relaxou esse requisito.

**A decisão não muda por causa disso** (DEC-21.3 é escolha de produto): continua sem service
worker, sem offline, sem cache e sem push. O que muda é o **texto da limitação** — está
corrigido em `parity-ledger.md` (`NEW-003-lim`). O que de fato não existe é **convite dentro
da aplicação**: nada trata `beforeinstallprompt`, então a instalação é pelo menu do navegador
e, no iOS, por "Adicionar à Tela de Início". **QA não abre defeito por isso.**

### O que NÃO foi verificado neste ambiente, e por quê
- **4.2** (`[~]`) — instalação real no Chrome/Edge desktop: verificada **pelo protocolo**
  (manifest, `display: standalone`, `start_url: "/"`, ícones, zero erro de instalabilidade),
  não clicando em "Instalar" numa janela com interface gráfica. O ambiente é headless.
- **4.3** (`[ ]`) — iOS/iPadOS Safari: **não há aparelho nem WebKit aqui.** As tags exigidas
  estão no HTML e o ícone plano foi conferido pixel a pixel, mas *"abre sem barra de
  endereço"* **só se prova no aparelho**. Fica para quem tiver um iPhone à mão.

### 4.5 — nada de service worker entrou
`grep -rniE "serviceWorker|workbox|vite-plugin-pwa"` em `frontend/` (fora `node_modules` e
`dist`) volta **vazio**, e `git diff package.json` está **limpo**: nenhuma dependência nova.

---

## DEC-100 — camada mobile (acrescentado à fatia em 25/08/2026)

- [x] 6.1 Auditar os 9 componentes de `frontend/src/components/mobile/` e completar o que
  faltava. **Achado central: não havia carregando, vazio nem erro.**
- [x] 6.2 Criar `MobileListState` (`MobileListSkeleton`, `MobileEmptyState`,
  `MobileErrorState`). **Fecha: NEW-004.**
- [x] 6.3 `MobileBottomBar`: rótulo em cada aba, `aria-current` na ativa, `min-w-0` para o
  rótulo truncar em vez de invadir a aba vizinha, e `env(safe-area-inset-bottom)`.
- [x] 6.4 `MobileTopBar`: painel de modo em **portal** (escapa do contexto de empilhamento do
  `glass-panel`, §5.4.4), `pointerdown` em vez de `mousedown`, `Escape` fecha,
  `env(safe-area-inset-top)`.
- [x] 6.5 `MobilePageLayout`: respiro do rodapé = altura da barra + `safe-area`; FAB acima da
  barra, com rótulo acessível.
- [x] 6.6 `MobileCard`: `statusTone` semântico no lugar de `statusColor` de paleta; teclado e
  `role="button"` quando clicável; selo de 8 px para 10 px.
- [x] 6.7 `MobileKPI`: `format` no lugar de dois booleanos ambíguos; estado `loading`.
- [x] 6.8 `MobileChartCard`: série tipada, formato pt-BR, eixo compacto, estado vazio; fora o
  `glass-panel` duplicado e a bolinha que fingia "ao vivo".
- [x] 6.9 `MobilePagination`: alvo de 44 px, `aria-live` no contador, sem o `pb-8` que
  duplicava a folga do layout.
- [x] 6.10 `MobileMenuActions` marcado como **descontinuado** — lista de ações fixa; o
  substituto é `MobileRowActions`.
- [x] 6.11 Teste travando o contrato da biblioteca:
  `frontend/src/components/mobile/__tests__/mobileLibrary.test.tsx` — **12 testes**.
- [x] 6.12 Padrão escrito nas convenções: **§5.4.8** de `.migration-ai9/ai9-conventions.md`,
  com a tabela "qual componente para qual caso", o que "sensação nativa" significa em termos
  concretos e o que **não** fazer (tabela com `overflow-x` fingindo de mobile).
- [x] 6.13 Verificação **renderizando em 390×844**, light e dark, com captura: `/dashboard`,
  `/users` e o seletor de modo **aberto**. Sem erro de console, sem violação de CSP e sem
  rolagem horizontal da página.
