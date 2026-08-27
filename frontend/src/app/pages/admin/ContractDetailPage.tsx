import { useParams, useNavigate } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, Download, PenLine } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { AsyncSection } from '@/components/ui/AsyncSection'
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { ContractBody } from '@/components/contracts/ContractBody'
import { contractVersionsApi } from '@/lib/api/contracts'
import { useRoleSlug } from '@/hooks/useNavItems'
import { formatDateTime } from '@/lib/utils/date'

/**
 * Histórico completo de um tipo de contrato — `/admin/contracts/:kind` (FE-340,
 * FE-341).
 *
 * Da versão mais recente à mais antiga, com os quatro estados. No legado
 * `nil.kind` transformava tipo inexistente em **500**; aqui vira "não
 * encontrado".
 *
 * **`type="multiple"` no acordeão (FE-341):** várias versões abertas ao mesmo
 * tempo é o ponto — comparar o que mudou entre a v2 e a v3 com um acordeão que
 * fecha a anterior a cada clique é comparar de memória.
 */
export function ContractDetailPage() {
  const { kind = '' } = useParams()
  const navigate = useNavigate()
  const papel = useRoleSlug()
  const podePublicar = papel === 'og' || papel === 'admin'

  const historico = useQuery({
    queryKey: ['contract-versions', 'history', kind],
    // `per_page` alto de propósito: um tipo de contrato tem unidades de
    // versões, não centenas, e paginar o histórico jurídico atrapalha mais do
    // que ajuda.
    queryFn: () => contractVersionsApi.list({ kind, perPage: 100 }),
  })

  const versoes = historico.data?.versions ?? []
  const vigente = versoes[0]

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-center gap-3">
        <Button variant="ghost" size="icon" aria-label="Voltar" onClick={() => navigate('/admin/contracts')}>
          <ArrowLeft aria-hidden="true" className="h-4 w-4" />
        </Button>
        <div className="min-w-0 flex-1">
          <h1 className="font-title text-2xl font-semibold text-foreground">
            {vigente?.kind ?? 'Contrato'}
          </h1>
          <p className="text-sm text-muted-foreground">
            {versoes.length} {versoes.length === 1 ? 'versão publicada' : 'versões publicadas'}, da mais
            recente para a mais antiga.
          </p>
        </div>
        {podePublicar && (
          <Button onClick={() => navigate(`/admin/contracts/${kind}/new`)}>
            <PenLine aria-hidden="true" className="h-4 w-4" />
            Nova versão
          </Button>
        )}
      </header>

      <AsyncSection
        loading={historico.isLoading}
        error={historico.error}
        data={historico.data}
        isEmpty={(d) => d.versions.length === 0}
        onRetry={() => historico.refetch()}
        emptyTitle="Nenhuma versão publicada"
        emptyDescription="Este tipo de contrato ainda não tem texto. Publique a primeira versão."
      >
        {() => (
          <Card>
            <CardHeader>
              <CardTitle>Histórico</CardTitle>
            </CardHeader>
            <CardContent>
              {/* FE-341 — `multiple`: comparar exige as duas abertas. */}
              <Accordion type="multiple" className="w-full">
                {versoes.map((v, indice) => (
                  <AccordionItem key={v.id} value={v.id}>
                    <AccordionTrigger>
                      <span className="flex flex-1 flex-wrap items-center gap-2 pr-3 text-left">
                        <span className="font-numeric text-sm font-semibold">v{v.version}</span>
                        {/* `as="span"`: o gatilho do acordeão É um `<button>`,
                            que só aceita conteúdo de frase. */}
                        {indice === 0 && <Badge as="span">vigente</Badge>}
                        <span className="min-w-0 flex-1 truncate text-sm font-normal">{v.title}</span>
                        <span className="text-xs font-normal text-muted-foreground">
                          {formatDateTime(v.published_at)}
                        </span>
                      </span>
                    </AccordionTrigger>
                    <AccordionContent>
                      <VersionBody id={v.id} podePublicar={podePublicar} />
                    </AccordionContent>
                  </AccordionItem>
                ))}
              </Accordion>
            </CardContent>
          </Card>
        )}
      </AsyncSection>
    </div>
  )
}

/**
 * O corpo de uma versão, buscado só quando o acordeão abre.
 *
 * Carregar os textos de todas as versões de uma vez faria a tela puxar dezenas
 * de KB de documento jurídico que ninguém pediu para ver.
 */
function VersionBody({ id, podePublicar }: { id: string; podePublicar: boolean }) {
  const versao = useQuery({
    queryKey: ['contract-versions', 'detail', id],
    queryFn: () => contractVersionsApi.get(id),
  })

  return (
    <AsyncSection
      loading={versao.isLoading}
      error={versao.error}
      data={versao.data}
      onRetry={() => versao.refetch()}
      size="inline"
      emptyTitle="Versão não encontrada"
    >
      {(v) => (
        <div className="space-y-4">
          <div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground">
            <span>Publicado por {v.creator?.name ?? 'autor não identificado'}</span>
            <span aria-hidden="true">·</span>
            <span className="font-numeric">{v.accepted_count ?? 0} aceites</span>
            {(v.divergent_count ?? 0) > 0 && (
              <Badge variant="destructive">
                <span className="font-numeric">{v.divergent_count}</span> aceites com hash divergente
              </Badge>
            )}
            {podePublicar && (v.accepted_count ?? 0) > 0 && (
              <Button
                variant="link"
                size="sm"
                onClick={() =>
                  contractVersionsApi
                    .downloadProof(v.id, `prova-aceite-${v.slug}-v${v.version}.csv`)
                    .catch(() => notify.error('Não foi possível baixar a prova de aceite.'))
                }
              >
                <Download aria-hidden="true" className="h-3.5 w-3.5" />
                Exportar prova de aceite (CSV)
              </Button>
            )}
          </div>
          <ContractBody html={v.description_html ?? ''} />
        </div>
      )}
    </AsyncSection>
  )
}

export default ContractDetailPage
