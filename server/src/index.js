'use strict'
require('dotenv').config()

const path     = require('path')
const fs       = require('fs')
const crypto   = require('crypto')
const bcrypt   = require('bcryptjs')
const { z }    = require('zod')
const Fastify  = require('fastify')
const { db }   = require('./db/postgres')
const redis    = require('./db/redis')
const { addSecurityHeaders, rateLimitKeyGenerator } = require('./middleware/security')
const { writeAuditLog } = require('./middleware/security')
const { supabase, telegram, AgentWatchdog } = require('./lib/integrations')
const { requireJwtSecret } = require('./security/tokens')
const signing = require('./security/signing')
const scheduler = require('./workers/scheduler')
const { getProductInfo } = require('./lib/productInfo')

// Dashboard static files path (serve built React app from port 3000)
const DASHBOARD_DIST = path.join(__dirname, '../../dashboard/dist')
const PROGRAM_INSTALLER = path.join(__dirname, '../../program/NeoOptimize.exe')
const RELEASE_INSTALLER = path.join(__dirname, '../../release/NeoOptimize.exe')

function resolveInstallerPath () {
  if (process.env.NEOOPTIMIZE_INSTALLER_PATH) return process.env.NEOOPTIMIZE_INSTALLER_PATH
  if (fs.existsSync(PROGRAM_INSTALLER)) return PROGRAM_INSTALLER
  return RELEASE_INSTALLER
}

const PRODUCT = getProductInfo()
const UpdateSessionSchema = z.object({
  email: z.string().email().max(255),
  password: z.string().min(8).max(128)
})

function absolutePublicUrl (req, targetPath) {
  const proto = req.headers['x-forwarded-proto'] || req.protocol || 'http'
  const host = req.headers['x-forwarded-host'] || req.headers.host || '127.0.0.1:3000'
  return `${proto}://${host}${targetPath}`
}

function buildUpdatePackageManifest (req, updateToken = '') {
  const installerPath = resolveInstallerPath()
  if (!fs.existsSync(installerPath)) {
    const err = new Error('NeoOptimize installer not found')
    err.statusCode = 404
    throw err
  }

  const buf = fs.readFileSync(installerPath)
  const sha256 = crypto.createHash('sha256').update(buf).digest('hex')
  const updateId = crypto
    .createHash('sha256')
    .update(`${PRODUCT.version}|${sha256}|NeoOptimize.exe`)
    .digest('hex')
    .slice(0, 32)
  const issuedAt = new Date()
  const expiresAt = new Date(issuedAt.getTime() + 15 * 60 * 1000)
  const installerUrl = '/downloads/neooptimize/installer'
  const manifest = {
    schema_version: '2.0',
    update_id: updateId,
    name: 'NeoOptimize',
    version: PRODUCT.version,
    release_channel: PRODUCT.release_channel,
    file: 'NeoOptimize.exe',
    bytes: buf.length,
    sha256,
    sha256_algorithm: 'SHA-256',
    installer_sha256: sha256,
    package_sha256: sha256,
    url: installerUrl,
    installer_url: installerUrl,
    absolute_installer_url: absolutePublicUrl(req, installerUrl),
    public_download_url: '/downloads/NeoOptimize.exe',
    silent_args: process.env.NEOOPTIMIZE_INSTALLER_SILENT_ARGS || '/S',
    command: 'NEOUPDATE',
    requires_credentials: true,
    credential_flow: {
      session_url: '/api/v1/update/session',
      token_type: 'Bearer',
      scope: 'neo_update',
      expires_in_seconds: 900
    },
    integrity: {
      algorithm: 'SHA-256',
      expected_sha256: sha256,
      reject_on_mismatch: true,
      authenticode_required: process.env.NEOOPTIMIZE_REQUIRE_AUTHENTICODE === 'true'
    },
    repair: {
      auto_repair: true,
      repair_args: process.env.NEOOPTIMIZE_INSTALLER_REPAIR_ARGS || '/S /REPAIR=1',
      critical_paths: [
        'program/NeoOptimize.exe',
        'program/NeoOptimize.UI.ps1',
        'program/NeoOptimize.ps1',
        'program/NeoOptimize.UpdateManager.ps1',
        'agent/NeoOptimize.Agent.exe'
      ]
    },
    issued_at: issuedAt.toISOString(),
    expires_at: expiresAt.toISOString()
  }

  if (updateToken) manifest.update_token = updateToken
  manifest.signature_algorithm = 'RSA-SHA256'
  manifest.signature = signing.signCommand(updateId, 'NEOUPDATE', manifest)
  return manifest
}

// Fastify logger config (pino-compatible object)
const loggerConfig = {
  level: process.env.LOG_LEVEL || 'info',
  transport: process.env.NODE_ENV !== 'production'
    ? { target: 'pino-pretty', options: { colorize: true, translateTime: 'SYS:standard', ignore: 'pid,hostname' } }
    : undefined
}

async function buildApp () {
  const jwtSecret = requireJwtSecret()
  const app = Fastify({
    logger: loggerConfig,
    trustProxy: true,
    bodyLimit: parseInt(process.env.BODY_LIMIT_BYTES || '1048576'),
    genReqId: () => require('crypto').randomUUID()
  })

  // ── Security Headers ──────────────────────────────────────────
  app.addHook('onSend', async (req, reply) => { await addSecurityHeaders(req, reply) })

  // ── CORS ──────────────────────────────────────────────────────
  await app.register(require('@fastify/cors'), {
    origin: (origin, cb) => {
      const allowed = [
        'http://localhost:5173', 'http://localhost:4173',
        'http://localhost:3000', 'http://127.0.0.1:3000',
        'https://localhost', 'https://neooptimize.duckdns.org',
        process.env.DASHBOARD_ORIGIN
      ].filter(Boolean)
      if (!origin || allowed.some(o => origin === o) || process.env.NODE_ENV !== 'production') {
        return cb(null, true)
      }
      cb(new Error('Not allowed by CORS'))
    },
    credentials: true
  })

  // ── Rate Limiting ─────────────────────────────────────────────
  await app.register(require('@fastify/rate-limit'), {
    global: true,
    max: parseInt(process.env.RATE_LIMIT_MAX || '200'),
    timeWindow: parseInt(process.env.RATE_LIMIT_WINDOW_MS || '60000'),
    keyGenerator: rateLimitKeyGenerator
  })

  // ── JWT ───────────────────────────────────────────────────────
  await app.register(require('@fastify/jwt'), {
    secret: jwtSecret,
    sign: { expiresIn: process.env.JWT_EXPIRES_IN || '8h' }
  })

  // ── WebSocket ─────────────────────────────────────────────────
  await app.register(require('@fastify/websocket'), {
    options: { maxPayload: 1048576 }
  })

  // ── Decorators ────────────────────────────────────────────────
  app.decorate('db',    db)
  app.decorate('redis', redis)

  app.addHook('onClose', async () => {
    await db.end().catch(() => {})
    redis.disconnect()
    redis.publisher?.disconnect()
  })

  // [BUG-S04 FIX] Register signToken using @fastify/jwt
  app.decorate('signToken', function (payload) {
    return this.jwt.sign(payload)
  })

  // [BUG-S03 FIX] Register verifyToken using @fastify/jwt
  app.decorate('verifyToken', function (token) {
    return this.jwt.verify(token)
  })

  app.decorate('authenticate', async function (req, reply) {
    try {
      await req.jwtVerify()
    } catch {
      return reply.code(401).send({ error: 'Unauthorized' })
    }
  })

  app.decorate('authenticateUpdateAccess', async function (req, reply) {
    try {
      await req.jwtVerify()
      if (req.user?.scope === 'neo_update' || req.user?.role) return
    } catch {}
    return reply.code(401).send({ error: 'Update credentials required' })
  })

  app.setErrorHandler((err, req, reply) => {
    if (err?.name === 'ZodError') {
      return reply.code(400).send({ error: 'Validation error' })
    }
    if (err?.code === '22P02') {
      return reply.code(400).send({ error: 'Invalid identifier or query value' })
    }
    if (err?.code === '23505') {
      return reply.code(409).send({ error: 'Duplicate record' })
    }
    req.log.error({ err }, 'request failed')
    return reply.code(err.statusCode || 500).send({ error: err.expose ? err.message : 'Internal server error' })
  })

  // ── Routes ────────────────────────────────────────────────────
  app.register(require('./routes/agent'),     { prefix: '/api/v1/agent' })
  app.register(require('./routes/dashboard'), { prefix: '/api/v1/dashboard' })
  app.register(require('./routes/auth'),      { prefix: '/api/v1/auth' })
  app.register(require('./routes/ws'),        { prefix: '/ws' })

  // ── Health Check ──────────────────────────────────────────────
  app.get('/health', { logLevel: 'warn' }, async () => {
    const pgOk    = await db.query('SELECT 1').then(() => true).catch(() => false)
    const redisOk = await redis.ping().then(r => r === 'PONG').catch(() => false)
    return {
      status:   pgOk && redisOk ? 'ok' : 'degraded',
      postgres: pgOk,
      redis:    redisOk,
      uptime:   process.uptime(),
      version:  PRODUCT.version,
      release_channel: PRODUCT.release_channel
    }
  })

  // ── Version ───────────────────────────────────────────────────
  app.get('/version', { logLevel: 'silent' }, async () => ({
    name: PRODUCT.name,
    version: PRODUCT.version,
    build: PRODUCT.build,
    release_channel: PRODUCT.release_channel
  }))

  // ── Secure Update Session ──────────────────────────────────────
  app.post('/api/v1/update/session', {
    config: { rateLimit: { max: 8, timeWindow: '1m' } }
  }, async (req, reply) => {
    let body
    try {
      body = UpdateSessionSchema.parse(req.body || {})
    } catch {
      return reply.code(400).send({ error: 'Invalid update credentials' })
    }

    const { rows } = await db.query(
      `SELECT u.id, u.email, u.password_hash, u.role, u.is_active, u.tenant_id, t.plan, t.name as tenant_name
       FROM users u JOIN tenants t ON u.tenant_id = t.id
       WHERE u.email = $1`,
      [body.email]
    )
    if (!rows.length || !rows[0].is_active) {
      await writeAuditLog(db, { action: 'update.session.failed', detail: { email: body.email, reason: 'not_found' }, ip: req.ip })
      return reply.code(401).send({ error: 'Invalid update credentials' })
    }

    const user = rows[0]
    if (!['admin', 'operator'].includes(user.role)) {
      await writeAuditLog(db, { actor_id: user.id, actor_type: 'user', action: 'update.session.denied', detail: { role: user.role }, ip: req.ip })
      return reply.code(403).send({ error: 'Update permission denied' })
    }

    const valid = await bcrypt.compare(body.password, user.password_hash)
    if (!valid) {
      await writeAuditLog(db, { actor_id: user.id, actor_type: 'user', action: 'update.session.failed', detail: { reason: 'bad_password' }, ip: req.ip })
      return reply.code(401).send({ error: 'Invalid update credentials' })
    }

    const token = app.jwt.sign({
      sub: user.id,
      email: user.email,
      role: user.role,
      tenantId: user.tenant_id,
      tenantName: user.tenant_name,
      plan: user.plan,
      scope: 'neo_update',
      token_type: 'update'
    }, { expiresIn: '15m' })

    await writeAuditLog(db, { actor_id: user.id, actor_type: 'user', action: 'update.session.created', ip: req.ip })
    return reply.send({
      token,
      token_type: 'Bearer',
      expires_in: 900,
      scope: 'neo_update',
      manifest_url: '/downloads/neooptimize/manifest',
      installer_url: '/downloads/neooptimize/installer'
    })
  })

  // ── RMM Update Package ─────────────────────────────────────────
  app.get('/downloads/neooptimize/manifest', { preHandler: app.authenticateUpdateAccess }, async (req, reply) => {
    const updateToken = app.jwt.sign({
      sub: req.user?.sub,
      email: req.user?.email,
      role: req.user?.role,
      tenantId: req.user?.tenantId,
      scope: 'neo_update',
      token_type: 'update-download'
    }, { expiresIn: '15m' })
    return reply.send(buildUpdatePackageManifest(req, updateToken))
  })

  app.get('/downloads/neooptimize/installer', { preHandler: app.authenticateUpdateAccess }, async (req, reply) => {
    const installerPath = resolveInstallerPath()
    if (!fs.existsSync(installerPath)) {
      return reply.code(404).send({ error: 'NeoOptimize installer not found' })
    }
    return reply
      .type('application/vnd.microsoft.portable-executable')
      .header('Cache-Control', 'no-store')
      .header('Content-Disposition', 'attachment; filename="NeoOptimize.exe"')
      .send(fs.createReadStream(installerPath))
  })

  // Public bootstrap download. Secure updates use /downloads/neooptimize/installer.
  app.get('/downloads/NeoOptimize.exe', async (req, reply) => {
    const installerPath = resolveInstallerPath()
    if (!fs.existsSync(installerPath)) {
      return reply.code(404).send({ error: 'NeoOptimize installer not found' })
    }
    return reply
      .type('application/vnd.microsoft.portable-executable')
      .header('Cache-Control', 'no-store')
      .header('Content-Disposition', 'attachment; filename="NeoOptimize.exe"')
      .send(fs.createReadStream(installerPath))
  })

  // ── Serve React Dashboard (SPA) ──────────────────────────────
  if (fs.existsSync(DASHBOARD_DIST)) {
    await app.register(require('@fastify/static'), {
      root:   DASHBOARD_DIST,
      prefix: '/'
    })

    // SPA fallback — all non-API, non-asset routes return index.html
    const indexHtml = fs.readFileSync(path.join(DASHBOARD_DIST, 'index.html'))
    app.setNotFoundHandler(async (req, reply) => {
      if (req.url.startsWith('/api/') || req.url.startsWith('/ws/')) {
        return reply.code(404).send({ error: 'Not Found', statusCode: 404 })
      }
      return reply.code(200).type('text/html').send(indexHtml)
    })

    app.log.info(`[Static] Dashboard served from ${DASHBOARD_DIST}`)
  } else {
    app.get('/', async () => ({
      name:      'NeoOptimize System Optimizer API v1.0',
      status:    'running',
      dashboard: 'Build dashboard: cd dashboard && npm run build',
    }))
  }

  return app
}

async function start () {
  const app  = await buildApp()
  const port = parseInt(process.env.PORT || '3000')
  const host = process.env.HOST || '0.0.0.0'

  await app.listen({ port, host })
  app.log.info(`NeoOptimize System Optimizer v${PRODUCT.version} listening on ${host}:${port}`)

  // ── Background Services ───────────────────────────────────────
  new AgentWatchdog(db, telegram)
  app.log.info('[Watchdog] Agent offline monitor started')

  // [NEW] Scheduled task runner
  await scheduler.start(db, app)
  app.log.info('[Scheduler] Task scheduler started')

  await telegram._send('🟢 *NeoMonitor v1.0 Online*\nAll systems operational.').catch(() => {})
  await supabase.mirrorAuditLog({
    action: 'server.start',
    actor_type: 'system',
    detail: { version: PRODUCT.version, release_channel: PRODUCT.release_channel },
    created_at: new Date().toISOString()
  }).catch(() => {})
}

if (require.main === module) {
  start().catch(err => {
    console.error(err)
    process.exit(1)
  })
}

module.exports = { buildApp, start }
