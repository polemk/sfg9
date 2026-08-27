import { Plus, Trash2, Undo2 } from 'lucide-react'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { MoneyInput } from '@/components/ui/MoneyInput'
import { Select } from '@/components/ui/Select'
import { formatMoney } from '@/lib/utils/number'
import type { MovementKind } from '../api/receivables'

/**
 * **As tarifas do borderô** (FE-175, FE-176).
 *
 * ## DEC-72 — remover tarifa fica PENDENTE até o Salvar
 *
 * No legado o botão de remover disparava um `DELETE` direto ao confirmar o
 * modal (`../sfg/app/views/pub/receivables/new/_body.js.erb:663-681`, linha
 * 674), **fora de qualquer submit**. O servidor apagava
 * (`receivable_taxes_controller.rb:15-24`) e **não recalculava o borderô pai**:
 * os `tarifas_*` só se corrigiam no próximo save, e entre uma coisa e outra o
 * borderô exibia total errado.
 *
 * A **DEC-72** trocou isso: a remoção é marcada aqui, o Salvar a executa dentro
 * da mesma transação que recalcula, e **Cancelar desfaz**. É exceção consciente
 * ao DEC-30, com o critério escrito na decisão: *"o que se preserva não é um
 * número, é uma janela em que o número está errado"*.
 *
 * Por isso a linha removida **não some da tela**: ela fica riscada, com um
 * botão de desfazer. Sumir seria mentir sobre o estado do servidor.
 *
 * ## Duplicidade de tipo continua PERMITIDA (Q-B15)
 *
 * Duas linhas de "Outras Despesas" no mesmo borderô são válidas — o legado
 * aceita e produção tem. Uma unicidade nova recusaria lançamento que existe.
 *
 * ## O total é do SERVIDOR
 *
 * Esta lista **não soma nada**. O total de tarifas que aparece no painel de
 * cálculo vem de `POST /receivables/preview` — contrato C2. O que se mostra
 * aqui embaixo é a soma **em exibição**, marcada como tal, para o usuário
 * conferir o que digitou; ela não alimenta cálculo nenhum.
 */
export interface TaxRow {
  /** Presente = tarifa já gravada. Ausente = linha nova. */
  id?: string
  movement_kind_id: string
  value: number | null
  /** Marcada para remoção no Salvar (DEC-72). Nunca some da tela antes disso. */
  removida?: boolean
  /** Chave estável de renderização — o id do banco não existe em linha nova. */
  chave: string
}

const CLASSIFICADOR_ROTULO: Record<string, string> = {
  is_advalorem: 'AdValorem',
  is_desagio: 'Deságio',
  is_iof: 'IOF',
  is_liquidation: 'Liquidação',
}

export function TaxRows({
  rows,
  kinds,
  disabled,
  onChange,
}: {
  rows: TaxRow[]
  kinds: MovementKind[]
  disabled?: boolean
  onChange: (rows: TaxRow[]) => void
}) {
  const opcoes = kinds.map((k) => ({
    value: k.id,
    label: k.title,
    description: k.tax_classifier ? CLASSIFICADOR_ROTULO[k.tax_classifier] : 'Entra em "Outras"',
  }))

  function atualizar(chave: string, mudanca: Partial<TaxRow>) {
    onChange(rows.map((r) => (r.chave === chave ? { ...r, ...mudanca } : r)))
  }

  function remover(row: TaxRow) {
    // Linha ainda não gravada some na hora: não há nada no servidor para
    // desfazer. Linha persistida fica marcada — é a DEC-72.
    if (!row.id) {
      onChange(rows.filter((r) => r.chave !== row.chave))
      return
    }
    atualizar(row.chave, { removida: true })
  }

  function acrescentar() {
    // A linha nova entra **no topo**, como no legado: é onde o olho já está
    // depois de clicar no botão.
    onChange([
      { chave: `nova-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`, movement_kind_id: '', value: null },
      ...rows,
    ])
  }

  const ativas = rows.filter((r) => !r.removida)
  const somaExibida = ativas.reduce((acc, r) => acc + (r.value ?? 0), 0)
  const pendentes = rows.filter((r) => r.removida).length

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h3 className="font-title text-sm font-semibold text-foreground">Tarifas</h3>
          <p className="text-xs text-muted-foreground">
            O classificador de cada tipo decide se a tarifa entra na base do IOF. Duas linhas do mesmo tipo são
            permitidas.
          </p>
        </div>
        {!disabled && (
          <Button type="button" variant="secondary" size="sm" onClick={acrescentar}>
            <Plus aria-hidden="true" className="h-4 w-4" />
            Acrescentar tarifa
          </Button>
        )}
      </div>

      {rows.length === 0 ? (
        <p className="rounded-md border border-dashed border-border px-4 py-6 text-center text-sm text-muted-foreground">
          Nenhuma tarifa. Sem tarifa o borderô não tem deságio nem IOF, e o custo efetivo sai zero.
        </p>
      ) : (
        <ul className="space-y-2">
          {rows.map((row) => {
            const tipo = kinds.find((k) => k.id === row.movement_kind_id)
            return (
              <li
                key={row.chave}
                className={
                  'grid grid-cols-1 items-start gap-2 rounded-md border border-border p-2 sm:grid-cols-[1fr_10rem_auto] ' +
                  (row.removida ? 'opacity-60' : '')
                }
              >
                <div className="space-y-1">
                  <Select
                    aria-label="Tipo de tarifa"
                    placeholder="Escolha o tipo…"
                    value={row.movement_kind_id || null}
                    disabled={disabled || row.removida}
                    onChange={(v) => atualizar(row.chave, { movement_kind_id: v })}
                    options={opcoes}
                  />
                  {tipo?.tax_classifier && (
                    <Badge variant="secondary">{CLASSIFICADOR_ROTULO[tipo.tax_classifier]}</Badge>
                  )}
                </div>

                <MoneyInput
                  aria-label="Valor da tarifa"
                  value={row.value}
                  disabled={disabled || row.removida}
                  onChange={(v) => atualizar(row.chave, { value: v })}
                />

                {!disabled && (
                  <div className="flex items-center justify-end">
                    {row.removida ? (
                      <Button
                        type="button"
                        variant="ghost"
                        size="sm"
                        onClick={() => atualizar(row.chave, { removida: false })}
                      >
                        <Undo2 aria-hidden="true" className="h-4 w-4" />
                        Desfazer
                      </Button>
                    ) : (
                      <Button
                        type="button"
                        variant="ghost"
                        size="icon"
                        aria-label="Remover tarifa"
                        onClick={() => remover(row)}
                      >
                        <Trash2 aria-hidden="true" className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                )}
              </li>
            )
          })}
        </ul>
      )}

      <div className="flex flex-wrap items-center justify-between gap-2 text-sm">
        <span className="text-muted-foreground">
          Soma do que está na tela:{' '}
          <span className="font-numeric tabular-nums text-foreground">{formatMoney(somaExibida)}</span>
        </span>
        {pendentes > 0 && (
          <span className="text-muted-foreground">
            {pendentes === 1
              ? '1 tarifa será removida ao salvar.'
              : `${pendentes} tarifas serão removidas ao salvar.`}{' '}
            Cancelar desfaz.
          </span>
        )}
      </div>
    </div>
  )
}
