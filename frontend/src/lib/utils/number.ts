/**
 * Número em pt-BR — formatação, e o parse que **desfaz** a formatação.
 *
 * A regra do app, que vale para `MoneyInput`, `PercentInput` e para toda coluna
 * de valor: **exibe formatado, envia número**. O que sai daqui para a API é
 * sempre `number` — nunca `"1.234,56"`, que é o erro clássico de virar `1234.56`
 * no servidor de um jeito e `1.23456` de outro.
 *
 * Nota de tipografia: todo texto produzido aqui deve ser renderizado com
 * `font-numeric` (Fira Mono + `tabular-nums`). Sem isso a coluna de valor de um
 * borderô não alinha, e neste app isso é defeito, não estética.
 */

import { APP_CURRENCY } from '@/lib/config/currency'

// A moeda vem da configuracao do app, nao daqui. Estava cravada como 'BRL' em
// sete lugares do frontend — sete copias nao sao sete decisoes, sao uma decisao
// que ninguem consegue mudar sem esquecer uma delas.
const fmtMoeda = new Intl.NumberFormat(APP_CURRENCY.locale, {
  style: 'currency',
  currency: APP_CURRENCY.code,
  minimumFractionDigits: APP_CURRENCY.minorUnits,
  maximumFractionDigits: APP_CURRENCY.minorUnits,
})

const fmtDecimal = (min: number, max: number) =>
  new Intl.NumberFormat(APP_CURRENCY.locale, { minimumFractionDigits: min, maximumFractionDigits: max })

/** `1234.5` → `R$ 1.234,50`. */
export function formatMoney(value: number | null | undefined, fallback = '—'): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return fallback
  return fmtMoeda.format(value)
}

/** `1234.5` → `1.234,50` (sem o símbolo — para célula de tabela densa). */
export function formatAmount(value: number | null | undefined, casas = 2, fallback = '—'): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return fallback
  return fmtDecimal(casas, casas).format(value)
}

/**
 * `1234567.89` → `R$ 1,2 mi`. **Só para rótulo de EIXO de gráfico.**
 *
 * Existe porque o eixo Y de um gráfico em reais com sete dígitos ou mais não
 * cabe na margem: os rótulos saíam cortados (`00000`, `0`) — visto renderizando
 * no painel. Notação compacta resolve a largura sem esconder informação: o valor
 * **exato** continua no tooltip e na tabela de valores, que é onde ele é lido.
 *
 * Não é uma segunda formatação de moeda (FE-431): `formatMoney` continua sendo a
 * única forma de escrever um valor para leitura. Este é rótulo de escala, e mora
 * no mesmo arquivo pelo mesmo motivo — um lugar só decide como número vira texto.
 */
const fmtCompacto = new Intl.NumberFormat(APP_CURRENCY.locale, {
  style: 'currency',
  currency: APP_CURRENCY.code,
  notation: 'compact',
  maximumFractionDigits: 1,
})

export function formatMoneyCompact(value: number | null | undefined, fallback = '—'): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return fallback
  return fmtCompacto.format(value)
}

/** `1234567.89` → `1,2 mi`. O irmão sem símbolo, para eixo de valor não monetário. */
const fmtCompactoSimples = new Intl.NumberFormat(APP_CURRENCY.locale, {
  notation: 'compact',
  maximumFractionDigits: 1,
})

export function formatAmountCompact(value: number | null | undefined, fallback = '—'): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return fallback
  return fmtCompactoSimples.format(value)
}

/** `12.5` → `12,50%`. O valor é o percentual, não a fração. */
export function formatPercent(value: number | null | undefined, casas = 2, fallback = '—'): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return fallback
  return `${fmtDecimal(casas, casas).format(value)}%`
}

/**
 * O percentual que o **servidor** já formatou (`"51.76%"`, de `Money.percent`)
 * escrito em pt-BR (`"51,76%"`).
 *
 * Por que trocar só o separador em vez de reformatar: os dígitos são do domínio
 * — inclusive os arredondamentos que a DEC-01 manda preservar —, e converter
 * para número e formatar de novo introduziria uma segunda decisão de
 * arredondamento sobre um valor que já foi decidido. Aqui não há aritmética:
 * é ortografia.
 *
 * Por que existe: sem isto o painel mostrava `51.76%` de um lado e `109,0%` do
 * outro, na mesma tela — dois idiomas para a mesma grandeza. Visto renderizando.
 */
export function localizePercentLabel(label: string | null | undefined, fallback = '—'): string {
  if (!label) return fallback
  return label.replace('.', ',')
}

export interface ParseResult {
  /** `null` quando a entrada está vazia ou não é número. */
  value: number | null
  /** Motivo legível quando `value` é `null` e o texto não estava vazio. */
  aviso?: string
}

/**
 * Interpreta número digitado em pt-BR, e **avisa** em vez de adivinhar.
 *
 * O caso que dá prejuízo: `1.234.56`. Isso não é pt-BR válido (dois separadores
 * de milhar e um ponto decimal misturados) e é exatamente o que sai de um
 * copiar-e-colar de planilha em locale errado. O legado engolia e gravava
 * `1234.56` **ou** `123456`, dependendo do caminho. Aqui a função devolve
 * `value: null` com aviso, e o campo mostra o aviso ao usuário — o valor não é
 * enviado torto.
 */
export function parseNumberPtBr(input: string): ParseResult {
  const bruto = (input ?? '').trim()
  if (!bruto) return { value: null }

  // Descarta o que é enfeite de moeda/percentual, mas guarda o sinal.
  const negativo = /^-|\(.*\)$/.test(bruto)
  const limpo = bruto.replace(/[R$\s%()]/gi, '').replace(/^-/, '')
  if (!limpo) return { value: null }

  if (!/^[\d.,]+$/.test(limpo)) {
    return { value: null, aviso: 'Use apenas números, ponto de milhar e vírgula decimal.' }
  }

  const virgulas = (limpo.match(/,/g) || []).length
  const pontos = (limpo.match(/\./g) || []).length

  if (virgulas > 1) {
    return { value: null, aviso: 'Há mais de uma vírgula decimal. Verifique o valor.' }
  }

  let normalizado: string
  if (virgulas === 1) {
    // pt-BR canônico: ponto é milhar, vírgula é decimal.
    const [inteira, decimal] = limpo.split(',')
    if (/\./.test(decimal ?? '')) {
      return { value: null, aviso: 'Separador de milhar depois da vírgula. Verifique o valor.' }
    }
    normalizado = `${inteira.replace(/\./g, '')}.${decimal ?? ''}`
  } else if (pontos === 0) {
    normalizado = limpo
  } else if (pontos === 1) {
    // Ambíguo: `1.234` é mil duzentos e trinta e quatro; `1.5` é um e meio.
    // A convenção do milhar exige exatamente 3 dígitos depois do ponto.
    const [, dec = ''] = limpo.split('.')
    normalizado = dec.length === 3 ? limpo.replace('.', '') : limpo
  } else {
    // Mais de um ponto: só é válido se TODOS forem milhar (grupos de 3).
    if (!/^\d{1,3}(\.\d{3})+$/.test(limpo)) {
      return { value: null, aviso: 'Separador decimal duplicado. Use vírgula para os centavos.' }
    }
    normalizado = limpo.replace(/\./g, '')
  }

  const n = Number(normalizado)
  if (!Number.isFinite(n)) return { value: null, aviso: 'Valor numérico inválido.' }
  return { value: negativo ? -n : n }
}

/** Arredonda para `casas` sem o erro de ponto flutuante de `toFixed` encadeado. */
export function arredondar(value: number, casas = 2): number {
  const f = 10 ** casas
  return Math.round((value + Number.EPSILON) * f) / f
}
