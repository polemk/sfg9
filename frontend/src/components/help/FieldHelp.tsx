import { HelpCircle } from 'lucide-react'
import { Tooltip } from '@/components/ui/Tooltip'
import { useFieldHelp } from '@/hooks/useFieldHelp'

/**
 * O ícone de ajuda ao lado do rótulo de um campo (OPS-545 / DEC-88).
 *
 * Uso, no formulário:
 *
 * ```tsx
 * <Label htmlFor="valor_bruto">
 *   Valor bruto <FieldHelp scope="receivables" field="valor_bruto" />
 * </Label>
 * ```
 *
 * **Campo sem texto não ganha ícone.** Não é detalhe de estilo: um ícone de
 * ajuda que abre um tooltip vazio ensina o operador a parar de clicar nos
 * ícones — e aí os 87 que têm conteúdo deixam de ser lidos. As 4 chaves
 * marcadas `TODO:` caem exatamente aqui.
 */
export function FieldHelp({
  scope,
  field,
  side = 'top',
}: {
  scope: string
  field: string
  side?: 'top' | 'right' | 'bottom' | 'left'
}) {
  const { texto } = useFieldHelp(scope)
  const conteudo = texto(field)

  if (!conteudo) return null

  return (
    <Tooltip
      side={side}
      className="inline-flex align-middle"
      content={<span className="block max-w-xs whitespace-normal text-left leading-snug">{conteudo}</span>}
    >
      <button
        type="button"
        aria-label={`Ajuda sobre o campo ${field}`}
        className="inline-flex h-4 w-4 items-center justify-center rounded-sm text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
      >
        <HelpCircle aria-hidden="true" className="h-3.5 w-3.5" />
      </button>
    </Tooltip>
  )
}
