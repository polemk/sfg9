import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, Coins, Landmark, Layers3, Lock, Pencil, Receipt as ReceiptIcon } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { ErrorState, LoadingState } from '@/components/ui/States'
import { Tooltip } from '@/components/ui/Tooltip'
import { KpiCard } from '@/components/kpi/KpiCard'
import { SectionHeading } from '@/components/ui/SectionHeading'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { mensagemDeErro } from '@/components/ui/AsyncSection'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { formatMoney } from '@/lib/utils/number'
import { chargesApi, type Charge, type ChargeStatementLine } from '../api/receivables'
import { ChargeEditDrawer } from '../components/ChargeEditDrawer'

/**
 * **Detalhe da cobrança** — rota própria, `/charges/:id`.
 *
 * ## Por que deixou de ser gaveta
 *
 * Achado do usuário (26/08/2026): *"o detalhe de cobrança ficou muito ruim
 * assim, ou fazemos em diálogo ou em uma página separada"*. Página, e a razão é
 * medida, não estética: o detalhe da cobrança é a porta da **seleção de
 * recibos**, e numa cobrança real dessa base isso é uma lista de **214
 * candidatos** com **9 persistidos**. O que o detalhe mostra — o extrato por
 * remuneração — é a mesma coisa em miniatura: uma tabela.
 *
 * A regra que vale para todo o app, e que o `SideDrawer` de ontem quebrava:
 * **formulário curto = gaveta; leitura densa = página**. O `SideDrawer` é
 * estreito e alto de propósito, porque formulário é uma coluna de campos —
 * espremer uma tabela ali brigaria com a rolagem horizontal, a coluna congelada
 * e os cartões de telefone que o `DataTable` acabou de ganhar (DS-01, DS-02). A
 * criação de cobrança **continua** gaveta, porque ela é de fato um formulário
 * curto: uma data e uma explicação.
 *
 * O par de páginas fica coerente com o resto do console: `/charges/:id` é o
 * detalhe e `/charges/:id/receipts` é a seleção — as duas com endereço, as duas
 * com Voltar do navegador funcionando. No legado a segunda era
 * `{section: 'receipts'}` em memória, com `history.replaceState`, e o botão
 * Voltar saía do console (**D-92**).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * `charges`, `receipts` e `remunerations` não existem no banco de produção: as
 * migrations que as criam estão entre as 24 que nunca subiram. Esta tela é o
 * espelho do código de 2022 (`../sfg/app/controllers/pub/charges_controller.rb`).
 */
export function ChargeDetailPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()

  const consulta = useQuery({
    queryKey: ['charge', id],
    queryFn: () => chargesApi.get(id),
    enabled: !!id,
  })

  const extrato = useQuery({
    queryKey: ['charge-statement', id],
    queryFn: () => chargesApi.statement(id),
    enabled: !!id,
  })

  const cobranca = consulta.data
  // FE-183 — a MESMA gaveta da lista. Ver `ChargeEditDrawer`.
  const [editando, setEditando] = useState<Charge | null>(null)

  useEffect(() => {
    document.title = cobranca
      ? `Safegold - Cobrança de ${dataBr(cobranca.date)}`
      : 'Safegold - Cobrança'
  }, [cobranca])

  const escopo = projectScopeCode(consulta.error)
  if (escopo) return <ProjectScopeState code={escopo} recurso="as cobranças" />

  if (consulta.isPending) return <LoadingState label="Carregando a cobrança…" />

  if (consulta.error || !cobranca) {
    return (
      <div className="space-y-4">
        <ErrorState
          title="Não foi possível abrir a cobrança"
          description={
            mensagemDeErro(consulta.error) ??
            'A cobrança não existe ou não pertence a este projeto.'
          }
          onRetry={() => consulta.refetch()}
        />
        <div className="flex justify-center">
          <Button variant="secondary" onClick={() => navigate('/charges')}>
            Voltar para a lista
          </Button>
        </div>
      </div>
    )
  }

  const linhas = extrato.data?.statement ?? []

  /**
   * O extrato é **tabela**, e por isso é `DataTable` — não uma `<ul>` desenhada
   * aqui. Com ela vêm de fábrica a rolagem com afordância, a coluna de
   * identificação congelada e os cartões abaixo de 768 px (DS-01/DS-02). Uma
   * lista à mão seria a décima quarta cópia do mesmo cartão.
   */
  const colunas: Column<ChargeStatementLine>[] = [
    {
      key: 'title',
      header: 'Remuneração',
      accessor: (l) => l.title,
      cell: (l) => <span className="text-foreground">{l.title}</span>,
    },
    {
      key: 'kind',
      header: 'Classe',
      width: '6rem',
      accessor: (l) => l.kind,
      // O MESMO par sigla + explicação da seleção de recibos
      // (`ChargeReceiptsPage`): as duas telas falam da mesma classe, e duas
      // grafias para a mesma coisa é como um vocabulário se parte.
      cell: (l) => (
        <Tooltip content={l.kind === 'LIQ' ? 'Operações de risco' : 'Operações estruturadas'}>
          <Badge variant={l.kind === 'LIQ' ? 'secondary' : 'outline'}>{l.kind}</Badge>
        </Tooltip>
      ),
    },
    {
      key: 'receipts_count',
      header: 'Recibos',
      width: '7rem',
      variant: 'number',
      accessor: (l) => l.receipts_count,
    },
    {
      key: 'operations_value',
      header: 'Valor das operações',
      align: 'right',
      accessor: (l) => Number(l.operations_value),
      cell: (l) => (
        <span className="font-numeric tabular-nums">{formatMoney(num(l.operations_value))}</span>
      ),
    },
    {
      key: 'value',
      header: 'Valor da remuneração',
      align: 'right',
      variant: 'money',
      accessor: (l) => Number(l.value),
      cell: (l) => (
        <span className="font-numeric tabular-nums text-foreground">
          {formatMoney(num(l.value))}
        </span>
      ),
    },
  ]

  return (
    <div className="space-y-6 pb-10">
      <PageHeader
        title={`Cobrança de ${dataBr(cobranca.date)}`}
        subtitle={`${cobranca.state_label} · ${cobranca.receipts_count} recibo(s) no pacote`}
        loading={consulta.isFetching && !consulta.isLoading}
        rightSlot={
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="ghost" onClick={() => navigate('/charges')}>
              <ArrowLeft aria-hidden="true" className="h-4 w-4" />
              Voltar para a lista
            </Button>
            {/* FE-183 — editar a partir do detalhe. Some no pacote faturado,
                que o servidor recusa de qualquer forma (D-18). */}
            {!cobranca.done && (
              <Button variant="secondary" onClick={() => setEditando(cobranca)}>
                <Pencil aria-hidden="true" className="h-4 w-4" />
                Editar
              </Button>
            )}
            {/* S8 / FE-184 — o caminho para a seleção de operações. No legado
                era `#select_receipt`, que trocava `route.section` em memória. */}
            <Button onClick={() => navigate(`/charges/${cobranca.id}/receipts`)}>
              <ReceiptIcon aria-hidden="true" className="h-4 w-4" />
              {cobranca.done ? 'Ver operações da cobrança' : 'Escolher operações da cobrança'}
            </Button>
          </div>
        }
      />

      <ChargeEditDrawer charge={editando} onClose={() => setEditando(null)} />

      {cobranca.done && (
        // D-18 — o bloqueio é do SERVIDOR. No legado ele existia só na tela, e a
        // API aceitava a alteração de um pacote já emitido.
        <Card className="flex items-start gap-3 border-border bg-muted/40 p-4">
          <Lock aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            Esta cobrança está <strong>faturada</strong>. Ela não aceita mais alteração — e o
            servidor recusa, mesmo fora desta tela.
          </p>
        </Card>
      )}

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard title="Valor cobrado" value={formatMoney(num(cobranca.value))} icon={Coins} />
        <KpiCard
          title="Valor das operações"
          value={formatMoney(num(cobranca.total_operations_value))}
          icon={Landmark}
        />
        <KpiCard
          title="Operações de risco"
          value={String(cobranca.risk_operations_count)}
          icon={ReceiptIcon}
        />
        <KpiCard
          title="Operações estruturadas"
          value={String(cobranca.structured_operations_count)}
          icon={Layers3}
        />
      </div>

      <section>
        <SectionHeading hint="Uma linha por remuneração cobrada, com quantos recibos ela reúne.">
          Extrato por remuneração
        </SectionHeading>

        {extrato.isError ? (
          // A mensagem do servidor nomeia a fatia que falta (S8). É **estado**,
          // não falha: uma lista vazia aqui faria parecer que não há nada a
          // faturar, que é uma afirmação diferente e errada.
          <p className="rounded-md border border-border bg-muted/40 px-3 py-3 text-sm text-muted-foreground">
            {mensagemDoServidor(extrato.error, 'Não foi possível carregar o extrato.')}
          </p>
        ) : (
          <DataTable<ChargeStatementLine>
            columns={colunas}
            data={linhas}
            rowKey={(l) => `${l.kind}-${l.remuneration_id}`}
            loading={extrato.isLoading}
            loadingLabel="Carregando extrato…"
            caption="Extrato por remuneração desta cobrança"
            emptyTitle="Nenhum recibo neste pacote ainda"
            emptyDescription="Escolha as operações da cobrança para o extrato aparecer aqui."
            emptyAction={
              !cobranca.done ? (
                <Button
                  variant="secondary"
                  onClick={() => navigate(`/charges/${cobranca.id}/receipts`)}
                >
                  Escolher operações da cobrança
                </Button>
              ) : undefined
            }
          />
        )}
      </section>
    </div>
  )
}

function num(v: string | number | null | undefined): number | null {
  if (v === null || v === undefined || v === '') return null
  const n = typeof v === 'number' ? v : Number(v)
  return Number.isFinite(n) ? n : null
}

function dataBr(iso: string | null | undefined): string {
  if (!iso) return '—'
  const [a, m, d] = iso.slice(0, 10).split('-')
  return d && m && a ? `${d}/${m}/${a}` : '—'
}
