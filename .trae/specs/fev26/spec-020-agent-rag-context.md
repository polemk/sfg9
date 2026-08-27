# Tarefa 2.1: Agent RAG Context Injection

**Sprint:** 2 - Agent Integration & Internal Tools
**Estimativa:** 1 dia
**Tipo:** Backend

---

## Contexto
Com a intenção do Lead já detectada (via `IntentDetectorService` - Tarefa 1.4) e a `Operation` definida, o Agente de IA precisa ter o conhecimento daquela operação específico embutido no seu cérebro momentâneo.
Para isso, devemos resgatar o `OperationKnowledge` correspondente no banco (que pode ser atrelado via a Operation identificada que agora reside no Lead) e inseri-lo dinamicamente no System Prompt do Bot, garantindo o "Retrieval" da arquitetura RAG.

---

## Onde começa
O `AgentService` ou a orquestração do AI Gateway atual gera respostas baseadas num `system_prompt` fixo (cadastrado no `ChatFlow` pelo painel de Builder). A Operação do Lead já é conhecida no banco (`lead.operation_id` etc).

## Onde termina
Toda vez que uma nova mensagem entrar na fila de processamento do LLM (ex: `AgentService`), o código deve buscar a `OperationKnowledge` do banco pertinente ao lead. Parte desse texto (ou os blocos mais semanticamente relevantes caso seja um texto massivo) deve ser apensado ou injetado perfeitamente no prompt técnico, municiando a inteligência para uma resposta embasada, factível e focada na Operação atual.

---

## O que precisa ser feito

### No Backend

1. **RAG Context Fetcher**:
   No ciclo de vida do envio do prompt (por exemplo, na preparação do `messages_array` enviado para API OpenAI/Anthropic), identificar o `Operation` atual atrelado àquela submissão (seja via sessão, via lead atrelado à conversa ou via Intent passado pelo Flow Node).
2. **Injeção de Prompt**:
   Resgatar o registro `OperationKnowledge` via ActiveRecord. Pegar a sua coluna `content`. 
   Pré-processar (ex: colocar delimitadores `<knowledge> ... </knowledge>`) e inserir dinamicamente antes do `system_prompt` principal configurado.

   *Exemplo conceitual*:
   ```markdown
   "Você é o Mario, suporte Purp.
   <knowledge>
     {{ operation_knowledge.content }}
   </knowledge>
   Responda apenas com base nas informações fornecidas."
   ```

3. **Fallback Resiliente**:
   Se a Operation não possuir uma Knowledge populada ou não houver operation atrelada, o Agente de IA deve prosseguir e responder de forma genérica valendo-se apenas do `system_prompt` principal dele, sem causar indisponibilidades ou retornos `500`.

### No Frontend
Não se aplica. É puramente contextual e manipulado em camada de Controller/Service backend.

---

## Observações importantes
- Fique atento aos limites de token (Context Window). Injetar o texto da `OperationKnowledge` cru pode ultrapassar a janela de um modelo pequeno (como GPT-3.5 ou Haiku se a Operation for um PDF imenso). Assumimos por enquanto que o texto do lojista é um resumo razoável. Para a V4, limite o resgate aos textos vitais, e caso exista risco, podemos evoluir para injetar *apenas* os "Chunks" semanticamente similares com a última pergunta do User, consolidando o RAG puro. Para o escopo dessa feature, a injeção do bloco completo atende.

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. Modificando um `OperationKnowledge` teste de um Lead, mandar uma mensagem pelo bot do Whatsapp e comprovar via logs submetidos à provedora de IA (API) que os delimitadores `<knowledge></knowledge>` e seu conteúdo trafegaram no Request Body.
2. A IA ser capaz de responder corretamente fatos que *apenas não existem* fora do `content` de sua própria operação (testar com dados fictícios).
3. Testes unitários do orquestrador de chat (`AgentService`) provando a inclusão e o não-quebra em caso de `nil`.

---

## Dependências
- Tarefa 1.4: Intent Detector Engine (`spec-019-intent-detector.md`)
- Ter ao menos um Agente (da Fase V3) funcionando minimamente na master.

## Próxima tarefa
Tarefa 2.2: Agent Asset Tools (Internal MCP) (`spec-021-agent-asset-tools.md`)
