# frozen_string_literal: true

module Api
  module Entities
    # Payload JSON da trilha de auditoria — `FE-446`.
    #
    # O legado tinha `api/v1/trackings/_show.json.jbuilder`, que expunha
    # `target_id`/`target_group_id`/`type`. Nenhum dos três é portado, e a
    # evidência está no relatório da S19: `target_*` **nunca é escrito** por
    # nenhum dos 20 emissores do `TrackingFacade`, e `type` é STI sempre `NULL`.
    #
    # O que muda de verdade em relação ao legado, e é o ponto do DEC-59 #3:
    # **o autor é o usuário REAL.** Na impersonação, `author` é quem impersonou
    # e `impersonated` é quem a sessão aparentava ser. A trilha do legado não
    # tinha esse conceito — ela gravava `true_user` em três chamadas e
    # `current_user` no resto, sem dizer qual era qual.
    class AuditVersion < Grape::Entity
      expose :id, documentation: { type: 'Integer', desc: 'Identificador da versão' }

      expose :item_type, documentation: { type: 'String', desc: 'Classe do registro versionado' }
      expose :item_id, documentation: { type: 'String', desc: 'Id do registro versionado, como texto' }

      expose :entity_label, documentation: { type: 'String', desc: 'Rótulo pt-BR do tipo, do catálogo' } do |v, _o|
        Sfg::AuditSummary.label_for(v.item_type)
      end

      expose :event, documentation: { type: 'String', desc: 'create, update ou destroy' }

      # A frase que a timeline mostra. Derivada, não gravada — ver
      # `Sfg::AuditSummary` para por que isso importa.
      expose :summary, documentation: { type: 'String', desc: 'Resumo em pt-BR do evento' } do |v, _o|
        Sfg::AuditSummary.call(item_type: v.item_type, event: v.event)
      end

      # Autor REAL do ato (DEC-59 #3). `nil` quando a versão nasceu fora de uma
      # requisição — seed, migração, console. Exposto como `null` de propósito:
      # "não sei quem foi" é informação, e esconder o campo faria a tela
      # inventar um autor.
      expose :author, documentation: { type: 'Object', desc: 'Usuário real do ato' } do |v, o|
        Api::Entities::AuditVersion.actor(v.whodunnit, o[:actors])
      end

      expose :impersonated,
             documentation: { type: 'Object', desc: 'Quem a sessão aparentava ser, só em impersonação' } do |v, o|
        Api::Entities::AuditVersion.actor(v.impersonated_id, o[:actors])
      end

      expose :reason, documentation: { type: 'String', desc: 'Motivo declarado do ato administrativo' }
      expose :ip_address, documentation: { type: 'String', desc: 'Origem da requisição' }

      expose :occurred_at, documentation: { type: 'DateTime', desc: 'Quando aconteceu (ISO-8601, UTC)' } do |v, _o|
        v.created_at&.utc&.iso8601
      end

      # Campo a campo, `[antes, depois]`. Vai na listagem porque é o que a
      # timeline mostra sem precisar de um segundo request.
      expose :changes, documentation: { type: 'Object', desc: 'Diff da mudança, campo a campo' } do |v, _o|
        v.object_changes.is_a?(Hash) ? v.object_changes : {}
      end

      # Foto COMPLETA do estado anterior (DEC-78). **Só no detalhe**: numa página
      # de 20 versões de `users`, mandar 20 fotos inteiras é trocar a listagem
      # por um download.
      expose :snapshot, if: { detail: true },
                        documentation: { type: 'Object', desc: 'Estado completo do registro antes da mudança' } do |v, _o|
        v.object.is_a?(Hash) ? v.object : {}
      end

      # Resolve um id de usuário em `{ id, name, email }` sem N+1 quando o
      # chamador passa o mapa pronto em `options[:actors]`.
      def self.actor(id, actors = nil)
        return nil if id.blank?

        user = actors ? actors[id.to_s] : ::User.find_by(id: id)
        return { id: id.to_s, name: nil, email: nil } unless user

        { id: user.id.to_s, name: user.name, email: user.email }
      end
    end
  end
end
