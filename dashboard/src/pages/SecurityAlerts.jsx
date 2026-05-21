import React, { useState, useEffect } from 'react';
import { TopBar } from '../App';
import { api } from '../lib/api';
import { toast } from 'react-hot-toast';
import {
  Shield, AlertTriangle, CheckCircle, RefreshCw, Search,
  Cpu, Globe, ChevronRight, Eye, XCircle, Brain, Zap,
  Activity, Clock, Server
} from 'lucide-react';

const SEV_CONFIG = {
  critical: { color: '#ff1744', bg: 'rgba(255,23,68,0.12)', label: 'CRITICAL' },
  high:     { color: '#ff6d00', bg: 'rgba(255,109,0,0.12)',  label: 'HIGH'     },
  medium:   { color: '#ffcc00', bg: 'rgba(255,204,0,0.12)', label: 'MEDIUM'   },
  low:      { color: '#00ff9d', bg: 'rgba(0,255,157,0.12)', label: 'LOW'      },
};

const AI_DECISION_CONFIG = {
  QUARANTINE: { color: '#ff1744', icon: '🔒', label: 'Quarantine' },
  AUTOIMMUNE: { color: '#ff6d00', icon: '⚔️', label: 'Autoimmune' },
  MONITOR:    { color: '#ffcc00', icon: '👁️',  label: 'Monitor'    },
  IGNORE:     { color: '#64748b', icon: '✓',  label: 'Ignore'      },
};

function SeverityBadge({ severity }) {
  const cfg = SEV_CONFIG[severity?.toLowerCase()] || SEV_CONFIG.low;
  return (
    <span style={{
      padding: '3px 10px', borderRadius: 5, fontSize: '0.68rem',
      fontWeight: 800, letterSpacing: '0.08em',
      background: cfg.bg, color: cfg.color, border: `1px solid ${cfg.color}44`
    }}>{cfg.label}</span>
  );
}

function AiDecisionBadge({ decision }) {
  if (!decision) return <span style={{ color: 'var(--text-muted)', fontSize: '0.78rem' }}>—</span>;
  const cfg = AI_DECISION_CONFIG[decision] || { color: 'var(--text-muted)', icon: '?', label: decision };
  return (
    <span style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: '0.8rem', color: cfg.color, fontWeight: 600 }}>
      <span>{cfg.icon}</span> {cfg.label}
    </span>
  );
}

function ThreatCheckPanel({ onClose }) {
  const [ip, setIp]     = useState('');
  const [hash, setHash] = useState('');
  const [ipResult, setIpResult]     = useState(null);
  const [hashResult, setHashResult] = useState(null);
  const [loading, setLoading] = useState(false);

  async function checkIp() {
    if (!ip.trim()) return;
    setLoading(true);
    try {
      const r = await api.checkIp(ip.trim());
      setIpResult(r);
    } catch (e) {
      toast.error('IP check failed: ' + e.message);
    } finally { setLoading(false); }
  }

  async function checkHash() {
    if (!hash.trim()) return;
    setLoading(true);
    try {
      const r = await api.checkHash(hash.trim());
      setHashResult(r);
    } catch (e) {
      toast.error('Hash check failed: ' + e.message);
    } finally { setLoading(false); }
  }

  return (
    <div style={{
      position: 'fixed', top: 0, left: 0, right: 0, bottom: 0,
      background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 9999
    }}>
      <div className="glass-panel" style={{ width: 520, padding: '1.5rem', position: 'relative' }}>
        <button onClick={onClose} style={{ position: 'absolute', top: 12, right: 12, background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)' }}>
          <XCircle size={20} />
        </button>
        <h3 style={{ margin: '0 0 1.2rem', display: 'flex', alignItems: 'center', gap: 10 }}>
          <Shield size={18} color="var(--danger)" /> Nullclaw Threat Intelligence
        </h3>

        <div style={{ marginBottom: '1rem' }}>
          <label style={{ fontSize: '0.8rem', color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>Check IP Address</label>
          <div style={{ display: 'flex', gap: 8 }}>
            <input value={ip} onChange={e => setIp(e.target.value)} placeholder="e.g. 185.220.101.5"
              className="form-group input" style={{ flex: 1, height: 36, padding: '0 12px', background: 'var(--bg-elevated)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontFamily: 'var(--font-mono)', fontSize: '0.85rem' }}
              onKeyDown={e => e.key === 'Enter' && checkIp()} />
            <button className="btn btn-secondary btn-sm" onClick={checkIp} disabled={loading}>Check</button>
          </div>
          {ipResult?.result && (
            <div style={{ marginTop: 8, padding: '10px 12px', borderRadius: 8, background: 'var(--bg-elevated)', border: '1px solid var(--border)', fontSize: '0.78rem', fontFamily: 'var(--font-mono)' }}>
              <div style={{ color: ipResult.result.threat_level >= 7 ? 'var(--danger)' : 'var(--success)' }}>
                Threat Level: {ipResult.result.threat_level ?? 'Unknown'} | Type: {ipResult.result.type || 'N/A'}
              </div>
            </div>
          )}
        </div>

        <div>
          <label style={{ fontSize: '0.8rem', color: 'var(--text-muted)', display: 'block', marginBottom: 6 }}>Check File Hash (SHA-256)</label>
          <div style={{ display: 'flex', gap: 8 }}>
            <input value={hash} onChange={e => setHash(e.target.value)} placeholder="SHA-256 hash..."
              className="form-group input" style={{ flex: 1, height: 36, padding: '0 12px', background: 'var(--bg-elevated)', border: '1px solid var(--border)', borderRadius: 8, color: 'var(--text-primary)', fontFamily: 'var(--font-mono)', fontSize: '0.78rem' }}
              onKeyDown={e => e.key === 'Enter' && checkHash()} />
            <button className="btn btn-secondary btn-sm" onClick={checkHash} disabled={loading}>Check</button>
          </div>
          {hashResult?.result && (
            <div style={{ marginTop: 8, padding: '10px 12px', borderRadius: 8, background: 'var(--bg-elevated)', border: '1px solid var(--border)', fontSize: '0.78rem', fontFamily: 'var(--font-mono)' }}>
              <div style={{ color: 'var(--text-secondary)' }}>{JSON.stringify(hashResult.result)}</div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default function SecurityAlerts() {
  const [alerts, setAlerts]       = useState([]);
  const [loading, setLoading]     = useState(true);
  const [showResolved, setResolved] = useState(false);
  const [search, setSearch]       = useState('');
  const [expanded, setExpanded]   = useState(null);
  const [showThreatCheck, setThreatCheck] = useState(false);
  const [counts, setCounts]       = useState({ critical: 0, high: 0, medium: 0, low: 0 });

  async function load(resolved = showResolved) {
    setLoading(true);
    try {
      const r = await api.getAlerts({ resolved, limit: 200 });
      const data = r.alerts || [];
      setAlerts(data);
      setCounts({
        critical: data.filter(a => a.severity === 'critical').length,
        high:     data.filter(a => a.severity === 'high').length,
        medium:   data.filter(a => a.severity === 'medium').length,
        low:      data.filter(a => a.severity === 'low').length,
      });
    } catch (e) {
      toast.error('Failed to load alerts: ' + e.message);
    } finally { setLoading(false); }
  }

  useEffect(() => { load(); }, []);

  async function handleResolve(id) {
    try {
      await api.resolveAlert(id);
      toast.success('Alert resolved');
      setAlerts(prev => prev.filter(a => a.id !== id));
    } catch (e) { toast.error(e.message); }
  }

  function toggleResolved() {
    const newVal = !showResolved;
    setResolved(newVal);
    load(newVal);
  }

  const filtered = alerts.filter(a =>
    !search ||
    a.rule_name?.toLowerCase().includes(search.toLowerCase()) ||
    a.hostname?.toLowerCase().includes(search.toLowerCase()) ||
    a.src_ip?.includes(search) ||
    a.process_name?.toLowerCase().includes(search.toLowerCase())
  );

  const unresolved = alerts.filter(a => !a.resolved).length;

  return (
    <>
      {showThreatCheck && <ThreatCheckPanel onClose={() => setThreatCheck(false)} />}

      <TopBar
        title={<>Security <span className="text-gradient">Alerts</span></>}
        subtitle={`${unresolved} active threats — AI-analyzed by Ollama & Nullclaw`}
        actions={
          <div style={{ display: 'flex', gap: 8 }}>
            <button className="btn btn-secondary btn-sm" onClick={() => setThreatCheck(true)}>
              <Shield size={13} /> Threat Intel
            </button>
            <button className="btn btn-secondary btn-sm" onClick={() => load()}>
              <RefreshCw size={13} />
            </button>
          </div>
        }
      />
      <div className="page-content animate-fade-in">

        {/* Severity stats */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '0.75rem', marginBottom: '0.75rem' }}>
          {Object.entries(SEV_CONFIG).map(([sev, cfg]) => (
            <div key={sev} className="glass-panel" style={{
              padding: '1rem', border: `1px solid ${cfg.color}22`,
              boxShadow: counts[sev] > 0 ? `0 0 12px ${cfg.color}18` : 'none'
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: '0.72rem', color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.08em' }}>{sev}</span>
                <AlertTriangle size={14} color={cfg.color} />
              </div>
              <div style={{ fontSize: '2rem', fontWeight: 800, color: cfg.color, lineHeight: 1.1, marginTop: 4 }}>{counts[sev]}</div>
              <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>active alerts</div>
            </div>
          ))}
        </div>

        {/* Filters */}
        <div style={{ display: 'flex', gap: 10, marginBottom: '0.75rem', alignItems: 'center' }}>
          <div className="topbar-search" style={{ width: 280 }}>
            <Search size={14} color="var(--text-muted)" />
            <input placeholder="Filter by rule, host, IP, process..." value={search} onChange={e => setSearch(e.target.value)} />
          </div>
          <button
            className={`btn btn-sm ${showResolved ? 'btn-primary' : 'btn-secondary'}`}
            onClick={toggleResolved}
          >
            {showResolved ? <CheckCircle size={13} /> : <Eye size={13} />}
            {showResolved ? 'Showing Resolved' : 'Show Resolved'}
          </button>
          <span style={{ marginLeft: 'auto', fontSize: '0.8rem', color: 'var(--text-muted)' }}>
            {filtered.length} alerts
          </span>
        </div>

        {/* Alert table */}
        <div className="glass-panel">
          {loading ? (
            <div className="loading-overlay"><div className="spinner" /></div>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Severity</th>
                    <th>Rule</th>
                    <th>System</th>
                    <th>Source IP</th>
                    <th>AI Decision</th>
                    <th>Confidence</th>
                    <th>Time</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {filtered.map(alert => (
                    <React.Fragment key={alert.id}>
                      <tr
                        style={{ cursor: 'pointer', background: expanded === alert.id ? 'var(--bg-elevated)' : undefined }}
                        onClick={() => setExpanded(expanded === alert.id ? null : alert.id)}
                      >
                        <td><SeverityBadge severity={alert.severity} /></td>
                        <td>
                          <div style={{ fontWeight: 600, fontSize: '0.85rem' }}>{alert.rule_name || 'Unknown Rule'}</div>
                          <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>{alert.source}</div>
                        </td>
                        <td>
                          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                            <Server size={13} color="var(--primary)" />
                            <span style={{ fontSize: '0.85rem', fontWeight: 500 }}>{alert.hostname || '—'}</span>
                          </div>
                        </td>
                        <td>
                          <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.8rem', color: alert.src_ip ? 'var(--warning)' : 'var(--text-muted)' }}>
                            {alert.src_ip || '—'}
                          </span>
                        </td>
                        <td><AiDecisionBadge decision={alert.ai_decision} /></td>
                        <td>
                          {alert.ai_confidence != null ? (
                            <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                              <div style={{ width: 50, height: 4, borderRadius: 2, background: 'var(--border)' }}>
                                <div style={{ width: `${alert.ai_confidence}%`, height: '100%', borderRadius: 2,
                                  background: alert.ai_confidence > 80 ? 'var(--success)' : alert.ai_confidence > 50 ? 'var(--warning)' : 'var(--danger)' }} />
                              </div>
                              <span style={{ fontSize: '0.78rem', color: 'var(--text-muted)' }}>{alert.ai_confidence}%</span>
                            </div>
                          ) : <span style={{ color: 'var(--text-muted)' }}>—</span>}
                        </td>
                        <td style={{ fontSize: '0.78rem', color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>
                          {alert.created_at ? new Date(alert.created_at).toLocaleString() : '—'}
                        </td>
                        <td>
                          {!alert.resolved && (
                            <button
                              className="btn btn-sm"
                              style={{ background: 'rgba(0,255,157,0.12)', color: 'var(--success)', border: '1px solid var(--success)44' }}
                              onClick={e => { e.stopPropagation(); handleResolve(alert.id); }}
                              title="Mark resolved"
                            >
                              <CheckCircle size={12} /> Resolve
                            </button>
                          )}
                        </td>
                      </tr>

                      {/* Expanded detail row */}
                      {expanded === alert.id && (
                        <tr>
                          <td colSpan={8} style={{ padding: 0 }}>
                            <div style={{
                              padding: '1rem 1.5rem',
                              background: 'linear-gradient(90deg, rgba(255,23,68,0.04) 0%, transparent 100%)',
                              borderLeft: `3px solid ${(SEV_CONFIG[alert.severity?.toLowerCase()] || SEV_CONFIG.low).color}`,
                              display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '1rem'
                            }}>
                              <div>
                                <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginBottom: 4 }}>DESCRIPTION</div>
                                <div style={{ fontSize: '0.85rem', lineHeight: 1.6 }}>{alert.description || 'No description available'}</div>
                                {alert.process_name && (
                                  <div style={{ marginTop: 8 }}>
                                    <span style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>PROCESS: </span>
                                    <code style={{ fontSize: '0.8rem', color: 'var(--warning)' }}>{alert.process_name}</code>
                                  </div>
                                )}
                              </div>
                              <div>
                                <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginBottom: 4 }}>AI ANALYSIS</div>
                                {alert.ai_reason ? (
                                  <div style={{ fontSize: '0.83rem', lineHeight: 1.6, color: 'var(--text-secondary)' }}>
                                    <Brain size={12} style={{ marginRight: 4, verticalAlign: 'middle' }} />
                                    {alert.ai_reason}
                                  </div>
                                ) : (
                                  <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>No AI analysis available</div>
                                )}
                                {alert.ai_model && (
                                  <div style={{ marginTop: 6, fontSize: '0.72rem', color: 'var(--text-muted)' }}>
                                    Model: <code>{alert.ai_model}</code>
                                  </div>
                                )}
                              </div>
                            </div>
                          </td>
                        </tr>
                      )}
                    </React.Fragment>
                  ))}

                  {filtered.length === 0 && !loading && (
                    <tr>
                      <td colSpan={8}>
                        <div className="empty-state">
                          <Shield size={40} className="empty-state-icon" style={{ color: 'var(--success)' }} />
                          <h4>{showResolved ? 'No resolved alerts' : '🛡️ No active threats detected'}</h4>
                          <p>{showResolved ? 'Resolved alerts will appear here' : 'Your systems are clean. Security monitoring is active.'}</p>
                        </div>
                      </td>
                    </tr>
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
