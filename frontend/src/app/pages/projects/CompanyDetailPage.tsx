import { useQuery } from '@tanstack/react-query'
import { useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, Building2, Landmark } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { Card } from '@/components/ui/Card'
import { DetailList } from '@/components/ui/DetailList'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { carrierConnectionsApi, companiesApi } from '@/lib/api/projects'

/**
 * **Detalhe da empresa** (FE-058, FE-059).
 *
 * Duas decisões do mapa, e as duas são "não portar":
 *
 * - **DC-06 — a aba "Controles de Risco" NÃO é portada.** No legado ela era um
 *   parcial vazio: não estava listada nas abas, não tinha action e nunca
 *   renderizou nada. A informação que ela prometia aparece aqui no cartão de
 *   resumo, alimentada pelo MESMO número que o servidor usa para bloquear a
 *   exclusão. Portar uma aba vazia é portar a aparência da função.
 * - **DC-05 — os filtros `kind` e `state` não existem.** Os selects não estavam
 *   no HTML e o backend ignorava os dois parâmetros.
 *
 * ⏳ A contagem de limites fica em zero até a **S5** entregar `risk_controls` —
 * e ela vem do servidor, não é calculada aqui.
 */
export function CompanyDetailPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()

  const empresa = useQuery({
    queryKey: ['company', id],
    queryFn: () => companiesApi.get(id),
    enabled: Boolean(id),
  })

  const portadores = useQuery({
    queryKey: ['carrier-connections', 'list'],
    queryFn: () => carrierConnectionsApi.list({ perPage: 100 }),
  })

  return (
    <div className="pb-10">
      <Button variant="ghost" size="sm" className="mb-2" onClick={() => navigate('/companies')}>
        <ArrowLeft aria-hidden="true" className="h-4 w-4" />
        Empresas
      </Button>

      <AsyncSection
        loading={empresa.isLoading}
        error={empresa.isError ? empresa.error : undefined}
        data={empresa.data ? [empresa.data] : undefined}
        onRetry={() => empresa.refetch()}
        loadingLabel="Carregando empresa…"
        emptyTitle="Empresa não encontrada"
        emptyDescription="Ela pode ter sido removida, ou pertencer a outro projeto — o sistema responde igual nos dois casos, de propósito."
      >
        {([c]) => (
          <>
            <PageHeader
              title={c.title}
              subtitle="Contraparte tomadora deste projeto"
              rightSlot={
                c.has_safegold_management ? <Badge variant="info">Gerido pela Safegold</Badge> : undefined
              }
            />

            <div className="grid gap-4 lg:grid-cols-2">
              <Card className="p-4">
                <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold text-card-foreground">
                  <Building2 aria-hidden="true" className="h-4 w-4" />
                  Cadastro
                </h2>
                <DetailList
                  items={[
                    { label: 'Razão social', content: c.title },
                    {
                      label: 'Gestão',
                      // A marca é DERIVADA do projeto: `companies` não tem
                      // coluna própria, então não há como divergir (D-30/Q-02).
                      content: c.has_safegold_management ? 'Gerida pela Safegold' : 'Gestão própria',
                    },
                    { label: 'Cadastrada em', content: formatarDataHora(c.created_at) },
                    { label: 'Atualizada em', content: formatarDataHora(c.updated_at) },
                  ]}
                />
              </Card>

              <Card className="p-4">
                <h2 className="mb-3 text-sm font-semibold text-card-foreground">Resumo</h2>
                <DetailList
                  columns={2}
                  items={[
                    { label: 'Portadores do projeto', content: c.carriers_count, numeric: true },
                    { label: 'Limites de risco', content: c.risk_controls_count, numeric: true },
                  ]}
                />
                {c.risk_controls_count === 0 && (
                  <p className="mt-3 text-xs text-muted-foreground">
                    Ainda não há limite de risco lançado para esta empresa. Enquanto não houver, ela pode ser
                    removida — é o mesmo critério que o servidor aplica.
                  </p>
                )}
              </Card>

              <Card className="p-4 lg:col-span-2">
                <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold text-card-foreground">
                  <Landmark aria-hidden="true" className="h-4 w-4" />
                  Portadores disponíveis
                </h2>
                {/* Os portadores da empresa são DERIVADOS do projeto (DB-068):
                    a ponte é `project_to_carrier_connections`, e não existe
                    tabela empresa↔portador. */}
                <AsyncSection
                  loading={portadores.isLoading}
                  error={portadores.isError ? portadores.error : undefined}
                  data={portadores.data?.items}
                  onRetry={() => portadores.refetch()}
                  loadingLabel="Carregando portadores…"
                  emptyTitle="Nenhum portador conectado ao projeto"
                  emptyDescription="Os portadores da empresa vêm do projeto. Conecte o primeiro em «Portadores do projeto»."
                >
                  {(lista) => (
                    <ul className="flex flex-wrap gap-2">
                      {lista.map((p) => (
                        <li key={p.id}>
                          <Badge variant="outline">{p.carrier_title ?? '—'}</Badge>
                        </li>
                      ))}
                    </ul>
                  )}
                </AsyncSection>
              </Card>
            </div>
          </>
        )}
      </AsyncSection>
    </div>
  )
}

function formatarDataHora(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return `${d.toLocaleDateString('pt-BR')} às ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`
}
