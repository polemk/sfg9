import * as React from 'react'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  AlertTriangle,
  Check,
  Copy,
  LogOut,
  QrCode,
  RefreshCw,
  Smartphone,
  WifiOff,
} from 'lucide-react'
import { notify } from '@/lib/notify'

import PageHeader from '@/components/PageHeader'
import { AsyncSection, mensagemDeErro } from '@/components/ui/AsyncSection'
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { DetailList } from '@/components/ui/DetailList'
import { EmptyState } from '@/components/ui/States'
import { Input } from '@/components/ui/Input'
import { Spinner } from '@/components/ui/Spinner'
import { useChannel } from '@/hooks/useCable'
import { instancesApi, webhooksApi } from '@/lib/api/endpoints'
import type { WhatsRealtimeEvent } from '@/lib/api/types'
import { cn } from '@/lib/utils'

/**
 * Tela de pareamento do WhatsApp — `/platform/whatsapp` (OG e Admin, DEC-83).
 *
 * A disposição parte do que a pessoa está fazendo: ela chegou aqui com o
 * celular na mão para parear um telefone. Então o palco de pareamento (código +
 * passo a passo + estado) ocupa a tela, e o que é configuração (detalhes da
 * instância, webhooks) desce para uma seção recolhida. A versão anterior fazia
 * o contrário — dois terços da grade ficavam VAZIOS e o QR era espremido numa
 * coluna lateral, do mesmo tamanho e peso do formulário de webhook.
 *
 * ## De onde vem o código, e por que isso não é polling
 *
 * São dois caminhos, e eles não competem:
 *
 * - **Primeira carga:** a tela BUSCA o código, uma vez, em
 *   `GET /whats/v1/instances/connect_instance` (que no backend vira
 *   `GET {WHATS_SERVER_URL}/instance/connect/{instance_name}` na Evolution e
 *   devolve o `base64` na hora). Buscar o estado inicial não é polling — o
 *   Princípio 10 proíbe ficar perguntando de tempos em tempos, não proíbe ler
 *   o estado ao abrir a tela. É também o que faz a tela funcionar em
 *   desenvolvimento, onde a Evolution (`whats.polemk.com`) não tem como
 *   alcançar o `localhost:3000` para entregar webhook nenhum.
 * - **Renovação:** quem entrega o código seguinte é o
 *   `WhatsappInstanceChannel` por Action Cable (WebSocket). A Evolution chama
 *   o webhook `QRCODE_UPDATED`, o `WhatsAppWebhookService` grava e faz
 *   `ActionCable.server.broadcast`, e o `received` abaixo troca a imagem.
 *   Não há — e não pode haver — `setInterval` batendo em endpoint. O único
 *   timer desta tela é um relógio local de 1s que faz a contagem andar; ele
 *   não fala com a rede.
 *
 * ## Os dois modos de falha que a tela precisa admitir
 *
 * 1. **Socket caiu.** Sem isso a tela trava mostrando um código morto e a
 *    pessoa fica apontando a câmera para um quadrado que nunca vai funcionar.
 *    O `disconnected` do canal acende o aviso; o `connected` apaga.
 * 2. **Não deu para falar com a Evolution.** Moldura branca não é estado: se a
 *    busca falhar, a chapa diz o que aconteceu e oferece tentar de novo.
 *
 * Repare no que **não** é modo de falha: código vencido. A tela promete que o
 * código se renova sozinho, então vencer é um estado de **transição** — ela
 * esmaece o código e busca outro. Prometer automático e depois exigir clique é
 * pior do que nunca ter prometido.
 */

/**
 * Janela de segurança, em segundos, para quando a Evolution não informa
 * validade (hoje ela nunca informa: `expires_in` chega nulo). Passado esse
 * tempo sem nenhum código novo pelo socket, o da tela já não vale e a
 * renovação automática entra.
 */
const JANELA_QR_SEGUNDOS = 60

/**
 * Teto de renovações automáticas seguidas sem nenhum sinal de vida do socket.
 * Existe para que "renovar sozinho" não vire, num ambiente quebrado, um laço
 * infinito de requisições — que é exatamente o polling que o Princípio 10
 * proíbe. Chegando ao teto, a tela para e passa a decisão para a pessoa.
 * Qualquer `qrcode_updated` que chegue pelo canal zera a contagem.
 */
const MAX_RENOVACOES_AUTO = 10

type EstadoInstancia = 'connected' | 'connecting' | 'waiting_qr' | 'disconnected' | 'unknown'
type EstadoCanal = 'connecting' | 'live' | 'offline'

/** Normaliza o status: o banco guarda o mapeado, o socket às vezes traz o cru da Evolution. */
function normalizarEstado(bruto: unknown): EstadoInstancia {
  const s = String(bruto ?? '').toLowerCase()
  if (s === 'open' || s === 'connected') return 'connected'
  if (s === 'connecting') return 'connecting'
  if (s === 'qr' || s === 'waiting_qr') return 'waiting_qr'
  if (s === 'close' || s === 'closed' || s === 'disconnected') return 'disconnected'
  return 'unknown'
}

const rotuloEstado: Record<EstadoInstancia, { texto: string; variante: 'success' | 'warning' | 'info' | 'destructive' | 'secondary' }> = {
  connected: { texto: 'Conectado', variante: 'success' },
  connecting: { texto: 'Conectando', variante: 'warning' },
  waiting_qr: { texto: 'Aguardando leitura', variante: 'info' },
  disconnected: { texto: 'Desconectado', variante: 'destructive' },
  unknown: { texto: 'Sem informação', variante: 'secondary' },
}

/** A Evolution manda ora `data:image/png;base64,...`, ora o base64 pelado. */
function comoDataUrl(qr: string): string {
  return qr.startsWith('data:') ? qr : `data:image/png;base64,${qr}`
}

function formatarData(valor: unknown): string {
  if (!valor) return ''
  const d = new Date(String(valor))
  if (Number.isNaN(d.getTime())) return ''
  return d.toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' })
}

/**
 * Mensagem de falha em português e acionável.
 *
 * O axios devolve `"Network Error"` quando a requisição nem chegou ao servidor
 * — string em inglês, sem sujeito, que não diz à pessoa o que fazer. Numa tela
 * que depende de um serviço externo (a Evolution), "não respondeu" é exatamente
 * a informação que falta.
 */
function mensagemDeFalha(e: unknown): string {
  const bruta = mensagemDeErro(e)
  if (!bruta || /network error|timeout|failed to fetch/i.test(bruta)) {
    return 'O servidor do WhatsApp não respondeu. Verifique a conexão e tente de novo.'
  }
  return bruta
}

const PASSOS = [
  'Abra o WhatsApp no telefone que vai ficar conectado.',
  'Toque em Mais opções no Android, ou em Configurações no iPhone.',
  'Toque em Dispositivos conectados e depois em Conectar dispositivo.',
  'Aponte a câmera do telefone para o código desta tela.',
]

export function WhatsappPage() {
  const queryClient = useQueryClient()

  const {
    data: instance,
    isPending,
    error,
    refetch,
  } = useQuery({
    queryKey: ['whats-instance'],
    queryFn: () => instancesApi.getInstance(),
  })

  const instanceId: string | undefined = instance?.instance_id || instance?.data?.instanceId

  // — Estado do pareamento —
  const [qr, setQr] = useState<string | null>(null)
  /** Momento (epoch ms) em que o código atual chegou. Base do "frescor". */
  const [qrRecebidoEm, setQrRecebidoEm] = useState<number | null>(null)
  /** Prazo absoluto (epoch ms), quando conhecido. Nulo = regime de frescor. */
  const [qrPrazo, setQrPrazo] = useState<number | null>(null)
  const [estadoBruto, setEstadoBruto] = useState<unknown>(undefined)
  const [estadoCanal, setEstadoCanal] = useState<EstadoCanal>('connecting')
  const [agora, setAgora] = useState(() => Date.now())
  const [webhookUrl, setWebhookUrl] = useState('')
  /** Falha da última tentativa de buscar código. Nulo = sem falha pendente. */
  const [falha, setFalha] = useState<unknown>(null)
  const [renovacoesAuto, setRenovacoesAuto] = useState(0)
  const buscouRef = useRef(false)

  const estado = normalizarEstado(estadoBruto ?? instance?.connection_status)
  const conectado = estado === 'connected'

  /** Guarda o código novo e reinicia a contagem. Ponto único de verdade do QR. */
  const aplicarQr = useCallback((base64: string | null, prazoIso?: string | null, expiresIn?: number | null) => {
    if (!base64) {
      setQr(null)
      setQrRecebidoEm(null)
      setQrPrazo(null)
      return
    }
    setQr(base64)
    setQrRecebidoEm(Date.now())
    if (typeof expiresIn === 'number' && expiresIn > 0) {
      setQrPrazo(Date.now() + expiresIn * 1000)
      return
    }
    const t = prazoIso ? new Date(prazoIso).getTime() : NaN
    setQrPrazo(Number.isNaN(t) ? null : t)
  }, [])

  // Carga inicial: o que já estava gravado na instância.
  useEffect(() => {
    if (!instance) return
    setEstadoBruto(instance.connection_status)
    if (instance.qr_code) aplicarQr(instance.qr_code, instance.qr_expires_at)
  }, [instance, aplicarQr])

  /**
   * A busca do código. É o MESMO caminho para os três gatilhos — primeira
   * carga, renovação automática e botão manual — para que os três produzam
   * exatamente o mesmo resultado e o mesmo erro.
   *
   * `reiniciar` só vem do botão manual: derrubar e recriar a sessão na
   * Evolution é caro e só se justifica quando a pessoa pediu explicitamente.
   */
  const buscarCodigo = useMutation({
    mutationFn: async ({ reiniciar }: { reiniciar?: boolean } = {}) => {
      if (reiniciar) {
        try {
          await instancesApi.restart()
        } catch {
          // Reiniciar é melhor-esforço: se falhar, o connect abaixo ainda pode
          // devolver código, e é o erro dele que interessa relatar.
        }
      }
      const numero = instance?.number || instance?.raw_response?.number
      const res = await instancesApi.connect(numero || undefined)
      const d = res?.data
      const base64 = d?.base64 || d?.qrcode || d?.qrcodeBase64 || null
      if (!base64) throw new Error('O servidor do WhatsApp respondeu sem código de pareamento.')
      return base64
    },
    onSuccess: (base64) => {
      setFalha(null)
      aplicarQr(base64)
    },
    onError: (e) => setFalha(e),
  })

  // Primeira carga: busca o código uma vez. Não é polling — é ler o estado ao abrir.
  useEffect(() => {
    if (!instance || buscouRef.current) return
    if (normalizarEstado(instance.connection_status) === 'connected') return
    buscouRef.current = true
    buscarCodigo.mutate({})
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [instance])

  // ————————————————————————————————————————————————————————————————
  // Action Cable: a ÚNICA fonte de código novo depois da carga inicial.
  // ————————————————————————————————————————————————————————————————
  useChannel(
    'WhatsappInstanceChannel',
    { instance_id: instanceId },
    {
      connected: () => setEstadoCanal('live'),
      disconnected: () => setEstadoCanal('offline'),
      received: (data: WhatsRealtimeEvent) => {
        setEstadoCanal('live')
        switch (data?.type) {
          case 'connection_update': {
            setEstadoBruto(data.status)
            if (normalizarEstado(data.status) === 'connected') aplicarQr(null)
            break
          }
          case 'logout_instance': {
            setEstadoBruto('disconnected')
            aplicarQr(null)
            buscouRef.current = false
            break
          }
          case 'qrcode_updated': {
            // Chegou código pelo canal: o tempo real está entregando, então a
            // contagem de renovações automáticas volta a zero.
            setRenovacoesAuto(0)
            setFalha(null)
            aplicarQr(data.qr_code ?? null, data.qr_expires_at, data.expires_in)
            setEstadoBruto((atual: unknown) => (normalizarEstado(atual) === 'connected' ? 'waiting_qr' : atual))
            break
          }
          default:
            break
        }
      },
    },
  )

  // Relógio local de 1s. Não é polling: não toca na rede, só faz o número andar.
  // Para de girar quando não há nada para contar, para não acordar o render à toa.
  useEffect(() => {
    if (conectado || !qrRecebidoEm) return
    setAgora(Date.now())
    const t = setInterval(() => setAgora(Date.now()), 1000)
    return () => clearInterval(t)
  }, [conectado, qrRecebidoEm])

  const { restando, decorrido, fracao, expirado } = useMemo(() => {
    if (!qrRecebidoEm) return { restando: null as number | null, decorrido: 0, fracao: 0, expirado: false }
    const passou = Math.max(0, Math.floor((agora - qrRecebidoEm) / 1000))
    if (qrPrazo) {
      const falta = Math.ceil((qrPrazo - agora) / 1000)
      const total = Math.max(1, Math.round((qrPrazo - qrRecebidoEm) / 1000))
      return {
        restando: Math.max(0, falta),
        decorrido: passou,
        fracao: Math.min(1, Math.max(0, 1 - falta / total)),
        expirado: falta <= 0,
      }
    }
    return {
      restando: null,
      decorrido: passou,
      fracao: Math.min(1, passou / JANELA_QR_SEGUNDOS),
      expirado: passou >= JANELA_QR_SEGUNDOS,
    }
  }, [agora, qrRecebidoEm, qrPrazo])

  const socketCaiu = estadoCanal === 'offline' && !conectado
  const podeRenovarSozinho = renovacoesAuto < MAX_RENOVACOES_AUTO
  /** Transição, não erro: o código venceu e outro está a caminho. */
  const renovando = !conectado && !!qr && (buscarCodigo.isPending || (expirado && podeRenovarSozinho))
  /** Aqui sim acabou o automático e a decisão volta para a pessoa. */
  const renovacaoDesistiu = !conectado && expirado && !podeRenovarSozinho && !buscarCodigo.isPending

  // Renovação automática: vencer é transição. A tela prometeu que o código se
  // renova sozinho, então ela renova — sem parede de erro e sem exigir clique.
  // O teto de `MAX_RENOVACOES_AUTO` é o que impede isto de virar polling.
  useEffect(() => {
    if (conectado || !expirado || buscarCodigo.isPending) return
    if (!podeRenovarSozinho) return
    setRenovacoesAuto((n) => n + 1)
    buscarCodigo.mutate({})
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expirado, conectado, podeRenovarSozinho])

  // — Ações —
  const desconectar = useMutation({
    mutationFn: () => instancesApi.logout(),
    onSuccess: () => {
      setEstadoBruto('disconnected')
      aplicarQr(null)
      buscouRef.current = false
      queryClient.invalidateQueries({ queryKey: ['whats-instance'] })
      notify.success('Telefone desconectado')
    },
    onError: (e) => notify.error(mensagemDeErro(e) || 'Não foi possível desconectar'),
  })

  const salvarWebhook = useMutation({
    mutationFn: (url: string) =>
      webhooksApi.config({
        url,
        events: ['SEND_MESSAGE', 'MESSAGES_UPSERT', 'MESSAGES_UPDATE', 'CONNECTION_UPDATE', 'LOGOUT_INSTANCE', 'QRCODE_UPDATED'],
        webhookByEvents: true,
        webhookBase64: true,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['whats-instance'] })
      notify.success('Webhook configurado')
    },
    onError: (e) => notify.error(mensagemDeErro(e) || 'Não foi possível configurar o webhook'),
  })

  const webhooks: any[] = Array.isArray(instance?.polemk_webhooks) ? instance.polemk_webhooks : []

  // Preenche a URL base a partir do webhook já cadastrado, uma vez.
  useEffect(() => {
    if (webhookUrl || webhooks.length === 0) return
    const w = webhooks[0]
    const base = w?.raw_response?.webhook?.url
    if (base) {
      setWebhookUrl(String(base))
      return
    }
    const u = w?.url
    if (typeof u !== 'string' || !u) return
    try {
      const parsed = new URL(u)
      const seg = parsed.pathname.split('/').filter(Boolean)
      seg.pop()
      setWebhookUrl(parsed.origin + (seg.length ? '/' + seg.join('/') : ''))
    } catch {
      setWebhookUrl(u.split('/').slice(0, -1).join('/'))
    }
  }, [webhooks, webhookUrl])

  const copiar = async (texto: string) => {
    try {
      await navigator.clipboard.writeText(texto)
      notify.success('Copiado para a área de transferência')
    } catch {
      notify.error('Não foi possível copiar')
    }
  }

  const badge = rotuloEstado[estado]

  return (
    <div className="pb-10">
      <PageHeader
        title="Conexão do WhatsApp"
        subtitle={
          instance?.display_name || instance?.instance_name
            ? `Instância ${instance.display_name || instance.instance_name}`
            : 'Pareie um telefone para enviar e receber mensagens'
        }
        loading={buscarCodigo.isPending || desconectar.isPending}
        rightSlot={
          instance ? (
            <>
              <IndicadorCanal estado={estadoCanal} conectado={conectado} />
              <Badge variant={badge.variante}>{badge.texto}</Badge>
            </>
          ) : null
        }
      />

      <AsyncSection
        loading={isPending}
        error={error}
        data={instance ?? null}
        isEmpty={(d: any) => !d?.instance_id && !d?.data?.instanceId}
        onRetry={() => refetch()}
        loadingLabel="Carregando a instância…"
        emptyState={
          <div className="rounded-lg border border-border bg-card">
            <EmptyState
              icon={<Smartphone aria-hidden="true" className="h-5 w-5 text-muted-foreground" />}
              title="Nenhuma instância registrada"
              description="Não há instância de WhatsApp cadastrada para esta conta, então não há o que parear. Cadastre uma instância para começar."
            />
          </div>
        }
      >
        {() => (
          <div className="space-y-6">
            {/* ——— O palco: é isto que a pessoa veio fazer ——— */}
            <section className="overflow-hidden rounded-lg border border-border bg-card shadow-e1">
              {conectado ? (
                <PainelConectado
                  instance={instance}
                  desconectando={desconectar.isPending}
                  onDesconectar={() => desconectar.mutate()}
                />
              ) : (
                <div className="grid gap-8 p-6 lg:grid-cols-[22rem_minmax(0,1fr)] lg:gap-12 lg:p-8">
                  {/* Coluna do código */}
                  <div className="mx-auto w-full max-w-[22rem]">
                    <ChapaQr
                      qr={qr}
                      falha={falha}
                      buscando={buscarCodigo.isPending}
                      renovando={renovando}
                      desistiu={renovacaoDesistiu}
                      onTentarDeNovo={() => buscarCodigo.mutate({ reiniciar: true })}
                    />

                    <Contagem
                      // Com falha pendente a chapa já diz que não deu para
                      // falar com o servidor; deixar a contagem ao lado
                      // anunciando "renova sozinho" seria a tela se
                      // contradizendo na mesma dobra.
                      temQr={!!qr && !falha}
                      renovando={renovando}
                      restando={restando}
                      decorrido={decorrido}
                      fracao={fracao}
                    />

                    {/* Saída secundária: a renovação é automática, então este
                        botão é para quando ela não deu conta — nunca o caminho
                        normal. Por isso `secondary`, e não a ação principal. */}
                    <Button
                      variant="secondary"
                      className="mt-4 w-full"
                      loading={buscarCodigo.isPending}
                      onClick={() => buscarCodigo.mutate({ reiniciar: true })}
                    >
                      <RefreshCw aria-hidden="true" className="h-4 w-4" />
                      Gerar código novo
                    </Button>
                  </div>

                  {/* Coluna do passo a passo */}
                  <div className="flex min-w-0 flex-col">
                    {socketCaiu && <AvisoSocket onRecarregar={() => window.location.reload()} />}

                    <h2 className="font-title text-lg font-semibold text-foreground">Como conectar o telefone</h2>
                    <p className="mt-1 max-w-prose text-sm text-muted-foreground">
                      Quatro passos, no telefone que vai ficar pareado.
                    </p>

                    <ol className="mt-6 space-y-5">
                      {PASSOS.map((passo, i) => (
                        <li key={i} className="flex gap-4">
                          <span
                            aria-hidden="true"
                            className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-muted font-numeric text-xs font-bold tabular-nums text-muted-foreground"
                          >
                            {i + 1}
                          </span>
                          <span className="max-w-prose pt-1 text-sm leading-relaxed text-foreground">{passo}</span>
                        </li>
                      ))}
                    </ol>

                    <PainelEstado estado={estado} />
                  </div>
                </div>
              )}
            </section>

            {/* ——— Secundário: recolhido, porque não é o que a pessoa veio fazer ——— */}
            <section className="rounded-lg border border-border bg-card px-6">
              <Accordion type="multiple" className="w-full">
                <AccordionItem value="detalhes" className="border-border last:border-b-0">
                  <AccordionTrigger className="font-title text-sm font-semibold text-foreground hover:no-underline">
                    Detalhes da instância
                  </AccordionTrigger>
                  <AccordionContent>
                    <DetailList
                      columns={3}
                      items={[
                        { label: 'Nome', content: instance?.display_name || instance?.instance_name },
                        { label: 'Identificador', content: instanceId, numeric: true },
                        { label: 'Integração', content: instance?.integration },
                        { label: 'Número', content: instance?.number, numeric: true },
                        { label: 'Última conexão', content: formatarData(instance?.last_connection_at) },
                        { label: 'Último logout', content: formatarData(instance?.last_logout_at) },
                        { label: 'Motivo do logout', content: instance?.logout_reason, full: true },
                      ]}
                    />
                  </AccordionContent>
                </AccordionItem>

                <AccordionItem value="webhooks" className="border-b-0">
                  <AccordionTrigger className="font-title text-sm font-semibold text-foreground hover:no-underline">
                    Webhooks
                  </AccordionTrigger>
                  <AccordionContent className="space-y-4">
                    <p className="max-w-prose text-sm text-muted-foreground">
                      URL base que recebe os eventos da instância. Cada evento é entregue num caminho próprio
                      abaixo dela — é por aqui que o <code className="font-numeric text-xs">QRCODE_UPDATED</code>{' '}
                      chega e alimenta o código desta tela.
                    </p>

                    <div className="flex flex-wrap items-center gap-3">
                      <Input
                        className="min-w-0 flex-1"
                        placeholder="https://exemplo.com/whats"
                        aria-label="URL base do webhook"
                        value={webhookUrl}
                        onChange={(e) => setWebhookUrl(e.target.value)}
                      />
                      <Button
                        variant="secondary"
                        loading={salvarWebhook.isPending}
                        onClick={() => {
                          if (!webhookUrl.trim()) {
                            notify.error('Informe a URL do webhook')
                            return
                          }
                          salvarWebhook.mutate(webhookUrl.trim())
                        }}
                      >
                        Salvar
                      </Button>
                    </div>

                    {webhooks.length > 0 ? (
                      <ul className="divide-y divide-border rounded-md border border-border">
                        {webhooks.map((w: any) => (
                          <li key={w.id} className="flex items-center gap-3 px-3 py-2">
                            <span className="min-w-0 flex-1 truncate font-numeric text-xs text-muted-foreground">
                              {w.url}
                            </span>
                            <Button
                              variant="ghost"
                              size="icon"
                              className="h-8 w-8"
                              aria-label={`Copiar ${w.url}`}
                              onClick={() => copiar(w.url)}
                            >
                              <Copy aria-hidden="true" className="h-4 w-4" />
                            </Button>
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <p className="text-sm text-muted-foreground">Nenhum webhook configurado.</p>
                    )}
                  </AccordionContent>
                </AccordionItem>
              </Accordion>
            </section>
          </div>
        )}
      </AsyncSection>
    </div>
  )
}

/**
 * Indicador do socket. É o que impede o pior modo de falha: a tela parada
 * mostrando um código morto sem dizer nada. "Ao vivo" significa literalmente
 * "o canal está entregando"; qualquer outra coisa é dito com todas as letras.
 */
function IndicadorCanal({ estado, conectado }: { estado: EstadoCanal; conectado: boolean }) {
  if (conectado) return null

  if (estado === 'live') {
    return (
      <span className="inline-flex items-center gap-2 text-xs font-medium text-muted-foreground">
        <span className="relative flex h-2 w-2">
          <span
            aria-hidden="true"
            className="absolute inline-flex h-full w-full animate-ping rounded-full bg-success opacity-60 motion-reduce:hidden"
          />
          <span aria-hidden="true" className="relative inline-flex h-2 w-2 rounded-full bg-success" />
        </span>
        Ao vivo
      </span>
    )
  }

  if (estado === 'offline') {
    return (
      <span className="inline-flex items-center gap-2 text-xs font-medium text-destructive">
        <WifiOff aria-hidden="true" className="h-3.5 w-3.5" />
        Reconectando
      </span>
    )
  }

  return (
    <span className="inline-flex items-center gap-2 text-xs font-medium text-muted-foreground">
      <Spinner size="xs" label={null} />
      Conectando
    </span>
  )
}

/**
 * A chapa do QR.
 *
 * **O detalhe que fazia o código não ser lido:** o PNG que a Evolution devolve
 * é um campo branco opaco com os módulos VAZADOS (alfa zero) — não tem um pixel
 * escuro sequer. Quem pinta o módulo é o fundo de trás da imagem. A tela antiga
 * pousava esse PNG sobre `bg-muted`, então o código saía branco sobre cinza
 * claro: dava para ver que "tem um QR ali", mas o contraste era baixo demais
 * para a câmera. Por isso a imagem tem `bg-qr-module` (grafite) atrás e a chapa
 * clara em volta faz a zona de silêncio. Os dois tokens são iguais no claro e
 * no escuro de propósito: QR que inverte com o tema é QR que para de ler.
 *
 * Sem animação de entrada na imagem, também de propósito: um código que entra
 * em fade fica ilegível justamente nos primeiros quadros em que a câmera está
 * apontada para ele.
 *
 * As sobreposições são filhas da própria chapa (`relative`/`absolute`) e não
 * usam `backdrop-filter` — nada de contexto de empilhamento novo, nada de
 * portal: são conteúdo contido, não superfície flutuante.
 */
function ChapaQr({
  qr,
  falha,
  buscando,
  renovando,
  desistiu,
  onTentarDeNovo,
}: {
  qr: string | null
  falha: unknown
  buscando: boolean
  renovando: boolean
  desistiu: boolean
  onTentarDeNovo: () => void
}) {
  // Falha de rede vence tudo: moldura branca não é estado, e "não consegui
  // falar com o servidor" é acionável enquanto um quadrado vazio não é.
  if (falha) {
    return (
      <ChapaMoldura>
        <div className="flex h-full w-full flex-col items-center justify-center gap-3 px-6 text-center">
          <AlertTriangle aria-hidden="true" className="h-8 w-8 text-destructive" />
          <p className="font-title text-base font-semibold text-foreground">
            Não foi possível falar com o servidor do WhatsApp
          </p>
          <p className="max-w-[17rem] text-sm text-muted-foreground">{mensagemDeFalha(falha)}</p>
          <Button className="mt-1" loading={buscando} onClick={onTentarDeNovo}>
            <RefreshCw aria-hidden="true" className="h-4 w-4" />
            Tentar de novo
          </Button>
        </div>
      </ChapaMoldura>
    )
  }

  if (!qr) {
    return (
      <ChapaMoldura>
        <div className="flex h-full w-full flex-col items-center justify-center gap-3 text-muted-foreground">
          {buscando ? (
            <>
              <Spinner size="lg" label={null} />
              <span className="text-sm font-medium">Buscando o código…</span>
            </>
          ) : (
            <>
              <QrCode aria-hidden="true" className="h-10 w-10" />
              <span className="max-w-[16rem] text-center text-sm font-medium">Nenhum código disponível ainda</span>
            </>
          )}
        </div>
      </ChapaMoldura>
    )
  }

  return (
    <ChapaMoldura comQr>
      <img
        // A `key` no próprio código força a troca da imagem quando um QR novo
        // chega pelo socket, sem reaproveitar o quadro antigo.
        key={qr.slice(-32)}
        src={comoDataUrl(qr)}
        alt="QR Code de pareamento do WhatsApp"
        className={cn(
          // `bg-qr-module` é o que pinta os módulos vazados do PNG.
          'h-full w-full rounded-sm bg-qr-module object-contain transition-opacity duration-300',
          (renovando || desistiu) && 'opacity-25',
        )}
      />

      {/* Transição, não parede: o código venceu e outro está a caminho. Sem
          botão, porque não há nada que a pessoa precise decidir aqui. */}
      {renovando && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 bg-qr-plate/70 px-6 text-center">
          <Spinner size="lg" label={null} className="text-qr-plate-foreground/70" />
          <p className="font-title text-sm font-semibold text-qr-plate-foreground">Buscando um código novo…</p>
        </div>
      )}

      {/* Só aqui o automático desistiu de verdade, e a decisão volta para a pessoa. */}
      {desistiu && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-3 bg-qr-plate/85 px-6 text-center">
          <AlertTriangle aria-hidden="true" className="h-7 w-7 text-destructive" />
          <p className="font-title text-base font-semibold text-qr-plate-foreground">
            A renovação automática parou
          </p>
          <p className="max-w-[17rem] text-sm text-qr-plate-foreground/70">
            O código deixou de se renovar sozinho depois de várias tentativas. Gere outro para continuar.
          </p>
          <Button className="mt-1" loading={buscando} onClick={onTentarDeNovo}>
            <RefreshCw aria-hidden="true" className="h-4 w-4" />
            Gerar código novo
          </Button>
        </div>
      )}
    </ChapaMoldura>
  )
}

/**
 * A moldura da chapa — mesma caixa (e mesmo tamanho) para todos os estados,
 * para nada saltar na troca.
 *
 * `comQr` decide o fundo, e a decisão é funcional: o branco existe para servir
 * o código, então só aparece quando há código. Sem código, uma chapa branca no
 * modo escuro é só uma laje brilhante no meio da tela, servindo a nada.
 */
function ChapaMoldura({ children, comQr }: { children: React.ReactNode; comQr?: boolean }) {
  return (
    <div
      className={cn(
        'relative aspect-square w-full overflow-hidden rounded-lg border border-border p-5',
        comQr ? 'bg-qr-plate shadow-e1' : 'bg-muted',
      )}
    >
      {children}
    </div>
  )
}

/**
 * A linha de validade, logo abaixo da chapa. Dois regimes, e ela diz qual está
 * em vigor — com prazo conhecido é contagem regressiva; sem prazo é frescor.
 * Os números levam `font-numeric`/`tabular-nums`: sem isso a largura do dígito
 * muda a cada segundo e a linha inteira treme.
 */
function Contagem({
  temQr,
  renovando,
  restando,
  decorrido,
  fracao,
}: {
  temQr: boolean
  renovando: boolean
  restando: number | null
  decorrido: number
  fracao: number
}) {
  if (!temQr) return null

  // A esquerda diz o frescor (que é o MOTIVO da renovação) e a direita diz o
  // que está acontecendo. Repetir aqui a mesma frase da chapa seria eco, não
  // informação.
  const texto = restando !== null ? `Expira em ${restando}s` : `Atualizado há ${decorrido}s`

  return (
    <div className="mt-4">
      <div
        role="progressbar"
        aria-label="Validade do código"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={Math.round(fracao * 100)}
        className="h-1 w-full overflow-hidden rounded-full bg-muted"
      >
        <div
          className={cn('h-full rounded-full transition-[width] duration-1000 ease-linear', renovando ? 'bg-muted-foreground/40' : 'bg-primary')}
          style={{ width: `${Math.round((1 - fracao) * 100)}%` }}
        />
      </div>
      <p
        aria-live="polite"
        className={cn(
          'mt-2 flex items-center justify-between gap-2 text-xs',
          'text-muted-foreground',
        )}
      >
        <span className="font-numeric tabular-nums">{texto}</span>
        <span>{renovando ? 'Renovando…' : 'Renova sozinho'}</span>
      </p>
    </div>
  )
}

/** Cor de texto por variante de estado — o mesmo vocabulário semântico do `Badge`. */
const corEstado: Record<'success' | 'warning' | 'info' | 'destructive' | 'secondary', string> = {
  success: 'text-success',
  warning: 'text-warning',
  info: 'text-info',
  destructive: 'text-destructive',
  secondary: 'text-foreground',
}

const explicacaoEstado: Record<EstadoInstancia, string> = {
  connected: 'O telefone está pareado.',
  connecting: 'O telefone foi reconhecido e a sessão está sendo aberta. Não feche esta página.',
  waiting_qr: 'A instância está esperando alguém ler o código desta tela.',
  disconnected: 'A instância não tem telefone pareado. Leia o código para conectar um.',
  unknown: 'A instância ainda não relatou um estado.',
}

/**
 * Estado ao vivo, no rodapé da coluna do passo a passo.
 *
 * Fica aqui, e não só no cabeçalho, porque é onde o olho já está: a pessoa
 * acabou de ler os quatro passos e a próxima pergunta dela é "e agora, funcionou?".
 * O `mt-auto` empurra o painel para a base da coluna, o que também resolve o
 * vazio que sobrava ao lado da chapa do QR.
 */
function PainelEstado({ estado }: { estado: EstadoInstancia }) {
  const badge = rotuloEstado[estado]

  return (
    <div className="mt-8 rounded-md border border-border bg-muted/50 p-4 lg:mt-auto">
      <p className="text-[11px] font-bold uppercase tracking-widest text-muted-foreground">Estado agora</p>
      {/* O nome do estado sai como texto, e não como um segundo `Badge`: a
          mesma pílula já está no cabeçalho, e duas pílulas idênticas na mesma
          dobra leem como engano, não como ênfase. */}
      <p className="mt-2 text-sm text-muted-foreground">
        <span className={cn('font-semibold', corEstado[badge.variante])}>{badge.texto}</span>
        {' — '}
        {explicacaoEstado[estado]}
      </p>
      <p className="mt-3 text-xs text-muted-foreground">
        Esta tela se atualiza sozinha — o código e o estado chegam em tempo real. Não recarregue a página.
      </p>
    </div>
  )
}

/** Socket caiu: o código na tela pode estar morto e a pessoa precisa saber AGORA. */
function AvisoSocket({ onRecarregar }: { onRecarregar: () => void }) {
  return (
    <div className="mb-6 flex flex-wrap items-start gap-3 rounded-md border border-destructive/40 bg-destructive/10 p-4">
      <WifiOff aria-hidden="true" className="mt-0.5 h-5 w-5 shrink-0 text-destructive" />
      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold text-foreground">Conexão em tempo real perdida</p>
        <p className="mt-1 max-w-prose text-sm text-muted-foreground">
          O código desta tela deixou de se renovar sozinho e provavelmente já não funciona. Estamos tentando
          reconectar; se não voltar, recarregue a página.
        </p>
      </div>
      <Button variant="secondary" size="sm" onClick={onRecarregar}>
        <RefreshCw aria-hidden="true" className="h-4 w-4" />
        Recarregar
      </Button>
    </div>
  )
}

/** Conectado: o QR não tem mais função nenhuma, então some da tela inteira. */
function PainelConectado({
  instance,
  desconectando,
  onDesconectar,
}: {
  instance: any
  desconectando: boolean
  onDesconectar: () => void
}) {
  const desde = formatarData(instance?.last_connection_at)

  return (
    <div className="flex flex-wrap items-center gap-6 p-6 lg:p-8">
      <div
        aria-hidden="true"
        className="flex h-14 w-14 shrink-0 items-center justify-center rounded-full bg-success/15 text-success"
      >
        <Check className="h-7 w-7" />
      </div>

      <div className="min-w-0 flex-1">
        <h2 className="font-title text-lg font-semibold text-foreground">Telefone conectado</h2>
        <p className="mt-1 max-w-prose text-sm text-muted-foreground">
          {instance?.number ? (
            <>
              O número <span className="font-numeric tabular-nums text-foreground">{instance.number}</span> está
              pareado e recebendo mensagens.
            </>
          ) : (
            'A instância está pareada e recebendo mensagens.'
          )}
          {desde ? ` Conectado desde ${desde}.` : ''}
        </p>
      </div>

      <Button variant="destructive" loading={desconectando} onClick={onDesconectar}>
        <LogOut aria-hidden="true" className="h-4 w-4" />
        Desconectar telefone
      </Button>
    </div>
  )
}

export default WhatsappPage
