import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useNavigate } from 'react-router-dom'
import { CatalogScreen } from './CatalogScreen'
import { CampoAtivo, CampoTexto, Campo } from './CatalogFields'
import { CarrierLogoField } from './CarrierLogoField'
import { Select } from '@/components/ui/Select'
import { Label } from '@/components/ui/Label'
import { Textarea } from '@/components/ui/textarea'
import { MoneyInput, NumericInput } from '@/components/ui/NumericInput'
import { formatPercent } from '@/lib/utils/number'
import {
  brStatesApi,
  carrierGroupsApi,
  carriersApi,
  FINANCIAL_AGENTS,
  type Carrier,
} from '@/lib/api/catalogs'

/**
 * **Portadores** (FE-060, FE-062..FE-067). Catálogo global.
 *
 * O portador **não é "fornecedor genérico"**: é a **contraparte financiadora** —
 * o FIDC, a securitizadora, a factoring ou o próprio cliente que põe o dinheiro
 * na operação. Todo rótulo desta tela usa esse vocabulário, e é por isso que o
 * formulário tem a estrutura de cotas de um fundo.
 *
 * Quatro coisas que mudam em relação ao legado:
 *
 * - **A paginação funciona** (D-20). A lista trazia tudo.
 * - **`bank_code` é texto e preserva `001`** (DC-12). Guardado como número, o
 *   código COMPE do Banco do Brasil virava `1`.
 * - **"% contas subordinadas" é somente leitura** (DC-09), calculado no
 *   servidor a partir das cotas. No legado era calculado em JS a cada tecla
 *   **e** persistido como coluna editável — duas fontes de verdade, e a guarda
 *   de divisão por zero só existia no cliente.
 * - **O detalhe é alcançável** (DC-08). No legado o HTML e o SCSS da tela de
 *   detalhe existem e nenhuma rota chega neles.
 */
export function CarriersPage() {
  const navigate = useNavigate()

  // Listas pequenas e estáveis: `Select` da base resolve. O
  // `AsyncSearchableSelect` só é necessário onde a lista é grande (S4).
  const grupos = useQuery({
    queryKey: ['carrier-groups', 'opcoes'],
    queryFn: () => carrierGroupsApi.list({ perPage: 100 }),
    staleTime: 5 * 60 * 1000,
  })

  const ufs = useQuery({
    queryKey: ['br-states'],
    queryFn: () => brStatesApi.list(),
    staleTime: Infinity,
  })

  const opcoesDeGrupo = useMemo(
    () => [
      { value: '', label: 'Sem grupo' },
      ...(grupos.data?.items ?? []).map((g) => ({ value: g.id, label: g.title })),
    ],
    [grupos.data],
  )

  const opcoesDeUf = useMemo(
    () => [
      { value: '', label: 'Sem UF' },
      ...(ufs.data ?? []).map((uf) => ({ value: uf.code, label: `${uf.code} — ${uf.name}`, text: uf.name })),
    ],
    [ufs.data],
  )

  return (
    <CatalogScreen<Carrier>
      queryKey="carriers"
      api={carriersApi}
      onRowClick={(c) => navigate(`/carriers/${c.id}`)}
      texts={{
        title: 'Portadores',
        subtitle: 'Contrapartes financiadoras — FIDC, securitizadora, factoring ou o próprio cliente.',
        singular: 'portador',
        createLabel: 'Novo portador',
        emptyTitle: 'Nenhum portador cadastrado',
        emptyDescription:
          'O portador é a contraparte que financia a operação. Sem ele não há limite de risco nem borderô.',
        searchPlaceholder: 'Buscar portador por razão social ou chave…',
      }}
      columns={[
        { key: 'title', header: 'Razão social', sortable: true, accessor: (c) => c.title },
        {
          key: 'group',
          header: 'Grupo',
          // Fallback `-`: campo ausente não deixa a célula vazia (FE-063).
          cell: (c) => c.group_title ?? '-',
        },
        {
          key: 'financial_agent',
          header: 'Agente',
          sortable: true,
          cell: (c) => c.financial_agent ?? '-',
        },
        {
          key: 'bank_code',
          header: 'COMPE',
          sortable: true,
          // Texto, e em fonte numérica: `001` alinha com `237` e continua `001`.
          cell: (c) => <span className="font-numeric tabular-nums">{c.bank_code ?? '-'}</span>,
        },
        { key: 'city', header: 'Cidade', sortable: true, cell: (c) => c.city_label },
        {
          key: 'projects_count',
          header: 'Projetos',
          variant: 'number',
          accessor: (c) => c.projects_count,
        },
      ]}
      mobileFields={(c) => [
        { label: 'Grupo', value: c.group_title ?? '-' },
        { label: 'Agente', value: c.financial_agent ?? '-' },
        { label: 'COMPE', value: <span className="font-numeric tabular-nums">{c.bank_code ?? '-'}</span> },
        { label: 'Cidade', value: c.city_label },
      ]}
      usageCount={(c) => c.projects_count}
      usageLabel={(c) =>
        c.projects_count === 1
          ? '1 projeto usa este portador — não é possível excluir'
          : `${c.projects_count} projetos usam este portador — não é possível excluir`
      }
      emptyForm={() => ({ title: '', is_active: true, senior_accounts: 0, subordinated_accounts: 0, net_worth: 0 })}
      toForm={(c) => ({
        title: c.title,
        resume: c.resume ?? '',
        integration_key: c.integration_key,
        bank_code: c.bank_code ?? '',
        group_id: c.group_id ?? '',
        financial_agent: c.financial_agent ?? '',
        city: c.city ?? '',
        uf: c.uf ?? '',
        net_worth: Number(c.net_worth ?? 0),
        senior_accounts: c.senior_accounts,
        subordinated_accounts: c.subordinated_accounts,
        is_active: c.is_active,
      })}
      form={({ values, setValue, editing }) => {
        // O mesmo cálculo do servidor, só para PREVER o que ele vai gravar.
        // Quem manda é o servidor (DC-09): este número não é enviado.
        //
        // **A fórmula é a do legado (DEC-30): subordinadas ÷ SÊNIOR × 100**, e
        // 0 quando não há cota sênior. Não é a proporção usual de cota
        // subordinada num FIDC — e é de propósito. O golden
        // `carriers_percentual_golden_spec.rb` reprova quem "consertar".
        const senior = Number(values.senior_accounts ?? 0)
        const percentual = senior > 0 ? (Number(values.subordinated_accounts ?? 0) * 100) / senior : 0

        return (
          <>
            <CampoTexto
              id="title"
              label="Razão social"
              value={values.title}
              onChange={(v) => setValue('title', v)}
              placeholder="Ex.: FIDC Aurora Crédito"
              hint="Razão social repetida é permitida: há contrapartes homônimas com usos distintos."
              autoFocus
            />

            <Campo id="resume" label="Descrição">
              <Textarea
                id="resume"
                value={(values.resume as string) ?? ''}
                onChange={(e) => setValue('resume', e.target.value)}
                placeholder="Como esta contraparte opera, em uma frase."
                rows={3}
              />
            </Campo>

            <Campo id="financial_agent" label="Agente financeiro">
              <Select
                id="financial_agent"
                value={(values.financial_agent as string) ?? ''}
                onChange={(v) => setValue('financial_agent', v)}
                placeholder="Selecione o agente…"
                options={[
                  { value: '', label: 'Não informado' },
                  ...FINANCIAL_AGENTS.map((a) => ({ value: a, label: a })),
                ]}
              />
            </Campo>

            <Campo id="group_id" label="Grupo">
              <Select
                id="group_id"
                value={(values.group_id as string) ?? ''}
                onChange={(v) => setValue('group_id', v || null)}
                placeholder="Sem grupo"
                options={opcoesDeGrupo}
              />
            </Campo>

            <CampoTexto
              id="bank_code"
              label="Código COMPE"
              value={values.bank_code}
              onChange={(v) => setValue('bank_code', v)}
              placeholder="Ex.: 001"
              hint="É texto, não número: o zero à esquerda faz parte do código."
            />

            <div className="grid grid-cols-2 gap-3">
              <CampoTexto
                id="city"
                label="Cidade"
                value={values.city}
                onChange={(v) => setValue('city', v)}
                placeholder="Ex.: Campinas"
              />
              <Campo id="uf" label="UF">
                <Select
                  id="uf"
                  value={(values.uf as string) ?? ''}
                  onChange={(v) => setValue('uf', v)}
                  placeholder="UF"
                  options={opcoesDeUf}
                />
              </Campo>
            </div>

            {/* --- Estrutura de cotas (FIDC) --------------------------------- */}
            <fieldset className="space-y-3 rounded-md border border-border p-3">
              <legend className="px-1 text-xs font-bold uppercase tracking-widest text-muted-foreground">
                Estrutura de cotas
              </legend>

              <Campo id="net_worth" label="Patrimônio líquido">
                <MoneyInput
                  id="net_worth"
                  value={(values.net_worth as number) ?? 0}
                  onChange={(v) => setValue('net_worth', v ?? 0)}
                />
              </Campo>

              <div className="grid grid-cols-2 gap-3">
                <Campo id="senior_accounts" label="Cotas sênior">
                  <NumericInput
                    id="senior_accounts"
                    casas={0}
                    value={(values.senior_accounts as number) ?? 0}
                    onChange={(v) => setValue('senior_accounts', v ?? 0)}
                  />
                </Campo>
                <Campo id="subordinated_accounts" label="Cotas subordinadas">
                  <NumericInput
                    id="subordinated_accounts"
                    casas={0}
                    value={(values.subordinated_accounts as number) ?? 0}
                    onChange={(v) => setValue('subordinated_accounts', v ?? 0)}
                  />
                </Campo>
              </div>

              {/* DC-09 — somente leitura. O número é do SERVIDOR; o que aparece
                  aqui é a previsão do que ele vai gravar, e sem cota nenhuma é
                  "—", nunca uma divisão por zero. */}
              <div className="space-y-1.5">
                <Label htmlFor="percentual">% de cotas subordinadas</Label>
                <output
                  id="percentual"
                  className="flex h-10 w-full items-center rounded-md border border-input bg-muted px-3 font-numeric text-sm tabular-nums text-muted-foreground"
                >
                  {formatPercent(percentual)}
                </output>
                <p className="text-xs text-muted-foreground">
                  Calculado pelo servidor: cotas subordinadas dividido por cotas sênior. Sem cotas sênior o
                  percentual é 0.
                </p>
              </div>
            </fieldset>

            {editing && (
              <>
                <CampoTexto
                  id="integration_key"
                  label="Chave de integração"
                  value={values.integration_key}
                  onChange={(v) => setValue('integration_key', v)}
                  hint="Derivada da razão social na criação e mantida depois."
                />

                <Campo id="logo" label="Logo">
                  <CarrierLogoField carrier={editing} />
                </Campo>
              </>
            )}

            <CampoAtivo
              value={values.is_active}
              onChange={(v) => setValue('is_active', v)}
              descricao="Portador inativo continua nas operações que já existem, mas não aparece para novas escolhas."
            />
          </>
        )
      }}
    />
  )
}
