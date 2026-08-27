# frozen_string_literal: true

module Availability
  # S11 — **os cinco relatórios que esta fatia declara para o cutover**
  # (`design.md` §8, tarefa 1.17).
  #
  # Não é tarefa do ETL (S14) inventar critério; é desta fatia declará-lo. Os
  # conversores (`Sfg::Etl::Converters::Availability*`) reportam anomalia
  # **linha a linha durante a carga**; este serviço responde as mesmas cinco
  # perguntas **sobre a base já carregada**, que é o que a janela de cutover
  # precisa para decidir se pode seguir.
  #
  # **Só leitura.** Nenhum método aqui grava.
  class DataReport
    def run
      [corrigidos_mais_de_uma_vez, consolidacoes_suspeitas, padroes_travados,
       duplicatas_do_unico, orfaos_de_hierarquia]
    end

    # 1. Lançamentos cujo par (`value`, `original_value`) é **inconsistente com
    #    uma única aplicação** da correção por dias úteis (D-02 / DEC-24).
    #
    #    O que isto mede e o que NÃO mede está escrito na saída, de propósito: o
    #    dado não guarda quantas vezes a correção foi reaplicada, e um relatório
    #    que afirmasse um número seria invenção.
    def corrigidos_mais_de_uma_vez
      linhas = []
      escopo = AvailabilityEntry.joins(:availability_template)
                                .where(availability_templates: { is_adjusted: true })
                                .where.not(original_value: 0)

      escopo.includes(:availability_template).find_each do |entrada|
        next if entrada.original_value == entrada.value

        esperado = (entrada.original_value.to_d * Sfg::BusinessDays.multiplier(entrada.date)).round(2)
        next if (esperado - entrada.value).abs <= BigDecimal('0.02')

        linhas << "#{entrada.id} (#{entrada.date}) base #{entrada.original_value} → gravado " \
                  "#{entrada.value}, esperado #{esperado}"
      end

      {
        titulo: '1. Correção por dias úteis aplicada mais de uma vez (D-02 / DEC-24)',
        resumo: "#{linhas.size} de #{escopo.count} lançamento(s) corrigido(s) têm valor e valor-base " \
                'inconsistentes com UMA aplicação. Quantas vezes a correção foi reaplicada o dado não ' \
                'guarda — este relatório não inventa esse número.',
        linhas: linhas
      }
    end

    # 2. Consolidação legítima × resíduo do `fix__7412`.
    #
    #    A rotina do legado fazia
    #    `p.availability_entries.where(company_id: nil).update_all(company_id: p.companies.first.id)`
    #    — ou seja, **reatribuiu consolidação à primeira empresa do projeto**.
    #    O sinal disso é um grupo (projeto, padrão, data) que tem lançamento na
    #    primeira empresa e **nenhuma linha de consolidação**, apesar de o
    #    projeto ter outras empresas.
    #
    #    É heurística, e está dito que é.
    def consolidacoes_suspeitas
      linhas = []

      Project.find_each do |project|
        primeira = Company.where(project_id: project.id).order(:created_at, :id).first
        next if primeira.nil?
        next if Company.where(project_id: project.id).count < 2

        suspeitos = AvailabilityEntry.where(project_id: project.id, company_id: primeira.id)
                                     .where.not(
                                       availability_template_id: AvailabilityEntry
                                         .where(project_id: project.id, company_id: nil)
                                         .select(:availability_template_id)
                                     )
        suspeitos.limit(200).each do |entrada|
          linhas << "#{project.name}: #{entrada.id} (#{entrada.date}) na primeira empresa " \
                    "(#{primeira.title}) sem linha de consolidação correspondente"
        end
      end

      {
        titulo: '2. Consolidação legítima × resíduo do `fix__7412` (DB-126)',
        resumo: "#{linhas.size} lançamento(s) com o padrão do resíduo. **Heurística**: a rotina do " \
                'legado reatribuiu empresa nula à PRIMEIRA empresa do projeto, e o sinal é a ausência ' \
                'da linha de consolidação para o mesmo padrão e data. Confirme por amostragem.',
        linhas: linhas
      }
    end

    # 3. Padrões travados. **Migram destravados** (DB-128) — o relatório existe
    #    para que alguém decida se a operação que travou precisa ser reexecutada.
    def padroes_travados
      travados = AvailabilityTemplate.where(is_locked: true)
      linhas = travados.limit(200).map do |t|
        "#{t.id} — #{t.title} (#{t.locked_message.presence || 'sem motivo registrado'}, " \
          "desde #{t.locked_at || 'data desconhecida'})"
      end

      {
        titulo: '3. Padrões TRAVADOS (DB-128 / D-05)',
        resumo: "#{travados.count} padrão(ões) travado(s) na base atual. No legado o `unlocked!` só " \
                'rodava no caminho feliz, então padrão travado costuma significar job morto — não ' \
                'operação em andamento.',
        linhas: linhas
      }
    end

    # 4. Duplicatas do único composto (DB-133). O índice do ai9 já as impede;
    #    este relatório serve à conferência **antes** de aplicar a restrição
    #    numa carga futura.
    def duplicatas_do_unico
      sql = <<~SQL.squish
        SELECT project_id, company_id, availability_template_id, date, COUNT(*) AS total
        FROM availability_entries
        GROUP BY project_id, company_id, availability_template_id, date
        HAVING COUNT(*) > 1
        LIMIT 200
      SQL
      grupos = AvailabilityEntry.connection.select_all(sql).to_a
      linhas = grupos.map do |g|
        "projeto #{g['project_id']} / empresa #{g['company_id'] || '(consolidação)'} / padrão " \
          "#{g['availability_template_id']} / #{g['date']}: #{g['total']} linhas"
      end

      {
        titulo: '4. Duplicatas de (projeto, empresa, padrão, data) (DB-133 / BE-131)',
        resumo: "#{linhas.size} grupo(s) duplicado(s). No legado a unicidade existia SÓ no model " \
                '(`validates_uniqueness_of`), que duas abas contornam; no ai9 é índice.',
        linhas: linhas
      }
    end

    # 5. Órfãos de hierarquia. No legado `top_parent_id` tinha default `0` e não
    #    era FK: linhas apontando para o id 0 são órfãs por construção (DB-120).
    def orfaos_de_hierarquia
      sem_pai = AvailabilityTemplate.where.not(parent_template_id: nil)
                                    .where.not(parent_template_id: AvailabilityTemplate.select(:id))
      sem_raiz = AvailabilityTemplate.where.not(parent_template_id: nil).where(top_parent_id: nil)

      linhas = sem_pai.limit(100).map { |t| "#{t.id} — pai inexistente (#{t.parent_template_id})" } +
               sem_raiz.limit(100).map { |t| "#{t.id} — sem `top_parent_id`, apesar de ter pai" }

      {
        titulo: '5. Órfãos de hierarquia (DB-120 / `top_parent_id = 0`)',
        resumo: "#{linhas.size} padrão(ões) com hierarquia quebrada. As FKs do ai9 impedem que isto " \
                'nasça aqui; o que aparecer veio da carga.',
        linhas: linhas
      }
    end
  end
end
