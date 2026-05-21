'use strict'

const {
  evaluateManifestAfterAgentReport,
  shouldEvaluateSafetyStatus,
  summarizeResult
} = require('../src/lib/safetyAutoResponse')

describe('Safety Auto-Response', () => {
  test('only evaluates failure-like safety statuses', () => {
    expect(shouldEvaluateSafetyStatus('ROLLBACK')).toBe(true)
    expect(shouldEvaluateSafetyStatus('REJECTED')).toBe(true)
    expect(shouldEvaluateSafetyStatus('FAILED')).toBe(true)
    expect(shouldEvaluateSafetyStatus('TIMEOUT')).toBe(true)
    expect(shouldEvaluateSafetyStatus('SUCCESS')).toBe(false)
  })

  test('summarizes endpoint self-healing result without leaking full payload', () => {
    expect(summarizeResult({
      rolled_back: true,
      error: 'guardrail breach',
      self_healing: { status: 'ROLLBACK', trace: 'large-local-log' },
      impact: { cpu: 99 }
    })).toEqual({
      rollback: false,
      rolled_back: true,
      rejected: false,
      error: 'guardrail breach',
      self_healing_status: 'ROLLBACK'
    })
  })

  test('skips healthy command reports', async () => {
    const fastify = { db: { query: jest.fn() }, log: { warn: jest.fn() } }

    const result = await evaluateManifestAfterAgentReport(fastify, {
      manifestId: 'manifest-1',
      tenantId: 'tenant-1',
      normalizedStatus: 'SUCCESS',
      reportStatus: 'success'
    })

    expect(result).toEqual({ action: 'skipped', reason: 'non_failure_status' })
    expect(fastify.db.query).not.toHaveBeenCalled()
  })

  test('revokes manifest and pending commands when rollback exceeds canary failure budget', async () => {
    const calls = []
    const manifestRow = {
      id: 'manifest-1',
      tenant_id: 'tenant-1',
      status: 'ACTIVE',
      canary_phase: 'PHASE_1_CANARY',
      manifest: {
        execution_control: {
          canary_policy: {
            current_phase: 'PHASE_1_CANARY',
            max_allowed_failure_rate: 0.05
          }
        }
      }
    }

    const fastify = {
      log: { warn: jest.fn() },
      db: {
        query: jest.fn(async (sql, params) => {
          calls.push({ sql, params })

          if (/SELECT \* FROM safety_manifests/i.test(sql)) {
            return { rows: [manifestRow], rowCount: 1 }
          }
          if (/SELECT \* FROM safety_manifest_targets/i.test(sql)) {
            return {
              rows: [
                { manifest_id: 'manifest-1', tenant_id: 'tenant-1', status: 'ROLLBACK' }
              ],
              rowCount: 1
            }
          }
          if (/SELECT \* FROM safety_events/i.test(sql)) {
            return { rows: [], rowCount: 0 }
          }
          return { rows: [], rowCount: 1 }
        })
      }
    }

    const result = await evaluateManifestAfterAgentReport(fastify, {
      manifestId: 'manifest-1',
      tenantId: 'tenant-1',
      agentId: 'agent-1',
      commandId: 'cmd-1',
      normalizedStatus: 'ROLLBACK',
      reportStatus: 'failed',
      result: { rolled_back: true, self_healing: { status: 'ROLLBACK' } }
    })

    expect(result.action).toBe('revoked')
    expect(result.reason).toBe('failure_rate_exceeded')
    expect(calls.some(call => /UPDATE safety_manifests/i.test(call.sql) && /REVOKED/i.test(call.sql))).toBe(true)
    expect(calls.some(call => /UPDATE commands/i.test(call.sql) && /safety_auto_response/i.test(call.sql))).toBe(true)
    expect(calls.some(call => /UPDATE safety_manifest_targets/i.test(call.sql) && /REVOKED/i.test(call.sql))).toBe(true)
    expect(calls.some(call => /safety\.auto_response\.manifest_revoked/i.test(JSON.stringify(call.params)))).toBe(true)
    expect(calls.some(call => /INSERT INTO audit_logs/i.test(call.sql))).toBe(true)
  })
})
