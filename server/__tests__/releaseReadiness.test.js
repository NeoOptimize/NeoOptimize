'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')
const crypto = require('crypto')
const { buildReleaseReadiness, installerMeta } = require('../src/lib/releaseReadiness')

function makeInstaller (filePath) {
  const buf = Buffer.alloc(11 * 1024 * 1024, 0)
  buf[0] = 0x4d
  buf[1] = 0x5a
  fs.writeFileSync(filePath, buf)
  const sha = crypto.createHash('sha256').update(buf).digest('hex')
  fs.writeFileSync(`${filePath}.sha256`, `${sha}  ${filePath}\n`)
  return sha
}

function fakeFastify () {
  return {
    redis: { ping: jest.fn(async () => 'PONG') },
    db: {
      query: jest.fn(async (sql) => {
        if (/SELECT 1/.test(sql)) return { rows: [{ '?column?': 1 }], rowCount: 1 }
        if (/to_regclass/i.test(sql)) {
          return {
            rows: [{
              agents: 'agents',
              commands: 'commands',
              telemetry: 'telemetry',
              safety_manifests: 'safety_manifests',
              safety_events: 'safety_events',
              agent_safety_states: 'agent_safety_states',
              command_impact_metrics: 'command_impact_metrics'
            }],
            rowCount: 1
          }
        }
        if (/SELECT\s+\(SELECT COUNT/i.test(sql)) {
          return {
            rows: [{
              agents: 1,
              active_commands: 0,
              revoked_24h: 0,
              severe_safety_events_24h: 0
            }],
            rowCount: 1
          }
        }
        return { rows: [], rowCount: 0 }
      })
    }
  }
}

describe('release readiness gate', () => {
  let root

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'neo-release-ready-'))
    fs.mkdirSync(path.join(root, 'program'), { recursive: true })
    fs.mkdirSync(path.join(root, 'release'), { recursive: true })
    fs.mkdirSync(path.join(root, 'dashboard/dist/assets'), { recursive: true })
    fs.mkdirSync(path.join(root, 'server/keys'), { recursive: true })
    fs.writeFileSync(path.join(root, 'dashboard/dist/index.html'), '<html></html>')
    fs.writeFileSync(path.join(root, 'dashboard/dist/assets/index-test.js'), 'console.log("neo")')
    fs.writeFileSync(path.join(root, 'server/keys/signing.priv.pem'), 'private', { mode: 0o600 })
    fs.writeFileSync(path.join(root, 'server/keys/signing.pub.pem'), 'public')
    makeInstaller(path.join(root, 'program/NeoOptimize.exe'))
  })

  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true })
  })

  test('passes when required release artifacts and services are healthy', async () => {
    const report = await buildReleaseReadiness(fakeFastify(), {
      rootDir: root,
      env: {
        JWT_SECRET: 'x'.repeat(48),
        AGENT_ENROLLMENT_TOKEN: 'enroll-token-that-is-long',
        SUPABASE_URL: 'https://example.supabase.co',
        SUPABASE_SERVICE_ROLE_KEY: 'service-role-token',
        E2B_API_KEY: 'e2b-token-long-enough',
        OLLAMA_URL: 'http://localhost:11434'
      }
    })

    expect(report.public_ready).toBe(true)
    expect(report.summary.fail).toBe(0)
    expect(report.checks.find(c => c.id === 'installer-hash')).toMatchObject({ status: 'pass' })
    expect(report.checks.find(c => c.id === 'dashboard-dist')).toMatchObject({ status: 'pass' })
  })

  test('flags legacy release artifacts before public publishing', async () => {
    fs.writeFileSync(path.join(root, 'release/old-vm.iso'), 'legacy')
    const report = await buildReleaseReadiness(fakeFastify(), {
      rootDir: root,
      env: {
        JWT_SECRET: 'x'.repeat(48),
        AGENT_ENROLLMENT_TOKEN: 'enroll-token-that-is-long'
      }
    })

    expect(report.checks.find(c => c.id === 'legacy-artifacts')).toMatchObject({ status: 'warn' })
  })

  test('detects invalid installer format', () => {
    const filePath = path.join(root, 'program/bad.exe')
    fs.writeFileSync(filePath, 'not a pe')

    expect(installerMeta(filePath)).toMatchObject({
      exists: true,
      pe: false
    })
  })
})
