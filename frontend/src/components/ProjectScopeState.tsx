import { FolderKanban, Users } from 'lucide-react'
import { EmptyState } from '@/components/ui/States'

/**
 * **Os dois 409 do escopo de projeto, tratados como ESTADO — nunca como erro.**
 *
 * `current_project!` responde três coisas diferentes, e antes elas eram um 404
 * só (`controller_helpers.rb`):
 *
 * | Situação | Resposta | O que a tela mostra |
 * | -------- | -------- | ------------------- |
 * | pediu um projeto que não enxerga | **404 `PROJECT_NOT_FOUND`** | erro de verdade |
 * | tem projetos e não escolheu | **409 `PROJECT_NOT_SELECTED`** | "escolha um projeto" |
 * | não participa de nenhum | **409 `PROJECT_NONE_AVAILABLE`** | "fale com um administrador" |
 *
 * As duas últimas **não são falha**: são o sistema esperando uma escolha, ou
 * dizendo que não há o que mostrar. Uma página de erro vermelha para "você ainda
 * não escolheu o projeto" faz o usuário procurar um problema que não existe. E
 * mostrá-las como vazio genérico ("nenhum indicador") é pior: afirma que o dado
 * não existe quando o que falta é o escopo.
 *
 * O 404 continua indistinguível entre id inexistente e id alheio — a
 * anti-enumeração não foi relaxada, e há spec provando a igualdade do corpo.
 *
 * ## Por que este arquivo existe uma vez só
 *
 * Ele nasceu **duas** vezes no mesmo dia: `ProjectScopeState` (S9, S10) e
 * `ProjectScopeState` (S5, S11), com props diferentes, nomes de função
 * diferentes e quatro textos diferentes para as mesmas duas situações. Nenhuma
 * das duas estava errada — as quatro fatias tinham o mesmo problema ao mesmo
 * tempo e nenhuma sabia da outra.
 *
 * A fusão pegou o melhor de cada, não a que chegou primeiro:
 *
 * - o **`recurso`** veio do `Notice` — "As renegociações são de um projeto por
 *   vez" diz mais do que "Esta tela mostra dados de um projeto";
 * - a **conferência do status 409** veio do `Notice`: casar só pelo `code` deixa
 *   passar qualquer resposta que carregue essa string em outro status;
 * - o **"na barra lateral"** veio do `State`, e é o texto correto — o ai9 não tem
 *   topbar, o seletor de projeto vive na barra lateral;
 * - o **"não há nada a corrigir aqui"** veio do `State`: é a frase que impede a
 *   pessoa de ficar procurando o próprio erro.
 *
 * O nome ficou `State` porque é o que estes componentes **são**, e é o
 * vocabulário que o resto da biblioteca já usa (`States.tsx`,
 * `MobileListState`). "Notice" sugere aviso passageiro; isto é o conteúdo da
 * tela enquanto o escopo não existe.
 */
export type ProjectScopeCode = 'PROJECT_NOT_SELECTED' | 'PROJECT_NONE_AVAILABLE'

/**
 * O código de escopo do erro, ou `null` quando o erro é outra coisa.
 *
 * Confere o **status** além do código: o `code` sozinho é uma string qualquer, e
 * casar só por ela transforma qualquer resposta que a carregue — um 500 com eco
 * do payload, um proxy — em "escolha um projeto".
 */
export function projectScopeCode(erro: unknown): ProjectScopeCode | null {
  const e = erro as { response?: { status?: number; data?: { code?: string } } }
  if (e?.response?.status !== 409) return null
  const codigo = e.response?.data?.code
  return codigo === 'PROJECT_NOT_SELECTED' || codigo === 'PROJECT_NONE_AVAILABLE' ? codigo : null
}

export interface ProjectScopeStateProps {
  code: ProjectScopeCode
  /** O que a tela mostraria — entra na frase para o aviso não ser genérico. */
  recurso?: string
}

export function ProjectScopeState({ code, recurso = 'Estes dados' }: ProjectScopeStateProps) {
  const assunto = maiuscula(recurso)

  if (code === 'PROJECT_NONE_AVAILABLE') {
    return (
      <EmptyState
        icon={<Users aria-hidden="true" className="h-5 w-5 text-muted-foreground" />}
        title="Você ainda não participa de nenhum projeto"
        description={`${assunto} são sempre de um projeto. Peça a um administrador para incluir você em um — não há nada a corrigir aqui.`}
      />
    )
  }

  return (
    <EmptyState
      icon={<FolderKanban aria-hidden="true" className="h-5 w-5 text-muted-foreground" />}
      title="Escolha um projeto para continuar"
      description={`${assunto} são de um projeto por vez. Use o seletor de projeto na barra lateral para escolher qual você quer ver.`}
    />
  )
}

function maiuscula(texto: string) {
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}
