# frozen_string_literal: true

# S6 / **BE-188**, **DB-163**, **DB-164** — o **recibo**: a remuneração devida
# sobre UMA operação. Dono por **DEC-63**.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `20220802225011_create_receipts` e `20220804195335_add_date_and_operation_title_to_receipts`
# nunca subiram; `remunerations` também não. Conferido no dump: não há
# `COPY public.receipts`. Regra espelhada de `../sfg/app/models/receipt.rb`,
# sem correção, e o golden trava a **leitura do código de 2022**.
#
# ## As três fotografias (DB-164)
#
# `operation_value`, `date` e `operation_title` são cópias do estado da operação
# **no dia do recibo**. Não é denormalização por desempenho: é o que faz um
# recibo emitido continuar dizendo o que foi cobrado, mesmo depois de a operação
# ser prorrogada ou reavaliada.
#
# `date` pode ser **nula**: ela vem de `operation.issue_date`, e a operação
# estática do par pré/antecipação tem `issue_date` nula por desenho (B-08 da
# S5). A tela não pode quebrar por isso (FE-184).
#
# ## O que fica pendente da S8
#
# - `remuneration_id` aponta para `remunerations`, tabela da **S8**. A
#   associação é declarada aqui e resolve em tempo de execução; sem o model, o
#   gerador de recibos (`Charges::ReceiptGenerator`) **para com aviso nomeando a
#   fatia**, em vez de explodir — mesmo padrão do motor de ETL.
# - `operation` é polimórfica entre `RiskOperation` (existe, S5) e
#   `StructuredOperation` (**S8**). O tipo desconhecido **falha**; no legado
#   virava a string `"???"` (`remuneration.rb:44`) e seguia adiante.
class Receipt < ApplicationRecord
  include ProjectScoped
  include Auditable

  # As duas siglas do legado (`receipt.rb:16-18`). Aqui elas continuam sendo
  # exatamente `LIQ` e `EST` — diferente de `status` e `state`, estas **não**
  # são rótulo pt-BR: são siglas técnicas que a tela também mostra.
  KIND_RISK = 'LIQ'
  KIND_STRUCTURED = 'EST'
  KINDS = [KIND_RISK, KIND_STRUCTURED].freeze

  # O de-para tipo de operação → sigla. No legado era um `if/elsif/else` que
  # terminava em `"???"`.
  KIND_BY_OPERATION = {
    'RiskOperation' => KIND_RISK,
    'StructuredOperation' => KIND_STRUCTURED
  }.freeze

  belongs_to :charge, optional: true, inverse_of: :receipts
  belongs_to :operation, polymorphic: true, optional: true
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false
  # Resolvida em tempo de execução: `remunerations` é da S8.
  belongs_to :remuneration, optional: true

  validates :title, presence: true
  validates :fee, presence: true, numericality: true
  validates :operation_value, presence: true, numericality: true
  validates :value, presence: true, numericality: true
  validates :user_id, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :operation_type, inclusion: { in: KIND_BY_OPERATION.keys, allow_nil: true }
  # `receipt.rb:14` — uma operação não pode ser faturada duas vezes. O índice
  # único do banco fecha a corrida que a validação não vê.
  validates :operation_id, uniqueness: { scope: %i[project_id operation_type],
                                         message: 'já tem um recibo neste projeto' },
                           allow_nil: true

  scope :risk, -> { where(kind: KIND_RISK) }
  scope :structured, -> { where(kind: KIND_STRUCTURED) }
  scope :unbilled, -> { where(charge_id: nil) }

  ORDERING = Sfg::Sortable.new(
    allowed: { 'date' => :date, 'kind' => :kind, 'value' => :value, 'title' => :title },
    default: { date: :desc }
  ).freeze

  # `receipt.rb:68-70` (`generate_temp_id`) — a identidade estável do candidato **antes de ele
  # existir**. É por ela que a tela casa "marcado" com "persistido" quando o
  # lote é enviado; sem ela, a lista de candidatos não tem chave.
  def self.temp_id_for(project_id:, kind:, remuneration_id:, operation_id:)
    "RCP-#{project_id}-#{kind}-#{remuneration_id}-#{operation_id}"
  end

  def self.kind_for_operation_type(type)
    KIND_BY_OPERATION[type.to_s]
  end

  def refresh_temp_id!
    self.temp_id = self.class.temp_id_for(
      project_id: project_id, kind: kind, remuneration_id: remuneration_id, operation_id: operation_id
    )
  end
end
