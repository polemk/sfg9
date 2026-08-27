# frozen_string_literal: true

# S11 / DB-122, BE-110..116, BE-140..148 — **o padrão de disponibilidade de um
# projeto**: a linha da grade do painel.
#
# Escopado por projeto (contrato **C1**), o oposto do
# `GlobalAvailabilityTemplate`. O escopo é aplicado **no endpoint**, por
# `current_project!` — `ProjectScoped` dá o `for_project` e recusa
# `default_scope` de propósito.
#
# ## O bloqueio (DB-128) — e o defeito que ele fecha
#
# Os quatro jobs do legado (ativar, desativar, remover, propagar) chamavam
# `locked!` antes de enfileirar e `unlocked!` **só no caminho feliz**
# (`project_availability_template.rb:718`, `:786`; e o de remoção **nunca**
# chamava). Uma exceção — engolida, com `destroy_failed_jobs? false` e sem
# retry — deixava o padrão **bloqueado para sempre**, sem caminho de
# recuperação. É o **D-05**.
#
# Aqui o par `lock!`/`unlock!` vive num lugar só e o `unlock!` roda em `ensure`
# nos quatro jobs. `AvailabilityTemplateLock` é o serviço; estes métodos são a
# persistência que ele usa.
#
# **Padrões travados no legado migram DESBLOQUEADOS** e o ETL os reporta: não se
# importa um estado que só existe porque um job morreu em 2019.
class ProjectAvailabilityTemplate < AvailabilityTemplate
  include ProjectScoped

  belongs_to :global_template, class_name: 'GlobalAvailabilityTemplate',
                               foreign_key: :global_availability_template_id,
                               optional: true, inverse_of: :project_templates

  # `restrict_with_error`, e desta vez ele **é respeitado** (DC-20). No legado a
  # associação declarava `dependent: :restrict_with_error` e o
  # `background_remove_templates` fazia `self.entries.destroy_all` logo antes do
  # `destroy_all` dos padrões — contornando a própria restrição e apagando
  # lançamento financeiro sem avisar ninguém.
  has_many :entries, class_name: 'AvailabilityEntry', foreign_key: :availability_template_id,
                     inverse_of: :availability_template, dependent: :restrict_with_error

  validates :project_id, presence: true

  validate :global_origin_must_be_unique_in_project
  validate :parent_must_belong_to_same_project

  def scope_label
    is_global? ? 'Global' : 'Específico'
  end

  # Só é removível se não tiver lançamento — a mesma pergunta que
  # `is_deletable?` respondia no legado, e agora a resposta vale também no
  # servidor, não só como dica de interface.
  def deletable?
    !AvailabilityEntry.where(availability_template_id: subtree_ids).exists?
  end

  # --- Bloqueio (DB-128) -------------------------------------------------
  # Desce para os filhos, como o legado fazia — bloquear o pai e deixar o filho
  # editável tornaria o bloqueio decorativo.
  def lock!(message, actor: nil)
    ids = subtree_ids
    self.class.where(id: ids).update_all(
      is_locked: true, locked_message: message, locked_at: Time.current,
      locked_by_id: actor&.id, updated_at: Time.current
    )
    reload
  end

  # **Chamado em `ensure`, com ou sem sucesso** (BE-147). Um job desta fatia sem
  # este `unlock!` no `ensure` é o D-05 de volta.
  def unlock!
    ids = subtree_ids
    self.class.where(id: ids).update_all(
      is_locked: false, locked_message: nil, locked_at: nil,
      locked_by_id: nil, updated_at: Time.current
    )
    reload if persisted?
    true
  rescue ActiveRecord::RecordNotFound
    # O registro foi destruído pela própria operação (remoção concluída). Não é
    # erro: não há o que desbloquear.
    true
  end

  private

  def siblings_at_base
    ProjectAvailabilityTemplate.where(project_id: project_id, parent_template_id: nil)
  end

  # "Um padrão de projeto por global por projeto" (DB-122). O índice único do
  # banco é a garantia; esta validação é a mensagem em pt-BR.
  def global_origin_must_be_unique_in_project
    return if global_availability_template_id.blank? || project_id.blank?

    irmao = ProjectAvailabilityTemplate.where(project_id: project_id,
                                              global_availability_template_id: global_availability_template_id)
                                       .where.not(id: id)
    return unless irmao.exists?

    errors.add(:global_availability_template_id, 'já foi trazido para este projeto')
  end

  # **FE-148 pelo lado do servidor.** No legado o formulário embutia
  # `AvailabilityTemplate.all` — todos os padrões de **todos** os projetos — num
  # atributo `data-templates`, e o `parent_template_id` escolhido ia direto para
  # o `permit`. Escolher um pai de outro projeto era um `select` de distância.
  def parent_must_belong_to_same_project
    return if parent_template_id.blank? || project_id.blank?

    pai = parent_template
    return if pai.nil?
    return if pai.project_id == project_id

    errors.add(:parent_template_id, 'pertence a outro projeto')
  end
end
