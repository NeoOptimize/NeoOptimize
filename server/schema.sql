-- ═══════════════════════════════════════════════════════════════════
-- NeoOptimize RMM — PostgreSQL Schema v6.0 (Production Hardened)
-- BUG FIXES v6.0:
--   [BUG-S01] Added all missing telemetry columns (location_label,
--             location_detail, camera_available, microphone_available,
--             biometric_available, device_info, bugs, verbose_info)
--   [BUG-S02] Added tenant_id to commands table (was missing)
--   [NEW]     scheduled_tasks table for cron-like automation
--   [NEW]     agent_groups table for bulk tag operations
--   [NEW]     alert_rules table for auto-response rules
--   [NEW]     system_health_scores table for trending
--   [NEW]     ollama_analyses table for local AI decisions
--   [NEW]     Extended telemetry partitions through 2028-12
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── Tenants ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS tenants (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        VARCHAR(120)  NOT NULL,
    plan        VARCHAR(30)   NOT NULL DEFAULT 'free',
    max_agents  INTEGER       NOT NULL DEFAULT 10,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    is_active   BOOLEAN       NOT NULL DEFAULT TRUE,
    -- Webhook for external notifications
    webhook_url TEXT,
    webhook_secret TEXT
);

-- ─── Dashboard Users ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    email           VARCHAR(255)  NOT NULL UNIQUE,
    password_hash   VARCHAR(255)  NOT NULL,
    role            VARCHAR(20)   NOT NULL DEFAULT 'operator',
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    last_login      TIMESTAMPTZ,
    -- TOTP 2FA
    totp_secret     TEXT,
    totp_enabled    BOOLEAN       NOT NULL DEFAULT FALSE,
    -- WebAuthn / FIDO2 Biometric
    webauthn_credential_id  TEXT,
    webauthn_public_key     TEXT,
    webauthn_sign_count     INTEGER NOT NULL DEFAULT 0,
    -- Preferences
    notification_email BOOLEAN NOT NULL DEFAULT TRUE,
    notification_telegram BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_users_tenant ON users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_users_email  ON users(email);

-- ─── Agent Groups / Tags ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS agent_groups (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        VARCHAR(80) NOT NULL,
    description TEXT,
    color       VARCHAR(7)  DEFAULT '#00e57a',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Agents ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS agents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    hostname        VARCHAR(255)  NOT NULL,
    bios_uuid       VARCHAR(64)   UNIQUE NOT NULL,
    api_key_hash    VARCHAR(64)   NOT NULL,
    version         VARCHAR(20)   NOT NULL DEFAULT '5.0.0',
    os              VARCHAR(120),
    cpu             VARCHAR(120),
    gpu             VARCHAR(120),
    ram_mb          INTEGER,
    ip_address      INET,
    public_ip       INET,
    status          VARCHAR(20)   NOT NULL DEFAULT 'offline',
    last_seen       TIMESTAMPTZ,
    first_seen      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    missed_checkins INTEGER       NOT NULL DEFAULT 0,
    tags            JSONB         NOT NULL DEFAULT '[]',
    metadata        JSONB         NOT NULL DEFAULT '{}',
    -- Health score (0-100)
    health_score    SMALLINT      NOT NULL DEFAULT 100,
    health_reason   TEXT,
    -- Group assignment
    group_id        UUID          REFERENCES agent_groups(id) ON DELETE SET NULL,
    -- Agent notes
    notes           TEXT
);

CREATE INDEX IF NOT EXISTS idx_agents_tenant    ON agents(tenant_id);
CREATE INDEX IF NOT EXISTS idx_agents_status    ON agents(status);
CREATE INDEX IF NOT EXISTS idx_agents_last_seen ON agents(last_seen);
CREATE INDEX IF NOT EXISTS idx_agents_bios_uuid ON agents(bios_uuid);
CREATE INDEX IF NOT EXISTS idx_agents_group     ON agents(group_id);

-- ─── Commands ─────────────────────────────────────────────────────
-- [BUG-S02 FIX] Added tenant_id column
CREATE TABLE IF NOT EXISTS commands (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id     UUID          NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    tenant_id    UUID          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    type         VARCHAR(50)   NOT NULL,
    args         JSONB         NOT NULL DEFAULT '{}',
    signature    TEXT,
    status       VARCHAR(20)   NOT NULL DEFAULT 'pending',
    priority     SMALLINT      NOT NULL DEFAULT 5,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    started_at   TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    timeout_secs INTEGER       NOT NULL DEFAULT 300,
    issued_by    UUID          REFERENCES users(id) ON DELETE SET NULL,
    issued_by_type VARCHAR(20) NOT NULL DEFAULT 'user',  -- 'user' | 'ai_system' | 'scheduled'
    result       JSONB         NOT NULL DEFAULT '{}',
    safety_manifest_id UUID,
    -- Scheduled task reference
    scheduled_task_id UUID
);

CREATE INDEX IF NOT EXISTS idx_commands_agent_status ON commands(agent_id, status);
CREATE INDEX IF NOT EXISTS idx_commands_status       ON commands(status);
CREATE INDEX IF NOT EXISTS idx_commands_created_at   ON commands(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_commands_tenant       ON commands(tenant_id);

-- ─── Command Safety Plane ────────────────────────────────────────
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

-- ─── Scheduled Tasks ──────────────────────────────────────────────
-- [NEW] Cron-like automation for periodic commands
CREATE TABLE IF NOT EXISTS scheduled_tasks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        VARCHAR(120) NOT NULL,
    description TEXT,
    -- Target: single agent, group, or all
    agent_id    UUID REFERENCES agents(id) ON DELETE CASCADE,
    group_id    UUID REFERENCES agent_groups(id) ON DELETE CASCADE,
    target_all  BOOLEAN NOT NULL DEFAULT FALSE,
    -- Command to run
    cmd_type    VARCHAR(50) NOT NULL,
    cmd_args    JSONB NOT NULL DEFAULT '{}',
    priority    SMALLINT NOT NULL DEFAULT 5,
    -- Schedule (cron expression, e.g. '0 2 * * 0' = Sunday 2AM)
    cron_expr   VARCHAR(100) NOT NULL DEFAULT '0 2 * * 0',
    timezone    VARCHAR(50) NOT NULL DEFAULT 'UTC',
    -- State
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    last_run    TIMESTAMPTZ,
    next_run    TIMESTAMPTZ,
    run_count   INTEGER NOT NULL DEFAULT 0,
    created_by  UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sched_tenant   ON scheduled_tasks(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sched_next_run ON scheduled_tasks(next_run) WHERE is_active = TRUE;

-- ─── Alert Rules ──────────────────────────────────────────────────
-- [NEW] Auto-response rules based on thresholds
CREATE TABLE IF NOT EXISTS alert_rules (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        VARCHAR(120) NOT NULL,
    description TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    -- Trigger condition (json: {metric, operator, threshold})
    condition   JSONB NOT NULL,
    -- Action when triggered
    action_cmd  VARCHAR(50),
    action_args JSONB NOT NULL DEFAULT '{}',
    -- Notification
    notify_telegram BOOLEAN NOT NULL DEFAULT TRUE,
    notify_email    BOOLEAN NOT NULL DEFAULT FALSE,
    -- Cooldown to prevent spam (minutes)
    cooldown_min INTEGER NOT NULL DEFAULT 60,
    last_triggered TIMESTAMPTZ,
    trigger_count  INTEGER NOT NULL DEFAULT 0,
    created_by  UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alert_rules_tenant ON alert_rules(tenant_id);

-- ─── Telemetry (partitioned) ──────────────────────────────────────
-- [BUG-S01 FIX] Added ALL missing columns: location_label, location_detail,
-- camera_available, microphone_available, biometric_available, device_info,
-- bugs, verbose_info, tenant_id
CREATE TABLE IF NOT EXISTS telemetry (
    id              BIGSERIAL,
    agent_id        UUID        NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    ts              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    active_command_id UUID      REFERENCES commands(id) ON DELETE SET NULL,
    schema_version  SMALLINT    NOT NULL DEFAULT 2,
    sample_kind     VARCHAR(30) NOT NULL DEFAULT 'periodic',
    -- Performance
    cpu_pct         FLOAT4,
    cpu_kernel_pct  FLOAT4,
    cpu_clock_mhz   FLOAT4,
    ram_used_mb     INTEGER,
    memory_available_mb INTEGER,
    memory_committed_pct FLOAT4,
    memory_cache_faults_sec FLOAT4,
    disk_free_gb    FLOAT4,
    disk_read_bytes_sec FLOAT8,
    disk_write_bytes_sec FLOAT8,
    disk_rw_bytes_sec FLOAT8,
    disk_queue_length FLOAT4,
    disk_time_pct   FLOAT4,
    disk_latency_ms FLOAT4,
    net_rx_kbps     FLOAT4,
    net_tx_kbps     FLOAT4,
    network_bandwidth_bps FLOAT8,
    network_bytes_total_sec FLOAT8,
    network_output_queue_length FLOAT4,
    network_latency_ms FLOAT4,
    power_profile   VARCHAR(80),
    on_battery      BOOLEAN,
    handle_count    INTEGER,
    thread_count    INTEGER,
    process_count   INTEGER,
    -- GPU
    gpu_pct         FLOAT4,
    gpu_temp_c      FLOAT4,
    cpu_temp_c      FLOAT4,
    gpu_name        VARCHAR(120),
    -- Peripherals
    cam_active      BOOLEAN,   -- raw C# field
    mic_active      BOOLEAN,   -- raw C# field
    camera_available      BOOLEAN,   -- flusher field (alias)
    microphone_available  BOOLEAN,   -- flusher field (alias)
    biometric_available   BOOLEAN,
    -- Location
    public_ip       INET,
    geo_city        VARCHAR(120),
    geo_country     VARCHAR(80),
    geo_lat         FLOAT8,
    geo_lon         FLOAT8,
    location_label  VARCHAR(120),
    location_detail JSONB NOT NULL DEFAULT '{}',
    -- Extended info (flusher fields)
    device_info     JSONB NOT NULL DEFAULT '{}',
    bugs            JSONB NOT NULL DEFAULT '{}',
    verbose_info    JSONB NOT NULL DEFAULT '{}',
    metrics         JSONB NOT NULL DEFAULT '{}',
    host_baseline   JSONB NOT NULL DEFAULT '{}',
    security_state  JSONB NOT NULL DEFAULT '{}',
    -- Catch-all
    extra           JSONB NOT NULL DEFAULT '{}'
) PARTITION BY RANGE (ts);

-- Partitions 2026
CREATE TABLE IF NOT EXISTS telemetry_2026_04 PARTITION OF telemetry FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE IF NOT EXISTS telemetry_2026_05 PARTITION OF telemetry FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE IF NOT EXISTS telemetry_2026_06 PARTITION OF telemetry FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE IF NOT EXISTS telemetry_2026_07 PARTITION OF telemetry FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE IF NOT EXISTS telemetry_2026_08 PARTITION OF telemetry FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE IF NOT EXISTS telemetry_2026_09 PARTITION OF telemetry FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE IF NOT EXISTS telemetry_2026_10 PARTITION OF telemetry FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE IF NOT EXISTS telemetry_2026_11 PARTITION OF telemetry FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE IF NOT EXISTS telemetry_2026_12 PARTITION OF telemetry FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');
-- Partitions 2027
CREATE TABLE IF NOT EXISTS telemetry_2027_01 PARTITION OF telemetry FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_02 PARTITION OF telemetry FOR VALUES FROM ('2027-02-01') TO ('2027-03-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_03 PARTITION OF telemetry FOR VALUES FROM ('2027-03-01') TO ('2027-04-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_04 PARTITION OF telemetry FOR VALUES FROM ('2027-04-01') TO ('2027-05-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_05 PARTITION OF telemetry FOR VALUES FROM ('2027-05-01') TO ('2027-06-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_06 PARTITION OF telemetry FOR VALUES FROM ('2027-06-01') TO ('2027-07-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_07 PARTITION OF telemetry FOR VALUES FROM ('2027-07-01') TO ('2027-08-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_08 PARTITION OF telemetry FOR VALUES FROM ('2027-08-01') TO ('2027-09-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_09 PARTITION OF telemetry FOR VALUES FROM ('2027-09-01') TO ('2027-10-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_10 PARTITION OF telemetry FOR VALUES FROM ('2027-10-01') TO ('2027-11-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_11 PARTITION OF telemetry FOR VALUES FROM ('2027-11-01') TO ('2027-12-01');
CREATE TABLE IF NOT EXISTS telemetry_2027_12 PARTITION OF telemetry FOR VALUES FROM ('2027-12-01') TO ('2028-01-01');
-- Partitions 2028
CREATE TABLE IF NOT EXISTS telemetry_2028_01 PARTITION OF telemetry FOR VALUES FROM ('2028-01-01') TO ('2028-02-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_02 PARTITION OF telemetry FOR VALUES FROM ('2028-02-01') TO ('2028-03-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_03 PARTITION OF telemetry FOR VALUES FROM ('2028-03-01') TO ('2028-04-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_04 PARTITION OF telemetry FOR VALUES FROM ('2028-04-01') TO ('2028-05-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_05 PARTITION OF telemetry FOR VALUES FROM ('2028-05-01') TO ('2028-06-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_06 PARTITION OF telemetry FOR VALUES FROM ('2028-06-01') TO ('2028-07-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_07 PARTITION OF telemetry FOR VALUES FROM ('2028-07-01') TO ('2028-08-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_08 PARTITION OF telemetry FOR VALUES FROM ('2028-08-01') TO ('2028-09-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_09 PARTITION OF telemetry FOR VALUES FROM ('2028-09-01') TO ('2028-10-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_10 PARTITION OF telemetry FOR VALUES FROM ('2028-10-01') TO ('2028-11-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_11 PARTITION OF telemetry FOR VALUES FROM ('2028-11-01') TO ('2028-12-01');
CREATE TABLE IF NOT EXISTS telemetry_2028_12 PARTITION OF telemetry FOR VALUES FROM ('2028-12-01') TO ('2029-01-01');
CREATE TABLE IF NOT EXISTS telemetry_default PARTITION OF telemetry DEFAULT;

CREATE INDEX IF NOT EXISTS idx_telemetry_agent_ts ON telemetry(agent_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_ts       ON telemetry(ts DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_tenant   ON telemetry(tenant_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_tenant_agent_ts ON telemetry(tenant_id, agent_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_sample_kind_ts ON telemetry(sample_kind, ts DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_ai_anomaly
  ON telemetry(tenant_id, ts DESC)
  WHERE cpu_pct >= 85 OR memory_committed_pct >= 90 OR disk_queue_length >= 2 OR disk_time_pct >= 90;

-- ─── AI-Empowered Telemetry Catalog ───────────────────────────────
-- Host identity/environment baseline, updated by agent check-in.
CREATE TABLE IF NOT EXISTS agent_host_baselines (
    agent_id      UUID PRIMARY KEY REFERENCES agents(id) ON DELETE CASCADE,
    tenant_id     UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    captured_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hostname      VARCHAR(255),
    os            JSONB       NOT NULL DEFAULT '{}',
    hardware      JSONB       NOT NULL DEFAULT '{}',
    disks         JSONB       NOT NULL DEFAULT '[]',
    security      JSONB       NOT NULL DEFAULT '{}',
    environment   JSONB       NOT NULL DEFAULT '{}',
    profile_hash  VARCHAR(64),
    raw_payload   JSONB       NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_agent_host_baselines_tenant ON agent_host_baselines(tenant_id, captured_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_host_baselines_profile ON agent_host_baselines(profile_hash);

-- Before/after command impact evidence for AI-verifiable treatment.
CREATE TABLE IF NOT EXISTS command_impact_metrics (
    id          BIGSERIAL PRIMARY KEY,
    command_id  UUID        NOT NULL REFERENCES commands(id) ON DELETE CASCADE,
    manifest_id UUID        REFERENCES safety_manifests(id) ON DELETE SET NULL,
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    agent_id    UUID        NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    status      VARCHAR(30) NOT NULL,
    baseline    JSONB       NOT NULL DEFAULT '{}',
    post_treatment JSONB    NOT NULL DEFAULT '{}',
    deltas      JSONB       NOT NULL DEFAULT '{}',
    event_probe JSONB       NOT NULL DEFAULT '{}',
    ram_freed_bytes BIGINT,
    cpu_stabilization_time_ms INTEGER,
    disk_latency_delta FLOAT4,
    handle_count INTEGER,
    thread_count INTEGER,
    process_count INTEGER,
    self_healing_triggered BOOLEAN NOT NULL DEFAULT FALSE,
    rollback_success BOOLEAN,
    report_payload JSONB    NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (command_id)
);

CREATE INDEX IF NOT EXISTS idx_command_impact_tenant ON command_impact_metrics(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_command_impact_agent ON command_impact_metrics(agent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_command_impact_status ON command_impact_metrics(status, created_at DESC);

-- Instant endpoint safety/self-healing state for circuit-breaker decisions.
CREATE TABLE IF NOT EXISTS agent_safety_states (
    id          BIGSERIAL PRIMARY KEY,
    agent_id    UUID        NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    command_id  UUID        REFERENCES commands(id) ON DELETE SET NULL,
    manifest_id UUID        REFERENCES safety_manifests(id) ON DELETE SET NULL,
    state_machine_position VARCHAR(40),
    guardrail_breach_reason VARCHAR(160),
    rollback_success BOOLEAN,
    secure_store_integrity JSONB NOT NULL DEFAULT '{}',
    payload     JSONB       NOT NULL DEFAULT '{}',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agent_safety_states_agent ON agent_safety_states(agent_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_safety_states_tenant ON agent_safety_states(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_safety_states_manifest ON agent_safety_states(manifest_id, created_at DESC);

-- ─── Audit Logs ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_logs (
    id          BIGSERIAL PRIMARY KEY,
    actor_id    UUID,
    actor_type  VARCHAR(30)  NOT NULL DEFAULT 'user',  -- 'user' | 'ai_system' | 'agent' | 'scheduler'
    action      VARCHAR(80)  NOT NULL,
    target_id   UUID,
    target_type VARCHAR(40),
    detail      JSONB        NOT NULL DEFAULT '{}',
    ip_address  INET,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_actor      ON audit_logs(actor_id);
CREATE INDEX IF NOT EXISTS idx_audit_action     ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_logs(created_at DESC);

-- ─── Signing Keys ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS signing_keys (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    public_key      TEXT        NOT NULL,
    private_key_enc TEXT        NOT NULL,
    algorithm       VARCHAR(20) NOT NULL DEFAULT 'RSA-2048-SHA256',
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    rotated_at      TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ
);

-- ─── Security Alerts ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS security_alerts (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id     UUID        REFERENCES agents(id) ON DELETE SET NULL,
    tenant_id    UUID        REFERENCES tenants(id) ON DELETE CASCADE,
    source       VARCHAR(40) NOT NULL DEFAULT 'aegis_av',
    severity     VARCHAR(20) NOT NULL,
    rule_name    VARCHAR(200),
    description  TEXT,
    src_ip       INET,
    process_name VARCHAR(200),
    -- AI analysis
    ai_decision  VARCHAR(30),  -- 'QUARANTINE' | 'MONITOR' | 'IGNORE' | 'AUTOIMMUNE'
    ai_reason    TEXT,
    ai_confidence SMALLINT,
    ai_model     VARCHAR(60),  -- which model made the decision
    -- Status
    resolved     BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_by  UUID REFERENCES users(id) ON DELETE SET NULL,
    resolved_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alerts_agent    ON security_alerts(agent_id);
CREATE INDEX IF NOT EXISTS idx_alerts_tenant   ON security_alerts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_alerts_severity ON security_alerts(severity);
CREATE INDEX IF NOT EXISTS idx_alerts_created  ON security_alerts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_resolved ON security_alerts(resolved) WHERE resolved = FALSE;

-- ─── Ollama AI Analyses ───────────────────────────────────────────
-- [NEW] Tracks all local AI analysis decisions
CREATE TABLE IF NOT EXISTS ollama_analyses (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id    UUID REFERENCES agents(id) ON DELETE SET NULL,
    tenant_id   UUID REFERENCES tenants(id) ON DELETE CASCADE,
    alert_id    UUID REFERENCES security_alerts(id) ON DELETE SET NULL,
    model       VARCHAR(60) NOT NULL,
    prompt_type VARCHAR(40) NOT NULL, -- 'threat_analysis' | 'health_score' | 'anomaly'
    input_data  JSONB NOT NULL DEFAULT '{}',
    output_text TEXT,
    decision    VARCHAR(30),
    confidence  SMALLINT,
    duration_ms INTEGER,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ollama_agent   ON ollama_analyses(agent_id);
CREATE INDEX IF NOT EXISTS idx_ollama_tenant  ON ollama_analyses(tenant_id, created_at DESC);

-- ─── System Health Scores (historical) ───────────────────────────
-- [NEW] Rolling health score tracking for trend analysis
CREATE TABLE IF NOT EXISTS health_scores (
    id          BIGSERIAL PRIMARY KEY,
    agent_id    UUID        NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    score       SMALLINT    NOT NULL, -- 0-100
    components  JSONB       NOT NULL DEFAULT '{}', -- {cpu:90, ram:80, disk:100, security:95}
    ts          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_health_agent_ts ON health_scores(agent_id, ts DESC);

-- ─── SEEDS ────────────────────────────────────────────────────────
INSERT INTO tenants (id, name, plan, max_agents)
VALUES ('00000000-0000-0000-0000-000000000001', 'Default', 'enterprise', 9999)
ON CONFLICT (id) DO NOTHING;

-- Bootstrap admin. Setup should replace this locked hash with an operator-provided password.
INSERT INTO users (id, tenant_id, email, password_hash, role)
VALUES (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000001',
    'admin@neooptimize.local',
    '$2b$12$xUkxxLOEVv7KAN4lWAeqFevfuFmoQlQb1htH.lW.gkLxUinMgYlC.',
    'admin'
) ON CONFLICT (id) DO NOTHING;

-- AI Service Account (cannot login — used for audit trail of AI actions)
INSERT INTO users (id, tenant_id, email, password_hash, role, is_active)
VALUES (
    '00000000-0000-0000-0000-000000000099',
    '00000000-0000-0000-0000-000000000001',
    'openfang-ai@system.local',
    '$2b$12$DISABLED_ACCOUNT_NO_LOGIN_POSSIBLE_XXXXXXXXXXXXXXXXXX',
    'operator',
    FALSE
) ON CONFLICT (id) DO NOTHING;

-- Default alert rules
INSERT INTO alert_rules (tenant_id, name, description, condition, action_cmd, notify_telegram, cooldown_min)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'High CPU Alert',
   'Trigger OPTIMIZE when CPU stays above 90%',
   '{"metric":"cpu_pct","operator":"gt","threshold":90,"duration_min":5}',
   'OPTIMIZE', TRUE, 60),
  ('00000000-0000-0000-0000-000000000001', 'Low Disk Alert',
   'Alert when free disk drops below 5GB',
   '{"metric":"disk_free_gb","operator":"lt","threshold":5}',
   NULL, TRUE, 120),
  ('00000000-0000-0000-0000-000000000001', 'Weekly Cleanup',
   'Run cleaner every Sunday at 2AM',
   '{"metric":"scheduled","cron":"0 2 * * 0"}',
   'CLEAN', FALSE, 10080)
ON CONFLICT DO NOTHING;

COMMIT;
