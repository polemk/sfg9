import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Trash2, User } from 'lucide-react'
import { notify } from '@/lib/notify'
import RichTextEditor from '@/components/RichTextEditor'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { EmptyState, LoadingState } from '@/components/ui/States'
import { helpAdminApi, type HelpCategory, type HelpItem } from '@/lib/api/help'
import { formatDateTime } from '@/lib/utils/date'
import { cn } from '@/lib/utils'

/**
 * Formulário e detalhe do item de ajuda (FE-366).
 *
 * Três bugs do legado morrem aqui:
 *
 * **(a) A autoria era reescrita.** `user_id` viajava num campo escondido sempre
 * com o `current_user`, então **editar item de outro autor reescrevia a
 * autoria** — depois da primeira revisão, "quem escreveu isto" não tinha mais
 * resposta. Aqui o campo **não existe no payload**: o servidor preserva o autor
 * e registra quem alterou por último em coluna própria.
 *
 * **(b) O toast dizia "Item criado" também na edição.** Aqui a mensagem sai do
 * modo em que o formulário está.
 *
 * **(c) O avatar de fallback usava `random_color`** e mudava de cor **a cada
 * render** — a mesma pessoa aparecia de uma cor diferente a cada tela. Aqui a
 * cor é derivada do id: determinística, e igual em qualquer lugar do app.
 */
export function HelpItemEditor({
  categoria,
  onChanged,
}: {
  categoria: HelpCategory | null
  onChanged: () => void
}) {
  const queryClient = useQueryClient()
  const [editandoId, setEditandoId] = useState<string | null>(null)
  const [criando, setCriando] = useState(false)
  const [titulo, setTitulo] = useState('')
  const [corpo, setCorpo] = useState('')

  const itens = useQuery({
    queryKey: ['help', 'items', categoria?.id],
    queryFn: () => helpAdminApi.items({ categoryId: categoria!.id, perPage: 100 }),
    enabled: categoria != null,
  })

  /**
   * **O corpo é buscado ao abrir, e o formulário só existe depois que ele
   * chega.**
   *
   * Isto não é otimização, é correção de um defeito achado renderizando: a
   * LISTA administrativa não traz `description_html` (o entity só o expõe com
   * `type: :full`, para a lista não carregar o texto de todos os itens). Abrir
   * o formulário com o item da lista deixava o editor **vazio** — e "Salvar
   * alterações" gravaria um corpo em branco por cima do conteúdo real. O
   * servidor recusaria (BE-352 rejeita corpo vazio), mas o usuário veria um
   * item que perdeu o texto na tela e um erro que não explica nada.
   *
   * `tsc` passava limpo com esse defeito. Só apareceu abrindo a tela.
   */
  const detalhe = useQuery({
    queryKey: ['help', 'item', editandoId],
    queryFn: () => helpAdminApi.getItem(editandoId!),
    enabled: editandoId != null,
  })

  const emEdicao = detalhe.data ?? null

  useEffect(() => {
    if (!detalhe.data) return
    setTitulo(detalhe.data.title)
    setCorpo(detalhe.data.description_html ?? '')
  }, [detalhe.data])

  // Trocar de categoria fecha o formulário: continuar editando um item que não
  // está mais na lista é como se grava conteúdo na categoria errada.
  useEffect(() => {
    setEditandoId(null)
    setCriando(false)
  }, [categoria?.id])

  const abrirNovo = () => {
    setEditandoId(null)
    setCriando(true)
    setTitulo('')
    setCorpo('')
  }

  const abrirEdicao = (item: HelpItem) => {
    setCriando(false)
    setTitulo(item.title)
    // Vazio de propósito até o corpo chegar: preencher com o que a lista tem
    // (nada) e deixar o botão ativo é exatamente o defeito acima.
    setCorpo('')
    setEditandoId(item.id)
  }

  const fechar = () => {
    setEditandoId(null)
    setCriando(false)
  }

  const salvar = useMutation({
    mutationFn: () =>
      emEdicao
        ? helpAdminApi.updateItem(emEdicao.id, { title: titulo, description: corpo })
        : helpAdminApi.createItem({
            help_category_id: categoria!.id,
            title: titulo,
            description: corpo,
          }),
    onSuccess: () => {
      notify.success(emEdicao ? 'Item atualizado.' : 'Item criado.')
      fechar()
      queryClient.invalidateQueries({ queryKey: ['help', 'items'] })
      onChanged()
    },
    onError: (erro: any) =>
      notify.error(erro?.response?.data?.message ?? 'Não foi possível gravar o item.'),
  })

  const excluir = useMutation({
    mutationFn: (id: string) => helpAdminApi.removeItem(id),
    onSuccess: () => {
      notify.success('Item excluído.')
      fechar()
      queryClient.invalidateQueries({ queryKey: ['help', 'items'] })
      onChanged()
    },
    // BE-354 — a falha responde ERRO COM MOTIVO. No legado o ternário era
    // `errors.any? ? :ok : :ok`: excluir falhava e a tela dizia que deu certo.
    onError: (erro: any) =>
      notify.error(erro?.response?.data?.message ?? 'Não foi possível excluir o item.'),
  })

  if (!categoria) {
    return (
      <Card>
        <CardContent className="p-0">
          <EmptyState
            title="Escolha uma categoria"
            description="Selecione uma categoria na árvore para ver e editar os itens dela."
          />
        </CardContent>
      </Card>
    )
  }

  const formularioAberto = criando || editandoId != null
  const carregandoCorpo = editandoId != null && detalhe.isLoading
  const podeSalvar =
    !carregandoCorpo && titulo.trim().length > 0 && corpo.replace(/<[^>]*>/g, '').trim().length > 0

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between gap-3">
        <CardTitle>{categoria.title}</CardTitle>
        {!formularioAberto && (
          <Button size="sm" onClick={abrirNovo}>
            <Plus aria-hidden="true" className="h-4 w-4" />
            Novo item
          </Button>
        )}
      </CardHeader>

      <CardContent className="space-y-4">
        {formularioAberto && carregandoCorpo ? (
          <LoadingState size="inline" label="Carregando o texto do item…" />
        ) : formularioAberto ? (
          <form
            className="space-y-4"
            onSubmit={(e) => {
              e.preventDefault()
              if (podeSalvar) salvar.mutate()
            }}
          >
            <div className="space-y-1.5">
              <Label htmlFor="help-item-title">Título</Label>
              <Input
                id="help-item-title"
                value={titulo}
                onChange={(e) => setTitulo(e.target.value)}
                placeholder="Ex.: Como aceitar os Termos de Uso"
              />
            </div>

            <div className="space-y-1.5">
              <Label>Conteúdo</Label>
              {/* Slate (F-14 / DEC-63). Corpo vazio é recusado pelo servidor
                  (BE-352) — no legado a validação de presença nunca falhava. */}
              <RichTextEditor value={corpo} onChange={setCorpo} placeholder="Escreva a resposta…" />
            </div>

            {emEdicao && (
              <p className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                <AutorChip nome={emEdicao.author?.name ?? 'autor não identificado'} id={emEdicao.author?.id} />
                <span>escreveu este item.</span>
                {emEdicao.last_updated_user && (
                  <span>
                    Última alteração por {emEdicao.last_updated_user.name} em{' '}
                    {formatDateTime(emEdicao.updated_at)}.
                  </span>
                )}
              </p>
            )}

            <div className="flex flex-wrap gap-2">
              <Button type="submit" disabled={!podeSalvar} loading={salvar.isPending}>
                {emEdicao ? 'Salvar alterações' : 'Criar item'}
              </Button>
              <Button type="button" variant="secondary" onClick={fechar}>
                Cancelar
              </Button>
              {emEdicao && (
                <Button
                  type="button"
                  variant="destructive"
                  className="ml-auto"
                  loading={excluir.isPending}
                  onClick={() => excluir.mutate(emEdicao.id)}
                >
                  <Trash2 aria-hidden="true" className="h-4 w-4" />
                  Excluir
                </Button>
              )}
            </div>
          </form>
        ) : (
          <AsyncSection
            loading={itens.isLoading}
            error={itens.error}
            data={itens.data}
            isEmpty={(d) => d.items.length === 0}
            onRetry={() => itens.refetch()}
            size="inline"
            emptyTitle="Nenhum item nesta categoria"
            emptyDescription="Crie o primeiro item pelo botão acima."
          >
            {(pagina) => (
              <ul className="space-y-2">
                {pagina.items.map((item) => (
                  <li key={item.id}>
                    <button
                      type="button"
                      onClick={() => abrirEdicao(item)}
                      className="flex w-full flex-wrap items-center gap-2 rounded-md border border-border bg-card px-4 py-3 text-left transition-colors hover:bg-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      <span className="min-w-0 flex-1 truncate text-sm text-foreground">{item.title}</span>
                      <AutorChip nome={item.author?.name ?? '—'} id={item.author?.id} />
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </AsyncSection>
        )}
      </CardContent>
    </Card>
  )
}

/**
 * (c) — a cor do avatar de fallback é **determinística**.
 *
 * O legado usava `random_color`, sorteada a cada render: a mesma pessoa
 * aparecia de uma cor diferente em cada linha da mesma lista, e a cor deixava
 * de servir para reconhecer alguém — que é a única função dela.
 *
 * Os quatro tons vêm de tokens semânticos, nunca de paleta literal.
 */
const TONS = ['bg-info', 'bg-success', 'bg-warning', 'bg-brand-steel'] as const

function AutorChip({ nome, id }: { nome: string; id?: string }) {
  const semente = id ?? nome
  let soma = 0
  for (let i = 0; i < semente.length; i += 1) soma = (soma + semente.charCodeAt(i)) % 997
  const tom = TONS[soma % TONS.length]

  return (
    <span className="inline-flex items-center gap-1.5 text-xs text-muted-foreground">
      <span
        aria-hidden="true"
        className={cn('flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-semibold text-background', tom)}
      >
        {nome.trim().charAt(0).toUpperCase() || <User className="h-3 w-3" />}
      </span>
      {nome}
    </span>
  )
}
