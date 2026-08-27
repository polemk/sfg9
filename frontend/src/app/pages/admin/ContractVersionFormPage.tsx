import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, ArrowLeft, Send } from 'lucide-react'
import { notify } from '@/lib/notify'
import RichTextEditor from '@/components/RichTextEditor'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { AsyncSection } from '@/components/ui/AsyncSection'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { ContractBody } from '@/components/contracts/ContractBody'
import { contractVersionsApi } from '@/lib/api/contracts'

/**
 * Publicar uma nova versão de contrato — `/admin/contracts/:kind/new` (FE-342).
 *
 * ## O pior comportamento da capability, e o que muda
 *
 * No legado **não existe botão salvar**. Qualquer `keyup` no editor registra a
 * ação na barra global, e **publicar é efeito colateral de digitar**: a pessoa
 * revisa um parágrafo e o sistema publica uma versão nova dos Termos de Uso —
 * que, por ser a de maior versão, passa a ser a vigente para todo mundo.
 *
 * Aqui: **um botão "Publicar", explícito**, com confirmação que informa o
 * número da nova versão e que **todos voltam a ter aceite pendente**. Sair com
 * alterações não publicadas avisa.
 *
 * ## O editor é o Slate (F-14 / DEC-63)
 *
 * `RichTextEditor.tsx` é o editor **em uso** na base. O TipTap estava declarado
 * no `package.json` **sem nenhum consumidor** e foi removido pela DEC-63. Não
 * existe um segundo editor a introduzir aqui.
 */
export function ContractVersionFormPage() {
  const { kind = '' } = useParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  const [titulo, setTitulo] = useState('')
  const [corpo, setCorpo] = useState('')
  const [sujo, setSujo] = useState(false)
  const [confirmando, setConfirmando] = useState(false)

  const prefill = useQuery({
    queryKey: ['contract-versions', 'prefill', kind],
    queryFn: () => contractVersionsApi.prefill(kind),
    retry: false,
  })

  // Pré-preenche uma vez, quando o rascunho chega. O `sujo` continua `false`:
  // abrir a tela não é ter alteração pendente.
  useEffect(() => {
    if (!prefill.data) return
    setTitulo(prefill.data.title || prefill.data.kind)
    setCorpo(prefill.data.description_html || '')
  }, [prefill.data])

  // Aviso de saída com alteração não publicada. É `beforeunload` porque é o
  // único gancho que o navegador honra numa navegação de página inteira.
  useEffect(() => {
    if (!sujo) return
    const aviso = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', aviso)
    return () => window.removeEventListener('beforeunload', aviso)
  }, [sujo])

  const publicar = useMutation({
    mutationFn: () => contractVersionsApi.create({ kind, title: titulo, description: corpo }),
    onSuccess: (contrato) => {
      setSujo(false)
      setConfirmando(false)
      notify.success(`Versão ${contrato.version} publicada.`)
      queryClient.invalidateQueries({ queryKey: ['contract-versions'] })
      queryClient.invalidateQueries({ queryKey: ['contracts'] })
      navigate(`/admin/contracts/${contrato.slug}`)
    },
    onError: (erro: any) => {
      setConfirmando(false)
      notify.error(erro?.response?.data?.message ?? 'Não foi possível publicar a versão.')
    },
  })

  const podePublicar = titulo.trim().length > 0 && corpo.replace(/<[^>]*>/g, '').trim().length > 0

  return (
    <div className="space-y-6">
      <header className="flex flex-wrap items-center gap-3">
        <Button
          variant="ghost"
          size="icon"
          aria-label="Voltar"
          onClick={() => navigate(`/admin/contracts/${kind}`)}
        >
          <ArrowLeft aria-hidden="true" className="h-4 w-4" />
        </Button>
        <div className="min-w-0 flex-1">
          <h1 className="font-title text-2xl font-semibold text-foreground">
            Nova versão {prefill.data ? `de ${prefill.data.kind}` : ''}
          </h1>
          <p className="text-sm text-muted-foreground">
            {prefill.data?.previous_version
              ? `A versão vigente é a v${prefill.data.previous_version}. Esta será a v${prefill.data.next_version}.`
              : 'Este é o primeiro documento deste tipo — o formulário abre em branco.'}
          </p>
        </div>
        <Button disabled={!podePublicar} onClick={() => setConfirmando(true)}>
          <Send aria-hidden="true" className="h-4 w-4" />
          Publicar
        </Button>
      </header>

      <AsyncSection
        loading={prefill.isLoading}
        error={prefill.error}
        data={prefill.data}
        onRetry={() => prefill.refetch()}
        emptyTitle="Tipo de contrato desconhecido"
        emptyDescription="Este tipo não está no catálogo fechado de contratos."
      >
        {(rascunho) => (
          <div className="grid gap-6 lg:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle>
                  Texto da v<span className="font-numeric">{rascunho.next_version}</span>
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-1.5">
                  <Label htmlFor="contract-title">Título</Label>
                  <Input
                    id="contract-title"
                    value={titulo}
                    onChange={(e) => {
                      setTitulo(e.target.value)
                      setSujo(true)
                    }}
                  />
                </div>

                <div className="space-y-1.5">
                  <Label>Conteúdo</Label>
                  {/* Slate. O `onChange` só marca o rascunho como alterado —
                      digitar NÃO publica (era o defeito do legado). */}
                  <RichTextEditor
                    value={corpo}
                    onChange={(v) => {
                      setCorpo(v)
                      setSujo(true)
                    }}
                    placeholder="Escreva o texto do contrato…"
                  />
                </div>

                {sujo && (
                  <p className="flex items-center gap-2 rounded-md border border-border bg-warning/10 px-3 py-2 text-xs text-foreground">
                    <AlertTriangle aria-hidden="true" className="h-3.5 w-3.5 text-warning" />
                    Há alterações não publicadas. Nada foi gravado até você clicar em Publicar.
                  </p>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>
                  {rascunho.previous_version
                    ? `Comparar com a v${rascunho.previous_version}`
                    : 'Pré-visualização'}
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    Como vai ficar
                  </p>
                  <ContractBody html={corpo} className="rounded-md border border-border p-4" />
                </div>
                {rascunho.previous_version && (
                  <div>
                    <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      Versão anterior (v{rascunho.previous_version})
                    </p>
                    <ContractBody
                      html={rascunho.description_html}
                      className="rounded-md border border-border bg-muted/40 p-4"
                    />
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        )}
      </AsyncSection>

      <Dialog open={confirmando} onOpenChange={setConfirmando}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Publicar a versão {prefill.data?.next_version} de {prefill.data?.kind}?
            </DialogTitle>
            <DialogDescription asChild>
              <div className="space-y-2 text-sm text-muted-foreground">
                <p>
                  A versão nova passa a ser a vigente imediatamente, e{' '}
                  <strong className="text-foreground">todos voltam a ter aceite pendente</strong> —
                  inclusive quem já havia aceitado a v{prefill.data?.previous_version ?? '—'}.
                </p>
                {(prefill.data?.current_accepted_count ?? 0) > 0 && (
                  <p>
                    A versão atual tem{' '}
                    <span className="font-numeric text-foreground">
                      {prefill.data?.current_accepted_count}
                    </span>{' '}
                    aceites gravados. Eles continuam válidos como prova do texto que aquelas pessoas
                    leram — a nova versão não os apaga.
                  </p>
                )}
              </div>
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setConfirmando(false)}>
              Cancelar
            </Button>
            <Button loading={publicar.isPending} onClick={() => publicar.mutate()}>
              Publicar versão {prefill.data?.next_version}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

export default ContractVersionFormPage
