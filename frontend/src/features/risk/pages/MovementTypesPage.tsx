import { ArrowDownLeft, ArrowUpRight, Lock } from 'lucide-react'
import { CatalogScreen } from '@/app/pages/catalogs/CatalogScreen'
import { CampoAtivo, Campo, CampoTexto } from '@/app/pages/catalogs/CatalogFields'
import { Badge } from '@/components/ui/Badge'
import { Select } from '@/components/ui/Select'
import { Switch } from '@/components/ui/switch'
import { Tooltip } from '@/components/ui/Tooltip'
import { useEffect } from 'react'
import { riskMovementTypesApi, type RiskMovementType } from '../api/risk'

/**
 * **Movimentações de Risco** (FE-278). Catálogo GLOBAL.
 *
 * O `credit_type` é o **sinal** com que o movimento entra no saldo da operação:
 * débito soma `+1`, crédito soma `−1`. Não é rótulo — é aritmética, e é por isso
 * que a coluna aparece com ícone e cor de estado em vez de texto solto.
 *
 * ### Três coisas que a tela do legado não tinha
 *
 * 1. **Filtro por estado.** Lá esta tela listava `RiskMovementType.all`,
 *    incluindo os desativados, sem nenhuma marca — enquanto a tela irmã ("Tipos
 *    de limite") listava só os ativos. As duas telas do mesmo cadastro
 *    discordavam sobre o que é "a lista".
 * 2. **O mesmo gate de papel da tela irmã** (FE-279). A assimetria do legado
 *    desapareceu, e o gate agora é do **servidor**, não da view.
 * 3. **Exclusão que não mente.** Lá o ramo de erro do `destroy` respondia `:ok`
 *    e a tela dizia "removido" sem ter removido (D-24).
 */
export function MovementTypesPage() {
  useEffect(() => {
    document.title = 'Safegold - Movimentações de Risco'
  }, [])

  return (
    <CatalogScreen<RiskMovementType>
      queryKey="risk-movement-types"
      api={riskMovementTypesApi}
      texts={{
        title: 'Movimentações de risco',
        subtitle:
          'Cada movimento de uma operação aponta para um destes tipos, e o tipo de crédito é o sinal dele no saldo.',
        singular: 'tipo de movimentação',
        createLabel: 'Novo tipo',
        emptyTitle: 'Nenhum tipo de movimentação cadastrado',
        emptyDescription:
          'Sem os tipos não é possível lançar movimento em operação nenhuma. Os oito do Safegold vêm do seed de referência.',
        searchPlaceholder: 'Buscar tipo por nome ou chave…',
      }}
      columns={[
        {
          key: 'title',
          header: 'Movimentação',
          sortable: true,
          accessor: (t) => t.title,
          cell: (t) => (
            <span className="flex items-center gap-2">
              <span className="truncate">{t.title}</span>
              {!t.is_active && (
                <Badge variant="secondary" className="shrink-0">
                  Desativado
                </Badge>
              )}
              {t.is_default && (
                <Tooltip content="Tipo do seed do Safegold — não pode ser removido.">
                  <Lock aria-hidden="true" className="h-3.5 w-3.5 shrink-0 text-muted-foreground" />
                </Tooltip>
              )}
            </span>
          ),
        },
        {
          key: 'credit_type',
          header: 'Tipo de crédito',
          sortable: true,
          accessor: (t) => t.credit_type,
          cell: (t) => <SinalDoMovimento tipo={t} />,
        },
        {
          key: 'system_exclusive',
          header: 'Exclusivo do sistema',
          sortable: true,
          accessor: (t) => (t.is_system_exclusive ? 1 : 0),
          cell: (t) =>
            t.is_system_exclusive ? (
              <Tooltip content="Só o sistema lança este movimento — ele não aparece no formulário manual.">
                <Badge variant="secondary">Sim</Badge>
              </Tooltip>
            ) : (
              <span className="text-muted-foreground">Não</span>
            ),
        },
        {
          key: 'transfer',
          header: 'Transferência',
          accessor: (t) => (t.is_transfer ? 1 : 0),
          cell: (t) =>
            t.is_transfer ? <Badge variant="secondary">Sim</Badge> : <span className="text-muted-foreground">—</span>,
        },
      ]}
      mobileFields={(t) => [
        { label: 'Crédito', value: <SinalDoMovimento tipo={t} /> },
        { label: 'Chave', value: <code className="font-numeric text-xs">{t.integration_key}</code> },
        { label: 'Sistema', value: t.is_system_exclusive ? 'Exclusivo' : 'Manual' },
        { label: 'Estado', value: t.is_active ? 'Ativo' : 'Desativado' },
      ]}
      usageCount={(t) => (bloqueioDeExclusao(t).bloqueado ? Math.max(1, t.dependents_count) : 0)}
      usageLabel={(t) => {
        const bloqueio = bloqueioDeExclusao(t)
        if (bloqueio.motivo) return bloqueio.motivo
        return t.dependents_count === 1
          ? '1 movimento usa este tipo — não é possível excluir'
          : `${t.dependents_count} movimentos usam este tipo — não é possível excluir`
      }}
      emptyForm={() => ({ title: '', credit_type: 'D', is_active: true, is_system_exclusive: false, is_transfer: false })}
      toForm={(t) => ({
        title: t.title,
        integration_key: t.integration_key,
        credit_type: t.credit_type,
        is_active: t.is_active,
        is_system_exclusive: t.is_system_exclusive,
        is_transfer: t.is_transfer,
      })}
      form={({ values, setValue, editing }) => (
        <>
          <CampoTexto
            id="title"
            label="Nome da movimentação"
            value={values.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Juros de Mora"
            hint={
              editing
                ? 'Renomear NÃO muda a chave de integração — e é por ela que o sistema encontra os movimentos que ele mesmo lança.'
                : 'A chave de integração é derivada deste nome e depois fica congelada.'
            }
            autoFocus
          />

          <Campo
            id="credit_type"
            label="Tipo de crédito"
            hint="É o SINAL do movimento no saldo da operação: débito soma, crédito abate."
          >
            <Select
              id="credit_type"
              options={[
                { value: 'D', label: 'Débito', description: 'Soma ao saldo devedor (+1)' },
                { value: 'C', label: 'Crédito', description: 'Abate o saldo devedor (−1)' },
              ]}
              value={(values.credit_type as string) ?? 'D'}
              onChange={(v) => setValue('credit_type', v)}
            />
          </Campo>

          <Campo
            id="is_system_exclusive"
            label="Exclusivo do sistema"
            hint="Ligado, o tipo some do formulário manual — só o próprio sistema o lança."
          >
            <Switch
              id="is_system_exclusive"
              checked={values.is_system_exclusive === true}
              onCheckedChange={(v) => setValue('is_system_exclusive', v)}
            />
          </Campo>

          <Campo
            id="is_transfer"
            label="Movimento de transferência"
            hint="Ligado, o lançamento gera o movimento espelho na outra metade do par pré/antecipação."
          >
            <Switch
              id="is_transfer"
              checked={values.is_transfer === true}
              onCheckedChange={(v) => setValue('is_transfer', v)}
            />
          </Campo>

          <CampoAtivo
            value={values.is_active}
            onChange={(v) => setValue('is_active', v)}
            descricao="Tipo desativado deixa de aparecer no formulário de movimento. Os lançamentos antigos continuam valendo."
          />
        </>
      )}
    />
  )
}

/**
 * O sinal, com ícone e token de estado.
 *
 * Débito **não** é "ruim" e crédito **não** é "bom" — são direções. Por isso o
 * par de tokens usado é o de indicador (`success` / `negative`), o mesmo do
 * semáforo de limite, e não `destructive`, que neste produto significa "apaga".
 */
function SinalDoMovimento({ tipo }: { tipo: RiskMovementType }) {
  const debito = tipo.credit_type === 'D'
  return (
    <span className="flex items-center gap-1.5">
      {debito ? (
        <ArrowUpRight aria-hidden="true" className="h-4 w-4 shrink-0 text-negative" />
      ) : (
        <ArrowDownLeft aria-hidden="true" className="h-4 w-4 shrink-0 text-success" />
      )}
      <span>{tipo.credit_type_description}</span>
      <span className="font-numeric text-xs text-muted-foreground">({debito ? '+1' : '−1'})</span>
    </span>
  )
}

/**
 * O critério do cadeado é o **do servidor**, e o servidor recusa por DOIS
 * motivos: vínculo (`dependents_count > 0`) e linha semeada (`is_default`).
 *
 * Sem a segunda metade a tela oferecia excluir um tipo do seed que ainda não
 * tinha uso — e o 422 só aparecia depois do clique. Visto renderizando: "Valor
 * Transferido" mostrava a lixeira enquanto os irmãos mostravam o cadeado.
 */
function bloqueioDeExclusao(registro: { is_default: boolean; dependents_count: number }) {
  if (registro.is_default) return { bloqueado: true, motivo: 'Tipo do seed do Safegold — não pode ser removido.' }
  return { bloqueado: registro.dependents_count > 0, motivo: '' }
}
