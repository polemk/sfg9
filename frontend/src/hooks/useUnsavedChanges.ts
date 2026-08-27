import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'

/**
 * **S2 / FE-400 — o aviso antes de perder o que foi digitado.**
 *
 * O legado tinha uma barra inferior de ações pendentes
 * (`dashBottomHolder` + `ActionStack`, `bottom_bar/_container.js.erb`) e, ainda
 * assim, **descartava a edição em silêncio** ao navegar: o `go()` do console
 * fechava a gaveta e limpava o holder sem perguntar nada. Quem tinha meia hora
 * de borderô preenchido clicava num item de menu e perdia tudo.
 *
 * Pior: o `cancel()` daquela barra montava `{ reload: defaultReload() }` — com
 * os parênteses — e portanto **executava** a recarga na hora de montar o
 * objeto, em vez de guardar a função. Descartar recarregava a página inteira
 * antes da hora. É o bug que a tarefa 4.7 manda corrigir, e a correção é não
 * recarregar nada: descartar restaura os valores **em memória**.
 *
 * ### Por que a interceptação é por clique, e não por `useBlocker`
 *
 * O `useBlocker` do react-router só existe em **data router**
 * (`createBrowserRouter`). Este app monta `<BrowserRouter>` em `main.tsx`, e
 * trocar o tipo de roteador para ganhar um aviso de formulário seria refatorar
 * a base por causa de uma tela (Princípio 6b). Então:
 *
 * - **saída do navegador** (fechar aba, recarregar, voltar para fora do app) →
 *   `beforeunload`, que é o único mecanismo que o navegador oferece e que
 *   funciona em qualquer roteador;
 * - **navegação dentro do app** → escuta de clique na **fase de captura** sobre
 *   os `<a href>` internos. A barra lateral, a topbar e as migalhas usam
 *   `NavLink`/`Link`, que renderizam `<a href>` de verdade — é por isso que
 *   isto pega o caminho real de saída, e não só o botão da própria tela.
 *
 * **O que ele NÃO pega, dito na cara:** o botão Voltar do navegador dentro do
 * SPA (`popstate` já aconteceu quando o evento chega, e desfazê-lo exige
 * empilhar uma entrada sentinela — um truque que quebra o histórico de verdade
 * que a S2 construiu, FE-397) e as chamadas programáticas de `navigate()` que
 * não passarem por aqui. Para essas, a tela chama `confirmarSaida()` no seu
 * próprio botão — é o que o formulário de borderô faz no "Cancelar".
 *
 * ### Uso
 *
 * ```tsx
 * const saida = useUnsavedChanges(alterado)
 * // …
 * <ConfirmDialog open={saida.perguntando} onOpenChange={saida.cancelar}
 *                onConfirm={saida.confirmar} … />
 * ```
 */
export interface UnsavedChangesGuard {
  /** Há uma saída represada esperando resposta. */
  perguntando: boolean
  /** Deixa a saída acontecer (e some com o aviso). */
  confirmar: () => void
  /** Fica na tela. */
  cancelar: () => void
  /**
   * Represa uma saída programática. Devolve `true` se perguntou (a tela **não**
   * deve navegar) e `false` se não havia nada a perder (pode navegar).
   */
  interceptar: (ir: () => void) => boolean
}

export function useUnsavedChanges(alterado: boolean): UnsavedChangesGuard {
  // A saída represada mora numa **ref**, e só o "há alguma?" é estado.
  //
  // Guardá-la no `useState` obrigaria a executá-la de dentro do atualizador
  // (`setPendente(atual => { atual(); return null })`), e atualizador do React
  // tem que ser puro: em `StrictMode` ele roda duas vezes, e a navegação
  // aconteceria duas vezes. É a mesma classe de erro do `cancel()` do legado —
  // efeito colateral no lugar errado.
  const pendente = useRef<(() => void) | null>(null)
  const [perguntando, setPerguntando] = useState(false)
  const navigate = useNavigate()

  // O listener de clique é instalado uma vez e lê o `alterado` por ref: sem
  // isso ele precisaria ser reinstalado a cada tecla digitada no formulário.
  const alteradoRef = useRef(alterado)
  alteradoRef.current = alterado

  // O `navigate` é estável no react-router 6, mas ler por ref tira a dúvida e
  // mantém o listener de clique instalado uma vez só.
  const navigateRef = useRef(navigate)
  navigateRef.current = navigate

  // Fechar a aba / recarregar. O texto é do navegador — desde 2016 nenhum deles
  // exibe mensagem customizada, e insistir numa string aqui só engana quem lê o
  // código.
  useEffect(() => {
    if (!alterado) return
    const aviso = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', aviso)
    return () => window.removeEventListener('beforeunload', aviso)
  }, [alterado])

  // Navegação por link interno. Fase de **captura**, para chegar antes do
  // handler do `Link` do react-router.
  useEffect(() => {
    function aoClicar(evento: MouseEvent) {
      if (!alteradoRef.current) return
      // Cliques com modificador abrem em outra aba: esta tela não perde nada.
      if (evento.defaultPrevented || evento.button !== 0) return
      if (evento.metaKey || evento.ctrlKey || evento.shiftKey || evento.altKey) return

      const alvo = (evento.target as HTMLElement | null)?.closest?.('a')
      if (!alvo) return

      const href = alvo.getAttribute('href')
      if (!href || href.startsWith('#')) return
      if (alvo.target && alvo.target !== '_self') return
      if (alvo.hasAttribute('download')) return

      // **Interno = `href` começando com `/` (e não `//`).** Todas as rotas do
      // `consoleNavigation` são caminhos absolutos do app, e é assim que o
      // `Link` as renderiza.
      //
      // Comparar `new URL(a.href).origin` com `window.location.origin` parece
      // mais rigoroso e **não é**: o `a.href` é resolvido contra a `<base>` do
      // documento, e a `location` contra a URL real. As duas divergem quando há
      // `<base>` — e divergem no jsdom, onde o anchor resolveu para
      // `http://localhost:3000/outra` com a `location` em `http://localhost/`.
      // A checagem "mais segura" simplesmente desligava a guarda inteira, em
      // silêncio. Achado rodando o teste, não lendo o código.
      const externo = /^[a-z][a-z0-9+.-]*:/i.test(href) || href.startsWith('//')
      if (externo) return

      const destino = new URL(href, window.location.origin)
      // Já estamos nele: não é saída.
      if (destino.pathname + destino.search === window.location.pathname + window.location.search) return

      evento.preventDefault()
      evento.stopPropagation()
      // A saída é represada como FUNÇÃO. Guardar `navigate(destino)` já chamado
      // é exatamente o bug do `cancel()` do legado — a ação aconteceria agora, e
      // não quando o usuário confirmasse.
      //
      // E a saída é pelo ROTEADOR (`navigate`), não por `location.assign`:
      // recarregar a aplicação inteira para trocar de tela é o que o legado
      // fazia e o que a S2 tirou (FE-397).
      pendente.current = () => navigateRef.current(destino.pathname + destino.search + destino.hash)
      setPerguntando(true)
    }

    document.addEventListener('click', aoClicar, true)
    return () => document.removeEventListener('click', aoClicar, true)
  }, [])

  const confirmar = useCallback(() => {
    const ir = pendente.current
    pendente.current = null
    setPerguntando(false)
    ir?.()
  }, [])

  const cancelar = useCallback(() => {
    pendente.current = null
    setPerguntando(false)
  }, [])

  const interceptar = useCallback((ir: () => void) => {
    if (!alteradoRef.current) {
      ir()
      return false
    }
    pendente.current = ir
    setPerguntando(true)
    return true
  }, [])

  return { perguntando, confirmar, cancelar, interceptar }
}
