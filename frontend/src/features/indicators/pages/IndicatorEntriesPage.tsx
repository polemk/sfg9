import { useCallback, useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { PageHeader } from '@/components/PageHeader'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { useIsReadonly } from '@/hooks/useMyPermissions'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { indicatorEntriesApi, type GridRow } from '@/lib/api/indicators'
import { EntryFilters } from '../components/EntryFilters'
import { MonthlyGrid } from '../components/MonthlyGrid'
import { IndicatorSeriesChart } from '../components/IndicatorSeriesChart'
import { CarrierVolumeChart } from '../components/CarrierVolumeChart'
import { ANO_ATUAL } from '../lib/periodo'

/**
 * **Gestão › Lançamentos de indicadores** (`FE-324..FE-329`, `FE-718`,
 * `FE-719`).
 *
 * É a tela que o cliente usa de verdade todo mês. Grade à esquerda, cartão de
 * FILTROS à direita — o mesmo arranjo do legado.
 *
 * ## O rótulo do menu (`Q-R33`)
 *
 * No legado **dois itens de menu se chamam "Indicadores"**: um em Gestão (esta
 * tela, `indicator_entries`) e outro em Cadastro (o catálogo, `indicators`).
 * Aqui esta é **"Lançamentos de indicadores"** e a outra continua "Indicadores".
 *
 * ## O que mais muda
 *
 * - **Os filtros ficam na URL.** No legado eles se perdem entre visitas.
 * - **Não lançado ≠ zero** (DEC-70) — a distinção nasce no serviço e chega
 *   pronta como `entry: null`.
 * - **O autosave tem `onError`** — ver `EntryCell`. É a correção do pior estado
 *   de UI do bloco inteiro.
 * - **A falha da grade aparece.** O `AsyncSection` cobre os quatro estados; no
 *   legado o modo "silent" trocava a lista por nada enquanto recarregava, e o
 *   erro não tinha estado nenhum.
 *
 * ## Os dois gráficos são FEATURE NOVA — S15 / `NEW-001` (DEC-21.1)
 *
 * A nota que estava aqui dizia que **não há gráfico nesta tela**, porque não há
 * no legado. **Continua verdade sobre o legado**, e o QA do Phase 4 não deve
 * procurá-los lá: `Doughnut` é global em `index.js.erb:31,37` e nenhuma view o
 * instancia. O que mudou foi a **decisão do usuário** (DEC-21), que supera a
 * nota de escopo do DEC-09 em vez de contrariá-la por engano.
 *
 * Os dois entram **nesta** tela, sem tela nova e **sem filtro próprio**: a série
 * mensal desenha a MESMA `linhas` que a grade recebe (nenhuma segunda consulta,
 * nenhum segundo número), e o volume por portador deriva a data de apuração do
 * período filtrado aqui. Um gráfico com filtro próprio ao lado de uma tabela com
 * outro filtro produz duas verdades na mesma tela.
 *
 * **Variação, acumulado e média continuam fora de escopo** — o gráfico plota o
 * que está lançado, e só.
 */
export function IndicatorEntriesPage() {
  const [params, setParams] = useSearchParams()
  const somenteLeitura = useIsReadonly()

  // Filtros persistidos na URL — deep-link, não feature nova.
  const ano = Number(params.get('year')) || ANO_ATUAL
  const mesBruto = params.get('month')
  const mes = mesBruto && Number(mesBruto) >= 1 && Number(mesBruto) <= 12 ? Number(mesBruto) : null
  const indicadorId = params.get('indicator') || null

  const atualizar = useCallback(
    (chave: string, valor: string | null) => {
      const proximo = new URLSearchParams(params)
      if (valor === null) proximo.delete(chave)
      else proximo.set(chave, valor)
      setParams(proximo, { replace: true })
    },
    [params, setParams],
  )

  const consulta = useQuery({
    queryKey: ['indicator-grid', { ano, mes, indicadorId }],
    queryFn: () => indicatorEntriesApi.grid({ year: ano, month: mes, indicatorId: indicadorId }),
    // O `silent` do legado (que trocava a lista por nada durante a recarga)
    // vira isto: a grade anterior fica na tela enquanto a nova chega.
    placeholderData: (anterior) => anterior,
  })

  // O seletor "POR INDICADOR" lista **só os ativos do projeto**, como no legado.
  // Ele sai da própria grade sem filtro de indicador — uma consulta a menos e,
  // mais importante, **a mesma lista** que a grade desenha: duas consultas
  // diferentes é como o filtro passa a oferecer o que a grade não mostra.
  const listaCompleta = useQuery({
    queryKey: ['indicator-grid', { ano, mes, indicadorId: null }],
    queryFn: () => indicatorEntriesApi.grid({ year: ano, month: mes, indicatorId: null }),
    enabled: indicadorId !== null,
    placeholderData: (anterior) => anterior,
  })

  // Os dois 409 de escopo NÃO são falha: são um passo que falta (escolher
  // projeto) ou uma pendência administrativa (não participa de nenhum). Mostrar
  // "Não foi possível carregar" neles acusa o usuário de um erro que ele não
  // cometeu — e mostrar o vazio genérico afirma que não há indicador quando o
  // que falta é o projeto.
  const escopo = projectScopeCode(consulta.error)

  const indicadoresDoFiltro = useMemo(() => {
    const fonte: GridRow[] = (indicadorId ? listaCompleta.data : consulta.data) ?? []
    return fonte.map((linha) => linha.indicator)
  }, [indicadorId, listaCompleta.data, consulta.data])

  return (
    <div className="pb-10">
      <PageHeader
        title="Lançamentos de indicadores"
        subtitle="Preencha os indicadores do projeto mês a mês. Cada célula é salva sozinha ao sair do campo."
        loading={consulta.isFetching && !consulta.isLoading}
      />

      {somenteLeitura && (
        <p className="mb-4 rounded-md border border-border bg-muted/40 px-3 py-2 text-sm text-muted-foreground">
          Seu perfil está em <strong>modo somente leitura</strong>: os valores ficam visíveis, mas não
          são salvos.
        </p>
      )}

      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_18rem]">
        {/* Grade primeiro no DOM: no telefone os filtros ficam ABAIXO da grade,
            e é a grade que o usuário veio usar. */}
        <div className="order-2 min-w-0 lg:order-1">
          {escopo ? (
            <ProjectScopeState code={escopo} recurso="os lançamentos de indicadores" />
          ) : (
          <AsyncSection
            loading={consulta.isLoading}
            error={consulta.isError ? consulta.error : undefined}
            data={consulta.data}
            onRetry={() => consulta.refetch()}
            loadingLabel="Carregando a grade…"
            emptyTitle="Nenhum indicador neste projeto"
            emptyDescription="Conecte um indicador global ou crie um específico em Projeto › Indicadores específicos."
          >
            {(linhas) => (
              <div className="space-y-4">
                {/* O gráfico vem ANTES da grade no DOM porque é a leitura, e a
                    grade é a digitação: quem abre a tela para conferir o mês vê
                    a evolução primeiro; quem veio preencher rola uma tela. */}
                <IndicatorSeriesChart linhas={linhas} indicadorId={indicadorId} ano={ano} mes={mes} />
                <MonthlyGrid linhas={linhas} year={ano} mes={mes} somenteLeitura={somenteLeitura} />
              </div>
            )}
          </AsyncSection>
          )}

          {/* Volume por portador: vem do bloco de risco, não da grade — por isso
              fica fora do `AsyncSection` dela e tem os próprios estados. */}
          {!escopo && <div className="mt-4"><CarrierVolumeChart ano={ano} mes={mes} /></div>}
        </div>

        <div className="order-1 lg:order-2">
          <EntryFilters
            indicadores={indicadoresDoFiltro}
            indicadorId={indicadorId}
            mes={mes}
            ano={ano}
            onIndicadorChange={(id) => atualizar('indicator', id)}
            onMesChange={(m) => atualizar('month', m === null ? null : String(m))}
            onAnoChange={(a) => atualizar('year', String(a))}
          />
        </div>
      </div>
    </div>
  )
}
