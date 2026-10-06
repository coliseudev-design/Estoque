-- Aparelhos (app de conferência) vinculados pelo painel do Estoque.
--
-- Pareamento: o supervisor gera no dashboard um código de uso único (QR Code ou
-- digitado), válido por poucos minutos. O app troca esse código por uma credencial
-- própria do aparelho (id + segredo). Daí em diante o operador entra com usuário + PIN
-- e o aparelho prova quem é pela credencial — que o supervisor pode revogar a qualquer
-- momento na tela Aparelhos.
--
-- Convive com a ativação pelo Coliseu.Identity (chave de ativação do painel de licenças):
-- os dois caminhos emitem o mesmo token de usuário.

CREATE TABLE devices (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name          TEXT        NOT NULL DEFAULT '',      -- apelido dado no pareamento ("Coletor doca 1")
    device_uuid   TEXT,                                 -- ANDROID_ID / IDFV
    model         TEXT,
    os            TEXT,
    app_version   TEXT,
    secret_hash   TEXT        NOT NULL,                 -- SHA-256 do segredo (o segredo só existe no aparelho)
    created_by    UUID REFERENCES users(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ,
    last_user_id  UUID REFERENCES users(id),
    revoked_at    TIMESTAMPTZ,
    revoked_by    UUID REFERENCES users(id)
);
CREATE INDEX devices_tenant ON devices (tenant_id, revoked_at);

CREATE TABLE device_pairings (
    code_hash   TEXT PRIMARY KEY,                       -- SHA-256 do código (o código aparece só na tela)
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        TEXT        NOT NULL DEFAULT '',
    created_by  UUID REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    device_id   UUID REFERENCES devices(id) ON DELETE SET NULL
);
CREATE INDEX device_pairings_tenant ON device_pairings (tenant_id, created_at DESC);
