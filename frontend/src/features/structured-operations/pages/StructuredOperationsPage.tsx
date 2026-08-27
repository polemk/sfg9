import { useEffect, useMemo, useState } from 'react'
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { Eye, MoreVertical, Pencil, Plus, Trash2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { DataTable, type Column, type SortState } from '@/components/ui/DataTable'
import { DateRangePicker } from '@/components/ui/DatePicker'
import { EmptyState } from '@/components/ui/States'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { SearchInput } from '@/components/ui/SearchInput'
import { Select } from '@/components/ui/Select'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { MobileRowActions } from '@/components/mobile/MobileRowActions'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { useMobile } from '@/hooks/useMobile'
import { usePagination } from '@/hooks/usePagination'
import { useSortStack } from '@/hooks/useSortStack'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { companiesApi, carrierConnectionsApi } from '@/lib/api/projects'
import { formatMoney, formatPercent } from '@/lib/utils/number'
import { CamposDoCartao } from '@/features/risk/components/CamposDoCartao'
import {
  listStructuredOperations,
  structuredOperationTypesApi,
  structuredOperationsApi,
  type StructuredOperation,
} from '../api/structuredOperations'
import { dataBr, mapaDePreFaturamento, semDataDoTipo } from '../lib/format'

/**
 * **Operações estruturadas** — a lista (`FE-280`…`FE-292`).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * `20220701125757_create_structured_operations` está entre as **24 migrations
 * que nunca subiram**: a última aplicada em produção é de 25/05/2022 e o
 * sistema rodou até 31/05/2025. **Nenhuma operação estruturada existiu em
 * produção.** O que esta tela replica vem do fonte de 2022
 * (`../sfg/app/views/pub/console/parts/structured_operations/`), não de
 * comportamento observado.
 *
 * ## O que muda em relação ao legado, e está registrado
 *
 * - **`FE-280` — os dois copy-paste saem.** O título da aba do legado era
 *   *"Safegold - Garantias do Projeto"* e o rótulo do deep-link era
 *   *"Recebívels"*: as duas strings vieram coladas de outras telas.
 * - **`FE-281` — o modo `silent`** (que congelava a lista com dados velhos em
 *   quase toda navegação) vira `keepPreviousData`: a mesma sensação de
 *   continuidade, sem tela mentindo — o cabeçalho mostra que está buscando.
 * - **`FE-282` — dois vazios distintos.** "Primeiro uso" e "busca sem
 *   resultado" eram indistinguíveis; agora o segundo **cita o termo**.
 * - **`FE-283` — a falha aparece.** O callback `failure` do proxy do legado é
 *   **vazio**: um 500 no `search` deixava a tela em carregamento eterno ou com
 *   dado velho, sem mensagem nenhuma. Não há referência visual no legado — o
 *   estado é novo por necessidade.
 * - **`FE-284` — UM campo de busca.** O legado tem **dois** `<input>` com a
 *   mesma classe no mesmo formulário; o segundo nunca fez nada.
 * - **`FE-287` — some o duplo `execute()` por clique**, que mandava duas
 *   requisições idênticas ao servidor a cada ordenação. E a chave `company`
 *   **não aparece**: saiu da allowlist (decisão **B-13**), porque não há coluna
 *   "Empresa" na tela — nem aqui, nem no legado.
 * - **`FE-288` — a paginação funciona**, porque o total agora é real. No legado
 *   **todas** as habilitações dependiam de um `totalCount` truncado.
 * - **`FE-290` — rotas reais** no lugar do `{resource, topic, section}` em
 *   memória (D-92): o botão Voltar do navegador volta.
 * - **`FE-292` — a exclusão bloqueada por recibo cai no ramo de ERRO**, com a
 *   mensagem de negócio. No legado o ternário degenerado
 *   `errors.any? ? :ok : :ok` respondia 200 e a tela recarregava a lista com a
 *   operação ainda lá, como se tivesse dado certo.
 *
 * ## O que é REPLICADO de propósito
 *
 * - **Decisão B-04 (`FE-286`):** os filtros de empresa/portador/tipo usam
 *   `.all` — **incluem inativos** — enquanto o formulário usa `.active`. Não é
 *   engano do porte: é o que permite achar operação histórica de um tipo que
 *   foi desativado depois.
 * - **`FE-289`:** tipo com pré-faturamento mostra `-` nas datas. O que muda é
 *   que **data nula deixa de quebrar a renderização** (no legado,
 *   `nil.strftime` derrubava a linha inteira).
 */
export function StructuredOperationsPage() {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const papel = useRoleSlug()
  const somenteLeitura = useIsReadonly()
  // O grupo "Gestão" é CRUD para os quatro papéis: o gate é a PARTICIPAÇÃO no
  // projeto (C1), não o papel (C3). O botão some para quem não pode e o
  // servidor recusa de novo — esconder botão nunca foi autorização.
  const podeEscrever = papel !== null && ALL_ROLES.includes(papel) && !somenteLeitura

  const busca = useDebouncedSearch()
  const paginacao = usePagination({ initialPerPage: 50 })

  // **FE-287 — a ordenação ACUMULA.** A regra vive em `useSortStack`, que nasceu
  // desta página: ela era a única das quatro listas que empilhava, e as outras
  // três (FE-159, FE-194, FE-254) guardavam uma chave só.
  const ordem = useSortStack([{ key: 'issue_date', direction: 'desc' }])

  const [filtroEmpresa, setFiltroEmpresa] = useState<string | null>(null)
  const [filtroPortador, setFiltroPortador] = useState<string | null>(null)
  const [filtroTipo, setFiltroTipo] = useState<string | null>(null)
  const [periodo, setPeriodo] = useState<{ from: Date | null; to: Date | null }>({ from: null, to: null })

  const [confirmando, setConfirmando] = useState<StructuredOperation | null>(null)
  const [acoesDe, setAcoesDe] = useState<string | null>(null)

  useEffect(() => {
    // FE-280 — no legado esta aba se chamava "Safegold - Garantias do Projeto".
    document.title = 'Safegold - Operações Estruturadas'
  }, [])

  const iso = (d: Date | null) => (d ? dataIso(d) : undefined)

  const filtros = useMemo(
    () => ({
      page: paginacao.page,
      perPage: paginacao.perPage,
      q: busca.consulta || undefined,
      companyId: filtroEmpresa ?? undefined,
      carrierId: filtroPortador ?? undefined,
      operationTypeId: filtroTipo ?? undefined,
      // FE-285 — escolhendo só a inicial, o filtro manda `from = to`: é a
      // janela de UM dia, e não uma faixa aberta que traria a base inteira. O
      // legado lia o ano final de `from` — o bug do ano morre aqui.
      from: iso(periodo.from),
      to: iso(periodo.to ?? periodo.from),
      orderingKeys: ordem.chaves,
      orderingStyles: ordem.estilos,
    }),
    [
      paginacao.page,
      paginacao.perPage,
      busca.consulta,
      filtroEmpresa,
      filtroPortador,
      filtroTipo,
      periodo,
      ordem.chaves, ordem.estilos,
    ],
  )

  const consulta = useQuery({
    queryKey: ['structured-operations', filtros],
    queryFn: () => listStructuredOperations(filtros),
    // FE-281 — o `silent` do legado, sem a tela mentindo.
    placeholderData: keepPreviousData,
  })

  const empresas = useQuery({
    queryKey: ['companies', 'para-operacoes-estruturadas'],
    queryFn: () => companiesApi.list({ perPage: 100 }),
  })

  // O legado lê `@current_project.carriers` — os portadores CONECTADOS ao
  // projeto, não o catálogo global.
  const portadores = useQuery({
    queryKey: ['project-carriers', 'para-operacoes-estruturadas'],
    queryFn: () => carrierConnectionsApi.list({ perPage: 100 }),
  })

  // **B-04 — o filtro usa `.all`, o formulário usa `.active`.** Replicado.
  const tipos = useQuery({
    queryKey: ['structured-operation-types', 'todos'],
    queryFn: () => structuredOperationTypesApi.list({ perPage: 100 }),
  })

  // FE-289 — `has_pre_faturamento` é do TIPO, e a entity da operação não o
  // expõe. O mapa vem do catálogo que a tela já carrega para o filtro.
  const preFaturamento = useMemo(() => mapaDePreFaturamento(tipos.data?.items), [tipos.data])

  const invalidar = () => queryClient.invalidateQueries({ queryKey: ['structured-operations'] })

  const excluir = useMutation({
    mutationFn: (operacao: StructuredOperation) => structuredOperationsApi.remove(operacao.id),
    onSuccess: () => {
      notify.success('Operação removida.')
      setConfirmando(null)
      invalidar()
    },
    // FE-292 — a recusa por recibo emitido chega como MENSAGEM. No legado ela
    // voltava 200 e a tela dizia que tinha dado certo.
    onError: (erro) => {
      notify.error(mensagemDoServidor(erro, 'Não foi possível remover a operação.'))
      setConfirmando(null)
    },
  })

  const escopo = projectScopeCode(consulta.error)
  if (escopo) return <ProjectScopeState code={escopo} recurso="as operações estruturadas" />

  const operacoes = consulta.data?.items ?? []
  const meta = consulta.data?.meta

  // FE-291 / FE-298 — as duas guardas, com a MESMA precedência do legado: sem
  // portador vence sem empresa. No legado a de portador estava na lista e a de
  // empresa só dentro do formulário; aqui as duas são avaliadas juntas.
  const semPortador = portadores.isSuccess && (portadores.data?.items?.length ?? 0) === 0
  const semEmpresa = empresas.isSuccess && (empresas.data?.items?.length ?? 0) === 0

  const buscando = busca.consulta.length > 0
  const filtrando =
    buscando || !!filtroEmpresa || !!filtroPortador || !!filtroTipo || !!periodo.from || !!periodo.to

  // FE-282 — os dois vazios são distintos. "Primeiro uso" fala de cadastrar; o
  // de busca CITA o termo, para o usuário saber que o filtro está ativo.
  const vazioTitulo = buscando
    ? `Nenhum resultado para «${busca.consulta}»`
    : filtrando
      ? 'Nenhuma operação para estes filtros'
      : 'Nenhuma operação estruturada neste projeto'
  const vazioDescricao = filtrando
    ? 'Tente outro termo ou limpe os filtros para ver a lista completa.'
    : 'A operação estruturada é o contrato de fomento, comissária ou intercompany do projeto. Cadastre a primeira.'

  const dataOuTraco = (operacao: StructuredOperation, valor: string | null) =>
    semDataDoTipo(operacao, preFaturamento) ? '-' : dataBr(valor)

  // **As larguras foram medidas RENDERIZANDO, não estimadas.** São **dez**
  // colunas (as mesmas do legado) e os valores usam `font-numeric` (Fira Mono),
  // que é mais larga que a de texto. Com a primeira versão a soma passava da
  // largura do container: a tabela rolava na horizontal, "Portador" ficava
  // cortado fora da tela e "Saldo" quebrava o sinal negativo em duas linhas
  // (`-` numa, `R$ 50.000,00` na outra). `tsc` não pega isso.
  //
  // "Título" é a única SEM largura: ela é a coluna elástica, e trunca com o
  // texto completo no `title` do elemento.
  const colunas: Column<StructuredOperation>[] = [
    {
      key: 'carrier',
      header: 'Portador',
      sortable: true,
      accessor: (o) => o.carrier_title,
      // `max-w` no CONTEÚDO, não `width` na coluna: a `Table` da base usa
      // `table-layout: auto`, onde a largura declarada é uma sugestão e o nome
      // longo do portador ("Cooperativa de Crédito Ipiranga") empurrava a
      // tabela para além do container — as duas últimas colunas, "Tx acordada"
      // e as AÇÕES, ficavam fora da tela. Limitar o conteúdo é o que a
      // truncagem precisa para valer. Medido renderizando.
      cell: (o) => (
        <span className="block max-w-[7rem] truncate font-medium" title={o.carrier_title ?? undefined}>
          {o.carrier_title ?? '—'}
        </span>
      ),
    },
    {
      key: 'operation_type',
      header: 'Tipo',
      sortable: true,
      accessor: (o) => o.operation_type_title,
      cell: (o) => (
        <span className="block max-w-[6.5rem] truncate" title={o.operation_type_title ?? undefined}>
          {o.operation_type_title ?? '—'}
        </span>
      ),
    },
    {
      key: 'title',
      header: 'Título',
      sortable: true,
      accessor: (o) => o.title,
      cell: (o) => (
        <span className="block max-w-[8rem] truncate" title={o.title}>
          {o.title}
        </span>
      ),
    },
    {
      key: 'contract_number',
      header: 'Contrato',
      sortable: true,
      accessor: (o) => o.contract_number,
      // FE-289 — no legado a célula ficava EM BRANCO quando não havia contrato.
      cell: (o) => <span className="font-numeric">{o.contract_number || '-'}</span>,
    },
    {
      key: 'issue_date',
      header: 'Emissão',
      sortable: true,
      align: 'center',
      width: '6rem',
      cell: (o) => <span className="font-numeric">{dataOuTraco(o, o.issue_date)}</span>,
    },
    {
      key: 'operation_value',
      header: 'Capital',
      sortable: true,
      align: 'right',
      width: '9rem',
      cellClassName: 'whitespace-nowrap',
      cell: (o) => <span className="font-numeric">{formatMoney(Number(o.operation_value))}</span>,
    },
    {
      key: 'balance',
      header: 'Saldo',
      sortable: true,
      align: 'right',
      // 9,5rem porque o valor vem NEGATIVO (DEC-01) e `-R$ 50.000,00` é um
      // caractere mais largo que o capital. Com 8,5rem o sinal caía sozinho na
      // linha de cima e virava um traço solto — visto renderizando.
      width: '9rem',
      cellClassName: 'whitespace-nowrap',
      // DEC-01 / Q-R20 — o saldo chega NEGATIVO e é exibido com o sinal.
      cell: (o) => <span className="font-numeric">{formatMoney(Number(o.balance))}</span>,
    },
    {
      key: 'due_date',
      header: 'Vencimento',
      sortable: true,
      align: 'center',
      width: '6rem',
      cell: (o) => <span className="font-numeric">{dataOuTraco(o, o.due_date)}</span>,
    },
    {
      key: 'agreed_rate',
      header: 'Tx acordada',
      sortable: true,
      align: 'right',
      width: '7rem',
      cellClassName: 'whitespace-nowrap',
      // FE-289 — DUAS casas na lista e no detalhe. No legado a lista saía crua
      // (`<%= r.agreed_rate %>%`) e o detalhe usava `sprintf('%.2f')`: o mesmo
      // número aparecia de dois jeitos em duas telas.
      cell: (o) => <span className="font-numeric">{formatPercent(Number(o.agreed_rate))}</span>,
    },
    {
      key: 'acoes',
      header: <span className="sr-only">Ações</span>,
      width: '7.5rem',
      align: 'right',
      cell: (o) => (
        <div className="flex justify-end gap-1" onClick={(e) => e.stopPropagation()}>
          <Button
            variant="ghost"
            size="icon"
            aria-label={`Ver mais sobre ${o.title}`}
            onClick={() => navigate(`/structured-operations/${o.id}`)}
          >
            <Eye aria-hidden="true" className="h-4 w-4" />
          </Button>
          {/* FE-290 — "Editar" e "Remover" só para não-somente-leitura. */}
          {podeEscrever && (
            <>
              <Button
                variant="ghost"
                size="icon"
                aria-label={`Editar ${o.title}`}
                onClick={() => navigate(`/structured-operations/${o.id}/edit`)}
              >
                <Pencil aria-hidden="true" className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                aria-label={`Remover ${o.title}`}
                onClick={() => setConfirmando(o)}
              >
                <Trash2 aria-hidden="true" className="h-4 w-4" />
              </Button>
            </>
          )}
        </div>
      ),
    },
  ]

  const cabecalho = (
    <PageHeader
      title="Operações Estruturadas"
      subtitle="Os contratos de fomento, comissária e intercompany do projeto — a base da remuneração faturada."
      loading={consulta.isFetching && !consulta.isLoading}
      searchSlot={
        // FE-284 — UM elemento. O legado tinha dois `<input>` com a mesma
        // classe no mesmo formulário; o segundo nunca fez nada.
        <SearchInput
          value={busca.termo}
          onValueChange={(v) => {
            busca.setTermo(v)
            paginacao.reset()
          }}
          onClear={() => {
            busca.limpar()
            paginacao.reset()
          }}
          loading={busca.pendente}
          placeholder="Buscar por portador ou título da operação"
          aria-label="Buscar operação estruturada"
        />
      }
      rightSlot={
        podeEscrever && !semPortador && !semEmpresa ? (
          <Button onClick={() => navigate('/structured-operations/new')}>
            <Plus aria-hidden="true" className="h-4 w-4" />
            Nova operação
          </Button>
        ) : undefined
      }
    />
  )

  // FE-291 / FE-298 — a guarda de PORTADOR tem precedência sobre a de empresa,
  // como no legado. O rótulo "Cadastrar recebível" que o legado mostrava aqui
  // era de outra tela e sai.
  if (semPortador) {
    return (
      <div className="pb-10">
        {cabecalho}
        <EmptyState
          title="Este projeto ainda não tem portador"
          description="É necessário ter um portador no projeto para que seja possível cadastrar uma operação estruturada."
          action={
            <Button variant="secondary" onClick={() => navigate('/project-carrier-connections')}>
              Vincular portador ao projeto
            </Button>
          }
        />
      </div>
    )
  }

  if (semEmpresa) {
    return (
      <div className="pb-10">
        {cabecalho}
        <EmptyState
          title="Este projeto não possui empresa"
          description="A operação estruturada pertence a uma empresa do projeto — é dela que sai o projeto dono da operação."
          action={
            <Button variant="secondary" onClick={() => navigate('/companies')}>
              Cadastrar empresa
            </Button>
          }
        />
      </div>
    )
  }

  return (
    <div className="pb-10">
      {cabecalho}

      <div className="mb-4 flex flex-col gap-3 lg:flex-row lg:items-end lg:justify-between">
        <div className="grid flex-1 gap-3 sm:grid-cols-3">
          {/* B-04 — os três filtros incluem INATIVOS. Replicado. */}
          <Select
            aria-label="Filtrar por empresa"
            placeholder="Filtrar por empresa"
            value={filtroEmpresa}
            onChange={(v) => {
              setFiltroEmpresa(v || null)
              paginacao.reset()
            }}
            options={[
              { value: '', label: 'Todas as empresas' },
              ...(empresas.data?.items ?? []).map((c) => ({ value: c.id, label: c.title })),
            ]}
          />
          <Select
            aria-label="Filtrar por portador"
            placeholder="Filtrar por portador"
            value={filtroPortador}
            onChange={(v) => {
              setFiltroPortador(v || null)
              paginacao.reset()
            }}
            options={[
              { value: '', label: 'Todos os portadores' },
              ...(portadores.data?.items ?? []).map((c) => ({
                value: c.carrier_id,
                label:
                  c.carrier_is_active === false
                    ? `${c.carrier_title ?? 'Portador'} (inativo)`
                    : (c.carrier_title ?? 'Portador'),
              })),
            ]}
          />
          <Select
            aria-label="Filtrar por tipo"
            placeholder="Filtrar por tipo"
            value={filtroTipo}
            onChange={(v) => {
              setFiltroTipo(v || null)
              paginacao.reset()
            }}
            options={[
              { value: '', label: 'Todos os tipos' },
              ...(tipos.data?.items ?? []).map((t) => ({
                value: t.id,
                // B-04 — o inativo aparece AQUI e não no formulário.
                label: t.is_active ? t.title : `${t.title} (inativo)`,
              })),
            ]}
          />
        </div>
        <DateRangePicker
          from={periodo.from}
          to={periodo.to}
          onChange={(r) => {
            setPeriodo(r)
            paginacao.reset()
          }}
          labelFrom="Período de"
          labelTo="até"
        />
      </div>

      {estreito ? (
        <AsyncSection
          loading={consulta.isLoading}
          error={consulta.isError ? consulta.error : undefined}
          data={operacoes}
          onRetry={() => consulta.refetch()}
          loadingLabel="Carregando operações…"
          emptyTitle={vazioTitulo}
          emptyDescription={vazioDescricao}
        >
          {(itens) => (
            <div>
              {itens.map((o) => (
                <MobileCard
                  key={o.id}
                  title={o.title || o.carrier_title || 'Operação'}
                  subtitle={o.operation_type_title ?? undefined}
                  status={o.is_ended ? 'Encerrada' : undefined}
                  statusTone={o.is_ended ? 'neutral' : undefined}
                  onClick={() => navigate(`/structured-operations/${o.id}`)}
                  headerAction={
                    <span onClick={(e) => e.stopPropagation()}>
                      <Button
                        variant="ghost"
                        size="icon"
                        aria-label={`Ações de ${o.title}`}
                        onClick={() => setAcoesDe(o.id)}
                      >
                        <MoreVertical aria-hidden="true" className="h-4 w-4" />
                      </Button>
                    </span>
                  }
                >
                  <CamposDoCartao
                    itens={[
                      ['Capital', formatMoney(Number(o.operation_value))],
                      ['Saldo', formatMoney(Number(o.balance))],
                      ['Contrato', o.contract_number || '-'],
                      ['Emissão', dataOuTraco(o, o.issue_date)],
                      ['Vencimento', dataOuTraco(o, o.due_date)],
                      ['Tx acordada', formatPercent(Number(o.agreed_rate))],
                    ]}
                  />
                </MobileCard>
              ))}
            </div>
          )}
        </AsyncSection>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border bg-card">
          <DataTable<StructuredOperation>
            columns={colunas}
            data={operacoes}
            rowKey={(o) => o.id}
            loading={consulta.isLoading}
            // FE-283 — o erro APARECE. No legado o `failure` do proxy era vazio.
            error={consulta.isError ? consulta.error : undefined}
            onRetry={() => consulta.refetch()}
            sortMode="server"
            sort={ordem.primeira}
            onSortChange={(s, chave) => {
              ordem.trocar(s, chave)
              paginacao.reset()
            }}
            onRowClick={(o) => navigate(`/structured-operations/${o.id}`)}
            caption="Operações estruturadas do projeto"
            loadingLabel="Carregando operações…"
            emptyTitle={vazioTitulo}
            emptyDescription={vazioDescricao}
          />
        </div>
      )}

      {meta && meta.total > 0 && (
        <div className="mt-4">
          {estreito ? (
            <MobilePagination
              page={meta.page}
              total={meta.total}
              perPage={meta.perPage}
              onPageChange={paginacao.setPage}
              loading={consulta.isFetching}
            />
          ) : (
            <PaginationPill
              page={meta.page}
              totalPages={meta.totalPages}
              perPage={meta.perPage}
              onPageChange={paginacao.setPage}
              onPerPageChange={paginacao.setPerPage}
              loading={consulta.isFetching}
            />
          )}
        </div>
      )}

      {/* DEC-100 — no telefone as ações da linha vão para a folha do rodapé. */}
      {acoesDe &&
        (() => {
          const alvo = operacoes.find((o) => o.id === acoesDe)
          if (!alvo) return null
          return (
            <MobileRowActions
              open
              onOpenChange={(aberto) => !aberto && setAcoesDe(null)}
              title={alvo.title || 'Operação'}
              subtitle={alvo.operation_type_title ?? undefined}
              actions={[
                {
                  key: 'ver',
                  label: 'Ver mais',
                  icon: <Eye aria-hidden="true" className="h-4 w-4" />,
                  onSelect: () => navigate(`/structured-operations/${alvo.id}`),
                },
                ...(podeEscrever
                  ? [
                      {
                        key: 'editar',
                        label: 'Editar',
                        icon: <Pencil aria-hidden="true" className="h-4 w-4" />,
                        onSelect: () => navigate(`/structured-operations/${alvo.id}/edit`),
                      },
                      {
                        key: 'remover',
                        label: 'Remover',
                        icon: <Trash2 aria-hidden="true" className="h-4 w-4" />,
                        destructive: true,
                        onSelect: () => setConfirmando(alvo),
                      },
                    ]
                  : []),
              ]}
            />
          )
        })()}

      <ConfirmDialog
        open={confirmando !== null}
        onOpenChange={(aberto) => !aberto && setConfirmando(null)}
        // FE-292 — no legado o modal se chamava "Excluir renegociação": rótulo
        // de outro módulo, copiado junto com a parcial.
        title="Excluir operação estruturada"
        description={
          confirmando
            ? `A operação «${confirmando.title}» será removida. A operação não pode ser desfeita. Tem certeza?`
            : ''
        }
        confirmLabel="Excluir"
        tone="destructive"
        loading={excluir.isPending}
        onConfirm={() => confirmando && excluir.mutate(confirmando)}
      />
    </div>
  )
}

/** `Date` → `YYYY-MM-DD` no fuso local (o `toISOString` volta um dia em UTC−3). */
function dataIso(d: Date): string {
  const mes = String(d.getMonth() + 1).padStart(2, '0')
  const dia = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${mes}-${dia}`
}
