# frozen_string_literal: true

# S6 — **o borderô**. `receivable_entries` e `receivable_taxes`.
#
# Fecha **DB-150**…**DB-157**, **DB-161**, **DB-164 (parcial)**, **DB-166**,
# **DB-564** e **DB-565**.
#
# ### Os nomes das colunas continuam em português
#
# Mesma escolha da S5 em `risk_controls` (`limite`, `taxa`,
# `limite_auto_liquidaveis`): os nomes do legado são preservados. São 60 colunas
# citadas por nome em `receivable_entry.rb:38-118`, nos goldens, no conversor de
# ETL e na conferência de paridade — renomear em massa trocaria o benefício de
# estilo por um mapa de 60 linhas que ninguém consegue auditar. Identificadores
# NOVOS (models, serviços, rotas, enums) continuam em inglês.
#
# ### A tabela fica LARGA de propósito
#
# São ~30 colunas **derivadas** (`custo_efetivo_*`, `taxa_desconto_nominal_*`,
# `multiplicador_*`, `*_percent`, os buckets de tarifa). Elas são derivadas do
# ponto de vista da fórmula, mas **armazenadas** do ponto de vista do banco: a
# lista ordena por `custo_efetivo_pz_med_emp`, filtra por `date` e soma
# `valor_liquido`. Calcular na leitura são 28 mil expressões por página. O que
# muda em relação ao legado é **quem** as escreve: um serviço só
# (`Receivables::Calculator`), não um `before_validation` de 80 linhas.
#
# ### Tipos — medidos no dump de produção, não supostos
#
# O legado mistura `decimal(15,2)` (dinheiro) e `float` (prazos, taxas, CETs,
# percentuais). O **DB-153** manda armazenar em `decimal` "com resultado
# idêntico ao float". Contei a precisão real das 28.131 linhas de produção:
#
# | Grupo | Casas em produção | Coluna aqui | Idêntico? |
# | ----- | ----------------- | ----------- | --------- |
# | dinheiro | 2 | `decimal(15,2)` | sim |
# | prazos (`prz_med_pond_*`) | 4 | `decimal(15,6)` | sim |
# | `taxa_desconto_nominal_*` | 2 (o legado faz `round(2)`) | `decimal(12,4)` | sim |
# | 7 CETs | 4 e 2 (`round(4)`/`round(2)`) | `decimal(12,4)` | sim |
# | `checagem_iof`, `dif_calc_vlr_liq` | 2 (`round(2)`) | `decimal(15,2)` | sim |
# | `float_calculado`, `diferenca_float`, os 4 `*_percent` | **até 20** | `decimal(15,6)` | **não** |
#
# As seis últimas não passam por `round` no legado: elas guardam o **ruído
# binário** do `float` (`79.7 - 76.7` grava `3.0000000000000057`). Nenhuma tem
# significado além da 4ª casa — as entradas têm 4 —, e as duas telas que as
# mostram formatam em 2. O corte em 6 casas é **perda deliberada de ruído**, não
# de informação, e está escrito aqui para que a conferência de paridade compare
# na precisão de exibição e não acuse regressão.
#
# > ### ⚠ SUPERADO PELA DEC-117 (26/08/2026) — a última linha da tabela mudou
# >
# > O raciocínio acima foi **medido e reprovado**: contra o dump de 31/05/2025 o
# > `decimal(15,6)` dessas 6 produziu **48 divergências em 5.321 comparações**
# > (`spec/lib/sfg/etl/values_precision_spec.rb`). "Perda de ruído" descrevia o
# > efeito, não a regra — e a DEC-02 exige o número **idêntico**, não parecido.
# >
# > `20260826235200_seis_colunas_de_escala_6_voltam_a_float.rb` devolve as 6 para
# > `float`, como o legado. **As outras 19 `float` do legado seguem `decimal`**, e
# > para elas as linhas acima continuam válidas: 0 divergências medidas.
#
# **O CÁLCULO continua em ponto flutuante** (DEC-02 / D-104), na mesma ordem e
# com os mesmos casts do legado. O que muda é só o armazenamento.
#
# ### `resource_kind_id` NÃO existe aqui
#
# Medido: **0 de 28.131** linhas de produção têm valor, e `resource_kinds` tem
# **0 linhas**. `DB-289` é `dropped` com evidência.
#
# ### Tipo e subtipo de operação de risco: NUNCA RODARAM EM PRODUÇÃO
#
# `20220610122917_add_risk_operation_type_to_receivable_entries` é uma das 24
# migrations que **nunca subiram** (`analise-dump-producao.md` §1) — o `COPY` de
# `receivable_entries` do dump não tem as duas colunas. Por **DEC-103b** elas
# vêm assim mesmo, espelhando o código de 2022, e todo golden que dependa delas
# leva a marca `NUNCA EXECUTADO EM PRODUÇÃO`.
class CreateReceivableEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :receivable_entries, id: :uuid, default: -> { 'gen_random_uuid()' },
                                      comment: 'Borderô — o lançamento de recebível. Onde o dinheiro entra no sistema. Escopado por projeto (C1). 28.131 linhas em produção, de 27/02/2022 a 30/05/2025.' do |t|
      # ---------------------------------------------------------------- vínculos
      t.uuid :project_id, null: false, comment: 'Projeto dono. Contrato C1 — o escopo é aplicado no endpoint, nunca por `default_scope`.'
      t.uuid :company_id, null: false, comment: 'Empresa (tomadora). Obrigatória desde 03/2022 (`20220322123523`). Borderôs anteriores receberam a empresa do projeto — ver DB-154 e o relatório do ETL.'
      t.uuid :carrier_id, null: false, comment: 'Portador (financiador). Catálogo GLOBAL; a oferta na tela é `ProjectToCarrierConnection.for_project`.'
      t.uuid :wallet_id, null: false, comment: 'Carteira.'
      t.uuid :receivable_kind_id, null: false, comment: 'Tipo de recebível.'
      t.uuid :resource_source_id, null: false, comment: 'Fonte do recurso. Obrigatória no legado e preenchida em 28.131 de 28.131 linhas de produção.'
      t.uuid :user_id, comment: 'Autor. Vem da SESSÃO — o `user_id` do corpo é ignorado.'

      t.uuid :risk_operation_type_id, comment: 'Tipo de operação de risco. OPCIONAL ("Não associar"). DERIVADO do subtipo no before_validation. NUNCA EXECUTADO EM PRODUÇÃO (DEC-103b).'
      t.uuid :risk_operation_subtype_id, comment: 'Subtipo de operação de risco. OPCIONAL. É ele que exige RiskControl ativo. NUNCA EXECUTADO EM PRODUÇÃO (DEC-103b).'

      # ------------------------------------------------------------- identificação
      t.date :date, null: false, comment: 'Data do borderô. Chave de ordenação padrão da lista.'
      t.date :data_credito, comment: 'Data de crédito. Nula em 20 de 28.131 linhas de produção.'
      t.string :nro_bordero, comment: 'Número do borderô. **String**, nunca inteiro: produção tem `F-76`, `48-49`, `202023005-6`, `1540962/20` e 669 linhas com texto vazio. Máximo medido: 29 caracteres.'
      t.string :contrato, comment: 'Contrato. PORTADO SEM TELA: 28.131 de 28.131 linhas de produção têm NULL, e nenhuma view do legado o lê.'
      t.text :description, comment: 'Descrição visível na lista (tooltip da linha). 9.231 linhas preenchidas em produção.'
      t.text :observacoes, comment: 'Observações. DEC-52 — ganha campo no formulário e exibição: são 379 textos de negócio, vindos do importador Django, que ninguém nunca viu na tela.'

      t.boolean :has_safegold_management, null: false, default: false,
                                          comment: 'Cópia da marca do projeto, recarimbada em TODO save — igual ao legado (`receivable_entry.rb:40`). Diferente da escolha da S4 em `Company` (derivar): aqui há 28.131 valores históricos em produção a preservar.'

      # -------------------------------------------------------------- entradas
      t.integer :qtd_titulos, null: false, comment: 'Quantidade de títulos. Máximo medido em produção: 28.889.400.'
      t.integer :qtd_recusada, null: false, default: 0, comment: 'Quantidade recusada. Nulo vira zero no `set_defaults` do legado.'
      t.decimal :valor_bruto, precision: 15, scale: 2, null: false, comment: 'Valor bruto. **Sem** exigência de `> 0` — como hoje (Q-B11).'
      t.decimal :vlr_bruto_recusado, precision: 15, scale: 2, null: false, default: 0, comment: 'Valor bruto recusado.'
      t.decimal :prz_med_pond_emp, precision: 15, scale: 6, null: false, comment: 'Prazo médio ponderado da EMPRESA, em dias. Validado `> 0`.'
      t.decimal :prz_med_pond_bco, precision: 15, scale: 6, null: false, comment: 'Prazo médio ponderado do BANCO, em dias. Validado `> 0`.'
      t.decimal :float_acordado, precision: 15, scale: 6, null: false, default: 0, comment: 'Float acordado, em dias.'
      t.decimal :cst_efetivo_acordado, precision: 12, scale: 4, null: false, default: 0, comment: 'Custo efetivo acordado, em % a.m. Alimenta `calc_valor_liq_correto`.'
      t.decimal :nominal_tax, precision: 12, scale: 4, comment: 'Taxa nominal INFORMADA pelo usuário. Continua sem ser validada contra as checagens (Q-B10) — é informativa. Coluna de 03/2022: nula em 18.900 linhas.'

      # --------------------------------------------------------------- deduções
      t.decimal :recompra, precision: 15, scale: 2, null: false, default: 0
      t.decimal :retencao, precision: 15, scale: 2, null: false, default: 0
      t.decimal :fomento, precision: 15, scale: 2, null: false, default: 0
      t.decimal :outros, precision: 15, scale: 2, null: false, default: 0

      # ------------------------------------------------------ buckets de tarifa
      # DERIVADOS das linhas de `receivable_taxes`, denormalizados aqui porque a
      # lista soma e ordena por eles.
      t.decimal :tarifas_ad_valorem, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: soma das tarifas com `is_advalorem`.'
      t.decimal :tarifas_desagio, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: soma das tarifas com `is_desagio`.'
      t.decimal :tarifas_iof, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: soma das tarifas com `is_iof`.'
      t.decimal :tarifas_outras, precision: 15, scale: 2, null: false, default: 0,
                                  comment: 'DERIVADO: total − advalorem − deságio − iof. Fica NEGATIVO se uma tarifa tiver dois classificadores; replicado (DEC-02) e reportado pelo ETL, nunca corrigido em silêncio.'

      # -------------------------------------------------------------- derivados
      t.decimal :vlr_bruto_final, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: `valor_bruto − vlr_bruto_recusado`. Negativo é aceito e propagado.'
      t.integer :qtd_final, null: false, default: 0, comment: 'DERIVADO: `qtd_titulos − qtd_recusada`.'
      t.decimal :float_calculado, precision: 15, scale: 6, null: false, default: 0, comment: 'DERIVADO: `prz_med_pond_bco − prz_med_pond_emp`. Ver a nota de precisão no cabeçalho.'
      t.decimal :diferenca_float, precision: 15, scale: 6, null: false, default: 0, comment: 'DERIVADO: `max(float_calculado − float_acordado, 0)`. Piso em zero replicado.'
      t.decimal :checagem_iof, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: IOF esperado pela alíquota vigente na data (BE-160). Base negativa produz IOF negativo — replicado.'
      t.decimal :valor_total_tarifas, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: soma dos 4 buckets.'
      t.decimal :valor_liquido, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: `vlr_bruto_final − valor_total_tarifas`. Zero é REJEITADO com 422 antes do cálculo (D-10).'

      t.decimal :recompra_percent, precision: 15, scale: 6, comment: 'DERIVADO: `100 × (recompra / valor_liquido)`.'
      t.decimal :retencao_percent, precision: 15, scale: 6, comment: 'DERIVADO.'
      t.decimal :fomento_percent, precision: 15, scale: 6, comment: 'DERIVADO.'
      t.decimal :outros_percent, precision: 15, scale: 6, comment: 'DERIVADO.'
      t.decimal :total_deducoes, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: soma das 4 deduções.'
      t.decimal :vlr_liq_recebido, precision: 15, scale: 2, null: false, default: 0, comment: 'DERIVADO: líquido menos as deduções.'

      t.decimal :taxa_desconto_nominal_desagio_advalorem_bancos, precision: 12, scale: 4, comment: 'DERIVADO. NULO quando `valor_liquido < 1` ou `tarifas_desagio < 1` — guarda de UM REAL, replicada.'
      t.decimal :taxa_desconto_nominal_despesas_bancos, precision: 12, scale: 4, comment: 'DERIVADO. NULO em 27.266 de 28.131 linhas: a guarda `tarifas_iof < 1` dispara em 97% dos borderôs.'
      t.decimal :taxa_desconto_nominal_despesas_iof_bancos, precision: 12, scale: 4, comment: 'DERIVADO. **Sem guarda** — a terceira variante não tem o `< 1` das outras duas. Assimetria replicada.'
      t.decimal :custo_efetivo_pz_med_banco, precision: 12, scale: 4, comment: 'DERIVADO: CET PM BCO. Guarda em `prz_med_pond_bco == 0`.'
      t.decimal :custo_efetivo_pz_med_banco_sem_iof, precision: 12, scale: 4,
                                                     comment: 'DERIVADO. **A guarda olha `prz_med_pond_emp` numa fórmula do BANCO** (`receivable_entry.rb:74`). Parece copy/paste e NÃO é corrigido — Q-B7, travado por golden.'
      t.decimal :taxa_desconto_nominal_desagio_advalorem_emp, precision: 12, scale: 4, comment: 'DERIVADO.'
      t.decimal :taxa_desconto_nominal_despesas_emp, precision: 12, scale: 4, comment: 'DERIVADO.'
      t.decimal :taxa_desconto_nominal_despesas_iof_emp, precision: 12, scale: 4, comment: 'DERIVADO. Sem guarda, igual à variante do banco.'
      t.decimal :custo_efetivo_pz_med_emp, precision: 12, scale: 4, comment: 'DERIVADO: CET PM EMP, 4 casas. É a chave de ordenação `cet` da lista.'
      t.decimal :custo_efetivo_pz_med_emp_sem_iof, precision: 12, scale: 4, comment: 'DERIVADO.'
      t.decimal :custo_efetivo_sem_float, precision: 12, scale: 4, comment: 'DERIVADO: CET sem float. Chave de ordenação `cetsf`.'
      t.decimal :custo_efetivo_com_float_total, precision: 12, scale: 4,
                                                comment: 'DERIVADO. Arredonda em **2** casas sobre a MESMA base que `custo_efetivo_pz_med_emp` arredonda em 4. Divergência replicada — Q-B8, travada por golden.'
      t.decimal :custo_efetivo_com_float_sem_iof, precision: 12, scale: 4, comment: 'DERIVADO. NULO quando a guarda `< 1` dispara.'

      t.decimal :multiplicador_pm_empresa, precision: 15, scale: 2, comment: 'DERIVADO: `vlr_bruto_final × prz_med_pond_emp`, truncado em 2 casas pela coluna.'
      t.decimal :multiplicador_pm_float, precision: 15, scale: 2, comment: 'DERIVADO: `vlr_bruto_final × prz_med_pond_bco`, truncado em 2 casas pela coluna.'

      t.decimal :calc_valor_liq_correto, precision: 15, scale: 2, comment: 'DERIVADO: líquido "correto" pela taxa acordada. Aproximação LINEAR (juros simples), com o expoente literal `0.0333…` — Q-B6, replicado.'
      t.decimal :dif_calc_vlr_liq, precision: 15, scale: 2, comment: 'DERIVADO: `valor_liquido − calc_valor_liq_correto`.'
      t.string :status, comment: 'DERIVADO: `ok` quando `dif_calc_vlr_liq >= 0`, `difference` quando `< 0`. **Dois** estados e nenhum terceiro — não existe baixa/liquidação/vencimento (D-19, Q-B9). BE-445: enum estável no banco, rótulo pt-BR na apresentação.'

      t.decimal :nominal_tax_check, precision: 12, scale: 4, comment: 'DERIVADO: taxa nominal apurada. Coluna de 03/2022 — nula em 18.900 linhas históricas.'
      t.decimal :nominal_tax_check_with_float, precision: 12, scale: 4, comment: 'DERIVADO: idem, com o float somado ao prazo.'

      t.integer :legacy_id, comment: 'DEC-12 — proveniência do ETL Django→Rails de 2021 (`receivable_entries.legacy_id`, 17.610 linhas preenchidas em produção). O ETL não é portado; a coluna sim (DB-157).'

      t.timestamps
    end

    add_index :receivable_entries, %i[project_id date], name: 'index_receivable_entries_on_project_and_date'
    add_index :receivable_entries, :company_id
    add_index :receivable_entries, :carrier_id
    add_index :receivable_entries, :wallet_id
    add_index :receivable_entries, :receivable_kind_id
    add_index :receivable_entries, :resource_source_id
    add_index :receivable_entries, :risk_operation_subtype_id
    add_index :receivable_entries, :user_id
    add_index :receivable_entries, :legacy_id, unique: true
    # Ordenação por CET e por líquido são as duas colunas que a lista ordena com
    # mais frequência; sem índice, 28 mil linhas ordenam em memória a cada página.
    add_index :receivable_entries, %i[project_id custo_efetivo_pz_med_emp],
              name: 'index_receivable_entries_on_project_and_cet'
    add_check_constraint :receivable_entries,
                         "status IS NULL OR status IN ('ok', 'difference')",
                         name: 'receivable_entries_status_check'

    add_foreign_key :receivable_entries, :projects
    add_foreign_key :receivable_entries, :companies
    add_foreign_key :receivable_entries, :carriers
    add_foreign_key :receivable_entries, :wallets
    add_foreign_key :receivable_entries, :receivable_kinds
    add_foreign_key :receivable_entries, :resource_sources
    add_foreign_key :receivable_entries, :users
    add_foreign_key :receivable_entries, :risk_operation_types
    add_foreign_key :receivable_entries, :risk_operation_subtypes

    # ====================================================================
    # `receivable_taxes` — a tarifa. 58.473 linhas em produção.
    # ====================================================================
    #
    # Título e classificadores ficam **denormalizados** aqui, de propósito
    # (D-B13): é o que o legado faz (`receivable_tax.rb:11-15`) e é o que
    # preserva a classificação usada no dia do lançamento quando alguém
    # reclassifica o `MovementKind` depois. Sem isso, mudar o `is_desagio` de um
    # tipo reescreveria a base do IOF de todos os borderôs históricos.
    create_table :receivable_taxes, id: :uuid, default: -> { 'gen_random_uuid()' },
                                    comment: 'Tarifa de um borderô. Título e classificadores DENORMALIZADOS na criação (D-B13): reclassificar o tipo depois não pode reescrever a base do IOF de borderô histórico.' do |t|
      t.uuid :receivable_entry_id, null: false, comment: 'Borderô dono.'
      t.uuid :movement_kind_id, null: false, comment: 'Tipo de movimentação de onde vieram título e classificadores.'
      t.decimal :value, precision: 15, scale: 2, null: false, default: 0, comment: 'Valor da tarifa.'
      t.string :title, null: false, comment: 'DENORMALIZADO do tipo no momento do lançamento.'
      t.boolean :is_advalorem, null: false, default: false, comment: 'DENORMALIZADO.'
      t.boolean :is_desagio, null: false, default: false, comment: 'DENORMALIZADO.'
      t.boolean :is_iof, null: false, default: false, comment: 'DENORMALIZADO.'
      t.integer :legacy_id, comment: 'DEC-12 — proveniência.'

      t.timestamps
    end

    # O legado lia esta tabela **4 vezes por save** (um `where` por bucket) e
    # **não tinha índice** em `receivable_entry_id`.
    add_index :receivable_taxes, :receivable_entry_id
    add_index :receivable_taxes, :movement_kind_id
    add_index :receivable_taxes, :legacy_id, unique: true
    add_foreign_key :receivable_taxes, :receivable_entries, on_delete: :cascade
    add_foreign_key :receivable_taxes, :movement_kinds

    # A operação de risco criada a partir do borderô. A coluna já existe em
    # `risk_operations` (criada na S5); a FK fecha o vínculo nos dois sentidos.
    add_foreign_key :risk_operations, :receivable_entries, column: :receivable_id
  end
end
