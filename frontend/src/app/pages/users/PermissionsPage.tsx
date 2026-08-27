import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query'
import { BadgeCheck, ShieldAlert } from 'lucide-react'
import { notify } from '@/lib/notify'

import PageHeader from '@/components/PageHeader'
import { PermissionControl } from '@/components/PermissionControl'
import { Badge } from '@/components/ui/Badge'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { useChannel } from '@/hooks/useCable'
import { userTypesApi, type PermissionChange, type UserTypeSummary } from '@/lib/api/endpoints'
import { useAuthStore } from '@/store/authStore'

/**
 * `/permissions` — **um card por papel**, com um controle por permissão. FE-026,
 * FE-027, FE-042, FE-043, BE-040, IMP-A18, **DEC-108**.
 *
 * ## O que esta tela faz que a do legado não fazia
 *
 * **1. A mudança tem efeito imediato — sem recarregar** (FE-027 / IMP-A18). No legado
 * a permissão era **clonada** para dentro de cada usuário na criação (`Role` +
 * 17 `Ability` copiadas, D-35): alterar o padrão do papel não alcançava ninguém que
 * já existisse, e a única forma de "aplicar" era recriar a conta. Aqui a permissão é
 * **resolvida por consulta** (`Authorization::PermissionResolver`), então a mudança
 * já vale na requisição seguinte de todo mundo — e o `PermissionsChannel` avisa cada
 * pessoa afetada para que a tela dela se refaça sozinha (Princípio 10: o evento não
 * carrega estado, ele invalida a consulta).
 *
 * **2. Existe toast de sucesso.** Na tela do legado
 * (`permissions/_body.js.erb`) o ramo `else` do callback era **vazio**: quando dava
 * certo, nada acontecia visivelmente, e o operador clicava de novo (FE-042/FE-043).
 *
 * **3. A trava de hierarquia é do servidor, e a tela a espelha** (DEC-18.2). O Admin
 * edita papéis de hierarquia **inferior** — nunca o OG, nunca outro Admin, nunca o
 * próprio. Quem manda é `editable`, campo que o servidor devolve; a tela não recalcula
 * hierarquia. Recalcular no cliente é como as duas contas divergem, e no legado o
 * `:id` do usuário era simplesmente descartado (D-34).
 *
 * **4. O Gerente não chega aqui.** O gate de papel está no registro de navegação
 * (`consoleNavigation.tsx`: `roles: ['og','admin']`), que é o mesmo dado que monta o
 * menu — esconder o item e barrar o endereço digitado à mão são a mesma linha. O
 * servidor recusa de qualquer forma (403 no catálogo e no `PUT`).
 *
 * ## Quantas permissões, e por quê — **DEC-108**
 *
 * O catálogo tem **7** linhas: `user_is_readonly` mais as 6 abilities do legado que
 * tinham call site real fora do factory e dos seeds. As outras 10 têm zero
 * consumidor, verificado uma a uma, e ficaram de fora.
 *
 * A tela **não tem lista escrita dentro dela**: ela renderiza o que o servidor
 * devolver. Foi assim que passou de 1 para 7 sem que nenhuma chave fosse digitada
 * aqui.
 *
 * ⚠ **Correção de atribuição.** Este bloco dizia antes *"DEC-18.6, decisão #6 do
 * usuário"*. As duas metades estavam erradas: a DEC-18.6 é sobre `Membership.role`
 * ser rótulo descritivo, outro assunto, e a decisão #6 foi do **orquestrador**,
 * registrada na seção "decisões de baixo impacto que eu tomei sozinho" — o usuário
 * nunca a tomou. A justificativa dela também era falsa: ela afirmava que nenhuma das
 * 16 era consultada, e isso valia para 10, não para 16. Quem manda agora é a DEC-108.
 *
 * ## Interruptor **ou** teto
 *
 * Duas das sete são **limite** (`max_users_amount`, `max_invitations_amount`): o
 * controle é campo numérico, não toggle, porque um booleano não guarda "50". Quem
 * decide qual renderizar é o `kind` que o servidor manda, em `PermissionControl` —
 * a tela não tem tabela de chaves. Num teto, **vazio = sem limite** e **0 = nenhum
 * permitido**, que são coisas diferentes.
 */
export function PermissionsPage() {
  const eu = useAuthStore((s) => s.user)

  const papeis = useQuery({
    queryKey: ['user-types'],
    queryFn: () => userTypesApi.list(),
  })

  // O canal é o do PRÓPRIO operador: se alguém revogar uma permissão do papel dele
  // enquanto esta tela está aberta, ela se refaz. Assinar o canal de outra pessoa é
  // rejeitado pelo servidor de propósito (flag U2).
  const queryClient = useQueryClient()
  useChannel('PermissionsChannel', { user_id: eu?.id }, {
    received: (evt) => {
      if (evt?.type === 'permissions_changed') {
        queryClient.invalidateQueries({ queryKey: ['user-type-permissions'] })
      }
    },
  })

  if (papeis.isLoading) return <LoadingState label="Carregando papéis…" />
  if (papeis.isError) {
    return (
      <ErrorState
        description={
          (papeis.error as any)?.response?.status === 403
            ? 'Seu perfil não alcança a área de permissões.'
            : 'Não foi possível carregar os papéis.'
        }
        onRetry={() => papeis.refetch()}
      />
    )
  }

  const lista = papeis.data?.user_types ?? []

  return (
    <div className="space-y-6">
      <PageHeader
        title="Permissões"
        subtitle="O que cada papel pode fazer. A mudança vale na hora, sem recarregar."
      />

      <div className="flex items-start gap-2.5 rounded-lg border border-border bg-muted/40 p-3.5">
        <ShieldAlert aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
        <p className="text-xs text-muted-foreground">
          Você edita apenas papéis <span className="font-medium">abaixo do seu</span> na hierarquia — nunca o seu
          próprio, nunca um igual. É o que impede autopromoção. Para uma exceção em <span className="font-medium">uma
          pessoa</span>, use a aba «Permissões» da conta dela.
        </p>
      </div>

      {lista.length === 0 ? (
        <EmptyState title="Nenhum papel no seu alcance" description="Não há papel abaixo do seu para editar." />
      ) : (
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">
          {lista.map((papel) => (
            <CardDoPapel key={papel.id} papel={papel} />
          ))}
        </div>
      )}
    </div>
  )
}

function CardDoPapel({ papel }: { papel: UserTypeSummary }) {
  const queryClient = useQueryClient()
  const chave = ['user-type-permissions', papel.id]

  const dados = useQuery({
    queryKey: chave,
    queryFn: () => userTypesApi.permissions(papel.id),
    retry: false,
  })

  const alterar = useMutation({
    mutationFn: ({ key, mudanca }: { key: string; mudanca: PermissionChange }) =>
      userTypesApi.setPermission(papel.id, key, mudanca),
    onSuccess: (_r, { mudanca }) => {
      // DEC-108 — um teto não é "concedido" nem "revogado"; ele passa a valer um
      // número. Dizer "Concedida" para `limit_value: 0` seria mentir na tela.
      notify.success(
        'limit_value' in mudanca
          ? mudanca.limit_value === null || mudanca.limit_value === undefined
            ? `Sem limite para ${papel.display_name}. Vale agora para quem já existe.`
            : `Teto de ${mudanca.limit_value} para ${papel.display_name}. Vale agora para quem já existe.`
          : mudanca.granted
            ? `Concedida para ${papel.display_name}. Vale agora para quem já existe.`
            : `Revogada de ${papel.display_name}. Vale agora para quem já existe.`,
      )
      queryClient.invalidateQueries({ queryKey: chave })
    },
    onError: (erro: any) => {
      const code = erro?.response?.data?.details?.code
      notify.error(
        code === 'HIERARCHY_LOCKED'
          ? `${papel.display_name} está fora do seu alcance de hierarquia.`
          : erro?.response?.data?.message || 'Não foi possível alterar a permissão.',
      )
    },
  })

  const travado =
    (dados.error as any)?.response?.data?.details?.code === 'HIERARCHY_LOCKED'

  return (
    <section className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4">
      <header className="flex items-center gap-2">
        <BadgeCheck aria-hidden="true" className="h-4 w-4 text-muted-foreground" />
        <h2 className="flex-1 text-sm font-semibold text-card-foreground">{papel.display_name}</h2>
        {/* C3 — o nível é EXIBIDO, nunca usado em conta. A hierarquia do ai9 é
            invertida em relação à do legado (lá OG=1111, aqui OG=1), e quem
            fizer aritmética sobre este número acerta num sistema e erra no
            outro. Quem decide alcance é o servidor. */}
        <Badge variant="outline" className="font-numeric">nível {papel.hierarchy_level}</Badge>
      </header>

      {papel.description && <p className="text-xs text-muted-foreground">{papel.description}</p>}

      {dados.isLoading ? (
        <LoadingState size="inline" label="Carregando…" />
      ) : travado ? (
        <p className="rounded-md bg-muted px-3 py-2 text-xs text-muted-foreground">
          Fora do seu alcance de hierarquia — você não edita este papel.
        </p>
      ) : dados.isError ? (
        <ErrorState size="inline" description="Não consegui ler as permissões deste papel." onRetry={() => dados.refetch()} />
      ) : (
        <ul className="divide-y divide-border">
          {(dados.data?.permissions ?? []).map((p) => (
            <li key={p.key} className="flex items-start gap-3 py-2.5">
              <div className="min-w-0 flex-1">
                <label htmlFor={`${papel.id}-${p.key}`} className="block text-sm text-card-foreground">
                  {p.title}
                </label>
                {p.description && <p className="mt-0.5 text-xs text-muted-foreground">{p.description}</p>}
              </div>
              {/* Toggle ou campo numérico conforme o `kind` do servidor (DEC-108).
                  `editable` também vem do SERVIDOR: a tela não recalcula
                  hierarquia — ver o item 3 no cabeçalho. */}
              <PermissionControl
                row={p}
                idPrefix={String(papel.id)}
                disabled={!dados.data?.editable || alterar.isPending}
                onChange={(mudanca) => alterar.mutate({ key: p.key, mudanca })}
              />
            </li>
          ))}
        </ul>
      )}

      {dados.data && !dados.data.editable && !travado && (
        <p className="text-xs text-muted-foreground">Somente leitura para o seu papel.</p>
      )}
    </section>
  )
}

// Nota de desenho: **cada card faz a própria consulta**, em vez de um `useQueries`
// só. É o que permite um papel fora do alcance de hierarquia falhar sozinho, com a
// explicação dentro do próprio card, sem derrubar a tela inteira — que é exatamente
// o caso do Admin olhando o card do OG.
