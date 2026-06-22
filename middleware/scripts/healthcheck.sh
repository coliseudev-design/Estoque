#!/bin/bash
# healthcheck.sh — Verifica se o middleware Coliseu responde.
# Executar via cron a cada 5 minutos:
#   */5 * * * * /opt/coliseu/middleware/scripts/healthcheck.sh >> /var/log/coliseu-health.log 2>&1
#
# Se o /health não responder em 5s, reinicia via PM2 e envia log de erro.

set -euo pipefail

HEALTH_URL="http://localhost:3000/health"
TIMEOUT=5
LOG_FILE="/var/log/coliseu-health.log"
RESTART_FLAG="/tmp/coliseu_restart_$(date +%Y%m%d).flag"
MAX_RESTARTS_PER_DAY=5

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# Conta quantos restarts foram feitos hoje
restart_count() {
    [ -f "$RESTART_FLAG" ] && cat "$RESTART_FLAG" || echo 0
}

increment_restart() {
    echo $(( $(restart_count) + 1 )) > "$RESTART_FLAG"
}

echo "$(timestamp) [HealthCheck] Verificando $HEALTH_URL ..."

# Tenta o health check
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" --max-time "$TIMEOUT" "$HEALTH_URL" || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
    echo "$(timestamp) [HealthCheck] OK — serviço respondendo (HTTP $HTTP_STATUS)"
    exit 0
fi

# Falhou — registra e tenta reiniciar
echo "$(timestamp) [HealthCheck] FALHA — HTTP $HTTP_STATUS. Iniciando restart..."

COUNT=$(restart_count)

if [ "$COUNT" -ge "$MAX_RESTARTS_PER_DAY" ]; then
    echo "$(timestamp) [HealthCheck] ALERTA: $COUNT restarts hoje. Limite atingido — verificação manual necessária!"
    # Aqui você pode integrar Telegram / Slack / e-mail:
    # curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    #      -d "chat_id=${TELEGRAM_CHAT_ID}" \
    #      -d "text=⚠️ Coliseu Middleware: $COUNT crashes hoje! Verificação manual necessária."
    exit 1
fi

# Reinicia via PM2
pm2 restart coliseu-middleware --update-env 2>&1 | while IFS= read -r line; do
    echo "$(timestamp) [PM2] $line"
done

increment_restart
echo "$(timestamp) [HealthCheck] Restart #$( restart_count) executado."
