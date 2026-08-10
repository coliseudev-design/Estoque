#!/bin/bash

# Agendamento cron: Padrão às 02:00 AM todos os dias
SCHEDULE=${CRON_SCHEDULE:-"0 2 * * *"}

echo "[Init] Configurando CRON com o agendamento: $SCHEDULE"

# Configura crontab root para rodar o backup.sh e redirecionar logs
echo "$SCHEDULE /scripts/backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root

# Dispara o crond em background e joga um log tail para travar o container
echo "[Init] Iniciando crond em background..."
crond -l 2

# Toca o log para existir e então dá tail nele para o docker ver as saídas
touch /var/log/backup.log
tail -f /var/log/backup.log
