import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { useRef } from 'react'
import {
  MobileActionsSheet,
  MobileRowActions,
  type MobileRowAction,
} from '../MobileRowActions'

/**
 * **Folha no telefone, menu ancorado no desktop** — o achado do usuário
 * (26/08/2026): *"o `more` de disponibilidade não faz sentido ser assim no
 * desktop; no mobile faz, no desktop tem que ser dropdown"*.
 *
 * A folha sobe do rodapé e ocupa metade da janela para oferecer **três** itens,
 * e o contexto de qual LINHA são essas ações sai de vista junto. No telefone é o
 * padrão certo — é a zona do polegar, e a linha some de qualquer jeito. Em
 * 1440 px é desperdício com perda de contexto.
 *
 * A correção mora no COMPONENTE (14 telas usam esta biblioteca), e o que estes
 * exemplos travam é justamente a diferença entre os dois tamanhos — que é a
 * única coisa que `tsc` e uma suíte de renderização única nunca veriam.
 */

const ACOES: MobileRowAction[] = [
  { key: 'renomear', label: 'Renomear', onSelect: vi.fn() },
  { key: 'ativacao', label: 'Desativar', onSelect: vi.fn() },
  {
    key: 'remover',
    label: 'Remover',
    destructive: true,
    disabledReason: 'Este padrão veio do catálogo global.',
    onSelect: vi.fn(),
  },
]

const larguraOriginal = window.innerWidth

function definirLargura(px: number) {
  Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: px })
}

beforeEach(() => {
  // `src/test/setup.ts` não chama `cleanup()` (UF-S15-04).
  cleanup()
})

afterEach(() => {
  definirLargura(larguraOriginal)
})

/** Uma tela em miniatura: o "…" da linha e a folha/menu no fim da página. */
function TelaComAncora({ open }: { open: boolean }) {
  const ancora = useRef<HTMLButtonElement | null>(null)
  return (
    <div>
      <button ref={ancora} type="button" aria-label="Ações de Caixa">
        …
      </button>
      <MobileActionsSheet
        open={open}
        onOpenChange={() => {}}
        anchorRef={ancora}
        title="1.1 — Caixa"
        actions={ACOES}
      />
    </div>
  )
}

describe('ações da linha — a apresentação muda com o tamanho da tela', () => {
  it('no DESKTOP é um menu ancorado, não a folha de meia tela', () => {
    definirLargura(1440)
    render(<TelaComAncora open />)

    const menu = screen.getByRole('menu', { name: /ações de 1\.1 — caixa/i })
    expect(menu).toBeInTheDocument()
    // A folha é `role="dialog"` e ocupa a janela inteira: no desktop ela não existe.
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(screen.getAllByRole('menuitem')).toHaveLength(3)
    // Ancorado = `fixed`, em portal no `body` (o `FloatingPanel` da biblioteca).
    expect(menu.style.position).toBe('fixed')
    expect(menu.parentElement).toBe(document.body)
  })

  it('no TELEFONE continua sendo a folha do rodapé, com a âncora ignorada', () => {
    definirLargura(390)
    render(<TelaComAncora open />)

    expect(screen.getByRole('dialog', { name: /ações de 1\.1 — caixa/i })).toBeInTheDocument()
    expect(screen.queryByRole('menu')).toBeNull()
  })

  it('no desktop SEM âncora nada muda: a folha continua sendo a resposta', () => {
    // O que mantém a mudança aditiva. As telas que ainda não passam a `ref`
    // renderizam exatamente o que renderizavam ontem.
    definirLargura(1440)
    render(
      <MobileActionsSheet open onOpenChange={() => {}} title="1.1 — Caixa" actions={ACOES} />,
    )
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(screen.queryByRole('menu')).toBeNull()
  })

  it('a ação bloqueada continua aparecendo, com o motivo escrito', () => {
    // D-24 — sumir com a ação é o que fazia o usuário do legado clicar em
    // "Remover" e ler "removido com sucesso" sem nada ter sido removido.
    definirLargura(1440)
    render(<TelaComAncora open />)

    const remover = screen.getByRole('menuitem', { name: /remover/i })
    expect(remover).toBeDisabled()
    expect(screen.getByText('Este padrão veio do catálogo global.')).toBeInTheDocument()
  })

  it('o menu abre com o foco no primeiro item utilizável', () => {
    definirLargura(1440)
    render(<TelaComAncora open />)
    expect(document.activeElement).toBe(screen.getByRole('menuitem', { name: /renomear/i }))
  })

  it('escolher um item fecha o menu e dispara a ação da tela', () => {
    definirLargura(1440)
    const acionar = vi.fn()
    const fechar = vi.fn()
    function Tela() {
      const ancora = useRef<HTMLButtonElement | null>(null)
      return (
        <div>
          <button ref={ancora} type="button">
            …
          </button>
          <MobileActionsSheet
            open
            onOpenChange={fechar}
            anchorRef={ancora}
            title="1.1 — Caixa"
            actions={[{ key: 'renomear', label: 'Renomear', onSelect: acionar }]}
          />
        </div>
      )
    }
    render(<Tela />)

    fireEvent.click(screen.getByRole('menuitem', { name: /renomear/i }))
    expect(acionar).toHaveBeenCalledTimes(1)
    expect(fechar).toHaveBeenCalledWith(false)
  })

  it('`MobileRowActions` — o mesmo corte, ancorado no PRÓPRIO gatilho', () => {
    definirLargura(1440)
    render(
      <MobileRowActions open onOpenChange={() => {}} title="Caixa" actions={ACOES} />,
    )
    expect(screen.getByRole('menu')).toBeInTheDocument()
    expect(screen.queryByRole('dialog')).toBeNull()
    // O gatilho anuncia o que abre — `menu`, não `dialog`.
    expect(screen.getByRole('button', { name: /ações de caixa/i })).toHaveAttribute(
      'aria-haspopup',
      'menu',
    )
  })

  it('`MobileRowActions` no telefone: gatilho de diálogo e folha', () => {
    definirLargura(390)
    render(<MobileRowActions open onOpenChange={() => {}} title="Caixa" actions={ACOES} />)
    expect(screen.getByRole('dialog')).toBeInTheDocument()
    expect(screen.queryByRole('menu')).toBeNull()
    expect(screen.getAllByRole('button', { name: /ações de caixa/i })[0]).toHaveAttribute(
      'aria-haspopup',
      'dialog',
    )
  })
})
