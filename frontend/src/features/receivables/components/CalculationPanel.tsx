import { AlertTriangle } from 'lucide-react'
import { Badge } from '@/components/ui/Badge'
import { Spinner } from '@/components/ui/Spinner'
import { Tooltip } from '@/components/ui/Tooltip'
import { formatAmount, formatMoney, formatPercent } from '@/lib/utils/number'
import type { ReceivableDerived } from '../api/receivables'

/**
 * **O painel de cálculo do borderô** — os 37 valores derivados, somente leitura.
 *
 * ## Tudo aqui vem do servidor. Nada é calculado nesta tela.
 *
 * Não há uma multiplicação, um `Math.pow` nem um arredondamento neste arquivo.
 * Os números chegam prontos de `POST /receivables/preview`, que chama o
 * **mesmo** `Receivables::Calculator` da gravação (contrato **C2**).
 *
 * É o que fecha o **D-09** na raiz: no legado a conta existia também em
 * JavaScript (`../sfg/app/views/pub/receivables/new/_body.js.erb:339-504`),
 * **parcial** — não calculava `taxa_desconto_nominal_*`,
 * `custo_efetivo_com_float_*`, `multiplicador_*` nem os `*_percent` — e com
 * outro arredondamento no total de tarifas. O usuário via um número na tela e
 * outro depois de salvar.
 *
 * ## Nulo não é zero (D-117)
 *
 * `formatMoney(null)` rende travessão; `formatMoney(0)` rende `R$ 0,00`. No
 * legado os dois viravam `R$ 0,00`, e num sistema de crédito isso confunde
 * "não informado" com "zero". Vários derivados são **legitimamente nulos**: as
 * guardas `< 1` do legado devolvem `nil`, e em 97% dos borderôs de produção a
 * de IOF dispara.
 *
 * ## As três divergências do legado ficam VISÍVEIS, com o porquê
 *
 * `custo_efetivo_com_float_total` arredonda em 2 casas sobre a mesma base que o
 * CET PM EMP arredonda em 4 (Q-B8); a guarda do CET do banco sem IOF olha o
 * prazo da **empresa** (Q-B7); e o líquido correto é aproximação **linear**
 * (Q-B6). As três são replicadas por DEC-30 e travadas por golden. O tooltip
 * diz isso na tela em vez de deixar o número parecer errado sem explicação.
 */
function Linha({
  rotulo,
  valor,
  ajuda,
  destaque,
}: {
  rotulo: string
  valor: React.ReactNode
  ajuda?: string
  destaque?: boolean
}) {
  const conteudo = (
    <div className="flex items-baseline justify-between gap-3 py-1">
      <dt className={'text-xs ' + (destaque ? 'font-medium text-foreground' : 'text-muted-foreground')}>
        {rotulo}
      </dt>
      <dd
        className={
          'font-numeric tabular-nums ' + (destaque ? 'text-base font-semibold text-foreground' : 'text-sm text-foreground')
        }
      >
        {valor}
      </dd>
    </div>
  )
  // `className="block"` no gatilho, e não é detalhe de estilo: o padrão do
  // `Tooltip` é `inline-block`, e com ele duas linhas do painel colapsavam na
  // MESMA linha ("CET com float total 2,06%CET com float sem IOF —"). Só
  // apareceu na captura da tela — `tsc` e `vitest` passavam com o painel
  // ilegível.
  return ajuda ? (
    <Tooltip content={ajuda} className="block w-full" side="left">
      {conteudo}
    </Tooltip>
  ) : (
    conteudo
  )
}

function Grupo({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <section className="rounded-md border border-border bg-card p-3">
      <h4 className="mb-1 font-title text-xs font-semibold uppercase tracking-[0.05em] text-muted-foreground">
        {titulo}
      </h4>
      <dl className="divide-y divide-border/60">{children}</dl>
    </section>
  )
}

/** `decimal` do Postgres chega como string; `null` continua `null`. */
function n(v: string | number | null | undefined): number | null {
  if (v === null || v === undefined || v === '') return null
  const x = typeof v === 'number' ? v : Number(v)
  return Number.isFinite(x) ? x : null
}

export function CalculationPanel({
  derived,
  loading,
  refreshing,
  problema,
  incompleto,
}: {
  derived: ReceivableDerived | null
  loading: boolean
  refreshing: boolean
  problema: string | null
  incompleto: boolean
}) {
  if (incompleto) {
    return (
      <div className="rounded-lg border border-dashed border-border px-4 py-8 text-center text-sm text-muted-foreground">
        Preencha o valor bruto, a quantidade de títulos e os dois prazos médios ponderados para ver o cálculo.
        <br />
        <span className="text-xs">Os dois prazos precisam ser maiores que zero — eles dividem seis fórmulas.</span>
      </div>
    )
  }

  if (problema) {
    return (
      <div className="flex items-start gap-3 rounded-lg border border-border bg-muted/40 px-4 py-4 text-sm">
        <AlertTriangle aria-hidden="true" className="mt-0.5 h-4 w-4 shrink-0 text-muted-foreground" />
        <div>
          <p className="font-medium text-foreground">Não dá para calcular com estes valores</p>
          {/* A mensagem é a do SERVIDOR. Reescrevê-la aqui daria duas versões da
              mesma regra, e é a do servidor que decide se o borderô grava. */}
          <p className="mt-0.5 text-muted-foreground">{problema}</p>
        </div>
      </div>
    )
  }

  if (loading || !derived) {
    return (
      <div className="flex items-center justify-center gap-2 rounded-lg border border-border px-4 py-8 text-sm text-muted-foreground">
        <Spinner className="h-4 w-4" />
        Calculando…
      </div>
    )
  }

  const diferenca = derived.status === 'difference'

  return (
    <div className={'space-y-3 transition-opacity ' + (refreshing ? 'opacity-60' : '')}>
      <Grupo titulo="Resultado">
        <Linha rotulo="Valor bruto final" valor={formatMoney(n(derived.vlr_bruto_final))} />
        <Linha rotulo="Total de tarifas" valor={formatMoney(n(derived.valor_total_tarifas))} />
        <Linha rotulo="Valor líquido" valor={formatMoney(n(derived.valor_liquido))} destaque />
        <Linha rotulo="Líquido recebido" valor={formatMoney(n(derived.vlr_liq_recebido))} />
        <Linha rotulo="Títulos finais" valor={derived.qtd_final ?? '—'} />
      </Grupo>

      <Grupo titulo="Tarifas por classificador">
        <Linha rotulo="AdValorem" valor={formatMoney(n(derived.tarifas_ad_valorem))} />
        <Linha rotulo="Deságio" valor={formatMoney(n(derived.tarifas_desagio))} />
        <Linha rotulo="IOF" valor={formatMoney(n(derived.tarifas_iof))} />
        <Linha
          rotulo="Outras"
          valor={formatMoney(n(derived.tarifas_outras))}
          ajuda="É o RESTO: total menos AdValorem, Deságio e IOF. Fica negativo se algum tipo tiver dois classificadores — comportamento do legado, preservado."
        />
        <Linha
          rotulo="IOF esperado"
          valor={formatMoney(n(derived.checagem_iof))}
          ajuda="Conferência: o IOF que a alíquota vigente na data da operação produziria sobre a base (bruto final menos AdValorem e Deságio)."
        />
      </Grupo>

      <Grupo titulo="Custo efetivo — empresa">
        <Linha
          rotulo="CET PM EMP"
          valor={formatPercent(n(derived.custo_efetivo_pz_med_emp), 4)}
          ajuda="É a coluna que a lista ordena. Quatro casas."
        />
        <Linha rotulo="CET PM EMP sem IOF" valor={formatPercent(n(derived.custo_efetivo_pz_med_emp_sem_iof), 4)} />
        <Linha rotulo="CET sem float" valor={formatPercent(n(derived.custo_efetivo_sem_float), 4)} />
        <Linha
          rotulo="CET com float total"
          valor={formatPercent(n(derived.custo_efetivo_com_float_total), 2)}
          ajuda="Duas casas, sobre a MESMA base que o CET PM EMP arredonda em quatro. A divergência é do legado e foi preservada de propósito — há teste travando os dois."
        />
        <Linha
          rotulo="CET com float sem IOF"
          valor={formatPercent(n(derived.custo_efetivo_com_float_sem_iof), 2)}
          ajuda="Nulo quando não há IOF de pelo menos um real. Em 97% dos borderôs de produção esta guarda dispara."
        />
      </Grupo>

      <Grupo titulo="Custo efetivo — banco">
        <Linha rotulo="CET PM BCO" valor={formatPercent(n(derived.custo_efetivo_pz_med_banco), 4)} />
        <Linha
          rotulo="CET PM BCO sem IOF"
          valor={formatPercent(n(derived.custo_efetivo_pz_med_banco_sem_iof), 4)}
          ajuda="A guarda desta fórmula olha o prazo da EMPRESA, não o do banco. Parece copy/paste do legado e foi preservada como está — há teste travando o comportamento."
        />
      </Grupo>

      <Grupo titulo="Taxas nominais">
        <Linha
          rotulo="Deságio + AdValorem (banco)"
          valor={formatPercent(n(derived.taxa_desconto_nominal_desagio_advalorem_bancos), 2)}
          ajuda="Nulo quando o líquido ou o deságio ficam abaixo de um real. Guarda do legado, preservada."
        />
        <Linha
          rotulo="Despesas (banco)"
          valor={formatPercent(n(derived.taxa_desconto_nominal_despesas_bancos), 2)}
        />
        <Linha
          rotulo="Despesas + IOF (banco)"
          valor={formatPercent(n(derived.taxa_desconto_nominal_despesas_iof_bancos), 2)}
          ajuda="Esta variante NÃO tem a guarda de um real que as outras duas têm. A assimetria é do legado."
        />
        <Linha
          rotulo="Deságio + AdValorem (empresa)"
          valor={formatPercent(n(derived.taxa_desconto_nominal_desagio_advalorem_emp), 2)}
        />
        <Linha rotulo="Despesas (empresa)" valor={formatPercent(n(derived.taxa_desconto_nominal_despesas_emp), 2)} />
        <Linha
          rotulo="Despesas + IOF (empresa)"
          valor={formatPercent(n(derived.taxa_desconto_nominal_despesas_iof_emp), 2)}
        />
        <Linha
          rotulo="Taxa nominal apurada"
          valor={formatPercent(n(derived.nominal_tax_check), 2)}
          ajuda="Apurada a partir do deságio. A taxa nominal que você informa acima NÃO é validada contra ela — é comparação informativa, como no legado."
        />
        <Linha
          rotulo="Taxa nominal com float"
          valor={formatPercent(n(derived.nominal_tax_check_with_float), 2)}
        />
      </Grupo>

      <Grupo titulo="Float e prazos">
        <Linha rotulo="Float calculado" valor={`${formatAmount(n(derived.float_calculado), 2)} dias`} />
        <Linha
          rotulo="Diferença de float"
          valor={`${formatAmount(n(derived.diferenca_float), 2)} dias`}
          ajuda="Float calculado menos o acordado, com piso em zero. Nunca fica negativa — regra do legado."
        />
        <Linha rotulo="Multiplicador PM empresa" valor={formatAmount(n(derived.multiplicador_pm_empresa), 2)} />
        <Linha rotulo="Multiplicador PM float" valor={formatAmount(n(derived.multiplicador_pm_float), 2)} />
      </Grupo>

      <Grupo titulo="Deduções">
        <Linha rotulo="Recompra" valor={formatPercent(n(derived.recompra_percent), 2)} />
        <Linha rotulo="Retenção" valor={formatPercent(n(derived.retencao_percent), 2)} />
        <Linha rotulo="Fomento" valor={formatPercent(n(derived.fomento_percent), 2)} />
        <Linha rotulo="Outros" valor={formatPercent(n(derived.outros_percent), 2)} />
        <Linha rotulo="Total de deduções" valor={formatMoney(n(derived.total_deducoes))} />
      </Grupo>

      <Grupo titulo="Conferência da taxa acordada">
        <Linha
          rotulo="Líquido correto"
          valor={formatMoney(n(derived.calc_valor_liq_correto))}
          ajuda="O líquido que a taxa acordada produziria. É uma aproximação LINEAR (juros simples), não desconto composto — a fórmula do legado, preservada."
        />
        <Linha rotulo="Diferença" valor={formatMoney(n(derived.dif_calc_vlr_liq))} />
        <div className="flex items-center justify-between gap-3 py-2">
          <dt className="text-xs text-muted-foreground">Situação</dt>
          <dd>
            {diferenca ? (
              <Tooltip content="O líquido ficou ABAIXO do líquido esperado pela taxa acordada.">
                <Badge variant="secondary">{derived.status_label ?? 'Diferença'}</Badge>
              </Tooltip>
            ) : (
              <span className="text-sm text-foreground">{derived.status_label ?? 'OK'}</span>
            )}
          </dd>
        </div>
      </Grupo>
    </div>
  )
}
