import { useAuthStore } from '@/store/authStore'

/**
 * S9 / FE-228 — **as permissões do usuário, do lado da tela**.
 *
 * ⚠ **Isto é conveniência, nunca a regra.** A recusa acontece no servidor
 * (`require_not_readonly!` roda em todo `/api/v1/*`, e `authorize!` consulta a
 * matriz). Esconder o botão sem a checagem do servidor é exatamente o que o
 * legado fazia — **D-17 / D-23 / D-34**: a única autorização que existia estava
 * nos gates das views, então qualquer requisição feita fora da tela fazia tudo.
 *
 * Se você está escrevendo uma tela nova: use isto para NÃO OFERECER a ação, e
 * confie no 403 do servidor para recusá-la. As duas coisas, sempre.
 */
export function usePermission(key: string): boolean {
  const user = useAuthStore((estado) => estado.user)
  const concessao = user?.permissions?.find((p) => p.key === key)
  if (!concessao) return false
  // Uma concessão revogada continua na lista, com `revoked_at` preenchido.
  return !concessao.revoked_at
}

/**
 * Modo Somente Leitura — a de maior alcance das 7 abilities do legado que
 * sobreviveram (DEC-108), promovida de flag de view a checagem de servidor.
 */
export function useIsReadonly(): boolean {
  return usePermission('user_is_readonly')
}
