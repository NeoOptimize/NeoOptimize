import React, { useCallback, useEffect, useState } from 'react';
import { TopBar } from '../App';
import { api } from '../lib/api';
import { toast } from 'react-hot-toast';
import { Lock, Server, Download, Shield, Copy, RefreshCw, Globe, Database, Brain, Zap, Code, AlertTriangle, Rocket, CheckCircle2, XCircle, Info } from 'lucide-react';

const readinessTone = {
  pass: { color: 'var(--success)', label: 'PASS', Icon: CheckCircle2 },
  warn: { color: 'var(--warning)', label: 'WARN', Icon: AlertTriangle },
  fail: { color: 'var(--danger)', label: 'FAIL', Icon: XCircle },
  info: { color: 'var(--text-muted)', label: 'INFO', Icon: Info },
};

function ReadinessCheck({ check }) {
  const tone = readinessTone[check.status] || readinessTone.info;
  const Icon = tone.Icon;
  return (
    <div style={{ display: 'grid', gridTemplateColumns: '24px 1fr auto', gap: 10, padding: '10px 0', borderBottom: '1px solid var(--border)', alignItems: 'start' }}>
      <Icon size={16} color={tone.color} style={{ marginTop: 2 }} />
      <div>
        <div style={{ fontWeight: 700, fontSize: '0.86rem' }}>{check.label}</div>
        <div style={{ color: 'var(--text-muted)', fontSize: '0.76rem', marginTop: 2 }}>{check.detail}</div>
        {check.remediation && (
          <div style={{ color: tone.color, fontSize: '0.74rem', marginTop: 4 }}>{check.remediation}</div>
        )}
      </div>
      <span style={{ color: tone.color, fontSize: '0.7rem', fontWeight: 900, letterSpacing: '0.04em' }}>{tone.label}</span>
    </div>
  );
}

export default function SettingsPage() {
  const [tab, setTab] = useState('security');
  const [pwForm, setPwForm] = useState({ current: '', next: '', confirm: '' });
  const [saving, setSaving] = useState(false);
  const [integrations, setIntegrations] = useState(null);
  const [loadingInt, setLoadingInt] = useState(false);
  const [integrationsRequested, setIntegrationsRequested] = useState(false);
  const [releaseReadiness, setReleaseReadiness] = useState(null);
  const [loadingRelease, setLoadingRelease] = useState(false);
  const [releaseRequested, setReleaseRequested] = useState(false);

  const loadIntegrations = useCallback(async () => {
    setIntegrationsRequested(true);
    setLoadingInt(true);
    try {
      const r = await api.getIntegrationStatus();
      setIntegrations(r);
    } catch (e) {
      toast.error(e.message || 'Unable to load integration status');
    }
    finally { setLoadingInt(false); }
  }, []);

  const loadReleaseReadiness = useCallback(async () => {
    setReleaseRequested(true);
    setLoadingRelease(true);
    try {
      const r = await api.getReleaseReadiness();
      setReleaseReadiness(r);
      if (r.public_ready) toast.success('Release gate passed');
      else toast.error('Release gate is blocked');
    } catch (e) {
      toast.error(e.message || 'Unable to run release readiness audit');
    }
    finally { setLoadingRelease(false); }
  }, []);

  useEffect(() => {
    if (tab === 'integrations' && !integrations && !loadingInt && !integrationsRequested) {
      loadIntegrations();
    }
  }, [tab, integrations, loadingInt, integrationsRequested, loadIntegrations]);

  useEffect(() => {
    if (tab === 'release' && !releaseReadiness && !loadingRelease && !releaseRequested) {
      loadReleaseReadiness();
    }
  }, [tab, releaseReadiness, loadingRelease, releaseRequested, loadReleaseReadiness]);

  async function handleChangePassword(e) {
    e.preventDefault();
    if (pwForm.next !== pwForm.confirm) return toast.error('Passwords do not match');
    if (pwForm.next.length < 10) return toast.error('Password must be at least 10 characters');
    setSaving(true);
    try {
      await api.changePassword(pwForm.current, pwForm.next);
      toast.success('Password changed successfully');
      setPwForm({ current: '', next: '', confirm: '' });
    } catch (e) { toast.error(e.message); }
    finally { setSaving(false); }
  }

  function copyToClipboard(text) {
    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(text).then(() => toast.success('Copied!')).catch(() => toast.error('Copy failed'));
      return;
    }
    toast.error('Clipboard is unavailable in this browser');
  }

  const serverUrl = window.location.origin;
  const installerUrl = `${serverUrl}/downloads/NeoOptimize.exe`;
  const manifestUrl = `${serverUrl}/downloads/neooptimize/manifest`;

  return (
    <>
      <TopBar title="Settings" subtitle="Application configuration and security" />
      <div className="page-content animate-fade-in">
        <div style={{ display: 'grid', gridTemplateColumns: '220px 1fr', gap: '1.5rem', alignItems: 'start' }}>
          {/* Tab menu */}
          <div className="glass-panel" style={{ padding: '8px' }}>
            {[
              { id: 'security',     icon: Lock,     label: 'Security'      },
              { id: 'release',      icon: Rocket,   label: 'Release Gate'  },
              { id: 'integrations', icon: Globe,    label: 'Integrations'  },
              { id: 'server',       icon: Server,   label: 'App Info'      },
              { id: 'deploy',       icon: Download, label: 'Deployment'    },
            ].map(t => (
              <button key={t.id}
                className={`nav-item ${tab === t.id ? 'active' : ''}`}
                style={{ width: '100%', border: 'none', cursor: 'pointer' }}
                onClick={() => setTab(t.id)}>
                <t.icon size={15} /> {t.label}
              </button>
            ))}
          </div>

          {/* Content */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '1.5rem' }}>

            {tab === 'security' && (
              <>
                <div className="glass-panel" style={{ padding: '1.5rem' }}>
                  <div style={{ fontWeight: 700, marginBottom: '1.2rem', display: 'flex', alignItems: 'center', gap: 8 }}>
                    <Lock size={16} color="var(--primary)" /> Change Password
                  </div>
                  <form onSubmit={handleChangePassword} style={{ display: 'flex', flexDirection: 'column', gap: '1rem', maxWidth: 400 }}>
                    <div className="form-group" style={{ marginBottom: 0 }}>
                      <label>Current Password</label>
                      <input type="password" value={pwForm.current} onChange={e => setPwForm(f => ({ ...f, current: e.target.value }))} placeholder="Current password" />
                    </div>
                    <div className="form-group" style={{ marginBottom: 0 }}>
                      <label>New Password</label>
                      <input type="password" value={pwForm.next} onChange={e => setPwForm(f => ({ ...f, next: e.target.value }))} placeholder="Min 10 chars, uppercase, number, symbol" />
                    </div>
                    <div className="form-group" style={{ marginBottom: 0 }}>
                      <label>Confirm New Password</label>
                      <input type="password" value={pwForm.confirm} onChange={e => setPwForm(f => ({ ...f, confirm: e.target.value }))} placeholder="Repeat new password" />
                    </div>
                    <button type="submit" className="btn btn-primary" style={{ alignSelf: 'flex-start' }} disabled={saving}>
                      <Lock size={14} /> {saving ? 'Saving...' : 'Update Password'}
                    </button>
                  </form>
                </div>

                <div className="glass-panel" style={{ padding: '1.5rem' }}>
                  <div style={{ fontWeight: 700, marginBottom: '1rem', display: 'flex', alignItems: 'center', gap: 8 }}>
                    <Shield size={16} color="var(--success)" /> Security Status
                  </div>
                  {[
                    { label: 'RSA Command Signing',      ok: true,  note: 'All commands are signed with RSA-2048' },
                    { label: 'API Key Hashing',          ok: true,  note: 'Keys stored as SHA-256 hashes only' },
                    { label: 'Rate Limiting',            ok: true,  note: '200 req/min global, 10 login/min' },
                    { label: 'Brute Force Protection',   ok: true,  note: 'IP lockout after 10 failed logins (15 min)' },
                    { label: 'JWT Authentication',       ok: true,  note: '8-hour expiry tokens' },
                    { label: 'SQL Injection Protection', ok: true,  note: 'Parameterized queries enforced' },
                    { label: 'Input Sanitization',       ok: true,  note: 'All inputs validated via Zod schemas' },
                    { label: 'Audit Logging',            ok: true,  note: 'All admin actions logged immutably' },
                    { label: 'HTTPS/TLS',                ok: false, note: 'Configure SSL certificate in nginx' },
                  ].map(item => (
                    <div key={item.label} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 0', borderBottom: '1px solid var(--border)' }}>
                      <div style={{ width: 10, height: 10, borderRadius: '50%', background: item.ok ? 'var(--success)' : 'var(--warning)', flexShrink: 0, boxShadow: item.ok ? '0 0 6px var(--success)' : 'none' }} />
                      <div style={{ flex: 1 }}>
                        <div style={{ fontWeight: 600, fontSize: '0.88rem' }}>{item.label}</div>
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>{item.note}</div>
                      </div>
                      <span style={{ fontSize: '0.72rem', color: item.ok ? 'var(--success)' : 'var(--warning)', fontWeight: 700 }}>
                        {item.ok ? 'ACTIVE' : 'CONFIGURE'}
                      </span>
                    </div>
                  ))}
                </div>
              </>
            )}

            {tab === 'release' && (
              <div className="glass-panel" style={{ padding: '1.5rem' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, alignItems: 'center', marginBottom: '1.2rem' }}>
                  <div>
                    <div style={{ fontWeight: 800, display: 'flex', alignItems: 'center', gap: 8 }}>
                      <Rocket size={16} color="var(--primary)" /> Public Release Readiness Gate
                    </div>
                    <div style={{ color: 'var(--text-muted)', fontSize: '0.78rem', marginTop: 3 }}>
                      Pre-distribution audit for service health, installer integrity, safety plane, and release hygiene.
                    </div>
                  </div>
                  <button className="btn btn-primary btn-sm" onClick={loadReleaseReadiness} disabled={loadingRelease}>
                    <RefreshCw size={13} /> {loadingRelease ? 'Auditing...' : 'Run Audit'}
                  </button>
                </div>

                {!releaseReadiness && !loadingRelease && (
                  <div style={{ textAlign: 'center', padding: '2rem', color: 'var(--text-muted)', fontSize: '0.85rem' }}>
                    Run the release gate before publishing a public installer.
                  </div>
                )}

                {releaseReadiness && (
                  <>
                    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, minmax(120px, 1fr))', gap: 10, marginBottom: '1rem' }}>
                      {[
                        { label: 'Status', value: releaseReadiness.overall_status, color: releaseReadiness.public_ready ? 'var(--success)' : 'var(--danger)' },
                        { label: 'Pass', value: releaseReadiness.summary?.pass || 0, color: 'var(--success)' },
                        { label: 'Warn', value: releaseReadiness.summary?.warn || 0, color: 'var(--warning)' },
                        { label: 'Fail', value: releaseReadiness.summary?.fail || 0, color: 'var(--danger)' },
                      ].map(item => (
                        <div key={item.label} style={{ background: 'var(--bg-elevated)', border: '1px solid var(--border)', borderRadius: 8, padding: '0.85rem' }}>
                          <div style={{ color: 'var(--text-muted)', fontSize: '0.7rem', textTransform: 'uppercase', letterSpacing: '0.06em' }}>{item.label}</div>
                          <div style={{ color: item.color, fontWeight: 900, fontSize: '1rem', marginTop: 4, textTransform: 'capitalize' }}>{String(item.value).replaceAll('_', ' ')}</div>
                        </div>
                      ))}
                    </div>

                    <div className={`alert ${releaseReadiness.public_ready ? 'alert-success' : 'alert-danger'}`} style={{ marginBottom: '1rem' }}>
                      {releaseReadiness.public_ready ? <CheckCircle2 size={16} /> : <XCircle size={16} />}
                      <div>
                        <strong>{releaseReadiness.public_ready ? 'Public beta gate passed' : 'Public release blocked'}</strong><br />
                        <span style={{ fontSize: '0.82rem' }}>
                          Channel: {releaseReadiness.release_channel} · Version: {releaseReadiness.version} · Generated: {new Date(releaseReadiness.generated_at).toLocaleString()}
                        </span>
                      </div>
                    </div>

                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 300px', gap: '1rem', alignItems: 'start' }}>
                      <div style={{ background: 'var(--bg-elevated)', border: '1px solid var(--border)', borderRadius: 8, padding: '0 1rem' }}>
                        {releaseReadiness.checks?.map(check => <ReadinessCheck key={check.id} check={check} />)}
                      </div>
                      <div style={{ background: 'var(--bg-elevated)', border: '1px solid var(--border)', borderRadius: 8, padding: '1rem' }}>
                        <div style={{ fontWeight: 800, marginBottom: 8 }}>Next Actions</div>
                        {!releaseReadiness.next_actions?.length && (
                          <div style={{ color: 'var(--text-muted)', fontSize: '0.82rem' }}>No blockers detected.</div>
                        )}
                        {releaseReadiness.next_actions?.slice(0, 6).map(item => (
                          <div key={item.id} style={{ marginBottom: 10, fontSize: '0.78rem' }}>
                            <div style={{ fontWeight: 700, color: readinessTone[item.status]?.color || 'var(--text-primary)' }}>{item.label}</div>
                            <div style={{ color: 'var(--text-muted)' }}>{item.remediation}</div>
                          </div>
                        ))}
                      </div>
                    </div>
                  </>
                )}
              </div>
            )}

            {tab === 'integrations' && (
              <div className="glass-panel" style={{ padding: '1.5rem' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1.2rem' }}>
                  <div style={{ fontWeight: 700, display: 'flex', alignItems: 'center', gap: 8 }}>
                    <Globe size={16} color="var(--primary)" /> Integration Status
                  </div>
                  <button className="btn btn-secondary btn-sm" onClick={loadIntegrations} disabled={loadingInt}>
                    <RefreshCw size={13} /> {loadingInt ? 'Checking...' : 'Test All'}
                  </button>
                </div>

                {!integrations && !loadingInt && (
                  <div style={{ textAlign: 'center', padding: '2rem', color: 'var(--text-muted)', fontSize: '0.85rem' }}>
                    Click <strong>Test All</strong> to check integration status
                  </div>
                )}

                {integrations && [
                  { key: 'supabase', label: 'Supabase', Icon: Database, color: '#3ecf8e', desc: integrations.supabase?.url || 'Audit log cloud mirror' },
                  { key: 'telegram', label: 'Telegram', Icon: Globe,    color: '#2ca5e0', desc: 'Real-time alert notifications' },
                  { key: 'ollama',   label: 'Ollama',   Icon: Brain,    color: '#a855f7', desc: integrations.ollama?.url || 'http://localhost:11434' },
                  { key: 'gemini',   label: 'Gemini',   Icon: Zap,      color: '#00f0ff', desc: 'Google AI deep analysis' },
                  { key: 'hf',       label: 'HuggingFace', Icon: Code,  color: '#ff6b35', desc: integrations.hf?.space || 'Not configured' },
                  { key: 'e2b',      label: 'E2B Sandbox', Icon: Shield, color: '#00ff9d', desc: 'Sandboxed Python execution' },
                  { key: 'nullclaw', label: 'Nullclaw', Icon: AlertTriangle, color: '#ff3366', desc: 'Threat intelligence IOC database' },
                ].map(({ key, label, Icon, color, desc }) => {
                  const ok = integrations[key]?.enabled;
                  return (
                    <div key={key} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 0', borderBottom: '1px solid var(--border)' }}>
                      <div style={{ width: 32, height: 32, borderRadius: 8, background: `${color}18`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                        <Icon size={15} color={color} />
                      </div>
                      <div style={{ flex: 1 }}>
                        <div style={{ fontWeight: 600, fontSize: '0.88rem' }}>{label}</div>
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>{desc}</div>
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                        <div style={{ width: 7, height: 7, borderRadius: 4, background: ok ? color : '#444', boxShadow: ok ? `0 0 8px ${color}` : 'none' }} />
                        <span style={{ fontSize: '0.72rem', color: ok ? color : 'var(--text-muted)', fontWeight: 700 }}>{ok ? 'CONNECTED' : 'DISABLED'}</span>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}

            {tab === 'server' && (
              <div className="glass-panel" style={{ padding: '1.5rem' }}>
                <div style={{ fontWeight: 700, marginBottom: '1.2rem', display: 'flex', alignItems: 'center', gap: 8 }}>
                  <Server size={16} color="var(--primary)" /> Application Information
                </div>
                {[
                  { label: 'Console URL',        value: serverUrl },
                  { label: 'Update Manifest API', value: manifestUrl },
                  { label: 'Client Installer',   value: installerUrl },
                ].map(({ label, value }) => (
                  <div key={label} style={{ marginBottom: '1rem' }}>
                    <label style={{ color: 'var(--text-muted)', fontSize: '0.78rem' }}>{label}</label>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, background: 'var(--bg-elevated)', borderRadius: 8, padding: '8px 12px', border: '1px solid var(--border)' }}>
                      <span style={{ fontFamily: 'var(--font-mono)', fontSize: '0.82rem', flex: 1, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{value}</span>
                      <button className="btn btn-ghost btn-icon" onClick={() => copyToClipboard(value)} title="Copy">
                        <Copy size={13} />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}

            {tab === 'deploy' && (
              <div className="glass-panel" style={{ padding: '1.5rem' }}>
                <div style={{ fontWeight: 700, marginBottom: '1.2rem', display: 'flex', alignItems: 'center', gap: 8 }}>
                  <Download size={16} color="var(--primary)" /> Client Deployment
                </div>
                <div className="alert alert-info" style={{ marginBottom: '1.5rem' }}>
                  <Download size={16} />
                  <div>
                    <strong>One Installer for All Windows Systems</strong><br />
                    <span style={{ fontSize: '0.82rem' }}>
                      The NeoOptimize installer includes the optimizer client and background service. Install on any Windows machine for automatic optimization scheduling.
                    </span>
                  </div>
                </div>
                {[
                  { title: 'NeoOptimize Client Setup (Windows)', desc: 'Full optimizer suite. Installs and registers to this console automatically.', href: installerUrl, badge: 'Recommended' },
                ].map(item => (
                  <div key={item.href} style={{ background: 'var(--bg-elevated)', borderRadius: 12, padding: '1.2rem', marginBottom: '1rem', border: '1px solid var(--border)' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
                      <div>
                        <div style={{ fontWeight: 600, marginBottom: 4 }}>{item.title}</div>
                        <div style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>{item.desc}</div>
                      </div>
                      <span className="badge badge-online">{item.badge}</span>
                    </div>
                    <a href={item.href} target="_blank" rel="noreferrer"
                      className="btn btn-primary btn-sm" style={{ textDecoration: 'none' }}>
                      <Download size={13} /> Download
                    </a>
                  </div>
                ))}
                <div style={{ marginTop: '1.5rem', background: 'var(--bg-elevated)', borderRadius: 10, padding: '1rem', border: '1px solid var(--border)' }}>
                  <div style={{ fontSize: '0.82rem', color: 'var(--text-muted)', marginBottom: 8, fontWeight: 600 }}>Silent Installation (Enterprise)</div>
                  <div style={{ fontFamily: 'var(--font-mono)', fontSize: '0.78rem', color: 'var(--success)' }}>
                    NeoOptimize.exe /S /SERVER={serverUrl}
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
