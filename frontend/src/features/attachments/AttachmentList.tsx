import { useState } from 'react'
import { FileText, Download, X } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Button } from '@/components/ui/Button'
import { openAttachment } from './useAttachments'
import { formatAmount } from '@/lib/utils/number'
import type { Attachment } from './types'

interface Props {
  attachments: Attachment[]
  /** Ausente = lista somente leitura (o usuário não pode remover). */
  onRemove?: (id: string) => void
  removingId?: string | null
  emptyLabel?: string
}

function humanSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  // `toFixed(1)` dava `2.5 MB` — ponto decimal em tela portuguesa.
  return `${formatAmount(bytes / (1024 * 1024), 1)} MB`
}

/**
 * Lista de anexos já enviados.
 *
 * **Não existe `<a href>` para o arquivo.** O download pede a URL assinada no
 * clique (`openAttachment`), porque a URL tem prazo de 5 minutos e o servidor
 * confere a autorização nesse mesmo instante. No legado o link era
 * `/system/:attachment/:id/...` — estático, adivinhável e sem autenticação (D-82).
 */
export function AttachmentList({ attachments, onRemove, removingId, emptyLabel }: Props) {
  const [openingId, setOpeningId] = useState<string | null>(null)

  const handleOpen = async (attachment: Attachment) => {
    setOpeningId(attachment.id)
    try {
      await openAttachment(attachment.id)
    } catch {
      notify.error('Não foi possível abrir o anexo. Recarregue a página e tente de novo.')
    } finally {
      setOpeningId(null)
    }
  }

  if (attachments.length === 0) {
    return (
      <p className="text-sm text-muted-foreground">
        {emptyLabel ?? 'Nenhum arquivo anexado.'}
      </p>
    )
  }

  return (
    <ul className="flex flex-col gap-2">
      {attachments.map((attachment) => (
        <li
          key={attachment.id}
          className="flex items-center gap-3 rounded-md border border-border bg-card px-3 py-2"
        >
          <FileText className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
          <span className="min-w-0 flex-1 truncate text-sm" title={attachment.filename}>
            {attachment.filename}
          </span>
          <span className="shrink-0 text-xs text-muted-foreground">
            {humanSize(attachment.byteSize)}
          </span>
          <Button
            variant="ghost"
            size="icon"
            aria-label={`Baixar ${attachment.filename}`}
            loading={openingId === attachment.id}
            onClick={() => handleOpen(attachment)}
          >
            <Download className="h-4 w-4" aria-hidden />
          </Button>
          {onRemove && (
            <Button
              variant="ghost"
              size="icon"
              aria-label={`Remover ${attachment.filename}`}
              loading={removingId === attachment.id}
              onClick={() => onRemove(attachment.id)}
            >
              <X className="h-4 w-4" aria-hidden />
            </Button>
          )}
        </li>
      ))}
    </ul>
  )
}
