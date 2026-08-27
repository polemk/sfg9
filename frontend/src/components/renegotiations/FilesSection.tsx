import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Paperclip } from 'lucide-react'
import { notify } from '@/lib/notify'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { FileDropzone } from '@/components/ui/FileDropzone'
import { AttachmentGallery } from './AttachmentGallery'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { renegotiationsApi, type RenegotiationAttachment } from '@/lib/api/renegotiations'
import type { AttachmentLimit } from '@/features/attachments/types'

/**
 * **Documentos da renegociação** (FE-209, FE-211, FE-212).
 *
 * ## O limite é comunicado de verdade
 *
 * Corrige o **D-50**. No legado o indicador de bloqueio era escrito no HTML
 * (`data-locked` no wrapper) e **nunca lido pelo JavaScript**; a validação que
 * existia lia `.lesson_attachment_content_wrapper` — seletor **de outro
 * produto** — e comparava com `NaN`. Aqui:
 *
 *  - **o número vem do servidor** (`GET …/attachments/limits`), com quantos já
 *    foram usados e quantos faltam;
 *  - a contagem aparece **no título**, não escondida;
 *  - quando o teto é atingido, a área de envio diz **por quê** e o que fazer.
 *
 * E, como sempre: a validação da tela é conveniência. O servidor aplica os mesmos
 * limites, lidos do mesmo `config/attachments.yml`, e recusa o que passar por
 * cima dela.
 */
export interface FilesSectionProps {
  renegotiationId: string
  podeEscrever: boolean
}

export function FilesSection({ renegotiationId, podeEscrever }: FilesSectionProps) {
  const queryClient = useQueryClient()
  const [baixando, setBaixando] = useState<string | null>(null)

  const anexos = useQuery({
    queryKey: ['renegotiation-attachments', renegotiationId],
    queryFn: () => renegotiationsApi.attachments.list(renegotiationId),
  })

  const limites = useQuery({
    queryKey: ['renegotiation-attachment-limits', renegotiationId],
    queryFn: () => renegotiationsApi.attachments.limits(renegotiationId),
  })

  function recarregar() {
    queryClient.invalidateQueries({ queryKey: ['renegotiation-attachments', renegotiationId] })
    queryClient.invalidateQueries({ queryKey: ['renegotiation-attachment-limits', renegotiationId] })
    queryClient.invalidateQueries({ queryKey: ['renegotiation', renegotiationId] })
  }

  const enviar = useMutation({
    mutationFn: (arquivos: File[]) => renegotiationsApi.attachments.upload(renegotiationId, arquivos),
    onSuccess: (criados) => {
      notify.success(criados.length === 1 ? 'Arquivo anexado.' : `${criados.length} arquivos anexados.`)
      recarregar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível anexar o arquivo.')),
  })

  const renomear = useMutation({
    mutationFn: ({ id, titulo }: { id: string; titulo: string }) =>
      renegotiationsApi.attachments.rename(renegotiationId, id, titulo),
    onSuccess: () => {
      notify.success('Anexo renomeado.')
      recarregar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível renomear o anexo.')),
  })

  const remover = useMutation({
    mutationFn: (anexo: RenegotiationAttachment) =>
      renegotiationsApi.attachments.remove(renegotiationId, anexo.id),
    onSuccess: () => {
      notify.success('Anexo removido.')
      recarregar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível remover o anexo.')),
  })

  async function baixar(anexo: RenegotiationAttachment) {
    setBaixando(anexo.id)
    try {
      await renegotiationsApi.attachments.download(renegotiationId, anexo.id, anexo.filename)
    } catch (erro) {
      notify.error(mensagemDoServidor(erro, 'Não foi possível baixar o arquivo.'))
    } finally {
      setBaixando(null)
    }
  }

  const lista = anexos.data ?? []
  // O `FileDropzone` fala a linguagem do catálogo de anexos; o endpoint da
  // renegociação devolve os mesmos números mais o consumo. A tradução é aqui,
  // num lugar só.
  const limite: AttachmentLimit | undefined = limites.data
    ? {
        multiple: true,
        maxFiles: limites.data.max_files,
        maxSizeBytes: limites.data.max_size_bytes,
        maxSizeMegabytes: limites.data.max_size_megabytes,
        contentTypes: limites.data.content_types,
      }
    : undefined

  return (
    <section className="rounded-lg border border-border bg-card p-4 sm:p-6">
      <header className="mb-4 flex flex-wrap items-center justify-between gap-2">
        <h2 className="flex items-center gap-2 text-sm font-semibold uppercase tracking-[0.08em] text-muted-foreground">
          <Paperclip className="h-4 w-4" aria-hidden />
          {/* A contagem no título (FE-209). */}
          Documentos ({lista.length}
          {limites.data ? `/${limites.data.max_files}` : ''})
        </h2>
      </header>

      {podeEscrever && (
        <FileDropzone
          className="mb-4"
          limit={limite}
          attachedCount={lista.length}
          uploading={enviar.isPending}
          onPick={(arquivos) => enviar.mutate(arquivos)}
          hint="Contrato, aditivo, comprovante — PDF, imagem ou planilha."
        />
      )}

      {anexos.isLoading && <LoadingState label="Carregando os documentos…" size="inline" />}

      {anexos.error && (
        <ErrorState
          size="inline"
          title="Não foi possível carregar os documentos"
          description={mensagemDoServidor(anexos.error, 'Tente novamente.')}
          onRetry={() => anexos.refetch()}
        />
      )}

      {!anexos.isLoading && !anexos.error && lista.length === 0 && (
        <EmptyState
          size="inline"
          icon={<Paperclip className="h-6 w-6" aria-hidden />}
          title="Nenhum documento anexado"
          description={
            podeEscrever
              ? 'Anexe o contrato, o aditivo ou os comprovantes do acordo. O arquivo fica guardado em área privada — o download passa por autorização.'
              : 'Ainda não há documentos nesta renegociação.'
          }
        />
      )}

      {lista.length > 0 && (
        <AttachmentGallery
          anexos={lista}
          baixando={baixando}
          podeEscrever={podeEscrever}
          onDownload={baixar}
          onRename={(anexo, titulo) => renomear.mutate({ id: anexo.id, titulo })}
          onDelete={(anexo) => remover.mutate(anexo)}
        />
      )}
    </section>
  )
}
