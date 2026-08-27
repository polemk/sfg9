import { useEffect } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, Radio } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { ErrorState, LoadingState } from '@/components/ui/States'
import { RegistrationCard } from '@/components/renegotiations/RegistrationCard'
import { SummaryCards } from '@/components/renegotiations/SummaryCards'
import { FilesSection } from '@/components/renegotiations/FilesSection'
import { InstallmentsTab } from '@/components/renegotiations/InstallmentsTab'
import { useRenegotiationChannel } from '@/hooks/useRenegotiationChannel'
import { useIsReadonly } from '@/hooks/usePermission'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { renegotiationsApi } from '@/lib/api/renegotiations'
import { localizePercentLabel } from '@/lib/utils/number'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'

/**
 * **Detalhe da renegociação** — abas GERAL e PREVISÕES (FE-204..FE-212).
 *
 * ## Deep-link e histórico REAIS (FE-204, corrige D-92)
 *
 * A aba ativa vive na **URL** (`?tab=previsoes`), não em memória JavaScript. No
 * legado o estado de navegação era só uma variável no cliente: recarregar a
 * página voltava para a primeira aba, o endereço da aba não podia ser
 * compartilhado, e o **Voltar do navegador saía do console inteiro** em vez de
 * voltar uma aba.
 *
 * ## Sem polling (Princípio 10)
 *
 * `useRenegotiationChannel` assina o canal da renegociação e invalida as
 * consultas quando qualquer parcela ou pagamento muda. **Nenhum temporizador
 * consulta a API nesta área** — `src/__tests__/no-api-polling.test.ts` varre estes
 * arquivos, e o canal do backend tem o teste espelho (`renegotiation_channel_spec`).
 *
 * ## Não existe aba PAGAMENTOS, e é escolha (DEC-53)
 *
 * O backend do pagamento é completo; a aba está comentada no legado e **não é
 * portada**. Os pagamentos aparecem como sublinha da previsão, que é como o
 * legado realmente os expunha. O QA do Phase 4 não deve abrir defeito por isso.
 */
const ABAS = ['geral', 'previsoes'] as const
type Aba = (typeof ABAS)[number]

export function RenegotiationDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [searchParams, setSearchParams] = useSearchParams()
  const readonly = useIsReadonly()

  const abaDaUrl = searchParams.get('tab') as Aba | null
  const aba: Aba = abaDaUrl && ABAS.includes(abaDaUrl) ? abaDaUrl : 'geral'

  // Endereço inválido é normalizado uma vez, sem empilhar no histórico.
  useEffect(() => {
    if (abaDaUrl && !ABAS.includes(abaDaUrl)) {
      setSearchParams({ tab: 'geral' }, { replace: true })
    }
  }, [abaDaUrl, setSearchParams])

  const canal = useRenegotiationChannel(id)

  const registro = useQuery({
    queryKey: ['renegotiation', id],
    queryFn: () => renegotiationsApi.get(id!),
    enabled: !!id,
  })

  const valores = useQuery({
    queryKey: ['renegotiation-general-values', id],
    queryFn: () => renegotiationsApi.generalValues(id!),
    enabled: !!id,
  })

  const opcoes = useQuery({
    queryKey: ['renegotiation-options'],
    queryFn: () => renegotiationsApi.options(),
    staleTime: 30 * 60 * 1000,
  })

  if (!id) return null
  if (registro.isLoading) return <LoadingState label="Carregando a renegociação…" />

  const escopo = projectScopeCode(registro.error)
  if (escopo) return <ProjectScopeState code={escopo} recurso="as renegociações" />

  if (registro.error) {
    return (
      <ErrorState
        title="Não foi possível carregar a renegociação"
        description={mensagemDoServidor(registro.error, 'Tente novamente.')}
        onRetry={() => registro.refetch()}
      />
    )
  }

  const r = registro.data!
  const podeEscrever = !readonly

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={r.title}
        subtitle={`${r.provider_name} · ${r.kind}${r.company_title ? ` · ${r.company_title}` : ''}`}
        loading={registro.isFetching}
        breadcrumb={
          <Button variant="ghost" size="sm" onClick={() => navigate('/renegotiations')}>
            <ArrowLeft className="mr-2 h-4 w-4" aria-hidden />
            Renegociações
          </Button>
        }
        rightSlot={
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant={r.state === 'Liquidado' ? 'success' : r.state === 'Inconsistente' ? 'warning' : 'secondary'}>
              {/* `"66.87% Pago"` chega do servidor com PONTO decimal. Só o
                  separador muda: os dígitos são do domínio (DEC-01). */}
              {localizePercentLabel(r.beauty_state, r.state)}
            </Badge>
            {canal.connected && (
              <span className="hidden items-center gap-1.5 text-xs text-muted-foreground sm:flex">
                <Radio className="h-3.5 w-3.5 text-success" aria-hidden />
                Ao vivo
              </span>
            )}
            {podeEscrever && (
              <Button variant="secondary" size="sm" onClick={() => navigate(`/renegotiations/${id}/edit`)}>
                Editar cadastro
              </Button>
            )}
          </div>
        }
      />

      <SummaryCards
        renegotiation={r}
        generalValues={valores.data}
        connected={canal.connected}
        loading={registro.isFetching && !registro.data}
      />

      <Tabs
        value={aba}
        // A aba entra no HISTÓRICO: o Voltar do navegador volta uma aba, e o
        // endereço da aba pode ser compartilhado (FE-204 / D-92).
        onValueChange={(valor) => setSearchParams({ tab: valor })}
      >
        <TabsList>
          <TabsTrigger value="geral">Geral</TabsTrigger>
          <TabsTrigger value="previsoes">
            Previsões
            {r.installments_count > 0 && (
              <span className="ml-2 font-numeric text-xs tabular-nums text-muted-foreground">
                {r.paid_installments}/{r.installments_count}
              </span>
            )}
          </TabsTrigger>
        </TabsList>

        <TabsContent value="geral" className="mt-4 flex flex-col gap-4">
          <RegistrationCard
            renegotiation={r}
            podeEditar={podeEscrever}
            onEdit={() => navigate(`/renegotiations/${id}/edit`)}
          />
          <FilesSection renegotiationId={id} podeEscrever={podeEscrever} />
        </TabsContent>

        <TabsContent value="previsoes" className="mt-4">
          <InstallmentsTab
            renegotiationId={id}
            podeEscrever={podeEscrever}
            delayTypes={opcoes.data?.delay_types ?? []}
          />
        </TabsContent>
      </Tabs>
    </div>
  )
}
