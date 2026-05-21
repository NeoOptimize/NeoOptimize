'use strict'

// ═══════════════════════════════════════════════════════════════════
// KEYGEN — RSA-2048 Key Pair Generator
// [BUG-S07 FIX] Previously an empty 40-byte file — now fully implemented
// Usage: npm run keygen
// ═══════════════════════════════════════════════════════════════════

const { generateKeyPair, getKeyFingerprint } = require('./signing')
const path = require('path')
const fs   = require('fs')

const KEY_DIR = process.env.KEY_DIR || path.join(__dirname, '../../keys')

console.log('═══════════════════════════════════════════════════')
console.log('  NeoOptimize RMM — RSA Key Generator v6.0')
console.log('═══════════════════════════════════════════════════')

// Safety check — warn if overwriting existing keys
if (fs.existsSync(path.join(KEY_DIR, 'signing.priv.pem'))) {
  console.warn('\n⚠️  WARNING: Existing signing keys found!')
  console.warn('   Regenerating will INVALIDATE all currently deployed agents.')
  console.warn('   All agents will need signing.pub.pem replaced on next deploy.\n')

  // In non-interactive mode (CI), skip unless forced
  if (!process.argv.includes('--force')) {
    console.log('   Use --force to overwrite. Aborting to prevent accidental key rotation.')
    process.exit(0)
  }
}

try {
  const { privPem, pubPem } = generateKeyPair()

  console.log('\n✅ RSA-2048 key pair generated successfully')
  console.log(`   Private key: ${path.join(KEY_DIR, 'signing.priv.pem')} (mode: 600 - KEEP SECRET)`)
  console.log(`   Public key:  ${path.join(KEY_DIR, 'signing.pub.pem')} (mode: 644 - distribute to agents)`)

  const fingerprint = getKeyFingerprint()
  console.log(`\n🔑 Public Key Fingerprint (SHA256):`)
  console.log(`   ${fingerprint.slice(0, 47)}`)
  console.log(`   ${fingerprint.slice(47)}`)

  console.log('\n📦 Next steps:')
  console.log('   1. Copy signing.pub.pem next to the agent EXE on each target machine')
  console.log('   2. Or embed it in appsettings.json as PublicKeyPem')
  console.log('   3. Restart the NeoOptimize RMM server')
  console.log('\n✅ Done.')
} catch (err) {
  console.error('\n❌ Key generation failed:', err.message)
  process.exit(1)
}
