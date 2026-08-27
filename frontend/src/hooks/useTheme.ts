import { useEffect } from 'react'
import { useThemeStore } from '@/store/themeStore'

export function useTheme() {
  const { theme, setTheme } = useThemeStore()

  useEffect(() => {
    const root = document.documentElement
    // Simplified logic: just sync theme state to DOM
    root.classList.remove('light', 'dark')
    root.classList.add(theme)
    root.setAttribute('data-theme', theme)
  }, [theme])

  const toggleTheme = () => {
    const newTheme = theme === 'light' ? 'dark' : 'light'
    setTheme(newTheme)
  }

  return { theme, toggleTheme, setTheme }
}