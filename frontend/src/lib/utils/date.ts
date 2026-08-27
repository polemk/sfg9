import { format, isValid, parse, startOfDay, endOfDay, addYears, addHours, addMinutes, formatDistanceToNow } from 'date-fns'
import { ptBR } from 'date-fns/locale'

/**
 * Datas em pt-BR — módulo, **nunca** global no `window` (IMP-A73).
 *
 * Substitui `helpers.js` do legado (`brazilianDate`, `extendedDate`,
 * `getExtendedMonth`, `getExtendedWeekday`) e as sentinelas de faixa de data do
 * `config/initializers/date_overload.rb` (`DateTime.dinosaurs`, `.mars`,
 * `today_start`, `today_end`), que eram usadas em 4 controllers.
 *
 * O legado tinha **duas** implementações do mesmo helper de data, com regra
 * diferente (D-125). Aqui é uma só, no cliente.
 */

/** Formato de data que o usuário vê e digita no Safegold. */
export const FORMATO_DATA = 'dd/MM/yyyy'
export const FORMATO_DATA_HORA = 'dd/MM/yyyy HH:mm'

/** Aceita `Date`, ISO do servidor, ou `dd/mm/aaaa` digitado. */
export type DateLike = Date | string | number | null | undefined

/**
 * Converte para `Date` sem inventar valor.
 *
 * O `new Date('31/12/2025')` do legado (`brazilianDate`) devolvia `Invalid Date`
 * silenciosamente e a tela mostrava "NaN". Aqui, entrada inválida devolve
 * `null` — quem chama decide o que mostrar.
 */
export function toDate(value: DateLike): Date | null {
  if (value === null || value === undefined || value === '') return null
  if (value instanceof Date) return isValid(value) ? value : null
  if (typeof value === 'number') {
    const d = new Date(value)
    return isValid(d) ? d : null
  }
  const s = value.trim()
  if (!s) return null
  // pt-BR digitado primeiro: `01/02/2026` é 1º de fevereiro, não 2 de janeiro.
  if (/^\d{2}\/\d{2}\/\d{4}$/.test(s)) {
    const d = parse(s, FORMATO_DATA, new Date())
    return isValid(d) ? d : null
  }
  // Data **sem hora** vinda da API (`2026-09-14`) é dia de calendário, não
  // instante. `new Date('2026-09-14')` a interpreta como meia-noite **UTC**;
  // em UTC−3 isso vira 13/09 às 21h e a tela mostra o dia anterior. Um
  // vencimento exibido um dia antes do real não é detalhe cosmético neste app.
  // Por isso a data pura é montada no fuso local, componente a componente.
  const soData = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s)
  if (soData) {
    const d = new Date(Number(soData[1]), Number(soData[2]) - 1, Number(soData[3]))
    return isValid(d) ? d : null
  }
  const d = new Date(s)
  return isValid(d) ? d : null
}

/** `dd/mm/aaaa`. Devolve `fallback` quando a entrada não é data. */
export function formatDate(value: DateLike, fallback = '—'): string {
  const d = toDate(value)
  return d ? format(d, FORMATO_DATA, { locale: ptBR }) : fallback
}

/** `dd/mm/aaaa hh:mm`. */
export function formatDateTime(value: DateLike, fallback = '—'): string {
  const d = toDate(value)
  return d ? format(d, FORMATO_DATA_HORA, { locale: ptBR }) : fallback
}

/** `Segunda-feira, 3 de março de 2026` — o `extendedDate` do legado. */
export function formatDateLong(value: DateLike, fallback = '—'): string {
  const d = toDate(value)
  if (!d) return fallback
  const texto = format(d, "EEEE, d 'de' MMMM 'de' yyyy", { locale: ptBR })
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}

/** Nome do mês em pt-BR (`getExtendedMonth`). `abreviado` dá "Mar". */
export function nomeDoMes(value: DateLike, abreviado = false): string {
  const d = toDate(value)
  if (!d) return ''
  const texto = format(d, abreviado ? 'MMM' : 'MMMM', { locale: ptBR })
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}

/** Dia da semana por extenso em pt-BR (`getExtendedWeekday`). */
export function nomeDoDiaDaSemana(value: DateLike): string {
  const d = toDate(value)
  if (!d) return ''
  const texto = format(d, 'EEEE', { locale: ptBR })
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}

/** ISO `aaaa-mm-dd` — o que vai para a API, sempre. */
export function toIsoDate(value: DateLike): string | null {
  const d = toDate(value)
  return d ? format(d, 'yyyy-MM-dd') : null
}

/* ── Sentinelas de faixa de data (BE-538 / OPS-618) ──────────────────────── */

/** Meia-noite de hoje — o `DateTime.today_start` do legado. */
export function todayStart(base: Date = new Date()): Date {
  return startOfDay(base)
}

/**
 * Último instante de hoje: `midnight + 23h59min`, **como no legado**.
 *
 * Sim, isso exclui o que acontecer entre 23:59:00 e 23:59:59 — um registro
 * gravado às 23:59:30 fica de fora do filtro "até hoje". É uma falha real do
 * legado, e mesmo assim ela é **replicada de propósito**: corrigir muda quais
 * linhas aparecem num relatório de fechamento.
 *
 * ⚠ **Isto aqui era `endOfDay` até 27/08.** Divergia do backend, que replica o
 * legado em `Sfg::DateBounds.today_end` — duas portas da MESMA sentinela, com
 * respostas opostas, e nenhuma das duas com consumidor que denunciasse. A
 * justificativa citava "D-119", mas D-119 é outro defeito (chaves de config
 * mortas em `legacy-defects.md`), e o `improvements-log.md` nunca registrou a
 * mudança. O que ele registra é o contrário: **PLAT-07** diz "comportamento
 * idêntico, incluindo o `today_end` de 23h59 (não 23h59m59s)".
 */
export function todayEnd(base: Date = new Date()): Date {
  return addMinutes(addHours(startOfDay(base), 23), 59)
}

/** Limite inferior "infinito" (`DateTime.dinosaurs`): hoje − 2000 anos. */
export function dinosaurs(base: Date = new Date()): Date {
  return addYears(startOfDay(base), -2000)
}

/** Limite superior "infinito" (`DateTime.mars`): hoje + 2000 anos. */
export function mars(base: Date = new Date()): Date {
  return addYears(startOfDay(base), 2000)
}

/**
 * Faixa de data pronta para a consulta, com as sentinelas no lugar do nulo.
 *
 * Uma ponta vazia não significa "sem filtro": significa "sem limite daquele
 * lado". Deixar `undefined` fazia cada controller do legado decidir sozinho — e
 * eles decidiam diferente.
 */
export function dateRange(de: DateLike, ate: DateLike): { de: Date; ate: Date } {
  const inicio = toDate(de)
  const fim = toDate(ate)
  return {
    de: inicio ? startOfDay(inicio) : dinosaurs(),
    ate: fim ? endOfDay(fim) : mars(),
  }
}

/* ── S19 · transversais de data ──────────────────────────────────────────── */

/**
 * Tempo relativo em pt-BR — `FE-430`, o `time_ago` do legado.
 *
 * **Um** utilitário, e é este. O legado tinha **dois**: `application_helper.rb:2`
 * e `ux_kit19/.../application_helper.rb:8`, o segundo copiado do primeiro. Nesta
 * base a duplicação já tinha recomeçado — `formatDistanceToNow` inline em
 * `ExecutionViewerPage.tsx:39` e em `ExecutionDetailPage.tsx:89`, cada um com o
 * seu tratamento de data inválida.
 *
 * O legado fazia `time_ago_in_words(t).gsub(/aproximadamente|atrás/, '') << ' atrás'`,
 * ou seja, removia "aproximadamente" no passado e o **mantinha** no futuro — duas
 * formas de texto para a mesma coisa. Aqui é uma só, e o sufixo ("atrás" / "em")
 * vem do `date-fns` em pt-BR.
 */
export function timeAgo(value: DateLike, fallback = '—'): string {
  const d = toDate(value)
  if (!d) return fallback
  return formatDistanceToNow(d, { addSuffix: true, locale: ptBR })
}

/**
 * ISO-8601 completo, com fuso — o que vai para a API quando o INSTANTE importa
 * (`FE-440`). Para dia de calendário use `toIsoDate`, que não carrega hora.
 *
 * O contrato da fronteira é este: **cliente↔servidor só troca ISO-8601**. O
 * legado montava `"%m/%d/%Y"` em `days_js_array` para o datepicker — formato
 * ambíguo, e `03/04` num sistema de vencimentos é 3 de abril ou 4 de março
 * dependendo de quem lê.
 */
export function toIsoDateTime(value: DateLike): string | null {
  const d = toDate(value)
  return d ? d.toISOString() : null
}

/**
 * Os 12 meses localizados como opções de select — `FE-436` (`month_array`).
 *
 * O legado montava um Hash `{ "Janeiro" => 1, ... }` chamando `I18n.l` doze
 * vezes sobre `Date.today.beginning_of_year`. Aqui vem do catálogo do
 * `date-fns`, e o `value` é o mês **1..12**, como o legado — as duas telas que
 * usavam (`charges`, `indicator_entries`) mandam esse número ao servidor.
 */
export function monthOptions(): Array<{ value: number; label: string }> {
  return Array.from({ length: 12 }, (_, i) => {
    const texto = format(new Date(2000, i, 1), 'MMMM', { locale: ptBR })
    return { value: i + 1, label: texto.charAt(0).toUpperCase() + texto.slice(1) }
  })
}

/**
 * Janela de anos centrada no ano corrente — `FE-437` (`ten_years_array`).
 *
 * O legado devolvia `[ano-5 .. ano+5]`, que são **onze** anos apesar do nome.
 * O intervalo é preservado; o nome é que era errado.
 */
export function yearWindow(span = 5, base: Date = new Date()): number[] {
  const ano = base.getFullYear()
  return Array.from({ length: span * 2 + 1 }, (_, i) => ano - span + i)
}

/**
 * Dia da semana em pt-BR a partir do ÍNDICE 0..6 — `FE-442` (`week_days`).
 *
 * Para uma data use `nomeDoDiaDaSemana`, que já existe acima. Esta forma existe
 * porque o legado indexava `I18n.t(:date)[:day_names][nday % 7]` e concatenava
 * `"-feira"` à mão, errando em domingo e sábado por `unless nday == 0 || nday == 6`
 * — uma regra de gramática escrita como condicional. Aqui o nome completo vem
 * do catálogo, que já traz "segunda-feira" inteiro.
 */
export function nomeDoDiaDaSemanaPorIndice(indice: number): string {
  // 2000-01-02 é um sábado; somando o índice chega-se ao dia certo com
  // domingo = 0, que é a convenção do legado e a do JavaScript.
  const base = new Date(2000, 0, 2 + (((indice % 7) + 7) % 7))
  const texto = format(base, 'EEEE', { locale: ptBR })
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}
