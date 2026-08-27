import { useMemo } from 'react'
import { useLocation } from 'react-router-dom'
import { CONSOLE_NAV_GROUPS, filtrarGrupos, useRoleSlug } from '@/hooks/useNavItems'
import { useCurrentProject } from '@/hooks/useCurrentProject'
import { screenLabelForPath } from '@/app/consoleNavigation'

/**
 * O CONTEXTO QUE O ASSISTENTE DO CONSOLE RECEBE A CADA MENSAGEM (DEC-13.2).
 *
 * Três fatos, e cada um resolve uma pergunta que o agente fazia ao usuário
 * embora o sistema já soubesse a resposta:
 *
 *  1. **em que tela ele está** — sem isto a conversa começava com "em que tela
 *     você está?", e a pessoa tinha de descrever o que está olhando para um
 *     assistente que roda dentro daquela tela;
 *  2. **qual é o projeto corrente** — o dado que o agente lê é sempre do projeto
 *     selecionado (contrato C1, revalidado no servidor a cada leitura). Ter o
 *     nome aqui deixa ele dizer de qual projeto está falando **sem** precisar
 *     consultar dado nenhum, inclusive quando a resposta é só de ajuda;
 *  3. **o que existe no menu DELE** — o agente responde "onde encontro X"
 *     nomeando telas que aquele papel realmente alcança, em vez de supor. A
 *     lista já vem filtrada por papel e participação.
 *
 * **Sem `mode`.** O filtro do menu lateral esconde grupos conforme o modo
 * escolhido na barra; isso é preferência de exibição, não alcance. Um item que
 * some da barra porque o modo é outro continua sendo um destino válido, e negá-lo
 * ao assistente faria a resposta depender de um botão da interface.
 *
 * **O que NÃO entra:** nada de conta, permissão, credencial ou trilha — a mesma
 * fronteira que `Ai::Tools::ConsoleScope::FORBIDDEN_RESOURCES` desenha no
 * servidor. Aqui o material é o mapa da navegação, não o dado de ninguém.
 */
export function useAssistantContext(): Record<string, string> {
  const location = useLocation()
  const role = useRoleSlug()
  const { current, hasProject } = useCurrentProject()

  return useMemo(() => {
    const contexto: Record<string, string> = {}

    const tela = screenLabelForPath(location.pathname)
    if (tela) contexto.tela_atual = tela
    contexto.rota_atual = location.pathname

    if (current?.name) contexto.projeto_selecionado = current.name

    const itens = filtrarGrupos(CONSOLE_NAV_GROUPS, { role, hasProject, mode: 'all' })
      .flatMap((g) => g.items)
      .map((i) => `${i.label} (${i.path})`)

    if (itens.length > 0) contexto.menu_disponivel = itens.join(' · ')

    return contexto
  }, [location.pathname, role, hasProject, current?.name])
}
