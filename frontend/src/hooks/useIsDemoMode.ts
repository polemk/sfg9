import { useAuthStore } from '@/store/authStore'

/**
 * Hook que determina se o console deve exibir dados de demonstração (mock/fake).
 * 
 * Retorna `true` para visitors E clients — ou seja, qualquer usuário
 * que não seja OG/Admin/Super. Isso garante que, mesmo após a compra
 * de um plano (quando visitor vira client), o console continue
 * mostrando dados fake ao invés de tentar buscar dados reais da API.
 * 
 * Apenas OG/Admin tem dados reais.
 */
export function useIsDemoMode(): boolean {
  const user = useAuthStore((s) => s.user)
  const t = (user?.user_type || '').toLowerCase()
  const slug = (user?.user_type_slug || '').toLowerCase()

  const isOG = t.includes('og') || t.includes('super') || t.includes('admin')

  // Se NÃO é OG, usa dados demo (visitors, clients, etc.)
  return !isOG
}
