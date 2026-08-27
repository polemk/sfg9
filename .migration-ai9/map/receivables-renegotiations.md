# Migration map — sfg → ai9 · **Recebíveis, Renegociações e Contratos**

> Bloco de 3 capabilities, **246 IDs**: `receivables` (108), `renegotiations` (98),
> `contracts` (40). Escrito no Phase 2 (25/08/2026), sobre a base ai9 **depois do trim**
> (`.migration-ai9/ai9-base-catalog.md`).
>
> **Este é o bloco onde número errado destrói a confiança no sistema inteiro.** Duas
> regras não negociáveis atravessam tudo o que está abaixo:
>
> 1. **DEC-02 — dinheiro em float é para replicar, não para consertar.** A decisão é do
>    usuário e está registrada no `improvements-log.md` como melhoria **recusada**. A
>    sequência de operações, os casts e os pontos de arredondamento do legado são
>    reproduzidos para que os totais **batam**. Ninguém troca por `BigDecimal` por
>    iniciativa própria. O que o DEC-02 **não** cobre é o D-10 (`Infinity`/`NaN` gravado
>    porque a guarda só existia no cliente) — isso é registro corrompido, não precisão,
>    e continua `corrigir`.
> 2. **Performance nunca muda resultado.** Índice, FK, `find_each`, agregação em uma
>    consulta: tudo bem-vindo. Uma query "otimizada" que muda um centavo é defeito, não
>    melhoria. Todo `build` de cálculo nasce com **teste golden** comparando contra
>    valores extraídos do legado.

## Resumo por estratégia

| Capability | reuse | adapt | build | Total |
| ---------- | ----- | ----- | ----- | ----- |
| `receivables` | 10 | 10 | 88 | 108 |
| `renegotiations` | 12 | 13 | 73 | 98 |
| `contracts` | 3 | 10 | 27 | 40 |
| **Total** | **25** | **33** | **188** | **246** |

O número de `build` é alto e é **correto**: o catálogo já enuncia que *"o domínio de
crédito do Safegold é `build` inteiro"*. O reuso deste bloco está na infraestrutura — e é
grande: **toda** linha `build` abaixo reusa auth, Grape, Kaminari, ActiveStorage, Action
Cable, React Query, design system e Recharts. Forçar `adapt` sobre um modelo do ai9 que
não foi feito para borderô seria pior que `build`.

---

## Legenda de infraestrutura reusada

Códigos usados na coluna "Equivalente ai9" para não repetir o mesmo caminho 246 vezes.
**Todos foram abertos e conferidos**, não inferidos do catálogo.

| Código | Arquivo(s) reais na base ai9 | O que dá de graça |
| ------ | ---------------------------- | ----------------- |
| **[GRAPE]** | `backend/app/controllers/api/v1/base.rb` (mount + `namespace`); `api/v1/controller_helpers.rb` (`process_service_response`, `authenticate_user!:25`, `require_og!:37`, `restrict_visitor_access!:44`); `api/v1/media.rb` como endpoint-modelo | Roteamento, `params do…end` (validação declarativa de verdade), Swagger, formato de erro |
| **[SVC]** | `backend/app/services/medium_service.rb`, `users_service.rb` (`class << self` + `ApiResponseHandler`) | Onde a regra financeira vai morar — **um lugar só** (corrige D-09) |
| **[ENT]** | `backend/app/controllers/api/entities/` (`Grape::Entity`, `documentation:` em todo `expose`) | Serialização e contrato de API documentado |
| **[AUTHZ]** | `backend/app/models/{permission,user_permission}.rb`; `api/v1/permissions.rb`; `PermissionAuditLog` | Base sobre a qual a matriz aprovada (DEC-18) é implementada. **Não criar mecanismo paralelo** |
| **[KAM]** | `kaminari` (`backend/Gemfile:85`) + `set_pagination_headers` + CORS expondo `X-Total-Count` (`config/initializers/cors.rb`) | Paginação que funciona de verdade (corrige D-20) |
| **[RQ]** | `@tanstack/react-query@5` + `frontend/src/lib/api/{client.ts,endpoints.ts,types.ts}` + `zustand` | Cache, `isLoading` vs `isFetching`, `isError`, `refetch`, invalidação |
| **[DS]** | `frontend/src/components/ui/*` (Table, Card, Badge, Input, Label, Button, dialog, tabs, accordion, drawer, switch, SearchableSelect/MultiSelect, Tooltip, Progress); `Layout.tsx`, `PageHeader.tsx`, `SideDrawer.tsx`, `ThemeProvider.tsx`+`ThemeToggle.tsx` (light **e** dark), `components/mobile/*` | Toda tela deste bloco se monta com isto |
| **[CABLE]** | `backend/app/channels/{application_cable,permissions_channel.rb,public_events_channel.rb}`; `config/cable.yml` (redis); `frontend/src/hooks/useCable.ts` (auth por cookie httpOnly `cable_token`) | **Polling é proibido** (Princípio 10) |
| **[AS]** | ActiveStorage (`config/application.rb:12`, `config/storage.yml` → Disk); `image_processing` (`Gemfile:10`); `Medium#file_url/optimized_url/small_url` (`app/models/medium.rb:22-72`) como modelo de variantes | Upload, variantes, metadados de imagem |
| **[CHART]** | `recharts@3.5.1`; `frontend/src/components/charts/{RechartsBar,RechartsLine,RechartsPie,theme}.tsx`; `components/kpi/KpiCard.tsx` | DEC-10 |
| **[RICH]** | `has_rich_text` já em uso (`backend/app/models/user.rb:18`); tabela `action_text_rich_texts` já no `schema.rb:30`; front `components/RichTextEditor.tsx` (Slate) e `RichTextInput.tsx` | Conteúdo rico de contrato — **reuso forte e não catalogado** |
| **[CRON]** | `sidekiq-cron` (`backend/Gemfile:38`) + `config/initializers/sidekiq.rb` (agendamento hardcoded em Ruby) | Agendamento único e versionado |
| **[TOAST]** | `sonner` (usado em `MediaPage.tsx`, `UsersPage.tsx`, `Sidebar.tsx`) | Mensagens de sucesso/erro em pt-BR |

---

## 1. Fatias verticais propostas

Ordem de execução. Uma fatia só fecha quando **backend + frontend + teste** dela existem
e rodam — não há fatia "só de model".

| Slice | Descrição (feature ponta a ponta) | IDs | Depende de | Prioridade |
| ----- | --------------------------------- | --- | ---------- | ---------- |
| **SR-1** | **Catálogos de recebível**: carteiras, tipos de recebível, tipos de movimentação (CRUD + busca + classificador único) e seus seeds | BE-185, BE-186, DB-158, DB-159, DB-160, FE-187, FE-188, FE-189, OPS-153 | auth/permissões (`auth-users`), `projects` | **alta** — destrava o formulário de borderô |
| **SR-2** | **Motor de cálculo do borderô (CET)**: as 26 fórmulas em um serviço único, com testes golden contra o legado | BE-155 a BE-182, DB-150, DB-151, DB-152, DB-153, DB-154, DB-155, DB-156, DB-157, DB-161, OPS-159 | SR-1 | **crítica** — é o coração numérico do bloco |
| **SR-3** | **Lista e CRUD de recebíveis**: busca, filtros, ordenação multi-coluna, paginação real, exclusão | BE-150, BE-151, BE-152, BE-153, BE-154, BE-184, OPS-157, OPS-158, FE-150 a FE-164, FE-178 | SR-2, `companies-carriers` | alta |
| **SR-4** | **Formulário de borderô + prévia em tempo real** (a prévia vem do servidor, nunca de conta em JS) | FE-165 a FE-177, OPS-154 | SR-3 | alta |
| **SR-5** | **Integração automática com o controle de risco** (movimento/operação gerada pelo borderô) | BE-183, DB-156 | SR-2, capability `risk` (RiskControl, RiskOperation, RiskMovement) | média — **bloqueada** pelo bloco de risco |
| **SR-6** | **Cobranças e recibos**: pacote de cobrança, geração de recibo por operação, consolidação em lote | BE-187, BE-188, BE-189, DB-162, DB-163, DB-164, DB-165, FE-179 a FE-186 | SR-3, `risk`, `structured-operations` (remunerações) | média |
| **SR-7** | **Carga de dados de recebíveis** (7.746 borderôs / 15.712 tarifas) + índices e FKs + recálculo em massa | DB-166, DB-167, OPS-150, OPS-151, OPS-152, OPS-155, OPS-156 | SR-2, SR-5, SR-6 | alta (é o gate do Phase 4) |
| **SN-1** | **Modelo e agregados da renegociação**: as ~20 colunas derivadas, estado, valor presente, consistência de lançamento | BE-195, BE-196, BE-199, BE-203 a BE-212, DB-190, DB-191, DB-192, DB-194, DB-196, DB-197, DB-198, OPS-195, OPS-196 | `projects`, `companies-carriers` (fornecedores) | **crítica** |
| **SN-2** | **Lista e CRUD de renegociações** | BE-190 a BE-194, BE-197, BE-198, BE-200, BE-201, FE-190 a FE-203 | SN-1 | alta |
| **SN-3** | **Previsões (parcelas) e pagamentos**: lote, avulsa, edição, exclusão em lote, cascata de recálculo | BE-202, BE-213 a BE-224, FE-213 a FE-227, FE-229, OPS-190, OPS-191 | SN-1, SN-2 | alta |
| **SN-4** | **Detalhe da renegociação**: abas, cards de resumo com atualização por **Action Cable** | FE-204 a FE-207, FE-228 | SN-3 | média |
| **SN-5** | **Anexos da renegociação** (kt-paperclip → ActiveStorage/`Medium`, entrega **privada** e autorizada) | BE-225 a BE-229, DB-193, DB-195, FE-208 a FE-212, OPS-192, OPS-193, OPS-194 | SN-2, [AS] | média — carrega 5 dos defeitos de segurança do bloco |
| **SN-6** | **Carga de dados de renegociações** + auditoria de divergências antes da carga | DB-199, OPS-197 | SN-3, SN-5 | alta |
| **SC-1** | **Documento de contrato e versionamento**: publicação append-only, histórico, console | BE-331, BE-334 a BE-339, BE-345 a BE-349, DB-330, FE-338 a FE-342, OPS-330, OPS-332 | auth/permissões, [RICH] | média — **independente dos outros dois domínios**, pode ir em paralelo |
| **SC-2** | **Página pública e ciclo de aceite**: leitura sem sessão, aceite, pendência, tolerância, bloqueio | BE-330, BE-332, BE-333, BE-340 a BE-344, DB-331, FE-330 a FE-337, OPS-331, OPS-333, OPS-334 | SC-1 | **BLOQUEADA** — depende de D-64/D-65 (ver §5) |

**Caminho crítico:** SR-1 → SR-2 → SR-3 → SR-4 e SN-1 → SN-2 → SN-3 são independentes
entre si e podem correr em paralelo. SR-5 e SR-6 dependem de blocos de outro agente
(`risk`, `structured-operations`) — se atrasarem, SR-3/SR-4 entregam valor sozinhos com
`risk_operation_subtype_id` nulo ("Não associar", DB-156). **SC-2 não deve ser iniciada
antes da resposta às perguntas Q-B1/Q-B2.**

---

## 2. Mapa item por item

### 2.1 `receivables` — backend (BE-150 … BE-189)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| BE-150 | build | [GRAPE] + [KAM] + [ENT] | `api/v1/receivables.rb#search`; `services/receivables/search_service.rb` | Escopo por projeto vem do JWT + membership (DEC-07), não de cookie; `limit`/`offset`/`order` aplicados de fato | Corrige D-16 (vazamento por `receivable_id`) e D-20 (paginação decorativa); data inválida → 422, não 500 | **alto** — mudar o `ORDER BY` final muda a página exibida; travar ordenação com teste | SR-1, `projects` |
| BE-151 | build | [GRAPE] + [SVC] | `services/receivables/create_service.rb` | Borderô + tarifas numa **única transação**, um único recálculo | Corrige D-11 (dois `save` → risco criado com valor errado) e o `save` de tarifa não checado; `user_id` do payload ignorado | **alto** — é o ponto que produziu dado sujo em produção | SR-2 |
| BE-152 | build | [GRAPE] + [SVC] | `services/receivables/update_service.rb` | Upsert de tarifas; payload sem tarifas preserva as existentes; recálculo uma vez só | — | médio | BE-151 |
| BE-153 | build | [GRAPE] + [AUTHZ] | `api/v1/receivables.rb#destroy` | Exclusão em transação com tarifas e operação de risco; `user_is_readonly` checado **no servidor** | Corrige D-17 e D-24 (os dois ramos do ternário respondiam `:ok`) | médio | [AUTHZ], SR-5 |
| BE-154 | **reuse** | `frontend/src/app/App.tsx` + `react-router-dom` + [DS] `Layout.tsx` | — | As 5 rotas REST mortas não existem; a navegação já é do React Router | Nada a construir. Entra no ledger como `dropped` **com evidência** (DEC-09) | baixo | — |
| BE-155 | build | [SVC] | `services/receivables/calculator.rb#tax_buckets` | Soma em 4 buckets a partir das flags | Tarifa com 2 flags conta nos dois buckets **e** `tarifas_outras` fica negativa — replicado (DEC-01/02); o dado inconsistente é **reportado** pelo ETL, não corrigido em silêncio | médio | SR-1 |
| BE-156 | build | [SVC] | `calculator.rb#vlr_bruto_final` | `valor_bruto − vlr_bruto_recusado` | Negativo aceito e propagado, como hoje | baixo | — |
| BE-157 | build | [SVC] | `calculator.rb#qtd_final` | `qtd_titulos − qtd_recusada` | Negativo aceito | baixo | — |
| BE-158 | build | [SVC] | `calculator.rb#float_calculado` | `prz_med_pond_bco − prz_med_pond_emp` | Float negativo preservado | baixo | — |
| BE-159 | build | [SVC] | `calculator.rb#diferenca_float` | `max(calculado − acordado, 0)` | Piso em zero replicado (DEC-01) | baixo | — |
| BE-160 | build | [SVC] + nova tabela `iof_rates` | `calculator.rb#checagem_iof`; `models/iof_rate.rb` | Alíquotas passam a ter **vigência**; a usada é a da data da operação | Corrige D-15. Base negativa continua produzindo IOF negativo (DEC-02) | **alto** — recálculo histórico muda de valor se a vigência for mal carregada; seed das alíquotas 0,000041 / 0,0038 com vigência aberta desde 2016 | SR-2 |
| BE-161 | build | [SVC] | `calculator.rb#valor_total_tarifas` | Soma dos 4 buckets | — | baixo | BE-155 |
| BE-162 | build | [SVC] + [GRAPE] `params do` | `calculator.rb#valor_liquido` + validação | Zero **rejeitado no servidor** (422) | Corrige D-10 — nunca gravar `Infinity`/`NaN` | médio | — |
| BE-163 | build | [SVC] | `calculator.rb#deduction_percents` | 4 percentuais sobre o líquido | Percentual negativo com líquido negativo preservado (DEC-02) | baixo | BE-162 |
| BE-164 | build | [SVC] | `calculator.rb#total_deducoes` | `nil` tratado como zero | Corrige `NoMethodError` em registro legado com `NULL` | baixo | — |
| BE-165 | build | [SVC] | `calculator.rb#vlr_liq_recebido` | Negativo aceito | — | baixo | BE-164 |
| BE-166 | build | [SVC] | `calculator.rb#nominal_rates_bank` | 3 variantes; guardas `< 1` replicadas; a 3ª variante (sem guarda) passa a ser **barrada por validação** em vez de gravar `Infinity` | Corrige D-10 sem alterar as guardas que produzem número | **alto** — o limiar `< 1` (um real) é assimétrico e produz `NULL`; travar em teste | BE-162 |
| BE-167 | build | [SVC] | `calculator.rb#cet_pm_banco_sem_iof` | Guarda olha `prz_med_pond_emp` numa fórmula do **banco** — replicado | DEC-02: parece copy/paste, mas trocar muda o valor exibido. Registrado como Q-B7 | **alto** | BE-162 |
| BE-168 | build | [SVC] | `calculator.rb#cet_pm_banco` | Coluna "CET PM BCO", 4 casas | — | médio | — |
| BE-169 | build | [SVC] | `calculator.rb#nominal_rates_company` | Espelho de BE-166 com `prz_med_pond_emp` | Mesmas guardas assimétricas | alto | BE-166 |
| BE-170 | build | [SVC] | `calculator.rb#cet_pm_emp_sem_iof` | — | — | médio | — |
| BE-171 | build | [SVC] | `calculator.rb#cet_pm_emp` | "CET PM EMP", chave de ordenação `cet`, 4 casas | — | médio | — |
| BE-172 | build | [SVC] + validação | `calculator.rb#cet_sem_float` | `prz_med_pond_emp = 0` barrado **antes** do cálculo | Corrige D-10 (o `before_validation` calculava antes de validar) | médio | — |
| BE-173 | build | [SVC] | `calculator.rb#cet_com_float_total` | Mesma base de BE-171, **2 casas** | DEC-02: a divergência de arredondamento (2 vs 4 na mesma base) é replicada. Registrado como Q-B8 | médio | BE-171 |
| BE-174 | build | [SVC] | `calculator.rb#cet_com_float_sem_iof` | Nulo quando não há IOF relevante (guarda `< 1`) | — | médio | — |
| BE-175 | build | [SVC] | `calculator.rb#pm_multipliers` | Truncados em 2 casas; empresa em branco → nulo | — | baixo | — |
| BE-176 | build | [SVC] + validação | `calculator.rb#valor_liq_correto` | Expoente literal `0.0333…` e aproximação linear replicados; CET acordado negativo → 422 em vez de `NaN` | DEC-02 + correção do D-10. **D-14 continua aberto** (Q-B6) | **alto** — alimenta o `status` do borderô | BE-156 |
| BE-177 | build | [SVC] | `calculator.rb#dif_calc_vlr_liq` | `round(…, 2)` | — | baixo | BE-176 |
| BE-178 | build | [SVC] | `calculator.rb#status` | Dois estados: "OK" / "Diferença" | D-19: não existe baixa/liquidação/vencimento no legado. Não inventar (DEC-09); registrado como Q-B9 | médio | BE-177 |
| BE-179 | build | [SVC] + validação | `calculator.rb#nominal_tax_check` | Denominador zero → 422 | Corrige D-10 | baixo | — |
| BE-180 | build | [SVC] | `calculator.rb#nominal_tax_check_with_float` | `nominal_tax` informada **não** é validada contra as checagens | Divergência continua apenas informativa (Q-B10) | baixo | BE-179 |
| BE-181 | build | model + [SVC] | `models/receivable_entry.rb` (validações) | Obrigatórios, prazos `> 0`, exigência de `RiskControl` ativo; mensagens em pt-BR | Sem janela de data, sem `valor_bruto > 0` — como hoje (Q-B11) | médio | SR-5 |
| BE-182 | build | [SVC] | `services/receivables/create_service.rb` | Tipo derivado do subtipo; `has_safegold_management` copiado do projeto; recusados nulos → zero | — | baixo | `projects` |
| BE-183 | build | [SVC] + transação | `services/receivables/risk_sync_service.rb` | Chamada **explícita** no serviço, não `after_commit`; roda **uma vez**, com o líquido já definitivo; operação estática ausente **falha com erro** em vez de silêncio | Corrige D-11 — e o backfill do Phase 3 precisa **recalcular**, não copiar (dado sujo em produção) | **crítico** — é o defeito que já sujou dado histórico | capability `risk` |
| BE-184 | build | [SVC] | `models/receivable_tax.rb`; `services/receivables/tax_service.rb` | Título e flags denormalizados; exclusão de tarifa **recalcula no servidor** | Corrige D-09 (o recálculo dependia do front chamar `update_and_save()`) | médio | BE-155 |
| BE-185 | build | [GRAPE] + [SVC] + [KAM] + [AUTHZ] | `api/v1/wallets.rb`, `api/v1/receivable_kinds.rb` | 2 catálogos gêmeos, escopo **global** (DEC-07); chave de integração derivada do título | `receivable_kinds#create` passa a responder 422 (respondia 200); chave de ordenação desconhecida ignorada em vez de 500; **`is_active` continua sem efeito** (Q-B12) | baixo | [AUTHZ] |
| BE-186 | build | [GRAPE] + [SVC] | `api/v1/movement_kinds.rb`; `models/movement_kind.rb` | Classificador único validado com mensagem pt-BR; `NULL` conta como zero; `kind` com domínio fechado | Corrige a mensagem crua "Múltiplos tipos". `is_title`/`is_liquidation` sem consumidor (D-74, Q-B13) | baixo | — |
| BE-187 | build | [GRAPE] + [SVC] + [KAM] | `api/v1/charges.rb`; `models/charge.rb` | Estados com domínio fechado; paginação real; exclusão bloqueada devolve erro de negócio | Corrige D-20 (`fetch_loq` nunca chamado) e o `restrict_with_error` que voltava 500 | médio | SR-6 |
| BE-188 | build | [SVC] | `services/charges/receipt_generator.rb`; `models/receipt.rb` | `value = operation_value × (fee/100)` — **multiplicação `decimal × float` e truncamento para `decimal(15,2)` replicados** (DEC-02); tipo desconhecido falha em vez de virar `"???"` | D-72 continua aberto: a fórmula é percentual flat, sem prazo (Q-B14) | **alto** — é a receita faturada | `structured-operations` (remunerações) |
| BE-189 | build | [SVC] + transação | `services/charges/bulk_receipts_service.rb` | Lote inteiro numa transação; cobrança "Faturado" recusa alteração **no servidor** | Corrige D-18 (bloqueio só na UI) e o lote sem transação | **alto** | BE-188 |

### 2.2 `receivables` — frontend (FE-150 … FE-189)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| FE-150 | build | [DS] `ui/Table.tsx`, `PageHeader.tsx`, `Layout.tsx` | `app/pages/receivables/ReceivablesPage.tsx` | 9 colunas ordenáveis, marca Safegold, **light e dark** | — | baixo | BE-150 |
| FE-151 | **reuse** | [RQ] `isLoading` vs `isFetching` | idem | Carga inicial mostra indicador; recarga por filtro não pisca | Comportamento nativo do React Query — não reimplementar | baixo | — |
| FE-152 | build | [DS] `ui/Card.tsx` | `components/ui/EmptyState.tsx` (**novo membro da biblioteca compartilhada**) | Estado vazio genérico | Componente compartilhado, não peça de uma tela só (Princípio 11) | baixo | — |
| FE-153 | adapt | `components/ui/EmptyState.tsx` (FE-152) | idem, variante com termo | Ecoa o termo pesquisado | — | baixo | FE-152 |
| FE-154 | **reuse** | [RQ] `isError` + `refetch`; [TOAST] `sonner` | idem | Falha de lista e de exclusão comunicadas | Corrige o silêncio do legado no `search` | baixo | — |
| FE-155 | adapt | `components/ImpersonateSearch.tsx:46-52` (debounce de 300 ms já implementado) | `hooks/useDebouncedValue.ts` (extrai o padrão como hook compartilhado) | Debounce 300 ms; só-espaços ignorado; **rótulo diz que a busca é por portador** | Corrige o rótulo genérico "Procurar" | baixo | — |
| FE-156 | build | [DS] `ui/dialog.tsx` + `date-fns@4` (+ locale pt-BR) | `components/ui/DateRangePicker.tsx` (**novo compartilhado**) | Intervalo em pt-BR, rótulo "De … a …" | Corrige o rótulo que lia `from.getYear()` no lugar de `to.getYear()` | médio — não existe seletor de data na base | — |
| FE-157 | **reuse** | [DS] `ui/SearchableSelect.tsx` | idem | Filtro por carteira | Inativas continuam aparecendo (Q-B12) | baixo | BE-185 |
| FE-158 | **reuse** | [DS] `ui/SearchableSelect.tsx` | idem | Portadores do projeto corrente apenas | — | baixo | `companies-carriers` |
| FE-159 | adapt | [DS] `ui/Table.tsx` (sem ordenação hoje) | `components/ui/SortableTableHeader.tsx` | Ciclo asc→desc→neutro, chaves acumuladas | Corrige D-20 — a ordenação passa a **funcionar** no servidor, não só na UI | médio — muda a ordem exibida hoje | BE-150 |
| FE-160 | adapt | `components/mobile/MobilePagination.tsx` | `components/ui/Pagination.tsx` (desktop) + o mobile existente | Primeira/anterior/próxima/última + campo de limite (padrão 50) | Corrige D-20 (última página ia para o lugar errado) | médio | BE-150 |
| FE-161 | build | [DS] `ui/Button.tsx`; `hooks/useAuth.ts` | `ReceivablesPage.tsx` | Botão some para somente-leitura; guarda de portador | Corrige a mensagem que falava em "controle de risco" numa tela de recebível | baixo | [AUTHZ] |
| FE-162 | build | [DS] `ui/Tooltip.tsx`, `ui/Badge.tsx` | `components/receivables/ReceivableRow.tsx` | Data `dd/mm/aaaa`, moeda pt-BR, **CET formatado em pt-BR** | Corrige CET impresso cru e o tooltip de descrição que saía vazio | baixo | OPS-159 |
| FE-163 | build | [DS] `ui/dialog.tsx`; `components/mobile/MobileMenuActions.tsx` | `components/ui/RowActionsMenu.tsx` (**novo compartilhado**) + confirmação | Editar/Remover com confirmação | — | baixo | FE-162 |
| FE-164 | build | `hooks/useAuth.ts`; [AUTHZ] | `hooks/usePermission.ts` (**novo compartilhado**) | Ações de escrita somem **e** o servidor recusa | Corrige D-17 — a defesa real passa a ser o servidor | médio | [AUTHZ] |
| FE-165 | build | [DS] `ui/{Input,Label,Card,tabs}.tsx`; `useState` controlado (§5.3 das convenções) | `app/pages/receivables/ReceivableFormPage.tsx` | 10 grupos de campos, calculados somente leitura, tipo de operação imutável na edição | Catálogo vazio não derruba a tela (o legado fazia `Wallet.first.id`) | **alto** — ~40 campos sem `react-hook-form`/`zod` na base (ver §4) | SR-1, SR-2 |
| FE-166 | build | `components/ui/EmptyState.tsx` (FE-152) | idem | Sem portador → formulário suprimido com a razão | — | baixo | FE-152 |
| FE-167 | build | `components/ui/EmptyState.tsx` + `react-router-dom` | idem | Atalho para cadastrar empresa, **também na edição** | Corrige a URL montada com variável `id` indefinida | baixo | `companies-carriers` |
| FE-168 | adapt | [DS] `ui/Input.tsx` | `components/ui/MoneyInput.tsx` (**novo compartilhado**) | `R$ 100.000,00` fora do foco; segundo separador descartado com aviso | — | médio | — |
| FE-169 | adapt | [DS] `ui/Input.tsx` | `components/ui/DecimalInput.tsx` | Vírgula na tela, ponto no envio | — | baixo | — |
| FE-170 | adapt | [DS] `ui/Input.tsx` | `components/ui/IntegerInput.tsx` | Quantidade só dígitos; nº do borderô é **texto** | Corrige os dois handlers conflitantes e o exemplo "Ex: 789" que contradizia o comportamento | baixo | — |
| FE-171 | build | [RQ] + endpoint de cálculo do BE (SR-2) | `api/v1/receivables.rb#preview` + `hooks/useReceivablePreview.ts` | A prévia **chama o servidor** — a conta não é reimplementada em JS | Corrige D-09 na raiz: fórmula em um lugar só. Prévia e gravação passam a coincidir sempre | **alto** — é a mudança de arquitetura mais visível do bloco; exige debounce para não inundar a API | SR-2 |
| FE-172 | build | [RQ] + validação do [GRAPE] | `ReceivableFormPage.tsx` | 5 combinações bloqueiam o salvar **e** o servidor responde 422 pelo mesmo motivo | Corrige D-10 | médio | BE-162, BE-172 |
| FE-173 | build | [DS] `ui/Button.tsx` + [TOAST] | `ReceivableFormPage.tsx` (barra inferior) | Revalida campos-chave; grava **uma vez** e volta à lista | Corrige o acúmulo de bindings `ajax:*` que podia enviar múltiplas vezes | baixo | — |
| FE-174 | build | `MoneyInput`/`DecimalInput` (FE-168/169) | idem | Conversão para formato numérico no envio, reformatação depois | — | baixo | FE-168 |
| FE-175 | build | [DS] `ui/{Button,SearchableSelect}.tsx` | `components/receivables/TaxRows.tsx` | Linha nova no topo, tipos `is_operation` ordenados, totais recalculados | Corrige as máscaras re-registradas a cada clique. Duplicidade de tipo continua permitida (Q-B15) | baixo | BE-186 |
| FE-176 | build | [DS] `ui/dialog.tsx` | idem | Linha não salva some; persistida exige confirmação e recalcula no servidor | Exclusão de tarifa **não** é transacional com o formulário — como hoje (Q-B16) | médio | BE-184 |
| FE-177 | build | `date-fns@4` + [DS] `ui/dialog.tsx` | `components/ui/DatePicker.tsx` (**novo compartilhado**) | Restrição mútua operação/crédito; padrão hoje no cadastro | Sem janela de data, como hoje (Q-B11) | médio | FE-156 |
| FE-178 | **reuse** | [TOAST] `sonner`; `lib/api/client.ts` (formato de erro) | idem | Erros com nome do campo em pt-BR; mensagem distingue cadastro de edição | Corrige o `translate_every_key` nunca chamado e o "foi cadastrado" na edição | baixo | — |
| FE-179 | build | [DS] `ui/Table.tsx` + `Pagination` (FE-160) | `app/pages/charges/ChargesPage.tsx` | Data, Situação, Valor, Operações; lista **paginada** | Corrige D-20 (limite fixo de 1000 no cliente, nenhum no servidor) | baixo | BE-187 |
| FE-180 | **reuse** | [DS] `ui/SearchableSelect.tsx` (×3) | idem | Situação, mês, ano | Ano ganha **opção em branco** (era impossível ver todas as cobranças) | baixo | — |
| FE-181 | build | [DS] `ui/Badge.tsx` + `RowActionsMenu` (FE-163) | `components/charges/ChargeRow.tsx` | `dd/mm/aa`, indicador de faturado, menu oculto para readonly | — | baixo | FE-163 |
| FE-182 | adapt | [CHART] `components/kpi/KpiCard.tsx` | `app/pages/charges/ChargeDetailPage.tsx` | Cabeçalho, totais por classe, extrato por remuneração | Extrato em **uma consulta agregada** (o legado tinha "TODO #7388 otimizar a busca" no código) | médio | BE-189 |
| FE-183 | build | [DS] `ui/dialog.tsx` + [TOAST] | idem | "Faturado" bloqueia seleção **na tela e no servidor** | Corrige D-18 | baixo | BE-189 |
| FE-184 | build | [DS] `ui/Table.tsx` | `app/pages/charges/ChargeReceiptsPage.tsx` | Classe/Data/Tipo/Valor op./Valor remuneração; vinculados pré-marcados | Recibo legado com `date` nulo não quebra a tela | baixo | BE-188 |
| FE-185 | build | [RQ] mutation + [TOAST] | idem | Inclusões e remoções num único lote; falha **reverte a marcação** | Corrige a tela que ficava fora de sincronia com o servidor | médio | BE-189 |
| FE-186 | adapt | [DS] `SideDrawer.tsx` | `components/charges/ChargeDrawer.tsx` | Criação sem "Faturado"; data padrão hoje + 30 dias | — | baixo | — |
| FE-187 | build | [DS] `ui/Table.tsx` + `SideDrawer.tsx` | `app/pages/catalogs/WalletsPage.tsx` | Lista + painel lateral; chave ausente mostra `-` | — | baixo | BE-185 |
| FE-188 | build | idem FE-187 | `app/pages/catalogs/ReceivableKindsPage.tsx` | Mesma estrutura + busca por título | — | baixo | BE-185 |
| FE-189 | build | [DS] `SideDrawer.tsx` + `ui/switch.tsx` | `app/pages/catalogs/MovementKindsPage.tsx` | 9 campos; classificadores mutuamente exclusivos **impedidos na tela** | Corrige o erro cru "Múltiplos tipos" vindo do servidor | baixo | BE-186 |

### 2.3 `receivables` — dados (DB-150 … DB-167)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| DB-150 | build | `backend/db/schema.rb` (padrão `id: :uuid, default: gen_random_uuid()`); pgcrypto | `db/migrate/*_recebiveis_nascem_no_ai9.rb`; `models/receivable_entry.rb` | Tabela larga (60 colunas), UUID como PK, ~7,7 mil registros | Migração com cabeçalho pt-BR longo e `comment:` nas colunas (convenção §4) | médio | — |
| DB-151 | build | idem | idem | FKs para user/project/carrier/wallet/kind/resource_source/company/tipo+subtipo; `nro_bordero` **string** (zeros à esquerda) | Corrige D-12 (zero FKs no legado). `resource_kind_id` migrado como proveniência (Q-B17) | médio | `projects`, `companies-carriers` |
| DB-152 | build | Convenção ai9 §4 sugere `decimal(14,2)` | idem | **18 colunas `decimal(15,2)`** — o legado tem teto R$ 9.999.999.999.999,99 | **Divergência consciente da convenção**: usar 15,2, não 14,2 (ver §3, D-B4). Estouro → 422, não truncamento silencioso | médio | — |
| DB-153 | build | — | idem | Prazos, floats, taxas e 7 CETs: armazenamento `decimal` no ai9, **resultado idêntico ao float do legado** | DEC-02 — D-13 fica subordinado; a divergência de precisão vai junto, registrada | **alto** — é o ponto onde "consertar" quebra a paridade | SR-2 |
| DB-154 | build | — | idem + ETL | `company_id` obrigatório no ai9; borderôs anteriores a 03/2022 recebem a empresa do projeto (ou "Empresa Padrão") **antes** da inserção | Relatório da carga lista quantos foram corrigidos | médio | OPS-197 (mesma rotina de empresa padrão) |
| DB-155 | build | — | idem | `description` visível; `observacoes` migrada sem tela | Q-B18: `observacoes` não é lida nem escrita por nenhuma tela | baixo | — |
| DB-156 | build | — | idem | Tipo e subtipo **opcionais** ("Não associar"); subtipo inexistente → 422 | — | baixo | `risk` |
| DB-157 | build | — | colunas `legacy_id`/`legacy_*` | Proveniência do sistema Django preservada | DEC-12 — o ETL não é portado, as colunas sim (única prova de proveniência 2016-2021) | baixo | — |
| DB-158 | build | — | `db/migrate/*_create_wallets.rb` | Catálogo global, ~8 registros; **índice único** em título | Corrige D-12 (unicidade só no AR, sujeita a corrida) | baixo | — |
| DB-159 | build | — | `*_create_receivable_kinds.rb` | 4 registros de `dtiporecebivel` | idem | baixo | — |
| DB-160 | build | — | `*_create_movement_kinds.rb` | 17 registros de `dtarifa`; `kind` com domínio fechado | Associação morta `has_many :receivables` **não** é portada | baixo | — |
| DB-161 | build | — | `*_create_receivable_taxes.rb` | ~15,7 mil registros; **índice em `receivable_entry_id`** | Corrige D-12 (tabela lida 4× por save sem índice). Tarifa órfã é **reportada**, não inserida (D-103) | médio | DB-150 |
| DB-162 | build | — | `*_create_charges.rb`; `models/charge.rb` | Totais denormalizados; `state` com **check constraint** | Restrição arquitetural do legado preservada: cobrança **nunca** referencia operação diretamente, só via `receipts` | baixo | — |
| DB-163 | build | — | `*_create_receipts.rb` | Operação polimórfica; **índice único** `(operation_id, project_id, operation_type)` | Corrige D-12 | médio | DB-162 |
| DB-164 | build | — | idem | `date` e `operation_title` como fotografia da operação; recibos de 02–04/08/2022 preenchidos na carga | Relatório informa quantos foram completados | baixo | — |
| DB-165 | build | — | `receipt_id` em `risk_operations` e `structured_operations` | Vínculo criado **em transação**, com FK nos dois lados | Corrige a referência circular por callbacks sem transação (recibo sem operação / operação sem recibo) | **alto** — determina quem aparece como candidato na cobrança | `risk`, `structured-operations` |
| DB-166 | build | — | migrations de índice | Índices em `(project_id, date)`, `wallet_id`, `carrier_id`, `receivable_taxes(receivable_entry_id)`, `charges(project_id,date)`, `receipts(charge_id)`, `receipts(remuneration_id)` | Corrige D-12; `schema.rb` versionado (o legado não tinha) | baixo | — |
| DB-167 | build | — | `scripts/etl/receivables/` | Mapeamento `fbordero`→`receivable_entries`, `fbortarifa`→`receivable_taxes`, `dcarteira`→`wallets`, `dtiporecebivel`→`receivable_kinds`, `dtarifa`→`movement_kinds` | Reconciliação de contagem origem×destino; carga em execução única | **alto** — o salto `integer`→`uuid` exige tabela de correspondência (D-103) | SR-7 |

### 2.4 `receivables` — operação (OPS-150 … OPS-159)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| OPS-150 | build | — | `scripts/etl/receivables/report.rb` | O ETL Django **não** é portado (DEC-12); o que se constrói é o **relatório** que identifica os registros marcados por ele (`user_id = 1`, `company_id = 1`) | Q-B19: reatribuir autor/empresa dos borderôs 2016-2021 ou manter | baixo | DB-167 |
| OPS-151 | build | Sidekiq + `find_each` | `jobs/receivables/bulk_recalculate_job.rb` | Recálculo em lotes, com progresso e falhas visíveis | Corrige o `ReceivableEntry.all` de uma vez e o logger silenciado; **não duplica** operação de risco (D-11) | **alto** — recálculo em massa que dispara sincronia de risco duas vezes recria o defeito | BE-183 |
| OPS-152 | **reuse** | A base ai9 **não tem** nenhum `establish_connection` alternativo (`backend/config/database.yml` único) | — | Nada a fazer: o boot do ai9 não depende de banco legado | DEC-12. O ETL roda como processo próprio, fora do ciclo de vida da app | baixo | — |
| OPS-153 | build | `backend/db/seeds.rb` + `db/seeds/` | `db/seeds/receivables_catalogs.rb` | Seed **executável e idempotente** (as flags `should_seed_*` do legado vinham `false`) | 10 carteiras nomeadas (ACC, ACE, Antecipação, Caução, Cheque, Comissária, Conta Garantida, Desconto, Domicílio, Fomento) | baixo | DB-158 |
| OPS-154 | build | `Rails.cache` | `config/receivables_help_inputs.yml` + `services/receivables/help_texts.rb` | Servido de cache, não `YAML.load_file` por render; campo sem chave não exibe indicador de ajuda | **Conteúdo faltando**: no legado os ~40 textos são placeholder ("Só um teste de informações do campo…") — Q-B20 | baixo | FE-165 |
| OPS-155 | **reuse** | Base ai9 sem `prawn`/`wicked_pdf`/`grover` (verificado no `Gemfile`) | — | Nenhuma geração de PDF | DEC-09 / D-84 — a gem estava declarada e a feature nunca existiu | baixo | — |
| OPS-156 | **reuse** | Base ai9 sem gerador de planilha; `api/v1/downloads.rb` serve binário mas não gera | — | Nenhum endpoint de exportação | DEC-09. O `exportingMonitor` do legado não corresponde a funcionalidade | baixo | — |
| OPS-157 | build | PostgreSQL fixo (DEC-05); `Arel`/`sanitize_sql_like` | `services/receivables/search_service.rb` | `ILIKE` direto — sem detecção de adaptador em runtime | Termo com `%`/`_` tratado como **literal** (o legado interpolava o fragmento SQL na string do `where`) | médio — é injeção de SQL no legado | BE-150 |
| OPS-158 | build | — | idem | Limite ausente **omite a cláusula** | Corrige `DateTime.dinosaurs`/`.mars` (intervalo de 4000 anos que pode estourar a faixa do banco) | baixo | — |
| OPS-159 | adapt | `Intl.NumberFormat` já usado em `components/mobile/MobileKPI.tsx` e `charts/RechartsBar.tsx` | `lib/format/money.ts` (**novo compartilhado**) + helper equivalente no backend | `R$ 100.000,00`; **nulo e zero distinguíveis** | Corrige D-117 (`format_money` renderizava nulo como `R$ 0,00` num sistema financeiro) e o `%1.Nf` half-up do C que divergia do `round` do Ruby em até um centavo | médio — arredondamento de exibição tem que coincidir com o de cálculo | SR-2 |

### 2.5 `renegotiations` — backend (BE-190 … BE-229)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| BE-190 | build | [GRAPE] + [KAM] + [ENT] | `api/v1/renegotiations.rb#search` | Escopo por projeto validado no servidor; busca cobre **`title` e `provider_name`** | Corrige o vazamento por `renegotiation_id` (família D-16/D-76/D-100) e a busca que só casava fornecedor apesar de "Nome" ser a 1ª coluna | **alto** — vazamento cross-tenant | SN-1 |
| BE-191 | build | [GRAPE] `params values:` | idem | Filtro por 4 estados, incluindo `empty` | Corrige D-49 (o `case` sem `when "empty"` abortava a action e a tela dava 500) | baixo | BE-209 |
| BE-192 | build | [GRAPE] | idem | Filtro por Financeiro/Operacional/Tributario/Trabalhista | — | baixo | — |
| BE-193 | build | [SVC] | idem | Ordenação acumulada por `title` e `provider_name`; chave desconhecida ignorada | Corrige o `nil + " "` → `NoMethodError` | baixo | — |
| BE-194 | build | [KAM] | idem | `l`/`o` aplicados de fato; padrão 20 | Corrige D-20 (`where!` descartava a relação nova) | médio | — |
| BE-195 | build | [SVC] | `api/v1/renegotiations.rb#general_values`; `services/renegotiations/aggregate_service.rb` | Recalcula **de verdade** e devolve os 7 valores + `unposted_value` + flag de "remover todas"; 404 para inexistente; recusa cross-project | Corrige D-48 (o hash era montado e **descartado**; a resposta era o JSON cru) | **alto** — alimenta os cards de resumo | SN-1 |
| BE-196 | build | [ENT] `Grape::Entity` | `api/entities/renegotiation.rb` | Representação com `installment_status` derivado; opções de serialização respeitadas | Corrige o `to_json` sobrescrito que quebrava a assinatura e levantava `ArgumentError` | baixo | BE-210 |
| BE-197 | **reuse** | `react-router-dom` + [DS] `Layout.tsx` | — | As 6 rotas REST mortas não existem (nenhum dos templates existe em disco) | `dropped` com evidência (DEC-09) | baixo | — |
| BE-198 | build | [GRAPE] + [SVC] | `services/renegotiations/create_service.rb` | Recalcula os agregados **na criação** | Corrige o registro que nascia com tudo zerado e `state = "Inconsistente"`; mensagem distingue criação de atualização | baixo | SN-1 |
| BE-199 | build | [SVC] | idem + `models/renegotiation.rb` | `provider_name`, `title`, `correct_value = total_debt`, `integration_key`, carimbo do projeto | Chave de integração passa a ser **única** (homônimos colidiam em silêncio). Valores zerados/negativos continuam aceitos (Q-B21) | médio | `companies-carriers` (fornecedores) |
| BE-200 | build | [GRAPE] + [SVC] | `services/renegotiations/update_service.rb` | Recalcula e persiste; recusa cross-project; **edição inválida não muta agregado** | Corrige o recálculo que rodava mesmo após falha de validação | médio | BE-195 |
| BE-201 | build | [GRAPE] | `api/v1/renegotiations.rb#destroy` | Só sem parcelas/pagamentos; anexos vão junto | Corrige D-24 (`errors.any? ? :ok : :ok` + template de retorno **vazio** → a tela mostrava sucesso e o registro voltava) | médio | SN-5 |
| BE-202 | build | [SVC] + transação | `services/renegotiations/batch_destroy_installments.rb` | Lote inteiro **numa transação**; ids de outra renegociação recusados; lote vazio não é sucesso | Corrige D-51 (remoção parcial reportada como falha total — o usuário reexecutava e apagava a mais) | **alto** — perda de dado | BE-203 |
| BE-203 | build | `update_all` (OPS-195) | `services/renegotiations/renumber_installments.rb` | Renumeração 1..N por vencimento após qualquer alteração | — | baixo | — |
| BE-204 | build | [SVC] | `aggregate_service.rb` | Somas de principal, juros e CM; `main_value` derivado | Aritmética do legado replicada (DEC-02) | médio | SN-1 |
| BE-205 | build | [SVC] | idem | `paid_value_with_interest_cm`, `late_payment_value`, `pending_main_value`, `paid_value` | **Assimetria preservada**: `pending_main_value` pode ficar negativo; `remaining_value` tem piso em zero (Q-B22) | médio | BE-204 |
| BE-206 | build | [SVC] | idem | `paid_percent` sem divisão por zero; > 100% aceito | DEC-02 — mora fora do numerador, dívida contratada fora do denominador | baixo | BE-205 |
| BE-207 | build | [SVC] + consulta agregada | idem | `remaining_value`, `paid/overdue/due_installments`; **vencidas calculadas na consulta** | Corrige D-54 (era fotografia do último `update_values!`, até 24 h desatualizada, dependente do cron). `due_installments` continua incluindo as vencidas (Q-B23) | médio | OPS-190 |
| BE-208 | build | [SVC] | idem | `installments_count`, `first/last_due_date`, `total_value_with_desagio`, `correct_value` | **`correct_value = total_debt` sempre** — `interest_rate_correction` e `grace_period` continuam sem uso (D-47, Q-B24). Deságio > original aceito | médio | — |
| BE-209 | build | [SVC] | `aggregate_service.rb#state` | 4 estados derivados | Corrige D-45 (a linha do estado "Inconsistente" era sobrescrita pela seguinte — o filtro da tela **nunca** retornava nada) | médio | BE-207 |
| BE-210 | build | [SVC] | idem | `unposted_value` e `installment_status` | — | baixo | BE-204 |
| BE-211 | build | consulta agregada | idem | Parcela do mês (inclui a já paga) e próxima parcela em aberto (vencidas nunca são "próxima") | Corrige N+2 consultas por linha da listagem — **sem alterar o número** | médio | BE-190 |
| BE-212 | build | [SVC] | `aggregate_service.rb#current_value` | VP da dívida pela taxa acordada; float e arredondamento final replicados | **`current_installment_value` é sobrescrito pelo VP** — replicado (D-46, Q-B25). É um número que o cliente lê | **alto** | DEC-02 |
| BE-213 | build | [GRAPE] + [KAM] | `api/v1/renegotiation_installments.rb#search` | Ordenadas por vencimento, com pagamentos; **paginação funciona**; 404 para renegociação inexistente | Corrige D-20 (`l`/`o` calculados e ignorados) | baixo | SN-3 |
| BE-214 | build | [GRAPE] `params do` | `api/v1/renegotiation_installments.rb#create` | Data ausente → 422 (não 500); repetições não numéricas → 422 | Corrige o `to_i` que virava 0 e respondia 200 "criada com sucesso" sem criar nada | médio | — |
| BE-215 | build | [SVC] | `services/renegotiations/create_installment.rb` | Uma parcela por data; falha **não** dispara recálculo nem renumeração | — | baixo | BE-203 |
| BE-216 | build | [SVC] + `date-fns`/`ActiveSupport` | `services/renegotiations/create_installments_batch.rb` | N parcelas, intervalo em Dias/Semanas/Meses, ajuste de fim de mês; intervalo 0 → 422; período desconhecido → 422 | Corrige as duplicatas dentro do próprio lote que falhavam em silêncio com resposta de sucesso | médio | BE-215 |
| BE-217 | build | [SVC] | idem | Derivações da parcela + identidade e cor do lote; parcela inválida **reportada** | Corrige D-52 e o `create` cujo retorno era ignorado | médio | OPS-196 |
| BE-218 | build | model + índice único | `models/renegotiation_installment.rb` | Principal `> 0`; **índice único** `(renegotiation_id, due_date)`; mês/ano acompanham a data | Corrige D-12 (unicidade só no AR, sujeita a corrida) | baixo | DB-191 |
| BE-219 | build | [SVC] | `services/renegotiations/recalculate_installment.rb` | Mora, total, pago, saldo, `is_paid` | **A mora entra dos dois lados da conta** — replicado (DEC-02). Consequência: pagar só a mora pode quitar a parcela (Q-B26) | **alto** | — |
| BE-220 | build | [SVC] + transação | idem | Renumera pagamentos, recalcula parcela, propaga para a renegociação; falha é **revertida e reportada** | Corrige o `save` sem bang que descartava o recálculo em silêncio | **alto** — divergência parcela×renegociação | BE-219 |
| BE-221 | build | [GRAPE] + [SVC] | `api/v1/renegotiation_installments.rb#update/#destroy` | Edição recalcula e renumera; exclusão barrada por pagamento; aumento reabre parcela quitada | — | médio | BE-220 |
| BE-222 | build | [GRAPE] + [KAM] | `api/v1/renegotiation_payments.rb#search` | Ordem determinística e paginação | Corrige D-20 (sem `ORDER BY`, ordem dependia do banco). Edição **não** muda a parcela pela URL | médio | — |
| BE-223 | build | [GRAPE] + [SVC] | `services/renegotiations/create_payment.rb` | `days_late`, `total_paid_value`; **teto no pendente da parcela**; mora negativa recusada; renegociação divergente recusada | Corrige D-52 (as três). **Sem imputação automática** — o pagamento vai só para a parcela escolhida | **alto** — muda o que hoje é aceito; pode barrar lançamento que o operador fazia | BE-219 |
| BE-224 | build | [SVC] | `api/v1/renegotiation_payments.rb#update/#destroy` | Recalcula **uma vez**; exclusão reabre a parcela; recusa cross-project | Corrige o `update` + `save` redundante que disparava a cascata em duplicidade | médio | BE-220 |
| BE-225 | build | [GRAPE] + [KAM] + [ENT] | `api/v1/renegotiation_attachments.rb#search` | Lista com título, formato e autor; filtro e limite aplicados | Corrige a rota que **nunca funcionou** (`la:` vs `ra` → `NameError`) e D-20 | baixo | SN-5 |
| BE-226 | **adapt** | [AS] + `models/medium.rb` + `services/medium_service.rb` como referência | `models/renegotiation_attachment.rb` (`has_one_attached :file`); `services/renegotiations/attachment_service.rb` | **Limites no servidor**: 4 arquivos, 5 MB, tipo validado **pelo conteúdo** (Marcel, via ActiveStorage) | Corrige D-50 e D-82. **`Medium` não serve como está**: `medium.rb:12` restringe `media_type` a `image`/`video` e anexo de renegociação é majoritariamente PDF (ver §4/§6) | **alto** — segurança | [AS] |
| BE-227 | **adapt** | `api/v1/downloads.rb:17-40` (entrega de binário atrás de checagem de permissão) | `api/v1/renegotiation_attachments.rb#download` | Download **autorizado por projeto**, nome original, `Content-Disposition: attachment` sempre; arquivo ausente → 404 legível | Corrige D-82 nas três frentes: sem verificação de permissão, `disposition: inline` com content-type do uploader (XSS armazenado na mesma origem), e arquivo alcançável por caminho direto. **Não reusar `AssetsProxyController`** (serve `public/uploads/**` inline e sem auth) | **alto** — segurança | BE-226 |
| BE-228 | **reuse** | — | — | A action de renomear anexo **não é portada** | DEC-11: `update_attributes` funcionaria em produção, mas a action chama `renegotiation_params`, método inexistente nesse controller → `NameError` em qualquer execução. Q-B27: renomear é funcionalidade pretendida e nunca entregue | baixo | — |
| BE-229 | build | [GRAPE] + [AUTHZ] | `api/v1/renegotiation_attachments.rb#destroy` | Só o autor exclui — **checado no servidor**; contador decrementado; registro sem arquivo é removido normalmente | Corrige D-82 (a regra de dono era só visual) | médio | DB-195 |

### 2.6 `renegotiations` — frontend (FE-190 … FE-229)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| FE-190 | build | [DS] `ui/Table.tsx`, `PageHeader.tsx` | `app/pages/renegotiations/RenegotiationsPage.tsx` | 13 colunas de resumo; "Data próxima" vazia mostra `-` | — | baixo | BE-190 |
| FE-191 | adapt | `components/ui/EmptyState.tsx` (FE-152) + [RQ] | idem | 4 estados do container | Corrige o `failure` vazio do proxy (a tela ficava no último estado, sem mensagem) | baixo | FE-152 |
| FE-192 | **reuse** | `hooks/useDebouncedValue.ts` (FE-155) | idem | Debounce 300 ms; busca casa **nome e fornecedor** | — | baixo | FE-155, BE-190 |
| FE-193 | **reuse** | [DS] `ui/SearchableSelect.tsx` | idem | Filtros de estado e tipo, ocultos até "Filtros" | "Sem parcela cadastrada" e "Inconsistente" passam a **funcionar** (D-49, D-45) | baixo | BE-191 |
| FE-194 | **reuse** | `components/ui/SortableTableHeader.tsx` (FE-159) | idem | Ciclo asc→desc→neutro, acumulado | — | baixo | FE-159 |
| FE-195 | **reuse** | `components/ui/Pagination.tsx` (FE-160) | idem | Padrão 50; botões desabilitados nos extremos | Corrige D-20 | baixo | FE-160 |
| FE-196 | build | `components/ui/RowActionsMenu.tsx` (FE-163) | `components/renegotiations/RenegotiationRow.tsx` | Linha abre o detalhe; remover só sem parcelas | Q-B28: o legado usa `provider_name` como título da rota enquanto a lista mostra `title` | baixo | FE-163 |
| FE-197 | build | [DS] `ui/Button.tsx` + `hooks/usePermission.ts` (FE-164) | `RenegotiationsPage.tsx` | Guarda de fornecedor; botão some para readonly | — | baixo | FE-164 |
| FE-198 | **reuse** | [DS] `ui/dialog.tsx` + [TOAST] | idem | Confirmação; **erro real do servidor exibido** | Corrige D-24 (o usuário via sucesso e o registro voltava) | baixo | BE-201 |
| FE-199 | build | [DS] `ui/{Input,Label,SearchableSelect,textarea}.tsx` | `app/pages/renegotiations/RenegotiationFormPage.tsx` | 13 campos; título "Editar {fornecedor}" | `grace_period` e `interest_rate_correction` continuam **fora da tela** (D-47, Q-B24) | médio | BE-198 |
| FE-200 | build | `components/ui/EmptyState.tsx` (FE-152) | idem | Sem fornecedor / sem empresa → explicação + atalho | — | baixo | FE-152 |
| FE-201 | **reuse** | `components/ui/{MoneyInput,DecimalInput}.tsx` (FE-168/169) | idem | Máscaras de dinheiro e percentual | **Truncamento da 3ª casa preservado** (`1,239` → `1,23`) — é o primeiro passo da cadeia de arredondamento que produz os totais atuais (DEC-02). Campo vazio vira `0,00` | médio | FE-168 |
| FE-202 | **reuse** | `components/ui/DatePicker.tsx` (FE-177) | idem | `dd/mm/aaaa`, limpável | — | baixo | FE-177 |
| FE-203 | **reuse** | [TOAST] + `lib/api/client.ts` | idem | Erros com campo em pt-BR; mensagem de **criação** distinta | Corrige "foi atualizada com sucesso" na criação | baixo | — |
| FE-204 | adapt | [DS] `ui/tabs.tsx` + `react-router-dom` | `app/pages/renegotiations/RenegotiationDetailPage.tsx` | Abas GERAL/PREVISÕES; **deep-link e histórico reais** | Corrige D-92 (estado de navegação só em memória JS; o Voltar saía do console) | médio | BE-195 |
| FE-205 | build | [DS] `ui/Card.tsx` | `components/renegotiations/RegistrationCard.tsx` | 13 campos somente leitura; vazio mostra `-` | — | baixo | — |
| FE-206 | adapt | [CHART] `components/kpi/KpiCard.tsx` | `components/renegotiations/SummaryCards.tsx` | 4 cards de resumo financeiro; Status `-` antes da resposta | — | baixo | BE-195 |
| FE-207 | build | **[CABLE]** `hooks/useCable.ts` + novo `channels/renegotiation_channel.rb` | idem + `hooks/useRenegotiationChannel.ts` | Cards atualizam **por Action Cable** após qualquer alteração de parcela/pagamento — **polling é proibido** (Princípio 10) | Campo ausente na resposta não interrompe os demais (o legado lançava `TypeError` e parava tudo); falha é sinalizada | médio | [CABLE], BE-195 |
| FE-208 | adapt | [AS] variantes (`Medium#small_url:60-72`) + `react-photo-album@3` (já no `package.json`) | `components/renegotiations/AttachmentGallery.tsx` | Miniaturas **de variante**, não do arquivo original; imagem indisponível vira marcador | Corrige a leitura de dimensões por render que derrubava o detalhe com 500 e a miniatura que resolvia para o original | médio | OPS-193 |
| FE-209 | build | [DS] `ui/Card.tsx` | `components/renegotiations/FilesSection.tsx` | Contagem no título; vazio explicado; **limite comunicado de verdade** | Corrige D-50 (o indicador de bloqueio era escrito no HTML e nunca lido pelo JS) | baixo | BE-225 |
| FE-210 | adapt | `components/ThumbnailPicker.tsx` (seleção de arquivo já existente) | `components/ui/FileDropzone.tsx` (**novo compartilhado**) | Arrastar e soltar + seletor múltiplo, com os limites aplicados | Corrige D-50 (a checagem lia `.lesson_attachment_content_wrapper`, seletor **de outro produto**, comparando com `NaN`) | médio | BE-226 |
| FE-211 | build | [DS] `ui/dialog.tsx` | `FilesSection.tsx` | Ação só para o autor — **e o servidor recusa** | Corrige D-82 | baixo | BE-229 |
| FE-212 | build | `lib/api/downloads.ts` (`getRaw`/blob já existente) | idem | Abre pelo endereço **autorizado** de download; tipo não visualizável vem como download | Corrige D-82 | médio | BE-227 |
| FE-213 | build | [DS] `ui/Table.tsx` + `hooks/usePermission.ts` | `components/renegotiations/InstallmentsTab.tsx` | 12 colunas; barra de ações some para readonly | — | baixo | FE-164 |
| FE-214 | build | [DS] `ui/Table.tsx` + [RQ] | idem | Valores em reais, datas `dd/mm/aaaa`; estados de carga/vazio/**erro** | A lista de parcelas do legado não tinha tratamento de erro | baixo | BE-213 |
| FE-215 | adapt | [DS] `ui/accordion.tsx` | `components/renegotiations/InstallmentRow.tsx` | Pagamentos aninhados expandem/recolhem; clique ignorado no modo seleção | — | baixo | — |
| FE-216 | build | `components/ui/RowActionsMenu.tsx` (FE-163) | idem | Gerar pagamento / editar / remover (só sem pagamento) | — | baixo | FE-163 |
| FE-217 | build | [DS] `ui/switch.tsx`, `ui/Button.tsx` | `InstallmentsTab.tsx` | Modo seleção; "Selecionar todos" pega só as sem pagamento; rótulo "REMOVER N PARCELAS" | — | baixo | — |
| FE-218 | build | [DS] `ui/dialog.tsx` | idem | Nada selecionado → aviso; **confirmação não expira** | Corrige a confirmação de operação irreversível que se autodescartava em 6 segundos | baixo | BE-202 |
| FE-219 | build | [DS] `ui/Tooltip.tsx` | `InstallmentRow.tsx` | Parcela com pagamento não recebe caixa de seleção | — | baixo | — |
| FE-220 | adapt | [DS] `SideDrawer.tsx` | `components/renegotiations/InstallmentDrawer.tsx` | 3 modos (única / lote / edição); repetições com mínimo 1 | — | médio | — |
| FE-221 | build | [RQ] + endpoint de cálculo | idem + `hooks/useInstallmentPreview.ts` | Totais derivados vêm **do servidor** | Corrige D-09 na renegociação: a regra financeira deixa de existir em dois lugares | médio | BE-217 |
| FE-222 | build | [DS] `ui/Button.tsx` | idem | Salvar só com principal > 0 — **e o servidor responde 422** | Corrige D-52 (o servidor tinha a validação, mas o erro era engolido e a resposta era 200) | baixo | BE-218 |
| FE-223 | build | [RQ] mutation + [TOAST] | idem | Fecha em sucesso restaurando o endereço; falha mantém aberto com os valores | — | baixo | — |
| FE-224 | adapt | [DS] `SideDrawer.tsx` | `components/renegotiations/PaymentDrawer.tsx` | Seletor de previsão com nº/vencimento/pendente; **data do pagamento editável** | Corrige a data somente leitura e sempre "hoje", que contradizia a existência do cálculo de dias de atraso (pagamento retroativo passa a ser possível) | médio — muda o que se pode lançar | BE-223 |
| FE-225 | build | [RQ] | idem | Pago Total calculado; salvar bloqueado com zero **e** com valor acima do pendente | Corrige D-52 (não havia checagem em nenhuma camada; o pendente era só rótulo do seletor) | médio | BE-223 |
| FE-226 | build | [RQ] mutation + [CABLE] | idem | Painel **fecha** após salvar; lista e cards atualizados | Corrige o `TypeError` causado pela aba de pagamentos comentada (D-53) que deixava o painel aberto; e a mensagem que dizia "A previsão foi criada" | baixo | FE-207 |
| FE-227 | build | [DS] `ui/dialog.tsx` + `react-router-dom` | `InstallmentRow.tsx` | Editar/excluir pagamento pela sublinha; endereço reflete o pagamento aberto | Corrige a URL que ficava literalmente com `{pid}` e o título de confirmação "Excluir previsão" | baixo | — |
| FE-228 | **reuse** | `hooks/usePermission.ts` (FE-164) + [AUTHZ] | todas as telas da área | Escrita suprimida na tela **e recusada no servidor** | Corrige D-17 | médio | FE-164 |
| FE-229 | **reuse** | — | — | A aba PAGAMENTOS e o "excluir todas as parcelas" **não** são portados (estão comentados no legado) | DEC-09. Q-B29 (D-53): a aba comentada é a causa raiz de FE-226 — confirmar se entra no escopo | baixo | — |

### 2.7 `renegotiations` — dados (DB-190 … DB-199)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| DB-190 | build | padrão UUID do `schema.rb` | `db/migrate/*_create_renegotiations.rb`; `models/renegotiation.rb` | Cadastro + ~20 agregados; FKs; `kind` e `state` com **domínio fechado** | Corrige D-103 (nenhuma migration de renegociação tem índice ou FK) | médio | `companies-carriers` |
| DB-191 | build | — | `*_create_renegotiation_installments.rb` | **Índice único** `(renegotiation_id, due_date)`; índices por renegociação, vencimento e `is_paid` | Corrige D-103/D-12. `saldo` negativo e `pending_value` positivo — **diferença de sinal documentada em `comment:`** | médio | DB-190 |
| DB-192 | build | — | `*_create_renegotiation_payments.rb` | Índices por parcela e por renegociação; **coerência renegociação×parcela garantida** | Corrige D-52 no banco. Q-B30: não há forma de pagamento nem conciliação bancária | médio | DB-191 |
| DB-193 | build | [AS] `active_storage_attachments`/`_blobs` (já no `schema.rb:40,50`) | `*_create_renegotiation_attachments.rb` | Metadados preservados; **tipo revalidado pelo conteúdo real** na carga; binários vão para o armazenamento privado | Corrige D-82 | **alto** — migração de binários de disco | BE-226 |
| DB-194 | build | — | ETL | Mapeamento `total_value`→`installments_main_value`, `installments.value`→`main_value`, `payments.value`→`installment_paid_value_with_interest_cm` | Semântica nova (o valor da parcela é **só o principal**). Q-B31: existem consumidores externos usando os nomes antigos? | médio | SN-6 |
| DB-195 | build | `counter_culture`-style manual | `models/renegotiation.rb#attachments_count` | Contador preenchido na carga, `null: false, default: 0`, sempre coerente | Corrige o nulo que fazia `nil > 0` → `NoMethodError` | baixo | DB-193 |
| DB-196 | build | Convenção ai9 §4 (`decimal(14,2)`) | migrations do domínio | `decimal(15,2)` para dinheiro, float para percentuais/taxas | **DEC-02**: truncamento em 2 casas na entrada → float no cálculo → arredondamento na gravação, replicado. Divergência consciente da convenção (§3, D-B4) | **alto** | SN-1 |
| DB-197 | build | — | coluna `has_safegold_management` | Carimbo copiado na criação, **nunca ressincronizado** | D-30, Q-B32: a propagação em massa do projeto alcança só `companies`; nenhum código de renegociação lê a coluna | baixo | `projects` |
| DB-198 | build | — | migrations de índice | FKs em todas as referências + os índices das consultas quentes | Corrige D-103; listagem deixa de ser quadrática em consultas | baixo | — |
| DB-199 | build | — | `scripts/etl/renegotiations/audit.rb` | **Auditoria antes da carga**: pagamentos com renegociação divergente, vencimentos duplicados, contadores errados, estados incoerentes | Corrige D-103. Bloqueios de exclusão preservados (renegociação↔parcela↔pagamento, projeto, fornecedor) | **alto** — é o gate da carga | SN-6 |

### 2.8 `renegotiations` — operação (OPS-190 … OPS-197)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| OPS-190 | build | consulta agregada (sem cron) | `services/renegotiations/aggregate_service.rb` | O cron diário **deixa de existir**: vencidas viram cálculo em consulta | Corrige D-54 (até 24 h desatualizado), a renegociação liquidada que nunca mais era reprocessada (estorno não a trazia de volta) e D-79 (o `save` sem bang pulava registro em silêncio) | médio — muda quando o número aparece, não qual é | BE-207 |
| OPS-191 | **adapt** | [CRON] `sidekiq-cron` (`Gemfile:38`) + `config/initializers/sidekiq.rb` | idem | Uma definição versionada, com retry, alerta e **trava de concorrência** | Corrige o crontab por host sem trava (dois hosts = processamento em duplicidade) e os 3 arquivos de agendamento do legado | baixo | — |
| OPS-192 | **adapt** | [AS] `config/storage.yml` (Disk) | serviço privado + `api/v1/renegotiation_attachments.rb#download` | Arquivo **não** fica em `public/`; só é servido pelo caminho autorizado | Corrige D-82. **Ver §6/flag 2**: `AssetsProxyController` faz exatamente o que não se pode fazer aqui; volume persistente é requisito de deploy | **alto** | BE-227 |
| OPS-193 | **adapt** | [AS] `blob.metadata` + `image_processing` (`Gemfile:10`); `Medium#small_url` | `models/renegotiation_attachment.rb` | Dimensões vêm de metadados persistidos; **nenhum processo externo por render** | Corrige as 2 chamadas de processo externo por imagem a cada renderização; falha marca só aquela imagem | baixo | [AS] |
| OPS-194 | build | Marcel (transitivo do ActiveStorage) | `services/renegotiations/attachment_service.rb` | Tipo verificado **pelo conteúdo**, allowlist de tipos | Corrige D-82 (`do_not_validate_attachment_file_type` + spoof detector monkey-patchado para `false`) | médio | BE-226 |
| OPS-195 | build | `update_all` | `renumber_installments.rb`, `renumber_payments.rb` | Renumeração em uma operação, **sem callbacks** (evita recursão de recálculo); só o ordinal muda | — | baixo | BE-203 |
| OPS-196 | build | — | `services/renegotiations/batch_color.rb` | Cor distinta por lote, **com terminação garantida** | Corrige o laço de rejeição potencialmente infinito quando o espaço de cores esgota | baixo | BE-217 |
| OPS-197 | build | `find_each` + Sidekiq | `scripts/etl/renegotiations/fixups.rb` | Empresa padrão por projeto sem empresa; recálculo geral **em lotes**; renumeração de pagamentos | Corrige as rotinas que re-salvavam tudo sem particionamento, carregando a base em memória | médio | DB-199 |

### 2.9 `contracts` — backend (BE-330 … BE-349)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| BE-330 | **adapt** | `api/v1/base.rb:45-48` (`namespace :public` com `Public::Media` e `Public::Chat`) | `api/v1/public/contracts.rb` | Leitura sem sessão pelo namespace público **que já existe** | Corrige D-69: destino de retorno só por **allowlist interna**, nunca interpolado em código | médio — open redirect + XSS refletido no legado | [GRAPE] |
| BE-331 | build | [SVC] | `services/contracts/resolver.rb` | Vigente = **maior `version`**, não maior `id`; tipo desconhecido → 404 | Corrige o `.last` que ordenava por `id` (versão re-salva servia a versão errada) e o `nil.kind` → 500 | médio | DB-330 |
| BE-332 | build | [SVC] | `services/contracts/pending_service.rb` | Sinalizador de pendência para o usuário da sessão; anônimo lê em modo leitura | Corrige D-64 na raiz técnica: `has_many :contracts, through: :contract_deals, source: :contract_deal` — `source` **inexistente**, então qualquer logado que abrisse `/contract/:type` recebia 500 | médio | **Q-B1** |
| BE-333 | build | [GRAPE] + [AUTHZ] | `api/v1/contracts.rb#accept` | Aceite **sempre** do usuário da sessão; sem sessão → 401; idempotente; só a versão vigente | Corrige D-68 (mass assignment de `user_id` e `id` — o 1º `create` podia gravar aceite em nome de outro) e o template de resposta de **0 bytes** | **alto** — juridicamente é o registro que prova o consentimento | **Q-B1** |
| BE-334 | build | [GRAPE] + [KAM] | `api/v1/contracts.rb#index` | Uma linha por tipo, com a versão mais recente; paginação **depois** do agrupamento | Corrige D-20 nesta capability (paginar antes do filtro fazia contrato sumir da lista) e o filtro por lista fixa (`@availabe_kinds` — typo do legado) que tornava tipo inesperado invisível e inéditável | baixo | DB-330 |
| BE-335 | build | [AUTHZ] `Permission`/`UserPermission`; `require_og!` (`controller_helpers.rb:37`) | `api/v1/contracts.rb#create` | Publicação **exige papel administrativo**; versões anteriores imutáveis; autor é o da sessão | Corrige a ausência **total** de autorização (qualquer logado publicava um novo Termos de Uso) e o mass assignment de `id`/`version` | **alto** — **a matriz aprovada dá só `R` a todos os papéis (linha 197). Q-B3** | [AUTHZ] |
| BE-336 | build | sequência/`advisory lock` do PostgreSQL | `models/contract.rb` | Numeração **só na criação**, sucessor da maior `version`; concorrentes recebem números distintos garantidos pelo banco | Corrige o `version_guess` que rodava em **todo `save`** (re-salvar incrementava a versão) e o `.last` por `id` | médio | DB-330 |
| BE-337 | build | índice único | `db/migrate/*_create_contracts.rb` | **Índice único** `(kind, version)`; `kind` e `version` obrigatórios | Corrige a unicidade só de aplicação e a ausência de `presence` em `kind` (contrato com `kind` nulo nunca aparecia na busca) | baixo | DB-330 |
| BE-338 | build | [SVC] | `services/contracts/prefill_service.rb` | Pré-preenche com título, conteúdo e tipo da versão anterior; **primeiro contrato abre vazio** | Corrige `where(kind:).last.version + 1` sem guarda (`nil.version`) | baixo | [RICH] |
| BE-339 | build | enum string (convenção §4) | `models/contract.rb` | Catálogo fechado: Termos de Uso, Politicas de Privacidade; tipo não editável após criação | Q-B4: tipos configuráveis? (liga com OPS-332 e o `user.html` órfão) | baixo | — |
| BE-340 | **adapt** | `api/auth/v1/registration.rb` (fluxo de cadastro existente) | idem + `services/contracts/accept_service.rb` | Consentimento **explícito lido pelo servidor**; sem contrato publicado, cadastro conclui e a pendência nasce depois | Corrige D-64: hoje o `after_create :create_contracts` grava os dois aceites **automaticamente**, e os checkboxes não são lidos por nenhum controller. **Atenção: DEC-18.7 desligou o cadastro público** — o consentimento precisa entrar no fluxo de **convite** | **alto — jurídico. Q-B1** | **Q-B1**, DEC-18.7 |
| BE-341 | build | [SVC] + consulta agregada | `services/contracts/pending_service.rb` | Pendência calculada a partir do **catálogo de tipos**, não do que o usuário já aceitou | Corrige D-64 e o N+1. Corrige a consequência não óbvia: quem nunca aceitou um tipo (contrato criado depois da conta) **nunca ficava pendente** dele | médio | BE-332 |
| BE-342 | build | [SVC] | idem | Tolerância de 30 dias corridos da publicação | Q-B5: a regra é a única política de prazo do módulo e hoje está **inerte** (o bloqueio que a consumia está comentado) | baixo | **Q-B2** |
| BE-343 | build | [GRAPE] `before` + front `ProtectedRoute.tsx` | `api/v1/controller_helpers.rb` (novo gate) + `components/ProtectedRoute.tsx` | Redireciona para a página de aceite; **sem laço**; chamadas de API respondem a pendência **explicitamente** em vez de redirecionar | Corrige D-64: hoje o bloqueio está **inteiramente comentado** — não existe bloqueio algum | **alto — muda o acesso de todo mundo. Q-B2** | **Q-B2** |
| BE-344 | build | consulta agregada + `Rails.cache` | `services/contracts/metrics.rb` | Percentual correto, sem divisão por zero, **sem 2 COUNTs por widget** | Corrige a divisão inteira em Ruby que dava sempre 0 ou 100. Q-B33: a métrica está **comentada em todas as views** — foi desligada por performance (volta corrigida) ou por estar errada (sai do escopo)? | baixo | — |
| BE-345 | **adapt** | [RICH] `has_rich_text` (`app/models/user.rb:18`), tabela `action_text_rich_texts` (`schema.rb:30`), `action_text/engine` (`config/application.rb:12`) | `models/contract.rb` (`has_rich_text :description`) + sanitização por allowlist | **Mesma fidelidade** na página pública e no console | Corrige a divergência mais grave: a página pública usava `CGI.unescape(...to_plain_text).html_safe` — **a tela que o usuário juridicamente lê era a menos fiel das duas**. `decoded_description` (`URI.unescape`, removido no Ruby 3.0) não é portado | médio | [RICH] |
| BE-346 | **reuse** | — | — | `set_info` **não** é portado | D-62: referencia a variável local inexistente `cont` e levantaria `NameError`; sem consumidor. `dropped` com evidência | baixo | — |
| BE-347 | build | [SVC] `ApiResponseHandler` | `services/contracts/accept_service.rb` | Falha de gravação **propagada e registrada** | Corrige `deal_for(user)` que não checava o retorno do `save` | baixo | BE-333 |
| BE-348 | **reuse** | Grape só expõe rota declarada (`api/v1/base.rb`) — não há `resources` implícito | — | Nenhuma rota sem handler; nenhuma rota declarada duas vezes | D-62: no legado `resources :contracts` gerava 5 actions inexistentes (500 por `ActionNotFound`) e era declarado **duas vezes** com paths diferentes. A base ai9 torna isso estruturalmente impossível | baixo | — |
| BE-349 | build | [GRAPE] | `api/v1/public/contracts.rb#index` | Requisição sem tipo → lista os tipos disponíveis ou 404 | Corrige uma rota pública que **sempre** falhava com 500 | baixo | BE-331 |

### 2.10 `contracts` — frontend e dados (FE-330 … OPS-334)

| ID | Estratégia | Equivalente ai9 (arquivo) | Alvo ai9 | O que muda | Melhoria proposta | Risco | Depende de |
| -- | ---------- | ------------------------- | -------- | ---------- | ----------------- | ----- | ---------- |
| FE-330 | **adapt** | [DS] `components/layouts/PublicSplitLayout.tsx`; `components/VisitorRoute.tsx` | `app/pages/public/ContractPage.tsx` | Página própria fora do console, **fora do `ProtectedRoute`** | **Número da versão passa a aparecer** (o legado mostrava só "Atualizado em"); contrato inexistente vira "não encontrado", não 500 | baixo | BE-330 |
| FE-331 | **adapt** | [RICH] `components/RichTextInput.tsx` (modo `displayHtml`) | `components/contracts/ContractBody.tsx` | Conteúdo rico com a formatação original, sanitizado | Corrige a perda de títulos/listas/negrito na tela que tem valor jurídico | médio | BE-345 |
| FE-332 | build | [DS] `PageHeader.tsx`, `ui/Button.tsx` | `ContractPage.tsx` (barra) | Ação de aceitar aparece **quando há pendência** | Corrige D-64: o botão "ACEITAR" da barra está **totalmente comentado** e o handler JS ficou órfão sobre um seletor que nunca casa | médio | **Q-B1/Q-B2** |
| FE-333 | build | [DS] `ui/Progress.tsx`; `react-intersection-observer` (já no `package.json`) | idem (rodapé) | Aceite no rodapé com indicação de progresso de leitura | Corrige D-64: o bloco do rodapé também está comentado — **hoje não existe nenhuma forma de aceitar um contrato pela interface** | médio | **Q-B1/Q-B2** |
| FE-334 | build | `react-router-dom` + allowlist interna | idem | Confirmação de sucesso; destino hostil recusado | Corrige D-69 (XSS refletido **e** open redirect no mesmo parâmetro) | **alto** — segurança | BE-330 |
| FE-335 | **adapt** | `hooks/useNavItems.ts` (fonte única estática, com ponto de extensão documentado) | idem | Links de Termos de Uso e Política com **URL corretamente codificada** | Corrige a concatenação de `ENV['alias']` com o tipo em português cru, sem escape | baixo | OPS-331 |
| FE-336 | **adapt** | `app/pages/ProfilePage.tsx` | idem | Caixa **desmarcada** por padrão; histórico de aceites visível | Corrige D-64: no legado a caixa só aparece se o usuário não tem registro de ToU, já vem **pré-marcada**, e `contract[agreed_by_user]` não é lido por nenhum controller | médio | **Q-B1** |
| FE-337 | **adapt** | `app/pages/LoginPage.tsx` + fluxo de `Registration` | fluxo de **convite** (DEC-18.7) | Caixa desmarcada, envio bloqueado, **gate validado no servidor** | Corrige D-64. **Conflito de escopo: DEC-18.7 desligou o cadastro público** — este requisito precisa ser reancorado no convite (Q-B34) | médio | DEC-18.7 |
| FE-338 | build | [DS] `ui/Table.tsx`, `ui/Input.tsx`; `hooks/useNavItems.ts` | `app/pages/admin/ContractsPage.tsx` | **Passa a existir item de menu** (visível só a quem tem permissão), **campo de busca de verdade** e estado de erro | Corrige a tela órfã do legado: sem menu, com JS lendo `lastQuery` de um campo que não existe no HTML | baixo | BE-334 |
| FE-339 | build | [DS] `ui/Card.tsx`, `ui/Badge.tsx` | `components/contracts/ContractCard.tsx` | Ações conforme o papel — **e recusadas pelo servidor** | Corrige a ausência de gate (qualquer um que chegasse à URL publicava nova versão) e o item "Excluir" comentado que anunciava ação inexistente | médio | **Q-B3** |
| FE-340 | build | [DS] `ui/Card.tsx` | `app/pages/admin/ContractDetailPage.tsx` | Histórico completo, da mais recente à mais antiga | Corrige `nil.kind` → 500 e a ausência de estados de carga/vazio/erro | baixo | BE-334 |
| FE-341 | **reuse** | [DS] `ui/accordion.tsx` (`type="multiple"`) | idem | Várias versões abertas ao mesmo tempo, para comparação | — | baixo | FE-340 |
| FE-342 | **adapt** | [RICH] `components/RichTextEditor.tsx` (Slate, com H1/H2/lista/negrito/link) | `app/pages/admin/ContractVersionFormPage.tsx` | **Botão "Publicar" explícito**, com confirmação informando o número da nova versão e que **todos voltam a ter aceite pendente**; comparação com a versão anterior; aviso de alterações não publicadas | Corrige o pior comportamento da capability: no legado **não existe botão salvar** — qualquer `keyup` registra a ação na barra global e publicar é efeito colateral de digitar | médio | BE-338 |
| DB-330 | build | `action_text_rich_texts` (`schema.rb:30`) já existe | `db/migrate/*_create_contracts.rb`; `models/contract.rb` | Tipo, versão, título, autor (FK), conteúdo rico; **índice único `(kind, version)`**; **append-only** | Corrige o modelo sem índices e sem FKs. `version` é **congelado** no valor do legado; dry-run reporta autores órfãos | médio | [RICH] |
| DB-331 | build | — | `*_create_contract_deals.rb`; `models/contract_deal.rb` | Usuário, versão, data/hora, **IP, user-agent e impressão (hash) do texto aceito**; índice único `(user_id, contract_id)`; FKs | Corrige D-65 — **é o principal gap de compliance do bloco**. Corrige também a associação quebrada `User#contracts`. **É requisito novo, não paridade: decisão jurídica (Q-B2)** | **alto — jurídico** | **Q-B2** |
| OPS-330 | build | `db/seeds.rb` + `db/seeds/` | `db/seeds/contracts.rb` | Publica a **versão 1** de cada tipo a partir dos documentos de origem; idempotente | Corrige D-64 no dado: o seed do legado **re-salva todos os usuários e fabrica aceite retroativo para toda a base**. No ai9 **nenhum** aceite é gerado pela carga | **alto — jurídico** | **Q-B1** |
| OPS-331 | **adapt** | Padrão `ENV.fetch('API_HOST')` já usado em `app/models/medium.rb:27,39` | `config/initializers/public_host.rb` | Host público validado **na inicialização** | Corrige a dependência silenciosa de `ENV['alias']`, não documentada em lugar nenhum: sem ela, **todos** os links de ToU e Privacidade quebram | baixo | — |
| OPS-332 | build | — | `db/seeds/contracts.rb` | Documento de origem sem tipo declarado é **ignorado e registrado** | Q-B4: `db/seed_assets/contracts/user.html` existe desde o legado, nenhum seed o carrega e seu tipo não consta do catálogo — possível "contrato de adesão" planejado e nunca ativado | baixo | BE-339 |
| OPS-333 | build | — | `services/contracts/proof_export.rb` | Exportação de prova: usuário, versão, **texto integral aceito**, data/hora e origem | Corrige D-65. **Requisito novo (Q-B2)** | **alto — jurídico** | DB-331 |
| OPS-334 | build | — | agregado de SC-2 | Fluxo de aceite **ativo e completo**: bloqueio + ação na interface + pendência | Corrige D-64 no agregado. **Hoje, somando os três pontos, o produto só tem páginas públicas de leitura e um aceite implícito no cadastro** | **alto — jurídico. Q-B1/Q-B2** | **Q-B1, Q-B2** |

---

## 3. Decisões de comportamento

Ambiguidades que **eu** resolvi, com a razão. Todas são reversíveis; nenhuma delas
inventa feature.

| ID | Ambiguidade do legado | Decisão | Razão |
| -- | --------------------- | ------- | ----- |
| **D-B1** | O cálculo do borderô vive em 2 lugares (26 fórmulas em Ruby + reimplementação parcial em JS), com divergências conhecidas (D-09) | A fórmula vive **só no backend**, num `ReceivableCalculator`. A prévia da tela (FE-171) chama um endpoint `#preview` que roda o **mesmo** serviço da gravação | É a única forma de garantir o cenário "prévia e gravação sempre coincidem". Também é o que torna o DEC-02 auditável: um lugar só onde replicar o float |
| **D-B2** | Tipo de armazenamento das ~30 colunas de taxa/CET | Coluna `decimal` no ai9; **sequência de cálculo em float**, com os mesmos casts e pontos de arredondamento | DEC-02 explicitamente permite: *"replicar o resultado não obriga a replicar o tipo de armazenamento"*. Ganha-se a garantia do banco sem perder a paridade |
| **D-B3** | Como provar que o float foi replicado | Todo método do `ReceivableCalculator` e do `RenegotiationAggregateService` nasce com **teste golden** alimentado por valores extraídos do legado | D-114: o legado não tem nenhum teste. Os goldens passam a ser a primeira especificação executável que o Safegold tem |
| **D-B4** | `ai9-conventions.md` §4 recomenda `decimal(14,2)` para dinheiro; o legado usa `decimal(15,2)` | **`decimal(15,2)`** neste bloco, divergindo da recomendação | O teto do legado é R$ 9.999.999.999.999,99 (DB-152, DB-196). Estreitar a coluna truncaria dado histórico em silêncio — exatamente o que este bloco não pode fazer |
| **D-B5** | Cards de resumo da renegociação atualizavam por chamada explícita após cada ação | **Action Cable** (`renegotiation_channel`), nunca polling | Princípio 10. A infra já existe e é reusada (`useCable.ts`, canal com auth por cookie httpOnly) |
| **D-B6** | `overdue_installments` era coluna persistida, atualizada por cron diário (D-54) | Passa a ser **cálculo em consulta**; o cron desaparece | O número não muda — muda **quando** fica correto. Elimina a janela de 24 h e o caso da renegociação liquidada que nunca mais era reprocessada |
| **D-B7** | Anexos de renegociação usam kt-paperclip, ficam em `public/system/...` e são servidos pelo webserver | **ActiveStorage** com serviço privado + endpoint de download autorizado. **`Medium` não é reusado como está**, e `AssetsProxyController` **não** é reusado de forma alguma | `medium.rb:12` restringe `media_type` a `image`/`video`; anexo de renegociação é majoritariamente PDF. `AssetsProxyController` serve `public/uploads/**` com `disposition: 'inline'` e **sem autenticação** — é literalmente o D-82 |
| **D-B8** | `receivables#index/show/new/edit`, `search_receivable`, e `index`/`show` dos 3 controllers de renegociação | Não portadas; a navegação é do React Router | DEC-09 + evidência de morte (templates ausentes, `current_user.receivables` é associação inexistente). Vão para o ledger como `dropped` **com evidência**, item a item |
| **D-B9** | `Charge#state` e `Renegotiation#kind`/`state` eram string livre | **Enum string + check constraint no banco** (convenção ai9 §4: "Prefira string") | Fecha o domínio sem mudar nenhum valor existente |
| **D-B10** | Busca textual montava fragmento SQL conforme o adaptador detectado em runtime | `ILIKE` do PostgreSQL, com o termo **sanitizado** (`%` e `_` literais) | DEC-05 fixou PostgreSQL. E o fragmento interpolado do legado é injeção de SQL |
| **D-B11** | A cobrança nunca referencia operação diretamente — só via `receipts` | **Preservado** como restrição arquitetural | Está escrito na própria migration legada ("jamais relacionar cobranças e ops diretamente… para evitar problemas de escalabilidade"). É decisão de arquitetura documentada, não descuido |
| **D-B12** | Data do pagamento de renegociação era somente leitura e sempre "hoje" | Passa a ser **editável** (FE-224) | O legado calcula `days_late` a partir dela — o campo travado tornava o cálculo inútil. É a intenção inequívoca do código, não feature nova |
| **D-B13** | Título denormalizado em `receivable_taxes` (cópia do `movement_kind`) | **Manter a cópia** (histórico fiel), sem normalizar | Recibo e tarifa guardam o rótulo do momento da operação. Normalizar mudaria o que telas antigas mostram. Nota registrada: `receivable_taxes` não tem `is_liquidation`, que existe em `movement_kinds` |
| **D-B14** | `Receipt#value = operation_value × (fee/100.0)` — `decimal × float` truncado para `decimal(15,2)` | **Replicado**, arredondamento acidental incluído | DEC-02. É o valor faturado: mudar aqui é mudar a receita reconhecida |
| **D-B15** | `contracts` no legado usa ActionText (`description`), mas a migration que cria a coluna **não existe** (D-108) | ActionText no ai9 (`has_rich_text :description`) — a base **já tem** a tabela e o engine | Reuso não catalogado. Reforça o bloqueador já registrado: existe schema legado fora das migrations |

---

## 4. Lacunas do ai9 (padrão novo a criar)

Não são defeitos da base — são coisas que a base não tem e que este bloco precisa.
Cada uma vira **componente compartilhado**, nunca peça de uma tela só (Princípio 11).

| Necessidade do legado | Existe no ai9? | Padrão proposto |
| --------------------- | -------------- | --------------- |
| **Motor de cálculo financeiro auditável** (26 fórmulas de CET + ~20 agregados de renegociação, com float replicado) | Não. Não há nenhum serviço de cálculo na base | `backend/app/services/receivables/calculator.rb` e `renegotiations/aggregate_service.rb`, funções puras, **teste golden por fórmula**, endpoint `#preview` para a tela consumir |
| **Escopo por projeto (multi-tenancy)** — DEC-07 | Não. Zero `tenant_id`; `blog_intake_session.rb` diz explicitamente "single-tenant" | `Membership` + `project_id` no JWT, validado a cada request no `controller_helpers.rb`. É o mesmo padrão que os outros blocos precisam — **combinar com o agente de `projects` para não nascerem dois** |
| **Máscaras de entrada** (dinheiro, decimal, inteiro, percentual) | Não. `ui/Input.tsx` é cru | `components/ui/{MoneyInput,DecimalInput,IntegerInput,PercentInput}.tsx`. **Cuidado**: o truncamento da 3ª casa (FE-201) é parte da cadeia de arredondamento do DEC-02, não é bug de máscara |
| **Seletor de data e de intervalo em pt-BR** | Não. `date-fns@4` está instalado, mas não há componente | `components/ui/{DatePicker,DateRangePicker}.tsx` sobre `ui/dialog.tsx` + `date-fns` com locale pt-BR |
| **Tabela com ordenação multi-coluna e paginação desktop** | Parcial. `ui/Table.tsx` não ordena; `mobile/MobilePagination.tsx` só existe no mobile | `components/ui/{SortableTableHeader,Pagination}.tsx` |
| **Estado vazio / estado de erro padronizados** | Não | `components/ui/EmptyState.tsx` + `ErrorState.tsx` (React Query já dá `isError`/`refetch`) |
| **Menu de ações de linha + confirmação de operação irreversível** | Parcial. `ui/dialog.tsx` existe; `mobile/MobileMenuActions.tsx` só no mobile | `components/ui/RowActionsMenu.tsx` + `ConfirmDialog.tsx`. **A confirmação não pode expirar sozinha** (o legado descartava em 6 s) |
| **Upload de documento privado** (PDF, não imagem/vídeo) | Parcial. ActiveStorage sim; `Medium` **não** (`medium.rb:12` só aceita `image`/`video`); `api/v1/uploads.rb` grava em `public/uploads/avatars`; `AssetsProxyController` serve `public/` sem auth | `RenegotiationAttachment` com `has_one_attached`, serviço privado, allowlist por conteúdo (Marcel) e endpoint de download autorizado. **Candidato natural a subir para a biblioteca compartilhada do ai9 depois** |
| **Formulário grande com regras cruzadas** (~40 campos no borderô) | Não. Sem `react-hook-form`/`zod`; o padrão é `useState` + validação manual (convenções §5.3) | **Não introduzir a lib nesta migração** — Princípio 6b e proporcionalidade. Usar `useState` + um `useReceivableForm.ts` por tela, com a validação forte no Grape/model. **Registrado como risco de manutenção**, não como bloqueio |
| **Auditoria de alteração em registro financeiro** | Não. `paper_trail` no Gemfile e **não usado**; só `PermissionAuditLog` | Fora do escopo por DEC-09 (o legado não tem). **Exceção**: `contract_deals` precisa de trilha própria (DB-331) — é requisito jurídico, não auditoria genérica |
| **Soft delete** | Não. Só o padrão `discarded_at` + job de purga (`PostDraft`) | Não é necessário neste bloco: o legado usa `restrict_with_error` (bloqueio), não exclusão lógica. **Preservar o bloqueio** (DB-199) |
| **Tabela de alíquotas com vigência** (IOF) | Não | `models/iof_rate.rb` com `valid_from`/`valid_to`, resolvida pela data da operação (BE-160). Padrão reaproveitável por qualquer taxa regulada |
| **Formatação monetária pt-BR compartilhada** | Parcial. `Intl.NumberFormat` inline em `MobileKPI.tsx` e `RechartsBar.tsx` | `lib/format/money.ts` + helper equivalente no backend, com **nulo ≠ zero** (D-117) e arredondamento idêntico ao do cálculo |
| **Gate de `user_is_readonly`** | Não. Só `require_og!` / `restrict_visitor_access!` / `user_type` | Policy declarativa por rota sobre `Permission`/`UserPermission` (DEC-18) + `hooks/usePermission.ts` no front. **Combinar com o agente de `auth-users`** |

---

## 5. Perguntas para o usuário

Ordenadas por consequência. As duas primeiras **bloqueiam a fatia SC-2**.

### Bloqueantes — jurídicas

**Q-B1 (D-64) — O aceite de contrato deve voltar a ser explícito?**
Hoje, em produção, o fluxo está **morto por três motivos independentes**: o bloqueio de
acesso está inteiramente comentado, os dois botões "ACEITAR" estão comentados nas views, e
o cálculo de pendência levanta exceção (`source: :contract_deal`, associação inválida). O
aceite real é **implícito**: um `after_create` no usuário grava os dois aceites sem
nenhuma interação, e o seed **fabrica aceite retroativo para toda a base**. Os checkboxes
de cadastro e de "Minha Conta" vêm **pré-marcados** e não são lidos por nenhum controller.

> **A consequência é jurídica: o sistema registra hoje um aceite que o usuário nunca deu
> conscientemente.** Reativar o fluxo é o comportamento **pretendido pelo código**, mas
> não é o comportamento de produção — então não cabe em "preservar comportamento" nem em
> "corrigir defeito". É decisão de produto e jurídica.
>
> **Não decidi sozinho.** Precisa da sua resposta antes de SC-2.
>
> Sub-perguntas que vêm junto: (a) o que fazer com os aceites implícitos **já existentes**
> na base — migrar como estão, marcar como "aceite implícito (legado)" ou descartar?
> (b) o DEC-18.7 desligou o cadastro público — o consentimento passa a viver no fluxo de
> **convite** (afeta BE-340 e FE-337)?

**Q-B2 (D-65) — Qual é o conjunto mínimo de prova exigido para o aceite?**
`contract_deals` guarda hoje **apenas** `user_id`, `contract_id` e `created_at`. Não há IP,
user-agent nem snapshot do texto; e como o texto vive em `action_text_rich_texts` e pode
ser alterado no próprio registro, **não existe garantia técnica de qual conteúdo foi
aceito**. Minha recomendação técnica é registrar os três (IP, user-agent e impressão
imutável do texto) — mas isso é **requisito novo, não paridade**, e a definição do mínimo
probatório cabe a você e à área jurídica. Depende disto: DB-331, OPS-333, e também
BE-342/BE-343 (a tolerância de 30 dias e o bloqueio só fazem sentido se o ciclo existir).

### Alta consequência

**Q-B3 — Quem publica uma nova versão de contrato?**
A matriz aprovada (DEC-18) dá `contracts` como **`R` para os quatro papéis**
(`authorization-matrix.md:197`), mas BE-335 exige papel administrativo para publicar, e a
lista/detalhe/formulário de contrato existem no console. A matriz é contrato aprovado —
não a altero por conta própria. Proponho **OG + Admin** (o gate do grupo "Admin"), com
`R` para os demais. Confirma?

**Q-B4 — `receipts` e o formulário de seleção de operações não estão na matriz.**
`receipts` é sub-recurso de `charges` e herda o gate do pai por inferência, mas isso não
está escrito. Confirma a herança, ou `receipts` merece linha própria?

**Q-B5 (D-11) — Reprocessar o histórico de operações de risco geradas por borderô?**
O `after_commit` disparava duas vezes: a `RiskOperation` nascia com o valor líquido
**sem as tarifas**. **Isso não é só bug de código — é dado sujo em produção.** O ai9 nasce
certo (BE-183), mas a carga precisa decidir: **recalcular** o valor de operação dos
borderôs históricos (números mudam, ficam certos) ou **copiar** o valor legado (números
batem com hoje, ficam errados)? Minha recomendação: recalcular, com relatório de quantos
mudaram e de quanto.

**Q-B6 (D-14) — `calc_valor_liq_correto` é aproximação linear proposital?**
A fórmula aplica juros simples sobre a taxa diária equivalente, não desconto composto — e
alimenta o `status` "OK"/"Diferença" do borderô. Replico como está (DEC-02). Confirma que
é a regra de negócio pretendida?

**Q-B7 (BE-167) — A guarda do CET do banco olha o prazo da empresa.**
`custo_efetivo_pz_med_banco_sem_iof` zera quando `prz_med_pond_emp == 0`, numa fórmula que
usa `prz_med_pond_bco`. Parece copy/paste. **Replico como está**, porque trocar muda o
valor exibido. Confirma?

**Q-B8 (BE-173) — Por que `custo_efetivo_com_float_total` arredonda em 2 casas e
`custo_efetivo_pz_med_emp` em 4, se a base é a mesma?** Replicado como está.

### Média consequência — decidir por item

| # | Pergunta | Onde |
| - | -------- | ---- |
| **Q-B9** (D-19) | Não existe **nenhum** estado de baixa, liquidação ou vencimento do recebível — só "OK"/"Diferença". A ausência é real ou falta uma funcionalidade inteira? | BE-178 |
| **Q-B10** | `nominal_tax` informada pelo usuário nunca é validada contra as checagens calculadas. Divergência deve virar erro, alerta, ou continuar informativa? | BE-180 |
| **Q-B11** | O legado aceita data de operação em 1900 ou 2100, e não valida `valor_bruto > 0`. Introduzir as validações? | BE-181, FE-177 |
| **Q-B12** (D-19) | `is_active` de carteiras / tipos de recebível é gravado e exibido, mas **nunca aplicado** em nenhum filtro ou select. Passar a esconder os desativados? | BE-185, FE-157 |
| **Q-B13** (D-74) | `is_title` e `is_liquidation` em `movement_kinds` não têm consumidor visível. Campos vivos ou resíduo? | BE-186 |
| **Q-B14** (D-72) | A remuneração é **percentual flat**: nem `agreed_rate`, nem `issue_date`/`due_date`, nem `balance` entram no cálculo do recibo. Zero testes cobrem isso. É a fórmula pretendida? | BE-188 |
| **Q-B15** | Tipo de tarifa duplicado no mesmo borderô é aceito e somado no mesmo bucket. Bloquear? | FE-175 |
| **Q-B16** | Excluir uma tarifa persistida tem efeito **imediato**, mesmo que o usuário cancele a edição do borderô. Manter, ou postergar até salvar? | FE-176 |
| **Q-B17** (D-74) | `receivable_entries.resource_kind_id` nunca é preenchido e não tem associação. Portar como proveniência ou descartar? | DB-151 |
| **Q-B18** | `receivable_entries.observacoes` não é lida nem escrita por nenhuma tela. Vira campo visível, funde com `description`, ou é descartada? | DB-155 |
| **Q-B19** | O ETL Django forçava `user_id = 1` e `company_id = 1` em todos os borderôs de 2016-2021. Reatribuir autor/empresa ou manter? | OPS-150 |
| **Q-B20** | Os ~40 textos de ajuda do formulário de borderô são **placeholder** no legado ("Só um teste de informações do campo…"). Preciso do texto real de cada campo, ou a tela sai sem ajuda? | OPS-154, FE-165 |
| **Q-B21** | Renegociação aceita `original_value = 0`, `total_debt` negativo e taxa negativa. Exigir valores positivos? | BE-199 |
| **Q-B22** | `pending_main_value` (pode ficar negativo) e `remaining_value` (piso em zero) medem "o que falta pagar" com regras diferentes. Qual é o número que o negócio considera correto? | BE-205 |
| **Q-B23** | `due_installments = installments_count − paid_installments`, então a coluna "A vencer" **inclui as vencidas**. É a semântica desejada? | BE-207 |
| **Q-B24** (D-47) | A tela promete correção monetária e carência, mas `interest_rate_correction` e `grace_period` **nunca são lidos** — `correct_value = total_debt` sempre. Implementar de fato ou remover os campos? | BE-208, FE-199 |
| **Q-B25** (D-46) | `calculate_current_value` **reatribui** `current_installment_value` com o valor presente — a coluna "Valor Parcela" passa a mostrar outra coisa sempre que há juros > 0 e saldo em aberto. Replico como está; precisa de reconciliação antes de mudar | BE-212 |
| **Q-B26** | Na parcela, a mora entra **dos dois lados** da conta (soma ao devido e ao pago). Consequência: pagar só a mora pode quitar a parcela. Validar com o negócio | BE-219 |
| **Q-B27** | Renomear anexo é funcionalidade pretendida e **nunca entregue** (a action chama método inexistente). Entra no escopo do ai9 ou fica de fora por DEC-09? | BE-228 |
| **Q-B28** | O legado usa `provider_name` como título da rota do detalhe enquanto a lista mostra `title`. Qual identificação prevalece? | FE-196 |
| **Q-B29** (D-53) | A aba PAGAMENTOS está comentada na view e é a causa do painel não fechar. Entra no escopo? E o botão "excluir todas as parcelas", também comentado? | FE-229 |
| **Q-B30** | Pagamento de renegociação não registra forma de pagamento nem conciliação bancária. Lacuna a preencher ou ausência intencional? | DB-192 |
| **Q-B31** | Três colunas foram renomeadas em 29/04/2022 com mudança de semântica. Existem relatórios ou integrações externas lendo os nomes antigos? | DB-194 |
| **Q-B32** (D-30) | `renegotiations.has_safegold_management` é copiado na criação, nunca ressincronizado, e **nenhum código de renegociação o lê**. Fotografia intencional ou defeito? Portar? | DB-197 |
| **Q-B33** | O percentual de aceite por contrato está **comentado em todas as views**. Foi desligado por performance (volta corrigido) ou por estar errado (sai do escopo)? | BE-344 |
| **Q-B34** | As URLs públicas de contrato viajam com o tipo em português, com espaço e com typo consolidado (`Politicas de Privacidade`, sem acento) — e essas URLs existem em links externos. Adotar slug (`termos-de-uso`) com redirect permanente, ou preservar a string literal? | BE-331, FE-335 |
| **Q-B35** | Tipos de contrato configuráveis pela UI? Hoje são literais em código, e existe `db/seed_assets/contracts/user.html` — um terceiro documento que nenhum seed carrega, sugerindo um "contrato de adesão" planejado e nunca ativado | BE-339, OPS-332 |

---

## 6. Correções ao catálogo da base ai9

Conforme a instrução ("se estiver errado, corrija com evidência"), abaixo o que
**verifiquei abrindo o arquivo** e diverge de `.migration-ai9/ai9-base-catalog.md`.
**Não editei o catálogo** — a instrução desta tarefa proíbe alterar arquivos fora de
`.migration-ai9/map/`. As correções abaixo precisam ser transcritas para lá.

| # | O que o catálogo diz | O que a base realmente tem (evidência) | Consequência para o mapa |
| - | -------------------- | -------------------------------------- | ------------------------ |
| **C-1** | *"Anexos e arquivos — **reuse**. `Medium` + … Cobre o que o legado faz com kt-paperclip: … **anexos de renegociação**"* | `backend/app/models/medium.rb:12` — `validates :media_type, presence: true, inclusion: { in: %w[image video] }`. A tabela `media` (`schema.rb:498-511`) não tem coluna de tamanho, nome original nem content-type | **Anexo de renegociação é `adapt`, não `reuse`.** A maioria dos anexos é PDF, que `Medium` **recusa**. Ver BE-226 / D-B7 |
| **C-2** | Mesma linha lista `assets_proxy_controller.rb` entre as peças de anexo reusáveis | `backend/app/controllers/assets_proxy_controller.rb:5-27` — herda de `ActionController::Base`, serve qualquer arquivo sob `public/uploads/**` com `disposition: 'inline'` e **sem nenhuma autenticação** | **Não reusar para este bloco.** É exatamente o padrão que o D-82 descreve (arquivo público + inline + content-type do uploader = XSS armazenado na mesma origem). Reusável só para asset público de marketing |
| **C-3** | Mesma linha: `api/v1/uploads.rb` como peça genérica de upload | `backend/app/controllers/api/v1/uploads.rb:17-45` — só trata `resource :avatar`, exige `image/*` e grava em `Rails.root/public/uploads/avatars` | Não serve para documento financeiro privado |
| **C-4** | *"O que a base **NÃO** tem: … Formulários com validação declarativa — não há `react-hook-form` nem `zod`"* | **Correto**, confirmado no `package.json`. Registro só o complemento: **`i18next`, `react-i18next` e `src/locales/{pt-br,en}` existem** na base, ao contrário do item 5 da mesma lista ("i18n") | i18n continua **fora de escopo por DEC-09/D-115**, mas a infra existe — o item deveria dizer "fora de escopo", não "a base não tem" |
| **C-5** | Catálogo **não menciona** rich text | `backend/config/application.rb:12` (`require 'action_text/engine'`), `app/models/user.rb:18` (`has_rich_text :biography`), `db/schema.rb:30` (tabela `action_text_rich_texts`), front `components/RichTextEditor.tsx` (Slate) e `RichTextInput.tsx` | **Reuso forte não catalogado.** O `Contract#description` do legado é ActionText — vira `reuse`/`adapt` em vez de `build`. Ver BE-345, DB-330, FE-342 (D-B15) |
| **C-6** | *"WhatsApp — reuse parcial: **`EvolutionConnection`**, `PolemkInstance`, …"*, listado entre os **models** | `EvolutionConnection` é **serviço** (`backend/app/services/evolution_connection.rb`), não model. `ls backend/app/models/` traz 18 arquivos, nenhum com esse nome | Correção menor; não afeta este bloco |
| **C-7** | Catálogo **não menciona** `kaminari` nem `sidekiq-cron` | `backend/Gemfile:85` (`kaminari ~> 1.2`) e `Gemfile:38` (`sidekiq-cron`); `set_pagination_headers` em `controller_helpers.rb`; CORS já expõe `X-Total-Count` | Reuso direto para **toda** paginação deste bloco (corrige D-20) e para OPS-191 |
| **C-8** | Catálogo **não menciona** `image_processing` nem que o ActiveStorage está em Disk | `backend/Gemfile:10`; `config/storage.yml` (Disk, `Rails.root/storage`); `Medium#optimized_url/small_url` já usam `file.variant` | Resolve FE-208 (miniatura de variante) e OPS-193 (dimensões por metadado) sem processo externo |

### Para transcrever em `upstream-flags.md` (não corrigir nesta migração — Princípio 6b)

| # | Achado | Onde | Por que importa |
| - | ------ | ---- | --------------- |
| **F-1** | `AssetsProxyController` serve qualquer arquivo de `public/uploads/**` com `disposition: 'inline'`, **sem autenticação e sem allowlist de tipo** | `backend/app/controllers/assets_proxy_controller.rb:5-27` | Um `.svg` ou `.html` colocado ali executa script na origem da aplicação. Não é problema criado por esta migração, mas é a mesma classe do D-82 que estamos corrigindo no Safegold. **Não mexer aqui**: o controller é usado por outros sistemas da base |
| **F-2** | `api/v1/uploads.rb` grava arquivo de usuário dentro de `public/` | `backend/app/controllers/api/v1/uploads.rb:38-45` | Avatar não é dado sensível, mas o padrão convida a reuso indevido. Sinalizado, não alterado |
| **F-3** | `Api::V1::Base` tem `rescue_from :all` que devolve **backtrace ao cliente** e cita "API ERROR - POLEMK WHATS" em app que não é WhatsApp | `backend/app/controllers/api/v1/base.rb:57-75` | Já registrado como flag 3 no `upstream-flags.md`; aqui vai o **caminho exato** e a observação de que a mensagem está trocada. Endpoints financeiros deste bloco vão precisar de `rescue_from` próprio para não vazar caminho de arquivo em 500 |
| **F-4** | `config/storage.yml` usa `service: Disk` **também em produção** (`config/environments/production.rb:10`) | idem | Anexos de renegociação são documento financeiro. Disk em produção exige volume persistente garantido — é decisão de plataforma, não desta migração, mas **bloqueia o cenário de OPS-192** ("perda de volume não derruba a tela") se não for tratado no deploy |
