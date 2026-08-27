# frozen_string_literal: true

# S10 / BE-320, BE-321, BE-322, BE-715, DB-310, DB-313 — **o indicador**.
#
# Um indicador é o cadastro que descreve *o que* o cliente lança mês a mês. Ele é
# **global** (`project_id` nulo — catálogo compartilhado, contrato C1 regra 4) ou
# **específico** de um projeto.
#
# Quatro comportamentos deste model são observáveis pelo usuário e por isso têm
# **teste golden** (`spec/models/indicator_spec.rb`, caracterizações `G1`, `G2` e
# `G4`). O teste não existe para provar que a regra está certa — existe para
# reprovar quem "consertar" depois sem passar por uma decisão (DEC-30).
#
# ## G1 — as três regras de unicidade (`BE-320`)
#
# Replicadas de `../sfg/app/models/indicator.rb:12-23`, incluindo o efeito
# colateral: dois projetos podem ter específicos homônimos, mas nenhum GLOBAL
# pode usar esse nome depois (a regra (a) olha `Indicator.where(title ...)` sem
# filtrar por projeto).
#
# ## G2 — título em CAIXA ALTA sem acento (`BE-321`, **DEC-89**)
#
# `indicator.rb:38-40` do legado faz `self.title = I18n.transliterate(title).upcase`
# num `before_validation` **sem `on:`** — em todo save. A **DEC-89 mandou
# replicar**, encerrando o conflito em que a spec de `BE-321` pedia "o título
# aparece como digitado". Consequência registrada e sem volta: "Inadimplência"
# vira "INADIMPLENCIA" **no banco**, não só na tela. Se você veio "consertar"
# preservando o que foi digitado, pare: a decisão está escrita e o golden test
# reprova.
#
# ## G2b — a chave (`OPS-312`, **DEC-85**)
#
# Derivada do título **na criação** (`I18n.transliterate(title).downcase.gsub(" ", "_")`),
# **congelada** depois, **sem unicidade** e **sem mudança de formato**. Não use
# `GlobalCatalog.slugify` aqui: ela troca **todo** caractere não alfanumérico por
# sublinhado, e o legado troca **só o espaço** — `"MARGEM S/A"` vira
# `margem_s/a` no legado e `margem_s_a` no slugify. O campo se chama "Chave de
# Integração"; mudar o formato quebraria um consumidor externo em silêncio.
#
# ## G4 — a denormalização (`BE-322`, T-D11)
#
# Renomear um indicador reescreve `title`, `key` e `value_type` de **todas** as
# suas entries, por `update_all` — pulando validações e callbacks e **sem** tocar
# `updated_at`. O resultado é replicado; o que muda é que, acima de
# {PROPAGATION_INLINE_LIMIT} linhas, isso sai do request e vira job. Um indicador
# com 20.000 lançamentos não pode travar a edição do título.
#
# ## Exclusão LÓGICA (`BE-318`, D-66)
#
# O legado declarava `has_many :entries, dependent: :delete_all` — excluir um
# indicador **apagava a série histórica inteira**, sem callback, sem backup, e
# com uma confirmação que dizia apenas "A operação não pode ser desfeita", sem
# mencionar os lançamentos. Na tela de específicos não havia nem confirmação.
# Aqui `#destroy` do serviço marca `discarded_at`; os lançamentos ficam.
class Indicator < ApplicationRecord
  include Auditable

  # Valor único hoje (Q-R32). Modelado como conjunto nomeado, não `enum` do
  # Rails: `enum` com um valor só geraria `Indicator.dinheiro`/`#dinheiro?`, e o
  # valor gravado é o texto em português que o legado grava — a coluna é
  # `string`, o dado migrado traz `"Dinheiro"`, e o formato não pode mudar.
  # Acrescentar "Percentual" amanhã é uma linha aqui, sem migração de dados.
  VALUE_TYPE_MONEY = 'Dinheiro'
  VALUE_TYPES = [VALUE_TYPE_MONEY].freeze

  # **DB-092 (S4)** — o escopo é uma COLUNA, não a inferência de um campo nulo.
  #
  # Antes, `project_id IS NULL` governava a interface inteira: o model, a
  # entity, o serviço de conexões e a linha da tela. O front já falava
  # `scope: "global" | "project"` — o banco é que ainda não. Agora fala, e um
  # CHECK garante que as duas representações não divirjam (ver a migration
  # `20260826235000`). Sem esse CHECK a coluna seria só mais um campo para sair
  # de sincronia.
  SCOPE_GLOBAL = 'global'
  SCOPE_PROJECT = 'project'
  SCOPES = [SCOPE_GLOBAL, SCOPE_PROJECT].freeze

  # Acima disto a propagação vira job. O número não é mágico: é o ponto em que
  # um `UPDATE` síncrono dentro do request começa a ser percebido como travada.
  PROPAGATION_INLINE_LIMIT = 500

  belongs_to :project, optional: true

  has_many :project_indicator_connections, dependent: :restrict_with_error, inverse_of: :indicator
  has_many :projects, through: :project_indicator_connections
  # **Sem `dependent: :delete_all`** — é o D-66. `restrict_with_error` garante
  # que nem um `destroy` acidental fora do serviço leve a série junto; o caminho
  # normal é `discard!`.
  has_many :entries, class_name: 'IndicatorEntry', dependent: :restrict_with_error, inverse_of: :indicator

  # DB-313 — a "Instrução". **ActionText já existe na base** (`action_text/engine`
  # em `config/application.rb:13`, `action_text_rich_texts` em `db/schema.rb:31`,
  # `User#biography` em `app/models/user.rb:68`). Nada de coluna
  # `description_html` paralela.
  #
  # ⚠ **Ponto crítico do ETL (S14):** o texto NÃO vive em `indicators`, vive em
  # `action_text_rich_texts`. Qualquer export/import precisa levar essa tabela
  # junto ou **o conteúdo se perde**, e os corpos do legado podem estar
  # URL-escapados (daí o `CGI.unescape` nas views de contrato).
  has_rich_text :description

  validates :title, presence: true, length: { maximum: 255 }
  validates :key, presence: true, length: { maximum: 255 }
  validates :value_type, presence: true, inclusion: { in: VALUE_TYPES }
  validates :scope, presence: true, inclusion: { in: SCOPES }

  validate :title_must_be_unique_across_scopes

  before_validation :normalize_title
  before_validation :derive_scope
  before_validation :derive_key, on: :create
  before_validation :apply_default_value_type, on: :create

  after_save :propagate_denormalized_fields

  scope :kept, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }
  # **Pela coluna**, não por `IS NULL` (DB-092). O plano vira igualdade sobre
  # `index_indicators_on_scope_and_title` em vez de varredura com `IS NULL`.
  scope :global, -> { where(scope: SCOPE_GLOBAL) }
  scope :specific, -> { where(scope: SCOPE_PROJECT) }
  scope :active, -> { where(is_active: true) }

  # Globais **mais** os específicos deste projeto — é o conjunto que a tela de
  # "Indicadores específicos" oferece (`BE-707`).
  scope :available_for, lambda { |project|
    project_id = project.respond_to?(:id) ? project.id : project
    where(project_id: [nil, project_id])
  }

  # Busca por texto. `ILIKE` com bind e `sanitize_sql_like` — o legado
  # interpolava o operador e montava o padrão dentro da string (`Dev.ilike`), de
  # modo que `100%` e `a'b` viravam padrão SQL em vez de texto literal.
  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
    where('title ILIKE :q OR key ILIKE :q', q: padrao)
  }

  # `BE-312` — ordenação dirigida pelo cliente, com allowlist REAL.
  #
  # Corrige três defeitos de uma vez em `../sfg/app/models/indicator.rb:52-81`:
  # (a) `prepare_ordering` chamava `Segment.get_ordering_key`/`get_ordering_style`
  # em vez dos métodos do próprio `Indicator`; (b) `get_ordering_key("key")`
  # devolvia `"integration_key"` — **coluna que não existe** em `indicators`
  # (a coluna é `key`) → `PG::UndefinedColumn`, 500 ao ordenar por "Chave";
  # (c) a chave era interpolada no SQL. Na UI só "Título" era clicável, o que
  # mascarava (b) e (c). Este é o achado **A-5** do DEC-85.
  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :key, 'created_at' => :created_at },
    default: { title: :asc }
  ).freeze

  # --- Estado ---------------------------------------------------------------

  # Lê a COLUNA (DB-092). O `||` só cobre o instante entre `Indicator.new` e o
  # `before_validation` que a deriva — nunca um registro persistido, onde o
  # CHECK do banco já garantiu a coerência com `project_id`.
  def global?
    (scope.presence || derived_scope) == SCOPE_GLOBAL
  end

  def specific?
    !global?
  end

  def discarded?
    discarded_at.present?
  end

  # Exclusão LÓGICA (D-66). Não toca nos lançamentos: eles são o histórico.
  def discard!
    return true if discarded?

    update!(discarded_at: Time.current)
  end

  def undiscard!
    return true unless discarded?

    update!(discarded_at: nil)
  end

  # O que uma exclusão afeta, **antes** de qualquer escrita — é o que a
  # confirmação de `FE-315` mostra. No legado a confirmação dizia só "A operação
  # não pode ser desfeita" e o `delete_all` levava tudo junto, calado.
  def deletion_impact
    {
      entries_count: entries.count,
      projects: projects.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
    }
  end

  private

  # DEC-89 — em **todo** save, não só na criação. `to_s` porque
  # `I18n.transliterate(nil)` levanta **antes** da validação de presença: no
  # legado `title` nulo dava 500; aqui dá 422.
  def normalize_title
    self.title = I18n.transliterate(title.to_s).upcase.strip.presence
  end

  # DEC-85 — o formato é o do legado (`indicator.rb:44`): transliterar,
  # minúsculas, **só o espaço** vira sublinhado. Nunca `slugify`.
  def derive_key
    return if key.present?

    self.key = I18n.transliterate(title.to_s).downcase.gsub(' ', '_').presence
  end

  def apply_default_value_type
    self.value_type = VALUE_TYPE_MONEY if value_type.blank?
  end

  # **DB-092** — o escopo acompanha `project_id` em TODO save, não só na
  # criação: promover/rebaixar um indicador por `update(project_id: ...)` sem
  # atualizar a coluna esbarraria no CHECK do banco e viraria 500. Derivando
  # aqui, vira o resultado certo.
  def derive_scope
    self.scope = derived_scope
  end

  def derived_scope
    project_id.nil? ? SCOPE_GLOBAL : SCOPE_PROJECT
  end

  # **G1** — as três regras, replicadas de `indicator.rb:12-23`.
  #
  # A comparação do legado é `where("title ILIKE LOWER(?)", title)` — sem `%`, ou
  # seja, igualdade insensível a caixa. A insensibilidade a acento vem do
  # armazenamento (o título já foi transliterado). Aqui a comparação é
  # `unaccent(lower(title))`, que dá o mesmo resultado e continua valendo se
  # algum dia entrar título acentuado pelo ETL.
  #
  # **A única divergência deliberada** em relação ao legado: `ILIKE` trata `%` e
  # `_` do título como curinga, então um indicador chamado `TAXA_MEDIA` fazia o
  # legado recusar `TAXAXMEDIA` como duplicado. Aqui a comparação é de
  # igualdade. É a mesma correção que a S3 fez no `Dev.ilike` da busca
  # (`GlobalCatalog#search`, OPS-056), pelo mesmo motivo, e está registrada em
  # `improvements-log.md`.
  def title_must_be_unique_across_scopes
    return if title.blank?

    if global?
      # (a) global não repete título de NENHUM outro — nem global, nem
      # específico. É esta linha que produz o efeito colateral replicado.
      errors.add(:title, 'Já utilizado') if same_title_scope.exists?
    else
      # (b) específico não repete título de global.
      errors.add(:title, 'Já utilizado por indicador global') if same_title_scope.global.exists?
      # (c) específico não repete título de outro específico DO MESMO projeto.
      errors.add(:title, 'Já utilizado nesse projeto') if same_title_scope.where(project_id: project_id).exists?
    end
  end

  def same_title_scope
    scope = self.class.where('unaccent(lower(indicators.title)) = unaccent(lower(?))', title)
    scope = scope.where.not(id: id) if persisted?
    scope
  end

  # **G4** — o histórico é reescrito (T-D11 / DEC-30).
  #
  # Duas diferenças em relação ao legado, e nenhuma delas muda o resultado:
  #
  # 1. **Só roda quando um dos três campos mudou.** O legado roda em todo save;
  #    como `update_all` não toca `updated_at`, reescrever os mesmos valores é
  #    literalmente invisível — a guarda economiza escrita sem mudar nada.
  # 2. **Acima de {PROPAGATION_INLINE_LIMIT} linhas vira job.** O `update_all`
  #    síncrono dentro do request é o que trava a edição do título de um
  #    indicador com 20.000 lançamentos.
  def propagate_denormalized_fields
    return unless saved_change_to_title? || saved_change_to_key? || saved_change_to_value_type?

    total = entries.count
    return if total.zero?

    if total > PROPAGATION_INLINE_LIMIT
      PropagateIndicatorFieldsJob.perform_later(id)
    else
      IndicatorEntry.propagate_from(self)
    end
  end
end
