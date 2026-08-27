# frozen_string_literal: true

module Api
  module Entities
    # S11 / BE-120, FE-127, FE-132 — **uma linha da grade de disponibilidade**.
    #
    # A linha é o par (padrão, lançamento). O lançamento pode não existir — a
    # célula vazia é `entry: null`, **nunca um registro criado na leitura**
    # (DC-30 / BE-130).
    #
    # `editable` vem do servidor porque o critério tem de ser **o mesmo** nos
    # dois lados (FE-132 / D-23): no legado o bloqueio da célula era
    # exclusivamente de interface, e um `PUT` direto gravava em consolidação
    # geral e em nó com filhos sem nenhuma recusa. Aqui o `PUT` recusa, e a tela
    # desenha o campo somente-leitura pela **mesma** resposta.
    class AvailabilityGridRow < Grape::Entity
      expose :template, using: Api::Entities::AvailabilityTemplate do |row|
        row[:template]
      end

      expose :entry, using: Api::Entities::AvailabilityEntry do |row|
        row[:entry]
      end

      expose :has_children do |row|
        row[:has_children]
      end

      expose :editable do |row|
        row[:editable]
      end

      # **DEC-26 — o rótulo É a decisão.** Duas regras de soma convivem na mesma
      # tela, de propósito, e o que impede isso de virar defeito silencioso (o
      # D-08 outra vez) é o usuário saber qual está lendo.
      expose :value_semantics, documentation: {
        type: 'String',
        desc: 'input | group_total | consolidation — qual regra de soma produziu o valor desta linha'
      } do |row|
        if row[:entry]&.consolidation?
          'consolidation'
        elsif row[:has_children]
          'group_total'
        else
          'input'
        end
      end

      expose :value_semantics_label do |row|
        case row[:entry]&.consolidation? ? 'consolidation' : (row[:has_children] ? 'group_total' : 'input')
        when 'consolidation' then 'Consolidação geral — soma bruta das empresas'
        when 'group_total' then 'Total do grupo — respeita cumulatividade e sinal'
        else 'Lançamento'
        end
      end
    end
  end
end
