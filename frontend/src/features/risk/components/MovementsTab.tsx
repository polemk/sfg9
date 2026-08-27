import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeftRight, MoreVertical, Pencil, Plus, Trash2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { MobileRowActions } from '@/components/mobile/MobileRowActions'
import { useMobile } from '@/hooks/useMobile'
import { usePagination } from '@/hooks/usePagination'
import { cn } from '@/lib/utils'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { formatDate } from '@/lib/utils/date'
import { formatMoney } from '@/lib/utils/number'
import { listRiskMovements, riskOperationsApi, type RiskMovement, type RiskOperation } from '../api/risk'
import { CamposDoCartao } from './CamposDoCartao'
import { MovementDrawer } from './MovementDrawer'

/**
 * **O extrato da operação** (FE-269, FE-270, FE-273, FE-276).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * `create_risk_movements` está entre as 24 migrations que nunca subiram
 * (`analise-dump-producao.md` §1). Fonte:
 * `../sfg/app/views/pub/console/parts/risk_operations/detail/parts/risk_movements/`.
 *
 * ## O que muda
 *
 * - **A lista é paginada e escopada.** No legado `l`/`o`/`q` eram lidos, tinham
 *   default e **nunca eram usados**; e qualquer `risk_operation_id` era aceito
 *   sem olhar o projeto (a segunda IDOR desta fatia).
 * - **Existe estado de ERRO.** No legado não há estado de erro em nenhuma das
 *   duas listas do detalhe (FE-276): falha de rede parecia lista vazia, e quem
 *   decide sobre carteira olhando "nada aqui" quando a verdade é "não consegui
 *   perguntar" decide errado. O `AsyncSection` cobre os quatro estados.
 * - **O título da confirmação fala de movimento.** No legado dizia "Excluir
 *   previsão", rótulo do módulo de renegociação.
 *
 * ## O que é REPLICADO de propósito
 *
 * **O sufixo `C`/`D` colado no valor** (`R$ 1.234,56C`). É como o operador lê o
 * extrato hoje, e o `credit_type` que o produz vem do servidor. A cor usa o par
 * único de tokens semânticos (D-101), não as duas paletas concorrentes do
 * legado.
 *
 * **Nenhum número é calculado aqui** (contrato C2): `balance` já é a saída de
 * `Risk::Calculator#recalculate_chain`.
 */
export function MovementsTab({ operacao }: { operacao: RiskOperation }) {
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const paginacao = usePagination({ initialPerPage: 20 })

  const [drawer, setDrawer] = useState<{ mode: 'new' | 'transfer'; movimento?: RiskMovement } | null>(null)
  const [confirmando, setConfirmando] = useState<RiskMovement | null>(null)
  const [acoesDe, setAcoesDe] = useState<string | null>(null)

  const consulta = useQuery({
    queryKey: ['risk-movements', operacao.id, paginacao.page, paginacao.perPage],
    queryFn: () => listRiskMovements(operacao.id, { page: paginacao.page, perPage: paginacao.perPage }),
  })

  const invalidar = () => {
    queryClient.invalidateQueries({ queryKey: ['risk-movements', operacao.id] })
    // O cartão de última movimentação e o cabeçalho leem o mesmo saldo.
    queryClient.invalidateQueries({ queryKey: ['risk-operation', operacao.id] })
    queryClient.invalidateQueries({ queryKey: ['risk-last-movement', operacao.id] })
    queryClient.invalidateQueries({ queryKey: ['risk-operations'] })
    queryClient.invalidateQueries({ queryKey: ['risk-summary'] })
  }

  const excluir = useMutation({
    mutationFn: (m: RiskMovement) => riskOperationsApi.removeMovement(operacao.id, m.id),
    onSuccess: () => {
      notify.success('Movimento removido.')
      setConfirmando(null)
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível remover o movimento.')),
  })

  const movimentos = consulta.data?.items ?? []
  const meta = consulta.data?.meta

  /** `R$ 1.234,56C` / `…D` — sufixo REPLICADO, cor pelos tokens (D-101). */
  const valorComSufixo = (m: RiskMovement) => {
    const credito = m.credit_type === 'C'
    return (
      <span className={cn('font-numeric', credito ? 'text-success' : 'text-negative')}>
        {formatMoney(Number(m.movement_value))}
        {m.credit_type ?? ''}
      </span>
    )
  }

  const colunas: Column<RiskMovement>[] = [
    { key: 'sequence', header: '#', width: '3.5rem', align: 'center',
      cell: (m) => <span className="font-numeric">{m.sequence ?? '—'}</span> },
    { key: 'date', header: 'Data', align: 'center', cell: (m) => formatDate(m.date) },
    { key: 'type', header: 'Tipo', cell: (m) => m.movement_type_title ?? '—' },
    { key: 'value', header: 'Valor movimento', align: 'right', cell: valorComSufixo },
    {
      key: 'balance',
      header: 'Saldo',
      align: 'right',
      cell: (m) => (
        <span className={cn('font-numeric', Number(m.balance) < 0 ? 'text-negative' : 'text-success')}>
          {formatMoney(Number(m.balance))}
        </span>
      ),
    },
    { key: 'observation', header: 'Observação', cell: (m) => m.observation || '—' },
    {
      key: 'acoes',
      header: '',
      width: '6rem',
      align: 'right',
      cell: (m) => (
        <div className="flex justify-end gap-1">
          <Button variant="ghost" size="icon" aria-label="Editar movimento"
                  onClick={() => setDrawer({ mode: m.is_transfer ? 'transfer' : 'new', movimento: m })}>
            <Pencil className="h-4 w-4" />
          </Button>
          <Button variant="ghost" size="icon" aria-label="Remover movimento"
                  onClick={() => setConfirmando(m)}>
            <Trash2 className="h-4 w-4" />
          </Button>
        </div>
      ),
    },
  ]

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap justify-end gap-2">
        <Button onClick={() => setDrawer({ mode: 'new' })}>
          <Plus className="mr-2 h-4 w-4" />
          Novo movimento
        </Button>
        {/* FE-272 — "Transferir" só existe em operação de subtipo
            pré-faturamento: é de lá que a contrapartida sai. */}
        {operacao.is_pre && (
          <Button variant="secondary" onClick={() => setDrawer({ mode: 'transfer' })}>
            <ArrowLeftRight className="mr-2 h-4 w-4" />
            Transferir
          </Button>
        )}
      </div>

      {estreito ? (
        <AsyncSection
          loading={consulta.isPending}
          error={consulta.error}
          data={movimentos}
          onRetry={() => consulta.refetch()}
          emptyTitle="Nenhum movimento"
          emptyDescription="Esta operação ainda não tem lançamento."
        >
          {(itens) => (
            <div className="space-y-3">
              {itens.map((m) => (
                <MobileCard
                  key={m.id}
                  title={`${m.sequence ?? '—'} · ${m.movement_type_title ?? 'Movimento'}`}
                  subtitle={formatDate(m.date)}
                  headerAction={
                    <Button variant="ghost" size="icon" aria-label="Ações do movimento"
                            onClick={() => setAcoesDe(m.id)}>
                      <MoreVertical className="h-4 w-4" />
                    </Button>
                  }
                >
                  <CamposDoCartao
                    itens={[
                      ['Valor', `${formatMoney(Number(m.movement_value))}${m.credit_type ?? ''}`],
                      ['Saldo', formatMoney(Number(m.balance))],
                      ...(m.observation ? ([['Observação', m.observation]] as Array<[string, string]>) : []),
                    ]}
                  />
                </MobileCard>
              ))}
            </div>
          )}
        </AsyncSection>
      ) : (
        <DataTable
          columns={colunas}
          data={movimentos}
          rowKey={(m) => m.id}
          loading={consulta.isPending}
          error={consulta.error}
          onRetry={() => consulta.refetch()}
          caption="Movimentos da operação"
          emptyTitle="Nenhum movimento"
          emptyDescription="Esta operação ainda não tem lançamento."
        />
      )}

      {meta && meta.total > 0 &&
        (estreito ? (
          <MobilePagination page={meta.page} perPage={meta.perPage} total={meta.total}
                            onPageChange={paginacao.setPage} loading={consulta.isFetching} />
        ) : (
          <PaginationPill page={meta.page} totalPages={meta.totalPages} perPage={meta.perPage}
                          onPageChange={paginacao.setPage} onPerPageChange={paginacao.setPerPage}
                          loading={consulta.isFetching} />
        ))}

      {acoesDe && (() => {
        const alvo = movimentos.find((m) => m.id === acoesDe)
        if (!alvo) return null
        return (
          <MobileRowActions
            open
            onOpenChange={(aberto) => !aberto && setAcoesDe(null)}
            title={alvo.movement_type_title ?? 'Movimento'}
            actions={[
              { key: 'editar', label: 'Editar', icon: <Pencil className="h-4 w-4" />,
                onSelect: () => setDrawer({ mode: alvo.is_transfer ? 'transfer' : 'new', movimento: alvo }) },
              { key: 'remover', label: 'Remover', icon: <Trash2 className="h-4 w-4" />, destructive: true,
                onSelect: () => setConfirmando(alvo) },
            ]}
          />
        )
      })()}

      {drawer && (
        <MovementDrawer
          operacao={operacao}
          movimento={drawer.movimento}
          mode={drawer.mode}
          onClose={() => setDrawer(null)}
          onSaved={invalidar}
        />
      )}

      <ConfirmDialog
        open={!!confirmando}
        onOpenChange={(aberto) => !aberto && setConfirmando(null)}
        title="Excluir movimento"
        description={
          confirmando?.is_transfer
            ? 'Este é um movimento de transferência: a contrapartida na operação par será removida junto, e os saldos das duas serão recalculados.'
            : 'O saldo dos movimentos seguintes será recalculado.'
        }
        confirmLabel="Excluir"
        loading={excluir.isPending}
        onConfirm={() => confirmando && excluir.mutate(confirmando)}
      />
    </div>
  )
}
