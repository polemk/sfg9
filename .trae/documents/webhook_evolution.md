✅ 1. CONNECTION_UPDATE

Disparado quando o status da conexão com o WhatsApp muda.

📩 Exemplo real de payload
{
  "event": "CONNECTION_UPDATE",
  "instanceId": "minha-instancia",
  "data": {
    "connection": "connecting",
    "lastDisconnect": null,
    "qr": null,
    "receivedPendingNotifications": false
  }
}

🧩 Outros exemplos reais em estados diferentes:
🔹 Quando o QR aparece
{
  "event": "CONNECTION_UPDATE",
  "instanceId": "minha-instancia",
  "data": {
    "connection": "qr",
    "qr": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
    "lastDisconnect": null,
    "receivedPendingNotifications": false
  }
}

🔹 Quando conecta
{
  "event": "CONNECTION_UPDATE",
  "instanceId": "minha-instancia",
  "data": {
    "connection": "open",
    "qr": null,
    "lastDisconnect": null,
    "receivedPendingNotifications": true
  }
}

🔹 Quando desconecta
{
  "event": "CONNECTION_UPDATE",
  "instanceId": "minha-instancia",
  "data": {
    "connection": "close",
    "lastDisconnect": {
      "error": "Connection Lost",
      "code": 515
    },
    "qr": null,
    "receivedPendingNotifications": false
  }
}

✅ 2. LOGOUT_INSTANCE

Disparado quando o WhatsApp faz logout (instância perdeu sessão).

📩 Exemplo real de payload
{
  "event": "LOGOUT_INSTANCE",
  "instanceId": "minha-instancia",
  "data": {
    "status": "logout",
    "reason": "session_expired",
    "timestamp": 1713022275000
  }
}

🧩 Outros motivos possíveis:

revoked_by_user

pairing_required

error_sync

unknown

Exemplo quando o usuário remove a sessão manualmente no WhatsApp:
{
  "event": "LOGOUT_INSTANCE",
  "instanceId": "minha-instancia",
  "data": {
    "status": "logout",
    "reason": "revoked_by_user",
    "timestamp": 1713022291000
  }
}

✅ 3. QRCODE_UPDATED

Disparado sempre que um novo QR Code é gerado.

📩 Exemplo real de payload
{
  "event": "QRCODE_UPDATED",
  "instanceId": "minha-instancia",
  "data": {
    "qr": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA...",
    "expiresIn": 25
  }
}

🔹 Outro exemplo — QR com ID interno da sessão
{
  "event": "QRCODE_UPDATED",
  "instanceId": "minha-instancia",
  "data": {
    "qr": "data:image/png;base64,AAABBBCCC...",
    "session": "k3JHdjs8SS92hs9sh2w",
    "expiresIn": 20
  }
}