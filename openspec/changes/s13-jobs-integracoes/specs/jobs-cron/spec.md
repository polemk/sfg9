## ADDED Requirements

### Requirement: SFG-S13-01 — Expurgo programado da trilha e do log de e-mails
O ai9 **MUST** expurgar, por job agendado (`sidekiq-cron`, ver OPS-472), os registros de
`trackings` e do log de e-mails (DB-481) mais antigos que um **prazo de retenção
configurável**, registrando no log a quantidade removida por tabela.

Motivo: DB-461 exige "política de retenção" e mede **4 registros de trilha por execução de
job**; DB-481 acrescenta uma linha por e-mail enviado. Nenhum requirement existente descreve
o expurgo, e a base ai9 **não tem nenhum padrão de expurgo** desde que o
`PurgeDiscardedDraftsJob` saiu no trim (lacuna registrada em
`.migration-ai9/map/data-infra.md` §4). Sem isto as duas tabelas crescem sem limite.

O prazo **MUST** vir de configuração (CFG-02), nunca de constante no código, e o job
**MUST NOT** capturar exceção sem relançar (contrato D-C).

#### Scenario: registro além do prazo é removido
- **GIVEN** um prazo de retenção de N dias e registros de trilha com N+1 dias
- **WHEN** o job de expurgo roda
- **THEN** os registros com mais de N dias são removidos e a quantidade removida aparece no log

#### Scenario: registro dentro do prazo é preservado
- **GIVEN** registros de trilha e de e-mail dentro do prazo de retenção
- **WHEN** o job de expurgo roda
- **THEN** nenhum deles é removido

#### Scenario: falha do expurgo é visível
- **GIVEN** uma falha de banco durante o expurgo
- **WHEN** o job executa
- **THEN** a exceção propaga, o Sidekiq retenta e a falha fica visível — o job não termina em sucesso silencioso
