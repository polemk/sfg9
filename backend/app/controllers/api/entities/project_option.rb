# frozen_string_literal: true

module Api
  module Entities
    # S2 / BE-412 — a projeção mínima de um projeto para o **seletor** da topbar.
    #
    # De propósito não expõe nada além do que o seletor desenha. O projeto
    # completo é da fatia S4; um seletor que devolvesse o registro inteiro viraria
    # a fonte de leitura de projeto do produto, e o escopo passaria a ser
    # decidido por quem chamou este endpoint em vez de por `current_project!`.
    class ProjectOption < Grape::Entity
      expose :id
      expose :name
      expose :slug
      expose :is_active
    end
  end
end
