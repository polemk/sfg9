import { Navigate } from 'react-router-dom'
import { useAuthStore } from '@/store/authStore'
import { useRoleSlug } from '@/hooks/useNavItems'
import { useCurrentProject } from '@/hooks/useCurrentProject'
import { LoadingState } from '@/components/ui/States'
import { MOUNTED_AREAS, type RoleSlug } from '@/app/consoleNavigation'

/**
 * FE-404 — **o redirecionador por papel**, e é só isso que o `dash` do legado é.
 *
 * ### Não existe dashboard, e isso é decisão (DC-15 / DEC-09)
 *
 * Os 3 endpoints de `dash` do legado estão **quebrados por template ausente**
 * (`MissingTemplate`), o `search` calcula um período e **não consulta nada**
 * (D-87), e não há model, view SQL, materialized view nem job que alimente
 * indicador (DB-399). O que existe de verdade em `dash/_body.js.erb:8-22` é um
 * `switch` de papel que manda o usuário para outra área — e é isso, e só isso,
 * que vira spec aqui.
 *
 * Um dashboard de verdade **existe** no plano: é a `NEW-002` (DEC-21.2), fatia
 * **S15**, depois dos serviços de cálculo — dashboard bonito sobre número
 * errado é pior que dashboard nenhum.
 *
 * ### O destino, papel a papel (a tabela do legado, sem alteração)
 *
 * | Papel | Sem projeto | Com projeto |
 * | ----- | ----------- | ----------- |
 * | OG | usuários | usuários |
 * | Admin, Gerente | projetos | recebíveis |
 * | Colaborador | minha conta | resultados |
 *
 * O `/` do Safegold é a **tela de login** (DEC-13.3). Este componente só entra
 * em cena quando já existe sessão — aí a raiz deixa de ser login e passa a ser
 * o encaminhamento por papel.
 */

/** Áreas que ainda não têm rota montada caem no `/dashboard`, nunca em 404. */
const FALLBACK = '/dashboard'

export function destinoPorPapel(
  papel: RoleSlug | null,
  temProjeto: boolean,
  rotasMontadas: (path: string) => boolean,
): string {
  const escolha = (() => {
    if (papel === 'og') return '/users'
    if (papel === 'admin' || papel === 'gerente') return temProjeto ? '/receivables' : '/projects'
    // Colaborador e papel desconhecido: o conjunto mais restrito.
    return temProjeto ? '/risk' : '/profile'
  })()

  return rotasMontadas(escolha) ? escolha : FALLBACK
}

export function RootRedirect({ fallback }: { fallback: React.ReactNode }) {
  const isAuthenticated = useAuthStore((s) => s.isAuthenticated)
  const papel = useRoleSlug()
  const { hasProject, isLoading } = useCurrentProject()

  // Sem sessão a raiz é o login (DEC-13.3) — quem renderiza é quem chamou.
  if (!isAuthenticated) return <>{fallback}</>

  // Redirecionar antes de saber se há projeto mandaria Admin para "projetos"
  // mesmo tendo projeto. Esperar aqui custa um piscar; errar custa uma tela.
  if (isLoading) return <LoadingState label="Abrindo o console…" />

  return <Navigate to={destinoPorPapel(papel, hasProject === true, rotaMontada)} replace />
}

function rotaMontada(path: string): boolean {
  return MOUNTED_AREAS.some((a) => a.path === path)
}
