import { Pencil, Power, Trash2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { Switch } from '@/components/ui/switch'
import { RichTextView } from '@/components/ui/RichTextField'
import { AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion'
import type { IndicatorConnectionRow } from '@/lib/api/indicators'

/**
 * `FE-320`, `FE-321`, `FE-323` — uma linha da tela "Indicadores específicos".
 *
 * ## As três coisas que mudam, e o usuário nota as três
 *
 * **1. O interruptor não trava mais no segundo clique.** No legado o
 * `preventDoubleSubmission` marca o widget como enviado e **nunca limpa a
 * flag**: o segundo clique é engolido **para sempre**, até a lista recarregar.
 * Aqui o estado de envio é o `isPending` do React Query, que termina sozinho.
 *
 * **2. "Excluir" ganha confirmação.** Nesta tela — e só nesta — o legado apaga o
 * indicador **e todos os lançamentos dele** sem diálogo nenhum. É a metade mais
 * perigosa do D-66, porque nem a frase genérica do outro lado existia aqui.
 *
 * **3. A restrição é EXPLICADA, não escondida** (`FE-323`). Este é o **único
 * ponto do módulo legado** que faz isso — "Você não possui permissão para
 * alterar o estado do indicador", com o controle visível — e esta fatia o
 * generaliza em vez de sumir com o botão. **E o interruptor não mente:** ver a
 * nota longa no `span` que envolve o `Switch`.
 *
 * A concordância também sai consertada: o legado diz "a relação foi ativado", e
 * tem "deasativado" e "Falhou ao ativado/deasativado" na mesma tela.
 */
export interface ConnectionRowProps {
  indicador: IndicatorConnectionRow
  somenteLeitura: boolean
  alternando: boolean
  onToggle: (indicador: IndicatorConnectionRow) => void
  onEditar: (indicador: IndicatorConnectionRow) => void
  onAlternarAtivo: (indicador: IndicatorConnectionRow) => void
  onExcluir: (indicador: IndicatorConnectionRow) => void
}

const AVISO_SOMENTE_LEITURA =
  'Você não possui permissão para alterar o estado do indicador.'

export function ConnectionRow({
  indicador,
  somenteLeitura,
  alternando,
  onToggle,
  onEditar,
  onAlternarAtivo,
  onExcluir,
}: ConnectionRowProps) {
  const global = indicador.scope === 'global'

  return (
    <div className="rounded-lg border border-border bg-card px-4 py-3">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0 flex-1">
          {indicador.description_html ? (
            <AccordionItem value={indicador.id} className="border-0">
              <AccordionTrigger className="py-0 text-left hover:no-underline">
                {/* `flex-wrap` + `shrink-0` nos selos: em 390 px o selo "Global"
                    era espremido pelo interruptor e saía cortado ("Globa").
                    Achado renderizando em 390×844. */}
                <span className="flex min-w-0 flex-wrap items-center gap-2">
                  <span className="truncate font-medium text-foreground">{indicador.title}</span>
                  <Badge variant={global ? 'secondary' : 'info'} className="shrink-0">
                    {global ? 'Global' : 'Do projeto'}
                  </Badge>
                  {!indicador.is_active && <Badge variant="secondary" className="shrink-0">Inativo</Badge>}
                </span>
              </AccordionTrigger>
              <AccordionContent className="pb-0 pt-3">
                <RichTextView html={indicador.description_html} />
              </AccordionContent>
            </AccordionItem>
          ) : (
            <span className="flex min-w-0 flex-wrap items-center gap-2">
              <span className="truncate font-medium text-foreground">{indicador.title}</span>
              <Badge variant={global ? 'secondary' : 'info'} className="shrink-0">
                {global ? 'Global' : 'Do projeto'}
              </Badge>
              {!indicador.is_active && <Badge variant="secondary" className="shrink-0">Inativo</Badge>}
            </span>
          )}
          <p className="mt-1 text-xs text-muted-foreground">
            <code className="font-numeric">{indicador.key}</code>
            {indicador.entries_count > 0 && (
              <>
                {' · '}
                <span className="font-numeric tabular-nums">{indicador.entries_count}</span>{' '}
                {indicador.entries_count === 1 ? 'lançamento' : 'lançamentos'}
              </>
            )}
          </p>
        </div>

        <div className="flex shrink-0 items-center gap-1">
          {global ? (
            // `reuse` verificado: o `switch.tsx` do Radix serve como está.
            //
            // O controle fica VISÍVEL para o perfil somente-leitura e explica a
            // restrição no clique — é o padrão do `FE-323`. **O aviso vem do
            // wrapper, não de um `preventDefault` no próprio interruptor**, e a
            // diferença é observável: `preventDefault` no `onClick` do Radix
            // Switch não desfaz o `aria-checked` que ele já escreveu no DOM.
            // Como `checked` (controlado) não muda, o React não re-renderiza e o
            // interruptor **fica ligado na tela sem nada ter sido gravado** —
            // capturado renderizando em `/indicator-connections` com
            // `user_is_readonly`: `aria-checked` ia de `false` a `true`, zero
            // requisição, zero aviso. É o pior estado possível numa tela de
            // permissão: parece que funcionou.
            //
            // `disabled` faz o Radix não tocar em nada, e o clique chega ao
            // `span` — que é quem explica.
            <span
              onClick={() => {
                if (somenteLeitura) notify.info(AVISO_SOMENTE_LEITURA)
              }}
            >
              <Switch
                checked={indicador.connected}
                disabled={alternando || somenteLeitura}
                aria-label={`${indicador.connected ? 'Desconectar' : 'Conectar'} ${indicador.title}`}
                onCheckedChange={() => onToggle(indicador)}
              />
            </span>
          ) : (
            <div className="flex items-center gap-1">
              <Button
                variant="ghost"
                size="icon"
                aria-label={`Editar ${indicador.title}`}
                onClick={() => (somenteLeitura ? notify.info(AVISO_SOMENTE_LEITURA) : onEditar(indicador))}
              >
                <Pencil aria-hidden="true" className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                aria-label={`${indicador.is_active ? 'Desativar' : 'Ativar'} ${indicador.title}`}
                onClick={() =>
                  somenteLeitura ? notify.info(AVISO_SOMENTE_LEITURA) : onAlternarAtivo(indicador)
                }
              >
                <Power aria-hidden="true" className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="icon"
                aria-label={`Excluir ${indicador.title}`}
                onClick={() => (somenteLeitura ? notify.info(AVISO_SOMENTE_LEITURA) : onExcluir(indicador))}
              >
                <Trash2 aria-hidden="true" className="h-4 w-4" />
              </Button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
