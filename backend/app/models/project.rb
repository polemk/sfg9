# frozen_string_literal: true

# S0 / DB-080 — a unidade de escopo (tenant) do Safegold.
#
# Nesta fatia o `Project` existe como **esquema e regra mínima**: é o alvo das
# FKs de `memberships` e de `users.current_project_id`. CRUD, tela e efeitos
# colaterais da criação são da fatia S4 (decisão DS0-2).
class Project < ApplicationRecord
  # Trilha de auditoria (DEC-59). Lista curta e deliberada — projeto entra
  # porque é o eixo de todo o escopo do sistema.
  has_paper_trail ignore: %i[updated_at]

  # S13 / OPS-494 — avatar do projeto por ActiveStorage, com os derivados e o
  # limite de 5 MB do legado (`project.rb:48-58,127`). Motor único (DEC-91): nada
  # de `Medium`, nada de `public/uploads`. As colunas Paperclip não são recriadas.
  include Attachable
  sfg_attachment :avatar

  # S13 / OPS-463, DB-460 — o estado do job vive AQUI, não numa tabela de fila.
  # `Project` é a única entidade do legado com `has_ongoing_job?` de verdade
  # (os outros 7 widgets liam `data-ongoing` sem nenhum emissor do outro lado).
  include JobProgressable

  belongs_to :owner, class_name: 'User', foreign_key: :user_id, inverse_of: :owned_projects

  has_many :memberships, dependent: :destroy
  has_many :members, through: :memberships, source: :user

  # --- S4: o agregado do projeto -------------------------------------------
  # **Nenhuma associação usa `dependent: :restrict_with_error`**, e isso é
  # decisão, não esquecimento: a mensagem dele é a genérica do Rails, em inglês
  # no meio do português — *"Não é possível excluir o registro pois existem
  # companies dependentes"*. Apareceu rodando, na tela.
  #
  # Todo bloqueio desta fatia passa por `.blocking_dependents`, que dá UMA
  # mensagem em pt-BR nomeando o vínculo e a contagem, e que também cobre os
  # dependentes cuja tabela ainda não nasceu (S5..S11) — associação declarada
  # contra classe inexistente levanta `NameError` na hora do `destroy`.
  #
  # A segunda camada continua sendo a FK do Postgres, que nasce `NO ACTION`.
  belongs_to :segment, optional: true
  belongs_to :sub_segment, optional: true
  belongs_to :responsible, class_name: 'User', optional: true, inverse_of: false

  has_many :companies, dependent: nil
  has_many :providers, dependent: nil
  has_many :project_guarantees, dependent: nil
  # A conexão com portador **acompanha** o projeto: ela não é dado próprio, é a
  # aresta. Um projeto removido sem as arestas deixaria linha órfã.
  has_many :project_to_carrier_connections, dependent: :destroy
  has_many :carriers, through: :project_to_carrier_connections

  # --- S10 — indicadores ------------------------------------------------------
  # A conexão com indicador é a mesma ideia da de portador: é a **aresta**, e
  # acompanha o projeto. Já os `indicator_entries` são **dado**, e por isso vêm
  # `dependent: nil` — quem decide o que acontece com o lançamento é o
  # `BlockingDependents` e a FK, nunca uma cascata silenciosa. Foi assim que o
  # legado perdia série histórica (D-66).
  has_many :project_indicator_connections, dependent: :destroy
  has_many :indicators, through: :project_indicator_connections
  has_many :indicator_entries, dependent: nil

  include BlockingDependents

  # BE-097 / DB-088 — a observação de disponibilidade em **ActionText**.
  # `reuse` de ponta a ponta: a tabela `action_text_rich_texts` já existe e o
  # caminho é o mesmo do `User#biography`. **Zero migration.**
  # O anexo é bloqueado NO SERVIDOR (o ActionText os aceita por padrão, e o
  # legado bloqueava só no cliente, por `trix-file-accept`).
  has_rich_text :availability_note

  validates :name, presence: true, length: { maximum: 255 },
                   uniqueness: { case_sensitive: false, message: 'já está em uso por outro projeto' }
  # O `.` e o `&` entram por **paridade com o legado** (DEC-122), medida no dump de
  # produção: dos 83 projetos, 81 usam só minúsculas/números/hífen — mas um tem `&`
  # e outro tem `.`, e a validação estreita **matava a carga na terceira tabela**,
  # deixando as outras 50 e poucas sem migrar.
  #
  # Decisão do usuário: aceitar os dois como estão, em vez de reescrever
  # identificador de cliente. O slug é imutável depois de criado (`freeze_slug`),
  # então isto vale para o que vem do legado; projeto novo nasce do `parameterize`
  # em `derive_slug` e nunca produz esses caracteres.
  #
  # **O `&` exige cuidado em quem monta URL.** Ele é separador de parâmetro numa
  # query string, e um link que não o codifique (`%26`) trunca o endereço do
  # projeto. Todo ponto que interpola slug em URL precisa usar codificação.
  validates :slug, presence: true, uniqueness: { case_sensitive: false },
                   format: { with: /\A[a-z0-9][a-z0-9\-_.&]*\z/,
                             message: 'aceita apenas minúsculas, números, hífen, sublinhado, ponto e &' }
  validates :integration_key, presence: true, length: { maximum: 255 },
                              uniqueness: { case_sensitive: false }
  validates :color, format: { with: /\A#\h{6}\z/, message: 'deve ser um hexadecimal como #1A2B3C' },
                    allow_blank: true
  validates :address_state, length: { is: 2 }, allow_blank: true
  validates :cep, format: { with: /\A\d{5}-?\d{3}\z/, message: 'deve ter 8 dígitos' }, allow_blank: true

  before_validation :derive_slug, on: :create
  before_validation :normalize_slug
  before_validation :freeze_slug, on: :update
  before_validation :derive_integration_key, on: :create
  before_validation :assign_color, on: :create
  before_validation :normalize_address

  # BE-097 / 7.4.9 — **anexo na observação é bloqueado NO SERVIDOR**.
  #
  # O ActionText aceita anexo por padrão. O legado bloqueava só no cliente
  # (`trix-file-accept` mais o botão escondido por CSS): um `curl`, ou o mesmo
  # navegador com o JS desligado, embutia arquivo numa nota de disponibilidade —
  # e o arquivo saía servido por `public/`, sem autenticação (D-82).
  #
  # O motor de anexo do Safegold é UM (`Attachable` + `config/attachments.yml`,
  # DEC-91); este caminho não é ele, e por isso não anexa nada.
  validate :availability_note_has_no_attachments

  scope :active, -> { where(is_active: true) }

  # Projetos em que o usuário PARTICIPA. É esta consulta, e não
  # `users.current_project_id`, que decide o que o usuário enxerga (C1).
  # Participação LITERAL: só os projetos em que o usuário tem linha em
  # `memberships`. Continua sendo a verdade sobre participação — é o que a
  # remoção de membro e o cálculo de "sobrou algum?" precisam saber.
  scope :for_member, lambda { |user|
    user_id = user.respond_to?(:id) ? user.id : user
    joins(:memberships).where(memberships: { user_id: user_id })
  }

  # Projetos em que o usuário pode ATUAR — que não é o mesmo que participar.
  #
  # **OG e Admin enxergam todos os projetos, sem precisar de participação.**
  # É a regra do negócio: quem administra o sistema precisa entrar em qualquer
  # projeto para dar suporte, conferir número e corrigir cadastro. Exigir que
  # alguém crie uma participação para o administrador antes de ele poder olhar
  # é burocracia que, na prática, vira gente criando participação e esquecendo
  # de remover — o que é pior para a auditoria do que a visão global explícita.
  #
  # O contrato **C1 continua valendo por inteiro**: o escopo segue aplicado no
  # endpoint, nunca por `default_scope`, e o dado de dentro do projeto continua
  # filtrado por `current_project!`. O que muda é **quais projetos entram na
  # lista**, não o fato de haver filtro.
  #
  # Gerente e Colaborador seguem restritos à participação.
  scope :visible_to, lambda { |user|
    next all if user.respond_to?(:og?) && (user.og? || user.admin?)

    for_member(user)
  }

  # BE-091 / D-24 — exclusão **bloqueia**, e o 422 nomeia o vínculo. No legado o
  # controller respondia `:ok` mesmo sem excluir, e o JS redirecionava dizendo
  # "removido com sucesso".
  #
  # As três primeiras são desta fatia; as demais entram por NOME porque a fatia
  # dona ainda não entregou a tabela. A lista é UMA — ver o comentário das
  # associações lá em cima para o porquê de nenhuma usar `dependent:`.
  def self.blocking_dependents
    {
      'Company' => { foreign_key: :project_id, label: 'empresa(s)' },
      'Provider' => { foreign_key: :project_id, label: 'fornecedor(es)' },
      'ProjectGuarantee' => { foreign_key: :project_id, label: 'garantia(s)' },
      'RiskControl' => { foreign_key: :project_id, label: 'limite(s) de risco' },
      'ReceivableEntry' => { foreign_key: :project_id, label: 'recebível(is)' },
      'Renegotiation' => { foreign_key: :project_id, label: 'renegociação(ões)' },
      'RiskOperation' => { foreign_key: :project_id, label: 'operação(ões) de risco' },
      'StructuredOperation' => { foreign_key: :project_id, label: 'operação(ões) estruturada(s)' },
      'AvailabilityEntry' => { foreign_key: :project_id, label: 'lançamento(s) de disponibilidade' },
      'IndicatorEntry' => { foreign_key: :project_id, label: 'lançamento(s) de indicador' }
    }
  end

  # BE-092 — o projeto de treinamento **não é removível, só limpo**. A regra
  # vivia no `before_destroy` do legado e continua sendo de servidor.
  before_destroy :refuse_to_destroy_sandbox

  scope :search, lambda { |term|
    termo = term.to_s.strip
    next all if termo.blank?

    padrao = "%#{ActiveRecord::Base.sanitize_sql_like(termo)}%"
    where('name ILIKE :q OR slug ILIKE :q', q: padrao)
  }

  # Chave desconhecida é ignorada, nunca 500 (`Sfg::Sortable`).
  ORDERING = Sfg::Sortable.new(
    allowed: { 'title' => :name, 'name' => :name, 'key' => :integration_key,
               'created_at' => :created_at, 'updated_at' => :updated_at },
    default: { name: :asc }
  ).freeze

  # Endereço formatado, uma linha por bloco. **Replica `Project#beauty_address`
  # do legado**, com duas diferenças, e as duas são dado que o operador digitou
  # e que o legado nunca mostrava:
  #
  #  1. lê `address_city`, a coluna que o formulário escreve. O legado lia
  #     `city`, uma SEGUNDA coluna de cidade que o formulário nunca preenchia —
  #     a cidade digitada jamais aparecia no endereço (**D-124**);
  #  2. inclui `address_type` ("Rua", "Avenida"). O legado o guardava, o
  #     formulário o pedia, e `beauty_address` começava direto no logradouro.
  #
  # O separador é `\n`: a tela decide como quebrar (`whitespace-pre-line`). O
  # legado devolvia `<br/>` do model — HTML montado no domínio.
  def formatted_address
    logradouro = [address_type, address].reject(&:blank?).join(' ')
    linha1 = [logradouro, address_number].reject(&:blank?).join(', ')
    linha2 = address_complement.presence && "Complemento #{address_complement}"
    cidade = [address_city, address_state].reject(&:blank?).join(', ')
    cidade = [cidade.presence, cep.presence && "CEP #{cep}"].compact.join(' - ')

    [linha1, linha2, neighborhood.presence, cidade].reject(&:blank?).join("\n")
  end

  # URL do avatar para a API — variante `preview`, prazo de imagem. `nil` quando
  # não há anexo, nunca string vazia: o front distingue os dois.
  def avatar_url
    return nil unless avatar.attached?

    Sfg::Attachments.variant_url(avatar, :preview, expires_in: Sfg::Attachments.image_url_expires_in)
  end

  private

  # DC-17 / Lacuna L-09 — **o slug nasce do nome e é imutável depois**.
  #
  # No legado `set_smart_id` rodava em TODO `before_validation`: renomear o
  # projeto mudava o slug e, com ele, todas as URLs baseadas nele. O algoritmo
  # de desambiguação é o do legado, replicado: sufixo numérico acrescentado ao
  # NOME antes de transliterar (`Acme Corp` → `acme-corp`, `acme-corp-2`, …).
  def derive_slug
    return if slug.present?

    tentativa = 1
    loop do
      base = tentativa > 1 ? "#{name} #{tentativa}" : name.to_s
      candidato = I18n.transliterate(base.squish).downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-+|-+\z/, '')
      self.slug = candidato.presence
      break if slug.blank? || !Project.where(slug: slug).where.not(id: id).exists?

      tentativa += 1
    end
  end

  def normalize_slug
    self.slug = slug.to_s.strip.downcase.presence
  end

  # A imutabilidade é aplicada **no model**, não só na ausência do campo no
  # `permit`: um job, um seed ou um `update_column` distraído também não podem
  # trocar a URL de um projeto em produção.
  def freeze_slug
    self.slug = slug_was if slug_changed?
  end

  def derive_integration_key
    return if integration_key.present?

    self.integration_key = GlobalCatalog.slugify(name)
  end

  # Cor de identificação sorteada na criação — o legado usava `ColorGenerator`
  # (gem não portada). O que importa é a cor ser estável e legível; a paleta é
  # fixa e vem dos tokens da marca, em vez de HSL aleatório que às vezes saía
  # ilegível sobre o fundo claro.
  PALETTE = %w[#FFC107 #EB9600 #607D8B #217B55 #7D1F1E #2D2D2A #3F51B5 #00838F].freeze

  def assign_color
    self.color = PALETTE.sample if color.blank?
  end

  def normalize_address
    self.address_state = address_state.to_s.strip.upcase.presence
    self.cep = cep.to_s.gsub(/\D/, '').then { |d| d.length == 8 ? "#{d[0, 5]}-#{d[5, 3]}" : cep.presence }
  end

  def availability_note_has_no_attachments
    # `rich_text_availability_note` (a associação crua), e NÃO `availability_note`:
    # o leitor gerado por `has_rich_text` **constrói** o registro quando ele não
    # existe, e o autosave o grava com `body` nulo — a coluna é `null: false`, e
    # criar projeto passava a estourar `NotNullViolation`. Uma validação que
    # materializa o que está validando é uma validação que muda o mundo.
    corpo = rich_text_availability_note&.body
    return if corpo.blank?
    return if corpo.attachments.blank?

    errors.add(:availability_note, 'não aceita anexos — use o campo de arquivos do projeto')
  end

  def refuse_to_destroy_sandbox
    return unless is_sandbox?

    errors.add(:base, 'O projeto de treinamento não pode ser removido — use "Limpar dados".')
    throw(:abort)
  end
end
