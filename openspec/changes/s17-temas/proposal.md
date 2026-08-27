# Proposal: S17 — Temas: o tema como produto (CRUD, precedência, tokens em runtime)

> Fatia **S17** da ordem de execução de `.migration-ai9/migration-map.md`.
> Bloco de origem: `.migration-ai9/map/data-infra.md` — capability `themes` (§2.6), fatia
> interna **S-12** ("Tema como produto") mais a parte de marca da fatia interna **S-02**.
> Depende de **S2** (casca do console) e de **S13** (motor único de anexos).
>
> **Por que esta fatia existe:** a conferência consolidada do fim do Phase 2 mostrou que os
> **21 IDs de `themes` não tinham dono nenhum**. Cada uma das 17 fatias estava correta
> internamente; a capability inteira caiu no vão entre elas. Um ID sem fatia não vira tarefa,
> não vira código e não é procurado no Phase 4 — é exatamente a perda silenciosa de feature
> que esta migração existe para impedir.

## Why

O Safegold **é vendido com a marca do cliente**. O legado levou isso a sério o bastante para
criar uma entidade (`AppTheme`, STI `GlobalTheme`/`UserTheme`), quatro anexos de imagem, um
formulário com cores, fontes e CSS custom, e um motor de geração de folha de estilo. E então
**não ligou nada disso na tela**:

1. **O motor não pinta nada.** `app/frontend/css/pub/templates/app_theme_template.css` está
   **100% comentado** — `generate_template` → `parse_template` → `cached_css` produz uma
   folha vazia. O usuário edita cor primária, salva com sucesso, e nada muda.
2. **`override_css` é aceito, validado, persistido e nunca chega ao HTML.** É um campo de
   texto livre que o usuário preenche achando que está customizando o produto.
3. **Os endpoints de tema não têm autenticação nem autorização.** `app_themes_controller`
   não exige sessão e não checa papel: **qualquer visitante** cria, edita, exclui e ativa o
   tema global do sistema (BE-384). É o defeito mais grave da capability.
4. **Quatro actions respondem erro** (`index`, `show`, `new`, `edit` — BE-375): as views
   existem em `app/views/pub/console/parts/themes/`, e nenhuma rota alcançável chega nelas.
5. **Dark mode não existe.** `STYLE__DARK` existe como constante, `beauty_style` sabe
   traduzi-la, e a opção está **comentada** na interface.

Do lado do ai9 o quadro é o inverso: **o mecanismo já existe e está pronto** —
`frontend/src/styles/globals.css` tem a camada `.dark`, `useTheme.ts` alterna, `ThemeToggle`
existe, e `tailwind.config` lê tokens CSS. O que não existe é **um tema como dado**: nada no
ai9 permite a um administrador definir a marca sem tocar em código.

**A soma disso é uma fatia barata com valor de demonstração alto**: o mecanismo é reuso, a
entidade é `build`, e o resultado é o produto abrindo com a marca do cliente — em claro **e
em escuro**, que é ganho novo e registrado como tal.

## What Changes

**25 IDs** — os 23 órfãos da conferência consolidada mais **`BE-379`** e **`BE-382`**, que
tinham **dois donos por engano** (citados em S13 e em S14 como "tematização", que não era
fatia nenhuma) e passam a ter **um**: esta. A tabela item-a-item está em `.migration-ai9/map/data-infra.md` §2.6 e §2.1
(`DB-548`) — aqui a estratégia e o alvo, sem duplicar as colunas do mapa.

### A. Entidade, dados e seed — 4 IDs

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| DB-548 | build | Tabela `app_themes` + `AppTheme`, STI `GlobalTheme`/`UserTheme`; um único global padrão garantido por **índice único parcial** (`where is_default`), não por callback |
| DB-388 | build | O mesmo esquema visto do lado da capability `themes`, mais `users.app_theme_id` (a coluna nasce na migration de `users` de S1 e é **usada** aqui) |
| OPS-543 | build | `AppThemeFactory` vira **seed de referência idempotente** do `GlobalTheme` da Safegold, aplicado pelo deploy |
| OPS-389 | adapt | Pipeline de imagem dos 4 anexos: ActiveStorage + variantes. O legado usava Paperclip **com detecção de spoof desligada** (`do_not_validate_attachment_file_type`) — aqui a validação por **magic bytes** (motor de S13) é obrigatória |

### B. Endpoints e regras — 13 IDs

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| BE-370 | build | `GET /api/v1/themes` — filtro, ordenação e **paginação funcionando**. O legado normaliza `q`/`l`/`o` e depois faz `AppTheme.all` cru |
| BE-371 | build | `POST /api/v1/themes` |
| BE-372 | build | `PATCH /api/v1/themes/:id` |
| BE-373 | build | `DELETE /api/v1/themes/:id` — a guarda do model (não se exclui tema em uso nem o padrão) responde **422 com motivo**, não `:ok` |
| BE-374 | build | `POST /api/v1/themes/:id/activate` — tornar padrão, com o índice único parcial como rede |
| BE-375 | build | As 4 actions quebradas viram **rotas reais do front** (lista, detalhe, novo, editar) |
| BE-376 | build | Rota SPA `/console/themes` + item de menu (consome `CONSOLE_NAV_ITEMS`, de S2) |
| BE-377 | build | Motor de CSS vira **tokens CSS em runtime**: o tema efetivo é servido como custom properties, sem geração e cache de folha de estilo em disco |
| BE-378 | build | `override_css` **passa a ser renderizado**, depois dos tokens — e **só admin/og o vê e o envia** (DEC-19). O servidor **rejeita o campo** se enviado por quem não tem o papel |
| BE-380 | build | Precedência de tema efetivo em **uma única resolução**: `UserTheme` do usuário → `GlobalTheme` padrão → tokens de fábrica |
| BE-384 | adapt | Autenticação e autorização nos endpoints de tema — fecha o buraco em que **qualquer anônimo** trocava o tema global |
| BE-379 | build? → build | Tipos de tema: a STI `GlobalTheme`/`UserTheme` **fica** (é o que dá "tema do sistema" e "tema do usuário" sem duas tabelas). A dúvida do mapa era se `UserTheme` sobreviveria sem tela — resolvida em **Q-19**: o modelo fica, a tela do usuário não entra nesta fatia |
| BE-382 | build? → build | Marca canônica: **um** `GlobalTheme` padrão semeado com a marca Safegold é a fonte de verdade de `app_name`, logos e cor primária. A dúvida era de onde vem o valor canônico; resolvida: do seed de referência (`OPS-543`), não de constante em código |

### C. Marca, tokens e dark mode — 5 IDs

| ID | Estratégia | O que é |
| -- | ---------- | ------- |
| BE-381 | build | **Dark mode passa a existir.** O mecanismo é 100% reuso (`globals.css` `.dark`, `useTheme.ts`, `ThemeToggle.tsx`); a paleta é 100% nova e sai da tematização |
| BE-383 | build | Onde o tema realmente aparece: logos, `display_name` e `copyright` — em **fonte única**, consumida por barra, telas de sessão e layout de e-mail |
| OPS-603 | adapt | A carga explícita de definições de marca do legado vira **um** ponto de configuração de marca, não constantes espalhadas |
| OPS-606 | adapt | Configuração da UI de autenticação (`Livetat::AuthUx19`) — as telas de sessão passam a ler os mesmos tokens |
| OPS-750 | build | `Livetat::UxKit19::Configuration` (`app_name`, `primary_color` = `#504746`) vira token de marca, e o valor legado fica registrado como referência do QA |

### D. Telas — 3 IDs

`FE-385` (lista, com paginação e ordenação reais), `FE-386` (formulário: cores, logos,
fontes, `override_css` sob gate de papel), `FE-387` (detalhe).

## Mudanças visíveis, decididas e registradas

Para o QA do Phase 4 não ler nenhuma delas como regressão — todas vão para
`improvements-log.md`:

1. **O tema passa a pintar.** No legado, salvar cor primária não mudava nada.
2. **`override_css` passa a ter efeito** — e passa a ser restrito a admin/og, sanitizado, e
   rejeitado no servidor se vier de outro papel. **Risco alto de segurança**: CSS arbitrário
   é vetor de exfiltração visual; por isso o gate é no servidor, não na tela.
3. **Anônimo deixa de poder trocar o tema global.**
4. **Dark mode passa a existir** (feature nova em relação ao legado, contraste mínimo AA nos
   dois modos, default claro).
5. **Lista de temas ganha paginação e ordenação de verdade.**
6. **Exclusão bloqueada responde 422 com motivo**, em vez de sucesso silencioso.

## Descartes com evidência

| ID | Motivo registrado |
| -- | ----------------- |
| — | **Nenhum ID desta fatia é `drop`.** Os campos mortos do legado (`secondary_color` e afins que o template comentado nunca lia) **não** viram colunas: a evidência é o template 100% comentado em `app_theme_template.css:1-…`, e o registro fica na linha de `BE-378` do ledger, não como descarte de ID |

## Fronteiras — dono único de cada ID (contrato C4)

- **Os dois `build?` de tema são desta fatia** (tabela B acima). Estavam citados em **S13**
  ("Como cada `build?` foi resolvido") e em **S14** ("Os `build?` desta fatia") como
  "tematização", que **não era fatia nenhuma** — dois donos que apontavam um para o outro.
  Agora o dono é S17; S13 e S14 apenas os citam, na Fronteiras de cada uma.
- **O motor de anexos é de S13** (`OPS-491..499`, incluindo `OPS-499`, os anexos do tema).
  S17 **consome** o motor e a validação por magic bytes; não cria um segundo caminho de
  upload. `OPS-389` (variantes de imagem por anexo) é a parte que roda **sobre** esse motor.
- **A paleta da marca é da tematização** (`theming-brand-engineer`), que roda antes de
  qualquer tela de feature. S17 define **onde os tokens entram**; não escolhe as cores.
  `OPS-635` (favicon, OG, `robots.txt`) continua sendo da fatia de marca.
- **O item de menu** usa `CONSOLE_NAV_ITEMS` de **S2** (`FE-441`/`FE-050`). S17 acrescenta
  uma entrada; não redesenha o menu.
- **`users.app_theme_id`** é coluna criada pela migration de `users` de **S1** (`DB-540`).
  S17 a **usa**; não a cria.

## Dependências

- **S2** — casca do console, rota e menu.
- **S13** — motor único de anexos e validação por magic bytes (`OPS-623`).
- **Tematização** — paleta light e dark da Safegold.
- **S1** — `users.app_theme_id`.

## Perguntas em aberto (defaults declarados em `map/data-infra.md` §6)

| # | Pergunta | Default |
| - | -------- | ------- |
| **Q-02** | Dark mode entra? | **Entra.** O mecanismo já está na base; o custo é a paleta |
| **Q-14** | `app_symbol.png` e `app_text.png` são referenciados pelo tema do legado e **não existem no repositório** | Gerados a partir do logo cheio, na tematização (mesma resposta de S16) |
| **Q-19** | `UserTheme` (tema por usuário) fica? | **Fica o modelo STI**, mas a interface expõe só o tema global nesta fatia. `UserTheme` sem tela é dado órfão; a tela é decisão do usuário |

## Capabilities

### New Capabilities

- `themes`: tema como dado — entidade, precedência, tokens em runtime e o gate de papel do
  `override_css`. **Uma** requirement genuinamente nova: o **contrato de tema efetivo**, que
  não existe no legado (lá o motor não pinta) nem na base ai9 (lá o tema é código).

### Modified Capabilities

Nenhuma. Os requirements de paridade dos 23 IDs já existem em `openspec/specs/` e são
**referenciados por ID**, não recriados.

## Impact

- **Backend:** `api/v1/themes.rb`, `api/entities/theme.rb`, `app/models/app_theme.rb` (+ STI),
  `app/services/themes/**`, migration `create_app_themes`, seed de referência.
- **Frontend:** `app/pages/console/themes/**`, `hooks/useTheme.ts` (passa a ler o tema
  efetivo do servidor), `styles/globals.css` (tokens vindos de custom properties),
  `hooks/useNavItems.ts` (uma entrada).
- **Paridade:** 23 IDs de inventário que **não tinham dono** passam a ter.
