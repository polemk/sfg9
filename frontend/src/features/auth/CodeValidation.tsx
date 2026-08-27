import React, { useState, useRef, useEffect } from 'react'
import { ArrowLeft, Copy, Check, ArrowRight } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { useAuth } from '@/hooks/useAuth'
import { useAuthStore } from '@/store/authStore'
import { notify } from '@/lib/notify'
import { authService } from '@/lib/api/auth'
import { cn } from '@/lib/utils'

interface CodeValidationProps {
  email: string
  onBack: () => void
  onSuccess: () => void
}

export const CodeValidation: React.FC<CodeValidationProps> = ({ email, onBack, onSuccess }) => {
  const [code, setCode] = useState(['', '', '', '', '', ''])
  const [loading, setLoading] = useState(false)
  const [copied, setCopied] = useState(false)
  const [invalidShake, setInvalidShake] = useState(false)
  const devToastShown = useRef(false)

  const inputRefs = useRef<(HTMLInputElement | null)[]>([])
  const { validateMagicCode } = useAuth()
  const { loginMethod, devCode, error, clearError } = useAuthStore()

  useEffect(() => {
    if (import.meta.env.MODE === 'development' && devCode && !devToastShown.current) {
      const showDevCodeToast = () => {
        notify.info(
          <div className="space-y-2">
            <p className="text-sm font-medium">Código de verificação (dev):</p>
            <div className="flex items-center gap-2 bg-muted p-2 rounded-md">
              <code className="text-sm font-mono flex-1">{devCode}</code>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => {
                  navigator.clipboard.writeText(devCode)
                  setCopied(true)
                  setTimeout(() => setCopied(false), 2000)
                }}
                className="h-6 px-2"
              >
                {copied ? <Check className="w-3 h-3" /> : <Copy className="w-3 h-3" />}
              </Button>
            </div>
          </div>,
          {
            duration: 8000,
            position: 'top-center',
          }
        )
      }
      devToastShown.current = true
      const timer = setTimeout(showDevCodeToast, 600)
      return () => clearTimeout(timer)
    }
  }, [devCode, copied])



  const handleCodeChange = (index: number, value: string) => {
    if (value.length > 1) return
    setInvalidShake(false)
    
    const newCode = [...code]
    newCode[index] = value
    setCode(newCode)

    if (value && index < 5) {
      inputRefs.current[index + 1]?.focus()
    }

    if (value && index === 5 && newCode.every(digit => digit !== '')) {
      handleSubmit(newCode.join(''))
    }
  }

  const handleKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace' && !code[index] && index > 0) {
      inputRefs.current[index - 1]?.focus()
    }
  }

  const handlePaste = (e: React.ClipboardEvent<HTMLInputElement>) => {
    e.preventDefault()
    const pastedData = e.clipboardData.getData('text').slice(0, 6)
    if (/^\d{6}$/.test(pastedData)) {
      const newCode = pastedData.split('')
      setCode(newCode)
      const { setLoginCode } = useAuthStore.getState()
      setLoginCode(pastedData)
      handleSubmit(pastedData)
    }
  }

  const handleSubmit = async (codeValue: string) => {
    if (loading) return
    
    // Validação adicional antes de submeter
    if (!codeValue.trim() || codeValue.length !== 6) {
      notify.error('Por favor, insira o código recebido')
      setInvalidShake(true)
      setTimeout(() => {
        setInvalidShake(false)
        setCode(['', '', '', '', '', ''])
        inputRefs.current[0]?.focus()
      }, 600)
      return
    }
    
    // Verificar se todos os campos são dígitos
    if (!/^\d{6}$/.test(codeValue)) {
      return
    }
    
    setLoading(true)
    try {
      // Set the code in the auth store and validate
      const { setLoginCode } = useAuthStore.getState()
      setLoginCode(codeValue)
      const next = await validateMagicCode()
      // O desfecho 'complete' saiu junto com a tela "Completar cadastro" (DEC-49/
      // DEC-18.7). 'blocked' é conta bloqueada (DEC-39): o motivo já foi posto em
      // `error` pelo hook e aparece acima do campo — não se sacode o campo do código,
      // porque o código não é o problema e sacudir sugere que é.
      if (next === 'blocked') {
        return
      } else if (next === 'login') {
        // navegação já feita em useAuth
        return
      } else {
        setInvalidShake(true)
        setTimeout(() => {
          setInvalidShake(false)
          setCode(['', '', '', '', '', ''])
          inputRefs.current[0]?.focus()
        }, 600)
        return
      }
    } catch (error: any) {
      console.error('Code validation failed:', error)
      const message = error.response?.data?.message || error.response?.data?.error || 'Código inválido ou expirado'
      notify.error(message)
      setInvalidShake(true)
      setTimeout(() => {
        setInvalidShake(false)
        setCode(['', '', '', '', '', ''])
        inputRefs.current[0]?.focus()
      }, 600)
    } finally {
      setLoading(false)
    }
  }

  const [resendCooldown, setResendCooldown] = useState(0)
  useEffect(() => {
    let timer: number | undefined
    if (resendCooldown > 0) {
      timer = window.setInterval(() => {
        setResendCooldown((v) => (v > 0 ? v - 1 : 0))
      }, 1000)
    }
    return () => {
      if (timer) window.clearInterval(timer)
    }
  }, [resendCooldown])

  const handleResend = async () => {
    if (resendCooldown > 0) return
    const { identifier, loginMethod } = useAuthStore.getState()
    try {
      const sanitized = loginMethod === 'email' ? identifier.trim() : identifier.replace(/\D/g, '')
      if (!sanitized) {
        notify.error('Identificador ausente')
        return
      }
      if (loginMethod === 'whatsapp') {
        const len = sanitized.length
        if (len < 11 || len > 15) {
          notify.error('Por favor, insira o WhatsApp com código do país sem + (ex: 5511999999999)')
          return
        }
      }
      await authService.requestLoginCode({ identifier: sanitized, method: loginMethod })
      notify.success('Novo código enviado!')
      setResendCooldown(120)
    } catch (e: any) {
      const msg = e?.response?.data?.error || e?.message || 'Falha ao reenviar código'
      notify.error(msg)
    }
  }



  return (
    <div className="w-full mx-auto animate-in fade-in duration-500">
      <div className="relative">

        {/* Cabeçalho */}
        <div className="mb-8 text-center">
          <h1 className="font-title text-2xl font-semibold tracking-tight text-foreground">
            Verificar código
          </h1>
          <p className="mt-2 break-words text-sm text-muted-foreground">
            Enviado para <span className="font-medium text-foreground">{email}</span>
          </p>
        </div>

        <form
          onSubmit={(e) => { e.preventDefault(); handleSubmit(code.join('')); }}
          className="space-y-5"
        >
          <div>
            <div className={cn('mb-3 grid grid-cols-6 gap-2', invalidShake && 'animate-shake')}>
              {[0, 1, 2, 3, 4, 5].map((index) => (
                <Input
                  key={index}
                  ref={(el) => (inputRefs.current[index] = el)}
                  type="text"
                  inputMode="numeric"
                  maxLength={1}
                  aria-label={`Dígito ${index + 1} do código`}
                  value={code[index] || ''}
                  onChange={(e) => handleCodeChange(index, e.target.value.replace(/\D/g, ''))}
                  onKeyDown={(e) => handleKeyDown(index, e)}
                  onPaste={handlePaste}
                  className={cn(
                    'font-numeric h-14 w-full p-0 text-center text-xl font-semibold',
                    invalidShake && 'border-destructive focus-visible:ring-destructive'
                  )}
                  disabled={loading}
                  placeholder="-"
                />
              ))}
            </div>
            <p className="text-center text-xs text-muted-foreground">
              O código expira em 5 minutos
            </p>
          </div>

          {error && (
            <div
              role="alert"
              className="flex items-center gap-3 rounded-md border border-destructive/30 bg-destructive/10 p-3"
            >
              <div className="h-2 w-2 shrink-0 rounded-full bg-destructive" />
              <div className="text-xs font-medium text-destructive">{error}</div>
            </div>
          )}

          <Button
            type="submit"
            disabled={loading || code.some((digit) => digit === '')}
            variant="primary"
            size="lg"
            className="w-full"
          >
            {loading ? (
              <>
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-current/30 border-t-current" />
                Verificando...
              </>
            ) : (
              <>
                Verificar código <ArrowRight className="h-4 w-4" />
              </>
            )}
          </Button>

          <div className="flex flex-col gap-2">
            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="w-full"
              onClick={handleResend}
              disabled={resendCooldown > 0}
            >
              {resendCooldown > 0
                ? `Reenviar em ${Math.floor(resendCooldown / 60)}:${String(resendCooldown % 60).padStart(2, '0')}`
                : 'Reenviar código'}
            </Button>

            <Button
              type="button"
              variant="ghost"
              size="sm"
              className="w-full text-muted-foreground"
              onClick={() => { clearError(); setInvalidShake(false); setCode(['', '', '', '', '', '']); onBack() }}
            >
              <ArrowLeft className="h-3.5 w-3.5" />
              Voltar para o login
            </Button>
          </div>
        </form>

        <style>{`
          @keyframes shake {
            0%, 100% { transform: translateX(0); }
            20% { transform: translateX(-4px); }
            40% { transform: translateX(4px); }
            60% { transform: translateX(-3px); }
            80% { transform: translateX(3px); }
          }
          .animate-shake { animation: shake 0.6s ease; }
          @media (prefers-reduced-motion: reduce) { .animate-shake { animation: none; } }
        `}</style>
      </div>
    </div>
  )
}
