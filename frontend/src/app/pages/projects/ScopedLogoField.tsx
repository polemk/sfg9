import { useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { ImageCropper } from '@/components/ui/ImageCropper'
import { Button } from '@/components/ui/Button'
import { mensagemDoServidor } from '@/lib/api/catalogs'

/**
 * **O logo de um recurso escopado por projeto** — FE-074 (fornecedor) e
 * FE-087 (projeto).
 *
 * É o mesmo campo do `CarrierLogoField` da S3, generalizado em vez de copiado:
 * duas cópias dariam dois limites, duas mensagens de recusa e dois jeitos de
 * dizer "sem logo". A diferença entre os dois usos é só o cliente e o texto.
 *
 * **O limite é conferido antes de enviar** — mandar 4 MB para receber 422 é
 * gastar a rede do usuário para descobrir o óbvio. E o servidor confere de novo
 * de qualquer forma, inclusive o tipo REAL do arquivo (magic bytes): no legado
 * a detecção de spoof estava desligada e um `.exe` renomeado para `.png`
 * entrava.
 *
 * **A escolha sobrevive a erro de validação em outro campo** (FE-087): o upload
 * é uma requisição própria e já persistiu quando o formulário é salvo. No
 * legado o `ajax:error` de QUALQUER campo resetava o input de arquivo, e o
 * usuário reescolhia a imagem a cada erro de digitação.
 *
 * ## Sem `record`: a CRIAÇÃO (DEC-136)
 *
 * O legado aceitava a imagem já no cadastro; a migração só a oferecia na
 * edição, porque o upload precisa de um id. Com `record` nulo o campo guarda o
 * arquivo (`onPending`) e mostra a prévia local — quem chama envia depois que o
 * POST devolve o id, com `enviarLogoPendente`.
 *
 * **A falha do segundo passo NÃO desfaz o cadastro.** O registro fica criado e
 * a tela diz que a imagem não subiu, com o caminho para tentar de novo. Perder
 * o cadastro inteiro porque a foto falhou seria trocar um incômodo por uma
 * perda.
 */
const TIPOS_ACEITOS = ['image/png', 'image/jpeg', 'image/webp', 'image/gif']

export interface ScopedLogoApi<T> {
  uploadLogo: (id: string, file: File) => Promise<T>
  removeLogo: (id: string) => Promise<T>
}

export function ScopedLogoField<T extends { id: string }>({
  record,
  api,
  currentUrl,
  urlOf,
  limiteMb,
  queryKeys,
  placeholder,
  onPending,
}: {
  /** `null` na CRIAÇÃO: o arquivo fica pendente até o registro existir. */
  record: T | null
  api: ScopedLogoApi<T>
  currentUrl: string | null
  urlOf: (atualizado: T) => string | null
  /** O MESMO número de `config/attachments.yml`, escrito onde o usuário lê. */
  limiteMb: number
  /** Caches a invalidar depois de trocar o arquivo. */
  queryKeys: string[]
  placeholder: string
  /** Chamado na criação, com o arquivo escolhido (ou `null` ao limpar). */
  onPending?: (file: File | null) => void
}) {
  const queryClient = useQueryClient()
  const limiteBytes = limiteMb * 1024 * 1024

  const invalidar = () => queryKeys.forEach((k) => queryClient.invalidateQueries({ queryKey: [k] }))

  async function enviar(file: File): Promise<string> {
    if (!TIPOS_ACEITOS.includes(file.type)) {
      notify.error('O logo precisa ser PNG, JPG, WebP ou GIF.')
      throw new Error('tipo não aceito')
    }
    if (file.size > limiteBytes) {
      notify.error(`O logo passa de ${limiteMb} MB. Escolha um arquivo menor.`)
      throw new Error('acima do limite')
    }

    // Sem registro ainda: guarda o arquivo e devolve uma prévia LOCAL. Nada
    // vai à rede — não há a quem anexar.
    if (record === null) {
      onPending?.(file)
      return URL.createObjectURL(file)
    }

    try {
      const atualizado = await api.uploadLogo(record.id, file)
      notify.success('Logo atualizado.')
      invalidar()
      return urlOf(atualizado) ?? ''
    } catch (erro) {
      notify.error(mensagemDoServidor(erro, 'Não foi possível enviar o logo.'))
      throw erro
    }
  }

  async function remover() {
    if (record === null) {
      onPending?.(null)
      return
    }

    try {
      await api.removeLogo(record.id)
      notify.success('Logo removido.')
      invalidar()
    } catch (erro) {
      notify.error(mensagemDoServidor(erro, 'Não foi possível remover o logo.'))
    }
  }

  return (
    <div className="space-y-2">
      <ImageCropper
        value={currentUrl ?? undefined}
        onChange={() => invalidar()}
        onUpload={enviar}
        aspectRatio={1}
        placeholder={placeholder}
      />
      <p className="text-xs text-muted-foreground">PNG, JPG, WebP ou GIF, até {limiteMb} MB.</p>
      {currentUrl && (
        <Button variant="ghost" size="sm" onClick={remover}>
          Remover logo
        </Button>
      )}
    </div>
  )
}

/**
 * **O segundo passo da criação (DEC-136): sobe o logo depois que o id existe.**
 *
 * Devolve `true` quando não havia nada a enviar ou o envio deu certo.
 *
 * **A falha aqui NÃO desfaz o cadastro**, e é decisão registrada: o registro
 * fica criado e a mensagem diz exatamente isso — que o cadastro está salvo e só
 * a imagem não subiu, com o caminho para tentar de novo pela edição. Desfazer o
 * cadastro porque a foto falhou trocaria um incômodo por uma perda.
 *
 * A mensagem é `warning`, não `error`: o que aconteceu foi um sucesso parcial, e
 * dizer "erro" faria o usuário achar que precisa cadastrar de novo — que é
 * justamente o que produziria o registro duplicado.
 */
export async function enviarLogoPendente<T extends { id: string }>(
  api: ScopedLogoApi<T>,
  id: string,
  file: File | null,
): Promise<boolean> {
  if (!file) return true

  try {
    await api.uploadLogo(id, file)
    return true
  } catch (erro) {
    notify.warning(
      mensagemDoServidor(erro, 'O cadastro foi salvo, mas a imagem não subiu. Envie pela edição.'),
    )
    return false
  }
}
