import { Building2 } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { CatalogScreen } from '@/app/pages/catalogs/CatalogScreen'
import { CampoTexto } from '@/app/pages/catalogs/CatalogFields'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { companiesApi, type Company } from '@/lib/api/projects'

/**
 * **Empresas** (FE-051, FE-054..FE-057) — a contraparte tomadora dentro do
 * projeto corrente.
 *
 * Reusa o `CatalogScreen`, o mesmo molde das cinco telas de catálogo global.
 * O que muda é o **escopo do dado**, não a forma da tela: aqui a lista vem
 * filtrada por `current_project!` no servidor, e nenhuma chamada manda
 * `project_id`. É a diferença que o `lib/api/projects.ts` documenta.
 *
 * O que o usuário vai notar em relação ao legado:
 *
 * - **A paginação funciona.** No legado `.order/.limit/.offset` eram descartados
 *   por um `where!` que mutava a relação e devolvia outra — a lista voltava
 *   inteira e a UI de paginação era decorativa (D-20).
 * - **A exclusão bloqueada é COMUNICADA.** Empresa com limite de risco,
 *   recebível ou renegociação não some por acidente: a ação de remover dá lugar
 *   à explicação, e forçar pela API responde 422. No legado o controller
 *   respondia `:ok` em qualquer caso (`errors.any? ? :ok : :ok`) e a tela dizia
 *   "removido com sucesso" sem ter removido (D-24).
 * - **Some o texto herdado** "Essa construtora não pode ser alterada", que era
 *   cópia de outra tela.
 *
 * **DC-05 — os filtros `kind` e `state` NÃO são portados**: os selects não
 * existiam no HTML do legado e o backend ignorava os dois parâmetros. Portar
 * um filtro que nunca filtrou seria portar a aparência da função.
 *
 * **DC-06 — a aba "Controles de Risco" não é portada**: era um parcial vazio,
 * não listada e sem action. A informação aparece na coluna "Limites" desta
 * lista, alimentada pelo mesmo número que o servidor usa para bloquear.
 */
export function CompaniesPage() {
  const navigate = useNavigate()

  return (
    <CatalogScreen<Company>
      queryKey="companies"
      api={companiesApi}
      onRowClick={(c) => navigate(`/companies/${c.id}`)}
      // A matriz dá CRUD de empresa aos QUATRO papéis (grupo "Projeto"); o gate
      // que importa aqui é o de projeto (C1), não o de papel.
      writeRoles={ALL_ROLES}
      texts={{
        title: 'Empresas',
        subtitle: 'Contrapartes tomadoras deste projeto. É delas que pendem limites, recebíveis e renegociações.',
        singular: 'empresa',
        createLabel: 'Nova empresa',
        emptyTitle: 'Nenhuma empresa cadastrada',
        emptyDescription:
          'Todo projeto nasce com a "Empresa Padrão". Cadastre as demais para separar limites e recebíveis por contraparte.',
        searchPlaceholder: 'Buscar empresa por razão social…',
        scopeResource: 'as empresas',
      }}
      columns={[
        {
          key: 'title',
          header: 'Empresa',
          sortable: true,
          accessor: (c) => c.title,
          cell: (c) => (
            <span className="flex items-center gap-2">
              <Building2 aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground" />
              <span className="truncate">{c.title}</span>
            </span>
          ),
        },
        {
          key: 'carriers_count',
          header: 'Portadores',
          variant: 'number',
          accessor: (c) => c.carriers_count,
        },
        {
          key: 'risk_controls_count',
          header: 'Limites',
          variant: 'number',
          accessor: (c) => c.risk_controls_count,
        },
      ]}
      mobileFields={(c) => [
        { label: 'Portadores', value: <span className="font-numeric tabular-nums">{c.carriers_count}</span> },
        { label: 'Limites', value: <span className="font-numeric tabular-nums">{c.risk_controls_count}</span> },
      ]}
      // O número que esconde a ação de remover é o MESMO que o servidor usa
      // para responder 422. No legado o botão sumia por uma contagem e a
      // exclusão era decidida por outra.
      usageCount={(c) => c.risk_controls_count}
      usageLabel={(c) =>
        c.risk_controls_count === 1
          ? '1 limite de risco usa esta empresa — não é possível excluir'
          : `${c.risk_controls_count} limites de risco usam esta empresa — não é possível excluir`
      }
      emptyForm={() => ({ title: '' })}
      toForm={(c) => ({ title: c.title })}
      form={({ values, setValue }) => (
        <CampoTexto
          id="title"
          label="Razão social"
          value={values.title}
          onChange={(v) => setValue('title', v)}
          placeholder="Ex.: Incorporadora Alfa Ltda."
          hint="Única dentro deste projeto."
          autoFocus
        />
      )}
    />
  )
}
