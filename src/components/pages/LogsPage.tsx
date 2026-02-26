import React, { useState } from 'react';
import { motion } from 'framer-motion';
import { FileText, Download, Search, Filter } from 'lucide-react';
export function LogsPage() {
  const [generating, setGenerating] = useState(false);
  const [reportReady, setReportReady] = useState(false);
  const generateReport = () => {
    setGenerating(true);
    setTimeout(() => {
      setGenerating(false);
      setReportReady(true);
    }, 2000);
  };
  return (
    <div className="space-y-4">
      <div
        className="text-xs flex items-center gap-2"
        style={{
          color: 'var(--text-muted)'
        }}>

        <span
          style={{
            color: 'var(--ansi-green)',
            fontWeight: 700
          }}>

          $
        </span>
        <span>tail -f /var/log/syslog | tee /tmp/neooptimize-session.log</span>
      </div>

      {/* HTML Report Export */}
      <div
        className="border p-4"
        style={{
          borderColor: 'var(--border-color)',
          backgroundColor: 'var(--bg-secondary)'
        }}>

        <div
          className="flex items-center gap-2 mb-3 text-xs font-bold"
          style={{
            color: 'var(--ansi-blue)'
          }}>

          <FileText size={14} /> HTML REPORT EXPORT
        </div>
        <div
          className="text-xs font-mono mb-3 p-2 border"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--terminal-output-bg)',
            color: 'var(--text-muted)'
          }}>

          $ neooptimize --export-report --format=html
        </div>

        {!reportReady ?
        <button
          onClick={generateReport}
          disabled={generating}
          className="w-full py-2 text-xs font-bold border transition-colors flex items-center justify-center gap-2"
          style={{
            borderColor: 'var(--ansi-blue)',
            color: generating ? 'var(--bg-primary)' : 'var(--ansi-blue)',
            backgroundColor: generating ? 'var(--ansi-blue)' : 'transparent'
          }}>

            {generating ? 'GENERATING REPORT...' : '[GENERATE REPORT]'}
          </button> :

        <div className="space-y-2">
            <div
            className="text-xs"
            style={{
              color: 'var(--ansi-green)'
            }}>

              ✓ Report generated successfully
            </div>
            <div
            className="flex items-center justify-between p-2 border"
            style={{
              borderColor: 'var(--border-color)',
              backgroundColor: 'var(--bg-primary)'
            }}>

              <span
              className="text-xs"
              style={{
                color: 'var(--text-primary)'
              }}>

                report_2024-01-15_04-23.html
              </span>
              <button
              className="px-2 py-1 text-[10px] font-bold border flex items-center gap-1"
              style={{
                borderColor: 'var(--ansi-green)',
                color: 'var(--ansi-green)'
              }}>

                <Download size={10} /> DOWNLOAD
              </button>
            </div>
          </div>
        }
      </div>

      {/* Log Viewer */}
      <div
        className="border flex flex-col h-[500px]"
        style={{
          borderColor: 'var(--border-color)',
          backgroundColor: 'var(--bg-secondary)'
        }}>

        <div
          className="p-2 border-b flex items-center justify-between"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-tertiary)'
          }}>

          <div className="flex gap-2">
            {['ALL', 'OK', 'WARN', 'ERR', 'INFO'].map((f) =>
            <button
              key={f}
              className="px-2 py-0.5 text-[10px] border"
              style={{
                borderColor: 'var(--border-color)',
                color: 'var(--text-muted)'
              }}>

                {f}
              </button>
            )}
          </div>
          <div
            className="flex items-center gap-2 px-2 py-0.5 border"
            style={{
              borderColor: 'var(--border-color)',
              backgroundColor: 'var(--bg-primary)'
            }}>

            <Search
              size={10}
              style={{
                color: 'var(--text-muted)'
              }} />

            <input
              type="text"
              placeholder="grep..."
              className="bg-transparent outline-none text-[10px] w-24"
              style={{
                color: 'var(--text-primary)'
              }} />

          </div>
        </div>

        <div
          className="flex-1 overflow-y-auto p-2 font-mono text-xs space-y-1"
          style={{
            backgroundColor: 'var(--terminal-output-bg)'
          }}>

          {[
          {
            time: '04:22:31',
            level: 'INFO',
            msg: 'neooptimize daemon started',
            color: 'var(--ansi-blue)'
          },
          {
            time: '04:22:38',
            level: 'OK',
            msg: 'Loaded config successfully',
            color: 'var(--ansi-green)'
          },
          {
            time: '04:22:41',
            level: 'ERR',
            msg: 'Disk optimization failed',
            color: 'var(--ansi-red)'
          },
          {
            time: '04:22:58',
            level: 'WARN',
            msg: 'Memory threshold at 67%',
            color: 'var(--ansi-yellow)'
          },
          {
            time: '04:23:05',
            level: 'OK',
            msg: 'Network latency reduced',
            color: 'var(--ansi-green)'
          }].
          map((log, i) =>
          <div key={i} className="flex gap-2">
              <span
              style={{
                color: 'var(--text-muted)'
              }}>

                {log.time}
              </span>
              <span
              style={{
                color: log.color
              }}>

                [{log.level}]
              </span>
              <span
              style={{
                color: 'var(--text-primary)'
              }}>

                {log.msg}
              </span>
            </div>
          )}
          <div
            className="flex items-center gap-1 mt-1"
            style={{
              color: 'var(--text-muted)'
            }}>

            <span
              style={{
                color: 'var(--ansi-green)'
              }}>

              {'>'}
            </span>
            <span
              className="cursor-blink"
              style={{
                color: 'var(--ansi-green)'
              }}>

              _
            </span>
          </div>
        </div>
      </div>
    </div>);

}