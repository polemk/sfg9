import type { ReactNode } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import { useRoleSlug } from '@/hooks/useNavItems'
import type { RoleSlug } from '@/app/consoleNavigation'

/**
 * Guarda de rota **por papel**, alimentada pela mesma lista que monta o menu.
 *
 * Esconder o item de menu não é gatear a rota: no legado a única autorização
 * que existia estava nos gates das views (D-23), então qualquer requisição
 * feita fora da tela fazia tudo (D-34). Aqui o item some **e** o endereço
 * digitado à mão para.
 *
 * Isto ainda **não é a autorização** — a autorização é a
 * `Authorization::Matrix` do servidor, que responde 403 mesmo que esta guarda
 * falhe. Esta é a camada de navegação: evita levar o usuário a uma tela que
 * vai encher de 403.
 *
 * `OgRoute` (da base) continua existindo para as telas herdadas do ai9; para
 * área nova do Safegold use esta, que fala a mesma linguagem de papel que o
 * `consoleNavigation` e a matriz.
 */
export function RoleRoute({ roles, children }: { roles: RoleSlug[]; children: ReactNode }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)
  const papel = useRoleSlug()

  if (!isAuthenticated) return <Navigate to="/login" replace />
  // Papel desconhecido cai no lado restrito, nunca no permissivo.
  if (!papel || !roles.includes(papel)) return <Navigate to="/dashboard" replace />

  return <>{children}</>
}
