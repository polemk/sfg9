import { describe, it, expect, vi, beforeEach } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { FileDropzone } from '@/components/ui/FileDropzone'
import { useInstallmentPreview } from '@/hooks/useInstallmentPreview'
import type { AttachmentLimit } from '@/features/attachments/types'

/**
 * S9 / tarefa 4.24 — os três comportamentos de tela que **não** se provam com
 * `tsc` nem olhando a página: a prévia que não recalcula, a confirmação que não
 * se autodescarta, e o limite comunicado antes do upload.
 */

vi.mock('@/lib/api/renegotiations', () => ({
  renegotiationsApi: {
    installments: {
      preview: vi.fn(),
    },
  },
}))

import { renegotiationsApi } from '@/lib/api/renegotiations'

function envolver() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  )
}

// ---------------------------------------------------------------------------
// FE-221 / C2 — a prévia vem do SERVIDOR
// ---------------------------------------------------------------------------
describe('useInstallmentPreview — os derivados vêm do servidor', () => {
  beforeEach(() => vi.clearAllMocks())

  function Sonda({ main }: { main: number | null }) {
    const { preview, idle, loading } = useInstallmentPreview('r-1', {
      due_date: '2025-01-10',
      main_value: main,
      interest_value: 50,
      monetary_correction_value: 10,
    })
    return (
      <div>
        <span data-testid="estado">{idle ? 'idle' : loading ? 'loading' : 'pronto'}</span>
        <span data-testid="total">{preview?.installments?.[0]?.installment_total_value ?? '—'}</span>
      </div>
    )
  }

  it('NÃO soma nada localmente: enquanto a resposta não chega, mostra o traço', async () => {
    // Se o hook somasse `1000 + 50 + 10` em JavaScript, o total apareceria antes
    // de qualquer resposta — e passaria a existir uma segunda fonte da regra
    // financeira (D-09).
    let resolver: (valor: unknown) => void = () => {}
    ;(renegotiationsApi.installments.preview as any).mockReturnValue(
      new Promise((res) => {
        resolver = res
      }),
    )

    render(<Sonda main={1000} />, { wrapper: envolver() })

    expect(screen.getByTestId('estado').textContent).toBe('loading')
    expect(screen.getByTestId('total').textContent).toBe('—')

    // **O número que aparece é o que o servidor mandou** — inclusive um que a
    // conta local jamais produziria.
    resolver({ installments: [{ installment_total_value: '999.99' }], renegotiation: {} })
    await waitFor(() => expect(screen.getByTestId('total').textContent).toBe('999.99'))
  })

  it('não consulta com rascunho inválido — 422 a cada tecla é ruído', () => {
    render(<Sonda main={0} />, { wrapper: envolver() })

    expect(screen.getByTestId('estado').textContent).toBe('idle')
    expect(renegotiationsApi.installments.preview).not.toHaveBeenCalled()
  })
})

// ---------------------------------------------------------------------------
// FE-218 — a confirmação NÃO se autodescarta
// ---------------------------------------------------------------------------
describe('ConfirmDialog — operação irreversível não some sozinha', () => {
  it('continua aberta depois de 30 segundos (o legado descartava em 6)', () => {
    vi.useFakeTimers()
    const aoConfirmar = vi.fn()

    render(
      <ConfirmDialog
        open
        onOpenChange={() => {}}
        title="Remover 3 previsão(ões)?"
        description="A remoção é definitiva."
        confirmLabel="Remover 3 previsão(ões)"
        onConfirm={aoConfirmar}
      />,
    )

    expect(screen.getByText('Remover 3 previsão(ões)?')).toBeTruthy()
    vi.advanceTimersByTime(30_000)
    // Ainda aberta. Quem parou para pensar não perdeu a caixa.
    expect(screen.getByText('Remover 3 previsão(ões)?')).toBeTruthy()

    vi.useRealTimers()
  })

  it('bloqueia o botão e DIZ o motivo quando não há o que confirmar', () => {
    const aoConfirmar = vi.fn()

    render(
      <ConfirmDialog
        open
        onOpenChange={() => {}}
        title="Remover 0 previsão(ões)?"
        description="A remoção é definitiva."
        confirmLabel="Remover"
        canConfirm={false}
        blockedReason="Selecione ao menos uma previsão."
        onConfirm={aoConfirmar}
      />,
    )

    expect(screen.getByText('Selecione ao menos uma previsão.')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Remover' }))
    expect(aoConfirmar).not.toHaveBeenCalled()
  })

  it('o rótulo de confirmar diz O QUE vai acontecer, não "OK"', () => {
    // No legado o texto de uma tela vazava na outra: "Excluir previsão" aparecia
    // ao excluir um PAGAMENTO. Por isso a prop é obrigatória e sem padrão.
    render(
      <ConfirmDialog
        open
        onOpenChange={() => {}}
        title="Excluir este pagamento?"
        description="A previsão volta a ficar em aberto."
        confirmLabel="Excluir pagamento"
        onConfirm={() => {}}
      />,
    )
    expect(screen.getByRole('button', { name: 'Excluir pagamento' })).toBeTruthy()
  })
})

// ---------------------------------------------------------------------------
// FE-210 / D-50 — o limite é comunicado ANTES do upload
// ---------------------------------------------------------------------------
describe('FileDropzone — o limite aparece na tela, com o número do servidor', () => {
  const limite: AttachmentLimit = {
    multiple: true,
    maxFiles: 4,
    maxSizeBytes: 5 * 1024 * 1024,
    maxSizeMegabytes: 5,
    contentTypes: ['pdf', 'png'],
  }

  it('mostra quantos arquivos cabem e quanto cada um pode pesar', () => {
    render(<FileDropzone limit={limite} attachedCount={1} onPick={() => {}} />)

    expect(screen.getByText(/Até 4 arquivos, 5 MB cada/)).toBeTruthy()
    expect(screen.getByText(/Faltam 3/)).toBeTruthy()
  })

  it('quando o teto foi atingido, DIZ isso e desabilita — em vez de deixar tentar', () => {
    // Corrige o D-50: no legado o indicador de bloqueio era escrito no HTML e
    // nunca lido pelo JavaScript; o usuário escolhia o arquivo e só descobria
    // depois.
    render(<FileDropzone limit={limite} attachedCount={4} onPick={() => {}} />)

    expect(screen.getByText(/Limite de 4 arquivos atingido/)).toBeTruthy()
    expect(screen.getByRole('button', { name: 'Escolher arquivos' })).toHaveProperty('disabled', true)
  })

  it('sem limite conhecido NÃO inventa um número', () => {
    // Inventar um padrão aqui é como a tela e o servidor divergem.
    render(<FileDropzone limit={undefined} attachedCount={0} onPick={() => {}} />)
    expect(screen.queryByText(/Até \d+ arquivos/)).toBeNull()
  })
})

// ---------------------------------------------------------------------------
// §5.4 — o portão de tokens desta fatia
// ---------------------------------------------------------------------------
describe('S9 — a área não escreve cor nem z-index literal (§5.4.2, §5.4.7)', () => {
  const RAIZ = path.resolve(__dirname, '../../../..')
  const AREAS = [
    'app/pages/renegotiations',
    'components/renegotiations',
  ].map((p) => path.join(RAIZ, p))

  function arquivos(dir: string, acc: string[] = []): string[] {
    for (const entrada of fs.readdirSync(dir, { withFileTypes: true })) {
      const completo = path.join(dir, entrada.name)
      if (entrada.isDirectory()) {
        if (entrada.name === '__tests__') continue
        arquivos(completo, acc)
      } else if (/\.tsx?$/.test(entrada.name)) {
        acc.push(completo)
      }
    }
    return acc
  }

  const fontes = AREAS.flatMap((dir) => arquivos(dir))

  it('nenhum arquivo tem #hex, rgb() ou z-[…]', () => {
    const infratores = fontes.filter((arquivo) => {
      const fonte = fs
        .readFileSync(arquivo, 'utf8')
        .split('\n')
        // Comentário que EXPLICA a regra não é reincidência.
        .filter((linha) => !linha.trim().startsWith('*') && !linha.trim().startsWith('//'))
        .join('\n')
      return /#[0-9a-fA-F]{3,6}\b|rgba?\(|bg-gradient|z-\[/.test(fonte)
    })

    expect(infratores.map((f) => path.basename(f))).toEqual([])
  })

  it('nenhum arquivo usa classe de paleta literal do Tailwind', () => {
    const infratores = fontes.filter((arquivo) => {
      const fonte = fs.readFileSync(arquivo, 'utf8')
      return /\b(bg|text|border)-(slate|gray|zinc|blue|emerald|rose|amber|red|green)-\d{2,3}\b/.test(fonte)
    })

    expect(infratores.map((f) => path.basename(f))).toEqual([])
  })

  it('`beauty_state` nunca chega à tela sem passar por pt-BR', () => {
    // O servidor devolve `"66.87% Pago"` — `paid_percent.to_s` concatenado, com
    // PONTO decimal (réplica de `../sfg/app/models/renegotiation.rb:129`). Renderizar
    // essa string crua põe `66.87% Pago` numa tela em português; foi o que o usuário
    // viu em `/renegotiations`, e é a terceira vez que este descuido aparece no
    // projeto (S8: `2.55%`; S15: `51.76%` ao lado de `109,0%`).
    const infratores = fontes.filter((arquivo) =>
      fs
        .readFileSync(arquivo, 'utf8')
        .split('\n')
        .some((linha) => /\.beauty_state/.test(linha) && !/localizePercentLabel/.test(linha)),
    )

    expect(infratores.map((f) => path.basename(f))).toEqual([])
  })

  it('todo valor monetário usa `font-numeric` (§5.4.2)', () => {
    // Sem `tabular-nums` a coluna de valor não alinha — e neste produto isso é
    // defeito, não estética.
    const comDinheiro = fontes.filter((f) => /formatarReais/.test(fs.readFileSync(f, 'utf8')))
    const semFonte = comDinheiro.filter((f) => !/font-numeric/.test(fs.readFileSync(f, 'utf8')))

    expect(semFonte.map((f) => path.basename(f))).toEqual([])
  })
})
