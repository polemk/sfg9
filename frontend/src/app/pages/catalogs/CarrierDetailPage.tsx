import { useQuery } from '@tanstack/react-query'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, Landmark } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { DetailList } from '@/components/ui/DetailList'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { formatMoney, formatPercent, formatAmount } from '@/lib/utils/number'
import { formatDateTime } from '@/lib/utils/date'
import { carriersApi, type Carrier } from '@/lib/api/catalogs'

/**
 * **Detalhe do portador** (FE-068 / DC-08 / D-22).
 *
 * Esta tela existia no legado — HTML e SCSS completos, em
 * `pub/console/parts/carriers/detail/` — e **nenhuma rota chegava nela**. A
 * action `show` respondia só a `format.js`, e não havia link em lugar nenhum
 * para abri-la. Era trabalho pronto e inalcançável; portá-la é barato e é o que
 * o DC-08 decidiu.
 *
 * O que ela mostra é a leitura do que a listagem resume: identificação,
 * estrutura de cotas e as relações (que é onde a S4 e a S5 vão pendurar as
 * conexões de projeto e os limites de risco).
 */
export function CarrierDetailPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()

  const consulta = useQuery({
    queryKey: ['carrier', id],
    queryFn: () => carriersApi.get(id),
    enabled: id.length > 0,
  })

  return (
    <div className="pb-10">
      <PageHeader
        title={consulta.data?.title ?? 'Portador'}
        subtitle="Contraparte financiadora"
        breadcrumb={
          <Link to="/carriers" className="inline-flex items-center gap-1 hover:text-foreground">
            <ArrowLeft aria-hidden="true" className="h-3 w-3" />
            Portadores
          </Link>
        }
        rightSlot={
          <Button variant="secondary" onClick={() => navigate('/carriers')}>
            Voltar à lista
          </Button>
        }
      />

      <AsyncSection
        loading={consulta.isLoading}
        error={consulta.isError ? consulta.error : undefined}
        data={consulta.data}
        onRetry={() => consulta.refetch()}
        emptyTitle="Portador não encontrado"
        emptyDescription="O registro pode ter sido excluído."
        loadingLabel="Carregando portador…"
      >
        {(carrier: Carrier) => (
          <Tabs defaultValue="identificacao">
            <TabsList>
              <TabsTrigger value="identificacao">Identificação</TabsTrigger>
              <TabsTrigger value="cotas">Estrutura de cotas</TabsTrigger>
              <TabsTrigger value="relacoes">Relações</TabsTrigger>
            </TabsList>

            <TabsContent value="identificacao">
              <div className="grid gap-4 lg:grid-cols-3">
                <Card className="lg:col-span-1">
                  <CardContent className="flex flex-col items-center gap-3 pt-6">
                    {carrier.logo_url ? (
                      <img
                        src={carrier.logo_url}
                        alt={`Logo de ${carrier.title}`}
                        className="h-28 w-28 rounded-lg object-contain"
                      />
                    ) : (
                      <div className="flex h-28 w-28 items-center justify-center rounded-lg bg-muted">
                        <Landmark aria-hidden="true" className="h-10 w-10 text-muted-foreground" />
                      </div>
                    )}
                    <p className="text-center font-title text-base font-semibold text-foreground">
                      {carrier.title}
                    </p>
                    <div className="flex flex-wrap justify-center gap-2">
                      {carrier.financial_agent && <Badge variant="secondary">{carrier.financial_agent}</Badge>}
                      <Badge variant={carrier.is_active ? 'success' : 'secondary'}>
                        {carrier.is_active ? 'Ativo' : 'Inativo'}
                      </Badge>
                    </div>
                  </CardContent>
                </Card>

                <Card className="lg:col-span-2">
                  <CardHeader>
                    <CardTitle>Cadastro</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <DetailList
                      items={[
                        { label: 'Grupo', content: carrier.group_title ?? '-' },
                        { label: 'Agente financeiro', content: carrier.financial_agent ?? '-' },
                        {
                          label: 'Código COMPE',
                          content: (
                            <span className="font-numeric tabular-nums">{carrier.bank_code ?? '-'}</span>
                          ),
                        },
                        { label: 'Cidade', content: carrier.city_label },
                        {
                          label: 'Chave de integração',
                          content: <code className="font-numeric text-xs">{carrier.integration_key}</code>,
                        },
                        { label: 'Descrição', content: carrier.resume || '-', full: true },
                        { label: 'Cadastrado em', content: formatDateTime(carrier.created_at) },
                        { label: 'Última alteração', content: formatDateTime(carrier.updated_at) },
                      ]}
                    />
                  </CardContent>
                </Card>
              </div>
            </TabsContent>

            <TabsContent value="cotas">
              <Card>
                <CardHeader>
                  <CardTitle>Estrutura de cotas</CardTitle>
                </CardHeader>
                <CardContent>
                  <DetailList
                    items={[
                      {
                        label: 'Patrimônio líquido',
                        content: (
                          <span className="font-numeric tabular-nums">
                            {formatMoney(Number(carrier.net_worth ?? 0))}
                          </span>
                        ),
                      },
                      {
                        label: 'Cotas sênior',
                        content: (
                          <span className="font-numeric tabular-nums">
                            {formatAmount(carrier.senior_accounts, 0)}
                          </span>
                        ),
                      },
                      {
                        label: 'Cotas subordinadas',
                        content: (
                          <span className="font-numeric tabular-nums">
                            {formatAmount(carrier.subordinated_accounts, 0)}
                          </span>
                        ),
                      },
                      {
                        // DC-09 — número do SERVIDOR, pela fórmula do legado
                        // (DEC-30): subordinadas ÷ sênior × 100, e 0 quando não
                        // há cota sênior.
                        label: '% de cotas subordinadas',
                        content: (
                          <span className="font-numeric tabular-nums">
                            {formatPercent(Number(carrier.subordinated_accounts_percent ?? 0))}
                          </span>
                        ),
                      },
                    ]}
                  />
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="relacoes">
              <Card>
                <CardHeader>
                  <CardTitle>Relações</CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  <DetailList
                    items={[
                      {
                        label: 'Projetos conectados',
                        content: (
                          <span className="font-numeric tabular-nums">{carrier.projects_count}</span>
                        ),
                      },
                    ]}
                  />
                  <p className="text-sm text-muted-foreground">
                    Limites de risco e recebíveis desta contraparte aparecem aqui quando as áreas de risco e
                    de recebíveis entrarem no ar. Enquanto houver qualquer vínculo, o portador não pode ser
                    excluído — o servidor recusa e nada é apagado.
                  </p>
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        )}
      </AsyncSection>
    </div>
  )
}
