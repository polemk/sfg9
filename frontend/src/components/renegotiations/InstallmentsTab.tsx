import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { CalendarRange, CheckSquare, Plus, Square, X } from 'lucide-react'
import { notify } from '@/lib/notify'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { MobileActionBar } from '@/components/mobile/MobileActionBar'
import { MobileActionsSheet } from '@/components/mobile/MobileRowActions'
import { useMobile } from '@/hooks/useMobile'
import { formatarReais } from '@/lib/api/projects'
import { formatDate } from '@/lib/utils/date'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import {
  renegotiationsApi,
  type InstallmentDraft,
  type RenegotiationInstallment,
  type RenegotiationPayment,
} from '@/lib/api/renegotiations'
import { InstallmentRow } from './InstallmentRow'
import { InstallmentDrawer } from './InstallmentDrawer'
import { PaymentDrawer } from './PaymentDrawer'

/**
 * **PREVISÕES** — a lista de parcelas, com pagamentos aninhados (FE-213..FE-219).
 *
 * ## Os quatro estados do contêiner, todos presentes
 *
 * Carregando, vazio, **erro** e conteúdo. O terceiro é o que faltava: a lista de
 * parcelas do legado **não tinha tratamento de erro nenhum** — a falha deixava a
 * tela no último estado, indistinguível de "não há nada".
 *
 * ## O modo seleção, e a perda de dado que ele fecha
 *
 * "Selecionar todos" pega **só as previsões sem pagamento** (FE-217), porque são
 * as únicas que o servidor aceita remover. A confirmação **não expira** (FE-218):
 * no legado a caixa de uma operação irreversível se descartava sozinha em 6
 * segundos, e refazer a ação era como o usuário acabava apagando parcelas a mais
 * (**D-51**).
 *
 * ⚠ O botão **"Excluir todas as parcelas" NÃO é portado** — nem tela, nem
 * backend (DEC-53 #3): operação destrutiva em massa, sem transação, que ninguém
 * pediu. Se voltar, volta como ação explícita, com confirmação e trilha.
 */
export interface InstallmentsTabProps {
  renegotiationId: string
  podeEscrever: boolean
  delayTypes: string[]
}

export function InstallmentsTab({ renegotiationId, podeEscrever, delayTypes }: InstallmentsTabProps) {
  const queryClient = useQueryClient()
  const mobile = useMobile()

  const [expandidas, setExpandidas] = useState<Set<string>>(new Set())
  const [modoSelecao, setModoSelecao] = useState(false)
  const [selecionadas, setSelecionadas] = useState<Set<string>>(new Set())
  const [painelParcela, setPainelParcela] = useState<{ aberto: boolean; editando: RenegotiationInstallment | null }>({
    aberto: false,
    editando: null,
  })
  const [painelPagamento, setPainelPagamento] = useState<{
    aberto: boolean
    installmentId: string | null
    editando: RenegotiationPayment | null
  }>({ aberto: false, installmentId: null, editando: null })
  const [confirmarLote, setConfirmarLote] = useState(false)
  const [confirmarParcela, setConfirmarParcela] = useState<RenegotiationInstallment | null>(null)
  const [confirmarPagamento, setConfirmarPagamento] = useState<RenegotiationPayment | null>(null)
  const [acoesMobile, setAcoesMobile] = useState<RenegotiationInstallment | null>(null)

  const consulta = useQuery({
    queryKey: ['renegotiation-installments', renegotiationId],
    queryFn: () => renegotiationsApi.installments.list(renegotiationId),
  })

  const parcelas = consulta.data?.items ?? []
  const semPagamento = useMemo(
    () => parcelas.filter((p) => !p.has_payments && p.payments.length === 0),
    [parcelas],
  )

  function recarregar() {
    queryClient.invalidateQueries({ queryKey: ['renegotiation-installments', renegotiationId] })
    queryClient.invalidateQueries({ queryKey: ['renegotiation', renegotiationId] })
    queryClient.invalidateQueries({ queryKey: ['renegotiation-general-values', renegotiationId] })
  }

  // --- Mutações -----------------------------------------------------------
  const criarParcela = useMutation({
    mutationFn: (rascunho: InstallmentDraft) => renegotiationsApi.installments.create(renegotiationId, rascunho),
    onSuccess: (resposta) => {
      notify.success(
        resposta.created === 1 ? 'Previsão criada.' : `${resposta.created} previsões criadas.`,
      )
      // **Fecha em sucesso** (FE-223). Em falha, o `onError` NÃO fecha — os
      // valores digitados continuam lá.
      setPainelParcela({ aberto: false, editando: null })
      recarregar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível criar a previsão.')),
  })

  const editarParcela = useMutation({
    mutationFn: ({ id, rascunho }: { id: string; rascunho: InstallmentDraft }) =>
      renegotiationsApi.installments.update(renegotiationId, id, {
        due_date: rascunho.due_date,
        main_value: rascunho.main_value ?? 0,
        interest_value: rascunho.interest_value ?? 0,
        monetary_correction_value: rascunho.monetary_correction_value ?? 0,
      }),
    onSuccess: () => {
      notify.success('Previsão atualizada.')
      setPainelParcela({ aberto: false, editando: null })
      recarregar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível atualizar a previsão.')),
  })

  const removerParcela = useMutation({
    mutationFn: (parcela: RenegotiationInstallment) =>
      renegotiationsApi.installments.remove(renegotiationId, parcela.id),
    onSuccess: () => {
      notify.success('Previsão removida.')
      setConfirmarParcela(null)
      recarregar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível remover a previsão.')),
  })

  const removerLote = useMutation({
    mutationFn: (ids: string[]) => renegotiationsApi.installments.removeBatch(renegotiationId, ids),
    onSuccess: (resposta) => {
      notify.success(`${resposta.deleted} previsão(ões) removida(s).`)
      setConfirmarLote(false)
      setModoSelecao(false)
      setSelecionadas(new Set())
      recarregar()
    },
    // O erro REAL do servidor aparece — e ele diz **qual** id falhou, porque nada
    // foi removido (D-51).
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível remover as previsões.')),
  })

  const salvarPagamento = useMutation({
    mutationFn: (dados: {
      renegotiation_installment_id: string
      date: string
      installment_paid_value_with_interest_cm: number
      late_payment_value: number
    }) =>
      painelPagamento.editando
        ? renegotiationsApi.payments.update(renegotiationId, painelPagamento.editando.id, {
            date: dados.date,
            installment_paid_value_with_interest_cm: dados.installment_paid_value_with_interest_cm,
            late_payment_value: dados.late_payment_value,
          })
        : renegotiationsApi.payments.create(renegotiationId, dados),
    onSuccess: () => {
      notify.success(painelPagamento.editando ? 'Pagamento atualizado.' : 'Pagamento registrado.')
      // **O painel FECHA após salvar** (FE-226), com lista e cartões atualizados.
      setPainelPagamento({ aberto: false, installmentId: null, editando: null })
      recarregar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível salvar o pagamento.')),
  })

  const removerPagamento = useMutation({
    mutationFn: (pagamento: RenegotiationPayment) =>
      renegotiationsApi.payments.remove(renegotiationId, pagamento.id),
    onSuccess: () => {
      notify.success('Pagamento removido. A previsão foi reaberta.')
      setConfirmarPagamento(null)
      recarregar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível remover o pagamento.')),
  })

  // --- Seleção ------------------------------------------------------------
  function alternarSelecao(id: string) {
    setSelecionadas((atual) => {
      const proximo = new Set(atual)
      if (proximo.has(id)) proximo.delete(id)
      else proximo.add(id)
      return proximo
    })
  }

  function selecionarTodas() {
    // **Só as sem pagamento** (FE-217) — são as únicas que o servidor remove.
    setSelecionadas(new Set(semPagamento.map((p) => p.id)))
  }

  function sairDaSelecao() {
    setModoSelecao(false)
    setSelecionadas(new Set())
  }

  const nenhumaSelecionada = selecionadas.size === 0

  // --- Render -------------------------------------------------------------
  if (consulta.isLoading) return <LoadingState label="Carregando as previsões…" />

  if (consulta.error) {
    return (
      <ErrorState
        title="Não foi possível carregar as previsões"
        description={mensagemDoServidor(consulta.error, 'Tente novamente.')}
        onRetry={() => consulta.refetch()}
      />
    )
  }

  return (
    <div className="flex flex-col gap-4">
      {/* Barra de ações — some inteira para quem é somente leitura (FE-213). */}
      {podeEscrever && parcelas.length > 0 && (
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex flex-wrap items-center gap-2">
            {modoSelecao ? (
              <>
                <Button variant="secondary" size="sm" onClick={selecionarTodas}>
                  <CheckSquare className="mr-2 h-4 w-4" aria-hidden />
                  Selecionar todos
                </Button>
                <Button variant="ghost" size="sm" onClick={sairDaSelecao}>
                  <X className="mr-2 h-4 w-4" aria-hidden />
                  Sair da seleção
                </Button>
                <span className="text-sm text-muted-foreground">
                  {selecionadas.size} de {semPagamento.length} selecionável(is)
                </span>
              </>
            ) : (
              <Button variant="secondary" size="sm" onClick={() => setModoSelecao(true)}>
                <Square className="mr-2 h-4 w-4" aria-hidden />
                Selecionar para remover
              </Button>
            )}
          </div>

          <div className="flex items-center gap-2">
            {modoSelecao && !mobile && (
              <Button
                variant="destructive"
                size="sm"
                onClick={() => {
                  if (nenhumaSelecionada) {
                    // Nada selecionado → AVISO, não uma caixa vazia (FE-218).
                    notify.error('Selecione ao menos uma previsão para remover.')
                    return
                  }
                  setConfirmarLote(true)
                }}
              >
                REMOVER {selecionadas.size} PREVISÃO(ÕES)
              </Button>
            )}
            {!modoSelecao && (
              <Button size="sm" onClick={() => setPainelParcela({ aberto: true, editando: null })}>
                <Plus className="mr-2 h-4 w-4" aria-hidden />
                Nova previsão
              </Button>
            )}
          </div>
        </div>
      )}

      {parcelas.length === 0 ? (
        <EmptyState
          icon={<CalendarRange className="h-6 w-6" aria-hidden />}
          title="Nenhuma previsão cadastrada"
          description="A previsão é a parcela do acordo: vencimento, principal, juros e correção. Lance as previsões para que os totais da renegociação passem a fechar."
          action={
            podeEscrever ? (
              <Button size="sm" onClick={() => setPainelParcela({ aberto: true, editando: null })}>
                <Plus className="mr-2 h-4 w-4" aria-hidden />
                Nova previsão
              </Button>
            ) : undefined
          }
        />
      ) : (
        <ul className="flex flex-col gap-2">
          {parcelas.map((parcela) => (
            <InstallmentRow
              key={parcela.id}
              parcela={parcela}
              compacto={mobile}
              expandida={expandidas.has(parcela.id)}
              onToggleExpandir={() =>
                setExpandidas((atual) => {
                  const proximo = new Set(atual)
                  if (proximo.has(parcela.id)) proximo.delete(parcela.id)
                  else proximo.add(parcela.id)
                  return proximo
                })
              }
              modoSelecao={modoSelecao}
              selecionada={selecionadas.has(parcela.id)}
              onToggleSelecao={() => alternarSelecao(parcela.id)}
              podeEscrever={podeEscrever}
              onGerarPagamento={() =>
                setPainelPagamento({ aberto: true, installmentId: parcela.id, editando: null })
              }
              onEditar={() => setPainelParcela({ aberto: true, editando: parcela })}
              onRemover={() => setConfirmarParcela(parcela)}
              onEditarPagamento={(pagamento) =>
                setPainelPagamento({ aberto: true, installmentId: parcela.id, editando: pagamento })
              }
              onRemoverPagamento={setConfirmarPagamento}
              onAcoesMobile={() => setAcoesMobile(parcela)}
            />
          ))}
        </ul>
      )}

      {/* Barra contextual do telefone: some quando a seleção acaba. */}
      {mobile && modoSelecao && selecionadas.size > 0 && (
        <MobileActionBar label={`${selecionadas.size} selecionada(s)`}>
          <Button variant="destructive" className="w-full" onClick={() => setConfirmarLote(true)}>
            REMOVER {selecionadas.size} PREVISÃO(ÕES)
          </Button>
        </MobileActionBar>
      )}

      {/* --- Painéis --- */}
      <InstallmentDrawer
        open={painelParcela.aberto}
        onClose={() => setPainelParcela({ aberto: false, editando: null })}
        renegotiationId={renegotiationId}
        editando={painelParcela.editando}
        delayTypes={delayTypes}
        salvando={criarParcela.isPending || editarParcela.isPending}
        onSubmit={(rascunho) => {
          if (painelParcela.editando) {
            editarParcela.mutate({ id: painelParcela.editando.id, rascunho })
          } else {
            criarParcela.mutate(rascunho)
          }
        }}
      />

      <PaymentDrawer
        open={painelPagamento.aberto}
        onClose={() => setPainelPagamento({ aberto: false, installmentId: null, editando: null })}
        installments={parcelas}
        installmentId={painelPagamento.installmentId}
        editando={painelPagamento.editando}
        salvando={salvarPagamento.isPending}
        onSubmit={(dados) => salvarPagamento.mutate(dados)}
      />

      {/* --- Confirmações. NENHUMA delas expira (FE-218). --- */}
      <ConfirmDialog
        open={confirmarLote}
        onOpenChange={setConfirmarLote}
        title={`Remover ${selecionadas.size} previsão(ões)?`}
        description={
          <>
            <p>
              A remoção é definitiva e as previsões restantes são renumeradas. Os totais da renegociação são
              recalculados.
            </p>
            <p>
              <strong>Ou todas saem, ou nenhuma sai.</strong> Se alguma delas não puder ser removida, nada é
              apagado e o motivo aparece.
            </p>
          </>
        }
        confirmLabel={`Remover ${selecionadas.size} previsão(ões)`}
        loading={removerLote.isPending}
        canConfirm={!nenhumaSelecionada}
        blockedReason={nenhumaSelecionada ? 'Selecione ao menos uma previsão.' : undefined}
        onConfirm={() => removerLote.mutate(Array.from(selecionadas))}
      />

      <ConfirmDialog
        open={!!confirmarParcela}
        onOpenChange={(aberto) => !aberto && setConfirmarParcela(null)}
        title="Remover esta previsão?"
        description={
          confirmarParcela ? (
            <p>
              Previsão #{confirmarParcela.number ?? '—'}, vencimento{' '}
              <span className="font-numeric tabular-nums">{formatDate(confirmarParcela.due_date)}</span>,
              principal{' '}
              <span className="font-numeric tabular-nums">{formatarReais(confirmarParcela.main_value)}</span>.
              As demais são renumeradas.
            </p>
          ) : null
        }
        confirmLabel="Remover previsão"
        loading={removerParcela.isPending}
        onConfirm={() => confirmarParcela && removerParcela.mutate(confirmarParcela)}
      />

      <ConfirmDialog
        open={!!confirmarPagamento}
        onOpenChange={(aberto) => !aberto && setConfirmarPagamento(null)}
        // O título diz o que É — no legado dizia "Excluir previsão" ao excluir
        // pagamento, porque o template era o mesmo.
        title="Excluir este pagamento?"
        description={
          confirmarPagamento ? (
            <p>
              Pagamento de{' '}
              <span className="font-numeric tabular-nums">
                {formatarReais(confirmarPagamento.total_paid_value)}
              </span>{' '}
              em <span className="font-numeric tabular-nums">{formatDate(confirmarPagamento.date)}</span>.
              A previsão volta a ficar em aberto.
            </p>
          ) : null
        }
        confirmLabel="Excluir pagamento"
        loading={removerPagamento.isPending}
        onConfirm={() => confirmarPagamento && removerPagamento.mutate(confirmarPagamento)}
      />

      <MobileActionsSheet
        open={!!acoesMobile}
        onOpenChange={(aberto) => !aberto && setAcoesMobile(null)}
        title={acoesMobile ? `Previsão #${acoesMobile.number ?? '—'}` : ''}
        subtitle={acoesMobile ? formatDate(acoesMobile.due_date) : undefined}
        actions={
          acoesMobile
            ? [
                {
                  key: 'pagar',
                  label: 'Gerar pagamento',
                  onSelect: () => {
                    setPainelPagamento({ aberto: true, installmentId: acoesMobile.id, editando: null })
                    setAcoesMobile(null)
                  },
                  disabledReason: acoesMobile.is_paid ? 'Previsão já quitada.' : undefined,
                },
                {
                  key: 'editar',
                  label: 'Editar previsão',
                  onSelect: () => {
                    setPainelParcela({ aberto: true, editando: acoesMobile })
                    setAcoesMobile(null)
                  },
                },
                {
                  key: 'remover',
                  label: 'Remover previsão',
                  destructive: true,
                  onSelect: () => {
                    setConfirmarParcela(acoesMobile)
                    setAcoesMobile(null)
                  },
                  disabledReason:
                    acoesMobile.has_payments || acoesMobile.payments.length > 0
                      ? 'Remova os pagamentos antes de excluir a previsão.'
                      : undefined,
                },
              ]
            : []
        }
      />
    </div>
  )
}
