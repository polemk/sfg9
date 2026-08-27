# Tarefa 029.5: Interface do Usuário (Bot Rules / Keywords)

**Sprint:** 2 - Aquisição de Leads via Comentários no Instagram
**Estimativa:** 1 dia
**Tipo:** Frontend + Backend (API Simples)

---

## Contexto
Com o mecanismo de deduplicação e match de palavras-chave criados no Backend, o proprietário do Bot/Agente de IA precisa ser capaz de cadastrá-las visualmente, sem precisar do console Ruby. Essa tela fará parte das configurações individuais de um Chatbot ("Agents" no Ai9). Nela, ele dirá: "Quando comentarem a palavra X no instagram, dê esse Reply Txt".

---

## Onde começa
- Tabelas de Keywords já criadas.
- Aplicação React já possui navegação para os Detalhes/Configurações do Agente.

## Onde termina
- Interface na aba de configurações do Agent (ou no Painel lateral / Subpágina) para listar, criar, inativar e editar as Keywords.
- Endpoint de Gravação Ativo no Backend Grape (`/api/v1/bots/:id/comment_keywords`).

---

## O que precisa ser feito

### No Backend

1. **Controller `CommentKeywords`:**
   - `GET /api/v1/bots/:bot_id/comment_keywords` (Listar)
   - `POST /api/v1/bots/:bot_id/comment_keywords` (Criar)
   - `PUT /api/v1/bots/:bot_id/comment_keywords/:id` (Ativar/Inativar/Editar resposta)
   - `DELETE ...` (Apagar)
   - A resposta da API deve adotar o padrao de `Api::Entities`.

### No Frontend

1. **UI Listagem e Input:**
   - Adicionar uma "Tab" ou "Card" nas configurações do Robô: "Automação de Comentários no Instagram".
   - Tabela (semelhante ao Shadcn Data Table) listando as keywords ativas.
   - Botão "Nova Palavra-chave" -> Abre um Modal/Sheet.
     - Campo 1: Palavra (String, obrigatório, ex: "Quero").
     - Campo 2: Correspondência Exata (Switch boolean default=off).
     - Campo 3: Mensagem de Resposta Direta (Textarea obrigatório). Explique na tooltip que essa é a primeira mensagem que o Lead recebe na DM. Após isso, a AI comum assume.

2. **Integração:**
   - Interligar com a API.
   - Gerar React Query mutators com tratamento de Loader/Toasts.

---

## Observações importantes
- Mantenha simples. Não estamos construindo um Typeform/Flow Builder gigantesco para Comentários como no Manychat, é uma aba direta e reta atrelada ao Agente. Apenas os botões de CRUD padrão.

---

## Critérios de aceite
O dev deve demonstrar que:
1. Criou uma nova keyword na UI com a palavra "Desconto" e escreveu a frase "Enviado o cupom!".
2. Ao recarregar a tela, a keyword permanece listada.
3. Ela é corretamente inserida no Backend ligada como "pertencente àquele Bot Id".
4. Ao rodar o Webhook de Teste (da Tarefa 29.4) usando a palavra recém-criada via UI, a resposta privada é acionada. (Fim da jornada End-to-End).

---

## Dependências
- Backend da Sprint 2 - Tarefas 029.1x.

## Próxima tarefa
- **Fim da Sprint 2.**
- **Tarefa 030.1**: Mudar a forma com que as RESPOSTAS MANUAIS e DO AGENTE IA saem, garantindo que usem a via correta Omnichannel baseando-se nesse novo Hub de entrada.
