# frozen_string_literal: true

# S8 / **BE-300**…**BE-306**, **DB-284**, **DB-285**, **DB-582** — a
# **remuneração**: a taxa que o projeto cobra por tipo de operação. Escopada por
# projeto (contrato C1).
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `20220629123512_create_remunerations` e `20220802165837_add_title_to_remuneration`
# são duas das **24 migrations que nunca subiram**. A consulta 8 do dump é
# explícita: *"a tabela `remunerations` **não existe** em produção"*
# (`analise-dump-producao.md` §2). Espelho de
# `../sfg/app/models/remuneration.rb`, sem corrigir o que parecer errado.
#
# **Consequência que fica registrada, e não fechada por conveniência:** a
# pergunta **P-026** ("existe remuneração com taxa fora de 0–100?") **perdeu o
# objeto**. Não há dado de produção contra o qual validar. A DEC-37 decidiu, por
# leitura de código, **não** validar a faixa — 250% passa hoje e continua
# passando. Isso é decisão, não medição.
#
# ## É a única linha que multiplica faturamento
#
# `value` é a taxa em %. Ela entra em `Receipt#fetch` (`receipt.rb:61-63`) como
# `fee`, e o valor faturado é `operation_value × (fee.to_f / 100.0)`. Duas
# implementações divergindo aqui é dinheiro errado — por isso o contrato **C2**:
# **um cálculo, um dono**. O dono é `Charges::ReceiptGenerator` (S6), e
# `Structured::RemunerationCalculator` é a fachada com o golden, sem aritmética
# própria.
#
# ## `title` é DESNORMALIZADO de propósito (decisão B-06, DB-285)
#
# `remuneration.rb:17-19` reescreve `title = operation_type.title` em **todo**
# save. Não é cache: é a coluna que a busca textual usa
# (`remunerations_controller.rb:14`). Trocar por join mudaria o resultado da
# busca para os registros criados antes de `add_title_to_remuneration`, que têm
# `title` NULL até o primeiro save. Ganho estético, custo de paridade.
#
# ## O polimorfismo, e os dois buracos que ele tinha
#
# `operation_type` aponta para `RiskOperationType` (LIQ) **ou**
# `StructuredOperationType` (EST). No legado, `operation_type_type` era string
# livre:
#
# - `operation_class` (`remuneration.rb:31-36`) devolvia **`nil`** para valor
#   desconhecido, e o `nil.where(...)` seguinte dava 500;
# - `beauty_type` (`remuneration.rb:38-46`) devolvia a string **`"???"`**, que
#   ia parar na coluna `kind` do recibo, atravessava a validação de presença e
#   virava um recibo que nenhum filtro achava.
#
# Os dois são fechados pelo `check_constraint` do banco + `inclusion` aqui: tipo
# inválido é **422 na criação**, e `"???"` nunca chega a existir.
class Remuneration < ApplicationRecord
  include ProjectScoped
  include BlockingDependents
  include Auditable

  # As duas classes possíveis, e a sigla de cada uma
  # (`remuneration.rb:31-46`). `Receipt::KIND_RISK`/`KIND_STRUCTURED` são as
  # mesmas duas siglas do outro lado da ponte — declaradas lá, referenciadas
  # aqui: uma sigla, um lugar.
  RISK_TYPE = 'RiskOperationType'
  STRUCTURED_TYPE = 'StructuredOperationType'
  OPERATION_TYPE_TYPES = [RISK_TYPE, STRUCTURED_TYPE].freeze

  # `remuneration.rb:31-36` (`operation_class`) e `:38-46` (`beauty_type`), como
  # tabela em vez de `if/elsif/else`. Sem o ramo do `else`.
  OPERATION_CLASSES = { RISK_TYPE => 'RiskOperation', STRUCTURED_TYPE => 'StructuredOperation' }.freeze
  KINDS = { RISK_TYPE => Receipt::KIND_RISK, STRUCTURED_TYPE => Receipt::KIND_STRUCTURED }.freeze

  belongs_to :operation_type, polymorphic: true, optional: true
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false
  # BE-303 — no legado `has_many :receipts` (`remuneration.rb:4`) está **sem
  # `dependent:`**: apagar a remuneração deixava **recibo órfão**, e como
  # `Receipt belongs_to :remuneration` é obrigatório, qualquer save posterior
  # daquele recibo falhava. Aqui a exclusão é bloqueada, com 422 e a frase
  # nomeando o vínculo.
  has_many :receipts, dependent: :restrict_with_error, inverse_of: :remuneration

  validates :operation_type_id, presence: true
  validates :operation_type_type, presence: true, inclusion: { in: OPERATION_TYPE_TYPES }
  validates :value, presence: true, numericality: true
  validates :title, presence: true
  # `remuneration.rb:11` — a unicidade de aplicação. O índice único composto do
  # banco (DB-284) fecha a corrida que ela não vê, e é o que garante que
  # `Receipt#fetch` (`receipt.rb:47-51`, um `.first`) ache **UMA** taxa.
  validates :operation_type_id,
            uniqueness: { scope: %i[operation_type_type project_id],
                          message: 'já tem remuneração neste projeto para este tipo de operação' }

  # `remuneration.rb:17-19` — em todo save, sem `on:`. BE-304.
  #
  # No legado isto era `self.title = self.operation_type.title` cru: tipo
  # inválido ou inexistente dava `NoMethodError` em `nil` → **500**. Aqui o
  # callback tolera a ausência e a validação de `inclusion`/presença responde
  # **422** com a mensagem certa.
  before_validation :copy_title_from_operation_type

  scope :of_kind, lambda { |operation_type_type|
    operation_type_type.present? ? where(operation_type_type: operation_type_type) : all
  }

  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    where('title ILIKE :q', q: "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%")
  }

  # BE-300 — no legado a listagem **não tem** paginação, ordenação nem total
  # (`remunerations_controller.rb:8-17`): a relação volta inteira e sem
  # `ORDER BY`.
  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'kind' => :operation_type_type,
               'value' => :value, 'created_at' => :created_at },
    default: { operation_type_type: :asc, title: :asc }
  ).freeze

  def self.blocking_dependents
    { 'Receipt' => { foreign_key: :remuneration_id, label: 'recibo(s)' } }
  end

  # `remuneration.rb:31-36`. A classe de operação que esta remuneração cobra.
  # **Sem o `nil` silencioso**: o domínio é fechado no banco e na validação.
  def operation_class
    nome = OPERATION_CLASSES[operation_type_type.to_s]
    return nil if nome.nil?

    nome.safe_constantize
  end

  # `remuneration.rb:38-46`. **Sem o `"???"`.**
  def beauty_type
    KINDS[operation_type_type.to_s]
  end

  # `remuneration.rb:25-29` (`receipt_candidates`) — mora em
  # `Charges::ReceiptGenerator` (contrato **C2**: um cálculo, um dono). Este
  # método é só o escopo, sem instanciar `Receipt` por candidato como o legado
  # fazia (N consultas por linha).
  #
  # **Q-R18, golden E7: operação ENCERRADA continua candidata.** `is_ended` não
  # entra no predicado — nem aqui nem no legado. Replicado.
  def candidate_operations
    klass = operation_class
    return ::StructuredOperation.none if klass.nil?

    klass.where(project_id: project_id, operation_type_id: operation_type_id, receipt_id: nil)
  end

  private

  # **Descoberto ESCREVENDO O TESTE, não lendo o código.**
  #
  # `operation_type` é o getter polimórfico do ActiveRecord: ele
  # **constantiza** `operation_type_type`. Com um valor fora do domínio —
  # `"Qualquer"` — a simples leitura levanta `NameError: uninitialized constant
  # Qualquer` **dentro do `before_validation`**, ou seja, ANTES de a validação
  # de `inclusion` conseguir responder 422. Resultado: **500**, exatamente o
  # modo de falha que o BE-304 existe para eliminar, só que por outra porta.
  #
  # O endpoint já barra pelo `values:` do Grape e o banco pelo
  # `check_constraint`, mas o model precisa aguentar sozinho: seed, console,
  # rake e ETL não passam por nenhum dos dois. O `rescue NameError` deixa a
  # validação falar, e a mensagem que chega ao usuário é a de inclusão.
  def copy_title_from_operation_type
    tipo = begin
      operation_type
    rescue NameError
      nil
    end
    return if tipo.nil?
    return unless tipo.respond_to?(:title)

    self.title = tipo.title
  end
end
