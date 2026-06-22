#!/bin/bash
# flush-tenant-cache.sh
# Remove as chaves Redis antigas (sem branchId) de um tenant para forçar re-sync correto.
#
# USO: ./flush-tenant-cache.sh <COMPANY_UUID>
# Exemplo: ./flush-tenant-cache.sh "3f8e9a12-0c1d-4b2e-8f3a-1234567890ab"
#
# Após rodar, force o Worker a sincronizar novamente para popular as chaves com branchId.

set -e

COMPANY_ID="${1:-}"
if [ -z "$COMPANY_ID" ]; then
  echo "❌ Uso: $0 <COMPANY_UUID>"
  exit 1
fi

echo "🔍 Buscando chaves Redis antigas de company:${COMPANY_ID}..."

# Chaves antigas (sem branchId) — formato: company:{id}:{entity}
OLD_KEYS=$(redis-cli KEYS "company:${COMPANY_ID}:*" | grep -v ":branch:")

if [ -z "$OLD_KEYS" ]; then
  echo "✅ Nenhuma chave antiga encontrada para ${COMPANY_ID}."
else
  echo "🗑  Removendo chaves antigas sem branchId:"
  echo "$OLD_KEYS"
  echo "$OLD_KEYS" | xargs redis-cli DEL
  echo "✅ Chaves antigas removidas. O Worker irá re-sincronizar com branchId na próxima execução."
fi

echo ""
echo "📋 Chaves atuais com branchId (corretas):"
redis-cli KEYS "company:${COMPANY_ID}:branch:*"
