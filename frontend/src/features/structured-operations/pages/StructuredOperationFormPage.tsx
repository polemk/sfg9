import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { FormActionBar } from '@/components/ui/FormActionBar'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { Tooltip } from '@/components/ui/Tooltip'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { mensagemDeErro } from '@/components/ui/AsyncSection'
import { useMobile } from '@/hooks/useMobile'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { carrierConnectionsApi, companiesApi } from '@/lib/api/projects'
import {
  structuredOperationTypesApi,
  structuredOperationsApi,
  type StructuredOperationInput,
} from '../api/structuredOperations'
import { OperationForm, iso, usePreSelecao, type OperationFormValues } from '../components/OperationForm'

/**
 * **Cadastro e edição da operação estruturada** (`FE-293`…`FE-298`).
 *
 * ## `FE-295` — o pior comportamento do formulário do legado morre aqui
 *
 * O legado **não tem botão "Salvar"**. Cada `change` de campo registrava uma
 * ação anônima numa barra inferior (`dashBottomHolder.getData().stack`) — e o
 * `handle.js.erb` **removia a ação da pilha** assim que **qualquer** campo
 * `.mandatory_field` ficasse vazio. Sem mensagem, sem realce no campo, sem
 * nada: o usuário simplesmente perdia a possibilidade de salvar e não tinha
 * como descobrir por quê.
 *
 * Aqui a barra é explícita e **diz o que falta**, item por item, na ordem em
 * que os campos aparecem na tela. É o `FormActionBar` da biblioteca — o mesmo
 * que o formulário de borderô usa, porque o defeito era o mesmo nas duas telas.
 *
 * ## A divergência `due_date`, corrigida (`FE-295`)
 *
 * No legado o vencimento **não** era `.mandatory_field` na tela, mas
 * `validates :due_date, presence: true` no model: o usuário conseguia disparar
 * o salvamento e recebia o erro do servidor. Agora as duas pontas concordam.
 *
 * ## `T-D5` — as datas são imutáveis na edição
 *
 * Na edição, emissão e vencimento aparecem **somente leitura** e o servidor
 * recusa a alteração. O legado fazia isso com dois campos `*_fake` que sequer
 * eram enviados — mesmo efeito, sem o campo fantasma.
 *
 * ## `FE-298` — os dois bloqueios, com a precedência do legado
 *
 * Sem portador no projeto vence sem empresa (é a ordem do
 * `new/_body.html.erb`). A concordância errada do legado ("cadastrar uma
 * operação **de estruturada**") sai. O caminho de "não tem empresa" continua
 * sendo o **link inline** — "clique aqui" — que cria a empresa sem sair do
 * formulário e recarrega as listas.
 */
export function StructuredOperationFormPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const estreito = useMobile()
  const editando = Boolean(id)

  const [valores, setValores] = useState<OperationFormValues>(() => vazio())
  const [criandoEmpresa, setCriandoEmpresa] = useState(false)
  const [novaEmpresa, setNovaEmpresa] = useState('')
  /**
   * **BE-291 — a troca de projeto deixa de ser efeito colateral.**
   *
   * `project_id` é derivado de `company.project_id` em todo save. No legado
   * bastava trocar um select para a operação **mudar de tenant**, levando junto
   * o vínculo com a remuneração e o recibo que ficavam para trás. O servidor
   * agora recusa com `PROJECT_CHANGE_REQUIRES_CONFIRMATION`; a tela pergunta e
   * reenvia com `confirm_project_change: true`.
   */
  const [confirmarProjeto, setConfirmarProjeto] = useState<{ aviso: string; dados: StructuredOperationInput } | null>(null)

  const empresas = useQuery({
    queryKey: ['companies', 'para-operacoes-estruturadas'],
    queryFn: () => companiesApi.list({ perPage: 100 }),
  })

  const portadores = useQuery({
    queryKey: ['project-carriers', 'para-operacoes-estruturadas'],
    queryFn: () => carrierConnectionsApi.list({ perPage: 100 }),
  })

  // **B-04** — o CADASTRO usa `.active`; quem inclui inativo é o filtro da
  // lista. Replicado de propósito.
  const tipos = useQuery({
    queryKey: ['structured-operation-types', 'ativos'],
    queryFn: () => structuredOperationTypesApi.list({ perPage: 100, active: true }),
  })

  const operacao = useQuery({
    queryKey: ['structured-operation', id],
    queryFn: () => structuredOperationsApi.get(id as string),
    enabled: editando,
  })

  useEffect(() => {
    document.title = editando
      ? 'Safegold - Editar operação estruturada'
      : 'Safegold - Cadastrar operação estruturada'
  }, [editando])

  // Carrega o registro no formulário uma vez, quando ele chega.
  useEffect(() => {
    const o = operacao.data
    if (!o) return
    setValores({
      company_id: o.company_id,
      carrier_id: o.carrier_id,
      operation_type_id: o.operation_type_id,
      title: o.title ?? '',
      contract_number: o.contract_number ?? '',
      issue_date: comoData(o.issue_date),
      due_date: comoData(o.due_date),
      operation_value: numero(o.operation_value),
      // DEC-01 — chega negativo do servidor; o campo edita o MÓDULO.
      original_balance: Math.abs(numero(o.original_balance) ?? 0),
      agreed_rate: numero(o.agreed_rate),
      observation: o.observation ?? '',
      is_on_variable: o.is_on_variable,
      is_ended: o.is_ended,
    })
  }, [operacao.data])

  const listasProntas =
    empresas.isSuccess && portadores.isSuccess && tipos.isSuccess && (!editando || operacao.isSuccess)

  const alterar = <K extends keyof OperationFormValues>(campo: K, valor: OperationFormValues[K]) =>
    setValores((atual) => ({ ...atual, [campo]: valor }))

  // FE-293 — a pré-seleção da primeira empresa/portador/tipo ativo, como o
  // legado fazia com `@first_company` / `@first_carrier` / `.first`.
  usePreSelecao(valores, alterar, {
    empresas: empresas.data?.items ?? [],
    portadores: portadores.data?.items ?? [],
    tipos: tipos.data?.items ?? [],
    pronto: !editando && listasProntas,
  })

  const salvar = useMutation({
    mutationFn: (dados: StructuredOperationInput) =>
      editando
        ? structuredOperationsApi.update(id as string, dados)
        : structuredOperationsApi.create(dados),
    onSuccess: (o) => {
      notify.success(editando ? `Operação «${o.title}» atualizada.` : `Operação «${o.title}» cadastrada.`)
      queryClient.invalidateQueries({ queryKey: ['structured-operations'] })
      queryClient.invalidateQueries({ queryKey: ['structured-operation', o.id] })
      // A cobrança conta candidatos a recibo: uma operação nova muda a lista.
      queryClient.invalidateQueries({ queryKey: ['charge-receipts'] })
      navigate(`/structured-operations/${o.id}`)
    },
    onError: (erro, dados) => {
      const codigo = (erro as any)?.response?.data?.code
      if (codigo === 'PROJECT_CHANGE_REQUIRES_CONFIRMATION') {
        setConfirmarProjeto({
          aviso: mensagemDoServidor(erro, 'Esta empresa pertence a outro projeto.'),
          dados,
        })
        return
      }
      notify.error(mensagemDoServidor(erro, 'Não foi possível salvar a operação.'))
    },
  })

  const criarEmpresa = useMutation({
    mutationFn: (title: string) => companiesApi.create({ title }),
    onSuccess: (c) => {
      notify.success(`Empresa «${c.title}» cadastrada.`)
      setCriandoEmpresa(false)
      setNovaEmpresa('')
      // "…e recarrega": as listas do formulário voltam a ser buscadas e a
      // empresa recém-criada já aparece pré-selecionada.
      queryClient.invalidateQueries({ queryKey: ['companies'] })
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível cadastrar a empresa.')),
  })

  /**
   * **O que falta preencher** — a lista que a barra mostra. É a mesma condição
   * que desabilita o botão: uma regra, um lugar.
   */
  const pendencias = useMemo(() => {
    const faltando: string[] = []
    if (!valores.company_id) faltando.push('a empresa')
    if (!valores.carrier_id) faltando.push('o portador')
    if (!valores.operation_type_id) faltando.push('o tipo de operação')
    // Na edição as datas são imutáveis: não podem ser pendência.
    if (!editando && !valores.issue_date) faltando.push('a data de emissão')
    // FE-295 — o vencimento passa a ser obrigatório TAMBÉM na tela.
    if (!editando && !valores.due_date) faltando.push('a data de vencimento')
    if (valores.operation_value === null) faltando.push('o capital da operação')
    return faltando
  }, [valores, editando])

  const podeSalvar = pendencias.length === 0 && !salvar.isPending

  function enviar() {
    if (!podeSalvar) return
    const base = {
      company_id: valores.company_id,
      carrier_id: valores.carrier_id,
      operation_type_id: valores.operation_type_id,
      title: valores.title || undefined,
      contract_number: valores.contract_number || undefined,
      operation_value: valores.operation_value ?? 0,
      // Vai em MÓDULO: quem inverte o sinal é o servidor (DEC-01).
      original_balance: valores.original_balance ?? 0,
      agreed_rate: valores.agreed_rate ?? 0,
      observation: valores.observation,
      is_on_variable: valores.is_on_variable,
      is_ended: valores.is_ended,
    }
    // T-D5 — as datas só viajam na CRIAÇÃO.
    const dados: StructuredOperationInput = editando
      ? base
      : { ...base, issue_date: iso(valores.issue_date), due_date: iso(valores.due_date) }
    salvar.mutate(dados)
  }

  const cabecalho = (
    <PageHeader
      title={editando ? 'Editar operação' : 'Cadastrar operação'}
      subtitle={
        editando
          ? 'Emissão e vencimento são definidos na criação e não mudam depois.'
          : 'O projeto da operação vem da empresa escolhida.'
      }
      rightSlot={
        <Button variant="ghost" onClick={() => navigate('/structured-operations')}>
          <ArrowLeft aria-hidden="true" className="h-4 w-4" />
          Voltar para a lista
        </Button>
      }
    />
  )

  const escopo = projectScopeCode(operacao.error ?? empresas.error)
  if (escopo) return <ProjectScopeState code={escopo} recurso="as operações estruturadas" />

  if (editando && operacao.isPending) return <LoadingState label="Carregando a operação…" />

  if (editando && (operacao.isError || !operacao.data)) {
    return (
      <div className="space-y-4 pb-10">
        {cabecalho}
        <ErrorState
          title="Não foi possível abrir a operação"
          description={
            mensagemDeErro(operacao.error) ?? 'A operação não existe ou não pertence a este projeto.'
          }
          onRetry={() => operacao.refetch()}
        />
      </div>
    )
  }

  const semPortador = portadores.isSuccess && (portadores.data?.items?.length ?? 0) === 0
  const semEmpresa = empresas.isSuccess && (empresas.data?.items?.length ?? 0) === 0

  // FE-298 — precedência: sem portador vence sem empresa.
  if (semPortador) {
    return (
      <div className="pb-10">
        {cabecalho}
        <EmptyState
          title="Este projeto ainda não tem portador"
          description="É necessário ter um portador no projeto para que seja possível cadastrar uma operação estruturada."
          action={
            <Button variant="secondary" onClick={() => navigate('/project-carrier-connections')}>
              Vincular portador ao projeto
            </Button>
          }
        />
      </div>
    )
  }

  if (semEmpresa) {
    return (
      <div className="pb-10">
        {cabecalho}
        <EmptyState
          title="Este projeto não possui empresa"
          description="A empresa é quem define o projeto da operação. Cadastre uma para liberar o formulário."
          action={
            <Button variant="secondary" onClick={() => setCriandoEmpresa(true)}>
              Cadastrar empresa aqui
            </Button>
          }
        />
        <DrawerDeEmpresa
          aberto={criandoEmpresa}
          valor={novaEmpresa}
          onValor={setNovaEmpresa}
          onFechar={() => setCriandoEmpresa(false)}
          onCriar={() => criarEmpresa.mutate(novaEmpresa.trim())}
          salvando={criarEmpresa.isPending}
        />
      </div>
    )
  }

  return (
    // Idem ao borderô: a `FormActionBar` fica acima das abas no telefone.
    <div className="pb-44 md:pb-28">
      {cabecalho}

      <OperationForm
        valores={valores}
        onChange={alterar}
        empresas={empresas.data?.items ?? []}
        portadores={portadores.data?.items ?? []}
        tipos={tipos.data?.items ?? []}
        editando={editando}
        estreito={estreito}
      />

      <FormActionBar pendencias={pendencias} resumo={<span className="text-muted-foreground">Tudo pronto para salvar.</span>}>
        <Button variant="ghost" onClick={() => navigate('/structured-operations')} disabled={salvar.isPending}>
          Cancelar
        </Button>
        <Tooltip content={podeSalvar ? '' : `Falta preencher: ${pendencias.join(', ')}`}>
          <span>
            <Button onClick={enviar} disabled={!podeSalvar}>
              {salvar.isPending ? 'Salvando…' : editando ? 'Salvar alterações' : 'Cadastrar operação'}
            </Button>
          </span>
        </Tooltip>
      </FormActionBar>

      <ConfirmDialog
        open={confirmarProjeto !== null}
        onOpenChange={(aberto) => !aberto && setConfirmarProjeto(null)}
        title="Mover a operação para outro projeto?"
        description={confirmarProjeto?.aviso ?? ''}
        confirmLabel="Mover mesmo assim"
        tone="destructive"
        loading={salvar.isPending}
        onConfirm={() => {
          if (!confirmarProjeto) return
          const dados = { ...confirmarProjeto.dados, confirm_project_change: true }
          setConfirmarProjeto(null)
          salvar.mutate(dados)
        }}
      />
    </div>
  )
}

/** O "clique aqui" do legado, como painel de verdade. */
function DrawerDeEmpresa({
  aberto,
  valor,
  onValor,
  onFechar,
  onCriar,
  salvando,
}: {
  aberto: boolean
  valor: string
  onValor: (v: string) => void
  onFechar: () => void
  onCriar: () => void
  salvando: boolean
}) {
  return (
    <SideDrawer
      open={aberto}
      onClose={onFechar}
      title="Nova empresa neste projeto"
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onFechar} disabled={salvando}>
            Cancelar
          </Button>
          <Button onClick={onCriar} disabled={!valor.trim() || salvando}>
            {salvando ? 'Cadastrando…' : 'Cadastrar empresa'}
          </Button>
        </div>
      }
    >
      <div className="space-y-1.5">
        <Label htmlFor="nova_empresa">Razão social</Label>
        <Input
          id="nova_empresa"
          value={valor}
          onChange={(e) => onValor(e.target.value)}
          placeholder="Ex.: Incorporadora Alfa Ltda."
          autoFocus
        />
        <p className="text-xs text-muted-foreground">
          Única dentro deste projeto. Depois de cadastrada, o formulário da operação volta com ela selecionada.
        </p>
      </div>
    </SideDrawer>
  )
}

function vazio(): OperationFormValues {
  return {
    company_id: '',
    carrier_id: '',
    operation_type_id: '',
    title: '',
    contract_number: '',
    issue_date: null,
    due_date: null,
    operation_value: null,
    original_balance: null,
    agreed_rate: null,
    observation: '',
    is_on_variable: true,
    is_ended: false,
  }
}

function numero(v: string | null | undefined): number | null {
  if (v === null || v === undefined || v === '') return null
  const n = Number(v)
  return Number.isFinite(n) ? n : null
}

/** `YYYY-MM-DD` → `Date` local. Data nula NÃO quebra a tela (FE-297). */
function comoData(v: string | null | undefined): Date | null {
  if (!v) return null
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(v)
  if (!m) return null
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
}
