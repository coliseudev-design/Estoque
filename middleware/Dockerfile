FROM node:20-alpine

WORKDIR /app

# Dependências nativas para better-sqlite3 e módulos nativos + wget para healthcheck
RUN apk add --no-cache python3 make g++ wget

# PM2 global — usa pm2-runtime como entrypoint (projetado para Docker)
# pm2-runtime age como PID 1 correto: propaga sinais e auto-reinicia o app
RUN npm install -g pm2

# Copia package files primeiro (cache de layer)
COPY package*.json ./
RUN npm ci --omit=dev

# Copia código fonte (inclui ecosystem.config.js)
COPY . .

# Cria pasta de logs e usuário não-root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup \
    && mkdir -p logs \
    && chown -R appuser:appgroup /app

USER appuser

EXPOSE 3000

# pm2-runtime é o substituto do "node" para containers:
# - Reinicia o processo automaticamente se cair
# - Propaga SIGTERM corretamente para graceful shutdown
# - Respeita max_memory_restart do ecosystem.config.js
# pm2-runtime puxará as vars puras do ambiente (sem cachear velhas configurações)
CMD ["pm2-runtime", "start", "src/index.js", "--name", "coliseu-middleware"]
