/**
 * Motor único de anexos — contrato com o backend (S13, sub-bloco B).
 *
 * O que estes tipos deliberadamente NÃO têm: um campo `url` dentro do anexo.
 * URL de anexo tem prazo (5 min), e um prazo embutido numa listagem que fica
 * aberta na tela expira antes de ser usado. A URL é pedida no momento de abrir o
 * arquivo — que é também o momento em que o servidor confere a autorização.
 */

/** Um anexo, como a API o devolve. `id` é assinado, nunca o id da linha. */
export interface Attachment {
  id: string
  filename: string
  contentType: string
  byteSize: number
  createdAt: string
}

/** Limites de um anexo, vindos de `config/attachments.yml` (CFG-02). */
export interface AttachmentLimit {
  multiple: boolean
  maxFiles: number | null
  maxSizeBytes: number
  maxSizeMegabytes: number
  contentTypes: string[]
}

/** Catálogo inteiro: `limits['renegotiation_attachment']['file']`. */
export type AttachmentLimits = Record<string, Record<string, AttachmentLimit>>

export interface AttachmentLimitsResponse {
  urlExpiresInSeconds: number
  attachments: AttachmentLimits
}

export interface SignedAttachmentUrl {
  id: string
  filename: string
  contentType: string
  byteSize: number
  url: string
  expiresAt: string
}
