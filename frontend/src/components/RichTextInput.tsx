import { useEffect, useState } from 'react'
import { Button } from '@/components/ui/Button'

export function RichTextInput({ value, displayHtml, onChange }: { value: string; displayHtml?: string; onChange: (v: string) => void }) {
  const [isRich, setIsRich] = useState(false)
  const [text, setText] = useState(value || '')
  const [html, setHtml] = useState(displayHtml || '')

  useEffect(() => {
    setText(value || '')
  }, [value])

  useEffect(() => {
    setHtml(displayHtml || '')
  }, [displayHtml])

  return (
    <div className="space-y-2">
      <div className="flex items-center gap-2">
        <Button variant="secondary" size="sm" onClick={() => setIsRich(false)}>Texto</Button>
        <Button variant="secondary" size="sm" onClick={() => setIsRich(true)}>WYSIWYG</Button>
      </div>
      {!isRich ? (
        <textarea
          className="rounded-lg border border-input bg-background p-3 text-sm text-foreground min-h-[120px]"
          value={text}
          onChange={(e) => { setText(e.target.value); onChange(e.target.value) }}
          placeholder="Digite o conteúdo"
        />
      ) : (
        <div
          className="rounded-lg border border-input bg-background p-3 text-sm text-foreground min-h-[120px]"
          contentEditable
          suppressContentEditableWarning
          onInput={(e) => {
            const val = (e.target as HTMLElement).innerHTML
            setHtml(val)
            onChange(val)
          }}
          dangerouslySetInnerHTML={{ __html: html || text.replace(/\n/g, '<br/>') }}
        />
      )}
    </div>
  )
}

export default RichTextInput

