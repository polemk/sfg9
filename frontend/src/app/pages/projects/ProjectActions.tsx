import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { notify } from '@/lib/notify'
import { SideDrawer } from '@/components/SideDrawer'
import { Button } from '@/components/ui/Button'
import { mensagemDoServidor } from '@/lib/api/catalogs'
import { projectsApi, type Project } from '@/lib/api/projects'
import { ProjectForm, type ProjectFormValues, valoresIniciais, doProjeto } from './ProjectForm'
import { enviarLogoPendente } from './ScopedLogoField'

/**
 * **Editar e remover um projeto — a gaveta e a confirmação, num lugar só.**
 *
 * Nasceu do **FE-094**: o detalhe do projeto não oferecia "Editar" nem
 * "Remover". As duas ações existiam só na LISTA, então quem abrisse o projeto
 * para conferir tinha de voltar para agir — e a lista, com filtro e paginação,
 * pode nem estar mostrando aquele projeto quando ele voltasse.
 *
 * Componente compartilhado, e não uma segunda cópia no detalhe. O que se
 * duplicaria não é layout: é a REGRA. O projeto de treinamento (`is_sandbox`)
 * nunca é removido — ele é limpo, e a limpeza é rotina de operação com
 * pré-visualização. Duas telas escrevendo essa condição divergiriam na primeira
 * mudança, e a que ficasse para trás ofereceria um "Remover" que o servidor
 * recusa.
 *
 * O `ProjectForm` já era compartilhado; o que faltava era o par gaveta +
 * confirmação em volta dele.
 */
export function useProjectActions({ onRemovido }: { onRemovido?: () => void } = {}) {
  const queryClient = useQueryClient()
  const [drawerAberto, setDrawerAberto] = useState(false)
  const [editando, setEditando] = useState<Project | null>(null)
  const [valores, setValores] = useState<ProjectFormValues>(valoresIniciais())
  const [confirmando, setConfirmando] = useState<Project | null>(null)
  // DEC-136 — o logo escolhido na criação, à espera do id.
  const [logoPendente, setLogoPendente] = useState<File | null>(null)

  // Invalida a lista E o detalhe: as duas telas abrem estas ações, e a que não
  // fosse invalidada mostraria o valor velho até um recarregamento.
  const invalidar = () => {
    queryClient.invalidateQueries({ queryKey: ['projects'] })
    queryClient.invalidateQueries({ queryKey: ['project'] })
  }

  const salvar = useMutation({
    mutationFn: async (dados: Record<string, unknown>) => {
      if (editando) return projectsApi.update(editando.id, dados)

      const criado = await projectsApi.create(dados)
      // **O segundo passo (DEC-136).** Falhar aqui NÃO desfaz o cadastro: o
      // projeto fica criado e a mensagem diz que só a imagem não subiu.
      await enviarLogoPendente(projectsApi, criado.id, logoPendente)
      return criado
    },
    onSuccess: () => {
      // FE-090 — "cadastrado" e "atualizado" são eventos diferentes, e o
      // legado dizia a mesma frase para os dois.
      notify.success(editando ? 'Projeto atualizado.' : 'Projeto cadastrado.')
      setDrawerAberto(false)
      setEditando(null)
      setLogoPendente(null)
      invalidar()
    },
    onError: (erro) => notify.error(mensagemDoServidor(erro, 'Não foi possível salvar o projeto.')),
  })

  const excluir = useMutation({
    mutationFn: (projeto: Project) => projectsApi.remove(projeto.id),
    onSuccess: (_dado, projeto) => {
      notify.success(`Projeto «${projeto.name}» removido.`)
      setConfirmando(null)
      invalidar()
      // O detalhe passa `onRemovido` para sair da rota: ficar na página de um
      // projeto que não existe mais renderiza "não encontrado" e parece defeito.
      onRemovido?.()
    },
    onError: (erro) => {
      // FE-084 — o erro do servidor APARECE, e a lista não muda.
      notify.error(mensagemDoServidor(erro, 'Não foi possível remover o projeto.'))
      setConfirmando(null)
    },
  })

  return {
    abrirCriacao() {
      setEditando(null)
      setValores(valoresIniciais())
      setLogoPendente(null)
      setDrawerAberto(true)
    },
    abrirEdicao(projeto: Project) {
      setEditando(projeto)
      setValores(doProjeto(projeto))
      setDrawerAberto(true)
    },
    confirmarRemocao: setConfirmando,
    salvando: salvar.isPending,
    /** As duas superfícies, prontas para montar no fim da tela. */
    superficies: (
      <>
        <SideDrawer
          open={drawerAberto}
          onClose={() => setDrawerAberto(false)}
          title={editando ? 'Editar projeto' : 'Novo projeto'}
          footer={
            <div className="flex justify-end gap-2">
              <Button variant="secondary" onClick={() => setDrawerAberto(false)}>
                Cancelar
              </Button>
              {/* FE-089 / DC-23 — **uma** requisição por clique em "Salvar".
                  O legado registrava salvamento a cada `keyup` do formulário. */}
              <Button disabled={salvar.isPending} onClick={() => salvar.mutate(paraPayload(valores, editando))}>
                Salvar
              </Button>
            </div>
          }
        >
          <ProjectForm values={valores} onChange={setValores} editing={editando}
                       onLogoPendente={setLogoPendente} />
        </SideDrawer>

        <SideDrawer
          open={confirmando !== null}
          onClose={() => setConfirmando(null)}
          title={confirmando?.is_sandbox ? 'Limpar projeto de treinamento' : 'Remover projeto'}
          footer={
            <div className="flex justify-end gap-2">
              <Button variant="secondary" onClick={() => setConfirmando(null)}>
                Cancelar
              </Button>
              <Button
                variant="destructive"
                disabled={excluir.isPending || confirmando?.is_sandbox}
                onClick={() => confirmando && excluir.mutate(confirmando)}
              >
                Remover
              </Button>
            </div>
          }
        >
          {confirmando?.is_sandbox ? (
            <p className="text-sm text-muted-foreground">
              «{confirmando.name}» é o projeto de treinamento. Ele nunca é removido — os dados são limpos e o
              projeto volta ao estado inicial. A limpeza é feita por rotina de operação, com pré-visualização.
            </p>
          ) : (
            <p className="text-sm text-muted-foreground">
              Remover «{confirmando?.name}»? Se houver empresa, limite, recebível ou renegociação vinculados, o
              servidor recusa e o projeto permanece — a mensagem dirá qual vínculo segura.
            </p>
          )}
        </SideDrawer>
      </>
    ),
  }
}

/**
 * O corpo que vai ao servidor.
 *
 * Movido **literalmente** do `ProjectsPage`, sem uma linha reescrita: é ele que
 * decide o que o `permit` do servidor recebe, e redigitar de memória o corpo de
 * um formulário de projeto é como se perde campo numa migração.
 *
 * Mora aqui junto das mutações porque quem envia é quem monta.
 */
export function paraPayload(v: ProjectFormValues, editando: Project | null): Record<string, unknown> {
  const base: Record<string, unknown> = {
    name: v.name,
    is_active: v.is_active,
    segment_id: v.segment_id ?? undefined,
    sub_segment_id: v.sub_segment_id ?? undefined,
    address_type: v.address_type,
    address: v.address,
    address_number: v.address_number,
    address_complement: v.address_complement,
    neighborhood: v.neighborhood,
    cep: v.cep,
    address_state: v.address_state ?? undefined,
    address_city: v.address_city,
    closing_date: v.closing_date || undefined,
    availability_note: v.availability_note,
  }

  if (editando) {
    // `slug` e `integration_key` não vão: são congelados na criação (DC-17).
    if (v.responsible_user_id !== undefined) base.responsible_user_id = v.responsible_user_id ?? ''
    return base
  }

  base.responsible_mode = v.responsible_mode
  if (v.responsible_mode === 'existing') base.responsible_user_id = v.responsible_user_id ?? ''
  if (v.responsible_mode === 'new') {
    base.responsible_name = v.responsible_name
    base.responsible_email = v.responsible_email
  }
  return base
}
