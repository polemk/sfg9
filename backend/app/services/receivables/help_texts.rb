# frozen_string_literal: true

module Receivables
  # S6 / **OPS-154** — os textos de ajuda dos campos do formulário de borderô.
  #
  # ## O que é portado: o MECANISMO. O conteúdo do legado é placeholder.
  #
  # `../sfg/config/receivables_help_inputs.yml` tem ~40 chaves e o texto de
  # todas elas é alguma variação de *"Só um teste de informações do campo…"*
  # (Q-B20). Copiar isso para a tela nova seria portar um lixo visível. O
  # mecanismo vem; o conteúdo nasce vazio, e **campo sem chave não exibe
  # indicador de ajuda** — em vez de exibir um ícone que abre um balão vazio.
  #
  # Isso é diferente da **DEC-88**, que mandou *escrever* os 91 textos da
  # central de ajuda: aqueles são conteúdo de produto e já foram escritos. Estes
  # são tooltips de campo de um formulário, e a decisão registrada para eles é
  # a **DEC-69** — portados com o placeholder. Aqui o placeholder vira **chave
  # ausente**, que é o mesmo efeito sem a mentira na tela.
  #
  # ## Servido de `Rails.cache`, não de `YAML.load_file` por render
  #
  # No legado o helper lia o arquivo do disco **a cada campo renderizado** —
  # ~40 leituras de disco por abertura do formulário.
  class HelpTexts
    CONFIG_PATH = 'config/receivables_help_inputs.yml'
    CACHE_KEY = 'receivables/help_texts/v1'

    class << self
      def all
        Rails.cache.fetch(CACHE_KEY, expires_in: 1.hour) { load_from_disk }
      end

      # `nil` quando não há texto — e é isso que faz a tela **não** desenhar o
      # indicador de ajuda.
      def for(field)
        all[field.to_s].presence
      end

      def reload!
        Rails.cache.delete(CACHE_KEY)
        all
      end

      private

      def load_from_disk
        caminho = Rails.root.join(CONFIG_PATH)
        return {} unless File.exist?(caminho)

        (YAML.safe_load_file(caminho) || {}).transform_values { |v| v.to_s.strip.presence }.compact
      rescue Psych::Exception => e
        Rails.logger.error("[Receivables::HelpTexts] YAML inválido em #{CONFIG_PATH}: #{e.message}")
        {}
      end
    end
  end
end
