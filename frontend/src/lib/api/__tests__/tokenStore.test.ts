import { describe, it, expect, beforeEach } from 'vitest'
import {
  getAccessToken,
  setAccessToken,
  getCsrfToken,
  setCsrfToken,
  clearTokens,
  purgeLegacyTokenStorage,
} from '../tokenStore'

// ⚠️ Este é o ÚNICO arquivo que usa localStorage de propósito: é o que ele
// precisa limpar. Varreduras por "localStorage + token" devem excluir __tests__.
describe('tokenStore — credenciais só em memória', () => {
  beforeEach(() => {
    clearTokens()
    localStorage.clear()
  })

  it('guarda e devolve o access token sem tocar em localStorage', () => {
    setAccessToken('access-123')

    expect(getAccessToken()).toBe('access-123')
    // O ponto da mudança: nada durável para um XSS encontrar
    expect(localStorage.getItem('access_token')).toBeNull()
    expect(JSON.stringify(localStorage)).not.toContain('access-123')
  })

  it('guarda o csrf token em memória', () => {
    setCsrfToken('csrf-abc')

    expect(getCsrfToken()).toBe('csrf-abc')
    expect(localStorage.getItem('csrf_token')).toBeNull()
  })

  it('clearTokens zera os dois (logout)', () => {
    setAccessToken('a')
    setCsrfToken('b')

    clearTokens()

    expect(getAccessToken()).toBeNull()
    expect(getCsrfToken()).toBeNull()
  })

  it('purga as chaves cruas que versões antigas persistiam', () => {
    localStorage.setItem('access_token', 'antigo')
    localStorage.setItem('refresh_token', 'antigo-refresh')
    localStorage.setItem('csrf_token', 'antigo-csrf')
    localStorage.setItem('token', 'antigo-compat')

    purgeLegacyTokenStorage()

    expect(localStorage.getItem('access_token')).toBeNull()
    expect(localStorage.getItem('refresh_token')).toBeNull()
    expect(localStorage.getItem('csrf_token')).toBeNull()
    expect(localStorage.getItem('token')).toBeNull()
  })

  it('purga os tokens do estado persistido do zustand, preservando o resto', () => {
    localStorage.setItem(
      'auth-storage',
      JSON.stringify({ state: { accessToken: 'x', refreshToken: 'y', user: { id: 'u-1' } }, version: 0 })
    )

    purgeLegacyTokenStorage()

    const persisted = JSON.parse(localStorage.getItem('auth-storage')!)
    expect(persisted.state.accessToken).toBeUndefined()
    expect(persisted.state.refreshToken).toBeUndefined()
    // O usuário continua lá — só as credenciais saem
    expect(persisted.state.user.id).toBe('u-1')
  })
})
