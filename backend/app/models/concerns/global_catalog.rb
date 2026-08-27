# frozen_string_literal: true

# S3 — **o molde dos catálogos globais** (contrato C1, regra 4 de `§0.6`).
#
# Os cinco cadastros desta fatia — `Carrier`, `CarrierGroup`, `Segment`,
# `SubSegment`, `ProjectGuaranteeType` — são o mesmo objeto com colunas
# diferentes: título, chave de integração, ativação, busca por texto, ordenação
# e exclusão bloqueável. Escrever cinco vezes é a forma mais rápida de terminar
# com cinco semânticas de busca.
#
# **Este concern é o OPOSTO do `ProjectScoped`, de propósito.** Um catálogo
# global NÃO tem `project_id`, NÃO inclui `ProjectScoped` e nenhum endpoint que
# o serve chama `current_project!`. A regra em uma frase, copiada do mapa:
#
# > o menu esconde a tela de administração do catálogo, não o dado do catálogo.
#
# Se você veio da S4 ou da S11 e está tentando aplicar `for_project` aqui: pare.
# Um portador cadastrado "no projeto A" sumiria da tela do projeto B e quebraria
# o `risk_control` que já aponta para ele. As duas regras são opostas por
# desenho, e `global_catalog?` existe para que o spec de contrato consiga
# afirmar isso sobre cada model.
module GlobalCatalog
  extend ActiveSupport::Concern

  # Dependência de concern (ActiveSupport::Concern): quem inclui `GlobalCatalog`
  # ganha junto o bloqueio de exclusão. O mecanismo foi extraído daqui na S4,
  # quando `Company`/`Provider`/`Project` passaram a precisar exatamente do
  # mesmo — duas cópias dele terminariam com duas semânticas de exclusão.
  include BlockingDependents

  # Chave de integração a partir de um título. Transliteração + minúsculas +
  # sublinhado, exatamente como o legado gerava — a chave dos registros
  # migrados não pode mudar de forma (mesma leitura conservadora do DEC-85).
  #
  # **A resolução de dependente por nome mudou de casa na S4** e agora vive em
  # `BlockingDependents`: `Company`, `Provider` e `Project` precisam da MESMA
  # regra de bloqueio, e duas cópias dela terminariam com duas semânticas de
  # exclusão. Os dois métodos abaixo continuam existindo porque `CatalogService`
  # os chama por este nome — são delegação, não uma segunda implementação.
  def self.dependent_class(class_name)
    BlockingDependents.dependent_class(class_name)
  end

  def self.dependent_class_with_column(class_name, foreign_key)
    BlockingDependents.dependent_class_with_column(class_name, foreign_key)
  end

  def self.slugify(value)
    I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '').presence
  end

  included do
    validates :title, presence: true, length: { maximum: 255 }
    validates :integration_key, presence: true, length: { maximum: 255 }

    scope :active, -> { where(is_active: true) }

    # Busca por texto — **`ILIKE` com bind, nunca interpolação** (OPS-056).
    #
    # O legado usava `Dev.ilike`, que interpolava o OPERADOR conforme o adapter
    # e montava o padrão dentro da string: `100%` e `a'b` viravam padrão SQL em
    # vez de texto literal. Aqui o termo é escapado por `sanitize_sql_like` (o
    # `%`, o `_` e a contrabarra deixam de ser curinga) e entra por bind.
    #
    # O alvo é Postgres (DEC-05), então `ILIKE` é literal no código.
    scope :search, lambda { |term|
      termo = term.to_s.strip
      next all if termo.blank?

      padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
      where('title ILIKE :q OR integration_key ILIKE :q', q: padrao)
    }

    before_validation :normalize_catalog_title
    before_validation :derive_integration_key, on: :create
    before_validation :normalize_integration_key

  end

  class_methods do
    # Marcador de leitura, espelho do `ProjectScoped.project_scoped?`.
    # `Model.global_catalog?` responde `true`, e o spec de contrato de C1
    # confere que nenhum destes cinco models também é `project_scoped?`.
    def global_catalog?
      true
    end

    def slug_for(value)
      GlobalCatalog.slugify(value)
    end

    # Dependentes que **bloqueiam** a exclusão, declarados por NOME de classe.
    #
    # Por nome, e não por `has_many … dependent: :restrict_with_error`, porque
    # metade das tabelas que apontam para estes catálogos nasce em S4..S6:
    # `project_to_carrier_connections` (S4), `receivable_entries` (S6),
    # `risk_controls` (S5), `project_guarantees` (S4). Uma associação declarada
    # contra classe inexistente levanta `NameError` na hora do `destroy`.
    #
    # Assim a regra fica escrita HOJE e passa a valer sozinha quando a fatia
    # dona entregar a tabela — em vez de virar uma linha que alguém precisa
    # lembrar de acrescentar depois. É exatamente o D-24: no legado excluir um
    # portador **apagava os `risk_controls` dele** (`dependent: :destroy`), e
    # essa é a assimetria mais perigosa do bloco.
    #
    # A segunda camada é o banco: as FKs que essas tabelas criarem para cá
    # nascem `NO ACTION`, então o Postgres recusa mesmo que alguém contorne o
    # model.
    #
    # Formato: `{ 'ClasseDependente' => { foreign_key: :coluna, label: 'texto pt-BR' } }`
    # O default (`{}`) vem de `BlockingDependents`; cada catálogo sobrescreve.
  end

  private


  def normalize_catalog_title
    self.title = title.to_s.strip.presence
  end

  # A chave é derivada do título **na criação** e **congelada** depois (DC-22).
  #
  # No legado o `before_validation … on: [:create]` fazia o mesmo, mas o campo
  # continuava no `permit` e a tela o reescrevia: título e chave divergiam na
  # primeira edição. É chave de **integração** — recalculá-la em silêncio quebra
  # consumidor externo, e silêncio é o pior modo de falha de integração (mesma
  # leitura do DEC-85).
  def derive_integration_key
    return if integration_key.present?

    self.integration_key = self.class.slug_for(title)
  end

  def normalize_integration_key
    self.integration_key = integration_key.to_s.strip.presence
  end
end
