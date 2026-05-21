#!/usr/bin/env node
'use strict'

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')

const ROOT = path.resolve(__dirname, '..')
loadEnv(path.join(ROOT, 'server', '.env'))

const { Pool } = require(path.join(ROOT, 'server', 'node_modules', 'pg'))
const signing = require(path.join(ROOT, 'server', 'src', 'security', 'signing'))
const {
  buildSafetyManifest,
  signSafetyManifest,
  attachSafetyManifestToArgs,
  evaluateAgentEligibility
} = require(path.join(ROOT, 'server', 'src', 'lib', 'safetyManifest'))

const args = parseArgs(process.argv.slice(2))
const mode = args.mode || 'runtime-smoke'
const timeoutSeconds = Number(args.timeout || (mode === 'rollback' ? 180 : 60))

main().catch(err => {
  console.error(`[FAIL] ${err.message}`)
  process.exitCode = 1
})

async function main () {
  const pool = new Pool({
    host: process.env.POSTGRES_HOST || 'localhost',
    port: Number(process.env.POSTGRES_PORT || 5432),
    database: process.env.POSTGRES_DB || 'neooptimize_rmm',
    user: process.env.POSTGRES_USER || 'neo_app',
    password: process.env.POSTGRES_PASSWORD,
    min: 0,
    max: 2,
    ssl: process.env.POSTGRES_SSL === 'true' ? { rejectUnauthorized: true } : false
  })

  try {
    const agent = await selectAgent(pool)
    const commandType = mode === 'rollback' ? 'SAFETY_ROLLBACK_TEST' : 'PING'
    const commandArgs = mode === 'rollback'
      ? {
          lab_self_healing_test: true,
          registry_path: 'HKLM\\SOFTWARE\\NeoOptimizeTest',
          value_name: 'OptimizationLevel',
          value: 'Extreme',
          cpu_burn_seconds: Number(args.cpuBurnSeconds || 45)
        }
      : { probe: 'agent-self-healing-runtime' }

    const issued = await issueSafeCommand(pool, agent, commandType, commandArgs)
    console.log(`[ISSUED] mode=${mode} agent=${agent.hostname} id=${issued.commandId} manifest=${issued.manifestId}`)

    const final = await waitForResult(pool, issued.commandId, timeoutSeconds)
    const result = final.result || {}
    const selfHealing = result.self_healing || null
    const rejected = final.status === 'rejected' || final.target_status === 'FAILED' || !!result.rejected

    console.log(JSON.stringify({
      ok: true,
      mode,
      agent: {
        id: agent.id,
        hostname: agent.hostname,
        version: agent.version,
        status: agent.status,
        last_seen: agent.last_seen
      },
      command: {
        id: issued.commandId,
        type: commandType,
        status: final.status,
        target_status: final.target_status,
        failure_reason: final.failure_reason
      },
      runtime_detected: !!selfHealing,
      rolled_back: !!(result.rollback || result.rolled_back),
      rejected,
      self_healing: selfHealing,
      impact: result.impact || final.impact || null
    }, null, 2))

    if (rejected) {
      throw new Error(final.failure_reason || result.error || 'Agent rejected command')
    }

    if (mode === 'runtime-smoke' && !selfHealing) {
      throw new Error('Agent answered PING but did not include self_healing metadata. VM likely still runs the old agent binary.')
    }

    if (mode === 'rollback' && final.target_status !== 'ROLLBACK') {
      throw new Error(`Expected safety target status ROLLBACK, got ${final.target_status || final.status}`)
    }
  } finally {
    await pool.end()
  }
}

async function selectAgent (pool) {
  const selector = args.agentId
    ? { sql: 'id = $1', values: [args.agentId] }
    : args.hostname
      ? { sql: 'hostname ILIKE $1', values: [args.hostname] }
      : { sql: "status = 'online'", values: [] }

  const { rows } = await pool.query(
    `SELECT id, tenant_id, hostname, version, os, tags, health_score, status, last_seen
       FROM agents
      WHERE ${selector.sql}
      ORDER BY last_seen DESC NULLS LAST
      LIMIT 1`,
    selector.values
  )
  if (!rows.length) throw new Error('No matching agent found. Use --agent-id or --hostname.')
  return rows[0]
}

async function issueSafeCommand (pool, agent, commandType, commandArgs) {
  const commandId = crypto.randomUUID()
  const manifest = buildSafetyManifest({
    commandId,
    type: commandType,
    args: commandArgs,
    agent,
    source: 'NeoOptimize.E2ERegression'
  })

  const eligibility = evaluateAgentEligibility(agent, manifest)
  if (!eligibility.ok) throw new Error(`Safety gate rejected agent: ${eligibility.reason}`)

  const signedManifest = signSafetyManifest(manifest)
  const safeArgs = attachSafetyManifestToArgs(commandArgs, signedManifest)
  const commandSignature = signing.signCommand(commandId, commandType, safeArgs)
  const canary = manifest.execution_control.canary_policy
  const bakeUntil = canary.enabled ? new Date(Date.now() + canary.bake_time_minutes * 60 * 1000) : null

  const client = await pool.connect()
  try {
    await client.query('BEGIN')

    const manifestRows = await client.query(
      `INSERT INTO safety_manifests
         (tenant_id, command_id, command_type, version, manifest, manifest_sha256, signature,
          status, risk_level, canary_phase, target_percentage, bake_until, created_by_type)
       VALUES ($1,$2,$3,$4,$5,$6,$7,'ACTIVE',$8,$9,$10,$11,'lab')
       RETURNING id`,
      [
        agent.tenant_id,
        commandId,
        commandType,
        manifest.version,
        JSON.stringify(manifest),
        signedManifest.manifest_sha256,
        signedManifest.signature,
        manifest.policy_gate.risk_level,
        canary.current_phase,
        canary.target_percentage,
        bakeUntil
      ]
    )

    const manifestId = manifestRows.rows[0].id
    await client.query(
      `INSERT INTO commands
         (id, agent_id, tenant_id, type, args, signature, priority, issued_by_type, timeout_secs, safety_manifest_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,'lab',$8,$9)`,
      [
        commandId,
        agent.id,
        agent.tenant_id,
        commandType,
        JSON.stringify(safeArgs),
        commandSignature,
        Number(args.priority || 1),
        manifest.execution_control.timeout_seconds,
        manifestId
      ]
    )

    await client.query(
      `INSERT INTO safety_manifest_targets (manifest_id, tenant_id, agent_id, command_id, phase, status)
       VALUES ($1,$2,$3,$4,$5,'QUEUED')`,
      [manifestId, agent.tenant_id, agent.id, commandId, canary.current_phase]
    )

    await client.query(
      `INSERT INTO safety_events (manifest_id, command_id, tenant_id, agent_id, event_type, severity, payload)
       VALUES ($1,$2,$3,$4,'e2e.command.issued','info',$5)`,
      [manifestId, commandId, agent.tenant_id, agent.id, JSON.stringify({ mode, command_type: commandType })]
    )

    await client.query('COMMIT')
    return { commandId, manifestId }
  } catch (err) {
    await client.query('ROLLBACK')
    throw err
  } finally {
    client.release()
  }
}

async function waitForResult (pool, commandId, timeoutSec) {
  const deadline = Date.now() + timeoutSec * 1000
  while (Date.now() < deadline) {
    const { rows } = await pool.query(
      `SELECT c.status, c.result, smt.status AS target_status, smt.failure_reason, smt.impact
         FROM commands c
         LEFT JOIN safety_manifest_targets smt ON smt.command_id = c.id
        WHERE c.id = $1`,
      [commandId]
    )
    if (!rows.length) throw new Error(`Command disappeared: ${commandId}`)
    const row = rows[0]
    if (['success', 'failed', 'timeout', 'rejected'].includes(row.status)) return row
    await sleep(3000)
  }
  throw new Error(`Timed out waiting for command result after ${timeoutSec}s`)
}

function loadEnv (file) {
  if (!fs.existsSync(file)) return
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const index = trimmed.indexOf('=')
    if (index < 0) continue
    const key = trimmed.slice(0, index).trim()
    const value = trimmed.slice(index + 1).trim()
    if (!process.env[key]) process.env[key] = value
  }
}

function parseArgs (argv) {
  const out = {}
  for (let i = 0; i < argv.length; i++) {
    const item = argv[i]
    if (!item.startsWith('--')) continue
    const key = item.slice(2).replace(/-([a-z])/g, (_, ch) => ch.toUpperCase())
    const next = argv[i + 1]
    if (!next || next.startsWith('--')) {
      out[key] = true
    } else {
      out[key] = next
      i++
    }
  }
  return out
}

function sleep (ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}
