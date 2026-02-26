import React, { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Clock, Plus, Trash2, Play, Pause } from 'lucide-react';
interface CronJob {
  id: number;
  schedule: string;
  command: string;
  user: string;
  status: 'active' | 'paused' | 'failed';
  lastRun: string;
  nextRun: string;
}
const initialJobs: CronJob[] = [
{
  id: 1,
  schedule: '0 2 * * *',
  command: '/opt/neooptimize/backup.sh',
  user: 'root',
  status: 'active',
  lastRun: '02:00:01',
  nextRun: 'tomorrow 02:00'
},
{
  id: 2,
  schedule: '*/15 * * * *',
  command: '/opt/cleanup.sh --temp',
  user: 'root',
  status: 'active',
  lastRun: '04:15:00',
  nextRun: 'in 12 min'
},
{
  id: 3,
  schedule: '0 0 * * 0',
  command: '/usr/bin/certbot renew',
  user: 'root',
  status: 'active',
  lastRun: 'Sun 00:00',
  nextRun: 'next Sunday'
},
{
  id: 4,
  schedule: '30 6 * * 1-5',
  command: '/opt/reports/daily.sh',
  user: 'user',
  status: 'paused',
  lastRun: 'Mon 06:30',
  nextRun: 'paused'
},
{
  id: 5,
  schedule: '0 * * * *',
  command: '/usr/sbin/logrotate /etc/logrotate.conf',
  user: 'root',
  status: 'active',
  lastRun: '04:00:00',
  nextRun: '05:00:00'
},
{
  id: 6,
  schedule: '0 3 * * *',
  command: '/opt/neooptimize --full --quiet',
  user: 'root',
  status: 'failed',
  lastRun: '03:00:12',
  nextRun: 'tomorrow 03:00'
}];

const statusColor: Record<string, string> = {
  active: 'var(--ansi-green)',
  paused: 'var(--ansi-yellow)',
  failed: 'var(--ansi-red)'
};
const sectionVariants = {
  hidden: {
    opacity: 0,
    y: 16
  },
  visible: (i: number) => ({
    opacity: 1,
    y: 0,
    transition: {
      delay: i * 0.08,
      duration: 0.35,
      ease: 'easeOut'
    }
  })
};
export function SchedulerPage() {
  const [jobs, setJobs] = useState<CronJob[]>(initialJobs);
  const [showAdd, setShowAdd] = useState(false);
  const [newSchedule, setNewSchedule] = useState('0 * * * *');
  const [newCommand, setNewCommand] = useState('');
  const toggleJob = (id: number) => {
    setJobs((prev) =>
    prev.map((j) =>
    j.id === id ?
    {
      ...j,
      status: j.status === 'active' ? 'paused' : 'active'
    } :
    j
    )
    );
  };
  const removeJob = (id: number) => {
    setJobs((prev) => prev.filter((j) => j.id !== id));
  };
  const addJob = () => {
    if (!newCommand.trim()) return;
    setJobs((prev) => [
    ...prev,
    {
      id: Date.now(),
      schedule: newSchedule,
      command: newCommand,
      user: 'root',
      status: 'active',
      lastRun: 'never',
      nextRun: 'pending'
    }]
    );
    setNewCommand('');
    setShowAdd(false);
  };
  const active = jobs.filter((j) => j.status === 'active').length;
  const failed = jobs.filter((j) => j.status === 'failed').length;
  return (
    <div className="space-y-4 font-mono text-xs">
      {/* Breadcrumb */}
      <div
        className="flex items-center gap-2"
        style={{
          color: 'var(--text-muted)'
        }}>

        <span
          style={{
            color: 'var(--ansi-green)',
            fontWeight: 700
          }}>

          root@neooptimize
        </span>
        <span>:~#</span>
        <span
          style={{
            color: 'var(--text-primary)',
            marginLeft: 4
          }}>

          crontab -l && systemctl list-timers
        </span>
        <span
          className="cursor-blink ml-1"
          style={{
            color: 'var(--ansi-green)'
          }}>

          █
        </span>
      </div>

      {/* Stats row */}
      <motion.div
        custom={0}
        variants={sectionVariants}
        initial="hidden"
        animate="visible"
        className="grid grid-cols-3 gap-3">

        {[
        {
          label: 'TOTAL JOBS',
          value: jobs.length,
          color: 'var(--text-primary)'
        },
        {
          label: 'ACTIVE',
          value: active,
          color: 'var(--ansi-green)'
        },
        {
          label: 'FAILED',
          value: failed,
          color: failed > 0 ? 'var(--ansi-red)' : 'var(--text-muted)'
        }].
        map((stat) =>
        <div
          key={stat.label}
          className="p-3 border text-center"
          style={{
            backgroundColor: 'var(--bg-secondary)',
            borderColor: 'var(--border-color)'
          }}>

            <div
            className="text-2xl font-bold mb-1"
            style={{
              color: stat.color
            }}>

              {stat.value}
            </div>
            <div
            style={{
              color: 'var(--text-muted)',
              fontSize: '10px'
            }}>

              {stat.label}
            </div>
          </div>
        )}
      </motion.div>

      {/* Job table */}
      <motion.div
        custom={1}
        variants={sectionVariants}
        initial="hidden"
        animate="visible"
        style={{
          backgroundColor: 'var(--bg-secondary)',
          border: '1px solid var(--border-color)'
        }}>

        {/* Table header */}
        <div
          className="px-3 py-1.5 text-[10px] font-bold border-b flex items-center justify-between"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-tertiary)',
            color: 'var(--text-muted)'
          }}>

          <span>
            <span
              style={{
                color: 'var(--ansi-green)'
              }}>

              $
            </span>{' '}
            crontab -l --verbose
          </span>
          <button
            onClick={() => setShowAdd((s) => !s)}
            className="flex items-center gap-1 px-2 py-0.5 border transition-all duration-150"
            style={{
              borderColor: 'var(--ansi-green)',
              color: 'var(--ansi-green)'
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = 'var(--ansi-green)';
              e.currentTarget.style.color = 'var(--bg-primary)';
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = 'transparent';
              e.currentTarget.style.color = 'var(--ansi-green)';
            }}>

            <Plus size={10} /> ADD JOB
          </button>
        </div>

        {/* Add job form */}
        <AnimatePresence>
          {showAdd &&
          <motion.div
            initial={{
              height: 0,
              opacity: 0
            }}
            animate={{
              height: 'auto',
              opacity: 1
            }}
            exit={{
              height: 0,
              opacity: 0
            }}
            transition={{
              duration: 0.2
            }}
            style={{
              overflow: 'hidden',
              borderBottom: '1px solid var(--border-color)'
            }}>

              <div
              className="p-3 space-y-2"
              style={{
                backgroundColor: 'var(--bg-tertiary)'
              }}>

                <div className="flex gap-2 items-center">
                  <span
                  style={{
                    color: 'var(--text-muted)',
                    width: 72,
                    flexShrink: 0
                  }}>

                    SCHEDULE
                  </span>
                  <input
                  type="text"
                  value={newSchedule}
                  onChange={(e) => setNewSchedule(e.target.value)}
                  className="flex-1 px-2 py-1 border outline-none font-mono text-xs"
                  style={{
                    borderColor: 'var(--border-color)',
                    backgroundColor: 'var(--bg-primary)',
                    color: 'var(--text-primary)'
                  }}
                  placeholder="0 * * * *" />

                </div>
                <div className="flex gap-2 items-center">
                  <span
                  style={{
                    color: 'var(--text-muted)',
                    width: 72,
                    flexShrink: 0
                  }}>

                    COMMAND
                  </span>
                  <input
                  type="text"
                  value={newCommand}
                  onChange={(e) => setNewCommand(e.target.value)}
                  className="flex-1 px-2 py-1 border outline-none font-mono text-xs"
                  style={{
                    borderColor: 'var(--border-color)',
                    backgroundColor: 'var(--bg-primary)',
                    color: 'var(--text-primary)'
                  }}
                  placeholder="/path/to/script.sh" />

                </div>
                <div className="flex gap-2 justify-end">
                  <button
                  onClick={() => setShowAdd(false)}
                  className="px-3 py-1 border text-[10px] transition-all"
                  style={{
                    borderColor: 'var(--border-color)',
                    color: 'var(--text-muted)'
                  }}>

                    CANCEL
                  </button>
                  <button
                  onClick={addJob}
                  className="px-3 py-1 border text-[10px] font-bold transition-all"
                  style={{
                    borderColor: 'var(--ansi-green)',
                    color: 'var(--ansi-green)'
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor =
                    'var(--ansi-green)';
                    e.currentTarget.style.color = 'var(--bg-primary)';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = 'transparent';
                    e.currentTarget.style.color = 'var(--ansi-green)';
                  }}>

                    + ADD
                  </button>
                </div>
              </div>
            </motion.div>
          }
        </AnimatePresence>

        {/* Column headers */}
        <div
          className="grid gap-2 px-3 py-1.5 text-[10px] font-bold border-b"
          style={{
            gridTemplateColumns: '140px 1fr 60px 80px 80px 70px',
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-tertiary)',
            color: 'var(--text-muted)'
          }}>

          <div>SCHEDULE</div>
          <div>COMMAND</div>
          <div>USER</div>
          <div>LAST RUN</div>
          <div>NEXT RUN</div>
          <div className="text-right">ACTIONS</div>
        </div>

        {/* Rows */}
        <div className="max-h-[50vh] overflow-y-auto">
          <AnimatePresence>
            {jobs.map((job, i) =>
            <motion.div
              key={job.id}
              initial={{
                opacity: 0,
                x: -8
              }}
              animate={{
                opacity: 1,
                x: 0
              }}
              exit={{
                opacity: 0,
                x: 8
              }}
              transition={{
                delay: i * 0.04,
                duration: 0.2
              }}
              className="grid gap-2 px-3 py-2 items-center border-b"
              style={{
                gridTemplateColumns: '140px 1fr 60px 80px 80px 70px',
                borderColor: 'var(--border-color)',
                backgroundColor:
                i % 2 === 0 ? 'var(--bg-primary)' : 'transparent'
              }}>

                <div
                style={{
                  color: 'var(--ansi-cyan)'
                }}>

                  {job.schedule}
                </div>
                <div
                className="truncate"
                style={{
                  color: 'var(--text-primary)'
                }}>

                  {job.command}
                </div>
                <div
                style={{
                  color: 'var(--text-muted)'
                }}>

                  {job.user}
                </div>
                <div
                style={{
                  color: 'var(--text-muted)',
                  fontSize: '10px'
                }}>

                  {job.lastRun}
                </div>
                <div
                style={{
                  color:
                  job.status === 'failed' ?
                  'var(--ansi-red)' :
                  'var(--text-muted)',
                  fontSize: '10px'
                }}>

                  {job.nextRun}
                </div>
                <div className="flex justify-end gap-1">
                  <span
                  className="px-1 py-0.5 text-[9px] font-bold"
                  style={{
                    backgroundColor: statusColor[job.status] + '22',
                    color: statusColor[job.status],
                    border: `1px solid ${statusColor[job.status]}44`
                  }}>

                    {job.status.toUpperCase()}
                  </span>
                  <button
                  onClick={() => toggleJob(job.id)}
                  className="p-1 border transition-colors"
                  style={{
                    borderColor: 'var(--ansi-yellow)',
                    color: 'var(--ansi-yellow)'
                  }}
                  title={job.status === 'active' ? 'Pause' : 'Resume'}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor =
                    'var(--ansi-yellow)';
                    e.currentTarget.style.color = 'var(--bg-primary)';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = 'transparent';
                    e.currentTarget.style.color = 'var(--ansi-yellow)';
                  }}>

                    {job.status === 'active' ?
                  <Pause size={9} /> :

                  <Play size={9} />
                  }
                  </button>
                  <button
                  onClick={() => removeJob(job.id)}
                  className="p-1 border transition-colors"
                  style={{
                    borderColor: 'var(--ansi-red)',
                    color: 'var(--ansi-red)'
                  }}
                  title="Delete"
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor = 'var(--ansi-red)';
                    e.currentTarget.style.color = 'var(--bg-primary)';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = 'transparent';
                    e.currentTarget.style.color = 'var(--ansi-red)';
                  }}>

                    <Trash2 size={9} />
                  </button>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </motion.div>

      {/* Cron reference */}
      <motion.div
        custom={2}
        variants={sectionVariants}
        initial="hidden"
        animate="visible"
        style={{
          backgroundColor: 'var(--bg-secondary)',
          border: '1px solid var(--border-color)'
        }}>

        <div
          className="px-3 py-1.5 text-[10px] border-b"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-tertiary)',
            color: 'var(--text-muted)'
          }}>

          <span
            style={{
              color: 'var(--ansi-green)'
            }}>

            $
          </span>{' '}
          man 5 crontab | grep FORMAT
        </div>
        <div className="p-3 grid grid-cols-5 gap-2 text-center text-[10px]">
          {[
          'MIN\n0-59',
          'HOUR\n0-23',
          'DOM\n1-31',
          'MON\n1-12',
          'DOW\n0-6'].
          map((f) => {
            const [label, range] = f.split('\n');
            return (
              <div
                key={label}
                className="p-2 border"
                style={{
                  borderColor: 'var(--border-color)'
                }}>

                <div
                  style={{
                    color: 'var(--ansi-yellow)',
                    fontWeight: 700
                  }}>

                  {label}
                </div>
                <div
                  style={{
                    color: 'var(--text-muted)'
                  }}>

                  {range}
                </div>
              </div>);

          })}
        </div>
        <div
          className="px-3 pb-3 space-y-1 text-[10px]"
          style={{
            color: 'var(--text-muted)'
          }}>

          {[
          {
            expr: '* * * * *',
            desc: 'every minute'
          },
          {
            expr: '0 * * * *',
            desc: 'every hour'
          },
          {
            expr: '0 0 * * *',
            desc: 'daily at midnight'
          },
          {
            expr: '0 0 * * 0',
            desc: 'weekly on Sunday'
          },
          {
            expr: '*/5 * * * *',
            desc: 'every 5 minutes'
          }].
          map((ex) =>
          <div key={ex.expr} className="flex gap-4">
              <span
              style={{
                color: 'var(--ansi-cyan)',
                width: 100,
                flexShrink: 0
              }}>

                {ex.expr}
              </span>
              <span>{ex.desc}</span>
            </div>
          )}
        </div>
      </motion.div>
    </div>);

}