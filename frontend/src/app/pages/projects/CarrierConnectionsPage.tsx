import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link2, Link2Off, Landmark } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { SearchInput } from '@/components/ui/SearchInput'
import { Checkbox } from '@/components/ui/Checkbox'
import { Badge } from '@/components/ui/Badge'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { MobileCard } from '@/components/mobile/MobileCard'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { MobileActionBar } from '@/components/mobile/MobileActionBar'
import { useMobile } from '@/hooks/useMobile'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { usePagination } from '@/hooks/usePagination'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { carrierConnectionsApi, type CarrierCandidate } from '@/lib/api/projects'

/**
 * **Conexões projeto ↔ portador** (FE-100, FE-101).
 *
 * A ponte é ÚNICA (DB-068): os portadores de uma empresa são derivados do
 * projeto. Não há tela empresa↔portador porque não há tabela empresa↔portador.
 *
 * O que muda em relação ao legado:
 *
 * - **O estado vem confirmado pelo servidor** (FE-101). O legado marcava o item
 *   otimisticamente e, num erro parcial de lote, a tela dizia "conectado" para
 *   o que não conectou. Aqui a lista é invalidada e redesenhada com a resposta.
 * - **O resultado é POR ITEM.** O lote do legado inspecionava só o último item
 *   e respondia `:ok` para o conjunto. Quando um item falha, esta tela diz
 *   quantos aplicaram, quantos não, e por quê.
 * - **Desconectar portador com garantia é recusado, com a contagem na
 *   mensagem** — em vez de deixar a garantia apontando para um portador que o
 *   formulário não oferece mais.
 * - **Não há `constantize` de parâmetro.** O legado montava a ação inteira a
 *   partir de nomes de classe vindos da query string.
 */
export function CarrierConnectionsPage() {
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const busca = useDebouncedSearch()
  const paginacao = usePagination()
  const [selecionados, setSelecionados] = useState<Set<string>>(new Set())

  const filtros = useMemo(
    () => ({ page: paginacao.page, perPage: paginacao.perPage, q: busca.consulta || undefined }),
    [paginacao.page, paginacao.perPage, busca.consulta],
  )

  const candidatos = useQuery({
    queryKey: ['carrier-connections', 'candidates', filtros],
    queryFn: () => carrierConnectionsApi.candidates(filtros),
  })

  const lote = useMutation({
    mutationFn: ({ acao, ids }: { acao: 'connect' | 'disconnect'; ids: string[] }) =>
      carrierConnectionsApi.batch(acao, ids),
    onSuccess: (resultado) => {
      // A mensagem diz o que REALMENTE aconteceu, item a item. "Conectado com
      // sucesso" para um lote em que metade falhou é como o legado mentia.
      if (resultado.failed === 0) {
        notify.success(
          resultado.action === 'connect'
            ? `${resultado.applied} portador(es) conectado(s).`
            : `${resultado.applied} portador(es) desconectado(s).`,
        )
      } else {
        const primeiraFalha = resultado.results.find((r) => r.status !== 'ok')
        notify.warning(
          `${resultado.applied} aplicado(s), ${resultado.failed} recusado(s). ${primeiraFalha?.message ?? ''}`,
        )
      }
      setSelecionados(new Set())
      queryClient.invalidateQueries({ queryKey: ['carrier-connections'] })
      // O formulário de garantia oferece exatamente estes portadores.
      queryClient.invalidateQueries({ queryKey: ['guarantee-available-carriers'] })
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível atualizar as conexões.')),
  })

  function alternar(id: string) {
    setSelecionados((atual) => {
      const proximo = new Set(atual)
      if (proximo.has(id)) proximo.delete(id)
      else proximo.add(id)
      return proximo
    })
  }

  const itens = candidatos.data?.items ?? []
  const meta = candidatos.data?.meta
  const buscando = busca.consulta.length > 0
  const marcados = itens.filter((c) => selecionados.has(c.id))
  const podeConectar = marcados.some((c) => !c.connected)
  const podeDesconectar = marcados.some((c) => c.connected)

  const acoes = (
    <div className="flex flex-wrap items-center gap-2">
      <Button
        size="sm"
        disabled={!podeConectar || lote.isPending}
        onClick={() =>
          lote.mutate({ acao: 'connect', ids: marcados.filter((c) => !c.connected).map((c) => c.id) })
        }
      >
        <Link2 aria-hidden="true" className="h-4 w-4" />
        Conectar
      </Button>
      <Button
        variant="secondary"
        size="sm"
        disabled={!podeDesconectar || lote.isPending}
        onClick={() =>
          lote.mutate({ acao: 'disconnect', ids: marcados.filter((c) => c.connected).map((c) => c.id) })
        }
      >
        <Link2Off aria-hidden="true" className="h-4 w-4" />
        Desconectar
      </Button>
    </div>
  )

  // O 409 de escopo é ESTADO, não erro — ver o comentário longo em
  // `CatalogScreen`. Esta tela é a quarta das quatro que pintavam a falha
  // vermelha quando bastava dizer "escolha um projeto".
  const escopo = projectScopeCode(candidatos.error)

  if (escopo) {
    return (
      <div className="pb-10">
        <PageHeader
          title="Portadores do projeto"
          subtitle="Quem financia este projeto. É esta lista que alimenta as garantias e os limites de risco."
        />
        <ProjectScopeState code={escopo} recurso="os portadores do projeto" />
      </div>
    )
  }

  return (
    <div className="pb-10">
      <PageHeader
        title="Portadores do projeto"
        subtitle="Quem financia este projeto. É esta lista que alimenta as garantias e os limites de risco."
        loading={candidatos.isFetching && !candidatos.isLoading}
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
            placeholder="Buscar portador por nome ou chave…"
            aria-label="Buscar portador por nome ou chave"
          />
        }
        rightSlot={estreito ? undefined : acoes}
      />

      <AsyncSection
        loading={candidatos.isLoading}
        error={candidatos.isError ? candidatos.error : undefined}
        data={itens}
        onRetry={() => candidatos.refetch()}
        loadingLabel="Carregando portadores…"
        emptyTitle={buscando ? `Nenhum resultado para «${busca.consulta}»` : 'Nenhum portador cadastrado'}
        emptyDescription={
          buscando
            ? 'Tente outro termo ou limpe a busca para ver a lista completa.'
            : 'Os portadores são um catálogo compartilhado. Cadastre-os em "Portadores", no grupo Cadastro.'
        }
      >
        {(lista) =>
          estreito ? (
            // DEC-100 — no telefone cada portador é um cartão com a caixa de
            // seleção no cabeçalho e o estado como selo. Uma tabela de quatro
            // colunas aqui vira rolagem horizontal, e a coluna de estado — que
            // é a informação — some da tela.
            <div>
              {lista.map((c) => (
                <MobileCard
                  key={c.id}
                  title={c.title}
                  onClick={() => alternar(c.id)}
                  headerAction={
                    <span onClick={(e) => e.stopPropagation()}>
                      <Checkbox
                        checked={selecionados.has(c.id)}
                        onChange={() => alternar(c.id)}
                        aria-label={`Selecionar ${c.title}`}
                      />
                    </span>
                  }
                >
                  <div className="flex flex-wrap items-center gap-2 text-sm">
                    <SeloConexao conectado={c.connected} />
                    {c.group_title && <span className="text-muted-foreground">{c.group_title}</span>}
                    {!c.is_active && <Badge variant="secondary">Inativo</Badge>}
                  </div>
                </MobileCard>
              ))}
            </div>
          ) : (
            <ul className="divide-y divide-border rounded-lg border border-border bg-card">
              {lista.map((c) => (
                <li key={c.id}>
                  <label className="flex cursor-pointer items-center gap-3 px-4 py-3 hover:bg-accent hover:text-accent-foreground">
                    <Checkbox
                      checked={selecionados.has(c.id)}
                      onChange={() => alternar(c.id)}
                      aria-label={`Selecionar ${c.title}`}
                    />
                    <Landmark aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground" />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate">{c.title}</span>
                      {c.group_title && (
                        <span className="block truncate text-xs text-muted-foreground">{c.group_title}</span>
                      )}
                    </span>
                    {!c.is_active && <Badge variant="secondary">Inativo</Badge>}
                    <SeloConexao conectado={c.connected} />
                  </label>
                </li>
              ))}
            </ul>
          )
        }
      </AsyncSection>

      {meta && meta.total > 0 && estreito ? (
        <MobilePagination
          page={meta.page}
          total={meta.total}
          perPage={meta.perPage}
          loading={candidatos.isFetching}
          onPageChange={paginacao.setPage}
        />
      ) : null}

      {meta && meta.total > 0 && !estreito && (
        <PaginationPill
          className="mt-4"
          page={meta.page}
          totalPages={meta.totalPages}
          perPage={meta.perPage}
          loading={candidatos.isFetching}
          onPageChange={paginacao.setPage}
          onPerPageChange={paginacao.setPerPage}
        />
      )}

      {/* No telefone as ações do lote descem para a barra fixa do rodapé: são
          alvos largos na zona do polegar, e só aparecem quando há seleção. */}
      {estreito && marcados.length > 0 && (
        <MobileActionBar>
          <div className="flex w-full items-center justify-between gap-3">
            <span className="font-numeric text-xs text-muted-foreground">
              {marcados.length} selecionado(s)
            </span>
            {acoes}
          </div>
        </MobileActionBar>
      )}
    </div>
  )
}

function SeloConexao({ conectado }: { conectado: boolean }) {
  return conectado ? (
    <Badge variant="success">Conectado</Badge>
  ) : (
    <Badge variant="secondary">Não conectado</Badge>
  )
}
