#!/usr/bin/env node
'use strict'

const fs = require('fs')
const https = require('https')
const path = require('path')

const ROOT = path.resolve(__dirname, '..')
const args = parseArgs(process.argv.slice(2))
const env = { ...loadEnv(path.join(ROOT, args.env || 'server/.env')), ...process.env }
const queueDir = path.resolve(ROOT, args.queue || env.SUPABASE_MIRROR_QUEUE_DIR || 'reports/supabase_mirror_queue')
const baseUrl = env.SUPABASE_URL
const key = env.SUPABASE_SERVICE_ROLE_KEY || env.SUPABASE_SERVICE_KEY

main().catch(err => {
  console.error(`[FAIL] ${err.message}`)
  process.exitCode = 1
})

async function main () {
  if (!baseUrl || !key) {
    throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required to flush queued mirror logs.')
  }
  if (!fs.existsSync(queueDir)) {
    console.log(`[OK] Queue directory not found: ${queueDir}`)
    return
  }

  const files = fs.readdirSync(queueDir)
    .filter(name => name.endsWith('.jsonl'))
    .sort()

  let flushed = 0
  let failed = 0
  for (const name of files) {
    const file = path.join(queueDir, name)
    const retryLines = []
    for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
      if (!line.trim()) continue
      let item
      try {
        item = JSON.parse(line)
      } catch {
        retryLines.push(line)
        failed++
        continue
      }

      const table = item.table
      if (!['audit_logs', 'action_logs', 'security_alerts'].includes(table)) {
        retryLines.push(line)
        failed++
        continue
      }
      let targetTable = table
      let targetPayload = item.payload
      if (table === 'action_logs') {
        targetPayload = normalizeActionLogPayload(targetPayload)
      }

      const res = await requestSupabase({
        baseUrl,
        key,
        method: 'POST',
        restPath: `/rest/v1/${targetTable}`,
        payload: targetPayload
      })

      if (res.ok) {
        flushed++
      } else if (table === 'audit_logs' && isMissingTable(res)) {
        targetTable = 'action_logs'
        targetPayload = normalizeActionLogPayload({
          source: 'system',
          action_type: item.payload?.action || 'audit',
          details: item.payload || {},
          created_at: item.payload?.created_at
        })
        const fallback = await requestSupabase({
          baseUrl,
          key,
          method: 'POST',
          restPath: '/rest/v1/action_logs',
          payload: targetPayload
        })
        if (fallback.ok) {
          flushed++
        } else {
          item.last_error = `HTTP ${fallback.status}: ${fallback.body}`
          retryLines.push(JSON.stringify(item))
          failed++
        }
      } else {
        item.last_error = `HTTP ${res.status}: ${res.body}`
        retryLines.push(JSON.stringify(item))
        failed++
      }
    }

    if (retryLines.length === 0) {
      fs.unlinkSync(file)
    } else {
      fs.writeFileSync(file, retryLines.join('\n') + '\n')
    }
  }

  console.log(JSON.stringify({ ok: failed === 0, queue_dir: queueDir, flushed, failed }, null, 2))
  if (failed > 0) process.exitCode = 1
}

function normalizeActionLogPayload (payload = {}) {
  return {
    ...payload,
    source: payload.source || 'system',
    action_type: payload.action_type || payload.action || 'mirror.payload',
    details: payload.details || payload.detail || payload,
    status: payload.status || 'success',
    summary: payload.summary || payload.action_type || payload.action || payload.source || 'NeoOptimize queued mirror payload'
  }
}

function isMissingTable (res) {
  return res.status === 404 && /PGRST205|Could not find the table/i.test(res.body || '')
}

function requestSupabase ({ baseUrl, key, method, restPath, payload }) {
  return new Promise((resolve) => {
    const url = new URL(restPath, baseUrl)
    const body = JSON.stringify(payload)
    const req = https.request({
      hostname: url.hostname,
      port: url.port || 443,
      path: `${url.pathname}${url.search}`,
      method,
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
        Prefer: 'return=minimal',
        'Content-Length': Buffer.byteLength(body)
      }
    }, (res) => {
      let data = ''
      res.on('data', chunk => { data += chunk })
      res.on('end', () => resolve({
        ok: res.statusCode >= 200 && res.statusCode < 300,
        status: res.statusCode,
        body: data.slice(0, 800)
      }))
    })
    req.on('error', err => resolve({ ok: false, status: 0, body: err.message }))
    req.write(body)
    req.end()
  })
}

function loadEnv (file) {
  if (!fs.existsSync(file)) return {}
  const out = {}
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#')) continue
    const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/)
    if (!match) continue
    let value = match[2].trim()
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1)
    }
    out[match[1]] = value
  }
  return out
}

function parseArgs (argv) {
  const out = {}
  for (let i = 0; i < argv.length; i++) {
    const item = argv[i]
    if (!item.startsWith('--')) continue
    const key = item.slice(2)
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
