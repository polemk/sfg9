import { describe, it, expect, vi } from 'vitest'
import React from 'react'
import { render } from '@testing-library/react'
import { CodeValidation } from '../CodeValidation'

// Mock do useAuth
vi.mock('@/hooks/useAuth', () => ({
  useAuth: () => ({
    validateMagicCode: vi.fn()
  })
}))

// Mock do useAuthStore
vi.mock('@/store/authStore', () => ({
  useAuthStore: () => ({
    loginMethod: 'email'
  })
}))

describe('CodeValidation', () => {
  it('deve renderizar sem erros', () => {
    const { container } = render(
      <CodeValidation 
        email="test@example.com" 
        onBack={vi.fn()} 
        onSuccess={vi.fn()} 
      />
    )
    expect(container).toBeTruthy()
  })

  it('deve ter título de verificação', () => {
    const { getByText, getByRole } = render(
      <CodeValidation 
        email="test@example.com" 
        onBack={vi.fn()} 
        onSuccess={vi.fn()} 
      />
    )
    // "Verificar código" aparece duas vezes — no título e no botão de submit.
    // O que este teste checa é o TÍTULO, então busca pelo papel de cabeçalho.
    expect(getByRole('heading', { name: 'Verificar código' })).toBeTruthy()
  })

  it('deve mostrar email do usuário', () => {
    const { getByText } = render(
      <CodeValidation 
        email="test@example.com" 
        onBack={vi.fn()} 
        onSuccess={vi.fn()} 
      />
    )
    // O rotulo virou "Enviado para <email>", com o e-mail em elemento proprio.
    expect(getByText('test@example.com')).toBeTruthy()
  })
})