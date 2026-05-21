'use strict'

const { signToken, verifyToken, parseDurationSeconds } = require('../src/security/tokens')

describe('JWT-compatible dashboard tokens', () => {
  const secret = '0123456789abcdef0123456789abcdef0123456789abcdef'

  test('signs and verifies an HS256 token', () => {
    const token = signToken(
      { sub: 'user-1', role: 'admin', tenantId: 'tenant-1' },
      { secret, expiresIn: '1h' }
    )

    const payload = verifyToken(token, { secret })
    expect(payload.sub).toBe('user-1')
    expect(payload.role).toBe('admin')
    expect(payload.tenantId).toBe('tenant-1')
    expect(payload.exp).toBeGreaterThan(payload.iat)
  })

  test('rejects a tampered payload', () => {
    const token = signToken({ sub: 'user-1' }, { secret, expiresIn: '1h' })
    const parts = token.split('.')
    const tamperedPayload = Buffer.from(JSON.stringify({ sub: 'user-2', exp: 9999999999 }))
      .toString('base64url')

    expect(() => verifyToken(`${parts[0]}.${tamperedPayload}.${parts[2]}`, { secret }))
      .toThrow(/signature/i)
  })

  test('parses compact duration strings', () => {
    expect(parseDurationSeconds('30s')).toBe(30)
    expect(parseDurationSeconds('15m')).toBe(900)
    expect(parseDurationSeconds('8h')).toBe(28800)
    expect(parseDurationSeconds('2d')).toBe(172800)
  })
})
