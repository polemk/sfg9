import { useQuery } from '@tanstack/react-query'
import { FolderKanban } from 'lucide-react'
import { Badge } from '@/components/ui/Badge'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { projectsApi } from '@/lib/api/projects'

/**
 * **Os projetos de um usuário** (FE-118 / BE-100 / DC-18) — a seção
 * informativa do detalhe da conta.
 *
 * **Informativa é a palavra:** ela mostra, não gerencia. Quem concede e revoga
 * participação é a aba "Membros" **do projeto**, onde as três condições de
 * servidor valem (não-readonly, não remover o dono, não remover a si mesmo).
 * Dar um botão de remover aqui seria a quarta rota para a mesma coisa, com as
 * condições reimplementadas — foi assim que o legado chegou ao D-34.
 *
 * O servidor devolve a **interseção** entre a participação do alvo e a
 * visibilidade de quem pergunta: um Gerente não descobre, pelo perfil de outra
 * pessoa, que existe um projeto que ele mesmo não enxerga.
 */
export function UserProjectsSection({ userId }: { userId: string }) {
  const projetos = useQuery({
    queryKey: ['user-projects', userId],
    queryFn: () => projectsApi.ofUser(userId),
    enabled: Boolean(userId),
  })

  return (
    <div className="space-y-2">
      <h3 className="flex items-center gap-2 text-sm font-medium text-foreground">
        <FolderKanban aria-hidden="true" className="h-4 w-4" />
        Projetos
      </h3>

      <AsyncSection
        loading={projetos.isLoading}
        error={projetos.isError ? projetos.error : undefined}
        data={projetos.data}
        onRetry={() => projetos.refetch()}
        loadingLabel="Carregando projetos…"
        emptyTitle="Não participa de nenhum projeto"
        emptyDescription="A participação é concedida na aba «Membros» do projeto."
      >
        {(lista) => (
          <ul className="divide-y divide-border rounded-lg border border-border bg-card">
            {lista.map((p) => (
              <li key={p.id} className="flex items-center gap-3 px-3 py-2">
                <span className="min-w-0 flex-1 truncate text-sm text-card-foreground">{p.name}</span>
                {p.is_active ? (
                  <Badge variant="success">Ativo</Badge>
                ) : (
                  <Badge variant="secondary">Inativo</Badge>
                )}
              </li>
            ))}
          </ul>
        )}
      </AsyncSection>

      <p className="text-xs text-muted-foreground">
        Somente leitura. Para conceder ou revogar, use a aba «Membros» do projeto.
      </p>
    </div>
  )
}
