/**
 * Rótulos de identidade que aparecem em MAIS DE UMA tela — DEC-74.
 *
 * Existe porque a mesma informação é mostrada em `/profile` (a própria pessoa) e em
 * `/users/:id` (o administrador olhando outra conta), e a primeira versão desta
 * fatia deixou a tabela só na primeira: no detalhe da conta o indicador saía como
 * **`media`**, o valor cru do banco, em vez de "Média". Rótulo escrito em dois
 * lugares é rótulo que fica diferente em um deles.
 */

/**
 * Os quatro degraus do indicador "Verificação", replicados como estão
 * (`engines/auth19/app/models/livetat/auth/user_info.rb:53-74`).
 *
 * **É decorativo:** o produto não decide nada com ele. O que mudou em relação ao
 * legado é que o degrau "Máxima" passa a ser **alcançável de verdade**, porque o ai9
 * verifica telefone — ele é canal de login (DEC-14). A trava de edição do telefone
 * que o legado punha junto (`is_phone_checked = 1` → campo `readonly` para sempre)
 * **não** é replicada: travá-lo deixaria quem trocou de número sem acesso.
 */
export const ROTULO_DE_VERIFICACAO: Record<string, string> = {
  baixa: 'Baixa',
  media: 'Média',
  alta: 'Alta',
  maxima: 'Máxima',
}

/** Devolve o rótulo, ou o próprio valor quando o servidor mandar um degrau novo. */
export function rotuloDeVerificacao(nivel?: string | null): string | null {
  if (!nivel) return null
  return ROTULO_DE_VERIFICACAO[nivel] ?? nivel
}
