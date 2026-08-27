# Tarefa 040.2: Normalização e Anti-Spam de Eventos e Scroll (High Watermark)

**Sprint:** 3 — Telemetria Comportamental & Mapa de Calor  
**Estimativa:** 1 dia  
**Tipo:** Frontend + Backend (Ajuste de Payload)

---

## Contexto

Atualmente o tracker engatilhado na base do aplicativo (ou landing pages) reporta as interações à medida rápida que acontecem sem filtro semântico de inteligência comportamental. Isso transborda o banco de dados enviando: "Scroll 25%", "Scroll 26%", "Scroll 50%", "Scroll 75%", e "Scroll 90%", tudo no mesmo segundo se o usuário deu uma "scrollada" vigorosa com o mouse. Isso torna o log inútil para uso estatístico, já que 90% dos dados são spam da mesma leitura de tela.

O High Watermark, atrelado com Debounce (atraso intencional de envio), age de forma que o sistema memorize a profundidade MÁXIMA que o visitante acessou a tela num quadro de tempo, consolidando em um único pacote informativo e com nomenclatura semântica clara.

---

## Onde começa

1. O projeto interceptador React/Vite de Eventos dispara `POST` assíncronamente sem travas.
2. Não há enfileiramento (Bufferização) entre a ação final do lead e o disparo.
3. Event log poluido exibindo múltiplos registros consecutivos no backend para a exata mesma rota.

## Onde termina

1. Emissões baseadas em High Watermark (só é transmitido o *maior* nível de scroll após um repouso da navegação do lead).
2. O tráfego de rede diminui com os acessos pesados, enviando blocos com atraso de ~3 a 5 segundos de inatividade, normalizando as propriedades de `payload` em um dicionário coeso para futuras buscas dinâmícas no PostgreSQL (JSONB).

---

## Fluxo

```
FRONTEND (Ao ler a Landing Page)
└─> Usuário scrolla rápido da Home até o Footer (0% a 90%)
    └─> `onScroll` hook avalia: Nova Posição (90%) é maior que o High Watermark (0%)? SIM.
        └─> Atualiza a maraca d'água para 90% e (Re)inicia Timer Secreto de Debounce (Ex: 4 segs)
            └─> Usuário repousa lendo a garantia por 4 segundos
                └─> Timer Estoura → O Tracker empacota: { event: "scroll_depth", max_depth: 90, duration: 4s } e Dispara API.
```

---

## O que precisa ser feito

### No Frontend

1. **Reescrever Observador de Rolagem (`useScrollTracking` ou Tracker)**: Alterar o interceptador atual do `window.addEventListener('scroll')`. O evento deve computar o Scroll Percentual da altura (Math.round) e salvar numa variável `let highWatermark = 0`.
2. **Aplicar Padrão Debounce**: Importar pacote `lodash.debounce` ou escrever debouncer customizado. O gatilho de API enviando a propriedade `max_depth` do Evento deve esperar a inatividade.
3. **Padronizar Tipologia de Payload**: Formatar e uniformizar via constantes TypeScript (enum): `PAGE_VIEW`, `SCROLL_MAX_DEPTH`, `CTA_CLICKED`. Isso evitará grafias mistas que possam poluir o JSON do back e dificultar a geração das timelines das analíticas.

### No Backend

1. **Tratamento de Payload JSONB Seguro**: Os Eventos normalizados já estão desenhados de forma que o Controller do Endpoint simplesmente englobe no Model sem atrito.
2. A recepção do Payload e salvamento da string deve conter validações mínimas garantindo que a key `type` conste dentros das chaves de identificação táticas (garantindo assim que no amanhã não aceitaremos "Trackings Vazios/Spam Malicioso").

---

## Critérios de aceite

1. Mover bruscamente para cima e para baixo a página renderizada não gera novos pings no console ou nas redes (Network DevTools). O ping ocorre com 1 única requisição consolidando a % máxima após o usuário parar o cursor/touch.
2. A tabela do Live Events Log visualizada no painel do GOAT mostrará um item purificado por visitante/rota como "Rolou para 85%" no invés da chuva anterior, reduzindo a ocupação de armazenamento global da plataforma.

---

## Dependências

Este artefato deve ser preferívelmente testado sob a conclusão da Tarefa 040.1, de forma que, no ato da validação, o lead recém unificado já possa ostentar em sua própria base, uma timeline livre de poluições.

## Próxima tarefa → Tarefa 040.3
- Implementação Crítica: Tracker Global Mapeador e Despachante de Heatmaps XY em Lote.
