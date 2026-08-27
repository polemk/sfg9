import { CatalogScreen } from './CatalogScreen'
import { CampoAtivo, CampoTexto } from './CatalogFields'
import { subSegmentsApi, type SubSegment } from '@/lib/api/catalogs'

/**
 * **Subsegmentos** (FE-078). Catálogo global e **independente** de segmentos.
 *
 * **Todo texto desta tela fala de subsegmento.** No legado ela foi feita por
 * cópia da de segmentos e o placeholder ficou "Ex: Segmento Comercial" — o
 * usuário lia "segmento" numa tela chamada "Subsegmentos".
 *
 * **Não há hierarquia segmento → subsegmento** (DC-13). Apesar do nome, o legado
 * nunca ligou os dois: são duas listas planas, e o projeto aponta para cada uma
 * por um campo próprio. Criar a hierarquia agora exigiria inventar o mapeamento
 * dos dados existentes — fica registrado como candidato a feature futura.
 */
export function SubSegmentsPage() {
  return (
    <CatalogScreen<SubSegment>
      queryKey="sub-segments"
      api={subSegmentsApi}
      texts={{
        title: 'Subsegmentos',
        subtitle: 'Recorte mais fino da atuação do cliente. Lista independente da de segmentos (DC-13).',
        singular: 'subsegmento',
        createLabel: 'Novo subsegmento',
        emptyTitle: 'Nenhum subsegmento cadastrado',
        emptyDescription: 'O subsegmento é opcional no projeto: cadastre os que a sua operação usa de fato.',
        searchPlaceholder: 'Buscar subsegmento por nome ou chave…',
      }}
      columns={[
        { key: 'title', header: 'Subsegmento', sortable: true, accessor: (s) => s.title },
        {
          key: 'key',
          header: 'Chave de integração',
          sortable: true,
          accessor: (s) => s.integration_key,
          cell: (s) => <code className="font-numeric text-xs text-muted-foreground">{s.integration_key}</code>,
        },
        { key: 'projects_count', header: 'Projetos', variant: 'number', accessor: (s) => s.projects_count },
      ]}
      mobileFields={(s) => [
        { label: 'Chave', value: <code className="font-numeric text-xs">{s.integration_key}</code> },
        { label: 'Projetos', value: <span className="font-numeric tabular-nums">{s.projects_count}</span> },
      ]}
      usageCount={(s) => s.projects_count}
      usageLabel={(s) =>
        s.projects_count === 1
          ? '1 projeto usa este subsegmento — não é possível excluir'
          : `${s.projects_count} projetos usam este subsegmento — não é possível excluir`
      }
      emptyForm={() => ({ title: '', is_active: true })}
      toForm={(s) => ({ title: s.title, integration_key: s.integration_key, is_active: s.is_active })}
      form={({ values, setValue, editing }) => (
        <>
          <CampoTexto
            id="title"
            label="Nome do subsegmento"
            value={values.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Autopeças"
            autoFocus
          />

          {editing && (
            <CampoTexto
              id="integration_key"
              label="Chave de integração"
              value={values.integration_key}
              onChange={(v) => setValue('integration_key', v)}
              hint="Derivada do nome na criação e mantida depois. Renomear o subsegmento não a altera."
            />
          )}

          <CampoAtivo
            value={values.is_active}
            onChange={(v) => setValue('is_active', v)}
            descricao="Subsegmento inativo continua nos projetos que já o usam, mas não aparece para novas escolhas."
          />
        </>
      )}
    />
  )
}
