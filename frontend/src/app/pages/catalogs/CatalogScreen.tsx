import { useMemo, useState, type ReactNode } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Pencil, Trash2, Lock } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { SearchInput } from '@/components/ui/SearchInput'
import { DataTable, type Column, type SortState } from '@/components/ui/DataTable'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { Tooltip } from '@/components/ui/Tooltip'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { MobileRowActions } from '@/components/mobile/MobileRowActions'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { useMobile } from '@/hooks/useMobile'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { usePagination } from '@/hooks/usePagination'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import type { RoleSlug } from '@/app/consoleNavigation'
import {
  mensagemDoServidor,
  type CatalogPage,
  type CatalogQuery,
} from '@/lib/api/catalogs'

/**
 * O mínimo que uma linha desta tela precisa ter.
 *
 * **Widened na S4.** Era `CatalogRecord`, que exige `integration_key` e
 * `is_active` — colunas que só os catálogos globais têm. Empresa não tem chave
 * de integração nem ativação, e forkar a tela por causa de duas colunas daria
 * dois comportamentos de "próxima página" e dois jeitos de dizer "nada
 * encontrado", que é exatamente o que este molde existe para impedir. O
 * componente só lê `id` e `title` da linha; o resto sempre veio das `columns`.
 */
export interface ScreenRow {
  id: string
  title: string
}

/**
 * **O molde das cinco telas de catálogo global** (S3).
 *
 * Os cinco cadastros são o mesmo objeto com colunas diferentes: lista paginada e
 * ordenável, busca, painel lateral de criação/edição, exclusão bloqueável.
 * Escrever cinco telas à mão é a forma mais rápida de terminar com cinco
 * comportamentos de "próxima página" e cinco jeitos de dizer "nada encontrado".
 *
 * **O que o molde NÃO faz:** escrever o texto por você. Rótulo, subtítulo, vazio
 * e confirmação de exclusão são props obrigatórias, porque no legado as cinco
 * telas foram feitas por cópia e o texto de uma vazava na outra — a de
 * subsegmento tinha o placeholder "Ex: Segmento Comercial", e o toast de excluir
 * grupo dizia "O portador foi excluído". Aqui cada tela **tem que** dizer o seu
 * nome; não há default a herdar errado.
 *
 * ### As três regras que este componente garante nas cinco telas
 *
 * 1. **O vazio de busca CITA o termo** (FE-062). "Nenhum resultado para
 *    «fomento»" é diferente de "nada por aqui" — a primeira frase diz ao usuário
 *    que o filtro está ativo.
 * 2. **O critério do botão "Remover" é o critério do SERVIDOR** (FE-075, FE-077,
 *    FE-078, FE-116 / tarefa 4.4.2). O botão só some quando a mesma contagem que
 *    o servidor usa para responder 422 é maior que zero — e, quando some, o
 *    lugar dele fica ocupado por um ícone com a explicação. No legado o botão
 *    sumia por uma contagem que divergia da lista, e a exclusão passava assim
 *    mesmo.
 * 3. **A falha APARECE.** Os quatro estados (carregando / vazio / erro /
 *    conteúdo) vêm do `DataTable`; no legado o callback de erro era vazio e a
 *    tela ficava em branco, indistinguível de "não há nada".
 */
export interface CatalogTexts {
  /** Título da tela. */
  title: string
  subtitle: string
  /** Como o registro se chama, no singular: "portador", "segmento"… */
  singular: string
  /** Rótulo do botão de criar: "Novo portador". */
  createLabel: string
  /** Vazio SEM busca. */
  emptyTitle: string
  emptyDescription: string
  /** Placeholder da busca. */
  searchPlaceholder: string
  /**
   * Como o recurso entra na frase do estado de escopo de projeto — "as
   * empresas", "os fornecedores". Só as telas ESCOPADAS por projeto precisam
   * dele; catálogo global nunca recebe 409 e pode omitir.
   */
  scopeResource?: string
}

export interface CatalogApi<T> {
  list: (filtros: CatalogQuery) => Promise<CatalogPage<T>>
  create: (dados: Record<string, unknown>) => Promise<T>
  update: (id: string, dados: Record<string, unknown>) => Promise<T>
  remove: (id: string) => Promise<unknown>
}

export interface CatalogScreenProps<T extends ScreenRow> {
  /** Chave raiz do cache do React Query. */
  queryKey: string
  api: CatalogApi<T>
  texts: CatalogTexts
  /** Colunas do `DataTable`, sem a de ações — o molde acrescenta. */
  columns: Column<T>[]
  /** Ordenação inicial. A chave é a PÚBLICA que o servidor conhece. */
  defaultSort?: SortState
  /** Papéis que podem escrever. Ausente = og/admin/gerente (grupo "Cadastro"). */
  writeRoles?: RoleSlug[]
  /**
   * Quantos vínculos o registro tem. **É o mesmo número que o servidor usa**
   * para responder 422 — por isso é obrigatório, e não opcional com default 0.
   */
  usageCount: (row: T) => number
  /** Frase do bloqueio, nomeando o vínculo: "3 projetos usam este segmento". */
  usageLabel: (row: T) => string
  /** Campos do formulário. Recebe o registro em edição (`null` = criação). */
  form: (props: CatalogFormProps<T>) => ReactNode
  /** Estado inicial do formulário para criação. */
  emptyForm: () => Record<string, unknown>
  /** Do registro para o estado do formulário. */
  toForm: (row: T) => Record<string, unknown>
  /** Filtros extras no cabeçalho (o `group_id` do portador, por exemplo). */
  filtersSlot?: ReactNode
  /** Filtros extras enviados ao servidor. */
  extraQuery?: Record<string, unknown>
  onRowClick?: (row: T) => void
  /**
   * DEC-136 — roda depois do POST de criacao, com o registro ja criado.
   * Existe para o segundo passo do anexo: o logo precisa de um id para se
   * pendurar. Falhar aqui nao desfaz o cadastro.
   */
  afterCreate?: (criado: T) => Promise<void>
  /**
   * O que a **versão estreita** mostra de cada registro (FE-063): rótulo curto e
   * valor. A tabela larga tem 5 ou 6 colunas; num telefone elas viram rolagem
   * horizontal, que é o jeito mais rápido de o usuário não ler nenhuma. Por
   * isso a lista estreita é declarada, não deduzida — cada tela escolhe os dois
   * ou três campos que importam.
   */
  mobileFields?: (row: T) => { label: string; value: ReactNode }[]
}

export interface CatalogFormProps<T> {
  values: Record<string, any>
  setValue: (campo: string, valor: unknown) => void
  editing: T | null
}

const PAPEIS_DE_ESCRITA: RoleSlug[] = ['og', 'admin', 'gerente']

export function CatalogScreen<T extends ScreenRow>({
  queryKey,
  api,
  texts,
  columns,
  defaultSort = { key: 'title', direction: 'asc' },
  writeRoles = PAPEIS_DE_ESCRITA,
  usageCount,
  usageLabel,
  form,
  emptyForm,
  toForm,
  filtersSlot,
  extraQuery,
  onRowClick,
  mobileFields,
  afterCreate,
}: CatalogScreenProps<T>) {
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const papel = useRoleSlug()
  // **O Somente Leitura é NEGAÇÃO, e ela não cabe em `writeRoles`.**
  //
  // `user_is_readonly` (DEC-108) é concessão por USUÁRIO, não papel: a mesma
  // Colaboradora pode tê-la e o colega ao lado não. Enquanto este molde decidia
  // só por papel, o perfil somente-leitura recebia criar/editar/excluir em
  // **todas as 16 telas** que montam este molde (o QA reportou 14; a contagem
  // por `grep '<CatalogScreen'` dá 16) e o servidor respondia **403** no clique
  // — a tela prometia e o servidor negava, que é o defeito que esta migração
  // veio consertar no legado (D-17 / D-23 / D-34, onde o gate existia SÓ na
  // view).
  //
  // O hook é o que outras nove telas já usam (`useMyPermissions`), e é de
  // propósito que não haja um segundo mecanismo: duas fontes para "este perfil
  // pode escrever?" terminam divergindo. Ele é **cortesia de interface** — quem
  // recusa continua sendo `require_not_readonly!` no servidor.
  const somenteLeitura = useIsReadonly()
  const podeEscrever = papel !== null && writeRoles.includes(papel) && !somenteLeitura

  const busca = useDebouncedSearch()
  const paginacao = usePagination()
  const [sort, setSort] = useState<SortState | null>(defaultSort)
  const [drawerAberto, setDrawerAberto] = useState(false)
  const [editando, setEditando] = useState<T | null>(null)
  const [valores, setValores] = useState<Record<string, any>>({})
  const [confirmando, setConfirmando] = useState<T | null>(null)
  // DEC-100 — qual linha está com a folha de ações aberta, no telefone.
  const [acoesDe, setAcoesDe] = useState<string | null>(null)

  // A busca volta para a página 1 sozinha: filtrar estando na página 7 mostra
  // uma lista vazia que o usuário lê como "nada encontrado".
  const filtros: CatalogQuery = useMemo(
    () => ({
      page: paginacao.page,
      perPage: paginacao.perPage,
      q: busca.consulta || undefined,
      orderingKey: sort?.key,
      orderingStyle: sort?.direction === 'desc' ? 'down' : 'up',
      ...extraQuery,
    }),
    [paginacao.page, paginacao.perPage, busca.consulta, sort, extraQuery],
  )

  const consulta = useQuery({
    queryKey: [queryKey, filtros],
    queryFn: () => api.list(filtros),
  })

  const invalidar = () => queryClient.invalidateQueries({ queryKey: [queryKey] })

  const salvar = useMutation({
    mutationFn: async (dados: Record<string, unknown>) => {
      if (editando) return api.update(editando.id, dados)

      const criado = await api.create(dados)
      // **DEC-136 — o segundo passo da criação.** Hoje o único uso é o logo
      // (fornecedor e portador), que precisa de um id para se pendurar. Falhar
      // aqui NÃO desfaz o cadastro: quem implementa o gancho avisa o que não
      // subiu, e o registro fica.
      await afterCreate?.(criado)
      return criado
    },
    onSuccess: () => {
      notify.success(editando ? `${maiuscula(texts.singular)} atualizado.` : `${maiuscula(texts.singular)} criado.`)
      fecharDrawer()
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, `Não foi possível salvar o ${texts.singular}.`)),
  })

  const excluir = useMutation({
    mutationFn: (row: T) => api.remove(row.id),
    onSuccess: (_dado, row) => {
      // O toast fala do REGISTRO desta tela. No legado o de grupo de portadores
      // dizia "O portador foi excluído" — texto copiado da tela vizinha.
      notify.success(`${maiuscula(texts.singular)} «${row.title}» excluído.`)
      setConfirmando(null)
      invalidar()
    },
    onError: (erro) => {
      // Bloqueio de dependência é 422 **de verdade** (D-24) e a mensagem do
      // servidor NOMEIA o vínculo. Ela é mostrada como está: reescrevê-la aqui
      // seria a segunda implementação da mesma regra.
      notify.error(mensagemDoServidor(erro, `Não foi possível excluir o ${texts.singular}.`))
      setConfirmando(null)
    },
  })

  function abrirCriacao() {
    setEditando(null)
    setValores(emptyForm())
    setDrawerAberto(true)
  }

  function abrirEdicao(row: T) {
    setEditando(row)
    setValores(toForm(row))
    setDrawerAberto(true)
  }

  function fecharDrawer() {
    setDrawerAberto(false)
    setEditando(null)
  }

  const colunas: Column<T>[] = [
    ...columns,
    {
      key: 'acoes',
      header: <span className="sr-only">Ações</span>,
      align: 'right',
      width: '7rem',
      cell: (row) => {
        if (!podeEscrever) return null
        const vinculos = usageCount(row)
        return (
          <div className="flex items-center justify-end gap-1" onClick={(e) => e.stopPropagation()}>
            <Button
              variant="ghost"
              size="icon"
              aria-label={`Editar ${row.title}`}
              onClick={() => abrirEdicao(row)}
            >
              <Pencil aria-hidden="true" className="h-4 w-4" />
            </Button>

            {vinculos > 0 ? (
              // O botão some porque o servidor RECUSARIA — e o lugar dele fica
              // ocupado pela explicação, em vez de a linha simplesmente perder
              // uma ação sem dizer por quê.
              <Tooltip content={usageLabel(row)}>
                <span
                  className="inline-flex h-9 w-9 items-center justify-center text-muted-foreground"
                  aria-label={usageLabel(row)}
                >
                  <Lock aria-hidden="true" className="h-4 w-4" />
                </span>
              </Tooltip>
            ) : (
              <Button
                variant="ghost"
                size="icon"
                aria-label={`Excluir ${row.title}`}
                onClick={() => setConfirmando(row)}
              >
                <Trash2 aria-hidden="true" className="h-4 w-4" />
              </Button>
            )}
          </div>
        )
      },
    },
  ]

  const meta = consulta.data?.meta
  const buscando = busca.consulta.length > 0

  // **Os dois 409 de escopo de projeto são ESTADO, não erro** — e este molde
  // os tratava como erro. Medido abrindo o app com o usuário OG, o único sem
  // projeto corrente: `/companies`, `/providers` e `/project-guarantees`
  // pintavam a caixa VERMELHA de falha, com um botão "Tentar de novo" que não
  // podia funcionar, enquanto as outras catorze telas escopadas mostravam
  // "Escolha um projeto para continuar". Mesma resposta do servidor, duas
  // telas diferentes — e a errada manda procurar um defeito que não existe.
  const escopo = projectScopeCode(consulta.error)

  const cabecalho = (
    <PageHeader
      title={texts.title}
      subtitle={texts.subtitle}
      loading={consulta.isFetching && !consulta.isLoading}
      searchSlot={
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
          placeholder={texts.searchPlaceholder}
          aria-label={texts.searchPlaceholder}
        />
      }
      rightSlot={
        podeEscrever ? (
          <Button onClick={abrirCriacao}>
            <Plus aria-hidden="true" className="h-4 w-4" />
            {texts.createLabel}
          </Button>
        ) : undefined
      }
    />
  )

  if (escopo) {
    return (
      <div className="pb-10">
        {cabecalho}
        <ProjectScopeState code={escopo} recurso={texts.scopeResource ?? texts.title.toLowerCase()} />
      </div>
    )
  }

  return (
    <div className="pb-10">
      {cabecalho}

      {filtersSlot && <div className="mb-4 flex flex-wrap items-center gap-2">{filtersSlot}</div>}

      {/* Versão estreita (FE-063): cartão por registro, com os campos que a tela
          escolheu. Os quatro estados continuam vindo do MESMO `AsyncSection`
          da tabela — inclusive a FALHA, que é o estado que o legado não tinha. */}
      {estreito && mobileFields ? (
        <AsyncSection
          loading={consulta.isLoading}
          error={consulta.isError ? consulta.error : undefined}
          data={consulta.data?.items}
          onRetry={() => consulta.refetch()}
          loadingLabel={`Carregando ${texts.title.toLowerCase()}…`}
          emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : texts.emptyTitle}
          emptyDescription={
            buscando
              ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
              : texts.emptyDescription
          }
        >
          {(itens) => (
            <div>
              {itens.map((row) => (
                <MobileCard
                  key={row.id}
                  title={row.title}
                  onClick={onRowClick ? () => onRowClick(row) : undefined}
                  headerAction={
                    // DEC-100 — as ações da linha vão para uma FOLHA no rodapé,
                    // com alvos de 48 px na zona do polegar. Dois ícones de
                    // 36 px encostados na borda direita é o padrão que a
                    // decisão veio proibir.
                    podeEscrever ? (
                      <span onClick={(e) => e.stopPropagation()}>
                        <MobileRowActions
                          open={acoesDe === row.id}
                          onOpenChange={(aberto) => setAcoesDe(aberto ? row.id : null)}
                          title={row.title}
                          subtitle={maiuscula(texts.singular)}
                          actions={[
                            {
                              key: 'editar',
                              label: 'Editar',
                              icon: <Pencil aria-hidden="true" className="h-4 w-4" />,
                              onSelect: () => abrirEdicao(row),
                            },
                            {
                              key: 'excluir',
                              label: 'Excluir',
                              icon: <Trash2 aria-hidden="true" className="h-4 w-4" />,
                              destructive: true,
                              // O critério é o MESMO do servidor: quando há
                              // vínculo, a ação fica visível e DIZ por quê, em
                              // vez de sumir sem explicação.
                              disabledReason: usageCount(row) > 0 ? usageLabel(row) : undefined,
                              onSelect: () => setConfirmando(row),
                            },
                          ]}
                        />
                      </span>
                    ) : undefined
                  }
                >
                  <dl className="grid grid-cols-2 gap-2 text-sm">
                    {mobileFields(row).map((campo) => (
                      <div key={campo.label}>
                        <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">
                          {campo.label}
                        </dt>
                        <dd className="text-foreground">{campo.value}</dd>
                      </div>
                    ))}
                  </dl>
                </MobileCard>
              ))}
            </div>
          )}
        </AsyncSection>
      ) : (
      <div className="overflow-x-auto rounded-lg border border-border bg-card">
        <DataTable
          columns={colunas}
          data={consulta.data?.items}
          rowKey={(row) => row.id}
          loading={consulta.isLoading}
          error={consulta.isError ? consulta.error : undefined}
          onRetry={() => consulta.refetch()}
          sortMode="server"
          sort={sort}
          onSortChange={(s) => {
            setSort(s)
            paginacao.reset()
          }}
          onRowClick={onRowClick}
          caption={texts.title}
          loadingLabel={`Carregando ${texts.title.toLowerCase()}…`}
          // FE-062 — o vazio de busca CITA o termo.
          emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : texts.emptyTitle}
          emptyDescription={
            buscando
              ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
              : texts.emptyDescription
          }
          emptyAction={
            buscando ? (
              <Button variant="secondary" size="sm" onClick={busca.limpar}>
                Limpar busca
              </Button>
            ) : podeEscrever ? (
              <Button size="sm" onClick={abrirCriacao}>
                <Plus aria-hidden="true" className="h-4 w-4" />
                {texts.createLabel}
              </Button>
            ) : undefined
          }
        />
      </div>
      )}

      {/* DEC-100 — no telefone a paginação é a `MobilePagination` (dois alvos
          largos, "Página X de Y"); a `PaginationPill` com primeiro/último e
          seletor de itens por página é da largura de mesa. */}
      {meta && meta.total > 0 && estreito ? (
        <MobilePagination
          page={meta.page}
          total={meta.total}
          perPage={meta.perPage}
          loading={consulta.isFetching}
          onPageChange={paginacao.setPage}
        />
      ) : null}

      {meta && meta.total > 0 && !estreito && (
        <PaginationPill
          className="mt-4"
          page={meta.page}
          totalPages={meta.totalPages}
          perPage={meta.perPage}
          loading={consulta.isFetching}
          onPageChange={paginacao.setPage}
          onPerPageChange={paginacao.setPerPage}
        />
      )}

      <SideDrawer
        open={drawerAberto}
        onClose={fecharDrawer}
        title={editando ? `Editar ${texts.singular}` : texts.createLabel}
        footer={
          <div className="flex gap-2">
            <Button variant="secondary" className="flex-1" onClick={fecharDrawer}>
              Cancelar
            </Button>
            <Button className="flex-1" loading={salvar.isPending} onClick={() => salvar.mutate(valores)}>
              Salvar
            </Button>
          </div>
        }
      >
        {form({
          values: valores,
          setValue: (campo, valor) => setValores((atual) => ({ ...atual, [campo]: valor })),
          editing: editando,
        })}
      </SideDrawer>

      <SideDrawer
        open={confirmando !== null}
        onClose={() => setConfirmando(null)}
        title={`Excluir ${texts.singular}`}
        footer={
          <div className="flex gap-2">
            <Button variant="secondary" className="flex-1" onClick={() => setConfirmando(null)}>
              Cancelar
            </Button>
            <Button
              variant="destructive"
              className="flex-1"
              loading={excluir.isPending}
              onClick={() => confirmando && excluir.mutate(confirmando)}
            >
              Excluir
            </Button>
          </div>
        }
      >
        <p className="text-sm text-foreground">
          Excluir o {texts.singular} <strong>«{confirmando?.title}»</strong>?
        </p>
        <p className="text-sm text-muted-foreground">
          A exclusão é definitiva. Se houver algum vínculo, o servidor recusa e nada é apagado.
        </p>
      </SideDrawer>
    </div>
  )
}

function maiuscula(texto: string) {
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}
