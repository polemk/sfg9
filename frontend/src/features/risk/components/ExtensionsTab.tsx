import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { CalendarClock } from 'lucide-react'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Button } from '@/components/ui/Button'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { useMobile } from '@/hooks/useMobile'
import { usePagination } from '@/hooks/usePagination'
import { formatDate } from '@/lib/utils/date'
import { listRiskExtensions, type RiskOperation, type RiskOperationExtension } from '../api/risk'
import { CamposDoCartao } from './CamposDoCartao'
import { ExtensionDrawer } from './ExtensionDrawer'

/**
 * **A aba PRORROGAÇÕES** (FE-274, FE-276).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * `create_risk_operation_extensions` está entre as 24 migrations que nunca
 * subiram. Fonte:
 * `../sfg/app/views/pub/console/parts/risk_operations/detail/parts/risk_extensions/`.
 *
 * A lista é **somente leitura**: o registro é log imutável, sem editar nem
 * excluir — nem aqui nem no legado. E, como a aba de movimentos, ela ganha
 * **estado de erro** (FE-276), que o legado não tinha em nenhuma das duas.
 */
export function ExtensionsTab({ operacao }: { operacao: RiskOperation }) {
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const paginacao = usePagination({ initialPerPage: 20 })
  const [drawerAberto, setDrawerAberto] = useState(false)

  const consulta = useQuery({
    queryKey: ['risk-extensions', operacao.id, paginacao.page, paginacao.perPage],
    queryFn: () => listRiskExtensions(operacao.id, { page: paginacao.page, perPage: paginacao.perPage }),
  })

  const invalidar = () => {
    queryClient.invalidateQueries({ queryKey: ['risk-extensions', operacao.id] })
    queryClient.invalidateQueries({ queryKey: ['risk-operation', operacao.id] })
    queryClient.invalidateQueries({ queryKey: ['risk-movements', operacao.id] })
    queryClient.invalidateQueries({ queryKey: ['risk-operations'] })
  }

  const itens = consulta.data?.items ?? []
  const meta = consulta.data?.meta

  const colunas: Column<RiskOperationExtension>[] = [
    { key: 'created_at', header: 'Prorrogado em', align: 'center',
      cell: (e) => formatDate(e.created_at) },
    { key: 'original_due_date', header: 'Data original', align: 'center',
      cell: (e) => formatDate(e.original_due_date) },
    { key: 'new_due_date', header: 'Nova data', align: 'center',
      cell: (e) => formatDate(e.new_due_date) },
    { key: 'user', header: 'Por', cell: (e) => e.user_name ?? '—' },
    { key: 'observation', header: 'Observação', cell: (e) => e.observation || '—' },
  ]

  return (
    <div className="space-y-4">
      <div className="flex justify-end">
        <Button onClick={() => setDrawerAberto(true)}>
          <CalendarClock className="mr-2 h-4 w-4" />
          Prorrogar
        </Button>
      </div>

      {estreito ? (
        <AsyncSection
          loading={consulta.isPending}
          error={consulta.error}
          data={itens}
          onRetry={() => consulta.refetch()}
          emptyTitle="Nenhuma prorrogação"
          emptyDescription="O vencimento desta operação nunca foi esticado."
        >
          {(lista) => (
            <div className="space-y-3">
              {lista.map((e) => (
                <MobileCard
                  key={e.id}
                  title={`${formatDate(e.original_due_date)} → ${formatDate(e.new_due_date)}`}
                  subtitle={`Prorrogado em ${formatDate(e.created_at)}`}
                >
                  <CamposDoCartao
                    itens={[
                      ['Por', e.user_name ?? '—'],
                      ...(e.observation ? ([['Observação', e.observation]] as Array<[string, string]>) : []),
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
          data={itens}
          rowKey={(e) => e.id}
          loading={consulta.isPending}
          error={consulta.error}
          onRetry={() => consulta.refetch()}
          caption="Prorrogações da operação"
          emptyTitle="Nenhuma prorrogação"
          emptyDescription="O vencimento desta operação nunca foi esticado."
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

      {drawerAberto && (
        <ExtensionDrawer
          operacao={operacao}
          onClose={() => setDrawerAberto(false)}
          onExtended={invalidar}
        />
      )}
    </div>
  )
}
