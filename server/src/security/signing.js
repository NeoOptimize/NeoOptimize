'use strict'

// ═══════════════════════════════════════════════════════════════════
// RSA-2048-SHA256 SIGNING SYSTEM
// - Server signs commands with private key
// - Agent verifies with embedded public key
// - Keys rotatable without agent reinstall
// ═══════════════════════════════════════════════════════════════════

const forge  = require('node-forge')
const crypto = require('crypto')
const path   = require('path')
const fs     = require('fs')

const ALGO        = 'RSA-SHA256'
const KEY_SIZE    = 2048
const KEY_DIR     = process.env.KEY_DIR || path.join(__dirname, '../../keys')
const PRIV_FILE   = path.join(KEY_DIR, 'signing.priv.pem')
const PUB_FILE    = path.join(KEY_DIR, 'signing.pub.pem')

// ─── Generate RSA Key Pair ───────────────────────────────────────
function generateKeyPair () {
  console.log('[signing] Generating RSA-2048 key pair...')

  const keypair = forge.pki.rsa.generateKeyPair({ bits: KEY_SIZE, e: 0x10001 })
  const privPem = forge.pki.privateKeyToPem(keypair.privateKey)
  const pubPem  = forge.pki.publicKeyToPem(keypair.publicKey)

  if (!fs.existsSync(KEY_DIR)) fs.mkdirSync(KEY_DIR, { recursive: true, mode: 0o700 })

  fs.writeFileSync(PRIV_FILE, privPem, { mode: 0o600 }) // owner read-only
  fs.writeFileSync(PUB_FILE,  pubPem,  { mode: 0o644 })

  console.log(`[signing] Keys written to ${KEY_DIR}`)
  return { privPem, pubPem }
}

// ─── Load Keys from Disk ─────────────────────────────────────────
function loadKeys () {
  if (!fs.existsSync(PRIV_FILE) || !fs.existsSync(PUB_FILE)) {
    throw new Error('Signing keys not found. Run: npm run keygen')
  }
  return {
    privPem: fs.readFileSync(PRIV_FILE, 'utf8'),
    pubPem:  fs.readFileSync(PUB_FILE,  'utf8')
  }
}

// ─── Sign a Command ──────────────────────────────────────────────
// Signs: JSON.stringify({ id, type, args }) deterministically
function signCommand (cmdId, cmdType, cmdArgs) {
  const { privPem } = loadKeys()

  // Canonical payload — agent must reconstruct the same string
  const payload = canonicalPayload(cmdId, cmdType, cmdArgs)

  const sign = crypto.createSign(ALGO)
  sign.update(payload)
  sign.end()

  const signature = sign.sign(privPem, 'base64')
  return signature
}

// ─── Verify Signature (Node.js side — for testing) ───────────────
function verifySignature (cmdId, cmdType, cmdArgs, signatureBase64) {
  const { pubPem } = loadKeys()
  const payload    = canonicalPayload(cmdId, cmdType, cmdArgs)

  const verify = crypto.createVerify(ALGO)
  verify.update(payload)
  verify.end()

  try {
    return verify.verify(pubPem, signatureBase64, 'base64')
  } catch {
    return false
  }
}

// ─── Canonical Payload ────────────────────────────────────────────
// MUST match exactly what the C# agent produces for verification
function canonicalPayload (cmdId, cmdType, cmdArgs) {
  // Sort args keys for deterministic serialization
  const sortedArgs = sortObject(cmdArgs || {})
  return `${cmdId}|${cmdType}|${JSON.stringify(sortedArgs)}`
}

function sortObject (obj) {
  if (Array.isArray(obj)) return obj.map(sortObject)
  if (typeof obj !== 'object' || obj === null) return obj
  return Object.keys(obj).sort().reduce((acc, k) => {
    acc[k] = sortObject(obj[k])
    return acc
  }, {})
}

// ─── Get Public Key PEM (distribute to agents) ───────────────────
function getPublicKeyPem () {
  if (!fs.existsSync(PUB_FILE)) {
    throw new Error('Public key not found. Run: npm run keygen')
  }
  return fs.readFileSync(PUB_FILE, 'utf8')
}

// ─── Key Fingerprint (for verification display) ──────────────────
function getKeyFingerprint () {
  const pubPem = getPublicKeyPem()
  const hash   = crypto.createHash('sha256').update(pubPem).digest('hex')
  // Format like SSH: XX:XX:XX:...
  return hash.match(/.{2}/g).join(':').toUpperCase()
}

module.exports = {
  generateKeyPair,
  signCommand,
  verifySignature,
  getPublicKeyPem,
  getKeyFingerprint,
  canonicalPayload
}
