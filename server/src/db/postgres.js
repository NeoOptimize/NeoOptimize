'use strict'
const { Pool } = require('pg')

const db = new Pool({
  host:     process.env.POSTGRES_HOST || 'localhost',
  port:     parseInt(process.env.POSTGRES_PORT || '5432'),
  database: process.env.POSTGRES_DB || 'neooptimize_rmm',
  user:     process.env.POSTGRES_USER || 'neo_app',
  password: process.env.POSTGRES_PASSWORD,
  min:      parseInt(process.env.POSTGRES_POOL_MIN || '2'),
  max:      parseInt(process.env.POSTGRES_POOL_MAX || '20'),
  idleTimeoutMillis:    30000,
  connectionTimeoutMillis: 5000,
  ssl:      process.env.POSTGRES_SSL === 'true' ? { rejectUnauthorized: true } : false
})

db.on('error', (err) => {
  console.error('[postgres] Unexpected pool error', err.message)
})

module.exports = { db }
