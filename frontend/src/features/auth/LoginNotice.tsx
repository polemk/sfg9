import { useEffect, useState } from 'react'
import { AlertTriangle, Info } from 'lucide-react'

/**
 * Avisos da tela de login.
 *
 * Cobre dois casos que no legado existiam no código e **nunca apareciam**:
 *
 *  1. **Conta bloqueada (FE-044 / IMP-A17).** A sessão derrubada por `ACCOUNT_BLOCKED`
 *     deixava o usuário de volta no formulário sem explicação nenhuma. O interceptor
 *     grava o motivo em `sessionStorage`; aqui ele é lido uma vez e apagado, para não
 *     reaparecer no login seguinte.
 *
 *  2. **Destino pós-login (`?next=`, FE-006).** O legado tinha o container
 *     `.warning_message` **comentado no HTML**: a mensagem existia e nunca era vista.
 *     Aqui ela aparece — e só para destino **same-origin**. O legado interpolava o
 *     `next` direto no JavaScript da página (família D-69, open redirect); um caminho
 *     absoluto para outro host é descartado em silêncio, não exibido.
 */
export function LoginNotice() {
  const [blockedReason, setBlockedReason] = useState<string | null>(null)

  useEffect(() => {
    try {
      const reason = sessionStorage.getItem('auth:endedReason')
      if (reason) {
        setBlockedReason(reason)
        sessionStorage.removeItem('auth:endedReason')
      }
    } catch { /* sessionStorage indisponível: segue sem aviso */ }
  }, [])

  const nextPath = safeNextPath(new URLSearchParams(window.location.search).get('next'))

  if (!blockedReason && !nextPath) return null

  return (
    <div className="mb-6 space-y-3">
      {blockedReason && (
        <div
          role="alert"
          className="flex items-start gap-3 rounded-md border border-destructive/30 bg-destructive/10 p-3"
        >
          <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-destructive" />
          <div className="text-xs font-medium leading-relaxed text-destructive">{blockedReason}</div>
        </div>
      )}

      {nextPath && (
        <div className="flex items-start gap-3 rounded-md border border-border bg-muted p-3">
          <Info className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
          <div className="text-xs leading-relaxed text-muted-foreground">
            Depois de entrar você volta para <span className="font-medium text-foreground">{nextPath}</span>.
          </div>
        </div>
      )}
    </div>
  )
}

/**
 * Allowlist de destino pós-login — **same-origin apenas** (BE-007 / IMP-A3).
 *
 * Aceita só caminho relativo começando com uma única `/`. Recusa:
 *  - `//evil.com` e `///evil.com` — o navegador lê como protocol-relative e sai do site;
 *  - `https://evil.com`, `javascript:…`, `data:…` — esquema externo ou executável;
 *  - qualquer coisa com `\` (o Chrome normaliza `\` para `/` em URL).
 */
export function safeNextPath(raw: string | null | undefined): string | null {
  if (!raw) return null

  let value: string
  try {
    value = decodeURIComponent(raw)
  } catch {
    return null
  }

  if (!value.startsWith('/')) return null
  if (value.startsWith('//')) return null
  if (value.includes('\\')) return null
  if (value.includes(':')) return null

  return value
}
