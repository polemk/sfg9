import { CatalogScreen } from './CatalogScreen'
import { CampoAtivo, CampoTexto } from './CatalogFields'
import { receivableKindsApi, type ReceivableKind } from '@/lib/api/receivables'

/**
 * **Tipos de recebível** (FE-188). Catálogo global do borderô.
 *
 * O que muda em relação ao legado: **a criação passa a dizer a verdade.** No
 * legado `receivable_kinds_controller#create` respondia **200** com o registro
 * não gravado — a tela dizia "cadastrado" e nada tinha sido cadastrado. Agora é
 * 422 com a mensagem do servidor.
 */
export function ReceivableKindsPage() {
  return (
    <CatalogScreen<ReceivableKind>
      queryKey="receivable-kinds"
      api={receivableKindsApi}
      texts={{
        title: 'Tipos de Recebíveis',
        subtitle: 'O que está sendo antecipado (Duplicata, Cheque, ACC…). Catálogo compartilhado por todos os projetos.',
        singular: 'tipo de recebível',
        createLabel: 'Novo tipo',
        emptyTitle: 'Nenhum tipo de recebível cadastrado',
        emptyDescription: 'Sem tipo não há borderô: o campo é obrigatório no lançamento. Cadastre o primeiro.',
        searchPlaceholder: 'Buscar tipo por nome ou chave…',
      }}
      columns={[
        { key: 'title', header: 'Tipo', sortable: true, accessor: (k) => k.title },
        {
          key: 'key',
          header: 'Chave de integração',
          sortable: true,
          accessor: (k) => k.integration_key,
          cell: (k) => <code className="font-numeric text-xs text-muted-foreground">{k.integration_key}</code>,
        },
        {
          key: 'receivable_entries_count',
          header: 'Borderôs',
          variant: 'number',
          accessor: (k) => k.receivable_entries_count,
        },
      ]}
      mobileFields={(k) => [
        { label: 'Chave', value: <code className="font-numeric text-xs">{k.integration_key}</code> },
        { label: 'Borderôs', value: <span className="font-numeric tabular-nums">{k.receivable_entries_count}</span> },
      ]}
      usageCount={(k) => k.receivable_entries_count}
      usageLabel={(k) =>
        k.receivable_entries_count === 1
          ? '1 borderô usa este tipo — não é possível excluir'
          : `${k.receivable_entries_count} borderôs usam este tipo — não é possível excluir`
      }
      emptyForm={() => ({ title: '', is_active: true })}
      toForm={(k) => ({ title: k.title, integration_key: k.integration_key, is_active: k.is_active })}
      form={({ values, setValue, editing }) => (
        <>
          <CampoTexto
            id="title"
            label="Nome do tipo"
            value={values.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Duplicata"
            autoFocus
          />

          {editing && (
            <CampoTexto
              id="integration_key"
              label="Chave de integração"
              value={values.integration_key}
              onChange={(v) => setValue('integration_key', v)}
              hint="Derivada do nome na criação e mantida depois."
            />
          )}

          <CampoAtivo
            value={values.is_active}
            onChange={(v) => setValue('is_active', v)}
            descricao="Marcador informativo: o tipo continua no formulário de borderô mesmo desativado (comportamento do legado, preservado)."
          />
        </>
      )}
    />
  )
}
