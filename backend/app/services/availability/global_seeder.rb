# frozen_string_literal: true

module Availability
  # S11 / OPS-081, OPS-120, OPS-121 — **do catálogo global para o projeto**.
  #
  # Dois caminhos, **um código**: semear o projeto inteiro (OPS-081/OPS-120) e
  # inserir um padrão novo em todos os projetos (OPS-121). No legado eram dois
  # métodos separados em `Project` — `create_templates_from_global` e
  # `create_template_from_global` —, e eles **divergiam**:
  #
  # | Atributo | `create_templates_from_global` | `create_template_from_global` |
  # | -------- | ------------------------------ | ----------------------------- |
  # | `is_mandatory` | copiado do global | **forçado a `1`** (`project.rb:359`) |
  # | `is_adjusted` | **não copiado** — todo padrão nascia não ajustado, mesmo derivando de global ajustado | **não copiado** |
  #
  # O resultado: dependendo de o padrão ter vindo da semeadura ou da
  # propagação, o mesmo global produzia padrões de projeto **diferentes**. Aqui
  # os atributos são copiados **fielmente**, pelos dois caminhos, pelo mesmo
  # `copy_attributes`.
  #
  # **`is_adjusted` copiado muda número exibido** (o padrão passa a ser
  # corrigido por dias úteis onde antes não era). Está registrado no
  # `improvements-log.md` para o QA do Phase 4 não ler como regressão.
  class GlobalSeeder
    class << self
      # Todos os globais para um projeto. **Idempotente e atômico**: rodar duas
      # vezes não duplica nada, e uma falha no meio não deixa o projeto
      # silenciosamente incompleto (que é o que o legado fazia — cada
      # `ProjectAvailabilityTemplate.create` era independente e o `delegate`
      # padrão só imprimia no stdout).
      def seed_project!(project, actor: nil, progress: nil)
        globais = GlobalAvailabilityTemplate.in_tree_order.to_a
        total = globais.size
        criados = 0

        ProjectAvailabilityTemplate.transaction do
          mapa = existing_map(project)

          globais.each_with_index do |global, indice|
            criados += 1 if upsert_from_global(project, global, mapa, actor: actor)
            progress&.call(indice + 1, total)
          end
        end

        TreeService.reorder_project!(project)
        { created: criados, total: total }
      end

      # Um global para um projeto — o caminho da propagação (OPS-121).
      def insert_into_project!(project, global, actor: nil)
        criado = false

        ProjectAvailabilityTemplate.transaction do
          mapa = existing_map(project)
          # O pai precisa existir antes do filho. Se o ancestral ainda não foi
          # trazido para este projeto, ele vem junto — senão a inserção falharia
          # com `parent_template_id` nulo e o padrão viraria raiz por engano.
          ancestors_of(global).each { |ancestral| upsert_from_global(project, ancestral, mapa, actor: actor) }
          criado = upsert_from_global(project, global, mapa, actor: actor)
        end

        TreeService.reorder_project!(project)
        criado
      end

      # Sincroniza `is_adjusted`/`is_cumulative` do global para os derivados
      # (DC-31). Hoje o legado não propaga nada disso, e o catálogo mente sobre
      # os padrões que gerou.
      def sync_attributes!(global)
        ProjectAvailabilityTemplate.where(global_availability_template_id: global.id)
                                   .update_all(is_adjusted: global.is_adjusted,
                                               is_cumulative: global.is_cumulative,
                                               updated_at: Time.current)
      end

      private

      def existing_map(project)
        ProjectAvailabilityTemplate.for_project(project)
                                   .where.not(global_availability_template_id: nil)
                                   .pluck(:global_availability_template_id, :id).to_h
      end

      def ancestors_of(global)
        cadeia = []
        atual = global.parent_template
        while atual
          cadeia.unshift(atual)
          atual = atual.parent_template
        end
        cadeia
      end

      # Devolve `true` quando criou. **Idempotência**: já existe → não recria e
      # não sobrescreve o que o projeto customizou (título, obrigatoriedade).
      def upsert_from_global(project, global, mapa, actor: nil)
        return false if mapa.key?(global.id)

        pai_id = global.parent_template_id.present? ? mapa[global.parent_template_id] : nil

        registro = ProjectAvailabilityTemplate.new(copy_attributes(global).merge(
                                                     project_id: project.id,
                                                     global_availability_template_id: global.id,
                                                     parent_template_id: pai_id,
                                                     user_id: actor&.id || global.user_id
                                                   ))
        TreeService.assign_next_position!(registro)
        registro.save!
        mapa[global.id] = registro.id
        true
      end

      # **Cópia fiel** — os oito atributos do padrão, sem forçar nenhum.
      def copy_attributes(global)
        {
          title: global.title,
          operation_type: global.operation_type,
          deadline_type: global.deadline_type,
          is_global: true,
          is_mandatory: global.is_mandatory,
          is_active: global.is_active,
          is_cumulative: global.is_cumulative,
          # O que o legado NÃO copiava, nos dois caminhos.
          is_adjusted: global.is_adjusted,
          default_position: global.default_position
        }
      end
    end
  end
end
