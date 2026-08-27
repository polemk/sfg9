/**
 * Transversais de texto e de listas — os helpers de view do legado que sobraram
 * sem dono e viraram **um utilitário por conceito** (fatia S19).
 *
 * O que **não** está aqui, de propósito:
 *  - **iniciais** (`FE-433`): o `UserAvatar` do design system já faz
 *    (`initialsOf`, `components/ui/UserAvatar.tsx`). Reimplementar seria a
 *    segunda versão do mesmo conceito, que é o defeito que esta fatia corrige;
 *  - **cor de identificação determinística** (`FE-435`): é `avatarTone`, exportada
 *    do mesmo arquivo. O legado usava a gem `color-generator` e sorteava a cor
 *    **a cada render** — o mesmo item mudava de cor ao rolar a lista;
 *  - **moeda** (`FE-431`): é `formatMoney` em `utils/number.ts`;
 *  - **datas, meses, dias e tempo relativo** (`FE-430`, `436`, `437`, `440`, `442`):
 *    estão em `utils/date.ts`;
 *  - **plural e concordância de gênero** (`FE-438`, `FE-432`): são **catálogo no
 *    servidor** (`config/locales/pt-BR.yml`), porque é lá que a frase da trilha é
 *    montada — uma vez só. Ver `Sfg::Inflection` e `Sfg::AuditSummary`.
 */

/**
 * Nome curto: primeiro e último nome — `FE-434` (`chop_middle_words`).
 *
 * Preserva o comportamento do legado (`application_helper.rb:38-45`), inclusive
 * devolver string vazia para entrada vazia. O que muda: `null`/`undefined` não
 * levantam. No legado `chop_middle_words(nil)` era `NoMethodError`, e o único
 * consumidor (`console/base/resume/_container.html.erb:10`) passava
 * `current_user.formal`, que pode ser nulo.
 */
export function chopMiddleWords(name?: string | null): string {
  const partes = (name ?? '').trim().split(/\s+/).filter(Boolean)
  if (partes.length === 0) return ''
  if (partes.length === 1) return partes[0]
  return `${partes[0]} ${partes[partes.length - 1]}`
}

/**
 * Distribui uma lista em `colunas` colunas, **intercalando** — `FE-439`
 * (`slice_in`).
 *
 * O item `k` cai na coluna `k % colunas`, que é o que o legado fazia
 * (`application_helper.rb:73-85`) e o que produz colunas de altura equilibrada
 * quando a lista não é múltipla do número de colunas.
 *
 * Duas diferenças, as duas por defeito medido:
 *  - o legado tinha **três** cópias desta função (`ux_kit19`,
 *    `feedback19/messages_controller.rb:203` e
 *    `auth_ux19/registrations_controller.rb:212`), duas delas dentro de
 *    controllers. É uma só;
 *  - `slice_in(lista, 0)` no legado devolve `[]` e **descarta a lista inteira**
 *    em silêncio. Aqui `colunas < 1` devolve uma coluna com tudo: nenhum item
 *    some porque alguém passou zero.
 */
export function sliceIn<T>(items: readonly T[], colunas: number, filtro?: (item: T) => boolean): T[][] {
  const n = Math.max(1, Math.floor(colunas))
  const saida: T[][] = Array.from({ length: n }, () => [])
  const lista = filtro ? items.filter(filtro) : items
  lista.forEach((item, k) => saida[k % n].push(item))
  return saida
}
