import { formatMoney } from '@/lib/utils/number'

/**
 * S10 — o período da grade mensal, em um lugar só.
 *
 * ## Não há fuso horário aqui, e isso foi MEDIDO
 *
 * O ETL da S14 mediu que o legado grava em UTC-2 até 2019 e UTC-3 de 2020 em
 * diante, e uma série mensal que agrega **por data** erra o mês de virada se
 * ignorar isso. **Este módulo não agrega por data.** O bucket do mês vem de
 * `year`/`month` **inteiros**, que o usuário digitou numa célula que já sabe o
 * seu mês — é assim no legado
 * (`indicator_entries/list/_widget.html.erb:21-22`, campos escondidos) e é assim
 * aqui. Não existe virada de mês a errar, e nenhuma conversão de fuso é feita
 * sobre o período.
 *
 * O único ponto em que `Date` aparece é para **rotular** o mês em pt-BR, e o
 * rótulo é construído com dia 1 no fuso local — nunca lido de volta como dado.
 */

/** Rótulos de mês em pt-BR, gerados por `Intl` (DEC-10), não escritos à mão. */
const FORMATADOR_LONGO = new Intl.DateTimeFormat('pt-BR', { month: 'long' })
const FORMATADOR_CURTO = new Intl.DateTimeFormat('pt-BR', { month: 'short' })

function capitalizar(texto: string): string {
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}

/** `[1..12]`. */
export const MESES = Array.from({ length: 12 }, (_, i) => i + 1)

/** "Janeiro", "Fevereiro"… É o `I18n.l(date, format: "%B").camelize` do legado. */
export function nomeDoMes(mes: number): string {
  return capitalizar(FORMATADOR_LONGO.format(new Date(2000, mes - 1, 1)))
}

/** "Jan", "Fev"… para a versão estreita. */
export function nomeCurtoDoMes(mes: number): string {
  return capitalizar(FORMATADOR_CURTO.format(new Date(2000, mes - 1, 1)).replace('.', ''))
}

export const ANO_ATUAL = new Date().getFullYear()

/**
 * Ano atual −5 a +5 — a mesma janela do `ten_years_array` do legado
 * (`application_helper.rb:65-69`), que apesar do nome devolve **onze** anos.
 * Replicado.
 */
export function anosDisponiveis(referencia = ANO_ATUAL): number[] {
  return Array.from({ length: 11 }, (_, i) => referencia - 5 + i)
}

/**
 * Formatação do valor da célula. **`null` é "não lançado"** e não vira zero
 * (DEC-70) — quem chama decide o que mostrar no lugar.
 *
 * Delega ao `formatMoney` da biblioteca em vez de instanciar um `Intl` próprio:
 * o app tem UM jeito de escrever dinheiro, e um segundo formatador é como
 * `R$ 1.234,50` e `R$ 1234,50` acabam na mesma tela.
 */
export function formatarValor(valor: string | null | undefined): string | null {
  const n = paraNumero(valor)
  if (n === null) return null
  return formatMoney(n)
}

/** Número puro (sem "R$") a partir do decimal-string da API. */
export function paraNumero(valor: string | null | undefined): number | null {
  if (valor === null || valor === undefined || valor === '') return null
  const n = Number(valor)
  return Number.isFinite(n) ? n : null
}

/**
 * Do número da tela para a string que a API recebe. **String, sempre**: a coluna
 * é `decimal(15,2)` e passar por float no JSON transforma `1234.56` em
 * `1234.5599999999999`.
 */
export function paraDecimalString(valor: number): string {
  return valor.toFixed(2)
}
