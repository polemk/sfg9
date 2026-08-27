# frozen_string_literal: true

module Structured
  # S8 / **OPS-284** — os textos de ajuda dos campos do formulário de operação
  # estruturada.
  #
  # Reusa o mecanismo que a S6 entregou em `Receivables::HelpTexts`, com o mesmo
  # contrato: `Rails.cache`, chave ausente = **sem indicador de ajuda**, arquivo
  # ausente = `{}` em vez de 500.
  #
  # ## Os dois defeitos que morrem aqui
  #
  # 1. **`YAML.load_file` a cada campo renderizado.** O helper do legado lia o
  #    arquivo do disco uma vez **por campo** — 13 leituras por abertura do
  #    formulário.
  # 2. **Arquivo ausente = 500.** Se o YAML sumisse do deploy, o formulário
  #    inteiro deixava de abrir. Aqui a ausência é `{}` e a tela sobe sem
  #    tooltip nenhum.
  #
  # ## O conteúdo nasce vazio, e isso é decisão (Q-R9)
  #
  # As **13** chaves do legado têm todas o **mesmo** texto placeholder — "Só um
  # teste de informações do campo pra descrever para que serve cada campo".
  # Portar o mecanismo é obrigação; portar o placeholder seria portar lixo
  # visível. O conteúdo real é do negócio.
  class HelpTexts
    CONFIG_PATH = 'config/structured_operations_help_inputs.yml'
    CACHE_KEY = 'structured/help_texts/v1'

    class << self
      def all
        Rails.cache.fetch(CACHE_KEY, expires_in: 1.hour) { load_from_disk }
      end

      # `nil` quando não há texto — é isso que faz a tela **não** desenhar o
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
        Rails.logger.error("[Structured::HelpTexts] YAML inválido em #{CONFIG_PATH}: #{e.message}")
        {}
      end
    end
  end
end
