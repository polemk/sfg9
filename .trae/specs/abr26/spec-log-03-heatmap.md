# Tarefa Log 03: Frontend - Correção do Limite de Scroll do Heatmap

**Sprint:** 3 - Otimizações Visuais e Heatmap
**Estimativa:** 0.5 dia(s)
**Tipo:** Frontend

---

## Contexto
Temos um recurso de visualização (Heatmap) na rota `/admin/metrics` que desenha pontos de clique e movimentação do mouse capturados através do event logger do site. Contudo, foi relatado que este heatmap apresenta um bug: ele só desenha e sobrepõe os dados de calor até "uma parte do scroll" (ou seja, apenas na viewport inicial ou numa altura fixa calculada na inicialização do script). Isso impede de estudar o comportamento do usuário no meio e final das páginas analisadas.

Precisamos debugar o motivo dessa âncora/height incorreto e consertá-lo para que a camada do heatmap cubra toda a extensão vertical do documento alvo ou permita que os cliques mais "profundos" sejam dispostos na coordenada `y` apropriada no overlay.

---

## Onde começa
- Componente Heatmap (ou equivalente) utilizado na tela de Métricas/Admin.
- Os logs armazenados via Event Logger possuem coordenadas (`x`, `y`) da ação.

## Onde termina
- Camada gráfica (overlay do Heatmap) cobrindo e plotando pontos em toda extensão (height) da renderização capturada, independente do `scrollY` onde o clique ocorreu.

---

## O que precisa ser feito

### No Frontend

1. **Investigar Cálculo do Height da Renderização**
   - Verificar como o container do mapa de calor está estilizado (ex: `height: 100vh`, erro comum). O heatmap container precisa abraçar `100%` da altura do conteúdo real escalado.
   - Analisar o redimensionamento do canvas ou library de heatmap quando a janela altera seu tamanho base.

2. **Ajuste de Cálculo de Scroll nas Coordenadas (`event.pageY` vs `event.clientY`)**
   - Validar se a captura do frontend de origem (o script embedado no cliente) está enviando os valores corretos. Ele deve capturar `pageY` e `pageX` relativos ao documento total, e não `clientY` / `clientX` que se restringe à janela visível, senão um clique no rodapé terá as mesmas coordenadas Y que o topo.
   - Ajustar o parser/mapping no gerador do gráfico de métricas para refletir essa escala de forma acurada com a visualização apresentada na UI do administrador.

3. **Manejo Dinâmico da Camada**
   - Se a tela alvo sendo renderizada para teste de heatmap utilizar lazy loading ou mudar de tamanho durante a sessão, aplicar `MutationObserver` ou `ResizeObserver` no container para recalcular a base do canvas do Heatmap.

---

## Observações importantes
> [!TIP]
> Caso a biblioteca de heatmap utilizada dependa estritamente de valores absolutos em pixel, considere normalizar (fazer um ratio) do `(X / DocumentWidth) * 100` e `(Y / DocumentHeight) * 100` e usar porcentagens na hora da plotagem gráfica. Assim você dribla diferenças absurdas de resolução entre o visitante mobile/desktop e quem está visualizando o admin.

> [!CAUTION]
> Ao mudar scripts no tracker publico de events (caso o bug esteja na fonte de envio), lembre-se que os dados passados (os já capturados) vão precisar de um tratamento de fall-back ou serão descartados/corrompidos para telas longas, já que tinham o `y` limitado.

---

## Critérios de aceite
1. O dev deve visualizar um heatmap para uma tela/landing page comprovadamente longa (mais de 2x a altura do monitor).
2. O dev deve mostrar os dados plotados aparecendo no fundo (bottom) da página com a rolagem do mouse.
3. Não deve existir cortes na parte inferior do canvas de cor ou quebras no alinhamento quando há scroll pelo container administrativo.

---

## Dependências
- Nenhuma dependência das Specs 01 ou 02, pode ser desenvolvido de forma isolada, a não ser que mude a estrutura dos dados guardados.

## Próxima tarefa
- Documentação da Nova View do Analytics finalizada.
