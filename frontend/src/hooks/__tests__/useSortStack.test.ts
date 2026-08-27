import { describe, it, expect } from 'vitest'
import { act, renderHook } from '@testing-library/react'
import { useSortStack } from '../useSortStack'

/**
 * **FE-159, FE-194, FE-254, FE-287 — a ordenação que acumula.**
 *
 * O `Sfg::Sortable` do backend recebe `ordering_keys[]` e `ordering_style[]`
 * como pares paralelos, e o legado empilhava as chaves clicadas. Quatro listas
 * do console migraram guardando UMA ordenação: cada clique substituía a
 * anterior, e o desempate por segunda coluna sumiu.
 *
 * A conferência de paridade da Phase 4 travou três delas. A quarta
 * (`StructuredOperationsPage`) tinha a versão certa **escrita à mão** — e é dela
 * que este hook nasceu. Quatro cópias da mesma regra divergiram em quatro
 * comportamentos; agora é uma, e é esta que os exemplos abaixo travam.
 */
describe('useSortStack', () => {
  it('começa com a pilha inicial e a expõe como pares paralelos', () => {
    const { result } = renderHook(() => useSortStack([{ key: 'date', direction: 'desc' }]))

    expect(result.current.chaves).toEqual(['date'])
    expect(result.current.estilos).toEqual(['down'])
    expect(result.current.primeira).toEqual({ key: 'date', direction: 'desc' })
  })

  it('o clique PROMOVE a coluna e empurra as anteriores para desempate', () => {
    const { result } = renderHook(() => useSortStack([{ key: 'date', direction: 'desc' }]))

    act(() => result.current.trocar({ key: 'value', direction: 'asc' }, 'value'))

    // A clicada é a primária; a anterior continua na pilha, atrás.
    expect(result.current.chaves).toEqual(['value', 'date'])
    expect(result.current.estilos).toEqual(['up', 'down'])
    expect(result.current.primeira).toEqual({ key: 'value', direction: 'asc' })
  })

  it('a mesma coluna clicada de novo NÃO entra duas vezes — ela troca de sentido', () => {
    const { result } = renderHook(() => useSortStack([{ key: 'date', direction: 'asc' }]))

    act(() => result.current.trocar({ key: 'date', direction: 'desc' }, 'date'))

    expect(result.current.chaves).toEqual(['date'])
    expect(result.current.estilos).toEqual(['down'])
  })

  it('o terceiro clique REMOVE só aquela chave, e não a pilha inteira', () => {
    const { result } = renderHook(() => useSortStack([{ key: 'date', direction: 'desc' }]))

    act(() => result.current.trocar({ key: 'value', direction: 'asc' }, 'value'))
    expect(result.current.chaves).toEqual(['value', 'date'])

    // `null` é o terceiro estado do tri-state do `DataTable`. É por isso que a
    // chave viaja separada: com `null` no primeiro argumento, não há como saber
    // QUAL coluna foi desligada.
    act(() => result.current.trocar(null, 'value'))

    expect(result.current.chaves).toEqual(['date'])
    expect(result.current.primeira).toEqual({ key: 'date', direction: 'desc' })
  })

  it('desligando a última chave, a pilha fica vazia e os parâmetros somem', () => {
    const { result } = renderHook(() => useSortStack([{ key: 'date', direction: 'desc' }]))

    act(() => result.current.trocar(null, 'date'))

    // `undefined`, não `[]`: array vazio viajaria como `ordering_keys[]=` e o
    // servidor teria de decidir o que fazer com uma lista vazia.
    expect(result.current.chaves).toBeUndefined()
    expect(result.current.estilos).toBeUndefined()
    expect(result.current.primeira).toBeNull()
  })

  it('`null` sem chave nenhuma não faz nada — melhor inerte que apagar a pilha', () => {
    const { result } = renderHook(() => useSortStack([{ key: 'date', direction: 'desc' }]))

    act(() => result.current.trocar(null))

    expect(result.current.chaves).toEqual(['date'])
  })

  it('a pilha guarda TRÊS níveis de desempate na ordem dos cliques', () => {
    const { result } = renderHook(() => useSortStack())

    act(() => result.current.trocar({ key: 'a', direction: 'asc' }, 'a'))
    act(() => result.current.trocar({ key: 'b', direction: 'desc' }, 'b'))
    act(() => result.current.trocar({ key: 'c', direction: 'asc' }, 'c'))

    expect(result.current.chaves).toEqual(['c', 'b', 'a'])
    expect(result.current.estilos).toEqual(['up', 'down', 'up'])
  })

  it('`limpar` zera tudo', () => {
    const { result } = renderHook(() => useSortStack([{ key: 'date', direction: 'desc' }]))

    act(() => result.current.limpar())

    expect(result.current.chaves).toBeUndefined()
    expect(result.current.ordenacoes).toEqual([])
  })
})
