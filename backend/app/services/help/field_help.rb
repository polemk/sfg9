# frozen_string_literal: true

module Help
  # S12 / OPS-545 — **o mecanismo da ajuda de campo** (o tooltip do formulário).
  #
  # A fronteira desta fatia: o **mecanismo é meu**, o **texto não**. Os 91 textos
  # foram escritos sob a DEC-88 e vivem em
  # `db/seed_assets/{receivables,risk_operations,structured_operations}_help_inputs.yml`,
  # com a revisão em `.migration-ai9/help-texts-review.md`. Trocar um texto é
  # editar YAML — **sem deploy de código**, que é o ponto do formato.
  #
  # Três regras de comportamento, e as três importam:
  #
  #  1. **Chave ausente não quebra a tela.** O legado tinha 91 chaves e a tela
  #     assumia que todas existiam. Aqui, campo sem texto simplesmente não ganha
  #     tooltip.
  #  2. **`TODO:` não vira tooltip.** Quatro chaves ficaram sem texto porque o
  #     campo não tem leitor nenhum no legado e a resposta depende do usuário
  #     (`contrato`, `resource_kind_id`, e os dois `is_on_variable`). Exibir
  #     "TODO: precisa saber…" a um operador é pior que não exibir nada — é a
  #     desinformação que a DEC-88 manda evitar. Ficam **fora** da resposta.
  #  3. **O arquivo é lido uma vez.** Em produção o mapa é memoizado; em
  #     desenvolvimento recarrega, para que editar o YAML apareça sem reiniciar
  #     o servidor.
  module FieldHelp
    # Escopo = formulário. O nome é o do arquivo, sem o sufixo `_help_inputs`.
    SCOPES = %w[receivables risk_operations structured_operations].freeze

    # A marca que a DEC-88 usou para "não sei ainda, e não vou inventar".
    TODO_PREFIX = 'TODO:'

    module_function

    def asset_path(scope)
      Rails.root.join('db', 'seed_assets', "#{scope}_help_inputs.yml")
    end

    # `{ scope => { campo => texto } }`, já sem os `TODO:`.
    def all
      return build_all if Rails.env.development?

      @all ||= build_all
    end

    def for_scope(scope)
      all.fetch(scope.to_s, {})
    end

    def text_for(scope, field)
      for_scope(scope)[field.to_s]
    end

    def build_all
      SCOPES.index_with { |scope| load_scope(scope) }
    end

    def load_scope(scope)
      caminho = asset_path(scope)
      return {} unless File.exist?(caminho)

      bruto = YAML.safe_load_file(caminho) || {}
      bruto.each_with_object({}) do |(campo, texto), acc|
        valor = texto.to_s.strip
        next if valor.blank?
        # Regra 2: chave pendente não vira tooltip.
        next if valor.start_with?(TODO_PREFIX)

        acc[campo.to_s] = valor
      end
    rescue Psych::Exception => e
      # YAML quebrado não pode derrubar o formulário inteiro. Registra e devolve
      # vazio — a tela perde os tooltips daquele escopo e continua funcionando.
      Rails.logger.error("[field_help] YAML inválido em #{caminho}: #{e.message}")
      {}
    end

    # Só para diagnóstico e para o spec: as chaves que estão marcadas `TODO:`.
    def pending_keys
      SCOPES.each_with_object({}) do |scope, acc|
        caminho = asset_path(scope)
        next unless File.exist?(caminho)

        bruto = YAML.safe_load_file(caminho) || {}
        pendentes = bruto.select { |_k, v| v.to_s.strip.start_with?(TODO_PREFIX) }.keys.map(&:to_s)
        acc[scope] = pendentes if pendentes.any?
      end
    end
  end
end
