import { lazy, type LazyExoticComponent, type ComponentType } from 'react'
import {
  LayoutGrid,
  Scale,
  FolderKanban,
  Globe,
  ShieldCheck,
  Plug,
  UserCircle,
  HelpCircle,
  Users as UsersIcon,
  Image as ImageIcon,
  Zap,
  Key,
  MessageSquare,
  Smartphone,
  History,
  ShieldAlert,
  CalendarRange,
  Receipt,
  RefreshCcw,
  Gauge,
  Layers3,
  Boxes,
  Building2,
  Truck,
  Landmark,
  SlidersHorizontal,
  Coins,
  Wallet,
  Users2,
  Network,
  BadgeCheck,
  Tags,
  Tag,
  ArrowLeftRight,
  FileStack,
  PackageSearch,
  Blocks,
  ShieldQuestion,
  BookOpen,
  LifeBuoy,
  ScrollText,
  type LucideIcon,
} from 'lucide-react'
import type { SidebarMode } from '@/store/sidebarModeStore'

/**
 * O MENU É O DOCUMENTO DE REQUISITOS DA NAVEGAÇÃO (D-118).
 *
 * No legado a navegação inteira vivia num helper de view —
 * `create_console_menu` (`../sfg/app/helpers/application_helper.rb:100-172`) —
 * que montava 6 grupos com `if current_user.og? || …` espalhados no meio. Era, na
 * prática, a maior regra de autorização de interface do produto, escrita onde
 * ninguém procura e impossível de testar.
 *
 * Aqui ela é **dado**: cada área declara o seu papel, o seu gate de projeto e a
 * sua rota. `useNavItems` aplica o filtro; `App.tsx` monta as rotas a partir da
 * MESMA lista. Um papel novo muda o menu sem tocar em componente nenhum
 * (tarefa F.1), e não existe caminho em que o menu mostre uma área cuja rota não
 * está montada — porque é o mesmo registro.
 *
 * ### Como acrescentar a sua área (fatias S3..S19)
 *
 * Ache a linha da sua área abaixo e troque `element: null` por
 * `element: lazy(() => import('@/app/pages/SuaPage').then(m => ({ default: m.SuaPage })))`.
 * A rota passa a existir e o item de menu acende no mesmo commit. Rotas de
 * detalhe/edição entram em `children`. **Não** acrescente `<Route>` solto em
 * `App.tsx` para uma área que já está aqui: as duas listas divergiriam, que é
 * exatamente o que este arquivo existe para impedir.
 *
 * ### As três regras de porte (design.md §2)
 *
 * 1. **`locked` é lido DO ITEM, nunca do grupo.** No legado a view lia
 *    `g[:locked]` do grupo (`_container.html.erb:24`) enquanto a flag era escrita
 *    no item — por isso os 4 itens marcados **nunca ficaram travados** (D-90).
 *    O mecanismo é portado corrigido; o **efeito** é preservado: **NENHUM item
 *    nasce `locked`** (DEC-15.1 — disponibilidades e cobranças estão vivas em
 *    produção). Se você veio "consertar" marcando os quatro, pare: o teste
 *    `useNavItems.test` reprova, e a decisão está escrita.
 * 2. **O filtro é papel + participação**, com os mesmos dados do servidor
 *    (C3 + C1). O menu esconde a **tela de administração** do catálogo, nunca o
 *    **dado** do catálogo — por isso o Colaborador não vê "Cadastro" mas os
 *    dropdowns dele continuam populados (DEC-18.4).
 * 3. **`requiresProject` é o gate `projects.count > 0`** do legado: o console sem
 *    participação mostra menos coisas.
 */

export type RoleSlug = 'og' | 'admin' | 'gerente' | 'colaborador'

/** Todos os papéis, na ordem de hierarquia do ai9 (menor = mais poder, DEC-41). */
export const ALL_ROLES: RoleSlug[] = ['og', 'admin', 'gerente', 'colaborador']

type PageComponent = LazyExoticComponent<ComponentType<any>>

export interface AreaChildRoute {
  /** Caminho RELATIVO à área (`':id'`, `'new'`, `':id/edit'`). */
  path: string
  element: PageComponent
}

export interface NavItem {
  /** `identifier` do `create_console_menu`. É o que amarra a linha ao ledger. */
  id: string
  /** Rota absoluta, em inglês e kebab-case (§8 das convenções). */
  path: string
  label: string
  icon: LucideIcon
  /** Chave do recurso na `Authorization::Matrix` do servidor. */
  resource: string
  /** Papéis que enxergam o item. Ausente = todos os papéis. */
  roles?: RoleSlug[]
  /** Gate `projects.count > 0` do legado. */
  requiresProject?: boolean
  /**
   * D-90 / DEC-15.1. Item visível porém desabilitado. **Nasce sempre `false`.**
   * O campo existe para que travar uma área seja um dado, não um `if` novo.
   */
  locked?: boolean
  /**
   * DEC-58 / P-090 — o **mecanismo de item inativo** do legado
   * (`_container.html.erb:24`, `'inactive' if i[:identifier] == "reports"`).
   * Portado sem consumidor: no legado nenhum item tinha `identifier: "reports"`,
   * então a condição **nunca foi verdadeira** e o item nunca existiu. Fica aqui
   * como campo para que uma área possa ser anunciada e desligada sem `if` novo.
   * **Nenhum item nasce marcado** — o QA não deve abrir defeito por estar sem uso.
   */
  inactive?: boolean
  /**
   * A página da área. `null` = a fatia dona ainda não entregou; a rota não é
   * montada e o item não aparece no menu.
   */
  element: PageComponent | null
  /** Rotas de detalhe/edição da área. */
  children?: AreaChildRoute[]
  /** Fatia dona da tela. Só documentação — nada lê em runtime. */
  slice?: string
}

export interface NavGroup {
  id: string
  title: string
  icon: LucideIcon
  /** Destino quando o grupo não tem itens — o `independent_group_menu_item` do legado. */
  path?: string
  /**
   * Grupo que **por desenho** tem um item só ("Perfil", "Ajuda"): vira link
   * direto em vez de abrir um acordeão de uma linha.
   *
   * É declarado, e não deduzido de `items.length === 1`, de propósito. Deduzir
   * faria "Cadastro" e "Admin" virarem link direto **hoje**, enquanto só uma
   * das telas de cada um está entregue — e o rótulo "Admin" levaria a
   * "Mensagens", que é um menu que mente. Quando as outras fatias chegarem, o
   * comportamento mudaria sozinho, sem ninguém decidir nada.
   */
  linkToSingleItem?: boolean
  roles?: RoleSlug[]
  requiresProject?: boolean
  items: NavItem[]
}

// --- Páginas que já existem na base -----------------------------------------
const DashboardPage = lazy(() => import('@/app/pages/DashboardPage').then(m => ({ default: m.DashboardPage })))
const UsersPage = lazy(() => import('@/app/pages/UsersPage').then(m => ({ default: m.UsersPage })))
// S1 / FE-022..FE-025, FE-513 — o detalhe da conta, com as abas Geral / Projetos /
// Permissões. Entra como rota FILHA de `/users`, no mesmo registro, para que o gate
// de papel da área valha também para o endereço digitado à mão.
const UserDetailPage = lazy(() => import('@/app/pages/users/UserDetailPage').then(m => ({ default: m.UserDetailPage })))
// S1 / FE-026, FE-027 — a tela de permissões por papel (DEC-18.2: OG e Admin).
const PermissionsPage = lazy(() => import('@/app/pages/users/PermissionsPage').then(m => ({ default: m.PermissionsPage })))
const ProfilePage = lazy(() => import('@/app/pages/ProfilePage').then(m => ({ default: m.ProfilePage })))
const CredentialsPage = lazy(() => import('@/app/pages/admin/CredentialsPage').then(m => ({ default: m.CredentialsPage })))
const FlowListPage = lazy(() => import('@/features/chat-builder/FlowListPage').then(m => ({ default: m.FlowListPage })))
const WhatsappPage = lazy(() => import('@/app/pages/WhatsappPage').then(m => ({ default: m.WhatsappPage })))
const MessagesPage = lazy(() => import('@/app/pages/MessagesPage').then(m => ({ default: m.MessagesPage })))
// Entregue pela S19; a rota e o item de menu são desta fatia (o cabeçalho do
// arquivo pede as duas linhas). Sem elas a trilha ficaria construída e
// inalcançável — o mesmo defeito que o legado tinha com `risk_entries` e com a
// área de temas.
const AuditTrailPage = lazy(() => import('@/app/pages/admin/AuditTrailPage').then(m => ({ default: m.AuditTrailPage })))

// --- S12: contratos, ajuda e FAQ ------------------------------------------
// Três áreas que o legado tinha e o menu NÃO listava. A tela de contratos era
// literalmente órfã (sem item de menu, e com o JS lendo um campo de busca que
// não existia no HTML); a de ajuda só era alcançável por URL. Aqui as três
// nascem no mesmo registro que monta a rota — não há como uma existir sem a
// outra.
const ContractsPage = lazy(() => import('@/app/pages/admin/ContractsPage').then(m => ({ default: m.ContractsPage })))
const ContractDetailPage = lazy(() => import('@/app/pages/admin/ContractDetailPage').then(m => ({ default: m.ContractDetailPage })))
const ContractVersionFormPage = lazy(() => import('@/app/pages/admin/ContractVersionFormPage').then(m => ({ default: m.ContractVersionFormPage })))
const HelpCenterPage = lazy(() => import('@/app/pages/admin/HelpCenterPage').then(m => ({ default: m.HelpCenterPage })))
const FaqPage = lazy(() => import('@/app/pages/FaqPage').then(m => ({ default: m.FaqPage })))

// --- S3 — os cinco CATÁLOGOS GLOBAIS ----------------------------------------
// DEC-18.4: o Colaborador NÃO vê estas telas (elas administram o catálogo), mas
// LÊ o dado pela API — por isso os dropdowns dele sobem populados. O menu
// esconde a tela de administração do catálogo, não o dado do catálogo.
const CarriersPage = lazy(() => import('@/app/pages/catalogs/CarriersPage').then(m => ({ default: m.CarriersPage })))
const CarrierDetailPage = lazy(() => import('@/app/pages/catalogs/CarrierDetailPage').then(m => ({ default: m.CarrierDetailPage })))
const CarrierGroupsPage = lazy(() => import('@/app/pages/catalogs/CarrierGroupsPage').then(m => ({ default: m.CarrierGroupsPage })))
const SegmentsPage = lazy(() => import('@/app/pages/catalogs/SegmentsPage').then(m => ({ default: m.SegmentsPage })))
const SubSegmentsPage = lazy(() => import('@/app/pages/catalogs/SubSegmentsPage').then(m => ({ default: m.SubSegmentsPage })))
const GuaranteeTypesPage = lazy(() => import('@/app/pages/catalogs/GuaranteeTypesPage').then(m => ({ default: m.GuaranteeTypesPage })))

// --- S4 — o PROJETO e o que é escopado por ele -------------------------------
// Regra oposta à da S3 e oposta de propósito: aqui o dado é filtrado por
// `current_project!` no servidor, e o item de menu carrega `requiresProject`
// (o gate `projects.count > 0` do legado). Uma tela destas sem projeto corrente
// responde 404 — não devolve o catálogo geral, que era o defeito de
// `providers#search` no legado.
const ProjectsPage = lazy(() => import('@/app/pages/projects/ProjectsPage').then(m => ({ default: m.ProjectsPage })))
const ProjectDetailPage = lazy(() => import('@/app/pages/projects/ProjectDetailPage').then(m => ({ default: m.ProjectDetailPage })))
const CompaniesPage = lazy(() => import('@/app/pages/projects/CompaniesPage').then(m => ({ default: m.CompaniesPage })))
const ProvidersPage = lazy(() => import('@/app/pages/projects/ProvidersPage').then(m => ({ default: m.ProvidersPage })))
const ProjectGuaranteesPage = lazy(() => import('@/app/pages/projects/ProjectGuaranteesPage').then(m => ({ default: m.ProjectGuaranteesPage })))
const CarrierConnectionsPage = lazy(() => import('@/app/pages/projects/CarrierConnectionsPage').then(m => ({ default: m.CarrierConnectionsPage })))
const CompanyDetailPage = lazy(() => import('@/app/pages/projects/CompanyDetailPage').then(m => ({ default: m.CompanyDetailPage })))
const ProviderDetailPage = lazy(() => import('@/app/pages/projects/ProviderDetailPage').then(m => ({ default: m.ProviderDetailPage })))

// --- S9 — RENEGOCIAÇÕES ------------------------------------------------------
// A dívida negociada com um fornecedor: cadastro, previsões (parcelas),
// pagamentos e documentos. Escopada por projeto (C1) — `requiresProject`.
//
// As rotas de formulário e de detalhe entram como FILHAS do mesmo registro, e
// não como `<Route>` solto em `App.tsx`: as duas listas divergiriam, que é
// exatamente o que este arquivo existe para impedir.
const RenegotiationsPage = lazy(() => import('@/app/pages/renegotiations/RenegotiationsPage').then(m => ({ default: m.RenegotiationsPage })))
const RenegotiationFormPage = lazy(() => import('@/app/pages/renegotiations/RenegotiationFormPage').then(m => ({ default: m.RenegotiationFormPage })))
const RenegotiationDetailPage = lazy(() => import('@/app/pages/renegotiations/RenegotiationDetailPage').then(m => ({ default: m.RenegotiationDetailPage })))

// --- S11 — DISPONIBILIDADES --------------------------------------------------
// **As três nascem HABILITADAS** (DEC-15.1). No legado os quatro itens do
// módulo eram marcados `locked: true`, mas a view lia `g[:locked]` — do GRUPO —
// e a marca estava nos ITENS: os quatro nunca ficaram travados (D-90). O usuário
// confirmou que as telas estão em uso, então o efeito observado é o que se
// porta, não a intenção aparente do código.
//
// As duas regras de escopo opostas do C1 convivem aqui, como nos indicadores: o
// **catálogo** (`/availability-templates`) é global e fica em "Cadastro"; o
// **painel** e os **padrões do projeto** são escopados e carregam
// `requiresProject`.
//
// `charges` continua `element: null` de propósito: por **DEC-63 (P-098)** as
// tabelas `charges`/`receipts` e a tela são da **S6**. Desta fatia, o item de
// menu já nasce sem `locked` — ele acende no commit em que a S6 entregar a tela.
const AvailabilityPage = lazy(() => import('@/app/pages/availability/AvailabilityPage').then(m => ({ default: m.AvailabilityPage })))
const ProjectAvailabilitiesPage = lazy(() => import('@/app/pages/availability/ProjectAvailabilitiesPage').then(m => ({ default: m.ProjectAvailabilitiesPage })))
const AvailabilityTemplatesPage = lazy(() => import('@/app/pages/availability/AvailabilityTemplatesPage').then(m => ({ default: m.AvailabilityTemplatesPage })))

// --- S5 — LIMITES DE RISCO e o motor de exposição ----------------------------
// Quatro telas, duas regras opostas: `RiskConsolePage` e `RiskControlsPage` são
// escopadas por projeto (C1) e carregam `requiresProject`; `OperationTypesPage`
// e `MovementTypesPage` administram CATÁLOGOS GLOBAIS e ficam no grupo
// "Cadastro" — o Colaborador não vê as telas e continua LENDO o dado pela API
// (DEC-18.4), que é o que faz o select do formulário de limite subir populado.
const RiskConsolePage = lazy(() => import('@/features/risk/pages/RiskConsolePage').then(m => ({ default: m.RiskConsolePage })))
const RiskControlsPage = lazy(() => import('@/features/risk/pages/RiskControlsPage').then(m => ({ default: m.RiskControlsPage })))
const RiskOperationTypesPage = lazy(() => import('@/features/risk/pages/OperationTypesPage').then(m => ({ default: m.OperationTypesPage })))
const RiskMovementTypesPage = lazy(() => import('@/features/risk/pages/MovementTypesPage').then(m => ({ default: m.MovementTypesPage })))

// --- S7 — OPERAÇÕES DE RISCO -------------------------------------------------
// A lista e o detalhe entram no MESMO registro (o detalhe como `children`), pelo
// motivo de sempre: duas listas de rota divergem. O detalhe usa `?aba=` em vez
// de `history.replaceState` — é a correção do D-92, e é o que dá link para
// "as movimentações desta operação".
const RiskOperationsPage = lazy(() => import('@/features/risk/pages/RiskOperationsPage').then(m => ({ default: m.RiskOperationsPage })))
const RiskOperationDetailPage = lazy(() => import('@/features/risk/pages/RiskOperationDetailPage').then(m => ({ default: m.RiskOperationDetailPage })))

// --- S6 — RECEBÍVEIS, COBRANÇAS e os três catálogos do borderô ---------------
// A mesma divisão da S5, e pelo mesmo motivo: `ReceivablesPage`,
// `ReceivableFormPage` e `ChargesPage` são escopadas por projeto (C1) e carregam
// `requiresProject`; `WalletsPage`, `ReceivableKindsPage` e `MovementKindsPage`
// administram CATÁLOGOS GLOBAIS e ficam no grupo "Cadastro" — o Colaborador não
// vê as telas e continua LENDO o dado pela API (DEC-18.4), que é o que faz os
// selects do formulário de borderô subirem populados.
const ReceivablesPage = lazy(() => import('@/features/receivables/pages/ReceivablesPage').then(m => ({ default: m.ReceivablesPage })))
const ReceivableFormPage = lazy(() => import('@/features/receivables/pages/ReceivableFormPage').then(m => ({ default: m.ReceivableFormPage })))
const ChargesPage = lazy(() => import('@/features/receivables/pages/ChargesPage').then(m => ({ default: m.ChargesPage })))
// S6 / FE-184, FE-185 — a seleção de recibos de uma cobrança. Entregue pela
// **S8**: as tarefas 3.24 e 3.25 estavam bloqueadas porque candidato a recibo
// depende de `Remuneration`, que é da S8.
const ChargeReceiptsPage = lazy(() => import('@/features/receivables/pages/ChargeReceiptsPage').then(m => ({ default: m.ChargeReceiptsPage })))
const ChargeDetailPage = lazy(() => import('@/features/receivables/pages/ChargeDetailPage').then(m => ({ default: m.ChargeDetailPage })))
const WalletsPage = lazy(() => import('@/app/pages/catalogs/WalletsPage').then(m => ({ default: m.WalletsPage })))
const ReceivableKindsPage = lazy(() => import('@/app/pages/catalogs/ReceivableKindsPage').then(m => ({ default: m.ReceivableKindsPage })))
const MovementKindsPage = lazy(() => import('@/app/pages/catalogs/MovementKindsPage').then(m => ({ default: m.MovementKindsPage })))

// --- S8 — OPERAÇÕES ESTRUTURADAS, REMUNERAÇÕES e os dois catálogos -----------
// A mesma divisão da S5/S6, e pelo mesmo motivo do contrato C1:
// `StructuredOperationsPage` (Gestão) e `RemunerationsPage` (Projeto) são
// escopadas por projeto e carregam `requiresProject`; `StructuredOperationTypesPage`
// e `ResourceSourcesPage` administram CATÁLOGOS GLOBAIS e ficam em "Cadastro" —
// o Colaborador não vê as telas e continua LENDO o dado pela API (DEC-18.4).
//
// **`resource_kinds` NÃO tem linha aqui — DEC-110.** O portão T-D7 foi
// respondido pelo dump: 0 linhas na tabela e 0 de 28.131 `receivable_entries` a
// referenciam. A tela e o item de menu viraram `dropped`; a tabela sai numa
// tarefa explícita. Se você veio "consertar" acrescentando a entrada, pare: a
// decisão está escrita e o P-041 (os dois cadastros indistinguíveis) foi fechado
// justamente por ela.
const StructuredOperationsPage = lazy(() => import('@/features/structured-operations/pages/StructuredOperationsPage').then(m => ({ default: m.StructuredOperationsPage })))
const StructuredOperationFormPage = lazy(() => import('@/features/structured-operations/pages/StructuredOperationFormPage').then(m => ({ default: m.StructuredOperationFormPage })))
const StructuredOperationDetailPage = lazy(() => import('@/features/structured-operations/pages/StructuredOperationDetailPage').then(m => ({ default: m.StructuredOperationDetailPage })))
const RemunerationsPage = lazy(() => import('@/features/structured-operations/pages/RemunerationsPage').then(m => ({ default: m.RemunerationsPage })))
const StructuredOperationTypesPage = lazy(() => import('@/features/structured-operations/pages/StructuredOperationTypesPage').then(m => ({ default: m.StructuredOperationTypesPage })))
const ResourceSourcesPage = lazy(() => import('@/app/pages/catalogs/ResourceSourcesPage').then(m => ({ default: m.ResourceSourcesPage })))

// --- S10 — INDICADORES -------------------------------------------------------
// Três telas, e as duas regras de escopo opostas do contrato C1 convivem aqui:
// o **catálogo** (`/indicators`) é global e não tem `requiresProject`; a tela de
// **conexões** e a **grade** são escopadas pelo projeto corrente e têm.
//
// Q-R33: no legado DOIS itens de menu se chamam "Indicadores" — um em Gestão
// (lançamentos) e outro em Cadastro (catálogo). Aqui o de Gestão passa a ser
// **"Lançamentos de indicadores"**.
const IndicatorsPage = lazy(() => import('@/features/indicators/pages/IndicatorsPage').then(m => ({ default: m.IndicatorsPage })))
const ProjectIndicatorsPage = lazy(() => import('@/features/indicators/pages/ProjectIndicatorsPage').then(m => ({ default: m.ProjectIndicatorsPage })))
const IndicatorEntriesPage = lazy(() => import('@/features/indicators/pages/IndicatorEntriesPage').then(m => ({ default: m.IndicatorEntriesPage })))

/**
 * Os grupos do console, na ordem do `create_console_menu`.
 *
 * Ícones: **ícone de destino nunca repete ícone de modo.** O `SidebarModeToggle`
 * usa `Layers`, `Briefcase`, `FileText` e `Settings2`; com a sidebar recolhida,
 * ícone repetido deixa dois controles diferentes indistinguíveis.
 */
export const CONSOLE_NAV_GROUPS: NavGroup[] = [
  // --- "Início" — grupo sem itens, vira link direto ------------------------
  {
    id: 'dash',
    title: 'Início',
    icon: LayoutGrid,
    path: '/dashboard',
    items: [],
  },

  // --- "Gestão" — gate `projects.count > 0`, sem gate de papel -------------
  {
    id: 'results_group',
    title: 'Gestão',
    icon: Scale,
    requiresProject: true,
    items: [
      { id: 'risk', path: '/risk', label: 'Controle de Risco', icon: ShieldAlert, resource: 'risk', requiresProject: true, element: RiskConsolePage, slice: 'S5' },
      { id: 'availability', path: '/availability', label: 'Painel de Disponibilidade', icon: CalendarRange, resource: 'availability', requiresProject: true, element: AvailabilityPage, slice: 'S11' },
      {
        id: 'receivables',
        path: '/receivables',
        label: 'Recebíveis',
        icon: Receipt,
        resource: 'receivables',
        requiresProject: true,
        element: ReceivablesPage,
        slice: 'S6',
        // `novo` ANTES de `:id`: o React Router casa na ordem, e sem isto
        // `/receivables/novo` cairia na rota de detalhe com o id `"novo"`.
        children: [
          { path: 'novo', element: ReceivableFormPage },
          { path: ':id', element: ReceivableFormPage },
        ],
      },
      {
        id: 'renegotiations', path: '/renegotiations', label: 'Renegociações', icon: RefreshCcw,
        resource: 'renegotiations', requiresProject: true, element: RenegotiationsPage, slice: 'S9',
        // `new` ANTES de `:id`: a rota literal tem de ganhar da paramétrica,
        // senão "/renegotiations/new" abriria o detalhe de uma renegociação
        // chamada "new" e responderia 404.
        children: [
          { path: 'new', element: RenegotiationFormPage },
          { path: ':id/edit', element: RenegotiationFormPage },
          { path: ':id', element: RenegotiationDetailPage },
        ],
      },
      // Q-R33 — rótulo distinto do catálogo, que fica em "Cadastro".
      { id: 'indicator_entries', path: '/indicator-entries', label: 'Lançamentos de indicadores', icon: Gauge, resource: 'indicator_entries', requiresProject: true, element: IndicatorEntriesPage, slice: 'S10' },
      {
        id: 'risk_operations', path: '/risk-operations', label: 'Operações de Risco', icon: Layers3,
        resource: 'risk_operations', requiresProject: true, element: RiskOperationsPage, slice: 'S7',
        children: [{ path: ':id', element: RiskOperationDetailPage }],
      },
      {
        // OPS-286 — o item de "Gestão". O legado chamava a aba desta tela de
        // "Safegold - Garantias do Projeto" e o deep-link de "Recebívels": as
        // duas strings vieram coladas de outras telas e ficam corrigidas.
        id: 'structured_operations', path: '/structured-operations', label: 'Operações Estruturadas', icon: Boxes,
        resource: 'structured_operations', requiresProject: true, element: StructuredOperationsPage, slice: 'S8',
        // `new` ANTES de `:id`: a rota literal tem de ganhar da paramétrica.
        children: [
          { path: 'new', element: StructuredOperationFormPage },
          { path: ':id/edit', element: StructuredOperationFormPage },
          { path: ':id', element: StructuredOperationDetailPage },
        ],
      },
    ],
  },

  // --- "Projeto" — gate `projects.count > 0` -------------------------------
  {
    id: 'project_group',
    title: 'Projeto',
    icon: FolderKanban,
    requiresProject: true,
    items: [
      {
        id: 'charges', path: '/charges', label: 'Cobranças', icon: Coins, resource: 'charges',
        requiresProject: true, element: ChargesPage, slice: 'S6',
        // A tela de recibos é rota FILHA, no mesmo registro. No legado ela era
        // `{resource: 'charges', topic: id, section: 'receipts'}` em memória,
        // com `history.replaceState` — e o botão Voltar saía do console (D-92).
        // O DETALHE também é rota própria (26/08/2026). Ele era um `SideDrawer`,
        // e gaveta é o lugar de formulário curto — o detalhe da cobrança abre o
        // extrato por remuneração e leva à seleção de recibos, que numa cobrança
        // real tem 214 candidatos. Leitura densa é página.
        //
        // `:id/receipts` ANTES de `:id`: o React Router casa na ordem, e a rota
        // mais específica tem de ser declarada primeiro.
        children: [
          { path: ':id/receipts', element: ChargeReceiptsPage },
          { path: ':id', element: ChargeDetailPage },
        ],
      },
      { id: 'project_availabilities', path: '/project-availabilities', label: 'Disponibilidades', icon: CalendarRange, resource: 'project_availabilities', requiresProject: true, element: ProjectAvailabilitiesPage, slice: 'S11' },
      {
        id: 'companies', path: '/companies', label: 'Empresas', icon: Building2, resource: 'companies',
        requiresProject: true, element: CompaniesPage, slice: 'S4',
        children: [{ path: ':id', element: CompanyDetailPage }],
      },
      {
        // D-22 — o detalhe do fornecedor **passa a existir**: no legado a rota
        // e a action existiam e o template não, então clicar na linha dava
        // `MissingTemplate`.
        id: 'providers', path: '/providers', label: 'Fornecedores', icon: Truck, resource: 'providers',
        requiresProject: true, element: ProvidersPage, slice: 'S4',
        children: [{ path: ':id', element: ProviderDetailPage }],
      },
      { id: 'project_guarantees', path: '/project-guarantees', label: 'Garantias', icon: Landmark, resource: 'project_guarantees', requiresProject: true, element: ProjectGuaranteesPage, slice: 'S4' },
      // A ponte projeto ↔ portador (DB-068). É a ÚNICA: os portadores da
      // empresa são derivados do projeto, e não há tabela empresa↔portador.
      { id: 'project_to_carrier_connections', path: '/project-carrier-connections', label: 'Portadores do projeto', icon: Landmark, resource: 'project_to_carrier_connections', requiresProject: true, element: CarrierConnectionsPage, slice: 'S4' },
      { id: 'indicator_connections', path: '/indicator-connections', label: 'Indicadores específicos', icon: Network, resource: 'indicator_connections', requiresProject: true, element: ProjectIndicatorsPage, slice: 'S10' },
      { id: 'risk_controls', path: '/risk-controls', label: 'Limites', icon: SlidersHorizontal, resource: 'risk_controls', requiresProject: true, element: RiskControlsPage, slice: 'S5' },
      {
        // FE-306 — os deep-links entram como rotas FILHAS, com histórico de
        // verdade. No legado eram `history.replaceState`, e por isso o botão
        // Voltar saía do console (D-92) — além de a URL virar
        // `/remunerations/undefined/edit.js`, porque `openEdit` gravava `taxId`
        // e o proxy lia `remuneration_id`.
        id: 'remunerations', path: '/remunerations', label: 'Remunerações', icon: Wallet,
        resource: 'remunerations', requiresProject: true, element: RemunerationsPage, slice: 'S8',
        children: [
          { path: 'add', element: RemunerationsPage },
          { path: ':id/edit', element: RemunerationsPage },
        ],
      },
    ],
  },

  // --- "Cadastro" — og / admin / gerente -----------------------------------
  // DEC-18.4: o Colaborador NÃO vê este grupo, mas LÊ os catálogos pela API.
  // Esconder a tela de administração não é esconder o dado.
  {
    id: 'management',
    title: 'Cadastro',
    icon: Globe,
    roles: ['og', 'admin', 'gerente'],
    items: [
      {
        id: 'projects', path: '/projects', label: 'Projetos', icon: FolderKanban, resource: 'projects',
        roles: ['og', 'admin', 'gerente'], element: ProjectsPage, slice: 'S4',
        // O detalhe entra como rota FILHA, no mesmo registro: é o que impede o
        // menu de mostrar uma área cuja rota não está montada.
        children: [{ path: ':id', element: ProjectDetailPage }],
      },
      { id: 'wallets', path: '/wallets', label: 'Carteiras', icon: Wallet, resource: 'wallets', roles: ['og', 'admin', 'gerente'], element: WalletsPage, slice: 'S6' },
      {
        id: 'users', path: '/users', label: 'Contas', icon: UsersIcon, resource: 'users',
        roles: ['og', 'admin', 'gerente'], element: UsersPage, slice: 'S1',
        // FE-018 — os deep-links do drawer entram como rotas FILHAS, com histórico
        // de verdade. No legado o mesmo efeito era `history.replaceState`, e por
        // isso o botão Voltar saía do console (mesma família do D-92).
        //
        // `new` vem ANTES de `:id` por clareza; o react-router já ranqueia segmento
        // estático acima de dinâmico, então `/users/new` nunca cai no detalhe.
        children: [
          { path: 'new', element: UsersPage },
          { path: ':id', element: UserDetailPage },
          { path: ':id/edit', element: UsersPage },
        ],
      },
      { id: 'carrier_groups', path: '/carrier-groups', label: 'Grupos de Portadores', icon: Users2, resource: 'carrier_groups', roles: ['og', 'admin', 'gerente'], element: CarrierGroupsPage, slice: 'S3' },
      {
        // FE-317 — os deep-links do drawer entram como rotas FILHAS, com
        // histórico de verdade. No legado o mesmo efeito existia por
        // `history.replaceState`, e por isso o botão Voltar saía do console (D-92).
        id: 'indicators', path: '/indicators', label: 'Indicadores', icon: Gauge, resource: 'indicators',
        roles: ['og', 'admin', 'gerente'], element: IndicatorsPage, slice: 'S10',
        children: [
          { path: 'new', element: IndicatorsPage },
          { path: ':id/edit', element: IndicatorsPage },
        ],
      },
      { id: 'availability_templates', path: '/availability-templates', label: 'Padrões de Disponibilidade', icon: CalendarRange, resource: 'availability_templates', roles: ['og', 'admin', 'gerente'], element: AvailabilityTemplatesPage, slice: 'S11' },
      // DEC-18.2: permissões são de OG e Admin — o Gerente NÃO alcança, embora
      // veja o resto do grupo. É a mesma linha da matriz do servidor.
      { id: 'permissions', path: '/permissions', label: 'Permissões', icon: BadgeCheck, resource: 'permissions', roles: ['og', 'admin'], element: PermissionsPage, slice: 'S1' },
      // DC-08 / D-22: o detalhe do portador existia no legado (HTML e SCSS
      // completos) e NENHUMA rota chegava nele. Entra como `children` da área,
      // que é o ponto de extensão previsto — não como `<Route>` solto em App.tsx.
      { id: 'carriers', path: '/carriers', label: 'Portadores', icon: Landmark, resource: 'carriers', roles: ['og', 'admin', 'gerente'], element: CarriersPage, slice: 'S3', children: [{ path: ':id', element: CarrierDetailPage }] },
      { id: 'segments', path: '/segments', label: 'Segmentos', icon: Tags, resource: 'segments', roles: ['og', 'admin', 'gerente'], element: SegmentsPage, slice: 'S3' },
      { id: 'sub_segments', path: '/sub-segments', label: 'Subsegmentos', icon: Tag, resource: 'sub_segments', roles: ['og', 'admin', 'gerente'], element: SubSegmentsPage, slice: 'S3' },
      { id: 'movement_kinds', path: '/movement-kinds', label: 'Tipos de Movimentação', icon: ArrowLeftRight, resource: 'movement_kinds', roles: ['og', 'admin', 'gerente'], element: MovementKindsPage, slice: 'S6' },
      { id: 'receivable_kinds', path: '/receivable-kinds', label: 'Tipos de Recebíveis', icon: FileStack, resource: 'receivable_kinds', roles: ['og', 'admin', 'gerente'], element: ReceivableKindsPage, slice: 'S6' },
      // OPS-286 / DEC-110 — sobra SÓ este cadastro. A Q-R22 (os dois rótulos
      // indistinguíveis) desapareceu quando `resource_kinds` caiu no portão
      // T-D7, então o rótulo do legado fica sem ambiguidade nenhuma.
      { id: 'resource_sources', path: '/resource-sources', label: 'Tipos de Recursos', icon: PackageSearch, resource: 'resource_sources', roles: ['og', 'admin', 'gerente'], element: ResourceSourcesPage, slice: 'S8' },
      { id: 'risk_operation_types', path: '/risk-operation-types', label: 'Tipos de Limite', icon: SlidersHorizontal, resource: 'risk_operation_types', roles: ['og', 'admin', 'gerente'], element: RiskOperationTypesPage, slice: 'S5' },
      { id: 'structured_operation_types', path: '/structured-operation-types', label: 'Tipos de OP Estruturada', icon: Blocks, resource: 'structured_operation_types', roles: ['og', 'admin', 'gerente'], element: StructuredOperationTypesPage, slice: 'S8' },
      { id: 'risk_movement_types', path: '/risk-movement-types', label: 'Movimentações de Risco', icon: ArrowLeftRight, resource: 'risk_movement_types', roles: ['og', 'admin', 'gerente'], element: RiskMovementTypesPage, slice: 'S5' },
      { id: 'project_guarantee_types', path: '/project-guarantee-types', label: 'Tipos de garantia', icon: ShieldQuestion, resource: 'project_guarantee_types', roles: ['og', 'admin', 'gerente'], element: GuaranteeTypesPage, slice: 'S3' },
    ],
  },

  // --- "Admin" — og / admin -------------------------------------------------
  {
    id: 'admin_settings',
    title: 'Admin',
    icon: ShieldCheck,
    roles: ['og', 'admin'],
    items: [
      { id: 'help_items', path: '/help/items', label: 'Central de ajuda', icon: BookOpen, resource: 'help_items', roles: ['og', 'admin'], element: HelpCenterPage, slice: 'S12' },
      // DEC-38 — a tela de contratos nasce gateada por OG e Admin, que é o
      // recurso NOVO `contract_versions` da matriz. O recurso `contracts`
      // (ler e aceitar) continua `R` para os quatro papéis e NÃO tem item de
      // menu: ele é alcançado pelo banner de pendência e pelo perfil.
      //
      // As rotas de detalhe e de nova versão entram como `children` — `App.tsx`
      // monta as três a partir desta linha, com o MESMO gate de papel.
      { id: 'contract_versions', path: '/admin/contracts', label: 'Contratos', icon: ScrollText, resource: 'contract_versions', roles: ['og', 'admin'], element: ContractsPage, slice: 'S12',
        children: [
          { path: ':kind/new', element: ContractVersionFormPage },
          { path: ':kind', element: ContractDetailPage },
        ] },
      // DS2-1: a tela de mensagens era ÓRFÃ no legado — existia e o
      // `create_console_menu` não a listava. Deixar de listá-la aqui repetiria
      // o defeito no produto novo.
      { id: 'admin_messages', path: '/messages', label: 'Mensagens', icon: MessageSquare, resource: 'admin_messages', roles: ['og', 'admin'], element: MessagesPage, slice: 'S2' },
      // DEC-77: a trilha GLOBAL é de OG e Admin. O histórico do próprio objeto
      // fica com quem vê o objeto, e isso é decidido na tela do objeto.
      // A tela é da S19; o item de menu e o gate são desta fatia.
      // O gate é `RoleRoute roles={['og','admin']}`, e NÃO o `OgRoute` sugerido
      // no cabeçalho da página: o `OgRoute` casa por `includes('admin')` no
      // NOME de exibição do papel, uma comparação frouxa que não é a mesma
      // regra do servidor. A matriz responde OG 200 · Admin 200 · Gerente 403 ·
      // Colaborador 403, e o menu tem que dizer exatamente isso — item que
      // aparece para quem toma 403 ao clicar é pior que item ausente.
      { id: 'audit_trail', path: '/admin/audit-trail', label: 'Trilha de auditoria', icon: History, resource: 'audit_trail', roles: ['og', 'admin'], element: AuditTrailPage, slice: 'S19' },
    ],
  },

  // --- "Plataforma" — o que a base ai9 trouxe e o Safegold mantém ----------
  // Não existe no `create_console_menu`: são telas da base (Galeria, Chatbot,
  // Credenciais) mais o pareamento por QR. Ficam num grupo próprio para não se
  // misturarem às áreas de paridade.
  {
    id: 'platform',
    title: 'Plataforma',
    icon: Plug,
    roles: ['og', 'admin'],
    items: [
      { id: 'chat_flows', path: '/admin/chat/flows', label: 'Chatbot', icon: Zap, resource: 'console', roles: ['og', 'admin'], element: FlowListPage, slice: 'base' },
      { id: 'credentials', path: '/admin/credentials', label: 'Credenciais', icon: Key, resource: 'console', roles: ['og', 'admin'], element: CredentialsPage, slice: 'base' },
      // DEC-83 / DS2-2: a tela de pareamento por QR existia na base e NÃO tinha
      // rota. É dela que o canal de login por WhatsApp (DEC-14) depende: quando
      // a sessão da instância expira, sem esta tela ninguém repareia e o canal
      // de entrada cai. Gate: OG e Admin.
      //
      // **O caminho NÃO pode ser `/whatsapp`.** O proxy de dev encaminha tudo
      // que começa com `/whats` ao Rails (`vite.config.ts`), e `/whatsapp` casa
      // com esse prefixo: a tela devolvia um `Routing Error` do Rails em vez de
      // abrir. Descoberto renderizando — `tsc` passa limpo com a rota
      // inalcançável. O prefixo do proxy foi apertado para `^/whats/` no mesmo
      // passo, mas o caminho fica sob `/platform/` porque é onde ele pertence.
      { id: 'whatsapp', path: '/platform/whatsapp', label: 'WhatsApp', icon: Smartphone, resource: 'console', roles: ['og', 'admin'], element: WhatsappPage, slice: 'S2' },
    ],
  },

  // --- "Perfil" — sem gate --------------------------------------------------
  {
    id: 'account',
    title: 'Perfil',
    icon: UserCircle,
    linkToSingleItem: true,
    items: [
      { id: 'my_account', path: '/profile', label: 'Minha conta', icon: UserCircle, resource: 'my_account', element: ProfilePage, slice: 'S1' },
    ],
  },

  // --- "Ajuda" — grupo sem itens, link direto ------------------------------
  {
    id: 'faq',
    title: 'Ajuda',
    icon: HelpCircle,
    linkToSingleItem: true,
    items: [
      { id: 'faq', path: '/faq', label: 'Ajuda', icon: LifeBuoy, resource: 'faq', element: FaqPage, slice: 'S12' },
    ],
  },
]

/** Todos os itens de todos os grupos, achatados. */
export const CONSOLE_NAV_ITEMS: NavItem[] = CONSOLE_NAV_GROUPS.flatMap(g => g.items)

/** Só as áreas cuja página existe — é o que `App.tsx` monta como rota. */
export const MOUNTED_AREAS: NavItem[] = CONSOLE_NAV_ITEMS.filter(i => i.element !== null)

/** A área do "Início": o `DashboardPage` da base, montado fora dos grupos. */
export const HOME_AREA = { path: '/dashboard', element: DashboardPage }
