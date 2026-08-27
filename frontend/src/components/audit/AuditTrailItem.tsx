import * as React from 'react'
import { cn } from '@/lib/utils'
import { UserAvatar } from '@/components/ui/UserAvatar'
import { Tooltip } from '@/components/ui/Tooltip'
import { timeAgo, formatDateTime } from '@/lib/utils/date'
import { auditAppearance } from './auditAppearance'
import type { AuditVersion } from '@/lib/api/auditTrail'

/**
 * Um item da trilha de atividade — `FE-445`.
 *
 * Estrutura herdada do widget do legado
 * (`api/v1/trackings/widgets/_widget.html.erb`): disco com ícone, avatar do
 * autor, frase e o "há tanto tempo". O que muda:
 *
 *  - a **frase vem pronta do servidor** (`summary`), montada uma vez só a partir
 *    do catálogo pt-BR. No legado era `resume`, uma coluna `string(300)` que
 *    fazia o `save` retornar `false` quando o texto passava do limite — e o
 *    evento **desaparecia**, sempre o do caso complicado;
 *  - o **autor é o usuário real** (DEC-59 #3). Quando houve impersonação, o item
 *    diz as duas pessoas — "Fulano, personificando Beltrano". Uma trilha que
 *    mostra só o impersonado é o oposto do ponto de ter trilha;
 *  - ícone e cor vêm de um **mapa** (`auditAppearance`), não de duas funções que
 *    devolvem constante como no legado;
 *  - o instante absoluto fica no `title`/tooltip. "há 3 dias" é o que se lê;
 *    "12/03/2026 14:22" é o que se cita numa investigação, e some da tela se
 *    não estiver em lugar nenhum.
 */
export interface AuditTrailItemProps {
  version: AuditVersion
  /** Última linha da lista: sem o fio vertical que liga um item ao próximo. */
  last?: boolean
  onSelect?: (version: AuditVersion) => void
  className?: string
}

export function AuditTrailItem({ version, last, onSelect, className }: AuditTrailItemProps) {
  const { icon: Icon, tone, label } = auditAppearance(version.event)
  const autor = version.author
  const impersonado = version.impersonated
  const clicavel = Boolean(onSelect)

  return (
    <li className={cn('relative flex gap-3 pb-5 last:pb-0', className)}>
      {/* Fio da timeline. `aria-hidden` porque é ornamento: a ordem já é dada
          pela lista, e um leitor de tela não deve anunciar um traço. */}
      {!last && <span aria-hidden="true" className="absolute left-[19px] top-10 bottom-0 w-px bg-border" />}

      <span
        className={cn('flex h-10 w-10 shrink-0 items-center justify-center rounded-full', tone)}
        aria-hidden="true"
      >
        <Icon className="h-[18px] w-[18px]" />
      </span>

      <div className="min-w-0 flex-1">
        <div className="flex flex-wrap items-baseline gap-x-2 gap-y-1">
          <span className="text-sm text-foreground">
            <span className="sr-only">{label}. </span>
            {version.summary}
          </span>
          <Tooltip content={formatDateTime(version.occurred_at)}>
            <time
              dateTime={version.occurred_at}
              className="text-xs text-muted-foreground"
            >
              {timeAgo(version.occurred_at)}
            </time>
          </Tooltip>
        </div>

        <div className="mt-1.5 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
          <UserAvatar
            size={20}
            name={autor?.name}
            email={autor?.email}
            colorKey={autor?.id ?? null}
          />
          {/* Autor desconhecido acontece de verdade: versão criada por seed,
              migração ou console não tem requisição, logo não tem `whodunnit`.
              Dizer "sistema" é honesto; inventar um nome não seria. */}
          <span className="truncate">{autor?.name || autor?.email || 'sistema'}</span>

          {impersonado && (
            <span className="rounded bg-warning/15 px-1.5 py-0.5 text-warning-foreground">
              personificando {impersonado.name || impersonado.email || impersonado.id}
            </span>
          )}

          {version.reason && <span className="truncate italic">"{version.reason}"</span>}

          {clicavel && (
            <button
              type="button"
              onClick={() => onSelect?.(version)}
              // Sem `ml-auto`: numa tela de 1440 px ele ia parar a 900 px do
              // texto que descreve, e o olho tinha de atravessar um rio de
              // vazio para ligar as duas coisas. A ação mora ao lado do
              // conteúdo sobre o qual ela age.
              className="rounded text-xs font-medium text-primary underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              Ver detalhes
            </button>
          )}
        </div>
      </div>
    </li>
  )
}
