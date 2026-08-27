import { useNavigate, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ArrowLeft, CalendarRange, Lock } from 'lucide-react'

import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { PageHeader } from '@/components/PageHeader'
import { availabilityTemplatesApi } from '@/lib/api/availability'
import { formatDateTime, timeAgo } from '@/lib/utils/date'

/**
 * `/availability-templates/:id` — o cartão "Dados do template" (FE-140).
 *
 * ## O que faltava
 *
 * Não havia tela de detalhe: `consoleNavigation.tsx` registrava só a lista, e
 * ela cobria parte do cartão (Nº, Título, Natureza, Prazo e os marcadores).
 * Ficavam de fora **Escopo**, **criado por / criado em** e o "há X desde a
 * atualização".
 *
 * ## O painel "Projetos" do legado nunca renderizou
 *
 * Ele existia em `availability_templates/detail/_body.html.erb:76-91`, atrás de
 * `if type == "ProjectAvailabilityTemplate"`, e chamava
 * `@availability_template.projects` — **associação que não existe** em nenhum
 * dos três models do legado (BE-133). Abrir o detalhe de um padrão de projeto
 * levantava `NoMethodError`; o painel nunca chegou à tela.
 *
 * O que a informação queria dizer existe e é `belongs_to :project`: um padrão
 * de projeto pertence a UM projeto. É isso que aparece aqui — no singular, que
 * é o que o dado é.
 */
export function AvailabilityTemplateDetailPage() {
  const { id = '' } = useParams<{ id: string }>()
  const navigate = useNavigate()

  const padrao = useQuery({
    queryKey: ['availability-template', id],
    queryFn: () => availabilityTemplatesApi.get(id),
    enabled: !!id,
  })

  if (padrao.isLoading) return <LoadingState label="Carregando o padrão…" />
  if (padrao.isError) {
    return (
      <ErrorState
        description="Não foi possível carregar este padrão."
        onRetry={() => padrao.refetch()}
      />
    )
  }

  const t = padrao.data
  if (!t) return <EmptyState title="Padrão não encontrado" description="Ele pode ter sido removido." />

  return (
    <div className="space-y-5">
      <PageHeader
        title={t.title}
        subtitle={`Nº ${t.position_path}`}
        rightSlot={
          <Button variant="secondary" size="sm" onClick={() => navigate('/availability-templates')}>
            <ArrowLeft aria-hidden="true" className="mr-1.5 h-4 w-4" />
            Voltar ao catálogo
          </Button>
        }
      />

      {t.is_locked && (
        <div className="flex items-center gap-2 rounded-lg border border-warning/30 bg-warning/10 px-3 py-2 text-sm text-warning">
          <Lock aria-hidden="true" className="h-4 w-4 shrink-0" />
          {t.locked_message ?? 'Operação em andamento neste padrão.'}
        </div>
      )}

      <section className="rounded-lg border border-border bg-card p-4">
        <h2 className="mb-3 text-sm font-semibold text-card-foreground">Dados do template</h2>

        <dl className="grid gap-x-6 gap-y-3 sm:grid-cols-2">
          <Linha rotulo="Título" valor={t.title} />
          <Linha rotulo="Tipo" valor={t.operation_type_label} />
          <Linha rotulo="Escopo" valor={t.scope_label} />
          <Linha rotulo="Prazo" valor={t.deadline_type_label} />
          <LinhaSimNao rotulo="Padrão" ligado={t.is_mandatory} />
          <LinhaSimNao rotulo="Acumulável" ligado={t.is_cumulative} />
          <LinhaSimNao rotulo="Corrigido para dias úteis" ligado={t.is_adjusted} />
          <Linha
            rotulo="Criado por"
            // O legado escrevia "<nome> em <data>" numa linha só
            // (`detail/_body.html.erb:66`). Sem autor, a data continua valendo:
            // dizer "—" para tudo esconderia o quando por falta do quem.
            valor={
              t.author_name
                ? `${t.author_name} em ${formatDateTime(t.created_at)}`
                : formatDateTime(t.created_at)
            }
          />
          <Linha rotulo="Atualizado" valor={timeAgo(t.updated_at)} />
        </dl>
      </section>

      {/* Só para padrão de projeto — no catálogo global não há projeto a mostrar. */}
      {t.type === 'ProjectAvailabilityTemplate' && (
        <section className="rounded-lg border border-border bg-card p-4">
          <h2 className="mb-3 text-sm font-semibold text-card-foreground">Projeto</h2>
          {t.project_name ? (
            <div className="flex items-center gap-2 text-sm text-card-foreground">
              <CalendarRange aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground" />
              {t.project_name}
            </div>
          ) : (
            <p className="text-sm text-muted-foreground">
              Este padrão não está vinculado a nenhum projeto.
            </p>
          )}
        </section>
      )}
    </div>
  )
}

function Linha({ rotulo, valor }: { rotulo: string; valor: string | null | undefined }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">{rotulo}</dt>
      <dd className="truncate text-sm text-card-foreground">{valor || '—'}</dd>
    </div>
  )
}

/**
 * SIM/NÃO como no legado, e com selo em vez de texto solto.
 *
 * O "NÃO" não é ausência de informação — é informação. Um traço no lugar dele
 * faria "não é acumulável" parecer "não sabemos".
 */
function LinhaSimNao({ rotulo, ligado }: { rotulo: string; ligado: boolean }) {
  return (
    <div className="min-w-0">
      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">{rotulo}</dt>
      <dd className="text-sm">
        <Badge variant={ligado ? 'success' : 'secondary'}>{ligado ? 'SIM' : 'NÃO'}</Badge>
      </dd>
    </div>
  )
}
