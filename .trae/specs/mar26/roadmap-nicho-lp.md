# Sprint: LPs Segmentadas por Nicho & Posicionamento

**Projeto:** ai9 / monorepo
**Estimativa:** 4–6 dias
**Referência de Implementação:** Next.js Routing / Landing Pages Segmentadas

---

## Contexto

Atualmente temos uma única Landing Page tentando se comunicar com todos os profissionais. Porém, as dores de aprendizado e uso do produto diferem entre um **Marketer**, um **Dev**, e um **Engenheiro**. 

O objetivo desta sprint é **componentizar a HomePage atual e segmentar o roteamento** para que o usuário caia num funil hiper-específico (e.g., `goat.polemk.com/engineer`). Todo o sistema se nutrirá nativamente da nossa própria API interna de Planos (`plansApi`). Não há necessidade de integrações externas como Asaas nesta camada de visualização/venda. Apenas exibimos planos com um modelo de pagamento único, criados internamente e etiquetados para o respectivo nicho.

---

## O Fluxo

```
Ad/UTM (Ex: Instagram de Engenharia)
        ↓
goat.polemk.com/engineer
(Copy: "Crie suas próprias ferramentas de gestão e automações...")
        ↓
API de Planos Interna (plansApi.list)
        ↓
Filtramos e exibimos apenas os planos (pagamento único) pertinentes ao Nicho "Engenheiro"
```

---

## Tarefa 1: Roteadores Dinâmicos no React (React Router)

**Contexto**
Precisamos de rotas nativas acessando a estrutura base da Landing Page atual (`HomePage.tsx`), mas envelopadas com propriedades contextuais do Nicho.

**O que fazer:**
1. Em `App.tsx` (ou nas definições de rotas), criar as rotas `/marketer`, `/engineer` e `/developer` apontando para o componente base.
2. Injetar na UI base um parâmetro `niche` (ex: `niche="engineer"`).
3. Na `PlansComparison`, filtrar o resultado de `plansApi.list()` para renderizar **apenas** os planos criados para aquele Nicho.

---

## Tarefa 2: Cadastros de Planos no Backend

**Contexto**
Basta usar a nossa tabela de Planos atual. Tudo ocorre do nosso lado, sem malabarismo externo.

**O que fazer:**
1. Via Goat Admin, cadastrar os planos específicos com pagamento único (non-subscription). 
2. Cada plano terá sua própria nomenclatura. O plano com a tag/identificador adequado ao nicho será espelhado no Frontend isolado pela regra recém-criada de filtragem.

---

## Tarefa 3: Componentização da Copy e Tema "Pro Max"

**Contexto**
O design precisa manter a fluidez e os brilhos de "UI UX Pro Max" da Rule 8 mas os Redatores e as Dores são trocadas.

**O que fazer:**
Isolar os componentes textuais de `HomePage.tsx` num arquivo de dicionário, de modo que `HeroCampfire.tsx` ou afins reajam à prop `niche`.
- **Engineer Copy:** O foco é usar o sistema como uma prancheta de criação lógica. Semelhante a usar AutoCAD. Ele não precisa construir a infraestrutura do zero para os workflows do escritório dele.
- **Marketer Copy:** Foco em gerir e automatizar canais de lead escaláveis sem depender de desenvolvedores para cruzar o backend de suas ferramentas.
- **Dev Copy:** Boilerplate as a service. Saltar a parte chata, não reinventar a roda, pular o setup e focar em ganhar velocidade de entrega ou construir produtos próprios.

---

## Próximos Passos
Ver as referências nas `spec-050` e `spec-051` atualizadas.
