#!/bin/bash
# backup.sh

echo "[$(date)] Iniciando rotina de backup do banco de dados..."

BACKUP_NAME="${PG_DATABASE}_backup_$(date +%Y-%m-%d_%H-%M-%S).sql.gz"
BACKUP_FILE="/backups/$BACKUP_NAME"

# 1. Fazendo o dump (usa as env vars do docker-compose)
PGPASSWORD="$PG_PASSWORD" pg_dump -h "$PG_HOST" -U "$PG_USER" -d "$PG_DATABASE" | gzip > "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    echo "[$(date)] Backup local criado com sucesso: $BACKUP_FILE"
else
    echo "[$(date)] ERRO ao criar backup local. Abortando."
    exit 1
fi

# 2. Limpeza Local (Mantém 7 dias)
echo "[$(date)] Limpando backups locais mais antigos que 7 dias..."
find /backups -name "${PG_DATABASE}_backup_*.sql.gz" -type f -mtime +7 -delete

# 3. Verificando configuração do Rclone
if [ ! -f "/root/.config/rclone/rclone.conf" ]; then
    echo "[$(date)] AVISO: rclone.conf não encontrado. Backup local gerado, mas upload ignorado."
    exit 0
fi

# 4. Upload para o Google Drive
echo "[$(date)] Sincronizando com o Google Drive..."
rclone copy "/backups" "gdrive:/" -v

if [ $? -eq 0 ]; then
    echo "[$(date)] Upload concluído com sucesso."
else
    echo "[$(date)] ERRO ao fazer upload para o Google Drive."
    exit 1
fi

# 5. Limpeza no Google Drive (Mantém 30 dias)
echo "[$(date)] Limpando backups mais antigos que 30 dias no Google Drive..."
rclone delete "gdrive:/" --min-age 30d -v

echo "[$(date)] Rotina de backup finalizada com sucesso."
