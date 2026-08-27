// useCountUp — anima um valor JÁ FORMATADO (ex.: "R$ 12.450,90", "34", "156")
// interpolando só a parte numérica, preservando prefixo/sufixo e casas decimais.
// Cai pra exibição instantânea se o valor não for parseável ou sob prefers-reduced-motion.
import { useEffect, useRef, useState } from 'react'

const VALUE_RE = /^([^\d]*)([\d.,]+)([^\d]*)$/

function parseValue(raw: string) {
  const match = VALUE_RE.exec(raw.trim())
  if (!match) return null
  const [, prefix, core, suffix] = match
  const decimals = core.includes(',') ? core.split(',')[1]?.length ?? 0 : 0
  const numeric = Number(core.replace(/\./g, '').replace(',', '.'))
  if (!Number.isFinite(numeric)) return null
  return { prefix, suffix, decimals, numeric }
}

function format(n: number, decimals: number) {
  return n.toLocaleString('pt-BR', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })
}

function easeOutExpo(t: number) {
  return t === 1 ? 1 : 1 - Math.pow(2, -10 * t)
}

export function useCountUp(value: string | number, durationMs = 800) {
  const stringValue = String(value)
  const [display, setDisplay] = useState(stringValue)
  const prevNumeric = useRef<number | null>(null)
  const frameRef = useRef<number>()

  useEffect(() => {
    const parsed = parseValue(stringValue)
    if (!parsed) {
      setDisplay(stringValue)
      prevNumeric.current = null
      return
    }

    const reduceMotion = typeof window !== 'undefined' &&
      window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

    const from = prevNumeric.current ?? 0
    const to = parsed.numeric

    if (reduceMotion || from === to) {
      setDisplay(`${parsed.prefix}${format(to, parsed.decimals)}${parsed.suffix}`)
      prevNumeric.current = to
      return
    }

    const start = performance.now()
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / durationMs)
      const current = from + (to - from) * easeOutExpo(t)
      setDisplay(`${parsed.prefix}${format(current, parsed.decimals)}${parsed.suffix}`)
      if (t < 1) {
        frameRef.current = requestAnimationFrame(tick)
      } else {
        prevNumeric.current = to
      }
    }
    frameRef.current = requestAnimationFrame(tick)
    return () => {
      if (frameRef.current) cancelAnimationFrame(frameRef.current)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stringValue])

  return display
}
