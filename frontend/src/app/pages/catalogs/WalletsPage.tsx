import { CatalogScreen } from './CatalogScreen'
import { CampoAtivo, CampoTexto } from './CatalogFields'
import { walletsApi, type Wallet } from '@/lib/api/receivables'

/**
 * **Carteiras** (FE-187). Catálogo global do borderô.
 *
 * Sem uma carteira cadastrada o formulário de borderô sobe com o select vazio e
 * **nenhum lançamento é possível** — `wallet_id` é obrigatório. No legado o
 * seed existia e **nunca rodava**: as flags `should_seed_*` vinham `false`
 * (`../sfg/db/seeds.rb`). Aqui as 12 carteiras de produção são dado de
 * REFERÊNCIA e nascem no primeiro boot.
 *
 * **`is_active` não filtra nada** (Q-B12), e isso é deliberado: no legado a
 * coluna existe, tem tela e nenhuma consulta a lê. Fazê-la filtrar sumiria com
 * a carteira do select de quem já lança sobre ela.
 */
export function WalletsPage() {
  return (
    <CatalogScreen<Wallet>
      queryKey="wallets"
      api={walletsApi}
      texts={{
        title: 'Carteiras',
        subtitle: 'A carteira do borderô (Antecipação, Desconto, Fomento…). Catálogo compartilhado por todos os projetos.',
        singular: 'carteira',
        createLabel: 'Nova carteira',
        emptyTitle: 'Nenhuma carteira cadastrada',
        emptyDescription: 'Sem carteira não há borderô: o campo é obrigatório no lançamento. Cadastre a primeira.',
        searchPlaceholder: 'Buscar carteira por nome ou chave…',
      }}
      columns={[
        { key: 'title', header: 'Carteira', sortable: true, accessor: (w) => w.title },
        {
          key: 'key',
          header: 'Chave de integração',
          sortable: true,
          accessor: (w) => w.integration_key,
          cell: (w) => <code className="font-numeric text-xs text-muted-foreground">{w.integration_key}</code>,
        },
        {
          key: 'receivable_entries_count',
          header: 'Borderôs',
          variant: 'number',
          accessor: (w) => w.receivable_entries_count,
        },
      ]}
      mobileFields={(w) => [
        { label: 'Chave', value: <code className="font-numeric text-xs">{w.integration_key}</code> },
        { label: 'Borderôs', value: <span className="font-numeric tabular-nums">{w.receivable_entries_count}</span> },
      ]}
      usageCount={(w) => w.receivable_entries_count}
      usageLabel={(w) =>
        w.receivable_entries_count === 1
          ? '1 borderô usa esta carteira — não é possível excluir'
          : `${w.receivable_entries_count} borderôs usam esta carteira — não é possível excluir`
      }
      emptyForm={() => ({ title: '', is_active: true })}
      toForm={(w) => ({ title: w.title, integration_key: w.integration_key, is_active: w.is_active })}
      form={({ values, setValue, editing }) => (
        <>
          <CampoTexto
            id="title"
            label="Nome da carteira"
            value={values.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Antecipação"
            autoFocus
          />

          {editing && (
            <CampoTexto
              id="integration_key"
              label="Chave de integração"
              value={values.integration_key}
              onChange={(v) => setValue('integration_key', v)}
              hint="Derivada do nome na criação e mantida depois. Renomear a carteira não a altera — ela pode estar em uso por um sistema externo."
            />
          )}

          <CampoAtivo
            value={values.is_active}
            onChange={(v) => setValue('is_active', v)}
            descricao="Marcador informativo. A carteira continua aparecendo no formulário de borderô mesmo desativada — é o comportamento do legado, preservado para não sumir com a opção de quem já lança sobre ela."
          />
        </>
      )}
    />
  )
}
