import { useQuery } from '@tanstack/react-query'
import { fieldHelpApi, type FieldHelpMap } from '@/lib/api/help'

/**
 * Ajuda de campo — **o mecanismo** (OPS-545 / DEC-88).
 *
 * A fronteira desta fatia é exatamente esta: o mecanismo é meu, o texto não. Os
 * 91 textos foram escritos sob a DEC-88 a partir das **fórmulas** (não dos
 * rótulos) e vivem em `backend/db/seed_assets/*_help_inputs.yml`. Trocar um
 * texto é editar YAML — nenhum deploy de front envolvido.
 *
 * Três garantias, e as três importam mais do que parecem:
 *
 * 1. **Chave ausente não quebra a tela.** `texto('campo_que_nao_existe')`
 *    devolve `undefined` e o `FieldHelp` simplesmente não renderiza nada.
 * 2. **`TODO:` não chega aqui.** O servidor já filtra as 4 chaves pendentes.
 *    Se um dia chegar uma, o filtro abaixo repete a regra — duas travas, porque
 *    exibir "TODO: precisa saber o que é o variável" a um operador é
 *    desinformação, que é o que a DEC-88 existe para evitar.
 * 3. **Uma requisição por sessão.** O mapa é estático; `staleTime: Infinity`
 *    evita refazer a chamada a cada formulário aberto.
 */
export function useFieldHelp(scope: string) {
  const query = useQuery({
    queryKey: ['field-help', scope],
    queryFn: () => fieldHelpApi.scope(scope),
    staleTime: Infinity,
    gcTime: Infinity,
    // Falha aqui é perda de tooltip, não de formulário: não vale insistir.
    retry: false,
  })

  const mapa: FieldHelpMap = query.data ?? {}
  const escopo = mapa[scope] ?? {}

  return {
    /** Texto do campo, ou `undefined` — nunca string vazia nem `TODO:`. */
    texto: (campo: string): string | undefined => {
      const valor = escopo[campo]
      if (!valor) return undefined
      if (valor.startsWith('TODO:')) return undefined
      return valor
    },
    carregando: query.isLoading,
    disponivel: Object.keys(escopo).length > 0,
  }
}
