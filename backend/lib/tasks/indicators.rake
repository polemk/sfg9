# frozen_string_literal: true

# S10 / OPS-311 — a manutenção que o legado fazia colando no `rails c`.
#
# `Indicator.fix_titles` (`../sfg/app/models/indicator.rb:88-92`) era
# `Indicator.all.each(&:save)`: sem rake task, sem log, sem contagem e sem
# pré-visualização. Aqui vira tarefa com `dry_run` primeiro — o modo em que se
# olha antes de escrever — e com relatório do que mudou.
#
#   bin/rails indicators:backfill            # dry-run: só mostra
#   bin/rails indicators:backfill[apply]     # grava
namespace :indicators do
  desc 'Renormaliza título/chave dos indicadores e ressincroniza a denormalização (OPS-311). ' \
       'Dry-run por padrão; passe [apply] para gravar.'
  task :backfill, [:mode] => :environment do |_t, args|
    aplicar = args[:mode].to_s == 'apply'
    relatorio = Indicators::BackfillService.call(dry_run: !aplicar)

    puts "Indicadores lidos: #{relatorio[:scanned]}"
    puts "#{aplicar ? 'Atualizados' : 'Mudariam'}: #{relatorio[:changed]}"
    relatorio[:items].each do |item|
      puts "  - #{item[:title]} (#{item[:id]})"
      item[:changes].each { |campo, d| puts "      #{campo}: #{d[:from].inspect} → #{d[:to].inspect}" }
    end
    puts 'Nada a fazer — o cadastro já está normalizado.' if relatorio[:changed].zero?
    puts "\n(dry-run: nada foi gravado. Rode `bin/rails indicators:backfill[apply]` para aplicar.)" unless aplicar
  end
end
