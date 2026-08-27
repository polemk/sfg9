import { useEffect, useState, ReactNode } from 'react'
import { X } from 'lucide-react'
import { Button } from '@/components/ui/Button'

interface SideDrawerProps {
  open: boolean
  onClose: () => void
  title: string
  children: ReactNode
  footer?: ReactNode
}

export function SideDrawer({ open, onClose, title, children, footer }: SideDrawerProps) {
  const [mounted, setMounted] = useState(false)
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    if (open) {
      setMounted(true)
      setVisible(false)
      const t = setTimeout(() => setVisible(true), 10)
      return () => clearTimeout(t)
    } else {
      setVisible(false)
      const t = setTimeout(() => setMounted(false), 200)
      return () => clearTimeout(t)
    }
  }, [open])

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])

  if (!mounted) return null

  return (
    <div className="fixed inset-0 z-drawer-backdrop" data-helper>
      {/* Backdrop */}
      <div 
        className={`absolute inset-0 bg-brand-ink/70 backdrop-blur-sm transition-opacity duration-200 ${visible ? 'opacity-100' : 'opacity-0 pointer-events-none'}`} 
        onClick={onClose} 
      />
      
      {/* Drawer Panel */}
      <div 
        className={`fixed right-0 top-0 h-screen w-full sm:w-[500px] glass-panel border-l transition-transform duration-300 will-change-transform flex flex-col z-drawer ${visible ? 'translate-x-0' : 'translate-x-full'}`}
      >
        {/* Header */}
        <div className="flex items-center justify-between p-6 border-b border-border shrink-0">
          <h2 className="font-title text-xl font-bold text-foreground">{title}</h2>
          <Button
            variant="ghost"
            size="icon"
            aria-label="Fechar"
            onClick={onClose}
          >
            <X className="h-5 w-5" />
          </Button>
        </div>
        
        {/* Content Area - Scrolls */}
        <div className="flex-1 overflow-y-auto p-6 space-y-6">
          {children}
        </div>

        {/* Footer Area - Fixed at bottom */}
        {footer && (
          <div className="p-6 border-t border-border space-y-3 shrink-0">
            {footer}
          </div>
        )}
      </div>
    </div>
  )
}
