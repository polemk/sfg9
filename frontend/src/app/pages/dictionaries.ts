export type Chunk = {
  text: string;
  decorator?: 'strike' | 'highlight' | null;
  /** Cor do texto. Sempre token via `hsl(var(--…))`, nunca cor literal. */
  color?: string;
  /** Fundo do realce. Idem: só token. */
  bgColor?: string;
  fadedText?: boolean;
  durationMs?: number;
};

export type NicheParams = {
  heroTitle: string;
  heroSubtitle: string;
  sloganChunks: Chunk[];
  drama1Title: string;
  drama1Desc: string;
  drama2Title: string;
  drama2Desc: string;
  heroImage?: string;
};

/**
 * Copy por perfil de leitor. Texto do domínio Safegold — risco, recebíveis,
 * borderô, operações estruturadas, renegociações, indicadores e limites por
 * portador. Sem marca de terceiro e sem auto-referência a tecnologia.
 *
 * As cores dos trechos são token: o riscado usa `--muted-foreground` e o
 * realce usa o ouro da marca (`--primary`). Trocar o tema troca a copy junto,
 * sem editar este arquivo.
 */
const RISCADO: Pick<Chunk, 'decorator' | 'color' | 'fadedText' | 'durationMs'> = {
  decorator: 'strike',
  color: 'hsl(var(--muted-foreground))',
  fadedText: true,
  durationMs: 800,
};

const REALCE: Pick<Chunk, 'decorator' | 'color' | 'bgColor' | 'durationMs'> = {
  decorator: 'highlight',
  color: 'hsl(var(--primary))',
  bgColor: 'hsl(var(--primary) / 0.14)',
  durationMs: 1000,
};

export const dictionaries: Record<string, NicheParams> = {
  default: {
    heroTitle: "Risco, recebível e borderô no mesmo lugar — com número que fecha.",
    heroSubtitle: "Cadastro de sacado, limite por portador, operação estruturada e renegociação em uma única operação. Sem planilha paralela e sem conferência manual no fim do dia.",
    sloganChunks: [
      { text: "menos ", decorator: null },
      { text: "planilha solta", ...RISCADO },
      { text: " mais carteira sob controle", ...REALCE },
    ],
    drama1Title: "A carteira só aparece no fechamento?",
    drama1Desc: "Posição de recebível, vencido e a vencer atualizada junto com a operação. Você enxerga a concentração por sacado antes de aprovar, não depois de perder.",
    drama2Title: "Limite decidido no feeling?",
    drama2Desc: "Limite por portador com política escrita e histórico de decisão. Cada aprovação fica registrada com quem aprovou, quando e sobre qual indicador.",
  },
  engineer: {
    heroTitle: "Operação estruturada montada com regra, não com exceção.",
    heroSubtitle: "Desenhe a operação uma vez — participantes, garantias, cronograma de liquidação — e repita sem refazer o cálculo à mão a cada rodada.",
    heroImage: "/niche/engineer.png",
    sloganChunks: [
      { text: "a estrutura que substitui a ", decorator: null },
      { text: "montagem manual", ...RISCADO },
      { text: " por operação repetível", ...REALCE },
    ],
    drama1Title: "Cada operação é um caso à parte?",
    drama1Desc: "Modele a estrutura com participantes e regras de rateio definidos. A liquidação segue o desenho, e o desvio fica visível no mesmo dia.",
    drama2Title: "Conferência que trava a mesa?",
    drama2Desc: "O borderô nasce fechado: título, sacado, prazo e valor conferidos na entrada. A mesa opera com o número já batido.",
  },
  marketer: {
    heroTitle: "Indicador de carteira que a diretoria entende na primeira leitura.",
    heroSubtitle: "Concentração, inadimplência, prazo médio e giro em painéis que saem da própria operação — não de um extrato reprocessado no fim do mês.",
    heroImage: "/niche/marketer.png",
    sloganChunks: [
      { text: "você acompanha a carteira em vez de ", decorator: null },
      { text: "recontar o mês", ...RISCADO },
      { text: " lendo o indicador do dia", ...REALCE },
    ],
    drama1Title: "Relatório que chega tarde demais?",
    drama1Desc: "Os indicadores são calculados sobre a operação corrente. Quando a concentração sobe, o painel mostra antes de virar prejuízo.",
    drama2Title: "Cada área com um número diferente?",
    drama2Desc: "Uma base só para risco, comercial e financeiro. O mesmo recebível conta a mesma história em qualquer tela.",
  },
  developer: {
    heroTitle: "Renegociação registrada do começo ao fim, sem perder o rastro.",
    heroSubtitle: "Proposta, aceite, novo cronograma e baixa dos títulos originais ficam encadeados. Dá para reconstruir qualquer acordo meses depois.",
    heroImage: "/niche/developer.png",
    sloganChunks: [
      { text: "o acordo que deixa de ser ", decorator: null },
      { text: "combinado por e-mail", ...RISCADO },
      { text: " e vira registro auditável", ...REALCE },
    ],
    drama1Title: "Acordo fechado que ninguém acha depois?",
    drama1Desc: "Cada renegociação guarda o título de origem, a condição aceita e o responsável. A trilha vem junto, não como anexo perdido.",
    drama2Title: "Baixa manual gerando diferença?",
    drama2Desc: "A liquidação do acordo baixa os títulos originais na mesma transação. A carteira não fica com valor duplicado esperando conserto.",
  },
  /* ── Perfil: cedente / cliente da mesa ──
   * Avatar: empresa que antecipa recebível e quer previsibilidade de caixa,
   * sem entender de risco de crédito para operar.
   */
  entrepreneur: {
    heroTitle: "Antecipar recebível sem descobrir o custo só no extrato.",
    heroSubtitle: "Envie o borderô, veja a condição aplicada por título e acompanhe a liquidação. O caixa da semana deixa de ser estimativa.",
    heroImage: "/niche/empreendedor.png",
    sloganChunks: [
      { text: "a antecipação que troca ", decorator: null },
      { text: "surpresa no extrato", ...RISCADO },
      { text: " por condição na tela", ...REALCE },
    ],
    drama1Title: "Não sabe quanto entra e quando?",
    drama1Desc: "Cada título mostra prazo, condição e valor líquido antes do envio. Você decide o que antecipar com o número na frente.",
    drama2Title: "Cobrança e recebimento em lugares diferentes?",
    drama2Desc: "Envio, aprovação, liquidação e retorno ficam na mesma esteira. Nada depende de alguém lembrar de atualizar a planilha.",
  },
};
