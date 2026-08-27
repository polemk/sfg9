import { useEffect, useMemo, useState } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import { Lock } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Campo } from '@/app/pages/catalogs/CatalogFields'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { DatePicker } from '@/components/ui/DatePicker'
import { Input } from '@/components/ui/Input'
import { Select } from '@/components/ui/Select'
import { Switch } from '@/components/ui/switch'
import { MoneyInput, PercentInput } from '@/components/ui/NumericInput'
import { Textarea } from '@/components/ui/textarea'
import { FieldHelp } from '@/components/help/FieldHelp'
import { companiesApi } from '@/lib/api/projects'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { riskOperationsApi, type RiskOperation, type RiskOperationInput } from '../api/risk'

/**
 * **Criar / editar operação de risco** (FE-258..FE-263).
 *
 * ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
 *
 * Fonte: `../sfg/app/views/pub/console/parts/risk_operations/new/_body.html.erb`.
 * As migrations desta família nunca subiram, então o que este formulário
 * replica é o **código de 2022**, não uma tela que alguém usou.
 *
 * ## As cinco decisões que moram aqui
 *
 * 1. **A cascata é empresa → portador → tipo** (FE-258), e cada degrau vem do
 *    servidor pelo mesmo critério que ele aplica no `POST`: empresa com limite
 *    ativo de tipo manual → portador → tipo. No legado a tela oferecia opções
 *    que o servidor recusava.
 * 2. **Em edição, os três viram texto readonly.** Mudá-los moveria a operação
 *    para outro limite, arrastando exposição — e o servidor recusa igual.
 * 3. **"Capital da Operação" é readonly na edição; "Saldo Inicial" é editável**
 *    (FE-259). É o legado. Editar o capital **não** regenera o movimento de
 *    liberação, e é isso que faz o saldo divergir do capital — replicado.
 * 4. **Datas somem em tipo com pré-faturamento** (FE-260/FE-311) e, em edição,
 *    são readonly **com regra de servidor** (T-D5): a API ignora `issue_date` e
 *    `due_date` no `PUT`. Esticar prazo é PRORROGAÇÃO.
 * 5. **FE-261 — o botão não some: ele diz o que falta.** No legado o "Salvar"
 *    simplesmente não aparecia até tudo estar preenchido, e o operador não
 *    sabia qual campo faltava.
 *
 * **Dinheiro é `MoneyInput` e taxa é `PercentInput`** (§5.4.9). O `MoneyInput`
 * preenche da direita para a esquerda e a moeda vem de `@/lib/config/currency`
 * — nunca `'BRL'` cravado. Esta é a **quarta e última** cópia de máscara do
 * legado eliminada (FE-262).
 */

export interface RiskOperationFormValues {
  company_id: string | null
  carrier_id: string | null
  operation_type_id: string | null
  operation_subtype_id: string | null
  title: string
  contract_number: string
  issue_date: Date | null
  due_date: Date | null
  operation_value: number | null
  original_balance: number | null
  agreed_rate: number | null
  observation: string
  is_on_variable: boolean
  is_ended: boolean
}

const VAZIO: RiskOperationFormValues = {
  company_id: null,
  carrier_id: null,
  operation_type_id: null,
  operation_subtype_id: null,
  title: '',
  contract_number: '',
  issue_date: null,
  due_date: null,
  operation_value: null,
  original_balance: 0,
  agreed_rate: 0,
  observation: '',
  is_on_variable: false,
  is_ended: false,
}

const iso = (d: Date | null) => (d ? d.toISOString().slice(0, 10) : '')

function paraFormulario(o: RiskOperation): RiskOperationFormValues {
  return {
    company_id: o.company_id,
    carrier_id: o.carrier_id,
    operation_type_id: o.operation_type_id,
    operation_subtype_id: o.operation_subtype_id,
    title: o.title ?? '',
    contract_number: o.contract_number ?? '',
    issue_date: o.issue_date ? new Date(`${o.issue_date}T00:00:00`) : null,
    due_date: o.due_date ? new Date(`${o.due_date}T00:00:00`) : null,
    operation_value: Number(o.operation_value),
    // **DEC-01, o outro lado.** O banco guarda negativo e o DETALHE exibe
    // negativo (FE-265); o FORMULÁRIO edita o módulo. Os dois convivem no
    // legado, e a melhoria foi declinada pelo usuário (D-93).
    original_balance: Number(o.original_balance_abs ?? o.original_balance),
    agreed_rate: Number(o.agreed_rate),
    observation: o.observation ?? '',
    is_on_variable: o.is_on_variable,
    is_ended: o.is_ended,
  }
}

export function RiskOperationDrawer({
  open,
  operacao,
  onClose,
  onSaved,
}: {
  open: boolean
  operacao: RiskOperation | null
  onClose: () => void
  onSaved: () => void
}) {
  const editando = !!operacao
  const [valores, setValores] = useState<RiskOperationFormValues>(VAZIO)

  useEffect(() => {
    if (!open) return
    setValores(operacao ? paraFormulario(operacao) : VAZIO)
  }, [open, operacao])

  const set = <K extends keyof RiskOperationFormValues>(campo: K, valor: RiskOperationFormValues[K]) =>
    setValores((atual) => ({ ...atual, [campo]: valor }))

  const empresas = useQuery({
    queryKey: ['risk-operation-drawer', 'empresas'],
    queryFn: () => companiesApi.list({ perPage: 100 }),
    enabled: open && !editando,
  })

  const portadores = useQuery({
    queryKey: ['risk-operation-drawer', 'portadores', valores.company_id],
    queryFn: () => riskOperationsApi.carriersForCompany(valores.company_id as string),
    enabled: open && !editando && !!valores.company_id,
  })

  const tipos = useQuery({
    queryKey: ['risk-operation-drawer', 'tipos', valores.company_id, valores.carrier_id],
    queryFn: () => riskOperationsApi.typesForCarrier(valores.company_id as string, valores.carrier_id as string),
    enabled: open && !editando && !!valores.company_id && !!valores.carrier_id,
  })

  /** A cascata devolveu vazio: a empresa não tem portador com limite manual. */
  const semPortador = !!valores.company_id && portadores.isSuccess && (portadores.data?.length ?? 0) === 0

  const tipoEscolhido = useMemo(
    () => (tipos.data ?? []).find((t) => t.id === valores.operation_type_id),
    [tipos.data, valores.operation_type_id],
  )

  /**
   * **O bloco Datas some inteiro quando o tipo tem pré-faturamento** (FE-260):
   * a operação de pré-faturamento vive no par estático do limite, que não tem
   * janela. Em edição a resposta do servidor já traz `has_pre_faturamento`.
   */
  const comPre = editando ? operacao!.has_pre_faturamento : (tipoEscolhido?.has_pre_faturamento ?? false)

  /**
   * **FE-261 — o que falta, dito em português.** Enquanto houver pendência o
   * botão fica desabilitado *e explicado*, em vez de sumir.
   */
  const faltando = useMemo(() => {
    const pendencias: string[] = []
    if (!editando) {
      if (!valores.company_id) pendencias.push('empresa')
      if (!valores.carrier_id) pendencias.push('portador')
      if (!valores.operation_type_id) pendencias.push('tipo de operação')
    }
    if (valores.operation_value === null || valores.operation_value === undefined) {
      pendencias.push('capital da operação')
    }
    if (!comPre) {
      if (!valores.issue_date) pendencias.push('data de emissão')
      if (!valores.due_date) pendencias.push('data de vencimento')
    }
    return pendencias
  }, [editando, valores, comPre])

  const salvar = useMutation({
    mutationFn: () => {
      if (editando) {
        // **T-D5** — as datas nem são enviadas: a API as ignora, e mandar o que
        // é ignorado convida alguém a "consertar" o servidor depois.
        return riskOperationsApi.update(operacao!.id, {
          title: valores.title || undefined,
          contract_number: valores.contract_number || undefined,
          original_balance: valores.original_balance ?? 0,
          agreed_rate: valores.agreed_rate ?? 0,
          observation: valores.observation || undefined,
          is_on_variable: valores.is_on_variable,
          is_ended: valores.is_ended,
        })
      }

      const payload: RiskOperationInput = {
        company_id: valores.company_id as string,
        carrier_id: valores.carrier_id as string,
        operation_type_id: valores.operation_type_id as string,
        title: valores.title || undefined,
        contract_number: valores.contract_number || undefined,
        // Operação de tipo com pré-faturamento não tem janela; o servidor
        // exige as datas, então usamos a data de hoje nos dois campos, que é o
        // que a tela do legado enviava escondido.
        issue_date: iso(valores.issue_date ?? new Date()),
        due_date: iso(valores.due_date ?? valores.issue_date ?? new Date()),
        operation_value: valores.operation_value ?? 0,
        original_balance: valores.original_balance ?? 0,
        agreed_rate: valores.agreed_rate ?? 0,
        observation: valores.observation || undefined,
        is_on_variable: valores.is_on_variable,
        is_ended: valores.is_ended,
      }
      return riskOperationsApi.create(payload)
    },
    onSuccess: () => {
      notify.success(editando ? 'Operação atualizada.' : 'Operação criada.')
      onSaved()
      onClose()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível salvar a operação.')),
  })

  /**
   * **OPS-237 — o mecanismo dos 13 tooltips, e ele é da biblioteca.**
   *
   * O legado fazia `YAML.load_file` **a cada render** da parcial
   * (`risk_operations/new/_body.html.erb:15`): sumir o arquivo no deploy dava
   * 500 no formulário inteiro. Aqui o mapa vem de `GET /help/fields` uma vez
   * por sessão (S12), e **campo sem texto não ganha ícone**.
   *
   * **A Q-R9 foi superada pela DEC-88.** O `tasks.md` desta fatia (Phase 2)
   * dizia "portar o mecanismo, conteúdo em branco até o negócio escrever",
   * porque no legado os 13 textos são **o mesmo placeholder** ("Só um teste de
   * informações do campo…", `db/seed_assets/risk_operations_help_inputs.yml`).
   * A DEC-88 mandou **escrever** os 91 textos, e eles existem: 12 dos 13 deste
   * formulário estão preenchidos. O 13.º (`is_on_variable`) continua marcado
   * `TODO:` porque a pergunta "o que é o variável e quem apura?" segue aberta
   * com o usuário — e o servidor **filtra** as chaves `TODO:`, então esse
   * campo simplesmente não ganha ícone.
   */
  const rotulo = (texto: string, campo: string) => (
    <>
      {texto} <FieldHelp scope="risk_operations" field={campo} />
    </>
  )

  const somenteLeitura = (rotulo: string, valor: string | null | undefined) => (
    <div className="flex items-center gap-2 rounded-md border border-input bg-muted px-3 py-2 text-sm text-muted-foreground">
      <Lock className="h-3.5 w-3.5 shrink-0" aria-hidden />
      <span className="truncate">{valor || '—'}</span>
      <span className="sr-only">{rotulo} não pode ser alterado nesta operação</span>
    </div>
  )

  return (
    <SideDrawer
      open={open}
      onClose={onClose}
      title={editando ? 'Editar operação de risco' : 'Nova operação de risco'}
      footer={
        <div className="flex w-full flex-col gap-2">
          {faltando.length > 0 && (
            <p className="text-xs text-muted-foreground">
              Falta preencher: {faltando.join(', ')}.
            </p>
          )}
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={onClose}>Cancelar</Button>
            <Button
              onClick={() => salvar.mutate()}
              disabled={faltando.length > 0 || salvar.isPending}
            >
              {salvar.isPending ? 'Salvando…' : 'Salvar'}
            </Button>
          </div>
        </div>
      }
    >
      <div className="space-y-6">
        {/* --- Cadastro ------------------------------------------------- */}
        <section className="space-y-4">
          <h3 className="text-sm font-semibold text-foreground">Cadastro</h3>

          <Campo id="op-empresa" label={rotulo('Empresa', 'company_id')}>
            {/* `editando` já cobre o caso "veio de recebível" da FE-258: uma
                operação criada pelo borderô só chega a este formulário em
                edição, e aí os três campos já são readonly. Repetir
                `operacao?.receivable_id` aqui é condição morta — o TypeScript
                inclusive a estreita para `never`. */}
            {editando ? (
              somenteLeitura('Empresa', operacao?.company_title)
            ) : (
              <Select
                value={valores.company_id ?? ''}
                onChange={(v) => {
                  set('company_id', v || null)
                  set('carrier_id', null)
                  set('operation_type_id', null)
                }}
                options={[
                  { value: '', label: 'Selecione a empresa' },
                  ...(empresas.data?.items ?? []).map((c) => ({ value: c.id, label: c.title })),
                ]}
              />
            )}
          </Campo>

          <Campo
            id="op-portador"
            label={rotulo('Portador', 'carrier_id')}
            hint={
              // **FE-263, o segundo bloqueio.** A cascata devolve só portador
              // com limite ATIVO de tipo manual — que é o mesmo `where` que o
              // servidor aplica no `POST`. Quando vem vazia, o select ficaria
              // mudo e o operador descobriria o critério por tentativa e erro
              // (foi o que o legado fazia). Aqui a tela diz o que falta e para
              // onde ir.
              !editando && valores.company_id && !portadores.isFetching && semPortador
                ? 'Nenhum portador desta empresa tem limite ativo de tipo manual. Cadastre o limite em «Limites» antes de abrir a operação.'
                : undefined
            }
          >
            {editando ? (
              somenteLeitura('Portador', operacao?.carrier_title)
            ) : (
              <Select
                value={valores.carrier_id ?? ''}
                onChange={(v) => { set('carrier_id', v || null); set('operation_type_id', null) }}
                disabled={!valores.company_id}
                options={[
                  { value: '', label: 'Selecione o portador' },
                  ...(portadores.data ?? []).map((c) => ({ value: c.id, label: c.title })),
                ]}
              />
            )}
          </Campo>

          <Campo id="op-tipo" label={rotulo('Tipo de operação', 'operation_type_id')}>
            {editando ? (
              somenteLeitura('Tipo', operacao?.operation_subtype_title ?? operacao?.operation_type_title)
            ) : (
              <Select
                value={valores.operation_type_id ?? ''}
                onChange={(v) => set('operation_type_id', v || null)}
                disabled={!valores.carrier_id}
                options={[
                  { value: '', label: 'Selecione o tipo' },
                  ...(tipos.data ?? []).map((t) => ({ value: t.id, label: t.title })),
                ]}
              />
            )}
          </Campo>

          <Campo id="op-titulo" label={rotulo('Título', 'titulo')} hint={'Vazio, assume o nome do portador.'}>
            <Input id="op-titulo" value={valores.title} onChange={(e) => set('title', e.target.value)} />
          </Campo>

          <Campo id="op-contrato" label={rotulo('Nº do contrato', 'nro_contrato')}>
            <Input id="op-contrato" value={valores.contract_number}
                   onChange={(e) => set('contract_number', e.target.value)} />
          </Campo>
        </section>

        {/* --- Datas — some inteiro em tipo com pré-faturamento (FE-260) --- */}
        {!comPre && (
          <section className="space-y-4">
            <h3 className="text-sm font-semibold text-foreground">Datas</h3>

            <Campo id="op-emissao" label={rotulo('Emissão', 'issue_date')}>
              {editando
                ? somenteLeitura('Emissão', operacao?.issue_date)
                : <DatePicker id="op-emissao" value={valores.issue_date} onChange={(d) => set('issue_date', d)} />}
            </Campo>

            <Campo
              id="op-vencimento"
              label={rotulo('Vencimento', 'due_date')}
              hint={editando ? 'Para esticar o prazo, use "Prorrogar".' : undefined}
            >
              {editando
                ? somenteLeitura('Vencimento', operacao?.due_date)
                : <DatePicker id="op-vencimento" value={valores.due_date} onChange={(d) => set('due_date', d)} />}
            </Campo>
          </section>
        )}

        {/* --- Valores --------------------------------------------------- */}
        <section className="space-y-4">
          <h3 className="text-sm font-semibold text-foreground">Valores</h3>

          <Campo id="op-capital" label={rotulo('Capital da operação', 'operation_value')}>
            {editando ? (
              somenteLeitura('Capital', operacao ? String(operacao.operation_value) : null)
            ) : (
              <MoneyInput id="op-capital" value={valores.operation_value} onChange={(v) => set('operation_value', v)} />
            )}
          </Campo>

          <Campo
            id="op-saldo"
            label={rotulo('Saldo inicial', 'balance')}
            hint="Gravado com sinal negativo — é a convenção do produto."
          >
            <MoneyInput id="op-saldo" value={valores.original_balance} onChange={(v) => set('original_balance', v)} />
          </Campo>
        </section>

        {/* --- Taxa acordada --------------------------------------------- */}
        <section className="space-y-4">
          <h3 className="text-sm font-semibold text-foreground">Taxa acordada</h3>
          <Campo id="op-taxa" label={rotulo('Taxa acordada', 'agreed_rate')}>
            <PercentInput id="op-taxa" value={valores.agreed_rate} onChange={(v) => set('agreed_rate', v)} />
          </Campo>
        </section>

        {/* --- Outros ----------------------------------------------------- */}
        <section className="space-y-4">
          <h3 className="text-sm font-semibold text-foreground">Outros</h3>

          <Campo id="op-observacao" label={rotulo('Observação', 'description')}>
            <Textarea id="op-observacao" value={valores.observation}
                      onChange={(e) => set('observation', e.target.value)} rows={3} />
          </Campo>

          <div className="flex items-center justify-between gap-3">
            <span className="text-sm">Considerar no variável</span>
            <Switch checked={valores.is_on_variable}
                    onCheckedChange={(v) => set('is_on_variable', v)} />
          </div>

          {/* O campo "Encerrada" some em tipo com pré-faturamento, como no
              legado — o par estático não encerra. */}
          {!comPre && (
            <div className="flex items-center justify-between gap-3">
              <span className="text-sm">
                Encerrada
                <span className="block text-xs text-muted-foreground">
                  Rótulo: a operação encerrada continua consumindo limite e aceitando movimento.
                </span>
              </span>
              <Switch checked={valores.is_ended} onCheckedChange={(v) => set('is_ended', v)} />
            </div>
          )}
        </section>
      </div>
    </SideDrawer>
  )
}
