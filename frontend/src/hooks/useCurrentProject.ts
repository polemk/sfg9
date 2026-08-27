import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { useAuthStore } from '@/store/authStore'
import { currentProjectApi, type CurrentProjectPayload } from '@/lib/api/console'

export const CURRENT_PROJECT_KEY = ['current-project'] as const

/**
 * O projeto corrente — contrato **C1** visto do cliente.
 *
 * **Estado de servidor, nunca cookie.** O legado guardava o tenant num cookie
 * `cached_info` escrito pelos dois lados, com 4 dias de vida e nenhuma flag de
 * segurança (D-28). Aqui a única fonte é `GET /api/v1/current_project`; trocar
 * de projeto é um `PUT` que o servidor revalida contra `memberships`.
 *
 * O menu consome o `hasProject` daqui para o gate `projects.count > 0`. Enquanto
 * a consulta está em voo, `hasProject` é `undefined` — a `Sidebar` trata isso
 * como "ainda não sei" e não pisca itens.
 */
export function useCurrentProject() {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)
  const queryClient = useQueryClient()

  const query = useQuery({
    queryKey: CURRENT_PROJECT_KEY,
    queryFn: () => currentProjectApi.get(),
    enabled: isAuthenticated,
    staleTime: 60_000,
  })

  const trocar = useMutation({
    mutationFn: (projectId: number) => currentProjectApi.set(projectId),
    onSuccess: (projeto) => {
      queryClient.setQueryData<CurrentProjectPayload>(CURRENT_PROJECT_KEY, (antigo) =>
        antigo ? { ...antigo, current: projeto } : antigo,
      )
      // Tudo que é escopado por projeto tem que ser relido: manter cache de
      // outro projeto na tela é exatamente o vazamento de escopo que o C1 fecha.
      queryClient.invalidateQueries()
      notify.success(`Projeto: ${projeto.name}`)
    },
    onError: () => {
      // Projeto inexistente e projeto sem participação respondem o MESMO 404
      // (DC-08 condição 2) — a mensagem também é a mesma, de propósito.
      notify.error('Projeto não encontrado.')
    },
  })

  const projects = query.data?.projects ?? []

  return {
    current: query.data?.current ?? null,
    projects,
    /** `undefined` enquanto carrega — não é `false`. */
    hasProject: query.isPending ? undefined : projects.length > 0,
    isLoading: query.isPending,
    error: query.error,
    switchProject: trocar.mutate,
    isSwitching: trocar.isPending,
  }
}
