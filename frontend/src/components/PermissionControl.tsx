import { useEffect, useState } from 'react'

import { Input } from '@/components/ui/Input'
import { Switch } from '@/components/ui/switch'
import type { PermissionChange, UserPermissionRow } from '@/lib/api/endpoints'

/**
 * O controle de **uma** permissão — interruptor ou teto numérico, conforme o
 * `kind` que o servidor mandou (DEC-108).
 *
 * ## Por que existe, e por que não mora dentro de uma tela
 *
 * Duas telas editam permissão: `/permissions` (por **papel**) e a aba Permissões
 * de `/users/:id` (por **pessoa**). Elas mostram o mesmo catálogo e precisam da
 * mesma regra de renderização; escrever a regra duas vezes é como as duas
 * divergem no dia em que o catálogo ganhar um terceiro tipo (Princípio 11).
 *
 * ## `null` não é `0`
 *
 * Num teto, **vazio = sem limite** e **`0` = nenhum permitido**. Os dois existem
 * no catálogo do legado (o OG não tinha teto útil; o Colaborador tinha `0`), e
 * confundi-los inverte a permissão. Por isso o campo é de texto com
 * `inputMode="numeric"` e não um `<input type="number">` com valor default: um
 * campo numérico vazio e um campo numérico zerado precisam continuar
 * distinguíveis.
 *
 * ## O teto grava ao SAIR do campo, não a cada tecla
 *
 * Digitar "50" emitiria "5" e depois "50" — duas gravações, duas entradas na
 * trilha de auditoria e um estado intermediário real no banco. Aqui a mudança
 * sobe no `blur` ou no Enter, e só quando o valor mudou de fato.
 */
export function PermissionControl({
  row,
  disabled,
  idPrefix,
  onChange,
}: {
  row: UserPermissionRow
  disabled: boolean
  /** Prefixo do `id`/`htmlFor` — a mesma permissão aparece em vários cards. */
  idPrefix: string
  onChange: (mudanca: PermissionChange) => void
}) {
  const id = `${idPrefix}-${row.key}`

  if (row.kind === 'limit') {
    return <CampoDeTeto id={id} row={row} disabled={disabled} onChange={onChange} />
  }

  return (
    <Switch
      id={id}
      checked={row.granted}
      disabled={disabled}
      onCheckedChange={(valor) => onChange({ granted: valor })}
      aria-label={row.title}
    />
  )
}

function CampoDeTeto({
  id,
  row,
  disabled,
  onChange,
}: {
  id: string
  row: UserPermissionRow
  disabled: boolean
  onChange: (mudanca: PermissionChange) => void
}) {
  const gravado = row.limit_value ?? null
  const [rascunho, setRascunho] = useState(gravado === null ? '' : String(gravado))

  // O valor pode chegar de fora — depois da própria gravação, ou pelo aviso do
  // `PermissionsChannel` quando outra pessoa mexeu no mesmo papel.
  useEffect(() => {
    setRascunho(gravado === null ? '' : String(gravado))
  }, [gravado])

  const confirmar = () => {
    const limpo = rascunho.replace(/[^\d]/g, '')
    const novo = limpo === '' ? null : Number(limpo)
    if (novo === gravado) {
      // Normaliza a tela de volta ao gravado (o usuário pode ter digitado "007").
      setRascunho(gravado === null ? '' : String(gravado))
      return
    }
    onChange({ limit_value: novo })
  }

  return (
    <div className="flex shrink-0 flex-col items-end gap-1">
      <Input
        id={id}
        value={rascunho}
        disabled={disabled}
        inputMode="numeric"
        placeholder="sem limite"
        className="h-9 w-28 text-right font-numeric max-md:h-11"
        aria-label={`${row.title} — teto`}
        aria-describedby={`${id}-ajuda`}
        onChange={(e) => setRascunho(e.target.value.replace(/[^\d]/g, ''))}
        onBlur={confirmar}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault()
            ;(e.target as HTMLInputElement).blur()
          }
        }}
      />
      <span id={`${id}-ajuda`} className="text-[11px] text-muted-foreground">
        {rascunho === '' ? 'sem limite' : 'vazio = sem limite'}
      </span>
    </div>
  )
}
