import { Badge } from '@/components/ui/Badge'
import { Label } from '@/components/ui/Label'
import { Radio, RadioGroup } from '@/components/ui/RadioGroup'
import { Select } from '@/components/ui/Select'
import { Switch } from '@/components/ui/switch'
import { CatalogScreen } from './CatalogScreen'
import { Campo, CampoAtivo, CampoTexto } from './CatalogFields'
import { movementKindsApi, type MovementKind, type TaxClassifier } from '@/lib/api/receivables'

/**
 * **Tipos de Movimentação** (FE-189). Catálogo global — e o mais sensível dos
 * três do borderô.
 *
 * É ele que decide em qual dos quatro *buckets* a tarifa cai e, por
 * consequência, **a base do IOF e os sete custos efetivos**. Um `is_desagio`
 * marcado errado aqui muda número em 28 mil borderôs.
 *
 * ## O erro cru "Múltiplos tipos" deixa de existir — e não por escondê-lo
 *
 * No legado os quatro classificadores eram **quatro caixas independentes**, e
 * marcar duas produzia a mensagem `"Múltiplos tipos Pode ter apenas um dos
 * tipos definidos: AdValorem, Deságio, IOF, Liquidação"` — o `errors.add` usava
 * uma frase inteira como se fosse nome de atributo
 * (`../sfg/app/models/movement_kind.rb:12-17`).
 *
 * Aqui os quatro viram **uma escolha só**: um grupo de rádio com "Nenhum" na
 * frente. O caminho para o erro fecha na interface, e não porque o erro foi
 * escondido — o servidor continua respondendo 422 (BE-447), e há
 * `check_constraint` no banco. **Esconder o botão nunca foi autorização**; o
 * que a tela faz aqui é não oferecer um estado inválido.
 *
 * ## Dois campos vêm SEM consumidor, e isso está escrito na tela
 *
 * `is_title` e `is_liquidation` existem, têm campo e **nenhuma regra os lê** —
 * nem no legado (D-74, Q-B13). Foram portados como estão, e o texto de ajuda
 * diz isso em vez de sugerir um efeito que não existe.
 */

const CLASSIFICADORES: { value: TaxClassifier | 'none'; label: string; hint: string }[] = [
  {
    value: 'none',
    label: 'Nenhum',
    hint: 'A tarifa entra em "Outras" — o resto da subtração no cálculo do borderô.',
  },
  {
    value: 'is_advalorem',
    label: 'AdValorem',
    hint: 'Soma em `tarifas_ad_valorem` e ENTRA na base do IOF.',
  },
  {
    value: 'is_desagio',
    label: 'Deságio',
    hint: 'Soma em `tarifas_desagio`, entra na base do IOF e alimenta as taxas nominais.',
  },
  {
    value: 'is_iof',
    label: 'IOF',
    hint: 'Soma em `tarifas_iof`. É o bucket que destrava as três taxas com guarda `< 1`.',
  },
  {
    value: 'is_liquidation',
    label: 'Liquidação',
    hint: 'Portado do legado SEM consumidor: nenhuma regra de cálculo lê este classificador.',
  },
]

function classificadorDe(values: Record<string, any>): TaxClassifier | 'none' {
  const marcado = (['is_advalorem', 'is_desagio', 'is_iof', 'is_liquidation'] as TaxClassifier[]).find(
    (flag) => values[flag] === true,
  )
  return marcado ?? 'none'
}

export function MovementKindsPage() {
  return (
    <CatalogScreen<MovementKind>
      queryKey="movement-kinds"
      api={movementKindsApi}
      texts={{
        title: 'Tipos de Movimentação',
        subtitle:
          'As tarifas que um borderô pode ter. O classificador de cada tipo decide a base do IOF e os custos efetivos.',
        singular: 'tipo de movimentação',
        createLabel: 'Novo tipo',
        emptyTitle: 'Nenhum tipo de movimentação cadastrado',
        emptyDescription:
          'Sem tipo de movimentação não há tarifa — e sem tarifa o borderô não tem deságio, não tem IOF e o custo efetivo sai zero.',
        searchPlaceholder: 'Buscar tipo por nome ou chave…',
      }}
      columns={[
        { key: 'title', header: 'Tipo', sortable: true, accessor: (m) => m.title },
        {
          key: 'classifier',
          header: 'Classificador',
          accessor: (m) => m.tax_classifier ?? '',
          cell: (m) => {
            const rotulo = CLASSIFICADORES.find((c) => c.value === (m.tax_classifier ?? 'none'))
            return m.tax_classifier ? (
              <Badge variant="secondary">{rotulo?.label}</Badge>
            ) : (
              <span className="text-muted-foreground">Outras</span>
            )
          },
        },
        {
          key: 'kind',
          header: 'Sentido',
          accessor: (m) => m.kind ?? '',
          cell: (m) => <span>{m.kind_label ?? '—'}</span>,
        },
        {
          key: 'is_operation',
          header: 'No borderô',
          accessor: (m) => (m.is_operation ? 1 : 0),
          cell: (m) =>
            m.is_operation ? <span>Sim</span> : <span className="text-muted-foreground">Não</span>,
        },
        {
          key: 'key',
          header: 'Chave',
          sortable: true,
          accessor: (m) => m.integration_key,
          cell: (m) => <code className="font-numeric text-xs text-muted-foreground">{m.integration_key}</code>,
        },
        {
          key: 'receivable_taxes_count',
          header: 'Tarifas',
          variant: 'number',
          accessor: (m) => m.receivable_taxes_count,
        },
      ]}
      mobileFields={(m) => [
        {
          label: 'Classificador',
          value: m.tax_classifier ? (
            <Badge variant="secondary">
              {CLASSIFICADORES.find((c) => c.value === m.tax_classifier)?.label}
            </Badge>
          ) : (
            <span className="text-muted-foreground">Outras</span>
          ),
        },
        { label: 'Sentido', value: m.kind_label ?? '—' },
        { label: 'Tarifas', value: <span className="font-numeric tabular-nums">{m.receivable_taxes_count}</span> },
      ]}
      usageCount={(m) => m.receivable_taxes_count}
      usageLabel={(m) =>
        m.receivable_taxes_count === 1
          ? '1 tarifa de borderô usa este tipo — não é possível excluir'
          : `${m.receivable_taxes_count} tarifas de borderô usam este tipo — não é possível excluir`
      }
      emptyForm={() => ({
        title: '',
        kind: 'debit',
        is_active: true,
        is_operation: true,
        is_title: false,
        is_advalorem: false,
        is_desagio: false,
        is_iof: false,
        is_liquidation: false,
      })}
      toForm={(m) => ({
        title: m.title,
        integration_key: m.integration_key,
        kind: m.kind ?? 'debit',
        is_active: m.is_active,
        is_operation: m.is_operation,
        is_title: m.is_title,
        is_advalorem: m.is_advalorem,
        is_desagio: m.is_desagio,
        is_iof: m.is_iof,
        is_liquidation: m.is_liquidation,
      })}
      form={({ values, setValue, editing }) => (
        <>
          <CampoTexto
            id="title"
            label="Nome do tipo"
            value={values.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Outras Despesas"
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

          <Campo
            id="kind"
            label="Sentido contábil"
            hint="Classificação informativa. Não entra em nenhuma fórmula do borderô."
          >
            <Select
              id="kind"
              value={values.kind ?? 'debit'}
              onChange={(v) => setValue('kind', v)}
              options={[
                { value: 'debit', label: 'Débito' },
                { value: 'credit', label: 'Crédito' },
              ]}
            />
          </Campo>

          {/* **Uma escolha, não quatro caixas.** É o que fecha o caminho para o
              erro cru "Múltiplos tipos" do legado sem esconder nada: o servidor
              continua recusando dois com 422 (BE-447), e o banco também. */}
          <RadioGroup
            legend="Classificador de taxa"
            value={classificadorDe(values)}
            onValueChange={(escolhido) => {
              ;(['is_advalorem', 'is_desagio', 'is_iof', 'is_liquidation'] as TaxClassifier[]).forEach((flag) =>
                setValue(flag, flag === escolhido),
              )
            }}
          >
            {CLASSIFICADORES.map((c) => (
              <Radio key={c.value} value={c.value} label={c.label} description={c.hint} />
            ))}
          </RadioGroup>

          <div className="flex items-start justify-between gap-4 rounded-md border border-border bg-muted/40 p-3">
            <div>
              <Label htmlFor="is_operation">Aparece no borderô</Label>
              <p className="mt-0.5 text-xs text-muted-foreground">
                Só os tipos marcados entram na lista de tarifas do formulário de borderô.
              </p>
            </div>
            <Switch
              id="is_operation"
              checked={values.is_operation === true}
              onCheckedChange={(v) => setValue('is_operation', v)}
            />
          </div>

          <div className="flex items-start justify-between gap-4 rounded-md border border-border bg-muted/40 p-3">
            <div>
              <Label htmlFor="is_title">Marcador "título"</Label>
              <p className="mt-0.5 text-xs text-muted-foreground">
                Portado do legado <strong>sem consumidor</strong>: nenhuma regra do sistema lê este marcador. Ele
                existe para não se perder dado histórico.
              </p>
            </div>
            <Switch
              id="is_title"
              checked={values.is_title === true}
              onCheckedChange={(v) => setValue('is_title', v)}
            />
          </div>

          <CampoAtivo
            value={values.is_active}
            onChange={(v) => setValue('is_active', v)}
            descricao="Marcador informativo: o tipo continua na lista de tarifas mesmo desativado (comportamento do legado, preservado)."
          />
        </>
      )}
    />
  )
}
