'use strict'

const crypto = require('crypto')

const PLACEHOLDER_PATTERNS = [
  /^CHANGE_ME/i,
  /openssl_rand/i,
  /random_secret_here/i
]

function base64UrlEncode (input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
}

function base64UrlDecode (input) {
  const padded = input.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(input.length / 4) * 4, '=')
  return Buffer.from(padded, 'base64')
}

function parseDurationSeconds (value, fallbackSeconds = 8 * 60 * 60) {
  if (!value) return fallbackSeconds
  if (typeof value === 'number') return Math.max(1, Math.floor(value))

  const match = String(value).trim().match(/^(\d+)([smhd])?$/i)
  if (!match) return fallbackSeconds

  const amount = parseInt(match[1], 10)
  const unit = (match[2] || 's').toLowerCase()
  const scale = { s: 1, m: 60, h: 3600, d: 86400 }[unit]
  return amount * scale
}

function isUnsafeSecret (secret) {
  return !secret || secret.length < 32 || PLACEHOLDER_PATTERNS.some(pattern => pattern.test(secret))
}

function requireJwtSecret (env = process.env) {
  const secret = env.JWT_SECRET
  if (!isUnsafeSecret(secret)) return secret

  if (env.NODE_ENV === 'production') {
    throw new Error('JWT_SECRET must be at least 32 characters and cannot be a placeholder in production.')
  }

  const fallback = crypto.randomBytes(48).toString('base64url')
  env.JWT_SECRET = fallback
  return fallback
}

function signToken (payload, { secret, expiresIn = '8h' } = {}) {
  if (isUnsafeSecret(secret)) throw new Error('Cannot sign token with an unsafe JWT secret.')

  const now = Math.floor(Date.now() / 1000)
  const body = {
    ...payload,
    iat: now,
    exp: now + parseDurationSeconds(expiresIn)
  }

  const encodedHeader = base64UrlEncode(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
  const encodedBody = base64UrlEncode(JSON.stringify(body))
  const signingInput = `${encodedHeader}.${encodedBody}`
  const signature = crypto.createHmac('sha256', secret).update(signingInput).digest('base64url')
  return `${signingInput}.${signature}`
}

function verifyToken (token, { secret } = {}) {
  if (isUnsafeSecret(secret)) throw new Error('Cannot verify token with an unsafe JWT secret.')
  if (typeof token !== 'string') throw new Error('Token must be a string.')

  const parts = token.split('.')
  if (parts.length !== 3 || parts.some(part => !part)) throw new Error('Malformed token.')

  const [encodedHeader, encodedBody, signature] = parts
  const header = JSON.parse(base64UrlDecode(encodedHeader).toString('utf8'))
  if (header.alg !== 'HS256' || header.typ !== 'JWT') throw new Error('Unsupported token header.')

  const signingInput = `${encodedHeader}.${encodedBody}`
  const expected = crypto.createHmac('sha256', secret).update(signingInput).digest('base64url')

  const actualBuffer = Buffer.from(signature)
  const expectedBuffer = Buffer.from(expected)
  if (actualBuffer.length !== expectedBuffer.length || !crypto.timingSafeEqual(actualBuffer, expectedBuffer)) {
    throw new Error('Invalid token signature.')
  }

  const payload = JSON.parse(base64UrlDecode(encodedBody).toString('utf8'))
  if (payload.exp && Math.floor(Date.now() / 1000) >= payload.exp) throw new Error('Token expired.')
  return payload
}

module.exports = {
  base64UrlEncode,
  base64UrlDecode,
  parseDurationSeconds,
  requireJwtSecret,
  signToken,
  verifyToken
}
