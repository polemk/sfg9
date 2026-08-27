# Tarefa 1.3: Background Embeddings Generation

**Sprint:** 1 - RAG Foundation, Asset Repository & Intent Detector
**Estimativa:** 1.5 dias
**Tipo:** Backend

---

## Contexto
Para habilitar a busca semântica em todo o conhecimento criado para a Operação, o texto precisa ser transformado em um "vetor de embeddings" numérico. Como a geração de embeddings depende de chamadas de rede para APIs externas (ex: OpenAI `text-embedding-ada-002` ou similar), realizar esse processo de forma síncrona durante a requisição web cria gargalos de performance e timeouts.
A solução é desacoplar esse processamento enviando o trabalho para o Sidekiq/ActiveJob. Assim, o usuário salva os textos/ativos instantaneamente, e o sistema os torna "buscáveis" em background logo em seguida.

---

## Onde começa
As tabelas `OperationKnowledge` e `OperationAsset` (Tarefa 1.2) existem na base de dados com as colunas do tipo `vector` vazias. O projeto já possui o Sidekiq configurado para o ActiveJob.

## Onde termina
Jobs assíncronos processarão qualquer texto novo ou atualizado, convertendo-os em vetores e persistindo no banco. Há também um mecanismo de fallback e tolerância a falhas na API de embeddings (retentativas nativas do Sidekiq).

---

## O que precisa ser feito

### No Backend

1. **Client do Provedor de Embeddings**:
   Criar um pequeno serviço client ou envolver a chamada API (ex: usando gem `ruby-openai` ou Faraday direto) responsável por submeter uma string e retornar um array de floats.
   
2. **Criação dos Jobs**:
   Criar um job (ex: `GenerateKnowledgeEmbeddingJob`) que recebe o ID do `OperationKnowledge`. O job busca o texto no banco, chama a API de embedding e salva o vetor resultante na coluna `embedding`.
   Repetir ou generalizar o padrão para `OperationAsset` (usando o título e descrição combinados como texto alvo para obter os embeddings de busca do arquivo).

3. **Gatilhos (Callbacks) Automáticos**:
   Adicionar um callback `after_commit, on: [:create, :update]` nos modelos `OperationKnowledge` e `OperationAsset`.
   O callback **só deve enfileirar o Job** se houver alteração significativa no conteúdo de texto (para evitar chamadas desnecessárias à API). Por exemplo: `if saved_change_to_content?`.

### No Frontend
Não se aplica diretamente, porém o design UX pode futuramente prever um estado "Processando busca semântica..." caso a indexação seja necessária para feedback visual imediato. Para o escopo desta tarefa, apenas o backend é aplicável.

---

## Observações importantes
- Em requisições de API de LLMs podem ocorrer limites de taxa (Rate Limits - 429). Utilize a retentativa exponencial nativa do Sidekiq; certifique-se de que o Job é idempotente.
- Se a coluna de embedding falhar de ser atualizada, a busca semântica apenas não encontrará este trecho específico, mas o sistema como um todo não vai cair. Tratar exceções sem pânico sistêmico, deixando o Sidekiq no status retry.

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. A criação de um novo `OperationKnowledge` pelo console, atestando via logs que o Job correspondente foi enfileirado (`Enqueued GenerateEmbeddingJob...`).
2. Após o processamento do Sidekiq, uma query na base de dados validando que a coluna `embedding` do registro criado agora possui valores floats ao invés de Nulo.
3. Simulando num RSpec uma atualização de texto do `OperationKnowledge`, provando que um novo requesito API foi mockado pelo VCR/WebMock.
4. Simulando uma atualização apenas de "status ativo" (sem tocar no texto) provando que o Job **NÃO** foi enfileirado acidentalmente, salvando cota de API.

---

## Dependências
- Tarefa 1.2: OperationKnowledge & OperationAsset Models (`spec-017-operation-knowledge-asset.md`)

## Próxima tarefa
Tarefa 1.4: Intent Detector Engine (`spec-019-intent-detector.md`)
