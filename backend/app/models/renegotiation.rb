# frozen_string_literal: true

# S9 / BE-199, DB-190 — **a renegociação**.
#
# É o outro lado do balcão do Safegold: a dívida negociada com um fornecedor,
# parcelada, paga ao longo do tempo e documentada por anexos.
#
# **O que este model deliberadamente NÃO faz: contas.** No legado
# `Renegotiation#update_values` (`app/models/renegotiation.rb:89-127`) calculava
# ~20 agregados dentro do model, e `update_values!` os gravava com um `save`
# **sem bang** — falha de validação **descartava o recálculo em silêncio**
# (**D-79**). Aqui as fórmulas vivem em `Renegotiations::AggregateService`
# (contrato C2: um cálculo, um dono), que persiste em transação e **levanta** em
# falha. O model guarda estado e invariantes; quem soma é o serviço.
#
# **Nenhum callback dispara cascata.** No legado o `after_save` do pagamento
# chamava a parcela, que chamava a renegociação — e, combinado com o `update` +
# `save` redundante do controller, a cascata rodava em duplicidade. Aqui a
# cascata é explícita e transacional, escrita nos serviços.
class Renegotiation < ApplicationRecord
  # Só pelo `attr_accessor` — o carimbo dela é feito dentro de
  # `carimbar_projeto_e_fornecedor`, junto com `provider_name` e `correct_value`.
  attr_accessor :preserve_safegold_stamp

  include ProjectScoped
  include Auditable
  include BlockingDependents

  # --- Domínios fechados (D-B9) -------------------------------------------
  # **Os valores continuam em português.** Não é descuido de convenção: são DADO
  # de produção que o ETL copia linha a linha e que a tela exibe. Traduzi-los
  # aqui obrigaria a traduzir na carga, na tela e no filtro — e a primeira
  # divergência entre os três viraria um estado que nenhum filtro encontra, que
  # é exatamente o D-49 voltando por outra porta.
  KIND_FINANCEIRO = 'Financeiro'
  KIND_OPERACIONAL = 'Operacional'
  KIND_TRIBUTARIO = 'Tributario'
  KIND_TRABALHISTA = 'Trabalhista'
  KINDS = [KIND_FINANCEIRO, KIND_OPERACIONAL, KIND_TRIBUTARIO, KIND_TRABALHISTA].freeze

  STATE_CLOSED = 'Liquidado'
  STATE_OPEN = 'Pago'
  STATE_INCONSISTENT = 'Inconsistente'
  STATE_EMPTY = 'Sem parcela cadastrada'
  STATES = [STATE_CLOSED, STATE_OPEN, STATE_INCONSISTENT, STATE_EMPTY].freeze

  # Chave pública do filtro → valor gravado. O legado tinha um `case` **sem**
  # `when "empty"`, e a action abortava com a tela em 500 (**D-49**).
  STATE_FILTERS = {
    'closed' => STATE_CLOSED,
    'open' => STATE_OPEN,
    'inconsistent' => STATE_INCONSISTENT,
    'empty' => STATE_EMPTY
  }.freeze

  ORIGINS = ['Minuta bancária', 'Fornecedor', 'Fundo'].freeze

  # --- Associações ---------------------------------------------------------
  belongs_to :provider
  belongs_to :company

  has_many :installments, class_name: 'RenegotiationInstallment', dependent: :restrict_with_error,
                          inverse_of: :renegotiation
  has_many :payments, class_name: 'RenegotiationPayment', dependent: :restrict_with_error,
                      inverse_of: :renegotiation
  # Os anexos **vão junto** quando a renegociação é excluída (BE-201). Parcela e
  # pagamento bloqueiam; anexo não é dado independente — é documento DELA.
  has_many :attachments, class_name: 'RenegotiationAttachment', dependent: :destroy,
                         inverse_of: :renegotiation

  # `restrict_with_error` acima já cobre o caminho do model; isto cobre o caminho
  # em que a coleção não foi carregada e dá a frase em pt-BR que nomeia o vínculo.
  def self.blocking_dependents
    {
      'RenegotiationInstallment' => { foreign_key: :renegotiation_id, label: 'parcela(s)' },
      'RenegotiationPayment' => { foreign_key: :renegotiation_id, label: 'pagamento(s)' }
    }
  end

  # --- Validações ----------------------------------------------------------
  validates :title, presence: true, length: { maximum: 255 }
  validates :provider_name, presence: true
  validates :provider_id, presence: true
  validates :company_id, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS, message: 'não é um tipo de renegociação conhecido' }
  validates :state, inclusion: { in: STATES }
  validates :renegotiation_date, presence: true
  validates :operation_interest_rate, presence: true, numericality: true
  validates :original_value, :total_debt, presence: true, numericality: true
  validates :integration_key, presence: true

  # **DEC-119 / DEC-127 — a unicidade vale entre as linhas que o ai9 criar.**
  #
  # No legado a chave era derivada do nome do fornecedor **sem unicidade
  # nenhuma**, e o dado real mostra por quê: 9 grupos, 82 linhas. Seis delas
  # repetem o rótulo digitado (`Renegociação`, `SSA`, `RENEGOCIAÇÃO
  # FINANCEIRA`), mas **três grupos repetem uma chave legitimamente derivada**
  # (`banco_bradesco`, `parcelamento_do_simples_absd`, `77800`): a chave sai de
  # `provider_name` (ver `derivar_chave_de_integracao`) e **um fornecedor tem
  # várias renegociações no mesmo projeto**. Repetir ali é o comportamento
  # certo, não sujeira — e é por isso que nenhum predicado sobre o VALOR da
  # chave separa os casos.
  #
  # O que separa é a proveniência. `if:` + `conditions:` espelham exatamente o
  # índice parcial de
  # `20260827020000_unicidade_parcial_onde_o_legado_diz_nao_se_aplica`
  # (`WHERE legacy_id IS NULL`); as duas mudam juntas ou a carga volta a parar.
  validates :integration_key,
            uniqueness: { scope: :project_id, message: 'já está em uso neste projeto',
                          conditions: -> { where(legacy_id: nil) } },
            if: -> { legacy_id.nil? }

  # `original_value = 0`, `total_debt` negativo e taxa negativa **continuam
  # aceitos** (Q-B21). O legado aceita, há registro de produção assim, e recusar
  # agora barraria edição de dado existente.

  # **Fornecedor e empresa são DO PROJETO** (C1, FE-197). O `permit` do legado
  # aceitava `provider_id`, `company_id` **e** `project_id` do corpo, e o `update`
  # não sobrescrevia nenhum: um campo escondido de formulário apontava a
  # renegociação para o fornecedor de outro tenant. O banco não pega isso — as
  # FKs de `provider_id` e `company_id` são simples, porque as duas tabelas têm o
  # próprio `project_id` e a FK composta exigiria um índice em cada uma.
  validate :provider_and_company_belong_to_project

  # --- Derivações de cadastro ----------------------------------------------
  # Mesmas do legado (`renegotiation.rb:22-37`), com uma diferença: o estado
  # inicial não é mais forçado para "Inconsistente" na criação — quem o define é
  # o `AggregateService`, chamado pelo `CreateService` **na criação** (BE-198).
  # No legado o registro nascia com tudo zerado e estado "Inconsistente" até
  # alguém mexer numa parcela.
  before_validation :carimbar_projeto_e_fornecedor
  before_validation :derivar_chave_de_integracao

  # --- Escopos de leitura ---------------------------------------------------
  # **A busca casa `title` E `provider_name`** (BE-190). No legado a primeira
  # coluna da lista era "Nome" e o `where` só olhava `provider_name`: buscar pelo
  # que estava escrito na tela não achava nada.
  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
    where('renegotiations.title ILIKE :q OR renegotiations.provider_name ILIKE :q', q: padrao)
  }

  scope :with_state, lambda { |chave|
    valor = STATE_FILTERS[chave.to_s]
    valor.present? ? where(state: valor) : all
  }

  scope :with_kind, ->(kind) { kind.present? && KINDS.include?(kind.to_s) ? where(kind: kind.to_s) : all }

  # Ordenação acumulada. As duas chaves são as que o legado conhecia
  # (`renegotiation.rb:196-207`); chave desconhecida é **ignorada** em vez de
  # produzir `nil + " "` → `NoMethodError` → 500.
  ORDERING = Sfg::Sortable.new(
    allowed: {
      'title' => 'renegotiations.title',
      'provider' => 'renegotiations.provider_name',
      'provider_name' => 'renegotiations.provider_name',
      'state' => 'renegotiations.state',
      'kind' => 'renegotiations.kind',
      'renegotiation_date' => 'renegotiations.renegotiation_date',
      'total_debt' => 'renegotiations.total_debt',
      'remaining_value' => 'renegotiations.remaining_value',
      'created_at' => 'renegotiations.created_at'
    },
    default: { 'renegotiations.provider_name' => :asc }
  ).freeze

  # --- Leitura derivada -----------------------------------------------------
  # `unposted_value` e `installment_status` medem a consistência do LANÇAMENTO:
  # se o que foi parcelado bate com a dívida contratada. Note que a referência é
  # `installments_main_value_with_interest` (principal + juros), **não**
  # `main_value` (que inclui correção monetária) — é o que o legado faz, com o
  # comentário `#7391 #7215` explicando que foi mudado a pedido do cliente.
  def unposted_value
    total_debt - installments_main_value_with_interest
  end

  def installment_status
    installments_main_value_with_interest == total_debt ? 'Consistente' : 'Inconsistente'
  end

  # "42.5% Pago" — o rótulo composto que a lista mostra quando há pagamento.
  def beauty_state
    return state unless state == STATE_OPEN

    "#{paid_percent}% #{STATE_OPEN}"
  end

  def attachments?
    attachments_count.to_i.positive?
  end

  private

  def carimbar_projeto_e_fornecedor
    # `has_safegold_management` é **carimbo** (D-30, Q-B32 / **DEC-112**).
    #
    # `renegotiation.rb:23-24` é um `before_validation` **sem `on:`**: recopia em
    # TODO save, não só na criação. O `new_record?` que estava aqui divergia do
    # legado — uma renegociação editada depois de a marca do projeto mudar
    # passava a divergir do que o legado gravaria. Nunca é ressincronizada em
    # massa: só `companies` é (`project.rb:298-303`).
    # `preserve_safegold_stamp` é do ETL (ver `SafegoldStamped`): carregar o
    # dump não pode recarimbar o valor histórico pelo de hoje.
    self.has_safegold_management = project.has_safegold_management if project.present? && !preserve_safegold_stamp
    self.provider_name = provider.title if provider.present?
    # `correct_value = total_debt` **sempre**. `interest_rate_correction` e
    # `grace_period` existem na tabela e nunca são lidos (D-47, Q-B24).
    self.correct_value = total_debt
    self.title = provider_name if title.blank?
  end

  def provider_and_company_belong_to_project
    return if project_id.blank?

    if provider.present? && provider.project_id != project_id
      errors.add(:provider_id, 'não pertence a este projeto')
    end
    return unless company.present? && company.project_id != project_id

    errors.add(:company_id, 'não pertence a este projeto')
  end

  def derivar_chave_de_integracao
    return if integration_key.present?
    return if provider_name.blank?

    self.integration_key = I18n.transliterate(provider_name).downcase.gsub(' ', '_')
  end
end
