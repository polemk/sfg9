import { describe, it, expect } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'

/**
 * **O respiro da `MobileTopBar` precisa ficar ACIMA das faixas.**
 *
 * A `MobileTopBar` é `fixed`, e quem reserva o espaço dela é a moldura. O
 * espaço estava reservado no `<main>` — mas as faixas de **impersonação** e de
 * **aceite de contrato** são irmãs do `main`, montadas acima dele. No telefone
 * elas nasciam ATRÁS da barra: medido em 390×844, no topo da página, a
 * primeira linha do aviso ("Você ainda não aceitou os documentos vigentes.")
 * ficava escondida e a faixa começava no meio da frase — em **todas** as telas,
 * para os seis usuários do elenco.
 *
 * ## Por que um teste de FONTE e não de render
 *
 * O que quebrou não é comportamento: é **ordem de aninhamento**. Montar o
 * `Layout` inteiro exigiria dobrar meia dúzia de stores, o roteador e o widget
 * de chat para conferir uma classe de padding — e ainda assim o `jsdom` não
 * calcula `env(safe-area-inset-top)`. O invariante que interessa é legível no
 * arquivo, e é ele que este exemplo trava. Mesmo desenho de
 * `marca-fonte-unica.test.ts`.
 */
const LAYOUT = fs.readFileSync(
  path.resolve(__dirname, '../Layout.tsx'),
  'utf8',
)

const RESPIRO = 'pt-[calc(4rem+env(safe-area-inset-top))]'

describe('Layout — o respiro do topo no telefone', () => {
  it('reserva o topo UMA vez só', () => {
    const ocorrencias = LAYOUT.split(RESPIRO).length - 1

    expect(ocorrencias).toBe(1)
  })

  it('reserva o topo ANTES das faixas, não dentro do `main`', () => {
    const respiro = LAYOUT.indexOf(RESPIRO)
    const faixa = LAYOUT.indexOf('<ImpersonationBanner')
    const principal = LAYOUT.indexOf('<main')

    expect(respiro).toBeGreaterThan(-1)
    expect(respiro).toBeLessThan(faixa)
    expect(respiro).toBeLessThan(principal)
  })

  it('o respiro vale só no telefone — no desktop a barra fixa não existe', () => {
    expect(LAYOUT).toContain(`${RESPIRO} md:pt-0`)
  })

  // O rodapé continua no `main`: a `MobileBottomBar` cobre o fim do conteúdo
  // rolável, e é lá que o espaço precisa existir.
  it('o respiro do rodapé continua no `main`', () => {
    const principal = LAYOUT.slice(LAYOUT.indexOf('<main'), LAYOUT.indexOf('>', LAYOUT.indexOf('<main')))

    expect(principal).toContain('pb-[calc(5rem+env(safe-area-inset-bottom))]')
  })
})
