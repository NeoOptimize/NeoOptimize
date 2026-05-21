'use strict'

const { buildOperatorBridgePlan, normalizeOperatorCommand } = require('../src/lib/operatorBridge')

describe('Neo AI operator bridge', () => {
  test('combines OpenFang critical alerts and NullClaw IOC into dispatch-ready recommendations', () => {
    const plan = buildOperatorBridgePlan({
      agent: { id: 'agent-1', hostname: 'WIN-LAB-01', health_score: 48 },
      telemetry: { cpu_pct: 91, ram_pct: 88, disk_free_gb: 4 },
      insight: {
        health_score: 48,
        risk_level: 'high',
        confidence: 0.86,
        command_plan: [{ command: 'DEEP_SCAN', priority: 'high', reason: 'Disk pressure' }]
      },
      alerts: [{ severity: 'critical', rule_name: 'encoded-powershell' }],
      openfangTelemetry: { hand: 'guardian', action: 'THREAT_SCAN', confidence: 88, reason: 'Suspicious encoded PowerShell' },
      nullclawIp: { threat_level: 9, type: 'ip' }
    })

    const commands = plan.recommended_commands.map(item => item.command)
    expect(plan.mode).toBe('advisory_dispatch_ready')
    expect(plan.dispatch_policy.auto_dispatch).toBe(false)
    expect(commands).toContain('THREAT_SCAN')
    expect(commands).toContain('AUTOIMMUNE')
    expect(commands).toContain('DEEP_SCAN')
    expect(plan.recommended_commands.every(item => item.requires_confirmation)).toBe(true)
  })

  test('falls back to baseline diagnostics and blocks unsupported commands', () => {
    const plan = buildOperatorBridgePlan({
      agent: { id: 'agent-2', hostname: 'WIN-LAB-02', health_score: 96 },
      telemetry: { cpu_pct: 12, ram_pct: 24, disk_free_gb: 88 },
      alerts: []
    })

    expect(plan.recommended_commands[0].command).toBe('SYSTEM_DIAGNOSTICS')
    expect(normalizeOperatorCommand('SHELL')).toBeNull()
    expect(normalizeOperatorCommand('clean')).toBe('CLEAN')
  })
})
