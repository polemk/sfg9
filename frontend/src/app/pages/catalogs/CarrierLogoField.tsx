import { useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { ImageCropper } from '@/components/ui/ImageCropper'
import { Button } from '@/components/ui/Button'
import { carriersApi, mensagemDoServidor, type Carrier } from '@/lib/api/catalogs'

/**
 * **O logo do portador** (FE-067 / DEC-47).
 *
 * Ele existia no legado e estava **morto pela metade** (DC-10): o upload
 * comentado no HTML, a exibição comentada na listagem, mas o handler de JS vivo
 * apontando para um input inexistente, o `permit` aceitando `logo` e o model com
 * anexo e validações completos. O DEC-47 mandou ligar de volta.
 *
 * **Onde o arquivo vai parar (DEC-91):** `has_one_attached` no próprio
 * `Carrier`, ActiveStorage — **não** o `Medium`. A tabela `media` não tem dono
 * nem escopo, então um logo criado por lá ficaria legível por qualquer
 * autenticado, misturado com imagem de conteúdo. (A galeria `/media` que
 * expunha esse acervo saiu na DEC-109; a razão de não usar `Medium` continua
 * valendo — é o dono e o escopo, não a tela.)
 *
 * **O limite é conferido ANTES de enviar.** Mandar 8 MB para receber 422 é
 * gastar a rede do usuário para descobrir o óbvio — e o servidor confere de novo
 * de qualquer forma, inclusive o tipo REAL do arquivo (no legado a detecção de
 * spoof estava desligada e um `.exe` renomeado para `.png` entrava).
 */
const TIPOS_ACEITOS = ['image/png', 'image/jpeg', 'image/webp', 'image/gif']
const LIMITE_BYTES = 2 * 1024 * 1024

export function CarrierLogoField({ carrier }: { carrier: Carrier }) {
  const queryClient = useQueryClient()

  const invalidar = () => {
    queryClient.invalidateQueries({ queryKey: ['carriers'] })
    queryClient.invalidateQueries({ queryKey: ['carrier', carrier.id] })
  }

  async function enviar(file: File): Promise<string> {
    if (!TIPOS_ACEITOS.includes(file.type)) {
      notify.error('O logo precisa ser PNG, JPG, WebP ou GIF.')
      throw new Error('tipo não aceito')
    }
    if (file.size > LIMITE_BYTES) {
      notify.error('O logo passa de 2 MB. Escolha um arquivo menor.')
      throw new Error('acima do limite')
    }

    try {
      const atualizado = await carriersApi.uploadLogo(carrier.id, file)
      notify.success('Logo atualizado.')
      invalidar()
      return atualizado.logo_url ?? ''
    } catch (erro) {
      notify.error(mensagemDoServidor(erro, 'Não foi possível enviar o logo.'))
      throw erro
    }
  }

  async function remover() {
    try {
      await carriersApi.removeLogo(carrier.id)
      notify.success('Logo removido.')
      invalidar()
    } catch (erro) {
      notify.error(mensagemDoServidor(erro, 'Não foi possível remover o logo.'))
    }
  }

  return (
    <div className="space-y-2">
      <ImageCropper
        value={carrier.logo_url ?? undefined}
        onChange={() => invalidar()}
        onUpload={enviar}
        aspectRatio={1}
        placeholder="Enviar logo do portador"
      />
      <p className="text-xs text-muted-foreground">PNG, JPG, WebP ou GIF, até 2 MB.</p>
      {carrier.logo_url && (
        <Button variant="ghost" size="sm" onClick={remover}>
          Remover logo
        </Button>
      )}
    </div>
  )
}
