import * as React from 'react'
import { cn } from '@/lib/utils'

/**
 * Logo do Safegold — **a única** fonte de marca visual do app.
 *
 * Nenhuma tela desenha o logo à mão nem escreve "Safegold" com `<span>`
 * estilizado. Se precisa da marca, importa daqui.
 *
 * A variante clara/escura é resolvida por CSS (`dark:` / `.surface-dark`), não
 * por JavaScript: as duas imagens ficam empilhadas e só uma aparece. Assim o
 * logo já nasce certo no primeiro paint, sem piscar ao trocar de tema.
 *
 *  full      símbolo + palavra (padrão — cabeçalho, login, e-mail)
 *  wordmark  só a palavra
 *  symbol    só o símbolo (sidebar recolhida, favicon, avatar)
 *
 * E dois tons:
 *
 *  brand  o ouro `#EB9600` do arquivo original + o grafite/branco do texto (padrão)
 *  mono   uma cor só, chapada — grafite no claro, quase-branco no escuro
 *
 * **O tom `mono` é DERIVADO, não é arte do cliente (DEC-93).** No legado as
 * constantes `_WHITE` e `_MONO` de `SFG/theme.rb:47-57` apontavam **todas para o
 * mesmo arquivo colorido**: logo branco e logo monocromático nunca existiram de
 * verdade. Os arquivos `*-mono*.png` foram gerados aqui a partir do canal alfa da
 * arte colorida, preenchido com `--brand-ink` / o branco morno da marca. Se o
 * manual de marca aparecer, o original vence a derivação — e a troca é de arquivo,
 * não de código.
 */
export type LogoVariant = 'full' | 'wordmark' | 'symbol'
export type LogoTone = 'brand' | 'mono'

/**
 * O catálogo de arquivos da marca. **Exportado de propósito:** há dois lugares
 * que precisam do CAMINHO e não podem renderizar um componente React — o
 * `logo` do JSON-LD em `components/seo/SEO.tsx` e qualquer meta de imagem. Eles
 * importam daqui em vez de escrever a string de novo, e assim a lista de
 * arquivos da marca continua existindo **uma vez só**.
 */
export const LOGO_SRC: Record<LogoTone, Record<LogoVariant, { light: string; dark: string }>> = {
  brand: {
    full: {
      light: '/images/brand/safegold-logo.png',
      dark: '/images/brand/safegold-logo-white.png',
    },
    wordmark: {
      light: '/images/brand/safegold-wordmark.png',
      dark: '/images/brand/safegold-wordmark-white.png',
    },
    symbol: {
      light: '/images/brand/safegold-symbol.png',
      dark: '/images/brand/safegold-symbol-white.png',
    },
  },
  mono: {
    full: {
      light: '/images/brand/safegold-logo-mono.png',
      dark: '/images/brand/safegold-logo-mono-white.png',
    },
    wordmark: {
      light: '/images/brand/safegold-wordmark-mono.png',
      dark: '/images/brand/safegold-wordmark-mono-white.png',
    },
    symbol: {
      light: '/images/brand/safegold-symbol-mono.png',
      dark: '/images/brand/safegold-symbol-mono-white.png',
    },
  },
}

export interface LogoProps extends React.HTMLAttributes<HTMLSpanElement> {
  variant?: LogoVariant
  /** Altura em px. A largura sai da proporção do arquivo. */
  height?: number
  /** Força a variante clara do logo (uso em superfície escura fixa). */
  onDark?: boolean
  /** `mono` = uma cor só. Para selo, marca d'água e impressão. */
  tone?: LogoTone
}

export function Logo({
  variant = 'full',
  height = 28,
  onDark = false,
  tone = 'brand',
  className,
  ...props
}: LogoProps) {
  const src = LOGO_SRC[tone][variant]
  const alt = 'Safegold'

  if (onDark) {
    return (
      <span className={cn('inline-flex items-center', className)} {...props}>
        <img src={src.dark} alt={alt} style={{ height }} className="w-auto select-none" />
      </span>
    )
  }

  return (
    <span className={cn('inline-flex items-center', className)} {...props}>
      <img
        src={src.light}
        alt={alt}
        style={{ height }}
        className="brand-logo-light w-auto select-none"
      />
      <img
        src={src.dark}
        alt=""
        aria-hidden="true"
        style={{ height }}
        className="brand-logo-dark w-auto select-none"
      />
    </span>
  )
}
