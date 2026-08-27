import { useTheme } from '@/hooks/useTheme'
import { Button } from '@/components/ui/Button'
import { Sun, Moon } from 'lucide-react'

export function ThemeToggle({ className }: { className?: string }) {
    const { theme, toggleTheme } = useTheme()

    return (
        <Button
            variant="ghost"
            size="sm"
            onClick={toggleTheme}
            className={`rounded-full w-8 h-8 p-0 text-muted-foreground hover:text-foreground hover:scale-105 transition-all ${className}`}
            aria-label="Toggle Theme"
        >
            {theme === 'dark' ? (
                <Moon className="w-5 h-5" />
            ) : (
                <Sun className="w-5 h-5" />
            )}
        </Button>
    )
}
