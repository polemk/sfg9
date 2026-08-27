import * as React from 'react'
import { cn } from '@/lib/utils'
import { FloatingPanel } from './FloatingPanel'
import { SearchInput } from './SearchInput'
import { ResultItem } from './ResultItem'
import { Badge } from './Badge'
import { EmptyState, ErrorState } from './States'
import { Spinner } from './Spinner'

/**
 * Autocomplete — **uma** implementação, simples e múltipla (FE-421, FE-422).
 *
 * Consolida as duas que existiam na base (`SearchableSelect` e
 * `SearchableMultiSelect`, mais o autocomplete embutido no `ImpersonateSearch`).
 * Eram três variações do mesmo componente com comportamento divergente: uma
 * filtrava por `label`+`detail`, outra só por `label`; uma fechava com clique
 * fora, outra também com `Escape`; nenhuma tinha estado de erro; e as três
 * abriam o painel com `absolute`, que é o defeito descrito no `FloatingPanel`.
 *
 * O componente é **agnóstico à origem dos dados**: recebe `options` já
 * filtradas quando a busca é remota (`onSearch` + `loading`), ou filtra
 * localmente quando não há `onSearch`. É o que permite a mesma peça servir o
 * autocomplete de membros (remoto, paginado) e um filtro de lista local.
 *
 * `multiple` acrescenta os selecionados como `Badge` removível acima do campo —
 * a variante de badge clicável (FE-425) existe exatamente para isto.
 */
export interface AutocompleteOption {
  id: string
  label: string
  subtitle?: string
  meta?: React.ReactNode
  icon?: React.ReactNode
  disabled?: boolean
}

interface BaseProps {
  options: AutocompleteOption[]
  placeholder?: string
  emptyMessage?: string
  /** Busca remota. Sem ele, o filtro é local sobre `options`. */
  onSearch?: (termo: string) => void
  loading?: boolean
  error?: unknown
  onRetry?: () => void
  disabled?: boolean
  /** Id do item cuja ação está em andamento (spinner na linha). */
  pendingId?: string | null
  className?: string
  panelClassName?: string
  'aria-label'?: string
}

export interface AutocompleteSingleProps extends BaseProps {
  multiple?: false
  value: string | null
  onChange: (id: string | null) => void
}

export interface AutocompleteMultipleProps extends BaseProps {
  multiple: true
  value: string[]
  onChange: (ids: string[]) => void
  /** Rótulos dos já selecionados quando não estão em `options` (busca remota). */
  selectedLabels?: Record<string, string>
}

export type AutocompleteProps = AutocompleteSingleProps | AutocompleteMultipleProps

export function Autocomplete(props: AutocompleteProps) {
  const {
    options,
    placeholder = 'Buscar…',
    emptyMessage = 'Nenhum resultado.',
    onSearch,
    loading,
    error,
    onRetry,
    disabled,
    pendingId,
    className,
    panelClassName,
  } = props

  const [open, setOpen] = React.useState(false)
  const [termo, setTermo] = React.useState('')
  const [ativo, setAtivo] = React.useState(0)
  const wrapRef = React.useRef<HTMLDivElement>(null)

  const multiplo = props.multiple === true
  const selecionados = multiplo ? props.value : props.value ? [props.value] : []

  // Sem `onSearch`, o filtro é local. Com ele, quem filtra é o servidor e o
  // componente não filtra de novo — filtrar duas vezes esconde resultado que o
  // servidor achou por outro campo (documento, e-mail).
  const visiveis = React.useMemo(() => {
    if (onSearch) return options
    const t = termo.trim().toLowerCase()
    if (!t) return options
    return options.filter(
      (o) => o.label.toLowerCase().includes(t) || (o.subtitle ?? '').toLowerCase().includes(t),
    )
  }, [options, termo, onSearch])

  React.useEffect(() => {
    setAtivo(0)
  }, [visiveis.length])

  const buscar = (v: string) => {
    setTermo(v)
    setOpen(true)
    onSearch?.(v)
  }

  const escolher = (o: AutocompleteOption) => {
    if (o.disabled) return
    if (props.multiple) {
      const ja = props.value.includes(o.id)
      props.onChange(ja ? props.value.filter((x) => x !== o.id) : [...props.value, o.id])
      // Múltipla escolha mantém o painel aberto: quem seleciona vários não
      // quer reabrir a cada item.
      setTermo('')
      onSearch?.('')
    } else {
      props.onChange(o.id)
      setTermo(o.label)
      setOpen(false)
    }
  }

  const remover = (id: string) => {
    if (props.multiple) props.onChange(props.value.filter((x) => x !== id))
    else props.onChange(null)
  }

  const rotuloDe = (id: string) =>
    options.find((o) => o.id === id)?.label ??
    (props.multiple ? props.selectedLabels?.[id] : undefined) ??
    id

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (!open && (e.key === 'ArrowDown' || e.key === 'Enter')) {
      setOpen(true)
      return
    }
    if (!open) return
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      setAtivo((i) => Math.min(visiveis.length - 1, i + 1))
    } else if (e.key === 'ArrowUp') {
      e.preventDefault()
      setAtivo((i) => Math.max(0, i - 1))
    } else if (e.key === 'Enter') {
      e.preventDefault()
      const o = visiveis[ativo]
      if (o) escolher(o)
    } else if (e.key === 'Escape') {
      e.preventDefault()
      setOpen(false)
    } else if (e.key === 'Backspace' && termo === '' && multiplo && selecionados.length) {
      // Backspace no campo vazio remove o último selecionado, como em campo
      // de destinatários de e-mail.
      remover(selecionados[selecionados.length - 1])
    }
  }

  const textoNoCampo = !multiplo && !open && props.value ? rotuloDe(props.value) : termo

  return (
    <div className={cn('w-full', className)}>
      {multiplo && selecionados.length > 0 && (
        <div className="mb-2 flex flex-wrap gap-1.5">
          {selecionados.map((id) => (
            <Badge key={id} variant="secondary" onRemove={() => remover(id)} removeLabel={`Remover ${rotuloDe(id)}`}>
              {rotuloDe(id)}
            </Badge>
          ))}
        </div>
      )}

      <div ref={wrapRef} onKeyDown={onKeyDown}>
        <SearchInput
          value={textoNoCampo}
          onValueChange={buscar}
          onFocus={() => setOpen(true)}
          onClear={() => {
            setTermo('')
            onSearch?.('')
            if (!multiplo) props.onChange(null)
          }}
          loading={loading}
          disabled={disabled}
          placeholder={placeholder}
          aria-label={props['aria-label']}
          aria-expanded={open}
          aria-autocomplete="list"
        />
      </div>

      <FloatingPanel
        open={open && !disabled}
        anchorRef={wrapRef as React.RefObject<HTMLElement>}
        onDismiss={() => setOpen(false)}
        className={panelClassName}
      >
        <div role="listbox" className="overflow-y-auto p-1">
          {error ? (
            <ErrorState size="inline" onRetry={onRetry} />
          ) : loading && visiveis.length === 0 ? (
            <div className="flex items-center justify-center gap-2 px-3 py-8 text-xs text-muted-foreground">
              <Spinner size="xs" label={null} /> Buscando…
            </div>
          ) : visiveis.length === 0 ? (
            <EmptyState size="inline" title={emptyMessage} icon={null} />
          ) : (
            visiveis.map((o, i) => (
              <ResultItem
                key={o.id}
                icon={o.icon}
                title={o.label}
                subtitle={o.subtitle}
                meta={o.meta}
                disabled={o.disabled}
                loading={pendingId === o.id}
                selected={selecionados.includes(o.id)}
                active={i === ativo}
                onMouseEnter={() => setAtivo(i)}
                onClick={() => escolher(o)}
              />
            ))
          )}
        </div>
      </FloatingPanel>
    </div>
  )
}
