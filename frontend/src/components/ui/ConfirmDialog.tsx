import { type ReactNode } from 'react'
import { AlertTriangle } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/Button'

/**
 * **Confirmação de ação destrutiva — e ela NÃO se autodescarta** (FE-218).
 *
 * Novo primitivo compartilhado, nascido na S9 porque a exclusão em lote de
 * parcelas é o caso mais afiado dele.
 *
 * ## A regra, e o defeito que ela fecha
 *
 * No legado a confirmação de operação **irreversível** era um aviso que se
 * descartava sozinho em **6 segundos**. Quem parasse para pensar — que é
 * exatamente o que se espera de quem vai apagar parcelas — perdia a caixa e
 * precisava recomeçar. Pior: combinado com o **D-51** (a resposta invertida do
 * `batch_destroy_installments!`), recomeçar era como o usuário acabava apagando
 * parcelas a mais.
 *
 * Aqui **não há temporizador nenhum**. A caixa fica aberta até o usuário decidir,
 * e o botão de confirmar é `destructive` de verdade — não um `primary` disfarçado.
 *
 * O conteúdo é obrigatório e específico: `title`, `description` e
 * `confirmLabel` são props sem valor padrão perigoso, porque no legado o texto de
 * uma tela vazava na outra ("Excluir previsão" aparecia ao excluir pagamento).
 */
export interface ConfirmDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description: ReactNode
  /** Rótulo do botão que executa. Diga O QUE vai acontecer, não "OK". */
  confirmLabel: string
  cancelLabel?: string
  onConfirm: () => void
  /** `true` enquanto a ação roda; a caixa continua aberta. */
  loading?: boolean
  /** `false` deixa o botão de confirmar desabilitado, com o motivo em `blockedReason`. */
  canConfirm?: boolean
  blockedReason?: string
  /** Ação não destrutiva usa o botão primário em vez do vermelho. */
  tone?: 'destructive' | 'primary'
}

export function ConfirmDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel,
  cancelLabel = 'Cancelar',
  onConfirm,
  loading = false,
  canConfirm = true,
  blockedReason,
  tone = 'destructive',
}: ConfirmDialogProps) {
  return (
    <Dialog open={open} onOpenChange={(aberto) => !loading && onOpenChange(aberto)}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {tone === 'destructive' && (
              <AlertTriangle className="h-5 w-5 shrink-0 text-destructive-text" aria-hidden />
            )}
            {title}
          </DialogTitle>
          <DialogDescription asChild>
            <div className="space-y-2 text-sm text-muted-foreground">{description}</div>
          </DialogDescription>
        </DialogHeader>

        {!canConfirm && blockedReason && (
          <p role="alert" className="rounded-md border border-warning/30 bg-warning/10 px-3 py-2 text-sm text-warning">
            {blockedReason}
          </p>
        )}

        <DialogFooter>
          <Button variant="secondary" onClick={() => onOpenChange(false)} disabled={loading}>
            {cancelLabel}
          </Button>
          <Button
            variant={tone === 'destructive' ? 'destructive' : 'primary'}
            onClick={onConfirm}
            loading={loading}
            disabled={!canConfirm}
          >
            {confirmLabel}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
