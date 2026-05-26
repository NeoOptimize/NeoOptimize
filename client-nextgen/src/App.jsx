import { useEffect, useMemo, useState } from 'react'
import { invoke as tauriInvoke } from '@tauri-apps/api/core'
import {
  Activity,
  Bot,
  BrainCircuit,
  Cpu,
  Database,
  Gauge,
  HardDrive,
  MessageSquare,
  Mic,
  Network,
  RefreshCw,
  ShieldCheck,
  Sparkles,
  Trash2,
  X,
  Zap
} from 'lucide-react'

const invokeTauri = async (command, args) => {
  if (!window.__TAURI_INTERNALS__) {
    throw new Error('Tauri bridge unavailable')
  }
  return tauriInvoke(command, args)
}

const fallbackSnapshot = {
  cpu: 0,
  ram: 0,
  disk_free: 0,
  network_rx: 0,
  network_tx: 0,
  os: navigator.platform || 'Unknown',
  host: 'local',
  uptime: 'preview mode',
  rmm_connected: false
}

const navItems = [
  ['Overview', Activity],
  ['AI Doctor', BrainCircuit],
  ['Optimizer', Zap],
  ['Telemetry', Gauge],
  ['Reports', Database],
  ['Settings', ShieldCheck],
  ['About', ShieldCheck]
]

const modules = [
  ['System Cleanup', 'Cleaner', 'Caches, temp files, dumps', Trash2, 'maintenance'],
  ['Maintenance Plan', 'Maintenance', 'Scheduled care and hygiene', Sparkles, 'maintenance'],
  ['Power Audit', 'Power', 'Plan and battery posture', Zap, 'maintenance'],
  ['Power Plan Tuning', 'PowerPlanTuning', 'Balanced/high-performance review', Zap, 'maintenance'],
  ['Startup Optimizer', 'StartupOptimizer', 'Startup load and boot impact', Gauge, 'performance'],
  ['Performance Tuning', 'Performance', 'Process, memory, and responsiveness', Gauge, 'performance'],
  ['Smart Booster', 'SmartBooster', 'Short safe performance boost', Zap, 'performance'],
  ['Smart Optimize', 'SmartOptimize', 'Profile-aware optimization', Sparkles, 'performance'],
  ['Before/After Benchmark', 'BenchmarkReport', 'Evidence report and delta', Gauge, 'telemetry'],
  ['Device Snapshot', 'DeviceSnapshot', 'Hardware and driver inventory', Cpu, 'telemetry'],
  ['Deep Scan', 'DeepScan', 'Junk, logs, residuals', Sparkles, 'diagnostics'],
  ['System Diagnostics', 'SystemDiagnostics', 'Services, events, hardware', BrainCircuit, 'diagnostics'],
  ['Windows Doctor', 'WindowsDoctor', 'Windows error diagnosis', BrainCircuit, 'diagnostics'],
  ['Security Audit', 'SecurityAudit', 'Defender, firewall, UAC posture', ShieldCheck, 'security'],
  ['Zero-Trust Hardening', 'ZeroTrustSecurity', 'VBS, HVCI, ASR review', ShieldCheck, 'security'],
  ['Threat Monitor', 'ThreatMonitor', 'Persistence and suspicious state', ShieldCheck, 'security'],
  ['Integrity Check', 'IntegrityScan', 'AuthentiCode and SHA scan', ShieldCheck, 'security'],
  ['Privacy Review', 'PrivacyReview', 'Camera, mic, location stay user-controlled', ShieldCheck, 'privacy'],
  ['Privacy Baseline', 'Privacy', 'Telemetry and app permissions audit', ShieldCheck, 'privacy'],
  ['Debloat Apps', 'Apps', 'Optional Windows app removal menu', Trash2, 'apps'],
  ['Feature Optimizer', 'FeatureOptimizer', 'Optional Windows features audit', Database, 'apps'],
  ['Component Cleanup', 'ComponentCleanup', 'WinSxS and component store', Trash2, 'storage'],
  ['Storage Tiering', 'StorageTiering', 'NVMe and DirectStorage checks', HardDrive, 'storage'],
  ['Disk Status', 'DiskStatus', 'SMART and volume overview', HardDrive, 'storage'],
  ['Network Diagnose', 'Network', 'DNS, adapter, latency checks', Network, 'network'],
  ['Network Diagnostics', 'NetworkDiagnostics', 'Routes, DNS, gateway, latency', Network, 'network'],
  ['Network Repair Toolkit', 'NetworkRepair', 'Safe repair plan and reset gates', Network, 'network'],
  ['Remote Access Check', 'RemoteReadiness', 'WinRM, SSH, QGA readiness only', Network, 'network'],
  ['Windows Repair', 'SystemRepair', 'DISM, SFC, WinRE checks', ShieldCheck, 'repair'],
  ['Update Repair', 'UpdateRepair', 'Windows Update component repair', RefreshCw, 'repair'],
  ['Restore Point', 'RestorePoint', 'Create rollback checkpoint', ShieldCheck, 'repair'],
  ['Update Manager', 'NeoUpdate', 'SHA-256 update integrity', RefreshCw, 'update'],
  ['Windows Updates', 'Updates', 'Windows update audit and repair gate', RefreshCw, 'update'],
  ['Container / Hyper-V', 'ContainerHyperVTuning', 'WSL2, Docker, Hyper-V review', Database, 'virtualization'],
  ['Game Mode Ultra', 'GameModeUltra', 'Gaming latency posture audit', Zap, 'gaming'],
  ['AI / NPU Caching', 'AINPUCaching', 'Local AI cache and compute limits', BrainCircuit, 'ai'],
  ['AI Doctor Check', 'AIPlan', 'Health score and treatment plan', BrainCircuit, 'ai'],
  ['Agentic Plan', 'NEOAgentic', 'Observe, plan, approve', Bot, 'ai'],
  ['Script Forge', 'AIScriptForge', 'PowerShell/CMD draft only', MessageSquare, 'ai'],
  ['Capability Catalog', 'AICatalog', 'Risk, rollback, verification metadata', Database, 'ai'],
  ['AI Providers', 'AIProviders', 'Local/cloud provider status', Bot, 'ai'],
  ['Local AI Setup', 'LocalAISetup', 'Install Ollama and NullClaw bridge', Bot, 'ai']
]

const moduleCategoryLabels = {
  maintenance: 'Maintenance',
  performance: 'Performance',
  diagnostics: 'Diagnostics',
  repair: 'Repair',
  security: 'Security',
  privacy: 'Privacy',
  apps: 'Apps',
  storage: 'Storage',
  network: 'Network',
  update: 'Updates',
  virtualization: 'Virtualization',
  gaming: 'Gaming',
  telemetry: 'Telemetry',
  ai: 'NEO AI'
}

const moduleCategories = [
  ['maintenance', 'Maintenance', 'Cleanup, power, scheduled care'],
  ['performance', 'Performance', 'Startup, memory, profile tuning'],
  ['diagnostics', 'Diagnostics', 'Inventory, benchmark, integrity checks'],
  ['repair', 'Repair', 'System repair and recovery workflows'],
  ['security', 'Security', 'Privacy, threat, and integrity review'],
  ['privacy', 'Privacy', 'Review camera, mic, location without org locks'],
  ['apps', 'Apps', 'Debloatware and optional feature choices'],
  ['storage', 'Storage', 'NVMe, component store, disk status'],
  ['network', 'Network', 'DNS, adapter, and latency checks'],
  ['update', 'Updates', 'Verified update manager'],
  ['virtualization', 'Virtualization', 'Containerization, WSL2, Hyper-V'],
  ['gaming', 'Gaming', 'Game mode and latency posture'],
  ['telemetry', 'Telemetry', 'Snapshots and benchmark reporting'],
  ['ai', 'NEO AI', 'Agentic planning and local model setup']
]

const CHAT_TTL_MS = 30 * 60 * 1000
const CHAT_STORAGE_KEY = 'neooptimize.neoMini.chat.v1'
const MINI_MODE = new URLSearchParams(window.location.search).get('view') === 'mini'

function nowId() {
  if (window.crypto?.randomUUID) return window.crypto.randomUUID()
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`
}

function pruneChat(items) {
  const cutoff = Date.now() - CHAT_TTL_MS
  return items
    .filter((item) => item && Number.isFinite(item.ts) && item.ts >= cutoff)
    .slice(-80)
}

function initialChatLog() {
  try {
    const stored = JSON.parse(window.localStorage.getItem(CHAT_STORAGE_KEY) || '[]')
    const restored = pruneChat(stored)
    if (restored.length) return restored
  } catch {
    window.localStorage.removeItem(CHAT_STORAGE_KEY)
  }
  return [
    {
      id: nowId(),
      role: 'neo',
      mode: 'system',
      text: 'Saya adalah NEO (Neural Execution Operator), artificial intelligence yang dibangun di zenthralix-lab oleh nol_eight.',
      ts: Date.now()
    }
  ]
}

function chatLabel(item) {
  if (item.role === 'neo') return 'NEO'
  return item.mode === 'voice' ? 'Voice' : 'You'
}

function formatChatTime(ts) {
  return new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

function formatBytesPerSecond(value) {
  if (!Number.isFinite(value) || value <= 0) return '0 B/s'
  if (value > 1024 * 1024) return `${(value / 1024 / 1024).toFixed(1)} MB/s`
  if (value > 1024) return `${(value / 1024).toFixed(1)} KB/s`
  return `${Math.round(value)} B/s`
}

function snapshotAnomalies(snapshot) {
  const findings = []
  if (Number(snapshot.cpu) >= 85) findings.push(`High CPU pressure (${snapshot.cpu}%).`)
  else if (Number(snapshot.cpu) >= 70) findings.push(`Elevated CPU load (${snapshot.cpu}%).`)
  if (Number(snapshot.ram) >= 85) findings.push(`High memory pressure (${snapshot.ram}%).`)
  else if (Number(snapshot.ram) >= 75) findings.push(`Elevated memory use (${snapshot.ram}%).`)
  if (Number(snapshot.disk_free) > 0 && Number(snapshot.disk_free) <= 12) findings.push(`Low system disk free space (${snapshot.disk_free}%).`)
  if (!snapshot.rmm_connected) findings.push('RMM endpoint is not connected; local mode is active.')
  if (!findings.length) findings.push('No urgent CPU/RAM/disk anomaly is visible in the current realtime sample.')
  return findings
}

function corpusHint() {
  return 'NEO uses the packaged Windows admin corpus for AI Doctor, Script Forge, anomaly triage, and repair suggestions when the native provider is available.'
}

function localNeoAnswer(text, snapshot) {
  const lower = String(text || '').toLowerCase()
  const normalized = lower.replace(/[!?.,]/g, '').trim()
  if (['hi', 'hello', 'halo', 'hai', 'help', 'bantuan'].includes(normalized)) {
    return [
      'Provider: NEO instant local chat.',
      'Saya aktif. Anda bisa minta status sistem, scan anomaly, saran code perbaikan, daftar modul, voice command, atau Local AI Setup.',
      `Runtime: ${snapshot.host} · CPU ${snapshot.cpu}% · RAM ${snapshot.ram}% · Disk free ${snapshot.disk_free}%`,
      'Best next action: ketik "scan anomaly", "saran code fix", atau buka Optimizer untuk memilih modul maintenance.'
    ].join('\n')
  }
  if (lower === 'status' || lower.includes('health') || lower.includes('kondisi')) {
    return [
      'Provider: NEO instant local status.',
      `Host: ${snapshot.host}`,
      `OS: ${snapshot.os}`,
      `CPU: ${snapshot.cpu}% · RAM: ${snapshot.ram}% · Disk free: ${snapshot.disk_free}%`,
      `RMM: ${snapshot.rmm_connected ? 'Connected' : 'Local mode'}`,
      `Anomaly: ${snapshotAnomalies(snapshot).join(' ')}`,
      'Best next action: run AI Doctor Check for a ranked treatment plan.'
    ].join('\n')
  }
  if (lower.includes('anomali') || lower.includes('anomaly') || lower.includes('scan') || lower.includes('detect')) {
    return [
      'Provider: NEO realtime anomaly triage.',
      ...snapshotAnomalies(snapshot).map((item) => `- ${item}`),
      'Recommended workflow: Device Snapshot -> Benchmark Report -> AI Doctor Check -> Windows Doctor if repair is needed.',
      'Notification path: NEO Mini status, local reports, and RMM telemetry when the endpoint is enrolled.',
      corpusHint()
    ].join('\n')
  }
  if (lower.includes('code') || lower.includes('script') || lower.includes('fix') || lower.includes('perbaikan') || lower.includes('bug') || lower.includes('powershell')) {
    return [
      'Provider: NEO code repair guide.',
      'Saya bisa memberi saran code perbaikan dan draft PowerShell/CMD melalui Script Forge. Default-nya read-only, dengan rollback note, timeout, SHA-256/report metadata, dan human approval sebelum apply.',
      'Best next action: klik Script Forge atau tulis detail error. Untuk safe system repair, gunakan Windows Doctor atau Update Repair terlebih dahulu.',
      corpusHint()
    ].join('\n')
  }
  if (lower.includes('module') || lower.includes('modul') || lower.includes('fitur')) {
    return [
      'Provider: NEO local module catalog.',
      `Available modules: ${modules.length} buttons across ${moduleCategories.length} categories.`,
      'Core areas: cleanup, performance, privacy, network, storage, repair, update, security, virtualization, gaming, telemetry, and AI.',
      'Best next action: open Optimizer, choose a category, then run one module at a time.'
    ].join('\n')
  }
  if (lower.includes('ollama') || lower.includes('model') || lower.includes('local ai') || lower.includes('neo-light') || lower.includes('neo-latest')) {
    return [
      'Provider: NEO Local AI setup guide.',
      'Installer and Local AI Setup run Ollama bootstrap in the background with no CMD popup. Required models: neo-light:latest, neo:latest, and neo-latest:latest.',
      'If the model is still downloading, NEO keeps answering through NeoCore/rule fallback.',
      'Best next action: run Local AI Setup, then ask "status" again.'
    ].join('\n')
  }
  if (lower.includes('notifikasi') || lower.includes('notification') || lower.includes('alert')) {
    return [
      'Provider: NEO notification guide.',
      'Local notifications: NEO Mini status line, tray balloon, worker log, and reports. Fleet notifications: RMM telemetry and alert routes after endpoint enrollment.',
      'Best next action: run Security Audit or Windows Doctor to generate anomaly/alert evidence.'
    ].join('\n')
  }
  if (lower.includes('voice') || lower.includes('mic') || lower.includes('suara')) {
    return [
      'Provider: NEO voice guide.',
      'Voice command uses Windows speech recognition when available and falls back to typed chat.',
      'Camera, microphone, and location are not locked by organization policy from NeoOptimize privacy review modules.',
      'Best next action: click the microphone button and say "neo optimize doctor" or type the same command.'
    ].join('\n')
  }
  return ''
}

export default function App() {
  const [snapshot, setSnapshot] = useState(fallbackSnapshot)
  const [history, setHistory] = useState([])
  const [status, setStatus] = useState('AI-empowered UI ready. PowerShell engine stays idle until an approved task is started.')
  const [activeNav, setActiveNav] = useState('Overview')
  const [busyAction, setBusyAction] = useState('')
  const [chatLog, setChatLog] = useState(initialChatLog)
  const [question, setQuestion] = useState('')
  const [voiceListening, setVoiceListening] = useState(false)
  const [activeModuleCategory, setActiveModuleCategory] = useState('maintenance')

  const health = useMemo(() => {
    const cpuPenalty = Math.max(0, snapshot.cpu - 55) * 0.32
    const ramPenalty = Math.max(0, snapshot.ram - 65) * 0.35
    const diskPenalty = snapshot.disk_free > 0 && snapshot.disk_free < 20 ? (20 - snapshot.disk_free) * 0.8 : 0
    return Math.max(42, Math.round(94 - cpuPenalty - ramPenalty - diskPenalty))
  }, [snapshot])

  const telemetryPath = useMemo(() => {
    if (!history.length) return ''
    const width = 300
    const height = 128
    const points = history.map((item, index) => {
      const x = history.length === 1 ? 0 : (index / (history.length - 1)) * width
      const y = height - (Math.max(0, Math.min(100, item.cpu)) / 100) * height
      return `${x.toFixed(1)},${y.toFixed(1)}`
    })
    return points.join(' ')
  }, [history])

  const isLinux = snapshot.os.toLowerCase().includes('linux')
  const platformName = isLinux ? 'Linux' : 'Windows'

  useEffect(() => {
    let cancelled = false

    async function refresh() {
      try {
        const next = await invokeTauri('get_system_snapshot')
        if (cancelled) return
        setSnapshot(next)
        setHistory((items) => [...items.slice(-35), next])
      } catch {
        if (cancelled) return
        setSnapshot((current) => ({ ...current, uptime: 'browser preview' }))
      }
    }

    refresh()
    const timer = window.setInterval(refresh, 1000)
    return () => {
      cancelled = true
      window.clearInterval(timer)
    }
  }, [])

  useEffect(() => {
    const clean = () => setChatLog((items) => pruneChat(items))
    clean()
    const timer = window.setInterval(clean, 60 * 1000)
    return () => window.clearInterval(timer)
  }, [])

  useEffect(() => {
    window.localStorage.setItem(CHAT_STORAGE_KEY, JSON.stringify(pruneChat(chatLog)))
  }, [chatLog])

  async function runAction(action) {
    if (busyAction) {
      setStatus(`Task ${busyAction} is still running. Wait for it to finish.`)
      return
    }
    setBusyAction(action)
    setStatus(`Starting ${action} through Rust supervisor...`)
    try {
      const result = await invokeTauri('run_action', { action })
      setStatus(result.message || `${action} started.`)
    } catch (error) {
      setStatus(`Cannot run ${action}: ${error.message || error}`)
    } finally {
      window.setTimeout(() => setBusyAction(''), 1200)
    }
  }

  async function askNeo(inputText = question, mode = 'text') {
    const text = String(inputText || '').trim()
    if (!text) return
    if (mode === 'text') setQuestion('')
    const pendingId = nowId()
    const timestamp = Date.now()
    setChatLog((items) => pruneChat([
      ...items,
      { id: nowId(), role: 'user', mode, text, ts: timestamp },
      { id: pendingId, role: 'neo', mode: 'system', text: 'thinking...', pending: true, ts: timestamp }
    ]))
    const identityQuestion = ['siapa anda', 'who are you'].includes(text.toLowerCase())
    if (identityQuestion) {
      setChatLog((items) => pruneChat(items.map((item) => item.id === pendingId
        ? {
            ...item,
            text: 'Saya adalah NEO (Neural Execution Operator), artificial intelligence yang dibangun di zenthralix-lab oleh nol_eight.',
            pending: false,
            ts: Date.now()
          }
        : item
      )))
      setStatus('NEO identity response complete.')
      return
    }
    const instant = localNeoAnswer(text, snapshot)
    if (instant) {
      setChatLog((items) => pruneChat(items.map((item) => item.id === pendingId
        ? { ...item, text: instant, pending: false, ts: Date.now() }
        : item
      )))
      setStatus('NEO local response complete.')
      return
    }
    try {
      const result = await invokeTauri('ask_neo', { question: text })
      const answer = String(result.answer || '').trim()
      const fallback = looksLikeProviderFailure(answer)
        ? [
            'Provider: NEO local fallback.',
            `Provider note: ${answer}`,
            'Best next action: run Local AI Setup, then ask again from NEO Mini.',
            'NEO typed chat remains available through packaged local rules, realtime telemetry, and corpus-aware AI Doctor/Script Forge when the provider is available.'
          ].join('\n')
        : answer
      setChatLog((items) => pruneChat(items.map((item) => item.id === pendingId
        ? { ...item, text: fallback || 'NEO tidak menerima output dari provider. Coba "status" atau "fitur".', pending: false, ts: Date.now() }
        : item
      )))
      setStatus('NEO response complete.')
    } catch (error) {
      const message = error?.message || String(error)
      setChatLog((items) => pruneChat(items.map((item) => item.id === pendingId
        ? {
            ...item,
            text: [
              'Provider: NEO local fallback.',
              `Provider note: ${message}`,
              'Best next action: run Local AI Setup, then ask again from NEO Mini.',
              'If Ollama is unavailable, NEO still uses packaged safe rules, telemetry guidance, anomaly triage, and corpus-aware AI Doctor/Script Forge.'
            ].join('\n'),
            pending: false,
            ts: Date.now()
          }
        : item
      )))
      setStatus(`NEO fallback active. ${message}`)
  }
}

function looksLikeProviderFailure(answer) {
  const lower = String(answer || '').toLowerCase()
  return lower.includes('cannot be loaded') ||
    lower.includes('is not digitally signed') ||
    lower.includes('running scripts is disabled') ||
    lower.includes('pssecurityexception') ||
    lower.includes('unauthorizedaccess')
}

  async function startVoiceCommand() {
    setVoiceListening(true)
    setStatus('NEO voice command listening...')
    try {
      const native = await invokeTauri('open_voice_command')
      if (native?.transcript) {
        await askNeo(native.transcript, 'voice')
      } else {
        setChatLog((items) => pruneChat([
          ...items,
          {
            id: nowId(),
            role: 'neo',
            mode: 'system',
            text: native?.message || 'Voice command finished without transcript. Type your command in NEO Mini.',
            ts: Date.now()
          }
        ]))
        setStatus(native?.message || 'Voice command finished.')
      }
      return
    } catch (nativeError) {
      setStatus(`Native voice bridge unavailable: ${nativeError?.message || nativeError}`)
    } finally {
      setVoiceListening(false)
    }

    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!SpeechRecognition) {
      let nativeMessage = 'Voice recognition is not available in this WebView runtime. Use text command in NEO Mini.'
      setChatLog((items) => pruneChat([
        ...items,
        {
          id: nowId(),
          role: 'neo',
          mode: 'system',
          text: nativeMessage,
          ts: Date.now()
        }
      ]))
      setStatus(nativeMessage)
      return
    }
    const recognition = new SpeechRecognition()
    recognition.lang = 'id-ID'
    recognition.interimResults = false
    recognition.maxAlternatives = 1
    recognition.onstart = () => {
      setVoiceListening(true)
      setStatus('NEO Mini voice listening...')
    }
    recognition.onerror = (event) => {
      setVoiceListening(false)
      setStatus(`Voice command failed: ${event.error || 'unknown error'}`)
    }
    recognition.onend = () => setVoiceListening(false)
    recognition.onresult = (event) => {
      const transcript = event.results?.[0]?.[0]?.transcript || ''
      if (transcript.trim()) askNeo(transcript, 'voice')
    }
    recognition.start()
  }

  async function showMiniTray() {
    try {
      const result = await invokeTauri('show_neo_mini')
      setStatus(result.message || 'NEO Mini opened.')
    } catch (error) {
      setStatus(`Cannot open NEO Mini: ${error.message || error}`)
    }
  }

  async function hideMiniTray() {
    try {
      await invokeTauri('hide_neo_mini')
    } catch {
      // Browser preview has no native Tauri window bridge.
    }
  }

  async function showMainWindow() {
    try {
      await invokeTauri('show_main_window')
    } catch {
      // Browser preview has no native Tauri window bridge.
    }
  }

  async function exitApp() {
    try {
      await invokeTauri('exit_app')
    } catch {
      window.close()
    }
  }

  async function openExternal(url) {
    try {
      const result = await invokeTauri('open_external_url', { url })
      setStatus(result.message || 'Opened support link.')
    } catch (error) {
      setStatus(`Cannot open support link: ${error.message || error}`)
    }
  }

  const guidance = {
    Overview: 'Realtime local posture with safe, user-approved maintenance actions.',
    'AI Doctor': `NEO reads local telemetry, packaged corpus, and approved ${platformName} care rules before suggesting treatment.`,
    Optimizer: 'Each module is allowlisted and dispatched through the Rust supervisor. Buttons throttle while a task is queued.',
    Telemetry: `Host ${snapshot.host} · uptime ${snapshot.uptime} · network RX ${formatBytesPerSecond(snapshot.network_rx)} · TX ${formatBytesPerSecond(snapshot.network_tx)}`,
    Reports: 'Benchmark, diagnostics, and maintenance reports are generated by the local engine and can be mirrored to RMM when enabled.',
    Settings: 'Default mode is local safety mode. Remote/RMM operations require explicit enrollment and signed commands.',
    About: 'Made with love at Zenthralix-Lab with Codex. Support helps keep community builds, local AI work, update integrity, and public maintenance tooling available.'
  }

  const renderModuleButton = ([title, action, note, Icon]) => {
    const displayTitle = title === 'Windows Doctor' ? `${platformName} Doctor` : title
    const displayNote = note.replace('Windows error diagnosis', `${platformName} error diagnosis`)
    return (
      <button
        key={action}
        className="module"
        disabled={Boolean(busyAction)}
        onClick={() => runAction(action)}
      >
        <div className="module-title"><Icon size={14} /> {displayTitle}</div>
        <div className="module-note">{displayNote}</div>
      </button>
    )
  }

  const categorizedModules = modules.filter((item) => item[4] === activeModuleCategory)
  if (MINI_MODE) {
    return (
      <MiniTray
        chatLog={chatLog}
        question={question}
        setQuestion={setQuestion}
        voiceListening={voiceListening}
        askNeo={askNeo}
        startVoiceCommand={startVoiceCommand}
        clearChat={() => setChatLog([])}
        hideMiniTray={hideMiniTray}
        showMainWindow={showMainWindow}
        exitApp={exitApp}
      />
    )
  }

  return (
    <div className="app">
      <aside className="sidebar">
        <div>
          <div className="brand">
            <div className="brand-mark"><ShieldCheck size={28} /></div>
            <div>
              <div className="brand-title">NeoOptimize</div>
              <div className="brand-subtitle">{platformName} Optimizer</div>
            </div>
          </div>
          <nav className="nav">
            {navItems.map(([label, Icon]) => (
              <button
                key={label}
                className={`nav-button ${activeNav === label ? 'active' : ''}`}
                onClick={() => {
                  setActiveNav(label)
                  setStatus(`${label} view selected.`)
                }}
              >
                <Icon size={17} />
                <span>{label}</span>
              </button>
            ))}
          </nav>
        </div>
        <div className="safety">
          <strong>Local safety mode</strong>
          <div className="muted">User-approved actions only.</div>
        </div>
      </aside>

      <main className="workspace">
        <header className="topbar">
          <div>
            <h1 className="title">NeoOptimize</h1>
            <div className="subtitle">AI-empowered local monitoring, diagnosis, repair guidance, and {platformName} maintenance.</div>
          </div>
          <div className="badges">
            <span className="badge good">AI READY</span>
            <span className="badge">{snapshot.rmm_connected ? 'LIVE' : 'LOCAL'}</span>
          </div>
        </header>

        <section className="page-shell">
          {activeNav === 'Overview' && (
            <div className="page-stack overview-page">
              <div className="metrics">
                <Metric label="CPU" value={`${snapshot.cpu}%`} note={snapshot.os} icon={Cpu} />
                <Metric label="RAM" value={`${snapshot.ram}%`} note="physical memory used" icon={Activity} />
                <Metric label="DISK" value={`${snapshot.disk_free}%`} note="system volume free" icon={HardDrive} />
                <Metric label="NET RX" value={formatBytesPerSecond(snapshot.network_rx)} note="receive rate" icon={Network} />
                <Metric label="NET TX" value={formatBytesPerSecond(snapshot.network_tx)} note="transmit rate" icon={Network} />
              </div>
              <div className="overview-grid">
                <HealthPanel health={health} runAction={runAction} />
                <div className="panel overview-summary">
                  <div className="section-title">System Posture</div>
                  <h2>Local safety mode</h2>
                  <p>{guidance.Overview}</p>
                  <div className="overview-actions">
                    <button className="link-button" disabled={Boolean(busyAction)} onClick={() => setActiveNav('Optimizer')}>Open modules</button>
                    <button className="link-button" disabled={Boolean(busyAction)} onClick={() => setActiveNav('Telemetry')}>View telemetry</button>
                    <button className="link-button" disabled={Boolean(busyAction)} onClick={showMiniTray}>Open NEO Mini</button>
                  </div>
                </div>
                <div className="panel device-panel">
                  <div className="section-title">Device</div>
                  <InfoRow label="Host" value={snapshot.host} />
                  <InfoRow label="OS" value={snapshot.os} />
                  <InfoRow label="Uptime" value={snapshot.uptime} />
                  <InfoRow label="RMM" value={snapshot.rmm_connected ? 'Connected' : 'Local mode'} />
                </div>
              </div>
            </div>
          )}

          {activeNav === 'AI Doctor' && (
            <div className="two-column-page">
              <DoctorPanel platformName={platformName} />
              <div className="panel action-panel">
                <div className="section-title">NEO Actions</div>
                <div className="action-list">
                  {[
                    ['AI Doctor Check', 'AIPlan', 'Generate health score and ranked treatment plan.'],
                    ['Agentic Plan', 'NEOAgentic', 'Observe, plan, and wait for approval before action.'],
                    ['Script Forge', 'AIScriptForge', 'Draft safe PowerShell/CMD commands without applying them.'],
                    ['Local AI Setup', 'LocalAISetup', 'Prepare local model provider and NullClaw bridge.']
                  ].map(([title, action, note]) => (
                    <button key={action} className="action-row" disabled={Boolean(busyAction)} onClick={() => runAction(action)}>
                      <strong>{title}</strong>
                      <span>{note}</span>
                    </button>
                  ))}
                </div>
              </div>
            </div>
          )}

          {activeNav === 'Optimizer' && (
            <div className="page-stack">
              <div className="category-strip" aria-label="Optimizer categories">
                {moduleCategories.map(([key, label, note]) => (
                  <button
                    key={key}
                    className={`category-button ${activeModuleCategory === key ? 'active' : ''}`}
                    onClick={() => setActiveModuleCategory(key)}
                  >
                    <strong>{label}</strong>
                    <span>{note}</span>
                  </button>
                ))}
              </div>
              <div className="module-panel paged">
                <div className="section-title">{moduleCategoryLabels[activeModuleCategory]} Modules</div>
                <div className="modules paged">{categorizedModules.map(renderModuleButton)}</div>
              </div>
            </div>
          )}

          {activeNav === 'Telemetry' && (
            <div className="page-stack">
              <div className="metrics">
                <Metric label="CPU" value={`${snapshot.cpu}%`} note="1 second sample" icon={Cpu} />
                <Metric label="RAM" value={`${snapshot.ram}%`} note="physical memory used" icon={Activity} />
                <Metric label="DISK" value={`${snapshot.disk_free}%`} note="system volume free" icon={HardDrive} />
                <Metric label="NET RX" value={formatBytesPerSecond(snapshot.network_rx)} note="receive rate" icon={Network} />
                <Metric label="NET TX" value={formatBytesPerSecond(snapshot.network_tx)} note="transmit rate" icon={Network} />
              </div>
              <div className="two-column-page telemetry-page">
                <TelemetryPanel telemetryPath={telemetryPath} wide />
                <div className="panel device-panel">
                  <div className="section-title">Device</div>
                  <InfoRow label="Host" value={snapshot.host} />
                  <InfoRow label="OS" value={snapshot.os} />
                  <InfoRow label="Uptime" value={snapshot.uptime} />
                  <InfoRow label="RMM" value={snapshot.rmm_connected ? 'Connected' : 'Local mode'} />
                </div>
              </div>
            </div>
          )}

          {activeNav === 'Reports' && (
            <div className="module-panel paged">
              <div className="section-title">Reports</div>
              <div className="modules paged">
                {modules.filter((item) => ['Collect', 'DeepScan', 'IntegrityScan', 'WindowsDoctor'].includes(item[1])).map(renderModuleButton)}
              </div>
            </div>
          )}

          {activeNav === 'Settings' && (
            <div className="two-column-page">
              <div className="panel action-panel">
                <div className="section-title">Safety</div>
                <InfoRow label="Execution" value="User-approved local actions only" />
                <InfoRow label="Remote" value="Signed RMM commands required after enrollment" />
                <InfoRow label="AI" value="Local-first provider with cloud providers optional" />
              </div>
              <div className="panel action-panel">
                <div className="section-title">Maintenance</div>
                <div className="action-list">
                  {[
                    ['Update Manager', 'NeoUpdate', 'Verify installer SHA-256 and update channel.'],
                    ['Integrity Check', 'IntegrityScan', 'Scan local files and AuthentiCode state.'],
                    ['Local AI Setup', 'LocalAISetup', 'Install or repair local AI provider.']
                  ].map(([title, action, note]) => (
                    <button key={action} className="action-row" disabled={Boolean(busyAction)} onClick={() => runAction(action)}>
                      <strong>{title}</strong>
                      <span>{note}</span>
                    </button>
                  ))}
                </div>
              </div>
            </div>
          )}

          {activeNav === 'About' && (
            <div className="panel about-panel">
              <div className="section-title">About NeoOptimize</div>
              <h2>NeoOptimize</h2>
              <p>{guidance.About}</p>
              <div className="support-card">
                <strong>Support Zenthralix-Lab</strong>
                <span>
                  Your support helps maintain public releases, update verification, local AI integration,
                  Windows/Linux safety research, and the infrastructure behind NeoOptimize development.
                </span>
                <code>neooptimizeofficial@gmail.com</code>
              </div>
              <div className="support-links" aria-label="Support links">
                <button onClick={() => openExternal('mailto:neooptimizeofficial@gmail.com')}>Email</button>
                <button onClick={() => openExternal('https://buymeacoffee.com/nol.eight')}>Buy Me a Coffee</button>
                <button onClick={() => openExternal('https://saweria.co/dtechtive')}>Saweria</button>
                <button onClick={() => openExternal('https://ik.imagekit.io/dtechtive/Dana')}>Dana</button>
              </div>
            </div>
          )}
        </section>

        <footer className="status-bar">{busyAction ? `${busyAction} task queued. Buttons are throttled.` : status}</footer>
      </main>
    </div>
  )
}

function MiniTray({
  chatLog,
  question,
  setQuestion,
  voiceListening,
  askNeo,
  startVoiceCommand,
  clearChat,
  hideMiniTray,
  showMainWindow,
  exitApp
}) {
  return (
    <div className="mini-app">
      <header className="mini-header">
        <div>
          <strong><Bot size={16} /> NEO Mini</strong>
          <span>Neural Execution Operator</span>
        </div>
        <button className="icon-button" onClick={hideMiniTray} title="Hide NEO Mini"><X size={16} /></button>
      </header>

      <div className="mini-toolbar">
        <button className="secondary" onClick={showMainWindow}>Open NeoOptimize</button>
        <button className="secondary" onClick={clearChat}>Clear Chat</button>
        <button className="secondary" onClick={exitApp}>Exit</button>
      </div>

      <div className="mini-prompts" aria-label="NEO Mini quick prompts">
        {[
          ['Status', 'status'],
          ['Scan', 'scan anomaly system'],
          ['Code Fix', 'saran code perbaikan dengan corpus'],
          ['Local AI', 'setup ollama neo-light neo-latest']
        ].map(([label, prompt]) => (
          <button key={label} className="prompt-chip" onClick={() => askNeo(prompt)}>
            {label}
          </button>
        ))}
      </div>

      <div className="chat-body mini-chat">
        {chatLog.length === 0 && (
          <div className="chat-empty">Conversation history is cleared automatically after 30 minutes.</div>
        )}
        {chatLog.map((item) => (
          <div key={item.id} className={`chat-line ${item.role} ${item.mode || ''}`}>
            <span className="chat-meta">{chatLabel(item)} · {formatChatTime(item.ts)}</span>
            <span className="chat-text">{item.text}</span>
          </div>
        ))}
      </div>

      <div className="mini-input">
        <input
          value={question}
          onChange={(event) => setQuestion(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter') {
              event.preventDefault()
              askNeo()
            }
          }}
          placeholder="Ask NEO..."
          autoFocus
        />
        <button className="primary" onClick={() => askNeo()}>Send</button>
        <button
          className={`secondary voice-button ${voiceListening ? 'listening' : ''}`}
          onClick={startVoiceCommand}
          aria-label={voiceListening ? 'Voice command listening' : 'Start voice command'}
          title={voiceListening ? 'Voice command listening' : 'Start voice command'}
        >
          <Mic size={15} />
        </button>
      </div>
    </div>
  )
}

function Metric({ label, value, note, icon: Icon }) {
  return (
    <div className="metric">
      <div className="metric-label"><Icon size={14} /> {label}</div>
      <div className="metric-value">{value}</div>
      <div className="metric-note">{note}</div>
    </div>
  )
}

function HealthPanel({ health, runAction }) {
  return (
    <div className="panel health">
      <div className="ring" style={{ '--score': `${health}%` }}>
        <div>
          <div className="score">{health}</div>
          <div className="muted">/100</div>
        </div>
      </div>
      <h3>Health Score</h3>
      <button className="link-button" onClick={() => runAction('AIPlan')}>Run AI Doctor check</button>
    </div>
  )
}

function DoctorPanel({ platformName }) {
  return (
    <div className="panel doctor-panel">
      <h2 className="panel-title">NEO AI Doctor</h2>
      <h3>Recommended Care Plan</h3>
      <div className="muted">Risk-ranked suggestions from local telemetry and packaged corpus.</div>
      <div className="care-list">
        <div className="care-item"><strong>Run Safe Cleanup</strong><span className="muted">Low risk temp/cache cleanup.</span></div>
        <div className="care-item"><strong>Review Startup Load</strong><span className="muted">Measure boot impact before disabling entries.</span></div>
        <div className="care-item"><strong>{platformName} Repair Scan</strong><span className="muted">Use approval gates before repair actions.</span></div>
      </div>
    </div>
  )
}

function TelemetryPanel({ telemetryPath, wide = false }) {
  return (
    <div className={`panel telemetry-panel ${wide ? 'wide' : ''}`}>
      <h2 className="panel-title">Live Telemetry</h2>
      <svg viewBox="0 0 300 128" className="telemetry-chart" aria-label="CPU telemetry">
        <g className="chart-grid">
          <line x1="0" y1="32" x2="300" y2="32" />
          <line x1="0" y1="64" x2="300" y2="64" />
          <line x1="0" y1="96" x2="300" y2="96" />
        </g>
        <polyline points={telemetryPath} />
      </svg>
      <div className="legend">
        <span>CPU</span>
        <span>RAM</span>
        <span>DISK</span>
        <span>NET</span>
      </div>
    </div>
  )
}

function InfoRow({ label, value }) {
  return (
    <div className="info-row">
      <span>{label}</span>
      <strong>{value || '-'}</strong>
    </div>
  )
}
