import { describe, it, expect } from 'vitest'
import { render } from '@testing-library/react'
import { UserAvatar, avatarTone } from '@/components/ui/UserAvatar'

/**
 * FE-427 — o legado sorteava a cor a cada render e a inicial "piscava" ao
 * rolar a lista. O teste que fecha isso é o da **estabilidade**, não o da
 * existência da cor.
 */
describe('UserAvatar — cor determinística', () => {
  it('o mesmo id devolve sempre o mesmo tom', () => {
    const a = avatarTone('u-42')
    for (let i = 0; i < 50; i++) expect(avatarTone('u-42')).toBe(a)
  })

  it('ids diferentes se espalham pela paleta', () => {
    const tons = new Set(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'].map(avatarTone))
    expect(tons.size).toBeGreaterThan(1)
  })

  it('a classe do avatar não muda entre renders para o mesmo id', () => {
    const { container, rerender } = render(<UserAvatar name="Ana" colorKey="u-42" />)
    const antes = container.firstElementChild!.className
    rerender(<UserAvatar name="Ana" colorKey="u-42" />)
    expect(container.firstElementChild!.className).toBe(antes)
  })

  it('sem `colorKey` fica no tom neutro — o comportamento anterior não muda', () => {
    const { container } = render(<UserAvatar name="Ana" />)
    expect(container.firstElementChild!.className).toContain('bg-muted')
  })

  it('cai nas iniciais quando não há imagem', () => {
    const { getByText } = render(<UserAvatar name="Ana Beatriz Correia" colorKey="u1" />)
    expect(getByText('AC')).toBeInTheDocument()
  })
})
