import { Pencil } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { formatarReais } from '@/lib/api/projects'
import { formatDate } from '@/lib/utils/date'
import type { Renegotiation } from '@/lib/api/renegotiations'

/**
 * **O cadastro da renegociação, somente leitura** (FE-205).
 *
 * Os 13 campos que o formulário grava, exibidos. **Campo vazio mostra `—`** — e
 * isso vale inclusive para o que é legitimamente zero: `R$ 0,00` e "não informado"
 * são coisas diferentes, e a tela não pode confundi-las.
 *
 * **`Taxa Juro Correção` e `Carência` não aparecem** aqui pelo mesmo motivo pelo
 * qual não aparecem no formulário: os dois existem na tabela e **nenhum cálculo
 * os lê** (D-47, Q-B24). Mostrá-los como se fossem parâmetros do acordo é
 * prometer um efeito que não existe.
 */
export interface RegistrationCardProps {
  renegotiation: Renegotiation
  onEdit?: () => void
  podeEditar?: boolean
}

export function RegistrationCard({ renegotiation: r, onEdit, podeEditar }: RegistrationCardProps) {
  const campos: Array<{ rotulo: string; valor: React.ReactNode; numerico?: boolean }> = [
    { rotulo: 'Nome', valor: r.title },
    { rotulo: 'Fornecedor', valor: r.provider_name },
    { rotulo: 'Empresa', valor: r.company_title },
    { rotulo: 'Tipo', valor: r.kind },
    { rotulo: 'Data da negociação', valor: formatDate(r.renegotiation_date), numerico: true },
    { rotulo: 'Origem', valor: r.origin },
    { rotulo: 'Correção monetária', valor: r.monetary_correction },
    { rotulo: 'Valor original vencido', valor: formatarReais(r.original_value), numerico: true },
    { rotulo: 'Valor original a vencer', valor: formatarReais(r.original_pending_value), numerico: true },
    { rotulo: 'Despesas adicionais', valor: formatarReais(r.additional_value), numerico: true },
    { rotulo: 'Valor total da dívida', valor: formatarReais(r.total_debt), numerico: true },
    { rotulo: 'Deságio', valor: formatarReais(r.desagio_value), numerico: true },
    { rotulo: 'Após deságio', valor: formatarReais(r.total_value_with_desagio), numerico: true },
    {
      rotulo: 'Taxa de juros acordada',
      valor: `${(r.operation_interest_rate ?? 0).toLocaleString('pt-BR', { minimumFractionDigits: 2 })}%`,
      numerico: true,
    },
    { rotulo: 'Primeiro vencimento', valor: formatDate(r.first_due_date), numerico: true },
    { rotulo: 'Último vencimento', valor: formatDate(r.last_due_date), numerico: true },
    { rotulo: 'Chave de integração', valor: r.integration_key },
  ]

  return (
    <section className="rounded-lg border border-border bg-card p-4 sm:p-6">
      <header className="mb-4 flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <h2 className="text-sm font-semibold uppercase tracking-[0.08em] text-muted-foreground">Cadastro</h2>
          {r.has_safegold_management && (
            <Badge variant="secondary" title="Carimbo copiado do projeto na criação.">
              Gestão Safegold
            </Badge>
          )}
        </div>
        {podeEditar && onEdit && (
          <Button variant="secondary" size="sm" onClick={onEdit}>
            <Pencil className="mr-2 h-4 w-4" aria-hidden />
            Editar
          </Button>
        )}
      </header>

      <dl className="grid gap-x-6 gap-y-4 sm:grid-cols-2 lg:grid-cols-3">
        {campos.map((campo) => (
          <div key={campo.rotulo} className="min-w-0">
            <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">{campo.rotulo}</dt>
            <dd
              className={`truncate text-sm text-foreground ${campo.numerico ? 'font-numeric tabular-nums' : ''}`}
              title={typeof campo.valor === 'string' ? campo.valor : undefined}
            >
              {/* Vazio mostra `—`, sempre. */}
              {campo.valor === null || campo.valor === undefined || campo.valor === '' ? '—' : campo.valor}
            </dd>
          </div>
        ))}
      </dl>

      {r.observation && (
        <div className="mt-4 border-t border-border pt-4">
          <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">Observações</dt>
          <dd className="mt-1 whitespace-pre-wrap text-sm text-foreground">{r.observation}</dd>
        </div>
      )}
    </section>
  )
}
