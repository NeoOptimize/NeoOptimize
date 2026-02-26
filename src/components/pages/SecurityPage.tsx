import React, { useState, useRef } from 'react';
import { motion } from 'framer-motion';
import { Shield, Lock, AlertTriangle, CheckCircle } from 'lucide-react';
export function SecurityPage() {
  const [scanning, setScanning] = useState(false);
  const [scanOutput, setScanOutput] = useState<string[]>([]);
  const outputRef = useRef<HTMLDivElement>(null);
  const runScan = () => {
    setScanning(true);
    setScanOutput([]);
    const steps = [
    'Initializing MSERT engine...',
    'Loading definitions (v1.403.1234.0)...',
    'Scanning /system32...',
    'Scanning /Users...',
    'Scanning startup items...',
    'Scan complete.'];

    steps.forEach((step, i) => {
      setTimeout(() => {
        setScanOutput((prev) => [...prev, step]);
        if (outputRef.current)
        outputRef.current.scrollTop = outputRef.current.scrollHeight;
        if (i === steps.length - 1) setScanning(false);
      }, i * 800);
    });
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
        <span>sudo msert --full-scan --verbose</span>
      </div>

      {/* MSERT Scan */}
      <div
        className="border p-4"
        style={{
          borderColor: 'var(--border-color)',
          backgroundColor: 'var(--bg-secondary)'
        }}>

        <div
          className="flex items-center gap-2 mb-4 text-xs font-bold"
          style={{
            color: 'var(--ansi-cyan)'
          }}>

          <Shield size={14} /> MSERT SECURITY SCAN
        </div>

        <div
          ref={outputRef}
          className="h-32 overflow-y-auto mb-4 p-2 border font-mono text-xs space-y-1"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--terminal-output-bg)'
          }}>

          {scanOutput.length === 0 && !scanning &&
          <div
            style={{
              color: 'var(--text-muted)'
            }}>

              Ready to scan...
            </div>
          }
          {scanOutput.map((line, i) =>
          <div
            key={i}
            style={{
              color: 'var(--text-primary)'
            }}>

              {line}
            </div>
          )}
          {scanning &&
          <div
            className="cursor-blink"
            style={{
              color: 'var(--ansi-green)'
            }}>

              _
            </div>
          }
        </div>

        {!scanning && scanOutput.length > 0 &&
        <div
          className="mb-4 p-2 border flex justify-between text-xs"
          style={{
            borderColor: 'var(--ansi-green)',
            backgroundColor: 'rgba(0,255,65,0.05)'
          }}>

            <span
            style={{
              color: 'var(--ansi-green)'
            }}>

              Threats found: 0
            </span>
            <span
            style={{
              color: 'var(--ansi-yellow)'
            }}>

              Suspicious: 2
            </span>
            <span
            style={{
              color: 'var(--text-primary)'
            }}>

              Clean: 15,847 files
            </span>
          </div>
        }

        <button
          onClick={runScan}
          disabled={scanning}
          className="w-full py-2 text-xs font-bold border transition-colors"
          style={{
            borderColor: 'var(--ansi-cyan)',
            color: scanning ? 'var(--bg-primary)' : 'var(--ansi-cyan)',
            backgroundColor: scanning ? 'var(--ansi-cyan)' : 'transparent'
          }}>

          {scanning ? 'SCANNING...' : '[RUN MSERT SCAN]'}
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Firewall Status */}
        <div
          className="border p-4"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-secondary)'
          }}>

          <div className="flex items-center justify-between mb-3">
            <div
              className="text-xs font-bold flex items-center gap-2"
              style={{
                color: 'var(--text-primary)'
              }}>

              <Lock size={14} /> FIREWALL STATUS
            </div>
            <span className="px-1.5 py-0.5 text-[9px] bg-[rgba(0,255,65,0.1)] text-[var(--ansi-green)]">
              ACTIVE
            </span>
          </div>
          <div className="space-y-2 text-xs">
            <div className="flex justify-between">
              <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                Rules Active
              </span>
              <span
                style={{
                  color: 'var(--text-primary)'
                }}>

                247
              </span>
            </div>
            <div className="flex justify-between">
              <span
                style={{
                  color: 'var(--text-muted)'
                }}>

                Blocked Today
              </span>
              <span
                style={{
                  color: 'var(--ansi-red)'
                }}>

                12
              </span>
            </div>
            <div
              className="mt-2 pt-2 border-t"
              style={{
                borderColor: 'var(--border-color)'
              }}>

              <div
                className="text-[10px] mb-1"
                style={{
                  color: 'var(--ansi-red)'
                }}>

                RECENT BLOCKED IPS
              </div>
              <div
                className="font-mono"
                style={{
                  color: 'var(--text-muted)'
                }}>

                <div>192.168.1.55 - 04:12:33</div>
                <div>10.0.0.88 - 03:45:12</div>
              </div>
            </div>
          </div>
        </div>

        {/* Vulnerability Scan */}
        <div
          className="border p-4"
          style={{
            borderColor: 'var(--border-color)',
            backgroundColor: 'var(--bg-secondary)'
          }}>

          <div
            className="flex items-center gap-2 mb-3 text-xs font-bold"
            style={{
              color: 'var(--ansi-yellow)'
            }}>

            <AlertTriangle size={14} /> VULNERABILITY CHECK
          </div>
          <div className="flex items-center gap-4 mb-4">
            <div
              className="text-3xl font-bold"
              style={{
                color: 'var(--ansi-green)'
              }}>

              87
            </div>
            <div
              className="text-xs"
              style={{
                color: 'var(--text-muted)'
              }}>

              Security Score
              <br />
              <span
                style={{
                  color: 'var(--ansi-green)'
                }}>

                Good Standing
              </span>
            </div>
          </div>
          <div className="space-y-2 text-xs">
            <div className="flex items-center gap-2">
              <CheckCircle
                size={12}
                style={{
                  color: 'var(--ansi-green)'
                }} />

              <span
                style={{
                  color: 'var(--text-primary)'
                }}>

                Open Ports Checked
              </span>
            </div>
            <div className="flex items-center gap-2">
              <CheckCircle
                size={12}
                style={{
                  color: 'var(--ansi-green)'
                }} />

              <span
                style={{
                  color: 'var(--text-primary)'
                }}>

                CVE Database Updated
              </span>
            </div>
            <div className="flex items-center gap-2">
              <AlertTriangle
                size={12}
                style={{
                  color: 'var(--ansi-yellow)'
                }} />

              <span
                style={{
                  color: 'var(--text-primary)'
                }}>

                2 Packages Outdated
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>);

}