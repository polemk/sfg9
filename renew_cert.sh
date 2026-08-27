#!/bin/bash
set -euo pipefail

# =============================================================================
#  renew_cert.sh — emite ou renova o certificado, e só então recarrega o Nginx
# =============================================================================
#
# Uso:
#
#     sudo ./renew_cert.sh                                  # renova o que existe
#     sudo ./renew_cert.sh sfg9.exemplo.com api-sfg9.exemplo.com   # emite para estes
#
# Sem argumento ele renova **apenas o certificado DESTE app**, cujos domínios ele
# lê de `backend/.env` (`APP_HOST` e `API_HOST`). Com domínios, ele EMITE
# (`certonly`) — o caminho da primeira vez e o do conserto.
#
# ⚠ **Nunca `certbot renew` sem escopo.** Esse comando mexe em TODOS os
# certificados do servidor, inclusive os dos outros sistemas que moram aqui.
# Renovar o certificado alheio já dispara o `deploy-hook` alheio, e um problema
# neste app vira problema de todo mundo. O escopo vem de `--cert-name`.
#
# ## Por que existe, em vez de chamar o certbot direto
#
# Três coisas que o certbot cru não faz, e que custaram um deploy em 27/08/2026:
#
#  1. **Destrava o cadeado órfão.** "Another instance of Certbot is already
#     running" quase nunca é outra instância — é o cadeado que sobrou de uma
#     execução interrompida.
#  2. **Confere o Nginx ANTES de recarregar.** Recarregar apontando para
#     certificado que não existe derruba o servidor inteiro, inclusive os outros
#     aplicativos que moram nele.
#  3. **Sai com status ≠ 0 quando falha.** O deploy daquele dia imprimiu "DEPLOY
#     CONCLUÍDO COM SUCESSO" com o Nginx fora do ar, porque a falha foi engolida
#     por um `|| true`.

VERDE=$'\033[1;32m'; VERMELHO=$'\033[1;31m'; AMARELO=$'\033[1;33m'; FIM=$'\033[0m'
ok()    { printf "  %s✓%s %s\n" "${VERDE}" "${FIM}" "$1"; }
aviso() { printf "  %s!%s %s\n" "${AMARELO}" "${FIM}" "$1"; }
morre() { printf "\n%s✗ %s%s\n\n" "${VERMELHO}" "$1" "${FIM}"; exit 1; }

[ "$(id -u)" -eq 0 ] || morre "Rode como root:  sudo ./renew_cert.sh $*"
command -v certbot >/dev/null 2>&1 || morre "certbot não está instalado.  apt install certbot"

echo "=========================================================="
echo "   🔒 Certificado TLS"
echo "=========================================================="

# ---------------------------------------------------------------- 1. cadeado
CADEADO=/var/lib/letsencrypt/.certbot.lock
if [ -f "${CADEADO}" ]; then
  if pgrep -x certbot >/dev/null 2>&1; then
    morre "Há um certbot REALMENTE rodando (pid $(pgrep -x certbot | tr '\n' ' ')). Espere ele terminar."
  fi
  aviso "cadeado órfão encontrado — removendo"
  rm -f "${CADEADO}"
fi

# ------------------------------------------- 2. em que estado o Nginx esta
#
# **Isto decide o modo do desafio, e e o que tira do impasse.**
#
# `--webroot` precisa do Nginx NO AR para servir
# `/.well-known/acme-challenge/`. Mas o caso classico de conserto e justamente o
# Nginx caido — porque a configuracao dele aponta para um certificado que nunca
# saiu. Ai fecha o circulo: Nginx caido -> certbot nao valida -> certificado nao
# sai -> configuracao segue invalida -> Nginx segue caido.
#
# `--standalone` sobe um servidor proprio na porta 80 e quebra o circulo. So
# funciona com a porta LIVRE, que e exatamente a situacao de um Nginx parado.
NGINX_ATIVO=0
if command -v nginx >/dev/null 2>&1; then
  systemctl is-active --quiet nginx && NGINX_ATIVO=1
fi

if [ "${NGINX_ATIVO}" = "1" ]; then
  ok "nginx no ar — desafio por webroot"
else
  aviso "nginx PARADO — o desafio vai por standalone (porta 80 livre)"
fi

# ------------------------------------------------------- 3. emitir / renovar
WEBROOT="${WEBROOT:-/var/www/html}"

if [ "$#" -eq 0 ]; then
  # **O domínio vem do `.env` DESTE app**, e vira `--cert-name`.
  #
  # Sem isso, `certbot renew` varre o servidor inteiro. Num servidor com vários
  # sistemas — que é o caso — isso significa mexer no certificado dos outros.
  ENV_APP="$(dirname "$0")/backend/.env"
  [ -f "${ENV_APP}" ] || morre "Não achei ${ENV_APP}. Informe os domínios:  sudo ./renew_cert.sh dominio.com api.dominio.com"

  APP_HOST="$(grep -m1 '^APP_HOST=' "${ENV_APP}" | cut -d= -f2- | tr -d '\r\n \"')"
  [ -n "${APP_HOST}" ] || morre "APP_HOST vazio em ${ENV_APP}. Informe os domínios na linha de comando."

  # O nome do certificado é o do PRIMEIRO domínio pedido na emissão. Se o
  # diretório não existir com esse nome, o certificado ou não foi emitido ou
  # ganhou sufixo (`-0001`) — em ambos os casos, adivinhar seria pior.
  if [ ! -d "/etc/letsencrypt/live/${APP_HOST}" ]; then
    echo ""
    echo "  Não há certificado com o nome '${APP_HOST}'. Os que existem:"
    certbot certificates 2>/dev/null | grep "Certificate Name:" | sed 's/^/    /'
    echo ""
    morre "Para EMITIR pela primeira vez:  sudo ./renew_cert.sh ${APP_HOST} <dominio-da-api>"
  fi

  echo ""
  echo "  Renovando SOMENTE o certificado deste app: ${APP_HOST}"
  echo "  (os certificados dos outros sistemas deste servidor não são tocados)"
  echo ""

  # `--deploy-hook` só dispara quando algo foi de fato renovado — evita
  # recarregar o Nginx à toa. Com `--cert-name`, o gancho também fica escopado.
  if certbot renew --cert-name "${APP_HOST}" --deploy-hook "systemctl reload nginx"; then
    ok "renovação concluída para ${APP_HOST}"
  else
    morre "A renovação falhou. Detalhe em /var/log/letsencrypt/letsencrypt.log"
  fi
else
  ARGS=()
  for dominio in "$@"; do ARGS+=(-d "${dominio}"); done

  if [ "${NGINX_ATIVO}" = "1" ]; then
    [ -d "${WEBROOT}" ] || morre "Webroot inexistente: ${WEBROOT}  (defina com WEBROOT=/caminho)"
    MODO=(--webroot -w "${WEBROOT}")
    DESCRICAO="webroot ${WEBROOT}"
  else
    MODO=(--standalone)
    DESCRICAO="standalone (o certbot sobe na porta 80)"
  fi

  echo ""
  echo "  Emitindo para: $*"
  echo "  Modo: ${DESCRICAO}"
  echo ""
  if certbot certonly "${MODO[@]}" "${ARGS[@]}"; then
    ok "certificado emitido"
  else
    echo ""
    echo "  Causas comuns, na ordem em que costumam ser:"
    echo "    • o DNS do domínio ainda não aponta para este servidor"
    echo "    • a porta 80 está fechada no firewall (o desafio HTTP-01 passa por ela)"
    if [ "${NGINX_ATIVO}" = "1" ]; then
      echo "    • o Nginx não serve ${WEBROOT} em /.well-known/acme-challenge/"
    else
      echo "    • algum outro processo já ocupa a porta 80 (veja: ss -lntp | grep :80)"
    fi
    morre "certbot certonly falhou."
  fi

  # O arquivo tem de EXISTIR. `certonly` pode sair com zero e mesmo assim não
  # haver o que o Nginx espera — e é o Nginx que cai, não o certbot.
  PRIMEIRO="$1"
  [ -f "/etc/letsencrypt/live/${PRIMEIRO}/fullchain.pem" ] \
    || morre "Não encontrei /etc/letsencrypt/live/${PRIMEIRO}/fullchain.pem"
  ok "fullchain.pem no lugar"
fi

# --------------------------------------------------------------- 3. o Nginx
if command -v nginx >/dev/null 2>&1; then
  echo ""
  echo "  Conferindo a configuração do Nginx…"

  SAIDA_TESTE="$(nginx -t 2>&1)" && TESTE_OK=1 || TESTE_OK=0
  [ "${TESTE_OK}" = "1" ] || echo "${SAIDA_TESTE}"

  if [ "${TESTE_OK}" = "1" ]; then
    ok "configuração válida"
  else
    # **O teste é do Nginx INTEIRO, não só do arquivo deste app.**
    #
    # Num servidor com vários sistemas, `nginx -t` reprova por defeito de
    # qualquer um deles — e por defeito do `nginx.conf` global, que não é nosso.
    # Aconteceu aqui em 27/08/2026:
    #
    #     unknown directive "passenger_root" in /etc/nginx/nginx.conf:12
    #
    # Nada a ver com este app: é o Passenger declarado sem o módulo carregado.
    # Travar o script nisso é parar por algo que já estava quebrado antes e que
    # não é nosso para consertar.
    echo ""
    if echo "${SAIDA_TESTE}" | grep -q "${APP_CONF:-/etc/nginx/sites-}"; then
      aviso "o erro parece estar num arquivo de SITE — pode ser deste app"
    else
      aviso "o erro NÃO está num arquivo de site — é do Nginx global, anterior a este script"
    fi
  fi

  # **`reload` com configuração inválida NÃO derruba o Nginx.**
  #
  # Ele valida antes de aplicar e, reprovando, mantém o processo antigo servindo.
  # O risco real é no `start` de um Nginx parado: aí a configuração inválida
  # impede de subir, e o servidor fica sem proxy nenhum.
  #
  # Por isso o gate é assimétrico: reload sempre se tenta; start só com teste
  # verde.
  if [ "${NGINX_ATIVO}" = "1" ]; then
    if systemctl reload nginx; then
      ok "nginx recarregado — o certificado novo está em uso"
    else
      aviso "o reload falhou; o Nginx SEGUE NO AR com a configuração anterior"
      aviso "o certificado foi emitido e só passa a valer quando o reload funcionar"
    fi
  elif [ "${TESTE_OK}" = "1" ]; then
    systemctl start nginx && ok "nginx SUBIU (estava parado)" \
      || morre "O teste passou mas o nginx não subiu. Veja:  systemctl status nginx"
  else
    aviso "nginx parado E configuração inválida — NÃO tentei subir"
    aviso "subir assim falharia e deixaria o servidor sem proxy. Conserte o erro acima primeiro."
  fi
fi

# ------------------------------------------------------------- 4. o resultado
echo ""
# Só o certificado deste app. `certbot certificates` sem filtro lista os dos
# outros sistemas, e essa informação não é nossa para despejar na tela.
NOME_CERT="${APP_HOST:-$1}"
certbot certificates --cert-name "${NOME_CERT}" 2>/dev/null \
  | grep -E "Certificate Name|Domains|Expiry Date" || true

printf "\n%s==========================================================%s\n" "${VERDE}" "${FIM}"
printf "%s  Pronto.%s\n" "${VERDE}" "${FIM}"
echo ""
echo "  A renovação automática já vem com o pacote do certbot"
echo "  (timer do systemd). Para conferir:"
echo ""
echo "      systemctl list-timers | grep certbot"
echo ""
echo "  Se não houver timer, agende com:"
echo ""
echo "      systemctl enable --now certbot.timer"
printf "%s==========================================================%s\n\n" "${VERDE}" "${FIM}"
