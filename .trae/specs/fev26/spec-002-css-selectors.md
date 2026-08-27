# Tarefa 1.2: Sugestões de Seletores CSS (Frontend)

**Sprint:** 1 - Core: Variáveis & Seletores
**Estimativa:** 0.5 dia
**Tipo:** Frontend

---

## Contexto
O nó de "Redirect" possui a ação "Scroll To", que requer um seletor CSS (ID) do elemento alvo. Usuários não técnicos (ou mesmo devs com pressa) não sabem os IDs das seções do site (Hero, Pricing, Contact, etc.).
Precisamos facilitar isso oferecendo uma lista pré-definida de âncoras comuns usadas em nossos layouts (Main Site, Admin, Visitor Panel).

---

## Onde começa
- `RedirectNode` tem um input de texto simples para `target`.

## Onde termina
- `RedirectNode` usa um componente `SelectorPicker` (novo ou adaptado) que mostra uma lista categorizada de seletores.

---

## O que precisa ser feito

### No Frontend

1. **Componente SelectorPicker**:
    - Criar componente similar ao `VariablePicker`.
    - Dados estáticos (hardcoded) organizados por contexto:
        - **Main Site**: `#hero`, `#features`, `#pricing`, `#testimonials`, `#contact`, `#footer`
        - **Admin**: `#topbar`, `#sidebar`, `#content`
        - **Visitor**: `#chat-widget`, `#proposal-view` (exemplos ilustrativos)
    
2. **Integração no RedirectNode**:
    - Substituir (ou complementar) o input de texto do `target` no `PropertiesPanel`.
    - Ao selecionar um item da lista, preencher o input com o valor (ex: `#pricing`).

---

## Observações importantes
- Não é necessário fazer "scraping" do site real neste momento. A lista é uma convenção de nomes que usamos nos templates.
- Manter a opção de digitação livre para casos avançados.

---

## Critérios de aceite
1. O dev deve demonstrar no Redirect Node a opção "Scroll To".
2. Deve aparecer um botão/dropdown para "Sugerir Seletor".
3. Ao selecionar "Pricing (#pricing)", o campo alvo deve ser preenchido com `#pricing`.

---

## Dependências
Nenhuma.

## Próxima tarefa
Tarefa 2.1: Log de Execução.
