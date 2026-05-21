'use strict'

// ═══════════════════════════════════════════════════════════════════
// COMMAND WORKER v6.0 — Redis Queue + Dispatcher
// [BUG-S10 FIX] Whitelist synced with dashboard.js ALL_COMMANDS
// [NEW] Timeout worker for expired commands
// ═══════════════════════════════════════════════════════════════════

const signing = require('../security/signing')
const { v4: uuidv4 } = require('uuid')

// [BUG-S10 FIX] Synced with dashboard.js ALL_COMMANDS — complete list
const ALLOWED_COMMANDS = new Set([
  // Optimization & Maintenance
  'OPTIMIZE', 'CLEAN', 'UPDATES', 'PRIVACY', 'POWER', 'SERVICES',
  'APP_MANAGER', 'SYSTEM_REPAIR', 'SYSTEM_DIAGNOSTICS', 'BACKUP_OPS',
  'PERFORMANCE', 'DEEP_SCAN', 'NEOUPDATE',
  // Endpoint security (OpenFang / local scanner)
  'SECURITY_SCAN', 'NETWORK_TEST', 'THREAT_SCAN', 'AUTOIMMUNE', 'INTEGRITY_SCAN',
  // Hardware Telemetry
  'COLLECT', 'SYSINFO',
  // Health Check
  'PING'
])

function start (app) {
  const { db, redis, log } = app

  // Worker 1: Process command dispatch queue (every 2s)
  setInterval(async () => {
    try { await processCommandQueue(db, redis, log) }
    catch (err) { log.error({ err }, 'commandWorker error') }
  }, 2000)

  // Worker 2: Timeout expired commands (every 15s)
  setInterval(async () => {
    try { await markTimedOutCommands(db, log) }
    catch (err) { log.error({ err }, 'timeout worker error') }
  }, 15000)

  // Worker 3: Alert rule evaluator (every 60s)
  setInterval(async () => {
    try { await evaluateAlertRules(db, redis, log) }
    catch (err) { log.error({ err }, 'alert rule evaluator error') }
  }, 60000)

  log.info('[CommandWorker] Started (queue + timeout + alert evaluator)')
}

async function processCommandQueue (db, redis, log) {
  // Atomic pop from Redis queue (safe for multiple worker instances)
  const raw = await redis.rpop('commands:queue')
  if (!raw) return

  const payload = JSON.parse(raw)
  const { agent_id, tenant_id, type, args, priority, issued_by } = payload

  // Whitelist check
  if (!ALLOWED_COMMANDS.has(type)) {
    log.warn({ type, agent_id }, '[Worker] Rejected unknown command type')
    return
  }

  // Validate agent exists
  const { rows: agents } = await db.query(
    `SELECT id FROM agents WHERE id = $1 AND tenant_id = $2`,
    [agent_id, tenant_id]
  )
  if (!agents.length) {
    log.warn({ agent_id }, '[Worker] Agent not found for queued command')
    return
  }

  const cmdId = uuidv4()

  // Sign command
  let signature = null
  try {
    signature = signing.signCommand(cmdId, type, args)
  } catch (err) {
    log.error({ err }, '[Worker] Failed to sign command — keys missing?')
    return
  }

  // Store to DB (with tenant_id — BUG-S02 is now fixed in schema)
  await db.query(`
    INSERT INTO commands
      (id, agent_id, tenant_id, type, args, signature, status, priority, issued_by, issued_by_type)
    VALUES ($1,$2,$3,$4,$5,$6,'pending',$7,$8,$9)`,
    [cmdId, agent_id, tenant_id, type, JSON.stringify(args || {}), signature, priority || 5, issued_by, issued_by ? 'user' : 'ai_system']
  )

  log.info({ cmdId, agentId: agent_id, type }, '[Worker] Command dispatched from queue')
}

async function markTimedOutCommands (db, log) {
  const { rowCount } = await db.query(`
    UPDATE commands
    SET status = 'timeout', completed_at = NOW()
    WHERE status IN ('delivered', 'running')
      AND NOW() > (delivered_at + (timeout_secs || ' seconds')::interval)
  `)
  if (rowCount > 0) {
    log.warn({ count: rowCount }, '[Worker] Commands marked as timed out')
  }
}

// ─── Alert Rule Evaluator ──────────────────────────────────────────
async function evaluateAlertRules (db, redis, log) {
  const { rows: rules } = await db.query(
    `SELECT * FROM alert_rules WHERE is_active = TRUE`
  )
  if (!rules.length) return

  for (const rule of rules) {
    try {
      const condition = rule.condition
      if (!condition.metric || condition.metric === 'scheduled') continue

      // Get latest telemetry for all agents in this tenant
      const { rows: agents } = await db.query(
        `SELECT id, hostname FROM agents WHERE tenant_id = $1 AND status = 'online'`,
        [rule.tenant_id]
      )

      for (const agent of agents) {
        const cached = await redis.get(`agent:tele:${agent.id}`)
        if (!cached) continue

        const tele = JSON.parse(cached)
        const metricMap = {
          cpu_pct:      tele.c,
          ram_used_mb:  tele.r,
          disk_free_gb: tele.d,
          gpu_pct:      tele.g
        }

        const value = metricMap[condition.metric]
        if (value === undefined || value === null) continue

        let triggered = false
        if (condition.operator === 'gt' && value > condition.threshold) triggered = true
        if (condition.operator === 'lt' && value < condition.threshold) triggered = true
        if (condition.operator === 'gte' && value >= condition.threshold) triggered = true
        if (condition.operator === 'lte' && value <= condition.threshold) triggered = true

        if (!triggered) continue

        // Check cooldown
        const cooldownKey = `alertcooldown:${rule.id}:${agent.id}`
        const onCooldown  = await redis.exists(cooldownKey)
        if (onCooldown) continue

        log.warn({ ruleId: rule.id, ruleName: rule.name, agentId: agent.id, value },
          '[AlertRule] Triggered')

        // Set cooldown
        await redis.setex(cooldownKey, rule.cooldown_min * 60, '1')

        // Auto-dispatch command if configured
        if (rule.action_cmd && ALLOWED_COMMANDS.has(rule.action_cmd)) {
          const cmdId = uuidv4()
          let sig = null
          try { sig = signing.signCommand(cmdId, rule.action_cmd, rule.action_args || {}) } catch {}

          await db.query(`
            INSERT INTO commands (id, agent_id, tenant_id, type, args, signature, priority, issued_by_type)
            VALUES ($1,$2,$3,$4,$5,$6,1,'ai_system')`,
            [cmdId, agent.id, rule.tenant_id, rule.action_cmd, JSON.stringify(rule.action_args || {}), sig]
          )
        }

        // Update rule stats
        await db.query(
          `UPDATE alert_rules SET last_triggered = NOW(), trigger_count = trigger_count + 1 WHERE id = $1`,
          [rule.id]
        )
      }
    } catch (err) {
      log.error({ err, ruleId: rule.id }, '[AlertRule] Evaluation error')
    }
  }
}

// ─── Enqueue Command (called from dashboard routes) ────────────────
async function enqueueCommand (redis, { agentId, tenantId, type, args, priority, issuedBy }) {
  if (!ALLOWED_COMMANDS.has(type)) {
    throw new Error(`Command type '${type}' not in whitelist`)
  }
  await redis.lpush('commands:queue', JSON.stringify({
    agent_id:  agentId,
    tenant_id: tenantId,
    type,
    args:      args || {},
    priority:  priority || 5,
    issued_by: issuedBy
  }))
}

module.exports = { start, enqueueCommand, ALLOWED_COMMANDS }
