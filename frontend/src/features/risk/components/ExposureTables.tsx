import { AlertTriangle } from 'lucide-react'
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion'
import { Badge } from '@/components/ui/Badge'
import { Tooltip } from '@/components/ui/Tooltip'
import { cn } from '@/lib/utils'
import { formatPercent } from '@/lib/utils/number'
import type { ExposureRow, ExposureTypeGroup } from '../api/risk'

/**
 * S5 / FE-235, FE-236, FE-237, FE-238 — **as duas tabelas do console**.
 *
 * ### Regra que vale para o arquivo inteiro: nada é recalculado aqui
 *
 * Todo número desta tela vem de `Risk::AggregateService` e é impresso como
 * chegou. Os campos `formatted_*` chegam prontos **de propósito**: é neles que
 * vivem os dois erros de rótulo do **D-95**, que a **DEC-01** manda preservar.
 * Formatá-los no cliente "consertaria" o D-95 sem ninguém ter decidido isso — e
 * criaria a segunda fonte de verdade que o contrato **C2** existe para impedir.
 *
 * **QA: não abra bug** para "Liquidável" e "Pré-Faturamento" mostrando o mesmo
 * valor monetário que "Lim. util" quando há empresa selecionada. É intencional,
 * está no `improvements-log.md` como melhoria declinada, e há golden travando.
 *
 * ### O semáforo (FE-238)
 *
 * `limite_disponivel < 0` pinta "Lim. disp" com o token **negativo**; acima de
 * zero, com o token **positivo**. No legado só o caso negativo tinha cor
 * (`accent-red-color-text`) e o positivo era texto comum — o par existe para que
 * "está tudo bem" seja uma informação, e não a ausência de uma.
 *
 * Os tokens são `--negative` e `--success`, que já são os indicadores da marca
 * (`#7D1F1E` e `#217B55`, os mesmos valores do legado, definidos em `globals.css`
 * nos dois modos). Criar um par `--indicator-*` paralelo daria dois nomes para a
 * mesma cor — que é exatamente o que a decisão B-10 veio evitar.
 */

/** As colunas, na ordem do cabeçalho do legado. */
const COLUNAS = ['Liquidável', 'Pré-Faturamento', 'Lim. util', 'Lim. disp', 'Lim. total', 'Tax'] as const

export function ExposureByTypeTable({ grupos }: { grupos: ExposureTypeGroup[] }) {
  return (
    // Um cabeçalho por tipo ATIVO que tenha pelo menos um limite. Tipo sem
    // limite não aparece — é o `if !risk_controls_of_type.blank?` do legado.
    <Accordion type="multiple" className="space-y-3">
      {grupos.map((grupo) => (
        <AccordionItem
          key={grupo.id}
          value={grupo.id}
          className="overflow-hidden rounded-lg border border-border bg-card"
        >
          <AccordionTrigger className="px-4 hover:no-underline">
            <div className="flex w-full flex-col gap-2 pr-3 text-left lg:flex-row lg:items-center">
              <span className="min-w-[10rem] flex-1 font-medium text-foreground">{grupo.title}</span>

              <div className="grid flex-[3] grid-cols-2 gap-x-4 gap-y-2 sm:grid-cols-3 lg:grid-cols-6">
                <ResumoDoTipo rotulo="Liquidável" valor={`${grupo.formatted_liq} - ${grupo.perc_liq}%`} />
                <ResumoDoTipo
                  rotulo="Pré-Faturamento"
                  valor={grupo.has_pre ? `${grupo.formatted_pre} - ${grupo.perc_pre}%` : '—'}
                />
                <ResumoDoTipo rotulo="Lim. util" valor={`${grupo.formatted_util} - ${grupo.perc_util}%`} />
                <ResumoDoTipo rotulo="Lim. disp" valor={grupo.formatted_disp} negativo={grupo.disp < 0} positivo={grupo.disp >= 0} />
                <ResumoDoTipo rotulo="Lim. total" valor={grupo.formatted_total} />
                <ResumoDoTipo rotulo="Tax" valor="—" />
              </div>
            </div>
          </AccordionTrigger>

          <AccordionContent className="px-0 pb-0">
            <div className="overflow-x-auto border-t border-border">
              <table className="w-full min-w-[48rem] text-sm">
                <caption className="sr-only">Limites do tipo {grupo.title}</caption>
                <thead className="sr-only">
                  <tr>
                    <th scope="col">Portador</th>
                    {COLUNAS.map((c) => (
                      <th key={c} scope="col">
                        {c}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {grupo.rcs.map((linha, i) => (
                    <ExposureRowCells key={linha.id ?? linha.carrier_id ?? i} linha={linha} />
                  ))}
                </tbody>
              </table>
            </div>
          </AccordionContent>
        </AccordionItem>
      ))}
    </Accordion>
  )
}

/**
 * **Layout de portador único** (FE-236).
 *
 * Com o portador escolhido, o cabeçalho vira o portador e **cada linha vira um
 * tipo de limite**. O legado renderizava `r[:rcs].first` e **escondia em
 * silêncio** os demais quando havia mais de um limite para a combinação — o que
 * acontece com dado legado. Aqui a tela **avisa** em vez de esconder.
 */
export function ExposureSingleCarrier({
  grupos,
  carrierTitle,
}: {
  grupos: ExposureTypeGroup[]
  carrierTitle: string
}) {
  return (
    <div className="overflow-hidden rounded-lg border border-border bg-card">
      <div className="border-b border-border px-4 py-3">
        <p className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Portador</p>
        <p className="font-medium text-foreground">{carrierTitle}</p>
      </div>

      <div className="overflow-x-auto">
        <table className="w-full min-w-[48rem] text-sm">
          <caption className="sr-only">Exposição de {carrierTitle} por tipo de limite</caption>
          <thead>
            <tr className="border-b border-border text-xs uppercase tracking-[0.05em] text-muted-foreground">
              <th scope="col" className="px-4 py-2 text-left">
                Tipo
              </th>
              {COLUNAS.map((c) => (
                <th key={c} scope="col" className="px-4 py-2 text-right">
                  {c}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {grupos.map((grupo) => {
              const linha = grupo.rcs[0]
              if (!linha) return null
              return (
                <ExposureRowCells
                  key={grupo.id}
                  linha={{ ...linha, risk_title: grupo.title.toUpperCase(), risk_subtitle: '' }}
                  extras={grupo.rcs.length}
                />
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function ExposureRowCells({ linha, extras }: { linha: ExposureRow; extras?: number }) {
  const disponivel = Number(linha.limits.limite_disponivel)
  const negativo = disponivel < 0
  const agregaVarios = (linha.controls_count ?? 0) > 1 || (extras ?? 0) > 1

  return (
    <tr className="border-b border-border last:border-0">
      <th scope="row" className="px-4 py-2.5 text-left font-normal">
        <span className="flex items-center gap-1.5">
          <span className="font-medium text-foreground">{linha.risk_title}</span>
          {agregaVarios && (
            <Tooltip
              content={`Esta linha soma ${linha.controls_count ?? extras} limites da mesma combinação — é dado do formato antigo. O legado mostrava só o primeiro.`}
            >
              <Badge variant="secondary" className="shrink-0">
                <AlertTriangle aria-hidden="true" className="mr-1 h-3 w-3" />
                {linha.controls_count ?? extras} limites
              </Badge>
            </Tooltip>
          )}
        </span>
        {linha.risk_subtitle && <span className="block text-xs text-muted-foreground">{linha.risk_subtitle}</span>}
      </th>

      <Celula valor={linha.limits.formatted_limite_liquidavel} />
      <Celula valor={linha.has_pre ? linha.limits.formatted_limite_pre : '-'} />
      <Celula valor={linha.limits.formatted_limite_utilizado} />
      <Celula valor={linha.limits.formatted_limite_disponivel} negativo={negativo} positivo={!negativo} />
      <Celula valor={linha.limits.formatted_limite_total} />
      <Celula valor={formatPercent(Number(linha.limits.taxa))} />
    </tr>
  )
}

function Celula({ valor, negativo, positivo }: { valor: string; negativo?: boolean; positivo?: boolean }) {
  return (
    <td
      className={cn(
        'px-4 py-2.5 text-right font-numeric tabular-nums',
        negativo && 'text-negative',
        positivo && 'text-success',
      )}
    >
      {valor}
    </td>
  )
}

function ResumoDoTipo({
  rotulo,
  valor,
  negativo,
  positivo,
}: {
  rotulo: string
  valor: string
  negativo?: boolean
  positivo?: boolean
}) {
  return (
    <div>
      <p className="text-xs uppercase tracking-[0.05em] text-muted-foreground">{rotulo}</p>
      <p
        className={cn(
          'font-numeric tabular-nums text-foreground',
          negativo && 'text-negative',
          positivo && 'text-success',
        )}
      >
        {valor}
      </p>
    </div>
  )
}
