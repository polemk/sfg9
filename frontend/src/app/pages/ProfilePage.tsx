import { useEffect, useMemo, useState, useRef } from 'react'
import { createEditor, Descendant, BaseEditor, Editor, Element as SlateElement, Transforms, Range } from 'slate'
import { Slate, Editable, withReact, ReactEditor } from 'slate-react'
import { withHistory, HistoryEditor } from 'slate-history'
 
import { setCsrfToken, clearTokens } from '@/lib/api/tokenStore'
import { useAuthStore } from '@/store/authStore'
import { authApi, usersApi } from '@/lib/api/endpoints'
import { authService } from '@/lib/api/auth'
import { apiClient } from '@/lib/api/client'
import { Input } from '@/components/ui/Input'
import { Select } from '@/components/ui/Select'
import { PhoneInputGroup } from '@/components/PhoneInputGroup'
import { Button } from '@/components/ui/Button'
import { CopyButton } from '@/components/ui/CopyButton'
import { notify } from '@/lib/notify'
import { Check, X, Shield, Upload, Bold, Italic, Underline, Heading1, Heading2, List, Code, Link as LinkIcon, User, MapPin, Copy, Trash2, AlertTriangle } from 'lucide-react'
import { UserAvatar } from '@/components/ui/UserAvatar'
// S12 / FE-336 — "Contratos e aceites". A caixa nasce DESMARCADA e o histórico
// distingue o aceite dado do carimbado pela base antiga (DEC-66).
import { MyTermsSection } from '@/components/contracts/MyTermsSection'
import { rotuloDeVerificacao } from '@/features/auth/identityLabels'

type CustomText = { text: string; bold?: boolean; italic?: boolean; underline?: boolean; code?: boolean }
type ParagraphElement = { type: 'paragraph'; children: CustomText[] }
type H1Element = { type: 'heading-one'; children: CustomText[] }
type H2Element = { type: 'heading-two'; children: CustomText[] }
type BulletedListElement = { type: 'bulleted-list'; children: ListItemElement[] }
type ListItemElement = { type: 'list-item'; children: CustomText[] }
type LinkElement = { type: 'link'; url: string; children: CustomText[] }
type CodeBlockElement = { type: 'code'; children: CustomText[] }
type CustomElement = ParagraphElement | H1Element | H2Element | BulletedListElement | ListItemElement | LinkElement | CodeBlockElement

declare module 'slate' {
  interface CustomTypes {
    Editor: BaseEditor & ReactEditor & HistoryEditor
    Element: CustomElement
    Text: CustomText
  }
}

function isMarkActive(editor: ReactEditor, mark: keyof CustomText) {
  const marks = Editor.marks(editor as any) as Partial<CustomText> | null
  return !!marks && !!(marks as any)[mark]
}

function toggleMark(editor: ReactEditor, mark: keyof CustomText) {
  if (isMarkActive(editor, mark)) {
    Editor.removeMark(editor as any, mark)
  } else {
    Editor.addMark(editor as any, mark, true)
  }
}

function isBlockActive(editor: ReactEditor, type: CustomElement['type']) {
  const [match] = Array.from(Editor.nodes(editor as any, { match: n => SlateElement.isElement(n) && (n as any).type === type }))
  return !!match
}

function toggleBlock(editor: ReactEditor, type: CustomElement['type']) {
  const isActive = isBlockActive(editor, type)
  Transforms.unwrapNodes(editor as any, { match: n => SlateElement.isElement(n) && (n as any).type === 'bulleted-list', split: true })
  const newType = isActive ? 'paragraph' : type
  Transforms.setNodes(editor as any, { type: newType } as any)
  if (type === 'bulleted-list' && !isActive) {
    Transforms.wrapNodes(editor as any, { type: 'bulleted-list', children: [] } as any)
    Transforms.setNodes(editor as any, { type: 'list-item' } as any)
  }
}

function isLinkActive(editor: ReactEditor) {
  const [link] = Array.from(Editor.nodes(editor as any, { match: n => SlateElement.isElement(n) && (n as any).type === 'link' }))
  return !!link
}

function unwrapLink(editor: ReactEditor) {
  Transforms.unwrapNodes(editor as any, { match: n => SlateElement.isElement(n) && (n as any).type === 'link' })
}

function wrapLink(editor: ReactEditor, url: string) {
  if (isLinkActive(editor)) unwrapLink(editor)
  const { selection } = editor as any
  const link: LinkElement = { type: 'link', url, children: [{ text: '' }] }
  if (selection && Range.isCollapsed(selection)) {
    Transforms.insertNodes(editor as any, [{ type: 'link', url, children: [{ text: url }] } as any])
  } else {
    Transforms.wrapNodes(editor as any, link as any, { split: true })
  }
}

function clearFormatting(editor: ReactEditor) {
  if (!(editor as any).selection) return
  ;(['bold','italic','underline','code'] as const).forEach((m) => {
    Editor.removeMark(editor as any, m as any)
  })
  Transforms.unwrapNodes(editor as any, { match: n => SlateElement.isElement(n) && ((n as any).type === 'link' || (n as any).type === 'bulleted-list'), split: true })
  Transforms.setNodes(editor as any, { type: 'paragraph' } as any, { match: n => SlateElement.isElement(n) && ((n as any).type === 'heading-one' || (n as any).type === 'heading-two' || (n as any).type === 'list-item' || (n as any).type === 'code') })
}

function serializeToHTML(nodes: Descendant[]): string {
  function serializeNode(n: Descendant): string {
    if ('text' in n) {
      let text = n.text
      if ((n as CustomText).bold) text = `<strong>${text}</strong>`
      if ((n as CustomText).italic) text = `<em>${text}</em>`
      if ((n as CustomText).underline) text = `<u>${text}</u>`
      if ((n as CustomText).code) text = `<code>${text}</code>`
      return text
    }
    const el = n as CustomElement
    const children = (el.children as any[]).map(serializeNode).join('')
    switch (el.type) {
      case 'paragraph':
        return `<p>${children}</p>`
      case 'heading-one':
        return `<h1>${children}</h1>`
      case 'heading-two':
        return `<h2>${children}</h2>`
      case 'bulleted-list':
        return `<ul>${children}</ul>`
      case 'list-item':
        return `<li>${children}</li>`
      case 'link':
        return `<a href="${(el as LinkElement).url}">${children}</a>`
      case 'code':
        return `<pre><code>${children}</code></pre>`
      default:
        return children
    }
  }
  return nodes.map(serializeNode).join('')
}

function deserializeHTML(html: string): Descendant[] {
  const parser = new DOMParser()
  const decodeHTML = (s: string) => (s || '')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
  const doc = parser.parseFromString(decodeHTML(html) || '<p></p>', 'text/html')
  function deserialize(el: Node, marks: Partial<CustomText> = {}, preserveWhitespace = false): Descendant[] {
    if (el.nodeType === 3) {
      const raw = (el.textContent || '').replace(/\r/g, '')
      const noNewlines = preserveWhitespace ? raw : raw.replace(/\n/g, '')
      if (!preserveWhitespace && noNewlines.trim().length === 0) return []
      return [{ text: noNewlines, ...marks }]
    }
    if (!(el instanceof HTMLElement)) {
      return []
    }
    const nextMarks = { ...marks }
    const tag = el.tagName.toLowerCase()
    const nextPreserve = preserveWhitespace || tag === 'pre'
    if (tag === 'strong' || tag === 'b') nextMarks.bold = true
    if (tag === 'em' || tag === 'i') nextMarks.italic = true
    if (tag === 'u') nextMarks.underline = true
    if (tag === 'code' && el.parentElement?.tagName.toLowerCase() !== 'pre') nextMarks.code = true
    let children = Array.from(el.childNodes).flatMap(child => deserialize(child, nextMarks, nextPreserve))
    const ensureTextChildren = (nodes: Descendant[]) => nodes.length ? nodes : [{ text: '' }]
    switch (tag) {
      case 'h1':
        return [{ type: 'heading-one', children: ensureTextChildren(children) } as any]
      case 'h2':
        return [{ type: 'heading-two', children: ensureTextChildren(children) } as any]
      case 'ul': {
        const items: Descendant[] = []
        Array.from(el.children).forEach((li) => {
          if (li.tagName.toLowerCase() === 'li') {
            const liChildren = Array.from(li.childNodes).flatMap(child => deserialize(child, nextMarks, nextPreserve))
            items.push({ type: 'list-item', children: ensureTextChildren(liChildren) } as any)
          }
        })
        const ensured = items.length ? items : [{ type: 'list-item', children: [{ text: '' }] } as any]
        return [{ type: 'bulleted-list', children: ensured as any } as any]
      }
      case 'li':
        return [{ type: 'list-item', children: ensureTextChildren(children) } as any]
      case 'a':
        return [{ type: 'link', url: el.getAttribute('href') || '', children: children.length ? children : [{ text: el.getAttribute('href') || '' }] } as any]
      case 'pre':
        return [{ type: 'code', children: ensureTextChildren(children) } as any]
      case 'p':
        return [{ type: 'paragraph', children: ensureTextChildren(children) } as any]
      default:
        if (tag === 'br') return preserveWhitespace ? [{ text: '\n' }] : []
        return children
    }
  }
  const bodyChildren = Array.from(doc.body.childNodes)
  const result = bodyChildren.flatMap(n => deserialize(n))
  const normalized = result
    .map((n: any) => {
      if ('text' in n) return { type: 'paragraph', children: [n] } as any
      return n
    })
    .filter((n: any, idx: number) => {
      if (!n || !('children' in n)) return true
      const ch: any[] = (n.children || [])
      const onlyEmptyText = ch.length === 1 && 'text' in ch[0] && (ch[0].text || '') === ''
      return idx === 0 ? !onlyEmptyText : true
    })
  return normalized.length ? normalized : [{ type: 'paragraph', children: [{ text: '' }] }]
}

function RichTextEditor({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const [editor] = useState(() => {
    const e = withHistory(withReact(createEditor()))
    const prevIsInline = e.isInline
    e.isInline = (element: any) => (element?.type === 'link') || prevIsInline(element)
    return e
  })
  const [content, setContent] = useState<Descendant[]>(deserializeHTML(value))
  const [version, setVersion] = useState(0)
  useEffect(() => {
    setContent(deserializeHTML(value))
    setVersion((v) => v + 1)
  }, [value])
  const renderElement = useMemo(() => (props: any) => {
    const { element, attributes, children } = props
    switch (element.type) {
      case 'heading-one':
        return <h1 {...attributes} className="text-lg font-semibold mb-2">{children}</h1>
      case 'heading-two':
        return <h2 {...attributes} className="text-base font-semibold mb-2">{children}</h2>
      case 'bulleted-list':
        return <ul {...attributes} className="list-disc pl-6">{children}</ul>
      case 'list-item':
        return <li {...attributes}>{children}</li>
      case 'link':
        return <a {...attributes} href={(element as LinkElement).url} className="text-primary underline">{children}</a>
      case 'code':
        return <pre {...attributes} className="bg-muted p-2 rounded text-xs overflow-auto"><code>{children}</code></pre>
      default:
        return <p {...attributes} className="mb-2">{children}</p>
    }
  }, [])
  const renderLeaf = useMemo(() => (props: any) => {
    const { leaf, attributes } = props
    let children = props.children
    if (leaf.bold) children = <strong>{children}</strong>
    if (leaf.italic) children = <em>{children}</em>
    if (leaf.underline) children = <u>{children}</u>
    if (leaf.code) children = <code className="bg-muted px-1 rounded text-xs">{children}</code>
    return <span {...attributes}>{children}</span>
  }, [])
  const onKeyDown = (e: React.KeyboardEvent) => {
    if (!e.ctrlKey) return
    if (e.key === 'b') { e.preventDefault(); toggleMark(editor as any, 'bold') }
    if (e.key === 'i') { e.preventDefault(); toggleMark(editor as any, 'italic') }
    if (e.key === 'u') { e.preventDefault(); toggleMark(editor as any, 'underline') }
    if (e.key === '`') { e.preventDefault(); toggleMark(editor as any, 'code') }
  }
  const isEmpty = useMemo(() => {
    if (!content || content.length === 0) return true
    if (content.length === 1) {
      const n: any = content[0]
      const children = (n?.children || []) as any[]
      if (children.length === 0) return true
      if (children.length === 1 && 'text' in children[0] && (children[0].text || '') === '') return true
    }
    return false
  }, [content])
  return (
    <div>
      <div className="flex gap-2 mb-2 -mt-2">
        <Button aria-label="Negrito" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleMark(editor as any, 'bold')}><Bold className="h-4 w-4" /></Button>
        <Button aria-label="Itálico" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleMark(editor as any, 'italic')}><Italic className="h-4 w-4" /></Button>
        <Button aria-label="Sublinhado" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleMark(editor as any, 'underline')}><Underline className="h-4 w-4" /></Button>
        <Button aria-label="Título 1" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleBlock(editor as any, 'heading-one')}><Heading1 className="h-4 w-4" /></Button>
        <Button aria-label="Título 2" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleBlock(editor as any, 'heading-two')}><Heading2 className="h-4 w-4" /></Button>
        <Button aria-label="Lista" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleBlock(editor as any, 'bulleted-list')}><List className="h-4 w-4" /></Button>
        <Button aria-label="Código" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => toggleBlock(editor as any, 'code')}><Code className="h-4 w-4" /></Button>
        <Button aria-label="Link" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => { const url = window.prompt('URL'); if (url) wrapLink(editor as any, url) }}><LinkIcon className="h-4 w-4" /></Button>
        <Button aria-label="Limpar formatação" variant="ghost" size="icon" className="h-8 w-8" onMouseDown={(e) => e.preventDefault()} onClick={() => clearFormatting(editor as any)}><X className="h-4 w-4" /></Button>
      </div>
      <div className="relative">
        {isEmpty && (
          <div className="absolute left-3 top-3 text-sm text-muted-foreground pointer-events-none select-none">Escreva sua biografia...</div>
        )}
        <Slate key={version} editor={editor as any} initialValue={content} onChange={(v) => { setContent(v); onChange(serializeToHTML(v)) }}>
          <Editable
            renderElement={renderElement as any}
            renderLeaf={renderLeaf as any}
            onKeyDown={onKeyDown}
            className="w-full min-h-[160px] p-3 text-sm text-foreground bg-background border border-border rounded-md outline-none"
            spellCheck={false}
          />
        </Slate>
      </div>
    </div>
  )
}

/** Os campos editáveis do perfil próprio, no formato do formulário. */
const CAMPOS_EDITAVEIS = [
  'name', 'phone', 'cpf_cnpj', 'cep', 'street', 'number', 'complement', 'district', 'city', 'state',
  'gender', 'birthday', 'cnpj', 'fiscal_document_number', 'fiscal_document_issued_at', 'graduation',
] as const

type CampoEditavel = (typeof CAMPOS_EDITAVEIS)[number]
type ValoresPerfil = Record<CampoEditavel, string>

function valoresDe(u: any): ValoresPerfil {
  return CAMPOS_EDITAVEIS.reduce((acc, chave) => {
    acc[chave] = (u?.[chave] ?? '') as string
    return acc
  }, {} as ValoresPerfil)
}

/**
 * Máscara de CPF/CNPJ **conforme digita**, e o ponto é que ela não trava nada.
 *
 * FE-030: no legado a máscara de CPF era validada no `submit` e reprovava o
 * formulário inteiro. Aqui a máscara só formata; a validação de dígito acontece por
 * campo, no `save`, e o servidor confere de novo (`GET /api/v1/users/validate_cpf`,
 * que agora responde 422/409 em vez de 405/406 — BE-035).
 */
function mascararDocumento(bruto: string): string {
  const d = bruto.replace(/\D/g, '').slice(0, 14)
  if (d.length <= 11) {
    return d
      .replace(/^(\d{3})(\d)/, '$1.$2')
      .replace(/^(\d{3})\.(\d{3})(\d)/, '$1.$2.$3')
      .replace(/^(\d{3})\.(\d{3})\.(\d{3})(\d)/, '$1.$2.$3-$4')
  }
  return d
    .replace(/^(\d{2})(\d)/, '$1.$2')
    .replace(/^(\d{2})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/^(\d{2})\.(\d{3})\.(\d{3})(\d)/, '$1.$2.$3/$4')
    .replace(/^(\d{2})\.(\d{3})\.(\d{3})\/(\d{4})(\d)/, '$1.$2.$3/$4-$5')
}

/** Dígitos verificadores do CPF. Não é formato: é o cálculo. */
function cpfValido(bruto: string): boolean {
  const d = bruto.replace(/\D/g, '')
  if (d.length !== 11 || /^(\d)\1{10}$/.test(d)) return false
  const dv = (ate: number) => {
    let soma = 0
    for (let i = 0; i < ate; i++) soma += Number(d[i]) * (ate + 1 - i)
    const r = (soma * 10) % 11
    return r === 10 ? 0 : r
  }
  return dv(9) === Number(d[9]) && dv(10) === Number(d[10])
}

export function ProfilePage() {
  const user = useAuthStore((s) => s.user)
  const setUser = useAuthStore((s) => s.setUser!)
  const [original, setOriginal] = useState(user)
  const [values, setValues] = useState(() => valoresDe(user))
  // Erro POR CAMPO (FE-030/FE-031). A versão anterior tinha um `validate()` que
  // devolvia **uma** string e abortava o `save` inteiro: um CPF com um dígito a
  // menos impedia de salvar o endereço, a biografia e o nome. Agora cada campo
  // reprova sozinho e diz por quê no lugar dele.
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  // FE-029 — conferindo o documento no servidor enquanto a pessoa digita.
  const [conferindoCpf, setConferindoCpf] = useState(false)
  const [isSaving, setIsSaving] = useState(false)
  const [showActions, setShowActions] = useState(false)
  const fileInputRef = useRef<HTMLInputElement | null>(null)
  const [uploading, setUploading] = useState(false)
  // O avatar sai de `values` de propósito: ele **não** é um campo do `PATCH`
  // (S13/OPS-493 — o valor é uma URL assinada com prazo, e gravá-la na coluna faria
  // o avatar expirar sozinho). Estado próprio para a prévia, e só.
  const [avatarUrl, setAvatarUrl] = useState<string>(user?.avatar_url || '')
  const [bio, setBio] = useState<string>((user as any)?.biography_html || (user as any)?.biography || (user as any)?.biography_text || '')
  // S13 / OPS-493 — o avatar passa pelo motor único de anexos.
  //
  // Regra de fronteira: o endpoint mudou de `/api/v1/uploads/avatar` (gravação
  // crua em `public/uploads`, servida como estático e sem autenticação — o D-82
  // vivo dentro do produto novo) para `/api/v1/users/:id/avatar`, que anexa por
  // ActiveStorage privado. O campo de resposta continua se chamando `avatar_url`,
  // então o resto desta tela não muda.
  //
  // O `if (file.size > 2MB)` local SAIU: o limite é do servidor (3 MB, declarado
  // em `config/attachments.yml`) e ele vinha mentindo — o backend antigo não
  // tinha limite nenhum, e este número não batia com nada.
  const handleAvatarFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    if (!user?.id) { notify.error('Sessão não carregada. Recarregue a página.'); return }
    setUploading(true)
    try {
      const form = new FormData()
      form.append('file', file)
      const data = await apiClient.post<{ avatar_url: string }>(
        `/api/v1/users/${user.id}/avatar`,
        form,
        { headers: { 'Content-Type': 'multipart/form-data' } }
      )
      setAvatarUrl(data.avatar_url)
      setUser({ ...(user as any), avatar_url: data.avatar_url })
      notify.success('Avatar enviado')
    } catch (error: any) {
      // O servidor recusa por tamanho e por conteúdo real do arquivo. A mensagem
      // dele é a que o usuário precisa ler — genérica aqui seria esconder "o
      // arquivo tem 8 MB" atrás de "erro ao enviar".
      notify.error(error?.response?.data?.message || 'Erro ao enviar avatar')
    }
    setUploading(false)
  }

  useEffect(() => {
    authApi.me().then((u) => {
      setOriginal(u)
      setValues(valoresDe(u))
      setAvatarUrl(u.avatar_url || '')
      setBio((u as any).biography_html || (u as any).biography || (u as any).biography_text || '')
      setUser(u)
    }).catch(() => {})
    authService.checkSessionStatus().then((res: any) => {
      if (res?.csrf_token) setCsrfToken(res.csrf_token)
    }).catch(() => {})
  }, [])

  /**
   * Só o que MUDOU vai no `PATCH` (FE-035).
   *
   * `email` saiu desta lista junto com `avatar_url`, e por motivos diferentes:
   *  - `avatar_url` é URL **assinada com prazo** (S13/OPS-493); devolvê-la ao
   *    servidor gravaria uma URL expirada na coluna e o avatar sumiria sozinho
   *    horas depois — falha silenciosa. Quem escreve o avatar é
   *    `POST /api/v1/users/:id/avatar`, e só ele.
   *  - `email` é **canal de login** (DEC-14): trocá-lo aqui, sem provar posse do
   *    endereço novo, é trocar a fechadura pela porta de dentro. Fica em leitura
   *    até existir o fluxo de confirmação do endereço novo.
   */
  const dirtyFields = useMemo(() => {
    const diff: Record<string, any> = {}
    if (!original) return diff
    CAMPOS_EDITAVEIS.forEach((k) => {
      const orig = ((original as any)[k] ?? '') as string
      // Campo esvaziado vai como `null`, não como string vazia: `null` é "apague
      // isto", e o servidor agora sabe a diferença (ver `api/auth/v1/me.rb`). Antes,
      // string vazia limpava campo de texto e **não limpava campo de data**.
      if ((values[k] ?? '') !== orig) diff[k] = values[k] === '' ? null : values[k]
    })
    return diff
  }, [values, original])

  const bioDirty = useMemo(() => {
    const orig = (original as any)?.biography_html || (original as any)?.biography || (original as any)?.biography_text || ''
    return (bio || '') !== (orig || '')
  }, [bio, original])

  const actionsActive = useMemo(() => {
    return Object.keys(dirtyFields).length > 0 || bioDirty
  }, [dirtyFields, bioDirty])

  useEffect(() => {
    if (actionsActive) setShowActions(true)
  }, [actionsActive])

  const canEdit = useMemo(() => {
    return !!user // JWT presente já foi verificado no guard
  }, [user])

  const trocar = (campo: CampoEditavel, valor: string) => {
    setValues((s) => ({ ...s, [campo]: valor }))
    // Digitar no campo limpa o erro DELE, não os outros. Limpar tudo faria a
    // pessoa perder de vista o segundo problema enquanto conserta o primeiro.
    setFieldErrors((e) => (e[campo] ? { ...e, [campo]: '' } : e))
  }

  /**
   * **FE-029 — a validação de CPF em tempo real.**
   *
   * `usersApi.validateCpf` existia em `endpoints.ts:271` e `grep -rn
   * 'validateCpf' src` não achava um consumidor: o endpoint estava pronto e a
   * tela nunca o chamava.
   *
   * A validação LOCAL (`cpfValido`) já rodava no envio, e ela confere os
   * dígitos — mas há uma coisa que só o servidor sabe: **se o documento já
   * está em outra conta** (409, BE-035). Sem esta chamada, a pessoa preenche o
   * formulário inteiro, salva, e só então descobre.
   *
   * Roda no `blur`, não a cada tecla: um CPF meio digitado é sempre inválido, e
   * uma requisição por dígito daria onze respostas erradas antes da certa. Não
   * é polling — quem dispara é o usuário saindo do campo.
   */
  const conferirCpfNoServidor = async (valor: string) => {
    const digitos = valor.replace(/\D/g, '')
    // Vazio é permitido (o campo não é obrigatório), e CNPJ não passa por aqui:
    // o endpoint é de CPF.
    if (digitos.length !== 11) return
    // Não gasta requisição com dígito verificador errado — a conta é local.
    if (!cpfValido(digitos)) return
    // Não incomoda o servidor com o documento que a própria conta já tem.
    if (digitos === (original?.cpf_cnpj || '').replace(/\D/g, '')) return

    setConferindoCpf(true)
    try {
      const resposta = await usersApi.validateCpf(digitos, original?.id)
      if (!resposta.valid) {
        setFieldErrors((e) => ({ ...e, cpf_cnpj: 'Este CPF já está em outra conta.' }))
      }
    } catch {
      // Falha de rede NÃO vira erro de campo: dizer "CPF inválido" porque a
      // requisição caiu seria acusar o dado do usuário de um problema nosso. A
      // validação do envio continua valendo como rede de segurança.
    } finally {
      setConferindoCpf(false)
    }
  }

  const cancelEdit = () => {
    if (!original) return
    setValues(valoresDe(original))
    setBio((original as any)?.biography_html || (original as any)?.biography || (original as any)?.biography_text || '')
    setFieldErrors({})
    notify.info('Alterações canceladas')
    setShowActions(false)
  }

  /**
   * Validação **por campo**. Devolve um mapa, nunca uma string única.
   *
   * FE-030 — este é o ponto da tarefa: no legado (e na versão anterior desta tela)
   * um CPF malformado abortava o `submit` inteiro, então quem tivesse um documento
   * antigo mal gravado não conseguia mais corrigir o próprio endereço. Aqui o
   * documento inválido reprova o documento; o resto salva.
   */
  const validarCampos = (): Record<string, string> => {
    const erros: Record<string, string> = {}

    if (!values.name.trim()) erros.name = 'Informe seu nome.'

    if ('phone' in dirtyFields && values.phone) {
      const d = values.phone.replace(/\D/g, '')
      if (d.length < 10 || d.length > 15) erros.phone = 'Telefone deve ter de 10 a 15 dígitos.'
    }

    if ('cpf_cnpj' in dirtyFields && values.cpf_cnpj) {
      const d = values.cpf_cnpj.replace(/\D/g, '')
      if (d.length === 11) {
        if (!cpfValido(d)) erros.cpf_cnpj = 'CPF inválido — confira os dígitos.'
      } else if (d.length !== 14) {
        erros.cpf_cnpj = 'Informe 11 dígitos (CPF) ou 14 (CNPJ).'
      }
    }

    if ('cnpj' in dirtyFields && values.cnpj && values.cnpj.replace(/\D/g, '').length !== 14) {
      erros.cnpj = 'CNPJ tem 14 dígitos.'
    }

    if ('cep' in dirtyFields && values.cep && !/^\d{5}-?\d{3}$/.test(values.cep)) {
      erros.cep = 'CEP no formato 00000-000.'
    }

    if ('state' in dirtyFields && values.state && !/^[A-Za-z]{2}$/.test(values.state)) {
      erros.state = 'UF tem 2 letras.'
    }

    return erros
  }

  const save = async () => {
    const erros = validarCampos()
    setFieldErrors(erros)
    if (Object.keys(erros).length > 0) {
      notify.error('Confira os campos marcados.')
      return
    }
    if (!Object.keys(dirtyFields).length && !bioDirty) { notify.info('Nada para salvar'); return }
    setIsSaving(true)
    setShowActions(false)
    try {
      let updated = original
      if (Object.keys(dirtyFields).length) {
        updated = await authApi.updateMe(dirtyFields)
        setOriginal(updated)
        setUser(updated)
      }
      if (bioDirty && original?.id) {
        await usersApi.update(original.id, { biography: bio })
        const refetched = await authApi.me()
        setOriginal(refetched)
        setUser(refetched)
      }
      notify.success('Perfil atualizado')
    } catch (e: any) {
      const detalhes = e?.response?.data?.details
      // O servidor devolve `details` como lista de mensagens do model. Elas
      // aparecem no toast porque não há como saber a qual campo cada uma
      // pertence — mas a validação acima já pegou os casos que dá para rotear.
      notify.error(
        Array.isArray(detalhes) && detalhes.length > 0
          ? detalhes.join(' · ')
          : e?.response?.data?.error || e?.message || 'Não foi possível salvar.',
      )
      setShowActions(true)
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <div className="w-full mt-2.5">
      <h1 className="text-2xl font-semibold mb-2 mt-6">Meu Perfil</h1>
      <p className="text-sm text-muted-foreground mb-6">Gerencie suas informações pessoais</p>
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="space-y-6">
          <div className="glass-panel rounded-lg p-6">
            <div className="flex flex-col items-center gap-2">
          <div className="relative">
          <div
            className={`h-24 w-24 rounded-full overflow-hidden border border-border bg-muted ${canEdit ? 'cursor-pointer' : ''}`}
            onClick={canEdit ? () => fileInputRef.current?.click() : undefined}
          >
            <UserAvatar
              name={values.name}
              email={original?.email}
              src={avatarUrl}
              colorKey={original?.id}
              size={96}
              className="border-0"
            />
          </div>
          {canEdit && (
            <Button
              variant="primary"
              size="icon"
              aria-label="Trocar foto de perfil"
              className="absolute -bottom-2 -right-2 h-8 w-8 rounded-full shadow-e2"
              onClick={(e) => { e.stopPropagation(); fileInputRef.current?.click() }}
              disabled={uploading}
            >
              <Upload className="h-4 w-4" />
            </Button>
          )}
          <input ref={fileInputRef} type="file" accept="image/*" onChange={handleAvatarFile} className="hidden" />
        </div>
        <p className="text-sm text-foreground">Foto de perfil</p>
        {/* O número vem do catálogo do servidor (`config/attachments.yml`), que é
            quem reprova. A tela dizia "2MB", que não batia com limite nenhum. */}
        <p className="text-xs text-muted-foreground">JPG, PNG, WEBP ou GIF, até 3 MB</p>
            </div>

            {/* FE-034 — o CÓDIGO, em leitura, com botão de copiar.
                É o `identifier` (BE-048): 6 caracteres que a pessoa dita ao
                suporte por telefone. Ele existia no banco e **não aparecia em
                lugar nenhum** da tela de perfil — quem precisava dele tinha de
                pedir a um OG. */}
            <CampoIdentidade
              rotulo="Seu código"
              valor={original?.identifier || ''}
              ajuda="É o que você informa ao suporte para identificar sua conta."
              copiavel
            />

            {/* FE-029 — o e-mail é LEITURA. Ele é canal de login (DEC-14): trocá-lo
                aqui, sem provar posse do endereço novo, é trocar a fechadura pela
                porta de dentro. */}
            <CampoIdentidade
              rotulo="E-mail de acesso"
              valor={original?.email || ''}
              ajuda="É por aqui que chega seu código de acesso. Para trocar, fale com um administrador."
            />

            {original?.confiability_level && (
              <CampoIdentidade
                rotulo="Verificação"
                valor={rotuloDeVerificacao(original.confiability_level) ?? ''}
                ajuda={
                  original.is_phone_checked
                    ? 'Telefone confirmado.'
                    : 'Confirme seu telefone para subir de nível.'
                }
              />
            )}
          </div>

          <div className="glass-panel rounded-lg p-6">
          <div className="flex items-center gap-2 mb-3">
            <div className="h-6 w-6 rounded-md bg-muted flex items-center justify-center"><Shield className="h-4 w-4" /></div>
            <p className="font-medium">Biografia</p>
          </div>
          <div className="space-y-2">
              <label className="block text-sm text-muted-foreground">Biografia</label>
              <RichTextEditor value={bio} onChange={setBio} />
          </div>
        </div>
        </div>

        <div className="space-y-6">
          <div className="glass-panel rounded-lg p-6">
            <div className="flex items-center gap-2 mb-4">
              <div className="h-6 w-6 rounded-md bg-muted flex items-center justify-center"><User className="h-4 w-4" /></div>
              <p className="font-medium">Informações Pessoais</p>
            </div>
            <div className="space-y-5">
              <Field
                label="Nome"
                value={values.name}
                erro={fieldErrors.name}
                placeholder="Seu nome completo"
                onChange={(v) => trocar('name', v)}
              />

              {/* FE-031 — máscara dinâmica de 8/9 dígitos, com DDI e DDD.
                  O `PhoneInputGroup` já monta `(48) 9 9999-9999` conforme digita e
                  devolve o número normalizado.

                  **O campo é EDITÁVEL mesmo com o telefone confirmado** (DEC-74).
                  No legado, `is_phone_checked = 1` deixava o input `readonly` para
                  sempre; aqui o telefone é canal de login e travá-lo deixaria quem
                  trocou de número sem acesso e sem autoatendimento. */}
              <div className="space-y-1.5">
                <label className="block text-sm text-muted-foreground">WhatsApp</label>
                <PhoneInputGroup value={values.phone} onChange={(v) => trocar('phone', v)} allowErase />
                {fieldErrors.phone && <p role="alert" className="text-xs text-destructive">{fieldErrors.phone}</p>}
              </div>

              <Field
                label="CPF/CNPJ"
                value={values.cpf_cnpj}
                erro={fieldErrors.cpf_cnpj}
                placeholder="000.000.000-00"
                inputMode="numeric"
                // FE-030 — a máscara formata; ela NÃO trava o formulário. O
                // documento inválido reprova o documento, e o resto salva.
                onChange={(v) => trocar('cpf_cnpj', mascararDocumento(v))}
                // FE-029 — ao sair do campo, o servidor diz o que a conta local
                // não sabe: se este CPF já está em OUTRA conta.
                onBlur={conferirCpfNoServidor}
                carregando={conferindoCpf}
              />

              <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
                <div className="space-y-1.5">
                  <label className="block text-sm text-muted-foreground">Gênero</label>
                  {/* Enum, não texto livre: no legado era string aberta, e o dado
                      de produção tinha grafias diferentes para a mesma coisa. */}
                  <Select
                    aria-label="Gênero"
                    value={values.gender || ''}
                    onChange={(v) => trocar('gender', v)}
                    options={[
                      { value: '', label: 'Não informar' },
                      { value: 'female', label: 'Feminino' },
                      { value: 'male', label: 'Masculino' },
                      { value: 'other', label: 'Outro' },
                      { value: 'undisclosed', label: 'Prefiro não dizer' },
                    ]}
                  />
                </div>
                <div className="space-y-1.5">
                  <label className="block text-sm text-muted-foreground">Aniversário</label>
                  {/* `type="date"` porque a coluna é `date`. No legado era string,
                      e comparar idade dependia de parse dentro da view. */}
                  <Input
                    type="date"
                    value={values.birthday || ''}
                    onChange={(e) => trocar('birthday', e.target.value)}
                  />
                </div>
              </div>

              <Field
                label="CNPJ (pessoa jurídica)"
                value={values.cnpj}
                erro={fieldErrors.cnpj}
                placeholder="00.000.000/0000-00"
                inputMode="numeric"
                onChange={(v) => trocar('cnpj', mascararDocumento(v))}
              />

              <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
                <Field
                  label="Documento fiscal (RG/CNH)"
                  value={values.fiscal_document_number}
                  placeholder="Número do documento"
                  onChange={(v) => trocar('fiscal_document_number', v)}
                />
                <div className="space-y-1.5">
                  <label className="block text-sm text-muted-foreground">Emitido em</label>
                  {/* Data REAL. O legado guardava string e aceitava "00/00/0000". */}
                  <Input
                    type="date"
                    value={values.fiscal_document_issued_at || ''}
                    onChange={(e) => trocar('fiscal_document_issued_at', e.target.value)}
                  />
                </div>
              </div>

              <Field
                label="Escolaridade"
                value={values.graduation}
                placeholder="ex: Ensino superior completo"
                onChange={(v) => trocar('graduation', v)}
              />
            </div>
          </div>
        </div>

        <div className="space-y-6">
          <div className="glass-panel rounded-lg p-6">
            <div className="flex items-center gap-2 mb-4">
              <div className="h-6 w-6 rounded-md bg-muted flex items-center justify-center"><MapPin className="h-4 w-4" /></div>
              <p className="font-medium">Endereço</p>
            </div>
            <div className="space-y-6">
              <Field label="CEP" value={values.cep} erro={fieldErrors.cep} placeholder="00000-000" inputMode="numeric" onChange={(v) => trocar('cep', v)} />
              <Field label="Rua/Avenida" value={values.street} placeholder="ex: Avenida Paulista" onChange={(v) => trocar('street', v)} />
              <Field label="Número" value={values.number} placeholder="ex: 1000" onChange={(v) => trocar('number', v)} />
              <Field label="Complemento" value={values.complement} placeholder="ex: Apto 123" onChange={(v) => trocar('complement', v)} />
              <Field label="Bairro" value={values.district} placeholder="ex: Centro" onChange={(v) => trocar('district', v)} />
              <Field label="Cidade" value={values.city} placeholder="ex: São Paulo" onChange={(v) => trocar('city', v)} />
              <Field label="Estado" value={values.state} erro={fieldErrors.state} placeholder="UF (ex: SP)" onChange={(v) => trocar('state', v.toUpperCase())} />
            </div>
          </div>
        </div>

        {/* Ocupa a largura inteira: a lista de aceites tem tipo, versão, data e
            a etiqueta que distingue o aceite dado do carimbado (DEC-66) — na
            coluna estreita do endereço o nome do contrato ficava truncado, e
            um documento jurídico com o nome cortado não serve de histórico. */}
        <div className="lg:col-span-3">
          <MyTermsSection />
        </div>

        {/* FE-033 — encerrar a própria conta. Ver a nota do componente. */}
        <div className="lg:col-span-3">
          <EncerrarContaSection />
        </div>

        <FloatingActions
          active={actionsActive && showActions}
          onSave={save}
          onCancel={cancelEdit}
          isSaving={isSaving}
        />
      </div>
    </div>
  )
}

/**
 * Campo editável com **mensagem de erro do próprio campo** (FE-030/FE-031).
 *
 * A mensagem fica debaixo do campo, e não num `toast`: o toast some em 4 segundos
 * e não diz onde clicar. `role="alert"` + `aria-invalid` fecham o par para o leitor
 * de tela.
 */
function Field({ label, value, onChange, placeholder, erro, inputMode, onBlur, carregando }: {
  label: string
  value: string
  onChange: (v: string) => void
  placeholder?: string
  erro?: string
  inputMode?: 'text' | 'numeric' | 'tel' | 'email'
  /** FE-029 — conferência no servidor ao sair do campo. */
  onBlur?: (v: string) => void
  /** Enquanto a conferência roda. Aparece como texto, não como spinner: o campo
      continua utilizável e a pessoa não fica esperando para digitar o resto. */
  carregando?: boolean
}) {
  return (
    <div className="space-y-1.5">
      <label className="block text-sm text-muted-foreground">{label}</label>
      <Input
        value={value ?? ''}
        onChange={(e) => onChange(e.target.value)}
        onBlur={onBlur ? (e) => onBlur(e.target.value) : undefined}
        placeholder={placeholder}
        inputMode={inputMode}
        aria-invalid={!!erro}
        aria-busy={carregando || undefined}
      />
      {erro && <p role="alert" className="text-xs text-destructive">{erro}</p>}
      {!erro && carregando && <p className="text-xs text-muted-foreground">Conferindo…</p>}
    </div>
  )
}

/**
 * Campo de **identidade**: mostra, não deixa editar, e explica por quê.
 *
 * Somente-leitura aqui não é falta de recurso — é decisão. O e-mail e o código são
 * o que identifica a conta; o legado deixava o e-mail editável no mesmo formulário
 * do endereço, sem confirmação nenhuma do endereço novo.
 */
function CampoIdentidade({ rotulo, valor, ajuda, copiavel }: {
  rotulo: string
  valor: string
  ajuda?: string
  copiavel?: boolean
}) {
  if (!valor) return null

  return (
    <div className="mt-4 w-full space-y-1 border-t border-border pt-3">
      <p className="text-xs uppercase tracking-wider text-muted-foreground">{rotulo}</p>
      <div className="flex items-center gap-2">
        <span className="min-w-0 flex-1 truncate font-numeric text-sm text-foreground">{valor}</span>
        {/* A lógica de copiar saiu daqui para `components/ui/CopyButton`: o
            FE-017 precisou dela no detalhe de OUTRA conta, e copiar o código de
            copiar seria a segunda definição de quando mostrar o "copiado" e do
            que dizer quando o navegador recusa. */}
        {copiavel && <CopyButton value={valor} label={rotulo} />}
      </div>
      {ajuda && <p className="text-xs text-muted-foreground">{ajuda}</p>}
    </div>
  )
}

function FloatingActions({ active, onSave, onCancel, isSaving }: {
  active: boolean
  onSave: () => void
  onCancel: () => void
  isSaving: boolean
}) {
  const [render, setRender] = useState(active)
  const [visible, setVisible] = useState(false)
  useEffect(() => {
    if (active) {
      setRender(true)
      const t = setTimeout(() => setVisible(true), 10)
      return () => clearTimeout(t)
    } else {
      setVisible(false)
      const t = setTimeout(() => setRender(false), 300)
      return () => clearTimeout(t)
    }
  }, [active])
  if (!render) return null
  return (
    <div className="fixed inset-x-0 bottom-6 z-fab" data-helper>
      <div className={`helper-fab absolute bottom-0 left-1/2 -translate-x-1/2 flex items-center gap-2 transition-all duration-300 ${visible ? 'ease-out opacity-100 translate-y-0' : 'ease-in opacity-0 translate-y-4'}`}>
        <Button onClick={onSave} disabled={isSaving} variant="primary" className="px-3.5 py-1.5 text-sm h-10">
          <span className="inline-flex items-center gap-1">
            <Check className="h-4 w-4" /> SALVAR
          </span>
        </Button>
        <Button onClick={onCancel} variant="secondary" className="px-3.5 py-1.5 text-sm h-10">
          <span className="inline-flex items-center gap-1">
            <X className="h-4 w-4" /> CANCELAR
          </span>
        </Button>
      </div>
    </div>
  )
}

/**
 * **Encerrar a própria conta** — FE-033 / BE-014 / IMP-A7.
 *
 * ## O que o legado tinha, e por que não servia
 *
 * Três defeitos numa função só:
 *
 *  1. **Não havia modal de confirmação.** O clique apagava. A tarefa pede
 *     "confirmação **de verdade**" justamente porque a do legado não existia.
 *  2. **O gate era `may_create_users?`** — permissão de **criar** usuários. Quem
 *     não podia criar não conseguia sair do sistema, e quem podia criar via o botão
 *     de apagar a própria conta como se fosse ação administrativa.
 *  3. **A confirmação, quando existia no fluxo equivalente, era por SENHA.** Este
 *     produto não tem senha (DEC-14).
 *
 * ## Como funciona aqui
 *
 * Dois passos, e o segundo prova posse do canal cadastrado: a pessoa pede o código
 * (`POST /auth/v1/magic_login/request_code`, o **mesmo** código de acesso), recebe
 * por e-mail ou WhatsApp e o digita. O `DELETE /api/v1/users/:id` só apaga com um
 * `LoginCode` válido e não usado (`UsersService#valid_self_removal_code?`), e ele é
 * consumido no ato.
 *
 * **A auto-remoção não passa pela matriz de autorização**, e isso é deliberado: a
 * matriz responde "pode remover CONTAS", que é poder administrativo. Remover a
 * própria conta é direito do titular — sem essa exceção o Colaborador, o papel mais
 * numeroso, não conseguiria sair. O código já prova quem é.
 *
 * **Conta dona de projeto responde 409**, com instrução: transferir a propriedade
 * antes. Apagar em cascata levaria o projeto junto.
 */
function EncerrarContaSection() {
  const user = useAuthStore((s) => s.user)
  const [aberto, setAberto] = useState(false)
  const [codigo, setCodigo] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [pedindo, setPedindo] = useState(false)
  const [codigoPedido, setCodigoPedido] = useState(false)

  // O destino é o canal cadastrado — mostrado para a pessoa saber ONDE olhar.
  const destino = user?.email || user?.phone || ''
  const canal: 'email' | 'whatsapp' = user?.email ? 'email' : 'whatsapp'

  const pedirCodigo = async () => {
    if (!destino) {
      notify.error('Sua conta não tem e-mail nem telefone — fale com um administrador.')
      return
    }
    setPedindo(true)
    try {
      await authApi.requestMagicCode(destino, canal)
      setCodigoPedido(true)
      notify.success(`Código enviado para ${destino}`)
    } catch (e: any) {
      notify.error(e?.response?.data?.message || 'Não consegui enviar o código.')
    } finally {
      setPedindo(false)
    }
  }

  const encerrar = async () => {
    if (!user?.id) return
    if (codigo.replace(/\D/g, '').length !== 6) {
      notify.error('O código tem 6 dígitos.')
      return
    }
    setEnviando(true)
    try {
      await usersApi.delete(user.id, codigo.replace(/\D/g, ''))
      notify.success('Sua conta foi encerrada.')
      // Sessão inteira embora: os cookies HttpOnly continuariam vivos, e a
      // próxima rota protegida tentaria restaurar uma sessão de conta apagada.
      try { await authService.logout() } catch { /* a conta já não existe */ }
      clearTokens()
      useAuthStore.getState().logout()
      window.location.href = '/login'
    } catch (e: any) {
      const status = e?.response?.status
      notify.error(
        status === 409
          ? 'Esta conta é dona de um ou mais projetos. Transfira a propriedade antes de encerrá-la.'
          : e?.response?.data?.message || 'Código inválido ou expirado. Peça um novo.',
      )
    } finally {
      setEnviando(false)
    }
  }

  return (
    <section className="rounded-lg border border-destructive/30 bg-destructive/5 p-6">
      <div className="flex items-start gap-3">
        <AlertTriangle aria-hidden="true" className="mt-0.5 h-5 w-5 shrink-0 text-destructive" />
        <div className="min-w-0 flex-1">
          <h2 className="text-sm font-semibold text-foreground">Encerrar minha conta</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Você perde o acesso imediatamente e a ação não pode ser desfeita. O que você lançou continua
            registrado na trilha de auditoria, em nome do seu usuário.
          </p>

          {!aberto ? (
            <Button variant="destructive" className="mt-4" onClick={() => setAberto(true)}>
              <Trash2 aria-hidden="true" className="mr-1.5 h-4 w-4" />
              Encerrar minha conta
            </Button>
          ) : (
            <div className="mt-4 space-y-3 rounded-md border border-border bg-card p-4">
              <p className="text-sm text-card-foreground">
                Para confirmar, envie um código para <span className="font-medium">{destino || 'seu canal cadastrado'}</span>{' '}
                e digite-o abaixo. É o mesmo código que você usa para entrar.
              </p>

              <div className="flex flex-wrap items-end gap-2">
                <Button variant="secondary" onClick={pedirCodigo} disabled={pedindo || !destino}>
                  {pedindo ? 'Enviando…' : codigoPedido ? 'Enviar de novo' : 'Enviar código'}
                </Button>

                <div className="min-w-[10rem] flex-1 space-y-1.5">
                  <label htmlFor="codigo-encerrar" className="block text-xs text-muted-foreground">
                    Código de 6 dígitos
                  </label>
                  <Input
                    id="codigo-encerrar"
                    value={codigo}
                    inputMode="numeric"
                    maxLength={6}
                    placeholder="000000"
                    className="font-numeric"
                    onChange={(e) => setCodigo(e.target.value.replace(/\D/g, '').slice(0, 6))}
                  />
                </div>
              </div>

              <div className="flex flex-wrap justify-end gap-2 pt-1">
                <Button variant="secondary" onClick={() => { setAberto(false); setCodigo(''); setCodigoPedido(false) }}>
                  Cancelar
                </Button>
                <Button variant="destructive" onClick={encerrar} disabled={enviando || codigo.length !== 6}>
                  {enviando ? 'Encerrando…' : 'Confirmar encerramento'}
                </Button>
              </div>
            </div>
          )}
        </div>
      </div>
    </section>
  )
}
