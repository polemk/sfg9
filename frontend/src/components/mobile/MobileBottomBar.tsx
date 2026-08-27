import { useState } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { MoreHorizontal } from 'lucide-react'
import { cn } from '@/lib/utils'
import { useNavItems } from '@/hooks/useNavItems'
import { MobileNavSheet } from './MobileNavSheet'

/**
 * **Navegação primária no telefone** — a barra de abas do rodapé (DEC-100).
 *
 * Três coisas foram consertadas aqui, e cada uma tinha um sintoma real:
 *
 * 1. **Aba sem rótulo.** Era só ícone. Ícone sozinho é adivinhação — "Operações" e
 *    "Operações estruturadas" viram o mesmo desenho, e este produto tem os dois. Toda barra
 *    de abas nativa (iOS e Android) rotula; a nossa passa a rotular.
 * 2. **Inativo em `opacity-40`.** Opacidade sobre o fundo derruba o contraste abaixo do
 *    mínimo legível e afeta o ícone E o texto de uma vez. Inativo agora é
 *    `text-muted-foreground`, que é o token feito para isso e já nasce conferido nos dois
 *    modos.
 * 3. **Sem `safe-area-inset-bottom`.** Instalado como PWA (`display: standalone`, NEW-003) o
 *    navegador some, e o indicador de início do iPhone passa a dividir espaço com a barra:
 *    a última aba fica embaixo dele. Só aparece no aparelho — nunca no DevTools.
 *
 * A rota ativa é anunciada por `aria-current="page"`, não só por cor: quem navega por leitor
 * de tela não enxerga o ouro.
 *
 * ### O quinto lugar é "Mais", e isso conserta um defeito de alcance
 *
 * A barra mostrava `useNavItems().slice(0, 5)` **e nada mais**. No telefone a `Sidebar` é
 * `hidden md:block` e a folha do avatar só tem perfil/tema/sair, então os outros ~35 destinos
 * do console — Projetos, Empresas, Portadores, Limites, Contratos, Central de ajuda — não
 * tinham **nenhum** caminho: existiam, com rota montada, e o polegar não chegava neles. Trocar
 * o modo no cabeçalho apenas trocava **quais** cinco apareciam.
 *
 * Agora são **quatro destinos + "Mais"**, e "Mais" abre a `MobileNavSheet` com o menu inteiro.
 * É o padrão nativo de iOS e Android, e mantém o teto de cinco abas da §5.4.8 — que existe por
 * medida, não por gosto: a sexta aba num 390 derruba o alvo abaixo de 44 px.
 *
 * ### O rótulo cabe INTEIRO, em até três linhas
 *
 * Com `truncate` numa faixa de ~70 px, "Painel de Disponibilidade" virava "Painel de D…" e
 * "Disponibilidades" virava "Disponibili…" — e os dois usam o **mesmo** `CalendarRange`. Duas
 * abas com o mesmo desenho e o rótulo cortado antes de divergir são, na prática, o "ícone sem
 * rótulo" que a §5.4.8 proíbe, e este produto tem esse par no menu de hoje.
 *
 * A medida foi feita: com `line-clamp-2` a 10 px, os dois rótulos mais longos do console
 * (`scrollHeight` 38 contra `clientHeight` 25) **continuavam cortados**. A 9 px em até três
 * linhas eles cabem por inteiro. Nove pixels é pequeno para texto corrido e é o tamanho certo
 * para rótulo de aba — o iOS usa 10 pt na dele. Todas as abas reservam a mesma altura, então
 * a barra não desalinha quando um rótulo usa uma linha e o vizinho usa três.
 *
 * A quebra é `hyphens-auto` + `break-words`, e não `overflow-wrap: anywhere`: o
 * `<html lang="pt-BR">` dá ao navegador o dicionário de hifenização, então
 * "Renegociações" quebra em sílaba ("Renego-/ciações") em vez de no meio da letra
 * ("Renegociaçõ/es"). Onde não houver dicionário, o `break-words` continua sendo a
 * rede de segurança — o que não pode acontecer é a palavra estourar a aba vizinha.
 */
export function MobileBottomBar() {
    const location = useLocation()
    const [menuAberto, setMenuAberto] = useState(false)
    // Cinco é o teto de uma barra de abas: acima disso o alvo de toque encolhe abaixo dos
    // 44 px e o rótulo deixa de caber num 390 de largura. O quinto lugar é "Mais" — sem ele
    // o resto do console fica inalcançável no telefone.
    const todos = useNavItems()
    const items = todos.slice(0, 4)
    // "Mais" só aparece quando há o que mostrar além das quatro primeiras. Com um console
    // pequeno (papel restrito, projeto ausente) a barra volta a ser só destinos.
    const temMais = todos.length > items.length

    const isActive = (path: string) =>
        location.pathname === path || location.pathname.startsWith(path + '/')

    // Nenhuma das quatro abas cobre a rota atual: "Mais" é quem leva até ela, então é ele
    // que fica aceso. Barra sem nenhum item ativo faz o usuário achar que saiu do app.
    const maisAtivo = temMais && !items.some((i) => isActive(i.path))

    return (
        <nav
            aria-label="Navegação principal"
            className={cn(
                'fixed bottom-0 left-0 right-0 z-appbar md:hidden',
                'rounded-t-lg border-t border-border bg-background shadow-e3 px-2',
                'pb-[env(safe-area-inset-bottom)]',
                'animate-in slide-in-from-bottom-full duration-500',
            )}
        >
            {/* 68 px, e não 64: com o rótulo em até três linhas as abas precisam de
                mais dois degraus de altura. O `Layout` já reserva 80 px + inset para
                a barra, então nada de conteúdo passa a ficar escondido — e o FAB do
                `MobilePageLayout`, ancorado em 88 px, continua acima dela. */}
            <ul className="relative flex h-[4.25rem] items-stretch justify-between z-base">
                {items.map((item) => {
                    const Icon = item.icon
                    const active = isActive(item.path)

                    return (
                        // `min-w-0` é o que faz o `truncate` do rótulo funcionar: item de
                        // flex nasce com `min-width: auto` e cresce até caber o texto
                        // inteiro, então "Grupos de Portadores" invadia a aba vizinha em
                        // vez de cortar. Sem isto as cinco abas se sobrepõem num 390.
                        <li key={item.path} className="min-w-0 flex-1">
                            <Link
                                to={item.path}
                                aria-current={active ? 'page' : undefined}
                                className={cn(
                                    'relative flex h-full min-h-[3rem] flex-col items-center justify-center gap-1 px-1',
                                    'transition-colors duration-200',
                                    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-inset',
                                    active ? 'text-primary' : 'text-muted-foreground',
                                )}
                            >
                                <Icon aria-hidden="true" className={cn('h-5 w-5 shrink-0', active && 'scale-110')} />
                                {/* Duas linhas, e só então corta. Numa faixa de ~70 px o
                                    `truncate` de uma linha apagava justamente a parte do
                                    nome que separa "Painel de Disponibilidade" de
                                    "Disponibilidades" — que compartilham o ícone. Como
                                    todas as abas reservam as mesmas duas linhas, a barra
                                    continua alinhada. */}
                                <span className="line-clamp-3 w-full hyphens-auto break-words text-center text-[9px] font-semibold leading-[1.2]">
                                    {item.label}
                                </span>
                                {active && (
                                    <span
                                        aria-hidden="true"
                                        className="absolute inset-x-4 top-0 h-0.5 rounded-full bg-primary"
                                    />
                                )}
                            </Link>
                        </li>
                    )
                })}

                {temMais && (
                    <li className="min-w-0 flex-1">
                        <button
                            type="button"
                            onClick={() => setMenuAberto(true)}
                            aria-haspopup="dialog"
                            aria-expanded={menuAberto}
                            className={cn(
                                'relative flex h-full w-full min-h-[3rem] flex-col items-center justify-center gap-1 px-1',
                                'transition-colors duration-200',
                                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-inset',
                                maisAtivo || menuAberto ? 'text-primary' : 'text-muted-foreground',
                            )}
                        >
                            <MoreHorizontal
                                aria-hidden="true"
                                className={cn('h-5 w-5 shrink-0', (maisAtivo || menuAberto) && 'scale-110')}
                            />
                            <span className="line-clamp-3 w-full text-center text-[9px] font-semibold leading-[1.2]">
                                Mais
                            </span>
                            {maisAtivo && (
                                <span
                                    aria-hidden="true"
                                    className="absolute inset-x-4 top-0 h-0.5 rounded-full bg-primary"
                                />
                            )}
                        </button>
                    </li>
                )}
            </ul>

            {/* Em portal, no `body`: esta `<nav>` é `fixed` com `z-appbar`, e `fixed` + `z`
                cria contexto de empilhamento — a folha renderizada aqui dentro ficaria presa
                atrás do conteúdo (§5.4.4). */}
            <MobileNavSheet open={menuAberto} onOpenChange={setMenuAberto} />
        </nav>
    )
}
