# frozen_string_literal: true

module Availability
  # S11 / DB-085, DB-131, BE-116, BE-137, BE-138 — **a numeração e a ordem da
  # árvore de padrões**, num lugar só.
  #
  # ## O que este serviço substitui
  #
  # No legado, a mesma lógica existia **quatro vezes**: `reorder_all!` e
  # `set_new_position!` em `GlobalAvailabilityTemplate` (≈300 linhas),
  # os mesmos dois em `ProjectAvailabilityTemplate` (≈310 linhas) e
  # `Project#reorder_project_availability_templates!`. As quatro cópias
  # divergiam entre si e todas tinham os mesmos três problemas:
  #
  # 1. **Custo quadrático.** Os três `import` finais rodavam **dentro** do laço
  #    de 1º nível (`project.rb:266-268`): com N padrões de 1º nível, cada um
  #    reimportava a lista inteira acumulada — N × N gravações.
  # 2. **Ordenação lexicográfica.** `position` era string e a ordem saía
  #    `1, 10, 11, 12, 2, 3…`. Aqui `sort_key` é zero-padded, então
  #    `"0002" < "0010"` e 12 irmãos ordenam `1,2,…,10,11,12`.
  # 3. **Nível derivado com OR bit a bit** (` |= `): um filho de nível 2
  #    herdando de 5 virava 7. Aqui é `parent.level + 1`, no model.
  #
  # ## Concorrência (BE-137)
  #
  # `max(position) + 1` lido e gravado por duas requisições ao mesmo tempo
  # produz duas linhas na mesma posição. A atribuição roda dentro de um
  # **advisory lock transacional do Postgres**, com chave derivada do grupo de
  # irmãos — dois `create` no mesmo grupo serializam; em grupos diferentes
  # correm juntos.
  class TreeService
    SEGMENT_WIDTH = AvailabilityTemplate::SORT_SEGMENT_WIDTH

    class << self
      def pad(number)
        format("%0#{SEGMENT_WIDTH}d", number.to_i)
      end

      # A posição seguinte no grupo de irmãos, atribuída sob advisory lock.
      # Devolve o próprio `template`, já com `position` e `sort_key`.
      def assign_next_position!(template)
        AvailabilityTemplate.transaction do
          lock_sibling_group!(template)
          ultima = sibling_scope(template).maximum(:position).to_i
          template.position = ultima + 1
          template.sort_key = build_sort_key(template)
          template
        end
      end

      # Recalcula `sort_key` a partir do pai. Chamado sempre que a posição ou o
      # pai mudam.
      def build_sort_key(template)
        prefixo = if template.parent_template_id.present?
                    pai = template.parent_template || AvailabilityTemplate.find_by(id: template.parent_template_id)
                    pai&.sort_key
                  end

        [prefixo, pad(template.position)].compact.join('.')
      end

      # **BE-138 — mover um padrão dentro do próprio grupo de irmãos.**
      #
      # O legado permitia qualquer inteiro e "corrigia" as posições vizinhas com
      # oito ramos de `if/elsif` diferentes por nível — dois dos quais
      # inalcançáveis (`elsif x <= position` seguido de `elsif x == position`).
      # Aqui o movimento inválido é **recusado no servidor** e o rearranjo é uma
      # única passada.
      #
      # Devolve `[ok, mensagem]`.
      def move!(template, position)
        destino = position.to_i
        irmaos = sibling_scope(template, include_self: true).order(:position, :id).to_a
        unless destino.between?(1, irmaos.size)
          return [false, "Posição inválida: informe um número entre 1 e #{irmaos.size}."]
        end

        AvailabilityTemplate.transaction do
          lock_sibling_group!(template)
          reordenados = irmaos.reject { |t| t.id == template.id }
          reordenados.insert(destino - 1, template)
          apply_positions!(reordenados)
        end

        [true, nil]
      end

      # **Renumeração contígua da árvore de um projeto** (BE-116).
      #
      # Substitui `Project#reorder_project_availability_templates!`. Uma consulta
      # traz a árvore inteira; a renumeração acontece em memória e volta em
      # `update_all` por posição — custo **linear**, não quadrático.
      #
      # Renumera os padrões **ativos** (`active_ignore_lock`), como o legado.
      # Divergência declarada: o legado usava `active` (que exclui bloqueado)
      # nas raízes e `active_ignore_lock` nos filhos, então um padrão bloqueado
      # por job em curso sumia da numeração de raiz e voltava depois. Aqui o
      # critério é **um só** — bloqueio é estado transitório de operação, não de
      # ordenação.
      def reorder_project!(project)
        renumber_tree!(ProjectAvailabilityTemplate.where(project_id: project_id_of(project)).active_ignore_lock)
      end

      # A mesma renumeração para o catálogo global.
      def reorder_global!
        renumber_tree!(GlobalAvailabilityTemplate.active_ignore_lock)
      end

      # Renumera um conjunto que já é uma árvore fechada.
      def renumber_tree!(scope)
        nos = scope.select(:id, :parent_template_id, :position, :sort_key, :level).order(:position, :created_at, :id).to_a
        return 0 if nos.empty?

        por_pai = nos.group_by(&:parent_template_id)
        atualizacoes = {}

        percorrer = lambda do |pai_id, prefixo|
          (por_pai[pai_id] || []).each_with_index do |no, indice|
            posicao = indice + 1
            chave = [prefixo, pad(posicao)].compact.join('.')
            atualizacoes[no.id] = { position: posicao, sort_key: chave }
            percorrer.call(no.id, chave)
          end
        end

        percorrer.call(nil, nil)

        aplicar_em_lote!(atualizacoes)
        atualizacoes.size
      end

      # Reescreve `sort_key` da subárvore de um nó — usado quando o pai muda de
      # posição e os descendentes precisam acompanhar.
      def rebuild_subtree_sort_keys!(template)
        ids = AvailabilityTemplate.subtree_ids_for(template.id)
        return if ids.blank?

        nos = AvailabilityTemplate.where(id: ids).select(:id, :parent_template_id, :position).to_a
        por_pai = nos.group_by(&:parent_template_id)
        atualizacoes = {}

        percorrer = lambda do |no, prefixo|
          chave = [prefixo, pad(no.position)].compact.join('.')
          atualizacoes[no.id] = { sort_key: chave }
          (por_pai[no.id] || []).sort_by(&:position).each { |filho| percorrer.call(filho, chave) }
        end

        raiz = nos.find { |n| n.id == template.id }
        pai_prefixo = template.parent_template&.sort_key
        percorrer.call(raiz, pai_prefixo) if raiz

        aplicar_em_lote!(atualizacoes)
      end

      # --- Peças internas ------------------------------------------------

      # Os irmãos: mesmo tipo (STI), mesmo projeto, mesmo pai.
      def sibling_scope(template, include_self: false)
        escopo = AvailabilityTemplate.where(type: template.type,
                                            project_id: template.project_id,
                                            parent_template_id: template.parent_template_id)
        escopo = escopo.where.not(id: template.id) if !include_self && template.persisted?
        escopo
      end

      private

      def project_id_of(project)
        project.respond_to?(:id) ? project.id : project
      end

      # Advisory lock **transacional**: some sozinho no commit ou no rollback.
      # A chave é textual e determinística — dois processos com o mesmo grupo de
      # irmãos calculam o mesmo número.
      def lock_sibling_group!(template)
        chave = [template.type, template.project_id, template.parent_template_id].map(&:to_s).join('/')
        AvailabilityTemplate.connection.execute(
          AvailabilityTemplate.sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', chave])
        )
      end

      def apply_positions!(ordenados)
        atualizacoes = {}
        ordenados.each_with_index do |no, indice|
          posicao = indice + 1
          next if no.position == posicao

          no.position = posicao
          atualizacoes[no.id] = { position: posicao, sort_key: build_sort_key(no) }
        end

        aplicar_em_lote!(atualizacoes)
        # Os descendentes herdam a chave nova.
        ordenados.each { |no| rebuild_subtree_sort_keys!(no) if atualizacoes.key?(no.id) }
      end

      # Uma gravação por nó, mas **fora de qualquer laço aninhado**: é a
      # diferença entre linear e quadrático. Sem callbacks de propósito —
      # posição não é regra de negócio e não deve disparar recálculo de valor.
      def aplicar_em_lote!(atualizacoes)
        return if atualizacoes.empty?

        AvailabilityTemplate.transaction do
          atualizacoes.each do |id, atributos|
            AvailabilityTemplate.where(id: id).update_all(atributos.merge(updated_at: Time.current))
          end
        end
      end
    end
  end
end
