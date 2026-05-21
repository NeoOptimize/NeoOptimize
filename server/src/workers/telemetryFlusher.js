'use strict'

// ═══════════════════════════════════════════════════════════════════
// TELEMETRY FLUSHER — Redis Buffer → PostgreSQL
// Batch writes every 10s — prevents per-row DB writes at scale
// ═══════════════════════════════════════════════════════════════════

const FLUSH_INTERVAL = 10000   // 10 seconds
const BATCH_SIZE     = 500     // rows per flush

function start (app) {
  const { db, redis, log } = app

  setInterval(async () => {
    try {
      // Get all tenant telemetry buffer keys
      const keys = await redis.keys('telemetry:buffer:*')
      for (const key of keys) {
        await flushBuffer(db, redis, key, log)
      }
    } catch (err) {
      log.error({ err }, 'telemetryFlusher error')
    }
  }, FLUSH_INTERVAL)

  log.info('Telemetry flusher started')
}

async function flushBuffer (db, redis, key, log) {
  // Atomically pop batch from right (oldest entries)
  const batch = await redis.lrange(key, -BATCH_SIZE, -1)
  if (!batch.length) return

  // Parse rows
  const rows = batch.map(r => {
    try { return JSON.parse(r) } catch { return null }
  }).filter(Boolean)

  if (!rows.length) return

  // Build bulk INSERT with unnest for efficiency
  const agentIds    = rows.map(r => r.agent_id)
  const tenantIds   = rows.map(r => r.tenant_id)
  const cpus        = rows.map(r => r.cpu_pct)
  const rams        = rows.map(r => r.ram_used_mb)
  const disks       = rows.map(r => r.disk_free_gb)
  const rxs         = rows.map(r => r.net_rx_kbps)
  const txs         = rows.map(r => r.net_tx_kbps)
  const publicIps   = rows.map(r => r.public_ip || null)
  const locations   = rows.map(r => r.location_label || null)
  const locationDetails = rows.map(r => JSON.stringify(r.location_detail || {}))
  const cameras     = rows.map(r => r.camera_available ?? null)
  const microphones = rows.map(r => r.microphone_available ?? null)
  const biometrics  = rows.map(r => r.biometric_available ?? null)
  const devices     = rows.map(r => JSON.stringify(r.device_info || {}))
  const bugs        = rows.map(r => JSON.stringify(r.bugs || {}))
  const verboseInfo = rows.map(r => JSON.stringify(r.verbose_info || r.verbose || {}))
  const extras      = rows.map(r => JSON.stringify(r.extra || {}))
  const tss         = rows.map(r => r.ts)

  try {
    await db.query(`
      INSERT INTO telemetry
        (agent_id, tenant_id, ts, cpu_pct, ram_used_mb, disk_free_gb, net_rx_kbps, net_tx_kbps,
         public_ip, location_label, location_detail, camera_available, microphone_available,
         biometric_available, device_info, bugs, verbose_info, extra)
      SELECT * FROM unnest(
        $1::uuid[], $2::uuid[], $3::timestamptz[],
        $4::float4[], $5::int[], $6::float4[], $7::float4[], $8::float4[],
        $9::varchar[], $10::varchar[], $11::jsonb[], $12::boolean[], $13::boolean[],
        $14::boolean[], $15::jsonb[], $16::jsonb[], $17::jsonb[], $18::jsonb[]
      )`,
      [
        agentIds, tenantIds, tss, cpus, rams, disks, rxs, txs,
        publicIps, locations, locationDetails, cameras, microphones,
        biometrics, devices, bugs, verboseInfo, extras
      ]
    )

    // Remove flushed items from buffer (trim from right)
    await redis.ltrim(key, 0, -(BATCH_SIZE + 1))

    log.debug({ key, count: rows.length }, 'Telemetry flushed to DB')
  } catch (err) {
    log.error({ err, key }, 'Failed to flush telemetry batch')
  }
}

module.exports = { start }
