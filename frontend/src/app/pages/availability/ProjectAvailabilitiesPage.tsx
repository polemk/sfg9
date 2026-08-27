import { useMemo, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import {
  CalendarRange,
  Lock,
  MoreHorizontal,
  Pencil,
  Plus,
  RefreshCcw,
  Power,
  PowerOff,
  Trash2,
  TrendingDown,
  TrendingUp,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { Badge } from '@/components/ui/Badge'
import { Button } from '@/components/ui/Button'
import { DataTable } from '@/components/ui/DataTable'
import { SearchInput } from '@/components/ui/SearchInput'
import { Select } from '@/components/ui/Select'
import { Switch } from '@/components/ui/switch'
import { Tooltip } from '@/components/ui/Tooltip'
import { Campo, CampoTexto } from '@/app/pages/catalogs/CatalogFields'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { MobileCard } from '@/components/mobile/MobileCard'
import {
  MobileEmptyState,
  MobileErrorState,
  MobileListSkeleton,
} from '@/components/mobile/MobileListState'
import { MobileActionsSheet, type MobileRowAction } from '@/components/mobile/MobileRowActions'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { useMobile } from '@/hooks/useMobile'
import { useCurrentProject } from '@/hooks/useCurrentProject'
import { useJobProgress } from '@/hooks/useJobProgress'
import { useDebouncedSearch } from '@/hooks/useDebouncedSearch'
import { projectAvailabilitiesApi, type AvailabilityTemplate } from '@/lib/api/availability'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { formatAmount } from '@/lib/utils/number'

const CHAVE = ['project-availabilities'] as const

/**
 * **Disponibilidades do projeto** — a árvore de padrões
 * (FE-107..FE-112, FE-142..FE-149).
 *
 * **Nasce habilitada** (DEC-15.1). No legado os quatro itens de menu do módulo
 * eram marcados `locked: true`, mas o menu lia `g[:locked]` — do **grupo** — e
 * a marca estava nos **itens**: os quatro nunca ficaram travados (**D-90**). O
 * usuário confirmou que as telas estão em uso, então o efeito observado é o que
 * se porta.
 *
 * ## O tempo real é de verdade, e é o único mecanismo
 *
 * Ativar, desativar e remover são operações **em segundo plano**: o endpoint
 * responde **202** e o padrão fica bloqueado até o job terminar. O fim chega
 * pelo `ProjectProgressChannel` — **um** canal, **um** nome de stream, definido
 * num lugar só no servidor. **Nenhum temporizador bate na API**: nem intervalo
 * fixo, nem revalidação periódica do React Query, nem long-poll (Princípio 10).
 * O evento não carrega o dado — ele invalida a consulta, e o React Query refaz.
 *
 * (O guarda `src/__tests__/no-api-polling.test.ts` é textual de propósito:
 * escrever o nome da função proibida num comentário já reprova o arquivo. É
 * severo, e está certo — o comentário de hoje é o `copiar-colar` de amanhã.)
 *
 * ## Os defeitos de interface que morrem aqui
 *
 * | Defeito | No legado |
 * | ------- | --------- |
 * | **FE-145** | o menu de contexto de um padrão "global + com filhos" ficava **sem nenhum item** — abria vazio |
 * | **FE-145** | `openDetail` era `ReferenceError`: clicar na linha quebrava |
 * | **FE-112** | a confirmação usava `M.SUCESS`, constante inexistente |
 * | **FE-111** | a mensagem dizia "Indicador ativado/deasativado" — texto de outro módulo, com erro de grafia |
 * | **FE-144** | `preventDoubleSubmit` nunca era restaurado: depois da primeira ação o controle ficava inerte |
 * | **FE-149** | dois handlers de recarregar, um deles para um seletor inexistente |
 */
export function ProjectAvailabilitiesPage() {
  const queryClient = useQueryClient()
  const { current: project } = useCurrentProject()
  const isMobile = useMobile()
  const busca = useDebouncedSearch()
  const [mostrarInativos, setMostrarInativos] = useState(true)
  const [criando, setCriando] = useState(false)
  const [renomeando, setRenomeando] = useState<AvailabilityTemplate | null>(null)
  const [removendo, setRemovendo] = useState<AvailabilityTemplate | null>(null)
  const [acoesDe, setAcoesDe] = useState<AvailabilityTemplate | null>(null)
  /**
   * **O botão "…" da linha que abriu o menu** — a âncora do dropdown de desktop.
   *
   * Achado do usuário: *"o `more` de disponibilidade não faz sentido ser assim
   * no desktop; no mobile faz, no desktop tem que ser dropdown"*. A escolha
   * entre folha e menu é do COMPONENTE (`MobileActionsSheet`, que decide por
   * `useMobile`); o que a tela precisa dar é o elemento em que o menu se ancora,
   * porque o "…" é por linha e a folha é uma só, no fim da página.
   */
  const ancoraDasAcoes = useRef<HTMLButtonElement | null>(null)

  const filtros = useMemo(
    () => ({
      q: busca.consulta || undefined,
      is_active: mostrarInativos ? undefined : true,
    }),
    [busca.consulta, mostrarInativos],
  )

  const lista = useQuery({
    queryKey: [...CHAVE, filtros],
    queryFn: () => projectAvailabilitiesApi.list(filtros),
  })

  /**
   * **A prova de que o "ao vivo" está ligado em alguma coisa.**
   *
   * O job publica no canal do projeto e este hook invalida a consulta da lista.
   * Sem isto a tela mostraria "bloqueado" para sempre até alguém apertar F5 —
   * que é exatamente o estado em que o legado deixava o usuário, porque o
   * `delegate` padrão só imprimia no stdout e **nenhuma tela consumia o
   * progresso**.
   */
  const progresso = useJobProgress({
    projectId: project?.id ?? null,
    // **`invalidateKeys` E MAIS NADA.** A primeira versão deste hook também
    // invalidava a mesma chave no `onDone`, e a prova de cabo mostrou o
    // resultado: **um** evento produzia **duas** requisições a
    // `/api/v1/project_availabilities`. Era inofensivo enquanto a tela fosse
    // idempotente, e deixaria de ser no primeiro contador ou animação.
    //
    // É o mesmo modo de falha do `WhatsappInstanceChannel`, que assinava duas
    // chaves enquanto o serviço transmitia para as duas: cada lado coerente
    // sozinho, nenhum portão pegando, e todo evento em dobro. A medição está
    // registrada — depois da correção, um evento produz **uma** requisição.
    invalidateKeys: [[...CHAVE]],
    onFailed: (p) =>
      notify.error(p.error ?? 'A operação em segundo plano falhou. O padrão voltou a ficar utilizável.'),
  })

  const recarregar = () => queryClient.invalidateQueries({ queryKey: CHAVE })

  const mutacaoAtivar = useMutation({
    mutationFn: (t: AvailabilityTemplate) =>
      t.is_active ? projectAvailabilitiesApi.deactivate(t.id) : projectAvailabilitiesApi.activate(t.id),
    onSuccess: (_dado, t) => {
      // FE-111 — a mensagem fala do domínio certo. O legado dizia "Indicador
      // ativado/deasativado", texto de outro módulo e com erro de grafia.
      notify.success(
        t.is_active
          ? 'Desativando o padrão de disponibilidade. Os lançamentos estão sendo recalculados.'
          : 'Ativando o padrão de disponibilidade. Os lançamentos estão sendo recalculados.',
      )
      recarregar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível alterar o padrão.')),
  })

  const mutacaoRemover = useMutation({
    mutationFn: (t: AvailabilityTemplate) => projectAvailabilitiesApi.remove(t.id),
    onSuccess: () => {
      notify.success('Removendo o padrão. Ele fica bloqueado até a operação terminar.')
      setRemovendo(null)
      recarregar()
    },
    onError: (erro) => {
      // DC-20 — padrão com lançamentos responde 422, e os lançamentos
      // PERMANECEM. O legado apagava tudo, contornando o próprio
      // `restrict_with_error`, e a tela dizia "removido com sucesso".
      notify.error(mensagemDoServidor(erro, 'Não foi possível remover o padrão.'))
      setRemovendo(null)
    },
  })

  const padroes = lista.data ?? []

  // **Os dois 409 de escopo são ESTADO, não erro** (`current_project!`). "Você
  // ainda não escolheu o projeto" numa página de erro vermelha faz o usuário
  // procurar um problema que não existe. O 404 (projeto que ele não enxerga)
  // continua caindo no `ErrorState`, porque aí é erro de verdade.
  const escopo = projectScopeCode(lista.error)

  /**
   * **FE-145 — o menu de contexto NUNCA renderiza vazio.**
   *
   * No legado, um padrão global **com filhos** produzia um menu sem nenhum
   * item: as três ações estavam atrás de condições que, juntas, nunca eram
   * verdadeiras. Aqui "Ver detalhes" está sempre presente, e cada ação
   * indisponível vira um item **desabilitado com o motivo** — que é informação,
   * não item a esconder.
   */
  const acoesDoPadrao = (t: AvailabilityTemplate): MobileRowAction[] => {
    const bloqueado = t.is_locked
    const motivoBloqueio = t.locked_message ?? 'Há uma operação em andamento neste padrão.'

    return [
      {
        key: 'renomear',
        label: 'Renomear',
        icon: <Pencil aria-hidden="true" className="h-4 w-4" />,
        disabledReason: bloqueado ? motivoBloqueio : undefined,
        onSelect: () => setRenomeando(t),
      },
      {
        key: 'ativacao',
        label: t.is_active ? 'Desativar' : 'Ativar',
        icon: t.is_active ? (
          <PowerOff aria-hidden="true" className="h-4 w-4" />
        ) : (
          <Power aria-hidden="true" className="h-4 w-4" />
        ),
        disabledReason: bloqueado
          ? motivoBloqueio
          : t.is_active && t.is_mandatory
            ? 'Este padrão é obrigatório e não pode ser desativado. É a mesma regra que o servidor aplica.'
            : undefined,
        onSelect: () => mutacaoAtivar.mutate(t),
      },
      {
        key: 'remover',
        label: 'Remover',
        icon: <Trash2 aria-hidden="true" className="h-4 w-4" />,
        destructive: true,
        disabledReason: bloqueado
          ? motivoBloqueio
          : t.is_global
            ? 'Este padrão veio do catálogo global. Remova-o no catálogo, ou desative-o aqui.'
            : t.deletable === false
              ? 'Este padrão tem lançamentos. Exclua os lançamentos antes, ou desative o padrão.'
              : undefined,
        onSelect: () => setRemovendo(t),
      },
    ]
  }

  const cabecalho = (
    <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 className="text-xl font-semibold text-foreground">Disponibilidades</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Os padrões deste projeto — as linhas do painel de disponibilidade, em até três níveis.
        </p>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <SearchInput
          value={busca.termo}
          onValueChange={busca.setTermo}
          onClear={busca.limpar}
          loading={busca.pendente}
          placeholder="Buscar pelo título do padrão…"
          className="w-full sm:w-64"
        />
        <label className="flex min-h-[3rem] items-center gap-2 text-sm text-muted-foreground sm:min-h-0">
          <Switch
            id="mostrar-inativos"
            checked={mostrarInativos}
            onCheckedChange={setMostrarInativos}
          />
          Mostrar desativados
        </label>
        {/*
          **FE-149 — atualizar a lista.** O legado tinha o botão, e ele não é
          enfeite aqui: ativar, desativar ou remover um padrão dispara um job que
          recalcula lançamentos em segundo plano, e a tela já se refaz sozinha
          quando o `ProjectProgressChannel` avisa. Quando o job falha, ou quando
          outra pessoa mexeu no catálogo, o aviso não vem — e sem este botão a
          única saída era recarregar a página inteira.

          **Isto NÃO é polling** (Princípio 10): quem clica é o usuário, não um
          temporizador. Nenhum intervalo bate na API.

          Usa o `recarregar()` da própria página — o mesmo que as mutações
          chamam. O legado tinha DOIS handlers de recarregar aqui, um deles
          apontando para um seletor inexistente; um caminho só é o conserto.
        */}
        <Button
          variant="secondary"
          aria-label="Atualizar a lista de padrões"
          disabled={lista.isFetching}
          onClick={recarregar}
        >
          <RefreshCcw
            aria-hidden="true"
            className={cn('mr-1.5 h-4 w-4', lista.isFetching && 'animate-spin')}
          />
          Atualizar
        </Button>
        <Button onClick={() => setCriando(true)}>
          <Plus aria-hidden="true" className="mr-1.5 h-4 w-4" />
          Novo padrão
        </Button>
      </div>
    </div>
  )

  const avisoDeProgresso = progresso.ativo ? (
    <div
      role="status"
      className="mb-3 flex items-center gap-2 rounded-md bg-secondary px-3 py-2 text-sm text-secondary-foreground"
    >
      <span className="h-2 w-2 animate-pulse rounded-full bg-primary" aria-hidden="true" />
      {progresso.message ?? 'Atualizando os lançamentos…'}
      {progresso.percent !== null && (
        // `useJobProgress` faz `Number(bruto)`: um andamento de 1/3 chegava como
        // `33.33333333333333%` na tela. Percentual de barra se lê inteiro.
        <span className="font-numeric tabular-nums">{formatAmount(progresso.percent, 0)}%</span>
      )}
    </div>
  ) : null

  // -------------------------------------------------------- versão estreita
  if (isMobile) {
    return (
      <div>
        {cabecalho}
        {avisoDeProgresso}

        {escopo && <ProjectScopeState code={escopo} recurso="os padrões de disponibilidade" />}

        {!escopo && lista.isLoading && <MobileListSkeleton rows={6} />}
        {!escopo && lista.isError && (
          <MobileErrorState
            detail={mensagemDoServidor(lista.error, 'Não foi possível carregar os padrões.')}
            onRetry={() => lista.refetch()}
          />
        )}
        {!escopo && !lista.isLoading && !lista.isError && padroes.length === 0 && (
          <MobileEmptyState
            title={busca.consulta ? 'Nada encontrado' : 'Nenhum padrão neste projeto'}
            description={
              busca.consulta
                ? `Nenhum padrão com "${busca.consulta}". Limpe a busca para ver a árvore inteira.`
                : 'Os padrões definem as linhas do painel de disponibilidade. Cadastre o primeiro, ou traga-os do catálogo global.'
            }
            filtered={Boolean(busca.consulta)}
          />
        )}

        <div className="space-y-2">
          {padroes.map((t) => (
            <MobileCard
              key={t.id}
              title={`${t.position_path} — ${t.title}`}
              subtitle={`${t.operation_type_label} · ${t.deadline_type_label} · nível ${t.level}`}
              statusTone={t.is_locked ? 'warning' : t.is_active ? 'success' : 'neutral'}
              status={t.is_locked ? 'Bloqueado' : t.is_active ? 'Ativo' : 'Desativado'}
              headerAction={
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label={`Ações de ${t.title}`}
                  className="min-h-[3rem] min-w-[3rem]"
                  onClick={() => setAcoesDe(t)}
                >
                  <MoreHorizontal aria-hidden="true" className="h-5 w-5" />
                </Button>
              }
            >
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-xs text-muted-foreground">{t.scope_label ?? '—'}</span>
                <Marcadores template={t} />
              </div>
            </MobileCard>
          ))}
        </div>

        <MobileActionsSheet
          open={acoesDe !== null}
          onOpenChange={(aberto) => !aberto && setAcoesDe(null)}
          title={acoesDe ? `${acoesDe.position_path} — ${acoesDe.title}` : ''}
          actions={acoesDe ? acoesDoPadrao(acoesDe) : []}
        />

        <Formularios
          criando={criando}
          setCriando={setCriando}
          renomeando={renomeando}
          setRenomeando={setRenomeando}
          removendo={removendo}
          setRemovendo={setRemovendo}
          onRemover={(t) => mutacaoRemover.mutate(t)}
          recarregar={recarregar}
        />
      </div>
    )
  }

  // ---------------------------------------------------------- versão larga
  return (
    <div>
      {cabecalho}
      {avisoDeProgresso}

      {escopo && <ProjectScopeState code={escopo} recurso="os padrões de disponibilidade" />}

      {!escopo && (
      <DataTable<AvailabilityTemplate>
        data={padroes}
        loading={lista.isLoading}
        error={lista.isError ? lista.error : null}
        onRetry={() => lista.refetch()}
        rowKey={(t) => t.id}
        emptyTitle={busca.consulta ? 'Nada encontrado' : 'Nenhum padrão neste projeto'}
        emptyDescription={
          busca.consulta
            ? `Nenhum padrão com "${busca.consulta}". Limpe a busca para ver a árvore inteira.`
            : 'Os padrões definem as linhas do painel de disponibilidade. Cadastre o primeiro, ou traga-os do catálogo global.'
        }
        columns={[
          {
            key: 'position',
            header: 'Nº',
            width: '5.5rem',
            cell: (t) => (
              <span className="font-numeric tabular-nums text-muted-foreground">{t.position_path}</span>
            ),
          },
          {
            key: 'title',
            header: 'Título',
            cell: (t) => (
              <span
                className="flex items-center gap-2"
                style={{ paddingLeft: `${(t.level - 1) * 1.25}rem` }}
              >
                <CalendarRange aria-hidden="true" className="h-4 w-4 shrink-0 text-muted-foreground" />
                <span className={t.is_active ? 'truncate' : 'truncate text-muted-foreground'}>
                  {t.title}
                </span>
              </span>
            ),
          },
          {
            key: 'operation_type',
            header: 'Natureza',
            width: '9rem',
            cell: (t) => {
              const ehDebito = t.operation_type === 'D'
              const Icone = ehDebito ? TrendingDown : TrendingUp
              return (
                <span className="flex items-center gap-1.5">
                  <Icone
                    aria-hidden="true"
                    className={ehDebito ? 'h-4 w-4 text-negative' : 'h-4 w-4 text-success'}
                  />
                  {t.operation_type_label}
                </span>
              )
            },
          },
          {
            key: 'estado',
            header: 'Estado',
            width: '13rem',
            // **FE-146 / DC-36** — o estado com **motivo, autor e data**. O
            // estado "concluído" do legado NÃO é portado: os estilos
            // `.disabled` e `.project_availability_completed` não têm emissor —
            // sem coluna, sem controller, sem o que preservar.
            cell: (t) => <EstadoDoPadrao template={t} />,
          },
          {
            key: 'flags',
            header: 'Marcadores',
            cell: (t) => <Marcadores template={t} />,
          },
          {
            key: 'acoes',
            header: <span className="sr-only">Ações</span>,
            align: 'right',
            width: '4rem',
            cell: (t) => (
              <Button
                variant="ghost"
                size="icon"
                aria-label={`Ações de ${t.title}`}
                aria-haspopup="menu"
                onClick={(evento) => {
                  // A âncora é o botão CLICADO, não um botão fixo: é o que faz o
                  // menu nascer colado na linha certa.
                  ancoraDasAcoes.current = evento.currentTarget
                  setAcoesDe(t)
                }}
              >
                <MoreHorizontal aria-hidden="true" className="h-4 w-4" />
              </Button>
            ),
          },
        ]}
      />
      )}

      {/* A mesma LISTA de ações da versão estreita — em outra apresentação. Duas
          implementações de "as ações deste padrão" seriam duas listas que
          divergem, e foi assim que o menu do legado ficou vazio numa combinação
          e cheio noutra. Aqui, no desktop, ela vira um menu ancorado no "…" da
          linha; no telefone continua sendo a folha do rodapé. Quem decide é o
          componente. */}
      <MobileActionsSheet
        open={acoesDe !== null}
        onOpenChange={(aberto) => !aberto && setAcoesDe(null)}
        anchorRef={ancoraDasAcoes}
        title={acoesDe ? `${acoesDe.position_path} — ${acoesDe.title}` : ''}
        actions={acoesDe ? acoesDoPadrao(acoesDe) : []}
      />

      <Formularios
        criando={criando}
        setCriando={setCriando}
        renomeando={renomeando}
        setRenomeando={setRenomeando}
        removendo={removendo}
        setRemovendo={setRemovendo}
        onRemover={(t) => mutacaoRemover.mutate(t)}
        recarregar={recarregar}
      />
    </div>
  )
}

/** FE-146 — bloqueado / desativado / específico, com motivo, autor e data. */
function EstadoDoPadrao({ template }: { template: AvailabilityTemplate }) {
  if (template.is_locked) {
    const quando = template.locked_at
      ? new Date(template.locked_at).toLocaleString('pt-BR')
      : 'agora'
    const quem = template.locked_by_name ? ` por ${template.locked_by_name}` : ''
    return (
      <Tooltip content={`${template.locked_message ?? 'Operação em andamento.'} (${quando}${quem})`}>
        <Badge variant="warning" className="whitespace-nowrap">
          <Lock aria-hidden="true" className="mr-1 h-3 w-3 shrink-0" />
          Bloqueado
        </Badge>
      </Tooltip>
    )
  }

  return (
    <span className="flex items-center gap-1.5">
      <Badge variant={template.is_active ? 'success' : 'outline'} className="whitespace-nowrap">
        {template.is_active ? 'Ativo' : 'Desativado'}
      </Badge>
      <Tooltip
        content={
          template.is_global
            ? 'Veio do catálogo global. Só pode ser removido pelo catálogo.'
            : 'Cadastrado neste projeto.'
        }
      >
        <Badge variant="secondary" className="whitespace-nowrap">{template.scope_label ?? '—'}</Badge>
      </Tooltip>
    </span>
  )
}

function Marcadores({ template }: { template: AvailabilityTemplate }) {
  return (
    <span className="flex flex-wrap items-center gap-1">
      {template.is_mandatory && (
        <Tooltip content="Obrigatório: não pode ser desativado.">
          <Badge variant="secondary" className="whitespace-nowrap">Obrigatório</Badge>
        </Tooltip>
      )}
      {template.is_adjusted && (
        <Tooltip content="Corrigido: o valor gravado é o digitado multiplicado pela proporção de dias úteis decorridos no mês (seg–sex, sem feriados).">
          <Badge variant="warning" className="whitespace-nowrap">Corrigido</Badge>
        </Tooltip>
      )}
      {/* **FE-133 — o marcador de não cumulativo, com explicação consultável.**
          O legado não mostrava isso em lugar nenhum, e o usuário via o valor do
          filho na tela sem entender por que ele não somava no pai. */}
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

function Formularios({
  criando,
  setCriando,
  renomeando,
  setRenomeando,
  removendo,
  setRemovendo,
  onRemover,
  recarregar,
}: {
  criando: boolean
  setCriando: (v: boolean) => void
  renomeando: AvailabilityTemplate | null
  setRenomeando: (v: AvailabilityTemplate | null) => void
  removendo: AvailabilityTemplate | null
  setRemovendo: (v: AvailabilityTemplate | null) => void
  onRemover: (t: AvailabilityTemplate) => void
  recarregar: () => void
}) {
  return (
    <>
      <DialogoDeCriacao aberto={criando} onFechar={() => setCriando(false)} onCriado={recarregar} />
      <DialogoDeRenomear
        template={renomeando}
        onFechar={() => setRenomeando(null)}
        onSalvo={recarregar}
      />

      <Dialog open={removendo !== null} onOpenChange={(aberto) => !aberto && setRemovendo(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Remover o padrão?</DialogTitle>
            <DialogDescription>
              {removendo
                ? `"${removendo.title}" e os itens abaixo dele saem deste projeto. O padrão fica bloqueado até a operação terminar. Se houver lançamento vinculado, o servidor recusa e nada é apagado.`
                : ''}
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="secondary" onClick={() => setRemovendo(null)}>
              Cancelar
            </Button>
            <Button variant="destructive" onClick={() => removendo && onRemover(removendo)}>
              Remover
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}

/**
 * **FE-110 / FE-148** — o "Faz parte de" vem de **busca sob demanda no
 * servidor**, já escopada no projeto corrente. Um `parent_template_id` de outro
 * projeto é recusado pelo servidor, e por isso nem chega a ser oferecido.
 */
function DialogoDeCriacao({
  aberto,
  onFechar,
  onCriado,
}: {
  aberto: boolean
  onFechar: () => void
  onCriado: () => void
}) {
  const [valores, setValores] = useState<Record<string, any>>({
    title: '',
    operation_type: 'C',
    deadline_type: 'CP',
    parent_template_id: null,
    is_mandatory: false,
    is_cumulative: true,
    is_adjusted: false,
  })

  const pais = useQuery({
    queryKey: ['project-availabilities', 'available-parents'],
    queryFn: () => projectAvailabilitiesApi.availableParents(),
    enabled: aberto,
  })

  const criar = useMutation({
    mutationFn: () => projectAvailabilitiesApi.create(valores),
    onSuccess: () => {
      notify.success('Padrão de disponibilidade criado.')
      setValores({
        title: '',
        operation_type: 'C',
        deadline_type: 'CP',
        parent_template_id: null,
        is_mandatory: false,
        is_cumulative: true,
        is_adjusted: false,
      })
      onCriado()
      onFechar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível criar o padrão.')),
  })

  const setValue = (campo: string, valor: unknown) =>
    setValores((atual) => ({ ...atual, [campo]: valor }))

  return (
    <Dialog open={aberto} onOpenChange={(a) => !a && onFechar()}>
      <DialogContent className="max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Novo padrão de disponibilidade</DialogTitle>
          <DialogDescription>
            O nível é derivado do padrão acima: sem pai, é 1º nível; com pai de 1º nível, é 2º. A
            hierarquia vai até três níveis.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <CampoTexto
            id="title"
            label="Título"
            value={valores.title}
            onChange={(v) => setValue('title', v)}
            placeholder="Ex.: Caixa e equivalentes"
            autoFocus
          />

          <Campo
            id="parent_template_id"
            label="Faz parte de"
            hint="Só padrões deste projeto que ainda podem receber um nível abaixo."
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
              value={valores.parent_template_id ?? ''}
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
              value={valores.operation_type}
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
              value={valores.deadline_type}
              onChange={(v) => setValue('deadline_type', v)}
            />
          </Campo>
        </div>

        <DialogFooter>
          <Button variant="secondary" onClick={onFechar}>
            Cancelar
          </Button>
          {/* FE-144 — o controle volta a ser utilizável depois da ação. No
              legado o `preventDoubleSubmit` nunca era restaurado. */}
          <Button onClick={() => criar.mutate()} disabled={criar.isPending || !valores.title.trim()}>
            {criar.isPending ? 'Criando…' : 'Criar padrão'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

/**
 * **FE-109 / DC-24** — na edição, **o que não pode mudar aparece somente
 * leitura, com a razão**.
 *
 * No legado toda a configuração vivia dentro de um `if id.blank?` na view: na
 * edição os campos simplesmente sumiam, sem nenhuma explicação. A restrição
 * fica — mudar a natureza da operação ou a correção reescreveria o significado
 * dos lançamentos já gravados —, mas agora ela é dita.
 */
function DialogoDeRenomear({
  template,
  onFechar,
  onSalvo,
}: {
  template: AvailabilityTemplate | null
  onFechar: () => void
  onSalvo: () => void
}) {
  const [titulo, setTitulo] = useState('')

  const salvar = useMutation({
    mutationFn: () => projectAvailabilitiesApi.rename(template!.id, titulo),
    onSuccess: () => {
      notify.success('Padrão renomeado.')
      onSalvo()
      onFechar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível renomear o padrão.')),
  })

  return (
    <Dialog
      open={template !== null}
      onOpenChange={(aberto) => {
        if (aberto && template) setTitulo(template.title)
        if (!aberto) onFechar()
      }}
    >
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Editar padrão</DialogTitle>
          <DialogDescription>
            Só o título é editável. A natureza da operação, o prazo, a cumulatividade, a correção e o
            pai definem como os lançamentos já gravados foram calculados — alterá-los mudaria valores
            do histórico. Para uma configuração diferente, crie um padrão novo.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          <CampoTexto
            id="titulo"
            label="Título"
            value={titulo}
            onChange={setTitulo}
            autoFocus
          />

          {template && (
            <dl className="grid grid-cols-2 gap-3 rounded-md bg-muted/40 p-3 text-sm">
              <ItemImutavel rotulo="Natureza" valor={template.operation_type_label} />
              <ItemImutavel rotulo="Prazo" valor={template.deadline_type_label} />
              <ItemImutavel rotulo="Nível" valor={String(template.level)} />
              <ItemImutavel rotulo="Numeração" valor={template.position_path} />
              <ItemImutavel
                rotulo="Entra na soma do pai"
                valor={template.is_cumulative ? 'Sim' : 'Não'}
              />
              <ItemImutavel
                rotulo="Corrigido por dias úteis"
                valor={template.is_adjusted ? 'Sim' : 'Não'}
              />
            </dl>
          )}
        </div>

        <DialogFooter>
          <Button variant="secondary" onClick={onFechar}>
            Cancelar
          </Button>
          <Button onClick={() => salvar.mutate()} disabled={salvar.isPending || !titulo.trim()}>
            {salvar.isPending ? 'Salvando…' : 'Salvar'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}

function ItemImutavel({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{rotulo}</dt>
      <dd className="text-sm text-foreground">{valor}</dd>
    </div>
  )
}
