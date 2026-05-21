'use strict'

// ═══════════════════════════════════════════════════════════════════
// SECURITY MIDDLEWARE v6.0
// [BUG-S05 FIX] Brute-force tracker migrated from in-memory Map → Redis
//               (survives server restarts, works in multi-instance deployments)
// ═══════════════════════════════════════════════════════════════════

const crypto = require('crypto')

const BLOCK_THRESHOLD  = 10
const BLOCK_DURATION_S = 15 * 60  // 15 minutes in seconds
const KEY_PREFIX       = 'bruteforce:'

// ─── IP Lockout Check (Redis-backed) ─────────────────────────────
async function checkBruteForce (redis, ip) {
  try {
    const key = `${KEY_PREFIX}${ip}`
    const [count, ttl] = await Promise.all([
      redis.get(key),
      redis.ttl(key)
    ])

    const attempts = parseInt(count || '0')
    if (attempts >= BLOCK_THRESHOLD && ttl > 0) {
      return { blocked: true, remaining: ttl }
    }
  } catch {
    // Redis failure — fail open (don't block legitimate users)
  }
  return { blocked: false }
}

async function recordFailedAttempt (redis, ip) {
  try {
    const key = `${KEY_PREFIX}${ip}`
    const attempts = await redis.incr(key)
    if (attempts === 1) {
      // First failure — set expiry window
      await redis.expire(key, BLOCK_DURATION_S * 2) // 2x window to track count
    }
    if (attempts >= BLOCK_THRESHOLD) {
      // Lock them out for 15 minutes
      await redis.expire(key, BLOCK_DURATION_S)
    }
  } catch {
    // Fail silently — don't crash the server on Redis issues
  }
}

async function resetAttempts (redis, ip) {
  try {
    await redis.del(`${KEY_PREFIX}${ip}`)
  } catch {}
}

// ─── Deep Input Sanitizer ─────────────────────────────────────────
function sanitizeString (val, maxLen = 1000) {
  if (typeof val !== 'string') return val
  return val
    .slice(0, maxLen)
    .replace(/[<>"'`;\\]/g, '') // Strip XSS chars
    .trim()
}

function deepSanitize (obj, depth = 0) {
  if (depth > 5) return {}
  if (typeof obj === 'string') return sanitizeString(obj)
  if (Array.isArray(obj)) return obj.slice(0, 100).map(v => deepSanitize(v, depth + 1))
  if (obj && typeof obj === 'object') {
    const clean = {}
    for (const [k, v] of Object.entries(obj)) {
      clean[sanitizeString(k, 64)] = deepSanitize(v, depth + 1)
    }
    return clean
  }
  return obj
}

// ─── Security Headers ─────────────────────────────────────────────
async function addSecurityHeaders (req, reply) {
  reply.header('X-Content-Type-Options',  'nosniff')
  reply.header('X-Frame-Options',         'DENY')
  reply.header('X-XSS-Protection',        '1; mode=block')
  reply.header('Referrer-Policy',         'strict-origin-when-cross-origin')
  reply.header('Permissions-Policy',      'camera=(), microphone=(), geolocation=()')
  reply.header('Strict-Transport-Security', 'max-age=31536000; includeSubDomains')
  reply.header('Content-Security-Policy',
    "default-src 'self'; " +
    "script-src 'self' 'unsafe-inline'; " +
    "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " +
    "font-src 'self' https://fonts.gstatic.com; " +
    "img-src 'self' data:; " +
    "connect-src 'self' ws: wss:"
  )
}

// ─── Audit Log Helper ─────────────────────────────────────────────
async function writeAuditLog (db, opts) {
  const {
    actor_id   = null,
    actor_type = 'system',
    action,
    target_id  = null,
    target_type = null,
    detail     = {},
    ip         = null
  } = opts

  try {
    await db.query(
      `INSERT INTO audit_logs (actor_id, actor_type, action, target_id, target_type, detail, ip_address)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [actor_id, actor_type, action, target_id, target_type, JSON.stringify(detail), ip]
    )
  } catch (err) {
    // Never fail a request because of audit log failure
    console.error('[AuditLog] Write failed:', err.message)
  }
}

// ─── Rate Limit Key by API Key + IP ───────────────────────────────
function rateLimitKeyGenerator (req) {
  return req.headers['x-api-key']
    ? `api:${crypto.createHash('md5').update(req.headers['x-api-key']).digest('hex')}`
    : `ip:${req.ip}`
}

module.exports = {
  addSecurityHeaders,
  checkBruteForce,
  recordFailedAttempt,
  resetAttempts,
  deepSanitize,
  writeAuditLog,
  rateLimitKeyGenerator
}
