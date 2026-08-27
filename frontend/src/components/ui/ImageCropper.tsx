import { useState, useRef, useCallback, useEffect } from 'react'
import { Button } from './Button'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from './dialog'
import { Upload, X, Move, ZoomIn, ZoomOut } from 'lucide-react'

/*
 * Textos traduzidos para pt-BR pela S3, primeira consumidora deste componente
 * (o logo do Portador, DEC-47). Até aqui ele estava na base com ZERO call sites
 * e todos os rótulos em inglês — "No logo", "Crop Logo", "Drag to position",
 * "Save". O produto é pt-BR fixo (DEC-09: i18n fora de escopo), e um recortador
 * em inglês no meio de um sistema de crédito é defeito visível numa demo de
 * venda. Só as STRINGS mudaram; comportamento, props e assinatura estão
 * intactos. Registrado em `.migration-ai9/upstream-flags.md`.
 */

interface ImageCropperProps {
  value?: string
  onChange: (url: string) => void
  onUpload: (file: File) => Promise<string>
  aspectRatio?: number
  placeholder?: string
  className?: string
}

interface CropState {
  x: number
  y: number
  scale: number
}

export function ImageCropper({
  value,
  onChange,
  onUpload,
  aspectRatio = 1,
  placeholder = 'Enviar imagem',
  className = ''
}: ImageCropperProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [tempImage, setTempImage] = useState<string | null>(null)
  const [cropState, setCropState] = useState<CropState>({ x: 0, y: 0, scale: 1 })
  const [isDragging, setIsDragging] = useState(false)
  const [dragStart, setDragStart] = useState({ x: 0, y: 0 })
  const [isUploading, setIsUploading] = useState(false)

  const canvasRef = useRef<HTMLCanvasElement>(null)
  const imageRef = useRef<HTMLImageElement | null>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    const reader = new FileReader()
    reader.onload = (event) => {
      setTempImage(event.target?.result as string)
      setCropState({ x: 0, y: 0, scale: 1 })
      setIsOpen(true)
    }
    reader.readAsDataURL(file)
    e.target.value = ''
  }

  const drawCanvas = useCallback(() => {
    const canvas = canvasRef.current
    const ctx = canvas?.getContext('2d')
    const img = imageRef.current

    if (!canvas || !ctx || !img) return

    const containerSize = 300
    canvas.width = containerSize
    canvas.height = containerSize / aspectRatio

    ctx.clearRect(0, 0, canvas.width, canvas.height)

    const imgAspect = img.width / img.height
    const canvasAspect = canvas.width / canvas.height

    let drawWidth, drawHeight
    if (imgAspect > canvasAspect) {
      drawHeight = canvas.height * cropState.scale
      drawWidth = drawHeight * imgAspect
    } else {
      drawWidth = canvas.width * cropState.scale
      drawHeight = drawWidth / imgAspect
    }

    const drawX = (canvas.width - drawWidth) / 2 + cropState.x
    const drawY = (canvas.height - drawHeight) / 2 + cropState.y

    ctx.drawImage(img, drawX, drawY, drawWidth, drawHeight)
  }, [cropState, aspectRatio])

  useEffect(() => {
    if (tempImage && isOpen) {
      const img = new Image()
      img.onload = () => {
        imageRef.current = img
        drawCanvas()
      }
      img.src = tempImage
    }
  }, [tempImage, isOpen, drawCanvas])

  useEffect(() => {
    drawCanvas()
  }, [cropState, drawCanvas])

  const handleMouseDown = (e: React.MouseEvent) => {
    setIsDragging(true)
    setDragStart({ x: e.clientX - cropState.x, y: e.clientY - cropState.y })
  }

  const handleMouseMove = (e: React.MouseEvent) => {
    if (!isDragging) return
    setCropState(prev => ({
      ...prev,
      x: e.clientX - dragStart.x,
      y: e.clientY - dragStart.y
    }))
  }

  const handleMouseUp = () => {
    setIsDragging(false)
  }

  const handleZoom = (delta: number) => {
    setCropState(prev => ({
      ...prev,
      scale: Math.max(0.5, Math.min(3, prev.scale + delta))
    }))
  }

  const handleCrop = async () => {
    const canvas = canvasRef.current
    if (!canvas) return

    setIsUploading(true)
    try {
      const blob = await new Promise<Blob>((resolve) => {
        canvas.toBlob((b) => resolve(b!), 'image/png', 0.9)
      })

      const file = new File([blob], 'cropped-logo.png', { type: 'image/png' })
      const url = await onUpload(file)
      onChange(url)
      setIsOpen(false)
      setTempImage(null)
    } catch (error) {
      console.error('Upload failed:', error)
    } finally {
      setIsUploading(false)
    }
  }

  const handleRemove = () => {
    onChange('')
  }

  return (
    <div className={className}>
      <div className="flex items-center gap-3">
        {value ? (
          <div className="relative group">
            <img
              src={value}
              alt="Logo"
              className="h-12 w-auto max-w-[120px] object-contain rounded border border-border bg-muted/50"
            />
            <button type="button"
              onClick={handleRemove}
              className="absolute -top-2 -right-2 w-5 h-5 rounded-full bg-destructive text-destructive-foreground flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
            >
              <X className="w-3 h-3" />
            </button>
          </div>
        ) : (
          <div className="h-12 w-24 rounded border-2 border-dashed border-muted-foreground/30 flex items-center justify-center text-muted-foreground text-xs">
            Sem imagem
          </div>
        )}

        <div className="relative">
          <input
            type="file"
            accept="image/*"
            onChange={handleFileSelect}
            className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
          />
          <Button type="button" variant="secondary" size="sm">
            <Upload className="w-4 h-4 mr-2" />
            {value ? 'Trocar' : placeholder}
          </Button>
        </div>
      </div>

      <Dialog open={isOpen} onOpenChange={setIsOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Enquadrar a imagem</DialogTitle>
          </DialogHeader>

          <div className="space-y-4">
            <div
              ref={containerRef}
              className="relative mx-auto bg-muted rounded-lg overflow-hidden cursor-move select-none"
              style={{ width: 300, height: 300 / aspectRatio }}
              onMouseDown={handleMouseDown}
              onMouseMove={handleMouseMove}
              onMouseUp={handleMouseUp}
              onMouseLeave={handleMouseUp}
            >
              <canvas
                ref={canvasRef}
                className="w-full h-full"
              />
              <div className="absolute inset-0 pointer-events-none border-2 border-dashed border-primary/50 rounded" />
              <div className="absolute bottom-2 left-1/2 -translate-x-1/2 text-xs text-muted-foreground flex items-center gap-1 bg-background/80 px-2 py-1 rounded">
                <Move className="w-3 h-3" /> Arraste para posicionar
              </div>
            </div>

            <div className="flex items-center justify-center gap-4">
              <Button
                type="button"
                variant="secondary"
                size="icon"
                onClick={() => handleZoom(-0.1)}
              >
                <ZoomOut className="w-4 h-4" />
              </Button>
              <span className="text-sm text-muted-foreground w-16 text-center">
                {Math.round(cropState.scale * 100)}%
              </span>
              <Button
                type="button"
                variant="secondary"
                size="icon"
                onClick={() => handleZoom(0.1)}
              >
                <ZoomIn className="w-4 h-4" />
              </Button>
            </div>
          </div>

          <DialogFooter>
            <Button variant="secondary" onClick={() => setIsOpen(false)}>
              Cancelar
            </Button>
            <Button onClick={handleCrop} disabled={isUploading}>
              {isUploading ? 'Enviando…' : 'Salvar'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
