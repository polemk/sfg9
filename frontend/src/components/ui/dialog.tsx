"use client"

import * as React from "react"
import * as DialogPrimitive from "@radix-ui/react-dialog"
import { X } from "lucide-react"

import { cn } from "@/lib/utils"

const Dialog = DialogPrimitive.Root

const DialogTrigger = DialogPrimitive.Trigger

const DialogPortal = DialogPrimitive.Portal

const DialogClose = DialogPrimitive.Close

const DialogOverlay = React.forwardRef<
  React.ElementRef<typeof DialogPrimitive.Overlay>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Overlay>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Overlay
    ref={ref}
    className={cn(
      "fixed inset-0 z-modal-backdrop bg-brand-ink/70  data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0",
      className
    )}
    {...props}
  />
))
DialogOverlay.displayName = DialogPrimitive.Overlay.displayName

export interface DialogContentProps
  extends React.ComponentPropsWithoutRef<typeof DialogPrimitive.Content> {
  /**
   * No telefone o diálogo ocupa a **tela inteira**; do `sm` para cima ele volta
   * a ser a caixa centrada de sempre.
   *
   * **Por que existe, e por que o padrão é `false`.** A caixa centrada nasce
   * `max-w-lg` com margem dos dois lados: num aparelho de 390 px isso vira uma
   * caixinha com pouco mais de 300 px úteis — ilegível para conteúdo de
   * leitura (par rótulo/valor, UUID, diff). Tela cheia é o padrão nativo para
   * "abrir um registro" no telefone, e é o que a DEC-100 pede: no aparelho a
   * densidade é **repensada**, não encolhida.
   *
   * É **aditivo**, no mesmo molde do `layout?: 'auto' | 'fixed'` do `DataTable`:
   * com o padrão `false` a string de classes é byte a byte a de antes, então
   * nenhuma das telas que já usam `Dialog` muda.
   */
  fullScreenOnMobile?: boolean
}

const DialogContent = React.forwardRef<
  React.ElementRef<typeof DialogPrimitive.Content>,
  DialogContentProps
>(({ className, children, fullScreenOnMobile = false, ...props }, ref) => (
  <DialogPortal>
    <DialogOverlay />
    <DialogPrimitive.Content
      ref={ref}
      className={cn(
        fullScreenOnMobile
          ? // Mobile-first: a base é a tela cheia e o `sm:` devolve a caixa
            // centrada. Nesta ordem o Tailwind gera o responsivo DEPOIS do
            // base, que é o que faz a sobreposição valer no desktop.
            "fixed inset-0 z-modal flex h-full w-full max-w-none flex-col gap-4 border-0 bg-popover p-5 text-popover-foreground duration-200 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 sm:inset-auto sm:left-[50%] sm:top-[50%] sm:h-auto sm:max-h-[88vh] sm:w-[calc(100%-3rem)] sm:max-w-lg sm:translate-x-[-50%] sm:translate-y-[-50%] sm:rounded-lg sm:border sm:border-border sm:p-6 sm:shadow-e3 sm:data-[state=closed]:zoom-out-95 sm:data-[state=open]:zoom-in-95"
          : "fixed left-[50%] top-[50%] z-modal grid w-full max-w-lg translate-x-[-50%] translate-y-[-50%] gap-4 border border-border bg-popover text-popover-foreground p-6 shadow-e3 duration-200 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[state=closed]:slide-out-0-left-1/2 data-[state=closed]:slide-out-to-top-[48%] data-[state=open]:slide-in-from-left-1/2 data-[state=open]:slide-in-from-top-[48%] sm:rounded-lg",
        className
      )}
      {...props}
    >
      {children}
      {/* Alvo de 44 px no telefone (o mesmo critério do `Select`): `p-2` dá 32,
          e fechar é a única saída de um diálogo em tela cheia. Do `sm:` para
          cima volta a ser exatamente o botão de antes. */}
      <DialogPrimitive.Close className="absolute right-4 top-4 rounded-full p-3 sm:p-2 opacity-70 ring-offset-background transition-opacity hover:opacity-100 hover:bg-muted focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:pointer-events-none data-[state=open]:bg-accent data-[state=open]:text-muted-foreground">
        <X className="h-4 w-4" />
        <span className="sr-only">Close</span>
      </DialogPrimitive.Close>
    </DialogPrimitive.Content>
  </DialogPortal>
))
DialogContent.displayName = DialogPrimitive.Content.displayName

const DialogHeader = ({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) => (
  <div
    className={cn(
      "flex flex-col space-y-1.5 text-center sm:text-left",
      className
    )}
    {...props}
  />
)
DialogHeader.displayName = "DialogHeader"

const DialogFooter = ({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) => (
  <div
    className={cn(
      "flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2",
      className
    )}
    {...props}
  />
)
DialogFooter.displayName = "DialogFooter"

const DialogTitle = React.forwardRef<
  React.ElementRef<typeof DialogPrimitive.Title>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Title>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Title
    ref={ref}
    className={cn(
      "text-lg font-semibold leading-none tracking-tight",
      className
    )}
    {...props}
  />
))
DialogTitle.displayName = DialogPrimitive.Title.displayName

const DialogDescription = React.forwardRef<
  React.ElementRef<typeof DialogPrimitive.Description>,
  React.ComponentPropsWithoutRef<typeof DialogPrimitive.Description>
>(({ className, ...props }, ref) => (
  <DialogPrimitive.Description
    ref={ref}
    className={cn("text-sm text-muted-foreground", className)}
    {...props}
  />
))
DialogDescription.displayName = DialogPrimitive.Description.displayName

export {
  Dialog,
  DialogPortal,
  DialogOverlay,
  DialogClose,
  DialogTrigger,
  DialogContent,
  DialogHeader,
  DialogFooter,
  DialogTitle,
  DialogDescription,
}
