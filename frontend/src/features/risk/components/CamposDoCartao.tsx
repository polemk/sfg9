/**
 * Os pares rótulo/valor **dentro** de um `MobileCard`.
 *
 * O `MobileCard` da biblioteca aceita `children` livres de propósito (cada tela
 * mostra campos diferentes) — mas as três listas desta fatia (operações,
 * movimentos, prorrogações) mostram a mesma **forma**: duas colunas de pares,
 * com o valor em `font-numeric`. Escrever isso três vezes é como se chega a
 * três espaçamentos diferentes no mesmo produto.
 *
 * Mora aqui, e não em `components/mobile/`, porque é composição de tela sobre
 * um componente que já existe — não um componente novo da biblioteca. Se uma
 * quarta fatia precisar do mesmo desenho, aí sim ele sobe (Princípio 11).
 *
 * É `<dl>`/`<dt>`/`<dd>` pelo mesmo motivo do `DetailList` do desktop: no
 * leitor de tela, rótulo e valor precisam ser anunciados como par.
 */
export function CamposDoCartao({ itens }: { itens: Array<[string, string]> }) {
  return (
    <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
      {itens.map(([rotulo, valor]) => (
        <div key={rotulo}>
          <dt className="text-xs text-muted-foreground">{rotulo}</dt>
          <dd className="font-numeric text-foreground">{valor}</dd>
        </div>
      ))}
    </dl>
  )
}
