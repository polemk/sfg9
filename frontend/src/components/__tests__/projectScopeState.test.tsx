import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'

/**
 * Este componente nasceu DUAS vezes no mesmo dia — `ProjectScopeNotice` (S9, S10)
 * e `ProjectScopeState` (S5, S11) — com props diferentes, nomes de função
 * diferentes e quatro textos diferentes para as mesmas duas situações. As quatro
 * fatias tinham o mesmo problema ao mesmo tempo e nenhuma sabia da outra.
 *
 * Os testes existem para o arquivo continuar sendo um só, e para travar as duas
 * decisões da fusão que são fáceis de desfazer sem perceber.
 */
describe('projectScopeCode', () => {
  const erro = (status: number, code?: string) => ({ response: { status, data: code ? { code } : {} } })

  it('reconhece os dois códigos de escopo em 409', () => {
    expect(projectScopeCode(erro(409, 'PROJECT_NOT_SELECTED'))).toBe('PROJECT_NOT_SELECTED')
    expect(projectScopeCode(erro(409, 'PROJECT_NONE_AVAILABLE'))).toBe('PROJECT_NONE_AVAILABLE')
  })

  it('NÃO reconhece o mesmo código fora do 409', () => {
    // Uma das duas versões casava só pelo `code`. `code` é uma string qualquer:
    // um 500 que ecoe o payload, ou um proxy, viraria "escolha um projeto".
    expect(projectScopeCode(erro(500, 'PROJECT_NOT_SELECTED'))).toBeNull()
    expect(projectScopeCode(erro(404, 'PROJECT_NONE_AVAILABLE'))).toBeNull()
  })

  it('deixa o 404 de projeto passar como erro de verdade', () => {
    // `PROJECT_NOT_FOUND` NÃO é estado de tela: é o 404 anti-enumeração.
    expect(projectScopeCode(erro(404, 'PROJECT_NOT_FOUND'))).toBeNull()
  })

  it('devolve null para o que não é erro de escopo', () => {
    expect(projectScopeCode(null)).toBeNull()
    expect(projectScopeCode(new Error('rede'))).toBeNull()
    expect(projectScopeCode(erro(409))).toBeNull()
  })
})

describe('ProjectScopeState', () => {
  it('"não escolheu" manda escolher, e diz ONDE — barra lateral, não topo', () => {
    render(<ProjectScopeState code="PROJECT_NOT_SELECTED" recurso="os limites de risco" />)

    expect(screen.getByText(/escolha um projeto/i)).toBeInTheDocument()
    // O ai9 não tem topbar; o seletor vive na barra lateral. Um dos dois
    // componentes dizia "no topo" e mandaria o usuário procurar onde não há.
    expect(screen.getByText(/barra lateral/i)).toBeInTheDocument()
    expect(screen.queryByText(/no topo/i)).not.toBeInTheDocument()
  })

  it('"não participa de nenhum" tira a culpa do usuário', () => {
    render(<ProjectScopeState code="PROJECT_NONE_AVAILABLE" recurso="as renegociações" />)

    expect(screen.getByText(/não participa de nenhum projeto/i)).toBeInTheDocument()
    expect(screen.getByText(/administrador/i)).toBeInTheDocument()
    // A frase que impede a pessoa de ficar procurando o próprio erro.
    expect(screen.getByText(/nada a corrigir/i)).toBeInTheDocument()
  })

  it('a frase nomeia o recurso da tela em vez de falar genérico', () => {
    render(<ProjectScopeState code="PROJECT_NOT_SELECTED" recurso="as disponibilidades" />)
    expect(screen.getByText(/As disponibilidades são de um projeto por vez/i)).toBeInTheDocument()
  })

  it('sem `recurso` continua legível — a prop é opcional', () => {
    render(<ProjectScopeState code="PROJECT_NOT_SELECTED" />)
    expect(screen.getByText(/Estes dados são de um projeto por vez/i)).toBeInTheDocument()
  })
})
