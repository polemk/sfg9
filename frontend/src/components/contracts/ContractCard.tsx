import { Link, useNavigate } from 'react-router-dom'
import { FileText, PenLine, Users } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/Card'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { formatDateTime } from '@/lib/utils/date'
import type { ContractCatalogEntry } from '@/lib/api/contracts'

/**
 * O cartão de um TIPO de contrato no console (FE-339).
 *
 * **As ações aparecem conforme o papel E são recusadas pelo servidor.** No
 * legado não havia gate nenhum: quem chegasse à URL publicava uma nova versão
 * dos Termos de Uso. A DEC-38 criou o recurso `contract_versions` (OG e Admin);
 * esconder o botão aqui é conforto, não segurança — o 403 vem da matriz.
 *
 * O item "Excluir" que o legado anunciava estava **comentado**: existia no
 * menu e não fazia nada. Aqui, ou a ação existe, ou não aparece.
 */
export function ContractCard({
  entry,
  podePublicar,
}: {
  entry: ContractCatalogEntry
  podePublicar: boolean
}) {
  const navigate = useNavigate()
  const publicado = entry.current_version != null

  return (
    <Card>
      <CardContent className="flex flex-wrap items-start gap-4 p-5">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md bg-muted">
          <FileText aria-hidden="true" className="h-5 w-5 text-muted-foreground" />
        </div>

        <div className="min-w-0 flex-1">
          <h3 className="font-title text-base font-semibold text-foreground">{entry.kind}</h3>
          {/* `div`, não `p`: este bloco é um contêiner flex com um `<Badge>`
              dentro, e `<div>` dentro de `<p>` é HTML inválido — o navegador
              fecha o `<p>` sozinho e a árvore renderizada deixa de ser a que
              está escrita aqui. Foi um aviso real do React. */}
          <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
            {publicado ? (
              <>
                <Badge variant="secondary">
                  <span className="font-numeric">v{entry.current_version}</span> vigente
                </Badge>
                <span className="font-numeric">
                  {entry.versions_count} {entry.versions_count === 1 ? 'versão' : 'versões'}
                </span>
                <span className="inline-flex items-center gap-1">
                  <Users aria-hidden="true" className="h-3.5 w-3.5" />
                  <span className="font-numeric">{entry.accepted_count}</span> aceites
                </span>
              </>
            ) : (
              <span>Nenhuma versão publicada.</span>
            )}
          </div>
        </div>

        <div className="flex shrink-0 items-center gap-2">
          {/* `Button` desta base NÃO tem `asChild` — navegar é `onClick`, e o
              botão continua sendo o mesmo componente de sempre. */}
          {publicado && (
            <Button variant="secondary" size="sm" onClick={() => navigate(`/admin/contracts/${entry.slug}`)}>
              Ver histórico
            </Button>
          )}
          {podePublicar && (
            <Button size="sm" onClick={() => navigate(`/admin/contracts/${entry.slug}/new`)}>
              <PenLine aria-hidden="true" className="h-4 w-4" />
              Nova versão
            </Button>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

export function ContractVersionRow({
  version,
  publishedAt,
  title,
  acceptedCount,
  divergentCount,
  isCurrent,
  to,
}: {
  version: number
  publishedAt: string
  title: string
  acceptedCount?: number
  divergentCount?: number
  isCurrent: boolean
  to: string
}) {
  return (
    <Link
      to={to}
      className="flex flex-wrap items-center gap-3 rounded-md border border-border bg-card px-4 py-3 transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
    >
      <span className="font-numeric text-sm font-semibold text-foreground">v{version}</span>
      {isCurrent && <Badge as="span">vigente</Badge>}
      <span className="min-w-0 flex-1 truncate text-sm text-foreground">{title}</span>
      <span className="text-xs text-muted-foreground">{formatDateTime(publishedAt)}</span>
      {acceptedCount != null && (
        <span className="font-numeric text-xs text-muted-foreground">{acceptedCount} aceites</span>
      )}
      {/* Mitigação 2 da DEC-80: o número que diz que o texto mudou depois dos aceites. */}
      {divergentCount != null && divergentCount > 0 && (
        <Badge as="span" variant="destructive">
          <span className="font-numeric">{divergentCount}</span> com hash divergente
        </Badge>
      )}
    </Link>
  )
}
