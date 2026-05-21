'use strict'

const fs = require('fs')
const path = require('path')

const root = path.join(__dirname, '..')

function read (...parts) {
  return fs.readFileSync(path.join(root, ...parts), 'utf8')
}

describe('database contract', () => {
  const schema = read('schema.sql')

  test('matches the tables and columns used by the API', () => {
    expect(schema).toMatch(/CREATE TABLE(?: IF NOT EXISTS)? audit_logs/i)
    expect(schema).toMatch(/actor_id\s+UUID/i)
    expect(schema).toMatch(/issued_by\s+UUID/i)
    expect(schema).toMatch(/CREATE TABLE(?: IF NOT EXISTS)? telemetry_default PARTITION OF telemetry DEFAULT/i)
    expect(schema).not.toMatch(/CREATE TABLE audit_log\s*\(/i)
    expect(schema).not.toMatch(/created_by\s+VARCHAR/i)
  })

  test('does not ship a known default admin password', () => {
    const retiredDefault = ['neooptimize', '2026'].join('')
    expect(schema.toLowerCase()).not.toContain(retiredDefault)
  })

  test('command inserts include tenant ownership', () => {
    const dashboardRoutes = read('src', 'routes', 'dashboard.js')
    const commandWorker = read('src', 'workers', 'commandWorker.js')

    expect(dashboardRoutes).not.toMatch(/INSERT INTO commands \(id, agent_id, type/i)
    expect(commandWorker).not.toMatch(/INSERT INTO commands\s*\n\s*\(id, agent_id, tenant_id, type, args, signature, status, priority, created_by\)/i)
  })

  test('defines command safety manifest and canary tracking tables', () => {
    expect(schema).toMatch(/CREATE TABLE(?: IF NOT EXISTS)? safety_manifests/i)
    expect(schema).toMatch(/CREATE TABLE(?: IF NOT EXISTS)? safety_manifest_targets/i)
    expect(schema).toMatch(/CREATE TABLE(?: IF NOT EXISTS)? safety_events/i)
    expect(schema).toMatch(/safety_manifest_id\s+UUID/i)
  })

  test('defines AI telemetry planes for host baseline, impact, and safety state', () => {
    expect(schema).toMatch(/active_command_id\s+UUID/i)
    expect(schema).toMatch(/disk_queue_length\s+FLOAT4/i)
    expect(schema).toMatch(/CREATE TABLE(?: IF NOT EXISTS)? agent_host_baselines/i)
    expect(schema).toMatch(/CREATE TABLE(?: IF NOT EXISTS)? command_impact_metrics/i)
    expect(schema).toMatch(/CREATE TABLE(?: IF NOT EXISTS)? agent_safety_states/i)
  })

  test('does not expose multimedia capture commands by default', () => {
    const dashboardRoutes = read('src', 'routes', 'dashboard.js')

    expect(dashboardRoutes).not.toMatch(/'SNAPSHOT'/)
    expect(dashboardRoutes).not.toMatch(/'LISTEN'/)
    expect(dashboardRoutes).not.toMatch(/'GEOLOCATE'/)
    expect(dashboardRoutes).not.toMatch(/'SHELL'/)
    expect(dashboardRoutes).not.toMatch(/'CUSTOM'/)
  })

  test('exposes maintenance diagnostics without permission-escalation tasking', () => {
    const dashboardRoutes = read('src', 'routes', 'dashboard.js')
    const commandWorker = read('src', 'workers', 'commandWorker.js')

    expect(dashboardRoutes).toMatch(/'DEEP_SCAN'/)
    expect(dashboardRoutes).toMatch(/'SYSTEM_DIAGNOSTICS'/)
    expect(commandWorker).toMatch(/'DEEP_SCAN'/)
    expect(commandWorker).toMatch(/'SYSTEM_DIAGNOSTICS'/)
    expect(dashboardRoutes).not.toMatch(/'GRANT_PERMISSIONS'/)
    expect(commandWorker).not.toMatch(/'GRANT_PERMISSIONS'/)
  })
})
