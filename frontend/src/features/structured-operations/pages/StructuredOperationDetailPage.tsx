import { useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, Pencil } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { DetailList } from '@/components/ui/DetailList'
import { ErrorState, LoadingState } from '@/components/ui/States'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { mensagemDeErro } from '@/components/ui/AsyncSection'
import { useCurrentProject } from '@/hooks/useCurrentProject'
import { useMobile } from '@/hooks/useMobile'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { formatMoney, formatPercent } from '@/lib/utils/number'
import { structuredOperationsApi } from '../api/structuredOperations'
import { dataBr } from '../lib/format'

/**
 * **Detalhe da operação estruturada** — o card CADASTRO (`FE-299`).
 *
 * ## O que o card mostra, e o que ele deliberadamente NÃO mostra
 *
 * Operação, Tipo, Portador, Contrato, Projeto, as duas datas, Saldo Inicial,
 * Capital, Saldo, Taxa e Observação — exatamente os 12 itens de
 * `structured_operations/detail/tabs/_tab_geral.html.erb`, na mesma ordem.
 *
 * **Não** aparecem: a **empresa** (embora seja ela que define o projeto), os
 * dois flags (`is_on_variable`, `is_ended`) e o **recibo**. As três ausências
 * são do legado e são replicadas: o detalhe é um resumo de cadastro, não um
 * espelho da tabela.
 *
 * ## `DEC-01` / `Q-R20` — os saldos aparecem NEGATIVOS
 *
 * `original_balance` é gravado `(-1) * |valor|` em **todo** save
 * (`structured_operation.rb:37`), e `balance` é copiado dele na mesma linha.
 * A tela do legado mostra os dois com o sinal, e esta mostra também. Não
 * "corrija": é a mesma convenção do `limite_utilizado_on` do painel de risco, e
 * mudá-la aqui faria as duas telas discordarem sobre o mesmo registro.
 *
 * O `balance` é **decorativo** (T-D6 / `BE-292`): nada no legado inteiro dá
 * baixa nele — não existe movimento, liquidação nem baixa de operação
 * estruturada. Por isso ele é rotulado como "saldo inicial recopiado", e não
 * como saldo corrente.
 *
 * ## `FE-299` — id inexistente responde 404, não 500
 *
 * No legado `fetch_structured_operation` fazia `find` **sem escopo** e sem
 * `rescue`: id de outro projeto abria a operação alheia, e id inexistente
 * derrubava a requisição. Aqui o servidor devolve **404 estruturado** para os
 * dois casos — indistinguíveis de propósito — e a tela mostra o estado.
 *
 * ## `FE-289` — a taxa tem DUAS casas aqui e na lista
 *
 * No legado o detalhe usava `sprintf('%.2f')` e a lista imprimia o número cru:
 * o mesmo `agreed_rate` aparecia de dois jeitos em duas telas.
 */
export function StructuredOperationDetailPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const estreito = useMobile()
  const papel = useRoleSlug()
  const somenteLeitura = useIsReadonly()
  const podeEscrever = papel !== null && ALL_ROLES.includes(papel) && !somenteLeitura
  const { current } = useCurrentProject()

  const consulta = useQuery({
    queryKey: ['structured-operation', id],
    queryFn: () => structuredOperationsApi.get(id),
    enabled: !!id,
  })

  const operacao = consulta.data

  useEffect(() => {
    document.title = operacao ? `Safegold - ${operacao.title}` : 'Safegold - Operação Estruturada'
  }, [operacao])

  const escopo = projectScopeCode(consulta.error)
  if (escopo) return <ProjectScopeState code={escopo} recurso="as operações estruturadas" />

  if (consulta.isPending) return <LoadingState label="Carregando a operação…" />

  if (consulta.isError || !operacao) {
    return (
      <div className="space-y-4">
        <ErrorState
          title="Não foi possível abrir a operação"
          description={
            mensagemDeErro(consulta.error) ?? 'A operação não existe ou não pertence a este projeto.'
          }
          onRetry={() => consulta.refetch()}
        />
        <div className="flex justify-center">
          <Button variant="secondary" onClick={() => navigate('/structured-operations')}>
            Voltar para a lista
          </Button>
        </div>
      </div>
    )
  }

  const num = (v: string | null) => (v === null || v === '' ? null : Number(v))

  return (
    <div className="space-y-6 pb-10">
      <PageHeader
        title={operacao.title || 'Operação estruturada'}
        subtitle={[operacao.carrier_title, operacao.operation_type_title].filter(Boolean).join(' · ')}
        rightSlot={
          <div className="flex flex-wrap gap-2">
            <Button variant="ghost" onClick={() => navigate('/structured-operations')}>
              <ArrowLeft aria-hidden="true" className="h-4 w-4" />
              Voltar
            </Button>
            {podeEscrever && (
              <Button variant="secondary" onClick={() => navigate(`/structured-operations/${operacao.id}/edit`)}>
                <Pencil aria-hidden="true" className="h-4 w-4" />
                Editar
              </Button>
            )}
          </div>
        }
      />

      <Card className="p-5">
        <h2 className="mb-4 font-title text-sm font-semibold uppercase tracking-[0.05em] text-muted-foreground">
          Cadastro
        </h2>

        <DetailList
          layout={estreito ? 'stack' : 'grid'}
          columns={2}
          emptyValue="-"
          items={[
            { label: 'Operação', content: operacao.title },
            { label: 'Tipo', content: operacao.operation_type_title },
            { label: 'Portador', content: operacao.carrier_title },
            { label: 'Contrato', content: operacao.contract_number },
            // O legado imprime `project.formal`. O projeto da operação é sempre
            // o corrente (C1), então o nome vem de `current_project`.
            { label: 'Projeto', content: current?.name ?? '-' },
            // Data nula é um traço — no legado, `nil.strftime` derrubava a view.
            { label: 'Data de emissão', content: dataBr(operacao.issue_date) },
            { label: 'Data vencimento', content: dataBr(operacao.due_date) },
            {
              label: 'Saldo Inicial',
              // DEC-01 / Q-R20 — COM o sinal, como o legado exibe.
              content: formatMoney(num(operacao.original_balance)),
              numeric: true,
            },
            {
              label: 'Capital da operação',
              content: formatMoney(num(operacao.operation_value)),
              numeric: true,
            },
            {
              label: 'Saldo',
              content: formatMoney(num(operacao.balance)),
              numeric: true,
            },
            {
              label: 'Taxa acordada',
              content: formatPercent(num(operacao.agreed_rate)),
              numeric: true,
            },
            { label: 'Observação', content: operacao.observation, full: true },
          ]}
        />

        <p className="mt-4 border-t border-border pt-3 text-xs text-muted-foreground">
          O saldo da operação estruturada é uma cópia do saldo inicial, reescrita a cada gravação: não existe
          baixa de saldo nesta operação.
        </p>
      </Card>
    </div>
  )
}
