import { useRef } from 'react'
import { Paperclip } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Button } from '@/components/ui/Button'
import { useAttachmentLimit } from './useAttachments'
import { isLocked, validatePick, LIMIT_EXCEEDED_TITLE } from './validation'

interface Props {
  /** Chave do catálogo: `model` + `name` de `config/attachments.yml`. */
  model: string
  name: string
  /** Quantos arquivos o registro JÁ tem — o teto conta o total, não o lote. */
  attachedCount: number
  onPick: (files: File[]) => void
  uploading?: boolean
  label?: string
}

/**
 * Seletor de arquivos do motor único de anexos — FE-484.
 *
 * Três coisas que ele faz e o legado não fazia:
 *
 *  1. **Os números vêm do servidor** (`useAttachmentLimit`), não de uma constante
 *     interpolada na view. Trocar o limite é trocar uma linha de
 *     `config/attachments.yml`, sem build de front.
 *  2. **O limite real é o do servidor.** Esta validação é conveniência: ela evita
 *     o upload inútil de 40 MB, e o backend recusa de novo se alguém passar por
 *     cima dela. No legado esta era a ÚNICA validação que existia.
 *  3. **Os textos são os do legado, palavra por palavra** — quem usa o sistema
 *     hoje vê a mesma mensagem, com o mesmo título "Limite excedido".
 *
 * O `data-locked` do wrapper é o mesmo atributo do legado
 * (`renegotiation_attachment_form_wrapper`), preservado porque é o gancho de
 * estilo que a tela usa para esmaecer a área quando o teto foi atingido.
 */
export function AttachmentUploader({
  model,
  name,
  attachedCount,
  onPick,
  uploading = false,
  label = 'Anexar arquivo',
}: Props) {
  const inputRef = useRef<HTMLInputElement>(null)
  const limit = useAttachmentLimit(model, name)
  const locked = isLocked(attachedCount, limit)

  const handleChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(event.target.files ?? [])
    // Zera o input SEMPRE: sem isto, escolher o mesmo arquivo duas vezes seguidas
    // não dispara `change` e a tela parece travada.
    event.target.value = ''
    if (files.length === 0) return

    const { accepted, errors } = validatePick(files, attachedCount, limit)
    errors.forEach((message) => notify.error(message, { description: LIMIT_EXCEEDED_TITLE }))
    if (accepted.length > 0) onPick(accepted)
  }

  const accept = limit?.contentTypes?.length
    ? limit.contentTypes.map((ext) => `.${ext}`).join(',')
    : undefined

  return (
    <div
      className="renegotiation_attachment_form_wrapper flex flex-col gap-2"
      data-locked={locked}
    >
      <input
        ref={inputRef}
        type="file"
        className="hidden"
        multiple={limit?.multiple ?? false}
        accept={accept}
        onChange={handleChange}
        data-testid={`attachment-input-${model}-${name}`}
      />
      <Button
        type="button"
        variant="secondary"
        disabled={locked}
        loading={uploading}
        onClick={() => inputRef.current?.click()}
      >
        <Paperclip className="mr-2 h-4 w-4" aria-hidden />
        {label}
      </Button>
      {limit && (
        <p className="text-xs text-muted-foreground">
          {limit.maxFiles != null
            ? `Até ${limit.maxFiles} arquivos, ${limit.maxSizeMegabytes} MB cada.`
            : `Até ${limit.maxSizeMegabytes} MB.`}
          {locked && ' Limite atingido.'}
        </p>
      )}
    </div>
  )
}
