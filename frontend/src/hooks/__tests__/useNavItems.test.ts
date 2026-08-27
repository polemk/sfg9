import { describe, it, expect } from 'vitest'
import { filtrarGrupos, filtrarPorPermissao } from '@/hooks/useNavItems'
import { CONSOLE_NAV_GROUPS, CONSOLE_NAV_ITEMS, type RoleSlug } from '@/app/consoleNavigation'

/**
 * O menu por papel — contrato **C3**, **sempre os dois lados**.
 *
 * Um teste que só verifique "o Colaborador NÃO vê Admin" **passa com o filtro
 * invertido**: numa hierarquia onde menor = mais poder (DEC-41), trocar `<` por
 * `>` some com o grupo Admin para todo mundo, e o teste continua verde. Por
 * isso cada caso abaixo afirma o que aparece **e** o que não aparece.
 */

const ids = (grupos: ReturnType<typeof filtrarGrupos>) => grupos.map((g) => g.id)

/**
 * As regras de C3/C1 são exercitadas em `filtrarPorPermissao`, **sem** a regra
 * de "a página já foi entregue". Misturar as duas faria "o Gerente traz o grupo
 * Cadastro" depender de quais fatias já chegaram — e o teste passaria a falhar
 * por motivo que não é o dele.
 */
function menuDe(role: RoleSlug | null, hasProject: boolean) {
  return filtrarPorPermissao(CONSOLE_NAV_GROUPS, { role, hasProject, mode: 'all' })
    .filter((g) => g.items.length > 0 || Boolean(g.path))
}

function itensDe(role: RoleSlug | null, hasProject: boolean) {
  return menuDe(role, hasProject).flatMap((g) => g.items.map((i) => i.id))
}

/** O que a sidebar realmente desenha hoje: permissão E página entregue. */
function menuRenderizadoDe(role: RoleSlug | null, hasProject: boolean) {
  return filtrarGrupos(CONSOLE_NAV_GROUPS, { role, hasProject, mode: 'all' })
}

describe('menu por papel (6.1.1, 6.1.2, F.3)', () => {
  it('Gerente: NÃO traz o grupo Admin E TRAZ o grupo Cadastro', () => {
    const grupos = ids(menuDe('gerente', true))
    expect(grupos).not.toContain('admin_settings')
    expect(grupos).toContain('management')
  })

  it('Colaborador: NÃO traz Cadastro nem Admin E TRAZ as telas do projeto', () => {
    const grupos = ids(menuDe('colaborador', true))
    expect(grupos).not.toContain('management')
    expect(grupos).not.toContain('admin_settings')
    // Os grupos "Gestão" e "Projeto" não têm gate de papel: o Colaborador entra,
    // desde que participe de algum projeto.
    expect(grupos).toContain('results_group')
    expect(grupos).toContain('project_group')
  })

  it('OG e Admin: trazem Cadastro E Admin', () => {
    for (const papel of ['og', 'admin'] as RoleSlug[]) {
      const grupos = ids(menuDe(papel, true))
      expect(grupos, papel).toContain('management')
      expect(grupos, papel).toContain('admin_settings')
    }
  })

  it('DEC-18.2: "Permissões" é de OG e Admin — o Gerente vê o grupo Cadastro sem esse item', () => {
    expect(itensDe('gerente', true)).not.toContain('permissions')
    expect(itensDe('og', true)).toContain('permissions')
  })

  it('papel desconhecido cai no conjunto MAIS RESTRITO, nunca no mais amplo', () => {
    const grupos = ids(menuDe(null, true))
    expect(grupos).not.toContain('management')
    expect(grupos).not.toContain('admin_settings')
    expect(grupos).not.toContain('platform')
  })
})

describe('gate de participação em projeto (6.1.3)', () => {
  it('sem participação, o conjunto é reduzido; com participação, é o completo do papel', () => {
    const semProjeto = ids(menuDe('colaborador', false))
    const comProjeto = ids(menuDe('colaborador', true))

    expect(semProjeto).not.toContain('results_group')
    expect(semProjeto).not.toContain('project_group')
    expect(comProjeto).toContain('results_group')
    expect(comProjeto).toContain('project_group')

    // O que não depende de projeto continua lá nos dois casos.
    expect(semProjeto).toContain('dash')
    // `account` NAO entra: o Perfil vive no dropdown do avatar, no rodape da
    // sidebar. Repetir o destino em dois lugares da mesma casca nao da acesso
    // novo — ver HIDDEN_GROUPS em sidebarModeStore.
    expect(semProjeto).not.toContain('account')
  })

  it('o gate de projeto NÃO derruba os grupos administrativos', () => {
    const grupos = ids(menuDe('og', false))
    expect(grupos).toContain('management')
    expect(grupos).toContain('admin_settings')
  })

  it('enquanto a consulta de projeto não voltou (`undefined`), o grupo fica escondido — não pisca', () => {
    const grupos = ids(filtrarPorPermissao(CONSOLE_NAV_GROUPS, { role: 'og', hasProject: undefined, mode: 'all' }))
    expect(grupos).not.toContain('results_group')
  })
})

describe('locked e inactive (6.1.4, DEC-15.1 e DEC-58)', () => {
  /**
   * O teste que reprova quem "conserta" o D-90 marcando os quatro.
   *
   * No legado a flag `locked` era escrita no ITEM e lida do GRUPO
   * (`_container.html.erb:24`), então os 4 itens marcados nunca ficaram
   * travados. Quem lê só o código legado conclui que corrigir é marcar os
   * quatro — e desliga disponibilidades e cobranças, que estão VIVAS em
   * produção (DEC-15.1). Porta-se o **efeito**, corrige-se o **mecanismo**.
   */
  it('NENHUM item nasce `locked` — disponibilidades e cobranças aparecem', () => {
    const marcados = CONSOLE_NAV_ITEMS.filter((i) => i.locked).map((i) => i.id)
    expect(marcados).toEqual([])

    const historicamenteMarcados = [
      'availability',
      'charges',
      'project_availabilities',
      'availability_templates',
    ]
    for (const id of historicamenteMarcados) {
      const item = CONSOLE_NAV_ITEMS.find((i) => i.id === id)
      expect(item, `${id} sumiu do registro`).toBeDefined()
      expect(item!.locked, `${id} nasceu locked`).toBeFalsy()
    }
  })

  it('DEC-58: o mecanismo de item inativo existe e NENHUM item o usa', () => {
    // O item `reports` do legado nunca existiu: nenhuma entrada de
    // `application_helper.rb:103-171` tem `identifier: "reports"`, então a
    // condição da view nunca foi verdadeira. Portamos o mecanismo, não o item.
    expect(CONSOLE_NAV_ITEMS.some((i) => i.id === 'reports')).toBe(false)
    expect(CONSOLE_NAV_ITEMS.filter((i) => i.inactive).map((i) => i.id)).toEqual([])
  })
})

describe('coerência do registro', () => {
  it('todo item visível tem página montada — menu nunca leva a 404', () => {
    for (const papel of ['og', 'admin', 'gerente', 'colaborador'] as RoleSlug[]) {
      for (const item of menuRenderizadoDe(papel, true).flatMap((g) => g.items)) {
        expect(item.element, `${item.id} apareceu sem página`).not.toBeNull()
      }
    }
  })

  it('grupo sem nenhuma página entregue não desenha um acordeão vazio', () => {
    for (const g of menuRenderizadoDe('og', true)) {
      expect(g.items.length > 0 || Boolean(g.path), `grupo ${g.id} ficou vazio`).toBe(true)
    }
  })

  it('os caminhos são únicos', () => {
    const paths = CONSOLE_NAV_ITEMS.map((i) => i.path)
    expect(new Set(paths).size).toBe(paths.length)
  })

  it('DEC-83: a tela de pareamento por WhatsApp está roteada e é de OG e Admin', () => {
    const whatsapp = CONSOLE_NAV_ITEMS.find((i) => i.id === 'whatsapp')
    expect(whatsapp).toBeDefined()
    expect(whatsapp!.element).not.toBeNull()
    expect(whatsapp!.roles).toEqual(['og', 'admin'])
    expect(itensDe('gerente', true)).not.toContain('whatsapp')
    expect(itensDe('og', true)).toContain('whatsapp')
  })

  it('DEC-77: a trilha global está roteada e é item de OG e Admin', () => {
    const trilha = CONSOLE_NAV_ITEMS.find((i) => i.id === 'audit_trail')
    expect(trilha).toBeDefined()
    // A tela é da S19 e ficaria construída e inalcançável sem a rota daqui.
    expect(trilha!.element).not.toBeNull()
    expect(trilha!.path).toBe('/admin/audit-trail')
    expect(trilha!.roles).toEqual(['og', 'admin'])

    // O menu tem que dizer o mesmo que o servidor: OG 200 · Admin 200 ·
    // Gerente 403 · Colaborador 403. Item visível para quem toma 403 ao clicar
    // é pior que item ausente.
    expect(itensDe('og', true)).toContain('audit_trail')
    expect(itensDe('admin', true)).toContain('audit_trail')
    expect(itensDe('gerente', true)).not.toContain('audit_trail')
    expect(itensDe('colaborador', true)).not.toContain('audit_trail')
  })

  it('DS2-1: a tela de mensagens NÃO é órfã — tem item de menu', () => {
    const mensagens = CONSOLE_NAV_ITEMS.find((i) => i.id === 'admin_messages')
    expect(mensagens).toBeDefined()
    expect(mensagens!.element).not.toBeNull()
    expect(itensDe('admin', true)).toContain('admin_messages')
  })

  it('ícone de destino não repete ícone de MODO (sidebar recolhida)', () => {
    // Com a sidebar recolhida só o ícone aparece. Se um grupo usasse o mesmo
    // ícone do `SidebarModeToggle`, os dois controles ficariam
    // indistinguíveis — foi um defeito real desta base.
    const iconesDeModo = ['Layers', 'Briefcase', 'FileText', 'Settings2']
    for (const g of CONSOLE_NAV_GROUPS) {
      const nome = (g.icon as any).displayName ?? (g.icon as any).name
      expect(iconesDeModo, `grupo ${g.id}`).not.toContain(nome)
    }
  })
})

describe('modos do SidebarModeToggle — o modo É o grupo', () => {
  it('escolher um modo mostra o grupo dele e os fixos, e nada mais', () => {
    const todos = itensDe('og', true)
    const grupos = filtrarGrupos(CONSOLE_NAV_GROUPS, { role: 'og', hasProject: true, mode: 'platform' })
    const ids = grupos.map((g) => g.id)
    const itens = grupos.flatMap((g) => g.items.map((i) => i.id))

    expect(itens.length).toBeLessThan(todos.length)
    // O grupo escolhido entra...
    expect(ids).toContain('platform')
    // ...os fixos escapam do filtro (senão o usuário perde o caminho de volta)...
    expect(ids).toContain('dash')
    // ...e nenhum outro contexto de trabalho aparece.
    expect(ids).not.toContain('results_group')
    expect(ids).not.toContain('management')
  })

  it('o modo `all` traz todos os contextos', () => {
    const ids = filtrarGrupos(CONSOLE_NAV_GROUPS, { role: 'og', hasProject: true, mode: 'all' }).map((g) => g.id)
    expect(ids).toContain('platform')
    expect(ids).toContain('management')
  })
})
