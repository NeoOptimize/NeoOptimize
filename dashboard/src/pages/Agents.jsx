import React, { useState, useEffect } from 'react';
import { TopBar } from '../App';
import { api } from '../lib/api';
import { toast } from 'react-hot-toast';
import {
  Monitor, Wifi, WifiOff, Search, RefreshCw, Trash2, Activity,
  Zap, Shield, Terminal, ChevronRight, Cpu, HardDrive, MapPin,
  Database, Settings, Power, Eye, Camera, Mic, Thermometer,
  Gauge, Globe2, Battery, Server,
  Package, Network, Box, Wrench, Save
} from 'lucide-react';

function parseMaybeJson(value, fallback = {}) {
  if (!value) return fallback;
  if (typeof value === 'object') return value;
  if (typeof value !== 'string') return fallback;
  try { return JSON.parse(value); } catch { return fallback; }
}

function nested(obj, path) {
  return path.split('.').reduce((acc, key) => (acc && acc[key] !== undefined ? acc[key] : undefined), obj);
}

function firstNumber(...values) {
  for (const value of values) {
    if (value === null || value === undefined || value === '') continue;
    const num = Number(value);
    if (Number.isFinite(num)) return num;
  }
  return null;
}

function firstText(...values) {
  for (const value of values) {
    if (value === null || value === undefined) continue;
    const text = String(value).trim();
    if (text) return text;
  }
  return null;
}

function firstBool(...values) {
  for (const value of values) {
    if (typeof value === 'boolean') return value;
    if (typeof value === 'string') {
      if (value.toLowerCase() === 'true') return true;
      if (value.toLowerCase() === 'false') return false;
    }
  }
  return null;
}

function normalizeTelemetry(raw = {}) {
  const metrics = parseMaybeJson(raw.metrics);
  const deviceInfo = parseMaybeJson(raw.device_info || raw.deviceInfo);
  const locationDetail = parseMaybeJson(raw.location_detail || raw.locationDetail);
  const securityState = parseMaybeJson(raw.security_state || raw.securityState);

  return {
    raw,
    metrics,
    deviceInfo,
    locationDetail,
    securityState,
    cpuPct: firstNumber(raw.cpu_pct, raw.c, nested(metrics, 'cpu.utilization_percent')),
    cpuKernelPct: firstNumber(raw.cpu_kernel_pct, nested(metrics, 'cpu.kernel_time_percent')),
    cpuClockMhz: firstNumber(raw.cpu_clock_mhz, nested(metrics, 'cpu.clock_mhz')),
    ramUsedMb: firstNumber(raw.ram_used_mb, raw.r, nested(metrics, 'memory.used_mb')),
    ramAvailableMb: firstNumber(raw.memory_available_mb, nested(metrics, 'memory.available_mb')),
    ramCommittedPct: firstNumber(raw.memory_committed_pct, nested(metrics, 'memory.committed_percent')),
    memoryCacheFaultsSec: firstNumber(raw.memory_cache_faults_sec, nested(metrics, 'memory.cache_faults_sec')),
    diskFreeGb: firstNumber(raw.disk_free_gb, raw.d, nested(metrics, 'disk.free_gb')),
    diskReadBytesSec: firstNumber(raw.disk_read_bytes_sec, nested(metrics, 'disk.read_bytes_sec')),
    diskWriteBytesSec: firstNumber(raw.disk_write_bytes_sec, nested(metrics, 'disk.write_bytes_sec')),
    diskRwBytesSec: firstNumber(raw.disk_rw_bytes_sec, nested(metrics, 'disk.read_write_bytes_sec')),
    diskQueueLength: firstNumber(raw.disk_queue_length, nested(metrics, 'disk.queue_length')),
    diskTimePct: firstNumber(raw.disk_time_pct, nested(metrics, 'disk.disk_time_percent')),
    diskLatencyMs: firstNumber(raw.disk_latency_ms, nested(metrics, 'disk.latency_ms')),
    netRxKbps: firstNumber(raw.net_rx_kbps, raw.rx, nested(metrics, 'network.rx_kbps')),
    netTxKbps: firstNumber(raw.net_tx_kbps, raw.tx, nested(metrics, 'network.tx_kbps')),
    networkBandwidthBps: firstNumber(raw.network_bandwidth_bps, nested(metrics, 'network.current_bandwidth_bps')),
    networkBytesTotalSec: firstNumber(raw.network_bytes_total_sec, nested(metrics, 'network.bytes_total_sec')),
    networkOutputQueueLength: firstNumber(raw.network_output_queue_length, nested(metrics, 'network.output_queue_length')),
    networkLatencyMs: firstNumber(raw.network_latency_ms, nested(metrics, 'network.latency_ms')),
    gpuPct: firstNumber(raw.gpu_pct, raw.g, nested(metrics, 'gpu.utilization_percent')),
    gpuTempC: firstNumber(raw.gpu_temp_c, raw.gt, nested(metrics, 'gpu.temperature_c')),
    gpuName: firstText(raw.gpu_name, raw.gn, nested(metrics, 'gpu.name')),
    cpuTempC: firstNumber(raw.cpu_temp_c, raw.ct, nested(metrics, 'thermal_power.cpu_temperature_c')),
    powerProfile: firstText(raw.power_profile, nested(metrics, 'thermal_power.power_profile')),
    onBattery: firstBool(raw.on_battery, nested(metrics, 'thermal_power.on_battery')),
    processCount: firstNumber(raw.process_count, nested(metrics, 'processes.process_count')),
    threadCount: firstNumber(raw.thread_count, nested(metrics, 'processes.thread_count')),
    handleCount: firstNumber(raw.handle_count, nested(metrics, 'processes.handle_count')),
    publicIp: firstText(raw.public_ip, raw.ip),
    geoCity: firstText(raw.geo_city, raw.location_label, raw.l),
    geoCountry: firstText(raw.geo_country),
    geoLat: firstNumber(raw.geo_lat, locationDetail.lat),
    geoLon: firstNumber(raw.geo_lon, locationDetail.lon),
    cameraAvailable: firstBool(raw.camera_available, nested(metrics, 'peripherals.camera_available')),
    microphoneAvailable: firstBool(raw.microphone_available, nested(metrics, 'peripherals.microphone_available')),
    biometricAvailable: firstBool(raw.biometric_available, nested(metrics, 'peripherals.biometric_available')),
    camActive: firstBool(raw.cam_active, nested(metrics, 'peripherals.cam_active')),
    micActive: firstBool(raw.mic_active, nested(metrics, 'peripherals.mic_active')),
    activeCommandId: firstText(raw.active_command_id),
    sampleKind: firstText(raw.sample_kind),
    ts: firstText(raw.ts, raw.timestamp)
  };
}

function formatPercent(value) {
  return value === null || value === undefined ? '--' : `${Number(value).toFixed(1)}%`;
}

function formatNumber(value, suffix = '') {
  return value === null || value === undefined ? '--' : `${Number(value).toLocaleString(undefined, { maximumFractionDigits: 1 })}${suffix}`;
}

function formatBytesPerSec(value) {
  if (value === null || value === undefined) return '--';
  const abs = Math.abs(value);
  if (abs >= 1024 * 1024) return `${(value / 1024 / 1024).toFixed(1)} MB/s`;
  if (abs >= 1024) return `${(value / 1024).toFixed(1)} KB/s`;
  return `${Math.round(value)} B/s`;
}

function MetricCard({ icon: Icon, label, value, detail, pct, color = 'var(--primary)' }) {
  const pctValue = pct === null || pct === undefined ? null : Math.max(0, Math.min(100, Number(pct) || 0));
  return (
    <div className="telemetry-card">
      <div className="telemetry-card-head">
        <span><Icon size={13} color={color} /> {label}</span>
        <strong style={{ color }}>{value}</strong>
      </div>
      {pctValue !== null && (
        <div className="progress-bg">
          <div className="progress-fill" style={{ width: `${pctValue}%`, background: pctValue > 85 ? 'var(--danger)' : color }} />
        </div>
      )}
      {detail && <div className="telemetry-card-detail">{detail}</div>}
    </div>
  );
}

function SystemModal({ agent, onClose, onCommand }) {
  const [tab, setTab] = useState('info');
  const [lastResult, setLastResult] = useState(null);
  const [liveTele, setLiveTele] = useState(agent.tele || null);
  const [telemetryHistory, setTelemetryHistory] = useState([]);
  const [telemetryError, setTelemetryError] = useState(null);
  const tele = normalizeTelemetry(liveTele || agent.tele || {});
  const ramTotalMb = firstNumber(agent.ram_mb, tele.deviceInfo.ram_mb, tele.deviceInfo.ram_total_mb) || 8192;
  const ramPct = tele.ramCommittedPct ?? (tele.ramUsedMb !== null ? (tele.ramUsedMb / ramTotalMb) * 100 : null);
  const locationLabel = firstText(
    tele.raw.location_label,
    tele.geoCity && tele.geoCountry ? `${tele.geoCity}, ${tele.geoCountry}` : tele.geoCity,
    agent.location_label
  );
  const networkIp = firstText(tele.publicIp, agent.public_ip, agent.ip_address);
  const telemetryLastSeen = tele.ts
    ? new Date(tele.ts).toLocaleTimeString()
    : agent.last_seen ? new Date(agent.last_seen).toLocaleTimeString() : '--';
  const cameraCaptureLabel = tele.cameraAvailable === null && tele.camActive
    ? 'legacy device signal'
    : tele.camActive ? 'active' : 'idle/disabled';
  const micCaptureLabel = tele.microphoneAvailable === null && tele.micActive
    ? 'legacy device signal'
    : tele.micActive ? 'active' : 'idle/disabled';

  useEffect(() => {
    setLiveTele(agent.tele || null);
    setTelemetryHistory([]);
    setTelemetryError(null);
  }, [agent.id, agent.tele]);

  useEffect(() => {
    if (tab !== 'telemetry') return undefined;
    let cancelled = false;

    async function loadTelemetry() {
      try {
        const res = await api.getAgentTelemetry(agent.id, { limit: 90, hours: 720 });
        if (cancelled) return;
        const history = res.telemetry || [];
        setTelemetryHistory(history);
        setLiveTele(history.length ? history[history.length - 1] : (agent.tele || null));
        setTelemetryError(null);
      } catch (e) {
        if (!cancelled) setTelemetryError(e.message);
      }
    }

    loadTelemetry();
    const timer = setInterval(loadTelemetry, 1000);
    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [tab, agent.id, agent.tele]);

  async function runCmd(id, type) {
    setLastResult({ loading: true, type });
    try {
      await onCommand(id, type);
      setLastResult({ done: true, type });
    } catch(e) {
      setLastResult({ error: e.message, type });
    }
  }

  return (
    <div className="modal-overlay" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className="modal system-modal">
        <div className="modal-header">
          <div>
            <div className="modal-title">{agent.hostname}</div>
            <span className={`badge badge-${agent.live_status || agent.status}`} style={{ marginTop: 4 }}>
              {agent.live_status || agent.status}
            </span>
          </div>
          <button className="btn btn-ghost btn-icon" onClick={onClose}>✕</button>
        </div>

        <div className="system-modal-tabs">
          <div className="tabs">
            {['info', 'optimize', 'telemetry'].map(t => (
              <button key={t} className={`tab ${tab === t ? 'active' : ''}`} onClick={() => setTab(t)}>
                {t === 'optimize' ? 'Optimizer' : t.charAt(0).toUpperCase() + t.slice(1)}
              </button>
            ))}
          </div>
        </div>

        <div className="modal-body system-modal-body">
          {tab === 'info' && (
            <div className="system-info-grid">
              {[
                { label: 'OS',         value: agent.os || 'Unknown' },
                { label: 'CPU',        value: agent.cpu || 'Unknown' },
                { label: 'RAM',        value: agent.ram_mb ? `${(agent.ram_mb/1024).toFixed(0)} GB` : 'Unknown' },
                { label: 'Host IP',    value: agent.ip_address || '—' },
                { label: 'Network IP', value: networkIp || '—' },
                { label: 'Location',   value: locationLabel || '—' },
                { label: 'Client Ver', value: `v${agent.version || '?'}` },
                { label: 'Machine ID', value: agent.bios_uuid?.slice(0, 18) + '...' || '—' },
                { label: 'Last Seen',  value: agent.last_seen ? new Date(agent.last_seen).toLocaleString() : '—' },
              ].map(({ label, value }) => (
                <div key={label} className="system-info-card">
                  <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginBottom: 4 }}>{label}</div>
                  <div style={{ fontSize: '0.85rem', fontWeight: 600 }}>{value}</div>
                </div>
              ))}
            </div>
          )}

          {tab === 'optimize' && (
            <div className="system-optimizer-layout">

              {/* ── Optimization & Maintenance ─── */}
              <div className="system-command-section system-command-section-wide">
                <div className="system-command-heading">Optimization & Maintenance</div>
                <div className="system-command-grid system-command-grid-wide">
                  {[
                    { type: 'OPTIMIZE',      label: 'Full Optimize',    icon: Zap,       desc: 'Run all performance modules' },
                    { type: 'CLEAN',         label: 'Disk Cleaner',     icon: HardDrive, desc: 'Clean temp, browser caches, dumps' },
                    { type: 'DEEP_SCAN',     label: 'Deep Junk Scan',   icon: Search,    desc: 'Find junk, caches, packages, residuals' },
                    { type: 'SYSTEM_DIAGNOSTICS', label: 'Diagnostics', icon: Activity,  desc: 'Boot, driver, event, WinRE anomalies' },
                    { type: 'SYSTEM_REPAIR', label: 'System Repair',    icon: Wrench,    desc: 'WinRE, DISM, SFC, update reset' },
                    { type: 'APP_MANAGER',   label: 'App Debloat',      icon: Box,       desc: 'Remove UWP bloat & OneDrive' },
                    { type: 'PRIVACY',       label: 'Privacy Harden',   icon: Eye,       desc: 'Block telemetry, spy domains' },
                    { type: 'POWER',         label: 'Power Manager',    icon: Power,     desc: 'Set Ultimate Performance plan' },
                    { type: 'SERVICES',      label: 'Trim Services',    icon: Settings,  desc: 'Disable unnecessary services' },
                    { type: 'UPDATES',       label: 'Windows Updates',  icon: Package,   desc: 'Silent critical update install' },
                    { type: 'BACKUP_OPS',    label: 'Auto Backup',      icon: Save,      desc: 'Backup Registry, WiFi, Drivers' },
                  ].map(cmd => (
                    <button key={cmd.type} className="btn btn-secondary"
                      style={{ flexDirection: 'column', alignItems: 'flex-start', padding: '9px 11px', height: 'auto', gap: 3 }}
                      disabled={(agent.live_status || agent.status) !== 'online'}
                      onClick={() => { runCmd(agent.id, cmd.type); }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                        <cmd.icon size={13} color="var(--primary)" />
                        <span style={{ fontWeight: 600, fontSize: '0.82rem' }}>{cmd.label}</span>
                      </div>
                      <span style={{ fontSize: '0.69rem', color: 'var(--text-muted)' }}>{cmd.desc}</span>
                    </button>
                  ))}
                </div>
              </div>

              {/* ── Security & Network ─── */}
              <div className="system-command-section">
                <div className="system-command-heading">Security & Network</div>
                <div className="system-command-grid">
                  {[
                    { type: 'SECURITY_SCAN', label: 'Security Scan',    icon: Shield,    desc: 'ASR, Defender, exploit mitigations' },
                    { type: 'NETWORK_TEST',  label: 'Network Optimize', icon: Network,   desc: 'DNS, TCP tuning, connectivity' },
                    { type: 'THREAT_SCAN',   label: 'Threat Scan',      icon: Activity,  desc: 'Detect DeepLoad & Fileless threats' },
                    { type: 'INTEGRITY_SCAN',label: 'Integrity Check',  icon: Search,    desc: 'SHA256 & Authenticode Audit' },
                  ].map(cmd => (
                    <button key={cmd.type} className="btn btn-secondary"
                      style={{ flexDirection: 'column', alignItems: 'flex-start', padding: '9px 11px', height: 'auto', gap: 3 }}
                      disabled={(agent.live_status || agent.status) !== 'online'}
                      onClick={() => { runCmd(agent.id, cmd.type); }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                        <cmd.icon size={13} color="var(--accent)" />
                        <span style={{ fontWeight: 600, fontSize: '0.82rem' }}>{cmd.label}</span>
                      </div>
                      <span style={{ fontSize: '0.69rem', color: 'var(--text-muted)' }}>{cmd.desc}</span>
                    </button>
                  ))}
                </div>
              </div>

              {/* ── Diagnostics ─── */}
              <div className="system-command-section">
                <div className="system-command-heading">Diagnostics</div>
                <div className="system-command-grid">
                  {[
                    { type: 'COLLECT',  label: 'Hardware Audit', icon: Database, desc: 'Full device inventory report' },
                    { type: 'SYSINFO', label: 'Quick Snapshot',  icon: Cpu,      desc: 'OS, CPU, RAM quick check' },
                  ].map(cmd => (
                    <button key={cmd.type} className="btn btn-secondary"
                      style={{ flexDirection: 'column', alignItems: 'flex-start', padding: '9px 11px', height: 'auto', gap: 3 }}
                      disabled={(agent.live_status || agent.status) !== 'online'}
                      onClick={() => { runCmd(agent.id, cmd.type); }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                        <cmd.icon size={13} color="var(--primary)" />
                        <span style={{ fontWeight: 600, fontSize: '0.82rem' }}>{cmd.label}</span>
                      </div>
                      <span style={{ fontSize: '0.69rem', color: 'var(--text-muted)' }}>{cmd.desc}</span>
                    </button>
                  ))}
                </div>
              </div>

              {/* Status Feedback */}
              {lastResult && (
                <div className="system-command-feedback" style={{
                  padding: '10px 14px', borderRadius: 8, fontSize: '0.8rem',
                  background: lastResult.loading ? 'var(--bg-elevated)' : lastResult.error ? 'rgba(255,59,59,0.1)' : 'rgba(0,240,255,0.08)',
                  border: `1px solid ${lastResult.error ? 'var(--danger)' : 'var(--border)'}`,
                  color: lastResult.error ? 'var(--danger)' : 'var(--text-muted)'
                }}>
                  {lastResult.loading && `⟳ Queuing ${lastResult.type}...`}
                  {lastResult.done  && `✓ ${lastResult.type} task queued — system will execute shortly`}
                  {lastResult.error && `✗ ${lastResult.error}`}
                </div>
              )}
            </div>
          )}

          {tab === 'telemetry' && (
            <div>
              {(liveTele || agent.tele || agent.public_ip || agent.location_label) ? (
                <>
                  <div className="telemetry-live-strip">
                    <span><Activity size={13} color="var(--success)" /> Real-time telemetry: 1s refresh</span>
                    <span>{telemetryHistory.length} samples · last update {telemetryLastSeen}</span>
                  </div>
                  {telemetryError && (
                    <div className="alert alert-warning" style={{ marginBottom: 10 }}>
                      <Activity size={14} /> <span>{telemetryError}</span>
                    </div>
                  )}

                  <div className="system-telemetry-grid">
                    <MetricCard
                      icon={Cpu}
                      label="CPU"
                      value={formatPercent(tele.cpuPct)}
                      pct={tele.cpuPct}
                      detail={`Kernel ${formatPercent(tele.cpuKernelPct)} · ${formatNumber(tele.cpuClockMhz, ' MHz')}`}
                    />
                    <MetricCard
                      icon={Gauge}
                      label="GPU"
                      value={formatPercent(tele.gpuPct)}
                      pct={tele.gpuPct}
                      color="var(--accent)"
                      detail={`${tele.gpuName || agent.gpu || 'GPU counter unavailable'} · ${formatNumber(tele.gpuTempC, ' C')}`}
                    />
                    <MetricCard
                      icon={Activity}
                      label="RAM"
                      value={tele.ramUsedMb !== null ? `${(tele.ramUsedMb / 1024).toFixed(1)} GB` : '--'}
                      pct={ramPct}
                      color="var(--warning)"
                      detail={`Available ${tele.ramAvailableMb !== null ? (tele.ramAvailableMb / 1024).toFixed(1) + ' GB' : '--'} · committed ${formatPercent(tele.ramCommittedPct)}`}
                    />
                    <MetricCard
                      icon={HardDrive}
                      label="Disk"
                      value={tele.diskFreeGb !== null ? `${tele.diskFreeGb.toFixed(1)} GB free` : '--'}
                      pct={tele.diskTimePct}
                      detail={`R ${formatBytesPerSec(tele.diskReadBytesSec)} · W ${formatBytesPerSec(tele.diskWriteBytesSec)} · Q ${formatNumber(tele.diskQueueLength)}`}
                    />
                    <MetricCard
                      icon={Network}
                      label="Network"
                      value={`RX ${formatNumber(tele.netRxKbps, ' KB/s')}`}
                      color="var(--success)"
                      detail={`TX ${formatNumber(tele.netTxKbps, ' KB/s')} · latency ${formatNumber(tele.networkLatencyMs, ' ms')}`}
                    />
                    <MetricCard
                      icon={Thermometer}
                      label="Thermal"
                      value={`CPU ${formatNumber(tele.cpuTempC, ' C')}`}
                      color="var(--danger)"
                      detail={`GPU ${formatNumber(tele.gpuTempC, ' C')} · power ${tele.powerProfile || '--'}${tele.onBattery === null ? '' : tele.onBattery ? ' · battery' : ' · AC'}`}
                    />
                    <MetricCard
                      icon={Server}
                      label="Processes"
                      value={formatNumber(tele.processCount)}
                      color="var(--primary)"
                      detail={`Threads ${formatNumber(tele.threadCount)} · handles ${formatNumber(tele.handleCount)}`}
                    />
                    <MetricCard
                      icon={Globe2}
                      label="IP / Location"
                      value={networkIp || '--'}
                      color="var(--primary)"
                      detail={`${locationLabel || 'Location not collected'}${tele.geoLat !== null && tele.geoLon !== null ? ` · ${tele.geoLat.toFixed(3)}, ${tele.geoLon.toFixed(3)}` : ''}`}
                    />
                  </div>

                  <div className="telemetry-detail-grid">
                    <div className="telemetry-detail-card">
                      <div className="telemetry-detail-title"><Monitor size={13} /> Device</div>
                      <div>OS runtime: {tele.deviceInfo.os_version || agent.os || '--'}</div>
                      <div>CPU threads: {tele.deviceInfo.processor_count || agent.cpu_threads || '--'}</div>
                      <div>Architecture: {tele.deviceInfo.is_64_bit_os === true ? '64-bit OS' : tele.deviceInfo.is_64_bit_os === false ? '32-bit OS' : '--'}</div>
                    </div>
                    <div className="telemetry-detail-card">
                      <div className="telemetry-detail-title"><Camera size={13} /> Camera / Mic</div>
                      <div>Camera: {tele.cameraAvailable === null ? 'unknown' : tele.cameraAvailable ? 'available' : 'not detected'} · capture {cameraCaptureLabel}</div>
                      <div>Microphone: {tele.microphoneAvailable === null ? 'unknown' : tele.microphoneAvailable ? 'available' : 'not detected'} · capture {micCaptureLabel}</div>
                      <div className="telemetry-note">Capture is never opened silently; public builds require explicit consent.</div>
                    </div>
                    <div className="telemetry-detail-card">
                      <div className="telemetry-detail-title"><Battery size={13} /> Power / Network Detail</div>
                      <div>Bandwidth: {formatBytesPerSec(tele.networkBandwidthBps)}</div>
                      <div>Total traffic: {formatBytesPerSec(tele.networkBytesTotalSec)}</div>
                      <div>Output queue: {formatNumber(tele.networkOutputQueueLength)}</div>
                    </div>
                    <div className="telemetry-detail-card">
                      <div className="telemetry-detail-title"><Shield size={13} /> Security State</div>
                      <div>UAC: {tele.securityState.uac_enabled === true ? 'enabled' : tele.securityState.uac_enabled === false ? 'disabled' : '--'}</div>
                      <div>Defender realtime: {tele.securityState.defender_realtime_enabled === true ? 'enabled' : tele.securityState.defender_realtime_enabled === false ? 'disabled' : '--'}</div>
                      <div>Active command: {tele.activeCommandId || 'none'}</div>
                    </div>
                  </div>
                </>
              ) : (
                <div className="empty-state"><Activity size={32} /><p>No telemetry data yet. System must be online and reporting.</p></div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export default function Systems() {
  const [agents, setAgents]       = useState([]);
  const [loading, setLoading]     = useState(true);
  const [search, setSearch]       = useState('');
  const [filter, setFilter]       = useState('all');
  const [selected, setSelected]   = useState(null);

  async function load() {
    try {
      setLoading(true);
      const res = await api.getAgents({ search, status: filter === 'all' ? undefined : filter });
      setAgents(res.agents || []);
    } catch (e) { toast.error('Failed to load systems'); }
    finally { setLoading(false); }
  }

  useEffect(() => { load(); }, [search, filter]);

  async function handleCommand(agentId, type) {
    try {
      await api.sendCommand(agentId, type);
      toast.success(`${type} task queued`);
    } catch (e) { toast.error(e.message); }
  }

  async function handleDelete(agent) {
    if (!confirm(`Remove "${agent.hostname}" from NeoOptimize? This cannot be undone.`)) return;
    try {
      await api.deleteAgent(agent.id);
      toast.success('System removed');
      load();
    } catch (e) { toast.error(e.message); }
  }

  async function handleBulkCommand(type) {
    if (!confirm(`Send "${type}" to ALL online systems?`)) return;
    const online = agents.filter(a => (a.live_status || a.status) === 'online');
    if (!online.length) return toast.error('No online systems');
    try {
      await api.sendBulkCommand(online.map(a => a.id), type);
      toast.success(`${type} sent to ${online.length} systems`);
    } catch (e) { toast.error(e.message); }
  }

  const online  = agents.filter(a => (a.live_status || a.status) === 'online').length;
  const offline = agents.length - online;

  return (
    <>
      <TopBar
        title="Systems"
        subtitle={`${online} online · ${offline} offline`}
        actions={
          <div style={{ display: 'flex', gap: 8 }}>
            <button className="btn btn-primary btn-sm" onClick={() => handleBulkCommand('OPTIMIZE')}>
              <Zap size={13} /> Optimize All
            </button>
            <button className="btn btn-secondary btn-sm" onClick={load}>
              <RefreshCw size={13} />
            </button>
          </div>
        }
      />
      <div className="page-content animate-fade-in">

        {/* Filters */}
        <div style={{ display: 'flex', gap: 12, marginBottom: '1.5rem', flexWrap: 'wrap' }}>
          <div className="topbar-search" style={{ width: 280 }}>
            <Search size={14} color="var(--text-muted)" />
            <input placeholder="Search hostname, IP..." value={search} onChange={e => setSearch(e.target.value)} />
          </div>
          <div className="tabs" style={{ width: 'auto' }}>
            {['all','online','offline'].map(f => (
              <button key={f} className={`tab ${filter === f ? 'active' : ''}`} onClick={() => setFilter(f)}>
                {f.charAt(0).toUpperCase() + f.slice(1)}
              </button>
            ))}
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
                    <th>Hostname</th>
                    <th>Status</th>
                    <th>OS</th>
                    <th>Location</th>
                    <th>IP</th>
                    <th>Last Seen</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {agents.map(agent => {
                    const status = agent.live_status || agent.status;
                    const isOnline = status === 'online';
                    return (
                      <tr key={agent.id}
                          style={{ cursor: 'pointer' }}
                          onClick={() => setSelected(agent)}>
                        <td>
                          <div style={{ fontWeight: 600 }}>{agent.hostname}</div>
                          <div style={{ fontSize: '0.72rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' }}>
                            {agent.bios_uuid?.slice(0, 12)}...
                          </div>
                        </td>
                        <td><span className={`badge badge-${status}`}>{status}</span></td>
                        <td style={{ fontSize: '0.83rem' }}>{agent.os || 'Unknown'}</td>
                        <td style={{ fontSize: '0.8rem', color: 'var(--primary)' }}>{agent.tele?.l || agent.location_label || '—'}</td>
                        <td style={{ fontFamily: 'var(--font-mono)', fontSize: '0.8rem' }}>{agent.tele?.ip || agent.public_ip || agent.ip_address || '—'}</td>
                        <td style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
                          {agent.last_seen ? new Date(agent.last_seen).toLocaleString() : 'Never'}
                        </td>
                        <td onClick={e => e.stopPropagation()}>
                          <div style={{ display: 'flex', gap: 6 }}>
                            <button className="btn btn-primary btn-sm"
                              disabled={!isOnline}
                              onClick={() => handleCommand(agent.id, 'OPTIMIZE')}>
                              <Zap size={12} />
                            </button>
                            <button className="btn btn-secondary btn-sm"
                              onClick={() => setSelected(agent)}>
                              <ChevronRight size={12} />
                            </button>
                            <button className="btn btn-danger btn-sm"
                              onClick={() => handleDelete(agent)}>
                              <Trash2 size={12} />
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                  {agents.length === 0 && !loading && (
                    <tr><td colSpan={7}>
                      <div className="empty-state">
                        <Monitor size={40} className="empty-state-icon" />
                        <h4>No systems found</h4>
                        <p>Try adjusting your search or install the NeoOptimize client</p>
                      </div>
                    </td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>

      {selected && (
        <SystemModal
          agent={selected}
          onClose={() => setSelected(null)}
          onCommand={handleCommand}
        />
      )}
    </>
  );
}
