import { useEffect, useRef } from 'react'
import { useTheme } from '@/hooks/useTheme'

export function LightGlassEffect() {
  const { theme } = useTheme()
  const overlayRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (theme !== 'light') return

    const handleMouseMove = (e: MouseEvent) => {
      if (!overlayRef.current) return

      const x = (e.clientX / window.innerWidth) * 100
      const y = (e.clientY / window.innerHeight) * 100

      requestAnimationFrame(() => {
        if (overlayRef.current) {
          overlayRef.current.style.setProperty('--mouse-x', `${x}%`)
          overlayRef.current.style.setProperty('--mouse-y', `${y}%`)
        }
      })
    }

    window.addEventListener('mousemove', handleMouseMove)
    return () => window.removeEventListener('mousemove', handleMouseMove)
  }, [theme])

  if (theme !== 'light') return null

  return (
    <div
      ref={overlayRef}
      className="fixed inset-0 z-base pointer-events-none transition-opacity duration-1000"
      style={{
        background: `
          /* Halo que segue o cursor — ouro da casa, bem fraco */
          radial-gradient(
            800px circle at var(--mouse-x, 50%) var(--mouse-y, 50%),
            hsl(var(--primary) / 0.10),
            transparent 45%
          ),

          /* Contramovimento — auxiliar frio da marca */
          radial-gradient(
            700px circle at calc(100% - var(--mouse-x, 50%)) calc(100% - var(--mouse-y, 50%)),
            hsl(var(--brand-steel) / 0.10),
            transparent 50%
          ),

          /* Ambiência parada no rodapé */
          radial-gradient(
            1000px circle at 50% 100%,
            hsl(var(--muted-foreground) / 0.08),
            transparent 60%
          ),

          /* Esvanecido do topo */
          linear-gradient(
            to bottom,
            hsl(var(--background) / 0.9) 0%,
            hsl(var(--background) / 0) 35%
          ),

          /* Esvanecido do rodapé */
          linear-gradient(
            to top,
            hsl(var(--muted) / 0.9) 0%,
            hsl(var(--muted) / 0) 35%
          ),

          /* Base da atmosfera */
          linear-gradient(
            135deg,
            hsl(var(--card) / 0.6) 0%,
            hsl(var(--background)) 100%
          )
        `,
        backdropFilter: 'blur(120px)',
        WebkitBackdropFilter: 'blur(120px)',
      }}
    >
      {/* Malha do piso — pista sutil de perspectiva */}
      <div
        className="absolute inset-x-0 bottom-0 h-1/3 opacity-[0.3]"
        style={{
          backgroundSize: '60px 60px',
          backgroundImage:
            'linear-gradient(to right, hsl(var(--border) / 0.5) 1px, transparent 1px), linear-gradient(to bottom, hsl(var(--border) / 0.5) 1px, transparent 1px)',
          maskImage: 'linear-gradient(to bottom, transparent, hsl(var(--foreground)))',
        }}
      />
    </div>
  )
}
