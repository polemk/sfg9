import { apiClient } from '@/lib/api/client'
import type {
  Attachment,
  AttachmentLimit,
  AttachmentLimitsResponse,
  SignedAttachmentUrl,
} from './types'

/**
 * O backend fala snake_case; o front, camelCase. A conversão fica AQUI, num lugar
 * só — espalhá-la pelos componentes é como um deles acaba lendo `max_files` e
 * outro `maxFiles`, e o limite some numa tela sem ninguém perceber.
 */
const toAttachment = (raw: any): Attachment => ({
  id: raw.id,
  filename: raw.filename,
  contentType: raw.content_type,
  byteSize: raw.byte_size,
  createdAt: raw.created_at,
})

const toLimit = (raw: any): AttachmentLimit => ({
  multiple: !!raw.multiple,
  maxFiles: raw.max_files ?? null,
  maxSizeBytes: raw.max_size_bytes,
  maxSizeMegabytes: raw.max_size_megabytes,
  contentTypes: raw.content_types ?? [],
})

export const attachmentsApi = {
  /** Limites declarados no servidor. A tela NÃO tem número escrito nela. */
  async limits(): Promise<AttachmentLimitsResponse> {
    const data = await apiClient.get<any>('/api/v1/attachments/limits')
    const attachments: AttachmentLimitsResponse['attachments'] = {}
    Object.entries(data.attachments ?? {}).forEach(([model, names]) => {
      attachments[model] = {}
      Object.entries(names as Record<string, any>).forEach(([name, limit]) => {
        attachments[model][name] = toLimit(limit)
      })
    })
    return { urlExpiresInSeconds: data.url_expires_in_seconds, attachments }
  },

  /**
   * URL assinada de prazo curto. É o servidor que autoriza — o front nunca monta
   * uma URL de anexo por conta própria.
   */
  async signedUrl(id: string): Promise<SignedAttachmentUrl> {
    const data = await apiClient.get<any>(`/api/v1/attachments/${encodeURIComponent(id)}`)
    return {
      id: data.id,
      filename: data.filename,
      contentType: data.content_type,
      byteSize: data.byte_size,
      url: data.url,
      expiresAt: data.expires_at,
    }
  },

  /** URL de um derivado nomeado (thumb, preview, large…). */
  async variantUrl(id: string, variant: string): Promise<string> {
    const data = await apiClient.get<any>(
      `/api/v1/attachments/${encodeURIComponent(id)}/variant`,
      { params: { variant } }
    )
    return data.url
  },
}

export { toAttachment }
