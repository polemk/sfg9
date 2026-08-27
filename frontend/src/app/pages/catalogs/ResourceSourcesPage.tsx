import { useEffect } from 'react'
import { CatalogScreen } from './CatalogScreen'
import { CampoAtivo, CampoTexto } from './CatalogFields'
import { resourceSourcesApi, type ResourceSource } from '@/lib/api/receivables'

/**
 * **Cadastro › Tipos de Recursos** — as fontes de recurso (`FE-308`).
 *
 * Catálogo **global** (contrato C1, regra 4). A **leitura** já existia: a S6 a
 * trouxe porque `receivable_entries.resource_source_id` é obrigatório — 28.131
 * de 28.131 linhas de produção têm valor — e sem o select o formulário de
 * borderô respondia 422 no Salvar. Esta tela é a superfície de **escrita**, que
 * é da S8 (`BE-308`, `BE-725`…`BE-729`).
 *
 * ## `DEC-110` — a `Q-R22` desapareceu, e isso simplifica esta tela
 *
 * A dúvida aberta era que `resource_kinds` e `resource_sources` tinham o
 * **mesmo** rótulo de menu e o mesmo título de aba; se as duas sobrevivessem,
 * os rótulos precisariam ficar distintos. O portão T-D7 foi respondido pelo
 * dump de produção: `resource_kinds` tem **0 linhas** e **0 de 28.131**
 * `receivable_entries` a referenciam. A superfície caiu e a tabela sai numa
 * tarefa explícita. **Sobra só esta tela**, e ela pode ficar com o rótulo do
 * legado sem ambiguidade nenhuma.
 *
 * ## O vazio agramatical sai
 *
 * O legado dizia *"Não existem utilização de recurso cadastrado"* — três
 * concordâncias erradas numa frase de seis palavras. E, como todo vazio do
 * legado, não distinguia "primeiro uso" de "busca sem resultado": o molde
 * resolve os dois, e o de busca **cita o termo**.
 *
 * ## `Q-R19` — `is_active` continua NÃO filtrando o borderô
 *
 * Desativar uma fonte aqui **não** a tira do select do formulário de borderô.
 * É o comportamento do legado e é replicado: as 28.131 linhas de produção
 * apontam para fontes que podem ter sido desativadas depois, e sumir com elas
 * quebraria a edição do histórico.
 */
export function ResourceSourcesPage() {
  useEffect(() => {
    document.title = 'Safegold - Tipos de Recursos'
  }, [])

  return (
    <CatalogScreen<ResourceSource>
      queryKey="resource-sources"
      api={resourceSourcesApi}
      writeRoles={['og', 'admin', 'gerente']}
      texts={{
        title: 'Tipos de Recursos',
        subtitle:
          'De onde vem o dinheiro do borderô (FIDC, próprio, cessão…). Catálogo compartilhado por todos os projetos.',
        singular: 'tipo de recurso',
        createLabel: 'Novo tipo de recurso',
        emptyTitle: 'Nenhum tipo de recurso cadastrado',
        emptyDescription:
          'A fonte de recurso é obrigatória no borderô: sem ela o lançamento não salva. Cadastre a primeira.',
        searchPlaceholder: 'Buscar tipo de recurso por título ou chave…',
      }}
      defaultSort={{ key: 'title', direction: 'asc' }}
      columns={[
        { key: 'title', header: 'Título', sortable: true, accessor: (s) => s.title },
        {
          key: 'key',
          header: 'Chave',
          sortable: true,
          accessor: (s) => s.integration_key,
          cell: (s) => (
            <code className="font-numeric text-xs text-muted-foreground">{s.integration_key || '-'}</code>
          ),
        },
        {
          key: 'receivable_entries_count',
          header: 'Borderôs',
          variant: 'number',
          accessor: (s) => s.receivable_entries_count,
        },
      ]}
      mobileFields={(s) => [
        { label: 'Chave', value: <code className="font-numeric text-xs">{s.integration_key || '-'}</code> },
        {
          label: 'Borderôs',
          value: <span className="font-numeric tabular-nums">{s.receivable_entries_count}</span>,
        },
      ]}
      // O número que esconde "Excluir" é o MESMO que o servidor usa para
      // responder 422.
      usageCount={(s) => s.receivable_entries_count}
      usageLabel={(s) =>
        s.receivable_entries_count === 1
          ? '1 borderô usa este tipo de recurso — não é possível excluir'
          : `${s.receivable_entries_count} borderôs usam este tipo de recurso — não é possível excluir`
      }
      emptyForm={() => ({ title: '', integration_key: '', is_active: true })}
      toForm={(s) => ({ title: s.title, integration_key: s.integration_key, is_active: s.is_active })}
      form={({ values, setValue }) => (
        <>
          <CampoTexto
            id="title"
            label="Escolha um título"
            value={values.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Utilização de recurso"
            autoFocus
          />

          <CampoTexto
            id="integration_key"
            label="Chave de integração"
            value={values.integration_key}
            onChange={(v) => setValue('integration_key', v)}
            placeholder="Ex.: utilizacao_de_recurso"
            hint="É por ela que uma integração externa acha a fonte."
          />

          <CampoAtivo
            value={values.is_active}
            onChange={(v) => setValue('is_active', v)}
            descricao="Marcador informativo: a fonte continua no formulário de borderô mesmo desativada (comportamento do legado, preservado — Q-R19)."
          />
        </>
      )}
    />
  )
}
