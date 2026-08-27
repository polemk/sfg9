# Design: S17 — Temas

> Origem: `.migration-ai9/map/data-infra.md` §2.6 (capability `themes`, 21 IDs) + `DB-548`
> de §2.1 + `OPS-603`/`OPS-606`/`OPS-750` de §2.2/§2.8.
> Esta fatia nasceu do fechamento do Phase 2: os 21 IDs de `themes` **não tinham dono**.

## Context

Medido nos dois lados, não suposto.

**No legado.** `app/models/app_theme.rb` tem 232 linhas: STI (`GlobalTheme`, `UserTheme`),
`default_theme`, quatro anexos Paperclip, `generate_template` → `parse_template` →
`cached_css`. O template que ele parseia,
`app/frontend/css/pub/templates/app_theme_template.css`, está **integralmente comentado** —
o motor sempre produziu folha vazia. `override_css` é permitido (`:125-148`), validado e
persistido, e nenhuma view o injeta. `app/controllers/pub/app_themes_controller.rb` não
declara `requires_current_user?` nem checa papel. Quatro actions (`index`, `show`, `new`,
`edit`) apontam para views que nenhuma rota alcança.

**Na base ai9.** O mecanismo de tema visual existe inteiro e funciona:
`frontend/src/styles/globals.css:45-70` define a camada `.dark`,
`frontend/src/hooks/useTheme.ts:8-14` alterna e persiste, `ThemeToggle.tsx` é o controle, e
`tailwind.config.*` lê custom properties. **O que não existe é tema como dado**: nenhuma
tabela, nenhum endpoint, nenhuma tela — a marca está em código.

A assimetria define o desenho: **o motor é reuso, a entidade é `build`**.

## Goals / Non-Goals

**Goals**
- Tema é **dado**, administrável, com um padrão global garantido no banco.
- **Uma** resolução de precedência, usada pelo servidor e pelo cliente — nunca duas.
- Tokens em runtime, não geração de arquivo CSS.
- Fechar o buraco de autorização (anônimo trocava o tema global).
- Dark mode passa a existir, com contraste AA nos dois modos.

**Non-Goals**
- **Não** portar o motor `generate_template`/`cached_css`. Ele nunca funcionou, e o
  equivalente ai9 (custom properties) é melhor e já está em pé.
- **Não** criar a tela de tema por usuário (`UserTheme`) — o modelo fica, a tela é decisão
  do usuário (Q-19).
- **Não** escolher cores. A paleta é da tematização.
- **Não** criar um segundo caminho de upload — o motor de anexos é de S13.

## Decisões

### D1 — Tokens em runtime, não folha de estilo gerada

O legado gerava e cacheava CSS. O ai9 serve o tema efetivo como **custom properties**
aplicadas na raiz do documento. Consequências que importam: não há cache a invalidar, não há
arquivo a versionar, e o mesmo par de tokens serve `light` e `dark` sem duplicar o motor.

**Por que não reaproveitar o cache do legado:** um cache de CSS por tema é a classe de bug
"o usuário está vendo a marca de ontem" — e o legado nem chegava a exercitá-la, porque a
folha era vazia.

### D2 — Um padrão global, garantido por índice, não por callback

`add_index :app_themes, :is_default, unique: true, where: "is_default"`. O legado garantia
"um padrão" em callback de model (`app_theme.rb:137-139`), que perde a corrida com dois
requests simultâneos e não vale para o ETL nem para o seed. O índice parcial vale para os
três caminhos e **corrige o D-59 na raiz**.

### D3 — `override_css` renderizado, mas com gate **no servidor**

O campo passa a ter efeito, injetado **depois** dos tokens (para poder sobrepor). Duas
travas, e ambas são obrigatórias:
- o campo **não aparece** em nenhuma tela para quem não é admin/og;
- o servidor **rejeita o campo** se ele vier no payload de quem não tem o papel.

Só a primeira é o erro clássico: gate na tela é gate nenhum. **Risco alto de segurança** —
CSS arbitrário injetado é vetor de exfiltração visual (`background-image:url(...)` com dado
na URL). Por isso, além do gate, o conteúdo é sanitizado (sem `@import`, sem `url()` para
host externo). DEC-19 fixou o gate em og/admin.

### D4 — Precedência em fonte única

`UserTheme` do usuário → `GlobalTheme` padrão → tokens de fábrica. A resolução vive em **um**
service no servidor; o cliente recebe o resultado, não a regra. É o contrato que vira
requirement nova nesta fatia — no legado a precedência estava espalhada por
`app_theme.rb:137-139` e três decorators (`user_decorator.rb:7, 38, 48, 76-80`), que é
exatamente como duas telas passam a discordar sobre qual é o tema.

### D5 — Dark mode: mecanismo herdado, paleta nova

Não há referência legada para comparar — o legado **não tem** dark (`STYLE__DARK` existe,
`beauty_style` traduz, a opção está comentada). Portanto isto **não é paridade**: é ganho,
e vai para `improvements-log.md` para o QA do Phase 4 não procurar o equivalente no legado.
Default é **claro**.

### D6 — Anexos: ActiveStorage com magic bytes, não Paperclip com spoof desligado

O legado declara `do_not_validate_attachment_file_type`: **aceita qualquer coisa** com
extensão de imagem. Aqui a validação é por conteúdo (`OPS-623`, motor de S13). O logo é o
único arquivo que um administrador sobe e que **todo mundo** carrega — é o pior lugar
possível para confiar em extensão.

## Risks

| Risco | Mitigação |
| ----- | --------- |
| **Alto (segurança)** — `override_css` arbitrário | Gate por papel no **servidor** + sanitização + teste que envia o campo com papel insuficiente e espera rejeição |
| **Médio** — dark mode sem referência legada | Contraste AA verificado nos dois modos; a paleta vem da tematização, não é inventada aqui |
| **Médio** — ordem com S13 | Se S13 ainda não tiver entregado o motor de anexos, os 4 anexos do tema **esperam**; o resto da fatia não depende deles |
| **Baixo** — `UserTheme` sem tela | O modelo fica, o seed não cria nenhum, e o ledger registra a decisão (Q-19) |

## Migration Plan

1. Migration `create_app_themes` (+ índice único parcial) e uso de `users.app_theme_id`.
2. Seed de referência do `GlobalTheme` Safegold (idempotente).
3. Service de resolução de tema efetivo + endpoint de leitura.
4. CRUD + ativação, com autorização desde o primeiro endpoint.
5. Tokens em runtime no cliente; `ThemeToggle` passa a operar sobre o tema efetivo.
6. Telas (lista, detalhe, formulário) — `override_css` só sob papel.
7. Anexos, quando o motor de S13 existir.

## Open Questions

- **Q-19** — `UserTheme` ganha tela? Default: **não nesta fatia**.
- **Q-14** — `app_symbol.png` / `app_text.png` não existem no repositório legado; gerados a
  partir do logo cheio (mesma resposta de S16).
