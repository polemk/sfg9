import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { BookOpen, ChevronRight, FolderPlus, Plus, Trash2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { AsyncSection } from '@/components/ui/AsyncSection'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { helpAdminApi, type HelpCategory, type HelpGroup } from '@/lib/api/help'
import { HelpItemEditor } from '@/components/help/HelpItemEditor'
import { cn } from '@/lib/utils'

/**
 * A Central de ajuda administrativa — `/help/items` (FE-365).
 *
 * Árvore **Grupo → Categoria → Item**, com criação, renomeação inline e
 * exclusão em cada nível. Dois defeitos observáveis do legado morrem aqui:
 *
 * **(a) O estado vazio nunca aparecia.** O legado chamava `setEmpty(false)` nos
 * **dois** ramos do `if` — a tela vazia ficava simplesmente em branco, e quem
 * abria a central pela primeira vez não sabia se estava vazia ou quebrada.
 *
 * **(b) O `focusout` de 200 ms.** A edição inline tinha um temporizador que
 * **revertia** a alteração, competindo com o Enter: renomear e clicar fora
 * perdia a edição — uma corrida observável, que às vezes funcionava. Aqui o
 * resultado é **determinístico e sem temporizador**: `blur` e `Enter` fazem a
 * mesma coisa (gravar), `Escape` cancela. Não há caminho em que a alteração
 * suma sozinha.
 *
 * **A confirmação de exclusão vem do SERVIDOR** (BE-357 / BE-360): a contagem
 * exata da subárvore é uma chamada, não um texto fixo no JS.
 */
export function HelpCenterPage() {
  const queryClient = useQueryClient()
  const [categoriaSelecionada, setCategoriaSelecionada] = useState<HelpCategory | null>(null)
  const [novoGrupo, setNovoGrupo] = useState('')
  const [novaCategoria, setNovaCategoria] = useState<{ groupId: string; title: string } | null>(null)
  const [aExcluir, setAExcluir] = useState<
    { tipo: 'group' | 'category'; id: string; nome: string } | null
  >(null)

  const arvore = useQuery({ queryKey: ['help', 'tree'], queryFn: () => helpAdminApi.tree() })

  const invalidar = () => {
    queryClient.invalidateQueries({ queryKey: ['help'] })
    queryClient.invalidateQueries({ queryKey: ['faq'] })
  }

  const falhou = (erro: any, padrao: string) =>
    notify.error(erro?.response?.data?.message ?? padrao)

  const criarGrupo = useMutation({
    mutationFn: (title: string) => helpAdminApi.createGroup({ title }),
    onSuccess: () => {
      setNovoGrupo('')
      invalidar()
      notify.success('Grupo criado.')
    },
    onError: (e) => falhou(e, 'Não foi possível criar o grupo.'),
  })

  const renomearGrupo = useMutation({
    mutationFn: ({ id, title }: { id: string; title: string }) => helpAdminApi.updateGroup(id, { title }),
    onSuccess: invalidar,
    onError: (e) => falhou(e, 'Não foi possível renomear o grupo.'),
  })

  const criarCategoria = useMutation({
    mutationFn: ({ groupId, title }: { groupId: string; title: string }) =>
      helpAdminApi.createCategory({ help_group_id: groupId, title }),
    onSuccess: () => {
      setNovaCategoria(null)
      invalidar()
      notify.success('Categoria criada.')
    },
    onError: (e) => falhou(e, 'Não foi possível criar a categoria.'),
  })

  const renomearCategoria = useMutation({
    mutationFn: ({ id, title }: { id: string; title: string }) =>
      helpAdminApi.updateCategory(id, { title }),
    onSuccess: invalidar,
    onError: (e) => falhou(e, 'Não foi possível renomear a categoria.'),
  })

  // A contagem da subárvore, buscada quando o diálogo abre.
  const impacto = useQuery({
    queryKey: ['help', 'impact', aExcluir?.tipo, aExcluir?.id],
    queryFn: () =>
      aExcluir!.tipo === 'group'
        ? helpAdminApi.groupImpact(aExcluir!.id)
        : helpAdminApi.categoryImpact(aExcluir!.id),
    enabled: aExcluir != null,
  })

  const excluir = useMutation({
    mutationFn: () =>
      aExcluir!.tipo === 'group'
        ? helpAdminApi.removeGroup(aExcluir!.id)
        : helpAdminApi.removeCategory(aExcluir!.id),
    onSuccess: (resposta) => {
      const d = resposta.deleted
      notify.success(
        aExcluir?.tipo === 'group'
          ? `Grupo removido, com ${d.categories} categorias e ${d.items} itens.`
          : `Categoria removida, com ${d.items} itens.`,
      )
      if (aExcluir?.tipo === 'category' && categoriaSelecionada?.id === aExcluir.id) {
        setCategoriaSelecionada(null)
      }
      setAExcluir(null)
      invalidar()
    },
    onError: (e) => falhou(e, 'Não foi possível excluir.'),
  })

  return (
    // `pt-6` porque estas três telas montam o próprio cabeçalho em vez de usar o
    // `PageHeader`, que já traz esse respiro. Sem ele o título encostava na barra
    // do telefone enquanto o resto do console tinha 24 px de folga — a diferença
    // aparece de imediato ao navegar entre uma tela e outra.
    <div className="space-y-6 pt-6">
      {/* `items-start`, não `items-center`: num 390 a descrição quebra em duas ou
          três linhas e o ícone centralizado descia para o meio do parágrafo — lido
          como um desenho solto na margem esquerda, longe do título a que pertence.
          Só aparece no telefone: no desktop a descrição cabe numa linha. */}
      <header className="flex items-start gap-3">
        <BookOpen aria-hidden="true" className="mt-1 h-6 w-6 shrink-0 text-primary" />
        <div>
          <h1 className="font-title text-2xl font-semibold text-foreground">Central de ajuda</h1>
          <p className="text-sm text-muted-foreground">
            Grupos, categorias e itens que aparecem na tela de Ajuda. Excluir não tem lixeira — a
            confirmação diz exatamente quanto se perde.
          </p>
        </div>
      </header>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,22rem)_1fr]">
        <Card>
          <CardHeader>
            <CardTitle>Árvore</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <AsyncSection
              loading={arvore.isLoading}
              error={arvore.error}
              data={arvore.data}
              onRetry={() => arvore.refetch()}
              size="inline"
              // (a) — o estado vazio agora APARECE.
              emptyTitle="A central de ajuda está vazia"
              emptyDescription="Crie o primeiro grupo no campo abaixo."
            >
              {(grupos) => (
                <div className="space-y-4">
                  {grupos.map((grupo) => (
                    <GrupoNode
                      key={grupo.id}
                      grupo={grupo}
                      categoriaSelecionadaId={categoriaSelecionada?.id ?? null}
                      onSelecionarCategoria={setCategoriaSelecionada}
                      onRenomearGrupo={(title) => renomearGrupo.mutate({ id: grupo.id, title })}
                      onRenomearCategoria={(id, title) => renomearCategoria.mutate({ id, title })}
                      onExcluirGrupo={() => setAExcluir({ tipo: 'group', id: grupo.id, nome: grupo.title })}
                      onExcluirCategoria={(c) =>
                        setAExcluir({ tipo: 'category', id: c.id, nome: c.title })
                      }
                      novaCategoria={novaCategoria?.groupId === grupo.id ? novaCategoria.title : null}
                      onNovaCategoria={(title) => setNovaCategoria({ groupId: grupo.id, title })}
                      onConfirmarCategoria={() =>
                        novaCategoria?.title.trim() &&
                        criarCategoria.mutate({ groupId: grupo.id, title: novaCategoria.title.trim() })
                      }
                      onCancelarCategoria={() => setNovaCategoria(null)}
                    />
                  ))}
                </div>
              )}
            </AsyncSection>

            <form
              className="flex gap-2 border-t border-border pt-4"
              onSubmit={(e) => {
                e.preventDefault()
                if (novoGrupo.trim()) criarGrupo.mutate(novoGrupo.trim())
              }}
            >
              <Input
                value={novoGrupo}
                onChange={(e) => setNovoGrupo(e.target.value)}
                placeholder="Novo grupo…"
                aria-label="Título do novo grupo"
              />
              <Button type="submit" size="sm" disabled={!novoGrupo.trim()} loading={criarGrupo.isPending}>
                <FolderPlus aria-hidden="true" className="h-4 w-4" />
                Criar
              </Button>
            </form>
          </CardContent>
        </Card>

        <HelpItemEditor categoria={categoriaSelecionada} onChanged={invalidar} />
      </div>

      <Dialog open={aExcluir != null} onOpenChange={(aberto) => !aberto && setAExcluir(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Excluir “{aExcluir?.nome}”?</DialogTitle>
            <DialogDescription asChild>
              <div className="space-y-2 text-sm text-muted-foreground">
                {impacto.isLoading ? (
                  <p>Calculando o que será perdido…</p>
                ) : (
                  <p>
                    Serão apagados{' '}
                    {aExcluir?.tipo === 'group' && (
                      <>
                        <span className="font-numeric text-foreground">{impacto.data?.categories ?? 0}</span>{' '}
                        {impacto.data?.categories === 1 ? 'categoria' : 'categorias'} e{' '}
                      </>
                    )}
                    <span className="font-numeric text-foreground">{impacto.data?.items ?? 0}</span>{' '}
                    {impacto.data?.items === 1 ? 'item' : 'itens'}.
                  </p>
                )}
                <p>
                  <strong className="text-foreground">Não há lixeira.</strong> Depois de excluir, o
                  conteúdo não volta.
                </p>
              </div>
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setAExcluir(null)}>
              Cancelar
            </Button>
            <Button
              variant="destructive"
              loading={excluir.isPending}
              disabled={impacto.isLoading}
              onClick={() => excluir.mutate()}
            >
              <Trash2 aria-hidden="true" className="h-4 w-4" />
              Excluir mesmo assim
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

function GrupoNode({
  grupo,
  categoriaSelecionadaId,
  onSelecionarCategoria,
  onRenomearGrupo,
  onRenomearCategoria,
  onExcluirGrupo,
  onExcluirCategoria,
  novaCategoria,
  onNovaCategoria,
  onConfirmarCategoria,
  onCancelarCategoria,
}: {
  grupo: HelpGroup
  categoriaSelecionadaId: string | null
  onSelecionarCategoria: (c: HelpCategory) => void
  onRenomearGrupo: (title: string) => void
  onRenomearCategoria: (id: string, title: string) => void
  onExcluirGrupo: () => void
  onExcluirCategoria: (c: HelpCategory) => void
  novaCategoria: string | null
  onNovaCategoria: (title: string) => void
  onConfirmarCategoria: () => void
  onCancelarCategoria: () => void
}) {
  return (
    <div>
      <div className="flex items-center gap-1">
        <InlineEditable value={grupo.title} onCommit={onRenomearGrupo} className="flex-1 font-medium" />
        <Button variant="ghost" size="icon" aria-label={`Nova categoria em ${grupo.title}`} onClick={() => onNovaCategoria('')}>
          <Plus aria-hidden="true" className="h-4 w-4" />
        </Button>
        <Button variant="ghost" size="icon" aria-label={`Excluir grupo ${grupo.title}`} onClick={onExcluirGrupo}>
          <Trash2 aria-hidden="true" className="h-4 w-4" />
        </Button>
      </div>

      {/* A linha da categoria NÃO é um `<button>` embrulhando a edição inline.
          `InlineEditable` vira um `<input>` quando está editando, e `<input>`
          dentro de `<button>` é HTML inválido: a barra de espaço digitada no
          nome ativaria o botão e trocaria de categoria no meio da renomeação.
          Aqui a linha é um `<li>` comum — o clique simples seleciona e o duplo
          abre a edição: dois gestos, um alvo. */}
      <ul className="mt-1 space-y-0.5 pl-3">
        {(grupo.categories ?? []).map((c) => (
          <li
            key={c.id}
            className={cn(
              'flex items-center gap-1 rounded-md px-1.5 py-1 text-sm transition-colors',
              categoriaSelecionadaId === c.id
                ? 'bg-accent text-accent-foreground'
                : 'text-foreground hover:bg-accent hover:text-accent-foreground',
            )}
          >
            <ChevronRight aria-hidden="true" className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
            <InlineEditable
              value={c.title}
              onSelect={() => onSelecionarCategoria(c)}
              onCommit={(title) => onRenomearCategoria(c.id, title)}
              className="min-w-0 flex-1"
              titulo={`Abrir ${c.title}. Clique duas vezes para renomear.`}
            />
            <span className="font-numeric text-xs text-muted-foreground">{c.items_count}</span>
            <Button variant="ghost" size="icon" aria-label={`Excluir categoria ${c.title}`} onClick={() => onExcluirCategoria(c)}>
              <Trash2 aria-hidden="true" className="h-4 w-4" />
            </Button>
          </li>
        ))}

        {novaCategoria !== null && (
          <li>
            <form
              className="flex gap-1 pl-1"
              onSubmit={(e) => {
                e.preventDefault()
                onConfirmarCategoria()
              }}
            >
              <Input
                autoFocus
                value={novaCategoria}
                onChange={(e) => onNovaCategoria(e.target.value)}
                onKeyDown={(e) => e.key === 'Escape' && onCancelarCategoria()}
                placeholder="Nova categoria…"
                aria-label="Título da nova categoria"
              />
              <Button type="submit" size="sm" disabled={!novaCategoria.trim()}>
                Criar
              </Button>
            </form>
          </li>
        )}
      </ul>
    </div>
  )
}

/**
 * Renomeação inline **determinística** (FE-365 (b)).
 *
 * `Enter` e `blur` gravam; `Escape` descarta. **Não existe temporizador.** No
 * legado um `focusout` de 200 ms revertia a edição competindo com o `Enter`, e
 * o resultado dependia de qual dos dois chegasse antes — uma corrida que às
 * vezes funcionava, que é o pior tipo de defeito de interface.
 */
function InlineEditable({
  value,
  onCommit,
  onSelect,
  titulo = 'Clique duas vezes para renomear',
  className,
}: {
  value: string
  onCommit: (novo: string) => void
  /** Clique simples. Ausente = o rótulo só edita, não seleciona nada. */
  onSelect?: () => void
  titulo?: string
  className?: string
}) {
  const [editando, setEditando] = useState(false)
  const [rascunho, setRascunho] = useState(value)

  const gravar = () => {
    setEditando(false)
    const limpo = rascunho.trim()
    if (limpo && limpo !== value) onCommit(limpo)
    else setRascunho(value)
  }

  if (!editando) {
    return (
      <span
        role="button"
        tabIndex={0}
        title={titulo}
        onClick={onSelect}
        onDoubleClick={() => {
          setRascunho(value)
          setEditando(true)
        }}
        onKeyDown={(e) => {
          // `F2` é o gesto de renomear que o usuário já conhece de gerenciador
          // de arquivos; `Enter`/`Espaço` seguem o papel de botão e selecionam.
          if (e.key === 'F2') {
            setRascunho(value)
            setEditando(true)
          }
          if ((e.key === 'Enter' || e.key === ' ') && onSelect) {
            e.preventDefault()
            onSelect()
          }
        }}
        // `leading-[2.75rem]` dá 44 px de altura ao rótulo sem virar flex (o
        // `truncate` depende de o elemento continuar `block`). Este rótulo é o
        // que SELECIONA a categoria na árvore, e vinha com 20 px — a altura da
        // linha de texto (§5.4.8, critério 1). No desktop volta ao normal.
        className={cn(
          'block truncate rounded-sm px-1 leading-[2.75rem] md:leading-normal',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
          className,
        )}
      >
        {value}
      </span>
    )
  }

  return (
    <input
      autoFocus
      value={rascunho}
      aria-label={`Renomear ${value}`}
      onChange={(e) => setRascunho(e.target.value)}
      onBlur={gravar}
      onKeyDown={(e) => {
        if (e.key === 'Enter') {
          e.preventDefault()
          gravar()
        }
        if (e.key === 'Escape') {
          setRascunho(value)
          setEditando(false)
        }
      }}
      className={cn(
        'min-w-0 rounded-sm border border-input bg-background px-1 py-0.5 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
        className,
      )}
    />
  )
}

export default HelpCenterPage
