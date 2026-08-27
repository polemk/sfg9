# Rails 8 API + React TypeScript

Sistema completo com backend Rails 8 API e frontend React TypeScript, incluindo integrações com Asaas (pagamentos) e Evolution API (WhatsApp).

## 🚀 Tecnologias

### Backend (Rails 8 API)

- Rails 8 (API-only)
- Grape para APIs RESTful
- Swagger/OpenAPI documentation
- PostgreSQL
- Redis
- Sidekiq para background jobs
- Action Cable para WebSocket
- JWT authentication
- Rack Attack para rate limiting

### Frontend (React + TypeScript)

- React 18 com TypeScript
- Vite para build e dev server
- React Router para navegação
- React Query para gerenciamento de estado do servidor
- Zustand para estado global
- Tailwind CSS para estilização
- Action Cable para WebSocket
- Lucide React para ícones

## 📋 Pré-requisitos

- Ruby 3.2.0+
- Node.js 20+
- PostgreSQL 14+
- Redis 6+
- Docker (opcional)

## 🔧 Instalação

### Opção 1: Setup Automatizado

```bash
# Clone o repositório
git clone <url-do-repositorio>
cd ai9

# Execute o script de setup
chmod +x setup.sh
./setup.sh
```

### Opção 2: Setup Manual

#### Backend

```bash
cd backend
bundle install
rails db:create db:migrate
rails server
```

#### Frontend

```bash
cd frontend
npm install
npm run dev
```

### Opção 3: Docker

```bash
# Desenvolvimento
docker-compose up

# Produção
docker-compose -f docker-compose.prod.yml up
```

## 👤 Como criar seu Usuário Admin (Seeds)

Para acessar o painel administrativo e ter permissões totais, você deve adicionar seu e-mail no arquivo de "seeds" (dados iniciais) do sistema.

1. **Edite o arquivo `backend/db/seeds.rb`**:
   - No topo do arquivo, mude `should_perform_users` de `false` para `true`.
   - Procure pelo trecho `if should_perform_users` (perto da linha 492).
   - Adicione seus dados copiando o modelo abaixo e colando dentro desse bloco:

```ruby
# Adicione isso dentro do bloco 'if should_perform_users'
meu_usuario = User.find_or_initialize_by(email: 'seu.email@exemplo.com')
meu_usuario.assign_attributes(
  name: 'Seu Nome',
  phone: '5599999999999', # Importante: Use DDI (55) + DDD + Número
  user_type: og_type,     # Garante acesso total (Admin)
  provider: nil,
  provider_uid: nil
)
meu_usuario.save!
puts "✅ Usuário criado: #{meu_usuario.email}"
```

2. **Rode o comando para salvar no banco**:
   No terminal, dentro da pasta `backend`, execute:

   ```bash
   rails db:seed
   ```

3. **Pronto!** Agora faça login usando o e-mail cadastrado.

## 📚 Documentação

- [Documentação de Setup](BUILD_SYSTEM.md)
- [Regras do Projeto](.trae/rules/project_rules.md)
- API Documentation: `http://localhost:3000/swagger_doc`
- Stoplight Elements: `http://localhost:3000/docs`

### 🔐 Autenticação JWT e Client Application

- Tipos de token:

  - Token de Usuário (JWT): emitido após login (Magic Login, OAuth). Assinado com `HS256` e expira em 15 minutos. Possui refresh token válido por 7 dias.
  - Token de Client Application (vitalício): string estática cadastrada via seeds e usada por integrações e fluxos sem usuário autenticado (ex.: envio de mensagem de WhatsApp na página de login).

- Headers:

  - `Authorization: Bearer <token>`

- Uso:
  - Endpoints exigem token válido (JWT de usuário OU token de Client Application), exceto webhooks do WhatsApp e documentação Swagger.
- O endpoint `POST /whats/v1/messages/send_message` exige token de Client Application.

- Renovação:

  - `POST /api/auth/v1/sessions/refresh` com `refresh_token` retorna novo par de tokens.

- Erros comuns:
  - 401 `unauthorized`: token ausente, inválido ou expirado
  - 403 `forbidden`: acesso negado
  - 429 `rate_limit_exceeded`: muitas tentativas

### 🔑 Client Application

- Modelo: `ClientApplication(name, token, active)`
- Seeds criam apps padrão (`ASAAS`, `FRONTEND_PUBLIC`) com tokens gerados e ativos.
- Tokens são vitalícios (não expiram) e devem ser mantidos em segredo.

### 🔓 Fluxo de Magic Login

- `POST /api/v1/auth/pre-register` solicita código (email/WhatsApp) mesmo sem conta existente.
- `POST /api/v1/auth/verify-code` valida código (checa expiração e correspondência).
- `POST /api/v1/auth/complete-registration` conclui cadastro (nome + campo complementar) e emite tokens JWT.
  - Regras de validação: nome mínimo 3 caracteres; email padrão; WhatsApp em formato internacional (10–15 dígitos, sem `+`).
  - Segurança: rate limit, bloqueio de brute force, expiração em 5 min, tentativas máximas.
- Segurança: rate limit, bloqueio de brute force, expiração e tentativas máximas.

## 🧪 Testes

### Backend

```bash
cd backend
bundle exec rspec
```

### Frontend

```bash
cd frontend
npm test
```

## 🚀 Deploy

### CI/CD

O projeto inclui GitHub Actions para:

- Testes automatizados
- Linting e análise de segurança
- Build e deploy

### Produção

```bash
# Backend
cd backend
RAILS_ENV=production bundle exec rails server

# Frontend
cd frontend
npm run build
npm run preview
```

## 🔐 Variáveis de Ambiente

### 1. Backend (`backend/.env`)

Configure as variáveis de integração, banco e segurança.

| Variável                       | Descrição                                   | Onde conseguir                                                                                                     |
| :----------------------------- | :------------------------------------------ | :----------------------------------------------------------------------------------------------------------------- |
| **Integrações**                |                                             |                                                                                                                    |
| `ASAAS_API_KEY`                | Chave de API do Asaas (Sandbox ou Produção) | Painel Asaas > Configurações > Integrações > API Web                                                               |
| `ASAAS_API_URL`                | URL base do Asaas                           | Sandbox: `https://api-sandbox.asaas.com/v3` <br> Prod: `https://api.asaas.com/v3`                                  |
| `WHATS_SERVER_URL`             | URL da sua instância da Evolution API       | Seu servidor Evolution API                                                                                         |
| `WHATS_AUTHENTICATION_API_KEY` | API Key Global da Evolution API             | Definida no `env` da Evolution API                                                                                 |
| `N8N_WEBHOOK_...`              | URLs dos workflows do N8N                   | Seus Workflows do N8N (Webhook node)                                                                               |
| **Segurança & Auth**           |                                             |                                                                                                                    |
| `DEVISE_JWT_SECRET_KEY`        | Chave secreta para assinar tokens JWT       | Gere com `bundle exec rails secret`                                                                                |
| `SECRET_KEY_BASE`              | Conteúdo da `master.key` (Credentials)      | Pegue o conteúdo de `backend/config/master.key`. Se não existir: `cd backend && EDITOR=vim rails credentials:edit` |
| `CORS_ORIGINS`                 | Domínios permitidos para chamar a API       | Ex: `http://localhost:5173,https://meu-site.com` (sem espaços)                                                     |
| **Email (SMTP)**               |                                             |                                                                                                                    |
| `SMTP_ADDRESS`                 | Host do servidor de email                   | Ex: `smtp.sendgrid.net`, `smtp.gmail.com`                                                                          |
| `SMTP_USERNAME`                | Usuário/Email autenticador                  | Painel do provedor de email                                                                                        |
| `SMTP_PASSWORD`                | Senha ou Key do email                       | Painel do provedor de email                                                                                        |

### 2. Frontend (`frontend/.env`)

Configure as URLs de conexão com o backend e integrações públicas.

| Variável                  | Descrição                           | Onde conseguir                                                                |
| :------------------------ | :---------------------------------- | :---------------------------------------------------------------------------- |
| `VITE_API_URL`            | URL base da API Rails               | Dev: `http://localhost:3000` <br> Prod: `https://api.meu-dominio.com`         |
| `VITE_WS_URL`             | URL do WebSocket (ActionCable)      | Dev: `ws://localhost:3000/cable` <br> Prod: `wss://api.meu-dominio.com/cable` |
| `VITE_GOOGLE_API_KEY`     | Chave pública do Google (Maps/Auth) | Google Cloud Console > Credentials                                            |
| `VITE_DISCORD_SERVER_URL` | Link de convite do Discord          | Seu servidor Discord > Convidar Pessoas                                       |

### 3. Raiz/Scripts (`.env`)

Usado principalmente por scripts de automação (`bin/prod`, Docker).

| Variável       | Descrição                                        | Importância                                |
| :------------- | :----------------------------------------------- | :----------------------------------------- |
| `CORS_ORIGINS` | Mesmo valor do backend, lido pelo script de prod | **Crítico** p/ evitar bloqueio em produção |
| `RAILS_PORT`   | Porta do container Backend                       | Padrão: `3000`                             |
```
| `VITE_PORT`    | Porta do container Frontend                      | Padrão: `5173`                             |

> **Nota**: Para criar os arquivos baseados nos exemplos:
>
> ```bash
> cp backend/.env.example backend/.env
> cp frontend/.env.example frontend/.env
> cp .env.example .env
> ```

### 🔄 Alternando Ambientes (bin/switch_env)

Para facilitar o desenvolvimento e testes (especialmente com webhooks), criamos um utilitário para alternar as configurações de `.env` automaticamente.

```bash
# Alternar para ambiente LOCAL (localhost:3000 / localhost:5173)
bin/switch_env local

# Alternar para ambiente NGROK (para testes de webhooks externos)
# Configura automaticamente WSS e HTTPS
bin/switch_env ngrok https://sua-url.ngrok-free.app

# Alternar para ambiente PRODUÇÃO (goat.polemk.com)
bin/switch_env prod
```

## 📖 Uso

1. Acesse `http://localhost:5173`
2. Faça login com as credenciais demo
3. Explore as funcionalidades de pagamentos e WhatsApp

## 🤝 Contribuindo

1. Faça fork do projeto
2. Crie sua feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📝 Licença

Este projeto está sob a licença MIT.

## 📞 Suporte

Para suporte, abra uma issue no repositório.
