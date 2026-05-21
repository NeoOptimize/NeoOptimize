'use strict'

const fs = require('fs')
const os = require('os')
const path = require('path')
const { getProductInfo, parseVersionText } = require('../src/lib/productInfo')

describe('product info', () => {
  test('parses extended NeoOptimize version strings', () => {
    expect(parseVersionText('NeoOptimize Suite v1.2.0-NeoCortex')).toBe('1.2.0-NeoCortex')
    expect(parseVersionText('NeoOptimize v1.0.1-production')).toBe('1.0.1-production')
  })

  test('uses VERSION.txt before package fallback', () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'neo-product-info-'))
    try {
      fs.mkdirSync(path.join(root, 'server'), { recursive: true })
      fs.writeFileSync(path.join(root, 'VERSION.txt'), 'NeoOptimize Suite v2.3.4-public-beta')
      fs.writeFileSync(path.join(root, 'server/package.json'), JSON.stringify({ version: '1.0.0' }))

      expect(getProductInfo({ rootDir: root, env: {} })).toMatchObject({
        version: '2.3.4-public-beta',
        release_channel: 'public-beta'
      })
    } finally {
      fs.rmSync(root, { recursive: true, force: true })
    }
  })
})
