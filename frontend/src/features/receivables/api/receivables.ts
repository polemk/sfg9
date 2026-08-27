/**
 * S6 — reexporta o cliente de recebíveis para dentro da pasta da feature.
 *
 * O cliente **mora em `lib/api/receivables.ts`**, junto com os outros, porque é
 * lá que vive a leitura única do envelope de paginação
 * (`lib/api/pagination.ts`) e a fábrica de catálogo que a S3 escreveu. Duplicar
 * o cliente aqui daria uma segunda leitura do envelope — que é exatamente o que
 * aquele arquivo existe para impedir.
 *
 * Este arquivo existe só para que as páginas da feature importem de um lugar
 * curto, no mesmo formato de `features/risk/api/risk.ts`.
 */
export * from '@/lib/api/receivables'
