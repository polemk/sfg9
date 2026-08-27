# Tarefa 030.6: Agentic Mode — Menu Item + Sidebar Persistente

**Sprint:** 3 — Agentic Mode + Widget
**Estimativa:** 1 dia
**Tipo:** Frontend

---

## Contexto

No `pkbot`, o agente era acessado via item no menu. No `comandae`,
queremos o mesmo padrão — sem a esfera flutuante no canto direito.

O agente deve estar acessível de duas formas:
1. **Item "Modo Agente"** no menu principal (sidebar esquerda)
2. **Chat lateral persistente** que fica aberto enquanto o usuário navega

---

## Onde começa

- Menu lateral do `comandae` já renderiza items com ícones
- Widget de chat já existe no NavKit (AI Chat Widget)
- `AgentService` + ChatFlow "Nathy" funcionando (Spec 030.5)

## Onde termina

- Esfera flutuante removida
- Menu tem item "Modo Agente" com ícone
- Ao clicar, abre sidebar de chat à direita que persiste entre páginas

---

## O que precisa ser feito

### 1. Remover esfera flutuante

Identificar e remover o componente de botão circular (FAB) no layout.

### 2. Adicionar item no menu

No componente de menu/sidebar principal, adicionar:
```tsx
{
  icon: <Bot />,  // lucide-react
  label: "Modo Agente",
  path: null,  // não navega — abre sidebar
  onClick: () => toggleAgentSidebar()
}
```

### 3. Sidebar de Chat Persistente

Componente `AgentSidebar` que:
- Abre à direita como drawer/panel (não substitui a página)
- Persiste entre navegações (não desmonta ao trocar de rota)
- Contém o chat completo (histórico, input, envio de áudio/imagem)
- Redimensionável (drag handle) ou largura fixa (~400px)
- Estado aberto/fechado em Zustand para persistir

### 4. Integração com AgentService

O sidebar usa o mesmo endpoint `POST /api/v1/public/chat` (ou novo endpoint
autenticado `POST /api/v1/chat/agent`) para se comunicar com o Nathy.

---

## Critérios de aceite

1. Menu tem item "Modo Agente" com ícone Bot
2. Clicar abre sidebar de chat à direita
3. Sidebar persiste ao navegar entre páginas
4. Enviar mensagem retorna resposta do agente
5. Esfera/FAB flutuante não existe mais

---

## Dependências

- Spec 030.5 (ChatFlow Nathy funcionando)
- Menu/sidebar existentes no frontend

## Próxima tarefa → Spec 030.7
