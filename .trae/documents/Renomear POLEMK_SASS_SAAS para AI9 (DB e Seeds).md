## Objetivo
- Substituir variáveis e prefixes POLEMK_SASS/POLEMK_SAAS por AI9 nos pontos solicitados.
- Padronizar nomes de usuário e bancos no `database.yml` para prefixo `ai9_`.

## Arquivos Alvo
- `backend/config/database.yml.example` — refs em development/test/production (username e database).
- `backend/config/database.yml` — refs em development/test/production (username, password e database).
- `backend/db/seeds.rb` — tokens/strings `POLEMK_SASS_*` e `POLEMK_SAAS_*`.

## Alterações Propostas
- `backend/config/database.yml.example`
  - `username: polemk_sass_user` → `username: ai9_user` (linha 6).
  - `database: polemk_sass_dev` → `database: ai9_dev` (linha 8).
  - `username: polemk_sass_user` → `username: ai9_user` (linha 15).
  - `database: polemk_sass_test` → `database: ai9_test` (linha 17).
  - `username: polemk_sass_user` → `username: ai9_user` (linha 24).
  - `database: polemk_sass_prod` → `database: ai9_prod` (linha 26).
- `backend/config/database.yml`
  - `username: polemk_saas_user` → `username: ai9_user` (linhas 6, 15, 24).
  - manter `password: 'pksaasusr'` (linhas 7, 16, 25) — sem mudança de segredo.
  - `database: polemk_saas_dev` → `database: ai9_dev` (linha 8).
  - `database: polemk_saas_test` → `database: ai9_test` (linha 17).
  - `database: polemk_saas_prod` → `database: ai9_prod` (linha 26).
- `backend/db/seeds.rb`
  - `instanceName: "POLEMK_SASS_WHATS"` → `instanceName: "AI9_WHATS"` (linha 8).
  - `instanceName: "POLEMK_SASS_#{user_tag}"` → `instanceName: "AI9_#{user_tag}"` (linha 16).
  - Caso existam `POLEMK_SAAS_*`, substituir igualmente por `AI9_*`.

## Busca Adicional (garantia)
- Executar busca case-insensitive por `polemk_sass` e `polemk_saas` no repositório para capturar quaisquer ocorrências remanescentes e padronizar para `ai9_` onde aplicável.
- Executar busca por `POLEMK_SASS` e `POLEMK_SAAS` e trocar por `AI9` apenas em tokens/strings de identificação (não em nomes de classes/modelos que não foram solicitados).

## Validação
- `rails db:prepare` para criar/ajustar `ai9_dev/test/prod` e validar conexão com `ai9_user`.
- `rails db:seed` para garantir que as mudanças em `seeds.rb` executam sem erros.
- Se necessário, criar role e bancos no Postgres:
  - `createuser -P ai9_user` (definir a mesma senha já usada em `database.yml`).
  - `createdb ai9_dev -O ai9_user`; `createdb ai9_test -O ai9_user`; `createdb ai9_prod -O ai9_user`.

## Decisões
- Senhas não serão alteradas (evitar quebra em ambientes existentes).
- Apenas nomes/identificadores serão atualizados para refletir AI9.

## Riscos & Assunções
- Assumo que `ai9_user` será/está disponível no Postgres; se não, criaremos conforme acima.
- Mudanças são compatíveis com Rails 8 API‑only; sem impacto em frontend.

## Rollback
- Caso necessário, retornamos para `polemk_sass_*` / `polemk_saas_*` usando o histórico das linhas referenciadas acima.