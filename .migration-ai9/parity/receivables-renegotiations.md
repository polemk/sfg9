# Paridade — `receivables`, `renegotiations`, `contracts` (Phase 4)

> **246 IDs.** Uma linha por ID: estado final, **como** foi verificado e, quando não deu,
> o motivo. Escrito em 26/08/2026, verificando **por execução**, nunca por leitura.
>
> Ambiente próprio, para não disputar com os outros agentes na mesma árvore:
> `puma` na **3103** (PID anotado), `vite` na **5203**, banco de suíte `sfg9_qa4rec_test`
> (criado e apagado por mim). O `sfg9_dev` foi usado só para exercitar a aplicação, e
> **voltou às contagens exatas do início** (2.706 borderôs · 61 renegociações · 706 parcelas ·
> 444 pagamentos · 2 contratos), sem sobra nenhuma.
>
> **O dump de produção existe e foi usado.** `sfg-31-may-25.sql` (133,4 MB, 56 tabelas,
> 782.742 linhas) e o banco restaurado `sfg_legacy_dump`, **somente leitura**. Ele é de
> **31/05/2025**: prova que as fórmulas batem, **não** é conferência de virada. Nenhum valor,
> nome ou identificador de pessoa foi copiado para cá — só contagens e somatórios.

## As evidências, e o que cada uma mede

| Código | O que foi executado | Medição |
| --- | --- | --- |
| **E1** | Varredura do motor de cálculo contra o dump de produção, linha a linha, pelo procedimento escrito no cabeçalho de `spec/services/receivables/calculator_spec.rb` (a varredura completa **não tinha ferramenta no repo** — só o texto do procedimento; escrevi uma) | **1.001.715 comparações · 0 divergências** sobre 28.095 borderôs limpos (28.131 − 32 com `NaN` gravado − 4 de bucket defasado) |
| **E2** | `rake sfg_etl:renegotiation_parity` nas **duas** origens: `SOURCE=dump` e `SOURCE=db` contra `sfg_legacy_dump` | **47.170 comparações · 47.162 iguais · 0 regressões · 8 mudanças declaradas (D-45)**, idêntico nas duas origens |
| **E3** | Coerência aritmética **interna** do dado real, em SQL somente-leitura no `sfg_legacy_dump` | 10 regras × 28.099 borderôs · 12 regras × 169 renegociações · 5 regras × 5.124 parcelas — **0 divergências** |
| **E4** | **Contrato C2 / D-09** executado por HTTP: `POST /receivables/preview`, `POST /receivables`, `GET /receivables/:id`, `PUT /receivables/:id` com o mesmo payload | **38 derivados idênticos nos 4 caminhos**, campo a campo |
| **E5** | C2 das parcelas por HTTP: `POST installments/preview` × agregado gravado; depois `DELETE installments/batch` | **23 campos idênticos** prévia × gravado; a remoção do lote devolve os agregados ao estado anterior com **0 campos fora** |
| **E6** | Guardas do **D-10** executadas na prévia **e** na gravação | líquido zero → 422 · líquido negativo → 422 · CET acordado &lt; −100% → 422 · prazo médio 0 → 422. **Nunca 500** |
| **E7** | Tela renderizada com login de verdade e dado real, em 1440×900, modo escuro e **390×844** | `/receivables`, `/receivables/novo`, `/receivables/:id`, `/renegotiations`, `/renegotiations/new`, `/renegotiations/:id`, `/admin/contracts`, `/admin/contracts/:kind`, `/contract/:kind` — **0 erro de console, 0 resposta 5xx** |
| **E8** | Comportamento de endpoint executado, com código HTTP **e** mensagem conferidos | 40 chamadas; toda recusa é 400/422/404, nenhuma 500 |
| **E11** | Conferido na **fonte do legado** (`../sfg`), com arquivo e linha — e comparado com `cmp`/`md5sum`, nunca com o `diff` deste shell | — |
| **E13** | Fato de esquema conferido **executando** contra um banco de verdade (`pg_indexes`, `pg_constraint`, `information_schema`), não lendo o `schema.rb` | 9 índices/constraints exigidos pelo mapa: **9 de 9 presentes** |

### Portões que rodei (verde prova que carrega, não que funciona — por isso são o piso, não a prova)

- `rspec` de serviço/modelo do bloco: **205 exemplos, 0 falhas** (goldens: 26 fórmulas de renegociação + 148 do borderô + 13 de portador + 7 de importação de contrato + 11 de agregado).
- `rspec` de request do bloco: **264 exemplos, 0 falhas** (10 arquivos).
- `rspec` de precisão/ETL: **53 exemplos, 0 falhas**.
- `vitest` do bloco: **44 testes, 0 falhas** em 5 arquivos.

---

## Uma linha por ID

### receivables — backend

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| BE-150 | **verified** | **E8+E7** |
| BE-151 | **verified** | **E4 (com ressalva)** — ressalva: provei o RESULTADO (os 38 derivados da gravação são idênticos aos da prévia, com 4 tarifas numa só chamada); **não medi por contagem de query** que o recálculo acontece uma vez só (D-11). |
| BE-152 | **verified** | **E4 (com ressalva)** — ressalva: idem BE-151, pelo `PUT`. |
| BE-153 | **verified** | **E8** |
| BE-154 | dropped | `dropped` no Phase 3 com evidência na própria linha do razão. Não reabri. |
| BE-155 | **verified** | **E1** |
| BE-156 | **verified** | **E1** |
| BE-157 | **verified** | **E1** |
| BE-158 | **verified** | **E1** |
| BE-159 | **verified** | **E1** |
| BE-160 | **verified** | **E1 (com ressalva)** — ressalva: o VALOR bate com produção em 28.095 linhas usando as alíquotas do legado; a **vigência** (`IofRate.effective_on`, a melhoria do D-15) **não tem oráculo** — produção nunca teve tabela de vigência. |
| BE-161 | **verified** | **E1** |
| BE-162 | **verified** | **E1+E6** |
| BE-163 | **verified** | **E1** |
| BE-164 | **verified** | **E1** |
| BE-165 | **verified** | **E1** |
| BE-166 | **verified** | **E1+E6** |
| BE-167 | **verified** | **E1** |
| BE-168 | **verified** | **E1** |
| BE-169 | **verified** | **E1** |
| BE-170 | **verified** | **E1** |
| BE-171 | **verified** | **E1** |
| BE-172 | **verified** | **E1+E6** |
| BE-173 | **verified** | **E1** |
| BE-174 | **verified** | **E1** |
| BE-175 | **verified** | **E1** |
| BE-176 | **verified** | **E1+E6** |
| BE-177 | **verified** | **E1** |
| BE-178 | **verified** | **E1** |
| BE-179 | **verified** | **E1+E6** |
| BE-180 | **verified** | **E1** |
| BE-181 | **verified** | **E6+E8** |
| BE-182 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-183 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| BE-184 | migrated | a exclusão de tarifa (que é o ponto do ID — o recálculo no servidor sem depender do front) não foi executada; o `PUT` com as mesmas tarifas foi (E4). |
| BE-185 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-186 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-187 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| BE-188 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| BE-189 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |

### receivables — frontend

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| FE-150 | **verified** | **E7 (com ressalva)** — ressalva: a tela renderiza em claro, escuro e 390×844, sem erro de console; a **ordenação foi conferida pela API** (E8), não pelo clique no cabeçalho. |
| FE-151 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-152 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-153 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-154 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-155 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-156 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-157 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-158 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-159 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-160 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-161 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-162 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-163 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-164 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-165 | **verified** | **E7 (com ressalva)** — ressalva: o formulário renderiza inteiro, com o painel de cálculo em estado vazio e as três mensagens de guarda; **não preenchi o formulário no navegador** — a prévia foi provada pelo endpoint (E4). |
| FE-166 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-167 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-168 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-169 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-170 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-171 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-172 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-173 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-174 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-175 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-176 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-177 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-178 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-179 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| FE-180 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| FE-181 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| FE-182 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| FE-183 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| FE-184 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| FE-185 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| FE-186 | migrated | depende de capability fora do meu bloco (`structured-operations` / `risk`); não executei. |
| FE-187 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-188 | migrated | o caminho deste ID não foi executado nesta passada. |
| FE-189 | migrated | o caminho deste ID não foi executado nesta passada. |

### receivables — dados

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| DB-150 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-151 | **verified** | **E13** |
| DB-152 | **verified** | **E13 (com nota)** — ressalva: o mapa diz **18** colunas `decimal(15,2)`; medi **20** no banco. Colunas acrescentadas depois do mapa — não é defeito, é o mapa que envelheceu. |
| DB-153 | **verified** | **E1+E13** |
| DB-154 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-155 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-156 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-157 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-158 | **verified** | **E13** |
| DB-159 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-160 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-161 | **verified** | **E13** |
| DB-162 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-163 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-164 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-165 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-166 | **verified** | **E13** |
| DB-167 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |

### receivables — operação

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| OPS-150 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| OPS-151 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| OPS-152 | dropped | `dropped` no Phase 3 com evidência na própria linha do razão. Não reabri. |
| OPS-153 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-154 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-155 | dropped | `dropped` no Phase 3 com evidência na própria linha do razão. Não reabri. |
| OPS-156 | dropped | `dropped` no Phase 3 com evidência na própria linha do razão. Não reabri. |
| OPS-157 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-158 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-159 | migrated | o caminho deste ID não foi executado nesta passada. |

### renegotiations — backend

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| BE-190 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-191 | **verified** | **E8** |
| BE-192 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-193 | **verified** | **E8** |
| BE-194 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-195 | **verified** | **E8** |
| BE-196 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-197 | dropped | `dropped` no Phase 3 com evidência na própria linha do razão. Não reabri. |
| BE-198 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-199 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-200 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-201 | **verified** | **E8** |
| BE-202 | **verified** | **E5** |
| BE-203 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-204 | **verified** | **E2 (reconfirmado)** |
| BE-205 | **verified** | **E2 (reconfirmado)** |
| BE-206 | **verified** | **E2 (reconfirmado)** |
| BE-207 | **verified** | **E2 (reconfirmado)** |
| BE-208 | **verified** | **E2 (reconfirmado)** |
| BE-209 | **verified** | **E2 (reconfirmado)** |
| BE-210 | migrated | não há oráculo: é derivado de leitura que o legado nunca persistiu. |
| BE-211 | migrated | não há oráculo: é derivado de leitura que o legado nunca persistiu. |
| BE-212 | **verified** | **E2 (reconfirmado)** |
| BE-213 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-214 | **verified** | **E8** |
| BE-215 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-216 | **verified** | **E8** |
| BE-217 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-218 | **verified** | **E8+E13** |
| BE-219 | **verified** | **E2 (reconfirmado)** |
| BE-220 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-221 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-222 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-223 | **verified** | **E2 (reconfirmado)** |
| BE-224 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-225 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-226 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-227 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-228 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-229 | migrated | o caminho deste ID não foi executado nesta passada. |

### renegotiations — frontend

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| FE-190 | **verified** | **E7 (com ressalva)** — ressalva: lista renderiza com as colunas e os agregados; filtros e ordenação conferidos pela API (E8). |
| FE-191 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-192 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-193 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-194 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-195 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-196 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-197 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-198 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-199 | **verified** | **E7 (com ressalva)** — ressalva: formulário renderiza inteiro; **a criação pela tela é impossível no seed** — ver D-QA4-02. |
| FE-200 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-201 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-202 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-203 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-204 | **verified** | **E7 (com ressalva)** — ressalva: detalhe renderiza com KPIs, abas, cartão de cadastro e anexos, em claro, escuro e telefone. |
| FE-205 | **verified** | **E7 (com ressalva)** — ressalva: cartão de cadastro com os 15 campos, inclusive a chave de integração. |
| FE-206 | **verified** | **E7 (com ressalva)** — ressalva: os 4 cartões de resumo batem com o que a API devolve para a mesma renegociação. |
| FE-207 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-208 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-209 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-210 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-211 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-212 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-213 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-214 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-215 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-216 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-217 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-218 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-219 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-220 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-221 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-222 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-223 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-224 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-225 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-226 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-227 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-228 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-229 | dropped | `dropped` no Phase 3 com evidência na própria linha do razão. Não reabri. |

### renegotiations — dados

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| DB-190 | **verified** | **E13** |
| DB-191 | **verified** | **E13** |
| DB-192 | **verified** | **E13** |
| DB-193 | **verified** | **E2 (reconfirmado)** |
| DB-194 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-195 | **verified** | **E2 (reconfirmado)** |
| DB-196 | **verified** | **E13** |
| DB-197 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |
| DB-198 | **verified** | **E13** |
| DB-199 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |

### renegotiations — operação

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| OPS-190 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-191 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-192 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-193 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-194 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-195 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-196 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-197 | migrated | depende da CARGA rodada contra o destino. O dump prova a FÓRMULA, não a virada — e a carga só acontece se o cliente comprar. |

### contracts — backend

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| BE-330 | **verified** | **E8+E7** |
| BE-331 | **verified** | **E8 (com ressalva)** — ressalva: o 404 para tipo desconhecido está provado; *"vigente = maior `version`"* **não**, porque só existe a versão 1 de cada tipo no seed — falta um segundo registro para a regra poder falhar. |
| BE-332 | **verified** | **E8+E7** |
| BE-333 | migrated | as recusas estão provadas (sem sessão → 401; id inexistente → 404). O **aceite positivo não foi executado de propósito**: gravaria um consentimento no seed compartilhado e mudaria o estado inicial da demonstração para os outros agentes. Precisa do usuário para liberar. |
| BE-334 | **verified** | **E8** |
| BE-335 | migrated | a publicação exige papel administrativo; publiquei como Admin e o servidor aceitou o papel, mas **não publiquei uma versão de verdade** para não sujar o catálogo do seed. O gate de papel negativo (gerente/colaborador) não foi executado. |
| BE-336 | migrated | a numeração só se prova com uma publicação real e com concorrência; não executei (ver BE-335). |
| BE-337 | **verified** | **E13** |
| BE-338 | **verified** | **E8** |
| BE-339 | **verified** | **E8** |
| BE-340 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-341 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-342 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-343 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-344 | dropped | `dropped` no Phase 3 com evidência na própria linha do razão. Não reabri. |
| BE-345 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-346 | dropped | `dropped` no Phase 3 com evidência na própria linha do razão. Não reabri. |
| BE-347 | migrated | o caminho deste ID não foi executado nesta passada. |
| BE-348 | dropped | `dropped` no Phase 3 com evidência na própria linha do razão. Não reabri. |
| BE-349 | **verified** | **E8+E7** |

### contracts — frontend

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| FE-330 | **verified** | **E7** |
| FE-331 | **verified** | **E7** |
| FE-332 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-333 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-334 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-335 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-336 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-337 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-338 | **verified** | **E7** |
| FE-339 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-340 | **verified** | **E7** |
| FE-341 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |
| FE-342 | migrated | a tela renderiza sem erro de console e sem 5xx (E7), mas o comportamento específico deste ID não foi exercido nesta passada. |

### contracts — dados

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| DB-330 | **verified** | **E13** |
| DB-331 | **verified** | **E13+E8** |

### contracts — operação

| ID | Estado final | Como verifiquei / por que não deu |
| -- | ------------ | --------------------------------- |
| OPS-330 | **verified** | **E11+E7** |
| OPS-331 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-332 | migrated | o caminho deste ID não foi executado nesta passada. |
| OPS-333 | **verified** | **E8** |
| OPS-334 | migrated | o caminho deste ID não foi executado nesta passada. |

---

## Contagem final

| Estado | IDs |
| --- | ---: |
| **verified** | **84** |
| migrated | 153 |
| dropped | 9 |
| **total** | **246** |

Dos 84 `verified`, **11 já eram** (BE-204…209, BE-212, BE-219, BE-223, DB-193, DB-195, promovidos
na S9). **73 são novos**, e 26 deles saem de oráculo de produção de verdade.

---

## Defeitos achados

### D-QA4-01 — o contador de força bruta conta **login bem-sucedido como falha**, e a trava se auto-alimenta

**Onde:** `app/services/auth/magic_login_service.rb:73` (`update_last_attempt`) + `app/models/login_attempt.rb`.
**Não é do meu bloco** — é da S1/auth. Está aqui porque **trancou a verificação visual do Phase 4
inteiro nesta máquina**, e porque o artefato que existia sobre ele estava errado.

`update_last_attempt` faz `LoginAttempt.where(...).last`. A tabela tem PK **`uuid`** e o modelo
**não define `implicit_order_column`**, então o SQL que sai é literalmente:

```sql
SELECT "login_attempts".* FROM "login_attempts" WHERE ... ORDER BY "login_attempts"."id" DESC LIMIT 1
```

Ordenar por UUID aleatório não é ordenar por tempo. Medido em banco próprio, **200 rodadas de 3
linhas**: `.last` devolveu a mais recente **58 vezes** — 29%, exatamente o 1/3 do acaso. Nas outras
71% o serviço marca como bem-sucedida uma tentativa **antiga** e deixa a recém-criada em
`success: false` para sempre.

**A consequência é operacional, não estética.** As três regras de `LoginAttempt.suspicious_activity?`
contam linhas `failed`:

| Regra | Limite | O que a trava vira na prática |
| --- | --- | --- |
| `failed_attempts_count(identifier, 15.min)` | 5 | ~5 pedidos legítimos de código da MESMA conta trancam a conta |
| `ip_failures` | 10 | ~10 pedidos legítimos do MESMO IP trancam **o IP inteiro** |
| `unique_identifiers` por IP | 5 | 5 contas distintas do mesmo IP |

Medido no `sfg9_dev` durante esta passada: **`falhas_ip = 10/10`, `distintos = 3/5`, `sucessos na
janela = 13`**. Ou seja, o IP travou pela regra das 10 falhas, com 3 identificadores só e 13
sucessos — as "falhas" eram os órfãos.

E a trava **se realimenta**: cada tentativa de destravar pede um código novo, que cria mais uma linha
`failed`. Fiquei preso ~25 minutos até entrar pelo **magic link** (fluxo real do produto,
`Auth::MagicLinkVerifyService`, que não passa pelo `LoginAttempt`).

**Como reproduzir em 30 segundos**, em banco próprio:

```ruby
3.times { |i| LoginAttempt.create!(identifier: "x@x", method: "email", ip_address: "127.0.0.1",
                                  success: false, created_at: Time.current + i.seconds) }
LoginAttempt.where(identifier: "x@x").order(id: :desc).limit(1).to_sql
# => ORDER BY "login_attempts"."id" DESC   <- uuid, não tempo
```

Ou, pela aplicação: peça código 10 vezes para contas diferentes e conte
`LoginAttempt.where(success: false).count`.

**Conserto de uma linha:** `self.implicit_order_column = :created_at` em `LoginAttempt` — ou trocar
`update_last_attempt` por atualizar o registro que `create_login_attempt` acabou de devolver, que é
o certo de verdade (não depender de ordenação nenhuma).

**Junto com o defeito, um artefato errado.** `.migration-ai9/tools/README.md` e a mensagem de erro do
`browser.js` afirmam que o bloqueio é *"a trava de força bruta por IP (5 identificadores distintos em
15 min) — trocar de `--as=` não ajuda"*, e dizem **"não é defeito: é a trava funcionando"**. Medi: era
a regra de **5 falhas por identificador** primeiro e a de **10 falhas por IP** depois; os
identificadores distintos estavam em 3. Quem seguir o texto troca de conta achando que não adianta,
ou espera achando que é normal. **É defeito, e a mensagem manda caçar fantasma.**

### D-QA4-02 — "Nova renegociação" é **impossível pela tela** no seed de demonstração

**Onde:** dado do seed × `renegotiations.integration_key` única por projeto (`BE-199`, correção
deliberada do legado, que deixava homônimos colidirem em silêncio). A regra está certa; o **seed** é
que não deixa espaço.

O formulário oferece os fornecedores do projeto. Medido: **todos os 12 projetos** têm exatamente
tantas renegociações quantas fornecedores — 3 e 3, 9 e 9, 12 e 12, 13 e 13. **Zero folga em todos.**

Executado nos 3 fornecedores que o formulário do projeto do Admin oferece:

```
8bf48f96… -> 422  Integration key já está em uso neste projeto
1c88f98a… -> 422  Integration key já está em uso neste projeto
ae6851c0… -> 422  Integration key já está em uso neste projeto
```

**Como reproduzir:** abrir `/renegotiations/new`, escolher **qualquer** fornecedor, preencher e
salvar. Não existe escolha que funcione.

**Consequência:** na apresentação, "criar uma renegociação" — que é a ação de entrada da tela — falha
sempre, com uma mensagem que parece defeito de sistema. **Conserto é de seed**, não de código:
semear alguns fornecedores sem renegociação em cada projeto.

### D-QA4-03 — a decisão "tarifa `NaN` entra como NULO" **ainda não existe no código**

**Onde:** `db/schema.rb` (`receivable_taxes.value` `null: false`), `app/lib/sfg/etl/values.rb:146`
(`to_decimal`), `app/lib/sfg/etl/converters/receivable_taxes.rb`, `app/models/receivable_tax.rb`.

O usuário decidiu: a **1 linha** de `receivable_taxes` com `NaN` (confirmada por mim no dump: 1 em
58.473, afetando 1 borderô) entra como **NULO**, e as somas do borderô **ignoram** tarifa nula.
Executei os quatro pontos:

| O que | Hoje |
| --- | --- |
| `Sfg::Etl::Values.to_decimal("NaN")` | devolve **`NaN`** — `BigDecimal("NaN")` **não levanta**, e o `numeric` do Postgres aceita |
| `receivable_taxes.value` | `null: false` — **não dá para gravar o NULO decidido** |
| `ReceivableTax` (modelo) | recusa NULO (*"não pode ficar em branco"*) **e** recusa NaN (*"não é um número válido."*) |
| `Receivables::Calculator` com tarifa nula | soma **ignora** (100,00 de 1 tarifa válida + 1 nula) — este pedaço **já está certo** |

O conversor hoje só **reporta** a linha como anomalia, com o texto *"Disposição pendente do usuário."*
— escrito antes da decisão chegar. **Falta:** migration tornando a coluna nulável, o `convert`
mapeando `NaN`→`nil`, e a validação do modelo aceitando `nil`. É o único item do meu bloco que sei
que está incompleto **por decisão nova**, não por descuido.

---

## Coisas que PARECIAM defeito e não são — conferidas na fonte antes de eu abrir a boca

1. **A lista de recebíveis não fecha na conta.** `BRUTO 1.187.365,96 − TARIFAS 44.485,84 ≠ LÍQUIDO
   1.116.866,41`. A diferença é exatamente `vlr_bruto_recusado = 26.013,71`, coluna que a lista não
   mostra. Fui ao legado: `../sfg/app/views/pub/console/parts/receivables/list/_widget.html.erb:22-29`
   mostra **as mesmas três colunas**, com o mesmo buraco. É réplica fiel (DEC-30), não defeito.
2. **`Math::DomainError` no motor.** `BigDecimal#**` com base negativa e expoente fracionário
   **levanta** no Ruby 3.4 (no 2.6.1 de produção devolvia `NaN`). Aparece com líquido negativo —
   R$ 236,89 de bruto com R$ 500,00 de deságio basta. **O `InputGuard` cobre**: `exponent_base_errors`
   devolve 422 na prévia **e** na gravação, executado. Só escapa quem chamar
   `Receivables::Calculator.call` direto, sem o guarda — foi o que a minha varredura fez de propósito.
3. **13 parcelas de produção com `paid_value` ≠ soma dos pagamentos.** Era **a minha regra** que estava
   errada: `paid_value` da parcela soma (principal+juros+CM **+ mora**), e as 13 são exatamente as 13
   parcelas que têm mora. Com a mora dentro: **0 fora de 5.124**. Re-conferi antes de reportar.
4. **KPI do telefone sem centavos** — R$ 330.107,52 vira **R$ 330.108**. Está escrito no código como
   deliberado (`components/mobile/MobileKPI.tsx:47-53`, `maximumFractionDigits: 0`). **Não mexi.** Mas
   registro: neste bloco, arredondar **para cima** um valor pago é o tipo de número que vira pergunta
   de cliente. Decisão do usuário se muda ou fica.
5. **O texto dos Termos de Uso é de outro produto** — fala em *"o box"*, *"anunciantes"*,
   *"varejistas"*. Comparei com `cmp` e `md5sum` (nunca com o `diff` deste shell):
   `db/seed_assets/contracts/tou.html` é **byte a byte idêntico** ao do legado
   (`c537fa885b9e1131d8d317725035eeb2`), e `privacy.html` também. **A migração está certa; o conteúdo
   herdado é que é impróprio para uma demonstração ao cliente.** Decisão do usuário.

---

## Artefatos que envelheceram — re-verificados na fonte, como manda a lição de 26/08

| Artefato | O que dizia | O que medi |
| --- | --- | --- |
| **O meu próprio briefing** | *"`total_debt = original_pending_value + additional_value + correct_value`"* | **Não é invariante.** Em produção passa **vazia**: `original_pending_value` = 0 nas **169** e `additional_value` = 0 nas **169**, e `correct_value = total_debt` **sempre** (D-47, `../sfg/app/models/renegotiation.rb:26,93`). No seed do ai9, que preenche esses dois campos, a regra falha **61 de 61** |
| **O meu próprio briefing** | *"`remaining_value = total_debt − paid_value`"* | Falha **55 de 169 em produção**. `remaining_value` é a soma de `pending_value` das parcelas (**piso em zero**) e `paid_value` **conta a mora** — a assimetria está documentada e é para preservar |
| **O meu próprio briefing** | *"Backend: `rvm use 3.2.3`"* | `Gemfile` e `.ruby-version` pedem **3.4.9**; com 3.2.3 o `bundler` recusa com `RubyVersionMismatch`. O `checkpoint.md` repete o 3.2.3 |
| **`tools/README.md`** e a mensagem do `browser.js` | *"trava de força bruta por IP (5 identificadores distintos) — **não é defeito**"* | Era a regra de **5 falhas por identificador** e a de **10 falhas por IP**; os distintos estavam em **3**. E **é** defeito — D-QA4-01 |
| **`calculator_spec.rb`** (cabeçalho) | *"`nominal_tax_check` nulo em 18.900 linhas — as colunas nasceram em `20220322123523` e as anteriores nunca foram recalculadas"* | O **total 18.900 está certo**; o **critério não**. O corte é por `created_at` e vai até **14/04/2022 18:08** — **781** linhas nasceram depois da migration e antes do deploy que passou a gravar. Cortar pela data da migration deixa 598 falsos positivos |
| **`calculator_spec.rb`** (cabeçalho) | *"Resultado da última execução: 927.267 comparações, 0 divergências"* | O número é repetido como verdade e **não existe ferramenta no repo que o refaça** — há `app/lib/sfg/etl/parity/renegotiations.rb`, **não há** o equivalente de `receivables`. Refiz a varredura com script próprio: **1.001.715 comparações, 0 divergências** |
| **`map/…` DB-152** | *"18 colunas `decimal(15,2)`"* | São **20** no banco. Colunas acrescentadas depois do mapa — o mapa é que envelheceu |
| **`map/…` BE-214** | *"Data ausente → **422** (não 500)"* | É **400** (validação de parâmetro do Grape). O ponto do item — *não 500* — está cumprido; o número previsto no mapa, não |

---

## O que precisa do usuário

1. **D-QA4-01, o conserto do `LoginAttempt`.** É de uma linha e destrava a verificação visual de
   todos os agentes. Não mexi porque é bloco da S1 e há outro agente na árvore.
2. **D-QA4-02, folga de fornecedor no seed.** Sem isso, "Nova renegociação" falha sempre na
   apresentação.
3. **D-QA4-03**, implementar a decisão do `NaN` da tarifa (migration + converter + validação).
4. **O aceite de contrato (BE-333) e a publicação de versão (BE-335/336)** ficaram `migrated` de
   propósito: executá-los grava consentimento e cria versão no seed **compartilhado**, mudando o
   estado inicial da demonstração para os outros agentes. Autorize e eu executo.
5. **O texto dos Termos de Uso e da Política** (item 5 acima) — decisão de conteúdo.
6. **Arredondamento do KPI no telefone** (item 4 acima) — decisão de produto.
7. Se quiser, transformo o meu script de varredura em `app/lib/sfg/etl/parity/receivables.rb` +
   `rake sfg_etl:receivable_parity`, para o número de 1.001.715 parar de ser folclore e virar
   comando.

---

## Ambiente, e o que devolvi limpo

- `puma` na **3103** (PID 3656116, anotado e morto por ele), `vite` na **5203**.
- Banco de suíte **próprio** `sfg9_qa4rec_test`, criado e apagado por mim — nunca usei o `sfg9_test`
  compartilhado como portão.
- `sfg_legacy_dump`: **somente leitura**, só `SELECT` de contagem e somatório. Nenhum nome, e-mail,
  documento ou valor identificável foi copiado para nenhum relatório.
- `sfg9_dev`: criei 1 borderô, 6+1 parcelas e 1 lote de teste, **e apaguei tudo pelos próprios
  endpoints do produto**. Contagens no fim: **2.706 · 61 · 706 · 444 · 2** — idênticas às do início,
  com **0 sobras** com o prefixo `QA4`.
- `git add` sempre por caminho explícito.

---

## Nota de bancada — o `git add` por caminho explícito **não basta**

Registro porque a regra escrita no `checkpoint.md` cobre metade do problema e eu vivi a outra metade.

Usei `git add` por caminho explícito, como manda. Mesmo assim, o meu commit levou **155 linhas do
razão que não são minhas** — as promoções do agente de risco (BE-230…, `Phase 4 do bloco risco`), que
estavam **no disco, sem commit**, quando o meu `git add` leu o arquivo. E o commit dele, minutos
antes, levou as **minhas** 84 pelo mesmo motivo.

**Conferi antes de sair, e nada se perdeu:** 1.439 IDs no razão, **0 perdidos**, **0 estados
regredidos**, **0 linhas encolhidas**. As duas passadas estão inteiras; só a autoria dos commits ficou
trocada.

**A regra que faltava:** num arquivo compartilhado, caminho explícito protege contra levar *outro
arquivo*; não protege contra levar *outra edição no mesmo arquivo*. O que protege é **conferir o
próprio commit depois de fazê-lo** — `git show HEAD -- <arquivo>` e olhar as linhas que mudaram fora
do seu escopo. Foi assim que eu vi. Levou 40 segundos e teria virado acusação errada se eu não
tivesse olhado o conteúdo das duas versões: a minha primeira leitura do diff dizia *"varri o trabalho
alheio"*, e o sentido era o oposto.

**Efeito colateral bom:** com as duas passadas no lugar, o `rake sfg_etl:ledger_gate` agora **passa
nos 5 portões**, inclusive o *"nenhum item aberto sem dono"*, que era o que reprovava a tarefa
S14 10.7. Não fui eu que fechei os 37 `pending` — só registro que o portão está verde, para quem for
fechar a 10.7 não repetir a leitura velha sem conferir.
