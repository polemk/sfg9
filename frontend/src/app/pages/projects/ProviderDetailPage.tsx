import { useQuery } from '@tanstack/react-query'
import { useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, Truck } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { Card } from '@/components/ui/Card'
import { DetailList } from '@/components/ui/DetailList'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { UserAvatar } from '@/components/ui/UserAvatar'
import { providersApi, type Provider } from '@/lib/api/projects'

/**
 * **Detalhe do fornecedor** (BE-065 / **D-22**).
 *
 * Esta tela **não existia no legado**: clicar na linha não levava a lugar
 * nenhum, porque a view de detalhe nunca foi escrita — a rota existia, o
 * controller tinha a action, e o `render` apontava para um template ausente.
 *
 * O que ela mostra e o legado não mostrava em lugar nenhum: **quando o cadastro
 * veio da Receita Federal**. Sem essa data não há como saber se a razão social
 * na tela é de ontem ou de 2021, e é ela que decide se vale reconsultar.
 */
export function ProviderDetailPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()

  const fornecedor = useQuery({
    queryKey: ['provider', id],
    queryFn: () => providersApi.get(id),
    enabled: Boolean(id),
  })

  return (
    <div className="pb-10">
      <Button variant="ghost" size="sm" className="mb-2" onClick={() => navigate('/providers')}>
        <ArrowLeft aria-hidden="true" className="h-4 w-4" />
        Fornecedores
      </Button>

      <AsyncSection
        loading={fornecedor.isLoading}
        error={fornecedor.isError ? fornecedor.error : undefined}
        data={fornecedor.data ? [fornecedor.data] : undefined}
        onRetry={() => fornecedor.refetch()}
        loadingLabel="Carregando fornecedor…"
        emptyTitle="Fornecedor não encontrado"
        emptyDescription="Ele pode ter sido removido, ou pertencer a outro projeto — o sistema responde igual nos dois casos, de propósito."
      >
        {([p]) => (
          <>
            <PageHeader
              title={p.title}
              subtitle={p.formatted_document}
              rightSlot={
                <div className="flex items-center gap-2">
                  <UserAvatar name={p.title} src={p.logo_url ?? undefined} size={32} />
                  {p.is_active ? <Badge variant="success">Ativo</Badge> : <Badge variant="secondary">Inativo</Badge>}
                </div>
              }
            />

            <div className="grid gap-4 lg:grid-cols-2">
              <Card className="p-4">
                <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold text-card-foreground">
                  <Truck aria-hidden="true" className="h-4 w-4" />
                  Cadastro
                </h2>
                <DetailList
                  items={[
                    { label: 'Nome', content: p.title },
                    { label: 'Chave de integração', content: p.integration_key },
                    { label: 'Tipo de documento', content: p.document_type ?? '—' },
                    { label: 'Documento', content: p.formatted_document, numeric: true },
                    { label: 'Descrição', content: p.resume || '—', full: true },
                    { label: 'Renegociações', content: p.renegotiations_count, numeric: true },
                  ]}
                />
              </Card>

              <Card className="p-4">
                <h2 className="mb-3 text-sm font-semibold text-card-foreground">Cadastro federal</h2>
                {p.cnpj_fetched_at ? (
                  <>
                    <DetailList
                      items={[
                        { label: 'Razão social', content: p.legal_name || '—' },
                        { label: 'Nome fantasia', content: p.trade_name || '—' },
                        { label: 'Situação', content: p.status || '—' },
                        { label: 'Abertura', content: formatarData(p.opened_at) },
                        { label: 'Situação em', content: formatarData(p.status_changed_at) },
                        { label: 'E-mail', content: p.email || '—' },
                        { label: 'Telefone', content: p.phone || '—' },
                        { label: 'Endereço', content: enderecoDe(p), full: true },
                      ]}
                    />
                    <p className="mt-3 text-xs text-muted-foreground">
                      Consultado em {formatarDataHora(p.cnpj_fetched_at)}. Reconsulte pelo formulário se o
                      cadastro puder ter mudado.
                    </p>
                  </>
                ) : (
                  <p className="text-sm text-muted-foreground">
                    Este fornecedor foi cadastrado à mão. Informe um CNPJ no formulário para preencher os dados
                    pela Receita Federal.
                  </p>
                )}
              </Card>
            </div>
          </>
        )}
      </AsyncSection>
    </div>
  )
}

function enderecoDe(p: Provider): string {
  const linha1 = [p.street, p.number].filter(Boolean).join(', ')
  const linha2 = [p.district, p.city, p.state].filter(Boolean).join(' · ')
  const cep = p.zip_code ? `CEP ${p.zip_code}` : ''
  return [linha1, p.complement, linha2, cep].filter(Boolean).join(' — ') || '—'
}

function formatarData(iso: string | null): string {
  if (!iso) return '—'
  const d = new Date(`${iso}T00:00:00`)
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString('pt-BR')
}

function formatarDataHora(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return `${d.toLocaleDateString('pt-BR')} às ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`
}
