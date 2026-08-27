import { useCallback, useEffect, useMemo, useRef, useState } from 'react'

/**
 * Busca com atraso — o padrão "input + ícone + debounce" que se repete em ~40
 * telas do Safegold (FE-420, FE-052).
 *
 * Três regras que cada tela reimplementaria (e erraria de um jeito diferente):
 *
 * 1. **300 ms.** Um único número para o app inteiro. Com valores diferentes por
 *    tela, a busca "parece travada" numa e "dispara demais" na outra.
 * 2. **Entrada só de espaços é ignorada.** `"   "` não é busca: o termo é
 *    aparado antes de virar consulta, e um termo aparado vazio equivale a
 *    "sem filtro" — nunca a "buscar por nada", que no servidor pagina o
 *    universo inteiro.
 * 3. **Limpar é imediato.** Apagar o campo não espera 300 ms para mostrar a
 *    lista completa de volta; só *digitar* espera.
 *
 * O hook não busca nada: devolve `termo` (o que está na tela) e `consulta` (o
 * valor estável que entra na `queryKey`). Quem busca é o React Query.
 */
export interface UseDebouncedSearchOptions {
  delay?: number
  initial?: string
  /** Comprimento mínimo para virar consulta. Abaixo dele, `consulta` é ''. */
  minLength?: number
  onDebouncedChange?: (consulta: string) => void
}

export function useDebouncedSearch({
  delay = 300,
  initial = '',
  minLength = 0,
  onDebouncedChange,
}: UseDebouncedSearchOptions = {}) {
  const [termo, setTermo] = useState(initial)
  const [consulta, setConsulta] = useState(() => initial.trim())
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const onChangeRef = useRef(onDebouncedChange)
  onChangeRef.current = onDebouncedChange

  const aplicar = useCallback(
    (valor: string) => {
      const limpo = valor.trim()
      const efetivo = limpo.length >= minLength ? limpo : ''
      setConsulta((atual) => {
        if (atual === efetivo) return atual
        onChangeRef.current?.(efetivo)
        return efetivo
      })
    },
    [minLength],
  )

  useEffect(() => {
    if (timer.current) clearTimeout(timer.current)
    // Campo vazio (ou só espaço) volta na hora: esperar para mostrar "tudo"
    // parece defeito.
    if (termo.trim() === '') {
      aplicar('')
      return
    }
    timer.current = setTimeout(() => aplicar(termo), delay)
    return () => {
      if (timer.current) clearTimeout(timer.current)
    }
  }, [termo, delay, aplicar])

  const limpar = useCallback(() => {
    if (timer.current) clearTimeout(timer.current)
    setTermo('')
    aplicar('')
  }, [aplicar])

  /** `true` entre a tecla e a consulta valer — para o spinner do campo. */
  const pendente = termo.trim() !== consulta

  return useMemo(
    () => ({ termo, setTermo, consulta, limpar, pendente }),
    [termo, consulta, limpar, pendente],
  )
}
