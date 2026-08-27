# frozen_string_literal: true

module Sfg
  module Etl
    # A ORDEM DE CARGA — versionada em `db/etl/load_order.yml` (tarefa 6.6).
    #
    # A ordem não é estética: é **dependência real**. `risk_movements` depois de
    # `risk_operations` porque o saldo é o acumulado dos movimentos; `companies`
    # depois de `projects` porque a empresa é por projeto.
    #
    # O piso são as **12 entidades de `Legacy::TABLES`** do pipeline Django→Rails de
    # 2021 (o único ETL que este sistema já viu rodar, e que **não tinha transação
    # nem idempotência** — BE-450), acrescidas do que o Safegold ganhou depois:
    # risco, estruturadas, renegociações, indicadores e disponibilidades.
    #
    # Fica em YAML e não em constante Ruby porque a ordem é **decisão de operação**:
    # ela é lida e discutida no dia do cutover por quem não vai abrir código.
    module Pipeline
      PATH = 'db/etl/load_order.yml'

      module_function

      def file = Rails.root.join(PATH)

      def entries
        raw = YAML.safe_load_file(file) || {}
        Array(raw['order'])
      end

      # Devolve as classes na ordem. Entrada cuja classe ainda não existe **não
      # derruba a carga**: vira `Missing`, que se comporta como conversor pulado e
      # aparece no relatório dizendo qual arquivo falta. É o mesmo princípio do
      # "pular com aviso" dos escritores da S20, um nível acima.
      def converters
        entries.filter_map do |entry|
          name = entry.is_a?(Hash) ? entry['converter'] : entry
          resolve(name, entry)
        end
      end

      # `{ 'geolocations' => 'DEC-92 — descartada…' }`. É a outra metade da cobertura:
      # tabela sem conversor precisa estar AQUI, com motivo escrito.
      def do_not_migrate
        raw = YAML.safe_load_file(file) || {}
        Array(raw['do_not_migrate']).to_h { |e| [e['table'], e['reason']] }
      end

      def resolve(name, entry)
        Object.const_get("Sfg::Etl::Converters::#{name}")
      rescue NameError
        Missing.build(name, entry)
      end

      # Conversor declarado no `load_order.yml` e ainda não escrito. Existe para que
      # a lacuna apareça **no relatório**, com o nome da tabela de origem e a fatia
      # dona — em vez de sumir porque ninguém acrescentou o arquivo.
      module Missing
        def self.build(name, entry)
          meta = entry.is_a?(Hash) ? entry : {}
          Class.new(Converters::Base) do
            define_singleton_method(:name) { "Sfg::Etl::Converters::#{name}" }
            define_singleton_method(:converter_name) { name.to_s.gsub(/(?<!\A)([A-Z])/, '_\1').downcase }
            define_singleton_method(:source_table) { meta.fetch('source_table', '(não declarada)') }
            define_singleton_method(:target_model) { meta.fetch('target_model', name.to_s) }
            define_singleton_method(:owner_slice) { meta['owner_slice'] }
            define_singleton_method(:requires) { [meta.fetch('target_model', name.to_s)] }
            define_singleton_method(:missing_models) { requires }
            define_singleton_method(:skip_message) do
              "conversor `app/lib/sfg/etl/converters/#{converter_name}.rb` ainda não escrito" \
                "#{owner_slice ? " — o model chega na #{owner_slice}" : ''}"
            end
          end
        end
      end
    end
  end
end
