import { CatalogScreen } from './CatalogScreen'
import { CampoAtivo, CampoTexto } from './CatalogFields'
import { carrierGroupsApi, type CarrierGroup } from '@/lib/api/catalogs'

/**
 * **Grupos de portadores** (FE-075, FE-076). Catálogo global.
 *
 * Duas correções visíveis:
 *
 * 1. **O toast fala do GRUPO.** No legado, excluir um grupo dizia "O portador
 *    foi excluído" — texto copiado da tela vizinha, numa ação que apagava outra
 *    coisa.
 * 2. **A contagem que esconde o botão é a MESMA que o servidor usa.** No legado
 *    `carriers_count` divergia da lista: o botão sumia e a exclusão passava
 *    assim mesmo, deixando `group_id` órfão. Agora é `counter_cache`, e grupo
 *    com portador responde **422** no servidor.
 */
export function CarrierGroupsPage() {
  return (
    <CatalogScreen<CarrierGroup>
      queryKey="carrier-groups"
      api={carrierGroupsApi}
      texts={{
        title: 'Grupos de portadores',
        subtitle: 'Agrupa contrapartes financiadoras por natureza — fundos, bancos, factorings.',
        singular: 'grupo',
        createLabel: 'Novo grupo',
        emptyTitle: 'Nenhum grupo cadastrado',
        emptyDescription: 'O grupo é opcional no portador. Cadastre os que a sua operação usa para filtrar.',
        searchPlaceholder: 'Buscar grupo por nome ou chave…',
      }}
      columns={[
        { key: 'title', header: 'Grupo', sortable: true, accessor: (g) => g.title },
        {
          key: 'key',
          header: 'Chave de integração',
          sortable: true,
          accessor: (g) => g.integration_key,
          cell: (g) => <code className="font-numeric text-xs text-muted-foreground">{g.integration_key}</code>,
        },
        {
          key: 'carriers_count',
          header: 'Portadores',
          sortable: true,
          variant: 'number',
          accessor: (g) => g.carriers_count,
        },
      ]}
      mobileFields={(g) => [
        { label: 'Chave', value: <code className="font-numeric text-xs">{g.integration_key}</code> },
        { label: 'Portadores', value: <span className="font-numeric tabular-nums">{g.carriers_count}</span> },
      ]}
      usageCount={(g) => g.carriers_count}
      usageLabel={(g) =>
        g.carriers_count === 1
          ? '1 portador pertence a este grupo — não é possível excluir'
          : `${g.carriers_count} portadores pertencem a este grupo — não é possível excluir`
      }
      emptyForm={() => ({ title: '', is_active: true })}
      toForm={(g) => ({ title: g.title, integration_key: g.integration_key, is_active: g.is_active })}
      form={({ values, setValue, editing }) => (
        <>
          <CampoTexto
            id="title"
            label="Nome do grupo"
            value={values.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Fundos multicedentes"
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
            descricao="Grupo inativo não aparece na escolha de novos portadores."
          />
        </>
      )}
    />
  )
}
