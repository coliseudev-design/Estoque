#!/usr/bin/env bash
# scripts/pg_backup.sh — Backup automático do PostgreSQL (Coliseu Speed)
#
# Requisitos:
#   - pg_dump instalado (pacote postgresql-client)
#   - Variáveis de ambiente: PG_HOST, PG_PORT, PG_DATABASE, PG_USER, PGPASSWORD
#
# Uso manual:
#   chmod +x scripts/pg_backup.sh
#   PGPASSWORD=<senha> bash scripts/pg_backup.sh
#
# Agendamento via cron (todo dia às 02h00):
#   0 2 * * * PGPASSWORD=<senha> /opt/coliseu/scripts/pg_backup.sh >> /var/log/coliseu_backup.log 2>&1
#
# No Windows (Task Scheduler), use WSL ou o pg_dump.exe do PostgreSQL:
#   schtasks /create /tn "ColiseuBackup" /tr "wsl bash /mnt/c/coliseu/scripts/pg_backup.sh" /sc daily /st 02:00

set -euo pipefail

# ── Configuração ──────────────────────────────────────────────────────────────
PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_DATABASE="${PG_DATABASE:-coliseu_speed}"
PG_USER="${PG_USER:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-/backups/coliseu}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# ── Preparação ────────────────────────────────────────────────────────────────
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/coliseu_${TIMESTAMP}.sql.gz"

mkdir -p "${BACKUP_DIR}"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Iniciando backup: ${BACKUP_FILE}"

# ── pg_dump com compressão gzip ───────────────────────────────────────────────
pg_dump \
  --host="${PG_HOST}" \
  --port="${PG_PORT}" \
  --username="${PG_USER}" \
  --dbname="${PG_DATABASE}" \
  --no-password \
  --format=plain \
  --no-owner \
  --no-privileges \
  | gzip -9 > "${BACKUP_FILE}"

BACKUP_SIZE=$(du -sh "${BACKUP_FILE}" | cut -f1)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup concluído: ${BACKUP_FILE} (${BACKUP_SIZE})"

# ── Limpeza: remove backups mais antigos que RETENTION_DAYS dias ──────────────
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Removendo backups com mais de ${RETENTION_DAYS} dias..."
find "${BACKUP_DIR}" \
  -name "coliseu_*.sql.gz" \
  -type f \
  -mtime +${RETENTION_DAYS} \
  -delete \
  -print | while read -r removed; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Removido: ${removed}"
  done

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup finalizado com sucesso."

# ── Lista backups existentes ──────────────────────────────────────────────────
echo ""
echo "Backups disponíveis:"
ls -lh "${BACKUP_DIR}"/coliseu_*.sql.gz 2>/dev/null || echo "  (nenhum)"
