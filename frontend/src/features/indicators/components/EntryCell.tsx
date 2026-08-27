import { useEffect, useRef, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { AlertCircle, Check, Loader2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { cn } from '@/lib/utils'
import { MoneyInput } from '@/components/ui/NumericInput'
import {
  indicatorEntriesApi,
  mensagemDoServidor,
  codigoDoServidor,
  type GridCell,
} from '@/lib/api/indicators'
import { paraDecimalString, paraNumero } from '../lib/periodo'

/**
 * `FE-326`, `FE-328`, `FE-329`, `FE-718` — **uma célula da grade**.
 *
 * ## O pior estado de UI do bloco inteiro, e o que ele vira aqui
 *
 * No legado cada célula é um `form_for` que submete no `change` por
 * `remote: true`, e **não há handler de erro nenhum**
 * (`indicator_entries/_body.js.erb`): em 422 o usuário vê o campo destravar sem
 * mensagem e **acredita que salvou**. Pior: o `preventDoubleSubmission` marca o
 * formulário como enviado e **nunca limpa a flag** — depois do primeiro
 * auto-save, o mesmo campo **não envia de novo** até a lista recarregar.
 *
 * Aqui cada célula tem os três estados visíveis — **enviando**, **salvo** e
 * **falhou** — e a falha **fica na tela** com o valor digitado preservado, para
 * o usuário tentar de novo. Cor por token semântico, nunca literal.
 *
 * ## "Não lançado" ≠ "zero" (DEC-70)
 *
 * `cell.entry === null` é **não lançado**: o campo fica vazio, com o traço no
 * placeholder. Um lançamento de zero mostra `R$ 0,00`. No legado os dois
 * apareciam como `0`, porque a view instanciava um `IndicatorEntry.new` para o
 * mês vazio e a coluna tem default `0.0`.
 *
 * ## Somente leitura (`FE-718`)
 *
 * O campo continua **visível e legível**, e a mensagem explica a restrição no
 * lugar de o controle sumir — o padrão do `FE-323`. E agora o servidor **também
 * impede** o POST: no legado o readonly era só `readonly` no HTML.
 */
export interface EntryCellProps {
  indicatorId: string
  year: number
  cell: GridCell
  rotulo: string
  somenteLeitura: boolean
}

type Estado = 'ocioso' | 'enviando' | 'salvo' | 'erro'

export function EntryCell({ indicatorId, year, cell, rotulo, somenteLeitura }: EntryCellProps) {
  const queryClient = useQueryClient()
  const [valor, setValorState] = useState<number | null>(paraNumero(cell.entry?.value))
  const [estado, setEstado] = useState<Estado>('ocioso')
  const [mensagem, setMensagem] = useState<string | null>(null)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)

  /**
   * **O valor corrente, fora do ciclo de render.**
   *
   * Não é preciosismo: o `NumericInput` chama `onChange` e, no mesmo evento de
   * saída, chama `onBlur`. Lendo `valor` do estado, o handler de saída enxerga o
   * valor **anterior** quando digitação e saída caem no mesmo lote do React — e
   * a gravação simplesmente não acontece. **Achado executando**: o campo exibia
   * `R$ 7.777,55` e o banco não tinha a linha. `tsc` e `vitest` passavam.
   */
  const valorRef = useRef<number | null>(paraNumero(cell.entry?.value))
  const setValor = (n: number | null) => {
    valorRef.current = n
    setValorState(n)
  }

  // O servidor é a verdade: quando a grade recarrega, a célula acompanha — a
  // menos que o usuário esteja com uma falha na tela, que não pode ser apagada
  // por baixo dele.
  useEffect(() => {
    if (estado === 'erro') return
    setValor(paraNumero(cell.entry?.value))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cell.entry?.id, cell.entry?.value])

  // O valor que o servidor tem agora, também fora do render, pelo mesmo motivo.
  const originalRef = useRef<number | null>(paraNumero(cell.entry?.value))
  originalRef.current = paraNumero(cell.entry?.value)

  useEffect(() => () => { if (timer.current) clearTimeout(timer.current) }, [])

  const gravar = useMutation({
    mutationFn: (numero: number) =>
      indicatorEntriesApi.upsert({
        indicator_id: indicatorId,
        year,
        month: cell.month,
        value: paraDecimalString(numero),
      }),
    onMutate: () => {
      setEstado('enviando')
      setMensagem(null)
    },
    onSuccess: () => {
      setEstado('salvo')
      // A marca de "salvo" some sozinha: ela confirma o ato, não é estado
      // permanente da célula.
      if (timer.current) clearTimeout(timer.current)
      timer.current = setTimeout(() => setEstado('ocioso'), 1800)
      queryClient.invalidateQueries({ queryKey: ['indicator-grid'] })
    },
    // **O handler que não existia.** Sem ele o 422 era invisível.
    onError: (erro) => {
      setEstado('erro')
      const codigo = codigoDoServidor(erro)
      const texto =
        codigo === 'READONLY_RESTRICTED'
          ? 'Seu perfil está em modo somente leitura: o lançamento não foi salvo.'
          : mensagemDoServidor(erro, 'Não foi possível salvar este lançamento.')
      setMensagem(texto)
      notify.error(`${rotulo}: ${texto}`)
    },
  })

  function aoSair() {
    if (somenteLeitura) return
    const atual = valorRef.current
    // Nada digitado numa célula nunca lançada continua "não lançado": gravar
    // zero por conta própria inventaria um lançamento (DEC-70).
    if (atual === null) return
    if (atual === originalRef.current) return
    gravar.mutate(atual)
  }

  const naoLancado = cell.entry === null

  return (
    <div className="flex items-center gap-2">
      <label
        htmlFor={`entry-${indicatorId}-${cell.month}`}
        className="w-24 shrink-0 text-sm text-muted-foreground"
      >
        {rotulo}
      </label>

      <div className="relative flex-1">
        <MoneyInput
          id={`entry-${indicatorId}-${cell.month}`}
          value={valor}
          onChange={setValor}
          onBlur={aoSair}
          onKeyDown={(e) => {
            if (e.key === 'Enter') (e.target as HTMLInputElement).blur()
          }}
          // Durante o envio o campo fica somente-leitura, não desabilitado:
          // desabilitar rouba o foco e o usuário perde o lugar na grade.
          readOnly={somenteLeitura || estado === 'enviando'}
          placeholder={naoLancado ? '—' : 'R$ 0,00'}
          aria-label={`${rotulo}, valor`}
          aria-invalid={estado === 'erro'}
          className={cn(
            'font-numeric tabular-nums pr-8',
            // Cor ao vivo pelos tokens semânticos — nunca literal.
            valor !== null && valor > 0 && 'text-success',
            valor !== null && valor < 0 && 'text-negative',
            naoLancado && valor === null && 'text-muted-foreground',
            estado === 'erro' && 'border-destructive',
          )}
        />

        <span className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2">
          {estado === 'enviando' && (
            <Loader2 aria-hidden="true" className="h-4 w-4 animate-spin text-muted-foreground" />
          )}
          {estado === 'salvo' && <Check aria-hidden="true" className="h-4 w-4 text-success" />}
          {estado === 'erro' && <AlertCircle aria-hidden="true" className="h-4 w-4 text-destructive" />}
        </span>
      </div>

      {estado === 'erro' && mensagem && (
        <p role="alert" className="w-full text-xs text-destructive">
          {mensagem}
        </p>
      )}
    </div>
  )
}
