# frozen_string_literal: true

# S10 / DB-312 — **a ponte projeto ↔ indicador**.
#
# Junção pura: existe só para dizer "este indicador aparece neste projeto". É ela
# que faz um indicador **global** entrar na grade mensal de um projeto, e é a
# ausência dela que faz o indicador sumir da tela sem que nenhum lançamento seja
# apagado (Q-R31: desconectar esconde, reconectar traz de volta com o histórico
# intacto — replicado, porque é conservador e não perde dado).
#
# A tabela foi criada pela **S4** (`20260826100300_create_project_connections.rb:52`),
# que deixou a FK para `indicators` combinada com esta fatia; a migration
# `20260826210100` fecha o combinado.
#
# **Não existe `is_active` aqui**, e isso é decisão: o controller do legado
# aceita `:is_active` no `permit` (`project_indicator_connections_controller.rb:196`)
# e a coluna **nunca existiu** na tabela — o parâmetro é descartado em silêncio
# desde 2021. Quem quer ligar/desligar o indicador mexe em `indicators.is_active`.
class ProjectIndicatorConnection < ApplicationRecord
  belongs_to :project
  belongs_to :indicator

  # A unicidade real é o índice único do banco
  # (`index_pic_on_project_and_indicator`). A validação aqui existe para dar
  # mensagem de humano no caminho normal; a corrida entre duas abas é barrada
  # pelo índice e tratada em `ConnectionService`.
  validates :indicator_id, uniqueness: { scope: :project_id,
                                         message: 'já está conectado a este projeto' }

  scope :for_project, lambda { |project|
    where(project_id: project.respond_to?(:id) ? project.id : project)
  }
end
