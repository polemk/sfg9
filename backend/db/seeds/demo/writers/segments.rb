# frozen_string_literal: true

module Demo
  module Writers
    # Os 3 segmentos do legado e os **subsegmentos que ele deixou vazios**
    # (`demo-seed-design.md` §4).
    #
    # `sub_segments` não tem FK para `segments` (DC-13) — a tabela é uma lista
    # plana. O razão guarda o subsegmento junto do cliente e é a S4 que liga os
    # dois no projeto.
    class Segments < Base
      def self.requires = %w[Segment]
      def self.owner_slice = 'S3'

      def call
        ledger.clients.map(&:segment).uniq.each do |title|
          upsert!(::Segment, find_by: { title: title }, attributes: { is_active: true })
        end

        if defined?(::SubSegment)
          ledger.clients.map(&:sub_segment).uniq.each do |title|
            upsert!(::SubSegment, find_by: { title: title }, attributes: { is_active: true })
          end
        end

        link_projects!
      end

      private

      # `projects.segment_id` é FK **lógica** na S0 — a tabela de segmentos só
      # nasce aqui. Por isso a ligação é feita neste módulo, depois de os dois
      # lados existirem, e não no escritor de projetos.
      def link_projects!
        segments = ::Segment.where(title: ledger.clients.map(&:segment)).index_by(&:title)
        subs = defined?(::SubSegment) ? ::SubSegment.all.index_by(&:title) : {}

        ledger.clients.each do |client|
          project = project_for(client)
          next if project.nil?

          attributes = { segment_id: segments[client.segment]&.id }
          attributes[:sub_segment_id] = subs[client.sub_segment]&.id if subs.any?
          assign(project, attributes)
          next unless project.changed?

          project.save!
          @updated += 1
        end
      end
    end
  end
end
