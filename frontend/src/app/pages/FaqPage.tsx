import { useEffect, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { LifeBuoy } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { SearchInput } from '@/components/ui/SearchInput'
import { AsyncSection } from '@/components/ui/AsyncSection'
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { faqApi, type HelpCategory } from '@/lib/api/help'
import { cn } from '@/lib/utils'

/**
 * A tela de ajuda do usuário final — `/faq` (FE-364).
 *
 * Árvore de grupos e categorias à esquerda, itens da categoria à direita, e uma
 * busca que atravessa o acervo inteiro. Três defeitos observáveis do legado
 * morrem aqui:
 *
 * **(a) `lastQuery = " "` ao trocar de categoria.** O legado punha um espaço no
 * termo ao mudar de categoria; como a busca era `LIKE '% %'`, **itens de título
 * curto sem espaço sumiam** — e ninguém ligava o sintoma à causa. Aqui trocar
 * de categoria **limpa** a busca, e "vazio" é vazio.
 *
 * **(b) Busca no `keyup`, sem debounce.** Era uma requisição por tecla. Aqui é
 * `useDebouncedSearch` (300 ms, o mesmo do app inteiro).
 *
 * **(c) Callback de falha VAZIO.** Falha de rede não mostrava nada: a lista
 * ficava como estava e a pessoa achava que não havia resultado. Aqui o quarto
 * estado (`AsyncSection`) mostra o erro com botão de tentar de novo.
 */
export function FaqPage() {
  const [categoria, setCategoria] = useState<HelpCategory | null>(null)
  const busca = useDebouncedSearch()

  const arvore = useQuery({
    queryKey: ['faq', 'tree'],
    queryFn: () => faqApi.tree(),
  })

  // Seleciona a primeira categoria quando a árvore chega — a tela nunca abre
  // com o painel da direita em branco sem explicação.
  useEffect(() => {
    if (categoria || !arvore.data) return
    const primeira = arvore.data.flatMap((g) => g.categories ?? [])[0]
    if (primeira) setCategoria(primeira)
  }, [arvore.data, categoria])

  const buscando = busca.consulta.length > 0

  const itens = useQuery({
    queryKey: ['faq', 'items', categoria?.id, buscando],
    queryFn: () => faqApi.items(categoria!.id, { perPage: 100 }),
    enabled: !buscando && categoria != null,
  })

  const resultados = useQuery({
    queryKey: ['faq', 'search', busca.consulta],
    queryFn: () => faqApi.search(busca.consulta, { perPage: 50 }),
    enabled: buscando,
  })

  const consulta = buscando ? resultados : itens

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
        <LifeBuoy aria-hidden="true" className="mt-1 h-6 w-6 shrink-0 text-primary" />
        <div>
          <h1 className="font-title text-2xl font-semibold text-foreground">Ajuda</h1>
          <p className="text-sm text-muted-foreground">
            Perguntas frequentes, organizadas por assunto. A busca olha o texto inteiro dos itens.
          </p>
        </div>
      </header>

      <SearchInput
        className="max-w-xl"
        value={busca.termo}
        onValueChange={busca.setTermo}
        onClear={busca.limpar}
        loading={busca.pendente}
        placeholder="Buscar na ajuda…"
      />

      <div className="grid gap-6 lg:grid-cols-[minmax(0,16rem)_1fr]">
        <Card className={cn(buscando && 'opacity-60')}>
          <CardHeader>
            <CardTitle>Assuntos</CardTitle>
          </CardHeader>
          <CardContent>
            <AsyncSection
              loading={arvore.isLoading}
              error={arvore.error}
              data={arvore.data}
              onRetry={() => arvore.refetch()}
              size="inline"
              emptyTitle="Nenhum assunto cadastrado"
              emptyDescription="A central de ajuda ainda está vazia."
            >
              {(grupos) => (
                <nav className="space-y-4">
                  {grupos.map((grupo) => (
                    <div key={grupo.id}>
                      <p className="mb-1.5 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                        {grupo.title}
                      </p>
                      <ul className="space-y-0.5">
                        {(grupo.categories ?? []).map((c) => (
                          <li key={c.id}>
                            <button
                              type="button"
                              onClick={() => {
                                setCategoria(c)
                                // (a) — trocar de categoria LIMPA a busca. No
                                // legado ela virava um espaço, e itens de
                                // título curto sumiam.
                                busca.limpar()
                              }}
                              className={cn(
                                // 44 px de alvo no telefone (§5.4.8, critério 1):
                                // `py-1.5` dava 32, e escolher a categoria é a
                                // única navegação desta tela.
                                'flex w-full min-h-[2.75rem] items-center rounded-md px-2 py-1.5 text-left text-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring md:min-h-0',
                                categoria?.id === c.id && !buscando
                                  ? 'bg-accent text-accent-foreground'
                                  : 'text-foreground hover:bg-accent hover:text-accent-foreground',
                              )}
                            >
                              <span className="flex w-full min-w-0 items-center justify-between gap-2">
                                <span className="truncate">{c.title}</span>
                                <span className="font-numeric text-xs text-muted-foreground">
                                  {c.items_count}
                                </span>
                              </span>
                            </button>
                          </li>
                        ))}
                      </ul>
                    </div>
                  ))}
                </nav>
              )}
            </AsyncSection>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>
              {buscando ? `Resultados para “${busca.consulta}”` : (categoria?.title ?? 'Itens')}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <AsyncSection
              loading={consulta.isLoading}
              error={consulta.error}
              data={consulta.data}
              isEmpty={(d) => d.items.length === 0}
              onRetry={() => consulta.refetch()}
              size="inline"
              emptyTitle={buscando ? 'Nada encontrado' : 'Nenhum item neste assunto'}
              emptyDescription={
                buscando ? 'Tente outras palavras.' : 'Escolha outro assunto na lista ao lado.'
              }
            >
              {(pagina) => (
                <Accordion type="multiple" className="w-full">
                  {pagina.items.map((item) => (
                    <AccordionItem key={item.id} value={item.id}>
                      <AccordionTrigger>
                        <span className="flex-1 pr-3 text-left text-sm">
                          {item.title}
                          {buscando && item.category && (
                            <span className="ml-2 text-xs font-normal text-muted-foreground">
                              {item.group?.title} · {item.category.title}
                            </span>
                          )}
                        </span>
                      </AccordionTrigger>
                      <AccordionContent>
                        <FaqItemBody id={item.id} html={item.description_html} />
                      </AccordionContent>
                    </AccordionItem>
                  ))}
                </Accordion>
              )}
            </AsyncSection>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

/**
 * O corpo de um item. Na listagem por categoria ele já vem no payload; nos
 * resultados de busca vem só o trecho, e o texto completo é buscado ao abrir.
 */
function FaqItemBody({ id, html }: { id: string; html?: string }) {
  const detalhe = useQuery({
    queryKey: ['faq', 'item', id],
    queryFn: () => faqApi.get(id),
    enabled: !html,
  })

  const corpo = html ?? detalhe.data?.description_html ?? ''

  return (
    <div
      className={cn(
        'text-sm leading-relaxed text-foreground',
        '[&_p]:mb-2 [&_ul]:mb-2 [&_ul]:list-disc [&_ul]:pl-5 [&_ol]:mb-2 [&_ol]:list-decimal [&_ol]:pl-5',
        '[&_strong]:font-semibold [&_a]:text-primary [&_a]:underline [&_a]:underline-offset-2',
        '[&_h1]:font-title [&_h1]:text-base [&_h1]:font-semibold [&_h2]:font-title [&_h2]:font-semibold',
      )}
      dangerouslySetInnerHTML={{ __html: corpo }}
    />
  )
}

export default FaqPage
