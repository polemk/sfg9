# frozen_string_literal: true

# S6 / **BE-187**, **DB-162** — o **pacote de cobrança**. Dona por **DEC-63**.
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `20220707164909_create_charges` é uma das **24 migrations que nunca subiram**:
# a tabela `charges` **não existe** no banco de produção (conferido no dump —
# não há `COPY public.charges`). A regra abaixo vem espelhada do código de 2022
# (`../sfg/app/models/charge.rb`), **sem corrigir o que parecer errado**, e todo
# golden desta família carrega a marca com arquivo e linha.
#
# O que isso muda na prática: aqui o golden tem uma **fonte**, não um
# **oráculo**. Ele trava a leitura do código de 2022 — não um comportamento
# validado por três anos de uso, como acontece no borderô.
#
# ## A restrição arquitetural, preservada (D-B11)
#
# O comentário original da migration diz: *"jamais relacionar cobranças e ops
# diretamente, deve-se usar o receipt como referência para evitar problemas de
# escalabilidade nas tabelas de operações"*. Não há coluna de operação aqui, e
# não haverá: o caminho é sempre `charge → receipts → operation`.
#
# ## `done` bloqueia no SERVIDOR (D-18)
#
# No legado o bloqueio de "Faturado" existia **só na tela**
# (`charges/show/_body.js.erb`): a API aceitava a alteração. Aqui recusa.
class Charge < ApplicationRecord
  include ProjectScoped
  include BlockingDependents
  include Auditable

  # Os três estados. No legado eram os textos pt-BR "Edição", "Disponível" e
  # "Faturado" gravados na coluna (`charge.rb:19-21`) — mesmo tratamento do
  # `status` do borderô (BE-445): valor estável no banco, rótulo na apresentação.
  STATE_EDITING = 'editing'
  STATE_AVAILABLE = 'available'
  STATE_DONE = 'done'
  STATES = [STATE_EDITING, STATE_AVAILABLE, STATE_DONE].freeze
  LEGACY_STATE_LABELS = {
    STATE_EDITING => 'Edição', STATE_AVAILABLE => 'Disponível', STATE_DONE => 'Faturado'
  }.freeze

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false
  has_many :receipts, dependent: :restrict_with_error, inverse_of: :charge

  validates :date, presence: true
  validates :state, presence: true, inclusion: { in: STATES }

  after_initialize :apply_default_state, if: :new_record?

  scope :in_state, ->(state) { state.present? ? where(state: state) : all }
  scope :in_month, ->(month) { month.present? ? where('EXTRACT(MONTH FROM date) = ?', month.to_i) : all }
  # **Ano em branco é opção válida** (FE-180). No legado o filtro de ano não
  # tinha alternativa vazia: era impossível ver todas as cobranças de uma vez.
  scope :in_year, ->(year) { year.present? ? where('EXTRACT(YEAR FROM date) = ?', year.to_i) : all }

  ORDERING = Sfg::Sortable.new(
    allowed: { 'date' => :date, 'state' => :state, 'value' => :value, 'created_at' => :created_at },
    default: { date: :desc }
  ).freeze

  # Exclusão bloqueada por recibo vinculado. No legado o
  # `dependent: :restrict_with_error` levantava e o controller devolvia **500**;
  # aqui é 422 com a frase nomeando o vínculo.
  def self.blocking_dependents
    { 'Receipt' => { foreign_key: :charge_id, label: 'recibo(s)' } }
  end

  def self.state_from_legacy(text) = LEGACY_STATE_LABELS.key(text.to_s.strip)
  def state_label = LEGACY_STATE_LABELS[state.to_s]
  def done? = state == STATE_DONE

  # `../sfg/app/models/charge.rb:48-63` (`calc!`) — os totais denormalizados.
  #
  # Duas diferenças, e as duas são medidas do próprio código legado:
  #
  # 1. O legado fazia **cinco** consultas de agregação (`liq.sum`, `est.sum`
  #    ×2, `liq.count`, `est.count`) mais um `receipts.count` (`:54-60`). Aqui é **uma**
  #    consulta agrupada por `kind` — o resultado é idêntico e provado por
  #    teste, que é a condição do Princípio 9.
  # 2. O legado terminava com `self.save` (`:62`), ignorando o retorno. Aqui é `save!`
  #    dentro da transação de quem chamou: total que não gravou não pode passar
  #    por gravado.
  def recalculate!
    linhas = receipts.reload.group(:kind).pluck(
      Arel.sql('kind'), Arel.sql('SUM(value)'), Arel.sql('SUM(operation_value)'), Arel.sql('COUNT(*)')
    )
    por_tipo = linhas.to_h { |kind, valor, operacao, total| [kind, [valor || 0, operacao || 0, total]] }

    liq = por_tipo[Receipt::KIND_RISK] || [0, 0, 0]
    est = por_tipo[Receipt::KIND_STRUCTURED] || [0, 0, 0]

    self.value = liq[0] + est[0]
    self.risk_operations_value = liq[1]
    self.structured_operations_value = est[1]
    self.total_operations_value = risk_operations_value + structured_operations_value
    self.risk_operations_count = liq[2]
    self.structured_operations_count = est[2]
    self.receipts_count = liq[2] + est[2]

    save!
    self
  end

  private

  # `charge.rb:22-24` — `after_initialize` gravando o estado inicial.
  def apply_default_state
    self.state ||= STATE_EDITING
  end
end
