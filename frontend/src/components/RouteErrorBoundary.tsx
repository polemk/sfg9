import { Component, type ErrorInfo, type ReactNode } from 'react'
import { ClientCrashPage } from '@/app/pages/ErrorPages'

interface Props {
  children: ReactNode
}

interface State {
  error: Error | null
}

/**
 * A rede de segurança do console (OPS-634 / tarefa F.4).
 *
 * Sem ela, uma exceção em qualquer tela desmonta a árvore inteira do React e o
 * usuário fica com **tela branca** — o mesmo sintoma do 404 que a rota curinga
 * resolveu, por outra causa. É o irmão de runtime do `MissingTemplate` do
 * legado, que virava 500 com stack trace na cara do usuário.
 *
 * Aqui a falha vira a tela de **queda no cliente** — não a de 500.
 *
 * A distinção não é preciosismo: a tela de 500 diz "algo quebrou do nosso lado"
 * e "a falha foi registrada", e as duas coisas são falsas para uma exceção do
 * navegador. Quem abre chamado com esse texto manda o time procurar no log do
 * servidor, onde não há nada — foi assim que o `Cannot read properties of null
 * (reading 'trim')` do detalhe de projeto chegou como se fosse defeito de API.
 *
 * A moldura é a mesma das outras, com a mensagem do erro num bloco monoespaçado
 * (é o que vai para o chamado) e um botão de tentar de novo que **remonta** em
 * vez de recarregar a página.
 */
export class RouteErrorBoundary extends Component<Props, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    // Console é o destino por enquanto: não há coletor de erro no produto, e
    // inventar um aqui seria decidir telemetria numa fatia de navegação.
    console.error('[RouteErrorBoundary]', error, info.componentStack)
  }

  render() {
    if (this.state.error) {
      return (
        <ClientCrashPage
          detail={this.state.error.message}
          onRetry={() => this.setState({ error: null })}
        />
      )
    }
    return this.props.children
  }
}
