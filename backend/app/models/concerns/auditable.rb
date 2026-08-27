# frozen_string_literal: true

# Liga o model à trilha de auditoria (`paper_trail`, DEC-59).
#
# Uso, no model:
#
#     class Receivable < ApplicationRecord
#       include Auditable
#     end
#
# As opções (`skip`, `ignore`) **não** ficam aqui nem no model: ficam em
# `Sfg::AuditTrail::VERSIONED`, que é o único lugar onde a lista de models
# versionados é declarada (DEC-78 #1). Incluir este módulo num model que não
# está declarado lá levanta na carga da classe, com a mensagem dizendo o que
# fazer — versionar por descuido é exatamente o que duplica a base.
#
# Por que a inclusão é explícita no model, e não um laço num initializer que
# aplicaria `has_paper_trail` a partir da lista: quem abre `Receivable.rb`
# precisa **ver** que o model é versionado. Trilha aplicada à distância é
# trilha que ninguém sabe que existe até a base dobrar de tamanho.
module Auditable
  extend ActiveSupport::Concern

  included do
    has_paper_trail(**Sfg::AuditTrail.options_for(name))
  end
end
