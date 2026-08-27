// Utilitários de tema para gráficos
// Recharts precisa de cor como string (não classe Tailwind), então aqui a cor
// sai como `hsl(var(--token))` — o token resolve sozinho entre claro e escuro,
// sem literal de cor no código.
export function getThemeVars() {
  return {
    primary: 'hsl(var(--primary))',
    accent: 'hsl(var(--accent))',
    fgMuted: 'hsl(var(--muted-foreground))',
    grid: 'hsl(var(--border))',
    // Antes eram três roxos/ciano neon fixos. Agora é o ouro Safegold e o azul
    // de informação — mesma função (destaque de série), sem cor literal.
    primaryVibrant: 'hsl(var(--primary))',
    primaryVibrant2: 'hsl(var(--brand-gold-deep))',
    accentVibrant: 'hsl(var(--info))'
  }
}

// Paleta categórica: seis séries distinguíveis, todas de token semântico.
const SERIES = [
  'hsl(var(--primary))',
  'hsl(var(--info))',
  'hsl(var(--success))',
  'hsl(var(--brand-steel))',
  'hsl(var(--negative))',
  'hsl(var(--muted-foreground))'
]

export function defaultPalette() {
  return [...SERIES]
}

export function vibrantPalette() {
  return [...SERIES]
}

export const LEAD_SOURCE_ORDER = ['Chat', 'Facebook', 'Instagram', 'Site', 'WhatsApp']

export function leadSourceColor(name: string) {
  const palette = vibrantPalette()
  const idx = LEAD_SOURCE_ORDER.indexOf(name)
  return palette[idx >= 0 ? idx : 0]
}
