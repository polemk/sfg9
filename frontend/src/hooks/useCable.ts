import { useState, useEffect, useRef } from 'react'
import { createConsumer } from '@rails/actioncable'
import { useAccessToken } from '@/lib/api/tokenStore'

const WS_URL = import.meta.env.VITE_WS_URL ||
  `${window.location.protocol === 'https:' ? 'wss' : 'ws'}://${window.location.host}/cable`

export function useCable() {
  const [consumer, setConsumer] = useState<any>(null)
  // A autenticação do WebSocket vem do cookie HttpOnly `cable_token` (escopo
  // /cable) — nunca da URL, então nada vaza em log de proxy. O browser envia o
  // cookie automaticamente no handshake.
  //
  // Gatilho de reconexão: a PRESENÇA do access token (não o valor). Ele nasce
  // nulo no reload e vira presente no mesmo /sessions/refresh que (re)emite o
  // cookie do cable — então reconectar nessa transição garante que o handshake
  // pegue o cookie recém-setado. Rotação do token (present→present) não refaz a
  // conexão. Conexão anônima (sem token/cookie) segue permitida p/ chat público.
  const hasSession = !!useAccessToken()

  useEffect(() => {
    let endpoint = WS_URL
    if (!endpoint.endsWith('/cable')) {
      endpoint = endpoint.replace(/\/+$/, '') + '/cable'
    }
    const cableConsumer = createConsumer(endpoint)
    setConsumer(cableConsumer)

    return () => {
      cableConsumer.disconnect()
    }
  }, [hasSession])

  return consumer
}

export function useChannel(
  channelName: string,
  params: Record<string, any> = {},
  handlers?: {
    connected?: () => void
    disconnected?: () => void
    received?: (data: any) => void
  }
) {
  const [subscription, setSubscription] = useState<any>(null)
  const consumer = useCable()
  const handlersRef = useRef(handlers)

  useEffect(() => {
    handlersRef.current = handlers
  }, [handlers])

  useEffect(() => {
    if (!consumer) return
    const paramValues = Object.values(params || {})
    const hasMissing = paramValues.some((v) => v === undefined || v === null || (typeof v === 'string' && v.length === 0))
    if (hasMissing) return

    // Reconexão é responsabilidade do próprio @rails/actioncable: o ConnectionMonitor
    // reabre o socket com backoff e o subscriptions.reload() re-assina TODAS as
    // subscriptions registradas no "welcome". Recriar a subscription manualmente no
    // disconnected() (versão anterior deste hook) gerava DUPLICATA — cada broadcast
    // passava a ser entregue 2x (received roda em toda subscription com o mesmo
    // identifier) — e usava timers/contadores globais compartilhados entre canais.
    const sub = consumer.subscriptions.create(
      { channel: channelName, ...params },
      {
        connected() {
          if (handlersRef.current?.connected) handlersRef.current.connected()
        },
        disconnected() {
          if (handlersRef.current?.disconnected) handlersRef.current.disconnected()
        },
        received(data: any) {
          if (handlersRef.current?.received) handlersRef.current.received(data)
        },
      }
    )

    setSubscription(sub)

    return () => {
      sub.unsubscribe()
    }
  }, [consumer, channelName, JSON.stringify(params)])

  return subscription
}
