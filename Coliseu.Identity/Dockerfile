# ── Build stage ──────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build
WORKDIR /src

# Copiar arquivos de projeto para cache de restore
COPY src/Coliseu.Identity.Domain/Coliseu.Identity.Domain.csproj src/Coliseu.Identity.Domain/
COPY src/Coliseu.Identity.Application/Coliseu.Identity.Application.csproj src/Coliseu.Identity.Application/
COPY src/Coliseu.Identity.Infrastructure/Coliseu.Identity.Infrastructure.csproj src/Coliseu.Identity.Infrastructure/
COPY src/Coliseu.Identity.Api/Coliseu.Identity.Api.csproj src/Coliseu.Identity.Api/
RUN dotnet restore src/Coliseu.Identity.Api/Coliseu.Identity.Api.csproj

# Copiar código-fonte e publicar
COPY src/ src/
RUN dotnet publish src/Coliseu.Identity.Api/Coliseu.Identity.Api.csproj \
    -c Release -o /app/publish --no-restore

# ── Runtime stage ────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS runtime
WORKDIR /app

# Instala wget para health check (deve ser antes de trocar para user non-root)
RUN apk add --no-cache wget

# Non-root user (segurança)
RUN addgroup -S coliseu && adduser -S coliseu -G coliseu
USER coliseu

COPY --from=build /app/publish .

EXPOSE 8080
ENTRYPOINT ["dotnet", "Coliseu.Identity.Api.dll"]
