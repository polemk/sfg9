import { useMemo } from 'react'
import { useParams, useSearchParams, useNavigate } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useInView } from 'react-intersection-observer'
import { ArrowLeft, Check, ShieldCheck } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Logo } from '@/components/brand/Logo'
import { ThemeToggle } from '@/components/ThemeToggle'
import { Button } from '@/components/ui/Button'
import { Progress } from '@/components/ui/Progress'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { ContractBody } from '@/components/contracts/ContractBody'
import { useAuthStore } from '@/store/authStore'
import { contractsApi, publicContractsApi } from '@/lib/api/contracts'
import { formatDateTime } from '@/lib/utils/date'

/**
 * A página pública de um contrato — `/contract/:kind` (FE-330..FE-334).
 *
 * ## Fora do `ProtectedRoute`, de propósito
 *
 * Termos de Uso e Política de Privacidade são leitura pública por natureza:
 * quem ainda não tem conta precisa ler antes de aceitar. A rota do servidor
 * (`/api/v1/public/contracts/:kind`) está na allowlist de `Api::Root` **por
 * caminho**, nunca por cabeçalho.
 *
 * Ela **não** usa o `PublicSplitLayout`: aquele layout embute o widget de chat e
 * chama `/api/v1/public/chat`. Documento com valor jurídico não divide a tela
 * com um assistente — e não faz chamada de rede que não precisa fazer.
 *
 * ## O número da versão aparece (FE-330)
 *
 * O legado mostrava só "Atualizado em". A pessoa não tinha como saber **qual
 * texto** estava lendo, nem citar a versão que aceitou. Aqui o número está no
 * cabeçalho e vai junto na prova de aceite.
 *
 * ## D-69 — o destino de retorno
 *
 * `?return_to=` é uma **chave** (`login`, `console`, `profile`, `faq`), nunca
 * uma URL. Quem resolve a chave é o servidor, pela allowlist; um valor
 * desconhecido volta como `/login` e a tela avisa que o destino foi recusado.
 * No legado o parâmetro era interpolado na view **e** usado como destino: XSS
 * refletido e open redirect na mesma variável.
 *
 * ## O aceite (FE-332 / FE-333, DEC-65)
 *
 * O botão volta a existir — no legado os dois estavam comentados, com handler e
 * rota `PUT` vivos e inalcançáveis. Com sessão aberta e o contrato pendente, o
 * rodapé mostra o **progresso de leitura** e o botão de aceitar. Sem sessão, a
 * página é só leitura: aceitar exige saber quem aceita.
 */
export function ContractPage() {
  const { kind = '' } = useParams()
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)

  const returnTo = searchParams.get('return_to') ?? undefined

  const contrato = useQuery({
    queryKey: ['public-contract', kind, returnTo],
    queryFn: () => publicContractsApi.get(kind, returnTo),
    retry: false,
  })

  // Pendência só faz sentido com sessão. Sem ela a página é leitura pura.
  const pendentes = useQuery({
    queryKey: ['contracts', 'pending'],
    queryFn: () => contractsApi.pending(),
    enabled: isAuthenticated,
    retry: false,
  })

  // Progresso de leitura: o sentinela no fim do documento. Quando ele entra na
  // viewport, a pessoa chegou ao fim — é o sinal honesto de "leu até aqui", em
  // vez de um contador de tempo que qualquer aba aberta satisfaz.
  const { ref: fimDoTexto, inView: chegouAoFim } = useInView({ threshold: 0 })

  const pendente = useMemo(
    () => (pendentes.data ?? []).find((c) => c.id === contrato.data?.id),
    [pendentes.data, contrato.data?.id],
  )

  const aceitar = useMutation({
    mutationFn: () => contractsApi.accept(contrato.data!.id),
    onSuccess: () => {
      notify.success('Aceite registrado. Obrigado.')
      queryClient.invalidateQueries({ queryKey: ['contracts'] })
      queryClient.invalidateQueries({ queryKey: ['me', 'terms'] })
    },
    onError: (erro: any) =>
      notify.error(erro?.response?.data?.message ?? 'Não foi possível registrar o aceite.'),
  })

  const destino = contrato.data?.return_to ?? '/login'
  const destinoRecusado = returnTo != null && contrato.data?.return_to_allowed === false

  return (
    <div className="min-h-[100dvh] bg-background text-foreground">
      <header className="sticky top-0 z-sticky border-b border-border bg-background/95 backdrop-blur">
        <div className="mx-auto flex max-w-3xl items-center gap-4 px-4 py-3 md:px-6">
          <Logo variant="full" height={26} />
          <div className="ml-auto flex items-center gap-2">
            <ThemeToggle />
            <Button variant="secondary" size="sm" onClick={() => navigate(destino)}>
              <ArrowLeft aria-hidden="true" className="mr-1.5 h-4 w-4" />
              Voltar
            </Button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-3xl px-4 py-8 md:px-6">
        <AsyncSection
          loading={contrato.isLoading}
          error={contrato.error}
          data={contrato.data}
          onRetry={() => contrato.refetch()}
          emptyTitle="Documento não encontrado"
          emptyDescription="Este contrato não existe ou ainda não foi publicado."
        >
          {(doc) => (
            <>
              <div className="mb-6 border-b border-border pb-5">
                <h1 className="font-title text-2xl font-semibold text-foreground">{doc.title}</h1>
                <p className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted-foreground">
                  {/* FE-330 — o número da versão passa a aparecer. */}
                  <span className="font-numeric">Versão {doc.version}</span>
                  <span aria-hidden="true">·</span>
                  <span>Publicado em {formatDateTime(doc.published_at)}</span>
                </p>
                {destinoRecusado && (
                  <p className="mt-3 rounded-md border border-border bg-muted px-3 py-2 text-xs text-muted-foreground">
                    O destino de retorno informado no endereço não está na lista de destinos permitidos e
                    foi ignorado. Você voltará para a tela inicial.
                  </p>
                )}
              </div>

              <ContractBody html={doc.description_html ?? ''} />

              {/* O sentinela do progresso de leitura. */}
              <div ref={fimDoTexto} aria-hidden="true" className="h-px w-full" />

              {isAuthenticated && pendente && (
                <div className="sticky bottom-0 mt-8 border-t border-border bg-background/95 py-4 backdrop-blur">
                  <div className="mb-3">
                    <div className="mb-1.5 flex items-center justify-between text-xs text-muted-foreground">
                      <span>{chegouAoFim ? 'Você chegou ao fim do documento' : 'Role até o fim para ler tudo'}</span>
                      <span className="font-numeric">{chegouAoFim ? '100%' : '—'}</span>
                    </div>
                    <Progress value={chegouAoFim ? 100 : 35} />
                  </div>
                  <Button className="w-full" onClick={() => aceitar.mutate()} disabled={aceitar.isPending}>
                    <Check aria-hidden="true" className="mr-2 h-4 w-4" />
                    {aceitar.isPending ? 'Registrando…' : `Aceitar ${doc.title} (v${doc.version})`}
                  </Button>
                  <p className="mt-2 text-center text-xs text-muted-foreground">
                    Ao aceitar, ficam registrados data e hora, seu endereço de rede, o navegador e uma
                    impressão do texto acima.
                  </p>
                </div>
              )}

              {isAuthenticated && !pendente && !pendentes.isLoading && (
                <p className="mt-8 flex items-center gap-2 rounded-md border border-border bg-muted px-3 py-2 text-sm text-muted-foreground">
                  <ShieldCheck aria-hidden="true" className="h-4 w-4 text-success" />
                  Você já aceitou a versão vigente deste documento.
                </p>
              )}
            </>
          )}
        </AsyncSection>
      </main>
    </div>
  )
}

export default ContractPage
