import { useEffect } from 'react'
import { CatalogScreen } from '@/app/pages/catalogs/CatalogScreen'
import { Campo, CampoAtivo, CampoTexto } from '@/app/pages/catalogs/CatalogFields'
import { Input } from '@/components/ui/Input'
import {
  structuredOperationTypesApi,
  type StructuredOperationType,
} from '../api/structuredOperations'

/**
 * **Cadastro › Tipos de OP Estruturada** (`FE-300`, `FE-301`, `FE-302`).
 *
 * Catálogo **global** (contrato C1, regra 4) — não é escopado por projeto. O
 * grupo "Cadastro" é de **og / admin / gerente**: o Colaborador não vê a tela e
 * mesmo assim **lê** o catálogo pela API (DEC-18.4), senão o dropdown do
 * formulário de operação sobe vazio para o papel mais numeroso.
 *
 * ## `FE-300` — "Excluir" não aparece, e agora a tela DIZ por quê
 *
 * O legado escondia o item do menu quando `is_default?`. Como **os quatro tipos
 * semeados são `is_default`**, na prática nenhum tipo é removível — e o usuário
 * via um menu com uma ação a menos, sem explicação. O comportamento é
 * replicado; o que muda é que o lugar do botão fica ocupado por um cadeado com
 * a razão escrita. A segunda guarda (tipo **em uso** por operação) também
 * aparece — no legado ela não existia na tela, e a exclusão ia até o servidor
 * para voltar em silêncio.
 *
 * ## `FE-302` — clicar em "Remover" fazia LITERALMENTE nada
 *
 * O `$.ajax` de DELETE do legado **não define `error`**, e o backend responde
 * 422 quando o tipo está bloqueado: o script de resposta nunca executava. Para
 * o usuário, o botão simplesmente não funcionava. Aqui a recusa vira toast com
 * a mensagem do servidor, que nomeia o vínculo.
 *
 * ## `FE-301` — as três copies erradas do legado saem
 *
 * O painel dizia **"Cadastrar uma taxa" / "Editar uma taxa"** (texto do helper
 * de *remunerações*) e a confirmação dizia **"Essa construtora não pode ser
 * alterada"** (de outro domínio inteiro). Além disso o ramo de **sucesso era
 * vazio** — salvar não emitia nada — e o de erro despejava
 * `<b>chave_tecnica</b>` cru na tela. Aqui o sucesso emite toast, o erro mostra
 * a mensagem do servidor e nenhuma chave técnica aparece.
 */
export function StructuredOperationTypesPage() {
  useEffect(() => {
    document.title = 'Safegold - Tipos de OP Estruturada'
  }, [])

  return (
    <CatalogScreen<StructuredOperationType>
      queryKey="structured-operation-types"
      api={structuredOperationTypesApi}
      // Grupo "Cadastro": `current_user.admin? || og? || manager?`, que é o
      // default do molde. Explícito porque é regra da tela, não herança.
      writeRoles={['og', 'admin', 'gerente']}
      texts={{
        title: 'Tipos de OP Estruturada',
        subtitle:
          'Fomento, comissária, intercompany e auto liquidável. É por este tipo que o recibo acha a remuneração do projeto.',
        singular: 'tipo de operação estruturada',
        createLabel: 'Novo tipo',
        emptyTitle: 'Nenhum tipo de operação estruturada',
        emptyDescription:
          'Sem tipo não há operação estruturada: o campo é obrigatório no cadastro. Cadastre o primeiro.',
        searchPlaceholder: 'Buscar tipo por título ou chave…',
      }}
      defaultSort={{ key: 'title', direction: 'asc' }}
      columns={[
        { key: 'title', header: 'Título', sortable: true, accessor: (t) => t.title },
        {
          key: 'key',
          header: 'Chave',
          sortable: true,
          accessor: (t) => t.integration_key,
          // O legado mostrava `-` para chave em branco. Replicado.
          cell: (t) => (
            <code className="font-numeric text-xs text-muted-foreground">{t.integration_key || '-'}</code>
          ),
        },
        {
          key: 'dependents_count',
          header: 'Operações',
          variant: 'number',
          accessor: (t) => t.dependents_count,
        },
      ]}
      mobileFields={(t) => [
        { label: 'Chave', value: <code className="font-numeric text-xs">{t.integration_key || '-'}</code> },
        {
          label: 'Operações',
          value: <span className="font-numeric tabular-nums">{t.dependents_count}</span>,
        },
      ]}
      // FE-300 — as DUAS guardas do servidor, no mesmo número que esconde o
      // botão: tipo semeado pelo sistema e tipo em uso.
      usageCount={(t) => (t.is_default ? Math.max(1, t.dependents_count) : t.dependents_count)}
      usageLabel={(t) =>
        t.is_default
          ? 'Tipo semeado pelo sistema — não é removível'
          : t.dependents_count === 1
            ? '1 operação estruturada usa este tipo — não é possível excluir'
            : `${t.dependents_count} operações estruturadas usam este tipo — não é possível excluir`
      }
      emptyForm={() => ({ title: '', integration_key: '', is_active: true })}
      toForm={(t) => ({ title: t.title, integration_key: t.integration_key, is_active: t.is_active })}
      form={({ values, setValue, editing }) => (
        <>
          {editing ? (
            // BE-298 — o título é IMUTÁVEL depois da criação, na tela e no
            // servidor. O legado já fazia isso com `readonly: 'readonly'`.
            <Campo
              id="title"
              label="Título"
              hint="Definido na criação e mantido depois — o título viaja congelado para dentro de cada remuneração."
            >
              <Input id="title" readOnly value={(values.title as string) ?? ''} />
            </Campo>
          ) : (
            <CampoTexto
              id="title"
              label="Escolha um título"
              value={values.title}
              onChange={(v) => setValue('title', v)}
              placeholder="Ex.: Fomento"
              autoFocus
            />
          )}

          <CampoTexto
            id="integration_key"
            label="Chave de integração"
            value={values.integration_key}
            onChange={(v) => setValue('integration_key', v)}
            placeholder="Ex.: fomento"
            hint="Congelada na criação. É por ela que uma integração externa acha o tipo."
          />

          <CampoAtivo
            value={values.is_active}
            onChange={(v) => setValue('is_active', v)}
            descricao="Tipo inativo sai do formulário de cadastro, mas continua no filtro da lista — é o que permite achar operação histórica de um tipo desativado."
          />
        </>
      )}
    />
  )
}
