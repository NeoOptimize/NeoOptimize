'use strict'

require('dotenv').config()

const fs = require('fs')
const path = require('path')
const { db } = require('./postgres')

async function migrate () {
  const schemaPath = path.join(__dirname, '../../schema.sql')
  const sql = fs.readFileSync(schemaPath, 'utf8')
  await db.query(sql)
  console.log('Schema migration completed.')
}

migrate()
  .catch((err) => {
    console.error('Schema migration failed:', err.message)
    process.exitCode = 1
  })
  .finally(async () => {
    await db.end()
  })
