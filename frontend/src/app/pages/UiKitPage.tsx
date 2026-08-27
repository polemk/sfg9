import { useState } from 'react'
import { Building2, Plus, Trash2 } from 'lucide-react'
import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/Card'
import { Badge } from '@/components/ui/Badge'
import { Checkbox } from '@/components/ui/Checkbox'
import { RadioGroup, Radio } from '@/components/ui/RadioGroup'
import { Select } from '@/components/ui/Select'
import { Spinner } from '@/components/ui/Spinner'
import { SearchInput } from '@/components/ui/SearchInput'
import { Autocomplete } from '@/components/ui/Autocomplete'
import { DatePicker, DateRangePicker } from '@/components/ui/DatePicker'
import { MoneyInput, PercentInput } from '@/components/ui/NumericInput'
import { DataTable, type Column } from '@/components/ui/DataTable'
import { DetailList } from '@/components/ui/DetailList'
import { PaginationPill } from '@/components/ui/PaginationPill'
import { MobilePagination } from '@/components/mobile/MobilePagination'
import { AsyncSection } from '@/components/ui/AsyncSection'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Tooltip } from '@/components/ui/Tooltip'
import { FieldHelp } from '@/components/help/FieldHelp'
import { UserAvatar } from '@/components/ui/UserAvatar'
import { Switch } from '@/components/ui/switch'
import { RechartsPie } from '@/components/charts/RechartsPie'
import { PageHeader } from '@/components/PageHeader'
import { ThemeToggle } from '@/components/ThemeToggle'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'
import { notify } from '@/lib/notify'
import { usePagination } from '@/hooks/usePagination'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'

/**
 * Galeria dos primitivos — **só em desenvolvimento** (`import.meta.env.DEV`).
 *
 * Existe por causa do DEC-98: "toda tela nasce conferida em light E dark, e a
 * conferência é renderizando e olhando". Um `tsc --noEmit` limpo já conviveu
 * com um popover invisível e com um menu que virava sopa de texto ao clicar.
 *
 * A galeria é o lugar onde cada primitivo aparece **aberto** — dropdown, modal,
 * calendário, autocomplete — que é o único estado em que dá para ver se o
 * `bg-popover` contrasta com o `card` embaixo. Fechado, tudo parece perfeito
 * nos dois modos.
 *
 * A rota não é registrada no build de produção.
 */
interface Linha {
  id: string
  cliente: string
  vencimento: string
  valor: number
  taxa: number
  status: 'Em dia' | 'Vencido' | 'Liquidado'
}

const LINHAS: Linha[] = [
  { id: '1', cliente: 'Metalúrgica Andrade Ltda', vencimento: '2026-09-14', valor: 128450.9, taxa: 2.35, status: 'Em dia' },
  { id: '2', cliente: 'Transportes Boa Vista', vencimento: '2026-07-02', valor: 9800, taxa: 3.1, status: 'Vencido' },
  { id: '3', cliente: 'Comercial São Judas', vencimento: '2026-11-30', valor: 45230.55, taxa: 1.8, status: 'Liquidado' },
  { id: '4', cliente: 'Agro Terra Nova S/A', vencimento: '2026-08-21', valor: 1204000, taxa: 2.05, status: 'Em dia' },
]

const COLUNAS: Column<Linha>[] = [
  { key: 'cliente', header: 'Cliente', sortable: true },
  { key: 'vencimento', header: 'Vencimento', variant: 'date', sortable: true },
  { key: 'valor', header: 'Valor', variant: 'money', sortable: true },
  { key: 'taxa', header: 'Taxa', variant: 'percent', sortable: true },
  {
    key: 'status',
    header: 'Situação',
    // Coluna sem `sortable`: repare que ela não ganha seta nem hover.
    cell: (r) => (
      <Badge variant={r.status === 'Vencido' ? 'destructive' : r.status === 'Liquidado' ? 'secondary' : 'success'}>
        {r.status}
      </Badge>
    ),
  },
]

const OPCOES = [
  { value: 'og', label: 'OG', description: 'Acesso total' },
  { value: 'admin', label: 'Administrador' },
  { value: 'gerente', label: 'Gerente' },
  { value: 'colaborador', label: 'Colaborador' },
  { value: 'suspenso', label: 'Suspenso', disabled: true },
]

const PESSOAS = [
  { id: 'u1', label: 'Ana Beatriz Correia', subtitle: 'ana.correia@safegold.com.br', meta: 'Gerente' },
  { id: 'u2', label: 'Carlos Eduardo Nunes', subtitle: 'carlos.nunes@safegold.com.br', meta: 'Colaborador' },
  { id: 'u3', label: 'Mariana Duarte', subtitle: 'mariana.duarte@safegold.com.br', meta: 'Admin' },
]

function Bloco({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <Card>
      <CardHeader className="pb-3">
        <CardTitle className="text-base">{titulo}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">{children}</CardContent>
    </Card>
  )
}

export function UiKitPage() {
  const [papel, setPapel] = useState<string | null>('gerente')
  const [marcado, setMarcado] = useState(true)
  const [radio, setRadio] = useState('participante')
  const [pessoa, setPessoa] = useState<string | null>(null)
  const [varias, setVarias] = useState<string[]>(['u1', 'u3'])
  const [data, setData] = useState<Date | null>(new Date('2026-09-14T12:00:00'))
  const [faixa, setFaixa] = useState<{ from: Date | null; to: Date | null }>({ from: null, to: null })
  const [valor, setValor] = useState<number | null>(128450.9)
  const [taxa, setTaxa] = useState<number | null>(2.35)
  const [ligado, setLigado] = useState(true)
  const busca = useDebouncedSearch()
  const paginacao = usePagination({ initialPerPage: 20 })

  return (
    <div className="mx-auto max-w-6xl px-6 pb-32">
      <PageHeader
        title="Biblioteca de primitivos"
        subtitle="S0 — fundação do design system Safegold. Confira em claro e escuro, com cada painel ABERTO."
        rightSlot={<ThemeToggle />}
        searchSlot={
          <SearchInput
            value={busca.termo}
            onValueChange={busca.setTermo}
            loading={busca.pendente}
            placeholder="Buscar recebível, cliente ou documento…"
          />
        }
      />

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
        <Bloco titulo="Button — as cinco variantes, tamanhos e loading">
          <div className="flex flex-wrap items-center gap-2">
            <Button variant="primary">Primary</Button>
            <Button variant="secondary">Secondary</Button>
            <Button variant="ghost">Ghost</Button>
            <Button variant="destructive">Destructive</Button>
            <Button variant="link">Link</Button>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button size="sm">sm</Button>
            <Button size="default">default</Button>
            <Button size="lg">lg</Button>
            <Button size="icon" aria-label="Adicionar">
              <Plus className="h-4 w-4" />
            </Button>
            <Button disabled>Desabilitado</Button>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Button loading>Salvando</Button>
            <Button variant="secondary" loading>
              Carregando
            </Button>
            <Spinner size="xs" />
            <Spinner size="sm" />
            <Spinner size="md" />
            <Spinner size="lg" />
          </div>
        </Bloco>

        <Bloco titulo="Checkbox, RadioGroup e Switch">
          <div className="flex flex-col gap-2">
            <Checkbox label="Marcado" checked={marcado} onChange={(e) => setMarcado(e.target.checked)} />
            <Checkbox label="Desmarcado" description="Com descrição secundária" />
            <Checkbox label="Indeterminado (selecionar tudo)" indeterminate />
            <Checkbox label="Desabilitado" disabled />
          </div>
          <RadioGroup legend="Participação no projeto" value={radio} onValueChange={setRadio}>
            <Radio value="responsavel" label="Responsável" />
            <Radio value="participante" label="Participante" description="Vê e edita o que é do projeto" />
            <Radio value="coordenador" label="Coordenador" />
          </RadioGroup>
          <div className="flex items-center gap-3">
            <Switch checked={ligado} onCheckedChange={setLigado} />
            <span className="text-sm text-foreground">Membro padrão</span>
          </div>
        </Bloco>

        <Bloco titulo="Select — painel em portal (abra e confira o contraste)">
          <Select options={OPCOES} value={papel} onChange={setPapel} aria-label="Papel" />
          <Select options={OPCOES} value={null} onChange={() => {}} placeholder="Sem seleção" />
          <Select options={[]} value={null} onChange={() => {}} placeholder="Sem opções" />
          <Select options={OPCOES} value={papel} onChange={setPapel} disabled />
        </Bloco>

        <Bloco titulo="Autocomplete — simples e múltiplo">
          <Autocomplete options={PESSOAS} value={pessoa} onChange={setPessoa} placeholder="Buscar usuário…" />
          <Autocomplete
            multiple
            options={PESSOAS}
            value={varias}
            onChange={setVarias}
            placeholder="Adicionar participantes…"
          />
        </Bloco>

        <Bloco titulo="DatePicker pt-BR e faixa de período">
          <DatePicker value={data} onChange={setData} aria-label="Vencimento" />
          <DateRangePicker from={faixa.from} to={faixa.to} onChange={setFaixa} />
        </Bloco>

        <Bloco titulo="MoneyInput e PercentInput — exibem formatado, enviam número">
          <MoneyInput value={valor} onChange={setValor} />
          <PercentInput value={taxa} onChange={setTaxa} />
          <p className="font-numeric text-xs tabular-nums text-muted-foreground">
            enviado: {JSON.stringify({ valor, taxa })}
          </p>
          <MoneyInput value={null} onChange={() => {}} error="Separador decimal duplicado." />
        </Bloco>

        <Bloco titulo="Badge — estado e removível">
          <div className="flex flex-wrap gap-2">
            <Badge>default</Badge>
            <Badge variant="secondary">secondary</Badge>
            <Badge variant="outline">outline</Badge>
            <Badge variant="destructive">destructive</Badge>
            <Badge variant="success">success</Badge>
            <Badge variant="warning">warning</Badge>
            <Badge variant="info">info</Badge>
            <Badge variant="negative">negative</Badge>
          </div>
          <div className="flex flex-wrap gap-2">
            <Badge variant="secondary" onRemove={() => {}}>
              Filtro: vencidos
            </Badge>
            <Badge variant="secondary" onRemove={() => {}}>
              Mariana Duarte
            </Badge>
          </div>
        </Bloco>

        <Bloco titulo="Avatar — cor determinística pelo id">
          <div className="flex flex-wrap items-center gap-3">
            {['u1', 'u2', 'u3', 'u4', 'u5', 'u6'].map((id) => (
              <UserAvatar key={id} name={`Usuário ${id}`} colorKey={id} />
            ))}
            <UserAvatar name="Sem cor" />
          </div>
          <div className="flex flex-wrap items-center gap-3">
            <Tooltip content="Tooltip à direita" side="right">
              <Button variant="secondary" size="sm">
                direita
              </Button>
            </Tooltip>
            <Tooltip content="Tooltip acima" side="top">
              <Button variant="secondary" size="sm">
                acima
              </Button>
            </Tooltip>
            <Tooltip content="Tooltip abaixo" side="bottom">
              <Button variant="secondary" size="sm">
                abaixo
              </Button>
            </Tooltip>
            <Tooltip content="Tooltip à esquerda" side="left">
              <Button variant="secondary" size="sm">
                esquerda
              </Button>
            </Tooltip>
          </div>

          {/* S12 / OPS-545 — a AJUDA DE CAMPO, que é um Tooltip com regra.
              Fica aqui porque é aqui que a conferência visual nos dois modos
              acontece, e porque S6/S7/S8 precisam ver o mecanismo antes de
              consumi-lo nos formulários financeiros.

              Os textos vêm do servidor, de `db/seed_assets/*_help_inputs.yml`
              (DEC-88). `valor_bruto` tem texto e ganha ícone; `contrato` está
              marcado `TODO:` e **não ganha ícone nenhum**; `campo_inexistente`
              não está no mapa e também não quebra nada. */}
          <div className="flex flex-wrap items-center gap-6">
            <span className="text-sm text-foreground">
              Valor bruto <FieldHelp scope="receivables" field="valor_bruto" />
            </span>
            <span className="text-sm text-foreground">
              Float acordado <FieldHelp scope="receivables" field="float_acordado" />
            </span>
            <span className="text-sm text-muted-foreground">
              Contrato (TODO:, sem tooltip) <FieldHelp scope="receivables" field="contrato" />
            </span>
            <span className="text-sm text-muted-foreground">
              Campo inexistente <FieldHelp scope="receivables" field="campo_inexistente" />
            </span>
          </div>
        </Bloco>

        <Bloco titulo="Estados — carregando, vazio, erro">
          <LoadingState size="inline" label="Carregando recebíveis…" />
          <EmptyState size="inline" title="Nenhum recebível" description="Ajuste o período ou o filtro." />
          <ErrorState size="inline" onRetry={() => notify.info('Tentando de novo')} />
          <AsyncSection size="inline" data={[] as string[]} emptyTitle="AsyncSection: vazio">
            {() => null}
          </AsyncSection>
        </Bloco>

        <Bloco titulo="Tabs com overflow horizontal">
          <Tabs defaultValue="geral">
            <TabsList>
              <TabsTrigger value="geral">Geral</TabsTrigger>
              <TabsTrigger value="parcelas">Parcelas</TabsTrigger>
              <TabsTrigger value="anexos">Anexos</TabsTrigger>
              <TabsTrigger value="pagamentos">Pagamentos</TabsTrigger>
              <TabsTrigger value="historico">Histórico</TabsTrigger>
              <TabsTrigger value="auditoria">Auditoria</TabsTrigger>
            </TabsList>
            <TabsContent value="geral">
              <DetailList
                items={[
                  { label: 'Cliente', content: 'Metalúrgica Andrade Ltda' },
                  { label: 'Documento', content: '12.345.678/0001-90', numeric: true },
                  { label: 'Vencimento', content: '14/09/2026', numeric: true },
                  { label: 'Valor', content: 'R$ 128.450,90', numeric: true },
                  { label: 'Observações', content: 'Borderô renegociado em 08/2026.', full: true },
                ]}
              />
            </TabsContent>
            <TabsContent value="parcelas">Parcelas</TabsContent>
            <TabsContent value="anexos">Anexos</TabsContent>
            <TabsContent value="pagamentos">Pagamentos</TabsContent>
            <TabsContent value="historico">Histórico</TabsContent>
            <TabsContent value="auditoria">Auditoria</TabsContent>
          </Tabs>
        </Bloco>

        <Bloco titulo="Dialog e Toast">
          <Dialog>
            <DialogTrigger asChild>
              <Button variant="secondary">
                <Building2 className="h-4 w-4" />
                Abrir dialog
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Remover participante</DialogTitle>
                <DialogDescription>
                  Esta ação tira o acesso da pessoa a tudo que é deste projeto. Ela não é desfeita.
                </DialogDescription>
              </DialogHeader>
              <Select options={OPCOES} value={papel} onChange={setPapel} aria-label="Papel no dialog" />
              <DialogFooter>
                <Button variant="secondary">Cancelar</Button>
                <Button variant="destructive">
                  <Trash2 className="h-4 w-4" />
                  Remover
                </Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="secondary" onClick={() => notify.success('Recebível salvo.')}>
              success
            </Button>
            <Button size="sm" variant="secondary" onClick={() => notify.error('Não foi possível salvar.')}>
              error
            </Button>
            <Button size="sm" variant="secondary" onClick={() => notify.warning('Salvo com ressalva.')}>
              warning
            </Button>
            <Button size="sm" variant="secondary" onClick={() => notify.info('O campo aceita apenas dígitos.')}>
              info (M.HELP)
            </Button>
          </div>
        </Bloco>

        <Bloco titulo="RechartsPie">
          <RechartsPie
            items={[
              { label: 'Em dia', value: 1204000 },
              { label: 'Vencidos', value: 9800 },
              { label: 'Liquidados', value: 45230 },
              { label: 'Renegociados', value: 128450 },
            ]}
            variant="money"
            height={260}
          />
        </Bloco>
      </div>

      <div className="mt-5">
        <Bloco titulo="DataTable — cabeçalho que ordena de verdade; 'Situação' não é ordenável">
          <DataTable columns={COLUNAS} data={LINHAS} rowKey={(r) => r.id} defaultSort={{ key: 'valor', direction: 'desc' }} />
        </Bloco>
      </div>

      <PaginationPill
        page={paginacao.page}
        totalPages={7}
        perPage={paginacao.perPage}
        onPageChange={paginacao.setPage}
        onPerPageChange={paginacao.setPerPage}
      />

      <div className="mx-auto max-w-sm">
        <MobilePagination page={paginacao.page} total={140} perPage={paginacao.perPage} onPageChange={paginacao.setPage} />
      </div>
    </div>
  )
}

export default UiKitPage
