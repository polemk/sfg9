# Fragmentos de inventário (Phase 1)

Cada unidade do worklist escreve seu próprio arquivo aqui; o QA consolida tudo em
`../feature-inventory.md`. Faixas de ID reservadas por unidade (evita colisão em
execução paralela):

| Unidade | Faixa numérica (BE/FE/DB/OPS) |
| ------- | ----------------------------- |
| auth-users | 001–049 |
| companies-carriers | 050–079 |
| projects | 080–119 |
| availability | 120–149 |
| receivables | 150–189 |
| renegotiations | 190–229 |
| risk | 230–279 |
| structured-operations | 280–309 |
| indicators | 310–329 |
| contracts | 330–349 |
| help-faq | 350–369 |
| themes | 370–389 |
| console-admin | 390–429 |
| misc-domain | 430–459 |
| jobs-cron | 460–479 |
| integrations | 480–499 |
| engines | 500–539 |
| data-schema | 540–599 |
| ops | 600–639 |
| public-site (dropped) | 640–659 |

## Faixa de overflow: **700–799**
A faixa de `projects` (080–119) esgotou — o CRUD de `project_guarantee_types` ficou
anexado a `BE-119` e precisa de numero proprio. Overflow de qualquer unidade usa
**700–799**, alocado pelo QA na consolidacao, com a unidade de origem anotada.

| Overflow | Origem | Motivo |
| -------- | ------ | ------ |
| BE-700 (a alocar) | projects | CRUD de `project_guarantee_types`, hoje colado em BE-119 |
| a alocar | indicators-contracts | usou sub-IDs decimais (`BE-318.3`) ancorados no ID vizinho porque 20 numeros nao cobriam os endpoints de `project_indicator_connections` |
| a alocar | structured-operations | ~40 rotas em 30 numeros: `new`/`edit` foram para a tabela FE e o CRUD de resources ficou agrupado em BE-307/308 |

**Regra do QA na consolidacao:** todo sub-ID decimal e todo agrupamento vira um ID
proprio na faixa 700-799. Um endpoint = um ID. Agrupamento esconde feature.
