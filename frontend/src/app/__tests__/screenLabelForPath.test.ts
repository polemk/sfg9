import { describe, it, expect } from 'vitest'
import { screenLabelForPath, CONSOLE_NAV_ITEMS } from '@/app/consoleNavigation'

/**
 * A TELA EM QUE A PESSOA ESTÁ, para o assistente do console (DEC-13.2).
 *
 * Sem isto o agente recebia só o `pathname` e perguntava "em que tela você
 * está?" — pergunta que o sistema já sabe responder, feita a quem está dentro
 * da tela. O que este teste protege é o que faria a resposta ficar errada em
 * silêncio: nomear a tela errada é pior que não nomear nenhuma, porque o agente
 * então explica com confiança o lugar errado.
 */
describe('screenLabelForPath', () => {
  it('nomeia a tela pelo caminho exato', () => {
    expect(screenLabelForPath('/risk')).toBe('Controle de Risco')
    expect(screenLabelForPath('/renegotiations')).toBe('Renegociações')
  })

  it('nomeia a mesma tela dentro de uma rota de detalhe', () => {
    expect(screenLabelForPath('/renegotiations/42')).toBe('Renegociações')
    expect(screenLabelForPath('/companies/7/edit')).toBe('Empresas')
  })

  // O caso que o prefixo ingênuo erra: `/risk-controls` não é uma sub-rota de
  // `/risk`, e responder "Controle de Risco" mandaria o agente explicar a tela
  // errada — com o nome certo na frase, o que torna o erro difícil de perceber.
  it('não confunde telas cujo caminho começa igual', () => {
    expect(screenLabelForPath('/risk-controls')).toBe('Limites')
    expect(screenLabelForPath('/risk-operations')).toBe('Operações de Risco')
  })

  it('reconhece o painel, que não é item de grupo', () => {
    expect(screenLabelForPath('/')).toBe('Início (painel do projeto)')
    expect(screenLabelForPath('/dashboard')).toBe('Início (painel do projeto)')
  })

  it('ignora barra final e query', () => {
    expect(screenLabelForPath('/charges/')).toBe(screenLabelForPath('/charges'))
    expect(screenLabelForPath('/charges?page=2')).toBe(screenLabelForPath('/charges'))
  })

  // `null` é resposta: o agente fica sem nome de tela em vez de receber um
  // palpite. Rota que não é área do console (um 404, por exemplo) cai aqui.
  it('devolve null quando o caminho não é uma área do console', () => {
    expect(screenLabelForPath('/rota-que-nao-existe')).toBeNull()
  })

  it('resolve TODA área declarada — nenhuma fica sem nome', () => {
    CONSOLE_NAV_ITEMS.forEach((item) => {
      expect(screenLabelForPath(item.path)).toBe(item.label)
    })
  })
})
