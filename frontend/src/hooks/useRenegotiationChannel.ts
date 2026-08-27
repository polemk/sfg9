import { useEffect, useRef, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useChannel } from './useCable'

/**
 * S9 / FE-207 — **os cartões de resumo atualizam por evento, nunca por relógio**.
 *
 * **Princípio 10: polling é proibido.** A tela de detalhe mostra quatro cartões
 * financeiros que mudam a cada parcela e a cada pagamento. Bater no servidor a
 * cada N segundos para descobrir se mudou é o que este hook existe para não
 * fazer — e é o que faz a mesma tela aberta em duas abas divergir.
 *
 * ## O que o canal manda, e o que ele NÃO manda
 *
 * O payload diz **o que mudou**, não carrega o estado. O hook invalida a consulta
 * e o React Query relê pelo endpoint — que é onde a autorização é conferida.
 * Empurrar o registro pelo canal criaria uma segunda superfície de leitura, sem
 * gate.
 *
 * ## O defeito do legado que isto substitui
 *
 * O legado montava o objeto de valores em JavaScript e escrevia campo a campo:
 * um campo ausente na resposta levantava `TypeError` e **parava a atualização dos
 * demais**. Aqui a falha de conexão é sinalizada (`connected`) e a tela continua
 * mostrando o último estado bom, com aviso — nenhum campo derruba outro.
 */
export interface RenegotiationChannelState {
  /** `false` enquanto o WebSocket não confirmou. A tela avisa em vez de mentir. */
  connected: boolean
  /** Quando chegou o último evento — para a tela dizer "atualizado agora". */
  lastEventAt: Date | null
}

export function useRenegotiationChannel(renegotiationId: string | undefined): RenegotiationChannelState {
  const queryClient = useQueryClient()
  const [connected, setConnected] = useState(false)
  const [lastEventAt, setLastEventAt] = useState<Date | null>(null)
  // O id fica numa ref para que o handler não precise ser recriado — recriar o
  // handler reassina o canal, e reassinar a cada render é polling com outro nome.
  const idRef = useRef(renegotiationId)
  idRef.current = renegotiationId

  useEffect(() => {
    if (!renegotiationId) setConnected(false)
  }, [renegotiationId])

  useChannel(
    'RenegotiationChannel',
    { renegotiation_id: renegotiationId },
    {
      connected: () => setConnected(true),
      disconnected: () => setConnected(false),
      received: () => {
        const id = idRef.current
        if (!id) return
        setLastEventAt(new Date())
        // Invalida as três consultas da tela de uma vez: o evento não diz qual
        // delas mudou, e recarregar as três é uma requisição a mais contra o
        // risco de mostrar número velho num cartão.
        queryClient.invalidateQueries({ queryKey: ['renegotiation', id] })
        queryClient.invalidateQueries({ queryKey: ['renegotiation-installments', id] })
        queryClient.invalidateQueries({ queryKey: ['renegotiation-general-values', id] })
      },
    },
  )

  return { connected, lastEventAt }
}
