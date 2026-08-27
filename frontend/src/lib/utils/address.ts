/**
 * Endereço — o `parseAddressAsHtml`/`parseAddressInLines` do legado, sem HTML.
 *
 * O original montava uma **string de HTML** com `<br/>` e a tela fazia `.split`
 * nela para voltar a ter linhas. Aqui a função devolve as linhas direto (o que
 * o React quer) e a versão em texto é derivada delas — nunca o contrário. Isso
 * elimina a montagem de HTML por concatenação, que é o vetor de injeção mais
 * simples que existe.
 */
export interface EnderecoParcial {
  address?: string | null
  number?: string | number | null
  complement?: string | null
  city?: string | null
  state?: string | null
  cep?: string | null
}

const preenchido = (v: unknown): v is string | number =>
  v !== null && v !== undefined && String(v).trim() !== ''

/** Linhas do endereço, na ordem de leitura. Campo ausente não vira linha vazia. */
export function enderecoEmLinhas(data: EnderecoParcial | null | undefined): string[] {
  if (!data) return []
  const linhas: string[] = []

  const logradouro = [data.address, data.number].filter(preenchido).join(', ')
  if (logradouro) linhas.push(logradouro)

  if (preenchido(data.complement)) linhas.push(String(data.complement).trim())

  const municipio = [data.city, data.state].filter(preenchido).join(', ')
  const comCep = preenchido(data.cep)
    ? municipio
      ? `${municipio} - ${String(data.cep).trim()}`
      : String(data.cep).trim()
    : municipio
  if (comCep) linhas.push(comCep)

  return linhas
}

/** Endereço numa linha só, para célula de tabela e tooltip. */
export function enderecoEmTexto(data: EnderecoParcial | null | undefined, separador = ' · '): string {
  return enderecoEmLinhas(data).join(separador)
}
