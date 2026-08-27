## ADDED Requirements

### Requirement: NEW-003 — Console instalável com manifest e ícones (FEATURE NOVA, não paridade)
O ai9 **MUST** servir um `manifest.webmanifest` estático a partir de `frontend/public/`,
declarando `name`, `short_name`, `start_url: "/"`, `scope: "/"`, `display: "standalone"`,
`lang: "pt-BR"`, `theme_color`, `background_color` e ícones de **192×192**, **512×512** e
**512×512 com `purpose: "maskable"`**; e **MUST** declarar no `index.html` o
`<link rel="manifest">` e um `apple-touch-icon` de 180×180, além das metas
`apple-mobile-web-app-*`.

> **Esta é uma feature nova (DEC-21), não paridade.** Ela **NÃO existe no legado** e **NÃO
> deve ser procurada lá** pelo QA do Phase 4 — e também não existe na base ai9: não há
> manifest, não há `apple-touch-icon`, não há referência a `standalone` e não há plugin de
> PWA no `package.json`. No `parity-ledger.md` entra como **`new`**.

O ai9 **MUST NOT**, nesta fatia, registrar service worker, implementar comportamento offline,
cache de app shell, push ou sincronização em segundo plano, nem acrescentar dependência de
build para PWA. **Consequência aceita e registrada:** sem service worker, os navegadores que
exigem um para o prompt automático de instalação **não** exibirão o convite; a instalação
ocorre pelos caminhos manuais (iOS "Adicionar à Tela de Início" e "Instalar página como
aplicativo" no desktop). Isto é decisão de escopo, **não** defeito.

O `theme_color` do manifest e o `<meta name="theme-color">` do HTML **MUST** ter o mesmo
valor, e os ícones **MUST** ser os da marca do produto — nunca os herdados da base.

#### Scenario: instalação pelo desktop
- **GIVEN** o console servido em produção
- **WHEN** o usuário instala a página como aplicativo pelo navegador
- **THEN** o app abre em janela própria, sem barra de endereço, com o ícone e o nome da marca, na tela de login

#### Scenario: adicionar à tela de início no iOS
- **GIVEN** o console aberto no Safari do iOS
- **WHEN** o usuário usa "Adicionar à Tela de Início"
- **THEN** o ícone usado é o `apple-touch-icon` declarado, e não uma captura da página

#### Scenario: ícone maskable no Android
- **GIVEN** o ícone maskable com zona segura
- **WHEN** o sistema aplica o recorte circular
- **THEN** o símbolo aparece inteiro, sobre a cor de fundo da marca, sem corte

#### Scenario: nenhum service worker é registrado
- **GIVEN** o console carregado
- **WHEN** os service workers registrados são inspecionados
- **THEN** não há nenhum, e nenhuma resposta é servida a partir de cache de aplicação

#### Scenario: manifest e HTML concordam na cor
- **GIVEN** o `theme_color` do manifest e o `<meta name="theme-color">`
- **WHEN** o app instalado é aberto
- **THEN** a tela de abertura e a barra de status usam a mesma cor da marca
