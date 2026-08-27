# Tarefa 51: Dicionário de Copy e Elementos Visuais por Nicho

**Sprint:** LPs Segmentadas
**Estimativa:** 1 dia (Desacoplamento Visual React)
**Estrutura de IA Recomendada:** Fal.ai (Imagens Originais)

---

## Contexto
Tendo o roteamento operando nativamente e lendo nossa Tabela de Planos interna, precisamos da "embalagem" textual perfeita. O foco aqui não é vender um framework para eles aprenderem a programar; é vender uma **bancada de trabalho profissional** para cada avatar rodar sua máquina de vendas, seus sistemas ou as regras lógicas da sua construtora sem reinventar a roda.

## Onde começa
- Componentes modulares do nosso front (`HeroCampfire`, `FeaturesSection`, e `CTA`s).

## Onde termina
- Arquivo `src/app/(public)/_components/dictionaries.ts` injetando a copy limpa e direta em cada landing age segmentada.

---

## Estrutura do Dicionário (Copy e Assets Sugeridos)

### Variante 1: O Engenheiro ( STUDENT )
*Foco: Ele resolve problemas em ferramentas poderosas (Revit/CAD). Nosso Boilerplate é sua nova e definitiva ferramenta para criar softwares internos para seu escritório sem precisar virar um DevOps.*

- **Hero Title**: "Você não precisa virar um programador de infraestrutura para criar os sistemas do seu escritório."
- **Hero Subtitle**: "Você jamais perderia três meses criando o AutoCAD do zero apenas para conseguir desenhar a planta de um prédio. Então por que perder tempo construindo sistemas de login, bancos de dados e gateways de pagamento do zero? Receba o terreno pronto, a fundação sólida. Preocupe-se apenas em projetar as regras e alavancar a sua construtora."
- **Dramas (Feature Cards)**:
  1. *A infraestrutura ou o cliente?* "Tenha acesso a uma API-first moderna pronta para ligar suas calculadoras de projeto, CRMs de campo ou automações de obra. Tudo sem precisar construir a base elétrica."
  2. *Retrabalho cego?* "Suba um painel administrativo seguro em sexta-feira à noite. Criamos a fundação para que o sistema de regras do seu negócio nunca caia e não exija sua atenção diária."
- **Asset / Image Request Suggestion**: 
  - Foco em materialidade: Um monitor elegante numa bancada de escritório brutalista, com um papel-vegetal ao lado. No monitor: painéis visuais hiper precisos cruzando um layout de App com polígonos/dimensões limpas flutuando. Estética de precisão fria.

---

### Variante 2: O Marketer ( BAD BUNNY GOAT )
*Foco: Automatizar Hubs, cruzar fluxos sem barreiras sistêmicas, rodar estratégias em alto nível tecnológico usando Inbound e CRM que eles mesmos controlam.*

- **Hero Title**: "Sua estratégia de tração não deveria ficar presa em integrações gessadas."
- **Hero Subtitle**: "Ferramentas como Zapier e Make te deixam não mão quando você quer escalar de verdade. Nós te entregamos o código-fonte de um polo distribuidor completo: Asaas, Mailer e WhatsApp. Construa seu próprio Hub de Aquisição e abaixe o CAC sem depender do suporte de grandes SaaS."
- **Dramas (Feature Cards)**:
  1. *Leads perdidos por delay?* "Não gaste tempo lidando com autenticações complexas de APIs. Tudo já está plugado em um repositório central pronto para gerar vendas imediatas."
  2. *Pagando caro nos planos SAAS?* "Acabe com a dependência mensal de painéis fechados. Utilize nosso 'boiler' para desdobrar fluxos complexos retendo 100% da inteligência e dos dados sob o seu controle."
- **Asset / Image Request Suggestion**:
  - Estúdio pouco iluminado, uma tela glow verde neon refletindo em óculos geométricos. Gráficos de retenção estilo Matrix x Hubspot disparando setas. Vibração de alta conversão sem limites.

---

### Variante 3: O Developer ( BABY GOAT )
*Foco: Boilerplate absoluto. Deletar setups monótonos e ir pro game faturar ou entregar apps sem burnout.*

- **Hero Title**: "Transforme código boilerplated na sua máquina autônoma de negócio."
- **Hero Subtitle**: "Pare de perder suas sextas-feiras refazendo autenticação e setup do Stripe pelo décimo projeto seguido. Nossa Stack (Vite + Rails 8 API) te catapulta do `yarn dev` para a tela de 'Projeto Entregue' reduzindo 200h de trabalho estúpido. Foque no que coloca dinheiro no seu bolso."
- **Dramas (Feature Cards)**:
  1. *Refazendo o mesmo Auth?* "Delegação instantânea do módulo core. Fica com a burocracia dos JWTs e redefinição de senhas com a gente; crie apenas sua regra de negócios."
  2. *Noite em claro com deploy* "O monorepo carrega o DevOps e arquitetura conteinerizada madura que nunca vacila. Escalonamento previsível para não te dar sustos na fatura."
- **Asset / Image Request Suggestion**:
  - Estética Indie Hacker / High Performance: Setup ultra-wide com o código perfeito sendo montado. Mesa clean, ambiente levemente dark, led purpura vazando, passando uma ideia de quem trabalha com alta alavancagem de tempo. Estilo "One Man Army".

---

### Variante 4: O Empreendedor ( MEI GOAT )
*Foco: Pequeno empresário (MEI) que está em busca de visibilidade e oportunidades na tecnologia. Não quer aprender a programar; quer uma bancada de trabalho digital que centralize vendas, gestão e atendimento.*

- **Hero Title**: "Sua pequena empresa merece a tecnologia das grandes, sem a complexidade."
- **Hero Subtitle**: "Pare de perder tempo com planilhas manuais e sistemas que não conversam entre si. Receba uma bancada de trabalho completa: CRM, automação de vendas e gestão financeira integrada ao WhatsApp e Pix. O terreno está pronto; foque em escalar o seu negócio."
- **Slogan Chunks (Canvas)**:
  - Neutro: "a bancada digital que transforma o seu MEI em "
  - Strike: "planilhas e bagunça"
  - Highlight: " máquina de vendas 💼"
- **Dramas (Feature Cards)**:
  1. *Gestão manual travando seu crescimento?* "Centralize seus leads, vendas e cobranças em um painel inteligente que trabalha por você 24/7. Sem precisar entender de código ou contratar uma equipe de TI."
  2. *Pagando caro em SaaS que te limita?* "Tenha controle total dos seus dados e da sua operação sem pagar assinaturas abusivas por cada novo cliente. Uma única licença, uso ilimitado, 100% seu."
- **Hashtags (#SloganCanvas)**: `#gestão  ·  #vendas  ·  #automação  ·  #mei  ·  #crescimento  ·  #pix  ·  #whatsapp`
- **Topbar Label**: `4 MEIs` (mobile e desktop)
- **SEO Title (pt-br)**: "Goat para MEI - Tecnologia das grandes empresas para o seu pequeno negócio"
- **SEO Description (pt-br)**: "CRM, automação de vendas, gestão financeira e WhatsApp integrados numa bancada digital pronta. Escale seu MEI sem precisar de equipe de TI."
- **Asset / Image Request Suggestion**: 
  - Estética "Local Business Elevated": Um balcão de loja/escritório moderno e minimalista com um tablet exibindo dashboards coloridos de vendas. Elementos flutuantes de Pix e WhatsApp convergindo para a tela. Iluminação quente, sensação de prosperidade e acessibilidade tecnológica.

---

## Observações de Arquitetura Frontend
Use dicionários na camada de roteamento (ex: `dictionaries.ts`) de forma que no `HomePage.tsx` a renderização utilize: `{copy[niche]?.heroTitle}`. A LP não será manchada com dezenas de IF's/ELSE's explícitos na árvore JSX.

## Critérios de aceite:
1. Roteamento React lendo as keys limpas do dicionário.
2. Temática certeira entregue via SSR base/SEO Tags para indexação isolada no Google de acordo com o slug.

