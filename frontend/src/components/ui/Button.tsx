import * as React from 'react'
import { cn } from '@/lib/utils'
import { Spinner } from './Spinner'

/**
 * Botão canônico do Safegold — **o único** do app.
 *
 * São cinco variantes e não há uma sexta. Se uma tela precisa de um botão que
 * não é nenhuma delas, a resposta é escolher a mais próxima, não criar variante
 * nem re-estilizar por cima com `className` de cor. Dois botões da mesma
 * variante têm que renderizar idênticos em qualquer lugar do app.
 *
 *  primary      preenchimento sólido de ouro Safegold. A ação principal da tela.
 *               No máximo um por bloco.
 *  secondary    contorno discreto sobre a superfície. A ação alternativa
 *               (cancelar, voltar, filtrar). Cobre o antigo `outline`.
 *  ghost        sem traço nem fundo até o hover. Ação de ícone, item de barra,
 *               ação terciária dentro de linha de tabela.
 *  destructive  sólido vermelho. Só para o que apaga/encerra de verdade.
 *  link         texto sublinhado no hover. Navegação disfarçada de botão.
 *
 * Sem gradiente, sem borda animada, sem glow. Cor vem SÓ de token
 * (`bg-primary`, `border-input`…) — nunca `#hex` nem `bg-blue-600`.
 *
 * `loading` é estado, não variante. Com ele o botão fica desabilitado, troca o
 * conteúdo por um `Spinner` e **preserva a largura** que tinha com o rótulo —
 * um botão que encolhe ao ser clicado move o que está do lado dele. O rótulo
 * continua no DOM (invisível) exatamente para isso.
 */
export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'destructive' | 'link'
export type ButtonSize = 'default' | 'sm' | 'lg' | 'icon'

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant
  size?: ButtonSize
  /** Trabalho em andamento: desabilita, mostra o spinner e trava a largura. */
  loading?: boolean
}

const baseStyles =
  'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md font-medium ' +
  'ring-offset-background transition-colors focus-visible:outline-none focus-visible:ring-2 ' +
  'focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none ' +
  'disabled:opacity-50 [&_svg]:shrink-0'

const variants: Record<ButtonVariant, string> = {
  primary: 'bg-primary text-primary-foreground shadow-e1 hover:bg-brand-gold-deep',
  secondary: 'border border-input bg-background text-foreground hover:bg-accent hover:text-accent-foreground',
  ghost: 'text-foreground hover:bg-accent hover:text-accent-foreground',
  destructive: 'bg-destructive text-destructive-foreground shadow-e1 hover:bg-destructive/90',
  link: 'text-foreground underline-offset-4 hover:underline hover:text-primary',
}

/**
 * **No telefone todo botão tem ao menos 44 px de altura** — critério 1 da §5.4.8.
 *
 * As alturas do desktop (`h-10` = 40, `h-9` = 36, `h-10` no ícone) são alvos de
 * ponteiro. A passada de mobile mediu isto em **31 das 33 telas auditadas**: o
 * "Novo portador", o "Filtros", o "Cancelar" e o "Criar renegociação" ficavam
 * todos abaixo do mínimo, no aparelho em que a pessoa usa o polegar.
 *
 * A correção fica **aqui, no botão**, e não em cada chamada com
 * `className="min-h-[3rem]"`: são centenas de call sites e a próxima tela
 * esqueceria — que é exatamente o modo de falha que o DEC-100 nomeia.
 *
 * ## Por que `max-md:` e não `md:` — e isto quebrou uma tela
 *
 * A primeira versão foi `min-h-[2.75rem] … md:min-h-0 md:h-10`, achando que
 * "restaurar no `md`" bastava. **Não basta:** o Tailwind emite as variantes
 * DEPOIS das classes base, então `md:h-10` passa a vencer qualquer `h-*` que o
 * chamador mande por `className`.
 *
 * Quem pagou foi o `SidebarSelectorCard`, que passa `h-auto` de propósito —
 * rótulo em cima e valor embaixo precisam de duas linhas. Com `md:h-10` no
 * botão, o card virou 40 px fixos e o conteúdo ficou espremido. O usuário viu
 * antes de mim.
 *
 * Com `max-md:`, o CSS de desktop volta a ser **byte a byte o de antes** —
 * `h-10` base, sobrescrevível pelo chamador como sempre foi — e o mínimo de
 * toque existe só onde ele importa, abaixo de 768 px. O `max-md:h-auto`
 * acompanha o `min-h` porque altura fixa e altura mínima brigam entre si.
 */
const sizes: Record<ButtonSize, string> = {
  default: 'h-10 px-5 py-2 text-sm max-md:h-auto max-md:min-h-[2.75rem]',
  sm: 'h-9 px-4 text-sm max-md:h-auto max-md:min-h-[2.75rem]',
  lg: 'h-11 px-8 text-base',
  icon: 'h-10 w-10 p-0 max-md:h-auto max-md:w-auto max-md:min-h-[2.75rem] max-md:min-w-[2.75rem]',
}

const spinnerSize: Record<ButtonSize, 'xs' | 'sm' | 'md'> = {
  default: 'sm',
  sm: 'xs',
  lg: 'sm',
  icon: 'sm',
}

const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  (
    { className, variant = 'primary', size = 'default', type = 'button', loading = false, disabled, children, ...props },
    ref,
  ) => (
    <button
      type={type}
      ref={ref}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      className={cn(
        baseStyles,
        variants[variant],
        sizes[size],
        // Carregando NÃO é desabilitado visualmente: o `disabled` existe só
        // para bloquear o segundo clique. Deixar em 50% de opacidade faz o
        // botão parecer quebrado no meio da própria ação — no escuro, o ouro
        // a 50% vira um marrom que ninguém reconhece como botão.
        loading && 'relative cursor-wait disabled:opacity-100',
        className,
      )}
      {...props}
    >
      {loading && (
        <span className="absolute inset-0 flex items-center justify-center">
          <Spinner size={spinnerSize[size]} label={null} />
        </span>
      )}
      <span className={cn('contents', loading && 'invisible')}>{children}</span>
    </button>
  ),
)
Button.displayName = 'Button'

export { Button }
