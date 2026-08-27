import React from 'react'
import { OgRoute } from '@/components/OgRoute'

/**
 * **Hoje é o mesmo que `OgRoute`, e por isso delega em vez de repetir.**
 *
 * Este guard existia para liberar as rotas de `/admin/chat/*` a três tipos de
 * usuário além do OG: `visitor`, `client` e — por acidente do
 * `includes('admin')` — o Admin. A **DEC-41 removeu `visitor`, `client` e
 * `free`**: os quatro papéis do Safegold são OG, Admin, Gerente e Colaborador.
 *
 * O backend foi limpo quando a DEC-41 entrou. **O frontend não** — e este
 * arquivo continuou decidindo acesso por `typeSlug === 'client'` e
 * `t.includes('cliente')`, tipos que não existem mais. Na prática o efeito já
 * era "OG e Admin passam", mas escrito de um jeito que convida ao erro:
 * "cliente" é palavra corrente do domínio, e a primeira pessoa que criar um tipo
 * com esse nome no futuro abre estas três rotas para ele sem perceber.
 *
 * Delegar — em vez de copiar a regra — garante que os dois não possam divergir.
 * Se um dia o chat precisar de um conjunto **diferente** de papéis, aí sim vale
 * um guard próprio, com a regra escrita e um teste dizendo qual é.
 */
export function VisitorRoute({ children }: { children: React.ReactNode }) {
  return <OgRoute>{children}</OgRoute>
}
