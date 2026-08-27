#!/bin/bash
set -e

echo "=========================================================="
echo "    🚀 DEPLOY AUTOMÁTICO (RAILS + REACT + SIDEKIQ) 🚀    "
echo "=========================================================="
echo ""

# ----------------------------------------------------
# 1. COLETAR VARIÁVEIS DO USUÁRIO E DO SISTEMA
# ----------------------------------------------------

echo "Por favor, insira as informações para construir o ambiente."

read -p "Nome do Aplicativo (usado para o systemd/nginx, ex: tru): " APP_NAME
read -p "Dominio Frontend (ex: tru.com.br): " PRIMARY_DOMAIN
read -p "Dominio Backend/API (ex: api.tru.com.br): " API_DOMAIN

echo ""
echo "Configuração de Portas:"
# Os padrões são os MESMOS do `bin/dev` deste repositório (3026/5185), e não os
# 3000/5173 genéricos do ai9 — o Safegold divide a bancada com outros apps, e
# repetir a porta do vizinho é o defeito que essa escolha evita.
read -p "Porta do Backend (Padrão: 3026): " RAILS_PORT
RAILS_PORT=${RAILS_PORT:-3026}
read -p "Porta do Frontend (Padrão: 5185): " VITE_PORT
VITE_PORT=${VITE_PORT:-5185}

# Redis compartilhado com segurança — isolamento via prefixo APP_NAME nas filas do Sidekiq
REDIS_URL="redis://localhost:6379/0"

echo ""
echo "Configuração de APIs de Integração (Opcional - deixe em branco para preencher depois no .env):"
read -p "N8N API Key: " N8N_API_KEY
read -p "N8N Webhook URL (Website Chat): " N8N_WEBHOOK_URL

echo ""
echo "Escolha o ambiente do Asaas:"
echo "1) Sandbox (https://api-sandbox.asaas.com/v3)"
echo "2) Produção (https://api.asaas.com/v3)"
read -p "Opção [1]: " ASAAS_ENV_OPTION
ASAAS_ENV_OPTION=${ASAAS_ENV_OPTION:-1}
if [ "$ASAAS_ENV_OPTION" == "2" ]; then
  ASAAS_API_URL="https://api.asaas.com/v3"
else
  ASAAS_API_URL="https://api-sandbox.asaas.com/v3"
fi
read -p "ASAAS API Key: " ASAAS_API_KEY

echo ""
read -p "Evolution (WhatsApp) Server URL: " WHATS_SERVER_URL
read -p "WhatsApp Authentication API Key: " WHATS_API_KEY

echo ""
echo "Configuração de SMTP (Email):"
read -p "SMTP Address (Padrão: mail.example.com): " SMTP_ADDRESS
SMTP_ADDRESS=${SMTP_ADDRESS:-mail.example.com}
read -p "SMTP Port (Padrão: 587): " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-587}
read -p "SMTP Username (Padrão: alerts@example.com): " SMTP_USERNAME
SMTP_USERNAME=${SMTP_USERNAME:-alerts@example.com}
read -p "SMTP Sender (Padrão: alerts@example.com): " SMTP_SENDER
SMTP_SENDER=${SMTP_SENDER:-alerts@example.com}
read -p "SMTP Domain (Padrão: example.com): " SMTP_DOMAIN
SMTP_DOMAIN=${SMTP_DOMAIN:-example.com}
read -p "Mailer From (Padrão: alerts@example.com): " MAILER_FROM
MAILER_FROM=${MAILER_FROM:-alerts@example.com}
read -p "SMTP Password: " SMTP_PASSWORD

echo ""
read -p "Google API Key (Frontend): " GOOGLE_API_KEY

echo ""
echo "Base de dados inicial:"
echo "  Os catálogos de REFERÊNCIA (tipos de recebível, carteiras, tipos de"
echo "  movimentação, fontes de recurso…) entram sempre — a aplicação não abre"
echo "  sem eles, e a tarefa é idempotente."
echo ""
echo "  A base de DEMONSTRAÇÃO é o conteúdo da apresentação: projetos, empresas,"
echo "  portadores, borderôs, operações e indicadores FICTÍCIOS. Nenhum dado real"
echo "  de cliente entra por aqui — a carga de produção é o ETL, noutro passo."
read -p "Semear a base de demonstração? [S/n]: " SEED_DEMO
SEED_DEMO=${SEED_DEMO:-S}

echo ""
echo "Configuração do Banco de Dados PostgreSQL da Aplicação:"
read -p "Nome do Banco de Dados (ex: tru_production): " DB_NAME
read -p "Usuário do Banco de Dados (ex: tru_user): " DB_USER
read -s -p "Senha do Banco de Dados: " DB_PASS
echo ""

echo ""
echo "Para criar essa base, digite a senha do superusuário 'postgres' do sistema:"
read -s -p "🔑 Senha do Postgres (usuário postgres): " PGPASSWORD_SUPER
echo ""

# Absolute path of the current directory where the repo is
REPO_DIR="$PWD"

# ----------------------------------------------------
# 2. CONFIGURAR VARIÁVEIS (.env) E (database.yml)
# ----------------------------------------------------
echo -e "\n⚙️ Gerando os arquivos .env do backend e frontend..."

# Preserva as chaves se o .env já existir para não derrubar sessões
if [ -f backend/.env ]; then
  echo "🔍 Arquivo .env detectado. Preservando chaves de segurança antigas..."
  EXISTING_JWT=$(grep '^JWT_SECRET_KEY=' backend/.env | cut -d '=' -f 2)
  EXISTING_SECRET=$(grep '^SECRET_KEY_BASE=' backend/.env | cut -d '=' -f 2)
fi

JWT_SECRET_KEY=${EXISTING_JWT:-$(openssl rand -hex 64)}
RAILS_MASTER_KEY=${EXISTING_SECRET:-$(openssl rand -hex 16)}

cat <<EOF > backend/.env
# Backend Environment Variables
APP_NAME=${APP_NAME}
REDIS_URL=${REDIS_URL}

N8N_WEBHOOK_WEBSITE_CHAT=${N8N_WEBHOOK_URL}
N8N_API_KEY=${N8N_API_KEY}

RAILS_ENV=production
PORT=${RAILS_PORT}
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true

# CORS Configuration
CORS_ORIGINS=https://${PRIMARY_DOMAIN}

# JWT Configuration
DEVISE_JWT_SECRET_KEY=${JWT_SECRET_KEY}
JWT_SECRET_KEY=${JWT_SECRET_KEY}
JWT_EXPIRATION_TIME=15
JWT_REFRESH_EXPIRATION_TIME=10080

# Integration APIs
ASAAS_API_KEY='${ASAAS_API_KEY}'
ASAAS_API_URL=${ASAAS_API_URL}
ASAAS_INVOICE_SERVICE_ID=178941
ASAAS_INVOICE_SERVICE_NAME='6203-1/00 - Licenciamento ou cessão de direito de uso de programas de computação'
ASAAS_INVOICE_SERVICE_CODE=1.05
ASAAS_INVOICE_UPDATE_PAYMENT=false
ASAAS_INVOICE_DEDUCTIONS=0
ASAAS_INVOICE_EFFECTIVE_DATE=ON_PAYMENT_CONFIRMATION
ASAAS_INVOICE_RECEIVED_ONLY=true
ASAAS_INVOICE_RETAIN_ISS=false
ASAAS_INVOICE_COFINS=0
ASAAS_INVOICE_CSLL=0
ASAAS_INVOICE_INSS=0
ASAAS_INVOICE_IR=0
ASAAS_INVOICE_PIS=0
ASAAS_INVOICE_ISS=0

WHATS_SERVER_TYPE=https
WHATS_SERVER_URL=${WHATS_SERVER_URL}
WHATS_AUTHENTICATION_API_KEY=${WHATS_API_KEY}
WHATS_CORS_ORIGIN=*
WHATS_CORS_METHODS=GET,POST,PUT,DELETE
WHATS_CORS_CREDENTIALS=true
WHATS_LOG_LEVEL=ERROR,WARN,DEBUG,INFO,LOG,VERBOSE,DARK,WEBHOOKS,WEBSOCKET
WHATS_LOG_COLOR=true
WHATS_CONFIG_SESSION_PHONE_CLIENT='${APP_NAME} API'
WHATS_CONFIG_SESSION_PHONE_NAME=${APP_NAME}
WHATS_LANGUAGE=en

# Security
SECRET_KEY_BASE=${RAILS_MASTER_KEY}

# Rate Limiting
RATE_LIMIT_REQUESTS_PER_MINUTE=60
RATE_LIMIT_BURST=10

OAUTH_REDIRECT_URI=https://${API_DOMAIN}/auth/callback
OAUTH_GOOGLE_REDIRECT_URI=https://${API_DOMAIN}/auth/callback
OAUTH_FACEBOOK_REDIRECT_URI=https://${API_DOMAIN}/auth/callback

FRONTEND_CALLBACK_URL=https://${PRIMARY_DOMAIN}/auth/callback

# Email Configuration
SMTP_ADDRESS=${SMTP_ADDRESS}
SMTP_PORT=${SMTP_PORT}
SMTP_USERNAME=${SMTP_USERNAME}
SMTP_SENDER=${SMTP_SENDER}
SMTP_PASSWORD='${SMTP_PASSWORD}'
SMTP_AUTHENTICATION=login
SMTP_DOMAIN=${SMTP_DOMAIN}
SMTP_TLS_ENABLED=true
SMTP_DELIVERING=async
MAILER_FROM=${MAILER_FROM}

APP_HOST=${PRIMARY_DOMAIN}
API_HOST=${API_DOMAIN}
EOF

cat <<EOF > frontend/.env
# Frontend Environment Variables
VITE_API_URL=https://${API_DOMAIN}
VITE_WS_URL=wss://${API_DOMAIN}/cable
VITE_APP_NAME=${APP_NAME}
VITE_APP_VERSION=1.0.0

# Theme Configuration
VITE_DEFAULT_THEME=dark

# Feature Flags
VITE_ENABLE_ANALYTICS=false
VITE_ENABLE_ERROR_REPORTING=true

# Google API Key
VITE_GOOGLE_API_KEY=${GOOGLE_API_KEY}

# Build Configuration
VITE_BUILD_MODE=production
VITE_PORT=${VITE_PORT}
EOF

echo "Arquivos .env gerados com sucesso."

echo -e "⚙️ Criando backend/config/database.yml (apenas bloco production)..."

cat <<EOF > backend/config/database.yml
production:
  adapter: postgresql
  encoding: unicode
  pool: 10
  host: localhost
  username: '${DB_USER}'
  password: '${DB_PASS}'
  database: '${DB_NAME}'
EOF

echo "database.yml gerado."


# ----------------------------------------------------
# 3. CONFIGURAR BANCO DE DADOS NATIVO (CRIAÇÃO/MIGRAÇÃO)
# ----------------------------------------------------
RUBY="/usr/local/rvm/rubies/ruby-3.2.3/bin/ruby"
export GEM_HOME="/usr/local/rvm/gems/ruby-3.2.3"
export GEM_PATH="/usr/local/rvm/gems/ruby-3.2.3:/usr/local/rvm/gems/ruby-3.2.3@global"
export PATH="/usr/local/rvm/gems/ruby-3.2.3/bin:/usr/local/rvm/gems/ruby-3.2.3@global/bin:/usr/local/rvm/rubies/ruby-3.2.3/bin:${PATH}"

echo -e "\n🗄️ Criando banco '${DB_NAME}' e usuário '${DB_USER}' via Postgres Nativamente..."

sudo -u postgres bash -c "
    set -euo pipefail
    export PGPASSWORD='${PGPASSWORD_SUPER}'

    # Cria role superusuario se não existir
    ROLE_EXISTS=\$(psql -U postgres -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'\")
    if [[ \"\$ROLE_EXISTS\" != '1' ]]; then
        echo '👤 Criando usuário ${DB_USER}'
        psql -U postgres -c \"CREATE ROLE \\\"${DB_USER}\\\" LOGIN PASSWORD '${DB_PASS}';\"
    else
        echo '✅ Usuário ${DB_USER} já existe. Atualizando senha...'
        psql -U postgres -c \"ALTER ROLE \\\"${DB_USER}\\\" PASSWORD '${DB_PASS}';\"
    fi

    # Garante superuser (necessário para pg_vector etc)
    psql -U postgres -c \"ALTER ROLE \\\"${DB_USER}\\\" SUPERUSER CREATEDB LOGIN;\"

    # Cria banco se não existir
    DB_EXISTS=\$(psql -U postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'\")
    if [[ \"\$DB_EXISTS\" != '1' ]]; then
        echo '🗃️ Criando banco ${DB_NAME}'
        createdb -U postgres -O \"${DB_USER}\" \"${DB_NAME}\"
    else
        echo '✅ Banco ${DB_NAME} já existe.'
    fi
"

# Executar migrações do rails após a criação do db/user
echo -e "\n📦 Preparando o Backend Rails..."
(
  cd backend

  echo "📁 Criando diretórios essenciais (log, tmp)..."
  mkdir -p log tmp/pids tmp/sockets tmp/cache
  touch log/production.log

  if [ ! -f Gemfile ]; then
    echo "📦 Criando Gemfile a partir do Gemfile.example..."
    cp Gemfile.example Gemfile
  fi

  echo "📦 Instalando dependências do Ruby (bundle install)..."
  RAILS_ENV=production bundle install

  # ------------------------------------------------------------------
  # ESQUEMA E SEMENTES — três passos, e não um
  # ------------------------------------------------------------------
  # Rodar só `db:seed` deixava a apresentação abrindo num sistema VAZIO. Esse
  # é o seed da base ai9 (contas, client application, instância do WhatsApp);
  # ele não conhece o Safegold.
  #
  #   1. db:migrate       — o esquema.
  #   2. db:seed          — a base ai9: contas e configuração da plataforma.
  #   3. reference:seed   — os catálogos que a aplicação EXIGE para abrir
  #                         (tipos de recebível, carteiras, tipos de
  #                         movimentação, fontes de recurso). Idempotente, e
  #                         semeia com o MESMO `legacy_id` que o ETL usa como
  #                         chave natural: rodar isto antes da carga faz o ETL
  #                         ATUALIZAR em vez de duplicar.
  #   4. demo:seed        — o conteúdo da apresentação, se pedido.
  #
  # A carga de produção NÃO está aqui: ela é `rake sfg_etl:load`, roda no
  # servidor com o dump do cliente e tem runbook próprio.
  echo "🚀 [1/3] Esquema e base da plataforma (db:migrate + db:seed)..."
  RAILS_ENV=production bundle exec rails db:migrate db:seed

  echo "🚀 [2/3] Catálogos de referência (reference:seed)..."
  RAILS_ENV=production bundle exec rake reference:seed

  if [[ "${SEED_DEMO^^}" != "N" ]]; then
    echo "🚀 [3/3] Base de demonstração (demo:seed)..."
    RAILS_ENV=production bundle exec rake demo:seed
  else
    echo "⏭️  [3/3] Base de demonstração PULADA por escolha na instalação."
  fi
)
# **Sem `|| echo aviso`, e de propósito.** A versão anterior engolia a falha:
# migração quebrada ou seed que estourou viravam uma linha amarela, o script
# seguia, o systemd subia e a apresentação abria num banco vazio — com o
# instalador dizendo que deu tudo certo. Com `set -e` no topo, falhar aqui
# INTERROMPE a instalação, que é o comportamento útil.
#
# É a mesma razão pela qual `demo:seed` aborta quando um escritor falha (ver
# `lib/tasks/demo.rake`): seed que imprime "FALHOU" e sai com 0 é seed que
# passa despercebido num script de deploy.

# ----------------------------------------------------
# 4. CRIAR E ATIVAR SYSTEMD SERVICE
# ----------------------------------------------------
echo -e "\n⚙️ Configurando o serviço Systemd..."

SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"

sudo tee "${SERVICE_FILE}" > /dev/null <<SERVICE_EOF
[Unit]
Description=${APP_NAME} Production Application (Rails + React + Sidekiq)
After=network.target postgresql.service redis.service

[Service]
# User and Group to run the application
# We use root for simplicity as per the bin/prod script using NVM globally,
# but it could be changed if needed.
User=root
Group=root

# Working Directory
WorkingDirectory=${REPO_DIR}

# Enviroment
Environment=RAILS_ENV=production
Environment=RAILS_PORT=${RAILS_PORT}
Environment=VITE_PORT=${VITE_PORT}

# ExecStart points to the bin/prod script
ExecStart=${REPO_DIR}/bin/prod

# Restart configuration
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE_EOF

echo "Recarregando daemon do systemd e iniciando ${APP_NAME}.service..."
sudo systemctl daemon-reload
sudo systemctl enable ${APP_NAME}.service
sudo systemctl start ${APP_NAME}.service

echo "Esperando serviços iniciarem..."
sleep 5

# ----------------------------------------------------
# 5. CONFIGURAR NGINX E SSL (OPCIONAL)
# ----------------------------------------------------
echo -e "\n⚠️ NOTA: A configuração de SSL exige que o DNS já esteja apontando para este IP."
echo "Para pular esta etapa e usar apenas em portas locais, digite 'n'."
read -p "Deseja configurar o Nginx e o SSL Let's Encrypt agora? [S/n]: " CONFIG_NGINX

if [[ "$CONFIG_NGINX" =~ ^[Nn]$ ]]; then
    echo -e "\n⏩ Pulando a configuração do Nginx e SSL."
else
    echo -e "\n🔒 Preparando Nginx para o desafio do Certbot (Zero Downtime)..."

    NGINX_CONF_PATH="/etc/nginx/apps.d/${APP_NAME}.conf"

    # PASSO A: Configuração HTTP-only temporária para o acme-challenge
    sudo tee "${NGINX_CONF_PATH}" > /dev/null <<NGINX_TEMP
server {
    listen 80;
    listen [::]:80;
    server_name PLACEHOLDER_DOMAINS;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
NGINX_TEMP

    # Substituir o placeholder pelos domínios reais
    sudo sed -i "s/PLACEHOLDER_DOMAINS/${PRIMARY_DOMAIN} ${API_DOMAIN}/" "${NGINX_CONF_PATH}"

    sudo systemctl reload nginx || { echo "⚠️ Aviso: O reload do Nginx falhou, verifique o arquivo de log ou as configurações do servidor."; }

    echo -e "\n🔒 Solicitando certificados Let's Encrypt via Webroot..."
    sudo certbot certonly --webroot -w /var/www/html -d "${PRIMARY_DOMAIN}" -d "${API_DOMAIN}" || { echo "⚠️ Aviso: Certbot falhou (provável erro de DNS). O proxy reverso não terá SSL válido."; }

    # ----------------------------------------------------
    # 6. CONFIGURAR NGINX DEFINITIVO (PATHS & HTTPS)
    # ----------------------------------------------------
    echo -e "\n🏗️ Escrevendo as regras finais do Nginx Proxy (SSL Ativado)..."

    sudo tee "${NGINX_CONF_PATH}" > /dev/null <<NGINX_FINAL
server {
    listen 80;
    listen [::]:80;
    server_name ${PRIMARY_DOMAIN} ${API_DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# -------------------------
# API DOMAIN (Backend)
# -------------------------
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${API_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${PRIMARY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${PRIMARY_DOMAIN}/privkey.pem;

    client_max_body_size 500m;
    # --- Security headers (API) --- HSTS ja vem do Rails (force_ssl)
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    # CSP acomoda o /docs (Stoplight via unpkg); respostas JSON ignoram CSP
    add_header Content-Security-Policy "default-src 'none'; script-src https://unpkg.com; style-src 'unsafe-inline' https://unpkg.com; img-src 'self' data: https:; font-src data: https://unpkg.com; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'" always;

    location / {
        proxy_pass http://127.0.0.1:${RAILS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Action Cable WebSockets Support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
    }
}

# -------------------------
# PRIMARY DOMAIN (Frontend Vite)
# -------------------------
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${PRIMARY_DOMAIN};

    ssl_certificate     /etc/letsencrypt/live/${PRIMARY_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${PRIMARY_DOMAIN}/privkey.pem;

    client_max_body_size 50m;
    # --- Security headers (frontend) ---
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), geolocation=(), microphone=(self), display-capture=(self)" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' https://www.youtube.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' data: https://fonts.gstatic.com; img-src 'self' data: blob: https:; media-src 'self' blob: https:; connect-src 'self' https://${API_DOMAIN} wss://${API_DOMAIN} https://fonts.gstatic.com https://vimeo.com; frame-src https://www.youtube.com https://www.youtube-nocookie.com https://player.vimeo.com; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'" always;

    location / {
        # npx serve is running on VITE_PORT
        proxy_pass http://127.0.0.1:${VITE_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX_FINAL

    echo "Reloading Nginx with HTTPS configuration..."
    sudo systemctl reload nginx || true
fi

echo "=========================================================="
echo " ✅ DEPLOY CONCLUÍDO COM SUCESSO! (Zero Downtime)"
echo " O projeto deve estar rodando em:"
echo " 🌐 Frontend: https://${PRIMARY_DOMAIN}"
echo " 🔌 API: https://${API_DOMAIN}"
echo "=========================================================="
echo " Status do serviço sistema:"
echo " sudo systemctl status ${APP_NAME}.service"
echo " Logs do sistema:"
echo " sudo journalctl -u ${APP_NAME}.service -f"
echo "=========================================================="
