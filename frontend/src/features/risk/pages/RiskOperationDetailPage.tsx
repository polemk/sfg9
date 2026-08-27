import { useEffect, useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, CalendarClock, Pencil, RefreshCw } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { ErrorState, LoadingState } from '@/components/ui/States'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { mensagemDeErro } from '@/components/ui/AsyncSection'
import { riskOperationsApi, type RiskOperation } from '../api/risk'
import { OperationGeneralTab } from '../components/OperationGeneralTab'
import { MovementsTab } from '../components/MovementsTab'
import { ExtensionsTab } from '../components/ExtensionsTab'
import { RiskOperationDrawer } from '../components/RiskOperationDrawer'
import { RenewalDrawer } from '../components/RenewalDrawer'
import { ExtensionDrawer } from '../components/ExtensionDrawer'

/**
 * **Detalhe da operação de risco** (FE-264).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * As seis migrations desta família estão entre as 24 que nunca subiram
 * (`analise-dump-producao.md` §1). Fonte:
 * `../sfg/app/views/pub/console/parts/risk_operations/detail/`.
 *
 * ## D-92 — a aba vira endereço de verdade
 *
 * O legado trocava de aba com `history.replaceState`, sem rota: recarregar caía
 * na primeira aba, e não havia link para "as movimentações desta operação". Aqui
 * a aba é `?aba=`, com `replace` na navegação para não empilhar histórico a cada
 * clique.
 *
 * ## A aba PRORROGAÇÕES só existe para tipo SEM pré-faturamento
 *
 * O par estático não tem janela de datas (B-08): não há vencimento a esticar.
 * Mostrar a aba vazia seria oferecer uma ação impossível.
 *
 * ## O 500 que não acontece mais
 *
 * Abrir o detalhe de uma operação **sem movimento** derrubava a tela no legado
 * (`@last_movement.date` em `nil`) — e o par estático nasce exatamente assim.
 * Ver `LastMovementCard` e `BE-255`.
 */
const ABAS = ['geral', 'movimentacoes', 'prorrogacoes'] as const
type Aba = (typeof ABAS)[number]

export function RiskOperationDetailPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [params, setParams] = useSearchParams()
  const papel = useRoleSlug()
  // **`user_is_readonly` é modificador de USUÁRIO, não de papel** (DEC-108), e
  // esta tela não o consultava: a conta somente-leitura da apresentação via os
  // botões de escrita e o servidor os recusava com 403. Medido renderizando
  // `/receivables` com Tereza — o "Novo borderô" estava lá.
  const somenteLeitura = useIsReadonly()
  const podeEscrever = papel !== null && ALL_ROLES.includes(papel) && !somenteLeitura

  const [editando, setEditando] = useState(false)
  const [renovando, setRenovando] = useState(false)
  const [prorrogando, setProrrogando] = useState(false)

  const consulta = useQuery({
    queryKey: ['risk-operation', id],
    queryFn: () => riskOperationsApi.get(id),
    enabled: !!id,
  })

  const operacao = consulta.data as RiskOperation | undefined

  useEffect(() => {
    document.title = operacao ? `Safegold - ${operacao.title}` : 'Safegold - Operação de Risco'
  }, [operacao])

  const abaAtual = (ABAS.includes(params.get('aba') as Aba) ? params.get('aba') : 'geral') as Aba

  const trocarAba = (aba: string) => {
    const proximo = new URLSearchParams(params)
    proximo.set('aba', aba)
    setParams(proximo, { replace: true })
  }

  const invalidar = () => {
    queryClient.invalidateQueries({ queryKey: ['risk-operation', id] })
    queryClient.invalidateQueries({ queryKey: ['risk-movements', id] })
    queryClient.invalidateQueries({ queryKey: ['risk-extensions', id] })
    queryClient.invalidateQueries({ queryKey: ['risk-renewals', id] })
    queryClient.invalidateQueries({ queryKey: ['risk-operations'] })
    queryClient.invalidateQueries({ queryKey: ['risk-summary'] })
  }

  const escopo = projectScopeCode(consulta.error)
  if (escopo) return <ProjectScopeState code={escopo} recurso="as operações de risco" />

  if (consulta.isPending) return <LoadingState label="Carregando a operação…" />

  if (consulta.error || !operacao) {
    return (
      <div className="space-y-4">
        <ErrorState
          title="Não foi possível abrir a operação"
          description={mensagemDeErro(consulta.error) ?? 'A operação não existe ou não pertence a este projeto.'}
          onRetry={() => consulta.refetch()}
        />
        <div className="flex justify-center">
          <Button variant="secondary" onClick={() => navigate('/risk-operations')}>
            Voltar para a lista
          </Button>
        </div>
      </div>
    )
  }

  const podeRenovar = podeEscrever && !operacao.has_pre_faturamento && !operacao.is_static

  return (
    <div className="space-y-6">
      <PageHeader
        title={operacao.title || 'Operação de risco'}
        subtitle={[operacao.carrier_title, operacao.operation_subtype_title].filter(Boolean).join(' · ')}
        rightSlot={
          <div className="flex flex-wrap gap-2">
            <Button variant="ghost" onClick={() => navigate('/risk-operations')}>
              <ArrowLeft className="mr-2 h-4 w-4" />
              Voltar
            </Button>
            {podeEscrever && !operacao.is_static && (
              <Button variant="secondary" onClick={() => setEditando(true)}>
                <Pencil className="mr-2 h-4 w-4" />
                Editar
              </Button>
            )}
            {podeRenovar && (
              <>
                <Button variant="secondary" onClick={() => setProrrogando(true)}>
                  <CalendarClock className="mr-2 h-4 w-4" />
                  Prorrogar
                </Button>
                <Button onClick={() => setRenovando(true)}>
                  <RefreshCw className="mr-2 h-4 w-4" />
                  Renovar
                </Button>
              </>
            )}
          </div>
        }
      />

      <Tabs value={abaAtual} onValueChange={trocarAba}>
        <TabsList>
          <TabsTrigger value="geral">Geral</TabsTrigger>
          <TabsTrigger value="movimentacoes">Movimentações</TabsTrigger>
          {/* Só para tipo SEM pré-faturamento — o par estático não tem
              vencimento a prorrogar. */}
          {!operacao.has_pre_faturamento && (
            <TabsTrigger value="prorrogacoes">Prorrogações</TabsTrigger>
          )}
        </TabsList>

        <TabsContent value="geral">
          <OperationGeneralTab operacao={operacao} />
        </TabsContent>

        <TabsContent value="movimentacoes">
          <MovementsTab operacao={operacao} />
        </TabsContent>

        {!operacao.has_pre_faturamento && (
          <TabsContent value="prorrogacoes">
            <ExtensionsTab operacao={operacao} />
          </TabsContent>
        )}
      </Tabs>

      <RiskOperationDrawer
        open={editando}
        operacao={editando ? operacao : null}
        onClose={() => setEditando(false)}
        onSaved={invalidar}
      />

      {renovando && (
        <RenewalDrawer operacao={operacao} onClose={() => setRenovando(false)} onRenewed={invalidar} />
      )}

      {prorrogando && (
        <ExtensionDrawer operacao={operacao} onClose={() => setProrrogando(false)} onExtended={invalidar} />
      )}
    </div>
  )
}
