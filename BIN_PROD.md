# Guia de Deploy e Produção (`bin/prod`)

O script `bin/prod` foi criado para orquestrar a execução do projeto em modo de produção de forma simples, subindo tanto o Backend (API) quanto o Frontend (SPA) e serviços auxiliares (Sidekiq) em um único comando.

## 🚀 Como Usar o `bin/prod`

### 1. Preparação (Primeira vez)

Garanta que o banco de dados de produção existe e está migrado:

```bash
RAILS_ENV=production bin/rails db:prepare
```

### 2. Configuração de Ambiente (.env)

Para produção real, recomenda-se configurar as variáveis de ambiente nos arquivos `.env` específicos de cada aplicação (`backend/.env` e `frontend/.env`) ou exportá-las no sistema. As mais importantes são:

```bash
# URLs para CORS (Frontend acessando Backend)
CORS_ORIGINS="https://meu-dominio.com,http://localhost:5173"

# URL da API para o Frontend saber onde bater
VITE_API_URL="https://api.meu-dominio.com"

# Portas (Padrão do bin/prod, altere apenas se necessário)
RAILS_PORT=3000
VITE_PORT=5173
```

### 3. Execução

```bash
bin/prod
```

## 🛠 Entendendo o `bin/prod`

O script realiza 4 etapas principais:

1.  **Verificação**: Checa se `ruby`, `node`, `bundler` e `npx` existem.
2.  **Build do Frontend**:
    - Roda o build do Vite para gerar a pasta `dist/` (arquivos estáticos otimizados).
    - O build roda em TODO restart, igual ao facil — não existe mais gate para
      pular (um gate desses já deixou produção servindo bundle velho).
3.  **Backend (Puma)**:
    - Sobe o servidor web **Puma** na porta 3000 (produção).
4.  **Frontend (Serve)**:
    - Sobe um servidor estático simples (`serve`) na porta 5173 apontando para a pasta `dist/`.
5.  **Sidekiq**:
    - Sobe o processamento de jobs em background.

---

## 🔒 Resolvendo CORS

O erro de CORS ocorre quando o Frontend (ex: `meu-dominio.com`) tenta acessar o Backend (ex: `api.meu-dominio.com`) e o Backend não autoriza explicitamente essa origem.

No arquivo `backend/config/initializers/cors.rb`, a aplicação lê a variável `CORS_ORIGINS`.

**Solução:**
Adicione a variável `CORS_ORIGINS` no arquivo `.env` dentro da pasta `backend/` (`backend/.env`):

```bash
CORS_ORIGINS="https://meu-dominio.com"
# Ou múltiplos separados por vírgula:
CORS_ORIGINS="https://meu-dominio.com,https://outro-frontend.com"
```

_Nota: Você também pode usar `export CORS_ORIGINS="..."` no terminal antes de rodar o comando, mas usar o arquivo `.env` é o recomendado para persistência._

---

## 🌐 Configuração Nginx (Recomendada)

Para expor sua aplicação na internet com segurança (HTTPS) e usar os domínios `meu-dominio.com` e `api.meu-dominio.com`, usamos o Nginx como **Proxy Reverso**. O Nginx recebe a requisição do usuário e repassa para o `bin/prod` rodando localmente.

### Arquitetura

- **https://meu-dominio.com** → Nginx → `http://localhost:5173` (Frontend)
- **https://api.meu-dominio.com** → Nginx → `http://localhost:3000` (Backend)

### Passo a Passo

1.  **Instale o Nginx e Certbot**:

    ```bash
    sudo apt update
    sudo apt install nginx certbot python3-certbot-nginx
    ```

2.  **Crie a configuração (`/etc/nginx/sites-available/meuapp`)**:

```nginx
# --- FRONTEND (meu-dominio.com) ---
server {
    server_name meu-dominio.com;

    location / {
        # Repassa para o servidor estático do frontend (bin/prod)
        proxy_pass http://localhost:5173;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}

# --- BACKEND (api.meu-dominio.com) ---
server {
    server_name api.meu-dominio.com;

    # API, Swagger, Docs, ActionCable
    location / {
        # Repassa para o Puma do Rails (bin/prod)
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade"; # Crucial para ActionCable (WebSocket)
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

3.  **Ative o site**:

    ```bash
    sudo ln -s /etc/nginx/sites-available/meuapp /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx
    ```

4.  **Gere o SSL (HTTPS)**:
    ```bash
    sudo certbot --nginx -d meu-dominio.com -d api.meu-dominio.com
    ```

### 5. Otimização de Performance (Gzip)

Para garantir que o Nginx comprima as respostas (complementando o Gzip da aplicação), adicione dentro do bloco `http { ... }` (geralmente em `/etc/nginx/nginx.conf`):

```nginx
http {
    # ... configurações existentes ...

    ##
    # Gzip Settings
    ##

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
}
```

Isso garante a compressão máxima antes de entregar o conteúdo ao usuário.

---

## ℹ️ Nota sobre Passenger vs Puma

Este projeto e o script `bin/prod` foram desenhados para usar **Puma** (servidor web padrão do Rails moderno).

**Por que não Passenger?**

- O **Passenger** gerencia o ciclo de vida do Ruby application por conta própria, substituindo a necessidade de rodar `bin/prod` para o backend.
- Se você usar Passenger (comum em cPanel/hospedagens compartilhadas), **não use o `bin/prod`** para o backend. Você terá que configurar o Passenger no Nginx/Apache para apontar para `backend/public` e configurar o Frontend separadamente.
- **Recomendação**: Mantenha o **Puma** (usando `bin/prod`) atrás do Nginx (como configurado acima) para ter total controle sobre os serviços (Sidekiq, etc) e manter a compatibilidade com os scripts do projeto.
