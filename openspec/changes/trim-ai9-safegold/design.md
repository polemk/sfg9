# Design: como o trim é executado com segurança

## Linha de base medida antes de remover qualquer coisa

Sem baseline, um agente de remoção não distingue "eu quebrei" de "já estava quebrado".

| Verificação | Comando | Baseline (24/08/2026) |
| ----------- | ------- | --------------------- |
| Type-check do front | `cd frontend && node node_modules/typescript/bin/tsc --noEmit` | **VERMELHO — 305 erros** |
| Distribuição dos erros | — | **282 em `src/components/3d/`, 23 em `src/components/3d/chat/` — 100% concentrados** |
| Backend specs | `cd backend && bundle exec rspec` | **medido em 24/08/2026: 1362 examples, 6 failures, 2 pending — JA VERMELHO** |

> `pnpm` não está disponível neste shell (Git Bash). Use os binários locais via `node`:
> `node node_modules/typescript/bin/tsc --noEmit`, `node node_modules/vitest/vitest.mjs run`.

**Consequência que simplifica tudo:** os 305 erros estão inteiramente dentro do
`AI9-022` (cenas 3D/WebGL), que é uma das features **a remover**. A causa é `three.js` +
`@react-three/fiber` sem os tipos de `JSX.IntrinsicElements` registrados.

**O backend tambem ja esta vermelho** — 6 falhas pre-existentes, anteriores a qualquer
remocao. Portanto o criterio para os blocos de backend e **nao piorar**: `rspec` tem que
terminar com **no maximo 6 falhas**, e as mesmas 6. Uma falha nova e do bloco.

Portanto o critério de aceite do Bloco 1 é objetivo e forte: **depois de remover o
AI9-022, o type-check tem que ficar em 0 erro.** Qualquer erro remanescente foi
introduzido pela remoção e precisa ser corrigido antes do commit.

## Ordem de remoção — por dependência, folhas primeiro

Derivada do grafo do ai9 e das dependências declaradas em
`.migration-ai9/ai9-feature-selection.md`.

| # | Bloco | IDs | Por que nesta posição |
| - | ----- | --- | --------------------- |
| 1 | Folhas visuais + landing | 021, 022, 023, 024, 025, 026, 027, 028, 029, 031, 032 | Nada depende delas. Zera o baseline. Inclui apontar `/` para o login (DEC-13.3) |
| 2 | Analytics | 011, 012, 013 → **010** | 011/012/013 só dependem de 010; saem antes, depois o hub `TrackedEvent` |
| 3 | Conteúdo | 019, 020, 015, 017, 004 → **005 (parcial)** | Folhas do bloco de IA primeiro; 005 por último porque o login depende dele (DEC-14) |
| 4 | Comercial | 003, 001, 018 → **refatorar `Sidebar`** → **002** | O menu é montado a partir de `plan_features`; a nav precisa ser desacoplada **antes** de remover 002 |
| 5 | Meta | 009 | Limpa as `has_many` de `chat_flow` |
| 6 | Leads | 006 | Hub `Lead` |
| 7 | Operations | 014 | A colisão de nome mais perigosa; todos os FKs para `Operation` já saíram |
| 8 | Desacoplar o chatbot | 007 (adapta) | Só depois que leads/Operations/Meta saíram |

## Regras que valem para todo bloco

1. **Escopo pelo grafo.** Antes de apagar, listar os nós que pertencem **só** à feature.
   `graphify explain "<nó>"` a partir da raiz do repo.
2. **Infra compartilhada não sai.** Se um item mantido (AI9-007/008/016/030/033/034/035)
   ou uma feature legada migrada também usa, fica — e a dependência é anotada.
3. **Das folhas para a raiz:** frontend (telas, componentes, rotas, nav, estilos) →
   backend (endpoints, services, jobs, policies) → dados (models, migrations, schema).
   Assim nunca sobra referência pendurada no meio do caminho.
4. **Migrations: apagar o arquivo, não escrever um "drop".** A base ai9 é um projeto
   novo sendo preparado para este cliente — a feature nunca foi necessária aqui. Apagar
   a migration exclusiva e limpar o schema, como se nunca tivesse sido gerada. **Isto
   nunca toca dado legado migrado** — aquilo é trabalho reversível do data engineer.
5. **Sem referência solta.** Item de menu, registro de rota, feature flag, string de
   i18n, seed e import que apontavam para a feature saem junto.
6. **Verificar.** Type-check (e specs, nos blocos de backend) tem que voltar **igual ou
   melhor** que o baseline. Nunca pior.
7. **Um commit por bloco**, com a lista do que saiu — para reverter cirurgicamente.
8. **Registrar** em `.migration-ai9/removed-features.md` e virar o ledger
   `to-remove` → `removed`.

## Armadilhas já identificadas (não descobrir na hora)

- **`Sidebar` × `plan_features` (AI9-002).** O menu lateral é montado a partir das
  features do plano. Remover 002 sem refatorar a navegação quebra o console inteiro.
  Também mexe em `PermissionsSyncService`.
- **Login × WhatsApp (AI9-005 × AI9-030) — ATUALIZADO pelo DEC-14, que revoga o DEC-13.4.**
  `code_validation.rb:27`, `magic_login.rb:25,70,106` e `registration.rb:60,91,120`
  aceitam `method: %w[email whatsapp]` e **continuam como estão** — o usuário decidiu
  manter o login por WhatsApp. Por isso o AI9-005 é **remoção parcial**: fica o mínimo
  que o envio exige (`evolution_connection.rb`, `api/whats/v1/instances.rb`,
  `polemk_instance_service.rb`, model `PolemkInstance` + tabela,
  `evolution_reconnect_job.rb`, `WhatsappPage.tsx`), porque
  `EvolutionConnection.send_message` resolve a instância via `PolemkInstance.first` e
  isso exige o pareamento por QR. Saem chats, grupos, inbox e webhooks.
  **Não** mexer nos 6 endpoints de auth.
- **Rota catch-all `/:code` (AI9-003).** Fica órfã ao remover cupons; limpar em `App.tsx`.
- **Rota `/` (AI9-021).** Ao remover a landing, apontar para a tela de login **na mesma
  tarefa** — não deixar a raiz quebrada entre commits.
- **`Purchase` é compartilhado** entre AI9-001 e o funil de AI9-010: sai com o bloco 2.
- **Chatbot (AI9-007).** Todos os `belongs_to` são `optional: true`, então a remoção de
  leads/Operations não quebra por constraint — mas há **81 referências a `Lead`** em 10
  arquivos de `app/services/ai/`, incluindo o nó `save_to_lead.rb` e o `tool_executor.rb`
  (34 referências). O bloco 8 trata isso explicitamente.

## Avisos de ambiente (descobertos executando os blocos)

- **NAO use `git stash` neste repo.** O agente do Bloco 2 usou `stash push -u` / `pop` e o
  working tree voltou com ~694 arquivos reescritos em **CRLF**, alem de renomear um arquivo
  versionado. Ele detectou, comparou byte a byte e restaurou tudo do HEAD — mas o custo foi
  alto. **Use `git worktree`** se precisar de arvore limpa.
- **`ruby`/`bundle` so existem no WSL**, e ha conflito de versao pre-existente:
  `.ruby-version` diz **3.4.9** e o `Gemfile` diz **3.2.3** (ja registrado em
  `upstream-flags.md`, item 2).
- O baseline do backend estava registrado so como **numero** (6 falhas), sem a lista. O
  agente do Bloco 2 resolveu certo: rodou `rspec` em HEAD e **comparou nome a nome**.
  **Para os proximos blocos, registre a LISTA das falhas**, nao so a contagem — senao nao
  da para provar que nenhuma e nova.
  Falhas atuais: **5**, subconjunto exato das 6 originais. A que sumiu foi
  `spec/models/lead_hub_push_spec.rb`, que pertencia ao proprio AI9-013.

