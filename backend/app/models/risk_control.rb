# frozen_string_literal: true

# S5 / BE-239, BE-240, BE-241, DB-230, DB-572 — **limite de risco**.
#
# O teto que autoriza toda operação de crédito do Safegold: uma linha por
# (empresa, portador, tipo). Nenhuma operação de risco (S7) e nenhum recebível
# (S6) existem sem um limite ativo para a combinação.
#
# **Escopado por projeto (C1)**: `include ProjectScoped` dá `belongs_to :project`,
# a validação de presença e `for_project`. O filtro é aplicado **no endpoint**,
# nunca por `default_scope`. O `project_id` não vem do cliente — é derivado da
# empresa no `before_validation`, como no legado.
#
# ### As duas leituras divergentes da desativação são REPLICADAS (decisão B-02)
#
# Um limite desativado:
#
# - **some** do resumo do console — os agregados partem de `active` (`.active`);
# - **continua** listando as operações dele na tela de Operações de Risco —
#   `#operations` do legado busca por (projeto, empresa, portador, tipo) e
#   **não olha `is_active`** (`../sfg/app/models/risk_control.rb:73-75`).
#
# As duas leituras existem no legado e as duas ficam. Unificá-las muda exposição
# financeira. Há golden separado para cada uma (`L4`).
#
# ### `has_safegold_management` é CARIMBO (DEC-112)
#
# Copiado da **empresa** (`risk_control.rb:15`), não do projeto, em todo save — e
# nunca ressincronizado em massa. Ver o método privado.
class RiskControl < ApplicationRecord
  include SafegoldStamped
  safegold_stamp_source :company

  include ProjectScoped
  include BlockingDependents
  # DEC-59 / DEC-78 — trilha com payload completo. `Sfg::AuditTrail::VERSIONED`
  # já declarava esta linha antes de o model existir, e a razão está escrita lá:
  # *"como estava este limite no dia em que estourou"* é a pergunta que a decisão
  # cita para justificar guardar o objeto inteiro, e não só o campo alterado.
  include Auditable

  belongs_to :company
  belongs_to :carrier
  # `optional: true` no NÍVEL DA ASSOCIAÇÃO, porque o `belongs_to` do Rails
  # valida presença sozinho e ignoraria a condicional abaixo. A obrigatoriedade
  # real está em `validates … if: :type_required?`: a linha herdada do formato
  # pré-2022 pode não ter tipo; a criada pela tela, nunca.
  belongs_to :risk_operation_type, optional: true
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  # **Bloqueia, nunca cascateia** (D-24). Consequência a conhecer: um limite de
  # tipo COM pré-faturamento nunca fica sem operação, porque o `after_create`
  # abre o par estático — logo ele não é excluível enquanto o par existir. É o
  # comportamento do legado, e a mensagem do 422 diz exatamente isso.
  has_many :risk_entries, dependent: :restrict_with_error
  has_many :risk_operations, dependent: :restrict_with_error

  before_validation :derive_title_and_project

  validates :company_id, presence: true
  validates :carrier_id, presence: true
  # **Obrigatório na tela, dispensado na linha herdada.**
  #
  # As 600 linhas de `risk_controls` em produção **não têm tipo**: a migration
  # que tiparia o limite nunca subiu (`analise-dump-producao.md` §2, consulta 5).
  # Elas são preservadas como estão — e, sem tipo, ficam de fora de todos os
  # agregados até o ETL expandi-las nas linhas tipadas. É o que o rótulo
  # "Legado" da tela comunica.
  #
  # Um limite criado pelo aplicativo **sempre** tem tipo: sem ele não há bucket,
  # não há par estático e não há exposição.
  validates :risk_operation_type_id, presence: true, if: :type_required?
  validates :limite, presence: true, numericality: true
  validates :taxa, presence: true, numericality: true
  # A quádrupla. O índice único do banco fecha a corrida que a validação não vê.
  validates :carrier_id, uniqueness: {
    scope: %i[company_id risk_operation_type_id],
    message: 'já tem um limite deste tipo para esta empresa'
  }

  after_create :open_static_pair!

  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }

  # Busca por texto — **IMP-R3**. No legado `params[:q]` era lido, recebia
  # `""` por default e **nunca era aplicado** ao `where`
  # (`../sfg/app/controllers/pub/risk_controls_controller.rb:10,17-22`): a caixa
  # de busca da tela de Limites não filtrava nada, e a mensagem
  # "Não encontramos nenhum resultado para a busca «x»" era inalcançável.
  # `ILIKE` com bind e `sanitize_sql_like`, nunca interpolação (DEC-05).
  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
    joins(:company, :carrier)
      .where('risk_controls.title ILIKE :q OR companies.title ILIKE :q OR carriers.title ILIKE :q', q: padrao)
  }

  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'limite' => :limite, 'taxa' => :taxa, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze

  def self.blocking_dependents
    {
      'RiskEntry' => { foreign_key: :risk_control_id, label: 'posição(ões) diária(s)' },
      'RiskOperation' => { foreign_key: :risk_control_id, label: 'operação(ões) de risco' }
    }
  end

  # **A leitura larga** (B-02, tela de Operações de Risco): por (projeto,
  # empresa, portador, tipo), **sem** olhar `is_active`. É o `#operations` do
  # legado, linha a linha.
  def operations
    RiskOperation.where(
      project_id: project_id, company_id: company_id,
      carrier_id: carrier_id, operation_type_id: risk_operation_type_id
    )
  end

  # A linha herdada do formato pré-2022. Não entra em agregado nenhum: todos
  # partem de `RiskOperationType.active`.
  def legacy_shape?
    risk_operation_type_id.nil?
  end

  # Só a linha que veio do ETL (tem `legacy_id`) pode nascer sem tipo.
  def type_required?
    legacy_id.blank?
  end

  def activate!
    self.is_active = true
    save!
  end

  def deactivate!
    self.is_active = false
    save!
  end

  private


  # BE-239 — réplica de `../sfg/app/models/risk_control.rb:12-16`, com uma
  # diferença: as guardas. No legado `self.company.project_id` com `company_id`
  # nulo levanta `NoMethodError` **antes** de a validação de presença rodar, e o
  # endpoint devolve **500** onde deveria devolver 422.
  def derive_title_and_project
    self.title = carrier.title if carrier_id.present? && carrier
    self.project_id = company.project_id if company_id.present? && company
  end

  # BE-241 — o par estático. Roda DENTRO da transação do `save`: se o tipo não
  # tiver os dois subtipos, o serviço levanta e o limite **não é gravado**.
  def open_static_pair!
    Risk::StaticPairService.call!(self)
  end
end
