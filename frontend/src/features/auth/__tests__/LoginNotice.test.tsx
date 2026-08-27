import { describe, it, expect, beforeEach } from 'vitest'
import React from 'react'
import { render, screen } from '@testing-library/react'
import { LoginNotice, safeNextPath } from '../LoginNotice'

/**
 * BE-007 / IMP-A3 e FE-044 / IMP-A17.
 *
 * O legado interpolava o `next` direto no JavaScript da página — família D-69, open
 * redirect —, e o aviso que deveria mostrar o destino vivia num container
 * `.warning_message` **comentado no HTML**: a mensagem existia e nunca aparecia.
 */
describe('safeNextPath — allowlist same-origin', () => {
  it('aceita caminho relativo', () => {
    expect(safeNextPath('/users')).toBe('/users')
    expect(safeNextPath('/users/1/edit')).toBe('/users/1/edit')
  })

  it('recusa protocol-relative (`//evil.com` sai do site)', () => {
    expect(safeNextPath('//evil.com')).toBeNull()
    expect(safeNextPath('///evil.com')).toBeNull()
  })

  it('recusa URL absoluta e esquema executável', () => {
    expect(safeNextPath('https://evil.com')).toBeNull()
    expect(safeNextPath('javascript:alert(1)')).toBeNull()
    expect(safeNextPath('data:text/html,<script>')).toBeNull()
  })

  it('recusa a forma codificada do mesmo ataque', () => {
    expect(safeNextPath('%2F%2Fevil.com')).toBeNull()
    expect(safeNextPath('https%3A%2F%2Fevil.com')).toBeNull()
  })

  it('recusa barra invertida (o Chrome normaliza `\\` para `/`)', () => {
    expect(safeNextPath('/\\evil.com')).toBeNull()
  })

  it('recusa vazio e nulo', () => {
    expect(safeNextPath('')).toBeNull()
    expect(safeNextPath(null)).toBeNull()
  })
})

describe('LoginNotice — conta bloqueada explica o motivo', () => {
  beforeEach(() => sessionStorage.clear())

  it('não renderiza nada quando não há aviso', () => {
    const { container } = render(<LoginNotice />)
    expect(container.firstChild).toBeNull()
  })

  it('mostra o motivo do bloqueio e o consome (não reaparece)', () => {
    sessionStorage.setItem('auth:endedReason', 'Conta desligada em 01/2026')
    const { unmount } = render(<LoginNotice />)
    expect(screen.getByText('Conta desligada em 01/2026')).toBeTruthy()
    expect(sessionStorage.getItem('auth:endedReason')).toBeNull()

    unmount()
    const { container } = render(<LoginNotice />)
    expect(container.firstChild).toBeNull()
  })
})
