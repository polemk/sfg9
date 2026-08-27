# Tarefa 50: Roteamento React de Landing Pages Segmentadas

**Sprint:** LPs Segmentadas
**Estimativa:** 1 dia
**Tipo:** Frontend + Backend (Planos admin)

---

## Contexto
Temos que atender a funis diferentes vindos de anúncios diferentes, oferecendo o produto sob perspectivas específicas. Para solucionar isso de maneira unificada e sem integrações confusas fora da Stack nativa: usaremos a nossa própria exibição no `HomePage.tsx`. Ele fará o consumo da nossa `plansApi.list`, mas o Frontend terá um "Gate" para apresentar somente as chaves de dicíonario de copy, e planos referentes a cada rota.

---

## Onde começa
- No roteamento principal do frontend (App Router via `react-router-dom`).
- Componente base `HomePage` da aplicação, que atualmente carrega a Copy Global e exibe `PlansComparison`.

## Onde termina
- Renderização limpa ao acessar `/developer`, `/marketer` e `/engineer`.
- A API retorna os produtos da nossa própria model de Planos. O painel administrativo da Goat gerencia os nomes, tags/niche, e exibição por lá, pagamentos únicos incluídos.

---

## O que precisa ser feito

### No Frontend (Rotas e Repasse de Context)
1. Modificar nas rotas globais a inclusão dos sub-caminhos: `<Route path="/engineer" element={<HomePage niche="engineer" />} />`. (Repetir para os perfis).
2. Na hierarquia dos componentes visuais listados em `HomePage` (`HeroCampfire`, `PlansComparison`), repassar o prop do nicho em questão.
3. Em `PlansComparison`, utilizar a filtragem baseada na API nativa. Como `plansApi.list()` atualmente retorna planos gerais, aplique no frontend `.filter(plan => plan.target_niche === niche)` (ou mapeie via identifiers pre-estabelecidos como `BABY_GOAT_DEV`, `BABY_GOAT_ENG`) para que a tela não divulgue planos perdidos num contexto isolado.

### No Backend (Administramento)
Basta criar os registros reais (Rows no banco de dados):
1. Cadastrar novos planos limitados (pagamentos únicos) com chaves fáceis de filtrar na Listagem.
2. Não há necessidade alguma de integrar Asaas neste processo de exibição. O sistema de Plans que criamos no painel de administrador e sua API fornecem a estrutura.

---

## Critérios de Aceite
1. Um usuário entra em `goat.polemk.com/engineer` e logo vê o texto "Sua prancheta de desenvolvimento de automações, não perca tempo programando do zero". E vê SOMENTE o pacote correspondente à classe dele na lista de preços.
2. A página raiz genérica (`/`) continua mostrando os elementos padrões para o usuário não segmentado.
3. Não foi criada nenhuma lógica acoplada ao Asaas na LP. Apenas consumidas nossas próprias Endpoints internas com React Query.
