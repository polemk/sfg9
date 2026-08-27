import { describe, it, expect } from 'vitest'
import {
  validatePick,
  isLocked,
  tooManyFilesMessage,
  fileTooLargeMessage,
} from '../validation'
import type { AttachmentLimit } from '../types'

// Limite da renegociação, como o servidor o devolve a partir de
// `config/attachments.yml` — 4 arquivos, 5 MB cada.
const limit: AttachmentLimit = {
  multiple: true,
  maxFiles: 4,
  maxSizeBytes: 5 * 1024 * 1024,
  maxSizeMegabytes: 5,
  contentTypes: ['pdf', 'png'],
}

// `File.size` é somente leitura no jsdom, então o tamanho é fixado à mão — é a
// única forma de exercitar o teto de 5 MB sem materializar 5 MB no teste.
const file = (name: string, size: number): File =>
  Object.defineProperty(new File([''], name, { type: 'application/pdf' }), 'size', {
    value: size,
  })

describe('validatePick', () => {
  it('aceita a seleção dentro do limite', () => {
    const { accepted, errors } = validatePick([file('a.pdf', 1024)], 0, limit)
    expect(accepted).toHaveLength(1)
    expect(errors).toHaveLength(0)
  })

  it('conta o que já está anexado, não só o lote — o teto é do registro', () => {
    const { accepted, errors } = validatePick([file('e.pdf', 1024)], 4, limit)
    expect(accepted).toHaveLength(0)
    expect(errors).toContain('O máximo de arquivos permitido para envio é de 4 arquivos')
  })

  it('recusa arquivo grande com o texto do legado', () => {
    const { accepted, errors } = validatePick([file('g.pdf', 6 * 1024 * 1024)], 0, limit)
    expect(accepted).toHaveLength(0)
    expect(errors).toContain(
      'O tamanho máximo de cada arquivo permitido para envio é de 5 MB'
    )
  })

  it('deixa passar quando o limite ainda não chegou do servidor — quem decide é o backend', () => {
    // Inventar um número aqui é como os dois lados divergem em silêncio.
    const { accepted, errors } = validatePick([file('a.pdf', 99 * 1024 * 1024)], 0, undefined)
    expect(accepted).toHaveLength(1)
    expect(errors).toHaveLength(0)
  })
})

describe('isLocked', () => {
  it('trava ao atingir o teto e não antes', () => {
    expect(isLocked(3, limit)).toBe(false)
    expect(isLocked(4, limit)).toBe(true)
  })

  it('não trava anexo único sem teto de quantidade', () => {
    expect(isLocked(1, { ...limit, multiple: false, maxFiles: null })).toBe(false)
  })
})

describe('mensagens', () => {
  it('usa os números do servidor, nunca constantes escritas na tela', () => {
    const outro: AttachmentLimit = { ...limit, maxFiles: 7, maxSizeMegabytes: 12 }
    expect(tooManyFilesMessage(outro)).toContain('7 arquivos')
    expect(fileTooLargeMessage(outro)).toContain('12 MB')
  })
})
