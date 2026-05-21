'use strict'

const crypto = require('crypto')

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
  setex: jest.fn(async () => 'OK'),
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

describe('RMM agent enrollment', () => {
  let app
  let previousToken

  beforeEach(async () => {
    previousToken = process.env.AGENT_ENROLLMENT_TOKEN
    process.env.AGENT_ENROLLMENT_TOKEN = 'lab-enroll-token'

    db.query.mockReset()
    redis.get.mockClear()
    redis.ttl.mockClear()
    redis.incr.mockClear()
    redis.expire.mockClear()
    redis.del.mockClear()
    redis.setex.mockClear()

    db.query.mockImplementation(async (sql) => {
      if (/SELECT 1/.test(sql)) return { rows: [{ '?column?': 1 }] }
      if (/INSERT INTO agents/i.test(sql)) {
        return { rows: [{ id: 'agent-1', hostname: 'WIN-TEST' }] }
      }
      if (/INSERT INTO audit_logs/i.test(sql)) {
        return { rows: [], rowCount: 1 }
      }
      return { rows: [], rowCount: 0 }
    })

    app = await buildApp()
  })

  afterEach(async () => {
    if (app) {
      await app.close().catch(() => {})
      app = null
    }

    if (previousToken === undefined) delete process.env.AGENT_ENROLLMENT_TOKEN
    else process.env.AGENT_ENROLLMENT_TOKEN = previousToken
  })

  test('rejects agent registration without the enrollment token', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/agent/register',
      payload: {
        uuid: '11111111-1111-1111-1111-111111111111',
        hostname: 'WIN-TEST'
      }
    })

    expect(res.statusCode).toBe(403)
    expect(JSON.parse(res.payload)).toEqual({ error: 'Enrollment token required' })
  })

  test('accepts agent registration with the enrollment token', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/agent/register',
      headers: {
        'x-enrollment-token': 'lab-enroll-token'
      },
      payload: {
        uuid: '11111111-1111-1111-1111-111111111111',
        hostname: 'WIN-TEST',
        os: 'Windows 11',
        cpu: 'Intel',
        gpu: 'NVIDIA',
        ram_mb: 16384,
        version: '4.1.0'
      }
    })

    expect(res.statusCode).toBe(201)
    const body = JSON.parse(res.payload)
    expect(body.agent_id).toBe('agent-1')
    expect(body.api_key).toBeTruthy()
    const agentUpsertCall = db.query.mock.calls.find(([sql]) => /INSERT INTO agents/i.test(sql))
    expect(agentUpsertCall[0]).toMatch(/api_key_hash\s*=\s*EXCLUDED\.api_key_hash/i)
    expect(db.query).toHaveBeenCalledWith(
      expect.stringMatching(/INSERT INTO audit_logs/i),
      expect.any(Array)
    )
  })

  test('mirrors NEO AI telemetry into OpenFang operator context', async () => {
    const apiKey = 'agent-api-key'
    const apiHash = crypto.createHash('sha256').update(apiKey).digest('hex')

    db.query.mockImplementation(async (sql, params) => {
      if (/SELECT 1/.test(sql)) return { rows: [{ '?column?': 1 }] }
      if (/FROM agents WHERE bios_uuid/i.test(sql)) {
        expect(params[1]).toBe(apiHash)
        return {
          rows: [{
            id: 'agent-1',
            tenant_id: 'tenant-1',
            hostname: 'WIN-TEST',
            os: 'Windows 11',
            cpu: 'Intel',
            gpu: 'NVIDIA',
            ram_mb: 16384
          }]
        }
      }
      if (/INSERT INTO telemetry/i.test(sql)) return { rows: [], rowCount: 1 }
      if (/FROM telemetry/i.test(sql)) return { rows: [] }
      if (/SELECT severity\s+FROM security_alerts/i.test(sql)) return { rows: [] }
      if (/INSERT INTO health_scores/i.test(sql)) return { rows: [], rowCount: 1 }
      if (/UPDATE agents SET health_score/i.test(sql)) return { rows: [], rowCount: 1 }
      if (/INSERT INTO audit_logs/i.test(sql)) return { rows: [], rowCount: 1 }
      if (/INSERT INTO security_alerts/i.test(sql)) return { rows: [], rowCount: 1 }
      return { rows: [], rowCount: 0 }
    })

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/agent/telemetry',
      headers: { 'x-api-key': apiKey },
      payload: {
        uuid: '11111111-1111-1111-1111-111111111111',
        hostname: 'WIN-TEST',
        sample_kind: 'neo_ai_audit',
        metrics: {
          memory: { used_percent: 71.2 },
          disk: { free_gb: 42 }
        },
        verbose_info: {
          neo_ai: {
            source: 'neo_ai',
            event: 'plan',
            provider: 'neocore',
            severity: 'high',
            confidence: 0.82,
            health_score: 58,
            summary: 'Defender realtime disabled and maintenance risk detected.',
            recommended_command: 'SECURITY_SCAN',
            recommendations: [
              { module: 'Security', rmm_command: 'SECURITY_SCAN', confidence_pct: 82, reason: 'Validate security posture.' }
            ]
          }
        }
      }
    })

    expect(res.statusCode).toBe(200)
    expect(JSON.parse(res.payload)).toEqual({ ok: true })
    const openfangCall = redis.setex.mock.calls.find(([key]) => key === 'openfang:tele:agent-1')
    expect(openfangCall).toBeTruthy()
    const mirrored = JSON.parse(openfangCall[2])
    expect(mirrored.hand).toBe('neo')
    expect(mirrored.recommended_command).toBe('SECURITY_SCAN')
    expect(mirrored.severity).toBe('high')
    expect(db.query).toHaveBeenCalledWith(
      expect.stringMatching(/INSERT INTO audit_logs/i),
      expect.any(Array)
    )
    expect(db.query).toHaveBeenCalledWith(
      expect.stringMatching(/INSERT INTO security_alerts/i),
      expect.arrayContaining(['agent-1', 'tenant-1', 'neo_ai', 'high'])
    )
  })
})
