# frozen_string_literal: true

# S4 / BE-066, DB-052..DB-056 — **fornecedor**, a contraparte das renegociações.
#
# Escopado por projeto (**C1**): `include ProjectScoped`. O legado aplicava o
# escopo na busca (`@providers.where!(project_id: …)`) e **não** no
# `fetch_provider` — `Provider.find(params[:id])`, sem escopo, servia
# `edit`/`update`/`destroy` de qualquer projeto. Aqui não há caminho de leitura
# fora de `for_project`.
#
# **Documento é o par `(document_type, document)` e continua OPCIONAL** (DC-11).
# O legado tinha duas colunas (`cnpj` e `cpf`) e a regra "ao menos um" estava
# **comentada** no próprio model (`provider.rb:36-38`) — a base quase certamente
# tem fornecedor sem documento, e exigi-lo agora reprovaria dado histórico. O
# que muda é que, **quando há documento, ele é validado de verdade**, com dígito
# verificador, por `Sfg::Document`.
#
# **`cnaes` e `atividades` viram UM `jsonb`: `activities`** (D-25). No legado
# `cnaes` era **YAML** (`serialize :cnaes`) e `atividades` era **JSON dentro de
# uma coluna de texto**, na mesma tabela — dois formatos para a mesma coisa, e o
# YAML ainda é superfície de desserialização. O ETL da S14 lê o YAML legado com
# carga **segura** (classes permitidas) e grava aqui.
#
# O logo é ActiveStorage pelo motor único (DEC-91). Paperclip **não** é portado:
# as 4 colunas `logo_*` não são recriadas, e `has_logo?` deixa de existir — o
# legado tratava a string literal `"missing.jpg"` como ausência de arquivo.
class Provider < ApplicationRecord
  include ProjectScoped
  include BlockingDependents
  include Attachable

  sfg_attachment :logo

  belongs_to :author, class_name: 'User', foreign_key: :user_id, optional: true, inverse_of: false

  validates :title, presence: true, length: { maximum: 255 }
  validates :integration_key, presence: true, length: { maximum: 255 }

  # **DEC-125 / DEC-127 — a unicidade vale entre as linhas que o ai9 criar.**
  #
  # Medido no dump de 31/05/2025: 6 grupos, **163 das 289 linhas**, um deles com
  # 119. Só 132 pares distintos — com a unicidade cheia, **157 fornecedores não
  # entram**. Dentro de cada grupo os TÍTULOS são todos distintos, e as chaves
  # repetidas estão em CAIXA e com acento (`SSA`, `Fornecedor`, `Renegociação`,
  # `Fidcs`, `Acionista`, `Colaboradores`) — forma que `GlobalCatalog.slugify`
  # nunca produz. São **rótulos de classificação digitados por gente**, não
  # chaves de integração.
  #
  # `if:` + `conditions:` são o espelho EXATO do índice parcial criado por
  # `20260827020000_unicidade_parcial_onde_o_legado_diz_nao_se_aplica`
  # (`WHERE legacy_id IS NULL`). Mudar um sem o outro devolve o bloqueio: com o
  # índice parcial e esta validação intacta, a carga ainda parava em
  # `Integration key já está em uso neste projeto` — foi assim que a DEC-127
  # nasceu.
  validates :integration_key,
            uniqueness: { scope: :project_id, message: 'já está em uso neste projeto',
                          conditions: -> { where(legacy_id: nil) } },
            if: -> { legacy_id.nil? }
  validates :document_type, inclusion: { in: Sfg::Document::TYPES, message: 'deve ser CPF ou CNPJ' },
                            allow_nil: true
  validates :document, uniqueness: { scope: %i[project_id document_type],
                                     message: 'já está cadastrado neste projeto' },
                       allow_nil: true

  validate :document_pair_is_coherent

  before_validation :normalize_strings
  before_validation :derive_title_from_registry, on: :create
  # A chave é derivada do título **na criação** e **congelada** depois (DC-22),
  # exatamente como nos catálogos globais. É chave de integração: recalculá-la
  # em silêncio quebra consumidor externo.
  before_validation :derive_integration_key, on: :create

  scope :active, -> { where(is_active: true) }

  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
    digitos = termo.gsub(/\D/, '')
    if digitos.present?
      where('title ILIKE :q OR integration_key ILIKE :q OR document LIKE :d', q: padrao, d: "%#{digitos}%")
    else
      where('title ILIKE :q OR integration_key ILIKE :q', q: padrao)
    end
  }

  # O legado só conhecia a chave `title` — e devolvia `nil` para qualquer outra,
  # produzindo `nil + " "` → **500** a partir da barra de endereço.
  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :title, 'key' => :integration_key, 'document' => :document,
               'created_at' => :created_at },
    default: { title: :asc }
  ).freeze

  def self.blocking_dependents
    # S9 — as renegociações do fornecedor (DB-071, BE-063).
    { 'Renegotiation' => { foreign_key: :provider_id, label: 'renegociação(ões)' } }
  end

  # Documento formatado para exibição, ou `-` quando não há — o mesmo fallback
  # do legado (`Provider#cpf_cnpj`), agora com máscara.
  def formatted_document
    return '-' if document.blank?

    Sfg::Document.mask(document_type, document)
  end

  # URL do logo, pelo ponto único do motor de anexos. `nil` quando não há —
  # nunca string vazia, e nunca `"missing.jpg"`.
  def logo_url
    return nil unless logo.attached?

    Sfg::Attachments.variant_url(logo, :preview, expires_in: Sfg::Attachments.image_url_expires_in)
  end

  private

  def normalize_strings
    self.title = title.to_s.strip.presence
    self.integration_key = integration_key.to_s.strip.presence
    self.document_type = document_type.to_s.strip.upcase.presence
    self.document = Sfg::Document.digits(document)
    self.state = state.to_s.strip.upcase.presence
    self.zip_code = zip_code.to_s.gsub(/\D/, '').presence
  end

  # O legado derivava o título de `fantasia` (ou `nome`) quando a tela deixava o
  # campo em branco depois de consultar a ReceitaWS. Preservado — é o que faz o
  # autopreenchimento por CNPJ chegar ao fim sem o operador redigitar.
  def derive_title_from_registry
    return if title.present?

    self.title = trade_name.presence || legal_name.presence
  end

  def derive_integration_key
    return if integration_key.present?

    self.integration_key = GlobalCatalog.slugify(title)
  end

  # O par tem de ser completo e verdadeiro, ou ausente por inteiro. Meio par
  # (tipo sem número, número sem tipo) é o que produz a coluna que ninguém sabe
  # ler depois.
  def document_pair_is_coherent
    if document.present? && document_type.blank?
      errors.add(:document_type, 'é obrigatório quando há documento')
      return
    end
    return if document.blank?
    return if Sfg::Document.valid?(document_type, document)

    errors.add(:document, "não é um #{document_type} válido")
  end
end
