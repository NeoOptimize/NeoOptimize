'use strict'

// ═══════════════════════════════════════════════════════════════════
// NeoOptimize RMM — Agent Routes v5.0 (Production)
// Handles: registration, check-in, telemetry, reports
// FIXES:
//   [BUG#1] Fixed INSERT to use 'issued_by' column (not 'created_by')
//   [NEW]   GPU/temp fields persisted to telemetry table
//   [NEW]   Supabase + Telegram integration hooks
//   [NEW]   timeout_secs passed back to agent in check-in response
// ═══════════════════════════════════════════════════════════════════

const crypto  = require('crypto')
const { supabase, telegram, nullclaw } = require('../lib/integrations')
const { writeAuditLog } = require('../middleware/security')
const { buildMlInsight } = require('../lib/mlAdvisor')
const { evaluateManifestAfterAgentReport } = require('../lib/safetyAutoResponse')
const { normalizeOperatorCommand } = require('../lib/operatorBridge')

function getEnrollmentToken (req) {
  const headerToken = req.headers['x-enrollment-token']
  if (typeof headerToken === 'string' && headerToken.trim()) return headerToken.trim()

  const bodyToken = req.body?.enrollment_token
  if (typeof bodyToken === 'string' && bodyToken.trim()) return bodyToken.trim()

  return ''
}

function tokensMatch (provided, expected) {
  if (!provided || !expected) return false
  const providedBuf = Buffer.from(provided)
  const expectedBuf = Buffer.from(expected)
  if (providedBuf.length !== expectedBuf.length) return false
  return crypto.timingSafeEqual(providedBuf, expectedBuf)
}

async function insertSafetyEvent (fastify, { tenantId, agentId = null, commandId = null, manifestId = null, eventType, severity = 'info', payload = {} }) {
  if (!manifestId) return
  await fastify.db.query(
    `INSERT INTO safety_events (manifest_id, command_id, tenant_id, agent_id, event_type, severity, payload)
     VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [manifestId, commandId, tenantId, agentId, eventType, severity, JSON.stringify(payload || {})]
  )
}

function isObject (value) {
  return value && typeof value === 'object' && !Array.isArray(value)
}

function readPath (source, path) {
  if (!isObject(source)) return undefined
  return path.split('.').reduce((current, key) => {
    if (!isObject(current) && !Array.isArray(current)) return undefined
    return current[key]
  }, source)
}

function firstPresent (...values) {
  for (const value of values) {
    if (value !== undefined && value !== null && value !== '') return value
  }
  return null
}

function asNumber (...values) {
  const value = firstPresent(...values)
  if (value === null) return null
  const parsed = typeof value === 'number' ? value : Number(String(value).trim())
  return Number.isFinite(parsed) ? parsed : null
}

function asInt (...values) {
  const value = asNumber(...values)
  return value === null ? null : Math.round(value)
}

function asBool (...values) {
  const value = firstPresent(...values)
  if (value === null) return null
  if (typeof value === 'boolean') return value
  if (typeof value === 'number') return value !== 0
  const normalized = String(value).trim().toLowerCase()
  if (['true', '1', 'yes', 'enabled', 'active', 'on'].includes(normalized)) return true
  if (['false', '0', 'no', 'disabled', 'inactive', 'off'].includes(normalized)) return false
  return null
}

function parseJsonMaybe (value, fallback) {
  if (isObject(value) || Array.isArray(value)) return value
  if (typeof value !== 'string' || !value.trim()) return fallback
  try {
    return JSON.parse(value)
  } catch {
    return fallback
  }
}

function stableStringify (value) {
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(',')}]`
  if (isObject(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`).join(',')}}`
  }
  return JSON.stringify(value)
}

function telemetryNumber (payload, ...paths) {
  return asNumber(...paths.map((path) => readPath(payload, path)))
}

function telemetryInt (payload, ...paths) {
  return asInt(...paths.map((path) => readPath(payload, path)))
}

function telemetryBool (payload, ...paths) {
  return asBool(...paths.map((path) => readPath(payload, path)))
}

function bytesToMb (value) {
  const bytes = asNumber(value)
  return bytes === null ? null : Math.round(bytes / 1048576)
}

function normalizeTelemetryPayload (payload) {
  const t = isObject(payload) ? payload : {}
  const metrics = isObject(t.metrics) ? t.metrics : {}
  const hostBaseline = isObject(t.host_baseline) ? t.host_baseline : {}
  const securityState = isObject(t.security_state)
    ? t.security_state
    : isObject(hostBaseline.security)
      ? hostBaseline.security
      : {}
  const memoryAvailableMb = asInt(
    t.memory_available_mb,
    readPath(metrics, 'memory.available_mb'),
    bytesToMb(readPath(metrics, 'memory.available_bytes'))
  )
  const networkBytesTotalSec = asNumber(
    t.network_bytes_total_sec,
    readPath(metrics, 'network.bytes_total_sec'),
    readPath(metrics, 'network.bytes_total_per_sec'),
    readPath(metrics, 'network.bytes_total')
  )

  return {
    timestamp: firstPresent(t.ts, t.timestamp, t.created_at),
    activeCommandId: firstPresent(t.active_command_id, t.command_id),
    schemaVersion: asInt(t.schema_version, 2) || 2,
    sampleKind: String(firstPresent(t.sample_kind, t.kind, 'periodic')).slice(0, 30),
    cpuPct: telemetryNumber(t, 'cpu_pct', 'metrics.cpu.utilization_percent'),
    cpuKernelPct: telemetryNumber(t, 'cpu_kernel_pct', 'metrics.cpu.kernel_time_percent'),
    cpuClockMhz: telemetryNumber(t, 'cpu_clock_mhz', 'metrics.cpu.clock_mhz'),
    ramUsedMb: telemetryInt(t, 'ram_used_mb', 'metrics.memory.used_mb'),
    memoryAvailableMb,
    memoryCommittedPct: telemetryNumber(t, 'memory_committed_pct', 'metrics.memory.committed_percent', 'metrics.memory.committed_bytes_in_use_percent', 'metrics.memory.used_percent'),
    memoryCacheFaultsSec: telemetryNumber(t, 'memory_cache_faults_sec', 'metrics.memory.cache_faults_sec'),
    diskFreeGb: telemetryNumber(t, 'disk_free_gb', 'metrics.disk.free_gb'),
    diskReadBytesSec: telemetryNumber(t, 'disk_read_bytes_sec', 'metrics.disk.read_bytes_sec', 'metrics.disk.read_bytes_per_sec'),
    diskWriteBytesSec: telemetryNumber(t, 'disk_write_bytes_sec', 'metrics.disk.write_bytes_sec', 'metrics.disk.write_bytes_per_sec'),
    diskRwBytesSec: asNumber(
      t.disk_rw_bytes_sec,
      readPath(metrics, 'disk.read_write_bytes_sec'),
      readPath(metrics, 'disk.read_write_bytes_per_sec')
    ),
    diskQueueLength: telemetryNumber(t, 'disk_queue_length', 'metrics.disk.queue_length', 'metrics.disk.average_queue_length'),
    diskTimePct: telemetryNumber(t, 'disk_time_pct', 'metrics.disk.disk_time_percent'),
    diskLatencyMs: telemetryNumber(t, 'disk_latency_ms', 'metrics.disk.latency_ms'),
    netRxKbps: telemetryNumber(t, 'net_rx_kbps', 'metrics.network.rx_kbps'),
    netTxKbps: telemetryNumber(t, 'net_tx_kbps', 'metrics.network.tx_kbps'),
    networkBandwidthBps: telemetryNumber(t, 'network_bandwidth_bps', 'metrics.network.current_bandwidth_bps', 'metrics.network.bandwidth_bps'),
    networkBytesTotalSec,
    networkOutputQueueLength: telemetryNumber(t, 'network_output_queue_length', 'metrics.network.output_queue_length'),
    networkLatencyMs: telemetryNumber(t, 'network_latency_ms', 'metrics.network.latency_ms'),
    powerProfile: firstPresent(t.power_profile, readPath(metrics, 'thermal_power.power_profile'), readPath(metrics, 'power.power_profile')),
    onBattery: telemetryBool(t, 'on_battery', 'metrics.thermal_power.on_battery', 'metrics.power.on_battery'),
    handleCount: telemetryInt(t, 'handle_count', 'metrics.processes.handle_count', 'metrics.system.handle_count'),
    threadCount: telemetryInt(t, 'thread_count', 'metrics.processes.thread_count', 'metrics.system.thread_count'),
    processCount: telemetryInt(t, 'process_count', 'metrics.processes.process_count', 'metrics.system.process_count'),
    gpuPct: telemetryNumber(t, 'gpu_pct', 'metrics.gpu.utilization_percent'),
    gpuTempC: telemetryNumber(t, 'gpu_temp_c', 'metrics.gpu.temperature_c'),
    cpuTempC: telemetryNumber(t, 'cpu_temp_c', 'metrics.thermal_power.cpu_temperature_c', 'metrics.thermal.cpu_temperature_c'),
    gpuName: firstPresent(t.gpu_name, readPath(hostBaseline, 'hardware.gpu'), readPath(metrics, 'gpu.name')),
    camActive: telemetryBool(t, 'cam_active', 'metrics.peripherals.cam_active'),
    micActive: telemetryBool(t, 'mic_active', 'metrics.peripherals.mic_active'),
    cameraAvailable: telemetryBool(t, 'camera_available', 'metrics.peripherals.camera_available'),
    microphoneAvailable: telemetryBool(t, 'microphone_available', 'metrics.peripherals.microphone_available'),
    biometricAvailable: telemetryBool(t, 'biometric_available', 'metrics.peripherals.biometric_available'),
    publicIp: firstPresent(t.public_ip, t.publicIp),
    geoCity: firstPresent(t.geo_city, readPath(t, 'geo.city')),
    geoCountry: firstPresent(t.geo_country, readPath(t, 'geo.country')),
    geoLat: asNumber(t.geo_lat, readPath(t, 'geo.lat')),
    geoLon: asNumber(t.geo_lon, readPath(t, 'geo.lon')),
    locationLabel: firstPresent(t.location_label, t.geo_city),
    locationDetail: isObject(t.location_detail) ? t.location_detail : {},
    deviceInfo: isObject(t.device_info) ? t.device_info : {},
    bugs: isObject(t.bugs) ? t.bugs : {},
    verboseInfo: isObject(t.verbose_info) ? t.verbose_info : {},
    metrics,
    hostBaseline,
    securityState,
    extra: {
      raw: t,
      received_at: new Date().toISOString()
    }
  }
}

function normalizeHostBaseline (agent, body = {}) {
  const meta = isObject(body.meta) ? body.meta : {}
  const os = parseJsonMaybe(meta.os_json || meta.os, {
    name: firstPresent(meta.os, agent.os),
    version: firstPresent(meta.os_version, meta.windows_version),
    build: firstPresent(meta.os_build, meta.windows_build),
    edition: firstPresent(meta.os_edition)
  })
  const hardware = parseJsonMaybe(meta.hardware_json, {
    cpu: firstPresent(meta.cpu, agent.cpu),
    cpu_cores: asInt(meta.cpu_cores),
    cpu_threads: asInt(meta.cpu_threads),
    cpu_mhz: asInt(meta.cpu_mhz),
    gpu: firstPresent(meta.gpu, agent.gpu),
    ram_mb: asInt(meta.ram_mb, agent.ram_mb),
    manufacturer: firstPresent(meta.manufacturer),
    model: firstPresent(meta.model),
    motherboard: firstPresent(meta.motherboard)
  })
  const disks = parseJsonMaybe(meta.disks_json || meta.disk_profile_json, [])
  const security = parseJsonMaybe(meta.security_state_json, {
    defender_status: firstPresent(meta.defender_status),
    bitlocker_status: firstPresent(meta.bitlocker_status),
    uac_enabled: asBool(meta.uac_enabled)
  })
  const environment = {
    agent_version: firstPresent(body.version, agent.version),
    hostname: firstPresent(body.hostname, agent.hostname),
    power_profile: firstPresent(meta.power_profile)
  }
  const raw = { meta, version: body.version || null, hostname: body.hostname || null }
  const profileHash = crypto.createHash('sha256')
    .update(stableStringify({ os, hardware, disks, security }))
    .digest('hex')

  return {
    hostname: firstPresent(body.hostname, agent.hostname),
    os,
    hardware,
    disks: Array.isArray(disks) ? disks : [],
    security,
    environment,
    profileHash,
    raw
  }
}

async function upsertHostBaseline (fastify, agent, body) {
  const baseline = normalizeHostBaseline(agent, body)
  await fastify.db.query(
    `INSERT INTO agent_host_baselines
       (agent_id, tenant_id, captured_at, hostname, os, hardware, disks, security, environment, profile_hash, raw_payload)
     VALUES ($1,$2,NOW(),$3,$4,$5,$6,$7,$8,$9,$10)
     ON CONFLICT (agent_id) DO UPDATE SET
       tenant_id = EXCLUDED.tenant_id,
       captured_at = NOW(),
       hostname = EXCLUDED.hostname,
       os = EXCLUDED.os,
       hardware = EXCLUDED.hardware,
       disks = EXCLUDED.disks,
       security = EXCLUDED.security,
       environment = EXCLUDED.environment,
       profile_hash = EXCLUDED.profile_hash,
       raw_payload = EXCLUDED.raw_payload`,
    [
      agent.id,
      agent.tenant_id,
      baseline.hostname,
      JSON.stringify(baseline.os),
      JSON.stringify(baseline.hardware),
      JSON.stringify(baseline.disks),
      JSON.stringify(baseline.security),
      JSON.stringify(baseline.environment),
      baseline.profileHash,
      JSON.stringify(baseline.raw)
    ]
  )
}

function normalizeCommandImpact (status, result = {}) {
  const impact = isObject(result.impact) ? result.impact : {}
  const telemetryDelta = isObject(result.telemetry_delta) ? result.telemetry_delta : {}
  const deltas = isObject(result.deltas)
    ? result.deltas
    : isObject(impact.deltas)
      ? impact.deltas
      : isObject(impact.telemetry_delta)
        ? impact.telemetry_delta
        : telemetryDelta

  return {
    status,
    baseline: firstPresent(result.baseline, impact.baseline, impact.before) || {},
    postTreatment: firstPresent(result.post_treatment, impact.post_treatment, impact.post, impact.after) || {},
    deltas: deltas || {},
    eventProbe: firstPresent(result.event_probe, result.windows_event_probe, impact.event_probe, readPath(result, 'self_healing.guardrail.ForbiddenEvents')) || {},
    ramFreedBytes: asInt(result.ram_freed_bytes, deltas.ram_freed_bytes, deltas.ram_available_bytes_delta, impact.ram_freed_bytes, impact.ram_used_bytes_delta),
    cpuStabilizationTimeMs: asInt(result.cpu_stabilization_time_ms, deltas.cpu_stabilization_time_ms),
    diskLatencyDelta: asNumber(result.disk_latency_delta, deltas.disk_latency_delta, deltas.disk_latency_delta_ms, impact.disk_latency_delta_ms),
    handleCount: asInt(result.handle_count, impact.handle_count, readPath(result, 'process_telemetry.handle_count')),
    threadCount: asInt(result.thread_count, impact.thread_count, readPath(result, 'process_telemetry.thread_count')),
    processCount: asInt(result.process_count, impact.process_count, readPath(result, 'process_telemetry.process_count')),
    selfHealingTriggered: asBool(result.self_healing_triggered, readPath(result, 'self_healing.triggered'), result.rollback, result.rolled_back) || false,
    rollbackSuccess: asBool(result.rollback_success, readPath(result, 'self_healing.rollback_success'), result.rolled_back, result.rollback)
  }
}

async function upsertCommandImpact (fastify, agent, commandId, manifestId, normalizedStatus, result = {}) {
  const impact = normalizeCommandImpact(normalizedStatus, result)
  await fastify.db.query(
    `INSERT INTO command_impact_metrics
       (command_id, manifest_id, tenant_id, agent_id, status, baseline, post_treatment, deltas,
        event_probe, ram_freed_bytes, cpu_stabilization_time_ms, disk_latency_delta,
        handle_count, thread_count, process_count, self_healing_triggered, rollback_success, report_payload)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)
     ON CONFLICT (command_id) DO UPDATE SET
       status = EXCLUDED.status,
       baseline = EXCLUDED.baseline,
       post_treatment = EXCLUDED.post_treatment,
       deltas = EXCLUDED.deltas,
       event_probe = EXCLUDED.event_probe,
       ram_freed_bytes = EXCLUDED.ram_freed_bytes,
       cpu_stabilization_time_ms = EXCLUDED.cpu_stabilization_time_ms,
       disk_latency_delta = EXCLUDED.disk_latency_delta,
       handle_count = EXCLUDED.handle_count,
       thread_count = EXCLUDED.thread_count,
       process_count = EXCLUDED.process_count,
       self_healing_triggered = EXCLUDED.self_healing_triggered,
       rollback_success = EXCLUDED.rollback_success,
       report_payload = EXCLUDED.report_payload,
       created_at = NOW()`,
    [
      commandId,
      manifestId,
      agent.tenant_id,
      agent.id,
      impact.status,
      JSON.stringify(impact.baseline),
      JSON.stringify(impact.postTreatment),
      JSON.stringify(impact.deltas),
      JSON.stringify(impact.eventProbe),
      impact.ramFreedBytes,
      impact.cpuStabilizationTimeMs,
      impact.diskLatencyDelta,
      impact.handleCount,
      impact.threadCount,
      impact.processCount,
      impact.selfHealingTriggered,
      impact.rollbackSuccess,
      JSON.stringify(result || {})
    ]
  )
}

async function insertAgentSafetyState (fastify, agent, commandId, manifestId, result = {}) {
  const state = firstPresent(result.state_machine_position, result.state, readPath(result, 'self_healing.state_machine_position'))
  const reason = firstPresent(result.guardrail_breach_reason, result.reason, readPath(result, 'self_healing.guardrail_breach_reason'), readPath(result, 'self_healing.rollback_reason'), readPath(result, 'self_healing.guardrail.Reason'))
  const rollbackSuccess = asBool(result.rollback_success, readPath(result, 'self_healing.rollback_success'), result.rolled_back, result.rollback)
  const secureStoreIntegrity = firstPresent(result.secure_store_integrity, readPath(result, 'self_healing.secure_store_integrity')) || {}
  const shouldPersist = state || reason || rollbackSuccess !== null || asBool(result.self_healing_triggered, result.rollback, result.rolled_back)

  if (!shouldPersist) return

  await fastify.db.query(
    `INSERT INTO agent_safety_states
       (agent_id, tenant_id, command_id, manifest_id, state_machine_position,
        guardrail_breach_reason, rollback_success, secure_store_integrity, payload)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
    [
      agent.id,
      agent.tenant_id,
      commandId,
      manifestId,
      state,
      reason,
      rollbackSuccess,
      JSON.stringify(isObject(secureStoreIntegrity) ? secureStoreIntegrity : {}),
      JSON.stringify(result || {})
    ]
  )
}

function normalizeSeverityLabel (value) {
  const normalized = String(value || '').trim().toLowerCase()
  if (['critical', 'high', 'medium', 'low', 'info'].includes(normalized)) return normalized
  if (['danger', 'severe', 'emergency'].includes(normalized)) return 'critical'
  if (['warn', 'warning'].includes(normalized)) return 'medium'
  return 'info'
}

function normalizeConfidencePercent (value) {
  const parsed = Number(value)
  if (!Number.isFinite(parsed)) return 72
  const percent = parsed <= 1 ? parsed * 100 : parsed
  return Math.max(0, Math.min(100, Math.round(percent)))
}

function extractNeoAiEnvelope (telemetry = {}) {
  const candidates = [
    readPath(telemetry, 'verboseInfo.neo_ai'),
    readPath(telemetry, 'verboseInfo.ai'),
    readPath(telemetry, 'metrics.neo_ai'),
    readPath(telemetry, 'extra.raw.neo_ai'),
    readPath(telemetry, 'extra.raw.ai')
  ]
  for (const candidate of candidates) {
    if (isObject(candidate)) return candidate
  }
  if (String(telemetry.sampleKind || '').toLowerCase().startsWith('neo_ai')) {
    return isObject(readPath(telemetry, 'extra.raw')) ? readPath(telemetry, 'extra.raw') : {}
  }
  return null
}

function isNeoAiTelemetry (telemetry = {}) {
  return !!extractNeoAiEnvelope(telemetry)
}

function firstRecommendationCommand (neo = {}) {
  const direct = normalizeOperatorCommand(firstPresent(
    neo.recommended_command,
    neo.rmm_command,
    neo.command,
    neo.action
  ))
  if (direct) return direct

  const recommendations = Array.isArray(neo.recommendations) ? neo.recommendations : []
  for (const recommendation of recommendations) {
    const command = normalizeOperatorCommand(firstPresent(
      recommendation?.rmm_command,
      recommendation?.command,
      recommendation?.action,
      recommendation?.local_action,
      recommendation?.module
    ))
    if (command) return command
  }
  return null
}

function buildNeoAiOpenFangPayload (agent, telemetry, neo) {
  const recommendations = Array.isArray(neo.recommendations) ? neo.recommendations : []
  const severity = normalizeSeverityLabel(firstPresent(
    neo.severity,
    neo.risk_level,
    readPath(neo, 'health.risk_level')
  ))
  const action = firstRecommendationCommand(neo)
  const confidence = normalizeConfidencePercent(firstPresent(
    neo.confidence,
    neo.confidence_score,
    readPath(neo, 'health.confidence'),
    recommendations[0]?.confidence,
    recommendations[0]?.confidence_pct
  ))
  const summary = String(firstPresent(
    neo.summary,
    neo.reason,
    neo.status,
    recommendations[0]?.reason,
    'NEO AI forwarded endpoint audit telemetry.'
  )).slice(0, 1000)

  return {
    hand: 'neo',
    source: 'neo_ai',
    agent_id: agent.id,
    hostname: agent.hostname,
    severity,
    priority: severity,
    confidence,
    action,
    recommended_command: action,
    summary,
    reason: summary,
    event: {
      source: 'neo_ai',
      sample_kind: telemetry.sampleKind,
      provider: firstPresent(neo.provider, neo.model, neo.model_name),
      event: firstPresent(neo.event, neo.kind, 'telemetry'),
      status: firstPresent(neo.status, null),
      report: firstPresent(neo.report, neo.report_path, neo.json_path),
      provider_errors: Array.isArray(neo.provider_errors) ? neo.provider_errors.slice(0, 8) : [],
      recommendation_count: recommendations.length,
      received_at: new Date().toISOString()
    },
    metrics: {
      health_score: asNumber(neo.health_score, readPath(neo, 'health.score')),
      recommendation_count: recommendations.length,
      features: isObject(neo.features) ? neo.features : {}
    },
    recommendations: recommendations.slice(0, 8)
  }
}

async function mirrorNeoAiTelemetryToOpenFang (fastify, { agent, telemetry }) {
  if (!isNeoAiTelemetry(telemetry)) return false

  const neo = extractNeoAiEnvelope(telemetry) || {}
  const payload = buildNeoAiOpenFangPayload(agent, telemetry, neo)
  await fastify.redis.setex(`openfang:tele:${agent.id}`, 3600, JSON.stringify(payload))

  await writeAuditLog(fastify.db, {
    actor_type: 'ai_system',
    action: 'neo_ai.telemetry',
    target_id: agent.id,
    target_type: 'agent',
    detail: {
      hostname: agent.hostname,
      severity: payload.severity,
      recommended_command: payload.recommended_command,
      confidence: payload.confidence,
      summary: payload.summary,
      sample_kind: telemetry.sampleKind
    }
  })

  if (['high', 'critical'].includes(payload.severity)) {
    await fastify.db.query(
      `INSERT INTO security_alerts
         (agent_id, tenant_id, source, severity, rule_name, description,
          ai_decision, ai_reason, ai_confidence, ai_model)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [
        agent.id,
        agent.tenant_id,
        'neo_ai',
        payload.severity,
        `NEO_${payload.severity.toUpperCase()}_TELEMETRY`,
        payload.summary,
        'MONITOR',
        'NEO forwarded endpoint debug, verbose, telemetry, or audit context to OpenFang.',
        payload.confidence / 100,
        payload.event.provider || 'NEO'
      ]
    )
  }

  fastify.log.info({
    agentId: agent.id,
    severity: payload.severity,
    action: payload.recommended_command
  }, '[NEO] mirrored telemetry to OpenFang context')
  return true
}

async function agentRoutes (fastify, opts) {

  // ─── REGISTER ───────────────────────────────────────────────────
  fastify.post('/register', async (req, reply) => {
    const { uuid, hostname, os, cpu, gpu, ram_mb, version } = req.body || {}
    if (!uuid || !hostname) return reply.code(400).send({ error: 'uuid and hostname required' })

    const requiredToken = (process.env.AGENT_ENROLLMENT_TOKEN || '').trim()
    if (requiredToken) {
      const providedToken = getEnrollmentToken(req)
      if (!tokensMatch(providedToken, requiredToken)) {
        fastify.log.warn({ ip: req.ip, hostname, uuid }, '[REGISTER] Enrollment token rejected')
        return reply.code(403).send({ error: 'Enrollment token required' })
      }
    }

    const tenantId = '00000000-0000-0000-0000-000000000001'
    const apiKey   = crypto.randomUUID()
    const apiHash  = crypto.createHash('sha256').update(apiKey).digest('hex')

    const { rows } = await fastify.db.query(
      `INSERT INTO agents (tenant_id, hostname, bios_uuid, api_key_hash, version, os, cpu, gpu, ram_mb, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'online')
       ON CONFLICT (bios_uuid) DO UPDATE SET
         hostname = EXCLUDED.hostname,
         version  = EXCLUDED.version,
         os       = EXCLUDED.os,
         cpu      = EXCLUDED.cpu,
         gpu      = EXCLUDED.gpu,
         ram_mb   = EXCLUDED.ram_mb,
         api_key_hash = EXCLUDED.api_key_hash,
         status   = 'online',
         last_seen = NOW()
       RETURNING id, hostname`,
      [tenantId, hostname, uuid, apiHash, version || '5.0.0', os, cpu, gpu, ram_mb]
    )

    fastify.log.info({ agentId: rows[0].id, hostname }, '[REGISTER] Agent registered/updated')
    await writeAuditLog(fastify.db, {
      actor_type: 'agent',
      action: 'agent.register',
      target_id: rows[0].id,
      target_type: 'agent',
      detail: { hostname, bios_uuid: uuid, version: version || '5.0.0' },
      ip: req.ip
    })
    return reply.code(201).send({ agent_id: rows[0].id, api_key: apiKey })
  })

  // ─── CHECK-IN (Poll for Commands) ───────────────────────────────
  fastify.post('/check-in', async (req, reply) => {
    const apiKey = req.headers['x-api-key']
    if (!apiKey) return reply.code(401).send({ error: 'Missing X-Api-Key' })

    const apiHash = crypto.createHash('sha256').update(apiKey).digest('hex')
    const { uuid, hostname, version, meta } = req.body || {}

    const { rows } = await fastify.db.query(
      `UPDATE agents SET
         last_seen   = NOW(),
         status      = 'online',
         hostname    = COALESCE($3, hostname),
         version     = COALESCE($4, version),
         cpu         = COALESCE($5::varchar, cpu),
         gpu         = COALESCE($6::varchar, gpu),
         ram_mb      = COALESCE($7::int, ram_mb),
         missed_checkins = 0
       WHERE bios_uuid = $1 AND api_key_hash = $2
       RETURNING id, hostname, tenant_id, version, os, cpu, gpu, ram_mb`,
      [uuid, apiHash, hostname, version, meta?.cpu, meta?.gpu, meta?.ram_mb ? parseInt(meta.ram_mb) : null]
    )

    if (!rows.length) return reply.code(401).send({ error: 'Unauthorized agent' })

    const agentId = rows[0].id
    try {
      await upsertHostBaseline(fastify, rows[0], req.body || {})
    } catch (err) {
      fastify.log.warn({ err, agentId }, '[TELEMETRY] host baseline upsert skipped')
    }

    // Get next pending command (highest priority first)
    const { rows: cmds } = await fastify.db.query(
      `UPDATE commands SET status='delivered', delivered_at=NOW()
       WHERE id = (
         SELECT c.id FROM commands c
         WHERE c.agent_id = $1
           AND c.status = 'pending'
           AND (
             c.safety_manifest_id IS NULL OR EXISTS (
               SELECT 1 FROM safety_manifests sm
               WHERE sm.id = c.safety_manifest_id AND sm.status = 'ACTIVE'
             )
           )
         ORDER BY c.priority ASC, c.created_at ASC
         LIMIT 1
         FOR UPDATE SKIP LOCKED
       )
       RETURNING id, type, args, signature, timeout_secs, safety_manifest_id`,
      [agentId]
    )

    if (cmds.length) {
      const cmd = cmds[0]
      if (cmd.safety_manifest_id) {
        await fastify.db.query(
          `UPDATE safety_manifest_targets
           SET status = 'DELIVERED', delivered_at = NOW()
           WHERE manifest_id = $1 AND agent_id = $2 AND command_id = $3`,
          [cmd.safety_manifest_id, agentId, cmd.id]
        )
      }
      fastify.log.info({ agentId, cmdId: cmd.id, type: cmd.type }, '[CHECKIN] Dispatching command')
      return reply.send({
        id:           cmd.id,
        cmd:          cmd.type,
        args:         cmd.args || {},
        safety_manifest: cmd.args?.safety_manifest || null,
        sig:          cmd.signature,
        timeout_secs: cmd.timeout_secs || 300
      })
    }

    return reply.send({})
  })

  // ─── TELEMETRY ──────────────────────────────────────────────────
  fastify.post('/telemetry', async (req, reply) => {
    const apiKey = req.headers['x-api-key']
    if (!apiKey) return reply.code(401).send({ error: 'Missing X-Api-Key' })

    const apiHash = crypto.createHash('sha256').update(apiKey).digest('hex')
    const t = req.body || {}

    // Resolve agent ID and tenant ID from UUID
    const { rows: agents } = await fastify.db.query(
      `SELECT id, tenant_id, hostname, os, cpu, gpu, ram_mb
       FROM agents WHERE bios_uuid = $1 AND api_key_hash = $2`,
      [t.uuid, apiHash]
    )
    if (!agents.length) return reply.code(401).send({ error: 'Unauthorized' })

    const agentId = agents[0].id
    const tenantId = agents[0].tenant_id
    const telemetry = normalizeTelemetryPayload(t)

    // Check IP against Nullclaw threat feed
    if (telemetry.publicIp) {
      const ioc = await nullclaw.checkIp(telemetry.publicIp)
      if (ioc && ioc.threat_level >= 7) {
        fastify.log.warn({ agentId, ip: telemetry.publicIp, ioc }, '[NULLCLAW] Malicious IP detected in telemetry')
        await telegram.criticalThreat(t.hostname, `Malicious IP: ${telemetry.publicIp}`, 'high')
      }
    }

    // Persist telemetry
    await fastify.db.query(
      `INSERT INTO telemetry
         (agent_id, tenant_id, ts, active_command_id, schema_version, sample_kind,
          cpu_pct, cpu_kernel_pct, cpu_clock_mhz,
          ram_used_mb, memory_available_mb, memory_committed_pct, memory_cache_faults_sec,
          disk_free_gb, disk_read_bytes_sec, disk_write_bytes_sec, disk_rw_bytes_sec,
          disk_queue_length, disk_time_pct, disk_latency_ms,
          net_rx_kbps, net_tx_kbps, network_bandwidth_bps, network_bytes_total_sec,
          network_output_queue_length, network_latency_ms, power_profile, on_battery,
          handle_count, thread_count, process_count,
          gpu_pct, gpu_temp_c, cpu_temp_c, gpu_name,
          cam_active, mic_active, camera_available, microphone_available, biometric_available,
          public_ip, geo_city, geo_country, geo_lat, geo_lon, location_label, location_detail,
          device_info, bugs, verbose_info, metrics, host_baseline, security_state, extra)
       VALUES ($1,$2,COALESCE($3::timestamptz,NOW()),$4::uuid,$5,$6,
          $7,$8,$9,
          $10,$11,$12,$13,
          $14,$15,$16,$17,
          $18,$19,$20,
          $21,$22,$23,$24,
          $25,$26,$27,$28,
          $29,$30,$31,
          $32,$33,$34,$35,
          $36,$37,$38,$39,$40,
          $41::inet,$42,$43,$44,$45,$46,$47,
          $48,$49,$50,$51,$52,$53,$54)`,
      [
        agentId, tenantId,
        telemetry.timestamp,
        telemetry.activeCommandId,
        telemetry.schemaVersion,
        telemetry.sampleKind,
        telemetry.cpuPct,
        telemetry.cpuKernelPct,
        telemetry.cpuClockMhz,
        telemetry.ramUsedMb,
        telemetry.memoryAvailableMb,
        telemetry.memoryCommittedPct,
        telemetry.memoryCacheFaultsSec,
        telemetry.diskFreeGb,
        telemetry.diskReadBytesSec,
        telemetry.diskWriteBytesSec,
        telemetry.diskRwBytesSec,
        telemetry.diskQueueLength,
        telemetry.diskTimePct,
        telemetry.diskLatencyMs,
        telemetry.netRxKbps,
        telemetry.netTxKbps,
        telemetry.networkBandwidthBps,
        telemetry.networkBytesTotalSec,
        telemetry.networkOutputQueueLength,
        telemetry.networkLatencyMs,
        telemetry.powerProfile,
        telemetry.onBattery,
        telemetry.handleCount,
        telemetry.threadCount,
        telemetry.processCount,
        telemetry.gpuPct,
        telemetry.gpuTempC,
        telemetry.cpuTempC,
        telemetry.gpuName,
        telemetry.camActive,
        telemetry.micActive,
        telemetry.cameraAvailable,
        telemetry.microphoneAvailable,
        telemetry.biometricAvailable,
        telemetry.publicIp,
        telemetry.geoCity,
        telemetry.geoCountry,
        telemetry.geoLat,
        telemetry.geoLon,
        telemetry.locationLabel,
        JSON.stringify(telemetry.locationDetail),
        JSON.stringify(telemetry.deviceInfo),
        JSON.stringify(telemetry.bugs),
        JSON.stringify(telemetry.verboseInfo),
        JSON.stringify(telemetry.metrics),
        JSON.stringify(telemetry.hostBaseline),
        JSON.stringify(telemetry.securityState),
        JSON.stringify(telemetry.extra)
      ]
    )

    // Cache latest telemetry in Redis for instant dashboard reads
    const cachePayload = {
      c:  telemetry.cpuPct,     cpu_pct: telemetry.cpuPct,
      r:  telemetry.ramUsedMb,  ram_used_mb: telemetry.ramUsedMb,
      d:  telemetry.diskFreeGb, disk_free_gb: telemetry.diskFreeGb,
      g:  telemetry.gpuPct,     gpu_pct: telemetry.gpuPct,
      gt: telemetry.gpuTempC,   gpu_temp_c: telemetry.gpuTempC,
      ct: telemetry.cpuTempC,   cpu_temp_c: telemetry.cpuTempC,
      rx: telemetry.netRxKbps,  net_rx_kbps: telemetry.netRxKbps,
      tx: telemetry.netTxKbps,  net_tx_kbps: telemetry.netTxKbps,
      gn: telemetry.gpuName,    l: telemetry.geoCity,
      cpu_kernel_pct: telemetry.cpuKernelPct,
      cpu_clock_mhz: telemetry.cpuClockMhz,
      memory_available_mb: telemetry.memoryAvailableMb,
      memory_committed_pct: telemetry.memoryCommittedPct,
      memory_cache_faults_sec: telemetry.memoryCacheFaultsSec,
      disk_read_bytes_sec: telemetry.diskReadBytesSec,
      disk_write_bytes_sec: telemetry.diskWriteBytesSec,
      disk_rw_bytes_sec: telemetry.diskRwBytesSec,
      disk_queue_length: telemetry.diskQueueLength,
      disk_time_pct: telemetry.diskTimePct,
      disk_latency_ms: telemetry.diskLatencyMs,
      network_bandwidth_bps: telemetry.networkBandwidthBps,
      network_bytes_total_sec: telemetry.networkBytesTotalSec,
      network_output_queue_length: telemetry.networkOutputQueueLength,
      network_latency_ms: telemetry.networkLatencyMs,
      power_profile: telemetry.powerProfile,
      on_battery: telemetry.onBattery,
      handle_count: telemetry.handleCount,
      thread_count: telemetry.threadCount,
      process_count: telemetry.processCount,
      cam_active: telemetry.camActive,
      mic_active: telemetry.micActive,
      camera_available: telemetry.cameraAvailable,
      microphone_available: telemetry.microphoneAvailable,
      biometric_available: telemetry.biometricAvailable,
      public_ip: telemetry.publicIp,
      geo_city: telemetry.geoCity,
      geo_country: telemetry.geoCountry,
      geo_lat: telemetry.geoLat,
      geo_lon: telemetry.geoLon,
      location_label: telemetry.locationLabel,
      location_detail: telemetry.locationDetail,
      device_info: telemetry.deviceInfo,
      security_state: telemetry.securityState,
      active_command_id: telemetry.activeCommandId,
      ts: new Date().toISOString()
    }
    await fastify.redis.setex(`agent:tele:${agentId}`, 60, JSON.stringify(cachePayload))

    // Update agent's public IP
    if (telemetry.publicIp) {
      await fastify.db.query(
        `UPDATE agents SET public_ip = $1::inet, ip_address = $1::inet WHERE id = $2`,
        [telemetry.publicIp, agentId]
      )
    }

    try {
      const [historyResult, alertsResult] = await Promise.all([
        fastify.db.query(
          `SELECT ts, cpu_pct, ram_used_mb, disk_free_gb, net_rx_kbps, net_tx_kbps,
                  gpu_pct, gpu_temp_c, cpu_temp_c, cpu_kernel_pct, memory_committed_pct,
                  disk_queue_length, network_latency_ms
           FROM telemetry
           WHERE agent_id = $1
           ORDER BY ts DESC
           LIMIT 96`,
          [agentId]
        ),
        fastify.db.query(
          `SELECT severity
           FROM security_alerts
           WHERE agent_id = $1 AND resolved = false AND created_at > NOW() - INTERVAL '24 hours'`,
          [agentId]
        )
      ])

      const insight = buildMlInsight({
        agent: agents[0],
        latestTelemetry: {
          ...t,
          cpu_pct: telemetry.cpuPct,
          ram_used_mb: telemetry.ramUsedMb,
          disk_free_gb: telemetry.diskFreeGb,
          net_rx_kbps: telemetry.netRxKbps,
          net_tx_kbps: telemetry.netTxKbps,
          gpu_pct: telemetry.gpuPct,
          gpu_temp_c: telemetry.gpuTempC,
          cpu_temp_c: telemetry.cpuTempC,
          memory_committed_pct: telemetry.memoryCommittedPct,
          disk_queue_length: telemetry.diskQueueLength
        },
        telemetryHistory: historyResult.rows.reverse(),
        alerts: alertsResult.rows
      })

      await fastify.redis.setex(`agent:ml:${agentId}`, 300, JSON.stringify(insight))
      await fastify.db.query(
        `INSERT INTO health_scores (agent_id, tenant_id, score, components)
         VALUES ($1, $2, $3, $4)`,
        [
          agentId,
          tenantId,
          insight.health_score,
          JSON.stringify({
            ...insight.components,
            anomaly_score: insight.anomaly_score,
            risk_level: insight.risk_level,
            model: insight.model
          })
        ]
      )
      await fastify.db.query(
        `UPDATE agents SET health_score = $1, health_reason = $2 WHERE id = $3`,
        [insight.health_score, insight.summary, agentId]
      )
    } catch (err) {
      fastify.log.warn({ err, agentId }, '[NeoCortex] telemetry scoring skipped')
    }

    try {
      await mirrorNeoAiTelemetryToOpenFang(fastify, { agent: agents[0], telemetry })
    } catch (err) {
      fastify.log.warn({ err, agentId }, '[NEO] telemetry mirror skipped')
    }

    return reply.send({ ok: true })
  })

  // ─── COMMAND REPORT ─────────────────────────────────────────────
  fastify.post('/report', async (req, reply) => {
    const apiKey = req.headers['x-api-key']
    if (!apiKey) return reply.code(401).send({ error: 'Missing X-Api-Key' })

    const { uuid, cmd_id, status, result } = req.body
    const apiHash = crypto.createHash('sha256').update(apiKey).digest('hex')

    // Validate ownership
    const { rows: agents } = await fastify.db.query(
      `SELECT a.id, a.hostname, c.type AS command_type, c.safety_manifest_id, c.tenant_id
       FROM agents a
       JOIN commands c ON c.agent_id = a.id
       WHERE a.bios_uuid = $1 AND a.api_key_hash = $2 AND c.id = $3`,
      [uuid, apiHash, cmd_id]
    )
    if (!agents.length) return reply.code(403).send({ error: 'Forbidden' })

    await fastify.db.query(
      `UPDATE commands
       SET status = $1, result = $2, completed_at = NOW(),
           started_at = COALESCE(started_at, NOW())
       WHERE id = $3`,
      [status, JSON.stringify(result || {}), cmd_id]
    )

    fastify.log.info({ cmdId: cmd_id, status }, '[REPORT] Command result received')

    const safetyManifestId = agents[0].safety_manifest_id
    const normalizedStatus = result?.rollback || result?.rolled_back
      ? 'ROLLBACK'
      : result?.rejected
        ? 'REJECTED'
        : status === 'timeout'
          ? 'TIMEOUT'
          : status === 'success'
            ? 'SUCCESS'
            : 'FAILED'

    try {
      await upsertCommandImpact(fastify, agents[0], cmd_id, safetyManifestId, normalizedStatus, result || {})
      await insertAgentSafetyState(fastify, agents[0], cmd_id, safetyManifestId, result || {})
    } catch (err) {
      fastify.log.warn({ err, cmdId: cmd_id }, '[TELEMETRY] command impact/safety persistence skipped')
    }

    if (safetyManifestId) {
      await fastify.db.query(
        `UPDATE safety_manifest_targets
         SET status = $1, reported_at = NOW(), failure_reason = $2, impact = $3
         WHERE manifest_id = $4 AND agent_id = $5 AND command_id = $6`,
        [
          normalizedStatus,
          normalizedStatus === 'SUCCESS' ? null : (result?.error || result?.reason || status),
          JSON.stringify(result?.impact || result || {}),
          safetyManifestId,
          agents[0].id,
          cmd_id
        ]
      )
      await insertSafetyEvent(fastify, {
        tenantId: agents[0].tenant_id,
        agentId: agents[0].id,
        commandId: cmd_id,
        manifestId: safetyManifestId,
        eventType: 'command.report',
        severity: normalizedStatus === 'SUCCESS' ? 'info' : 'high',
        payload: { status, normalized_status: normalizedStatus, result: result || {} }
      })

      const safetyDecision = await evaluateManifestAfterAgentReport(fastify, {
        manifestId: safetyManifestId,
        tenantId: agents[0].tenant_id,
        agentId: agents[0].id,
        commandId: cmd_id,
        normalizedStatus,
        reportStatus: status,
        result: result || {}
      })

      if (safetyDecision.action === 'revoked') {
        fastify.log.warn({
          manifestId: safetyManifestId,
          cmdId: cmd_id,
          agentId: agents[0].id,
          decision: safetyDecision.decision,
          reason: safetyDecision.reason
        }, '[SafetyAutoResponse] Safety manifest auto-revoked after agent report')

        await supabase.mirrorAuditLog({
          action: 'safety_manifest.auto_revoke',
          target_id: safetyManifestId,
          detail: {
            command_id: cmd_id,
            agent_id: agents[0].id,
            hostname: agents[0].hostname,
            normalized_status: normalizedStatus,
            reason: safetyDecision.reason,
            decision: safetyDecision.decision
          },
          created_at: new Date().toISOString()
        })
      }
    }

    // Mirror critical security scan results to Supabase
    const commandType = req.body.cmd_type || agents[0].command_type
    if (['THREAT_SCAN', 'INTEGRITY_SCAN', 'AUTOIMMUNE'].includes(commandType)) {
      await supabase.mirrorAuditLog({
        action: `cmd.${status}`,
        target_id: cmd_id,
        detail: { command_type: commandType, result },
        created_at: new Date().toISOString()
      })
    }

    return reply.send({ ok: true })
  })
}

module.exports = agentRoutes
