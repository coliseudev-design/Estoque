-- 005_users_email.sql
-- Adiciona suporte a email para login unificado e compatibilidade com Coliseu Identity/Nexus.
ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT;
CREATE INDEX IF NOT EXISTS users_email ON users (lower(email));
