'use strict'
const IORedis = require('ioredis')

const redis = new IORedis(process.env.REDIS_URL || 'redis://localhost:6379', {
  password:      process.env.REDIS_PASSWORD,
  lazyConnect:   true,
  retryStrategy: (times) => {
    if (times > 20) return null
    return Math.min(times * 200, 5000)
  },
  reconnectOnError: (err) => {
    return err.message.includes('READONLY')
  }
})

redis.on('error',   (err) => console.error('[redis] error:', err.message))
redis.on('connect', ()    => console.log('[redis] connected'))

// Publisher is a second connection (subscribe uses its own)
const publisher = redis.duplicate({ lazyConnect: true })
publisher.on('error', (err) => console.error('[redis:pub] error:', err.message))

module.exports = redis
module.exports.publisher = publisher
