# Tasks: S17 — Temas → **Marca em fonte única**

> **ESTA FATIA ENCOLHEU. Leia este bloco antes das tarefas.**
>
> As 36 tarefas abaixo foram escritas quando a S17 era *"CRUD de temas com precedência e
> tokens em runtime"*. Duas decisões cortaram a maior parte delas, e **a DEC vence a tarefa**:
>
> - **DEC-55 — a área de temas NÃO é portada.** Marca e paleta vivem como **tokens**; o
>   claro/escuro fica no `ThemeToggle` que a base já tem. O motivo é medido, não estético: o
>   motor do legado **não pintava nada**. `app_theme_template.css` tem 167 linhas e o arquivo
>   **inteiro** está dentro de um comentário — abre `/*` na linha 1, fecha `*/` na 167, **zero
>   regras fora dele** (defeito **D-55**) — e o parser continuava rodando em cima disso
>   (`app_theme.rb:207-231`), gravando um comentário CSS inteiro em `cached_css`. A área
>   também não tinha item de menu (**D-63**): três telas, nenhuma alcançável pelo produto.
> - **DEC-56 — `UserTheme` é descartado.** A precedência passa a ter **dois** níveis, não três.
>   `user_theme.rb:2` declarava `has_many :users` e a coluna existia, mas o `select` do
>   formulário oferecia **apenas** `GlobalTheme` (`themes/form/_body.html.erb:36`): `UserTheme`
>   era **inalcançável pela UI** e nada nunca o escreveu.
>
> **O custo, registrado e aceito pelo usuário (DEC-55):** trocar o logo passa a exigir
> **deploy**. A alternativa (tema como configuração única editável) foi oferecida e recusada.
>
> **Tarefa riscada não é tarefa esquecida.** Cada uma abaixo mantém o texto original com o
> motivo do corte ao lado, e o ID correspondente está no `parity-ledger.md` como `dropped`
> **com evidência** — nunca `dropped` por omissão.

**Portões que valem para a fatia inteira:**
- ~~**Autorização primeiro.** Nenhum endpoint de tema é escrito sem o gate de papel no mesmo
  commit. O defeito do legado (BE-384) é anônimo trocando o tema global.~~
  **Anulado por DEC-55** — e é o melhor jeito de fechar o buraco: **não existe endpoint de
  tema**. `BE-384` deixa de ser uma superfície a proteger e passa a ser uma superfície que
  não existe. Há um teste que garante que ela não volte
  (`frontend/src/__tests__/marca-fonte-unica.test.ts`).
- ~~**`override_css` é campo de risco alto.**~~ **Anulado por DEC-55** — o campo não existe em
  lugar nenhum do ai9. O mesmo teste falha se a string reaparecer.
- **A paleta não se decide aqui.** Cor vem da tematização. **Continua valendo.**
- Nada em `frontend/` é reescrito: o mecanismo (`globals.css`, `useTheme.ts`,
  `ThemeToggle.tsx`) é **reuso** (Princípio 6b). **Continua valendo** — inclusive depois do
  DEC-101, que tirou o prazo mas **não** virou licença para re-arquitetar o design system.

## 1. Dados e seed

- [x] ~~1.1 Migration `create_app_themes` com `type` (STI), `title`, `primary_color`, cores
  secundárias, fontes, `override_css`, `user_id` e `is_default`.~~
  **Anulada por DEC-55.** A tabela não é criada. `DB-548` e `DB-388` → `dropped`. Colunas de
  um motor que nunca pintou um pixel não viram esquema.
- [x] ~~1.2 Índice **único parcial** `where: "is_default"`.~~
  **Anulada por DEC-55** — sem tabela, não há índice. O defeito **D-59** (dois globais padrão
  ao mesmo tempo, porque a garantia era callback e não banco) some junto com a tabela.
- [x] ~~1.3 Model `AppTheme` + STI `GlobalTheme` / `UserTheme`.~~
  **Anulada por DEC-56.** `BE-379` → `dropped`: `UserTheme` era inalcançável pela UI e nada o
  escrevia. No ai9 a preferência por usuário já existe como **claro/escuro**, que é o controle
  que o usuário corporativo espera.
- [x] ~~1.4 Ligar `users.app_theme_id` ao `AppTheme`, com índice.~~
  **Anulada por DEC-56.** A coluna **não deveria existir**, e existe: nasceu na migration de
  `users` de S1 (`20260825130000_add_safegold_identity_columns_to_users.rb:58,90`), escrita
  **antes** da decisão. Está registrada como dívida no `improvements-log.md` para o dono de S1
  remover — esta fatia **não** mexe em `db/schema.rb`, que está sendo editado por outros
  agentes agora (armadilha 1 e 2 do `checkpoint.md`).
- [x] ~~1.5 Seed de referência idempotente do `GlobalTheme` da Safegold.~~
  **Anulada por DEC-55.** `OPS-543` → `dropped`. A marca canônica não é linha de banco: é
  token em `globals.css` e arquivo versionado em `public/images/brand/`. `BE-382` **sobrevive
  com outro alvo** — a fonte de verdade existe, só não é o seed.

## 2. Resolução do tema efetivo

- [x] ~~2.1 `Sfg::Themes::EffectiveThemeService` — `UserTheme` → `GlobalTheme` padrão →
  tokens de fábrica.~~
  **Anulada por DEC-55/56.** Com `UserTheme` fora e sem `GlobalTheme`, sobram os "tokens de
  fábrica" — que é o único degrau que sempre pintou. `BE-380` → **`migrated` reduzido**: a
  resolução existe, tem **dois** níveis (claro/escuro) e vive em `useTheme.ts`, não num
  serviço do servidor.
- [x] ~~2.2 Endpoint de leitura do tema efetivo.~~ **Anulada por DEC-55.**
- [x] ~~2.3 Teste de precedência com os três degraus.~~
  **Anulada por DEC-56** — não há três degraus. O teste que sobrou é outro e existe:
  `marca-fonte-unica.test.ts` prova que nenhuma tela reimplementa cor por fora do token.

## 3. Autorização

- [x] ~~3.1 Todos os endpoints de tema exigem sessão (401 para anônimo nos cinco verbos).~~
  **Anulada por DEC-55** — zero endpoints.
- [x] ~~3.2 Escrita restrita a og/admin (DEC-19), verificada no servidor.~~ **Anulada por DEC-55.**
- [x] ~~3.3 `override_css` rejeitado pelo servidor quando enviado por papel insuficiente.~~
  **Anulada por DEC-55.**
- [x] 3.4 **(nova, e é o que sobrou desta seção)** Remover a política de anexo
  `public_brand`, que ficou órfã com a área de temas. Era a **única** que devolvia `true` sem
  olhar o usuário — anexo legível antes de existir sessão, porque a tela de login precisava do
  logo do tema. Política de "todo mundo, inclusive anônimo" **sem consumidor** é arma
  carregada: a próxima linha de catálogo que a escolhesse por engano abriria o anexo para a
  internet. Feito em `backend/app/lib/sfg/attachments.rb`, com o motivo escrito no lugar.
  Verificado: nenhuma entrada de `config/attachments.yml` referencia política inexistente.

## 4. Endpoints

- [x] ~~4.1 `GET /api/v1/themes` com filtro, ordenação e paginação real.~~ **Anulada por
  DEC-55.** `BE-370` → `dropped`.
- [x] ~~4.2 `POST /api/v1/themes`.~~ **Anulada por DEC-55.** `BE-371` → `dropped`.
- [x] ~~4.3 `PATCH /api/v1/themes/:id`.~~ **Anulada por DEC-55.** `BE-372` → `dropped`.
- [x] ~~4.4 `DELETE /api/v1/themes/:id` com 422 e motivo.~~ **Anulada por DEC-55.** `BE-373`
  → `dropped`.
- [x] ~~4.5 `POST /api/v1/themes/:id/activate`.~~ **Anulada por DEC-55.** `BE-374` → `dropped`.

## 5. Tokens e marca — **a fatia inteira mora aqui**

- [x] ~~5.1 O tema efetivo é aplicado como custom properties na raiz; nenhum CSS é gerado nem
  cacheado.~~ **Reinterpretada por DEC-55, e entregue.** Os tokens **são** custom properties
  na raiz (`frontend/src/styles/globals.css`, três blocos: `:root`, `.dark`, `.surface-dark`).
  O que caiu foi a origem: vêm do build, não de `cached_css`. `BE-377` → `dropped` como
  *motor*, porque o motor era o defeito.
- [x] ~~5.2 `override_css` injetado depois dos tokens e sanitizado.~~
  **Anulada por DEC-55.** `BE-378` → `dropped`. **A evidência é o próprio ID:** `BE-378` é
  literalmente *"o motor de temas não pinta nada — template 100% comentado, `override_css`
  inerte, campos mortos"*. Portar um campo cuja definição de paridade é "não tem efeito"
  seria portar o defeito.
- [x] 5.3 **Fonte única de marca.** `components/brand/Logo.tsx` é a única fonte visual, e
  `LOGO_SRC` é o catálogo de arquivos — exportado porque o JSON-LD de `SEO.tsx` precisa do
  **caminho** e não pode renderizar um componente. Verificado por teste, não por `grep` de uma
  vez só: `marca-fonte-unica.test.ts` reprova qualquer arquivo fora do `Logo.tsx` que cite
  `/images/brand/safegold-(logo|wordmark|symbol)`. **Fecha: BE-383, OPS-603, OPS-750.**
- [x] 5.4 As telas de sessão leem os mesmos tokens. `LoginPage`, `OAuthCallbackPage`,
  `MagicLinkCallbackPage` e `CodeValidation` usam `<Logo>` e classes de token; nenhuma
  configuração de UI de autenticação foi portada. **Fecha: OPS-606.**
- [x] 5.5 `#504746` (o `primary_color` do kit de UI legado) registrado no `parity-ledger.md`
  como **valor de referência do QA** — é o que o Phase 4 compara para saber que a cor mudou
  **de propósito**, e não por acidente. **Fecha: OPS-750 (parte).**
- [x] 5.6 **(nova — DEC-93)** Variante **monocromática** do logo. No legado, `SFG/theme.rb:47-57`
  declarava `_WHITE` e `_MONO` apontando **todas para o mesmo arquivo colorido**: logo branco e
  logo monocromático **nunca existiram**. As seis artes `*-mono*.png` foram **derivadas** do
  canal alfa da arte colorida, preenchido com uma cor só (`--brand-ink` no claro, o branco
  morno da marca no escuro), e a derivação está escrita no `Logo.tsx`. Exposta como
  `<Logo tone="mono">`. Se o manual de marca aparecer, o original vence — e a troca é de
  arquivo, não de código.

## 6. Dois modos

- [x] 6.1 Paleta dark da Safegold nos tokens de `globals.css` — **consumida**, não escolhida.
  Grafite `#2D2D2A` e ouro `#FFC107`, confirmados por **medição** (DEC-68: a amostragem do PNG
  do logo deu `#292C28`, refutando o `#050517` do SCSS). **Fecha: BE-381 (parte).**
- [x] 6.2 Contraste verificado nos **dois** modos, em **todas** as telas construídas e em
  **duas** larguras (1440×900 e 390×844, DEC-100), com resultado registrado. A verificação é
  por `getComputedStyle` no DOM vivo, não por leitura de código: `tsc` limpo convive
  perfeitamente com um popover invisível — já conviveu. **Fecha: BE-381.**
- [x] 6.3 Registrado no `improvements-log.md` que dark mode é **ganho, não paridade** — o QA
  do Phase 4 **não deve procurá-lo no legado** (`STYLE__DARK` existe lá, com a opção
  comentada).

## 7. Telas

- [x] ~~7.1 Rota SPA `/console/themes` + entrada em `CONSOLE_NAV_ITEMS`.~~
  **Anulada por DEC-55.** `BE-376` → `dropped`. Nota: no legado a área **também** não tinha
  item de menu (D-63) — a diferença é que agora a ausência é deliberada e testada.
- [x] ~~7.2 Lista de temas com paginação e ordenação.~~ **Anulada por DEC-55.** `FE-385` →
  `dropped`.
- [x] ~~7.3 Detalhe do tema.~~ **Anulada por DEC-55.** `FE-387` → `dropped`.
- [x] ~~7.4 Formulário novo/editar — cores, logos, fontes; `override_css` só para og/admin.~~
  **Anulada por DEC-55.** `FE-386` → `dropped`.
- [x] ~~7.5 As quatro actions que respondiam erro no legado passam a ser rotas alcançáveis.~~
  **Anulada por DEC-55.** `BE-375` → `dropped`. As quatro actions apontavam para templates
  inexistentes e davam 500 em toda chamada; não há comportamento a preservar.

## 8. Anexos

- [x] ~~8.1 Os 4 anexos do tema usam o motor único de S13.~~
  **Anulada por DEC-55**, e a limpeza foi feita: o catálogo `app_theme` (4 anexos) saiu de
  `backend/config/attachments.yml`, com o motivo no lugar dele. `OPS-499` → `dropped`.
  **O que NÃO se perdeu:** a regra de que falta de imagem de marca **não pode derrubar envio
  de e-mail** (uma das duas quebras do `BE-485`, onde o legado fazia `File.new(...)` no arquivo
  do tema dentro do mailer). Ela agora vale **por construção** — o layout de e-mail não abre
  arquivo nenhum.
- [x] ~~8.2 Validação por magic bytes.~~ **Anulada por DEC-55** quanto ao tema. A regra em si
  **continua valendo para todo o resto** e é do motor de S13, que já a implementa.
- [x] ~~8.3 Variantes de imagem por anexo.~~ **Anulada por DEC-55.** `OPS-389` → `dropped`.

## 9. Paridade e fechamento

- [x] 9.1 Os **25 IDs** desta fatia conferidos contra `.migration-ai9/parity-ledger.md`:
  **18 `dropped` com evidência nomeada** (nenhum por omissão) e **7 `migrated`**. Nenhum
  `blocked`, nenhum `pending`.
- [x] 9.2 Registradas no `improvements-log.md` as mudanças visíveis — com atenção às duas que
  a proposta original prometia e que **não** acontecem mais: *"o tema passa a pintar"* e
  *"`override_css` passa a ter efeito"*. Um QA que leia a proposta antiga procuraria as duas.
- [x] 9.3 Registrada a evidência de que os campos mortos do legado não viram colunas: o
  template `app_theme_template.css` está **100% comentado** (`/*` na linha 1, `*/` na 167).
  É o **D-55**, e é o que sustenta 18 dos 25 descartes.
- [x] 9.4 `BE-379` e `BE-382` constam apenas aqui como donos. `BE-379` fecha como `dropped`
  (DEC-56); `BE-382` fecha como `migrated` com alvo trocado — a marca canônica existe, em
  token e arquivo, não em seed de banco.

## 10. Varredura de fonte única — **o portão que sobrou desta fatia**

- [x] 10.1 Varredura de **todo** `frontend/src`, comentários descontados: zero `#hex`, zero
  `rgb()/rgba()/hsl()` com número cravado, zero classe de paleta literal do Tailwind
  (`slate-`, `blue-`, `white`, `black`…), zero `z-[…]`, zero `shadow-[…]`/`rounded-[…]`, e
  zero variante `dark:` consertando cor. Congelada em
  `frontend/src/__tests__/marca-fonte-unica.test.ts` — 26 casos — para que a próxima tela
  nasça sob a regra em vez de ser auditada depois.
- [x] 10.2 Os **9 componentes de `components/mobile/`** (DEC-100) incluídos na varredura.
  Resultado: **limpos**. Onde há cor em `style={{}}` é `hsl(var(--token))`, que é o token
  escrito como string porque Recharts não aceita classe Tailwind — e já estava explicado em
  comentário no `MobileChartCard.tsx`.
- [x] 10.3 Varredura **no DOM vivo**, que é a que pega o que o `grep` não pega: para cada tela
  × modo × largura, a paleta de tokens é resolvida no documento (nos **três** blocos: raiz,
  `.dark` e `.surface-dark`) e **todo** elemento visível é percorrido atrás de cor **opaca**
  que não saia de nenhum token. Cor com alpha < 1 é derivada de token por opacidade e não
  conta. **19 telas × 2 modos × 2 larguras = 76 renderizações; resultado final: 0 cores de
  fora, 0 reprovações de contraste.**
  A primeira passada não deu isso — deu **2** "cores de fora" e **20** reprovações de
  contraste, e as duas listas ensinaram coisas diferentes:
  - As 2 "cores de fora" eram **falso positivo do próprio verificador**: o painel do login usa
    `.surface-dark`, que redefine a paleta localmente, e o verificador só resolvia os tokens na
    raiz. Corrigido no verificador, não no app.
  - As 20 de contraste eram **reais**, e 18 delas tinham **uma causa só**: o ouro
    `#FFC107` usado como TEXTO no claro (1,63:1). Corrigido nos tokens — ver 10.4.
- [x] 10.4 **Correção de contraste, no token e em um lugar só.** `--primary` servia ao fundo do
  botão (ouro cheio, grafite por cima, 10,4:1) e ao texto de 12px (1,63:1) ao mesmo tempo, e um
  valor não serve aos dois: clarear conserta o texto e estraga o botão. Entraram seis tokens
  `-text` nos três blocos e o `tailwind.config.js` passou a mapear **só `textColor`** para
  eles. **Nenhuma das 125 chamadas de `text-primary` mudou** — e `--primary` continua sendo
  exatamente o ouro medido no logo (DEC-68). Junto, `--destructive` do escuro foi de 55% para
  53%: o branco do próprio botão de apagar estava em 4,36:1.
- [x] 10.5 **Superfície flutuante ABERTA** nos dois modos e nas duas larguras — select,
  autocomplete, dialog, tooltip e os menus do shell. Medido por `getComputedStyle`, **nunca por
  pixel**: no headless com `--disable-gpu` o `backdrop-filter` compõe errado e pinta o painel
  com a cor de trás, e uma fatia anterior quase abriu defeito que não existia por causa disso.
  Três coisas por painel: (1) tem área, (2) o fundo é **opaco e diferente** do que está atrás —
  um popover só existe se der para ver que é um popover, (3) o texto de dentro passa AA contra
  o fundo **dele**, não contra o da página. **Zero problemas.** No escuro o dialog mede
  `rgb(48,48,44)` sobre `rgb(24,24,22)`: a escala `background` 9% → `card` 12% → `popover` 18%
  se sustenta, que é exatamente o que faltava quando `--popover` esteve 1% acima de `--card` e
  o painel aberto parecia transparente.
