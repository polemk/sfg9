import React from 'react'
import { Navigate } from 'react-router-dom'
import { useAuthStore, useRole } from '@/store/authStore'

/**
 * **Guarda das rotas de console administrativo.** Passa OG e Admin; o resto vai
 * para o painel.
 *
 * A regra vem do `useRole()`, que é onde a **DEC-41** já está implementada —
 * este arquivo não decide papel por conta própria.
 *
 * Antes ele fazia `user_type.toLowerCase().includes('admin')`, e isso tem dois
 * problemas. O primeiro é que casa por acidente: um tipo chamado
 * "Administrativo" ou "Sub-admin" passaria. O segundo é pior — a mesma decisão
 * ficava escrita em três lugares (aqui, no `VisitorRoute` e no `useRole`), e
 * três cópias de uma regra de autorização valem pela mais frouxa.
 */
export function OgRoute({ children }: { children: React.ReactNode }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)
  const { isOg, isAdmin } = useRole()

  if (!isAuthenticated) return <Navigate to="/login" replace />
  if (!(isOg || isAdmin)) return <Navigate to="/dashboard" replace />

  return <>{children}</>
}
