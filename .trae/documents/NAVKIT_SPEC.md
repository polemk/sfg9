# Especificação de Implementação: Navkit (React/TSX)

Este documento é um guia completo para entender e construir o **Navkit**, nosso sistema de navegação exclusivo. Ele foi escrito para ser compreendido tanto por desenvolvedores experientes quanto por iniciantes.

---

## 1. O Que é o Navkit? (Conceito Básico)

Imagine que o seu site não é uma longa página que você rola para baixo (como um feed de rede social), nem um livro onde você vira páginas. Imagine que seu site é um **tabuleiro de xadrez gigante** ou um **mapa**.

- **A Matriz**: O site inteiro é uma grande grade (grid) de telas.
- **A Janela**: A tela do computador ou celular do usuário é uma "janela" que mostra apenas **uma** célula desse tabuleiro por vez.
- **A Navegação**: Para ver outras partes do site, o usuário move essa "janela" para:
  - ⬆️ Cima
  - ⬇️ Baixo
  - ⬅️ Esquerda
  - ➡️ Direita

Diferente de clicar em um link e esperar uma página carregar, no Navkit todas as telas já estão organizadas vizinhas umas das outras. A navegação é um deslize suave, como mover a câmera em um jogo de estratégia.

### Visualização

Imagine um site com 9 telas organizadas em 3 colunas e 3 linhas:

```mermaid
graph TD
    subgraph Coluna 0
    A0[0,0 - Institucional] --- B0[0,1 - Produtos] --- C0[0,2 - Detalhe Prod]
    end
    subgraph Coluna 1
    A1[1,0 - Sobre Nós] --- B1[1,1 - HOME (Início)] --- C1[1,2 - Login]
    end
    subgraph Coluna 2
    A2[2,0 - Contato] --- B2[2,1 - Blog] --- C2[2,2 - Termos]
    end
    
    A1 --> A0
    A1 --> A2
    B1 --> A1
    B1 --> C1
    B1 --> B0
    B1 --> B2
```

Se você está na **HOME (1,1)**:
- Para ver **Produtos**, você vai para a **Esquerda**.
- Para ver **Login**, você vai para **Baixo**.
- Para ver **Sobre Nós**, você vai para **Cima**.

---

## 2. Como Funciona "Por Baixo do Capô"?

Para fazer essa mágica acontecer em um site moderno (React), nós precisamos de algumas peças fundamentais. Vamos chamar de "Peças de LEGO" do nosso sistema.

### Peça 1: O "GPS" (Contexto e Estado)
O site precisa saber exatamente onde você está o tempo todo. Nós chamamos isso de **Estado de Posição**.
- É apenas um par de números: `X` (horizontal) e `Y` (vertical).
- Exemplo: "Agora o usuário está na posição X=1, Y=1".

### Peça 2: O "Mundo" (Container)
Este é o elemento que segura TODAS as telas do site.
- Ele é gigante. Se o site tem 3 telas de largura, ele tem 300% da largura da tela do seu monitor.
- **O Truque**: Para mostrar a tela da direita, nós não movemos a câmera. Nós movemos o "Mundo" inteiro para a esquerda! É como puxar um papel na mesa para ler o que está escrito no canto.

### Peça 3: O "Histórico" (URLs e Navegador)
Quando você anda pelo tabuleiro, o endereço do site lá em cima (`www.site.com/home` -> `www.site.com/contato`) precisa mudar automaticamente.
- Se o usuário clicar no botão "Voltar" do navegador, o Navkit tem que entender isso e "deslizar" a tela de volta para onde estava.
- Isso dá a sensação de um site profissional e não apenas um "jogo" ou apresentação de slides.

---

## 3. Guia de Implementação: Passo a Passo (Do Zero)

Quer criar um Navkit em um projeto novo? Siga esta receita de bolo.

### Passo 1: Preparar o Terreno (Contexto)
Crie o "cérebro" da navegação. Ele vai guardar a posição `X` e `Y` e fornecer a função `irPara(x, y)` para qualquer botão usar.

*Para desenvolvedores:* Crie um `React Context` chamado `NavKitContext`.

### Passo 2: Construir o Tabuleiro (Layout)
Crie uma estrutura HTML que permita que telas fiquem lado a lado.
- O elemento pai (janela) deve esconder tudo que transborda (`overflow: hidden`).
- O elemento filho (mundo) deve ter o tamanho total das telas somadas.

```tsx
// Exemplo Simplificado
<Janela>
  <Mundo style={{ transform: `translate(-${x}00vw, -${y}00vh)` }}>
    <TelaHome />
    <TelaContato />
    ...
  </Mundo>
</Janela>
```

### Passo 3: Criar as Células (Screens)
Cada tela precisa saber sua posição fixa no tabuleiro.
- A tela "Home" sabe que mora na rua 1, andar 1.
- A tela "Contato" sabe que mora na rua 2, andar 1.
Elas se posicionam sozinhas (absolute positioning) dentro do "Mundo".

### Passo 4: Conectar as Setas e Gestos
Agora precisamos das formas de mover o mundo.
1.  **Setas na Tela**: Botões fixos nas bordas. Quando clicados, chamam `irPara(x+1, y)`, etc.
2.  **Dedo (Touch)**: Detectar quando o usuário arrasta o dedo na tela (gesto de "swipe"). Se arrastar para cima, chamamos `irPara(x, y+1)`.

### Passo 5: Sincronizar com a URL (A "Mágica" Final)
Aqui conectamos o tabuleiro ao navegador.
1.  Crie um "Mapa de Rotas": Diga ao sistema que a posição `(1,1)` se chama `/home` e a `(2,1)` se chama `/contato`.
2.  Quando a posição mudar -> Mude a URL silenciosamente (sem recarregar).
3.  Quando o site abrir -> Leia a URL e descubra em qual posição começar.

---

## 4. Glossário para Iniciantes

- **React**: A ferramenta de construção usada. Pense nela como a "cola" e os "tijolos" modernos da web.
- **Viewport/Janela**: A área visível do navegador (o retângulo da sua tela).
- **Deep Linking**: A capacidade de mandar um link direto para uma tela interna (ex: mandar o link da tela de Contato direto para um amigo), em vez de obrigá-lo a entrar na Home e navegar até lá.
- **Slug**: A parte amigável do endereço do site. Em `site.com/contato`, o slug é `/contato`.
- **PushState**: Um comando técnico que diz ao navegador "Ei, mude o endereço lá em cima, mas não recarregue a página, eu cuido do resto".

---

## 5. Estrutura Técnica (Para o Programador)

Se você for programar isso agora, esta é a estrutura de pastas recomendada dentro do seu projeto (`src/` ou `app/javascript`):

```
NavKit/
├── index.tsx           # O ponto de entrada (Onde tudo começa)
├── Camada de Dados/
│   ├── context.tsx     # O cérebro (Guarda o X e Y)
│   ├── types.ts        # O dicionário (Define o que é uma "Posição")
│   └── routes.ts       # O mapa (Diz qual coordenada é qual URL)
├── Camada Visual/
│   ├── NavKitMatrix.tsx   # O Tabuleiro (Aplica o movimento/transform)
│   ├── NavKitScreen.tsx   # A Célula (Onde você coloca seu conteúdo)
│   └── UI/
│       ├── NavKitControls.tsx  # As Setas (Cima, Baixo...)
│       ├── TopBar.tsx          # Barra de topo (Logo)
│       └── BottomBar.tsx       # Barra de pé (Links úteis)
└── Ferramentas/
    ├── useNavKit.ts       # Atalho para programadores usarem o sistema
    └── useHistorySync.ts  # O Robô que cuida das URLs
```
