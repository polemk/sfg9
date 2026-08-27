# Tarefa 2.3: AI Chat Lead Generator (Extração Mágica via IA)

**Sprint:** 2 - Intelligence & Lead Generation
**Estimativa:** 2.5 dias(s)
**Tipo:** Backend

---

## Contexto
Diferente da abordagem estruturada onde o builder usa nós (Tarefa 12, "Save to Lead") e preenche variáveis do tipo `{{user_name}}` explicitamente, em um atendimento nativamente fluido com *AI Agents* o usuário revela `nome`, `idade`, `produto de interesse` em um parágrafo jogado (e.g., "Opa, me chamo José, trabalho na Acme e queria orçar um plano anual pra minha empresa de 5 pessoas, meu email jose@acme.com"). O objetivo aqui é que o AI Agent extraia inteligentemente dados chave dessa sentença não guiada usando `Function Calling / Tool Use` do Claude ou OpenAI, populando a tabela de Leads automaticamente sem que haja nós lógicos no caminho.

---

## Onde começa
- O *AI Agent* responde conversacionalmente ao Lead ("Olá José! Entendi que você precisa de orçamento..."). 
- Contudo, a base de dados (`Leads`) do dono do negócio continua em branco. Ele tem que reler todas as transcrições do histórico e abrir o HubSpot manualmente se quiser os dados.

## Onde termina
- O backend de Agent injecta um **Array de Tools** nas chamadas ao provedor LLM. Entre as tools, existe uma chamada `upsert_lead_profile(name, email, company, intent)`.
- Se a IA detectar na conversa os parâmetros providos pelo usuário, a própria LLM sinaliza querer rodar a função com os argumentos detectados.
- O Backend intercepta o callback "tool_use", salva/processa os dados no DB (`Lead`), devolve um "tool_result" sucesso para a LLM, que continua a conversa ciente de que o CRM foi atualizado.

---

## O que precisa ser feito

### No Backend (Adaptação `Ai::AgentService`)
1. **Tool Definition:** Construir o JSON schema para as tools de extração de Lead.
   - Anthropic: `tools: [{ name: "capture_lead", description: "Use always when user provides identifiable info...", input_schema: { ... } }]`.
   - OpenAI equivalência: `tools: [{ type: 'function', function: { name: 'capture_lead' ... } }]`.
2. **Orquestração da Função (Tool Executor):** 
   - No `AgentService.respond`, se a resposta do provider for uma intenção de Tool Call `stop_reason: "tool_use"`, pare o retorno final para o frontend.
   - Trate o bloco `tool_use`. Usando os argumentos retornados pela IA, invoque o `Leads::Creator` informando os dados mapeados.
   - Construa um bloco `tool_result` indicando que salvou. Mande uma nova request (anexando essa última interação) pra LLM e receba o texto de fechamento ("Legal, José, anotei aqui e o time vai em breve falar com vc!").
3. **Controle de Sessão Acionável:** Para evitar sobrepujar o PostgreSQL chamando a Tool em TODA resposta, instruir a LLM estritamente só chamar Tool_Use para atualização efetiva baseada em novo contexto.

---

## Observações importantes
- Essa é uma das **features mais valiosas** para os clientes finais da AI9, é a fusão do atendimento com automação em background imperceptível.
- A abstração em torno da extração deve perdoar campos faltantes, permitindo campos opcionais em sua raiz de schema. Apenas usar o `session.lead` de chave primária.
- Essa tarefa é 100% server-side lógica de LangChain-like pattern. Se feita corretamente, na tela aparecerá para o usuário final apenas uma pausa ligeiramente maior para o processamento de duplo hop (1: Request User -> 2: Tool Call -> 3: Tool Result -> 4: Resposta Final).

---

## Critérios de aceite
1. O criador ativa uma flag no painel da AI: "Extrair Metadados Automaticamente" na aba Builder.
2. O usuário na ponta envia a mensagem: "Meu nome é Carlos Alberto e meu telefone é 1199999999".
3. A tabela `Leads` (que estava com id anônimo) tem suas properties "nome" e "telefone" preenchidas imediatamente logo após a resposta do bot sumir da rede.
4. O bot responde elegantemente incorporando a compreensão de que os dados foram anotados, e encorajando continuação.
5. Inspecionando o Terminal Backend de Log, observa-se claramente o loop secundário de `tool_use` / `function_call`.

---

## Dependências
- `AgentService` refatorado para suportar providers. (Já feito na Tarefa 009).

## Próxima tarefa
- Tarefa 3.1: New Lead List Dashboard
