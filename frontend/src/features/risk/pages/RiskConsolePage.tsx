import { useEffect, useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, ShieldAlert } from 'lucide-react'
import { PageHeader } from '@/components/PageHeader'
import { DatePicker } from '@/components/ui/DatePicker'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { mensagemDeErro } from '@/components/ui/AsyncSection'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { Select } from '@/components/ui/Select'
import { MobileCard } from '@/components/mobile/MobileCard'
import { useMobile } from '@/hooks/useMobile'
import { companiesApi } from '@/lib/api/projects'
import { formatPercent } from '@/lib/utils/number'
import { riskControlsApi, type ExposureTypeGroup, type RiskSummary } from '../api/risk'
import { ExposureByTypeTable, ExposureSingleCarrier } from '../components/ExposureTables'

/**
 * **Controle de Risco** (FE-230..FE-239) — o painel principal do produto.
 *
 * É a tela que o cliente abre para saber quanto de cada limite está utilizado,
 * disponível, liquidável e em pré-faturamento **numa data**.
 *
 * ### Uma aba só, e é de propósito
 *
 * O legado declara duas (`RESUMO` e posições diárias) e a segunda está
 * **comentada** no próprio arquivo, junto com o botão "Cadastrar posição", que
 * nasce com classe `deactive`. A aba de posições não volta (DEC-57 / FE-234) — o
 * dado é preservado no banco, a superfície não.
 *
 * ### O estado de erro é a razão principal desta tela ter sido reescrita
 *
 * No legado o `failure` do proxy AJAX era **vazio**: quando a consulta falhava,
 * o painel ficava em carregamento eterno ou mostrando o dado velho da consulta
 * anterior — sem nada dizendo que a data mudou e a resposta não chegou. Num
 * painel de exposição de crédito isso é a diferença entre decidir com o número
 * de hoje e decidir com o de ontem achando que é o de hoje.
 *
 * Os três estados (carregando, vazio, erro) são obrigatórios aqui, e **erro não
 * pode parecer vazio**.
 *
 * ### Sem polling (Princípio 10)
 *
 * O estado vem do mesmo carregamento da tela. Trocar empresa, portador ou data
 * refaz a consulta pela `queryKey` do React Query — não há `setInterval` em
 * lugar nenhum, e atualização ao vivo, se um dia houver, é Action Cable.
 */
export function RiskConsolePage() {
  const estreito = useMobile()
  const [empresa, setEmpresa] = useState<string | null>(null)
  const [portador, setPortador] = useState<string | null>(null)
  const [data, setData] = useState<Date>(() => new Date())

  useEffect(() => {
    document.title = 'Safegold - Controle de Risco'
  }, [])

  const dataIso = useMemo(() => toIsoDate(data), [data])

  const empresas = useQuery({
    queryKey: ['risk-console-companies'],
    queryFn: () => companiesApi.list({ perPage: 100 }),
  })

  // FE-232 — só portadores COM limite ativo, e a lista muda com a empresa.
  const portadores = useQuery({
    queryKey: ['risk-console-carriers', empresa],
    queryFn: () => riskControlsApi.carriersWithActiveControl(empresa ?? undefined),
  })

  const resumo = useQuery({
    queryKey: ['risk-summary', empresa, portador, dataIso],
    queryFn: () =>
      riskControlsApi.summary({
        companyId: empresa ?? undefined,
        carrierId: portador ?? undefined,
        date: dataIso,
      }),
  })

  const escopo = projectScopeCode(resumo.error)

  return (
    <div className="pb-10">
      <PageHeader
        title="Controle de risco"
        subtitle="Quanto de cada limite está utilizado, disponível, liquidável e em pré-faturamento — na data escolhida."
        loading={resumo.isFetching && !resumo.isLoading}
      />

      <div className="mb-4 grid gap-2 sm:grid-cols-3">
        {/* FE-231 — sem empresa, o resumo agrega o PROJETO inteiro, e a opção
            em branco do legado (`include_blank: "Grupo econômico"`) é o que
            NOMEIA isso. Ela é uma opção da lista, não um botão de limpar: linha
            vazia sem rótulo é lida como "escolha alguma coisa".
            Trocar a empresa zera o portador — a lista de portadores muda com ela. */}
        <Select
          aria-label="Empresa"
          options={[
            { value: '', label: 'Grupo econômico', description: 'Agrega o projeto inteiro' },
            ...(empresas.data?.items ?? []).map((e) => ({ value: e.id, label: e.title })),
          ]}
          value={empresa ?? ''}
          onChange={(v) => {
            setEmpresa(v || null)
            setPortador(null)
          }}
        />

        <Select
          aria-label="Portador"
          options={[
            { value: '', label: 'TODOS', description: 'Um cabeçalho por tipo de limite' },
            ...(portadores.data ?? []).map((c) => ({
              value: c.id,
              label: c.title,
              description: c.group_title ?? undefined,
            })),
          ]}
          value={portador ?? ''}
          onChange={(v) => setPortador(v || null)}
        />

        {/* FE-233 — data única, e `maxDate = hoje`. Consultar exposição futura
            não existe no legado; oferecer seria feature nova (DEC-09). */}
        <DatePicker
          aria-label="Data da posição"
          value={data}
          onChange={(d) => d && setData(d)}
          max={new Date()}
          clearable={false}
        />
      </div>

      {resumo.isLoading ? (
        <LoadingState label="Apurando a exposição na data…" />
      ) : escopo ? (
        // Os dois 409 de escopo NÃO são falha: são o sistema esperando uma
        // escolha, ou dizendo que não há projeto a mostrar. Página de erro aqui
        // faria o usuário procurar um problema que não existe.
        <ProjectScopeState code={escopo} recurso="a exposição de risco" />
      ) : resumo.isError ? (
        // O estado que o legado NÃO tinha. Erro não pode parecer vazio.
        <ErrorState
          title="Não foi possível apurar a exposição"
          description={
            mensagemDeErro(resumo.error) ??
            'A consulta ao servidor falhou. Não há número para mostrar — e "sem número" não é zero. Tente de novo ou escolha outra data.'
          }
          onRetry={() => resumo.refetch()}
        />
      ) : (
        <ResumoDeExposicao resumo={resumo.data} estreito={estreito} />
      )}
    </div>
  )
}

function ResumoDeExposicao({ resumo, estreito }: { resumo: RiskSummary | undefined; estreito: boolean }) {
  if (!resumo) return null

  const grupos = resumo.controls_info ?? []

  if (grupos.length === 0) {
    return (
      <EmptyState
        title="Nenhum limite ativo nesta seleção"
        description={
          resumo.scope === 'company'
            ? 'Esta empresa não tem limite ativo. Cadastre um em "Limites" ou escolha outra empresa.'
            : 'Este projeto não tem limite ativo. Cadastre o primeiro em "Limites".'
        }
      />
    )
  }

  return (
    <div className="space-y-4">
      <AvisoDeEstouro grupos={grupos} />

      {estreito ? (
        <ResumoEstreito grupos={grupos} />
      ) : resumo.is_single ? (
        <ExposureSingleCarrier grupos={grupos} carrierTitle={resumo.carrier_title} />
      ) : (
        <ExposureByTypeTable grupos={grupos} />
      )}
    </div>
  )
}

/**
 * **NEW-004 — o aviso de estouro de limite** (DEC-95).
 *
 * Feature nova, aprovada explicitamente: quando a utilização passa do teto, a
 * tela avisa. O QA do Phase 4 **não deve procurá-la no legado**.
 *
 * **É proibido este aviso recalcular por conta própria.** O número já vem do
 * motor de limites (contrato C2); aqui ele é apenas lido — `limite_disponivel`
 * negativo é a definição de estourado, a mesma que pinta a célula. Recalcular
 * criaria a segunda fonte de verdade que o C2 existe para impedir.
 *
 * Sem polling: o estado vem do mesmo carregamento da tela (Princípio 10).
 */
function AvisoDeEstouro({ grupos }: { grupos: ExposureTypeGroup[] }) {
  const estourados = grupos.flatMap((g) =>
    g.rcs
      .filter((linha) => Number(linha.limits.limite_disponivel) < 0)
      .map((linha) => ({ tipo: g.title, portador: linha.risk_title, valor: linha.limits.formatted_limite_disponivel })),
  )

  if (estourados.length === 0) return null

  return (
    <div
      role="alert"
      className="flex items-start gap-3 rounded-lg border border-border bg-negative/10 p-4 text-sm"
    >
      <ShieldAlert aria-hidden="true" className="mt-0.5 h-5 w-5 shrink-0 text-negative" />
      <div className="min-w-0">
        <p className="font-medium text-foreground">
          {estourados.length === 1
            ? '1 limite está com utilização acima do teto'
            : `${estourados.length} limites estão com utilização acima do teto`}
        </p>
        <ul className="mt-1 space-y-0.5 text-muted-foreground">
          {estourados.slice(0, 5).map((e, i) => (
            <li key={`${e.tipo}-${e.portador}-${i}`}>
              <span className="text-foreground">{e.portador}</span> · {e.tipo} ·{' '}
              <span className="font-numeric tabular-nums text-negative">{e.valor}</span> disponível
            </li>
          ))}
          {estourados.length > 5 && <li>e mais {estourados.length - 5}…</li>}
        </ul>
      </div>
    </div>
  )
}

/**
 * **Versão estreita** (DEC-100): cartão por linha, nunca tabela com rolagem
 * horizontal. No celular a coluna que sai da tela costuma ser justamente o valor
 * disponível — que é a razão de alguém abrir esta tela fora do escritório.
 */
function ResumoEstreito({ grupos }: { grupos: ExposureTypeGroup[] }) {
  return (
    <div className="space-y-6">
      {grupos.map((grupo) => (
        <section key={grupo.id}>
          <header className="mb-2">
            <h2 className="text-sm font-medium uppercase tracking-[0.05em] text-muted-foreground">{grupo.title}</h2>
            <p className="font-numeric tabular-nums text-sm text-foreground">
              {grupo.formatted_util} utilizado de {grupo.formatted_total}
            </p>
          </header>

          {grupo.rcs.map((linha, i) => {
            const disponivel = Number(linha.limits.limite_disponivel)
            const estourado = disponivel < 0
            return (
              <MobileCard
                key={linha.id ?? linha.carrier_id ?? i}
                title={linha.risk_title}
                subtitle={linha.risk_subtitle || undefined}
                status={estourado ? 'Acima do teto' : undefined}
                statusTone={estourado ? 'warning' : undefined}
              >
                <dl className="grid grid-cols-2 gap-2 text-sm">
                  <Campo rotulo="Liquidável" valor={linha.limits.formatted_limite_liquidavel} />
                  <Campo rotulo="Pré-Faturamento" valor={linha.has_pre ? linha.limits.formatted_limite_pre : '-'} />
                  <Campo rotulo="Lim. util" valor={linha.limits.formatted_limite_utilizado} />
                  <Campo
                    rotulo="Lim. disp"
                    valor={linha.limits.formatted_limite_disponivel}
                    tom={estourado ? 'negative' : 'success'}
                  />
                  <Campo rotulo="Lim. total" valor={linha.limits.formatted_limite_total} />
                  <Campo rotulo="Tax" valor={formatPercent(Number(linha.limits.taxa))} />
                </dl>
                {estourado && (
                  <p className="mt-2 flex items-center gap-1.5 text-xs text-negative">
                    <AlertTriangle aria-hidden="true" className="h-3.5 w-3.5 shrink-0" />
                    Utilização acima do teto cadastrado.
                  </p>
                )}
              </MobileCard>
            )
          })}
        </section>
      ))}
    </div>
  )
}

function Campo({ rotulo, valor, tom }: { rotulo: string; valor: string; tom?: 'negative' | 'success' }) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">{rotulo}</dt>
      <dd
        className={
          tom === 'negative'
            ? 'font-numeric tabular-nums text-negative'
            : tom === 'success'
              ? 'font-numeric tabular-nums text-success'
              : 'font-numeric tabular-nums text-foreground'
        }
      >
        {valor}
      </dd>
    </div>
  )
}

/** `yyyy-mm-dd` no fuso LOCAL — `toISOString()` volta um dia em fusos negativos. */
function toIsoDate(d: Date): string {
  const mes = String(d.getMonth() + 1).padStart(2, '0')
  const dia = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${mes}-${dia}`
}
