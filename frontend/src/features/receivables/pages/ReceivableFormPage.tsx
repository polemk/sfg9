import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, Building2, Landmark, Undo2 } from 'lucide-react'
import { notify } from '@/lib/notify'
import { PageHeader } from '@/components/PageHeader'
import { Button } from '@/components/ui/Button'
import { Card } from '@/components/ui/Card'
import { DatePicker } from '@/components/ui/DatePicker'
import { EmptyState, ErrorState, LoadingState } from '@/components/ui/States'
import { ConfirmDialog } from '@/components/ui/ConfirmDialog'
import { FormActionBar } from '@/components/ui/FormActionBar'
import { Input } from '@/components/ui/Input'
import { Label } from '@/components/ui/Label'
import { MoneyInput } from '@/components/ui/MoneyInput'
import { NumericInput } from '@/components/ui/NumericInput'
import { Select } from '@/components/ui/Select'
import { Textarea } from '@/components/ui/textarea'
import { Tooltip } from '@/components/ui/Tooltip'
import { ProjectScopeState, projectScopeCode } from '@/components/ProjectScopeState'
import { useMobile } from '@/hooks/useMobile'
import { useUnsavedChanges } from '@/hooks/useUnsavedChanges'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { carrierConnectionsApi, companiesApi } from '@/lib/api/projects'
import { formatMoney } from '@/lib/utils/number'
import {
  movementKindsApi,
  receivableKindsApi,
  receivablesApi,
  resourceSourcesApi,
  walletsApi,
  type ReceivableEntry,
  type ReceivablePayload,
} from '../api/receivables'
import { useReceivablePreview } from '../hooks/useReceivablePreview'
import { CalculationPanel } from '../components/CalculationPanel'
import { TaxRows, type TaxRow } from '../components/TaxRows'

/**
 * **Formulário de borderô** (FE-165…FE-178).
 *
 * ## Uma regra governa esta tela: ela não calcula
 *
 * Todo campo derivado é **somente leitura** e vem de
 * `POST /receivables/preview` — o mesmo `Receivables::Calculator` que a
 * gravação usa (contrato **C2**). Não há aritmética de borderô neste arquivo.
 *
 * ## Os estados de bloqueio dizem a RAZÃO (FE-166, FE-167)
 *
 * Sem portador conectado ao projeto, ou sem empresa cadastrada, o formulário é
 * **suprimido com o motivo e o atalho para resolver** — inclusive na edição, que
 * é onde o legado montava a URL com uma variável `id` indefinida e o link ia
 * para lugar nenhum.
 *
 * ## Catálogo vazio NÃO derruba a tela
 *
 * O legado fazia `Wallet.first.id` para pré-selecionar a carteira. Com o
 * catálogo vazio isso é `NoMethodError` — e o catálogo estava vazio porque as
 * flags `should_seed_*` do legado vinham `false` e o seed nunca rodava.
 *
 * ## Gravar acontece UMA vez
 *
 * O botão desabilita enquanto a mutação está em voo. No legado a tela acumulava
 * *bindings* `ajax:*` a cada re-render e o mesmo clique podia enviar o
 * formulário várias vezes.
 *
 * ## O tipo de operação é imutável na edição
 *
 * Trocar o subtipo de um borderô já lançado moveria exposição entre limites sem
 * deixar rastro na operação de risco. O servidor também recusa.
 */
interface FormState {
  date: Date | null
  data_credito: Date | null
  nro_bordero: string
  description: string
  observacoes: string
  company_id: string
  carrier_id: string
  wallet_id: string
  receivable_kind_id: string
  resource_source_id: string
  valor_bruto: number | null
  vlr_bruto_recusado: number | null
  qtd_titulos: number | null
  qtd_recusada: number | null
  prz_med_pond_emp: number | null
  prz_med_pond_bco: number | null
  float_acordado: number | null
  cst_efetivo_acordado: number | null
  nominal_tax: number | null
  recompra: number | null
  retencao: number | null
  fomento: number | null
  outros: number | null
}

const VAZIO: FormState = {
  date: new Date(),
  data_credito: null,
  nro_bordero: '',
  description: '',
  observacoes: '',
  company_id: '',
  carrier_id: '',
  wallet_id: '',
  receivable_kind_id: '',
  resource_source_id: '',
  valor_bruto: null,
  vlr_bruto_recusado: 0,
  qtd_titulos: null,
  qtd_recusada: 0,
  prz_med_pond_emp: null,
  prz_med_pond_bco: null,
  float_acordado: 0,
  cst_efetivo_acordado: 0,
  nominal_tax: null,
  recompra: 0,
  retencao: 0,
  fomento: 0,
  outros: 0,
}

export function ReceivableFormPage() {
  const { id } = useParams<{ id: string }>()
  const editando = Boolean(id && id !== 'novo')
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const estreito = useMobile()

  const [valores, setValores] = useState<FormState>(VAZIO)
  const [tarifas, setTarifas] = useState<TaxRow[]>([])
  const [carregado, setCarregado] = useState(false)

  // **FE-400 — o ponto de restauração.** Descartar é voltar a ISTO, em memória.
  // No legado o `cancel()` da barra inferior montava `{ reload: defaultReload() }`
  // — com os parênteses —, então a recarga da página **executava na hora de
  // montar o objeto**, antes de qualquer confirmação. Aqui não há recarga
  // nenhuma: o formulário volta ao estado inicial e a tela continua de pé.
  const inicial = useRef<{ valores: FormState; tarifas: TaxRow[] }>({ valores: VAZIO, tarifas: [] })
  const [descartando, setDescartando] = useState(false)

  useEffect(() => {
    document.title = editando ? 'Safegold - Editar borderô' : 'Safegold - Novo borderô'
  }, [editando])

  // --- Catálogos ---------------------------------------------------------
  const empresas = useQuery({ queryKey: ['companies', 'form'], queryFn: () => companiesApi.list({ perPage: 100 }) })
  const portadores = useQuery({
    // **Um critério só** para o portador oferecível: a conexão do projeto — o
    // mesmo que o servidor aplica. Ter dois critérios foi o que fez a tela do
    // legado oferecer portador que o servidor recusava.
    queryKey: ['carrier-connections', 'form'],
    queryFn: () => carrierConnectionsApi.list({ perPage: 100 }),
  })
  const carteiras = useQuery({ queryKey: ['wallets', 'form'], queryFn: () => walletsApi.list({ perPage: 100 }) })
  const tipos = useQuery({
    queryKey: ['receivable-kinds', 'form'],
    queryFn: () => receivableKindsApi.list({ perPage: 100 }),
  })
  // **A fonte de recurso é obrigatória no servidor.** O campo estava faltando e
  // o Salvar respondia 422 — apareceu dirigindo o formulário pela tela, não em
  // teste: `tsc` e `rspec` passavam com o formulário impossível de enviar.
  const fontes = useQuery({
    queryKey: ['resource-sources', 'form'],
    queryFn: () => resourceSourcesApi.list({ perPage: 100 }),
  })
  const tiposDeTarifa = useQuery({
    queryKey: ['movement-kinds', 'form'],
    // Só os `is_operation` — é o único dos flags de exibição do legado que tem
    // leitor.
    queryFn: () => movementKindsApi.list({ perPage: 100 }),
  })
  const ajuda = useQuery({ queryKey: ['receivable-help-texts'], queryFn: () => receivablesApi.helpTexts() })

  const registro = useQuery({
    queryKey: ['receivable', id],
    queryFn: () => receivablesApi.get(id!),
    enabled: editando,
  })

  // Carrega o registro no formulário **uma vez**: sobrescrever a cada refetch
  // apagaria o que o usuário digitou enquanto a prévia rodava.
  useEffect(() => {
    if (!editando || !registro.data || carregado) return
    const r = registro.data
    const carregadoDoRegistro: FormState = {
      date: dataDe(r.date),
      data_credito: dataDe(r.data_credito),
      nro_bordero: r.nro_bordero ?? '',
      description: r.description ?? '',
      observacoes: r.observacoes ?? '',
      company_id: r.company_id,
      carrier_id: r.carrier_id,
      wallet_id: r.wallet_id,
      receivable_kind_id: r.receivable_kind_id,
      resource_source_id: r.resource_source_id,
      valor_bruto: num(r.valor_bruto),
      vlr_bruto_recusado: num(r.vlr_bruto_recusado),
      qtd_titulos: r.qtd_titulos,
      qtd_recusada: r.qtd_recusada,
      prz_med_pond_emp: num(r.prz_med_pond_emp),
      prz_med_pond_bco: num(r.prz_med_pond_bco),
      float_acordado: num(r.float_acordado),
      cst_efetivo_acordado: num(r.cst_efetivo_acordado),
      nominal_tax: num(r.nominal_tax),
      recompra: num(r.recompra),
      retencao: num(r.retencao),
      fomento: num(r.fomento),
      outros: num(r.outros),
    }
    setValores(carregadoDoRegistro)
    const tarifasDoRegistro = r.taxes.map((t) => ({
      chave: t.id,
      id: t.id,
      movement_kind_id: t.movement_kind_id,
      value: num(t.value),
    }))
    setTarifas(tarifasDoRegistro)
    // O ponto de restauração é o registro COMO VEIO do servidor — não o
    // `VAZIO`. Sem isto, "Descartar" numa edição limparia o borderô inteiro em
    // vez de desfazer o que foi mexido agora.
    inicial.current = { valores: carregadoDoRegistro, tarifas: tarifasDoRegistro }
    setCarregado(true)
  }, [editando, registro.data, carregado])

  // A prévia. Só as tarifas **não removidas** entram — a linha marcada para
  // remoção não pode continuar somando enquanto o usuário decide (DEC-72).
  const previa = useReceivablePreview({
    valor_bruto: valores.valor_bruto,
    vlr_bruto_recusado: valores.vlr_bruto_recusado,
    qtd_titulos: valores.qtd_titulos,
    qtd_recusada: valores.qtd_recusada,
    prz_med_pond_emp: valores.prz_med_pond_emp,
    prz_med_pond_bco: valores.prz_med_pond_bco,
    float_acordado: valores.float_acordado,
    cst_efetivo_acordado: valores.cst_efetivo_acordado,
    recompra: valores.recompra,
    retencao: valores.retencao,
    fomento: valores.fomento,
    outros: valores.outros,
    date: valores.date ? iso(valores.date) : null,
    taxes: tarifas.filter((t) => !t.removida).map((t) => ({ movement_kind_id: t.movement_kind_id, value: t.value })),
  })

  const salvar = useMutation({
    mutationFn: (payload: ReceivablePayload) =>
      editando ? receivablesApi.update(id!, payload) : receivablesApi.create(payload),
    onSuccess: (registro: ReceivableEntry) => {
      // A mensagem distingue cadastro de edição. No legado a tela dizia "foi
      // cadastrado" nas duas.
      notify.success(editando ? 'Borderô atualizado.' : 'Borderô cadastrado.')
      queryClient.invalidateQueries({ queryKey: ['receivables'] })
      queryClient.invalidateQueries({ queryKey: ['receivables-summary'] })
      queryClient.invalidateQueries({ queryKey: ['receivable', registro.id] })
      navigate('/receivables')
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível salvar o borderô.')),
  })

  // --- FE-400: estado sujo, descarte e aviso de saída ---------------------
  //
  // A comparação é por **serialização**, e não campo a campo: o formulário tem
  // 22 campos mais a lista de tarifas, e uma comparação escrita à mão passaria a
  // mentir na primeira vez que alguém acrescentasse um campo e esquecesse a
  // linha. As datas viram ISO para não comparar duas instâncias de `Date` por
  // identidade — que nunca são iguais.
  const impressao = useCallback(
    (v: FormState, t: TaxRow[]) =>
      JSON.stringify({
        ...v,
        date: v.date ? iso(v.date) : null,
        data_credito: v.data_credito ? iso(v.data_credito) : null,
        // `chave` é identidade de linha na tela, não dado: incluí-la faria
        // "remover e recriar a mesma tarifa" contar como alteração.
        tarifas: t.map((x) => ({ id: x.id ?? null, movement_kind_id: x.movement_kind_id, value: x.value, removida: Boolean(x.removida) })),
      }),
    [],
  )

  const alterado =
    impressao(valores, tarifas) !== impressao(inicial.current.valores, inicial.current.tarifas)

  // Só o `alterado` arma o aviso. Um formulário intocado tem que deixar sair
  // sem perguntar nada — perguntar sempre é o jeito de a pessoa aprender a
  // clicar "sim" sem ler, e aí o aviso deixa de proteger no dia em que importa.
  const saida = useUnsavedChanges(alterado)

  // **Descartar não recarrega.** Restaura o ponto e fica na tela — é a correção
  // do `cancel()` do legado, e é também o que o cenário "Descartar alterações"
  // da FE-400 exige: "as alterações são desfeitas na interface e a barra some,
  // sem recarregar a página inteira".
  function descartar() {
    setValores(inicial.current.valores)
    setTarifas(inicial.current.tarifas)
    salvar.reset()
    setDescartando(false)
  }

  // "Cancelar" sai da tela. Com alteração pendente, pergunta antes — no legado
  // a saída era silenciosa.
  function sair() {
    saida.interceptar(() => navigate('/receivables'))
  }

  function set<K extends keyof FormState>(campo: K, valor: FormState[K]) {
    setValores((v) => ({ ...v, [campo]: valor }))
  }

  function textoDeAjuda(campo: string): string | undefined {
    // Campo sem chave **não exibe** indicador de ajuda. O conteúdo do legado é
    // integralmente placeholder ("Só um teste de informações do campo…"),
    // então hoje nenhum campo tem — e a tela não desenha um ícone que abriria
    // um balão vazio (Q-B20 / OPS-154).
    return ajuda.data?.[campo] || undefined
  }

  // --- Os bloqueios, com a razão -----------------------------------------
  const escopo = projectScopeCode(registro.error ?? empresas.error ?? portadores.error)

  const cabecalho = (
    <PageHeader
      title={editando ? 'Editar borderô' : 'Novo borderô'}
      subtitle="Os valores calculados aparecem à direita e vêm do servidor — a tela não refaz a conta."
      rightSlot={
        <Button variant="ghost" onClick={sair}>
          <ArrowLeft aria-hidden="true" className="h-4 w-4" />
          Voltar à lista
        </Button>
      }
    />
  )

  if (escopo) {
    return (
      <div className="pb-10">
        {cabecalho}
        <ProjectScopeState code={escopo} recurso="os recebíveis" />
      </div>
    )
  }

  if (editando && registro.isLoading) {
    return (
      <div className="pb-10">
        {cabecalho}
        <LoadingState label="Carregando borderô…" />
      </div>
    )
  }

  if (editando && registro.isError) {
    return (
      <div className="pb-10">
        {cabecalho}
        <ErrorState
          title="Não foi possível carregar o borderô"
          description={mensagemDoServidor(registro.error, 'Tente novamente.')}
          onRetry={() => registro.refetch()}
        />
      </div>
    )
  }

  const semPortador = portadores.isSuccess && (portadores.data?.items.length ?? 0) === 0
  const semEmpresa = empresas.isSuccess && (empresas.data?.items.length ?? 0) === 0

  // **FE-166 / FE-167 — o formulário é suprimido COM A RAZÃO**, e o atalho
  // funciona também na edição (no legado a URL era montada com uma variável
  // indefinida e o link não ia a lugar nenhum).
  if (semPortador || semEmpresa) {
    return (
      <div className="pb-10">
        {cabecalho}
        {/*
          S2 / 2.9 — o destino é `/project-carrier-connections`, que é o `path`
          declarado em `consoleNavigation.tsx` para o item
          `project_to_carrier_connections`. Estava `/project-carriers`, que não
          existe: caía na rota curinga e o atalho do estado vazio levava à tela
          de "não encontrado" — o MESMO defeito que o comentário acima diz ter
          sido corrigido do legado, reintroduzido por um endereço escrito de
          cabeça. Achado conferindo a 2.9 rota por rota.
        */}
        {semPortador ? (
          <EmptyState
            icon={<Landmark aria-hidden="true" className="h-5 w-5 text-muted-foreground" />}
            title="Este projeto ainda não tem nenhum portador conectado"
            description="O borderô precisa de um portador, e só os portadores conectados a este projeto podem ser escolhidos. Conecte o primeiro para poder lançar."
            action={<Button onClick={() => navigate('/project-carrier-connections')}>Conectar portadores</Button>}
          />
        ) : (
          <EmptyState
            icon={<Building2 aria-hidden="true" className="h-5 w-5 text-muted-foreground" />}
            title="Este projeto ainda não tem nenhuma empresa"
            description="O borderô é lançado no nome de uma empresa do projeto. Cadastre a primeira para poder lançar."
            action={<Button onClick={() => navigate('/companies')}>Cadastrar empresa</Button>}
          />
        )}
      </div>
    )
  }

  const opcoesEmpresa = (empresas.data?.items ?? []).map((c) => ({ value: c.id, label: c.title }))
  const opcoesPortador = (portadores.data?.items ?? []).map((c) => ({
    value: c.carrier_id,
    label: c.carrier_title ?? c.carrier_id,
  }))
  const opcoesCarteira = (carteiras.data?.items ?? []).map((w) => ({ value: w.id, label: w.title }))
  const opcoesTipo = (tipos.data?.items ?? []).map((k) => ({ value: k.id, label: k.title }))
  const opcoesFonte = (fontes.data?.items ?? []).map((f) => ({ value: f.id, label: f.title }))

  // **As cinco condições que travam o Salvar.** As mesmas cinco fazem o
  // servidor responder 422, pelo mesmo motivo (FE-172 / D-10) — a tela é
  // conveniência, o servidor é a defesa.
  const faltando: string[] = []
  if (!valores.date) faltando.push('a data')
  if (!valores.company_id) faltando.push('a empresa')
  if (!valores.carrier_id) faltando.push('o portador')
  if (!valores.wallet_id) faltando.push('a carteira')
  if (!valores.receivable_kind_id) faltando.push('o tipo de recebível')
  if (!valores.resource_source_id) faltando.push('a fonte de recurso')
  if (valores.valor_bruto === null) faltando.push('o valor bruto')
  if (valores.qtd_titulos === null) faltando.push('a quantidade de títulos')
  if ((valores.prz_med_pond_emp ?? 0) <= 0) faltando.push('o prazo médio da empresa (maior que zero)')
  if ((valores.prz_med_pond_bco ?? 0) <= 0) faltando.push('o prazo médio do banco (maior que zero)')
  if (tarifas.some((t) => !t.removida && !t.movement_kind_id)) faltando.push('o tipo de cada tarifa')

  const podeSalvar = faltando.length === 0 && previa.problema === null && !salvar.isPending

  function enviar() {
    if (!podeSalvar) return
    const payload: ReceivablePayload = {
      date: iso(valores.date!),
      company_id: valores.company_id,
      carrier_id: valores.carrier_id,
      wallet_id: valores.wallet_id,
      receivable_kind_id: valores.receivable_kind_id,
      resource_source_id: valores.resource_source_id,
      valor_bruto: valores.valor_bruto,
      qtd_titulos: valores.qtd_titulos,
      prz_med_pond_emp: valores.prz_med_pond_emp,
      prz_med_pond_bco: valores.prz_med_pond_bco,
      vlr_bruto_recusado: valores.vlr_bruto_recusado ?? 0,
      qtd_recusada: valores.qtd_recusada ?? 0,
      float_acordado: valores.float_acordado ?? 0,
      cst_efetivo_acordado: valores.cst_efetivo_acordado ?? 0,
      recompra: valores.recompra ?? 0,
      retencao: valores.retencao ?? 0,
      fomento: valores.fomento ?? 0,
      outros: valores.outros ?? 0,
      nominal_tax: valores.nominal_tax,
      data_credito: valores.data_credito ? iso(valores.data_credito) : null,
      nro_bordero: valores.nro_bordero || null,
      description: valores.description || null,
      observacoes: valores.observacoes || null,
      // A lista **completa** do que deve ficar. O que foi marcado para remoção
      // simplesmente não vai — e o servidor apaga na mesma transação (DEC-72).
      taxes: tarifas
        .filter((t) => !t.removida && t.movement_kind_id)
        .map((t) => ({ id: t.id, movement_kind_id: t.movement_kind_id, value: t.value })),
    }
    salvar.mutate(payload)
  }

  const campos = (
    <div className="space-y-4">
      <Card className="space-y-4 p-4">
        <h3 className="font-title text-sm font-semibold text-foreground">Identificação</h3>
        <div className="grid gap-4 sm:grid-cols-2">
          {/*
            **FE-177 — a restrição mútua das duas datas.**

            Regra do legado, lida linha a linha em
            `receivables/new/_body.js.erb:74-106`: escolher a data do borderô
            define o `minDate` do seletor de CRÉDITO, e escolher a de crédito
            define o `maxDate` do seletor do BORDERÔ. Ou seja **o crédito nunca
            é anterior ao borderô**, e a trava vale nos dois sentidos.

            A migração trouxe os dois campos sem `min` nem `max` — o componente
            aceita os dois e ninguém passava. Sem isso, um crédito anterior ao
            borderô entra: nenhum dos dois lados valida a combinação, nem o
            legado validava. A defesa sempre foi só a tela, e ela tinha sumido.
          */}
          <Campo id="date" rotulo="Data do borderô" ajuda={textoDeAjuda('date')}>
            <DatePicker
              id="date"
              value={valores.date}
              max={valores.data_credito}
              onChange={(d) => set('date', d)}
            />
          </Campo>
          <Campo
            id="nro_bordero"
            rotulo="Nº do borderô"
            ajuda={textoDeAjuda('nro_bordero')}
            dica="Texto livre: pode ter letras, barras e traços. Zeros à esquerda são preservados."
          >
            <Input
              id="nro_bordero"
              value={valores.nro_bordero}
              onChange={(e) => set('nro_bordero', e.target.value)}
              placeholder="Ex.: F-76, 48-49, 1540962/20"
            />
          </Campo>
          <Campo id="data_credito" rotulo="Data de crédito" ajuda={textoDeAjuda('data_credito')}>
            <DatePicker
              id="data_credito"
              value={valores.data_credito}
              min={valores.date}
              clearable
              onChange={(d) => set('data_credito', d)}
            />
          </Campo>
        </div>
      </Card>

      <Card className="space-y-4 p-4">
        <h3 className="font-title text-sm font-semibold text-foreground">Partes e classificação</h3>
        <div className="grid gap-4 sm:grid-cols-2">
          <Campo id="company_id" rotulo="Empresa" ajuda={textoDeAjuda('company_id')}>
            <Select
              id="company_id"
              value={valores.company_id || null}
              onChange={(v) => set('company_id', v)}
              placeholder="Escolha a empresa…"
              options={opcoesEmpresa}
            />
          </Campo>
          <Campo
            id="carrier_id"
            rotulo="Portador"
            ajuda={textoDeAjuda('carrier_id')}
            dica="Só os portadores conectados a este projeto aparecem — é o mesmo critério que o servidor aplica."
          >
            <Select
              id="carrier_id"
              value={valores.carrier_id || null}
              onChange={(v) => set('carrier_id', v)}
              placeholder="Escolha o portador…"
              options={opcoesPortador}
            />
          </Campo>
          <Campo id="wallet_id" rotulo="Carteira" ajuda={textoDeAjuda('wallet_id')}>
            <Select
              id="wallet_id"
              value={valores.wallet_id || null}
              onChange={(v) => set('wallet_id', v)}
              placeholder="Escolha a carteira…"
              options={opcoesCarteira}
            />
          </Campo>
          <Campo id="receivable_kind_id" rotulo="Tipo de recebível" ajuda={textoDeAjuda('receivable_kind_id')}>
            <Select
              id="receivable_kind_id"
              value={valores.receivable_kind_id || null}
              onChange={(v) => set('receivable_kind_id', v)}
              placeholder="Escolha o tipo…"
              options={opcoesTipo}
            />
          </Campo>
          <Campo
            id="resource_source_id"
            rotulo="Fonte de recurso"
            ajuda={textoDeAjuda('resource_source_id')}
            dica="De onde sai o dinheiro da operação. Obrigatório — o servidor recusa o borderô sem ele."
          >
            <Select
              id="resource_source_id"
              value={valores.resource_source_id || null}
              onChange={(v) => set('resource_source_id', v)}
              placeholder="Escolha a fonte…"
              options={opcoesFonte}
            />
          </Campo>
        </div>
      </Card>

      <Card className="space-y-4 p-4">
        <h3 className="font-title text-sm font-semibold text-foreground">Valores e prazos</h3>
        <div className="grid gap-4 sm:grid-cols-2">
          <Campo id="valor_bruto" rotulo="Valor bruto" ajuda={textoDeAjuda('valor_bruto')}>
            <MoneyInput id="valor_bruto" value={valores.valor_bruto} onChange={(v) => set('valor_bruto', v)} />
          </Campo>
          <Campo id="vlr_bruto_recusado" rotulo="Valor bruto recusado" ajuda={textoDeAjuda('vlr_bruto_recusado')}>
            <MoneyInput
              id="vlr_bruto_recusado"
              value={valores.vlr_bruto_recusado}
              onChange={(v) => set('vlr_bruto_recusado', v)}
            />
          </Campo>
          <Campo id="qtd_titulos" rotulo="Quantidade de títulos" ajuda={textoDeAjuda('qtd_titulos')}>
            <Input
              id="qtd_titulos"
              inputMode="numeric"
              value={valores.qtd_titulos ?? ''}
              // Só dígitos: a quantidade é inteira, e no legado o exemplo
              // "Ex: 789" contradizia o comportamento do campo.
              onChange={(e) => set('qtd_titulos', inteiro(e.target.value))}
              placeholder="0"
            />
          </Campo>
          <Campo id="qtd_recusada" rotulo="Quantidade recusada" ajuda={textoDeAjuda('qtd_recusada')}>
            <Input
              id="qtd_recusada"
              inputMode="numeric"
              value={valores.qtd_recusada ?? ''}
              onChange={(e) => set('qtd_recusada', inteiro(e.target.value))}
              placeholder="0"
            />
          </Campo>
          <Campo
            id="prz_med_pond_emp"
            rotulo="Prazo médio ponderado — empresa (dias)"
            ajuda={textoDeAjuda('prz_med_pond_emp')}
            dica="Precisa ser maior que zero: ele divide seis fórmulas do custo efetivo."
          >
            <NumericInput
              id="prz_med_pond_emp"
              kind="decimal"
              casas={2}
              value={valores.prz_med_pond_emp}
              onChange={(v) => set('prz_med_pond_emp', v)}
            />
          </Campo>
          <Campo
            id="prz_med_pond_bco"
            rotulo="Prazo médio ponderado — banco (dias)"
            ajuda={textoDeAjuda('prz_med_pond_bco')}
            dica="Precisa ser maior que zero."
          >
            <NumericInput
              id="prz_med_pond_bco"
              kind="decimal"
              casas={2}
              value={valores.prz_med_pond_bco}
              onChange={(v) => set('prz_med_pond_bco', v)}
            />
          </Campo>
          <Campo id="float_acordado" rotulo="Float acordado (dias)" ajuda={textoDeAjuda('float_acordado')}>
            <NumericInput
              id="float_acordado"
              kind="decimal"
              casas={2}
              value={valores.float_acordado}
              onChange={(v) => set('float_acordado', v)}
            />
          </Campo>
          <Campo
            id="cst_efetivo_acordado"
            rotulo="Custo efetivo acordado (% a.m.)"
            ajuda={textoDeAjuda('cst_efetivo_acordado')}
          >
            <NumericInput
              id="cst_efetivo_acordado"
              kind="percent"
              value={valores.cst_efetivo_acordado}
              onChange={(v) => set('cst_efetivo_acordado', v)}
            />
          </Campo>
          <Campo
            id="nominal_tax"
            rotulo="Taxa nominal (% a.m.)"
            ajuda={textoDeAjuda('nominal_tax')}
            dica="Informativa: NÃO é conferida contra a taxa apurada no painel — é o comportamento do legado, preservado."
          >
            <NumericInput
              id="nominal_tax"
              kind="percent"
              value={valores.nominal_tax}
              onChange={(v) => set('nominal_tax', v)}
            />
          </Campo>
        </div>
      </Card>

      <Card className="space-y-4 p-4">
        <h3 className="font-title text-sm font-semibold text-foreground">Deduções</h3>
        <div className="grid gap-4 sm:grid-cols-2">
          <Campo id="recompra" rotulo="Recompra" ajuda={textoDeAjuda('recompra')}>
            <MoneyInput id="recompra" value={valores.recompra} onChange={(v) => set('recompra', v)} />
          </Campo>
          <Campo id="retencao" rotulo="Retenção" ajuda={textoDeAjuda('retencao')}>
            <MoneyInput id="retencao" value={valores.retencao} onChange={(v) => set('retencao', v)} />
          </Campo>
          <Campo id="fomento" rotulo="Fomento" ajuda={textoDeAjuda('fomento')}>
            <MoneyInput id="fomento" value={valores.fomento} onChange={(v) => set('fomento', v)} />
          </Campo>
          <Campo id="outros" rotulo="Outros" ajuda={textoDeAjuda('outros')}>
            <MoneyInput id="outros" value={valores.outros} onChange={(v) => set('outros', v)} />
          </Campo>
        </div>
      </Card>

      <Card className="p-4">
        <TaxRows rows={tarifas} kinds={tiposDeTarifa.data?.items ?? []} onChange={setTarifas} />
      </Card>

      <Card className="space-y-4 p-4">
        <h3 className="font-title text-sm font-semibold text-foreground">Anotações</h3>
        <Campo id="description" rotulo="Descrição" ajuda={textoDeAjuda('description')} dica="Aparece na lista.">
          <Input
            id="description"
            value={valores.description}
            onChange={(e) => set('description', e.target.value)}
            placeholder="Um resumo curto do lançamento"
          />
        </Campo>
        {/* **DEC-52** — o campo passa a ter tela. A coluna existe desde 2021,
            está no `permit` do legado, tem tooltip órfão no YAML de ajuda e
            **nenhuma view a lê**. O único escritor real era o importador: há
            379 textos de negócio em produção que ninguém nunca viu. */}
        <Campo
          id="observacoes"
          rotulo="Observações"
          ajuda={textoDeAjuda('observacoes')}
          dica="Texto longo, para o histórico do lançamento."
        >
          <Textarea
            id="observacoes"
            rows={3}
            value={valores.observacoes}
            onChange={(e) => set('observacoes', e.target.value)}
          />
        </Campo>
      </Card>
    </div>
  )

  return (
    // O respiro da barra de ações. No telefone ela ficou ACIMA da
    // `MobileBottomBar` (4.25rem), então o `pb-28` do desktop não bastava: o
    // campo "Observações" nascia por baixo dela. `pb-44` = 11rem cobre a barra
    // de ações (~4.5rem com a lista recolhida) mais as abas.
    <div className="pb-44 md:pb-28">
      {cabecalho}

      <div className={estreito ? 'space-y-4' : 'grid grid-cols-[minmax(0,1fr)_22rem] gap-4 items-start'}>
        {campos}
        <aside className={estreito ? '' : 'sticky top-4'}>
          <h3 className="mb-2 font-title text-sm font-semibold text-foreground">
            Cálculo
            <span className="ml-2 text-xs font-normal text-muted-foreground">calculado pelo servidor</span>
          </h3>
          <CalculationPanel
            derived={previa.derived}
            loading={previa.loading}
            refreshing={previa.refreshing}
            problema={previa.problema}
            incompleto={previa.incompleto}
          />
        </aside>
      </div>

      {/* A barra inferior é a `FormActionBar` da biblioteca — a mesma que o
          formulário de operação estruturada usa (S8). Ela existe porque o
          legado, nas duas telas, removia a ação de salvar **sem mensagem**
          quando um obrigatório ficava vazio; por isso ela EXIGE a lista de
          pendências. Grava uma vez: o botão desabilita enquanto a mutação está
          em voo. */}
      <FormActionBar
        alterado={alterado}
        // **A falha fica na barra**, não só no `toast`. O cenário "Falha ao
        // salvar" da FE-400 exige que a pendência volte COM O MOTIVO e que os
        // controles voltem a ser acionáveis — e um aviso que some em 4 s leva o
        // motivo junto. O `salvar.reset()` de `descartar()` é o que o limpa.
        erro={salvar.isError ? mensagemDoServidor(salvar.error, 'Não foi possível salvar o borderô.') : undefined}
        pendencias={faltando}
        resumo={
          previa.derived ? (
            <span>
              <span className="text-muted-foreground">Líquido </span>
              <span className="font-numeric tabular-nums text-base font-semibold text-foreground">
                {formatMoney(num(previa.derived.valor_liquido))}
              </span>
            </span>
          ) : (
            <span className="text-muted-foreground">Calculando…</span>
          )
        }
      >
        {/* **Descartar** só existe quando há o que descartar. Ele desfaz na
            tela e NÃO recarrega — é a correção do `cancel()` do legado. No
            telefone o rótulo some e fica o ícone: em 390 px, três botões com
            texto quebram a barra em duas linhas e empurram o Salvar para fora
            do alcance do polegar (DEC-100). */}
        {alterado && (
          <Button
            variant="ghost"
            onClick={() => setDescartando(true)}
            disabled={salvar.isPending}
            aria-label="Descartar alterações"
          >
            <Undo2 aria-hidden="true" className="h-4 w-4 sm:mr-2" />
            <span className="hidden sm:inline">Descartar</span>
          </Button>
        )}
        <Button variant="ghost" onClick={sair} disabled={salvar.isPending}>
          Cancelar
        </Button>
        <Tooltip content={podeSalvar ? '' : `Falta preencher: ${faltando.join(', ')}`}>
          <span>
            <Button onClick={enviar} disabled={!podeSalvar}>
              {salvar.isPending ? 'Salvando…' : editando ? 'Salvar alterações' : 'Cadastrar borderô'}
            </Button>
          </span>
        </Tooltip>
      </FormActionBar>

      {/* FE-400 — descartar o que foi digitado é destrutivo e pede confirmação. */}
      <ConfirmDialog
        open={descartando}
        onOpenChange={setDescartando}
        title="Descartar as alterações?"
        description={
          editando
            ? 'O borderô volta a como estava quando você abriu. O que já foi salvo não é afetado.'
            : 'O formulário volta a ficar em branco. Nada foi salvo ainda.'
        }
        confirmLabel="Descartar"
        onConfirm={descartar}
      />

      {/* FE-400 — sair com alteração pendente. No legado o `go()` do console
          fechava a gaveta e descartava tudo sem perguntar. */}
      <ConfirmDialog
        open={saida.perguntando}
        onOpenChange={(aberto) => !aberto && saida.cancelar()}
        title="Sair sem salvar?"
        description="Este borderô tem alterações que ainda não foram salvas. Se você sair agora, elas se perdem."
        confirmLabel="Sair sem salvar"
        cancelLabel="Continuar editando"
        onConfirm={saida.confirmar}
      />
    </div>
  )
}

function Campo({
  id,
  rotulo,
  ajuda,
  dica,
  children,
}: {
  id: string
  rotulo: string
  ajuda?: string
  dica?: string
  children: React.ReactNode
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={id}>
        {rotulo}
        {/* Indicador de ajuda **só quando há texto** (OPS-154). Um ícone que
            abre um balão vazio é pior do que nenhum ícone. */}
        {ajuda && (
          <Tooltip content={ajuda}>
            <span className="ml-1 cursor-help text-xs text-muted-foreground">(?)</span>
          </Tooltip>
        )}
      </Label>
      {children}
      {dica && <p className="text-xs text-muted-foreground">{dica}</p>}
    </div>
  )
}

function num(v: string | number | null | undefined): number | null {
  if (v === null || v === undefined || v === '') return null
  const n = typeof v === 'number' ? v : Number(v)
  return Number.isFinite(n) ? n : null
}

function inteiro(texto: string): number | null {
  const so = texto.replace(/\D/g, '')
  return so === '' ? null : Number(so)
}

function dataDe(iso: string | null | undefined): Date | null {
  if (!iso) return null
  const [a, m, d] = iso.slice(0, 10).split('-').map(Number)
  return a && m && d ? new Date(a, m - 1, d) : null
}

function iso(d: Date): string {
  const mes = String(d.getMonth() + 1).padStart(2, '0')
  const dia = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${mes}-${dia}`
}
