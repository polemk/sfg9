import * as React from 'react'
import { History } from 'lucide-react'
import { cn } from '@/lib/utils'
import { LoadingState, EmptyState, ErrorState } from '@/components/ui/States'
import { AuditTrailItem } from './AuditTrailItem'
import type { AuditVersion } from '@/lib/api/auditTrail'

/**
 * Timeline de atividade — `FE-445`.
 *
 * Componente **burro de propósito**: recebe as versões e os três estados que não
 * são conteúdo. Quem busca é a tela — a global (`/api/v1/audit_trail`, OG e
 * Admin, DEC-77) ou a de um objeto (`Sfg::AuditTrail.for_record`, quem vê o
 * objeto). As duas mostram a mesma coisa, e é por isso que o componente não
 * conhece a origem.
 *
 * Os quatro estados vêm do design system (`States.tsx`), não reescritos aqui: o
 * quarto, o de **erro**, é o que o legado não tinha (FE-401) — uma trilha vazia
 * por falha de rede é indistinguível de "nada aconteceu", e numa trilha de
 * auditoria essas duas coisas não podem se parecer.
 */
export interface AuditTrailTimelineProps {
  versions: AuditVersion[]
  loading?: boolean
  error?: boolean
  onRetry?: () => void
  onSelect?: (version: AuditVersion) => void
  /** Texto do estado vazio — a trilha global e a de um objeto dizem coisas diferentes. */
  emptyLabel?: string
  emptyDescription?: string
  className?: string
}

export function AuditTrailTimeline({
  versions,
  loading,
  error,
  onRetry,
  onSelect,
  emptyLabel = 'Nada registrado ainda',
  emptyDescription = 'Quando algo mudar, o registro aparece aqui com quem fez, quando e por quê.',
  className,
}: AuditTrailTimelineProps) {
  if (loading) return <LoadingState label="Carregando a trilha…" size="inline" />

  if (error) {
    return (
      <ErrorState
        size="inline"
        title="Não foi possível carregar a trilha"
        description="A trilha é o registro de auditoria; uma lista vazia aqui não significa que nada aconteceu."
        onRetry={onRetry}
      />
    )
  }

  if (versions.length === 0) {
    return (
      <EmptyState
        size="inline"
        icon={<History aria-hidden="true" className="h-5 w-5 text-muted-foreground" />}
        title={emptyLabel}
        description={emptyDescription}
      />
    )
  }

  return (
    <ol className={cn('list-none', className)}>
      {versions.map((v, i) => (
        <AuditTrailItem
          key={v.id}
          version={v}
          last={i === versions.length - 1}
          onSelect={onSelect}
        />
      ))}
    </ol>
  )
}
