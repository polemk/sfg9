/** @type {import('tailwindcss').Config} */
export default {
  darkMode: ['class'],
  content: [
    './pages/**/*.{ts,tsx}',
    './components/**/*.{ts,tsx}',
    './app/**/*.{ts,tsx}',
    './src/**/*.{ts,tsx}',
  ],
  theme: {
    container: {
      center: true,
      padding: '2rem',
      screens: {
        '2xl': '1400px',
      },
    },
    extend: {
      fontFamily: {
        // Fontes da marca Safegold (as mesmas do legado): Work Sans para
        // texto, Fira Mono para número. `font-numeric` é obrigatório em
        // coluna de valor — é o que faz o dígito alinhar.
        sans: ['var(--font-text)'],
        title: ['var(--font-title)'],
        numeric: ['var(--font-numeric)'],
      },
      boxShadow: {
        // Elevação tokenizada. Nunca escreva `shadow-[0_4px_...]` na tela.
        e1: 'var(--elevation-1)',
        e2: 'var(--elevation-2)',
        e3: 'var(--elevation-3)',
        // Lateral, para a coluna congelada da tabela que rola na horizontal.
        'sticky-col': 'var(--elevation-sticky-col)',
        // Espelhada, para a borda direita de uma tabela que continua.
        'scroll-edge': 'var(--elevation-scroll-edge)',
      },
      zIndex: {
        base: '0',
        // Cabeçalho STICKY de uma página (o `PageHeader`, a lista de credenciais).
        // Sobe sobre o conteúdo que rola por baixo dele — e nada mais.
        sticky: '20',
        // As barras fixas do APP (topo e abas no telefone, topbar do console).
        // Precisam de um degrau PRÓPRIO acima do `sticky`: elas e o `PageHeader`
        // dividiam o mesmo 20, e no empate quem vence é quem vem depois no DOM —
        // que é sempre o conteúdo, porque a barra é montada antes do `main`.
        // Resultado: ao rolar, o título da página passava POR CIMA da barra do
        // telefone, em toda tela que rola. Não era transparência; era empate.
        appbar: '30',
        fab: '45',
        'drawer-backdrop': '50',
        drawer: '55',
        // A parede é tomada de tela inteira: passa por cima do cabeçalho fixo
        // do app (z-[60]), que senão engole o seletor de fontes, o período e o
        // próprio "sair da parede" — foi o que aconteceu no FÁCIL.
        parede: '62',
        brand: '65',
        // Modal passa por cima até da faixa: enquanto está aberto, ele é a tela.
        'modal-backdrop': '66',
        modal: '68',
        // Superfície flutuante ancorada (dropdown, select, datepicker,
        // autocomplete). Fica ACIMA do modal porque um select aberto dentro de
        // um dialog tem que cobrir o dialog, e ABAIXO do toast, que nunca pode
        // ser escondido por um menu. Todo painel desses renderiza em portal no
        // `document.body` — o número aqui só resolve o empate entre irmãos do
        // body; o que realmente conserta o empilhamento é o portal.
        popover: '69',
        toast: '70',
        tooltip: '80',
      },
      colors: {
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
        secondary: {
          DEFAULT: 'hsl(var(--secondary))',
          foreground: 'hsl(var(--secondary-foreground))',
        },
        destructive: {
          DEFAULT: 'hsl(var(--destructive))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        muted: {
          DEFAULT: 'hsl(var(--muted))',
          foreground: 'hsl(var(--muted-foreground))',
        },
        accent: {
          DEFAULT: 'hsl(var(--accent))',
          foreground: 'hsl(var(--accent-foreground))',
        },
        popover: {
          DEFAULT: 'hsl(var(--popover))',
          foreground: 'hsl(var(--popover-foreground))',
        },
        card: {
          DEFAULT: 'hsl(var(--card))',
          foreground: 'hsl(var(--card-foreground))',
        },
        // Chapa do QR — os únicos tokens que NÃO mudam entre claro e escuro,
        // de propósito. O PNG da Evolution tem os módulos VAZADOS, então quem
        // pinta o módulo é o que está atrás da imagem (`qr-module`), e a chapa
        // (`qr-plate`) é a zona de silêncio. Ver a nota em `globals.css`.
        'qr-plate': {
          DEFAULT: 'hsl(var(--qr-plate))',
          foreground: 'hsl(var(--qr-plate-foreground))',
        },
        'qr-module': 'hsl(var(--qr-module))',
        // Estado — semânticos, derivados das cores de indicador do legado
        // (#217B55 positivo, #7D1F1E negativo, #3454D1 azul, #FFC107 ouro).
        success: {
          DEFAULT: 'hsl(var(--success))',
          foreground: 'hsl(var(--success-foreground))',
        },
        warning: {
          DEFAULT: 'hsl(var(--warning))',
          foreground: 'hsl(var(--warning-foreground))',
        },
        info: {
          DEFAULT: 'hsl(var(--info))',
          foreground: 'hsl(var(--info-foreground))',
        },
        negative: {
          DEFAULT: 'hsl(var(--negative))',
          foreground: 'hsl(var(--negative-foreground))',
        },
        // Cores literais da marca Safegold — use só quando a peça É a marca
        // (logo, faixa, selo). Para ação/estado use os semânticos acima.
        'brand-gold': {
          DEFAULT: 'hsl(var(--brand-gold))',
          deep: 'hsl(var(--brand-gold-deep))',
        },
        'brand-steel': 'hsl(var(--brand-steel))',
        // Faixa de marca do topo — mesmo token do brsw, para a faixa ser
        // literalmente igual nos dois sites.
        'brand-ink': {
          DEFAULT: 'hsl(var(--brand-ink))',
          foreground: 'hsl(var(--brand-ink-foreground))',
        },
      },
      /**
       * `text-*` das cores de estado usa a variante `-text`, não a de fundo.
       *
       * Uma cor semântica é usada de dois jeitos opostos e um valor só não
       * serve aos dois. `bg-primary` quer o ouro cheio da marca com grafite por
       * cima (10,4:1); `text-primary` quer a mesma ideia em letra de 12px — e o
       * ouro #FFC107 sobre branco dá **1,63:1**. Clarear o ouro conserta o texto
       * e estraga o botão, escurecer faz o contrário: são dois tokens.
       *
       * O mapeamento vive aqui, e não nas telas, por um motivo prático: são 125
       * chamadas de `text-primary` no repo, e nenhuma precisou mudar. A tela
       * continua escrevendo `text-primary` e sai legível nos dois modos.
       *
       * `backgroundColor`, `borderColor`, `ringColor`, `fill` e `stroke`
       * **não** são remapeados — continuam no token de fundo, que é o certo
       * para eles.
       *
       * `foreground` é repetido em cada entrada de propósito: `extend.textColor`
       * SUBSTITUI a chave inteira vinda de `colors`, então omitir aqui apagaria
       * `text-primary-foreground` do projeto.
       *
       * A marca não entra nesta lista: `text-brand-gold` continua sendo o ouro
       * cheio, porque ali a cor é o assunto (faixa, selo, logo), não o texto.
       */
      textColor: {
        primary: {
          DEFAULT: 'hsl(var(--primary-text))',
          foreground: 'hsl(var(--primary-foreground))',
        },
        destructive: {
          DEFAULT: 'hsl(var(--destructive-text))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        success: {
          DEFAULT: 'hsl(var(--success-text))',
          foreground: 'hsl(var(--success-foreground))',
        },
        warning: {
          DEFAULT: 'hsl(var(--warning-text))',
          foreground: 'hsl(var(--warning-foreground))',
        },
        info: {
          DEFAULT: 'hsl(var(--info-text))',
          foreground: 'hsl(var(--info-foreground))',
        },
        negative: {
          DEFAULT: 'hsl(var(--negative-text))',
          foreground: 'hsl(var(--negative-foreground))',
        },
      },
      borderRadius: {
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
        sm: 'calc(var(--radius) - 4px)',
      },
      keyframes: {
        // Blink de seleção estilo tela de escolha de lutador: a borda verde
        // pisca dura (steps), sem fade — é jogo, não vitrine.
        'mk-blink': {
          '0%, 49%': { outlineColor: 'rgb(16 185 129)' },
          '50%, 100%': { outlineColor: 'rgb(16 185 129 / 0.15)' },
        },
        'brand-marquee': {
          from: { transform: 'translate3d(0,0,0)' },
          to: { transform: 'translate3d(-50%,0,0)' },
        },
        // Barra de progresso indeterminado (atualização em segundo plano no
        // `PageHeader`). Um traço curto atravessando a faixa — é o que diz
        // "está acontecendo algo" sem fingir que sabe o percentual.
        'progress-indeterminate': {
          '0%': { transform: 'translateX(-100%)' },
          '100%': { transform: 'translateX(400%)' },
        },
        'accordion-down': {
          from: { height: 0 },
          to: { height: 'var(--radix-accordion-content-height)' },
        },
        'accordion-up': {
          from: { height: 'var(--radix-accordion-content-height)' },
          to: { height: 0 },
        },
      },
      animation: {
        'brand-marquee': 'brand-marquee 32s linear infinite',
        'progress-indeterminate': 'progress-indeterminate 1.1s ease-in-out infinite',
        'mk-blink': 'mk-blink 0.32s steps(1, end) infinite',
        'accordion-down': 'accordion-down 0.2s ease-out',
        'accordion-up': 'accordion-up 0.2s ease-out',
      },
    },
  },
  plugins: [require('tailwindcss-animate')],
}