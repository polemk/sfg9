import { useEffect, useRef } from 'react'
import { notify } from '@/lib/notify'
import { Card } from '@/components/ui/Card'
import { DatePicker } from '@/components/ui/DatePicker'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { MoneyInput } from '@/components/ui/MoneyInput'
import { PercentInput } from '@/components/ui/NumericInput'
import { Select } from '@/components/ui/Select'
import { Textarea } from '@/components/ui/textarea'
import { FieldHelp } from '@/components/help/FieldHelp'
import type { Company } from '@/lib/api/projects'
import type { CarrierConnection } from '@/lib/api/projects'
import type { StructuredOperationType } from '../api/structuredOperations'
import { dataBr } from '../lib/format'

/**
 * **O formulário da operação estruturada** (`FE-293`, `FE-294`, `FE-297`).
 *
 * ## O layout é o do legado, em componentes do ai9
 *
 * Duas colunas: **Cadastro + Datas** à esquerda, **Valores + Taxa Acordada +
 * Outros** à direita — a mesma divisão de
 * `structured_operations/new/_body.html.erb`. No telefone as duas colunas
 * empilham (DEC-100): o formulário é de digitação, não de leitura, e cartão não
 * ajuda aqui.
 *
 * ## As três gambiarras do legado que NÃO são portadas
 *
 * 1. `f.hidden_field :id, name: "is_pub_domain", value: 1` — o campo `id` do
 *    registro renomeado para virar uma flag de domínio. O servidor do ai9 não
 *    tem esse conceito.
 * 2. `data-movements` no `<div>` raiz, carregando **o JSON de todos os
 *    `MovementKind` com `is_operation`** — e **nada** no JavaScript da tela o
 *    lê. Era peso morto no HTML de cada abertura.
 * 3. `f.text_field :project_id` e `:user_id` escondidos com `display: none` —
 *    os dois vêm do servidor: `project_id` é DERIVADO da empresa em todo save
 *    e `user_id` vem da SESSÃO (DB-297).
 *
 * ## As 13 tooltips existem como MECANISMO (Q-R9 → DEC-88)
 *
 * No legado os 13 `info_tippy` liam
 * `db/seed_assets/structured_operations_help_inputs.yml`, e o arquivo inteiro
 * era o **mesmo placeholder** repetido. A Q-R9 mandava portar o mecanismo com
 * conteúdo em branco; a **DEC-88**, posterior, mandou **escrever os textos** —
 * e eles estão escritos, no mesmo YAML, servidos por
 * `GET /api/v1/field_help`. Campo sem texto (o `is_on_variable`, marcado
 * `TODO:`) simplesmente **não ganha ícone**: um tooltip vazio ensina o operador
 * a parar de clicar nos que têm conteúdo.
 *
 * ## `FE-294` — a máscara, e o aviso que NÃO impede a digitação
 *
 * Capital e Saldo Inicial usam o `MoneyInput` da casa (preenchimento da direita
 * para a esquerda, como o `jquery-mask-plugin` do legado fazia com
 * `.money-value`). A Taxa acordada usa o `PercentInput`.
 *
 * O aviso de separador (`1.234.56`, o copiar-e-colar de planilha em locale
 * errado) **continua sendo um toast e continua não impedindo a digitação** —
 * replicado, tarefa 10.2. O que muda é que o valor mal formado **não é
 * adivinhado**: o campo mantém o último valor bom em vez de gravar `123456`
 * ou `1234.56` conforme o caminho, que é o que o legado fazia.
 */
export interface OperationFormValues {
  company_id: string
  carrier_id: string
  operation_type_id: string
  title: string
  contract_number: string
  issue_date: Date | null
  due_date: Date | null
  operation_value: number | null
  /** Digitado em MÓDULO. Quem inverte o sinal é o servidor (DEC-01). */
  original_balance: number | null
  agreed_rate: number | null
  observation: string
  is_on_variable: boolean
  is_ended: boolean
}

const ESCOPO_AJUDA = 'structured_operations'

export function OperationForm({
  valores,
  onChange,
  empresas,
  portadores,
  tipos,
  editando,
  estreito,
}: {
  valores: OperationFormValues
  onChange: <K extends keyof OperationFormValues>(campo: K, valor: OperationFormValues[K]) => void
  empresas: Company[]
  portadores: CarrierConnection[]
  /** **Só os ATIVOS** — o cadastro usa `.active`, o filtro da lista usa `.all` (B-04). */
  tipos: StructuredOperationType[]
  editando: boolean
  estreito: boolean
}) {
  return (
    <div className={estreito ? 'space-y-4' : 'grid grid-cols-2 items-start gap-4'}>
      {/* --- Coluna esquerda: Cadastro + Datas ------------------------------ */}
      <div className="space-y-4">
        <Card className="space-y-4 p-5">
          <h3 className="font-title text-sm font-semibold uppercase tracking-[0.05em] text-muted-foreground">
            Cadastro
          </h3>

          <div className="grid gap-4 sm:grid-cols-2">
            <Campo id="contract_number" rotulo="Contrato" ajuda="nro_contrato">
              <Input
                id="contract_number"
                value={valores.contract_number}
                onChange={(e) => onChange('contract_number', e.target.value)}
                placeholder="Ex.: C234-8"
              />
            </Campo>

            <Campo
              id="title"
              rotulo="Título"
              ajuda="titulo"
              dica="Em branco, a operação passa a se chamar como o portador."
            >
              <Input
                id="title"
                value={valores.title}
                onChange={(e) => onChange('title', e.target.value)}
                placeholder="Ex.: Operação de fomento X"
              />
            </Campo>
          </div>

          <Campo id="company_id" rotulo="Empresa" ajuda="company_id" obrigatorio>
            <Select
              id="company_id"
              aria-label="Empresa"
              placeholder="clique para escolher…"
              value={valores.company_id || null}
              onChange={(v) => onChange('company_id', v ?? '')}
              options={empresas.map((c) => ({ value: c.id, label: c.title }))}
            />
          </Campo>

          <div className="grid gap-4 sm:grid-cols-2">
            <Campo id="carrier_id" rotulo="Portador" ajuda="carrier_id" obrigatorio>
              <Select
                id="carrier_id"
                aria-label="Portador"
                placeholder="clique para escolher…"
                value={valores.carrier_id || null}
                onChange={(v) => onChange('carrier_id', v ?? '')}
                options={portadores.map((c) => ({
                  value: c.carrier_id,
                  label: c.carrier_title ?? 'Portador',
                }))}
              />
            </Campo>

            <Campo
              id="operation_type_id"
              rotulo="Tipo de operação"
              ajuda="operation_type_id"
              obrigatorio
            >
              <Select
                id="operation_type_id"
                aria-label="Tipo de operação"
                placeholder="clique para escolher…"
                value={valores.operation_type_id || null}
                onChange={(v) => onChange('operation_type_id', v ?? '')}
                // B-04 — aqui só ATIVOS. O filtro da lista mostra os inativos.
                options={tipos.map((t) => ({ value: t.id, label: t.title }))}
              />
            </Campo>
          </div>

          <Campo id="observation" rotulo="Observação" ajuda="description">
            <Textarea
              id="observation"
              rows={3}
              value={valores.observation}
              onChange={(e) => onChange('observation', e.target.value)}
            />
          </Campo>
        </Card>

        <Card className="space-y-4 p-5">
          <h3 className="font-title text-sm font-semibold uppercase tracking-[0.05em] text-muted-foreground">
            Datas
          </h3>

          {editando ? (
            // **T-D5 — na edição as duas datas são READONLY na tela e
            // IMUTÁVEIS no servidor.** O legado fazia isso com dois campos
            // `*_fake` que nem sequer eram enviados; aqui é o mesmo efeito, sem
            // o campo fantasma.
            <div className="grid gap-4 sm:grid-cols-2">
              <Campo id="issue_date_ro" rotulo="Data de emissão" ajuda="issue_date">
                <Input id="issue_date_ro" readOnly value={dataBr(iso(valores.issue_date))} />
              </Campo>
              <Campo id="due_date_ro" rotulo="Data de vencimento" ajuda="due_date">
                <Input id="due_date_ro" readOnly value={dataBr(iso(valores.due_date))} />
              </Campo>
            </div>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2">
              {/* FE-297 — a amarração cruzada: a emissão define o mínimo do
                  vencimento e o vencimento define o máximo da emissão. O
                  legado tinha o par, e junto o seletor `.closing_date_hidden`,
                  herdado de outra tela — esse sai. */}
              <Campo id="issue_date" rotulo="Data de emissão" ajuda="issue_date" obrigatorio>
                <DatePicker
                  id="issue_date"
                  value={valores.issue_date}
                  max={valores.due_date}
                  onChange={(d) => onChange('issue_date', d)}
                />
              </Campo>
              <Campo id="due_date" rotulo="Data de vencimento" ajuda="due_date" obrigatorio>
                <DatePicker
                  id="due_date"
                  value={valores.due_date}
                  min={valores.issue_date}
                  onChange={(d) => onChange('due_date', d)}
                />
              </Campo>
            </div>
          )}
        </Card>
      </div>

      {/* --- Coluna direita: Valores + Taxa Acordada + Outros --------------- */}
      <div className="space-y-4">
        <Card className="space-y-4 p-5">
          <h3 className="font-title text-sm font-semibold uppercase tracking-[0.05em] text-muted-foreground">
            Valores
          </h3>

          <div className="grid gap-4 sm:grid-cols-2">
            <Campo
              id="operation_value"
              rotulo="Capital da operação"
              ajuda="operation_value"
              obrigatorio
            >
              <MoneyInput
                id="operation_value"
                value={valores.operation_value}
                onChange={(v) => onChange('operation_value', v)}
              />
            </Campo>

            <Campo
              id="original_balance"
              rotulo="Saldo inicial"
              ajuda="balance"
              dica="Digitado em módulo. É gravado negativo, por convenção do sistema."
            >
              <MoneyInput
                id="original_balance"
                value={valores.original_balance}
                onChange={(v) => onChange('original_balance', v)}
              />
            </Campo>
          </div>
        </Card>

        <Card className="space-y-4 p-5">
          <h3 className="font-title text-sm font-semibold uppercase tracking-[0.05em] text-muted-foreground">
            Taxa Acordada
          </h3>

          <Campo
            id="agreed_rate"
            rotulo="Taxa acordada"
            ajuda="agreed_rate"
            dica="Registro do que foi combinado. O valor faturado sai da remuneração do projeto, não desta taxa."
          >
            <TaxaComAviso
              id="agreed_rate"
              value={valores.agreed_rate}
              onChange={(v) => onChange('agreed_rate', v)}
            />
          </Campo>
        </Card>

        <Card className="space-y-4 p-5">
          <h3 className="font-title text-sm font-semibold uppercase tracking-[0.05em] text-muted-foreground">
            Outros
          </h3>

          <Campo id="is_on_variable" rotulo="Considerar no variável" ajuda="is_on_variable">
            <Select
              id="is_on_variable"
              aria-label="Considerar no variável"
              value={valores.is_on_variable ? 'sim' : 'nao'}
              onChange={(v) => onChange('is_on_variable', v === 'sim')}
              options={[
                { value: 'sim', label: 'Considerar no variável' },
                { value: 'nao', label: 'Não considerar no variável' },
              ]}
            />
          </Campo>

          <Campo id="is_ended" rotulo="Encerrada" ajuda="is_ended">
            <Select
              id="is_ended"
              aria-label="Encerrada"
              value={valores.is_ended ? 'sim' : 'nao'}
              onChange={(v) => onChange('is_ended', v === 'sim')}
              options={[
                { value: 'sim', label: 'Encerrado' },
                { value: 'nao', label: 'Não encerrado' },
              ]}
            />
          </Campo>
        </Card>
      </div>
    </div>
  )
}

/**
 * `FE-294`, replicado: o aviso de separador **é toast** e **não impede a
 * digitação**.
 *
 * O `PercentInput` da casa mostra o aviso embaixo do campo e segura o valor até
 * o texto ser interpretável — o usuário continua digitando o tempo todo. Aqui o
 * aviso é **promovido a toast**, como no legado, e disparado só na transição
 * (não a cada tecla, que era o que tornaria a correção pior que o defeito).
 */
function TaxaComAviso({
  id,
  value,
  onChange,
}: {
  id: string
  value: number | null
  onChange: (v: number | null) => void
}) {
  const avisado = useRef(false)

  return (
    <PercentInput
      id={id}
      value={value}
      onChange={onChange}
      // A faixa fica ABERTA — sem `min`, sem `max` (T-D9 / FE-305). É a taxa
      // que multiplica todo o faturamento; travá-la é decisão do negócio, não
      // da migração.
      onWarningChange={(aviso) => {
        if (aviso && !avisado.current) {
          avisado.current = true
          notify.warning(aviso)
        }
        if (!aviso) avisado.current = false
      }}
    />
  )
}

function Campo({
  id,
  rotulo,
  ajuda,
  dica,
  obrigatorio,
  children,
}: {
  id: string
  rotulo: string
  /** Chave no YAML de ajuda. Sem texto, o ícone não aparece. */
  ajuda: string
  dica?: string
  obrigatorio?: boolean
  children: React.ReactNode
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>
        {rotulo}
        {obrigatorio && (
          <span aria-hidden="true" className="ml-0.5 text-destructive">
            *
          </span>
        )}{' '}
        <FieldHelp scope={ESCOPO_AJUDA} field={ajuda} />
      </Label>
      {children}
      {dica && <p className="text-xs text-muted-foreground">{dica}</p>}
    </div>
  )
}

/** `Date` → `YYYY-MM-DD` no fuso local. */
export function iso(d: Date | null): string | undefined {
  if (!d) return undefined
  const mes = String(d.getMonth() + 1).padStart(2, '0')
  const dia = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${mes}-${dia}`
}

/** Efeito de pré-seleção: a primeira opção ativa, como o legado fazia (`@first_*`). */
export function usePreSelecao(
  valores: OperationFormValues,
  onChange: <K extends keyof OperationFormValues>(campo: K, valor: OperationFormValues[K]) => void,
  {
    empresas,
    portadores,
    tipos,
    pronto,
  }: {
    empresas: Company[]
    portadores: CarrierConnection[]
    tipos: StructuredOperationType[]
    pronto: boolean
  },
) {
  useEffect(() => {
    if (!pronto) return
    if (!valores.company_id && empresas[0]) onChange('company_id', empresas[0].id)
    if (!valores.carrier_id && portadores[0]) onChange('carrier_id', portadores[0].carrier_id)
    if (!valores.operation_type_id && tipos[0]) onChange('operation_type_id', tipos[0].id)
    // Só quando as listas chegam, e só para preencher o que está vazio.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pronto, empresas, portadores, tipos])
}
