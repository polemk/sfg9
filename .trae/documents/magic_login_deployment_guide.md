# Magic Login - Guia de Configuração e Deployment

## 1. Configuração de Ambiente

### 1.1 Variáveis de Ambiente - Backend
```bash
# .env.development / .env.production

# Banco de Dados
DATABASE_URL=postgresql://username:password@localhost:5432/ai9_development
REDIS_URL=redis://localhost:6379/0

# JWT & Segurança
JWT_SECRET=your-super-secret-jwt-key-min-32-characters
JWT_EXPIRATION_HOURS=24
REFRESH_TOKEN_EXPIRATION_DAYS=7

# Email (ActionMailer)
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_DOMAIN=your-domain.com
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_AUTHENTICATION=plain
SMTP_ENABLE_STARTTLS_AUTO=true

# WhatsApp (Evolution API)
EVOLUTION_BASE_URL=https://api.evolution.com
EVOLUTION_API_KEY=your-evolution-api-key
EVOLUTION_INSTANCE=your-instance-name

# OAuth
GOOGLE_CLIENT_ID=your-google-client-id
GOOGLE_CLIENT_SECRET=your-google-client-secret
FACEBOOK_APP_ID=your-facebook-app-id
FACEBOOK_APP_SECRET=your-facebook-app-secret

# Rate Limiting
RATE_LIMIT_REQUESTS_PER_MINUTE=5
RATE_LIMIT_LOGIN_ATTEMPTS=3

# Outros
RAILS_ENV=development
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true
```

### 1.2 Variáveis de Ambiente - Frontend
```bash
# .env.local / .env.production

# API
REACT_APP_API_URL=http://localhost:3000/api
REACT_APP_API_VERSION=v1

# OAuth Redirect URLs
REACT_APP_GOOGLE_REDIRECT_URI=http://localhost:3001/auth/callback
REACT_APP_FACEBOOK_REDIRECT_URI=http://localhost:3001/auth/callback

# Outros
REACT_APP_ENVIRONMENT=development
REACT_APP_DEBUG=true
GENERATE_SOURCEMAP=true
```

## 2. Configuração do Banco de Dados

### 2.1 Criação e Migração
```bash
# Criar banco de dados
rails db:create

# Executar migrações
rails db:migrate

# Popular com dados iniciais
rails db:seed
```

### 2.2 Índices e Performance
```sql
-- Índices para performance
CREATE INDEX idx_login_codes_identifier ON login_codes(identifier);
CREATE INDEX idx_login_codes_code ON login_codes(code);
CREATE INDEX idx_login_codes_created_at ON login_codes(created_at);
CREATE INDEX idx_login_codes_expires_at ON login_codes(expires_at);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_login_attempts_ip_address ON login_attempts(ip_address);
CREATE INDEX idx_login_attempts_created_at ON login_attempts(created_at);

-- Limpeza de códigos expirados (executar via cron)
DELETE FROM login_codes WHERE expires_at < NOW() - INTERVAL '1 hour';
DELETE FROM login_attempts WHERE created_at < NOW() - INTERVAL '24 hours';
```

### 2.3 Backup e Restore
```bash
# Backup completo
pg_dump -h localhost -U username -d ai9_production > backup_$(date +%Y%m%d_%H%M%S).sql

# Restore
psql -h localhost -U username -d ai9_production < backup.sql
```

## 3. Configuração do Redis

### 3.1 Configuração básica
```bash
# Instalação no Ubuntu
sudo apt-get install redis-server

# Configuração de segurança
sudo vim /etc/redis/redis.conf

# Adicionar senha
requirepass your-redis-password

# Limitar conexões
maxclients 10000

# Reiniciar Redis
sudo systemctl restart redis-server
```

### 3.2 Monitoramento Redis
```bash
# Verificar status
redis-cli ping

# Monitorar comandos em tempo real
redis-cli monitor

# Estatísticas
redis-cli info
```

## 4. Configuração de Email

### 4.1 Gmail SMTP
```ruby
# config/environments/production.rb
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address:              'smtp.gmail.com',
  port:                 587,
  domain:               'your-domain.com',
  user_name:            ENV['SMTP_USERNAME'],
  password:             ENV['SMTP_PASSWORD'],
  authentication:       'plain',
  enable_starttls_auto: true,
  open_timeout:         5,
  read_timeout:         5
}

config.action_mailer.default_url_options = { host: 'your-domain.com' }
config.action_mailer.perform_deliveries = true
config.action_mailer.raise_delivery_errors = true
```

### 4.2 Teste de Email
```ruby
# rails console
Auth::EmailService.new.send_magic_login_code(
  User.first,
  '123456'
)
```

## 5. Configuração WhatsApp (Evolution API)

### 5.1 Instalação Evolution API
```bash
# Via Docker
docker run -d \
  --name evolution-api \
  -p 8080:8080 \
  -e AUTHENTICATION_GLOBAL_AUTH_TOKEN=your-api-key \
  -e AUTHENTICATION_GLOBAL_WEBHOOK_TOKEN=your-webhook-token \
  evolution/api:latest
```

### 5.2 Configuração de Webhook
```ruby
# Adicionar webhook no Evolution
POST /instance/create
{
  "instanceName": "ai9-instance",
  "token": "your-instance-token",
  "webhook": "https://your-domain.com/api/v1/whatsapp/webhooks",
  "webhook_by_events": true,
  "events": ["MESSAGES_UPSERT", "CONNECTION_UPDATE"]
}
```

### 5.3 Teste de Envio
```ruby
# rails console
service = Auth::WhatsMessageService.new
service.send_message(
  '+5511999999999',
  'Seu código de acesso é: 123456'
)
```

## 6. Configuração OAuth

### 6.1 Google OAuth
```bash
# 1. Acessar Google Cloud Console
# 2. Criar projeto ou selecionar existente
# 3. Habilitar Google+ API
# 4. Criar credenciais OAuth 2.0
# 5. Adicionar URIs autorizadas:
#    - http://localhost:3001/auth/callback (dev)
#    - https://your-domain.com/auth/callback (prod)
```

### 6.2 Facebook OAuth
```bash
# 1. Acessar Facebook Developers
# 2. Criar aplicativo
# 3. Adicionar produto Facebook Login
# 4. Configurar URIs de redirecionamento:
#    - http://localhost:3001/auth/callback
#    - https://your-domain.com/auth/callback
```

## 7. Deployment

### 7.1 Backend (Capistrano)
```ruby
# config/deploy.rb
lock '~> 3.17.0'

set :application, 'ai9'
set :repo_url, 'git@github.com:your-org/ai9.git'
set :branch, 'main'
set :deploy_to, '/var/www/ai9'
set :keep_releases, 5

set :linked_files, %w{config/master.key .env.production}
set :linked_dirs, %w{log tmp/pids tmp/cache tmp/sockets public/system}

set :rbenv_type, :user
set :rbenv_ruby, '3.2.0'

set :puma_threads, [4, 16]
set :puma_workers, 0
set :puma_bind, 'unix:///var/www/ai9/shared/tmp/sockets/puma.sock'
set :puma_state, '/var/www/ai9/shared/tmp/pids/puma.state'
set :puma_pid, '/var/www/ai9/shared/tmp/pids/puma.pid'
set :puma_access_log, '/var/www/ai9/shared/log/puma.access.log'
set :puma_error_log, '/var/www/ai9/shared/log/puma.error.log'

namespace :deploy do
  desc 'Run seed'
  task :seed do
    on roles(:app) do
      within current_path do
        execute :bundle, :exec, 'rails', 'db:seed', 'RAILS_ENV=production'
      end
    end
  end

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      invoke 'puma:restart'
    end
  end

  after :publishing, :restart
end
```

### 7.2 Frontend (PM2)
```javascript
// ecosystem.config.js
module.exports = {
  apps: [{
    name: 'ai9-frontend',
    script: 'serve',
    args: '-s build -l 3001',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env: {
      NODE_ENV: 'production',
      REACT_APP_API_URL: 'https://api.your-domain.com/api',
      REACT_APP_ENVIRONMENT: 'production'
    }
  }]
};
```

### 7.3 Build e Deploy Frontend
```bash
# Build otimizado
npm run build

# Deploy com PM2
pm2 start ecosystem.config.js
pm2 save
pm2 startup

# Monitorar logs
pm2 logs ai9-frontend
```

## 8. Nginx Configuration

### 8.1 Backend API
```nginx
# /etc/nginx/sites-available/ai9-api
upstream ai9_backend {
  server unix:///var/www/ai9/shared/tmp/sockets/puma.sock fail_timeout=0;
}

server {
  listen 80;
  server_name api.your-domain.com;
  
  # Redirect HTTP to HTTPS
  return 301 https://$server_name$request_uri;
}

server {
  listen 443 ssl http2;
  server_name api.your-domain.com;

  ssl_certificate /etc/letsencrypt/live/api.your-domain.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/api.your-domain.com/privkey.pem;
  
  # SSL Configuration
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers HIGH:!aNULL:!MD5;
  ssl_prefer_server_ciphers on;
  
  # Security headers
  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;
  add_header X-XSS-Protection "1; mode=block";
  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
  
  # Logging
  access_log /var/log/nginx/ai9_api_access.log;
  error_log /var/log/nginx/ai9_api_error.log;
  
  # Rate limiting
  limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
  limit_req zone=api burst=20 nodelay;
  
  location / {
    proxy_pass http://ai9_backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # Timeouts
    proxy_connect_timeout 30s;
    proxy_send_timeout 30s;
    proxy_read_timeout 30s;
  }
  
  location /cable {
    proxy_pass http://ai9_backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

### 8.2 Frontend
```nginx
# /etc/nginx/sites-available/ai9-frontend
server {
  listen 80;
  server_name your-domain.com;
  
  return 301 https://$server_name$request_uri;
}

server {
  listen 443 ssl http2;
  server_name your-domain.com;

  ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
  
  # SSL Configuration
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_ciphers HIGH:!aNULL:!MD5;
  ssl_prefer_server_ciphers on;
  
  # Security headers
  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;
  add_header X-XSS-Protection "1; mode=block";
  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
  
  # Gzip compression
  gzip on;
  gzip_vary on;
  gzip_min_length 1024;
  gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;
  
  root /var/www/ai9-frontend/build;
  index index.html;
  
  # Handle React Router
  location / {
    try_files $uri $uri/ /index.html;
  }
  
  # Static assets with cache
  location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
  }
  
  # API proxy (opcional, se frontend e backend no mesmo domínio)
  location /api {
    proxy_pass http://ai9_backend;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```

## 9. Monitoramento e Logs

### 9.1 Configuração de Logs
```ruby
# config/environments/production.rb
config.log_level = :info
config.log_formatter = ::Logger::Formatter.new

# Logs estruturados em JSON
config.logger = ActiveSupport::Logger.new(STDOUT)
config.logger.formatter = proc do |severity, datetime, progname, msg|
  {
    timestamp: datetime.iso8601,
    level: severity,
    message: msg,
    service: 'ai9-api',
    environment: Rails.env
  }.to_json + "\n"
end

# Lograge para requests
config.lograge.enabled = true
config.lograge.formatter = Lograge::Formatters::Json.new
config.lograge.custom_options = lambda do |event|
  {
    request_id: event.payload[:request_id],
    user_id: event.payload[:user_id],
    ip: event.payload[:ip],
    user_agent: event.payload[:user_agent]
  }
end
```

### 9.2 Monitoramento com Sentry
```ruby
# Gemfile
gem 'sentry-ruby'
gem 'sentry-rails'

# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.environment = Rails.env
  config.enabled_environments = %w[production staging]
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  config.traces_sample_rate = 0.1
end
```

### 9.3 Health Checks
```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def index
    checks = {
      database: database_check,
      redis: redis_check,
      email: email_check
    }
    
    overall_health = checks.values.all? { |check| check[:status] == 'ok' }
    
    status = overall_health ? :ok : :service_unavailable
    render json: { 
      status: overall_health ? 'healthy' : 'unhealthy',
      checks: checks,
      timestamp: Time.current.iso8601
    }, status: status
  end
  
  private
  
  def database_check
    ActiveRecord::Base.connection.execute('SELECT 1')
    { status: 'ok', message: 'Database connection successful' }
  rescue StandardError => e
    { status: 'error', message: e.message }
  end
  
  def redis_check
    Rails.cache.redis.ping
    { status: 'ok', message: 'Redis connection successful' }
  rescue StandardError => e
    { status: 'error', message: e.message }
  end
  
  def email_check
    # Testar conexão SMTP sem enviar email
    smtp = Net::SMTP.new(ENV['SMTP_ADDRESS'], ENV['SMTP_PORT'])
    smtp.enable_starttls_auto
    smtp.start(ENV['SMTP_DOMAIN'], ENV['SMTP_USERNAME'], ENV['SMTP_PASSWORD'], :plain)
    smtp.finish
    { status: 'ok', message: 'SMTP connection successful' }
  rescue StandardError => e
    { status: 'error', message: e.message }
  end
end
```

## 10. Manutenção

### 10.1 Limpeza de Dados
```ruby
# lib/tasks/maintenance.rake
namespace :maintenance do
  desc 'Limpar códigos de login expirados'
  task cleanup_expired_codes: :environment do
    count = LoginCode.where('expires_at < ?', 1.hour.ago).delete_all
    Rails.logger.info "Deleted #{count} expired login codes"
  end
  
  desc 'Limpar tentativas de login antigas'
  task cleanup_old_attempts: :environment do
    count = LoginAttempt.where('created_at < ?', 24.hours.ago).delete_all
    Rails.logger.info "Deleted #{count} old login attempts"
  end
  
  desc 'Limpar tokens de refresh expirados'
  task cleanup_expired_refresh_tokens: :environment do
    count = RefreshToken.where('expires_at < ?', Time.current).delete_all
    Rails.logger.info "Deleted #{count} expired refresh tokens"
  end
  
  desc 'Executar todas as limpezas'
  task all: [:cleanup_expired_codes, :cleanup_old_attempts, :cleanup_expired_refresh_tokens]
end
```

### 10.2 Cron Jobs
```bash
# Adicionar ao crontab
# Limpar dados expirados diariamente às 3 AM
0 3 * * * cd /var/www/ai9/current && RAILS_ENV=production bundle exec rake maintenance:all

# Backup diário do banco
0 2 * * * /usr/bin/pg_dump -h localhost -U username -d ai9_production > /backups/ai9_$(date +\%Y\%m\%d).sql
```

### 10.3 Performance Monitoring
```ruby
# Gemfile
gem 'rack-mini-profiler'
gem 'bullet'

# config/environments/development.rb
config.after_initialize do
  Bullet.enable = true
  Bullet.alert = true
  Bullet.bullet_logger = true
  Bullet.console = true
  Bullet.rails_logger = true
end
```

## 11. Troubleshooting

### 11.1 Problemas Comuns

**Código não chega por email:**
1. Verificar configuração SMTP
2. Verificar spam/junk folder
3. Verificar logs de email
4. Testar conexão SMTP manualmente

**Código não chega por WhatsApp:**
1. Verificar conexão Evolution API
2. Verificar número de telefone formatado corretamente
3. Verificar quota de mensagens
4. Verificar logs de webhook

**OAuth não funciona:**
1. Verificar Client ID/Secret
2. Verificar URIs de redirecionamento
3. Verificar HTTPS em produção
4. Verificar CORS configuration

**Performance lenta:**
1. Verificar índices do banco
2. Verificar N+1 queries
3. Verificar cache Redis
4. Verificar logs de slow queries

### 11.2 Debug em Desenvolvimento
```ruby
# rails console
# Testar serviço de email
Auth::EmailService.new.send_magic_login_code(User.first, '123456')

# Testar serviço WhatsApp
Auth::WhatsMessageService.new.send_message('+5511999999999', 'Test message')

# Verificar códigos ativos
LoginCode.where(identifier: 'test@example.com').last

# Verificar tentativas de login
LoginAttempt.where(ip_address: '127.0.0.1').count
```

### 11.3 Logs de Debug
```bash
# Ver logs em tempo real
tail -f log/development.log

# Filtrar logs por componente
grep "MagicLogin" log/development.log

# Ver logs de erro
tail -f log/production.log | grep ERROR

# Ver logs de email
tail -f log/mail.log
```

## 12. Checklist de Deployment

### 12.1 Pré-deployment
- [ ] Todos os testes passando
- [ ] Código revisado e aprovado
- [ ] Migrations testadas
- [ ] Variáveis de ambiente configuradas
- [ ] Backups do banco verificados
- [ ] SSL certificates válidos

### 12.2 Deployment
- [ ] Executar migrations
- [ ] Executar seeds se necessário
- [ ] Reiniciar serviços
- [ ] Verificar health checks
- [ ] Testar fluxos críticos
- [ ] Monitorar erros e performance

### 12.3 Pós-deployment
- [ ] Verificar logs por erros
- [ ] Testar todos os métodos de login
- [ ] Verificar monitoramento
- [ ] Atualizar documentação
- [ ] Comunicar mudanças aos usuários
- [ ] Preparar rollback se necessário

---

**Importante**: Sempre teste em