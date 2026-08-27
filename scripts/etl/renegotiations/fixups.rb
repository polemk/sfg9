#!/usr/bin/env ruby
# frozen_string_literal: true

# FIXUPS PÓS-CARGA DA RENEGOCIAÇÃO — S9, tarefas 5.4 e 5.5 (**OPS-197**).
#
# Este arquivo é o **ponto de entrada nomeado** que o `tasks.md` pede
# (`scripts/etl/renegotiations/fixups.rb`). A rotina em si mora em
# `backend/app/lib/sfg/etl/fixups/renegotiations.rb`, e não aqui, por dois
# motivos concretos:
#
#  1. ela precisa dos models e dos serviços do ai9 (`AggregateService`,
#     `RenumberInstallments`, `AttachmentService`) — fora do autoload seria uma
#     segunda definição das mesmas regras, que é exatamente o que o contrato C2
#     proíbe;
#  2. lá ela é **testável** (`spec/lib/sfg/etl/renegotiation_fixups_spec.rb`),
#     e script solto no `scripts/` não entra em suíte nenhuma.
#
# Uso:
#
#     ruby scripts/etl/renegotiations/fixups.rb                  # ENSAIO (padrão)
#     ruby scripts/etl/renegotiations/fixups.rb --apply          # grava
#     ruby scripts/etl/renegotiations/fixups.rb --steps counters # só uma etapa
#     ruby scripts/etl/renegotiations/fixups.rb --after <uuid>   # retomada dura
#
# Equivalente por rake, que é o caminho do runbook:
#
#     cd backend && bundle exec rake sfg_etl:renegotiation_fixups DRY_RUN=0
#
# **O padrão é ensaio.** Ele reconcilia e relata ANTES de qualquer escrita, e o
# relatório é arquivo em `backend/tmp/etl/`, nunca saída de terminal.

require 'shellwords'

BACKEND = File.expand_path('../../../backend', __dir__)

env = { 'DRY_RUN' => '1' }
args = ARGV.dup

until args.empty?
  case (flag = args.shift)
  when '--apply' then env['DRY_RUN'] = '0'
  when '--dry-run' then env['DRY_RUN'] = '1'
  when '--steps' then env['STEPS'] = args.shift
  when '--after' then env['AFTER'] = args.shift
  when '--batch' then env['BATCH'] = args.shift
  when '--run-id' then env['RUN_ID'] = args.shift
  when '-h', '--help'
    # O cabeçalho útil começa DEPOIS do shebang e do `frozen_string_literal`.
    cabecalho = File.readlines(__FILE__).drop(2).take_while { |l| l.start_with?('#') || l.strip.empty? }
    puts cabecalho.map { |l| l.sub(/\A# ?/, '') }.join
    exit 0
  else
    abort "Opção desconhecida: #{flag}. Use --help."
  end
end

puts "== fixups da renegociação (#{env['DRY_RUN'] == '0' ? 'APLICANDO' : 'ENSAIO'})"
Dir.chdir(BACKEND) do
  exit(system(env, 'bundle', 'exec', 'rake', 'sfg_etl:renegotiation_fixups') ? 0 : 1)
end
