'use strict'

// ═══════════════════════════════════════════════════════════════════
// SCHEDULER WORKER v1.0
// [NEW] Cron-based task runner — runs scheduled_tasks from DB
// ═══════════════════════════════════════════════════════════════════

const signing  = require('../security/signing')
const { v4: uuidv4 } = require('uuid')

// Minimal cron parser (supports: minute hour dom month dow)
function shouldRunNow (cronExpr, lastRun) {
  try {
    const now   = new Date()
    const parts = cronExpr.trim().split(/\s+/)
    if (parts.length !== 5) return false

    const [min, hour, dom, month, dow] = parts

    const matches = (field, value) => {
      if (field === '*') return true
      if (field.includes('/')) {
        const [, step] = field.split('/')
        return value % parseInt(step) === 0
      }
      if (field.includes(',')) return field.split(',').map(Number).includes(value)
      if (field.includes('-')) {
        const [start, end] = field.split('-').map(Number)
        return value >= start && value <= end
      }
      return parseInt(field) === value
    }

    const matchMin   = matches(min,   now.getMinutes())
    const matchHour  = matches(hour,  now.getHours())
    const matchDom   = matches(dom,   now.getDate())
    const matchMonth = matches(month, now.getMonth() + 1)
    const matchDow   = matches(dow,   now.getDay())

    if (!(matchMin && matchHour && matchDom && matchMonth && matchDow)) return false

    // Don't run if already ran within this minute
    if (lastRun) {
      const diff = (now - new Date(lastRun)) / 1000
      if (diff < 60) return false
    }

    return true
  } catch { return false }
}

async function start (db, app) {
  const log = app.log

  setInterval(async () => {
    try {
      // 1. Auto-Restart HuggingFace Spaces (if enabled and sleeping)
      const { hf } = require('../lib/integrations')
      if (hf) {
        await hf.checkAndRestartIdleSpace()
      }

      // 2. Process Scheduled Tasks
      const { rows: tasks } = await db.query(
        `SELECT * FROM scheduled_tasks WHERE is_active = TRUE`
      )

      for (const task of tasks) {
        if (!shouldRunNow(task.cron_expr, task.last_run)) continue

        log.info({ taskId: task.id, name: task.name, cmd: task.cmd_type }, '[Scheduler] Running task')

        // Resolve target agents
        let agentQuery = ''
        const agentParams = [task.tenant_id]

        if (task.agent_id) {
          agentQuery = `SELECT id FROM agents WHERE id = $2 AND tenant_id = $1 AND status = 'online'`
          agentParams.push(task.agent_id)
        } else if (task.group_id) {
          agentQuery = `SELECT id FROM agents WHERE group_id = $2 AND tenant_id = $1 AND status = 'online'`
          agentParams.push(task.group_id)
        } else if (task.target_all) {
          agentQuery = `SELECT id FROM agents WHERE tenant_id = $1 AND status = 'online'`
        } else {
          continue
        }

        const { rows: agents } = await db.query(agentQuery, agentParams)
        if (!agents.length) {
          log.debug({ taskId: task.id }, '[Scheduler] No online agents found for task')
          continue
        }

        for (const agent of agents) {
          const cmdId = uuidv4()
          let sig = null
          try { sig = signing.signCommand(cmdId, task.cmd_type, task.cmd_args || {}) }
          catch (err) { log.error({ err }, '[Scheduler] Signing failed'); continue }

          await db.query(`
            INSERT INTO commands
              (id, agent_id, tenant_id, type, args, signature, priority, issued_by_type, scheduled_task_id)
            VALUES ($1,$2,$3,$4,$5,$6,$7,'scheduled',$8)`,
            [cmdId, agent.id, task.tenant_id, task.cmd_type,
             JSON.stringify(task.cmd_args || {}), sig, task.priority || 5, task.id]
          )
        }

        // Update task stats
        await db.query(
          `UPDATE scheduled_tasks SET last_run = NOW(), run_count = run_count + 1 WHERE id = $1`,
          [task.id]
        )
      }
    } catch (err) {
      app.log.error({ err }, '[Scheduler] Error in scheduler loop')
    }
  }, 60 * 1000) // Check every minute
}

module.exports = { start }
