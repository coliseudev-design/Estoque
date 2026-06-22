#!/bin/bash
# setup_rclone.sh
# Facilita a configuração do Google Drive na VPS

echo "=========================================================="
echo " CONFIGURAÇÃO DO BACKUP NO GOOGLE DRIVE (Via Rclone)"
echo "=========================================================="
echo "Como a VPS não possui navegador web, faremos o processo headless."
echo ""
echo "PASSO 1:"
echo "No seu COMPUTADOR (Windows/Mac/Linux), instale o rclone e digite:"
echo "  rclone authorize \"drive\""
echo ""
echo "O navegador irá abrir, pedindo para você logar no Google."
echo "Após aceitar, o terminal do seu computador mostrará um TOKEN parecido com:"
echo "  {\"access_token\":\"ya29...\", ...}"
echo ""
echo "PASSO 2:"
echo "Copie esse código INTEIRO (incluindo as chaves {})."
echo ""
read -p "Cole o Token JSON aqui: " token

if [ -z "$token" ]; then
    echo "Cancelado. O Token não pode ser vazio."
    exit 1
fi

mkdir -p ./backup
CONF_FILE="./backup/rclone.conf"

cat > $CONF_FILE <<EOL
[gdrive]
type = drive
scope = drive
token = $token
root_folder_id = 1bnpoRNKR8UcxuEpPBKuqRjZyBbCqgP2t
EOL

echo "=========================================================="
echo "SUCESSO! Arquivo rclone.conf gerado em $CONF_FILE"
echo "O Backup será direcionado automaticamente para a pasta desejada!"
echo ""
echo "Agora você já pode iniciar o serviço:"
echo "  docker-compose -f docker-compose.prod.yml up -d db-backup"
echo "=========================================================="
