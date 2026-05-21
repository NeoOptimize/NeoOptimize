-- ═══════════════════════════════════════════════════════════════════
-- NeoOptimize RMM — Migration Script v5.x → v6.0
-- Safe to run on existing database (uses IF NOT EXISTS / ALTER IF)
-- Run: psql -U neo_app -d neooptimize_rmm -f migrate_v6.sql
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Add tenant_id to commands (BUG-S02 FIX) ──────────────────
ALTER TABLE commands
  ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE;

-- Backfill tenant_id from agent's tenant_id for existing rows
UPDATE commands c
SET tenant_id = a.tenant_id
FROM agents a
WHERE c.agent_id = a.id
  AND c.tenant_id IS NULL;

-- Now make it NOT NULL (after backfill)
ALTER TABLE commands
  ALTER COLUMN tenant_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_commands_tenant ON commands(tenant_id);

-- ─── 2. Fix telemetry missing columns (BUG-S01 FIX) ──────────────
ALTER TABLE telemetry
  ADD COLUMN IF NOT EXISTS tenant_id          UUID REFERENCES tenants(id),
  ADD COLUMN IF NOT EXISTS camera_available   BOOLEAN,
  ADD COLUMN IF NOT EXISTS microphone_available BOOLEAN,
  ADD COLUMN IF NOT EXISTS biometric_available BOOLEAN,
  ADD COLUMN IF NOT EXISTS location_label     VARCHAR(120),
  ADD COLUMN IF NOT EXISTS location_detail    JSONB NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS device_info        JSONB NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS bugs               JSONB NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS verbose_info       JSONB NOT NULL DEFAULT '{}';

-- Backfill tenant_id on telemetry from agents
UPDATE telemetry t
SET tenant_id = a.tenant_id
FROM agents a
WHERE t.agent_id = a.id
  AND t.tenant_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_telemetry_tenant ON telemetry(tenant_id, ts DESC);

-- ─── 3. Add missing columns to agents ─────────────────────────────
ALTER TABLE agents
  ADD COLUMN IF NOT EXISTS health_score  SMALLINT NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS health_reason TEXT,
  ADD COLUMN IF NOT EXISTS group_id      UUID REFERENCES agent_groups(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS notes         TEXT;

-- ─── 4. Add missing columns to tenants ───────────────────────────
ALTER TABLE tenants
  ADD COLUMN IF NOT EXISTS webhook_url    TEXT,
  ADD COLUMN IF NOT EXISTS webhook_secret TEXT;

-- ─── 5. Add missing columns to users ─────────────────────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS totp_secret           TEXT,
  ADD COLUMN IF NOT EXISTS totp_enabled          BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS notification_email    BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS notification_telegram BOOLEAN NOT NULL DEFAULT TRUE;

-- ─── 6. Add missing columns to security_alerts ───────────────────
ALTER TABLE security_alerts
  ADD COLUMN IF NOT EXISTS tenant_id   UUID REFERENCES tenants(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS ai_model    VARCHAR(60),
  ADD COLUMN IF NOT EXISTS resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;

-- Backfill tenant_id on security_alerts
UPDATE security_alerts sa
SET tenant_id = a.tenant_id
FROM agents a
WHERE sa.agent_id = a.id
  AND sa.tenant_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_alerts_tenant   ON security_alerts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_alerts_resolved ON security_alerts(resolved) WHERE NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_alerts_resolved');

-- ─── 7. Add commands.scheduled_task_id ───────────────────────────
ALTER TABLE commands
  ADD COLUMN IF NOT EXISTS scheduled_task_id UUID,
  ADD COLUMN IF NOT EXISTS safety_manifest_id UUID;

-- ─── 8. Create new tables (if not exist) ──────────────────────────

-- Agent Groups
CREATE TABLE IF NOT EXISTS agent_groups (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        VARCHAR(80) NOT NULL,
    description TEXT,
    color       VARCHAR(7)  DEFAULT '#00e57a',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_agent_groups_tenant ON agent_groups(tenant_id);

-- Scheduled Tasks
CREATE TABLE IF NOT EXISTS scheduled_tasks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        VARCHAR(120) NOT NULL,
    description TEXT,
    agent_id    UUID REFERENCES agents(id) ON DELETE CASCADE,
    group_id    UUID REFERENCES agent_groups(id) ON DELETE CASCADE,
    target_all  BOOLEAN NOT NULL DEFAULT FALSE,
    cmd_type    VARCHAR(50) NOT NULL,
    cmd_args    JSONB NOT NULL DEFAULT '{}',
    priority    SMALLINT NOT NULL DEFAULT 5,
    cron_expr   VARCHAR(100) NOT NULL DEFAULT '0 2 * * 0',
    timezone    VARCHAR(50) NOT NULL DEFAULT 'UTC',
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    last_run    TIMESTAMPTZ,
    next_run    TIMESTAMPTZ,
    run_count   INTEGER NOT NULL DEFAULT 0,
    created_by  UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sched_tenant   ON scheduled_tasks(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sched_next_run ON scheduled_tasks(next_run) WHERE is_active = TRUE;

-- Alert Rules
CREATE TABLE IF NOT EXISTS alert_rules (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        VARCHAR(120) NOT NULL,
    description TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    condition   JSONB NOT NULL,
    action_cmd  VARCHAR(50),
    action_args JSONB NOT NULL DEFAULT '{}',
    notify_telegram BOOLEAN NOT NULL DEFAULT TRUE,
    notify_email    BOOLEAN NOT NULL DEFAULT FALSE,
    cooldown_min INTEGER NOT NULL DEFAULT 60,
    last_triggered TIMESTAMPTZ,
    trigger_count  INTEGER NOT NULL DEFAULT 0,
    created_by  UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_alert_rules_tenant ON alert_rules(tenant_id);

-- Ollama AI Analyses
CREATE TABLE IF NOT EXISTS ollama_analyses (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id    UUID REFERENCES agents(id) ON DELETE SET NULL,
    tenant_id   UUID REFERENCES tenants(id) ON DELETE CASCADE,
    alert_id    UUID REFERENCES security_alerts(id) ON DELETE SET NULL,
    model       VARCHAR(60) NOT NULL,
    prompt_type VARCHAR(40) NOT NULL,
    input_data  JSONB NOT NULL DEFAULT '{}',
    output_text TEXT,
    decision    VARCHAR(30),
    confidence  SMALLINT,
    duration_ms INTEGER,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_ollama_agent  ON ollama_analyses(agent_id);
CREATE INDEX IF NOT EXISTS idx_ollama_tenant ON ollama_analyses(tenant_id, created_at DESC);

-- Health Scores
CREATE TABLE IF NOT EXISTS health_scores (
    id          BIGSERIAL PRIMARY KEY,
    agent_id    UUID        NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    score       SMALLINT    NOT NULL,
    components  JSONB       NOT NULL DEFAULT '{}',
    ts          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_health_agent_ts ON health_scores(agent_id, ts DESC);

-- Command Safety Plane
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

-- ─── 9. Insert default alert rules (idempotent) ───────────────────
INSERT INTO alert_rules (tenant_id, name, description, condition, action_cmd, notify_telegram, cooldown_min)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'High CPU Alert',
   'Trigger OPTIMIZE when CPU stays above 90%',
   '{"metric":"cpu_pct","operator":"gt","threshold":90,"duration_min":5}',
   'OPTIMIZE', TRUE, 60),
  ('00000000-0000-0000-0000-000000000001', 'Low Disk Alert',
   'Alert when free disk drops below 5GB',
   '{"metric":"disk_free_gb","operator":"lt","threshold":5}',
   NULL, TRUE, 120)
ON CONFLICT DO NOTHING;

-- ─── Done ──────────────────────────────────────────────────────────
DO $$ BEGIN
  RAISE NOTICE 'NeoOptimize RMM migration v6.0 completed successfully';
END $$;

COMMIT;
