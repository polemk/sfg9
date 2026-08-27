# frozen_string_literal: true

# S5 / DB-230, DB-240 — **`risk_controls.risk_operation_type_id` passa a aceitar nulo.**
#
# ### O que mudou, e é medição, não opinião
#
# A migration original desta fatia (`20260826160300`) declarou a coluna
# `null: false`, assumindo o que o material da fatia dizia: que `RiskControl`
# "mudou de forma em 2022" e que **talvez** tivessem sobrado linhas antigas
# (DEC-43, P-018).
#
# O dump de produção, analisado em 26/08/2026
# (`.migration-ai9/analise-dump-producao.md` §2, consulta 5), diz o contrário:
#
# - `risk_controls` em produção tem **600 linhas**;
# - a tabela **não tem** coluna `risk_operation_type_id`, porque a migration
#   `20220611152145_change_risk_control_fields.rb` **nunca subiu**;
# - portanto **nenhuma** linha está no formato novo — todas as 600 são do
#   formato pré-2022, com as 8 colunas `limite_*`/`taxa_*`;
# - valores não-zero por família: auto-liquidáveis **457**, comissária **151**,
#   fomento **131**, intercompany **28**.
#
# Com `null: false` a carga do ETL seria **impossível**: as 600 linhas não têm
# tipo para declarar. E a entity desta mesma fatia já expunha
# `is_legacy_shape = risk_operation_type_id.nil?`, com o rótulo "Legado" na tela
# (FE-243) — ou seja, o esquema contradizia o que a própria fatia dizia esperar.
#
# ### O nulo NÃO é uma porta aberta para o aplicativo
#
# Um limite criado pela tela continua **obrigado** a ter tipo: a validação do
# model virou condicional e só dispensa a linha que veio do legado
# (`legacy_id` presente). Ver `RiskControl#type_required?`.
#
# ### O que a linha sem tipo significa
#
# Ela **não entra em nenhum agregado do painel** — todos partem de
# `RiskOperationType.active`. É de propósito, e é o que o rótulo "Legado"
# comunica: o limite existe, está preservado, e só volta a contar depois de
# convertido em linhas tipadas (`Sfg::Etl::Converters::RiskControls`, que faz a
# expansão de 4 pares por linha).
class AllowNullOperationTypeOnRiskControls < ActiveRecord::Migration[8.0]
  def up
    change_column_null :risk_controls, :risk_operation_type_id, true
    change_column_comment :risk_controls, :risk_operation_type_id,
                          from: nil,
                          to: 'Tipo do limite. NULO apenas na linha herdada do formato pré-2022 ' \
                              '(600 em produção). Limite criado pela tela é obrigado a ter tipo.'
  end

  def down
    change_column_null :risk_controls, :risk_operation_type_id, false
  end
end
