import React, { useState } from 'react'
import { MagicLogin } from './MagicLogin'
import { CodeValidation } from './CodeValidation'
import { useAuthStore } from '@/store/authStore'

/**
 * Fluxo de entrada em DUAS etapas: destino -> código.
 *
 * A terceira etapa ("Completar cadastro") FOI REMOVIDA junto com o componente
 * `CompleteRegistration`. Ela existia para o auto-cadastro, que a DEC-49 apagou, e
 * chamava `POST /auth/v1/complete_registration` — rota que responde 404 desde então.
 * Entrada no Safegold é só por convite (DEC-18.7): quem valida um código já tem conta.
 *
 * Os três painéis empilhados do legado (Entrar / Cadastre-se / Esqueci a senha) somem
 * pelo mesmo motivo — não há cadastro público e não há senha (DEC-14).
 */
type AuthStep = 'login' | 'code'

export const AuthFlow: React.FC = () => {
  const [currentStep, setCurrentStep] = useState<AuthStep>('login')
  const { identifier } = useAuthStore()

  const handleCodeSent = () => {
    setCurrentStep('code')
  }

  const handleBackToLogin = () => {
    setCurrentStep('login')
  }

  return (
    <>
      {currentStep === 'login' && (
        <MagicLogin onCodeSent={handleCodeSent} />
      )}

      {currentStep === 'code' && identifier && (
        <CodeValidation
          email={identifier}
          onBack={handleBackToLogin}
          onSuccess={handleBackToLogin}
        />
      )}
    </>
  )
}
