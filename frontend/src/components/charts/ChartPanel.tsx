import * as React from 'react'
import { BarChart3, Inbox, AlertTriangle, Table2 } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { mensagemDeErro } from '@/components/ui/AsyncSection'
import { formatAmount, formatMoney } from '@/lib/utils/number'
import { cn } from '@/lib/utils'

/**
 * **A moldura de um gráfico** — título, os quatro estados, e a *tabela gêmea*.
 *
 * ## Por que é membro da biblioteca, e não um bloco dentro da tela
 *
 * A base já tem `RechartsLine`, `RechartsBar` e `RechartsPie`, e eles desenham
 * — só isso. Nenhum deles sabe dizer "sem lançamentos no período", nenhum tem
 * estado de erro, e nenhum expõe os valores fora do tooltip. Escritos à mão em
 * cada tela, esses três pedaços divergem, e a tela que esquecer o erro só é
 * descoberta em produção (é a mesma razão de `AsyncSection` existir). Então a
 * moldura nasce **uma vez**, tokenizada, e as duas telas da S15 a reusam.
 *
 * ## A tabela gêmea não é enfeite de acessibilidade: é o valor exato
 *
 * Três coisas, medidas, exigem que os números também existam fora do desenho:
 *
 * 1. **O tooltip de `RechartsLine` imprime o número CRU** (`{val}` em
 *    `RechartsLine.tsx`), então um total de borderô aparece lá como
 *    `4346040.76` — ponto decimal de JavaScript no meio de uma coluna em reais.
 *    O componente é da base compartilhada e **não é editado aqui** (Princípio
 *    6b); a limitação está registrada em `upstream-flags.md`.
 * 2. **O ouro da marca sobre o card branco dá 1,63:1** (medido com o validador
 *    do `dataviz`, modo claro, superfície `#ffffff`). Abaixo de 3:1 a regra é
 *    explícita: **exige alívio** — rótulo visível ou tabela. Aqui é a tabela.
 * 3. **Tooltip não pode ser o único caminho para o valor.** Ele não existe no
 *    teclado nem no toque, e some do leitor de tela.
 *
 * A tabela é `<table>` de verdade, com `<caption>` e `<th scope>`, e fica
 * fechada por padrão para não competir com o desenho.
 *
 * ## O que este componente NÃO faz
 *
 * Não calcula. Recebe `labels` e `values` prontos do servidor e formata. Somar,
 * tirar média ou derivar variação aqui criaria a segunda implementação da
 * fórmula (contrato C2 / D-09) — e a nota de escopo de `indicators` continua
 * proibindo série derivada.
 */
export type ChartValueFormat = 'currency' | 'decimal'

export interface ChartPanelProps {
  title: string
  /** Uma linha dizendo **o que** e **de quando** — nunca decorativa. */
  subtitle?: React.ReactNode
  /** Carregamento inicial. Reserva a altura do gráfico: o número não empurra a página. */
  loading?: boolean
  error?: unknown
  onRetry?: () => void
  /**
   * `false` desenha o estado de ausência. É o chamador que decide o que é
   * ausência — "nenhum lançamento" e "tudo zerado" são coisas diferentes, e o
   * servidor manda `has_data` justamente para não confundi-las.
   */
  hasData?: boolean
  emptyTitle?: string
  emptyDescription?: string
  /**
   * Substitui a moldura padrão do estado vazio. Existe porque "não há dado" nem
   * sempre é a mesma notícia: um painel de alerta vazio é uma **boa** notícia, e
   * o ícone de caixa vazia diria o contrário.
   */
  emptyState?: React.ReactNode
  /** Os mesmos dados que o gráfico desenha, para a tabela gêmea. */
  labels: string[]
  values: number[]
  valueFormat?: ChartValueFormat
  /** Cabeçalho da coluna de rótulos na tabela ("Mês", "Portador"). */
  labelHeader?: string
  valueHeader?: string
  /** Ação extra no cabeçalho (um seletor que já pertence à tela). */
  headerSlot?: React.ReactNode
  /**
   * Esconde o gêmeo "Ver valores". Só para o painel cujo **conteúdo já é a
   * tabela** — ali o gêmeo repetiria a mesma informação duas vezes, e a razão
   * de ele existir (o valor fora do desenho) já está satisfeita.
   */
  hideValueTable?: boolean
  className?: string
  /** O gráfico. Só é montado quando há dado — série vazia não vira linha em zero. */
  children: React.ReactNode
}

/** A altura de `RechartsLine`/`RechartsBar` (260px) mais a faixa do eixo X. */
const ALTURA_GRAFICO = 'min-h-[16.25rem]'

function formatar(valor: number, formato: ChartValueFormat) {
  return formato === 'currency' ? formatMoney(valor) : formatAmount(valor)
}

export function ChartPanel({
  title,
  subtitle,
  loading = false,
  error,
  onRetry,
  hasData = true,
  emptyTitle = 'Sem dados no período',
  emptyDescription,
  emptyState,
  labels,
  values,
  valueFormat = 'currency',
  labelHeader = 'Rótulo',
  valueHeader = 'Valor',
  headerSlot,
  hideValueTable = false,
  className,
  children,
}: ChartPanelProps) {
  const [tabelaAberta, setTabelaAberta] = React.useState(false)
  const idTabela = React.useId()

  return (
    <section className={cn('rounded-lg bg-card p-4 shadow-e1', className)} aria-labelledby={`${idTabela}-titulo`}>
      <header className="mb-3 flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <h3 id={`${idTabela}-titulo`} className="font-title text-sm font-semibold text-foreground">
            {title}
          </h3>
          {subtitle && <p className="mt-0.5 text-xs text-muted-foreground">{subtitle}</p>}
        </div>
        {headerSlot}
      </header>

      {/* A ordem de decisão é a do `AsyncSection`, e pelo mesmo motivo: **erro
          vence carregamento**. Numa refetch que falha, o React Query mantém
          `isFetching` por um instante junto com o erro — se o carregamento
          vencesse, a tela giraria para sempre sobre uma falha. */}
      {error ? (
        <div role="alert" className={cn('flex flex-col items-center justify-center gap-3 text-center', ALTURA_GRAFICO)}>
          <span className="flex h-11 w-11 items-center justify-center rounded-full bg-destructive/10 text-destructive">
            <AlertTriangle className="h-5 w-5" />
          </span>
          <div className="space-y-1">
            <p className="text-sm font-semibold text-foreground">Não foi possível carregar o gráfico</p>
            <p className="max-w-sm text-xs text-muted-foreground">
              {mensagemDeErro(error) ?? 'A consulta falhou. Nada foi perdido — pode tentar de novo.'}
            </p>
          </div>
          {onRetry && (
            <Button variant="secondary" size="sm" onClick={onRetry}>
              Tentar de novo
            </Button>
          )}
        </div>
      ) : loading ? (
        // Esqueleto com a MESMA altura do gráfico: o número não desloca o
        // layout quando chega. Spinner aqui faria a página pular.
        <div
          role="status"
          aria-busy
          aria-label={`Carregando ${title}`}
          className={cn('animate-pulse rounded-md bg-muted/50', ALTURA_GRAFICO)}
        />
      ) : !hasData ? (
        emptyState ?? (
        <div role="status" className={cn('flex flex-col items-center justify-center gap-3 text-center', ALTURA_GRAFICO)}>
          <span className="flex h-11 w-11 items-center justify-center rounded-full bg-muted text-muted-foreground">
            <Inbox className="h-5 w-5" />
          </span>
          <div className="space-y-1">
            <p className="text-sm font-semibold text-foreground">{emptyTitle}</p>
            {emptyDescription && <p className="max-w-sm text-xs text-muted-foreground">{emptyDescription}</p>}
          </div>
        </div>
        )
      ) : (
        <>
          {children}

          {!hideValueTable && (
          <div className="mt-2 flex justify-end">
            <Button
              variant="ghost"
              size="sm"
              aria-expanded={tabelaAberta}
              aria-controls={idTabela}
              onClick={() => setTabelaAberta((v) => !v)}
            >
              {tabelaAberta ? <BarChart3 className="h-4 w-4" /> : <Table2 className="h-4 w-4" />}
              {tabelaAberta ? 'Ocultar valores' : 'Ver valores'}
            </Button>
          </div>
          )}

          {!hideValueTable && tabelaAberta && (
            // O contêiner rola sozinho: no telefone (390 px) a tabela nunca
            // empurra a página para os lados (DEC-100).
            <div id={idTabela} className="mt-1 max-h-64 overflow-auto rounded-md border border-border">
              <table className="w-full text-sm">
                <caption className="sr-only">{title} — valores exatos</caption>
                <thead className="sticky top-0 bg-muted/60 text-xs uppercase tracking-wide text-muted-foreground">
                  <tr>
                    <th scope="col" className="px-3 py-2 text-left font-semibold">
                      {labelHeader}
                    </th>
                    <th scope="col" className="px-3 py-2 text-right font-semibold">
                      {valueHeader}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {labels.map((rotulo, i) => (
                    <tr key={`${rotulo}-${i}`} className="border-t border-border">
                      <th scope="row" className="px-3 py-1.5 text-left font-normal text-foreground">
                        {rotulo}
                      </th>
                      {/* `font-numeric` (tabular-nums) porque é coluna de valor:
                          sem ela os centavos não alinham, e neste app isso é
                          defeito, não estética. */}
                      <td className="px-3 py-1.5 text-right font-numeric text-foreground">
                        {formatar(values[i] ?? 0, valueFormat)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}
    </section>
  )
}
