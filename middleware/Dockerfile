# ============================================
# ColiseSpeed Middleware — Multi-stage Build
# ============================================

# ── Stage 1: Dependencies ──
FROM node:20-alpine AS dependencies
WORKDIR /app

# Dependências nativas para better-sqlite3 e módulos nativos
RUN apk add --no-cache python3 make g++

# Instala apenas deps de produção (cache de layer)
COPY package*.json ./
RUN npm ci --omit=dev

# ── Stage 2: Production ──
FROM node:20-alpine AS production
WORKDIR /app

# wget para healthcheck
RUN apk add --no-cache wget

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

# Node direto — Docker restart policy cuida do restart automático
CMD ["node", "src/index.js"]
