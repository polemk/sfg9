import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { AuditTrailTimeline } from '../AuditTrailTimeline'
import { auditAppearance, AUDIT_EVENTS } from '../auditAppearance'
import type { AuditVersion } from '@/lib/api/auditTrail'

function versao(over: Partial<AuditVersion> = {}): AuditVersion {
  return {
    id: 1,
    item_type: 'UserPermission',
    item_id: '7',
    entity_label: 'permissão do usuário',
    event: 'create',
    summary: 'A permissão do usuário foi criada',
    author: { id: '10', name: 'Ana Gestora', email: 'ana@exemplo.com' },
    impersonated: null,
    reason: null,
    ip_address: '10.0.0.1',
    occurred_at: '2026-03-10T12:00:00.000Z',
    changes: { granted: [false, true] },
    ...over,
  }
}

describe('AuditTrailTimeline (FE-445)', () => {
  it('mostra a frase que veio do servidor, não uma montada aqui', () => {
    render(<AuditTrailTimeline versions={[versao()]} />)
    expect(screen.getByText('A permissão do usuário foi criada')).toBeInTheDocument()
  })

  it('mostra o autor REAL do ato', () => {
    render(<AuditTrailTimeline versions={[versao()]} />)
    expect(screen.getByText('Ana Gestora')).toBeInTheDocument()
  })

  // DEC-59 #3 — é o ponto de ter trilha.
  it('na impersonação diz as DUAS pessoas: quem agiu e quem foi personificado', () => {
    render(
      <AuditTrailTimeline
        versions={[
          versao({
            impersonated: { id: '20', name: 'Beltrano Cliente', email: null },
            event: 'impersonate_start',
            summary: 'A conta de usuário passou a ser personificada',
          }),
        ]}
      />,
    )
    expect(screen.getByText('Ana Gestora')).toBeInTheDocument()
    expect(screen.getByText(/personificando Beltrano Cliente/)).toBeInTheDocument()
  })

  it('autor ausente vira "sistema" — não some nem inventa nome', () => {
    render(<AuditTrailTimeline versions={[versao({ author: null })]} />)
    expect(screen.getByText('sistema')).toBeInTheDocument()
  })

  it('o instante absoluto fica no `datetime`, em ISO — o relativo é o que se lê', () => {
    render(<AuditTrailTimeline versions={[versao()]} />)
    const tempo = document.querySelector('time')
    expect(tempo?.getAttribute('datetime')).toBe('2026-03-10T12:00:00.000Z')
    expect(tempo?.textContent).not.toMatch(/\d{2}\/\d{2}\/\d{4}/)
  })

  it('mostra o motivo declarado quando existe', () => {
    render(<AuditTrailTimeline versions={[versao({ reason: 'pedido do cliente' })]} />)
    expect(screen.getByText(/pedido do cliente/)).toBeInTheDocument()
  })

  it('chama `onSelect` ao pedir o detalhe', () => {
    const aoSelecionar = vi.fn()
    render(<AuditTrailTimeline versions={[versao()]} onSelect={aoSelecionar} />)
    fireEvent.click(screen.getByRole('button', { name: 'Ver detalhes' }))
    expect(aoSelecionar).toHaveBeenCalledWith(expect.objectContaining({ id: 1 }))
  })

  describe('os quatro estados', () => {
    it('carregando', () => {
      render(<AuditTrailTimeline versions={[]} loading />)
      expect(screen.getByText('Carregando a trilha…')).toBeInTheDocument()
    })

    it('vazio diz que nada aconteceu', () => {
      render(<AuditTrailTimeline versions={[]} />)
      expect(screen.getByText('Nada registrado ainda')).toBeInTheDocument()
    })

    // O estado que o legado não tinha (FE-401). Numa trilha de auditoria,
    // "falhou ao carregar" e "nada aconteceu" não podem se parecer.
    it('erro é distinguível de vazio, e oferece tentar de novo', () => {
      const tentar = vi.fn()
      render(<AuditTrailTimeline versions={[]} error onRetry={tentar} />)
      expect(screen.getByText('Não foi possível carregar a trilha')).toBeInTheDocument()
      fireEvent.click(screen.getByRole('button', { name: /Tentar de novo/ }))
      expect(tentar).toHaveBeenCalled()
    })
  })
})

describe('auditAppearance (FE-443) — aparência é DADO, não `case`', () => {
  it('cada evento conhecido tem ícone, tom e rótulo', () => {
    for (const e of AUDIT_EVENTS) {
      const a = auditAppearance(e)
      expect(a.icon).toBeTruthy()
      expect(a.tone).toBeTruthy()
      expect(a.label).toBeTruthy()
    }
  })

  it('evento novo cai no padrão sem quebrar a tela', () => {
    expect(auditAppearance('algo_que_nao_existe').label).toBe('Evento')
  })

  it('a cor é token semântico, nunca literal — troca sozinha entre claro e escuro', () => {
    for (const e of AUDIT_EVENTS) {
      expect(auditAppearance(e).tone).not.toMatch(/#[0-9a-f]{3,8}|rgb\(|hsl\(/i)
    }
  })

  // O portão da tarefa: acrescentar um tipo não exige mexer em componente.
  it('criação, alteração e remoção têm tons diferentes entre si', () => {
    const tons = ['create', 'update', 'destroy'].map((e) => auditAppearance(e).tone)
    expect(new Set(tons).size).toBe(3)
  })
})
