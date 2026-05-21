#!/usr/bin/env node
'use strict'

const fs = require('fs')
const https = require('https')
const path = require('path')

function parseArgs (argv) {
  const args = {
    env: 'server/.env',
    writeTest: null,
    json: false
  }

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--help' || arg === '-h') args.help = true
    else if (arg === '--json') args.json = true
    else if (arg === '--env') args.env = argv[++i]
    else if (arg === '--write-test') {
      const next = argv[i + 1]
      if (next && !next.startsWith('--')) {
        args.writeTest = next
        i++
      } else {
        args.writeTest = 'both'
      }
    }
  }
  return args
}

function usage () {
  return [
    'Usage: node tools/Check-SupabaseMirror.js [--env server/.env] [--write-test audit_logs|action_logs|both] [--json]',
    '',
    'Default mode is read-only and prints redacted credential diagnostics plus REST table probe status.',
    '--write-test inserts a tiny probe log row to verify RLS/write policy. It does not print secrets.'
  ].join('\n')
}

function loadEnvFile (filePath) {
  const fullPath = path.resolve(process.cwd(), filePath)
  if (!fs.existsSync(fullPath)) return {}

  const env = {}
  const lines = fs.readFileSync(fullPath, 'utf8').split(/\r?\n/)
  for (const line of lines) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/)
    if (!match) continue
    let value = match[2].trim()
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1)
    }
    env[match[1]] = value
  }
  return env
}

function describeSupabaseKey (key) {
  if (!key) return { present: false, format: 'missing', role: null, length: 0 }
  if (key.startsWith('sb_secret_')) return { present: true, format: 'supabase_secret', role: 'service_role', length: key.length }
  if (key.startsWith('sb_publishable_')) return { present: true, format: 'supabase_publishable', role: 'anon', length: key.length }
  if (!key.includes('.')) return { present: true, format: 'opaque', role: null, length: key.length }

  try {
    const [, payload] = key.split('.')
    const normalized = payload.replace(/-/g, '+').replace(/_/g, '/')
    const decoded = JSON.parse(Buffer.from(normalized, 'base64').toString('utf8'))
    return { present: true, format: 'jwt', role: decoded.role || null, length: key.length }
  } catch (_) {
    return { present: true, format: 'unknown', role: null, length: key.length }
  }
}

function requestSupabase ({ baseUrl, key, method, restPath, payload = null, prefer = 'return=minimal' }) {
  return new Promise((resolve) => {
    const url = new URL(restPath, baseUrl)
    const body = payload ? JSON.stringify(payload) : null
    const req = https.request({
      hostname: url.hostname,
      port: url.port || 443,
      path: `${url.pathname}${url.search}`,
      method,
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
        Prefer: prefer,
        ...(body ? { 'Content-Length': Buffer.byteLength(body) } : {})
      }
    }, (res) => {
      let data = ''
      res.on('data', chunk => { data += chunk })
      res.on('end', () => {
        resolve({
          ok: res.statusCode >= 200 && res.statusCode < 300,
          status: res.statusCode,
          body: data.slice(0, 800)
        })
      })
    })
    req.on('error', err => resolve({ ok: false, status: 0, body: err.message }))
    if (body) req.write(body)
    req.end()
  })
}

function probePayload (table) {
  const now = new Date().toISOString()
  const probeId = `neo-supabase-probe-${Date.now()}`
  if (table === 'audit_logs') {
    return {
      actor_type: 'ai_system',
      action: 'supabase.mirror_probe',
      target_id: null,
      target_type: 'system',
      detail: { probe_id: probeId, source: 'Check-SupabaseMirror.js' },
      created_at: now
    }
  }
  return {
    source: 'system',
    action_type: 'supabase.mirror_probe',
    details: { probe_id: probeId, source: 'Check-SupabaseMirror.js' },
    status: 'success',
    summary: 'NeoOptimize Supabase mirror probe',
    created_at: now
  }
}

async function main () {
  const args = parseArgs(process.argv.slice(2))
  if (args.help) {
    console.log(usage())
    return
  }

  const fileEnv = loadEnvFile(args.env)
  const env = { ...fileEnv, ...process.env }
  const baseUrl = env.SUPABASE_URL
  const keySource = env.SUPABASE_SERVICE_ROLE_KEY
    ? 'SUPABASE_SERVICE_ROLE_KEY'
    : env.SUPABASE_SERVICE_KEY
      ? 'SUPABASE_SERVICE_KEY'
      : env.SUPABASE_ANON_KEY
        ? 'SUPABASE_ANON_KEY'
        : null
  const key = env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY
  const keyInfo = describeSupabaseKey(key)

  const report = {
    env_file: path.resolve(process.cwd(), args.env),
    supabase_url_present: !!baseUrl,
    key_source: keySource,
    key_info: keyInfo,
    read_only: !args.writeTest,
    probes: []
  }

  if (!baseUrl || !key) {
    report.error = 'SUPABASE_URL and a service key are required'
    printReport(report, args.json)
    process.exitCode = 1
    return
  }

  if (keySource === 'SUPABASE_ANON_KEY' || keyInfo.role === 'anon') {
    report.warning = 'Anon/publishable keys are not suitable for RMM mirror writes behind RLS'
  }

  for (const table of ['audit_logs', 'action_logs']) {
    const readProbe = await requestSupabase({
      baseUrl,
      key,
      method: 'GET',
      restPath: `/rest/v1/${table}?select=*&limit=0`
    })
    report.probes.push({ table, mode: 'read_schema', ...readProbe })
  }

  if (args.writeTest) {
    const tables = args.writeTest === 'both' ? ['audit_logs', 'action_logs'] : [args.writeTest]
    for (const table of tables) {
      if (!['audit_logs', 'action_logs'].includes(table)) {
        report.probes.push({ table, mode: 'write_probe', ok: false, status: 0, body: 'Unknown table for write test' })
        continue
      }
      const writeProbe = await requestSupabase({
        baseUrl,
        key,
        method: 'POST',
        restPath: `/rest/v1/${table}`,
        payload: probePayload(table)
      })
      report.probes.push({ table, mode: 'write_probe', ...writeProbe })
    }
  }

  printReport(report, args.json)
  const failures = report.probes.filter(probe => !probe.ok && !isAcceptableMissingAuditLog(probe))
  if (failures.length > 0) process.exitCode = 1
}

function isAcceptableMissingAuditLog (probe) {
  return probe.table === 'audit_logs' &&
    probe.status === 404 &&
    /PGRST205|Could not find the table/i.test(probe.body || '')
}

function printReport (report, json) {
  if (json) {
    console.log(JSON.stringify(report, null, 2))
    return
  }

  console.log('Supabase Mirror Probe')
  console.log(`Env file: ${report.env_file}`)
  console.log(`SUPABASE_URL present: ${report.supabase_url_present}`)
  console.log(`Key source: ${report.key_source || 'missing'}`)
  console.log(`Key format: ${report.key_info.format}; role: ${report.key_info.role || 'unknown'}; length: ${report.key_info.length}`)
  if (report.warning) console.log(`Warning: ${report.warning}`)
  if (report.error) console.log(`Error: ${report.error}`)
  console.log(`Mode: ${report.read_only ? 'read-only' : 'write-test enabled'}`)

  for (const probe of report.probes) {
    const body = probe.ok ? '' : ` body=${JSON.stringify(probe.body)}`
    console.log(`${probe.ok ? 'OK' : 'FAIL'} ${probe.table} ${probe.mode}: HTTP ${probe.status}${body}`)
  }
}

main().catch(err => {
  console.error(err.stack || err.message)
  process.exit(1)
})
