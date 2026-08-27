import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Campo, CampoAtivo, CampoTexto } from '@/app/pages/catalogs/CatalogFields'
import { Select } from '@/components/ui/Select'
import { DatePicker } from '@/components/ui/DatePicker'
import { Autocomplete } from '@/components/ui/Autocomplete'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { Button } from '@/components/ui/Button'
import RichTextEditor from '@/components/RichTextEditor'
import { ScopedLogoField } from './ScopedLogoField'
import { brStatesApi, segmentsApi, subSegmentsApi } from '@/lib/api/catalogs'
import { projectsApi, type Project } from '@/lib/api/projects'

/**
 * **O formulário do projeto** (FE-085..FE-089, FE-099).
 *
 * Cinco coisas que o legado fazia e que não voltam:
 *
 * 1. **A chave e o slug não são editáveis.** Eram, e o `set_smart_id` recalculava
 *    o slug em todo `before_validation`: renomear o projeto trocava as URLs
 *    (DC-17). Aqui os dois são derivados na criação e congelados — a tela os
 *    mostra, em cinza, para que ninguém procure onde editar.
 * 2. **UMA cidade.** O legado tinha `city` e `address_city`; o formulário
 *    escrevia numa e o endereço formatado lia a outra (**D-124**).
 * 3. **A escolha do responsável é explícita** e tem três modos, como no legado —
 *    mas o modo "criar" **envia link de convite**, não senha em texto plano
 *    (D-38). O seletor busca no SERVIDOR (`Autocomplete` com `onSearch`), porque
 *    a base de usuários não cabe num select carregado de uma vez.
 * 4. **A data de baixa é `dd/mm/aaaa`** com máscara e vai como data de verdade.
 * 5. **A observação é o `RichTextEditor` da base** — `reuse` puro, nenhum
 *    componente novo: ele fala HTML nos dois sentidos e casa exatamente com o
 *    `availability_note_html` do ActionText.
 */
export interface ProjectFormValues {
  name: string
  is_active: boolean
  segment_id: string | null
  sub_segment_id: string | null
  address_type: string
  address: string
  address_number: string
  address_complement: string
  neighborhood: string
  cep: string
  address_state: string | null
  address_city: string
  closing_date: string
  availability_note: string
  responsible_mode: 'none' | 'existing' | 'new'
  responsible_user_id?: string | null
  responsible_name: string
  responsible_email: string
}

export function valoresIniciais(): ProjectFormValues {
  return {
    name: '',
    is_active: true,
    segment_id: null,
    sub_segment_id: null,
    address_type: '',
    address: '',
    address_number: '',
    address_complement: '',
    neighborhood: '',
    cep: '',
    address_state: null,
    address_city: '',
    closing_date: '',
    availability_note: '',
    responsible_mode: 'none',
    responsible_user_id: null,
    responsible_name: '',
    responsible_email: '',
  }
}

export function doProjeto(p: Project): ProjectFormValues {
  return {
    name: p.name,
    is_active: p.is_active,
    segment_id: p.segment_id,
    sub_segment_id: p.sub_segment_id,
    address_type: p.address_type ?? '',
    address: p.address ?? '',
    address_number: p.address_number ?? '',
    address_complement: p.address_complement ?? '',
    neighborhood: p.neighborhood ?? '',
    cep: p.cep ?? '',
    address_state: p.address_state,
    address_city: p.address_city ?? '',
    closing_date: p.closing_date ?? '',
    availability_note: p.availability_note_html ?? '',
    responsible_mode: p.responsible_id ? 'existing' : 'none',
    responsible_user_id: p.responsible_id,
    responsible_name: p.responsible_name ?? '',
    responsible_email: p.responsible_email ?? '',
  }
}

const MODOS: { value: ProjectFormValues['responsible_mode']; label: string; description: string }[] = [
  { value: 'none', label: 'Sem responsável com conta', description: 'Guarda só nome e e-mail, como referência.' },
  { value: 'existing', label: 'Indicar alguém que já tem conta', description: 'A posse do projeto passa a ser dessa pessoa.' },
  { value: 'new', label: 'Criar a conta do responsável', description: 'A pessoa recebe um link para definir a própria entrada.' },
]

export function ProjectForm({
  values,
  onChange,
  editing,
}: {
  values: ProjectFormValues
  onChange: (v: ProjectFormValues) => void
  editing: Project | null
}) {
  const [termoResponsavel, setTermoResponsavel] = useState('')

  const set = <K extends keyof ProjectFormValues>(campo: K, valor: ProjectFormValues[K]) =>
    onChange({ ...values, [campo]: valor })

  const segmentos = useQuery({
    queryKey: ['segments', 'ativos'],
    queryFn: () => segmentsApi.list({ active: true, perPage: 100 }),
  })
  const subsegmentos = useQuery({
    queryKey: ['sub-segments', 'ativos'],
    queryFn: () => subSegmentsApi.list({ active: true, perPage: 100 }),
  })
  // UF vem do servidor (`GET /api/v1/br_states`) — é cadastro, não
  // geocodificação: a gem `geocoder` do legado não foi portada (DEC-92).
  const ufs = useQuery({ queryKey: ['br-states'], queryFn: () => brStatesApi.list() })

  const candidatos = useQuery({
    queryKey: ['responsible-candidates', termoResponsavel],
    queryFn: () => projectsApi.responsibleCandidates(termoResponsavel || undefined),
    enabled: values.responsible_mode === 'existing',
  })

  return (
    <div className="space-y-5">
      <CampoTexto
        id="name"
        label="Nome do projeto"
        value={values.name}
        onChange={(v) => set('name', v)}
        placeholder="Ex.: Residencial Jardim das Acácias"
        hint="Único no sistema. É dele que saem a chave de integração e o endereço da URL."
        autoFocus
      />

      {editing && (
        <div className="grid gap-3 sm:grid-cols-2">
          <Campo
            id="slug"
            label="Endereço (slug)"
            hint="Congelado na criação: renomear o projeto não muda a URL."
          >
            <Input id="slug" value={editing.slug} readOnly disabled className="font-numeric" />
          </Campo>
          <Campo
            id="integration_key"
            label="Chave de integração"
            hint="Congelada na criação — pode estar em uso por um sistema externo."
          >
            <Input id="integration_key" value={editing.integration_key} readOnly disabled className="font-numeric" />
          </Campo>
        </div>
      )}

      <div className="grid gap-3 sm:grid-cols-2">
        <Campo id="segment_id" label="Segmento">
          <Select
            id="segment_id"
            options={(segmentos.data?.items ?? []).map((s) => ({ value: s.id, label: s.title }))}
            value={values.segment_id}
            onChange={(v) => set('segment_id', v)}
            placeholder="Selecione…"
          />
        </Campo>
        <Campo
          id="sub_segment_id"
          label="Subsegmento"
          hint="Catálogo INDEPENDENTE do segmento — não é uma lista filha (DC-13)."
        >
          <Select
            id="sub_segment_id"
            options={(subsegmentos.data?.items ?? []).map((s) => ({ value: s.id, label: s.title }))}
            value={values.sub_segment_id}
            onChange={(v) => set('sub_segment_id', v)}
            placeholder="Selecione…"
          />
        </Campo>
      </div>

      <fieldset className="space-y-3 rounded-md border border-border p-3">
        <legend className="px-1 text-xs font-semibold uppercase tracking-[0.05em] text-muted-foreground">
          Endereço
        </legend>

        <div className="grid gap-3 sm:grid-cols-[8rem,1fr,6rem]">
          <CampoTexto id="address_type" label="Tipo" value={values.address_type} onChange={(v) => set('address_type', v)} placeholder="Rua" />
          <CampoTexto id="address" label="Logradouro" value={values.address} onChange={(v) => set('address', v)} />
          <CampoTexto id="address_number" label="Número" value={values.address_number} onChange={(v) => set('address_number', v)} placeholder="s/n" />
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <CampoTexto id="address_complement" label="Complemento" value={values.address_complement} onChange={(v) => set('address_complement', v)} />
          <CampoTexto id="neighborhood" label="Bairro" value={values.neighborhood} onChange={(v) => set('neighborhood', v)} />
        </div>

        <div className="grid gap-3 sm:grid-cols-[10rem,1fr,8rem]">
          <Campo id="cep" label="CEP">
            <Input
              id="cep"
              className="font-numeric"
              inputMode="numeric"
              value={values.cep}
              onChange={(e) => set('cep', e.target.value)}
              placeholder="00000-000"
            />
          </Campo>
          <CampoTexto id="address_city" label="Cidade" value={values.address_city} onChange={(v) => set('address_city', v)} />
          <Campo id="address_state" label="UF">
            <Select
              id="address_state"
              options={(ufs.data ?? []).map((u) => ({ value: u.code, label: u.code, text: u.name, description: u.name }))}
              value={values.address_state}
              onChange={(v) => set('address_state', v)}
              placeholder="UF"
            />
          </Campo>
        </div>
      </fieldset>

      {editing && (
        <div className="space-y-1.5">
          <Label htmlFor="avatar">Logo do projeto</Label>
          {/* FE-087 — a escolha SOBREVIVE a erro de validação em outro campo: o
              upload é requisição própria e já persistiu. No legado o
              `ajax:error` de qualquer campo resetava o input de arquivo. */}
          <ScopedLogoField
            record={editing}
            api={projectsApi}
            currentUrl={editing.avatar_url}
            urlOf={(p) => p.avatar_url}
            limiteMb={5}
            queryKeys={['projects', 'project']}
            placeholder="Enviar logo do projeto"
          />
        </div>
      )}

      <Campo id="closing_date" label="Data de baixa" hint="Informativa. Formato dd/mm/aaaa.">
        <DatePicker
          id="closing_date"
          value={values.closing_date || null}
          onChange={(d) => set('closing_date', d ? d.toISOString().slice(0, 10) : '')}
          clearable
        />
      </Campo>

      {!editing && (
        <fieldset className="space-y-3 rounded-md border border-border p-3">
          <legend className="px-1 text-xs font-semibold uppercase tracking-[0.05em] text-muted-foreground">
            Responsável
          </legend>

          <div className="flex flex-wrap gap-2">
            {MODOS.map((m) => (
              <Button
                key={m.value}
                type="button"
                variant={values.responsible_mode === m.value ? 'primary' : 'secondary'}
                size="sm"
                onClick={() => set('responsible_mode', m.value)}
              >
                {m.label}
              </Button>
            ))}
          </div>
          <p className="text-xs text-muted-foreground">
            {MODOS.find((m) => m.value === values.responsible_mode)?.description}
          </p>

          {values.responsible_mode === 'existing' && (
            <Campo
              id="responsible_user_id"
              label="Quem responde pelo projeto"
              hint="A lista já vem filtrada pela sua hierarquia — você não indica alguém com poder maior que o seu."
            >
              <Autocomplete
                aria-label="Buscar responsável"
                options={(candidatos.data ?? []).map((u) => ({ id: u.id, label: u.name, subtitle: u.email }))}
                value={values.responsible_user_id ?? null}
                onChange={(id) => set('responsible_user_id', id)}
                onSearch={setTermoResponsavel}
                loading={candidatos.isFetching}
                placeholder="Buscar por nome ou e-mail…"
                emptyMessage="Nenhuma conta encontrada com esse termo."
              />
            </Campo>
          )}

          {values.responsible_mode === 'new' && (
            <>
              <CampoTexto id="responsible_name" label="Nome" value={values.responsible_name} onChange={(v) => set('responsible_name', v)} />
              <CampoTexto
                id="responsible_email"
                label="E-mail"
                value={values.responsible_email}
                onChange={(v) => set('responsible_email', v)}
                hint="A pessoa recebe um link de uso único para definir a própria entrada. Nenhuma senha é criada, exibida ou enviada."
              />
            </>
          )}

          {values.responsible_mode === 'none' && (
            <div className="grid gap-3 sm:grid-cols-2">
              <CampoTexto id="responsible_name" label="Nome (referência)" value={values.responsible_name} onChange={(v) => set('responsible_name', v)} />
              <CampoTexto id="responsible_email" label="E-mail (referência)" value={values.responsible_email} onChange={(v) => set('responsible_email', v)} />
            </div>
          )}
        </fieldset>
      )}

      <div className="space-y-1.5">
        <Label htmlFor="availability_note">Observação · Disponibilidade</Label>
        {/* `reuse` puro: o editor da base fala HTML nos dois sentidos e casa
            com o `availability_note_html` do ActionText. **Anexo é recusado no
            servidor** — o legado bloqueava só no cliente. */}
        <RichTextEditor
          value={values.availability_note}
          onChange={(v) => set('availability_note', v)}
          placeholder="Combinados de fechamento, prazos, quem confere…"
        />
        <p className="text-xs text-muted-foreground">
          Texto com formatação. Anexos não são aceitos neste campo.
        </p>
      </div>

      <CampoAtivo
        value={values.is_active}
        onChange={(v) => set('is_active', v)}
        descricao="Projeto inativo continua com o histórico, mas sai das listas de escolha."
      />
    </div>
  )
}
