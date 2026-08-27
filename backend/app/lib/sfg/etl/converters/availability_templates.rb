# frozen_string_literal: true

module Sfg
  module Etl
    module Converters
      # `availability_templates` (legado) -> `AvailabilityTemplate` (ai9). **S11.**
      #
      # ## UMA tabela, não três
      #
      # O `load_order.yml` declarava três conversores —
      # `availability_templates`, `global_availability_templates` e
      # `project_availability_templates`. **As duas últimas tabelas não existem
      # no legado.** `GlobalAvailabilityTemplate` e `ProjectAvailabilityTemplate`
      # são STI sobre a MESMA tabela `availability_templates`, que tem a coluna
      # `type` (`20210420180734_create_availability_templates.rb:6`). Carregar
      # três produziria dois passos vazios e um relatório mentindo sobre
      # cobertura. Este conversor é um só, e a coluna `type` decide a classe.
      #
      # ## A hierarquia é DIFERIDA
      #
      # `parent_template_id` e `top_parent_id` apontam para a própria tabela, e o
      # pai pode vir depois do filho na ordem de leitura. Os dois entram em
      # `deferred`: o motor faz um segundo passo ao fim da carga, resolvendo pelo
      # de-para. É o mesmo mecanismo que resolve o ciclo
      # `users.default_project_id`.
      #
      # ## `sort_key` vem da `position` string do legado, zero-padded
      #
      # O legado guarda `"1.2.3"` numa coluna de texto e ordena por ela — daí a
      # ordenação lexicográfica em que "10" vem antes de "2" (DB-131). A carga
      # traduz cada segmento para quatro dígitos (`"0001.0002.0003"`), o que
      # **preserva a hierarquia** e **corrige a ordem**. Quando a `position` do
      # legado estiver vazia ou malformada, a chave é reconstruída pelo
      # `Availability::TreeService.renumber_tree!` depois da carga — e a rake
      # `sfg:availability:report` diz quantas linhas caíram nesse caso.
      #
      # ## Três coisas que NÃO são copiadas, cada uma por um motivo
      #
      # | Coluna do legado | O que acontece |
      # | ---------------- | -------------- |
      # | `is_locked`, `locked_at`, `locked_message` | **Migram DESBLOQUEADAS** (DB-128). Não se importa um estado que só existe porque um job morreu em 2019 e o `unlocked!` do legado nunca rodava fora do caminho feliz (D-05). As linhas travadas saem no relatório |
      # | `job_id` | Era FK para `delayed_jobs`, tabela que o ai9 não tem (DB-460). Não há para onde apontar |
      # | `job_state` / `job_report` | Texto livre em pt-BR (`"Concluido"`, sem acento) e **array Ruby numa coluna de texto**. O estado vira `enum` de conjunto fechado; o que não mapear vira `nil`, porque "não sei" é diferente de "pendente" |
      class AvailabilityTemplates < Base
        def self.source_table = 'availability_templates'
        def self.target_model = 'AvailabilityTemplate'
        def self.requires = %w[AvailabilityTemplate Project]
        def self.owner_slice = 'S11'

        def self.references = {
          'project_id' => 'projects',
          'user_id' => 'livetat_auth_users'
        }

        # Auto-referências: só resolvem no segundo passo, quando a tabela inteira
        # já tem de-para.
        def self.deferred = {
          'parent_template_id' => %w[availability_templates parent_template_id],
          'top_parent_id' => %w[availability_templates top_parent_id],
          'global_availability_template_id' => %w[availability_templates global_availability_template_id]
        }

        def self.booleans = %w[is_global is_mandatory is_active is_cumulative is_adjusted
                               should_insert_on_existing_projects is_locked is_upper_level]

        def self.uniques = [%w[project_id parent_template_id title]]

        # `sort_key` e `level` são derivados da `position` do legado, e
        # `is_locked` é forçado a `false`: a reconciliação não deve acusar
        # divergência nas três.
        def self.derived = %w[sort_key level position is_locked]

        # `pending` não existe no legado; `Pendente` significa "enfileirado num
        # Delayed::Job que já não existe", e por isso vira `nil`.
        JOB_STATES = {
          'Concluido' => 'done',
          'Concluído' => 'done',
          'Falhou' => 'failed'
        }.freeze

        SEGMENT_WIDTH = 4

        def convert(row)
          {
            type: sti_class(row),
            project_id: ref('projects', row['project_id']),
            title: row['title'],
            operation_type: operation_type(row),
            deadline_type: deadline_type(row),

            level: level_of(row),
            position: position_of(row),
            sort_key: sort_key_of(row),
            default_position: row['default_position'],

            is_global: truthy(row['is_global']),
            is_mandatory: truthy(row['is_mandatory']),
            is_active: truthy(row['is_active']),
            is_cumulative: truthy(row['is_cumulative']),
            is_adjusted: truthy(row['is_adjusted']),
            should_insert_on_existing_projects: truthy(row['should_insert_on_existing_projects']),

            # DB-128 — **desbloqueado, sempre**.
            is_locked: false,
            locked_at: nil,
            locked_message: nil,
            locked_by_id: nil,

            job_state: JOB_STATES[row['job_state'].to_s.strip],
            job_progress: nil,
            job_report: legacy_job_report(row),

            user_id: ref('livetat_auth_users', row['user_id']),
            legacy_id: row['id'],
            created_at: Values.to_utc(row['created_at']).value,
            updated_at: Values.to_utc(row['updated_at']).value
          }
        end

        # Os cinco relatórios que o `design.md` §8 desta fatia exige do ETL —
        # a parte que cabe aos padrões. Os dois restantes estão em
        # `AvailabilityEntries`.
        def anomalies(row)
          linhas = []

          if truthy(row['is_locked'])
            linhas << Values.anomaly_line(
              'padrão TRAVADO no legado — migra DESBLOQUEADO (DB-128, D-05). Confira se a operação ' \
              'que o travou precisa ser reexecutada',
              'availability_templates', row['id'], 'is_locked', row['locked_message']
            )
          end

          if row['top_parent_id'].to_i.zero? && row['top_parent_id'].present? &&
             row['parent_template_id'].present?
            linhas << Values.anomaly_line(
              'órfão apontando para `top_parent_id = 0` — o default do legado não era FK (DB-120). ' \
              'A raiz é reconstruída pela cadeia de pais',
              'availability_templates', row['id'], 'top_parent_id', row['top_parent_id']
            )
          end

          if sort_key_of(row).blank?
            linhas << Values.anomaly_line(
              '`position` vazia ou malformada — a chave de ordem será reconstruída por ' \
              '`Availability::TreeService.renumber_tree!` depois da carga',
              'availability_templates', row['id'], 'position', row['position']
            )
          end

          unless AvailabilityTemplate::OPERATION_TYPES.key?(row['operation_type'].to_s)
            linhas << Values.anomaly_line(
              'natureza de operação fora de C/D/S/M — no legado qualquer código desconhecido era ' \
              'somado como CRÉDITO (DC-28); o ai9 recusa a linha',
              'availability_templates', row['id'], 'operation_type', row['operation_type']
            )
          end

          linhas
        end

        private

        # A coluna `type` do legado já traz a classe. Vazia — o que acontece em
        # linha antiga — decide-se por `project_id`, que é o discriminante real.
        def sti_class(row)
          declarado = row['type'].to_s.strip
          return declarado if %w[GlobalAvailabilityTemplate ProjectAvailabilityTemplate].include?(declarado)

          row['project_id'].present? ? 'ProjectAvailabilityTemplate' : 'GlobalAvailabilityTemplate'
        end

        # `max_level` do legado é 1, 2 ou 3 — o mesmo que o `level` do ai9. Sem
        # ele (0 é o default da migration), a profundidade sai da `position`.
        def level_of(row)
          nivel = row['max_level'].to_i
          return nivel if nivel.between?(1, AvailabilityTemplate::MAX_LEVEL)

          segmentos = row['position'].to_s.split('.').size
          segmentos.between?(1, AvailabilityTemplate::MAX_LEVEL) ? segmentos : 1
        end

        # A posição DENTRO do grupo de irmãos é o último segmento do caminho.
        def position_of(row)
          ultimo = row['position'].to_s.split('.').last.to_i
          return ultimo if ultimo.positive?

          case level_of(row)
          when 1 then row['numeric_first_level'].to_i
          when 2 then row['numeric_second_level'].to_i
          else row['numeric_third_level'].to_i
          end.then { |n| n.positive? ? n : 1 }
        end

        def sort_key_of(row)
          segmentos = row['position'].to_s.split('.').map(&:to_i)
          return nil if segmentos.empty? || segmentos.any?(&:negative?)
          return nil if segmentos.all?(&:zero?)

          segmentos.map { |n| format("%0#{SEGMENT_WIDTH}d", n) }.join('.')
        end

        def operation_type(row)
          codigo = row['operation_type'].to_s.strip
          AvailabilityTemplate::OPERATION_TYPES.key?(codigo) ? codigo : 'C'
        end

        def deadline_type(row)
          codigo = row['deadline_type'].to_s.strip
          AvailabilityTemplate::DEADLINE_TYPES.key?(codigo) ? codigo : 'CP'
        end

        # O `job_report` do legado é um **array Ruby serializado numa coluna de
        # texto**. Não se tenta interpretá-lo: ele entra como texto bruto dentro
        # de um `jsonb` estruturado, marcado como origem legada, para que o valor
        # continue auditável sem fingir que virou objeto.
        def legacy_job_report(row)
          bruto = row['job_report'].to_s.strip
          return nil if bruto.empty?

          { source: 'legacy', raw: bruto, legacy_job_state: row['job_state'] }
        end

        def truthy(value)
          ActiveModel::Type::Boolean.new.cast(value) == true || value.to_i == 1
        end
      end
    end
  end
end
