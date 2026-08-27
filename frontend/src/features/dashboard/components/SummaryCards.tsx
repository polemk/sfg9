import { Link } from 'react-router-dom'
import { Receipt, ShieldAlert, SlidersHorizontal, RefreshCcw, Gauge, type LucideIcon } from 'lucide-react'
import { KpiCard } from '@/components/kpi/KpiCard'
import { formatAmount, formatMoney } from '@/lib/utils/number'
import { numeroDe, type DashboardCard } from '@/lib/api/dashboard'

/**
 * S15 / `NEW-002` (parte 1) — **os quatro números da tela inicial**.
 *
 * ## Três regras, e nenhuma é de layout
 *
 * **1. O ícone é a única coisa que o cliente decide.** Rótulo, valor, contexto e
 * destino vêm do payload. Com a rota codificada aqui, o dia em que o menu
 * mudasse deixaria o painel apontando para uma tela que não existe — e ninguém
 * procuraria o motivo neste arquivo.
 *
 * **2. Ausente não é zero** (D-117). `value: null` vira `—` com a explicação
 * embaixo; `R$ 0,00` fica reservado para o zero de verdade. Num sistema de
 * crédito "não operamos nada" e "não sabemos" levam a decisões opostas.
 *
 * **3. Nada é somado aqui.** A moeda é formatada pelo helper único (`FE-431`,
 * `lib/utils/number`), e é só isso que este componente faz com o número.
 *
 * ## Cartão que não veio
 *
 * A lista pode ter menos de quatro itens: o servidor **omite** o cartão que o
 * papel não pode ler, em vez de mandá-lo zerado. Este componente desenha o que
 * chegou, sem buraco reservado — um espaço vazio anunciaria a existência do
 * dado que a permissão esconde.
 */
const ICONES: Record<string, LucideIcon> = {
  total_operado: Receipt,
  exposicao: ShieldAlert,
  limites_no_teto: SlidersHorizontal,
  renegociacoes_em_atraso: RefreshCcw,
}

/**
 * O texto que ocupa o lugar do número quando ele não existe. É específico por
 * cartão porque "não há" tem causas diferentes, e a causa é o que o usuário
 * precisa saber para agir.
 */
const AUSENCIA: Record<string, string> = {
  total_operado: 'Sem borderô no período',
  exposicao: 'Nenhum limite ativo no projeto',
  limites_no_teto: 'Nenhum limite ativo no projeto',
  renegociacoes_em_atraso: 'Nenhuma renegociação no projeto',
}

function valorLegivel(cartao: DashboardCard): string {
  const n = numeroDe(cartao.value)
  if (n === null) return '—'
  // Contagem inteira não leva casas decimais: "2,00 limites no teto" seria uma
  // precisão que o dado não tem.
  return cartao.format === 'currency' ? formatMoney(n) : formatAmount(n, 0)
}

/**
 * **Herói na linha inteira; embaixo, três cartões de larguras DIFERENTES.**
 *
 * ```
 * ┌──────────────────────────────────────────────┐
 * │ TOTAL OPERADO      R$ 174.493.854,98         │  ← o número da carteira
 * ├────────────────────┬───────────┬─────────────┤
 * │ EXPOSIÇÃO          │ NO TETO 1 │ ATRASO    1 │
 * └────────────────────┴───────────┴─────────────┘
 * ```
 *
 * ## A largura segue o CONTEÚDO, e é isso que a torna certa
 *
 * `R$ 17.050.735,05` são 16 caracteres; `1` é um. Dar a mesma largura aos três
 * desperdiça espaço nos contadores e aperta justamente o valor monetário — o
 * número que **já foi cortado quatro vezes** nesta tela, em quatro larguras
 * diferentes. Com `2fr / 1fr / 1fr` a coluna do dinheiro cresce e as das
 * contagens encolhem, e o problema deixa de existir por desenho em vez de por
 * ajuste de fonte.
 *
 * É também o alívio prático do `UF-S15-03` (o `KpiCard` não encolhe nem trunca
 * valor longo): em vez de espremer, dá-se a coluna que o valor precisa.
 *
 * ## O destaque continua sendo do Total operado
 *
 * Ele é o único da primeira linha e leva o contorno de marca
 * (`card-highlight`). Os outros três são recortes: a exposição é a posição de
 * risco, e os dois contadores são ocorrências.
 *
 * ## O corpo do valor deixou de ser problema desta tela
 *
 * Ele era ajustado daqui por seletor de descendente, e foi **cinco vezes**, em
 * cinco larguras diferentes — a evidência que fez a conta subir para o
 * `KpiCard`, que é quem sabe a largura do próprio cartão (`UF-S15-03`, corrigido
 * na base com aval explícito). Aqui só se escolhe a **densidade**: `default` no
 * herói, `compact` nos três de baixo.
 */
const CHAVE_PRINCIPAL = 'total_operado'


function CartaoLigado({ cartao, density }: { cartao: DashboardCard; density: 'default' | 'compact' }) {
  const Icone = ICONES[cartao.key] ?? Gauge
  const ausente = numeroDe(cartao.value) === null
  const principal = cartao.key === CHAVE_PRINCIPAL

  return (
    <Link
      to={cartao.href}
      // O cartão inteiro é o alvo: no telefone um link de texto dentro de um
      // card de 6rem é um alvo que ninguém acerta (DEC-100).
      className={[
        // `h-full` no elo E no cartão: os três da fileira têm conteúdo de
        // alturas diferentes (o selo do dinheiro é uma linha, a data da contagem
        // é outra) e sem isto a fileira terminava em degrau. Visto na tela.
        'block h-full rounded-lg [&>*]:h-full focus-visible:outline-none focus-visible:ring-2',
        'focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background',
      ].join(' ')}
      aria-label={`${cartao.label}: ${valorLegivel(cartao)}. Abrir a tela correspondente`}
    >
      <KpiCard
        title={cartao.label}
        value={valorLegivel(cartao)}
        icon={Icone}
        // O badge de variação do `KpiCard` seria uma comparação mês a mês —
        // série derivada, que a nota de escopo de `indicators` mantém fora. Aqui
        // ele carrega o CONTEXTO do número (o período, a data de apuração), que
        // é informação de verdade.
        // **O selo de data sai dos contadores.** A coluna de contagem tem ~153 px
        // e o selo "em 26/08/2026" ao lado do ícone precisa de ~140 px: ele
        // quebrava em duas linhas e o título junto. A data de apuração já está
        // no subtítulo de cada painel de risco, então aqui ela era repetição que
        // custava a legibilidade do próprio cartão. **Quando o valor está
        // ausente o selo volta**, porque aí ele não repete nada — ele diz por
        // que não há número, que é a única informação que a tela tem.
        // **O selo só aparece quando o valor NÃO existe.** Com o filtro de
        // tempo no cabeçalho, a data de apuração e a janela estão escritas uma
        // vez no alto da página, e cada painel de risco repete a sua no
        // subtítulo — o selo em cada cartão era a terceira e a quarta vez. O que
        // ele passa a carregar é a única informação que a tela não tem em outro
        // lugar: **por que não há número**.
        changeLabel={ausente ? AUSENCIA[cartao.key] : undefined}
        changeType="neutral"
        glow={principal}
        density={density}
        // Quando falta número, o rodapé diz de QUANDO era a apuração que não
        // achou nada — sem isso "Sem borderô no período" não diz qual período.
        footer={ausente ? <p className="text-[10px] text-muted-foreground">{cartao.hint}</p> : undefined}
      />
    </Link>
  )
}

export function SummaryCards({ cards }: { cards: DashboardCard[] }) {
  const heroi = cards.find((c) => c.key === CHAVE_PRINCIPAL) ?? null
  const demais = cards.filter((c) => c !== heroi)

  return (
    <div className="space-y-3 sm:space-y-4">
      {heroi && <CartaoLigado cartao={heroi} density="default" />}

      {demais.length > 0 && (
        // `2fr 1fr 1fr` só quando há espaço para três colunas. Abaixo disso a
        // proporção não ajuda — ela só apertaria os três de uma vez.
        <div
          className={[
            // **No telefone a fileira é 2 colunas, não 1.** Empilhar os três em
            // coluna única custava três alturas de cartão inteiras antes de o
            // primeiro gráfico aparecer — e um contador de UM dígito não precisa
            // dos 390 px de largura do aparelho. Os cartões de dinheiro seguem
            // ocupando a linha toda (o valor é longo); os contadores dividem.
            'grid grid-cols-2 gap-3 sm:gap-4',
            // **A proporção sai do rótulo mais longo, medido.**
            // `RENEGOCIAÇÕES EM ATRASO` são 23 caracteres a 10 px com
            // `tracking-[0.2em]` (~8,2 px por caractere) = ~189 px, mais o
            // respiro do cartão compacto (32 px) = **~221 px de piso**. A
            // Exposição precisa de ~258 px para `R$ 17.050.735,05` mais 48 px
            // de respiro = ~306 px. A razão natural é 306 : 221 : 221, e daí
            // sai `1.4fr 1fr 1fr`.
            //
            // **É por isso que esta fileira ocupa a largura inteira.** Em meia
            // tela (~612 px úteis) o piso somado dos três dá ~748 px: não cabe,
            // e foi tentando fazer caber que o rótulo quebrou em duas linhas e
            // o cartão cresceu em altura.
            // **A fileira vive em META tela (~612 px úteis), e a proporção sai
            // daí.** `1.7fr 1fr 1fr` dá ~281/165/165: a Exposição fica com
            // ~249 px de texto, onde `R$ 17.050.735,05` cabe em `text-2xl`
            // (~230 px), e os contadores com ~133 px, onde o rótulo mais longo
            // quebra em **duas linhas equilibradas sem esticar o cartão** —
            // porque no modo compacto o ícone está ao lado dele, não acima.
            demais.length === 3 ? 'lg:grid-cols-[1.7fr_1fr_1fr]' : 'lg:grid-cols-3',
          ].join(' ')}
        >
          {demais.map((cartao) => (
            <div
              key={cartao.key}
              // `currency` atravessa as duas colunas no telefone: `R$
              // 17.050.735,05` não cabe em meia largura de 390 px sem encolher a
              // ponto de não se ler. `integer` divide, que é o ganho.
              className={cartao.format === 'currency' ? 'col-span-2 sm:col-span-1' : undefined}
            >
              <CartaoLigado cartao={cartao} density="compact" />
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
