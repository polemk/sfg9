import * as React from 'react'
import { cn } from '@/lib/utils'

/**
 * **Campo de texto rico — membro da biblioteca** (`FE-316`, Princípio 11).
 *
 * ## Por que ele nasce aqui e não dentro da tela de indicador
 *
 * A base tinha **três** implementações de rich text e **nenhuma em uso**:
 * `components/RichTextInput.tsx` (contentEditable), `components/RichTextEditor.tsx`
 * (Slate, 13 KB) e uma função local dentro de `app/pages/ProfilePage.tsx:200` —
 * essa última é a única viva. O `package.json` carrega **duas** stacks
 * (`slate*` e `@tiptap/*`) para isso. É a **UF-2**: registrada, não consolidada,
 * porque consolidar é refactor da base.
 *
 * O que esta fatia faz é o mínimo honesto: **promover UM deles a membro da
 * biblioteca**, com a borda de leitura sanitizada, em vez de acrescentar a
 * quarta implementação dentro de uma tela.
 *
 * ## UF-1 — a sanitização, e por que ela é na LEITURA
 *
 * `RichTextInput` renderiza com `dangerouslySetInnerHTML` **sem sanitização
 * nenhuma**, e não há DOMPurify no `package.json`. A "Instrução" do indicador é
 * HTML escrito por um usuário e **lido por todos os outros do projeto**: é XSS
 * armazenado com alcance de tenant.
 *
 * Sanitizar na **escrita** não resolveria: o dado migrado do legado já está
 * gravado, e um segundo cliente (ou o próprio ETL) grava sem passar por aqui. A
 * borda que sempre existe é a de leitura, e é onde o filtro fica.
 *
 * O filtro é uma **allowlist fechada**, aplicada sobre um documento parseado com
 * `DOMParser` (que não executa script nem carrega recurso) — não é regex sobre
 * string, que é o jeito clássico de deixar passar. Tag fora da lista é
 * **desembrulhada** (o texto sobrevive, a tag some); atributo fora da lista é
 * removido; `href` só sobrevive se for `http`, `https` ou `mailto`.
 *
 * **Isto não toca o `RichTextInput` compartilhado**: sanitizá-lo afetaria todo
 * consumidor de rich text da base, e essa é uma mudança da plataforma, não desta
 * fatia (Princípio 6b).
 */

const TAGS_PERMITIDAS = new Set([
  'p', 'br', 'div', 'span', 'strong', 'b', 'em', 'i', 'u', 's', 'code', 'pre',
  'blockquote', 'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'a', 'hr',
  'table', 'thead', 'tbody', 'tr', 'th', 'td',
])

/** `tag => atributos permitidos`. O que não estiver aqui é removido. */
const ATRIBUTOS_PERMITIDOS: Record<string, Set<string>> = {
  a: new Set(['href', 'title']),
}

const PROTOCOLOS_PERMITIDOS = ['http:', 'https:', 'mailto:']

function hrefSeguro(valor: string): boolean {
  try {
    // `base` só existe para resolver caminho relativo; o que importa é o
    // protocolo resultante. `javascript:` e `data:` não passam.
    const url = new URL(valor, window.location.origin)
    return PROTOCOLOS_PERMITIDOS.includes(url.protocol)
  } catch {
    return false
  }
}

/**
 * Devolve HTML seguro para `dangerouslySetInnerHTML`.
 *
 * Exportada porque quem exibe a Instrução fora deste componente (um card, um
 * cabeçalho de grade) precisa da **mesma** sanitização — duas sanitizações
 * diferentes é o mesmo que uma só, a mais fraca.
 */
export function sanitizeRichText(html: string | null | undefined): string {
  if (!html) return ''

  const doc = new DOMParser().parseFromString(`<div id="raiz">${html}</div>`, 'text/html')
  const raiz = doc.getElementById('raiz')
  if (!raiz) return ''

  const limpar = (no: Element) => {
    // Cópia: a lista viva muda enquanto desembrulhamos filhos.
    Array.from(no.children).forEach((filho) => limpar(filho))

    const tag = no.tagName.toLowerCase()

    if (!TAGS_PERMITIDAS.has(tag)) {
      // Desembrulha: o texto sobrevive, a tag some. `<script>` some inteiro
      // porque o conteúdo dele é texto que não queremos de volta.
      if (tag === 'script' || tag === 'style' || tag === 'iframe' || tag === 'object' || tag === 'embed') {
        no.remove()
        return
      }
      const pai = no.parentNode
      if (!pai) return
      while (no.firstChild) pai.insertBefore(no.firstChild, no)
      pai.removeChild(no)
      return
    }

    const permitidos = ATRIBUTOS_PERMITIDOS[tag] ?? new Set<string>()
    Array.from(no.attributes).forEach((attr) => {
      const nome = attr.name.toLowerCase()
      // Todo `on*` sai, sempre — é o vetor mais direto e não há caso legítimo.
      if (!permitidos.has(nome) || nome.startsWith('on')) {
        no.removeAttribute(attr.name)
        return
      }
      if (nome === 'href' && !hrefSeguro(attr.value)) no.removeAttribute(attr.name)
    })

    if (tag === 'a') {
      no.setAttribute('rel', 'noopener noreferrer')
      no.setAttribute('target', '_blank')
    }
  }

  Array.from(raiz.children).forEach((filho) => limpar(filho))
  return raiz.innerHTML
}

export interface RichTextFieldProps {
  /** HTML atual. */
  value: string | null | undefined
  onChange: (html: string) => void
  label?: string
  hint?: string
  placeholder?: string
  id?: string
  disabled?: boolean
  className?: string
}

/**
 * Editor. `contentEditable` com o conteúdo **sanitizado ao montar** e a cada vez
 * que o valor vem de fora — nunca a cada tecla, porque reescrever o DOM sob o
 * cursor faz o cursor pular para o começo a cada caractere (é o defeito clássico
 * de editor caseiro, e o `RichTextInput` da base o tem).
 */
export function RichTextField({
  value,
  onChange,
  label,
  hint,
  placeholder = 'Explique como este indicador deve ser preenchido…',
  id,
  disabled,
  className,
}: RichTextFieldProps) {
  const autoId = React.useId()
  const campoId = id ?? autoId
  const ref = React.useRef<HTMLDivElement>(null)
  // O que o próprio campo emitiu por último. Serve para NÃO reescrever o DOM
  // enquanto o usuário digita — só quando o valor vem de fora.
  const emitido = React.useRef<string | null>(null)

  React.useEffect(() => {
    const no = ref.current
    if (!no) return
    if (value === emitido.current) return
    no.innerHTML = sanitizeRichText(value)
  }, [value])

  const vazio = !value || sanitizeRichText(value).replace(/<[^>]*>/g, '').trim() === ''

  return (
    <div className={cn('space-y-1.5', className)}>
      {label && (
        <label htmlFor={campoId} className="text-sm font-medium text-foreground">
          {label}
        </label>
      )}
      <div className="relative">
        <div
          id={campoId}
          ref={ref}
          role="textbox"
          aria-multiline="true"
          aria-label={label}
          contentEditable={!disabled}
          suppressContentEditableWarning
          onInput={(e) => {
            const bruto = (e.target as HTMLElement).innerHTML
            emitido.current = bruto
            onChange(bruto)
          }}
          className={cn(
            'min-h-[7.5rem] w-full overflow-y-auto rounded-md border border-input bg-background px-3 py-2',
            'text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
            'prose-sm [&_a]:text-primary [&_a]:underline [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5',
            disabled && 'cursor-not-allowed opacity-60',
          )}
        />
        {vazio && (
          <span className="pointer-events-none absolute left-3 top-2 text-sm text-muted-foreground">
            {placeholder}
          </span>
        )}
      </div>
      {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
    </div>
  )
}

export interface RichTextViewProps {
  html: string | null | undefined
  className?: string
}

/**
 * Leitura. **Todo** ponto do app que exibe HTML de usuário passa por aqui — é a
 * borda da UF-1.
 */
export function RichTextView({ html, className }: RichTextViewProps) {
  const limpo = React.useMemo(() => sanitizeRichText(html), [html])
  if (!limpo) return null

  return (
    <div
      className={cn(
        'text-sm leading-relaxed text-muted-foreground',
        '[&_a]:text-primary [&_a]:underline [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:list-decimal [&_ol]:pl-5',
        '[&_p]:mb-2 [&_p:last-child]:mb-0',
        className,
      )}
      dangerouslySetInnerHTML={{ __html: limpo }}
    />
  )
}
