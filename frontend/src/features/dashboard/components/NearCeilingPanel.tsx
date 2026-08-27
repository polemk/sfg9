import { Link } from 'react-router-dom'
import { ShieldCheck } from 'lucide-react'
import { ChartPanel } from '@/components/charts/ChartPanel'
import { LimitMeters } from '@/components/charts/LimitMeters'
import { formatPercent } from '@/lib/utils/number'
import { numeroDe, type DashboardNearCeiling } from '@/lib/api/dashboard'

/**
 * **"Quem está prestes a estourar?"** — os limites com 90% ou mais do teto
 * consumido (**DEC-116**).
 *
 * ## Por que é lista, e não mais um número
 *
 * O cartão "Limites no teto" responde **quantos** já atingiram 100%. Este painel
 * responde **quem** está na zona de perigo, e **em que grau** — porque 89% e 99%
 * têm urgências completamente diferentes e uma contagem apagaria essa diferença.
 * É a diferença entre saber que há risco e saber onde ele está.
 *
 * ## A faixa é fechada dos dois lados, e é o que separa os dois indicadores
 *
 * `>= 90%` **e** `< 100%`. **Quem já estourou não está "prestes" a nada** — já
 * aconteceu, e ele é contado pelo cartão irmão. Cada limite aparece em
 * exatamente um dos dois: com sobreposição, os dois respondiam parcialmente a
 * mesma coisa e nenhum respondia inteiro, e o leitor tinha de reler cada
 * porcentagem para separar o que ainda dá para evitar do que já é fato
 * consumado.
 *
 * O corte de cima é aplicado no domínio pelo **sinal do disponível**, junto com
 * a porcentagem: com teto zero a porcentagem não existe, e filtrar só por ela
 * deixaria esses limites escaparem pela borda que a divisão por zero abre.
 *
 * ## O estado vazio é uma resposta, não um buraco
 *
 * "Nenhum limite acima de 90%" é a notícia boa, e é o que o cliente mais vai ver.
 * Ele merece o mesmo cuidado do resto: ícone de tranquilidade, a frase que
 * afirma o que foi conferido, e a data em que foi conferido. Um espaço em branco
 * no lugar diria "não sei".
 *
 * ## A porcentagem é formatada AQUI
 *
 * O domínio manda `98.7`; quem escreve `98,7%` é `formatPercent`
 * (`Intl.NumberFormat` pt-BR, `lib/utils/number`), pela mesma regra que tirou a
 * formatação monetária do backend (OPS-289). O ponto decimal de JavaScript não
 * chega à tela.
 */
export function NearCeilingPanel({ dados }: { dados: DashboardNearCeiling }) {
  const emExtenso = dados.date.split('-').reverse().join('/')

  const itens = dados.items.map((item) => ({
    id: item.id,
    label: item.title,
    // **O TIPO, não o portador.** O título do limite é derivado do portador
    // (`RiskControl#derive_title_and_project`), então "portador" repetia a
    // primeira metade da linha: `FIDC Aurora Crédito · FIDC Aurora Crédito`,
    // visto na tela. O tipo é o que diferencia dois limites do mesmo portador —
    // e é o que faltava para a linha ser identificável.
    sublabel: item.operation_type_title || undefined,
    used: numeroDe(item.used) ?? 0,
    total: numeroDe(item.total) ?? 0,
    available: numeroDe(item.available) ?? 0,
    // Uma casa decimal: com duas, "98,70%" sugere uma precisão que a decisão
    // de negócio não usa; com zero, 89,6% e 90,4% viram o mesmo "90%" — dos
    // dois lados do corte.
    percentLabel: formatPercent(item.percent, 1),
    // **Toda linha desta lista é atenção, nenhuma é perigo.** Quem estourou não
    // está aqui (ele é do cartão), e verde diria "está tudo bem" a um limite a
    // 99% do teto. É o terceiro estado do medidor, e o token dele foi escolhido
    // por contraste medido, não por nome (ver `chartTokens`).
    tone: 'warning' as const,
  }))

  return (
    <ChartPanel
      title="Limites prestes a estourar"
      subtitle={
        dados.has_data
          ? `${itens.length} ${itens.length === 1 ? 'limite entre' : 'limites entre'} ${dados.threshold}% e 100% do teto em ${emExtenso} — ainda dá tempo de agir`
          : `Conferido em ${emExtenso}, sobre todos os limites ativos do projeto`
      }
      hasData={dados.has_data}
      emptyTitle={`Nenhum limite entre ${dados.threshold}% e 100%`}
      emptyDescription="Nenhum limite ativo do projeto está na faixa de atenção. Assim que algum entrar, ele aparece aqui com a porcentagem em que está."
      emptyState={
        // O estado vazio deste painel é uma **boa notícia**, e o ícone genérico
        // de "caixa vazia" diria o contrário. Aqui ele afirma o que foi
        // conferido, em vez de sugerir que faltou dado.
        <div role="status" className="flex min-h-[8rem] flex-col items-center justify-center gap-3 text-center">
          <span className="flex h-11 w-11 items-center justify-center rounded-full bg-success/10 text-success">
            <ShieldCheck className="h-5 w-5" />
          </span>
          <div className="space-y-1">
            <p className="text-sm font-semibold text-foreground">
              Nenhum limite entre {dados.threshold}% e 100%
            </p>
            <p className="max-w-sm text-xs text-muted-foreground">
              Nenhum limite ativo do projeto está na faixa de atenção em {emExtenso}. Assim que algum
              entrar, ele aparece aqui com a porcentagem em que está.
            </p>
          </div>
        </div>
      }
      labels={itens.map((i) => i.label)}
      values={itens.map((i) => i.used)}
      valueFormat="currency"
      labelHeader="Limite"
      valueHeader="Utilizado"
      headerSlot={
        <Link
          to="/risk-controls"
          className="rounded-md text-xs font-medium text-primary-text underline-offset-2 hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          Ver os limites
        </Link>
      }
    >
      <LimitMeters items={itens} />
    </ChartPanel>
  )
}
