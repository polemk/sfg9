# frozen_string_literal: true

# S5 / BE-279, DB-234, OPS-232 — **tipo de movimentação de risco**. Catálogo GLOBAL.
#
# O `credit_type` é o **sinal** com que o movimento entra no recálculo do saldo
# da operação: `D` → `+1`, `C` → `−1`
# (`../sfg/app/models/risk_movement_type.rb:53-61`). No legado, um valor fora de
# `('C','D')` fazia `parse_credit_type_value` devolver **0** e o movimento
# simplesmente não mexia no saldo, sem erro nenhum. Aqui há `enum` no model
# **e** check constraint no banco.
#
# ### B-09 — a resolução deixa de ser por título literal
#
# O legado achava os três tipos funcionais por
# `where(title: "Liberação do Recurso", is_default: 1).first.id`
# (`:73-82`). Renomear o tipo pela tela de administração — que é uma tela
# **aberta ao usuário** — quebrava a criação de movimentos, e o erro só aparecia
# no `NoMethodError` de `nil.id` na hora de lançar.
#
# Aqui a resolução é por `integration_key`, que nasce derivada do título e é
# **congelada** (DC-22): renomear o título não a muda. As três chaves abaixo são
# **CONTRATO** — e, quando o tipo não existe, o erro é de negócio e é levantado
# **antes** de qualquer gravação, nomeando a chave que falta.
#
# ### `credit_type_description` deixou de ser coluna
#
# No legado era gravada uma vez, no create, e nunca mais recalculada: trocar o
# tipo de crédito na edição deixava a descrição errada para sempre — e a
# ordenação da tela ordenava por ela. Aqui é derivada do enum.
class RiskMovementType < ApplicationRecord
  include GlobalCatalog

  # As três chaves funcionais. São contrato com a S7 (recálculo, transferência).
  RELEASE_KEY = 'liberacao_do_recurso'
  TRANSFER_OUT_KEY = 'valor_transferido'
  TRANSFER_IN_KEY = 'transferencia_recebida'

  # Erro de NEGÓCIO, não `NoMethodError`: diz qual chave falta e é levantado
  # antes de gravar qualquer coisa.
  class MissingFunctionalType < StandardError
    def initialize(key)
      super("Tipo de movimentação obrigatório não encontrado: «#{key}». " \
            'Rode `rake reference:seed` — a chave de integração é contrato do módulo de risco.')
    end
  end

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  # Rails 8, valores string. O que fica GRAVADO é `'C'`/`'D'`, exatamente como
  # no legado.
  #
  # **Cuidado com a leitura, e é por isso que existe `#credit_type_code`:** o
  # `enum` faz `tipo.credit_type` devolver o **rótulo** (`'debit'`), não o valor
  # da coluna. O contrato com o legado, com o ETL e com a API é `'C'`/`'D'` —
  # então é `credit_type_code` que a entity expõe. Um teste de request pegou
  # isso: a resposta saía com `"debit"` onde a tela e o ETL esperam `"D"`.
  enum :credit_type, { credit: 'C', debit: 'D' }, validate: true

  validates :title, uniqueness: { case_sensitive: false }
  validates :integration_key, uniqueness: { case_sensitive: false }

  # Réplica do `before_destroy` do legado (`risk_movement_type.rb:13-18`), que
  # existe nos DOIS catálogos de tipo. Faltava só aqui — e o request spec pegou:
  # o `destroy` de um tipo semeado respondia 200 e removia a linha.
  before_destroy :refuse_to_destroy_seeded_type, prepend: true

  # `manual` = o que o usuário pode lançar: nem transferência (o sistema gera o
  # espelho) nem exclusivo do sistema.
  scope :manual, -> { where(is_transfer: false, is_system_exclusive: false, is_active: true) }
  scope :transfers, -> { where(is_transfer: true) }

  ORDERING = Sfg::Sortable.new(
    allowed: {
      'title' => :title, 'key' => :integration_key,
      # No legado esta chave apontava para `credit_type_description`, que virou
      # derivada. `credit_type` ordena `C` antes de `D` — "Crédito" antes de
      # "Débito", que é a mesma ordem visível.
      'credit_type' => :credit_type,
      'system_exclusive' => :is_system_exclusive,
      'created_at' => :created_at
    },
    default: { title: :asc }
  ).freeze

  def self.blocking_dependents
    { 'RiskMovement' => { foreign_key: :movement_type_id, label: 'movimento(s) de risco' } }
  end

  class << self
    # OPS-232 / B-09 — os três tipos funcionais, por chave. Levantam
    # `MissingFunctionalType` em vez de devolver `nil`.
    def release = fetch_functional!(RELEASE_KEY)
    def transfer_out = fetch_functional!(TRANSFER_OUT_KEY)
    def transfer_in = fetch_functional!(TRANSFER_IN_KEY)

    def fetch_functional!(key)
      find_by(integration_key: key) || raise(MissingFunctionalType, key)
    end
  end

  # O valor **gravado** (`'C'`/`'D'`), não o rótulo do enum. É este que vai para
  # a API e para o ETL.
  def credit_type_code
    self.class.credit_types[credit_type]
  end

  # Derivada, nunca coluna.
  def credit_type_description
    credit? ? 'Crédito' : 'Débito'
  end

  # O sinal do movimento no recálculo do saldo (`parse_credit_type_value`).
  def credit_type_value
    credit? ? -1 : 1
  end

  private

  def refuse_to_destroy_seeded_type
    return unless is_default?

    errors.add(:is_default, 'Não pode remover tipo padrão')
    throw(:abort)
  end
end
