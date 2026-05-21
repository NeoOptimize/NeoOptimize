import React, { useState, useEffect } from 'react';
import { TopBar } from '../App';
import { api } from '../lib/api';
import { Shield, RefreshCw, Search, LogIn, LogOut, Key, Trash2, UserPlus, Settings } from 'lucide-react';

const ACTION_ICONS = {
  'login.success':  <LogIn size={13} color="var(--success)" />,
  'login.failed':   <LogIn size={13} color="var(--danger)" />,
  'login.blocked':  <Shield size={13} color="var(--danger)" />,
  'logout':         <LogOut size={13} color="var(--text-muted)" />,
  'command.issued': <Key size={13} color="var(--primary)" />,
  'command.bulk':   <Key size={13} color="var(--warning)" />,
  'agent.delete':   <Trash2 size={13} color="var(--danger)" />,
  'user.create':    <UserPlus size={13} color="var(--success)" />,
  'user.update':    <Settings size={13} color="var(--info)" />,
};

export default function AuditLog() {
  const [logs, setLogs]     = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch]  = useState('');

  async function load() {
    setLoading(true);
    try {
      const res = await api.getAuditLogs();
      setLogs(res.logs || []);
    } finally { setLoading(false); }
  }

  useEffect(() => { load(); }, []);

  async function deleteLog(log) {
    if (!confirm(`Delete audit log "${log.action}"?`)) return;
    await api.deleteAuditLog(log.id);
    setLogs(prev => prev.filter(item => item.id !== log.id));
  }

  async function clearLogs() {
    if (!confirm('Delete all visible audit logs for this tenant? A new audit.clear entry will be written.')) return;
    const res = await api.clearAuditLogs();
    await load();
    alert(`Deleted ${res.deleted || 0} audit log(s).`);
  }

  const filtered = logs.filter(l =>
    !search || l.action?.includes(search) || l.actor_email?.includes(search) || l.ip_address?.includes(search)
  );

  return (
    <>
      <TopBar
        title="Audit Log"
        subtitle="Security event trail — all admin actions logged"
        actions={
          <div style={{ display: 'flex', gap: 8 }}>
            <button className="btn btn-danger btn-sm" onClick={clearLogs} disabled={!logs.length}>
              <Trash2 size={13} /> Clear
            </button>
            <button className="btn btn-secondary btn-sm" onClick={load}>
              <RefreshCw size={13} />
            </button>
          </div>
        }
      />
      <div className="page-content animate-fade-in">
        <div className="alert alert-info" style={{ marginBottom: '1.5rem' }}>
          <Shield size={16} />
          <span>Audit logs capture all authentication events, command issuances, and administrative changes for compliance and forensic analysis.</span>
        </div>

        <div style={{ marginBottom: '1rem' }}>
          <div className="topbar-search" style={{ width: 320 }}>
            <Search size={14} color="var(--text-muted)" />
            <input placeholder="Filter by action, user, IP..." value={search} onChange={e => setSearch(e.target.value)} />
          </div>
        </div>

        <div className="glass-panel">
          {loading ? (
            <div className="loading-overlay"><div className="spinner" /></div>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Action</th>
                    <th>Actor</th>
                    <th>Target</th>
                    <th>IP Address</th>
                    <th>Detail</th>
                    <th>Timestamp</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map((log) => (
                    <tr key={log.id}>
                      <td>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                          {ACTION_ICONS[log.action] || <Shield size={13} color="var(--text-muted)" />}
                          <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.8rem' }}>{log.action}</span>
                        </div>
                      </td>
                      <td style={{ fontSize: '0.83rem' }}>
                        <div>{log.actor_email || log.actor_type || 'system'}</div>
                        <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>{log.actor_type}</div>
                      </td>
                      <td style={{ fontSize: '0.8rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>
                        {log.target_type && `${log.target_type}: ${log.target_id?.slice(0, 8)}...`}
                      </td>
                      <td style={{ fontFamily: 'var(--font-mono)', fontSize: '0.8rem' }}>{log.ip_address || '—'}</td>
                      <td style={{ maxWidth: 200 }}>
                        <div style={{
                          fontSize: '0.72rem', color: 'var(--text-muted)',
                          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                          fontFamily: 'var(--font-mono)'
                        }}>
                          {log.detail ? JSON.stringify(log.detail).slice(0, 60) : '—'}
                        </div>
                      </td>
                      <td style={{ fontSize: '0.78rem', color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
                        {log.created_at ? new Date(log.created_at).toLocaleString() : '—'}
                      </td>
                      <td>
                        <button className="btn btn-danger btn-sm" onClick={() => deleteLog(log)} title="Delete audit log">
                          <Trash2 size={12} />
                        </button>
                      </td>
                    </tr>
                  ))}
                  {filtered.length === 0 && (
                    <tr><td colSpan={7}>
                      <div className="empty-state">
                        <Shield size={36} className="empty-state-icon" />
                        <h4>No audit logs</h4>
                        <p>Events will appear here as they occur</p>
                      </div>
                    </td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </>
  );
}
