import React, { useState, useEffect } from 'react';
import { TopBar } from '../App';
import { api } from '../lib/api';
import { toast } from 'react-hot-toast';
import {
  Zap, HardDrive, Lock, Globe, Shield, Settings, RefreshCw,
  Battery, Wrench, User, CheckCircle, Clock, AlertTriangle, Search,
  Play, BarChart3, Cpu, Activity, ChevronRight
} from 'lucide-react';

const MODULES = [
  {
    id: '01', key: 'CLEAN',       icon: HardDrive, color: '#00f0ff',
    name: 'System Cleaner',
    desc: 'Deep clean: temp files, browser caches, prefetch, WER dumps, DNS cache, recycle bin',
    tags: ['Junk', 'Cache', 'Temp', 'DNS'],
    impact: 'high', safe: true
  },
  {
    id: '15', key: 'DEEP_SCAN',   icon: Search,    color: '#00ff9d',
    name: 'Deep Junk Scanner',
    desc: 'Scan every fixed drive for junk files, obsolete package caches, residual backups, dumps, logs, and app caches',
    tags: ['All Drives', 'Packages', 'Residual', 'Report'],
    impact: 'medium', safe: true
  },
  {
    id: '02', key: 'PERFORMANCE', icon: Zap,       color: '#a855f7',
    name: 'Performance Tuner',
    desc: 'RAM flush, visual effects disable, pagefile tuning, NTFS optimization, boot sequence',
    tags: ['RAM', 'Boot', 'NTFS', 'Visual'],
    impact: 'high', safe: true
  },
  {
    id: '03', key: 'PRIVACY',     icon: Lock,      color: '#00ff9d',
    name: 'Privacy Hardener',
    desc: 'Block telemetry servers, disable Cortana, ad tracking, activity history, app diagnostics',
    tags: ['Telemetry', 'Cortana', 'Tracking'],
    impact: 'medium', safe: true
  },
  {
    id: '04', key: 'NETWORK_TEST',icon: Globe,     color: '#00f0ff',
    name: 'Network Optimizer',
    desc: 'TCP/IP tuning, DNS selection (Cloudflare/Google), QoS, Nagle off, IPv6 tweak',
    tags: ['TCP/IP', 'DNS', 'QoS'],
    impact: 'medium', safe: true
  },
  {
    id: '05', key: 'SECURITY_SCAN',icon: Shield,   color: '#ff3366',
    name: 'Security Hardening',
    desc: 'Defender tuning, Firewall hardening, SMBv1 off, TLS config, exploit protection, ASR rules',
    tags: ['Defender', 'Firewall', 'SMB', 'TLS'],
    impact: 'high', safe: true
  },
  {
    id: '06', key: 'SERVICES',    icon: Settings,  color: '#ffcc00',
    name: 'Services Manager',
    desc: '5 profiles: Home / Gaming / Workstation / Minimal / Restore. Disable unnecessary services.',
    tags: ['Services', 'Startup', 'Gaming'],
    impact: 'medium', safe: true
  },
  {
    id: '07', key: 'UPDATES',     icon: RefreshCw, color: '#a855f7',
    name: 'Update Manager',
    desc: 'Control Windows Update schedule, audit drivers, run winget upgrade, pause if gaming',
    tags: ['Windows Update', 'Driver', 'Winget'],
    impact: 'low', safe: true
  },
  {
    id: '08', key: 'POWER',       icon: Battery,   color: '#00ff9d',
    name: 'Power & Gaming Mode',
    desc: 'Ultimate Performance power plan, GPU boost, mouse latency reduction, game mode',
    tags: ['Power Plan', 'GPU', 'Gaming'],
    impact: 'medium', safe: true
  },
  {
    id: '16', key: 'SYSTEM_DIAGNOSTICS', icon: Activity, color: '#00f0ff',
    name: 'System Diagnostics',
    desc: 'Detect Windows anomalies: boot, WinRE, driver errors, event log errors, pending reboot, disk health',
    tags: ['Boot', 'Driver', 'Events', 'WinRE'],
    impact: 'high', safe: true
  },
  {
    id: '10', key: 'SYSTEM_REPAIR', icon: Wrench,  color: '#64748b',
    name: 'System Repair',
    desc: 'Conservative repair: WinRE enable, DISM RestoreHealth, SFC, Windows Update reset, service recovery',
    tags: ['SFC', 'DISM', 'WinRE', 'WU Reset'],
    impact: 'high', safe: true
  },
];

const IMPACT_COLOR = { high: 'var(--success)', medium: 'var(--warning)', low: 'var(--text-muted)' };

function ModuleCard({ mod, onRun, running, disabled }) {
  const Icon = mod.icon;
  const isRunning = running === mod.key;

  return (
    <div className="glass-panel" style={{
      padding: '1.2rem', border: `1px solid var(--border)`,
      transition: 'all 0.2s ease', cursor: 'default',
      opacity: disabled ? 0.5 : 1,
      ...(isRunning ? { borderColor: mod.color, boxShadow: `0 0 16px ${mod.color}22` } : {})
    }}
    onMouseEnter={e => { if (!disabled) e.currentTarget.style.borderColor = mod.color; }}
    onMouseLeave={e => { if (!isRunning) e.currentTarget.style.borderColor = 'var(--border)'; }}>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 38, height: 38, background: `${mod.color}18`, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
            <Icon size={18} color={mod.color} />
          </div>
          <div>
            <div style={{ fontWeight: 700, fontSize: '0.9rem' }}>{mod.name}</div>
            <div style={{ fontSize: '0.68rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>MOD-{mod.id}</div>
          </div>
        </div>
        <span style={{
          fontSize: '0.62rem', padding: '2px 8px', borderRadius: 4, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.07em',
          background: `${IMPACT_COLOR[mod.impact]}15`, color: IMPACT_COLOR[mod.impact]
        }}>{mod.impact} impact</span>
      </div>

      <p style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', lineHeight: 1.5, marginBottom: 10 }}>{mod.desc}</p>

      <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap', marginBottom: 12 }}>
        {mod.tags.map(tag => (
          <span key={tag} style={{ fontSize: '0.62rem', padding: '2px 7px', borderRadius: 4, background: 'var(--bg-elevated)', color: 'var(--text-muted)', border: '1px solid var(--border)' }}>{tag}</span>
        ))}
      </div>

      <button
        className="btn btn-primary btn-sm"
        style={{ width: '100%', justifyContent: 'center', background: isRunning ? `${mod.color}cc` : undefined }}
        disabled={disabled || isRunning}
        onClick={() => onRun(mod)}
      >
        {isRunning
          ? <><div className="spinner" style={{ width: 13, height: 13 }} /> Running...</>
          : <><Play size={13} /> Run Module</>
        }
      </button>
    </div>
  );
}

export default function Optimizer() {
  const [agents, setAgents]     = useState([]);
  const [selected, setSelected] = useState(null);
  const [running, setRunning]   = useState(null);
  const [taskLog, setTaskLog]   = useState([]);
  const [bulkMode, setBulkMode] = useState(false);

  useEffect(() => {
    api.getAgents().then(r => {
      const online = (r.agents || []).filter(a => (a.live_status || a.status) === 'online');
      setAgents(online);
      if (online.length === 1) setSelected(online[0].id);
    }).catch(() => {});
  }, []);

  async function runModule(mod) {
    if (!bulkMode && !selected) return toast.error('Select a system first');
    setRunning(mod.key);

    try {
      if (bulkMode) {
        const ids = agents.map(a => a.id);
        await api.sendBulkCommand(ids, mod.key);
        toast.success(`🚀 ${mod.name} → ${ids.length} systems`);
        setTaskLog(prev => [{ time: new Date(), module: mod.name, target: `${ids.length} systems (bulk)`, status: 'queued', color: mod.color }, ...prev.slice(0, 19)]);
      } else {
        await api.sendCommand(selected, mod.key);
        const sys = agents.find(a => a.id === selected);
        toast.success(`✓ ${mod.name} queued for ${sys?.hostname}`);
        setTaskLog(prev => [{ time: new Date(), module: mod.name, target: sys?.hostname || selected, status: 'queued', color: mod.color }, ...prev.slice(0, 19)]);
      }
    } catch (e) {
      toast.error(e.message);
      setTaskLog(prev => [{ time: new Date(), module: mod.name, target: 'error', status: 'failed', color: 'var(--danger)' }, ...prev.slice(0, 19)]);
    } finally {
      setRunning(null);
    }
  }

  async function runFullOptimize() {
    if (!bulkMode && !selected) return toast.error('Select a system first');
    setRunning('OPTIMIZE');
    try {
      if (bulkMode) {
        await api.sendBulkCommand(agents.map(a => a.id), 'OPTIMIZE');
        toast.success(`Safe Care queued for ALL ${agents.length} systems`);
      } else {
        await api.sendCommand(selected, 'OPTIMIZE');
        const sys = agents.find(a => a.id === selected);
        toast.success(`Safe Care queued for ${sys?.hostname}`);
      }
      setTaskLog(prev => [{ time: new Date(), module: 'SAFE CARE PLAN', target: bulkMode ? `${agents.length} systems` : agents.find(a=>a.id===selected)?.hostname, status: 'queued', color: 'var(--primary)' }, ...prev.slice(0, 19)]);
    } catch (e) {
      toast.error(e.message);
    } finally {
      setRunning(null);
    }
  }

  const noTarget = !bulkMode && !selected;

  return (
    <>
      <TopBar
        title={<>Optimizer <span className="text-gradient">Modules</span></>}
        subtitle="Run AI-assisted optimization and maintenance modules on approved endpoints"
        actions={
          <button className="btn btn-primary btn-sm"
            style={{ background: 'linear-gradient(135deg, var(--primary), var(--accent))' }}
            onClick={runFullOptimize}
            disabled={running === 'OPTIMIZE' || (agents.length === 0)}>
            {running === 'OPTIMIZE'
              ? <><div className="spinner" style={{ width: 13, height: 13 }} /> Running...</>
              : <><Zap size={13} /> Safe Care Plan</>
            }
          </button>
        }
      />
      <div className="page-content animate-fade-in">

        {/* Target selector */}
        <div className="glass-panel" style={{ padding: '1rem 1.2rem', marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: '1.5rem', flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <span style={{ fontSize: '0.82rem', color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>Target System:</span>
            {agents.length === 0 ? (
              <span style={{ fontSize: '0.82rem', color: 'var(--danger)' }}>⚠ No online systems</span>
            ) : (
              <div className="form-group" style={{ marginBottom: 0 }}>
                <select value={selected || ''} disabled={bulkMode}
                  onChange={e => setSelected(e.target.value)}
                  style={{ height: 34, fontSize: '0.82rem', minWidth: 220 }}>
                  <option value="">— Select system —</option>
                  {agents.map(a => <option key={a.id} value={a.id}>{a.hostname} ({a.ip_address})</option>)}
                </select>
              </div>
            )}
          </div>

          <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer', userSelect: 'none' }}>
            <div onClick={() => setBulkMode(v => !v)} style={{
              width: 36, height: 20, borderRadius: 10,
              background: bulkMode ? 'var(--primary)' : 'var(--bg-elevated)',
              border: '1px solid var(--border)', position: 'relative', cursor: 'pointer', transition: 'var(--transition)'
            }}>
              <div style={{
                width: 14, height: 14, borderRadius: 7, background: 'white',
                position: 'absolute', top: 2, left: bulkMode ? 18 : 2, transition: 'var(--transition)'
              }} />
            </div>
            <span style={{ fontSize: '0.82rem' }}>All online systems ({agents.length})</span>
          </label>

          {!noTarget && (
            <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 6 }}>
              <CheckCircle size={14} color="var(--success)" />
              <span style={{ fontSize: '0.8rem', color: 'var(--success)' }}>
                {bulkMode ? `${agents.length} systems selected` : `${agents.find(a => a.id === selected)?.hostname} selected`}
              </span>
            </div>
          )}
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 300px', gap: '1rem', alignItems: 'start' }}>

          {/* Module cards */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: '0.75rem' }}>
            {MODULES.map(mod => (
              <ModuleCard key={mod.id} mod={mod} onRun={runModule} running={running} disabled={noTarget || agents.length === 0} />
            ))}
          </div>

          {/* Task log */}
          <div className="glass-panel" style={{ padding: '1rem', position: 'sticky', top: '1rem' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: '0.75rem' }}>
              <Activity size={14} color="var(--primary)" />
              <span style={{ fontSize: '0.8rem', fontWeight: 700, color: 'var(--text-secondary)' }}>Task Queue</span>
            </div>
            {taskLog.length === 0 ? (
              <div style={{ textAlign: 'center', padding: '2rem 0', color: 'var(--text-muted)', fontSize: '0.8rem' }}>
                <Clock size={28} style={{ display: 'block', margin: '0 auto 8px', opacity: 0.4 }} />
                No tasks yet. Run a module to start.
              </div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                {taskLog.map((t, i) => (
                  <div key={i} style={{
                    padding: '8px 10px', borderRadius: 8,
                    background: 'var(--bg-elevated)', border: `1px solid ${t.color}33`,
                    fontSize: '0.75rem'
                  }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 2 }}>
                      <span style={{ fontWeight: 700, color: t.color }}>{t.module}</span>
                      <span style={{
                        fontSize: '0.62rem', padding: '1px 6px', borderRadius: 3,
                        background: t.status === 'queued' ? 'rgba(0,255,157,0.12)' : 'rgba(255,51,102,0.12)',
                        color: t.status === 'queued' ? 'var(--success)' : 'var(--danger)'
                      }}>{t.status}</span>
                    </div>
                    <div style={{ color: 'var(--text-muted)' }}>→ {t.target}</div>
                    <div style={{ color: 'var(--text-muted)', opacity: 0.6 }}>{t.time.toLocaleTimeString()}</div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

      </div>
    </>
  );
}
