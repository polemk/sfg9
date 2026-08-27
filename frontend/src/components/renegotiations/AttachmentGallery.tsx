import { useEffect, useState } from 'react'
import { Download, FileText, ImageOff, Pencil, Trash2, Check, X } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Tooltip } from '@/components/ui/Tooltip'
import { attachmentsApi } from '@/features/attachments'
import { formatDate } from '@/lib/utils/date'
import { formatAmount } from '@/lib/utils/number'
import type { RenegotiationAttachment } from '@/lib/api/renegotiations'

/**
 * **A galeria de anexos** (FE-208, FE-211, FE-212).
 *
 * ## Miniatura de VARIANTE, nunca do arquivo original
 *
 * O legado renderizava o arquivo inteiro dentro de um `<img>` de 80 px — e ainda
 * chamava **dois processos externos por imagem, a cada renderização**, só para
 * descobrir a dimensão (`Paperclip::Geometry.from_file`). Quando o arquivo sumia
 * do disco, o detalhe inteiro caía com **500**. Aqui a miniatura é um derivado
 * nomeado do ActiveStorage (`thumb`), e imagem indisponível vira **marcador**, não
 * tela quebrada.
 *
 * ## A URL é pedida no momento do clique
 *
 * Nada de URL guardada na listagem: ela tem prazo de 5 minutos e uma listagem que
 * fica aberta na tela a veria expirar. O download passa pelo endpoint
 * **autorizado** da renegociação, que responde sempre
 * `Content-Disposition: attachment`.
 */
export interface AttachmentGalleryProps {
  anexos: RenegotiationAttachment[]
  onDownload: (anexo: RenegotiationAttachment) => void
  onRename?: (anexo: RenegotiationAttachment, titulo: string) => void
  onDelete?: (anexo: RenegotiationAttachment) => void
  podeEscrever?: boolean
  baixando?: string | null
}

export function AttachmentGallery({
  anexos,
  onDownload,
  onRename,
  onDelete,
  podeEscrever,
  baixando,
}: AttachmentGalleryProps) {
  const [renomeando, setRenomeando] = useState<string | null>(null)
  const [rascunho, setRascunho] = useState('')

  return (
    <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
      {anexos.map((anexo) => (
        <li
          key={anexo.id}
          className="flex items-start gap-3 rounded-lg border border-border bg-background p-3"
        >
          <Miniatura anexo={anexo} />

          <div className="flex min-w-0 flex-1 flex-col gap-1">
            {renomeando === anexo.id ? (
              <form
                className="flex items-center gap-1"
                onSubmit={(evento) => {
                  evento.preventDefault()
                  onRename?.(anexo, rascunho)
                  setRenomeando(null)
                }}
              >
                <Input
                  autoFocus
                  value={rascunho}
                  onChange={(e) => setRascunho(e.target.value)}
                  aria-label="Novo nome do anexo"
                />
                <Button type="submit" variant="ghost" size="icon" aria-label="Salvar nome">
                  <Check className="h-4 w-4" aria-hidden />
                </Button>
                <Button
                  type="button"
                  variant="ghost"
                  size="icon"
                  aria-label="Cancelar"
                  onClick={() => setRenomeando(null)}
                >
                  <X className="h-4 w-4" aria-hidden />
                </Button>
              </form>
            ) : (
              <span className="truncate text-sm font-medium text-foreground" title={anexo.title}>
                {anexo.title}
              </span>
            )}

            <span className="text-xs text-muted-foreground">
              {anexo.format || '—'}
              {anexo.byte_size != null && ` · ${formatarTamanho(anexo.byte_size)}`}
              {' · '}
              {formatDate(anexo.created_at)}
            </span>
            <span className="truncate text-xs text-muted-foreground">
              Enviado por {anexo.author_name ?? '—'}
            </span>

            <div className="mt-1 flex flex-wrap items-center gap-1">
              <Button
                variant="ghost"
                size="sm"
                onClick={() => onDownload(anexo)}
                loading={baixando === anexo.id}
              >
                <Download className="mr-1.5 h-4 w-4" aria-hidden />
                Baixar
              </Button>

              {podeEscrever && onRename && renomeando !== anexo.id && (
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    setRenomeando(anexo.id)
                    setRascunho(anexo.title)
                  }}
                >
                  <Pencil className="mr-1.5 h-4 w-4" aria-hidden />
                  Renomear
                </Button>
              )}

              {/* FE-211 — a ação de excluir aparece **só para o autor**. E o
                  servidor recusa de qualquer forma (BE-229): no legado a regra
                  de dono era só visual. */}
              {podeEscrever && onDelete && anexo.can_delete && (
                <Button variant="ghost" size="sm" onClick={() => onDelete(anexo)}>
                  <Trash2 className="mr-1.5 h-4 w-4 text-destructive-text" aria-hidden />
                  <span className="text-destructive-text">Excluir</span>
                </Button>
              )}

              {podeEscrever && onDelete && !anexo.can_delete && (
                <Tooltip content="Só quem enviou o anexo pode removê-lo.">
                  <span className="px-2 text-xs text-muted-foreground">Sem permissão para excluir</span>
                </Tooltip>
              )}
            </div>
          </div>
        </li>
      ))}
    </ul>
  )
}

/**
 * A miniatura. Para imagem, pede o derivado `thumb`; para documento, mostra o
 * ícone. **Falha marca só ESTA imagem** — nunca derruba a lista.
 */
function Miniatura({ anexo }: { anexo: RenegotiationAttachment }) {
  const [url, setUrl] = useState<string | null>(null)
  const [falhou, setFalhou] = useState(false)

  useEffect(() => {
    let vivo = true
    if (!anexo.is_image || !anexo.file_id) return
    attachmentsApi
      .variantUrl(anexo.file_id, 'thumb')
      .then((endereco) => vivo && setUrl(endereco))
      .catch(() => vivo && setFalhou(true))
    return () => {
      vivo = false
    }
  }, [anexo.is_image, anexo.file_id])

  const moldura =
    'flex h-14 w-14 shrink-0 items-center justify-center overflow-hidden rounded-md border border-border bg-muted'

  if (!anexo.is_image) {
    return (
      <div className={moldura} aria-hidden>
        <FileText className="h-6 w-6 text-muted-foreground" />
      </div>
    )
  }

  if (falhou || !anexo.file_id) {
    return (
      <div className={moldura} title="Imagem indisponível">
        <ImageOff className="h-6 w-6 text-muted-foreground" aria-hidden />
      </div>
    )
  }

  return (
    <div className={moldura}>
      {url ? (
        <img
          src={url}
          alt={anexo.title}
          className="h-full w-full object-cover"
          onError={() => setFalhou(true)}
        />
      ) : (
        <span className="h-full w-full animate-pulse bg-muted" aria-hidden />
      )}
    </div>
  )
}

function formatarTamanho(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${formatAmount(bytes / 1024, 0)} KB`
  // `toFixed(1)` dava `2.5 MB` — ponto decimal em tela portuguesa.
  return `${formatAmount(bytes / (1024 * 1024), 1)} MB`
}
