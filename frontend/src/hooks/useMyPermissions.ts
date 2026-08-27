import { useQuery } from '@tanstack/react-query'
import { apiClient } from '@/lib/api/client'

/**
 * As permissões **efetivas do próprio usuário** — o que o front usa para
 * esconder botão (`FE-314`, `FE-318`, `FE-718`).
 *
 * O endpoint `GET /api/v1/permissions/me` existe desde a S0 e **nenhuma tela o
 * consumia**: o comentário do próprio endpoint diz *"é o que o front usa para
 * esconder botão"*, e o front nunca chamou. Sem ele, o único jeito de a tela
 * saber que o perfil é somente-leitura seria tentar gravar e ler o 403 — que é
 * exatamente o estado de UI que esta migração veio consertar.
 *
 * **Nasce na biblioteca compartilhada, não dentro de uma tela** (Princípio 11):
 * "este perfil pode escrever?" é a mesma pergunta em recebível, renegociação,
 * limite e indicador.
 *
 * ## O que este hook NÃO é
 *
 * Não é autorização. O servidor decide, sempre — `require_not_readonly!` e
 * `authorize!` continuam valendo e são o que impede a gravação. Isto aqui é
 * **cortesia de interface**: evitar oferecer um controle que o servidor vai
 * recusar. No legado era o contrário: o gate existia SÓ na view, e a requisição
 * direta passava (D-23 / D-34).
 *
 * A resposta é resolvida por consulta a cada vez (nunca congelada no usuário),
 * então uma revogação vale na requisição seguinte. O cache de 5 minutos é da
 * tela, não da decisão.
 */
export interface MyPermission {
  id: string
  key: string
  title: string
  description: string | null
  sort_order: number
  granted: boolean
  /** DEC-108 — `conditional` (interruptor) ou `limit` (teto numérico). */
  kind?: 'conditional' | 'limit'
  /** Só em `kind: 'limit'`. `null` = sem limite; `0` = nenhum permitido. */
  limit_value?: number | null
}

/**
 * O endpoint responde **plano** (`{user_id, permissions}`) porque
 * `Api::V1::ControllerHelpers#process_service_response` devolve `response[:data]`
 * direto — e não o `{ data: … }` do `ApiResponseHandler`. As duas formas existem
 * na base; ler as duas aqui é mais barato que descobrir a diferença com a tela
 * em branco (foi o que aconteceu: o hook lia só `data.permissions` e o modo
 * somente-leitura nunca acendia).
 */
interface MyPermissionsResponse {
  user_id?: string
  permissions?: MyPermission[]
  data?: { user_id: string; permissions: MyPermission[] }
}

export const MY_PERMISSIONS_KEY = ['permissions', 'me'] as const

export function useMyPermissions() {
  return useQuery({
    queryKey: MY_PERMISSIONS_KEY,
    queryFn: async () => {
      const resposta = await apiClient.get<MyPermissionsResponse>('/api/v1/permissions/me')
      return resposta?.permissions ?? resposta?.data?.permissions ?? []
    },
    staleTime: 5 * 60 * 1000,
  })
}

/**
 * `true` quando o perfil tem a concessão `user_is_readonly` — a de maior alcance
 * das 7 abilities do legado que sobreviveram (DEC-108), promovida de flag de
 * view a checagem de servidor.
 *
 * **Enquanto a resposta não chega, devolve `false`**: assumir readonly faria a
 * tela piscar sem os botões e depois mostrá-los, o que parece defeito. O
 * servidor recusa de qualquer forma, e o erro é tratado com a mensagem
 * explicativa do padrão `FE-323`.
 */
export function useIsReadonly(): boolean {
  const { data } = useMyPermissions()
  return (data ?? []).some((p) => p.key === 'user_is_readonly' && p.granted)
}
