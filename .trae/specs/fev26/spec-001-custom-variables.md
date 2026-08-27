# Tarefa 1.1: Suporte a Variáveis Customizadas (Backend + Frontend)

**Sprint:** 1 - Core: Variáveis & Seletores
**Estimativa:** 1 dia
**Tipo:** Backend + Frontend

---

## Contexto
Atualmente, o Chat Builder permite o uso de variáveis do sistema (ex: `{{name}}`), mas não permite que o usuário crie suas próprias variáveis para armazenar dados específicos (ex: `{{lead_score}}`, `{{interesse_produto}}`). Ferramentas como ManyChat permitem isso para segmentação avançada.
O usuário precisa de uma forma de definir essas variáveis e de instruções claras sobre como inseri-las no fluxo.

---

## Onde começa
- `User` model existe mas não tem campo para definição de variáveis customizadas.
- `VariablePicker` no frontend lista apenas variáveis hardcoded do sistema.

## Onde termina
- Tabela `users` tem coluna `custom_variables` (JSONB).
- Endpoint API permite adicionar/remover variáveis customizadas.
- `VariablePicker` permite criar nova variável e lista as existentes.
- Usuário vê tooltip/instrução sobre como usar variáveis.

---

## O que precisa ser feito

### No Backend

1. **Migration**: Adicionar colunar `custom_variables` do tipo JSONB na tabela `users`. Default: `[]`.
2. **Model**: Expor `custom_variables` na entidade `User`.
3. **Controller**: Criar/Atualizar endpoint para modificar `custom_variables`. Pode ser uma ação no `UsersController#update` ou endpoint dedicado se preferir atomicidade.

### No Frontend

1. **API Client**: Adicionar método para atualizar variáveis customizadas do usuário.
2. **VariablePicker**:
    - Adicionar aba ou seção "Customizadas".
    - Botão "+ Criar Variável" que abre um input/modal simples.
    - Ao criar, chama API e atualiza lista local.
    - Adicionar ícone de "Info" (?) com tooltip explicando: "Use variáveis para salvar respostas do usuário e personalizar o fluxo."

---

## Observações importantes
- Persistência: As variáveis são definições (metadados). O *valor* da variável para cada lead continua sendo salvo no `context` da sessão (JSONB) como já funciona hoje. Esta tarefa é sobre *definir* quais variáveis existem para facilitar a seleção.
- Validação: Nomes de variáveis devem ser slug-friendly (sem espaços, minúsculas), ex: `minha_variavel`. O frontend deve converter "Minha Variável" para `minha_variavel` automaticamente ou validar.

---

## Critérios de aceite
1. O dev deve demonstrar a criação de uma variável chamada "Score do Lead".
2. O sistema deve salvar `score_do_lead` no backend.
3. Ao recarregar a página, a variável `score_do_lead` deve aparecer na lista do `VariablePicker`.
4. Ao clicar na variável, ela deve ser inserida no texto como `{{score_do_lead}}`.

---

## Dependências
Nenhuma.

## Próxima tarefa
Tarefa 1.2: Seletores CSS.
