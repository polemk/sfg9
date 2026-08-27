import { useEffect, useState } from 'react'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { Switch } from '@/components/ui/switch'
import { RichTextField } from '@/components/ui/RichTextField'
import type { IndicatorInput } from '@/lib/api/indicators'

/**
 * O mínimo que o painel lê de um indicador. Deliberadamente **menor** que
 * `Indicator`: a tela de "Indicadores específicos" tem só a linha da listagem
 * (`IndicatorConnectionRow`), sem `project_id` nem contagens, e forçar o tipo
 * cheio ali obrigaria a inventar campos — que é como um `as any` entra no
 * código e passa a esconder erro de verdade.
 */
export interface DrawerIndicator {
  id: string
  title: string
  key: string
  is_active: boolean
  description_html: string | null
}

/**
 * `FE-316` — o painel de cadastro/edição do indicador.
 *
 * Três campos, os mesmos do legado
 * (`indicators/helper/_body.html.erb`): Título, Chave de Integração e Instrução.
 * O que muda:
 *
 * - **A Chave só aparece na edição, e explicando por quê.** No legado ela está
 *   no formulário de criação como campo livre, mas é derivada do título quando
 *   vazia — o usuário via um campo que quase nunca deveria preencher. Aqui ele
 *   entende que ela existe e é congelada (DEC-85).
 * - **A Instrução passa pelo `RichTextField` da biblioteca**, com a leitura
 *   sanitizada (UF-1). No legado é `rich_text_area` do ActionText renderizando
 *   HTML de usuário sem filtro para todos os outros do projeto.
 * - **O aviso de que o título vira CAIXA ALTA** fica escrito no campo. É DEC-89
 *   e não tem volta: "Inadimplência" fica "INADIMPLENCIA" no banco. Um usuário
 *   que digita com acento e vê o resultado sem ele precisa saber que é regra, e
 *   não defeito.
 * - **A copy "Essa construtora não pode ser alterada"** — texto de outra tela
 *   que vazou por cópia no legado — não existe aqui.
 */
export interface IndicatorDrawerProps {
  open: boolean
  onClose: () => void
  /** `null` = criação. */
  editando: DrawerIndicator | null
  /** Criação dentro do projeto corrente (indicador específico). */
  escopo?: 'global' | 'project'
  salvando: boolean
  onSubmit: (dados: IndicatorInput) => void
}

export function IndicatorDrawer({ open, onClose, editando, escopo = 'global', salvando, onSubmit }: IndicatorDrawerProps) {
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [isActive, setIsActive] = useState(true)

  useEffect(() => {
    if (!open) return
    setTitle(editando?.title ?? '')
    setDescription(editando?.description_html ?? '')
    setIsActive(editando?.is_active ?? true)
  }, [open, editando])

  const rotulo = editando
    ? 'Editar indicador'
    : escopo === 'project'
      ? 'Novo indicador do projeto'
      : 'Novo indicador'

  return (
    <SideDrawer
      open={open}
      onClose={onClose}
      title={rotulo}
      footer={
        <div className="flex gap-2">
          <Button variant="secondary" className="flex-1" onClick={onClose}>
            Cancelar
          </Button>
          <Button
            className="flex-1"
            loading={salvando}
            disabled={title.trim().length === 0}
            onClick={() => onSubmit({ title, description, is_active: isActive })}
          >
            Salvar
          </Button>
        </div>
      }
    >
      <div className="space-y-1.5">
        <Label htmlFor="indicator-title">Título</Label>
        <Input
          id="indicator-title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Ex.: Inadimplência da carteira"
          autoFocus
        />
        <p className="text-xs text-muted-foreground">
          O título é gravado em <strong>caixa alta e sem acento</strong> — “Inadimplência” fica
          “INADIMPLENCIA”. É como o sistema sempre funcionou, e toda a lista fica homogênea.
        </p>
      </div>

      {editando && (
        <div className="space-y-1.5">
          <Label htmlFor="indicator-key">Chave de Integração</Label>
          <Input id="indicator-key" value={editando.key} readOnly disabled className="font-numeric" />
          <p className="text-xs text-muted-foreground">
            Derivada do título na criação e mantida depois. Renomear o indicador não a altera —
            ela pode estar em uso por um sistema externo.
          </p>
        </div>
      )}

      <RichTextField
        label="Instrução"
        value={description}
        onChange={setDescription}
        hint="Aparece para quem preenche a grade mensal deste indicador. Aceita negrito, listas e links."
      />

      <div className="flex items-start justify-between gap-4 rounded-md border border-border bg-muted/40 p-3">
        <div>
          <Label htmlFor="indicator-active">Indicador ativo</Label>
          <p className="mt-1 text-xs text-muted-foreground">
            Inativo continua nos projetos que já o usam e nos lançamentos históricos, mas some da
            grade mensal.
          </p>
        </div>
        <Switch id="indicator-active" checked={isActive} onCheckedChange={setIsActive} />
      </div>
    </SideDrawer>
  )
}
