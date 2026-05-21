-- NeoOptimize AI-Empowered Telemetry Schema
-- Adds the four telemetry planes:
-- 1. host identity/environment baseline
-- 2. high-frequency performance metrics
-- 3. command impact before/after evidence
-- 4. agent safety/self-healing state

BEGIN;

ALTER TABLE telemetry
  ADD COLUMN IF NOT EXISTS active_command_id UUID REFERENCES commands(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS schema_version SMALLINT NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS sample_kind VARCHAR(30) NOT NULL DEFAULT 'periodic',
  ADD COLUMN IF NOT EXISTS cpu_kernel_pct FLOAT4,
  ADD COLUMN IF NOT EXISTS cpu_clock_mhz FLOAT4,
  ADD COLUMN IF NOT EXISTS memory_available_mb INTEGER,
  ADD COLUMN IF NOT EXISTS memory_committed_pct FLOAT4,
  ADD COLUMN IF NOT EXISTS memory_cache_faults_sec FLOAT4,
  ADD COLUMN IF NOT EXISTS disk_read_bytes_sec FLOAT8,
  ADD COLUMN IF NOT EXISTS disk_write_bytes_sec FLOAT8,
  ADD COLUMN IF NOT EXISTS disk_rw_bytes_sec FLOAT8,
  ADD COLUMN IF NOT EXISTS disk_queue_length FLOAT4,
  ADD COLUMN IF NOT EXISTS disk_time_pct FLOAT4,
  ADD COLUMN IF NOT EXISTS disk_latency_ms FLOAT4,
  ADD COLUMN IF NOT EXISTS network_bandwidth_bps FLOAT8,
  ADD COLUMN IF NOT EXISTS network_bytes_total_sec FLOAT8,
  ADD COLUMN IF NOT EXISTS network_output_queue_length FLOAT4,
  ADD COLUMN IF NOT EXISTS network_latency_ms FLOAT4,
  ADD COLUMN IF NOT EXISTS power_profile VARCHAR(80),
  ADD COLUMN IF NOT EXISTS on_battery BOOLEAN,
  ADD COLUMN IF NOT EXISTS handle_count INTEGER,
  ADD COLUMN IF NOT EXISTS thread_count INTEGER,
  ADD COLUMN IF NOT EXISTS process_count INTEGER,
  ADD COLUMN IF NOT EXISTS metrics JSONB NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS host_baseline JSONB NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS security_state JSONB NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_telemetry_tenant_agent_ts ON telemetry(tenant_id, agent_id, ts DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_sample_kind_ts ON telemetry(sample_kind, ts DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_ai_anomaly
  ON telemetry(tenant_id, ts DESC)
  WHERE cpu_pct >= 85 OR memory_committed_pct >= 90 OR disk_queue_length >= 2 OR disk_time_pct >= 90;

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

COMMIT;
