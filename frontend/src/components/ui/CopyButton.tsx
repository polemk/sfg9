import { useState } from 'react'
import { Check, Copy } from 'lucide-react'
import { notify } from '@/lib/notify'
import { cn } from '@/lib/utils'
import { Button } from './Button'

export interface CopyButtonProps {
  /** O que vai para a área de transferência. Vazio não renderiza nada. */
  value: string | null | undefined
  /** Entra no `aria-label` e na mensagem: "Copiar {label}" / "{label} copiado". */
  label: string
  className?: string
}

/**
 * **Copiar um valor curto para a área de transferência.**
 *
 * Nasceu do FE-017: o `identifier` — o código que a pessoa **dita por telefone**
 * para o suporte — aparecia no detalhe de outra conta sem nenhum jeito de
 * copiar. Só a conta própria tinha o botão (FE-034), e é justamente no detalhe
 * de outra conta que o administrador precisa dele.
 *
 * Componente compartilhado porque o `ProfilePage` já tinha esta lógica escrita à
 * mão, dentro de um `CampoIdentidade` moldado para o layout daquela tela. Copiar
 * o código de copiar para a segunda tela seria a segunda definição de quando
 * mostrar o "copiado" e do que dizer quando o navegador recusa.
 *
 * **A recusa é tratada, e não silenciosa.** `navigator.clipboard` exige contexto
 * seguro e pode ser negado; falhar calado faria o botão parecer quebrado. O
 * texto ao lado continua selecionável, e é isso que a mensagem de erro diz.
 */
export function CopyButton({ value, label, className }: CopyButtonProps) {
  const [copiado, setCopiado] = useState(false)

  if (!value) return null

  const copiar = async () => {
    try {
      await navigator.clipboard.writeText(value)
      setCopiado(true)
      notify.success(`${label} copiado`)
      setTimeout(() => setCopiado(false), 2000)
    } catch {
      notify.error('Não consegui copiar. Selecione e copie manualmente.')
    }
  }

  return (
    <Button
      variant="ghost"
      size="icon"
      aria-label={`Copiar ${label}`}
      onClick={copiar}
      className={cn('h-7 w-7', className)}
    >
      {copiado ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
    </Button>
  )
}
