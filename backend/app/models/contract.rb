# frozen_string_literal: true

# S12 / BE-336, BE-337, BE-339, BE-345 — uma **versão publicada** de um
# documento de contrato (Termos de Uso ou Política de Privacidade).
#
# Uma linha = uma versão. O "documento vigente" de um tipo é a linha de **maior
# `version`** (`Contracts::Resolver`), nunca a de maior `id`: o legado usava
# `.last` sem `order` (`pub/contracts_controller.rb:4`), então re-salvar uma
# versão antiga fazia o sistema servir o texto errado ao público (BE-331).
#
# **Append-only na NUMERAÇÃO, editável no TEXTO.** Isto é a DEC-80 escolhendo a
# opção (b) e recusando a (d): `kind` e `version` são imutáveis depois da
# criação, mas o corpo continua editável no lugar. A consequência jurídica está
# assumida e mitigada em `ContractDeal`, que grava o hash **e o texto** lidos no
# momento do aceite — e em `#divergent_deals_count`, que diz a quem publica
# quantos aceites ficarão com hash divergente (mitigação 2 da DEC-80).
#
# O `tasks.md:5.2` pedia "alterar uma versão publicada é recusada" para o
# documento inteiro; a **DEC-80 vence o `tasks.md`** e recusa só a identidade
# (tipo e número).
class Contract < ApplicationRecord
  # Trilha de auditoria (DEC-59 / DEC-78). Declarado em
  # `Sfg::AuditTrail::VERSIONED` pela S19, com o motivo: *"o texto vigente decide
  # o que o usuário aceitou"*. O ACEITE não entra na trilha — tem prova própria
  # (DEC-80), e está em `EXCLUDED`.
  include Auditable

  KIND_TERMS_OF_USE = 'Termos de Uso'
  KIND_PRIVACY_POLICY = 'Politicas de Privacidade'

  # Catálogo **fechado** (BE-339 / Q-B4). Não é configurável pela interface: um
  # tipo novo é migration (o CHECK do banco) + linha aqui + texto de origem.
  # A grafia é a do legado, **com o typo consolidado** em "Politicas" — a string
  # viaja em URL pública e existe em links externos (Q-B34).
  KINDS = [KIND_TERMS_OF_USE, KIND_PRIVACY_POLICY].freeze

  # Q-B34 RESOLVIDA: nem só a string literal (default), nem só o slug. O **slug
  # é a forma canônica** das URLs novas e a string literal **continua sendo
  # aceita** na rota pública, que resolve as duas. Assim o link externo antigo
  # (`/contract/Politicas%20de%20Privacidade`) continua abrindo e o link novo
  # não depende de espaço nem de typo.
  SLUGS = {
    KIND_TERMS_OF_USE => 'termos-de-uso',
    KIND_PRIVACY_POLICY => 'politicas-de-privacidade'
  }.freeze

  has_rich_text :description

  belongs_to :creator, class_name: 'User', optional: true
  has_many :contract_deals, dependent: :destroy, inverse_of: :contract
  has_many :accepting_users, through: :contract_deals, source: :user

  validates :kind, presence: true, inclusion: { in: KINDS, message: 'não está no catálogo de contratos' }
  validates :title, presence: true, length: { maximum: 255 }
  validates :version, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  # O legado NÃO validava o corpo, e `has_rich_text` faz o leitor devolver um
  # `ActionText::RichText` construído na hora — `presence` sozinho nunca falha.
  # Por isso a validação olha o texto puro, não o objeto.
  validate :corpo_nao_pode_ser_vazio

  before_validation :assign_version_and_slug, on: :create
  # `before_create`, e não `before_validation`: `save(validate: false)` pula a
  # validação mas não os callbacks de gravação. Sem isto, o caminho que ignora
  # validação gravaria `published_at` nulo e batia no `null: false` do banco com
  # a mensagem errada — escondendo o defeito que se estava tentando ver.
  before_create :ensure_defaults
  # Append-only na identidade. Sem isto, um `update(kind: …)` moveria a versão 3
  # dos Termos para dentro da numeração da Política e o índice único não
  # perceberia nada errado.
  before_update :recusar_mudanca_de_identidade

  scope :of_kind, ->(kind) { where(kind: kind) }
  scope :newest_first, -> { order(version: :desc) }

  # A versão vigente de cada tipo, uma linha por tipo. É `DISTINCT ON` para não
  # depender de agrupar em Ruby — o legado carregava a lista inteira e escolhia
  # o máximo em memória DEPOIS de paginar, que é o D-20 nesta capability
  # (contrato sumia da lista).
  scope :current_per_kind, lambda {
    from(
      unscoped.select('DISTINCT ON (kind) *').order(:kind, version: :desc),
      :contracts
    ).order(:kind)
  }

  def self.kind_for(param)
    valor = param.to_s.strip
    return valor if KINDS.include?(valor)

    SLUGS.key(valor.downcase)
  end

  def slug_value
    SLUGS.fetch(kind, kind.to_s.parameterize)
  end

  # HTML **sanitizado** do corpo (BE-345). A sanitização acontece na
  # renderização, não na gravação: o que está guardado é o que o editor
  # produziu, e a allowlist é aplicada em toda saída — inclusive na pública, que
  # é a que tem valor jurídico e era, no legado, a MENOS fiel das duas
  # (`CGI.unescape(...to_plain_text).html_safe`, que jogava fora título, lista e
  # negrito da tela que o usuário assina).
  def description_html
    Contracts::Renderer.html(description)
  end

  def description_text
    Contracts::Renderer.text(description)
  end

  # SHA-256 do texto, normalizado. É o que `ContractDeal` congela no aceite.
  def content_hash
    Contracts::Renderer.digest(description)
  end

  # Mitigação 2 da DEC-80: **quantos aceites ficam com hash divergente** se este
  # texto mudar. Quem publica é OG ou Admin (DEC-38), então o aviso chega a quem
  # pode decidir.
  def divergent_deals_count
    atual = content_hash
    contract_deals.where.not(content_hash: atual).where.not(content_hash: nil).count
  end

  # `decoded_description` do legado (`contract.rb:27-29`) **não é portado**:
  # `URI.unescape` foi removido no Ruby 3.0 e o método levantaria `NoMethodError`
  # em qualquer chamada. BE-345.

  private

  # Numeração atribuída **só na criação** (BE-336). No legado o `version_guess`
  # era `before_save` sem `on:` (`contract.rb:2`), então **re-salvar
  # incrementava** — a versão 3 virava 4 sem ninguém publicar nada.
  #
  # A distinção entre concorrentes é do BANCO, em dois níveis: o `advisory lock`
  # serializa o cálculo do próximo número, e o índice único `(kind, version)` é
  # a rede embaixo. Aplicação sozinha (`validates_uniqueness_of`) não resolve —
  # era exatamente o que o legado tinha.
  def assign_version_and_slug
    self.slug = slug_value if kind.present?
    return if version.present?
    return if kind.blank?

    self.version = self.class.next_version_for(kind)
  end

  def self.next_version_for(kind)
    connection.execute(
      sanitize_sql_array(['SELECT pg_advisory_xact_lock(hashtext(?))', "contracts:#{kind}"])
    )
    (of_kind(kind).maximum(:version) || 0) + 1
  end

  def ensure_defaults
    self.published_at ||= Time.current
    self.slug = slug_value if slug.blank? && kind.present?
  end

  def recusar_mudanca_de_identidade
    return unless kind_changed? || version_changed?

    errors.add(:base, 'Tipo e número de versão não mudam depois de publicados. Publique uma versão nova.')
    throw(:abort)
  end

  def corpo_nao_pode_ser_vazio
    return if description_text.present?

    errors.add(:description, 'não pode ficar em branco')
  end
end
