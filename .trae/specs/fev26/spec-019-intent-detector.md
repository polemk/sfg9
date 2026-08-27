# Tarefa 1.4: Intent Detector Engine

**Sprint:** 1 - RAG Foundation, Asset Repository & Intent Detector
**Estimativa:** 1.5 dias
**Tipo:** Backend

---

## Contexto
No fluxo atual do bot, a identificação de qual Operação o lead está interessado depende primordialmente de uma verificação exata de `keywords` digitadas na conversa. Esse modelo é frágil, pois não compreende sinônimos, erros de digitação ou o contexto real do usuário ("intent").
Com a base suportando `pgvector` e as Operações estruturadas vetorialmente, podemos evoluir para um `IntentDetectorService`. Ele receberá a mensagem inicial do usuário, vai convertê-la em embedding e executará uma busca de similaridade contextual para encontrar a Operação mais adequada com alta precisão.

---

## Onde começa
O sistema depende de matching de texto exato ou parcial de array strings (`keywords` na tabela operations). Os embeddings das Operations (Tarefas 1.1, 1.2 e 1.3) já existem no banco e estão populados.

## Onde termina
A detecção da intenção principal do bot usará busca vetorial (similaridade de cosseno) como método primário. A associação correta ficará mais aderente a intenções "abertas" e linguagem natural do dia a dia do lead.

---

## O que precisa ser feito

### No Backend

1. **Operations::IntentDetectorService**:
   Criar um serviço (`app/services/operations/intent_detector_service.rb`) responsável por:
   - Receber a primeira mensagem (texto/intenção) de um lead novo.
   - Chamar o provedor de embeddings (ex: OpenAI API) de modo *síncrono* para formatar o `query vector`. 
   - Executar a query SQL via `pgvector` usando o operador de similaridade de cosseno (`<=>`) para mapear contra os registros preenchidos da tabela `operations` e `operation_knowledges`.

2. **Threshold de Similaridade Criteriosa**:
   Evitar falso-positivos por aproximações matemáticas incorretas introduzindo um "threshold" (limite). Por exemplo: caso a intenção do usuário seja totalmente não relacional (ex: "gosto de pizza" direcionada ao bot imobiliário), a query da distância do vetor retornará baixo índice, e o serviço deve preferir resultar `nil` a induzir uma Operação forçada e errada.

3. **Injeção do Detector no Fluxo do Bot**:
   Atualizar a inteligência inicial receptiva (onde os Leads são classificados) para instanciar/chamar esse Detector antes de se ater ao fallback da regra de Keywords simples, garantindo a triagem inteligente daquele Lead para aquela Operação.

### No Frontend
Não se aplica diretamente, pois não afeta painel de UI visível de administradores até os próximos relatórios no roadmap V4.

---

## Observações importantes
- A consulta síncrona na OpenAI possui latência entre `200ms` a `400ms`. Se a API falhar ou der _timeout_, garanta implementar um bloco `rescue` que faça **fallback elegante (fail-soft)** recorrendo de volta ao método antigo das arrays `keywords`, para evitar downtime no bote do WhatsApp do cliente.
- Caso as Operações da empresa cheguem à casa dos milhares, considere no futuro criar um [índice HNSW](https://github.com/pgvector/pgvector#hnsw) do pgvector. Para agora, sequential scans estão perfeitamente otimizados.

---

## Critérios de aceite
Para considerar esta tarefa concluída, o dev deve demonstrar:

1. Testes automatizados robustos (`spec/services/operations/intent_detector_service_spec.rb`):
   - Deve encontrar a operação mesmo utilizando uma string que seja sinônimo com alguns erros gramaticais (exclusivo via mocks dos vetores no VCR/Webmock).
   - Deve retornar nulo para uma string caótica, demonstrando respeito ao Threshold fixado.
   - Simulando erro de API remota da OpenAi, que a aplicação não quebra em exceção pesada e reverte passivamente.
2. Execução manual via Console de Rails comprovando em ambiente de Dev que o `IntentDetectorService.call("Quero renovar minha assinatura amanhã urgente")` devolve a operação esperada (`OperationId`).

---

## Dependências
- Tarefa 1.3: Background Embeddings Generation (`spec-018-background-embeddings.md`)

## Próxima tarefa
Tarefa 2.1: Agent RAG Context Injection (`spec-020-agent-rag-context.md`)
