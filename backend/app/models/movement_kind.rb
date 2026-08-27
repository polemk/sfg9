# frozen_string_literal: true

# S6 / **BE-186**, **BE-446**, **BE-447**, **BE-448**, **DB-160**, **DB-433**,
# **DB-563** — tipo de movimentação (a "tarifa" do borderô).
#
# **Catálogo GLOBAL** (C1, regra 4). É ele que decide em qual dos quatro buckets
# a tarifa cai — e, por consequência, a base do IOF e todos os CETs. Errar a
# classificação aqui muda número em 28 mil borderôs.
#
# ## BE-447 — exclusividade dos classificadores, com mensagem de humano
#
# No legado a validação existe (`../sfg/app/models/movement_kind.rb:12-17`) mas
# a mensagem é o erro cru **"Múltiplos tipos Pode ter apenas um dos tipos
# definidos"** — o `errors.add("Múltiplos tipos", …)` usa uma frase como se
# fosse nome de atributo. Aqui a mensagem é pt-BR legível e o
# `check_constraint` do banco fecha a corrida que a validação não vê.
#
# `NULL` conta como zero: no legado `[nil, 1, nil, nil].sum` levanta
# `TypeError`, e as colunas eram `integer` **nullable**. Aqui são `boolean NOT
# NULL DEFAULT false` — o `nil` deixa de existir.
#
# ## `is_title` e `is_liquidation` são PORTADOS SEM CONSUMIDOR
#
# D-74 / Q-B13: as duas colunas existem, têm campo na tela e **nenhuma regra as
# lê** — nem no legado. Portadas como estão, sem inventar semântica.
#
# ## BE-446 — a chave de integração
#
# Derivada do título na **criação** e congelada depois (`GlobalCatalog`). É o
# comportamento do legado (`movement_kind.rb:6-8`), com a diferença de que lá a
# chave continuava no `permit` e a tela a reescrevia: título e chave divergiam
# na primeira edição.
class MovementKind < ApplicationRecord
  include GlobalCatalog

  # O sentido contábil. No legado era o texto pt-BR "Crédito"/"Débito"
  # (`movement_kind.rb:26-27`) gravado na coluna — mesmo tratamento do `status`
  # em `BE-445`: valor estável no banco, rótulo na apresentação.
  KIND_CREDIT = 'credit'
  KIND_DEBIT = 'debit'
  KINDS = [KIND_CREDIT, KIND_DEBIT].freeze
  LEGACY_KIND_LABELS = { KIND_CREDIT => 'Crédito', KIND_DEBIT => 'Débito' }.freeze

  # Os quatro classificadores de taxa. **No máximo um** por tipo (BE-447).
  TAX_CLASSIFIERS = %i[is_advalorem is_desagio is_iof is_liquidation].freeze

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :title, uniqueness: { case_sensitive: false }
  validates :kind, inclusion: { in: KINDS, allow_nil: true, message: 'deve ser crédito ou débito' }
  validate :single_tax_classifier

  # Só os tipos com `is_operation` aparecem na lista de tarifas do formulário —
  # é o único dos flags de exibição que tem leitor no legado
  # (`receivables/new/_body.html.erb`).
  scope :for_operation, -> { where(is_operation: true) }

  # BE-448 — exclusão bloqueada por dependente, com a frase nomeando o vínculo.
  # No legado era `dependent: :restrict_with_error` em duas associações e o
  # controller devolvia **500**.
  def self.blocking_dependents
    {
      'ReceivableTax' => { foreign_key: :movement_kind_id, label: 'tarifa(s) de borderô' }
    }
  end

  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :integration_key, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze

  def self.kind_from_legacy(text) = LEGACY_KIND_LABELS.key(text.to_s.strip)
  def kind_label = LEGACY_KIND_LABELS[kind.to_s]

  # O classificador ativo, ou `nil`. É o que a tela mostra numa coluna só, em
  # vez de quatro caixas marcadas.
  def tax_classifier
    TAX_CLASSIFIERS.find { |flag| public_send(flag) }
  end

  private

  def single_tax_classifier
    marcados = TAX_CLASSIFIERS.count { |flag| public_send(flag) }
    return if marcados <= 1

    errors.add(
      :base,
      'Um tipo de movimentação pode ter no máximo um classificador: ' \
      'AdValorem, Deságio, IOF ou Liquidação.'
    )
  end
end
