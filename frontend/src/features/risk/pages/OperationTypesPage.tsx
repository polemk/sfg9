import { AlertTriangle, Lock } from 'lucide-react'
import { CatalogScreen } from '@/app/pages/catalogs/CatalogScreen'
import { CampoAtivo, Campo, CampoTexto } from '@/app/pages/catalogs/CatalogFields'
import { Badge } from '@/components/ui/Badge'
import { Switch } from '@/components/ui/switch'
import { Tooltip } from '@/components/ui/Tooltip'
import { useEffect } from 'react'
import { riskOperationTypesApi, type RiskOperationType } from '../api/risk'

/**
 * **Tipos de Limite** (FE-277). Catálogo GLOBAL.
 *
 * As quatro modalidades do Safegold — Fomento, Comissária, Intercompany, Auto
 * Liquidável — deixaram de ser colunas de `risk_controls` em 2022 e são **linhas
 * desta tela**. É por isso que ela existe: sem um tipo cadastrado não há limite,
 * e sem limite não há operação de risco nem recebível.
 *
 * ### O campo que a tela protege
 *
 * **"Operações estáticas" só é editável na criação.** A flag decide se o tipo
 * abre o par pré-faturamento/antecipação e, portanto, em qual coluna do painel
 * de exposição cada operação soma. Mudá-la depois deixaria o tipo com o número
 * errado de subtipos e trocaria, em silêncio, o bucket de **toda operação já
 * gravada**.
 *
 * No legado ela está no `permit` e o formulário de edição a oferece — o
 * bloqueio aqui tem par no servidor (`Risk::OperationTypeService`), que
 * simplesmente não a aceita no update. A tela **diz por quê** em vez de só
 * desabilitar.
 */
export function OperationTypesPage() {
  useEffect(() => {
    document.title = 'Safegold - Tipos de Limite'
  }, [])

  return (
    <CatalogScreen<RiskOperationType>
      queryKey="risk-operation-types"
      api={riskOperationTypesApi}
      texts={{
        title: 'Tipos de limite',
        subtitle:
          'As modalidades de crédito que o limite de risco pode assumir. Cada tipo gera os próprios subtipos.',
        singular: 'tipo de limite',
        createLabel: 'Novo tipo',
        emptyTitle: 'Nenhum tipo de limite cadastrado',
        emptyDescription:
          'Sem pelo menos um tipo não é possível cadastrar limite de risco. Os quatro tipos do Safegold vêm do seed de referência.',
        searchPlaceholder: 'Buscar tipo por nome ou chave…',
      }}
      columns={[
        {
          key: 'title',
          header: 'Tipo',
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
          key: 'key',
          header: 'Chave de integração',
          sortable: true,
          accessor: (t) => t.integration_key,
          cell: (t) => <code className="font-numeric text-xs text-muted-foreground">{t.integration_key}</code>,
        },
        {
          key: 'pre',
          header: 'Operações estáticas',
          accessor: (t) => (t.has_pre_faturamento ? 1 : 0),
          cell: (t) =>
            t.has_pre_faturamento ? (
              <Badge variant="secondary">Pré-faturamento</Badge>
            ) : (
              <span className="text-muted-foreground">—</span>
            ),
        },
        {
          key: 'subtypes',
          header: 'Subtipos',
          variant: 'number',
          accessor: (t) => t.subtypes?.length ?? 0,
          cell: (t) => <span className="font-numeric tabular-nums">{t.subtypes?.length ?? 0}</span>,
        },
      ]}
      mobileFields={(t) => [
        { label: 'Chave', value: <code className="font-numeric text-xs">{t.integration_key}</code> },
        {
          label: 'Estáticas',
          value: t.has_pre_faturamento ? 'Pré-faturamento' : '—',
        },
        {
          label: 'Subtipos',
          value: <span className="font-numeric tabular-nums">{t.subtypes?.length ?? 0}</span>,
        },
        { label: 'Estado', value: t.is_active ? 'Ativo' : 'Desativado' },
      ]}
      usageCount={(t) => (bloqueioDeExclusao(t).bloqueado ? Math.max(1, t.dependents_count) : 0)}
      usageLabel={(t) => {
        const bloqueio = bloqueioDeExclusao(t)
        if (bloqueio.motivo) return bloqueio.motivo
        return t.dependents_count === 1
          ? '1 limite ou operação usa este tipo — não é possível excluir'
          : `${t.dependents_count} limites ou operações usam este tipo — não é possível excluir`
      }}
      emptyForm={() => ({ title: '', is_active: true, has_pre_faturamento: false })}
      toForm={(t) => ({
        title: t.title,
        integration_key: t.integration_key,
        is_active: t.is_active,
        allow_manual_operations: t.allow_manual_operations,
        allow_receivable_entries: t.allow_receivable_entries,
        has_pre_faturamento: t.has_pre_faturamento,
      })}
      form={({ values, setValue, editing }) => (
        <>
          <CampoTexto
            id="title"
            label="Nome do tipo"
            value={values.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Fomento"
            hint={
              editing
                ? 'Renomear NÃO muda a chave de integração — ela é congelada na criação.'
                : 'A chave de integração é derivada deste nome e depois fica congelada.'
            }
            autoFocus
          />

          <Campo
            id="has_pre_faturamento"
            label="Operações estáticas (pré-faturamento)"
            hint={
              editing ? (
                <span className="flex items-start gap-1.5 text-warning">
                  <AlertTriangle aria-hidden="true" className="mt-0.5 h-3.5 w-3.5 shrink-0" />
                  <span className="text-muted-foreground">
                    Não pode mudar depois de criado: trocaria a coluna do painel em que{' '}
                    <strong>toda operação já gravada</strong> deste tipo é somada. Crie outro tipo se precisar do
                    outro comportamento.
                  </span>
                </span>
              ) : (
                'Liga o par pré-faturamento / antecipação. Só pode ser escolhido agora — depois de criado, é definitivo.'
              )
            }
          >
            <div className="flex items-center gap-3">
              <Switch
                id="has_pre_faturamento"
                checked={values.has_pre_faturamento === true}
                disabled={Boolean(editing)}
                onCheckedChange={(v) => setValue('has_pre_faturamento', v)}
              />
              <span className="text-sm text-muted-foreground">
                {values.has_pre_faturamento ? 'Gera dois subtipos (pré e antecipação)' : 'Gera um subtipo'}
              </span>
            </div>
          </Campo>

          <Campo
            id="allow_manual_operations"
            label="Permite lançamento manual"
            hint="Se desligado, operações deste tipo só nascem a partir de recebível."
          >
            <Switch
              id="allow_manual_operations"
              checked={values.allow_manual_operations !== false}
              onCheckedChange={(v) => setValue('allow_manual_operations', v)}
            />
          </Campo>

          <Campo
            id="allow_receivable_entries"
            label="Permite criação pelo recebível"
            hint="Se desligado, o borderô não oferece este tipo."
          >
            <Switch
              id="allow_receivable_entries"
              checked={values.allow_receivable_entries !== false}
              onCheckedChange={(v) => setValue('allow_receivable_entries', v)}
            />
          </Campo>

          <CampoAtivo
            value={values.is_active}
            onChange={(v) => setValue('is_active', v)}
            descricao="Tipo desativado some do painel de exposição e dos formulários. Os subtipos acompanham."
          />
        </>
      )}
    />
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
