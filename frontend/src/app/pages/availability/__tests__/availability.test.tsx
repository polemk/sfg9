import { describe, expect, it } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'
import { CONSOLE_NAV_GROUPS } from '@/app/consoleNavigation'
import { formatarValor } from '@/lib/api/availability'

/**
 * S11 — testes da fatia de disponibilidades (seção 7.4 da fila).
 *
 * Três deles são de **fonte**, e isso é deliberado: o que eles protegem não é o
 * que a tela renderiza num cenário, é a **ausência de um caminho**. "Nenhum
 * padrão de outro projeto viaja no payload" e "o critério de somente-leitura vem
 * do servidor" são afirmações sobre o código inteiro, e um teste de render prova
 * um caso; um teste de fonte prova o conjunto. É o mesmo desenho do
 * `no-api-polling.test.ts` da S0.
 */
const RAIZ = path.resolve(__dirname, '../../../..')
const PAGINAS = path.resolve(__dirname, '..')

function ler(arquivo: string): string {
  return fs.readFileSync(path.join(PAGINAS, arquivo), 'utf8')
}

const TELAS = ['AvailabilityPage.tsx', 'ProjectAvailabilitiesPage.tsx', 'AvailabilityTemplatesPage.tsx']

describe('S11 — payload sem padrão de outro projeto (FE-110, FE-139, FE-147, FE-148)', () => {
  it('nenhuma tela busca a lista GLOBAL de padrões para montar o campo "Faz parte de"', () => {
    // É o vazamento do `data-templates`: o legado serializava
    // `AvailabilityTemplate.all` — todos os padrões de TODOS os projetos — num
    // atributo do HTML, e o filtro de níveis rodava sobre esse JSON.
    const tela = ler('ProjectAvailabilitiesPage.tsx')

    expect(tela).toContain('projectAvailabilitiesApi.availableParents')
    // A tela do PROJETO nunca chama o catálogo global para achar um pai.
    expect(tela).not.toContain('availabilityTemplatesApi')
  })

  it('o cliente nunca envia `project_id` — o escopo é do servidor (C1)', () => {
    const camada = fs.readFileSync(path.join(RAIZ, 'lib/api/availability.ts'), 'utf8')
    const corpoDosMetodos = camada.split('// --- Padrões do projeto')[1] ?? ''

    expect(corpoDosMetodos).not.toMatch(/project_id:/)
    for (const tela of TELAS) {
      expect(ler(tela)).not.toMatch(/project_id:\s*/)
    }
  })
})

describe('S11 — o critério de somente-leitura vem do SERVIDOR (FE-132 / D-23)', () => {
  it('a grade decide pela resposta, não por uma regra própria de tela', () => {
    const tela = ler('AvailabilityPage.tsx')

    // O campo só aparece quando o SERVIDOR disse que a célula é editável.
    expect(tela).toContain('editable ? (')
    // E a tela não recalcula o critério por conta própria — se recalculasse,
    // os dois lados poderiam divergir, que é exatamente o D-23.
    expect(tela).not.toMatch(/const\s+editavel\s*=/)
  })
})

describe('S11 — o menu de contexto NUNCA renderiza vazio (FE-145, FE-108)', () => {
  it('as três ações são sempre construídas; a indisponível vira motivo, não sumiço', () => {
    const tela = ler('ProjectAvailabilitiesPage.tsx')
    const bloco = tela.slice(tela.indexOf('const acoesDoPadrao'), tela.indexOf('const cabecalho'))

    // No legado, "global + com filhos" produzia um menu com zero itens.
    expect(bloco).toContain("key: 'renomear'")
    expect(bloco).toContain("key: 'ativacao'")
    expect(bloco).toContain("key: 'remover'")
    // Nenhuma ação é removida condicionalmente da lista — o que muda é o motivo.
    expect(bloco).not.toMatch(/\.filter\(/)
    expect(bloco).toContain('disabledReason')
  })
})

describe('S11 — valor negativo mostra o SINAL, não só a cor (FE-125)', () => {
  it('o formatador devolve o sinal no próprio número', () => {
    // O legado exibia o MÓDULO (`total * -1` no JS) e sinalizava só por
    // vermelho: ambíguo, e invisível para quem não distingue as cores.
    expect(formatarValor('-1234.56')).toMatch(/-/)
    expect(formatarValor('-1234.56')).toContain('1.234,56')
    expect(formatarValor('1234.56')).not.toMatch(/-/)
  })

  it('a tela não desfaz o sinal antes de exibir', () => {
    const tela = ler('AvailabilityPage.tsx')
    expect(tela).not.toMatch(/\*\s*-1/)
    expect(tela).not.toMatch(/Math\.abs\(/)
  })
})

describe('S11 — valor digitado e valor corrigido aparecem AMBOS (FE-134)', () => {
  it('a célula corrigida mostra a base e o multiplicador, além do valor gravado', () => {
    const tela = ler('AvailabilityPage.tsx')

    expect(tela).toContain('entry.original_value')
    expect(tela).toContain('business_days_multiplier')
    // E diz, na explicação, o que acontece ao salvar de novo — o D-02 que a
    // DEC-24 mandou replicar.
    expect(tela).toContain('valor já corrigido')
  })
})

describe('S11 — o progresso vem do CANAL, nunca de temporizador (Princípio 10, OPS-127)', () => {
  it('as telas de disponibilidade consomem `useJobProgress` e nenhum timer de API', () => {
    for (const arquivo of ['AvailabilityPage.tsx', 'ProjectAvailabilitiesPage.tsx']) {
      const tela = ler(arquivo)
      expect(tela).toContain('useJobProgress')
      expect(tela).not.toContain('refetchInterval')
      expect(tela).not.toMatch(/setTimeout\([^)]*Api\./)
    }
  })
})

describe('S11 — os quatro itens de menu nascem HABILITADOS (DEC-15.1 / D-90)', () => {
  const itens = CONSOLE_NAV_GROUPS.flatMap((g) => g.items)
  const alvos = ['availability', 'charges', 'project_availabilities', 'availability_templates']

  it('os quatro existem no menu', () => {
    for (const id of alvos) {
      expect(itens.find((i) => i.id === id), `item ${id}`).toBeTruthy()
    }
  })

  it('NENHUM dos quatro nasce marcado como travado', () => {
    // O mecanismo `locked` continua existindo e passa a ser lido do ITEM (o
    // legado lia `g[:locked]`, do grupo — por isso os quatro nunca ficaram
    // travados na prática, D-90). O que se preserva é o EFEITO: produção é a
    // verdade, não a intenção aparente do código.
    for (const id of alvos) {
      const item = itens.find((i) => i.id === id)!
      expect((item as Record<string, unknown>).locked ?? false, `item ${id}`).toBe(false)
    }
  })

  it('as quatro telas estão montadas — "Cobranças" acendeu na S6 (DEC-63 / P-098)', () => {
    // **Este caso mudou de sentido na S6, e isso estava previsto.** Ele nasceu
    // travando "a tela de cobranças ainda NÃO existe": desta fatia saiu o item
    // de menu sem `locked`, e o comentário original dizia que ele acenderia no
    // commit em que a S6 entregasse a tela — porque menu que leva a 404 é pior
    // que menu curto (`apenasMontados`).
    //
    // A S6 entregou (`features/receivables/pages/ChargesPage.tsx`, DEC-63 deu
    // `charges`/`receipts` a ela). A asserção foi invertida **no mesmo passo**
    // da entrega, que é a Regra de fronteira: quem muda o contrato conserta os
    // dois lados junto.
    for (const id of alvos) {
      expect(itens.find((i) => i.id === id)!.element, `tela de ${id}`).not.toBeNull()
    }
  })
})
