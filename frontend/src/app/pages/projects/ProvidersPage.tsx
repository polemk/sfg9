import { useState } from 'react'
import { useMutation } from '@tanstack/react-query'
import { Search, Loader2 } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { notify } from '@/lib/notify'
import { CatalogScreen } from '@/app/pages/catalogs/CatalogScreen'
import { CampoAtivo, CampoTexto } from '@/app/pages/catalogs/CatalogFields'
import { ProviderDocumentField } from './ProviderDocumentField'
import { ScopedLogoField, enviarLogoPendente } from './ScopedLogoField'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { Button } from '@/components/ui/Button'
import { UserAvatar } from '@/components/ui/UserAvatar'
import { Label } from '@/components/ui/Label'
import { apiClient } from '@/lib/api/client'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { providersApi, type DocumentType, type Provider } from '@/lib/api/projects'

/** O que `GET /api/v1/cnpj/:cnpj` devolve — forma NORMALIZADA, não o corpo cru. */
interface CnpjLookup {
  data: {
    cnpj: string
    name: string | null
    trade_name: string | null
    status: string | null
    opened_at: string | null
    email: string | null
    phone: string | null
    zip_code: string | null
    street: string | null
    number: string | null
    complement: string | null
    district: string | null
    city: string | null
    state: string | null
    main_activity: string | null
    secondary_activities: string[]
  }
  remaining_quota: number
}

/**
 * **Fornecedores** (FE-069..FE-074) — a contraparte das renegociações.
 *
 * O que muda em relação ao legado:
 *
 * - **O detalhe passa a existir** (D-22): no legado clicar na linha não levava
 *   a lugar nenhum, porque a view de detalhe nunca foi escrita.
 * - **O autopreenchimento por CNPJ volta a funcionar** (D-27 / DEC-46). Estava
 *   morto por DUAS pontas: o botão estava comentado no HTML e a URL do JS tinha
 *   o ERB escapado (`<%%=`), de modo que a requisição ia para um literal. Agora
 *   ele consulta `GET /api/v1/cnpj/:cnpj`, com **teto por usuário/dia** — a
 *   consulta é paga e o custo é do cliente.
 * - **DC-07 — "relações de fornecedor" não é portado**: o handler apontava para
 *   um seletor que não existia no DOM. Ação inerte é pior que ação ausente.
 * - **Iniciais quando não há logo** (FE-070). O legado testava
 *   `logo_file_name != "missing.jpg"` — a string literal era o valor de
 *   "sem arquivo", e um fornecedor que chamasse o arquivo assim ficava sem logo.
 */
export function ProvidersPage() {
  const navigate = useNavigate()
  // DEC-136 — o logo escolhido na criacao, a espera do id.
  const [logoPendente, setLogoPendente] = useState<File | null>(null)

  return (
    <CatalogScreen<Provider>
      queryKey="providers"
      api={providersApi}
      // FE-070 — clicar na linha ABRE o detalhe. No legado a linha não levava a
      // lugar nenhum (D-22): a view de detalhe nunca foi escrita.
      onRowClick={(p) => navigate(`/providers/${p.id}`)}
      writeRoles={ALL_ROLES}
      texts={{
        title: 'Fornecedores',
        subtitle: 'Contrapartes das renegociações deste projeto.',
        singular: 'fornecedor',
        createLabel: 'Novo fornecedor',
        emptyTitle: 'Nenhum fornecedor cadastrado',
        emptyDescription:
          'O fornecedor é quem recebe numa renegociação. Cadastre o primeiro para começar a lançar.',
        searchPlaceholder: 'Buscar por nome, chave ou documento…',
        scopeResource: 'os fornecedores',
      }}
      columns={[
        {
          key: 'title',
          header: 'Fornecedor',
          sortable: true,
          accessor: (p) => p.title,
          cell: (p) => (
            <span className="flex items-center gap-2">
              <UserAvatar name={p.title} src={p.logo_url ?? undefined} size={28} />
              <span className="truncate">{p.title}</span>
            </span>
          ),
        },
        {
          key: 'document',
          header: 'Documento',
          sortable: true,
          accessor: (p) => p.document ?? '',
          cell: (p) => <span className="font-numeric text-xs">{p.formatted_document}</span>,
        },
        {
          key: 'key',
          header: 'Chave de integração',
          sortable: true,
          accessor: (p) => p.integration_key,
          cell: (p) => <code className="font-numeric text-xs text-muted-foreground">{p.integration_key}</code>,
        },
        {
          key: 'renegotiations_count',
          header: 'Renegociações',
          variant: 'number',
          accessor: (p) => p.renegotiations_count,
        },
      ]}
      mobileFields={(p) => [
        { label: 'Documento', value: <span className="font-numeric text-xs">{p.formatted_document}</span> },
        {
          label: 'Renegociações',
          value: <span className="font-numeric tabular-nums">{p.renegotiations_count}</span>,
        },
        { label: 'Situação', value: p.is_active ? 'Ativo' : 'Inativo' },
      ]}
      usageCount={(p) => p.renegotiations_count}
      usageLabel={(p) =>
        p.renegotiations_count === 1
          ? '1 renegociação usa este fornecedor — não é possível excluir'
          : `${p.renegotiations_count} renegociações usam este fornecedor — não é possível excluir`
      }
      emptyForm={() => ({ title: '', is_active: true, document_type: null, document: '' })}
      toForm={(p) => ({
        title: p.title,
        resume: p.resume ?? '',
        integration_key: p.integration_key,
        is_active: p.is_active,
        document_type: p.document_type,
        document: p.document ?? '',
      })}
      afterCreate={async (criado) => {
        // DEC-136 — o segundo passo. Falhar aqui não desfaz o cadastro.
        await enviarLogoPendente(providersApi, criado.id, logoPendente)
        setLogoPendente(null)
      }}
      form={({ values, setValue, editing }) => (
        <FormularioFornecedor values={values} setValue={setValue} editing={editing}
                              onLogoPendente={setLogoPendente} />
      )}
    />
  )
}

function FormularioFornecedor({
  values,
  setValue,
  editing,
  onLogoPendente,
}: {
  values: Record<string, any>
  setValue: (campo: string, valor: unknown) => void
  editing: Provider | null
  /** DEC-136 — o logo escolhido na criação, à espera do id. */
  onLogoPendente?: (file: File | null) => void
}) {
  const [restante, setRestante] = useState<number | null>(null)

  const consultar = useMutation({
    mutationFn: (cnpj: string) => apiClient.get<CnpjLookup>(`/api/v1/cnpj/${cnpj}`),
    onSuccess: (resposta) => {
      const d = resposta.data
      // O título só é sobrescrito quando está vazio: quem já digitou um apelido
      // interno não quer perdê-lo para a razão social do cadastro federal.
      if (!values.title) setValue('title', d.trade_name || d.name || '')
      setValue('legal_name', d.name)
      setValue('trade_name', d.trade_name)
      setValue('status', d.status)
      setValue('email', d.email)
      setValue('phone', d.phone)
      setValue('zip_code', d.zip_code)
      setValue('street', d.street)
      setValue('number', d.number)
      setValue('complement', d.complement)
      setValue('district', d.district)
      setValue('city', d.city)
      setValue('state', d.state)
      setValue('cnpj_fetched_at', new Date().toISOString())
      setRestante(resposta.remaining_quota)
      notify.success('Cadastro preenchido a partir da Receita Federal.')
    },
    // Indisponibilidade da integração **não impede o cadastro manual** — é a
    // regra escrita no próprio endpoint.
    onError: (erro) =>
      notify.error(mensagemDoServidor(erro, 'Não foi possível consultar o CNPJ. Preencha os dados à mão.')),
  })

  const digitos = String(values.document ?? '').replace(/\D/g, '')
  const podeConsultar = values.document_type === 'CNPJ' && digitos.length === 14

  return (
    <>
      <ProviderDocumentField
        tipo={(values.document_type as DocumentType | null) ?? null}
        valor={String(values.document ?? '')}
        onChange={(tipo, valor) => {
          setValue('document_type', tipo)
          setValue('document', valor)
        }}
      />

      {values.document_type === 'CNPJ' && (
        <div className="rounded-md border border-border bg-muted/40 p-3">
          <Button
            type="button"
            variant="secondary"
            size="sm"
            disabled={!podeConsultar || consultar.isPending}
            onClick={() => consultar.mutate(digitos)}
          >
            {consultar.isPending ? (
              <Loader2 aria-hidden="true" className="h-4 w-4 animate-spin" />
            ) : (
              <Search aria-hidden="true" className="h-4 w-4" />
            )}
            Preencher pela Receita Federal
          </Button>
          <p className="mt-2 text-xs text-muted-foreground">
            {restante === null
              ? 'A consulta é paga por chamada e tem teto diário por usuário.'
              : `Restam ${restante} consulta(s) hoje.`}
          </p>
        </div>
      )}

      <CampoTexto
        id="title"
        label="Nome do fornecedor"
        value={values.title}
        onChange={(v) => setValue('title', v)}
        placeholder="Ex.: Britagem São José"
      />

      <CampoTexto
        id="resume"
        label="Descrição"
        value={values.resume}
        onChange={(v) => setValue('resume', v)}
        placeholder="Opcional"
      />

      {editing && (
        <CampoTexto
          id="integration_key"
          label="Chave de integração"
          value={values.integration_key}
          onChange={(v) => setValue('integration_key', v)}
          hint="Derivada do nome na criação e mantida depois. Renomear o fornecedor não a altera — ela pode estar em uso por um sistema externo."
        />
      )}

      {/* **FE-074 / DEC-136 — o campo existe também na CRIAÇÃO.**

          Estava escondido porque o anexo precisa de um registro para se
          pendurar, e o formulário dizia "envie depois, na edição". O legado
          aceitava já no cadastro, e a DEC-136 mandou voltar a aceitar.

          Sem registro, o `ScopedLogoField` guarda o arquivo e mostra a prévia
          local; o `afterCreate` do `CatalogScreen` o envia quando o id existe.
          Isto NÃO é o input que o legado tinha — lá o `ajax:error` de qualquer
          campo descartava o arquivo escolhido; aqui ele sobrevive. */}
      <div className="space-y-1.5">
        <Label htmlFor="logo">Logo</Label>
        <ScopedLogoField
          record={editing}
          api={providersApi}
          currentUrl={editing?.logo_url ?? null}
          urlOf={(p) => p.logo_url}
          limiteMb={1}
          queryKeys={['providers', 'provider']}
          placeholder="Enviar logo do fornecedor"
          onPending={onLogoPendente}
        />
      </div>

      <CampoAtivo
        value={values.is_active}
        onChange={(v) => setValue('is_active', v)}
        descricao="Fornecedor inativo continua nas renegociações que já o citam, mas não aparece para novas escolhas."
      />
    </>
  )
}
