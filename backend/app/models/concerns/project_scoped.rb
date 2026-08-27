# frozen_string_literal: true

# Peça 4 do contrato **C1** — escopo por projeto.
#
# O que este concern dá a um model: `belongs_to :project`, a validação de
# presença e o scope `for_project`. O que ele deliberadamente **NÃO** dá:
# `default_scope`.
#
# Por que não `default_scope` (a tentação óbvia de quem for implementar):
#   - vaza para `unscoped` e some sem avisar;
#   - quebra `joins`/`includes` em silêncio;
#   - contamina job, seed e rake, que legitimamente cruzam projetos;
#   - e o pior: torna o escopo **invisível na leitura do código**.
#
# O legado errou exatamente aí — sempre que chegava um id por parâmetro
# (`company_id`, `receivable_id`, `risk_operation_id`…), o filtro de projeto era
# descartado. É a família inteira D-01 / D-16 / D-29 / D-76 / D-100.
#
# A forma canônica no endpoint (copie esta, não invente outra):
#
#   project = current_project!                     # 404 se não houver participação
#   scope   = Receivable.for_project(project)      # escopo explícito, visível
#   scope   = scope.where(id: params[:receivable_id]) if params[:receivable_id]
#   # o project_id que vier no CORPO da requisição é SEMPRE ignorado
#
# Job, seed e rake **não** chamam `current_project!`: recebem `project_id` como
# argumento explícito e usam `for_project` direto. É por isso que o escopo não
# pode ser `default_scope`.
module ProjectScoped
  extend ActiveSupport::Concern

  included do
    belongs_to :project

    validates :project_id, presence: true

    # Aceita um `Project`, um id ou uma coleção de ids. Nunca devolve `all`:
    # escopo vazio é preferível a escopo esquecido.
    scope :for_project, lambda { |project|
      project_id = project.respond_to?(:id) ? project.id : project
      where(project_id: project_id)
    }
  end

  class_methods do
    # Marcador de leitura: `Model.project_scoped?` responde `true`. Serve à
    # tarefa 6.5 (conferir que nenhuma fatia criou um segundo mecanismo) e à
    # conferência automática do spec de contrato.
    def project_scoped?
      true
    end
  end
end
