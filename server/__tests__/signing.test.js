'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')

describe('command signing', () => {
  let tempDir
  let signing

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'neo-signing-'))
    jest.resetModules()
    process.env.KEY_DIR = tempDir
    signing = require('../src/security/signing')
    signing.generateKeyPair()
  })

  afterEach(() => {
    delete process.env.KEY_DIR
    fs.rmSync(tempDir, { recursive: true, force: true })
  })

  test('verifies commands with deterministically sorted args', () => {
    const args = { z: 1, a: { b: true, a: 'first' } }
    const signature = signing.signCommand('cmd-1', 'CLEAN', args)

    expect(signing.verifySignature('cmd-1', 'CLEAN', { a: { a: 'first', b: true }, z: 1 }, signature))
      .toBe(true)
  })

  test('preserves nested arrays in canonical args', () => {
    const args = {
      safety_manifest: {
        manifest: {
          pre_flight_safety: {
            snapshot_registry_keys: ['HKLM\\SOFTWARE\\NeoOptimizeTest']
          },
          impact_guardrails: {
            thresholds: { forbidden_event_ids: [41, 1001] }
          }
        }
      }
    }
    const signature = signing.signCommand('cmd-2', 'PING', args)

    expect(signing.verifySignature('cmd-2', 'PING', {
      safety_manifest: {
        manifest: {
          impact_guardrails: {
            thresholds: { forbidden_event_ids: [41, 1001] }
          },
          pre_flight_safety: {
            snapshot_registry_keys: ['HKLM\\SOFTWARE\\NeoOptimizeTest']
          }
        }
      }
    }, signature)).toBe(true)
  })

  test('rejects modified commands', () => {
    const signature = signing.signCommand('cmd-1', 'CLEAN', { scope: 'temp' })

    expect(signing.verifySignature('cmd-1', 'POWER', { scope: 'temp' }, signature))
      .toBe(false)
  })
})
