# Tarefa 008: Parâmetros Avançados (Agente AI)

**Sprint:** 3 - Integração e Configuração Avançada
**Estimativa:** 1 dia
**Tipo:** Frontend

---

## Contexto
Agentes de IA precisam de ajustes finos (temperatura, tokens), mas a maioria dos usuários não entende o que "Top P" ou "Frequency Penalty" faz.
Precisamos não apenas oferecer os controles, mas **educar** o usuário sobre o impacto de cada mudança, usando linguagem clara, exemplos práticos e feedback visual.

**Valor para o usuário:** Empoderamento. O usuário entende que aumentar a temperatura deixa o bot "mais criativo" e diminuir "mais robótico", sem precisar ler documentação técnica externa.

---

## Onde começa
- `AIAgentConfigPanel` existe com campos básicos.
- Não existem controles avançados.

## Onde termina
- Seção "Configurações Avançadas" (Accordion).
- Controles deslizantes para Temperature, Top P, Frequency Penalty, Presence Penalty e Max Tokens.
- Cada controle possui Tooltips ricos e/ou descrições "helper text" que mudam dinamicamente ou explicam o conceito com exemplos.

---

## O que precisa ser feito

### No Frontend (`AIAgentConfigPanel`)

1.  **Componente Reutilizável `AIParameterSlider`**:
    -   Props: `label`, `value`, `onChange`, `min`, `max`, `step`, `description`, `lowLabel`, `highLabel`, `examples`.
    -   Layout: Label + Valor numérico atual.
    -   Slider do shadcn/ui.
    -   Legendas nas extremidades (ex: "Conservador" esq, "Criativo" dir).
    -   **HoverCard/Tooltip Rico**: Ao passar o mouse no Label ou ícone de ajuda `(?)`.

2.  **Parâmetros a Implementar**:

    | Parâmetro | Range | Descrição Educativa | Exemplo Baixo | Exemplo Alto |
    | :--- | :--- | :--- | :--- | :--- |
    | **Temperature** | 0.0 - 2.0 | Controla a aleatoriedade e criatividade. | **0.2**: Respostas determinísticas, focadas, "robóticas". Ótimo para suporte técnico e dados. | **1.2**: Respostas inusitadas, criativas, imprevisíveis. Ótimo para brainstorming e poemas. |
    | **Top P** | 0.0 - 1.0 | Filtra a diversidade do vocabulário. Combine com temperatura para refinar. | **0.1**: Usa apenas as palavras mais óbvias e comuns. Texto muito simples. | **0.9**: Permite vocabulário mais rico e raro. Texto mais natural e variado. |
    | **Max Tokens** | 1 - 4096+ | Limite máximo de tamanho da resposta. | **100**: Respostas curtas, direto ao ponto. | **2000**: Textos longos, ensaios, explicações detalhadas. |
    | **Presence Penalty** | -2.0 - 2.0 | Evita repetir **tópicos** já mencionados. | **-2.0**: Tende a ficar no mesmo assunto. | **2.0**: Força a mudar de assunto, evita "círculos". |
    | **Frequency Penalty** | -2.0 - 2.0 | Evita repetir **palavras** verbatim. | **-2.0**: Pode repetir frases exatas. | **2.0**: Evita repetição de palavras, vocabulário mais vasto. |

3.  **Lógica Visual**:
    -   Se Temperature for alterado, mostrar um "feedback instantâneo" (ex: mudar ícone de 😐 para 🤪).
    -   Manter defaults sensatos (`Temp: 0.7`, `Top P: 1`, `Penalties: 0`).

4.  **Botão "Resetar Defaults"**:
    -   Para caso o usuário se perca nas configurações.

---

## Observações importantes
-   **UX Writing:** Não use "Nucleus Sampling" como título principal. Use "Diversidade (Top P)". Use termos amigáveis.
-   **Conflitos:** Explicar (tooltip) que alterar Temperature E Top P juntos pode ter resultados inesperados. (Recomendação OpenAI: altere um ou outro).

---

## Critérios de aceite

1.  **Educativo:**
    -   [ ] Passar o mouse no `(?)` da temperatura mostra explicação clara: "Controla a aleatoriedade...".
    -   [ ] Sliders têm labels nas pontas ("Preciso" <-> "Criativo").
2.  **Funcional:**
    -   [ ] Todos os 5 parâmetros persistem no JSON `agent_config`.
    -   [ ] Reset button volta para os valores padrão.
    -   [ ] Inputs numéricos ao lado dos sliders permitem digitação exata.

---

## Dependências
-   Tarefa 004 (Base).
