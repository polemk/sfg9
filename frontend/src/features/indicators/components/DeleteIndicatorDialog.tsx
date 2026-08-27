import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, Loader2 } from 'lucide-react'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { ErrorState } from '@/components/ui/States'
import { indicatorsApi } from '@/lib/api/indicators'

/**
 * `FE-315` / `FE-321` — **a confirmação que fecha o D-66 na copy**.
 *
 * ## O defeito que ela substitui
 *
 * No legado a exclusão de um indicador dispara
 * `has_many :entries, dependent: :delete_all`: **toda a série histórica some**,
 * sem callback, sem backup e sem trilha. A confirmação da tela de catálogo dizia
 * apenas *"A operação não pode ser desfeita"* — **sem mencionar os
 * lançamentos**. E na tela de indicadores específicos (`FE-321`) **não havia
 * diálogo nenhum**: clicar em "Excluir" apagava o indicador e os lançamentos
 * direto.
 *
 * ## O que ela faz
 *
 * 1. **Pergunta ao servidor, ANTES de qualquer escrita**, quantos lançamentos e
 *    quais projetos o indicador tem (`GET :id/deletion_impact`). O número é o
 *    mesmo que o servidor usa — não uma contagem própria da tela, que divergiria.
 * 2. **Diz o que acontece de verdade**: a exclusão agora é lógica, e os
 *    lançamentos **ficam**. Prometer menos do que se faz também é mentir para o
 *    usuário — quem lê "vai apagar tudo" e não quer perder o histórico desiste
 *    de uma operação segura.
 * 3. **Não some com a ação quando há vínculo.** O indicador com histórico é
 *    exatamente o caso em que a exclusão lógica existe.
 */
export interface DeleteIndicatorDialogProps {
  /** `null` = fechado. */
  indicadorId: string | null
  titulo: string
  excluindo: boolean
  onCancel: () => void
  onConfirm: () => void
}

export function DeleteIndicatorDialog({
  indicadorId,
  titulo,
  excluindo,
  onCancel,
  onConfirm,
}: DeleteIndicatorDialogProps) {
  const impacto = useQuery({
    queryKey: ['indicator-deletion-impact', indicadorId],
    queryFn: () => indicatorsApi.deletionImpact(indicadorId as string),
    // Só pergunta quando o diálogo abre: é leitura para decidir, não para listar.
    enabled: Boolean(indicadorId),
  })

  const dados = impacto.data
  const lancamentos = dados?.entries_count ?? 0
  const projetos = dados?.projects ?? []

  return (
    <SideDrawer
      open={indicadorId !== null}
      onClose={onCancel}
      title="Excluir indicador"
      footer={
        <div className="flex gap-2">
          <Button variant="secondary" className="flex-1" onClick={onCancel}>
            Cancelar
          </Button>
          <Button
            variant="destructive"
            className="flex-1"
            loading={excluindo}
            // Confirmar antes de saber o impacto é o defeito que este diálogo
            // veio consertar.
            disabled={impacto.isLoading || impacto.isError}
            onClick={onConfirm}
          >
            Excluir
          </Button>
        </div>
      }
    >
      <p className="text-sm text-foreground">
        Excluir o indicador <strong>«{titulo}»</strong>?
      </p>

      {impacto.isLoading && (
        <p className="flex items-center gap-2 text-sm text-muted-foreground">
          <Loader2 aria-hidden="true" className="h-4 w-4 animate-spin" />
          Conferindo o que será afetado…
        </p>
      )}

      {impacto.isError && (
        <ErrorState
          title="Não consegui conferir o impacto"
          description="Sem saber quantos lançamentos existem, a exclusão fica bloqueada."
          onRetry={() => impacto.refetch()}
        />
      )}

      {dados && (
        <div className="space-y-3 rounded-md border border-border bg-muted/40 p-3">
          <div className="flex items-start gap-2">
            <AlertTriangle aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
            <div className="space-y-2 text-sm">
              <p className="text-foreground">
                {lancamentos === 0 ? (
                  <>Este indicador <strong>não tem nenhum lançamento</strong>.</>
                ) : (
                  <>
                    Este indicador tem{' '}
                    <strong className="font-numeric tabular-nums">{lancamentos}</strong>{' '}
                    {lancamentos === 1 ? 'lançamento' : 'lançamentos'} no histórico.
                  </>
                )}
              </p>

              {projetos.length > 0 && (
                <p className="text-muted-foreground">
                  Ele aparece {projetos.length === 1 ? 'no projeto' : 'nos projetos'}{' '}
                  <strong className="text-foreground">
                    {projetos.map((p) => p.name).join(', ')}
                  </strong>{' '}
                  e vai sumir {projetos.length === 1 ? 'da grade mensal dele' : 'das grades mensais deles'}.
                </p>
              )}

              {/* O ponto que o legado não tinha como dizer, porque não era verdade. */}
              <p className="text-muted-foreground">
                {lancamentos === 0
                  ? 'Nada de histórico será perdido.'
                  : 'Os lançamentos históricos NÃO são apagados — eles continuam no banco e voltam se o indicador for restaurado.'}
              </p>
            </div>
          </div>
        </div>
      )}
    </SideDrawer>
  )
}
