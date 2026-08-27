import { useQuery } from '@tanstack/react-query'
import { ShieldCheck, AlertTriangle } from 'lucide-react'
import { CatalogScreen } from '@/app/pages/catalogs/CatalogScreen'
import { Campo, CampoTexto } from '@/app/pages/catalogs/CatalogFields'
import { ALL_ROLES } from '@/app/consoleNavigation'
import { Select } from '@/components/ui/Select'
import { MoneyInput } from '@/components/ui/NumericInput'
import { Textarea } from '@/components/ui/textarea'
import { Tooltip } from '@/components/ui/Tooltip'
import { guaranteeTypesApi } from '@/lib/api/catalogs'
import {
  formatarReais,
  projectGuaranteesApi,
  type ProjectGuarantee,
} from '@/lib/api/projects'

/**
 * **Garantias do Projeto** (FE-113, FE-114, FE-115).
 *
 * Quatro defeitos do legado morrem aqui:
 *
 * - **D-29** — passar `project_guarantee_id` na URL lia a garantia de QUALQUER
 *   projeto: a linha 22 do controller reatribuía a relação escopada. O escopo
 *   agora é do servidor e o filtro entra dentro dele.
 * - **D-32** — ordenar por "Título" produzia erro de SQL (a chave apontava para
 *   `risk_operations.title`, tabela fora do join). Agora as quatro colunas
 *   ordenam.
 * - **FE-113** — cada clique de ordenação executava a consulta **duas** vezes.
 *   Aqui a lista é uma query só, com `sortMode="server"`.
 * - **BE-119 / FE-115** — o formulário oferece **só portadores conectados ao
 *   projeto**, com o mesmo critério que o servidor usa para aceitar. O legado
 *   usava um critério no botão e outro no formulário.
 */
export function ProjectGuaranteesPage() {
  return (
    <CatalogScreen<ProjectGuarantee>
      queryKey="project-guarantees"
      api={projectGuaranteesApi}
      writeRoles={ALL_ROLES}
      defaultSort={{ key: 'created_at', direction: 'desc' }}
      texts={{
        title: 'Garantias do projeto',
        subtitle: 'O que cada portador garante neste projeto, por tipo e por valor.',
        singular: 'garantia',
        createLabel: 'Nova garantia',
        emptyTitle: 'Nenhuma garantia cadastrada',
        emptyDescription:
          'A garantia liga um portador conectado ao projeto a um tipo e a um valor. Conecte um portador antes de cadastrar a primeira.',
        searchPlaceholder: 'Buscar pelo título da garantia ou do portador…',
        scopeResource: 'as garantias',
      }}
      columns={[
        {
          key: 'title',
          header: 'Título',
          sortable: true,
          accessor: (g) => g.title,
          cell: (g) => (
            <span className="flex items-center gap-2">
              <ShieldCheck aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground" />
              <span className="truncate">{g.title}</span>
            </span>
          ),
        },
        {
          key: 'carrier',
          header: 'Portador',
          sortable: true,
          accessor: (g) => g.carrier_title ?? '',
          cell: (g) => (
            <span className="block truncate">
              {g.carrier_title ?? '—'}
              {g.carrier_group_title && (
                <span className="block text-xs text-muted-foreground">{g.carrier_group_title}</span>
              )}
            </span>
          ),
        },
        {
          key: 'guarantee_type',
          header: 'Tipo',
          sortable: true,
          accessor: (g) => g.guarantee_type_title ?? '',
          cell: (g) => (
            <span className="flex items-center gap-1.5">
              <span className="truncate">{g.guarantee_type_title ?? '—'}</span>
              {/* DEC-86 — o tipo foi semeado como suposição; a lista definitiva
                  é do cliente. A tela AVISA em vez de fingir que é cadastro
                  aprovado. */}
              {g.guarantee_type_is_provisional && (
                <Tooltip content="Tipo provisório: a lista definitiva ainda vem do cliente (DEC-86).">
                  <AlertTriangle aria-hidden="true" className="h-3.5 w-3.5 shrink-0 text-warning" />
                </Tooltip>
              )}
            </span>
          ),
        },
        {
          key: 'value',
          header: 'Valor',
          sortable: true,
          variant: 'number',
          accessor: (g) => Number(g.value),
          cell: (g) => <span className="font-numeric tabular-nums">{formatarReais(g.value)}</span>,
        },
      ]}
      mobileFields={(g) => [
        { label: 'Portador', value: g.carrier_title ?? '—' },
        { label: 'Tipo', value: g.guarantee_type_title ?? '—' },
        {
          label: 'Valor',
          value: <span className="font-numeric tabular-nums">{formatarReais(g.value)}</span>,
        },
      ]}
      // Garantia não tem dependente que bloqueie: ela é a ponta da cadeia.
      usageCount={() => 0}
      usageLabel={() => ''}
      emptyForm={() => ({ title: '', value: null, observation: '', carrier_id: null, guarantee_type_id: null })}
      toForm={(g) => ({
        title: g.title,
        value: Number(g.value),
        observation: g.observation ?? '',
        carrier_id: g.carrier_id,
        guarantee_type_id: g.guarantee_type_id,
      })}
      form={({ values, setValue }) => <FormularioGarantia values={values} setValue={setValue} />}
    />
  )
}

function FormularioGarantia({
  values,
  setValue,
}: {
  values: Record<string, any>
  setValue: (campo: string, valor: unknown) => void
}) {
  // **Um único critério** de "o projeto tem portador": a conexão. É a mesma
  // consulta que o servidor usa para aceitar o `carrier_id` (BE-119).
  const portadores = useQuery({
    queryKey: ['guarantee-available-carriers'],
    queryFn: () => projectGuaranteesApi.availableCarriers(),
  })

  const tipos = useQuery({
    queryKey: ['guarantee-types', 'ativos'],
    queryFn: () => guaranteeTypesApi.list({ active: true, perPage: 100 }),
  })

  const semPortador = !portadores.isLoading && (portadores.data?.length ?? 0) === 0

  return (
    <>
      <CampoTexto
        id="title"
        label="Título da garantia"
        value={values.title}
        onChange={(v) => setValue('title', v)}
        placeholder="Ex.: Aval dos sócios"
        autoFocus
      />

      <Campo
        id="carrier_id"
        label="Portador"
        hint={
          semPortador
            ? 'Este projeto ainda não tem portador conectado. Conecte um em "Conexões" antes de cadastrar a garantia.'
            : 'Só portadores conectados a este projeto — é o mesmo critério que o servidor aplica.'
        }
      >
        <Select
          id="carrier_id"
          options={(portadores.data ?? []).map((c) => ({
            value: c.id,
            label: c.title,
            description: c.group_title ?? undefined,
          }))}
          value={values.carrier_id ?? null}
          onChange={(v) => setValue('carrier_id', v)}
          disabled={semPortador}
          placeholder={semPortador ? 'Nenhum portador conectado' : 'Selecione o portador…'}
        />
      </Campo>

      <Campo id="guarantee_type_id" label="Tipo de garantia">
        <Select
          id="guarantee_type_id"
          options={(tipos.data?.items ?? []).map((t) => ({
            value: t.id,
            label: t.title,
            description: t.is_provisional ? 'Tipo provisório (DEC-86)' : undefined,
          }))}
          value={values.guarantee_type_id ?? null}
          onChange={(v) => setValue('guarantee_type_id', v)}
          placeholder="Selecione o tipo…"
        />
      </Campo>

      <Campo id="value" label="Valor garantido">
        {/* `MoneyInput` da S0: exibe formatado, envia NÚMERO. */}
        <MoneyInput
          id="value"
          value={(values.value as number | null) ?? null}
          onChange={(v) => setValue('value', v)}
        />
      </Campo>

      {/* O texto NÃO é mais truncado: a coluna virou `text` (no legado era
          `string(255)` com uma caixa de texto na tela, e o excedente era
          cortado em silêncio). O usuário não precisa saber disso — o que ele
          precisa saber é que pode escrever à vontade. */}
      <Campo id="observation" label="Observação" hint="Texto livre — escreva o quanto precisar.">
        <Textarea
          id="observation"
          rows={4}
          value={(values.observation as string) ?? ''}
          onChange={(e) => setValue('observation', e.target.value)}
        />
      </Campo>
    </>
  )
}
