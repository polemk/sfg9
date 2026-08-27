import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import {
  CalendarDays,
  Hash,
  Lock,
  Trash2,
  TrendingDown,
  TrendingUp,
  Wand2,
} from 'lucide-react'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Calendar } from '@/components/ui/Calendar'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { Card } from '@/components/ui/Card'
import { MoneyInput } from '@/components/ui/NumericInput'
import { Select } from '@/components/ui/Select'
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/Sheet'
import { Tooltip } from '@/components/ui/Tooltip'
import { RichTextView } from '@/components/ui/RichTextField'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import {
  MobileEmptyState,
  MobileErrorState,
  MobileListSkeleton,
} from '@/components/mobile/MobileListState'
import { MobileKPI } from '@/components/mobile/MobileKPI'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { useMobile } from '@/hooks/useMobile'
import { useCurrentProject } from '@/hooks/useCurrentProject'
import { useJobProgress } from '@/hooks/useJobProgress'
import { companiesApi } from '@/lib/api/projects'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { formatPercent } from '@/lib/utils/number'
import {
  availabilityEntriesApi,
  availabilityPanelApi,
  formatarValor,
  type AvailabilityGridRow,
} from '@/lib/api/availability'

/**
 * **Painel de Disponibilidade** — a grade hierárquica por data e empresa
 * (FE-120..FE-134).
 *
 * ## O endpoint desta tela era o D-01
 *
 * No legado `/api/v1/project_availability` herdava de `ApplicationController` —
 * **não** do `PubApplicationController` — e a primeira linha do `before_action`
 * era `Project.find(params[:id] || params[:project_id])`, sem escopo e sem
 * sessão. Qualquer requisição lia a disponibilidade de qualquer projeto por id.
 * Aqui **não existe parâmetro de projeto**: o servidor o resolve por
 * `current_project!`.
 *
 * ## Os números são os do legado, e isso é decisão
 *
 * Quatro DECs mandaram **replicar**, e cada uma tem golden test no servidor:
 *
 * - **DEC-24** — a correção por dias úteis incide sobre o valor digitado, e o
 *   valor digitado é o já corrigido que a tela mostrava (D-02). Por isso o
 *   **FE-134**: os dois números ficam visíveis, com o multiplicador. No legado o
 *   usuário digitava X e via Y, sem nenhuma indicação;
 * - **DEC-26** — duas semânticas de soma convivem: a **consolidação geral** soma
 *   bruto; o **nó com filhos** aplica cumulatividade e sinal (D-08). *O rótulo
 *   não é cosmético: ele É a decisão.* Sem ele, a divergência volta a ser
 *   defeito silencioso;
 * - **DEC-27** — os cards de padrão base mostram **saldo acumulado**
 *   (`virtual_value`), métrica diferente de `value`. O "total geral" bruto do
 *   legado era calculado e **nunca renderizado**; a DEC o classificou como
 *   código morto, e ele não está aqui;
 * - **DEC-28** — dias úteis são seg–sex, **sem feriados**.
 *
 * ## Uma fonte de verdade para "é estreito" (FE-123)
 *
 * `hooks/useMobile.ts`, no cliente. No legado o servidor decidia por *user
 * agent* (`mobile_device?` na view) **e** o cliente por detecção própria
 * (`isMobile.any()` no JS): os dois podiam discordar, e discordavam.
 */
export function AvailabilityPage() {
  const queryClient = useQueryClient()
  const { current: project } = useCurrentProject()
  const isMobile = useMobile()

  const [dia, setDia] = useState<Date>(() => new Date())
  const [mesVisivel, setMesVisivel] = useState<Date>(() => new Date())
  const [companyId, setCompanyId] = useState<string>('')
  const [calendarioAberto, setCalendarioAberto] = useState(false)

  const dataIso = useMemo(() => toIso(dia), [dia])

  const empresas = useQuery({
    queryKey: ['companies', 'availability'],
    queryFn: () => companiesApi.list({ perPage: 100 }),
  })

  const painel = useQuery({
    queryKey: [
      'availability-panel',
      { month: mesVisivel.getMonth() + 1, year: mesVisivel.getFullYear(), companyId },
    ],
    queryFn: () =>
      availabilityPanelApi.get({
        month: mesVisivel.getMonth() + 1,
        year: mesVisivel.getFullYear(),
        company_id: companyId || undefined,
      }),
  })

  const grade = useQuery({
    queryKey: ['availability-grid', { date: dataIso, companyId }],
    queryFn: () =>
      availabilityEntriesApi.grid({ date: dataIso, company_id: companyId || undefined }),
  })

  /**
   * **O tempo real, ligado de verdade.** Ativar/desativar/remover um padrão
   * recalcula lançamentos em segundo plano; quando o job termina, o
   * `ProjectProgressChannel` avisa e as duas consultas se refazem sozinhas.
   * **Nenhum temporizador bate na API** — nem intervalo fixo, nem revalidação
   * periódica do React Query (Princípio 10).
   */
  useJobProgress({
    projectId: project?.id ?? null,
    invalidateKeys: [['availability-panel'], ['availability-grid']],
  })

  // **FE-121 — trocar a visão recarrega indicadores E grade.** No legado só a
  // grade recarregava, e os indicadores continuavam mostrando a empresa
  // anterior. As duas queries têm `companyId` na chave, então a troca invalida
  // as duas por construção — não por um `useEffect` que alguém pode esquecer.

  const invalidar = () => {
    queryClient.invalidateQueries({ queryKey: ['availability-grid'] })
    queryClient.invalidateQueries({ queryKey: ['availability-panel'] })
  }

  const diasMarcados = useMemo(
    () => (painel.data?.dates ?? []).map((d) => fromIso(d)),
    [painel.data?.dates],
  )

  const consolidacao = companyId === ''

  // **Os dois 409 de escopo são ESTADO, não erro.** Qualquer uma das três
  // consultas pode trazê-los, e a resposta é a mesma para a página inteira —
  // não faz sentido desenhar o calendário e os indicadores ao lado de "escolha
  // um projeto".
  const escopo =
    projectScopeCode(painel.error) ?? projectScopeCode(grade.error) ?? projectScopeCode(empresas.error)

  // ------------------------------------------------------------- blocos
  const seletorDeEmpresa = (
    <div>
      <h2 className="mb-2 text-sm font-semibold text-foreground">Escolha uma visão</h2>
      <Select
        id="company_id"
        options={[
          {
            value: '',
            label: 'Consolidação geral',
            description: 'Soma bruta das empresas — não aceita lançamento',
          },
          ...(empresas.data?.items ?? []).map((c) => ({ value: c.id, label: c.title })),
        ]}
        value={companyId}
        onChange={(v) => setCompanyId(v ?? '')}
        placeholder="Consolidação geral"
      />
      {consolidacao && (
        <p className="mt-2 text-xs leading-relaxed text-muted-foreground">
          A consolidação geral <strong>soma o valor bruto</strong> de todas as empresas, sem aplicar
          cumulatividade nem sinal de débito. É uma regra de soma diferente da que os itens com filhos
          usam — escolha uma empresa para lançar valores.
        </p>
      )}
    </div>
  )

  const calendario = (
    <div>
      <h2 className="mb-2 text-sm font-semibold text-foreground">Escolha uma data</h2>
      <Calendar
        selected={dia}
        month={mesVisivel}
        onMonthChange={setMesVisivel}
        onSelect={(d) => {
          setDia(d)
          setCalendarioAberto(false)
        }}
        marked={diasMarcados}
        markedLabel="com lançamento"
        className="w-full rounded-md bg-card p-3 shadow-e1"
      />
      <p className="mt-2 text-xs text-muted-foreground">
        O ponto marca os dias que já têm lançamento neste mês e nesta visão.
      </p>
    </div>
  )

  const indicadores = (
    <div>
      <h2 className="mb-2 text-sm font-semibold text-foreground">Indicadores</h2>

      {/* **FE-120 — a falha APARECE.** No legado o callback de erro desta
          requisição era literalmente vazio: quando ela falhava, os indicadores
          simplesmente paravam nos valores anteriores. */}
      {painel.isError && (
        <ErrorState
          title="Não consegui carregar os indicadores"
          description={mensagemDoServidor(painel.error, 'Tente de novo em instantes.')}
          onRetry={() => painel.refetch()}
        />
      )}

      {painel.isLoading && <LoadingState label="Carregando indicadores…" />}

      {painel.data && (
        <div className="space-y-2">
          {/* FE-124 — quantidade de lançamentos com valor diferente de zero. */}
          <IndicadorSimples
            rotulo="Lançamentos com valor"
            valor={String(painel.data.count)}
            icone={<Hash aria-hidden="true" className="h-4 w-4" />}
          />

          <p className="pt-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            {painel.data.by_entry_label}
          </p>

          {painel.data.by_entry.length === 0 && (
            <p className="text-xs text-muted-foreground">
              Nenhum padrão de 1º nível ativo neste projeto.
            </p>
          )}

          {painel.data.by_entry.map((item) => (
            <IndicadorDeSaldo key={item.id} nome={item.name} total={item.total} />
          ))}
        </div>
      )}
    </div>
  )

  // FE-126 (`reuse`) — a observação do projeto, em modo leitura. Some quando
  // vazia, em vez de deixar um cabeçalho órfão como o legado deixava.
  const observacao = painel.data?.observation_html ? (
    <div>
      <h2 className="mb-2 text-sm font-semibold text-foreground">Observação</h2>
      <Card className="p-3">
        <RichTextView html={painel.data.observation_html} />
      </Card>
    </div>
  ) : null

  const gradeDoDia = (
    <GradeDeDisponibilidade
      consulta={grade}
      consolidacao={consolidacao}
      dataIso={dataIso}
      companyId={companyId}
      onMudou={invalidar}
      isMobile={isMobile}
    />
  )

  // -------------------------------------------------------- versão estreita
  if (isMobile) {
    return (
      <div className="space-y-4">
        <header>
          <h1 className="text-xl font-semibold text-foreground">Disponibilidade</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {formatarDataLonga(dia)} · {consolidacao ? 'Consolidação geral' : nomeDaEmpresa(empresas.data?.items, companyId)}
          </p>
        </header>

        {escopo ? (
          <ProjectScopeState code={escopo} recurso="as disponibilidades" />
        ) : (
          <>
        {seletorDeEmpresa}

        {/* **FE-123 — a escolha de data na tela estreita.** Uma folha ancorada
            no rodapé, na zona do polegar, com o mesmo calendário da tela larga:
            um componente, um comportamento. */}
        <Button
          variant="secondary"
          className="min-h-[3rem] w-full justify-start"
          onClick={() => setCalendarioAberto(true)}
        >
          <CalendarDays aria-hidden="true" className="mr-2 h-4 w-4" />
          {formatarDataLonga(dia)}
        </Button>

        {/* Folha ancorada no RODAPÉ — a zona do polegar (DEC-100, item 2). E
            `safe-area-inset-bottom` porque, instalado como PWA, o navegador
            some e o conteúdo ficaria sob o indicador de início do iPhone. */}
        <Sheet open={calendarioAberto} onOpenChange={setCalendarioAberto}>
          <SheetContent side="bottom" className="pb-[env(safe-area-inset-bottom)]">
            <SheetHeader>
              <SheetTitle>Escolha uma data</SheetTitle>
            </SheetHeader>
            {calendario}
          </SheetContent>
        </Sheet>

        {painel.data && (
          // **Uma coluna, não duas.** Em 390 px, dois `MobileKPI` lado a lado
          // cortam o valor: "R$ 225.990,00" virava "R$ 225.990" sem os
          // centavos — e num painel financeiro o centavo cortado é o tipo de
          // detalhe que faz o usuário conferir no papel. Medido em 390×844.
          <div className="grid grid-cols-1 gap-2">
            <MobileKPI
              title="Lançamentos"
              value={painel.data.count}
              icon={Hash}
              format="plain"
            />
            {painel.data.by_entry.slice(0, 3).map((item) => (
              <MobileKPI
                key={item.id}
                title={item.name}
                // **String, não número.** O `format="currency"` do `MobileKPI`
                // arredonda para zero casas (convenção de KPI da S0, e ela está
                // certa para um indicador). Aqui o número é **saldo financeiro**:
                // "R$ 225.990" em vez de "R$ 225.990,00" é o tipo de detalhe que
                // faz o usuário ir conferir no papel. O componente deixa string
                // passar sem formatar, então a tela estreita e a larga usam o
                // **mesmo** `formatarValor` — inclusive o sinal (FE-125).
                value={formatarValor(item.total)}
                icon={Number(item.total) < 0 ? TrendingDown : TrendingUp}
                color={
                  Number(item.total) < 0 ? 'hsl(var(--negative))' : 'hsl(var(--success))'
                }
              />
            ))}
          </div>
        )}

        {gradeDoDia}
        {observacao}
          </>
        )}
      </div>
    )
  }

  // ---------------------------------------------------------- versão larga
  return (
    <div>
      <header className="mb-4">
        <h1 className="text-xl font-semibold text-foreground">Painel de Disponibilidade</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Os valores do projeto por data e por empresa, na árvore de padrões.
        </p>
      </header>

      {escopo && <ProjectScopeState code={escopo} recurso="as disponibilidades" />}

      {!escopo && (
      <div className="flex flex-col gap-6 lg:flex-row">
        <aside className="w-full space-y-6 lg:w-80 lg:shrink-0">
          {seletorDeEmpresa}
          {calendario}
          {indicadores}
          {observacao}
        </aside>

        <section className="min-w-0 flex-1">{gradeDoDia}</section>
      </div>
      )}
    </div>
  )
}

/**
 * A grade hierárquica (FE-127..FE-134).
 *
 * **Sempre expandida** (DC-35): o código de colapsar/expandir do legado está
 * **comentado** no HTML e no SCSS — porta-se o que roda. Expandir/recolher
 * entra como comportamento novo do `DataTable`, não como paridade.
 */
function GradeDeDisponibilidade({
  consulta,
  consolidacao,
  dataIso,
  companyId,
  onMudou,
  isMobile,
}: {
  consulta: ReturnType<typeof useQuery<Awaited<ReturnType<typeof availabilityEntriesApi.grid>>>>
  consolidacao: boolean
  dataIso: string
  companyId: string
  onMudou: () => void
  isMobile: boolean
}) {
  const linhas = consulta.data?.rows ?? []

  // **FE-128 — os cinco estados, e nenhum deles se parece com outro.** No
  // legado a falha era silenciosa: a lista simplesmente parava de atualizar.
  if (consulta.isLoading) {
    return isMobile ? <MobileListSkeleton rows={8} /> : <LoadingState label="Carregando a grade…" />
  }

  if (consulta.isError) {
    const detalhe = mensagemDoServidor(consulta.error, 'Tente de novo em instantes.')
    return isMobile ? (
      <MobileErrorState detail={detalhe} onRetry={() => consulta.refetch()} />
    ) : (
      <ErrorState
        title="Não consegui carregar a grade"
        description={detalhe}
        onRetry={() => consulta.refetch()}
      />
    )
  }

  if (!dataIso) {
    return isMobile ? (
      <MobileEmptyState title="Selecione uma data" description="Escolha o dia para ver os lançamentos." />
    ) : (
      <EmptyState title="Selecione uma data" description="Escolha o dia para ver os lançamentos." />
    )
  }

  if (linhas.length === 0) {
    // Português corrigido: o legado escrevia "Voce nao possue…".
    const titulo = 'Nenhum padrão ativo neste projeto'
    const descricao =
      'Você ainda não tem padrões de disponibilidade ativos. Cadastre-os em "Disponibilidades", ou traga-os do catálogo global.'
    return isMobile ? (
      <MobileEmptyState title={titulo} description={descricao} />
    ) : (
      <EmptyState title={titulo} description={descricao} />
    )
  }

  return (
    <div>
      {/* **DEC-26 — o rótulo do modo de leitura.** É a metade da decisão que
          impede as duas regras de soma de virarem o D-08 outra vez. */}
      <div className="mb-3 flex flex-wrap items-center gap-2">
        {/* `shrink-0` + `whitespace-nowrap`: sem os dois o selo quebra entre o
            ícone e o rótulo quando a coluna aperta, e "Σ" fica sozinho numa
            linha. */}
        <Badge variant={consolidacao ? 'info' : 'secondary'} className="shrink-0 whitespace-nowrap">
          {consulta.data?.mode_label}
        </Badge>
        <span className="text-xs text-muted-foreground">
          {consolidacao
            ? 'Os valores desta visão são a soma bruta das empresas.'
            : 'Os itens com filhos mostram o total do grupo, respeitando cumulatividade e sinal.'}
        </span>
      </div>

      <div className="space-y-1">
        {linhas.map((linha) => (
          <LinhaDaGrade
            key={linha.template.id}
            linha={linha}
            dataIso={dataIso}
            companyId={companyId}
            onMudou={onMudou}
          />
        ))}
      </div>
    </div>
  )
}

function LinhaDaGrade({
  linha,
  dataIso,
  companyId,
  onMudou,
}: {
  linha: AvailabilityGridRow
  dataIso: string
  companyId: string
  onMudou: () => void
}) {
  const { template, entry, editable, has_children: temFilhos } = linha
  const [valor, setValor] = useState<number | null>(entry ? Number(entry.value) : null)
  // FE-131 — a confirmação antes de excluir o lançamento.
  const [confirmandoExclusao, setConfirmandoExclusao] = useState(false)

  // O valor volta a acompanhar o servidor quando a consulta se refaz — por
  // gravação, por troca de data ou por evento do canal.
  useEffect(() => {
    setValor(entry ? Number(entry.value) : null)
  }, [entry?.id, entry?.value])

  /**
   * **FE-130 — a guarda de envio duplo é POR CÉLULA.**
   *
   * O legado usava `$('form')` — o formulário **global** da tela —, então
   * bloquear o envio de uma célula travava a grade inteira, e desbloquear
   * liberava todas. `useMutation` por linha resolve isso por construção: cada
   * célula tem o próprio `isPending`.
   */
  const gravar = useMutation({
    mutationFn: (novo: number) =>
      entry
        ? availabilityEntriesApi.update(entry.id, novo)
        : availabilityEntriesApi.create({
            availability_template_id: template.id,
            company_id: companyId,
            date: dataIso,
            value: novo,
          }),
    onSuccess: () => {
      // A mensagem distingue criado de alterado — o legado dizia "salvo" para
      // os dois.
      notify.success(entry ? 'Lançamento alterado.' : 'Lançamento criado.')
      onMudou()
    },
    onError: (erro) => {
      notify.error(mensagemDoServidor(erro, 'Não foi possível salvar o lançamento.'))
      setValor(entry ? Number(entry.value) : null)
    },
  })

  const excluir = useMutation({
    mutationFn: () => availabilityEntriesApi.remove(entry!.id),
    onSuccess: () => {
      notify.success('Lançamento excluído.')
      setConfirmandoExclusao(false)
      onMudou()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível excluir o lançamento.')),
  })

  const ehDebito = template.operation_type === 'D'
  const IconeNatureza = ehDebito ? TrendingDown : TrendingUp

  return (
    <div
      className="flex flex-col gap-2 rounded-md bg-card px-3 py-2 shadow-e1 sm:flex-row sm:items-center sm:gap-3"
      style={{ marginLeft: `${(template.level - 1) * 1.25}rem` }}
    >
      <div className="flex min-w-0 flex-1 items-center gap-2">
        <span className="w-14 shrink-0 font-numeric text-xs tabular-nums text-muted-foreground">
          {template.position_path}
        </span>
        <span className={temFilhos ? 'truncate font-semibold' : 'truncate'}>{template.title}</span>

        {/* FE-129 — a natureza da operação LEGÍVEL. O legado exibia `C`/`D` cru. */}
        <Tooltip content={`${template.operation_type_label} · ${template.deadline_type_label}`}>
          <IconeNatureza
            aria-label={template.operation_type_label}
            className={ehDebito ? 'h-4 w-4 shrink-0 text-negative' : 'h-4 w-4 shrink-0 text-success'}
          />
        </Tooltip>

        {/* FE-133 — o marcador de não cumulativo, com explicação consultável. */}
        {template.is_cumulative === false && (
          <Tooltip content="Não cumulativo: este item NÃO entra na soma do nível acima — contribui zero.">
            <Badge variant="outline" className="whitespace-nowrap">Não soma</Badge>
          </Tooltip>
        )}

        {template.is_locked && (
          <Tooltip content={template.locked_message ?? 'Operação em andamento neste padrão.'}>
            <Lock aria-hidden="true" className="h-3.5 w-3.5 shrink-0 text-warning" />
          </Tooltip>
        )}
      </div>

      <div className="flex shrink-0 items-center gap-2 sm:w-72 sm:justify-end">
        {/* **FE-134 — os DOIS valores visíveis.** No legado o usuário digitava X
            e via Y, sem nenhuma indicação de que houve correção. */}
        {entry?.is_adjusted && entry.business_days_multiplier !== null && (
          <Tooltip
            // `toFixed(1)` escrevia `72.5%` — ponto decimal de JavaScript num
            // texto em português. `formatPercent` passa por `Intl.NumberFormat`
            // pt-BR e devolve `72,5%`.
            content={`Corrigido por dias úteis: ${formatarValor(entry.original_value)} × ${formatPercent(
              entry.business_days_multiplier * 100,
              1,
            )} de dias úteis decorridos = ${formatarValor(entry.value)}. Salvar de novo aplica a correção sobre o valor já corrigido.`}
          >
            <Badge variant="warning" className="whitespace-nowrap">
              <Wand2 aria-hidden="true" className="mr-1 h-3 w-3" />
              base {formatarValor(entry.original_value)}
            </Badge>
          </Tooltip>
        )}

        {/* **FE-132 / D-23 — o MESMO critério do servidor.** `editable` vem da
            resposta; no legado o bloqueio era exclusivamente de interface, e um
            `PUT` direto gravava em consolidação geral e em nó com filhos. */}
        {editable ? (
          <>
            <MoneyInput
              id={`valor-${template.id}`}
              aria-label={`Valor de ${template.title}`}
              value={valor}
              onChange={setValor}
              disabled={gravar.isPending}
              className="w-40"
              onBlur={() => {
                if (valor === null) return
                if (entry && Number(entry.value) === valor) return
                gravar.mutate(valor)
              }}
            />
            {/* FE-131 — excluir oferecido só onde se aplica: célula que existe,
                numa empresa, fora da consolidação. */}
            {entry && (
              <>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label={`Excluir lançamento de ${template.title}`}
                  disabled={excluir.isPending}
                  onClick={() => setConfirmandoExclusao(true)}
                >
                  <Trash2 aria-hidden="true" className="h-4 w-4" />
                </Button>

                {/* **FE-131 — pergunta antes.** Estava excluindo no clique, e a
                    lixeira fica DENTRO da célula, encostada no campo de valor
                    que o usuário acabou de editar: errar o alvo por alguns
                    pixels apagava o lançamento sem volta. O texto nomeia o
                    padrão e mostra o valor — "tem certeza?" não ajuda quem
                    errou a célula, que é o caso contra o qual isto existe. */}
                <ConfirmDialog
                  open={confirmandoExclusao}
                  onOpenChange={setConfirmandoExclusao}
                  title="Excluir este lançamento?"
                  description={
                    `O lançamento de «${template.title}» no valor de ${formatarValor(entry.value)} ` +
                    'será removido. Os totais da grade são recalculados na hora.'
                  }
                  confirmLabel="Excluir lançamento"
                  tone="destructive"
                  loading={excluir.isPending}
                  onConfirm={() => excluir.mutate()}
                />
              </>
            )}
          </>
        ) : (
          <Tooltip content={linha.value_semantics_label}>
            <span
              className={
                Number(entry?.value ?? 0) < 0
                  ? 'font-numeric tabular-nums font-semibold text-negative'
                  : 'font-numeric tabular-nums font-semibold text-foreground'
              }
            >
              {/* **FE-125 — o sinal vai no PRÓPRIO valor.** O legado exibia o
                  módulo e sinalizava só por vermelho: ambíguo, e invisível para
                  quem não distingue as cores. */}
              {formatarValor(entry?.value ?? 0)}
            </span>
          </Tooltip>
        )}
      </div>
    </div>
  )
}

function IndicadorSimples({
  rotulo,
  valor,
  icone,
}: {
  rotulo: string
  valor: string
  icone: React.ReactNode
}) {
  return (
    <Card className="flex items-center justify-between p-3">
      <span className="flex items-center gap-2 text-sm text-muted-foreground">
        {icone}
        {rotulo}
      </span>
      <span className="font-numeric tabular-nums text-lg font-semibold text-foreground">{valor}</span>
    </Card>
  )
}

/**
 * FE-125 — o card de padrão base. **O sinal fica no número**, e a cor é reforço,
 * não a única informação.
 */
function IndicadorDeSaldo({ nome, total }: { nome: string; total: string }) {
  const numero = Number(total)
  const negativo = numero < 0

  return (
    <Card className="flex items-center justify-between gap-3 p-3">
      <span className="min-w-0 truncate text-sm text-muted-foreground">{nome}</span>
      <span
        className={
          negativo
            ? 'shrink-0 font-numeric tabular-nums font-semibold text-negative'
            : 'shrink-0 font-numeric tabular-nums font-semibold text-success'
        }
      >
        {formatarValor(total)}
      </span>
    </Card>
  )
}

// --- Datas --------------------------------------------------------------
function toIso(d: Date): string {
  const mes = String(d.getMonth() + 1).padStart(2, '0')
  const dia = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${mes}-${dia}`
}

/**
 * `new Date('2026-08-14')` é meia-noite **UTC** e, em Brasília, vira 13/08 às
 * 21h — o calendário marcaria o dia anterior. Construir a data por partes evita
 * isso, e é o defeito que o `_body.js.erb` do legado contornava somando um dia
 * (`new Date(y, m, d + 1)`).
 */
function fromIso(iso: string): Date {
  const [ano, mes, dia] = iso.split('-').map(Number)
  return new Date(ano, (mes ?? 1) - 1, dia ?? 1)
}

function formatarDataLonga(d: Date): string {
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: 'long', year: 'numeric' })
}

function nomeDaEmpresa(
  empresas: { id: string; title: string }[] | undefined,
  id: string,
): string {
  return empresas?.find((c) => c.id === id)?.title ?? 'Consolidação geral'
}
