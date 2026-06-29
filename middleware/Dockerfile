# ============================================
# ColiseSpeed Middleware — Multi-stage Build
# ============================================

# ── Stage 1: Dependencies ──
FROM node:20-alpine AS dependencies
WORKDIR /app

# Dependências nativas para better-sqlite3 e módulos nativos
RUN apk add --no-cache python3 make g++ wget

# PM2 global — pm2-runtime como PID 1 (propaga sinais + auto-restart)
RUN npm install -g pm2

# Instala apenas deps de produção (cache de layer)
COPY package*.json ./
RUN npm ci --omit=dev

# ── Stage 2: Production ──
FROM node:20-alpine AS production
WORKDIR /app

# wget para healthcheck
RUN apk add --no-cache wget

# Copia PM2 do stage anterior
COPY --from=dependencies /usr/local/lib/node_modules/pm2 /usr/local/lib/node_modules/pm2
COPY --from=dependencies /usr/local/bin/pm2 /usr/local/bin/pm2
COPY --from=dependencies /usr/local/bin/pm2-runtime /usr/local/bin/pm2-runtime
COPY --from=dependencies /usr/local/bin/pm2-dev /usr/local/bin/pm2-dev

# Copia node_modules de produção
COPY --from=dependencies /app/node_modules ./node_modules

# Copia código fonte
COPY . .

# Remove arquivos desnecessários da imagem final
RUN rm -rf tests/ .env.example .env *.test.js .dockerignore

# Cria pasta de logs e usuário não-root
RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup && \
    mkdir -p logs && \
    chown -R appuser:appgroup /app

ENV NODE_ENV=production
USER appuser
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

CMD ["pm2-runtime", "start", "src/index.js", "--name", "colisespeed-middleware"]
