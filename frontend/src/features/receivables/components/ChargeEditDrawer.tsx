import { useEffect, useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { DatePicker } from '@/components/ui/DatePicker'
import { Label } from '@/components/ui/Label'
import { Select } from '@/components/ui/Select'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { CHARGE_STATES, chargesApi, type Charge, type ChargeState } from '../api/receivables'

/**
 * **FE-181 / FE-183 / FE-186 — a edição da cobrança, que não existia em tela
 * nenhuma.**
 *
 * `chargesApi.update` e o `PUT /api/v1/charges/:id` existiam e funcionavam;
 * `grep -rn 'chargesApi.update' src` não achava um consumidor. A consequência
 * não era cosmética: **a situação "Faturado" era inalcançável pela interface**.
 * No legado só se chegava a ela editando o pacote, então a funcionalidade tinha
 * sumido inteira — e a lista exibia uma coluna "Situação" que ninguém conseguia
 * mudar.
 *
 * Componente compartilhado, e não uma cópia por tela: a lista (FE-181) e o
 * detalhe (FE-183) abrem a MESMA gaveta. Duas cópias divergiriam na primeira
 * regra nova, e a regra aqui é justamente a que não pode divergir — `done` é
 * porta de uma via.
 *
 * Continua gaveta pelo mesmo critério que manteve a criação em gaveta: dois
 * campos é formulário curto. O DETALHE virou página porque leva tabela.
 */
export function ChargeEditDrawer({
  charge,
  onClose,
}: {
  /** A cobrança em edição, ou `null` com a gaveta fechada. */
  charge: Charge | null
  onClose: () => void
}) {
  const queryClient = useQueryClient()
  const [data, setData] = useState<Date | null>(null)
  const [estado, setEstado] = useState<ChargeState>('editing')

  // O rascunho é recarregado a cada abertura, e não no `onClick` de quem chama:
  // assim "Cancelar" é cancelamento de verdade, e reabrir a mesma cobrança
  // depois de desistir não traz de volta o que foi digitado antes.
  useEffect(() => {
    if (!charge) return
    // `date` chega como `AAAA-MM-DD`. `new Date('2026-08-27')` seria lido como
    // UTC e voltaria um dia no fuso de São Paulo — a data apareceria diferente
    // da que o servidor guarda, sem ninguém ter editado nada.
    const [ano, mes, dia] = charge.date.split('-').map(Number)
    setData(new Date(ano, mes - 1, dia))
    setEstado(charge.state)
  }, [charge])

  const salvar = useMutation({
    mutationFn: (dados: { id: string; date: string; state: ChargeState }) =>
      chargesApi.update(dados.id, { date: dados.date, state: dados.state }),
    onSuccess: (atualizada) => {
      notify.success(
        atualizada.done
          ? 'Cobrança faturada. A partir de agora ela não aceita mais alteração.'
          : 'Cobrança atualizada.',
      )
      // Invalida a lista E o detalhe: as duas telas abrem esta gaveta, e a que
      // não fosse invalidada mostraria o valor velho até um recarregamento.
      queryClient.invalidateQueries({ queryKey: ['charges'] })
      queryClient.invalidateQueries({ queryKey: ['charge', atualizada.id] })
      onClose()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível atualizar a cobrança.')),
  })

  const iso = (d: Date) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`

  return (
    <SideDrawer
      open={charge !== null}
      onClose={onClose}
      title="Editar cobrança"
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="ghost" onClick={onClose} disabled={salvar.isPending}>
            Cancelar
          </Button>
          <Button
            onClick={() => charge && data && salvar.mutate({ id: charge.id, date: iso(data), state: estado })}
            disabled={!data || salvar.isPending}
          >
            {salvar.isPending ? 'Salvando…' : 'Salvar'}
          </Button>
        </div>
      }
    >
      <div className="space-y-4">
        <div className="space-y-1.5">
          <Label htmlFor="charge_edit_date">Data da cobrança</Label>
          <DatePicker id="charge_edit_date" value={data} onChange={setData} />
        </div>

        <div className="space-y-1.5">
          <Label htmlFor="charge_edit_state">Situação</Label>
          <Select
            id="charge_edit_state"
            value={estado}
            onChange={setEstado}
            options={CHARGE_STATES}
          />
          {estado === 'done' ? (
            // O aviso não é decoração. `done` é porta de uma via: o servidor
            // recusa qualquer alteração depois (D-18), então quem marca aqui
            // precisa saber que não há volta pela tela nem pela API.
            <p className="text-xs text-destructive">
              <strong>Faturado não tem volta.</strong> Depois de salvar, esta cobrança não aceita mais alteração
              nem exclusão — nem por aqui, nem pela API.
            </p>
          ) : (
            <p className="text-xs text-muted-foreground">
              "Disponível" libera o pacote para o cliente. "Faturado" o fecha em definitivo.
            </p>
          )}
        </div>
      </div>
    </SideDrawer>
  )
}
