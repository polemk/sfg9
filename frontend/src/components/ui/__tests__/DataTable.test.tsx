import { describe, it, expect, vi } from 'vitest'
import { render, screen, fireEvent, within } from '@testing-library/react'
import { DataTable, type Column } from '@/components/ui/DataTable'

interface Linha {
  id: string
  cliente: string
  valor: number
  vencimento: string
  situacao: string
}

const DADOS: Linha[] = [
  { id: '1', cliente: 'Beta', valor: 300, vencimento: '2026-03-01', situacao: 'Em dia' },
  { id: '2', cliente: 'alfa', valor: 1000, vencimento: '2026-01-15', situacao: 'Vencido' },
  { id: '3', cliente: 'Gama', valor: 50, vencimento: '2026-07-20', situacao: 'Em dia' },
]

const COLUNAS: Column<Linha>[] = [
  { key: 'cliente', header: 'Cliente', sortable: true },
  { key: 'valor', header: 'Valor', variant: 'money', sortable: true },
  { key: 'vencimento', header: 'Vencimento', variant: 'date', sortable: true },
  { key: 'situacao', header: 'Situação' },
]

function clientesNaOrdem() {
  const linhas = screen.getAllByRole('row').slice(1) // pula o cabeçalho
  return linhas.map((r) => within(r).getAllByRole('cell')[0].textContent)
}

describe('DataTable — o cabeçalho ordena de verdade (FE-061)', () => {
  it('ordena crescente, decrescente e volta à ordem original em três cliques', () => {
    render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} />)
    const cabecalho = screen.getByRole('button', { name: /Cliente/ })

    fireEvent.click(cabecalho)
    // `localeCompare` pt-BR ignora caixa: "alfa" vem antes de "Beta".
    expect(clientesNaOrdem()).toEqual(['alfa', 'Beta', 'Gama'])

    fireEvent.click(cabecalho)
    expect(clientesNaOrdem()).toEqual(['Gama', 'Beta', 'alfa'])

    fireEvent.click(cabecalho)
    expect(clientesNaOrdem()).toEqual(['Beta', 'alfa', 'Gama'])
  })

  it('ordena número como número, não como texto', () => {
    render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} />)
    fireEvent.click(screen.getByRole('button', { name: /Valor/ }))
    // Como texto, "1000" viria antes de "300".
    expect(clientesNaOrdem()).toEqual(['Gama', 'Beta', 'alfa'])
  })

  it('coluna sem `sortable` NÃO vira botão e não anuncia aria-sort', () => {
    render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} />)
    expect(screen.queryByRole('button', { name: /Situação/ })).toBeNull()
    const th = screen.getByText('Situação').closest('th')!
    expect(th.getAttribute('aria-sort')).toBeNull()
  })

  it('coluna ordenável anuncia aria-sort e ele acompanha a direção', () => {
    render(<DataTable columns={COLUNAS} data={DADOS} rowKey={(r) => r.id} />)
    const th = screen.getByText('Cliente').closest('th')!
    expect(th).toHaveAttribute('aria-sort', 'none')
    fireEvent.click(screen.getByRole('button', { name: /Cliente/ }))
    expect(th).toHaveAttribute('aria-sort', 'ascending')
    fireEvent.click(screen.getByRole('button', { name: /Cliente/ }))
    expect(th).toHaveAttribute('aria-sort', 'descending')
  })

  it('no modo `server` delega a ordenação em vez de ordenar sozinho', () => {
    const onSortChange = vi.fn()
    render(
      <DataTable
        columns={COLUNAS}
        data={DADOS}
        rowKey={(r) => r.id}
        sortMode="server"
        sort={null}
        onSortChange={onSortChange}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: /Cliente/ }))
    // A COLUNA CLICADA viaja no segundo argumento (FE-159/194/254): no terceiro
    // clique o primeiro argumento é `null` e não diz mais qual coluna foi
    // desligada, e quem empilha ordenações precisa saber para tirar a chave
    // certa da pilha em vez de limpar tudo. Ver `useSortStack`.
    expect(onSortChange).toHaveBeenCalledWith({ key: 'cliente', direction: 'asc' }, 'cliente')
    // A ordem na tela não muda: quem ordena é a consulta.
    expect(clientesNaOrdem()).toEqual(['Beta', 'alfa', 'Gama'])
  })

  it('não muta o array recebido — ele é o cache da consulta', () => {
    const dados = [...DADOS]
    render(<DataTable columns={COLUNAS} data={dados} rowKey={(r) => r.id} />)
    fireEvent.click(screen.getByRole('button', { name: /Valor/ }))
    expect(dados.map((d) => d.id)).toEqual(['1', '2', '3'])
  })

  it('formata moeda e data em pt-BR na célula', () => {
    render(<DataTable columns={COLUNAS} data={[DADOS[0]]} rowKey={(r) => r.id} />)
    expect(screen.getByText(/R\$\s?300,00/)).toBeInTheDocument()
    expect(screen.getByText('01/03/2026')).toBeInTheDocument()
  })
})
