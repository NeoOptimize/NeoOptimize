'use strict'

// ═══════════════════════════════════════════════════════════════════
// DASHBOARD ROUTES v6.0 — Full Management API
// [BUG-S08 FIX] Telemetry query uses correct schema v6.0 columns
// [NEW] Scheduled tasks, alert rules, agent groups, health scores
// [NEW] Ollama AI analysis on security alerts
// ═══════════════════════════════════════════════════════════════════

const { z }             = require('zod')
const crypto            = require('crypto')
const net               = require('net')
const signing           = require('../security/signing')
const { writeAuditLog } = require('../middleware/security')
const { ollama, telegram, supabase, gemini, nullclaw, hf, e2b } = require('../lib/integrations')
const { buildMlInsight, buildFleetInsights } = require('../lib/mlAdvisor')
const { OPERATOR_BRIDGE_COMMANDS, buildOperatorBridgePlan, normalizeOperatorCommand } = require('../lib/operatorBridge')
const { buildReleaseReadiness } = require('../lib/releaseReadiness')
const {
  buildSafetyManifest,
  signSafetyManifest,
  attachSafetyManifestToArgs,
  evaluateAgentEligibility,
  selectCanaryTargets,
  evaluateCanary,
  globalKillSwitchActive
} = require('../lib/safetyManifest')

function signOrThrow (cmdId, cmdType, args) {
  return signing.signCommand(cmdId, cmdType, args)
}

// ─── Schemas ─────────────────────────────────────────────────────
const ALL_COMMANDS = [
  // Optimization & Maintenance
  'OPTIMIZE', 'CLEAN', 'UPDATES', 'PRIVACY', 'POWER', 'SERVICES',
  'APP_MANAGER', 'SYSTEM_REPAIR', 'SYSTEM_DIAGNOSTICS', 'BACKUP_OPS', 'PERFORMANCE',
  'DEEP_SCAN', 'NEOUPDATE',
  // Security Layers
  'SECURITY_SCAN', 'NETWORK_TEST', 'THREAT_SCAN', 'AUTOIMMUNE', 'INTEGRITY_SCAN',
  // Hardware Telemetry & Inventory
  'COLLECT', 'SYSINFO',
  // Misc
  'PING'
  // NOTE: GRANT_PERMISSIONS removed — this is a System Optimizer, not RMM
]

const CommandSchema = z.object({
  agent_id:  z.string().uuid(),
  type:      z.enum(ALL_COMMANDS),
  args:      z.record(z.unknown()).optional().default({}),
  priority:  z.number().int().min(1).max(10).optional().default(5)
})

const BulkCommandSchema = z.object({
  agent_ids: z.array(z.string().uuid()).min(1).max(100),
  type:      CommandSchema.shape.type,
  args:      z.record(z.unknown()).optional().default({}),
  priority:  z.number().int().min(1).max(10).optional().default(5)
})

const UserCreateSchema = z.object({
  email:     z.string().email().max(255),
  password:  z.string().min(10).max(128),
  role:      z.enum(['admin', 'operator', 'viewer']).default('operator')
})

const IdParamSchema = z.object({ id: z.string().uuid() })
const NumericIdParamSchema = z.object({ id: z.coerce.number().int().positive().max(2147483647) })
const PaginationSchema = z.object({
  limit:  z.coerce.number().int().min(1).max(200).default(50),
  offset: z.coerce.number().int().min(0).max(100000).default(0)
})
const AgentListQuerySchema = PaginationSchema.extend({
  status: z.enum(['online', 'offline', 'uninstalled']).optional(),
  search: z.string().trim().max(120).optional()
})
const CommandListQuerySchema = PaginationSchema.extend({
  agent_id: z.string().uuid().optional(),
  status:   z.enum(['pending', 'delivered', 'running', 'success', 'failed', 'timeout']).optional()
})
const AuditLogQuerySchema = PaginationSchema.extend({
  limit: z.coerce.number().int().min(1).max(500).default(100)
})
const AuditDeleteQuerySchema = z.object({
  older_than_days: z.coerce.number().int().min(1).max(3650).optional()
})
const TelemetryQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(1000).default(100),
  hours: z.coerce.number().int().min(1).max(720).default(24)
})
const AlertListQuerySchema = PaginationSchema.extend({
  resolved: z.enum(['true', 'false']).default('false').transform(v => v === 'true')
})
const UserPatchSchema = z.object({
  role:      z.enum(['admin', 'operator', 'viewer']).optional(),
  is_active: z.coerce.boolean().optional()
}).strict()
const ScheduledTaskSchema = z.object({
  name:        z.string().trim().min(1).max(120),
  description: z.string().trim().max(500).optional().nullable(),
  agent_id:    z.string().uuid().optional().nullable(),
  group_id:    z.string().uuid().optional().nullable(),
  target_all:  z.coerce.boolean().optional().default(false),
  cmd_type:    z.enum(ALL_COMMANDS),
  cmd_args:    z.record(z.unknown()).optional().default({}),
  priority:    z.coerce.number().int().min(1).max(10).optional().default(5),
  cron_expr:   z.string().trim().min(3).max(120).regex(/^[\w\s*/?,#L.-]+$/),
  timezone:    z.string().trim().min(1).max(64).regex(/^[A-Za-z0-9_/\-+]+$/).optional().default('UTC')
}).strict()
const AlertRuleSchema = z.object({
  name:            z.string().trim().min(1).max(120),
  condition:       z.record(z.unknown()),
  action_cmd:      z.enum(ALL_COMMANDS).optional().nullable(),
  notify_telegram: z.coerce.boolean().optional().default(false),
  cooldown_min:    z.coerce.number().int().min(1).max(10080).optional().default(60)
}).strict()
const AlertRulePatchSchema = z.object({
  is_active: z.coerce.boolean()
}).strict()
const AgentGroupSchema = z.object({
  name:        z.string().trim().min(1).max(80),
  description: z.string().trim().max(300).optional().nullable(),
  color:       z.string().trim().regex(/^#[0-9A-Fa-f]{6}$/).optional().default('#00e57a')
}).strict()
const AgentGroupAssignSchema = z.object({
  group_id: z.string().uuid().optional().nullable()
}).strict()
const SeveritySchema = z.string().trim().max(16).transform(v => v.toLowerCase())
  .refine(v => ['info', 'low', 'medium', 'high', 'critical'].includes(v), 'invalid severity')
const SafeIpString = z.string().trim().min(3).max(64).regex(/^[A-Za-z0-9:.%-]+$/)
const SecurityAlertIngestSchema = z.object({
  agent_id:     z.string().uuid(),
  severity:     SeveritySchema,
  rule_name:    z.string().trim().max(160).optional().nullable(),
  description:  z.string().trim().max(2000).optional().nullable(),
  src_ip:       SafeIpString.optional().nullable(),
  process_name: z.string().trim().max(260).optional().nullable()
}).strict()
const OpenFangCommandSchema = z.object({
  agent_id: z.string().uuid(),
  type:     z.enum(ALL_COMMANDS),
  args:     z.record(z.unknown()).optional().default({}),
  priority: z.coerce.number().int().min(1).max(10).optional().default(10)
}).strict()
const OpenFangTelemetrySchema = z.object({
  agent_id: z.string().uuid().optional().nullable(),
  hand: z.string().trim().max(40).regex(/^[A-Za-z0-9_.-]+$/).optional().default('guardian'),
  severity: SeveritySchema.optional().default('info'),
  summary: z.string().trim().max(2000).optional().default(''),
  action: z.string().trim().max(50).optional().nullable(),
  recommended_command: z.string().trim().max(50).optional().nullable(),
  confidence: z.coerce.number().min(0).max(100).optional().nullable(),
  event: z.record(z.unknown()).optional().default({}),
  metrics: z.record(z.unknown()).optional().default({})
}).strict()
const OperatorBridgeDispatchSchema = z.object({
  command: z.enum([...OPERATOR_BRIDGE_COMMANDS]),
  reason: z.string().trim().max(1000).optional().default('Operator bridge dispatch'),
  args: z.record(z.unknown()).optional().default({}),
  priority: z.coerce.number().int().min(1).max(10).optional().default(5)
}).strict()
const SafetyRevokeSchema = z.object({
  reason: z.string().trim().min(1).max(1000).default('Operator revoked safety manifest')
}).strict()
const SafetyManifestQuerySchema = PaginationSchema.extend({
  status: z.enum(['ACTIVE', 'PAUSED', 'REVOKED', 'COMPLETED']).optional(),
  risk_level: z.enum(['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']).optional()
})
const ThreatIpSchema = z.object({ ip: SafeIpString }).strict()
const ThreatHashSchema = z.object({ hash: z.string().trim().regex(/^[A-Fa-f0-9]{32,128}$/) }).strict()
const E2BAnalyzeSchema = z.object({ code: z.string().min(1).max(20000) }).strict()

function parseRequest (schema, value, reply) {
  try {
    return schema.parse(value || {})
  } catch (err) {
    reply.code(400).send({
      error: 'Validation error',
      details: err.errors?.slice(0, 5).map(e => ({ path: e.path.join('.'), message: e.message }))
    })
    return null
  }
}

function parseIdParam (req, reply) {
  const params = parseRequest(IdParamSchema, req.params, reply)
  return params?.id || null
}

function parseNumericIdParam (req, reply) {
  const params = parseRequest(NumericIdParamSchema, req.params, reply)
  return params?.id || null
}

function safeJsonParse (value, fallback = null) {
  if (!value) return fallback
  if (typeof value === 'object') return value
  try { return JSON.parse(value) } catch { return fallback }
}

function normalizeIp (value) {
  return String(value || '').trim().replace(/^::ffff:/, '')
}

function isPublicIp (value) {
  const ip = normalizeIp(value)
  const family = net.isIP(ip)
  if (!family) return false

  if (family === 4) {
    const parts = ip.split('.').map(Number)
    if (parts[0] === 10) return false
    if (parts[0] === 127) return false
    if (parts[0] === 169 && parts[1] === 254) return false
    if (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) return false
    if (parts[0] === 192 && parts[1] === 168) return false
    return true
  }

  const lower = ip.toLowerCase()
  return !(lower === '::1' || lower.startsWith('fc') || lower.startsWith('fd') || lower.startsWith('fe80:'))
}

async function loadOperatorBridgeContext (fastify, tenantId, agentId) {
  const { rows: agentRows } = await fastify.db.query(
    `SELECT * FROM agents WHERE id = $1 AND tenant_id = $2`,
    [agentId, tenantId]
  )
  if (!agentRows.length) return null

  const agent = agentRows[0]
  const [telemetryResult, alertsResult, recentCommandsResult, cachedTele, cachedMl, openfangCached] = await Promise.all([
    fastify.db.query(
      `SELECT ts, cpu_pct, ram_used_mb, disk_free_gb, net_rx_kbps, net_tx_kbps,
              gpu_pct, gpu_temp_c, cpu_temp_c, public_ip
       FROM telemetry
       WHERE agent_id = $1
       ORDER BY ts DESC
       LIMIT 96`,
      [agentId]
    ),
    fastify.db.query(
      `SELECT severity, rule_name, description, source, ai_decision, ai_confidence, created_at
       FROM security_alerts
       WHERE agent_id = $1 AND resolved = false AND created_at > NOW() - INTERVAL '24 hours'
       ORDER BY created_at DESC
       LIMIT 20`,
      [agentId]
    ),
    fastify.db.query(
      `SELECT id, type, status, priority, created_at, completed_at
       FROM commands
       WHERE agent_id = $1
       ORDER BY created_at DESC
       LIMIT 12`,
      [agentId]
    ),
    fastify.redis.get(`agent:tele:${agentId}`),
    fastify.redis.get(`agent:ml:${agentId}`),
    fastify.redis.get(`openfang:tele:${agentId}`)
  ])

  const history = telemetryResult.rows.reverse()
  const latestTelemetry = safeJsonParse(cachedTele, null) || history[history.length - 1] || {}
  const cachedInsight = safeJsonParse(cachedMl, null)
  const insight = cachedInsight || buildMlInsight({
    agent,
    latestTelemetry,
    telemetryHistory: history,
    alerts: alertsResult.rows
  })

  const openfangTelemetry = safeJsonParse(openfangCached, null)
  const candidateIp = normalizeIp(agent.public_ip || agent.ip_address || latestTelemetry.public_ip)
  let nullclawIp = null
  if (isPublicIp(candidateIp)) {
    try { nullclawIp = await nullclaw.checkIp(candidateIp) } catch { nullclawIp = null }
  }

  return {
    agent,
    latestTelemetry,
    telemetryHistory: history,
    alerts: alertsResult.rows,
    recentCommands: recentCommandsResult.rows,
    insight,
    openfangTelemetry,
    nullclawIp,
    nullclawTargetIp: isPublicIp(candidateIp) ? candidateIp : null
  }
}

function isSafetyBypassCommand (type) {
  return ['PING', 'COLLECT', 'SYSINFO', 'SYSTEM_DIAGNOSTICS', 'NETWORK_TEST'].includes(String(type || '').toUpperCase())
}

async function insertSafetyEvent (fastify, { tenantId, agentId = null, commandId = null, manifestId = null, eventType, severity = 'info', payload = {} }) {
  await fastify.db.query(
    `INSERT INTO safety_events (manifest_id, command_id, tenant_id, agent_id, event_type, severity, payload)
     VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [manifestId, commandId, tenantId, agentId, eventType, severity, JSON.stringify(payload || {})]
  )
}

async function createSafeCommand (fastify, {
  tenantId,
  agent,
  type,
  args = {},
  priority = 5,
  issuedBy = null,
  issuedByType = 'user',
  source = 'NeoOptimize.RMM',
  dryRun = false
}) {
  const commandType = String(type || '').toUpperCase()
  if (globalKillSwitchActive() && !isSafetyBypassCommand(commandType)) {
    const err = new Error('Global safety kill switch is active')
    err.statusCode = 423
    throw err
  }

  const cmdId = crypto.randomUUID()
  const manifest = buildSafetyManifest({ commandId: cmdId, type: commandType, args, agent, source, dryRun })
  const eligibility = evaluateAgentEligibility(agent, manifest)
  if (!eligibility.ok) {
    const err = new Error(`Safety gate rejected command: ${eligibility.reason}`)
    err.statusCode = 412
    err.safetyReason = eligibility.reason
    throw err
  }

  const signedManifest = signSafetyManifest(manifest)
  const safeArgs = attachSafetyManifestToArgs(args, signedManifest)
  const sig = signOrThrow(cmdId, commandType, safeArgs)
  const canary = manifest.execution_control.canary_policy
  const bakeUntil = canary.enabled
    ? new Date(Date.now() + (canary.bake_time_minutes * 60 * 1000))
    : null

  const { rows: manifestRows } = await fastify.db.query(
    `INSERT INTO safety_manifests
       (tenant_id, command_id, command_type, version, manifest, manifest_sha256, signature,
        status, risk_level, canary_phase, target_percentage, bake_until, created_by, created_by_type)
     VALUES ($1,$2,$3,$4,$5,$6,$7,'ACTIVE',$8,$9,$10,$11,$12,$13)
     RETURNING id`,
    [
      tenantId,
      cmdId,
      commandType,
      manifest.version,
      JSON.stringify(manifest),
      signedManifest.manifest_sha256,
      signedManifest.signature,
      manifest.policy_gate.risk_level,
      canary.current_phase,
      canary.target_percentage,
      bakeUntil,
      issuedBy,
      issuedByType
    ]
  )

  const manifestId = manifestRows[0].id
  const { rows } = await fastify.db.query(
    `INSERT INTO commands
       (id, agent_id, tenant_id, type, args, signature, priority, issued_by, issued_by_type, timeout_secs, safety_manifest_id)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
     RETURNING id`,
    [
      cmdId,
      agent.id,
      tenantId,
      commandType,
      JSON.stringify(safeArgs),
      sig,
      priority,
      issuedBy,
      issuedByType,
      manifest.execution_control.timeout_seconds,
      manifestId
    ]
  )

  await fastify.db.query(
    `INSERT INTO safety_manifest_targets (manifest_id, tenant_id, agent_id, command_id, phase, status)
     VALUES ($1,$2,$3,$4,$5,'QUEUED')`,
    [manifestId, tenantId, agent.id, cmdId, canary.current_phase]
  )

  await insertSafetyEvent(fastify, {
    tenantId,
    agentId: agent.id,
    commandId: cmdId,
    manifestId,
    eventType: 'manifest.created',
    payload: { command_type: commandType, risk_level: manifest.policy_gate.risk_level, source }
  })

  return {
    commandId: rows[0].id,
    manifestId,
    signedManifest,
    riskLevel: manifest.policy_gate.risk_level,
    canaryPhase: canary.current_phase
  }
}

function sendSafetyError (reply, err) {
  if ([412, 423].includes(err?.statusCode)) {
    return reply.code(err.statusCode).send({
      error: err.message,
      reason: err.safetyReason || null
    })
  }
  throw err
}

async function dashboardRoutes (fastify, opts) {
  const auth = { preHandler: fastify.authenticate }

  // ─── STATS ──────────────────────────────────────────────────────
  fastify.get('/stats', auth, async (req, reply) => {
    const tenantId = req.user.tenantId

    const [agentStats, cmdStats, onlineCount] = await Promise.all([
      fastify.db.query(
        `SELECT status, COUNT(*)::int AS count FROM agents WHERE tenant_id = $1 GROUP BY status`,
        [tenantId]
      ),
      fastify.db.query(
        `SELECT status, COUNT(*)::int AS count FROM commands
         WHERE agent_id IN (SELECT id FROM agents WHERE tenant_id = $1)
         AND created_at > NOW() - INTERVAL '24 hours'
         GROUP BY status`,
        [tenantId]
      ),
      fastify.db.query(
        `SELECT COUNT(*)::int AS count FROM agents
         WHERE tenant_id = $1 AND last_seen > NOW() - INTERVAL '2 minutes'`,
        [tenantId]
      )
    ])

    return reply.send({
      agents:    agentStats.rows,
      commands:  cmdStats.rows,
      online_now: onlineCount.rows[0]?.count || 0
    })
  })

  // ─── PUBLIC RELEASE READINESS GATE ───────────────────────────────
  fastify.get('/release/readiness', auth, async (req, reply) => {
    const report = await buildReleaseReadiness(fastify)
    return reply.send(report)
  })

  // ─── AGENT LIST ──────────────────────────────────────────────────
  fastify.get('/agents', auth, async (req, reply) => {
    const tenantId = req.user.tenantId
    const queryInput = parseRequest(AgentListQuerySchema, req.query, reply)
    if (!queryInput) return
    const { status, search, limit, offset } = queryInput

    let query = `
      SELECT a.*, 
        CASE
          WHEN a.status = 'uninstalled' THEN 'uninstalled'
          WHEN a.last_seen > NOW() - INTERVAL '2 minutes' THEN 'online'
          ELSE 'offline'
        END AS live_status
      FROM agents a
      WHERE a.tenant_id = $1`
    const params = [tenantId]

    if (status) {
      params.push(status)
      query += ` AND a.status = $${params.length}`
    }
    if (search) {
      params.push(`%${search.replace(/[%_]/g, '\\$&')}%`)
      query += ` AND (a.hostname ILIKE $${params.length} OR a.ip_address::text ILIKE $${params.length})`
    }

    query += ` ORDER BY a.last_seen DESC NULLS LAST LIMIT $${params.push(limit)} OFFSET $${params.push(offset)}`

    const { rows } = await fastify.db.query(query, params)

    // Enrich with cached telemetry from Redis
    const enriched = await Promise.all(rows.map(async (agent) => {
      const tele = await fastify.redis.get(`agent:tele:${agent.id}`)
      return { ...agent, tele: tele ? JSON.parse(tele) : null }
    }))

    return reply.send({ agents: enriched, total: enriched.length })
  })

  // ─── AGENT DETAIL ───────────────────────────────────────────────
  fastify.get('/agents/:id', auth, async (req, reply) => {
    const tenantId = req.user.tenantId
    const agentId = parseIdParam(req, reply)
    if (!agentId) return
    const { rows } = await fastify.db.query(
      `SELECT * FROM agents WHERE id = $1 AND tenant_id = $2`,
      [agentId, tenantId]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Agent not found' })

    // Get recent commands
    const { rows: cmds } = await fastify.db.query(
      `SELECT id, type, status, created_at, completed_at, result
       FROM commands WHERE agent_id = $1
       ORDER BY created_at DESC LIMIT 20`,
      [agentId]
    )

    const tele = await fastify.redis.get(`agent:tele:${agentId}`)
    return reply.send({
      ...rows[0],
      tele: tele ? JSON.parse(tele) : null,
      recent_commands: cmds
    })
  })

  // ─── GEMINI AI SYSTEM ANALYSIS ─────────────────────────────────────
  fastify.post('/agents/:id/gemini-analysis', auth, async (req, reply) => {
    const tenantId = req.user.tenantId
    const agentId = parseIdParam(req, reply)
    if (!agentId) return
    const { rows: agentRows } = await fastify.db.query(
      `SELECT * FROM agents WHERE id = $1 AND tenant_id = $2`,
      [agentId, tenantId]
    )
    if (!agentRows.length) return reply.code(404).send({ error: 'Agent not found' })

    const tele = await fastify.redis.get(`agent:tele:${agentId}`)
    const telemetry = tele ? JSON.parse(tele) : {}

    const analysis = await gemini.analyzeWindowsSystem(agentRows[0], telemetry)
    if (!analysis) return reply.code(500).send({ error: 'Gemini analysis failed or disabled' })
    
    // Save the analysis to audit logs
    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub, actor_type: 'user',
      action: 'agent.gemini_analysis', target_id: agentId, target_type: 'agent',
      detail: { status: analysis.status, score: analysis.score }, ip: req.ip
    })

    return reply.send({ analysis })
  })

  // ─── NEO CORTEX LOCAL ML INSIGHT ────────────────────────────────
  fastify.get('/agents/:id/ml-insight', auth, async (req, reply) => {
    const tenantId = req.user.tenantId
    const agentId = parseIdParam(req, reply)
    if (!agentId) return
    const { rows: agentRows } = await fastify.db.query(
      `SELECT * FROM agents WHERE id = $1 AND tenant_id = $2`,
      [agentId, tenantId]
    )
    if (!agentRows.length) return reply.code(404).send({ error: 'Agent not found' })

    const [telemetryResult, alertsResult, cachedTele, cachedMl] = await Promise.all([
      fastify.db.query(
        `SELECT ts, cpu_pct, ram_used_mb, disk_free_gb, net_rx_kbps, net_tx_kbps,
                gpu_pct, gpu_temp_c, cpu_temp_c
         FROM telemetry
         WHERE agent_id = $1
         ORDER BY ts DESC
         LIMIT 96`,
        [agentId]
      ),
      fastify.db.query(
        `SELECT severity, rule_name, created_at
         FROM security_alerts
         WHERE agent_id = $1 AND resolved = false AND created_at > NOW() - INTERVAL '24 hours'
         ORDER BY created_at DESC`,
        [agentId]
      ),
      fastify.redis.get(`agent:tele:${agentId}`),
      fastify.redis.get(`agent:ml:${agentId}`)
    ])

    const history = telemetryResult.rows.reverse()
    const latestTelemetry = cachedTele
      ? JSON.parse(cachedTele)
      : history[history.length - 1] || {}
    const cached = cachedMl ? JSON.parse(cachedMl) : null
    const insight = buildMlInsight({
      agent: agentRows[0],
      latestTelemetry,
      telemetryHistory: history,
      alerts: alertsResult.rows
    })

    return reply.send({
      insight,
      cached,
      timestamp: new Date().toISOString()
    })
  })

  // ─── OPERATOR BRIDGE — NeoOptimize ↔ RMM ↔ OpenFang/NullClaw ─────
  fastify.get('/agents/:id/operator-bridge', auth, async (req, reply) => {
    const tenantId = req.user.tenantId
    const agentId = parseIdParam(req, reply)
    if (!agentId) return

    const context = await loadOperatorBridgeContext(fastify, tenantId, agentId)
    if (!context) return reply.code(404).send({ error: 'System not found' })

    const plan = buildOperatorBridgePlan(context)
    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub,
      actor_type: 'user',
      action: 'operator_bridge.plan',
      target_id: agentId,
      target_type: 'agent',
      detail: {
        model: plan.model,
        risk_level: plan.risk_level,
        health_score: plan.health_score,
        recommended_commands: plan.recommended_commands.map(item => item.command),
        sources: plan.sources
      },
      ip: req.ip
    })

    return reply.send({
      bridge: {
        status: 'ready',
        mode: 'advisory_dispatch_ready',
        dispatch_endpoint: `/api/v1/dashboard/agents/${agentId}/operator-bridge/dispatch`,
        auto_dispatch: false,
        requires_confirmation: true
      },
      agent: {
        id: context.agent.id,
        hostname: context.agent.hostname,
        status: context.agent.status,
        live_status: context.agent.last_seen && new Date(context.agent.last_seen).getTime() > Date.now() - 120000 ? 'online' : 'offline',
        os: context.agent.os,
        version: context.agent.version,
        health_score: context.agent.health_score,
        last_seen: context.agent.last_seen
      },
      telemetry: context.latestTelemetry,
      insight: context.insight,
      openfang: context.openfangTelemetry,
      nullclaw: {
        target_ip: context.nullclawTargetIp,
        result: context.nullclawIp
      },
      recent_commands: context.recentCommands,
      plan,
      timestamp: new Date().toISOString()
    })
  })

  fastify.post('/agents/:id/operator-bridge/dispatch', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const tenantId = req.user.tenantId
    const agentId = parseIdParam(req, reply)
    if (!agentId) return

    const body = parseRequest(OperatorBridgeDispatchSchema, req.body, reply)
    if (!body) return

    const command = normalizeOperatorCommand(body.command)
    if (!command) return reply.code(400).send({ error: 'Unsupported operator bridge command' })

    const { rows: agents } = await fastify.db.query(
      `SELECT id, hostname, version, os, tags, health_score FROM agents WHERE id = $1 AND tenant_id = $2`,
      [agentId, tenantId]
    )
    if (!agents.length) return reply.code(404).send({ error: 'System not found' })

    const args = {
      ...body.args,
      source: 'NeoOptimize.OperatorBridge',
      reason: body.reason,
      bridge_model: 'neo-operator-bridge-v1'
    }
    let created
    try {
      created = await createSafeCommand(fastify, {
        tenantId,
        agent: agents[0],
        type: command,
        args,
        priority: body.priority,
        issuedBy: req.user.sub,
        issuedByType: 'user',
        source: 'NeoOptimize.OperatorBridge'
      })
    } catch (err) {
      return sendSafetyError(reply, err)
    }

    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub,
      actor_type: 'user',
      action: 'operator_bridge.dispatch',
      target_id: agentId,
      target_type: 'agent',
      detail: {
        cmd_type: command,
        cmd_id: created.commandId,
        safety_manifest_id: created.manifestId,
        risk_level: created.riskLevel,
        priority: body.priority,
        reason: body.reason
      },
      ip: req.ip
    })

    return reply.code(201).send({
      ok: true,
      cmd_id: created.commandId,
      safety_manifest_id: created.manifestId,
      risk_level: created.riskLevel,
      canary_phase: created.canaryPhase,
      source: 'operator_bridge',
      command
    })
  })

  // ─── DELETE AGENT ───────────────────────────────────────────────
  fastify.delete('/agents/:id', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const agentId = parseIdParam(req, reply)
    if (!agentId) return
    const { rows } = await fastify.db.query(
      `DELETE FROM agents WHERE id = $1 AND tenant_id = $2 RETURNING id, hostname`,
      [agentId, req.user.tenantId]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Agent not found' })
    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub, actor_type: 'user',
      action: 'agent.delete', target_id: agentId, target_type: 'agent',
      detail: { hostname: rows[0].hostname }, ip: req.ip
    })
    return reply.send({ ok: true })
  })

  // ─── SEND COMMAND ───────────────────────────────────────────────
  fastify.post('/commands', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const body = CommandSchema.parse(req.body)

    // Verify agent belongs to tenant
    const { rows: agents } = await fastify.db.query(
      `SELECT id, hostname, version, os, tags, health_score FROM agents WHERE id = $1 AND tenant_id = $2`,
      [body.agent_id, req.user.tenantId]
    )
    if (!agents.length) return reply.code(404).send({ error: 'Agent not found' })

    let created
    try {
      created = await createSafeCommand(fastify, {
        tenantId: req.user.tenantId,
        agent: agents[0],
        type: body.type,
        args: body.args,
        priority: body.priority,
        issuedBy: req.user.sub,
        issuedByType: 'user',
        source: 'NeoOptimize.Dashboard'
      })
    } catch (err) {
      return sendSafetyError(reply, err)
    }

    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub, actor_type: 'user',
      action: 'command.issued', target_id: body.agent_id, target_type: 'agent',
      detail: {
        cmd_type: body.type,
        cmd_id: created.commandId,
        safety_manifest_id: created.manifestId,
        risk_level: created.riskLevel
      }, ip: req.ip
    })

    return reply.code(201).send({
      ok: true,
      cmd_id: created.commandId,
      safety_manifest_id: created.manifestId,
      risk_level: created.riskLevel,
      canary_phase: created.canaryPhase
    })
  })

  // ─── BULK COMMAND ───────────────────────────────────────────────
  fastify.post('/commands/bulk', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const body = BulkCommandSchema.parse(req.body)

    // Verify ALL agents belong to tenant
    const { rows: agents } = await fastify.db.query(
      `SELECT id, hostname, version, os, tags, health_score FROM agents WHERE id = ANY($1::uuid[]) AND tenant_id = $2`,
      [body.agent_ids, req.user.tenantId]
    )
    if (agents.length !== body.agent_ids.length) return reply.code(400).send({ error: 'One or more agents not found' })

    const targetAgents = selectCanaryTargets(agents, body.type)
    const targetIds = new Set(targetAgents.map(agent => agent.id))
    const heldAgentIds = agents.filter(agent => !targetIds.has(agent.id)).map(agent => agent.id)

    const issued = []
    for (const agent of targetAgents) {
      try {
        issued.push(await createSafeCommand(fastify, {
          tenantId: req.user.tenantId,
          agent,
          type: body.type,
          args: body.args,
          priority: body.priority,
          issuedBy: req.user.sub,
          issuedByType: 'user',
          source: 'NeoOptimize.DashboardBulk'
        }))
      } catch (err) {
        return sendSafetyError(reply, err)
      }
    }

    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub, actor_type: 'user',
      action: 'command.bulk',
      detail: {
        cmd_type: body.type,
        issued_count: issued.length,
        held_count: heldAgentIds.length,
        canary_enforced: heldAgentIds.length > 0
      }, ip: req.ip
    })

    return reply.code(201).send({
      ok: true,
      issued: issued.length,
      held: heldAgentIds.length,
      held_agent_ids: heldAgentIds,
      canary_enforced: heldAgentIds.length > 0,
      cmd_ids: issued.map(item => item.commandId),
      safety_manifest_ids: issued.map(item => item.manifestId)
    })
  })

  // ─── COMMAND HISTORY ─────────────────────────────────────────────
  fastify.get('/commands', auth, async (req, reply) => {
    const queryInput = parseRequest(CommandListQuerySchema, req.query, reply)
    if (!queryInput) return
    const { agent_id, status, limit, offset } = queryInput

    let query = `
      SELECT c.id, c.type, c.status, c.priority, c.created_at, c.delivered_at,
             c.completed_at, c.result, a.hostname, u.email as issued_by_email
      FROM commands c
      JOIN agents a ON c.agent_id = a.id
      LEFT JOIN users u ON c.issued_by = u.id
      WHERE a.tenant_id = $1`
    const params = [req.user.tenantId]

    if (agent_id) { params.push(agent_id); query += ` AND c.agent_id = $${params.length}` }
    if (status)   { params.push(status);   query += ` AND c.status = $${params.length}` }

    query += ` ORDER BY c.created_at DESC LIMIT $${params.push(limit)} OFFSET $${params.push(offset)}`

    const { rows } = await fastify.db.query(query, params)
    return reply.send({ commands: rows })
  })

  // ─── COMMAND SAFETY MANIFESTS ────────────────────────────────────
  fastify.get('/safety/manifests', auth, async (req, reply) => {
    const queryInput = parseRequest(SafetyManifestQuerySchema, req.query, reply)
    if (!queryInput) return
    const { status, risk_level: riskLevel, limit, offset } = queryInput

    let query = `
      SELECT id, command_id, command_type, version, status, risk_level, canary_phase,
             target_percentage, bake_until, failure_rate, created_at, revoked_at, completed_at
      FROM safety_manifests
      WHERE tenant_id = $1`
    const params = [req.user.tenantId]

    if (status) { params.push(status); query += ` AND status = $${params.length}` }
    if (riskLevel) { params.push(riskLevel); query += ` AND risk_level = $${params.length}` }
    query += ` ORDER BY created_at DESC LIMIT $${params.push(limit)} OFFSET $${params.push(offset)}`

    const { rows } = await fastify.db.query(query, params)
    return reply.send({ manifests: rows })
  })

  fastify.get('/safety/manifests/:id', auth, async (req, reply) => {
    const manifestId = parseIdParam(req, reply)
    if (!manifestId) return
    const { rows } = await fastify.db.query(
      `SELECT * FROM safety_manifests WHERE id = $1 AND tenant_id = $2`,
      [manifestId, req.user.tenantId]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Safety manifest not found' })

    const [targets, events] = await Promise.all([
      fastify.db.query(
        `SELECT smt.*, a.hostname
         FROM safety_manifest_targets smt
         JOIN agents a ON a.id = smt.agent_id
         WHERE smt.manifest_id = $1 AND smt.tenant_id = $2
         ORDER BY smt.assigned_at DESC`,
        [manifestId, req.user.tenantId]
      ),
      fastify.db.query(
        `SELECT *
         FROM safety_events
         WHERE manifest_id = $1 AND tenant_id = $2
         ORDER BY created_at DESC
         LIMIT 100`,
        [manifestId, req.user.tenantId]
      )
    ])

    return reply.send({ manifest: rows[0], targets: targets.rows, events: events.rows })
  })

  fastify.post('/safety/manifests/:id/revoke', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const manifestId = parseIdParam(req, reply)
    if (!manifestId) return
    const body = parseRequest(SafetyRevokeSchema, req.body, reply)
    if (!body) return

    const { rows } = await fastify.db.query(
      `UPDATE safety_manifests
       SET status = 'REVOKED', revoked_at = NOW(), revoked_by = $3, revoke_reason = $4
       WHERE id = $1 AND tenant_id = $2
       RETURNING id, command_id, command_type`,
      [manifestId, req.user.tenantId, req.user.sub, body.reason]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Safety manifest not found' })

    await fastify.db.query(
      `UPDATE commands
       SET status = 'failed',
           completed_at = COALESCE(completed_at, NOW()),
           result = jsonb_build_object('revoked', true, 'reason', $3)
       WHERE safety_manifest_id = $1 AND tenant_id = $2 AND status = 'pending'`,
      [manifestId, req.user.tenantId, body.reason]
    )
    await fastify.db.query(
      `UPDATE safety_manifest_targets
       SET status = 'REVOKED', reported_at = COALESCE(reported_at, NOW()), failure_reason = $3
       WHERE manifest_id = $1 AND tenant_id = $2 AND status IN ('QUEUED','DELIVERED')`,
      [manifestId, req.user.tenantId, body.reason]
    )
    await insertSafetyEvent(fastify, {
      tenantId: req.user.tenantId,
      commandId: rows[0].command_id,
      manifestId,
      eventType: 'manifest.revoked',
      severity: 'critical',
      payload: { reason: body.reason, revoked_by: req.user.sub }
    })
    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub, actor_type: 'user',
      action: 'safety_manifest.revoke', target_id: manifestId, target_type: 'safety_manifest',
      detail: { command_type: rows[0].command_type, reason: body.reason }, ip: req.ip
    })

    return reply.send({ ok: true, id: manifestId, status: 'REVOKED' })
  })

  fastify.post('/safety/manifests/:id/evaluate', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const manifestId = parseIdParam(req, reply)
    if (!manifestId) return

    const { rows } = await fastify.db.query(
      `SELECT * FROM safety_manifests WHERE id = $1 AND tenant_id = $2`,
      [manifestId, req.user.tenantId]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Safety manifest not found' })

    const [targets, events] = await Promise.all([
      fastify.db.query(
        `SELECT * FROM safety_manifest_targets WHERE manifest_id = $1 AND tenant_id = $2`,
        [manifestId, req.user.tenantId]
      ),
      fastify.db.query(
        `SELECT * FROM safety_events
         WHERE manifest_id = $1 AND tenant_id = $2 AND created_at > NOW() - INTERVAL '24 hours'`,
        [manifestId, req.user.tenantId]
      )
    ])
    const decision = evaluateCanary({ manifestRow: rows[0], targets: targets.rows, events: events.rows })

    if (decision.decision === 'REVOKE') {
      await fastify.db.query(
        `UPDATE safety_manifests
         SET status = 'REVOKED', revoked_at = NOW(), revoke_reason = $3, failure_rate = $4
         WHERE id = $1 AND tenant_id = $2`,
        [manifestId, req.user.tenantId, decision.reason, decision.failure_rate]
      )
      await fastify.db.query(
        `UPDATE commands SET status = 'failed', completed_at = COALESCE(completed_at, NOW()),
             result = jsonb_build_object('revoked', true, 'reason', $3)
         WHERE safety_manifest_id = $1 AND tenant_id = $2 AND status = 'pending'`,
        [manifestId, req.user.tenantId, decision.reason]
      )
      await insertSafetyEvent(fastify, {
        tenantId: req.user.tenantId,
        commandId: rows[0].command_id,
        manifestId,
        eventType: 'manifest.auto_revoked',
        severity: 'critical',
        payload: decision
      })
    } else if (decision.decision === 'ADVANCE') {
      const manifest = rows[0].manifest
      manifest.execution_control.canary_policy.current_phase = decision.next_phase
      manifest.execution_control.canary_policy.target_percentage = decision.next_phase === 'PHASE_2_CANARY' ? 10.0 : 100.0
      const bakeMinutes = Number(manifest.execution_control.canary_policy.bake_time_minutes || 30)
      await fastify.db.query(
        `UPDATE safety_manifests
         SET manifest = $3, canary_phase = $4, target_percentage = $5,
             bake_until = NOW() + ($6 || ' minutes')::interval, failure_rate = $7
         WHERE id = $1 AND tenant_id = $2`,
        [
          manifestId,
          req.user.tenantId,
          JSON.stringify(manifest),
          decision.next_phase,
          manifest.execution_control.canary_policy.target_percentage,
          bakeMinutes,
          decision.failure_rate
        ]
      )
      await insertSafetyEvent(fastify, {
        tenantId: req.user.tenantId,
        commandId: rows[0].command_id,
        manifestId,
        eventType: 'manifest.phase_advanced',
        payload: decision
      })
    } else if (decision.decision === 'COMPLETE') {
      await fastify.db.query(
        `UPDATE safety_manifests
         SET status = 'COMPLETED', completed_at = NOW(), failure_rate = $3
         WHERE id = $1 AND tenant_id = $2`,
        [manifestId, req.user.tenantId, decision.failure_rate]
      )
      await insertSafetyEvent(fastify, {
        tenantId: req.user.tenantId,
        commandId: rows[0].command_id,
        manifestId,
        eventType: 'manifest.completed',
        payload: decision
      })
    }

    return reply.send({ ok: true, id: manifestId, decision })
  })

  // ─── AUDIT LOGS ──────────────────────────────────────────────────
  fastify.get('/audit-logs', auth, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'Admin only' })
    const queryInput = parseRequest(AuditLogQuerySchema, req.query, reply)
    if (!queryInput) return
    const { limit, offset } = queryInput

    const { rows } = await fastify.db.query(
      `SELECT al.*, u.email as actor_email
       FROM audit_logs al
       LEFT JOIN users u ON al.actor_id = u.id
       WHERE al.actor_id IN (SELECT id FROM users WHERE tenant_id = $1)
          OR al.actor_id IS NULL
       ORDER BY al.created_at DESC
       LIMIT $2 OFFSET $3`,
      [req.user.tenantId, limit, offset]
    )
    return reply.send({ logs: rows })
  })

  fastify.delete('/audit-logs/:id', auth, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'Admin only' })
    const auditId = parseNumericIdParam(req, reply)
    if (!auditId) return
    const { rows } = await fastify.db.query(
      `DELETE FROM audit_logs al
       WHERE al.id = $1
         AND (
           al.actor_id IN (SELECT id FROM users WHERE tenant_id = $2)
           OR al.actor_id IS NULL
         )
       RETURNING al.id, al.action`,
      [auditId, req.user.tenantId]
    )
    if (!rows.length) return reply.code(404).send({ error: 'Audit log not found' })
    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub, actor_type: 'user',
      action: 'audit.delete', target_type: 'audit_log',
      detail: { deleted_id: rows[0].id, deleted_action: rows[0].action }, ip: req.ip
    })
    return reply.send({ ok: true, deleted: rows[0].id })
  })

  fastify.delete('/audit-logs', auth, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'Admin only' })
    const queryInput = parseRequest(AuditDeleteQuerySchema, req.query, reply)
    if (!queryInput) return
    const { older_than_days: olderThanDays } = queryInput
    const params = [req.user.tenantId]
    let ageFilter = ''

    if (olderThanDays !== undefined) {
      params.push(olderThanDays)
      ageFilter = ` AND al.created_at < NOW() - ($${params.length} || ' days')::interval`
    }

    const { rowCount } = await fastify.db.query(
      `DELETE FROM audit_logs al
       WHERE (
           al.actor_id IN (SELECT id FROM users WHERE tenant_id = $1)
           OR al.actor_id IS NULL
       )${ageFilter}`,
      params
    )

    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub, actor_type: 'user',
      action: 'audit.clear', target_type: 'audit_log',
      detail: { deleted_count: rowCount, older_than_days: olderThanDays || null }, ip: req.ip
    })
    return reply.send({ ok: true, deleted: rowCount })
  })

  // ─── USER MANAGEMENT ─────────────────────────────────────────────
  fastify.get('/users', auth, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'Admin only' })
    const { rows } = await fastify.db.query(
      `SELECT id, email, role, is_active, last_login, created_at FROM users WHERE tenant_id = $1`,
      [req.user.tenantId]
    )
    return reply.send({ users: rows })
  })

  fastify.post('/users', auth, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'Admin only' })
    const body    = UserCreateSchema.parse(req.body)
    const bcrypt  = require('bcryptjs')
    const hash    = await bcrypt.hash(body.password, 12)

    const { rows } = await fastify.db.query(
      `INSERT INTO users (tenant_id, email, password_hash, role) VALUES ($1,$2,$3,$4) RETURNING id, email, role`,
      [req.user.tenantId, body.email, hash, body.role]
    )
    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub, actor_type: 'user',
      action: 'user.create', target_id: rows[0].id, target_type: 'user',
      detail: { email: body.email, role: body.role }, ip: req.ip
    })
    return reply.code(201).send(rows[0])
  })

  fastify.patch('/users/:id', auth, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'Admin only' })
    const userId = parseIdParam(req, reply)
    if (!userId) return
    const body = parseRequest(UserPatchSchema, req.body, reply)
    if (!body) return
    const { role, is_active } = body
    const updates = []
    const params  = []

    if (role !== undefined)      { params.push(role);      updates.push(`role = $${params.length}`) }
    if (is_active !== undefined) { params.push(is_active); updates.push(`is_active = $${params.length}`) }

    if (!updates.length) return reply.code(400).send({ error: 'Nothing to update' })

    params.push(userId, req.user.tenantId)
    await fastify.db.query(
      `UPDATE users SET ${updates.join(',')} WHERE id = $${params.length - 1} AND tenant_id = $${params.length}`,
      params
    )

    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub, actor_type: 'user',
      action: 'user.update', target_id: userId, target_type: 'user',
      detail: body, ip: req.ip
    })
    return reply.send({ ok: true })
  })

  fastify.delete('/users/:id', auth, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'Admin only' })
    const userId = parseIdParam(req, reply)
    if (!userId) return
    if (userId === req.user.sub) return reply.code(400).send({ error: 'Cannot delete yourself' })
    await fastify.db.query(
      `DELETE FROM users WHERE id = $1 AND tenant_id = $2`,
      [userId, req.user.tenantId]
    )
    return reply.send({ ok: true })
  })

  // ─── TELEMETRY HISTORY ───────────────────────────────────────────
  // [BUG-S08 FIX] Query now uses only columns that exist in schema v6.0
  fastify.get('/agents/:id/telemetry', auth, async (req, reply) => {
    const agentId = parseIdParam(req, reply)
    if (!agentId) return
    const queryInput = parseRequest(TelemetryQuerySchema, req.query, reply)
    if (!queryInput) return
    const { limit, hours } = queryInput
    const { rows } = await fastify.db.query(
      `SELECT active_command_id, schema_version, sample_kind,
              cpu_pct, cpu_kernel_pct, cpu_clock_mhz,
              ram_used_mb, memory_available_mb, memory_committed_pct, memory_cache_faults_sec,
              disk_free_gb, disk_read_bytes_sec, disk_write_bytes_sec, disk_rw_bytes_sec,
              disk_queue_length, disk_time_pct, disk_latency_ms,
              net_rx_kbps, net_tx_kbps, network_bandwidth_bps, network_bytes_total_sec,
              network_output_queue_length, network_latency_ms,
              power_profile, on_battery, handle_count, thread_count, process_count,
              gpu_pct, gpu_temp_c, cpu_temp_c, gpu_name,
              cam_active, mic_active, camera_available, microphone_available,
              biometric_available, location_label, location_detail,
              device_info, bugs, verbose_info,
              public_ip, geo_city, geo_country, extra, ts
       FROM telemetry
       WHERE agent_id = $1 AND tenant_id = $2
         AND ts > NOW() - ($3 || ' hours')::interval
	       ORDER BY ts DESC LIMIT $4`,
      [agentId, req.user.tenantId, hours, limit]
    )
    return reply.send({ telemetry: rows.reverse() })
  })

  // ─── HEALTH SCORE HISTORY ────────────────────────────────────────
  fastify.get('/agents/:id/health', auth, async (req, reply) => {
    const agentId = parseIdParam(req, reply)
    if (!agentId) return
    const { rows } = await fastify.db.query(
      `SELECT score, components, ts FROM health_scores
       WHERE agent_id = $1 AND tenant_id = $2
       ORDER BY ts DESC LIMIT 48`,
      [agentId, req.user.tenantId]
    )
    return reply.send({ history: rows.reverse() })
  })

  // ─── SECURITY ALERTS ─────────────────────────────────────────────
  fastify.get('/alerts', auth, async (req, reply) => {
    const queryInput = parseRequest(AlertListQuerySchema, req.query, reply)
    if (!queryInput) return
    const { resolved, limit, offset } = queryInput
    const { rows } = await fastify.db.query(
      `SELECT sa.*, a.hostname FROM security_alerts sa
       LEFT JOIN agents a ON a.id = sa.agent_id
       WHERE sa.tenant_id = $1 AND sa.resolved = $2
       ORDER BY sa.created_at DESC LIMIT $3 OFFSET $4`,
      [req.user.tenantId, resolved, limit, offset]
    )
    return reply.send({ alerts: rows })
  })

  fastify.patch('/alerts/:id/resolve', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const alertId = parseIdParam(req, reply)
    if (!alertId) return
    await fastify.db.query(
      `UPDATE security_alerts SET resolved = TRUE, resolved_by = $1, resolved_at = NOW() WHERE id = $2 AND tenant_id = $3`,
      [req.user.sub, alertId, req.user.tenantId]
    )
    await writeAuditLog(fastify.db, { actor_id: req.user.sub, actor_type: 'user', action: 'alert.resolve', target_id: alertId, ip: req.ip })
    return reply.send({ ok: true })
  })

  // ─── SCHEDULED TASKS ─────────────────────────────────────────────
  fastify.get('/scheduled-tasks', auth, async (req, reply) => {
    const { rows } = await fastify.db.query(
      `SELECT st.*, u.email as created_by_email FROM scheduled_tasks st
       LEFT JOIN users u ON u.id = st.created_by
       WHERE st.tenant_id = $1 ORDER BY st.created_at DESC`,
      [req.user.tenantId]
    )
    return reply.send({ tasks: rows })
  })

  fastify.post('/scheduled-tasks', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const body = parseRequest(ScheduledTaskSchema, req.body, reply)
    if (!body) return
    const { name, description, agent_id, group_id, target_all, cmd_type, cmd_args, priority, cron_expr, timezone } = body
    const { rows } = await fastify.db.query(
      `INSERT INTO scheduled_tasks (tenant_id, name, description, agent_id, group_id, target_all, cmd_type, cmd_args, priority, cron_expr, timezone, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *`,
      [req.user.tenantId, name, description, agent_id||null, group_id||null, !!target_all, cmd_type, JSON.stringify(cmd_args||{}), priority||5, cron_expr, timezone||'UTC', req.user.sub]
    )
    await writeAuditLog(fastify.db, { actor_id: req.user.sub, actor_type: 'user', action: 'schedule.create', detail: { name, cmd_type, cron_expr }, ip: req.ip })
    return reply.code(201).send(rows[0])
  })

  fastify.delete('/scheduled-tasks/:id', auth, async (req, reply) => {
    if (req.user.role !== 'admin') return reply.code(403).send({ error: 'Admin only' })
    const taskId = parseIdParam(req, reply)
    if (!taskId) return
    await fastify.db.query(`DELETE FROM scheduled_tasks WHERE id = $1 AND tenant_id = $2`, [taskId, req.user.tenantId])
    return reply.send({ ok: true })
  })

  // ─── ALERT RULES ─────────────────────────────────────────────────
  fastify.get('/alert-rules', auth, async (req, reply) => {
    const { rows } = await fastify.db.query(
      `SELECT * FROM alert_rules WHERE tenant_id = $1 ORDER BY created_at DESC`,
      [req.user.tenantId]
    )
    return reply.send({ rules: rows })
  })

  fastify.post('/alert-rules', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const body = parseRequest(AlertRuleSchema, req.body, reply)
    if (!body) return
    const { name, condition, action_cmd, notify_telegram, cooldown_min } = body
    const { rows } = await fastify.db.query(
      `INSERT INTO alert_rules (tenant_id, name, condition, action_cmd, notify_telegram, cooldown_min, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
      [req.user.tenantId, name, JSON.stringify(condition), action_cmd||null, !!notify_telegram, cooldown_min||60, req.user.sub]
    )
    return reply.code(201).send(rows[0])
  })

  fastify.patch('/alert-rules/:id', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const ruleId = parseIdParam(req, reply)
    if (!ruleId) return
    const body = parseRequest(AlertRulePatchSchema, req.body, reply)
    if (!body) return
    await fastify.db.query(`UPDATE alert_rules SET is_active=$1 WHERE id=$2 AND tenant_id=$3`, [body.is_active, ruleId, req.user.tenantId])
    return reply.send({ ok: true })
  })

  // ─── AGENT GROUPS ────────────────────────────────────────────────
  fastify.get('/groups', auth, async (req, reply) => {
    const { rows } = await fastify.db.query(
      `SELECT g.*, COUNT(a.id)::int as agent_count FROM agent_groups g
       LEFT JOIN agents a ON a.group_id = g.id
       WHERE g.tenant_id = $1 GROUP BY g.id ORDER BY g.name`,
      [req.user.tenantId]
    )
    return reply.send({ groups: rows })
  })

  fastify.post('/groups', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const body = parseRequest(AgentGroupSchema, req.body, reply)
    if (!body) return
    const { name, description, color } = body
    const { rows } = await fastify.db.query(
      `INSERT INTO agent_groups (tenant_id, name, description, color) VALUES ($1,$2,$3,$4) RETURNING *`,
      [req.user.tenantId, name, description||null, color||'#00e57a']
    )
    return reply.code(201).send(rows[0])
  })

  fastify.patch('/agents/:id/group', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const agentId = parseIdParam(req, reply)
    if (!agentId) return
    const body = parseRequest(AgentGroupAssignSchema, req.body, reply)
    if (!body) return
    const { group_id } = body
    await fastify.db.query(
      `UPDATE agents SET group_id = $1 WHERE id = $2 AND tenant_id = $3`,
      [group_id || null, agentId, req.user.tenantId]
    )
    return reply.send({ ok: true })
  })

  async function handleSecurityAlertIngestion (req, reply) {
    const key = req.headers['x-openfang-key'] || req.headers['x-api-key']
    if (process.env.OPENFANG_API_KEY && key !== process.env.OPENFANG_API_KEY) {
      return reply.code(401).send({ error: 'Unauthorized: Invalid OpenFang API Key' })
    }
    const body = parseRequest(SecurityAlertIngestSchema, req.body, reply)
    if (!body) return
    const { agent_id, severity, rule_name, description, src_ip, process_name } = body

    const { rows: agentRows } = await fastify.db.query('SELECT tenant_id, hostname FROM agents WHERE id=$1', [agent_id])
    if (!agentRows.length) return reply.code(404).send({ error: 'Agent not found' })
    const { tenant_id, hostname } = agentRows[0]

    // [NEW] Ollama AI analysis of the threat
    let aiDecision = null, aiReason = null, aiConfidence = null, aiModel = null
    const aiResult = await ollama.analyzeThreat({ severity, rule_name, description, src_ip, process_name, hostname })
    if (aiResult) {
      aiDecision   = aiResult.decision
      aiReason     = aiResult.reason
      aiConfidence = aiResult.confidence
      aiModel      = aiResult.model
      fastify.log.info({ agentId: agent_id, decision: aiDecision, confidence: aiConfidence }, '[Ollama] Threat analyzed')
    }

    // Persist alert to security_alerts table
    const { rows: alertRows } = await fastify.db.query(
      `INSERT INTO security_alerts (agent_id, tenant_id, source, severity, rule_name, description, src_ip, process_name, ai_decision, ai_reason, ai_confidence, ai_model)
       VALUES ($1,$2,'security_onion',$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,
      [agent_id, tenant_id, severity, rule_name, description, src_ip, process_name, aiDecision, aiReason, aiConfidence, aiModel]
    )

    await writeAuditLog(fastify.db, {
      actor_id: null, actor_type: 'ai_system', action: 'openfang.alert',
      target_id: agent_id, target_type: 'agent',
      detail: { severity, rule_name, src_ip, ai_decision: aiDecision }, ip: req.ip
    })

    // Auto-dispatch THREAT_SCAN if critical/high severity
    if (['critical', 'high'].includes(severity?.toLowerCase())) {
      const { rows: agents } = await fastify.db.query(
        'SELECT id, tenant_id, hostname, version, os, tags, health_score FROM agents WHERE id = $1',
        [agent_id]
      )
      if (!agents.length) return reply.code(404).send({ error: 'Agent not found' })
      try {
        await createSafeCommand(fastify, {
          tenantId: agents[0].tenant_id,
          agent: agents[0],
          type: 'THREAT_SCAN',
          args: { source: 'openfang.alert', rule_name, severity },
          priority: 1,
          issuedBy: null,
          issuedByType: 'ai_system',
          source: 'OpenFang'
        })
      } catch (err) {
        if (![412, 423].includes(err.statusCode)) throw err
        fastify.log.warn({ err, agentId: agent_id }, '[Safety] OpenFang auto-dispatch blocked')
      }
    }

    return reply.send({ ok: true, auto_response: ['critical','high'].includes(severity?.toLowerCase()) })
  }

  // ─── SECURITY ONION / OPENFANG ALERT INGESTION ───────────────────
  fastify.post('/security/alert', handleSecurityAlertIngestion)
  fastify.post('/aegis/alert', handleSecurityAlertIngestion) // legacy alias; Aegis AV is reserved for the next project.

  // ─── OPENFANG AI → NeoOptimize COMMAND DISPATCH ──────────────────
  fastify.post('/openfang/command', async (req, reply) => {
    const key = req.headers['x-openfang-key']
    if (process.env.OPENFANG_API_KEY && key !== process.env.OPENFANG_API_KEY) {
      return reply.code(401).send({ error: 'Unauthorized AI Connector' })
    }
    // Rate limit: 60 commands per minute for AI endpoints
    const rlKey  = `rl:openfang:${req.ip}`
    const rlCount = await fastify.redis.incr(rlKey)
    if (rlCount === 1) await fastify.redis.expire(rlKey, 60)
    if (rlCount > 60) return reply.code(429).send({ error: 'Rate limit exceeded' })

    const body = parseRequest(OpenFangCommandSchema, req.body, reply)
    if (!body) return
    const { agent_id, type, args, priority } = body

    const { rows: agents } = await fastify.db.query(
      'SELECT id, tenant_id, hostname, version, os, tags, health_score FROM agents WHERE id = $1',
      [agent_id]
    )
    if (!agents.length) return reply.code(404).send({ error: 'Agent not found' })

    let created
    try {
      created = await createSafeCommand(fastify, {
        tenantId: agents[0].tenant_id,
        agent: agents[0],
        type,
        args,
        priority,
        issuedBy: null,
        issuedByType: 'ai_system',
        source: 'OpenFang.Command'
      })
    } catch (err) {
      return sendSafetyError(reply, err)
    }

    await writeAuditLog(fastify.db, {
      actor_id: null, actor_type: 'ai_system',
      action: 'openfang.command',
      target_id: agent_id, target_type: 'agent',
      detail: {
        cmd_type: type,
        cmd_id: created.commandId,
        safety_manifest_id: created.manifestId,
        risk_level: created.riskLevel,
        source: 'openfang_guardian'
      }, ip: req.ip
    })

    return reply.code(201).send({
      ok: true,
      cmd_id: created.commandId,
      safety_manifest_id: created.manifestId,
      risk_level: created.riskLevel,
      canary_phase: created.canaryPhase,
      source: 'openfang'
    })
  })

  // ─── OPENFANG TELEMETRY INGEST ───────────────────────────────────
  // OpenFang can forward processed operator-hand telemetry back to NeoOptimize.
  fastify.post('/openfang/telemetry', async (req, reply) => {
    const key = req.headers['x-openfang-key']
    if (process.env.OPENFANG_API_KEY && key !== process.env.OPENFANG_API_KEY) {
      return reply.code(401).send({ error: 'Unauthorized AI Connector' })
    }

    const body = parseRequest(OpenFangTelemetrySchema, req.body, reply)
    if (!body) return

    let target = null
    if (body.agent_id) {
      const { rows } = await fastify.db.query(
        `SELECT id, tenant_id, hostname FROM agents WHERE id = $1`,
        [body.agent_id]
      )
      target = rows[0] || null
    }

    const payload = {
      ...body,
      received_at: new Date().toISOString(),
      normalized_action: normalizeOperatorCommand(body.recommended_command || body.action)
    }

    if (target) {
      await fastify.redis.setex(`openfang:tele:${target.id}`, 3600, JSON.stringify(payload))
      await writeAuditLog(fastify.db, {
        actor_id: null,
        actor_type: 'ai_system',
        action: 'openfang.telemetry',
        target_id: target.id,
        target_type: 'agent',
        detail: {
          hand: body.hand,
          severity: body.severity,
          action: payload.normalized_action,
          confidence: body.confidence,
          summary: body.summary
        },
        ip: req.ip
      })
    }

    return reply.send({
      status: 'received',
      processing_hand: body.hand,
      agent_id: target?.id || body.agent_id || null,
      cached: !!target,
      normalized_action: payload.normalized_action
    })
  })

  // ─── OPENFANG FETCH PENDING SCANS ────────────────────────────────
  fastify.get('/openfang/results', async (req, reply) => {
    const key = req.headers['x-openfang-key']
    if (process.env.OPENFANG_API_KEY && key !== process.env.OPENFANG_API_KEY) {
      return reply.code(401).send({ error: 'Unauthorized AI Connector' })
    }
    
    // Guardian hand is fetching finished THREAT_SCAN results to analyze
    const { rows } = await fastify.db.query(
      `SELECT c.id, c.agent_id, a.hostname, c.result 
       FROM commands c
       JOIN agents a ON a.id = c.agent_id
       WHERE c.type = 'THREAT_SCAN' 
         AND c.status = 'success'
       ORDER BY c.completed_at DESC 
       LIMIT 10`
    )
    
    // We send them in the exact format OpenFang expects
    return reply.send({ commands: rows })
  })
  // ─── AI ANALYSIS — Gemini (per system) ──────────────────────────
  // Already exists above at line 151-174

  // ─── AI HEALTH SCORE — Ollama ────────────────────────────────────
  fastify.get('/agents/:id/ai-health', auth, async (req, reply) => {
    const tenantId = req.user.tenantId
    const agentId = parseIdParam(req, reply)
    if (!agentId) return
    const { rows: agentRows } = await fastify.db.query(
      `SELECT * FROM agents WHERE id = $1 AND tenant_id = $2`,
      [agentId, tenantId]
    )
    if (!agentRows.length) return reply.code(404).send({ error: 'System not found' })

    const tele = await fastify.redis.get(`agent:tele:${agentId}`)
    const telemetry = tele ? JSON.parse(tele) : {}

    const { rows: alerts } = await fastify.db.query(
      `SELECT severity FROM security_alerts WHERE agent_id=$1 AND resolved=false AND created_at > NOW() - INTERVAL '24 hours'`,
      [agentId]
    )

    const healthResult = await ollama.calculateHealthScore(telemetry, alerts)
    return reply.send({ health: healthResult, timestamp: new Date().toISOString() })
  })

  // ─── AI RECOMMENDATIONS — Ollama ─────────────────────────────────
  fastify.get('/agents/:id/ai-recommend', auth, async (req, reply) => {
    const tenantId = req.user.tenantId
    const agentId = parseIdParam(req, reply)
    if (!agentId) return
    const { rows } = await fastify.db.query(
      `SELECT hostname, os, cpu, ram_mb, last_seen FROM agents WHERE id=$1 AND tenant_id=$2`,
      [agentId, tenantId]
    )
    if (!rows.length) return reply.code(404).send({ error: 'System not found' })

    const tele = await fastify.redis.get(`agent:tele:${agentId}`)
    const telemetry = tele ? JSON.parse(tele) : {}

    // Build prompt for optimization recommendations
    const prompt = `You are NeoOptimize AI advisor. A Windows system needs optimization.\nSystem: ${JSON.stringify(rows[0])}\nTelemetry: CPU=${telemetry.cpu_pct}%, RAM=${telemetry.ram_used_mb}MB, Disk free=${telemetry.disk_free_gb}GB\nList top 3 optimization actions as JSON: {"recommendations":[{"module":"module name","priority":"critical|high|medium","reason":"why","command":"OPTIMIZE|CLEAN|SECURITY_SCAN|etc"}]}`

    const { ollama: ollamaLib } = require('../lib/integrations')
    let recommendations = { recommendations: [] }
    try {
      const raw = await ollamaLib._generate ? ollamaLib._generate(prompt) : null
      const jsonMatch = raw?.match(/{[\s\S]*}/)
      if (jsonMatch) recommendations = JSON.parse(jsonMatch[0])
    } catch (err) {
      req.log.warn({ err, agentId }, '[Ollama] recommendation parsing failed')
    }

    recommendations.recommendations = Array.isArray(recommendations.recommendations)
      ? recommendations.recommendations
        .filter(item => !item.command || ALL_COMMANDS.includes(String(item.command).toUpperCase()))
        .slice(0, 5)
      : []

    return reply.send({ ...recommendations, model: 'ollama', timestamp: new Date().toISOString() })
  })

  // ─── FLEET ML INSIGHTS — NeoCortex cached scores ────────────────
  fastify.get('/ml/fleet-insights', auth, async (req, reply) => {
    const tenantId = req.user.tenantId
    const { rows: agents } = await fastify.db.query(
      `SELECT id, hostname, health_score, health_reason, status, last_seen
       FROM agents
       WHERE tenant_id = $1
       ORDER BY health_score ASC, last_seen DESC NULLS LAST
       LIMIT 200`,
      [tenantId]
    )

    const insights = []
    for (const agent of agents) {
      const cached = await fastify.redis.get(`agent:ml:${agent.id}`)
      if (cached) {
        insights.push(JSON.parse(cached))
      } else {
        insights.push({
          model: 'neocortex-hybrid-v1',
          agent_id: agent.id,
          hostname: agent.hostname,
          health_score: agent.health_score,
          risk_level: agent.health_score < 45 ? 'critical' : agent.health_score < 65 ? 'high' : agent.health_score < 82 ? 'medium' : 'low',
          anomaly_score: 0,
          summary: agent.health_reason || 'No live ML cache yet.'
        })
      }
    }

    return reply.send({
      fleet: buildFleetInsights(insights),
      timestamp: new Date().toISOString()
    })
  })

  // ─── NULLCLAW IP THREAT CHECK ────────────────────────────────────
  fastify.post('/threat/check-ip', auth, async (req, reply) => {
    const body = parseRequest(ThreatIpSchema, req.body, reply)
    if (!body) return
    const { ip } = body
    const result = await nullclaw.checkIp(ip)
    return reply.send({ ip, result, checked_at: new Date().toISOString() })
  })

  fastify.post('/threat/check-hash', auth, async (req, reply) => {
    const body = parseRequest(ThreatHashSchema, req.body, reply)
    if (!body) return
    const { hash } = body
    const result = await nullclaw.checkHash(hash)
    return reply.send({ hash, result, checked_at: new Date().toISOString() })
  })

  // ─── HF SPACE STATUS ─────────────────────────────────────────────
  fastify.get('/integrations/hf/status', auth, async (req, reply) => {
    const restarted = await hf.checkAndRestartIdleSpace()
    return reply.send({
      space: process.env.HF_SPACE_ID,
      restarted,
      stage: hf.lastStage || null,
      error: hf.lastError || null,
      checked_at: new Date().toISOString()
    })
  })

  // ─── E2B SANDBOX ANALYSIS ────────────────────────────────────────
  fastify.post('/integrations/e2b/analyze', auth, async (req, reply) => {
    if (req.user.role === 'viewer') return reply.code(403).send({ error: 'Forbidden' })
    const body = parseRequest(E2BAnalyzeSchema, req.body, reply)
    if (!body) return
    const { code } = body
    const result = await e2b.runPythonScript(code)
    await writeAuditLog(fastify.db, {
      actor_id: req.user.sub, actor_type: 'user',
      action: 'e2b.analyze', detail: { code_length: code.length }, ip: req.ip
    })
    return reply.send(result)
  })

  // ─── INTEGRATION STATUS OVERVIEW ────────────────────────────────
  fastify.get('/integrations/status', auth, async (req, reply) => {
    return reply.send({
      neocortex: { enabled: true, model: 'neocortex-hybrid-v1' },
      supabase: {
        enabled: !!(process.env.SUPABASE_URL && !process.env.SUPABASE_URL.includes('YOUR_PROJECT')),
        url: process.env.SUPABASE_URL || null
      },
      telegram: { enabled: !!(process.env.TELEGRAM_BOT_TOKEN && !process.env.TELEGRAM_BOT_TOKEN.includes('YOUR_BOT')) },
      ollama:   { enabled: true, url: process.env.OLLAMA_URL || 'http://localhost:11434', model: process.env.OLLAMA_MODEL || 'neo-light' },
      gemini:   { enabled: !!process.env.GEMINI_API_KEY },
      hf:       { enabled: !!(process.env.HF_TOKEN && process.env.HF_SPACE_ID), space: process.env.HF_SPACE_ID },
      e2b:      { enabled: !!process.env.E2B_API_KEY },
      nullclaw: { enabled: !!(process.env.NULLCLAW_API_KEY && process.env.NULLCLAW_API_KEY.length > 5) },
    })
  })
}

module.exports = dashboardRoutes
