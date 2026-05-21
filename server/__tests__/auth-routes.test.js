'use strict'

const bcrypt = require('bcryptjs')

jest.mock('../src/db/postgres', () => ({
  db: {
    query: jest.fn(),
    end: jest.fn()
  }
}))

jest.mock('../src/db/redis', () => ({
  get: jest.fn(async () => null),
  ttl: jest.fn(async () => -2),
  incr: jest.fn(async () => 1),
  expire: jest.fn(async () => 1),
  del: jest.fn(async () => 1),
  ping: jest.fn(async () => 'PONG'),
  disconnect: jest.fn(),
  publisher: { disconnect: jest.fn() }
}))

jest.mock('../src/lib/integrations', () => ({
  supabase: { enabled: false, mirrorAuditLog: jest.fn(async () => null), mirrorAlert: jest.fn(async () => null) },
  telegram: { enabled: false, _send: jest.fn(async () => null), agentOffline: jest.fn(async () => null) },
  ollama: {},
  nullclaw: {},
  webhook: {},
  e2b: {},
  hf: { checkAndRestartIdleSpace: jest.fn(async () => false) },
  gemini: { analyzeWindowsSystem: jest.fn(async () => null) },
  AgentWatchdog: jest.fn()
}))

jest.mock('../src/workers/scheduler', () => ({
  start: jest.fn(async () => {})
}))

const { db } = require('../src/db/postgres')
const redis = require('../src/db/redis')
const { buildApp } = require('../src/index')

describe('RMM auth bootstrap', () => {
  let app

  beforeEach(async () => {
    db.query.mockReset()
    redis.get.mockClear()
    redis.ttl.mockClear()
    redis.incr.mockClear()
    redis.expire.mockClear()
    redis.del.mockClear()

    db.query.mockImplementation(async (sql) => {
      if (/SELECT 1/.test(sql)) return { rows: [{ '?column?': 1 }] }
      return { rows: [] }
    })

    app = await buildApp()
  })

  afterEach(async () => {
    if (app) {
      await app.close().catch(() => {})
      app = null
    }
  })

  test('returns 401 for malformed tokens without executing protected handlers', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/v1/auth/me',
      headers: {
        authorization: 'Bearer not-a-valid.jwt.token'
      }
    })

    expect(res.statusCode).toBe(401)
    expect(JSON.parse(res.payload)).toEqual({ error: 'Unauthorized' })
  })

  test('logs in with the bootstrap admin account and returns a usable session token', async () => {
    const password = 'Sup3r!Secret123'
    const passwordHash = await bcrypt.hash(password, 12)

    db.query.mockImplementation(async (sql) => {
      if (/FROM users u JOIN tenants t/i.test(sql)) {
        return {
          rows: [{
            id: 'user-1',
            email: 'admin@neooptimize.local',
            password_hash: passwordHash,
            role: 'admin',
            is_active: true,
            tenant_id: 'tenant-1',
            plan: 'pro',
            tenant_name: 'NeoOptimize Lab'
          }]
        }
      }

      if (/UPDATE users SET last_login/i.test(sql)) {
        return { rows: [], rowCount: 1 }
      }

      if (/INSERT INTO audit_logs/i.test(sql)) {
        return { rows: [], rowCount: 1 }
      }

      return { rows: [], rowCount: 0 }
    })

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/login',
      payload: {
        email: 'admin@neooptimize.local',
        password
      }
    })

    expect(res.statusCode).toBe(200)

    const body = JSON.parse(res.payload)
    expect(body.email).toBe('admin@neooptimize.local')
    expect(body.role).toBe('admin')
    expect(body.token).toContain('.')
    expect(redis.del).toHaveBeenCalledWith('bruteforce:127.0.0.1')
  })
})
