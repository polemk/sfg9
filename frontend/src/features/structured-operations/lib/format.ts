import { formatDate } from '@/lib/utils/date'
import type { StructuredOperation, StructuredOperationType } from '../api/structuredOperations'

/**
 * S8 / **OPS-289** — as três regras de apresentação que a lista, o formulário e
 * o detalhe compartilham.
 *
 * A formatação **saiu do backend**. No legado ela era monkey-patch em
 * `Integer`/`Float`/`BigDecimal` (`to_currency`), com um `rescue` que engolia a
 * falha e devolvia o número **cru** — então um valor mal formado aparecia sem
 * máscara e ninguém ficava sabendo. Agora é `Intl.NumberFormat('pt-BR')` e
 * `date-fns` no front, e o ponto único é `lib/utils/number.ts` +
 * `lib/utils/date.ts` da base (é lá que mora a moeda do app, `APP_CURRENCY`).
 * Este arquivo **não reimplementa nenhuma delas**: só carrega o que é regra
 * desta unidade.
 */

/**
 * Data no padrão do legado (`%d/%m/%Y`), com `-` para nulo.
 *
 * O `-` não é enfeite: o legado fazia `r.issue_date.strftime("%d/%m/%Y")` sem
 * guarda, e uma operação com data nula **derrubava a renderização da linha**
 * (FE-289, FE-297, FE-299). Aqui a data nula é um traço, e a tela continua de pé.
 */
export function dataBr(valor: string | null | undefined): string {
  return formatDate(valor ?? null, '-')
}

/**
 * `operation_type_id` → `has_pre_faturamento`.
 *
 * A flag é do **TIPO**, e a entity da operação não a expõe — o legado lia
 * `r.operation_type.has_pre_faturamento?` na view. O mapa é montado a partir do
 * catálogo que a tela já carrega para o filtro, em vez de pedir uma segunda
 * consulta por linha (que era o N+1 do legado).
 */
export function mapaDePreFaturamento(
  tipos: StructuredOperationType[] | undefined,
): Record<string, boolean> {
  const mapa: Record<string, boolean> = {}
  for (const t of tipos ?? []) mapa[t.id] = t.has_pre_faturamento
  return mapa
}

/**
 * A regra `has_pre_faturamento → as datas viram "-"`, **replicada**.
 *
 * Diferente do homônimo de `risk_operation_types`, aqui a flag não gera subtipo
 * nem muda bucket: o único efeito observável no legado é este, na exibição.
 */
export function semDataDoTipo(
  operacao: Pick<StructuredOperation, 'operation_type_id'>,
  preFaturamento: Record<string, boolean>,
): boolean {
  return preFaturamento[operacao.operation_type_id] === true
}
