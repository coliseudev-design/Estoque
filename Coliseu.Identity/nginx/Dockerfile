# nginx/Dockerfile — Multi-stage: build React/Vite + serve com Nginx
#
# Stage 1: build o frontend dentro do Docker (sem dependência de dist/ commitado)
# Stage 2: nginx serve os arquivos estáticos gerados

# ── Stage 1: Node build ────────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

# Copia manifests e instala deps (cache layer separado)
# NODE_ENV forçado para development para garantir que devDependencies (vite, typescript, etc)
# sejam instaladas — Coolify injeta NODE_ENV=production via build args que quebraria o build
COPY admin-frontend/package*.json ./
RUN NODE_ENV=development npm install

# Copia código fonte
COPY admin-frontend/ ./

# Build args (variáveis VITE_ injetadas pelo Coolify como Build Variables)
ARG VITE_SALES_API_URL=https://licencas.coliseusistemas.com.br
ARG VITE_SALES_API_KEY
ARG VITE_IDENTITY_API_URL=https://adminlicencas.coliseusistemas.com.br

ENV VITE_SALES_API_URL=$VITE_SALES_API_URL
ENV VITE_SALES_API_KEY=$VITE_SALES_API_KEY
ENV VITE_IDENTITY_API_URL=$VITE_IDENTITY_API_URL

# Increase Node heap memory size to prevent Vite OOM kills on VPS during build
ENV NODE_OPTIONS="--max-old-space-size=2048"

RUN npm run build

# ── Stage 2: Nginx ─────────────────────────────────────────────────────────
FROM nginx:1.27-alpine

# gettext provides envsubst (replaces $ADMIN_API_KEY in nginx.conf at startup)
RUN apk add --no-cache gettext

COPY --from=builder /app/dist /usr/share/nginx/html

# Copy as template — envsubst substitutes $ADMIN_API_KEY at container startup
COPY nginx/nginx.conf /etc/nginx/nginx.conf.template

EXPOSE 80

# At startup: substitute ONLY $ADMIN_API_KEY (leave nginx vars like $host intact),
# write the resolved conf, then start nginx in foreground.
CMD ["/bin/sh", "-c", \
    "envsubst '$ADMIN_API_KEY' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && \
     nginx -g 'daemon off;'"]
