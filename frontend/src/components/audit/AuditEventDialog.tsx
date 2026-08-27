import * as React from 'react'
import { ArrowRight, ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { DetailList } from '@/components/ui/DetailList'
import { formatDateTime } from '@/lib/utils/date'
import { auditAppearance } from './auditAppearance'
import type { AuditVersion } from '@/lib/api/auditTrail'

/**
 * Detalhe de UM evento da trilha — `FE-446`.
 *
 * **Por que diálogo e não gaveta.** Isto é leitura de um registro: pares
 * rótulo/valor, identificadores longos e um diff antes→depois. O `Sheet` é a
 * gaveta de **formulário** — estreita e alta de propósito, porque formulário é
 * uma coluna de campos. Aqui ela picotava UUID no meio, espremia o diff em
 * duas colunas de 200 px e deixava metade da altura vazia. Um detalhe de
 * leitura é **diálogo modal centrado**, com largura para o conteúdo.
 *
 * **No telefone o diálogo vai a tela cheia** (`fullScreenOnMobile`), que é o
 * padrão nativo para "abrir um registro" e o que a DEC-100 pede: no aparelho a
 * densidade é repensada, não encolhida. A caixa centrada de 390 px sobraria
 * com ~300 px úteis — ilegível justamente para o diff, que é o coração da tela.
 *
 * **O diff é o assunto**, então ele é uma grade de três colunas com cabeçalho
 * (campo · antes · depois) no desktop e blocos rotulados no telefone. O valor
 * antigo **não** leva `line-through`: numa auditoria ele é dado que se lê e se
 * copia, não texto cancelado. A distinção fica na cor **e** no rótulo — cor
 * nunca é o único portador (regra de acessibilidade do PRODUCT.md).
 *
 * **A foto completa do estado anterior (DEC-78)** continua colapsada e com
 * rolagem própria: ela é o que permite reconstruir o registro em qualquer ponto
 * do tempo, mas aberta por padrão empurraria todo o resto para fora da tela.
 */
export interface AuditEventDialogProps {
  /** A versão escolhida na lista. `null` fecha o diálogo. */
  version: AuditVersion | null
  /** Foto completa do estado anterior — vem do detalhe, não do índice (DEC-78). */
  snapshot?: Record<string, unknown> | null
  snapshotLoading?: boolean
  onOpenChange: (aberto: boolean) => void
}

/** Um valor de auditoria vira texto sem perder o que ele era. */
function comoTexto(valor: unknown): string {
  if (valor === null || valor === undefined || valor === '') return '—'
  if (typeof valor === 'boolean') return valor ? 'sim' : 'não'
  if (typeof valor === 'object') return JSON.stringify(valor)
  return String(valor)
}

/**
 * Identificador (UUID, hash, chave) merece monoespaçado: é para ser conferido
 * caractere a caractere, e a proporcional faz `0`/`O` e `1`/`l` se confundirem
 * exatamente onde isso custa caro.
 */
function pareceIdentificador(campo: string, texto: string): boolean {
  if (/(^|_)(id|uuid|token|jti|hash|slug)$/i.test(campo)) return true
  return /^[0-9a-f]{8,}(-[0-9a-f]{4,}){0,4}$/i.test(texto)
}

function Valor({
  rotulo,
  texto,
  mono,
  tone,
}: {
  rotulo: string
  texto: string
  mono: boolean
  tone: 'antes' | 'depois'
}) {
  return (
    <div className="min-w-0">
      {/* O rótulo só aparece no telefone, onde as colunas viram pilha e a
          posição deixa de dizer qual valor é qual. */}
      <span className="mb-1 block text-[10px] font-bold uppercase tracking-widest text-muted-foreground sm:hidden">
        {rotulo}
      </span>
      <p
        className={cn(
          // `break-words` quebra o UUID nos hífens, que são as junções que ele
          // já tem — nunca no meio de um segmento.
          'break-words rounded-md px-2 py-1.5 text-xs leading-relaxed',
          mono && 'font-mono',
          tone === 'antes'
            ? 'bg-muted text-muted-foreground'
            : 'bg-primary/10 text-foreground',
        )}
      >
        {texto}
      </p>
    </div>
  )
}

/** Grade do diff — três colunas no desktop, pilha rotulada no telefone. */
const GRADE = 'sm:grid-cols-[minmax(7rem,0.8fr)_minmax(0,1.4fr)_auto_minmax(0,1.4fr)]'

export function AuditEventDialog({
  version,
  snapshot,
  snapshotLoading,
  onOpenChange,
}: AuditEventDialogProps) {
  const aparencia = version ? auditAppearance(version.event) : null
  const mudancas = Object.entries(version?.changes ?? {})

  return (
    <Dialog open={version !== null} onOpenChange={onOpenChange}>
      <DialogContent
        fullScreenOnMobile
        // A largura é o conserto, e a medida é o conteúdo: um UUID em 12 px
        // monoespaçado pede ~260 px de coluna. `max-w-lg` (512 px) é a medida
        // de um formulário curto; em `3xl` o identificador ainda quebrava. Em
        // `4xl` as duas colunas de valor cabem inteiras.
        className="sm:max-w-4xl"
      >
        {version && aparencia && (
          <>
            <DialogHeader className="shrink-0 pr-10 text-left sm:text-left">
              <span
                className={cn(
                  'mb-1 inline-flex w-fit items-center gap-1.5 rounded-full px-2.5 py-1 text-[11px] font-bold uppercase tracking-widest',
                  aparencia.tone,
                )}
              >
                <aparencia.icon aria-hidden="true" className="h-3.5 w-3.5" />
                {aparencia.label}
              </span>
              <DialogTitle className="font-title text-lg font-semibold sm:text-xl">
                {version.summary}
              </DialogTitle>
              {/* Sem `id` próprio: o Radix liga `aria-describedby` sozinho, e
                  sobrescrever o id dele deixa o diálogo sem descrição. */}
              <DialogDescription>
                {version.entity_label}{' '}
                {/* `break-words`, não `break-all`: a quebra acontece nos
                    hífens que o UUID já tem, nunca no meio de um segmento. */}
                <span className="font-mono text-xs break-words">#{version.item_id}</span>
              </DialogDescription>
            </DialogHeader>

            {/* O corpo é quem rola. Sem `min-h-0` o flex não deixa o filho
                encolher e a rolagem vaza para a página inteira. */}
            <div className="-mx-1 min-h-0 flex-1 space-y-6 overflow-y-auto px-1 pb-1 sm:max-h-[62vh]">
              <DetailList
                items={[
                  { label: 'Autor', content: version.author?.name ?? version.author?.email ?? 'sistema' },
                  { label: 'Quando', content: formatDateTime(version.occurred_at) },
                  ...(version.impersonated
                    ? [
                        {
                          label: 'Personificando',
                          content:
                            version.impersonated.name ??
                            version.impersonated.email ??
                            version.impersonated.id,
                        },
                      ]
                    : []),
                  {
                    label: 'Origem',
                    content: version.ip_address ? (
                      <span className="font-mono text-xs">{version.ip_address}</span>
                    ) : (
                      '—'
                    ),
                  },
                  { label: 'Motivo', content: version.reason ?? '—', full: true },
                ]}
                columns={3}
              />

              <section>
                <h3 className="mb-2 text-[11px] font-bold uppercase tracking-widest text-muted-foreground">
                  O que mudou
                </h3>

                {mudancas.length === 0 ? (
                  // Acontece de verdade: impersonação não altera campo. Uma
                  // seção com título e nada embaixo parece falha de carga.
                  <p className="rounded-lg border border-dashed border-border px-4 py-6 text-center text-sm text-muted-foreground">
                    Este evento não registra alteração de campo.
                  </p>
                ) : (
                  <div className="overflow-hidden rounded-lg border border-border">
                    <div
                      className={cn(
                        'hidden gap-x-4 border-b border-border bg-muted/40 px-4 py-2 text-[10px] font-bold uppercase tracking-widest text-muted-foreground sm:grid',
                        GRADE,
                      )}
                    >
                      <span>Campo</span>
                      <span>Antes</span>
                      <span aria-hidden="true" />
                      <span>Depois</span>
                    </div>

                    {mudancas.map(([campo, [antes, depois]]) => {
                      const txtAntes = comoTexto(antes)
                      const txtDepois = comoTexto(depois)
                      const mono =
                        pareceIdentificador(campo, txtAntes) || pareceIdentificador(campo, txtDepois)
                      return (
                        <div
                          key={campo}
                          className={cn(
                            'grid grid-cols-1 gap-x-4 gap-y-2 border-b border-border px-4 py-3 last:border-b-0 sm:items-start',
                            GRADE,
                          )}
                        >
                          <span className="break-words pt-1.5 font-mono text-xs font-medium text-foreground">
                            {campo}
                          </span>
                          <Valor rotulo="Antes" texto={txtAntes} mono={mono} tone="antes" />
                          <ArrowRight
                            aria-hidden="true"
                            className="mt-2.5 hidden h-4 w-4 shrink-0 text-muted-foreground sm:block"
                          />
                          <Valor rotulo="Depois" texto={txtDepois} mono={mono} tone="depois" />
                        </div>
                      )
                    })}
                  </div>
                )}
              </section>

              {/* DEC-78 — a foto COMPLETA do estado anterior. Colapsada, com
                  rolagem própria, para não empurrar o diff para fora da tela. */}
              <section>
                {snapshotLoading && (
                  <p className="text-xs text-muted-foreground">Carregando o estado anterior…</p>
                )}
                {snapshot && (
                  <details className="group rounded-lg border border-border">
                    <summary className="flex cursor-pointer list-none items-center justify-between gap-2 px-4 py-3 text-[11px] font-bold uppercase tracking-widest text-muted-foreground hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring">
                      Estado completo antes da mudança
                      <ChevronRight
                        aria-hidden="true"
                        className="h-4 w-4 shrink-0 transition-transform group-open:rotate-90"
                      />
                    </summary>
                    <pre className="max-h-[40vh] overflow-auto border-t border-border bg-muted/40 p-4 text-xs leading-relaxed text-foreground">
                      {JSON.stringify(snapshot, null, 2)}
                    </pre>
                  </details>
                )}
              </section>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  )
}
