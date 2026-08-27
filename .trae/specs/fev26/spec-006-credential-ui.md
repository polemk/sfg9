# Tarefa 006: UI de Credenciais

**Sprint:** 2 - Gerenciamento de Credenciais
**Estimativa:** 1 dia
**Tipo:** Frontend

---

## Contexto
Com o backend de credenciais pronto, o usuário precisa de uma interface para gerenciar suas chaves. Essa interface deve ser segura, intuitiva e seguir o padrão visual do painel administrativo.

**Valor para o usuário:** Facilidade em adicionar e remover chaves de API sem precisar mexer em código ou variáveis de ambiente.

---

## Onde começa
- Backend de credenciais (`/api/v1/credentials`) existe.
- Não há interface para chamar esses endpoints.

## Onde termina
- Nova página `/credentials` (ou aba em Configurações).
- Lista de credenciais cadastradas (com provider e chave mascarada).
- Modal/Formulário para adicionar nova credencial.

---

## O que precisa ser feito

### No Frontend

1.  **Service/API Client**:
    -   Adicionar métodos em `src/services/api.ts` (ou similar) para `getCredentials`, `createCredential`, `deleteCredential`.

2.  **Página de Listagem (`CredentialsPage.tsx`)**:
    -   **Design:** Tabela ou Grid de Cards (shadcn/ui).
    -   Colunas: Nome, Provedor (ícone OpenAI/Anthropic), Chave (ex: `sk-proj...`), Data Criação, Ações (Excluir).
    -   **Empty State:** "Nenhuma credencial cadastrada. Adicione uma para começar."

3.  **Modal de Adição (`CreateCredentialModal.tsx`)**:
    -   **Provider Select:** Dropdown com ícones (`OpenAI`, `Anthropic`, `Google Gemini`, etc.).
    -   **Name Input:** "Nome da Chave" (placeholder: "Minha API Produção").
    -   **Key Input:** Tipo `password` (com toggle de visibilidade).
    -   **Validação:** Campos obrigatórios.

4.  **Feedback UX**:
    -   Toast de sucesso ao criar.
    -   Dialog de confirmação ("Tem certeza?") ao excluir.
    -   Skeleton loading ao carregar a lista.

---

## Observações importantes
-   **Design System:** Usar componentes existentes (`Button`, `Table`, `Dialog`, `Input`) do shadcn/ui.
-   **Segurança Frontend:** NUNCA logar a chave digitada no console. Limpar o formulário após envio.
-   **UX Psychology:** Usar ícones de cadeado ou escudo para reforçar a segurança da página.

---

## Critérios de aceite

1.  **Listagem:**
    -   [ ] Carrega dados da API corretamente.
    -   [ ] Mostra loader durante o fetch.
    -   [ ] Formata data de criação amigavelmente.

2.  **Criação:**
    -   [ ] Valida campos vazios.
    -   [ ] Envia POST correto para API.
    -   [ ] Atualiza a lista automaticamente após sucesso.
    -   [ ] Fecha o modal após sucesso.

3.  **Exclusão:**
    -   [ ] Pede confirmação antes de apagar.
    -   [ ] Remove item da lista visualmente após sucesso.

---

## Dependências
-   Tarefa 005 (Backend de Credenciais).
