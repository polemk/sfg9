/**
 * A moeda do app — um lugar só.
 *
 * O legado já tratava moeda como configuração, não como constante: o
 * `config/initializers/type_casting.rb` define `Currency::BRL` e `Currency::USD`
 * com `DEFAULT = BRL`, e cada campo monetário passava o dicionário da moeda.
 * Aqui o equivalente vive neste arquivo.
 *
 * Isto existe porque `currency: 'BRL'` estava **cravado em sete lugares** do
 * frontend. Sete cópias não são sete decisões: são uma decisão que ninguém
 * consegue mudar sem esquecer uma delas.
 *
 * `minorUnits` é quantas casas decimais a moeda tem — é o que faz o campo
 * monetário preencher da direita para a esquerda: com 2, digitar `1` é um
 * centavo. Moeda sem subunidade (JPY) usa 0, e aí digitar `1` é uma unidade.
 */
export interface CurrencyConfig {
  /** Código ISO 4217 — o que o `Intl.NumberFormat` entende. */
  code: string
  /** Locale de formatação. Decide o separador decimal e o de milhar. */
  locale: string
  /** Casas decimais da moeda. 2 para BRL/USD, 0 para JPY. */
  minorUnits: number
}

export const CURRENCIES = {
  BRL: { code: 'BRL', locale: 'pt-BR', minorUnits: 2 },
  USD: { code: 'USD', locale: 'en-US', minorUnits: 2 },
} as const satisfies Record<string, CurrencyConfig>

/**
 * A moeda corrente do app.
 *
 * Trocar aqui troca **toda** exibição e todo campo monetário de uma vez. O
 * padrão é BRL, como o `Currency::DEFAULT` do legado.
 */
export const APP_CURRENCY: CurrencyConfig =
  CURRENCIES[(import.meta.env?.VITE_APP_CURRENCY as keyof typeof CURRENCIES) ?? 'BRL'] ??
  CURRENCIES.BRL

/** `10 ** minorUnits` — o divisor entre unidade menor e maior. */
export function minorFactor(moeda: CurrencyConfig = APP_CURRENCY): number {
  return 10 ** moeda.minorUnits
}
