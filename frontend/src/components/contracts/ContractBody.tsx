import { cn } from '@/lib/utils'

/**
 * O corpo de um contrato — **um renderizador só, para as duas telas** (FE-331).
 *
 * No legado o mesmo documento aparecia de dois jeitos: o console mostrava o
 * rich text e a página pública fazia
 * `CGI.unescape(...to_plain_text).html_safe`, jogando fora título, lista e
 * negrito. **A tela que o usuário juridicamente lê era a menos fiel das duas.**
 * Aqui as duas usam este componente, e o HTML vem do mesmo
 * `Contracts::Renderer` do servidor.
 *
 * **A sanitização é do servidor**, por allowlist (BE-345), e não daqui: uma
 * segunda allowlist no cliente divergiria da primeira no dia em que alguém
 * acrescentasse uma tag — e a divergência apareceria como "a tela pública
 * perdeu a tabela", que é o defeito que estamos consertando.
 *
 * `prose-*` não existe nesta base (sem `@tailwindcss/typography`), então a
 * tipografia do documento é declarada aqui, com **tokens** — nunca cor literal.
 */
export function ContractBody({ html, className }: { html: string; className?: string }) {
  return (
    <div
      className={cn(
        'max-w-none text-sm leading-relaxed text-foreground',
        '[&_h1]:font-title [&_h1]:text-xl [&_h1]:font-semibold [&_h1]:mt-6 [&_h1]:mb-2',
        '[&_h2]:font-title [&_h2]:text-lg [&_h2]:font-semibold [&_h2]:mt-5 [&_h2]:mb-2',
        '[&_h3]:font-title [&_h3]:text-base [&_h3]:font-semibold [&_h3]:mt-4 [&_h3]:mb-1',
        '[&_p]:mb-3',
        '[&_ul]:mb-3 [&_ul]:list-disc [&_ul]:pl-6',
        '[&_ol]:mb-3 [&_ol]:list-decimal [&_ol]:pl-6',
        '[&_li]:mb-1',
        '[&_strong]:font-semibold',
        '[&_a]:text-primary [&_a]:underline [&_a]:underline-offset-2',
        '[&_blockquote]:border-l-2 [&_blockquote]:border-border [&_blockquote]:pl-4 [&_blockquote]:text-muted-foreground',
        '[&_table]:w-full [&_table]:border-collapse [&_th]:border [&_th]:border-border [&_th]:p-2',
        '[&_td]:border [&_td]:border-border [&_td]:p-2',
        '[&_img]:max-w-full',
        className,
      )}
      // O HTML já passou pela allowlist do servidor. Ver o cabeçalho.
      dangerouslySetInnerHTML={{ __html: html }}
    />
  )
}
