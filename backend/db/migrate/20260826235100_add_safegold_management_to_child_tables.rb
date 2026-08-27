# frozen_string_literal: true

# S4 / **DB-051 + DB-090** — o carimbo de `has_safegold_management` nas filhas.
#
# **DEC-112.** Este bloqueio era fóssil: o razão dizia "Q-02 SEM RESPOSTA", mas
# a Q-02 do `decisions.md` é a matriz de autorização (fechada pela DEC-08). A
# pergunta certa é a **Q-17** dos mapas (F-10 / P-019), e o **DEC-30 a
# destravou**: resposta **(b) — manter o carimbo, inclusive a inconsistência**.
#
# ## O que o legado faz, e que passa a ser replicado
#
# Seis models copiam a marca do projeto num `before_validation` **sem `on:`** —
# ou seja, **em todo save**, não só na criação:
#
# | model | linha no legado | de onde copia |
# | --- | --- | --- |
# | `Company` | `company.rb:13` | `project` |
# | `AvailabilityEntry` | `availability_entry.rb:17` | `project` |
# | `ReceivableEntry` | `receivable_entry.rb:40` | `project` |
# | `Renegotiation` | `renegotiation.rb:24` | `project` |
# | `RiskControl` | `risk_control.rb:15` | **`company`** |
# | `RiskEntry` | `risk_entry.rb:32` | **`company`** |
#
# `receivable_entries` e `renegotiations` já tinham a coluna (S6 e S9). Esta
# migration cria as **quatro** que faltavam.
#
# ## O defeito é replicado de propósito (D-30)
#
# Quando a marca do projeto muda, o legado ressincroniza **só `companies`**
# (`project.rb:298-303`, um `update_all`). As outras cinco ficam com o carimbo
# velho **para sempre**. Não se deriva na leitura e não se passa a ressincronizar
# as cinco: as duas seriam melhoria não autorizada, e o DEC-30 governa.
#
# O que torna isso seguro está medido: a varredura da fonte não achou **um único
# leitor interno** — nenhum `where(has_safegold_management: …)`, nenhum scope,
# nenhum `if` de regra. As leituras são a exibição do próprio interruptor e uma
# cópia interna em `risk_control.rb:184`. O consumidor real é externo (BI /
# planilha do cliente), e é exatamente ele que quer o valor **histórico**.
class AddSafegoldManagementToChildTables < ActiveRecord::Migration[7.1]
  COMENTARIO = 'DB-090/DEC-112 — CARIMBO da marca do projeto, recopiado em todo save. ' \
               'Ressincronizado em massa APENAS em `companies` (D-30, replicado).'

  def up
    # `boolean` com default e `null: false`: no PostgreSQL 11+ isto não reescreve
    # a tabela, o que importa em `risk_entries` — 642.447 linhas em produção, a
    # maior do dump.
    add_column :companies, :has_safegold_management, :boolean, default: false, null: false,
               comment: 'DB-051/DEC-112 — cópia da marca do projeto. É a ÚNICA filha ressincronizada ' \
                        'quando a marca do projeto muda (`project.rb:298-303`).'
    add_column :availability_entries, :has_safegold_management, :boolean, default: false, null: false,
               comment: COMENTARIO
    add_column :risk_controls, :has_safegold_management, :boolean, default: false, null: false,
               comment: "#{COMENTARIO} Copiada da EMPRESA, não do projeto (`risk_control.rb:15`)."
    add_column :risk_entries, :has_safegold_management, :boolean, default: false, null: false,
               comment: "#{COMENTARIO} Copiada da EMPRESA, não do projeto (`risk_entry.rb:32`)."

    # Backfill: o carimbo inicial é o valor de hoje. Um `UPDATE … FROM` por
    # tabela, não um `find_each` — `risk_entries` sozinha inviabilizaria o
    # segundo.
    execute(<<~SQL.squish)
      UPDATE companies c SET has_safegold_management = COALESCE(p.has_safegold_management, false)
        FROM projects p WHERE p.id = c.project_id
    SQL
    execute(<<~SQL.squish)
      UPDATE availability_entries a SET has_safegold_management = COALESCE(p.has_safegold_management, false)
        FROM projects p WHERE p.id = a.project_id
    SQL
    # As duas de risco copiam da EMPRESA, que acabou de ser carimbada acima.
    execute(<<~SQL.squish)
      UPDATE risk_controls r SET has_safegold_management = COALESCE(c.has_safegold_management, false)
        FROM companies c WHERE c.id = r.company_id
    SQL
    execute(<<~SQL.squish)
      UPDATE risk_entries r SET has_safegold_management = COALESCE(c.has_safegold_management, false)
        FROM companies c WHERE c.id = r.company_id
    SQL
  end

  def down
    remove_column :risk_entries, :has_safegold_management
    remove_column :risk_controls, :has_safegold_management
    remove_column :availability_entries, :has_safegold_management
    remove_column :companies, :has_safegold_management
  end
end
