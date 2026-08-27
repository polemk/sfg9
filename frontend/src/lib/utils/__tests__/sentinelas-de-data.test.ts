import { describe, it, expect, beforeEach, afterEach, vi } from "vitest"
import { todayStart, todayEnd, dinosaurs, mars, dateRange } from "@/lib/utils/date"

/**
 * **BE-538 — as quatro sentinelas de `date_overload.rb`.**
 *
 * O legado reabria `DateTime` para acrescentar `dinosaurs`, `mars`,
 * `today_start` e `today_end`. Elas decidem o que entra num filtro de período
 * quando o usuário não informa data — ou seja, decidem quais linhas aparecem
 * num relatório. Estavam portadas e **sem um único exemplo** dos dois lados.
 *
 * O custo de não ter teste aqui já apareceu: `todayEnd` tinha divergido para
 * `endOfDay` e ninguém percebeu, porque nenhum consumidor e nenhum exemplo
 * olhavam para ela. O backend replicava 23h59, o frontend devolvia 23:59:59.999,
 * e as duas conviviam. Ver o cabeçalho de `todayEnd` em `date.ts`.
 *
 * A data é congelada: sentinela que se calcula "agora" quebra sozinha à
 * meia-noite, e um teste que passa de dia e falha de madrugada é pior que
 * nenhum.
 */
describe("sentinelas de faixa de data (BE-538)", () => {
  // 15:42:30 de um dia qualquer — hora cheia de propósito, para que
  // "meia-noite" seja um resultado e não uma coincidência.
  const AGORA = new Date(2026, 7, 27, 15, 42, 30, 123)

  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(AGORA)
  })
  afterEach(() => vi.useRealTimers())

  it("todayStart é a meia-noite de hoje", () => {
    expect(todayStart()).toEqual(new Date(2026, 7, 27, 0, 0, 0, 0))
  })

  // **Este exemplo trava uma falha do legado, de propósito.**
  //
  // `midnight + 23h59min` deixa de fora tudo entre 23:59:00 e 23:59:59. É
  // errado, e é replicado: corrigir muda quais linhas entram num fechamento.
  // Decisão assinada em PLAT-07 do `improvements-log.md`.
  it("todayEnd é 23:59:00 — e NÃO o fim real do dia", () => {
    expect(todayEnd()).toEqual(new Date(2026, 7, 27, 23, 59, 0, 0))
    expect(todayEnd().getSeconds()).toBe(0)
  })

  it("bate com o backend, que replica a mesma regra em Sfg::DateBounds", () => {
    // `Time.zone.now.midnight + 23.hours + 59.minutes`
    const comoNoBackend = new Date(2026, 7, 27, 0, 0, 0, 0)
    comoNoBackend.setHours(comoNoBackend.getHours() + 23)
    comoNoBackend.setMinutes(comoNoBackend.getMinutes() + 59)
    expect(todayEnd()).toEqual(comoNoBackend)
  })

  it("dinosaurs e mars são meia-noite ± 2000 anos", () => {
    // `new Date(26, ...)` NAO da o ano 26: o construtor mapeia dois digitos
    // para 1926. O ano tem de ser posto depois, com `setFullYear`.
    const menos2000 = new Date(2026, 7, 27, 0, 0, 0, 0)
    menos2000.setFullYear(26)

    expect(dinosaurs()).toEqual(menos2000)
    expect(mars()).toEqual(new Date(4026, 7, 27, 0, 0, 0, 0))
  })

  describe("dateRange", () => {
    it("ponta vazia vira sentinela, não undefined", () => {
      const faixa = dateRange(null, null)
      expect(faixa.de).toEqual(dinosaurs())
      expect(faixa.ate).toEqual(mars())
    })

    it("ponta informada é normalizada para o dia inteiro", () => {
      const faixa = dateRange("2026-03-10", "2026-03-12")
      expect(faixa.de).toEqual(new Date(2026, 2, 10, 0, 0, 0, 0))
      // Aqui é `endOfDay` mesmo: o limite que o USUÁRIO escolheu inclui o dia
      // todo. A regra de 23h59 é da sentinela "hoje", não de uma data digitada.
      expect(faixa.ate.getHours()).toBe(23)
      expect(faixa.ate.getMinutes()).toBe(59)
      expect(faixa.ate.getSeconds()).toBe(59)
    })
  })
})
