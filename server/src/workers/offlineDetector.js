'use strict'

// ═══════════════════════════════════════════════════════════════════
// OFFLINE DETECTOR WORKER
// Marks agents offline after N missed check-ins
// ═══════════════════════════════════════════════════════════════════

function start (app) {
  const { db, log } = app
  const THRESHOLD   = parseInt(process.env.AGENT_OFFLINE_THRESHOLD || '2')
  const INTERVAL    = parseInt(process.env.AGENT_CHECKIN_INTERVAL || '30')
  const UNINSTALLED_DELETE_DAYS = parseInt(process.env.AGENT_AUTO_DELETE_UNINSTALLED_DAYS || '7')

  setInterval(async () => {
    try {
      // Agents not seen in (THRESHOLD * INTERVAL + 30s) buffer
      const window = THRESHOLD * INTERVAL + 30

      const { rowCount } = await db.query(`
        UPDATE agents
        SET status = 'offline', missed_checkins = missed_checkins + 1
        WHERE status = 'online'
          AND last_seen < NOW() - ($1 || ' seconds')::interval`,
        [window]
      )

      if (rowCount > 0) {
        log.warn({ count: rowCount }, 'Agents marked offline')
      }

      if (UNINSTALLED_DELETE_DAYS > 0) {
        const deleted = await db.query(`
          DELETE FROM agents
          WHERE status = 'uninstalled'
            AND COALESCE(last_seen, first_seen) < NOW() - ($1 || ' days')::interval
          RETURNING id, hostname, tenant_id`,
          [UNINSTALLED_DELETE_DAYS]
        )

        if (deleted.rowCount > 0) {
          log.info({
            count: deleted.rowCount,
            days: UNINSTALLED_DELETE_DAYS,
            agents: deleted.rows.map(row => ({ id: row.id, hostname: row.hostname }))
          }, 'Auto-deleted uninstalled agent records')
        }
      }
    } catch (err) {
      log.error({ err }, 'offlineDetector error')
    }
  }, INTERVAL * 1000)

  log.info(`Offline detector started (threshold: ${THRESHOLD} missed check-ins, uninstall auto-delete: ${UNINSTALLED_DELETE_DAYS} day(s))`)
}

module.exports = { start }
