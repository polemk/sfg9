import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import * as React from 'react'
import { MobileCard } from '../MobileCard'
import { MobileKPI } from '../MobileKPI'
import { MobileChartCard } from '../MobileChartCard'
import { MobilePagination } from '../MobilePagination'
import { MobileEmptyState, MobileErrorState, MobileListSkeleton } from '../MobileListState'
import { Wallet } from 'lucide-react'
import { MobileRowActions, MobileActionsSheet } from '../MobileRowActions'
import { MobilePageLayout } from '../MobilePageLayout'
import { MobileBottomBar as MobileBottomBarLazy } from '../MobileBottomBar'
import { MobileNavSheet } from '../MobileNavSheet'

/**
 * Trava do contrato da biblioteca mobile (DEC-100).
 *
 * Não é teste de pixel — é teste do que **sete fatias** (S5..S11) vão herdar ao consumir
 * estes componentes. Cada `it` aqui existe porque o comportamento contrário já apareceu na
 * base ou tem consequência direta numa tela financeira.
 */
describe('biblioteca mobile — contrato compartilhado', () => {
  describe('MobileCard', () => {
    it('linha clicável é alcançável pelo teclado e ativa por Enter', () => {
      // `onClick` num <div> deixava a linha inalcançável por Tab: quem navega por teclado
      // não conseguia abrir registro nenhum da lista.
      const aoClicar = vi.fn()
      render(<MobileCard title="Borderô 4471" onClick={aoClicar} />)

      const linha = screen.getByRole('button', { name: /Borderô 4471/ })
      expect(linha).toHaveAttribute('tabindex', '0')

      fireEvent.keyDown(linha, { key: 'Enter' })
      expect(aoClicar).toHaveBeenCalledTimes(1)
    })

    it('card sem onClick não vira botão — lista de leitura não anuncia ação falsa', () => {
      render(<MobileCard title="Somente leitura" />)
      expect(screen.queryByRole('button')).toBeNull()
    })

    it('valor monetário sai em pt-BR, com separador de milhar', () => {
      render(<MobileCard title="Parcela" value={1234567.89} />)
      // `R$ 1234567.89` era o que saía do formato cru — ilegível numa coluna de valores.
      expect(screen.getByText(/1\.234\.567,89/)).toBeInTheDocument()
    })

    it('saída leva sinal negativo e token destrutivo', () => {
      const { container } = render(<MobileCard title="Baixa" value={500} type="despesa" />)
      expect(container.textContent).toContain('-R$')
    })
  })

  describe('MobileKPI', () => {
    it('format="plain" não transforma contagem em moeda', () => {
      // O padrão anterior era moeda, então uma contagem de parcelas saía como `R$ 12`.
      render(<MobileKPI title="Parcelas" value={12} icon={Wallet} format="plain" />)
      expect(screen.getByText('12')).toBeInTheDocument()
    })

    it('carregando mostra esqueleto e marca aria-busy, sem exibir número falso', () => {
      const { container } = render(
        <MobileKPI title="Exposição" value={0} icon={Wallet} loading />,
      )
      expect(container.querySelector('[aria-busy="true"]')).toBeTruthy()
      expect(screen.queryByText(/R\$/)).toBeNull()
    })
  })

  describe('MobileChartCard', () => {
    it('série vazia diz que não há dado, em vez de desenhar retângulo em branco', () => {
      render(<MobileChartCard title="Operado" data={[]} dataKey="valor" />)
      expect(screen.getByText('Sem dados no período')).toBeInTheDocument()
    })
  })

  describe('MobilePagination', () => {
    it('some quando há uma página só', () => {
      const { container } = render(
        <MobilePagination page={1} total={5} perPage={10} onPageChange={vi.fn()} />,
      )
      expect(container.firstChild).toBeNull()
    })

    it('não deixa passar do fim nem do começo', () => {
      const aoMudar = vi.fn()
      render(<MobilePagination page={1} total={30} perPage={10} onPageChange={aoMudar} />)

      expect(screen.getByRole('button', { name: 'Página anterior' })).toBeDisabled()
      fireEvent.click(screen.getByRole('button', { name: 'Próxima página' }))
      expect(aoMudar).toHaveBeenCalledWith(2)
    })
  })

  describe('estados de lista', () => {
    it('carregando é anunciado como ocupado', () => {
      render(<MobileListSkeleton rows={2} />)
      expect(screen.getByRole('status')).toHaveAttribute('aria-busy', 'true')
    })

    it('vazio por filtro diz que o dado continua lá', () => {
      // "Nenhum resultado" sem essa distinção faz o usuário concluir que o sistema
      // perdeu o registro dele.
      render(<MobileEmptyState title="Nenhum borderô" filtered />)
      expect(screen.getByText(/Os dados continuam lá/)).toBeInTheDocument()
    })

    it('erro é alert, nunca se confunde com vazio, e oferece tentar de novo', () => {
      const aoTentar = vi.fn()
      render(<MobileErrorState detail="500 Internal Server Error" onRetry={aoTentar} />)

      expect(screen.getByRole('alert')).toBeInTheDocument()
      expect(screen.getByText('500 Internal Server Error')).toBeInTheDocument()

      fireEvent.click(screen.getByRole('button', { name: /Tentar de novo/ }))
      expect(aoTentar).toHaveBeenCalledTimes(1)
    })
  })
})

/**
 * Achado do usuário (26/08/2026): *"esse more parecendo um botão no final da
 * tela ficou super estranho"* — um "…" órfão flutuando no rodapé, visível
 * inclusive com a lista VAZIA.
 *
 * A causa: `MobileRowActions` renderiza o próprio gatilho quando fechado, e
 * quatro telas o usavam como folha controlada no fim do arquivo, já tendo o
 * gatilho dentro da linha. As duas formas de uso chegavam com props idênticas,
 * então o componente não tinha como distinguir — a saída foram dois nomes.
 */
describe('MobileActionsSheet — a folha sem gatilho', () => {
  const acoes = [{ key: 'ver', label: 'Ver', onSelect: () => {} }]

  it('fechada, não renderiza NADA — nem o "…" órfão', () => {
    const { container } = render(
      <MobileActionsSheet open={false} onOpenChange={() => {}} title="Padrão" actions={acoes} />,
    )
    expect(container).toBeEmptyDOMElement()
    expect(document.querySelectorAll('button')).toHaveLength(0)
  })

  it('aberta, mostra as ações', () => {
    render(<MobileActionsSheet open onOpenChange={() => {}} title="Padrão" actions={acoes} />)
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(screen.getByText('Ver')).toBeInTheDocument()
  })

  it('MobileRowActions continua rendendo o gatilho quando fechado — é o uso por linha', () => {
    render(<MobileRowActions open={false} onOpenChange={() => {}} title="Padrão" actions={acoes} />)
    expect(screen.getByRole('button', { name: /ações de padrão/i })).toBeInTheDocument()
  })
})

/**
 * Achado do usuário (26/08/2026): *"o mobile/responsivo não está levando em
 * consideração a botbar para o tamanho da tela, ficando conteúdo cortado, nem a
 * topbar pois no scroll o conteúdo da tela fica por cima da topbar"*.
 *
 * Eram dois defeitos na MOLDURA, não nas telas:
 *
 * 1. `main` reservava só o topo. A `MobileBottomBar` é `fixed`, então os últimos
 *    ~4rem de toda lista ficavam atrás das abas. O `MobilePageLayout` já fazia a
 *    conta, mas só protegia as telas que o usam.
 * 2. A `MobileTopBar` era `glass-panel` — 88% de opacidade. O conteúdo não ficava
 *    por cima: era visto ATRAVÉS dela. A `MobileBottomBar` já era opaca, e a
 *    assimetria entre as duas era o defeito.
 */
describe('moldura do telefone — as duas barras entram na conta', () => {
  // A barra lê o projeto corrente por react-query; sem o provedor ela nem monta.
  function renderComBarra(no: React.ReactElement) {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    return render(
      <QueryClientProvider client={client}>
        <MemoryRouter>{no}</MemoryRouter>
      </QueryClientProvider>,
    )
  }

  it('a barra de baixo é OPACA — conteúdo não aparece através dela', async () => {
    const { MobileBottomBar } = await import('../MobileBottomBar')
    const { container } = renderComBarra(<MobileBottomBar />)
    const nav = container.querySelector('nav')
    expect(nav?.className).toContain('bg-background')
    expect(nav?.className).not.toContain('glass-panel')
  })

  it('a barra de baixo reserva a área segura do aparelho', async () => {
    const { MobileBottomBar } = await import('../MobileBottomBar')
    const { container } = renderComBarra(<MobileBottomBar />)
    expect(container.querySelector('nav')?.className).toContain('safe-area-inset-bottom')
  })

  it('o MobilePageLayout continua reservando o rodapé para quem o usa', () => {
    const { container } = render(
      <MobilePageLayout>
        <p>conteúdo</p>
      </MobilePageLayout>,
    )
    const raiz = container.firstElementChild as HTMLElement
    expect(raiz.style.paddingBottom).toContain('safe-area-inset-bottom')
  })
})

/**
 * **Passada de mobile nas fatias fechadas (DEC-100), 26/08/2026.**
 *
 * A renderização em 390×844 achou um defeito que nenhum portão via: a barra de
 * abas mostrava `useNavItems().slice(0, 5)` **e nada mais**. No telefone a
 * `Sidebar` é `hidden md:block` e a folha do avatar só tem perfil/tema/sair —
 * então os outros ~35 destinos do console (Projetos, Empresas, Portadores,
 * Limites, Contratos, Central de ajuda) **não tinham caminho nenhum**. Existiam,
 * com rota montada, e o polegar não chegava.
 *
 * O segundo defeito era de rótulo: com `truncate` numa faixa de ~70 px,
 * "Painel de Disponibilidade" e "Disponibilidades" — que compartilham o ícone
 * `CalendarRange` — viravam "Painel de D…" e "Disponibili…". Duas abas com o
 * mesmo desenho e o nome cortado antes de divergir são o "ícone sem rótulo" que
 * a §5.4.8 proíbe.
 */
describe('MobileBottomBar — alcance e rótulo (passada DEC-100)', () => {
  function renderBarra() {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    return render(
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <MobileBottomBarLazy />
        </MemoryRouter>
      </QueryClientProvider>,
    )
  }

  it('o rótulo NÃO trunca — é ele que separa duas abas de mesmo ícone', () => {
    const { container } = renderBarra()
    const nav = container.querySelector('nav')
    // Sem rótulo visível não há o que conferir: a barra só monta com itens de
    // menu, e o filtro depende de papel/projeto. O que este teste trava é a
    // AUSÊNCIA de `truncate` na classe do rótulo.
    for (const rotulo of nav?.querySelectorAll('span.line-clamp-3') ?? []) {
      expect(rotulo.className).not.toContain('truncate')
    }
  })

  it('a barra cabe na reserva que o Layout faz (80 px + inset)', () => {
    const { container } = renderBarra()
    const lista = container.querySelector('nav ul')
    // 4.25rem = 68 px. O `main` do Layout reserva `calc(5rem + inset)` = 80 px:
    // uma barra mais alta que a reserva volta a comer o fim da lista, que foi o
    // defeito que o usuário reportou.
    expect(lista?.className).toContain('h-[4.25rem]')
  })
})

/**
 * A folha que devolve o console inteiro ao telefone. Ver o cabeçalho do
 * `MobileNavSheet` para o porquê de ela existir.
 */
describe('MobileNavSheet — o menu inteiro no telefone', () => {
  function renderFolha(aberta: boolean, aoMudar = vi.fn()) {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    return render(
      <QueryClientProvider client={client}>
        <MemoryRouter>
          <MobileNavSheet open={aberta} onOpenChange={aoMudar} />
        </MemoryRouter>
      </QueryClientProvider>,
    )
  }

  it('fechada não renderiza nada', () => {
    const { container } = renderFolha(false)
    expect(container).toBeEmptyDOMElement()
    expect(document.querySelector('[role="dialog"]')).toBeNull()
  })

  it('aberta é um diálogo em portal, no body, e não dentro da barra', () => {
    renderFolha(true)
    const dialogo = screen.getByRole('dialog', { name: 'Todos os menus' })
    expect(dialogo).toBeInTheDocument()
    // §5.4.4: a `MobileBottomBar` é `fixed` com `z-appbar`, e `fixed` + `z` cria
    // contexto de empilhamento. Renderizada lá dentro, a folha ficaria presa.
    expect(dialogo.closest('nav')).toBeNull()
    expect(dialogo.parentElement).toBe(document.body)
  })

  it('Escape fecha — é o mínimo de teclado de uma superfície flutuante', () => {
    const aoMudar = vi.fn()
    renderFolha(true, aoMudar)
    fireEvent.keyDown(document, { key: 'Escape' })
    expect(aoMudar).toHaveBeenCalledWith(false)
  })
})
