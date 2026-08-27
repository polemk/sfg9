import { CatalogScreen } from './CatalogScreen'
import { CampoAtivo, CampoTexto } from './CatalogFields'
import { segmentsApi, type Segment } from '@/lib/api/catalogs'

/**
 * **Segmentos** (FE-077). Catálogo global.
 *
 * O que muda em relação ao legado, e o usuário vai notar:
 *
 * - **Criar segmento FUNCIONA.** No legado a criação falhava **100% das vezes**
 *   (`user_id` fora do `permit` enquanto o model o exigia — D-21). A feature
 *   estava quebrada em produção desde 2021.
 * - **O bloqueio de exclusão é COMUNICADO.** Segmento em uso por projeto não
 *   some por acidente: o botão de remover dá lugar à explicação, e forçar pela
 *   API responde 422 com a frase que nomeia o vínculo.
 * - **A paginação funciona** — a lista não traz mais tudo de uma vez (D-20).
 */
export function SegmentsPage() {
  return (
    <CatalogScreen<Segment>
      queryKey="segments"
      api={segmentsApi}
      texts={{
        title: 'Segmentos',
        subtitle: 'Ramo de atuação do cliente. Catálogo compartilhado por todos os projetos.',
        singular: 'segmento',
        createLabel: 'Novo segmento',
        emptyTitle: 'Nenhum segmento cadastrado',
        emptyDescription: 'Os segmentos alimentam o cadastro de projeto. Cadastre o primeiro para começar.',
        searchPlaceholder: 'Buscar segmento por nome ou chave…',
      }}
      columns={[
        { key: 'title', header: 'Segmento', sortable: true, accessor: (s) => s.title },
        {
          key: 'key',
          header: 'Chave de integração',
          sortable: true,
          accessor: (s) => s.integration_key,
          cell: (s) => <code className="font-numeric text-xs text-muted-foreground">{s.integration_key}</code>,
        },
        {
          key: 'projects_count',
          header: 'Projetos',
          variant: 'number',
          accessor: (s) => s.projects_count,
        },
      ]}
      mobileFields={(s) => [
        { label: 'Chave', value: <code className="font-numeric text-xs">{s.integration_key}</code> },
        { label: 'Projetos', value: <span className="font-numeric tabular-nums">{s.projects_count}</span> },
      ]}
      usageCount={(s) => s.projects_count}
      usageLabel={(s) =>
        s.projects_count === 1
          ? '1 projeto usa este segmento — não é possível excluir'
          : `${s.projects_count} projetos usam este segmento — não é possível excluir`
      }
      emptyForm={() => ({ title: '', is_active: true })}
      toForm={(s) => ({ title: s.title, integration_key: s.integration_key, is_active: s.is_active })}
      form={({ values, setValue, editing }) => (
        <>
          <CampoTexto
            id="title"
            label="Nome do segmento"
            value={values.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Indústria de transformação"
            autoFocus
          />

          {editing && (
            <CampoTexto
              id="integration_key"
              label="Chave de integração"
              value={values.integration_key}
              onChange={(v) => setValue('integration_key', v)}
              hint="Derivada do nome na criação e mantida depois. Renomear o segmento não a altera — ela pode estar em uso por um sistema externo."
            />
          )}

          <CampoAtivo
            value={values.is_active}
            onChange={(v) => setValue('is_active', v)}
            descricao="Segmento inativo continua nos projetos que já o usam, mas não aparece para novas escolhas."
          />
        </>
      )}
    />
  )
}
