# frozen_string_literal: true

module Api
  module Entities
    # S4 / BE-059, BE-065 — **fornecedor**.
    #
    # O documento sai em **três campos**: `document_type` e `document` (dígitos,
    # o que está no banco) e `formatted_document` (com máscara, pronto para a
    # tela). O legado devolvia `cpf_cnpj` — um campo só, com ou sem máscara
    # conforme quem tivesse gravado — e a tela adivinhava qual era.
    class Provider < Grape::Entity
      expose :id, documentation: { type: 'String', desc: 'UUID' }
      expose :project_id, documentation: { type: 'String', desc: 'Projeto dono. NUNCA aceito no corpo (C1)' }
      expose :title, documentation: { type: 'String' }
      expose :resume, documentation: { type: 'String', desc: 'Descrição livre' }
      expose :integration_key,
             documentation: { type: 'String', desc: 'Chave de integração, congelada na criação (DC-22)' }
      expose :is_active, documentation: { type: 'Boolean' }

      expose :document_type, documentation: { type: 'String', desc: 'CPF | CNPJ | null' }
      expose :document, documentation: { type: 'String', desc: 'Somente dígitos' }
      expose :formatted_document, documentation: { type: 'String', desc: 'Com máscara, ou `-`' }

      expose :cnpj_fetched_at,
             documentation: { type: 'DateTime', desc: 'Quando o cadastro veio da ReceitaWS. `null` = preenchido à mão' }
      expose :legal_name, :trade_name, :status, :opened_at, :status_changed_at
      expose :email, :phone
      expose :zip_code, :street, :number, :complement, :district, :city, :state
      expose :activities,
             documentation: { type: 'Object', desc: 'CNAEs e atividades num ÚNICO jsonb (D-25)' }

      expose :logo_url, documentation: { type: 'String', desc: 'URL assinada da variante `preview`, ou `null`' }

      # **Só as renegociações.** Hoje é o único dependente do fornecedor, então
      # somar daria o mesmo número — mas por acaso, e o acaso acaba no dia em que
      # ele ganhar o segundo. Foi exatamente assim que a coluna "LIMITES" da tela
      # de Empresas passou a mostrar 43 onde havia 4.
      expose :renegotiations_count,
             documentation: { type: 'Integer', desc: 'Renegociações do fornecedor (só elas)' } do |p, options|
        ((options[:usage] || {})[p.id] || {})['Renegotiation'].to_i
      end
      expose :created_at
      expose :updated_at
    end
  end
end
