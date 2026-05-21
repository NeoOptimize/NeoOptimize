'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')

describe('NeoOptimize command safety manifest', () => {
  let tempDir
  let safety
  let signing

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'neo-safety-signing-'))
    jest.resetModules()
    process.env.KEY_DIR = tempDir
    signing = require('../src/security/signing')
    signing.generateKeyPair()
    safety = require('../src/lib/safetyManifest')
  })

  afterEach(() => {
    delete process.env.KEY_DIR
    fs.rmSync(tempDir, { recursive: true, force: true })
  })

  test('builds and signs a critical manifest with pre-flight rollback guardrails', () => {
    const manifest = safety.buildSafetyManifest({
      commandId: '11111111-1111-1111-1111-111111111111',
      type: 'SYSTEM_REPAIR',
      args: { source: 'test' },
      agent: { id: 'agent-1', hostname: 'WIN-01', version: '5.0.0', os: 'Windows 11 10.0.22631' },
      source: 'Jest'
    })
    const signed = safety.signSafetyManifest(manifest)
    const safeArgs = safety.attachSafetyManifestToArgs({ source: 'test' }, signed)

    expect(manifest.policy_gate.risk_level).toBe('CRITICAL')
    expect(manifest.pre_flight_safety.create_windows_restore_point).toBe(true)
    expect(manifest.rollback.trigger_on_failure).toBe(true)
    expect(signed.manifest_sha256).toMatch(/^[a-f0-9]{64}$/)
    expect(safeArgs.safety_manifest.signature).toBeTruthy()
  })

  test('rejects old agent versions and chooses canary subset for high risk bulk commands', () => {
    const manifest = safety.buildSafetyManifest({
      commandId: 'cmd-2',
      type: 'AUTOIMMUNE',
      agent: { version: '1.0.0' }
    })
    expect(safety.evaluateAgentEligibility({ version: '1.0.0' }, manifest)).toMatchObject({ ok: false })

    const agents = Array.from({ length: 200 }, (_, index) => ({
      id: `agent-${String(index).padStart(3, '0')}`,
      health_score: index === 5 ? 99 : 80,
      tags: index === 5 ? ['canary'] : []
    }))
    const selected = safety.selectCanaryTargets(agents, 'AUTOIMMUNE')

    expect(selected.length).toBe(2)
    expect(selected[0].id).toBe('agent-005')
  })

  test('canary evaluator revokes on failure rate and advances after bake window', () => {
    const manifest = safety.buildSafetyManifest({ commandId: 'cmd-3', type: 'THREAT_SCAN' })
    const revoke = safety.evaluateCanary({
      manifestRow: { manifest, status: 'ACTIVE', canary_phase: 'PHASE_1_CANARY', bake_until: new Date(Date.now() - 1000).toISOString() },
      targets: [{ status: 'FAILED' }, { status: 'SUCCESS' }],
      events: []
    })
    expect(revoke.decision).toBe('REVOKE')

    const advance = safety.evaluateCanary({
      manifestRow: { manifest, status: 'ACTIVE', canary_phase: 'PHASE_1_CANARY', bake_until: new Date(Date.now() - 1000).toISOString() },
      targets: [{ status: 'SUCCESS' }, { status: 'SUCCESS' }],
      events: []
    })
    expect(advance).toMatchObject({ decision: 'ADVANCE', next_phase: 'PHASE_2_CANARY' })
  })
})
