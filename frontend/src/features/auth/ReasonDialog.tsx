import { useEffect, useRef, useState } from 'react'
import { ShieldAlert } from 'lucide-react'
import type { ReactNode } from 'react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'

/**
 * Diálogo de **motivo obrigatório** — usado por impersonação (DEC-18.3) e bloqueio de
 * conta (DEC-39).
 *
 * Substitui o `window.prompt` que estava no caminho de bloqueio. Não é preferência
 * estética: `prompt` é bloqueado por padrão em iframe e em navegador headless (o teste
 * de tela não conseguia exercitar o fluxo), não segue o tema — some no modo escuro — e
 * não tem como validar o tamanho mínimo antes de enviar. O servidor recusa motivo com
 * menos de 5 caracteres; a recusa precisa aparecer aqui, não como 422 seco.
 *
 * Na impersonação, o aviso de que a sessão expira é parte do contrato, não decoração:
 * sem ele a pessoa pode achar que voltou à própria conta quando ainda está vendo como
 * outra.
 */
export function ReasonDialog({
  open,
  title,
  description,
  label = 'Motivo',
  placeholder,
  confirmLabel = 'Confirmar',
  minLength = 5,
  onCancel,
  onConfirm
}: {
  open: boolean
  title: ReactNode
  description?: ReactNode
  label?: string
  placeholder?: string
  confirmLabel?: string
  minLength?: number
  onCancel: () => void
  onConfirm: (reason: string) => void
}) {
  const [reason, setReason] = useState('')
  const inputRef = useRef<HTMLInputElement | null>(null)

  useEffect(() => {
    if (open) {
      setReason('')
      const t = setTimeout(() => inputRef.current?.focus(), 50)
      return () => clearTimeout(t)
    }
  }, [open])

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onCancel() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onCancel])

  if (!open) return null

  const tooShort = reason.trim().length < minLength

  return (
    <div className="fixed inset-0 z-modal" role="dialog" aria-modal="true" aria-label={label}>
      <div className="absolute inset-0 z-modal-backdrop bg-brand-ink/60" onClick={onCancel} />
      <div className="absolute z-modal left-1/2 top-1/2 w-[90%] max-w-md -translate-x-1/2 -translate-y-1/2 rounded-lg border border-border bg-popover p-6 text-popover-foreground shadow-e3">
        <div className="mb-3 flex items-start gap-3">
          <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-warning/15 text-warning">
            <ShieldAlert className="h-5 w-5" />
          </span>
          <div>
            <h3 className="text-lg font-semibold text-foreground">{title}</h3>
            {description && <p className="mt-1 text-sm text-muted-foreground">{description}</p>}
          </div>
        </div>

        <label htmlFor="reason-dialog-input" className="mb-1.5 block text-sm font-medium text-foreground">
          {label}
        </label>
        <Input
          id="reason-dialog-input"
          ref={inputRef}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder={placeholder || 'Ex.: investigar o chamado 4711'}
          aria-describedby="reason-dialog-help"
          onKeyDown={(e) => { if (e.key === 'Enter' && !tooShort) onConfirm(reason.trim()) }}
        />
        <p id="reason-dialog-help" className="mt-1.5 text-xs text-muted-foreground">
          Mínimo de {minLength} caracteres.
        </p>

        <div className="mt-5 flex justify-end gap-2">
          <Button variant="secondary" onClick={onCancel}>Cancelar</Button>
          <Button variant="primary" disabled={tooShort} onClick={() => onConfirm(reason.trim())}>
            {confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  )
}
