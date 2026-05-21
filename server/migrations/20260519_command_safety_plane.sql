-- NeoOptimize Command Safety Plane migration
-- Safe to run repeatedly on an existing database.

BEGIN;

ALTER TABLE commands
  ADD COLUMN IF NOT EXISTS safety_manifest_id UUID;

CREATE TABLE IF NOT EXISTS safety_manifests (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id         UUID          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    command_id        UUID          NOT NULL,
    command_type      VARCHAR(50)   NOT NULL,
    version           VARCHAR(30)   NOT NULL DEFAULT '1.0.0',
    manifest          JSONB         NOT NULL,
    manifest_sha256   VARCHAR(64)   NOT NULL,
    signature         TEXT          NOT NULL,
    status            VARCHAR(20)   NOT NULL DEFAULT 'ACTIVE',
    risk_level        VARCHAR(20)   NOT NULL,
    canary_phase      VARCHAR(40)   NOT NULL DEFAULT 'PHASE_1_CANARY',
    target_percentage NUMERIC(5,2)  NOT NULL DEFAULT 1.00,
    bake_until        TIMESTAMPTZ,
    failure_rate      FLOAT4        NOT NULL DEFAULT 0,
    created_by        UUID          REFERENCES users(id) ON DELETE SET NULL,
    created_by_type   VARCHAR(20)   NOT NULL DEFAULT 'user',
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    revoked_by        UUID          REFERENCES users(id) ON DELETE SET NULL,
    revoked_at        TIMESTAMPTZ,
    revoke_reason     TEXT,
    completed_at      TIMESTAMPTZ,
    CONSTRAINT chk_safety_manifest_status CHECK (status IN ('ACTIVE','PAUSED','REVOKED','COMPLETED')),
    CONSTRAINT chk_safety_manifest_risk CHECK (risk_level IN ('LOW','MEDIUM','HIGH','CRITICAL'))
);

CREATE INDEX IF NOT EXISTS idx_safety_manifests_tenant ON safety_manifests(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_safety_manifests_status ON safety_manifests(status, risk_level);
CREATE INDEX IF NOT EXISTS idx_safety_manifests_command ON safety_manifests(command_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_commands_safety_manifest'
  ) THEN
    ALTER TABLE commands
      ADD CONSTRAINT fk_commands_safety_manifest
      FOREIGN KEY (safety_manifest_id) REFERENCES safety_manifests(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS safety_manifest_targets (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    manifest_id   UUID        NOT NULL REFERENCES safety_manifests(id) ON DELETE CASCADE,
    tenant_id      UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    agent_id       UUID        NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    command_id     UUID        REFERENCES commands(id) ON DELETE SET NULL,
    phase          VARCHAR(40) NOT NULL DEFAULT 'PHASE_1_CANARY',
    status         VARCHAR(30) NOT NULL DEFAULT 'QUEUED',
    assigned_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at   TIMESTAMPTZ,
    reported_at    TIMESTAMPTZ,
    failure_reason TEXT,
    impact         JSONB       NOT NULL DEFAULT '{}',
    UNIQUE (manifest_id, agent_id),
    CONSTRAINT chk_safety_target_status CHECK (status IN ('QUEUED','DELIVERED','SUCCESS','FAILED','TIMEOUT','ROLLBACK','REJECTED','REVOKED'))
);

CREATE INDEX IF NOT EXISTS idx_safety_targets_manifest ON safety_manifest_targets(manifest_id, status);
CREATE INDEX IF NOT EXISTS idx_safety_targets_agent ON safety_manifest_targets(agent_id, assigned_at DESC);

CREATE TABLE IF NOT EXISTS safety_events (
    id            BIGSERIAL PRIMARY KEY,
    manifest_id   UUID        REFERENCES safety_manifests(id) ON DELETE SET NULL,
    command_id     UUID        REFERENCES commands(id) ON DELETE SET NULL,
    tenant_id      UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    agent_id       UUID        REFERENCES agents(id) ON DELETE SET NULL,
    event_type     VARCHAR(50) NOT NULL,
    severity       VARCHAR(20) NOT NULL DEFAULT 'info',
    payload        JSONB       NOT NULL DEFAULT '{}',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_safety_events_manifest ON safety_events(manifest_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_safety_events_tenant ON safety_events(tenant_id, created_at DESC);

COMMIT;

