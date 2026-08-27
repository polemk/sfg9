# Tarefa 2: Store Zustand + Preview Mode

**Sprint:** 1 — Visitor Preview
**Estimativa:** 0.5 dia
**Tipo:** Frontend

---

## Contexto

O visitor precisa escolher um plano e o console inteiro reage a essa escolha: menu filtra, páginas mostram preview, CTAs mudam. Para isso, precisa de um estado global que diga "qual plano está selecionado" e "estamos em modo preview?".

O projeto já usa Zustand (`authStore.ts`) e React Query para data fetching. O user já tem `user_type_slug` disponível via `useAuthStore()`. A API da Tarefa 1 fornece os planos.

---

## Onde começa

- `authStore.ts` existe com `user`, `isAuthenticated`
- User tem `user_type_slug` (ex: `'visitor'`, `'og'`, `'partner'`)
- API `GET /api/v1/public/plans/preview` funcionando (Tarefa 1)
- React Query já configurado no projeto

## Onde termina

- Store `planPreviewStore` criado e funcional
- Hook de inicialização carrega planos via React Query
- `isPreviewMode` é `true` para visitors, `false` para demais
- Plano selecionado persiste entre navegações via `localStorage`
- Outros componentes (Sidebar, páginas) podem consumir o store

---

## O que precisa ser feito

### No Frontend

**Store** em `frontend/src/store/planPreviewStore.ts` com Zustand:

Estado necessário:
- `plans` — array de planos vindos da API
- `selectedPlan` — plano ativo (ou null durante loading)
- `isPreviewMode` — boolean derivado do user type
- `activeMenuKeys()` — getter que retorna as `menu_key` do plano selecionado (filtrando nulls)

Comportamentos:
- `setSelectedPlan(plan)` persiste `plan.id` no `localStorage` (key: `ai9_preview_plan_id`)
- Se tem ID salvo no localStorage e planos carregados, restaurar a seleção
- Se nenhum plano selecionado e tem planos disponíveis, auto-selecionar o `is_popular` ou o primeiro
- Se user não é visitor, `isPreviewMode` é `false` e o store fica inerte

**Hook de inicialização** em `frontend/src/hooks/usePlanPreview.ts`:
- Usa React Query para fetch dos planos
- No sucesso, seta os planos no store
- Detecta `isPreviewMode` a partir do `user_type_slug` do `authStore`
- Chamar esse hook no `Layout.tsx` ou `App.tsx` para garantir disponibilidade global

---

## Observações importantes

- O store deve funcionar sem quebrar quando `plans` está vazio (loading state). Componentes consumidores devem lidar com `selectedPlan === null`.
- Não usar `sessionStorage` — o visitor pode fechar e voltar, e o plano selecionado deve persistir.
- O `isPreviewMode` não deve depender apenas do store — deve ser derivado do user type a cada render, caso o user type mude (ex: após compra, visitor vira client).

---

## Critérios de aceite

1. Store criado e exportando `usePlanPreviewStore`
2. `isPreviewMode` retorna `true` para user com `user_type_slug === 'visitor'`
3. `isPreviewMode` retorna `false` para `og`, `client`, `partner`
4. Selecionar plano persiste entre navegações (recarregar página mantém seleção)
5. Auto-seleciona plano popular quando nenhum está selecionado
6. `activeMenuKeys()` retorna array de strings sem nulls
7. Funciona sem erro quando API ainda não respondeu (plans vazio)
8. Testes Vitest cobrindo: seleção, persistência, auto-seleção, activeMenuKeys

---

## Dependências

- Tarefa 1 (API de planos) precisa estar pronta para o fetch funcionar

## Próxima tarefa → Spec 03 (Seletor de Plano + Menu Dinâmico)
