#!/bin/bash
set -e

# =============================================================================
#  install_dev.sh — põe o Safegold de pé na MÁQUINA DE QUEM DESENVOLVE
# =============================================================================
#
# O `install.sh` é de servidor: pergunta domínio, SSL, systemd, nginx e a senha de
# superusuário do Postgres. Nada disso existe num notebook, e responder aquilo com
# valores fingidos produz um ambiente que parece pronto e não é.
#
# Este aqui faz só o que separa um `git clone` de um `bin/dev` que sobe:
#
#   1. confere o que precisa estar instalado — TUDO de uma vez, não um por vez;
#   2. cria o papel e os bancos `_dev` e `_test` no Postgres;
#   3. escreve `backend/config/database.yml`, que é git-ignored (é por isso que
#      clonar o repositório não basta);
#   4. escreve os dois `.env` a partir dos `.env.example` versionados;
#   5. instala as dependências, migra e semeia.
#
# Depois disso quem roda a aplicação é o `bin/dev`, que sobe backend, Sidekiq e
# frontend juntos. Este script não sobe nada — instalar e executar são coisas
# diferentes, e misturá-las é o que faz um instalador virar um monstro.
#
# **É seguro rodar de novo.** Nada é sobrescrito sem perguntar, e os segredos já
# gravados são preservados.

RAIZ="$(cd "$(dirname "$0")" && pwd)"
cd "${RAIZ}"

VERDE=$'\033[1;32m'; VERMELHO=$'\033[1;31m'; AMARELO=$'\033[1;33m'; CIANO=$'\033[1;36m'; FIM=$'\033[0m'

titulo() { printf "\n%s== %s ==%s\n" "${CIANO}" "$1" "${FIM}"; }
ok()     { printf "  %s✓%s %s\n" "${VERDE}" "${FIM}" "$1"; }
aviso()  { printf "  %s!%s %s\n" "${AMARELO}" "${FIM}" "$1"; }
morre()  { printf "\n%s✗ %s%s\n\n" "${VERMELHO}" "$1" "${FIM}"; exit 1; }

echo "=========================================================="
echo "   🧑‍💻 Safegold — ambiente de DESENVOLVIMENTO local"
echo "=========================================================="

# -----------------------------------------------------------------------------
# 1. PRÉ-REQUISITOS
# -----------------------------------------------------------------------------
#
# **Todos de uma vez, e não um por vez.** Descobrir dependência que falta a cada
# nova execução é o pior jeito de instalar qualquer coisa: a pessoa conserta um
# item, espera dois minutos de `bundle install`, e descobre o próximo. A lista
# inteira sai numa tela só, com o comando de cada um.
titulo "1/6 · Conferindo o que precisa estar instalado"

RUBY_ESPERADO="$(tr -d '[:space:]' < backend/.ruby-version)"
FALTANDO=()

command -v ruby  >/dev/null 2>&1 || FALTANDO+=("ruby ${RUBY_ESPERADO}  →  rvm install ${RUBY_ESPERADO}   (ou rbenv/asdf)")
command -v node  >/dev/null 2>&1 || FALTANDO+=("node             →  https://nodejs.org  (ou nvm install --lts)")
command -v npm   >/dev/null 2>&1 || FALTANDO+=("npm              →  vem junto com o node")
command -v psql  >/dev/null 2>&1 || FALTANDO+=("postgresql       →  apt install postgresql   |   brew install postgresql@15")
command -v redis-cli >/dev/null 2>&1 || FALTANDO+=("redis            →  apt install redis-server |   brew install redis")

if [ ${#FALTANDO[@]} -gt 0 ]; then
  printf "\n%sFaltam %d coisa(s):%s\n\n" "${VERMELHO}" "${#FALTANDO[@]}" "${FIM}"
  for item in "${FALTANDO[@]}"; do echo "   • ${item}"; done
  echo ""
  morre "Instale o que está acima e rode este script de novo."
fi

# A versão do Ruby é conferida contra o que o app pede, não contra um número
# escrito aqui. O `Gemfile` reprova sozinho mais adiante, mas com uma mensagem
# que não diz como resolver — esta diz.
RUBY_ATUAL="$(ruby -e 'print RUBY_VERSION')"
if [ "${RUBY_ATUAL}" != "${RUBY_ESPERADO}" ]; then
  printf "\n  Ruby ativo: %s  ·  o app pede: %s\n" "${RUBY_ATUAL}" "${RUBY_ESPERADO}"
  aviso "Ative a versão certa antes de continuar. Com RVM:  rvm use ${RUBY_ESPERADO}"
  aviso "Se ela não estiver instalada:  rvm install ${RUBY_ESPERADO}"
  morre "Ruby na versão errada."
fi
ok "ruby ${RUBY_ATUAL}"
ok "node $(node -v)"
ok "postgres e redis encontrados"

# Postgres no ar — sem isto o erro só aparece no `db:create`, dez passos adiante.
pg_isready -q 2>/dev/null || morre "O Postgres não está respondendo. Suba o serviço e tente de novo."
ok "postgres respondendo"

redis-cli ping >/dev/null 2>&1 || aviso "Redis não respondeu ao ping. O Sidekiq vai precisar dele — suba antes do bin/dev."

# -----------------------------------------------------------------------------
# 2. PERGUNTAS — poucas, e todas com padrão
# -----------------------------------------------------------------------------
titulo "2/6 · Configuração"
echo "  Tudo tem padrão entre colchetes. Enter aceita."
echo ""

read -p "  Prefixo dos bancos [sfg9]: " PREFIXO;      PREFIXO="${PREFIXO:-sfg9}"
read -p "  Usuário do Postgres [${PREFIXO}_user]: " DB_USER; DB_USER="${DB_USER:-${PREFIXO}_user}"
read -sp "  Senha para esse usuário [dev]: " DB_PASS;  echo "";  DB_PASS="${DB_PASS:-dev}"
read -p "  Porta do backend [3026]: " PORTA_API;      PORTA_API="${PORTA_API:-3026}"
read -p "  Porta do frontend [5186]: " PORTA_WEB;     PORTA_WEB="${PORTA_WEB:-5186}"

DB_DEV="${PREFIXO}_dev"
DB_TEST="${PREFIXO}_test"

# -----------------------------------------------------------------------------
# 3. BANCO
# -----------------------------------------------------------------------------
#
# Criar papel e banco exige uma conexão administrativa, e ela não é igual em toda
# máquina: no Linux costuma ser `sudo -u postgres`, e num macOS com Homebrew o
# usuário do sistema já é superusuário e não existe conta `postgres` no SO. O
# script tenta os dois, nessa ordem, em vez de assumir um.
titulo "3/6 · Banco de dados"

# A conexão é resolvida UMA vez e guardada em `PSQL_ADMIN`.
#
# Duas razões, e a segunda foi um defeito real na primeira versão deste arquivo:
# sondar a cada chamada faria o `sudo` pedir senha SETE vezes (papel, dois
# bancos, duas extensões, duas verificações), o que ninguém aguenta.
#
# A ordem tenta primeiro o que não incomoda: conexão como o próprio usuário
# (macOS com Homebrew já nasce assim), depois a conta `postgres` por senha, e só
# então o `sudo` — anunciado antes, para o pedido de senha não ser surpresa.
#
# ⚠ Sem `-n` no `sudo`, **de propósito**. A primeira versão usava `sudo -n true`
# como teste e, com isso, descartava o caminho mais comum no Linux: onde o sudo
# pede senha — que é a máquina da maioria — a sondagem falhava calada e o script
# morria dizendo que não havia conexão administrativa, quando havia.
# `-w` em TODAS as sondagens (`--no-password`).
#
# Sem ele o `psql` PEDE senha pelo stdin, e o `>/dev/null` esconde o prompt sem
# tirar a espera: o script fica congelado, sem imprimir nada, e quem roda nao tem
# como saber que ele quer algo. Medido aqui — `timeout 25` devolveu 124, e a
# travada estava no `psql -U postgres`, nao no `sudo`, que era onde eu supunha.
# Com `-w` a sondagem falha na hora e passa para a proxima.
resolver_psql_admin() {
  if psql -w -d postgres -c '\q' >/dev/null 2>&1; then
    PSQL_ADMIN=(psql -d postgres)
    ok "conexão administrativa: usuário atual"
    return
  fi

  if psql -w -U postgres -h localhost -c '\q' >/dev/null 2>&1; then
    PSQL_ADMIN=(psql -U postgres -h localhost)
    ok "conexão administrativa: conta postgres"
    return
  fi

  # `-t 0` — so tenta o sudo se houver terminal para responder.
  #
  # Sem esta guarda, rodar o script sem terminal (CI, `bash install_dev.sh <
  # /dev/null`, um `docker build`) trava PARA SEMPRE no pedido de senha, sem
  # imprimir nada. Medido: `timeout 25` devolveu 124.
  if command -v sudo >/dev/null 2>&1 && id postgres >/dev/null 2>&1 && [ -t 0 ]; then
    echo ""
    echo "  Preciso do Postgres como administrador para criar o papel e os bancos."
    echo "  O sudo pode pedir a SUA senha do sistema agora."
    if sudo -u postgres psql -w -c '\q' >/dev/null 2>&1; then
      PSQL_ADMIN=(sudo -u postgres psql)
      ok "conexão administrativa: sudo -u postgres"
      return
    fi
  fi

  echo ""
  echo "  Nenhum destes funcionou:"
  echo "     psql -d postgres"
  echo "     psql -U postgres -h localhost"
  echo "     sudo -u postgres psql"
  echo ""
  echo "  Num Postgres recém-instalado no Linux, o caminho costuma ser dar a si"
  echo "  mesmo um papel de superusuário, uma vez só:"
  echo ""
  echo "     sudo -u postgres createuser --superuser \"$(whoami)\""
  echo ""
  morre "Sem conexão administrativa no Postgres."
}

# `client-min-messages=warning` cala os NOTICE do Postgres.
#
# Nao e frescura: o `CREATE EXTENSION IF NOT EXISTS` emite NOTICE em stderr, e
# ele se INTERCALA com as linhas de progresso. Na segunda execucao a saida saiu
# assim, medido: `ok: banco sfg9ensaio_dev jNOTICE:  e  ok: banco ...`. Quem le
# isto e um colega instalando pela primeira vez.
psql_admin() { PGOPTIONS=--client-min-messages=warning "${PSQL_ADMIN[@]}" -v ON_ERROR_STOP=1 "$@"; }

resolver_psql_admin

# `DO $$` porque `CREATE ROLE` não tem `IF NOT EXISTS`. A senha é atualizada
# sempre, de propósito: rodar de novo com senha diferente tem de funcionar.
psql_admin -q <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}' CREATEDB;
  ELSE
    ALTER ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASS}' CREATEDB;
  END IF;
END
\$\$;
SQL
ok "papel ${DB_USER}"

for banco in "${DB_DEV}" "${DB_TEST}"; do
  if psql_admin -tAc "SELECT 1 FROM pg_database WHERE datname = '${banco}'" | grep -q 1; then
    ok "banco ${banco} já existe"
  else
    psql_admin -q -c "CREATE DATABASE ${banco} OWNER ${DB_USER};"
    ok "banco ${banco} criado"
  fi
  # `pgcrypto` é usada pelo schema (`gen_random_uuid()` nas PKs). Sem ela a
  # primeira migration falha com "function does not exist", que não diz nada
  # sobre extensão faltando.
  psql_admin -q -d "${banco}" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
done
ok "extensão pgcrypto habilitada nos dois"

# -----------------------------------------------------------------------------
# 4. database.yml — o arquivo que falta depois do clone
# -----------------------------------------------------------------------------
#
# Ele é git-ignored por decisão do tech lead (dev e produção têm configurações
# diferentes, e unificá-las num arquivo parametrizado não paga), e é exatamente
# por isso que clonar o repositório não é suficiente para rodar.
titulo "4/6 · database.yml e .env"

escrever_arquivo() {
  local destino="$1"
  if [ -f "${destino}" ]; then
    read -p "  ${destino} já existe. Sobrescrever? [s/N]: " resposta
    case "${resposta}" in
      [sS]*) return 0 ;;
      *) aviso "mantido como estava: ${destino}"; return 1 ;;
    esac
  fi
  return 0
}

if escrever_arquivo backend/config/database.yml; then
cat > backend/config/database.yml <<YML
# Gerado por install_dev.sh. NÃO versionado (ver .gitignore).
#
# A seção 'production' aponta para um banco que não existe de propósito: numa máquina de
# desenvolvimento, falhar é melhor do que escrever sem querer num banco real.
development:
  adapter: postgresql
  encoding: unicode
  pool: 10
  host: localhost
  username: ${DB_USER}
  password: '${DB_PASS}'
  database: ${DB_DEV}

test:
  adapter: postgresql
  encoding: unicode
  pool: 10
  host: localhost
  username: ${DB_USER}
  password: '${DB_PASS}'
  database: ${DB_TEST}

production:
  adapter: postgresql
  encoding: unicode
  pool: 10
  host: localhost
  username: ${DB_USER}
  password: '${DB_PASS}'
  database: ${PREFIXO}_prod_nao_existe_em_dev
YML
ok "backend/config/database.yml"
fi

# -----------------------------------------------------------------------------
# .env do backend
# -----------------------------------------------------------------------------
#
# Em desenvolvimento o boot exige QUATRO (`config/initializers/required_env.rb`):
# SECRET_KEY_BASE, DEVISE_JWT_SECRET_KEY, REDIS_URL e APP_NAME. As demais são de
# produção.
#
# **As chaves do Active Record Encryption NÃO são geradas aqui, e isso é
# deliberado.** Em desenvolvimento o initializer usa defaults conhecidos; gerar um
# jogo próprio tornaria ilegível o que já estivesse cifrado no banco local de quem
# roda o script pela segunda vez. Em produção é o contrário — lá não há default e
# o `install.sh` gera e preserva.
if [ -f backend/.env ]; then
  ANTIGO_JWT=$(grep '^DEVISE_JWT_SECRET_KEY=' backend/.env | cut -d '=' -f 2-)
  ANTIGO_SECRET=$(grep '^SECRET_KEY_BASE=' backend/.env | cut -d '=' -f 2-)
fi
JWT_SECRET="${ANTIGO_JWT:-$(openssl rand -hex 64)}"
SECRET_BASE="${ANTIGO_SECRET:-$(openssl rand -hex 64)}"

if escrever_arquivo backend/.env; then
cat > backend/.env <<ENV
# Gerado por install_dev.sh — ambiente de DESENVOLVIMENTO.
# O contrato completo, com o porquê de cada variável, está em backend/.env.example.

APP_NAME=Safegold
RAILS_ENV=development
PORT=${PORTA_API}
RAILS_LOG_TO_STDOUT=true

REDIS_URL=redis://localhost:6379/0

SECRET_KEY_BASE=${SECRET_BASE}
DEVISE_JWT_SECRET_KEY=${JWT_SECRET}
JWT_SECRET_KEY=${JWT_SECRET}
JWT_EXPIRATION_TIME=15
JWT_REFRESH_EXPIRATION_TIME=10080

CORS_ORIGINS=http://localhost:${PORTA_WEB}
APP_HOST=localhost:${PORTA_WEB}
API_HOST=localhost:${PORTA_API}

# E-mail: sem SMTP em dev. O Rails escreve a mensagem no log em vez de enviar,
# então o link do convite e o código de acesso aparecem no terminal do backend.
SMTP_DELIVERING=false
MAILER_FROM=nao-responda@localhost
ENV
ok "backend/.env"
fi

# -----------------------------------------------------------------------------
# .env do frontend
# -----------------------------------------------------------------------------
#
# ⚠ O `.env.example` do frontend aponta para `localhost:3000`, que **não** é a
# porta deste app (3026). Herança do modelo genérico. Aqui a porta vem da resposta
# dada acima, e as duas URLs precisam bater com o backend por outro motivo além do
# óbvio: elas alimentam o `connect-src` do CSP (`csp.config.ts`), e origem errada
# ali derruba a API e o Action Cable **em silêncio** — recurso bloqueado por CSP
# não gera erro visível, só some.
if escrever_arquivo frontend/.env; then
cat > frontend/.env <<ENV
# Gerado por install_dev.sh — ambiente de DESENVOLVIMENTO.
# O contrato completo está em frontend/.env.example.

VITE_API_URL=http://localhost:${PORTA_API}
VITE_WS_URL=ws://localhost:${PORTA_API}/cable
VITE_APP_NAME=Safegold
VITE_BUILD_MODE=development

# Nasce desligado (DEC-87), e ligar exige mexer também no csp.config.ts.
VITE_GA_ENABLED=false
ENV
ok "frontend/.env"
fi

# -----------------------------------------------------------------------------
# 5. DEPENDÊNCIAS E BANCO
# -----------------------------------------------------------------------------
titulo "5/6 · Dependências e migrations"

echo "  Instalando gems…"
( cd backend && bundle install --quiet )
ok "gems"

echo "  Instalando pacotes do frontend… (demora na primeira vez)"
( cd frontend && npm install --silent --legacy-peer-deps )
ok "pacotes do frontend"

echo "  Rodando migrations…"
( cd backend && RAILS_ENV=development bundle exec rails db:migrate )
ok "migrations"

# O banco de teste é preparado a partir do schema, e não migrado: é assim que a
# suíte espera encontrá-lo, e é o que o `maintain_test_schema!` confere.
echo "  Preparando o banco de teste…"
( cd backend && RAILS_ENV=test bundle exec rails db:test:prepare )
ok "banco de teste"

# -----------------------------------------------------------------------------
# 6. SEEDS
# -----------------------------------------------------------------------------
#
# Os catálogos de REFERÊNCIA entram sempre: a aplicação não abre sem eles, e a
# tarefa é idempotente. A base de DEMONSTRAÇÃO é conteúdo fictício — projetos,
# empresas, borderôs — e é opcional, mas sem ela a primeira tela é uma lista
# vazia e não dá para conferir nada.
titulo "6/6 · Base inicial"

( cd backend && RAILS_ENV=development bundle exec rake reference:seed )
ok "catálogos de referência"

read -p "  Semear a base de DEMONSTRAÇÃO (dado fictício)? [S/n]: " SEMEAR_DEMO
case "${SEMEAR_DEMO}" in
  [nN]*) aviso "pulado — rode depois com:  cd backend && bundle exec rake demo:seed" ;;
  *) ( cd backend && RAILS_ENV=development bundle exec rake demo:seed ); ok "base de demonstração" ;;
esac

# -----------------------------------------------------------------------------
printf "\n%s==========================================================%s\n" "${VERDE}" "${FIM}"
printf "%s  Pronto. Para subir tudo:%s\n\n" "${VERDE}" "${FIM}"
echo "      ./bin/dev"
echo ""
echo "  Ele sobe backend, Sidekiq e frontend juntos."
echo ""
echo "      frontend   http://localhost:${PORTA_WEB}"
echo "      backend    http://localhost:${PORTA_API}"
echo ""
echo "  ⚠ O Sidekiq não é opcional: sem ele, desativar um padrão de"
echo "    disponibilidade responde 202 e a tela fica travada esperando."
echo ""
echo "  Sem SMTP em dev, o código de acesso do login aparece no LOG do"
echo "  backend — procure no terminal, não na caixa de entrada."
echo ""
echo "  Rodar os testes:"
echo "      cd backend  && bundle exec rspec"
echo "      cd frontend && npx vitest run"
printf "%s==========================================================%s\n\n" "${VERDE}" "${FIM}"
