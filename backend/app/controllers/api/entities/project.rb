# frozen_string_literal: true

module Api
  module Entities
    # S4 / BE-080, BE-101 — **o projeto**, na forma que a lista e o detalhe usam.
    #
    # O seletor da topbar continua com `Api::Entities::ProjectOption`, de
    # propósito: um seletor que devolvesse o registro inteiro viraria a fonte de
    # leitura de projeto do produto (S2).
    #
    # `availability_note_html` e `_text` seguem o caminho já existente do
    # `User#biography` (`api/entities/user.rb`) — ActionText **reuse**, zero
    # componente novo dos dois lados.
    class Project < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :name, documentation: { type: 'String', desc: 'Nome do projeto (era `formal`). Único' }
      expose :slug,
             documentation: { type: 'String', desc: 'IMUTÁVEL após a criação (DC-17): renomear não muda a URL' }
      expose :integration_key,
             documentation: { type: 'String', desc: 'Chave de integração, congelada na criação' }
      expose :color, documentation: { type: 'String', desc: 'Hex #RRGGBB' }
      expose :is_active, documentation: { type: 'Boolean' }

      expose :segment_id
      expose :segment_title, documentation: { type: 'String' } do |p|
        p.segment&.title
      end
      expose :sub_segment_id
      expose :sub_segment_title, documentation: { type: 'String' } do |p|
        p.sub_segment&.title
      end

      # Endereço — UMA coluna de cidade (`address_city`). O legado tinha `city` e
      # `address_city`, escrevia numa e lia da outra: a cidade digitada nunca
      # aparecia no endereço formatado (**D-124**).
      expose :address_type, :address, :address_number, :address_complement
      expose :neighborhood, :cep, :address_state, :address_city
      expose :formatted_address, documentation: { type: 'String', desc: 'Endereço em linhas, pronto para exibir' }
      expose :closing_date, documentation: { type: 'Date', desc: 'Data de baixa. Informativa' }

      expose :responsible_id
      expose :responsible_name, documentation: { type: 'String', desc: 'Nome do responsável (com ou sem conta)' } do |p|
        p.responsible&.name || p.responsible_name
      end
      expose :responsible_email, documentation: { type: 'String' } do |p|
        p.responsible&.email || p.responsible_email
      end

      expose :owner_id, documentation: { type: 'String', desc: 'Dono. Não perde participação (DEC-18.5)' } do |p|
        p.user_id
      end
      expose :owner_name, documentation: { type: 'String' } do |p|
        p.owner&.name
      end

      expose :has_safegold_management,
             documentation: { type: 'Boolean', desc: 'Gerido pela Safegold. Só em `projects` — ver Q-02' }
      expose :has_bi, documentation: { type: 'Boolean', desc: 'BI contratado (DC-16)' }
      expose :is_sandbox,
             documentation: { type: 'Boolean', desc: 'Projeto de treinamento: NÃO removível, só limpável' }

      expose :avatar_url, documentation: { type: 'String', desc: 'URL assinada da variante `preview`, ou `null`' }

      expose :job_state, documentation: { type: 'String', desc: 'running | done | failed | null' }
      expose :job_progress, documentation: { type: 'Integer', desc: '0..100. `null` = o job ainda não reportou' }

      # **Sanitizada no servidor** (`Sfg::RichText`), com a mesma allowlist do
      # contrato e da instrução do indicador. Antes ia crua: a tela renderizava
      # com `dangerouslySetInnerHTML` e o comentário justificava dizendo que "o
      # ActionText recusa anexo no servidor" — recusar anexo não é sanitizar.
      expose :availability_note_html, documentation: { type: 'String', desc: 'ActionText — HTML sanitizado' } do |p|
        Sfg::RichText.sanitize(p.availability_note.body)
      end
      # **Sempre String, nunca `nil`** — igual ao `_html` logo acima.
      #
      # O `&.to_plain_text` sozinho devolvia `nil` para nota vazia enquanto o
      # irmão `_html` já fazia `.to_s`. Dois campos que descrevem a MESMA nota
      # discordavam sobre como representar "vazio", e o tipo declarado no
      # frontend dizia `string` para os dois. Resultado: a tela de detalhe de
      # projeto chamava `.trim()` em `null` e caía inteira — com `tsc` verde,
      # porque o tipo mentia. Coerção aqui, no lado que produz o dado.
      expose :availability_note_text, documentation: { type: 'String', desc: 'ActionText — texto puro (`""` quando vazio)' } do |p|
        p.availability_note.body&.to_plain_text.to_s
      end

      expose :members_count, documentation: { type: 'Integer' } do |p, options|
        (options[:members_counts] || {})[p.id] || p.memberships.size
      end

      expose :created_at
      expose :updated_at
    end
  end
end
