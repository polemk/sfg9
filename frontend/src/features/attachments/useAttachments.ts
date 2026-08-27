import { useQuery } from '@tanstack/react-query'
import { attachmentsApi } from './api'
import type { AttachmentLimit } from './types'

/**
 * Limites de anexo do servidor (CFG-02). **Sempre use isto em vez de escrever o
 * número na tela.**
 *
 * No legado os dois números do anexo de renegociação viviam interpolados no
 * JavaScript da view (`SFG::Metadata::MAX_FILES_PER_RENEGOTIATION` e
 * `MAX_FILE_SIZE` dentro de um `.js.erb`). Mudar o limite exigia mexer no ERB, e o
 * servidor nem consultava esses valores — a validação era só do cliente.
 *
 * `staleTime` alto de propósito: limite não muda durante a sessão, e refazer a
 * consulta a cada montagem de formulário é ruído.
 */
export function useAttachmentLimits() {
  return useQuery({
    queryKey: ['attachments', 'limits'],
    queryFn: () => attachmentsApi.limits(),
    staleTime: 30 * 60 * 1000,
  })
}

/** Limite de um anexo específico: `useAttachmentLimit('renegotiation_attachment', 'file')`. */
export function useAttachmentLimit(model: string, name: string): AttachmentLimit | undefined {
  const { data } = useAttachmentLimits()
  return data?.attachments?.[model]?.[name]
}

/**
 * Abre o anexo numa aba nova. Pede a URL assinada NO MOMENTO do clique — nunca
 * guarda a URL, porque ela expira (5 min) e uma URL guardada vira link quebrado
 * ou, pior, link compartilhável.
 */
export async function openAttachment(id: string) {
  const signed = await attachmentsApi.signedUrl(id)
  window.open(signed.url, '_blank', 'noopener,noreferrer')
}
