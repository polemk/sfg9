# Tarefa 3: Seletor de Plano + Menu Dinâmico no Sidebar

**Sprint:** 1 — Visitor Preview
**Estimativa:** 1.5 dias
**Tipo:** Frontend

---

## Contexto

Este é o coração da experiência: o visitor seleciona um plano no sidebar e o menu muda instantaneamente para mostrar apenas os recursos daquele plano. É o mesmo conceito do "comandae" onde trocar o modo troca o menu — aqui trocar o plano troca o que o visitor vê.

Hoje o `Sidebar.tsx` monta o array `items[]` com spreads condicionais por role (`isOG`, `isVisitor`, `isPartner`). Para visitors, mostra apenas Dashboard, Leads e Analytics fixos. Com a nova lógica, os items passam a ser derivados das `menu_keys` do plano selecionado.

---

## Onde começa

- `Sidebar.tsx` (315 linhas) com menu por role
- `planPreviewStore` funcionando com `selectedPlan` e `activeMenuKeys()` (Tarefa 2)
- Design system do sidebar: bg `#0B0C10`, cor ativa `#39ff14` com glow, text `slate-300/400`
- Sidebar colapsa por padrão no mobile

## Onde termina

- Componente `PlanSelector` renderiza no sidebar abaixo do logo para visitors
- Trocar plano no seletor filtra os items do menu instantaneamente
- Dashboard sempre visível independente do plano
- Mobile funciona com sidebar colapsada (PlanSelector vira ícone com popover)

---

## O que precisa ser feito

### No Frontend

**Componente `PlanSelector`:**
- Renderiza dentro do sidebar, entre o logo e os nav links, APENAS quando `isPreviewMode`
- Mostra os planos disponíveis como lista compacta ou dropdown
- Cada plano exibe: título, preço, badge "Popular" se aplicável, contagem de recursos
- Plano ativo: borda `#39ff14` com glow, fundo sutil verde
- Touch target mínimo de 48px por item (Instagram WebView)
- Tap seleciona o plano via `setSelectedPlan()` do store
- Gerar referência visual no Stitch via DESIGN.md antes de implementar

**Sidebar.tsx — adaptação:**
- Criar mapa de `menu_key → { path, label, icon }` com todas as rotas possíveis do console
- Quando `isPreviewMode`: construir `items[]` a partir de `activeMenuKeys()` usando o mapa
- Dashboard sempre incluído (não depende de menu_key)
- Quando não é preview: manter lógica existente por role intacta
- Animação suave ao trocar plano: items entram com fade + translateY (só `opacity` e `transform`, GPU-friendly)

**Comportamento mobile:**
- Sidebar colapsada: PlanSelector vira ícone no topo (ex: Package icon) que abre popover com os planos
- Sidebar expandida (hamburger): PlanSelector aparece normalmente abaixo do logo

---

## Observações importantes

- Não remover a lógica existente de roles (`isOG`, `isPartner`). O preview mode é um branch alternativo que só ativa para visitors. Se o user não é visitor, sidebar funciona exatamente como antes.
- O mapa de `menu_key → rota` fica no frontend e é a source of truth do que cada key significa em termos de navegação. Se amanhã uma rota mudar, só precisa atualizar o mapa.
- Sidebar colapsada no mobile é o comportamento padrão atual — não mudar isso. O visitor abre o hamburger, vê o PlanSelector + menu filtrado, navega.

---

## Critérios de aceite

1. PlanSelector aparece no sidebar apenas para visitors (`isPreviewMode`)
2. Mostra todos os planos com preço e badge Popular
3. Plano ativo tem destaque visual diferenciado
4. Trocar plano atualiza o menu instantaneamente (sem reload)
5. Dashboard sempre visível independente do plano selecionado
6. Items do menu correspondem exatamente às `menu_keys` do plano
7. Sidebar funciona normalmente para users não-visitor (sem regressão)
8. Mobile: sidebar colapsada com PlanSelector como ícone + popover funciona
9. Touch targets ≥ 48px em todos os elementos do PlanSelector
10. Testes Vitest: PlanSelector renderiza para visitors, Sidebar filtra items por plano

---

## Dependências

- Tarefa 2 (Store com plano selecionado e activeMenuKeys)

## Próxima tarefa → Spec 04 (Info Cards + Dados Mock)
