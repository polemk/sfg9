import { Label } from '@/components/ui/Label'
import { Input } from '@/components/ui/Input'
import { Button } from '@/components/ui/Button'
import { DOCUMENT_TYPES, mascararDocumento, type DocumentType } from '@/lib/api/projects'

/**
 * **Documento do fornecedor: o par (tipo, número)** — DC-11.
 *
 * Três defeitos do legado morrem neste componente:
 *
 * 1. **FE-071 — "desabilitar" era só CSS.** Havia dois blocos, CPF e CNPJ, e
 *    alternar entre eles apenas mudava a aparência: os dois continuavam no DOM
 *    e os dois eram enviados. Aqui existe UM campo, e o tipo escolhido decide a
 *    máscara e a validação — não há como mandar os dois.
 * 2. **FE-072 — o aviso distingue INCOMPLETO de INVÁLIDO.** O legado só sabia
 *    dizer "inválido", e quem estava no meio da digitação lia isso como erro.
 * 3. **Só dígitos vão para o servidor.** No legado a máscara ia junto, e o
 *    mesmo fornecedor entrava duas vezes apesar da unicidade — `12.345.678/0001-95`
 *    e `12345678000195` são strings diferentes.
 *
 * O documento **continua opcional**: a regra "ao menos um" estava comentada no
 * model do legado e a base tem fornecedor sem documento.
 */
const TAMANHO: Record<DocumentType, number> = { CPF: 11, CNPJ: 14 }

export function ProviderDocumentField({
  tipo,
  valor,
  onChange,
}: {
  tipo: DocumentType | null
  valor: string
  onChange: (tipo: DocumentType | null, valor: string) => void
}) {
  const digitos = valor.replace(/\D/g, '')
  const incompleto = tipo !== null && digitos.length > 0 && digitos.length < TAMANHO[tipo]

  return (
    <div className="space-y-1.5">
      <Label htmlFor="document">Documento</Label>

      <div className="flex flex-wrap items-center gap-2">
        <div className="flex rounded-md border border-input p-0.5" role="group" aria-label="Tipo de documento">
          <Button
            type="button"
            variant={tipo === null ? 'primary' : 'ghost'}
            size="sm"
            onClick={() => onChange(null, '')}
          >
            Sem documento
          </Button>
          {DOCUMENT_TYPES.map((t) => (
            <Button
              key={t}
              type="button"
              variant={tipo === t ? 'primary' : 'ghost'}
              size="sm"
              // Trocar de tipo LIMPA o número: um CPF de 11 dígitos lido como
              // CNPJ nunca é válido, e deixá-lo lá só produz um erro que o
              // usuário não entende.
              onClick={() => onChange(t, '')}
            >
              {t}
            </Button>
          ))}
        </div>

        {tipo !== null && (
          <Input
            id="document"
            className="w-56 font-numeric"
            inputMode="numeric"
            value={mascararDocumento(tipo, valor)}
            onChange={(e) => onChange(tipo, e.target.value.replace(/\D/g, ''))}
            placeholder={tipo === 'CPF' ? '000.000.000-00' : '00.000.000/0000-00'}
            aria-describedby="document-hint"
          />
        )}
      </div>

      <p id="document-hint" className="text-xs text-muted-foreground">
        {tipo === null
          ? 'O documento é opcional — o cadastro histórico tem fornecedor sem CPF nem CNPJ.'
          : incompleto
            ? `Faltam ${TAMANHO[tipo] - digitos.length} dígito(s) para completar o ${tipo}.`
            : `O dígito verificador é conferido no servidor. Só os números são gravados.`}
      </p>
    </div>
  )
}
