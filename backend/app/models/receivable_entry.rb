# frozen_string_literal: true

# S6 / **BE-181**, **BE-445**, **DB-150**…**DB-157**, **DB-564** — **o borderô**.
#
# É o registro central do Safegold: onde o dinheiro entra no sistema. 28.131
# linhas em produção, de 27/02/2022 a 30/05/2025.
#
# ## O que este model NÃO faz, e é a mudança que mais importa
#
# **Ele não calcula.** No legado, um `before_validation` de 80 linhas
# (`../sfg/app/models/receivable_entry.rb:38-118`) atribuía ~30 colunas
# derivadas **antes** de qualquer validação rodar. Isso produziu três defeitos
# de uma vez:
#
# - **D-09** — a mesma conta existia também em JavaScript
#   (`receivables/new/_body.js.erb:339-504`), parcial e com outro
#   arredondamento: a prévia da tela e o valor gravado divergiam;
# - **D-10** — calcular antes de validar grava `Infinity`/`NaN`. Há **30
#   borderôs em produção** com `NaN` em coluna de dinheiro;
# - **D-11** — o controller salvava **duas vezes**, e a `RiskOperation` nascia
#   no primeiro save, **antes de existir qualquer tarifa**, com o líquido errado
#   congelado para sempre.
#
# Aqui a conta vive em `Receivables::Calculator` (contrato **C2**), chamada pela
# prévia e pela gravação, **uma vez por operação**, com as tarifas já no lugar.
#
# ## Escopo por projeto (C1)
#
# `include ProjectScoped` dá `for_project`; o filtro é aplicado **no endpoint**
# via `current_project!`, nunca por `default_scope`. É a correção literal da
# família D-01/D-16/D-29/D-76/D-100: no legado, sempre que chegava
# `receivable_id` por parâmetro, o escopo de projeto era descartado.
#
# ## As validações são as do legado (Q-B11)
#
# **Sem** janela de data e **sem** `valor_bruto > 0`. Acrescentá-las recusaria
# lançamentos que o legado aceita há três anos.
class ReceivableEntry < Entry
  include SafegoldStamped
  safegold_stamp_source :project

  include ProjectScoped
  include BlockingDependents
  # DEC-59 / DEC-78 — trilha com payload completo. "Como estava este borderô no
  # dia em que o número saiu errado" é a pergunta que a decisão cita.
  include Auditable

  belongs_to :company
  belongs_to :carrier
  belongs_to :wallet
  belongs_to :receivable_kind
  belongs_to :resource_source
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false
  # Opcionais — "Não associar" é escolha válida na tela (DB-156). E as duas
  # colunas **nunca existiram em produção**: a migration que as cria é uma das
  # 24 que não subiram (DEC-103b).
  belongs_to :risk_operation_type, optional: true
  belongs_to :risk_operation_subtype, optional: true

  has_many :taxes, class_name: 'ReceivableTax', dependent: :destroy, inverse_of: :receivable_entry
  # `dependent: :destroy` replica o legado (`receivable_entry.rb:8`): excluir o
  # borderô leva junto a operação de risco que ele gerou. Não é cascata
  # acidental — a operação **é** o borderô do ponto de vista da exposição.
  has_one :risk_operation, class_name: 'RiskOperation', foreign_key: :receivable_id,
                           dependent: :destroy, inverse_of: false

  before_validation :apply_defaults
  before_validation :derive_operation_type

  validates :user_id, presence: true
  validates :date, presence: true
  validates :carrier_id, presence: true
  validates :company_id, presence: true
  validates :wallet_id, presence: true
  validates :receivable_kind_id, presence: true
  validates :resource_source_id, presence: true
  validates :qtd_titulos, presence: true, numericality: { only_integer: true }
  validates :valor_bruto, presence: true, numericality: true
  validates :prz_med_pond_emp, presence: true, numericality: { greater_than: 0 }
  validates :prz_med_pond_bco, presence: true, numericality: { greater_than: 0 }
  validates :float_acordado, presence: true, numericality: true
  validates :cst_efetivo_acordado, presence: true, numericality: true
  validates :status, inclusion: { in: STATUSES, allow_nil: true }
  validate :risk_control_must_be_active
  validate :derived_values_must_be_finite

  scope :ordered, -> { order(date: :desc, created_at: :desc) }

  # Busca por texto. **No legado a busca de recebíveis interpolava fragmento SQL
  # na string do `where`** — `%` e `_` do usuário viravam curinga, e aspas
  # abriam caminho de injeção. Aqui `sanitize_sql_like` + bind (OPS-157).
  #
  # O rótulo da caixa na tela diz que a busca é **por portador**, e é: é o que o
  # legado consulta. Número do borderô e descrição entram junto porque estavam
  # na mesma caixa e ninguém percebia a diferença.
  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
    joins(:carrier).where(
      'carriers.title ILIKE :q OR receivable_entries.nro_bordero ILIKE :q ' \
      'OR receivable_entries.description ILIKE :q',
      q: padrao
    )
  }

  # Janela de datas. **Limite ausente OMITE a cláusula** (OPS-158). No legado o
  # que faltava virava `DateTime.dinosaurs` (ano −2000) ou `DateTime.mars` (ano
  # +2000) — um intervalo de 4000 anos que o banco tem de percorrer e que pode
  # estourar a faixa de `date`.
  scope :between_dates, lambda { |from, to|
    escopo = all
    escopo = escopo.where(date: from..) if from.present?
    escopo = escopo.where(date: ..to) if to.present?
    escopo
  }

  # As 10 chaves de ordenação do legado (`receivable_entry.rb:190-213`), agora
  # numa allowlist que **ignora** chave desconhecida em vez de responder 500
  # (`Sfg::Sortable`). `carrier` e `wallet` ordenam por título da tabela
  # associada — quem usar precisa do `joins`, e o serviço já o faz.
  ORDERING = Sfg::Sortable.new(
    allowed: {
      'carrier' => 'carriers.title', 'wallet' => 'wallets.title',
      'date' => 'receivable_entries.date',
      'bruto' => 'receivable_entries.valor_bruto',
      'tarifas' => 'receivable_entries.valor_total_tarifas',
      'liquido' => 'receivable_entries.valor_liquido',
      'titulos' => 'receivable_entries.qtd_titulos',
      'pmr' => 'receivable_entries.prz_med_pond_bco',
      'cet' => 'receivable_entries.custo_efetivo_pz_med_emp',
      'cetsf' => 'receivable_entries.custo_efetivo_sem_float'
    },
    default: { 'receivable_entries.date' => :desc }
  ).freeze

  # As colunas que o `Receivables::Calculator` escreve. Uma lista só, lida pelo
  # serviço de gravação, pela prévia e pelo teste que compara as duas.
  DERIVED_COLUMNS = %i[
    tarifas_ad_valorem tarifas_desagio tarifas_iof tarifas_outras
    vlr_bruto_final qtd_final float_calculado diferenca_float checagem_iof
    valor_total_tarifas valor_liquido
    recompra_percent retencao_percent fomento_percent outros_percent
    total_deducoes vlr_liq_recebido
    taxa_desconto_nominal_desagio_advalorem_bancos taxa_desconto_nominal_despesas_bancos
    taxa_desconto_nominal_despesas_iof_bancos
    custo_efetivo_pz_med_banco custo_efetivo_pz_med_banco_sem_iof
    taxa_desconto_nominal_desagio_advalorem_emp taxa_desconto_nominal_despesas_emp
    taxa_desconto_nominal_despesas_iof_emp
    custo_efetivo_pz_med_emp custo_efetivo_pz_med_emp_sem_iof
    custo_efetivo_sem_float custo_efetivo_com_float_total custo_efetivo_com_float_sem_iof
    multiplicador_pm_empresa multiplicador_pm_float
    calc_valor_liq_correto dif_calc_vlr_liq status
    nominal_tax_check nominal_tax_check_with_float
  ].freeze

  # As colunas que o usuário digita. É delas que o `Calculator::Input` é montado
  # — na prévia e na gravação, pelo mesmo caminho.
  INPUT_COLUMNS = %i[
    valor_bruto vlr_bruto_recusado qtd_titulos qtd_recusada
    prz_med_pond_emp prz_med_pond_bco float_acordado cst_efetivo_acordado
    recompra retencao fomento outros
  ].freeze

  # **Nada bloqueia a exclusão de um borderô** — de propósito. O que pende dele
  # (tarifas e a operação de risco gerada) é `dependent: :destroy`, porque essas
  # linhas **são** o borderô: sem ele não têm significado. É o comportamento do
  # legado. O `include BlockingDependents` fica pelo `before_destroy`, que é a
  # peça que a S7 usará quando a operação ganhar dependentes próprios.

  # O `Input` do calculador a partir deste registro. **As tarifas vêm do
  # argumento quando dado** — é o que permite calcular com as tarifas que ainda
  # não foram gravadas, dentro da mesma transação, sem um `save` extra (D-11).
  # **DEC-120 — o borderô que tem tarifa de valor DESCONHECIDO se declara.**
  #
  # Tarifa com `value` nulo fica fora das somas (`Receivables::Calculator`), e é
  # exatamente por ficar fora que o total mostrado **não é o total real**: ele é
  # o total do que se sabe. Sem esta marca a tela mostraria um número redondo
  # para um borderô incompleto, que é a forma mais silenciosa de mentir.
  #
  # `taxes.loaded? ? … : exists?` porque a lista já vem carregada no detalhe (o
  # entity expõe as tarifas) e recontar no banco seria uma consulta por linha na
  # listagem.
  def unknown_tax?
    if taxes.loaded?
      taxes.any? { |t| t.value.nil? }
    else
      taxes.where(value: nil).exists?
    end
  end

  def calculator_input(taxes: nil)
    Receivables::Calculator::Input.new(
      **INPUT_COLUMNS.index_with { |c| public_send(c) },
      taxes: (taxes || self.taxes).map do |t|
        Receivables::Calculator::Tax.new(
          value: t.value, is_advalorem: t.is_advalorem,
          is_desagio: t.is_desagio, is_iof: t.is_iof
        )
      end
    )
  end

  private

  # `../sfg/app/models/receivable_entry.rb:216-219` — `set_defaults` no
  # `after_initialize`. Aqui em `before_validation`, que é onde o valor
  # realmente precisa estar: no legado um payload com `qtd_recusada: null`
  # sobrescrevia o default depois do `after_initialize` e a subtração
  # levantava `NoMethodError`.
  def apply_defaults
    self.qtd_recusada = 0 if qtd_recusada.nil?
    self.vlr_bruto_recusado = 0 if vlr_bruto_recusado.nil?
    self.recompra = 0 if recompra.nil?
    self.retencao = 0 if retencao.nil?
    self.fomento = 0 if fomento.nil?
    self.outros = 0 if outros.nil?
  end

  # `receivable_entry.rb:39` — o tipo é DERIVADO do subtipo, nunca informado.
  # **NUNCA EXECUTADO EM PRODUÇÃO** (DEC-103b): a migration que criou as duas
  # colunas é uma das 24 que não subiram.
  def derive_operation_type
    return if risk_operation_subtype_id.blank?

    self.risk_operation_type_id = risk_operation_subtype&.risk_operation_type_id
  end

  # **BE-181** — recebível exige limite ATIVO para o par
  # (empresa, portador, tipo). Réplica de `receivable_entry.rb:27-36`.
  #
  # ⚠ **NUNCA EXECUTADO EM PRODUÇÃO** (DEC-103b): depende de
  # `risk_operation_subtype_id`, coluna que não existe no banco de produção.
  # A regra vem espelhada do código de 2022, sem correção.
  #
  # A mensagem muda: o legado escrevia "Não possui limite cadastrado" sem dizer
  # de quem nem de qual tipo.
  def risk_control_must_be_active
    return if risk_operation_subtype_id.blank?
    return if company_id.blank? || carrier_id.blank?

    tipo_id = risk_operation_subtype&.risk_operation_type_id
    existe = RiskControl.where(
      company_id: company_id, carrier_id: carrier_id,
      risk_operation_type_id: tipo_id, project_id: project_id, is_active: true
    ).exists?
    return if existe

    errors.add(:risk_operation_subtype_id,
               'não tem limite de risco ativo para esta empresa e este portador. ' \
               'Cadastre o limite antes de lançar o borderô.')
  end

  # **D-10, a última linha de defesa.** O `Receivables::InputGuard` barra antes
  # de calcular; isto barra na hora de gravar, inclusive quando o registro vem
  # de um `update_column`, de um rake ou de um conversor de ETL.
  #
  # Não é redundância inútil: os 30 `NaN` de produção entraram exatamente por um
  # caminho que não passava pela tela.
  def derived_values_must_be_finite
    corrompidas = (DERIVED_COLUMNS + INPUT_COLUMNS).filter_map do |coluna|
      coluna if Receivables::InputGuard.nonfinite?(public_send(coluna))
    end
    return if corrompidas.empty?

    errors.add(:base,
               'Valor infinito ou indeterminado em: ' \
               "#{corrompidas.join(', ')}. O borderô não pode ser gravado assim.")
  end
end
