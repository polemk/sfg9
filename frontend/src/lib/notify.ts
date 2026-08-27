import type { ReactNode } from 'react'
import { toast as sonner } from 'sonner'

/**
 * Notificações — o `M.push(...)` do legado, mapeado para o `sonner` do ai9.
 *
 * O legado tinha uma classe `M` (`app/frontend/js/msg_helper.js.erb`) com nove
 * estilos, mas só quatro eram usados de fato: `SUCCESS`, `ERROR`, `WARNING` e
 * `HELP`. Os cinco `NEGATIVE_*` eram variações de **cor de fundo** literal
 * (`COLOR__RED`, `COLOR__ACCENT`, `COLOR__ACCENT_AUX`…) — não eram tipos de
 * mensagem, eram tinta. Não sobrevivem: cor de aviso vem do token semântico.
 *
 * O de-para, para quem for portar tela (FE-410):
 *
 * | Legado                | Aqui                | Observação                          |
 * | --------------------- | ------------------- | ----------------------------------- |
 * | `M.push(t, M.SUCCESS)`| `notify.success(t)` | título padrão "Concluído"           |
 * | `M.push(t, M.ERROR)`  | `notify.error(t)`   | título padrão "Houve um problema"   |
 * | `M.push(t, M.WARNING)`| `notify.warning(t)` | era o "Confirmar" — ver `confirm()` |
 * | `M.push(t, M.HELP)`   | `notify.info(t)`    | o único que não sumia sozinho       |
 * | `M.NEGATIVE_*`        | —                   | era cor literal, não tipo           |
 *
 * Duas regras que vêm do comportamento observado no legado e que o app mantém:
 *
 * - **Ajuda não some sozinha.** No legado, `M.HELP` era o único com
 *   `allowToastClose` e ficava 8s; texto de ajuda que evapora em 3s não é
 *   ajuda. Aqui `info` fica até o usuário fechar.
 * - **Erro dura mais que sucesso.** Sucesso é confirmação (o usuário já sabe o
 *   que fez); erro é informação nova que ele precisa ler.
 *
 * **Toast não é tratamento de erro de carregamento.** Para falha de consulta
 * use `ErrorState`/`AsyncSection`, que ficam na tela e oferecem "tentar de
 * novo". O toast some, e a tela vazia atrás dele é indistinguível de "não há
 * nada" — foi assim que o legado ficou sem estado de erro (FE-401).
 */
const DURACAO = {
  success: 3000,
  error: 8000,
  warning: 6000,
  /** `Infinity`: fica até o usuário fechar. */
  info: Infinity,
} as const

export interface NotifyOptions {
  /** Linha de apoio abaixo do título. */
  description?: string
  duration?: number
  action?: { label: string; onClick: () => void }
  /**
   * Onde o aviso aparece. Raro de precisar — o padrão do `<Toaster>` vale para
   * o app inteiro, e mover um aviso de lugar sem motivo confunde quem já sabe
   * onde olhar.
   *
   * Existe porque o aviso de código de desenvolvimento (`CodeValidation`) fica
   * no topo, para não tapar o campo em que a pessoa vai digitar o código.
   */
  position?: 'top-center' | 'top-right' | 'top-left' | 'bottom-center' | 'bottom-right' | 'bottom-left'
}

export const notify = {
  /** `M.SUCCESS` — confirmação de algo que o usuário acabou de fazer. */
  success(message: ReactNode, options?: NotifyOptions) {
    return sonner.success(message, { duration: DURACAO.success, ...options })
  },

  /** `M.ERROR` — a ação falhou. Diga o que falhou, não "erro inesperado". */
  error(message: ReactNode, options?: NotifyOptions) {
    return sonner.error(message, { duration: DURACAO.error, ...options })
  },

  /** `M.WARNING` — deu certo, mas com ressalva que o usuário precisa ver. */
  warning(message: ReactNode, options?: NotifyOptions) {
    return sonner.warning(message, { duration: DURACAO.warning, ...options })
  },

  /** `M.HELP` — orientação. Fica na tela até ser fechada. */
  info(message: ReactNode, options?: NotifyOptions) {
    return sonner.info(message, { duration: DURACAO.info, closeButton: true, ...options })
  },

  /**
   * Progresso de uma ação assíncrona: um toast só, que troca de estado.
   * Substitui o padrão do legado de empilhar "salvando…" e depois "salvo!".
   */
  promise<T>(p: Promise<T>, msgs: { loading: string; success: string | ((d: T) => string); error: string | ((e: unknown) => string) }) {
    return sonner.promise(p, msgs)
  },

  dismiss(id?: string | number) {
    return sonner.dismiss(id)
  },
}

/** Extrai a mensagem que o servidor mandou; cai num texto útil se não houver. */
export function mensagemDaFalha(error: unknown, padrao = 'Não foi possível concluir a ação.'): string {
  if (!error) return padrao
  if (typeof error === 'string') return error
  const e = error as any
  return e?.response?.data?.error ?? e?.response?.data?.message ?? e?.message ?? padrao
}
