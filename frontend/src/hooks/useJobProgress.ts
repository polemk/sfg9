import { useCallback, useMemo, useRef, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useChannel } from './useCable'

/**
 * useJobProgress — progresso de job por Action Cable (OPS-087).
 *
 * **`setInterval` é proibido nesta migração (Princípio 10).** O legado
 * perguntava ao servidor "já terminou?" de segundo em segundo, para toda aba
 * aberta, mesmo quando não havia job nenhum rodando. Aqui o servidor **avisa**:
 * o `ProjectProgressChannel` transmite o andamento e o percentual sobe na tela
 * sem recarregar.
 *
 * Ao terminar, o hook **invalida as queries** indicadas em vez de mandar o dado
 * pronto pelo socket. É a regra de realtime da casa (§5.7 das convenções): o
 * websocket é o *gatilho*, o React Query continua sendo a única fonte do dado.
 * Mandar o registro pelo socket cria um segundo caminho de dado que diverge do
 * primeiro no dia em que o serializador mudar.
 *
 * O canal é assinado só quando há `projectId` — o `useChannel` ignora parâmetro
 * nulo, então a tela pode montar o hook antes de o projeto estar resolvido.
 */
export type JobStatus = 'idle' | 'running' | 'done' | 'failed'

export interface JobProgress {
  /** Identificador do job, quando o servidor manda mais de um por projeto. */
  jobId?: string
  status: JobStatus
  /** 0–100. `null` enquanto o job não reportou nada. */
  percent: number | null
  /** Texto do passo atual ("Importando 320 de 1.204"). */
  message?: string
  error?: string
}

export interface UseJobProgressOptions {
  projectId: string | number | null | undefined
  /** Só ouve este job. Sem isso, ouve todos os do projeto. */
  jobId?: string | null
  /** Queries a invalidar quando o job termina. */
  invalidateKeys?: unknown[][]
  onDone?: (p: JobProgress) => void
  onFailed?: (p: JobProgress) => void
}

const INICIAL: JobProgress = { status: 'idle', percent: null }

export function useJobProgress({
  projectId,
  jobId,
  invalidateKeys,
  onDone,
  onFailed,
}: UseJobProgressOptions) {
  const [progress, setProgress] = useState<JobProgress>(INICIAL)
  const queryClient = useQueryClient()
  // Guardados em ref para não recriar os handlers (e a assinatura) a cada
  // render do consumidor.
  const cbRef = useRef({ onDone, onFailed, invalidateKeys })
  cbRef.current = { onDone, onFailed, invalidateKeys }

  const received = useCallback(
    (evt: any) => {
      if (!evt || typeof evt !== 'object') return
      // Filtro por job: sem ele, dois importadores do mesmo projeto pintariam
      // a mesma barra com percentuais alternados.
      if (jobId && evt.job_id && String(evt.job_id) !== String(jobId)) return

      const status: JobStatus =
        evt.status === 'completed' || evt.status === 'done'
          ? 'done'
          : evt.status === 'failed' || evt.status === 'error'
            ? 'failed'
            : 'running'

      const bruto = evt.percent ?? evt.progress ?? null
      const percent =
        bruto === null || bruto === undefined ? null : Math.max(0, Math.min(100, Number(bruto)))

      const proximo: JobProgress = {
        jobId: evt.job_id ? String(evt.job_id) : undefined,
        status,
        // Concluído sem número é 100%: barra parada em 87% com "concluído"
        // escrito ao lado é o tipo de detalhe que faz o usuário duvidar.
        percent: status === 'done' ? 100 : percent,
        message: evt.message ?? evt.step ?? undefined,
        error: evt.error ?? undefined,
      }
      setProgress(proximo)

      if (status === 'done' || status === 'failed') {
        for (const key of cbRef.current.invalidateKeys ?? []) {
          queryClient.invalidateQueries({ queryKey: key })
        }
        if (status === 'done') cbRef.current.onDone?.(proximo)
        else cbRef.current.onFailed?.(proximo)
      }
    },
    [jobId, queryClient],
  )

  useChannel('ProjectProgressChannel', { project_id: projectId ?? null }, { received })

  const reset = useCallback(() => setProgress(INICIAL), [])

  return useMemo(
    () => ({ ...progress, ativo: progress.status === 'running', reset }),
    [progress, reset],
  )
}
