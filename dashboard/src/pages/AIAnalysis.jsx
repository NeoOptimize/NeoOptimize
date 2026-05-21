import React, { useState, useEffect } from 'react';
import { TopBar } from '../App';
import { api } from '../lib/api';
import { toast } from 'react-hot-toast';
import {
  Brain, Zap, Activity, Server, RefreshCw, CheckCircle,
  XCircle, AlertTriangle, ChevronRight, Cpu, HardDrive,
  Shield, Globe, Database, Code, ExternalLink
} from 'lucide-react';

// ── Integration badges ───────────────────────────────────────────
const INTEGRATIONS = [
  { key: 'neocortex', label: 'NeoCortex',    icon: Activity, color: '#00e57a', desc: 'Local hybrid ML scoring' },
  { key: 'supabase',  label: 'Supabase',     icon: Database, color: '#3ecf8e', desc: 'Audit log mirror & cloud persistence' },
  { key: 'telegram',  label: 'Telegram',     icon: Globe,    color: '#2ca5e0', desc: 'Real-time alerts & notifications' },
  { key: 'ollama',    label: 'Ollama Local', icon: Brain,    color: '#a855f7', desc: 'Local AI health scoring & threat analysis' },
  { key: 'gemini',    label: 'Gemini',       icon: Zap,      color: '#00f0ff', desc: 'Google AI system deep analysis' },
  { key: 'hf',        label: 'HuggingFace',  icon: Code,     color: '#ff6b35', desc: 'HF Space inference & model hosting' },
  { key: 'e2b',       label: 'E2B Sandbox',  icon: Shield,   color: '#00ff9d', desc: 'Sandboxed Python code execution' },
  { key: 'nullclaw',  label: 'Nullclaw',     icon: AlertTriangle, color: '#ff3366', desc: 'Threat intelligence & IOC database' },
];

function IntegrationCard({ cfg, status }) {
  const Icon = cfg.icon;
  const active = status?.enabled;
  return (
    <div className="glass-panel" style={{
      padding: '1rem', border: `1px solid ${active ? cfg.color + '40' : 'var(--border)'}`,
      transition: 'all 0.2s ease',
      boxShadow: active ? `0 0 16px ${cfg.color}15` : 'none'
    }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 36, height: 36, borderRadius: 10, background: `${cfg.color}18`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon size={18} color={cfg.color} />
          </div>
          <span style={{ fontWeight: 700, fontSize: '0.92rem' }}>{cfg.label}</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
          <div style={{ width: 7, height: 7, borderRadius: 4, background: active ? cfg.color : 'var(--text-muted)', boxShadow: active ? `0 0 8px ${cfg.color}` : 'none' }} />
          <span style={{ fontSize: '0.72rem', color: active ? cfg.color : 'var(--text-muted)', fontWeight: 700 }}>{active ? 'CONNECTED' : 'DISABLED'}</span>
        </div>
      </div>
      <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', margin: 0, lineHeight: 1.5 }}>{cfg.desc}</p>
      {status?.model && <div style={{ marginTop: 6, fontSize: '0.72rem', color: 'var(--text-muted)' }}>Model: <code style={{ color: cfg.color }}>{status.model}</code></div>}
      {status?.space && <div style={{ marginTop: 6, fontSize: '0.72rem', color: 'var(--text-muted)' }}>Space: <code style={{ color: cfg.color }}>{status.space}</code></div>}
    </div>
  );
}

function GeminiAnalysisCard({ agentId, hostname }) {
  const [result, setResult]   = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError]     = useState(null);

  async function runAnalysis() {
    setLoading(true); setError(null);
    try {
      const r = await api.getGeminiAnalysis(agentId);
      setResult(r.analysis);
    } catch (e) {
      setError(e.message.includes('disabled') ? 'GEMINI_API_KEY not configured in .env' : e.message);
    } finally { setLoading(false); }
  }

  const statusColor = result?.status === 'healthy' ? 'var(--success)' : result?.status === 'warning' ? 'var(--warning)' : 'var(--danger)';

  return (
    <div className="glass-panel" style={{ padding: '1.2rem' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 34, height: 34, borderRadius: 8, background: 'rgba(0,240,255,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Zap size={16} color="var(--primary)" />
          </div>
          <div>
            <div style={{ fontWeight: 700, fontSize: '0.9rem' }}>Gemini Deep Analysis</div>
            <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>{hostname} — Google AI</div>
          </div>
        </div>
        <button className="btn btn-primary btn-sm" onClick={runAnalysis} disabled={loading}>
          {loading ? <><div className="spinner" style={{ width: 13, height: 13 }} /> Analyzing...</> : <><Zap size={13} /> Analyze</>}
        </button>
      </div>

      {error && <div className="alert alert-danger" style={{ marginBottom: 0 }}><XCircle size={14} /><span>{error}</span></div>}

      {result && !error && (
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: '0.75rem' }}>
            <div style={{
              padding: '6px 14px', borderRadius: 8, fontWeight: 700,
              background: `${statusColor}15`, color: statusColor, fontSize: '0.8rem', letterSpacing: '0.06em'
            }}>{result.status?.toUpperCase()}</div>
            <div style={{ fontSize: '1.5rem', fontWeight: 800, color: statusColor }}>{result.score}/100</div>
            <div style={{ fontSize: '0.78rem', color: 'var(--text-muted)' }}>System Health</div>
          </div>

          {result.findings?.length > 0 && (
            <div style={{ marginBottom: '0.75rem' }}>
              <div style={{ fontSize: '0.72rem', color: 'var(--danger)', letterSpacing: '0.08em', fontWeight: 700, marginBottom: 6 }}>⚠ FINDINGS</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                {result.findings.map((f, i) => (
                  <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 8, fontSize: '0.82rem', color: 'var(--text-secondary)' }}>
                    <ChevronRight size={13} color="var(--danger)" style={{ flexShrink: 0, marginTop: 2 }} /> {f}
                  </div>
                ))}
              </div>
            </div>
          )}

          {result.recommendations?.length > 0 && (
            <div>
              <div style={{ fontSize: '0.72rem', color: 'var(--success)', letterSpacing: '0.08em', fontWeight: 700, marginBottom: 6 }}>✓ RECOMMENDATIONS</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                {result.recommendations.map((r, i) => (
                  <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 8, fontSize: '0.82rem', color: 'var(--text-secondary)' }}>
                    <CheckCircle size={13} color="var(--success)" style={{ flexShrink: 0, marginTop: 2 }} /> {r}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {!result && !error && !loading && (
        <div style={{ textAlign: 'center', padding: '1.5rem', color: 'var(--text-muted)', fontSize: '0.82rem' }}>
          Click <strong>Analyze</strong> to run Gemini AI deep inspection on this system
        </div>
      )}
    </div>
  );
}

function E2BSandboxPanel() {
  const [code, setCode]     = useState(`import psutil\nimport json\n\ncpu = psutil.cpu_percent(interval=1)\nmem = psutil.virtual_memory()\ndisk = psutil.disk_usage('/')\n\nprint(json.dumps({\n    'cpu': cpu,\n    'memory_percent': mem.percent,\n    'disk_percent': disk.percent\n}))`);
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);

  async function run() {
    setLoading(true);
    try {
      const r = await api.runE2bAnalysis(code);
      setResult(r);
    } catch (e) {
      setResult({ success: false, error: e.message });
    } finally { setLoading(false); }
  }

  return (
    <div className="glass-panel" style={{ padding: '1.2rem' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '0.75rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 34, height: 34, borderRadius: 8, background: 'rgba(0,255,157,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Code size={16} color="var(--success)" />
          </div>
          <div>
            <div style={{ fontWeight: 700, fontSize: '0.9rem' }}>E2B Sandbox</div>
            <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>Secure Python execution</div>
          </div>
        </div>
        <button className="btn btn-sm" style={{ background: 'rgba(0,255,157,0.12)', color: 'var(--success)', border: '1px solid var(--success)44' }} onClick={run} disabled={loading}>
          {loading ? <><div className="spinner" style={{ width: 13, height: 13 }} /> Running...</> : '▶ Execute'}
        </button>
      </div>

      <textarea value={code} onChange={e => setCode(e.target.value)} rows={8}
        style={{ width: '100%', background: '#0a0a14', border: '1px solid var(--border)', borderRadius: 8, padding: '10px 14px', color: '#00ff9d', fontFamily: 'var(--font-mono)', fontSize: '0.8rem', lineHeight: 1.6, resize: 'vertical', boxSizing: 'border-box' }} />

      {result && (
        <div style={{ marginTop: '0.75rem', padding: '10px 14px', borderRadius: 8, background: 'var(--bg-elevated)', border: `1px solid ${result.success ? 'var(--success)' : 'var(--danger)'}33`, fontFamily: 'var(--font-mono)', fontSize: '0.8rem' }}>
          {result.success ? (
            <pre style={{ margin: 0, color: 'var(--text-secondary)', overflowX: 'auto' }}>{result.text}</pre>
          ) : (
            <div style={{ color: 'var(--danger)' }}>Error: {result.error}</div>
          )}
        </div>
      )}
    </div>
  );
}

function NeoCortexInsightCard({ agentId, hostname }) {
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  async function loadInsight() {
    if (!agentId) return;
    setLoading(true); setError(null);
    try {
      const r = await api.getMlInsight(agentId);
      setResult(r.insight);
    } catch (e) {
      setError(e.message);
    } finally { setLoading(false); }
  }

  useEffect(() => {
    setResult(null);
    if (agentId) loadInsight();
  }, [agentId]);

  const riskColor = result?.risk_level === 'critical' ? 'var(--danger)'
    : result?.risk_level === 'high' ? 'var(--danger)'
      : result?.risk_level === 'medium' ? 'var(--warning)'
        : 'var(--success)';
  const components = result?.components || {};

  return (
    <div className="glass-panel" style={{ padding: '1.2rem', marginBottom: '0.75rem' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 12, marginBottom: '1rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ width: 36, height: 36, borderRadius: 8, background: 'rgba(168,85,247,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Brain size={18} color="#a855f7" />
          </div>
          <div>
            <div style={{ fontWeight: 800, fontSize: '0.95rem' }}>NeoCortex Local ML</div>
            <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>{hostname || 'No system selected'}</div>
          </div>
        </div>
        <button className="btn btn-secondary btn-sm" onClick={loadInsight} disabled={!agentId || loading}>
          {loading ? <><div className="spinner" style={{ width: 13, height: 13 }} /> Analyzing...</> : <><RefreshCw size={13} /> Analyze</>}
        </button>
      </div>

      {error && <div className="alert alert-danger"><XCircle size={14} /><span>{error}</span></div>}

      {!agentId && (
        <div style={{ padding: '1rem', color: 'var(--text-muted)', fontSize: '0.82rem', textAlign: 'center' }}>
          Select an online system for local ML scoring.
        </div>
      )}

      {result && !error && (
        <>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, minmax(0, 1fr))', gap: '0.75rem', marginBottom: '0.9rem' }}>
            {[
              { label: 'Health', value: `${result.health_score}/100`, icon: Activity, color: riskColor },
              { label: 'Risk', value: result.risk_level?.toUpperCase(), icon: AlertTriangle, color: riskColor },
              { label: 'Anomaly', value: `${result.anomaly_score}/100`, icon: Cpu, color: result.anomaly_score > 65 ? 'var(--danger)' : 'var(--success)' },
              { label: 'Confidence', value: `${Math.round((result.confidence || 0) * 100)}%`, icon: Shield, color: 'var(--primary)' },
            ].map(item => {
              const Icon = item.icon;
              return (
                <div key={item.label} style={{ padding: '0.85rem', borderRadius: 8, background: 'var(--bg-elevated)', border: '1px solid var(--border)' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-muted)', fontSize: '0.72rem', marginBottom: 6 }}>
                    <Icon size={13} color={item.color} /> {item.label}
                  </div>
                  <div style={{ color: item.color, fontWeight: 800, fontSize: '1.15rem' }}>{item.value}</div>
                </div>
              );
            })}
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1.15fr 1fr', gap: '0.75rem' }}>
            <div style={{ padding: '0.9rem', borderRadius: 8, background: 'var(--bg-elevated)', border: '1px solid var(--border)' }}>
              <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', letterSpacing: '0.08em', fontWeight: 700, marginBottom: 8 }}>COMPONENTS</div>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0, 1fr))', gap: 8 }}>
                {Object.entries(components).map(([key, value]) => (
                  <div key={key} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, fontSize: '0.8rem', padding: '7px 9px', borderRadius: 7, background: 'rgba(255,255,255,0.03)' }}>
                    <span style={{ color: 'var(--text-muted)', textTransform: 'capitalize' }}>{key}</span>
                    <strong style={{ color: value < 65 ? 'var(--danger)' : value < 82 ? 'var(--warning)' : 'var(--success)' }}>{value}</strong>
                  </div>
                ))}
              </div>

              {result.signals?.length > 0 && (
                <div style={{ marginTop: '0.85rem' }}>
                  <div style={{ fontSize: '0.72rem', color: 'var(--warning)', letterSpacing: '0.08em', fontWeight: 700, marginBottom: 6 }}>SIGNALS</div>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
                    {result.signals.slice(0, 4).map((signal, i) => (
                      <div key={`${signal.metric}-${i}`} style={{ fontSize: '0.8rem', color: 'var(--text-secondary)', display: 'flex', gap: 8, alignItems: 'flex-start' }}>
                        <ChevronRight size={13} color="var(--warning)" style={{ marginTop: 2, flexShrink: 0 }} />
                        <span>{signal.label}: {signal.value} vs baseline {signal.baseline}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>

            <div style={{ padding: '0.9rem', borderRadius: 8, background: 'var(--bg-elevated)', border: '1px solid var(--border)' }}>
              <div style={{ fontSize: '0.72rem', color: 'var(--success)', letterSpacing: '0.08em', fontWeight: 700, marginBottom: 8 }}>ACTION PLAN</div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
                {result.recommendations?.slice(0, 5).map((rec, i) => (
                  <div key={`${rec.title}-${i}`} style={{ padding: '8px 9px', borderRadius: 7, background: 'rgba(255,255,255,0.03)' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, marginBottom: 4 }}>
                      <span style={{ fontWeight: 700, fontSize: '0.82rem' }}>{rec.title}</span>
                      {rec.command && <code style={{ color: 'var(--primary)', fontSize: '0.72rem' }}>{rec.command}</code>}
                    </div>
                    <div style={{ color: 'var(--text-muted)', fontSize: '0.76rem', lineHeight: 1.45 }}>{rec.reason}</div>
                  </div>
                ))}
              </div>
              <div style={{ marginTop: '0.75rem', display: 'flex', alignItems: 'center', gap: 7, fontSize: '0.74rem', color: 'var(--text-muted)' }}>
                <HardDrive size={13} /> {result.model}
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

export default function AIAnalysis() {
  const [agents, setAgents]         = useState([]);
  const [selected, setSelected]     = useState('');
  const [integrations, setIntegrations] = useState({});
  const [loadingInt, setLoadingInt] = useState(true);

  useEffect(() => {
    api.getAgents().then(r => {
      const online = (r.agents || []).filter(a => (a.live_status || a.status) === 'online');
      setAgents(online);
      if (online.length === 1) setSelected(online[0].id);
    }).catch(() => {});

    api.getIntegrationStatus().then(r => {
      setIntegrations(r);
      setLoadingInt(false);
    }).catch(() => { setLoadingInt(false); });
  }, []);

  const selectedAgent = agents.find(a => a.id === selected);

  return (
    <>
      <TopBar
        title={<>AI <span className="text-gradient">Analysis</span></>}
        subtitle="Gemini, Ollama, E2B, HuggingFace, Nullclaw — multi-AI system intelligence"
      />
      <div className="page-content animate-fade-in">

        {/* Integration status grid */}
        <div style={{ marginBottom: '0.75rem' }}>
          <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', letterSpacing: '0.1em', textTransform: 'uppercase', marginBottom: '0.6rem' }}>
            Integration Status
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: '0.5rem' }}>
            {INTEGRATIONS.map(cfg => (
              <IntegrationCard key={cfg.key} cfg={cfg} status={integrations[cfg.key]} />
            ))}
          </div>
        </div>

        {/* Target selector */}
        <div className="glass-panel" style={{ padding: '0.9rem 1.2rem', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '1rem' }}>
          <span style={{ fontSize: '0.82rem', color: 'var(--text-muted)', whiteSpace: 'nowrap' }}>Analyze System:</span>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <select value={selected} onChange={e => setSelected(e.target.value)}
              style={{ height: 34, fontSize: '0.82rem', minWidth: 240 }}>
              <option value="">— Select online system —</option>
              {agents.map(a => <option key={a.id} value={a.id}>{a.hostname} ({a.ip_address})</option>)}
            </select>
          </div>
          {agents.length === 0 && (
            <span style={{ fontSize: '0.82rem', color: 'var(--danger)' }}>⚠ No online systems</span>
          )}
        </div>

        <NeoCortexInsightCard agentId={selected} hostname={selectedAgent?.hostname} />

        {/* Main panels */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '0.75rem', marginBottom: '0.75rem' }}>
          <GeminiAnalysisCard agentId={selected} hostname={selectedAgent?.hostname || 'No system selected'} />
          <E2BSandboxPanel />
        </div>

        {/* HF Space status */}
        <div className="glass-panel" style={{ padding: '1.2rem' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ width: 34, height: 34, borderRadius: 8, background: 'rgba(255,107,53,0.12)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <ExternalLink size={16} color="#ff6b35" />
              </div>
              <div>
                <div style={{ fontWeight: 700 }}>HuggingFace Space</div>
                <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)' }}>
                  {integrations.hf?.space || 'Not configured'} — Auto wake-up enabled
                </div>
              </div>
            </div>
            <button className="btn btn-secondary btn-sm" onClick={async () => {
              try {
                const r = await api.getHfStatus();
                toast.success(r.restarted ? 'HF Space restarted' : 'HF Space is running');
              } catch (e) { toast.error(e.message); }
            }}>
              <RefreshCw size={13} /> Check & Wake Space
            </button>
          </div>
          {integrations.hf?.enabled && (
            <div style={{ marginTop: '0.75rem', padding: '0.75rem 1rem', borderRadius: 8, background: 'var(--bg-elevated)', fontSize: '0.82rem', color: 'var(--text-muted)' }}>
              Space ID: <code style={{ color: '#ff6b35' }}>{integrations.hf.space}</code>
            </div>
          )}
        </div>

      </div>
    </>
  );
}
