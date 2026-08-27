import { useCallback, useMemo, useState } from 'react'
import type { SortState } from '@/components/ui/DataTable'

/**
 * **A ordenação que ACUMULA — FE-159, FE-194, FE-254, FE-287.**
 *
 * O `Sfg::Sortable` do backend recebe `ordering_keys[]` e `ordering_style[]`
 * como pares paralelos, e o legado empilhava as chaves clicadas
 * (`_body.js.erb:42-58`, com `push`/`splice`). Quatro listas do console
 * migraram guardando **um** `SortState`: cada clique SUBSTITUÍA a ordenação em
 * vez de empilhar, e o desempate por segunda coluna — que numa tabela de
 * borderôs é o que separa duas linhas do mesmo dia — desapareceu.
 *
 * A pilha aqui é explícita:
 *
 *   * o clique **promove** a coluna a primária e empurra as anteriores para
 *     desempate;
 *   * o terceiro clique (o `null` do tri-state do `DataTable`) **remove** a
 *     chave da pilha — é a única forma de o usuário desfazer uma ordenação;
 *   * a mesma coluna nunca aparece duas vezes.
 *
 * ## Por que é um hook, e não copiado em cada página
 *
 * Porque já estava copiado. A `StructuredOperationsPage` tinha a versão certa;
 * as outras três, a versão de uma chave só. Quatro cópias divergiram em quatro
 * comportamentos diferentes — e a quinta lista a nascer copiaria de qual delas?
 *
 * ## O `DataTable` mostra só a PRIMEIRA
 *
 * Ele recebe `SortState | null`, e é o certo: a seta na coluna indica a
 * ordenação primária. As de desempate viajam para o servidor e não têm
 * afordância visual — no legado também não tinham.
 */
export function useSortStack(inicial: SortState[] = []) {
  const [ordenacoes, setOrdenacoes] = useState<SortState[]>(inicial)

  const trocar = useCallback((proximo: SortState | null, chave?: string) => {
    setOrdenacoes((atual) => {
      // Com `proximo` nulo o `DataTable` não diz QUAL coluna foi desligada —
      // por isso a chave também chega por fora, lida do clique. Sem ela o
      // terceiro clique limparia a pilha inteira em vez de tirar uma chave.
      const alvo = proximo?.key ?? chave
      if (!alvo) return atual

      const semAChave = atual.filter((o) => o.key !== alvo)
      return proximo ? [proximo, ...semAChave] : semAChave
    })
  }, [])

  const limpar = useCallback(() => setOrdenacoes([]), [])

  /** `ordering_keys[]` para o cliente de API. `undefined` com a pilha vazia. */
  const chaves = useMemo(
    () => (ordenacoes.length ? ordenacoes.map((o) => o.key) : undefined),
    [ordenacoes],
  )

  /** `ordering_style[]`, na MESMA ordem — são pares paralelos no servidor. */
  const estilos = useMemo(
    () =>
      ordenacoes.length
        ? ordenacoes.map((o) => (o.direction === 'desc' ? ('down' as const) : ('up' as const)))
        : undefined,
    [ordenacoes],
  )

  return {
    ordenacoes,
    /** A primária, que é a que o `DataTable` desenha. */
    primeira: ordenacoes[0] ?? null,
    trocar,
    limpar,
    chaves,
    estilos,
  }
}
