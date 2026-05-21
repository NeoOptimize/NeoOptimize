'use strict'

const { buildMlInsight, SAFE_COMMANDS, normalizeTelemetry } = require('../src/lib/mlAdvisor')

function sample (offset, overrides = {}) {
  return {
    ts: new Date(Date.now() + offset * 60000).toISOString(),
    cpu_pct: 22 + (offset % 3),
    ram_used_mb: 3200 + (offset % 5) * 20,
    disk_free_gb: 42 - offset * 0.05,
    net_rx_kbps: 120 + (offset % 4) * 10,
    net_tx_kbps: 80 + (offset % 4) * 8,
    ...overrides
  }
}

describe('NeoCortex ML advisor', () => {
  test('normalizes abbreviated Redis telemetry and derives RAM percent', () => {
    const normalized = normalizeTelemetry({ c: 44, r: 4096, d: 18, gt: 63 }, { ram_mb: 8192 })

    expect(normalized.cpu_pct).toBe(44)
    expect(normalized.ram_pct).toBe(50)
    expect(normalized.disk_free_gb).toBe(18)
    expect(normalized.gpu_temp_c).toBe(63)
  })

  test('flags telemetry far outside learned baseline', () => {
    const history = Array.from({ length: 24 }, (_, index) => sample(index))
    const insight = buildMlInsight({
      agent: { id: 'agent-1', hostname: 'lab-win-01', ram_mb: 8192 },
      latestTelemetry: sample(25, { cpu_pct: 96, ram_used_mb: 7900, disk_free_gb: 4, net_rx_kbps: 4000 }),
      telemetryHistory: history,
      alerts: [{ severity: 'high' }]
    })

    expect(insight.model).toBe('neocortex-hybrid-v1')
    expect(insight.health_score).toBeLessThan(70)
    expect(['critical', 'high']).toContain(insight.risk_level)
    expect(insight.anomaly_score).toBeGreaterThan(0)
    expect(insight.signals.length).toBeGreaterThan(0)
    expect(insight.command_plan.length).toBeGreaterThan(0)
    for (const action of insight.command_plan) {
      expect(SAFE_COMMANDS.has(action.command)).toBe(true)
    }
  })

  test('does not advertise sensitive collection in guardrails', () => {
    const insight = buildMlInsight({
      agent: { id: 'agent-1', hostname: 'lab-win-01', ram_mb: 8192 },
      latestTelemetry: sample(1),
      telemetryHistory: Array.from({ length: 12 }, (_, index) => sample(index))
    })

    expect(insight.guardrails.autonomous_actions).toBe(false)
    expect(insight.guardrails.allowed_commands).not.toContain('SNAPSHOT')
    expect(insight.guardrails.allowed_commands).not.toContain('LISTEN')
    expect(insight.guardrails.allowed_commands).not.toContain('GEOLOCATE')
    expect(insight.guardrails.data_policy).toMatch(/no camera, microphone, biometric, or secret collection/i)
  })
})
