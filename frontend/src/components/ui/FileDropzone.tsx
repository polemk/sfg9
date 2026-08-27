import { useRef, useState } from 'react'
import { UploadCloud } from 'lucide-react'
import { notify } from '@/lib/notify'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/Button'
import { validatePick, isLocked, LIMIT_EXCEEDED_TITLE } from '@/features/attachments/validation'
import type { AttachmentLimit } from '@/features/attachments/types'

/**
 * S9 / FE-210 — **arrastar e soltar, com o limite comunicado de verdade**.
 *
 * Novo primitivo compartilhado. Ele **não reimplementa a validação**: chama
 * `validatePick` de `features/attachments/validation.ts`, que é a mesma função
 * que o `AttachmentUploader` (S13) usa. Duas validações de anexo no front seriam
 * duas mensagens diferentes para o mesmo arquivo recusado.
 *
 * **O limite entra por prop, e vem do servidor.** Nenhum número está escrito
 * aqui: quem chama passa o `limit` que veio de
 * `GET /api/v1/renegotiations/:id/attachments/limits`. É a correção do **D-50** —
 * no legado o JavaScript da tela lia `.lesson_attachment_content_wrapper` (um
 * seletor **de outro produto**), comparava com `NaN`, e o indicador de bloqueio
 * era escrito no HTML e **nunca lido**.
 *
 * E, como sempre: **isto é conveniência**. O servidor aplica o limite de novo, e
 * é ele que manda.
 */
export interface FileDropzoneProps {
  /** Limite vindo do servidor. `undefined` = ainda carregando; não se inventa um. */
  limit: AttachmentLimit | undefined
  /** Quantos arquivos o registro JÁ tem — o teto conta o total, não o lote. */
  attachedCount: number
  onPick: (files: File[]) => void
  uploading?: boolean
  label?: string
  hint?: string
  className?: string
  /** Desabilita por motivo externo (somente leitura, por exemplo). */
  disabled?: boolean
  disabledReason?: string
}

export function FileDropzone({
  limit,
  attachedCount,
  onPick,
  uploading = false,
  label = 'Arraste os arquivos ou clique para escolher',
  hint,
  className,
  disabled = false,
  disabledReason,
}: FileDropzoneProps) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [arrastando, setArrastando] = useState(false)
  const bloqueado = disabled || isLocked(attachedCount, limit)

  function receber(files: File[]) {
    if (files.length === 0) return
    const { accepted, errors } = validatePick(files, attachedCount, limit)
    errors.forEach((mensagem) => notify.error(mensagem, { description: LIMIT_EXCEEDED_TITLE }))
    if (accepted.length > 0) onPick(accepted)
  }

  const restantes = limit?.maxFiles != null ? Math.max(0, limit.maxFiles - attachedCount) : null

  return (
    <div className={cn('flex flex-col gap-2', className)}>
      <input
        ref={inputRef}
        type="file"
        className="hidden"
        multiple={(limit?.maxFiles ?? 1) > 1}
        accept={limit?.contentTypes?.length ? limit.contentTypes.map((e) => `.${e}`).join(',') : undefined}
        onChange={(evento) => {
          const files = Array.from(evento.target.files ?? [])
          // Zera SEMPRE: sem isto, escolher o mesmo arquivo duas vezes seguidas
          // não dispara `change` e a tela parece travada.
          evento.target.value = ''
          receber(files)
        }}
        data-testid="file-dropzone-input"
      />

      <div
        role="button"
        tabIndex={bloqueado ? -1 : 0}
        aria-disabled={bloqueado}
        data-locked={bloqueado}
        onClick={() => !bloqueado && inputRef.current?.click()}
        onKeyDown={(evento) => {
          if (bloqueado) return
          if (evento.key === 'Enter' || evento.key === ' ') {
            evento.preventDefault()
            inputRef.current?.click()
          }
        }}
        onDragOver={(evento) => {
          evento.preventDefault()
          if (!bloqueado) setArrastando(true)
        }}
        onDragLeave={() => setArrastando(false)}
        onDrop={(evento) => {
          evento.preventDefault()
          setArrastando(false)
          if (bloqueado) return
          receber(Array.from(evento.dataTransfer.files ?? []))
        }}
        className={cn(
          'flex min-h-[7rem] cursor-pointer flex-col items-center justify-center gap-2 rounded-lg border border-dashed border-border bg-muted/40 px-4 py-6 text-center transition-colors',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
          arrastando && 'border-primary bg-accent',
          bloqueado && 'cursor-not-allowed opacity-60',
        )}
      >
        <UploadCloud aria-hidden className="h-6 w-6 text-muted-foreground" />
        <p className="text-sm font-medium text-foreground">{label}</p>

        {/* **O limite é comunicado de verdade** — e o número vem do servidor. */}
        {limit && (
          <p className="text-xs text-muted-foreground">
            {limit.maxFiles != null
              ? `Até ${limit.maxFiles} arquivos, ${limit.maxSizeMegabytes} MB cada.`
              : `Até ${limit.maxSizeMegabytes} MB por arquivo.`}
            {restantes !== null && restantes > 0 && ` Faltam ${restantes}.`}
          </p>
        )}

        {bloqueado && (
          <p className="text-xs font-medium text-warning">
            {disabledReason ??
              (limit?.maxFiles != null
                ? `Limite de ${limit.maxFiles} arquivos atingido. Remova um para enviar outro.`
                : 'Envio indisponível.')}
          </p>
        )}

        {hint && !bloqueado && <p className="text-xs text-muted-foreground">{hint}</p>}
      </div>

      <Button
        type="button"
        variant="secondary"
        size="sm"
        className="self-start"
        disabled={bloqueado}
        loading={uploading}
        onClick={() => inputRef.current?.click()}
      >
        Escolher arquivos
      </Button>
    </div>
  )
}
