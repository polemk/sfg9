import { useQuery } from '@tanstack/react-query'
import { renegotiationsApi, type InstallmentDraft, type InstallmentPreview } from '@/lib/api/renegotiations'

/**
 * S9 / FE-221 — **os totais derivados da parcela vêm do SERVIDOR** (contrato C2).
 *
 * ## Por que este hook existe, em uma frase
 *
 * Porque a alternativa — somar `principal + juros + correção` em JavaScript para
 * mostrar o total enquanto o usuário digita — coloca a regra financeira em **dois
 * lugares**, e é o **D-09**: o dia em que a fórmula do servidor mudar (ou já for
 * diferente, como é o caso da mora, que entra dos dois lados da conta), a
 * simulação e o salvamento passam a mostrar números diferentes, e ninguém
 * descobre até um cliente somar a coluna.
 *
 * **A prévia chama o MESMO serviço que a gravação** (`AggregateService.preview` e
 * `AggregateService.recalculate!` compartilham `Renegotiations::Formulas`). Há um
 * teste no backend que envia o mesmo rascunho aos dois endpoints e compara campo
 * a campo.
 *
 * ## O que ele deliberadamente não faz
 *
 * - **Não calcula nada localmente**, nem "para ir adiantando". Enquanto a
 *   resposta não chega, a tela mostra o traço, não um número provisório que vai
 *   piscar para outro.
 * - **Não dispara com rascunho inválido.** Sem data ou com principal ≤ 0 o
 *   servidor responderia 422, e 422 a cada tecla é ruído.
 */
export interface UseInstallmentPreviewResult {
  preview: InstallmentPreview | undefined
  loading: boolean
  /** `true` quando o rascunho ainda não é consultável (falta data ou valor). */
  idle: boolean
  error: unknown
}

export function useInstallmentPreview(
  renegotiationId: string | undefined,
  draft: InstallmentDraft,
  options: { enabled?: boolean; replacingId?: string } = {},
): UseInstallmentPreviewResult {
  const consultavel =
    !!renegotiationId &&
    !!draft.due_date &&
    typeof draft.main_value === 'number' &&
    draft.main_value > 0 &&
    (options.enabled ?? true)

  const query = useQuery({
    // A chave inclui o rascunho INTEIRO: mudar qualquer campo é outra pergunta.
    queryKey: ['installment-preview', renegotiationId, draft, options.replacingId ?? null],
    queryFn: () => renegotiationsApi.installments.preview(renegotiationId!, draft, options.replacingId),
    enabled: consultavel,
    // O rascunho é volátil por natureza; guardar a resposta faria a tela mostrar
    // o total de um rascunho anterior.
    staleTime: 0,
    gcTime: 0,
    retry: false,
  })

  return {
    preview: query.data,
    loading: query.isFetching,
    idle: !consultavel,
    error: query.error,
  }
}
