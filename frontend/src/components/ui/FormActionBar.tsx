import { useState, type ReactNode } from 'react'
import { ChevronDown } from 'lucide-react'
import { cn } from '@/lib/utils'

/**
 * **A barra de ação de um formulário longo** — fixa no rodapé, com o estado do
 * formulário à esquerda e os botões à direita.
 *
 * Nasce na biblioteca compartilhada porque é o substituto de um padrão que o
 * legado repetia em **toda** tela de cadastro: a "barra inferior de ações
 * pendentes" (`dashBottomHolder.getData().stack`), onde cada `change` de campo
 * empilhava uma ação anônima. O defeito daquele desenho não era o visual — era
 * que, se **qualquer** campo obrigatório ficasse vazio, a ação era **removida
 * da pilha sem mensagem nenhuma**: o usuário perdia a possibilidade de salvar e
 * não tinha como saber por quê (`FE-295`, e a mesma família em recebíveis).
 *
 * Por isso o componente **exige** `pendencias`: quando o formulário não pode
 * ser enviado, a barra **diz o que falta**. Não existe caminho em que ela
 * simplesmente desabilite o botão em silêncio — que é exatamente o que ela
 * existe para impedir.
 *
 * ### Contrato
 *
 * - `pendencias` vazio ⇒ o formulário pode ser enviado; a barra mostra o
 *   `resumo` (o total calculado, o valor líquido, o que a tela quiser).
 * - `pendencias` com itens ⇒ a barra lista as pendências, em pt-BR, na ordem em
 *   que os campos aparecem na tela.
 * - Os botões vão em `children`, para que cada tela escolha o próprio rótulo
 *   ("Cadastrar borderô", "Salvar alterações") — genérico aqui foi como o
 *   legado acabou com "Essa construtora não pode ser alterada" em cinco telas.
 *
 * ### O estado sujo (S2 / FE-400)
 *
 * A barra do legado só existia **porque** havia alteração pendente: ela subia
 * no primeiro `change` e sumia quando a pilha esvaziava. Aqui ela é sempre
 * visível (é onde mora o botão de salvar), então o que ela precisa dizer a mais
 * é **se há coisa não salva** — e é isso que `alterado` faz.
 *
 * A ordem de precedência do texto da esquerda é deliberada, e é a ordem em que
 * as três coisas importam para quem está no formulário:
 *
 * 1. **`erro`** — o salvar acabou de falhar. Fica na tela até a próxima
 *    tentativa; o `toast` sozinho some em 4 s e leva o motivo junto.
 * 2. **`pendencias`** — não dá para enviar, e a barra diz o que falta.
 * 3. **`alterado`** — dá para enviar e há coisa não salva.
 * 4. **`resumo`** — nada pendente: o total, o líquido, o que a tela quiser.
 *
 * A página que a usa precisa reservar o espaço dela (`pb-28`), senão o último
 * campo fica embaixo da barra.
 */
export function FormActionBar({
  pendencias,
  resumo,
  alterado = false,
  erro,
  children,
  className,
  label = 'Ações do formulário',
}: {
  /** O que falta preencher. Vazio = pode enviar. */
  pendencias: string[]
  /** O que a barra mostra quando não há pendência. */
  resumo?: ReactNode
  /** FE-400 — há alteração não salva. */
  alterado?: boolean
  /** FE-400 — o motivo da última falha ao salvar. Fica até a próxima tentativa. */
  erro?: ReactNode
  /** Os botões (Cancelar, Descartar, Salvar…). */
  children: ReactNode
  className?: string
  label?: string
}) {
  // O detalhamento das pendências no telefone nasce RECOLHIDO. Ver a nota do
  // `Pendencias` abaixo.
  const [abertas, setAbertas] = useState(false)

  return (
    <div
      role="region"
      aria-label={label}
      className={cn(
        // **A barra fica ACIMA da `MobileBottomBar`, não por baixo dela.**
        //
        // Medido em 390×844: com `bottom-0` a barra ficava atrás das abas de
        // navegação (`z-appbar` = 30 contra `z-20` daqui) e o botão "Cadastrar
        // borderô" — o único jeito de terminar a tela — aparecia como uma tira
        // de 6 px espremida sob "Recebíveis". O `tsc` e a suíte passavam.
        //
        // `4.25rem` é a altura declarada da `MobileBottomBar`
        // (`h-[4.25rem]`), e o `safe-area-inset-bottom` é o mesmo que ela soma.
        // No desktop não há barra de abas, então volta para o rodapé.
        'fixed inset-x-0 z-20 border-t border-border bg-card/95 px-4 py-3 backdrop-blur',
        'bottom-[calc(4.25rem+env(safe-area-inset-bottom))] md:bottom-0',
        'md:pb-[max(0.75rem,env(safe-area-inset-bottom))]',
        className,
      )}
    >
      {/* **No telefone o texto fica em CIMA dos botões, não ao lado.**
          Medido em 390×844: com os dois lado a lado (`flex-wrap`), os botões
          ficavam com ~230 px e sobravam ~90 px para a frase — que quebrava numa
          palavra por linha ("Faltam / 9 / campos: / a / empresa, / o /
          portador…"). Empilhar dá a largura inteira à frase e mantém os botões
          numa linha só, alinhados à direita, onde o polegar já os procura. */}
      <div className="mx-auto flex max-w-6xl flex-col items-stretch gap-2 md:flex-row md:flex-wrap md:items-center md:justify-between md:gap-3">
        <div className="min-w-0 text-sm md:flex-1">
          {erro ? (
            // `role="alert"`: falha ao salvar INTERROMPE — é a única das quatro
            // que precisa cortar o que a pessoa está lendo.
            <span role="alert" className="text-destructive-text">
              {erro}
            </span>
          ) : pendencias.length > 0 ? (
            <Pendencias itens={pendencias} abertas={abertas} alternar={() => setAbertas((v) => !v)} />
          ) : alterado ? (
            <span role="status" className="flex items-center gap-2 text-muted-foreground">
              <span aria-hidden className="h-2 w-2 shrink-0 rounded-full bg-warning" />
              Alterações não salvas
              {resumo && <span className="hidden sm:inline">· {resumo}</span>}
            </span>
          ) : (
            resumo
          )}
        </div>
        <div className="flex shrink-0 items-center justify-end gap-2">{children}</div>
      </div>
    </div>
  )
}

/**
 * **A lista de pendências, que no telefone não pode virar um muro de texto.**
 *
 * Medido em 390×844 no formulário de borderô: com o formulário em branco são
 * **nove** pendências, e a frase inteira ocupava quatro linhas — cerca de 110 px,
 * um oitavo da tela, empurrando o botão de salvar para fora. "Cabe" não é o
 * critério (DEC-100).
 *
 * A saída **não** é encurtar a mensagem: dizer o que falta é a razão de o
 * componente existir (FE-295 — o legado tirava o salvar em silêncio). A saída é
 * recolher: o telefone mostra a contagem e as duas primeiras, e quem quiser a
 * lista toca para abrir. No desktop a linha inteira sempre cabe e não há
 * recolhimento nenhum.
 *
 * `role="status"` fica no elemento que **muda de texto**, para que o leitor de
 * tela anuncie a mudança da razão do bloqueio.
 */
function Pendencias({
  itens,
  abertas,
  alternar,
}: {
  itens: string[]
  abertas: boolean
  alternar: () => void
}) {
  const CURTO = 2
  const recolhivel = itens.length > CURTO
  const resumo = recolhivel && !abertas ? itens.slice(0, CURTO).join(', ') : itens.join(', ')

  return (
    <div role="status" className="text-muted-foreground">
      {/* No desktop, a lista completa, sempre — é uma linha só. */}
      <span className="hidden md:inline">Falta preencher: {itens.join(', ')}.</span>

      <span className="md:hidden">
        {recolhivel ? (
          <button
            type="button"
            onClick={alternar}
            aria-expanded={abertas}
            // `text-left` porque a folha de estilo do próprio navegador dá
            // `text-align: center` a `<button>`, e a frase de duas linhas sairia
            // centralizada no meio de um bloco de texto alinhado à esquerda.
            className="flex w-full items-start gap-1 text-left"
          >
            <span className="min-w-0">
              Faltam <strong className="font-semibold">{itens.length}</strong> campos: {resumo}
              {!abertas && '…'}
            </span>
            <ChevronDown
              aria-hidden
              className={cn('mt-0.5 h-4 w-4 shrink-0 transition-transform', abertas && 'rotate-180')}
            />
          </button>
        ) : (
          <span>Falta preencher: {itens.join(', ')}.</span>
        )}
      </span>
    </div>
  )
}
