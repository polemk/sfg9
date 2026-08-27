import { useEffect } from 'react'

export function MouseTracker() {
    useEffect(() => {
        const handleMouseMove = (e: MouseEvent) => {
            document.body.style.setProperty('--mouse-x', `${e.clientX}px`)
            document.body.style.setProperty('--mouse-y', `${e.clientY}px`)
        }

        window.addEventListener('mousemove', handleMouseMove)
        return () => {
            window.removeEventListener('mousemove', handleMouseMove)
        }
    }, [])

    return null
}
