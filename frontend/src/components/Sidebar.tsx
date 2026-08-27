import { useEffect, useRef, useState } from 'react'
import { Link, NavLink, useLocation, useNavigate } from 'react-router-dom'
import { notify } from '@/lib/notify'
import {
    Bell,
    ChevronDown,
    ChevronLeft,
    ChevronRight,
    Lock,
    LogOut,
    Menu,
    MessageCircle,
    Moon,
    Sun,
    User,
} from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { FloatingPanel } from '@/components/ui/FloatingPanel'
import { Switch } from '@/components/ui/switch'
import { Tooltip } from '@/components/ui/Tooltip'
import { UserAvatar } from '@/components/ui/UserAvatar'
import { rotuloDeVerificacao } from '@/features/auth/identityLabels'
import { Logo } from '@/components/brand/Logo'
import { ImpersonateSelector } from '@/components/ImpersonateSelector'
import { SidebarModeToggle } from '@/components/SidebarModeToggle'
import { SidebarSearch } from '@/components/SidebarSearch'
import { ProjectSelector } from '@/components/ProjectSelector'
import { useChat } from '@/contexts/ChatContext'
import { useSidebarMode } from '@/store/sidebarModeStore'
import { useNavGroups } from '@/hooks/useNavItems'
import { useTheme } from '@/hooks/useTheme'
import { authService } from '@/lib/api/auth'
import { useAuthStore, useRole } from '@/store/authStore'
import { cn } from '@/lib/utils'
import type { NavGroup, NavItem } from '@/app/consoleNavigation'

/**
 * A casca de navegação do console (FE-395, FE-396, FE-741).
 *
 * ### O que mudou em relação à base
 *
 * O menu era uma lista **plana** de 5 itens. O Safegold tem **6 grupos**
 * (`create_console_menu`), e lista plana com 30 e poucas entradas é rolagem
 * infinita. Os grupos viram **acordeão**, com o grupo do item ativo aberto por
 * padrão.
 *
 * ### Três armadilhas desta casca, já pagas antes
 *
 * 1. **O `<aside>` usa `.glass-panel`, que aplica `backdrop-filter`, que CRIA
 *    CONTEXTO DE EMPILHAMENTO.** Todo painel flutuante desenhado por um
 *    descendente fica preso ao `z-index` deste bloco — subir o número do filho
 *    **não resolve**, porque o teto não é o número. E o `<nav>` é
 *    `overflow-y-auto`, então um painel `absolute` ainda seria **recortado**
 *    mesmo com o empilhamento certo. Por isso **todo** painel daqui (perfil,
 *    flyout de grupo recolhido) é `FloatingPanel`, que renderiza em portal no
 *    `document.body` com `position: fixed`.
 * 2. **O bloco de widgets é `z-sticky` e o `<nav>` é `z-base`.** Os dois já
 *    estiveram em `z-10`, empatados — e no empate quem vem depois no DOM ganha,
 *    então o menu de "VENDO COMO" abria atrás dos itens do menu.
 * 3. **Ícone de destino não repete ícone de modo.** O `SidebarModeToggle` usa
 *    `Layers`/`Briefcase`/`FileText`/`Settings2`; com a sidebar recolhida só o
 *    ícone aparece, e ícone repetido deixa dois controles indistinguíveis.
 *
 * ### FE-396 / IMP-A23 — cor determinística das iniciais
 *
 * O `random_color` do legado (`observer.rb:32-36`) gerava **cor nova a cada
 * render**: a mesma pessoa aparecia de uma cor a cada carregamento de página.
 * O `UserAvatar` da biblioteca deriva o tom do identificador (`avatarTone`), e a
 * cor de alguém passa a ser sempre a mesma.
 */

// `ImpersonationWarning` FOI REMOVIDA daqui (S1 / FE-037).
//
// Ela era o aviso de "Visualizando como" desenhado dentro da barra lateral, e o
// problema não era o desenho: **a barra nasce recolhida** (`sidebar_collapsed`
// default `true`) e **não existe abaixo de `md`**. Na configuração padrão o aviso
// era um ícone de olho; no telefone, nada. O substituto é
// `features/auth/ImpersonationBanner.tsx`, montado no `Layout` — aparece em toda
// tela do console e em toda largura, e não pode ser dispensado.
//
// Manter as duas peças deixaria dois avisos do mesmo estado na mesma viewport, e
// a que some é sempre a que alguém esquece de atualizar.

/**
 * Uma linha de item dentro do grupo.
 *
 * `locked` e `inactive` desenham a mesma coisa — item visível e não clicável —
 * por motivos diferentes, e os dois nascem **vazios** hoje:
 *  - `locked` é o D-90/DEC-15.1: no legado a flag era escrita no item e lida do
 *    grupo, então nunca travou nada. Corrigimos o mecanismo e **não marcamos
 *    ninguém**, porque disponibilidades e cobranças estão vivas em produção;
 *  - `inactive` é o DEC-58/P-090: o mecanismo do item `reports`, que **nunca
 *    existiu** no menu do legado.
 */
function ItemLink({ item, onNavigate, collapsed }: { item: NavItem; onNavigate?: () => void; collapsed?: boolean }) {
    const Icon = item.icon
    const travado = Boolean(item.locked || item.inactive)

    if (travado) {
        return (
            <Tooltip
                content={collapsed ? `${item.label} — indisponível nesta versão` : 'Indisponível nesta versão'}
                side="right"
                className={cn('block', collapsed ? 'flex justify-center' : 'w-full')}
            >
                <span
                    aria-disabled="true"
                    className={cn(
                        'flex cursor-not-allowed items-center rounded-md text-sm text-muted-foreground/50',
                        collapsed ? 'h-10 w-10 shrink-0 justify-center p-0' : 'gap-3 px-3 py-2',
                    )}
                >
                    <Icon aria-hidden="true" className="h-4 w-4 shrink-0" />
                    {!collapsed && (
                        <>
                            <span className="flex-1 truncate">{item.label}</span>
                            <Lock aria-hidden="true" className="h-3.5 w-3.5" />
                        </>
                    )}
                </span>
            </Tooltip>
        )
    }

    const link = (
        <NavLink
            to={item.path}
            onClick={onNavigate}
            className={({ isActive }) => cn(
                'relative flex items-center overflow-hidden rounded-md text-sm transition-colors',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                collapsed ? 'h-10 w-10 shrink-0 justify-center p-0' : 'gap-3 px-3 py-2',
                isActive
                    ? 'bg-accent font-medium text-foreground'
                    : 'text-muted-foreground hover:bg-accent/60 hover:text-foreground',
            )}
        >
            {({ isActive }) => (
                <>
                    {/* Item ativo: barra sólida de ouro à esquerda, sem glow. */}
                    {isActive && <span className="absolute inset-y-0 left-0 w-[3px] rounded-r-full bg-primary" />}
                    <Icon aria-hidden="true" className="h-4 w-4 shrink-0" />
                    {!collapsed && <span className="flex-1 truncate">{item.label}</span>}
                </>
            )}
        </NavLink>
    )

    // Recolhida, o rótulo só existe no tooltip — e ele é em portal, senão o
    // `backdrop-filter` do `.glass-panel` do <aside> o prenderia.
    if (collapsed) {
        return (
            <Tooltip content={item.label} side="right" className={cn('block', collapsed ? 'flex justify-center' : 'w-full')}>
                {link}
            </Tooltip>
        )
    }
    return link
}

/** Grupo recolhido: o painel abre em portal, ancorado no ícone. */
export function Sidebar() {
    const [collapsed, setCollapsed] = useState(() => {
        const saved = localStorage.getItem('sidebar_collapsed')
        return saved ? JSON.parse(saved) : true
    })


    // Publica a largura da trilha para quem precisa se alinhar ao conteudo sem
    // ser descendente dele — hoje a `PaginationPill`, que flutua fixa no rodape.
    // Sem isto ela centralizaria sobre a janela inteira e ficaria deslocada para
    // a direita, por cima da barra lateral.
    useEffect(() => {
        const largura = window.innerWidth < 1024 ? '0px' : collapsed ? '72px' : '18rem'
        document.documentElement.style.setProperty('--sidebar-w', largura)
    }, [collapsed])

    const navigate = useNavigate()
    const location = useLocation()
    const { user, logout } = useAuthStore()
    // FE-396 — o mesmo rótulo que `/profile` e o detalhe da conta usam, da
    // mesma fonte. Três telas escrevendo "Verificação" de três jeitos seria o
    // começo de três vocabulários.
    const nivelDeVerificacao = rotuloDeVerificacao((user as { confiability_level?: string })?.confiability_level)
    const { theme, setTheme } = useTheme()
    const { isOpen, toggleChat } = useChat()
    const { isOg, canImpersonate } = useRole()

    const groups = useNavGroups()
    const { mode } = useSidebarMode()

    const perfilRef = useRef<HTMLButtonElement>(null)
    const [perfilAberto, setPerfilAberto] = useState(false)

    useEffect(() => {
        localStorage.setItem('sidebar_collapsed', JSON.stringify(collapsed))
    }, [collapsed])

    // Mobile: navegar fecha o menu, senão ele cobre a tela que acabou de abrir.
    useEffect(() => {
        if (!collapsed && window.innerWidth < 1024) setCollapsed(true)
    }, [location.pathname])

    const handleLogout = async () => {
        // O DELETE é obrigatório: ele revoga os três tokens na denylist e apaga
        // os cookies HttpOnly. Limpar só o estado local deixaria o cookie vivo,
        // e o próximo acesso a uma rota protegida restauraria a sessão.
        try {
            await authService.logout()
        } catch {
            // Rede fora ou sessão já morta: segue com a limpeza local.
        }
        logout()
        notify.success('Logout realizado com sucesso!')
        navigate('/login')
    }

    const impersonating = useAuthStore((s) => s.impersonating)
    const fecharNoMobile = () => { if (window.innerWidth < 1024) setCollapsed(true) }

    return (
        <>
            {/* Fundo do menu em mobile */}
            {!collapsed && (
                <div
                    className="lg:hidden fixed inset-0 z-drawer-backdrop bg-brand-ink/70 backdrop-blur-sm"
                    onClick={() => setCollapsed(true)}
                />
            )}

            <aside
                className={cn(
                    'fixed inset-y-0 left-0 z-drawer flex h-full shrink-0 flex-col transition-all duration-300 ease-[cubic-bezier(0.25,0.1,0.25,1)] lg:relative lg:translate-x-0',
                    'glass-panel border-r-0 shadow-e2',
                    // **Um inset só, decidido aqui.** Recolhida, a trilha tinha padding
                    // em três níveis diferentes — cabeçalho 8 px, nav 8 px, rodapé 12 px —
                    // e o bloco de widgets fora do eixo. Padding sobre padding em
                    // elementos irmãos é o que fazia a barra parecer torta: cada bloco
                    // centralizava dentro de uma largura diferente.
                    collapsed ? 'w-[72px] px-2 -translate-x-full' : 'w-72 translate-x-0',
                )}
            >
                {/* Cabeçalho: marca e recolher */}
                <div className={cn(
                    'relative z-10 flex h-20 shrink-0 items-center transition-all duration-300',
                    collapsed ? 'justify-center' : 'justify-between px-6',
                )}>
                    <div className="shrink-0 transition-all duration-300">
                        {collapsed ? (
                            <Logo variant="symbol" height={20} />
                        ) : (
                            <Link to="/" className="flex items-center transition-opacity hover:opacity-80" aria-label="Safegold">
                                <Logo variant="full" height={22} />
                            </Link>
                        )}
                    </div>

                    <div className={cn(
                        'flex shrink-0 items-center overflow-hidden transition-all duration-300',
                        collapsed ? 'ml-0 max-w-0 opacity-0 pointer-events-none' : 'ml-auto max-w-[40px] opacity-100',
                    )}>
                        <Button variant="ghost" size="icon" onClick={() => setCollapsed(true)} aria-label="Recolher menu" className="h-8 w-8">
                            <ChevronLeft className="h-4 w-4" />
                        </Button>
                    </div>
                </div>

                {collapsed && (
                    <Button
                        variant="secondary"
                        size="icon"
                        onClick={() => setCollapsed(false)}
                        aria-label="Expandir menu"
                        className="absolute -right-4 top-6 z-sticky hidden h-8 w-8 rounded-full shadow-e1 lg:flex"
                    >
                        <ChevronRight className="h-4 w-4" />
                    </Button>
                )}

                {/* Widgets: impersonação e modo. `z-sticky` é o que impede o
                    painel deles de abrir atrás do <nav> (armadilha 2). */}
                <div className={cn('relative z-sticky space-y-3', collapsed ? 'flex flex-col items-center' : 'px-4')}>
                    {/* **Sem o `!collapsed`, e de proposito.** O cartao ja sabe se
                        desenhar recolhido (icone so, com o painel ancorado ao
                        lado — `ImpersonateSelector.tsx:102,138`); o que faltava
                        era deixa-lo aparecer. Enquanto ele so existia expandido
                        e a barra nascia RECOLHIDA, o recurso nao tinha porta na
                        configuracao padrao — era o FE-036, e a solucao de entao
                        foi duplicar o item no menu do usuario. O usuario pediu o
                        item de volta para fora do menu (26/08/2026), entao a
                        porta passa a ser esta, unica e valida nos dois estados.
                        A SAIDA da impersonacao nao depende daqui: o
                        `ImpersonationBanner` e global (`Layout.tsx:69`). */}
                    {canImpersonate && !impersonating && <ImpersonateSelector collapsed={collapsed} />}
                    {isOg && <SidebarModeToggle collapsed={collapsed} />}
                    {/* O ai9 não tem topbar: seletor de projeto e busca vivem
                        aqui. O título e o chip de usuário que a barra também
                        carregava não vieram — já existem no `PageHeader` de cada
                        tela e no cartão do rodapé. */}
                    {!collapsed && <ProjectSelector />}
                    <SidebarSearch collapsed={collapsed} onNavigate={fecharNoMobile} />
                </div>

                {/* Os grupos */}
                <nav
                    aria-label="Navegação do console"
                    className={cn(
                        'z-base flex flex-1 flex-col overflow-y-auto custom-scrollbar py-2',
                        collapsed ? 'items-center gap-1 scrollbar-none' : 'gap-0.5 px-3',
                    )}
                >
                    {groups.map((group) => {
                        const Icon = group.icon
                        // Link direto: grupo sem itens (o `dash`) ou grupo que
                        // POR DESENHO tem um item só (`linkToSingleItem`).
                        // Nunca deduzido de `items.length === 1` — ver a nota do
                        // campo em `consoleNavigation.tsx`.
                        const destino = group.path ?? (group.linkToSingleItem ? group.items[0]?.path : null)

                        if (destino) {
                            const ativo = location.pathname.startsWith(destino)
                            const conteudo = (
                                <NavLink
                                    to={destino}
                                    onClick={fecharNoMobile}
                                    className={cn(
                                        'relative flex items-center overflow-hidden rounded-md transition-colors',
                                        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                                        collapsed ? 'h-10 w-10 shrink-0 justify-center p-0' : 'gap-3 px-3 py-2.5',
                                        ativo ? 'bg-accent font-medium text-foreground' : 'text-muted-foreground hover:bg-accent/60 hover:text-foreground',
                                    )}
                                >
                                    {ativo && <span className="absolute inset-y-0 left-0 w-[3px] rounded-r-full bg-primary" />}
                                    <Icon aria-hidden="true" className="h-5 w-5 shrink-0" />
                                    {!collapsed && <span className="flex-1 truncate text-sm">{group.title}</span>}
                                </NavLink>
                            )
                            return (
                                <Tooltip key={group.id} content={group.title} side="right" disabled={!collapsed} className={cn('block', collapsed ? 'flex justify-center' : 'w-full')}>
                                    {conteudo}
                                </Tooltip>
                            )
                        }

                        // --- Menu PLANO -------------------------------------------------
                        // O acordeão saiu: com o modo filtrando por grupo, abrir e
                        // fechar seção virou trabalho sem ganho — o usuário já
                        // escolheu o contexto no seletor. Os itens do grupo entram
                        // direto na lista.
                        //
                        // O rótulo é estático e não interativo. No modo "Tudo" ele
                        // orienta a leitura de uma lista longa; recolhida, some (só
                        // ícones cabem) e a separação fica por um traço.
                        return (
                            <div key={group.id} className="flex flex-col">
                                {/* O rótulo de seção só existe no modo "Tudo".
                                    Nos demais, o seletor logo acima já mostra o
                                    nome do contexto — repetir "CADASTRO" a dois
                                    centímetros de "MODO: Cadastro" não informa
                                    nada e ainda encurta a lista útil. */}
                                {!collapsed && mode === 'all' && (
                                    <span className="px-3 pb-1 pt-3 text-[0.68rem] font-semibold uppercase tracking-[0.08em] text-muted-foreground/70">
                                        {group.title}
                                    </span>
                                )}
                                {collapsed && mode === 'all' && <span aria-hidden="true" className="my-1 h-px w-6 bg-border" />}
                                {group.items.map((item) => (
                                    <ItemLink key={item.path} item={item} onNavigate={fecharNoMobile} collapsed={collapsed} />
                                ))}
                            </div>
                        )
                    })}
                </nav>

                {/* Rodapé: modo agente e o cartão do usuário */}
                <div className={cn(
                    'z-sticky mt-auto flex flex-col gap-2 border-t border-border bg-muted/30 py-3',
                    // Recolhida, o inset horizontal e do `aside` — ver a nota la em cima.
                    // Este bloco tinha `p-3` (12 px) contra os 8 px do cabecalho e do nav:
                    // tres valores de inset na mesma trilha.
                    collapsed ? 'items-center' : 'px-3',
                )}>
                    <div
                        role="button"
                        tabIndex={0}
                        onClick={toggleChat}
                        onKeyDown={(e) => e.key === 'Enter' && toggleChat()}
                        className={cn(
                            'flex cursor-pointer items-center overflow-hidden rounded-md border transition-colors',
                            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                            // Recolhido, o MESMO quadrado de 40 px dos itens do menu. Com
                            // `w-full p-2.5` ele ocupava os 54 px da trilha e encostava o
                            // ícone à esquerda: centro em 29 contra 36 de todo o resto.
                            collapsed ? 'h-10 w-10 shrink-0 justify-center p-0' : 'w-full p-2.5',
                            isOpen
                                ? 'border-primary bg-accent text-foreground'
                                : 'border-border bg-secondary/40 text-muted-foreground hover:bg-accent hover:text-foreground',
                        )}
                        aria-label="Alternar modo agente"
                    >
                        <MessageCircle className="h-5 w-5 shrink-0" />
                        <div className={cn(
                            'flex items-center justify-between overflow-hidden whitespace-nowrap transition-all duration-300',
                            collapsed ? 'ml-0 max-w-0 opacity-0' : 'ml-3 max-w-[200px] flex-1 opacity-100',
                        )}>
                            <span className="text-sm font-medium">Modo agente</span>
                            <Switch checked={isOpen} className="pointer-events-none shrink-0" />
                        </div>
                    </div>

                    {/* O cartão de perfil não é botão visual: `<button>` cru
                        tokenizado, como manda o §5.4.3. */}
                    <button
                        ref={perfilRef}
                        type="button"
                        onClick={() => setPerfilAberto((v) => !v)}
                        aria-haspopup="menu"
                        aria-expanded={perfilAberto}
                        aria-label="Menu do usuário"
                        className="flex w-full items-center overflow-hidden rounded-md border border-transparent p-2 transition-colors hover:border-border hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                        {/* FE-396 / IMP-A23: o tom vem do identificador, não de
                            um gerador aleatório a cada render. */}
                        <UserAvatar
                            name={user?.name}
                            email={user?.email}
                            src={user?.avatar_url}
                            colorKey={user?.id ?? user?.email}
                            size={36}
                            className="shrink-0"
                        />
                        <div className={cn(
                            'overflow-hidden whitespace-nowrap text-left transition-all duration-300',
                            collapsed ? 'ml-0 max-w-0 opacity-0' : 'ml-3 max-w-[200px] flex-1 opacity-100',
                        )}>
                            <p className="truncate text-sm font-medium text-foreground">
                                {user?.name?.split(' ')[0] || user?.email || 'Usuário'}
                            </p>
                            <p className="truncate text-xs uppercase tracking-wider text-muted-foreground">
                                {user?.user_type || 'Membro'}
                            </p>
                            {/* **FE-396 — o nível de verificação, aqui também.**
                                A DEC-74 manda replicar o indicador, e ele só
                                existia em `/profile` e no detalhe da conta: o
                                lugar onde a pessoa passa o dia todo não o
                                mostrava. É o que diz se ela consegue receber um
                                código de acesso — descobrir isso na hora de
                                entrar é tarde. */}
                            {nivelDeVerificacao && (
                                <p className="truncate text-[0.65rem] text-muted-foreground">
                                    Verificação: {nivelDeVerificacao}
                                </p>
                            )}
                        </div>
                    </button>

                    {/* Portal, não `absolute`: ver a armadilha 1 no topo. */}
                    <FloatingPanel
                        open={perfilAberto}
                        anchorRef={perfilRef as React.RefObject<HTMLElement>}
                        onDismiss={() => setPerfilAberto(false)}
                        side="top"
                        matchWidth={false}
                        className="min-w-[14rem] p-1.5"
                        role="menu"
                    >
                        <div className="mb-1 border-b border-border px-3 py-2">
                            <p className="truncate text-sm font-semibold text-popover-foreground">{user?.name}</p>
                            <p className="truncate text-xs text-muted-foreground">{user?.email}</p>
                        </div>

                        <button
                            type="button"
                            onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
                            className="flex w-full items-center gap-2.5 rounded-md px-3 py-2 text-sm text-popover-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            {theme === 'dark' ? <Moon className="h-4 w-4" /> : <Sun className="h-4 w-4" />}
                            <span>Tema {theme === 'dark' ? 'Escuro' : 'Claro'}</span>
                        </button>

                        <button
                            type="button"
                            className="flex w-full items-center gap-2.5 rounded-md px-3 py-2 text-sm text-popover-foreground transition-colors hover:bg-accent hover:text-accent-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            <Bell className="h-4 w-4" />
                            <span>Notificações</span>
                        </button>

                        <div className="my-1 h-px bg-border" />

                        <Link
                            to="/profile"
                            onClick={() => setPerfilAberto(false)}
                            className="flex items-center gap-2.5 rounded-md px-3 py-2 text-sm text-popover-foreground transition-colors hover:bg-accent hover:text-accent-foreground"
                        >
                            <User className="h-4 w-4" /> Meu perfil
                        </Link>

                        <div className="my-1 h-px bg-border" />

                        <button
                            type="button"
                            onClick={handleLogout}
                            className="flex w-full items-center gap-2.5 rounded-md px-3 py-2 text-sm text-destructive transition-colors hover:bg-destructive/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                        >
                            <LogOut className="h-4 w-4" /> Sair
                        </button>
                    </FloatingPanel>
                </div>

                {/*
                  **FE-335 / FE-395 — o rodapé do menu.**

                  O legado fechava a barra com a descrição do produto e os dois
                  links de contrato. Nada disso existia no console: `grep -rn
                  'termos-de-uso' src` não achava um consumidor, e o que havia
                  era só o construtor da URL no backend.

                  Não é enfeite. Os dois contratos são os que o usuário aceita
                  para usar o sistema (DEC-66, e a aba "Contratos e aceites" do
                  perfil registra o aceite): sem um caminho para RELER o que se
                  aceitou, o aceite fica sem lastro. O rodapé é o lugar onde
                  todo produto o coloca, e é onde o legado o tinha.

                  Some quando a barra está recolhida — texto de 11px espremido
                  em 64px vira ruído, e o link continua alcançável abrindo a
                  barra.
                */}
                {!collapsed && (
                    <div className="border-t border-border px-3 py-2.5">
                        <p className="mb-1.5 text-[0.65rem] leading-snug text-muted-foreground">
                            Gestão de crédito, risco e recebíveis.
                        </p>
                        <nav aria-label="Contratos" className="flex flex-wrap gap-x-2 gap-y-0.5">
                            <Link
                                to="/contract/termos-de-uso"
                                className="text-[0.65rem] text-muted-foreground underline-offset-2 transition-colors hover:text-foreground hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            >
                                Termos de uso
                            </Link>
                            <span aria-hidden className="text-[0.65rem] text-muted-foreground">·</span>
                            <Link
                                to="/contract/politicas-de-privacidade"
                                className="text-[0.65rem] text-muted-foreground underline-offset-2 transition-colors hover:text-foreground hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                            >
                                Políticas de privacidade
                            </Link>
                        </nav>
                    </div>
                )}
            </aside>

            {/* Abrir o menu em mobile */}
            {collapsed && (
                <Button
                    variant="secondary"
                    size="icon"
                    onClick={() => setCollapsed(false)}
                    aria-label="Abrir menu"
                    className="fixed left-4 top-3 z-sticky h-10 w-10 lg:hidden"
                >
                    <Menu className="h-5 w-5" />
                </Button>
            )}
        </>
    )
}
