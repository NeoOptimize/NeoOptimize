'use strict'

require('dotenv').config()

const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const bcrypt = require('bcryptjs')
const { db } = require('../db/postgres')

async function main () {
  const email = process.env.ADMIN_EMAIL || 'admin@neooptimize.local'
  const password = process.argv[2] || process.env.ADMIN_PASSWORD || crypto.randomBytes(18).toString('base64url')
  const hash = await bcrypt.hash(password, 12)

  const { rowCount } = await db.query(
    'UPDATE users SET password_hash = $1, is_active = TRUE WHERE email = $2',
    [hash, email]
  )

  if (rowCount === 0) {
    throw new Error(`Admin user not found: ${email}`)
  }

  const outputPath = path.join(__dirname, '../../.local-admin.txt')
  if (process.env.WRITE_LOCAL_ADMIN_FILE !== 'false') {
    fs.writeFileSync(outputPath, [
      'NeoOptimize local admin',
      `URL: http://localhost:${process.env.PORT || '3000'}`,
      `Email: ${email}`,
      `Password: ${password}`,
      ''
    ].join('\n'), { mode: 0o600 })
  }

  console.log(`Admin email: ${email}`)
  console.log(`Admin password: ${password}`)
  console.log(`Local credential file: ${outputPath}`)
}

main()
  .catch((err) => {
    console.error(err.message)
    process.exitCode = 1
  })
  .finally(async () => {
    await db.end().catch(() => {})
  })
