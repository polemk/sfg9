import { useEffect, useMemo, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { receivablesApi, type ReceivableDerived, type ReceivablePayload } from '@/lib/api/receivables'

/**
 * S6 / **FE-171**, contrato **C2** — a prévia do formulário de borderô.
 *
 * ## O que este hook NÃO faz
 *
 * **Não calcula nada.** Nem soma de tarifa, nem `valor_bruto - recusado`, nem
 * arredondamento. Ele monta o payload, espera o usuário parar de digitar e
 * pergunta ao servidor — que responde com o resultado do **mesmo**
 * `Receivables::Calculator` que a gravação usa.
 *
 * No legado a conta existia duas vezes: no `before_validation` do model e numa
 * reimplementação **parcial** em JavaScript
 * (`../sfg/app/views/pub/receivables/new/_body.js.erb:339-504`) que não
 * calculava `taxa_desconto_nominal_*`, `custo_efetivo_com_float_*`,
 * `multiplicador_*` nem os `*_percent`, e arredondava o total de tarifas de
 * outro jeito. Era o **D-09**: o número da tela e o número gravado divergiam, e
 * não havia como dizer qual estava certo.
 *
 * ## O debounce, e por que ele é de 400 ms
 *
 * Cada tecla num campo monetário produz um payload novo. Sem espera, digitar
 * "149208,24" dispara nove requisições e a última a chegar nem sempre é a
 * última a sair. 400 ms é o suficiente para o usuário terminar o número e curto
 * o bastante para a prévia parecer viva.
 *
 * O React Query cuida do resto: chave por payload, `keepPreviousData` para o
 * painel **não piscar** entre uma tecla e outra, e cancelamento automático da
 * requisição anterior.
 *
 * ## Enquanto os campos obrigatórios não estão preenchidos, não há pergunta
 *
 * `prz_med_pond_emp` e `prz_med_pond_bco` precisam ser **maiores que zero** — é
 * validação do legado (`../sfg/app/models/receivable_entry.rb:20-21`) e é
 * divisor de seis fórmulas. Perguntar antes disso só produziria 422 a cada
 * tecla.
 */
export interface PreviewInput {
  valor_bruto: number | null
  vlr_bruto_recusado: number | null
  qtd_titulos: number | null
  qtd_recusada: number | null
  prz_med_pond_emp: number | null
  prz_med_pond_bco: number | null
  float_acordado: number | null
  cst_efetivo_acordado: number | null
  recompra: number | null
  retencao: number | null
  fomento: number | null
  outros: number | null
  date: string | null
  taxes: { movement_kind_id: string; value: number | null }[]
}

const DEBOUNCE_MS = 400

export interface PreviewResult {
  derived: ReceivableDerived | null
  /** Primeira carga: o painel ainda não tem número nenhum. */
  loading: boolean
  /** Recarga: já há número na tela e ele está sendo atualizado. */
  refreshing: boolean
  /** Mensagem do servidor quando a combinação é impossível (D-10). */
  problema: string | null
  /** Falta preencher algo obrigatório — não é erro, é um passo que falta. */
  incompleto: boolean
}

function completo(entrada: PreviewInput): boolean {
  return (
    entrada.valor_bruto !== null &&
    entrada.qtd_titulos !== null &&
    (entrada.prz_med_pond_emp ?? 0) > 0 &&
    (entrada.prz_med_pond_bco ?? 0) > 0
  )
}

function payloadDe(entrada: PreviewInput): Partial<ReceivablePayload> {
  return {
    valor_bruto: entrada.valor_bruto,
    vlr_bruto_recusado: entrada.vlr_bruto_recusado ?? 0,
    qtd_titulos: entrada.qtd_titulos,
    qtd_recusada: entrada.qtd_recusada ?? 0,
    prz_med_pond_emp: entrada.prz_med_pond_emp,
    prz_med_pond_bco: entrada.prz_med_pond_bco,
    float_acordado: entrada.float_acordado ?? 0,
    cst_efetivo_acordado: entrada.cst_efetivo_acordado ?? 0,
    recompra: entrada.recompra ?? 0,
    retencao: entrada.retencao ?? 0,
    fomento: entrada.fomento ?? 0,
    outros: entrada.outros ?? 0,
    date: entrada.date ?? undefined,
    // Só as tarifas com tipo escolhido: uma linha em branco não é uma tarifa de
    // zero real, é uma linha que o usuário ainda não terminou de preencher.
    taxes: entrada.taxes.filter((t) => t.movement_kind_id),
  }
}

export function useReceivablePreview(entrada: PreviewInput): PreviewResult {
  const [atrasado, setAtrasado] = useState(entrada)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const chave = JSON.stringify(payloadDe(entrada))

  useEffect(() => {
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => setAtrasado(entrada), DEBOUNCE_MS)
    return () => {
      if (timer.current) clearTimeout(timer.current)
    }
    // `chave` já resume o payload inteiro; depender do objeto dispararia a cada
    // render, porque ele é remontado toda vez.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chave])

  const pronto = completo(atrasado)
  const payload = useMemo(() => payloadDe(atrasado), [atrasado])

  const consulta = useQuery({
    queryKey: ['receivable-preview', payload],
    queryFn: () => receivablesApi.preview(payload),
    enabled: pronto,
    // O painel não pisca entre uma tecla e outra: o número anterior fica na
    // tela, esmaecido, enquanto o novo vem.
    placeholderData: (anterior) => anterior,
    retry: false,
  })

  const problema = consulta.error
    ? ((consulta.error as any)?.response?.data?.message ??
       (consulta.error as any)?.response?.data?.error ??
       'Não foi possível calcular com estes valores.')
    : null

  return {
    derived: (consulta.data as ReceivableDerived | undefined) ?? null,
    loading: pronto && consulta.isLoading,
    refreshing: pronto && consulta.isFetching && !consulta.isLoading,
    problema,
    incompleto: !pronto,
  }
}
