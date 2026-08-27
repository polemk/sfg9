# S0 — Inventário dos módulos JS do legado importados de fato (FE-538)

> Tarefa **4.23** de `tasks.md`. Este documento é o insumo direto das tarefas 4.1–4.22:
> para cada módulo que o legado **realmente carrega**, qual é o equivalente ai9 e onde ele
> mora hoje no repo. O critério de "importado de fato" é literal — só entra o que aparece
> num `import` dos dois packs de entrada:
>
> - `../sfg/app/frontend/js/index.js.erb` (pack do app, 6 módulos próprios)
> - `../sfg/app/frontend/vendor/js/index.js.erb` (pack vendor, 13 bibliotecas + 3 próprios)
>
> Tudo que existe em `app/frontend/` mas **não** é importado por um desses dois arquivos
> está marcado como morto e não vira tarefa.

## 1. Os 13 módulos de vendor importados

| # | Módulo do legado | Para que servia | Equivalente ai9 | Onde está | Situação |
| - | ---------------- | --------------- | --------------- | --------- | -------- |
| 1 | `jquery` | tudo | React 18 + hooks | `src/` | **cai** — a base não tem jQuery |
| 2 | `jquery-toast-plugin` | toasts (`M.push`) | `sonner` + `notify` | `src/lib/notify.ts` | **adapt** — de-para de `M.SUCCESS/ERROR/HELP/WARNING` documentado no módulo (FE-410) |
| 3 | `jquery.rateit` | estrelas de avaliação | — | — | **dropped** (FE-429). Ver §4 |
| 4 | `remotipart` | upload por `remote: true` | `FormData` + axios | `src/lib/api/client.ts` | **cai** — sem UJS |
| 5 | `air-datepicker` (+ `datepicker_overrides.js`) | seletor de data | `DatePicker` + `Calendar` | `src/components/ui/{DatePicker,Calendar}.tsx` | **build** (FE-745). Sem dependência nova: usa o `date-fns` que já estava no `package.json` |
| 6 | `animejs` | animação imperativa | `tailwindcss-animate` + `framer-motion` | `tailwind.config.js`, já na base | **adapt** |
| 7 | `romanjs` | numeral romano | — | — | **dropped** — nenhuma view do console usa; era do site público, fora de escopo |
| 8 | `vanilla-picker` | seletor de cor | — | — | **dropped** — cor agora é token; não há tela de escolher cor no console |
| 9 | `node-vibrant` | cor dominante de imagem | — | — | **dropped** — era o que sorteava a cor do avatar/card. Substituído por `avatarTone`, determinístico (FE-427) |
| 10 | `croppie` | recorte de imagem | `ImageCropper` | `src/components/ui/ImageCropper.tsx` (já existia) | **reuse** |
| 11 | `photoswipe` (+ `photoswipe-ui-default`) | galeria em tela cheia | `react-photo-album` + `Dialog` | `package.json`, `src/components/ui/dialog.tsx` | **adapt** — o override de CSS do PhotoSwipe cai junto com o `rateit` |
| 12 | `@rails/ujs` | `data-remote`, `data-confirm` | `Dialog` de confirmação + axios | `src/components/ui/dialog.tsx` | **cai** |
| 13 | `tippy.js` (com tema `app_theme`) | tooltip | `Tooltip` | `src/components/ui/Tooltip.tsx` | **adapt** (FE-426) — uma dependência a menos; as 4 posições estão cobertas |

### Os 3 módulos proprietários do vendor (DEC-10 — usar as libs do ai9)

| Módulo | Equivalente ai9 | Onde está | Situação |
| ------ | --------------- | --------- | -------- |
| `lvt-dialog.js` | `Dialog` (Radix) | `src/components/ui/dialog.tsx` | **adapt** (FE-743) — a aparência muda, o comportamento não |
| `lvt-doughnut.js` | `RechartsPie` | `src/components/charts/RechartsPie.tsx` | **adapt** (FE-744). **Nota:** o legado não instancia nenhum gráfico (achado #1 do `migration-map.md`) — isto é o componente ficando disponível, não uma tela portada |
| `iv-viewer.js` | `react-photo-album` + `Dialog` | já na base | **adapt** |

Também importados pelo glob do vendor, sem consumidor no console: `dragula_wrapper.js`,
`foundation.js`, `masonry.pkgd.min.js`, `jquery_masked_input_plugin.min.js`,
`rails-action-text.js`. A máscara de input é a única com sucessora real —
`NumericInput`/`DatePicker` fazem máscara em React, sem plugin.

## 2. Os 6 módulos próprios do pack do app

| Módulo | O que era | Equivalente ai9 | Onde está |
| ------ | --------- | --------------- | --------- |
| `msg_helper.js.erb` (classe `M`) | 9 estilos de toast, dos quais 4 usados | `notify` | `src/lib/notify.ts` — o de-para completo está no comentário do módulo (FE-410) |
| `toolbars.js` (751 linhas: `ContextToolbar`, `Toolbar`, `SearchBar`) | barra imperativa com hide-on-scroll, "extend", loader e wrapper de mensagem | `PageHeader` (com `sticky`, `loading`, `searchSlot`) + `SearchInput` | `src/components/PageHeader.tsx`, `src/components/ui/SearchInput.tsx` (FE-740) |
| `helpers.js` | `scriptLoader`, `toastAlert`, `countChar`, `getExtendedMonth`, `getExtendedWeekday`, `extendedDate`, `brazilianDate`, `parseAddressInLines`, `parseAddressAsHtml`, `requireSignIn` | datas → `lib/utils/date.ts`; endereço → `lib/utils/address.ts`; toast → `lib/notify.ts`; `requireSignIn` → `ProtectedRoute`; `scriptLoader` → import estático do Vite | `src/lib/utils/`, `src/components/ProtectedRoute.tsx` (FE-742) |
| `polling_helper.js` (`PollingManager`) | perguntava ao servidor "já terminou?" em intervalo | `useJobProgress` sobre `ProjectProgressChannel` | `src/hooks/useJobProgress.ts` — **polling é proibido** (Princípio 10, OPS-087) |
| `simple_menu.js` | menu suspenso em `absolute` | `FloatingPanel` (portal + `position: fixed`) | `src/components/ui/FloatingPanel.tsx` |
| `index.js.erb` | pendurava os 15 nomes acima em `global.*` | — | **nada vira global no `window`** (IMP-A73) |

## 3. As duas peças de CSS puro (FE-413, FE-419)

| Legado | Onde | Uso real | Equivalente ai9 |
| ------ | ---- | -------- | --------------- |
| `app_arrow` | `css/pub/recyclable/button.scss` — seta desenhada com `border` e `transform` | **0 ocorrências** em `app/views/` | Ícone da biblioteca (`lucide-react`: `ChevronDown`/`ChevronRight`), já usado por `Select`, `DatePicker`, `DataTable` e `PaginationPill` |
| `app_switch_toggle` | `css/pub/recyclable/switches.scss` | 12 ocorrências em `app/views/` | `Switch` (Radix) — `src/components/ui/switch.tsx`, com `data-[state=checked]:bg-primary` |

## 4. `Rating` (FE-429) — **dropped**, com a evidência

A tarefa 4.22 mandava construir "só se houver uso real" (Q-B13). Não há. Três evidências,
todas verificáveis na origem:

1. **A fonte do dado é um número aleatório.** `app/decorators/models/user_decorator.rb:62`:
   `def rating; (Random.rand(3000)/999.99).round(2) + 2; end`. Não existe coluna, não existe
   cálculo — a nota é sorteada a cada chamada.
2. **A única referência em view está comentada.**
   `app/views/pub/console/parts/users/helper/_body.js.erb:106`:
   `// ratingElement.rateit('value', rating);`.
3. **O SCSS existe e não é aplicado.** `css/pub/recyclable/generic_rating.scss` define
   `.app_rating_widget`, e nenhuma view usa essa classe.

Portar um widget de estrelas para exibir `Random.rand` seria migrar um defeito. `jquery.rateit`
sai do inventário junto com o override de CSS do PhotoSwipe que a tarefa citava.
