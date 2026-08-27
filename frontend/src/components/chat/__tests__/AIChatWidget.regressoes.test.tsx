import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const RAIZ = resolve(__dirname, '../../../..')
const ler = (caminho: string) => readFileSync(resolve(RAIZ, caminho), 'utf-8')

/** O código sem comentários — as varreduras procuram o que o navegador executa. */
function semComentarios(caminho: string): string {
  return ler(caminho)
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .filter((linha) => !linha.trim().startsWith('//'))
    .join('\n')
}

const WIDGET = 'src/components/chat/AIChatWidget.tsx'
const LISTA_MOBILE = 'src/features/chat-builder/MobileFlowListPage.tsx'

describe('AIChatWidget — o que já quebrou uma vez', () => {
  /**
   * **O botão de minimizar não fazia nada.**
   *
   * `handleMinimize` trocava `isMinimized` desde sempre, mas a variável não era
   * lida em NENHUM lugar do segundo layout do widget — havia dois no mesmo
   * arquivo, e só o primeiro implementava o encolhimento. O React
   * re-renderizava e a tela ficava igual.
   *
   * O exemplo exige que o estado seja LIDO depois do segundo `return`, que é
   * onde ele faltava.
   */
  it('o segundo layout LÊ `isMinimized` — sem isso o botão volta a não fazer nada', () => {
    const fonte = semComentarios(WIDGET)
    // `z-drawer` só existe no segundo layout — é a âncora estável. Usar o
    // último `return (` pegava o de uma função interna, não o do componente.
    const inicio = fonte.indexOf('z-drawer')
    expect(inicio).toBeGreaterThan(-1)
    const segundoLayout = fonte.slice(inicio)

    expect(segundoLayout).toContain('isMinimized')
    // A altura tem de depender do estado: era `lg:h-[600px]` fixo.
    expect(segundoLayout).toMatch(/isMinimized \?[^\n]*h-\[/)
  })

  /**
   * **A persona de reserva mostrava a foto de uma pessoa real do time do ai9.**
   *
   * `/images/team/vini.webp`. A pasta inteira saiu; o fallback é a marca.
   */
  it('nenhuma foto de pessoa como persona de reserva', () => {
    // `semComentarios`: o comentário do conserto CITA o caminho removido, e sem
    // isto o exemplo reprovaria o arquivo que o consertou — o incentivo passaria
    // a ser não escrever o porquê.
    const fonte = semComentarios(WIDGET)

    expect(fonte).not.toContain('/images/team/')
    expect(fonte).toContain('/images/brand/safegold-icon')
  })

  /**
   * `/images/avatars/default.png` era referenciado duas vezes e não existia —
   * persona sem avatar mostrava imagem quebrada.
   */
  it('não aponta para `/images/avatars/`, que não existe mais', () => {
    expect(semComentarios(WIDGET)).not.toContain('/images/avatars/')
  })
})

describe('MobileFlowListPage — dado falso não volta', () => {
  /**
   * Três personas inventadas entravam no mapa ANTES dos fluxos reais, então
   * apareciam sempre. E os papéis vinham do CRM do ai9 (AI9-006), `removed`
   * nesta migração. É o mesmo defeito que o FE-011 fechou na tela de contas.
   */
  it('sem personas inventadas na lista', () => {
    const fonte = semComentarios(LISTA_MOBILE)

    expect(fonte).not.toContain('Marta Atendimento')
    expect(fonte).not.toContain('Anna Assistente')
    expect(fonte).not.toContain('Maju AI')
    expect(fonte).not.toContain('Gestão de Leads')
  })

  /**
   * `api.dicebear.com` recebia o NOME da persona a cada render, de dentro do
   * console de um cliente de crédito — e o CSP já bloqueava o domínio, então
   * era vazamento sem contrapartida. O FE-427 tirou das outras telas; esta
   * ficou para trás.
   */
  it('não manda nome de persona para serviço de terceiro', () => {
    expect(semComentarios(LISTA_MOBILE)).not.toContain('dicebear')
  })
})
