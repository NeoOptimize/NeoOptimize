import React, { useState, useEffect } from 'react';
import { TopBar } from '../App';
import { api } from '../lib/api';
import { toast } from 'react-hot-toast';
import {
  Terminal, Send, Clock, CheckCircle, XCircle, Loader, Zap,
  Shield, Wifi, HardDrive, Activity, RefreshCw, Monitor,
  Search, Wrench
} from 'lucide-react';

const COMMAND_TYPES = [
  { type: 'OPTIMIZE',      label: 'Full Optimize',     icon: Zap,       desc: 'Run all NeoOptimize modules on target' },
  { type: 'CLEAN',         label: 'System Clean',      icon: HardDrive, desc: 'Clean temp files, recycle bin, logs' },
  { type: 'DEEP_SCAN',     label: 'Deep Junk Scan',    icon: Search,    desc: 'Scan all fixed drives for junk, caches, packages, residuals' },
  { type: 'COLLECT',       label: 'Collect Telemetry', icon: Activity,  desc: 'Force telemetry snapshot' },
  { type: 'SYSTEM_DIAGNOSTICS', label: 'System Diagnostics', icon: Wrench, desc: 'Detect boot, driver, Windows, and event-log anomalies' },
  { type: 'SECURITY_SCAN', label: 'Security Scan',     icon: Shield,    desc: 'Check for vulnerabilities & open ports' },
  { type: 'NETWORK_TEST',  label: 'Network Test',      icon: Wifi,      desc: 'Diagnose network connectivity' },
  { type: 'UPDATES',       label: 'Check Updates',     icon: RefreshCw, desc: 'Trigger Windows Update check' },
  { type: 'PERFORMANCE',   label: 'Performance Report',icon: Monitor,   desc: 'Detailed CPU/RAM/Disk analysis' },
];

const STATUS_ICON = {
  pending:   <Loader size={14} color="var(--warning)" style={{ animation: 'spin 1s linear infinite' }} />,
  delivered: <Clock size={14} color="var(--info)" />,
  success:   <CheckCircle size={14} color="var(--success)" />,
  failed:    <XCircle size={14} color="var(--danger)" />,
  timeout:   <XCircle size={14} color="var(--text-muted)" />,
};

export default function Commands() {
  const [agents,   setAgents]   = useState([]);
  const [commands, setCommands] = useState([]);
  const [loading,  setLoading]  = useState(true);
  const [sending,  setSending]  = useState(false);

  const [form, setForm] = useState({
    agent_id: '',
    type: 'OPTIMIZE',
    priority: 5,
    bulk: false,
  });

  async function loadAll() {
    setLoading(true);
    try {
      const [agRes, cmdRes] = await Promise.all([api.getAgents(), api.getCommands()]);
      setAgents(agRes.agents || []);
      setCommands(cmdRes.commands || []);
    } catch { toast.error('Failed to load data'); }
    finally { setLoading(false); }
  }

  useEffect(() => {
    loadAll();
    const t = setInterval(loadAll, 15000);
    return () => clearInterval(t);
  }, []);

  async function handleSend(e) {
    e.preventDefault();
    if (!form.bulk && !form.agent_id) return toast.error('Select a system');
    setSending(true);
    try {
      if (form.bulk) {
        const online = agents.filter(a => (a.live_status || a.status) === 'online').map(a => a.id);
        if (!online.length) return toast.error('No online systems');
        await api.sendBulkCommand(online, form.type, {}, form.priority);
        toast.success(`Sent "${form.type}" to ${online.length} systems`);
      } else {
        await api.sendCommand(form.agent_id, form.type, {}, form.priority);
        toast.success(`Command "${form.type}" queued`);
      }
      loadAll();
    } catch (e) { toast.error(e.message); }
    finally { setSending(false); }
  }

  const pending = commands.filter(c => c.status === 'pending').length;
  const success = commands.filter(c => c.status === 'success').length;
  const failed  = commands.filter(c => c.status === 'failed' || c.status === 'timeout').length;

  return (
    <>
      <TopBar
        title="Optimizer Tasks"
        subtitle="Schedule and monitor optimization tasks"
        actions={
          <button className="btn btn-secondary btn-sm" onClick={loadAll}>
            <RefreshCw size={13} /> Refresh
          </button>
        }
      />
      <div className="page-content animate-fade-in">

        {/* Stats row */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '1rem', marginBottom: '1.5rem' }}>
          {[
            { label: 'Pending', value: pending, color: 'var(--warning)' },
            { label: 'Succeeded', value: success, color: 'var(--success)' },
            { label: 'Failed', value: failed, color: 'var(--danger)' },
          ].map(s => (
            <div key={s.label} className="glass-panel" style={{ padding: '1.2rem 1.5rem' }}>
              <div style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginBottom: 6 }}>{s.label}</div>
              <div style={{ fontSize: '2rem', fontWeight: 800, color: s.color }}>{s.value}</div>
            </div>
          ))}
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '340px 1fr', gap: '1.5rem', alignItems: 'start' }}>

          {/* Run Task Panel */}
          <div className="glass-panel" style={{ padding: '1.5rem' }}>
            <div style={{ fontWeight: 700, fontSize: '0.95rem', marginBottom: '1.2rem', display: 'flex', alignItems: 'center', gap: 8 }}>
              <Terminal size={16} color="var(--primary)" /> Run Optimizer Task
            </div>

            <form onSubmit={handleSend} style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>
              {/* Bulk toggle */}
              <label style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer', userSelect: 'none' }}>
                <div
                  onClick={() => setForm(f => ({ ...f, bulk: !f.bulk }))}
                  style={{
                    width: 40, height: 22, borderRadius: 11,
                    background: form.bulk ? 'var(--primary)' : 'var(--bg-elevated)',
                    border: '1px solid var(--border)',
                    position: 'relative', cursor: 'pointer', transition: 'var(--transition)'
                  }}>
                  <div style={{
                    width: 16, height: 16, borderRadius: 8,
                    background: 'white',
                    position: 'absolute', top: 2,
                    left: form.bulk ? 20 : 2,
                    transition: 'var(--transition)'
                  }} />
                </div>
                <span style={{ fontSize: '0.85rem' }}>Run on ALL online systems</span>
              </label>

              {/* System Select */}
              {!form.bulk && (
                <div className="form-group" style={{ marginBottom: 0 }}>
                  <label>Target System</label>
                  <select value={form.agent_id} onChange={e => setForm(f => ({ ...f, agent_id: e.target.value }))}>
                    <option value="">— Select system —</option>
                    {agents.filter(a => (a.live_status || a.status) === 'online').map(a => (
                      <option key={a.id} value={a.id}>{a.hostname} ({a.ip_address})</option>
                    ))}
                  </select>
                </div>
              )}

              {/* Command Type */}
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Command Type</label>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                  {COMMAND_TYPES.map(cmd => (
                    <label key={cmd.type}
                      style={{
                        display: 'flex', alignItems: 'center', gap: 10,
                        padding: '10px 12px', borderRadius: 8, cursor: 'pointer',
                        background: form.type === cmd.type ? 'var(--primary-dim)' : 'var(--bg-elevated)',
                        border: `1px solid ${form.type === cmd.type ? 'var(--border-active)' : 'var(--border)'}`,
                        transition: 'var(--transition)'
                      }}>
                      <input type="radio" name="cmdType" value={cmd.type}
                        checked={form.type === cmd.type}
                        onChange={() => setForm(f => ({ ...f, type: cmd.type }))}
                        style={{ display: 'none' }} />
                      <cmd.icon size={15} color={form.type === cmd.type ? 'var(--primary)' : 'var(--text-muted)'} />
                      <div>
                        <div style={{ fontSize: '0.83rem', fontWeight: 600, color: form.type === cmd.type ? 'var(--primary)' : 'var(--text-primary)' }}>{cmd.label}</div>
                        <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)' }}>{cmd.desc}</div>
                      </div>
                    </label>
                  ))}
                </div>
              </div>

              {/* Priority */}
              <div className="form-group" style={{ marginBottom: 0 }}>
                <label>Priority (1=High, 10=Low): {form.priority}</label>
                <input type="range" min={1} max={10} value={form.priority}
                  onChange={e => setForm(f => ({ ...f, priority: parseInt(e.target.value) }))}
                  style={{ width: '100%', accentColor: 'var(--primary)' }} />
              </div>

              <button type="submit" className="btn btn-primary" disabled={sending}>
                {sending ? <><div className="spinner" style={{ width: 14, height: 14 }} /> Sending...</>
                         : <><Send size={14} /> {form.bulk ? 'Send to All' : 'Send Command'}</>}
              </button>
            </form>
          </div>

          {/* Command History */}
          <div className="glass-panel">
            <div className="section-header">
              <span className="section-title"><Clock size={14} style={{ marginRight: 8, verticalAlign: 'middle' }} />Command History</span>
            </div>
            {loading ? (
              <div className="loading-overlay"><div className="spinner" /></div>
            ) : (
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Command</th>
                      <th>System</th>
                      <th>Status</th>
                      <th>Issued By</th>
                      <th>Issued At</th>
                      <th>Completed</th>
                    </tr>
                  </thead>
                  <tbody>
                    {commands.map(cmd => (
                      <tr key={cmd.id}>
                        <td>
                          <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.82rem',
                            background: 'var(--bg-elevated)', padding: '2px 8px', borderRadius: 4 }}>
                            {cmd.type}
                          </span>
                        </td>
                        <td style={{ fontWeight: 600 }}>{cmd.hostname}</td>
                        <td>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                            {STATUS_ICON[cmd.status] || STATUS_ICON.pending}
                            <span className={`badge badge-${cmd.status === 'success' ? 'success' : cmd.status === 'failed' || cmd.status === 'timeout' ? 'failed' : 'pending'}`}>
                              {cmd.status}
                            </span>
                          </div>
                        </td>
                        <td style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                          {cmd.issued_by_email || 'system'}
                        </td>
                        <td style={{ fontSize: '0.8rem', color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
                          {cmd.created_at ? new Date(cmd.created_at).toLocaleString() : '—'}
                        </td>
                        <td style={{ fontSize: '0.8rem', color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
                          {cmd.completed_at ? new Date(cmd.completed_at).toLocaleString() : '—'}
                        </td>
                      </tr>
                    ))}
                    {commands.length === 0 && (
                      <tr><td colSpan={6}>
                        <div className="empty-state">
                          <Terminal size={36} className="empty-state-icon" />
                          <h4>No commands yet</h4>
                          <p>Issue a command using the panel on the left</p>
                        </div>
                      </td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
