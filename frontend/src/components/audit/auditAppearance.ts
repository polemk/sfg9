import { PlusCircle, PencilLine, Trash2, UserCheck, UserX, Info, type LucideIcon } from 'lucide-react'
import type { AuditEvent } from '@/lib/api/auditTrail'

/**
 * Aparência do item da trilha — `FE-443`, o par `tracking_color`/`tracking_icon`.
 *
 * **É dado, não `case`.** Acrescentar um evento novo é acrescentar uma linha
 * neste mapa; nenhum componente muda. O portão da tarefa é exatamente esse.
 *
 * O que o legado fazia (`application_helper.rb:182-190`) merece registro porque
 * a tarefa foi escrita supondo o contrário: as duas funções **ignoram o
 * argumento**. `tracking_color(t)` devolve `SFG::Theme.COLOR__ACCENT` para
 * qualquer evento e `tracking_icon(t)` devolve `'zmdi zmdi-info'` para qualquer
 * evento. Não havia mapa a portar — havia duas constantes com cara de função.
 * O mapa abaixo é comportamento **novo**, e está no `improvements-log.md`.
 *
 * As cores são **tokens semânticos**, nunca literais: mudam sozinhas entre o
 * tema claro e o escuro, como o resto da interface.
 */
export interface AuditAppearance {
  icon: LucideIcon
  /** Classes de token para o disco do ícone. */
  tone: string
  /** Rótulo curto do evento, para leitor de tela e para o filtro. */
  label: string
}

const PADRAO: AuditAppearance = {
  icon: Info,
  tone: 'bg-muted text-muted-foreground',
  label: 'Evento',
}

const MAPA: Record<AuditEvent, AuditAppearance> = {
  create: { icon: PlusCircle, tone: 'bg-success/15 text-success', label: 'Criação' },
  update: { icon: PencilLine, tone: 'bg-info/15 text-info', label: 'Alteração' },
  destroy: { icon: Trash2, tone: 'bg-negative/15 text-negative', label: 'Remoção' },
  // A impersonação não é um evento do `paper_trail`: é gravada à mão na mesma
  // tabela, porque a trilha é uma só (DEC-59). Ganha destaque próprio porque é
  // o ato mais sensível do sistema, e uma trilha em que ele parece "alteração"
  // esconde justamente o que se quer enxergar.
  impersonate_start: { icon: UserCheck, tone: 'bg-warning/20 text-warning-foreground', label: 'Impersonação iniciada' },
  impersonate_stop: { icon: UserX, tone: 'bg-warning/15 text-warning-foreground', label: 'Impersonação encerrada' },
}

export function auditAppearance(event: string): AuditAppearance {
  return MAPA[event as AuditEvent] ?? PADRAO
}

/** Os eventos conhecidos, na ordem em que o filtro os mostra. */
export const AUDIT_EVENTS = Object.keys(MAPA) as AuditEvent[]
