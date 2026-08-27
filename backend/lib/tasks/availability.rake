# frozen_string_literal: true

# S11 / OPS-129, DB-127, DB-133, e o contrato do `design.md` §8 com a S14.
#
# ## O que esta rake substitui, e por que ela nasce diferente
#
# No legado havia `AvailabilityTemplate.destroy_existing`:
#
#     def self.destroy_existing
#       AvailabilityEntry.destroy_all
#       ProjectAvailabilityTemplate.destroy_all
#       GlobalAvailabilityTemplate.destroy_all
#     end
#
# Três linhas, **sem uma única guarda**, que apagam todos os lançamentos
# financeiros e todos os padrões de todos os projetos. Chamável do console por
# quem tivesse acesso, sem confirmação, sem pré-visualização, sem trilha.
#
# **Aqui não existe tarefa destrutiva.** As cinco tarefas abaixo são de
# **leitura e reconciliação**; a única que grava (`reconcile_virtual_values`)
# exige `APPLY=1` explícito, roda em transação e registra por `paper_trail`
# (DEC-59) — e mesmo assim só reescreve um valor **derivado**, nunca um valor
# digitado.
namespace :sfg do
  namespace :availability do
    desc 'Os CINCO relatórios que o cutover de disponibilidades exige (design.md §8). Só leitura.'
    task report: :environment do
      relatorio = Availability::DataReport.new
      relatorio.run.each do |secao|
        puts "\n== #{secao[:titulo]} =="
        puts "   #{secao[:resumo]}"
        secao[:linhas].first(25).each { |linha| puts "   - #{linha}" }
        puts "   … e mais #{secao[:linhas].size - 25} linha(s)" if secao[:linhas].size > 25
      end
      puts "\nNenhuma linha foi alterada — esta tarefa é de leitura."
    end

    desc 'DB-127 — reconcilia `virtual_value` com o recalculado. Só reporta; APPLY=1 grava.'
    task reconcile_virtual_values: :environment do
      aplicar = ENV['APPLY'].to_s == '1'
      divergentes = []

      AvailabilityEntry.includes(:availability_template).find_each do |entrada|
        gravado = entrada.virtual_value
        entrada.recompute_virtual_value
        recalculado = entrada.virtual_value
        next if (gravado - recalculado).abs <= BigDecimal('0.01')

        divergentes << { id: entrada.id, date: entrada.date, gravado: gravado, recalculado: recalculado }
        entrada.restore_attributes unless aplicar
      end

      puts "#{divergentes.size} lançamento(s) com `virtual_value` divergente do recalculado."
      divergentes.first(25).each do |d|
        puts "   - #{d[:id]} (#{d[:date]}): gravado #{d[:gravado]} × recalculado #{d[:recalculado]}"
      end

      if aplicar
        AvailabilityEntry.transaction do
          divergentes.each { |d| AvailabilityEntry.find(d[:id]).recompute_and_save! }
        end
        puts "\n#{divergentes.size} lançamento(s) reconciliado(s). `value` e `original_value` NÃO foram tocados."
      else
        puts "\nNada foi gravado. Rode com APPLY=1 para aplicar."
      end
    end

    desc 'Renumera a árvore de padrões de um projeto (PROJECT_ID=…) ou do catálogo global.'
    task renumber: :environment do
      if ENV['PROJECT_ID'].present?
        project = Project.find(ENV.fetch('PROJECT_ID'))
        total = Availability::TreeService.reorder_project!(project)
        puts "#{total} padrão(ões) renumerado(s) no projeto #{project.name}."
      else
        total = Availability::TreeService.reorder_global!
        puts "#{total} padrão(ões) renumerado(s) no catálogo global."
      end
    end
  end
end
