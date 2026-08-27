// DashboardPage component
import { useCallback } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { AlertTriangle } from 'lucide-react'
import PageHeader from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { mensagemDeErro } from '@/components/ui/AsyncSection'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { MasonryGrid } from '@/components/ui/MasonryGrid'
import { nomeDoMes } from '@/lib/utils/date'
import { ChartPanel } from '@/components/charts/ChartPanel'
import { SeriesLineChart } from '@/components/charts/SeriesLineChart'
import { SummaryCards } from '@/features/dashboard/components/SummaryCards'
import { DashboardFilters } from '@/features/dashboard/components/DashboardFilters'
import { LimitConsumptionPanel } from '@/features/dashboard/components/LimitConsumptionPanel'
import { CarrierExposurePanel } from '@/features/dashboard/components/CarrierExposurePanel'
import { NearCeilingPanel } from '@/features/dashboard/components/NearCeilingPanel'
import { OverdueRenegotiationsPanel } from '@/features/dashboard/components/OverdueRenegotiationsPanel'
import { dashboardApi, valoresDaSerie, DASHBOARD_SUMMARY_KEY } from '@/lib/api/dashboard'
import { useAuthStore } from '@/store/authStore'

/**
 * **Dashboard do console** — S15 / `NEW-002`.
 *
 * > **Feature NOVA (DEC-21), não paridade.** O `dash` do legado é uma tela vazia
 * > com uma única aba "GERAL" (`dash/_body.js.erb:8-22`), e não existe model,
 * > view SQL nem job que alimente indicador de painel na origem (`DB-399`,
 * > registrado como `dropped`). **O QA do Phase 4 não deve procurar esta tela no
 * > legado.** No `parity-ledger.md` ela entra como `new`.
 *
 * ## O que havia aqui antes
 *
 * O placeholder do Bloco 6 do trim. Esta tela era montada sobre
 * `GET /api/v1/analytics/dashboard` (AI9-010, removido no Bloco 2) e mostrava
 * KPIs de vendas, assinaturas e leads — as quatro features saíram do produto.
 * O comentário anterior dizia que *"o painel do Safegold nasce dos dados do
 * legado no Phase 2"*. É esta fatia, e é este arquivo.
 *
 * ## A regra que segura a tela: nenhum número nasce aqui
 *
 * Os quatro cartões e a série vêm de `GET /api/v1/dashboard/summary`, que é um
 * **compositor** dos serviços de domínio que já calculam cada valor para a tela
 * de detalhe (contrato **C2**). A exposição mostrada aqui é, byte a byte, a
 * mesma que o console de risco mostra na mesma data — porque é a mesma função.
 * Somar no cliente daria ao sistema dois números para a mesma coisa (**D-09**).
 *
 * ## Os quatro estados existem desde o primeiro commit
 *
 * São eles que aparecem numa demonstração antes de o seed rodar:
 *
 * - **escopo** — os dois 409 de projeto são *estado*, não erro (`ProjectScopeState`);
 * - **erro** — com "tentar de novo". O contêiner de resumo do legado **não tinha
 *   estado de erro** (FE-239), e é justamente o defeito que não se repete;
 * - **carregando** — esqueleto com a altura final, sem deslocar o layout;
 * - **sem dado** — "sem borderô no período", nunca `R$ 0,00` (D-117).
 *
 * ## Cada gráfico responde uma pergunta, e são três perguntas diferentes
 *
 * | Painel | A pergunta | Forma | De onde vem |
 * | ------ | ---------- | ----- | ----------- |
 * | Total operado por mês | *"a carteira está crescendo?"* | linha temporal | `Receivables::SearchService.monthly_totals` (S6) |
 * | Consumo de limite | *"ainda cabe operação?"* | medidor contra o teto | `Risk::AggregateService.total_limits_on` (S5) |
 * | Limites prestes a estourar | *"quem está na zona de perigo, e em que grau?"* | lista ordenada com medidor | `Risk::AggregateService.controls_near_ceiling_on` (S5, DEC-116) |
 * | Exposição por portador | *"onde está concentrado o risco?"* | ranking em barra | `Risk::AggregateService.volume_by_carrier_on` (S5) |
 * | Renegociações em atraso | *"o que já venceu, e quanto pesa?"* | tabela de três colunas | `Renegotiations::AggregateService.overdue_renegotiations_on` (S9/S13) |
 *
 * Três formas diferentes porque são três perguntas diferentes — repetir a linha
 * temporal com outra série encheria o espaço sem responder mais nada. E os três
 * saem de agregado **que já existe**: em painel de homologação, número que não
 * vem de agregado real é mentira em apresentação.
 *
 * ## O filtro de tempo: uma POSIÇÃO e uma JANELA (design G7)
 *
 * A tela mistura duas naturezas de tempo — ponto no tempo (exposição, limites,
 * renegociações) e período (total operado e a série). **Há exatamente um ponto
 * no tempo na página:** a data define a posição, e o período não é uma segunda
 * data — é uma janela ancorada nela ("os N meses que terminam no mês da data").
 * Dois seletores de data deixariam o usuário comparar números apurados em dias
 * diferentes sem perceber; assim isso é impossível por construção.
 *
 * Os dois vivem na **URL**, então o painel filtrado é um link que se manda para
 * alguém e o botão voltar funciona.
 *
 * ## Sem polling (Princípio 10)
 *
 * Não há `setInterval` nem `refetchInterval` nesta tela nem nos hooks que ela
 * usa. A atualização é o refetch do React Query ao navegar/focar; se um número
 * precisar ser vivo, o caminho é Action Cable.
 */
/**
 * "2025-09-01" → "setembro de 2025". Por extenso porque é o cabeçalho: `09/2025`
 * é notação de coluna de tabela, e a primeira linha da tela é onde a pessoa
 * decide se está olhando o que queria.
 */
function mesPorExtenso(iso: string): string {
  const [ano, mes] = iso.split('-')
  return `${nomeDoMes(new Date(Number(ano), Number(mes) - 1, 1)).toLowerCase()} de ${ano}`
}

/** `YYYY-MM-DD` de hoje, no fuso local — é a posição padrão do painel. */
function hojeIso(): string {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

const JANELAS_VALIDAS = [6, 12, 24]

export function DashboardPage() {
  const user = useAuthStore((s) => s.user)
  const primeiroNome = user?.name?.split(' ')?.[0]
  const [params, setParams] = useSearchParams()

  // Os dois filtros saem da URL, com validação na leitura: parâmetro torto na
  // barra de endereço não pode virar requisição torta nem tela quebrada.
  const dataBruta = params.get('date') ?? ''
  const date = /^\d{4}-\d{2}-\d{2}$/.test(dataBruta) ? dataBruta : hojeIso()
  const mesesBrutos = Number(params.get('months'))
  const months = JANELAS_VALIDAS.includes(mesesBrutos) ? mesesBrutos : 12

  const atualizar = useCallback(
    (chave: 'date' | 'months', valor: string) => {
      const proximo = new URLSearchParams(params)
      proximo.set(chave, valor)
      // `replace`: mexer no filtro não enche o histórico de uma entrada por
      // clique — o botão voltar continua saindo do painel.
      setParams(proximo, { replace: true })
    },
    [params, setParams],
  )

  const consulta = useQuery({
    queryKey: [...DASHBOARD_SUMMARY_KEY, date, months],
    queryFn: () => dashboardApi.summary({ date, months }),
    // O painel anterior fica na tela enquanto o novo chega: trocar tudo por
    // esqueleto numa atualização de fundo é o "flash de vazio" que faz o
    // usuário achar que perdeu o dado.
    placeholderData: (anterior) => anterior,
  })

  const escopo = projectScopeCode(consulta.error)
  const resumo = consulta.data
  const serie = resumo?.series ?? null

  return (
    <div className="space-y-6 pb-28">
      <PageHeader
        title="Dashboard"
        // O escopo na primeira linha: de QUAL projeto e de QUANDO é o que está
        // na tela. Sem isso a pessoa tem de conferir o seletor da barra lateral
        // para saber o que está lendo — e numa demonstração ninguém confere,
        // apenas acredita no número errado.
        subtitle={
          resumo
            ? `${resumo.project.name} · ${mesPorExtenso(resumo.period.from)} a ${mesPorExtenso(resumo.period.to)}`
            : primeiroNome
              ? `Bem-vindo de volta, ${primeiroNome}`
              : 'Resumo do projeto corrente'
        }
        loading={consulta.isFetching && !consulta.isLoading}
        rightSlot={
          <DashboardFilters
            date={date}
            months={months}
            disabled={consulta.isLoading}
            onDateChange={(iso) => atualizar('date', iso)}
            onMonthsChange={(m) => atualizar('months', String(m))}
          />
        }
      />

      {escopo ? (
        // `recurso` entra no meio de uma frase no PLURAL ("… são de um projeto
        // por vez"), então tem de ser um sintagma plural. Com "o resumo do
        // projeto" a tela dizia "O resumo do projeto SÃO de um projeto por vez"
        // — visto renderizando, não deduzido.
        <ProjectScopeState code={escopo} recurso="os números do resumo" />
      ) : consulta.isError ? (
        // A tela inteira falhou: um cartão em branco aqui seria pior que a
        // mensagem, porque parece número.
        <div
          role="alert"
          className="flex flex-col items-center gap-3 rounded-lg bg-card p-10 text-center shadow-e1"
        >
          <span className="flex h-12 w-12 items-center justify-center rounded-full bg-destructive/10 text-destructive">
            <AlertTriangle className="h-6 w-6" />
          </span>
          <div className="space-y-1">
            <h2 className="font-title text-lg font-semibold text-foreground">Não foi possível carregar o resumo</h2>
            <p className="max-w-md text-sm text-muted-foreground">
              {mensagemDeErro(consulta.error) ??
                'A consulta falhou. Nada foi perdido — os números continuam nas telas de detalhe.'}
            </p>
          </div>
          <Button variant="secondary" onClick={() => consulta.refetch()}>
            Tentar de novo
          </Button>
        </div>
      ) : (
        // **UM fluxo, não duas zonas.** Título de seção obriga cada grupo a ser
        // um contêiner próprio, e masonry só empacota **dentro** de um
        // contêiner: com "Carteira" e "Risco" separando, eram dois masonry
        // independentes e o vazio no fim do primeiro não podia ser preenchido
        // pelo primeiro bloco do segundo. Os títulos eram, em boa parte, a causa
        // do buraco que se queria eliminar.
        //
        // **O que substitui os títulos como orientação:** cada bloco já se
        // nomeia — o cartão diz TOTAL OPERADO, o painel diz "Consumo de limite
        // por tipo" e o subtítulo diz de quando é o número. O rótulo da zona
        // repetia um nível acima o que o bloco já dizia; o agrupamento continua
        // pela **ordem** (o dinheiro e a evolução primeiro, o risco depois) e
        // pela proximidade. Cada painel continua sendo uma `<section>` com nome
        // acessível — a estrutura para leitor de tela não se perdeu com o título.
        //
        // **Cartões numa metade, gráfico na outra** — o primeiro pedido do
        // usuário, e o que vale. O que antes obrigava a faixa a ocupar a tela
        // inteira era o rótulo longo quebrando e esticando o cartão; isso foi
        // resolvido **no `KpiCard`** (densidade `compact`: ícone ao lado do
        // rótulo, e o corpo do valor calculado pelo comprimento do texto),
        // então a largura deixou de ser a moeda de troca.
        <MasonryGrid className="xl:grid-cols-2">
          <div>
            {consulta.isLoading ? (
              // O esqueleto tem a MESMA forma do resultado — herói largo e três
              // compactos embaixo —, senão o layout salta quando o número chega.
              <div role="status" aria-busy aria-label="Carregando os indicadores" className="space-y-4">
                <div aria-hidden="true" className="h-[10.5rem] animate-pulse rounded-lg bg-muted/50" />
                <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-[1.7fr_1fr_1fr]">
                  {[0, 1, 2].map((i) => (
                    <div key={i} aria-hidden="true" className="h-[7rem] animate-pulse rounded-lg bg-muted/50" />
                  ))}
                </div>
              </div>
            ) : (
              resumo && <SummaryCards cards={resumo.cards} />
            )}
          </div>

            {/* A série só existe para quem pode ver recebíveis — o servidor
                manda `series: null` para quem não pode, e o gráfico some junto
                com o cartão, em vez de aparecer zerado. */}
            {(consulta.isLoading || serie) && (
              <ChartPanel
                title="Total operado por mês"
                subtitle="Valor bruto dos borderôs, mês a mês"
                loading={consulta.isLoading}
                hasData={serie?.has_data ?? false}
                emptyTitle="Sem borderô no período"
                emptyDescription="Nenhuma operação foi lançada na janela escolhida neste projeto. Assim que o primeiro borderô entrar, a série aparece aqui."
                labels={serie?.labels ?? []}
                values={valoresDaSerie(serie)}
                valueFormat="currency"
                labelHeader="Mês"
                valueHeader="Total operado"
              >
                <SeriesLineChart
                  labels={serie?.labels ?? []}
                  values={valoresDaSerie(serie)}
                  height={220}
                  measureLabel="Total operado por mês"
                />
              </ChartPanel>
            )}

            {/* **A troca é na ORIGEM, não por CSS.** Mover com `order` ou
                `grid-area` descasaria a ordem visual da ordem de leitura: quem
                navega por teclado ou leitor de tela passaria pelos blocos numa
                sequência diferente da que enxerga. Aqui a posição é
                consequência do DOM, e é o DOM que muda. */}
            {resumo?.limits && <CarrierExposurePanel date={resumo.date} />}
            {resumo?.overdue_renegotiations && (
              <OverdueRenegotiationsPanel dados={resumo.overdue_renegotiations} />
            )}
            {resumo?.limits && <LimitConsumptionPanel limites={resumo.limits} />}
            {resumo?.near_ceiling && <NearCeilingPanel dados={resumo.near_ceiling} />}
        </MasonryGrid>
      )}
    </div>
  )
}
