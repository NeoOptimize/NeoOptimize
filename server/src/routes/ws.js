'use strict'

// ═══════════════════════════════════════════════════════════════════
// WEBSOCKET ROUTE — Real-time Dashboard Bridge v6.0
// [BUG-S03 FIX] Uses fastify.verifyToken (properly decorated in index.js)
// [BUG-S06 FIX] Strict per-tenant isolation on broadcast
// ═══════════════════════════════════════════════════════════════════

const IORedis = require('ioredis')

let subscriber   = null
let subscriberReady = false

async function wsRoutes (fastify, opts) {
  // Connected dashboard clients: Map<tenantId, Set<WebSocket>>
  const clients = new Map()

  // ── Redis pub/sub channels ─────────────────────────────────────
  const CHANNELS = [
    'agent:online', 'agent:offline', 'agent:uninstalled',
    'cmd:result', 'tele:update', 'alert:new', 'health:update'
  ]

  async function ensureSubscriber () {
    if (subscriberReady || subscriber?.status === 'connecting') return

    if (!subscriber) {
      subscriber = new IORedis(process.env.REDIS_URL, {
        password:      process.env.REDIS_PASSWORD,
        lazyConnect:   true,
        retryStrategy: (times) => Math.min(times * 100, 5000)
      })

      subscriber.on('message', (channel, message) => {
        try {
          const data = JSON.parse(message)

          // [BUG-S06 FIX] Strict tenant isolation — broadcast ONLY to matching tenant
          const tenantId = data.tenant_id || data.tenantId

          if (tenantId) {
            // Send only to the specific tenant's clients
            const sockets = clients.get(tenantId)
            if (sockets) {
              for (const ws of sockets) {
                if (ws.readyState === ws.OPEN) {
                  ws.send(JSON.stringify({ event: channel, data }))
                }
              }
            }
          } else {
            // Broadcast to all (only for non-tenant-specific events like server alerts)
            for (const [, sockets] of clients) {
              for (const ws of sockets) {
                if (ws.readyState === ws.OPEN) {
                  ws.send(JSON.stringify({ event: channel, data }))
                }
              }
            }
          }
        } catch (err) {
          fastify.log.warn({ err, channel }, 'WS broadcast error')
        }
      })

      subscriber.on('error', (err) => {
        fastify.log.warn({ err }, 'WS Redis subscriber error')
        subscriberReady = false
      })

      subscriber.on('ready', () => { subscriberReady = true })
    }

    try {
      await subscriber.connect()
      await subscriber.subscribe(...CHANNELS)
      subscriberReady = true
    } catch (err) {
      fastify.log.warn({ err }, 'WS Redis subscriber unavailable — realtime updates will retry')
      subscriberReady = false
    }
  }

  fastify.addHook('onClose', async () => {
    subscriberReady = false
    subscriber?.disconnect()
  })

  // ── WebSocket Endpoint ─────────────────────────────────────────
  fastify.get('/stream', { websocket: true }, async (connection, req) => {
    const ws = connection.socket || connection
    await ensureSubscriber()

    // [BUG-S03 FIX] Use fastify.verifyToken (properly decorated via @fastify/jwt)
    let user
    try {
      const token = req.query.token
      if (!token) throw new Error('No token provided')
      user = fastify.verifyToken(token)  // ← now works correctly
    } catch (err) {
      ws.send(JSON.stringify({ event: 'error', data: { message: 'Unauthorized', detail: err.message } }))
      ws.close(1008, 'Unauthorized')
      return
    }

    const tenantId = user.tenantId

    // Register client under their tenant
    if (!clients.has(tenantId)) clients.set(tenantId, new Set())
    clients.get(tenantId).add(ws)

    fastify.log.info({ userId: user.sub, tenantId, role: user.role }, 'WS client connected')

    // Send welcome + current stats
    try {
      const { rows: summary } = await fastify.db.query(
        `SELECT status, COUNT(*)::int as count FROM agents WHERE tenant_id = $1 GROUP BY status`,
        [tenantId]
      )
      const { rows: alertCount } = await fastify.db.query(
        `SELECT COUNT(*)::int as count FROM security_alerts WHERE tenant_id = $1 AND resolved = FALSE`,
        [tenantId]
      )
      ws.send(JSON.stringify({
        event: 'connected',
        data: {
          user: { email: user.email, role: user.role },
          summary,
          unresolved_alerts: alertCount[0]?.count || 0
        }
      }))
    } catch (err) {
      fastify.log.warn({ err }, 'WS welcome query failed')
    }

    // ── Heartbeat ──────────────────────────────────────────────
    const heartbeatInterval = parseInt(process.env.WS_HEARTBEAT_INTERVAL || '25000')
    const heartbeat = setInterval(() => {
      if (ws.readyState === ws.OPEN) ws.ping()
    }, heartbeatInterval)

    // ── Incoming messages from dashboard ──────────────────────
    ws.on('message', async (rawMsg) => {
      try {
        const msg = JSON.parse(rawMsg.toString())

        if (msg.event === 'ping') {
          ws.send(JSON.stringify({ event: 'pong', data: { ts: Date.now() } }))
          return
        }

        if (msg.event === 'subscribe:agent' && msg.data?.agent_id) {
          // Send latest cached telemetry for requested agent
          const tele = await fastify.redis.get(`agent:tele:${msg.data.agent_id}`)
          if (tele) {
            ws.send(JSON.stringify({ event: 'tele:snapshot', data: { agent_id: msg.data.agent_id, ...JSON.parse(tele) } }))
          }
        }
      } catch { /* ignore malformed */ }
    })

    // ── Cleanup on disconnect ──────────────────────────────────
    ws.on('close', () => {
      clearInterval(heartbeat)
      clients.get(tenantId)?.delete(ws)
      if (clients.get(tenantId)?.size === 0) clients.delete(tenantId)
      fastify.log.info({ userId: user.sub, tenantId }, 'WS client disconnected')
    })

    ws.on('error', (err) => {
      fastify.log.warn({ err }, 'WS socket error')
    })
  })
}

module.exports = wsRoutes
