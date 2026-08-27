import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { FileSignature } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Button } from '@/components/ui/Button'
import { Badge } from '@/components/ui/Badge'
import { Checkbox } from '@/components/ui/Checkbox'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { contractsApi } from '@/lib/api/contracts'
import { formatDateTime } from '@/lib/utils/date'

/**
 * "Meus contratos" no perfil — `/profile` (FE-336).
 *
 * ## A caixa nasce DESMARCADA
 *
 * No legado a caixa de aceite só aparecia se o usuário **não tinha registro de
 * Termos de Uso**, vinha **pré-marcada**, e `contract[agreed_by_user]` **não era
 * lido por controller nenhum**. Ou seja: a interface afirmava um consentimento
 * que o servidor nunca via — três defeitos em cima do mesmo campo. Aqui a caixa
 * nasce desmarcada, ela habilita o botão, e quem grava é o servidor, com prova.
 *
 * ## O histórico é visível, e distingue os dois tipos de aceite
 *
 * DEC-66: os aceites que vieram da base antiga entram marcados
 * `implicit_legacy` — a data original é preservada como histórico, e eles **não**
 * satisfazem a pendência. Mostrar isso é o que faz o pedido de reaceite parecer
 * razoável em vez de arbitrário: a pessoa vê "seu aceite anterior foi carimbado
 * pelo sistema, não dado por você".
 */
export function MyTermsSection() {
  const queryClient = useQueryClient()
  const [concordo, setConcordo] = useState(false)

  const terms = useQuery({ queryKey: ['me', 'terms'], queryFn: () => contractsApi.myTerms() })

  const aceitar = useMutation({
    mutationFn: () => contractsApi.acceptAllPending(),
    onSuccess: () => {
      setConcordo(false)
      notify.success('Aceite registrado.')
      queryClient.invalidateQueries({ queryKey: ['me', 'terms'] })
      queryClient.invalidateQueries({ queryKey: ['contracts'] })
    },
    onError: (erro: any) =>
      notify.error(erro?.response?.data?.message ?? 'Não foi possível registrar o aceite.'),
  })

  return (
    <div className="glass-panel rounded-lg p-6">
      <div className="mb-4 flex items-center gap-2">
        <div className="flex h-6 w-6 items-center justify-center rounded-md bg-muted">
          <FileSignature aria-hidden="true" className="h-4 w-4" />
        </div>
        <p className="font-medium">Contratos e aceites</p>
      </div>

      <AsyncSection
        loading={terms.isLoading}
        error={terms.error}
        data={terms.data}
        isEmpty={(d) => d.pending.length === 0 && d.accepted.length === 0}
        onRetry={() => terms.refetch()}
        size="inline"
        emptyTitle="Nenhum contrato publicado"
        emptyDescription="Quando os Termos de Uso forem publicados, eles aparecem aqui."
      >
        {(dados) => (
          <div className="space-y-5">
            {dados.pending.length > 0 && (
              <div className="space-y-3 rounded-md border border-border bg-warning/10 p-4">
                <p className="text-sm font-medium text-foreground">Aguardando seu aceite</p>
                <ul className="space-y-1 text-sm">
                  {dados.pending.map((c) => (
                    <li key={c.id}>
                      <Link
                        to={`/contract/${c.slug}`}
                        className="text-primary underline underline-offset-2 hover:no-underline"
                      >
                        {c.title}
                      </Link>{' '}
                      <span className="font-numeric text-muted-foreground">v{c.version}</span>
                      {c.overdue && (
                        <Badge variant="warning" className="ml-2">
                          prazo vencido
                        </Badge>
                      )}
                    </li>
                  ))}
                </ul>

                {/* DESMARCADA por padrão. E ela habilita o botão de verdade —
                    no legado nenhum controller lia o campo. */}
                <Checkbox
                  checked={concordo}
                  onChange={(e) => setConcordo(e.target.checked)}
                  label="Li e concordo com os documentos acima."
                />

                <Button
                  size="sm"
                  disabled={!concordo}
                  loading={aceitar.isPending}
                  onClick={() => aceitar.mutate()}
                >
                  Registrar meu aceite
                </Button>
              </div>
            )}

            <div>
              <p className="mb-2 text-sm font-medium text-foreground">Histórico</p>
              {dados.accepted.length === 0 ? (
                <p className="text-sm text-muted-foreground">Você ainda não aceitou nenhum documento.</p>
              ) : (
                <ul className="space-y-2">
                  {dados.accepted.map((d) => (
                    <li
                      key={d.id}
                      className="flex flex-wrap items-center gap-2 rounded-md border border-border px-3 py-2 text-sm"
                    >
                      <span className="min-w-0 flex-1 truncate text-foreground">{d.kind}</span>
                      <span className="font-numeric text-xs text-muted-foreground">v{d.version}</span>
                      <span className="text-xs text-muted-foreground">
                        {formatDateTime(d.accepted_at)}
                      </span>
                      {d.source === 'implicit_legacy' ? (
                        <Badge variant="secondary" title="Registro herdado do sistema antigo, sem interação sua">
                          carimbado pelo sistema antigo
                        </Badge>
                      ) : (
                        <Badge variant="success">aceite seu</Badge>
                      )}
                    </li>
                  ))}
                </ul>
              )}
            </div>
          </div>
        )}
      </AsyncSection>
    </div>
  )
}
