import { CatalogScreen } from './CatalogScreen'
import { CampoAtivo, CampoTexto, Campo } from './CatalogFields'
import { Badge } from '@/components/ui/Badge'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/Label'
import { Textarea } from '@/components/ui/textarea'
import { guaranteeTypesApi, type GuaranteeType } from '@/lib/api/catalogs'

/**
 * **Tipos de garantia** (FE-116, FE-117). Catálogo global.
 *
 * Duas coisas que só existem nesta tela, e cada uma tem motivo escrito:
 *
 * - **O selo "provisório" (DEC-86).** A tabela existe no legado desde 2022 e
 *   **nenhum seed a popula**: o select de garantias do projeto sobe **vazio**
 *   até alguém cadastrar à mão. Não há nada a migrar — o conteúdo é novo, é
 *   suposição, e **a lista definitiva é do cliente**. O selo diz isso ao usuário
 *   em vez de deixá-lo descobrir depois; desmarcar é o gesto de "esta linha é
 *   nossa agora".
 * - **A chave de integração é congelada** (DC-22). Renomear o tipo **não** a
 *   recalcula: é chave de integração, e recalculá-la em silêncio quebraria um
 *   consumidor externo sem nenhum erro aparecer.
 */
export function GuaranteeTypesPage() {
  return (
    <CatalogScreen<GuaranteeType>
      queryKey="guarantee-types"
      api={guaranteeTypesApi}
      defaultSort={{ key: 'sort_order', direction: 'asc' }}
      texts={{
        title: 'Tipos de garantia',
        subtitle: 'Alimenta o select de garantias do projeto. Catálogo compartilhado por todos os projetos.',
        singular: 'tipo de garantia',
        createLabel: 'Novo tipo',
        emptyTitle: 'Nenhum tipo de garantia cadastrado',
        emptyDescription:
          'Sem nenhum tipo, o cadastro de garantias do projeto fica sem opções para escolher.',
        searchPlaceholder: 'Buscar tipo por nome ou chave…',
      }}
      columns={[
        {
          key: 'title',
          header: 'Tipo',
          sortable: true,
          accessor: (t) => t.title,
          cell: (t) => (
            <span className="flex flex-wrap items-center gap-2">
              {t.title}
              {t.is_provisional && (
                <Badge variant="warning" title="Semeado como suposição — a lista definitiva é do cliente">
                  provisório
                </Badge>
              )}
              {!t.is_active && <Badge variant="secondary">inativo</Badge>}
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
        { key: 'sort_order', header: 'Ordem', sortable: true, variant: 'number', accessor: (t) => t.sort_order },
        {
          key: 'guarantees_count',
          header: 'Em uso',
          variant: 'number',
          accessor: (t) => t.guarantees_count,
        },
      ]}
      mobileFields={(t) => [
        { label: 'Chave', value: <code className="font-numeric text-xs">{t.integration_key}</code> },
        { label: 'Ordem', value: <span className="font-numeric tabular-nums">{t.sort_order}</span> },
        { label: 'Em uso', value: <span className="font-numeric tabular-nums">{t.guarantees_count}</span> },
      ]}
      usageCount={(t) => t.guarantees_count}
      usageLabel={(t) =>
        t.guarantees_count === 1
          ? '1 garantia de projeto usa este tipo — não é possível excluir'
          : `${t.guarantees_count} garantias de projeto usam este tipo — não é possível excluir`
      }
      emptyForm={() => ({ title: '', sort_order: 0, is_active: true, is_provisional: false })}
      toForm={(t) => ({
        title: t.title,
        integration_key: t.integration_key,
        sort_order: t.sort_order,
        description: t.description ?? '',
        observation: t.observation ?? '',
        is_active: t.is_active,
        is_provisional: t.is_provisional,
      })}
      form={({ values, setValue, editing }) => (
        <>
          <CampoTexto
            id="title"
            label="Nome do tipo"
            value={values.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Cessão fiduciária de recebíveis"
            autoFocus
          />

          {editing && (
            <CampoTexto
              id="integration_key"
              label="Chave de integração"
              value={values.integration_key}
              onChange={(v) => setValue('integration_key', v)}
              hint="Congelada na criação. Renomear o tipo não a altera — ela pode estar em uso por um sistema externo."
            />
          )}

          <Campo id="description" label="Descrição">
            <Textarea
              id="description"
              value={(values.description as string) ?? ''}
              onChange={(e) => setValue('description', e.target.value)}
              placeholder="O que este instrumento garante, em uma frase."
              rows={3}
            />
          </Campo>

          <Campo
            id="sort_order"
            label="Ordem no select"
            hint="Menor aparece primeiro na lista de garantias do projeto."
          >
            <input
              id="sort_order"
              type="number"
              value={(values.sort_order as number) ?? 0}
              onChange={(e) => setValue('sort_order', Number(e.target.value))}
              className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 font-numeric text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
            />
          </Campo>

          {/* DEC-86 — o selo é editável de propósito: quando o cliente confirmar
              a lista, desmarcar é o gesto de "esta linha é nossa agora". */}
          <div className="flex items-start justify-between gap-4 rounded-md border border-border bg-muted/40 p-3">
            <div>
              <Label htmlFor="is_provisional">Provisório</Label>
              <p className="mt-0.5 text-xs text-muted-foreground">
                Tipo sugerido pelo sistema, ainda não confirmado pelo cliente. Desmarque quando a lista
                definitiva for validada.
              </p>
            </div>
            <Switch
              id="is_provisional"
              checked={values.is_provisional === true}
              onCheckedChange={(v) => setValue('is_provisional', v)}
            />
          </div>

          <CampoAtivo
            value={values.is_active}
            onChange={(v) => setValue('is_active', v)}
            descricao="Tipo inativo continua nas garantias que já o usam, mas não aparece para novas escolhas."
          />
        </>
      )}
    />
  )
}
