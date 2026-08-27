import '@testing-library/jest-dom'
import { vi } from 'vitest'

try {
  if (typeof navigator !== 'undefined') {
    const existingClipboard = (navigator as any).clipboard
    if (existingClipboard) {
      existingClipboard.writeText = vi.fn()
    } else {
      Object.defineProperty(navigator, 'clipboard', {
        value: { writeText: vi.fn() },
        configurable: true,
        writable: true
      })
    }
  }
} catch {}

// `Element.scrollIntoView` NÃO EXISTE no jsdom, e o `Select` do ai9 o chama ao
// abrir para manter a opção ativa visível (`Select.tsx:88`). Sem este dublê,
// QUALQUER exemplo que abra um `Select` morre com "el?.scrollIntoView is not a
// function" — e o erro aponta para o componente, não para a lacuna do ambiente,
// então quem esbarra nele procura defeito no lugar errado.
//
// Fica aqui, e não no arquivo de quem esbarrou: o `Select` é usado em dezenas de
// telas, e o próximo a testar uma delas cairia no mesmo buraco.
if (typeof Element !== 'undefined' && !Element.prototype.scrollIntoView) {
  Element.prototype.scrollIntoView = vi.fn()
}

Object.defineProperty(window, 'location', {
  value: Object.assign(new URL('http://localhost/'), {
    assign: vi.fn(),
    reload: vi.fn()
  }),
  writable: true
})