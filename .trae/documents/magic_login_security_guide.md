# Magic Login - Guia de Segurança e Compliance

## 1. Visão Geral de Segurança

Este documento descreve as medidas de segurança implementadas no sistema Magic Login, garantindo proteção contra vulnerabilidades comuns e conformidade com regulamentações de privacidade.

## 2. Princípios de Segurança

### 2.1 Confidencialidade

* Criptografia de dados em trânsito (TLS 1.3)

* Criptografia de dados em repouso (AES-256)

* Tokens JWT com assinatura forte (RS256)

* Sanitização de inputs e outputs

### 2.2 Integridade

* Validação de dados em múltiplas camadas

* Logs de auditoria completos

* Prevenção de tampering

* Verificação de integridade de mensagens

### 2.3 Disponibilidade

* Rate limiting e DDoS protection

* Circuit breakers para serviços externos

* Graceful degradation

* Monitoramento proativo

## 3. Implementações de Segurança

### 3.1 Autenticação e Autorização

#### JWT Security

```ruby
# config/initializers/jwt.rb
require 'jwt'

class JsonWebToken
  ALGORITHM = 'RS256'
  
  class << self
    def encode(payload, exp = 24.hours.from_now)
      payload[:exp] = exp.to_i
      JWT.encode(payload, private_key, ALGORITHM)
    end
    
    def decode(token)
      body = JWT.decode(token, public_key, true, algorithm: ALGORITHM)[0]
      HashWithIndifferentAccess.new body
    rescue JWT::ExpiredSignature, JWT::VerificationError => e
      raise ExceptionHandler::ExpiredSignature, e.message
    rescue JWT::DecodeError => e
      raise ExceptionHandler::DecodeError, e.message
    end
    
    private
    
    def private_key
      OpenSSL::PKey::RSA.new(ENV['JWT_PRIVATE_KEY'])
    end
    
    def public_key
      OpenSSL::PKey::RSA.new(ENV['JWT_PUBLIC_KEY'])
    end
  end
end
```

#### Rate Limiting

```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  ### Throttle Spammy Clients ###
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?('/assets')
  end
  
  ### Throttle Login Attempts ###
  throttle('logins/ip', limit: 5, period: 20.minutes) do |req|
    if req.path == '/api/v1/magic_login/request_code' && req.post?
      req.ip
    end
  end
  
  ### Throttle Code Validation ###
  throttle('code_validation/ip', limit: 10, period: 10.minutes) do |req|
    if req.path == '/api/v1/magic_login/validate_code' && req.post?
      req.ip
    end
  end
  
  ### Block Suspicious Requests ###
  blocklist('block malicious IPs') do |req|
    # Verificar listas negras de IP
    MaliciousIPChecker.blocked?(req.ip)
  end
  
  ### Custom Responses ###
  self.throttled_response = lambda do |env|
    retry_after = (env['rack.attack.match_data'] || {})[:period]
    [
      429,
      { 'Content-Type' => 'application/json', 'Retry-After' => retry_after.to_s },
      [{ error: 'Rate limit exceeded. Try again later.' }.to_json]
    ]
  end
end
```

#### Brute Force Protection

```ruby
# app/services/auth/brute_force_protection_service.rb
module Auth
  class BruteForceProtectionService
    MAX_ATTEMPTS = 3
    LOCKOUT_DURATION = 30.minutes
    
    def initialize(identifier, ip_address)
      @identifier = identifier
      @ip_address = ip_address
    end
    
    def allowed?
      !ip_blocked? && !identifier_blocked?
    end
    
    def record_attempt(success)
      if success
        reset_attempts
      else
        increment_attempts
      end
    end
    
    def lockout_remaining_time
      return 0 unless blocked?
      
      last_attempt = get_last_attempt
      return 0 unless last_attempt
      
      time_since_last = Time.current - last_attempt.created_at
      remaining = LOCKOUT_DURATION - time_since_last
      [remaining, 0].max
    end
    
    private
    
    def ip_blocked?
      attempts = LoginAttempt.where(
        ip_address: @ip_address,
        created_at: LOCKOUT_DURATION.ago..Time.current,
        success: false
      ).count
      
      attempts >= MAX_ATTEMPTS
    end
    
    def identifier_blocked?
      attempts = LoginAttempt.where(
        identifier: @identifier,
        created_at: LOCKOUT_DURATION.ago..Time.current,
        success: false
      ).count
      
      attempts >= MAX_ATTEMPTS
    end
    
    def increment_attempts
      LoginAttempt.create!(
        identifier: @identifier,
        ip_address: @ip_address,
        success: false
      )
    end
    
    def reset_attempts
      LoginAttempt.where(
        identifier: @identifier,
        ip_address: @ip_address
      ).delete_all
    end
    
    def get_last_attempt
      LoginAttempt.where(
        identifier: @identifier,
        ip_address: @ip_address
      ).order(created_at: :desc).first
    end
  end
end
```

### 3.2 Validação e Sanitização

#### Input Validation

```ruby
# app/validators/email_validator.rb
class EmailValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?
    
    unless valid_email_format?(value)
      record.errors.add(attribute, 'não é um email válido')
      return
    end
    
    unless domain_exists?(value)
      record.errors.add(attribute, 'domínio não existe')
    end
  end
  
  private
  
  def valid_email_format?(email)
    email =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
  end
  
  def domain_exists?(email)
    domain = email.split('@').last
    
    begin
      Resolv::DNS.new.getresources(domain, Resolv::DNS::Resource::IN::MX)
      true
    rescue Resolv::ResolvError
      false
    end
  end
end
```

#### Phone Number Validation

```ruby
# app/validators/phone_validator.rb
class PhoneValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?
    
    unless valid_phone_format?(value)
      record.errors.add(attribute, 'não é um telefone válido')
      return
    end
    
    unless valid_country_code?(value)
      record.errors.add(attribute, 'código de país não suportado')
    end
  end
  
  private
  
  def valid_phone_format?(phone)
    # Aceita formatos: +5511999999999, 5511999999999, 11999999999
    phone =~ /\A\+?[1-9]\d{1,14}\z/
  end
  
  def valid_country_code?(phone)
    # Verificar se é Brasil (+55) ou outros países suportados
    phone.start_with?('+55') || phone.length == 11
  end
end
```

### 3.3 Criptografia de Dados Sensíveis

#### Encrypted Attributes

```ruby
# app/models/login_code.rb
class LoginCode < ApplicationRecord
  encrypts :code, deterministic: true
  
  validates :code, presence: true, length: { is: 6 }
  validates :identifier, presence: true
  validates :method, inclusion: { in: %w[email whatsapp] }
  
  # Método para validar código sem expor o valor real
  def validate_code(input_code)
    return false if expired?
    return false if validation_attempts >= 3
    
    # Usar hash seguro para comparação
    valid = BCrypt::Password.new(code_digest) == input_code
    
    if valid
      update!(validation_attempts: 0)
    else
      increment!(:validation_attempts)
    end
    
    valid
  end
  
  private
  
  def code_digest
    @code_digest ||= BCrypt::Password.create(code)
  end
end
```

### 3.4 Segurança de Sessão

#### Secure Session Management

```ruby
# app/controllers/concerns/secure_session_concern.rb
module SecureSessionConcern
  extend ActiveSupport::Concern
  
  included do
    before_action :validate_session_security
    after_action :set_security_headers
  end
  
  private
  
  def validate_session_security
    # Verificar IP consistency
    if session[:ip_address] && session[:ip_address] != request.remote_ip
      reset_session
      render json: { error: 'Sessão inválida' }, status: :unauthorized
      return
    end
    
    # Verificar user agent
    if session[:user_agent] && session[:user_agent] != request.user_agent
      reset_session
      render json: { error: 'Sessão inválida' }, status: :unauthorized
      return
    end
    
    # Verificar tempo de sessão
    if session[:created_at] && session[:created_at] < 24.hours.ago
      reset_session
      render json: { error: 'Sessão expirada' }, status: :unauthorized
      return
    end
  end
  
  def set_security_headers
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';"
  end
  
  def create_secure_session(user)
    session[:user_id] = user.id
    session[:ip_address] = request.remote_ip
    session[:user_agent] = request.user_agent
    session[:created_at] = Time.current
    session[:secure] = true
    session[:httponly] = true
    session[:same_site] = :strict
  end
end
```

## 4. Proteção de Dados Pessoais (LGPD)

### 4.1 Consentimento e Transparência

```ruby
# app/models/user_consent.rb
class UserConsent < ApplicationRecord
  belongs_to :user
  
  CONSENT_TYPES = %w[
    terms_of_service
    privacy_policy
    marketing_communications
    data_processing
  ].freeze
  
  validates :consent_type, inclusion: { in: CONSENT_TYPES }
  validates :version, presence: true
  validates :ip_address, presence: true
  
  scope :active, -> { where(revoked_at: nil) }
  scope :for_type, ->(type) { where(consent_type: type) }
  
  def active?
    revoked_at.nil?
  end
  
  def revoke!
    update!(revoked_at: Time.current)
  end
end
```

### 4.2 Direitos do Titular

```ruby
# app/services/lgpd/data_export_service.rb
module Lgpd
  class DataExportService
    def initialize(user)
      @user = user
    end
    
    def export_all_data
      {
        personal_data: export_personal_data,
        login_history: export_login_history,
        consent_history: export_consent_history,
        data_processing_log: export_processing_log
      }
    end
    
    def export_personal_data
      {
        id: @user.id,
        email: @user.email,
        phone: @user.phone,
        name: @user.name,
        user_type: @user.user_type,
        created_at: @user.created_at,
        updated_at: @user.updated_at,
        last_login_at: @user.last_login_at,
        login_count: @user.login_count
      }
    end
    
    def export_login_history
      @user.login_attempts.order(created_at: :desc).map do |attempt|
        {
          timestamp: attempt.created_at,
          method: attempt.method,
          success: attempt.success,
          ip_address: attempt.ip_address,
          user_agent: attempt.user_agent
        }
      end
    end
    
    def export_consent_history
      @user.user_consents.order(created_at: :desc).map do |consent|
        {
          consent_type: consent.consent_type,
          version: consent.version,
          given_at: consent.created_at,
          revoked_at: consent.revoked_at,
          ip_address: consent.ip_address
        }
      end
    end
    
    def export_processing_log
      # Logs de processamento de dados
      DataProcessingLog.where(user_id: @user.id).order(created_at: :desc).map do |log|
        {
          timestamp: log.created_at,
          operation: log.operation,
          data_types: log.data_types,
          legal_basis: log.legal_basis,
          purpose: log.purpose
        }
      end
    end
  end
end
```

### 4.3 Anonimização e Pseudonimização

```ruby
# app/services/lgpd/data_anonymization_service.rb
module Lgpd
  class DataAnonymizationService
    def anonymize_user(user)
      ActiveRecord::Base.transaction do
        # Anonimizar dados pessoais
        user.update!(
          email: generate_anonymous_email(user.id),
          phone: generate_anonymous_phone(user.id),
          name: "User #{user.id}",
          anonymized_at: Time.current
        )
        
        # Remover dados sensíveis
        user.login_attempts.destroy_all
        user.user_consents.destroy_all
        
        # Manter logs anonimizados para analytics
        anonymize_login_codes(user)
        
        # Criar registro de anonimização
        create_anonymization_record(user)
      end
    end
    
    private
    
    def generate_anonymous_email(user_id)
      "anonymous_#{user_id}@deleted.local"
    end
    
    def generate_anonymous_phone(user_id)
      "+55000000000#{user_id.to_s.rjust(4, '0')}"
    end
    
    def anonymize_login_codes(user)
      user.login_codes.update_all(
        identifier: "anonymous_#{user.id}@deleted.local"
      )
    end
    
    def create_anonymization_record(user)
      DataAnonymizationLog.create!(
        user_id: user.id,
        anonymized_at: Time.current,
        reason: 'User request - LGPD Article 18'
      )
    end
  end
end
```

## 5. Auditoria e Logs

### 5.1 Audit Logging

```ruby
# app/models/audit_log.rb
class AuditLog < ApplicationRecord
  ACTIONS = %w[
    login_attempt
    login_success
    login_failure
    code_generated
    code_validated
    oauth_callback
    session_created
    session_destroyed
    consent_given
    consent_revoked
    data_exported
    data_anonymized
  ].freeze
  
  validates :action, inclusion: { in: ACTIONS }
  validates :user_id, presence: true
  validates :ip_address, presence: true
  validates :user_agent, presence: true
  
  scope :recent, -> { where('created_at > ?', 30.days.ago) }
  scope :by_action, ->(action) { where(action: action) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  
  def self.record(action, user, request, metadata = {})
    create!(
      action: action,
      user_id: user&.id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: metadata,
      created_at: Time.current
    )
  end
end
```

### 5.2 Security Event Monitoring

```ruby
# app/services/security_monitoring_service.rb
class SecurityMonitoringService
  SUSPICIOUS_PATTERNS = {
    multiple_failed_logins: { threshold: 5, timeframe: 10.minutes },
    rapid_code_requests: { threshold: 3, timeframe: 5.minutes },
    suspicious_ip_changes: { threshold: 2, timeframe: 30.minutes },
    unusual_login_times: { threshold: 1, timeframe: 1.hour }
  }.freeze
  
  def check_suspicious_activity(user, request)
    SUSPICIOUS_PATTERNS.each do |pattern, config|
      if detect_pattern?(user, request, pattern, config)
        alert_security_team(user, request, pattern)
        potentially_lock_account(user)
      end
    end
  end
  
  private
  
  def detect_pattern?(user, request, pattern, config)
    case pattern
    when :multiple_failed_logins
      AuditLog.by_user(user.id)
        .by_action('login_failure')
        .where('created_at > ?', config[:timeframe].ago)
        .count >= config[:threshold]
        
    when :rapid_code_requests
      AuditLog.by_user(user.id)
        .by_action('code_generated')
        .where('created_at > ?', config[:timeframe].ago)
        .count >= config[:threshold]
        
    when :suspicious_ip_changes
      recent_logins = AuditLog.by_user(user.id)
        .by_action('login_success')
        .where('created_at > ?', config[:timeframe].ago)
        .distinct
        .pluck(:ip_address)
        
      recent_logins.count >= config[:threshold] && !recent_logins.include?(request.remote_ip)
      
    when :unusual_login_times
      # Verificar logins fora do horário normal do usuário
      user_login_times = AuditLog.by_user(user.id)
        .by_action('login_success')
        .where('created_at > ?', 30.days.ago)
        .pluck(:created_at)
        .map(&:hour)
        
      current_hour = Time.current.hour
      usual_hours = user_login_times.uniq
      
      usual_hours.empty? || !usual_hours.include?(current_hour)
    end
  end
  
  def alert_security_team(user, request, pattern)
    SecurityMailer.suspicious_activity_alert(
      user: user,
      pattern: pattern,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    ).deliver_later
  end
  
  def potentially_lock_account(user)
    # Implementar lógica de bloqueio preventivo
    user.update!(security_locked: true, locked_at: Time.current)
  end
end
```

## 6. Vulnerability Management

### 6.1 Dependency Scanning

```ruby
# Gemfile
group :development, :test do
  gem 'bundler-audit', require: false
  gem 'brakeman', require: false
  gem 'ruby_audit', require: false
end

# lib/tasks/security.rake
namespace :security do
  desc 'Run all security checks'
  task all: [:bundle_audit, :brakeman, :ruby_audit]
  
  desc 'Check for vulnerable gems'
  task :bundle_audit do
    sh 'bundle audit check --update'
  end
  
  desc 'Run Brakeman security scanner'
  task :brakeman do
    sh 'brakeman -q -z'
  end
  
  desc 'Check Ruby vulnerabilities'
  task :ruby_audit do
    sh 'ruby-audit check'
  end
end
```

### 6.2 Security Headers

```ruby
# config/application.rb
config.force_ssl = true
config.ssl_options = {
  hsts: { expires: 1.year, subdomains: true },
  secure_cookies: true,
  secure_headers: true
}

# config/initializers/secure_headers.rb
SecureHeaders::Configuration.default do |config|
  config.x_frame_options = "DENY"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "1; mode=block"
  config.x_download_options = "noopen"
  config.x_permitted_cross_domain_policies = "none"
  config.referrer_policy = "strict-origin-when-cross-origin"
  
  config.csp = {
    default_src: %w('self'),
    script_src: %w('self' 'unsafe-inline'),
    style_src: %w('self' 'unsafe-inline'),
    img_src: %w('self' data: https:),
    font_src: %w('self'),
    connect_src: %w('self' https:),
    media_src: %w('self'),
    object_src: %w('none'),
    child_src: %w('none'),
    worker_src: %w('none'),
    frame_ancestors: %w('none'),
    form_action: %w('self'),
    base_uri: %w('self')
  }
  
  config.hsts = "max-age=#{1.year.to_i}; includeSubDomains; preload"
end
```

## 7. Incident Response

### 7.1 Security Incident Response Plan

```ruby
# app/services/incident_response_service.rb
class IncidentResponseService
  SEVERITY_LEVELS = {
    low: { response_time: 24.hours, team: 'security-analysts' },
    medium: { response_time: 4.hours, team: 'security-team' },
    high: { response_time: 1.hour, team: 'incident-response' },
    critical: { response_time: 15.minutes, team: 'all-hands' }
  }.freeze
  
  def initialize(incident)
    @incident = incident
  end
  
  def handle_security_incident
    assess_severity
    notify_team
    contain_threat
    investigate
    remediate
    document
    
    # Criar ticket para follow-up
    create_incident_ticket
  end
  
  private
  
  def assess_severity
    severity = case @incident.type
    when 'data_breach'
      :critical
    when 'unauthorized_access'
      @incident.affected_users > 100 ? :high : :medium
    when 'suspicious_activity'
      :medium
    when 'failed_login_spike'
      :low
    else
      :medium
    end
    
    @incident.update!(severity: severity)
  end
  
  def notify_team
    severity_config = SEVERITY_LEVELS[@incident.severity]
    
    SecurityMailer.incident_notification(
      incident: @incident,
      team: severity_config[:team],
      response_time: severity_config[:response_time]
    ).deliver_later
    
    # Notificações Slack/Teams para severidades altas
    if [:high, :critical].include?(@incident.severity)
      SlackNotifier.send_incident_alert(@incident)
    end
  end
  
  def contain_threat
    case @incident.type
    when 'unauthorized_access'
      # Bloquear IPs suspeitos
      block_suspicious_ips
      
      # Forçar logout de sessões afetadas
      revoke_affected_sessions
      
    when 'data_breach'
      # Isolar sistemas afetados
      isolate_affected_systems
      
      # Notificar autoridades se necessário
      notify_authorities_if_required
    end
  end
  
  def investigate
    # Coletar evidências
    collect_evidence
    
    # Analisar logs
    analyze_logs
    
    # Identificar root cause
    identify_root_cause
  end
  
  def remediate
    # Aplicar correções
    apply_fixes
    
    # Verificar se ameaça foi eliminada
    verify_remediation
    
    # Restaurar serviços
    restore_services
  end
  
  def document
    # Criar relatório completo
    generate_incident_report
    
    # Documentar lições aprendidas
    document_lessons_learned
    
    # Atualizar procedimentos
    update_procedures
  end
  
  def create_incident_ticket
    # Criar ticket no sistema de helpdesk
    # Definir follow-up actions
    # Agendar revisão post-incidente
  end
end
```

## 8. Compliance e Certificações

### 8.1 LGPD Compliance Checklist

* [x] Consent management system

* [x] Data subject rights implementation

* [x] Data processing records

* [x] Privacy by design principles

* [x] Data protection impact assessments

* [x] Breach notification procedures

* [x] Data retention policies

* [x] Cross-border data transfer controls

### 8.2 Security Certifications Roadmap

1. **SOC 2 Type II** - Sistema de controle de segurança
2. **ISO 27001** - Gestão de segurança da informação
3. **PCI DSS** - Se processamento de pagamentos
4. **ISO 27701** - Gestão de privacidade

### 8.3 Regular Security Assessments

```bash
# Penetration Testing Schedule
- Monthly: Automated vulnerability scans
- Quarterly: Manual security testing
- Annually: Full penetration test
- Ad-hoc: After major changes

# Compliance Audits
- Bi-annual: Internal security audit
- Annual: External security audit
- Annual: LGPD compliance review
```

## 9. Security Training and Awareness

### 9.1 Developer Security Training

* OWASP Top 10 awareness

* Secure coding practices

* Code review security checklist

* Incident response procedures

### 9.2 User Security Awareness

* Strong password policies

* Phishing awareness

* Social engineering prevention

* Privacy settings guidance

***

**Importante**: Esta documentação deve ser revisada e atualizada regularmente para refletir novas ameaças e requisitos regulatórios.
