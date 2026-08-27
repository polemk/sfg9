import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { History, X } from 'lucide-react'
import { auditTrailApi, type AuditTrailFilters, type AuditVersion } from '@/lib/api/auditTrail'
import { AuditTrailTimeline } from '@/components/audit/AuditTrailTimeline'
import { AuditEventDialog } from '@/components/audit/AuditEventDialog'
import { AUDIT_EVENTS, auditAppearance } from '@/components/audit/auditAppearance'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Select } from '@/components/ui/Select'
import { Label } from '@/components/ui/Label'
import { Button } from '@/components/ui/Button'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { DEFAULT_PER_PAGE } from '@/lib/api/pagination'
import { toIsoDateTime, todayStart } from '@/lib/utils/date'

/**
 * Trilha de auditoria global — a tela de `GET /api/v1/audit_trail`.
 *
 * **Quem vê (DEC-77):** OG e Admin. A autorização é do **servidor** — o endpoint
 * responde 403 para os demais e a tela mostra o estado de erro. A tela não
 * decide isso pelo papel: papel lido no cliente é sugestão, não autorização.
 *
 * O histórico **do próprio objeto** não é esta tela: é servido pelo endpoint do
 * objeto (`Sfg::AuditTrail.for_record`) e desenhado pelo mesmo
 * `AuditTrailTimeline`, dentro da tela do objeto.
 *
 * **A rota existe:** `/admin/audit-trail`, no grupo "Admin" do menu. Ligada pela
 * S2 no registro declarativo `app/consoleNavigation.tsx`, que é a fonte única de
 * rota E de item de menu — não há `<Route>` solto em `App.tsx` para esta tela.
 *
 * O gate de navegação é `RoleRoute roles={['og','admin']}`, e **não** o `OgRoute`
 * da base: o `OgRoute` casa por `includes('admin')` no NOME de exibição do papel,
 * o que não é a mesma regra do servidor. A autorização de verdade continua sendo
 * a do endpoint (OG 200 · Admin 200 · Gerente 403 · Colaborador 403).
 *
 * ## Desenho (passada `impeccable`, modo Operate)
 *
 * **Os filtros são uma faixa própria acima da lista, não um canto.** Antes eles
 * moravam no `CardHeader`, num `flex-wrap` estreito: como o `Select` é `w-full`
 * por padrão, os três empilhavam numa coluna à direita e metade da largura do
 * cabeçalho ficava vazia — cara de sobra, não de desenho. A faixa horizontal é
 * o mesmo padrão já usado em `RenegotiationsPage`: reuso, não invenção. Cada
 * seletor ganhou **rótulo visível** — "Todos os tipos" sozinho não diz o que
 * está sendo filtrado.
 *
 * **O total fica no cabeçalho da lista** porque é a resposta a "meu filtro
 * pegou alguma coisa?", que é a pergunta seguinte a qualquer filtro.
 */
export function AuditTrailPage() {
  const [filtros, setFiltros] = useState<AuditTrailFilters>({ page: 1, perPage: DEFAULT_PER_PAGE })
  const [selecionada, setSelecionada] = useState<AuditVersion | null>(null)

  const tipos = useQuery({
    queryKey: ['audit-trail', 'types'],
    queryFn: () => auditTrailApi.types(),
    staleTime: 5 * 60 * 1000,
  })

  const trilha = useQuery({
    queryKey: ['audit-trail', filtros],
    queryFn: () => auditTrailApi.list(filtros),
  })

  const detalhe = useQuery({
    queryKey: ['audit-trail', 'detalhe', selecionada?.id],
    queryFn: () => auditTrailApi.get(selecionada!.id),
    enabled: selecionada !== null,
  })

  const meta = trilha.data?.meta

  // Cada mudança de filtro volta para a página 1: filtrar estando na página 7 e
  // continuar na 7 mostra uma lista vazia que parece "nada encontrado".
  const aplicar = (parcial: Partial<AuditTrailFilters>) =>
    setFiltros((atual) => ({ ...atual, ...parcial, page: 1 }))

  const temFiltro = Boolean(filtros.itemType || filtros.event || filtros.from)

  const limpar = () =>
    setFiltros((atual) => ({ page: 1, perPage: atual.perPage }))

  const opcoesDeEvento = useMemo(
    () => AUDIT_EVENTS.map((e) => ({ value: e as string, label: auditAppearance(e).label })),
    [],
  )

  // Calculado uma vez por montagem: recriar a lista a cada render mudaria o
  // valor de "hoje" no meio da sessão e o filtro deixaria de casar.
  const periodos = useMemo(
    () => [
      { value: '', label: 'Desde sempre' },
      { value: toIsoDateTime(todayStart()) ?? '', label: 'Hoje' },
      { value: toIsoDateTime(new Date(Date.now() - 7 * 864e5)) ?? '', label: 'Últimos 7 dias' },
      { value: toIsoDateTime(new Date(Date.now() - 30 * 864e5)) ?? '', label: 'Últimos 30 dias' },
    ],
    [],
  )

  return (
    <div className="space-y-6">
      <header className="flex items-center gap-3">
        <History aria-hidden="true" className="h-6 w-6 text-primary" />
        <div>
          <h1 className="font-title text-2xl font-semibold text-foreground">Trilha de auditoria</h1>
          <p className="text-sm text-muted-foreground">
            Tudo que mudou no sistema: quem fez, sobre o quê, quando e por quê.
          </p>
        </div>
      </header>

      {/* Faixa de filtros — largura inteira, três campos de peso igual. No
          telefone eles empilham, que é o que cabe em 390 px. */}
      <section
        aria-label="Filtros da trilha"
        className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4 shadow-e1 sm:flex-row sm:flex-wrap sm:items-end sm:gap-4"
      >
        <div className="flex min-w-[12rem] flex-1 flex-col gap-1.5">
          <Label htmlFor="filtro-tipo" className="text-xs text-muted-foreground">
            Tipo de registro
          </Label>
          <Select
            id="filtro-tipo"
            aria-label="Tipo de registro"
            value={filtros.itemType ?? ''}
            onChange={(v) => aplicar({ itemType: v || undefined })}
            options={[
              { value: '', label: 'Todos os tipos' },
              ...(tipos.data ?? []).map((t) => ({ value: t.value, label: t.label })),
            ]}
          />
        </div>

        <div className="flex min-w-[12rem] flex-1 flex-col gap-1.5">
          <Label htmlFor="filtro-evento" className="text-xs text-muted-foreground">
            Evento
          </Label>
          <Select
            id="filtro-evento"
            aria-label="Tipo de evento"
            value={filtros.event ?? ''}
            onChange={(v) => aplicar({ event: (v || undefined) as AuditTrailFilters['event'] })}
            options={[{ value: '', label: 'Todos os eventos' }, ...opcoesDeEvento]}
          />
        </div>

        <div className="flex min-w-[12rem] flex-1 flex-col gap-1.5">
          <Label htmlFor="filtro-periodo" className="text-xs text-muted-foreground">
            Período
          </Label>
          {/* ISO-8601 no valor, sempre (FE-440). O rótulo é pt-BR; o que
              trafega nunca é `dd/mm/aaaa`. */}
          <Select
            id="filtro-periodo"
            aria-label="Período"
            value={filtros.from ?? ''}
            onChange={(v) => aplicar({ from: v || undefined })}
            options={periodos}
          />
        </div>

        {/* Não é filtro novo: é a saída do filtro. Só aparece quando há o que
            limpar, para não ocupar a faixa com um botão morto. */}
        {temFiltro && (
          <Button variant="ghost" size="sm" onClick={limpar} className="self-start sm:self-end">
            <X aria-hidden="true" className="mr-2 h-4 w-4" />
            Limpar
          </Button>
        )}
      </section>

      <Card>
        <CardHeader className="flex-row items-baseline justify-between gap-3 space-y-0 pb-4">
          <CardTitle>Eventos</CardTitle>
          {meta && (
            <span className="shrink-0 text-xs text-muted-foreground">
              {meta.total.toLocaleString('pt-BR')} {meta.total === 1 ? 'evento' : 'eventos'}
              {temFiltro && ' no filtro'}
            </span>
          )}
        </CardHeader>

        <CardContent className="space-y-4">
          <AuditTrailTimeline
            versions={trilha.data?.versions ?? []}
            loading={trilha.isLoading}
            error={trilha.isError}
            onRetry={() => trilha.refetch()}
            onSelect={setSelecionada}
            emptyLabel="Nenhum evento neste filtro"
            emptyDescription="Nenhum registro corresponde aos filtros escolhidos."
          />

          {meta && meta.total > 0 && (
            <PaginationPill
              page={meta.page}
              totalPages={meta.totalPages}
              perPage={meta.perPage}
              loading={trilha.isFetching}
              onPageChange={(page) => setFiltros((a) => ({ ...a, page }))}
              onPerPageChange={(perPage) => setFiltros((a) => ({ ...a, perPage, page: 1 }))}
            />
          )}
        </CardContent>
      </Card>

      {/* Detalhe do evento: **diálogo**, não gaveta de formulário — o porquê
          está no cabeçalho do `AuditEventDialog`. */}
      <AuditEventDialog
        version={selecionada}
        snapshot={detalhe.data?.snapshot ?? null}
        snapshotLoading={selecionada !== null && detalhe.isLoading}
        onOpenChange={(aberto) => !aberto && setSelecionada(null)}
      />
    </div>
  )
}
