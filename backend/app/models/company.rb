# frozen_string_literal: true

# S4 / BE-058, DB-050 — **empresa**, a contraparte tomadora dentro de um projeto.
#
# É o primeiro consumidor do contrato **C1**: `include ProjectScoped` dá
# `belongs_to :project`, a validação de presença e `for_project`. O escopo é
# aplicado **no endpoint** (`Company.for_project(current_project!)`), nunca por
# `default_scope`.
#
# É dela que pendem os limites de risco (S5), os recebíveis (S6) e as
# renegociações (S9) — por isso ela nasce antes de todos eles.
#
# Uma coisa que o legado tinha e que **não** volta:
#
# 1. **`dependent: :restrict_with_error` em `risk_controls`/`receivables`.**
#    Não porque a regra mude — ela é a mesma — mas porque as duas classes só
#    nascem em S5 e S6, e uma associação declarada contra classe inexistente
#    levanta `NameError` na hora do `destroy`. A regra fica declarada em
#    `.blocking_dependents` e passa a valer sozinha quando a tabela existir.
class Company < ApplicationRecord
  include SafegoldStamped
  safegold_stamp_source :project

  include ProjectScoped
  include BlockingDependents

  # Os portadores da empresa são **derivados do projeto** (DB-068): a ponte
  # única é `project_to_carrier_connections`. Nenhuma tabela empresa↔portador é
  # inventada — o legado não tem, e `Company#carriers` já era `through: :project`.
  has_many :carriers, through: :project

  validates :title, presence: true, length: { maximum: 255 },
                    uniqueness: { scope: :project_id, message: 'já existe neste projeto' }

  before_validation :normalize_title

  # Busca por texto — `ILIKE` com bind, nunca interpolação. O legado usava
  # `Dev.ilike`, que interpolava o OPERADOR conforme o adapter e montava o
  # padrão dentro da string: `100%` e `a'b` viravam padrão SQL em vez de texto.
  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    where('title ILIKE :q', q: "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%")
  }

  # Ordenação dirigida pelo cliente. Chave desconhecida é **ignorada**, nunca
  # 500 — ver `Sfg::Sortable`.
  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze

  def self.blocking_dependents
    {
      # S5 — os limites de risco da empresa. Política **simétrica**: bloquear,
      # nunca cascatear (DB-069). No legado a assimetria era o D-24.
      'RiskControl' => { foreign_key: :company_id, label: 'limite(s) de risco' },
      # S6 — os recebíveis lançados contra esta empresa (DB-070).
      'ReceivableEntry' => { foreign_key: :company_id, label: 'recebível(is)' },
      # S9 — as renegociações (DB-071).
      'Renegotiation' => { foreign_key: :company_id, label: 'renegociação(ões)' },
      # S11 — os lançamentos de disponibilidade da empresa.
      'AvailabilityEntry' => { foreign_key: :company_id, label: 'lançamento(s) de disponibilidade' }
    }
  end

  private


  def normalize_title
    self.title = title.to_s.strip.presence
  end
end
