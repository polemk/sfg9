import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, Building2, Truck } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { Select } from '@/components/ui/Select'
import { Textarea } from '@/components/ui/textarea'
import { DatePicker } from '@/components/ui/DatePicker'
import { MoneyInput, PercentInput } from '@/components/ui/NumericInput'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { companiesApi, providersApi } from '@/lib/api/projects'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { renegotiationsApi } from '@/lib/api/renegotiations'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { toIsoDate } from '@/lib/utils/date'

/**
 * **Cadastro de renegociação** — criação e edição (FE-199..FE-203).
 *
 * ## Os 13 campos, e os dois que NÃO estão aqui
 *
 * `interest_rate_correction` ("Taxa Juro Correção") e `grace_period` ("Carência")
 * existem na tabela e **nunca são lidos por cálculo nenhum** (**D-47**, Q-B24):
 * `correct_value` é sempre igual a `total_debt`, e a carência não entra em
 * vencimento nem em juros. No legado eles também não aparecem na tela, e a
 * **DEC-40** decidiu que continuam **visíveis e inertes** no domínio, sem
 * formulário. Colocá-los aqui prometeria um efeito que não existe.
 *
 * ## Três defeitos do legado que morrem
 *
 * - **FE-203** — a mensagem de sucesso dizia "foi atualizada com sucesso"
 *   **também na criação**, porque o template era um só. Aqui a frase distingue.
 * - **FE-200** — sem fornecedor ou sem empresa, o formulário abria com selects
 *   vazios e o `save` falhava sem explicar. Agora a tela explica e dá o atalho.
 * - **BE-198** — o registro nascia com tudo zerado e estado "Inconsistente". O
 *   servidor recalcula na criação; a tela não precisa fazer nada.
 */
export function RenegotiationFormPage() {
  const { id } = useParams<{ id: string }>()
  const editando = !!id
  const navigate = useNavigate()
  const queryClient = useQueryClient()

  const opcoes = useQuery({
    queryKey: ['renegotiation-options'],
    queryFn: () => renegotiationsApi.options(),
    staleTime: 30 * 60 * 1000,
  })

  const fornecedores = useQuery({
    queryKey: ['providers', 'ativos', 'para-renegociacao'],
    queryFn: () => providersApi.list({ active: true, perPage: 100 }),
  })

  const empresas = useQuery({
    queryKey: ['companies', 'para-renegociacao'],
    queryFn: () => companiesApi.list({ perPage: 100 }),
  })

  /**
   * **As renegociações que já existem no projeto — para não oferecer o que o
   * servidor recusa.**
   *
   * A `integration_key` é derivada do nome do fornecedor e é **única por
   * projeto** (`Renegotiation`, S9): um fornecedor que já tem renegociação
   * neste projeto responde **422** com "Chave de integração já está em uso
   * neste projeto" — uma mensagem que nomeia um campo que a pessoa nunca viu,
   * sobre uma escolha que a tela ofereceu.
   *
   * Medido: com o seed de demonstração, três das oito opções do `select` eram
   * 422 garantido. O servidor continua sendo a defesa; isto é a conveniência
   * que evita o erro — as duas coisas, sempre.
   *
   * Uma consulta a mais, e barata: o cliente com mais renegociações tem 13.
   */
  const existentes = useQuery({
    queryKey: ['renegotiations', 'fornecedores-em-uso'],
    queryFn: () => renegotiationsApi.list({ perPage: 100 }),
  })

  const registro = useQuery({
    queryKey: ['renegotiation', id],
    queryFn: () => renegotiationsApi.get(id!),
    enabled: editando,
  })

  const [form, setForm] = useState<Record<string, any>>(() => formularioVazio())

  useEffect(() => {
    if (registro.data) setForm(doRegistro(registro.data))
  }, [registro.data])

  const salvar = useMutation({
    mutationFn: (dados: Record<string, unknown>) =>
      editando ? renegotiationsApi.update(id!, dados) : renegotiationsApi.create(dados),
    onSuccess: (salvo) => {
      // **A frase distingue criação de edição** (FE-203).
      notify.success(editando ? 'Renegociação atualizada.' : 'Renegociação criada.')
      queryClient.invalidateQueries({ queryKey: ['renegotiations'] })
      queryClient.invalidateQueries({ queryKey: ['renegotiation', salvo.id] })
      navigate(`/renegotiations/${salvo.id}`)
    },
    onError: (erro) =>
      notify.error(
        mensagemDoServidor(
          erro,
          editando ? 'Não foi possível atualizar a renegociação.' : 'Não foi possível criar a renegociação.',
        ),
      ),
  })

  const listaFornecedores = fornecedores.data?.items ?? []

  /**
   * O fornecedor da renegociação que está sendo EDITADA não conta: ele é o dono
   * da chave, e a unicidade não colide consigo mesma.
   */
  const fornecedoresEmUso = useMemo(() => {
    const usados = new Set<string>()
    for (const renegociacao of existentes.data?.items ?? []) {
      if (editando && renegociacao.id === id) continue
      if (renegociacao.provider_id) usados.add(renegociacao.provider_id)
    }
    return usados
  }, [existentes.data, editando, id])
  const listaEmpresas = empresas.data?.items ?? []
  const carregandoDependencias = fornecedores.isLoading || empresas.isLoading
  const semFornecedor = !carregandoDependencias && listaFornecedores.length === 0
  const semEmpresa = !carregandoDependencias && listaEmpresas.length === 0

  const valido = useMemo(
    () => !!form.provider_id && !!form.company_id && !!form.kind && !!form.renegotiation_date,
    [form],
  )

  function definir(campo: string, valor: unknown) {
    setForm((atual) => ({ ...atual, [campo]: valor }))
  }

  function enviar(evento: React.FormEvent) {
    evento.preventDefault()
    if (!valido) {
      notify.error('Preencha fornecedor, empresa, tipo e data da negociação.')
      return
    }
    salvar.mutate({
      title: form.title?.trim() || undefined,
      provider_id: form.provider_id,
      company_id: form.company_id,
      kind: form.kind,
      renegotiation_date: toIsoDate(form.renegotiation_date),
      origin: form.origin || undefined,
      monetary_correction: form.monetary_correction || undefined,
      observation: form.observation || undefined,
      original_value: form.original_value ?? 0,
      original_pending_value: form.original_pending_value ?? 0,
      additional_value: form.additional_value ?? 0,
      total_debt: form.total_debt ?? 0,
      desagio_value: form.desagio_value ?? 0,
      operation_interest_rate: form.operation_interest_rate ?? 0,
    })
  }

  // O formulário depende de fornecedor e empresa DO PROJETO: sem projeto
  // corrente não há o que oferecer, e o aviso é o mesmo das outras telas.
  const escopo =
    projectScopeCode(fornecedores.error) ??
    projectScopeCode(empresas.error) ??
    projectScopeCode(registro.error)
  if (escopo) return <ProjectScopeState code={escopo} recurso="as renegociações" />

  if (editando && registro.isLoading) return <LoadingState label="Carregando a renegociação…" />
  if (editando && registro.error) {
    return (
      <ErrorState
        title="Não foi possível carregar a renegociação"
        description={mensagemDoServidor(registro.error, 'Tente novamente.')}
        onRetry={() => registro.refetch()}
      />
    )
  }

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={editando ? `Editar ${form.provider_name || 'renegociação'}` : 'Nova renegociação'}
        subtitle="O acordo com o fornecedor. As parcelas e os pagamentos são lançados no detalhe."
        rightSlot={
          <Button variant="ghost" size="sm" onClick={() => navigate(editando ? `/renegotiations/${id}` : '/renegotiations')}>
            <ArrowLeft className="mr-2 h-4 w-4" aria-hidden />
            Voltar
          </Button>
        }
      />

      {/* FE-200 — sem fornecedor / sem empresa: explicação + atalho. */}
      {semFornecedor && (
        <EmptyState
          icon={<Truck className="h-6 w-6" aria-hidden />}
          title="Este projeto ainda não tem fornecedor"
          description="A renegociação é uma dívida COM um fornecedor. Cadastre o fornecedor antes de registrar o acordo."
          action={
            <Button size="sm" onClick={() => navigate('/providers')}>
              Cadastrar fornecedor
            </Button>
          }
        />
      )}
      {semEmpresa && (
        <EmptyState
          icon={<Building2 className="h-6 w-6" aria-hidden />}
          title="Este projeto ainda não tem empresa"
          description="A renegociação é registrada por uma empresa do projeto — é ela que deve."
          action={
            <Button size="sm" onClick={() => navigate('/companies')}>
              Cadastrar empresa
            </Button>
          }
        />
      )}

      {!semFornecedor && !semEmpresa && (
        <form onSubmit={enviar} className="flex flex-col gap-6">
          <Secao titulo="Identificação">
            <Campo id="provider_id" label="Fornecedor" obrigatorio>
              <Select
                id="provider_id"
                options={listaFornecedores.map((f) => ({
                  value: f.id,
                  label: f.title,
                  // Desabilitado **com a razão escrita**: sumir com a opção
                  // faria a pessoa procurar o fornecedor que ela sabe que
                  // existe. Ver `fornecedoresEmUso`.
                  disabled: fornecedoresEmUso.has(f.id),
                  description: fornecedoresEmUso.has(f.id)
                    ? 'Já tem renegociação neste projeto — uma por fornecedor'
                    : undefined,
                }))}
                value={form.provider_id}
                onChange={(valor) => definir('provider_id', valor)}
                placeholder="Selecione o fornecedor…"
                block
              />
            </Campo>

            <Campo id="company_id" label="Empresa" obrigatorio>
              <Select
                id="company_id"
                options={listaEmpresas.map((e) => ({ value: e.id, label: e.title }))}
                value={form.company_id}
                onChange={(valor) => definir('company_id', valor)}
                placeholder="Selecione a empresa…"
                block
              />
            </Campo>

            <Campo
              id="title"
              label="Nome da renegociação"
              dica="Em branco, o nome do fornecedor é usado — é o que o legado faz."
            >
              <Input
                id="title"
                value={form.title ?? ''}
                onChange={(e) => definir('title', e.target.value)}
                placeholder="Ex.: Acordo 2025 — parcelamento"
              />
            </Campo>

            <Campo id="kind" label="Tipo de renegociação" obrigatorio>
              <Select
                id="kind"
                options={(opcoes.data?.kinds ?? []).map((k) => ({ value: k, label: k }))}
                value={form.kind}
                onChange={(valor) => definir('kind', valor)}
                placeholder="Selecione o tipo…"
                block
              />
            </Campo>

            <Campo id="renegotiation_date" label="Data da negociação" obrigatorio>
              <DatePicker
                id="renegotiation_date"
                value={form.renegotiation_date}
                onChange={(valor) => definir('renegotiation_date', valor)}
              />
            </Campo>

            <Campo id="origin" label="Origem" dica="De onde veio o acordo.">
              <Select
                id="origin"
                options={(opcoes.data?.origins ?? []).map((o) => ({ value: o, label: o }))}
                value={form.origin}
                onChange={(valor) => definir('origin', valor)}
                placeholder="Selecione a origem…"
                block
              />
            </Campo>
          </Secao>

          <Secao titulo="Valores">
            <Campo id="original_value" label="Valor original vencido">
              <MoneyInput
                id="original_value"
                value={form.original_value}
                onChange={(valor) => definir('original_value', valor)}
              />
            </Campo>

            <Campo id="original_pending_value" label="Valor original a vencer">
              <MoneyInput
                id="original_pending_value"
                value={form.original_pending_value}
                onChange={(valor) => definir('original_pending_value', valor)}
              />
            </Campo>

            <Campo id="additional_value" label="Despesas adicionais (exceto juros)">
              <MoneyInput
                id="additional_value"
                value={form.additional_value}
                onChange={(valor) => definir('additional_value', valor)}
              />
            </Campo>

            <Campo
              id="total_debt"
              label="Valor total da dívida"
              dica="Com juros projetados. É a referência de consistência do lançamento das parcelas."
            >
              <MoneyInput
                id="total_debt"
                value={form.total_debt}
                onChange={(valor) => definir('total_debt', valor)}
              />
            </Campo>

            <Campo id="desagio_value" label="Valor do deságio">
              <MoneyInput
                id="desagio_value"
                value={form.desagio_value}
                onChange={(valor) => definir('desagio_value', valor)}
              />
            </Campo>

            <Campo
              id="operation_interest_rate"
              label="Taxa de juros acordada (% ao período)"
              dica="Entra no cálculo do valor presente da dívida."
            >
              <PercentInput
                id="operation_interest_rate"
                value={form.operation_interest_rate}
                onChange={(valor) => definir('operation_interest_rate', valor)}
              />
            </Campo>

            <Campo id="monetary_correction" label="Índice de correção monetária">
              <Input
                id="monetary_correction"
                value={form.monetary_correction ?? ''}
                onChange={(e) => definir('monetary_correction', e.target.value)}
                placeholder="Ex.: IPCA"
              />
            </Campo>
          </Secao>

          <Secao titulo="Observações" colunaUnica>
            <Campo id="observation" label="Observações">
              <Textarea
                id="observation"
                rows={4}
                value={form.observation ?? ''}
                onChange={(e) => definir('observation', e.target.value)}
                placeholder="Texto livre — escreva o quanto precisar."
              />
            </Campo>
          </Secao>

          <div className="flex flex-wrap items-center justify-end gap-2">
            <Button
              type="button"
              variant="secondary"
              onClick={() => navigate(editando ? `/renegotiations/${id}` : '/renegotiations')}
            >
              Cancelar
            </Button>
            <Button type="submit" loading={salvar.isPending} disabled={!valido}>
              {editando ? 'Salvar alterações' : 'Criar renegociação'}
            </Button>
          </div>
        </form>
      )}
    </div>
  )
}

// --- Peças -----------------------------------------------------------------

function formularioVazio(): Record<string, any> {
  return {
    title: '',
    provider_id: null,
    company_id: null,
    kind: null,
    renegotiation_date: null,
    origin: null,
    monetary_correction: '',
    observation: '',
    original_value: null,
    original_pending_value: null,
    additional_value: null,
    total_debt: null,
    desagio_value: null,
    operation_interest_rate: null,
  }
}

function doRegistro(r: Awaited<ReturnType<typeof renegotiationsApi.get>>): Record<string, any> {
  return {
    title: r.title,
    provider_name: r.provider_name,
    provider_id: r.provider_id,
    company_id: r.company_id,
    kind: r.kind,
    renegotiation_date: r.renegotiation_date,
    origin: r.origin,
    monetary_correction: r.monetary_correction ?? '',
    observation: r.observation ?? '',
    original_value: Number(r.original_value),
    original_pending_value: Number(r.original_pending_value),
    additional_value: Number(r.additional_value),
    total_debt: Number(r.total_debt),
    desagio_value: Number(r.desagio_value),
    operation_interest_rate: r.operation_interest_rate,
  }
}

function Secao({
  titulo,
  children,
  colunaUnica,
}: {
  titulo: string
  children: React.ReactNode
  colunaUnica?: boolean
}) {
  return (
    <section className="rounded-lg border border-border bg-card p-4 sm:p-6">
      <h2 className="mb-4 text-sm font-semibold uppercase tracking-[0.08em] text-muted-foreground">
        {titulo}
      </h2>
      <div className={colunaUnica ? 'grid gap-4' : 'grid gap-4 sm:grid-cols-2'}>{children}</div>
    </section>
  )
}

function Campo({
  id,
  label,
  dica,
  obrigatorio,
  children,
}: {
  id: string
  label: string
  dica?: string
  obrigatorio?: boolean
  children: React.ReactNode
}) {
  return (
    <div className="flex flex-col gap-1.5">
      <Label htmlFor={id}>
        {label}
        {obrigatorio && <span className="ml-1 text-destructive-text">*</span>}
      </Label>
      {children}
      {dica && <p className="text-xs text-muted-foreground">{dica}</p>}
    </div>
  )
}
