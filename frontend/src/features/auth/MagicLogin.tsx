import React, { useState, useEffect } from 'react'
import { Mail, MessageCircle, Chrome, Facebook, ArrowRight } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { PhoneInputGroup } from '@/components/PhoneInputGroup'
import { useAuth } from '@/hooks/useAuth'
import { cn } from '@/lib/utils'
import { notify } from '@/lib/notify'

interface MagicLoginProps {
  onCodeSent: () => void
}

export const MagicLogin: React.FC<MagicLoginProps> = ({ onCodeSent }) => {
  const {
    loginMethod,
    identifier,
    isLoading,
    error,
    setLoginMethod,
    setIdentifier,
    clearError,
    requestMagicLogin,
    loginWithGoogle,
    loginWithFacebook
  } = useAuth()

  const [localIdentifier, setLocalIdentifier] = useState(identifier)

  useEffect(() => {
    setLocalIdentifier(identifier)
  }, [identifier])

  /**
   * **DEFEITO CORRIGIDO AQUI (S1, tarefa 9.4.2): na aba WhatsApp, o botão não fazia
   * nada em silêncio.**
   *
   * Esta função tinha três pré-checagens (identificador vazio, e-mail sem `@`,
   * WhatsApp com menos de 11 dígitos) que davam `return` seco, com um `console.warn`
   * e o comentário *"a validação já é feita no hook"*. **O hook não era chamado
   * nesses casos**, então a validação não acontecia em lugar nenhum.
   *
   * **Medido:** na aba **WhatsApp**, digitar um número curto e clicar em "Entrar"
   * deixava a tela exatamente igual — sem mensagem, sem erro, sem avanço. O único
   * sinal ia para o console do navegador, onde nenhum usuário olha. (Na aba
   * **E-mail** o estrago era menor porque o `<input type="email">` aciona a
   * validação nativa do navegador antes do `submit`; mas isso é sorte do tipo do
   * campo, não desenho — e um `<input type="email">` aceita `a@b`, que a nossa regra
   * recusa, então o caso do e-mail também dependia do hook.)
   *
   * As três checagens eram cópias das que o `useAuth` já faz — e o `useAuth`
   * **escreve o motivo em `error`**, que é o que a faixa vermelha abaixo do campo
   * renderiza. Chamar o hook direto conserta e apaga a duplicação no mesmo passo.
   */
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (isLoading) return

    const success = await requestMagicLogin()
    if (!success) return

    const APP_NAME = import.meta.env.VITE_APP_NAME || 'Safegold'
    if (import.meta.env.MODE !== 'development') {
      notify.success(`Código do ${APP_NAME} enviado! Verifique seu e-mail ou WhatsApp.`)
    }
    onCodeSent()
  }

  const handleMethodChange = (method: 'email' | 'whatsapp') => {
    setLoginMethod(method)
    setLocalIdentifier('')
    clearError()
  }

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const value = e.target.value
    if (loginMethod === 'whatsapp') {
      const digits = value.replace(/\D/g, '')
      const normalized = digits.startsWith('55') ? digits.slice(0, 13) : digits.slice(0, 15)
      setIdentifier(normalized)
      setLocalIdentifier(formatWhatsApp(normalized))
    } else {
      setLocalIdentifier(value)
      setIdentifier(value)
    }
    if (error) clearError()
  }

  const getPlaceholder = () => {
    return loginMethod === 'email'
      ? 'seu@email.com'
      : '(11) 9 0000-0000'
  }

  const formatWhatsApp = (digits: string) => {
    // Formatting logic kept simple for brevity as standard input handles display well mostly
    // But re-using the existing logic for consistency
    if (!digits) return ''
    if (digits.startsWith('55')) {
      const ddi = digits.slice(0, 2)
      const ddd = digits.slice(2, 4)
      const rest = digits.slice(4)
      if (rest.length <= 4) return `${ddi}${ddd ? ' (' + ddd + ')' : ''} ${rest}`.trim()
      if (rest.length <= 8) return `${ddi} (${ddd}) ${rest.slice(0, 4)}-${rest.slice(4)}`
      const first = rest.slice(0, 5)
      const last = rest.slice(5, 9)
      return `${ddi} (${ddd}) ${first}-${last}`
    }
    return digits
  }

  return (
    <div className="w-full mx-auto animate-in fade-in duration-500">
      <div className="relative">

        {/* Cabeçalho */}
        <div className="text-center mb-8">
          <h1 className="font-title text-2xl font-semibold tracking-tight text-foreground">
            Acessar o painel
          </h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Enviamos um código de acesso. Sem senha para lembrar.
          </p>
        </div>

        {/* Seletor de canal */}
        <div className="mb-6 flex gap-1 rounded-md border border-border bg-muted p-1">
          {(['email', 'whatsapp'] as const).map((method) => (
            <button
              key={method}
              type="button"
              onClick={() => handleMethodChange(method)}
              className={cn(
                'flex flex-1 items-center justify-center gap-2 rounded-sm py-2.5 text-xs font-semibold uppercase tracking-wider transition-colors',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background',
                loginMethod === method
                  ? 'bg-primary text-primary-foreground shadow-e1'
                  : 'text-muted-foreground hover:bg-accent hover:text-accent-foreground'
              )}
            >
              {method === 'email' ? <Mail className="h-3.5 w-3.5" /> : <MessageCircle className="h-3.5 w-3.5" />}
              <span>{method === 'email' ? 'E-mail' : 'WhatsApp'}</span>
            </button>
          ))}
        </div>

        {/* Formulário */}
        <form onSubmit={handleSubmit} className="space-y-5">
          {loginMethod === 'email' ? (
            <div className="relative">
              <Mail className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                type="email"
                value={localIdentifier}
                onChange={handleInputChange}
                placeholder={getPlaceholder()}
                aria-label="E-mail"
                className="h-12 pl-10"
                disabled={isLoading}
              />
            </div>
          ) : (
            <PhoneInputGroup
              value={identifier}
              onChange={(normalized) => {
                setIdentifier(normalized)
                setLocalIdentifier(formatWhatsApp(normalized))
                if (error) clearError()
              }}
              disabled={isLoading}
              className="h-12"
            />
          )}

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
            disabled={isLoading || !localIdentifier.trim()}
            variant="primary"
            size="lg"
            className="w-full"
          >
            {isLoading ? (
              <>
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-current/30 border-t-current" />
                Enviando...
              </>
            ) : (
              <>
                Entrar <ArrowRight className="h-4 w-4" />
              </>
            )}
          </Button>
        </form>

        {/* Rodapé */}
        <div className="mt-8 border-t border-border pt-6 text-center">
          <div className="mb-4 text-xs font-medium uppercase tracking-widest text-muted-foreground">
            Ou entre com
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Button type="button" variant="secondary" onClick={loginWithGoogle}>
              <Chrome className="h-4 w-4" />
              <span className="text-xs font-semibold uppercase tracking-wider">Google</span>
            </Button>
            <Button type="button" variant="secondary" onClick={loginWithFacebook}>
              <Facebook className="h-4 w-4" />
              <span className="text-xs font-semibold uppercase tracking-wider">Facebook</span>
            </Button>
          </div>
        </div>

      </div>
    </div>
  )
}
