import { RichTextView } from '@/components/ui/RichTextField'
import { Badge } from '@/components/ui/Badge'
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion'
import type { GridRow } from '@/lib/api/indicators'
import { nomeDoMes } from '../lib/periodo'
import { EntryCell } from './EntryCell'

/**
 * `FE-326`, `FE-327`, `FE-719` — **a grade mensal**.
 *
 * Um cartão por indicador. Em **todos os meses**, 12 linhas (Jan..Dez), cada uma
 * com gravação independente. Em **mês único**, o indicador vira **uma linha só**,
 * rotulada com o título dele em vez do nome do mês.
 *
 * ## Duas diferenças com o legado, e as duas são do usuário
 *
 * **1. A instrução aparece nos dois modos** (`FE-327`). No legado o bloco de
 * instrução só existe no ramo de 12 meses
 * (`indicator_entries/list/_widget.html.erb:8-12`); quem filtra por um mês
 * específico **perde a explicação de como preencher** exatamente na hora de
 * preencher.
 *
 * **2. No modo mês único NÃO há título clicável** (`FE-719`). É interação que
 * não existe nesse modo no legado — replicado. A instrução fica aberta, porque
 * não há acordeão para escondê-la.
 */
export interface MonthlyGridProps {
  linhas: GridRow[]
  year: number
  /** `null` = os 12 meses. */
  mes: number | null
  somenteLeitura: boolean
}

export function MonthlyGrid({ linhas, year, mes, somenteLeitura }: MonthlyGridProps) {
  const mesUnico = mes !== null

  if (mesUnico) {
    return (
      <div className="rounded-lg border border-border bg-card p-4">
        <h3 className="mb-1 font-title text-sm font-semibold uppercase tracking-[0.05em] text-muted-foreground">
          {nomeDoMes(mes)} de {year}
        </h3>
        <div className="space-y-3 pt-2">
          {/* `cells[0]` só existe porque o serviço devolve exatamente uma célula
              quando `month` é informado. A guarda existe mesmo assim: o dia em
              que o contrato mudar, a tela mostra uma linha a menos em vez de
              derrubar a grade inteira com `Cannot read properties of undefined`
              — que é o modo de falha que `tsc` não pega. */}
          {linhas.filter((linha) => linha.cells.length > 0).map((linha) => (
            <div key={linha.indicator.id} className="space-y-2 border-t border-border pt-3 first:border-0 first:pt-0">
              <EntryCell
                indicatorId={linha.indicator.id}
                year={year}
                cell={linha.cells[0]}
                // Modo mês único: o rótulo é o TÍTULO do indicador, não o mês.
                rotulo={linha.indicator.title}
                somenteLeitura={somenteLeitura}
              />
              {linha.indicator.description_html && (
                <RichTextView html={linha.indicator.description_html} className="pl-1" />
              )}
            </div>
          ))}
        </div>
      </div>
    )
  }

  return (
    <Accordion type="single" collapsible className="space-y-3">
      {linhas.map((linha) => (
        <div key={linha.indicator.id} className="rounded-lg border border-border bg-card p-4">
          <div className="flex items-start justify-between gap-3">
            {linha.indicator.description_html ? (
              <AccordionItem value={linha.indicator.id} className="flex-1 border-0">
                <AccordionTrigger className="py-0 text-left hover:no-underline">
                  <span className="font-title text-sm font-semibold uppercase tracking-[0.05em] text-foreground">
                    {linha.indicator.title}
                  </span>
                </AccordionTrigger>
                <AccordionContent className="pb-0 pt-3">
                  <RichTextView html={linha.indicator.description_html} />
                </AccordionContent>
              </AccordionItem>
            ) : (
              <h3 className="flex-1 font-title text-sm font-semibold uppercase tracking-[0.05em] text-foreground">
                {linha.indicator.title}
              </h3>
            )}
            {/* Quantos meses do ano já têm lançamento — leitura que o legado não
                dava, e que a grade responde de graça agora que "não lançado" é
                distinguível de zero (DEC-70). */}
            <Badge variant="secondary" className="shrink-0 font-numeric tabular-nums">
              {linha.cells.filter((c) => c.entry !== null).length}/12
            </Badge>
          </div>

          <div className="mt-3 grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
            {linha.cells.map((cell) => (
              <EntryCell
                key={cell.month}
                indicatorId={linha.indicator.id}
                year={year}
                cell={cell}
                rotulo={nomeDoMes(cell.month)}
                somenteLeitura={somenteLeitura}
              />
            ))}
          </div>
        </div>
      ))}
    </Accordion>
  )
}
