# Tarefa 4: Info Cards Explicativos + Dados Mock nas Páginas

**Sprint:** 2 — Preview Experience
**Estimativa:** 1.5 dias
**Tipo:** Frontend

---

## Contexto

O visitor está navegando pelo console com o menu filtrado pelo plano que escolheu. Ao entrar em cada página (Leads, Analytics, Operações...), ele precisa entender o que aquele recurso faz e como vai funcionar quando comprar. Duas coisas resolvem isso: dados fake realistas para as páginas parecerem "vivas", e cards informativos explicando cada seção.

O visitante vem do Instagram — atenção curta, tela pequena. Os cards precisam ser sutis, não intrusivos, com um "Leia mais" que expande. A ideia é que um card venha aberto por padrão para o visitor entender de cara, e os demais fiquem com um ícone ℹ️ clicável.

---

## Onde começa

- Páginas do admin existem e funcionam (Leads, Analytics, Dashboard, Operações, etc.)
- `planPreviewStore` com `isPreviewMode` e `selectedPlan` (Tarefa 2)
- Sidebar filtrando menu por plano (Tarefa 3)
- Páginas fazem fetch de dados via React Query/hooks existentes

## Onde termina

- Componente `PreviewInfoCard` reutilizável em qualquer página
- Cada página de preview mostra dados mock realistas em vez de dados reais
- Um info card vem expandido por padrão, demais mostram ℹ️
- CTA sticky no bottom de cada página: "Quero esse plano" → abre checkout
- Badge discreto "Preview" no topo da página

---

## O que precisa ser feito

### No Frontend

**Componente `PreviewInfoCard`:**
- Card sutil integrado ao layout da página (não é modal, não é overlay)
- Estado colapsado: ícone ℹ️ com 1 linha de texto resumido
- Estado expandido: 2-4 linhas explicando o recurso + como funciona no plano
- Botão "Leia mais" / "Menos" para alternar
- Dismissable: ao fechar, minimiza pro ℹ️ (não some pra sempre, persiste via localStorage)
- Prop `defaultExpanded` para o card que vem aberto por padrão
- Visual: `bg-white/5 border border-white/10 rounded-lg`, texto `slate-300`, touch target 48px

**Alternativa por página:** Onde a página já tem cards próprios (ex: dashboard com KPI cards), adicionar ícone ℹ️ em cada card existente que abre tooltip/popover com explicação. Um deles vem aberto.

**Dados mock — `PreviewGuard.tsx`:**
- Wrapper leve que envolve páginas
- Quando `isPreviewMode`: intercepta os hooks de data fetching ou renderiza com dados mock
- Abordagem recomendada: arquivo `previewMockData.ts` com dados estáticos por rota
- Cada página verifica `isPreviewMode` e usa mock data em vez de chamar API
- Dados devem ser realistas (nomes brasileiros, valores plausíveis, datas recentes)

**Mock data por página:**
- Dashboard: KPIs (142 visitantes, 38 leads, 26% conversão, R$ 4.200 faturamento)
- Leads: 5-10 leads fake com nome, telefone, origem (Instagram, WhatsApp), status
- Analytics: dados de gráfico simulados (últimos 7 dias com variação)
- Operações: 2-3 projetos fake com status e milestones

**CTA sticky no bottom:**
- Aparece em toda página quando `isPreviewMode`
- Texto: "Quero esse plano" ou "Ativar {nome do plano}"
- Full-width, 48px height, fixo no bottom com `safe-area-inset-bottom`
- Toque abre checkout inline (Tarefa 6)
- No mobile: considerar que MobileChatBar (56px) também fica no bottom — CTA fica acima

**Badge "Preview":**
- Pill discreta no topo da página: "Preview — {nome do plano}"
- Não obstrui conteúdo, apenas informa

---

## Observações importantes

- Não recriar nenhuma página. As páginas existentes renderizam normalmente — só muda a fonte de dados (mock vs real) e adiciona info cards.
- Os dados mock são estáticos — não precisam de API, não precisam de loading state. Renderização instantânea.
- O CTA sticky precisa conviver com a MobileChatBar no mobile. Posicionar acima dela (bottom: 56px + safe-area) ou integrar visualmente.
- O `PreviewGuard` não deve quebrar páginas que não têm mock data definido. Se não tem mock para aquela rota, renderiza a página normal com badge "Preview" apenas.

---

## Critérios de aceite

1. Visitor vê dados fake realistas ao entrar em qualquer página coberta pelo mock
2. Info card aparece com explicação do recurso, um vem expandido por padrão
3. "Leia mais" expande/colapsa o card
4. Card minimizado mostra ícone ℹ️ clicável
5. Badge "Preview" aparece discreto no topo
6. CTA sticky no bottom funciona e abre checkout
7. CTA convive com MobileChatBar no mobile sem sobreposição
8. Página sem mock data definido não quebra
9. Funciona no viewport 375px (Instagram WebView)
10. Testes Vitest: PreviewInfoCard renderiza/expande, PreviewGuard alterna mock/real

---

## Dependências

- Tarefa 3 (Sidebar dinâmica — para o visitor conseguir navegar entre páginas)

## Próxima tarefa → Spec 05 (MobileChatBar + Patch Chat)
