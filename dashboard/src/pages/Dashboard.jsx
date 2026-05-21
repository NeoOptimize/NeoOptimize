import React, { useState, useEffect } from 'react';
import { api, createWebSocket } from '../lib/api';
import { TopBar } from '../App';
import { toast } from 'react-hot-toast';
import {
  Server, Activity, Zap, AlertTriangle, RefreshCw, BarChart3
} from 'lucide-react';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, BarChart, Bar
} from 'recharts';

// ── Optimizer modules status data (mirrors PS client) ──────────────────────
const OPTIMIZER_MODULES = [
  { id: '01', name: 'System Cleaner',        icon: '🧹', color: 'var(--primary)' },
  { id: '02', name: 'Performance Tuner',     icon: '⚡', color: 'var(--accent)' },
  { id: '03', name: 'Privacy Hardener',      icon: '🔒', color: 'var(--success)' },
  { id: '04', name: 'Network Optimizer',     icon: '🌐', color: 'var(--primary)' },
  { id: '05', name: 'Security Hardening',    icon: '🛡️', color: 'var(--danger)' },
  { id: '06', name: 'Services Manager',      icon: '⚙️', color: 'var(--warning)' },
  { id: '07', name: 'Update Manager',        icon: '🔄', color: 'var(--accent)' },
  { id: '08', name: 'Power & Gaming',        icon: '🔋', color: 'var(--success)' },
  { id: '09', name: 'Maintenance Suite',     icon: '🔧', color: 'var(--primary)' },
  { id: '10', name: 'Profile Selector',      icon: '👤', color: 'var(--text-muted)' },
];

function StatCard({ label, value, icon: Icon, color, sub, glow = false }) {
  return (
    <div className="glass-panel stat-card" style={glow ? { boxShadow: `0 0 20px ${color}22` } : {}}>
      <div className="stat-card-header">
        <span className="stat-label">{label}</span>
        <div className="stat-icon" style={{ background: `${color}22` }}>
          <Icon size={18} color={color} />
        </div>
      </div>
      <span className="stat-value" style={{ color }}>{value}</span>
      {sub && <span className="stat-change">{sub}</span>}
    </div>
  );
}

function HealthScoreGauge({ score }) {
  const color = score >= 90 ? 'var(--success)' : score >= 70 ? 'var(--warning)' : 'var(--danger)';
  const grade = score >= 90 ? 'EXCELLENT' : score >= 75 ? 'GOOD' : score >= 60 ? 'FAIR' : 'NEEDS WORK';
  const radius = 52;
  const circ = 2 * Math.PI * radius;
  const dashoffset = circ - (score / 100) * circ;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '8px 0' }}>
      <svg width="130" height="130" viewBox="0 0 130 130">
        <circle cx="65" cy="65" r={radius} fill="none" stroke="var(--border)" strokeWidth="10" />
        <circle cx="65" cy="65" r={radius} fill="none" stroke={color}
          strokeWidth="10" strokeDasharray={circ} strokeDashoffset={dashoffset}
          strokeLinecap="round" transform="rotate(-90 65 65)"
          style={{ transition: 'stroke-dashoffset 1s ease', filter: `drop-shadow(0 0 8px ${color})` }}
        />
        <text x="65" y="58" textAnchor="middle" fill={color} fontSize="24" fontWeight="800" fontFamily="Inter">{score}</text>
        <text x="65" y="74" textAnchor="middle" fill="var(--text-muted)" fontSize="10" fontFamily="Inter">/ 100</text>
      </svg>
      <div style={{ fontWeight: 700, fontSize: '0.8rem', color, letterSpacing: '0.1em' }}>{grade}</div>
      <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginTop: 2 }}>System Health Score</div>
    </div>
  );
}

const CustomTooltip = ({ active, payload }) => {
  if (!active || !payload?.length) return null;
  return (
    <div style={{
      background: 'var(--bg-elevated)', border: '1px solid var(--border-active)',
      borderRadius: 8, padding: '8px 12px', fontSize: '0.78rem'
    }}>
      {payload.map((p, i) => (
        <div key={i} style={{ color: p.color }}>{p.name}: {p.value?.toFixed ? p.value.toFixed(1) : p.value}{p.unit || '%'}</div>
      ))}
    </div>
  );
};

export default function Dashboard() {
  const [stats, setStats]         = useState({ online: 0, offline: 0, total: 0, commands_today: 0 });
  const [loading, setLoading]     = useState(true);
  const [taskBusy, setTaskBusy]   = useState(false);
  const [healthScore, setHealth]  = useState(82);
  const [cpuData, setCpuData]     = useState(Array.from({ length: 30 }, (_, i) => ({ t: i, v: Math.random() * 20 + 5 })));
  const [ramData, setRamData]     = useState(Array.from({ length: 30 }, (_, i) => ({ t: i, v: Math.random() * 3 + 2 })));
  const [taskData, setTaskData]   = useState([
    { name: 'Clean', count: 12 }, { name: 'Perf', count: 8 },
    { name: 'Security', count: 15 }, { name: 'Updates', count: 5 },
    { name: 'Network', count: 9 }, { name: 'Power', count: 6 }
  ]);

  async function loadData() {
    try {
      const stRes = await api.getStats();

      let on = 0, off = 0, cmds = 0;
      (stRes.agents || []).forEach(s => {
        if (s.status === 'online')  on  = parseInt(s.count);
        if (s.status === 'offline') off = parseInt(s.count);
      });
      (stRes.commands || []).forEach(c => { cmds += parseInt(c.count); });
      setStats({ online: on, offline: off, total: on + off, commands_today: cmds });

      // Compute health from connected systems
      const total = on + off;
      const score = total === 0 ? 82 : Math.round(70 + (on / total) * 30);
      setHealth(score);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  }

  async function handleRefreshClick() {
    if (taskBusy) {
      toast('Task sedang berjalan. Tunggu sampai selesai.');
      return;
    }
    const toastId = toast.loading('Task sedang berjalan...');
    setTaskBusy(true);
    try {
      await loadData();
      toast.success('Dashboard refreshed', { id: toastId });
    } catch (e) {
      toast.error('Refresh failed: ' + e.message, { id: toastId });
    } finally {
      setTaskBusy(false);
    }
  }

  useEffect(() => {
    loadData();

    const ws = createWebSocket((msg) => {
      if (msg.event === 'tele:update') {
        const cpu = msg.data.c;
        const ram = msg.data.r;
        if (cpu !== undefined) setCpuData(prev => [...prev.slice(1), { t: Date.now(), v: cpu }]);
        if (ram !== undefined) setRamData(prev => [...prev.slice(1), { t: Date.now(), v: (ram / 1024).toFixed(2) }]);
      } else if (msg.event === 'agent:online' || msg.event === 'agent:offline') {
        loadData();
      }
    });

    const t = setInterval(loadData, 6000);
    return () => { ws?.close(); clearInterval(t); };
  }, []);

  if (loading) return (
    <>
      <TopBar title="Overview" subtitle="System performance dashboard" />
      <div className="page-content">
        <div className="loading-overlay"><div className="spinner" /><span>Loading system data...</span></div>
      </div>
    </>
  );

  return (
    <>
      <TopBar
        title={<>System <span className="text-gradient">Overview</span></>}
        subtitle="Real-time performance & optimization monitoring"
        actions={
          <button className="btn btn-secondary btn-sm" onClick={handleRefreshClick} disabled={taskBusy}>
            {taskBusy ? <div className="spinner" style={{ width: 13, height: 13 }} /> : <RefreshCw size={13} />} Refresh
          </button>
        }
      />
      <div className="page-content animate-fade-in">

        {/* ── Row 1: Stats ─────────────────────────────────────────── */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '0.75rem', marginBottom: '0.75rem' }}>
          <StatCard label="Protected Endpoints" value={stats.total}       icon={Server}        color="var(--primary)"  sub="Synced endpoint agents" glow />
          <StatCard label="Online Now"        value={stats.online}         icon={Activity}      color="var(--success)"  sub="Active & connected"   />
          <StatCard label="Offline"           value={stats.offline}        icon={AlertTriangle} color="var(--danger)"   sub="Need attention"       />
          <StatCard label="Tasks Today"       value={stats.commands_today} icon={Zap}           color="var(--warning)"  sub="Optimization tasks"   />
        </div>

        {/* ── Row 2: Health Score + Module Grid ────────────────────── */}
        <div style={{ display: 'grid', gridTemplateColumns: '180px 1fr', gap: '0.75rem', marginBottom: '0.75rem' }}>

          {/* Health Score Gauge */}
          <div className="glass-panel" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '1rem' }}>
            <HealthScoreGauge score={healthScore} />
          </div>

          {/* Optimizer Module Status Grid */}
          <div className="glass-panel" style={{ padding: '1rem' }}>
            <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', letterSpacing: '0.1em', textTransform: 'uppercase', marginBottom: '0.75rem' }}>
              Optimizer Modules — {OPTIMIZER_MODULES.length} Available
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '0.5rem' }}>
              {OPTIMIZER_MODULES.map(m => (
                <div key={m.id} style={{
                  background: 'var(--bg-elevated)', borderRadius: 10,
                  padding: '8px 10px', border: '1px solid var(--border)',
                  display: 'flex', flexDirection: 'column', gap: 4
                }}>
                  <div style={{ fontSize: '1rem' }}>{m.icon}</div>
                  <div style={{ fontSize: '0.68rem', fontWeight: 700, color: 'var(--text-secondary)', lineHeight: 1.2 }}>{m.name}</div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                    <div style={{ width: 6, height: 6, borderRadius: 3, background: m.color, boxShadow: `0 0 6px ${m.color}` }} />
                    <span style={{ fontSize: '0.6rem', color: m.color, textTransform: 'uppercase', letterSpacing: '0.05em' }}>READY</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* ── Row 3: Charts ────────────────────────────────────────── */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '0.75rem', marginBottom: '0.75rem' }}>

          {/* CPU Chart */}
          {[
            { title: 'CPU Usage',    data: cpuData,  color: 'var(--primary)', key: 'v', unit: '%' },
            { title: 'Memory Usage', data: ramData,  color: 'var(--accent)',  key: 'v', unit: ' GB' },
          ].map(chart => (
            <div key={chart.title} className="glass-panel chart-container">
              <div className="chart-header">
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <div style={{ width: 32, height: 32, background: `${chart.color}15`, borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <Activity size={16} color={chart.color} />
                  </div>
                  <span className="chart-title">{chart.title}</span>
                </div>
                <div className="pulse" style={{ width: 6, height: 6, borderRadius: '50%', background: chart.color }} />
              </div>
              <ResponsiveContainer width="100%" height={120}>
                <AreaChart data={chart.data} margin={{ top: 10, right: 0, left: -25, bottom: 0 }}>
                  <defs>
                    <linearGradient id={`grad-${chart.title}`} x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%"  stopColor={chart.color} stopOpacity={0.2} />
                      <stop offset="95%" stopColor={chart.color} stopOpacity={0}   />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.03)" vertical={false} />
                  <XAxis dataKey="t" hide />
                  <YAxis tick={{ fontSize: 10, fill: 'var(--text-muted)' }} axisLine={false} tickLine={false} />
                  <Tooltip content={<CustomTooltip />} />
                  <Area type="monotone" dataKey={chart.key} stroke={chart.color} strokeWidth={2}
                    fill={`url(#grad-${chart.title})`} dot={false} animationDuration={1500} />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          ))}

          {/* Tasks by Type Bar Chart */}
          <div className="glass-panel chart-container">
            <div className="chart-header">
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <div style={{ width: 32, height: 32, background: 'rgba(168,85,247,0.15)', borderRadius: 8, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <BarChart3 size={16} color="var(--accent)" />
                </div>
                <span className="chart-title">Tasks by Module</span>
              </div>
            </div>
            <ResponsiveContainer width="100%" height={120}>
              <BarChart data={taskData} margin={{ top: 10, right: 0, left: -25, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.03)" vertical={false} />
                <XAxis dataKey="name" tick={{ fontSize: 9, fill: 'var(--text-muted)' }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fontSize: 9, fill: 'var(--text-muted)' }} axisLine={false} tickLine={false} />
                <Tooltip content={<CustomTooltip />} />
                <Bar dataKey="count" fill="var(--accent)" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

      </div>
    </>
  );
}
