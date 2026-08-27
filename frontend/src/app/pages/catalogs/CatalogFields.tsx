import type { ReactNode } from 'react'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { Switch } from '@/components/ui/switch'

/**
 * Os campos que os cinco formulários de catálogo têm em comum.
 *
 * Fica separado do `CatalogScreen` porque a tela decide a ORDEM e o VOCABULÁRIO
 * dos campos — o portador chama o dele de "Razão social", o segmento de "Nome do
 * segmento". Um formulário genérico com rótulo genérico é como o legado acabou
 * com "Essa construtora não pode ser alterada" aparecendo em cinco entidades.
 */
export function Campo({
  id,
  label,
  hint,
  children,
}: {
  id: string
  /**
   * `ReactNode`, e não `string`: o rótulo carrega o `<FieldHelp>` ao lado do
   * texto (OPS-545 / DEC-88). Era `string`, e a primeira tela que precisou do
   * ícone recorreu a `as unknown as string` — cast que compila e mente. A
   * assinatura passa a dizer a verdade.
   */
  label: ReactNode
  hint?: ReactNode
  children: ReactNode
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>{label}</Label>
      {children}
      {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
    </div>
  )
}

export function CampoTexto({
  id,
  label,
  value,
  onChange,
  placeholder,
  hint,
  autoFocus,
}: {
  id: string
  label: string
  value: unknown
  onChange: (v: string) => void
  placeholder?: string
  hint?: ReactNode
  autoFocus?: boolean
}) {
  return (
    <Campo id={id} label={label} hint={hint}>
      <Input
        id={id}
        value={(value as string) ?? ''}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        autoFocus={autoFocus}
      />
    </Campo>
  )
}

/**
 * "Ativo" — o `is_active` dos cinco catálogos.
 *
 * No legado era `integer default 1` e o filtro caía em `NULL`; aqui é boolean
 * `null: false` no banco, então a caixa nunca fica num terceiro estado.
 */
export function CampoAtivo({
  value,
  onChange,
  descricao,
}: {
  value: unknown
  onChange: (v: boolean) => void
  descricao: string
}) {
  return (
    <div className="flex items-start justify-between gap-4 rounded-md border border-border bg-muted/40 p-3">
      <div>
        <Label htmlFor="is_active">Ativo</Label>
        <p className="mt-0.5 text-xs text-muted-foreground">{descricao}</p>
      </div>
      <Switch id="is_active" checked={value !== false} onCheckedChange={onChange} />
    </div>
  )
}
