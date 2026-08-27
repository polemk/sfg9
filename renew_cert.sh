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
# Sem argumento ele roda `certbot renew`, que renova todo certificado perto de
# vencer e não faz nada com os demais — é o modo do agendamento. Com domínios,
# ele EMITE (`certonly`), que é o caminho da primeira vez e o do conserto.
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

# ------------------------------------------------------- 2. emitir / renovar
WEBROOT="${WEBROOT:-/var/www/html}"

if [ "$#" -eq 0 ]; then
  echo ""
  echo "  Renovando o que estiver perto de vencer…"
  # `--deploy-hook` só dispara quando ALGO foi de fato renovado — é o que evita
  # recarregar o Nginx à toa nas execuções diárias do agendamento.
  if certbot renew --deploy-hook "systemctl reload nginx"; then
    ok "certbot renew concluído"
  else
    morre "certbot renew falhou. Detalhe em /var/log/letsencrypt/letsencrypt.log"
  fi
else
  [ -d "${WEBROOT}" ] || morre "Webroot inexistente: ${WEBROOT}  (defina com WEBROOT=/caminho)"

  ARGS=()
  for dominio in "$@"; do ARGS+=(-d "${dominio}"); done

  echo ""
  echo "  Emitindo para: $*"
  echo "  Webroot: ${WEBROOT}"
  echo ""
  if certbot certonly --webroot -w "${WEBROOT}" "${ARGS[@]}"; then
    ok "certificado emitido"
  else
    echo ""
    echo "  Causas comuns, na ordem em que costumam ser:"
    echo "    • o DNS do domínio ainda não aponta para este servidor"
    echo "    • a porta 80 não está aberta (o desafio HTTP-01 passa por ela)"
    echo "    • o Nginx não serve ${WEBROOT} em /.well-known/acme-challenge/"
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
  if nginx -t; then
    if systemctl reload nginx; then
      ok "nginx recarregado"
    else
      morre "O teste passou mas o reload falhou. Veja:  systemctl status nginx"
    fi
  else
    morre "A configuração do Nginx NÃO passou. O reload NÃO foi feito, de propósito — recarregar com configuração inválida derruba os outros aplicativos deste servidor."
  fi
fi

# ------------------------------------------------------------- 4. o resultado
echo ""
certbot certificates 2>/dev/null | grep -E "Certificate Name|Domains|Expiry Date" || true

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
