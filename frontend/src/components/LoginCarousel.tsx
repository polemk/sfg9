import { useEffect, useState } from 'react'

/**
 * Painel de marca do login.
 *
 * Substitui o carousel padrão do ai9 (imagens geradas por IA + copy sobre
 * "Inteligência Artificial Nativa"). O copy agora fala do domínio real do
 * Safegold: risco, recebível, borderô, operação estruturada, renegociação,
 * indicador e limite por portador.
 *
 * A arte dos 5 slides foi fornecida pelo cliente em 25/08/2026 e vive em
 * `public/images/login-carousel/`. WebP a 84 — 1,7 MB de PNG viraram 210 KB, o
 * que importa numa tela que é a primeira coisa que carrega.
 *
 * O logo NÃO é desenhado aqui: o painel do formulário, ao lado, já mostra a
 * marca. Dois logos na mesma tela é redundância, não reforço de marca.
 */
type Slide = {
  eyebrow: string
  title: string
  description: string
  image?: string
}

const SLIDES: Slide[] = [
  {
    eyebrow: 'Risco',
    title: 'A exposição inteira em uma tela',
    description:
      'Operações de risco, movimentos e extensões consolidados por projeto. O que está em aberto, o que venceu e quanto disso é seu.',
    image: '/images/login-carousel/01_risco.webp',
  },
  {
    eyebrow: 'Recebíveis',
    title: 'Do borderô à liquidação',
    description:
      'Cada título rastreado da entrada do borderô até o pagamento, com o portador, o sacado e a data que realmente importam.',
    image: '/images/login-carousel/02_recebiveis.webp',
  },
  {
    eyebrow: 'Limites',
    title: 'Limite por portador, controlado',
    description:
      'Teto, consumo e saldo por portador e por carteira, atualizados a cada operação — antes de aprovar, não depois.',
    image: '/images/login-carousel/03_limites.webp',
  },
  {
    eyebrow: 'Renegociação',
    title: 'Reperfilamento sem perder o histórico',
    description:
      'Parcelas, pagamentos e anexos da renegociação amarrados ao contrato de origem. A trilha continua legível meses depois.',
    image: '/images/login-carousel/04_renegociacao.webp',
  },
  {
    eyebrow: 'Indicadores',
    title: 'Os números que sustentam a decisão',
    description:
      'Disponibilidade, remuneração, garantias e indicadores de carteira apurados sobre o mesmo dado que a operação usa.',
    image: '/images/login-carousel/05_indicadores.webp',
  },
]

export function LoginCarousel() {
  const [current, setCurrent] = useState(0)

  useEffect(() => {
    const timer = setInterval(() => {
      setCurrent((prev) => (prev + 1) % SLIDES.length)
    }, 7000)
    return () => clearInterval(timer)
  }, [])

  const slide = SLIDES[current]

  return (
    <div className="surface-dark relative h-full w-full overflow-hidden bg-background">
      {/* Faixa de ouro na base: o único traço de cor forte do painel. */}
      <div aria-hidden="true" className="absolute inset-x-0 bottom-0 h-1.5 bg-primary" />

      {/* A arte ocupa o painel inteiro. O véu é o que garante que o texto
          continue legível sobre qualquer um dos cinco slides — sem ele, o
          título branco some no slide claro da renegociação. */}
      {slide.image && (
        <>
          <img
            key={slide.image}
            src={slide.image}
            alt=""
            aria-hidden="true"
            className="fade-in absolute inset-0 h-full w-full object-cover"
          />
          <div
            aria-hidden="true"
            className="absolute inset-0 bg-gradient-to-t from-background via-background/85 to-background/25"
          />
        </>
      )}

      <div className="relative z-10 flex h-full flex-col justify-end gap-10 p-12 lg:p-16">
        <div key={current} className="fade-in max-w-2xl">
          <p className="mb-4 text-xs font-semibold uppercase tracking-[0.22em] text-primary">
            {slide.eyebrow}
          </p>
          <h2 className="font-title text-4xl font-semibold leading-tight tracking-tight text-foreground lg:text-5xl">
            {slide.title}
          </h2>
          <p className="mt-5 text-lg leading-relaxed text-muted-foreground">
            {slide.description}
          </p>
        </div>

        <div className="flex items-center gap-2" role="tablist" aria-label="Destaques do Safegold">
          {SLIDES.map((s, i) => (
            <button
              key={s.eyebrow}
              type="button"
              role="tab"
              aria-selected={i === current}
              aria-label={s.eyebrow}
              onClick={() => setCurrent(i)}
              className={`h-1.5 rounded-full transition-all duration-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background ${
                i === current ? 'w-10 bg-primary' : 'w-2 bg-muted-foreground/40 hover:bg-muted-foreground/70'
              }`}
            />
          ))}
        </div>
      </div>
    </div>
  )
}
