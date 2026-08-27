# Tarefa 2.2: Agent Asset Tools (Internal MCP)

**Sprint:** 2 - Agent Integration & Internal Tools
**Estimativa:** 1 dia
**Tipo:** Backend

---

## Contexto
O Agente IA agora tem o contexto em texto sobre a Operação que o Lead está interessado (Tarefa 2.1), porém Operações complexas possuem imagens, PDFs, catálogos (media assets). É inviável e oneroso trafegar a Base64 ou a URL gigante da imagem no prompt o tempo todo. A IA precisa descobrir e entregar o *Asset* correto para o Lead (ex: "Me veja uma foto do empreendimento!").
Nesta tarefa, vamos expor as ferramentas (Tools / Function Calling via MCP interno) para a IA. O agente poderá usar um comando próprio como `search_operation_assets("foto da fachada")`, e o backend responderá com uma lista de Mídias, incluindo o "shortcode" (ex: `[asset:SECURE12]`) de cada uma. Assim, o Agente passa o shortcode na conversa e o frontend tratará de converter o shortcode na UI.

---

## Onde começa
A integração de AI Agent (ex: OpenAI Assistants ou ChatCompletion) possui suporte a Tool Calling/Functions nativos. `OperationAsset` já possui a tabela preenchida com `shortcode`, `title`, `description` e vetores (`embedding`) persistidos de Tarefas anteriores.

## Onde termina
O modelo de linguagem (LLM) conseguirá acionar, via *Function Calling*, uma ferramenta nomeada `search_operation_assets(query)` ou `list_operation_assets()` no escopo do `FlowEngine` e `AgentService`. O resultado trará o `title` e o `shortcode`, permitindo que o Bot inclua nativamente a mídia recomendada durante a prosa (e.g., "Aqui está a planta baixa: [asset:BRTXZ9]").

---

## O que precisa ser feito

### No Backend

1. **Definição da Ferramenta**:
   Criar a Tool Specification (no formato exigido pelo Provider da IA atual, ex: JSON Schema do OpenAI) para uma função `search_operation_assets`. Ela deve receber o parâmetro `query` (a intenção de mídia que o cliente buscou: "planta", "vídeo").

2. **Implementação do Executor da Ferramenta**:
   Na classe encarregada pelas invocações de Tool (`ToolExecutor`), adicionar o método equivalente `execute_search_operation_assets(query, context)`:
   - Receber a _query_ gerada pelo Bot.
   - Embeber a _query_ gerando um vetor.
   - Usar `pgvector` para encontrar os Top 3 `OperationAsset` na qual a Operation bata com o escopo atual (via cosine similarity).
   - Retornar para o Bot o formato enxuto: `{ results: [{ title: "Foto", shortcode: "[asset:X1Y2]" }] }`.

3. **Restrição por Operation**:
   Garantir que os recursos pesquisados fiquem **obrigatoriamente limitados à `Operation` atual do Lead**. Nunca permita que um Lead da Operação X encontre assets da Operação Y por acidente vetorial, impondo assim um forte WHERE SQL.

### No Frontend
Não se aplica, focado 100% no fluxo do Agente no backend.

---

## Observações importantes
- Em vez de buscar todos os Assets para que o assistente analise, delegue o filtro para busca semântica no banco via `pgvector`. A IA só precisa providenciar a pergunta e o Job/Client retorna as prováveis correspondentes.
- Caso não hajam Assets cadastrados no sistema, certifique-se de que o Tool Execution retorne `[]` ordenado, para que o Prompt deduza naturalmente que "No momento não tenho nenhuma mídia para te enviar sobre isso."

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. Teste de request interceptado mostrando que o Agente "decidiu" (Function Call Trigger) chamar `search_operation_assets("fachada")` dada uma pergunta de "como é por fora?".
2. A listagem devolvida para a LLM pela implementação contendo apenas strings simples sem vazar URLs sensíveis.
3. Teste garantindo o isolamento da Operação via `where(operation_id: current_lead.operation_id)`.

---

## Dependências
- Tarefa 2.1: Agent RAG Context Injection (`spec-020-agent-rag-context.md`)
- Tarefa 1.2 e 1.3 já funcionais contemplando os Embeddings dos Assets prontos na base.

## Próxima tarefa
Tarefa 2.3: Frontend Asset Shortcode Parser (`spec-022-frontend-asset-parser.md`)
