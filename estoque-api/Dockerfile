# Build a partir da RAIZ do repositório (contexto ".") para incluir o dashboard:
#   docker build -f estoque-api/Dockerfile -t coliseu-estoque-api .
FROM node:20-alpine

ENV NODE_ENV=production \
    DASHBOARD_DIR=/app/dashboard

WORKDIR /app/api
COPY estoque-api/package*.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

COPY estoque-api/src ./src
COPY estoque-api/sql ./sql
COPY dashboard /app/dashboard

USER node
EXPOSE 3100
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD wget -qO- http://127.0.0.1:3100/health || exit 1

CMD ["node", "src/index.js"]
