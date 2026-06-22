FROM alpine:3.19

# Instalar postgresql-client (para dump), rclone (para cloud) e tzdata (para fuso horário local)
RUN apk add --no-cache postgresql16-client rclone tzdata bash

# Configurar timezone para o Brasil
ENV TZ=America/Sao_Paulo
RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /scripts

# Adiciona os scripts
COPY backup.sh /scripts/backup.sh
RUN chmod +x /scripts/backup.sh

COPY entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /scripts/entrypoint.sh

# Diretório onde os dumps locais ficarão
RUN mkdir -p /backups

ENTRYPOINT ["/scripts/entrypoint.sh"]
