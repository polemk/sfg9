import { useEffect, useMemo, useState } from 'react'
import { Info } from 'lucide-react'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { Label } from '@/components/ui/Label'
import { Input } from '@/components/ui/Input'
import { Select } from '@/components/ui/Select'
import { DatePicker } from '@/components/ui/DatePicker'
import { MoneyInput } from '@/components/ui/NumericInput'
import { useInstallmentPreview } from '@/hooks/useInstallmentPreview'
import { formatarReais } from '@/lib/api/projects'
import { formatDate, toIsoDate } from '@/lib/utils/date'
import type { InstallmentDraft, RenegotiationInstallment } from '@/lib/api/renegotiations'

/**
 * **O painel de previsão** — os três modos: única, lote e edição (FE-220..FE-223).
 *
 * ## Os totais derivados vêm do SERVIDOR (FE-221 / contrato C2)
 *
 * Nada é somado aqui. `principal + juros + correção` parece trivial de fazer em
 * JavaScript — e é exatamente por parecer trivial que a regra financeira acaba
 * existindo em dois lugares (**D-09**). O painel mostra o que
 * `POST …/installments/preview` respondeu, que é o **mesmo serviço** que a
 * gravação usa. Enquanto a resposta não chega, o painel mostra o traço; nunca um
 * número provisório que vai piscar para outro.
 *
 * ## Três comportamentos que o legado não tinha
 *
 * - **Salvar só com principal > 0** (FE-222) — e o servidor responde 422 pelo
 *   mesmo motivo. No legado a validação existia no model, o erro era engolido, e
 *   a resposta era 200 "criada com sucesso" **sem ter criado nada** (D-52).
 * - **Repetições com mínimo 1** e intervalo obrigatório > 0. No legado
 *   `"abc".to_i` virava 0, o laço não rodava e a resposta continuava de sucesso.
 * - **Falha mantém o painel aberto com os valores digitados** (FE-223). Fechar em
 *   erro obriga a redigitar tudo.
 */
export interface InstallmentDrawerProps {
  open: boolean
  onClose: () => void
  renegotiationId: string
  /** Preenchido = modo EDIÇÃO. */
  editando?: RenegotiationInstallment | null
  delayTypes: string[]
  onSubmit: (rascunho: InstallmentDraft) => void
  salvando?: boolean
}

export function InstallmentDrawer({
  open,
  onClose,
  renegotiationId,
  editando,
  delayTypes,
  onSubmit,
  salvando,
}: InstallmentDrawerProps) {
  const modoEdicao = !!editando

  const [dueDate, setDueDate] = useState<Date | string | null>(null)
  const [mainValue, setMainValue] = useState<number | null>(null)
  const [interestValue, setInterestValue] = useState<number | null>(null)
  const [cmValue, setCmValue] = useState<number | null>(null)
  const [multiplas, setMultiplas] = useState(false)
  const [repeticoes, setRepeticoes] = useState(2)
  const [intervalo, setIntervalo] = useState(1)
  const [tipoIntervalo, setTipoIntervalo] = useState<string | null>(null)

  // Reabrir o painel recomeça o rascunho — menos na edição, que carrega a parcela.
  useEffect(() => {
    if (!open) return
    if (editando) {
      setDueDate(editando.due_date)
      setMainValue(Number(editando.main_value))
      setInterestValue(Number(editando.interest_value))
      setCmValue(Number(editando.monetary_correction_value))
      setMultiplas(false)
    } else {
      setDueDate(null)
      setMainValue(null)
      setInterestValue(null)
      setCmValue(null)
      setMultiplas(false)
      setRepeticoes(2)
      setIntervalo(1)
      setTipoIntervalo(delayTypes[2] ?? delayTypes[0] ?? null)
    }
  }, [open, editando, delayTypes])

  const rascunho: InstallmentDraft = useMemo(
    () => ({
      due_date: toIsoDate(dueDate) ?? '',
      main_value: mainValue,
      interest_value: interestValue ?? 0,
      monetary_correction_value: cmValue ?? 0,
      multiple: multiplas && !modoEdicao,
      repetitions: repeticoes,
      repetition_delay: intervalo,
      repetition_type: tipoIntervalo,
    }),
    [dueDate, mainValue, interestValue, cmValue, multiplas, modoEdicao, repeticoes, intervalo, tipoIntervalo],
  )

  const previa = useInstallmentPreview(renegotiationId, rascunho, {
    enabled: open,
    replacingId: editando?.id,
  })

  const principalValido = typeof mainValue === 'number' && mainValue > 0
  const loteValido = !multiplas || modoEdicao || (repeticoes >= 1 && intervalo >= 1 && !!tipoIntervalo)
  const podeSalvar = !!rascunho.due_date && principalValido && loteValido

  const derivada = previa.preview?.installments?.[0]

  return (
    <SideDrawer
      open={open}
      onClose={onClose}
      title={modoEdicao ? `Editar previsão #${editando?.number ?? ''}` : 'Nova previsão'}
      footer={
        <div className="flex items-center justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={salvando}>
            Cancelar
          </Button>
          <Button onClick={() => onSubmit(rascunho)} loading={salvando} disabled={!podeSalvar}>
            {modoEdicao ? 'Salvar' : multiplas ? `Criar ${repeticoes} previsões` : 'Criar previsão'}
          </Button>
        </div>
      }
    >
      <div className="flex flex-col gap-4">
        {!modoEdicao && (
          <div className="flex gap-2 rounded-lg bg-muted p-1" role="tablist" aria-label="Modo de criação">
            <ModoBotao ativo={!multiplas} onClick={() => setMultiplas(false)}>
              Parcela única
            </ModoBotao>
            <ModoBotao ativo={multiplas} onClick={() => setMultiplas(true)}>
              Múltiplas parcelas
            </ModoBotao>
          </div>
        )}

        <div className="flex flex-col gap-1.5">
          <Label htmlFor="due_date">{multiplas ? 'Vencimento da primeira parcela' : 'Vencimento'}</Label>
          <DatePicker id="due_date" value={dueDate} onChange={(valor) => setDueDate(valor)} />
        </div>

        {multiplas && !modoEdicao && (
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="repeticoes">Quantidade</Label>
              <Input
                id="repeticoes"
                type="number"
                min={1}
                value={repeticoes}
                onChange={(e) => setRepeticoes(Math.max(1, Number(e.target.value) || 1))}
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="intervalo">A cada</Label>
              <Input
                id="intervalo"
                type="number"
                min={1}
                value={intervalo}
                onChange={(e) => setIntervalo(Math.max(1, Number(e.target.value) || 1))}
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="tipoIntervalo">Período</Label>
              <Select
                id="tipoIntervalo"
                options={delayTypes.map((t) => ({ value: t, label: t }))}
                value={tipoIntervalo}
                onChange={setTipoIntervalo}
                block
              />
            </div>
          </div>
        )}

        <div className="grid gap-3 sm:grid-cols-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="main_value">Principal</Label>
            <MoneyInput id="main_value" value={mainValue} onChange={setMainValue} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="interest_value">Juros</Label>
            <MoneyInput id="interest_value" value={interestValue} onChange={setInterestValue} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="cm_value">Correção monetária</Label>
            <MoneyInput id="cm_value" value={cmValue} onChange={setCmValue} />
          </div>
        </div>

        {!principalValido && (
          <p className="text-xs text-muted-foreground">
            O principal precisa ser maior que zero — é a mesma regra que o servidor aplica.
          </p>
        )}

        {/* ---- A prévia. Os números são do SERVIDOR. ---- */}
        <section className="rounded-lg border border-border bg-muted/40 p-4">
          <header className="mb-3 flex items-center gap-2">
            <Info className="h-4 w-4 text-muted-foreground" aria-hidden />
            <h3 className="text-xs font-semibold uppercase tracking-[0.08em] text-muted-foreground">
              Prévia — calculada pelo servidor
            </h3>
          </header>

          <dl className="grid grid-cols-2 gap-3 text-sm">
            <Derivado rotulo="Principal + juros" valor={derivada?.main_value_with_interest} carregando={previa.loading} />
            <Derivado
              rotulo="Com correção"
              valor={derivada?.main_value_with_interest_cm}
              carregando={previa.loading}
            />
            <Derivado
              rotulo="Total da parcela"
              valor={derivada?.installment_total_value}
              carregando={previa.loading}
            />
            <Derivado rotulo="Pendente" valor={derivada?.pending_value} carregando={previa.loading} />
          </dl>

          {multiplas && !modoEdicao && (previa.preview?.installments?.length ?? 0) > 1 && (
            <div className="mt-3 border-t border-border pt-3">
              <p className="mb-1 text-xs text-muted-foreground">
                Vencimentos que serão criados ({previa.preview!.installments.length}):
              </p>
              <p className="font-numeric text-xs tabular-nums text-foreground">
                {previa
                  .preview!.installments.slice(0, 6)
                  .map((i) => formatDate(i.due_date))
                  .join(' · ')}
                {previa.preview!.installments.length > 6 && ' …'}
              </p>
            </div>
          )}

          {previa.error != null && (
            <p role="alert" className="mt-3 text-xs text-destructive-text">
              Não foi possível calcular a prévia. Confira a data e os valores.
            </p>
          )}

          {previa.idle && (
            <p className="mt-3 text-xs text-muted-foreground">
              Informe o vencimento e o principal para ver os totais.
            </p>
          )}
        </section>
      </div>
    </SideDrawer>
  )
}

function ModoBotao({
  ativo,
  onClick,
  children,
}: {
  ativo: boolean
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={ativo}
      onClick={onClick}
      className={`flex-1 rounded-md px-3 py-2 text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring ${
        ativo ? 'bg-card text-foreground shadow-e1' : 'text-muted-foreground hover:text-foreground'
      }`}
    >
      {children}
    </button>
  )
}

function Derivado({
  rotulo,
  valor,
  carregando,
}: {
  rotulo: string
  valor: string | undefined
  carregando?: boolean
}) {
  return (
    <div>
      <dt className="text-xs uppercase tracking-[0.05em] text-muted-foreground">{rotulo}</dt>
      <dd className="font-numeric tabular-nums text-foreground">
        {/* Enquanto a resposta não chega: traço, nunca um número local. */}
        {carregando || valor === undefined ? '—' : formatarReais(valor)}
      </dd>
    </div>
  )
}
