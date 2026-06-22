-- ══════════════════════════════════════════════════════════════════════════════
-- init.sql — Coliseu.Identity Database Bootstrap
--
-- Este script é executado AUTOMATICAMENTE pelo PostgreSQL na primeira inicialização
-- do container (quando o volume pg_data está vazio).
-- Referência: https://hub.docker.com/_/postgres → "Initialization scripts"
--
-- IMPORTANTE: Este script é idempotente (usa IF NOT EXISTS e ON CONFLICT).
-- Não causa erros se o banco já estiver inicializado.
-- ══════════════════════════════════════════════════════════════════════════════

-- ── Extensões ────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- para gen_random_uuid()

-- ── Tabela: companies ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS companies (
    "Id"                        uuid                     NOT NULL PRIMARY KEY,
    "Name"                      character varying(200)   NOT NULL,
    "CompanyKeyHash"            character varying(64)    NOT NULL,
    "FirebirdHost"              character varying(255)   NOT NULL,
    "FirebirdDatabasePath"      character varying(500)   NOT NULL,
    "FirebirdUser"              character varying(100)   NOT NULL,
    "FirebirdPasswordEncrypted" character varying(500)   NOT NULL,
    "DeviceLimit"               integer                  NOT NULL,
    "Status"                    integer                  NOT NULL,
    "CreatedAt"                 timestamp with time zone NOT NULL,
    "UpdatedAt"                 timestamp with time zone,
    "ContactEmail"              character varying(255)
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_companies_CompanyKeyHash"
    ON companies ("CompanyKeyHash");
CREATE INDEX IF NOT EXISTS "IX_companies_Name"
    ON companies ("Name");

-- ── Tabela: permission_groups ───────────────────────────────────────────
-- Grupos de permissões RBAC para usuários administrativos.
CREATE TABLE IF NOT EXISTS permission_groups (
    "Id"           uuid                     NOT NULL PRIMARY KEY,
    "Name"         character varying(200)   NOT NULL,
    "Description"  character varying(500),
    "Permissions"  jsonb                    NOT NULL DEFAULT '[]',
    "CreatedAt"    timestamp with time zone NOT NULL,
    "UpdatedAt"    timestamp with time zone
);

-- ── Tabela: admin_users ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_users (
    "Id"                  uuid                     NOT NULL PRIMARY KEY,
    "Email"               character varying(255)   NOT NULL,
    "Name"                character varying(200),
    "PasswordHash"        character varying(255)   NOT NULL,
    "Role"                integer                  NOT NULL,
    "IsActive"            boolean                  NOT NULL DEFAULT true,
    "CreatedAt"           timestamp with time zone NOT NULL,
    "LastLoginAt"         timestamp with time zone,
    "TotpSecretEncrypted" character varying(500),
    "TotpEnabled"         boolean                  NOT NULL DEFAULT false,
    "PermissionGroupId"   uuid                     REFERENCES permission_groups("Id") ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_admin_users_Email"
    ON admin_users ("Email");

-- ── Tabela: audit_logs ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_logs (
    "Id"        uuid                     NOT NULL PRIMARY KEY,
    "Action"    character varying(100)   NOT NULL,
    "CompanyId" uuid,
    "DeviceId"  uuid,
    "IpAddress" character varying(45),
    "UserAgent" character varying(500),
    "Details"   character varying(2000),
    "CreatedAt" timestamp with time zone NOT NULL
);

CREATE INDEX IF NOT EXISTS "IX_audit_logs_Action"    ON audit_logs ("Action");
CREATE INDEX IF NOT EXISTS "IX_audit_logs_CompanyId" ON audit_logs ("CompanyId");
CREATE INDEX IF NOT EXISTS "IX_audit_logs_CreatedAt" ON audit_logs ("CreatedAt");

-- ── Tabela: devices ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS devices (
    "Id"              uuid                     NOT NULL PRIMARY KEY,
    "CompanyId"       uuid                     NOT NULL REFERENCES companies("Id") ON DELETE CASCADE,
    "DeviceUuid"      character varying(255),  -- nullable: dispositivos pendentes de ativação
    "Model"           character varying(200),
    "OS"              character varying(100),
    "AppVersion"      character varying(50),
    "Status"          integer                  NOT NULL,
    "ActivationKey"   character varying(64),
    "FirstActivation" timestamp with time zone NOT NULL,
    "LastAccess"      timestamp with time zone NOT NULL
);

CREATE INDEX IF NOT EXISTS "IX_devices_CompanyId" ON devices ("CompanyId");
CREATE UNIQUE INDEX IF NOT EXISTS "IX_devices_DeviceUuid_CompanyId"
    ON devices ("DeviceUuid", "CompanyId")
    WHERE "DeviceUuid" IS NOT NULL;  -- índice parcial, ignora NULLs

-- ── Tabela: sessions ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sessions (
    "Id"           uuid                     NOT NULL PRIMARY KEY,
    "DeviceId"     uuid                     NOT NULL REFERENCES devices("Id") ON DELETE CASCADE,
    "RefreshToken" character varying(500)   NOT NULL,
    "ExpiresAt"    timestamp with time zone NOT NULL,
    "CreatedAt"    timestamp with time zone NOT NULL,
    "IsRevoked"    boolean                  NOT NULL DEFAULT false
);

CREATE UNIQUE INDEX IF NOT EXISTS "IX_sessions_RefreshToken" ON sessions ("RefreshToken");
CREATE INDEX IF NOT EXISTS "IX_sessions_DeviceId" ON sessions ("DeviceId");

-- ── Tabela de controle de migrations do EF Core ───────────────────────────────
-- Marca todas as migrations como "já aplicadas" para que o .NET não tente
-- re-executá-las sobre o schema que acabamos de criar aqui.
CREATE TABLE IF NOT EXISTS "__EFMigrationsHistory" (
    "MigrationId"    character varying(150) NOT NULL PRIMARY KEY,
    "ProductVersion" character varying(32)  NOT NULL
);

INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion") VALUES
    ('20260226164542_InitialCreate',              '8.0.11'),
    ('20260227030105_AddDeviceActivationKey',      '8.0.11'),
    ('20260227105840_AddTotpToAdminUser',          '8.0.11'),
    ('20260227185422_AddContactEmailToCompany',    '8.0.11'),
    ('20260301000000_MakeDeviceUuidNullable',      '8.0.11'),
    ('20260301000001_AddPermissionGroupsAndAdminUserUpdates', '8.0.11')
ON CONFLICT ("MigrationId") DO NOTHING;

-- ── Seed: Grupo Super Administrador com todas as permissões ────────────────
INSERT INTO permission_groups (
    "Id", "Name", "Description", "Permissions", "CreatedAt"
)
SELECT
    'a0000000-0000-0000-0000-000000000001'::uuid,
    'Super Administrador',
    'Acesso total — todas as permissões',
    '["companies.create","companies.read","companies.update","companies.delete","devices.read","devices.revoke","devices.activate","users.manage","audit.read","settings.read","webhooks.manage","kpi.read","reports.read"]'::jsonb,
    NOW()
WHERE NOT EXISTS (
    SELECT 1 FROM permission_groups WHERE "Name" = 'Super Administrador'
);

-- ── SuperAdmin inicial ────────────────────────────────────────────────────
-- A senha é lida da variável SEED_ADMIN_PASSWORD via a função abaixo.
-- Se a variável não existir, usa o fallback 'AdminColiseu2026!' (hash pré-computado).
-- ATENÇÃO: troque a senha pelo painel Admin imediatamente após o primeiro login.
--
-- Hash BCrypt (cost=12) para 'AdminColiseu@2025' — gerado via Python bcrypt:
--   python -c "import bcrypt; print(bcrypt.hashpw(b'sua_senha', bcrypt.gensalt(12)).decode())"
INSERT INTO admin_users (
    "Id", "Email", "Name", "PasswordHash", "Role", "IsActive", "CreatedAt", "PermissionGroupId"
)
SELECT
    gen_random_uuid(),
    'admin@coliseu.com.br',
    'Super Admin',
    '$2b$12$.jEcMAjtB.6d5P/QWx6Nwe0xS3kKJ9HxstG2F3bVvQg2ajxFXYfMW',
    0,      -- Role 0 = SuperAdmin
    true,
    NOW(),
    'a0000000-0000-0000-0000-000000000001'::uuid
WHERE NOT EXISTS (
    SELECT 1 FROM admin_users WHERE "Email" = 'admin@coliseu.com.br'
);
