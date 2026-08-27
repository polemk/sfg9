# Analise do dump de producao — 26/08/2026

Fontes entregues pelo usuario: `sfg-31-may-25.sql` (133,4 MB, texto puro, `pg_dump` 13.4) e
`sfg-31-may-25.tar` (42,3 MB, `public/system/`).

**Analisados SEM restaurar o banco e SEM extrair o tar**, por instrucao explicita do usuario:
*"não é para inflar o dump nem o sistema de arquivos agora é só para analise e desbloquear as
outras tarefas"*. Tudo abaixo saiu de leitura em fluxo do texto do dump e de `tar -tvf`.

## 0. O dump e o certo, e e atual

- E o Safegold em Rails (tem `risk_*`, `renegotiations`, `livetat_auth_*`), **nao** o Django
  anterior que estava no repositorio e que fez a introspeccao da S14 abortar.
- **56 tabelas com dados.** Dado mais recente por tabela: `risk_entries` 31/05/2025,
  `receivable_entries` 30/05/2025, `indicator_entries` 23/05/2025. Bate com o nome do arquivo.
  **O sistema esta em uso**; nao e backup velho.
- Faixa total: 27/02/2022 a 31/05/2025.

## 1. O ACHADO PRINCIPAL — 24 migrations do repositorio NUNCA rodaram em producao

`schema_migrations` de producao tem **114 versoes**; o repositorio tem **138**. A ultima que
rodou foi **20220525124802 (25/05/2022)** — ou seja, **em tres anos de uso, nenhuma migration
nova subiu**. E o inverso e limpo: **0 migrations em producao ausentes do repositorio.**

As 24 nao aplicadas nao sao ruido: sao **familias inteiras de recurso**, todas de jun–ago/2022.

| Familia | Migrations que nunca subiram | Fatia afetada |
| --- | --- | --- |
| Operacoes de risco tipadas | `create_risk_operation_types`, `create_risk_movement_types`, `create_risk_operations`, `create_risk_movements`, `create_risk_operation_extensions`, `create_risk_operation_subtypes`, `add_risk_operation_type_to_receivable_entries` | **S7** |
| Limites tipados | `change_risk_control_fields` | **S5** |
| Operacoes estruturadas | `create_structured_operation_types`, `create_structured_operations` | **S8** |
| Cobrancas | `create_charges` | **S11** |
| Remuneracoes | `create_remunerations`, `add_title_to_remuneration` | S7/S8 |
| Recibos | `create_receipts`, `add_date_and_operation_title_to_receipts` | S8 |
| Garantias de projeto | `create_project_guarantees`, `create_project_guarantee_types` | **S4** |
| Colunas avulsas | `add_discount_values_to_renegotiation`, `add_agent_to_carriers`, `add_has_bi_to_projects`, `add_city_column_to_carriers`, `add_company_column_to_availability_entries`, `add_is_adjusted_column_to_availability_templates`, `add_original_value_column_to_availability_entries` | S4/S9/S11 |

### Por que isso importa mais do que parece

O **DEC-30** governa a migracao inteira e diz: *"o legado e um sistema validado, entao replique
regra e calculo como estao"*. **Essa premissa vale para o que RODOU** — tres anos de uso real
validam o comportamento. **Ela nao vale para o que nunca subiu.** Codigo escrito em 2022 e nunca
executado em producao nao e "validado": e rascunho abandonado, e pode conter defeito que nenhum
usuario jamais encontrou porque nenhum usuario jamais chegou nele.

Isso **nao decide** que essas familias saem do escopo — o DEC-22 (escopo completo) continua de pe
e a decisao e do usuario. O que muda e o **criterio de verificacao**: onde nao ha producao para
comparar, o golden test nao tem oraculo. Ou se replica o codigo tal como esta (assumindo o
defeito junto), ou se trata como recurso novo e se decide o comportamento correto.

## 2. As oito consultas — respondidas

Duas **nao podiam rodar como escritas**: a coluna que elas consultam nao existe.

| # | Pergunta | Resposta medida |
| --- | --- | --- |
| 1 | `availability_templates.default_position` existe? | **NAO EXISTE** — zero ocorrencias no dump inteiro, e nenhuma migration a cria |
| 2 | `resource_kinds` tem uso? | **0 de 28.131** `receivable_entries` tem `resource_kind_id`; a tabela `resource_kinds` tem **0 linhas** |
| 3 | `geolocations` tem linhas? | **0 linhas** |
| 4 | `risk_entries` tem dado? | **642.447 linhas** (a maior tabela do sistema) |
| 5 | Limites no formato pre-2022? | **TODOS os 600.** `risk_controls` **nao tem** coluna de tipo — a migration `change_risk_control_fields` nunca subiu |
| 6 | Alguem entra so com username? | **0 de 135** usuarios. **Nao e bloqueador de cutover** |
| 7 | Rebaixados pela precedencia invertida de 2021? | As colunas `is_staff`/`is_superuser` **nao existem** — o legado usa `livetat_auth_role_types` |
| 8 | Remuneracao com taxa fora de 0–100? | A tabela `remunerations` **nao existe em producao** (migration nunca subiu) |

### O que cada resposta destrava

- **(2) 10 IDs viram `dropped` com evidencia** (BE-307, BE-720..724, FE-307, DB-286, DB-289,
  DB-294), a S8 encolhe e **P-041 desaparece junto**.
- **(3) 12 IDs viram `dropped` com evidencia** (DB-592, DB-431, DB-480, OPS-481, OPS-482, FE-483,
  BE-435..440); as tarefas 6.5–6.9 da S13 somem e **P-092 vira codigo morto antes de nascer**.
  Confirma a **DEC-92**.
- **(4)** A fatia R8 **nao** e descartada: tabela e model sao portados, sem tela — que e
  exatamente o que a **DEC-57** ja decidiu.
- **(5)** Fecha o **P-018**, e nao no sentido de "sobrou alguma linha antiga": **nao existe linha
  no formato novo**. O conversor de ETL da S5 e 4 colunas fixas -> linhas tipadas, para 600
  registros. Distribuicao dos valores nao-zero: auto-liquidaveis 457, comissaria 151, fomento
  131, intercompany 28.
- **(6)** Fecha o **P-049** em "(a) seguir". **Deixa de ser bloqueador de cutover.**
- **(1)** E defeito de verdade, nao pergunta de escopo — veja a secao 3. **Fecha o D-06.**

## 3. D-126 (novo) — `default_position` quebra a listagem de padroes de disponibilidade

> **Correcao de 26/08/2026 — colisao de identificador.** Este defeito foi batizado aqui de
> **"D-125"**, mas o **D-125 ja existia** no `legacy-defects.md` desde o inventario: e o
> `ux_kit19` parcialmente vivo. O defeito abaixo passou a ser o **D-126**, e as referencias em
> `s11/tasks.md`, `improvements-log.md` e `parity-ledger.md` foram corrigidas.
> **O D-125 do `ux_kit19` nao foi tocado.**
>
> E ele nao e "defeito novo": e a **resposta do D-06**, que estava em "perguntar" exatamente
> sobre esta coluna desde o inventario.

A coluna nao existe no banco e nenhuma migration a cria. E o legado a usa **como coluna SQL**:

- `app/controllers/pub/availability_templates_controller.rb:22` -> `order!(default_position: :asc)`
- `app/views/pub/console/parts/availability_templates/list/_child_widget.html.erb:40` -> idem
- mais duas views que chamam `at.default_position` como metodo, e **nao ha metodo no model**.

`order!(default_position: :asc)` emite `ORDER BY default_position ASC` e o Postgres levanta
`UndefinedColumn`. **Nao ha o que replicar aqui**: e uma das excecoes previstas no DEC-30 ("nao
ha legado a replicar"). A S11 ordena pela coluna `position`, que existe, e registra a divergencia.

## 4. Contrato C3 confirmado com dado de producao

`livetat_auth_role_types` traz a hierarquia real do legado:

| Papel | `hierarchy` no legado | Nivel no ai9 (DEC-41) |
| --- | ---: | ---: |
| OG | **1111** | 1 |
| Admin | **998** | 2 |
| Gerente | **888** | 3 |
| Colaborador | **799** | 4 |

**No legado, MAIOR numero = mais poder. No ai9, MENOR numero = mais poder.** A inversao do C3
deixa de ser inferencia de leitura de codigo e passa a ser **medida**. O `Legacy::RoleMap` da S14
esta certo, e o teste que reprova aritmetica sobre `hierarchy` esta protegendo o lugar certo.

## 5. `public/system/` — reconciliado 100%, DEC-84 destravada

655 entradas, 41,8 MB de arquivo. Cruzamento contra o banco, **sem extrair**:

| Acervo | Banco | Tar | Orfao (banco sem arquivo) | Orfao (arquivo sem banco) | Nome divergente | Tamanho divergente |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Anexos de renegociacao (`files/`) | 44 | 44 | **0** | **0** | **0** | **0** |
| Avatares de usuario (`avatars/`) | 135 | 135 | **0** | **0** | — | — |

Mais 5 `full_logos`, 5 `symbol_logos` e 5 `text_logos`. Soma dos anexos de renegociacao no banco:
**37,6 MB**, batendo com o tar.

`active_storage_attachments` e `active_storage_blobs` tem **0 linhas** — o legado guarda anexo em
**Paperclip** (`file_file_name`, `file_file_size`), sob `public/system/`. A conversao para
ActiveStorage e trabalho do conversor da S9, e agora tem origem completa para trabalhar.

## 6. Confirmacoes do que a S14 ja tinha medido

- `livetat_auth_user_infos` **nao tem** coluna `phone`: so `phone_country_code`, `phone_area_code`
  e `phone_number`. O achado ETL-S14-01 estava certo, e agora esta confirmado contra producao.
- `is_phone_checked` existe (DEC-74).
- `pictures`, `delayed_jobs`, `livetat_auth_omni_providers` e `geolocations` tem **0 linhas** —
  o `do_not_migrate` da S14 esta correto para todas.

## 7. O que continua pendente do usuario

**Uma decisao**, nao um dado: o que fazer com as 7 familias de recurso que existem **so no
codigo** e nunca rodaram em producao (secao 1). Ela afeta S5, S7, S8, S11 e parte de S4.

---

## 8. CORRECOES a este documento, medidas EXECUTANDO o ETL contra o dump (26/08/2026)

Esta analise foi feita lendo o dump com script. Depois dela o motor da S14 **rodou** contra o
mesmo arquivo (`baseline`, `introspect`, `dry_run`, `attachments`, `reconcile`), e quatro
coisas que estao escritas acima nao se sustentaram. Ficam aqui, e nao apagadas la em cima,
porque saber **como** a conta errou vale mais que a conta certa sozinha.

| O que este documento diz | O que a execucao mediu |
| --- | --- |
| Secao 3 chama o defeito do `default_position` de **D-125** | No catalogo (`legacy-defects.md`) **D-125 e o `ux_kit19`**. O numero certo e **D-126**, que e o que o `parity-ledger.md` e o `improvements-log.md` ja usam. Corrigido no titulo da secao 3 |
| Secao 5: "`public/system/` reconciliado 100%" — 44 anexos e 135 avatares | **Verdade em contagem e em tamanho, e insuficiente.** Faltavam **3 avatares de projeto** (`projects.avatar`, 342.414 B) na conta, e um dos 44 documentos financeiros — `renegotiation_attachments#45`, `ANEXO_INSTRUMENTO_DE_GARANTIA.pdf` — **tem 0 byte no banco E no disco**. Reconciliacao de contagem e de tamanho passa; o documento nao existe (**D-133**). Alem disso, **121 dos 135 avatares sao o mesmo placeholder `missing.jpg`** |
| Secao 5: "5 `full_logos`, 5 `symbol_logos`, 5 `text_logos`" | Sao **entradas de `tar -tvf`**, nao arquivos. Sao **3 arquivos** por logo (original + thumb + preview) e **1 linha** em `app_themes`. Do acervo so o `_original` viaja: o ai9 gera variante sob demanda |
| Secao 6: as confirmacoes sobre `livetat_auth_users` | Faltou a mais importante. **`is_active` nao e o flag de bloqueio do legado — `deactivated` e**, e e o unico `boolean` do schema inteiro. Cruzamento: 50 ativos, **72** com `is_active=1, deactivated=t` e 13 com `is_active=0, deactivated=t`. O conversor bloqueava so por `is_active` e deixaria **72 contas hoje impedidas de entrar no legado entrarem no ai9** (**D-128**, corrigido) |

### O que a execucao acrescentou, e que a leitura nao tinha como ver

- **`memberships.role`**: 669 de 1.134 (**59%**) tem valor que o **proprio model do legado
  nunca declarou** — "Gerente" 655 e "Colaborador" 14, escritos pelo ETL de 2021 a partir da
  precedencia invertida do Q-16. O `CHECK` do ai9 recusa os dois (**D-127**). **Aguarda
  decisao do usuario** — `upstream-flags.md` #S14-1.
- **`action_text_rich_texts` tem 512 linhas** (Indicator 485, HelpItem 25, Contract 2). Sao
  as "instrucoes" dos indicadores e os textos de ajuda, e **nao moram em coluna nenhuma**:
  carregar `indicators` sem elas perde 485 descricoes sem deixar rastro. Ganhou conversor.
- **`carriers.bank_code`**: 229 de 328 sao codigo de fantasia (`8888` x181, `999` x31,
  `9999` x13, `888` x4) e 83 sao nulos (**D-130**).
- **`username` vazio em 72 de 135** — string vazia, nao nula (**D-131**), e **7 usuarios com
  `default_project_id = 0`** (**D-132**).
- **Tres renegociacoes com ano impossivel**: `0020-08-21`, `0020-09-21`, `0009-12-21`
  (**D-129**).
- **Volumetria total: 782.742 linhas em 56 tabelas**, e **772.234 delas passaram pelos
  conversores** no dry-run, com zero escrita.
- **Fuso confirmado sobre dado real**: 2016-2019 UTC-2 e 2020+ UTC-3, com a hora local
  reexibida identica nos 11 anos. Sobre instantes **reais** da origem so ha 2022-2025 — o
  sistema Rails comeca em 27/02/2022; anos anteriores so existem em coluna `date`, sem hora.
- **Cobertura**: **6 tabelas com dado e sem dono declarado** — `trackings` (6.076),
  `livetat_auth_abilities` (2.224), `livetat_feedback_states` (8), `livetat_feedback_contexts`
  (4), `livetat_auth_client_applications` (3) e `app_themes` (1). Cada uma precisa de
  conversor ou de descarte com motivo antes da janela.
- **C3, o outro lado da medicao**: `livetat_auth_roles` tem 135 linhas e a distribuicao e
  **OG 6, Admin 11, Colaborador 118, Gerente 0**. A hierarquia da secao 4 esta confirmada, e
  **nao existe conta com papel global "Gerente" em producao** — para exercitar esse papel na
  janela e preciso criar conta de teste no ai9, nao ha conta migrada para usar. (Cuidado com
  o homonimo: "Gerente" aparece 655 vezes em `memberships.role`, que e outra coisa — ver
  D-127.)

---

## Adendo — 26/08/2026, S9: o que a EXECUCAO do verificador de paridade mediu

Fonte: `rake sfg_etl:renegotiation_parity SOURCE=dump DUMP=sfg-31-may-25.sql`
(`Sfg::Etl::Parity::Renegotiations`). Nada foi carregado no banco de destino — a DEC-102 adiou
a **carga**, nao a **conferencia**.

### O numero

**47.170 comparacoes** sobre a populacao inteira — 169 renegociacoes x 19 agregados, 5.124
parcelas x 8 colunas, 1.230 pagamentos x 2 colunas — com **47.162 iguais, 0 divergencia de
precisao e 0 REGRESSAO**.

As 8 divergencias sao a mudanca **declarada** do D-45 e agora tem lista nominal: as
renegociacoes de legado **#65, #136, #137, #140, #163, #178, #180, #202** passam de `Pago`
para `Inconsistente` no dia do cutover. No legado a linha que escrevia "Inconsistente" era
apagada pela seguinte (`renegotiation.rb:118-123`), entao o estado nunca chegava ao banco e os
dois filtros da tela ficavam inertes.

### Uma hipotese que a execucao REPROVOU

A secao 1 acima registra que `add_discount_values_to_renegotiation` (20/06/2022) e uma das 24
migrations que nunca subiram. A leitura do codigo levava a uma conclusao forte:
`renegotiation.rb:113` faz `self.total_value_with_desagio = self.original_value -
self.desagio_value`, e num banco sem essas colunas isso e `NoMethodError` — logo `update_values`
nunca terminaria em producao, e com ele morreria o cron diario
`CRONFacade.update_renegotiations_counters`.

**Falso.** Os agregados gravados batem com a soma das parcelas em 47.162 de 47.170
comparacoes, **inclusive `overdue_installments` conferido na data do proprio `updated_at`** —
que so bate se o recalculo rodou. Logo o recalculo rodava, e a conclusao e a outra:

> **A producao roda um commit anterior a 20/06/2022.** O repositorio nao esta a frente apenas
> nas migrations: esta a frente tambem no CODIGO da aplicacao.

Isso importa para o cutover por um motivo pratico: **`sfg/` nao e uma foto do que esta no ar**.
Onde o repositorio e a producao divergirem, o DEC-30 ("o legado e sistema validado") vale para o
que ESTA no ar. Tres anos de uso validam o comportamento executado, nao o commitado.

### `attachments_count` — a conferencia da DB-195, medida

| Medida | Valor |
| --- | --- |
| Renegociacoes na origem | 169 |
| Com `attachments_count` **NULO** | **134** |
| Com contador **fora** da contagem real | **0** |
| Com anexo de fato | 35 |
| Anexos totais | 44 |

O NULO e o `nil > 0` que derrubava o detalhe com `NoMethodError`. No ai9 a coluna e
`null: false, default: 0`, entao ele vira 0 — que e o numero certo para quem nao tem anexo.
Onde o legado escreveu numero, ele estava **certo**: copiar e seguro, e o `fixups.rb` reconcilia
no destino de qualquer forma.

### O acervo, lido de verdade (e nao so listado)

A secao 5 acima reconciliou **nome e tamanho**. Este adendo leu os **bytes**: 44 arquivos,
**39.424.330 bytes**, tipo apurado pelos magic bytes (Marcel) — 41 `application/pdf`, 1 `xlsx`,
1 `docx`, 1 `zip`, **0 fora da allowlist** do catalogo do ai9. Nenhum arquivo passa dos 5 MB
(o maior tem 5.072.833 B, contra o teto de 5.242.880).

**43 dos 44 foram religados por ActiveStorage** contra o acervo real, cada um provado por
tamanho **e** SHA-256 depois de anexado, e a segunda passada nao criou blob novo. O 44º e o
**D-133** — 0 byte no banco e no acervo —, e ele **nao** e reanexado: fica sem binario e
nomeado no relatorio.
