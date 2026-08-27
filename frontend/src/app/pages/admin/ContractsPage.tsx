import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { ScrollText } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { SearchInput } from '@/components/ui/SearchInput'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { usePagination } from '@/hooks/usePagination'
import { useRoleSlug } from '@/hooks/useNavItems'
import { ContractCard, ContractVersionRow } from '@/components/contracts/ContractCard'
import { contractVersionsApi } from '@/lib/api/contracts'

/**
 * O console de contratos — `/admin/contracts` (FE-338).
 *
 * **A tela do legado era ÓRFÃ**: existia, não estava em nenhum menu, e o JS lia
 * `lastQuery` de um campo de busca que **não existe no HTML** — a busca nunca
 * funcionou porque o campo nunca foi renderizado. Aqui a tela tem item de menu
 * (`consoleNavigation.tsx`, grupo Admin, visível a OG e Admin) e tem **campo de
 * busca de verdade**, com debounce e os quatro estados.
 *
 * **Quem publica é o servidor que decide** (DEC-38). O papel lido aqui só
 * decide se o botão aparece; um Gerente que digitar a URL bate no `RoleRoute` e,
 * se passar, bate no 403 da matriz.
 */
export function ContractsPage() {
  const papel = useRoleSlug()
  const podePublicar = papel === 'og' || papel === 'admin'

  const busca = useDebouncedSearch()
  const { page, perPage, setPage, setPerPage } = usePagination()

  const catalogo = useQuery({
    queryKey: ['contract-versions', 'catalog'],
    queryFn: () => contractVersionsApi.catalog(),
  })

  const versoes = useQuery({
    queryKey: ['contract-versions', 'list', busca.consulta, page, perPage],
    queryFn: () => contractVersionsApi.list({ q: busca.consulta || undefined, page, perPage }),
  })

  const vigentePorTipo = useMemo(() => {
    const mapa = new Map<string, number>()
    for (const e of catalogo.data ?? []) if (e.current_version != null) mapa.set(e.kind, e.current_version)
    return mapa
  }, [catalogo.data])

  return (
    // `pt-6` porque estas três telas montam o próprio cabeçalho em vez de usar o
    // `PageHeader`, que já traz esse respiro. Sem ele o título encostava na barra
    // do telefone enquanto o resto do console tinha 24 px de folga — a diferença
    // aparece de imediato ao navegar entre uma tela e outra.
    <div className="space-y-6 pt-6">
      {/* `items-start`, não `items-center`: num 390 a descrição quebra em duas ou
          três linhas e o ícone centralizado descia para o meio do parágrafo — lido
          como um desenho solto na margem esquerda, longe do título a que pertence.
          Só aparece no telefone: no desktop a descrição cabe numa linha. */}
      <header className="flex items-start gap-3">
        <ScrollText aria-hidden="true" className="mt-1 h-6 w-6 shrink-0 text-primary" />
        <div>
          <h1 className="font-title text-2xl font-semibold text-foreground">Contratos</h1>
          <p className="text-sm text-muted-foreground">
            Termos de Uso e Política de Privacidade. Publicar uma versão nova faz todos voltarem a ter
            aceite pendente.
          </p>
        </div>
      </header>

      <AsyncSection
        loading={catalogo.isLoading}
        error={catalogo.error}
        data={catalogo.data}
        onRetry={() => catalogo.refetch()}
        emptyTitle="Nenhum tipo de contrato no catálogo"
      >
        {(entradas) => (
          <div className="grid gap-4 md:grid-cols-2">
            {entradas.map((e) => (
              <ContractCard key={e.kind} entry={e} podePublicar={podePublicar} />
            ))}
          </div>
        )}
      </AsyncSection>

      <Card>
        <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <CardTitle>Todas as versões</CardTitle>
          <SearchInput
            className="sm:max-w-xs"
            value={busca.termo}
            onValueChange={busca.setTermo}
            onClear={busca.limpar}
            loading={busca.pendente}
            placeholder="Buscar por título…"
          />
        </CardHeader>
        <CardContent className="space-y-3">
          <AsyncSection
            loading={versoes.isLoading}
            error={versoes.error}
            data={versoes.data}
            isEmpty={(d) => d.versions.length === 0}
            onRetry={() => versoes.refetch()}
            size="inline"
            emptyTitle={busca.consulta ? 'Nenhuma versão com esse título' : 'Nenhuma versão publicada'}
            emptyDescription={
              busca.consulta ? 'Tente outro termo.' : 'Publique a primeira versão pelo cartão do tipo acima.'
            }
          >
            {(pagina) => (
              <div className="space-y-2">
                {pagina.versions.map((v) => (
                  <ContractVersionRow
                    key={v.id}
                    // O destino é o HISTÓRICO do tipo, não uma rota por versão:
                    // a versão abre no acordeão de lá, e é lá que dá para
                    // comparar duas (FE-341).
                    to={`/admin/contracts/${v.slug}`}
                    version={v.version}
                    title={v.title}
                    publishedAt={v.published_at}
                    acceptedCount={v.accepted_count}
                    divergentCount={v.divergent_count}
                    isCurrent={vigentePorTipo.get(v.kind) === v.version}
                  />
                ))}
              </div>
            )}
          </AsyncSection>

          {versoes.data && versoes.data.meta.totalPages > 1 && (
            <PaginationPill
              page={versoes.data.meta.page}
              totalPages={versoes.data.meta.totalPages}
              perPage={versoes.data.meta.perPage}
              onPageChange={setPage}
              onPerPageChange={setPerPage}
              loading={versoes.isFetching}
            />
          )}
        </CardContent>
      </Card>
    </div>
  )
}

export default ContractsPage
