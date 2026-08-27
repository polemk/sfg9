import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { MemoryRouter } from 'react-router-dom'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'

/**
 * S4 / seção 7.5 — as garantias da fatia de projeto e empresas que se verificam
 * **no cliente**.
 *
 * As de escopo (7.1) são do servidor e vivem em `spec/requests/api/v1/`. O que
 * se prova aqui é o outro lado do contrato: que a tela não oferece o que o
 * servidor recusa, e que ela não inventa dado que o servidor não mandou.
 */
vi.mock('@/hooks/useNavItems', () => ({ useRoleSlug: () => 'og' }))
vi.mock('sonner', () => ({ toast: { success: vi.fn(), error: vi.fn(), warning: vi.fn() } }))

import { MobileRowActions } from '@/components/mobile/MobileRowActions'

const raiz = resolve(__dirname, '../../../../..')
const ler = (caminho: string) => readFileSync(resolve(raiz, caminho), 'utf-8')

/**
 * O código **sem os comentários**.
 *
 * As varreduras abaixo procuram o defeito no que o navegador executa, não no
 * que a próxima pessoa lê. Sem isto, documentar o defeito que se está fechando
 * ("o legado usava `is_active_{id}` nos dois") reprovaria o arquivo que o
 * fechou — e o incentivo passaria a ser não escrever o porquê.
 */
function semComentarios(caminho: string): string {
  return ler(caminho)
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .split('\n')
    .filter((linha) => !linha.trim().startsWith('//'))
    .join('\n')
}

describe('S4 — as marcas do projeto (FE-093)', () => {
  // 7.5.3 — no legado os DOIS interruptores usavam
  // `id="is_active_{project.id}"`: clicar no rótulo de "BI contratado"
  // alternava o de "Gerido pela Safegold". A leitura é do CÓDIGO porque o
  // defeito é de atributo, e um teste de comportamento passaria com os dois ids
  // iguais desde que só um estivesse na tela.
  const fonte = semComentarios('src/app/pages/projects/ProjectDetailPage.tsx')

  it('os dois interruptores têm ids DISTINTOS, e cada rótulo aponta para o seu', () => {
    expect(fonte).toContain('id="has_safegold_management"')
    expect(fonte).toContain('htmlFor="has_safegold_management"')
    expect(fonte).toContain('id="has_bi"')
    expect(fonte).toContain('htmlFor="has_bi"')

    // O id do legado não pode ter voltado por cópia.
    expect(fonte).not.toContain('is_active_')
  })

  it('nenhuma tela da fatia escreve cor literal — a cor do projeto é DADO', () => {
    const telas = [
      'src/app/pages/projects/ProjectsPage.tsx',
      'src/app/pages/projects/ProjectDetailPage.tsx',
      'src/app/pages/projects/CompaniesPage.tsx',
      'src/app/pages/projects/ProvidersPage.tsx',
      'src/app/pages/projects/ProjectGuaranteesPage.tsx',
      'src/app/pages/projects/CarrierConnectionsPage.tsx',
      'src/app/pages/projects/ProjectForm.tsx',
      'src/app/pages/projects/ProviderDocumentField.tsx',
      'src/components/mobile/MobileRowActions.tsx',
      'src/components/mobile/MobileActionBar.tsx',
    ]

    telas.forEach((caminho) => {
      const codigo = semComentarios(caminho)
      // `#RRGGBB`/`rgb()` e as paletas literais do Tailwind. A única cor que
      // aparece nesta fatia é `p.color`, que vem do banco.
      expect(codigo).not.toMatch(/#[0-9a-fA-F]{6}\b/)
      expect(codigo).not.toMatch(/\brgba?\(/)
      expect(codigo).not.toMatch(/\b(bg|text|border)-(slate|gray|zinc|blue|emerald|red|amber)-\d{2,3}\b/)
      expect(codigo).not.toMatch(/\bdark:/)
      expect(codigo).not.toMatch(/\bz-\[/)
    })
  })
})

describe('S4 — as três condições de participação são do SERVIDOR (FE-095)', () => {
  const fonte = semComentarios('src/app/pages/projects/ProjectDetailPage.tsx')

  // A tela **espelha** as condições para não oferecer o que será recusado; ela
  // não as implementa. O comentário e o formato do código provam a intenção, e
  // os três motivos precisam existir — se um sumir, a tela passa a oferecer uma
  // ação que o servidor nega com 403, que é pior que não oferecer.
  it('a lista de membros conhece as TRÊS: dono, você mesmo e perfil sem gestão', () => {
    expect(fonte).toContain('É o dono do projeto')
    expect(fonte).toContain('Você não remove a própria participação')
    expect(fonte).toContain('Seu perfil não gerencia participações')
  })

  it('a mensagem de remoção fala do PROJETO, não da empresa (FE-097)', () => {
    expect(fonte).toContain('saiu deste projeto')
    // O texto do legado, copiado de outra tela.
    expect(fonte).not.toContain('removido da empresa')
  })
})

describe('S4 — nenhum payload de tela carrega dado de OUTRO projeto (7.5.1)', () => {
  // O legado embutia `AvailabilityTemplate.all` num atributo `data-` da página:
  // o HTML de um projeto carregava os padrões de TODOS. A regra aqui é a
  // ausência: nenhuma chamada desta fatia manda `project_id`, e nenhuma lista
  // vem de um `all` do cliente.
  const cliente = semComentarios('src/lib/api/projects.ts')

  it('nenhum cliente ESCOPADO manda `project_id` — o escopo é do servidor', () => {
    // Há **um** `project_id` legítimo no arquivo, e ele não é escopo: é o
    // filtro `project_id` da LISTA DE PROJETOS (BE-082), aplicado pelo servidor
    // DENTRO de `Project.visible_to`. É exatamente o parâmetro que no legado
    // substituía o escopo (`Project.where(id: params[:project_id])`, D-29) e
    // que agora entra no `where`. Ele pertence a `projectsApi` e a mais nenhum.
    const escopados = cliente.slice(
      cliente.indexOf('export const companiesApi'),
      cliente.indexOf('export const projectsApi'),
    )
    expect(escopados).not.toMatch(/project_id/)

    // O corpo de `create`/`update` é montado pela tela; nenhuma delas o inclui.
    ;[
      'src/app/pages/projects/ProjectsPage.tsx',
      'src/app/pages/projects/CompaniesPage.tsx',
      'src/app/pages/projects/ProvidersPage.tsx',
      'src/app/pages/projects/ProjectGuaranteesPage.tsx',
    ].forEach((caminho) => {
      expect(semComentarios(caminho)).not.toMatch(/project_id/)
    })
  })

  it('o filtro por id de garantia existe e vai como `project_guarantee_id`, dentro do escopo', () => {
    expect(cliente).toContain('project_guarantee_id')
  })
})

describe('S4 — o formulário salva com UMA requisição (FE-089 / DC-23)', () => {
  // **O alvo é `ProjectActions`, e não mais `ProjectsPage`** (FE-094): a gaveta
  // e as mutações saíram da lista para um módulo compartilhado com o detalhe,
  // porque o detalhe também precisava editar e remover — e duplicar a regra do
  // projeto de treinamento em duas telas era o que se queria evitar.
  //
  // O guarda continua o mesmo e continua textual: quem mora aqui é o único
  // disparo do salvamento, então é aqui que se conta.
  const fonte = semComentarios('src/app/pages/projects/ProjectActions.tsx')
  const lista = semComentarios('src/app/pages/projects/ProjectsPage.tsx')
  const detalhe = semComentarios('src/app/pages/projects/ProjectDetailPage.tsx')

  it('não há autosave: nenhum `onKeyUp`/`onBlur` dispara mutação', () => {
    // No legado o formulário de projeto registrava salvamento a cada `keyup`.
    expect(fonte).not.toMatch(/onKeyUp/)
    expect(fonte).not.toMatch(/onBlur=\{\(\)\s*=>\s*salvar/)
    // O único disparo é o botão.
    const disparos = fonte.match(/salvar\.mutate\(/g) ?? []
    expect(disparos.length).toBe(1)
  })

  it('nem a lista nem o detalhe têm uma SEGUNDA cópia do salvamento', () => {
    // A extração só vale se ela de fato removeu a duplicata: uma cópia
    // esquecida numa das telas divergiria na primeira mudança de regra.
    for (const [nome, texto] of [['lista', lista], ['detalhe', detalhe]] as const) {
      expect(texto, `${nome} ainda dispara o salvamento por conta própria`).not.toMatch(/salvar\.mutate\(/)
      expect(texto, `${nome} ainda monta o formulário por conta própria`).not.toMatch(/<ProjectForm/)
    }
  })
})

describe('S4 — polling é proibido (Princípio 10)', () => {
  it('nenhuma tela da fatia usa `refetchInterval` nem `setInterval`', () => {
    const telas = [
      'src/app/pages/projects/ProjectsPage.tsx',
      'src/app/pages/projects/ProjectDetailPage.tsx',
      'src/app/pages/projects/CompaniesPage.tsx',
      'src/app/pages/projects/ProvidersPage.tsx',
      'src/app/pages/projects/ProjectGuaranteesPage.tsx',
      'src/app/pages/projects/CarrierConnectionsPage.tsx',
    ]
    telas.forEach((caminho) => {
      const codigo = semComentarios(caminho)
      expect(codigo).not.toContain('refetchInterval')
      expect(codigo).not.toContain('setInterval')
    })
  })
})

describe('S4 — a folha de ações do telefone (DEC-100)', () => {
  /**
   * **A folha é do TELEFONE, e agora isto está DECLARADO.**
   *
   * Estes exemplos sempre falaram do telefone — está no nome — mas rodavam na
   * largura padrão do jsdom (1024), e passavam porque a folha era incondicional.
   * Desde 26/08/2026 ela não é: acima de 768 px o mesmo componente rende um menu
   * ancorado no "…", que foi o pedido do usuário (*"no desktop tem que ser
   * dropdown"*). O que faltava aqui era dizer em que aparelho o exemplo roda.
   *
   * O lado de desktop tem portão próprio em
   * `components/mobile/__tests__/rowActionsDesktop.test.tsx`.
   */
  const larguraOriginal = window.innerWidth
  beforeEach(() => {
    Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: 390 })
  })
  afterEach(() => {
    Object.defineProperty(window, 'innerWidth', {
      configurable: true,
      writable: true,
      value: larguraOriginal,
    })
  })

  function montar(props: Partial<Parameters<typeof MobileRowActions>[0]> = {}) {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
    const onOpenChange = vi.fn()
    const escolher = vi.fn()
    const utils = render(
      <MemoryRouter>
        <QueryClientProvider client={client}>
          <MobileRowActions
            open
            onOpenChange={onOpenChange}
            title="Construtora Alfa"
            subtitle="Empresa"
            actions={[
              { key: 'editar', label: 'Editar', onSelect: escolher },
              {
                key: 'excluir',
                label: 'Excluir',
                destructive: true,
                disabledReason: '3 limites de risco usam esta empresa — não é possível excluir',
                onSelect: escolher,
              },
            ]}
            {...props}
          />
        </QueryClientProvider>
      </MemoryRouter>,
    )
    return { ...utils, onOpenChange, escolher }
  }

  it('a ação bloqueada APARECE e diz por quê — não some da folha', () => {
    montar()
    const excluir = screen.getByRole('button', { name: /Excluir/ })
    expect(excluir).toBeDisabled()
    expect(screen.getByText(/3 limites de risco usam esta empresa/)).toBeInTheDocument()
  })

  it('a ação liberada dispara e fecha a folha', () => {
    const { escolher, onOpenChange } = montar()
    fireEvent.click(screen.getByRole('button', { name: 'Editar' }))
    expect(escolher).toHaveBeenCalledTimes(1)
    expect(onOpenChange).toHaveBeenCalledWith(false)
  })

  it('a folha é um diálogo rotulado — o leitor de tela anuncia sobre o que são as ações', () => {
    montar()
    expect(screen.getByRole('dialog', { name: /Ações de Construtora Alfa/ })).toBeInTheDocument()
  })
})
