# frozen_string_literal: true

module Indicators
  # S10 / OPS-311 — **o sucessor de `Indicator.fix_titles`**.
  #
  # No legado (`../sfg/app/models/indicator.rb:88-92`) isto era:
  #
  #     def self.fix_titles
  #       Indicator.all.each { |ind| ind.save }
  #     end
  #
  # Um método de classe, sem rake task, sem log, sem contagem, sem lote e sem
  # ninguém saber quando rodou. Ele existe porque re-salvar o indicador dispara
  # os dois `before_validation` (normalização do título, derivação da chave) e o
  # `after_save` de propagação — ou seja: **é o remendo para o dia em que a
  # regra de normalização mudou e o dado antigo ficou para trás**, e para o dia
  # em que a denormalização das entries saiu de sincronia.
  #
  # Aqui ele continua fazendo exatamente isso, e ganha o que faltava:
  #
  # - **é idempotente e diz por escrito**: rodar duas vezes seguidas não muda
  #   nada na segunda, e o relatório mostra isso (`changed: 0`);
  # - **tem `dry_run`**, que é o modo em que se olha antes de escrever;
  # - **loga** quantos foram lidos, quantos mudaram e quais;
  # - **processa em lote** (`find_each`), em vez de carregar a tabela inteira;
  # - **a propagação em massa vira job** quando o indicador é grande, pelo mesmo
  #   corte de `Indicator::PROPAGATION_INLINE_LIMIT`.
  #
  # Não é migração de dados: é manutenção, e por isso mora aqui e não em
  # `db/migrate`. O ETL da S14 é outro caminho.
  class BackfillService
    class << self
      # `dry_run: true` não grava nada — apenas reporta o que mudaria.
      def call(dry_run: false, logger: Rails.logger)
        lidos = 0
        alterados = []

        Indicator.unscoped.find_each(batch_size: 200) do |indicator|
          lidos += 1
          diferencas = pending_changes(indicator)
          next if diferencas.empty?

          alterados << { id: indicator.id, title: indicator.title, changes: diferencas }
          indicator.save! unless dry_run
        end

        relatorio = { scanned: lidos, changed: alterados.size, items: alterados, dry_run: dry_run }
        titulos = alterados.empty? ? '' : ": #{alterados.map { |a| a[:title] }.join(', ')}"
        logger.info(
          "[Indicators::BackfillService] #{lidos} indicador(es) lidos, #{alterados.size} " \
          "#{dry_run ? 'mudariam' : 'atualizados'}#{titulos}"
        )
        relatorio
      end

      private

      # O que os callbacks fariam se este registro fosse salvo agora. Calculado
      # numa cópia, para que o `dry_run` não tenha um caminho de código próprio
      # — dois caminhos é como o dry-run passa a mentir.
      def pending_changes(indicator)
        copia = indicator.dup
        copia.id = indicator.id
        copia.valid?

        %i[title key value_type].each_with_object({}) do |campo, acc|
          atual = indicator.public_send(campo)
          futuro = copia.public_send(campo)
          acc[campo] = { from: atual, to: futuro } if atual != futuro
        end
      end
    end
  end
end
