# frozen_string_literal: true

module Api
  module Entities
    # S11 / BE-133, BE-140, BE-141, FE-108, FE-140, FE-146 — **o padrão de
    # disponibilidade**, serializado.
    #
    # Serve às duas classes (STI): catálogo global e padrão de projeto. É o
    # BE-133 — no legado o detalhe chamava `@availability_template.projects`,
    # associação que **não existe** em nenhuma das duas, e a tela morria com
    # `NoMethodError` sempre que alguém abria o detalhe de um padrão de projeto.
    #
    # **Nenhum padrão de outro projeto viaja neste payload** (FE-110, FE-139,
    # FE-147, FE-148). O legado embutia `AvailabilityTemplate.all` — todos os
    # padrões de **todos** os projetos — num atributo `data-templates` do HTML,
    # e o filtro de "níveis derivados do pai" rodava sobre esse JSON global.
    class AvailabilityTemplate < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :type, documentation: { type: 'String', desc: 'GlobalAvailabilityTemplate | ProjectAvailabilityTemplate' }
      expose :project_id, documentation: { type: 'String', desc: 'Nulo no catálogo global. NUNCA aceito no corpo (C1)' }
      expose :global_availability_template_id

      expose :title
      expose :level, documentation: { type: 'Integer', desc: '1..3 — derivado do pai' }
      expose :position, documentation: { type: 'Integer', desc: 'Posição inteira entre os irmãos' }
      expose :position_path, documentation: { type: 'String', desc: '"1.2.3" — derivado da sort_key' } do |t|
        t.position_path
      end
      expose :sort_key
      expose :default_position
      expose :parent_template_id
      expose :top_parent_id

      expose :operation_type
      # **FE-129 — a natureza da operação vai LEGÍVEL.** O legado exibia o
      # código `C`/`D` cru na tela.
      expose :operation_type_label do |t|
        t.operation_type_label
      end
      expose :deadline_type
      expose :deadline_type_label do |t|
        t.deadline_type_label
      end

      expose :is_global
      expose :is_mandatory
      expose :is_active
      expose :is_cumulative
      expose :is_adjusted
      expose :should_insert_on_existing_projects

      # FE-146 / DC-36 — o estado visual: **motivo, autor e data** do bloqueio.
      # O legado renderizava `data-deletable` sem nunca lê-lo e tinha estilos
      # `.project_availability_completed` **sem emissor** — sem coluna, sem
      # controller, sem o que preservar. O estado "concluído" não é portado.
      expose :is_locked
      expose :locked_message
      expose :locked_at
      expose :locked_by_name do |t|
        t.locked_by&.name
      end

      expose :job_state
      expose :job_progress

      expose :scope_label, documentation: { type: 'String', desc: 'Global | Específico' } do |t|
        t.respond_to?(:scope_label) ? t.scope_label : nil
      end

      expose :has_children do |t|
        t.has_children?
      end

      # FE-112 / DC-20 — a tela precisa saber se a remoção vai ser aceita
      # **antes** de oferecer o botão, e o critério é o **mesmo** do servidor.
      expose :deletable do |t|
        t.respond_to?(:deletable?) ? t.deletable? : nil
      end

      expose :created_at
      expose :updated_at
    end
  end
end
