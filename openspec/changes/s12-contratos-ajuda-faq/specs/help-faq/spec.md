# Help/FAQ — deltas da fatia S12

> Os 21 requirements de inventário desta capability **já existem** em
> `openspec/specs/help-faq/spec.md` (BE-350…BE-364, FE-364…FE-366, DB-367…DB-369).
> **Não são recriados aqui.**
>
> O que segue é o requirement **novo**, sem ID de inventário: a decisão de fatia de manter
> **um único editor de rich text** na base, tomada a partir da flag **F-14**.

## ADDED Requirements

### Requirement: EDT-S12 — Um único editor de rich text para contrato e item de ajuda
O sistema SHALL usar **um** componente de edição de rich text no frontend — o que já está em
uso na base (`components/RichTextEditor.tsx`, Slate) — tanto no formulário de versão de
contrato quanto no formulário de item de ajuda, e NÃO SHALL introduzir um segundo editor.

Contexto: convivem dois na base — Slate em uso e TipTap declarado no `package.json`
(flag **F-14**). Manter os dois multiplica o comportamento de colagem, de sanitização e de
serialização do conteúdo em duas telas que **guardam texto de valor jurídico e texto de
suporte ao usuário**. A duplicidade existente na base é **registrada** em
`.migration-ai9/upstream-flags.md`, não corrigida (Princípio 6b).

#### Scenario: As duas telas usam o mesmo editor
- **GIVEN** o formulário de nova versão de contrato e o formulário de item de ajuda
- **WHEN** ambos são abertos
- **THEN** os dois usam o mesmo componente de edição, com o mesmo conjunto de marcações
  suportadas

#### Scenario: O segundo editor não é introduzido
- **GIVEN** o código do frontend depois desta fatia
- **WHEN** os imports são inspecionados
- **THEN** nenhum módulo do segundo editor é importado por código de aplicação

#### Scenario: O conteúdo salvo abre igual nas duas pontas
- **GIVEN** um conteúdo rico com títulos, listas e negrito salvo pelo editor
- **WHEN** ele é reaberto para edição e quando é renderizado para leitura
- **THEN** a formatação é a mesma nas duas situações, e o HTML renderizado passa pela
  allowlist de sanitização
