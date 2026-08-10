FROM node:20-alpine

# Instala ferramentas básicas e timezone
RUN apk add --no-cache tzdata dumb-init && \
    cp /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime && \
    echo "America/Sao_Paulo" > /etc/timezone

# Diretório da aplicação
WORKDIR /usr/src/app

# Copia pacote json e instala dependências
# A flag --omit=dev garante que nodemon e jest não subam pra prod
COPY package*.json ./
RUN npm ci --omit=dev

# Copia o restante do código
COPY src ./src

# Exposição da porta default (pode ser sobrescrita pelo docker-compose)
EXPOSE 3100

# Troca para usuário não-root (segurança)
USER node

# Inicia a aplicação usando dumb-init para garantir captura correta de SIGTERM/SIGINT
CMD ["dumb-init", "node", "src/index.js"]
