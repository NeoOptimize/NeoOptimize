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
const { buildApp } = require('../src/index')

describe('secure update routes', () => {
  let app
  let previousJwtSecret

  beforeEach(async () => {
    previousJwtSecret = process.env.JWT_SECRET
    process.env.JWT_SECRET = 'test-secret-for-update-routes-that-is-long-enough'

    db.query.mockReset()
    db.query.mockImplementation(async (sql) => {
      if (/SELECT 1/.test(sql)) return { rows: [{ '?column?': 1 }] }
      if (/INSERT INTO audit_logs/i.test(sql)) return { rows: [], rowCount: 1 }
      return { rows: [], rowCount: 0 }
    })

    app = await buildApp()
  })

  afterEach(async () => {
    if (app) {
      await app.close().catch(() => {})
      app = null
    }
    if (previousJwtSecret === undefined) delete process.env.JWT_SECRET
    else process.env.JWT_SECRET = previousJwtSecret
  })

  test('requires credentials for protected update installer endpoint', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/downloads/neooptimize/installer'
    })

    expect(res.statusCode).toBe(401)
    expect(JSON.parse(res.payload)).toEqual({ error: 'Update credentials required' })
  })

  test('issues short-lived update token after password verification', async () => {
    const password = 'Sup3r!Update123'
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
            plan: 'enterprise',
            tenant_name: 'NeoOptimize Lab'
          }]
        }
      }
      if (/INSERT INTO audit_logs/i.test(sql)) return { rows: [], rowCount: 1 }
      if (/SELECT 1/.test(sql)) return { rows: [{ '?column?': 1 }] }
      return { rows: [], rowCount: 0 }
    })

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/update/session',
      payload: {
        email: 'admin@neooptimize.local',
        password
      }
    })

    expect(res.statusCode).toBe(200)
    const body = JSON.parse(res.payload)
    expect(body.token).toContain('.')
    expect(body.scope).toBe('neo_update')
    expect(body.manifest_url).toBe('/downloads/neooptimize/manifest')
    expect(body.installer_url).toBe('/downloads/neooptimize/installer')
  })
})
