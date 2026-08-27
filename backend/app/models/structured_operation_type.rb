# frozen_string_literal: true

# S8 / **BE-296**…**BE-299**, **DB-283**, **DB-292**, **DB-580** — **tipo de
# operação estruturada**. Catálogo GLOBAL (contrato C1, regra 4).
#
# ## ⚠ NUNCA EXECUTADO EM PRODUÇÃO — DEC-103b
#
# `20220701123654_create_structured_operation_types` é uma das **24 migrations
# que nunca subiram** (`analise-dump-producao.md` §1). Tudo aqui vem espelhado de
# `../sfg/app/models/structured_operation_type.rb` e de
# `../sfg/app/controllers/pub/structured_operation_types_controller.rb`, sem
# corrigir o que parecer errado (DEC-103b, confirmada pela DEC-105).
#
# **O golden desta família tem uma FONTE, não um ORÁCULO.** Ele trava a leitura
# do código de 2022 — não um comportamento validado por três anos de uso, como
# aconteceu no borderô da S6.
#
# ## O irmão que ele NÃO é
#
# `RiskOperationType` (S5) tem o mesmo nome de colunas e um comportamento
# central que este **não** tem: lá o `after_create` gera os subtipos, e
# `has_pre_faturamento` decide o bucket de exposição de toda operação do tipo.
# Aqui **não existe subtipo de operação estruturada** — a coluna homônima está
# no `permit` do legado (`structured_operation_types_controller.rb:135`), **sem
# formulário e sem um único leitor** em todo o repositório (Q-R15). É migrada
# como coluna e **não ganha consumidor**; o spec documenta a ausência.
#
# ## Os quatro tipos semeados são TODOS `is_default`
#
# `../sfg/db/seeds.rb:335-338` cria Fomento, Comissária, Intercompany e Auto
# Liquidável com `is_default: 1`. O `before_destroy`
# (`structured_operation_type.rb:10-15`) recusa remover tipo padrão — logo, na
# prática, **nenhum dos quatro é removível pela tela**. Isso é replicado, com a
# mensagem dizendo por quê (BE-299/FE-300), em vez de deixar o botão sumir sem
# explicação.
class StructuredOperationType < ApplicationRecord
  include GlobalCatalog

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  has_many :operations, class_name: 'StructuredOperation', foreign_key: :operation_type_id,
                        dependent: :restrict_with_error, inverse_of: :operation_type

  validates :title, uniqueness: { case_sensitive: false }
  # BE-297 — a chave é única no BANCO. No legado só o título era único: dois
  # títulos diferentes ("Auto Liquidável" e "Auto-Liquidável") derivavam a mesma
  # `integration_key` e colidiam em silêncio, e é a chave que a integração usa.
  validates :integration_key, uniqueness: { case_sensitive: false }

  # `structured_operation_type.rb:2` — `scope :active, -> { where ('is_active = 1 ') }`,
  # SQL literal com o espaço sobrando. O `active` do `GlobalCatalog` é o mesmo
  # predicado com bind e boolean (DB-283/BE-296).
  scope :manual, -> { where(allow_manual_operations: true, is_active: true) }
  scope :seeded, -> { where(is_default: true) }

  before_destroy :refuse_to_destroy_seeded_type, prepend: true

  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :integration_key, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze

  # BE-299 — a segunda guarda: tipo em uso por operação também não sai.
  # No legado a guarda de `is_default` existia **duas vezes** (no controller e no
  # `before_destroy`) e a de uso não existia — o `dependent: :restrict_with_error`
  # levantava e o ternário degenerado `errors.any? ? :ok : :ok`
  # (`structured_operation_types_controller.rb:108`) devolvia **200** de qualquer
  # jeito. Aqui é uma guarda só, e o 422 é de verdade.
  def self.blocking_dependents
    { 'StructuredOperation' => { foreign_key: :operation_type_id, label: 'operação(ões) estruturada(s)' } }
  end

  private

  # `structured_operation_type.rb:10-15`, ao pé da letra — inclusive a mensagem.
  def refuse_to_destroy_seeded_type
    return unless is_default?

    errors.add(:is_default,
               'Não pode remover tipo padrão. Os quatro tipos do Safegold (Fomento, Comissária, ' \
               'Intercompany e Auto Liquidável) são semeados pelo sistema.')
    throw(:abort)
  end
end
