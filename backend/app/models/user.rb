# frozen_string_literal: true

# Modelo de usuário para o sistema de Magic Login
# Suporta autenticação via código (email/WhatsApp) e OAuth social
#
# Attributes:
# - custom_variables: (jsonb) Variáveis customizadas definidas pelo usuário para uso no chat
class User < ApplicationRecord
  # Trilha de auditoria (DEC-59 / DEC-78). A lista de models versionados é curta
  # e deliberada; `users` entra porque troca de papel e mudança de identidade são
  # exatamente o que se quer poder reconstruir depois.
  #
  #  - `skip: :jti` — o `jti` NÃO é copiado para dentro do `object`. Guardar
  #    identificador de token na trilha é vazar credencial num lugar que, por
  #    desenho, tem retenção longa (DEC-59 #3);
  #  - `ignore:` — `updated_at`, `last_login_at` e `login_count` mudam a cada
  #    login. Sem isto, com payload COMPLETO (DEC-78), cada login duplicaria a
  #    linha inteira do usuário na trilha.
  #
  # LGPD (DEC-78 #3): a foto completa de `users` duplica CPF/CNPJ e endereço em
  # cada versão. É deliberado — auditoria de acesso precisa do estado — e é por
  # isso que a retenção de `versions` é finita desde o início
  # (`PurgeAuditVersionsJob`).
  has_paper_trail skip: %i[jti],
                  ignore: %i[updated_at last_login_at login_count]

  # S13 / OPS-493 — o avatar sai de `public/uploads/avatars/` (gravação crua em
  # disco, servida como estático e sem autenticação por `api/v1/uploads.rb`) e
  # passa a ser ActiveStorage, com os mesmos três derivados do legado
  # (`auth19/.../user.rb:4-18`: thumb 80 / preview 250 / 1500) e o mesmo limite de
  # 3 MB. As 4 colunas Paperclip (`avatar_file_name` e cia.) **não** são recriadas.
  #
  # A coluna `avatar_url` CONTINUA existindo e continua sendo o campo da API: ela
  # guarda a foto que vem do OAuth (`from_omniauth`), que é uma URL de terceiro e
  # não um binário nosso. `display_avatar_url` decide entre as duas — anexo tem
  # precedência. Regra de fronteira: o nome do campo na entity não muda, então
  # nenhum consumidor do front precisa mudar junto.
  include Attachable
  sfg_attachment :avatar

  devise :omniauthable, omniauth_providers: %i[google_oauth2 facebook]
  belongs_to :user_type

  # --- Contrato C1: escopo por projeto ---------------------------------------
  # `current_project` é PREFERÊNCIA, não autorização. Quem autoriza é
  # `memberships`, revalidado a cada request por `current_project!`.
  belongs_to :current_project, class_name: 'Project', optional: true

  has_many :memberships, dependent: :destroy
  has_many :projects, through: :memberships
  has_many :owned_projects, class_name: 'Project', foreign_key: :user_id,
                            dependent: :restrict_with_error, inverse_of: :owner
  has_many :login_codes, dependent: :destroy
  has_many :login_attempts, dependent: :destroy
  has_many :user_permissions, dependent: :destroy
  # Bloco 8 do trim (AI9-007, DEC-13.2): o dono das conversas do assistente
  # interno. É por AQUI que todo lookup de sessão passa — nunca
  # `ChatSession.find(params[:session_id])`, que era o IDOR.
  has_many :chat_sessions, dependent: :destroy
  # F.3 / DB-541 — cadastro secundário. `dependent: :destroy` porque o perfil não tem
  # vida própria: sem o usuário ele é lixo.
  has_one :user_profile, dependent: :destroy
  # Gestor direto (F.1 / DB-540). Auto-relação descritiva — NÃO é autorização: quem
  # autoriza é papel + membership (DEC-18.6).
  belongs_to :manager, class_name: 'User', optional: true
  has_many :subordinates, class_name: 'User', foreign_key: :manager_id,
                          dependent: :nullify, inverse_of: :manager
  has_rich_text :biography

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :user_type_id, presence: true

  # Email ou telefone deve estar presente
  validates :email, presence: true, unless: -> { phone.present? }
  validates :phone, presence: true, unless: -> { email.present? }

  # Validações específicas por campo
  validates :email,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: { case_sensitive: false },
            allow_blank: true

  validates :phone,
            format: { with: /\A[0-9]{10,15}\z/ },
            uniqueness: true,
            allow_blank: true



  # Documento e endereço
  validates :cpf_cnpj,
            format: { with: /\A(?:\d{11}|\d{14})\z/ },
            allow_blank: true,
            if: -> { self.class.column_names.include?('cpf_cnpj') }
  validates :cep,
            format: { with: /\A\d{8}\z/ },
            allow_blank: true,
            if: -> { self.class.column_names.include?('cep') }
  validates :state,
            format: { with: /\A[A-Z]{2}\z/ },
            allow_blank: true,
            if: -> { self.class.column_names.include?('state') }

  # **DEC-45 — `username` identifica, não recebe.**
  #
  # A unicidade é garantida pelo BANCO (índice único parcial `WHERE username IS NOT
  # NULL`); a validação daqui existe para dar mensagem de erro decente, não para ser a
  # trava. Duas requisições simultâneas passam pela validação da aplicação e só uma
  # passa pelo índice — é assim que tem de ser.
  #
  # O formato é restrito de propósito: `username` entra na MESMA caixa de texto que
  # e-mail e telefone na tela de login, e um `username` que possa conter `@` ou só
  # dígitos ficaria ambíguo com os outros dois canais.
  #
  # **`allow_blank`, não `allow_nil` (DEC-119 / DEC-127).** Medido no dump de
  # 31/05/2025: **72 contas com `username` vazio** e 11 com nulo; entre os 52
  # preenchidos há **zero** repetidos. Vazio é "não se aplica", e unicidade não
  # deveria alcançá-lo — com `allow_nil` a string vazia caía na validação de
  # formato E na de unicidade, e a 2ª conta vazia era recusada. O índice parcial
  # de `20260827020000_unicidade_parcial_onde_o_legado_diz_nao_se_aplica`
  # (`WHERE username IS NOT NULL AND username <> ''`) é o espelho desta linha.
  validates :username,
            format: { with: /\A[a-z0-9][a-z0-9._-]{2,49}\z/,
                      message: 'deve ter de 3 a 50 caracteres: letras minúsculas, dígitos, ponto, hífen ou sublinhado' },
            uniqueness: { case_sensitive: false },
            allow_blank: true
  validate :username_is_not_email_or_phone_shaped

  validates :identifier,
            format: { with: /\A[A-Z0-9]{6}\z/ },
            uniqueness: true,
            allow_nil: true

  # Enum como STRING (tarefa 1.1). O legado guardava texto livre e a tela comparava
  # contra rótulos traduzidos, então "Feminino" e "feminino" eram valores diferentes.
  GENDERS = %w[male female other undisclosed].freeze
  validates :gender, inclusion: { in: GENDERS }, allow_blank: true

  validates :provider, inclusion: { in: %w[email whatsapp google facebook] }, allow_nil: true
  validates :provider_uid, uniqueness: { scope: :provider }, allow_nil: true

  # Custom variables validation
  validate :custom_variables_format, if: -> { custom_variables.present? }

  # Callbacks
  before_validation :normalize_email, if: :email_changed?
  before_validation :normalize_phone, if: :phone_changed?
  before_validation :normalize_cpf_cnpj, if: -> { respond_to?(:cpf_cnpj_changed?) && cpf_cnpj_changed? }
  before_validation :normalize_cep, if: -> { respond_to?(:cep_changed?) && cep_changed? }
  before_validation :normalize_state, if: -> { respond_to?(:state_changed?) && state_changed? }
  before_validation :normalize_username, if: -> { respond_to?(:username_changed?) && username_changed? }

  # BE-048 / IMP-A21 — o código curto nasce com o registro. A unicidade quem garante é
  # o índice do banco: o `before_create` tenta, e se o índice recusar a colisão o
  # `save` refaz o sorteio. Gerar sem essa rede é o padrão que produz duplicata sob
  # concorrência e só aparece meses depois, quando dois usuários ditam o mesmo código
  # por telefone.
  before_create :assign_identifier

  # AI9-24 / Tarefa 1 — invalida o cache de autorização do admin quando o telefone muda,
  # para que a próxima mensagem reflita o novo/antigo número sem esperar o TTL.

  # OPS-006 — o job de membro padrão é enfileirado **só quando
  # `is_default_member` muda**, nunca em todo `update` do usuário. No legado
  # (`user_decorator.rb:242-252`) qualquer alteração de cadastro reenfileirava a
  # varredura de todos os projetos.
  after_commit :enqueue_default_member_job, on: %i[create update]

  # Scopes
  scope :by_email, ->(email) { where(email: email.downcase) }
  scope :by_phone, ->(phone) { where(phone: normalize_phone_number(phone)) }
  scope :by_provider, ->(provider, uid) { where(provider: provider, provider_uid: uid) }
  scope :active, -> { where.not(last_login_at: nil) }
  # DEC-39 — o recorte que o caminho de entrada usa. Conta bloqueada não é conta
  # apagada: ela continua na listagem administrativa (com selo), e some só daqui.
  scope :not_blocked, -> { where(blocked_at: nil) }
  scope :blocked, -> { where.not(blocked_at: nil) }

  # Métodos de classe

  # **DEC-45 — resolução de identidade para o caminho de entrada.**
  #
  # Três chaves, nesta ordem: e-mail, telefone, `username`. O ramo de `username`
  # ACRESCENTA — não altera os de e-mail e telefone, que são o caminho que 100% dos
  # usuários já usam hoje. Mexer neles para acomodar a terceira chave seria pôr o
  # caminho crítico em risco por causa da exceção.
  #
  # A ordem importa: `username` é testado por ÚLTIMO porque um endereço de e-mail e um
  # telefone nunca casam com o formato de `username` (ver
  # `username_is_not_email_or_phone_shaped`), mas o inverso não é garantido em base
  # legada — e um `username` que roube a resolução de um e-mail manda o código para o
  # destino errado.
  def self.find_for_identifier(value)
    value = value.to_s.strip
    return nil if value.blank?

    if value.include?('@')
      find_by(email: value.downcase)
    else
      digits = value.gsub(/[^0-9]/, '')
      by_phone_match = digits.length.between?(10, 15) ? find_by(phone: digits) : nil
      by_phone_match || where('LOWER(username) = ?', value.downcase).first
    end
  end

  # OAuth: **casa, nunca cria** (DEC-44).
  #
  # No legado o cadastro público criava **Admin** — é o D-39, e a DEC-49 fechou as 4
  # rotas que o produziam. Login social criando conta reabriria exatamente a mesma
  # porta, só que por fora do `api/root.rb`: bastaria uma conta Google qualquer.
  # Entrada no sistema é **só por convite** (DEC-18.7), então aqui o provedor social
  # prova quem a pessoa é — não a admite.
  #
  # A ordem de casamento é `(provider, uid)` e depois **e-mail**. Nunca por NOME: no
  # legado o casamento passava por `formal` (nome completo), e dois "João Silva" viravam
  # a mesma conta.
  def self.find_for_oauth(provider, uid, info = {})
    user = find_by(provider: provider, provider_uid: uid)
    return user if user

    email = info[:email].to_s.strip.downcase
    return nil if email.blank?

    user = find_by(email: email)
    return nil unless user

    # Primeiro login social de uma conta que já existia: grava o vínculo para que os
    # próximos passem pelo `(provider, uid)` mesmo se o e-mail mudar.
    user.update(
      provider: provider,
      provider_uid: uid,
      avatar_url: info[:image].presence || user.avatar_url
    )
    user
  end

  # Métodos de instância
  def og?
    user_type&.name.to_s.downcase == 'og'
  end

  # DEC-41 parte 2: `client?`, `visitor?` e `free?` FORAM REMOVIDOS junto com os
  # tipos. Se você veio procurar `visitor?`, o que você quer é
  # `Authorization::PermissionResolver#readonly?` (`user_is_readonly`, DEC-18.6)
  # — o gate global virou `require_not_readonly!`.
  def admin?
    user_type&.admin? || false
  end

  def gerente?
    user_type&.gerente? || false
  end

  def colaborador?
    user_type&.colaborador? || false
  end

  # O que a API expõe como `avatar_url`. Precedência: anexo nosso > URL do OAuth.
  #
  # Devolve a variante `preview` (250 px), não o original: o avatar aparece em
  # lista, topbar e trilha, e servir 1500 px em `<img>` de 32 px é o tipo de peso
  # que ninguém percebe até a lista ter 200 linhas.
  def display_avatar_url
    if avatar.attached?
      url = Sfg::Attachments.variant_url(avatar, :preview,
                                         expires_in: Sfg::Attachments.image_url_expires_in)
      return url if url.present?
    end

    avatar_url
  end

  # Participação: a verdade do escopo (C1). NUNCA use `current_project_id` para
  # decidir o que o usuário enxerga — ele é preferência e pode estar obsoleto.
  def member_of?(project)
    project_id = project.respond_to?(:id) ? project.id : project
    memberships.exists?(project_id: project_id)
  end

  def permission_resolver
    Authorization::PermissionResolver.new(self)
  end

  # NÃO se chama `readonly?`: esse nome é do ActiveRecord (marca o registro como
  # não-gravável) e sobrescrevê-lo faz TODO `create`/`update` do model estourar
  # `ActiveRecord::ReadOnlyRecord`. Colisão descoberta na suíte, e é o tipo de
  # coisa que passa despercebida até um caminho de escrita raro quebrar.
  def readonly_access?
    permission_resolver.readonly?
  end

  # --- Bloqueio de conta (DEC-39) ---------------------------------------------
  def blocked?
    blocked_at.present?
  end

  # Bloquear **revoga a sessão na hora** (IMP-A15/A16). Sem rotacionar o `jti`, o
  # access token que o usuário já tem na aba aberta continua valendo até expirar — e
  # "bloqueado" que só vale no próximo login não é bloqueio, é aviso.
  def block!(reason: nil)
    update!(
      blocked_at: Time.current,
      blocked_reason: reason.presence,
      jti: SecureRandom.uuid
    )
  end

  def unblock!
    update!(blocked_at: nil, blocked_reason: nil)
  end

  # --- Indicador de verificação (DEC-74) --------------------------------------
  # A escada de quatro degraus do legado (`auth19/.../user_info.rb:53-74`) é replicada
  # **como está**, inclusive o fato de o degrau máximo depender de `is_phone_checked`.
  #
  # O que NÃO é replicado é a trava que o legado amarrava nessa mesma flag: lá, com
  # `is_phone_checked = 1`, o campo de telefone virava `readonly` para sempre
  # (`my_account/parts/phone/_container.js.erb:14-16`). No ai9 o telefone é canal de
  # login (DEC-14); replicar a trava seria portar um bloqueio de acesso — quem perdesse
  # o número ficaria sem entrar e sem autoatendimento. O indicador vai; a trava não.
  CONFIABILITY_LEVELS = %w[baixa media alta maxima].freeze

  def confiability_level
    return 'maxima' if email.present? && phone.present? && cpf_cnpj.present? && is_phone_checked?
    return 'alta'   if email.present? && phone.present? && cpf_cnpj.present?
    return 'media'  if email.present? && phone.present?

    'baixa'
  end

  def display_name
    name.presence || email&.split('@')&.first || phone&.slice(-4, 4)
  end

  def can_impersonate?
    user_type&.can_impersonate?
  end

  def display_identifier
    email.presence || phone.presence || "#{provider}:#{provider_uid}"
  end

  def update_login_stats!
    update!(
      last_login_at: Time.current,
      login_count: login_count + 1
    )
  end

  def jwt_subject
    id
  end

  def active_login_code
    login_codes.where('expires_at > ?', Time.current)
               .where(used_at: nil)
               .order(created_at: :desc)
               .first
  end

  # NÃO é mais consultado pelo pedido de código. O cooldown de 30 s passou a ser
  # cobrado por DESTINO NORMALIZADO em `Api::Auth::V1::SecurityHelpers`
  # (`CODE_RESEND_COOLDOWN`), porque aqui ele só alcançava conta que existe — e essa
  # assimetria era um oráculo de enumeração da carteira de clientes (D-QA-01).
  # Fica como consulta de conveniência; não religue no caminho de login.
  def can_request_new_code?
    last_code = login_codes.order(created_at: :desc).first
    return true if last_code.nil?

    # Esperar 30 segundos entre requisições
    last_code.created_at < 30.seconds.ago
  end

  private

  def enqueue_default_member_job
    return unless saved_change_to_is_default_member?
    return unless is_default_member?

    DefaultMemberJob.perform_later(id)
  end

  def normalize_email
    self.email = email.downcase.strip if email.present?
  end

  def normalize_phone
    self.phone = self.class.normalize_phone_number(phone) if phone.present?
  end

  def normalize_cpf_cnpj
    self.cpf_cnpj = cpf_cnpj.to_s.gsub(/[^0-9]/, '') if cpf_cnpj.present?
  end

  def normalize_cep
    self.cep = cep.to_s.gsub(/[^0-9]/, '') if cep.present?
  end

  def normalize_state
    self.state = state.to_s.strip.upcase if state.present?
  end

  def normalize_username
    self.username = username.to_s.strip.downcase.presence
  end

  # `username` divide a caixa de texto do login com e-mail e telefone. Se um usuário
  # puder registrar `5511999999999` ou `fulano@x.com` como `username`, ele sequestra a
  # resolução de outra pessoa — o código de acesso sairia para o destino errado.
  def username_is_not_email_or_phone_shaped
    return if username.blank?

    errors.add(:username, 'não pode conter @ (isso é um e-mail)') if username.include?('@')
    errors.add(:username, 'não pode ser só dígitos (isso é um telefone)') if username.match?(/\A[0-9]+\z/)
  end

  # 6 caracteres A-Z0-9, sorteados com `SecureRandom`. Retry porque a unicidade real é
  # o índice do banco: sob concorrência, dois `before_create` sorteiam sem se ver.
  IDENTIFIER_ALPHABET = ('A'..'Z').to_a.concat(('0'..'9').to_a).freeze
  IDENTIFIER_MAX_TRIES = 10

  def assign_identifier
    return if identifier.present?

    IDENTIFIER_MAX_TRIES.times do
      candidate = Array.new(6) { IDENTIFIER_ALPHABET.sample(random: SecureRandom) }.join
      next if self.class.exists?(identifier: candidate)

      self.identifier = candidate
      return
    end

    # Esgotou o sorteio: deixa `nil` em vez de gravar colisão. `identifier` é código de
    # conveniência, não chave — falhar o cadastro inteiro por causa dele seria pior.
    Rails.logger.warn('[User] não foi possível sortear `identifier` único em 10 tentativas')
  end

  def self.normalize_phone_number(phone)
    # Normaliza para somente dígitos (sem '+') para compatibilidade com dados existentes
    phone.to_s.gsub(/[^0-9]/, '')
  end

  def custom_variables_format
    unless custom_variables.is_a?(Hash)
      errors.add(:custom_variables, 'deve ser um objeto (Hash)')
      return
    end

    custom_variables.each do |key, _value|
      unless key.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
        errors.add(:custom_variables, "chave '#{key}' deve ser snake_case (ex: minha_variavel)")
      end
    end
  end
end
