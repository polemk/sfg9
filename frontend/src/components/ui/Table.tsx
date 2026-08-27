import * as React from "react"

import { cn } from "@/lib/utils"

/**
 * Acréscimo ADITIVO (26/08/2026): acesso ao container que rola.
 *
 * O `<div>` de fora sempre foi quem rola (`overflow-auto`), mas ele não tinha nome
 * nem `ref` — então quem quisesse medir o transbordo para desenhar uma afordância
 * ("há mais conteúdo à direita") não tinha por onde. Sem nenhuma das duas props o
 * markup sai idêntico ao de antes; nenhuma das telas existentes muda.
 */
export interface TableProps extends React.HTMLAttributes<HTMLTableElement> {
    /**
     * Atributos do container que rola: classes (barra visível, `scroll-snap`),
     * `role`/`tabIndex` para quem navega por teclado, `aria-label`.
     */
    wrapperProps?: React.HTMLAttributes<HTMLDivElement> & { [chave: `data-${string}`]: string }
    /** `ref` do container que rola — para medir `scrollLeft`/`scrollWidth`. */
    wrapperRef?: React.Ref<HTMLDivElement>
}

const Table = React.forwardRef<HTMLTableElement, TableProps>(
    ({ className, wrapperProps, wrapperRef, ...props }, ref) => (
        <div
            ref={wrapperRef}
            {...wrapperProps}
            className={cn("relative w-full overflow-auto", wrapperProps?.className)}
        >
            <table
                ref={ref}
                className={cn("w-full caption-bottom text-sm", className)}
                {...props}
            />
        </div>
    )
)
Table.displayName = "Table"

const TableHeader = React.forwardRef<
    HTMLTableSectionElement,
    React.HTMLAttributes<HTMLTableSectionElement>
>(({ className, ...props }, ref) => (
    <thead ref={ref} className={cn("[&_tr]:border-b", className)} {...props} />
))
TableHeader.displayName = "TableHeader"

const TableBody = React.forwardRef<
    HTMLTableSectionElement,
    React.HTMLAttributes<HTMLTableSectionElement>
>(({ className, ...props }, ref) => (
    <tbody
        ref={ref}
        className={cn("[&_tr:last-child]:border-0", className)}
        {...props}
    />
))
TableBody.displayName = "TableBody"

const TableFooter = React.forwardRef<
    HTMLTableSectionElement,
    React.HTMLAttributes<HTMLTableSectionElement>
>(({ className, ...props }, ref) => (
    <tfoot
        ref={ref}
        className={cn(
            "border-t bg-muted/50 font-medium [&>tr]:last:border-b-0",
            className
        )}
        {...props}
    />
))
TableFooter.displayName = "TableFooter"

const TableRow = React.forwardRef<
    HTMLTableRowElement,
    React.HTMLAttributes<HTMLTableRowElement>
>(({ className, ...props }, ref) => (
    <tr
        ref={ref}
        className={cn(
            "border-b transition-colors hover:bg-muted/50 data-[state=selected]:bg-muted",
            className
        )}
        {...props}
    />
))
TableRow.displayName = "TableRow"

const TableHead = React.forwardRef<
    HTMLTableCellElement,
    React.ThHTMLAttributes<HTMLTableCellElement>
>(({ className, ...props }, ref) => (
    <th
        ref={ref}
        className={cn(
            "h-12 px-4 text-left align-middle text-xs font-bold uppercase tracking-[0.05em] text-muted-foreground [&:has([role=checkbox])]:pr-0",
            className
        )}
        {...props}
    />
))
TableHead.displayName = "TableHead"

const TableCell = React.forwardRef<
    HTMLTableCellElement,
    React.TdHTMLAttributes<HTMLTableCellElement>
>(({ className, ...props }, ref) => (
    <td
        ref={ref}
        className={cn("p-4 align-middle [&:has([role=checkbox])]:pr-0", className)}
        {...props}
    />
))
TableCell.displayName = "TableCell"

const TableCaption = React.forwardRef<
    HTMLTableCaptionElement,
    React.HTMLAttributes<HTMLTableCaptionElement>
>(({ className, ...props }, ref) => (
    <caption
        ref={ref}
        className={cn("mt-4 text-sm text-muted-foreground", className)}
        {...props}
    />
))
TableCaption.displayName = "TableCaption"

export {
    Table,
    TableHeader,
    TableBody,
    TableFooter,
    TableHead,
    TableRow,
    TableCell,
    TableCaption,
}
