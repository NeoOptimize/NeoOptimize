'use strict'

// ─── Auth Routes — Enterprise Grade with Brute-Force + Redis Protection ──
const bcrypt  = require('bcryptjs')
const { z }   = require('zod')
const { checkBruteForce, recordFailedAttempt, resetAttempts, writeAuditLog } = require('../middleware/security')

const LoginSchema = z.object({
  email:    z.string().email().max(255),
  password: z.string().min(8).max(128)
})

const ChangePasswordSchema = z.object({
  current_password: z.string().min(8).max(128),
  new_password: z.string().min(10).max(128)
    .regex(/[A-Z]/, 'Must contain uppercase')
    .regex(/[0-9]/, 'Must contain number')
    .regex(/[^A-Za-z0-9]/, 'Must contain special char')
})

async function authRoutes (fastify, opts) {

  // ─── LOGIN ──────────────────────────────────────────────────────
  // [BUG-S04 FIX] Uses fastify.signToken (now properly decorated in index.js)
  fastify.post('/login', {
    config: { rateLimit: { max: 20, timeWindow: '1m' } }
  }, async (req, reply) => {
    const ip = req.ip

    // Check brute-force lockout (now Redis-backed)
    const lockout = await checkBruteForce(fastify.redis, ip)
    if (lockout.blocked) {
      await writeAuditLog(fastify.db, { action: 'login.blocked', detail: { ip }, ip })
      return reply.code(429).send({
        error: `Too many failed attempts. Try again in ${lockout.remaining}s`
      })
    }

    let body
    try {
      body = LoginSchema.parse(req.body)
    } catch {
      return reply.code(400).send({ error: 'Invalid input format' })
    }

    const { rows } = await fastify.db.query(
      `SELECT u.id, u.email, u.password_hash, u.role, u.is_active, u.tenant_id, t.plan, t.name as tenant_name
       FROM users u JOIN tenants t ON u.tenant_id = t.id
       WHERE u.email = $1`,
      [body.email]
    )

    if (!rows.length || !rows[0].is_active) {
      await recordFailedAttempt(fastify.redis, ip)
      await writeAuditLog(fastify.db, { action: 'login.failed', detail: { email: body.email, reason: 'not_found' }, ip })
      return reply.code(401).send({ error: 'Invalid credentials' })
    }

    const user  = rows[0]
    const valid = await bcrypt.compare(body.password, user.password_hash)

    if (!valid) {
      await recordFailedAttempt(fastify.redis, ip)
      await writeAuditLog(fastify.db, { actor_id: user.id, action: 'login.failed', detail: { reason: 'bad_password' }, ip })
      return reply.code(401).send({ error: 'Invalid credentials' })
    }

    await resetAttempts(fastify.redis, ip)

    // Update last_login
    await fastify.db.query('UPDATE users SET last_login = NOW() WHERE id = $1', [user.id])
    await writeAuditLog(fastify.db, { actor_id: user.id, actor_type: 'user', action: 'login.success', ip })

    // [BUG-S04 FIX] fastify.signToken is now properly decorated
    const token = fastify.signToken({
      sub:        user.id,
      email:      user.email,
      role:       user.role,
      tenantId:   user.tenant_id,
      tenantName: user.tenant_name,
      plan:       user.plan
    })

    return reply.send({
      token,
      email:      user.email,
      role:       user.role,
      tenantName: user.tenant_name
    })
  })

  // ─── LOGOUT ─────────────────────────────────────────────────────
  fastify.post('/logout', { preHandler: fastify.authenticate }, async (req, reply) => {
    await writeAuditLog(fastify.db, { actor_id: req.user.sub, actor_type: 'user', action: 'logout', ip: req.ip })
    return reply.send({ ok: true })
  })

  // ─── ME ─────────────────────────────────────────────────────────
  fastify.get('/me', { preHandler: fastify.authenticate }, async (req, reply) => {
    const { rows } = await fastify.db.query(
      `SELECT u.id, u.email, u.role, u.last_login, u.totp_enabled,
              t.name as tenant_name, t.plan
       FROM users u JOIN tenants t ON u.tenant_id = t.id
       WHERE u.id = $1`,
      [req.user.sub]
    )
    return reply.send(rows[0] || req.user)
  })

  // ─── CHANGE PASSWORD ────────────────────────────────────────────
  fastify.post('/change-password', { preHandler: fastify.authenticate }, async (req, reply) => {
    let body
    try {
      body = ChangePasswordSchema.parse(req.body)
    } catch (err) {
      return reply.code(400).send({ error: err.errors?.[0]?.message || 'Validation error' })
    }

    const { rows } = await fastify.db.query(
      'SELECT password_hash FROM users WHERE id = $1', [req.user.sub]
    )
    if (!rows.length) return reply.code(404).send({ error: 'User not found' })

    const valid = await bcrypt.compare(body.current_password, rows[0].password_hash)
    if (!valid) {
      await writeAuditLog(fastify.db, { actor_id: req.user.sub, actor_type: 'user', action: 'password.change.failed', ip: req.ip })
      return reply.code(401).send({ error: 'Current password incorrect' })
    }

    const newHash = await bcrypt.hash(body.new_password, 12)
    await fastify.db.query('UPDATE users SET password_hash = $1 WHERE id = $2', [newHash, req.user.sub])
    await writeAuditLog(fastify.db, { actor_id: req.user.sub, actor_type: 'user', action: 'password.change.success', ip: req.ip })

    return reply.send({ ok: true, message: 'Password changed successfully' })
  })

  // ─── REFRESH TOKEN ───────────────────────────────────────────────
  fastify.post('/refresh', { preHandler: fastify.authenticate }, async (req, reply) => {
    // Issue a fresh token with updated expiry
    const token = fastify.signToken({
      sub:        req.user.sub,
      email:      req.user.email,
      role:       req.user.role,
      tenantId:   req.user.tenantId,
      tenantName: req.user.tenantName,
      plan:       req.user.plan
    })
    return reply.send({ token })
  })
}

module.exports = authRoutes
