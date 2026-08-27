import { useEffect, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, Lock } from 'lucide-react'
import { Campo } from '@/app/pages/catalogs/CatalogFields'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { Select } from '@/components/ui/Select'
import { MoneyInput, PercentInput } from '@/components/ui/NumericInput'
import { companiesApi } from '@/lib/api/projects'
import { riskControlsApi, riskOperationTypesApi, type RiskControl } from '../api/risk'

export interface RiskControlFormValues {
  company_id: string | null
  carrier_id: string | null
  risk_operation_type_id: string | null
  limite: number | null
  taxa: number | null
  original_balance: number | null
  original_balance_pre: number | null
}

export const LIMITE_VAZIO: RiskControlFormValues = {
  company_id: null,
  carrier_id: null,
  risk_operation_type_id: null,
  limite: 0,
  taxa: 0,
  original_balance: 0,
  original_balance_pre: 0,
}

/**
 * **Criar / editar limite** (FE-244, FE-245, FE-248).
 *
 * ### A cascata empresa → portador é UM critério só
 *
 * O select de portador é populado por `GET /risk_controls/carriers?company_id=`,
 * que devolve **os portadores conectados ao projeto** — exatamente o mesmo
 * `where` que o servidor usa para aceitar o `carrier_id` no `POST`. No legado a
 * tela oferecia `Carrier.all` e o servidor recusava metade das escolhas
 * (FE-241): o usuário descobria o critério por tentativa e erro.
 *
 * ### Empresa, portador e tipo são bloqueados na edição — com par no servidor
 *
 * Decisão **B-01**. Mudá-los moveria a exposição de uma combinação para outra
 * arrastando as operações que já consomem o limite. No legado os três estavam no
 * `permit` e **só a tela** os desabilitava — quem chamasse o endpoint direto
 * trocava. Aqui a tela explica, e o servidor responde 422 (BE-235).
 *
 * ### "Saldo Inicial" só aparece em tipo com pré-faturamento, e só na criação
 *
 * FE-245. Os dois campos viram o par estático de operações no `after_create`
 * (BE-241); depois de criado o par já existe, e reescrever os campos não o
 * mudaria — mostrar um campo que não faz nada é pior do que não mostrá-lo.
 */
export function RiskControlDrawer({
  open,
  onClose,
  editing,
  values,
  setValue,
  onSubmit,
  saving,
}: {
  open: boolean
  onClose: () => void
  editing: RiskControl | null
  values: RiskControlFormValues
  setValue: <K extends keyof RiskControlFormValues>(campo: K, valor: RiskControlFormValues[K]) => void
  onSubmit: () => void
  saving: boolean
}) {
  const empresas = useQuery({
    queryKey: ['risk-drawer-companies'],
    queryFn: () => companiesApi.list({ perPage: 100 }),
    enabled: open,
  })

  const tipos = useQuery({
    queryKey: ['risk-operation-types', 'ativos'],
    queryFn: () => riskOperationTypesApi.list({ active: true, perPage: 100 }),
    enabled: open,
  })

  const portadores = useQuery({
    queryKey: ['risk-drawer-carriers', values.company_id],
    queryFn: () => riskControlsApi.carriersForCompany(values.company_id as string),
    enabled: open && Boolean(values.company_id),
  })

  // Trocar a empresa zera o portador: o conjunto de portadores muda com ela, e
  // manter a escolha antiga é como o formulário do legado mandava um par que o
  // servidor recusava.
  useEffect(() => {
    if (editing) return
    if (values.carrier_id && !(portadores.data ?? []).some((c) => c.id === values.carrier_id)) {
      setValue('carrier_id', null)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [values.company_id, portadores.data])

  const tipoEscolhido = useMemo(
    () => (tipos.data?.items ?? []).find((t) => t.id === values.risk_operation_type_id) ?? null,
    [tipos.data, values.risk_operation_type_id],
  )

  const semEmpresa = !empresas.isLoading && (empresas.data?.items.length ?? 0) === 0
  const semPortador = Boolean(values.company_id) && !portadores.isLoading && (portadores.data?.length ?? 0) === 0
  const bloqueado = Boolean(editing)
  const mostrarSaldoInicial = !bloqueado && Boolean(tipoEscolhido?.has_pre_faturamento)

  const podeSalvar =
    Boolean(values.company_id) && Boolean(values.carrier_id) && Boolean(values.risk_operation_type_id)

  return (
    <SideDrawer
      open={open}
      onClose={onClose}
      title={editing ? 'Editar limite' : 'Novo limite de risco'}
      footer={
        <div className="flex gap-2">
          <Button variant="secondary" className="flex-1" onClick={onClose}>
            Cancelar
          </Button>
          <Button className="flex-1" loading={saving} disabled={!podeSalvar} onClick={onSubmit}>
            Salvar
          </Button>
        </div>
      }
    >
      {bloqueado && (
        <p className="flex items-start gap-2 rounded-md border border-border bg-muted/40 p-3 text-xs text-muted-foreground">
          <Lock aria-hidden="true" className="mt-0.5 h-3.5 w-3.5 shrink-0" />
          <span>
            Empresa, portador e tipo definem <strong>qual</strong> limite é este e não podem ser trocados. Para
            outra combinação, cadastre um limite novo.
          </span>
        </p>
      )}

      <Campo
        id="company_id"
        label="Empresa"
        hint={
          semEmpresa
            ? 'Este projeto ainda não tem empresa cadastrada. Cadastre uma em "Empresas" antes de criar o limite.'
            : undefined
        }
      >
        <Select
          id="company_id"
          options={(empresas.data?.items ?? []).map((e) => ({ value: e.id, label: e.title }))}
          value={values.company_id}
          onChange={(v) => setValue('company_id', v)}
          disabled={bloqueado || semEmpresa}
          placeholder={semEmpresa ? 'Nenhuma empresa neste projeto' : 'Selecione a empresa…'}
        />
      </Campo>

      <Campo
        id="carrier_id"
        label="Portador"
        hint={
          !values.company_id
            ? 'Escolha a empresa primeiro — os portadores vêm do projeto dela.'
            : semPortador
              ? 'Nenhum portador conectado a este projeto. Conecte um em "Portadores do projeto" antes de criar o limite.'
              : 'Só portadores conectados a este projeto — é o mesmo critério que o servidor aplica.'
        }
      >
        <Select
          id="carrier_id"
          options={(portadores.data ?? []).map((c) => ({
            value: c.id,
            label: c.title,
            description: c.group_title ?? undefined,
          }))}
          value={values.carrier_id}
          onChange={(v) => setValue('carrier_id', v)}
          disabled={bloqueado || !values.company_id || semPortador}
          placeholder={values.company_id ? 'Selecione o portador…' : 'Escolha a empresa primeiro'}
        />
      </Campo>

      <Campo
        id="risk_operation_type_id"
        label="Tipo de limite"
        hint={
          tipoEscolhido?.has_pre_faturamento
            ? 'Este tipo usa operações estáticas: o limite nasce com o par pré-faturamento / antecipação.'
            : undefined
        }
      >
        <Select
          id="risk_operation_type_id"
          options={(tipos.data?.items ?? []).map((t) => ({
            value: t.id,
            label: t.title,
            description: t.has_pre_faturamento ? 'Com pré-faturamento' : undefined,
          }))}
          value={values.risk_operation_type_id}
          onChange={(v) => setValue('risk_operation_type_id', v)}
          disabled={bloqueado}
          placeholder="Selecione o tipo…"
        />
      </Campo>

      <Campo id="limite" label="Limite" hint="Zero é um valor válido: significa teto zerado, não campo vazio.">
        <MoneyInput id="limite" value={values.limite} onChange={(v) => setValue('limite', v)} />
      </Campo>

      <Campo id="taxa" label="Taxa" hint="Taxa acordada do limite, em % ao mês.">
        <PercentInput id="taxa" value={values.taxa} onChange={(v) => setValue('taxa', v)} />
      </Campo>

      {mostrarSaldoInicial && <InitialBalanceFields values={values} setValue={setValue} />}
    </SideDrawer>
  )
}

/**
 * **Saldo Inicial** (FE-245) — só para tipo com pré-faturamento e só na criação.
 *
 * Os dois valores viram o par estático de operações. A troca importa e é fácil
 * de errar: "Liquidável" alimenta a operação de **antecipação** e "Pré" alimenta
 * a de **pré-faturamento** (`original_balance` × `original_balance_pre`).
 *
 * O aviso ao pé não é decoração: o saldo inicial **não aparece** na exposição
 * até que a operação estática receba um movimento. É como o painel calcula hoje
 * (o saldo de uma operação sem movimento é `0`, não o `original_balance`), e
 * quem cadastra precisa saber disso antes de estranhar o número.
 */
function InitialBalanceFields({
  values,
  setValue,
}: {
  values: RiskControlFormValues
  setValue: <K extends keyof RiskControlFormValues>(campo: K, valor: RiskControlFormValues[K]) => void
}) {
  return (
    <div className="space-y-4 rounded-md border border-border bg-muted/30 p-3">
      <div>
        <p className="text-sm font-medium text-foreground">Saldo inicial</p>
        <p className="mt-0.5 text-xs text-muted-foreground">
          Abre o par de operações estáticas do limite. Só pode ser informado agora.
        </p>
      </div>

      <Campo id="original_balance" label="Liquidável">
        <MoneyInput
          id="original_balance"
          value={values.original_balance}
          onChange={(v) => setValue('original_balance', v)}
        />
      </Campo>

      <Campo id="original_balance_pre" label="Pré-faturamento">
        <MoneyInput
          id="original_balance_pre"
          value={values.original_balance_pre}
          onChange={(v) => setValue('original_balance_pre', v)}
        />
      </Campo>

      <p className="flex items-start gap-2 text-xs text-muted-foreground">
        <AlertTriangle aria-hidden="true" className="mt-0.5 h-3.5 w-3.5 shrink-0 text-warning" />
        <span>
          O saldo inicial <strong>só entra na exposição</strong> quando a operação estática receber o primeiro
          movimento. Até lá o painel mostra zero para este limite — é assim que o cálculo funciona.
        </span>
      </p>
    </div>
  )
}
