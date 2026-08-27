import * as React from 'react'
import { cn } from '@/lib/utils'

/**
 * Avatar de usuário — foto quando existe, iniciais tokenizadas quando não.
 *
 * Substitui as chamadas a `api.dicebear.com` que estavam espalhadas pelas telas.
 * Duas razões, nesta ordem:
 *  1. o dicebear sorteia a cor de fundo pelo hash do nome, o que colocava
 *     vermelho, roxo e verde-limão aleatórios no meio de uma interface grafite
 *     e ouro — cor fora da marca, e fora de qualquer token;
 *  2. era uma requisição a um terceiro para desenhar duas letras: dependência
 *     de rede, e o nome do usuário saindo do domínio numa query string.
 *
 * **Cor determinística (FE-427).** Passando `colorKey` (o id do usuário, de
 * preferência — nunca o nome, que muda), o avatar ganha um matiz estável: o
 * mesmo id dá sempre o mesmo tom, em qualquer tela e em qualquer render. O
 * legado sorteava a cor **a cada render** e a inicial "piscava" ao rolar a
 * lista; era o mesmo usuário mudando de cor entre a linha da tabela e o
 * cabeçalho da tela.
 *
 * A paleta é fechada e feita **de tokens** (`primary`, `brand-steel`,
 * `success`, `info`, `warning`, `negative`, cada um com fundo a 15% e texto
 * cheio). Não é `hsl(hash % 360)`: matiz livre produz rosa-choque e verde-limão
 * no meio de uma interface grafite e ouro, e não muda com o tema.
 */
export interface UserAvatarProps extends React.HTMLAttributes<HTMLSpanElement> {
  name?: string | null
  email?: string | null
  src?: string | null
  /** Lado do quadrado, em px. */
  size?: number
  /**
   * Chave da cor determinística — use o **id** do registro. Sem ela, o avatar
   * fica no tom neutro (`muted`), que é o comportamento anterior.
   */
  colorKey?: string | number | null
}

/**
 * Paleta fechada de tons de avatar. Só token — muda sozinha entre claro e
 * escuro, como todo o resto.
 */
const TONS = [
  'bg-primary/20 text-foreground',
  'bg-brand-steel/20 text-foreground',
  'bg-success/20 text-foreground',
  'bg-info/20 text-foreground',
  'bg-warning/25 text-foreground',
  'bg-negative/20 text-foreground',
] as const

/**
 * Hash estável (djb2). Precisa ser **puro e determinístico**: `Math.random`,
 * `Date.now` ou a ordem de render não podem participar — foi assim que a cor
 * do legado passou a mudar a cada pintura.
 */
export function avatarTone(key: string | number): string {
  const s = String(key)
  let h = 5381
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) >>> 0
  return TONS[h % TONS.length]
}

function initialsOf(name?: string | null, email?: string | null): string {
  const source = (name || '').trim() || (email || '').trim()
  if (!source) return '?'
  const parts = source.split(/[\s@._-]+/).filter(Boolean)
  if (parts.length === 0) return '?'
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
}

export function UserAvatar({ name, email, src, size = 40, colorKey, className, ...props }: UserAvatarProps) {
  const [failed, setFailed] = React.useState(false)
  const showImage = Boolean(src) && !failed

  return (
    <span
      className={cn(
        'inline-flex shrink-0 select-none items-center justify-center overflow-hidden rounded-full',
        'border border-border',
        colorKey === null || colorKey === undefined ? 'bg-muted text-muted-foreground' : avatarTone(colorKey),
        className
      )}
      style={{ width: size, height: size, fontSize: Math.max(10, Math.round(size * 0.36)) }}
      {...props}
    >
      {showImage ? (
        <img
          src={src as string}
          alt={name || email || 'Avatar'}
          className="h-full w-full object-cover"
          onError={() => setFailed(true)}
        />
      ) : (
        <span className="font-title font-semibold leading-none tracking-tight">
          {initialsOf(name, email)}
        </span>
      )}
    </span>
  )
}
