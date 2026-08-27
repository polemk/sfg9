import type { AttachmentLimit } from './types'

/**
 * Textos do legado, preservados palavra por palavra
 * (`renegotiations/detail/tabs/_tab_geral.js.erb:91,102`). O título do aviso era
 * "Limite excedido" nos dois casos.
 *
 * **Os números vêm do servidor**, não daqui. É a diferença entre o legado (que
 * interpolava a constante no JS e não validava nada no backend) e este motor.
 */
export const LIMIT_EXCEEDED_TITLE = 'Limite excedido'

export function tooManyFilesMessage(limit: AttachmentLimit): string {
  return `O máximo de arquivos permitido para envio é de ${limit.maxFiles} arquivos`
}

export function fileTooLargeMessage(limit: AttachmentLimit): string {
  return `O tamanho máximo de cada arquivo permitido para envio é de ${limit.maxSizeMegabytes} MB`
}

export interface PickValidationResult {
  accepted: File[]
  errors: string[]
}

/**
 * Confere a seleção do usuário contra o limite do servidor.
 *
 * **Isto é conveniência, não segurança.** O servidor valida de novo, sempre — o
 * legado tinha só esta metade, e um `curl` passava por cima dela. Se algum dia
 * esta função e o backend discordarem, quem manda é o backend.
 */
export function validatePick(
  files: File[],
  alreadyAttached: number,
  limit: AttachmentLimit | undefined
): PickValidationResult {
  if (!limit) {
    // Sem limite conhecido não se inventa um: manda tudo e deixa o servidor
    // responder. Inventar um número aqui é como os dois lados divergem.
    return { accepted: files, errors: [] }
  }

  const errors: string[] = []
  let accepted = files

  if (limit.maxFiles != null && alreadyAttached + files.length > limit.maxFiles) {
    errors.push(tooManyFilesMessage(limit))
    accepted = files.slice(0, Math.max(0, limit.maxFiles - alreadyAttached))
  }

  const oversized = accepted.filter((f) => f.size > limit.maxSizeBytes)
  if (oversized.length > 0) {
    errors.push(fileTooLargeMessage(limit))
    accepted = accepted.filter((f) => f.size <= limit.maxSizeBytes)
  }

  return { accepted, errors }
}

/** `true` quando o registro já bateu o teto — vira o `data-locked` do wrapper. */
export function isLocked(alreadyAttached: number, limit: AttachmentLimit | undefined): boolean {
  if (!limit || limit.maxFiles == null) return false
  return alreadyAttached >= limit.maxFiles
}
