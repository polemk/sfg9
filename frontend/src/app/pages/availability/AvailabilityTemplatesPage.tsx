import { useQuery } from '@tanstack/react-query'
import { CalendarRange, Lock, TrendingDown, TrendingUp } from 'lucide-react'
import { CatalogScreen } from '@/app/pages/catalogs/CatalogScreen'
import { Campo, CampoTexto } from '@/app/pages/catalogs/CatalogFields'
import { Select } from '@/components/ui/Select'
import { Switch } from '@/components/ui/switch'
import { Tooltip } from '@/components/ui/Tooltip'
import { Badge } from '@/components/ui/Badge'
import {
  availabilityTemplatesApi,
  type AvailabilityTemplate,
} from '@/lib/api/availability'

/**
 * **Tipos de disponibilidade** — o catálogo GLOBAL de padrões
 * (FE-135, FE-136, FE-137, FE-138, FE-139, FE-140, FE-141).
 *
 * **Esta tela não é escopada por projeto, e isso é a regra** (contrato C1,
 * regra 4). O padrão cadastrado aqui alimenta todos os projetos; escopá-lo
 * faria um padrão sumir da tela do projeto vizinho e quebraria os padrões de
 * projeto que derivam dele.
 *
 * ## Quatro defeitos do legado morrem aqui
 *
 * - **D-06 / D-125** — a busca com texto **derrubava a requisição**. O controller
 *   montava `where!("title #{Dev.ilike} ", "#{@query}%")` — fragmento SQL sem
 *   placeholder — e ordenava por `default_position`. A análise do dump de
 *   produção (26/08/2026) confirmou que **essa coluna não existe**: zero
 *   ocorrências, e nenhuma migration a cria. `ORDER BY default_position` levanta
 *   `UndefinedColumn`, ou seja, **esta listagem está quebrada em produção há
 *   anos**. Aqui a busca é por substring e a ordem é a **hierarquia**.
 * - **D-07 / D-20** — `l` e `o` eram lidos e **nunca aplicados**: a lista vinha
 *   inteira, sempre. Agora a paginação é real (`PaginationPill`, DEC-62).
 * - **BE-134** — `is_mandatory |= 1` no model: **todo padrão global nascia
 *   obrigatório**, ignorando o formulário. A obrigatoriedade agora aparece na
 *   tela e o valor escolhido é o gravado.
 * - **DB-132** — `should_insert_on_existing_projects` tinha default `1` e
 *   **nunca era exposto**: toda criação disparava job em **todos** os projetos,
 *   sem ninguém pedir. Virou escolha, com a consequência escrita ao lado.
 *
 * O parcial `_child_widget.html.erb` do legado **não é portado**: ele usa
 * `default_position` e **nenhuma view o renderiza** (FE-138).
 */
export function AvailabilityTemplatesPage() {
  return (
    <CatalogScreen<AvailabilityTemplate>
      queryKey="availability-templates"
      api={availabilityTemplatesApi as never}
      // A ordem padrão é a **hierárquica** (D-125): o catálogo é uma árvore, e
      // listá-lo por data de criação embaralharia pais e filhos. A chave
      // pública `position` aponta para `sort_key` no servidor.
      defaultSort={{ key: 'position', direction: 'asc' }}
      texts={{
        title: 'Tipos de disponibilidade',
        subtitle:
          'O catálogo global de padrões. O que é cadastrado aqui pode ser levado para os projetos.',
        singular: 'padrão',
        createLabel: 'Novo padrão',
        emptyTitle: 'Nenhum padrão no catálogo',
        emptyDescription:
          'O padrão define uma linha do painel de disponibilidade: a natureza da operação, o prazo e se o valor é corrigido por dias úteis. Cadastre o primeiro para poder levá-lo aos projetos.',
        searchPlaceholder: 'Buscar pelo título do padrão…',
      }}
      columns={[
        {
          key: 'position',
          header: 'Nº',
          sortable: true,
          width: '5.5rem',
          accessor: (t) => t.sort_key,
          cell: (t) => (
            <span className="font-numeric tabular-nums text-muted-foreground">{t.position_path}</span>
          ),
        },
        {
          key: 'title',
          header: 'Título',
          sortable: true,
          accessor: (t) => t.title,
          cell: (t) => (
            // A indentação é o que faz a árvore ser legível numa tabela plana.
            <span
              className="flex items-center gap-2"
              style={{ paddingLeft: `${(t.level - 1) * 1.25}rem` }}
            >
              <CalendarRange aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground" />
              <span className="truncate">{t.title}</span>
              {t.is_locked && (
                <Tooltip content={t.locked_message ?? 'Operação em andamento.'}>
                  <Lock aria-hidden="true" className="h-3.5 w-3.5 shrink-0 text-warning" />
                </Tooltip>
              )}
            </span>
          ),
        },
        {
          key: 'operation_type',
          header: 'Natureza',
          sortable: true,
          accessor: (t) => t.operation_type_label,
          // FE-129 — legível. O legado mostrava o código `C`/`D` cru.
          cell: (t) => <NaturezaDaOperacao template={t} />,
        },
        {
          key: 'deadline_type',
          header: 'Prazo',
          sortable: true,
          accessor: (t) => t.deadline_type_label,
          cell: (t) => <span className="text-muted-foreground">{t.deadline_type_label}</span>,
        },
        {
          key: 'flags',
          header: 'Marcadores',
          accessor: () => '',
          cell: (t) => <MarcadoresDoPadrao template={t} />,
        },
      ]}
      mobileFields={(t) => [
        { label: 'Nº', value: t.position_path },
        { label: 'Natureza', value: <NaturezaDaOperacao template={t} /> },
        { label: 'Prazo', value: t.deadline_type_label },
        { label: 'Marcadores', value: <MarcadoresDoPadrao template={t} /> },
      ]}
      // Excluir um global desvincula os padrões de projeto derivados, em
      // transação (BE-136). Não há dependente que **bloqueie** — o que havia no
      // legado era uma rotina manual de limpeza depois (`fix_after_global_remove`).
      usageCount={() => 0}
      usageLabel={() => ''}
      emptyForm={() => ({
        title: '',
        operation_type: 'C',
        deadline_type: 'CP',
        parent_template_id: null,
        is_mandatory: false,
        is_cumulative: true,
        is_adjusted: false,
        should_insert_on_existing_projects: false,
      })}
      toForm={(t) => ({
        title: t.title,
        operation_type: t.operation_type,
        deadline_type: t.deadline_type,
        parent_template_id: t.parent_template_id,
        is_mandatory: t.is_mandatory,
        is_cumulative: t.is_cumulative,
        is_adjusted: t.is_adjusted,
      })}
      form={({ values, setValue, editing }) => (
        <FormularioPadraoGlobal values={values} setValue={setValue} editando={editing} />
      )}
    />
  )
}

/**
 * FE-129 — a natureza da operação **legível**, com o sinal que ela imprime no
 * valor. O legado exibia `C` e `D` crus, e o usuário tinha de saber de cor.
 */
function NaturezaDaOperacao({ template }: { template: AvailabilityTemplate }) {
  const ehDebito = template.operation_type === 'D'
  const Icone = ehDebito ? TrendingDown : TrendingUp
  return (
    <span className="flex items-center gap-1.5">
      <Icone
        aria-hidden="true"
        className={ehDebito ? 'h-4 w-4 shrink-0 text-negative' : 'h-4 w-4 shrink-0 text-success'}
      />
      <span className="truncate">{template.operation_type_label || '—'}</span>
    </span>
  )
}

/**
 * Os marcadores que mudam o **número** e que o legado não mostrava em lugar
 * nenhum da lista.
 */
function MarcadoresDoPadrao({ template }: { template: AvailabilityTemplate }) {
  return (
    <span className="flex flex-wrap items-center gap-1">
      {template.is_mandatory && (
        <Tooltip content="Obrigatório: não pode ser desativado, e os níveis acima também precisam ser obrigatórios.">
          <Badge variant="secondary" className="whitespace-nowrap">Obrigatório</Badge>
        </Tooltip>
      )}
      {template.is_adjusted && (
        <Tooltip content="Corrigido: o valor é multiplicado pela proporção de dias úteis decorridos no mês (seg–sex, sem feriados).">
          <Badge variant="warning" className="whitespace-nowrap">Corrigido</Badge>
        </Tooltip>
      )}
      {!template.is_cumulative && (
        <Tooltip content="Não cumulativo: este item NÃO entra na soma do nível acima — contribui zero.">
          <Badge variant="outline" className="whitespace-nowrap">
            Não soma
          </Badge>
        </Tooltip>
      )}
      {!template.is_mandatory && !template.is_adjusted && template.is_cumulative && (
        <span className="text-xs text-muted-foreground">—</span>
      )}
    </span>
  )
}

function FormularioPadraoGlobal({
  values,
  setValue,
  editando,
}: {
  values: Record<string, any>
  setValue: (campo: string, valor: unknown) => void
  editando: AvailabilityTemplate | null
}) {
  // **Busca sob demanda, escopada no servidor** (FE-139). O legado embutia
  // `AvailabilityTemplate.all` — todos os padrões de TODOS os projetos — num
  // atributo `data-templates` do HTML, e o filtro de níveis rodava sobre esse
  // JSON global.
  const pais = useQuery({
    queryKey: ['availability-templates', 'available-parents'],
    queryFn: () => availabilityTemplatesApi.availableParents(),
  })

  return (
    <>
      <CampoTexto
        id="title"
        label="Título do padrão"
        value={values.title}
        onChange={(v) => setValue('title', v)}
        placeholder="Ex.: Caixa e equivalentes"
        autoFocus
      />

      <Campo
        id="parent_template_id"
        label="Faz parte de"
        hint="Só aparecem padrões que ainda podem receber um nível abaixo — a hierarquia tem no máximo 3 níveis."
      >
        <Select
          id="parent_template_id"
          options={[
            { value: '', label: 'Nenhum — este é um padrão de 1º nível' },
            ...(pais.data ?? []).map((p) => ({
              value: p.id,
              label: `${p.position_path} — ${p.title}`,
            })),
          ]}
          value={values.parent_template_id ?? ''}
          onChange={(v) => setValue('parent_template_id', v || null)}
          placeholder="Selecione o padrão acima…"
        />
      </Campo>

      <Campo id="operation_type" label="Natureza da operação">
        <Select
          id="operation_type"
          options={[
            { value: 'C', label: 'Crédito', description: 'Soma no total do nível acima' },
            { value: 'D', label: 'Débito', description: 'Subtrai do total do nível acima' },
            { value: 'S', label: 'Saldo' },
            { value: 'M', label: 'Movimentação' },
          ]}
          value={values.operation_type ?? 'C'}
          onChange={(v) => setValue('operation_type', v)}
        />
      </Campo>

      <Campo id="deadline_type" label="Prazo">
        <Select
          id="deadline_type"
          options={[
            { value: 'CP', label: 'Curto Prazo' },
            { value: 'LP', label: 'Longo Prazo' },
          ]}
          value={values.deadline_type ?? 'CP'}
          onChange={(v) => setValue('deadline_type', v)}
        />
      </Campo>

      {/* **BE-134 — a obrigatoriedade PASSA A EXISTIR na tela.** No legado o
          model fazia `is_mandatory |= 1` e todo padrão global nascia
          obrigatório, dissesse o formulário o que dissesse. */}
      <Interruptor
        id="is_mandatory"
        label="Obrigatório"
        descricao="Um padrão obrigatório não pode ser desativado nos projetos. Ele só pode ser marcado se os níveis acima também forem obrigatórios."
        value={values.is_mandatory}
        onChange={(v) => setValue('is_mandatory', v)}
      />

      <Interruptor
        id="is_cumulative"
        label="Entra na soma do nível acima"
        descricao="Desmarcado, este padrão contribui ZERO para o total do pai — o valor continua visível, mas não soma."
        value={values.is_cumulative}
        onChange={(v) => setValue('is_cumulative', v)}
      />

      <Interruptor
        id="is_adjusted"
        label="Corrigido por dias úteis"
        descricao="O valor gravado é o digitado multiplicado pela proporção de dias úteis decorridos no mês (seg–sex, sem feriados). Alterar isto num padrão já usado propaga para os projetos derivados, em segundo plano."
        value={values.is_adjusted}
        onChange={(v) => setValue('is_adjusted', v)}
      />

      {/* **DB-132 — a propagação vira ESCOLHA.** No legado a coluna tinha
          default `1` e não aparecia em tela nenhuma: toda criação enfileirava um
          job para cada projeto existente, sem ninguém pedir. */}
      {!editando && (
        <Interruptor
          id="should_insert_on_existing_projects"
          label="Levar para os projetos que já existem"
          descricao="Marcado, o padrão é copiado para todos os projetos em segundo plano, e cada projeto avisa quando terminar. Desmarcado, ele fica só no catálogo e entra nos projetos criados daqui para frente."
          value={values.should_insert_on_existing_projects}
          onChange={(v) => setValue('should_insert_on_existing_projects', v)}
        />
      )}
    </>
  )
}

/** Interruptor com a consequência escrita ao lado — não só o rótulo. */
function Interruptor({
  id,
  label,
  descricao,
  value,
  onChange,
}: {
  id: string
  label: string
  descricao: string
  value: unknown
  onChange: (v: boolean) => void
}) {
  return (
    <div className="flex items-start gap-3 rounded-md bg-muted/40 p-3">
      <Switch id={id} checked={value === true} onCheckedChange={onChange} />
      <label htmlFor={id} className="cursor-pointer">
        <span className="block text-sm font-medium text-foreground">{label}</span>
        <span className="mt-0.5 block text-xs leading-relaxed text-muted-foreground">{descricao}</span>
      </label>
    </div>
  )
}
