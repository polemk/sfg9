# frozen_string_literal: true

# S11 / DB-085, DB-121, DB-131, DB-566 — **a base dos padrões de disponibilidade**.
#
# Uma tabela, duas classes (STI): `GlobalAvailabilityTemplate` é o catálogo —
# `project_id` nulo, **não escopado** — e `ProjectAvailabilityTemplate` é o
# padrão de um projeto, escopado por `ProjectScoped`. As duas regras são opostas
# de propósito; a mesma tensão que existe entre `GlobalCatalog` e `ProjectScoped`.
#
# ## A hierarquia deixou de morar em nove colunas
#
# O legado guardava a árvore em `numeric_first_level`, `numeric_second_level`,
# `numeric_third_level`, `max_level`, `parent_level`, `is_upper_level`,
# `position` (string), `parent_position` (string) e `top_parent_id` com
# default `0`. Aqui são três: `level`, `position` e `sort_key`.
#
# `sort_key` é a **única** chave de ordem, e o caminho legível ("1.2.3") é
# derivado dela — o legado mantinha os dois em paralelo e eles divergiam
# (`reorder_all!` gravava `position` sem tocar em `parent_position` em alguns
# ramos).
#
# ## O nível é derivado do pai, não calculado com OR bit a bit
#
# `global_availability_template.rb:52` fazia `self.numeric_first_level |=
# self.parent_template.numeric_first_level` — **OR bit a bit**, não atribuição.
# Um filho de nível 2 herdando de 5 virava **7**. Funcionava por acidente
# enquanto os valores fossem `0`/`nil`. Aqui é `parent.level + 1`, e
# profundidade acima de 3 é recusada.
class AvailabilityTemplate < ApplicationRecord
  # ---------------------------------------------------------------------
  # Conjuntos fechados (DC-28)
  # ---------------------------------------------------------------------
  # **`is_credit?`/`is_debit?` comparam o CÓDIGO, nunca a string traduzida.**
  # No legado (`availability_template.rb:74-80`) a comparação era contra
  # `beauty_op_type`, que devolve `""` para qualquer código desconhecido — e
  # `"" == "Débito"` é falso, então **tudo que não fosse `D` virava crédito**
  # na soma. Aqui `operation_type` é conjunto fechado validado, e um valor fora
  # dele é recusado na gravação em vez de virar crédito em silêncio.
  OPERATION_TYPES = {
    'C' => 'Crédito',
    'D' => 'Débito',
    'S' => 'Saldo',
    'M' => 'Movimentação'
  }.freeze

  DEADLINE_TYPES = {
    'CP' => 'Curto Prazo',
    'LP' => 'Longo Prazo'
  }.freeze

  JOB_STATES = %w[pending running done failed].freeze

  MAX_LEVEL = 3

  # Largura do segmento de `sort_key`. Quatro dígitos cobrem 9.999 irmãos —
  # muito além dos 12 que derrubavam a ordenação lexicográfica do legado.
  SORT_SEGMENT_WIDTH = 4

  self.inheritance_column = :type

  # S0 / DB-460 — as colunas `job_state`/`job_progress` na própria entidade, para
  # que quem chega DEPOIS do evento (a aba fechada, o F5, o outro operador) saiba
  # que há operação em curso. O socket é só o aviso de que mudou.
  include JobProgressable

  belongs_to :project, optional: true
  belongs_to :parent_template, class_name: 'AvailabilityTemplate', optional: true, inverse_of: :child_templates
  belongs_to :top_parent, class_name: 'AvailabilityTemplate', optional: true, inverse_of: false
  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false
  belongs_to :locked_by, class_name: 'User', optional: true, inverse_of: false

  has_many :child_templates, class_name: 'AvailabilityTemplate', foreign_key: :parent_template_id,
                             inverse_of: :parent_template, dependent: :restrict_with_error

  validates :title, length: { maximum: 255 }

  # **DEC-128.4 / DEC-127 — título vazio é "não se aplica", e 90 linhas têm.**
  #
  # Medido no dump de 31/05/2025: **90 de 2.705** padrões chegam com o título em
  # branco. Gerar título a partir do contexto foi **recusado** pelo usuário —
  # seria texto que ninguém escreveu aparecendo na tela como se fosse do cliente.
  #
  # A exigência continua de pé para tudo que nasce no ai9; só a linha herdada
  # (`legacy_id` presente) entra como está. É o par obrigatório do índice parcial
  # de `20260827020000_unicidade_parcial_onde_o_legado_diz_nao_se_aplica`
  # (`AND title <> ''`): sem esta linha o índice aceita e o model recusa, que é a
  # armadilha da DEC-127 — parece resolvido e não está.
  validates :title, presence: true, unless: -> { legacy_id.present? }
  validates :operation_type, presence: true, inclusion: { in: OPERATION_TYPES.keys,
                                                          message: 'não é uma natureza de operação conhecida' }
  validates :deadline_type, presence: true, inclusion: { in: DEADLINE_TYPES.keys,
                                                         message: 'não é um prazo conhecido' }
  validates :level, inclusion: { in: 1..MAX_LEVEL, message: "a hierarquia tem no máximo #{MAX_LEVEL} níveis" }
  validates :job_state, inclusion: { in: JOB_STATES }, allow_nil: true

  validate :parent_must_be_consistent
  validate :mandatory_chain_must_be_mandatory

  before_validation :normalize_title
  before_validation :derive_level_and_top_parent

  # `active` do legado: ativo **e** destravado (`availability_template.rb:12`).
  scope :active, -> { where(is_active: true, is_locked: false) }
  scope :active_ignore_lock, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }
  scope :mandatory, -> { where(is_mandatory: true) }
  scope :roots, -> { where(parent_template_id: nil) }
  # A ordem da árvore inteira, numa consulta. Substitui `all_ids_by_position`,
  # que no legado fazia **uma consulta por nó de 1º e 2º nível** e depois
  # remontava a ordem com um `JOIN (VALUES …)` construído por interpolação.
  scope :in_tree_order, -> { order(:sort_key, :id) }

  # Busca por **substring** — o legado montava `"title #{Dev.ilike} "` sem
  # placeholder e passava o padrão como segundo argumento de `where!`, o que
  # produz SQL inválido: **qualquer texto digitado derrubava a requisição**
  # (D-06). O termo aqui é escapado por `sanitize_sql_like` e entra por bind.
  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
    where('availability_templates.title ILIKE :q', q: padrao)
  }

  ORDERING = Sfg::Sortable.new(
    allowed: {
      'title' => 'availability_templates.title',
      'position' => 'availability_templates.sort_key',
      'operation_type' => 'availability_templates.operation_type',
      'deadline_type' => 'availability_templates.deadline_type',
      'created_at' => 'availability_templates.created_at'
    },
    # **D-125 — a ordem é a HIERARQUIA, não `default_position`.**
    #
    # A DEC-79 mandou criar a coluna `default_position` no ai9 e ordenar por ela,
    # "como o legado pretende". A análise do dump de produção (26/08/2026)
    # mostrou que a intenção nunca virou realidade: a coluna **não existe no
    # banco** — zero ocorrências no dump inteiro — e nenhuma migration a cria.
    # `availability_templates_controller.rb:22` emite `ORDER BY default_position`
    # e o Postgres levanta `UndefinedColumn`: **a listagem de padrões está
    # quebrada em produção há anos**.
    #
    # Não há o que replicar — é a exceção 3 do DEC-30 ("não existe legado a
    # replicar"). A coluna continua existindo (a DEC-79 a criou, e o ETL a
    # carrega se algum dia ela aparecer), mas **não é a chave de ordem**.
    default: { 'availability_templates.sort_key' => :asc }
  ).freeze

  # ---------------------------------------------------------------------
  # Leitura
  # ---------------------------------------------------------------------

  # O caminho legível: `"1.2.3"`. Derivado de `sort_key`, nunca guardado à
  # parte — no legado `position` e `parent_position` eram colunas separadas e
  # divergiam.
  def position_path
    sort_key.to_s.split('.').map { |segmento| segmento.to_i.to_s }.join('.')
  end

  def operation_type_label = OPERATION_TYPES.fetch(operation_type.to_s, '')
  def deadline_type_label = DEADLINE_TYPES.fetch(deadline_type.to_s, '')

  # DC-28 — comparação por **código**.
  def credit? = operation_type.to_s == 'C'
  def debit? = operation_type.to_s == 'D'

  def root? = parent_template_id.blank?

  # "Tem filho" no sentido do legado (`has_child?`): filho **ativo**, ignorando
  # bloqueio. É o conjunto que a soma do nó pai percorre.
  def children_for_sum
    self.class.where(parent_template_id: id).active_ignore_lock
  end

  def has_children? = children_for_sum.exists?

  def base_level? = level == 1

  # Nós de 1º nível **anteriores** a este, na ordem da árvore. É a base do
  # saldo acumulado (`previous_level_templates` do legado).
  def previous_base_templates
    siblings_at_base.where(position: ...position).order(position: :desc)
  end

  def next_base_templates
    siblings_at_base.where('availability_templates.position > ?', position).order(position: :asc)
  end

  def locked? = is_locked?

  # Os ids deste padrão e de toda a descendência, numa **CTE recursiva**: custo
  # linear no tamanho da subárvore. O legado descia a árvore com recursão em
  # Ruby, uma consulta por nó (`background_remove_templates`).
  def subtree_ids = self.class.subtree_ids_for(id)

  def self.subtree_ids_for(root_id)
    return [] if root_id.blank?

    sql = <<~SQL.squish
      WITH RECURSIVE subarvore AS (
        SELECT id FROM availability_templates WHERE id = :root
        UNION ALL
        SELECT t.id FROM availability_templates t
          JOIN subarvore s ON t.parent_template_id = s.id
      )
      SELECT id FROM subarvore
    SQL

    AvailabilityTemplate.connection.select_values(
      AvailabilityTemplate.sanitize_sql_array([sql, { root: root_id }])
    )
  end

  private

  def siblings_at_base
    raise NotImplementedError, "#{self.class.name} precisa declarar `siblings_at_base`"
  end

  # **Sem `.presence`** (DEC-128.4): a coluna é `null: false` e a linha herdada
  # pode ter título vazio. Transformar '' em `nil` trocava um título em branco —
  # que a decisão manda preservar — por uma violação de NOT NULL no meio da carga.
  def normalize_title
    self.title = title.to_s.strip
  end

  # **O nível vem do pai, sempre.** E o `top_parent` sobe a cadeia até a raiz —
  # sem o default `0` do legado, que gerava órfãos apontando para o id 0.
  def derive_level_and_top_parent
    if parent_template_id.blank?
      self.level = 1
      self.top_parent_id = nil
    else
      pai = parent_template
      return if pai.nil?

      self.level = pai.level.to_i + 1
      self.top_parent_id = pai.top_parent_id.presence || pai.id
    end
  end

  # Pai de tipo errado, pai de outro projeto e pai fundo demais são recusados
  # **no servidor**. O legado aceitava qualquer `parent_template_id` que
  # chegasse no `permit` — inclusive de outro projeto (FE-148).
  def parent_must_be_consistent
    return if parent_template_id.blank?

    pai = parent_template
    if pai.nil?
      errors.add(:parent_template_id, 'não existe')
      return
    end

    errors.add(:parent_template_id, 'precisa ser do mesmo tipo de padrão') unless pai.type == type
    errors.add(:parent_template_id, 'não pode ser o próprio padrão') if pai.id == id
    return unless pai.level.to_i >= MAX_LEVEL

    errors.add(:parent_template_id, "a hierarquia tem no máximo #{MAX_LEVEL} níveis")
  end

  # BE-139 — **obrigatoriedade hierárquica**: um padrão só pode ser obrigatório
  # se a cadeia acima também for. Regra do legado
  # (`availability_template.rb:2-8`), preservada. O que muda é que lá ela
  # comparava `is_mandatory` inteiro; aqui é booleano.
  def mandatory_chain_must_be_mandatory
    return unless is_mandatory?
    return if parent_template_id.blank?

    pai = parent_template
    return if pai.nil?

    raiz = top_parent_id.present? ? self.class.find_by(id: top_parent_id) : pai
    return if pai.is_mandatory? && (raiz.nil? || raiz.is_mandatory?)

    errors.add(:is_mandatory, 'só pode ser marcado se os níveis acima também forem obrigatórios')
  end
end
